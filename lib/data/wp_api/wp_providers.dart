import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import '../models/article.dart';
import '../models/category.dart';
import '../../core/i18n/strings.dart';
import '../../shared/util/html_text.dart';

// --- Caché local (shared_preferences): muestra lo último al instante. ---
List<Map<String, dynamic>>? _cacheRead(SharedPreferences prefs, String key) {
  final s = prefs.getString(key);
  if (s == null) return null;
  try {
    return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return null;
  }
}

void _cacheWrite(
    SharedPreferences prefs, String key, List<Map<String, dynamic>> data) {
  prefs.setString(key, jsonEncode(data));
}

/// Salud del backend (API WordPress). Se marca "caído" tras varios fallos
/// seguidos (sin respuesta o 5xx) y se limpia al primer éxito. Lo alimenta el
/// interceptor de `dioProvider`; el shell muestra un banner cuando
/// `down && !dismissed`. `dismissed` = el usuario lo cerró a mano.
class BackendHealth {
  final bool down;
  final bool dismissed;
  const BackendHealth({this.down = false, this.dismissed = false});
}

class BackendHealthNotifier extends Notifier<BackendHealth> {
  static const _threshold = 2; // fallos seguidos antes de avisar (evita flicker)
  int _fails = 0;

  @override
  BackendHealth build() => const BackendHealth();

  void reportError() {
    _fails++;
    if (_fails >= _threshold && !state.down) {
      state = const BackendHealth(down: true);
    }
  }

  void reportOk() {
    _fails = 0;
    if (state.down || state.dismissed) state = const BackendHealth();
  }

  void dismiss() {
    if (state.down && !state.dismissed) {
      state = const BackendHealth(down: true, dismissed: true);
    }
  }
}

final backendHealthProvider =
    NotifierProvider<BackendHealthNotifier, BackendHealth>(
        BackendHealthNotifier.new);

/// Cliente HTTP base contra la API REST de WordPress de unicaradio.it.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://www.unicaradio.it/wp-json',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
  ));
  // Alimenta el estado de salud: si las peticiones a WordPress no llegan (sin
  // respuesta) o dan 5xx → caído; un 4xx (el server respondió) o un éxito = vivo.
  dio.interceptors.add(InterceptorsWrapper(
    onResponse: (res, handler) {
      ref.read(backendHealthProvider.notifier).reportOk();
      handler.next(res);
    },
    onError: (e, handler) {
      final status = e.response?.statusCode ?? 0;
      if (e.response == null || status >= 500) {
        ref.read(backendHealthProvider.notifier).reportError();
      } else if (status >= 400) {
        ref.read(backendHealthProvider.notifier).reportOk();
      }
      handler.next(e);
    },
  ));
  return dio;
});

// ─────────────────────────────────────────────────────────────────────────
// Banner de la Home (SOLO italiano). Se obtiene scrapeando la home de la web:
// el <img> del bloque banner (uploads/AAAA/MM/banner-*) y, si lo lleva, su
// enlace. Refleja lo que el equipo ponga en WordPress aunque cambie el nombre
// del archivo. En web el HTML se pide por el proxy del preview (CORS).
// ─────────────────────────────────────────────────────────────────────────
class HomeBanner {
  final String imageUrl;
  final String? linkUrl; // null = banner sin enlace (no clicable)
  const HomeBanner({required this.imageUrl, this.linkUrl});
}

String get _homeHtmlUrl => kIsWeb
    ? Uri.base.resolve('/home-html').toString()
    : 'https://www.unicaradio.it/';

const _kHomeBannerCache = 'home_banner';

// <a href=...>? seguido del <img ... src=".../uploads/AAAA/MM/banner-...">.
// El <a> es OPCIONAL (a veces el banner no lleva enlace). Los thumbnails de
// artículo no casan (su nombre no empieza por "banner-" tras la carpeta de fecha).
final _bannerRe = RegExp(
    r'(?:<a\b[^>]*\bhref="([^"]+)"[^>]*>\s*)?'
    r'<img\b[^>]*\bsrc="([^"]*wp-content/uploads/\d{4}/\d{2}/banner-[^"]+?)"',
    caseSensitive: false);

HomeBanner? _parseHomeBanner(String html) {
  final m = _bannerRe.firstMatch(html);
  if (m == null) return null;
  var img = m.group(2)!;
  if (!img.startsWith('http')) {
    img = 'https://www.unicaradio.it${img.startsWith('/') ? '' : '/'}$img';
  }
  final link = m.group(1);
  final validLink = (link != null && link.startsWith('http')) ? link : null;
  return HomeBanner(imageUrl: img, linkUrl: validLink);
}

HomeBanner? _readCachedBanner(SharedPreferences prefs) {
  final c = prefs.getString(_kHomeBannerCache);
  if (c == null) return null;
  try {
    final m = jsonDecode(c) as Map<String, dynamic>;
    return HomeBanner(
        imageUrl: m['image'] as String, linkUrl: m['link'] as String?);
  } catch (_) {
    return null;
  }
}

/// Banner cacheado (SÍNCRONO): se muestra AL INSTANTE mientras el fetch fresco
/// termina (el home de la web está mal optimizado y tarda). null si no es
/// italiano o si aún no se ha cacheado ninguno.
final cachedHomeBannerProvider = Provider<HomeBanner?>((ref) {
  if (ref.watch(langProvider) != AppLang.it) return null;
  return _readCachedBanner(ref.watch(sharedPreferencesProvider));
});

/// Banner de la Home (fetch fresco): null si el idioma no es italiano o no hay
/// banner. En fallo/timeout devuelve el último cacheado. La UI muestra primero
/// [cachedHomeBannerProvider] y lo sustituye con este cuando llega.
final homeBannerProvider = FutureProvider<HomeBanner?>((ref) async {
  if (ref.watch(langProvider) != AppLang.it) return null;
  final prefs = ref.watch(sharedPreferencesProvider);
  final cached = _readCachedBanner(prefs);

  // Dio propio: sin el baseUrl /wp-json ni el interceptor de salud del backend
  // (un fallo aquí no debe marcar "backend caído").
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    // El home de Aruba responde 500 pero CON el HTML completo (bug del plugin
    // de eventos que marca la página como error tras renderizarla). Aceptamos
    // cualquier status < 600 para leer el body y extraer el banner igualmente.
    validateStatus: (status) => status != null && status < 600,
    // Polylang redirige la home RAIZ segun el idioma del navegador; sin este
    // header la mandaria a la home EN INGLES (que no lleva el banner italiano).
    headers: {'Accept-Language': 'it-IT,it;q=0.9'},
  ));
  // Reintentos: el home es LENTO y a veces devuelve el 500 SIN el HTML completo
  // (o da timeout). Reintentamos unas veces para no depender de que el usuario
  // recargue a mano. Como el cacheado ya se muestra, esto ocurre por detrás.
  // (Sin cache-buster: el banner cambia rara vez y el home cacheado del CDN basta.)
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final res = await dio.get<dynamic>(_homeHtmlUrl,
          options: Options(responseType: ResponseType.plain));
      final banner = _parseHomeBanner((res.data ?? '').toString());
      if (banner != null) {
        prefs.setString(_kHomeBannerCache,
            jsonEncode({'image': banner.imageUrl, 'link': banner.linkUrl}));
        return banner;
      }
    } catch (_) {
      // red/timeout → reintentamos
    }
    // Backoff: el home tarda 4-10 s en responder y a veces necesita respirar
    // entre intentos → esperamos 4 s y luego 8 s. Es invisible (ya se muestra el
    // banner cacheado); estos reintentos ocurren por detrás.
    if (attempt < 2) {
      await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
    }
  }
  return cached; // tras los reintentos: el último conocido (o null)
});

// ─────────────────────────────────────────────────────────────────────────
// Banner promo DENTRO de una noticia (slot "stream-item-above-post" de la web),
// SOLO italiano y SOLO al abrir la noticia (no se pre-cargan todas). Mismo truco
// que el home: Aruba responde 500 pero con el HTML completo. Se cachea el
// resultado por noticia (banner o "sin banner") con caducidad suave, para no
// re-scrapear en cada apertura.
// ─────────────────────────────────────────────────────────────────────────
const _kArticleBannerTtlMs = 6 * 60 * 60 * 1000; // 6 h

// Dentro del slot above-post: <span title>? <a href>? <img src=".../uploads/...">.
final _abovePostImgRe = RegExp(
    r'(?:<a\b[^>]*\bhref="([^"]+)"[^>]*>\s*)?'
    r'<img\b[^>]*\bsrc="([^"]*wp-content/uploads/[^"]+?)"',
    caseSensitive: false);

HomeBanner? _parseArticleBanner(String html) {
  final i = html.toLowerCase().indexOf('stream-item-above-post');
  if (i < 0) return null; // esta noticia no tiene el slot → sin banner
  final end = (i + 900) > html.length ? html.length : i + 900;
  final m = _abovePostImgRe.firstMatch(html.substring(i, end));
  if (m == null) return null;
  final img = m.group(2)!;
  if (!img.startsWith('http')) return null;
  final link = m.group(1);
  return HomeBanner(
      imageUrl: img,
      linkUrl: (link != null && link.startsWith('http')) ? link : null);
}

/// Banner de una noticia (por su URL/permalink). null si no es italiano, la URL
/// está vacía o la noticia no tiene banner. Se pide SOLO al abrir la noticia y
/// se cachea el resultado (con caducidad) para no re-scrapear en cada apertura.
final articleBannerProvider =
    FutureProvider.autoDispose.family<HomeBanner?, String>((ref, url) async {
  if (ref.watch(langProvider) != AppLang.it || url.isEmpty) return null;
  final prefs = ref.watch(sharedPreferencesProvider);
  final key = 'art_banner:$url';

  Map<String, dynamic>? cache;
  final c = prefs.getString(key);
  if (c != null) {
    try {
      cache = jsonDecode(c) as Map<String, dynamic>;
    } catch (_) {}
  }
  HomeBanner? cachedBanner;
  if (cache != null && cache['image'] != null) {
    cachedBanner = HomeBanner(
        imageUrl: cache['image'] as String, linkUrl: cache['link'] as String?);
  }
  // Caché fresca → NO re-scrapeamos (devuelve el banner, o null = sin banner).
  final ts = (cache?['ts'] as num?)?.toInt() ?? 0;
  if (cache != null &&
      DateTime.now().millisecondsSinceEpoch - ts < _kArticleBannerTtlMs) {
    return cachedBanner;
  }

  // Fetch del HTML del post (en web por el proxy; acepta el 500 con body).
  final fetchUrl = kIsWeb
      ? Uri.base.resolve('/article-html?url=${Uri.encodeComponent(url)}').toString()
      : url;
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (status) => status != null && status < 600,
    headers: {'Accept-Language': 'it-IT,it;q=0.9'},
  ));
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final res = await dio.get<dynamic>(fetchUrl,
          options: Options(responseType: ResponseType.plain));
      final html = (res.data ?? '').toString();
      // Solo cacheamos el resultado si bajó una página real (no un 500 vacío).
      if (html.length > 5000) {
        final banner = _parseArticleBanner(html);
        prefs.setString(
            key,
            jsonEncode({
              'image': banner?.imageUrl,
              'link': banner?.linkUrl,
              'ts': DateTime.now().millisecondsSinceEpoch,
            }));
        return banner;
      }
    } catch (_) {
      // red/timeout → reintentamos
    }
    if (attempt < 2) await Future.delayed(Duration(seconds: 4 * (attempt + 1)));
  }
  return cachedBanner; // fetch falló → lo último conocido (o null)
});

/// Categorías para los chips de Noticias (las más usadas primero).
/// Depende del idioma: Polylang devuelve nombres traducidos según el parámetro `lang`.
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final dio = ref.watch(dioProvider);
  final lang = ref.watch(langProvider).code;
  final res = await dio.get('/wp/v2/categories', queryParameters: {
    'per_page': 30,
    'orderby': 'count',
    'order': 'desc',
    '_fields': 'id,name,count',
    // SIEMPRE filtramos por idioma (incl. 'it'): sin el parámetro, Polylang
    // devuelve categorías de TODOS los idiomas y se colaban chips de otros
    // idiomas en la vista italiana.
    'lang': lang,
  });
  final list = (res.data as List).cast<Map<String, dynamic>>();
  return list.map(Category.fromJson).where((c) => c.count > 0).toList();
});

/// Mapa id→nombre para resolver la categoría de cada post sin `_embed`.
final categoriesMapProvider = FutureProvider<Map<int, String>>((ref) async {
  final cats = await ref.watch(categoriesProvider.future);
  return {for (final c in cats) c.id: c.name};
});

/// Categoría seleccionada en Noticias (null = todas / Home).
final selectedCategoryProvider = StateProvider<int?>((_) => null);

/// Carga UNA página de noticias de forma LIGERA:
///  1) posts sin `_embed` (solo ids/títulos) — pocos KB,
///  2) las URLs de imagen en una sola llamada batch a `/media`,
///  3) la categoría se resuelve con el mapa de categorías.
/// El sitio usa Polylang: la API devuelve el MISMO artículo en cada idioma
/// como posts distintos. El italiano (idioma por defecto) NO lleva prefijo de
/// idioma en la URL; las traducciones sí (`/es/`, `/en/`, `/zh/`...).
/// Filtramos al idioma seleccionado por ese prefijo (it = sin prefijo).
/// Tope superior para pedir posts: descarta los que tienen FECHA FUTURA.
///
/// La web publica traducciones automáticas fechadas semanas por delante y, como
/// WordPress ordena por fecha, copaban enteras las primeras páginas: en agosto
/// de 2026 solo había 1 post italiano entre los 100 primeros, así que Inicio y
/// Noticias salían vacíos en italiano. El margen de 12 h evita que la zona
/// horaria del móvil esconda una noticia recién publicada (lo que filtramos de
/// verdad son semanas de desfase, no horas).
String _notFutureCutoff() =>
    DateTime.now().add(const Duration(hours: 12)).toIso8601String();

final _langPrefix = RegExp(r'unicaradio\.it/([a-z]{2})/');
bool _matchesLang(Map<String, dynamic> p, String code) {
  final m = _langPrefix.firstMatch((p['link'] as String?) ?? '');
  final postLang = m?.group(1) ?? 'it';
  return postLang == code;
}

Future<({List<Article> items, bool hasMore})> _fetchPage(
  Dio dio, {
  int? categoryId,
  required int page,
  required String langCode,
  required Map<int, String> catNames,
}) async {
  // El reparto por idiomas NO es estable: en junio de 2026 el ~60% de los posts
  // eran italianos y bastaba pedir 20 en crudo; hoy cada noticia se publica en 9
  // idiomas y el italiano es ~14%. Pedimos el máximo para todos (100 ≈ 16 KB) y
  // el controlador sigue paginando si aún no reúne bastantes del idioma.
  const rawPerPage = 100;
  final res = await dio.get('/wp/v2/posts', queryParameters: {
    'per_page': rawPerPage,
    'page': page,
    'before': _notFutureCutoff(), // sin esto el italiano sale vacío
    '_fields': 'id,date,link,title,excerpt,featured_media,categories,_links',
    if (categoryId != null) 'categories': categoryId,
  });
  final all = (res.data as List).cast<Map<String, dynamic>>();
  final posts = all.where((p) => _matchesLang(p, langCode)).toList();
  final totalPages =
      int.tryParse('${res.headers.value('x-wp-totalpages')}') ?? page;

  final mediaOf = <int, int>{}; // postId → mediaId (posts con imagen propia)
  final mediaIds = <int>{};
  final noImage = <Map<String, dynamic>>[];

  for (final p in posts) {
    final id = (p['id'] as num?)?.toInt() ?? 0;
    final m = (p['featured_media'] as num?)?.toInt() ?? 0;
    if (m > 0) {
      mediaOf[id] = m;
      mediaIds.add(m);
    } else if (langCode != 'it') {
      noImage.add(p);
    }
  }

  // Las traducciones (es/en/…) tienen featured_media=0 en Polylang Free:
  // la imagen está solo en el post italiano original.
  //
  // Estrategia en dos pasos:
  //  A) _links.pll_translate: Polylang expone el ID exacto del original.
  //     Si está disponible, lo usamos → imagen 100% correcta.
  //  B) Proximidad de IDs (sin límite de distancia): tomamos el italiano
  //     con el ID más alto < pid, con "mark-as-used" para evitar que la
  //     misma imagen italiana se repita en varios posts traducidos.
  final itPostToMedia = <int, int>{}; // italianPostId → mediaId

  // Paso A: IDs exactos desde _links.pll_translate
  final exactItIdOf = <int, int>{}; // spanishPostId → italianPostId
  final extraItIds = <int>{}; // IDs de originales italianos no en este batch
  if (langCode != 'it' && noImage.isNotEmpty) {
    final allIds = all.map((p) => (p['id'] as num?)?.toInt() ?? 0).toSet();
    for (final p in noImage) {
      final pid = (p['id'] as num?)?.toInt() ?? 0;
      final links = p['_links'];
      if (links is Map) {
        for (final item in (links['pll_translate'] as List? ?? [])) {
          if (item is Map && item['lang'] == 'it') {
            final href = (item['href'] as String?) ?? '';
            final m = RegExp(r'/posts/(\d+)').firstMatch(href);
            final itId = m != null ? int.tryParse(m.group(1)!) : null;
            if (itId != null) {
              exactItIdOf[pid] = itId;
              if (!allIds.contains(itId)) extraItIds.add(itId);
            }
            break;
          }
        }
      }
    }
  }

  // Paso B: pool de italianos del batch actual (siempre, como respaldo)
  if (langCode != 'it' && noImage.isNotEmpty) {
    for (final p in all) {
      if (!_matchesLang(p, 'it')) continue;
      final id = (p['id'] as num?)?.toInt() ?? 0;
      final m = (p['featured_media'] as num?)?.toInt() ?? 0;
      if (m > 0) {
        itPostToMedia[id] = m;
        mediaIds.add(m);
      }
    }
    // Originales italianos encontrados vía _links pero ausentes del batch
    if (extraItIds.isNotEmpty) {
      try {
        final pr = await dio.get('/wp/v2/posts', queryParameters: {
          'include': extraItIds.join(','),
          'per_page': extraItIds.length,
          '_fields': 'id,featured_media',
        });
        for (final x in (pr.data as List).cast<Map<String, dynamic>>()) {
          final id = (x['id'] as num).toInt();
          final m = (x['featured_media'] as num?)?.toInt() ?? 0;
          if (m > 0) {
            itPostToMedia[id] = m;
            mediaIds.add(m);
          }
        }
      } catch (_) {}
    }
  }

  // Una sola llamada batch para TODOS los media IDs (propios + italianos).
  final media = <int, String>{};
  if (mediaIds.isNotEmpty) {
    final mr = await dio.get('/wp/v2/media', queryParameters: {
      'include': mediaIds.join(','),
      'per_page': mediaIds.length,
      '_fields': 'id,source_url',
    });
    for (final x in (mr.data as List)) {
      media[(x['id'] as num).toInt()] = (x['source_url'] as String?) ?? '';
    }
  }

  // Pool de imágenes italianas: postId → imageUrl
  final italianPool = <int, String>{};
  itPostToMedia.forEach((postId, mediaId) {
    final url = media[mediaId];
    if (url != null && url.isNotEmpty) italianPool[postId] = url;
  });
  final sortedItIds = italianPool.keys.toList()..sort();

  // Asignación de imágenes: procesamos en orden ascendente de ID para que
  // el post más cercano al original italiano tenga prioridad.
  // Cada original italiano se usa como máximo una vez (usedItIds).
  final usedItIds = <int>{};
  final imageByPid = <int, String>{};
  final sortedPosts =
      posts.map((p) => (p['id'] as num?)?.toInt() ?? 0).toList()..sort();
  for (final pid in sortedPosts) {
    if (mediaOf.containsKey(pid)) continue; // ya tiene imagen propia
    // Prioridad 1: match exacto desde _links.pll_translate
    final exactItId = exactItIdOf[pid];
    if (exactItId != null) {
      final url = italianPool[exactItId];
      if (url != null && !usedItIds.contains(exactItId)) {
        imageByPid[pid] = url;
        usedItIds.add(exactItId);
        continue;
      }
    }
    // Prioridad 2: italiano más cercano por ID (sin límite de distancia)
    int? bestIt;
    for (final id in sortedItIds) {
      if (id < pid && !usedItIds.contains(id)) bestIt = id;
    }
    if (bestIt != null) {
      imageByPid[pid] = italianPool[bestIt]!;
      usedItIds.add(bestIt);
    }
  }

  final items = posts.map((p) {
    final pid = (p['id'] as num?)?.toInt() ?? 0;
    final mid = mediaOf[pid] ?? 0;
    final cats =
        ((p['categories'] as List?) ?? const []).map((e) => (e as num).toInt());
    var cat = '';
    for (final id in cats) {
      final n = catNames[id];
      if (n != null && n.isNotEmpty) {
        cat = n;
        break;
      }
    }
    final imageUrl = mid > 0 ? media[mid] : imageByPid[pid];
    return Article.light(p, imageUrl: imageUrl, category: cat);
  }).toList();

  return (items: items, hasMore: page < totalPages);
}

/// Estado paginado de una lista de noticias.
class ArticlesState {
  final List<Article> items;
  final int page;
  final bool hasMore;
  final bool initialLoading;
  final bool loadingMore;
  final Object? error;

  const ArticlesState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.initialLoading = true,
    this.loadingMore = false,
    this.error,
  });

  ArticlesState copyWith({
    List<Article>? items,
    int? page,
    bool? hasMore,
    bool? initialLoading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      ArticlesState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        initialLoading: initialLoading ?? this.initialLoading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Controlador paginado por categoría (`null` = todas / Home).
/// `loadMore()` añade los 10 siguientes.
class ArticlesController extends AutoDisposeFamilyNotifier<ArticlesState, int?> {
  static const _minFirst = 8; // mínimo a mostrar en la primera carga
  bool _busy = false; // M2: evita que _loadFirst y loadMore se solapen

  @override
  ArticlesState build(int? categoryId) {
    ref.watch(langProvider); // las noticias siguen el idioma elegido
    _loadFirst();
    return const ArticlesState();
  }

  Future<void> _loadFirst() async {
    if (_busy) return; // M2: ya hay una carga en curso → no la pisamos
    _busy = true;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final code = ref.read(langProvider).code;
      final cacheKey = 'news_${code}_${arg ?? 'all'}';

      // 1) Caché al instante (si la hay) → la app abre sin esperar.
      final cached = _cacheRead(prefs, cacheKey);
      if (cached != null && cached.isNotEmpty) {
        state = ArticlesState(
            items: cached.map(Article.fromCache).toList(),
            page: 1,
            hasMore: true,
            initialLoading: false);
      } else {
        state = const ArticlesState(initialLoading: true);
      }

      // 2) Refresca en segundo plano y re-guarda.
      try {
        final cats = await ref.read(categoriesMapProvider.future);
        final dio = ref.read(dioProvider);
        // Acumula páginas hasta tener ~8 (idiomas con pocas traducciones traen
        // pocos artículos por página). Dedup por id por si entran posts nuevos.
        final items = <Article>[];
        final seen = <int>{};
        var page = 0;
        var hasMore = true;
        while (items.length < _minFirst && hasMore && page < 4) {
          page++;
          final r = await _fetchPage(dio,
              categoryId: arg, page: page, langCode: code, catNames: cats);
          for (final a in r.items) {
            if (seen.add(a.id)) items.add(a);
          }
          hasMore = r.hasMore;
        }
        state = ArticlesState(
            items: items, page: page, hasMore: hasMore, initialLoading: false);
        _cacheWrite(prefs, cacheKey, items.map((a) => a.toCache()).toList());
      } catch (e) {
        // Si ya mostramos caché, la mantenemos; si no, error.
        if (state.items.isEmpty) {
          state =
              ArticlesState(initialLoading: false, hasMore: false, error: e);
        }
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    // M2: no solapar con _loadFirst ni con otro loadMore.
    if (_busy || state.loadingMore || state.initialLoading || !state.hasMore) {
      return;
    }
    _busy = true;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final cats = await ref.read(categoriesMapProvider.future);
      final code = ref.read(langProvider).code;
      // M12: la paginación de WP es CRUDA (mezcla idiomas); una página puede
      // traer 0 del idioma activo. Pedimos páginas hasta juntar ~8 NUEVOS
      // (dedup por id) o agotar, para que "Ver más" no se quede pegado ni
      // duplique al insertarse posts nuevos al principio.
      final existing = {for (final a in state.items) a.id};
      final fresh = <Article>[];
      var page = state.page;
      var hasMore = state.hasMore;
      var tries = 0;
      while (fresh.length < _minFirst && hasMore && tries < 4) {
        tries++;
        page++;
        final r = await _fetchPage(ref.read(dioProvider),
            categoryId: arg, page: page, langCode: code, catNames: cats);
        hasMore = r.hasMore;
        for (final a in r.items) {
          if (existing.add(a.id)) fresh.add(a);
        }
      }
      state = state.copyWith(
        items: [...state.items, ...fresh],
        page: page,
        hasMore: hasMore,
        loadingMore: false,
      );
    } catch (e) {
      // M6: NO tragar el error — lo guardamos para que la UI lo muestre/reintente.
      state = state.copyWith(loadingMore: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> refresh() => _loadFirst();
}

final articlesControllerProvider =
    NotifierProvider.family.autoDispose<ArticlesController, ArticlesState, int?>(
        ArticlesController.new);

// --- Búsqueda ---
// Estado del texto buscado (uno por pantalla: Inicio, Noticias, Podcast).
final homeQueryProvider = StateProvider<String>((_) => '');
final newsQueryProvider = StateProvider<String>((_) => '');
final podcastQueryProvider = StateProvider<String>((_) => '');
// 0=todos, 1=podcast (sin entrevistas), 2=entrevistas
final podcastSectionProvider = StateProvider<int>((_) => 0);

/// Índice de búsqueda: lista LIGERA (id/título/extracto/fecha/link, SIN imágenes)
/// de muchos artículos, para buscar en cliente sobre "todo" al instante. Se
/// descarga en 2º plano (crece en vivo), se cachea y es por idioma.
///
/// Para italiano usa una VENTANA TEMPORAL deslizante (~18 meses) con
/// actualización incremental: solo trae lo nuevo en la cabeza y extiende la
/// cola si hace falta. Para otros idiomas (pocas traducciones) usa un tope por
/// cantidad, igual que antes.
class SearchIndex extends Notifier<List<Article>> {
  static const _window = Duration(days: 540); // ~18 meses (italiano)
  static const _maxPages = 40; // cap de seguridad
  static const _targetItems = 1200; // tope por cantidad (no-italiano)
  static const _refreshCooldown = Duration(minutes: 15);

  @override
  List<Article> build() {
    final code = ref.watch(langProvider).code;
    final prefs = ref.read(sharedPreferencesProvider);
    final cached = _cacheRead(prefs, 'searchindex_$code')
            ?.map(Article.fromCache)
            .toList() ??
        <Article>[];
    _refresh(code, cached);
    return cached; // disponible al instante (lo de la sesión anterior)
  }

  Future<void> _refresh(String code, List<Article> initial) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final dio = ref.read(dioProvider);

    final tsKey = 'searchindex_${code}_ts';
    final lastTs = DateTime.tryParse(prefs.getString(tsKey) ?? '');
    if (lastTs != null &&
        DateTime.now().difference(lastTs) < _refreshCooldown) {
      return;
    }

    final isItalian = code == 'it';
    final cutoff = isItalian ? DateTime.now().subtract(_window) : null;
    final byId = {for (final a in initial) a.id: a};

    // Petición con un reintento automático: un error puntual (502, timeout)
    // no debe matar toda la descarga.
    Future<Response<dynamic>?> fetchPage(
        Map<String, dynamic> params) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await dio.get('/wp/v2/posts', queryParameters: params);
        } catch (_) {
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 3));
          }
        }
      }
      return null; // ambos intentos fallaron
    }

    try {
      var page = 0;
      var totalPages = _maxPages;
      var anyOk = false; // L6: ¿bajamos al menos una página con éxito?

      // Fase 1 — cabeza incremental: añade artículos nuevos (ID no visto);
      // para cuando no hay novedades o se llega al límite de la ventana.
      while (page < _maxPages) {
        page++;
        final res = await fetchPage({
          'per_page': 100,
          'page': page,
          // Igual que en _fetchPage: los posts con fecha futura ocupaban la
          // página 1 entera, así que "added == 0" cortaba el bucle de cabeza y
          // el índice italiano dejaba de incorporar noticias nuevas.
          'before': _notFutureCutoff(),
          '_fields': 'id,date,link,title,excerpt',
        });
        if (res == null) break; // fallo de red → salir de Fase 1, continuar con lo que hay
        anyOk = true;

        final list = (res.data as List).cast<Map<String, dynamic>>();
        totalPages =
            int.tryParse('${res.headers.value('x-wp-totalpages')}') ??
                totalPages;

        var added = 0;
        var reachedCutoff = false;
        for (final p in list) {
          if (!_matchesLang(p, code)) continue;
          final a = Article.light(p);
          if (cutoff != null && a.date.isBefore(cutoff)) {
            reachedCutoff = true;
            continue;
          }
          if (!byId.containsKey(a.id)) {
            byId[a.id] = a;
            added++;
          }
        }

        final all = byId.values.toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        state = all; // L17: actualiza la UI en vivo, pero NO reescribe el blob
        // de caché en cada página (se persiste una sola vez al final).

        if (page >= totalPages) break;
        // Solo cortamos por "pagina sin novedades" en italiano (la Fase 2 hace
        // backfill con cursor). En otros idiomas las traducciones son escasas y
        // una pagina cruda de 100 posts puede no traer NINGUNA del idioma → no
        // debemos parar aun (seguimos hasta totalPages / _targetItems / _maxPages).
        if (isItalian && added == 0) break;
        if (reachedCutoff) break;
        if (!isItalian && all.length >= _targetItems) break;

        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Fase 2 — backfill con cursor de fecha (solo italiano):
      // usa ?before= para saltar directamente al rango no cacheado, evitando
      // re-descargar páginas que ya están en byId.
      if (isItalian && cutoff != null && byId.isNotEmpty) {
        var cursor = byId.values
            .reduce((a, b) => a.date.isBefore(b.date) ? a : b)
            .date;
        var backfillPage = 0;
        while (cursor.isAfter(cutoff) && backfillPage < _maxPages) {
          backfillPage++;
          final res = await fetchPage({
            'per_page': 100,
            'before': cursor.toIso8601String(),
            'orderby': 'date',
            'order': 'desc',
            '_fields': 'id,date,link,title,excerpt',
          });
          if (res == null) break;
          final list = (res.data as List).cast<Map<String, dynamic>>();
          if (list.isEmpty) break;

          // El cursor avanza por la fecha del post más antiguo del lote
          // (cualquier idioma), garantizando que cada llamada trae contenido nuevo.
          final rawOldest =
              DateTime.tryParse(list.last['date'] as String? ?? '');
          if (rawOldest == null || !rawOldest.isBefore(cursor)) break;

          var reachedCutoff = false;
          for (final p in list) {
            if (!_matchesLang(p, code)) continue;
            final a = Article.light(p);
            if (a.date.isBefore(cutoff)) {
              reachedCutoff = true;
              continue;
            }
            if (!byId.containsKey(a.id)) byId[a.id] = a;
          }

          final all = byId.values.toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          state = all; // L17: en vivo; se persiste una sola vez al final
          cursor = rawOldest;

          if (reachedCutoff) break;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }

      // Poda: eliminar artículos fuera de la ventana.
      if (cutoff != null) {
        byId.removeWhere((_, a) => a.date.isBefore(cutoff));
      }

      final result = byId.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      state = result;
      // L17: única escritura del blob completo (antes se reescribía por página).
      _cacheWrite(prefs, 'searchindex_$code',
          result.map((a) => a.toCache()).toList());
      // L6: solo activamos el cooldown de 15 min si de verdad bajamos algo; si la
      // red falló en la 1ª página, dejamos que se reintente en la próxima apertura.
      if (anyOk) prefs.setString(tsKey, DateTime.now().toIso8601String());
    } catch (_) {}
  }
}

final searchIndexProvider =
    NotifierProvider<SearchIndex, List<Article>>(SearchIndex.new);

/// Respaldo "buscar en todo el archivo": consulta `?search=` del servidor, que
/// SÍ busca en todo el histórico (no solo en la ventana del índice) pero es
/// LENTA en este Aruba (~varios segundos). Por eso NO se dispara en cada tecla:
/// `archiveQueryProvider` guarda la consulta para la que el usuario pidió
/// expresamente buscar en el archivo (al pulsar el botón), y la UI solo observa
/// `archiveSearchProvider` para esa consulta. Resultados de texto (sin imagen).
final archiveQueryProvider = StateProvider<String>((_) => '');

/// Dio dedicado a la búsqueda en archivo. La consulta `?search=` de WordPress
/// es LENTA en este Aruba (~18-20s) y NO emite progreso hasta que responde; en
/// web, dio aborta a los `connectTimeout` (15s del dio normal) si el server no
/// ha empezado a responder, cortando la búsqueda. Como `connectTimeout` solo se
/// fija en `BaseOptions` (no por petición), usamos un Dio aparte con timeouts
/// largos. En móvil no hay este corte, pero los 60s tampoco molestan.
final _archiveDioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    baseUrl: 'https://www.unicaradio.it/wp-json',
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));
});

final archiveSearchProvider = FutureProvider.autoDispose
    .family<List<Article>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const <Article>[];
  final dio = ref.watch(_archiveDioProvider);
  final code = ref.watch(langProvider).code;

  // Un reintento: Aruba (al 110% de cuota) puede dar un 502 puntual. Además, si
  // el 1er intento se cortó pero disparó la caché del server, el 2º vuela.
  Response<dynamic>? res;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      res = await dio.get('/wp/v2/posts', queryParameters: {
        'search': q,
        'per_page': 30, // los 30 más relevantes; suficiente como respaldo
        'orderby': 'relevance',
        '_fields': 'id,date,link,title,excerpt',
      });
      break;
    } catch (_) {
      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
      } else {
        rethrow; // ambos intentos fallaron → el provider queda en error
      }
    }
  }
  final all = (res!.data as List).cast<Map<String, dynamic>>();
  return all
      .where((p) => _matchesLang(p, code))
      .map((p) => Article.light(p))
      .toList();
});

/// Contenido completo de un artículo (se pide al abrir el detalle).
final articleContentProvider =
    FutureProvider.autoDispose.family<String, int>((ref, id) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/wp/v2/posts/$id',
      queryParameters: {'_fields': 'content'});
  final html = (res.data['content']?['rendered'] as String?) ?? '';
  return html;
});

/// Imagen de cabecera de un artículo, por id. La usa el detalle cuando el
/// artículo viene del buscador (índice/archivo), que se carga ligero y SIN
/// imagen. Dos llamadas pequeñas: el post (featured_media) y el media (URL).
/// Devuelve null si no hay imagen o falla → el detalle deja el placeholder.
final articleImageProvider =
    FutureProvider.autoDispose.family<String?, int>((ref, id) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get('/wp/v2/posts/$id',
        queryParameters: {'_fields': 'featured_media'});
    final mediaId = (res.data['featured_media'] as num?)?.toInt() ?? 0;
    if (mediaId <= 0) return null;
    final mr = await dio.get('/wp/v2/media/$mediaId',
        queryParameters: {'_fields': 'source_url'});
    return mr.data['source_url'] as String?;
  } catch (_) {
    return null;
  }
});

/// Artículo completo por id. Lo usa el manejador de deep links para navegar
/// directamente a un artículo al abrir un enlace compartido.
final singleArticleProvider =
    FutureProvider.autoDispose.family<Article, int>((ref, id) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/wp/v2/posts/$id',
      queryParameters: {'_embed': true});
  return Article.fromJson(res.data as Map<String, dynamic>);
});

/// Feed de podcast (episodios reales con audio). Fuente: la taxonomía `series`
/// de la API REST (fetchPodcastEpisodes), NO el RSS: el RSS estaba topado en ~9
/// (los mismos 6-9 repetidos por los 9 idiomas de Polylang), mientras que
/// `series` pagina de verdad → ~50 episodios. El título sale en el idioma
/// elegido, con el italiano de respaldo (el audio siempre es italiano). Dedup
/// por audio → no se pierde ningún episodio por traducir. keepAlive: se descarga
/// una vez y lo comparten Home y la pestaña Podcast; refetch al cambiar de idioma.
final podcastFeedProvider = FutureProvider<List<PodcastEpisode>>((ref) async {
  return fetchPodcastEpisodes(ref.watch(dioProvider),
      langCode: ref.watch(langProvider).code);
});

/// Último episodio de podcast (para el "podcast del día"). Tolera fallos.
final latestEpisodeProvider =
    FutureProvider.autoDispose<PodcastEpisode?>((ref) async {
  try {
    final eps = await ref.watch(podcastFeedProvider.future);
    return eps.isEmpty ? null : eps.first;
  } catch (_) {
    return null;
  }
});

/// Estado paginado de la lista de episodios de podcast.
class PodcastState {
  final List<PodcastEpisode> items;
  final int page;
  final bool hasMore;
  final bool initialLoading;
  final bool loadingMore;
  final Object? error;

  const PodcastState({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.initialLoading = true,
    this.loadingMore = false,
    this.error,
  });

  PodcastState copyWith({
    List<PodcastEpisode>? items,
    int? page,
    bool? hasMore,
    bool? initialLoading,
    bool? loadingMore,
  }) =>
      PodcastState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        initialLoading: initialLoading ?? this.initialLoading,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

// --- Podcast desde el feed RSS (/feed/podcast) ---
// El endpoint /ssp/v1/episodes devuelve TODOS los posts del blog (casi sin
// audio). El feed RSS lista solo los episodios REALES, con audio + imagen
// propia + duración. Filtramos por idioma con el mismo prefijo de URL.

String? _rssText(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c.innerText;
  }
  return null;
}

XmlElement? _rssChild(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

DateTime _parsePubDate(String? s) {
  if (s == null || s.isEmpty) return DateTime.now();
  try {
    final cleaned = s.replaceAll(RegExp(r'\s*[+-]\d{4}$'), '').trim();
    return DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US').parseUtc(cleaned);
  } catch (_) {
    return DateTime.tryParse(s) ?? DateTime.now();
  }
}

/// Descarga y parsea el feed RSS de podcast. Solo episodios con audio, del
/// idioma indicado (it = sin prefijo de URL).
Future<List<PodcastEpisode>> fetchPodcastFeed(
  Dio dio, {
  required String langCode,
}) async {
  // El feed devuelve ~50 ítems por página. Con 9 idiomas Polylang, las
  // traducciones nuevas empujan los originales italianos hacia abajo del feed.
  // posts_per_rss=100 amplía la ventana; ?paged=N recorre páginas más antiguas.
  // Paramos SOLO cuando todos los ítems de una página ya estaban vistos
  // globalmente (el servidor devuelve la misma página → no soporta paginación).
  const maxPages = 10;
  final out = <PodcastEpisode>[];
  final seenIds = <int>{}; // IDs de episodios italianos añadidos
  final globalGuids = <String>{}; // GUIDs de TODOS los ítems para detectar dups reales

  final base = kIsWeb
      ? Uri.base.resolve('/feed/podcast').toString()
      : 'https://www.unicaradio.it/feed/podcast';
  for (var page = 1; page <= maxPages; page++) {
    final url = page == 1
        ? '$base?posts_per_rss=100'
        : '$base?posts_per_rss=100&paged=$page';
    Response<dynamic> res;
    try {
      res = await dio.get(url, options: Options(responseType: ResponseType.plain));
    } catch (_) {
      break;
    }
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(res.data as String);
    } on XmlException catch (_) {
      break; // respuesta no-XML (ej. error HTML del servidor) → paramos
    }
    final items = doc.findAllElements('item').toList();
    if (items.isEmpty) break;

    var newGlobalItems = 0; // ítems que no estaban en páginas anteriores
    for (final item in items) {
      final link = _rssText(item, 'link') ?? '';
      final guid = _rssText(item, 'guid') ?? link;
      if (globalGuids.add(guid)) newGlobalItems++;

      final m = _langPrefix.firstMatch(link);
      final lang = m?.group(1) ?? 'it';
      if (lang != langCode) continue;

      final audio = _rssChild(item, 'enclosure')?.getAttribute('url');
      if (audio == null || audio.isEmpty) continue; // solo con audio real

      // El id del post está en la URL del audio: /podcast-download/<id>/...
      final pid = int.tryParse(
          RegExp(r'/podcast-download/(\d+)').firstMatch(audio)?.group(1) ?? '');
      final idMatch = RegExp(r'p=(\d+)').firstMatch(guid);
      final id = pid ?? (idMatch != null ? int.parse(idMatch.group(1)!) : link.hashCode);
      if (!seenIds.add(id)) continue;
      out.add(PodcastEpisode(
        id: id,
        title: stripHtml(_rssText(item, 'title') ?? ''),
        imageUrl: _rssChild(item, 'image')?.getAttribute('href'),
        audioUrl: audio,
        date: _parsePubDate(_rssText(item, 'pubDate')),
      ));
    }
    // Si todos los GUIDs de esta página ya estaban vistos → el servidor devuelve
    // la misma página con ?paged → no soporta paginación → paramos.
    if (page > 1 && newGlobalItems == 0) break;
  }

  // El RSS casi nunca trae imagen por episodio (1 de 50). Como los episodios SON
  // posts (con audio), sacamos la imagen destacada del post por su id, igual que
  // en noticias: lote de posts → featured_media → lote de media.
  final need = out
      .where((e) => (e.imageUrl == null || e.imageUrl!.isEmpty) && e.id > 100000)
      .map((e) => e.id)
      .toSet();
  if (need.isNotEmpty) {
    final imageOf = <int, String>{};
    try {
      final pr = await dio.get('/wp/v2/posts', queryParameters: {
        'include': need.join(','),
        'per_page': need.length,
        '_fields': 'id,featured_media',
      });
      final fmOf = <int, int>{};
      final mids = <int>{};
      for (final p in (pr.data as List).cast<Map<String, dynamic>>()) {
        final id = (p['id'] as num).toInt();
        final m = (p['featured_media'] as num?)?.toInt() ?? 0;
        if (m > 0) {
          fmOf[id] = m;
          mids.add(m);
        }
      }
      if (mids.isNotEmpty) {
        final mr = await dio.get('/wp/v2/media', queryParameters: {
          'include': mids.join(','),
          'per_page': mids.length,
          '_fields': 'id,source_url',
        });
        final urlOf = <int, String>{};
        for (final x in (mr.data as List)) {
          urlOf[(x['id'] as num).toInt()] = (x['source_url'] as String?) ?? '';
        }
        fmOf.forEach((id, mid) {
          final u = urlOf[mid];
          if (u != null && u.isNotEmpty) imageOf[id] = u;
        });
      }
    } catch (_) {}
    if (imageOf.isNotEmpty) {
      return out.map((e) {
        final u = imageOf[e.id];
        return (u != null && (e.imageUrl == null || e.imageUrl!.isEmpty))
            ? PodcastEpisode(
                id: e.id,
                title: e.title,
                imageUrl: u,
                audioUrl: e.audioUrl,
                date: e.date)
            : e;
      }).toList();
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────
// Podcast desde la API REST (taxonomía `series` de Seriously Simple Podcasting).
//
// El feed RSS es un callejón sin salida para la biblioteca del coche: devuelve
// SIEMPRE ~50 ítems que son los MISMOS 9 episodios repetidos en los 9 idiomas de
// Polylang, e ignora `posts_per_rss` y `paged` (con ?paged=2 reenvía la misma
// página). Techo real: 9 episodios italianos.
//
// Los episodios REALES son los posts de la taxonomía `series`: decenas de series
// con contenido y miles de posts, TODOS con `meta.audio_file` (el mp3 directo).
// `/wp/v2/posts?series=<ids>` SÍ pagina (100 por página) y el filtro admite
// varias series separadas por coma (OR).
//
// Polylang publica cada episodio en ~9 idiomas como posts distintos que
// COMPARTEN el mismo mp3 (solo cambian título y link) → deduplicamos por
// `audio_file` y nos quedamos con el título del idioma pedido, con el italiano
// de respaldo. (El parámetro `lang` NO filtra en esta ruta: devuelve el total
// igual, así que filtramos por el prefijo de idioma de la URL, como _matchesLang.)
// ─────────────────────────────────────────────────────────────────────────

/// IDs de las series de podcast que tienen episodios (count > 0).
Future<List<int>> _podcastSeriesIds(Dio dio) async {
  final res = await dio.get('/wp/v2/series',
      queryParameters: {'per_page': 100, '_fields': 'id,count'});
  return (res.data as List)
      .cast<Map<String, dynamic>>()
      .where((s) => ((s['count'] as num?)?.toInt() ?? 0) > 0)
      .map((s) => (s['id'] as num).toInt())
      .toList();
}

/// Episodios reales de podcast, los más nuevos primero. `pages` = páginas de 100
/// posts en crudo; cada una rinde ~23 episodios únicos (el resto son traducciones
/// del mismo audio). Con 3 páginas salen ~50 (el RSS solo daba 9). No subir
/// `pages` a lo bruto: Aruba va justo de cuota y Android Auto limita los hijos
/// por nodo.
Future<List<PodcastEpisode>> fetchPodcastEpisodes(
  Dio dio, {
  required String langCode,
  int pages = 3,
}) async {
  final List<int> seriesIds;
  try {
    seriesIds = await _podcastSeriesIds(dio);
  } catch (_) {
    return const <PodcastEpisode>[]; // sin red o error → nada (no revienta)
  }
  if (seriesIds.isEmpty) return const <PodcastEpisode>[];
  final series = seriesIds.join(',');

  final chosen = <String, PodcastEpisode>{}; // audio → episodio elegido
  final inLang = <String, bool>{}; // audio → su título ya está en el idioma pedido
  final mediaOf = <String, int>{}; // audio → id de la imagen destacada

  for (var page = 1; page <= pages; page++) {
    final Response<dynamic> res;
    try {
      res = await dio.get('/wp/v2/posts', queryParameters: {
        'series': series,
        'per_page': 100,
        'page': page,
        '_fields': 'id,date,link,title,featured_media,meta.audio_file',
      });
    } catch (_) {
      break; // sin red o fin de páginas → devolvemos lo que llevemos
    }
    // Una página con 2xx pero cuerpo no-array (error del plugin, HTML de Aruba)
    // NO debe reventar el cast y tirar los episodios ya acumulados: cortamos y
    // devolvemos lo que llevemos.
    if (res.data is! List) break;
    final list = (res.data as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) break;

    for (final p in list) {
      // fromJson ya lee meta.audio_file, title.rendered, link y date.
      final e = PodcastEpisode.fromJson(p);
      final audio = e.audioUrl ?? '';
      if (audio.isEmpty) continue;

      final lang = _langPrefix.firstMatch(e.link ?? '')?.group(1) ?? 'it';
      final wanted = lang == langCode;
      if (!wanted && lang != 'it') continue; // ni el idioma pedido ni el respaldo

      // Algunas traducciones vienen sin imagen destacada → guardamos la primera
      // válida que veamos para ese audio.
      final fm = (p['featured_media'] as num?)?.toInt() ?? 0;
      if (fm > 0 && !mediaOf.containsKey(audio)) mediaOf[audio] = fm;

      if (!chosen.containsKey(audio)) {
        chosen[audio] = e;
        inLang[audio] = wanted;
      } else if (wanted && inLang[audio] != true) {
        chosen[audio] = e; // sustituye el respaldo italiano por el idioma pedido
        inLang[audio] = true;
      }
    }
  }

  // Carátulas: featured_media → URL, en lotes de 100 (tope de per_page en WP).
  final urlOf = <int, String>{};
  final ids = mediaOf.values.toSet().toList();
  for (var i = 0; i < ids.length; i += 100) {
    final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
    try {
      final mr = await dio.get('/wp/v2/media', queryParameters: {
        'include': chunk.join(','),
        'per_page': chunk.length,
        '_fields': 'id,source_url',
      });
      for (final x in (mr.data as List)) {
        urlOf[(x['id'] as num).toInt()] = (x['source_url'] as String?) ?? '';
      }
    } catch (_) {
      // sin carátulas: mejor episodios sin imagen que ningún episodio
    }
  }

  final out = <PodcastEpisode>[];
  chosen.forEach((audio, e) {
    final img = urlOf[mediaOf[audio] ?? 0] ?? '';
    out.add(PodcastEpisode(
      id: e.id,
      title: e.title,
      imageUrl: img.isNotEmpty ? img : e.imageUrl,
      audioUrl: e.audioUrl,
      link: e.link,
      date: e.date,
    ));
  });
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
}

class PodcastController extends Notifier<PodcastState> {
  List<PodcastEpisode> _all = const [];
  bool _busy = false;
  static const _pageSize = 8;

  @override
  PodcastState build() {
    _loadFirst();
    return const PodcastState();
  }

  Future<void> _loadFirst() async {
    if (_busy) return;
    _busy = true;
    final prefs = ref.read(sharedPreferencesProvider);

    // 1) Caché al instante (si la hay).
    final cached = _cacheRead(prefs, 'podcast');
    if (cached != null && cached.isNotEmpty) {
      _all = cached.map(PodcastEpisode.fromCache).toList();
      state = PodcastState(
          items: _all.take(_pageSize).toList(),
          page: 1,
          hasMore: _all.length > _pageSize,
          initialLoading: false);
    } else {
      state = const PodcastState(initialLoading: true);
    }

    // 2) Refresca y re-guarda.
    try {
      _all = await ref.read(podcastFeedProvider.future);
      final first = _all.take(_pageSize).toList();
      state = PodcastState(
          items: first,
          page: 1,
          hasMore: _all.length > first.length,
          initialLoading: false);
      _cacheWrite(prefs, 'podcast', _all.map((e) => e.toCache()).toList());
    } catch (e) {
      if (state.items.isEmpty) {
        state = PodcastState(initialLoading: false, hasMore: false, error: e);
      }
    } finally {
      _busy = false;
    }
  }

  // El feed se descarga entero de una vez → la paginación es en cliente.
  Future<void> loadMore() async {
    if (state.initialLoading || !state.hasMore) return;
    final next = _all.take((state.page + 1) * _pageSize).toList();
    state = state.copyWith(
        items: next, page: state.page + 1, hasMore: _all.length > next.length);
  }

  Future<void> refresh() async {
    ref.invalidate(podcastFeedProvider);
    return _loadFirst();
  }
}

final podcastControllerProvider =
    NotifierProvider<PodcastController, PodcastState>(PodcastController.new);

/// Suscribe un email a la newsletter (The Newsletter Plugin: POST a `/?na=s`
/// con campos ne/ny/nr/nlang). En web pasa por el proxy del server de preview
/// (`/subscribe`); en móvil va directo (sin CORS). Devuelve true si fue OK.
Future<bool> subscribeNewsletter(Dio dio, String email, String lang) async {
  try {
    if (kIsWeb) {
      final url = Uri.base.resolve('/subscribe').toString();
      final r = await dio.post(url,
          data: {'email': email, 'lang': lang},
          options: Options(contentType: Headers.formUrlEncodedContentType));
      return r.data is Map && r.data['ok'] == true;
    }
    final r = await dio.post(
      'https://www.unicaradio.it/?na=s',
      data: {'ne': email, 'ny': '1', 'nr': 'widget', 'nlang': lang},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final code = r.statusCode ?? 0;
    return code >= 200 && code < 400;
  } catch (_) {
    return false;
  }
}
