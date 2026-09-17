# Baut aus index.html + styles.css + js/*.js eine einzige Datei,
# die per Doppelklick über file:// läuft (kein Server, kein CORS-Problem).
#
# Hintergrund: <script type="module"> mit import-Anweisungen wird von Chrome
# über file:// aus Sicherheitsgruenden blockiert. Diese Datei vereinigt alle
# Module in der richtigen Reihenfolge in einem klassischen <script>-Block und
# entfernt dabei die import/export-Anweisungen.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Reihenfolge der Module: zuerst die Abhaengigkeiten, dann die Verbraucher.
$moduleOrder = @('rng.js', 'geometry.js', 'generator.js', 'graph.js', 'dijkstra.js', 'renderer.js', 'main.js')

function Get-StrippedSource([string]$path) {
  # Explizit als UTF-8 lesen, sonst entstehen doppelt kodierte Umlaute
  # (aus "ö" würde "Ã¶"), die im Browser falsch angezeigt werden.
  $src = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

  # import-Zeilen entfernen (sie können sich über mehrere Zeilen strecken)
  $src = [regex]::Replace($src, "(?m)^\s*import\s*\{[^}]*\}\s*from\s*'[^']*';\s*$", '')
  # export-Schlüsselwort entfernen, die Namen bleiben im gemeinsamen Scope
  $src = [regex]::Replace($src, '(?m)^\s*export\s*\{[^}]*\};\s*$', '')
  $src = [regex]::Replace($src, '\bexport\s+(?=(class|function|const|let|var)\b)', '')

  return $src.Trim()
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('/* =======================================================================')
[void]$sb.AppendLine('   Dijkstra im Schlauch - automatisch erzeugte Einzeldatei')
[void]$sb.AppendLine('   Quelle: index.html, styles.css, js/*.js')
[void]$sb.AppendLine('   Erzeugt von tools/build_single_file.ps1 - nicht direkt bearbeiten!')
[void]$sb.AppendLine('   ======================================================================= */')

foreach ($m in $moduleOrder) {
  $path = Join-Path $root "js\$m"
  if (-not (Test-Path $path)) { throw "Modul fehlt: $path" }
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("/* ---------------------------- $m ---------------------------- */")
  [void]$sb.AppendLine((Get-StrippedSource $path))
}

$bundle = $sb.ToString()

# HTML-Grundgeruest einlesen und Script-Teil ersetzen.
# Wichtig: explizit als UTF-8 lesen, sonst gehen die Umlaute verloren.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$html = [System.IO.File]::ReadAllText((Join-Path $root 'index.html'), [System.Text.Encoding]::UTF8)
$css = [System.IO.File]::ReadAllText((Join-Path $root 'styles.css'), [System.Text.Encoding]::UTF8)
$html = $html -replace '<link rel="stylesheet" href="styles.css" />', "<style>`n$css`n</style>"
$html = $html -replace '<script type="module" src="js/main.js"></script>', "<script>`n$bundle`n</script>"
$html = $html -replace '<title>.*?</title>', '<title>Dijkstra im Schlauch (Einzeldatei)</title>'
# Zeichensatz sicherstellen, damit die Umlaute auch bei file:// stimmen.
$html = $html -replace '(<meta charset="utf-8" />)', '$1'

$outPath = Join-Path $root 'dijkstra-schlauch.html'
[System.IO.File]::WriteAllText($outPath, $html, $utf8)

Write-Host ("Erzeugt: {0}" -f $outPath)
Write-Host ("Größe: {0:N0} Bytes" -f (Get-Item $outPath).Length)

# Kontrolle: es darf kein import/export mehr übrig sein
$check = [System.IO.File]::ReadAllText($outPath, [System.Text.Encoding]::UTF8)
$leftover = ([regex]::Matches($check, '(?m)^\s*(import|export)\s')).Count
if ($leftover -gt 0) {
  Write-Host ("WARNUNG: {0} import/export-Reste gefunden" -f $leftover)
  exit 1
}
# Kontrolle: keine doppelt kodierten Umlaute (Ã¶ statt ö)
$mojibake = ([regex]::Matches($check, 'Ã[\x80-\xBF]')).Count
if ($mojibake -gt 0) {
  Write-Host ("WARNUNG: {0} falsch kodierte Umlaute gefunden" -f $mojibake)
  exit 1
}
Write-Host 'Kontrolle: keine import/export-Reste, Umlaute korrekt, Datei ist direkt öffenbar.'
