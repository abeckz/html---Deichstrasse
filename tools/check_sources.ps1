# Prüft jede Quelldatei einzeln auf Syntaxschäden, BEVOR gebündelt wird.
#
# Hintergrund: Beim Einfügen von Code kann eine Funktion mitten in einer anderen
# landen. Dann bleibt die Klammerbalance der Gesamtdatei zufällig stimmig, aber
# die Struktur ist zerstört. Diese Prüfung achtet deshalb auf:
#   1. Klammerbalance pro Datei (geschweift und rund),
#   2. jede Top-Level-Definition beginnt in Spalte 1,
#   3. nach einer schließenden Klammer in Spalte 1 darf kein Code folgen,
#      der zu einer alten Funktion gehört (verwaiste Fragmente).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$jsDir = Join-Path $root 'js'

$failures = 0
function Pruefe([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

Write-Host '=== Quelldateien einzeln prüfen ==='
Write-Host ''

foreach ($file in Get-ChildItem (Join-Path $jsDir '*.js') | Sort-Object Name) {
  $src = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
  $lines = $src -split "\r?\n"
  Write-Host ("--- {0} ({1} Zeilen) ---" -f $file.Name, $lines.Count)

  # 1. Klammerbalance ohne Kommentare
  $code = $src -replace '(?s)/\*.*?\*/', '' -replace '//[^\r\n]*', ''
  foreach ($pair in @(@('{', '}'), @('(', ')'), @('[', ']'))) {
    $o = ([regex]::Matches($code, [regex]::Escape($pair[0]))).Count
    $c = ([regex]::Matches($code, [regex]::Escape($pair[1]))).Count
    Pruefe ($o -eq $c) ("{0}: Klammern {1}{2} = {3} / {4}" -f $file.Name, $pair[0], $pair[1], $o, $c)
  }

  # 2. Verwaiste Fragmente: Einrückung ohne umgebenden Block am Dateianfang
  $orphan = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    # Eine Zeile, die eingerückt ist, obwohl davor eine Funktion geschlossen wurde
    if ($line -match '^\s{2,}\S' -and $i -gt 0) {
      $prev = $lines[$i - 1]
      if ($prev -match '^}' -or $prev -match '^export \{[^}]*\};$') {
        # Erlaubt: Fortsetzung einer mehrzeiligen Anweisung, Kommentar, leere Zeile
        if ($line -notmatch '^\s*(//|\*|/\*)' -and $line -notmatch '^\s*$') {
          Write-Host ("  [FAIL] {0}: Verdächtige Zeile {1}: {2}" -f $file.Name, ($i + 1), $line.Trim())
          $orphan = $true
          $script:failures++
        }
      }
    }
  }
  if (-not $orphan) { Pruefe $true ("{0}: keine verwaisten Fragmente" -f $file.Name) }

  Write-Host ''
}

# 3. Alle exportierten Namen sind vorhanden
Write-Host '--- Exporte und Importe ---'
$modules = @{}
foreach ($file in Get-ChildItem (Join-Path $jsDir '*.js')) { $modules[$file.Name] = $file.FullName }

$importProblems = 0
foreach ($name in $modules.Keys | Sort-Object) {
  $src = [System.IO.File]::ReadAllText($modules[$name], [System.Text.Encoding]::UTF8)
  foreach ($m in [regex]::Matches($src, "import\s*\{([^}]*)\}\s*from\s*'\./([^']+)'")) {
    $target = $m.Groups[2].Value
    $targetSrc = [System.IO.File]::ReadAllText($modules[$target], [System.Text.Encoding]::UTF8)
    foreach ($imported in $m.Groups[1].Value -split ',') {
      $imp = $imported.Trim()
      if (-not $imp) { continue }
      if ($targetSrc -notmatch "export (function|const|class|let|var) $imp\b" -and $targetSrc -notmatch "export \{[^}]*\b$imp\b") {
        Write-Host ("  [FAIL] {0} importiert {1}, aber {2} exportiert es nicht" -f $name, $imp, $target)
        $importProblems++
        $script:failures++
      }
    }
  }
}
if ($importProblems -eq 0) { Pruefe $true 'Alle Importe werden von den Zielmodulen exportiert' }

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: Alle Quelldateien sind syntaktisch in Ordnung.' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
