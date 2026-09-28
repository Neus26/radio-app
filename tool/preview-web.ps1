# Preview web: compila la app y la sirve en http://localhost:8121
# Uso (desde la raíz del repo):  ./tool/preview-web.ps1 [puerto]
# Alternativa para desarrollo:  flutter run -d chrome  (hot reload; pero el
#   podcast NO carga ahí por CORS — usa este script para verlo).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$port = if ($args.Count -ge 1) { $args[0] } else { "8121" }
Set-Location $root

# --pwa-strategy=none: sin service worker (evita la caché que deja la pantalla
# en blanco en la preview).
Write-Host "→ flutter build web --pwa-strategy=none ..." -ForegroundColor Cyan
flutter build web --pwa-strategy=none

$webDir = Join-Path $root "build/web"
$sw = Join-Path $webDir "flutter_service_worker.js"
if (Test-Path $sw) { Remove-Item $sw -Force }

Write-Host "→ Sirviendo en http://localhost:$port (con proxy /feed/podcast)" -ForegroundColor Green
Set-Location $webDir
python (Join-Path $root "tool/preview-server.py") $port
