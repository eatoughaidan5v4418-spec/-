<#
.SYNOPSIS
  在 AutoCAD 2025 中建立 v7 两层车库装配、夹带、止推和限位试配方案。
.NOTES
  两台 42 电机改按用户选择的 24 mm 短轴规格；200 mm 丝杆保留。
  输出为设计核对模型，不是最终加工装配。脚本不会覆盖已有输出目录。
#>
param(
    [string]$OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_加厚夹带'),
    [switch]$Probe,
    [switch]$Fast,
    [switch]$NewInstance
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
if($NewInstance) { $app=New-Object -ComObject 'AutoCAD.Application.25'; $app.Visible=$false }
else {
    try { $app=[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25') }
    catch { $app=New-Object -ComObject 'AutoCAD.Application.25' }
}
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
    # R102 真圆和与之连通的 8/7 个销槽、4 个支撑臂槽/口袋；二层加 DOCK 缺口。
    $deck=Box -250 250 -250 250 ($ztop-5) $ztop
    $cut=Cylinder 0 0 ($ztop-6) ($ztop+1) 102
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
    # 立柱在 ±230…250，四角切至 ±229，留 1 mm 名义侧向间隙。
    foreach($sx in @(-1,1)) { foreach($sy in @(-1,1)) {
        $xx=if($sx -gt 0) {@(229,251)} else {@(-251,-229)}
        $yy=if($sy -gt 0) {@(229,251)} else {@(-251,-229)}
        $cut=Box $xx[0] $xx[1] $yy[0] $yy[1] ($ztop-6) ($ztop+1)
        $deck.Boolean(2,$cut)
    } }
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
    $tray=NewTray -38 100 0
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
              [bool]$moveZ,[bool]$rotate,[string]$confidence,[int]$transparency=0,[bool]$slide=$false) {
    $solid.Layer=$layer
    if($transparency -gt 0) { $solid.EntityTransparency=[string]$transparency }
    $record=[pscustomobject]@{ id=$id; label=$label; role=$role; layer=$layer;
        moveZ=$moveZ; rotate=$rotate; slide=$slide; confidence=$confidence; solid=$solid }
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
function CrossCylinder([double]$x,[double]$y,[double]$z,[double]$radius,[double]$length,[double]$angle) {
    # 圆柱轴线沿本地 Y，再绕塔心旋转。
    $obj=Cylinder 0 0 (-$length/2) ($length/2) $radius
    $obj.Rotate3D($origin,[double[]]@(1,0,0),[Math]::PI/2)
    Spin $obj $angle
    MoveBy $obj $x $y $z
    return $obj
}
function LocalPoint([double]$u,[double]$w,[double]$angle) {
    $a=RotateXY $u $angle; $b=RotateXY $w ($angle+90)
    return ,@(($a[0]+$b[0]),($a[1]+$b[1]))
}
function CrossRing([double]$u,[double]$w,[double]$z,[double]$outer,[double]$inner,[double]$length,[double]$angle) {
    $p=LocalPoint $u $w $angle
    $obj=CrossCylinder $p[0] $p[1] $z $outer $length $angle
    $cut=CrossCylinder $p[0] $p[1] $z $inner ($length+2) $angle
    $obj.Boolean(2,$cut)
    return $obj
}
function NewLimitBracket([double]$ringZ,[double]$switchZ,[double]$angle) {
    # 8 mm 导杆开口抱箍，侧板含两个独立的 ±1.5 mm 调整长孔。
    $p=RotateXY 140 $angle
    $obj=Ring $p[0] $p[1] $ringZ ($ringZ+5) 10.5 4.1
    $arm=RadialBox 148 152 3 6 $ringZ ($ringZ+5) $angle
    $obj.Boolean(0,$arm)
    $panel=RadialBox 151 160 3 6 ($switchZ-2) ($switchZ+14.8) $angle
    $obj.Boolean(0,$panel)
    $slit=RadialBox 144 151 -0.6 0.6 ($ringZ-1) ($ringZ+6) $angle
    $obj.Boolean(2,$slit)
    $c=RotateXY 149 $angle
    $cut=CrossCylinder $c[0] $c[1] ($ringZ+2.5) 1.6 30 $angle
    $obj.Boolean(2,$cut)
    foreach($z in @(($switchZ+3.15),($switchZ+9.65))) {
        $slot=RadialBox 154.8 157.2 2 7 ($z-1.5) ($z+1.5) $angle
        $obj.Boolean(2,$slot)
        $c=LocalPoint 156 4.5 $angle
        foreach($end in @(-1.5,1.5)) {
            $cut=CrossCylinder $c[0] $c[1] ($z+$end) 1.2 6 $angle
            $obj.Boolean(2,$cut)
        }
    }
    return $obj
}
function NewBrace([double]$z0,[double]$z1,[double]$angle) {
    # 180 mm 毛坯：两端与框内表面修斜，避免斜撑和环梁体积重叠。
    $brace=RadialBox 140 320 -10 10 $z0 $z1 $angle
    $sx=if([Math]::Cos($angle*[Math]::PI/180) -gt 0) {1} else {-1}
    $sy=if([Math]::Sin($angle*[Math]::PI/180) -gt 0) {1} else {-1}
    $x=if($sx -gt 0) {@(230,400)} else {@(-400,-230)}
    $y=if($sy -gt 0) {@(230,400)} else {@(-400,-230)}
    $cut=Box $x[0] $x[1] -400 400 ($z0-1) ($z1+1)
    $brace.Boolean(2,$cut)
    $cut=Box -400 400 $y[0] $y[1] ($z0-1) ($z1+1)
    $brace.Boolean(2,$cut)
    return $brace
}
function NewSupportArm([double]$z,[double]$angle,[bool]$isNut) {
    # 内段在旋转盘下方；r100 外抬高绕开联轴器；外端为轴承或螺母夹座。
    $obj=RadialBox 40 110 -5 5 ($z-42) ($z-27) $angle
    $collarBottom=if($isNut) {$z-5} else {$z-22}
    $collarTop=if($isNut) {$z+15} else {$z-2}
    $upright=RadialBox 100 110 -5 5 ($z-42) $collarTop $angle
    $obj.Boolean(0,$upright)
    $outer=RadialBox 100 130 -5 5 $collarBottom $collarTop $angle
    $obj.Boolean(0,$outer)
    $center=RotateXY 140 $angle
    $bore=if($isNut) {5.2} else {7.7}
    $collar=Ring $center[0] $center[1] $collarBottom $collarTop 11 $bore
    $obj.Boolean(0,$collar)
    foreach($r in @(44,52)) {
        $p=RotateXY $r $angle
        DrillPoint $obj $p[0] $p[1] ($z-42) ($z-27) 1.7
    }
    if($isNut) {
        DrillPair $obj $center[0] $center[1] $collarBottom $collarTop 16 $angle 1.7
        DrillPair $obj $center[0] $center[1] $collarBottom $collarTop 16 ($angle+90) 1.7
    } else {
        # 直线轴承夹口：外侧 1.2 mm 裂缝、横向 M3 螺孔；螺钉和螺母需实配。
        $slit=RadialBox 147.5 152 -0.6 0.6 ($z-23) ($z-1) $angle
        $obj.Boolean(2,$slit)
        $p=RotateXY 149.3 $angle
        $hole=CrossCylinder $p[0] $p[1] ($z-12) 1.7 30 $angle
        $obj.Boolean(2,$hole)
    }
    return $obj
}
function NewLiftMotorBracket([double]$x,[double]$y) {
    # 上压板＋两侧立壁＋四个底脚孔，留出 42.3 mm 机身和 22 mm 凸台。
    $obj=Box ($x-25) ($x+25) ($y-25) ($y+25) 40 44
    $bore=Cylinder $x $y 39 45 11.5
    $obj.Boolean(2,$bore)
    foreach($dx in @(-15.5,15.5)) { foreach($dy in @(-15.5,15.5)) {
        DrillPoint $obj ($x+$dx) ($y+$dy) 40 44 1.7
    } }
    foreach($sign in @(-1,1)) {
        $x0=if($sign -gt 0) {$x+21.75} else {$x-25}
        $x1=if($sign -gt 0) {$x+25} else {$x-21.75}
        $wall=Box $x0 $x1 ($y-25) ($y+25) 0 40.01
        $obj.Boolean(0,$wall)
        $x0=if($sign -gt 0) {$x+21.75} else {$x-35}
        $x1=if($sign -gt 0) {$x+35} else {$x-21.75}
        $foot=Box $x0 $x1 ($y-25) ($y+25) 0 4
        $obj.Boolean(0,$foot)
    }
    foreach($dx in @(-30,30)) { foreach($dy in @(-15.5,15.5)) {
        DrillPoint $obj ($x+$dx) ($y+$dy) 0 4 2.25
    } }
    return $obj
}

# 坐标原点是底板上表面中心；静态框架和两块甲板。
$base=Box -260 260 -260 260 -6 0
$screw=RotateXY 140 112.5
foreach($dx in @(-30,30)) { foreach($dy in @(-15.5,15.5)) {
    DrillPoint $base ($screw[0]+$dx) ($screw[1]+$dy) -6 0 2.25
    $cut=Cylinder ($screw[0]+$dx) ($screw[1]+$dy) -7 -3.5 4.2
    $base.Boolean(2,$cut)
} }
foreach($angle in @(22.5,202.5)) {
    $p=RotateXY 140 $angle
    DrillPair $base $p[0] $p[1] -6 0 32 ($angle+90) 2.25
}
Part $base 'BASE' '底板 520×520×6（无中心大窗口）' 'BASE' 'BASE' $false $false '方案外形及未冻结候选孔' 25
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
        $body=NewBrace ($level.top-25) ($level.top-5) $angle
        Part $body ("BRACE_"+$level.id+"_"+$angle) ("修斜端斜撑 "+$level.id+" / "+$angle+"度") 'BRACE' 'FRAME' $false $false '型材外包络；角码待实配'
    }
}
$l1=NewDeck 100 $false
Part $l1 'DECK_L1' '一层甲板 500×500×5；4角各21×21避让' 'DECK' 'DECK_L1' $false $false '既有井口；角部改造' 60
$l2=NewDeck 190 $true
Part $l2 'DECK_L2' '二层甲板 500×500×5；4角各21×21避让' 'DECK' 'DECK_L2' $false $false '既有井口；角部改造' 60
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
$body=Box ($screw[0]-21.15) ($screw[0]+21.15) ($screw[1]-21.15) ($screw[1]+21.15) 0 40
Part $body 'LIFT_MOTOR_BODY' '升降42短轴电机机身包络' 'MOTOR' 'MOTOR_BODY' $false $false '24A规格，42.3方、机身40上限' 20
$body=Ring $screw[0] $screw[1] 40 42 11 2.55
Part $body 'LIFT_MOTOR_BOSS' '升降电机定位凸缘 Ø22×2' 'MOTOR_BOSS' 'MOTOR_BODY' $false $false '商品图'
$body=Cylinder $screw[0] $screw[1] 40 64 2.5
Part $body 'LIFT_MOTOR_SHAFT' '升降电机短轴 Ø5×24' 'LIFT_SHAFT' 'MOTOR_SHAFT' $false $false '拟购24A规格；圆柱近似'
$body=NewLiftMotorBracket $screw[0] $screw[1]
Part $body 'LIFT_MOTOR_BRACKET' '升降电机跨机身打印支架' 'LIFT_BRACKET' 'MOUNT_ENVELOPE' $false $false '新增打印件；孔深及强度待核' 10
$body=Box ($screw[0]-8) ($screw[0]+8) ($screw[1]-26.15) ($screw[1]-21.15) 0 9.6
Part $body 'LIFT_MOTOR_CONNECTOR' '升降电机侧向插头包络' 'CONNECTOR' 'MOTOR_BODY' $false $false '按侧向插头外伸5近似，线束未建' 30
$coupler=Cylinder $screw[0] $screw[1] 54 79 10
$bore=Cylinder $screw[0] $screw[1] 53 66.5 2.55
$coupler.Boolean(2,$bore)
$bore=Cylinder $screw[0] $screw[1] 66.49 80 4.05
$coupler.Boolean(2,$bore)
Part $coupler 'LIFT_COUPLER' '5-8联轴器 Ø20×25；两轴端插10/11' 'COUPLER' 'MOUNT_ENVELOPE' $false $false '内部孔深及夹紧位置待实测' 25
$body=Cylinder $screw[0] $screw[1] 68 268 4
Part $body 'LEAD_SCREW' 'T8 丝杆外包络 Ø8×200' 'SCREW' 'SCREW' $false $false '螺纹按圆柱包络'
$body=NewSquareRing $screw[0] $screw[1] 236 248 48 27 6.5 202.5
DrillPair $body $screw[0] $screw[1] 236 248 36 202.5 2.25
Part $body 'KFL_TOP' 'KFL08 顶部轴承座壳体包络' 'FIXTURE' 'MOUNT_ENVELOPE' $false $false '厚12及内圈凸出均是假设，须实测' 30
$body=Ring $screw[0] $screw[1] 235 249 6 4.05
Part $body 'KFL_INNER_RACE' 'KFL 内圈包络，假设两面各凸出1' 'RADIAL_RACE' 'MOUNT_ENVELOPE' $false $false '外径12和凸出1均待实测'
foreach($s in @(@{id='BOTTOM';z0=234},@{id='TOP';z0=248})) {
    $inner=if($s.id -eq 'BOTTOM') {5.5} else {7.0}
    $body=Ring $screw[0] $screw[1] $s.z0 ($s.z0+1) 10 $inner
    Part $body ('THRUST_SEAT_'+$s.id+'_1') '金属阶梯支承垫片第一层' 'THRUST_SEAT' 'MOUNT_ENVELOPE' $false $false '须避开KFL旋转内圈，按实物车削'
    $inner=if($s.id -eq 'BOTTOM') {7.0} else {5.5}
    $body=Ring $screw[0] $screw[1] ($s.z0+1) ($s.z0+2) 10 $inner
    Part $body ('THRUST_SEAT_'+$s.id+'_2') '金属阶梯支承垫片第二层' 'THRUST_SEAT' 'MOUNT_ENVELOPE' $false $false '对推力轴承壳圈提供足够支承'
}
foreach($s in @(@{id='BOTTOM';z0=229},@{id='TOP';z0=250})) {
    $body=Ring $screw[0] $screw[1] $s.z0 ($s.z0+5) 8 4.05
    Part $body ('THRUST_BEARING_'+$s.id) 'F8-16M 止推轴承 8×16×5 外包络' 'THRUST_BEARING' 'MOUNT_ENVELOPE' $false $false '单向受力，上下反装；内部未建模' 10
}
foreach($s in @(@{id='BOTTOM_1';z0=217},@{id='BOTTOM_2';z0=223},@{id='TOP_1';z0=255},@{id='TOP_2';z0=261})) {
    $body=Ring $screw[0] $screw[1] $s.z0 ($s.z0+6) 8.3 4.05
    Part $body ('T8_JAM_'+$s.id) '金属 T8 匹配螺纹对锁薄螺母包络' 'JAM_NUT' 'MOUNT_ENVELOPE' $false $false '每件厚6、外径上限16.6；螺纹及防松需加工验证'
}
foreach($sign in @(-1,1)) {
    $p=RotateXY (18*$sign) 202.5
    $body=Ring ($screw[0]+$p[0]) ($screw[1]+$p[1]) 248 270 5 2.25
    Part $body ('KFL_SPACER_'+$sign) 'KFL08 耳上金属支承柱 Ø10×22' 'SPACER' 'MOUNT_ENVELOPE' $false $false '金属承载，外径10内孔4.5；尺寸按实物修配' 10
}
$limitAngle=22.5
foreach($limit in @(@{id='LOW';ring=31;switch=33;lever=39.5},@{id='HIGH';ring=192;switch=184;lever=190})) {
    $body=NewLimitBracket $limit.ring $limit.switch $limitAngle
    Part $body ('LIMIT_BRACKET_'+$limit.id) '导杆开口抱箍及限位开关可调座' 'LIMIT_BRACKET' 'MOUNT_ENVELOPE' $false $false '试配座；孔距6.5，调节±1.5，具体开关尺寸待核' 10
    $body=RadialBox 153 159 -2.9 2.9 $limit.switch ($limit.switch+12.8) $limitAngle
    $p=LocalPoint 156 0 $limitAngle
    foreach($height in @(($limit.switch+3.15),($limit.switch+9.65))) {
        $cut=CrossCylinder $p[0] $p[1] $height 1.1 10 $limitAngle
        $body.Boolean(2,$cut)
    }
    Part $body ('LIMIT_SWITCH_'+$limit.id) '微动开关本体参考外包络' 'LIMIT_SWITCH' 'MOUNT_ENVELOPE' $false $false 'D2F类参考体；实际型号、触点与摇臂待核'
    $u0=if($limit.id -eq 'LOW') {146.8} else {150.0}
    $body=RadialBox $u0 153 -2 -1 $limit.lever ($limit.lever+0.5) $limitAngle
    Part $body ('LIMIT_LEVER_'+$limit.id) '微动开关摇臂未变形包络' 'LIMIT_LEVER' 'MOUNT_ENVELOPE' $false $false '仅触发位置示意；动作后会弹性变形，非实际商品尺寸'
}
$chain=RadialBox 130 152 -7 7 40 250 67.5
Part $chain 'CHAIN_ZONE' '拖链预留包络，不代表实际拖链形状' 'CHAIN_ENVELOPE' 'DRAG_CHAIN_ENVELOPE' $false $false '仅空间占位' 65
Write-Host ('FIXED_COMPONENTS count='+$parts.Count)

# 初始状态：一层对接高度 Z=100，角度 θ=0，托盘在转运台中央。
$zLift=100.0
$body=Cylinder 0 0 ($zLift-27) ($zLift-22) 58
$cut=Cylinder 0 0 ($zLift-28) ($zLift-21) 12
$body.Boolean(2,$cut)
DrillQuad $body ($zLift-27) ($zLift-22) 58 0 2.25
foreach($x in @(-15.5,15.5)) { foreach($y in @(-15.5,15.5)) {
    DrillPoint $body $x $y ($zLift-27) ($zLift-22) 1.7
    $counterbore=Cylinder $x $y ($zLift-25.2) ($zLift-21) 3.1
    $body.Boolean(2,$counterbore)
} }
foreach($angle in @(22.5,112.5,202.5)) { foreach($radius in @(44,52)) {
    $p=RotateXY $radius $angle
    DrillPoint $body $p[0] $p[1] ($zLift-27) ($zLift-22) 1.7
} }
Part $body 'LIFT_DISC' '升降中心盘 R58×5，中心孔Ø24' 'LIFT_DISC' 'LIFT_PLATFORM' $true $false '铝板方案；孔位需实配' 30
foreach($angle in @(22.5,112.5,202.5)) {
    $isNut=($angle -eq 112.5)
    $body=NewSupportArm $zLift $angle $isNut
    Part $body ("LIFT_ARM_"+$angle) ("阶梯支撑臂及夹座 "+$angle+"度") 'ARM' 'LIFT_PLATFORM' $true $false '新打印件；夹紧与承载需实测' 20
}
$rodIndex=0
foreach($angle in @(22.5,202.5)) {
    $rodIndex++
    $p=RotateXY 140 $angle
    $body=Ring $p[0] $p[1] ($zLift-50) ($zLift-5) 7.5 4
    Part $body ("LM8LUU_"+$rodIndex) ("LM8LUU直线轴承 "+$rodIndex) 'LINEAR_BEARING' 'GUIDES' $true $false '商品图圆环包络'
}
$body=Ring $screw[0] $screw[1] $zLift ($zLift+15) 5 4.05
Part $body 'LIFT_NUT' 'T8螺母本体 Ø10×15 包络' 'NUT' 'SCREW' $true $false '螺母本体尺寸假设，须实测'
$body=Ring $screw[0] $screw[1] ($zLift+15) ($zLift+18) 11 4.05
DrillPair $body $screw[0] $screw[1] ($zLift+15) ($zLift+18) 16 112.5 1.7
DrillPair $body $screw[0] $screw[1] ($zLift+15) ($zLift+18) 16 202.5 1.7
Part $body 'LIFT_NUT_FLANGE' 'T8螺母法兰 Ø22；孔距圆16' 'NUT_FLANGE' 'SCREW' $true $false '法兰及孔位假设，须实测'
$body=Box -21.15 21.15 -21.15 21.15 ($zLift-82) ($zLift-42)
Part $body 'ROT_MOTOR_BODY' '旋转42短轴电机机身包络' 'MOTOR' 'MOTOR_BODY' $true $false '24A规格，42.3方、机身40上限' 20
$body=Box -8 8 -26.15 -21.15 ($zLift-82) ($zLift-72.4)
Part $body 'ROT_MOTOR_CONNECTOR' '旋转电机侧向插头包络' 'CONNECTOR' 'MOTOR_BODY' $true $false '按侧向插头外伸5近似，线束未建' 30
$body=Ring 0 0 ($zLift-42) ($zLift-40) 11 2.55
Part $body 'ROT_MOTOR_BOSS' '旋转电机定位凸缘 Ø22×2' 'MOTOR_BOSS' 'MOTOR_BODY' $true $false '商品图'
$body=Cylinder 0 0 ($zLift-42) ($zLift-18) 2.5
Part $body 'ROT_MOTOR_SHAFT' '旋转电机短轴 Ø5×24' 'ROT_SHAFT' 'MOTOR_SHAFT' $true $false '拟购24A规格；圆柱近似'
foreach($x in @(-15.5,15.5)) { foreach($y in @(-15.5,15.5)) {
    $body=Ring $x $y ($zLift-42) ($zLift-27) 4 1.7
    Part $body ('ROT_SPACER_'+$x+'_'+$y) '旋转电机 15 mm 安装柱' 'SPACER' 'MOUNT_ENVELOPE' $true $false '新打印件；M3紧固深度待核' 10
} }
$body=NewSquareRing 0 0 ($zLift-22) ($zLift-21.3) 71 71 17.5 0
DrillQuad $body ($zLift-22) ($zLift-21.3) 58 0 2
Part $body 'BEARING_BOTTOM' '3寸转盘下板包络' 'BEARING_BOTTOM' 'TURNTABLE' $true $false '商品图外形，结构近似' 15
$body=Ring 0 0 ($zLift-21.3) ($zLift-14.7) 31 17.5
Part $body 'BEARING_RACE' '转盘中间滚道包络' 'BEARING_RACE' 'TURNTABLE' $true $false '滚道内外径假设' 30
$body=NewSquareRing 0 0 ($zLift-14.7) ($zLift-14) 71 71 17.5 20
DrillQuad $body ($zLift-14.7) ($zLift-14) 58 20 2
Part $body 'BEARING_TOP' '3寸转盘上板包络（20度布置）' 'BEARING_TOP' 'TURNTABLE' $true $true '商品图外形，结构近似' 15
$body=Ring 0 0 ($zLift-34.2) ($zLift-24.2) 5 2.5
Part $body 'FLANGE_HUB' '5 mm法兰轴套 Ø10×10' 'FLANGE' 'TURNTABLE' $true $true '商品图近似'
$body=Ring 0 0 ($zLift-24.2) ($zLift-22) 11 2.5
DrillPoint $body 0 -8 ($zLift-24.2) ($zLift-22) 1.5
DrillPoint $body 0 8 ($zLift-24.2) ($zLift-22) 1.5
Part $body 'FLANGE_DISC' '法兰片 Ø22×2.2' 'FLANGE' 'TURNTABLE' $true $true '商品图近似'
$body=Ring 0 0 ($zLift-22) ($zLift-14) 11 2.6
DrillPair $body 0 0 ($zLift-22) ($zLift-14) 16 90 1.4
Part $body 'FLANGE_SPACER' '转盘中孔内 Ø22×8 法兰隔套' 'FLANGE_SPACER' 'TURNTABLE' $true $true '新打印件；扭矩与接触面待验证' 10
$transferX=-74.0; $transferY=-23.5; $idlerX=87.5
$body=NewTransferPlate ($zLift-14) ($zLift-11)
# 为电机及限位安装孔保留左边缘；惰轮及带轮轮廓仍须实测。
$ear=Box -85 -50 -39 -32.999 ($zLift-14) ($zLift-11)
$body.Boolean(0,$ear)
$ear=Box -90 -84.999 -39 33 ($zLift-14) ($zLift-11)
$body.Boolean(0,$ear)
$ear=Box 84.999 93 -29 -18 ($zLift-14) ($zLift-11)
$body.Boolean(0,$ear)
DrillPair $body 0 0 ($zLift-14) ($zLift-11) 16 90 1.7
foreach($v in @(-8,8)) {
    $cut=Cylinder 0 $v ($zLift-12.8) ($zLift-10) 2.7
    $body.Boolean(2,$cut)
}
DrillQuad $body ($zLift-14) ($zLift-11) 58 20 2.25
foreach($u in @(-29,29)) { foreach($v in @(-29,29)) {
    $a=20*[Math]::PI/180
    $x=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
    $y=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
    $cut=Cylinder $x $y ($zLift-12.8) ($zLift-10) 3.2
    $body.Boolean(2,$cut)
} }
DrillPoint $body $transferX $transferY ($zLift-14) ($zLift-11) 3.2
foreach($dx in @(-11.5,11.5)) { foreach($dy in @(-11.5,11.5)) {
    if($dx -eq 11.5 -and $dy -eq 11.5) {continue}
    DrillPoint $body ($transferX+$dx) ($transferY+$dy) ($zLift-14) ($zLift-11) 1.4
} }
DrillPoint $body $idlerX $transferY ($zLift-14) ($zLift-11) 1.7
foreach($u in @(-56,56)) { foreach($w in @(-26.5,28.5)) {
    DrillPoint $body $u $w ($zLift-14) ($zLift-11) 1.4
} }
foreach($u in @(-81.85,-75.35,75.35,81.85)) {
    DrillPoint $body $u 22 ($zLift-14) ($zLift-11) 1.2
}
Part $body 'TRANSFER_PLATE' 'P03E转运板：增加两支撑条安装孔' 'TRANSFER_PLATE' 'TRANSFER_PLATE' $true $true '电机、惰轮和支撑条孔待实配' 20
$body=Box -85 85 -3.5 3.5 ($zLift-11) ($zLift-6)
Part $body 'TRANSFER_RAIL' 'MGN7 导轨 170 外包络' 'RAIL' 'RAIL' $true $true '轨高按旧模型5近似'
foreach($s in @(@{w=-26.5;end=78.5},@{w=28.5;end=85})) {
    $w=$s.w
    $body=Box -60 $s.end ($w-2.5) ($w+2.5) ($zLift-11) $zLift
    foreach($u in @(-56,56)) { DrillPoint $body $u $w ($zLift-11) ($zLift-6) 1.3 }
    Part $body ("STRIP_"+$w) ("托盘铝支撑条 w="+$w) 'STRIP' 'LIFT_PLATFORM' $true $true '5×11铝条；两端M2.5盲螺纹，支承与强度待验证'
}
$body=Box ($transferX-14.1) ($transferX+14.1) ($transferY-14.1) ($transferY+14.1) ($zLift+6) ($zLift+31.5)
Part $body 'TRANSFER_MOTOR_BODY' '28步进电机机身包络（轴向下）' 'MOTOR' 'MOTOR_BODY' $true $true '规格书；机身25.5为上限' 20
$body=Ring $transferX $transferY ($zLift+4) ($zLift+6) 11 2.55
Part $body 'TRANSFER_MOTOR_BOSS' '28电机 Ø22 定位凸缘' 'MOTOR_BOSS' 'MOTOR_BODY' $true $true '规格书'
$body=Cylinder $transferX $transferY ($zLift-11.5) ($zLift+6) 2.5
Part $body 'TRANSFER_MOTOR_SHAFT' '28电机轴 Ø5×17.5（向下）' 'TRANSFER_SHAFT' 'MOTOR_SHAFT' $true $true '规格书；轴方向为设计方案'
foreach($dx in @(-11.5,11.5)) { foreach($dy in @(-11.5,11.5)) {
    if($dx -eq 11.5 -and $dy -eq 11.5) {continue}
    $body=Ring ($transferX+$dx) ($transferY+$dy) ($zLift-11) ($zLift+6) 2.5 1.4
    Part $body ('TRANSFER_SPACER_'+$dx+'_'+$dy) '28电机 17 mm 安装柱' 'SPACER' 'MOUNT_ENVELOPE' $true $true '新打印件；滑块旁名义间隙1待实配' 10
} }
$body=Ring $transferX $transferY ($zLift-9.5) ($zLift-3.5) 6.5 2.55
Part $body 'TRANSFER_PULLEY' 'GT2 16齿带轮包络（实际尺寸待核）' 'PULLEY' 'RAIL' $true $true '外径13、轮宽6是假设'
$body=Ring $idlerX $transferY ($zLift-9.5) ($zLift-3.5) 6.5 1.7
Part $body 'TRANSFER_IDLER' 'GT2 惰轮包络（实际尺寸待核）' 'IDLER' 'RAIL' $true $true '外径13、轮宽6是假设'
# 同步带采用外径包络的保守几何，实际齿形与夹紧方式尚未确定。
foreach($side in @(@{id='NEAR';y0=($transferY+6.5);y1=($transferY+7.9)},@{id='FAR';y0=($transferY-7.9);y1=($transferY-6.5)})) {
    $body=Box $transferX $idlerX $side.y0 $side.y1 ($zLift-9.5) ($zLift-3.5)
    Part $body ('BELT_'+$side.id) ('GT2皮带直线包络 '+$side.id) 'BELT' 'RAIL' $true $true '皮带厚1.4、宽6包络，齿形待核'
}
foreach($end in @(@{id='MOTOR';x=$transferX;lo=($transferX-10);hi=$transferX},@{id='IDLER';x=$idlerX;lo=$idlerX;hi=($idlerX+10)})) {
    $body=Ring $end.x $transferY ($zLift-9.5) ($zLift-3.5) 7.9 6.5
    $half=Box $end.lo $end.hi ($transferY-10) ($transferY+10) ($zLift-11) ($zLift-3)
    $body.Boolean(1,$half)
    Part $body ('BELT_WRAP_'+$end.id) ('GT2皮带绕轮包络 '+$end.id) 'BELT' 'RAIL' $true $true '按轮缘保守包络，实际轮径待测'
}
$sliderCenter=-69.0
$forkCenter=-67.0
$body=Box ($sliderCenter-11.25) ($sliderCenter+11.25) -8.5 8.5 ($zLift-6) ($zLift-3)
Part $body 'TRANSFER_SLIDER' 'MGN7C滑块上部包络；收回位置' 'SLIDER' 'RAIL' $true $true '宽17长22.5的包络，实际滑块待核' 15 $true
$body=Box ($forkCenter-10) ($forkCenter+10) -7.5 7.5 ($zLift-3) ($zLift-1)
$bar=Box ($forkCenter+8) ($forkCenter+34) -3 3 ($zLift-3) ($zLift-1)
$body.Boolean(0,$bar)
$eye=Ring ($forkCenter+36) 0 ($zLift-5) ($zLift-1) 5 2.6
$body.Boolean(0,$eye)
$cut=Cylinder ($forkCenter+36) 0 ($zLift-6) $zLift 2.6
$body.Boolean(2,$cut)
foreach($y in @(-6,6)) { DrillPoint $body $sliderCenter $y ($zLift-3) ($zLift-1) 1.1 }
 # 夹座向惰轮方向移动 0.5 mm；两端越程时无需削薄背壁。
# 皮带上移 0.5 mm，为 1 mm 挡边保留与板面的间隙。
$clampCenter=$forkCenter+0.5
$x0=$clampCenter+1; $x1=$clampCenter+7
$bridge=Box ($clampCenter-3) ($clampCenter+11) -19 -7 ($zLift-2.5) ($zLift-1)
$body.Boolean(0,$bridge)
$outer=Box ($clampCenter-3) ($clampCenter+11) -12.4 -9.9 ($zLift-9.5) ($zLift-1.5)
$body.Boolean(0,$outer)
$inner=Box $x0 $x1 -19 -17 ($zLift-9.6) ($zLift-2.4)
$body.Boolean(0,$inner)
$lip=Box $x0 $x1 -19 -14.1 ($zLift-10.5) ($zLift-9.5)
$body.Boolean(0,$lip)
foreach($x in @(($clampCenter-0.5),($clampCenter+8.5))) {
    $hole=CrossCylinder $x -11.15 ($zLift-6.5) 1.1 5 0
    $body.Boolean(2,$hole)
    $pocket=Box ($x-2.4) ($x+2.4) -11.9 -10.2 ($zLift-9.6) ($zLift-4.4)
    $body.Boolean(2,$pocket)
}
Part $body 'TRANSFER_FORK' '拨叉及加厚双螺钉开口带夹座' 'FORK' 'RAIL' $true $true '背壁2mm、挡边1mm；6mm搭接、强度、带路和拉脱仍待实测' 10 $true
$body=Box $x0 $x1 -15.6 -14.2 ($zLift-9.5) ($zLift-3.5)
Part $body 'BELT_END_OVERLAP' '第二条开口皮带端搭接包络' 'BELT_END' 'RAIL' $true $true '6mm重叠近似；带端过渡和张紧未建' 25 $true
$body=Box ($clampCenter-3) ($clampCenter+11) -14.2 -12.6 ($zLift-9.3) ($zLift-3.7)
Part $body 'BELT_PRESS_PLATE' '皮带压片 14×5.6×1.6' 'BELT_PRESS' 'MOUNT_ENVELOPE' $true $true '金属压片候选；边缘倒钝，实际厚度和受力待核' 10 $true
foreach($x in @(($clampCenter-0.5),($clampCenter+8.5))) {
    $nut=Box ($x-2.3) ($x+2.3) -11.85 -10.25 ($zLift-8.55) ($zLift-4.45)
    $cut=CrossCylinder $x -11.05 ($zLift-6.5) 1.05 3 0
    $nut.Boolean(2,$cut)
    Part $nut ('BELT_M2_NUT_'+$x) 'M2 六角螺母矩形包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $true $true '可从底部滑入，尺寸待实测' 0 $true
    $bolt=CrossCylinder $x -11.1 ($zLift-6.5) 1 3 0
    Part $bolt ('BELT_M2_SETSCR_'+$x) 'M2×3 平端紧定螺钉包络' 'FASTENER' 'MOUNT_ENVELOPE' $true $true '须用短内六角工具调压，螺钉及压片实配' 0 $true
}
foreach($end in @(
    @{id='IN'; min=-85; max=-72.2; panelMin=-89; panelMax=-72.2; fingerMin=-85; fingerMax=-79; holes=@(-81.85,-75.35); leverMin=-81.25; leverMax=-80.75},
    @{id='OUT'; min=72.2; max=85; panelMin=72.2; panelMax=89; fingerMin=83; fingerMax=89; holes=@(75.35,81.85); leverMin=80.75; leverMax=81.25}
)) {
    $holder=Box $end.panelMin $end.panelMax 17.4 20.4 ($zLift-11) ($zLift-2)
    $foot=Box $end.min $end.max 20.399 24 ($zLift-11) ($zLift-8.5)
    $holder.Boolean(0,$foot)
    $stop=Box $end.fingerMin $end.fingerMax 7 17.401 ($zLift-3) ($zLift-1.5)
    $holder.Boolean(0,$stop)
    foreach($x in $end.holes) {
        # 横向长孔使开关可以沿行程调整 ±0.5；底座孔另由板底固定。
        $slot=Box ($x-0.5) ($x+0.5) 17 21 ($zLift-7.3) ($zLift-4.9)
        $holder.Boolean(2,$slot)
        foreach($dx in @(-0.5,0.5)) {
            $cut=CrossCylinder ($x+$dx) 18.9 ($zLift-6.1) 1.2 5 0
            $holder.Boolean(2,$cut)
        }
        DrillPoint $holder $x 22 ($zLift-11) ($zLift-9) 1.1
    }
    Part $holder ('FORK_LIMIT_BRACKET_'+$end.id) '拨叉端点开关支架及柔性止挡' 'FORK_LIMIT_BRACKET' 'MOUNT_ENVELOPE' $true $true '固定孔及开关需实配；打印止挡不作为防坠或安全保护' 10
    $body=Box $end.min $end.max 11.5 17.3 ($zLift-9) ($zLift-3.2)
    foreach($x in $end.holes) {
        $cut=CrossCylinder $x 14.4 ($zLift-6.1) 1.1 8 0
        $body.Boolean(2,$cut)
    }
    Part $body ('FORK_LIMIT_SWITCH_'+$end.id) '拨叉微动开关本体包络' 'LIMIT_SWITCH' 'MOUNT_ENVELOPE' $true $true '孔距6.5参考；实际开关、摇臂、布线待核'
    $lever=Box $end.leverMin $end.leverMax 8 11.5 ($zLift-3.9) ($zLift-3.2)
    Part $lever ('FORK_LIMIT_LEVER_'+$end.id) '拨叉端点开关摇臂未变形包络' 'FORK_LIMIT_LEVER' 'MOUNT_ENVELOPE' $true $true '仅触点示意，真实摇臂变形和动作点待测'
    foreach($x in $end.holes) {
        $p=CrossCylinder $x 17.5 ($zLift-6.1) 1 12 0
        Part $p ('FORK_SWITCH_'+$end.id+'_'+$x+'_SHAFT') '拨叉端限位 M2×12 螺钉' 'FASTENER' 'MOUNT_ENVELOPE' $true $true '尺寸及头部待核'
        $p=CrossCylinder $x 10.75 ($zLift-6.1) 2 1.5 0
        Part $p ('FORK_SWITCH_'+$end.id+'_'+$x+'_HEAD') '拨叉端限位 M2 螺钉头' 'FASTENER_HEAD' 'MOUNT_ENVELOPE' $true $true '近似'
        $p=CrossRing $x 21.2 ($zLift-6.1) 2.35 1.1 1.6 0
        Part $p ('FORK_SWITCH_'+$end.id+'_'+$x+'_NUT') '拨叉端限位 M2 螺母包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $true $true '近似'
    }
}
$body=NewTray -38 $zLift 0
Part $body 'CENTER_TRAY' '转运台上的托盘' 'CENTER_TRAY' 'TRAY' $true $true '125×60；定位销距内端7，较v6向外移3' 0 $true
$body=Cylinder -31 0 ($zLift-5) $zLift 2
Part $body 'CENTER_PIN' '转运托盘定位销' 'PIN' 'TRAY_PIN' $true $true '外伸5，安装方式未定' 0 $true
$body=Box -31 74 -21.5 21.5 ($zLift+3) ($zLift+33)
Part $body 'CENTER_CAR' '转运模型车外包络 105×43×30' 'CENTER_CAR' 'CAR_ENVELOPE' $true $true '载荷包络' 65 $true

# 紧固件只表示轴杆、圆形头部和螺母外包络；实际螺钉规格、咬合和可达性需实测。
function AddFastener([string]$id,[double]$x,[double]$y,[double]$z0,[double]$z1,[double]$shaftR,
                     [double]$head0,[double]$head1,[double]$headR,
                     [double]$nut0,[double]$nut1,[double]$nutR,[bool]$moveZ,[bool]$rotate,[bool]$slide=$false) {
    $shaft=Cylinder $x $y $z0 $z1 $shaftR
    Part $shaft ($id+'_SHAFT') '紧固件轴杆名义包络' 'FASTENER' 'MOUNT_ENVELOPE' $moveZ $rotate '紧固件外形近似' 0 $slide
    if($head1 -gt $head0) {
        $head=Cylinder $x $y $head0 $head1 $headR
        Part $head ($id+'_HEAD') '紧固件头部名义包络' 'FASTENER_HEAD' 'MOUNT_ENVELOPE' $moveZ $rotate '紧固件外形近似' 0 $slide
    }
    if($nut1 -gt $nut0) {
        $nut=Ring $x $y $nut0 $nut1 $nutR ($shaftR+0.1)
        Part $nut ($id+'_NUT') '螺母名义包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $moveZ $rotate '圆形螺母包络；实际六角及工具待核' 0 $slide
    }
}
foreach($sign in @(-1,1)) {
    $p=RotateXY (18*$sign) 202.5
    $x=$screw[0]+$p[0]; $y=$screw[1]+$p[1]
    AddFastener ('KFL_FIX_'+$sign) $x $y 231 276 2.0 276 278.5 4.0 232.8 236 4.1 $false $false
    $washer=Ring $x $y 275 276 4.5 2.1
    Part $washer ('KFL_FIX_'+$sign+'_WASHER') '顶板上 M4 垫圈' 'FASTENER_WASHER' 'MOUNT_ENVELOPE' $false $false 'M4固定件与顶板实际尺寸待核'
}
foreach($limit in @(@{id='LOW';ring=31;switch=33},@{id='HIGH';ring=192;switch=184})) {
    $p=LocalPoint 149 2 $limitAngle
    $body=CrossCylinder $p[0] $p[1] ($limit.ring+2.5) 1.5 25 $limitAngle
    Part $body ('LIMIT_CLAMP_'+$limit.id+'_SHAFT') 'M3×25 抱箍螺钉包络' 'FASTENER' 'MOUNT_ENVELOPE' $false $false '螺钉端部、扳手可达性和防滑待测'
    $p=LocalPoint 149 -11.75 $limitAngle
    $body=CrossCylinder $p[0] $p[1] ($limit.ring+2.5) 2.75 2.5 $limitAngle
    Part $body ('LIMIT_CLAMP_'+$limit.id+'_HEAD') 'M3 抱箍螺钉头' 'FASTENER_HEAD' 'MOUNT_ENVELOPE' $false $false '近似'
    $body=CrossRing 149 11.7 ($limit.ring+2.5) 3.2 1.6 2.4 $limitAngle
    Part $body ('LIMIT_CLAMP_'+$limit.id+'_NUT') 'M3 六角螺母圆形保守包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $false $false '外形与工具待实测'
    foreach($offset in @(3.15,9.65)) {
        $z=$limit.switch+$offset
        $p=LocalPoint 156 3.1 $limitAngle
        $body=CrossCylinder $p[0] $p[1] $z 1.0 12 $limitAngle
        Part $body ('LIMIT_FIX_'+$limit.id+'_'+$offset+'_SHAFT') 'M2×12 开关螺钉' 'FASTENER' 'MOUNT_ENVELOPE' $false $false '开关实际孔位待核'
        $p=LocalPoint 156 -3.65 $limitAngle
        $body=CrossCylinder $p[0] $p[1] $z 2.0 1.5 $limitAngle
        Part $body ('LIMIT_FIX_'+$limit.id+'_'+$offset+'_HEAD') 'M2 螺钉头' 'FASTENER_HEAD' 'MOUNT_ENVELOPE' $false $false '近似'
        $body=CrossRing 156 6.8 $z 2.35 1.1 1.6 $limitAngle
        Part $body ('LIMIT_FIX_'+$limit.id+'_'+$offset+'_NUT') 'M2 六角螺母包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $false $false '近似'
    }
}
foreach($u in @(-56,56)) { foreach($w in @(-26.5,28.5)) {
    AddFastener ('STRIP_FIX_'+$u+'_'+$w) $u $w ($zLift-14) ($zLift-6) 1.25 ($zLift-16) ($zLift-14) 2.25 0 0 0 $true $true
} }
foreach($u in @(-81.85,-75.35,75.35,81.85)) {
    AddFastener ('FORK_LIMIT_BASE_'+$u) $u 22 ($zLift-14) ($zLift-9) 1.0 ($zLift-15.5) ($zLift-14) 2.0 0 0 0 $true $true
}
foreach($u in @(-29,29)) { foreach($v in @(-29,29)) {
    AddFastener ('BLOW_'+$u+'_'+$v) $u $v ($zLift-29.4) ($zLift-21.3) 1.5 ($zLift-21.3) ($zLift-19.3) 2.75 ($zLift-29.4) ($zLift-27) 3.2 $true $false
    $a=20*[Math]::PI/180
    $x=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
    $y=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
    AddFastener ('BUP_'+$u+'_'+$v) $x $y ($zLift-17.1) ($zLift-12.8) 1.5 ($zLift-12.8) ($zLift-11.1) 3.0 ($zLift-17.1) ($zLift-14.7) 3.2 $true $true
} }
foreach($v in @(-8,8)) {
    # M2.5 低头高1.6，沉孔深1.8；14 mm 轴杆端部略伸出螺母。
    AddFastener ('FLANGE_SCREW_'+$v) 0 $v ($zLift-26.8) ($zLift-12.8) 1.25 ($zLift-12.8) ($zLift-11.2) 2.25 0 0 0 $true $true
    # M2.5 六角螺母按宽5.9×径向5.1的保守包络；平面朝轴套。
    $nut=NewSquareRing 0 $v ($zLift-26.2) ($zLift-24.2) 5.9 5.1 1.35 0
    Part $nut ('FLANGE_SCREW_'+$v+'_NUT') 'M2.5 六角螺母保守外包络' 'FASTENER_NUT' 'MOUNT_ENVELOPE' $true $true '须让平面朝向轴套，尺寸实配'
}
foreach($x in @(-15.5,15.5)) { foreach($y in @(-15.5,15.5)) {
    AddFastener ('ROT_MOUNT_'+$x+'_'+$y) $x $y ($zLift-42) ($zLift-25.2) 1.5 ($zLift-25.2) ($zLift-22.2) 2.75 0 0 0 $true $false
    AddFastener ('LIFT_MOUNT_'+$x+'_'+$y) ($screw[0]+$x) ($screw[1]+$y) 40 44 1.5 44 46.5 2.75 0 0 0 $false $false
} }
foreach($x in @(-30,30)) { foreach($y in @(-15.5,15.5)) {
    # M4×12 的轴杆从头部承压面 Z=-3.5 延伸到 Z=8.5；螺母以上仍有 1.3 mm。
    AddFastener ('LIFT_BRACKET_FOOT_'+$x+'_'+$y) ($screw[0]+$x) ($screw[1]+$y) -3.5 8.5 2.0 -6 -3.5 4.0 4 7.2 4.1 $false $false
} }
foreach($angle in @(22.5,112.5,202.5)) { foreach($radius in @(44,52)) {
    $p=RotateXY $radius $angle
    AddFastener ('ARM_MOUNT_'+$angle+'_'+$radius) $p[0] $p[1] ($zLift-44.4) ($zLift-22) 1.5 ($zLift-22) ($zLift-19.5) 2.75 ($zLift-44.4) ($zLift-42) 3.2 $true $false
} }
foreach($angle in @(112.5,202.5)) { foreach($sign in @(-1,1)) {
    $d=RotateXY (8*$sign) $angle
    AddFastener ('NUT_MOUNT_'+$angle+'_'+$sign) ($screw[0]+$d[0]) ($screw[1]+$d[1]) ($zLift+5) ($zLift+18) 1.5 ($zLift+18) ($zLift+20.5) 2.75 0 0 0 $true $false
} }
foreach($dx in @(-11.5,11.5)) { foreach($dy in @(-11.5,11.5)) {
    if($dx -eq 11.5 -and $dy -eq 11.5) {continue}
    AddFastener ('TRANSFER_MOUNT_'+$dx+'_'+$dy) ($transferX+$dx) ($transferY+$dy) ($zLift-14) ($zLift+6) 1.2 ($zLift-16.4) ($zLift-14) 2.25 0 0 0 $true $true
} }
AddFastener 'IDLER_MOUNT' $idlerX $transferY ($zLift-16.4) ($zLift-3.5) 1.5 ($zLift-3.5) ($zLift-1) 2.75 ($zLift-16.4) ($zLift-14) 3.2 $true $true
foreach($y in @(-6,6)) {
    AddFastener ('SLIDER_MOUNT_'+$y) $sliderCenter $y ($zLift-3) ($zLift-1) 0.95 ($zLift-1) ($zLift+0.5) 1.7 0 0 0 $true $true $true
}
Write-Host ('MOVING_COMPONENTS count='+$parts.Count)

# 已停放的托盘和车：第一层 E 位由中央托盘占用，DOCK 不放；二层 DOCK 留空。
foreach($level in @(@{id='L1';top=100;angles=@(45,90,135,180,225,315)},
                     @{id='L2';top=190;angles=@(0,45,90,135,180,225,315)})) {
    foreach($angle in $level.angles) {
        $body=NewTray 100 $level.top $angle
        Part $body ("TRAY_"+$level.id+"_"+$angle) ("停放托盘 "+$level.id+" / "+$angle+"度") 'PARKED_TRAY' 'TRAY' $false $false '内端r100；定位销r107，距内端7'
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
# 检查真实实体内的背壁/挡边材料；缩进 0.01 mm 避免面重合数值误差。
$clampChecks=New-Object 'System.Collections.Generic.List[object]'
foreach($test in @(
    @{name='2mm背壁'; box=@(($x0+0.01),($x1-0.01),-18.99,-17.01,($zLift-9.49),($zLift-3.51)); note='在 6×2×6 mm 背壁内部取样'},
    @{name='1mm挡边'; box=@(($x0+0.01),($x1-0.01),-18.99,-14.11,($zLift-10.49),($zLift-9.51)); note='在 6×4.9×1 mm 底挡边内部取样'}
)) {
    $b=$test.box; $materialProbe=Box $b[0] $b[1] $b[2] $b[3] $b[4] $b[5]
    $expected=[double]$materialProbe.Volume; $hit=$false
    $common=$materialProbe.CheckInterference($partById['TRANSFER_FORK'].solid,$true,[ref]$hit)
    $actual=if($hit -and $null -ne $common) {[double]$common.Volume} else {0.0}
    if($null -ne $common) { $common.Delete() }; $materialProbe.Delete()
    if([Math]::Abs($actual-$expected) -gt 0.001) { throw ($test.name+' 实体材料不足；体积 '+$actual+' / '+$expected) }
    $clampChecks.Add([pscustomobject]@{检查=$test.name;结果='通过';说明=$test.note})
}
# 将每个假设带轮外形沿相对拨叉的全部 -2..140 mm 行程扫掠；
# 径向及轴向均扩张 0.99 mm 后，检查整件拨叉是否与扫掠体相交。
foreach($wheel in @(@{name='电机轮连续间隙';x=$transferX},@{name='惰轮连续间隙';x=$idlerX})) {
    $radius=6.5+0.99; $lo=$wheel.x-140; $hi=$wheel.x+2
    $swept=Box $lo $hi ($transferY-$radius) ($transferY+$radius) ($zLift-10.49) ($zLift-2.51)
    $end=Cylinder $lo $transferY ($zLift-10.49) ($zLift-2.51) $radius; $swept.Boolean(0,$end)
    $end=Cylinder $hi $transferY ($zLift-10.49) ($zLift-2.51) $radius; $swept.Boolean(0,$end)
    $hit=$false; $null=$swept.CheckInterference($partById['TRANSFER_FORK'].solid,$false,[ref]$hit)
    $swept.Delete()
    if($hit) { throw ($wheel.name+' 小于 0.99 mm 或存在碰撞') }
    $clampChecks.Add([pscustomobject]@{检查=$wheel.name;结果='通过';说明='假设轮径13、轮宽6；全行程径向及轴向扩张0.99 mm的包络与拨叉不相交'})
}
$clampChecks | Export-Csv -LiteralPath (Join-Path $OutputDir '夹带结构_连续包络检查.csv') -NoTypeInformation -Encoding UTF8
Write-Host 'CLAMP_SOLID_AND_CONTINUOUS_SWEEP passed margin=0.99mm'
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
    FastenerProbe ('KFL_'+$sign) '顶部轴承座及金属支承柱' ($screw[0]+$offset[0]) ($screw[1]+$offset[1]) 236 275 1.9 @('ROOF','KFL_TOP',('KFL_SPACER_'+$sign)) '孔距36；KFL厚度、孔径及支承面需实测。'
}
$a=20*[Math]::PI/180
foreach($u in @(-29,29)) { foreach($v in @(-29,29)) {
    $name=('B_'+$u+'_'+$v)
    FastenerProbe ($name+'_LOWER') '转盘下板与升降中心盘' $u $v ($zLift-27) ($zLift-21.3) 1.9 @('LIFT_DISC','BEARING_BOTTOM') '孔距58；未计紧固件头部、垫圈及装拆。'
    $x=$u*[Math]::Cos($a)-$v*[Math]::Sin($a)
    $y=$u*[Math]::Sin($a)+$v*[Math]::Cos($a)
    FastenerProbe ($name+'_UPPER') '转盘上板与P03E' $x $y ($zLift-14.7) ($zLift-11) 1.9 @('BEARING_TOP','TRANSFER_PLATE') '孔组旋转20°；未计紧固件头部、垫圈及装拆。'
} }
foreach($v in @(-8,8)) {
    FastenerProbe ('FLANGE_'+$v) '法兰、隔套与P03E' 0 $v ($zLift-24.2) ($zLift-11) 1.25 @('FLANGE_DISC','FLANGE_SPACER','TRANSFER_PLATE') '候选 M2.5；孔距16；紧固件和安装顺序待复核。'
}
foreach($x in @(-15.5,15.5)) { foreach($y in @(-15.5,15.5)) {
    FastenerProbe ('ROT_MOUNT_'+$x+'_'+$y) '旋转电机安装柱与中心盘' $x $y ($zLift-42) ($zLift-22) 1.5 @('LIFT_DISC',('ROT_SPACER_'+$x+'_'+$y)) '孔距31；电机攻丝深度及沉孔头部待测。'
    FastenerProbe ('LIFT_MOUNT_'+$x+'_'+$y) '升降电机与顶部压板' ($screw[0]+$x) ($screw[1]+$y) 40 44 1.5 @('LIFT_MOTOR_BRACKET') '孔距31；电机攻丝深度待测。'
} }
foreach($x in @(-30,30)) { foreach($y in @(-15.5,15.5)) {
    FastenerProbe ('LIFT_BRACKET_FOOT_'+$x+'_'+$y) '升降支架与底板' ($screw[0]+$x) ($screw[1]+$y) -6 4 1.9 @('BASE','LIFT_MOTOR_BRACKET') '候选 M4；底板下表面沉孔。'
} }
foreach($dx in @(-11.5,11.5)) { foreach($dy in @(-11.5,11.5)) {
    if($dx -eq 11.5 -and $dy -eq 11.5) {continue}
    FastenerProbe ('TRANSFER_MOUNT_'+$dx+'_'+$dy) '28电机安装柱与P03E' ($transferX+$dx) ($transferY+$dy) ($zLift-11) ($zLift+6) 1.2 @('TRANSFER_PLATE',('TRANSFER_SPACER_'+$dx+'_'+$dy)) '孔距23；三点M2.5固定，孔深和强度需实测。'
} }
foreach($u in @(-56,56)) { foreach($w in @(-26.5,28.5)) {
    FastenerProbe ('STRIP_FIX_'+$u+'_'+$w) '支撑铝条与P03E' $u $w ($zLift-14) ($zLift-6) 1.2 @('TRANSFER_PLATE',('STRIP_'+$w)) '仅核对名义孔道，螺纹深度和条材强度待测。'
} }
foreach($u in @(-81.85,-75.35,75.35,81.85)) {
    $end=if($u -lt 0) {'IN'} else {'OUT'}
    FastenerProbe ('FORK_LIMIT_BASE_'+$u) '拨叉限位座与P03E' $u 22 ($zLift-14) ($zLift-9) 0.95 @('TRANSFER_PLATE',('FORK_LIMIT_BRACKET_'+$end)) 'M2紧固孔候选，底脚强度和装配待核。'
}
$mountRows | Export-Csv -LiteralPath (Join-Path $OutputDir '候选安装孔_名义贯通检查.csv') -NoTypeInformation -Encoding UTF8
Write-Host ('MOUNT_PROBES total='+$mountRows.Count+' blocked_or_error='+@($mountRows | Where-Object { $_.结果 -ne '名义贯通' }).Count)

# 单独移动复制实体，确认止挡接触边界；不把止挡强度或开关动作当作已验证。
$stopChecks=New-Object 'System.Collections.Generic.List[object]'
foreach($stop in @(
    @{id='LOW'; moving='LM8LUU_1'; bracket='LIMIT_BRACKET_LOW'; before=86.1; after=85.9},
    @{id='HIGH'; moving='LIFT_ARM_22.5'; bracket='LIMIT_BRACKET_HIGH'; before=193.9; after=194.1}
)) {
    $hits=@()
    foreach($height in @($stop.before,$stop.after)) {
        $clone=$partById[$stop.moving].solid.Copy()
        try {
            MoveBy $clone 0 0 ($height-100)
            $hit=$false
            $null=$clone.CheckInterference($partById[$stop.bracket].solid,$false,[ref]$hit)
            $hits+=@([bool]$hit)
        } finally { $clone.Delete() }
    }
    $stopChecks.Add([pscustomobject]@{位置=$stop.id; 临界前高度_mm=$stop.before; 临界前相交=$hits[0];
        临界后高度_mm=$stop.after; 临界后相交=$hits[1];
        说明='仅验证刚体几何接触边界；抱箍防滑、开关过行程和强度必须实测'})
    if($hits[0] -or -not $hits[1]) { throw ('限位止挡几何边界异常：'+$stop.id) }
}
$stopChecks | Export-Csv -LiteralPath (Join-Path $OutputDir '限位_机械止挡检测.csv') -NoTypeInformation -Encoding UTF8
Write-Host 'STOP_CONTACT_GEOMETRY low=86 high=194 passed'
$forkStopChecks=New-Object 'System.Collections.Generic.List[object]'
foreach($stop in @(
    @{id='IN'; bracket='FORK_LIMIT_BRACKET_IN'; before=-1.9; after=-2.1},
    @{id='OUT'; bracket='FORK_LIMIT_BRACKET_OUT'; before=139.9; after=140.1}
)) {
    $hits=@()
    foreach($stroke in @($stop.before,$stop.after)) {
        $clone=$partById['TRANSFER_FORK'].solid.Copy()
        try {
            MoveBy $clone $stroke 0 0
            $hit=$false
            $null=$clone.CheckInterference($partById[$stop.bracket].solid,$false,[ref]$hit)
            $hits+=@([bool]$hit)
        } finally { $clone.Delete() }
    }
    $forkStopChecks.Add([pscustomobject]@{位置=$stop.id; 临界前行程_mm=$stop.before; 临界前相交=$hits[0];
        临界后行程_mm=$stop.after; 临界后相交=$hits[1]; 说明='刚体几何边界，打印止挡和轨道强度未验证'})
    if($hits[0] -or -not $hits[1]) { throw ('拨叉止挡几何边界异常：'+$stop.id) }
}
$forkStopChecks | Export-Csv -LiteralPath (Join-Path $OutputDir '拨叉_机械止挡检测.csv') -NoTypeInformation -Encoding UTF8
Write-Host 'FORK_STOP_CONTACT_GEOMETRY in=-2 out=140 passed'

# 在添加红色干涉体之前导出各个真实三维实体；SAT 不是 SolidWorks 原生约束装配。
$ss=$doc.SelectionSets.Add('garage_assembly_export')
$ss.Select(5)
if ($ss.Count -ne $parts.Count) {
    throw ('模型空间中实体数 '+$ss.Count+' 与清单 '+$parts.Count+' 不一致，停止导出')
}
$doc.Export((Join-Path $OutputDir '车库_两层三维实体_v7'),'SAT',$ss)
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
function ClashRow($pose,[double]$height,[double]$angle,$a,$b,$volume,$stroke='') {
    return [pscustomobject]@{工况=$pose; 升降高度_mm=$height; 旋转角_deg=$angle; 推拉行程_mm=$stroke;
        零件A=$a.id; 名称A=$a.label; 零件B=$b.id; 名称B=$b.label;
        相交体积_mm3=$volume; 判读=(Classification $a $b)}
}
function ExportClashes($rows,[string]$path) {
    if($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 }
    else { '"工况","升降高度_mm","旋转角_deg","推拉行程_mm","零件A","名称A","零件B","名称B","相交体积_mm3","判读"' | Set-Content -LiteralPath $path -Encoding UTF8 }
}

$initialBounds=CollectBounds
$manifest=foreach($p in $parts) {
    $b=$initialBounds[$p.id]
    [pscustomobject]@{编号=$p.id; 名称=$p.label; 类别=$p.role; 图层=$p.layer;
        句柄=$p.solid.Handle; 随升降=$p.moveZ; 随转盘=$p.rotate; 随托盘推拉=$p.slide; 尺寸依据=$p.confidence;
        体积_mm3=[Math]::Round([double]$p.solid.Volume,4);
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
ExportClashes $baselineRows (Join-Path $OutputDir '基准工况_实体相交.csv')
Write-Host ('BASELINE candidates='+$baseCandidates+' overlaps='+$baselineRows.Count+' errors='+$errors.Count)

# 离散状态下只扫描相对位置发生变化的成对实体；同组连接处已在基准状态检查。
$poses=New-Object 'System.Collections.Generic.List[object]'
$heights=@(86,88,90,92,182,192,194)
for($height=95;$height -le 190;$height+=5) { $heights+=$height }
if($Fast) { $heights=@(86,88,90,92,100,130,190,192,194) }
foreach($height in @($heights | Sort-Object -Unique)) {
    $poses.Add([pscustomobject]@{height=$height;angle=0})
}
foreach($height in @(86,92,130,190,192,194)) {
    $step=if($Fast) {45} else {15}
    for($angle=$step;$angle -le 315;$angle+=$step) {
        $poses.Add([pscustomobject]@{height=$height;angle=$angle})
    }
}
$sampleRows=New-Object 'System.Collections.Generic.List[object]'
$limitContactRows=New-Object 'System.Collections.Generic.List[object]'
$poseSummary=New-Object 'System.Collections.Generic.List[object]'
function IsExpectedLimitContact($a,$b,[double]$height) {
    $pair=PairKey $a.id $b.id
    return (($height -lt 90 -and $pair -eq (PairKey 'LIMIT_LEVER_LOW' 'LM8LUU_1')) -or
            ($height -gt 192 -and $pair -eq (PairKey 'LIMIT_LEVER_HIGH' 'LIFT_ARM_22.5')))
}
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
    $candidates=0; $overlaps=0; $contacts=0; $errorsBefore=$errors.Count
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
                    if(IsExpectedLimitContact $a $b $currentZ) {
                        $contacts++
                        $limitContactRows.Add((ClashRow '限位接触_摇臂未变形' $currentZ $currentAngle $a $b ''))
                    } else {
                        $overlaps++
                        $sampleRows.Add((ClashRow '采样' $currentZ $currentAngle $a $b ''))
                    }
                }
            } catch {
                $errors.Add([pscustomobject]@{工况=('Z'+$currentZ+' / '+$currentAngle+'deg');
                    零件A=$a.id; 零件B=$b.id; 错误=$_.Exception.Message})
            }
        }
    }
    $poseSummary.Add([pscustomobject]@{升降高度_mm=$currentZ; 旋转角_deg=$currentAngle;
        候选实体对=$candidates; 相交实体对=$overlaps; 预期限位接触=$contacts; 检查错误=($errors.Count-$errorsBefore)})
    Write-Host ('POSE z='+$currentZ+' angle='+$currentAngle+' candidates='+$candidates+' overlaps='+$overlaps+' contacts='+$contacts+' errors='+($errors.Count-$errorsBefore))
}
# 恢复到一层、0 度，以便图纸、清单和冲突高亮对应同一工况。
foreach($p in $parts) {
    if ($p.rotate -and [Math]::Abs($currentAngle) -gt 0.000001) { Spin $p.solid (-$currentAngle) }
    if ($p.moveZ -and [Math]::Abs($currentZ-100) -gt 0.000001) { MoveBy $p.solid 0 0 (100-$currentZ) }
}
# 把推拉组件从工作端点继续移动到刚性止挡，专门检查越程与带轮、支架的碰撞。
$forkOverrunRows=New-Object 'System.Collections.Generic.List[object]'
$forkOverrunContacts=New-Object 'System.Collections.Generic.List[object]'
$forkOverrunSummary=New-Object 'System.Collections.Generic.List[object]'
$lastOverrun=0.0
foreach($stroke in @(-2,-1.5,-1,-0.5,0,138,138.5,139,139.5,140)) {
    $delta=$stroke-$lastOverrun
    foreach($p in $parts) { if($p.slide -and $delta -ne 0) { MoveBy $p.solid $delta 0 0 } }
    $lastOverrun=[double]$stroke
    $bounds=CollectBounds; $candidates=0; $hits=0; $contacts=0; $errorsBefore=$errors.Count
    for($i=0;$i -lt $parts.Count;$i++) { for($j=$i+1;$j -lt $parts.Count;$j++) {
        $a=$parts[$i]; $b=$parts[$j]
        if($a.slide -eq $b.slide -or -not (BoxesOverlap $bounds[$a.id] $bounds[$b.id])) { continue }
        $candidates++
        try {
            $hit=$false
            $null=$a.solid.CheckInterference($b.solid,$false,[ref]$hit)
            if($hit) {
                $key=PairKey $a.id $b.id
                $expected=(($stroke -lt -0.5 -and $key -eq (PairKey 'FORK_LIMIT_LEVER_IN' 'TRANSFER_SLIDER')) -or
                           ($stroke -gt 138.5 -and $key -eq (PairKey 'FORK_LIMIT_LEVER_OUT' 'TRANSFER_SLIDER')))
                if($expected) { $contacts++; $forkOverrunContacts.Add((ClashRow '拨叉越程_预期摇臂接触' 100 0 $a $b '' $stroke)) }
                else { $hits++; $forkOverrunRows.Add((ClashRow '拨叉越程' 100 0 $a $b '' $stroke)) }
            }
        } catch {
            $errors.Add([pscustomobject]@{工况=('拨叉越程 '+$stroke+' mm');零件A=$a.id;零件B=$b.id;错误=$_.Exception.Message})
        }
    } }
    $forkOverrunSummary.Add([pscustomobject]@{工况='载盘'; 行程_mm=$stroke; 候选实体对=$candidates; 相交实体对=$hits; 预期限位接触=$contacts; 检查错误=($errors.Count-$errorsBefore)})
    Write-Host ('FORK_OVERRUN stroke='+$stroke+' overlaps='+$hits+' contacts='+$contacts)
}
foreach($p in $parts) { if($p.slide) { MoveBy $p.solid (-$lastOverrun) 0 0 } }
# 一层 E 位的载盘推拉：固定其余车位，滑块、叉、中央托盘及载车包络一起沿 +X 移动 138 mm。
$transferRows=New-Object 'System.Collections.Generic.List[object]'
$transferSummary=New-Object 'System.Collections.Generic.List[object]'
$lastTravel=0.0
$travels=if($Fast) {@(0,2,4,6,8,10,30,68,108,128,130,132,134,136,138)} else {@(0..69 | ForEach-Object {$_*2})}
foreach($travel in $travels) {
    $delta=$travel-$lastTravel
    foreach($p in $parts) { if($p.slide -and $delta -ne 0) { MoveBy $p.solid $delta 0 0 } }
    $lastTravel=[double]$travel
    $bounds=CollectBounds; $candidates=0; $hits=0; $errorsBefore=$errors.Count
    for($i=0;$i -lt $parts.Count;$i++) { for($j=$i+1;$j -lt $parts.Count;$j++) {
        $a=$parts[$i]; $b=$parts[$j]
        if($a.slide -eq $b.slide) { continue }
        if(-not (BoxesOverlap $bounds[$a.id] $bounds[$b.id])) { continue }
        $candidates++
        try {
            $hit=$false
            $null=$a.solid.CheckInterference($b.solid,$false,[ref]$hit)
            if($hit) { $hits++; $transferRows.Add((ClashRow '一层载盘推拉' 100 0 $a $b '' $travel)) }
        } catch {
            $errors.Add([pscustomobject]@{工况=('载盘推拉 '+$travel+' mm');零件A=$a.id;零件B=$b.id;错误=$_.Exception.Message})
        }
    } }
    $transferSummary.Add([pscustomobject]@{工况='一层载盘推拉'; 行程_mm=$travel; 候选实体对=$candidates; 相交实体对=$hits; 检查错误=($errors.Count-$errorsBefore)})
    if($travel % 20 -eq 0 -or $travel -eq 138) { Write-Host ('TRANSFER loaded='+$travel+' candidates='+$candidates+' overlaps='+$hits) }
}
foreach($p in $parts) { if($p.slide) { MoveBy $p.solid (-$lastTravel) 0 0 } }

# 放好托盘后下降 8 mm：托盘留在车位，空叉沿相同行程推拉。
$parkedIds=@('CENTER_TRAY','CENTER_PIN','CENTER_CAR')
$forkIds=@($parts | Where-Object { $_.slide -and $_.id -notin $parkedIds } | ForEach-Object { $_.id })
foreach($p in $parts) {
    if($p.id -in $parkedIds) { MoveBy $p.solid 138 0 0 }
    elseif($p.moveZ) { MoveBy $p.solid 0 0 -8 }
}
$lastTravel=0.0
foreach($travel in $travels) {
    $delta=$travel-$lastTravel
    foreach($p in $parts) { if($p.id -in $forkIds -and $delta -ne 0) { MoveBy $p.solid $delta 0 0 } }
    $lastTravel=[double]$travel
    $bounds=CollectBounds; $candidates=0; $hits=0; $errorsBefore=$errors.Count
    for($i=0;$i -lt $parts.Count;$i++) { for($j=$i+1;$j -lt $parts.Count;$j++) {
        $a=$parts[$i]; $b=$parts[$j]
        $aFork=$a.id -in $forkIds; $bFork=$b.id -in $forkIds
        $aParked=$a.id -in $parkedIds; $bParked=$b.id -in $parkedIds
        $changed=($aFork -ne $bFork)
        if($travel -eq 0 -and ($aParked -ne $bParked)) { $changed=$true }
        if(-not $changed) { continue }
        if(-not (BoxesOverlap $bounds[$a.id] $bounds[$b.id])) { continue }
        $candidates++
        try {
            $hit=$false
            $null=$a.solid.CheckInterference($b.solid,$false,[ref]$hit)
            if($hit) { $hits++; $transferRows.Add((ClashRow '一层空叉推拉' 92 0 $a $b '' $travel)) }
        } catch {
            $errors.Add([pscustomobject]@{工况=('空叉推拉 '+$travel+' mm');零件A=$a.id;零件B=$b.id;错误=$_.Exception.Message})
        }
    } }
    $transferSummary.Add([pscustomobject]@{工况='一层空叉推拉'; 行程_mm=$travel; 候选实体对=$candidates; 相交实体对=$hits; 检查错误=($errors.Count-$errorsBefore)})
    if($travel % 20 -eq 0 -or $travel -eq 138) { Write-Host ('TRANSFER empty='+$travel+' candidates='+$candidates+' overlaps='+$hits) }
}
# 托盘留在车位时也单独检查拨叉的两端越程，不能只用载盘结果代替。
foreach($stroke in @(-2,-1.5,-1,-0.5,0,138,138.5,139,139.5,140)) {
    $delta=$stroke-$lastTravel
    foreach($p in $parts) { if($p.id -in $forkIds -and $delta -ne 0) { MoveBy $p.solid $delta 0 0 } }
    $lastTravel=[double]$stroke
    $bounds=CollectBounds; $candidates=0; $hits=0; $contacts=0; $errorsBefore=$errors.Count
    for($i=0;$i -lt $parts.Count;$i++) { for($j=$i+1;$j -lt $parts.Count;$j++) {
        $a=$parts[$i]; $b=$parts[$j]
        if(($a.id -in $forkIds) -eq ($b.id -in $forkIds)) { continue }
        if(-not (BoxesOverlap $bounds[$a.id] $bounds[$b.id])) { continue }
        $candidates++
        try {
            $hit=$false
            $null=$a.solid.CheckInterference($b.solid,$false,[ref]$hit)
            if($hit) {
                $key=PairKey $a.id $b.id
                $expected=(($stroke -lt -0.5 -and $key -eq (PairKey 'FORK_LIMIT_LEVER_IN' 'TRANSFER_SLIDER')) -or
                           ($stroke -gt 138.5 -and $key -eq (PairKey 'FORK_LIMIT_LEVER_OUT' 'TRANSFER_SLIDER')))
                if($expected) { $contacts++; $forkOverrunContacts.Add((ClashRow '空叉越程_预期摇臂接触' 92 0 $a $b '' $stroke)) }
                else { $hits++; $forkOverrunRows.Add((ClashRow '空叉越程' 92 0 $a $b '' $stroke)) }
            }
        } catch {
            $errors.Add([pscustomobject]@{工况=('空叉越程 '+$stroke+' mm');零件A=$a.id;零件B=$b.id;错误=$_.Exception.Message})
        }
    } }
    $forkOverrunSummary.Add([pscustomobject]@{工况='空叉'; 行程_mm=$stroke; 候选实体对=$candidates; 相交实体对=$hits; 预期限位接触=$contacts; 检查错误=($errors.Count-$errorsBefore)})
    Write-Host ('FORK_OVERRUN_EMPTY stroke='+$stroke+' overlaps='+$hits+' contacts='+$contacts)
}
foreach($p in $parts) {
    if($p.id -in $forkIds) { MoveBy $p.solid (-$lastTravel) 0 0 }
    if($p.id -in $parkedIds) { MoveBy $p.solid -138 0 0 }
    elseif($p.moveZ) { MoveBy $p.solid 0 0 8 }
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

# 按装配中同一个实体复制导出试配 STL；样件孔径、方向和承载必须实测。
$printDir=Join-Path $OutputDir '打印件_STL_待实配'
$null=New-Item -ItemType Directory -Path $printDir
$printParts=@(
    @{id='LIFT_ARM_22.5';angle=22.5;file='01_导杆支撑臂_打印2件.stl'},
    @{id='LIFT_ARM_112.5';angle=112.5;file='02_丝杆支撑臂_打印1件.stl'},
    @{id='LIFT_MOTOR_BRACKET';angle=0;file='03_升降电机跨式支架_打印1件.stl'},
    @{id='ROT_SPACER_-15.5_-15.5';angle=0;file='04_旋转电机隔柱15_打印4件.stl'},
    @{id='TRANSFER_SPACER_-11.5_-11.5';angle=0;file='06_转运电机隔柱17_打印3件.stl'},
    @{id='KFL_SPACER_-1';angle=0;file='07_KFL支承柱22_仅试配非承载.stl'},
    @{id='FLANGE_SPACER';angle=0;file='08_转盘法兰隔套8_打印1件.stl'},
    @{id='TRANSFER_FORK';angle=0;file='09_拨叉及双螺钉皮带座_试配.stl'},
    @{id='LIMIT_BRACKET_LOW';angle=22.5;file='10_下限位调节座_试配.stl'},
    @{id='LIMIT_BRACKET_HIGH';angle=22.5;file='11_上限位调节座_试配.stl'},
    @{id='FORK_LIMIT_BRACKET_IN';angle=0;file='12_拨叉收回限位座_试配.stl'},
    @{id='FORK_LIMIT_BRACKET_OUT';angle=0;file='13_拨叉伸出限位座_试配.stl'}
)
$oldFileDia=$doc.GetVariable('FILEDIA')
$oldFacet=$doc.GetVariable('FACETRES')
try {
    $doc.SetVariable('FILEDIA',[int16]0)
    $doc.SetVariable('FACETRES',[double]6)
    foreach($item in $printParts) {
        $clone=$partById[$item.id].solid.Copy()
        try {
            if($item.angle -ne 0) { Spin $clone (-[double]$item.angle) }
            $bb=Bounds $clone
            MoveBy $clone (5-$bb[0][0]) (5-$bb[0][1]) (5-$bb[0][2])
            $tempStl=Join-Path $env:TEMP ('garage_v4_'+[Guid]::NewGuid().ToString('N')+'.stl')
            $fn=$tempStl.Replace('\','/')
            $cmd='(progn (command "_.STLOUT" (handent "'+$clone.Handle+'") "" "_Y" "'+$fn+'") (princ))' + "`n"
            $doc.SendCommand($cmd)
            if(-not (Test-Path -LiteralPath $tempStl)) { throw ('STL 未生成：'+$item.id) }
            Copy-Item -LiteralPath $tempStl -Destination (Join-Path $printDir $item.file)
            Write-Host ('PRINT_STL '+$item.file)
        } finally { $clone.Delete() }
    }
} finally {
    $doc.SetVariable('FILEDIA',$oldFileDia)
    $doc.SetVariable('FACETRES',$oldFacet)
}
ExportClashes $sampleRows (Join-Path $OutputDir '运动采样_实体相交.csv')
ExportClashes $limitContactRows (Join-Path $OutputDir '限位_预期摇臂接触.csv')
ExportClashes $forkOverrunRows (Join-Path $OutputDir '拨叉_越程实体相交.csv')
ExportClashes $forkOverrunContacts (Join-Path $OutputDir '拨叉_预期摇臂接触.csv')
$forkOverrunSummary | Export-Csv -LiteralPath (Join-Path $OutputDir '拨叉_越程覆盖情况.csv') -NoTypeInformation -Encoding UTF8
$poseSummary | Export-Csv -LiteralPath (Join-Path $OutputDir '运动采样_覆盖情况.csv') -NoTypeInformation -Encoding UTF8
ExportClashes $transferRows (Join-Path $OutputDir '托盘推拉_实体相交.csv')
$transferSummary | Export-Csv -LiteralPath (Join-Path $OutputDir '托盘推拉_覆盖情况.csv') -NoTypeInformation -Encoding UTF8
if ($errors.Count -gt 0) { $errors | Export-Csv -LiteralPath (Join-Path $OutputDir '干涉检查_错误.csv') -NoTypeInformation -Encoding UTF8 }

$vp=$doc.ActiveViewport
$vp.Direction=[double[]]@(1,-1,0.8)
$vp.Target=[double[]]@(0,0,135)
$vp.Center=[double[]]@(0,0)
$vp.Height=700.0
$doc.ActiveViewport=$vp
try { $doc.SendCommand("_.VSCURRENT`n_Conceptual`n") } catch { Write-Host ('VISUAL_STYLE_NOTE '+$_.Exception.Message) }
$doc.Regen(1)
if ($app.Visible) { $app.ZoomExtents() }
$dwgPath=Join-Path $OutputDir '车库_两层三维装配_v7.dwg'
$doc.SaveAs($dwgPath,64)
$summary=[pscustomobject]@{
    单位='mm'; 采样模式=($(if($Fast) {'快速试验'} else {'完整离散采样'})); 基准载盘高度_mm=100; 基准转角_deg=0; 实体数=$parts.Count;
    基准候选对=$baseCandidates; 基准相交对=$baselineRows.Count; 离散工况数=$poses.Count;
    采样相交记录数=$sampleRows.Count; 推拉工况数=$transferSummary.Count; 推拉相交记录数=$transferRows.Count; 检查错误数=$errors.Count;
    限位预期接触记录数=$limitContactRows.Count;
    拨叉越程工况数=$forkOverrunSummary.Count; 拨叉越程相交记录数=$forkOverrunRows.Count; 拨叉预期接触记录数=$forkOverrunContacts.Count;
    候选孔探针数=$mountRows.Count; 探针阻挡或错误数=@($mountRows | Where-Object { $_.结果 -ne '名义贯通' }).Count;
    恢复基准最大偏差_mm=$maxRestoreError;
    电机短轴_mm=24; 顶板厚_mm=5; 快照说明='一层中央载盘；各层其余车位有托盘和模型车包络'
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir '检查统计.json') -Encoding UTF8
$doc.Close($false)
if($NewInstance) { $app.Quit() }
Write-Host ('DONE dwg='+$dwgPath+' errors='+$errors.Count)
if($errors.Count -gt 0) { throw '存在实体检查错误，请查看干涉检查_错误.csv；检查结果不完整。' }
