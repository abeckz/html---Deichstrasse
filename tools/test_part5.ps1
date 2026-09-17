$ErrorActionPreference = 'Stop'
# Nur Teil 5 isoliert: Zufallsgraphen Dijkstra vs. Bellman-Ford
$script:rngState = 1
function Get-Rand {
  $script:rngState = ($script:rngState + 0x6d2b79f5) -band 0xFFFFFFFF
  $t = $script:rngState -bxor ($script:rngState -shr 15)
  $t = [uint32](([uint64]$t * [uint64](1 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 7)
  $t = [uint32](([uint64]$t * [uint64](61 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 14)
  return ($t -band 0xFFFFFFFF) / 4294967296
}

$script:rngState = 12345
$nCount = 8
$zNodes = @()
for ($i = 0; $i -lt $nCount; $i++) {
  $zNodes += , [pscustomobject]@{ id = $i; x = (Get-Rand) * 10; y = (Get-Rand) * 10; z = (Get-Rand) * 10 }
}
Write-Host ("Knoten gebaut: {0}" -f $zNodes.Count)

$zEdges = New-Object System.Collections.Generic.List[object]
$zAdj = @{}
for ($i = 0; $i -lt $nCount; $i++) { $zAdj[$i] = New-Object System.Collections.Generic.List[object] }

$tries = 0
while ($zEdges.Count -lt 20 -and $tries -lt 400) {
  $tries++
  $idxA = [int][math]::Floor((Get-Rand) * $nCount)
  $idxB = [int][math]::Floor((Get-Rand) * $nCount)
  if ($idxA -eq $idxB) { continue }
  $dup = $false
  foreach ($ex in $zEdges) { if (($ex.a -eq $idxA -and $ex.b -eq $idxB) -or ($ex.a -eq $idxB -and $ex.b -eq $idxA)) { $dup = $true; break } }
  if ($dup) { continue }
  $nodeA = $zNodes[$idxA]; $nodeB = $zNodes[$idxB]
  $L = [math]::Sqrt(($nodeA.x - $nodeB.x) * ($nodeA.x - $nodeB.x) + ($nodeA.y - $nodeB.y) * ($nodeA.y - $nodeB.y) + ($nodeA.z - $nodeB.z) * ($nodeA.z - $nodeB.z))
  if ($L -le 0) { continue }
  $e2 = [pscustomobject]@{ a = $idxA; b = $idxB; length = $L }
  $zEdges.Add($e2)
  $zAdj[$idxA].Add($e2)
  $zAdj[$idxB].Add($e2)
}
Write-Host ("Kanten: {0} (Versuche {1})" -f $zEdges.Count, $tries)

# Dijkstra
$src = 0
$d2 = @{}; $v2 = @{}; $p2 = @{}
for ($i = 0; $i -lt $nCount; $i++) { $d2[$i] = [double]::PositiveInfinity; $v2[$i] = $false }
$d2[$src] = 0.0
$q2 = New-Object System.Collections.Generic.List[object]
$q2.Add([pscustomobject]@{ id = $src; d = 0.0 })
while ($q2.Count -gt 0) {
  $best = 0
  for ($i = 1; $i -lt $q2.Count; $i++) { if ($q2[$i].d -lt $q2[$best].d) { $best = $i } }
  $it = $q2[$best]; $q2.RemoveAt($best)
  if ($v2[$it.id]) { continue }
  if ($it.d -gt $d2[$it.id]) { continue }
  $v2[$it.id] = $true
  foreach ($e in $zAdj[$it.id]) {
    $o = if ($e.a -eq $it.id) { $e.b } else { $e.a }
    if ($v2[$o]) { continue }
    $c = $d2[$it.id] + $e.length
    if ($c -lt $d2[$o]) { $d2[$o] = $c; $p2[$o] = $it.id; $q2.Add([pscustomobject]@{ id = $o; d = $c }) }
  }
}

# Bellman-Ford
$bf2 = @{}
for ($i = 0; $i -lt $nCount; $i++) { $bf2[$i] = [double]::PositiveInfinity }
$bf2[$src] = 0.0
for ($it3 = 0; $it3 -lt $nCount; $it3++) {
  $ch = $false
  foreach ($e in $zEdges) {
    if (-not [double]::IsPositiveInfinity($bf2[$e.a]) -and $bf2[$e.a] + $e.length -lt $bf2[$e.b] - 1e-12) { $bf2[$e.b] = $bf2[$e.a] + $e.length; $ch = $true }
    if (-not [double]::IsPositiveInfinity($bf2[$e.b]) -and $bf2[$e.b] + $e.length -lt $bf2[$e.a] - 1e-12) { $bf2[$e.a] = $bf2[$e.b] + $e.length; $ch = $true }
  }
  if (-not $ch) { break }
}
$mismatch = 0
for ($i = 0; $i -lt $nCount; $i++) {
  if ([double]::IsPositiveInfinity($d2[$i]) -and [double]::IsPositiveInfinity($bf2[$i])) { continue }
  if ([math]::Abs($d2[$i] - $bf2[$i]) -gt 1e-9) { $mismatch++ }
}
Write-Host ("Abweichungen Dijkstra/Bellman-Ford: {0}" -f $mismatch)

# Pfadverfolgung pruefen
$traceOk = $true
for ($i = 0; $i -lt $nCount; $i++) {
  if ([double]::IsPositiveInfinity($d2[$i])) { continue }
  $sum2 = 0.0
  $cur2 = $i
  $guard2 = 0
  while ($cur2 -ne $src -and $guard2++ -lt ($nCount * 2)) {
    $nxt = $p2[$cur2]
    if ($null -eq $nxt) { $traceOk = $false; break }
    $ee = $null
    foreach ($cand in $zAdj[$cur2]) { if (($cand.a -eq $cur2 -and $cand.b -eq $nxt) -or ($cand.b -eq $cur2 -and $cand.a -eq $nxt)) { $ee = $cand; break } }
    if ($null -eq $ee) { $traceOk = $false; break }
    $sum2 += $ee.length
    $cur2 = $nxt
  }
  if ([math]::Abs($sum2 - $d2[$i]) -gt 1e-9) { $traceOk = $false }
}
Write-Host ("Nachverfolgung konsistent: {0}" -f $traceOk)
Write-Host 'TEIL5 FERTIG'
