param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线优化安装复核'))
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition');$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
$folder=(Resolve-Path -LiteralPath $Folder).Path
$target=Join-Path $folder '车库_v7_走线优化_R12试配.dwg'
if((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath (Join-Path $folder '车库_v7_走线优化_R12.SAT'))){throw '目标文件已存在，拒绝覆盖'}
$manifest=Import-Csv (Join-Path $folder '装配清单.csv') -Encoding UTF8
$app=New-Object -ComObject 'AutoCAD.Application.25';$app.Visible=$false;$doc=$null
try {
 $doc=$app.Documents.Open((Join-Path $folder '车库_v7_走线优化.dwg'),$true);$space=$doc.ModelSpace
 $origin=[double[]]@(0,0,0);$axis=[double[]]@(0,0,1)
 function Box([double]$x0,[double]$x1,[double]$y0,[double]$y1,[double]$z0,[double]$z1){return $space.AddBox([double[]]@((($x0+$x1)/2),(($y0+$y1)/2),(($z0+$z1)/2)),($x1-$x0),($y1-$y0),($z1-$z0))}
 function RadBox([double]$r0,[double]$r1,[double]$w0,[double]$w1,[double]$z0,[double]$z1){$b=Box $r0 $r1 $w0 $w1 $z0 $z1;$b.Rotate3D($origin,$axis,67.5*[Math]::PI/180);return $b}
 function Ring([double]$ri,[double]$ro,[double]$z0,[double]$z1){$p=[double[]]@(0,0,(($z0+$z1)/2));$a=$space.AddCylinder($p,$ro,($z1-$z0));$b=$space.AddCylinder($p,$ri,($z1-$z0+2));$a.Boolean(2,$b);return $a}
 function BB($o){$lo=$null;$hi=$null;$o.GetBoundingBox([ref]$lo,[ref]$hi);return ,@($lo,$hi)}
 function Overlap($a,$b){for($i=0;$i -lt 3;$i++){if($a[1][$i] -le $b[0][$i]+0.00001 -or $b[1][$i] -le $a[0][$i]+0.00001){return $false}};return $true}
 # 将线夹入口开出候选切向避让槽，使 Ø3 示例线以 R12 曲线转入穿板孔。
 $aStart=67.5*[Math]::PI/180;$radius=12.0;$px=62.0;$py=18.0
 for($q=0;$q -lt 40;$q++){$rr=[Math]::Sqrt($px*$px+$py*$py);$phi=[Math]::Atan2($py,$px);$k=($rr-89)/($phi+4*[Math]::PI-$aStart);$norm=[Math]::Sqrt($k*$k+$rr*$rr);$tx=($k*[Math]::Cos($phi)-$rr*[Math]::Sin($phi))/$norm;$ty=($k*[Math]::Sin($phi)+$rr*[Math]::Cos($phi))/$norm;$px=62-$radius*$tx;$py=18-$radius*$ty}
 $jrPart=@($manifest | Where-Object {$_.id -eq 'JR_CLAMP'});if($jrPart.Count -ne 1){throw '找不到唯一的旋转线夹'}
 $jr=$doc.HandleToObject($jrPart[0].handle);$oldVolume=[double]$jr.Volume
 $relief=Box -7.5 1.8 -1.8 1.8 79 85.2
 $relief.Rotate3D($origin,$axis,[Math]::Atan2($ty,$tx));$relief.Move($origin,[double[]]@(62,18,0));$jr.Boolean(2,$relief)
 $removed=$oldVolume-[double]$jr.Volume;if($removed -le 0.01){throw '线夹入口避让没有切除实体'}
 @([pscustomobject]@{零件='JR_CLAMP';项目='R12示意弯头的候选切向入口槽';旧体积_mm3=[Math]::Round($oldVolume,4);新体积_mm3=[Math]::Round([double]$jr.Volume,4);移除体积_mm3=[Math]::Round($removed,4)}) | Export-Csv (Join-Path $folder 'R12线夹入口_移除体积.csv') -NoTypeInformation -Encoding UTF8
 $physical=New-Object 'System.Collections.Generic.List[object]'
 foreach($p in $manifest){if($p.layer -eq 'W_CABLE_ENVELOPE'){continue};$o=$doc.HandleToObject($p.handle);$physical.Add([pscustomobject]@{id=$p.id;solid=$o;lift=($p.lift -eq 'True');rot=($p.rot -eq 'True');slide=($p.slide -eq 'True');chain=($p.layer -eq 'W_CHAIN');bounds=(BB $o)})}
 $all=@($physical.ToArray());$rotating=@($all | Where-Object {$_.lift -and $_.rot -and !$_.slide});$fixedLift=@($all | Where-Object {$_.lift -and !$_.rot -and !$_.slide});$static=@($all | Where-Object {!$_.lift -and !$_.rot -and !$_.slide -and !$_.chain})
 $tests=New-Object 'System.Collections.Generic.List[object]';$summary=New-Object 'System.Collections.Generic.List[object]'
 function CheckProbe($probe,$name,$objects){
  $bb=BB $probe;$candidates=0;$hits=0
  foreach($p in $objects){if(-not (Overlap $bb $p.bounds)){continue};$candidates++;$hit=$false;$piece=$probe.CheckInterference($p.solid,$true,[ref]$hit);$v=0.0;if($hit -and $null -ne $piece){$v=[double]$piece.Volume;$piece.Delete()};if($v -gt 0.000001){$hits++;$tests.Add([pscustomobject]@{检查=$name;对象=$p.id;相交体积_mm3=[Math]::Round($v,5)})}}
  $summary.Add([pscustomobject]@{检查=$name;对象数=$objects.Count;包络候选=$candidates;相交数=$hits});$probe.Delete()
 }
 # 使用 1.5 mm 半径实体包络覆盖假设 Ø3 mm 线缆的平面环、固定端和竖直出口。
 CheckProbe (Ring 62 90.5 75 78) '基准_线环全占用包络' $all
 CheckProbe (RadBox 87.5 97.5 -1.5 1.5 75 78) '基准_JF入口包络' $all
 CheckProbe ($space.AddCylinder([double[]]@(62,18,85),[double]1.5,[double]12)) '基准_JR竖直出口包络' $all
 # 65 个半径 1.65 的球覆盖 Ø3、R12 弯头的连续体积（相邻中心弧距约 0.295）。
 for($i=0;$i -le 64;$i++){$a=($i/64.0)*[Math]::PI/2;$p=[double[]]@(($px+$radius*[Math]::Sin($a)*$tx),($py+$radius*[Math]::Sin($a)*$ty),(76.5+$radius*(1-[Math]::Cos($a))));CheckProbe ($space.AddSphere($p,[double]1.65)) ('基准_R12弯头扩大包络_'+$i) $all}
 # 全圆/全高保守包络：按目标的运动属性分别检查，避免把不同时姿态当成实际碰撞。
 CheckProbe (Ring 87.5 97.5 75 78) '全角度_JF入口对随转件' $rotating
 CheckProbe (Ring 61.5 69 74.8 91) '全角度_JR出口与弯头对随升降固定件' $fixedLift
 CheckProbe (Ring 62 90.5 61 172) '全升降_线环对静止件' $static
 CheckProbe (RadBox 87.5 97.5 -1.5 1.5 61 172) '全升降_JF入口对静止件' $static
 CheckProbe (Ring 61.5 69 60.8 185) '全升降全角度_JR出口对静止件' $static
 $summary | Export-Csv (Join-Path $folder '线环Ø3_R12_空间探针覆盖.csv') -NoTypeInformation -Encoding UTF8
 $tests | Export-Csv (Join-Path $folder '线环Ø3_R12_空间探针相交.csv') -NoTypeInformation -Encoding UTF8
 # 示意线不是实体线缆；只在新文件中替换旧的参考线，不修改原装配。
 $oldPaths=@($doc.ModelSpace | Where-Object {$_.ObjectName -eq 'AcDb3dPolyline' -and $_.Layer -eq 'W_LOOP_PATH'})
 if($oldPaths.Count -ne 1){throw '原参考线数量异常'};$oldPaths[0].Delete()
 $ss=$doc.SelectionSets.Add('r12_sat');$ss.Select(5);$doc.Export((Join-Path $folder '车库_v7_走线优化_R12'),'SAT',$ss);$ss.Delete()
 $points=New-Object 'System.Collections.Generic.List[double]';$rEnd=[Math]::Sqrt($px*$px+$py*$py);$aEnd=[Math]::Atan2($py,$px)+4*[Math]::PI
 $points.Add(96*[Math]::Cos($aStart));$points.Add(96*[Math]::Sin($aStart));$points.Add(76.5)
 for($i=0;$i -le 140;$i++){$t=$i/140.0;$r=89+($rEnd-89)*$t;$a=$aStart+($aEnd-$aStart)*$t;$points.Add($r*[Math]::Cos($a));$points.Add($r*[Math]::Sin($a));$points.Add(76.5)}
 for($i=1;$i -le 64;$i++){$a=($i/64.0)*[Math]::PI/2;$points.Add($px+$radius*[Math]::Sin($a)*$tx);$points.Add($py+$radius*[Math]::Sin($a)*$ty);$points.Add(76.5+$radius*(1-[Math]::Cos($a)))}
 $points.Add(62);$points.Add(18);$points.Add(89.5)
 $ref=$space.Add3DPoly([double[]]$points.ToArray());$ref.Layer='W_LOOP_PATH';$doc.Regen(1);$doc.SaveAs($target,64)
 Write-Host ('WIRE_SPACE checks='+$summary.Count+' hits='+$tests.Count+' points='+($points.Count/3))
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
