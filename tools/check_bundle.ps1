# Prüft das erzeugte Bundle (dijkstra-schlauch.html) so weit wie ohne Browser
# möglich: Syntax, Ausführungsreihenfolge und dass main.js-Code am Ende steht.
#
# Hintergrund: Beim Bündeln werden die Module in einer festen Reihenfolge
# zusammengesetzt. Wird main.js zu früh eingefügt, greift es auf Funktionen zu,
# die noch nicht definiert sind.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundlePath = Join-Path $root 'dijkstra-schlauch.html'
$html = [System.IO.File]::ReadAllText($bundlePath, [System.Text.Encoding]::UTF8)

$failures = 0
function Pruefe([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

Write-Host '=== Bundle-Prüfung ==='
Write-Host ''

# Skriptblock herausziehen
$m = [regex]::Match($html, '(?s)<script>\r?\n(.*?)\r?\n</script>')
Pruefe ($m.Success) 'Es gibt genau einen Skriptblock'
if (-not $m.Success) { exit 1 }
$js = $m.Groups[1].Value

# Klammerbalance
$code = $js -replace '(?s)/\*.*?\*/', '' -replace '//[^\r\n]*', ''
foreach ($pair in @(@('{', '}'), @('(', ')'), @('[', ']'))) {
  $o = ([regex]::Matches($code, [regex]::Escape($pair[0]))).Count
  $c = ([regex]::Matches($code, [regex]::Escape($pair[1]))).Count
  Pruefe ($o -eq $c) ("Klammerbalance {0}{1}: {2} / {3}" -f $pair[0], $pair[1], $o, $c)
}

# Keine Modulreste
Pruefe (-not ($html -match 'type="module"')) 'Kein type="module" mehr (file:// tauglich)'
Pruefe (-not ($js -match '(?m)^\s*(import|export)\s')) 'Keine import/export-Anweisungen'

# Reihenfolge: Abhängigkeiten vor Verbrauchern
$posRng = $js.IndexOf('--------------------------- rng.js')
$posGeo = $js.IndexOf('--------------------------- geometry.js')
$posGen = $js.IndexOf('--------------------------- generator.js')
$posGra = $js.IndexOf('--------------------------- graph.js')
$posDij = $js.IndexOf('--------------------------- dijkstra.js')
$posRen = $js.IndexOf('--------------------------- renderer.js')
$posMai = $js.IndexOf('--------------------------- main.js')

Pruefe ($posRng -ge 0 -and $posRng -lt $posGeo) 'rng.js vor geometry.js'
Pruefe ($posGeo -lt $posGen) 'geometry.js vor generator.js'
Pruefe ($posGen -lt $posGra) 'generator.js vor graph.js'
Pruefe ($posGra -lt $posDij) 'graph.js vor dijkstra.js'
Pruefe ($posDij -lt $posRen) 'dijkstra.js vor renderer.js'
Pruefe ($posRen -lt $posMai) 'renderer.js vor main.js'
Pruefe ($posMai -gt 0) 'main.js ist enthalten'

# Kernfunktionen vorhanden
foreach ($name in 'makeRng', 'makeNoise1D', 'v3', 'centroid2D', 'sortByAngle', 'lerp3', 'makeLookAtCamera',
  'projectWithCamera', 'buildBasePolygon', 'buildRing', 'buildScene', 'buildGraph', 'pickEndpoints',
  'initDijkstra', 'dijkstraStep', 'shortestPath', 'class Renderer', 'buildWorld', 'setRunning',
  'toggleRunning', 'advanceGrowth', 'startTracing', 'loop') {
  Pruefe ($js -match [regex]::Escape($name)) ("Enthält " + $name)
}

# Start muss am Ende stehen
$tail = $js.Substring([math]::Max(0, $js.Length - 900))
Pruefe ($tail -match 'buildWorld\(') 'buildWorld wird am Ende aufgerufen'
Pruefe ($tail -match 'setRunning\(true\)') 'Animation wird am Ende gestartet'

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: Bundle ist vollständig und richtig aufgebaut.' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
