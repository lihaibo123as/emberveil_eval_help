// scan_dangling.js —— 「调用了但本文件没定义、也不像客户端 API」的粗筛工具（人工复核用，不是闸门）
// 用途：跨分支/跨文件抄代码时，抄来了一堆**本文件不存在**的助手（本轮实例：SM / flushStore）
//   —— luacheck 不查未定义全局，ADDON DECL ORDER 只查「声明在引用之后」，都拦不住它。
// 用法：node scan_dangling.js
//
// ★★★1.75.42 新增**第二段：全仓判据**（血的教训）：1.75.34 的「孤儿清理」把 **5 个函数的定义删掉、调用点全留着**
//   —— `Share.lua` 的 `shNoPop`（8 处调用）真机直接红字 `attempt to call global 'shNoPop' (a nil value)`，
//   另外 4 个（`EVAL_WTT_HANDLE`/`EVAL_WTT_STATE`/`EVAL_DS_NODE_DIAG`/`EVAL_DS_QC_PROBE`）被 `type(...)=="function"`
//   守卫住 ⇒ **不崩但功能静默死掉**（工具柄拿不到 ⇒ 任务线装备永不检索）。
//   ★旧版本**只扫 `addons/` 子目录**（`listLua('addons', [])`）⇒ 主插件文件（Share/Engine/DataSearch/Toolbox/EvalHelp…）
//     一个都不看，所以这类雷它天生抓不到。现在补第二段：**在全仓范围内**找「被调用、但哪里都没有定义」的名字。
//   ★白名单：客户端 API 索引 `api_*.html`（本机有就读，取 JSON 里的 name 字段）+ 已知 Lua/WoW 全局。
const fs = require('fs');
const path = require('path');

const KEYWORDS = new Set(['and', 'or', 'not', 'if', 'then', 'else', 'elseif', 'end', 'for', 'while', 'repeat',
  'until', 'do', 'return', 'function', 'local', 'in', 'break', 'nil', 'true', 'false']);
const KNOWN_GLOBAL = new Set(['pcall', 'xpcall', 'type', 'tostring', 'tonumber', 'ipairs', 'pairs', 'next',
  'unpack', 'select', 'error', 'assert', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal',
  'print', 'format', 'strfind', 'strsub', 'gsub', 'getglobal', 'table', 'string', 'math', '_G', 'arg1', 'arg2',
  'this', 'event', 'CreateFrame', 'GetTime', 'SlashCmdList', 'EVAL_LOGLINE', 'EVAL_SAY',
  'concat', 'insert', 'remove', 'sort', 'getn', 'upper', 'lower', 'find', 'gsub', 'sub', 'format', 'rep', 'floor',
  // WoW/本客户端由 Lua 环境直接提供的全局（api_*.html 索引里不一定收）
  'time', 'date', 'difftime', 'mod', 'abs', 'min', 'max', 'random', 'sqrt', 'ceil', 'strtrim', 'strsplit',
  'strjoin', 'wipe', 'tinsert', 'tremove', 'foreach', 'foreachi', 'securecall', 'hooksecurefunc', 'bit',
  // 客户端 FrameXML 里定义的全局（api_*.html 没收录，但确实是客户端给的；Toolbox 用了它开聊天输入）
  'ChatEdit_ActivateChat', 'ChatEdit_OnEnterPressed', 'ChatEdit_OnEscapePressed', 'ChatFrame_OnEvent']);
// 常见「点在方法上」的调用名（来自 SetXxx 家族）——避免误报
const METHODISH = /^(Set|Get|Is|Has|Enable|Disable|Register|Unregister|Show|Hide|Clear|Add|Remove|Play|Stop|Start)/;

function listLua(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name === '.git' || e.name === 'tmp' || e.name === 'preview') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) listLua(p, out);
    else if (e.name.slice(-4) === '.lua') out.push(p);
  }
  return out;
}

// ===== 第一段（原有）：按**单文件**粗筛（只看 addons/ 子插件；跨文件全局会误报 ⇒ 范围故意收窄）=====
let flagged = 0;
for (const file of listLua('addons', [])) {
  const src = fs.readFileSync(file, 'utf8');
  const defined = new Set();
  for (const re of [/(?:^|\n)\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)/g,
                    /(?:^|\n)\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=/g,
                    /(?:^|\n)\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g,
                    /(?:^|\n)\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/gm]) {
    for (const m of src.matchAll(re)) defined.add(m[1]);
  }
  // 形参也要算「已定义」（闭包参数）
  for (const m of src.matchAll(/function[^()]*\(([^)]*)\)/g)) {
    for (const p of m[1].split(',')) { const n = p.trim(); if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(n)) defined.add(n); }
  }
  const called = new Map();
  for (const m of src.matchAll(/(?<![.:A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
    const n = m[1];
    if (!called.has(n)) {
      const upto = src.slice(0, m.index);
      called.set(n, upto.split('\n').length);
    }
  }
  const dang = [];
  for (const [n, line] of called) {
    if (KEYWORDS.has(n) || KNOWN_GLOBAL.has(n) || defined.has(n) || METHODISH.test(n)) continue;
    dang.push(n + '@' + line);
  }
  if (dang.length) {
    flagged++;
    console.log(path.relative(__dirname, file).replace(/\\/g, '/') + ' → 可疑未定义调用: ' + dang.join(', '));
  }
}
if (!flagged) console.log('scan_dangling[第一段·单文件]: 未发现可疑的未定义调用');

// ===== 第二段（1.75.42 新增）：**全仓**判据 —— 被调用、但全项目哪里都没有定义（= 真机必崩/静默死）=====
//   ★三个必要的「去噪」步骤（第一版全踩了，报出 174 条假阳性）：
//     ① 客户端 API 索引 `api_*.html` 里是**转义过的 JSON**（`\"name\":\"X\"`）⇒ 必须按 parse_api.js 那套
//        「取出 index 字符串再 JSON.parse」，直接正则匹配 `"name":"` 只能拿到 14 条；
//     ② **字符串字面量**要先剥掉（Locales 里的英文词、数据文件里的地名，都会被当成函数调用）；
//     ③ 定义形态要含**普通赋值**（`EVAL_X = someLocal` 这种桥），否则一堆真定义被当成「没定义」。
// ★一趟扫的 Lua 清洗器（**必须先处理字符串再处理注释**）：第一版写成「先按行剥 `--` 再剥引号」，
//   于是 `local s = "a--b"` 这类行被从中间切断、引号失衡 ⇒ 后面大半个文件被当成字符串吃掉
//   （实测 Engine.lua 315KB 只剩 36KB）⇒ 报出一堆「明明有定义」的假阳性。这里一次扫描同时处理：
//   长串 `[[..]]`/`[=[..]=]` · 行注释 `--` · 普通串 `"…"`/`'…'`（含 `\` 转义）。
function cleanLua(s) {
  let out = '', i = 0;
  while (i < s.length) {
    const c = s[i], n = s[i + 1];
    if (c === '[' && (n === '[' || n === '=')) {
      let eq = 0, j = i + 1;
      while (s[j] === '=') { eq++; j++; }
      if (s[j] === '[') {
        const close = ']' + '='.repeat(eq) + ']';
        const k = s.indexOf(close, j + 1);
        i = (k < 0) ? s.length : k + close.length;
        out += ' ';
        continue;
      }
    }
    if (c === '-' && n === '-') {
      const k = s.indexOf('\n', i);
      i = (k < 0) ? s.length : k;          // 保留换行，行号不变
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c; i++;
      while (i < s.length && s[i] !== q) { if (s[i] === '\\') i++; i++; }
      i++; out += '""';
      continue;
    }
    out += c; i++;
  }
  return out;
}
const API = new Set();
for (const f of fs.readdirSync(__dirname)) {
  if (!/^api_.*\.html$/.test(f)) continue;
  const html = fs.readFileSync(path.join(__dirname, f), 'utf8');
  const m = html.match(/index: JSON\.parse\('((?:[^'\\]|\\.)*)'\)/);
  if (!m) continue;
  try {
    const raw = JSON.parse('"' + m[1].replace(/"/g, '\\"') + '"');
    const idx = JSON.parse(raw);
    for (const e of idx) if (e && e.name) API.add(e.name);
  } catch (e) { /* 索引读不出就少一层白名单，宁多报不漏报 */ }
}
function cleanLuaOld(s) { return s; }   // 占位（旧的两段式清洗已删，见 cleanLua 的注释）
const files = listLua(__dirname, []).filter(function (f) { return f.indexOf(path.sep + 'doc' + path.sep) < 0; });
const definedAll = new Set();
const callers = new Map();
for (const file of files) {
  const src = cleanLua(fs.readFileSync(file, 'utf8'));
  for (const re of [/function\s+([A-Za-z_][A-Za-z0-9_]*)\s*[.(]/g,
                    /([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function/g,
                    /(?:^|\n)\s*(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)/g,
                    // ★多名字 local（`local a, b, c = …`）——第一版只取第一个名字，把 `atkUse`/`origUp` 误报成未定义
                    /local\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)+)/g]) {
    for (const m of src.matchAll(re)) {
      for (const nm of m[1].split(',')) { const t = nm.trim(); if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(t)) definedAll.add(t); }
    }
  }
  for (const m of src.matchAll(/function[^()\n]*\(([^)]*)\)/g)) {
    for (const p of m[1].split(',')) { const n = p.trim(); if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(n)) definedAll.add(n); }
  }
}
for (const file of files) {
  const raw = fs.readFileSync(file, 'utf8');
  const src = cleanLua(raw);
  const rel = path.relative(__dirname, file).replace(/\\/g, '/');
  for (const m of src.matchAll(/(?<![.:A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\s*\(/g)) {
    const n = m[1];
    if (!callers.has(n)) callers.set(n, []);
    // ★「这一处调用有没有 type(X)=="function" 守卫」决定它是**真机必崩**还是**静默死**。
    //   ★守卫判定必须回到**原文**做：cleanLua 会把 `"function"` 这种字符串字面量剥成 `""`，
    //   在清洗后的文本里永远匹配不到守卫（第一版就是这么把 4 个有守卫的名字误报成「必崩」的）。
    const guarded = new RegExp('type\\s*\\(\\s*' + n + '\\s*\\)\\s*==').test(raw);
    const cur = callers.get(n);
    if (!cur.some(function (e) { return e.file === rel && e.guarded === guarded; })) cur.push({ file: rel, guarded: guarded });
  }
}
const missing = [];
for (const [n, where] of callers) {
  if (KEYWORDS.has(n) || KNOWN_GLOBAL.has(n) || METHODISH.test(n)) continue;
  if (definedAll.has(n) || API.has(n)) continue;
  const unguarded = where.filter(function (e) { return !e.guarded; }).map(function (e) { return e.file; });
  const guarded = where.filter(function (e) { return e.guarded; }).map(function (e) { return e.file; });
  missing.push({ name: n, unguarded: unguarded, guarded: guarded });
}
const hard = missing.filter(function (m) { return m.unguarded.length > 0; }).sort(function (a, b) { return a.name.localeCompare(b.name); });
const soft = missing.filter(function (m) { return m.unguarded.length === 0; }).sort(function (a, b) { return a.name.localeCompare(b.name); });
console.log('scan_dangling[第二段·全仓]: 客户端 API 白名单 ' + API.size + ' 条 · 全仓定义 ' + definedAll.size + ' 个');
if (hard.length === 0) console.log('scan_dangling[第二段·全仓]: ✅ 没有**无守卫**的「被调用却没定义」名字（真机必崩那一类）');
else {
  console.log('scan_dangling[第二段·全仓]: ★★★ ' + hard.length + ' 个**无守卫**（真机必崩，等同 shNoPop 那次）：');
  for (const m of hard) console.log('  - ' + m.name + '  ← ' + m.unguarded.join(', '));
}
if (soft.length > 0) {
  console.log('scan_dangling[第二段·全仓]: （' + soft.length + ' 个**有 type 守卫** ⇒ 不崩但功能静默死/死钩子，逐个复核）');
  for (const m of soft) console.log('  - ' + m.name + '  ← ' + m.guarded.join(', '));
}
