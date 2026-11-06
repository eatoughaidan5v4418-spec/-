<#
.SYNOPSIS
  用 AutoCAD ActiveX 生成 v6 夹紧止推限位方案涉及的板件三视图（单位 mm）。
.NOTES
  Windows PowerShell 5.1: powershell.exe -NoProfile -File tools\create_cad_v6.ps1
  在新目录中生成文件；目标目录已存在时拒绝覆盖。图纸不是加工图。
#>
param(
    [string]$OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\图纸_v6_夹紧止推限位'),
    [switch]$NewInstance
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

if ($NewInstance) { $app = New-Object -ComObject 'AutoCAD.Application.25'; $app.Visible = $false }
else {
    try { $app = [Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25') }
    catch { $app = New-Object -ComObject 'AutoCAD.Application.25' }
}
Write-Host ('连接到 ' + $app.Name + ' ' + $app.Version)
$template = Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
if (-not (Test-Path -LiteralPath $template)) { throw "未找到 AutoCAD 公制模板：$template" }
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\archive\cad\图纸_v3_草案'
$json = & py -X utf8 (Join-Path $PSScriptRoot 'cad_deck_projection_v3.py') $source
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
function Add-PolylineOutline([object[]]$points,[double]$x,[double]$y) {
    for($i=0;$i -lt $points.Count;$i++) {
        $j=($i+1)%$points.Count
        Add-Line ($x+$points[$i][0]) ($y+$points[$i][1]) ($x+$points[$j][0]) ($y+$points[$j][1])
    }
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

function Fit-DrawingView($document) {
    $xmin=[double]::PositiveInfinity; $ymin=$xmin; $xmax=[double]::NegativeInfinity; $ymax=$xmax
    foreach($entity in $document.ModelSpace) {
        try {
            $lo=$null; $hi=$null; $entity.GetBoundingBox([ref]$lo,[ref]$hi)
            $xmin=[Math]::Min($xmin,$lo[0]); $ymin=[Math]::Min($ymin,$lo[1])
            $xmax=[Math]::Max($xmax,$hi[0]); $ymax=[Math]::Max($ymax,$hi[1])
        } catch { }
    }
    if([double]::IsInfinity($xmin)) { throw '无法计算图纸默认视图范围' }
    $vp=$document.ActiveViewport
    $vp.Direction=[double[]]@(0,0,1); $vp.Target=[double[]]@(0,0,0)
    $height=1.2*[Math]::Max(($ymax-$ymin),(($xmax-$xmin)/1.3))
    $aspect=$vp.Width/$vp.Height
    $vp.Width=$height*$aspect; $vp.Height=$height
    $vp.Center=[double[]]@((($xmin+$xmax)/2),(($ymin+$ymax)/2))
    $document.ActiveViewport=$vp
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
    Add-Text ($part.code + '  ' + $part.name + ' / 三视图（v6 夹紧止推限位方案）') $x ($frontY + $thickness + 29*$scale) (4*$scale)
    Add-Text '主视图' $x ($frontY + $thickness + 9*$scale) (2.8*$scale)
    Add-Text '左视图' $leftX ($frontY + $thickness + 9*$scale) (2.8*$scale)
    Add-Text '俯视图' $x ($y + $width + 8*$scale) (2.8*$scale)
    Add-Rect $x $frontY $length $thickness
    Add-Rect $leftX $frontY $width $thickness

    if ($part.kind -eq 'disc') {
        Add-Circle ($x+$length/2) ($y+$width/2) 58 'OUTLINE'
    } elseif ($part.kind -eq 'transfer_v4') {
        # P03B 外形加左侧电机安装耳，所有坐标均以转盘中心为基准。
        $outline=@(@(0,9),@(37,9),@(40,0),@(136,0),@(141,15),@(173,15),
                   @(173,19),@(177,19),@(177,30),@(173,30),@(173,81),
                   @(141,81),@(136,96),@(40,96),@(35,81),@(0,81))
        Add-PolylineOutline $outline $x $y
        foreach($u in @(37,40,136,141,173)) { Add-Line ($x+$u) $frontY ($x+$u) ($frontY+$thickness) }
        foreach($v in @(9,15,19,30,81)) { Add-Line ($leftX+$v) $frontY ($leftX+$v) ($frontY+$thickness) }
    } elseif ($part.kind -eq 'tray') {
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
        $outer=@(@(21,0),@(479,0),@(479,21),@(500,21),@(500,479),@(479,479),
                 @(479,500),@(21,500),@(21,479),@(0,479),@(0,21),@(21,21))
        Add-PolylineOutline $outer $x $y
        Add-Well ($x + $length / 2) ($y + $width / 2) -11.25 348.75
    } elseif ($part.kind -eq 'deck2') {
        $cx = $x + $length / 2; $cy = $y + $width / 2
        $sy = $cy - [Math]::Sqrt(96*96 - 38*38)
        $phi = [Math]::Acos(38.0/96) * 180 / [Math]::PI
        $outer=@(@(288,0),@(479,0),@(479,21),@(500,21),@(500,479),@(479,479),
                 @(479,500),@(21,500),@(21,479),@(0,479),@(0,21),@(21,21),@(21,0),@(212,0))
        for($i=0;$i -lt $outer.Count-1;$i++) {
            Add-Line ($x+$outer[$i][0]) ($y+$outer[$i][1]) ($x+$outer[$i+1][0]) ($y+$outer[$i+1][1])
        }
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
    if ($part.code -in @('P02S','P04')) {
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
        if ($part.code -eq 'P02S') {
            foreach($dx in @(-30,30)) { foreach($dy in @(-15.5,15.5)) {
                $id='J'+$dx+'_'+$dy
                Add-ProposedHole ($cx+140*$c+$dx) ($cy+140*$s+$dy) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
                Add-Circle ($cx+140*$c+$dx) ($cy+140*$s+$dy) 4.2 'PROPOSED_HOLES'
            } }
            $table += 'J：电机轴心 r140 / 112.5°。'
            $table += 'J 四孔相对轴心 X±30、Y±15.5，Φ4.5。'
            $table += '底面沉 Ø8.4 深2.5；不需中心大窗。'
        }
        if ($part.code -eq 'P04') {
            foreach ($sign in @(1,-1)) {
                $index++; $hx = 140*$c - $sign*18*$s; $hy = 140*$s + $sign*18*$c
                $id = 'D' + $index
                Add-ProposedHole ($cx+$hx) ($cy+$hy) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
                $table += ('{0}: X={1:N2}  Y={2:N2}' -f $id,$hx,$hy)
            }
        }
    }
    if ($part.code -in @('P03','P03B','P03D')) {
        $cx = if($part.code -eq 'P03D') {$x+88} else {$x+$length/2}; $cy = $y+$width/2
        Add-Center $cx $cy
        $index = 0
        foreach ($offset in @(-8,8)) {
            $index++; Add-ProposedHole $cx ($cy+$offset) 1.7 ('F'+$index) $x $y $width $frontY $leftX $thickness $scale
            if($part.code -eq 'P03D') { Add-Circle $cx ($cy+$offset) 2.7 'PROPOSED_HOLES' }
        }
        $index = 0
        foreach ($u in @(-29,29)) { foreach ($v in @(-29,29)) {
            if ($part.code -in @('P03B','P03D')) {
                $a=20*[Math]::PI/180
                $hu=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
                $hv=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
            } else { $hu=$u; $hv=$v }
            $index++
            $id='B'+$index
            Add-ProposedHole ($cx+$hu) ($cy+$hv) 2.25 $id $x $y $width $frontY $leftX $thickness $scale
            if ($part.code -in @('P03B','P03D')) {
                $table += ('{0}: u={1:N2}  w={2:N2}' -f $id,$hu,$hv)
                if($part.code -eq 'P03D') { Add-Circle ($cx+$hu) ($cy+$hv) 3.2 'PROPOSED_HOLES' }
            }
        } }
        Add-Dimension $cx ($cy-8) $cx ($cy+8) ($cx+18) $cy ([Math]::PI/2) $scale 'REF'
        $table += 'F=(0, ±8) Ø3.4，沉Ø5.4深1.8（低头）。'
        if ($part.code -eq 'P03') { $table += 'B1～B4: (±29, ±29)，孔径参考 4.5' }
        else { $table += 'B1～B4 为58方孔组旋转20°，Φ4.5' }
        $table += '坐标原点为转运台旋转中心。'
        if ($part.code -in @('P03B','P03D')) {
            Add-Dimension $x ($y+15) $x ($y+81) ($x-7*$scale) ($y+$width/2) ([Math]::PI/2) $scale
            if($part.code -eq 'P03D') { Add-Dimension ($x+40) $y ($x+136) $y ($x+88) ($y-7*$scale) 0 $scale }
            else { Add-Dimension ($x+37) $y ($x+133) $y ($x+85) ($y-7*$scale) 0 $scale }
        }
        if ($part.code -eq 'P03D') {
            Add-ProposedHole ($cx-72) ($cy-23.5) 3.2 'T' $x $y $width $frontY $leftX $thickness $scale
            foreach($dx in @(-11.5,11.5)) { foreach($dy in @(-11.5,11.5)) {
                if($dx -eq 11.5 -and $dy -eq 11.5) {continue}
                Add-ProposedHole ($cx-72+$dx) ($cy-23.5+$dy) 1.4 ('T'+$dx+'_'+$dy) $x $y $width $frontY $leftX $thickness $scale
            } }
            Add-ProposedHole ($cx+83.5) ($cy-23.5) 1.7 'I' $x $y $width $frontY $leftX $thickness $scale
            foreach($u in @(-56,56)) { foreach($w in @(-26.5,28.5)) {
                Add-ProposedHole ($cx+$u) ($cy+$w) 1.4 ('S'+$u+'_'+$w) $x $y $width $frontY $leftX $thickness $scale
            } }
            foreach($u in @(-81.85,-75.35,75.35,81.85)) {
                Add-ProposedHole ($cx+$u) ($cy+22) 1.2 ('L'+$u) $x $y $width $frontY $leftX $thickness $scale
            }
            $table += 'B 孔另沉 Ø6.4、深1.8，低头螺钉。'
            $table += 'T 电机轴 (-72,-23.5) Ø6.4。'
            $table += 'T 三孔轴心±11.5，Ø2.8；I=(83.5,-23.5) Ø3.4。'
            $table += 'S 支撑条孔 u=±56，w=-26.5/28.5，Ø2.8。'
            $table += 'L 拨叉限位座孔 u=±75.35/±81.85，w=22，Ø2.4。'
            $table += '左侧安装耳 u=-88…-51、w=-39。'
            $table += '右侧惰轮耳 u=85…89、w=-29…-18。'
        }
    }
    if ($part.code -eq 'P07R') {
        $cx=$x+$length/2; $cy=$y+$width/2
        Add-Center $cx $cy
        Add-Circle $cx $cy 12 'PROPOSED_HOLES'
        foreach($dx in @(-29,29)) { foreach($dy in @(-29,29)) {
            Add-ProposedHole ($cx+$dx) ($cy+$dy) 2.25 ('B'+$dx+'_'+$dy) $x $y $width $frontY $leftX $thickness $scale
        } }
        foreach($dx in @(-15.5,15.5)) { foreach($dy in @(-15.5,15.5)) {
            Add-ProposedHole ($cx+$dx) ($cy+$dy) 1.7 ('M'+$dx+'_'+$dy) $x $y $width $frontY $leftX $thickness $scale
            Add-Circle ($cx+$dx) ($cy+$dy) 3.1 'PROPOSED_HOLES'
        } }
        foreach($angle in @(22.5,112.5,202.5)) { foreach($radius in @(44,52)) {
            $rad=$angle*[Math]::PI/180
            $hx=$radius*[Math]::Cos($rad); $hy=$radius*[Math]::Sin($rad)
            Add-ProposedHole ($cx+$hx) ($cy+$hy) 1.7 ('A'+$angle+'_'+$radius) $x $y $width $frontY $leftX $thickness $scale
        } }
        $table += '中心 Ø24；B=(±29,±29) Φ4.5。'
        $table += 'M=(±15.5,±15.5) Φ3.4，沉Ø6.2深3.2。'
        $table += 'A：22.5°/112.5°/202.5°各 r44、r52，Φ3.4。'
    }
    if ($part.code -in @('P05R','P06R')) {
        $profile = if($part.code -eq 'P05R') {$projection.P05} else {$projection.P06}
        Add-DeckProjections $profile $x $width $frontY $leftX $thickness
        foreach($v in @(21,479)) {
            Add-Line ($x+$v) $frontY ($x+$v) ($frontY+$thickness) 'OUTLINE'
            Add-Line ($leftX+$v) $frontY ($leftX+$v) ($frontY+$thickness) 'OUTLINE'
        }
        Add-Center ($x+$length/2) ($y+$width/2)
        Add-DeckDetails $leftX ($y+155) $scale
        if ($part.code -eq 'P06R') {
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
        if ($part.code -in @('P02S','P04')) { Add-Text '孔心坐标：塔心原点 / X右 Y后 / mm' $noteX $noteY (2.3*$scale) }
        else { Add-Text '候选孔位坐标（mm）' $noteX $noteY (2.3*$scale) }
        $noteY -= 5*$scale
        foreach ($row in $table) {
            Add-Text $row $noteX $noteY (2.2*$scale) 'PROPOSED_HOLES'
            $noteY -= 4.5*$scale
        }
    }
    Add-Text '第一角投影 | mm | 拟定孔位红色标示，未确认前禁止加工' $x ($y - 30*$scale) (2.5*$scale)
    $doc.Regen(1)
    Fit-DrawingView $doc
    $dxf = Join-Path $OutputDir ($part.code + '_' + $part.name + '.dxf')
    $dwg = Join-Path $OutputDir ($part.code + '_' + $part.name + '.dwg')
    $doc.SaveAs($dxf, 65) # ac2018_dxf
    $doc.SaveAs($dwg, 64) # ac2018_dwg
    Write-Host ($part.code + ' 已生成，实体数 ' + $script:space.Count)
    $doc.Close($false)
}

$parts = @(
    @{code='P02S'; name='底板_短轴支架安装'; kind='plate'; length=520; width=520; thickness=6; notes=@('短轴方案：中央不需开大窗。','升降电机支架四孔 Φ4.5。','支架孔底面沉 Ø8.4 深2.5。','四个导杆支座候选孔 Φ4.5。','红色孔均待实配后加工。')},
    @{code='P03D'; name='转运板_支撑条安装'; kind='transfer_v4'; length=177; width=96; thickness=3; notes=@('采用3 mm铝板，中心局部96×96。','孔 B 先钻 Φ4.5，再沉 Ø6.4 深1.8。','两根5×11铝条下方M2.5螺钉固定。','皮带夹座与铝条之间需实配。','含皮带包络约 R94.64，距井口约1.36。','红色孔仅为方案，复尺后再加工。')},
    @{code='P04'; name='顶板_轴承座安装'; kind='plate'; length=500; width=500; thickness=5; notes=@('已确认顶板厚5 mm。','D1～D4：SHF8，组内孔距32。','D5～D6：KFL08，孔距36。','KFL两耳上方采用22 mm金属支承柱。','安装孔暂定 Ø4.5，须复尺确认。','轴承及螺钉与顶板须实配。')},
    @{code='P05R'; name='一层甲板_四角避让'; kind='deck1'; length=500; width=500; thickness=5; notes=@('四角各切 21×21，名义间隙1。','井口 R96，销槽及四口袋沿用原图。','层甲板安装孔及材料公差待核。','支撑臂 10 宽，夹座外径22。')},
    @{code='P06R'; name='二层甲板_四角避让'; kind='deck2'; length=500; width=500; thickness=5; notes=@('四角各切 21×21，名义间隙1。','井口 R96；DOCK 缺口宽76。','销槽及四口袋沿用原图。','层甲板安装孔及材料公差待核。')},
    @{code='P07R'; name='升降中心盘'; kind='disc'; length=116; width=116; thickness=5; notes=@('铝板圆盘 Ø116×5。','中心开 Ø24，供旋转轴法兰通过。','B 为下转盘螺孔；M 为电机柱安装孔。','短轴方案电机隔柱15；M 沉 Ø6.2 深3.2。','A 为三个支撑臂安装孔，每臂2孔。','全部孔位及沉孔待实测后冻结。')}
)
foreach ($part in $parts) { New-PartsDrawing $part }

if ($NewInstance) { $app.Quit() }
Write-Host ('完成：' + $OutputDir)
