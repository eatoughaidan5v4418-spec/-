param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线复核完成'))
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition');$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
$folder=(Resolve-Path -LiteralPath $Folder).Path
$target=Join-Path $folder '车库_v7_走线候选_含示意线.dwg'
if(Test-Path -LiteralPath $target){throw '目标文件已存在，拒绝覆盖'}
$app=New-Object -ComObject 'AutoCAD.Application.25';$app.Visible=$false;$doc=$null
try {
 $doc=$app.Documents.Open((Join-Path $folder '车库_v7_走线候选.dwg'),$true)
 $layer=$doc.Layers.Add('W_LOOP_PATH');$layer.Color=[int16]6
 $points=New-Object 'System.Collections.Generic.List[double]';$rEnd=[Math]::Sqrt(58*58+18*18)
 $aStart=67.5*[Math]::PI/180;$aEnd=[Math]::Atan2(18,58)+4*[Math]::PI
 for($i=0;$i -le 140;$i++){$t=$i/140.0;$r=88+($rEnd-88)*$t;$a=$aStart+($aEnd-$aStart)*$t;$points.Add($r*[Math]::Cos($a));$points.Add($r*[Math]::Sin($a));$points.Add(82.5)}
 $ref=$doc.ModelSpace.Add3DPoly([double[]]$points.ToArray());$ref.Layer='W_LOOP_PATH'
 $doc.Regen(1);$doc.SaveAs($target,64)
 Write-Host ('DONE '+$ref.Handle+' '+$target)
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
