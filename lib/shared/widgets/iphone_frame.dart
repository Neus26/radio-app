import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Encuadra la app dentro de un iPhone 17 Pro (402×874 pts) para la preview
/// web. Se **escala para caber** en la ventana (en pantallas pequeñas no se
/// deforma; nunca se agranda más allá de su tamaño natural). En un móvil real
/// NO se usa (la app ocupa toda la pantalla).
class IPhoneFrame extends StatelessWidget {
  final Widget child;
  const IPhoneFrame({super.key, required this.child});

  static const double screenW = 402; // ancho lógico iPhone 17 Pro
  static const double screenH = 874; // alto lógico
  static const double _bodyW = screenW + 28; // + marco (padding 12 + borde 2)
  static const double _bodyH = screenH + 28;

  @override
  Widget build(BuildContext context) {
    final phone = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF050506),
        borderRadius: BorderRadius.circular(58),
        border: Border.all(color: const Color(0xFF1A1A1D), width: 2),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 50, spreadRadius: 4),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(46),
        child: SizedBox(
          width: screenW,
          height: screenH,
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: const Size(screenW, screenH),
                    padding: const EdgeInsets.only(top: 50, bottom: 14),
                    viewPadding: const EdgeInsets.only(top: 50, bottom: 14),
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: child,
                ),
              ),
              // Dynamic Island
              Positioned(
                top: 11,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 124,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: const Color(0xFF0A0A0B),
      child: LayoutBuilder(
        builder: (context, c) {
          // Llena el espacio disponible manteniendo la proporción iPhone 17 Pro:
          // se agranda hasta casi tocar los bordes y se encoge en pantallas
          // pequeñas. Tope 1.5 para no perder nitidez.
          final fit = math.min(c.maxWidth / _bodyW, c.maxHeight / _bodyH);
          final scale = math.min(1.5, fit * 0.96);
          return Center(
            child: Transform.scale(
              scale: scale,
              child: phone,
            ),
          );
        },
      ),
    );
  }
}
