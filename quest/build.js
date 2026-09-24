/**
 * quest/build.js —— 生成插件数据文件 quest/QuestData.lua（独立脚本，不参与插件运行）
 *
 * 输入：quest/chains.js（人工策展清单） + quest/cache/（fetch.js 抓下来的 JSON）
 * 输出：quest/QuestData.lua（**纯数据**，进 .toc，插件运行期只读它）
 *
 * 用法：node quest/build.js             # 用缓存（缺什么抓什么）
 *       node quest/build.js --force     # 全部重抓
 *
 * 解耦说明：本脚本与插件源码零耦合；生成物是纯数据表（无函数、无 local），
 *   插件侧只通过全局 EVAL_QC_* 读取，改名/换源都不会波及插件逻辑。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const api = require('./fetch.js');
api.bootstrap(__filename); // ★必须在任何网络请求之前（会重启自身一次以带上代理环境变量）

const { CHAINS, SOURCE } = require('./chains.js');

const OUT = path.join(__dirname, 'QuestData.lua');

/** Lua 字符串字面量（转义引号与反斜杠；中文按 UTF-8 原样） */
function L(s) {
  return '"' + String(s == null ? '' : s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[\r\n]+/g, ' ') + '"';
}
/** 数字（整数不带小数点；无效值返回 nil 表示省略该字段） */
function N(v) {
  if (typeof v !== 'number' || !isFinite(v) || v <= 0) return null;
  return Number.isInteger(v) ? String(v) : String(Math.round(v * 10) / 10);
}
/** 拼 {k=v,...}，跳过空值 */
function fields(obj) {
  const parts = [];
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    if (v === null || v === undefined || v === '') continue;
    parts.push(k + '=' + v);
  }
  return '{' + parts.join(',') + '}';
}

(async () => {
  console.log('策展清单:', CHAINS.length, '条链 | 来源:', SOURCE);

  // ---------- ① 抓任务 ----------
  const quests = {};
  const missing = [];
  const qidSet = new Set();
  for (const c of CHAINS) c.quests.forEach(id => qidSet.add(id));
  let n = 0;
  for (const id of [...qidSet].sort((a, b) => a - b)) {
    let rec;
    try { rec = await api.quest(id); } catch (e) { rec = { id, error: e.message }; }
    if (rec.error || !rec.title) { missing.push(id + '(' + (rec.error || 'no-title') + ')'); continue; }
    quests[id] = rec;
    n++;
    if (n % 25 === 0) console.log('  任务', n, '/', qidSet.size);
  }

  // ---------- ② 收集奖励物品并抓物品 ----------
  const rewardIds = new Set();
  for (const rec of Object.values(quests)) {
    for (const it of [...(rec.choose || []), ...(rec.receive || [])]) if (it.id) rewardIds.add(it.id);
  }
  const items = {};
  let m = 0;
  for (const id of [...rewardIds].sort((a, b) => a - b)) {
    let it;
    try { it = await api.item(id); } catch (e) { it = { id, error: e.message }; }
    if (!it.error && it.name) items[id] = it;
    m++;
    if (m % 25 === 0) console.log('  物品', m, '/', rewardIds.size);
  }

  // ---------- ③ 组装链（奖励武器优先排序） ----------
  const chains = [];
  for (const c of CHAINS) {
    const rw = new Set();
    for (const q of c.quests) {
      const rec = quests[q];
      if (!rec) continue;
      for (const it of [...(rec.choose || []), ...(rec.receive || [])]) if (it.id && items[it.id]) rw.add(it.id);
    }
    const sorted = [...rw].sort((a, b) => {
      const A = items[a], B = items[b];
      const aw = A.dps ? 1 : 0, bw = B.dps ? 1 : 0;
      if (aw !== bw) return bw - aw;                       // 武器优先
      if ((B.q || 0) !== (A.q || 0)) return (B.q || 0) - (A.q || 0); // 品质高者先
      return (B.ilvl || 0) - (A.ilvl || 0);
    });
    const gotSteps = c.quests.filter(q => quests[q]);
    if (gotSteps.length !== c.quests.length) {
      console.log('  ⚠ 链', c.key, '缺任务:', c.quests.filter(q => !quests[q]).join(','));
    }
    if (!sorted.length) console.log('  ⚠ 链', c.key, '没有任何奖励物品');
    chains.push({
      key: c.key, name: c.name, f: c.f, t: c.t, lo: c.lo, hi: c.hi, zone: c.zone,
      note: c.note, quests: gotSteps, rewards: sorted,
    });
  }

  // ---------- ④ 生成 Lua ----------
  const stamp = new Date().toISOString().slice(0, 10);
  const lines = [];
  lines.push('-- ============================================================================');
  lines.push('-- QuestData.lua —— 任务线数据（**生成物，请勿手改**）');
  lines.push('--');
  lines.push('-- 数据来源：' + SOURCE + '（逐条抓取核对）');
  lines.push('-- 生成脚本：quest/build.js（策展清单在 quest/chains.js）');
  lines.push('-- 重新生成：node quest/build.js        （加 --force 可全部重抓）');
  lines.push('--');
  lines.push('-- 本文件是**纯数据**：没有函数、没有 local、没有副作用 —— 载入即赋值三个全局表。');
  lines.push('-- 检索逻辑在 quest/QuestChains.lua；界面只在「数据检索」Tab 里用它（解耦约定）。');
  lines.push('-- ============================================================================');
  lines.push('');
  lines.push('EVAL_QC_META = ' + fields({
    src: L(SOURCE), built: L(stamp), chains: chains.length,
    quests: Object.keys(quests).length, items: Object.keys(items).length,
  }));
  lines.push('');
  lines.push('-- 物品：n=名称 q=品质(0粗糙/1普通/2优秀/3精良) il=物品等级 dps=每秒伤害 sp=速度 s=部位 k=类型 st=属性');
  lines.push('EVAL_QC_ITEMS = {');
  for (const id of Object.keys(items).map(Number).sort((a, b) => a - b)) {
    const it = items[id];
    lines.push('  [' + id + ']=' + fields({
      n: L(it.name), q: it.q || null, il: N(it.ilvl), dps: N(it.dps), sp: N(it.speed),
      s: it.slot ? L(it.slot) : null, k: it.kind ? L(it.kind) : null, st: it.stats ? L(it.stats) : null,
    }) + ',');
  }
  lines.push('}');
  lines.push('');
  lines.push('-- 任务：n=名称 lv=任务等级 z=地区 req=需要等级');
  lines.push('EVAL_QC_QUESTS = {');
  for (const id of Object.keys(quests).map(Number).sort((a, b) => a - b)) {
    const q = quests[id];
    lines.push('  [' + id + ']=' + fields({
      n: L(q.title), lv: N(q.level), z: q.zone ? L(q.zone) : null, req: N(q.requires),
    }) + ',');
  }
  lines.push('}');
  lines.push('');
  lines.push('-- 任务线：k=键 n=名称 f=阵营(A联盟/H部落/B双方) t=档位(S/A/B) lo..hi=等级区间 z=地区');
  lines.push('--         note=一句话点评 qs=完整上下级任务序列(按接取顺序) rw=奖励物品(武器优先排序)');
  lines.push('EVAL_QC_CHAINS = {');
  for (const c of chains) {
    lines.push('  ' + fields({
      k: L(c.key), n: L(c.name), f: L(c.f), t: L(c.t), lo: c.lo, hi: c.hi, z: L(c.zone), note: L(c.note),
    }).replace(/}$/, '') +
      ',qs={' + c.quests.join(',') + '},rw={' + c.rewards.join(',') + '}},');
  }
  lines.push('}');
  lines.push('');
  fs.writeFileSync(OUT, lines.join('\n'), 'utf8');

  // ---------- ⑤ 自检 ----------
  const weapons = Object.values(items).filter(i => i.dps);
  console.log('\n=== 生成完成 ===');
  console.log('文件:', OUT, '|', (fs.statSync(OUT).size / 1024).toFixed(1), 'KB');
  console.log('任务', Object.keys(quests).length, '| 物品', Object.keys(items).length, '| 其中武器', weapons.length, '| 链', chains.length);
  if (missing.length) console.log('⚠ 抓取失败的任务:', missing.join(', '));
  console.log('\n链 / 武器奖励:');
  for (const c of chains) {
    const w = c.rewards.map(id => items[id]).filter(i => i.dps).map(i => i.name + (i.q >= 3 ? '(蓝)' : ''));
    console.log('  [' + c.t + ']' + c.name + ' — ' + (w.join(' / ') || '(无武器)'));
  }
})().catch(e => { console.error('ERR:', e.message); process.exit(1); });
