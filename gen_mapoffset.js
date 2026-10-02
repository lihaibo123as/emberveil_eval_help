// gen_mapoffset.js —— 从存档导出「世界迷雾 · 独立偏移量数据库」`MapOverlayOffset.lua`
// ============================================================================
// 用途（用户定案）：「我微调的数据储存为独立偏移量数据库.然后整合到作为插件的基础数据.
//   插件是给其他人使用的他们就能看到正确的矫正过的贴图了」
// 数据源：最新一份 `SavedVariables\EvalHelp.lua` 的 `worldFogCfg.edit`
//   （编辑模式拖出来的逐块补偿；★账号不固定 ⇒ 一律取「所有账号目录里 mtime 最新那份」）。
// 产物：`MapOverlayOffset.lua`（**生成物，勿手改**）—— 与 `MapOverlayData.lua` **配对使用**：
//   最终坐标 = MapOverlayData.lua 表值 + 本文件偏移量（存档里同键的后续微调优先）。
// ★★★**数据库语义 = 合并累积**（不是全量镜像！）：
//   · 存档里的**非零**记录 ⇒ **写入 / 更新**到文件（存档优先）；
//   · 存档里的**显式 {0,0} 影**（拖回原点压文件）⇒ 从文件里**删除**那一键（= 用户明确「这块回原始表值」）；
//   · 存档里**没有**的键 ⇒ **保留**旧文件记录 —— 烘完就清存档是正常动作，绝不清掉已烘的数据；
//   · `--prune` = 全量镜像重建（丢弃旧文件里「存档已没有」的一切 —— 显式大扫除才用）。
// 用法：
//   node gen_mapoffset.js              合并累积导出（默认）
//   node gen_mapoffset.js --from <存档路径>   指定存档
//   node gen_mapoffset.js --account <账号>    指定账号目录（大小写不敏感；★1.75.60e：用户约定
//     「同步世界迷雾」= 把**指定角色/账号**的偏移量烘成插件偏移量 ⇒ 点名时用这条，别靠「最新」猜）
//   node gen_mapoffset.js --check      只校验（配对/孤儿/漂移），不写文件
//   node gen_mapoffset.js --prune      全量镜像重建（丢弃旧文件里存档已没有的键）
//   node gen_mapoffset.js --maps A,B   **只同步这几张图，且这几张图是「整图替换」**（用户定：
//     「偏移配置更新的时候某个区域是替代.别合并.直接指定区域数据覆盖」——存档 = 这几张图的**全量真值**：
//     这张图里不在存档里的旧库记录**删掉**；没点名的其它图旧库记录原样保留）。
//     如「同步世界迷雾 lihaiboas2 洛克莫丹的」⇒ --account lihaiboas2 --maps LochModan）
// ★生成器不许内置第三方路径（与 gen_mapoverlay.js 同一口径）：只读「本机存档」与「本仓库的 MapOverlayData.lua」。
// ============================================================================
const fs = require("fs"), path = require("path");
const ROOT = __dirname;
const OUT = path.join(ROOT, "MapOverlayOffset.lua");
const BASE = path.join(ROOT, "MapOverlayData.lua");
const ACCOUNTS_DIR = path.join(process.env.LOCALAPPDATA, "Azeroth", "Saved", "Account");

// ── 找存档（所有账号里 mtime 最新、且含 worldFogCfg 的那份；--account 可点名账号目录）──
function walk(d, out) {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else if (e.name === "EvalHelp.lua") out.push(p);
  }
  return out;
}
const argFrom = (() => { const i = process.argv.indexOf("--from"); return i > 0 ? process.argv[i + 1] : null; })();
const argAccount = (() => { const i = process.argv.indexOf("--account"); return i > 0 ? process.argv[i + 1] : null; })();
const argMaps = (() => { const i = process.argv.indexOf("--maps"); return i > 0 ? process.argv[i + 1] : null; })();
const CHECKONLY = process.argv.includes("--check");
const PRUNE = process.argv.includes("--prune");
let savePath = argFrom, saveText = null, saveMtime = null;
if (argAccount && !savePath) {
  // 指定账号：账号目录名大小写不敏感匹配（LIHAIBOAS1 / LIHAIBOAS2 / lihaiboas3 这类）
  const want = argAccount.toLowerCase();
  const dir = fs.existsSync(ACCOUNTS_DIR)
    ? fs.readdirSync(ACCOUNTS_DIR, { withFileTypes: true })
        .filter(e => e.isDirectory() && e.name.toLowerCase() === want)
        .map(e => path.join(ACCOUNTS_DIR, e.name, "SavedVariables", "EvalHelp.lua"))
        .find(p => fs.existsSync(p))
    : null;
  if (!dir) {
    console.error("账号目录里没有「" + argAccount + "」（现有：" +
      (fs.existsSync(ACCOUNTS_DIR) ? fs.readdirSync(ACCOUNTS_DIR).join(" / ") : "（目录不存在）") + "）");
    process.exit(1);
  }
  savePath = dir;
}
if (savePath) {
  saveText = fs.readFileSync(savePath, "utf8").replace(/^﻿/, "");
  saveMtime = fs.statSync(savePath).mtime;
} else {
  const cands = walk(ACCOUNTS_DIR, [])
    .map(p => ({ p, st: fs.statSync(p) })).sort((a, b) => b.st.mtime - a.st.mtime);
  for (const c of cands) {
    const s = fs.readFileSync(c.p, "utf8").replace(/^﻿/, "");
    if (s.indexOf('"worldFogCfg"') < 0) continue;
    savePath = c.p; saveText = s; saveMtime = c.st.mtime; break;
  }
}
if (!saveText) { console.error("找不到含 worldFogCfg 的存档（--from 可指定）"); process.exit(1); }

// ── 小工具：取 `key` 那一层 {...} 表体（括号配平）──
function bodyOf(s, key, from) {
  const i = s.indexOf(key, from || 0);
  if (i < 0) return null;
  let a = s.indexOf("{", i), d = 0, b = a;
  for (; b < s.length; b++) { const ch = s[b]; if (ch === "{") d++; else if (ch === "}") { d--; if (d === 0) { b++; break; } } }
  return s.slice(a, b);
}

// ── 解析 worldFogCfg.edit（★深度感知：第 1 层 = 地图，第 2 层 = 区域#块号）──
function parseEdit(editBody) {
  const out = {};
  const re = /\[\s*"((?:[^"\\]|\\.)*)"\s*\]\s*=\s*\{/g;
  let pos = 0, d = 0, curMap = null;
  for (const m of editBody.matchAll(re)) {
    for (let k = pos; k < m.index; k++) {
      const ch = editBody[k];
      if (ch === "{") d++; else if (ch === "}") d--;
    }
    if (d === 1) { curMap = m[1].replace(/\\"/g, '"'); out[curMap] = {}; }
    else if (d === 2 && curMap) {
      let a = m.index + m[0].length - 1, dd = 0, b = a;
      for (; b < editBody.length; b++) { const ch = editBody[b]; if (ch === "{") dd++; else if (ch === "}") { dd--; if (dd === 0) { b++; break; } } }
      const f = {};
      for (const kv of editBody.slice(a, b).matchAll(/\[\s*"(\w+)"\s*\]\s*=\s*("(?:[^"\\]|\\.)*"|-?[\d.]+|true|false)/g)) {
        f[kv[1]] = kv[2].replace(/^"|"$/g, "");
      }
      out[curMap][m[1]] = f;
    }
    pos = m.index;
  }
  return out;
}

// ── 解析 MapOverlayData.lua（同深度感知）：{ 地图: { 区域: [宽,高,offsetX,offsetY] } } ──
function parseBase(src) {
  const out = {};
  const re = /\["((?:[^"\\]|\\.)*)"\]\s*=\s*\{/g;
  let pos = 0, d = 0, curMap = null;
  for (const m of src.matchAll(re)) {
    for (let k = pos; k < m.index; k++) {
      const ch = src[k];
      if (ch === "{") d++; else if (ch === "}") d--;
    }
    if (d === 1) { curMap = m[1]; out[curMap] = {}; }
    else if (d === 2 && curMap) {
      let a = m.index + m[0].length - 1, dd = 0, b = a;
      for (; b < src.length; b++) { const ch = src[b]; if (ch === "{") dd++; else if (ch === "}") { dd--; if (dd === 0) { b++; break; } } }
      const nums = src.slice(a + 1, b - 1).split(",").map(v => Number(v.trim()));
      if (nums.length >= 4 && nums.every(v => !Number.isNaN(v))) out[curMap][m[1]] = nums;
    }
    pos = m.index;
  }
  return out;
}
function tilesOf(w, h) {
  if (!(w > 0) || !(h > 0)) return 0;
  return Math.ceil(w / 256) * Math.ceil(h / 256);   // 与 MDQ.tiles 同算法（每 256×256 一块）
}
// 第 t 块（1 基，行优先）的期望矩形 —— **与 tools/WorldFog.lua 的 MDQ.expectRect 逐行同算法**
function tileRect(b, t) {
  const w = b[0], h = b[1], ox = b[2], oy = b[3];
  const nh = Math.ceil(w / 256), nv = Math.ceil(h / 256);
  if (!(t >= 1) || t > nh * nv) return null;
  const j = Math.floor((t - 1) / nh) + 1, k = ((t - 1) % nh) + 1;
  let tw = (k < nh) ? 256 : (w % 256); if (tw === 0) tw = 256;
  let th = (j < nv) ? 256 : (h % 256); if (th === 0) th = 256;
  return { x: ox + 256 * (k - 1), y: oy + 256 * (j - 1), w: tw, h: th };
}

// ── 解析**上一次导出的** MapOverlayOffset.lua（合并累积的旧库；自己发的格式，自己吃得回来）──
function parseOldOffset(src) {
  const out = {};
  let curMap = null;
  for (const line of src.split("\n")) {
    let m = line.match(/^\t\["([^"]+)"\] = \{$/);
    if (m) { curMap = m[1]; out[curMap] = {}; continue; }
    m = line.match(/^\t\t\["([^"]+)"\] = \{ (.*) \},$/);
    if (m && curMap) {
      const recs = {};
      for (const cm of m[2].matchAll(/\[(\d+)\]=\{([^}]*)\}/g)) {
        const f = {};
        for (const kv of cm[2].matchAll(/(\w+)=(-?[\d.]+)/g)) f[kv[1]] = Number(kv[2]);
        recs[Number(cm[1])] = f;
      }
      out[curMap][m[1]] = recs;
    }
  }
  return out;
}

// ── 主流程 ──
const buildTag = (saveText.match(/buildTag"?\s*\]?\s*=\s*"([^"]+)"/) || [])[1] || "?";
const editBody = bodyOf(saveText, '"edit"');
if (!editBody) { console.error("存档里没有 worldFogCfg.edit（还没拖过 ⇒ 没什么可导出的）"); process.exit(1); }
const edit = parseEdit(editBody);
// ── --maps A,B：只同步这几张图（大小写不敏感）—— ★这几张图是**整图替换**（见 ②a：它们的旧库不铺底）──
let mapsWanted = null;   // Set<小写图名>，或 null = 不过滤（全量合并累积）
if (argMaps) {
  const want = argMaps.split(",").map(s => s.trim().toLowerCase()).filter(s => s.length > 0);
  const miss = want.filter(w => !Object.keys(edit).some(m => m.toLowerCase() === w));
  if (miss.length > 0) {
    console.error("--maps 里这几张图存档里没有：" + miss.join(", ") + "（存档里现有：" + Object.keys(edit).join(" / ") + "）");
    process.exit(1);
  }
  for (const m of Object.keys(edit)) {
    if (!want.includes(m.toLowerCase())) delete edit[m];
  }
  mapsWanted = new Set(want);
  console.log("（--maps 整图替换：" + Object.keys(edit).join(" / ")
    + " —— 这几张图的旧库记录以存档**全量覆盖**；其余图的旧库记录原样保留）");
}
const baseSrc = fs.readFileSync(BASE, "utf8");
const base = parseBase(baseSrc.slice(baseSrc.indexOf("EVAL_MAP_OVERLAY_DATA")));

const fmt = (v) => {
  const n = Number(v);
  if (Number.isNaN(n)) return "0";
  if (Number.isInteger(n)) return String(n);
  return n.toFixed(1);
};
const sameRec = (a, b) => ["x", "y", "dw", "dh", "bx", "by", "bw", "bh"].every(k => {
  if (a[k] === undefined && b[k] === undefined) return true;
  if (a[k] === undefined || b[k] === undefined) return false;
  // ★产物按 0.1 一位小数落盘 ⇒ 旧库读回的值带舍入，容差内算**同一条**（不然每次导出都全员假「更新」）
  return Math.abs(a[k] - b[k]) <= 0.06;
});

// ① 把存档整理成 { map: { area: { tile: rec } } }，收集 0 影键（= 删除指令），并做配对校验
//   ★1.75.60x：**地图名大小写不敏感**（客户端报的图名与上游基础表拼写不一定相同 —— 真机实测存档里是
//     `BadLands` / `Blastedlands` / `HinterLands`，基础表里是 `Badlands` / `BlastedLands` / `Hinterlands`；
//     只按精确键查会把这 3 张图的记录**误报成孤儿**，而运行期查基础表本来就是大小写不敏感的）
const baseKeyCI = {};
const baseOf = (m) => {
  if (base[m]) return base[m];
  const k = baseKeyCI[m] || (baseKeyCI[m] = Object.keys(base).find(x => x.toLowerCase() === String(m).toLowerCase()));
  return k ? base[k] : null;
};
const saveMaps = {}, zeroKeys = [];
let nSkipZero = 0, nOrphan = 0, nDrift = 0, nSave = 0;
const warns = [];
for (const map of Object.keys(edit)) {
  for (const key of Object.keys(edit[map])) {
    const r = edit[map][key];
    const x = Number(r.x), y = Number(r.y);
    if (Number.isNaN(x) || Number.isNaN(y)) continue;
    const ci = key.lastIndexOf("#");
    if (ci <= 0) { warns.push("键形态不认（按最后一个 # 切）：" + map + " 的 " + key); continue; }
    const area = key.slice(0, ci), tile = Number(key.slice(ci + 1));
    if (!Number.isInteger(tile) || tile < 1) { warns.push("块号不是正整数：" + map + " 的 " + key); continue; }
    // ★1.75.60o：**尺寸补偿**（dw/dh）也是补偿 —— 「0 影」的判据必须同时看尺寸：
    //   只有位置与尺寸**都**为 0 才是删除指令；「只调了宽高」的记录是**有效补偿**（旧写法会把它当 0 影删掉）。
    const dw = Number(r.dw), dh = Number(r.dh);
    const hasSize = (!Number.isNaN(dw) && dw !== 0) || (!Number.isNaN(dh) && dh !== 0);
    if (x === 0 && y === 0 && !hasSize) { nSkipZero++; zeroKeys.push({ map, area, tile }); continue; }
    const rec = { x, y };
    for (const f of ["dw", "dh", "bx", "by", "bw", "bh"]) { const v = Number(r[f]); if (!Number.isNaN(v)) rec[f] = v; }
    // 配对校验（**按块**比：record 里存的是「该块的表值」⇒ 与 expectRect 出来的块矩形比）
    const bm = baseOf(map);
    const b = bm && bm[area];
    if (!b) { nOrphan++; warns.push("**孤儿** " + map + " / " + key + "（基础表里没这个区域 ⇒ 运行时**不生效**）"); }
    else {
      const tr = tileRect(b, tile);
      if (tr == null) { nOrphan++; warns.push("**孤儿** " + map + " / " + key + "（该区域共 " + tilesOf(b[0], b[1]) + " 块 ⇒ 运行时**不生效**）"); }
      else {
        const drift = (rec.bx !== undefined && Math.abs(rec.bx - tr.x) > 0.5) || (rec.by !== undefined && Math.abs(rec.by - tr.y) > 0.5)
          || (rec.bw !== undefined && Math.abs(rec.bw - tr.w) > 0.5) || (rec.bh !== undefined && Math.abs(rec.bh - tr.h) > 0.5);
        if (drift) {
          nDrift++;
          warns.push("**基础表已变** " + map + " / " + key + "：调时 " + [rec.bx, rec.by, rec.bw, rec.bh].join(",")
            + " ⇒ 现在 " + [tr.x, tr.y, tr.w, tr.h].join(","));
        }
      }
    }
    ((saveMaps[map] = saveMaps[map] || {})[area] = saveMaps[map][area] || {})[tile] = rec;
    nSave++;
  }
}

// ② 合并累积（--prune = 跳过旧库，全量镜像）
const old = (!PRUNE && fs.existsSync(OUT)) ? parseOldOffset(fs.readFileSync(OUT, "utf8")) : {};
let nNew = 0, nUpd = 0, nDel = 0, nKeep = 0, nTot = 0, nDrop = 0;
let nOldRep = 0, nHitRep = 0;   // 被替换图的旧记录总数 / 其中被存档同名键顶回去的（⇒ 真丢弃 = 差）
const merged = {};
//   2a. 旧库铺底（保留）
//   ★★但 `--maps` 点名的图**不铺底** —— 用户定：「偏移配置更新的时候某个区域是**替代**.别合并.
//     直接指定区域数据覆盖」⇒ 这几张图 = **整图替换**：存档是这张图的全量真值，旧库里不在存档里的
//     记录**丢弃**（`nDrop` 如实播报）。没点名的图照旧铺底（合并累积）。
for (const map of Object.keys(old)) {
  if (mapsWanted && mapsWanted.has(map.toLowerCase())) {
    for (const area of Object.keys(old[map])) nOldRep += Object.keys(old[map][area]).length;
    continue;
  }
  for (const area of Object.keys(old[map])) {
    for (const tile of Object.keys(old[map][area])) {
      ((merged[map] = merged[map] || {})[area] = merged[map][area] || {})[tile] = old[map][area][tile];
    }
  }
}
//   2b. 存档非零 ⇒ 写/更新（被替换图：与**旧库**比对来判「新增/更新」；别的图：与 merged 比）
for (const map of Object.keys(saveMaps)) {
  const rep = mapsWanted && mapsWanted.has(map.toLowerCase());
  for (const area of Object.keys(saveMaps[map])) {
    for (const tile of Object.keys(saveMaps[map][area])) {
      const src = rep ? old : merged;
      const had = src[map] && src[map][area] && src[map][area][tile];
      if (had === undefined) nNew++;
      else {
        if (!sameRec(had, saveMaps[map][area][tile])) nUpd++;
        if (rep) nHitRep++;      // 旧记录被同名键顶回去 ⇒ 不算「丢弃」
      }
      ((merged[map] = merged[map] || {})[area] = merged[map][area] || {})[tile] = saveMaps[map][area][tile];
    }
  }
}
nDrop = nOldRep - nHitRep;   // ★整图替换真正丢弃的旧记录数
//   2c. 存档显式 0 影 ⇒ 从库里删除那一键
for (const z of zeroKeys) {
  if (merged[z.map] && merged[z.map][z.area] && merged[z.map][z.area][z.tile] !== undefined) {
    delete merged[z.map][z.area][z.tile];
    nDel++;
  }
}
//   2d. 统计（保留 = 旧库有、存档没碰的；空区域/空地图不发货）
for (const map of Object.keys(merged)) {
  for (const area of Object.keys(merged[map])) {
    if (Object.keys(merged[map][area]).length === 0) { delete merged[map][area]; continue; }
    nTot += Object.keys(merged[map][area]).length;
  }
  if (Object.keys(merged[map]).length === 0) delete merged[map];
}
nKeep = nTot - nNew - nUpd;   // 合计里除去「本次新写/更新」的 = 原样保留的

// ③ 发射 Lua（形态与 MapOverlayData.lua 同风格；tab 缩进；排序确定 ⇒ git diff 干净）
const mapNames = Object.keys(merged).sort((a, b) => a.localeCompare(b, "en"));
const L = [];
L.push("-- ★★★生成物（**勿手改**）—— 生成器：`node gen_mapoffset.js`");
L.push("--   数据源：存档 `worldFogCfg.edit`（编辑模式逐块微调；存档 = " + savePath);
L.push("--     ｜ 存档时间 = " + saveMtime.toLocaleString() + " ｜ buildTag = " + buildTag + "）");
L.push("--   ★**数据库语义**：全量导出 = **合并累积**（存档非零 = 写/更新 ｜ 存档显式 0 影 = 删除 ｜ 存档没有 = **保留**）");
L.push("--     ★「0 影」= **位置与尺寸都为 0** 的记录；只调了宽高（dw/dh 非 0）的记录是**有效补偿**，不是删除指令");
L.push("--     —— 烘完就清存档是正常动作，绝不清掉已烘的数据；全量镜像重建用 `node gen_mapoffset.js --prune`");
L.push("--   ★★**但 `--maps <图>` 点名的图 = 整图替换**（用户定：「偏移配置更新的时候某个区域是替代.别合并."
  + "直接指定区域数据覆盖」）：存档是这几张图的**全量真值**，旧库里不在存档里的记录**丢弃**；没点名的图照旧合并累积。");
L.push("--     本次点名的图：" + (mapsWanted ? Object.keys(merged).filter(m => mapsWanted.has(m.toLowerCase())).join(" / ")
  + "（整图替换，丢弃旧记录 " + nDrop + " 条）" : "（无 —— 全量合并累积）"));
L.push("--   形态：`EVAL_MAP_OVERLAY_OFFSET[地图文件名][区域名][块号] = { x=, y=, dw=, dh=, bx=, by=, bw=, bh= }`");
L.push("--     · x, y = **表口径偏移量**（地图像素；正 x 右 / 正 y 下，与 MapOverlayData.lua 的 offsetX/offsetY 同符号）");
L.push("--     · dw, dh = **尺寸补偿**（表口径增量；最终块尺寸 = 基础表块尺寸 + dw/dh ⇒ 基础表重生也不影响；缺省 = 0）");
L.push("--     · bx, by, bw, bh = 导出时该块在**基础表**里的值（配对基准 ⇒ 基础表重生时能判出「这条是按旧表调的」）");
L.push("--   ★与 `MapOverlayData.lua` **配对使用**（消费方 = `tools/WorldFog.lua`）：");
L.push("--       最终坐标 = MapOverlayData.lua 表值 + 本文件偏移量；");
L.push("--       存档 `worldFogCfg.edit` 里同键的后续微调**优先**于本文件（清存档 ⇒ 回落到本文件基线）；");
L.push("--       基础表里查不到 (区域,块号) 的条目**不生效**（孤儿补偿绝不硬加到别的块上）。");
L.push("--   统计：地图 " + mapNames.length + " 张 ｜ 偏移量 " + nTot + " 条"
  + "（本次：新增 " + nNew + " ｜ 更新 " + nUpd + " ｜ 删除 " + nDel + " ｜ 保留 " + nKeep
  + (nDrop > 0 ? " ｜ 整图替换丢弃 " + nDrop : "") + "）");
L.push("EVAL_MAP_OVERLAY_OFFSET = {");
for (const map of mapNames) {
  L.push('\t["' + map + '"] = {');
  for (const area of Object.keys(merged[map]).sort((a, b) => a.localeCompare(b, "en"))) {
    const recs = merged[map][area];
    const cells = Object.keys(recs).map(Number).sort((p, q) => p - q).map(t => {
      const r = recs[t];
      let c = "[" + t + "]={x=" + fmt(r.x) + ",y=" + fmt(r.y);
      if (r.dw !== undefined) c += ",dw=" + fmt(r.dw);
      if (r.dh !== undefined) c += ",dh=" + fmt(r.dh);
      if (r.bx !== undefined) c += ",bx=" + fmt(r.bx);
      if (r.by !== undefined) c += ",by=" + fmt(r.by);
      if (r.bw !== undefined) c += ",bw=" + fmt(r.bw);
      if (r.bh !== undefined) c += ",bh=" + fmt(r.bh);
      return c + "}";
    });
    L.push('\t\t["' + area + '"] = { ' + cells.join(", ") + " },");
  }
  L.push("\t},");
}
L.push("}");
L.push("");

if (CHECKONLY) {
  console.log("（--check：只校验，不写文件）");
} else {
  fs.writeFileSync(OUT, L.join("\n"), "utf8");
  console.log("已写出 " + OUT + "（" + (fs.statSync(OUT).size / 1024).toFixed(1) + " KB）");
}
console.log("数据源存档 = " + savePath);
console.log((PRUNE ? "（--prune 全量镜像）" : (mapsWanted ? "（整图替换：点名图覆盖、其余图合并累积）" : "（合并累积）"))
  + " 地图 " + mapNames.length + " 张 ｜ 库里 " + nTot + " 条"
  + " ｜ 本次：新增 " + nNew + " ｜ 更新 " + nUpd + " ｜ 删除 " + nDel + " ｜ 保留 " + nKeep
  + (nDrop > 0 ? " ｜ **整图替换丢弃 " + nDrop + " 条**" : "")
  + " ｜ 存档非零 " + nSave + " ｜ 显式归零 " + nSkipZero + " ｜ 孤儿 " + nOrphan + " ｜ 基础表已变 " + nDrift);
if (warns.length > 0) {
  console.log("--- 校验警告（照发但点名；孤儿运行时**不生效**）---");
  for (const w of warns) console.log("  " + w);
}
console.log("下一步：把 MapOverlayOffset.lua 留在仓库（toc 已挂）⇒ 别人装插件就直接看到矫正后的贴图。");
