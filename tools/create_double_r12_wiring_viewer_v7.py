"""从 AutoCAD 导出的实体网格制作离线、基准姿态的局部三维预览。"""
from __future__ import annotations

import base64
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs' / 'cad' / '三维装配_v7_走线优化安装复核'
MESH = OUT / '三维预览网格_双端R12'
manifest = json.loads((MESH / 'manifest.json').read_text(encoding='utf-8-sig'))
scene = []
worst = 0.0
for obj in manifest:
    data = (MESH / obj['file']).read_bytes()
    n = struct.unpack_from('<I', data, 80)[0]
    if 84 + n * 50 != len(data) or not n:
        raise ValueError('STL 文件异常：' + obj['id'])
    lo = [float('inf')]*3
    hi = [float('-inf')]*3
    for i in range(n):
        values = struct.unpack_from('<9f', data, 84+i*50+12)
        for j in range(3):
            for k in range(3):
                lo[k] = min(lo[k], values[j*3+k]); hi[k] = max(hi[k], values[j*3+k])
    # AutoCAD 的 STLOUT 为每个实体平移到正坐标；按清单的基准包围盒移回装配坐标。
    expected_lo = [float(obj['xyz'[i]+'0']) for i in range(3)]
    expected_hi = [float(obj['xyz'[i]+'1']) for i in range(3)]
    error = max(abs((hi[i]-lo[i])-(expected_hi[i]-expected_lo[i])) for i in range(3))
    if error > 0.5:
        raise ValueError(f"预览网格范围与 CAD 清单偏差过大：{obj['id']}，{error:.3f} mm")
    worst = max(worst, error)
    scene.append({'id': obj['id'], 'layer': obj['layer'], 'offset': [expected_lo[i]-lo[i] for i in range(3)], 'data': base64.b64encode(data).decode('ascii')})

path = [96*math.cos(math.radians(67.5)),96*math.sin(math.radians(67.5)),76.5]
a_start=math.radians(67.5);entry_end=math.radians(81.4868355184167);radius=12
px,py=63.36313637853419,6.0776739176653685
tx,ty=-0.11359469821118306,0.993527173527886
for i in range(65):
    a=i/64*entry_end;u=88-radius*math.sin(a);w=radius*(1-math.cos(a))
    path.extend((u*math.cos(a_start)-w*math.sin(a_start),u*math.sin(a_start)+w*math.cos(a_start),76.5))
r_start=math.hypot(u,w);a_spiral=a_start+math.atan2(w,u);r_end=math.hypot(px,py);a_end=math.atan2(py,px)+4*math.pi
for i in range(1,181):
    t=i/180;r=r_start+(r_end-r_start)*t;a=a_spiral+(a_end-a_spiral)*t
    path.extend((r*math.cos(a),r*math.sin(a),76.5))
for i in range(1,65):
    a=i/64*math.pi/2
    path.extend((px+radius*math.sin(a)*tx,py+radius*math.sin(a)*ty,76.5+radius*(1-math.cos(a))))
path.extend((62,18,89.5))

template = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>v7 走线优化 · 三维试配</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#eaf0f3;color:#17334a;font:15px "Microsoft YaHei",sans-serif}
header{padding:17px 24px 12px;background:#fff;border-bottom:1px solid #d6e1e7}
h1{font-size:23px;margin:0 0 6px}p{margin:0;line-height:1.55;color:#5c7182}
.warning{color:#ae3f38;font-weight:bold}.layout{display:grid;grid-template-columns:minmax(0,1fr) 265px;height:calc(100vh - 110px);min-height:490px}
#view{position:relative;overflow:hidden}canvas{display:block}.side{background:#fff;padding:18px;border-left:1px solid #d6e1e7;overflow:auto}
.side h2{font-size:16px;margin:0 0 10px}.side p{font-size:13px;margin:12px 0}.item{display:flex;gap:8px;align-items:center;margin:12px 0}
.swatch{width:14px;height:14px;border-radius:3px}.buttons{display:flex;gap:8px;margin:16px 0}button{border:1px solid #bdcbd2;background:#f6f9fa;border-radius:6px;padding:7px 10px;color:#17334a;cursor:pointer}
.overlay{position:absolute;left:16px;bottom:15px;background:#ffffffdf;padding:9px 12px;border-radius:7px;color:#516979;pointer-events:none}
@media(max-width:720px){.layout{display:block;height:auto}#view{height:62vh}.side{border:0}}
</style></head><body>
<header><h1>v7 走线优化 · 三维试配</h1><p>基准姿态 ZL=100、θ=0，显示 __COUNT__ 个重点实体；拖链为简化试配，线环为占用区和参考线。 <span class="warning">真实线材与紧固方式待验证。</span></p></header>
<div class="layout"><div id="view"><div class="overlay">鼠标左键旋转 · 滚轮缩放 · 右键平移</div></div><aside class="side">
<h2>显示部件</h2>
<label class="item"><input type="checkbox" data-group="chain" checked><span class="swatch" style="background:#07899a"></span>升降拖链</label>
<label class="item"><input type="checkbox" data-group="bracket" checked><span class="swatch" style="background:#e2a43a"></span>支架、导槽和线夹</label>
<label class="item"><input type="checkbox" data-group="fastener" checked><span class="swatch" style="background:#335da9"></span>候选紧固件包络</label>
<label class="item"><input type="checkbox" data-group="zone" checked><span class="swatch" style="background:#a867c6"></span>线环候选占用区</label>
<label class="item"><input type="checkbox" data-group="path" checked><span class="swatch" style="background:#e32b8a"></span>线环中心线（示意）</label>
<label class="item"><input type="checkbox" data-group="mechanism" checked><span class="swatch" style="background:#597f91"></span>转台与升降件</label>
<label class="item"><input type="checkbox" data-group="deck" checked><span class="swatch" style="background:#b8cbd3"></span>两层甲板</label>
<label class="item"><input type="checkbox" data-group="tray" checked><span class="swatch" style="background:#78a7bb"></span>托盘与车辆包络</label>
<label class="item"><input type="checkbox" data-group="frame" checked><span class="swatch" style="background:#8a9ea8"></span>底板和立柱</label>
<div class="buttons"><button id="reset">复位视角</button><button id="top">俯视</button></div>
<p>透明几何便于看清内部。中心线不是真实电缆轨迹；这里不是运动仿真，也没有显示全部螺钉和线缆，请结合完整 DWG 和调整位置图查看。</p>
</aside></div>
<script src="../vendor/three.min.js"></script><script src="../vendor/OrbitControls.js"></script>
<script>
const input = __SCENE__;
const pathCoordinates = __PATH__;
const mount=document.getElementById('view'), scene=new THREE.Scene();scene.background=new THREE.Color(0xeaf0f3);
const camera=new THREE.PerspectiveCamera(38,1,0.5,4000);camera.up.set(0,0,1);
const renderer=new THREE.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});renderer.setPixelRatio(1);mount.appendChild(renderer.domElement);
const controls=new THREE.OrbitControls(camera,renderer.domElement);controls.target.set(0,0,100);controls.enableDamping=true;
scene.add(new THREE.HemisphereLight(0xffffff,0x6d8491,1.0));const sun=new THREE.DirectionalLight(0xffffff,0.7);sun.position.set(260,400,600);scene.add(sun);
const groups={};for(const n of ['chain','bracket','fastener','zone','path','mechanism','deck','tray','frame']){groups[n]=new THREE.Group();scene.add(groups[n]);}
function category(layer){if(layer==='W_CHAIN')return 'chain';if(layer==='W_BRACKET'||layer==='W_CLAMP'||layer==='W_GUIDE')return 'bracket';if(layer==='W_FASTENER')return 'fastener';if(layer==='W_CABLE_ENVELOPE')return 'zone';if(layer.startsWith('DECK'))return 'deck';if(layer==='TRAY'||layer==='CAR_ENVELOPE')return 'tray';if(layer==='BASE'||layer==='FRAME')return 'frame';return 'mechanism';}
const palette={chain:[0x07899a,1],bracket:[0xe0a038,1],fastener:[0x335da9,1],zone:[0xa466c6,0.33],mechanism:[0x5e8293,1],deck:[0xa9bdc7,0.30],tray:[0x7ea9bb,0.33],frame:[0x93a4ad,0.33]};
function geometry(encoded){const b=atob(encoded),u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);const d=new DataView(u.buffer),n=d.getUint32(80,true),verts=new Float32Array(n*9),norms=new Float32Array(n*9);
for(let i=0;i<n;i++){let offset=84+i*50;let x=d.getFloat32(offset,true),y=d.getFloat32(offset+4,true),z=d.getFloat32(offset+8,true);for(let j=0;j<3;j++){let k=i*9+j*3;norms[k]=x;norms[k+1]=y;norms[k+2]=z;for(let a=0;a<3;a++)verts[k+a]=d.getFloat32(offset+12+j*12+a*4,true);}}
const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.BufferAttribute(verts,3));geo.setAttribute('normal',new THREE.BufferAttribute(norms,3));return geo;}
for(const obj of input){const key=category(obj.layer),[color,opacity]=palette[key];const material=new THREE.MeshStandardMaterial({color,transparent:opacity<1,opacity,depthWrite:opacity===1,side:THREE.DoubleSide,roughness:.75});let mesh=new THREE.Mesh(geometry(obj.data),material);mesh.position.set(...obj.offset);mesh.name=obj.id;groups[key].add(mesh);}
const pathGeo=new THREE.BufferGeometry();pathGeo.setAttribute('position',new THREE.Float32BufferAttribute(pathCoordinates,3));groups.path.add(new THREE.Line(pathGeo,new THREE.LineBasicMaterial({color:0xe32b8a,depthTest:false})));
for(const c of document.querySelectorAll('[data-group]'))c.addEventListener('change',()=>groups[c.dataset.group].visible=c.checked);
function reset(){camera.position.set(510,610,420);controls.target.set(0,0,100);controls.update();}reset();
document.getElementById('reset').onclick=reset;document.getElementById('top').onclick=()=>{camera.position.set(0.01,0,850);controls.target.set(0,0,100);controls.update();};
function resize(){const w=mount.clientWidth,h=mount.clientHeight;camera.aspect=w/h;camera.updateProjectionMatrix();renderer.setSize(w,h)}window.addEventListener('resize',resize);resize();
function draw(){requestAnimationFrame(draw);controls.update();renderer.render(scene,camera)}draw();
</script></body></html>'''
result = template.replace('__SCENE__', json.dumps(scene, ensure_ascii=False, separators=(',', ':'))).replace('__PATH__',json.dumps(path,separators=(',', ':'))).replace('__COUNT__',str(len(scene)))
(OUT / '走线三维预览_双端R12.html').write_text(result, encoding='utf-8')
print(f'预览包含 {len(scene)} 个实体；网格范围最大偏差 {worst:.3f} mm。')
