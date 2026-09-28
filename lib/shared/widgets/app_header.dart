import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_theme.dart';
import 'brand_logo.dart';

/// Cabecera general, igual en todas las pestañas (se coloca en el shell):
/// logo (izquierda) · nombre de la sección (centro) · EN DIRECTO (derecha).
/// El logo lleva a Inicio (`onLogoTap`).
class AppHeader extends ConsumerWidget {
  final String title;
  final VoidCallback? onLiveTap;
  final VoidCallback? onLogoTap;
  const AppHeader(
      {super.key, required this.title, this.onLiveTap, this.onLogoTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onLogoTap,
            // El logo no llena su caja: sin esto los huecos no reciben el toque.
            behavior: HitTestBehavior.opaque,
            child: const BrandLogo(height: 26),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(context, size: 24),
                ),
              ),
            ),
          ),
          LivePill(label: s.live, onTap: onLiveTap),
        ],
      ),
    );
  }
}
