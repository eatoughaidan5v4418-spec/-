"""将调整位置 SVG 渲染成便于预览的 PNG。"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
folder = root / 'docs' / 'cad' / '三维装配_v7_走线优化安装复核'
edge = Path(r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
if not edge.exists():
    raise SystemExit('找不到 Microsoft Edge；SVG 仍可直接打开。')
for stem in ('01_甲板通道与支架_优化对照', '02_旋转导槽与线夹_优化方案', '03_运动互锁与拖链_风险示意'):
    with tempfile.TemporaryDirectory(prefix='wire-review-') as profile:
        result = subprocess.run([
            str(edge), '--headless', '--disable-gpu', '--hide-scrollbars',
            '--force-device-scale-factor=1', '--user-data-dir='+profile,
            '--window-size=2400,1720', '--screenshot='+str(folder / (stem+'.png')),
            (folder / (stem+'.svg')).as_uri(),
        ], capture_output=True, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    print(stem+'.png')

viewer = folder / '走线三维预览_双端R12.html'
if viewer.exists():
    with tempfile.TemporaryDirectory(prefix='wire-3d-') as profile:
        result = subprocess.run([
            str(edge), '--headless', '--use-gl=angle', '--use-angle=swiftshader',
            '--enable-unsafe-swiftshader', '--hide-scrollbars',
            '--force-device-scale-factor=1', '--user-data-dir='+profile,
            '--window-size=1800,1200', '--virtual-time-budget=3000',
            '--screenshot='+str(folder/'走线三维预览_双端R12.png'), viewer.as_uri(),
        ], capture_output=True, timeout=90, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    print('走线三维预览_双端R12.png')
