import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../shared/widgets/article_tile.dart';
import '../../shared/widgets/load_more_button.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/search_results.dart';

/// Pestaña Noticias: buscador, chips de categoría (API) y lista paginada.
class NewsPage extends ConsumerWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    ref.listen(langProvider, (prev, next) {
      if (prev != null && prev != next) {
        ref.read(selectedCategoryProvider.notifier).state = null;
      }
    });
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: SearchField(query: newsQueryProvider, hint: s.searchHint),
          ),
          const Expanded(child: _NewsContent()),
        ],
      ),
    );
  }
}

class _NewsContent extends ConsumerWidget {
  const _NewsContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final query = ref.watch(newsQueryProvider).trim();

    if (query.isNotEmpty) return SearchResults(query: query);

    // Los chips de categoría son solo-italiano (ver categoriesProvider): en el
    // resto de idiomas hay una sola lista, sin nada entre lo que deslizar.
    if (lang != AppLang.it) return const _ArticleList(categoryId: null);

    // La clave por idioma recrea el pager (y su PageController) cuando cambian
    // las categorías, que dependen del idioma.
    return _CategoryPager(key: ValueKey(lang));
  }
}

/// Chips de categoría + lista paginada, sincronizados: deslizar en horizontal
/// pasa de una categoría a la siguiente y tocar un chip anima hasta su página.
/// `selectedCategoryProvider` se mantiene al día desde `onPageChanged` (única
/// fuente de verdad) para que sobreviva a una búsqueda y vuelta.
class _CategoryPager extends ConsumerStatefulWidget {
  const _CategoryPager({super.key});

  @override
  ConsumerState<_CategoryPager> createState() => _CategoryPagerState();
}

class _CategoryPagerState extends ConsumerState<_CategoryPager> {
  PageController? _pager;
  final _chipsScroll = ScrollController();
  final _chipKeys = <GlobalKey>[];
  int _page = 0;

  @override
  void dispose() {
    _pager?.dispose();
    _chipsScroll.dispose();
    super.dispose();
  }

  /// Arranca en la categoría que ya estuviera elegida (p.ej. al volver de una
  /// búsqueda), no siempre en "Todas".
  void _syncToSelection(List<int?> ids) {
    if (_pager != null) {
      // Si la lista de categorías se acorta, no dejamos una página fantasma.
      if (_page >= ids.length) {
        _page = ids.length - 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pager?.jumpToPage(_page);
        });
      }
      return;
    }
    final want = ids.indexOf(ref.read(selectedCategoryProvider));
    _page = want < 0 ? 0 : want;
    _pager = PageController(initialPage: _page);
  }

  void _onPageChanged(List<int?> ids, int i) {
    setState(() => _page = i);
    ref.read(selectedCategoryProvider.notifier).state = ids[i];
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealChip(i));
  }

  /// Deja el chip activo a la vista al deslizar (si no, se pierde de vista y no
  /// se sabe en qué categoría estás).
  void _revealChip(int i) {
    if (!mounted || i < 0 || i >= _chipKeys.length) return;
    final ctx = _chipKeys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);
    final catsAsync = ref.watch(categoriesProvider);

    // Sin categorías (cargando o error) se muestra la lista sola, como antes.
    final cats = catsAsync.valueOrNull;
    if (cats == null) {
      return _ArticleList(categoryId: ref.watch(selectedCategoryProvider));
    }

    final ids = <int?>[null, for (final c in cats) c.id];
    final labels = <String>[s.allChip, for (final c in cats) c.name];
    _syncToSelection(ids);
    while (_chipKeys.length < ids.length) {
      _chipKeys.add(GlobalKey());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: ListView.builder(
            controller: _chipsScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: labels.length,
            itemBuilder: (_, i) => _Chip(
              key: _chipKeys[i],
              label: labels[i],
              active: i == _page,
              onTap: () => _pager?.animateToPage(
                i,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
              ),
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pager,
            itemCount: ids.length,
            onPageChanged: (i) => _onPageChanged(ids, i),
            // Las páginas visitadas se mantienen vivas: al volver a una
            // categoría no se recarga de red ni se pierde el "cargar más".
            itemBuilder: (_, i) =>
                _KeepAlive(child: _ArticleList(categoryId: ids[i])),
          ),
        ),
      ],
    );
  }
}

/// Mantiene viva una página del PageView (si no, al salir de la vista se
/// destruye y su provider autoDispose vuelve a pedir la categoría a la API).
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Lista paginada de una categoría (`null` = todas).
class _ArticleList extends ConsumerWidget {
  final int? categoryId;
  const _ArticleList({required this.categoryId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final state = ref.watch(articlesControllerProvider(categoryId));
    final ctrl = ref.read(articlesControllerProvider(categoryId).notifier);

    if (state.initialLoading) return const _ListSkeleton();
    if (state.error != null && state.items.isEmpty) {
      return _ErrorBox(
          message: s.loadError, retry: s.retry, onRetry: ctrl.refresh);
    }
    if (state.items.isEmpty) {
      return Center(
          child: Text(s.noResults,
              style: const TextStyle(color: AppColors.mutedDark)));
    }
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: ctrl.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        itemCount: state.items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= state.items.length) {
            return LoadMoreButton(
                loading: state.loadingMore,
                label: s.loadMore,
                onTap: ctrl.loadMore);
          }
          return ArticleTile(article: state.items[i]);
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip(
      {super.key,
      required this.label,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.brand
                : (dark ? AppColors.surfaceDark : AppColors.surfaceLight),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Text(label,
              style: TextStyle(
                  color: active
                      ? Colors.white
                      : (dark ? const Color(0xFFB7BAC1) : AppColors.ink),
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Container(
            width: 92,
            height: 72,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 12,
                    width: 70,
                    color: Colors.white.withValues(alpha: .06)),
                const SizedBox(height: 8),
                Container(
                    height: 14,
                    width: double.infinity,
                    color: Colors.white.withValues(alpha: .06)),
                const SizedBox(height: 6),
                Container(
                    height: 14,
                    width: 180,
                    color: Colors.white.withValues(alpha: .06)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final String retry;
  final Future<void> Function() onRetry;
  const _ErrorBox(
      {required this.message, required this.retry, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: AppColors.mutedDark, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.mutedDark)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: Text(retry)),
        ],
      ),
    );
  }
}
