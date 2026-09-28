/// Normaliza texto para búsquedas flexibles: minúsculas + sin tildes/diacríticos.
/// Así "Málaga", "malaga" y "MALAGA" coinciden.
String normalizeForSearch(String input) {
  final s = input.toLowerCase();
  const accents = 'àáâãäåèéêëìíîïòóôõöùúûüñçýÿ';
  const plain = 'aaaaaaeeeeiiiiooooouuuuncyy';
  final sb = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    final idx = accents.indexOf(ch);
    sb.write(idx >= 0 ? plain[idx] : ch);
  }
  return sb.toString();
}

/// ¿`haystack` contiene `query` ignorando tildes y mayúsculas?
bool matchesQuery(String haystack, String query) =>
    normalizeForSearch(haystack).contains(normalizeForSearch(query));
