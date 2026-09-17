# Zustandsmaschine von main.js nachbilden und alle Klickpfade durchspielen.
# Prueft insbesondere: Klick auf "Start" startet wirklich, "Pause" pausiert,
# nach dem Ende startet der Knopf einen neuen Durchlauf.

$ErrorActionPreference = 'Stop'

$script:phase = 'growing'
$script:running = $false
$script:label = 'Start'
$script:growLevel = 0
$script:rings = 7

function Reset-Search([bool]$autoStart) {
  $script:phase = 'growing'
  $script:running = $autoStart
  $script:growLevel = 0
  $script:label = if ($autoStart) { 'Pause' } else { 'Start' }
}

function Set-Running([bool]$value) {
  if ($script:phase -ne 'done') {
    $script:running = $value
    $script:label = if ($value) { 'Pause' } else { 'Weiter' }
    return
  }
  if ($value) { Reset-Search $true }
}

function Invoke-ToggleRunning {
  if ($script:phase -eq 'done') { Reset-Search $true; return }
  Set-Running (-not $script:running)
}

# Animation nachbilden: in jeder Runde waechst ein Ring, danach läuft die Suche.
function Step-Frame {
  if (-not $script:running) { return }
  if ($script:phase -eq 'growing') {
    $script:growLevel++
    if ($script:growLevel -ge $script:rings) { $script:phase = 'searching' }
    return
  }
  if ($script:phase -eq 'searching') {
    $script:phase = 'tracing'
    return
  }
  if ($script:phase -eq 'tracing') {
    $script:phase = 'done'
    $script:label = 'Erneut abspielen'
    $script:running = $false
  }
}

function Run-Frames([int]$n) { for ($i = 0; $i -lt $n; $i++) { Step-Frame } }

function Show-State([string]$was) {
  Write-Host ("{0,-34} phase={1,-10} running={2,-5} label={3}" -f $was, $script:phase, $script:running, $script:label)
}

$failures = 0
function Assert([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

Write-Host '=== Szenario A: Laden der Seite, dann Klick auf Start/Pause ==='
Reset-Search $true   # buildWorld() startet automatisch
Show-State 'nach dem Laden'
Assert ($script:running -eq $true) 'automatischer Start läuft'
Assert ($script:label -eq 'Pause') 'Knopf zeigt Pause'

Invoke-ToggleRunning # Klick 1
Show-State 'nach Klick 1'
Assert ($script:running -eq $false) 'Klick pausiert'
Assert ($script:label -eq 'Weiter') 'Knopf zeigt Weiter'

Invoke-ToggleRunning # Klick 2
Show-State 'nach Klick 2'
Assert ($script:running -eq $true) 'Klick setzt fort'
Assert ($script:label -eq 'Pause') 'Knopf zeigt Pause'

Write-Host ''
Write-Host '=== Szenario B: Durchlauf bis zum Ende, dann erneut starten ==='
Run-Frames 40
Show-State 'nach 40 Frames'
Assert ($script:phase -eq 'done') 'Ablauf ist beendet'
Assert ($script:running -eq $false) 'am Ende steht die Animation'
Assert ($script:label -eq 'Erneut abspielen') 'Knopf laedt zum Neustart ein'

Invoke-ToggleRunning # Klick auf "Erneut abspielen"
Show-State 'nach Neustart-Klick'
Assert ($script:running -eq $true) 'Neustart läuft wirklich los'
Assert ($script:phase -eq 'growing') 'beginnt wieder mit dem Aufbau'
Assert ($script:label -eq 'Pause') 'Knopf zeigt Pause'

Write-Host ''
Write-Host '=== Szenario C: "Neu suchen" mitten im Lauf ==='
Run-Frames 3
Reset-Search $true
Show-State 'nach Neu suchen'
Assert ($script:running -eq $true) 'Suche startet sofort'
Assert ($script:growLevel -eq 0) 'Schlauch wird neu aufgebaut'

Write-Host ''
Write-Host '=== Szenario D: Pause waehrend des Aufbaus, dann Start ==='
Reset-Search $true
Run-Frames 2
Invoke-ToggleRunning
Show-State 'pausiert beim Aufbau'
$levelBefore = $script:growLevel
Run-Frames 10
Assert ($script:growLevel -eq $levelBefore) 'in Pause waechst nichts weiter'
Invoke-ToggleRunning
Run-Frames 3
Show-State 'nach Fortsetzen'
Assert ($script:growLevel -gt $levelBefore) 'Aufbau läuft nach dem Klick weiter'

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: alle Klickpfade korrekt' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
