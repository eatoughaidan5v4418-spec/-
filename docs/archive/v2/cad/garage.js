/* 基于硬件方案 v2 的概念模型。实际部件、传感器与控制器尚未接入。 */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const { Simulation, CELLS, HEIGHTS } = GarageSimulation;
  const sim = new Simulation();
  let selected = null;
  let paused = false;
  let speed = 2;
  let lastUI = '';
  let renderScene = () => {};
  let syncScene = () => {};

  function selectTray(level, id) {
    if (sim.status !== 'idle') return;
    selected = { level, id };
    updateUI();
  }

  function updateUI() {
    const busy = sim.status !== 'idle';
    const signature = JSON.stringify([
      sim.layers.map(slots => slots.map(t => t && [t.id, t.hasCar])), selected, sim.status,
      sim.label, sim.motor, Math.round(sim.liftZ), sim.platformTray && sim.platformTray.id, sim.log
    ]);
    if (signature === lastUI) return;
    lastUI = signature;
    $('floor-maps').innerHTML = sim.layers.map((slots, level) => {
      const cars = slots.filter(t => t && t.hasCar).length;
      const buttons = [2, 3, 0, 1].map(index => {
        const tray = slots[index], cell = CELLS[index];
        const chosen = tray && selected && selected.id === tray.id;
        const type = !tray ? 'empty' : tray.hasCar ? 'has-car' : 'has-tray';
        const description = !tray ? '无托盘' : tray.hasCar ? '载车托盘' : '空托盘';
        return `<button type="button" class="cell ${type} ${chosen ? 'selected' : ''}" data-level="${level}" data-id="${tray ? tray.id : ''}" ${!tray || busy ? 'disabled' : ''} aria-label="${level + 1}层${cell.name}位，${description}${tray ? '，编号' + tray.id : ''}"><b>${cell.name} ${index === 3 ? '· 交接' : ''}</b><small>${description}${tray ? ' / ' + tray.id : ''}</small></button>`;
      }).join('');
      return `<div class="floor-card"><div class="floor-head"><strong>${level + 1}F · ${level ? '二层' : '一层'}</strong><small>在位载车 ${cars} / 3</small></div><div class="floor-grid">${buttons}</div><div class="floor-caption"><span>↑ 后侧</span><span>→ 升降台</span></div></div>`;
    }).join('');
    const tray = selected ? sim.getTray(selected.id) : null;
    $('selection-title').textContent = tray ? `${selected.level + 1} 层 · 托盘 ${tray.id}` : '请选择托盘';
    $('selection-detail').textContent = tray ? (tray.hasCar ? '当前有车，可执行取车' : '当前无车，可执行存车') : '点击车位图或模型中的托盘';
    $('store').disabled = busy || !tray || tray.hasCar;
    $('retrieve').disabled = busy || !tray || !tray.hasCar;
    $('selection-help').textContent = busy ? '运行期间不可切换托盘。' : '空托盘用于存车；载车托盘用于取车。';
    const labels = { idle: '待机', running: '运行中', paused: '已暂停', waiting: '等待确认', stopped: '已停止' };
    $('status-pill').textContent = labels[sim.status] || sim.status;
    $('status-pill').className = 'status-pill ' + (sim.status === 'waiting' ? 'waiting' : sim.status === 'stopped' ? 'stopped' : '');
    $('current-step').textContent = sim.label;
    $('motor-state').textContent = sim.status === 'paused' ? '演示暂停' : sim.motor;
    $('lift-height').innerHTML = `${Math.round(sim.liftZ)} <small>mm</small>`;
    $('platform-state').textContent = sim.platformTray ? sim.platformTray.id : '无';
    $('dock-card').hidden = sim.status !== 'waiting';
    if (sim.status === 'waiting') {
      const storing = sim.operation.kind === 'store';
      $('dock-title').textContent = storing ? '请在 DOCK 放好车辆' : '请在 DOCK 取走车辆';
      $('dock-detail').textContent = storing ? '车辆应固定在托盘内；点击确认后，演示才会继续。' : '取走车辆后点击确认，空托盘将返回原层。';
      $('confirm-dock').firstChild.textContent = storing ? '已放车，继续 ' : '已取车，继续 ';
    }
    $('pause').disabled = sim.status !== 'running' && sim.status !== 'paused';
    $('pause').textContent = sim.status === 'paused' ? '继续' : '暂停';
    $('stop').disabled = sim.status === 'idle' || sim.status === 'stopped';
    $('explode').disabled = sim.status !== 'idle';
    $('event-log').innerHTML = sim.log.map(line => `<li>${line}</li>`).join('');
  }

  $('floor-maps').addEventListener('click', event => {
    const button = event.target.closest('button[data-id]');
    if (button && button.dataset.id) selectTray(Number(button.dataset.level), button.dataset.id);
  });
  function start(kind) {
    if (!selected) return;
    try {
      $('explode').value = 0;
      $('explode-value').value = '0%';
      sim.start(kind, selected.level, selected.id);
      paused = false;
    } catch (error) { sim.label = error.message; }
    updateUI();
  }
  $('store').addEventListener('click', () => start('store'));
  $('retrieve').addEventListener('click', () => start('retrieve'));
  $('confirm-dock').addEventListener('click', () => { try { sim.confirmDock(); } catch (error) { sim.label = error.message; } updateUI(); });
  $('speed').addEventListener('input', event => { speed = Number(event.target.value); $('speed-label').textContent = speed + '×'; });
  $('explode').addEventListener('input', event => { $('explode-value').value = event.target.value + '%'; syncScene(); });
  $('show-frame').addEventListener('change', () => syncScene());
  $('show-cars').addEventListener('change', () => syncScene());
  $('pause').addEventListener('click', () => {
    if (sim.status === 'running') { sim.status = 'paused'; paused = true; }
    else if (sim.status === 'paused') { sim.status = 'running'; paused = false; }
    updateUI();
  });
  $('stop').addEventListener('click', () => { sim.stop(); paused = false; updateUI(); });
  $('reset').addEventListener('click', () => {
    sim.reset(); selected = null; paused = false;
    $('explode').value = 0; $('explode-value').value = '0%';
    syncScene(); updateUI();
  });

  try {
    if (typeof THREE === 'undefined' || !THREE.OrbitControls) throw new Error('Three.js 未加载');
    const container = $('viewport');
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(38, 1, 1, 5000);
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.outputEncoding = THREE.sRGBEncoding;
    container.appendChild(renderer.domElement);
    const controls = new THREE.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = .07;
    controls.minDistance = 450;
    controls.maxDistance = 2200;
    controls.maxPolarAngle = Math.PI * .49;
    controls.target.set(225, 265, 90);
    function setView(top) {
      camera.position.set(top ? 225 : 1000, top ? 1450 : 790, top ? 90.1 : 1100);
      controls.target.set(225, 265, 90);
      controls.update();
    }
    setView(false);
    $('reset-view').addEventListener('click', () => setView(false));
    $('top-view').addEventListener('click', () => setView(true));
    scene.add(new THREE.HemisphereLight(0xd7edff, 0x283442, .85));
    const light = new THREE.DirectionalLight(0xffffff, .9);
    light.position.set(250, 1000, -400); scene.add(light);
    const fill = new THREE.DirectionalLight(0x8ecfff, .38);
    fill.position.set(-500, 500, 500); scene.add(fill);

    const material = (color, metalness=.25, roughness=.48, opacity=1) => new THREE.MeshStandardMaterial({
      color, metalness, roughness, transparent: opacity < 1, opacity, depthWrite: opacity >= 1
    });
    const steel = material(0x9aabb6, .7, .32);
    const dark = material(0x34495a, .6, .45);
    const deck = material(0x526f7d, .5, .55, .76);
    const frameMat = material(0x809ba8, .72, .3);
    const gold = material(0xc2ed71, .28, .38);
    const turquoise = material(0x67c3d1, .35, .38);
    const black = material(0x182a38, .35, .5);
    const trayMat = material(0xc0cbd0, .7, .28);
    const tire = material(0x17212b, .1, .7);
    const makeBox = (parent, w, d, h, x, y, z, mat) => {
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
      mesh.position.set(x, z, y); parent.add(mesh); return mesh;
    };
    const cylinder = (parent, radius, length, x, y, z, mat, alongY=false) => {
      const mesh = new THREE.Mesh(new THREE.CylinderGeometry(radius, radius, length, 16), mat);
      if (alongY) mesh.rotation.x = Math.PI / 2;
      mesh.position.set(x, z, y); parent.add(mesh); return mesh;
    };

    const ground = new THREE.GridHelper(1200, 30, 0x3a5563, 0x263b49);
    ground.position.set(225, -7, 100); scene.add(ground);
    makeBox(scene, 550, 300, 6, 240, 90, -3, dark);
    const frame = new THREE.Group(); scene.add(frame);
    for (const x of [-10, 310]) for (const y of [-10, 190]) makeBox(frame, 20, 20, 630, x, y, 315, frameMat);
    for (const y of [-10, 190]) makeBox(frame, 340, 20, 20, 150, y, 640, frameMat);
    for (const x of [-10, 310]) makeBox(frame, 20, 180, 20, x, 90, 640, frameMat);
    const roof = frame.children.slice(-4);

    const floorGroups = [], gantries = [], heads = [], pins = [];
    HEIGHTS.forEach((height, level) => {
      const floor = new THREE.Group(); scene.add(floor); floorGroups.push(floor);
      makeBox(floor, 320, 180, 3, 160, 90, -1.5, deck);
      // 每层四格的标记和 20 mm 交接唇板。
      for (const c of CELLS) {
        const marker = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(140, 1, 80)), new THREE.LineBasicMaterial({ color: 0xa4bfbc, transparent:true, opacity:.45 }));
        marker.position.set(c.x, .8, c.y); floor.add(marker);
      }
      makeBox(floor, 20, 180, 2, 310, 90, .3, turquoise);
      for (const x of [0, 300]) {
        makeBox(floor, 9, 150, 8, x, 90, 145, steel);
        makeBox(floor, 12, 8, 140, x, 20, 72, dark);
        makeBox(floor, 12, 8, 140, x, 160, 72, dark);
      }
      const beam = new THREE.Group(); floor.add(beam); gantries.push(beam);
      makeBox(beam, 310, 9, 10, 150, 0, 150, steel);
      makeBox(beam, 310, 5, 5, 150, 0, 158, dark);
      const head = new THREE.Group(); beam.add(head); heads.push(head);
      makeBox(head, 30, 24, 21, 0, 0, 143, turquoise);
      makeBox(head, 18, 18, 65, 0, -25, 102, dark);
      cylinder(head, 3, 86, -50, -30, 100, steel);
      cylinder(head, 3, 86, 50, -30, 100, steel);
      const pinGroup = new THREE.Group(); head.add(pinGroup); pins.push(pinGroup);
      makeBox(pinGroup, 125, 5, 5, 0, -30, 7, gold);
      cylinder(pinGroup, 1.5, 9, -60, -30, 2.5, steel);
      cylinder(pinGroup, 1.5, 9, 60, -30, 2.5, steel);
    });
    for (const x of [345, 455]) cylinder(scene, 4, 500, x, 205, 260, steel);
    cylinder(scene, 4, 450, 400, 205, 315, gold);
    makeBox(scene, 58, 45, 76, 400, 205, 38, dark);
    const lift = new THREE.Group(); scene.add(lift);
    makeBox(lift, 150, 90, 4, 400, 135, -10, dark);
    for (const x of [340, 380, 420, 460]) cylinder(lift, 6, 70, x, 135, -6, steel, true);
    for (const y of [91, 179]) makeBox(lift, 150, 4, 12, 400, y, -1, turquoise);
    makeBox(lift, 135, 12, 65, 400, 200, 25, dark);
    for (const x of [345, 455]) for (const z of [0, 50]) cylinder(lift, 8, 24, x, 205, z, steel);

    const trayObjects = new Map();
    function createTray(tray) {
      const group = new THREE.Group(); scene.add(group);
      const plate = makeBox(group, 140, 80, 2, 0, 0, 1, trayMat);
      const highlight = new THREE.LineSegments(new THREE.EdgesGeometry(plate.geometry), new THREE.LineBasicMaterial({ color: 0xc2ed71 }));
      highlight.position.copy(plate.position); group.add(highlight);
      for (const x of [-60, 60]) cylinder(group, 2, .5, x, -30, 2.1, black);
      for (const x of [-52, 52]) makeBox(group, 5, 46, 5, x, 0, 4.5, dark);
      const car = new THREE.Group(); group.add(car);
      const paint = material(tray.level ? 0x75c8d3 : 0xc1ed73, .32, .35);
      makeBox(car, 105, 43, 12, 0, 0, 12, paint);
      makeBox(car, 53, 38, 13, -3, 0, 24.5, paint);
      makeBox(car, 30, 39, 6, -3, 0, 28, black);
      for (const x of [-32, 33]) for (const y of [-20, 20]) cylinder(car, 6, 5, x, y, 8, tire, true);
      group.traverse(object => { object.userData.trayId = tray.id; });
      return { group, car, highlight };
    }
    sim.trays.forEach(tray => trayObjects.set(tray.id, createTray(tray)));
    syncScene = () => {
      const separation = Number($('explode').value) / 100;
      frame.visible = $('show-frame').checked;
      roof.forEach(part => { part.position.y = 640 + separation * 110; });
      floorGroups.forEach((group, index) => {
        group.position.y = HEIGHTS[index] + separation * (index + 1) * 55;
        gantries[index].position.z = sim.heads[index].y;
        heads[index].position.x = sim.heads[index].x;
        pins[index].position.y = 50 - sim.heads[index].pin * 49;
      });
      lift.position.y = sim.liftZ;
      for (const tray of sim.trays) {
        const obj = trayObjects.get(tray.id);
        const attachedToLift = sim.platformTray === tray;
        const offset = attachedToLift ? 0 : separation * (tray.level + 1) * 55;
        obj.group.position.set(tray.x, tray.z + offset, tray.y);
        obj.car.visible = tray.hasCar && $('show-cars').checked;
        obj.highlight.visible = !!selected && selected.id === tray.id;
      }
    };
    const raycaster = new THREE.Raycaster(), mouse = new THREE.Vector2();
    let down = null;
    renderer.domElement.addEventListener('pointerdown', event => { down = { x:event.clientX, y:event.clientY }; });
    renderer.domElement.addEventListener('pointerup', event => {
      if (!down || Math.hypot(event.clientX - down.x, event.clientY - down.y) > 5 || sim.status !== 'idle') return;
      const rect = renderer.domElement.getBoundingClientRect();
      mouse.set((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1);
      raycaster.setFromCamera(mouse, camera);
      const hits = raycaster.intersectObjects(Array.from(trayObjects.values(), o => o.group), true);
      if (hits.length) {
        const tray = sim.getTray(hits[0].object.userData.trayId);
        if (tray) selectTray(tray.level, tray.id);
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
  function frame(now) {
    if (last && !paused) sim.update(Math.min((now - last) / 1000, .06) * speed);
    last = now;
    renderScene();
    if (now - uiAt > 120) { updateUI(); uiAt = now; }
    requestAnimationFrame(frame);
  }
  updateUI(); requestAnimationFrame(frame);
})();
