/** quest/probe_tags.js —— 统计列表行里的标签/地区分布（设计阵营与筛选用；只读） */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
const sweep = JSON.parse(fs.readFileSync(path.join(Q.CACHE, 'sweep_10_60.json'), 'utf8'));
const qs = sweep.quests;
const withRw = qs.filter(q => q.rewards.length);
const tagN = {}, typeN = {}, zoneN = {};
for (const q of qs) { tagN[q.tag || '(空)'] = (tagN[q.tag || '(空)'] || 0) + 1; typeN[q.type || '(空)'] = (typeN[q.type || '(空)'] || 0) + 1; }
for (const q of withRw) zoneN[q.zone || '(空)'] = (zoneN[q.zone || '(空)'] || 0) + 1;
const top = o => Object.entries(o).sort((a, b) => b[1] - a[1]).slice(0, 18);
console.log('全部任务', qs.length, '| 有奖励', withRw.length);
console.log('tag 分布:', JSON.stringify(top(tagN)));
console.log('type 分布:', JSON.stringify(top(typeN)));
console.log('有奖励任务的地区 top:', JSON.stringify(top(zoneN)));
// 名字里有没有分隔符（生成器用 | 当分隔符，必须先证明不会撞）
const bad = qs.filter(q => /[|]/.test(q.name) || /[|]/.test(q.zone));
console.log('名字/地区含 | 的任务数 =', bad.length, bad.slice(0, 3).map(b => b.name));
const lvN = {};
for (const q of withRw) { const b = Math.floor(q.lv / 10) * 10; lvN[b + '-' + (b + 9)] = (lvN[b + '-' + (b + 9)] || 0) + 1; }
console.log('有奖励任务按等级段:', JSON.stringify(lvN));
