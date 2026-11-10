"""Complete the user's imported adapter schematic via the installed official CLI."""
from pathlib import Path
import base64
import json
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs' / '嘉立创原理图_双板_已连线_0805'
CLI = 'E:/lceda-pro/lceda-pro.exe'
SESSION = '9e0a6e37-511d-4455-8707-dc53e405e27d'
PROJECT = '985e424f192c4b7886df8a7fcba375a3'
PAGES = ['30968987fbc1647d', '8fa31840ba825b92']
LIB = '0819f05c4eef4c71ace90d822a990e87'
FPS = {'resistor': ('6cfdf2d0c1ca4752bd1a0125f55b71e9', 'R0805'),
       'capacitor': ('ccb32feceadc4298b406326a506ce8e7', 'C0805')}


def call(code):
    f = OUT / '_eda_operation.js'
    f.write_text(code, encoding='utf-8')
    r = subprocess.run([CLI, 'invoke', '--session', SESSION, '--code-file', str(f),
                        '--timeout', '120000'], capture_output=True, encoding='utf-8', timeout=150)
    for line in r.stdout.splitlines():
        if line.startswith('{"ok"'):
            data = json.loads(line)
            if not data['ok']:
                raise RuntimeError(data.get('error'))
            return data.get('value')
    raise RuntimeError(r.stdout + r.stderr)


def records(source):
    result = []
    for line in source.splitlines():
        if '||' in line:
            a, b = line.split('||', 1)
            result.append([json.loads(a), json.loads(b.rstrip('|'))])
    return result


def serialize(rows):
    return '\n'.join(json.dumps(a, ensure_ascii=False, separators=(',', ':')) + '||' +
                     json.dumps(b, ensure_ascii=False, separators=(',', ':')) + '|' for a, b in rows).rstrip('|')


def pin_nets(components, side):
    nets = {}
    for c in components:
        if c['kind'] == 'connector':
            nets[c['ref']] = {p['number']: p['name'] for p in c['pins'] if p['name'] != 'NC'}
    power = 'V3_S' if side else 'V3_M'
    drivers = [('S103', 'U', ['PD12', 'PF6', 'PF7'])] if side else [
        ('M101', 'Z', ['PA8', 'PA1', 'PD10']), ('M102', 'T', ['PA0', 'PB14', 'PE14'])]
    def add(ref, a, b):
        nets[ref] = {'1': a, '2': b}
    for pre, axis, gpios in drivers:
        for suffix, gpio, ext in zip(['STEP', 'DIR', 'EN'], gpios,
                                     [f'{axis}_STEP_EXT', f'{axis}_DIR_EXT', f'{axis}_EN_N_EXT']):
            add(f'R_{pre}_{axis}_{suffix}', 'MCU_' + gpio, ext)
        add(f'R_{pre}_{axis}_ENPU', power, f'{axis}_EN_N_EXT')
        add(f'C_{pre}_{axis}_VIO', power, 'GND')
    if not side:
        add('R_M_PWR', 'V3P3_OUT', power)
        for suffix in ['PWR_100N', 'PWR_10U', 'LAYER1', 'LAYER2']:
            add('C_M_' + suffix, power, 'GND')
        for bus, gpio in [('SDA', 'PB7'), ('SCL', 'PB6')]:
            add('R_M_' + bus, 'MCU_' + gpio, f'LAYER_{bus}_EXT')
            add('R_M_' + bus + '_PU', power, f'LAYER_{bus}_EXT')
        detectors = [('130','PG0'), ('131','PG1'), ('132','PG2'), ('140','PG3'),
                     ('150','PG4'), ('151','PG5'), ('141','PG6'), ('133','PG7'),
                     ('142','PD8'), ('143','PD9')]
        byref = {c['ref']: c for c in components}
        for suffix, gpio in detectors:
            c = byref['J_M' + suffix]
            ext = c['pins'][-1]['name']
            add('R_' + suffix + '_SER', ext, 'MCU_' + gpio)
            add('R_' + suffix + '_PU', power, 'MCU_' + gpio)
            add('C_' + suffix + '_FLT', 'MCU_' + gpio, 'GND')
            if len(c['pins']) == 3:
                add('C_' + suffix + '_VCC', power, 'GND')
    else:
        add('R_S_PWR', 'V3P3_CORE', power)
        add('R_S_TX', 'MCU_PB10', 'HMI_TO_SCREEN_RX')
        add('R_S_RX', 'HMI_FROM_SCREEN_TX', 'MCU_PB11')
        add('JP_HMI5', 'V5_EXT_S', 'VHMI_S')
        add('JP_HMI3', power, 'VHMI_S')
        for suffix in ['PWR_100N', 'PWR_10U']:
            add('C_S_' + suffix, power, 'GND')
        for suffix in ['HMI_100N', 'HMI_BULK']:
            add('C_S_' + suffix, 'VHMI_S', 'GND')
    assert set(nets) == {c['ref'] for c in components}
    return nets


def complete(source, components, side):
    rows = records(source)
    # Work from the pre-wiring import. A saved snapshot makes re-runs deterministic.
    rows = [r for r in rows if r[0]['type'] not in {'WIRE', 'LINE'} and
            not (r[0]['type'] == 'ATTR' and r[1].get('key') in {'NET', 'Relevance'})]
    refs = {b['parentId']: b['value'] for a, b in rows
            if a['type'] == 'ATTR' and b.get('key') == 'Designator'}
    byref = {c['ref']: c for c in components}
    delta = {}
    # Expand the spacing, keeping each symbol and its own annotations intact.
    for a, b in rows:
        if a['type'] == 'COMPONENT':
            c = byref[refs[a['id']]]
            extra = 120 if c['kind'] == 'connector' and c['ref'] not in {
                'J_M001', 'H_M001', 'J_S001', 'J_S002', 'H_S001'} else 0
            dx, dy = round(b['x'] * .8 + extra, 3), round(b['y'] * .3, 3)
            delta[a['id']] = (dx, dy)
            b['x'] += dx
            b['y'] += dy
            if c['kind'] in FPS:
                fp, name = FPS[c['kind']]
                b['attrs']['FootprintName'] = json.dumps({'uuid':fp, 'name':name, 'source':LIB})
                b['attrs']['Footprints'] = '[]'
    for a, b in rows:
        if a['type'] == 'ATTR' and b.get('parentId') in delta:
            dx, dy = delta[b['parentId']]
            # Invisible migrated attrs sometimes carry Cartesian y; their position is immaterial.
            if isinstance(b.get('x'), (int, float)): b['x'] += dx
            if isinstance(b.get('y'), (int, float)): b['y'] += dy
            c = byref[refs[b['parentId']]]
            if c['kind'] in FPS and b.get('key') == 'Footprint':
                b['value'] = FPS[c['kind']][0]
        elif a['type'] == 'TEXT':
            b['x'] *= 1.8
            b['y'] *= 1.3
            v = b.get('value', '')
            if '待连线原理图' in v or '本页没有导线' in v:
                b['value'] = '已连线：短导线 + 同名网络标签电气相连；电阻、电容及0Ω选择电阻统一0805。'
            elif '所有端点保留给你' in v:
                b['value'] = '同名网络相连；MCU原始网与EXT接口网之间经过串联电阻。NC引脚保持悬空。'
            elif '封装未绑定' in v or '原理图符号未绑定' in v:
                b['value'] = '电阻R0805 / 电容C0805；连接器封装及PCB由用户后续完成。原线针序须核对。'
            elif '这里只画原理图元件' in v:
                b['value'] = '仅原理图；电阻电容0805，连接器封装由用户选择。'
        elif a['type'] == 'RECT':
            for k in ['dotX1', 'dotX2']: b[k] *= 1.8
            for k in ['dotY1', 'dotY2']: b[k] *= 1.3
    max_ticket = max(a.get('ticket', 0) for a,b in rows)
    def append(typ, body):
        nonlocal max_ticket
        max_ticket += 1
        ident = uuid.uuid4().hex[:16]
        rows.append([{'type':typ,'ticket':max_ticket,'id':ident}, body])
        return ident
    for ident, ref in refs.items():
        c = byref[ref]
        if c['kind'] in FPS:
            # Ensure the attribute exists even if the import omitted an empty footprint.
            if not any(a['type']=='ATTR' and b.get('parentId')==ident and b.get('key')=='Footprint' for a,b in rows):
                append('ATTR', {'parentId':ident, 'key':'Footprint', 'value':FPS[c['kind']][0],
                                'keyVisible':False,'valueVisible':False,'x':0,'y':0,'zIndex':0})
    expected = pin_nets(components, side)
    connections = []
    for ident, ref in refs.items():
        c = byref[ref]
        dx, dy = delta[ident]
        for p in c['pins']:
            net = expected[ref].get(p['number'])
            if net is None: continue
            x, y = p['x']+dx, p['y']+dy
            if c['kind'] == 'connector':
                sign = -1 if p['x'] < c['x'] else 1
            else:
                sign = -1 if p['number']=='1' else 1
            end = x + sign * 30
            wire = append('WIRE', {'zIndex':1000})
            append('LINE', {'startX':x,'startY':y,'endX':end,'endY':y,'lineGroup':wire,
                            'strokeColor':None,'strokeWidth':None,'strokeStyle':None,
                            'fillColor':None,'fillStyle':None})
            append('ATTR', {'x':end,'y':y-3,'rotation':0,'fontSize':10,'fontFamily':None,
                            'fontWeight':False,'color':None,'align':'RIGHT_BOTTOM' if sign<0 else 'LEFT_BOTTOM',
                            'value':net,'key':'NET','parentId':wire,'keyVisible':False,
                            'valueVisible':True,'zIndex':1002})
            connections.append({'ref':ref,'pin':p['number'],'net':net,'x':x,'y':y})
    return serialize(rows), connections


def main():
    OUT.mkdir(exist_ok=True)
    manifest = json.loads((ROOT/'docs/嘉立创原理图_双板_v1/原理图对象与引脚核对.json').read_text('utf-8'))
    info = call('return await eda.dmt_Project.getCurrentProjectInfo();')
    if info['uuid'] != PROJECT:
        raise RuntimeError('User has switched projects; refusing to edit unrelated project')
    reports=[]
    for index, page in enumerate(PAGES):
        call(f'const tab=await eda.dmt_EditorControl.openDocument({json.dumps(page)}); '
             'if(!tab || !await eda.dmt_EditorControl.waitForDocumentReady(tab,15000)) throw Error("Page not ready"); return tab;')
        original = OUT/f'0{index+1}_导入原始快照.txt'
        if not original.exists():
            original.write_text(call('return await eda.sys_FileManager.getDocumentSource();'), 'utf-8')
        source, connections = complete(original.read_text('utf-8'), manifest[index]['components'], bool(index))
        (OUT/f'0{index+1}_已连线原理图源码.txt').write_text(source, 'utf-8')
        result = call('const ok=await eda.sys_FileManager.setDocumentSource('+json.dumps(source,ensure_ascii=False)+'); '
                      'if(!ok)throw Error("Source rejected"); const saved=await eda.sch_Document.save(); '
                      'if(!saved)throw Error("Save failed"); await eda.dmt_EditorControl.zoomToAllPrimitives(); '
                      'return {saved,components:(await eda.sch_PrimitiveComponent.getAll()).length,'
                      'wires:(await eda.sch_PrimitiveWire.getAll()).length};')
        reports.append({'page':page,'expected':connections,**result})
        print(json.dumps({'page':index+1,**result},ensure_ascii=False),flush=True)
    (OUT/'预期连接与写入结果.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2),'utf-8')
    netlist = call('return await eda.sch_Netlist.getNetlist();')
    (OUT/'嘉立创回读网表.json').write_text(netlist,'utf-8')
    actual = json.loads(netlist)
    byref = {c['props']['Designator']:c for c in actual['components'].values()}
    errors=[]
    for report in reports:
        for p in report['expected']:
            got=byref[p['ref']]['pinInfoMap'][p['pin']]['net']
            if got != p['net']: errors.append({**p,'actual':got})
    passives=[c for m in manifest for c in m['components'] if c['kind'] in FPS]
    for c in passives:
        if byref[c['ref']]['props'].get('Footprint') != FPS[c['kind']][0]:
            errors.append({'ref':c['ref'],'error':'Incorrect 0805 footprint'})
    verification={'component_count':len(byref),'connected_pins_checked':sum(len(r['expected']) for r in reports),
                  'passives_0805_checked':len(passives),'errors':errors,'project_uuid':PROJECT,
                  'client_version':'4.1.97','pcb_created':False}
    (OUT/'网表核对结果.json').write_text(json.dumps(verification,ensure_ascii=False,indent=2),'utf-8')
    print(json.dumps(verification,ensure_ascii=False),flush=True)
    if errors: raise RuntimeError('Netlist validation failed')
    exported=call('const f=await eda.sys_FileManager.getProjectFile("星火一号双板转接_已连线_0805",undefined,"epro2"); '
                  'if(!f)throw Error("Export failed"); const bytes=new Uint8Array(await f.arrayBuffer()); '
                  'let s=""; for(let i=0;i<bytes.length;i+=8192)s+=String.fromCharCode(...bytes.subarray(i,i+8192)); '
                  'return {name:f.name,data:btoa(s),size:f.size};')
    target=OUT/'星火一号双板转接_已连线_0805.epro2'
    target.write_bytes(base64.b64decode(exported['data']))
    print(json.dumps({'export':str(target),'bytes':target.stat().st_size},ensure_ascii=False),flush=True)
    call('const tab=await eda.dmt_EditorControl.openDocument("30968987fbc1647d"); '
         'await eda.dmt_EditorControl.activateDocument(tab); await eda.dmt_EditorControl.zoomToAllPrimitives(tab); return true;')


if __name__=='__main__': main()
