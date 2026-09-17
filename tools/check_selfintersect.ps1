# Kritische Pruefung der ausgelenkten Zwischenpunkte (dent):
# Bleibt die Reihenfolge der Punkte um das Zentrum erhalten? Wenn sich die
# Winkelreihenfolge umkehrt, überschneiden sich die Striche und der Ring
# wird unleserlich. Getestet über viele Seeds und Ringstufen.

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

$cornerCount = 8
$cornerSegments = 2
$rings = 7
$radius = 1.5
$jitter = 0.18
$height = 5.0
$dent = 0.28

Write-Host '=== Selbstüberschneidung der Ringe pruefen ==='
Write-Host ("Parameter: {0} Ecken, {1} Teilstuecke, dent={2}" -f $cornerCount, $cornerSegments, $dent)
Write-Host ''

$badSeeds = @()
$minGapGlobal = 999.0
$maxDentActual = 0.0

foreach ($seed in 1..25) {
  Set-Rng ([uint32]((([int64]$seed * 7919 + 13) % 4294967296)))
  $nA = Set-Noise 16
  $nB = Set-Noise 24

  $corners = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $angle = ($i / $cornerCount) * 2 * [math]::PI + ((Get-Rand) - 0.5) * 0.24
    $wob = 1 + (Get-Noise $nA ($i / $cornerCount)) * 0.35
    $rad = $radius * $wob * (1 + ((Get-Rand) * 2 - 1) * $jitter)
    $corners += [pscustomobject]@{ x = [math]::Cos($angle) * $rad; z = [math]::Sin($angle) * $rad }
  }

  $bad = $false
  $minGap = 999.0

  for ($lvl = 0; $lvl -lt $rings; $lvl++) {
    $t = $lvl / ($rings - 1)
    $twist = $t * 1.1
    $shrink = 1 - $t * 0.15
    $bumpAmp = 0.12
    $cs = [math]::Cos($twist); $sn = [math]::Sin($twist)

    # Ringpunkte mit Auslenkung erzeugen (wie buildRing in generator.js)
    $pts = @()
    for ($i = 0; $i -lt $cornerCount; $i++) {
      $A = $corners[$i]
      $B = $corners[($i + 1) % $cornerCount]

      # Ecken wie in buildRing verdrehen/verformen
      $prep = @()
      foreach ($pair in @(@($A, $i), @($B, ($i + 1)))) {
        $C = $pair[0]; $idx = $pair[1]
        $rx = $C.x * $cs - $C.z * $sn
        $rz = $C.x * $sn + $C.z * $cs
        $u = $idx / $cornerCount
        $bump = 1 + (Get-Noise $nA ($u + $t)) * $bumpAmp + (Get-Noise $nB ($u * 2 - $t)) * $bumpAmp * 0.5
        $r = $shrink * $bump
        $prep += [pscustomobject]@{ x = $rx * $r; z = $rz * $r }
      }
      $a2 = $prep[0]; $b2 = $prep[1]

      $dX = $b2.x - $a2.x; $dZ = $b2.z - $a2.z
      $len = [math]::Sqrt($dX * $dX + $dZ * $dZ)
      $nX = -$dZ / $len; $nZ = $dX / $len

      for ($s = 0; $s -lt $cornerSegments; $s++) {
        $f = $s / $cornerSegments
        $bx = $a2.x + $dX * $f
        $bz = $a2.z + $dZ * $f
        if ($s -gt 0) {
          $u = ($i + $s / $cornerSegments) / $cornerCount
          $amount = ((Get-Noise $nA ($u * 1.7 + $t * 1.3)) * 0.7 + (Get-Noise $nB ($u * 3.1 - $t * 0.9)) * 0.3) * $dent
          if ([math]::Abs($amount) -gt $script:maxDentActual) { $script:maxDentActual = [math]::Abs($amount) }
          $bx += $nX * $amount
          $bz += $nZ * $amount
        }
        $pts += [pscustomobject]@{ x = $bx; z = $bz }
      }
    }

    # Winkel aller Punkte um den Ursprung: muessen monoton laufen
    for ($i = 0; $i -lt $pts.Count; $i++) {
      $cur = $pts[$i]
      $nxt = $pts[($i + 1) % $pts.Count]
      $aCur = [math]::Atan2($cur.z, $cur.x)
      $aNxt = [math]::Atan2($nxt.z, $nxt.x)
      $d = $aNxt - $aCur
      # Normierung auf (-pi, pi]
      while ($d -gt [math]::PI) { $d -= 2 * [math]::PI }
      while ($d -le -[math]::PI) { $d += 2 * [math]::PI }

      if ($d -le 0) {
        # Winkel läuft rueckwaerts -> der Ring überschneidet sich
        $bad = $true
      }
      if ([math]::Abs($d) -lt $minGap) { $minGap = [math]::Abs($d) }
    }
  }

  if ($minGap -lt $minGapGlobal) { $minGapGlobal = $minGap }
  if ($bad) { $badSeeds += $seed }
}

Write-Host ("größte tatsaechliche Auslenkung : {0:N4}" -f $maxDentActual)
Write-Host ("Kleinster Winkelschritt im Ring   : {0:N4} rad (bei 8 Ecken x 2 = {1:N4} erwartet)" -f $minGapGlobal, (2 * [math]::PI / 16))
Write-Host ''
if ($badSeeds.Count -eq 0) {
  Write-Host 'ERGEBNIS: keine Selbstüberschneidung - die Ringe bleiben geschlossen und lesbar.'
} else {
  Write-Host ("ERGEBNIS: überschneidung bei Seeds: {0}" -f ($badSeeds -join ', '))
  Write-Host 'dent verkleinern!'
}
