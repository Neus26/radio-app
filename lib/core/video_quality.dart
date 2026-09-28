import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'i18n/strings.dart' show sharedPreferencesProvider;
import 'analytics/analytics.dart';

/// Calidades de vídeo del directo: dos streams H264 en el servidor MediaMTX.
/// high = 1024 kbps (1280x720), low = 512 kbps (854x480).
///
/// Agosto 2026: la emisora movió el vídeo a `mmtx.unicaradio.it` **por HTTPS**
/// y renombró los mounts (el antiguo `mystream` ya no existe: el servidor
/// responde "path 'mystream' is not configured").
enum VideoQuality {
  high('1024', 'unicaradio1024k'),
  low('512', 'unicaradio512k');

  final String kbps;
  final String _mount;
  const VideoQuality(this.kbps, this._mount);

  String get playerUrl =>
      'https://mmtx.unicaradio.it/$_mount/'
      '?controls=false&muted=false&disablepictureinpicture=true';
}

const String kVideoQualityPrefsKey = 'videoQuality';

/// Calidad de vídeo elegida (persistida). Por defecto: Alta (1024 kbps).
final videoQualityProvider = StateProvider<VideoQuality>((ref) {
  final saved =
      ref.watch(sharedPreferencesProvider).getString(kVideoQualityPrefsKey);
  for (final q in VideoQuality.values) {
    if (q.name == saved) return q;
  }
  return VideoQuality.high;
});

/// Cambia la calidad de vídeo y la persiste. El cambio automático por conexión
/// lenta NO llama a esta función (no persiste) para que el usuario vuelva a
/// alta calidad la próxima vez que abra la app.
void setVideoQuality(WidgetRef ref, VideoQuality q) {
  ref.read(videoQualityProvider.notifier).state = q;
  ref.read(sharedPreferencesProvider).setString(kVideoQualityPrefsKey, q.name);
  Analytics.instance.log('video_quality_change', {'quality': q.name});
}
