param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_v7_走线复核完成'))
$ErrorActionPreference='Stop'
# 使用与 v7 建模相同的 COM 忙碌重试机制。
$source=Get-Content (Join-Path $PSScriptRoot 'create_garage_assembly_v7.ps1') -Raw
$start=$source.IndexOf('Add-Type -TypeDefinition');$end=$source.IndexOf('if (-not $Probe)')
Invoke-Expression $source.Substring($start,$end-$start)
$folder=(Resolve-Path -LiteralPath $Folder).Path
$meshDir=Join-Path $folder '三维预览网格'
if(Test-Path -LiteralPath $meshDir){throw '预览网格目录已存在，拒绝覆盖'}
$null=New-Item -ItemType Directory -Path $meshDir
$manifest=Import-Csv (Join-Path $folder '装配清单.csv') -Encoding UTF8
$ids=@('BASE','DECK_L1','DECK_L2','LIFT_DISC','BEARING_BOTTOM','BEARING_RACE','BEARING_TOP',
 'TRANSFER_PLATE','CENTER_TRAY','TRAY_L1_45','TRAY_L2_45','CAR_L1_45','CAR_L2_45',
 'ROT_MOTOR_BODY','LIFT_ARM_22.5','LIFT_ARM_112.5','LIFT_ARM_202.5',
 'COLUMN_1','COLUMN_2','COLUMN_3','COLUMN_4')
$selected=@($manifest | Where-Object { ($ids -contains $_.id) -or $_.layer -like 'W_*' })
$app=New-Object -ComObject 'AutoCAD.Application.25';$app.Visible=$false;$doc=$null
try {
 $doc=$app.Documents.Open((Join-Path $folder '车库_v7_走线候选.dwg'),$true)
 $doc.SetVariable('FILEDIA',[int16]0);$doc.SetVariable('FACETRES',[double]3)
 $items=New-Object 'System.Collections.Generic.List[object]';$i=0
 foreach($p in $selected){
  $solid=$doc.HandleToObject($p.handle)
  if($solid.ObjectName -ne 'AcDb3dSolid' -or $solid.Layer -ne $p.layer){throw ('实体与清单不符：'+$p.id)}
  $temp=Join-Path $env:TEMP ('wire_view_'+[Guid]::NewGuid().ToString('N')+'.stl')
  $fn=$temp.Replace('\','/')
  $cmd='(progn (command "_.STLOUT" (handent "'+$solid.Handle+'") "" "_Y" "'+$fn+'") (princ))'+"`n"
  try {
   $doc.SendCommand($cmd)
   if(-not (Test-Path -LiteralPath $temp)){throw ('STL 未生成：'+$p.id)}
   $name=('part_{0:D3}.stl' -f $i);Copy-Item -LiteralPath $temp -Destination (Join-Path $meshDir $name)
   $items.Add([pscustomobject]@{id=$p.id;layer=$p.layer;file=$name;x0=$p.x0;y0=$p.y0;z0=$p.z0;x1=$p.x1;y1=$p.y1;z1=$p.z1})
   Write-Host ('PREVIEW '+$p.id)
  } finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
  $i++
 }
 $items | ConvertTo-Json | Set-Content (Join-Path $meshDir 'manifest.json') -Encoding UTF8
 Write-Host ('DONE '+$items.Count)
} finally {if($null -ne $doc){$doc.Close($false)};$app.Quit()}
