import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../shared/util/share_util.dart';
import '../../shared/widgets/html_body.dart';
import '../../shared/widgets/remote_image.dart';

class ArticleDetailPage extends ConsumerWidget {
  final Article article;
  const ArticleDetailPage({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppColors.mutedDark : const Color(0xFF444458);
    final s = ref.watch(sProvider);
    final contentAsync = ref.watch(articleContentProvider(article.id));
    // Los artículos del buscador vienen sin imagen (carga ligera). Si falta, la
    // pedimos por id; si la trae (lista de noticias), usamos esa directamente.
    final hasOwnImage =
        article.imageUrl != null && article.imageUrl!.isNotEmpty;
    final imageUrl = hasOwnImage
        ? article.imageUrl
        : ref.watch(articleImageProvider(article.id)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        leading: const BackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: s.share,
            onPressed: () => shareContent(
              context,
              s,
              title: article.title,
              url: appRedirectUrl(type: 'article', id: article.id),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
        children: [
          // Imagen de cabecera
          RemoteImage(
            url: imageUrl,
            width: double.infinity,
            height: 230,
            radius: 18,
          ),
          const SizedBox(height: 18),

          // Categoría
          if (article.category.isNotEmpty)
            Text(
              article.category.toUpperCase(),
              style: const TextStyle(
                color: AppColors.brandSoft,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          const SizedBox(height: 8),

          // Título
          Text(
            article.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Fecha
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 13, color: muted),
              const SizedBox(width: 5),
              Text(
                DateFormat('d MMMM yyyy', s.lang.code).format(article.date),
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Separador
          Divider(
            height: 1,
            thickness: 0.5,
            color: dark ? Colors.white12 : Colors.black12,
          ),
          const SizedBox(height: 22),

          // Banner promo de la noticia (solo italiano; oculto si no tiene).
          _ArticleBanner(articleUrl: article.link),

          // Contenido
          contentAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brand),
              ),
            ),
            error: (_, __) => Text(
              article.excerpt,
              style: TextStyle(fontSize: 15.5, height: 1.8, color: muted),
            ),
            data: (html) => html.trim().isEmpty
                ? Text(
                    article.excerpt,
                    style: TextStyle(fontSize: 15.5, height: 1.8, color: muted),
                  )
                : HtmlBody(html: html),
          ),
        ],
      ),
    );
  }
}

/// Banner promocional dentro de una noticia (slot above-post de la web). Solo
/// italiano; clicable solo si trae enlace → navegador externo; oculto si la
/// noticia no tiene banner. Se carga al abrir (ver articleBannerProvider).
class _ArticleBanner extends ConsumerWidget {
  final String articleUrl;
  const _ArticleBanner({required this.articleUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(langProvider) != AppLang.it) return const SizedBox.shrink();
    final banner = ref.watch(articleBannerProvider(articleUrl)).valueOrNull;
    if (banner == null) return const SizedBox.shrink();

    Widget image = AspectRatio(
      aspectRatio: 728 / 91,
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
    return Padding(padding: const EdgeInsets.only(bottom: 22), child: image);
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
