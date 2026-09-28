#!/usr/bin/env python3
"""Servidor de preview web de RadioApp.

Sirve los ficheros estáticos del build (debe ejecutarse desde build/web) y
ADEMÁS proxya el feed RSS de podcast en /feed/podcast con CORS. El feed
original (unicaradio.it/feed/podcast) NO manda cabeceras CORS, así que en la
preview web no se podía cargar; este proxy lo resuelve (mismo origen). En el
móvil real no hace falta (no hay CORS).

Uso (desde build/web):  python ../../tool/preview-server.py 8121
"""
import ssl
import sys
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, urlencode

# Python en Windows no usa el almacén de certificados del sistema.
# Para el servidor local de preview es seguro omitir la verificación SSL.
_SSL_CTX = ssl.create_default_context()
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE


# Opener que NO sigue redirects: un redirect de una URL permitida (unicaradio.it)
# hacia otro host saltaría la allowlist de /article-html (SSRF). En un 3xx se
# lanza HTTPError y _proxy_text sirve el cuerpo tal cual, sin ir al Location.
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=_SSL_CTX), _NoRedirect
)

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8121
FEED_URL = "https://www.unicaradio.it/feed/podcast"
SUBSCRIBE_URL = "https://www.unicaradio.it/?na=s"
RCAST_STATUS_URL = "https://status.rcast.net/66954"
RCAST_ARTWORK_URL = "https://artwork.rcast.net/66954"
REGIA_LAST_URL = "https://www.unicaradio.it/regia/lastsongs.html"
REGIA_NEXT_URL = "https://www.unicaradio.it/regia/nextsongs.html"
HOME_URL = "https://www.unicaradio.it/"


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path.startswith("/feed/podcast"):
            self._proxy_feed()
            return
        if self.path.startswith("/rcast-status"):
            self._proxy_text(RCAST_STATUS_URL)
            return
        if self.path.startswith("/rcast-artwork"):
            self._proxy_text(RCAST_ARTWORK_URL)
            return
        if self.path.startswith("/regia-last"):
            self._proxy_text(REGIA_LAST_URL + "?" + urlparse(self.path).query)
            return
        if self.path.startswith("/regia-next"):
            self._proxy_text(REGIA_NEXT_URL + "?" + urlparse(self.path).query)
            return
        if self.path.startswith("/home-html"):
            # HTML de la home (para sacar el banner). SIN cache-buster: el home
            # cacheado del CDN basta y no estresa el origen. Reutiliza el proxy.
            self._proxy_text(HOME_URL)
            return
        if self.path.startswith("/article-html"):
            # HTML de un post (para su banner above-post). Solo unicaradio.it
            # para evitar convertir esto en un proxy abierto (SSRF).
            target = (parse_qs(urlparse(self.path).query).get("url") or [""])[0]
            if target.startswith("https://www.unicaradio.it/"):
                self._proxy_text(target)
            else:
                self.send_error(400, "url no permitida")
            return
        super().do_GET()

    # Proxy de texto plano (status/artwork de rcast) con CORS, para la radio en web.
    def _proxy_text(self, url):
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 (preview)",
                    # Polylang redirige la home raiz al idioma detectado; forzamos
                    # italiano para que salga la home IT (con su banner).
                    "Accept-Language": "it-IT,it;q=0.9",
                },
            )
            try:
                with _OPENER.open(req, timeout=20) as r:
                    data = r.read()
            except urllib.error.HTTPError as he:
                # El home de Aruba devuelve 500 pero con el HTML completo dentro;
                # servimos el cuerpo igualmente para poder extraer el banner.
                data = he.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:  # noqa: BLE001
            self.send_error(502, f"rcast proxy error: {exc}")

    def _json(self, ok):
        payload = b'{"ok": true}' if ok else b'{"ok": false}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):  # noqa: N802
        if self.path.startswith("/subscribe"):
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)
            qs = parse_qs(body.decode("utf-8"))
            email = (qs.get("email") or [""])[0]
            lang = (qs.get("lang") or ["it"])[0]
            self._subscribe(email, lang)
            return
        self.send_error(405)

    def _subscribe(self, email, lang):
        if "@" not in email:
            self._json(False)
            return
        try:
            body = urlencode(
                {"ne": email, "ny": "1", "nr": "widget", "nlang": lang}
            ).encode()
            req = urllib.request.Request(
                SUBSCRIBE_URL,
                data=body,
                headers={
                    "User-Agent": "Mozilla/5.0 (preview)",
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            urllib.request.urlopen(req, timeout=25, context=_SSL_CTX)
            self._json(True)
        except Exception:  # noqa: BLE001
            self._json(False)

    def _proxy_feed(self):
        try:
            qs = urlparse(self.path).query
            url = FEED_URL + ("?" + qs if qs else "")
            req = urllib.request.Request(
                url, headers={"User-Agent": "Mozilla/5.0 (preview)"}
            )
            with urllib.request.urlopen(req, timeout=30, context=_SSL_CTX) as r:
                data = r.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as exc:  # noqa: BLE001
            self.send_error(502, f"feed proxy error: {exc}")


if __name__ == "__main__":
    print(f"Preview en http://localhost:{PORT}  (proxy /feed/podcast activo)")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
