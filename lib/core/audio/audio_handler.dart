import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';
import '../../data/models/article.dart';
import '../theme/app_colors.dart';
import 'car_catalog.dart';
import 'car_media.dart';

/// Singleton inicializado en main() antes de runApp().
late final UnicaAudioHandler audioHandler;

Future<void> initAudioService() async {
  if (kIsWeb) {
    // En web AudioService.init no conecta con ningún SO; creamos el handler
    // directamente para que el resto del código pueda usarlo sin guardas.
    audioHandler = UnicaAudioHandler();
    return;
  }
  audioHandler = await AudioService.init(
    builder: UnicaAudioHandler.new,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.neuscampos.radioapp.channel',
      androidNotificationChannelName: 'RadioApp',
      // androidNotificationOngoing debe ser false cuando androidStopForegroundOnPause
      // también es false: audio_service lanza AssertionError con la combinación.
      androidNotificationOngoing: false,
      // false = el servicio foreground sobrevive interrupciones breves (llamada,
      // notificación). Con true Android puede matar el proceso al pausar.
      androidStopForegroundOnPause: false,
      notificationColor: AppColors.brand,
      // Podcast: los saltos son de ±30 s (el default del template es 10 s).
      // Los usa SeekHandler.rewind()/fastForward() → seek().
      fastForwardInterval: const Duration(seconds: 30),
      rewindInterval: const Duration(seconds: 30),
      // Android Auto: estos hints son los DEFAULTS de TODO el árbol (se aplican
      // por TIPO de ítem). Ambos en LISTA para que los episodios salgan como
      // lista compacta y no como tarjetas gigantes. La raíz solo tiene navegables
      // (se pintan como pestañas de todos modos) y el directo, que sí queremos
      // grande, lleva su propio override de cuadrícula en radioFolderMediaItem.
      androidBrowsableRootExtras: const {
        AndroidContentStyle.supportedKey: true,
        AndroidContentStyle.browsableHintKey:
            AndroidContentStyle.listItemHintValue,
        AndroidContentStyle.playableHintKey:
            AndroidContentStyle.listItemHintValue,
      },
    ),
  );
}

/// Handler de audio que gestiona la sesión de medios del SO.
/// RadioNotifier y PodcastNotifier comparten los AudioPlayer que viven aquí;
/// el handler actualiza title/artist/portada → la pantalla del coche lo lee
/// vía Bluetooth AVRCP (Android) / CarPlay + MPNowPlayingInfoCenter (iOS).
class UnicaAudioHandler extends BaseAudioHandler with SeekHandler {
  // Radio en directo: buffer de arranque acotado (~2 s) para bajar la latencia
  // al dar a play, MANTENIENDO automaticallyWaitsToMinimizeStalling=true (el
  // default) — es lo que da reproducción fiable y auto-recuperación tras un
  // corte en red móvil. Ponerlo en false (intento anterior) hacía que AVPlayer
  // "sonara" con el buffer vacío y desactivaba el reintento → tardaba, sonaba
  // mudo o no arrancaba. El podcast (bajo demanda) usa el buffer por defecto.
  final AudioPlayer radioPlayer = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      darwinLoadControl: DarwinLoadControl(
        preferredForwardBufferDuration: Duration(seconds: 2),
      ),
    ),
  );
  final AudioPlayer podcastPlayer = AudioPlayer();

  /// Catálogo de la biblioteca del coche (Android Auto). Inyectable para poder
  /// probar el sondeo del "ahora suena" sin tocar la red.
  final CarCatalog _catalog;

  // 'radio' | 'podcast' | '' — determina qué player controlan los botones del coche
  String _active = '';

  // true mientras cambiamos de episodio (skip): silencia el estado 'idle'
  // transitorio de setAudioSource para que Android Auto no salga de la pantalla
  // de reproducción a la lista.
  bool _switchingEpisode = false;

  /// Lo registra RadioNotifier: se invoca cuando el SO (notificación / coche /
  /// Bluetooth) para la sesión de radio, para que el Notifier sincronice su
  /// estado interno (volver a polling lento y reflejar el estado parado).
  void Function()? onRadioStoppedExternally;

  /// Lo registra PodcastNotifier: el coche tomó el control y paró el episodio
  /// (arrancó la radio). Además de reflejar el estado parado, el Notifier CANCELA
  /// su carga en vuelo (token generacional): un `setAudioSource` lanzado desde la
  /// app acabaría sonando ENCIMA de la radio que acaba de pedir el coche.
  void Function()? onPodcastStoppedExternally;

  /// Los registra la UI (Radio/PodcastNotifier) para reflejar en pantalla lo que
  /// se arranca DESDE EL COCHE. En arranque en frío no hay UI y quedan a null:
  /// la reproducción funciona igual (por eso el handler no depende de ellos).
  void Function()? onRadioStartedExternally;
  void Function(PodcastEpisode ep)? onPodcastStartedExternally;

  /// Callbacks de vídeo: el SO pide play/pause desde la pantalla de bloqueo.
  void Function()? onVideoPlay;
  void Function()? onVideoPause;

  UnicaAudioHandler({CarCatalog? catalog})
    : _catalog = catalog ?? CarCatalog() {
    radioPlayer.playerStateStream.listen((ps) {
      if (_active == 'radio') _syncState(ps, radioPlayer);
    });
    podcastPlayer.playerStateStream.listen((ps) {
      if (_active == 'podcast' && !_switchingEpisode) {
        _syncState(ps, podcastPlayer);
      }
    });
  }

  void _syncState(PlayerState ps, AudioPlayer p) {
    final playing = ps.playing;
    final isPodcast = _active == 'podcast';
    // L22: refleja también completed/idle (antes todo lo que no era buffering
    // caía a "ready", dejando un episodio terminado como si siguiera activo).
    final processing = switch (ps.processingState) {
      ProcessingState.loading ||
      ProcessingState.buffering => AudioProcessingState.loading,
      ProcessingState.completed => AudioProcessingState.completed,
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.ready => AudioProcessingState.ready,
    };
    playbackState.add(
      playbackState.value.copyWith(
        playing: playing,
        processingState: processing,
        // Podcast: ⏮ episodio anterior · ⏯ · ⏭ episodio siguiente. Solo 3 botones
        // a propósito: Android Auto tiene ~4 huecos, así que con más (⏪/⏩) los
        // solapa, mete unos en el menú ⋮ y ⏪ se confunde con ⏮ (los dos apuntan a
        // la izquierda). Para avanzar/retroceder DENTRO del episodio está la barra,
        // que se arrastra con MediaAction.seek. Radio (directo): solo ⏯ y ⏹.
        controls: [
          if (isPodcast) MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          if (isPodcast) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        // audio_service NO anuncia ACTION_SEEK_TO ni los SKIP por su cuenta (lo
        // deja a systemActions): sin seek la barra no se arrastra; sin skip no
        // salta de episodio. La radio es DIRECTO → sin seek ni skip.
        systemActions: isPodcast
            ? const {
                MediaAction.seek,
                MediaAction.skipToNext,
                MediaAction.skipToPrevious,
              }
            : const <MediaAction>{},
        // Vista compacta (notificación del móvil): ⏮ ⏯ ⏭ (índices 0, 1, 2).
        androidCompactActionIndices: isPodcast ? const [0, 1, 2] : const [0],
        // La radio es DIRECTO: posición -1 (PLAYBACK_POSITION_UNKNOWN) para que el
        // coche NO pinte contador ni barra. Android IGNORA MediaItem.isLive (0 usos
        // en el código nativo de audio_service): lo que de verdad quita el contador
        // es que no haya posición conocida. Solo el podcast lleva posición real.
        updatePosition: _active == 'radio'
            ? const Duration(milliseconds: -1)
            : p.position,
      ),
    );
  }

  /// El coche pidió reproducir algo y la fuente falló (mount caído, sin red, URL
  /// mala). Sin esto no se emite NINGÚN estado: la pantalla del coche se queda
  /// con el spinner puesto y el usuario no recibe ninguna señal del fallo.
  void _emitCarPlaybackError() {
    _active = '';
    _stopNowPlayingPolling();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.error,
        controls: const [MediaControl.play],
        systemActions: const <MediaAction>{},
        androidCompactActionIndices: const [0],
        updatePosition: Duration.zero,
      ),
    );
  }

  // ── Actualización de metadatos ───────────────────────────────────────────────

  /// Llama RadioNotifier al empezar a reproducir el stream.
  void setRadioActive(String title, String artist, {String? artworkUri}) {
    _active = 'radio';
    _setMeta(
      id: 'radio',
      title: title.isEmpty ? 'RadioApp' : title,
      artist: artist,
      artworkUri: artworkUri,
      isLive: true,
    );
    // El playerStateStream ya disparó con _active=='' y fue ignorado.
    // Forzamos la sincronización ahora para que audio_service arranque
    // el foreground service y muestre la notificación/pantalla de bloqueo.
    _syncState(radioPlayer.playerState, radioPlayer);
    // Único punto de arranque del sondeo del "ahora suena". Si la app está viva,
    // el guard `_uiOwnsNowPlaying` lo deja en no-op (sonda RadioNotifier).
    _startNowPlayingPolling();
  }

  /// Llama RadioNotifier cada vez que cambia la canción (polling / ICY).
  void updateRadioNowPlaying(
    String title,
    String artist, {
    String? artworkUri,
  }) {
    if (_active != 'radio') return;
    // isLive también aquí: cada _setMeta reconstruye el MediaItem entero, así que
    // sin esto el cambio de canción reintroduciría el contador y la barra.
    _setMeta(
      id: 'radio',
      title: title.isEmpty ? 'RadioApp' : title,
      artist: artist,
      artworkUri: artworkUri,
      isLive: true,
    );
  }

  /// Llama PodcastNotifier al empezar un episodio.
  void setPodcastActive({
    required String id,
    required String title,
    String? artworkUri,
    Duration? duration,
  }) {
    _active = 'podcast';
    _stopNowPlayingPolling(); // la radio dejó de estar activa
    _setMeta(id: id, title: title, artworkUri: artworkUri, duration: duration);
    _syncState(podcastPlayer.playerState, podcastPlayer);
  }

  /// Activa la sesión de vídeo en directo: la pantalla de bloqueo muestra
  /// el título y los controles play/pausa, igual que con el stream de audio.
  void setVideoActive(String title) {
    _active = 'video';
    _stopNowPlayingPolling(); // la radio dejó de estar activa
    _setMeta(id: 'video', title: title, artist: 'In diretta');
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
        controls: [MediaControl.pause, MediaControl.stop],
        androidCompactActionIndices: const [0],
        updatePosition: Duration.zero,
      ),
    );
  }

  /// Marca la sesión como inactiva (radio parada / podcast parado).
  void clearActive() {
    _active = '';
    _stopNowPlayingPolling();
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle),
    );
  }

  void _setMeta({
    required String id,
    required String title,
    String artist = '',
    String? artworkUri,
    Duration? duration,
    bool isLive = false,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        artUri: artworkUri != null ? Uri.tryParse(artworkUri) : null,
        duration: duration,
        // La radio es DIRECTO: con isLive el coche no pinta contador ni barra de
        // posición. El podcast lo deja en false (tiene duración y barra con ±30 s).
        isLive: isLive,
      ),
    );
  }

  // ── "Ahora suena" de la radio EN EL COCHE ────────────────────────────────────
  // Con la app abierta, RadioNotifier ya sonda (20 s) y nos empuja la canción con
  // updateRadioNowPlaying(). Pero Android Auto arranca el servicio EN FRÍO (sin
  // UI, sin Riverpod): ahí no sonda nadie y el coche se queda con "RadioApp" y
  // sin carátula. Este timer SOLO cubre ese hueco.
  Timer? _nowPlayingTimer;
  bool _nowPlayingBusy = false;

  /// true mientras RadioNotifier esté vivo: es ÉL quien sonda. Evita el DOBLE
  /// sondeo. Lo pone la UI (build → true, onDispose → false).
  bool _uiOwnsNowPlaying = false;

  void setUiOwnsNowPlaying(bool value) {
    if (_uiOwnsNowPlaying == value) return;
    _uiOwnsNowPlaying = value;
    if (value) {
      _stopNowPlayingPolling(); // la UI toma el relevo
    } else if (_active == 'radio') {
      _startNowPlayingPolling(); // la UI murió y la radio sigue sonando
    }
  }

  /// Idempotente: ni arranca un segundo timer ni pisa el sondeo de la UI.
  void _startNowPlayingPolling() {
    if (_uiOwnsNowPlaying || _nowPlayingTimer != null) return;
    unawaited(_refreshNowPlaying()); // primer tick YA (no esperar 20 s)
    _nowPlayingTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshNowPlaying()),
    );
  }

  void _stopNowPlayingPolling() {
    _nowPlayingTimer?.cancel();
    _nowPlayingTimer = null;
  }

  Future<void> _refreshNowPlaying() async {
    if (_active != 'radio') {
      _stopNowPlayingPolling();
      return;
    }
    if (_nowPlayingBusy) return; // un tick lento no encadena peticiones
    _nowPlayingBusy = true;
    try {
      final t = await _catalog.nowPlaying();
      // Durante la red pudo entrar la UI (que ya sonda) o pararse la radio:
      // descartamos en vez de pisar la sesión con datos que ya no tocan.
      if (t == null || t.title.isEmpty) return;
      if (_active != 'radio' || _uiOwnsNowPlaying) return;
      updateRadioNowPlaying(
        t.title,
        t.artist,
        artworkUri: t.artworkUrl ?? kRadioLogoUrl,
      );
    } finally {
      _nowPlayingBusy = false;
    }
  }

  // ── Controles del coche / auriculares ────────────────────────────────────────

  @override
  Future<void> play() async {
    if (_active == 'radio') await radioPlayer.play();
    if (_active == 'podcast') await podcastPlayer.play();
    if (_active == 'video') onVideoPlay?.call();
  }

  @override
  Future<void> pause() async {
    // El stream de radio no se puede pausar, solo parar.
    if (_active == 'radio') {
      await radioPlayer.stop();
      clearActive();
      onRadioStoppedExternally?.call(); // M9: sincroniza el RadioNotifier
      return;
    }
    if (_active == 'podcast') await podcastPlayer.pause();
    if (_active == 'video') {
      onVideoPause?.call();
      clearActive();
    }
  }

  @override
  Future<void> stop() async {
    final wasRadio = _active == 'radio';
    final wasVideo = _active == 'video';
    await radioPlayer.stop();
    await podcastPlayer.stop();
    clearActive();
    if (wasRadio) onRadioStoppedExternally?.call(); // M9
    if (wasVideo) onVideoPause?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_active == 'podcast') await podcastPlayer.seek(position);
  }

  @override
  Future<void> skipToNext() => _skipEpisode(1);

  @override
  Future<void> skipToPrevious() => _skipEpisode(-1);

  /// Salta al episodio siguiente (+1) o anterior (-1) en la lista del coche. La
  /// lista va de más nuevo a más viejo (skipToNext → el anterior en el tiempo).
  /// Sin lista, si el episodio actual no está en ella, o en los extremos → no
  /// hace nada (nunca deja la reproducción a medias).
  Future<void> _skipEpisode(int delta) async {
    if (_active != 'podcast') return;
    final curId = episodeIdFrom(mediaItem.value?.id ?? '');
    if (curId == null) return;
    final eps = await _catalog.episodes();
    final i = eps.indexWhere((e) => e.id == curId);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= eps.length) return;
    await _playEpisodeFromCar(eps[j]);
  }

  // ── Biblioteca del coche (Android Auto) ──────────────────────────────────────

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    // Raíz: pestaña Radio + pestaña de podcasts. Son 2 navegables CONSTANTES →
    // se devuelven sin tocar la red (solo el idioma, que sale de prefs cacheadas,
    // no del feed). Bajar el feed aquí dejaba la pantalla del coche con el
    // spinner varios segundos antes de poder abrir la pestaña Radio, que no
    // depende del feed para nada.
    if (parentMediaId == AudioService.browsableRootId) {
      // Los nombres de las secciones siguen el idioma elegido, leído de prefs
      // (sin Riverpod: en arranque en frío desde el coche no hay providers).
      final s = await _catalog.strings();
      return rootChildren(radioTitle: s.tabRadio, podcastsTitle: s.carPodcasts);
    }
    // Dentro de la pestaña Radio: solo el directo (el feed no pinta aquí).
    if (parentMediaId == CarIds.radioFolder) {
      return radioChildren(title: (await _catalog.strings()).tabRadio);
    }
    if (parentMediaId == CarIds.podcasts) {
      final eps = await _catalog.episodes();
      return eps.map(episodeMediaItem).toList();
    }
    return const <MediaItem>[];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    // Algunos hosts llaman a onLoadItem sobre el nodo navegable de la pestaña.
    if (mediaId == CarIds.radioFolder) {
      return radioFolderMediaItem(title: (await _catalog.strings()).tabRadio);
    }
    if (mediaId == CarIds.radio) {
      return radioMediaItem(title: (await _catalog.strings()).tabRadio);
    }
    final epId = episodeIdFrom(mediaId);
    if (epId == null) return null;
    final ep = await _catalog.episodeById(epId);
    return ep == null ? null : episodeMediaItem(ep);
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    if (mediaId == CarIds.radio) {
      await _playRadioFromCar();
      return;
    }
    final epId = episodeIdFrom(mediaId);
    if (epId == null) return;
    final ep = await _catalog.episodeById(epId);
    if (ep != null) await _playEpisodeFromCar(ep);
  }

  /// Radio en directo desde el coche, con la calidad que el usuario tenga
  /// elegida. Exclusión: primero paramos el podcast (y el vídeo, que lleva su
  /// propio audio: en el coche SOLO hay audio).
  Future<void> _playRadioFromCar() async {
    if (_active == 'video') onVideoPause?.call();
    await podcastPlayer.stop();
    // El stop() NO basta: si la app estaba cargando un episodio, su
    // `setAudioSource` aún no había llegado al player y seguiría hasta play().
    onPodcastStoppedExternally?.call();
    try {
      final url = await _catalog.radioUrl();
      // Timeout como en la UI: si el mount conecta pero se cuelga, no dejamos el
      // "cargando" infinito en la pantalla del coche.
      await radioPlayer
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      _emitCarPlaybackError();
      return;
    }
    // setRadioActive marca la sesión 'radio' → arranca el servicio en primer
    // plano y la notificación/pantalla del coche, y ARRANCA el sondeo del "ahora
    // suena". En arranque en frío no hay RadioNotifier vivo (ni polling ni ICY),
    // así que el logo fijo evita el hueco gris hasta que el primer tick del
    // sondeo lo sustituya por la canción + su carátula real (~1 RTT).
    setRadioActive('RadioApp', '', artworkUri: kRadioLogoUrl);
    unawaited(radioPlayer.play()); // play() solo completa al terminar
    onRadioStartedExternally?.call();
  }

  /// Episodio desde el coche. La duración se la damos al coche cuando el player
  /// ya la conoce (tras cargar la fuente) → ahí aparece la barra de posición.
  Future<void> _playEpisodeFromCar(PodcastEpisode ep) async {
    final url = ep.audioUrl;
    if (url == null || url.isEmpty) return;
    // El vídeo en directo lleva su propio audio: si no lo paramos, sonaría
    // ENCIMA del episodio (en el coche solo hay audio).
    if (_active == 'video') onVideoPause?.call();
    await radioPlayer.stop();
    onRadioStoppedExternally?.call(); // la UI de radio deja de decir "sonando"
    // Silenciamos el 'idle' transitorio del cambio de fuente (ver _switchingEpisode):
    // si no, al saltar de episodio Android Auto sale del reproductor a la lista.
    _switchingEpisode = true;
    Duration? duration;
    try {
      duration = await podcastPlayer
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      _switchingEpisode = false;
      _emitCarPlaybackError();
      return;
    }
    setPodcastActive(
      id: CarIds.episode(ep.id),
      title: ep.title,
      artworkUri: ep.imageUrl,
      duration: duration,
    );
    unawaited(podcastPlayer.play());
    onPodcastStartedExternally?.call(ep);
    _switchingEpisode = false;
  }
}
