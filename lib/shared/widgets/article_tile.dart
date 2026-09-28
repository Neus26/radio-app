import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/analytics/analytics.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../features/article/article_detail_page.dart';
import 'remote_image.dart';

/// Fila de noticia (miniatura + categoría + título). Clickable → detalle.
class ArticleTile extends ConsumerWidget {
  final Article article;
  const ArticleTile({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reintenta la imagen por id si la noticia se publicó/cacheó sin ella.
    final imageUrl = (article.imageUrl != null && article.imageUrl!.isNotEmpty)
        ? article.imageUrl
        : ref.watch(articleImageProvider(article.id)).valueOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () {
          Analytics.instance.log('news_open', {
            'article_id': article.id.toString(),
            if (article.category.isNotEmpty) 'category': article.category,
          });
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => ArticleDetailPage(article: article)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RemoteImage(
                url: imageUrl, width: 92, height: 72, radius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article.category.isNotEmpty)
                    Text(article.category.toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.brandSoft,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: .4)),
                  const SizedBox(height: 4),
                  Text(article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.2)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
