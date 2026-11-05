/* 检查两层甲板井孔的销槽，尤其是二层跨越 0° 的 315° 方位。 */
'use strict';
const assert = require('node:assert/strict');
const deck = require('../docs/cad/deck.js');

function hasSlot(points, degrees) {
  const angle = degrees * Math.PI / 180;
  const c = Math.cos(angle), s = Math.sin(angle);
  // 销槽末端的两个角应同时位于 r=118、横向 ±7。
  return [-7, 7].every(w => points.some(([x, y]) =>
    Math.abs(x * c + y * s - 118) < 1e-7 &&
    Math.abs(-x * s + y * c - w) < 1e-7));
}

for (const angle of deck.BAYS) {
  assert(hasSlot(deck.hole(), angle), `一层缺少 ${angle}° 销槽`);
  assert.equal(hasSlot(deck.shaftOutline(), angle), angle !== 270,
    `二层 ${angle}° 销槽与 DOCK 竖井布置不符`);
}
console.log('甲板井孔检查通过：一层 8 个销槽，二层 7 个销槽并保留 DOCK 竖井。');
