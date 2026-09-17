# Logiktest: bildet die Kernformeln von rng/generator/graph/dijkstra in
# PowerShell nach und prueft sie gegen Bellman-Ford und BFS.
# Zweck: unabhaengige Verifikation der JS-Logik, da hier kein Node/Python laeuft.

$ErrorActionPreference = 'Stop'

# --- RNG (Mulberry32) und 1D-Noise -----------------------------------------
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
  $values = @()
  for ($i = 0; $i -lt $points; $i++) { $values += (Get-Rand) * 2 - 1 }
  return , $values
}

function Get-Noise($values, $t) {
  $n = $values.Count
  $x = (($t % 1) + 1) % 1
  $f = $x * $n
  $i0 = [int]([math]::Floor($f)) % $n
  $i1 = ($i0 + 1) % $n
  $frac = $f - [math]::Floor($f)
  $smooth = (1 - [math]::Cos($frac * [math]::PI)) * 0.5
  return $values[$i0] * (1 - $smooth) + $values[$i1] * $smooth
}

# --- Szenenparameter wie in main.js / generator.js -------------------------
$cornerCount = 9
$cornerSegments = 3
$rings = 7
$height = 3.4
$radius = 1.5
$jitter = 0.18

# --- Szenengenerator (wie generator.js + graph.js) -------------------------
function Build-SeedWorld([int]$seed) {
  Set-Rng ([uint32]((([int64]$seed * 7919 + 13) % 4294967296)))
  $nA = Set-Noise 16
  $nB = Set-Noise 24

  # 1) unregelmaessiges Grundpolygon in der x-z-Ebene
  $corners = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $angle = ($i / $cornerCount) * 2 * [math]::PI + ((Get-Rand) - 0.5) * 0.24
    $wobble = 1 + (Get-Noise $nA ($i / $cornerCount)) * 0.35
    $rad = $radius * $wobble * (1 + ((Get-Rand) * 2 - 1) * $jitter)
    $corners += [pscustomobject]@{ x = [math]::Cos($angle) * $rad; z = [math]::Sin($angle) * $rad }
  }

  # Flaechenschwerpunkt des Grundpolygons
  $area = 0.0; $cx = 0.0; $cz = 0.0
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $j = ($i + $cornerCount - 1) % $cornerCount
    $cross = $corners[$j].x * $corners[$i].z - $corners[$i].x * $corners[$j].z
    $area += $cross
    $cx += ($corners[$j].x + $corners[$i].x) * $cross
    $cz += ($corners[$j].z + $corners[$i].z) * $cross
  }
  $area *= 0.5
  $center = [pscustomobject]@{ x = $cx / (6 * $area); z = $cz / (6 * $area) }

  $nodeIndex = @{}
  $nodeList = New-Object System.Collections.Generic.List[object]
  $edgeList = New-Object System.Collections.Generic.List[object]

  $getNodeId = {
    param($px, $py, $pz, $ringIdx)
    $k = '{0}|{1}|{2}' -f [int][math]::Round($px * 1000), [int][math]::Round($py * 1000), [int][math]::Round($pz * 1000)
    if (-not $nodeIndex.ContainsKey($k)) {
      $id = $nodeList.Count
      $nodeIndex[$k] = $id
      $nodeList.Add([pscustomobject]@{
        id = $id; x = $px; y = $py; z = $pz; ring = $ringIdx
        edges = (New-Object System.Collections.Generic.List[object])
      })
    }
    return $nodeIndex[$k]
  }

  $addEdge = {
    param($aId, $bId, $kind)
    if ($aId -eq $bId) { return $null }
    $n1 = $nodeList[$aId]; $n2 = $nodeList[$bId]
    $len = [math]::Sqrt(($n1.x - $n2.x) * ($n1.x - $n2.x) + ($n1.y - $n2.y) * ($n1.y - $n2.y) + ($n1.z - $n2.z) * ($n1.z - $n2.z))
    if ($len -lt 1e-6) { return $null }
    $e = [pscustomobject]@{ id = $edgeList.Count; a = $aId; b = $bId; length = $len; kind = $kind }
    $edgeList.Add($e)
    $nodeList[$aId].edges.Add($e)
    $nodeList[$bId].edges.Add($e)
    return $e
  }

$perRing = $cornerCount * $cornerSegments


  # 2) Ringe aufbauen (Schlauch): jede Stufe ist eine verformte, gedrehte Kopie
  $ringPoints = New-Object System.Collections.Generic.List[object]
  for ($lvl = 0; $lvl -lt $rings; $lvl++) {
    $t = $lvl / ($rings - 1)
    $y = $t * $height
    $twist = $t * 1.2
    $shrink = 1 - $t * 0.15
    $bumpAmp = 0.12
    $cs = [math]::Cos($twist); $sn = [math]::Sin($twist)
    $pts = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $cornerCount; $i++) {
      $idxA = $i
      $idxB = ($i + 1) % $cornerCount
      $cA = $corners[$idxA]; $cB = $corners[$idxB]
      $relAx = $cA.x - $center.x; $relAz = $cA.z - $center.z
      $relBx = $cB.x - $center.x; $relBz = $cB.z - $center.z
      $rxA = $relAx * $cs - $relAz * $sn; $rzA = $relAx * $sn + $relAz * $cs
      $rxB = $relBx * $cs - $relBz * $sn; $rzB = $relBx * $sn + $relBz * $cs
      $uA = $idxA / $cornerCount; $uB = $idxB / $cornerCount
      $bA = 1 + (Get-Noise $nA ($uA + $t)) * $bumpAmp + (Get-Noise $nB ($uA * 2 - $t)) * $bumpAmp * 0.5
      $bB = 1 + (Get-Noise $nA ($uB + $t)) * $bumpAmp + (Get-Noise $nB ($uB * 2 - $t)) * $bumpAmp * 0.5
      $rA = $shrink * $bA; $rB = $shrink * $bB
      $Px = $center.x + $rxA * $rA; $Pz = $center.z + $rzA * $rA
      $Qx = $center.x + $rxB * $rB; $Qz = $center.z + $rzB * $rB
      for ($s = 0; $s -lt $cornerSegments; $s++) {
        $f = $s / $cornerSegments
        $pts.Add([pscustomobject]@{ x = $Px + ($Qx - $Px) * $f; y = $y; z = $Pz + ($Qz - $Pz) * $f })
      }
    }
    $ringPoints.Add($pts)
  }

  # 3) Ringstriche als Kanten
  for ($lvl = 0; $lvl -lt $rings; $lvl++) {
    $pts = $ringPoints[$lvl]
    for ($i = 0; $i -lt $pts.Count; $i++) {
      $p = $pts[$i]; $q = $pts[($i + 1) % $pts.Count]
      $aId = & $getNodeId $p.x $p.y $p.z $lvl
      $bId = & $getNodeId $q.x $q.y $q.z $lvl
      & $addEdge $aId $bId 'ring' | Out-Null
    }
  }

  # 4) Rippen mit Luecken, aber mindestens eine pro Ringpaar
  for ($r = 0; $r -lt $rings - 1; $r++) {
    $built = 0
    for ($i = 0; $i -lt $perRing; $i++) {
      $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + $seed * 0.001)
      if ($gapNoise -gt 0.75) { continue }
      $p = $ringPoints[$r][$i]; $q = $ringPoints[$r + 1][$i]
      $aId = & $getNodeId $p.x $p.y $p.z $r
      $bId = & $getNodeId $q.x $q.y $q.z ($r + 1)
      if (& $addEdge $aId $bId 'rib') { $built++ }
    }
    if ($built -eq 0) {
      $i = [math]::Abs([int][math]::Round([math]::Sin($r * 3.1 + $seed) * $perRing)) % $perRing
      $p = $ringPoints[$r][$i]; $q = $ringPoints[$r + 1][$i]
      $aId = & $getNodeId $p.x $p.y $p.z $r
      $bId = & $getNodeId $q.x $q.y $q.z ($r + 1)
      & $addEdge $aId $bId 'rib' | Out-Null
    }
  }

  return [pscustomobject]@{
    corners = $corners; center = $center; area = $area
    nodes = $nodeList; edges = $edgeList; ringPoints = $ringPoints
  }
}


# --- Dijkstra (wie dijkstra.js) --------------------------------------------
function Invoke-Dijkstra($world, [int]$startId) {
  $dist = @{}; $prev = @{}; $done = @{}
  foreach ($n in $world.nodes) { $dist[$n.id] = [double]::PositiveInfinity; $done[$n.id] = $false }
  $dist[$startId] = 0.0
  $heap = New-Object System.Collections.Generic.List[object]
  $heap.Add([pscustomobject]@{ id = $startId; d = 0.0 })
  $settledCount = 0

  while ($heap.Count -gt 0) {
    $best = 0
    for ($i = 1; $i -lt $heap.Count; $i++) { if ($heap[$i].d -lt $heap[$best].d) { $best = $i } }
    $it = $heap[$best]; $heap.RemoveAt($best)
    if ($done[$it.id]) { continue }
    if ($it.d -gt $dist[$it.id]) { continue }
    $done[$it.id] = $true
    $settledCount++
    foreach ($e in $world.nodes[$it.id].edges) {
      $o = if ($e.a -eq $it.id) { $e.b } else { $e.a }
      if ($done[$o]) { continue }
      $cand = $dist[$it.id] + $e.length
      if ($cand -lt $dist[$o]) {
        $dist[$o] = $cand
        $prev[$o] = $it.id
        $heap.Add([pscustomobject]@{ id = $o; d = $cand })
      }
    }
  }
  return [pscustomobject]@{ dist = $dist; prev = $prev; settled = $settledCount }
}

function Invoke-BellmanFord($world, [int]$startId) {
  $bf = @{}
  foreach ($n in $world.nodes) { $bf[$n.id] = [double]::PositiveInfinity }
  $bf[$startId] = 0.0
  for ($iter = 0; $iter -lt $world.nodes.Count; $iter++) {
    $changed = $false
    foreach ($e in $world.edges) {
      if (-not [double]::IsPositiveInfinity($bf[$e.a]) -and $bf[$e.a] + $e.length -lt $bf[$e.b] - 1e-12) { $bf[$e.b] = $bf[$e.a] + $e.length; $changed = $true }
      if (-not [double]::IsPositiveInfinity($bf[$e.b]) -and $bf[$e.b] + $e.length -lt $bf[$e.a] - 1e-12) { $bf[$e.a] = $bf[$e.b] + $e.length; $changed = $true }
    }
    if (-not $changed) { break }
  }
  return $bf
}

function Trace-Path($world, $result, [int]$startId, [int]$targetId) {
  $ids = New-Object System.Collections.Generic.List[int]
  $cur = $targetId
  $guard = 0
  while ($cur -ne $startId -and $guard++ -lt ($world.nodes.Count + 2)) {
    $ids.Add($cur)
    if (-not $result.prev.ContainsKey($cur)) { return $null }
    $cur = $result.prev[$cur]
  }
  $ids.Add($startId)
  $arr = $ids.ToArray(); [array]::Reverse($arr)
  return $arr
}


# --- Test 1: Szene und Graph -------------------------------------------------
Write-Host '=== 1) Szene und Graph ==='
$world = Build-SeedWorld 20260917
$ringEdges = @($world.edges | Where-Object { $_.kind -eq 'ring' })
$ribEdges = @($world.edges | Where-Object { $_.kind -eq 'rib' })
$radii = $world.corners | ForEach-Object { [math]::Sqrt(($_.x - $world.center.x) * ($_.x - $world.center.x) + ($_.z - $world.center.z) * ($_.z - $world.center.z)) }
$rMin = ($radii | Measure-Object -Minimum).Minimum
$rMax = ($radii | Measure-Object -Maximum).Maximum
Write-Host ("Ecken: {0}, Flaeche: {1:N3}, Radien {2:N3} .. {3:N3}" -f $world.corners.Count, $world.area, $rMin, $rMax)
Write-Host ("Knoten: {0}, Striche: {1} (Ring {2}, Rippen {3})" -f $world.nodes.Count, $world.edges.Count, $ringEdges.Count, $ribEdges.Count)
Write-Host ("Grundpolygon unregelmaessig: {0}" -f (($rMax - $rMin) -gt 0.05))
Write-Host ("Ringe verbunden: {0}" -f ($ribEdges.Count -ge ($rings - 1)))

# --- Test 2: Dijkstra gegen Bellman-Ford ------------------------------------
Write-Host ''
Write-Host '=== 2) Dijkstra gegen Bellman-Ford ==='
$bottom = @($world.nodes | Where-Object { $_.ring -eq 0 })
$top = @($world.nodes | Where-Object { $_.ring -eq ($rings - 1) })
$start = ($bottom | Sort-Object z -Descending)[0]
$target = ($top | Sort-Object z)[0]
$dij = Invoke-Dijkstra $world $start.id
$bf = Invoke-BellmanFord $world $start.id

$mismatch = 0
foreach ($n in $world.nodes) {
  $x1 = $dij.dist[$n.id]; $x2 = $bf[$n.id]
  $inf1 = [double]::IsPositiveInfinity($x1); $inf2 = [double]::IsPositiveInfinity($x2)
  if ($inf1 -ne $inf2) { $mismatch++; continue }
  if (-not $inf1 -and [math]::Abs($x1 - $x2) -gt 1e-9) { $mismatch++ }
}
Write-Host ("Start #{0} (Hoehe {1:N2}), Ziel #{2} (Hoehe {3:N2})" -f $start.id, $start.y, $target.id, $target.y)
Write-Host ("abgearbeitete Knoten: {0} von {1}" -f $dij.settled, $world.nodes.Count)
Write-Host ("Abweichungen Dijkstra/Bellman-Ford: {0}" -f $mismatch)

# --- Test 3: Weg und Konsistenz ---------------------------------------------
Write-Host ''
Write-Host '=== 3) Weg nach oben ==='
$targetDist = $dij.dist[$target.id]
if ([double]::IsPositiveInfinity($targetDist)) {
  Write-Host 'FEHLER: Ziel nicht erreichbar'
} else {
  $path = Trace-Path $world $dij $start.id $target.id
  $sum = 0.0
  $heights = @()
  $kinds = @{ ring = 0; rib = 0 }
  $edgesOk = $true
  foreach ($nodeId in $path) { $heights += ($world.nodes | Where-Object { $_.id -eq $nodeId })[0].y }
  for ($i = 0; $i -lt $path.Count - 1; $i++) {
    $fromId = $path[$i]; $toId = $path[$i + 1]
    $ee = $null
    foreach ($cand in $world.nodes[$fromId].edges) {
      if (($cand.a -eq $fromId -and $cand.b -eq $toId) -or ($cand.b -eq $fromId -and $cand.a -eq $toId)) { $ee = $cand; break }
    }
    if ($null -eq $ee) { $edgesOk = $false; break }
    $sum += $ee.length
    $kinds[$ee.kind] = $kinds[$ee.kind] + 1
  }
  $straight = [math]::Sqrt(($start.x - $target.x) * ($start.x - $target.x) + ($start.y - $target.y) * ($start.y - $target.y) + ($start.z - $target.z) * ($start.z - $target.z))
  $mono = $true
  for ($i = 1; $i -lt $heights.Count; $i++) { if ($heights[$i] -lt $heights[$i - 1] - 1e-9) { $mono = $false } }

  Write-Host ("Weg: {0} Striche ({1} Ringstriche, {2} Rippen), Summe {3:N3}, Dijkstra {4:N3}" -f ($path.Count - 1), $kinds['ring'], $kinds['rib'], $sum, $targetDist)
  Write-Host ("Wegekanten existieren und Summe stimmt: {0}" -f ($edgesOk -and ([math]::Abs($sum - $targetDist) -lt 1e-9)))
  Write-Host ("Weg >= Luftlinie ({0:N3}): {1}" -f $straight, ($targetDist -ge $straight - 1e-9))
  Write-Host ("Hoehe {0:N2} -> {1:N2}, monoton steigend: {2}" -f $heights[0], $heights[$heights.Count - 1], $mono)
}

# --- Test 4: viele Seeds erreichbar -----------------------------------------
Write-Host ''
Write-Host '=== 4) Viele Seeds ==='
$ok = 0; $bad = @()
foreach ($s in 1..15) {
  $w = Build-SeedWorld $s
  $bot = @($w.nodes | Where-Object { $_.ring -eq 0 })
  $tpr = @($w.nodes | Where-Object { $_.ring -eq ($rings - 1) })
  $st = ($bot | Sort-Object z -Descending)[0]
  $tg = ($tpr | Sort-Object z)[0]
  $res = Invoke-Dijkstra $w $st.id
  if (-not [double]::IsPositiveInfinity($res.dist[$tg.id])) { $ok++ } else { $bad += $s }
}
Write-Host ("Seeds mit erreichbarem Ziel: {0} / 15" -f $ok)
if ($bad.Count -gt 0) { Write-Host ("nicht erreichbar bei Seed: {0}" -f ($bad -join ', ')) }

Write-Host ''
Write-Host 'FERTIG'
