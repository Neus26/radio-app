import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart' show fetchPodcastEpisodes;
import '../audio_quality.dart';
import '../i18n/strings.dart' show S, langFromPrefs;
import 'radio_track.dart';

/// Alimenta la biblioteca que ve el coche (Android Auto).
///
/// SIN Riverpod a propósito: cuando abres la app desde el coche "en frío",
/// Android Auto levanta solo el servicio de medios; la UI no se construye y los
/// providers no existen. Este catálogo se apaña solo con prefs + red.
class CarCatalog {
  CarCatalog({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;
  List<PodcastEpisode>? _cache;
  String? _cacheLang; // idioma con el que se llenó _cache: los títulos dependen de él

  /// OJO con el baseUrl: fetchPodcastEpisodes pide `/wp/v2/series`,
  /// `/wp/v2/posts` y `/wp/v2/media` con rutas RELATIVAS. Sin este baseUrl los
  /// episodios no bajarían (y sin avisar: el fetch se traga el error).
  static Dio _defaultDio() => Dio(BaseOptions(
        baseUrl: 'https://www.unicaradio.it/wp-json',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
      ));

  /// Mount de la radio según la calidad que el usuario tenga elegida.
  Future<String> radioUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return audioQualityFromPrefs(prefs).url;
  }

  /// Strings en el idioma que el usuario tenga elegido, leídos de prefs SIN
  /// Riverpod (el coche puede arrancar en frío: solo el servicio, sin UI).
  ///
  /// `S` y `langFromPrefs` son puros: NO tocan providers. Se leen en cada
  /// navegación (getInstance ya está cacheada: ni red ni disco) para que un
  /// cambio de idioma se refleje al volver a entrar en la biblioteca.
  ///
  /// OJO: esto es el idioma de la INTERFAZ. El idioma del CONTENIDO (el feed de
  /// podcasts, que es italiano) no se toca: ver `episodes()`.
  Future<S> strings() async {
    final prefs = await SharedPreferences.getInstance();
    return S(langFromPrefs(prefs));
  }

  /// Episodios ya cargados en memoria, SIN tocar la red (null si aún no hay
  /// ninguno). La raíz del coche la usa para no bloquearse: pintar dos tiles
  /// constantes no puede quedarse esperando a que baje el feed entero.
  List<PodcastEpisode>? get cachedEpisodes => _cache;

  /// Episodios reales de podcast (API REST de la taxonomía `series`). Solo los
  /// que tienen audio real. Cachea en memoria: el coche pide los hijos varias
  /// veces.
  ///
  /// La fuente es `fetchPodcastEpisodes`, NO el feed RSS: el RSS está topado en
  /// 9 episodios (los mismos repetidos en los 9 idiomas de Polylang), mientras
  /// que la taxonomía `series` da miles y pagina de verdad. Con 3 páginas salen
  /// ~50 (lo último de todos los programas), sin castigar a Aruba ni pasarse del
  /// límite de hijos por nodo de Android Auto.
  ///
  /// El idioma sale de prefs (SIN Riverpod: en arranque en frío desde el coche
  /// no hay providers). NO es el idioma del audio (siempre italiano): es solo
  /// para elegir el TÍTULO traducido de cada episodio cuando existe, con el
  /// italiano de respaldo (las traducciones comparten el mismo mp3).
  ///
  /// NUNCA cachea un resultado VACÍO. `fetchPodcastEpisodes` se traga los fallos
  /// de red (devuelve `[]` sin lanzar), así que memorizar ese vacío dejaría la
  /// carpeta del coche vacía para SIEMPRE: el servicio de medios vive horas y
  /// nadie invalida la caché. Sin caché devolvemos vacío, pero se reintenta la
  /// próxima vez que el coche entre en la carpeta.
  Future<List<PodcastEpisode>> episodes({bool refresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final lang = langFromPrefs(prefs).code;
    // La caché se invalida si cambió el idioma: los títulos de los episodios
    // vienen traducidos, así que un cambio de idioma en la app tiene que
    // reflejarse al volver a entrar en la carpeta (si no, se quedaban congelados
    // en el idioma del primer fetch).
    if (!refresh && _cache != null && _cacheLang == lang) return _cache!;
    try {
      final eps = await fetchPodcastEpisodes(_dio, langCode: lang, pages: 3);
      final withAudio = eps.where((e) => (e.audioUrl ?? '').isNotEmpty).toList();
      if (withAudio.isNotEmpty) {
        _cache = withAudio;
        _cacheLang = lang;
      }
    } catch (_) {
      // Sin red: carpeta vacía en vez de reventar la biblioteca del coche.
    }
    return _cache ?? const <PodcastEpisode>[];
  }

  Future<PodcastEpisode?> episodeById(int id) async {
    for (final e in await episodes()) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// "Ahora suena" del directo SIN Riverpod (arranque en frío desde el coche:
  /// solo el servicio de medios, sin UI, sin RadioNotifier que sondee).
  ///
  /// Dos peticiones de TEXTO PLANO a rcast: la canción ("ARTISTA - TÍTULO") y la
  /// URL de su carátula. URLs ABSOLUTAS a propósito: dio ignora el baseUrl
  /// (wp-json) cuando la ruta ya es absoluta, así que reutilizamos este mismo Dio
  /// sin romper los podcasts (que piden con rutas relativas).
  ///
  /// `responseType: plain` fuerza a dio a devolver el String crudo (no intenta
  /// parsear JSON sobre un text/plain). null si no hay red o la canción viene
  /// vacía → el handler se queda con "RadioApp" + el logo fijo.
  Future<RadioTrack?> nowPlaying() async {
    try {
      final st = await _dio.get<dynamic>('https://status.rcast.net/66954',
          options: Options(responseType: ResponseType.plain));
      final raw = (st.data ?? '').toString().trim();
      if (raw.isEmpty) return null;
      String? art;
      try {
        final ar = await _dio.get<dynamic>('https://artwork.rcast.net/66954',
            options: Options(responseType: ResponseType.plain));
        art = parseArtworkUrl((ar.data ?? '').toString());
      } catch (_) {
        // Sin carátula: el handler cae al logo fijo.
      }
      return parseRadioTrack(raw, artworkUrl: art);
    } catch (_) {
      return null;
    }
  }
}
