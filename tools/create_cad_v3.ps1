<#
.SYNOPSIS
  用 AutoCAD ActiveX 生成 v3 零件三视图草案（单位 mm）。
.NOTES
  Windows PowerShell 5.1: powershell.exe -NoProfile -File tools\create_cad_v3.ps1
  在新目录中生成文件；目标目录已存在时拒绝覆盖。图纸不是加工图。
#>
param(
    [string]$OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\图纸_v3_草案')
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputDir) { throw "输出目录已存在，拒绝覆盖：$OutputDir" }
$null = New-Item -ItemType Directory -Path $OutputDir
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

try { $app = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25') }
catch { $app = New-Object -ComObject 'AutoCAD.Application.25' }
Write-Host ('连接到 ' + $app.Name + ' ' + $app.Version)
$template = Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
if (-not (Test-Path -LiteralPath $template)) { throw "未找到 AutoCAD 公制模板：$template" }

function Add-Line([double]$x1, [double]$y1, [double]$x2, [double]$y2, [string]$layer = 'OUTLINE') {
    $p1 = [double[]]@($x1, $y1, 0); $p2 = [double[]]@($x2, $y2, 0)
    $entity = $script:space.AddLine($p1, $p2)
    $entity.Layer = $layer
}

function Add-Rect([double]$x, [double]$y, [double]$w, [double]$h, [string]$layer = 'OUTLINE') {
    Add-Line $x $y ($x + $w) $y $layer
    Add-Line ($x + $w) $y ($x + $w) ($y + $h) $layer
    Add-Line ($x + $w) ($y + $h) $x ($y + $h) $layer
    Add-Line $x ($y + $h) $x $y $layer
}

function Add-Text([string]$value, [double]$x, [double]$y, [double]$height, [string]$layer = 'NOTES') {
    $point = [double[]]@($x, $y, 0)
    $entity = $script:space.AddText($value, $point, $height)
    $entity.StyleName = 'CN_NOTES'
    $entity.Layer = $layer
}

function Add-Circle([double]$x, [double]$y, [double]$radius, [string]$layer = 'REFERENCE') {
    $point = [double[]]@($x, $y, 0)
    $entity = $script:space.AddCircle($point, $radius)
    $entity.Layer = $layer
}

function Add-Arc([double]$x, [double]$y, [double]$radius, [double]$start, [double]$end) {
    # AddArc 从起点逆时针到终点；把负角度正规化，保留跨 0° 的弧。
    $a = (($start % 360) + 360) % 360 * [Math]::PI / 180
    $b = (($end % 360) + 360) % 360 * [Math]::PI / 180
    $center = [double[]]@($x, $y, 0)
    $entity = $script:space.AddArc($center, $radius, $a, $b)
    $entity.Layer = 'OUTLINE'
}

function Add-Dimension([double]$x1, [double]$y1, [double]$x2, [double]$y2,
                       [double]$dx, [double]$dy, [double]$angle, [double]$scale) {
    $p1 = [double[]]@($x1, $y1, 0); $p2 = [double[]]@($x2, $y2, 0)
    $location = [double[]]@($dx, $dy, 0)
    $entity = $script:space.AddDimRotated($p1, $p2, $location, $angle)
    $entity.Layer = 'DIMENSIONS'
    $entity.TextHeight = 2.7 * $scale
    $entity.ArrowheadSize = 2.0 * $scale
    $entity.TextGap = 0.7 * $scale
    $entity.PrimaryUnitsPrecision = 0
    $entity.Update()
}

function Add-LocalLine([double]$cx, [double]$cy, [double]$angle,
                       [double]$u1, [double]$v1, [double]$u2, [double]$v2) {
    $a = $angle * [Math]::PI / 180; $c = [Math]::Cos($a); $s = [Math]::Sin($a)
    Add-Line ($cx + $u1 * $c - $v1 * $s) ($cy + $u1 * $s + $v1 * $c) ($cx + $u2 * $c - $v2 * $s) ($cy + $u2 * $s + $v2 * $c)
}

function Add-Well([double]$cx, [double]$cy, [double]$start, [double]$end) {
    # deck.js 的 R96 井口、销槽和支撑臂 / 竖向件口袋；圆弧保留为真圆弧。
    $halfAngle = [Math]::Asin(7.0 / 96.0) * 180 / [Math]::PI
    $c0 = [Math]::Sqrt(96.0 * 96 - 7.0 * 7)
    $features = @()
    foreach ($angle in @(0,45,90,135,180,225,270,315)) { $features += @{ angle = [double]$angle; type = 'slot' } }
    foreach ($angle in @(22.5,67.5,112.5,202.5)) { $features += @{ angle = [double]$angle; type = 'pocket' } }
    foreach ($feature in $features) {
        $a = $feature.angle
        while ($a -lt $start) { $a += 360 }
        while ($a -ge $start + 360) { $a -= 360 }
        $feature.angle = $a
    }
    $features = $features | Where-Object { $_.angle - $halfAngle -gt $start -and $_.angle + $halfAngle -lt $end } | Sort-Object { $_.angle }
    $current = $start
    foreach ($feature in $features) {
        $a = [double]$feature.angle
        if ($a - $halfAngle -gt $current) { Add-Arc $cx $cy 96 $current ($a - $halfAngle) }
        if ($feature.type -eq 'slot') {
            $points = @(@($c0,-7), @(118,-7), @(118,7), @($c0,7))
        } else {
            $points = @(@($c0,-7), @(125,-7), @(125,-13), @(160,-13), @(160,13), @(125,13), @(125,7), @($c0,7))
        }
        for ($i = 0; $i -lt $points.Count - 1; $i++) {
            Add-LocalLine $cx $cy $a $points[$i][0] $points[$i][1] $points[$i+1][0] $points[$i+1][1]
        }
        $current = $a + $halfAngle
    }
    if ($end -gt $current) { Add-Arc $cx $cy 96 $current $end }
}

function New-PartsDrawing($part) {
    $doc = $app.Documents.Add($template)
    $script:space = $doc.ModelSpace
    $doc.SetVariable('INSUNITS', [int16]4)
    $style = $doc.TextStyles.Add('CN_NOTES')
    $style.SetFont('Microsoft YaHei', $false, $false, 134, 34)
    foreach ($entry in @(@('OUTLINE',7), @('DIMENSIONS',3), @('NOTES',7), @('REFERENCE',1))) {
        $layer = $doc.Layers.Add([string]$entry[0]); $layer.Color = [int16]$entry[1]
    }
    $length = [double]$part.length; $width = [double]$part.width; $thickness = [double]$part.thickness
    $scale = [Math]::Max([double]1, [Math]::Max($length, $width) / 150.0)
    $x = 45 * $scale; $y = 45 * $scale
    $frontY = $y + $width + 38 * $scale
    $leftX = $x + $length + 40 * $scale

    # 第一角投影：俯视图在主视图下方，左视图在主视图右方。
    Add-Text ($part.code + '  ' + $part.name + ' / 三视图草案') $x ($frontY + $thickness + 29*$scale) (4*$scale)
    Add-Text '主视图' $x ($frontY + $thickness + 9*$scale) (2.8*$scale)
    Add-Text '左视图' $leftX ($frontY + $thickness + 9*$scale) (2.8*$scale)
    Add-Text '俯视图' $x ($y + $width + 8*$scale) (2.8*$scale)
    Add-Rect $x $frontY $length $thickness
    Add-Rect $leftX $frontY $width $thickness

    if ($part.kind -eq 'tray') {
        # 内端为 X=0，两个 C10；销为装配参考，红色图层不是加工孔。
        Add-Line $x ($y + 10) ($x + 10) $y
        Add-Line ($x + 10) $y ($x + $length) $y
        Add-Line ($x + $length) $y ($x + $length) ($y + $width)
        Add-Line ($x + $length) ($y + $width) ($x + 10) ($y + $width)
        Add-Line ($x + 10) ($y + $width) $x ($y + $width - 10)
        Add-Line $x ($y + $width - 10) $x ($y + 10)
        Add-Line ($x + 10) $frontY ($x + 10) ($frontY + $thickness)
        Add-Line ($leftX + 10) $frontY ($leftX + 10) ($frontY + $thickness)
        Add-Line ($leftX + $width - 10) $frontY ($leftX + $width - 10) ($frontY + $thickness)
        Add-Circle ($x + 10) ($y + $width / 2) 2
        Add-Rect ($x + 8) ($frontY - 5) 4 5 'REFERENCE'
        Add-Rect ($leftX + $width / 2 - 2) ($frontY - 5) 4 5 'REFERENCE'
    } elseif ($part.kind -eq 'deck1') {
        Add-Rect $x $y $length $width
        Add-Well ($x + $length / 2) ($y + $width / 2) -11.25 348.75
    } elseif ($part.kind -eq 'deck2') {
        $cx = $x + $length / 2; $cy = $y + $width / 2
        $sy = $cy - [Math]::Sqrt(96*96 - 38*38)
        $phi = [Math]::Acos(38.0/96) * 180 / [Math]::PI
        Add-Line ($cx+38) $y ($x+$length) $y
        Add-Line ($x+$length) $y ($x+$length) ($y+$width)
        Add-Line ($x+$length) ($y+$width) $x ($y+$width)
        Add-Line $x ($y+$width) $x $y
        Add-Line $x $y ($cx-38) $y
        Add-Line ($cx-38) $y ($cx-38) $sy
        Add-Line ($cx+38) $sy ($cx+38) $y
        Add-Well $cx $cy (-$phi) (180+$phi)
        Add-Line ($x + $length/2 - 38) $frontY ($x + $length/2 - 38) ($frontY + $thickness)
        Add-Line ($x + $length/2 + 38) $frontY ($x + $length/2 + 38) ($frontY + $thickness)
    } else {
        Add-Rect $x $y $length $width
    }

    Add-Dimension $x $y ($x+$length) $y ($x+$length/2) ($y-15*$scale) 0 $scale
    Add-Dimension $x $y $x ($y+$width) ($x-15*$scale) ($y+$width/2) ([Math]::PI/2) $scale
    Add-Text ('板厚 t = ' + $thickness + ' mm') $leftX ($frontY - 11*$scale) (2.6*$scale)
    $noteX = $leftX; $noteY = $y + $width - 5*$scale
    Add-Text '设计说明' $noteX $noteY (3.2*$scale)
    $noteY -= 7*$scale
    foreach ($note in $part.notes) {
        Add-Text $note $noteX $noteY (2.5*$scale)
        $noteY -= 5.5*$scale
    }
    Add-Text '第一角投影 | mm | 设计草案，禁止直接加工' $x ($y - 30*$scale) (2.5*$scale)
    $doc.Regen(1)
    if ($app.Visible) { $app.ZoomExtents() }
    $dxf = Join-Path $OutputDir ($part.code + '_' + $part.name + '.dxf')
    $dwg = Join-Path $OutputDir ($part.code + '_' + $part.name + '.dwg')
    $doc.SaveAs($dxf, 65) # ac2018_dxf
    $doc.SaveAs($dwg, 64) # ac2018_dwg
    Write-Host ($part.code + ' 已生成，实体数 ' + $script:space.Count)
    $doc.Close($false)
}

$parts = @(
    @{code='P01'; name='托盘板'; kind='tray'; length=125; width=60; thickness=3; notes=@('亚克力；内端两个角 C10。','红色为定位销装配参考，不是孔。','销 Φ4，下伸 5；中心距内端 10。','销的固定方式、磁铁和挡车件待定。')},
    @{code='P02'; name='底板'; kind='plate'; length=520; width=520; thickness=6; notes=@('椴木板或亚克力，材料待选。','仅示外形；全部安装孔待实物确认。')},
    @{code='P03'; name='转运台底板'; kind='plate'; length=170; width=66; thickness=3; notes=@('铝板或亚克力，材料待选。','仅示底板外形，不含支撑条。','导轨、电机及轴承孔位待实物确认。')},
    @{code='P04'; name='顶板'; kind='plate'; length=500; width=500; thickness=3; notes=@('亚克力；3 mm 取自采购清单。','三维示意使用 5 mm，厚度待统一。','导杆及丝杆支座孔位待实物确认。')},
    @{code='P05'; name='一层甲板'; kind='deck1'; length=500; width=500; thickness=5; notes=@('亚克力，井孔和槽取自示意模型。','井口 R96；销槽宽 14，至 r118。','支撑臂槽宽 14；口袋宽 26。','主视及左视仅示外轮廓，省略隐藏线。','全部孔槽与安装孔须核对后确定。')},
    @{code='P06'; name='二层甲板'; kind='deck2'; length=500; width=500; thickness=5; notes=@('亚克力，井孔和槽取自示意模型。','前侧 DOCK 竖井缺口宽 76。','井口 R96；7 个销槽，避开竖井。','主视及左视仅示外轮廓，省略隐藏线。','全部孔槽与安装孔须核对后确定。')}
)
foreach ($part in $parts) { New-PartsDrawing $part }
Write-Host ('完成：' + $OutputDir)
