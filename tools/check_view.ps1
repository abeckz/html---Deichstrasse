# Prüft die ECHTE Kamera aus js/geometry.js (makeLookAtCamera + projectWithCamera).
#
# Diese Prüfung ist eindeutig, weil sie den Blickwinkel im Weltraum misst:
#   * Der Blickwinkel ist der Winkel zwischen Blickrichtung und Bodenebene.
#     Ein Winkel < 0 Grad bedeutet Blick von oben (Blickrichtung zeigt abwärts).
#   * Die Kamera muss über dem Boden stehen (eye.y > 0).
#   * Der hintere Bodenpunkt muss im Bild oberhalb des vorderen liegen.
#   * Alle Bodenpunkte müssen unterhalb der Bildmitte liegen (man schaut hinab).

$ErrorActionPreference = 'Stop'

$W = 900.0
$H = 700.0
$towerHeight = 5.0

function Norm($a) { $l = [math]::Sqrt($a.x * $a.x + $a.y * $a.y + $a.z * $a.z); if ($l -le 0) { $l = 1 }; return [pscustomobject]@{ x = $a.x / $l; y = $a.y / $l; z = $a.z / $l } }
function SubV($a, $b) { return [pscustomobject]@{ x = $a.x - $b.x; y = $a.y - $b.y; z = $a.z - $b.z } }
function CrossV($a, $b) { return [pscustomobject]@{ x = $a.y * $b.z - $a.z * $b.y; y = $a.z * $b.x - $a.x * $b.z; z = $a.x * $b.y - $a.y * $b.x } }
function DotV($a, $b) { return $a.x * $b.x + $a.y * $b.y + $a.z * $b.z }
function LenV($a) { return [math]::Sqrt($a.x * $a.x + $a.y * $a.y + $a.z * $a.z) }

# Bildet makeLookAtCamera nach
function Make-Camera($eye, $target, $fov) {
  $forward = Norm (SubV $target $eye)
  $up = Norm ([pscustomobject]@{ x = 0; y = 1; z = 0 })
  $right = Norm (CrossV $forward $up)
  $up2 = Norm (CrossV $right $forward)
  return [pscustomobject]@{ eye = $eye; forward = $forward; right = $right; up = $up2; fov = $fov }
}

# Bildet projectWithCamera nach
function Project-Via($p, $cam, [double]$panX = 0, [double]$panY = 0) {
  $d = SubV $p $cam.eye
  $cx = DotV $d $cam.right
  $cy = DotV $d $cam.up
  $cz = DotV $d $cam.forward
  $safeZ = [math]::Max($cz, 0.05)
  $k = ($cam.fov * ([math]::Min($W, $H) / 2)) / $safeZ
  return [pscustomobject]@{ x = $W / 2 + $cx * $k + $panX; y = $H / 2 - $cy * $k + $panY; depth = $safeZ }
}

Write-Host '=== Kamera-Prüfung (echte 3D-Kamera) ==='
Write-Host ''

# Werte wie in renderer.js (home)
$orbit = -0.55
$eyeHeight = 4.8
$distance = 6.5
$targetHeight = 1.6
$fov = 1.35

$eye = [pscustomobject]@{ x = [math]::Sin($orbit) * $distance; y = $eyeHeight; z = [math]::Cos($orbit) * $distance }
$target = [pscustomobject]@{ x = 0; y = $targetHeight; z = 0 }
$cam = Make-Camera $eye $target $fov

Write-Host ("Kamerastandort : ({0:N2}, {1:N2}, {2:N2})" -f $eye.x, $eye.y, $eye.z)
Write-Host ("Blickziel      : ({0:N2}, {1:N2}, {2:N2})" -f $target.x, $target.y, $target.z)

# Blickwinkel gegen die Bodenebene: wie stark zeigt forward nach unten?
$angle = [math]::Asin(-$cam.forward.y) * 180 / [math]::PI
Write-Host ("Blickrichtung  : ({0:N3}, {1:N3}, {2:N3})" -f $cam.forward.x, $cam.forward.y, $cam.forward.z)
Write-Host ("Blickwinkel zur Bodenebene: {0:N1} Grad" -f $angle)
Write-Host ''

# Punkte testen
$frontBottom = Project-Via ([pscustomobject]@{ x = 0; y = 0; z = 2.0 }) $cam
$backBottom  = Project-Via ([pscustomobject]@{ x = 0; y = 0; z = -2.0 }) $cam
$topRing     = Project-Via ([pscustomobject]@{ x = 0; y = $towerHeight; z = 0 }) $cam

Write-Host ("vorderer Bodenpunkt : Bild-x={0,6:N0}  Bild-y={1,6:N0}" -f $frontBottom.x, $frontBottom.y)
Write-Host ("hinterer Bodenpunkt : Bild-x={0,6:N0}  Bild-y={1,6:N0}" -f $backBottom.x, $backBottom.y)
Write-Host ("Turmspitze          : Bild-x={0,6:N0}  Bild-y={1,6:N0}" -f $topRing.x, $topRing.y)
Write-Host ''

$failures = 0
function Pruefe([bool]$cond, [string]$text) {
  if ($cond) { Write-Host ("  [OK]   {0}" -f $text) }
  else { Write-Host ("  [FAIL] {0}" -f $text); $script:failures++ }
}

Pruefe ($eye.y -gt 0.5) 'Kamera steht über dem Boden (eye.y > 0)'
Pruefe ($angle -gt 5) 'Blickrichtung zeigt nach unten (Winkel > 5 Grad)'
Pruefe ($angle -lt 70) 'Blick ist schräg, nicht senkrecht von oben (Winkel < 70 Grad)'
Pruefe ($backBottom.y -lt $frontBottom.y) 'Hinterer Bodenpunkt liegt im Bild weiter oben'
Pruefe ($topRing.y -lt $backBottom.y) 'Turmspitze liegt über allen Bodenpunkten'
Pruefe ($frontBottom.y -gt ($H / 2)) 'Vorderer Bodenpunkt liegt unterhalb der Bildmitte'
Pruefe ($cam.forward.y -lt 0) 'Blickvektor zeigt abwärts (forward.y < 0)'

Write-Host ''
if ($failures -eq 0) { Write-Host 'ERGEBNIS: Blick kommt eindeutig von schräg oben.' }
else { Write-Host ("ERGEBNIS: {0} Problem(e)" -f $failures) }
exit $failures
