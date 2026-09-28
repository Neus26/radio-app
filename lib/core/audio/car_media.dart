import 'package:audio_service/audio_service.dart';
import '../../data/models/article.dart';

/// Árbol navegable que Android Auto muestra en la pantalla del coche.
/// SOLO audio: radio en directo + podcasts/entrevistas. Sin noticias ni vídeo.
///
/// Este archivo es PURO (sin I/O ni Riverpod) para poder testearlo entero.

/// Logo FIJO de la emisora (PNG 512x512 real), respaldo de carátula cuando aún
/// no se sabe qué canción suena (arranque en frío desde el coche).
///
/// OJO: NO usar 'https://artwork.rcast.net/66954' como artUri. Ese endpoint NO
/// es una imagen: devuelve text/plain con la URL de la carátula DENTRO. Android
/// se descarga ese texto y BitmapFactory.decodeFile() da null → cuadro gris. La
/// carátula real (por canción) se resuelve en runtime (ver radio_track.dart).
const String kRadioLogoUrl =
    'https://www.unicaradio.it/wp-content/uploads/2026/07/cropped-icon.png';

class CarIds {
  CarIds._();

  /// Pestaña navegable "Radio" (contiene el directo). La raíz SOLO admite
  /// navegables: los playables sueltos caen en la pestaña automática "Altro".
  static const String radioFolder = 'radio-folder';

  /// Radio en directo (reproducible de un toque). Vive DENTRO de la pestaña
  /// Radio. Su id lo usan playFromMediaId y _setMeta: no se toca.
  static const String radio = 'radio';

  /// Carpeta navegable de episodios.
  static const String podcasts = 'podcasts';

  static const String podcastPrefix = 'podcast:';

  static String episode(int id) => '$podcastPrefix$id';
}

/// Devuelve el id del episodio si [mediaId] es de podcast; null en otro caso.
int? episodeIdFrom(String mediaId) {
  if (!mediaId.startsWith(CarIds.podcastPrefix)) return null;
  return int.tryParse(mediaId.substring(CarIds.podcastPrefix.length));
}

/// La radio es DIRECTO: `isLive` + sin duración → el coche no pinta barra de
/// posición ni permite avanzar/retroceder. Solo Play/Stop.
///
/// El título llega YA TRADUCIDO desde fuera (el handler lo saca de `S`, con el
/// idioma leído de prefs): este archivo no importa i18n para seguir siendo puro.
MediaItem radioMediaItem({required String title}) => MediaItem(
      id: CarIds.radio,
      title: title,
      artist: 'RadioApp',
      album: 'RadioApp',
      playable: true,
      isLive: true,
      artUri: Uri.parse(kRadioLogoUrl),
    );

/// Pestaña "Radio". La raíz SOLO admite navegables: Android Auto convierte los
/// navegables de la raíz en PESTAÑAS y manda los playables sueltos a la pestaña
/// automática "Altro" (los rootHints por defecto solo aceptan FLAG_BROWSABLE y
/// audio_service no los lee). Por eso el directo NO cuelga de la raíz sino de
/// esta carpeta. El título llega ya traducido (ver `radioMediaItem`).
MediaItem radioFolderMediaItem({required String title}) => MediaItem(
      id: CarIds.radioFolder,
      title: title,
      playable: false,
      extras: const {
        // Su único hijo playable (el directo) como tarjeta grande, fácil de
        // pulsar. Contrarresta el default global de lista (ver el handler).
        AndroidContentStyle.playableHintKey: AndroidContentStyle.gridItemHintValue,
      },
    );

/// Hijos de la pestaña Radio: solo el directo. El título llega traducido.
List<MediaItem> radioChildren({required String title}) =>
    [radioMediaItem(title: title)];

/// Carpeta/pestaña de podcasts: `playable: false`. Sin carátula: ahora es una
/// PESTAÑA (la doc pide icono monocromo, no la foto del primer episodio). Sus
/// hijos (episodios) se piden en modo lista compacta.
/// El título llega ya traducido (ver `radioMediaItem`).
MediaItem podcastsFolderMediaItem({required String title}) => MediaItem(
      id: CarIds.podcasts,
      title: title,
      playable: false,
      extras: const {
        AndroidContentStyle.playableHintKey: AndroidContentStyle.listItemHintValue,
      },
    );

/// Episodio reproducible. El feed NO trae duración: la barra de posición aparece
/// al reproducir, cuando el player ya conoce la duración real (ver el handler).
MediaItem episodeMediaItem(PodcastEpisode ep) => MediaItem(
      id: CarIds.episode(ep.id),
      title: ep.title,
      artist: 'RadioApp',
      album: 'Podcast · RadioApp',
      playable: true,
      artUri: (ep.imageUrl != null && ep.imageUrl!.isNotEmpty)
          ? Uri.tryParse(ep.imageUrl!)
          : null,
    );

/// Raíz de la biblioteca: SOLO navegables (Android Auto los pinta como pestañas
/// y tira los playables sueltos a "Altro"). Radio primero = pestaña por defecto,
/// así al entrar ya se ve el directo. Los nombres vienen traducidos al idioma
/// que el usuario tenga elegido.
List<MediaItem> rootChildren({
  required String radioTitle,
  required String podcastsTitle,
}) =>
    [
      radioFolderMediaItem(title: radioTitle),
      podcastsFolderMediaItem(title: podcastsTitle),
    ];
