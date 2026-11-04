/* 基于硬件方案 v3（中央升降塔式）的概念模型。实际部件、传感器与控制器尚未接入。
 * 三维坐标映射：three.x = X（右），three.y = Z（上），three.z = -Y（Y 向后）。 */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const { Simulation, DIRS, GEOM, DOCK, MAX_LAYERS, levelZ, bayName, isDock, isShaft, isStorage } = GarageSimulation;
  // 竖向件位于车位缝隙（22.5° + k·90°），r = 140。
  const MEMBER_R = 140;
  const polar = (r, a) => [r * Math.cos(a * Math.PI / 180), r * Math.sin(a * Math.PI / 180)];
  const [ROD1, ROD2, SCREW, CHAIN] = [22.5, 202.5, 112.5, 67.5].map(a => polar(MEMBER_R, a));
  const params = new URLSearchParams(location.search);
  const sim = new Simulation(params.get('layers') === '1' ? 1 : 2);   // ?layers=1 打开一层样机
  let selected = null;
  let paused = false;
  let speed = 2;
  let lastUI = '';
  let renderScene = () => {};
  let syncScene = () => {};
  const deg = Math.PI / 180;

  function selectTray(id) {
    if (sim.status !== 'idle') return;
    const tray = sim.getTray(id);
    const at = tray && sim.locate(id);
    if (!tray || !at || at.lift) return;
    selected = id;
    updateUI();
  }

  function cellHTML(layer, dir) {
    if (isShaft(layer, dir)) return '<div class="cell lift-cell">DOCK 竖井</div>';
    const tray = sim.bays[layer][dir];
    const dock = isDock(layer, dir);
    const busy = sim.status !== 'idle';
    const type = !tray ? 'empty' : tray.hasCar ? 'has-car' : 'has-tray';
    const desc = !tray ? '无托盘' : tray.hasCar ? `有车 / ${tray.id}` : `空托盘 / ${tray.id}`;
    const chosen = tray && selected === tray.id;
    const selectable = tray && tray.hasCar && !dock && !busy;
    return `<button type="button" class="cell ${type} ${dock ? 'dock' : ''} ${chosen ? 'selected' : ''}" data-id="${tray ? tray.id : ''}" ${selectable ? '' : 'disabled'} aria-label="${bayName(layer, dir)}，${desc}"><b>${dock ? 'DOCK' : DIRS[dir].key + ' · ' + DIRS[dir].name}</b><small>${desc}</small></button>`;
  }

  function updateUI() {
    const busy = sim.status !== 'idle';
    const signature = JSON.stringify([
      sim.bays.map(slots => slots.map(t => t && [t.id, t.hasCar])), selected, sim.status, sim.label, sim.motor,
      Math.round(sim.lift.z), Math.round(sim.lift.theta), Math.round(sim.lift.fork), sim.lift.tray && sim.lift.tray.id,
      sim.log, sim.layerCount, sim.autoStage
    ]);
    if (signature === lastUI) return;
    lastUI = signature;
    const maps = [];
    for (let layer = sim.layerCount - 1; layer >= 0; layer--) {
      const cars = sim.bays[layer].filter(t => t && t.hasCar).length;
      const here = Math.abs(sim.lift.z - levelZ(layer)) <= GEOM.free + 0.01;
      const center = `<div class="cell lift-cell">${here ? '● 转运台' : '升降井'}</div>`;
      const grid = [3, 2, 1, 4, -1, 0, 5, 6, 7].map(d => d < 0 ? center : cellHTML(layer, d)).join('');
      const slots = DIRS.filter((_, d) => isStorage(layer, d)).length;
      maps.push(`<div class="floor-card"><div class="floor-head"><strong>${layer + 1}F · 甲板 Z=${levelZ(layer)}</strong><small>载车 ${cars} / ${slots}</small></div><div class="floor-grid cross">${grid}</div><div class="floor-caption"><span>↑ 后侧</span><span>↓ 前侧（用户）</span></div></div>`);
    }
    $('floor-maps').innerHTML = maps.join('');
    $('layer-badge').textContent = `${sim.layerCount}F`;
    const tray = selected ? sim.getTray(selected) : null;
    const at = tray && sim.locate(tray.id);
    $('selection-title').textContent = tray && at && !at.lift ? `${bayName(at.layer, at.dir)} · 托盘 ${tray.id}` : '请选择载车托盘';
    $('selection-detail').textContent = tray ? (tray.hasCar ? '当前有车，可执行取车' : '当前无车') : '存车无需选择，系统自动分配车位';
    const dock = sim.dockTray();
    const hasEmpty = sim.trays.some(t => !t.hasCar);
    $('store').disabled = busy || !hasEmpty || (dock && dock.hasCar);
    $('retrieve').disabled = busy || !tray || !tray.hasCar || !at || at.lift || isDock(at.layer, at.dir);
    $('selection-help').textContent = busy ? '运行期间不可切换操作。' : !hasEmpty ? '车库已满，只能取车。' : dock ? `DOCK 已预置空托盘 ${dock.id}，存车无需等待。` : '存车：调空托盘到 DOCK；取车：先选中载车托盘。';
    const labels = { idle: '待机', running: '运行中', paused: '已暂停', waiting: '等待确认', stopped: '已停止' };
    $('status-pill').textContent = labels[sim.status] || sim.status;
    $('status-pill').className = 'status-pill ' + (sim.status === 'waiting' ? 'waiting' : sim.status === 'stopped' ? 'stopped' : '');
    $('current-step').textContent = sim.label;
    $('motor-state').textContent = sim.status === 'paused' ? '演示暂停' : sim.motor;
    $('lift-height').innerHTML = `${Math.round(sim.lift.z)} <small>mm</small>`;
    $('lift-theta').innerHTML = `${Math.round(sim.lift.theta)} <small>°</small>`;
    $('lift-fork').innerHTML = `${Math.round(sim.lift.fork)} <small>mm</small>`;
    $('platform-state').textContent = sim.lift.tray ? sim.lift.tray.id : '无';
    $('dock-card').hidden = sim.status !== 'waiting';
    if (sim.status === 'waiting') {
      const storing = sim.operation.kind === 'store';
      $('dock-title').textContent = storing ? '请在 DOCK 放好车辆' : '请在 DOCK 取走车辆';
      $('dock-detail').textContent = storing ? '车辆放入托盘挡块内，手离开光电区后点击确认。' : '取走车辆后点击确认；空托盘将留在 DOCK 供下次存车。';
      $('confirm-dock').firstChild.textContent = storing ? '已放车，继续 ' : '已取车，完成 ';
      $('cancel-dock').hidden = !storing;
    }
    $('pause').disabled = sim.status !== 'running' && sim.status !== 'paused';
    $('pause').textContent = sim.status === 'paused' ? '继续' : '暂停';
    $('stop').disabled = sim.status === 'idle' || sim.status === 'stopped';
    $('explode').disabled = busy;
    $('one-layer').disabled = busy;
    $('one-layer').checked = sim.layerCount === 1;
    $('auto-stage').checked = sim.autoStage;
    $('event-log').innerHTML = sim.log.map(line => `<li>${line}</li>`).join('');
  }

  function act(fn) {
    try {
      $('explode').value = 0; $('explode-value').value = '0%';
      fn(); paused = false;
    } catch (error) { sim.label = error.message; }
    updateUI();
  }
  $('floor-maps').addEventListener('click', event => {
    const button = event.target.closest('button[data-id]');
    if (button && button.dataset.id) selectTray(button.dataset.id);
  });
  $('store').addEventListener('click', () => act(() => sim.store()));
  $('retrieve').addEventListener('click', () => act(() => { sim.retrieve(selected); selected = null; }));
  $('confirm-dock').addEventListener('click', () => act(() => sim.confirmDock()));
  $('cancel-dock').addEventListener('click', () => act(() => sim.cancelDock()));
  $('speed').addEventListener('input', event => { speed = Number(event.target.value); $('speed-label').textContent = speed + '×'; });
  $('explode').addEventListener('input', event => { $('explode-value').value = event.target.value + '%'; syncScene(); });
  $('show-frame').addEventListener('change', () => syncScene());
  $('show-cars').addEventListener('change', () => syncScene());
  $('auto-stage').addEventListener('change', event => { sim.autoStage = event.target.checked; updateUI(); });
  function resetTo(layers) {
    const autoStage = sim.autoStage;
    sim.reset(layers); sim.autoStage = autoStage;
    selected = null; paused = false;
    $('explode').value = 0; $('explode-value').value = '0%';
    syncScene(); updateUI();
  }
  $('one-layer').addEventListener('change', event => {
    resetTo(event.target.checked ? 1 : MAX_LAYERS);
    sim.addLog(event.target.checked ? '一层样机：7 个存车位，升降只在一层啮合 / 脱开高度动作。' : '两层计划书方案：14 个存车位，二层前侧为 DOCK 竖井。');
    updateUI();
  });
  $('pause').addEventListener('click', () => {
    if (sim.status === 'running') { sim.status = 'paused'; paused = true; }
    else if (sim.status === 'paused') { sim.status = 'running'; paused = false; }
    updateUI();
  });
  $('stop').addEventListener('click', () => { sim.stop(); paused = false; updateUI(); });
  $('reset').addEventListener('click', () => resetTo(sim.layerCount));

  try {
    if (typeof THREE === 'undefined' || !THREE.OrbitControls) throw new Error('Three.js 未加载');
    const container = $('viewport');
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(36, 1, 1, 6000);
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.outputEncoding = THREE.sRGBEncoding;
    container.appendChild(renderer.domElement);
    const controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = .07;
    controls.minDistance = 350;
    controls.maxDistance = 2600;
    controls.maxPolarAngle = Math.PI * .49;
    function setView(top) {
      camera.position.set(top ? 0 : 640, top ? 1250 : 520, top ? 0.1 : 760);
      controls.target.set(0, 130, 0);
      controls.update();
    }
    setView(params.get('view') === 'top');   // ?view=top 打开俯视
    $('reset-view').addEventListener('click', () => setView(false));
    $('top-view').addEventListener('click', () => setView(true));
    scene.add(new THREE.HemisphereLight(0xd7edff, 0x283442, .85));
    const light = new THREE.DirectionalLight(0xffffff, .9);
    light.position.set(300, 1000, 500); scene.add(light);
    const fill = new THREE.DirectionalLight(0x8ecfff, .38);
    fill.position.set(-600, 400, -400); scene.add(fill);

    const material = (color, metalness = .25, roughness = .48, opacity = 1) => new THREE.MeshStandardMaterial({
      color, metalness, roughness, transparent: opacity < 1, opacity, depthWrite: opacity >= 1
    });
    const steel = material(0x9aabb6, .7, .32);
    const dark = material(0x34495a, .6, .45);
    const deckMat = material(0x6d8f9c, .2, .55, .55);
    const roofMat = material(0x6d8f9c, .2, .55, .18);
    const frameMat = material(0x809ba8, .72, .3);
    const gold = material(0xc2ed71, .28, .38);
    const turquoise = material(0x67c3d1, .35, .38);
    const amber = material(0xf0c060, .3, .4);
    const black = material(0x182a38, .35, .5);
    const trayMat = material(0xd5dde0, .2, .3);
    const tire = material(0x17212b, .1, .7);

    // box(父, X 长, Y 深, Z 高, 中心 X, Y, Z, 材质)
    const box = (parent, sx, sy, sz, x, y, z, mat) => {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(sx, sz, sy), mat);
      mesh.position.set(x, z, -y); parent.add(mesh); return mesh;
    };
    // 竖直圆柱，z0..z1
    const post = (parent, r, x, y, z0, z1, mat) => {
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(r, r, z1 - z0, 20), mat);
      mesh.position.set(x, (z0 + z1) / 2, -y); parent.add(mesh); return mesh;
    };
    // 沿世界方向 α（度，从 +X 转向 +Y）放置的长条
    const radial = (parent, alphaDeg, r0, r1, width, z0, z1, mat) => {
      const g = new THREE.Group();
      g.rotation.y = alphaDeg * deg; parent.add(g);
      box(g, r1 - r0, width, z1 - z0, (r0 + r1) / 2, 0, (z0 + z1) / 2, mat);
      return g;
    };

    const ground = new THREE.GridHelper(1400, 28, 0x3a5563, 0x263b49);
    ground.position.y = -8; scene.add(ground);
    box(scene, 520, 520, 6, 0, 0, -3, dark);

    // 甲板轮廓见 deck.js：一层为方板 + 井孔；二层前侧开 DOCK 竖井缺口。
    const toShape = (points, Cls) => {
      const shape = new Cls();
      points.forEach(([x, y], i) => { if (i) shape.lineTo(x, y); else shape.moveTo(x, y); });
      return shape;
    };
    const E = GarageDeck.EDGE;
    const deckShape = toShape([[-E, -E], [E, -E], [E, E], [-E, E]], THREE.Shape);
    deckShape.holes.push(toShape(GarageDeck.hole(), THREE.Path));
    const shaftShape = toShape(GarageDeck.shaftOutline(), THREE.Shape);
    const extrude = shape => new THREE.ExtrudeGeometry(shape, { depth: 5, bevelEnabled: false, curveSegments: 4 });
    const deckGeometry = extrude(deckShape), shaftDeckGeometry = extrude(shaftShape);

    const frame = new THREE.Group(); scene.add(frame);
    const ring = (parent, zc, front = true) => {
      for (const y of front ? [-240, 240] : [240]) box(parent, 460, 20, 20, 0, y, zc, frameMat);
      for (const x of [-240, 240]) box(parent, 20, 460, 20, x, 0, zc, frameMat);
    };
    for (const x of [-240, 240]) for (const y of [-240, 240]) box(frame, 20, 20, 270, x, y, 135, frameMat);
    ring(frame, 10);
    const roofGroup = new THREE.Group(); frame.add(roofGroup);
    ring(roofGroup, 260);
    box(roofGroup, 500, 500, 5, 0, 0, 272.5, roofMat);

    // 层模块：环梁 + 斜撑 + 甲板 + 车位标识 + 霍尔示意。
    const layerGroups = [];
    for (let layer = 0; layer < MAX_LAYERS; layer++) {
      const g = new THREE.Group(); scene.add(g); layerGroups.push(g);
      const zDeck = levelZ(layer);
      const deck = new THREE.Mesh(layer > DOCK.layer ? shaftDeckGeometry : deckGeometry, deckMat);
      deck.rotation.x = -Math.PI / 2; deck.position.y = zDeck - 5; g.add(deck);
      const beams = new THREE.Group(); g.add(beams); beams.userData.frame = true;
      ring(beams, zDeck - 15, layer === DOCK.layer);   // 二层取消前环梁，留出 DOCK 竖井
      for (const a of [45, 135, 225, 315]) radial(beams, a, 140, 322, 20, zDeck - 25, zDeck - 5, frameMat);
      DIRS.forEach((dir, d) => {
        if (isShaft(layer, d)) return;
        const dock = isDock(layer, d);
        const bay = new THREE.Group(); bay.rotation.y = dir.theta * deg; g.add(bay);
        const outline = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(130, 1, 64)),
          new THREE.LineBasicMaterial({ color: dock ? 0xf0c060 : 0xa4bfbc, transparent: true, opacity: dock ? .9 : .45 }));
        outline.position.set(161, zDeck + .6, 0); bay.add(outline);
        box(bay, 4, 50, 8, 228, 0, zDeck + 4, dock ? amber : dark);          // 端挡
        for (const w of [-33, 33]) box(bay, 125, 3, 4, 160, w, zDeck + 2, dark); // 侧导条
        box(bay, 10, 10, 2, 202, 0, zDeck - 6, turquoise);                       // 霍尔（甲板下）
        if (dock) {
          for (const w of [-40, 40]) box(bay, 6, 6, 45, 238, w, zDeck + 22.5, amber); // DOCK 对射光电
        }
      });
    }

    // 升降塔固定件。
    const tower = new THREE.Group(); scene.add(tower);
    for (const [x, y] of [ROD1, ROD2]) {
      post(tower, 4, x, y, 0, 270, steel);
      for (const z of [8, 254]) box(tower, 20, 14, 16, x, y, z, dark);
    }
    box(tower, 42, 42, 40, SCREW[0], SCREW[1], 20, dark);           // 升降电机
    post(tower, 10, SCREW[0], SCREW[1], 40, 60, steel);             // 联轴器
    post(tower, 4, SCREW[0], SCREW[1], 60, 260, gold);              // T8 丝杆 200
    box(tower, 24, 24, 12, SCREW[0], SCREW[1], 254, dark);          // 顶端轴承座
    radial(tower, 67.5, 130, 152, 14, 40, 250, material(0x22323f, .2, .7, .7)); // 拖链区示意

    // 升降平台（不转）+ 转运台（转）。
    const lift = new THREE.Group(); scene.add(lift);
    post(lift, 58, 0, 0, -27, -22, dark);
    for (const a of [22.5, 112.5, 202.5]) radial(lift, a, 40, 150, 10, -42, -22, dark);   // 10 宽 × 20 高竖立臂
    for (const [x, y] of [ROD1, ROD2]) post(lift, 8, x, y, -50, -5, steel); // LM8LUU
    post(lift, 11, SCREW[0], SCREW[1], -32, -22, gold);       // 丝杆螺母
    box(lift, 42, 42, 46, 0, 0, -50, black);                  // 旋转电机（直驱）
    const rotor = new THREE.Group(); lift.add(rotor);
    post(rotor, 50, 0, 0, -22, -14, steel);                   // 圆形转盘轴承
    box(rotor, 170, 66, 3, 0, 0, -12.5, turquoise);           // 转运台底板
    for (const w of [-27, 27]) box(rotor, 125, 6, 11, 22.5, w, -5.5, dark); // 托盘支撑条
    box(rotor, 170, 7, 5, 0, 0, -8.5, steel);                 // MGN7 导轨
    box(rotor, 28, 28, 30, -70, -18, 4, black);               // 转运电机 NEMA11
    const fork = new THREE.Group(); rotor.add(fork);
    box(fork, 22, 12, 4, -36, 0, -4, gold);                   // 滑块与拨叉座
    box(fork, 36, 6, 3, -18, 0, -3.5, gold);                  // 伸出臂
    for (const w of [-4, 4]) box(fork, 8, 3, 6, 0, w, -4, gold); // U 形叉

    const trayObjects = new Map();
    function trayObject(tray) {
      if (trayObjects.has(tray.id)) return trayObjects.get(tray.id);
      const group = new THREE.Group(); scene.add(group);
      // 托盘 125×60×3，内端（-u 侧，靠井口）两角 C10 倒角，给升降支撑臂让位。
      const outline = toShape([[-62.5, -20], [-52.5, -30], [62.5, -30], [62.5, 30], [-52.5, 30], [-62.5, 20]], THREE.Shape);
      const plate = new THREE.Mesh(new THREE.ExtrudeGeometry(outline, { depth: 3, bevelEnabled: false }), trayMat);
      plate.rotation.x = -Math.PI / 2; group.add(plate);
      const highlight = new THREE.LineSegments(new THREE.EdgesGeometry(plate.geometry), new THREE.LineBasicMaterial({ color: 0xc2ed71 }));
      highlight.rotation.copy(plate.rotation); group.add(highlight);
      post(group, 2, -52.5, 0, -5, 0, steel);                 // 定位销
      post(group, 3, 42.5, 0, -1, 0, black);                   // 磁铁
      for (const x of [-57, 57]) box(group, 4, 46, 6, x, 0, 6, dark); // 挡车件
      const car = new THREE.Group(); group.add(car);
      const level = Number(tray.id[0]) - 1;
      const paint = material([0xc1ed73, 0x75c8d3, 0xf0a978][level] || 0xc1ed73, .32, .35);
      box(car, 105, 43, 12, 0, 0, 13, paint);
      box(car, 53, 38, 13, -3, 0, 25.5, paint);
      box(car, 30, 39, 6, -3, 0, 29, black);
      for (const x of [-32, 33]) for (const y of [-19, 19]) {
        const wheel = new THREE.Mesh(new THREE.CylinderGeometry(6, 6, 5, 16), tire);
        wheel.rotation.x = Math.PI / 2; wheel.position.set(x, 9, -y); car.add(wheel);
      }
      group.traverse(object => { object.userData.trayId = tray.id; });
      const entry = { group, car, highlight };
      trayObjects.set(tray.id, entry);
      return entry;
    }

    syncScene = () => {
      const separation = Number($('explode').value) / 100;
      const lift3 = layer => separation * (layer + 1) * 70;
      frame.visible = $('show-frame').checked;
      roofGroup.position.y = separation * (MAX_LAYERS + 1) * 70;
      layerGroups.forEach((g, layer) => {
        g.visible = layer < sim.layerCount;
        g.position.y = lift3(layer);
        g.children.forEach(child => { if (child.userData.frame) child.visible = frame.visible; });
      });
      lift.position.y = sim.lift.z;
      rotor.rotation.y = sim.lift.theta * deg;
      fork.position.x = sim.lift.fork;
      const alive = new Set(sim.trays.map(t => t.id));
      for (const [id, obj] of trayObjects) obj.group.visible = alive.has(id);
      for (const tray of sim.trays) {
        const obj = trayObject(tray);
        const at = sim.locate(tray.id);
        if (!at) continue;
        let theta, r, z;
        if (at.lift) { theta = sim.lift.theta; r = sim.lift.fork + GEOM.trayOffset; z = sim.lift.z; }
        else { theta = DIRS[at.dir].theta; r = GEOM.trayCenterR; z = levelZ(at.layer) + lift3(at.layer); }
        obj.group.position.set(r * Math.cos(theta * deg), z, -r * Math.sin(theta * deg));
        obj.group.rotation.y = theta * deg;
        obj.car.visible = tray.hasCar && $('show-cars').checked;
        obj.highlight.visible = selected === tray.id;
      }
    };

    const raycaster = new THREE.Raycaster(), mouse = new THREE.Vector2();
    let down = null;
    renderer.domElement.addEventListener('pointerdown', event => { down = { x: event.clientX, y: event.clientY }; });
    renderer.domElement.addEventListener('pointerup', event => {
      if (!down || Math.hypot(event.clientX - down.x, event.clientY - down.y) > 5 || sim.status !== 'idle') return;
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
      raycaster.setFromCamera(mouse, camera);
      const targets = Array.from(trayObjects.values()).filter(o => o.group.visible).map(o => o.group);
      const hits = raycaster.intersectObjects(targets, true);
      if (hits.length) {
        const tray = sim.getTray(hits[0].object.userData.trayId);
        if (tray && tray.hasCar) selectTray(tray.id);
      }
    });
    function resize() {
      const width = container.clientWidth, height = container.clientHeight;
      if (!width || !height) return;
      camera.aspect = width / height; camera.updateProjectionMatrix(); renderer.setSize(width, height, false);
    }
    if (typeof ResizeObserver !== 'undefined') new ResizeObserver(resize).observe(container);
    else window.addEventListener('resize', resize);
    resize();
    renderScene = () => { syncScene(); controls.update(); renderer.render(scene, camera); };
  } catch (error) {
    $('render-error').hidden = false;
    console.error('三维画面初始化失败：', error);
  }

  let last = 0, uiAt = 0;
  function tick(now) {
    if (last && !paused) sim.update(Math.min((now - last) / 1000, .06) * speed);
    last = now;
    renderScene();
    if (now - uiAt > 120) { updateUI(); uiAt = now; }
    requestAnimationFrame(tick);
  }
  updateUI(); requestAnimationFrame(tick);
})();
