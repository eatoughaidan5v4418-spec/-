param([string]$OutputDir=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线优化安装复核'))
$ErrorActionPreference='Stop'
# 沿用 v7 的 COM 忙碌重试；不运行其建模代码。
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition')
$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
if(Test-Path -LiteralPath $OutputDir){throw '输出目录已存在，拒绝覆盖'}
$null=New-Item -ItemType Directory -Path $OutputDir
$OutputDir=(Resolve-Path -LiteralPath $OutputDir).Path
$root=Split-Path $PSScriptRoot -Parent
$base=Join-Path $root 'docs\cad\三维装配_v7_加厚夹带'
$app=New-Object -ComObject 'AutoCAD.Application.25'; $app.Visible=$false
$doc=$null
try {
$doc=$app.Documents.Open((Join-Path $base '车库_两层三维装配_v7.dwg'),$true)
$space=$doc.ModelSpace; $origin=[double[]]@(0,0,0); $axis=[double[]]@(0,0,1)
$old=New-Object 'System.Collections.Generic.List[object]'
foreach($r in (Import-Csv (Join-Path $base '模型零件与范围.csv'))){
 if($r.编号 -eq 'CHAIN_ZONE'){ $doc.HandleToObject($r.句柄).Delete(); continue }
 $old.Add([pscustomobject]@{id=$r.编号;solid=$doc.HandleToObject($r.句柄);lift=($r.随升降 -eq 'True');rot=($r.随转盘 -eq 'True');slide=($r.随托盘推拉 -eq 'True')})
}
foreach($name in @('W_CHAIN','W_BRACKET','W_GUIDE','W_CABLE_ENVELOPE','W_CLAMP','W_FASTENER','W_INTERFERENCE')){
 $l=$doc.Layers.Add($name); $l.Color=[int16]($(switch($name){W_CHAIN{4} W_BRACKET{30} W_GUIDE{3} W_CABLE_ENVELOPE{6} W_CLAMP{2} W_FASTENER{5} default{1}}))
}
function Box([double]$x0,[double]$x1,[double]$y0,[double]$y1,[double]$z0,[double]$z1){return $space.AddBox([double[]]@((($x0+$x1)/2),(($y0+$y1)/2),(($z0+$z1)/2)),[double]($x1-$x0),[double]($y1-$y0),[double]($z1-$z0))}
function Spin($o,$a){if([Math]::Abs($a) -gt 0.000001){$o.Rotate3D($origin,$axis,[double]($a*[Math]::PI/180))}}
function MoveZ($o,$z){if([Math]::Abs($z) -gt 0.000001){$o.Move($origin,[double[]]@(0,0,$z))}}
function RadBox([double]$r0,[double]$r1,[double]$w0,[double]$w1,[double]$z0,[double]$z1){$b=Box $r0 $r1 $w0 $w1 $z0 $z1; Spin $b 67.5; return $b}
function Ring([double]$ri,[double]$ro,[double]$z0,[double]$z1){
 $p=[double[]]@(0,0,(($z0+$z1)/2))
 $b=$space.AddCylinder($p,[double]$ro,[double]($z1-$z0))
 $c=$space.AddCylinder($p,[double]$ri,[double]($z1-$z0+2));$b.Boolean(2,$c);return $b
}
function HoleAt([double]$r,[double]$w,[double]$z0,[double]$z1,[double]$radius){
 $a=67.5*[Math]::PI/180;$x=$r*[Math]::Cos($a)-$w*[Math]::Sin($a);$y=$r*[Math]::Sin($a)+$w*[Math]::Cos($a)
 return $space.AddCylinder([double[]]@($x,$y,(($z0+$z1)/2)),$radius,($z1-$z0))
}
function IntersectVolume($a,$b){$isHit=$false;$piece=$a.CheckInterference($b,$true,[ref]$isHit);if($isHit -and $null -ne $piece){$v=[double]$piece.Volume;$piece.Delete();return $v};return 0.0}
function BB($o){$lo=$null;$hi=$null;$o.GetBoundingBox([ref]$lo,[ref]$hi);return ,@($lo,$hi)}
function Overlap($a,$b){for($k=0;$k -lt 3;$k++){if($a[1][$k] -le $b[0][$k]+0.00001 -or $b[1][$k] -le $a[0][$k]+0.00001){return $false}};return $true}
# 两层通道沿 67.5° 扩至 r=100..174、切向 ±13；先后比较停放托盘投影下的材料面积。
$deckSupport=New-Object 'System.Collections.Generic.List[object]';$deckCuts=New-Object 'System.Collections.Generic.List[object]'
foreach($level in @(@{id='L1';top=100},@{id='L2';top=190})){
 $deck=($old | Where-Object {$_.id -eq ('DECK_'+$level.id)}).solid
 $before=@{};$trays=@($old | Where-Object {$_.id -like ('TRAY_'+$level.id+'_*')})
 foreach($tray in $trays){$probe=$tray.solid.Copy();MoveZ $probe (-4);$before[$tray.id]=(IntersectVolume $deck $probe)/3;$probe.Delete()}
 $v0=[double]$deck.Volume;$cut=RadBox 100 174 -13 13 ($level.top-6) ($level.top+1);$deck.Boolean(2,$cut)
 $deckCuts.Add([pscustomobject]@{零件=('DECK_'+$level.id);移除体积_mm3=[Math]::Round(($v0-[double]$deck.Volume),4);槽口='r100..174，w±13'})
 foreach($tray in $trays){$probe=$tray.solid.Copy();MoveZ $probe (-4);$after=(IntersectVolume $deck $probe)/3;$probe.Delete();$deckSupport.Add([pscustomobject]@{托盘=$tray.id;修改前支承投影_mm2=[Math]::Round($before[$tray.id],4);修改后支承投影_mm2=[Math]::Round($after,4);减少_mm2=[Math]::Round(($before[$tray.id]-$after),4)})}
}
# J0 底板、J1 升降盘和 JR 转运板的配套候选孔。
$holeCuts=New-Object 'System.Collections.Generic.List[object]'
$baseSolid=($old | Where-Object {$_.id -eq 'BASE'}).solid;$v0=[double]$baseSolid.Volume
foreach($w in @(-8,8)){$cut=HoleAt 162 $w -7 1 1.7;$baseSolid.Boolean(2,$cut)}
$holeCuts.Add([pscustomobject]@{零件='BASE';试配孔='67.5°局部 r162、w±8，直径3.4';移除体积_mm3=[Math]::Round(($v0-[double]$baseSolid.Volume),4)})
$disc=($old | Where-Object {$_.id -eq 'LIFT_DISC'}).solid;$v0=[double]$disc.Volume
foreach($w in @(-3,3)){$cut=HoleAt 52 $w 72 79 1.1;$disc.Boolean(2,$cut)}
$holeCuts.Add([pscustomobject]@{零件='LIFT_DISC';试配孔='67.5°局部 r52、w±3，直径2.2';移除体积_mm3=[Math]::Round(($v0-[double]$disc.Volume),4)})
$plate=($old | Where-Object {$_.id -eq 'TRANSFER_PLATE'}).solid;$v0=[double]$plate.Volume
$cut=$space.AddCylinder([double[]]@(62,18,87.5),[double]2.25,[double]5);$plate.Boolean(2,$cut)
foreach($q in @(@(58,14),@(66,22))){$cut=$space.AddCylinder([double[]]@($q[0],$q[1],87.5),[double]1.1,[double]5);$plate.Boolean(2,$cut)}
$holeCuts.Add([pscustomobject]@{零件='TRANSFER_PLATE';试配孔='x62、y18直径4.5；x58、y14及x66、y22直径2.2';移除体积_mm3=[Math]::Round(($v0-[double]$plate.Volume),4)})
$deckSupport | Export-Csv (Join-Path $OutputDir '甲板_托盘支承投影.csv') -NoTypeInformation -Encoding UTF8
$deckCuts | Export-Csv (Join-Path $OutputDir '甲板改口_移除体积.csv') -NoTypeInformation -Encoding UTF8
$holeCuts | Export-Csv (Join-Path $OutputDir '新增孔_移除体积.csv') -NoTypeInformation -Encoding UTF8
$new=New-Object 'System.Collections.Generic.List[object]'
function AddNew($o,$id,$layer,$lift,$rot,$kind){$o.Layer=$layer;$o.EntityTransparency='25';$new.Add([pscustomobject]@{id=$id;solid=$o;lift=$lift;rot=$rot;slide=$false;kind=$kind})}
## J0 支架一体化，拖链端头留 0.5 名义间隙，底脚增加两颗候选 M3 孔。
$j0=RadBox 158 174 -12 12 0 4;$stand=RadBox 169 173 -10 10 3 44;$j0.Boolean(0,$stand)
$holder=RadBox 161 171 -10 10 38 45;$j0.Boolean(0,$holder)
$cut=RadBox 162.5 169.5 -8.5 8.5 39.5 46;$j0.Boolean(2,$cut)
foreach($w in @(-8,8)){$cut=HoleAt 162 $w -1 5 1.7;$j0.Boolean(2,$cut)}
AddNew $j0 'J0_BRACKET' 'W_BRACKET' $false $false '候选实体'
## J1 支架与导槽一体化，含端头容纳腔、升降盘孔及固定侧线夹孔。
$j1=RadBox 48 120 -8 8 70 73;$holder=RadBox 111 121 -10 10 70 78;$j1.Boolean(0,$holder)
$cut=RadBox 112.5 119.5 -8.5 8.5 72.5 79;$j1.Boolean(2,$cut)
foreach($w in @(-3,3)){$cut=HoleAt 52 $w 69 74 1.1;$j1.Boolean(2,$cut)}
foreach($w in @(-5,5)){$cut=HoleAt 96 $w 69 74 1.1;$j1.Boolean(2,$cut)}
$floor=Ring 59 92 73 74;$j1.Boolean(0,$floor)
$inner=Ring 59 61 74 79;$j1.Boolean(0,$inner)
$outer=Ring 91 92 74 79;$cut=RadBox 90.5 92.5 -3 3 73.5 79.5;$outer.Boolean(2,$cut);$j1.Boolean(0,$outer)
AddNew $j1 'J1_BRACKET_GUIDE' 'W_BRACKET' $true $false '候选实体'
## 固定侧设置 5×4 的候选通道；实际线束直径与线夹结构仍须选型。
$jf=RadBox 93 99 -8 8 73 79;$cut=RadBox 92 100 -2.5 2.5 74.5 78.5;$jf.Boolean(2,$cut)
foreach($w in @(-5,5)){$cut=HoleAt 96 $w 72 80 1.1;$jf.Boolean(2,$cut)}
AddNew $jf 'JF_CLAMP' 'W_CLAMP' $true $false '候选实体'
## 旋转侧线夹与板下表面接触，孔与 P03E 候选穿线孔同轴。
$jr=Box 55 69 11 25 80 86;$cut=$space.AddCylinder([double[]]@(62,18,83),[double]2.25,[double]8);$jr.Boolean(2,$cut)
foreach($q in @(@(58,14),@(66,22))){$cut=$space.AddCylinder([double[]]@($q[0],$q[1],83),[double]1.1,[double]8);$jr.Boolean(2,$cut)}
AddNew $jr 'JR_CLAMP' 'W_CLAMP' $true $true '候选实体'
# 此环为电缆允许占用区，不假装模拟真实柔性线的收放。
AddNew (Ring 62 90 74.5 78.5) 'ROTARY_CABLE_ZONE' 'W_CABLE_ENVELOPE' $true $false '线环占用包络'
# 紧固件头部和轴杆采用候选外包络；螺纹、螺母及锁紧形式尚未选型。
foreach($w in @(-8,8)){
 AddNew (HoleAt 162 $w -6 4 1.5) ('J0_BOLT_'+$w+'_SHAFT') 'W_FASTENER' $false $false '候选紧固件包络'
 AddNew (HoleAt 162 $w 4 6.5 2.75) ('J0_BOLT_'+$w+'_HEAD') 'W_FASTENER' $false $false '候选紧固件包络'
}
foreach($w in @(-3,3)){
 AddNew (HoleAt 52 $w 70 78 1.0) ('J1_BOLT_'+$w+'_SHAFT') 'W_FASTENER' $true $false '候选紧固件包络'
 AddNew (HoleAt 52 $w 78 80.5 2.2) ('J1_BOLT_'+$w+'_HEAD') 'W_FASTENER' $true $false '候选紧固件包络'
}
foreach($w in @(-5,5)){
 AddNew (HoleAt 96 $w 70 79 1.0) ('JF_BOLT_'+$w+'_SHAFT') 'W_FASTENER' $true $false '候选紧固件包络'
 AddNew (HoleAt 96 $w 79 81.5 2.2) ('JF_BOLT_'+$w+'_HEAD') 'W_FASTENER' $true $false '候选紧固件包络'
}
$i=0;foreach($q in @(@(58,14),@(66,22))){
 $shaft=$space.AddCylinder([double[]]@($q[0],$q[1],84.5),[double]1.0,[double]9)
 $head=$space.AddCylinder([double[]]@($q[0],$q[1],90.25),[double]2.2,[double]2.5)
 AddNew $shaft ('JR_BOLT_'+$i+'_SHAFT') 'W_FASTENER' $true $true '候选紧固件包络'
 AddNew $head ('JR_BOLT_'+$i+'_HEAD') 'W_FASTENER' $true $true '候选紧固件包络';$i++
}
function MakeChain([double]$z){
 $list=New-Object 'System.Collections.Generic.List[object]'
 $m=$z-27;$c=(157+40+$m)/2
 $list.Add((RadBox 163 169 -8 8 40 $c))
 $list.Add((RadBox 113 119 -8 8 $m $c))
 # 每段有少量搭接，形状仅代表外厚6、外宽16、R25的候选链体。
 for($i=0;$i -lt 18;$i++){
  $a0=$i*10*[Math]::PI/180;$a1=($i+1)*10*[Math]::PI/180;$am=($a0+$a1)/2
  $r=141+25*[Math]::Cos($am);$zz=$c+25*[Math]::Sin($am)
  $b=Box (-2.8) 2.8 -8 8 -3 3
  $b.Rotate3D($origin,[double[]]@(0,1,0),[double]([Math]::PI/2-$am))
  $b.Move($origin,[double[]]@($r,0,$zz));Spin $b 67.5;$list.Add($b)
 }
 foreach($b in $list){$b.Layer='W_CHAIN';$b.EntityTransparency='15'}
 return ,$list
}
$chain=MakeChain 100
function AssertRadialCenter($solid,[double]$r,[double]$w){
 $bb=BB $solid;$x=($bb[0][0]+$bb[1][0])/2;$y=($bb[0][1]+$bb[1][1])/2
 $a=67.5*[Math]::PI/180;$rr=$x*[Math]::Cos($a)+$y*[Math]::Sin($a);$ww=-$x*[Math]::Sin($a)+$y*[Math]::Cos($a)
 if([Math]::Abs($rr-$r) -gt 0.001 -or [Math]::Abs($ww-$w) -gt 0.001){throw ("径向定位错误：r=$rr,w=$ww；期望 r=$r,w=$w")}
}
AssertRadialCenter (($new | Where-Object {$_.id -eq 'JF_CLAMP'}).solid) 96 0
AssertRadialCenter $chain[0] 166 0;AssertRadialCenter $chain[1] 116 0
$rows=New-Object 'System.Collections.Generic.List[object]'
$coverage=New-Object 'System.Collections.Generic.List[object]'
$errors=New-Object 'System.Collections.Generic.List[object]'
$savedHits=New-Object 'System.Collections.Generic.List[object]'
$initial=@{}; foreach($p in @($old.ToArray())+@($new.ToArray())){$initial[$p.id]=BB $p.solid}
function CheckPair($a,$b,$z,$ang,$stroke,$phase){
 try{
  $hit=$false;$intersection=$a.solid.CheckInterference($b.solid,$true,[ref]$hit)
  if($hit -and $null -ne $intersection){
   $vol=[double]$intersection.Volume
   if($vol -gt 0.000001){
    $rows.Add([pscustomobject]@{阶段=$phase;Z=$z;角度=$ang;行程=$stroke;新增件=$a.id;对象=$b.id;体积=[Math]::Round($vol,4);性质=$a.kind})
    if($z -eq 100 -and $ang -eq 0 -and $stroke -eq 0 -and $phase -eq '基准'){$intersection.Layer='W_INTERFERENCE';$savedHits.Add($intersection)}else{$intersection.Delete()}
   }else{$intersection.Delete()}
  }
 }catch{$errors.Add([pscustomobject]@{Z=$z;角度=$ang;行程=$stroke;A=$a.id;B=$b.id;错误=$_.Exception.Message})}
}
function PoseBounds($p,[double]$z,[double]$ang,[double]$stroke){
 $bb=$initial[$p.id];$x0=[double]$bb[0][0];$x1=[double]$bb[1][0];$y0=[double]$bb[0][1];$y1=[double]$bb[1][1]
 if($p.slide){$x0+=$stroke;$x1+=$stroke}
 if($p.rot){
  $c=[Math]::Cos($ang*[Math]::PI/180);$s=[Math]::Sin($ang*[Math]::PI/180)
  $xc=($x0+$x1)/2;$yc=($y0+$y1)/2;$hx=($x1-$x0)/2;$hy=($y1-$y0)/2
  $rx=$xc*$c-$yc*$s;$ry=$xc*$s+$yc*$c
  $ex=[Math]::Abs($c)*$hx+[Math]::Abs($s)*$hy;$ey=[Math]::Abs($s)*$hx+[Math]::Abs($c)*$hy
  $x0=$rx-$ex;$x1=$rx+$ex;$y0=$ry-$ey;$y1=$ry+$ey
 }
 $dz=if($p.lift){$z-100}else{0}
 return ,@([double[]]@($x0,$y0,([double]$bb[0][2]+$dz)),[double[]]@($x1,$y1,([double]$bb[1][2]+$dz)))
}
function RelativeKey($a,$b,$z,$ang,$stroke){
 $isChain=$a.id -like 'CHAIN_*'
 $axisymmetric=$a.id -in @('ROTARY_CABLE_ZONE')
 $k=$a.id+'|'+$b.id
 if($isChain -or ($a.lift -ne $b.lift)){$k+='|Z'+$z}
 if(($isChain -and $b.rot) -or (!$isChain -and !$axisymmetric -and ($a.rot -ne $b.rot))){$k+='|A'+$ang}
 if($a.slide -or $b.slide){$k+='|S'+$stroke}
 return $k
}
function CheckPose($z,$ang,$stroke,$phase){
 if($null -eq $script:poseChain -or $script:poseChainZ -ne $z){
  if($null -ne $script:poseChain){foreach($p in $script:poseChain){$p.solid.Delete()}}
  $script:poseChain=New-Object 'System.Collections.Generic.List[object]';$j=0
  foreach($solid in (MakeChain $z)){$script:poseChain.Add([pscustomobject]@{id=('CHAIN_'+$j);solid=$solid;kind='候选链体';lift=$false;rot=$false;slide=$false});$j++}
  $script:poseChainZ=$z
 }
 $parts=@{};$bounds=@{}
 foreach($p in @($old.ToArray())+@($new.ToArray())){$parts[$p.id]=$p;$bounds[$p.id]=PoseBounds $p $z $ang $stroke}
 foreach($p in $script:poseChain){$parts[$p.id]=$p;$bounds[$p.id]=BB $p.solid}
 $before=$rows.Count;$pending=New-Object 'System.Collections.Generic.List[object]';$move=@{}
 foreach($d in $pairDefs){
  if(-not (Overlap $bounds[$d.a] $bounds[$d.b])){continue}
  $a=$parts[$d.a];$b=$parts[$d.b];$key=RelativeKey $a $b $z $ang $stroke
  if($cache.ContainsKey($key)){
   $v=$cache[$key];if($v.hit){$rows.Add([pscustomobject]@{阶段=$phase;Z=$z;角度=$ang;行程=$stroke;新增件=$a.id;对象=$b.id;体积=$v.volume;性质=$a.kind})}
  }else{
   $pending.Add([pscustomobject]@{a=$a;b=$b;key=$key})
   if($a.id -notlike 'CHAIN_*'){$move[$a.id]=$a};if($b.id -notlike 'CHAIN_*'){$move[$b.id]=$b}
  }
 }
 foreach($p in $move.Values){
  if($p.slide -and $stroke -ne 0){$p.solid.Move($origin,[double[]]@($stroke,0,0))}
  if($p.rot){Spin $p.solid $ang};if($p.lift){MoveZ $p.solid ($z-100)}
 }
 foreach($pair in $pending){
  $n=$rows.Count;CheckPair $pair.a $pair.b $z $ang $stroke $phase
  $hit=$rows.Count -gt $n;$vol=if($hit){$rows[$rows.Count-1].体积}else{0}
  $cache[$pair.key]=[pscustomobject]@{hit=$hit;volume=$vol}
 }
 foreach($p in $move.Values){if($p.lift){MoveZ $p.solid (100-$z)};if($p.rot){Spin $p.solid (-$ang)};if($p.slide -and $stroke -ne 0){$p.solid.Move($origin,[double[]]@(-$stroke,0,0))}}
 $count=$rows.Count-$before
 $coverage.Add([pscustomobject]@{阶段=$phase;Z=$z;角度=$ang;行程=$stroke;相交记录=$count})
 Write-Host ('POSE '+$phase+' Z='+$z+' A='+$ang+' S='+$stroke+' hits='+$count+' newChecks='+$pending.Count)
}
# 导出基准装配（不包含后续相交体）。
$ss=$doc.SelectionSets.Add('wiring_export');$ss.Select(5)
$doc.Export((Join-Path $OutputDir '车库_v7_走线优化'),'SAT',$ss);$ss.Delete()
$manifest=foreach($p in @($old.ToArray())+@($new.ToArray())){$b=BB $p.solid;[pscustomobject]@{id=$p.id;handle=$p.solid.Handle;layer=$p.solid.Layer;lift=$p.lift;rot=$p.rot;slide=$p.slide;x0=$b[0][0];y0=$b[0][1];z0=$b[0][2];x1=$b[1][0];y1=$b[1][1];z1=$b[1][2]}}
$chainManifest=@();$idx=0;foreach($c in $chain){$b=BB $c;$chainManifest += [pscustomobject]@{id=('CHAIN_'+$idx);handle=$c.Handle;layer=$c.Layer;lift='动态几何';rot=$false;slide=$false;x0=$b[0][0];y0=$b[0][1];z0=$b[0][2];x1=$b[1][0];y1=$b[1][1];z1=$b[1][2]};$idx++}
$manifest=@($manifest)+@($chainManifest)
$manifest | Export-Csv (Join-Path $OutputDir '装配清单.csv') -NoTypeInformation -Encoding UTF8
# 连续行程的保守全包络，覆盖全部角度和升降/推拉组合；相交只是候选。
$swept=@{}
foreach($p in @($old.ToArray())+@($new.ToArray())){
 $b=$initial[$p.id];$lo=[double[]]$b[0].Clone();$hi=[double[]]$b[1].Clone()
 if($p.slide){$hi[0]+=138}
 if($p.rot){$rr=0;foreach($x in @($lo[0],$hi[0])){foreach($y in @($lo[1],$hi[1])){$rr=[Math]::Max($rr,[Math]::Sqrt($x*$x+$y*$y))}};$lo[0]=-$rr;$lo[1]=-$rr;$hi[0]=$rr;$hi[1]=$rr}
 if($p.lift){$lo[2]-=14;$hi[2]+=94};$swept[$p.id]=@($lo,$hi)
}
$env=RadBox 112.5 169.5 -8 8 37 210.5;$chainEnv=BB $env;$env.Delete()
$continuous=New-Object 'System.Collections.Generic.List[object]'
foreach($a in $new){foreach($b in $old){if(Overlap $swept[$a.id] $swept[$b.id]){$continuous.Add([pscustomobject]@{新增件=$a.id;对象=$b.id;结论='全行程包络重叠，须精查'})}}}
for($i=0;$i -lt $new.Count;$i++){for($j=$i+1;$j -lt $new.Count;$j++){if(Overlap $swept[$new[$i].id] $swept[$new[$j].id]){$continuous.Add([pscustomobject]@{新增件=$new[$i].id;对象=$new[$j].id;结论='全行程包络重叠，须精查'})}}}
foreach($b in @($old.ToArray())+@($new.ToArray())){if(Overlap $chainEnv $swept[$b.id]){$continuous.Add([pscustomobject]@{新增件='CHAIN_ALL';对象=$b.id;结论='全行程包络重叠，须精查'})}}
$continuous | Export-Csv (Join-Path $OutputDir '全行程_保守包络候选.csv') -NoTypeInformation -Encoding UTF8
# 将整个假设拖链包络向各方向额外扩大至少 1 mm，直接与静止原实体做布尔相交。
# 若不相交，可证明该简化链体在升降全范围内与该静止对象的名义间隙不小于 1 mm。
$sweepChecks=New-Object 'System.Collections.Generic.List[object]'
$probe=RadBox 111.5 170.5 -9.5 9.5 38.5 212;$probeBounds=BB $probe
foreach($p in $old){if($p.lift -or $p.rot -or $p.slide){continue};$v=0.0;if(Overlap $probeBounds $initial[$p.id]){$v=IntersectVolume $probe $p.solid};$sweepChecks.Add([pscustomobject]@{检查='拖链_扩大1mm_相对静止件';对象=$p.id;相交体积_mm3=[Math]::Round($v,5)})}
$probe.Delete()
# JR 线夹围绕转轴的全圆包络同样向各方向扩大至少 1 mm；与同升降、不旋转的实体检查。
$probe=Ring 55 74.5 79 92.5;$probeBounds=BB $probe
foreach($p in @($old.ToArray())+@($new.ToArray())){if(!$p.lift -or $p.rot -or $p.slide -or $p.id -eq 'ROTARY_CABLE_ZONE'){continue};$v=0.0;if(Overlap $probeBounds $initial[$p.id]){$v=IntersectVolume $probe $p.solid};$sweepChecks.Add([pscustomobject]@{检查='JR_全圆扩大1mm_相对随升降固定件';对象=$p.id;相交体积_mm3=[Math]::Round($v,5)})}
$probe.Delete()
# J1 一体支架的全高包络由中心圆柱及径向臂两个探针组成；二者均留至少 1 mm。
$j1Probes=@(
 @{name='J1中心_扩大1mm_相对静止件';solid=($space.AddCylinder([double[]]@(0,0,116),[double]93,[double]122))},
 @{name='J1臂_扩大1mm_相对静止件';solid=(RadBox 47 122 -11 11 55 177)},
 @{name='JR升降全圆_扩大1mm_相对静止件';solid=(Ring 55 74.5 65 186.5)}
)
foreach($item in $j1Probes){$probe=$item.solid;$pb=BB $probe;foreach($p in $old){if($p.lift -or $p.rot -or $p.slide){continue};$v=0.0;if(Overlap $pb $initial[$p.id]){$v=IntersectVolume $probe $p.solid};$sweepChecks.Add([pscustomobject]@{检查=$item.name;对象=$p.id;相交体积_mm3=[Math]::Round($v,5)})};$probe.Delete()}
$sweepChecks | Export-Csv (Join-Path $OutputDir '关键零件_连续包络实体检查.csv') -NoTypeInformation -Encoding UTF8
$pairDefs=New-Object 'System.Collections.Generic.List[object]'
foreach($p in $continuous){if($p.新增件 -eq 'CHAIN_ALL'){for($i=0;$i -lt 20;$i++){$pairDefs.Add([pscustomobject]@{a=('CHAIN_'+$i);b=$p.对象})}}else{$pairDefs.Add([pscustomobject]@{a=$p.新增件;b=$p.对象})}}
$cache=@{};$script:poseChain=$null;$script:poseChainZ=$null
CheckPose 100 0 0 '基准'
foreach($z in @(86,92,100,130,160,182,190,194)){foreach($a in @(-135,-90,-45,0,45,90,135,180)){CheckPose $z $a 0 '升降旋转'}}
foreach($z in @(92,100,182,190)){foreach($a in @(-135,-90,-45,0,45,90,135,180)){foreach($u in @(0,34.5,69,103.5,138)){CheckPose $z $a $u '推拉'}}}
# 额外检查线夹角点最接近 r52 螺钉的两个角度，防止常规 45° 采样遗漏。
foreach($a in @(11.19,101.19)){CheckPose 100 $a 0 '螺钉近邻'}
# 清空缓存对两个姿态重新进行全部候选实体运算，并与前面的结果逐条比较。
$audit=New-Object 'System.Collections.Generic.List[object]'
foreach($case in @(@{z=100;a=0;u=0;phase='基准'},@{z=190;a=45;u=138;phase='推拉'})){
 $original=@($rows | Where-Object {$_.阶段 -eq $case.phase -and [double]$_.Z -eq $case.z -and [double]$_.角度 -eq $case.a -and [double]$_.行程 -eq $case.u})
 $n=$rows.Count;$cache=@{};CheckPose $case.z $case.a $case.u '独立复算';$actual=@($rows.ToArray() | Select-Object -Skip $n)
 $oldPairs=@{};foreach($r in $original){$oldPairs[$r.新增件+'|'+$r.对象]=$r.体积}
 foreach($r in $actual){$key=$r.新增件+'|'+$r.对象;if(!$oldPairs.ContainsKey($key) -or [Math]::Abs([double]$oldPairs[$key]-[double]$r.体积) -gt .001){throw ('缓存复算不一致：'+$key)}}
 if($actual.Count -ne $original.Count){throw ('缓存复算数量不一致：'+$case.z+','+$case.a+','+$case.u)}
 $audit.Add([pscustomobject]@{Z=$case.z;角度=$case.a;行程=$case.u;相交数=$actual.Count;结论='逐对体积一致'})
 if($rows.Count -gt $n){$rows.RemoveRange($n,$rows.Count-$n)};$coverage.RemoveAt($coverage.Count-1)
}
$audit | Export-Csv (Join-Path $OutputDir '缓存结果_独立复算.csv') -NoTypeInformation -Encoding UTF8
if($null -ne $script:poseChain){foreach($p in $script:poseChain){$p.solid.Delete()};$script:poseChain=$null}
$rows | Export-Csv (Join-Path $OutputDir '姿态_实体相交.csv') -NoTypeInformation -Encoding UTF8
$coverage | Export-Csv (Join-Path $OutputDir '姿态_覆盖.csv') -NoTypeInformation -Encoding UTF8
$errors | Export-Csv (Join-Path $OutputDir '检查错误.csv') -NoTypeInformation -Encoding UTF8
$maxError=0;foreach($p in @($old.ToArray())+@($new.ToArray())){$bb=BB $p.solid;for($e=0;$e -lt 2;$e++){for($i=0;$i -lt 3;$i++){$maxError=[Math]::Max($maxError,[Math]::Abs($bb[$e][$i]-$initial[$p.id][$e][$i]))}}}
if($maxError -gt 0.001){throw '姿态未恢复'}
$vp=$doc.ActiveViewport;$vp.Direction=[double[]]@(1,-1,0.8);$vp.Target=[double[]]@(0,0,135);$vp.Height=650;$doc.ActiveViewport=$vp
# 仅用于显示 JF → JR 的基准姿态中心线；不参与实体碰撞判定，也不表示真实柔性线形。
$pathLayer=$doc.Layers.Add('W_LOOP_PATH');$pathLayer.Color=[int16]6
$points=New-Object 'System.Collections.Generic.List[double]';$aStart=67.5*[Math]::PI/180
# 试配线环末端以 R4 圆弧平顺转入竖直孔，实际线材能否接受此动态弯曲半径尚未确定。
$px=62.0;$py=18.0;for($q=0;$q -lt 30;$q++){$rr=[Math]::Sqrt($px*$px+$py*$py);$phi=[Math]::Atan2($py,$px);$k=($rr-89)/($phi+4*[Math]::PI-$aStart);$norm=[Math]::Sqrt($k*$k+$rr*$rr);$tx=($k*[Math]::Cos($phi)-$rr*[Math]::Sin($phi))/$norm;$ty=($k*[Math]::Sin($phi)+$rr*[Math]::Cos($phi))/$norm;$px=62-4*$tx;$py=18-4*$ty}
$rEnd=[Math]::Sqrt($px*$px+$py*$py);$aEnd=[Math]::Atan2($py,$px)+4*[Math]::PI
$points.Add(96*[Math]::Cos($aStart));$points.Add(96*[Math]::Sin($aStart));$points.Add(76.5)
for($i=0;$i -le 140;$i++){$t=$i/140.0;$r=89+($rEnd-89)*$t;$a=$aStart+($aEnd-$aStart)*$t;$points.Add($r*[Math]::Cos($a));$points.Add($r*[Math]::Sin($a));$points.Add(76.5)}
for($i=1;$i -le 32;$i++){$a=($i/32.0)*[Math]::PI/2;$points.Add($px+4*[Math]::Sin($a)*$tx);$points.Add($py+4*[Math]::Sin($a)*$ty);$points.Add(76.5+4*(1-[Math]::Cos($a)))}
$points.Add(62);$points.Add(18);$points.Add(89.5)
$wireRef=$space.Add3DPoly([double[]]$points.ToArray());$wireRef.Layer='W_LOOP_PATH'
$doc.Regen(1)
$doc.SaveAs((Join-Path $OutputDir '车库_v7_走线优化.dwg'),64)
@{姿态数=$coverage.Count;相交记录=$rows.Count;包络候选=$continuous.Count;连续实体检查=$sweepChecks.Count;错误=$errors.Count;恢复偏差=$maxError;说明='全行程AABB保守筛查、关键零件连续包络及227姿态实体检测；线环为占用包络，不是柔性仿真'} | ConvertTo-Json | Set-Content (Join-Path $OutputDir '检查统计.json') -Encoding UTF8
Write-Host ('DONE '+$OutputDir)
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
