/**
 * quest/sweep_details.js —— 逐条抓「物品页 + 任务详情页」（独立脚本，可随时重跑，走缓存）
 *
 * 阶段一（item）：把全量列表里品质 ≥2 的奖励物品逐条抓下来
 *   → 名称 / 品质 / 物品等级 / 每秒伤害 / 速度 / 部位 / 类型 / 属性 / 反向引用（奖励来自哪个任务）
 *   ★只有物品页能给出「是不是装备」——列表页只给 id/品质/图标
 * 阶段二（quest）：把带装备奖励的任务逐条抓详情页
 *   → 「本系列第 N/M 部分」= 站点自报的任务线归属与完整度（用户要求审计「任务线是否完整」）
 *   → 任务发布者 / 要求 / 经验 等
 *
 * 用法：node quest/sweep_details.js [item|quest|all]   （默认 all）
 * 产物：quest/cache/item_<id>.json · quest/cache/quest_<id>.json（fetch.js 的 cached() 负责）
 *       quest/cache/eq_summary.json（本次扫出来的装备清单与统计）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const SLEEP = 200;
const CONC = Number(process.argv.find(a => /^\d+$/.test(a))) || 4; // 并发（单条 ~1.2s；4 条约 3 条/秒，别一次轰）
const sleep = ms => new Promise(r => setTimeout(r, ms));
const mode = process.argv[2] || 'all';

function loadSweep() {
  const f = path.join(Q.CACHE, 'sweep_10_60.json');
  if (!fs.existsSync(f)) throw new Error('缺 quest/cache/sweep_10_60.json —— 先跑 node quest/sweep.js');
  return JSON.parse(fs.readFileSync(f, 'utf8'));
}

(async () => {
  Q.ensureCache();
  const sweep = loadSweep();
  const quests = sweep.quests;
  const qById = {};
  for (const q of quests) qById[q.id] = q;

  const itemIds = [];
  const itemMeta = {};
  for (const q of quests) {
    for (const it of q.rewards) {
      // ★全部奖励物品都抓（含白/灰）：任务行的 `rw` 是「列表页 ∪ 详情页」的并集，缺了哪件都会变成
      //   「奖励 id 不在物品表里」（审计 B 硬错误）。装备视图另按 `eq` 只显示装备。
      if (!itemMeta[it.id]) { itemMeta[it.id] = it; itemIds.push(it.id); }
    }
  }
  console.log(`列表：任务 ${quests.length} · 带奖励 ${quests.filter(q => q.rewards.length).length} · 奖励物品 ${itemIds.length}`);

  // ---------- 阶段一：物品 ----------
  const eq = {}, notEq = {}, failed = [];
  if (mode === 'item' || mode === 'all') {
    let done = 0, cachedN = 0;
    const queue = itemIds.slice();
    async function itemWorker() {
      while (queue.length) {
        const id = queue.shift();
        const f = path.join(Q.CACHE, `item_${id}.json`);
        const wasCached = fs.existsSync(f);
        let rec = null;
        try { rec = await Q.item(id); } catch (e) { failed.push(id); }
        if (wasCached) cachedN++;
        done++;
        if (rec) {
          const isEq = !!(rec.slot || (rec.dps && rec.dps > 0));
          const row = {
            id, n: rec.name, q: (rec.q != null ? rec.q : (itemMeta[id] ? itemMeta[id].q : 1)),
            ilvl: rec.ilvl || 0, dps: rec.dps || 0, sp: rec.speed || 0,
            s: rec.slot || '', k: rec.kind || '', st: rec.stats || '',
            icon: (itemMeta[id] || {}).icon || '', from: rec.rewardFrom || '',
          };
          if (isEq) eq[id] = row; else notEq[id] = row;
        }
        if (done % 50 === 0) console.log(`  物品 ${done}/${itemIds.length}（命中装备 ${Object.keys(eq).length} · 非装备 ${Object.keys(notEq).length} · 失败 ${failed.length} · 已缓存 ${cachedN}）`);
        if (!wasCached) await sleep(SLEEP);
      }
    }
    await Promise.all(Array.from({ length: CONC }, itemWorker));
    console.log(`物品阶段完成：装备 ${Object.keys(eq).length} · 非装备 ${Object.keys(notEq).length} · 失败 ${failed.length}`);
  }

  // ---------- 阶段二：带装备奖励的任务详情（拿系列信息） ----------
  const seriesQuests = {};
  if (mode === 'quest' || mode === 'all') {
    // ★**所有带奖励的任务**都抓详情（不只在列表页看到装备的那些）：列表页的奖励图标是截断显示的，
    //   详情页的「选择一件/直接给予」才是完整清单 —— 这是装备视图「不漏件」的前提。
    const want = quests.filter(q => q.rewards.length > 0 || q.tag);
    console.log(`任务详情阶段：带奖励的任务 ${want.length} 条`);
    let done = 0, cachedN = 0, bad = 0, withSeries = 0;
    const qQueue = want.slice();
    async function questWorker() {
      while (qQueue.length) {
        const q = qQueue.shift();
        const f = path.join(Q.CACHE, `quest_${q.id}.json`);
        const wasCached = fs.existsSync(f);
        let rec = null;
        try { rec = await Q.quest(q.id); } catch (e) { bad++; }
        if (wasCached) cachedN++;
        done++;
        if (rec && rec.series) withSeries++;
        if (rec) {
          seriesQuests[q.id] = {
            id: q.id, title: rec.title || q.name, level: rec.level || q.lv, zone: rec.zone || q.zone,
            part: rec.series ? rec.series.part : 0, total: rec.series ? rec.series.total : 0,
            steps: rec.series ? rec.series.steps : [],
            trusted: rec.series ? rec.series.trusted : false,
            choose: (rec.choose || []).map(x => x.id).filter(Boolean),
            receive: (rec.receive || []).map(x => x.id).filter(Boolean),
          };
        }
        if (done % 50 === 0) console.log(`  任务 ${done}/${want.length}（带系列 ${withSeries} · 失败 ${bad} · 已缓存 ${cachedN}）`);
        if (!wasCached) await sleep(SLEEP);
      }
    }
    await Promise.all(Array.from({ length: CONC }, questWorker));
    console.log(`任务阶段完成：${Object.keys(seriesQuests).length} 条 · 其中带系列 ${withSeries} · 抓取失败 ${bad}`);
  }

  // ---------- 阶段三：详情页里**新出现**的奖励物品（列表页截断 ⇒ 详情页会带出没抓过的 id） ----------
  if (mode === 'all') {
    const have = new Set(Object.keys({ ...eq, ...notEq }).map(Number));
    const extra = new Set();
    for (const f of fs.readdirSync(Q.CACHE)) {
      if (!/^quest_\d+\.json$/.test(f)) continue;
      try {
        const r = JSON.parse(fs.readFileSync(path.join(Q.CACHE, f), 'utf8'));
        for (const x of [...(r.choose || []), ...(r.receive || [])]) if (x.id && !have.has(x.id)) extra.add(x.id);
      } catch (e) {}
    }
    console.log(`补抓阶段：详情页新出现的奖励物品 ${extra.size} 件`);
    const q3 = [...extra];
    let d3 = 0;
    async function w3() {
      while (q3.length) {
        const id = q3.shift();
        let rec = null;
        try { rec = await Q.item(id); } catch (e) {}
        d3++;
        if (rec) {
          const isEq = !!(rec.slot || (rec.dps && rec.dps > 0));
          const row = {
            id, n: rec.name, q: (rec.q != null ? rec.q : 1), ilvl: rec.ilvl || 0, dps: rec.dps || 0,
            sp: rec.speed || 0, s: rec.slot || '', k: rec.kind || '', st: rec.stats || '',
            icon: (itemMeta[id] || {}).icon || '', from: rec.rewardFrom || '',
          };
          if (isEq) eq[id] = row; else notEq[id] = row;
        }
        if (d3 % 50 === 0) console.log(`  补抓 ${d3}/${extra.size}`);
        await sleep(SLEEP);
      }
    }
    await Promise.all(Array.from({ length: CONC }, w3));
    console.log(`补抓完成：装备 ${Object.keys(eq).length} · 非装备 ${Object.keys(notEq).length}`);
  }

  const sumFile = path.join(Q.CACHE, 'eq_summary.json');
  const prev = fs.existsSync(sumFile) ? JSON.parse(fs.readFileSync(sumFile, 'utf8')) : {};
  const out = {
    eq: Object.keys(eq).length ? eq : (prev.eq || {}),
    notEq: Object.keys(notEq).length ? notEq : (prev.notEq || {}),
    series: Object.keys(seriesQuests).length ? seriesQuests : (prev.series || {}),
    failed,
    at: new Date().toISOString(),
  };
  fs.writeFileSync(sumFile, JSON.stringify(out));
  console.log('产物 =', sumFile);
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
