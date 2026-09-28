# Modelo de datos — RadioApp (referencia)

Resumen del esquema real de la BBDD (WordPress) **mapeado a lo que la app necesita y a la API REST**. Estructura extraída de un export de phpMyAdmin (89 tablas). La app **no** consume la BBDD; lee la API REST. Esto es referencia para entender el contenido.

> Nota: el `.sql` de estructura está en `docs/db-sample/` (ignorado por git).

## Plataforma
- WordPress (multisite: hay `wp_blogs`, `wp_site`) sobre **Percona/MySQL 8**, charset `utf8mb4`.
- **Multilingüe = TranslatePress** (tablas `wp_trp_*`), **no Polylang**. Idiomas vistos: `it_it` (original) y `en_gb`. → **La API REST devuelve el contenido en italiano (original); las traducciones se renderizan en el front, no salen limpias por la API.** Implicación: en la app, UI en IT/ES la controlamos nosotros; el *contenido* (noticias/podcasts) llega en italiano salvo que resolvamos TRP aparte.

## Tablas relevantes para la app (de 89, estas importan)

### Contenido (noticias, páginas, podcasts)
- **`wp_posts`** — todo el contenido. Campo clave **`post_type`**: `post` (noticias), `page`, `podcast` (episodios SSP), `attachment` (medios), `tribe_events` (eventos). Campos: `ID, post_author, post_date, post_title, post_content, post_excerpt, post_status('publish'), post_name(slug), post_type, guid`.
- **`wp_postmeta`** — metadatos por post (`post_id, meta_key, meta_value`). Claves de interés: `_thumbnail_id` (imagen destacada), y para podcasts el **`audio_file`** (URL del MP3) y duración (SSP).
  → En la API: imagen vía `_embed` (`wp:featuredmedia`). Audio del podcast: confirmar `audio_file` vs RSS.

### Taxonomías (categorías / series de podcast)
- **`wp_terms`** (`term_id, name, slug`) + **`wp_term_taxonomy`** (`taxonomy`: `category`, `post_tag`, `series` de podcast, `tribe_events_cat`; `parent, count`) + **`wp_term_relationships`** (post ↔ término).
  → En la API: `wp/v2/categories` y `_embed['wp:term']`.

### Podcast
- Episodios = `wp_posts` con `post_type='podcast'`; audio/duración en `wp_postmeta`; series en taxonomía `series`. Endpoint: `ssp/v1/episodes`. Stats en `wp_ssp_stats` (no se usa para leer).

### Radio — palinsesto / horario
- **`wp_mp_timetable_data`** (plugin MP Timetable): `column_id` (día/columna), `event_id` (→ programa, normalmente un `wp_posts`), `event_start`/`event_end` (`time`), `description`. → Fuente de la **programación de radio** (pantalla Radio, fase posterior). **No** está en la API REST estándar → si la queremos, export puntual o endpoint propio del plugin.

### Eventos / agenda
- **`wp_tec_events`** (The Events Calendar): `post_id` (→ `wp_posts` tipo `tribe_events`), `start_date`, `end_date`, `timezone`. + `wp_tec_occurrences`. Endpoint: `tribe/events/v1/events`.

### Otros (referencia, no para la app v1)
- Usuarios: `wp_users`, `wp_usermeta`, `wp_ppress_*` (ProfilePress login/registro).
- TTS "Escuchar": `wp_atlasvoice_analytics` (AtlasVoice).
- Config del sitio: `wp_options` (aquí viven ajustes del stream de radio, SSP, TRP… serializados).
- Newsletter: `wp_newsletter*`. SEO: `wp_yoast_*`. Seguridad: `wp_wf*` (Wordfence). GDPR: `wp_wpgdprc_*`. Imágenes: `wp_shortpixel_*`. Acciones programadas: `wp_actionscheduler_*`, `wp_shepherd_*`. Duplicator: `wp_duplicator_*`.

## Mapeo BBDD → API → App (MVP Inicio)
| Necesidad app | Tabla(s) | Endpoint API |
|---|---|---|
| Noticia destacada / Lo último | `wp_posts`(post) + `wp_postmeta` + términos | `GET /wp/v2/posts?_embed` |
| Categorías (chips) | `wp_terms`/`wp_term_taxonomy` | `GET /wp/v2/categories` |
| Podcast del día | `wp_posts`(podcast) + meta | `GET /ssp/v1/episodes` (+ RSS para audio) |
| Directo (EN DIRECTO) | — (externo) | stream rcast.net (pendiente) |
| Programación radio | `wp_mp_timetable_data` | sin endpoint estándar (fase Radio) |
| Eventos | `wp_tec_events` | `GET /tribe/events/v1/events` |

## Incógnitas confirmadas / abiertas
1. **Idioma del contenido:** TranslatePress → la API da italiano. Traducir contenido en la app (ES/EN) requiere resolver TRP o asumir contenido en IT. **Decisión MVP:** UI en IT/ES; contenido en IT.
2. **Audio podcast:** `audio_file` en `wp_postmeta` vs feed RSS — confirmar al cablear.
3. **Stream directo:** URL de rcast.net + "sonando ahora" — investigar.
4. **Palinsesto radio:** `wp_mp_timetable_data` no está en API REST — export puntual o endpoint propio si se necesita.
