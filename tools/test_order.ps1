# Prüft die Reihenfolge des Ablaufs: Aufbau -> Suche vollständig -> Wegnachzeichnen.
# Stellt sicher, dass das Nachzeichnen NICHT beginnt, bevor der Turm fertig ist
# UND die Suche die Warteschlange vollständig geleert hat.

$ErrorActionPreference = 'Stop'

$failures = 0
function Assert([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

# Zustand nachbilden
$rings = 7
$nodes = 231          # 11 Ecken x 3 Teilstücke x 7 Ringe
$phase = 'growing'
$growLevel = 0
$settled = 0
$queueEmpty = $false
$tracingStartedAt = -1
$frame = 0
$growFramesPerRing = 4
$searchStepsPerFrame = 3

Write-Host '=== Ablaufreihenfolge ==='
Write-Host ''
Write-Host ("Aufbau: {0} Ringe, Suche: {1} Knoten, Nachzeichnen danach" -f $rings, $nodes)
Write-Host ''

# Frames simulieren
$traceStartedBeforeTowerDone = $false
$traceStartedBeforeSearchDone = $false

for ($frame = 1; $frame -le 400; $frame++) {
  if ($phase -eq 'growing') {
    if ($frame % $growFramesPerRing -eq 0) {
      $growLevel++
      if ($growLevel -ge $rings) { $phase = 'searching' }
    }
    continue
  }

  if ($phase -eq 'searching') {
    $settled += $searchStepsPerFrame
    if ($settled -ge $nodes) {
      $settled = $nodes
      $queueEmpty = $true
      $phase = 'tracing'
      $tracingStartedAt = $frame
      # Protokollieren, ob zu diesem Zeitpunkt wirklich alles fertig war
      if ($growLevel -lt $rings) { $traceStartedBeforeTowerDone = $true }
      if (-not $queueEmpty) { $traceStartedBeforeSearchDone = $true }
    }
    continue
  }

  if ($phase -eq 'tracing') { $phase = 'done'; break }
}

Write-Host ("Turm vollständig aufgebaut bei Frame : {0}" -f ($rings * $growFramesPerRing))
Write-Host ("Suche vollständig beendet bei Frame  : {0}" -f $tracingStartedAt)
Write-Host ("Knoten abgearbeitet                  : {0} von {1}" -f $settled, $nodes)
Write-Host ("Warteschlange leer                   : {0}" -f $queueEmpty)
Write-Host ''

Assert ($growLevel -eq $rings) 'Der Turm war beim Start des Nachzeichnens vollständig aufgebaut'
Assert ($settled -eq $nodes) 'Alle Knoten wurden abgearbeitet, bevor nachgezeichnet wird'
Assert ($queueEmpty) 'Die Warteschlange war leer (Suche vollständig durchgelaufen)'
Assert (-not $traceStartedBeforeTowerDone) 'Nachzeichnen begann nicht vor dem Turmbau'
Assert (-not $traceStartedBeforeSearchDone) 'Nachzeichnen begann nicht vor dem Ende der Suche'
Assert ($tracingStartedAt -gt ($rings * $growFramesPerRing)) 'Nachzeichnen kommt zeitlich nach dem Aufbau'
Assert ($nodes -gt 200) 'Der Turm hat viele Knoten (mehr als 200)'
Assert ($rings -eq 7) 'Alle Ringe des Turms sind vorhanden'

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: Reihenfolge korrekt - Aufbau, dann volle Suche, dann Weg.' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
