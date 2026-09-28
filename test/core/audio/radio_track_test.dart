import 'package:flutter_test/flutter_test.dart';
import 'package:radio_app/core/audio/radio_track.dart';

void main() {
  group('parseRadioTrack (status.rcast.net → "ARTISTA - TÍTULO")', () {
    test('separa artista y título por " - " (caso real)', () {
      final t = parseRadioTrack('ROBBIE WILLIAMS - RADIO');
      expect(t.artist, 'ROBBIE WILLIAMS');
      expect(t.title, 'RADIO');
    });

    test('sin separador: todo es título y el artista queda vacío', () {
      final t = parseRadioTrack('Solo un jingle');
      expect(t.title, 'Solo un jingle');
      expect(t.artist, '');
    });

    test('recorta espacios sobrantes', () {
      final t = parseRadioTrack('  JANIS PARK  -  DISCO FEVER  ');
      expect(t.artist, 'JANIS PARK');
      expect(t.title, 'DISCO FEVER');
    });

    test('adjunta la carátula que se le pasa', () {
      final t = parseRadioTrack('A - B',
          artworkUrl: 'https://cdn.rcast.net/cache/itunes/x.png');
      expect(t.artworkUrl, 'https://cdn.rcast.net/cache/itunes/x.png');
    });

    test('sin carátula queda null (el handler cae al logo fijo)', () {
      expect(parseRadioTrack('A - B').artworkUrl, isNull);
    });
  });

  group('parseArtworkUrl (artwork.rcast.net → URL en texto plano)', () {
    test('devuelve la URL cuando el texto es una URL http(s)', () {
      expect(parseArtworkUrl('https://cdn.rcast.net/cache/itunes/x.png'),
          'https://cdn.rcast.net/cache/itunes/x.png');
    });

    test('recorta espacios/saltos antes de comprobar', () {
      expect(parseArtworkUrl('  https://cdn.rcast.net/y.png\n'),
          'https://cdn.rcast.net/y.png');
    });

    test('si no parece una URL → null (evita el cuadro gris)', () {
      expect(parseArtworkUrl(''), isNull);
      expect(parseArtworkUrl('sin caratula'), isNull);
    });
  });
}
