import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'brand_logo.dart';

/// Enruta todas las imágenes por wsrv.nl:
/// - Web: necesario para CORS (CanvasKit lo exige).
/// - Móvil: convierte WebP → JPEG. El emulador x86_64 de Android no implementa
///   el codec WebP en android.graphics.ImageDecoder; en dispositivos ARM64 reales
///   también evita descargar uploads de WordPress a resolución completa.
String? _resolveUrl(String? url) {
  if (url == null || url.isEmpty) return url;
  if (kIsWeb) {
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=800';
  }
  return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=800&output=jpg';
}

const _placeholderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF3A3D44), Color(0xFF1F2127)],
);

/// Imagen remota con caché y placeholder en gradiente (cae al placeholder
/// si no hay URL o falla la carga).
class RemoteImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  const RemoteImage({
    super.key,
    this.url,
    this.width,
    this.height,
    this.radius = 12,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    // Mientras carga: gradiente liso (no parpadea el logo en cada carga normal).
    final loading = Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(gradient: _placeholderGradient),
    );
    final Widget img = (url == null || url!.isEmpty)
        ? _branded()
        : CachedNetworkImage(
            imageUrl: _resolveUrl(url)!,
            width: width,
            height: height,
            fit: fit,
            placeholder: (_, __) => loading,
            errorWidget: (_, __, ___) => _branded(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: img,
    );
  }

  // Placeholder de MARCA: gradiente + logo RadioApp sutil, para posts que de
  // verdad NO tienen imagen (raro: p.ej. una noticia publicada sin destacada).
  Widget _branded() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(gradient: _placeholderGradient),
      child: LayoutBuilder(builder: (_, c) {
        final side = c.biggest.shortestSide;
        // En miniaturas muy pequeñas el logo no se leería → solo gradiente.
        if (!side.isFinite || side < 44) return const SizedBox.expand();
        return Center(
          child: Opacity(
            opacity: .28,
            child: BrandLogo(
              height: (side * 0.34).clamp(22.0, 60.0),
              color: Colors.white,
            ),
          ),
        );
      }),
    );
  }
}
