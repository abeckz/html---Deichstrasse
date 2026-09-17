$ErrorActionPreference = 'Stop'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
  & "$PSScriptRoot\verify_logic.ps1"
} catch {
  Write-Host '--- FEHLERDETAILS ---'
  Write-Host ("Zeile: {0}" -f $_.InvocationInfo.ScriptLineNumber)
  Write-Host ("Text : {0}" -f $_.InvocationInfo.Line.Trim())
  Write-Host ("Info : {0}" -f $_.Exception.Message)
  if ($_.InvocationInfo.PositionMessage) { Write-Host $_.InvocationInfo.PositionMessage }
  exit 1
}
Write-Host ("Dauer: {0:N1} s" -f $sw.Elapsed.TotalSeconds)
