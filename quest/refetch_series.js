/**
 * quest/refetch_series.js —— 解析器修好后**重抓**带系列的任务页（缓存里存的是旧解析结果）
 *
 * 背景（1.75.9）：`fetch.js` 的系列解析旧实现按可见行对齐 → 部分页面整块错位（实测 #8949 / #1170
 * 把整条链读成同一个名字、只解出 1 个 id）。改用「块内任务链接按文档顺序 + part 号插回当前页」后，
 * 这些页面的 id 全部解出来了 —— 但**缓存里存的是解析后的 JSON**，必须重抓才会更新。
 *
 * 用法：node quest/refetch_series.js [并发数]   # 默认 4；只重抓「缓存里带 series 的任务」
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const CONC = Number(process.argv[2]) || 4;
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  Q.ensureCache();
  const targets = [];
  for (const f of fs.readdirSync(Q.CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    let r = null;
    try { r = JSON.parse(fs.readFileSync(path.join(Q.CACHE, f), 'utf8')); } catch (e) { continue; }
    if (r && r.series) targets.push(+(f.match(/(\d+)/) || [])[1]);
  }
  console.log(`重抓带系列的任务 ${targets.length} 条（并发 ${CONC}）`);
  for (const id of targets) { try { fs.unlinkSync(path.join(Q.CACHE, `quest_${id}.json`)); } catch (e) {} }
  let done = 0, bad = 0, trusted = 0, total = 0;
  const queue = targets.slice();
  await Promise.all(Array.from({ length: CONC }, async () => {
    while (queue.length) {
      const id = queue.shift();
      let rec = null;
      try { rec = await Q.quest(id); } catch (e) { bad++; }
      done++;
      if (rec && rec.series) {
        total++;
        const ids = rec.series.steps.filter(s => s.id).length;
        if (rec.series.trusted) trusted++;
        else console.log(`  ⚠ 不可信系列 #${id} ${rec.title}：${rec.series.part}/${rec.series.total}，解出 id ${ids}`);
      }
      if (done % 50 === 0) console.log(`  ${done}/${targets.length}（可信系列 ${trusted}/${total} · 失败 ${bad}）`);
      await sleep(200);
    }
  }));
  console.log(`完成：${targets.length} 条（带系列 ${total} · 其中可信 ${trusted} · 失败 ${bad}）`);
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
