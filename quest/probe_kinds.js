/** quest/probe_kinds.js —— 只读探针：全量装备的「部位 / 类型」分布（回答「戒指/项链/饰品 能不能细分」）
 *  用法：node quest/probe_kinds.js
 */
'use strict';
const fs = require('fs');
const src = fs.readFileSync('quest/QuestBulk.lua', 'utf8');
const i = src.indexOf('\ni={');
const j = src.indexOf('\n},', i);
const body = src.slice(i, j < 0 ? src.length : j);
const re = /\[(\d+)\]="((?:[^"\\]|\\.)*)"/g;
const rows = [];
let m;
while ((m = re.exec(body))) rows.push(m[2].split('|'));

const eq = rows.filter(p => p[9] === '1');
console.log('装备类物品 ' + eq.length + ' 件');
const w = eq.filter(p => (parseFloat(p[3]) || 0) > 0);
const armor = eq.filter(p => !(parseFloat(p[3]) || 0) > 0);
console.log('  武器（dps>0）' + w.length + ' 件 · 非武器 ' + armor.length + ' 件');

const tally = list => {
  const t = {};
  for (const p of list) {
    const key = (p[5] || '(空部位)') + ' / ' + (p[6] || '(空类型)');
    t[key] = (t[key] || 0) + 1;
  }
  return Object.entries(t).sort((a, b) => b[1] - a[1]);
};
console.log('\n武器 部位/类型：');
for (const [k, n] of tally(w)) console.log('  ' + k + '  ×' + n);
console.log('\n非武器 部位/类型：');
for (const [k, n] of tally(armor)) console.log('  ' + k + '  ×' + n);
