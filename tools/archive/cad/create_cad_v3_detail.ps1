<#
.SYNOPSIS
  用 AutoCAD ActiveX 生成 v3 板件补充图（单位 mm），原草案保持不变。
.NOTES
  Windows PowerShell 5.1: powershell.exe -NoProfile -File tools\archive\cad\create_cad_v3_detail.ps1
  在新目录中生成文件；目标目录已存在时拒绝覆盖。图纸不是加工图。
#>
param(
    [string]$OutputDir = (Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'docs\archive\cad\图纸_v3_完善版')
)

$ErrorActionPreference = 'Stop'
# AutoCAD 切换文档/重生成时可能短暂拒绝 COM 调用；仅在本线程限时重试。
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IOleMessageFilter {
    [PreserveSig] int HandleInComingCall(int type, IntPtr caller, int tick, IntPtr info);
    [PreserveSig] int RetryRejectedCall(IntPtr callee, int tick, int rejectType);
    [PreserveSig] int MessagePending(IntPtr callee, int tick, int pendingType);
}
public class CadRetryFilter : IOleMessageFilter {
    [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IOleMessageFilter f, out IOleMessageFilter old);
    public static void Register() { IOleMessageFilter old; CoRegisterMessageFilter(new CadRetryFilter(), out old); }
    public int HandleInComingCall(int t, IntPtr c, int tick, IntPtr i) { return 0; }
    public int RetryRejectedCall(IntPtr c, int tick, int t) { return tick < 20000 ? 200 : -1; }
    public int MessagePending(IntPtr c, int tick, int t) { return 2; }
}
'@
[CadRetryFilter]::Register()
if (Test-Path -LiteralPath $OutputDir) { throw "输出目录已存在，拒绝覆盖：$OutputDir" }
$null = New-Item -ItemType Directory -Path $OutputDir
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

try { $app = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25') }
catch { $app = New-Object -ComObject 'AutoCAD.Application.25' }
Write-Host ('连接到 ' + $app.Name + ' ' + $app.Version)
$template = Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
if (-not (Test-Path -LiteralPath $template)) { throw "未找到 AutoCAD 公制模板：$template" }
$source = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'docs\archive\cad\图纸_v3_草案'
$json = & py -X utf8 (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'cad_deck_projection_v3.py') $source
if ($LASTEXITCODE -ne 0) { throw '甲板正投影计算失败。' }
$projection = $json | ConvertFrom-Json

function Add-Line([double]$x1, [double]$y1, [double]$x2, [double]$y2, [string]$layer = 'OUTLINE') {
    $p1 = [double[]]@($x1, $y1, 0); $p2 = [double[]]@($x2, $y2, 0)
    $entity = $script:space.AddLine($p1, $p2)
    $entity.Layer = $layer
    if ($layer -in @('HIDDEN','PROPOSED_HIDDEN')) { $entity.LinetypeScale = 0.35 }
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

function Add-Arc([double]$x, [double]$y, [double]$radius, [double]$start, [double]$end, [string]$layer = 'OUTLINE') {
    # AddArc 从起点逆时针到终点；把负角度正规化，保留跨 0° 的弧。
    $a = (($start % 360) + 360) % 360 * [Math]::PI / 180
    $b = (($end % 360) + 360) % 360 * [Math]::PI / 180
    $center = [double[]]@($x, $y, 0)
    $entity = $script:space.AddArc($center, $radius, $a, $b)
    $entity.Layer = $layer
}

function Add-Dimension([double]$x1, [double]$y1, [double]$x2, [double]$y2,
                       [double]$dx, [double]$dy, [double]$angle, [double]$scale,
                       [string]$suffix = '', [double]$factor = 1.0) {
    $p1 = [double[]]@($x1, $y1, 0); $p2 = [double[]]@($x2, $y2, 0)
    $location = [double[]]@($dx, $dy, 0)
    $entity = $script:space.AddDimRotated($p1, $p2, $location, $angle)
    $entity.Layer = 'DIMENSIONS'
    $entity.TextHeight = 2.7 * $scale
    $entity.ArrowheadSize = 2.0 * $scale
    $entity.TextGap = 0.7 * $scale
    $entity.PrimaryUnitsPrecision = 0
    $entity.LinearScaleFactor = $factor
    if ($suffix) { $entity.TextOverride = '<> ' + $suffix }
    $entity.Update()
}

function Add-ProposedHole([double]$px, [double]$py, [double]$radius, [string]$label,
                          [double]$viewX, [double]$viewY, [double]$width,
                          [double]$frontY, [double]$leftX, [double]$thickness, [double]$scale) {
    Add-Circle $px $py $radius 'PROPOSED_HOLES'
    Add-Line ($px-3) $py ($px+3) $py 'CENTER'
    Add-Line $px ($py-3) $px ($py+3) 'CENTER'
    Add-Text $label ($px+3.5) ($py+3.5) (1.7*$scale) 'PROPOSED_HOLES'
    foreach ($offset in @(-$radius,$radius)) {
        Add-Line ($px+$offset) $frontY ($px+$offset) ($frontY+$thickness) 'PROPOSED_HIDDEN'
        $sideX = $leftX + $width - ($py - $viewY) + $offset
        Add-Line $sideX $frontY $sideX ($frontY+$thickness) 'PROPOSED_HIDDEN'
    }
}

function Add-Center([double]$x, [double]$y) {
    Add-Line ($x-6) $y ($x+6) $y 'CENTER'
    Add-Line $x ($y-6) $x ($y+6) 'CENTER'
}

function Add-DeckProjections($profile, [double]$x, [double]$width, [double]$frontY,
                             [double]$leftX, [double]$thickness) {
    foreach ($v in $profile.front_hidden) { Add-Line ($x+[double]$v) $frontY ($x+[double]$v) ($frontY+$thickness) 'HIDDEN' }
    foreach ($v in $profile.front_visible) { Add-Line ($x+[double]$v) $frontY ($x+[double]$v) ($frontY+$thickness) 'OUTLINE' }
    foreach ($v in $profile.left_hidden) { Add-Line ($leftX+$width-[double]$v) $frontY ($leftX+$width-[double]$v) ($frontY+$thickness) 'HIDDEN' }
    foreach ($v in $profile.left_visible) { Add-Line ($leftX+$width-[double]$v) $frontY ($leftX+$width-[double]$v) ($frontY+$thickness) 'OUTLINE' }
}

function Add-DeckDetails([double]$x, [double]$y, [double]$annotationScale) {
    # 3:1 局部图；尺寸实体乘 1/3 显示实际尺寸。
    $s = 3.0
    $c0 = [Math]::Sqrt(96*96-7*7)
    $tip = $x + (118-$c0)*$s
    $a = [Math]::Asin(7.0/96)*180/[Math]::PI
    Add-Text '销槽局部 3:1' $x ($y+39) (2.6*$annotationScale)
    Add-Line $x ($y-7*$s) $tip ($y-7*$s) 'DETAIL'
    Add-Line $tip ($y-7*$s) $tip ($y+7*$s) 'DETAIL'
    Add-Line $tip ($y+7*$s) $x ($y+7*$s) 'DETAIL'
    Add-Arc ($x-$c0*$s) $y (96*$s) (-$a-5) (-$a) 'DETAIL'
    Add-Arc ($x-$c0*$s) $y (96*$s) $a ($a+5) 'DETAIL'
    Add-Dimension $tip ($y-7*$s) $tip ($y+7*$s) ($tip+18) $y ([Math]::PI/2) $annotationScale '' (1/$s)
    Add-Text '槽端 r118，根部接 R96' $x ($y-43) (2.1*$annotationScale)

    $x2 = $x + 220
    Add-Text '支撑臂槽及口袋局部 3:1' $x2 ($y+54) (2.6*$annotationScale)
    Add-Line ($x2-45) ($y-7*$s) $x2 ($y-7*$s) 'DETAIL'
    Add-Line $x2 ($y-7*$s) $x2 ($y-13*$s) 'DETAIL'
    Add-Line $x2 ($y-13*$s) ($x2+35*$s) ($y-13*$s) 'DETAIL'
    Add-Line ($x2+35*$s) ($y-13*$s) ($x2+35*$s) ($y+13*$s) 'DETAIL'
    Add-Line ($x2+35*$s) ($y+13*$s) $x2 ($y+13*$s) 'DETAIL'
    Add-Line $x2 ($y+13*$s) $x2 ($y+7*$s) 'DETAIL'
    Add-Line $x2 ($y+7*$s) ($x2-45) ($y+7*$s) 'DETAIL'
    Add-Dimension ($x2+35*$s) ($y-13*$s) ($x2+35*$s) ($y+13*$s) ($x2+35*$s+19) $y ([Math]::PI/2) $annotationScale '' (1/$s)
    Add-Dimension $x2 ($y-13*$s) ($x2+35*$s) ($y-13*$s) ($x2+17.5*$s) ($y-13*$s-16) 0 $annotationScale '' (1/$s)
    Add-Text '连接段宽14；口袋 r125～160' $x2 ($y-74) (2.1*$annotationScale)
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
    try { $null = $doc.Linetypes.Item('HIDDEN2') }
    catch { $doc.Linetypes.Load('HIDDEN2', 'acadiso.lin') }
    foreach ($entry in @(@('OUTLINE',7), @('DIMENSIONS',3), @('NOTES',7), @('REFERENCE',1),
                         @('HIDDEN',8), @('PROPOSED_HOLES',1), @('PROPOSED_HIDDEN',1),
                         @('CENTER',4), @('DETAIL',7))) {
        $layer = $doc.Layers.Add([string]$entry[0]); $layer.Color = [int16]$entry[1]
        if ($entry[0] -in @('HIDDEN','PROPOSED_HIDDEN')) { $layer.Linetype = 'HIDDEN2' }
    }
    $length = [double]$part.length; $width = [double]$part.width; $thickness = [double]$part.thickness
    $scale = [Math]::Max([double]1, [Math]::Max($length, $width) / 150.0)
    $x = 45 * $scale; $y = 45 * $scale
    $frontY = $y + $width + 38 * $scale
    $leftX = $x + $length + 40 * $scale

    # 第一角投影：俯视图在主视图下方，左视图在主视图右方。
    Add-Text ($part.code + '  ' + $part.name + ' / 三视图（完善版）') $x ($frontY + $thickness + 29*$scale) (4*$scale)
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
    } elseif ($part.kind -eq 'transfer_wide') {
        # 中部 96 mm 段宽 96；两端保持宽 66，过渡长各 5。
        $outline = @(@(0,15), @(32,15), @(37,0), @(133,0), @(138,15), @(170,15),
                     @(170,81), @(138,81), @(133,96), @(37,96), @(32,81), @(0,81))
        for ($i=0; $i -lt $outline.Count; $i++) {
            $j = ($i+1) % $outline.Count
            Add-Line ($x+$outline[$i][0]) ($y+$outline[$i][1]) ($x+$outline[$j][0]) ($y+$outline[$j][1])
        }
        foreach ($u in @(32,37,133,138)) { Add-Line ($x+$u) $frontY ($x+$u) ($frontY+$thickness) }
        foreach ($v in @(15,81)) { Add-Line ($leftX+$v) $frontY ($leftX+$v) ($frontY+$thickness) }
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
    } else {
        Add-Rect $x $y $length $width
    }

    Add-Dimension $x $y ($x+$length) $y ($x+$length/2) ($y-15*$scale) 0 $scale
    Add-Dimension $x $y $x ($y+$width) ($x-15*$scale) ($y+$width/2) ([Math]::PI/2) $scale
    $table = @()
    if ($part.kind -eq 'tray') {
        Add-Dimension $x ($y+$width) ($x+10) ($y+$width) ($x+5) ($y+$width+18*$scale) 0 $scale 'REF'
    }
    if ($part.code -in @('P02','P04')) {
        $cx = $x + $length/2; $cy = $y + $width/2
        $index = 0
        foreach ($angle in @(22.5,202.5)) {
            $a = $angle * [Math]::PI / 180; $c = [Math]::Cos($a); $s = [Math]::Sin($a)
            Add-Center ($cx+140*$c) ($cy+140*$s)
            foreach ($sign in @(1,-1)) {
                $index++; $hx = 140*$c - $sign*16*$s; $hy = 140*$s + $sign*16*$c
                $id = 'D' + $index
                Add-ProposedHole ($cx+$hx) ($cy+$hy) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
                $table += ('{0}: X={1:N2}  Y={2:N2}' -f $id,$hx,$hy)
            }
        }
        $a = 112.5 * [Math]::PI / 180; $c = [Math]::Cos($a); $s = [Math]::Sin($a)
        Add-Center ($cx+140*$c) ($cy+140*$s)
        if ($part.code -eq 'P04') {
            foreach ($sign in @(1,-1)) {
                $index++; $hx = 140*$c - $sign*18*$s; $hy = 140*$s + $sign*18*$c
                $id = 'D' + $index
                Add-ProposedHole ($cx+$hx) ($cy+$hy) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
                $table += ('{0}: X={1:N2}  Y={2:N2}' -f $id,$hx,$hy)
            }
        }
    }
    if ($part.code -in @('P03','P03B')) {
        $cx = $x+$length/2; $cy = $y+$width/2
        Add-Center $cx $cy
        $index = 0
        foreach ($offset in @(-8,8)) {
            $index++; Add-ProposedHole $cx ($cy+$offset) 1.7 ('F'+$index) $x $y $width $frontY $leftX $thickness $scale
        }
        $index = 0
        foreach ($u in @(-29,29)) { foreach ($v in @(-29,29)) {
            if ($part.code -eq 'P03B') {
                $a=20*[Math]::PI/180
                $hu=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
                $hv=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
            } else { $hu=$u; $hv=$v }
            $index++
            $id='B'+$index
            Add-ProposedHole ($cx+$hu) ($cy+$hv) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
            if ($part.code -eq 'P03B') { $table += ('{0}: u={1:N2}  w={2:N2}' -f $id,$hu,$hv) }
        } }
        Add-Dimension $cx ($cy-8) $cx ($cy+8) ($cx+18) $cy ([Math]::PI/2) $scale 'REF'
        $table += 'F1/F2: (0, ±8)，孔径参考 3.4'
        if ($part.code -eq 'P03') { $table += 'B1～B4: (±29, ±29)，孔径参考 4.5' }
        else { $table += 'B1～B4 为58方孔组旋转20°，Φ4.5' }
        $table += '坐标原点为转运台旋转中心。'
        if ($part.code -eq 'P03B') {
            Add-Dimension $x ($y+15) $x ($y+81) ($x-7*$scale) ($y+$width/2) ([Math]::PI/2) $scale
            Add-Dimension ($x+37) $y ($x+133) $y ($x+85) ($y-7*$scale) 0 $scale
        }
    }
    if ($part.code -in @('P05','P06')) {
        $profile = $projection.($part.code)
        Add-DeckProjections $profile $x $width $frontY $leftX $thickness
        Add-Center ($x+$length/2) ($y+$width/2)
        Add-DeckDetails $leftX ($y+155) $scale
        if ($part.code -eq 'P06') {
            Add-Dimension ($x+$length/2-38) $y ($x+$length/2+38) $y ($x+$length/2) ($y-7*$scale) 0 $scale
        }
    }
    Add-Text ('板厚 t = ' + $thickness + ' mm') $leftX ($frontY - 11*$scale) (2.6*$scale)
    $noteX = $leftX; $noteY = $y + $width - 5*$scale
    Add-Text '设计说明' $noteX $noteY (3.2*$scale)
    $noteY -= 7*$scale
    foreach ($note in $part.notes) {
        Add-Text $note $noteX $noteY (2.5*$scale)
        $noteY -= 5.5*$scale
    }
    if ($table.Count) {
        $noteY -= 2*$scale
        if ($part.code -in @('P02','P04')) { Add-Text '孔心坐标：塔心原点 / X右 Y后 / mm' $noteX $noteY (2.3*$scale) }
        else { Add-Text '候选孔位坐标（mm）' $noteX $noteY (2.3*$scale) }
        $noteY -= 5*$scale
        foreach ($row in $table) {
            Add-Text $row $noteX $noteY (2.2*$scale) 'PROPOSED_HOLES'
            $noteY -= 4.5*$scale
        }
    }
    Add-Text '第一角投影 | mm | 拟定孔位红色标示，未确认前禁止加工' $x ($y - 30*$scale) (2.5*$scale)
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
    @{code='P01'; name='托盘板'; kind='tray'; length=125; width=60; thickness=3; notes=@('亚克力，内端两角 2×C10。','销轴线距内端10，横向居中30。','红色销 Φ4、下伸5，仅为装配参考。','销固定、磁铁和挡车件仍未确定。','另附无孔空白板闭合轮廓。')},
    @{code='P02'; name='底板'; kind='plate'; length=520; width=520; thickness=6; notes=@('椴木板或亚克力，材料待选。','红色 D1～D4 为 SHF8 候选孔。','两导杆 r140 / 22.5°、202.5°。','安装孔按 M4 预留 Φ4.5，待复尺。','十字仅为轴线，不代表加工孔。','长轴电机、丝杆与支座布置未定。')},
    @{code='P03'; name='转运台底板'; kind='plate'; length=170; width=66; thickness=3; notes=@('铝板或亚克力，材料待选。','红色孔为装配核对方案，禁止钻孔。','法兰 F 孔距16；转盘 B 孔距58。','转盘宽71，超出底板两侧各2.5。','B 孔距边仅4，连接结构须重设计。','导轨、电机、支撑条安装孔未定。')},
    @{code='P03B'; name='转运台底板_局部加宽备选'; kind='transfer_wide'; length=170; width=96; thickness=3; notes=@('备选设计；中部 96×96，两端宽66。','各端过渡长5，单侧展开15。','71方转盘孔组旋转20°后布置。','按头径9及支撑条宽6估算，间隙约2。','旋转包络仍为 R91.2，需三维复核。','红色孔仅为装配方案，禁止直接钻孔。','转盘上下板装拆与电机长轴仍待处理。')},
    @{code='P04'; name='顶板'; kind='plate'; length=500; width=500; thickness=5; notes=@('亚克力，用户确认厚度 5 mm。','D1～D4：SHF8，组内孔距32。','D5～D6：KFL08，孔距36。','红色候选孔按 M4 预留 Φ4.5。','支座均按切向排列，未做实物复尺。','轴端间隙及支座 Z 向装配未定。')},
    @{code='P05'; name='一层甲板'; kind='deck1'; length=500; width=500; thickness=5; notes=@('亚克力，井口 R96；单位 mm。','8 销槽按 0°起每45°，宽14至 r118。','4 口袋：22.5°、67.5°、112.5°、202.5°。','连接段宽14至 r125；口袋 r125～160、宽26。','主、左视虚线由井槽轮廓正投影。','安装孔、材料公差与装配待核。')},
    @{code='P06'; name='二层甲板'; kind='deck2'; length=500; width=500; thickness=5; notes=@('亚克力，井口 R96；单位 mm。','7 销槽：0°起每45°，去掉270°。','4 口袋：22.5°、67.5°、112.5°、202.5°。','连接段宽14至 r125；口袋 r125～160、宽26。','前侧竖井缺口宽76，沿中心线对称。','主、左视虚线由井槽轮廓正投影。','安装孔、材料公差与装配待核。')}
)
foreach ($part in $parts) { New-PartsDrawing $part }

# 独立无孔托盘空白轮廓：真实 1:1，单条闭合多段线；装配孔不在此文件中。
$cutDir = Join-Path $OutputDir '托盘空白板轮廓'
$null = New-Item -ItemType Directory -Path $cutDir
$blank = $app.Documents.Add($template)
$blank.SetVariable('INSUNITS', [int16]4)
$blankLayer = $blank.Layers.Add('CUT_PROFILE')
$blankLayer.Color = [int16]7
$coordinates = [double[]]@(0,10, 10,0, 125,0, 125,60, 10,60, 0,50)
$poly = $blank.ModelSpace.AddLightweightPolyline($coordinates)
$poly.Closed = $true
$poly.Layer = 'CUT_PROFILE'
$blank.Regen(1)
if ($app.Visible) { $app.ZoomExtents() }
$blank.SaveAs((Join-Path $cutDir 'P01_托盘空白板_无孔轮廓.dxf'), 65)
$blank.SaveAs((Join-Path $cutDir 'P01_托盘空白板_无孔轮廓.dwg'), 64)
$blank.Close($false)
Write-Host 'P01 无孔空白板闭合轮廓已生成'
Write-Host ('完成：' + $OutputDir)
