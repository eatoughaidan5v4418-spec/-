param([string]$Folder=(Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\图纸_v6_夹紧止推限位'))
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVerifyV6DrawFilter {
 [PreserveSig] int HandleInComingCall(int t, IntPtr c, int k, IntPtr i);
 [PreserveSig] int RetryRejectedCall(IntPtr c, int k, int r);
 [PreserveSig] int MessagePending(IntPtr c, int k, int t);
}
public class VerifyV6DrawFilter : IVerifyV6DrawFilter {
 [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IVerifyV6DrawFilter f, out IVerifyV6DrawFilter old);
 public static void Register() { IVerifyV6DrawFilter old; CoRegisterMessageFilter(new VerifyV6DrawFilter(),out old); }
 public int HandleInComingCall(int t, IntPtr c, int k, IntPtr i) { return 0; }
 public int RetryRejectedCall(IntPtr c, int k, int r) { return k<30000 ? 200 : -1; }
 public int MessagePending(IntPtr c, int k, int t) { return 2; }
}
'@
[VerifyV6DrawFilter]::Register()
$folder=(Resolve-Path -LiteralPath $Folder).Path
$files=@(Get-ChildItem -LiteralPath $folder -Filter '*.dwg' -File | Sort-Object Name)
if($files.Count -ne 11) { throw ('应有11张DWG，实际 '+$files.Count) }
$app=New-Object -ComObject 'AutoCAD.Application.25'
$app.Visible=$false
$doc=$null
try {
 foreach($file in $files) {
  $dxf=Join-Path $folder ([IO.Path]::GetFileNameWithoutExtension($file.Name)+'.dxf')
  if(-not (Test-Path -LiteralPath $dxf)) { throw ('缺少对应DXF：'+$file.Name) }
  $expected=& py -X utf8 -c 'import sys; from pathlib import Path; sys.path.insert(0,sys.argv[1]); from check_cad_drawings_v3 import entities; print(len(entities(Path(sys.argv[2]))))' $PSScriptRoot $dxf
  if($LASTEXITCODE -ne 0) { throw ('DXF 读取失败：'+$file.Name) }
  $doc=$app.Documents.Open($file.FullName,$true)
  if($doc.ModelSpace.Count -ne [int]$expected) { throw ('DWG/DXF实体数不一致：'+$file.Name) }
  if([int]$doc.GetVariable('INSUNITS') -ne 4) { throw ('单位不是毫米：'+$file.Name) }
  $xmin=[double]::PositiveInfinity; $ymin=$xmin; $xmax=[double]::NegativeInfinity; $ymax=$xmax
  foreach($entity in $doc.ModelSpace) {
   try {
    $lo=$null; $hi=$null; $entity.GetBoundingBox([ref]$lo,[ref]$hi)
    $xmin=[Math]::Min($xmin,$lo[0]); $ymin=[Math]::Min($ymin,$lo[1])
    $xmax=[Math]::Max($xmax,$hi[0]); $ymax=[Math]::Max($ymax,$hi[1])
   } catch { }
  }
  $view=$doc.ActiveViewport; $center=$view.Center
  if([double]::IsInfinity($xmin) -or $xmin -lt $center[0]-$view.Width/2-0.1 -or
     $xmax -gt $center[0]+$view.Width/2+0.1 -or $ymin -lt $center[1]-$view.Height/2-0.1 -or
     $ymax -gt $center[1]+$view.Height/2+0.1) { throw ('默认视图未完整包含图纸：'+$file.Name) }
  Write-Output ($file.Name+'：DWG/DXF '+$expected+' 个实体，单位与默认视图通过')
  $doc.Close($false); $doc=$null
 }
} finally {
 if($null -ne $doc) { $doc.Close($false) }
 $app.Quit()
}
