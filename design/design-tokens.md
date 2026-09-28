# Design tokens — RadioApp app

Sistema visual validado por el cliente. Capturas en `design/screens/`, logo en `design/logo_*.svg`.

## Color
| Token | Valor | Uso |
|---|---|---|
| `brand` | `#bc0a26` | Rojo RadioApp (acción, acentos, activo) |
| `brandSoft` | `#ff5a72` | Rojo claro (kickers/acentos en tema oscuro) |
| `ink` | `#15171a` | Texto principal (claro) |
| `white` | `#ffffff` | — |
| **Oscuro** | | |
| `bgDark` | `#16181c` | Fondo app (con rejilla sutil) |
| `surfaceDark` | `#26282e` | Tarjetas/strips |
| `tabbarDark` | `#141619` | Barra inferior |
| `mutedDark` | `#8b8e95` | Texto secundario |
| `hairlineDark` | `#2a2d33` | Separadores |
| **Claro** | | |
| `bgLight` | `#fafbfc` | Fondo app (casi blanco + rejilla muy tenue) |
| `surfaceLight` | `#f6f3f4` | Tarjetas |
| `mutedLight` | `#9a9a9f` | Texto secundario |

## Tipografía
- **UI / cuerpo:** **Manrope** (400/500/700/800).
- **Display / títulos de sección:** **Bebas Neue** (condensada, mayúsculas).
- `tabular-nums` en horas/duraciones.
- Sin emojis → iconos de línea SVG.

## Fondo "rejilla de altavoz"
Patrón regular embossado (CSS en el diseño; en Flutter = `CustomPainter` o textura). Oscuro: puntos sutiles sobre `#16181c`. Claro: muy tenue sobre `#fafbfc`. **Es el fondo de la app**, no del lienzo.

## Forma / elevación
- Tarjetas radius **16–18**. Dispositivo/Sheets radius grande.
- Profundidad por glows del rojo de marca sobre oscuro (no sombras grises planas).

## Navegación
- **Barra inferior, 5 pestañas:** Inicio · Noticias · Podcast · Radio · Más.
- Activo en rojo de marca; iconos de línea (~24–26px).

## Logo
- SVG vectorizado oficial (`logo_h.svg` horizontal, `logo_v.svg` vertical). Play en negativo transparente que toma el color del fondo. **No recrear a mano.**
- Header con logo en pantallas principales (no en detalle).

## Pantallas (referencia en `design/screens/`)
1. **Inicio** — header(logo + EN DIRECTO) · noticia destacada · podcast del día · "Lo último".
2. **Noticias** — buscador · chips de categoría · destacada + filas.
3. **Podcast** — vista general + reproductor (mini-player → pantalla completa, logo en carátula grande).
4. **Radio** — "sonando ahora" + ecualizador + EN DIRECTO + historial → inmersivo.
5. **Más** — ajustes (tema, idioma, suscripciones, redes, contacto).
