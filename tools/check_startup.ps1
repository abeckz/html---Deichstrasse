# Prüft den Startablauf statisch: Fehlt am Dateiende der Startbefehl, bleibt
# die Szene unsichtbar (alle Knoten starten mit visible = false).
# Genau dieser Fehler hat einmal die ganze Anzeige lahmgelegt.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $root 'js\main.js'
$src = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)

$failures = 0
function Pruefe([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

Write-Host '=== Startablauf ==='
Write-Host ''

$tail = $src.Substring([math]::Max(0, $src.Length - 700))

Pruefe ($src -match 'function setRunning') 'Funktion setRunning ist vorhanden'
Pruefe ($src -match 'function toggleRunning') 'Funktion toggleRunning ist vorhanden'
Pruefe ($tail -match 'buildWorld\(') 'buildWorld wird am Ende aufgerufen'
Pruefe ($tail -match 'requestAnimationFrame\(loop\)') 'Die Animationsschleife wird gestartet'
Pruefe ($tail -match 'setRunning\(true\)') 'Die Animation wird nach dem Laden gestartet'

Write-Host ''
Pruefe ($src -match "n\.visible = false") 'Knoten starten unsichtbar (Aufbauphase)'
Pruefe ($src -match 'advanceGrowth') 'Es gibt die Aufbauphase, die Knoten sichtbar macht'
Pruefe ($src -match "n\.ring < app\.growLevel") 'Die Aufbauphase setzt visible = true'

Write-Host ''
Write-Host '=== Prüfung der Modul-Exporte ==='
$geometry = [System.IO.File]::ReadAllText((Join-Path $root 'js\geometry.js'), [System.Text.Encoding]::UTF8)
$renderer = [System.IO.File]::ReadAllText((Join-Path $root 'js\renderer.js'), [System.Text.Encoding]::UTF8)

foreach ($name in 'makeLookAtCamera', 'projectWithCamera', 'v3', 'centroid2D', 'sortByAngle', 'lerp3', 'dist') {
  Pruefe ($geometry -match "export (function|const) $name") ("geometry.js exportiert " + $name)
}
Pruefe ($renderer -match "import \{ makeLookAtCamera, projectWithCamera \} from './geometry.js'") 'renderer.js importiert die Kamera-Funktionen'
Pruefe ($renderer -notmatch '\bproject\(') 'renderer.js nutzt nicht mehr die alte project-Funktion'
Pruefe ($renderer -match 'resetView\(\)') 'resetView ist vorhanden'
Pruefe ($renderer -match 'panBy\(') 'panBy ist vorhanden (Strg + Maus)'

Write-Host ''
Write-Host '=== Prüfung der HTML-Elemente ==='
$html = [System.IO.File]::ReadAllText((Join-Path $root 'index.html'), [System.Text.Encoding]::UTF8)
$ids = [regex]::Matches($html, 'id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
foreach ($need in 'scene', 'playPause', 'reset', 'resetView', 'regenerate', 'speed', 'density', 'seedInput', 'showDist', 'showHidden', 'showNodes', 'statNodes', 'statEdges', 'statSettled', 'statReached', 'statDist', 'statState', 'progress', 'tooltip', 'summary') {
  Pruefe ($ids -contains $need) ("index.html enthält #" + $need)
}

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: Startablauf und Verdrahtung sind vollständig.' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
