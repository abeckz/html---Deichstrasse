# Prüft die Kamera physikalisch: Steht sie über der Szene und blickt sie
# tatsächlich auf die Grundfläche hinab?
#
# Kriterien für "Blick von schräg oben":
#  1. Die Kamera ist höher als die Grundfläche (cameraHeight > 0).
#  2. Im Bild erscheint der hintere Bodenpunkt weiter OBEN als der vordere
#     (kleineres Bild-y), der Boden liegt also als Fläche sichtbar vor uns.
#  3. Die Turmspitze liegt oberhalb des vorderen Bodenpunkts im Bild.
#  4. Beide Bodenpunkte liegen unterhalb der Bildmitte (man schaut hinab).

$ErrorActionPreference = 'Stop'

$W = 900.0
$H = 700.0
$towerHeight = 5.0

function Rotate-Point($p, [double]$yaw, [double]$pitch) {
  $cy = [math]::Cos($yaw); $sy = [math]::Sin($yaw)
  $x1 = $p.x * $cy - $p.z * $sy
  $z1 = $p.x * $sy + $p.z * $cy
  $cx = [math]::Cos($pitch); $sx = [math]::Sin($pitch)
  $y1 = $p.y * $cx - $z1 * $sx
  $z2 = $p.y * $sx + $z1 * $cx
  return [pscustomobject]@{ x = $x1; y = $y1; z = $z2 }
}

function Project-Point($p, $view) {
  $r = Rotate-Point ([pscustomobject]@{ x = $p.x; y = $p.y - $view.cameraHeight; z = $p.z }) $view.yaw $view.pitch
  $zc = [math]::Max($r.z + $view.distance, 0.2)
  $k = ($view.fov * ([math]::Min($W, $H) / 2)) / $zc
  return [pscustomobject]@{ x = $W / 2 + $r.x * $k; y = $H / 2 - $r.y * $k + $view.offsetY; depth = $zc }
}

function Test-Camera($view, [string]$name) {
  $frontBottom = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = 2.0 }) $view
  $backBottom  = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = -2.0 }) $view
  $topRing     = Project-Point ([pscustomobject]@{ x = 0; y = $towerHeight; z = 0 }) $view

  $k1 = $view.cameraHeight -gt 0.5
  $k2 = ($backBottom.y - $frontBottom.y) -lt 0
  $k3 = $topRing.y -lt $frontBottom.y
  $k4 = ($frontBottom.y -gt ($H / 2)) -and ($backBottom.y -gt ($H / 2))
  $all = $k1 -and $k2 -and $k3 -and $k4

  Write-Host ("{0}" -f $name)
  Write-Host ("   Kamerahöhe über Boden : {0,6:N2}   höher als Grundfläche: {1}" -f $view.cameraHeight, $k1)
  Write-Host ("   hinterer Bodenpunkt y : {0,6:N0}   vorderer y: {1,6:N0}   Boden als Fläche sichtbar: {2}" -f $backBottom.y, $frontBottom.y, $k2)
  Write-Host ("   Turmspitze y          : {0,6:N0}   oberhalb des vorderen Bodens: {1}" -f $topRing.y, $k3)
  Write-Host ("   beide Bodenpunkte unterhalb Bildmitte ({0:N0}): {1}" -f ($H / 2), $k4)
  Write-Host ("   ERGEBNIS: {0}" -f $(if ($all) { 'schräg von oben - korrekt' } else { 'NICHT von oben!' }))
  Write-Host ''
  return $all
}

Write-Host '=== Kameraprüfung (Canvas: y zeigt nach unten) ==='
Write-Host ''

$ok = $true

$new = [pscustomobject]@{ yaw = -0.6; pitch = 0.55; cameraHeight = 3.4; distance = 9.0; fov = 1.35; offsetY = 30 }
$ok = (Test-Camera $new 'NEU: Kamera auf Höhe 3.4, pitch 0.55') -and $ok

$under = [pscustomobject]@{ yaw = -0.6; pitch = 0.55; cameraHeight = -3.4; distance = 9.0; fov = 1.35; offsetY = 30 }
$null = Test-Camera $under 'GEGENPROBE: Kamera unter dem Boden (soll fehlschlagen)'

Write-Host '=== Zusammenfassung ==='
if ($ok) { Write-Host 'Der neue Startblick ist eindeutig schräg von oben.' }
else { Write-Host 'Der neue Startblick erfüllt die Kriterien NICHT.' }
