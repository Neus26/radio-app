import 'package:flutter_test/flutter_test.dart';
import 'package:radio_app/core/audio/audio_handler.dart';
import 'package:radio_app/core/audio/car_catalog.dart';
import 'package:radio_app/core/audio/radio_track.dart';

/// Catálogo que NUNCA toca la red: `setRadioActive` arranca el sondeo del "ahora
/// suena", y en los tests no queremos que salga a rcast.net. Devuelve null como
/// si no hubiera canción todavía.
class _SilentCatalog extends CarCatalog {
  @override
  Future<RadioTrack?> nowPlaying() async => null;
}

/// El MediaItem que se EMITE al reproducir (no el del árbol) debe anunciar la
/// radio como DIRECTO: sin isLive el coche pinta contador (0:04) y barra.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Handler con catálogo mudo + cierre del sondeo al terminar el test (para no
  /// dejar el Timer.periodic vivo entre tests).
  UnicaAudioHandler makeHandler() {
    final handler = UnicaAudioHandler(catalog: _SilentCatalog());
    addTearDown(handler.clearActive); // cancela el sondeo iniciado por la radio
    return handler;
  }

  group('Radio en directo (MediaItem emitido al reproducir)', () {
    test('setRadioActive emite isLive=true y sin duración', () {
      final handler = makeHandler();
      handler.setRadioActive('RadioApp', '');
      final m = handler.mediaItem.value;
      expect(m, isNotNull);
      expect(m!.isLive, isTrue);
      expect(m.duration, isNull);
    });

    test('updateRadioNowPlaying (cambio de canción) mantiene isLive=true', () {
      final handler = makeHandler();
      handler.setRadioActive('RadioApp', '');
      handler.updateRadioNowPlaying('CANCION', 'ARTISTA');
      final m = handler.mediaItem.value;
      expect(m!.title, 'CANCION');
      expect(m.isLive, isTrue);
      expect(m.duration, isNull);
    });
  });

  group('Podcast NO se ve afectado (sigue con duración y barra)', () {
    test('setPodcastActive emite isLive=false y conserva la duración', () {
      final handler = makeHandler();
      handler.setPodcastActive(
        id: 'podcast:1',
        title: 'Puntata',
        duration: const Duration(minutes: 5),
      );
      final m = handler.mediaItem.value;
      expect(m!.isLive, isFalse);
      expect(m.duration, const Duration(minutes: 5));
    });
  });
}
