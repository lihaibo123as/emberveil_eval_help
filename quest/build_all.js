/**
 * 生成物：quest/QuestAll.lua —— **全量任务表**（用户 1.75.14 定案「全量任务进包」）
 *   数据来源 = quest/cache/quest_<id>.json（fetch.js 抓下来的任务详情，4018 个，已审计 0 坏档）
 *   ★只读缓存、**不联网**；与 QuestBulk 同一套紧凑串记法（'|' 分隔，生成器保证名字里没有 '|'）。
 *   字段：名|等级|地区|阵营|有装备奖励(0/1)|标签码|需要等级|c:可选奖励id,r|r:直接给予id,r
 *     · 阵营：站点详情页不给 ⇒ 取 QuestBulk.q 里那份（只有带装备奖励的任务有），其余留空（= 不限，与现有口径一致）
 *     · 标签码：站点 tags 归一到短码（d=地下城 e=精英 r=团队 p=PvP s=护送 l=传说 w=世界事件），空 = 无标签
 *     · ★★1.75.21 后三个字段是**本次审计补的**（用户报障「有些属于任务线的，点任务详情是空的」）：
 *       ① 需要等级：站点「需要等级 N」；② ③ 该任务在站点上的**奖励物品**（`可选一件` / `直接给予`）。
 *       ★旧口径只把「带装备奖励」的 751 条收进 QuestBulk ⇒ 其余 3267 条的奖励**整段丢失**，
 *         详情里只能写「无装备奖励」，用户看到的就是「空的」。实测：站点给奖励的任务共 1685 个，
 *         其中 **934 个**不是装备奖励任务（药水/卷轴/任务物品/食谱）—— 这些数据的唯一来源就在这里。
 *       ★奖励物品名进 `iw`（**只写 QuestBulk.i 里没有的**，已有的那边有名字+品质，不重复占字节）。
 *   ★★1.75.21 再补一张**父子任务表** `ch`（用户：「一个任务完成出现另外 2 个后续任务 ⇒ 定义父子任务形式」）：
 *     `ch[id] = "后续任务id,后续任务id"` = **两侧并集**：站点任务页「解锁」行（父侧）+ 「需要」行
 *     （子侧，即前置任务）。由 `tmp/refetch_graph.js` 增量重抓写进缓存（**只加字段、不动既有字段**
 *     ⇒ 奖励数据零回归）。运行期没抓到边的任务退回**系列下一步**（站点「本系列第 N/M 部分」线性顺序）兜底。
 *     ★★边界铁律：站点关系行是**兄弟 div、一行一类**（`解锁` / `需要` / `只能选择一个`）⇒ 取本行自己的
 *       `</div>` 为界 —— 用「下一个面板标题」当界会把「只能选择一个」的**互斥选项**吃成父子边
 *       （实测 #3526 地精/侏儒工程学 = 8 节点完全图）。
 *   用法：node quest/build_all.js
 */
const fs = require('fs');
const path = require('path');
const DIR = __dirname;
const CACHE = path.join(DIR, 'cache');

// ---------- 1) 带装备奖励的任务（用于 gear 标记 + 阵营）+ 已有物品表（避免重复写名字） ----------
const bulkSrc = fs.readFileSync(path.join(DIR, 'QuestBulk.lua'), 'utf8');
const faction = new Map();      // id -> "A"/"H"/""
const bulkItems = new Set();    // QuestBulk.i 里已有名字的物品
let gearN = 0;
{
  let cur = null;
  for (const ln of bulkSrc.split('\n')) {
    const sec = ln.match(/^\s*([A-Za-z_]\w*)\s*=\s*\{\s*$/);
    if (sec) { cur = sec[1]; continue; }
    if (/^\s*\}\s*,?\s*$/.test(ln)) { cur = null; continue; }
    if (cur === 'q') {
      const m = ln.match(/^\s*\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$/);
      if (!m) continue;
      gearN++;
      faction.set(Number(m[1]), m[2].split('|')[3] || '');
    } else if (cur === 'i') {
      const m = ln.match(/^\s*\[(\d+)\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*,?\s*$/);
      if (m) bulkItems.add(Number(m[1]));
    }
  }
}

// ---------- 1b) 奖励归一：站点「可选一件」块里会混进「你还将得到：」那一段 + 数量行 ----------
//   实测 #103 长明的灯塔：choose 里混着数量行「3」与「你还将得到：」之后的两张卷轴；
//   #127 卖鱼的 receive 里混着数量「5」。⇒ 判据 = **有链接（有 id）才算奖励物品**，
//   数量/表头一律丢弃；「你还将得到：」之后的条目归到**直接给予**。
const MARK_ALSO = /^你还将得到|^你还将会得到|^另外你将得到/;
function normRewards(ch, rc) {
  const choose = [], extra = [], recv = [];
  let after = false;
  for (const x of ch || []) {
    if (typeof x.name === 'string' && MARK_ALSO.test(x.name)) { after = true; continue; }
    if (!x.id) continue;
    (after ? extra : choose).push(x);
  }
  for (const x of rc || []) if (x.id) recv.push(x);
  const seen = new Set(), c2 = [], r2 = [];
  for (const x of choose) if (!seen.has(x.id)) { seen.add(x.id); c2.push(x.id); }
  for (const x of recv.concat(extra)) if (!seen.has(x.id)) { seen.add(x.id); r2.push(x.id); }
  return { choose: c2, receive: r2 };
}

// ---------- 2) 扫缓存 ----------
const TAGMAP = [
  [/地下城/, 'd'], [/精英/, 'e'], [/团队|Raid/i, 'r'], [/PvP/i, 'p'],
  [/护送/, 's'], [/传说/, 'l'], [/世界事件/, 'w'],
];
const files = fs.readdirSync(CACHE).filter((f) => /^quest_\d+\.json$/.test(f));
const rows = [];
const iw = new Map();           // 奖励物品 id -> 名字（只写 QuestBulk.i 里没有的）
const chRows = [];              // 父子任务：{ id, s: "子id,子id" }
const rawCh = [];               // 父侧（站点「解锁」）原样收集，过完全表再过滤
const rawNeed = [];             // 子侧（站点「需要」= 前置任务）原样收集
const rawObj = [];              // 任务目标材料原样收集（{ id, ids, names, needs }）
let chBoth = 0, chOnlyU = 0, chOnlyN = 0;   // 两侧一致的边 / 只在解锁 / 只在需要
let skipped = 0, rwQuests = 0, rwRefs = 0, chEdges = 0;
for (const f of files) {
  let o;
  try { o = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8')); } catch (e) { skipped++; continue; }
  const id = Number(o.id || f.match(/quest_(\d+)\.json/)[1]);
  const name = String(o.title || '').replace(/\|/g, '/').trim();
  if (!id || !name) { skipped++; continue; }
  const lv = Number(o.level) || 0;
  const zone = String(o.zone || '').replace(/\|/g, '/').trim();
  const fac = faction.get(id) || '';
  const gear = faction.has(id) ? 1 : 0;
  const tags = String(o.tags || '');
  let code = '';
  for (const [re, c] of TAGMAP) if (re.test(tags)) code += c;
  const req = Number(o.requires) || 0;
  const { choose, receive } = normRewards(o.choose, o.receive);
  if (choose.length || receive.length) rwQuests++;
  rwRefs += choose.length + receive.length;
  for (const x of choose.concat(receive)) {
    if (bulkItems.has(x)) continue;
    const src = (o.choose || []).concat(o.receive || []).find((z) => z.id === x);
    if (src && src.name) iw.set(x, String(src.name).replace(/\|/g, '/').replace(/"/g, '').trim());
  }
  const rwField = (choose.length ? '|c:' + choose.join(',') : '') + (receive.length ? '|r:' + receive.join(',') : '');
  rows.push({ id, s: `${name}|${lv}|${zone}|${fac}|${gear}|${code}|${req}${rwField}` });
  // 父子任务：先原样收**两侧**（`解锁` = 父侧 / `需要` = 子侧），过完全部任务再合并过滤
  if (Array.isArray(o.unlocks) && o.unlocks.length) rawCh.push({ id, kids: o.unlocks });
  if (Array.isArray(o.needs) && o.needs.length) rawNeed.push({ id, pars: o.needs });
  // 需求材料：原样收，过完全表后按**物品页的 Quest Item 标记**剔除任务道具
  if (Array.isArray(o.objectives) && o.objectives.length) rawObj.push({
    id, ids: o.objectives, names: o.objectiveNames || [], needs: o.objectiveNeeds || [],
  });
}
rows.sort((a, b) => a.id - b.id);
// ---------- 2b) 需求材料（1.75.22）：**剔除任务道具**（判据 = 物品页有没有 `Quest Item` 标记） ----------
//   ★用户原话：「只筛选显示制造业/普通物品等，而非任务道具」——任务道具（石板/徽记/头颅这类）是噪声，
//     玩家真正要准备的是交易品/消耗品/配方/装备。
//   ★判不出（物品页没抓到）⇒ **保留**并计数（项目铁律：判不出就不剔），候选名单如实告知。
const itemMeta = new Map();
const itemMetaOf = (id) => {
  if (itemMeta.has(id)) return itemMeta.get(id);
  let m = null;
  try { m = JSON.parse(fs.readFileSync(path.join(CACHE, 'item_' + id + '.json'), 'utf8')); } catch (e) { m = null; }
  itemMeta.set(id, m);
  return m;
};
const obRows = [], owNames = new Map();
let objQuests = 0, objKept = 0, objDrop = 0, objUnknown = 0;
for (const e of rawObj) {
  // ★同一件材料在站点目标块里可能出现**多行**（如「后勤任务简报 X」出现两次，一次 `0/1` 一次 `0/0`）
  //   ⇒ 按 id **合并取最大数量**（不合并就会出现两个一样的图标；`need=0` 的不写「×0」但图标保留）
  const keep = new Map();
  for (let k = 0; k < e.ids.length; k++) {
    const iid = e.ids[k];
    const meta = itemMetaOf(iid);
    if (meta && meta.questItem === true) { objDrop++; continue; }   // 任务道具 ⇒ 剔掉
    if (!meta || typeof meta.questItem !== 'boolean') objUnknown++;
    const prev = keep.get(iid) || 0;
    keep.set(iid, Math.max(prev, e.needs[k] || 0));
    if (!owNames.has(iid)) {
      const nm = String((meta && meta.name) || e.names[k] || '').replace(/\|/g, '/').replace(/"/g, '').trim();
      const qv = Number(meta && meta.q);
      owNames.set(iid, nm + '|' + (Number.isFinite(qv) ? qv : 1));
    }
  }
  if (keep.size > 0) {
    const parts = [];
    for (const [iid, n] of keep) parts.push(iid + ':' + n);
    objQuests++; objKept += parts.length;
    obRows.push({ id: e.id, s: parts.join(',') });
  }
}
obRows.sort((a, b) => a.id - b.id);

// ---------- 3) 写 Lua ----------
// 父子表：**两侧并集**（站点把同一层关系从两头各写一行）—— 不一致的部分**如实计数**，不藏也不猜。
//   ★只留两头都在本表里的边；自环一律丢（生成器与运行期双保险）。
{
  const known = new Set(rows.map(r => r.id));
  const up = new Map(), dn = new Map();
  const put = (m, p, c) => { if (!m.has(p)) m.set(p, new Set()); m.get(p).add(c); };
  for (const e of rawCh) for (const c of e.kids) if (known.has(c) && c !== e.id) put(up, e.id, c);
  for (const e of rawNeed) for (const p of e.pars) if (known.has(p) && p !== e.id) put(dn, p, e.id);
  const parents = new Set([...up.keys(), ...dn.keys()]);
  for (const p of [...parents].sort((a, b) => a - b)) {
    const a = up.get(p) || new Set(), b = dn.get(p) || new Set();
    const kids = [...new Set([...a, ...b])].sort((x, y) => x - y);
    chEdges += kids.length;
    for (const k of kids) {
      const inA = a.has(k), inB = b.has(k);
      if (inA && inB) chBoth++; else if (inA) chOnlyU++; else chOnlyN++;
    }
    chRows.push({ id: p, s: kids.join(',') });
  }
}

// ---------- 3) 写 Lua ----------
const out = [];
out.push('-- ★★★本文件是**生成物**，绝不手改（改生成器 quest/build_all.js 后重跑：node quest/build_all.js）');
out.push('-- 全量任务表（用户 1.75.14 定案「全量任务进包」）：含**没有装备奖励**的任务，便于按名/按地区检索。');
out.push('--   q[id] = 名称|任务等级|地区|阵营(A/H/空=不限)|有装备奖励(0/1)|标签码(d地下城 e精英 r团队 pPvP s护送 l传说 w世界事件)');
out.push('--           |需要等级|c:可选奖励物品id,r|r:直接给予物品id,r（后两项没有就整段省略）');
out.push('--   iw[id] = 奖励物品名（**只收 QuestBulk.i 里没有的**：那边已有名字+品质，不重复占字节）');
out.push('--   ch[id] = **后续（子）任务 id**，来自站点任务页「解锁」面板（一个任务可带多个后续）；');
out.push('--            运行期没有这条时退回「系列下一步」兜底（见 QuestChains 的 EVAL_QC_QUEST_NEXT）。');
out.push('--   ob[id] = **需求材料** `物品id:需要数量,…`（★**生成期已剔除任务道具** —— 判据 = 物品页有无');
out.push('--            `Quest Item` 标记；用户要求「只显示制造业/普通物品，而非任务道具」）；`ow[id]="名|品质"`。');
out.push('--   数据来源 = 官方库任务详情页（' + files.length + ' 个，已抓取缓存）；阵营取自带装备奖励那份表（详情页不提供）。');
out.push('EVAL_QC_ALL = {');
out.push('  meta = { src = "database.emberveil.org", built = "' + new Date().toISOString().slice(0, 10) + '", n = ' + rows.length +
  ', rw = ' + rwQuests + ', ch = ' + chRows.length + ', chEdge = ' + chEdges +
  ', ob = ' + obRows.length + ', obNeed = ' + objKept + ' },');
out.push('  q = {');
let line = '   ';
for (const r of rows) {
  const piece = `[${r.id}]="${r.s}",`;
  if (line.length + piece.length > 118) { out.push(line); line = '   '; }
  line += piece;
}
if (line.trim() !== '') out.push(line);
out.push('  },');
out.push('  iw = {');
line = '   ';
for (const [id, nm] of [...iw.entries()].sort((a, b) => a[0] - b[0])) {
  const piece = `[${id}]="${nm}",`;
  if (line.length + piece.length > 118) { out.push(line); line = '   '; }
  line += piece;
}
if (line.trim() !== '') out.push(line);
out.push('  },');
out.push('  ch = {');
line = '   ';
for (const r of chRows) {
  const piece = `[${r.id}]="${r.s}",`;
  if (line.length + piece.length > 118) { out.push(line); line = '   '; }
  line += piece;
}
if (line.trim() !== '') out.push(line);
out.push('  },');
out.push('  ob = {');
line = '   ';
for (const r of obRows) {
  const piece = `[${r.id}]="${r.s}",`;
  if (line.length + piece.length > 118) { out.push(line); line = '   '; }
  line += piece;
}
if (line.trim() !== '') out.push(line);
out.push('  },');
out.push('  ow = {');
line = '   ';
for (const [id, s] of [...owNames.entries()].sort((a, b) => a[0] - b[0])) {
  const piece = `[${id}]="${s}",`;
  if (line.length + piece.length > 118) { out.push(line); line = '   '; }
  line += piece;
}
if (line.trim() !== '') out.push(line);
out.push('  },');
out.push('}');
const dst = path.join(DIR, 'QuestAll.lua');
fs.writeFileSync(dst, out.join('\n') + '\n', 'utf8');
const size = fs.statSync(dst).size;
console.log('缓存任务详情 = ' + files.length + ' ｜ 写入行数 = ' + rows.length + ' ｜ 跳过 = ' + skipped);
console.log('带装备奖励(gear=1) = ' + gearN + ' ｜ **站点给奖励的任务 = ' + rwQuests + '**（物品引用 ' + rwRefs + ' · 新增物品名 ' + iw.size + '）');
console.log('**父子任务 = ' + chRows.length + ' 个父任务 / ' + chEdges + ' 条后续边**' +
  '（两侧一致 ' + chBoth + ' ｜ 只在「解锁」' + chOnlyU + ' ｜ 只在「需要」' + chOnlyN + '）');
console.log('**需求材料 = ' + objQuests + ' 个任务 / ' + objKept + ' 条材料**（剔除任务道具 ' + objDrop +
  ' · 物品页缺失而保留 ' + objUnknown + ' · 材料名表 ' + owNames.size + '）');
console.log('产物 = quest/QuestAll.lua  ' + (size / 1024).toFixed(1) + ' KB');
// 抽查：血色修道院的 7 个任务应在
const sm = rows.filter((r) => r.s.split('|')[2] === '血色修道院');
console.log('抽查 血色修道院 = ' + sm.length + ' 个：' + sm.map((r) => r.s.split('|')[0] + '(' + r.s.split('|')[1] + ',gear' + r.s.split('|')[4] + ')').join(' · '));
