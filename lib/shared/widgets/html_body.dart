import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../util/html_text.dart' show stripHtml, stripHtmlSegment;
import 'remote_image.dart';

// ── Tipos de bloque ───────────────────────────────────────────────────────────

enum _BT { p, h2, h3, img, ul, ol, quote }

class _Block {
  final _BT type;
  final String raw;
  final List<String> items;
  const _Block(this.type, {this.raw = '', this.items = const []});
}

// ── Widget principal ──────────────────────────────────────────────────────────

/// Renderiza HTML básico de WordPress como widgets Flutter con tipografía editorial.
/// Soporta: párrafos, h2/h3, listas (ul/ol), blockquote e imágenes en <figure>.
class HtmlBody extends StatelessWidget {
  final String html;
  const HtmlBody({super.key, required this.html});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor =
        dark ? Colors.white.withValues(alpha: .87) : const Color(0xFF1A1A2E);
    final mutedColor = dark ? AppColors.mutedDark : const Color(0xFF444458);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _parseBlocks(html)
          .map((b) => _buildWidget(context, b, bodyColor, mutedColor))
          .toList(),
    );
  }

  Widget _buildWidget(
      BuildContext context, _Block b, Color body, Color muted) {
    switch (b.type) {
      case _BT.h2:
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 28, 0, 8),
          child: Text(
            stripHtml(b.raw),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: body,
                height: 1.25),
          ),
        );
      case _BT.h3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 6),
          child: Text(
            stripHtml(b.raw),
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: body,
                height: 1.3),
          ),
        );
      case _BT.img:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: RemoteImage(url: b.raw, height: 200, radius: 10),
        );
      case _BT.ul:
      case _BT.ol:
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: b.items.asMap().entries.map((e) {
              final bullet = b.type == _BT.ol ? '${e.key + 1}.' : '•';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(bullet,
                          style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.brand,
                              fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 15, height: 1.65, color: muted)),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      case _BT.quote:
        return Container(
          margin: const EdgeInsets.fromLTRB(0, 8, 0, 18),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            border:
                const Border(left: BorderSide(color: AppColors.brand, width: 3)),
            color: AppColors.brand.withValues(alpha: .07),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
          ),
          child: Text(
            stripHtml(b.raw),
            style: TextStyle(
                fontSize: 15,
                height: 1.7,
                color: muted,
                fontStyle: FontStyle.italic),
          ),
        );
      default: // párrafo
        final text = stripHtml(b.raw).trim();
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _InlineParagraph(raw: b.raw, color: muted),
        );
    }
  }
}

// ── Parser de bloques ─────────────────────────────────────────────────────────

List<_Block> _parseBlocks(String html) {
  final out = <_Block>[];

  // Grupos en orden de aparición en el patrón:
  //  1 → src de <img> dentro de <figure> (comillas dobles o simples)
  //  2 → nombre del tag heading (h1-h6)
  //  3 → inner HTML del heading
  //  4 → inner HTML de <blockquote>
  //  5 → ul|ol
  //  6 → inner HTML de la lista
  //  7 → cierre ul|ol (ignorado)
  //  8 → inner HTML de <p>
  final re = RegExp(
    r'''<figure\b[^>]*>.*?<img\b[^>]+src=["']([^"']+)["'][^>]*/?>.*?</figure>'''
    r'|<(h[1-6])\b[^>]*>(.*?)</h[1-6]>'
    r'|<blockquote\b[^>]*>(.*?)</blockquote>'
    r'|<(ul|ol)\b[^>]*>(.*?)</(ul|ol)>'
    r'|<p\b[^>]*>(.*?)</p>'
    //  9 → src de <img> suelta a nivel de bloque (fuera de <figure>/<p>)
    r'''|<img\b[^>]+src=["']([^"']+)["'][^>]*/?>''',
    dotAll: true,
    caseSensitive: false,
  );

  // Para detectar <img> sueltas dentro de <p> o fuera de <figure>.
  final imgRe = RegExp(r'''<img\b[^>]+src=["']([^"']+)["'][^>]*/?>''',
      caseSensitive: false);

  for (final m in re.allMatches(html)) {
    if (m.group(1) != null) {
      out.add(_Block(_BT.img, raw: m.group(1)!));
    } else if (m.group(2) != null) {
      final tag = m.group(2)!.toLowerCase();
      final type = (tag == 'h1' || tag == 'h2') ? _BT.h2 : _BT.h3;
      out.add(_Block(type, raw: m.group(3)!));
    } else if (m.group(4) != null) {
      out.add(_Block(_BT.quote, raw: m.group(4)!));
    } else if (m.group(5) != null) {
      final ordered = m.group(5)!.toLowerCase() == 'ol';
      final items = RegExp(r'<li\b[^>]*>(.*?)</li>',
              dotAll: true, caseSensitive: false)
          .allMatches(m.group(6)!)
          .map((li) => stripHtml(li.group(1)!).trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        out.add(_Block(ordered ? _BT.ol : _BT.ul, items: items));
      }
    } else if (m.group(8) != null) {
      final inner = m.group(8)!;
      final imgM = imgRe.firstMatch(inner);
      final text = stripHtml(inner).trim();
      // M5: si el <p> tiene texto lo emitimos; y si además trae una imagen, la
      // emitimos también (antes la imagen se descartaba cuando había texto).
      if (text.isNotEmpty) out.add(_Block(_BT.p, raw: inner));
      if (imgM != null) out.add(_Block(_BT.img, raw: imgM.group(1)!));
    } else if (m.group(9) != null) {
      // M5: <img> suelta a nivel de bloque (no envuelta en <figure> ni <p>).
      out.add(_Block(_BT.img, raw: m.group(9)!));
    }
  }
  return out;
}

// ── Párrafo con formato inline (negrita / cursiva / enlaces) ─────────────────

class _InlineParagraph extends StatefulWidget {
  final String raw;
  final Color color;
  const _InlineParagraph({required this.raw, required this.color});

  @override
  State<_InlineParagraph> createState() => _InlineParagraphState();
}

class _InlineParagraphState extends State<_InlineParagraph> {
  List<InlineSpan> _spans = const [];
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(_InlineParagraph old) {
    super.didUpdateWidget(old);
    if (old.raw != widget.raw || old.color != widget.color) {
      setState(() {
        _disposeRecognizers();
        _buildSpans();
      });
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _buildSpans() {
    final base = TextStyle(fontSize: 15.5, height: 1.8, color: widget.color);
    final linkStyle = base.copyWith(
        color: AppColors.brand, decoration: TextDecoration.underline);
    final spans = <InlineSpan>[];

    var html = widget.raw.replaceAll(
        RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // Captura <a href>, bold e italic; el resto de tags inline se aplanan.
    final re = RegExp(
      r'''<a\b[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>'''
      r'|<(strong|b|em|i)\b[^>]*>(.*?)</(strong|b|em|i)>',
      dotAll: true,
      caseSensitive: false,
    );

    int last = 0;
    for (final m in re.allMatches(html)) {
      if (m.start > last) {
        final plain = stripHtmlSegment(html.substring(last, m.start));
        if (plain.trim().isNotEmpty) spans.add(TextSpan(text: plain, style: base));
      }
      if (m.group(1) != null) {
        final href = m.group(1)!;
        final text = stripHtmlSegment(m.group(2)!).trim();
        if (text.isNotEmpty) {
          final recognizer = TapGestureRecognizer()
            ..onTap = () {
              final uri = Uri.tryParse(href);
              if (uri != null &&
                  (uri.scheme == 'https' ||
                      uri.scheme == 'http' ||
                      uri.scheme == 'mailto')) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            };
          _recognizers.add(recognizer);
          spans.add(TextSpan(text: text, style: linkStyle, recognizer: recognizer));
        }
      } else if (m.group(3) != null) {
        final tag = m.group(3)!.toLowerCase();
        final text = stripHtmlSegment(m.group(4)!).trim();
        if (text.isNotEmpty) {
          final isBold = tag == 'strong' || tag == 'b';
          spans.add(TextSpan(
            text: text,
            style: isBold
                ? base.copyWith(fontWeight: FontWeight.w700)
                : base.copyWith(fontStyle: FontStyle.italic),
          ));
        }
      }
      last = m.end;
    }
    if (last < html.length) {
      final plain = stripHtmlSegment(html.substring(last));
      if (plain.trim().isNotEmpty) spans.add(TextSpan(text: plain, style: base));
    }
    _spans = spans;
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans),
      textAlign: TextAlign.justify,
      textScaler: MediaQuery.textScalerOf(context),
    );
  }
}
