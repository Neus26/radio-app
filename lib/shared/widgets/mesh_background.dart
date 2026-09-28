import 'package:flutter/material.dart';

/// Fondo de la app: rejilla de altavoz regular y sutil (puntos embossados).
/// Es el "metal grid" del diseño. Pinta detrás del contenido.
class MeshBackground extends StatelessWidget {
  final Widget child;
  const MeshBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _MeshPainter(dark),
      child: child,
    );
  }
}

class _MeshPainter extends CustomPainter {
  final bool dark;
  _MeshPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    const step = 13.0;
    final hole = Paint()
      ..color = dark
          ? Colors.black.withValues(alpha: .50)
          : Colors.black.withValues(alpha: .045);
    final hi = Paint()
      ..color = dark
          ? Colors.white.withValues(alpha: .05)
          : Colors.white.withValues(alpha: .50);

    for (double y = -step; y < size.height + step; y += step) {
      for (double x = -step; x < size.width + step; x += step) {
        final cx = x + step / 2;
        canvas.drawCircle(Offset(cx, y + step * 0.43), 1.0, hi);
        canvas.drawCircle(Offset(cx, y + step * 0.57), 1.5, hole);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MeshPainter old) => old.dark != dark;
}
