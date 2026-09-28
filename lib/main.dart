import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/analytics/analytics.dart';
import 'core/analytics/consent.dart';
import 'core/audio/audio_handler.dart';
import 'core/i18n/strings.dart';
import 'core/theme/app_theme.dart';
import 'features/shell/main_shell.dart';
import 'shared/widgets/iphone_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Carga los datos de formato de fecha de todos los locales, para que las
  // fechas (artículos, podcasts) salgan en el idioma seleccionado, no en inglés.
  await initializeDateFormatting();
  // Firebase solo en móvil: en web no hay config (y la preview web debe
  // seguir funcionando). La recogida arranca APAGADA hasta que el usuario
  // consienta (ver AndroidManifest + core/analytics/).
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) debugPrint('Firebase init: $e');
    }
  }
  // Registra la MediaSession del SO (Android) / MPNowPlayingInfoCenter (iOS)
  // para que la pantalla del coche reciba título/artista/portada por Bluetooth.
  // En web audio_service es un no-op seguro.
  await initAudioService();
  final prefs = await SharedPreferences.getInstance();
  // RGPD: reactiva la recogida solo si en una sesión previa se concedió.
  await Analytics.instance.setEnabled(analyticsGrantedIn(prefs));
  runApp(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const RadioApp(),
  ));
}

class RadioApp extends ConsumerWidget {
  const RadioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'RadioApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      // Encuadre iPhone en web + dirección RTL para idiomas como el árabe.
      builder: (context, child) {
        final app = child ?? const SizedBox.shrink();
        return Consumer(builder: (context, ref, _) {
          final rtl = ref.watch(langProvider).rtl;
          // Encuadre iPhone solo en la preview WEB; en el móvil real, pantalla
          // completa. El frame se escala para caber (ver IPhoneFrame).
          final framed = kIsWeb ? IPhoneFrame(child: app) : app;
          return Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: framed,
          );
        });
      },
      home: const MainShell(),
    );
  }
}
