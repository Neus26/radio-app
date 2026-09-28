import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../data/models/article.dart';
import '../../core/analytics/analytics.dart';
import '../../core/audio/audio_handler.dart';
import '../../core/audio/car_media.dart';
import '../radio/radio_notifier.dart';

class PodcastPlayState {
  final PodcastEpisode? episode;
  final bool playing;
  final bool loading;
  final bool hasError;
  final double volume;

  const PodcastPlayState({
    this.episode,
    this.playing = false,
    this.loading = false,
    this.hasError = false,
    this.volume = 1.0,
  });

  PodcastPlayState copyWith({
    PodcastEpisode? episode,
    bool? playing,
    bool? loading,
    bool? hasError,
    double? volume,
  }) =>
      PodcastPlayState(
        episode: episode ?? this.episode,
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        hasError: hasError ?? this.hasError,
        volume: volume ?? this.volume,
      );
}

class PodcastNotifier extends Notifier<PodcastPlayState> {
  // El AudioPlayer vive en el handler para que el SO tenga acceso a él.
  AudioPlayer get _player => audioHandler.podcastPlayer;
  StreamSubscription<PlayerState>? _stateSub;
  int _playGen = 0; // token generacional: evita race si playEpisode se llama dos veces

  /// Expuesto para que podcast_page.dart acceda a los streams de posición/duración.
  AudioPlayer get player => audioHandler.podcastPlayer;

  @override
  PodcastPlayState build() {
    _stateSub = _player.playerStateStream.listen((ps) {
      final buffering = ps.processingState == ProcessingState.loading ||
          ps.processingState == ProcessingState.buffering;
      final completed = ps.processingState == ProcessingState.completed;
      state = state.copyWith(
        loading: buffering,
        playing: completed ? false : ps.playing,
        hasError: ps.playing ? false : state.hasError,
      );
      if (completed) {
        unawaited(_player.seek(Duration.zero));
      }
    });
    // El coche arrancó un episodio: fijamos cuál es. El `playing` ya lo actualiza
    // solo el listener de playerStateStream de arriba.
    audioHandler.onPodcastStartedExternally = (ep) {
      state = state.copyWith(episode: ep, loading: false, hasError: false);
    };
    // El coche tomó el control y paró el episodio (arrancó la radio). Igual que
    // pauseForOther(), cancelamos la carga en vuelo (++_playGen): si no, un
    // episodio que la app estaba cargando llegaría a play() DESPUÉS y sonaría
    // ENCIMA de la radio del coche.
    audioHandler.onPodcastStoppedExternally = () {
      ++_playGen;
      state = state.copyWith(playing: false, loading: false);
    };
    ref.onDispose(() {
      _stateSub?.cancel();
      // NO dispose del player — lo gestiona el handler
    });
    return const PodcastPlayState();
  }

  Future<void> playEpisode(PodcastEpisode ep) async {
    // Mismo episodio y SIN error → alternar play/pausa. Si el intento anterior
    // FALLO (hasError), NO delegamos en playPause (haria play() sobre un player
    // sin fuente valida): caemos abajo y recargamos la fuente desde cero.
    if (state.episode?.id == ep.id && !state.hasError) {
      await playPause();
      return;
    }
    if (ep.audioUrl == null || ep.audioUrl!.isEmpty) {
      state = state.copyWith(hasError: true);
      return;
    }
    final url = ep.audioUrl!;
    if (!url.toLowerCase().startsWith('http://') && !url.toLowerCase().startsWith('https://')) {
      state = state.copyWith(hasError: true);
      return;
    }
    final gen = ++_playGen;
    state = PodcastPlayState(episode: ep, loading: true, volume: state.volume);
    try {
      await ref.read(radioProvider.notifier).stopForOther();
      if (gen != _playGen) return; // otra llamada ganó la carrera
      // Timeout como en la radio: si la fuente conecta pero se cuelga, no
      // dejamos el "cargando" infinito — salta al catch y marca error.
      await _player
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (gen != _playGen) return;
      // play() NO se await (su Future solo completa cuando el episodio termina
      // o se pausa); si no, el timeout saltaria a los 30s con el audio sonando.
      unawaited(_player.play());
      Analytics.instance.log('podcast_play', {
        'episode_id': ep.id.toString(),
        'episode_title':
            ep.title.length > 100 ? ep.title.substring(0, 100) : ep.title,
      });
      // L23: la duración puede llegar tarde; la esperamos PERO con timeout, para
      // no dejar este flujo colgado para siempre si la fuente nunca la reporta.
      final dur = _player.duration ??
          await _player.durationStream
              .firstWhere((d) => d != null)
              .timeout(const Duration(seconds: 8), onTimeout: () => null);
      if (gen != _playGen) return; // no mandar metadatos de una carga ya superada
      // Notificar al handler para que la pantalla del coche muestre el episodio.
      // El id es el CANÓNICO del árbol navegable ('podcast:<id>'): con el id
      // pelado, Android Auto no puede casar lo que suena con la fila de la lista
      // y el propio handler no sabría resolverlo (episodeIdFrom exige el prefijo).
      audioHandler.setPodcastActive(
        id: CarIds.episode(ep.id),
        title: ep.title,
        artworkUri: ep.imageUrl,
        duration: dur,
      );
    } catch (_) {
      if (gen == _playGen) {
        state = state.copyWith(loading: false, hasError: true, playing: false);
      }
    }
  }

  Future<void> playPause() async {
    if (state.playing) {
      await _player.pause();
    } else {
      if (state.hasError) state = state.copyWith(hasError: false);
      await ref.read(radioProvider.notifier).stopForOther();
      await _player.play();
    }
  }

  Future<void> seek(Duration pos) => _player.seek(pos);

  Future<void> setVolume(double v) async {
    state = state.copyWith(volume: v);
    await _player.setVolume(v);
  }

  /// Pausa el episodio si está sonando. Lo llama la radio al empezar a sonar,
  /// para que no se solapen los dos audios.
  Future<void> pauseForOther() async {
    // INTEG-1: contempla también la ventana de carga (loading) y cancela la
    // carga en vuelo (++_playGen). Si no, un episodio que estaba cargando
    // llegaría a _player.play() DESPUÉS de que la radio tomara el control y
    // sonarían los dos a la vez.
    if (state.playing || state.loading) {
      ++_playGen;
      try {
        await _player.pause();
      } catch (_) {}
      state = state.copyWith(playing: false, loading: false);
    }
  }
}

final podcastPlayerProvider =
    NotifierProvider<PodcastNotifier, PodcastPlayState>(PodcastNotifier.new);
