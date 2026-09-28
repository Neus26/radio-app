import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/i18n/strings.dart';

/// URL de la página de redirección alojada en unicaradio.it.
/// Si la app está instalada, el JS de la página abre radioapp://type?id=X;
/// si no, muestra el enlace de descarga.
String appRedirectUrl({required String type, required int id}) =>
    'https://www.unicaradio.it/app/?type=$type&id=$id';

/// Intenta compartir con el sistema nativo; en web sin HTTPS copia al portapapeles.
Future<void> shareContent(
  BuildContext context,
  S s, {
  required String title,
  required String url,
}) async {
  final text = url.isNotEmpty ? '$title\n$url' : title;
  try {
    final result = await SharePlus.instance.share(
      ShareParams(subject: title, text: text),
    );
    if (result.status == ShareResultStatus.unavailable && context.mounted) {
      await _copyFallback(context, s, text);
    }
  } catch (_) {
    if (context.mounted) await _copyFallback(context, s, text);
  }
}

Future<void> _copyFallback(BuildContext context, S s, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.linkCopied),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
