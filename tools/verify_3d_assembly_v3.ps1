param(
    [string]$Folder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\cad\三维装配_初步校核')
)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("00000016-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVerifyAssemblyOleFilter {
    [PreserveSig] int HandleInComingCall(int type, IntPtr caller, int tick, IntPtr info);
    [PreserveSig] int RetryRejectedCall(IntPtr callee, int tick, int rejectType);
    [PreserveSig] int MessagePending(IntPtr callee, int tick, int pendingType);
}
public class VerifyAssemblyOleFilter : IVerifyAssemblyOleFilter {
    [DllImport("Ole32.dll")] private static extern int CoRegisterMessageFilter(IVerifyAssemblyOleFilter f, out IVerifyAssemblyOleFilter old);
    public static void Register() { IVerifyAssemblyOleFilter old; CoRegisterMessageFilter(new VerifyAssemblyOleFilter(), out old); }
    public int HandleInComingCall(int t, IntPtr c, int tick, IntPtr i) { return 0; }
    public int RetryRejectedCall(IntPtr c, int tick, int t) { return tick < 30000 ? 200 : -1; }
    public int MessagePending(IntPtr c, int tick, int t) { return 2; }
}
'@
[VerifyAssemblyOleFilter]::Register()
$folder=(Resolve-Path -LiteralPath $Folder).Path
$dwg=Join-Path $folder '车库_两层三维装配_一层载盘.dwg'
$sat=Join-Path $folder '车库_两层三维实体_一层载盘.SAT'
$manifest=Import-Csv -LiteralPath (Join-Path $folder '模型零件与范围.csv') -Encoding UTF8
$app=[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.25')
$previous=$app.ActiveDocument
$dwgDoc=$null; $importDoc=$null; $openedHere=$false
try {
    foreach($existing in $app.Documents) {
        if ($existing.FullName -eq $dwg) { $dwgDoc=$existing; break }
    }
    if ($null -eq $dwgDoc) { $dwgDoc=$app.Documents.Open($dwg,$true); $openedHere=$true }
    $solidCount=0; $highlightCount=0
    foreach($entity in $dwgDoc.ModelSpace) {
        if($entity.ObjectName -eq 'AcDb3dSolid') {
            $solidCount++
            if($entity.Layer -eq 'INTERFERENCE') { $highlightCount++ }
        }
    }
    if($solidCount -ne ($manifest.Count+6) -or $highlightCount -ne 6) {
        throw ('DWG 实体数量不符：'+$solidCount+'，红色干涉体：'+$highlightCount)
    }
    $deckVolumes=@{}
    foreach($part in $manifest) {
        $entity=$dwgDoc.HandleToObject($part.句柄)
        if($entity.ObjectName -ne 'AcDb3dSolid' -or $entity.Layer -ne $part.图层) {
            throw ('DWG 零件与清单不符：'+$part.编号)
        }
        $low=$null; $high=$null
        $entity.GetBoundingBox([ref]$low,[ref]$high)
        $expectedLow=@([double]$part.最小X_mm,[double]$part.最小Y_mm,[double]$part.最小Z_mm)
        $expectedHigh=@([double]$part.最大X_mm,[double]$part.最大Y_mm,[double]$part.最大Z_mm)
        for($i=0;$i -lt 3;$i++) {
            if([Math]::Abs($low[$i]-$expectedLow[$i]) -gt 0.002 -or
               [Math]::Abs($high[$i]-$expectedHigh[$i]) -gt 0.002) {
                throw ('DWG 零件包络与清单不符：'+$part.编号)
            }
        }
        if($part.编号 -in @('DECK_L1','DECK_L2')) { $deckVolumes[$part.编号]=[double]$entity.Volume }
    }
    $areaCheck=Join-Path $PSScriptRoot 'check_deck_3d_v3.py'
    & py $areaCheck $deckVolumes['DECK_L1'] $deckVolumes['DECK_L2']
    if($LASTEXITCODE -ne 0) { throw '甲板三维体积与二维轮廓核对失败。' }
    $template=Join-Path $env:LOCALAPPDATA 'Autodesk\AutoCAD 2025\R25.0\chs\Template\acadiso.dwt'
    $importDoc=$app.Documents.Add($template)
    $null=$importDoc.Import($sat,[double[]]@(0,0,0),1.0)
    $imported=@($importDoc.ModelSpace | Where-Object { $_.ObjectName -eq 'AcDb3dSolid' }).Count
    if($imported -ne $manifest.Count) { throw ('SAT 重新导入实体数量不符：'+$imported) }
    Write-Output ('DWG 重开核对通过：'+$manifest.Count+' 个零件实体 + '+$highlightCount+' 个干涉高亮。')
    Write-Output ('SAT 回导 AutoCAD 核对通过：'+$imported+' 个三维实体；SolidWorks 导入未实测。')
} finally {
    if($null -ne $importDoc) { $importDoc.Close($false) }
    if($openedHere -and $null -ne $dwgDoc) { $dwgDoc.Close($false) }
    if($null -ne $previous) {
        try { $previous.Activate() } catch { Write-Host '原活动文档已关闭，跳过视图恢复。' }
    }
}
