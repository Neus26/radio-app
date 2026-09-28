import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/util/share_util.dart';
import '../../data/models/article.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../shared/util/text_search.dart';
import '../../shared/widgets/load_more_button.dart';
import '../../shared/widgets/remote_image.dart';
import '../../shared/widgets/search_field.dart';
import 'podcast_notifier.dart';

bool _isInterview(PodcastEpisode ep) =>
    ep.title.toLowerCase().contains('intervista');

class PodcastPage extends ConsumerWidget {
  const PodcastPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    // Reproductor, buscador y chips quedan fijos arriba; abajo, la lista de
    // episodios de cada sección, que se pasa deslizando en horizontal.
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: _PlayerCard(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: SearchField(query: podcastQueryProvider, hint: s.searchHint),
          ),
          const Expanded(child: _SectionPager()),
        ],
      ),
    );
  }
}

/// Chips de sección (Todos · Podcast · Entrevistas) + las tres listas: deslizar
/// en horizontal cambia de sección y tocar un chip anima hasta ella.
/// `podcastSectionProvider` se actualiza desde `onPageChanged`.
class _SectionPager extends ConsumerStatefulWidget {
  const _SectionPager();

  @override
  ConsumerState<_SectionPager> createState() => _SectionPagerState();
}

class _SectionPagerState extends ConsumerState<_SectionPager> {
  // Arranca en la sección que ya estuviera elegida (se conserva al cambiar de
  // pestaña, porque el shell mantiene las páginas vivas).
  late final PageController _pager =
      PageController(initialPage: ref.read(podcastSectionProvider));
  late int _page = ref.read(podcastSectionProvider);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _goTo(int i) => _pager.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);
    final labels = [s.allChip, 'Podcast', s.interviews];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 9),
                _Chip(
                  label: labels[i],
                  active: i == _page,
                  onTap: () => _goTo(i),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: PageView.builder(
            controller: _pager,
            itemCount: labels.length,
            onPageChanged: (i) {
              setState(() => _page = i);
              ref.read(podcastSectionProvider.notifier).state = i;
            },
            itemBuilder: (_, i) => _SectionList(section: i),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.brand
              : (dark ? AppColors.surfaceDark : AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

/// Lista de episodios de una sección (0=todos, 1=podcast, 2=entrevistas).
/// Cada sección es su propia zona con scroll y "tirar para refrescar".
class _SectionList extends ConsumerWidget {
  final int section;
  const _SectionList({required this.section});

  static const _padding = EdgeInsets.fromLTRB(18, 0, 18, 24);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final query = ref.watch(podcastQueryProvider).trim();
    final state = ref.watch(podcastControllerProvider);
    final ctrl = ref.read(podcastControllerProvider.notifier);

    // 1) Filtro de sección (client-side; el feed es siempre italiano).
    final bySection = switch (section) {
      1 => state.items.where((ep) => !_isInterview(ep)).toList(),
      2 => state.items.where(_isInterview).toList(),
      _ => state.items,
    };
    // 2) Filtro de búsqueda sobre el resultado de la sección.
    final items = query.isEmpty
        ? bySection
        : bySection.where((ep) => matchesQuery(ep.title, query)).toList();

    if (state.initialLoading) {
      return ListView(
        padding: _padding,
        children: const [_PodcastSkeleton()],
      );
    }

    final showLoadMore = query.isEmpty && state.hasMore;
    final loadMore = LoadMoreButton(
      loading: state.loadingMore,
      label: s.loadMore,
      onTap: ctrl.loadMore,
    );

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: ctrl.refresh,
      child: Builder(builder: (_) {
        if (state.error != null && state.items.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: _padding,
            children: [
              _ErrorBox(
                  message: s.podcastError, retry: s.retry, onRetry: ctrl.refresh),
            ],
          );
        }
        if (items.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: _padding,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text(query.isEmpty ? s.podcastEmpty : s.noResults,
                      style: const TextStyle(color: AppColors.mutedDark)),
                ),
              ),
              if (showLoadMore) loadMore,
            ],
          );
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: _padding,
          itemCount: items.length + (showLoadMore ? 1 : 0),
          itemBuilder: (_, i) => i >= items.length
              ? loadMore
              : _EpisodeTile(episode: items[i]),
        );
      }),
    );
  }
}

// ── Reproductor del episodio activo ──────────────────────────────────────────

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final play = ref.watch(podcastPlayerProvider);
    if (play.episode == null && !play.hasError) return const SizedBox.shrink();

    final ep = play.episode;
    final notifier = ref.read(podcastPlayerProvider.notifier);

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFBC0A26), Color(0xFF7A0816)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(alpha: .4),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RemoteImage(
                    url: ep?.imageUrl, width: 72, height: 72, radius: 12),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.tabPodcast.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ep?.title ?? '—',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ProgressBar(notifier: notifier),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: notifier.playPause,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: play.loading
                        ? const Padding(
                            padding: EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              color: AppColors.brand,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Icon(
                            play.playing ? Icons.pause : Icons.play_arrow,
                            color: AppColors.brand,
                            size: 26,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                if (play.hasError)
                  Expanded(
                    child: Text(s.noAudio,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 12)),
                  )
                else
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.volume_down,
                            color: Colors.white60, size: 20),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              overlayColor:
                                  Colors.white.withValues(alpha: .15),
                            ),
                            child: Slider(
                              value: play.volume,
                              onChanged: (v) => notifier.setVolume(v),
                            ),
                          ),
                        ),
                        const Icon(Icons.volume_up,
                            color: Colors.white60, size: 20),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final PodcastNotifier notifier;
  const _ProgressBar({required this.notifier});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: notifier.player.positionStream,
      builder: (_, posSnap) {
        return StreamBuilder<Duration?>(
          stream: notifier.player.durationStream,
          builder: (_, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final fraction =
                dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;
            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: .15),
                  ),
                  child: Slider(
                    value: fraction.clamp(0.0, 1.0),
                    onChanged: dur.inMilliseconds > 0
                        ? (v) => notifier
                            .seek(Duration(milliseconds: (v * dur.inMilliseconds).round()))
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                      Text(_fmt(dur),
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── Fila de episodio ──────────────────────────────────────────────────────────

class _EpisodeTile extends ConsumerWidget {
  final PodcastEpisode episode;
  const _EpisodeTile({required this.episode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final play = ref.watch(podcastPlayerProvider);
    final notifier = ref.read(podcastPlayerProvider.notifier);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isActive = play.episode?.id == episode.id;
    final muted = dark ? AppColors.mutedDark : AppColors.mutedLight;

    return InkWell(
      onTap: () => notifier.playEpisode(episode),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            RemoteImage(
                url: episode.imageUrl, width: 56, height: 56, radius: 10),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isActive ? AppColors.brand : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMM yyyy', ref.watch(langProvider).code)
                        .format(episode.date),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _ShareEpisodeButton(episode: episode),
            const SizedBox(width: 6),
            _PlayButton(episode: episode, play: play, notifier: notifier),
          ],
        ),
      ),
    );
  }
}

class _ShareEpisodeButton extends ConsumerWidget {
  final PodcastEpisode episode;
  const _ShareEpisodeButton({required this.episode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (episode.title.isEmpty) return const SizedBox.shrink();
    final s = ref.watch(sProvider);
    return GestureDetector(
      onTap: () => shareContent(
        context, s,
        title: episode.title,
        url: appRedirectUrl(type: 'podcast', id: episode.id),
      ),
      child: const Icon(Icons.share_outlined, size: 20, color: AppColors.mutedDark),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final PodcastEpisode episode;
  final PodcastPlayState play;
  final PodcastNotifier notifier;
  const _PlayButton(
      {required this.episode, required this.play, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final isActive = play.episode?.id == episode.id;
    final noAudio = episode.audioUrl == null || episode.audioUrl!.isEmpty;

    return GestureDetector(
      onTap: noAudio ? null : () => notifier.playEpisode(episode),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isActive ? AppColors.brand : AppColors.brand.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: isActive && play.loading
            ? const Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Icon(
                isActive && play.playing ? Icons.pause : Icons.play_arrow,
                color: isActive ? Colors.white : AppColors.brand,
                size: 20,
              ),
      ),
    );
  }
}

// ── Skeleton y error ──────────────────────────────────────────────────────────

class _PodcastSkeleton extends StatelessWidget {
  const _PodcastSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double w = double.infinity, double r = 10}) =>
        Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return Column(
      children: [
        for (var i = 0; i < 6; i++) ...[
          Row(
            children: [
              box(56, w: 56, r: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    box(14, w: double.infinity),
                    const SizedBox(height: 6),
                    box(12, w: 120),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              box(36, w: 36, r: 18),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final String retry;
  final Future<void> Function() onRetry;
  const _ErrorBox(
      {required this.message, required this.retry, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, color: AppColors.mutedDark, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.mutedDark)),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: Text(retry)),
        ],
      ),
    );
  }
}
