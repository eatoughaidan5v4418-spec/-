param([string]$Folder=(Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) 'docs\archive\cad\三维装配_v4_干涉调整'))
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVerifyV4OleFilter {
    [PreserveSig] int HandleInComingCall(int type, IntPtr caller, int tick, IntPtr info);
    [PreserveSig] int RetryRejectedCall(IntPtr callee, int tick, int rejectType);
    [PreserveSig] int MessagePending(IntPtr callee, int tick, int pendingType);
}
public class VerifyV4OleFilter : IVerifyV4OleFilter {
    [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IVerifyV4OleFilter f, out IVerifyV4OleFilter old);
    public static void Register() { IVerifyV4OleFilter old; CoRegisterMessageFilter(new VerifyV4OleFilter(), out old); }
    public int HandleInComingCall(int t, IntPtr c, int tick, IntPtr i) { return 0; }
    public int RetryRejectedCall(IntPtr c, int tick, int t) { return tick < 30000 ? 200 : -1; }
    public int MessagePending(IntPtr c, int tick, int t) { return 2; }
}
'@
[VerifyV4OleFilter]::Register()
$folder=(Resolve-Path -LiteralPath $Folder).Path
$dwg=Join-Path $folder '车库_两层三维装配_v4.dwg'
$sat=Join-Path $folder '车库_两层三维实体_v4.SAT'
$manifest=Import-Csv -LiteralPath (Join-Path $folder '模型零件与范围.csv') -Encoding UTF8
$app=[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25')
$previous=$app.ActiveDocument
$dwgDoc=$null; $importDoc=$null; $openedHere=$false
try {
    foreach($existing in $app.Documents) { if($existing.FullName -eq $dwg) { $dwgDoc=$existing; break } }
    if($null -eq $dwgDoc) { $dwgDoc=$app.Documents.Open($dwg,$true); $openedHere=$true }
    $count=0
    foreach($entity in $dwgDoc.ModelSpace) {
        if($entity.ObjectName -eq 'AcDb3dSolid') { $count++ }
    }
    if($count -ne $manifest.Count) { throw ('DWG 实体数量不符：'+$count+' / '+$manifest.Count) }
    foreach($part in $manifest) {
        $entity=$dwgDoc.HandleToObject($part.句柄)
        if($entity.ObjectName -ne 'AcDb3dSolid' -or $entity.Layer -ne $part.图层) {
            throw ('DWG 零件和清单不符：'+$part.编号)
        }
        if([Math]::Abs([double]$entity.Volume-[double]$part.体积_mm3) -gt 0.001) {
            throw ('DWG 体积和清单不符：'+$part.编号)
        }
        $low=$null; $high=$null
        $entity.GetBoundingBox([ref]$low,[ref]$high)
        $expectedLow=@([double]$part.最小X_mm,[double]$part.最小Y_mm,[double]$part.最小Z_mm)
        $expectedHigh=@([double]$part.最大X_mm,[double]$part.最大Y_mm,[double]$part.最大Z_mm)
        for($i=0;$i -lt 3;$i++) {
            if([Math]::Abs($low[$i]-$expectedLow[$i]) -gt 0.002 -or
               [Math]::Abs($high[$i]-$expectedHigh[$i]) -gt 0.002) {
                throw ('DWG 零件包络和清单不符：'+$part.编号)
            }
        }
    }
    $template=Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
    $importDoc=$app.Documents.Add($template)
    $null=$importDoc.Import($sat,[double[]]@(0,0,0),1.0)
    $imported=@($importDoc.ModelSpace | Where-Object { $_.ObjectName -eq 'AcDb3dSolid' }).Count
    if($imported -ne $manifest.Count) { throw ('SAT 回导数量不符：'+$imported) }
    Write-Output ('DWG 重开检查通过：'+$count+' 个实体，句柄、图层、范围和体积均匹配。')
    Write-Output ('SAT 回导 AutoCAD 通过：'+$imported+' 个实体；SolidWorks 未实测。')
} finally {
    if($null -ne $importDoc) { $importDoc.Close($false) }
    if($openedHere -and $null -ne $dwgDoc) { $dwgDoc.Close($false) }
    if($null -ne $previous) { try { $previous.Activate() } catch { Write-Host '原活动文档已关闭，跳过视图恢复。' } }
}
