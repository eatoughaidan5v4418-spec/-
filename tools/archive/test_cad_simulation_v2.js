/* 验证网页模拟的状态边界；不验证实际机械、电气或传感器。 */
'use strict';
const assert = require('node:assert/strict');
const { Simulation, CELLS } = require('../docs/cad/simulation.js');

function permutations(values) {
  if (values.length < 2) return [values];
  return values.flatMap((value, index) =>
    permutations(values.filter((_, i) => i !== index)).map(rest => [value, ...rest]));
}

function checkDuringMotion(sim) {
  const occupied = sim.layers.flat().filter(Boolean);
  if (sim.platformTray) occupied.push(sim.platformTray);
  assert.equal(occupied.length, 6, '托盘数量在运动中必须守恒');
  assert.equal(new Set(occupied.map(t => t.id)).size, 6, '托盘不能重复出现在两个位置');
  if (sim.motor === '升降电机') {
    assert(sim.allHeadsClear(), '升降时所有抓取头必须退回并抬销');
    assert(!sim.platformTray || Math.abs(sim.platformTray.x - 400) < .01, '升降时托盘必须完全在台内');
  }
  if (sim.motor === '交接滚筒') assert(sim.heads.every(head => head.pin === 0), '滚筒运动前必须退销');
  for (let i = 0; i < sim.trays.length; i++) for (let j = i + 1; j < sim.trays.length; j++) {
    const a = sim.trays[i], b = sim.trays[j];
    if (Math.abs(a.z - b.z) < .01) {
      assert(!(Math.abs(a.x - b.x) < 139.99 && Math.abs(a.y - b.y) < 79.99), '同一高度托盘投影重叠');
    }
  }
}

function runUntil(sim, expected) {
  let steps = 0;
  while (sim.status === 'running' && steps++ < 3000) {
    sim.update(.04);
    checkDuringMotion(sim);
  }
  assert.equal(sim.status, expected, sim.label);
}

let cases = 0;
for (const level of [0, 1]) for (const order of permutations([0, 1, 2, 3])) {
  for (const targetIndex of [0, 1, 2]) for (const kind of ['store', 'retrieve']) {
    const sim = new Simulation();
    const original = sim.layers[level].slice();
    sim.layers[level] = order.map(index => original[index]);
    sim.layers[level].forEach((tray, index) => {
      if (tray) { tray.x = CELLS[index].x; tray.y = CELLS[index].y; }
    });
    const target = original[targetIndex];
    target.hasCar = kind === 'retrieve';
    const before = sim.layers.map(slots => slots.map(tray => tray && [tray.id, tray.hasCar]));
    sim.start(kind, level, target.id);
    runUntil(sim, 'waiting');
    assert.equal(sim.liftZ, 70);
    assert.equal(sim.platformTray.id, target.id);
    assert.equal(target.hasCar, kind === 'retrieve', '未经用户确认不得改变车辆状态');
    sim.update(10);
    assert.equal(sim.status, 'waiting', '等待用户确认时不得自动继续');
    sim.confirmDock();
    runUntil(sim, 'idle');
    before[level].find(tray => tray && tray[0] === target.id)[1] = kind === 'store';
    assert.deepEqual(sim.layers.map(slots => slots.map(tray => tray && [tray.id, tray.hasCar])), before);
    assert.equal(sim.platformTray, null);
    assert.equal(sim.layers[level].filter(Boolean).length, 3);
    cases++;
  }
}

const stop = new Simulation();
assert.throws(() => stop.start('store', 0, '101'), /空托盘/);
assert.throws(() => stop.start('retrieve', 0, '103'), /载车托盘/);
stop.start('store', 0, '103');
stop.update(.2);
stop.stop();
const stoppedAt = stop.liftZ;
stop.update(100);
assert.equal(stop.status, 'stopped');
assert.equal(stop.liftZ, stoppedAt);
assert.throws(() => stop.confirmDock());
stop.reset();
assert.equal(stop.status, 'idle');
console.log(`${cases} 个存取循环通过：全排列、两层、三托盘、存车与取车`);
console.log('运动互锁、托盘守恒、平面重叠、DOCK 确认、模拟急停与复位检查通过');
console.log('测试范围仅为模拟状态和矩形投影；不代表实物安全或三维干涉已验证。');
