import '../../shared/util/html_text.dart';

/// Noticia (post de WordPress). Construida desde `/wp/v2/posts?_embed`.
class Article {
  final int id;
  final String title;
  final String excerpt;
  final String contentHtml;
  final String? imageUrl;
  final String category;
  final DateTime date;
  final String link;

  const Article({
    required this.id,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.imageUrl,
    required this.category,
    required this.date,
    required this.link,
  });

  /// Serialización compacta para la caché local (shared_preferences).
  Map<String, dynamic> toCache() => {
        'id': id,
        'title': title,
        'excerpt': excerpt,
        'imageUrl': imageUrl,
        'category': category,
        'date': date.toIso8601String(),
        'link': link,
      };

  factory Article.fromCache(Map<String, dynamic> j) => Article(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        excerpt: j['excerpt'] as String? ?? '',
        contentHtml: '',
        imageUrl: j['imageUrl'] as String?,
        category: j['category'] as String? ?? '',
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        link: j['link'] as String? ?? '',
      );

  /// Construye desde la respuesta LIGERA (posts sin `_embed`): la imagen y la
  /// categoría se resuelven aparte (media batch + mapa de categorías).
  factory Article.light(Map<String, dynamic> j,
      {String? imageUrl, String category = ''}) {
    String rendered(String key) {
      try {
        return (j[key]['rendered'] as String?) ?? '';
      } catch (_) {
        return '';
      }
    }

    return Article(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: stripHtml(rendered('title')),
      excerpt: stripHtml(rendered('excerpt')),
      contentHtml: '',
      imageUrl: imageUrl,
      category: category,
      date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      link: (j['link'] as String?) ?? '',
    );
  }

  factory Article.fromJson(Map<String, dynamic> j) {
    String? image;
    try {
      image = j['_embedded']['wp:featuredmedia'][0]['source_url'] as String?;
    } catch (_) {}

    String category = '';
    try {
      category = (j['_embedded']['wp:term'][0][0]['name'] as String?) ?? '';
    } catch (_) {}

    String rendered(String key) {
      try {
        return (j[key]['rendered'] as String?) ?? '';
      } catch (_) {
        return '';
      }
    }

    return Article(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: stripHtml(rendered('title')),
      excerpt: stripHtml(rendered('excerpt')),
      contentHtml: rendered('content'),
      imageUrl: image,
      category: stripHtml(category),
      date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      link: (j['link'] as String?) ?? '',
    );
  }
}

/// Episodio de podcast (Seriously Simple Podcasting `/ssp/v1/episodes`).
class PodcastEpisode {
  final int id;
  final String title;
  final String? imageUrl;
  final String? audioUrl;
  final String? link;
  final DateTime date;

  const PodcastEpisode({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.audioUrl,
    this.link,
    required this.date,
  });

  /// Serialización compacta para la caché local.
  Map<String, dynamic> toCache() => {
        'id': id,
        'title': title,
        'imageUrl': imageUrl,
        'audioUrl': audioUrl,
        'link': link,
        'date': date.toIso8601String(),
      };

  factory PodcastEpisode.fromCache(Map<String, dynamic> j) => PodcastEpisode(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        audioUrl: j['audioUrl'] as String?,
        link: j['link'] as String?,
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
      );

  factory PodcastEpisode.fromJson(Map<String, dynamic> j) {
    String? image = (j['episode_player_image'] ??
        j['episode_featured_image']) as String?;
    String? audio;
    try {
      audio = ((j['meta'] as Map?)?['audio_file'] ??
          j['audio_file'] ??
          j['player_link']) as String?;
    } catch (_) {}
    String title = '';
    try {
      title = (j['title']?['rendered'] ?? j['title']) as String? ?? '';
    } catch (_) {}
    return PodcastEpisode(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: stripHtml(title),
      imageUrl: image,
      audioUrl: audio,
      link: j['link'] as String?,
      date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
