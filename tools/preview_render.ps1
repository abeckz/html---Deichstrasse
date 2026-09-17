# Rendert die Szene offline als SVG mit der ECHTEN Kamera aus js/geometry.js.
# Damit lässt sich ohne Browser prüfen, ob der Blick von schräg oben kommt und
# ob die Polygone unregelmäßig geformt sind.

$ErrorActionPreference = 'Stop'
$outPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'vorschau.svg'

$W = 900.0
$H = 700.0

# --- Kamera: identisch zu renderer.js (home) --------------------------------
$orbit = -0.55
$eyeHeight = 4.8
$distance = 6.5
$targetHeight = 1.6
$fov = 1.35

function Norm($a) { $l = [math]::Sqrt($a.x * $a.x + $a.y * $a.y + $a.z * $a.z); if ($l -le 0) { $l = 1 }; return [pscustomobject]@{ x = $a.x / $l; y = $a.y / $l; z = $a.z / $l } }
function SubV($a, $b) { return [pscustomobject]@{ x = $a.x - $b.x; y = $a.y - $b.y; z = $a.z - $b.z } }
function CrossV($a, $b) { return [pscustomobject]@{ x = $a.y * $b.z - $a.z * $b.y; y = $a.z * $b.x - $a.x * $b.z; z = $a.x * $b.y - $a.y * $b.x } }
function DotV($a, $b) { return $a.x * $b.x + $a.y * $b.y + $a.z * $b.z }

$eye = [pscustomobject]@{ x = [math]::Sin($orbit) * $distance; y = $eyeHeight; z = [math]::Cos($orbit) * $distance }
$target = [pscustomobject]@{ x = 0; y = $targetHeight; z = 0 }
$forward = Norm (SubV $target $eye)
$right = Norm (CrossV $forward ([pscustomobject]@{ x = 0; y = 1; z = 0 }))
$up = Norm (CrossV $right $forward)

function Project-Point($p) {
  $d = SubV $p $eye
  $cx = DotV $d $right
  $cy = DotV $d $up
  $cz = DotV $d $forward
  $safeZ = [math]::Max($cz, 0.05)
  $k = ($fov * ([math]::Min($W, $H) / 2)) / $safeZ
  return [pscustomobject]@{ x = $W / 2 + $cx * $k; y = $H / 2 - $cy * $k; depth = $safeZ }
}

# --- Zufall und Rauschen ---------------------------------------------------
$script:rngState = 20260917
function Get-Rand {
  $script:rngState = ($script:rngState + 0x6d2b79f5) -band 0xFFFFFFFF
  $t = $script:rngState -bxor ($script:rngState -shr 15)
  $t = [uint32](([uint64]$t * [uint64](1 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 7)
  $t = [uint32](([uint64]$t * [uint64](61 -bor $t)) % 4294967296)
  $t = $t -bxor ($t -shr 14)
  return ($t -band 0xFFFFFFFF) / 4294967296
}
function Make-Noise([int]$points) {
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

$noiseA = Make-Noise 16
$noiseB = Make-Noise 24

$cornerCount = 12
$cornerSegments = 3
$rings = 7
$height = 5.0
$radius = 1.5
$dent = 0.38
$spikeChance = 0.35
$dentChance = 0.3
$perRing = $cornerCount * $cornerSegments


# --- Szene erzeugen (wie generator.js) -------------------------------------
$corners = @()
for ($i = 0; $i -lt $cornerCount; $i++) {
  $u = $i / $cornerCount
  $step = (2 * [math]::PI) / $cornerCount
  $angle = $i * $step + ((Get-Rand) * 2 - 1) * $step * 0.45
  $wobble = 1 + (Get-Noise $noiseA $u) * 0.6
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
$centerX = ($corners | Measure-Object -Property x -Average).Average
$centerZ = ($corners | Measure-Object -Property z -Average).Average

# Ringe
$ringPoints = New-Object System.Collections.Generic.List[object]
for ($lvl = 0; $lvl -lt $rings; $lvl++) {
  $t = $lvl / ($rings - 1)
  $y = $t * $height
  $twist = $t * 1.0
  $shrink = 1 - $t * 0.2
  $bumpAmp = 0.15
  $jagAmp = 0.09
  $warpAmp = 0.05
  $cs = [math]::Cos($twist); $sn = [math]::Sin($twist)

  $ec = @()
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $c = $corners[$i]
    $relx = $c.x - $centerX; $relz = $c.z - $centerZ
    $rx = $relx * $cs - $relz * $sn
    $rz = $relx * $sn + $relz * $cs
    $u = $i / $cornerCount
    $wave = (Get-Noise $noiseA ($u + $t * 1.3)) * $bumpAmp + (Get-Noise $noiseB ($u * 2 - $t)) * $bumpAmp * 0.5
    $jag = [math]::Sin(($i * 2.3 + $lvl * 2.7) * 2.1) * $jagAmp
    $r = $shrink * (1 + $wave + $jag)
    $ec += [pscustomobject]@{ x = $centerX + $rx * $r; y = $y; z = $centerZ + $rz * $r }
  }

  $pts = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $cornerCount; $i++) {
    $a = $ec[$i]; $b = $ec[($i + 1) % $cornerCount]
    $dx = $b.x - $a.x; $dz = $b.z - $a.z
    $l = [math]::Sqrt($dx * $dx + $dz * $dz)
    if ($l -le 0) { $l = 1 }
    $nx = -$dz / $l; $nz = $dx / $l

    for ($s = 0; $s -lt $cornerSegments; $s++) {
      $f = $s / $cornerSegments
      $bx = $a.x + $dx * $f
      $bz = $a.z + $dz * $f
      if ($s -gt 0) {
        $u = ($i + $s / $cornerSegments) / $cornerCount
        $soft = (Get-Noise $noiseA ($u * 2.3 + $t * 1.7)) * 0.8 + (Get-Noise $noiseB ($u * 4.1 - $t * 1.1)) * 0.4
        $hard = if ([math]::Sin(($i * 2.7 + $lvl * 1.9) * 3.1) -gt 0.35) { 0.9 } else { -0.55 }
        $amount = ($soft + $hard * 0.7) * $dent
        $bx += $nx * $amount
        $bz += $nz * $amount
      }
      $lift = [math]::Sin(($i + 1) * 1.7 + $lvl * 2.3) * $warpAmp
      $pts.Add([pscustomobject]@{ x = $bx; y = $y + $lift; z = $bz })
    }
  }
  $ringPoints.Add($pts)
}

# Kanten sammeln
$edges = New-Object System.Collections.Generic.List[object]
for ($lvl = 0; $lvl -lt $rings; $lvl++) {
  $pts = $ringPoints[$lvl]
  for ($i = 0; $i -lt $pts.Count; $i++) {
    $edges.Add([pscustomobject]@{ p = $pts[$i]; q = $pts[($i + 1) % $pts.Count]; kind = 'ring' })
  }
}
for ($r = 0; $r -lt $rings - 1; $r++) {
  for ($i = 0; $i -lt $perRing; $i++) {
    $gapNoise = [math]::Sin($i * 12.9898 + $r * 78.233 + 20260917 * 0.001)
    if ($gapNoise -gt 0.75) { continue }
    $edges.Add([pscustomobject]@{ p = $ringPoints[$r][$i]; q = $ringPoints[$r + 1][$i]; kind = 'rib' })
  }
}

# --- Zeichnen --------------------------------------------------------------
$proj = $edges | ForEach-Object {
  $pa = Project-Point $_.p
  $pb = Project-Point $_.q
  $midDepth = ($pa.depth + $pb.depth) / 2
  $axis = Project-Point ([pscustomobject]@{ x = $centerX; y = $_.p.y; z = $centerZ })
  [pscustomobject]@{
    x1 = $pa.x; y1 = $pa.y; x2 = $pb.x; y2 = $pb.y
    depth = $midDepth; behind = ($axis.depth -lt $midDepth); kind = $_.kind
  }
}

$svg = New-Object System.Text.StringBuilder
[void]$svg.AppendLine("<svg xmlns='http://www.w3.org/2000/svg' width='$W' height='$H'>")
[void]$svg.AppendLine("<rect width='$W' height='$H' fill='#0b1020'/>")
[void]$svg.AppendLine("<text x='20' y='30' fill='#e8ecf8' font-family='sans-serif' font-size='16'>Vorschau mit echter Kamera: Blick von schräg oben</text>")

# Bodenraster
$g = -3.0
while ($g -le 3.0001) {
  $ra = Project-Point ([pscustomobject]@{ x = $g; y = 0; z = -3.0 })
  $rb = Project-Point ([pscustomobject]@{ x = $g; y = 0; z = 3.0 })
  $rc = Project-Point ([pscustomobject]@{ x = -3.0; y = 0; z = $g })
  $rd = Project-Point ([pscustomobject]@{ x = 3.0; y = 0; z = $g })
  [void]$svg.AppendLine("<line x1='$($ra.x)' y1='$($ra.y)' x2='$($rb.x)' y2='$($rb.y)' stroke='#2a3a63' stroke-width='1'/>")
  [void]$svg.AppendLine("<line x1='$($rc.x)' y1='$($rc.y)' x2='$($rd.x)' y2='$($rd.y)' stroke='#2a3a63' stroke-width='1'/>")
  $g += 0.5
}

$behindN = 0; $frontN = 0
foreach ($layer in @($true, $false)) {
  foreach ($p in ($proj | Where-Object { $_.behind -eq $layer } | Sort-Object depth -Descending)) {
    $color = if ($p.behind) { '#5a6a99' } else { '#8fb0ff' }
    $wd = if ($p.kind -eq 'rib') { 1.5 } else { 2.4 }
    $op = if ($p.behind) { 0.16 } else { 1 }
    [void]$svg.AppendLine("<line x1='$($p.x1)' y1='$($p.y1)' x2='$($p.x2)' y2='$($p.y2)' stroke='$color' stroke-width='$wd' stroke-opacity='$op'/>")
    if ($p.behind) { $behindN++ } else { $frontN++ }
  }
}

[void]$svg.AppendLine('</svg>')
# Mit BOM schreiben, damit die Umlaute im Browser stimmen.
[System.IO.File]::WriteAllText($outPath, $svg.ToString(), (New-Object System.Text.UTF8Encoding($true)))

# --- Bericht ---------------------------------------------------------------
$angle = [math]::Asin(-$forward.y) * 180 / [math]::PI
$frontB = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = 2.0 })
$backB = Project-Point ([pscustomobject]@{ x = 0; y = 0; z = -2.0 })

Write-Host ("Vorschau erzeugt : {0}" -f $outPath)
Write-Host ("Kamera           : ({0:N2}, {1:N2}, {2:N2})" -f $eye.x, $eye.y, $eye.z)
Write-Host ("Blickwinkel      : {0:N1} Grad unter der Waagerechten" -f $angle)
Write-Host ("Striche gesamt   : {0} (vorne {1}, hinten {2})" -f ($frontN + $behindN), $frontN, $behindN)
Write-Host ("Ringe            : {0}, Striche pro Ring: {1}" -f $rings, $perRing)
Write-Host ("Blick von oben   : {0} (hinterer Bodenpunkt y={1:N0}, vorderer y={2:N0})" -f ($backB.y -lt $frontB.y), $backB.y, $frontB.y)

