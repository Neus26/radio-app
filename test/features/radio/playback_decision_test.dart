import 'package:flutter_test/flutter_test.dart';
import 'package:radio_app/features/radio/playback_decision.dart';

void main() {
  group('decidePlayback', () {
    test('primer plano, sin audio de fondo → no hace nada (suena el vídeo)', () {
      expect(
        decidePlayback(
          videoMode: true,
          videoIntendedPlaying: true,
          foreground: true,
          backgroundAudioActive: false,
        ),
        PlaybackAction.none,
      );
    });

    test('segundo plano → arranca audio de fondo', () {
      expect(
        decidePlayback(
          videoMode: true,
          videoIntendedPlaying: true,
          foreground: false,
          backgroundAudioActive: false,
        ),
        PlaybackAction.startBackgroundAudio,
      );
    });

    test('vuelve a primer plano con audio de fondo → para audio y reanuda vídeo', () {
      expect(
        decidePlayback(
          videoMode: true,
          videoIntendedPlaying: true,
          foreground: true,
          backgroundAudioActive: true,
        ),
        PlaybackAction.stopBackgroundAudioResumeVideo,
      );
    });

    test('segundo plano y audio de fondo ya activo → no hace nada (idempotente)', () {
      expect(
        decidePlayback(
          videoMode: true,
          videoIntendedPlaying: true,
          foreground: false,
          backgroundAudioActive: true,
        ),
        PlaybackAction.none,
      );
    });

    test('el usuario dejó de querer vídeo con audio de fondo → para audio, no reanuda', () {
      expect(
        decidePlayback(
          videoMode: true,
          videoIntendedPlaying: false,
          foreground: true,
          backgroundAudioActive: true,
        ),
        PlaybackAction.stopBackgroundAudioOnly,
      );
    });

    test('modo audio (no vídeo) sin audio de fondo → no hace nada', () {
      expect(
        decidePlayback(
          videoMode: false,
          videoIntendedPlaying: false,
          foreground: false,
          backgroundAudioActive: false,
        ),
        PlaybackAction.none,
      );
    });
  });
}
