import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'i18n/strings.dart' show sharedPreferencesProvider;
import 'analytics/analytics.dart';

/// Calidades de audio de la radio: los 3 mounts del Icecast, servidos por HTTPS
/// (con CORS) en streaming.unicaradio.it. El "ahora suena" y el historial van
/// por otra vía (rcast/regia) y NO dependen de esto.
enum AudioQuality {
  high('192', 'unica192.mp3', 'MP3'),
  medium('128', 'unica128.ogg', 'OGG'),
  low('48', 'unica48.aac', 'AAC+');

  final String kbps;
  final String _mount;
  final String codec;
  const AudioQuality(this.kbps, this._mount, this.codec);

  String get url => 'https://streaming.unicaradio.it/$_mount';
  bool get isOgg => _mount.endsWith('.ogg');
}

// OGG no suena en iOS/Safari → ocultamos la 128 en iOS (vale para la app nativa
// y para Safari en iPhone, que también reporta iOS).
bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

// Calidad por defecto cuando el usuario no ha elegido. En iOS arrancamos en
// AAC+ (48k): AVPlayer inicia los streams MP3/ICY en directo con ~5 s de retardo
// (probado: TTFB del servidor 42 ms, el retardo es del arranque de AVPlayer con
// MP3), mientras que el AAC+ arranca casi al instante. En Android el 192 MP3 va
// fino. El usuario puede subir a 192 MP3 en Ajustes (con arranque más lento).
AudioQuality get _defaultQuality => _isIOS ? AudioQuality.low : AudioQuality.high;

/// Calidades que se ofrecen en la plataforma actual (sin OGG en iOS).
List<AudioQuality> get availableQualities => _isIOS
    ? AudioQuality.values.where((q) => !q.isOgg).toList()
    : AudioQuality.values;

/// Clave de SharedPreferences donde se persiste la calidad elegida.
const String kAudioQualityPrefsKey = 'audioQuality';

/// Calidad guardada, leída directamente de prefs SIN Riverpod. La usa el
/// catálogo del coche: Android Auto puede arrancar la app en frío (solo el
/// servicio, sin UI) y ahí los providers no existen.
AudioQuality audioQualityFromPrefs(SharedPreferences prefs) {
  final saved = prefs.getString(kAudioQualityPrefsKey);
  for (final q in AudioQuality.values) {
    if (q.name == saved) return (q.isOgg && _isIOS) ? _defaultQuality : q;
  }
  return _defaultQuality;
}

/// Calidad elegida (persistida). Por defecto: iOS = AAC+ 48k (arranque rápido),
/// Android = 192 MP3. El usuario puede cambiarla en Ajustes.
final audioQualityProvider = StateProvider<AudioQuality>((ref) {
  final saved =
      ref.watch(sharedPreferencesProvider).getString(kAudioQualityPrefsKey);
  for (final q in AudioQuality.values) {
    if (q.name == saved) {
      // Si guardó OGG pero ahora está en iOS, cae al default de la plataforma.
      return (q.isOgg && _isIOS) ? _defaultQuality : q;
    }
  }
  return _defaultQuality;
});

/// Cambia la calidad y la persiste. La radio reacciona sola (reconecta si suena).
void setAudioQuality(WidgetRef ref, AudioQuality q) {
  ref.read(audioQualityProvider.notifier).state = q;
  ref.read(sharedPreferencesProvider).setString(kAudioQualityPrefsKey, q.name);
  Analytics.instance.log('audio_quality_change', {'quality': q.name});
}
