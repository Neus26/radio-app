/// Convierte HTML a texto plano: elimina tags y decodifica entidades.
String stripHtml(String input) {
  var s = input.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = _decodeEntities(s);
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// Como [stripHtml] pero SIN trim final, para preservar los espacios que rodean
/// a tags inline (<strong>, <em>, <span>…) dentro de un párrafo.
/// Evita que "el <strong>75%</strong> Los" se renderice como "el75%Los".
String stripHtmlSegment(String input) {
  var s = input.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = _decodeEntities(s);
  s = s.replaceAll(RegExp(r'[ \t]+'), ' '); // colapsa espacios, no newlines
  return s;
}

String _decodeEntities(String s) {
  const map = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#039;': "'",
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
    '&hellip;': '…',
    '&mdash;': '—',
    '&ndash;': '–',
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&rdquo;': '”',
    '&ldquo;': '“',
    '&egrave;': 'è',
    '&agrave;': 'à',
    '&ograve;': 'ò',
    '&igrave;': 'ì',
    '&ugrave;': 'ù',
    '&eacute;': 'é',
    '&ccedil;': 'ç',
    '&ntilde;': 'ñ',
  };
  map.forEach((k, v) => s = s.replaceAll(k, v));
  // entidades numéricas hexadecimales (&#xNN; o &#XNN;)
  s = s.replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  // entidades numéricas decimales (&#NNN;)
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  return s;
}
