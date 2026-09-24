// scan_dangling.js —— 「调用了但本文件没定义、也不像客户端 API」的粗筛工具（人工复核用，不是闸门）
// 用途：跨分支/跨文件抄代码时，抄来了一堆**本文件不存在**的助手（本轮实例：SM / flushStore）
//   —— luacheck 不查未定义全局，ADDON DECL ORDER 只查「声明在引用之后」，都拦不住它。
// 用法：node scan_dangling.js
const fs = require('fs');
const path = require('path');

const KEYWORDS = new Set(['and', 'or', 'not', 'if', 'then', 'else', 'elseif', 'end', 'for', 'while', 'repeat',
  'until', 'do', 'return', 'function', 'local', 'in', 'break', 'nil', 'true', 'false']);
const KNOWN_GLOBAL = new Set(['pcall', 'xpcall', 'type', 'tostring', 'tonumber', 'ipairs', 'pairs', 'next',
  'unpack', 'select', 'error', 'assert', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal',
  'print', 'format', 'strfind', 'strsub', 'gsub', 'getglobal', 'table', 'string', 'math', '_G', 'arg1', 'arg2',
  'this', 'event', 'CreateFrame', 'GetTime', 'SlashCmdList', 'EVAL_LOGLINE', 'EVAL_SAY',
  'concat', 'insert', 'remove', 'sort', 'getn', 'upper', 'lower', 'find', 'gsub', 'sub', 'format', 'rep', 'floor']);
// 常见「点在方法上」的调用名（来自 SetXxx 家族）——避免误报
const METHODISH = /^(Set|Get|Is|Has|Enable|Disable|Register|Unregister|Show|Hide|Clear|Add|Remove|Play|Stop|Start)/;

function listLua(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) listLua(p, out);
    else if (e.name.slice(-4) === '.lua') out.push(p);
  }
  return out;
}

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
if (!flagged) console.log('scan_dangling: 未发现可疑的未定义调用');
