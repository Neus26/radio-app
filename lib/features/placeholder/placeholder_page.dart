import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Stub navegable para las pestañas aún no construidas (Noticias, Podcast,
/// Radio, Más). Deja claro el "hueco" y qué llegará.
class PlaceholderPage extends ConsumerWidget {
  final String title;
  final IconData icon;
  final String hint;
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.hint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.brand),
              const SizedBox(height: 18),
              Text(title, style: AppTheme.display(context, size: 56)),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppColors.brandSoft.withValues(alpha: .5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(s.comingSoon.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.brandSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1)),
              ),
              const SizedBox(height: 16),
              Text(hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.mutedDark
                          : AppColors.mutedLight,
                      height: 1.4,
                      fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
