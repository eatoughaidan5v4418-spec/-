<# 生成 v6 装配及新增部件的可复核 CAD 详图；尺寸仍需实配。 #>
param([Parameter(Mandatory=$true)][string]$OutputDir)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDetailFilter {
 [PreserveSig] int HandleInComingCall(int t, IntPtr c, int k, IntPtr i);
 [PreserveSig] int RetryRejectedCall(IntPtr c, int k, int r);
 [PreserveSig] int MessagePending(IntPtr c, int k, int t);
}
public class DetailFilter : IDetailFilter {
 [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IDetailFilter f, out IDetailFilter old);
 public static void Register() { IDetailFilter old; CoRegisterMessageFilter(new DetailFilter(),out old); }
 public int HandleInComingCall(int t, IntPtr c, int k, IntPtr i) { return 0; }
 public int RetryRejectedCall(IntPtr c, int k, int r) { return k<30000 ? 200 : -1; }
 public int MessagePending(IntPtr c, int k, int t) { return 2; }
}
'@
[DetailFilter]::Register()
$OutputDir=(Resolve-Path -LiteralPath $OutputDir).Path
$template=Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
$app=New-Object -ComObject 'AutoCAD.Application.25'
$app.Visible=$false
$doc=$null
function L([double]$x1,[double]$y1,[double]$x2,[double]$y2,[string]$layer='OUTLINE') {
 $e=$script:space.AddLine([double[]]@($x1,$y1,0),[double[]]@($x2,$y2,0)); $e.Layer=$layer
}
function Rect2D([double]$x,[double]$y,[double]$w,[double]$h,[string]$layer='OUTLINE') {
 L $x $y ($x+$w) $y $layer; L ($x+$w) $y ($x+$w) ($y+$h) $layer
 L ($x+$w) ($y+$h) $x ($y+$h) $layer; L $x ($y+$h) $x $y $layer
}
function T([string]$value,[double]$x,[double]$y,[double]$height=3,[string]$layer='NOTES') {
 $e=$script:space.AddText($value,[double[]]@($x,$y,0),$height); $e.StyleName='CN_NOTES'; $e.Layer=$layer
}
function C([double]$x,[double]$y,[double]$r,[string]$layer='OUTLINE') {
 $e=$script:space.AddCircle([double[]]@($x,$y,0),$r); $e.Layer=$layer
}
function Arc([double]$x,[double]$y,[double]$r,[double]$a,[double]$b,[string]$layer='OUTLINE') {
 $e=$script:space.AddArc([double[]]@($x,$y,0),$r,$a,$b); $e.Layer=$layer
}
function Dim([double]$x1,[double]$y1,[double]$x2,[double]$y2,[double]$x,[double]$y,[double]$angle,[double]$factor=1) {
 $e=$script:space.AddDimRotated([double[]]@($x1,$y1,0),[double[]]@($x2,$y2,0),[double[]]@($x,$y,0),$angle)
 $e.Layer='DIMENSIONS'; $e.TextHeight=3; $e.ArrowheadSize=2; $e.TextGap=0.7
 $e.PrimaryUnitsPrecision=2; $e.LinearScaleFactor=$factor; $e.Update()
}
function StartSheet([string]$title) {
 $script:doc=$app.Documents.Add($template); $script:space=$script:doc.ModelSpace
 $script:doc.SetVariable('INSUNITS',[int16]4)
 $style=$script:doc.TextStyles.Add('CN_NOTES'); $style.SetFont('Microsoft YaHei',$false,$false,134,34)
 foreach($v in @(@('OUTLINE',7),@('DIMENSIONS',3),@('NOTES',7),@('REFERENCE',1),@('CENTER',4))) {
  $layer=$script:doc.Layers.Add([string]$v[0]); $layer.Color=[int16]$v[1]
 }
 T $title 20 325 5
 T '单位 mm；放大示意；红线为待实配或近似件；确认前不可直接加工' 20 316 2.7 'REFERENCE'
}
function SaveSheet([string]$name) {
 $script:doc.Regen(1)
 $xmin=[double]::PositiveInfinity; $ymin=$xmin; $xmax=[double]::NegativeInfinity; $ymax=$xmax
 foreach($entity in $script:doc.ModelSpace) {
  try {
   $lo=$null; $hi=$null; $entity.GetBoundingBox([ref]$lo,[ref]$hi)
   $xmin=[Math]::Min($xmin,$lo[0]); $ymin=[Math]::Min($ymin,$lo[1])
   $xmax=[Math]::Max($xmax,$hi[0]); $ymax=[Math]::Max($ymax,$hi[1])
  } catch { }
 }
 if([double]::IsInfinity($xmin)) { throw '无法计算详图默认视图范围' }
 $vp=$script:doc.ActiveViewport
 $vp.Direction=[double[]]@(0,0,1); $vp.Target=[double[]]@(0,0,0)
 $height=1.2*[Math]::Max(($ymax-$ymin),(($xmax-$xmin)/1.3))
 $aspect=$vp.Width/$vp.Height
 $vp.Width=$height*$aspect; $vp.Height=$height
 $vp.Center=[double[]]@((($xmin+$xmax)/2),(($ymin+$ymax)/2))
 $script:doc.ActiveViewport=$vp
 foreach($ext in @('dxf','dwg')) { if(Test-Path -LiteralPath (Join-Path $OutputDir ($name+'.'+$ext))) { throw ('拒绝覆盖 '+$name+'.'+$ext) } }
 $script:doc.SaveAs((Join-Path $OutputDir ($name+'.dxf')),65)
 $script:doc.SaveAs((Join-Path $OutputDir ($name+'.dwg')),64)
 Write-Host ('DETAIL '+$name+' entities='+$script:space.Count)
 $script:doc.Close($false); $script:doc=$null
}
function AxialRing([double]$cx,[double]$base,[double]$scale,[double]$z0,[double]$z1,[double]$r0,[double]$r1,[string]$layer='OUTLINE') {
 $y=$base+($z0-210)*$scale; $h=($z1-$z0)*$scale
 Rect2D ($cx-$r1*$scale) $y (($r1-$r0)*$scale) $h $layer
 Rect2D ($cx+$r0*$scale) $y (($r1-$r0)*$scale) $h $layer
}
try {
 StartSheet 'A01  丝杆顶部双向止推安装 / 轴向剖视'
 $cx=100.0; $base=45.0; $s=4.0
 Rect2D ($cx-16) $base 32 ((268-210)*$s) 'CENTER'
 Rect2D 25 ($base+(270-210)*$s) 150 (5*$s)
 AxialRing $cx $base $s 236 248 6.5 13.5 'REFERENCE'
 AxialRing $cx $base $s 235 249 4.05 6 'REFERENCE'
 AxialRing $cx $base $s 234 235 5.5 10
 AxialRing $cx $base $s 235 236 7 10
 AxialRing $cx $base $s 248 249 7 10
 AxialRing $cx $base $s 249 250 5.5 10
 AxialRing $cx $base $s 229 234 4.05 8
 AxialRing $cx $base $s 250 255 4.05 8
 foreach($z in @(217,223,255,261)) { AxialRing $cx $base $s $z ($z+6) 4.05 8.3 'REFERENCE' }
 T 'Z=270～275 顶板 5' 185 292 3
 T '上端螺母 261～267、255～261' 185 272 3
 T 'F8-16M 上止推轴承 250～255' 185 257 3
 T '台阶座圈：外20，内14/11，各厚1' 185 242 3
 T 'KFL 壳 236～248；内圈暂按凸出1' 185 227 3
 T 'F8-16M 下止推轴承 229～234' 185 212 3
 T '下端螺母 223～229、217～223' 185 197 3
 T '金属支承柱 2×：外10、孔4.5、长22' 20 20 3
 T '止推轴承两件 8×16×5，承载方向相反；螺纹薄螺母共4件。' 20 10 3
 T '螺纹与实物丝杆匹配；内圈凸出、支承面、锁紧和轴向游隙先复尺。' 20 2 3 'REFERENCE'
 SaveSheet 'A01_顶部双向止推安装_试配'

 StartSheet 'A02  开口同步带双螺钉压夹 / 试配'
 T 'A-A 截面：在两条带端搭接区；截面放大 10:1' 20 300 3.2
 $sx=10.0; $ox=35.0; $oy=130.0
 # x 对应皮带法向 y=-18.3..-9.9；y 对应高度 z=-10.5..-1.5。
 Rect2D $ox ($oy+4) (1.3*$sx) (7.1*$sx)
 Rect2D ($ox+1.3*$sx) ($oy+0.5*$sx) (1.4*$sx) (6*$sx) 'REFERENCE'
 Rect2D ($ox+2.7*$sx) ($oy+0.5*$sx) (1.4*$sx) (6*$sx) 'REFERENCE'
 Rect2D ($ox+4.1*$sx) ($oy+0.7*$sx) (1.6*$sx) (5.6*$sx)
 Rect2D ($ox+5.9*$sx) ($oy+0.5*$sx) (2.5*$sx) (8.5*$sx)
 Rect2D $ox $oy (4.2*$sx) (0.5*$sx)
 Rect2D $ox ($oy+7.5*$sx) (11.3*$sx) (1.5*$sx)
 L ($ox+5.7*$sx) ($oy+3.5*$sx) ($ox+8.8*$sx) ($oy+3.5*$sx) 'CENTER'
 T '背板' 35 119 2.8; T '带1' 52 119 2.8 'REFERENCE'; T '带2' 68 119 2.8 'REFERENCE'
 T '压片' 83 119 2.8; T '螺母座' 103 119 2.8
 T '顶视：夹带基准与两螺钉中心' 215 300 3.2
 Rect2D 215 220 140 25
 Rect2D 255 220 60 25 'REFERENCE'
 C 240 232.5 10 'CENTER'; C 330 232.5 10 'CENTER'
 Dim 240 220 330 220 285 205 0 0.1
 Dim 255 245 315 245 285 262 0 0.1
 T '双 M2×3 平端紧定螺钉，螺母从底部滑入。' 215 186 3
 T '金属压片 14×5.6×1.6；夹紧两端的名义搭接长度6。' 215 174 3
 T '底部挡边厚0.5，距转运板0.5；实际打印及摩擦需验证。' 215 162 3
 T '后夹壁两端按带轮半径6.9切除，越程时名义径向余量0.4。' 215 150 3 'REFERENCE'
 T '皮带宽6、单层厚1.4为假设；两端过渡、夹持力与张紧未验证。' 20 60 3 'REFERENCE'
 T '此图及STL为试配：先试装，再做不少于设计载荷的防滑与循环试验。' 20 48 3 'REFERENCE'
 SaveSheet 'A02_开口皮带压夹_试配'

 StartSheet 'A03  导杆可调限位座 / 上下各一'
 T '俯视（抱箍及侧板），图形放大 4:1' 20 300 3.2
 C 90 220 42; C 90 220 16.4
 Rect2D (90+11*4) (220+3*4) (9*4) (3*4)
 L (90+4.1*4) (220-0.6*4) (90+11*4) (220-0.6*4) 'REFERENCE'
 L (90+4.1*4) (220+0.6*4) (90+11*4) (220+0.6*4) 'REFERENCE'
 Dim 48 220 132 220 90 165 0 0.25
 T '侧板视图（放大4:1）' 220 300 3.2
 Rect2D 225 210 36 67.2
 foreach($cy in @(230.6,256.6)) {
  L 240.2 ($cy-6) 240.2 ($cy+6) 'REFERENCE'
  L 249.8 ($cy-6) 249.8 ($cy+6) 'REFERENCE'
  Arc 245 ($cy-6) 4.8 ([Math]::PI) (2*[Math]::PI) 'REFERENCE'
  Arc 245 ($cy+6) 4.8 0 ([Math]::PI) 'REFERENCE'
 }
 Dim 265 230.6 265 256.6 275 243.6 ([Math]::PI/2) 0.25
 T '孔 Ø8.2；外径 Ø21；开口宽1.2；M3 横向夹紧' 20 144 3
 T '侧板两个 Ø2.4 宽长孔，孔中心距6.5，沿高度各可调 ±1.5。' 20 132 3
 T '下座：环 Z31～36，开关壳 Z33～45.8。' 20 112 3
 T '上座：环 Z192～197，开关壳 Z184～196.8。' 20 100 3
 T '按假设摇臂：下 Z90、上 Z192 接触；机械止挡 Z86 / Z194。' 20 88 3
 T '实物开关型号、动作点、过行程和接线均未确认；需低速实测。' 20 76 3 'REFERENCE'
 T '打印抱箍并非安全认证止挡，轴向防滑、碰撞载荷及防坠必须验证。' 20 64 3 'REFERENCE'
 SaveSheet 'A03_上下限位座_试配'

 StartSheet 'A04  托盘支撑铝条 / 两根不同长度'
 T '负 W 侧：133×5×11；端部至孔中心 4、116；距右端17。' 20 298 3.2
 Rect2D 40 240 133 5; C 44 242.5 1.3 'REFERENCE'; C 156 242.5 1.3 'REFERENCE'
 Dim 40 240 173 240 106.5 228 0
 Dim 44 245 156 245 100 260 0
 T '正 W 侧：145×5×11；端部至孔中心 4、116；距右端29。' 20 196 3.2
 Rect2D 40 145 145 5; C 44 147.5 1.3 'REFERENCE'; C 156 147.5 1.3 'REFERENCE'
 Dim 40 145 185 145 112.5 133 0
 Dim 44 150 156 150 100 165 0
 T '两个 M2.5 螺纹盲孔，孔深约6；由板底 M2.5×8 螺钉安装。' 20 105 3
 T '安装坐标 u=±56；两条中心线分别 W=-26.5、+28.5。' 20 93 3
 T '材料建议铝；仅5 mm宽，孔边距、强度、托盘跨空需实测。' 20 81 3 'REFERENCE'
 SaveSheet 'A04_托盘支撑条_试配'

 StartSheet 'A05  拨叉两端开关及止挡支架 / 镜像一对'
 T '收回端俯视（放大5:1）；伸出端为左右镜像' 20 300 3.2
 $x=70.0; $y=165.0; $s=5.0
 $points=@(@(0,10.4),@(4,10.4),@(4,0),@(10,0),@(10,10.4),@(16.8,10.4),@(16.8,17),@(4,17),@(4,13.4),@(0,13.4))
 for($i=0;$i -lt $points.Count;$i++) {
  $a=$points[$i]; $b=$points[($i+1)%$points.Count]
  L ($x+$a[0]*$s) ($y+$a[1]*$s) ($x+$b[0]*$s) ($y+$b[1]*$s)
 }
 foreach($u in @(7.15,13.65)) { C ($x+$u*$s) ($y+15*$s) (1.1*$s) 'REFERENCE' }
 Dim ($x+7.15*$s) ($y+15*$s) ($x+13.65*$s) ($y+15*$s) ($x+10.4*$s) ($y+20*$s) 0 0.2
 Dim $x $y ($x+16.8*$s) $y ($x+8.4*$s) ($y-10) 0 0.2
 T '拨叉普通行程 0～138；假设开关在 -0.5 / 138.5 接触。' 205 250 3
 T '止挡名义位置 -2 / 140，接触后剩余行程各约1.5。' 205 238 3
 T '开关本体孔距6.5，侧板长孔沿行程可调 ±0.5。' 205 226 3
 T 'P03D 固定孔：u=±75.35、±81.85，w=22，Ø2.4。' 205 214 3
 T '底脚宽仅3.6；材料、螺纹、轴承及停止距离必须实测。' 205 202 3 'REFERENCE'
 T '开关、摇臂过行程和失效保护未验证；不得依赖打印止挡防坠。' 20 106 3 'REFERENCE'
 SaveSheet 'A05_拨叉两端限位座_试配'
} finally {
 if($null -ne $script:doc) { $script:doc.Close($false) }
 $app.Quit()
}
