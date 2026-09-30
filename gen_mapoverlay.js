// gen_mapoverlay.js —— 把 S_WorldMap（MozzFullWorldMap 血统）的探索层区域表转成我们的数据文件
//
//   源：TurtleWoW 的 `!Libs\!MyLib\libs\LibMapOverlayData.lua`（库名 LibMapOverlayData）
//       形态：MapOverlayData["<地图文件名>"] = { "区域名:宽:高:offsetX:offsetY", ... }
//   产物：`MapOverlayData.lua`（全局 `EVAL_MAP_OVERLAY_DATA`），形态更紧凑：
//        EVAL_MAP_OVERLAY_DATA["<地图文件名>"]["区域名"] = { 宽, 高, offsetX, offsetY }
//   ★单位：地图像素；原点 = `WorldMapDetailFrame` 左上、y 向下（与 `GetMapOverlayInfo` 同口径）。
//   ★这是**生成物**：以后要更新只改源文件 + 重跑本脚本，绝不手改产物。
//
//   用法：node gen_mapoverlay.js [源文件路径]
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2] || 'D:/game/TurtleWoW/Interface/AddOns/!Libs/!MyLib/libs/LibMapOverlayData.lua';
const OUT = path.join(__dirname, 'MapOverlayData.lua');

if (!fs.existsSync(SRC)) {
  console.log('MISSING 源文件：' + SRC);
  console.log('（TurtleWoW 侧路径可按需改：node gen_mapoverlay.js <路径>）');
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
out.push('--   源：TurtleWoW `!Libs\\!MyLib\\libs\\LibMapOverlayData.lua`（库 LibMapOverlayData = MozzFullWorldMap 血统）');
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

fs.writeFileSync(OUT, out.join('\n'), 'utf8');
console.log('OK 地图 ' + mapKeys.length + ' 张 / 区域 ' + nArea + ' 条 / 异常 ' + nBad + ' 条');
console.log('写出：' + OUT + '（' + fs.statSync(OUT).size + ' bytes）');
console.log('地图键：' + mapKeys.join(' '));
