# Gegenprobe für check_sources.ps1: Baut absichtlich einen Schaden ein und
# prüft, ob der Test ihn erkennt. Danach wird die Datei wiederhergestellt.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$mainFile = Join-Path $root 'js\generator.js'
$orig = [System.IO.File]::ReadAllText($mainFile, [System.Text.Encoding]::UTF8)

# Den Block heraussuchen und entfernen (mit Index, nicht mit Regex)
$startMarker = '    const sideShift = rng.range(-0.35, 0.35) * radius;'
$endMarker = "return sortByAngle(corners, centroid2D(corners));`r`n}`r`n"

$startIdx = $orig.IndexOf($startMarker)
$endIdx = $orig.IndexOf($endMarker)

if ($startIdx -lt 0 -or $endIdx -lt 0) {
  Write-Host 'FEHLER: Marker nicht gefunden, Gegenprobe nicht möglich.'
  exit 1
}

# Block von startIdx bis Ende des endMarkers entfernen
$cutEnd = $endIdx + $endMarker.Length
$broken = $orig.Substring(0, $startIdx) + $orig.Substring($cutEnd)

Write-Host '=== Gegenprobe: Schaden wird eingebaut ==='
Write-Host ''
[System.IO.File]::WriteAllText($mainFile, $broken, (New-Object System.Text.UTF8Encoding($false)))

$result = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check_sources.ps1') 2>&1 | Out-String

# Wiederherstellen
[System.IO.File]::WriteAllText($mainFile, $orig, (New-Object System.Text.UTF8Encoding($false)))

$detected = $result -match 'FAIL|Problem'

Write-Host ($result -split "`r?`n" | Where-Object { $_ -match 'FAIL|ERGEBNIS' } | ForEach-Object { "  " + $_.Trim() } | Out-String).Trim()
Write-Host ''
Write-Host '=== Ergebnis der Gegenprobe ==='
if ($detected) {
  Write-Host '  [OK]   Der Test hat den eingebauten Schaden erkannt.'
} else {
  Write-Host '  [FAIL] Der Test hat den Schaden NICHT erkannt - Prüfung ist unzureichend!'
}

# Kontrolle: Datei ist wieder unverändert
$now = [System.IO.File]::ReadAllText($mainFile, [System.Text.Encoding]::UTF8)
if ($now -eq $orig) {
  Write-Host '  [OK]   Quelldatei wurde korrekt wiederhergestellt.'
} else {
  Write-Host '  [FAIL] Quelldatei ist verändert!'
}

if (-not $detected) { exit 1 }
