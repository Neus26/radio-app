import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_colors.dart';

/// Logo oficial RadioApp (SVG vectorizado). El disco es rojo fijo; el texto
/// toma `currentColor` (lo adaptamos al tema vía SvgTheme).
class BrandLogo extends StatelessWidget {
  final double height;
  final Color? color;
  const BrandLogo({super.key, this.height = 30, this.color});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? (dark ? Colors.white : const Color(0xFF312E32));
    final svg = SvgPicture.asset(
      'assets/logo/logo_h.svg',
      height: height,
      theme: SvgTheme(currentColor: c),
    );
    if (!dark) return svg;
    // In dark mode the disc's evenodd-transparent holes show the dark background.
    // A white circle placed behind the SVG (using exact SVG coordinate ratios)
    // makes those holes always appear white, without adding any outer background.
    final s = height / 60.0;
    return Stack(
      children: [
        Positioned(
          left: 4.2 * s,
          top: 1.0 * s,
          width: 57.3 * s,
          height: 57.5 * s,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
        svg,
      ],
    );
  }
}

/// Pastilla "EN DIRECTO / IN DIRETTA" con punto pulsante.
class LivePill extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const LivePill({super.key, required this.label, this.onTap});

  @override
  State<LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: AppColors.brand.withValues(alpha: .55), blurRadius: 14),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween(begin: 1.0, end: .35).animate(_c),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 7),
        Text(widget.label,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: .5)),
      ]),
    ),
    );
  }
}
