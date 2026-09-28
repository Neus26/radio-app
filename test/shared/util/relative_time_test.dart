import 'package:flutter_test/flutter_test.dart';
import 'package:radio_app/core/i18n/strings.dart';
import 'package:radio_app/shared/util/relative_time.dart';

void main() {
  final s = S(AppLang.es);

  test('noticia de hace unos minutos', () {
    final d = DateTime.now().subtract(const Duration(minutes: 5));
    expect(relativeTime(d, AppLang.es), s.relMin(5));
  });

  test('noticia de hace unas horas', () {
    final d = DateTime.now().subtract(const Duration(hours: 3));
    expect(relativeTime(d, AppLang.es), s.relHour(3));
  });

  test('noticia de hace días', () {
    final d = DateTime.now().subtract(const Duration(days: 2));
    expect(relativeTime(d, AppLang.es), s.relDay(2));
  });

  // La web publica traducciones con fecha FUTURA (agosto 2026: fechadas del 17
  // al 30 cuando era día 6). Con `difference` negativo se colaba por la primera
  // rama y en Inicio salía literalmente "hace -20568 min".
  test('noticia con fecha FUTURA no muestra un tiempo negativo', () {
    final futura = DateTime.now().add(const Duration(days: 14));
    final texto = relativeTime(futura, AppLang.es);
    expect(texto.contains('-'), isFalse,
        reason: 'no debe salir un número negativo: $texto');
    expect(texto, s.relMin(0));
  });

  test('fecha futura por segundos (desfase de reloj) tampoco es negativa', () {
    final futura = DateTime.now().add(const Duration(seconds: 30));
    expect(relativeTime(futura, AppLang.es), s.relMin(0));
  });
}
