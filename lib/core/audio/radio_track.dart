/// "Ahora suena" del directo. PURO: sin I/O ni Riverpod, para poder testearlo
/// entero y compartirlo entre RadioNotifier (app abierta) y CarCatalog (arranque
/// en frío desde el coche, sin providers).
class RadioTrack {
  final String title;
  final String artist;
  final String? artworkUrl;
  const RadioTrack({
    required this.title,
    required this.artist,
    this.artworkUrl,
  });
}

/// status.rcast.net devuelve TEXTO PLANO con la forma "ARTISTA - TÍTULO"
/// (verificado: "ROBBIE WILLIAMS - RADIO"). El separador es " - " (espacio,
/// guion, espacio). Si no aparece, el texto entero se toma como título.
RadioTrack parseRadioTrack(String raw, {String? artworkUrl}) {
  final s = raw.trim();
  final sep = s.indexOf(' - ');
  return sep > 0
      ? RadioTrack(
          artist: s.substring(0, sep).trim(),
          title: s.substring(sep + 3).trim(),
          artworkUrl: artworkUrl,
        )
      : RadioTrack(title: s, artist: '', artworkUrl: artworkUrl);
}

/// artwork.rcast.net NO es una imagen: devuelve la URL de la carátula en TEXTO
/// PLANO. Si se pasa tal cual a `artUri`, Android descarga ese texto y
/// BitmapFactory.decodeFile() da null → cuadro gris. Hay que resolverla antes:
/// devolvemos la URL solo si de verdad parece una URL (empieza por http); en
/// otro caso null y el handler cae al logo fijo.
String? parseArtworkUrl(String raw) {
  final u = raw.trim();
  return u.startsWith('http') ? u : null;
}
