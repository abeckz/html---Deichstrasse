# Prüft die neuen, deutlich unförmigeren Polygone:
#  - Wie viele Knoten und Striche entstehen?
#  - Wie viele echte Abzweigungen (Knoten mit mehr als 2 Kanten) gibt es?
#  - Wie stark weichen die Seiten von geraden Linien ab?
#  - Bleibt der Graph zusammenhängend?

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

# Werte wie in main.js / generator.js
$cornerCount = 11
$cornerSegments = 3
$rings = 7
$perRing = $cornerCount * $cornerSegments
$radius = 1.5
$jitter = 0.2
$dent = 0.34

Write-Host '=== Neue Polygonform ==='
Write-Host ("Ecken pro Ring        : {0}" -f $cornerCount)
Write-Host ("Striche pro Ring      : {0} ({1} Ecken x {2} Teilstücke)" -f $perRing, $cornerCount, $cornerSegments)
Write-Host ("Ringe                 : {0}" -f $rings)
Write-Host ("Knoten pro Ring       : {0}" -f $perRing)
Write-Host ("Knoten gesamt         : {0}" -f ($perRing * $rings))
Write-Host ''

foreach ($seed in @(20260917, 1, 42)) {
  Set-Rng ([uint32]((([int64]$seed * 7919 + 13) % 4294967296)))
  $nA = Set-Noise 16
  $nB = Set-Noise 24

  # Unförmiges Grundpolygon wie buildBasePolygon
  $corners = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $u = $i / $cornerCount
    $step = (2 * [math]::PI) / $cornerCount
    $angle = $i * $step + ((Get-Rand) * 2 - 1) * $step * 0.35
    $wobble = 1 + (Get-Noise $nA $u) * 0.55
    $local = 1 + ((Get-Rand) * 2 - 1) * $jitter * 2.2
    $spike = if ((Get-Rand) -lt 0.28) { 1.25 + (Get-Rand) * 0.45 } else { 1 }
    $dn = if ((Get-Rand) -lt 0.2) { 0.55 + (Get-Rand) * 0.23 } else { 1 }
    $r = $radius * $wobble * $local * $spike * $dn
    $corners += [pscustomobject]@{ x = [math]::Cos($angle) * $r; z = [math]::Sin($angle) * $r }
  }

  # Radien-Spannweite: wie unförmig ist das Grundpolygon?
  $radii = $corners | ForEach-Object { [math]::Sqrt($_.x * $_.x + $_.z * $_.z) }
  $rMin = ($radii | Measure-Object -Minimum).Minimum
  $rMax = ($radii | Measure-Object -Maximum).Maximum

  # Knotengrad bestimmen: echte Abzweigungen sind Knoten mit > 2 Kanten
  $nodeCount = $perRing * $rings
  $degree = @{}
  for ($i = 0; $i -lt $nodeCount; $i++) { $degree[$i] = 0 }

  # Ringstriche
  for ($lvl = 0; $lvl -lt $rings; $lvl++) {
    for ($i = 0; $i -lt $perRing; $i++) {
      $a = $lvl * $perRing + $i
      $b = $lvl * $perRing + (($i + 1) % $perRing)
      $degree[$a]++; $degree[$b]++
    }
  }
  # Rippen mit Lücken
  $ribCount = 0
  for ($r = 0; $r -lt $rings - 1; $r++) {
    $built = 0
    for ($i = 0; $i -lt $perRing; $i++) {
      $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + $seed * 0.001)
      if ($gapNoise -gt 0.75) { continue }
      $a = $r * $perRing + $i
      $b = ($r + 1) * $perRing + $i
      $degree[$a]++; $degree[$b]++
      $built++
    }
    if ($built -eq 0) {
      $i = [math]::Abs([int][math]::Round([math]::Sin($r * 3.1 + $seed) * $perRing)) % $perRing
      $degree[$r * $perRing + $i]++; $degree[($r + 1) * $perRing + $i]++
      $built = 1
    }
    $ribCount += $built
  }

  $branches = @($degree.Values | Where-Object { $_ -gt 2 }).Count
  $ringEdges = $perRing * $rings
  $totalEdges = $ringEdges + $ribCount

  Write-Host ("Seed {0}" -f $seed)
  Write-Host ("   Grundpolygon-Radien    : {0:N3} bis {1:N3}  (Spannweite {2:N3})" -f $rMin, $rMax, ($rMax - $rMin))
  Write-Host ("   Ringstriche            : {0}" -f $ringEdges)
  Write-Host ("   Rippen (mit Lücken)    : {0}" -f $ribCount)
  Write-Host ("   Striche gesamt         : {0}" -f $totalEdges)
  Write-Host ("   Knoten mit Abzweigung  : {0} von {1} (Grad > 2)" -f $branches, $nodeCount)
  Write-Host ("   Knoten mit Grad 4      : {0}" -f @($degree.Values | Where-Object { $_ -ge 4 }).Count)
  Write-Host ''
}

# Abweichung der Seiten von der Geraden nachrechnen
Write-Host '=== Sind die Seiten wirklich gebrochen? ==='
$radiusT = 1.5
$maxDev = 0.0
for ($i = 0; $i -lt $cornerCount; $i++) {
  $angleA = ($i / $cornerCount) * 2 * [math]::PI
  $angleB = (($i + 1) / $cornerCount) * 2 * [math]::PI
  $aX = [math]::Cos($angleA) * $radiusT; $aZ = [math]::Sin($angleA) * $radiusT
  $bX = [math]::Cos($angleB) * $radiusT; $bZ = [math]::Sin($angleB) * $radiusT
  $dX = $bX - $aX; $dZ = $bZ - $aZ
  $len = [math]::Sqrt($dX * $dX + $dZ * $dZ)

  # beide Zwischenpunkte (s = 1/3 und s = 2/3)
  foreach ($s in @(1, 2)) {
    $f = $s / $cornerSegments
    $mx = $aX + $dX * $f
    $mz = $aZ + $dZ * $f
    $nX = -$dZ / $len; $nZ = $dX / $len
    $amount = 0.8 * $dent   # mittlerer Betrag
    $newX = $mx + $nX * $amount
    $newZ = $mz + $nZ * $amount
    $dev = [math]::Abs($dX * ($aZ - $newZ) - ($aX - $newX) * $dZ) / $len
    if ($dev -gt $maxDev) { $maxDev = $dev }
  }
}
Write-Host ("Größte Abweichung eines Zwischenpunkts von der Geraden: {0:N3}" -f $maxDev)
Write-Host ("Bei einem einfachen Vieleck wäre dieser Wert exakt 0.")
