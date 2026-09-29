/**
 * gen_itemprices.js —— 生成 ItemPriceData.lua（全量**基准收购价**表）
 *
 * 为什么需要这张表：本客户端**没有**「由物品 id 拿售价」的 API（`GetItemInfo` 停在 texture，已按官方 wiki 原文核过）
 * ⇒ 插件只能「在商人处学价」，**没去过商人**的物品就一个价都没有。这张表用来兜住那种情况。
 *
 * ★★数据流水线（两段，**上游不再是另一个插件的目录**）：
 *   ① 快照（本仓库自带）：`doc/items-vanilla-prices.txt` —— 一行一条 `id,sell,buy`（铜）。
 *      默认**只读它**；它不在 .toc 里 ⇒ 不加载、不占脚本内存。
 *   ② 生成物：`ItemPriceData.lua`（`EVAL_IP_BASE`）—— 本脚本写出，**绝不手改**。
 *
 * 用法：
 *   node gen_itemprices.js              读 doc/items-vanilla-prices.txt → 写 ItemPriceData.lua（幂等）
 *   node gen_itemprices.js --from <路径> --vendor   换来源时把指定上游重新导出成本仓库快照（一次性）
 *
 * ★本脚本**不内置任何第三方路径**：默认只认本仓库自带的快照；要换来源就显式 `--from` 指定，
 *   导出完那一步就结束了 —— 之后生成只读快照，上游删掉也不影响。
 *   上游形态 = Lua 表 `[id] = "sell,buy"`（例如某份公开的 Vanilla 1.12 物品数据）；许可与出处记在
 *   `doc/物品价数据-出处与许可.md`（改来源时同步更新那一节）。
 *
 * ★★★诚实边界（同时写进生成物头部）：
 *   ① 这是 **Vanilla 1.12 物品数据快照、不是 Emberveil 实测数据**：本服**新增**物品这里没有行（按「无价」处理）；
 *      本服**改过价**的物品会先显示快照价，直到你在商人处学到真价（学到即永久覆盖）。
 *   ② `sell=0` = 不可卖、`buy=0` = 没有商人卖 —— 两者都当**无价**，绝不当作免费。
 */
const fs = require('fs');
const path = require('path');

const SEED = path.join(__dirname, 'doc', 'items-vanilla-prices.txt');
const DST = path.join(__dirname, 'ItemPriceData.lua');

const argv = process.argv.slice(2);
const wantVendor = argv.includes('--vendor');
const fromIdx = argv.indexOf('--from');
const fromPath = fromIdx >= 0 ? argv[fromIdx + 1] : null;

function fail(msg) { console.error('生成失败：' + msg); process.exit(1); }

// ===== 读上游 =====
// 默认只读本仓库自带的快照（上游一律靠 --from 显式给出）
function readSeed() {
  if (fromPath) {
    if (!fs.existsSync(fromPath)) fail('--from 指定的文件不存在：' + fromPath);
    return parseLuaTable(fs.readFileSync(fromPath, 'utf8'), fromPath);
  }
  if (!fs.existsSync(SEED)) {
    fail('找不到本仓库快照 ' + SEED + '（要换来源请用 `--from <路径> --vendor` 先导出一次）');
  }
  return parseSeed(fs.readFileSync(SEED, 'utf8'));
}

function parseSeed(txt) {
  const rows = [];
  for (const raw of txt.split(/\r?\n/)) {
    const line = raw.trim();
    if (line === '' || line[0] === '#') continue;
    const m = line.match(/^(\d+)\s*,\s*(\d+)\s*,\s*(\d+)$/);
    if (!m) fail('快照里有一行形态不认（应为 `id,sell,buy`）：' + raw.slice(0, 80));
    rows.push([Number(m[1]), Number(m[2]), Number(m[3])]);
  }
  if (rows.length === 0) fail('快照里一条都没解析到');
  return rows;
}

function parseLuaTable(txt, where) {
  const rows = [];
  const re = /\[(\d+)\]\s*=\s*"(\d+),(\d+)"/g;
  let m;
  while ((m = re.exec(txt)) !== null) rows.push([Number(m[1]), Number(m[2]), Number(m[3])]);
  if (rows.length === 0) fail('一条都没解析到（' + where + ' 的形态变了？）');
  const allAssign = (txt.match(/\[\d+\]\s*=/g) || []).length;
  if (allAssign !== rows.length) fail(`${where} 里有 ${allAssign} 条 [id]=，只解析出 ${rows.length} 条（形态不齐，先人工看一眼）`);
  return rows;
}

// ===== 规范化（去重 + 定序；同 id 两个不同价 ⇒ 直接报错，不悄悄取一个）=====
function normalize(rows) {
  const map = new Map();
  for (const r of rows) {
    const prev = map.get(r[0]);
    if (prev && (prev[1] !== r[1] || prev[2] !== r[2])) {
      fail(`id ${r[0]} 出现两次且价格不同（${prev[1]},${prev[2]} vs ${r[1]},${r[2]}）`);
    }
    map.set(r[0], r);
  }
  return [...map.values()].sort((a, b) => a[0] - b[0]);
}

// ===== --vendor：把上游导出成本仓库快照 =====
if (wantVendor) {
  if (!fromPath) fail('--vendor 必须配 --from <路径>（本脚本不内置任何第三方路径）');
  if (!fs.existsSync(fromPath)) fail('--vendor 找不到上游：' + fromPath);
  const src = fromPath;
  const list = normalize(parseLuaTable(fs.readFileSync(src, 'utf8'), src));
  const out = [];
  out.push('# items-vanilla-prices.txt —— Vanilla 1.12 物品**基准收购价**快照（一行一条：id,sell,buy，单位铜）');
  out.push('# 用途：gen_itemprices.js 的输入（生成的 ItemPriceData.lua 才是插件读的东西）。本文件不在 .toc 里，不加载。');
  out.push('# 出处与许可（MIT 来源）以及「这是快照、不是本服实测价」的准确性边界：见 doc/物品价数据-出处与许可.md。');
  out.push('# sell=0 表示不可卖、buy=0 表示没有商人卖；两者在运行期都按「无价」处理，绝不当作免费。');
  out.push('# 条数：' + list.length + '（id ' + list[0][0] + ' ~ ' + list[list.length - 1][0] + '）');
  for (const r of list) out.push(r[0] + ',' + r[1] + ',' + r[2]);
  fs.writeFileSync(SEED, out.join('\n') + '\n', 'utf8');
  console.log('已写出快照：', path.relative(__dirname, SEED), (fs.statSync(SEED).size / 1024).toFixed(1) + ' KB', '(' + list.length + ' 条)');
}

// ===== 生成 ItemPriceData.lua =====
const list = normalize(readSeed());
const sellPos = list.filter(r => r[1] > 0).length;
const buyPos = list.filter(r => r[2] > 0).length;
const sig = list.reduce((a, r) => (a + r[0] * 7 + r[1] * 3 + r[2]) % 2147483647, 0);
const stamp = new Date().toISOString().slice(0, 10);

const L = [];
L.push('-- ★★★本文件是**生成物**，绝不手改（改生成器 gen_itemprices.js 后重跑：node gen_itemprices.js）');
L.push('-- 全量**基准收购价**表（兜底用）：客户端没有任何「由物品 id 拿售价」的 API（`GetItemInfo` 停在 texture），');
L.push('--   所以插件只能「在商人处学价」—— 没去过的物品就一个价都没有。这张表用来兜住那种情况：');
L.push('--   `p[id] = "sell,buy"`（铜），★**学到真价后一律以真价为准**（本表只是兜底，绝不写回存档）。');
L.push('-- 数据：Vanilla 1.12 物品数据快照（本仓库自带 doc/items-vanilla-prices.txt）。');
L.push('--   ★出处、许可（MIT 来源）与准确性边界全部记在 doc/物品价数据-出处与许可.md —— 用之前先读它。');
L.push('-- ★★诚实边界（用之前先读这三条）：');
L.push('--   ① 这是 **快照数据、不是 Emberveil 实测数据**：本服**新增**物品这里没有行（按「无价」处理）；');
L.push('--      本服**改过价**的物品会先显示快照价，直到你在商人处学到真价（学到即永久覆盖）。');
L.push('--   ② `sell=0` = 不可卖、`buy=0` = 没有商人卖 —— 两者都当**无价**，绝不当作免费。');
L.push('--   ③ 本文件**在 .toc 里**（由 tools/ItemPrice.lua 使用；只被按需读单条，不预建索引表）。');
L.push('EVAL_IP_BASE = {');
L.push('  meta = {');
L.push('    src = "vanilla-1.12",');
L.push('    seed = "doc/items-vanilla-prices.txt",');
L.push('    doc = "doc/物品价数据-出处与许可.md",');
L.push(`    built = "${stamp}", n = ${list.length}, sellPos = ${sellPos}, buyPos = ${buyPos},`);
L.push(`    idMin = ${list[0][0]}, idMax = ${list[list.length - 1][0]}, sig = ${sig},`);
L.push('  },');
L.push('  p = {');
const per = 6;
for (let i = 0; i < list.length; i += per) {
  const chunk = list.slice(i, i + per).map(r => `[${r[0]}]=${JSON.stringify(r[1] + ',' + r[2])}`).join(',');
  L.push('   ' + chunk + ',');
}
L.push('  },');
L.push('}');
L.push('');

const out = L.join('\n');
fs.writeFileSync(DST, out, 'utf8');

console.log('=== gen_itemprices.js ===');
console.log('读出               :', list.length, '条（去重后）· sell>0 ' + sellPos + ' · buy>0 ' + buyPos);
console.log('写出               :', path.relative(__dirname, DST), (Buffer.byteLength(out) / 1024).toFixed(1) + ' KB');
console.log('  id 范围          :', list[0][0], '~', list[list.length - 1][0]);
console.log('  sig              :', sig, '（模块/闸门可用来核对表没被改过；换来源但内容不变时它应当不变）');
