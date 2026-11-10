param([string]$OutputDir=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线复核完成'))
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
foreach($name in @('W_CHAIN','W_BRACKET','W_GUIDE','W_CABLE_ENVELOPE','W_CLAMP','W_INTERFERENCE')){
 $l=$doc.Layers.Add($name); $l.Color=[int16]($(switch($name){W_CHAIN{4} W_BRACKET{30} W_GUIDE{3} W_CABLE_ENVELOPE{6} W_CLAMP{2} default{1}}))
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
function BB($o){$lo=$null;$hi=$null;$o.GetBoundingBox([ref]$lo,[ref]$hi);return ,@($lo,$hi)}
function Overlap($a,$b){for($k=0;$k -lt 3;$k++){if($a[1][$k] -le $b[0][$k]+0.00001 -or $b[1][$k] -le $a[0][$k]+0.00001){return $false}};return $true}
$new=New-Object 'System.Collections.Generic.List[object]'
function AddNew($o,$id,$layer,$lift,$rot,$kind){$o.Layer=$layer;$o.EntityTransparency='25';$new.Add([pscustomobject]@{id=$id;solid=$o;lift=$lift;rot=$rot;slide=$false;kind=$kind})}
AddNew (RadBox 158 174 -12 12 0 4) 'J0_FOOT' 'W_BRACKET' $false $false '候选实体'
AddNew (RadBox 169 173 -10 10 4 44) 'J0_STAND' 'W_BRACKET' $false $false '候选实体'
AddNew (RadBox 162 170 -10 10 37 43) 'J0_CLAMP' 'W_CLAMP' $false $false '候选实体'
AddNew (RadBox 48 120 -6 6 70 73) 'J1_ARM' 'W_BRACKET' $true $false '候选实体'
AddNew (RadBox 112 120 -10 10 70 77) 'J1_CLAMP' 'W_CLAMP' $true $false '候选实体'
AddNew (Ring 59 92 77 79) 'GUIDE_BASE' 'W_GUIDE' $true $false '候选实体'
AddNew (Ring 59 61 79 86) 'GUIDE_INNER' 'W_GUIDE' $true $false '候选实体'
AddNew (Ring 90 92 79 86) 'GUIDE_OUTER' 'W_GUIDE' $true $false '候选实体'
AddNew (RadBox 84 92 -5 5 79 87) 'JF_CLAMP' 'W_CLAMP' $true $false '候选实体'
AddNew (Box 54 62 14 22 82 89) 'JR_CLAMP' 'W_CLAMP' $true $true '候选实体'
# 此环为电缆允许占用区，不假装模拟真实柔性线的收放。
AddNew (Ring 62 88 80 85) 'ROTARY_CABLE_ZONE' 'W_CABLE_ENVELOPE' $true $false '线环占用包络'
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
foreach($v in @(@('J0_FOOT',166),@('J0_STAND',171),@('J0_CLAMP',166),@('J1_ARM',84),@('J1_CLAMP',116),@('JF_CLAMP',88))){
 $p=$new | Where-Object {$_.id -eq $v[0]};AssertRadialCenter $p.solid $v[1] 0
}
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
 $axisymmetric=$a.id -in @('GUIDE_BASE','GUIDE_INNER','GUIDE_OUTER','ROTARY_CABLE_ZONE')
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
 # 基准和前 5 个极限姿态与无缓存、逐对移动的直接检查比对。
 if($phase -eq '基准' -and $count -ne 29){throw ("基准姿态复核不一致：$count / 29")}
 if($phase -eq '升降旋转' -and $z -eq 86 -and $stroke -eq 0){$expect=@{'-135'=32;'-90'=30;'-45'=29;'0'=29;'45'=30};if($expect.ContainsKey([string]$ang) -and $count -ne $expect[[string]$ang]){throw ("直接检查复核不一致：Z=$z A=$ang，$count / $($expect[[string]$ang])")}}
 $coverage.Add([pscustomobject]@{阶段=$phase;Z=$z;角度=$ang;行程=$stroke;相交记录=$count})
 Write-Host ('POSE '+$phase+' Z='+$z+' A='+$ang+' S='+$stroke+' hits='+$count+' newChecks='+$pending.Count)
}
# 导出基准装配（不包含后续相交体）。
$ss=$doc.SelectionSets.Add('wiring_export');$ss.Select(5)
$doc.Export((Join-Path $OutputDir '车库_v7_走线候选'),'SAT',$ss);$ss.Delete()
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
$pairDefs=New-Object 'System.Collections.Generic.List[object]'
foreach($p in $continuous){if($p.新增件 -eq 'CHAIN_ALL'){for($i=0;$i -lt 20;$i++){$pairDefs.Add([pscustomobject]@{a=('CHAIN_'+$i);b=$p.对象})}}else{$pairDefs.Add([pscustomobject]@{a=$p.新增件;b=$p.对象})}}
$cache=@{};$script:poseChain=$null;$script:poseChainZ=$null
CheckPose 100 0 0 '基准'
foreach($z in @(86,92,100,130,160,182,190,194)){foreach($a in @(-135,-90,-45,0,45,90,135,180)){CheckPose $z $a 0 '升降旋转'}}
foreach($z in @(92,100,182,190)){foreach($a in @(-135,-90,-45,0,45,90,135,180)){foreach($u in @(0,34.5,69,103.5,138)){CheckPose $z $a $u '推拉'}}}
if($null -ne $script:poseChain){foreach($p in $script:poseChain){$p.solid.Delete()};$script:poseChain=$null}
$rows | Export-Csv (Join-Path $OutputDir '姿态_实体相交.csv') -NoTypeInformation -Encoding UTF8
$coverage | Export-Csv (Join-Path $OutputDir '姿态_覆盖.csv') -NoTypeInformation -Encoding UTF8
$errors | Export-Csv (Join-Path $OutputDir '检查错误.csv') -NoTypeInformation -Encoding UTF8
$maxError=0;foreach($p in @($old.ToArray())+@($new.ToArray())){$bb=BB $p.solid;for($e=0;$e -lt 2;$e++){for($i=0;$i -lt 3;$i++){$maxError=[Math]::Max($maxError,[Math]::Abs($bb[$e][$i]-$initial[$p.id][$e][$i]))}}}
if($maxError -gt 0.001){throw '姿态未恢复'}
$vp=$doc.ActiveViewport;$vp.Direction=[double[]]@(1,-1,0.8);$vp.Target=[double[]]@(0,0,135);$vp.Height=650;$doc.ActiveViewport=$vp
# 仅用于显示 JF → JR 的基准姿态中心线；不参与实体碰撞判定，也不表示真实柔性线形。
$pathLayer=$doc.Layers.Add('W_LOOP_PATH');$pathLayer.Color=[int16]6
$points=New-Object 'System.Collections.Generic.List[double]';$rEnd=[Math]::Sqrt(58*58+18*18)
$aStart=67.5*[Math]::PI/180;$aEnd=[Math]::Atan2(18,58)+4*[Math]::PI
for($i=0;$i -le 140;$i++){$t=$i/140.0;$r=88+($rEnd-88)*$t;$a=$aStart+($aEnd-$aStart)*$t;$points.Add($r*[Math]::Cos($a));$points.Add($r*[Math]::Sin($a));$points.Add(82.5)}
$wireRef=$space.Add3DPoly([double[]]$points.ToArray());$wireRef.Layer='W_LOOP_PATH'
$doc.Regen(1)
$doc.SaveAs((Join-Path $OutputDir '车库_v7_走线候选.dwg'),64)
@{姿态数=$coverage.Count;相交记录=$rows.Count;包络候选=$continuous.Count;错误=$errors.Count;恢复偏差=$maxError;说明='全行程AABB保守筛查 + 225姿态实体检测；线环为占用包络，不是柔性仿真；未通过设计'} | ConvertTo-Json | Set-Content (Join-Path $OutputDir '检查统计.json') -Encoding UTF8
Write-Host ('DONE '+$OutputDir)
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
