/** probe_localorder.js —— 局部量**在声明之前被引用**的静态审计（真机表现：红字 `attempt to call global 'X' (a nil value)`）
 *
 *  背景：1.75.12 用户实测 `DataSearch.lua:3301: attempt to call global 'qpFillList' (a nil value)` ——
 *        根因是「局部函数的**声明位置**即契约」：EVAL_QP_SCROLL 排在 `local function qpFillList` 之前，
 *        于是它捕获的是**全局 nil**。这类事故不报错、只在真机弹红字，必须靠静态审计守。
 *
 *  实现（两趟）：摘注释/字符串 → 建**作用域树**（function 参数 / then / do 开块，elseif/else/end 收块；
 *    local 声明挂到当前块）→ 第二趟对每个引用由内向外找最近声明：
 *      · 找到「声明位置 < 引用位置」或参数同名        → 正常
 *      · 只找到「声明位置 > 引用位置」（将来才声明）  → **报警**（此刻抓到的是全局，极可能 nil）
 *  用法（CLI）  ：node probe_localorder.js [文件...]     默认 DataSearch.lua + quest/QuestChains.lua + EvalHelp.lua
 *  用法（自检） ：node probe_localorder.js --selftest   正例必报 / 反例不报（判据纪律：闸门自己也要被证明）
 *  用法（模块） ：const { scan } = require('./probe_localorder.js')
 */
'use strict';
const fs = require('fs');

/** 去注释与字符串字面量（等长空白替换，字符位置不变） */
function blank(raw) {
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c === '-' && raw[i + 1] === '-') {
      let j = raw.indexOf('\n', i);
      if (j < 0) j = raw.length;
      out += ' '.repeat(j - i);
      i = j - 1;
      continue;
    }
    if (c === '"' || c === "'") {
      out += ' ';
      i++;
      while (i < raw.length && raw[i] !== c) {
        if (raw[i] === '\\') { out += '  '; i += 2; continue; }
        out += raw[i] === '\n' ? '\n' : ' ';
        i++;
      }
      out += ' ';
      continue;
    }
    out += c;
  }
  return out;
}

function scan(raw) {
  const code = blank(raw);
  const lines = raw.split(/\r?\n/);
  const lineOf = idx => code.slice(0, idx).split('\n').length;

  const mkScope = parent => ({ parent: parent, params: new Set(), decls: [], refs: [], kids: [] });
  const root = mkScope(null);
  let cur = root;
  const declIndex = {};                       // 名字 → [{at}]（同名可多处声明）

  const push = params => {
    const s = mkScope(cur);
    cur.kids.push(s);
    if (params) s.params = params;
    if (pending) { for (const n of pending) s.params.add(n); pending = null; }  // for 循环变量挂在循环体作用域
    cur = s;
  };
  const pop = () => { if (cur.parent) cur = cur.parent; };
  let pending = null;

  const tokRe = /\b(function|then|do|elseif|else|end|until|local|for)\b|\b([A-Za-z_]\w*)\s*\(|\b([A-Za-z_]\w*)\s*[.\[]/g;
  let m;
  while ((m = tokRe.exec(code))) {
    const kw = m[1];
    if (kw === 'for') {                       // for i = 1, n do / for k, v in pairs(t) do
      const fm = code.slice(m.index, m.index + 200)
        .match(/^for\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*(?:=|in\b)/);
      if (fm) pending = fm[1].split(',').map(s => s.trim());
      continue;
    }
    if (kw === 'local') {
      const lm = code.slice(m.index, m.index + 200)
        .match(/^local\s+(?:function\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)/);
      if (lm) for (const raw2 of lm[1].split(',')) {
        const n = raw2.trim();
        cur.decls.push({ n: n, at: m.index });
        (declIndex[n] = declIndex[n] || []).push({ at: m.index });
      }
      continue;
    }
    if (kw === 'function') {                  // 参数只取括号内 ⇒ 不会把函数名当参数
      const op = code.indexOf('(', m.index);
      const cl = op < 0 ? -1 : code.indexOf(')', op);
      push(new Set(((op < 0 || cl < 0) ? '' : code.slice(op + 1, cl)).match(/[A-Za-z_]\w*/g) || []));
      continue;
    }
    if (kw === 'then' || kw === 'do') { push(null); continue; }
    // ★if 的分支配对：then 开块；elseif 收上一块（它自己的 then 会再开）；else 收上一块**并**开新块（由 end 收）
    //   —— 首个版本让 else 只 pop 不 push，块栈于是**越来越浅**，函数作用域被提前弹掉，
    //   把 DD_FILTER(items, locked, ...) 这类**参数**误报成「先引用后声明」。
    if (kw === 'elseif') { pop(); continue; }
    if (kw === 'else') { pop(); push(null); continue; }
    if (kw === 'end' || kw === 'until') { pop(); continue; }
    const name = m[3] || m[2];
    if (!name) continue;
    // ★字段名/方法名不算本文件的局部量引用：`b.refresh()` / `ui.root` / `row.icon` / `e.chains[j]`
    //   （首个版本漏了这一刀，把 ui.root / pc.bg / row.icon 全报成「先引用后声明」）
    if (m[2] && (code[m.index - 1] === '.' || code[m.index - 1] === ':')) continue;
    if (m[3] && (code[m.index - 1] === '.' || code[m.index - 1] === ':')) continue;
    cur.refs.push({ n: name, at: m.index });
  }

  const bad = [];
  (function visit(sc) {
    for (const r of sc.refs) {
      const decls = declIndex[r.n];
      if (!decls) continue;
      let ok = false, future = false;
      for (let s = sc; s; s = s.parent) {
        if (s.params.has(r.n)) { ok = true; break; }
        let before = false, after = false;
        for (const d of s.decls) { if (d.n !== r.n) continue; if (d.at < r.at) before = true; else after = true; }
        if (before) { ok = true; break; }
        if (after) future = true;
      }
      if (!ok && future) {
        const useLine = lineOf(r.at);
        const later = decls.map(d => lineOf(d.at)).filter(l => l > useLine).sort((a, b) => a - b);
        bad.push({ n: r.n, useLine: useLine, declLine: later[0] || 0,
          text: (lines[useLine - 1] || '').trim().slice(0, 70) });
      }
    }
    for (const k of sc.kids) visit(k);
  })(root);
  return bad;
}

module.exports = { scan };

if (require.main === module && process.argv[2] === '--selftest') {
  const cases = [
    { want: 1, why: '局部函数在声明前被调用（真机抓全局 nil）',
      src: 'local function outer()\n  helper()\nend\nlocal function helper() end\n' },
    { want: 1, why: '更早的函数引用后面才声明的局部函数',
      src: 'local f = function() return later() end\nlocal function later() end\n' },
    { want: 1, why: 'if 块里引用块外的将来声明',
      src: 'local function a()\n  if x then b() end\nend\nlocal function b() end\n' },
    { want: 0, why: '参数同名（不是全局）',
      src: 'local function plan(measure) return measure("x") end\nlocal function measure(s) return s end\n' },
    { want: 0, why: '字段/方法调用 b.refresh()',
      src: 'local function go(b) b.refresh() end\nlocal function refresh() end\n' },
    { want: 0, why: '先声明后赋值（本次修复后的形状）',
      src: 'local f\nlocal function scroll() f() end\nf = function() end\n' },
    { want: 0, why: '注释里的名字不算（摘注释）',
      src: '-- local function g() h() end\nlocal function g() end\n' },
  ];
  let bad = 0;
  for (const c of cases) {
    const got = scan(c.src).length;
    if (got !== c.want) bad++;
    console.log((got === c.want ? 'OK  ' : 'FAIL') + '  want=' + c.want + ' got=' + got + '  ' + c.why);
  }
  console.log(bad ? 'SELFTEST FAIL ' + bad + ' 条' : 'SELFTEST OK（' + cases.length + ' 条夹具）');
  process.exitCode = bad ? 1 : 0;
  return;
}

if (require.main === module) {
  const files = process.argv.slice(2).length ? process.argv.slice(2)
    : ['DataSearch.lua', 'quest/QuestChains.lua', 'EvalHelp.lua'];
  let total = 0;
  for (const f of files) {
    const bad = scan(fs.readFileSync(f, 'utf8'));
    if (bad.length) {
      total += bad.length;
      console.log('!! ' + f + '：' + bad.length + ' 处「先引用后声明」（真机会抓全局 nil）');
      for (const b of bad) console.log('   ' + b.n + '  引用@' + b.useLine + ' < 声明@' + b.declLine + '   |' + b.text);
    } else console.log('OK ' + f + '：无「先引用后声明」的局部量');
  }
  process.exitCode = total ? 1 : 0;
}
