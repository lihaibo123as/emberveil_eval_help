/**
 * quest/fix_curated_report.js —— 策展链 vs 站点系列 对照报告（只读，给人工/脚本改 chains.js 用）
 *
 * 用法：node quest/fix_curated_report.js [只在线的链名关键字]
 * 输出：每条策展链 → 策展 ids；站点各条系列（按 part 排序的 id:名 列表）；差集（漏/多）
 *       对「一个详情都没抓到」的 id，**在线核一次**（站点有没有这个任务）。
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);
const CACHE = path.join(__dirname, 'cache');
const chains = require('./chains.js').CHAINS;
const filter = process.argv[2] || '';

const seriesOf = {};
for (const f of fs.readdirSync(CACHE)) {
  if (!/^quest_\d+\.json$/.test(f)) continue;
  let r = null;
  try { r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8')); } catch (e) { continue; }
  if (r && r.series && r.series.steps) seriesOf[r.id] = r;
}

(async () => {
  for (const c of chains) {
    if (filter && c.name.indexOf(filter) < 0) continue;
    console.log('\n=== ' + c.name + ' | 策展 ' + c.quests.length + ' 步 | ' + c.quests.join(','));
    // 站点：按系列分组
    const groups = new Map();
    for (const id of c.quests) {
      const r = seriesOf[id];
      if (!r || !r.series || r.series.total < 2) continue;
      const steps = r.series.steps.filter(s => s.id).sort((a, b) => a.n - b.n);
      if (!steps.length) continue;
      const key = r.series.total + ':' + (steps[0].id || '');
      if (!groups.has(key)) groups.set(key, { total: r.series.total, steps: new Map() });
      const g = groups.get(key);
      for (const s of steps) g.steps.set(s.n, { id: s.id, name: s.name });
    }
    for (const [key, g] of groups) {
      const list = [...g.steps.entries()].sort((a, b) => a[0] - b[0]).map(([n, s]) => `${n}:${s.id}:${s.name}`);
      console.log('   站点系列 [' + g.total + ' 步] ' + list.join(' , '));
    }
    const siteIds = new Set();
    for (const g of groups.values()) for (const s of g.steps.values()) siteIds.add(s.id);
    const missing = [...siteIds].filter(id => c.quests.indexOf(id) < 0);
    const extra = c.quests.filter(id => !siteIds.has(id));
    if (missing.length) console.log('   ⚠ 站点有、策展没有:', missing.join(','));
    if (extra.length) console.log('   ⚠ 策展有、站点系列里没有:', extra.join(','));
    // 在线核：策展里连详情都抓不到的那些 id
    for (const id of c.quests) {
      if (seriesOf[id]) continue;
      let title = '(抓取失败)';
      try {
        const html = await Q.fetchText(`${Q.BASE}/quest/${id}`);
        const rec = Q.parseQuestDetail(html, id);
        title = rec.title || '(页面无标题)';
      } catch (e) { title = 'ERR ' + e.message; }
      console.log(`   ? 在线核 #${id} → ${title}`);
      await new Promise(r => setTimeout(r, 200));
    }
  }
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
