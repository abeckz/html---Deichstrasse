# Sucht die Kombination aus cameraHeight und pitch, bei der die Kamera
# eindeutig schräg von oben auf die Grundfläche blickt.
#
# Physik: Steht die Kamera über der Szene (cameraHeight > 0), muss die
# Blickrichtung nach unten zeigen. In dieser Projektion entspricht das einem
# NEGATIVEN pitch, weil pitch die Szene kippt (nicht die Kamera).
# Diese Datei sucht den gültigen Bereich und begründet das Vorzeichen.

$ErrorActionPreference = 'Stop'

$W = 900.0
$H = 700.0
$towerHeight = 5.0
$distance = 9.0
$fov = 1.35
$offsetY = 30

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
  $k = ($fov * ([math]::Min($W, $H) / 2)) / $zc
  return [pscustomobject]@{ x = $W / 2 + $r.x * $k; y = $H / 2 - $r.y * $k + $offsetY; depth = $zc }
}

Write-Host '=== Systematische Suche: cameraHeight x pitch ==='
Write-Host ''
Write-Host 'Bewertet wird, ob der hintere Bodenpunkt im Bild weiter oben liegt als'
Write-Host 'der vordere (Boden als Fläche) UND ob die Kamera über dem Boden steht.'
Write-Host ''

$results = @()

foreach ($camH in @(0.0, 2.0, 3.4, 5.0, 7.0)) {
  foreach ($pi in @(-0.9, -0.7, -0.55, -0.4, -0.25, 0.0, 0.25, 0.4, 0.55, 0.7, 0.9)) {
    $view = [pscustomobject]@{ yaw = -0.6; pitch = $pi; cameraHeight = $camH; distance = $distance; fov = $fov; offsetY = $offsetY }

    $front = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = 2.0 }) $view
    $back  = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = -2.0 }) $view
    $top   = Project-Point ([pscustomobject]@{ x = 0; y = $towerHeight; z = 0 }) $view

    $bodenAlsFläche = ($back.y - $front.y) -lt 0          # hinterer Punkt oben im Bild
    $schautHinab     = ($front.y -gt ($H / 2)) -and ($back.y -gt ($H / 2))
    $turmOben        = $top.y -lt $front.y

    $ok = $bodenAlsFläche -and $schautHinab -and $turmOben

    $results += [pscustomobject]@{
      camH = $camH; pitch = $pi
      ok = $ok; Fläche = $bodenAlsFläche; hinab = $schautHinab; turm = $turmOben
      backY = $back.y; frontY = $front.y; topY = $top.y
    }
  }
}

Write-Host ("{0,6} {1,7}  {2,-8} {3,-9} {4,-8} {5,7} {6,7} {7,7}" -f 'camH', 'pitch', 'Ergebnis', 'Fläche', 'hinab', 'hint.y', 'vorn.y', 'Spitze')
foreach ($r in $results) {
  $mark = if ($r.ok) { 'OK' } else { '--' }
  Write-Host ("{0,6:N1} {1,7:N2}  {2,-8} {3,-9} {4,-8} {5,7:N0} {6,7:N0} {7,7:N0}" -f `
      $r.camH, $r.pitch, $mark, $r.Fläche, $r.hinab, $r.backY, $r.frontY, $r.topY)
}

Write-Host ''
$good = @($results | Where-Object { $_.ok })
if ($good.Count -gt 0) {
  Write-Host 'Gültige Kombinationen (Kamera über dem Boden):'
  foreach ($g in $good) { Write-Host ("   cameraHeight = {0:N1}, pitch = {1:N2}" -f $g.camH, $g.pitch) }
} else {
  Write-Host 'KEINE gültige Kombination gefunden - Kriterien überdenken.'
}
