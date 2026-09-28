import '../../core/i18n/strings.dart';

/// "hace 5 min" / "3 ore fa"… a partir de la fecha de publicación.
///
/// Si la fecha es FUTURA la tratamos como "ahora mismo": la web tiene noticias
/// fechadas por delante (traducciones automáticas) y sin esta pinza salía un
/// tiempo negativo, literalmente "hace -20568 min".
String relativeTime(DateTime date, AppLang lang) {
  final s = S(lang);
  final diff = DateTime.now().difference(date);
  final d = diff.isNegative ? Duration.zero : diff;
  if (d.inMinutes < 60) return s.relMin(d.inMinutes);
  if (d.inHours < 24) return s.relHour(d.inHours);
  return s.relDay(d.inDays);
}
