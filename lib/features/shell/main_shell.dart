import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/analytics/analytics.dart';
import '../../core/analytics/consent.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../features/article/article_detail_page.dart';
import '../../features/podcast/podcast_notifier.dart';
import '../../shared/widgets/app_header.dart';
import '../../shared/widgets/mesh_background.dart';
import '../home/home_page.dart';
import '../more/more_page.dart';
import '../news/news_page.dart';
import '../podcast/podcast_page.dart';
import '../radio/radio_page.dart';

/// Shell principal: contenido + barra inferior de 5 pestañas.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _initDeepLinks();
    Future.microtask(() => ref.read(searchIndexProvider));
    if (!kIsWeb) _requestNotificationPermission();
    // RGPD: la primera vez (solo en móvil) pedimos consentimiento de analítica.
    if (!kIsWeb) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowAnalyticsConsent());
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await Permission.notification.request();
    }
  }

  /// Diálogo de consentimiento de analítica (una sola vez). Si ya se decidió
  /// antes (concedido o rechazado), no vuelve a aparecer.
  Future<void> _maybeShowAnalyticsConsent() async {
    if (!mounted) return;
    if (ref.read(analyticsConsentProvider) != AnalyticsConsent.unknown) return;
    final s = ref.read(sProvider);
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(s.analyticsTitle),
        content: Text(s.analyticsBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.analyticsDeny),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.analyticsAllow),
          ),
        ],
      ),
    );
    if (!mounted || granted == null) return;
    setAnalyticsConsent(
        ref, granted ? AnalyticsConsent.granted : AnalyticsConsent.denied);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    // Apertura en frío: app lanzada desde un link
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null && mounted) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _handleLink(initial));
      }
    } catch (_) {}
    // App en segundo plano: link recibido mientras ya corría
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) { if (mounted) _handleLink(uri); },
      onError: (_) {}, // errores de plataforma al parsear el URI
    );
  }

  void _handleLink(Uri uri) {
    if (uri.scheme != 'radioapp') return;
    final id = int.tryParse(uri.queryParameters['id'] ?? '');
    if (id == null) return;
    switch (uri.host) {
      case 'article':
        _openArticle(id);
      case 'podcast':
        _openPodcast(id);
    }
  }

  Future<void> _openArticle(int id) async {
    try {
      final article = await ref.read(singleArticleProvider(id).future);
      if (!mounted) return;
      Analytics.instance
          .log('news_open', {'article_id': id.toString(), 'source': 'deep_link'});
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ArticleDetailPage(article: article)),
      );
    } catch (_) {}
  }

  Future<void> _openPodcast(int id) async {
    if (!mounted) return;
    // Aterriza YA en la pestaña Podcast: aunque el episodio no este en el feed
    // (episodio antiguo) o el feed falle, el deep link deja al usuario en la
    // seccion correcta en vez de no hacer nada.
    setState(() => _index = 2);
    try {
      final episodes = await ref.read(podcastFeedProvider.future);
      final ep = episodes.where((e) => e.id == id).firstOrNull;
      if (ep == null || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(podcastPlayerProvider.notifier).playEpisode(ep);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);

    final pages = [
      HomePage(onGoToPodcast: () => setState(() => _index = 2)),
      const NewsPage(),
      const PodcastPage(),
      const RadioPage(),
      const MorePage(),
    ];

    final tabs = [
      (_TabIcon.home, s.tabHome),
      (_TabIcon.news, s.tabNews),
      (_TabIcon.podcast, s.tabPodcast),
      (_TabIcon.radio, s.tabRadio),
      (_TabIcon.more, s.tabMore),
    ];

    return Scaffold(
      body: MeshBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: tabs[_index].$2,
                onLiveTap: () => setState(() => _index = 3),
                onLogoTap: () => setState(() => _index = 0),
              ),
              const _ConnectionBanner(),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        tabs: tabs,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Banner fino que avisa cuando el backend está caído / no carga. Se muestra
/// mientras dure el problema; se quita solo al recuperarse (primer éxito) o con
/// la X. El botón reintentar refresca los providers de contenido.
class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(backendHealthProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: (!health.down || health.dismissed)
          ? const SizedBox(width: double.infinity)
          : _bannerBody(ref),
    );
  }

  Widget _bannerBody(WidgetRef ref) {
    final s = ref.watch(sProvider);
    return Material(
      color: AppColors.brand,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 7, 6, 7),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.connBanner,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () {
                // Reintenta: refresca los providers de contenido. Si el backend
                // sigue caído, el interceptor lo vuelve a marcar y el banner
                // permanece; si responde, reportOk lo oculta solo.
                ref.invalidate(categoriesProvider);
                ref.invalidate(podcastFeedProvider);
                ref.invalidate(searchIndexProvider);
                ref.invalidate(articlesControllerProvider);
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(s.retry,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5)),
            ),
            IconButton(
              onPressed: () =>
                  ref.read(backendHealthProvider.notifier).dismiss(),
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TabIcon { home, news, podcast, radio, more }

IconData _iconFor(_TabIcon t, bool active) {
  switch (t) {
    case _TabIcon.home:
      return active ? Icons.home : Icons.home_outlined;
    case _TabIcon.news:
      return active ? Icons.article : Icons.article_outlined;
    case _TabIcon.podcast:
      return active ? Icons.mic : Icons.mic_none;
    case _TabIcon.radio:
      return Icons.radio;
    case _TabIcon.more:
      return Icons.menu;
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final List<(_TabIcon, String)> tabs;
  final ValueChanged<int> onTap;
  const _BottomBar(
      {required this.index, required this.tabs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barColor = dark ? AppColors.tabbarDark : AppColors.tabbarLight;
    final hairline = dark ? AppColors.hairlineDark : AppColors.hairlineLight;
    final inactive = dark ? AppColors.mutedDark : const Color(0xFFB3B3B8);

    return Container(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(top: BorderSide(color: hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: _TabItem(
                      icon: _iconFor(tabs[i].$1, i == index),
                      label: tabs[i].$2,
                      active: i == index,
                      inactive: inactive,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color inactive;
  const _TabItem(
      {required this.icon,
      required this.label,
      required this.active,
      required this.inactive});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brand : inactive;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 25),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
                color: active
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : AppColors.brand)
                    : inactive,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}
