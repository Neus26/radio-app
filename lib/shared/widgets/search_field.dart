import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';

/// Campo de búsqueda reutilizable, enlazado a un `StateProvider<String>`.
/// Incluye botón de borrar. Lo usan Inicio, Noticias y Podcast.
class SearchField extends ConsumerStatefulWidget {
  final StateProvider<String> query;
  final String hint;
  const SearchField({super.key, required this.query, required this.hint});

  @override
  ConsumerState<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<SearchField> {
  late final TextEditingController _c =
      TextEditingController(text: ref.read(widget.query));
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _set(String v) {
    setState(() {}); // refrescar el botón de borrar inmediatamente
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(widget.query.notifier).state = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.search, color: Color(0xFF8D9097), size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _c,
            onChanged: _set,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: const TextStyle(
                  color: Color(0xFF8D9097),
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
        ),
        if (_c.text.isNotEmpty)
          GestureDetector(
            onTap: () {
              _c.clear();
              _debounce?.cancel();
              ref.read(widget.query.notifier).state = '';
              setState(() {});
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: Color(0xFF8D9097), size: 20),
            ),
          ),
      ]),
    );
  }
}
