# RadioApp — App móvil (Flutter)

> **Nota de portfolio:** esta es una copia personal, con fines de portfolio, de una app real
> que desarrollé durante un período de prácticas para una radio universitaria (nombre y
> ubicación del cliente omitidos por privacidad; "RadioApp" es un nombre ficticio para esta
> copia). No incluye secretos, claves de firma ni documentación interna de equipo. La app sigue
> consumiendo una **API pública de solo lectura** (sin autenticación) para mostrar contenido
> real de esa radio.

App **Android/iOS** hecha en **Flutter** para la radio: noticias, podcasts, radio en directo
(audio + vídeo) y ajustes, en **9 idiomas**.

---

## Qué hace la app

- **Inicio:** noticia destacada, podcast del día y últimas noticias contra la API, con
  pull-to-refresh, skeletons y manejo de errores.
- **Noticias:** buscador, chips de categoría y lista paginada. Carga ligera (posts sin
  contenido completo + URLs de imagen en una sola llamada batch) y filtrada por idioma.
- **Podcast:** episodios reales con reproductor inline (`just_audio`), barra de progreso
  seekable, pull-to-refresh y skeleton.
- **Radio:** stream en directo (audio Icecast + vídeo HLS embebido), metadata ICY, carátula
  real e historial/próximas canciones vía polling.
- **Ajustes:** tema claro/oscuro, selector de idioma (9), notificaciones, suscripción a
  newsletter, redes y contacto.
- **Android Auto:** integración de la radio y el podcast en la pantalla del coche.

## Por qué es interesante técnicamente

El sitio no tiene una API a medida: todo sale del **REST de WordPress** con **Polylang**
(el mismo artículo publicado 9 veces, una por idioma, como posts distintos) y un hosting
compartido con particularidades propias. Algunos de los problemas reales que hubo que
resolver:

- **Filtrado por idioma sin endpoint dedicado:** se deduce el idioma de un post por el
  **prefijo de su URL** (`/es/`, `/en/`… ; italiano = sin prefijo), ya que Polylang no expone
  un filtro fiable en todas las rutas.
- **Reparto desigual de traducciones:** en italiano casi todos los posts recientes están
  disponibles; en el resto de idiomas las traducciones tardan horas en llegar, así que hay
  que pedir bastantes posts en crudo y descartar los que aún no están traducidos.
- **Imágenes de posts traducidos:** las traducciones no siempre heredan la imagen destacada
  del original italiano, así que se resuelve por los metadatos de traducción de Polylang y,
  si no están, por proximidad de IDs.
- **Podcast:** el feed RSS público limita a ~9 episodios por los 9 idiomas mezclados; los
  episodios reales (con audio) se sacan en su lugar de la taxonomía `series` de la API REST,
  deduplicando por URL de audio.
- **Radio en directo:** "sonando ahora" e historial se obtienen por *polling* a un servicio
  externo (Icecast/rcast) y parseo de HTML, con reintentos y *fallback* de calidad para el
  vídeo.

## Stack

Flutter · **Riverpod** (estado) · **dio** (HTTP) · **just_audio** + **audio_service**
(audio/Android Auto) · **webview_flutter** (vídeo HLS embebido) · **google_fonts** ·
**flutter_svg** · **cached_network_image** · **xml** (parseo de RSS).

## Arquitectura (resumen)

```
lib/
  core/       → tema, i18n (9 idiomas), audio (handler, Android Auto)
  data/       → modelos + cliente de la API REST de WordPress
  features/   → home, news, article, podcast, radio, more (settings)
  shared/     → widgets y utilidades comunes
```

No hay backend propio: la app consume directamente la API REST pública de WordPress de la
radio y el stream de audio/vídeo de su proveedor de streaming.

## Ejecutar en local

Requisitos: **Flutter 3.44.1 stable** (Dart 3.12.1).

```bash
flutter pub get
flutter run -d chrome      # o con un dispositivo/emulador conectado
```

El podcast usa un feed RSS sin cabeceras CORS; en la preview web hace falta el proxy
incluido en `tool/` (ver `tool/preview-web.ps1`). En móvil funciona directo.

---

Proyecto original a dos manos; esta copia de portfolio la mantengo yo (Neus) para mostrar
el trabajo técnico. Los créditos de ambas personas siguen visibles dentro de la propia app
(pantalla "Más").
