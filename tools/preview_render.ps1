# Rendert die Szene offline als SVG, damit man OHNE Browser pruefen kann, ob
# die Polygone klar erkennbar sind und die Ansicht schräg von oben kommt.
# Bildet Projektion, Tiefensortierung und Rückseiten-Daempfung nach.

$ErrorActionPreference = 'Stop'
$outPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'vorschau.svg'

# --- Kamera (muss zu renderer.js homeView passen) --------------------------
$yaw = -0.6
$pitch = 0.55
$distance = 9.5
$fov = 1.35
$offsetY = 40
$W = 900.0
$H = 700.0

function Rotate-Point($p, [double]$yaw, [double]$pitch) {
  $cy = [math]::Cos($yaw); $sy = [math]::Sin($yaw)
  $x1 = $p.x * $cy - $p.z * $sy
  $z1 = $p.x * $sy + $p.z * $cy
  $cx = [math]::Cos($pitch); $sx = [math]::Sin($pitch)
  $y1 = $p.y * $cx - $z1 * $sx
  $z2 = $p.y * $sx + $z1 * $cx
  return [pscustomobject]@{ x = $x1; y = $y1; z = $z2 }
}

function Project-Point($p) {
  $r = Rotate-Point $p $yaw $pitch
  $zc = $r.z + $distance
  $safe = [math]::Max($zc, 0.2)
  $k = ($fov * ([math]::Min($W, $H) / 2)) / $safe
  return [pscustomobject]@{ x = $W / 2 + $r.x * $k; y = $H / 2 - $r.y * $k + $offsetY; depth = $zc }
}

# --- Szene nachbilden (wie generator.js mit dent) --------------------------
$cornerCount = 11
$cornerSegments = 3
$rings = 7
$height = 5.0
$radius = 1.5
$dent = 0.34
$rngState = 20260917
function Next-Rand {
  $script:rngState = ($script:rngState + 0x6d2b79f5) -band 0xFFFFFFFF
  $t = $script:rngState -bxor ($script:rngState -shr 15)
  $t = [uint32](([uint64]$t * [uint64](1 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 7)
  $t = [uint32](([uint64]$t * [uint64](61 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 14)
  return ($t -band 0xFFFFFFFF) / 4294967296
}

# Feste Basisform mit leichter unregelmäßigkeit
$corners = @()
for ($i = 0; $i -lt $cornerCount; $i++) {
  $angle = ($i / $cornerCount) * 2 * [math]::PI + ((Next-Rand) - 0.5) * 0.24
  $rad = $radius * (1 + ((Next-Rand) * 2 - 1) * 0.18)
  $corners += [pscustomobject]@{ x = [math]::Cos($angle) * $rad; z = [math]::Sin($angle) * $rad }
}

# Ringe mit ausgelenkten Zwischenpunkten erzeugen
$ringPoints = @()
for ($lvl = 0; $lvl -lt $rings; $lvl++) {
  $t = $lvl / ($rings - 1)
  $y = $t * $height
  $twist = $t * 1.1
  $cs = [math]::Cos($twist); $sn = [math]::Sin($twist)
  $pts = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $A = $corners[$i]
    $B = $corners[($i + 1) % $cornerCount]

    $aX = $A.x * $cs - $A.z * $sn; $aZ = $A.x * $sn + $A.z * $cs
    $bX = $B.x * $cs - $B.z * $sn; $bZ = $B.x * $sn + $B.z * $cs

    $dX = $bX - $aX; $dZ = $bZ - $aZ
    $len = [math]::Sqrt($dX * $dX + $dZ * $dZ)
    $nX = -$dZ / $len; $nZ = $dX / $len

    for ($s = 0; $s -lt $cornerSegments; $s++) {
      $f = $s / $cornerSegments
      $bx = $aX + $dX * $f
      $bz = $aZ + $dZ * $f
      if ($s -gt 0) {
        # Auslenkung: hier mit festem Faktor, damit die Vorschau stabil ist
        $amount = (([math]::Sin(($i + $s) * 2.3 + $lvl * 1.7)) * 0.7) * $dent
        $bx += $nX * $amount
        $bz += $nZ * $amount
      }
      $pts += [pscustomobject]@{ x = $bx; y = $y; z = $bz }
    }
  }
  $ringPoints += , $pts
}

# Kanten sammeln: Ringstriche und Rippen
$edges = New-Object System.Collections.Generic.List[object]
for ($lvl = 0; $lvl -lt $rings; $lvl++) {
  $pts = $ringPoints[$lvl]
  for ($i = 0; $i -lt $pts.Count; $i++) {
    $edges.Add([pscustomobject]@{ p = $pts[$i]; q = $pts[($i + 1) % $pts.Count]; kind = 'ring' })
  }
}
$perRing = $ringPoints[0].Count
for ($r = 0; $r -lt $rings - 1; $r++) {
  for ($i = 0; $i -lt $perRing; $i++) {
    $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + 20260917 * 0.001)
    if ($gapNoise -gt 0.75) { continue }
    $edges.Add([pscustomobject]@{ p = $ringPoints[$r][$i]; q = $ringPoints[$r + 1][$i]; kind = 'rib' })
  }
}


# --- Projektion, Tiefensortierung, Rückseiten-Daempfung --------------------
$centerX = ($corners | Measure-Object -Property x -Average).Average
$centerZ = ($corners | Measure-Object -Property z -Average).Average

$projected = $edges | ForEach-Object {
  $pa = Project-Point $_.p
  $pb = Project-Point $_.q
  $midDepth = ($pa.depth + $pb.depth) / 2

  # Zentrum des Schlauches auf gleicher Höhe projizieren
  $levelY = $_.p.y
  $center = Project-Point ([pscustomobject]@{ x = $centerX; y = $levelY; z = $centerZ })

  [pscustomobject]@{
    x1 = $pa.x; y1 = $pa.y; x2 = $pb.x; y2 = $pb.y
    depth = $midDepth
    behind = ($center.depth -lt $midDepth)
    kind = $_.kind
  }
}

$svg = New-Object System.Text.StringBuilder
[void]$svg.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' width='$W' height='$H'>")
[void]$svg.AppendLine("<rect width='$W' height='$H' fill='#0b1020'/>")
[void]$svg.AppendLine("<text x='20' y='30' fill='#e8ecf8' font-family='sans-serif' font-size='16'>Vorschau: Startblick schräg von oben (yaw=$yaw, pitch=$pitch)</text>")

# Bodenraster zur Kontrolle der Ansicht
$g = -2.0
while ($g -le 2.0001) {
  $g1 = Project-Point ([pscustomobject]@{ x = $g; y = 0; z = -2.5 })
  $g2 = Project-Point ([pscustomobject]@{ x = $g; y = 0; z = 2.5 })
  $g3 = Project-Point ([pscustomobject]@{ x = -2.5; y = 0; z = $g })
  $g4 = Project-Point ([pscustomobject]@{ x = 2.5; y = 0; z = $g })
  [void]$svg.AppendLine("<line x1='$($g1.x)' y1='$($g1.y)' x2='$($g2.x)' y2='$($g2.y)' stroke='#2a3a63' stroke-width='1'/>")
  [void]$svg.AppendLine("<line x1='$($g3.x)' y1='$($g3.y)' x2='$($g4.x)' y2='$($g4.y)' stroke='#2a3a63' stroke-width='1'/>")
  $g += 0.5
}

$behindCount = 0
$frontCount = 0
foreach ($layer in @($true, $false)) {
  foreach ($p in ($projected | Where-Object { $_.behind -eq $layer } | Sort-Object depth -Descending)) {
    $color = if ($p.behind) { '#5a6a99' } else { '#8fb0ff' }
    $width = if ($p.kind -eq 'rib') { 1.4 } else { 2.2 }
    $opacity = if ($p.behind) { 0.16 } else { 1 }
    [void]$svg.AppendLine("<line x1='$($p.x1)' y1='$($p.y1)' x2='$($p.x2)' y2='$($p.y2)' stroke='$color' stroke-width='$width' stroke-opacity='$opacity'/>")
    if ($p.behind) { $behindCount++ } else { $frontCount++ }
  }
}

# Knotenpunkte klein (nur vorne)
foreach ($lvl in 0..($rings - 1)) {
  foreach ($pt in $ringPoints[$lvl]) {
    $sp = Project-Point $pt
    $cc = Project-Point ([pscustomobject]@{ x = $centerX; y = $pt.y; z = $centerZ })
    if ($cc.depth -lt $sp.depth) { continue }
    [void]$svg.AppendLine("<circle cx='$($sp.x)' cy='$($sp.y)' r='1.5' fill='#c8d6f5'/>")
  }
}

[void]$svg.AppendLine('</svg>')
# Mit BOM schreiben, damit der Browser die Umlaute in der SVG-Datei
# auch ohne charset-Angabe korrekt darstellt.
[System.IO.File]::WriteAllText($outPath, $svg.ToString(), (New-Object System.Text.UTF8Encoding($true)))

Write-Host ("Vorschau erzeugt: {0}" -f $outPath)
Write-Host ("Striche gesamt  : {0} (vorne {1}, hinten {2})" -f ($frontCount + $behindCount), $frontCount, $behindCount)
Write-Host ("Ringe           : {0}, Striche pro Ring: {1}" -f $rings, $perRing)

# Kontrolle der Ansicht: liegt der hintere Bodenpunkt weiter oben im Bild?
$fb = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = 1.5 })
$bb = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = -1.5 })
Write-Host ("Blick von oben  : {0} (hinterer Bodenpunkt y={1:N0}, vorderer y={2:N0})" -f ($bb.y -lt $fb.y), $bb.y, $fb.y)
