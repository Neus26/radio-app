import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:firebase_analytics/firebase_analytics.dart';

/// Envoltorio fino sobre Firebase Analytics.
///
/// No hace NADA en dos casos:
///  - en web (Firebase solo se inicializa en móvil → el preview no se rompe);
///  - mientras el usuario no haya dado su consentimiento (RGPD).
///
/// Los puntos de la app llaman a `Analytics.instance.log(...)` sin preocuparse
/// del consentimiento: el filtro vive aquí.
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  bool _enabled = false; // refleja el consentimiento; arranca apagado

  FirebaseAnalytics? get _fa => kIsWeb ? null : FirebaseAnalytics.instance;

  /// Activa/desactiva la recogida según el consentimiento y lo propaga al SDK.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      await _fa?.setAnalyticsCollectionEnabled(enabled);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics setEnabled: $e');
    }
  }

  /// Registra un evento (no-op si no hay consentimiento o es web).
  Future<void> log(String name, [Map<String, Object>? params]) async {
    if (!_enabled) return;
    try {
      await _fa?.logEvent(name: name, parameters: params);
    } catch (e) {
      if (kDebugMode) debugPrint('analytics log($name): $e');
    }
  }
}
