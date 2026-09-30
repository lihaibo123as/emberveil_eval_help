// gen_mapoverlay.js —— 把 S_WorldMap（MozzFullWorldMap 血统）的探索层区域表转成我们的数据文件
//
//   ★★数据流水线（**上游不是另一个插件的目录**，与 `gen_itemprices.js` 同一范式）：
//     ① 快照（本仓库自带）：`doc/地图层数据-源快照.txt` —— 上游 `LibMapOverlayData` 的原样副本
//        （形态：MapOverlayData["<地图文件名>"] = { "区域名:宽:高:offsetX:offsetY", ... }）。
//        **默认只读它**；它不在 `.toc` 里 ⇒ 游戏不加载、不占脚本内存。
//     ② 生成物：`MapOverlayData.lua`（全局 `EVAL_MAP_OVERLAY_DATA`），形态更紧凑：
//        EVAL_MAP_OVERLAY_DATA["<地图文件名>"]["区域名"] = { 宽, 高, offsetX, offsetY }
//   ★单位：地图像素；原点 = `WorldMapDetailFrame` 左上、y 向下（与 `GetMapOverlayInfo` 同口径）。
//   ★这是**生成物**：以后要更新只改源（或换来源重导快照）+ 重跑本脚本，绝不手改产物。
//
//   用法：
//     node gen_mapoverlay.js                          读 doc/地图层数据-源快照.txt → 写 MapOverlayData.lua（幂等）
//     node gen_mapoverlay.js --from <路径> --vendor   换来源时把指定上游重新导出成本仓库快照（一次性）
//   ★本脚本**不内置任何第三方路径**：默认只认本仓库自带的快照；要换来源就显式 `--from` 指定，
//     导出完那一步就结束了 —— 之后生成只读快照，上游删掉也不影响（出处/许可见 `doc/地图层数据-出处与许可.md`）。
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, 'MapOverlayData.lua');
const SNAP = path.join(__dirname, 'doc', '地图层数据-源快照.txt');

// 命令行：`--from <路径>` = 用指定上游（换来源）；`--vendor` = 把它**写回快照**（一次性导出）。
const argv = process.argv.slice(2);
const iFrom = argv.indexOf('--from');
const fromPath = (iFrom >= 0) ? argv[iFrom + 1] : null;
const doVendor = argv.indexOf('--vendor') >= 0;
if (iFrom >= 0 && !fromPath) { console.log('--from 后面要跟路径'); process.exit(1); }
const SRC = fromPath || SNAP;

if (!fs.existsSync(SRC)) {
  console.log('MISSING 源文件：' + SRC);
  console.log('（换来源：node gen_mapoverlay.js --from <上游路径> --vendor 一次性导出快照，之后照旧直接跑）');
  process.exit(1);
}
const raw = fs.readFileSync(SRC, 'utf8').replace(/^\uFEFF/, '');
const lines = raw.split(/\r?\n/);

const maps = {};          // 地图文件名 → { 区域名 → [w,h,ox,oy] }
let curMap = null, nArea = 0, nBad = 0;
const reMap = /^\s*\["([^"]+)"\]\s*=\s*\{(.*)\},\s*$/;
const reEntry = /"([^"]+)"/g;

for (const ln of lines) {
  const m = ln.match(reMap);
  if (m) {
    curMap = m[1];
    maps[curMap] = {};
    const body = m[2];
    let em;
    reEntry.lastIndex = 0;
    while ((em = reEntry.exec(body)) !== null) {
      const f = em[1].split(':');
      if (f.length < 5) { nBad++; continue; }
      const area = f[0];
      const w = Number(f[1]), h = Number(f[2]), ox = Number(f[3]), oy = Number(f[4]);
      if (!area || !isFinite(w) || !isFinite(h) || !isFinite(ox) || !isFinite(oy)) { nBad++; continue; }
      if (maps[curMap][area]) nBad++;   // 同图同名区域 = 源数据有重（如实计数，不静默覆盖）
      maps[curMap][area] = [w, h, ox, oy];
      nArea++;
    }
  }
}

const mapKeys = Object.keys(maps);
if (!mapKeys.length) { console.log('源文件里没解析出任何地图（格式变了？）'); process.exit(1); }

const num = v => (Number.isInteger(v) ? String(v) : String(v));
const out = [];
out.push('-- ★★★生成物（**勿手改**）—— 生成器：`node gen_mapoverlay.js`');
out.push('--   源：本仓库快照 `doc/地图层数据-源快照.txt`（上游 LibMapOverlayData = MozzFullWorldMap 血统的区域表）');
out.push('--   形态：`EVAL_MAP_OVERLAY_DATA[地图文件名][区域名] = { 宽, 高, offsetX, offsetY }`');
out.push('--   ★单位 = **地图像素**；原点 = `WorldMapDetailFrame` 左上、**y 向下**（与 `GetMapOverlayInfo` 同口径）。');
out.push('--   ★贴图路径按 Mozz 规则拼：`Interface\\WorldMap\\<地图文件名>\\<区域名><分块号>`，');
out.push('--     每 256×256 一块、序号从 1 起；消费方 = `tools/SimpleMap.lua` 的 MDQ 渲染族');
out.push('--     （工具箱 → 缩放大地图 → [设置] →「打开世界迷雾」开关）。');
out.push('--   统计：地图 ' + mapKeys.length + ' 张 ｜ 区域 ' + nArea + ' 条' + (nBad ? (' ｜ 异常/重复 ' + nBad + ' 条') : ''));
out.push('EVAL_MAP_OVERLAY_DATA = {');
for (const mk of mapKeys) {
  out.push('\t["' + mk + '"] = {');
  const areas = Object.keys(maps[mk]).sort();
  // ★每条后面都带逗号：同一行里放多条时，缺逗号 = 语法错（第一版就踩了，luacheck 当场抓到）
  const cells = areas.map(a => '["' + a + '"]={' + maps[mk][a].map(num).join(',') + '},');
  // 每行 4 条，便于 diff
  for (let i = 0; i < cells.length; i += 4) out.push('\t\t' + cells.slice(i, i + 4).join(' '));
  out.push('\t},');
}
out.push('}');
out.push('-- ★元信息（取证用：核对时写入日志，一眼知道比对的是哪一版数据）');
out.push('EVAL_MAP_OVERLAY_META = { maps = ' + mapKeys.length + ', areas = ' + nArea
  + ', src = "LibMapOverlayData", gen = "gen_mapoverlay.js" }');
out.push('');

if (doVendor && fromPath) {
  // ★一次性导出：把上游**原样**写回快照（不加工，保真第一；加工只在上面那段解析里做）
  const header = [
    '-- ★★★**数据快照（只读，勿改）** —— 上游 `LibMapOverlayData`（MozzFullWorldMap 血统的区域表）的**原样副本**。',
    '--   取自：TurtleWoW 发行版内 `Interface\\AddOns\\!Libs\\!MyLib\\libs\\LibMapOverlayData.lua`。',
    '--   用途：`gen_mapoverlay.js` 的**唯一默认来源** ⇒ 生成 `MapOverlayData.lua` 不再依赖任何其它插件的目录',
    '--        （本项目定案：物品价那次同样口径 ——「**不需要和其他插件做关联性**」）。',
    '--   ★本文件**不在 `EvalHelp.toc` 里** ⇒ 游戏不加载、不占内存；扩展名 `.txt` ⇒ 任何工具都不会当代码解析。',
    '--   ★出处/许可见 `doc/地图层数据-出处与许可.md`（上游文件本身未声明许可 ⇒ 以对方声明为准）。',
    '',
  ].join('\n');
  fs.writeFileSync(SNAP, header + raw, 'utf8');
  console.log('快照已更新：' + SNAP + '（' + (fs.statSync(SNAP).size / 1024).toFixed(1) + 'KB，原样副本）');
}

fs.writeFileSync(OUT, out.join('\n'), 'utf8');
console.log('OK 地图 ' + mapKeys.length + ' 张 / 区域 ' + nArea + ' 条 / 异常 ' + nBad + ' 条');
console.log('写出：' + OUT + '（' + fs.statSync(OUT).size + ' bytes）');
console.log('地图键：' + mapKeys.join(' '));
