import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../features/article/article_detail_page.dart';
import '../util/text_search.dart';
import 'load_more_button.dart';

/// Quita duplicados por título normalizado: la web a veces publica el mismo
/// artículo varias veces (títulos idénticos, IDs distintos). Conserva el primero
/// de cada título (la lista viene ordenada por fecha desc → el más reciente).
/// `seen` permite arrastrar títulos ya mostrados (p.ej. del índice al archivo).
List<Article> _dedupeByTitle(List<Article> items, {Set<String>? seen}) {
  final s = seen ?? <String>{};
  final out = <Article>[];
  for (final a in items) {
    final key = normalizeForSearch(a.title).trim();
    if (key.isEmpty || s.add(key)) out.add(a);
  }
  return out;
}

/// Resultados de búsqueda sobre el índice local (instantáneo) con:
///  - **paginación**: muestra de [_pageSize] en [_pageSize] (aunque haya 1000
///    coincidencias solo pinta las primeras y un "Carica altro"),
///  - **contador** del total de coincidencias,
///  - **respaldo opcional**: un botón "buscar en todo el archivo" que lanza el
///    `?search=` del servidor (lento) para encontrar noticias más viejas que la
///    ventana del índice.
/// Lista de texto (sin imagen); al tocar abre el artículo completo.
class SearchResults extends ConsumerStatefulWidget {
  final String query;
  const SearchResults({super.key, required this.query});

  @override
  ConsumerState<SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<SearchResults> {
  static const _pageSize = 20; // resultados locales por "página"
  int _limit = _pageSize;

  @override
  void didUpdateWidget(SearchResults old) {
    super.didUpdateWidget(old);
    // Nueva búsqueda → volver a empezar por la primera página.
    if (old.query != widget.query) _limit = _pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);
    final index = ref.watch(searchIndexProvider);
    final q = widget.query.trim();

    if (index.isEmpty) {
      // El índice aún se está descargando (primera vez, sin caché).
      return const Center(
          child: CircularProgressIndicator(color: AppColors.brand));
    }

    final matched = index
        .where((a) => matchesQuery('${a.title} ${a.excerpt}', q))
        .toList();
    final localIds = {for (final a in matched) a.id};
    // Quita duplicados por título (la web tiene el mismo artículo repetido con
    // IDs distintos). `localTitles` recoge los ya mostrados para que el archivo
    // tampoco los repita.
    final localTitles = <String>{};
    final results = _dedupeByTitle(matched, seen: localTitles);
    final shown = results.take(_limit).toList();
    final hasMoreLocal = results.length > shown.length;

    final archiveQ = ref.watch(archiveQueryProvider);
    final archiveActive = q.isNotEmpty && archiveQ == q;

    final children = <Widget>[];

    // Cabecera: contador de coincidencias o "sin resultados".
    if (results.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 10),
        child: Text(s.resultsCount(results.length),
            style: const TextStyle(
                color: AppColors.mutedDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ));
    } else if (!archiveActive) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
            child: Text(s.noResults,
                style: const TextStyle(color: AppColors.mutedDark))),
      ));
    }

    for (final a in shown) {
      children.add(_SearchResultTile(article: a));
    }

    if (hasMoreLocal) {
      children.add(LoadMoreButton(
        loading: false,
        label: s.loadMore,
        onTap: () => setState(() => _limit += _pageSize),
      ));
    }

    // Respaldo: buscar en todo el archivo del servidor (lento, bajo demanda).
    children.add(_archiveSection(s, q, archiveActive, localIds, localTitles));

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: children,
    );
  }

  /// Sección de "buscar en todo el archivo": botón si no se ha lanzado; spinner
  /// + resultados (deduplicados contra el índice) si está activa.
  Widget _archiveSection(
      S s, String q, bool active, Set<int> localIds, Set<String> localTitles) {
    if (q.isEmpty) return const SizedBox.shrink();

    if (!active) {
      return Column(
        children: [
          const Divider(height: 28),
          TextButton.icon(
            onPressed: () => ref.read(archiveQueryProvider.notifier).state = q,
            icon: const Icon(Icons.travel_explore, size: 20),
            style: TextButton.styleFrom(foregroundColor: AppColors.brand),
            label: Text(s.searchArchiveBtn,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      );
    }

    final archive = ref.watch(archiveSearchProvider(q));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 28),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text(s.searchArchiveTitle.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.brandSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: .6)),
        ),
        ...archive.when(
          loading: () => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                const CircularProgressIndicator(color: AppColors.brand),
                const SizedBox(height: 14),
                Text(s.searchArchiveHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.mutedDark, fontSize: 13)),
              ]),
            ),
          ],
          error: (_, __) => [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(s.loadError,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.mutedDark)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(archiveSearchProvider(q)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: const BorderSide(color: AppColors.brand),
                  ),
                  child: Text(s.retry),
                ),
              ]),
            ),
          ],
          data: (list) {
            // Quita lo ya mostrado por el índice (por id) y los títulos
            // repetidos (la web duplica artículos con IDs distintos).
            final fresh = _dedupeByTitle(
                list.where((a) => !localIds.contains(a.id)).toList(),
                seen: localTitles);
            if (fresh.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: Text(s.searchArchiveEmpty,
                          style:
                              const TextStyle(color: AppColors.mutedDark))),
                ),
              ];
            }
            return [for (final a in fresh) _SearchResultTile(article: a)];
          },
        ),
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Article article;
  const _SearchResultTile({required this.article});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppColors.mutedDark : const Color(0xFF6B6E76);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ArticleDetailPage(article: article))),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15.5, height: 1.25)),
            if (article.excerpt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(article.excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.35)),
            ],
          ],
        ),
      ),
    );
  }
}
