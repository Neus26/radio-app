import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/strings.dart' show sharedPreferencesProvider;
import 'analytics.dart';

/// Estado del consentimiento de analítica (RGPD).
///  - [unknown]: aún no se ha preguntado (no se recoge nada).
///  - [granted]: el usuario aceptó.
///  - [denied]: el usuario rechazó.
enum AnalyticsConsent { unknown, granted, denied }

const _kAnalyticsConsent = 'analyticsConsent';

AnalyticsConsent _parse(String? s) => switch (s) {
      'granted' => AnalyticsConsent.granted,
      'denied' => AnalyticsConsent.denied,
      _ => AnalyticsConsent.unknown,
    };

/// Consentimiento actual (persistido en SharedPreferences).
final analyticsConsentProvider = StateProvider<AnalyticsConsent>((ref) =>
    _parse(ref.watch(sharedPreferencesProvider).getString(_kAnalyticsConsent)));

/// True si el usuario concedió la analítica en una sesión anterior. Se usa en
/// `main()` para reactivar la recogida antes de levantar el árbol de widgets.
bool analyticsGrantedIn(SharedPreferences prefs) =>
    prefs.getString(_kAnalyticsConsent) == 'granted';

/// Guarda el consentimiento, lo persiste y lo propaga al SDK de analítica.
void setAnalyticsConsent(WidgetRef ref, AnalyticsConsent consent) {
  ref.read(analyticsConsentProvider.notifier).state = consent;
  ref
      .read(sharedPreferencesProvider)
      .setString(_kAnalyticsConsent, consent.name);
  Analytics.instance.setEnabled(consent == AnalyticsConsent.granted);
}
