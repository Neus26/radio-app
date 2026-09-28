import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/analytics/consent.dart';
import '../../core/audio_quality.dart';
import '../../core/video_quality.dart';
import '../../core/i18n/strings.dart';
import '../../core/theme/app_colors.dart';
import '../../data/wp_api/wp_providers.dart';
import '../../shared/widgets/brand_logo.dart';

// Enlaces de ejemplo (placeholder): en el proyecto real apuntan a los
// perfiles/plataformas oficiales de la radio; aquí se genericizan para el
// portfolio.
const _podcastLinks = <(IconData, String, String)>[
  (Icons.podcasts, 'Apple Podcasts', 'https://podcasts.apple.com/'),
  (Icons.music_note, 'Spotify', 'https://open.spotify.com/'),
  (Icons.rss_feed, 'RSS', 'https://www.unicaradio.it/podcast/feed/'),
];
const _socialLinks = <(IconData, String, String)>[
  (Icons.camera_alt_outlined, 'Instagram', 'https://www.instagram.com/'),
  (Icons.facebook, 'Facebook', 'https://www.facebook.com/'),
  (Icons.smart_display_outlined, 'YouTube', 'https://www.youtube.com/'),
  (Icons.music_note, 'TikTok', 'https://www.tiktok.com/'),
  (Icons.alternate_email, 'X (Twitter)', 'https://twitter.com/'),
];
const _contactMailto = 'mailto:contacto@example.com';
const _contactEmail = 'contacto@example.com';
const _websiteUrl = 'https://example.com';

Future<void> _open(String url, {BuildContext? context}) async {
  final uri = Uri.parse(url);
  try {
    // En web abre en pestaña nueva; en móvil lanza la app externa.
    final ok = await launchUrl(uri,
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    if (!ok) throw Exception('launchUrl returned false');
  } catch (_) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }
}

/// Pantalla "Altro / Más" (ajustes). Tema e idioma cambian la app en vivo.
class MorePage extends ConsumerStatefulWidget {
  const MorePage({super.key});

  @override
  ConsumerState<MorePage> createState() => _MorePageState();
}

class _MorePageState extends ConsumerState<MorePage> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);
    final mode = ref.watch(themeModeProvider);
    final lang = ref.watch(langProvider);
    final quality = ref.watch(audioQualityProvider);
    final videoQuality = ref.watch(videoQualityProvider);
    final isDark = mode == ThemeMode.dark;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          // ---- Contatti (arriba del todo y bien visible: Google Play exige que
          // el contacto sea fácil de encontrar — política de Noticias/Revistas).
          // Email + web como filas grandes y tocables.
          _GroupLabel(s.contact),
          _Card(children: [
            InkWell(
              onTap: () => _open(_contactMailto, context: context),
              child: const _SettingRow(
                icon: Icons.mail_outline,
                label: _contactEmail,
                trailing:
                    Icon(Icons.chevron_right, color: Color(0xFF6B6E76)),
              ),
            ),
            InkWell(
              onTap: () => _open(_websiteUrl, context: context),
              child: const _SettingRow(
                icon: Icons.public,
                label: 'www.example.com',
                trailing: Icon(Icons.open_in_new,
                    size: 18, color: Color(0xFF6B6E76)),
              ),
            ),
          ]),

          // ---- Apariencia ----
          _GroupLabel(s.appearance),
          _Card(children: [
            _SettingRow(
              icon: Icons.dark_mode_outlined,
              label: s.theme,
              trailing: _Segmented(
                options: [s.light, s.dark],
                selected: isDark ? 1 : 0,
                onChanged: (i) => setThemeMode(
                    ref, i == 0 ? ThemeMode.light : ThemeMode.dark),
              ),
            ),
            InkWell(
              onTap: () => _showLanguageSheet(context, ref),
              child: _SettingRow(
                icon: Icons.language,
                label: s.language,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(lang.native,
                      style: const TextStyle(
                          color: AppColors.brandSoft,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, color: Color(0xFF6B6E76)),
                ]),
              ),
            ),
          ]),

          // ---- Contenido ----
          _GroupLabel(s.content),
          _Card(children: [
            InkWell(
              onTap: () => _showQualitySheet(context, ref),
              child: _SettingRow(
                icon: Icons.graphic_eq,
                label: s.audioQuality,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${quality.kbps} kbps',
                      style: const TextStyle(
                          color: AppColors.brandSoft,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, color: Color(0xFF6B6E76)),
                ]),
              ),
            ),
            InkWell(
              onTap: () => _showVideoQualitySheet(context, ref),
              child: _SettingRow(
                icon: Icons.videocam_outlined,
                label: s.videoQuality,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${videoQuality.kbps} kbps',
                      style: const TextStyle(
                          color: AppColors.brandSoft,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, color: Color(0xFF6B6E76)),
                ]),
              ),
            ),
            InkWell(
              onTap: () => _showSubscribeSheet(context),
              child: _SettingRow(
                icon: Icons.rss_feed,
                label: s.subscribe,
                trailing: const Icon(Icons.chevron_right,
                    color: Color(0xFF6B6E76)),
              ),
            ),
          ]),

          // ---- Privacidad ----
          _GroupLabel(s.privacy),
          _Card(children: [
            _SettingRow(
              icon: Icons.analytics_outlined,
              label: s.analyticsToggle,
              trailing: Switch(
                value: ref.watch(analyticsConsentProvider) ==
                    AnalyticsConsent.granted,
                onChanged: (v) => setAnalyticsConsent(ref,
                    v ? AnalyticsConsent.granted : AnalyticsConsent.denied),
              ),
            ),
          ]),

          // ---- RadioApp ----
          const _GroupLabel('RadioApp'),
          _Card(children: [
            InkWell(
              onTap: () => _showLinksSheet(context, s.social, _socialLinks),
              child: _SettingRow(
                icon: Icons.public,
                label: s.social,
                trailing:
                    const Icon(Icons.chevron_right, color: Color(0xFF6B6E76)),
              ),
            ),
          ]),

          // ---- Desarrollado por ----
          _GroupLabel(s.developedBy),
          _Card(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _CreditChip(
                      user: 'viipperr', url: 'https://github.com/viipperr'),
                  _CreditChip(user: 'Neus26', url: 'https://github.com/Neus26'),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 26),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BrandLogo(
                    height: 22,
                    color: isDark
                        ? const Color(0xFF6B6E76)
                        : const Color(0xFFB3B3B8)),
                const SizedBox(width: 10),
                const Text('v1.0',
                    style: TextStyle(
                        color: Color(0xFF6B6E76),
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior para elegir entre los 9 idiomas.
void _showLanguageSheet(BuildContext context, WidgetRef ref) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final current = ref.read(langProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0xFF6B6E76),
                borderRadius: BorderRadius.circular(3)),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final l in AppLang.values)
                    ListTile(
                      title: Text(l.native,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: l == current ? AppColors.brand : null)),
                      trailing: l == current
                          ? const Icon(Icons.check, color: AppColors.brand)
                          : null,
                      onTap: () {
                        setLang(ref, l);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Hoja inferior para elegir la calidad de audio de la radio.
void _showQualitySheet(BuildContext context, WidgetRef ref) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final s = ref.read(sProvider);
  final current = ref.read(audioQualityProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0xFF6B6E76),
                borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(s.audioQuality,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final q in availableQualities)
                    ListTile(
                      title: Text(_qLabel(s, q),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: q == current ? AppColors.brand : null)),
                      subtitle: Text('${q.kbps} kbps · ${q.codec}'),
                      trailing: q == current
                          ? const Icon(Icons.check, color: AppColors.brand)
                          : null,
                      onTap: () {
                        setAudioQuality(ref, q);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Hoja inferior para elegir la calidad de vídeo del directo.
void _showVideoQualitySheet(BuildContext context, WidgetRef ref) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final s = ref.read(sProvider);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0xFF6B6E76),
                borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(s.videoQuality,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              // Consumer para que el checkmark se actualice si el auto-switch
              // cambia la calidad mientras el sheet está abierto.
              child: Consumer(
                builder: (_, cRef, __) {
                  final current = cRef.watch(videoQualityProvider);
                  return Column(
                    children: [
                      for (final q in VideoQuality.values)
                        ListTile(
                          title: Text(_vqLabel(s, q),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color:
                                      q == current ? AppColors.brand : null)),
                          subtitle: Text('${q.kbps} kbps · H264'),
                          trailing: q == current
                              ? const Icon(Icons.check, color: AppColors.brand)
                              : null,
                          onTap: () {
                            setVideoQuality(cRef, q);
                            Navigator.of(ctx).pop();
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _vqLabel(S s, VideoQuality q) => switch (q) {
      VideoQuality.high => s.qHigh,
      VideoQuality.low => s.qLow,
    };

String _qLabel(S s, AudioQuality q) => switch (q) {
      AudioQuality.high => s.qHigh,
      AudioQuality.medium => s.qMedium,
      AudioQuality.low => s.qLow,
    };

/// Hoja inferior con una lista de enlaces externos (abre en el navegador/app).
void _showLinksSheet(
    BuildContext context, String title, List<(IconData, String, String)> links) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
                color: const Color(0xFF6B6E76),
                borderRadius: BorderRadius.circular(3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final l in links)
                    ListTile(
                      leading: Icon(l.$1, color: AppColors.brand),
                      title: Text(l.$2,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.open_in_new,
                          size: 18, color: Color(0xFF6B6E76)),
                      onTap: () {
                        _open(l.$3, context: context);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Hoja "Suscribir": apps de podcast (Apple/Spotify/RSS) + alta a la newsletter.
void _showSubscribeSheet(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.surfaceDark : Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _SubscribeSheet(),
    ),
  );
}

class _SubscribeSheet extends ConsumerStatefulWidget {
  const _SubscribeSheet();
  @override
  ConsumerState<_SubscribeSheet> createState() => _SubscribeSheetState();
}

class _SubscribeSheetState extends ConsumerState<_SubscribeSheet> {
  final _email = TextEditingController();
  bool _loading = false;
  bool _ok = false;
  String? _msg;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(sProvider);
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() {
        _ok = false;
        _msg = s.invalidEmail;
      });
      return;
    }
    setState(() {
      _loading = true;
      _msg = null;
    });
    final ok = await subscribeNewsletter(
        ref.read(dioProvider), email, ref.read(langProvider).code);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ok = ok;
      _msg = ok ? s.newsletterOk : s.newsletterErr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: const Color(0xFF6B6E76),
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            const SizedBox(height: 16),
            Text(s.subscribe,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            for (final l in _podcastLinks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(l.$1, color: AppColors.brand),
                title: Text(l.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.open_in_new,
                    size: 18, color: Color(0xFF6B6E76)),
                onTap: () => _open(l.$3, context: context),
              ),
            const Divider(height: 26),
            Text(s.newsletter,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(s.newsletterDesc,
                style: const TextStyle(
                    color: Color(0xFF8D9097), fontSize: 14, height: 1.3)),
            const SizedBox(height: 14),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: s.emailHint,
                filled: true,
                fillColor:
                    dark ? const Color(0xFF111317) : const Color(0xFFF0F0F2),
                prefixIcon:
                    const Icon(Icons.mail_outline, color: Color(0xFF8D9097)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.brand.withValues(alpha: .5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : Text(s.subscribeBtn,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_msg!,
                    style: TextStyle(
                        color: _ok
                            ? const Color(0xFF3Fae6a)
                            : AppColors.brandSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: Color(0xFF7E818A),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  const _SettingRow(
      {required this.icon, required this.label, required this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.brandSoft, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Chip de crédito compacto: logo de GitHub + usuario; al tocar abre el perfil.
/// Pensado para ir dos en una fila (uno a la izquierda, otro a la derecha).
class _CreditChip extends StatelessWidget {
  final String user;
  final String url;
  const _CreditChip({required this.user, required this.url});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(url, context: context),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/github.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(
                  AppColors.brandSoft, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Text(user,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// Control segmentado de 2 opciones (pastilla roja deslizante).
class _Segmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Segmented(
      {required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1B1D21)
            : const Color(0xFFECEAEB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: i == selected ? AppColors.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(options[i],
                    style: TextStyle(
                        color: i == selected
                            ? Colors.white
                            : const Color(0xFF9DA0A7),
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }
}
