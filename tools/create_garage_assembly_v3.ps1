<#
.SYNOPSIS
  在 AutoCAD 2025 中建立两层车库三维实体、生成 SAT 并检查离散工况的干涉。
.NOTES
  按已确认的两台 42 电机均为 67 mm 长轴建模；未给全尺寸的采购件为近似包络。
  输出为设计核对模型，不是最终加工装配。脚本不会覆盖已有输出目录。
#>
param(
    [string]$OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_初步校核'),
    [switch]$Probe
)

$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAssemblyOleMessageFilter {
    [PreserveSig] int HandleInComingCall(int type, IntPtr caller, int tick, IntPtr info);
    [PreserveSig] int RetryRejectedCall(IntPtr callee, int tick, int rejectType);
    [PreserveSig] int MessagePending(IntPtr callee, int tick, int pendingType);
}
public class AssemblyCadRetryFilter : IAssemblyOleMessageFilter {
    [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IAssemblyOleMessageFilter f, out IAssemblyOleMessageFilter old);
    public static void Register() { IAssemblyOleMessageFilter old; CoRegisterMessageFilter(new AssemblyCadRetryFilter(), out old); }
    public int HandleInComingCall(int t, IntPtr c, int tick, IntPtr i) { return 0; }
    public int RetryRejectedCall(IntPtr c, int tick, int t) { return tick < 30000 ? 200 : -1; }
    public int MessagePending(IntPtr c, int tick, int t) { return 2; }
}
'@
[AssemblyCadRetryFilter]::Register()

if (-not $Probe) {
    if (Test-Path -LiteralPath $OutputDir) { throw "输出目录已存在，拒绝覆盖：$OutputDir" }
    $null=New-Item -ItemType Directory -Path $OutputDir
    $OutputDir=(Resolve-Path -LiteralPath $OutputDir).Path
}
try { $app=[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25') }
catch { $app=New-Object -ComObject 'AutoCAD.Application.25' }
$template=Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
if (-not (Test-Path -LiteralPath $template)) { throw "未找到 AutoCAD 公制模板：$template" }
$doc=$app.Documents.Add($template)
$doc.SetVariable('INSUNITS',[int16]4)
$script:space=$doc.ModelSpace
$origin=[double[]]@(0,0,0)
$zaxis=[double[]]@(0,0,1)
$script:parts=New-Object 'System.Collections.Generic.List[object]'

function Box([double]$x0,[double]$x1,[double]$y0,[double]$y1,[double]$z0,[double]$z1) {
    $p=[double[]]@((($x0+$x1)/2),(($y0+$y1)/2),(($z0+$z1)/2))
    return $script:space.AddBox($p,($x1-$x0),($y1-$y0),($z1-$z0))
}
function Cylinder([double]$x,[double]$y,[double]$z0,[double]$z1,[double]$r) {
    $p=[double[]]@($x,$y,(($z0+$z1)/2))
    return $script:space.AddCylinder($p,$r,($z1-$z0))
}
function Spin($solid,[double]$degrees) {
    if ([Math]::Abs($degrees) -gt 1e-10) { $solid.Rotate3D($origin,$zaxis,$degrees*[Math]::PI/180) }
}
function MoveBy($solid,[double]$x,[double]$y,[double]$z) {
    $solid.Move($origin,[double[]]@($x,$y,$z))
}
function RadialBox([double]$u0,[double]$u1,[double]$w0,[double]$w1,
                   [double]$z0,[double]$z1,[double]$angle) {
    $obj=Box $u0 $u1 $w0 $w1 $z0 $z1
    Spin $obj $angle
    return $obj
}
function Ring([double]$x,[double]$y,[double]$z0,[double]$z1,[double]$outside,[double]$inside) {
    $obj=Cylinder $x $y $z0 $z1 $outside
    $cut=Cylinder $x $y ($z0-1) ($z1+1) $inside
    $obj.Boolean(2,$cut)
    return $obj
}
function Bounds($solid) {
    $min=$null; $max=$null
    $solid.GetBoundingBox([ref]$min,[ref]$max)
    return ,@([double[]]$min,[double[]]$max)
}
function Near([double]$a,[double]$b,[double]$eps=0.001) { return [Math]::Abs($a-$b) -le $eps }

function NewDeck([double]$ztop,[bool]$upper) {
    # R96 真圆和与之连通的 8/7 个销槽、4 个支撑臂槽/口袋；二层加 DOCK 缺口。
    $deck=Box -250 250 -250 250 ($ztop-5) $ztop
    $cut=Cylinder 0 0 ($ztop-6) ($ztop+1) 96
    $deck.Boolean(2,$cut)
    foreach($angle in @(0,45,90,135,180,225,270,315)) {
        if ($upper -and $angle -eq 270) { continue }
        $cut=RadialBox 95 118 -7 7 ($ztop-6) ($ztop+1) $angle
        $deck.Boolean(2,$cut)
    }
    foreach($angle in @(22.5,67.5,112.5,202.5)) {
        $cut=RadialBox 95 125 -7 7 ($ztop-6) ($ztop+1) $angle
        $deck.Boolean(2,$cut)
        $cut=RadialBox 124.999 160 -13 13 ($ztop-6) ($ztop+1) $angle
        $deck.Boolean(2,$cut)
    }
    if ($upper) {
        $cut=Box -38 38 -251 0 ($ztop-6) ($ztop+1)
        $deck.Boolean(2,$cut)
    }
    return $deck
}

function NewTray([double]$inner,[double]$ztop,[double]$angle) {
    # 125×60×3；向内两角各 C10；在托盘本地方向加工再绕井中心旋转。
    $tray=Box $inner ($inner+125) -30 30 $ztop ($ztop+3)
    $sqrt2=[Math]::Sqrt(2)
    foreach($side in @(-1,1)) {
        $nx=-1/$sqrt2; $ny=$side/$sqrt2
        $distance=(20-$inner)/$sqrt2
        $cut=Box $distance ($distance+220) -200 200 ($ztop-1) ($ztop+4)
        Spin $cut ([Math]::Atan2($ny,$nx)*180/[Math]::PI)
        $tray.Boolean(2,$cut)
    }
    Spin $tray $angle
    return $tray
}

function NewTransferPlate([double]$z0,[double]$z1) {
    # P03B：两端宽66，中部96×96，单边5×15过渡。
    $plate=Box -85 85 -33 33 $z0 $z1
    $center=Box -48 48 -48 48 $z0 $z1
    $plate.Boolean(0,$center)
    $sqrt10=[Math]::Sqrt(10)
    foreach($sx in @(-1,1)) { foreach($sy in @(-1,1)) {
        $xa=@((47.99*$sx),(53*$sx)) | Sort-Object
        $ya=@((32.99*$sy),(48*$sy)) | Sort-Object
        $wedge=Box $xa[0] $xa[1] $ya[0] $ya[1] $z0 $z1
        $d=192/$sqrt10
        $half=Box ($d-250) $d -250 250 ($z0-1) ($z1+1)
        Spin $half ([Math]::Atan2($sy,3*$sx)*180/[Math]::PI)
        $wedge.Boolean(1,$half)
        $plate.Boolean(0,$wedge)
    } }
    return $plate
}

function NewSquareRing([double]$x,[double]$y,[double]$z0,[double]$z1,
                       [double]$length,[double]$width,[double]$bore,[double]$angle) {
    $obj=Box (-$length/2) ($length/2) (-$width/2) ($width/2) $z0 $z1
    $cut=Cylinder 0 0 ($z0-1) ($z1+1) $bore
    $obj.Boolean(2,$cut)
    Spin $obj $angle
    MoveBy $obj $x $y 0
    return $obj
}

if ($Probe) {
    $tray=NewTray -41 100 0
    if (-not (Near $tray.Volume 22200 0.01)) { throw ('托盘体积异常：'+$tray.Volume) }
    $p=NewTransferPlate 0 3
    if (-not (Near $p.Volume 42750 0.05)) { throw ('P03B 体积异常：'+$p.Volume) }
    $b=Bounds $p
    if (-not (Near $b[0][0] -85) -or -not (Near $b[1][0] 85) -or
        -not (Near $b[0][1] -48) -or -not (Near $b[1][1] 48)) { throw 'P03B 包络异常' }
    $deck1=NewDeck 100 $false
    $deck2=NewDeck 190 $true
    if ($deck1.Volume -le 1000000 -or $deck2.Volume -ge $deck1.Volume) { throw '甲板体积异常' }
    Write-Output ('PROBE_OK tray_volume='+$tray.Volume+' plate_volume='+$p.Volume+
                  ' deck1_volume='+$deck1.Volume+' deck2_volume='+$deck2.Volume)
    $doc.Close($false)
    exit
}

$layers=@(
    @('BASE',8), @('FRAME',8), @('DECK_L1',4), @('DECK_L2',4), @('ROOF',8),
    @('GUIDES',7), @('SCREW',2), @('MOUNT_ENVELOPE',6), @('LIFT_PLATFORM',5),
    @('TURNTABLE',6), @('TRANSFER_PLATE',4), @('RAIL',7), @('MOTOR_BODY',8),
    @('MOTOR_SHAFT',1), @('TRAY',3), @('TRAY_PIN',2), @('CAR_ENVELOPE',6),
    @('DRAG_CHAIN_ENVELOPE',3), @('INTERFERENCE',1)
)
foreach($entry in $layers) {
    $layer=$doc.Layers.Add([string]$entry[0])
    $layer.Color=[int16]$entry[1]
}

function Part($solid,[string]$id,[string]$label,[string]$role,[string]$layer,
              [bool]$moveZ,[bool]$rotate,[string]$confidence,[int]$transparency=0) {
    $solid.Layer=$layer
    if($transparency -gt 0) { $solid.EntityTransparency=[string]$transparency }
    $record=[pscustomobject]@{ id=$id; label=$label; role=$role; layer=$layer;
        moveZ=$moveZ; rotate=$rotate; confidence=$confidence; solid=$solid }
    $script:parts.Add($record)
}

function RotateXY([double]$radius,[double]$angle) {
    $a=$angle*[Math]::PI/180
    return ,@(($radius*[Math]::Cos($a)),($radius*[Math]::Sin($a)))
}
function DrillPoint($solid,[double]$x,[double]$y,[double]$z0,[double]$z1,[double]$r) {
    $cutter=Cylinder $x $y ($z0-1) ($z1+1) $r
    $solid.Boolean(2,$cutter)
}
function DrillPair($solid,[double]$x,[double]$y,[double]$z0,[double]$z1,
                   [double]$pitch,[double]$angle,[double]$r) {
    foreach($sign in @(-1,1)) {
        $p=RotateXY (($pitch/2)*$sign) $angle
        DrillPoint $solid ($x+$p[0]) ($y+$p[1]) $z0 $z1 $r
    }
}
function DrillQuad($solid,[double]$z0,[double]$z1,[double]$pitch,[double]$angle,[double]$r) {
    $a=$angle*[Math]::PI/180
    foreach($u in @(-($pitch/2),($pitch/2))) { foreach($v in @(-($pitch/2),($pitch/2))) {
        $x=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
        $y=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
        DrillPoint $solid $x $y $z0 $z1 $r
    } }
}

# 坐标原点是底板上表面中心；静态框架和两块甲板。
$base=Box -260 260 -260 260 -6 0
foreach($angle in @(22.5,202.5)) {
    $p=RotateXY 140 $angle
    DrillPair $base $p[0] $p[1] -6 0 32 ($angle+90) 2.25
}
Part $base 'BASE' '底板 520×520×6（4个候选安装孔）' 'BASE' 'BASE' $false $false '方案外形及未冻结候选孔' 25
$postIndex=0
foreach($x in @(-240,240)) { foreach($y in @(-240,240)) {
    $postIndex++
    $body=Box ($x-10) ($x+10) ($y-10) ($y+10) 0 270
    Part $body ("COLUMN_"+$postIndex) ("2020立柱 "+$postIndex) 'FRAME' 'FRAME' $false $false '外包络'
} }
$rings=@(
    @{id='BASE'; z=10; front=$true},
    @{id='ROOF'; z=260; front=$true},
    @{id='L1'; z=85; front=$true},
    @{id='L2'; z=175; front=$false}
)
foreach($ring in $rings) {
    foreach($side in @(-1,1)) {
        $x=240*$side
        $body=Box ($x-10) ($x+10) -230 230 ($ring.z-10) ($ring.z+10)
        Part $body ("RING_"+$ring.id+"_X"+$side) ("环梁 "+$ring.id+" / X"+$side) 'FRAME' 'FRAME' $false $false '外包络'
    }
    foreach($side in @(-1,1)) {
        if(-not $ring.front -and $side -eq -1) {continue}
        $y=240*$side
        $body=Box -230 230 ($y-10) ($y+10) ($ring.z-10) ($ring.z+10)
        Part $body ("RING_"+$ring.id+"_Y"+$side) ("环梁 "+$ring.id+" / Y"+$side) 'FRAME' 'FRAME' $false $false '外包络'
    }
}
foreach($level in @(@{id='L1';top=100},@{id='L2';top=190})) {
    foreach($angle in @(45,135,225,315)) {
        $body=RadialBox 140 322 -10 10 ($level.top-25) ($level.top-5) $angle
        Part $body ("BRACE_"+$level.id+"_"+$angle) ("斜撑 "+$level.id+" / "+$angle+"度") 'BRACE' 'FRAME' $false $false '外包络'
    }
}
$l1=NewDeck 100 $false
Part $l1 'DECK_L1' '一层甲板 500×500×5' 'DECK' 'DECK_L1' $false $false '既有二维轮廓' 60
$l2=NewDeck 190 $true
Part $l2 'DECK_L2' '二层甲板 500×500×5' 'DECK' 'DECK_L2' $false $false '既有二维轮廓' 60
$roof=Box -250 250 -250 250 270 275
foreach($angle in @(22.5,202.5)) {
    $p=RotateXY 140 $angle
    DrillPair $roof $p[0] $p[1] 270 275 32 ($angle+90) 2.25
}
$p=RotateXY 140 112.5
DrillPair $roof $p[0] $p[1] 270 275 36 202.5 2.25
Part $roof 'ROOF' '顶板 500×500×5（6个候选安装孔）' 'ROOF' 'ROOF' $false $false '厚度已确认；孔位待复核' 75
Write-Host ('FRAME_AND_DECKS count='+$parts.Count)

# 导杆、支座、丝杆；支座厚度和外形为商品图包络，安装孔及紧固件没有冻结。
$rodIndex=0
foreach($angle in @(22.5,202.5)) {
    $rodIndex++
    $p=RotateXY 140 $angle
    $body=Cylinder $p[0] $p[1] 0 270 4
    Part $body ("ROD_"+$rodIndex) ("Φ8导杆 "+$rodIndex) 'ROD' 'GUIDES' $false $false '方案尺寸'
    foreach($end in @(@{id='BOTTOM';z0=0;z1=10},@{id='TOP';z0=260;z1=270})) {
        $body=NewSquareRing $p[0] $p[1] $end.z0 $end.z1 43 24 4 ($angle+90)
        DrillPair $body $p[0] $p[1] $end.z0 $end.z1 32 ($angle+90) 2.5
        Part $body ("SHF_"+$rodIndex+"_"+$end.id) ("SHF8支座包络 "+$rodIndex+" / "+$end.id) 'FIXTURE' 'MOUNT_ENVELOPE' $false $false '商品图包络' 30
    }
}
$screw=RotateXY 140 112.5
$body=Box ($screw[0]-21) ($screw[0]+21) ($screw[1]-21) ($screw[1]+21) 0 40
Part $body 'LIFT_MOTOR_BODY' '升降42电机机身包络' 'MOTOR' 'MOTOR_BODY' $false $false '已购外形，40为上限' 20
$body=Cylinder $screw[0] $screw[1] 40 42 11
Part $body 'LIFT_MOTOR_BOSS' '升降电机定位凸缘 Ø22×2' 'MOTOR_BOSS' 'MOTOR_BODY' $false $false '商品图'
$body=Cylinder $screw[0] $screw[1] 40 107 2.5
Part $body 'LIFT_MOTOR_SHAFT' '升降电机长轴 Ø5×67' 'LIFT_SHAFT' 'MOTOR_SHAFT' $false $false '用户确认长轴；圆柱近似'
$coupler=Cylinder $screw[0] $screw[1] 42 67 10
$bore=Cylinder $screw[0] $screw[1] 41 55 2.5
$coupler.Boolean(2,$bore)
$bore=Cylinder $screw[0] $screw[1] 54 68 4
$coupler.Boolean(2,$bore)
Part $coupler 'LIFT_COUPLER' '5-8联轴器 Ø20×25 包络' 'COUPLER' 'MOUNT_ENVELOPE' $false $false '轴向位置和内部孔深假设' 25
$body=Cylinder $screw[0] $screw[1] 60 260 4
Part $body 'LEAD_SCREW' 'T8 丝杆外包络 Ø8×200' 'SCREW' 'SCREW' $false $false '螺纹按圆柱包络'
$body=NewSquareRing $screw[0] $screw[1] 248 260 48 27 4 202.5
DrillPair $body $screw[0] $screw[1] 248 260 36 202.5 2.25
Part $body 'KFL_TOP' 'KFL08 顶部轴承座包络' 'FIXTURE' 'MOUNT_ENVELOPE' $false $false '厚12为假设，未设计支承' 30
$chain=RadialBox 130 152 -7 7 40 250 67.5
Part $chain 'CHAIN_ZONE' '拖链预留包络，不代表实际拖链形状' 'CHAIN_ENVELOPE' 'DRAG_CHAIN_ENVELOPE' $false $false '仅空间占位' 65
Write-Host ('FIXED_COMPONENTS count='+$parts.Count)

# 初始状态：一层对接高度 Z=100，角度 θ=0，托盘在转运台中央。
$zLift=100.0
$body=Cylinder 0 0 ($zLift-27) ($zLift-22) 58
DrillQuad $body ($zLift-27) ($zLift-22) 58 0 2.25
Part $body 'LIFT_DISC' '升降平台中心盘（中心尚未开孔）' 'LIFT_DISC' 'LIFT_PLATFORM' $true $false '示意盘，转盘候选孔未冻结' 30
foreach($angle in @(22.5,112.5,202.5)) {
    $body=RadialBox 40 150 -5 5 ($zLift-42) ($zLift-22) $angle
    Part $body ("LIFT_ARM_"+$angle) ("升降支撑臂 "+$angle+"度") 'ARM' 'LIFT_PLATFORM' $true $false '示意外形，连接未设计' 20
}
$rodIndex=0
foreach($angle in @(22.5,202.5)) {
    $rodIndex++
    $p=RotateXY 140 $angle
    $body=Ring $p[0] $p[1] ($zLift-50) ($zLift-5) 7.5 4
    Part $body ("LM8LUU_"+$rodIndex) ("LM8LUU直线轴承 "+$rodIndex) 'LINEAR_BEARING' 'GUIDES' $true $false '商品图圆环包络'
}
$body=Ring $screw[0] $screw[1] ($zLift-32) ($zLift-22) 11 4
Part $body 'LIFT_NUT' 'T8螺母包络（安装件未设计）' 'NUT' 'SCREW' $true $false '示意包络'
$body=Box -21 21 -21 21 ($zLift-67) ($zLift-27)
Part $body 'ROT_MOTOR_BODY' '旋转42电机机身包络' 'MOTOR' 'MOTOR_BODY' $true $false '已购外形，40为上限' 20
$body=Cylinder 0 0 ($zLift-27) ($zLift-25) 11
Part $body 'ROT_MOTOR_BOSS' '旋转电机定位凸缘 Ø22×2' 'MOTOR_BOSS' 'MOTOR_BODY' $true $false '商品图'
$body=Cylinder 0 0 ($zLift-27) ($zLift+40) 2.5
Part $body 'ROT_MOTOR_SHAFT' '旋转电机长轴 Ø5×67' 'ROT_SHAFT' 'MOTOR_SHAFT' $true $false '用户确认长轴；圆柱近似'
$body=NewSquareRing 0 0 ($zLift-22) ($zLift-21.3) 71 71 17.5 0
DrillQuad $body ($zLift-22) ($zLift-21.3) 58 0 2
Part $body 'BEARING_BOTTOM' '3寸转盘下板包络' 'BEARING_BOTTOM' 'TURNTABLE' $true $false '商品图外形，结构近似' 15
$body=Ring 0 0 ($zLift-21.3) ($zLift-14.7) 31 17.5
Part $body 'BEARING_RACE' '转盘中间滚道包络' 'BEARING_RACE' 'TURNTABLE' $true $false '滚道内外径假设' 30
$body=NewSquareRing 0 0 ($zLift-14.7) ($zLift-14) 71 71 17.5 20
DrillQuad $body ($zLift-14.7) ($zLift-14) 58 20 2
Part $body 'BEARING_TOP' '3寸转盘上板包络（20度布置）' 'BEARING_TOP' 'TURNTABLE' $true $true '商品图外形，结构近似' 15
$body=Ring 0 0 ($zLift-26.2) ($zLift-16.2) 5 2.5
Part $body 'FLANGE_HUB' '5 mm法兰轴套 Ø10×10' 'FLANGE' 'TURNTABLE' $true $true '商品图近似'
$body=Ring 0 0 ($zLift-16.2) ($zLift-14) 11 2.5
DrillPoint $body 0 -8 ($zLift-16.2) ($zLift-14) 1.5
DrillPoint $body 0 8 ($zLift-16.2) ($zLift-14) 1.5
Part $body 'FLANGE_DISC' '法兰片 Ø22×2.2' 'FLANGE' 'TURNTABLE' $true $true '商品图近似'
$body=NewTransferPlate ($zLift-14) ($zLift-11)
DrillPair $body 0 0 ($zLift-14) ($zLift-11) 16 90 1.7
DrillQuad $body ($zLift-14) ($zLift-11) 58 20 2.25
Part $body 'TRANSFER_PLATE' 'P03B局部加宽转运板（尚无中心孔）' 'TRANSFER_PLATE' 'TRANSFER_PLATE' $true $true 'P03B备选二维轮廓' 20
$body=Box -85 85 -3.5 3.5 ($zLift-11) ($zLift-6)
Part $body 'TRANSFER_RAIL' 'MGN7 导轨 170 外包络' 'RAIL' 'RAIL' $true $true '轨高按旧模型5近似'
foreach($w in @(-27,27)) {
    $body=Box -40 85 ($w-3) ($w+3) ($zLift-11) $zLift
    Part $body ("STRIP_"+$w) ("托盘支撑条 w="+$w) 'STRIP' 'LIFT_PLATFORM' $true $true '旧示意外形，安装未设计'
}
$body=Box -84.1 -55.9 -32.1 -3.9 ($zLift-11) ($zLift+14.5)
Part $body 'TRANSFER_MOTOR_BODY' '28步进电机机身包络' 'MOTOR' 'MOTOR_BODY' $true $true '型号外形，安装位置假设' 20
$body=Cylinder -70 -18 ($zLift+14.5) ($zLift+32) 2.5
Part $body 'TRANSFER_MOTOR_SHAFT' '28电机轴 Ø5×17.5' 'TRANSFER_SHAFT' 'MOTOR_SHAFT' $true $true '规格书，轴朝上为假设'
$body=NewTray -41 $zLift 0
Part $body 'CENTER_TRAY' '转运台上的托盘' 'CENTER_TRAY' 'TRAY' $true $true '托盘外形'
$body=Cylinder -31 0 ($zLift-5) $zLift 2
Part $body 'CENTER_PIN' '转运托盘定位销' 'PIN' 'TRAY_PIN' $true $true '外伸5，安装方式未定'
$body=Box -31 74 -21.5 21.5 ($zLift+3) ($zLift+33)
Part $body 'CENTER_CAR' '转运模型车外包络 105×43×30' 'CENTER_CAR' 'CAR_ENVELOPE' $true $true '载荷包络' 65
Write-Host ('MOVING_COMPONENTS count='+$parts.Count)

# 已停放的托盘和车：第一层 E 位由中央托盘占用，DOCK 不放；二层 DOCK 留空。
foreach($level in @(@{id='L1';top=100;angles=@(45,90,135,180,225,315)},
                     @{id='L2';top=190;angles=@(0,45,90,135,180,225,315)})) {
    foreach($angle in $level.angles) {
        $body=NewTray 97 $level.top $angle
        Part $body ("TRAY_"+$level.id+"_"+$angle) ("停放托盘 "+$level.id+" / "+$angle+"度") 'PARKED_TRAY' 'TRAY' $false $false '托盘外形'
        $p=RotateXY 107 $angle
        $body=Cylinder $p[0] $p[1] ($level.top-5) $level.top 2
        Part $body ("PIN_"+$level.id+"_"+$angle) ("停放托盘销 "+$level.id+" / "+$angle+"度") 'PIN' 'TRAY_PIN' $false $false '外伸5，安装方式未定'
        $body=RadialBox 107 212 -21.5 21.5 ($level.top+3) ($level.top+33) $angle
        Part $body ("CAR_"+$level.id+"_"+$angle) ("模型车包络 "+$level.id+" / "+$angle+"度") 'PARKED_CAR' 'CAR_ENVELOPE' $false $false '载荷包络' 70
    }
}
Write-Host ('ASSEMBLY_READY solids='+$parts.Count)

# 对候选孔用细于孔径的临时圆柱探针检查名义贯通；不表示实际紧固件已选定。
$partById=@{}
foreach($p in $parts) { $partById[$p.id]=$p }
$mountRows=New-Object 'System.Collections.Generic.List[object]'
function FastenerProbe([string]$id,[string]$label,[double]$x,[double]$y,[double]$z0,[double]$z1,
                       [double]$radius,[string[]]$componentIds,[string]$note) {
    $probe=Cylinder $x $y $z0 $z1 $radius
    $blocked=New-Object 'System.Collections.Generic.List[string]'
    $err=''
    foreach($componentId in $componentIds) {
        try {
            $hit=$false
            $null=$probe.CheckInterference($partById[$componentId].solid,$false,[ref]$hit)
            if($hit) { $blocked.Add($componentId) }
        } catch { $err=$_.Exception.Message }
    }
    $probe.Delete()
    $status=if($err) {'检查出错'} elseif($blocked.Count -gt 0) {'探针被阻挡'} else {'名义贯通'}
    $mountRows.Add([pscustomobject]@{编号=$id; 位置=$label; X_mm=[Math]::Round($x,3);
        Y_mm=[Math]::Round($y,3); 探针直径_mm=(2*$radius); 检查对象=($componentIds -join ' / ');
        结果=$status; 阻挡=($blocked -join ' / '); 备注=$note; 错误=$err})
}
foreach($angle in @(22.5,202.5)) {
    $index=if($angle -eq 22.5) {1} else {2}
    $p=RotateXY 140 $angle
    foreach($sign in @(-1,1)) {
        $offset=RotateXY (16*$sign) ($angle+90)
        $x=$p[0]+$offset[0]; $y=$p[1]+$offset[1]
        FastenerProbe ("SHF_"+$index+'_BOTTOM_'+$sign) '导杆底座' $x $y -6 10 1.9 @('BASE',("SHF_"+$index+'_BOTTOM')) '孔距32；探针细于候选孔，未计螺钉头。'
        FastenerProbe ("SHF_"+$index+'_TOP_'+$sign) '导杆顶座' $x $y 260 275 1.9 @('ROOF',("SHF_"+$index+'_TOP')) '孔距32；探针细于候选孔，未计螺钉头。'
    }
}
foreach($sign in @(-1,1)) {
    $offset=RotateXY (18*$sign) 202.5
    FastenerProbe ('KFL_'+$sign) '顶部轴承座' ($screw[0]+$offset[0]) ($screw[1]+$offset[1]) 248 275 1.9 @('ROOF','KFL_TOP') '孔距36；KFL孔径假设，支座上方仍有10 mm间隙。'
}
$a=20*[Math]::PI/180
foreach($u in @(-29,29)) { foreach($v in @(-29,29)) {
    $name=('B_'+$u+'_'+$v)
    FastenerProbe ($name+'_LOWER') '转盘下板与升降中心盘' $u $v ($zLift-27) ($zLift-21.3) 1.9 @('LIFT_DISC','BEARING_BOTTOM') '孔距58；未计紧固件头部、垫圈及装拆。'
    $x=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
    $y=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
    FastenerProbe ($name+'_UPPER') '转盘上板与P03B' $x $y ($zLift-14.7) ($zLift-11) 1.9 @('BEARING_TOP','TRANSFER_PLATE') '孔组旋转20°；未计紧固件头部、垫圈及装拆。'
} }
foreach($v in @(-8,8)) {
    FastenerProbe ('FLANGE_'+$v) '法兰与P03B' 0 $v ($zLift-16.2) ($zLift-11) 1.4 @('FLANGE_DISC','TRANSFER_PLATE') '孔距16；未计紧固件头部、垫圈及装拆。'
}
$mountRows | Export-Csv -LiteralPath (Join-Path $OutputDir '候选安装孔_名义贯通检查.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('MOUNT_PROBES total='+$mountRows.Count+' blocked_or_error='+@($mountRows | Where-Object { $_.结果 -ne '名义贯通' }).Count)

# 在添加红色干涉体之前导出各个真实三维实体；SAT 不是 SolidWorks 原生约束装配。
$ss=$doc.SelectionSets.Add('garage_assembly_export')
$ss.Select(5)
if ($ss.Count -ne $parts.Count) {
    throw ('模型空间中实体数 '+$ss.Count+' 与清单 '+$parts.Count+' 不一致，停止导出')
}
$doc.Export((Join-Path $OutputDir '车库_两层三维实体_一层载盘'),'SAT',$ss)
$ss.Delete()

function CollectBounds {
    $result=@{}
    foreach($p in $script:parts) { $result[$p.id]=Bounds $p.solid }
    return $result
}
function BoxesOverlap($a,$b) {
    for($i=0;$i -lt 3;$i++) {
        if ($a[1][$i] -le ($b[0][$i]+0.000001) -or
            $b[1][$i] -le ($a[0][$i]+0.000001)) { return $false }
    }
    return $true
}
function PairKey([string]$a,[string]$b) { return ((@($a,$b) | Sort-Object) -join '|') }
function Classification($a,$b) {
    $roles=@($a.role,$b.role)
    if (($roles -contains 'LIFT_SHAFT' -and $roles -contains 'SCREW') -or
        ($roles -contains 'ROT_SHAFT' -and $roles -contains 'LIFT_DISC') -or
        ($roles -contains 'ROT_SHAFT' -and $roles -contains 'CENTER_TRAY') -or
        ($roles -contains 'ROT_SHAFT' -and $roles -contains 'TRANSFER_PLATE') -or
        ($roles -contains 'ROT_SHAFT' -and $roles -contains 'RAIL')) {
        return '关键轴系实体相交：按当前假设布置需整改'
    }
    if ($a.role -in @('FRAME','BRACE') -and $b.role -in @('FRAME','BRACE')) {
        return '框架包络相交：连接及端部需设计'
    }
    if (($a.role -in @('LIFT_DISC','ARM') -and $b.role -in @('ARM','LINEAR_BEARING','NUT')) -or
        ($b.role -in @('LIFT_DISC','ARM') -and $a.role -in @('ARM','LINEAR_BEARING','NUT'))) {
        return '升降平台连接处：固定方式及开孔待设计'
    }
    if ($a.confidence -match '包络|近似|假设' -or $b.confidence -match '包络|近似|假设') {
        return '包含近似件或包络：须按实物复核'
    }
    return '模型实体相交：须核对是否需要连接或避让'
}
function ClashRow($pose,[double]$height,[double]$angle,$a,$b,$volume) {
    return [pscustomobject]@{工况=$pose; 升降高度_mm=$height; 旋转角_deg=$angle;
        零件A=$a.id; 名称A=$a.label; 零件B=$b.id; 名称B=$b.label;
        相交体积_mm3=$volume; 判读=(Classification $a $b)}
}

$initialBounds=CollectBounds
$manifest=foreach($p in $parts) {
    $b=$initialBounds[$p.id]
    [pscustomobject]@{编号=$p.id; 名称=$p.label; 类别=$p.role; 图层=$p.layer;
        句柄=$p.solid.Handle; 随升降=$p.moveZ; 随转盘=$p.rotate; 尺寸依据=$p.confidence;
        最小X_mm=[Math]::Round($b[0][0],3); 最小Y_mm=[Math]::Round($b[0][1],3);
        最小Z_mm=[Math]::Round($b[0][2],3); 最大X_mm=[Math]::Round($b[1][0],3);
        最大Y_mm=[Math]::Round($b[1][1],3); 最大Z_mm=[Math]::Round($b[1][2],3)}
}
$manifest | Export-Csv -LiteralPath (Join-Path $OutputDir '模型零件与范围.csv') -NoTypeInformation -Encoding UTF8

$critical=@{}
foreach($pair in @(
    @('LIFT_MOTOR_SHAFT','LEAD_SCREW'),
    @('ROT_MOTOR_SHAFT','LIFT_DISC'),
    @('ROT_MOTOR_SHAFT','TRANSFER_PLATE'),
    @('ROT_MOTOR_SHAFT','TRANSFER_RAIL'),
    @('ROT_MOTOR_SHAFT','CENTER_TRAY'),
    @('ROT_MOTOR_SHAFT','CENTER_CAR')
)) { $critical[(PairKey $pair[0] $pair[1])]=$true }
$baselineRows=New-Object 'System.Collections.Generic.List[object]'
$errors=New-Object 'System.Collections.Generic.List[object]'
$baseCandidates=0
for($i=0;$i -lt $parts.Count;$i++) {
    $a=$parts[$i]
    for($j=$i+1;$j -lt $parts.Count;$j++) {
        $b=$parts[$j]
        if (-not (BoxesOverlap $initialBounds[$a.id] $initialBounds[$b.id])) { continue }
        $baseCandidates++
        try {
            $overlap=$false
            $intersection=$a.solid.CheckInterference($b.solid,$true,[ref]$overlap)
            if ($overlap) {
                if ($null -eq $intersection) { throw '返回相交但未生成相交体' }
                $volume=[double]$intersection.Volume
                if ($volume -gt 0.000001) {
                    $baselineRows.Add((ClashRow '一层基准' 100 0 $a $b ([Math]::Round($volume,4))))
                    if ($critical.ContainsKey((PairKey $a.id $b.id))) {
                        $intersection.Layer='INTERFERENCE'
                        $intersection.EntityTransparency='15'
                    } else { $intersection.Delete() }
                } else { $intersection.Delete() }
            }
        } catch {
            $errors.Add([pscustomobject]@{工况='一层基准'; 零件A=$a.id; 零件B=$b.id; 错误=$_.Exception.Message})
        }
    }
}
$baselineRows | Export-Csv -LiteralPath (Join-Path $OutputDir '基准工况_实体相交.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('BASELINE candidates='+$baseCandidates+' overlaps='+$baselineRows.Count+' errors='+$errors.Count)

# 离散状态下只扫描相对位置发生变化的成对实体；同组连接处已在基准状态检查。
$poses=New-Object 'System.Collections.Generic.List[object]'
foreach($height in @(92,100,110,120,130,140,150,160,170,180,182,190)) {
    $poses.Add([pscustomobject]@{height=$height;angle=0})
}
foreach($height in @(100,130,190)) {
    foreach($angle in @(45,90,135,180,225,270,315)) {
        $poses.Add([pscustomobject]@{height=$height;angle=$angle})
    }
}
$sampleRows=New-Object 'System.Collections.Generic.List[object]'
$poseSummary=New-Object 'System.Collections.Generic.List[object]'
$currentZ=100.0; $currentAngle=0.0
foreach($pose in $poses) {
    $dz=[double]$pose.height-$currentZ
    $da=[double]$pose.angle-$currentAngle
    foreach($p in $parts) {
        if ($p.moveZ -and [Math]::Abs($dz) -gt 0.000001) { MoveBy $p.solid 0 0 $dz }
        if ($p.rotate -and [Math]::Abs($da) -gt 0.000001) { Spin $p.solid $da }
    }
    $currentZ=[double]$pose.height; $currentAngle=[double]$pose.angle
    $bounds=CollectBounds
    $candidates=0; $overlaps=0; $errorsBefore=$errors.Count
    for($i=0;$i -lt $parts.Count;$i++) {
        $a=$parts[$i]
        for($j=$i+1;$j -lt $parts.Count;$j++) {
            $b=$parts[$j]
            if ($a.moveZ -eq $b.moveZ -and $a.rotate -eq $b.rotate) { continue }
            if (-not (BoxesOverlap $bounds[$a.id] $bounds[$b.id])) { continue }
            $candidates++
            try {
                $hit=$false
                $null=$a.solid.CheckInterference($b.solid,$false,[ref]$hit)
                if ($hit) {
                    $overlaps++
                    $sampleRows.Add((ClashRow '采样' $currentZ $currentAngle $a $b ''))
                }
            } catch {
                $errors.Add([pscustomobject]@{工况=('Z'+$currentZ+' / '+$currentAngle+'deg');
                    零件A=$a.id; 零件B=$b.id; 错误=$_.Exception.Message})
            }
        }
    }
    $poseSummary.Add([pscustomobject]@{升降高度_mm=$currentZ; 旋转角_deg=$currentAngle;
        候选实体对=$candidates; 相交实体对=$overlaps; 检查错误=($errors.Count-$errorsBefore)})
    Write-Host ('POSE z='+$currentZ+' angle='+$currentAngle+' candidates='+$candidates+' overlaps='+$overlaps+' errors='+($errors.Count-$errorsBefore))
}
# 恢复到一层、0 度，以便图纸、清单和冲突高亮对应同一工况。
foreach($p in $parts) {
    if ($p.rotate -and [Math]::Abs($currentAngle) -gt 0.000001) { Spin $p.solid (-$currentAngle) }
    if ($p.moveZ -and [Math]::Abs($currentZ-100) -gt 0.000001) { MoveBy $p.solid 0 0 (100-$currentZ) }
}
$restoredBounds=CollectBounds
$maxRestoreError=0.0
foreach($p in $parts) {
    for($edge=0;$edge -lt 2;$edge++) { for($axis=0;$axis -lt 3;$axis++) {
        $d=[Math]::Abs($initialBounds[$p.id][$edge][$axis]-$restoredBounds[$p.id][$edge][$axis])
        if($d -gt $maxRestoreError) { $maxRestoreError=$d }
    } }
}
if($maxRestoreError -gt 0.0001) { throw ('运动采样后模型未恢复基准；最大偏差 mm：'+$maxRestoreError) }
$sampleRows | Export-Csv -LiteralPath (Join-Path $OutputDir '运动采样_实体相交.csv') -NoTypeInformation -Encoding UTF8
$poseSummary | Export-Csv -LiteralPath (Join-Path $OutputDir '运动采样_覆盖情况.csv') -NoTypeInformation -Encoding UTF8
if ($errors.Count -gt 0) { $errors | Export-Csv -LiteralPath (Join-Path $OutputDir '干涉检查_错误.csv') -NoTypeInformation -Encoding UTF8 }

$vp=$doc.ActiveViewport
$vp.Direction=[double[]]@(1,-1,0.8)
$doc.ActiveViewport=$vp
if ($app.Visible) {
    try { $doc.SendCommand("_.VSCURRENT`n_Conceptual`n") } catch { Write-Host ('VISUAL_STYLE_NOTE '+$_.Exception.Message) }
}
$doc.Regen(1)
if ($app.Visible) { $app.ZoomExtents() }
$dwgPath=Join-Path $OutputDir '车库_两层三维装配_一层载盘.dwg'
$doc.SaveAs($dwgPath,64)
$summary=[pscustomobject]@{
    单位='mm'; 基准载盘高度_mm=100; 基准转角_deg=0; 实体数=$parts.Count;
    基准候选对=$baseCandidates; 基准相交对=$baselineRows.Count; 离散工况数=$poses.Count;
    采样相交记录数=$sampleRows.Count; 检查错误数=$errors.Count;
    候选孔探针数=$mountRows.Count; 探针阻挡或错误数=@($mountRows | Where-Object { $_.结果 -ne '名义贯通' }).Count;
    恢复基准最大偏差_mm=$maxRestoreError;
    电机长轴_mm=67; 顶板厚_mm=5; 快照说明='一层中央载盘；各层其余车位有托盘和模型车包络'
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir '检查统计.json') -Encoding UTF8
$doc.Close($false)
Write-Host ('DONE dwg='+$dwgPath+' errors='+$errors.Count)
if($errors.Count -gt 0) { throw '存在实体检查错误，请查看干涉检查_错误.csv；检查结果不完整。' }
