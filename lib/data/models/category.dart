import '../../shared/util/html_text.dart';

/// Categoría de noticias (taxonomía `category` de WordPress).
class Category {
  final int id;
  final String name;
  final int count;

  const Category({required this.id, required this.name, required this.count});

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: stripHtml((j['name'] as String?) ?? ''),
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}
