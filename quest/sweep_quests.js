/**
 * quest/sweep_quests.js —— 批量抓「任务详情页」（拿站点自报的「本系列第 N/M 部分」= 任务线归属）
 *
 * 为什么需要它（用户 1.75.9 第 2 条）：
 *   只抓「有装备奖励」的任务，只能拼出 20 条低等级小线（10-31）。
 *   要覆盖 **30-60 的经典线 / 大型线 / 各种开门线**，必须把该等级段的任务详情页也抓下来，
 *   因为「这条任务属于哪条系列、第几部分、整条系列有多少步」**只写在任务详情页里**。
 *
 * 特点：可中断重跑（每页一条 JSON 缓存）；并发 3（单条 ≈1.2s，别一次轰服务器）；
 *       失败重试交给 fetch.js；进度每 50 条一行。
 *
 * 用法：node quest/sweep_quests.js [lo] [hi] [--seed]
 *   lo/hi   等级区间（默认 30 60）
 *   --seed  额外把「名人任务线」关键词搜一遍（安其拉/纳克萨玛斯/黑翼/奥妮克希亚…），
 *           保证开门/史诗线一定进数据（它们未必落在 30-60 段里）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const SEEDS = [
  '流沙节杖', '安其拉', '纳克萨玛斯', '黑翼之巢', '奥妮克希亚', '熔火之心', '黑石塔', '黑石深渊',
  '奎尔塞拉', '雷霆之怒', '泰坦', '达隆郡', '爱与家庭', '林克', '通灵学院', '斯坦索姆', '厄运之槌',
  '祖尔格拉布', '沉没的神庙', '玛拉顿', '剃刀高地', '剃刀沼泽', '奥达曼', '祖尔法拉克', '乌特加德',
  '血色修道院', '诺莫瑞根', '黑暗深渊', '哀嚎洞穴', '死亡矿井', '暴风城监狱', '影牙城堡',
  '猎人史诗', '牧师史诗', '术士史诗', '圣骑士史诗', '战士史诗', '德鲁伊史诗', '萨满史诗',
  '钥匙', '传送', '开门', '史诗', '传说', '灰烬使者', '风剑', '米拉之歌', '银月',
];

const args = process.argv.slice(2);
const seedMode = args.includes('--seed');
const nums = args.filter(a => !a.startsWith('--')).map(Number).filter(n => n > 0);
const LO = nums[0] || 30, HI = nums[1] || 60;
const CONC = 3;
const sleep = ms => new Promise(r => setTimeout(r, ms));

function readJson(f) { return JSON.parse(fs.readFileSync(path.join(Q.CACHE, f), 'utf8')); }

(async () => {
  Q.ensureCache();
  const sweep = readJson('sweep_10_60.json');
  const ids = sweep.quests.filter(q => q.lv >= LO && q.lv <= HI).map(q => q.id);
  console.log(`[任务详情] 等级 ${LO}-${HI}：${ids.length} 条（并发 ${CONC}，可中断重跑）`);

  if (seedMode) {
    let added = 0;
    for (const kw of SEEDS) {
      let hits = [];
      try { hits = await Q.searchQuest(kw); } catch (e) { console.log('  搜索失败', kw, e.message); }
      for (const id of hits.slice(0, 12)) if (ids.indexOf(id) < 0) { ids.push(id); added++; }
      console.log(`  种子「${kw}」→ ${hits.length} 命中，累计新增 ${added}`);
      await sleep(250);
    }
    console.log(`[种子] 额外加入 ${added} 条候选任务`);
  }

  let done = 0, cachedN = 0, bad = 0, withSeries = 0;
  const queue = ids.slice();
  async function worker() {
    while (queue.length) {
      const id = queue.shift();
      const f = path.join(Q.CACHE, `quest_${id}.json`);
      const wasCached = fs.existsSync(f);
      let rec = null;
      try { rec = await Q.quest(id); } catch (e) { bad++; }
      if (wasCached) cachedN++;
      done++;
      if (rec && rec.series) withSeries++;
      if (done % 50 === 0) console.log(`  任务 ${done}/${ids.length}（带系列 ${withSeries} · 失败 ${bad} · 已缓存 ${cachedN}）`);
      if (!wasCached) await sleep(250);
    }
  }
  await Promise.all(Array.from({ length: CONC }, worker));
  console.log(`完成：${ids.length} 条（新抓 ${ids.length - cachedN} · 已缓存 ${cachedN} · 失败 ${bad} · 带系列 ${withSeries}）`);
  // 汇总：现在缓存里一共有多少条带系列的任务（给 build_bulk 用）
  const files = fs.readdirSync(Q.CACHE).filter(f => /^quest_\d+\.json$/.test(f));
  let ser = 0;
  for (const f of files) {
    try { const r = JSON.parse(fs.readFileSync(path.join(Q.CACHE, f), 'utf8')); if (r.series && r.series.steps) ser++; } catch (e) {}
  }
  console.log(`缓存里带「本系列第 N/M 部分」的任务共 ${ser} 条 / 任务详情缓存 ${files.length} 条`);
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
