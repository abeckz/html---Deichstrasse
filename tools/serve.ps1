# Winziger HTTP-Server nur mit Windows-Bordmitteln (kein Node, kein Python).
# Liefert die Projektdateien aus, damit <script type="module"> über http://
# geladen werden kann - damit verschwindet der CORS-Fehler bei file://.
#
# Aufruf:  powershell -ExecutionPolicy Bypass -File tools\serve.ps1
# Danach im Browser oeffnen:  http://localhost:8080/

param(
  [int]$Port = 8080,
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

$mime = @{
  '.html' = 'text/html; charset=utf-8'
  '.css'  = 'text/css; charset=utf-8'
  '.js'   = 'text/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'
  '.svg'  = 'image/svg+xml'
  '.png'  = 'image/png'
  '.ico'  = 'image/x-icon'
  '.md'   = 'text/plain; charset=utf-8'
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
} catch {
  Write-Host ("Port {0} ist belegt. Anderen Port waehlen, z. B.:" -f $Port)
  Write-Host ("  powershell -ExecutionPolicy Bypass -File tools\serve.ps1 -Port 8081")
  exit 1
}

$rootFull = (Resolve-Path $Root).Path
Write-Host ''
Write-Host '  Dijkstra im Schlauch - lokaler Server läuft'
Write-Host ("  Ordner : {0}" -f $rootFull)
Write-Host ("  Adresse: {0}" -f $prefix)
Write-Host ''
Write-Host '  Beenden mit Strg + C'
Write-Host ''

if (-not $NoOpen) { Start-Process $prefix | Out-Null }

while ($listener.IsListening) {
  $ctx = $null
  try { $ctx = $listener.GetContext() } catch { break }
  if ($null -eq $ctx) { break }

  $req = $ctx.Request
  $res = $ctx.Response
  $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }

  $full = Join-Path $rootFull $rel
  $status = 200

  # Pfad darf den Projektordner nicht verlassen
  $resolved = $null
  try { $resolved = (Resolve-Path -LiteralPath $full -ErrorAction Stop).Path } catch { }
  if ($null -eq $resolved -or -not $resolved.StartsWith($rootFull)) {
    $status = 404
    $body = [System.Text.Encoding]::UTF8.GetBytes('404 - nicht gefunden')
    $res.ContentType = 'text/plain; charset=utf-8'
  } else {
    $body = [System.IO.File]::ReadAllBytes($resolved)
    $ext = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
  }

  $res.StatusCode = $status
  $res.Headers['Cache-Control'] = 'no-store'
  $res.ContentLength64 = $body.Length
  try {
    $res.OutputStream.Write($body, 0, $body.Length)
  } catch { }
  $res.OutputStream.Close()

  Write-Host ("  {0}  {1}  {2}" -f $req.HttpMethod, $status, $rel)
}

$listener.Stop()
$listener.Close()
