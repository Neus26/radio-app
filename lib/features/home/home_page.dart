import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../shared/util/relative_time.dart';
import '../../shared/widgets/article_tile.dart';
import '../../shared/widgets/load_more_button.dart';
import '../../shared/widgets/remote_image.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/search_results.dart';
import '../article/article_detail_page.dart';
import '../podcast/podcast_notifier.dart';

/// Pantalla Inicio — contra la API REST (carga ligera + paginación).
class HomePage extends ConsumerWidget {
  final VoidCallback? onGoToPodcast;
  const HomePage({super.key, this.onGoToPodcast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: SearchField(query: homeQueryProvider, hint: s.searchHint),
          ),
          Expanded(child: _HomeContent(onGoToPodcast: onGoToPodcast)),
        ],
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  final VoidCallback? onGoToPodcast;
  const _HomeContent({this.onGoToPodcast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final query = ref.watch(homeQueryProvider).trim();
    final searching = query.isNotEmpty;
    final state = ref.watch(articlesControllerProvider(null));
    final ctrl = ref.read(articlesControllerProvider(null).notifier);

    // Buscando → índice (todos). Si no → portada normal.
    if (searching) return SearchResults(query: query);
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: ctrl.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          const _HomeBanner(),
          if (state.initialLoading)
            const _HomeSkeleton()
          else if (state.error != null && state.items.isEmpty)
            _ErrorBox(
                message: s.loadError,
                retry: s.retry,
                onRetry: ctrl.refresh)
          else
            ..._content(context, ref, s, state, ctrl, onGoToPodcast),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, WidgetRef ref, S s,
      ArticlesState state, ArticlesController ctrl, VoidCallback? onGoToPodcast) {
    // L11: estado vacío explícito (idiomas con pocas traducciones pueden devolver
    // 0 artículos) en vez de dejar la pantalla en blanco.
    if (state.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(
            child: Text(
              s.noResults,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.mutedDark
                    : AppColors.mutedLight,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ];
    }
    final featured = state.items.first;
    final rest = state.items.skip(1).toList();

    return [
      _HeroCard(article: featured),
      const SizedBox(height: 16),
      _PodcastStrip(onGoToPodcast: onGoToPodcast),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 24, 2, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(s.latest, style: AppTheme.display(context, size: 30)),
          ],
        ),
      ),
      for (final a in rest) ArticleTile(article: a),
      if (state.hasMore && state.error == null)
        LoadMoreButton(
          loading: state.loadingMore,
          label: s.loadMore,
          onTap: ctrl.loadMore,
        ),
      // M6: si "Ver más" falló (red de Aruba), avisamos con opción de reintento
      // en vez de quedarnos en silencio.
      if (state.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: TextButton.icon(
              onPressed: state.loadingMore ? null : ctrl.loadMore,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(s.retry),
              style: TextButton.styleFrom(foregroundColor: AppColors.brand),
            ),
          ),
        ),
    ];
  }
}

/// Banner promocional de la Home (SOLO italiano). Se obtiene de la web (ver
/// homeBannerProvider). Clicable solo si el banner trae enlace → navegador
/// externo. Si no hay banner o no es italiano, no ocupa espacio.
class _HomeBanner extends ConsumerWidget {
  const _HomeBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(langProvider) != AppLang.it) return const SizedBox.shrink();
    // Muestra el cacheado al instante; cuando el fetch fresco llega, lo sustituye.
    final banner = ref.watch(homeBannerProvider).valueOrNull ??
        ref.watch(cachedHomeBannerProvider);
    if (banner == null) return const SizedBox.shrink();

    Widget image = AspectRatio(
      aspectRatio: 729 / 91, // proporción del banner en la web
      child: RemoteImage(
        url: banner.imageUrl,
        width: double.infinity,
        height: double.infinity,
        radius: 12,
      ),
    );
    if (banner.linkUrl != null) {
      image = InkWell(
        onTap: () => _open(banner.linkUrl!),
        borderRadius: BorderRadius.circular(12),
        child: image,
      );
    }
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: image);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {}
  }
}

class _HeroCard extends ConsumerWidget {
  final Article article;
  const _HeroCard({required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    // Si la noticia se publicó sin imagen (o se cacheó sin ella), la reintentamos
    // por id: si ya está disponible en el server, la mostramos.
    final imageUrl = (article.imageUrl != null && article.imageUrl!.isNotEmpty)
        ? article.imageUrl
        : ref.watch(articleImageProvider(article.id)).valueOrNull;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? AppColors.mutedDark
        : AppColors.mutedLight;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ArticleDetailPage(article: article))),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RemoteImage(
              url: imageUrl,
              width: double.infinity,
              height: 230,
              radius: 18),
          const SizedBox(height: 12),
          if (article.category.isNotEmpty)
            Text(article.category.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.brandSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 1)),
          const SizedBox(height: 6),
          Text(article.title,
              style: const TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, height: 1.18)),
          const SizedBox(height: 8),
          Text(relativeTime(article.date, lang),
              style: TextStyle(color: muted, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PodcastStrip extends ConsumerWidget {
  final VoidCallback? onGoToPodcast;
  const _PodcastStrip({this.onGoToPodcast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final ep = ref.watch(latestEpisodeProvider).valueOrNull;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final title = ep?.title ?? 'RadioApp Podcast';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        GestureDetector(
          // El botón nunca queda muerto: en móviles con red lenta el feed puede
          // no haber cargado aún (ep == null). Aun así lleva a la pestaña
          // Podcast; y si el último episodio ya está disponible, lo reproduce.
          onTap: () {
            if (ep != null) {
              ref.read(podcastPlayerProvider.notifier).playEpisode(ep);
            }
            onGoToPodcast?.call();
          },
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppColors.brand.withValues(alpha: .5),
                    blurRadius: 14),
              ],
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 5),
              Text(s.podcastOfDay,
                  style: const TextStyle(
                      color: AppColors.brandSoft,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: .4)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double w = double.infinity, double r = 12}) =>
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(r),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        box(200, r: 18),
        const SizedBox(height: 12),
        box(16, w: 90),
        const SizedBox(height: 8),
        box(22, w: 280),
        const SizedBox(height: 22),
        box(80, r: 16),
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
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
