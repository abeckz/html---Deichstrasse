# Prueft die neue Geometrie: 8 Ecken, 2 Teilstuecke pro Seite, ausgelenkte
# Zwischenpunkte. Fragt: Wie viele Striche entstehen, und sind die Seiten
# wirklich keine geraden Linien mehr?

$ErrorActionPreference = 'Stop'

$cornerCount = 8
$cornerSegments = 2
$rings = 7
$perRing = $cornerCount * $cornerSegments

Write-Host '=== Neue Polygonform ==='
Write-Host ("Ecken pro Ring        : {0}" -f $cornerCount)
Write-Host ("Striche pro Ring      : {0}" -f $perRing)
Write-Host ("Ringe                 : {0}" -f $rings)
Write-Host ("Knoten gesamt         : {0}" -f ($perRing * $rings))

$seed = 20260917
$ribTotal = 0
for ($r = 0; $r -lt $rings - 1; $r++) {
  $built = 0
  for ($i = 0; $i -lt $perRing; $i++) {
    $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + $seed * 0.001)
    if ($gapNoise -gt 0.75) { continue }
    $built++
  }
  if ($built -eq 0) { $built = 1 }
  $ribTotal += $built
}
$ringEdges = $perRing * $rings
Write-Host ("Ringstriche           : {0}" -f $ringEdges)
Write-Host ("Rippen (mit Lücken)  : {0}" -f $ribTotal)
Write-Host ("Striche gesamt        : {0}" -f ($ringEdges + $ribTotal))
Write-Host ''

Write-Host '=== Sind die Seiten noch gerade? ==='
$radius = 1.5
$dent = 0.28
$shown = 0
for ($i = 0; $i -lt $cornerCount; $i++) {
  $angleA = ($i / $cornerCount) * 2 * [math]::PI
  $angleB = (($i + 1) / $cornerCount) * 2 * [math]::PI
  $aX = [math]::Cos($angleA) * $radius; $aZ = [math]::Sin($angleA) * $radius
  $bX = [math]::Cos($angleB) * $radius; $bZ = [math]::Sin($angleB) * $radius

  $f = 1 / $cornerSegments
  $midX = $aX + ($bX - $aX) * $f
  $midZ = $aZ + ($bZ - $aZ) * $f

  $dX = $bX - $aX; $dZ = $bZ - $aZ
  $len = [math]::Sqrt($dX * $dX + $dZ * $dZ)
  $nX = -$dZ / $len; $nZ = $dX / $len
  $amount = 0.5 * $dent

  $newX = $midX + $nX * $amount
  $newZ = $midZ + $nZ * $amount

  $dist = [math]::Abs($dX * ($aZ - $newZ) - ($aX - $newX) * $dZ) / $len

  if ($shown -lt 3) {
    Write-Host ("  Seite {0}: Abweichung von der Geraden = {1:N4}" -f $i, $dist)
    $shown++
  }
}
Write-Host '  (vorher war diese Abweichung exakt 0 - daher wirkten die Polygone so einfach)'
Write-Host ''
Write-Host ("Pro Ring liegen etwa {0} von {1} Strichen auf der Rückseite (16% Deckkraft)." -f `
    ([math]::Floor($perRing / 2)), $perRing)
Write-Host 'FERTIG'
