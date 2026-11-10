param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线复核完成'))
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition');$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
$folder=(Resolve-Path -LiteralPath $Folder).Path
$manifest=Import-Csv (Join-Path $folder '装配清单.csv') -Encoding UTF8
$rows=Import-Csv (Join-Path $folder '姿态_实体相交.csv') -Encoding UTF8
$baseline=@($rows | Where-Object {$_.阶段 -eq '基准'}).Count
if($manifest.Count -ne 340){throw ('清单实体数量错误：'+$manifest.Count)}
if(@($manifest | Where-Object {$_.layer -eq 'W_CHAIN'}).Count -ne 20){throw '拖链分段数量错误'}
$app=New-Object -ComObject 'AutoCAD.Application.25';$app.Visible=$false;$doc=$null;$import=$null
try {
 $dwg=Join-Path $folder '车库_v7_走线候选_含示意线.dwg'
 if(-not (Test-Path -LiteralPath $dwg)){$dwg=Join-Path $folder '车库_v7_走线候选.dwg'}
 $doc=$app.Documents.Open($dwg,$true)
 foreach($p in $manifest){
  $obj=$doc.HandleToObject($p.handle)
  if($obj.ObjectName -ne 'AcDb3dSolid' -or $obj.Layer -ne $p.layer){throw ('实体、图层或句柄不符：'+$p.id)}
  $lo=$null;$hi=$null;$obj.GetBoundingBox([ref]$lo,[ref]$hi)
  $expectLo=@([double]$p.x0,[double]$p.y0,[double]$p.z0);$expectHi=@([double]$p.x1,[double]$p.y1,[double]$p.z1)
  for($i=0;$i -lt 3;$i++){if([Math]::Abs($lo[$i]-$expectLo[$i]) -gt 0.002 -or [Math]::Abs($hi[$i]-$expectHi[$i]) -gt 0.002){throw ('实体包络不符：'+$p.id)}}
 }
 $solids=@($doc.ModelSpace | Where-Object {$_.ObjectName -eq 'AcDb3dSolid'}).Count
 $clashes=@($doc.ModelSpace | Where-Object {$_.ObjectName -eq 'AcDb3dSolid' -and $_.Layer -eq 'W_INTERFERENCE'}).Count
 if($clashes -ne $baseline -or $solids -ne $manifest.Count+$baseline){throw ("DWG 数量不符：总 $solids，相交体 $clashes，基准 $baseline")}
 $paths=@($doc.ModelSpace | Where-Object {$_.ObjectName -eq 'AcDb3dPolyline' -and $_.Layer -eq 'W_LOOP_PATH'})
 if($paths.Count -ne 1){throw ('旋转示意线数量错误：'+$paths.Count)}
 $coords=$paths[0].Coordinates
 if($coords.Count -ne 423 -or [Math]::Abs($coords[0]-88*[Math]::Cos(67.5*[Math]::PI/180)) -gt .001 -or [Math]::Abs($coords[1]-88*[Math]::Sin(67.5*[Math]::PI/180)) -gt .001 -or [Math]::Abs($coords[420]-58) -gt .001 -or [Math]::Abs($coords[421]-18) -gt .001 -or [Math]::Abs($coords[422]-82.5) -gt .001){throw '旋转示意线的端点或点数不符'}
 $template=Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
 $import=$app.Documents.Add($template)
 $null=$import.Import((Join-Path $folder '车库_v7_走线候选.SAT'),[double[]]@(0,0,0),1.0)
 $n=@($import.ModelSpace | Where-Object {$_.ObjectName -eq 'AcDb3dSolid'}).Count
 if($n -ne $manifest.Count){throw ('SAT 回导数量不符：'+$n)}
 @("DWG 重开通过：$($manifest.Count) 个装配实体、$clashes 个基准相交体、1 条旋转中心示意线；句柄、图层、包络和示意线端点符合清单。", "SAT 回导 AutoCAD：$n 个装配实体；不包含相交标记和示意线；SolidWorks 未实测。") | Set-Content (Join-Path $folder '验证_重开.txt') -Encoding UTF8
 Write-Host ("DWG OK: $solids solids; SAT OK: $n solids")
} finally {if($null -ne $import){$import.Close($false)};if($null -ne $doc){$doc.Close($false)};$app.Quit()}
