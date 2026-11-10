param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线优化安装复核'))
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition');$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
$folder=(Resolve-Path -LiteralPath $Folder).Path
$manifest=Import-Csv (Join-Path $folder '装配清单.csv') -Encoding UTF8
$app=New-Object -ComObject 'AutoCAD.Application.25';$app.Visible=$false;$doc=$null
try {
 $doc=$app.Documents.Open((Join-Path $folder '车库_v7_走线优化.dwg'),$true)
 $origin=[double[]]@(0,0,0);$axis=[double[]]@(0,0,1);$angle=67.5
 $slide=@($manifest | Where-Object {$_.slide -eq 'True'} | ForEach-Object {[pscustomobject]@{id=$_.id;solid=$doc.HandleToObject($_.handle)}})
 $chain=@($manifest | Where-Object {$_.layer -eq 'W_CHAIN'} | ForEach-Object {[pscustomobject]@{id=$_.id;solid=$doc.HandleToObject($_.handle)}})
 function BB($o){$lo=$null;$hi=$null;$o.GetBoundingBox([ref]$lo,[ref]$hi);return ,@($lo,$hi)}
 function Overlap($a,$b){for($k=0;$k -lt 3;$k++){if($a[1][$k] -le $b[0][$k]+0.00001 -or $b[1][$k] -le $a[0][$k]+0.00001){return $false}};return $true}
 $rows=New-Object 'System.Collections.Generic.List[object]';$coverage=New-Object 'System.Collections.Generic.List[object]'
 foreach($u in @(0,34.5,69,103.5,138)){
  foreach($p in $slide){if($u -ne 0){$p.solid.Move($origin,[double[]]@($u,0,0))};$p.solid.Rotate3D($origin,$axis,$angle*[Math]::PI/180)}
  $n=$rows.Count
  foreach($a in $chain){$ab=BB $a.solid;foreach($b in $slide){if(-not (Overlap $ab (BB $b.solid))){continue};$hit=$false;$piece=$a.solid.CheckInterference($b.solid,$true,[ref]$hit);if($hit -and $null -ne $piece){$v=[double]$piece.Volume;if($v -gt 0.000001){$rows.Add([pscustomobject]@{Z=100;角度=$angle;行程=$u;拖链=$a.id;对象=$b.id;相交体积_mm3=[Math]::Round($v,4)})};$piece.Delete()}}}
  foreach($p in $slide){$p.solid.Rotate3D($origin,$axis,(-$angle*[Math]::PI/180));if($u -ne 0){$p.solid.Move($origin,[double[]]@(-$u,0,0))}}
  $coverage.Add([pscustomobject]@{Z=100;角度=$angle;行程=$u;相交数=($rows.Count-$n)})
 }
 $rows | Export-Csv (Join-Path $folder '非车位角度_推拉相交.csv') -NoTypeInformation -Encoding UTF8
 $coverage | Export-Csv (Join-Path $folder '非车位角度_推拉覆盖.csv') -NoTypeInformation -Encoding UTF8
 Write-Host ('OFF_AXIS hits='+$rows.Count)
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
