/**
 * quest/build_bulk.js —— 生成 quest/QuestBulk.lua（**全量**装备/任务数据，独立脚本）
 *
 * 与 quest/build.js（人工策展 22 条链）的分工：
 *   · build.js      → QuestData.lua：策展任务线（10-30 经典线，人工定稿的档位/点评）
 *   · build_bulk.js → QuestBulk.lua：**全量**（10-60+ 所有带装备奖励的任务 + 自动拼出的任务线）
 *
 * 输入缓存（都由 sweep.js / sweep_details.js 抓下）：
 *   cache/sweep_10_60.json  任务列表行（id/等级/名称/地区/标签/奖励物品 id+品质+图标）
 *   cache/eq_summary.json   物品页（装备判定/名称/属性）+ 任务详情页（「本系列第 N/M 部分」）
 * 输出：quest/QuestBulk.lua（纯数据：EVAL_QC_BULK = { meta=…, q=…, i=…, s=…, sn=… }）
 *
 * 用法：node quest/build_bulk.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const CACHE = path.join(ROOT, 'cache');
const OUT = path.join(ROOT, 'QuestBulk.lua');
const SOURCE = 'database.emberveil.org';
const SEP = '|';                       // 记录内分隔符（生成前**证明**名字里不会出现）
const OPEN_RE = /之门|节杖|开门|门扉|钥匙|传送门|流沙|入侵|纳克萨玛斯|黑翼|熔火|安其拉|奥妮克希亚|克尔苏加德|泰坦|奎尔塞拉|雷霆之怒|风剑|灰烬|史诗|传说/;
// 档位（**按站点自报的系列长度**分档，不是质量评价）：≥8 步 = S（大型/史诗线）· ≥5 步 = A · 其余 B
const TIER_S = 8, TIER_A = 5;

const L = s => '"' + String(s == null ? '' : s).replace(/[\\"]/g, c => '\\' + c).replace(/[\r\n]+/g, ' ')
  .replace(/[\x00-\x1f]/g, c => '\\' + c.charCodeAt(0)) + '"';

function readJson(f, what) {
  const p = path.join(CACHE, f);
  if (!fs.existsSync(p)) throw new Error('缺 ' + p + '（先跑 node quest/sweep.js 与 node quest/sweep_details.js）—— ' + what);
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

const sweep = readJson('sweep_10_60.json', '任务列表行');
const detail = readJson('eq_summary.json', '物品/任务详情');
const eq = detail.eq || {}, notEq = detail.notEq || {};
// ★id 补全件（与审计共用一份口径）：站点有些页面的系列块**只给步骤名不给链接**，
//   用「任务名 → id」把缺的补上（候选要过 part/total 交叉验证）——否则经典线会只剩 1 步。
const R = require('./resolve.js');
const nameIndex = R.buildNameIndex(CACHE, sweep.quests);
const seriesById = R.buildSeriesById(CACHE);
console.log('名字索引', Object.keys(nameIndex).length, '个任务名 · 系列记录表', Object.keys(seriesById).length, '条');

// 系列（任务线归属）从**全部任务详情缓存**里汇总 —— 不只是「有装备奖励的那 346 条」：
//   30-60 的经典线 / 大型线 / 开门线大多不以装备奖励为主，但它们的详情页同样写着「本系列第 N/M 部分」。
const seriesOf = {};
{
  let n = 0;
  for (const f of fs.readdirSync(CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    let rec = null;
    try { rec = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8')); } catch (e) { continue; }
    if (rec && rec.series && rec.series.steps && rec.series.steps.length >= 2) {
      // 归一成与 eq_summary 同一形状（part/total/steps 提到顶层），下游只认这一种
      seriesOf[rec.id] = {
        id: rec.id, title: rec.title, level: rec.level, zone: rec.zone,
        part: rec.series.part, total: rec.series.total, steps: rec.series.steps,
      };
      n++;
    }
  }
  console.log('任务详情缓存：带系列的任务', n, '条（目录里 quest_*.json 共',
    fs.readdirSync(CACHE).filter(f => /^quest_\d+\.json$/.test(f)).length, '条）');
}

/** 名字里绝不许出现分隔符（撞了就是数据错位，宁可当场失败也不写坏生成物） */
const bad = [];
const guard = (s, where) => { if (typeof s === 'string' && s.indexOf(SEP) >= 0) bad.push(where + '=' + s); };

// ---------- ① 物品表（**先算被引用的物品**，再装表；装备视图另按 eq 过滤） ----------
const sweepById = {};
for (const q of sweep.quests) sweepById[q.id] = q;
// 详情缓存里的等级也当依据（种子任务/低等级前置任务可能不在 10-60 列表行里）
const lvlOf = {};
for (const f of fs.readdirSync(CACHE)) {
  if (!/^quest_\d+\.json$/.test(f)) continue;
  try {
    const r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8'));
    if (r && r.id && r.level) lvlOf[r.id] = r.level;
  } catch (e) {}
}
for (const q of sweep.quests) if (!lvlOf[q.id]) lvlOf[q.id] = q.lv;
// ★奖励的**权威来源 = 任务详情页**（1.75.9 审计实证）：列表页的奖励图标是**截断显示**的
//   （实测 #451 列表只画了 2458，详情页的「选择一件/直接给予」还有 2459）⇒ 只信列表页会漏奖励，
//   装备视图就会漏件。这里取**两者并集**：详情页优先，列表页补齐（详情页没抓到的任务仍可用）。
const detailRw = {};
const questItemName = {};   // ★物品页拿不到名字时的兜底：任务详情页的奖励链接文本里就有名字
                            //   （实测：白/灰物品无「拾取后绑定」行 ⇒ parseItemDetail 的名字启发式落空，
                            //     但任务页的 `<a href="/item/ID">名字</a>` 一定有 —— 24 件无名称就是这批）
for (const f of fs.readdirSync(CACHE)) {
  if (!/^quest_\d+\.json$/.test(f)) continue;
  try {
    const r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8'));
    if (!r || !r.id) continue;
    const all = [...(r.choose || []), ...(r.receive || [])];
    const ids = all.map(x => x.id).filter(Boolean);
    if (ids.length) detailRw[r.id] = ids;
    for (const x of all) if (x.id && x.name && !questItemName[x.id]) questItemName[x.id] = x.name;
  } catch (e) {}
}
console.log('任务详情缓存里带奖励的任务', Object.keys(detailRw).length, '条（与列表页取并集）');
// ★只装「奖励里**有装备**」的任务（用户要求：任务奖励只要有装备/武器的都可以采集，单任务也算）——
//   非装备任务不进包：它们不参与装备视图，装进去只是白占客户端内存（1.12 客户端内存有限）。
const allWanted = sweep.quests.filter(q => q.rewards.some(r => eq[r.id]) || (detailRw[q.id] || []).some(id => eq[id]));
const wanted = allWanted;
const questRows = [];
const stepNames = {};                 // 自动任务线里出现、但不在任务表里的步骤名（id → 名）
const usedItems = {};                 // 实际被这些任务用到的物品（物品表只装这些，别把 1882 件全塞进去）
const namelessItems = [];             // 物品页解析不出名字的（审计要报出来，便于重抓）
for (const q of wanted) {
  guard(q.name, 'quest' + q.id); guard(q.zone, 'zone' + q.id);
  const rw = [...new Set([...(q.rewards || []).map(r => r.id), ...(detailRw[q.id] || [])])];
  for (const id of rw) usedItems[id] = 1;
  questRows.push('[' + q.id + ']=' + L([q.name, q.lv, q.zone || '', q.tag || '', rw.join(',')].join(SEP)) + ',');
}
console.log('任务：带装备奖励', wanted.length, '条 · 引用到的奖励物品', Object.keys(usedItems).length, '件');
// ---------- ①′ 物品表：只装被上面这些任务引用到的物品（装备 + 它们的杂物奖励；装备视图另按 eq 过滤） ----------
const itemRows = [];
for (const id of Object.keys(usedItems).map(Number).sort((a, b) => a - b)) {
  const r = eq[id] || notEq[id];
  if (!r) continue;
  const isEq = !!eq[id];
  const nm = r.n || questItemName[id] || '';
  if (!nm) { namelessItems.push(id); continue; }   // 两边都拿不到名字 ⇒ 不装（界面会出现空行；审计里如实计数）
  guard(nm, 'item' + id);
  itemRows.push('[' + id + ']=' + L([nm, r.q != null ? r.q : 1, r.ilvl || 0, r.dps || 0, r.sp || 0,
    r.s || '', r.k || '', r.st || '', r.icon || '', isEq ? 1 : 0].join(SEP)) + ',');
}
console.log('物品表：', itemRows.length, '件（其中装备', Object.keys(eq).filter(id => usedItems[id]).length, '· 无名称', namelessItems.length, '）');

// ---------- ③ 自动任务线（站点自报的「本系列第 N/M 部分」拼出来） ----------
// ★两道体检（1.75.9 数据质量事故的补丁）：
//   ① `series.trusted`：id 覆盖率 <50% 的页直接**不采信**（旧解析器错位时就是这种形状）
//   ② 去重**两级**：先按「步数 + id 集合重叠 ≥60%」聚类（同系列各成员页解出的 id 有±1 差别），
//      再按「首位步骤名 + 步数」兜底合并同名同长的线（站点同一系列在不同页上 total 会差 1 的场景也收住）。
const clusters = [];
let dropped = 0, incomplete = 0, byNameN = 0;
for (const raw of Object.values(seriesOf)) {
  if (!raw.total || raw.total < 2 || !raw.steps || !raw.steps.length) continue;
  // ① 先用「名字 → id」把站点没给链接的步骤补上（候选过 part/total 交叉验证，见 resolve.js）
  const rec = R.fillSeriesIds(raw, nameIndex, seriesById);
  byNameN += rec.byName;
  // ② 补完仍不全的**不采信**（用户要求「任务线是否完整」要能审出来）
  if (!rec.trusted) { dropped++; continue; }
  const ids = rec.steps.map(s => s.id).filter(Boolean);
  if (ids.length < 2) { dropped++; continue; }
  if (ids.length !== rec.total) { incomplete++; continue; }
  const idSet = new Set(ids);
  let best = null, bestJ = 0;
  for (const c of clusters) {
    if (c.total !== rec.total) continue;
    let inter = 0;
    for (const id of idSet) if (c.ids.has(id)) inter++;
    const j = inter / (idSet.size + c.ids.size - inter);
    if (j > bestJ) { bestJ = j; best = c; }
  }
  if (best && bestJ >= 0.6) {
    for (const id of idSet) best.ids.add(id);
    if (ids.length > best.rec.steps.filter(s => s.id).length) best.rec = rec;
  } else {
    clusters.push({ total: rec.total, ids: idSet, rec });
  }
}
console.log('id 补全：按名字补出', byNameN, '个步骤 id');
const byKey = {};
for (const c of clusters) {
  const steps = c.rec.steps.filter(s => s.id).sort((a, b) => a.n - b.n);
  const nm = (steps[0] && steps[0].name) || '';
  // 末尾两位步骤名相同才算同一条（防「同名不同线」被误并）
  const tail = (steps[steps.length - 1] && steps[steps.length - 1].name) || '';
  const key = nm + '#' + c.total + '#' + tail;
  const cur = byKey[key];
  if (!cur || c.ids.size > cur.ids.size) byKey[key] = c;
}
const finalSeries = Object.keys(byKey).map(k => byKey[k].rec);
console.log('系列去重：聚类', clusters.length, '→ 合并后', finalSeries.length, '条');
console.log('系列体检：采信', finalSeries.length, '条 · 丢弃', dropped, '条（id 覆盖不足）· 不完整丢弃', incomplete, '条（步骤数 < 站点自报）');
const seriesRows = [];
const seriesList = [];
let bigN = 0, openN = 0, unresolved = 0;
for (const rec of finalSeries) {
  const steps = rec.steps.filter(s => s.id).sort((a, b) => a.n - b.n);
  const ids = steps.map(s => s.id);
  const names = steps.map(s => s.name || '');
  const unresolvedHere = ids.filter((id, i) => !sweepById[id] && !names[i]);
  unresolved += unresolvedHere.length;
  for (let i = 0; i < ids.length; i++) if (!sweepById[ids[i]] && names[i]) stepNames[ids[i]] = names[i];
  // 等级区间：能从任务表/列表行/详情缓存读到的步骤里取
  const lvs = ids.map(id => lvlOf[id] || 0).filter(v => v > 0);
  const lo = lvs.length ? Math.min(...lvs) : 0, hi = lvs.length ? Math.max(...lvs) : 0;
  const zone = (sweepById[ids[0]] || {}).zone || '';
  const t = ids.length >= TIER_S ? 'S' : (ids.length >= TIER_A ? 'A' : 'B');
  const open = names.some(n => OPEN_RE.test(n)) || ids.some(id => OPEN_RE.test((sweepById[id] || {}).name || ''));
  if (t === 'S') bigN++;
  if (open) openN++;
  guard(names[0], 'series' + ids[0]);
  seriesRows.push(L([names[0] || ('系列 ' + ids[0]), lo, hi, zone, t, open ? 1 : 0, ids.join(',')].join(SEP)) + ',');
  seriesList.push({ ids, t, open, lo, hi });
}

// ---------- ④ 写文件 ----------
const stamp = new Date().toISOString().slice(0, 10);
const lines = [];
lines.push('-- ============================================================================');
lines.push('-- QuestBulk.lua —— **全量**任务/装备数据（生成物，请勿手改）');
lines.push('--');
lines.push('-- 数据来源：' + SOURCE + '/quests（站点页面逐条抓取）');
lines.push('-- 生成脚本：quest/build_bulk.js（抓取在 sweep.js / sweep_details.js，缓存可重跑）');
lines.push('-- 重新生成：node quest/sweep.js 10 60 && node quest/sweep_details.js all && node quest/build_bulk.js');
lines.push('--');
lines.push('-- 纯数据：无函数、无 local、无副作用 —— 载入即赋值一个全局表。');
lines.push('-- 记法（分隔符 ' + SEP + '，生成前已校验任何名字都不含它）：');
lines.push('--   q[id]  = 名称' + SEP + '任务等级' + SEP + '地区' + SEP + '阵营(A联盟/H部落/空=不限)' + SEP + '奖励物品id,id');
lines.push('--   i[id]  = 名称' + SEP + '品质' + SEP + '物品等级' + SEP + '每秒伤害' + SEP + '速度' + SEP + '部位' + SEP + '类型' + SEP + '属性' + SEP + '图标名' + SEP + '是否装备');
lines.push('--   s[n]   = 系列名' + SEP + '最低等级' + SEP + '最高等级' + SEP + '地区' + SEP + '档位(按系列长度 S>=8/A>=5/B)' + SEP + '是否开门/史诗' + SEP + '步骤任务id,id');
lines.push('--   sn[id] = 系列步骤名（该步骤任务本身没有装备奖励、不在 q 表里时用它）');
lines.push('-- 逻辑层在 quest/QuestChains.lua（EVAL_QC_BULK_*）；界面只在「数据检索」Tab 用它。');
lines.push('-- ============================================================================');
lines.push('');
lines.push('EVAL_QC_BULK = {');
lines.push('meta={src=' + L(SOURCE) + ',built=' + L(stamp) + ',quests=' + questRows.length +
  ',items=' + itemRows.length + ',equip=' + Object.keys(eq).length + ',series=' + seriesRows.length + '},');
lines.push('i={');
lines.push(...itemRows.map(l => '  ' + l));
lines.push('},');
lines.push('q={');
lines.push(...questRows.map(l => '  ' + l));
lines.push('},');
lines.push('s={');
lines.push(...seriesRows.map(l => '  ' + l));
lines.push('},');
lines.push('sn={');
lines.push(...Object.keys(stepNames).map(Number).sort((a, b) => a - b).map(id => '  [' + id + ']=' + L(stepNames[id]) + ','));
lines.push('},');
lines.push('}');
lines.push('');

if (bad.length) {
  console.error('✖ 名字里出现分隔符 ' + SEP + '，已拒绝写出生成物：', bad.slice(0, 5));
  process.exit(1);
}
fs.writeFileSync(OUT, lines.join('\n'), 'utf8');
console.log('生成完成:', OUT, '|', (fs.statSync(OUT).size / 1024).toFixed(1), 'KB');
console.log('任务', questRows.length, '| 物品', itemRows.length, '（装备', Object.keys(eq).length, '）| 自动任务线', seriesRows.length,
  '（S 档大型', bigN, '· 开门/史诗', openN, '）| 系列步骤名补充', Object.keys(stepNames).length, '| 未解析步骤', unresolved);
const lvN = {};
for (const q of wanted) { const b = Math.floor(q.lv / 10) * 10; const k = b + '-' + (b + 9); lvN[k] = (lvN[k] || 0) + 1; }
console.log('任务按等级段:', JSON.stringify(lvN));
