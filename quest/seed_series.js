/**
 * quest/seed_series.js —— 用「名人任务线」关键词把**大型/开门/史诗线**抓进数据
 *
 * ★关键事实（本次探针实测，把第一次 0 命中的坑钉死）：
 *   站点搜索 `/quests?name=<词>` 匹配的是**任务标题原文（英文）**，且是**子串匹配**：
 *     · `name=Onyxia` → 3 条（奥妮克希亚开门线）✓
 *     · `name=安其拉` → **0 条**（中文名只是 lang=zhCN 的显示层，不参与检索）✗
 *     · 多词短语（`Scepter of the Shifting Sands`）→ 0 条（不是全文检索）
 *   ⇒ 种子必须用**英文单词**（能从标题里认出来的那种）。
 *
 * 做法：关键词命中 → 抓这些任务详情（一条详情就带回整条系列）→ 再对「新发现的系列成员」扩一轮。
 * 用法：node quest/seed_series.js [并发数]   # 默认 3，走缓存、可重跑
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const KWS = [
  'Naxxramas', 'Onyxia', 'Quel\'Serrar', 'Thunderfury', 'Molten Core', 'Darrowshire', 'Linken',
  'Eranikus', 'Hakkar', 'Atal\'Hakkar', 'Scholomance', 'Sunken Temple', 'Cenarion', 'Argent Dawn',
  'Uldaman', 'Maraudon', 'Gnomeregan', 'Shadowfang', 'Stockade', 'Scarlet', 'Felwood', 'Silithus',
  'Un\'Goro', 'Winterspring', 'Azshara', 'Blasted Lands', 'Burning Steppes', 'Western Plaguelands',
  'Eastern Plaguelands', 'Feralas', 'Hinterlands', 'Searing Gorge', 'Dustwallow', 'Tanaris',
  'Zul', 'Razorfen', 'Wailing', 'Blackfathom', 'Deadmines', 'Stratholme', 'Dire Maul', 'Blackrock',
  'Warchief', 'Thrall', 'Cairne', 'Magni', 'Bolvar', 'Rexxar', 'Hemet', 'Nat Pagle',
  'Defiler', 'Ashbringer', 'Lightforge', 'Beaststalker', 'Virtuous', 'Devout', 'Magister',
  'Dreadmist', 'Wildheart', 'Battlegear', 'Elements', 'Prophecy', 'Nightslayer', 'Giantstalker',
  'Arcanist', 'Felheart', 'Cenarion', 'Earthfury', 'Vestments',
  // 第二波（第一次探针发现：搜索是**标题子串**，这些词能命中安其拉开门/龙火护符一类的长线）
  'Scepter', 'Azuregos', 'Anachronos', 'Moonglade', 'Dragonshrine', 'Hive', 'Silithid', 'Emerald',
  'Ledger', 'Shifting', 'Badge', 'Emblem', 'Draconic', 'Menethil', 'Doomhammer', 'Lothar',
];
const CONC = Number(process.argv[2]) || 3;
const MAX_FETCH = 900;
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  Q.ensureCache();
  const seen = new Set();
  const seriesHit = [];
  async function fetchOne(id) {
    if (seen.has(id)) return null;
    seen.add(id);
    let rec = null;
    try { rec = await Q.quest(id); } catch (e) { rec = null; }
    if (rec && rec.series && rec.series.steps && rec.series.steps.length >= 2) {
      console.log(`  ★系列 #${id} ${rec.title}：第 ${rec.series.part}/${rec.series.total} 部分 · ${rec.series.steps.length} 步`);
      seriesHit.push({ id, title: rec.title, total: rec.series.total, steps: rec.series.steps.length });
    }
    await sleep(200);
    return rec;
  }
  async function pool(ids) {
    const queue = ids.slice();
    await Promise.all(Array.from({ length: CONC }, async () => {
      while (queue.length && seen.size < MAX_FETCH) { await fetchOne(queue.shift()); }
    }));
  }

  // ① 关键词搜索
  const cand = new Set();
  for (const kw of KWS) {
    let rows = [];
    try { rows = Q.parseQuestList(await Q.fetchText(`${Q.BASE}/quests?name=${encodeURIComponent(kw)}`)); } catch (e) {}
    if (rows.length) console.log(`  种子「${kw}」→ ${rows.length} 命中`);
    rows.slice(0, 10).forEach(r => cand.add(r.id));
    await sleep(200);
  }
  console.log(`[种子] 候选 ${cand.size} 条`);
  await pool([...cand]);

  // ② 扩展：把新发现系列里的步骤任务也抓一遍（系列信息常常只在其中一条上）
  const members = new Set();
  for (const f of fs.readdirSync(Q.CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    try {
      const r = JSON.parse(fs.readFileSync(path.join(Q.CACHE, f), 'utf8'));
      if (r && r.series && r.series.steps) r.series.steps.forEach(s => { if (s.id && !seen.has(s.id)) members.add(s.id); });
    } catch (e) {}
  }
  console.log(`[扩展] 系列成员待补抓 ${members.size} 条`);
  await pool([...members]);

  console.log(`完成：抓到 ${seriesHit.length} 条带系列的任务；最长系列 =`,
    seriesHit.sort((a, b) => b.steps - a.steps).slice(0, 6).map(s => `${s.title}(${s.steps}步/${s.total})`).join(' · ') || '(无)');
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
