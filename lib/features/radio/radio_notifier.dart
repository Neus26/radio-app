import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../podcast/podcast_notifier.dart';
import '../../core/analytics/analytics.dart';
import '../../core/audio/audio_handler.dart';
import '../../core/audio/car_media.dart' show kRadioLogoUrl;
import '../../core/audio_quality.dart';
import '../../core/video_quality.dart';
import 'playback_decision.dart';

// El audio sale del Icecast (mount según la calidad — ver core/audio_quality.dart).
// status/artwork y las listas de la regia se piden por XHR y NO mandan CORS → en la
// PREVIEW WEB van por el proxy del server de preview (tool/preview-server.py);
// en el MÓVIL real van directos.
String get _statusUrl => kIsWeb
    ? Uri.base.resolve('/rcast-status').toString()
    : 'https://status.rcast.net/66954';
String get _artworkUrl => kIsWeb
    ? Uri.base.resolve('/rcast-artwork').toString()
    : 'https://artwork.rcast.net/66954';
// Listas de la regia: historial real ("Sonó antes") y próximas ("A continuación").
String get _lastSongsUrl => kIsWeb
    ? Uri.base.resolve('/regia-last').toString()
    : 'https://www.unicaradio.it/regia/lastsongs.html';
String get _nextSongsUrl => kIsWeb
    ? Uri.base.resolve('/regia-next').toString()
    : 'https://www.unicaradio.it/regia/nextsongs.html';

class NowPlaying {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? time; // HH:MM en historial/próximas; null para "ahora"
  const NowPlaying({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.time,
  });
  static const empty = NowPlaying(title: '—', artist: '');

  bool get isEmpty => title == '—';

  @override
  bool operator ==(Object other) =>
      other is NowPlaying && other.title == title && other.artist == artist;

  @override
  int get hashCode => Object.hash(title, artist);
}

class RadioState {
  final bool playing;
  final bool loading;
  final bool hasError;
  final double volume;
  final NowPlaying nowPlaying;
  final List<NowPlaying> history; // "Sonó antes" (lastsongs)
  final List<NowPlaying> upNext; // "A continuación" (nextsongs)
  final bool videoMode; // true = modo vídeo HLS
  final int videoToken; // incrementa al recargar/parar el WebView del vídeo
  final bool videoAutoSwitchedToLow; // true al hacer fallback automático a 512k
  final bool videoFullscreen; // true mientras el vídeo se ve a pantalla completa

  const RadioState({
    this.playing = false,
    this.loading = false,
    this.hasError = false,
    this.volume = 0.9,
    this.nowPlaying = NowPlaying.empty,
    this.history = const [],
    this.upNext = const [],
    this.videoMode = false,
    this.videoToken = 0,
    this.videoAutoSwitchedToLow = false,
    this.videoFullscreen = false,
  });

  RadioState copyWith({
    bool? playing,
    bool? loading,
    bool? hasError,
    double? volume,
    NowPlaying? nowPlaying,
    List<NowPlaying>? history,
    List<NowPlaying>? upNext,
    bool? videoMode,
    int? videoToken,
    bool? videoAutoSwitchedToLow,
    bool? videoFullscreen,
  }) => RadioState(
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    hasError: hasError ?? this.hasError,
    volume: volume ?? this.volume,
    nowPlaying: nowPlaying ?? this.nowPlaying,
    history: history ?? this.history,
    upNext: upNext ?? this.upNext,
    videoMode: videoMode ?? this.videoMode,
    videoToken: videoToken ?? this.videoToken,
    videoAutoSwitchedToLow: videoAutoSwitchedToLow ?? this.videoAutoSwitchedToLow,
    videoFullscreen: videoFullscreen ?? this.videoFullscreen,
  );
}

// Parseo de las tablas HTML de la regia: filas
// <th>HH:MM</th><th>ARTISTA - TÍTULO</th>. La fila "IN ONDA" no casa (su primera
// celda no es una hora), así que se descarta sola.
final _songRowRe = RegExp(
  r'<th[^>]*>\s*(\d{1,2}:\d{2})\s*</th>\s*<th[^>]*>\s*([^<]+?)\s*</th>',
  caseSensitive: false,
);

String _decodeEntities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

class RadioNotifier extends Notifier<RadioState> with WidgetsBindingObserver {
  // El AudioPlayer vive en el handler para que el SO tenga acceso a él.
  AudioPlayer get _player => audioHandler.radioPlayer;

  // Dio propio para rcast.net / regia — sin base URL de WordPress
  late final Dio _rcastDio;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<IcyMetadata?>? _icySub;
  Timer? _pollTimer;

  // ── Vídeo (WebView del player HTML de Wowza) ─────────────────────────────────
  // El directo se ve con el player HTML embebido (la MISMA URL que abre el
  // navegador y que sí funciona): gestiona la sesión HLS (?session=...) él solo,
  // cosa que ExoPlayer no sostenía (moría en segundos al caducar/rotar la sesión).
  // SOLO para verlo DENTRO de la app; en segundo plano se pasa a audio de la
  // radio (ver _startBackgroundAudio) → pantalla de bloqueo = solo audio.
  // Parámetros del player HTML de Wowza (todos default true): quitamos SUS
  // controles (ya tenemos el play/pausa nuestro debajo), arrancamos CON sonido
  // (setMediaPlaybackRequiresUserGesture(false) permite el autoplay con audio) y
  // sin botón de PiP en el player.
  // JS que detecta errores del <video> del player HTML y avisa para hacer
  // fallback automático a la calidad baja. Sondea el DOM cada 500 ms hasta 10 s
  // porque el player Wowza/MediaMTX carga el <video> de forma asíncrona.
  static const _videoErrorListenerJs = '''
(function(){
  var sent=false;
  function attach(){
    var v=document.querySelector('video');
    if(!v)return false;
    v.addEventListener('error',function(){
      if(!sent){sent=true;VideoFallback.postMessage('error');}
    });
    return true;
  }
  var n=0,id=setInterval(function(){if(attach()||++n>20)clearInterval(id);},500);
})();
''';
  WebViewController? _webController;

  /// Expuesto para que radio_page monte el WebViewWidget (lo observa via videoToken).
  WebViewController? get webController => _webController;
  // Token de generación: serializa las transiciones del _player (play/stop/
  // reconnect/stopForOther). Cada transición lo incrementa; las anteriores se
  // descartan tras sus await en vez de pisar el estado con datos obsoletos.
  int _gen = 0;
  // Generación de _fetchStatus: si una lectura más nueva del "ahora suena"
  // adelanta a la nuestra durante el await de la carátula, descartamos la
  // vieja para no pisar la canción reciente con datos obsoletos.
  int _statusGen = 0;

  // ── Continuidad de audio del modo vídeo (2A) ─────────────────────────────────
  // El usuario quiere el vídeo sonando (true tras _startVideo OK).
  bool _videoIntendedPlaying = false;
  // Ya hicimos el cambiazo a audio de fondo (vídeo pausado, _player sonando).
  bool _backgroundAudioActive = false;
  // Último estado del ciclo de vida (la app arranca en primer plano).
  AppLifecycleState _appState = AppLifecycleState.resumed;

  @override
  RadioState build() {
    _rcastDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    unawaited(_player.setVolume(0.9));
    // Mientras la UI viva es ELLA quien sonda el "ahora suena": el handler no debe
    // sondear en paralelo (evita el doble sondeo). En arranque en frío desde el
    // coche no hay UI y el handler sonda solo.
    audioHandler.setUiOwnsNowPlaying(true);
    _listenPlayerState();
    _listenIcy();
    // Cambiar la calidad mientras suena la radio → reconectar al nuevo mount.
    ref.listen(audioQualityProvider, (prev, next) {
      if (prev != null && prev != next && (state.playing || state.loading)) {
        _reconnect(next.url);
      }
    });
    // Cambiar la calidad de vídeo mientras se reproduce → recargar el player.
    ref.listen(videoQualityProvider, (prev, next) {
      if (prev == null || prev == next) return;
      if (state.videoMode && _videoIntendedPlaying && !_backgroundAudioActive) {
        unawaited(_webController?.loadRequest(Uri.parse(next.playerUrl)));
      }
    });
    // Si el SO (notificación/coche/Bluetooth) para la radio, sincronizamos el
    // Notifier: volvemos a polling lento y reflejamos el estado parado, en vez
    // de seguir sondeando rápido con la sesión colgada.
    audioHandler.onRadioStoppedExternally = () {
      // Invalida cualquier carga de radio EN VUELO (playPause/_reconnect miran
      // `if (gen != _gen) return;`). Si no, al tocar un episodio en el coche una
      // carga a medias de la app terminaría reproduciendo la radio ENCIMA.
      ++_gen;
      _backgroundAudioActive = false;
      _videoIntendedPlaying = false;
      _startIdlePolling();
      if (state.playing || state.loading) {
        state = state.copyWith(playing: false, loading: false);
      }
    };
    // El coche (Android Auto) arrancó la radio: lo reflejamos en la UI. Si
    // estábamos en modo vídeo lo cerramos (en el coche solo hay audio).
    audioHandler.onRadioStartedExternally = () {
      _videoIntendedPlaying = false;
      _backgroundAudioActive = false;
      unawaited(_webController?.loadRequest(Uri.parse('about:blank')));
      _startPolling(); // sondeo rápido (20 s): está sonando de verdad
      state = state.copyWith(
        playing: true,
        loading: false,
        hasError: false,
        videoMode: false,
        videoToken: state.videoToken + 1,
      );
    };
    // Observador del ciclo de vida: al ir a segundo plano / apagar pantalla se
    // decide si hay que pasar al audio de fondo (ver _evaluatePlayback).
    WidgetsBinding.instance.addObserver(this);
    // Fetch inmediato + polling lento aunque no se esté reproduciendo: así el
    // "Sonó antes" y "A continuación" salen llenos desde que se abre la app.
    _startIdlePolling();
    ref.onDispose(() {
      // La UI muere: si la radio sigue sonando (arrancada desde el coche), el
      // handler retoma el sondeo del "ahora suena".
      audioHandler.setUiOwnsNowPlaying(false);
      WidgetsBinding.instance.removeObserver(this);
      _stateSub?.cancel();
      _icySub?.cancel();
      _pollTimer?.cancel();
      unawaited(_webController?.loadRequest(Uri.parse('about:blank')));
      // NO dispose del player — lo gestiona el handler
      _rcastDio.close();
    });
    return const RadioState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nota: 'state' aquí es el AppLifecycleState del parámetro (no el del
    // Notifier); en este método no usamos el estado del Notifier.
    _appState = state;
    _evaluatePlayback();
  }

  void _listenPlayerState() {
    _stateSub = _player.playerStateStream.listen(
      (ps) {
        // Un stream en directo puede quedarse en "buffering" aunque ya esté sonando.
        // Solo mostramos spinner durante la conexión inicial (antes de que empiece a sonar).
        final isLoading =
            !ps.playing &&
            (ps.processingState == ProcessingState.loading ||
                ps.processingState == ProcessingState.buffering);
        state = state.copyWith(loading: isLoading, playing: ps.playing);
      },
      onError: (_) {
        // El player entró en estado de error: pararlo, volver a polling lento y avisar
        unawaited(_player.stop());
        audioHandler.clearActive();
        _startIdlePolling();
        state = state.copyWith(loading: false, playing: false, hasError: true);
      },
    );
  }

  // ICY metadata — solo funciona en móvil (no en web)
  void _listenIcy() {
    try {
      _icySub = _player.icyMetadataStream.listen(
        (meta) {
          final raw = (meta?.info?.title ?? '').trim();
          if (raw.isEmpty) return;
          _updateNowPlaying(_parseRaw(raw));
        },
        onError: (_) {}, // ICY lanza asíncronamente en web
      );
    } catch (_) {
      // icyMetadataStream puede lanzar síncronamente en web
    }
  }

  // Un "tick" de sondeo: canción actual + listas de la regia.
  void _poll() {
    _fetchStatus();
    _fetchSongLists();
  }

  // Polling rápido (20 s) mientras se reproduce
  void _startPolling() {
    _pollTimer?.cancel();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
  }

  // Polling lento (60 s) en idle — "now playing" e historial no quedan obsoletos
  void _startIdlePolling() {
    _pollTimer?.cancel();
    _poll();
    _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) => _poll());
  }

  Future<void> _fetchStatus() async {
    try {
      final res = await _rcastDio.get<dynamic>(_statusUrl);
      final data = res.data;
      if (data == null) return;

      String song = '';
      String artist = '';
      String title = '';

      if (data is Map) {
        // Formato Icecast estándar: {"icestats": {"source": {"title": "..."}}}
        final icestats = data['icestats'];
        if (icestats is Map) {
          final source = icestats['source'];
          final Map<String, dynamic>? src = source is List
              ? (source.isNotEmpty
                    ? source.first as Map<String, dynamic>?
                    : null)
              : (source is Map ? source as Map<String, dynamic> : null);
          if (src != null) {
            title = (src['title'] ?? '').toString().trim();
            artist = (src['artist'] ?? src['server_name'] ?? '')
                .toString()
                .trim();
          }
        }

        // Formato directo rcast: {"song": "...", "artist": "...", "title": "..."}
        if (title.isEmpty) {
          song = (data['song'] ?? '').toString().trim();
          artist = (data['artist'] ?? artist).toString().trim();
          title = (data['title'] ?? '').toString().trim();
        }

        // Formato alternativo: {"current": "Artist - Title"}
        if (title.isEmpty && song.isEmpty) {
          song = (data['current'] ?? data['nowplaying'] ?? '')
              .toString()
              .trim();
        }
      } else if (data is String) {
        // rcast.net devuelve el track en TEXTO PLANO: "Artista - Título"
        song = data.trim();
      }

      final raw = title.isNotEmpty ? title : song;
      if (raw.isEmpty) return;

      final base = artist.isNotEmpty
          ? NowPlaying(title: raw, artist: artist)
          : _parseRaw(raw);

      // Si la canción no cambió Y ya tenemos carátula → nada que actualizar.
      if (base == state.nowPlaying && state.nowPlaying.artworkUrl != null) {
        if (state.hasError) state = state.copyWith(hasError: false);
        return;
      }

      // La red respondió → si había banner de error, lo quitamos ya.
      if (state.hasError) state = state.copyWith(hasError: false);

      // Esta lectura es ahora la más reciente. Si otra _fetchStatus la adelanta
      // mientras pedimos la carátula (await de abajo), la nuestra se descartará.
      final gen = ++_statusGen;

      // Carátula: artwork.rcast.net devuelve la URL de la imagen en texto plano.
      String? art;
      try {
        final ar = await _rcastDio.get<dynamic>(_artworkUrl);
        final u = (ar.data ?? '').toString().trim();
        if (u.startsWith('http')) art = u;
      } catch (e) {
        if (kDebugMode) debugPrint('radio artwork: $e');
      }

      // M7: la canción pudo cambiar durante el await de la carátula. Si una
      // lectura MÁS NUEVA nos adelantó, abandonamos para no pisarla con datos
      // viejos. Si seguimos siendo la última, escribimos la canción (avanza
      // aunque sea distinta de la que se mostraba) junto con su carátula.
      if (gen != _statusGen) return;

      _updateNowPlaying(
        NowPlaying(title: base.title, artist: base.artist, artworkUrl: art),
      );
    } catch (e) {
      // status falló — la ICY sigue funcionando en móvil
      if (kDebugMode) debugPrint('radio _fetchStatus: $e');
    }
  }

  // Historial real ("Sonó antes") y próximas ("A continuación") desde la regia.
  // Sustituye al antiguo historial local (que se sembraba con el único track
  // anterior de rcast y quedaba vacío hasta escuchar).
  Future<void> _fetchSongLists() async {
    // Cache-buster: Aruba cachea estas .html con un Last-Modified viejo y servía
    // una copia CONGELADA (horas atrás). Un parámetro único por petición fuerza
    // la versión fresca. En web el proxy de preview reenvía la query a Aruba.
    Map<String, dynamic> bust() => {'_': DateTime.now().millisecondsSinceEpoch};
    try {
      final r = await _rcastDio.get<dynamic>(
        _lastSongsUrl,
        queryParameters: bust(),
        options: Options(responseType: ResponseType.plain),
      );
      final raw = (r.data ?? '').toString();
      final list = _parseSongs(raw, max: 8);
      if (list.isNotEmpty) {
        state = state.copyWith(history: list);
      } else if (kDebugMode && raw.trim().isNotEmpty) {
        // L4: llegó HTML pero el regex no casó ninguna fila → posible cambio de
        // formato de la regia. Lo dejamos en logs para detectarlo (el historial
        // se conserva a propósito para no parpadear a vacío).
        debugPrint(
          'radio lastsongs: HTML recibido pero 0 filas parseadas '
          '(¿cambió el formato de la regia?)',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('radio lastsongs: $e');
    }
    try {
      final r = await _rcastDio.get<dynamic>(
        _nextSongsUrl,
        queryParameters: bust(),
        options: Options(responseType: ResponseType.plain),
      );
      state = state.copyWith(
        upNext: _parseSongs((r.data ?? '').toString(), max: 3),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('radio nextsongs: $e');
    }
  }

  List<NowPlaying> _parseSongs(String html, {required int max}) {
    final out = <NowPlaying>[];
    for (final m in _songRowRe.allMatches(html)) {
      final rawSong = _decodeEntities(m.group(2) ?? '').trim();
      if (rawSong.isEmpty) continue;
      final np = _parseRaw(rawSong);
      out.add(NowPlaying(title: np.title, artist: np.artist, time: m.group(1)));
      if (out.length >= max) break;
    }
    return out;
  }

  NowPlaying _parseRaw(String raw) {
    final sep = raw.indexOf(' - ');
    return sep > 0
        ? NowPlaying(
            artist: raw.substring(0, sep),
            title: raw.substring(sep + 3),
          )
        : NowPlaying(title: raw, artist: '');
  }

  void _updateNowPlaying(NowPlaying np) {
    final sameSong = np == state.nowPlaying;
    // No degradamos de "con carátula" a "sin carátula" en la misma canción: la
    // metadata ICY del móvil nunca trae carátula, así que conservamos la que ya
    // obtuvo _fetchStatus en vez de borrarla.
    final art =
        np.artworkUrl ?? (sameSong ? state.nowPlaying.artworkUrl : null);
    if (sameSong && art == state.nowPlaying.artworkUrl) return;
    final next = NowPlaying(
      title: np.title,
      artist: np.artist,
      artworkUrl: art,
      time: np.time,
    );
    state = state.copyWith(nowPlaying: next);
    // Actualizar la pantalla del coche con el nuevo track. Nunca mandamos
    // carátula nula: sin ella Android Auto pinta un cuadro gris → logo fijo.
    audioHandler.updateRadioNowPlaying(
      next.title,
      next.artist,
      artworkUri: next.artworkUrl ?? kRadioLogoUrl,
    );
  }

  // Envía a la sesión del coche el track actual. L24: si aún no se sabe qué
  // suena (nowPlaying vacío '—'), manda "RadioApp" como respaldo.
  void _pushRadioMeta() {
    final np = state.nowPlaying;
    audioHandler.setRadioActive(
      np.isEmpty ? 'RadioApp' : np.title,
      np.artist,
      // Nunca carátula nula → logo fijo si aún no hay carátula de la canción.
      artworkUri: np.artworkUrl ?? kRadioLogoUrl,
    );
  }

  Future<void> playPause() async {
    // Guard: evita llamadas concurrentes si ya se está cargando
    if (state.loading) return;
    final gen = ++_gen; // M1: serializa esta transición
    if (state.playing) {
      await _player.stop();
      if (gen != _gen) return;
      audioHandler.clearActive();
      _startIdlePolling();
      state = state.copyWith(playing: false, loading: false);
      Analytics.instance.log('radio_stop');
      return;
    }
    state = state.copyWith(loading: true, hasError: false);
    try {
      await ref.read(podcastPlayerProvider.notifier).pauseForOther();
      if (gen != _gen) return;
      await _player
          .setAudioSource(
            AudioSource.uri(Uri.parse(ref.read(audioQualityProvider).url)),
          )
          .timeout(const Duration(seconds: 30));
      if (gen != _gen) return;
      // play() NO se await: su Future solo completa cuando la reproduccion
      // TERMINA/para, y un stream en directo es infinito -> se colgaria y
      // saltaria el timeout a los 30s (error falso + coche/lockscreen sin
      // arrancar). El setAudioSource de arriba ya confirmo la conexion.
      unawaited(_player.play());
      // Notificar al handler qué está sonando para la pantalla del coche
      _pushRadioMeta();
      _startPolling();
      Analytics.instance.log('radio_play', {
        'quality': ref.read(audioQualityProvider).name,
      });
    } catch (_) {
      if (gen != _gen) return;
      state = state.copyWith(loading: false, hasError: true);
    }
  }

  /// Reconecta al mount actual (al cambiar de calidad mientras suena).
  Future<void> _reconnect(String url) async {
    final gen = ++_gen; // M1: serializa frente a play/stop/otros reconnect
    state = state.copyWith(loading: true, hasError: false);
    try {
      await _player
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (gen != _gen) return;
      unawaited(_player.play()); // no await: play() solo completa al terminar
      // Re-sincroniza la sesión del coche con el nuevo mount.
      _pushRadioMeta();
    } catch (_) {
      if (gen != _gen) return;
      // M8: limpiar como hace onError — parar, soltar la sesión y volver a
      // polling lento, en vez de quedarse sondeando rápido sin sonar.
      await _player.stop();
      audioHandler.clearActive();
      _startIdlePolling();
      state = state.copyWith(loading: false, hasError: true);
    }
  }

  /// Para el stream si está sonando. Lo llama el podcast al empezar a sonar,
  /// para que no se solapen los dos audios.
  Future<void> stopForOther() async {
    if (state.playing ||
        state.loading ||
        _backgroundAudioActive ||
        _videoIntendedPlaying) {
      ++_gen;
      if (state.videoMode) {
        await _stopVideo();
      } else {
        await _player.stop();
        audioHandler.clearActive();
        _startIdlePolling();
      }
      state = state.copyWith(playing: false, loading: false);
    }
  }

  /// Pull-to-refresh: re-pide el "ahora suena" + las listas de la regia.
  Future<void> refresh() async {
    await _fetchStatus();
    await _fetchSongLists();
  }

  Future<void> setVolume(double v) async {
    state = state.copyWith(volume: v);
    await _player.setVolume(v);
    // En modo vídeo, el volumen va al <video> del player HTML (vía JS).
    if (state.videoMode) {
      await _webController?.runJavaScript(_videoVolumeJs(v));
    }
  }

  /// JS que fija el volumen (0..1) del <video> del player HTML y lo desmutea.
  /// El `if(e)` evita fallar si aún no existe el elemento (p.ej. en about:blank).
  String _videoVolumeJs(double v) =>
      "var e=document.querySelector('video');if(e){e.volume=$v;e.muted=false;}";

  // ── Vídeo ────────────────────────────────────────────────────────────────────

  /// Cambia entre modo audio y modo vídeo. Si estaba reproduciendo, reconecta
  /// automáticamente en el nuevo modo.
  Future<void> setVideoMode(bool video) async {
    if (state.videoMode == video) return;
    final wasPlaying = state.playing || state.loading;
    if (video) {
      if (wasPlaying) {
        ++_gen;
        await _player.stop();
        audioHandler.clearActive();
        _startIdlePolling();
      }
      state = state.copyWith(
        videoMode: true,
        playing: false,
        loading: false,
        hasError: false,
      );
      if (wasPlaying) await _startVideo();
    } else {
      final vPlaying = state.playing;
      await _stopVideo();
      state = state.copyWith(videoMode: false);
      if (vPlaying) await playPause();
    }
  }

  /// Play/pause del vídeo (equivalente a playPause() para el audio).
  Future<void> videoPlayPause() async {
    if (state.loading) return;
    if (state.playing) {
      await _stopVideo();
      state = state.copyWith(playing: false, loading: false);
    } else {
      await _startVideo();
    }
  }

  Future<void> _startVideo() async {
    final gen = ++_gen;
    state = state.copyWith(loading: true, hasError: false);
    try {
      await ref.read(podcastPlayerProvider.notifier).pauseForOther();
      if (gen != _gen) return;
      // El player HTML de Wowza (la misma URL del navegador) gestiona la sesión
      // HLS él solo. Reutilizamos el mismo WebViewController entre plays.
      final c = _webController ??= await _createWebController();
      if (gen != _gen) return;
      await c.loadRequest(
          Uri.parse(ref.read(videoQualityProvider).playerUrl));
      if (gen != _gen) return;
      _videoIntendedPlaying = true;
      state = state.copyWith(
        loading: false,
        playing: true,
        videoToken: state.videoToken + 1,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('radio _startVideo webview: $e');
      if (gen != _gen) return;
      // Si la carga falla y estamos en alta calidad, intentamos con la baja.
      if (ref.read(videoQualityProvider) == VideoQuality.high) {
        ref.read(videoQualityProvider.notifier).state = VideoQuality.low;
        try {
          final c = _webController ??= await _createWebController();
          if (gen != _gen) return;
          await c.loadRequest(Uri.parse(VideoQuality.low.playerUrl));
          if (gen != _gen) return;
          _videoIntendedPlaying = true;
          state = state.copyWith(
            loading: false,
            playing: true,
            videoToken: state.videoToken + 1,
            videoAutoSwitchedToLow: true,
          );
          return;
        } catch (_) {
          if (gen != _gen) return;
        }
      }
      state = state.copyWith(
        loading: false,
        hasError: true,
        videoToken: state.videoToken + 1,
      );
    }
  }

  /// Crea (una sola vez) el WebViewController del player. JavaScript activado y,
  /// en Android, autoplay del <video> SIN gesto del usuario (si no, el player
  /// HTML no arranca solo y se queda parado).
  Future<WebViewController> _createWebController() async {
    // iOS (WKWebView): por defecto NO reproduce vídeo inline ni permite autoplay
    // sin un gesto del usuario, así que el <video> del player HTML se queda parado.
    // Hay que activarlo AL CREAR el controlador (equivalente iOS al
    // setMediaPlaybackRequiresUserGesture(false) de Android de más abajo).
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final c = WebViewController.fromPlatformCreationParams(params);
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setBackgroundColor(const Color(0xFF000000));
    // Canal JS: el listener de errores del <video> avisa aquí para el fallback.
    await c.addJavaScriptChannel(
      'VideoFallback',
      onMessageReceived: (_) => _onVideoError(),
    );
    // Al cargar el player: ajusta volumen + inyecta listener de errores de vídeo.
    // En about:blank el querySelector no encuentra nada y no hace nada.
    await c.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) {
        c.runJavaScript(_videoVolumeJs(state.volume));
        c.runJavaScript(_videoErrorListenerJs);
      },
    ));
    if (c.platform is AndroidWebViewController) {
      await (c.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    return c;
  }

  /// Llamado desde JS cuando el <video> del player emite un evento 'error'.
  /// Si estamos en alta calidad, cambia a baja y recarga el player.
  void _onVideoError() {
    if (!state.videoMode || !_videoIntendedPlaying) return;
    if (ref.read(videoQualityProvider) == VideoQuality.low) {
      if (!state.hasError) state = state.copyWith(hasError: true);
      return;
    }
    // Cambio solo en memoria (no persiste): la próxima apertura de la app
    // vuelve a intentar alta calidad.
    // No llamamos loadRequest aquí: el listener de videoQualityProvider en
    // build() ya lo hace síncronamente al detectar el cambio de estado.
    ref.read(videoQualityProvider.notifier).state = VideoQuality.low;
    state = state.copyWith(videoAutoSwitchedToLow: true);
  }

  /// Limpia el flag de auto-switch (llamado desde la UI tras mostrar el aviso).
  void clearAutoSwitchFlag() {
    state = state.copyWith(videoAutoSwitchedToLow: false);
  }

  /// Entra/sale de pantalla completa del vídeo. Solo cambia el flag; la UI
  /// (radio_page) monta el mismo WebViewController en la página fullscreen y lo
  /// saca de la tarjeta inline (un WebViewController no puede estar en dos
  /// WebViewWidget a la vez). El bump de videoToken fuerza el re-montaje.
  void setVideoFullscreen(bool value) {
    if (state.videoFullscreen == value) return;
    state = state.copyWith(
      videoFullscreen: value,
      videoToken: state.videoToken + 1,
    );
  }

  Future<void> _stopVideo() async {
    _videoIntendedPlaying = false;
    if (_backgroundAudioActive) {
      _backgroundAudioActive = false;
      ++_gen;
      await _player.stop();
    }
    // Cargar en blanco detiene el audio/vídeo del player HTML (mantenemos el
    // controller para reutilizarlo en el siguiente play).
    await _webController?.loadRequest(Uri.parse('about:blank'));
    audioHandler.clearActive();
    _startIdlePolling();
    state = state.copyWith(videoToken: state.videoToken + 1);
  }

  // ── Continuidad de audio del modo vídeo ──────────────────────────────────────

  /// Evalúa el estado y arranca/para el audio de fondo según corresponda. Se
  /// llama en cada cambio de ciclo de vida.
  void _evaluatePlayback() {
    final action = decidePlayback(
      videoMode: state.videoMode,
      videoIntendedPlaying: _videoIntendedPlaying,
      foreground: _appState == AppLifecycleState.resumed,
      backgroundAudioActive: _backgroundAudioActive,
    );
    switch (action) {
      case PlaybackAction.none:
        break;
      case PlaybackAction.startBackgroundAudio:
        unawaited(_startBackgroundAudio());
      case PlaybackAction.stopBackgroundAudioResumeVideo:
        unawaited(_stopBackgroundAudio(resumeVideo: true));
      case PlaybackAction.stopBackgroundAudioOnly:
        unawaited(_stopBackgroundAudio(resumeVideo: false));
    }
  }

  /// Pausa el vídeo y arranca el stream de audio de la radio en segundo plano,
  /// reutilizando _player + audio_service (sesión 'radio' en el lockscreen).
  Future<void> _startBackgroundAudio() async {
    if (_backgroundAudioActive) return;
    _backgroundAudioActive = true;
    final gen = ++_gen; // serializa frente a play/stop/reconnect/otros
    try {
      // Corta el vídeo del player HTML (about:blank) → se apaga su audio.
      await _webController?.loadRequest(Uri.parse('about:blank'));
      await ref.read(podcastPlayerProvider.notifier).pauseForOther();
      if (gen != _gen) return;
      await _player
          .setAudioSource(
            AudioSource.uri(Uri.parse(ref.read(audioQualityProvider).url)),
          )
          .timeout(const Duration(seconds: 30));
      if (gen != _gen) return;
      unawaited(_player.play()); // no await: play() solo completa al terminar
      _pushRadioMeta(); // sesión 'radio' en el lockscreen
    } catch (_) {
      if (gen != _gen) return;
      _backgroundAudioActive = false;
      state = state.copyWith(hasError: true, loading: false, playing: false);
    }
  }

  /// Para el audio de fondo. Si [resumeVideo] y seguimos con controller, reanuda
  /// el vídeo (sesión 'video'); si no, deja la sesión limpia.
  Future<void> _stopBackgroundAudio({required bool resumeVideo}) async {
    if (!_backgroundAudioActive) return;
    _backgroundAudioActive = false;
    ++_gen; // invalida cualquier transición de _player en vuelo
    await _player.stop();
    if (resumeVideo && _webController != null) {
      // Volvemos a primer plano: recargamos el player HTML y quitamos la sesión
      // de medios (el vídeo in-app no tiene pantalla de bloqueo).
      await _webController!.loadRequest(
          Uri.parse(ref.read(videoQualityProvider).playerUrl));
      audioHandler.clearActive();
      state = state.copyWith(playing: true, loading: false);
    } else {
      audioHandler.clearActive();
      _startIdlePolling();
      state = state.copyWith(playing: false, loading: false);
    }
  }
}

final radioProvider = NotifierProvider<RadioNotifier, RadioState>(
  RadioNotifier.new,
);
