// ★生成器：「打开世界迷雾」的自带贴图媒体包（`media/WorldMap/**`）
//
// 用途：把 1.12 客户端的探索层美术（`Interface\WorldMap\<地图>\<区域><块号>`）从客户端的 MPQ 归档里
//       解出来，逐字节写进插件自带的 `media/WorldMap/`，让插件在**不依赖客户端美术**的情况下也能整张画出地图。
//
// ★★★本生成器**不内置任何第三方路径**（与 `gen_mapoverlay.js` / `gen_itemprices.js` 同一口径）：
//    想换来源必须显式 `--from <MPQ 路径>`。默认**什么都不做**并把用法打出来。
//
// 用法：
//   node gen_worldmap_media.js --from "D:\game\TurtleWoW\Data\interface.MPQ" --full-only
//   node gen_worldmap_media.js --from "<路径>/interface.MPQ" --maps Barrens,Durotar
//   node gen_worldmap_media.js --from "<路径>/interface.MPQ" --all
//   加 --dry 只报不写。
//
// ★只放「整张齐全」的图（--full-only）：一张图缺任何一块就不放它 —— 否则运行期判定成「用自带」时，
//   缺的那块会画不出来（破洞）。判据 = `tmp/wm_coverage.js` 的逐图覆盖率。
//
// 读 MPQ 的口径（StormLib/MPQ 公开格式）：Header → 解密 hash 表 / block 表（key = HashString("(hash table)"/"(block table)", 3)）
//   → 按 zlib 扇区解压（扇区大小 = 512 << wSectorSizeShift）→ 写文件。解出来就是标准 BLP2，**不转格式**。
const fs = require("fs"), path = require("path"), zlib = require("zlib");

const argv = process.argv.slice(2);
const DRY = argv.includes("--dry");
const ALL = argv.includes("--all");
const FULLONLY = argv.includes("--full-only");
const fi = argv.indexOf("--from");
const MPQ = fi >= 0 ? argv[fi + 1] : null;
const mi = argv.indexOf("--maps");
const only = mi >= 0 ? new Set((argv[mi + 1] || "").split(",").map(s => s.trim()).filter(Boolean)) : null;
const OUTROOT = path.join(__dirname, "media", "WorldMap");

if (!MPQ) {
  console.log("用法：node gen_worldmap_media.js --from <interface.MPQ 路径> [--full-only | --maps A,B | --all] [--dry]");
  console.log("说明：本生成器不内置任何第三方路径 —— 来源必须由 --from 显式给出（默认不动任何文件）。");
  process.exit(0);
}
if (!fs.existsSync(MPQ)) { console.log("找不到 MPQ：" + MPQ); process.exit(1); }
if (!ALL && !FULLONLY && !only) { console.log("要指定 --full-only（推荐）或 --maps <图1,图2> 或 --all"); process.exit(1); }

const buf = fs.readFileSync(MPQ);
const u32 = o => buf.readUInt32LE(o), u16 = o => buf.readUInt16LE(o);
const cryptTable = (() => {
  const t = new Uint32Array(0x500); let seed = 0x00100001;
  for (let i = 0; i < 0x100; i++) { let idx = i; for (let k = 0; k < 5; k++, idx += 0x100) {
    seed = (seed * 125 + 3) % 0x2AAAAB; const a = (seed & 0xFFFF) << 16;
    seed = (seed * 125 + 3) % 0x2AAAAB; const b = seed & 0xFFFF; t[idx] = (a | b) >>> 0; } }
  return t;
})();
function hashString(name, ht) {
  const s = name.toUpperCase().replace(/\//g, "\\");
  let s1 = 0x7FED7FED >>> 0, s2 = 0xEEEEEEEE >>> 0;
  for (let i = 0; i < s.length; i++) { const c = s.charCodeAt(i);
    s1 = (cryptTable[(ht << 8) + c] ^ ((s1 + s2) >>> 0)) >>> 0;
    s2 = ((c + s1 + s2 + (s2 << 5) + 3) >>> 0); }
  return s1 >>> 0;
}
function decrypt(a, key) {
  let seed = 0xEEEEEEEE >>> 0;
  for (let i = 0; i < a.length; i++) {
    seed = (seed + cryptTable[0x400 + (key & 0xFF)]) >>> 0;
    let ch = a[i]; ch = (ch ^ ((key + seed) >>> 0)) >>> 0; a[i] = ch;
    key = ((((~key) << 0x15) + 0x11111111) | (key >>> 0x0B)) >>> 0;
    seed = ((ch + seed + (seed << 5) + 3)) >>> 0;
  }
}
if (buf.toString("latin1", 0, 4) !== "MPQ\x1A") { console.log("不是 MPQ 头（只支持明文头的 v0/v1 归档）"); process.exit(1); }
const hp = u32(16), bp = u32(20), hashN = u32(24), blockN = u32(28), SECT = 512 << u16(14);
const hashT = new Uint32Array(hashN * 4); for (let i = 0; i < hashT.length; i++) hashT[i] = u32(hp + i * 4);
decrypt(hashT, hashString("(hash table)", 3));
const blkT = new Uint32Array(blockN * 4); for (let i = 0; i < blkT.length; i++) blkT[i] = u32(bp + i * 4);
decrypt(blkT, hashString("(block table)", 3));

function find(name) {
  const start = hashString(name, 0) & (hashN - 1), hA = hashString(name, 1), hB = hashString(name, 2);
  for (let i = 0; i < hashN; i++) {
    const idx = (start + i) & (hashN - 1), o = idx * 4;
    if (hashT[o + 3] === 0xFFFFFFFF) return null;
    if (hashT[o] === hA && hashT[o + 1] === hB) { const b = hashT[o + 3] * 4;
      return { filePos: blkT[b], compSize: blkT[b + 1], fileSize: blkT[b + 2], flags: blkT[b + 3] }; }
  }
  return null;
}
function extract(e) {
  if (!(e.flags & 0x200)) return buf.slice(e.filePos, e.filePos + e.fileSize);   // 未压缩
  const n = Math.ceil(e.fileSize / SECT), out = [];
  for (let i = 0; i < n; i++) {
    const s = buf.readUInt32LE(e.filePos + i * 4), t = buf.readUInt32LE(e.filePos + (i + 1) * 4);
    let b = buf.slice(e.filePos + s, e.filePos + t);
    const mask = b[0]; b = b.slice(1);
    if (mask & 0x02) b = zlib.inflateSync(b);
    else if (mask !== 0) throw new Error("不支持的压缩掩码 0x" + mask.toString(16));
    out.push(b);
  }
  return Buffer.concat(out);
}

// 区域表 = `MapOverlayData.lua`（生成物；本生成器只读它，不自己维护第二份）
const lines = fs.readFileSync(path.join(__dirname, "MapOverlayData.lua"), "utf8").split(/\r?\n/);
const data = {}; let cur = null;
const areaRe = /\["([^"]+)"\]\s*=\s*\{\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\}/g;
for (const ln of lines) {
  const m = ln.match(/^\t\["([^"]+)"\]\s*=\s*\{/);
  if (m) { cur = m[1]; data[cur] = {}; continue; }
  if (!cur) continue;
  areaRe.lastIndex = 0; let a;
  while ((a = areaRe.exec(ln))) data[cur][a[1]] = [+a[2], +a[3], +a[4], +a[5]];
}

// 「整张齐全」预检
const coverage = {};
for (const [mapName, areas] of Object.entries(data)) {
  let tot = 0, hit = 0;
  for (const [areaName, r] of Object.entries(areas)) {
    const n = Math.ceil(r[0] / 256) * Math.ceil(r[1] / 256);
    for (let t = 1; t <= n; t++) { tot++; if (find(`Interface\\WorldMap\\${mapName}\\${areaName}${t}.blp`)) hit++; }
  }
  coverage[mapName] = { tot, hit, full: hit === tot };
}
if (FULLONLY) {
  const full = Object.entries(coverage).filter(([, c]) => c.full);
  console.log(`整张齐全的图：${full.length} 张 / ${full.reduce((s, [, c]) => s + c.tot, 0)} 块（不齐的 ${Object.keys(coverage).length - full.length} 张不放）`);
}

let wrote = 0, same = 0, bytes = 0, miss = 0;
const manifest = [];
for (const [mapName, areas] of Object.entries(data)) {
  if (only && !only.has(mapName)) continue;
  if (FULLONLY && !coverage[mapName].full) continue;
  for (const [areaName, r] of Object.entries(areas)) {
    const n = Math.ceil(r[0] / 256) * Math.ceil(r[1] / 256);
    for (let t = 1; t <= n; t++) {
      const e = find(`Interface\\WorldMap\\${mapName}\\${areaName}${t}.blp`);
      if (!e) { miss++; continue; }
      let body; try { body = extract(e); } catch (x) { miss++; continue; }
      manifest.push({ map: mapName, area: areaName, tile: t, bytes: body.length });
      bytes += body.length;
      const dir = path.join(OUTROOT, mapName), dst = path.join(dir, `${areaName}${t}.blp`);
      let old = null; try { old = fs.readFileSync(dst); } catch (x) {}
      if (old && old.length === body.length && old.equals(body)) { same++; continue; }
      if (DRY) continue;
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(dst, body);
      wrote++;
    }
  }
}
console.log(`命中并写出 ${wrote} 个 ｜ 内容相同跳过 ${same} 个 ｜ 解压后合计 ${(bytes / 1048576).toFixed(2)} MB ｜ 未命中 ${miss} 个`);
console.log("产物目录：" + OUTROOT);
console.log("★提示：贴图是客户端资源（BLP2，256×256 分块），随插件分发前请自行确认许可 —— 见 doc/地图层数据-出处与许可.md");
