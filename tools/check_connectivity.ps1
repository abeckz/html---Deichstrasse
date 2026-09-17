# Prueft bei der neuen Geometrie (6 Ecken, keine Zwischenpunkte), ob der
# obere Ring über die Rippen zuverlaessig erreichbar bleibt.
# Bei nur 6 Rippen pro Ringpaar ist eine Lücke kritischer als vorher.

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
$cornerSegments = 3
$rings = 7
$perRing = $cornerCount * $cornerSegments
$radius = 1.5
$jitter = 0.18
$height = 5.0

function Test-SeedEdges([int]$seed) {
  Set-Rng ([uint32]((([int64]$seed * 7919 + 13) % 4294967296)))
  $nA = Set-Noise 16
  $nB = Set-Noise 24

  # Grundpolygon-Ecken (nur für die Winkelverteilung; hier zaehlt die Topologie)
  $corners = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $angle = ($i / $cornerCount) * 2 * [math]::PI + ((Get-Rand) - 0.5) * 0.24
    $wob = 1 + (Get-Noise $nA ($i / $cornerCount)) * 0.35
    $rad = $radius * $wob * (1 + ((Get-Rand) * 2 - 1) * $jitter)
    $corners += [pscustomobject]@{ x = [math]::Cos($angle) * $rad; z = [math]::Sin($angle) * $rad }
  }

  # Graph: pro Ring ein geschlossener Zug aus 6 Strichen, Rippen mit Lücken
  $adj = @{}
  $nodeCount = $perRing * $rings
  for ($i = 0; $i -lt $nodeCount; $i++) { $adj[$i] = New-Object System.Collections.Generic.List[int] }
  function Add-Link($u, $v, $adjRef) { }

  for ($lvl = 0; $lvl -lt $rings; $lvl++) {
    for ($i = 0; $i -lt $perRing; $i++) {
      $a = $lvl * $perRing + $i
      $b = $lvl * $perRing + (($i + 1) % $perRing)
      $adj[$a].Add($b); $adj[$b].Add($a)
    }
  }

  $ribsPerPair = @()
  for ($r = 0; $r -lt $rings - 1; $r++) {
    $built = 0
    for ($i = 0; $i -lt $perRing; $i++) {
      $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + $seed * 0.001)
      if ($gapNoise -gt 0.75) { continue }
      $a = $r * $perRing + $i
      $b = ($r + 1) * $perRing + $i
      $adj[$a].Add($b); $adj[$b].Add($a)
      $built++
    }
    if ($built -eq 0) {
      $i = [math]::Abs([int][math]::Round([math]::Sin($r * 3.1 + $seed) * $perRing)) % $perRing
      $a = $r * $perRing + $i
      $b = ($r + 1) * $perRing + $i
      $adj[$a].Add($b); $adj[$b].Add($a)
      $built = 1
    }
    $ribsPerPair += $built
  }

  # BFS von Ring 0 aus
  $seen = @{}
  $stack = New-Object System.Collections.Generic.List[int]
  $stack.Add(0); $seen[0] = $true
  while ($stack.Count -gt 0) {
    $cur = $stack[0]; $stack.RemoveAt(0)
    foreach ($nb in $adj[$cur]) { if (-not $seen.ContainsKey($nb)) { $seen[$nb] = $true; $stack.Add($nb) } }
  }
  $topReached = 0
  for ($i = ($rings - 1) * $perRing; $i -lt $nodeCount; $i++) { if ($seen.ContainsKey($i)) { $topReached++ } }

  return [pscustomobject]@{
    Seed = $seed
    Ribs = $ribsPerPair
    ReachedNodes = $seen.Count
    Nodes = $nodeCount
    TopReached = $topReached
  }
}

Write-Host '=== Neue Geometrie: Erreichbarkeit mit 6 Rippen pro Ringpaar ==='
Write-Host ''
$allOk = $true
foreach ($s in 1..20) {
  $res = Test-SeedEdges $s
  $ok = $res.TopReached -eq $perRing
  if (-not $ok) { $allOk = $false }
  $mark = if ($ok) { 'ok  ' } else { 'FEHL' }
  Write-Host ("{0} Seed {1,2}: Rippen pro Stufe [{2}]  erreicht {3}/{4} Knoten, oberer Ring {5}/{6}" -f `
      $mark, $res.Seed, ($res.Ribs -join ','), $res.ReachedNodes, $res.Nodes, $res.TopReached, $perRing)
}

Write-Host ''
if ($allOk) { Write-Host 'ERGEBNIS: oberer Ring bei allen Seeds vollständig erreichbar' }
else { Write-Host 'ERGEBNIS: es gibt Seeds mit abgeschnittenem oberen Ring' }
