import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radio_app/core/audio/car_media.dart';
import 'package:radio_app/data/models/article.dart';

PodcastEpisode _ep({int id = 123, String title = 'Puntata', String? img, String? audio}) =>
    PodcastEpisode(
      id: id,
      title: title,
      imageUrl: img,
      audioUrl: audio ?? 'https://unicaradio.it/podcast-download/$id/a.mp3',
      date: DateTime(2026, 1, 1),
    );

void main() {
  group('IDs', () {
    test('el id de episodio se serializa y se vuelve a parsear', () {
      expect(CarIds.episode(42), 'podcast:42');
      expect(episodeIdFrom('podcast:42'), 42);
    });

    test('un mediaId que no es de podcast devuelve null', () {
      expect(episodeIdFrom(CarIds.radio), isNull);
      expect(episodeIdFrom('podcasts'), isNull);
      expect(episodeIdFrom('podcast:no-es-numero'), isNull);
      expect(episodeIdFrom(''), isNull);
    });
  });

  group('MediaItem de la radio', () {
    test('es reproducible, en directo y SIN duración (no sale barra de posición)', () {
      final m = radioMediaItem(title: 'Radio');
      expect(m.id, CarIds.radio);
      expect(m.playable, isTrue);
      expect(m.isLive, isTrue);
      expect(m.duration, isNull);
    });

    test('el título llega traducido desde fuera (el coche sigue el idioma)', () {
      expect(radioMediaItem(title: 'Радио').title, 'Радио');
    });

    test('la carátula es el logo PNG real, no el endpoint text/plain (evita el '
        'cuadro gris)', () {
      final m = radioMediaItem(title: 'Radio');
      expect(m.artUri, Uri.parse(kRadioLogoUrl));
      // artwork.rcast.net NO es una imagen (devuelve text/plain): no debe usarse
      // como artUri o Android pinta un hueco gris.
      expect(kRadioLogoUrl, isNot(contains('artwork.rcast.net')));
      expect(kRadioLogoUrl, endsWith('.png'));
    });
  });

  group('Pestaña Radio (saca el directo de la pestaña automática "Altro")', () {
    test('es navegable (no reproducible) y lleva el título traducido', () {
      final m = radioFolderMediaItem(title: 'Radio');
      expect(m.id, CarIds.radioFolder);
      expect(m.title, 'Radio');
      expect(m.playable, isFalse);
    });

    test('su hijo (el directo) se pide en cuadrícula (tarjeta grande)', () {
      final m = radioFolderMediaItem(title: 'Radio');
      expect(m.extras?[AndroidContentStyle.playableHintKey],
          AndroidContentStyle.gridItemHintValue);
    });

    test('contiene solo el directo, con el título traducido', () {
      final children = radioChildren(title: 'Радио');
      expect(children.map((e) => e.id).toList(), [CarIds.radio]);
      expect(children.single.title, 'Радио');
      expect(children.single.playable, isTrue);
    });
  });

  group('Carpeta de podcasts', () {
    test('es navegable (no reproducible) y lleva el título que se le pasa', () {
      final m = podcastsFolderMediaItem(title: 'Podcast e interviste');
      expect(m.id, CarIds.podcasts);
      expect(m.title, 'Podcast e interviste');
      expect(m.playable, isFalse);
    });

    test('sus hijos se piden en modo lista', () {
      final m = podcastsFolderMediaItem(title: 'Podcast e interviste');
      expect(m.extras?[AndroidContentStyle.playableHintKey],
          AndroidContentStyle.listItemHintValue);
    });

    test('sin carátula: ahora es una pestaña (icono de pestaña, no foto)', () {
      expect(podcastsFolderMediaItem(title: 'Podcast e interviste').artUri,
          isNull);
    });
  });

  group('MediaItem de episodio', () {
    test('es reproducible y lleva el id con prefijo', () {
      final m = episodeMediaItem(_ep(id: 7, title: 'Intervista'));
      expect(m.id, 'podcast:7');
      expect(m.title, 'Intervista');
      expect(m.playable, isTrue);
    });

    test('sin imagen no revienta: artUri queda null', () {
      final m = episodeMediaItem(_ep(img: null));
      expect(m.artUri, isNull);
    });

    test('con imagen la expone como artUri', () {
      final m = episodeMediaItem(_ep(img: 'https://unicaradio.it/x.jpg'));
      expect(m.artUri.toString(), 'https://unicaradio.it/x.jpg');
    });

    test('con imagen vacía artUri queda null', () {
      expect(episodeMediaItem(_ep(img: '')).artUri, isNull);
    });
  });

  group('Raíz', () {
    test('solo navegables: la pestaña Radio primero y la de podcasts después',
        () {
      final r = _root();
      expect(
          r.map((e) => e.id).toList(), [CarIds.radioFolder, CarIds.podcasts]);
    });

    test('ningún playable suelto en la raíz (si no, caería en "Altro")', () {
      // Android Auto tira los playables de la raíz a la pestaña "Altro": la raíz
      // debe llevar SOLO navegables.
      expect(_root().every((e) => e.playable == false), isTrue);
    });

    test('los nombres de las secciones son los que se le pasan (idioma elegido)',
        () {
      final r = rootChildren(radioTitle: '电台', podcastsTitle: '播客与访谈');
      expect(r.firstWhere((e) => e.id == CarIds.radioFolder).title, '电台');
      expect(r.firstWhere((e) => e.id == CarIds.podcasts).title, '播客与访谈');
    });

    test('las pestañas van sin carátula (son iconos de pestaña, no fotos)', () {
      final r = _root();
      expect(r.firstWhere((e) => e.id == CarIds.radioFolder).artUri, isNull);
      expect(r.firstWhere((e) => e.id == CarIds.podcasts).artUri, isNull);
    });
  });
}

/// Raíz con títulos de relleno: estos tests miran la ESTRUCTURA, no el idioma.
List<MediaItem> _root() => rootChildren(
      radioTitle: 'Radio',
      podcastsTitle: 'Podcast e interviste',
    );
