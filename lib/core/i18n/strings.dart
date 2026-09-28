import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idiomas soportados. `code` = código ISO (y prefijo de URL en Polylang),
/// `native` = nombre en su idioma, `rtl` = escritura derecha→izquierda.
enum AppLang {
  it('it', 'Italiano', false),
  en('en', 'English', false),
  es('es', 'Español', false),
  de('de', 'Deutsch', false),
  ru('ru', 'Русский', false),
  fr('fr', 'Français', false),
  ar('ar', 'العربية', true),
  zh('zh', '中文', false),
  pt('pt', 'Português', false);

  final String code;
  final String native;
  final bool rtl;
  const AppLang(this.code, this.native, this.rtl);
}

/// Detecta el idioma del dispositivo; si no está soportado, cae a italiano.
AppLang _detectDeviceLang() {
  final code = PlatformDispatcher.instance.locale.languageCode;
  return AppLang.values.firstWhere((l) => l.code == code,
      orElse: () => AppLang.it);
}

/// Instancia de SharedPreferences (se inyecta en `main` tras cargarla).
final sharedPreferencesProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('sharedPreferencesProvider sin inicializar'));

/// Clave de SharedPreferences donde se persiste el idioma elegido.
const String kLangPrefsKey = 'lang';
const _kTheme = 'theme';

/// Idioma guardado, leído directamente de prefs SIN Riverpod. Lo usa el catálogo
/// del coche: Android Auto puede arrancar la app en frío (solo el servicio de
/// medios, sin UI) y ahí los providers no existen.
AppLang langFromPrefs(SharedPreferences prefs) {
  final saved = prefs.getString(kLangPrefsKey);
  if (saved != null) {
    for (final l in AppLang.values) {
      if (l.code == saved) return l;
    }
  }
  return _detectDeviceLang();
}

/// Idioma actual: el guardado por el usuario; si no, el del móvil.
/// Reutiliza `langFromPrefs` para que la app y el coche no se desincronicen.
final langProvider = StateProvider<AppLang>(
    (ref) => langFromPrefs(ref.watch(sharedPreferencesProvider)));

/// Tema actual: el guardado por el usuario; si no, claro.
final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final saved = ref.watch(sharedPreferencesProvider).getString(_kTheme);
  return saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
});

/// Cambia el idioma y lo persiste.
void setLang(WidgetRef ref, AppLang lang) {
  ref.read(langProvider.notifier).state = lang;
  ref.read(sharedPreferencesProvider).setString(kLangPrefsKey, lang.code);
}

/// Cambia el tema y lo persiste.
void setThemeMode(WidgetRef ref, ThemeMode mode) {
  ref.read(themeModeProvider.notifier).state = mode;
  ref
      .read(sharedPreferencesProvider)
      .setString(_kTheme, mode == ThemeMode.light ? 'light' : 'dark');
}

// Orden de las traducciones: it, en, es, de, ru, fr, ar, zh, pt
const Map<String, List<String>> _tr = {
  'tabHome': ['Home', 'Home', 'Inicio', 'Home', 'Главная', 'Accueil', 'الرئيسية', '首页', 'Início'],
  'tabNews': ['Notizie', 'News', 'Noticias', 'News', 'Новости', 'Actualités', 'الأخبار', '新闻', 'Notícias'],
  'tabPodcast': ['Podcast', 'Podcast', 'Podcast', 'Podcast', 'Подкаст', 'Podcast', 'البودكاست', '播客', 'Podcast'],
  'tabRadio': ['Radio', 'Radio', 'Radio', 'Radio', 'Радио', 'Radio', 'راديو', '电台', 'Rádio'],
  'tabMore': ['Impostazioni', 'Settings', 'Ajustes', 'Einstellungen', 'Настройки', 'Réglages', 'الإعدادات', '设置', 'Definições'],
  'live': ['IN DIRETTA', 'ON AIR', 'EN DIRECTO', 'LIVE', 'В ЭФИРЕ', 'EN DIRECT', 'مباشر', '直播', 'AO VIVO'],
  'latest': ['Ultime', 'Latest', 'Lo último', 'Neueste', 'Последние', 'Dernières', 'الأحدث', '最新', 'Últimas'],
  'seeAll': ['Vedi tutto', 'See all', 'Ver todo', 'Alle', 'Все', 'Voir tout', 'عرض الكل', '查看全部', 'Ver tudo'],
  'podcastOfDay': ['PODCAST DEL GIORNO', 'PODCAST OF THE DAY', 'PODCAST DEL DÍA', 'PODCAST DES TAGES', 'ПОДКАСТ ДНЯ', 'PODCAST DU JOUR', 'بودكاست اليوم', '今日播客', 'PODCAST DO DIA'],
  'comingSoon': ['Prossimamente', 'Coming soon', 'Próximamente', 'Demnächst', 'Скоро', 'Bientôt', 'قريبًا', '即将推出', 'Em breve'],
  'sectionComingSoon': ['Questa sezione arriverà presto.', 'This section is coming soon.', 'Esta sección llegará pronto.', 'Dieser Bereich kommt bald.', 'Этот раздел скоро появится.', 'Cette section arrive bientôt.', 'سيتوفر هذا القسم قريبًا.', '此板块即将上线。', 'Esta secção chegará em breve.'],
  'searchHint': ['Cerca in RadioApp', 'Search RadioApp', 'Buscar en RadioApp', 'In RadioApp suchen', 'Поиск в RadioApp', 'Rechercher dans RadioApp', 'ابحث في RadioApp', '在 RadioApp 中搜索', 'Pesquisar na RadioApp'],
  'allChip': ['Tutto', 'All', 'Todo', 'Alle', 'Все', 'Tout', 'الكل', '全部', 'Tudo'],
  'loadMore': ['Carica altro', 'Load more', 'Cargar más', 'Mehr laden', 'Загрузить ещё', 'Charger plus', 'تحميل المزيد', '加载更多', 'Carregar mais'],
  'noResults': ['Nessun risultato', 'No results', 'Sin resultados', 'Keine Ergebnisse', 'Нет результатов', 'Aucun résultat', 'لا نتائج', '无结果', 'Sem resultados'],
  'nowPlaying': ['IN ONDA ORA', 'NOW PLAYING', 'SONANDO AHORA', 'JETZT LÄUFT', 'СЕЙЧАС ИГРАЕТ', 'EN ÉCOUTE', 'يُبثّ الآن', '正在播放', 'A TOCAR AGORA'],
  'playedBefore': ['Suonava prima', 'Played before', 'Sonó antes', 'Vorher gespielt', 'Играло ранее', 'Précédemment', 'شُغّل سابقًا', '之前播放', 'Tocou antes'],
  'upNext': ['A seguire', 'Up next', 'A continuación', 'Als Nächstes', 'Далее', 'À suivre', 'التالي', '即将播放', 'A seguir'],
  'audioQuality': ['Qualità audio', 'Audio quality', 'Calidad de audio', 'Audioqualität', 'Качество звука', 'Qualité audio', 'جودة الصوت', '音频质量', 'Qualidade de áudio'],
  'developedBy': ['Sviluppato da', 'Developed by', 'Desarrollado por', 'Entwickelt von', 'Разработано', 'Développé par', 'تطوير', '开发者', 'Desenvolvido por'],
  'qHigh': ['Alta', 'High', 'Alta', 'Hoch', 'Высокое', 'Haute', 'عالية', '高', 'Alta'],
  'qMedium': ['Media', 'Medium', 'Media', 'Mittel', 'Среднее', 'Moyenne', 'متوسطة', '中', 'Média'],
  'qLow': ['Bassa', 'Low', 'Baja', 'Niedrig', 'Низкое', 'Basse', 'منخفضة', '低', 'Baixa'],
  'streamError': ['Impossibile collegarsi allo stream.', "Couldn't connect to the stream.", 'No se pudo conectar al stream.', 'Verbindung zum Stream fehlgeschlagen.', 'Не удалось подключиться к потоку.', 'Impossible de se connecter au flux.', 'تعذّر الاتصال بالبث.', '无法连接到直播流。', 'Não foi possível ligar ao stream.'],
  'retry': ['Riprova', 'Retry', 'Reintentar', 'Erneut', 'Повторить', 'Réessayer', 'إعادة المحاولة', '重试', 'Repetir'],
  'loadError': ['Impossibile caricare il contenuto.', "Couldn't load the content.", 'No se pudo cargar el contenido.', 'Inhalt konnte nicht geladen werden.', 'Не удалось загрузить контент.', 'Impossible de charger le contenu.', 'تعذّر تحميل المحتوى.', '无法加载内容。', 'Não foi possível carregar o conteúdo.'],
  'appearance': ['Aspetto', 'Appearance', 'Apariencia', 'Darstellung', 'Внешний вид', 'Apparence', 'المظهر', '外观', 'Aparência'],
  'theme': ['Tema', 'Theme', 'Tema', 'Thema', 'Тема', 'Thème', 'السمة', '主题', 'Tema'],
  'light': ['Chiaro', 'Light', 'Claro', 'Hell', 'Светлая', 'Clair', 'فاتح', '浅色', 'Claro'],
  'dark': ['Scuro', 'Dark', 'Oscuro', 'Dunkel', 'Тёмная', 'Sombre', 'داكن', '深色', 'Escuro'],
  'language': ['Lingua', 'Language', 'Idioma', 'Sprache', 'Язык', 'Langue', 'اللغة', '语言', 'Idioma'],
  'content': ['Contenuti', 'Content', 'Contenido', 'Inhalte', 'Контент', 'Contenu', 'المحتوى', '内容', 'Conteúdo'],
  'subscribe': ['Abbonati al podcast', 'Subscribe to podcast', 'Suscribir al podcast', 'Podcast abonnieren', 'Подписаться на подкаст', "S'abonner au podcast", 'اشترك في البودكاست', '订阅播客', 'Subscrever o podcast'],
  'notifications': ['Notifiche', 'Notifications', 'Notificaciones', 'Mitteilungen', 'Уведомления', 'Notifications', 'الإشعارات', '通知', 'Notificações'],
  'social': ['Social', 'Social', 'Redes sociales', 'Social', 'Соцсети', 'Réseaux sociaux', 'وسائل التواصل', '社交', 'Redes sociais'],
  'contact': ['Contatti', 'Contact', 'Contacto', 'Kontakt', 'Контакты', 'Contact', 'اتصل بنا', '联系', 'Contacto'],
  'episodes': ['Episodi', 'Episodes', 'Episodios', 'Episoden', 'Эпизоды', 'Épisodes', 'الحلقات', '分集', 'Episódios'],
  'podcastError': ['Impossibile caricare i podcast.', "Couldn't load podcasts.", 'No se pudieron cargar los podcasts.', 'Podcasts konnten nicht geladen werden.', 'Не удалось загрузить подкасты.', 'Impossible de charger les podcasts.', 'تعذّر تحميل البودكاست.', '无法加载播客。', 'Não foi possível carregar os podcasts.'],
  'podcastEmpty': ['Nessun episodio disponibile.', 'No episodes available.', 'Sin episodios disponibles.', 'Keine Episoden verfügbar.', 'Нет доступных эпизодов.', 'Aucun épisode disponible.', 'لا توجد حلقات متاحة.', '无可用分集。', 'Sem episódios disponíveis.'],
  'noAudio': ['Audio non disponibile per questo episodio.', 'Audio not available for this episode.', 'Audio no disponible para este episodio.', 'Audio für diese Episode nicht verfügbar.', 'Аудио недоступно для этого эпизода.', 'Audio non disponible pour cet épisode.', 'الصوت غير متاح لهذه الحلقة.', '此分集无音频。', 'Áudio não disponível para este episódio.'],
  'newsletter': ['Newsletter', 'Newsletter', 'Boletín', 'Newsletter', 'Рассылка', 'Newsletter', 'النشرة البريدية', '邮件订阅', 'Newsletter'],
  'newsletterDesc': ['Ricevi le novità di RadioApp via email.', 'Get RadioApp news by email.', 'Recibe las novedades de RadioApp por email.', 'Erhalte Neuigkeiten von RadioApp per E-Mail.', 'Получайте новости RadioApp по почте.', "Reçois les actus de RadioApp par email.", 'استقبل أخبار RadioApp عبر البريد.', '通过邮件接收 RadioApp 的最新消息。', 'Recebe as novidades da RadioApp por email.'],
  'emailHint': ['La tua email', 'Your email', 'Tu email', 'Deine E-Mail', 'Ваш e-mail', 'Ton email', 'بريدك الإلكتروني', '你的邮箱', 'O teu email'],
  'subscribeBtn': ['Iscriviti', 'Subscribe', 'Suscribirse', 'Abonnieren', 'Подписаться', "S'abonner", 'اشترك', '订阅', 'Subscrever'],
  'newsletterOk': ['Fatto! Controlla la tua email per confermare.', 'Done! Check your email to confirm.', '¡Listo! Revisa tu correo para confirmar.', 'Fertig! Bestätige über die E-Mail.', 'Готово! Проверьте почту для подтверждения.', "C'est fait ! Confirme via ton email.", 'تم! تحقق من بريدك للتأكيد.', '完成！请查收邮件确认。', 'Pronto! Confirma no teu email.'],
  'newsletterErr': ['Non riuscito. Riprova.', "Couldn't subscribe. Try again.", 'No se pudo. Inténtalo de nuevo.', 'Fehlgeschlagen. Versuch es erneut.', 'Не удалось. Попробуйте снова.', 'Échec. Réessaie.', 'تعذّر الاشتراك. حاول مجددًا.', '订阅失败，请重试。', 'Falhou. Tenta de novo.'],
  'invalidEmail': ['Email non valida', 'Invalid email', 'Email no válido', 'Ungültige E-Mail', 'Неверный e-mail', 'Email invalide', 'بريد غير صالح', '邮箱无效', 'Email inválido'],
  'resultsWord': ['risultati', 'results', 'resultados', 'Ergebnisse', 'результатов', 'résultats', 'نتيجة', '条结果', 'resultados'],
  'searchArchiveBtn': ['Cerca in tutto l\'archivio', 'Search the full archive', 'Buscar en todo el archivo', 'Gesamtes Archiv durchsuchen', 'Искать во всём архиве', "Chercher dans toute l'archive", 'ابحث في كامل الأرشيف', '搜索完整存档', 'Pesquisar todo o arquivo'],
  'searchArchiveTitle': ['Dall\'archivio', 'From the archive', 'Del archivo', 'Aus dem Archiv', 'Из архива', "Depuis l'archive", 'من الأرشيف', '来自存档', 'Do arquivo'],
  'searchArchiveHint': ['Ricerca nel server, può richiedere qualche secondo…', 'Searching the server, this may take a few seconds…', 'Buscando en el servidor, puede tardar unos segundos…', 'Server wird durchsucht, kann ein paar Sekunden dauern…', 'Поиск на сервере, это может занять несколько секунд…', 'Recherche sur le serveur, cela peut prendre quelques secondes…', 'يجري البحث في الخادم، قد يستغرق بضع ثوانٍ…', '正在搜索服务器，可能需要几秒…', 'A pesquisar no servidor, pode demorar uns segundos…'],
  'searchArchiveEmpty': ['Niente anche nell\'archivio.', 'Nothing in the archive either.', 'Nada tampoco en el archivo.', 'Auch im Archiv nichts gefunden.', 'В архиве тоже ничего.', "Rien dans l'archive non plus.", 'لا شيء في الأرشيف أيضًا.', '存档中也没有结果。', 'Nada no arquivo também.'],
  'share': ['Condividi', 'Share', 'Compartir', 'Teilen', 'Поделиться', 'Partager', 'مشاركة', '分享', 'Compartilhar'],
  'linkCopied': ['Link copiato!', 'Link copied!', '¡Enlace copiado!', 'Link kopiert!', 'Ссылка скопирована!', 'Lien copié !', 'تم نسخ الرابط!', '链接已复制！', 'Link copiado!'],
  'connBanner': ['Problemi di connessione. Alcune cose potrebbero non funzionare.', 'Connection problems. Some things may not work.', 'Problemas de conexión. Algunas cosas pueden no funcionar.', 'Verbindungsprobleme. Einige Funktionen könnten nicht gehen.', 'Проблемы с подключением. Некоторые функции могут не работать.', 'Problèmes de connexion. Certaines choses peuvent ne pas fonctionner.', 'مشاكل في الاتصال. قد لا تعمل بعض الميزات.', '连接出现问题，部分功能可能无法使用。', 'Problemas de ligação. Algumas coisas podem não funcionar.'],
  'privacy': ['Privacy', 'Privacy', 'Privacidad', 'Datenschutz', 'Конфиденциальность', 'Confidentialité', 'الخصوصية', '隐私', 'Privacidade'],
  'analyticsTitle': ['Aiutaci a migliorare', 'Help us improve', 'Ayúdanos a mejorar', 'Hilf uns, besser zu werden', 'Помогите нам стать лучше', 'Aidez-nous à nous améliorer', 'ساعدنا على التحسّن', '帮助我们改进', 'Ajude-nos a melhorar'],
  'analyticsBody': ['Possiamo raccogliere dati di utilizzo anonimi per migliorare l\'app? Puoi cambiare idea quando vuoi nelle Impostazioni.', 'May we collect anonymous usage data to improve the app? You can change this anytime in Settings.', '¿Podemos recopilar datos de uso anónimos para mejorar la app? Puedes cambiarlo cuando quieras en Ajustes.', 'Dürfen wir anonyme Nutzungsdaten erfassen, um die App zu verbessern? Du kannst dies jederzeit in den Einstellungen ändern.', 'Можно собирать анонимные данные об использовании, чтобы улучшать приложение? Это можно изменить в любой момент в настройках.', 'Pouvons-nous collecter des données d\'utilisation anonymes pour améliorer l\'application ? Vous pouvez changer d\'avis à tout moment dans les Réglages.', 'هل تسمح لنا بجمع بيانات استخدام مجهولة لتحسين التطبيق؟ يمكنك تغيير ذلك في أي وقت من الإعدادات.', '我们可以收集匿名使用数据来改进应用吗？你可以随时在设置中更改。', 'Podemos recolher dados de utilização anónimos para melhorar a app? Podes alterar isto a qualquer momento nas Definições.'],
  'analyticsAllow': ['Consenti', 'Allow', 'Permitir', 'Erlauben', 'Разрешить', 'Autoriser', 'السماح', '允许', 'Permitir'],
  'analyticsDeny': ['Rifiuta', 'Decline', 'Rechazar', 'Ablehnen', 'Отклонить', 'Refuser', 'رفض', '拒绝', 'Recusar'],
  'analyticsToggle': ['Analitica anonima', 'Anonymous analytics', 'Analítica anónima', 'Anonyme Analyse', 'Анонимная аналитика', 'Analyses anonymes', 'تحليلات مجهولة', '匿名分析', 'Análise anónima'],
  'videoTapPlay': ['Premi play per vedere la diretta', 'Tap play to watch live', 'Pulsa play para ver el directo', 'Play drücken für den Livestream', 'Нажмите play, чтобы смотреть эфир', 'Appuie sur play pour voir le direct', 'اضغط play لمشاهدة البث المباشر', '点击播放观看直播', 'Toca em play para ver em direto'],
  'videoAppOnly': ['Video disponibile solo nell\'app', 'Video available only in the app', 'Vídeo disponible solo en la app', 'Video nur in der App verfügbar', 'Видео доступно только в приложении', 'Vidéo disponible uniquement dans l\'app', 'الفيديو متاح فقط في التطبيق', '视频仅在应用中可用', 'Vídeo disponível apenas na app'],
  'videoFullscreen': ['Schermo intero', 'Fullscreen', 'Pantalla completa', 'Vollbild', 'Полный экран', 'Plein écran', 'ملء الشاشة', '全屏', 'Ecrã inteiro'],
  'videoFullscreenHint': ['Video a schermo intero', 'Video playing fullscreen', 'Vídeo a pantalla completa', 'Video im Vollbild', 'Видео на весь экран', 'Vidéo en plein écran', 'الفيديو بملء الشاشة', '视频全屏播放', 'Vídeo em ecrã inteiro'],
  'upNextEmpty': ['Nessuna canzone in programma al momento.', 'No upcoming songs scheduled right now.', 'Sin próximas canciones programadas por ahora.', 'Zurzeit keine nächsten Titel geplant.', 'Сейчас нет запланированных песен.', 'Aucun titre programmé pour le moment.', 'لا توجد أغانٍ مجدولة حاليًا.', '暂无接下来的曲目安排。', 'Sem próximas músicas programadas por agora.'],
  'interviews': ['Interviste', 'Interviews', 'Entrevistas', 'Interviews', 'Интервью', 'Interviews', 'مقابلات', '访谈', 'Entrevistas'],
  // Nombre de la carpeta de podcasts en el coche (Android Auto). No se puede
  // componer de tabPodcast + interviews: el conector depende del idioma.
  // La sección de radio del coche reutiliza 'tabRadio' (ya vale en los 9).
  'carPodcasts': ['Podcast e interviste', 'Podcasts and interviews', 'Podcasts y entrevistas', 'Podcasts und Interviews', 'Подкасты и интервью', 'Podcasts et interviews', 'بودكاست ومقابلات', '播客与访谈', 'Podcasts e entrevistas'],
  // Tiempo relativo ("hace X"). {n} se sustituye por el número.
  'videoQuality': ['Qualità video', 'Video quality', 'Calidad de vídeo', 'Videoqualität', 'Качество видео', 'Qualité vidéo', 'جودة الفيديو', '视频质量', 'Qualidade de vídeo'],
  'videoAutoSwitched': ['Qualità video ridotta per connessione lenta', 'Video quality reduced due to slow connection', 'Calidad de vídeo reducida por conexión lenta', 'Videoqualität wegen schwacher Verbindung gesenkt', 'Качество видео снижено из-за слабого соединения', "Qualité vidéo réduite à cause d'une connexion lente", 'تم تقليل جودة الفيديو بسبب ضعف الاتصال', '因网络较差，已切换至低画质', 'Qualidade de vídeo reduzida por ligação lenta'],
  'relMin': ['{n} min fa', '{n} min ago', 'hace {n} min', 'vor {n} Min.', '{n} мин назад', 'il y a {n} min', 'منذ {n} دقيقة', '{n} 分钟前', 'há {n} min'],
  'relHour': ['{n} ore fa', '{n}h ago', 'hace {n} h', 'vor {n} Std.', '{n} ч назад', 'il y a {n} h', 'منذ {n} ساعة', '{n} 小时前', 'há {n} h'],
  'relDay': ['{n} giorni fa', '{n}d ago', 'hace {n} d', 'vor {n} Tagen', '{n} дн назад', 'il y a {n} j', 'منذ {n} يوم', '{n} 天前', 'há {n} d'],
};

/// Strings de la app según el idioma seleccionado.
class S {
  final AppLang lang;
  const S(this.lang);

  String _(String key) {
    final list = _tr[key];
    return (list == null) ? key : list[lang.index];
  }

  String get tabHome => _('tabHome');
  String get tabNews => _('tabNews');
  String get tabPodcast => _('tabPodcast');
  String get tabRadio => _('tabRadio');
  String get tabMore => _('tabMore');
  String get live => _('live');
  String get latest => _('latest');
  String get seeAll => _('seeAll');
  String get podcastOfDay => _('podcastOfDay');
  String get comingSoon => _('comingSoon');
  String get sectionComingSoon => _('sectionComingSoon');
  String get searchHint => _('searchHint');
  String get allChip => _('allChip');
  String get loadMore => _('loadMore');
  String get noResults => _('noResults');
  String get episodes => _('episodes');
  String get podcastError => _('podcastError');
  String get podcastEmpty => _('podcastEmpty');
  String get noAudio => _('noAudio');
  String get nowPlaying => _('nowPlaying');
  String get playedBefore => _('playedBefore');
  String get upNext => _('upNext');
  String get audioQuality => _('audioQuality');
  String get developedBy => _('developedBy');
  String get qHigh => _('qHigh');
  String get qMedium => _('qMedium');
  String get qLow => _('qLow');
  String get streamError => _('streamError');
  String get retry => _('retry');
  String get loadError => _('loadError');
  String get appearance => _('appearance');
  String get theme => _('theme');
  String get light => _('light');
  String get dark => _('dark');
  String get language => _('language');
  String get content => _('content');
  String get subscribe => _('subscribe');
  String get notifications => _('notifications');
  String get social => _('social');
  String get contact => _('contact');
  String get newsletter => _('newsletter');
  String get newsletterDesc => _('newsletterDesc');
  String get emailHint => _('emailHint');
  String get subscribeBtn => _('subscribeBtn');
  String get newsletterOk => _('newsletterOk');
  String get newsletterErr => _('newsletterErr');
  String get invalidEmail => _('invalidEmail');
  String get searchArchiveBtn => _('searchArchiveBtn');
  String get searchArchiveTitle => _('searchArchiveTitle');
  String get searchArchiveHint => _('searchArchiveHint');
  String get searchArchiveEmpty => _('searchArchiveEmpty');
  String get share => _('share');
  String get linkCopied => _('linkCopied');
  String get connBanner => _('connBanner');
  String get privacy => _('privacy');
  String get analyticsTitle => _('analyticsTitle');
  String get analyticsBody => _('analyticsBody');
  String get analyticsAllow => _('analyticsAllow');
  String get analyticsDeny => _('analyticsDeny');
  String get analyticsToggle => _('analyticsToggle');
  String get videoTapPlay => _('videoTapPlay');
  String get videoAppOnly => _('videoAppOnly');
  String get videoFullscreen => _('videoFullscreen');
  String get videoFullscreenHint => _('videoFullscreenHint');
  String get upNextEmpty => _('upNextEmpty');
  String get interviews => _('interviews');
  String get carPodcasts => _('carPodcasts');
  String get videoQuality => _('videoQuality');
  String get videoAutoSwitched => _('videoAutoSwitched');
  String relMin(int n) => _('relMin').replaceFirst('{n}', '$n');
  String relHour(int n) => _('relHour').replaceFirst('{n}', '$n');
  String relDay(int n) => _('relDay').replaceFirst('{n}', '$n');
  String resultsCount(int n) => '$n ${_('resultsWord')}';
}

/// Acceso a los strings según el idioma seleccionado.
final sProvider = Provider<S>((ref) => S(ref.watch(langProvider)));
