# Nachweis, dass die Polygone echte, unregelmäßige Vielecke sind und keine
# gleichmäßig geformten "Quader".
#
# Geprüft wird:
#  1. Streuung der Radien (Abstand Ecke -> Schwerpunkt)
#  2. Streuung der Seitenlängen (bei einem Quadrat wären alle gleich)
#  3. Streuung der Innenwinkel (bei einem regelmäßigen Vieleck alle gleich)
#  4. konkave Ecken: Innenwinkel > 180 Grad (Einbuchtungen)

$ErrorActionPreference = 'Stop'

$script:rngState = 1
function Set-Rng([uint32]$seed) { $script:rngState = $seed }
function Get-Rand {
  $script:rngState = ($script:rngState + 0x6d2b79f5) -band 0xFFFFFFFF
  $t = $script:rngState -bxor ($script:rngState -shr 15)
  $t = [uint32](([uint64]$t * [uint64](1 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 7)
  $t = [uint32](([uint64]$t * [uint64](61 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 14)
  return ($t -band 0xFFFFFFFF) / 4294967296
}
function Set-Noise([int]$points) {
  $v = @()
  for ($i = 0; $i -lt $points; $i++) { $v += (Get-Rand) * 2 - 1 }
  return , $v
}
function Get-Noise($values, $t) {
  $n = $values.Count
  $x = (($t % 1) + 1) % 1
  $f = $x * $n
  $i0 = [int]([math]::Floor($f)) % $n
  $i1 = ($i0 + 1) % $n
  $frac = $f - [math]::Floor($f)
  $sm = (1 - [math]::Cos($frac * [math]::PI)) * 0.5
  return $values[$i0] * (1 - $sm) + $values[$i1] * $sm
}

$cornerCount = 12
$radius = 1.5
$spikeChance = 0.35
$dentChance = 0.3

function Build-Polygon([int]$seed) {
  Set-Rng ([uint32]((([int64]$seed * 7919 + 13) % 4294967296)))
  $noise = Set-Noise 16
  $corners = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $u = $i / $cornerCount
    $step = (2 * [math]::PI) / $cornerCount
    $angle = $i * $step + ((Get-Rand) * 2 - 1) * $step * 0.45
    $wobble = 1 + (Get-Noise $noise $u) * 0.6
    $local = 1 + ((Get-Rand) * 2 - 1) * 0.4
    $spike = if ((Get-Rand) -lt $spikeChance) { 1.3 + (Get-Rand) * 0.65 } else { 1 }
    $dn = if ((Get-Rand) -lt $dentChance) { 0.45 + (Get-Rand) * 0.27 } else { 1 }
    $r = $radius * $wobble * $local * $spike * $dn
    $sideShift = ((Get-Rand) * 2 - 1) * 0.35 * $radius
    $corners += [pscustomobject]@{
      x = [math]::Cos($angle) * $r + $sideShift
      z = [math]::Sin($angle) * $r + ((Get-Rand) * 2 - 1) * 0.35 * $radius
    }
  }
  # nach Winkel um den Schwerpunkt sortieren
  $cx = ($corners | Measure-Object -Property x -Average).Average
  $cz = ($corners | Measure-Object -Property z -Average).Average
  return @($corners | Sort-Object { [math]::Atan2($_.z - $cz, $_.x - $cx) })
}

function Streuung($werte) {
  $m = ($werte | Measure-Object -Average).Average
  if ($m -eq 0) { return 0 }
  $min = ($werte | Measure-Object -Minimum).Minimum
  $max = ($werte | Measure-Object -Maximum).Maximum
  return [pscustomobject]@{ Min = $min; Max = $max; Mittel = $m; Spanne = ($max - $min) }
}

Write-Host '=== Sind die Polygone echte unregelmäßige Vielecke? ==='
Write-Host ("Ecken pro Polygon: {0}" -f $cornerCount)
Write-Host ''

$konkavGesamt = 0
$seeds = @(20260917, 1, 42, 7, 99)

foreach ($seed in $seeds) {
  $poly = Build-Polygon $seed
  $n = $poly.Count

  $cx = ($poly | Measure-Object -Property x -Average).Average
  $cz = ($poly | Measure-Object -Property z -Average).Average

  # 1. Radien
  $radii = @()
  foreach ($p in $poly) { $radii += [math]::Sqrt(($p.x - $cx) * ($p.x - $cx) + ($p.z - $cz) * ($p.z - $cz)) }
  $rS = Streuung $radii

  # 2. Seitenlängen
  $seiten = @()
  for ($i = 0; $i -lt $n; $i++) {
    $a = $poly[$i]; $b = $poly[($i + 1) % $n]
    $seiten += [math]::Sqrt(($a.x - $b.x) * ($a.x - $b.x) + ($a.z - $b.z) * ($a.z - $b.z))
  }
  $sS = Streuung $seiten

  # 3. Innenwinkel (in Grad), 4. konkave Ecken zählen
  $winkel = @()
  $konkav = 0
  for ($i = 0; $i -lt $n; $i++) {
    $prev = $poly[($i - 1 + $n) % $n]
    $cur = $poly[$i]
    $next = $poly[($i + 1) % $n]

    $v1x = $prev.x - $cur.x; $v1z = $prev.z - $cur.z
    $v2x = $next.x - $cur.x; $v2z = $next.z - $cur.z
    $l1 = [math]::Sqrt($v1x * $v1x + $v1z * $v1z)
    $l2 = [math]::Sqrt($v2x * $v2x + $v2z * $v2z)
    if ($l1 -le 0 -or $l2 -le 0) { continue }

    $cosA = ($v1x * $v2x + $v1z * $v2z) / ($l1 * $l2)
    $cosA = [math]::Max(-1, [math]::Min(1, $cosA))
    $ang = [math]::Acos($cosA) * 180 / [math]::PI

    # Umlaufsinn bestimmen: Kreuzprodukt aufeinanderfolgender Kanten
    $e1x = $cur.x - $prev.x; $e1z = $cur.z - $prev.z
    $e2x = $next.x - $cur.x; $e2z = $next.z - $cur.z
    $kreuz = $e1x * $e2z - $e1z * $e2x

    if ($kreuz -gt 0) { $innen = 180 - $ang } else { $innen = 180 + $ang }
    $winkel += $innen
    if ($innen -gt 180) { $konkav++ }
  }
  $wS = Streuung $winkel

  $konkavGesamt += $konkav

  Write-Host ("Seed {0}" -f $seed)
  Write-Host ("   Radien        : {0:N2} bis {1:N2}   Spanne {2:N2}   (bei einem Kreis 0)" -f $rS.Min, $rS.Max, $rS.Spanne)
  Write-Host ("   Seitenlängen  : {0:N2} bis {1:N2}   Spanne {2:N2}   (beim Quadrat 0)" -f $sS.Min, $sS.Max, $sS.Spanne)
  Write-Host ("   Innenwinkel   : {0:N0} bis {1:N0} Grad   Spanne {2:N0}   (beim regelmäßigen Vieleck 0)" -f $wS.Min, $wS.Max, $wS.Spanne)
  Write-Host ("   konkave Ecken : {0} von {1}   (Einbuchtungen, Innenwinkel > 180 Grad)" -f $konkav, $n)
  Write-Host ''
}

Write-Host '=== Zusammenfassung ==='
if ($konkavGesamt -gt 0) {
  Write-Host ("Die Polygone haben insgesamt {0} konkave Ecken - es sind echte unregelmäßige Vielecke." -f $konkavGesamt)
} else {
  Write-Host 'Keine konkaven Ecken gefunden.'
}
