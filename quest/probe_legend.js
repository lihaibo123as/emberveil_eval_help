/** quest/probe_legend.js —— 找「传说级」任务/任务线（风剑/橙杖/安其拉/奎尔塞拉…），决定橙色档给谁 */
'use strict';
const fs = require('fs');
const path = require('path');
const CACHE = path.join(__dirname, 'cache');
const LEG = ['雷霆之怒', '风剑', '逐风者', '埃提耶什', '流沙', '节杖', '安其拉', '甲虫之墙', '灰烬使者', '萨弗拉斯', '奎尔塞拉', '泰坦', '橙'];
const series = [];
for (const f of fs.readdirSync(CACHE)) {
  if (!/^quest_\d+\.json$/.test(f)) continue;
  let r = null;
  try { r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8')); } catch (e) { continue; }
  if (r && r.series && r.series.steps && r.series.steps.length >= 2) {
    const names = r.series.steps.map(s => s.name).join(' ');
    if (LEG.some(k => names.indexOf(k) >= 0)) series.push({ id: r.id, title: r.title, total: r.series.total, names: r.series.steps.map(s => s.name).join(' / ') });
  }
}
console.log('=== 命中传说关键词的「系列」（' + series.length + ' 条记录）===');
const seen = new Set();
for (const s of series) {
  const key = s.total + ':' + s.names.slice(0, 40);
  if (seen.has(key)) continue;
  seen.add(key);
  console.log(`  #${s.id} ${s.title} (${s.total}步) → ${s.names.slice(0, 150)}`);
}
const sweep = JSON.parse(fs.readFileSync(path.join(CACHE, 'sweep_10_60.json'), 'utf8'));
console.log('\n=== 命中传说关键词的「单任务」===');
for (const q of sweep.quests) if (LEG.some(k => q.name.indexOf(k) >= 0)) console.log(`  #${q.id} ${q.name} (Lv${q.lv} ${q.zone}) 奖励[${q.rewards.map(r => r.id).join(',')}]`);
