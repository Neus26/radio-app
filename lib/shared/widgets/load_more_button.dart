import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Botón "Ver más / Carica altro" para paginar listas.
class LoadMoreButton extends StatelessWidget {
  final bool loading;
  final String label;
  final VoidCallback onTap;
  const LoadMoreButton({
    super.key,
    required this.loading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const SizedBox(
                height: 30,
                width: 30,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.brand),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brand,
                  side: const BorderSide(color: AppColors.brand),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                ),
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
      ),
    );
  }
}
