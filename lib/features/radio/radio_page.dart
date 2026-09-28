import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/remote_image.dart';
import 'radio_notifier.dart';

class RadioPage extends ConsumerWidget {
  const RadioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    // Aviso al usuario cuando el sistema cambia solo a calidad de vídeo baja.
    ref.listen(
      radioProvider.select((r) => r.videoAutoSwitchedToLow),
      (_, next) {
        if (!next) return;
        ref.read(radioProvider.notifier).clearAutoSwitchFlag();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.videoAutoSwitched),
          duration: const Duration(seconds: 4),
        ));
      },
    );
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: ref.read(radioProvider.notifier).refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          children: [
            const SizedBox(height: 4),
            const _ModeChips(),
            const SizedBox(height: 10),
            const _PlayerCard(),
            const SizedBox(height: 24),
            const _UpNextSection(),
            const _HistorySection(),
          ],
        ),
      ),
    );
  }
}

// ── Tarjeta reproductor ───────────────────────────────────────────────────────

class _PlayerCard extends ConsumerWidget {
  const _PlayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    // L14: solo los campos que pinta la tarjeta (el volumen tiene su propio
    // Consumer), para no reconstruirla entera al arrastrar el slider.
    final playing = ref.watch(radioProvider.select((r) => r.playing));
    final loading = ref.watch(radioProvider.select((r) => r.loading));
    final nowPlaying = ref.watch(radioProvider.select((r) => r.nowPlaying));
    final hasError = ref.watch(radioProvider.select((r) => r.hasError));
    final videoMode = ref.watch(radioProvider.select((r) => r.videoMode));

    return Container(
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
          if (videoMode) ...[
            // ── Modo vídeo ─────────────────────────────────────────────────
            const _VideoWidget(),
            const SizedBox(height: 12),
            Text(
              s.nowPlaying,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              nowPlaying.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ] else ...[
            // ── Modo audio (diseño original) ────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => ref.read(radioProvider.notifier).playPause(),
                  child: _Artwork(playing: playing, artworkUrl: nowPlaying.artworkUrl),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.nowPlaying,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nowPlaying.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (nowPlaying.artist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nowPlaying.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              GestureDetector(
                onTap: () => videoMode
                    ? ref.read(radioProvider.notifier).videoPlayPause()
                    : ref.read(radioProvider.notifier).playPause(),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            color: AppColors.brand,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: AppColors.brand,
                          size: 28,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(child: _VolumeControl()),
            ],
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white60, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.streamError,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => videoMode
                        ? ref.read(radioProvider.notifier).videoPlayPause()
                        : ref.read(radioProvider.notifier).playPause(),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.refresh,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Slider de volumen aislado: observa SOLO r.volume (L14), así arrastrarlo no
// reconstruye toda la tarjeta del reproductor (título, carátula, etc.).
class _VolumeControl extends ConsumerWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(radioProvider.select((r) => r.volume));
    return Row(
      children: [
        const Icon(Icons.volume_down, color: Colors.white60, size: 20),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withValues(alpha: .15),
            ),
            child: Slider(
              value: volume,
              onChanged: (v) => ref.read(radioProvider.notifier).setVolume(v),
            ),
          ),
        ),
        const Icon(Icons.volume_up, color: Colors.white60, size: 20),
      ],
    );
  }
}

// ── Artwork con ecualizador animado ──────────────────────────────────────────

class _Artwork extends StatefulWidget {
  final bool playing;
  final String? artworkUrl;
  const _Artwork({required this.playing, this.artworkUrl});

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork>
    with SingleTickerProviderStateMixin {
  // Se inicializa en initState (no perezoso): si no, al destruir el widget sin
  // haber reproducido nunca, dispose crearía el controller y petaría.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(_Artwork old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7A3D), Color(0xFFBC0A26)],
        ),
      ),
      child: Stack(
        children: [
          // Carátula real del track actual (URL obtenida de artwork.rcast.net)
          RemoteImage(
            url: widget.artworkUrl,
            width: 80,
            height: 80,
            radius: 14,
          ),
          // Ecualizador encima cuando está reproduciendo
          if (widget.playing)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .55),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) {
                      const phases = [0.0, 1.1, 2.2, 3.3, 4.4];
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final phase in phases)
                            _EqBar(
                              height:
                                  4 +
                                  14 *
                                      ((sin(_c.value * 2 * pi + phase) + 1) /
                                          2),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Toggle Audio / Vídeo ─────────────────────────────────────────────────────

class _ModeChips extends ConsumerWidget {
  const _ModeChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final videoMode = ref.watch(radioProvider.select((r) => r.videoMode));

    Widget chip(String label, IconData icon, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.brand : Colors.transparent,
            border: Border.all(
              color: active
                  ? AppColors.brand
                  : (dark ? Colors.white30 : Colors.black26),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : null),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        chip(
          'Audio',
          Icons.radio,
          !videoMode,
          () => ref.read(radioProvider.notifier).setVideoMode(false),
        ),
        const SizedBox(width: 8),
        chip(
          'Video',
          Icons.videocam,
          videoMode,
          () => ref.read(radioProvider.notifier).setVideoMode(true),
        ),
      ],
    );
  }
}

// ── Reproductor de vídeo embebido ─────────────────────────────────────────────

class _VideoWidget extends ConsumerWidget {
  const _VideoWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    // videoToken cambia cuando el controller se crea o destruye → reconstruye.
    ref.watch(radioProvider.select((st) => st.videoToken));
    final playing = ref.watch(radioProvider.select((st) => st.playing));
    final loading = ref.watch(radioProvider.select((st) => st.loading));
    final fullscreen = ref.watch(radioProvider.select((st) => st.videoFullscreen));
    final wc = ref.read(radioProvider.notifier).webController;

    // En web el vídeo del directo no está disponible (solo en la app nativa):
    // mostramos un aviso en su lugar.
    if (kIsWeb) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: const Color(0xFF4A0410),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            child: Text(
              s.videoAppOnly,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
        ),
      );
    }

    // Parado/pausado: se mantiene el recuadro con la marca de RadioApp en vez
    // de esconderlo. Antes desaparecía y la pantalla quedaba compacta, sin que se
    // entendiera dónde iba a salir el vídeo. Al dar play el vídeo aparece
    // justo aquí, con este mismo tamaño (mismo marco).
    if (!playing && !loading) {
      return GestureDetector(
        onTap: () => ref.read(radioProvider.notifier).videoPlayPause(),
        child: const _VideoFrame(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brand, Color(0xFF7A0816)],
          ),
          child: Center(
            child: FractionallySizedBox(
              heightFactor: .46,
              child: Image(
                image: AssetImage('assets/splash_mark.png'),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    }

    return _VideoFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Reproductor: player HTML embebido (WebView). Mientras se ve a
          // pantalla completa NO se monta aquí: el mismo WebViewController vive
          // en la página fullscreen (no puede estar en dos WebViewWidget a la vez).
          if (wc != null && !fullscreen) WebViewWidget(controller: wc),
          // Con el vídeo en pantalla completa, la tarjeta inline queda como
          // hueco oscuro con un aviso hasta que se vuelve.
          if (fullscreen)
            Center(
              child: Text(
                s.videoFullscreenHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
          // Spinner de carga
          if (loading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          // Botón de pantalla completa (el player va con controls=false, así
          // que el fullscreen lo aporta la app). Oculto mientras conecta o si ya
          // estamos en fullscreen.
          if (wc != null && !loading && !fullscreen)
            Positioned(
              right: 6,
              bottom: 6,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  iconSize: 22,
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                  tooltip: s.videoFullscreen,
                  onPressed: () => _openVideoFullscreen(context, ref),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Abre el vídeo a pantalla completa en horizontal reutilizando el mismo
  /// WebViewController. El flag videoFullscreen saca primero el WebView de la
  /// tarjeta inline (los `await` de orientación dan margen a ese re-render antes
  /// de montar la página fullscreen → nunca hay dos WebViewWidget con el mismo
  /// controller a la vez). Al volver se restaura el modo vertical.
  Future<void> _openVideoFullscreen(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(radioProvider.notifier);
    final navigator = Navigator.of(context);
    notifier.setVideoFullscreen(true);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const _VideoFullscreenPage(),
      ),
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    notifier.setVideoFullscreen(false);
  }
}

/// Marco del vídeo del directo: 16:9 con esquinas redondeadas. Lo comparten el
/// recuadro de espera (marca de Unica) y el vídeo en marcha, así que al dar play
/// el vídeo sale exactamente en el mismo sitio y con el mismo tamaño.
class _VideoFrame extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  const _VideoFrame({required this.child, this.gradient});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Sin degradado: fondo oscuro mientras conecta / detrás del vídeo.
            color: gradient == null ? const Color(0xFF4A0410) : null,
            gradient: gradient,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Página a pantalla completa del vídeo en directo. Muestra el MISMO
/// WebViewController que la tarjeta inline (que mientras tanto no lo monta) y un
/// botón para salir. Al hacer pop, _openVideoFullscreen restaura la orientación.
class _VideoFullscreenPage extends ConsumerWidget {
  const _VideoFullscreenPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // videoToken cambia al entrar/salir de fullscreen → re-monta el WebView.
    ref.watch(radioProvider.select((st) => st.videoToken));
    final wc = ref.read(radioProvider.notifier).webController;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (wc != null) WebViewWidget(controller: wc),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    iconSize: 26,
                    icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EqBar extends StatelessWidget {
  final double height;
  const _EqBar({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

// ── "A continuación" (próximas, de nextsongs) ────────────────────────────────

class _UpNextSection extends ConsumerWidget {
  const _UpNextSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    final upNext = ref.watch(radioProvider.select((r) => r.upNext));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppColors.mutedDark : AppColors.mutedLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.upNext, style: AppTheme.display(context, size: 26)),
        const SizedBox(height: 12),
        // Si no hay cola programada (directo/programa), en vez de ocultar la
        // sección mostramos una nota, para que el usuario sepa que no falla.
        if (upNext.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              s.upNextEmpty,
              style: TextStyle(
                color: muted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final track in upNext) _SongRow(track: track),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── "Sonó antes" (historial real, de lastsongs) ──────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sProvider);
    // L14: observamos solo history + nowPlaying (no todo el estado) para no
    // reconstruir la lista en cada poll ni al mover el volumen.
    final hist = ref.watch(radioProvider.select((r) => r.history));
    final now = ref.watch(radioProvider.select((r) => r.nowPlaying));
    final history = hist.where((t) => t != now).take(6).toList();
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.playedBefore, style: AppTheme.display(context, size: 26)),
        const SizedBox(height: 12),
        for (final track in history) _SongRow(track: track),
      ],
    );
  }
}

// Fila de canción: hora (si la hay) + título/artista. Texto, sin carátula —
// lastsongs/nextsongs no dan cover por canción.
class _SongRow extends StatelessWidget {
  final NowPlaying track;
  const _SongRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? AppColors.mutedDark : AppColors.mutedLight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (track.time != null) ...[
            SizedBox(
              width: 40,
              child: Text(
                track.time!,
                style: TextStyle(
                  color: muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (track.artist.isNotEmpty)
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
