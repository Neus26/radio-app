import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:radio_app/main.dart';
import 'package:radio_app/core/i18n/strings.dart';
import 'package:radio_app/data/models/article.dart';
import 'package:radio_app/data/models/category.dart';
import 'package:radio_app/data/wp_api/wp_providers.dart';
import 'package:radio_app/features/radio/radio_notifier.dart';
import 'package:radio_app/features/podcast/podcast_notifier.dart';

/// Controladores falsos (sin red) para el test.
class _FakeArticles extends ArticlesController {
  @override
  ArticlesState build(int? categoryId) =>
      const ArticlesState(initialLoading: false, items: [], hasMore: false);
}

class _FakePodcast extends PodcastController {
  @override
  PodcastState build() =>
      const PodcastState(initialLoading: false, items: [], hasMore: false);
}

/// Radio falsa: no se conecta al stream ni busca estado.
class _FakeRadio extends RadioNotifier {
  @override
  RadioState build() => const RadioState();
}

/// Reproductor de podcast falso: evita tocar el `audioHandler` (singleton que
/// solo se inicializa en main(), no en el test).
class _FakePodcastPlayer extends PodcastNotifier {
  @override
  PodcastPlayState build() => const PodcastPlayState();
}

/// Índice de búsqueda falso (sin red).
class _FakeSearchIndex extends SearchIndex {
  @override
  List<Article> build() => const [];
}

void main() {
  testWidgets('Arranca y muestra la barra de 5 pestañas', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          langProvider.overrideWith((ref) => AppLang.it), // test en italiano
          articlesControllerProvider.overrideWith(_FakeArticles.new),
          podcastControllerProvider.overrideWith(_FakePodcast.new),
          radioProvider.overrideWith(_FakeRadio.new),
          podcastPlayerProvider.overrideWith(_FakePodcastPlayer.new),
          searchIndexProvider.overrideWith(_FakeSearchIndex.new),
          categoriesProvider.overrideWith((ref) async => <Category>[]),
          latestEpisodeProvider.overrideWith((ref) async => null),
        ],
        child: const RadioApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Notizie'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Impostazioni'), findsOneWidget);
  });
}
