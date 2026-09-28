import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:radio_app/core/audio/car_catalog.dart';
import 'package:radio_app/core/audio_quality.dart';
import 'package:radio_app/core/i18n/strings.dart';

/// Post de episodio con la forma real de `/wp/v2/posts?series=...`: la nueva
/// fuente REST (taxonomía `series` de SSP). El mp3 va en `meta.audio_file`; sin
/// esa clave el episodio no es reproducible (no debe salir).
Map<String, dynamic> _post(int id,
        {String? audio, int media = 0, String? link}) =>
    {
      'id': id,
      'date': '2026-01-01T10:00:00',
      'link': link ?? 'https://www.unicaradio.it/podcast-$id/',
      'title': {'rendered': 'Puntata $id'},
      'featured_media': media,
      if (audio != null) 'meta': {'audio_file': audio},
    };

/// Adapter falso de dio para la fuente REST de episodios. Sirve `/wp/v2/series`,
/// `/wp/v2/posts` y `/wp/v2/media` como JSON, cuenta las peticiones (para
/// comprobar la caché) y permite simular "sin red" (campo a null). No hace falta
/// ninguna dependencia nueva: dio ya deja sustituir el adapter (y CarCatalog
/// acepta un Dio inyectado justo para esto).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.series, this.posts, Map<int, String>? media})
      : media = media ?? const {};

  /// `[{id, count}]` de `/wp/v2/series`. null = la petición falla (sin red).
  List<Map<String, dynamic>>? series;

  /// Posts de la PÁGINA 1 de `/wp/v2/posts` (las páginas 2+ llegan vacías y
  /// cortan el bucle). null = la petición falla (sin red).
  List<Map<String, dynamic>>? posts;

  /// id de media → source_url para `/wp/v2/media`.
  Map<int, String> media;

  /// Posts de la PÁGINA 2 (para probar que se acumulan varias páginas). null =
  /// página 2 vacía → corta el bucle.
  List<Map<String, dynamic>>? postsPage2;

  /// Si true, la PÁGINA 2 responde 200 con un cuerpo NO-array (error del plugin
  /// de WordPress / HTML de Aruba): NO debe reventar el cast ni tirar los de la
  /// página 1.
  bool page2Garbage = false;

  int seriesCalls = 0;
  int postsCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path.contains('/wp/v2/series')) {
      seriesCalls++;
      return _json(options, series);
    }
    if (path.contains('/wp/v2/posts')) {
      postsCalls++;
      if (posts == null) throw _noNet(options);
      final page =
          int.tryParse(options.uri.queryParameters['page'] ?? '1') ?? 1;
      if (page == 1) return _json(options, posts);
      if (page == 2 && page2Garbage) {
        // 200 con objeto (no lista): simula el error del plugin de WP.
        return ResponseBody.fromString(
            jsonEncode({'code': 'rest_error'}), 200, headers: {
          Headers.contentTypeHeader: ['application/json; charset=UTF-8'],
        });
      }
      if (page == 2 && postsPage2 != null) return _json(options, postsPage2);
      return _json(options, const <Map<String, dynamic>>[]); // resto: vacío
    }
    if (path.contains('/wp/v2/media')) {
      final include = (options.uri.queryParameters['include'] ?? '')
          .split(',')
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
      final out = [
        for (final e in media.entries)
          if (include.contains(e.key)) {'id': e.key, 'source_url': e.value}
      ];
      return _json(options, out);
    }
    // Nada más debería pedirse en estos tests.
    throw DioException(
        requestOptions: options, type: DioExceptionType.badResponse);
  }

  DioException _noNet(RequestOptions o) =>
      DioException(requestOptions: o, type: DioExceptionType.connectionError);

  ResponseBody _json(RequestOptions options, List<Object?>? data) {
    if (data == null) throw _noNet(options); // campo a null = sin red
    return ResponseBody.fromString(jsonEncode(data), 200, headers: {
      Headers.contentTypeHeader: ['application/json; charset=UTF-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

CarCatalog _catalogWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.unicaradio.it/wp-json'));
  dio.httpClientAdapter = adapter;
  return CarCatalog(dio: dio);
}

/// Adapter falso para el "ahora suena": sirve status.rcast.net y
/// artwork.rcast.net como TEXTO PLANO (que es como responden de verdad). null en
/// cualquiera de los dos = "sin red" para esa petición.
class _RcastAdapter implements HttpClientAdapter {
  _RcastAdapter({this.status, this.artwork});

  String? status; // cuerpo de status.rcast.net
  String? artwork; // cuerpo de artwork.rcast.net

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    if (url.contains('status.rcast.net')) return _serve(options, status);
    if (url.contains('artwork.rcast.net')) return _serve(options, artwork);
    throw DioException(
        requestOptions: options, type: DioExceptionType.badResponse);
  }

  ResponseBody _serve(RequestOptions options, String? body) {
    if (body == null) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['text/plain; charset=UTF-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// El baseUrl es el de wp-json a propósito: nowPlaying usa URLs ABSOLUTAS, así
/// que dio debe ignorar el baseUrl (si no, se rompería al pedir rcast).
CarCatalog _rcastCatalog(_RcastAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://www.unicaradio.it/wp-json'));
  dio.httpClientAdapter = adapter;
  return CarCatalog(dio: dio);
}

/// mp3 directo de ejemplo (el que sirve `meta.audio_file`).
String _mp3(int id) => 'https://www.unicaradio.it/wp-content/uploads/$id.mp3';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audioQualityFromPrefs (lo usa el coche, sin Riverpod)', () {
    test('sin nada guardado → calidad alta por defecto', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(audioQualityFromPrefs(prefs), AudioQuality.high);
      expect(audioQualityFromPrefs(prefs).url,
          'https://streaming.unicaradio.it/unica192.mp3');
    });

    test('respeta la calidad que el usuario guardó', () async {
      SharedPreferences.setMockInitialValues({kAudioQualityPrefsKey: 'low'});
      final prefs = await SharedPreferences.getInstance();
      expect(audioQualityFromPrefs(prefs), AudioQuality.low);
      expect(audioQualityFromPrefs(prefs).url,
          'https://streaming.unicaradio.it/unica48.aac');
    });

    test('un valor basura guardado no rompe: cae a alta', () async {
      SharedPreferences.setMockInitialValues({kAudioQualityPrefsKey: 'xxx'});
      final prefs = await SharedPreferences.getInstance();
      expect(audioQualityFromPrefs(prefs), AudioQuality.high);
    });
  });

  group('langFromPrefs (el coche lee el idioma sin Riverpod)', () {
    test('respeta el idioma que el usuario guardó', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'ru'});
      final prefs = await SharedPreferences.getInstance();
      expect(langFromPrefs(prefs), AppLang.ru);
    });

    test('lee lo que escribe setLang (mismo formato: el código ISO)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLangPrefsKey, AppLang.es.code);
      expect(langFromPrefs(prefs), AppLang.es);
    });

    test('un valor basura guardado no rompe: cae al idioma del dispositivo',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'xx'});
      final prefs = await SharedPreferences.getInstance();
      expect(AppLang.values, contains(langFromPrefs(prefs)));
    });
  });

  group('Nombres de las secciones del coche', () {
    test('la sección Radio y la carpeta de podcasts existen en los 9 idiomas',
        () {
      // `S._` indexa la lista de traducciones por `lang.index`: una clave con
      // menos de 9 valores reventaría con RangeError SOLO en ese idioma (en
      // runtime, dentro del coche). Esto lo pilla aquí.
      for (final l in AppLang.values) {
        expect(S(l).tabRadio, isNotEmpty, reason: 'tabRadio en ${l.code}');
        expect(S(l).carPodcasts, isNotEmpty, reason: 'carPodcasts en ${l.code}');
      }
    });

    test('no están a fuego en castellano: cada idioma trae lo suyo', () {
      expect(S(AppLang.it).carPodcasts, 'Podcast e interviste');
      expect(S(AppLang.es).carPodcasts, 'Podcasts y entrevistas');
      expect(S(AppLang.ru).tabRadio, 'Радио');
    });
  });

  group('CarCatalog.strings (idioma de la biblioteca del coche)', () {
    test('sirve los strings en el idioma guardado en prefs', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final catalog = _catalogWith(_FakeAdapter());

      final s = await catalog.strings();

      expect(s.lang, AppLang.it);
      expect(s.tabRadio, 'Radio');
      expect(s.carPodcasts, 'Podcast e interviste');
    });

    test('un cambio de idioma se refleja en la siguiente navegación', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final catalog = _catalogWith(_FakeAdapter());
      expect((await catalog.strings()).lang, AppLang.it);

      // El usuario cambia el idioma en la app (setLang persiste el código).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLangPrefsKey, AppLang.de.code);

      final s = await catalog.strings();
      expect(s.lang, AppLang.de);
      expect(s.carPodcasts, 'Podcasts und Interviews');
    });

    test('no toca la red: leer el idioma no puede depender del feed', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'fr'});
      final adapter = _FakeAdapter();
      final catalog = _catalogWith(adapter);

      expect((await catalog.strings()).lang, AppLang.fr);
      expect(adapter.seriesCalls, 0);
      expect(adapter.postsCalls, 0);
    });
  });

  group('CarCatalog.episodes', () {
    test('posts OK → solo los episodios que tienen audio', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 188586, 'count': 10}
        ],
        posts: [
          _post(101, audio: _mp3(101), media: 555),
          _post(102), // sin meta.audio_file → no es reproducible
        ],
        media: {555: 'https://www.unicaradio.it/101.jpg'},
      );
      final eps = await _catalogWith(adapter).episodes();

      expect(eps.map((e) => e.id).toList(), [101]);
      expect(eps.single.audioUrl, _mp3(101));
    });

    test('deduplica traducciones por audio y elige el título del idioma pedido',
        () async {
      // Polylang publica el MISMO mp3 como posts distintos por idioma (solo
      // cambia título y link). Deduplicando por audio se elige el título del
      // idioma pedido, con el italiano de respaldo.
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'es'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [
          // italiano (respaldo, sin prefijo de idioma en la URL)
          _post(10, audio: _mp3(7), link: 'https://www.unicaradio.it/podcast-10/'),
          // español (el idioma pedido, prefijo /es/)
          _post(20,
              audio: _mp3(7), link: 'https://www.unicaradio.it/es/podcast-20/'),
        ],
      );
      final eps = await _catalogWith(adapter).episodes();

      expect(eps.length, 1, reason: 'las dos son el mismo audio → un episodio');
      expect(eps.single.title, 'Puntata 20',
          reason: 'gana el título del idioma pedido (el post español)');
    });

    test('la segunda llamada sirve de la caché, sin volver a pedir los posts',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101))],
      );
      final catalog = _catalogWith(adapter);

      await catalog.episodes();
      final calls = adapter.postsCalls;
      final eps = await catalog.episodes();

      expect(eps.single.id, 101);
      expect(adapter.postsCalls, calls, reason: 'no debe repetir la petición');
    });

    test(
        'sin red → carpeta vacía, pero REINTENTA en la siguiente entrada '
        '(no memoriza el fallo)', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(series: null); // sin red en /series
      final catalog = _catalogWith(adapter);

      expect(await catalog.episodes(), isEmpty);
      expect(catalog.cachedEpisodes, isNull);
      final callsOffline = adapter.seriesCalls;

      // Vuelve la cobertura: la siguiente entrada en la carpeta SÍ toca la red.
      adapter.series = [
        {'id': 1, 'count': 5}
      ];
      adapter.posts = [_post(101, audio: _mp3(101))];
      final eps = await catalog.episodes();

      expect(adapter.seriesCalls, greaterThan(callsOffline),
          reason: 'debe reintentar en vez de servir la caché envenenada');
      expect(eps.single.id, 101);
    });

    test('una lista vacía tampoco se cachea: se reintenta', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: const [],
      );
      final catalog = _catalogWith(adapter);

      expect(await catalog.episodes(), isEmpty);
      final callsVacio = adapter.seriesCalls;

      adapter.posts = [_post(101, audio: _mp3(101))];

      expect((await catalog.episodes()).single.id, 101);
      expect(adapter.seriesCalls, greaterThan(callsVacio));
    });

    test('acumula los episodios de varias páginas (no solo la primera)',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 250}
        ],
        posts: [_post(101, audio: _mp3(101))],
      )..postsPage2 = [_post(202, audio: _mp3(202))];

      final eps = await _catalogWith(adapter).episodes();

      expect(eps.map((e) => e.id).toSet(), {101, 202},
          reason: 'los episodios de la página 1 y la 2 se combinan');
    });

    test('una página 2 no-array NO tira los episodios ya bajados de la 1',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 250}
        ],
        posts: [_post(101, audio: _mp3(101))],
      )..page2Garbage = true;

      final eps = await _catalogWith(adapter).episodes();

      expect(eps.map((e) => e.id).toList(), [101],
          reason: 'la página basura se ignora; la 1 sobrevive');
    });

    test('un cambio de idioma invalida la caché (vuelve a pedir los títulos)',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101))],
      );
      final catalog = _catalogWith(adapter);
      await catalog.episodes();
      final calls = adapter.postsCalls;

      // El usuario cambia el idioma en la app (setLang persiste el código).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLangPrefsKey, AppLang.es.code);

      await catalog.episodes();
      expect(adapter.postsCalls, greaterThan(calls),
          reason: 'al cambiar de idioma no puede servir los títulos viejos');
    });
  });

  group('CarCatalog.cachedEpisodes (la raíz del coche NO puede tocar la red)',
      () {
    test('antes de cargar nada es null y no dispara ninguna petición', () async {
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101))],
      );
      final catalog = _catalogWith(adapter);

      expect(catalog.cachedEpisodes, isNull);
      expect(adapter.seriesCalls, 0);
      expect(adapter.postsCalls, 0);
    });

    test('tras cargar los episodios expone los ya cacheados con su carátula',
        () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101), media: 555)],
        media: {555: 'https://www.unicaradio.it/101.jpg'},
      );
      final catalog = _catalogWith(adapter);
      await catalog.episodes();

      expect(catalog.cachedEpisodes?.single.imageUrl,
          'https://www.unicaradio.it/101.jpg');
    });
  });

  group('CarCatalog.nowPlaying (el coche resuelve la canción sin Riverpod)', () {
    test('canción + carátula resueltas desde texto plano', () async {
      final catalog = _rcastCatalog(_RcastAdapter(
        status: 'ROBBIE WILLIAMS - RADIO',
        artwork: 'https://cdn.rcast.net/cache/itunes/abc.png',
      ));
      final t = await catalog.nowPlaying();

      expect(t, isNotNull);
      expect(t!.artist, 'ROBBIE WILLIAMS');
      expect(t.title, 'RADIO');
      expect(t.artworkUrl, 'https://cdn.rcast.net/cache/itunes/abc.png');
    });

    test('status vacío → null (el coche se queda con "RadioApp" + logo)',
        () async {
      final catalog = _rcastCatalog(_RcastAdapter(status: '   ', artwork: null));
      expect(await catalog.nowPlaying(), isNull);
    });

    test('sin red en status → null', () async {
      final catalog = _rcastCatalog(_RcastAdapter(status: null, artwork: null));
      expect(await catalog.nowPlaying(), isNull);
    });

    test('carátula caída → canción igual, sin carátula (fallback al logo)',
        () async {
      final catalog =
          _rcastCatalog(_RcastAdapter(status: 'A - B', artwork: null));
      final t = await catalog.nowPlaying();

      expect(t, isNotNull);
      expect(t!.title, 'B');
      expect(t.artworkUrl, isNull);
    });

    test('artwork que NO es una URL → carátula null (evita el cuadro gris)',
        () async {
      final catalog = _rcastCatalog(
          _RcastAdapter(status: 'A - B', artwork: 'no hay caratula'));
      expect((await catalog.nowPlaying())?.artworkUrl, isNull);
    });
  });

  group('CarCatalog.episodeById', () {
    test('devuelve el episodio', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101))],
      );
      final ep = await _catalogWith(adapter).episodeById(101);

      expect(ep?.id, 101);
    });

    test('id inexistente → null', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(
        series: [
          {'id': 1, 'count': 5}
        ],
        posts: [_post(101, audio: _mp3(101))],
      );

      expect(await _catalogWith(adapter).episodeById(999), isNull);
    });

    test('sin red → null, sin envenenar la caché', () async {
      SharedPreferences.setMockInitialValues({kLangPrefsKey: 'it'});
      final adapter = _FakeAdapter(series: null);
      final catalog = _catalogWith(adapter);

      expect(await catalog.episodeById(101), isNull);

      adapter.series = [
        {'id': 1, 'count': 5}
      ];
      adapter.posts = [_post(101, audio: _mp3(101))];
      expect((await catalog.episodeById(101))?.id, 101);
    });
  });
}
