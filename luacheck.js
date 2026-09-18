// luacheck.js —— 语法闸门（fengari 真解析）
// ★★★1.73.28 起**逐个文件**检查：原先只 loadbuffer 一个文件（EvalHelp.lua），其余模块的语法错误
//   会**整片漏过去** —— 本轮实测：Toolbox.lua 里一处坏转义（手写 "["\]" 这种）luacheck 照样报
//   SYNTAX OK，直到运行时 load 才炸（LOAD ERROR ... expected ')' near backslash）。
//   ★教训：语法闸门必须覆盖「所有会被 load 的文件」，只查主文件等于没查（本项目最怕的「绿但真错」）。
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, to_luastring } = fengari;

const SKIP_DIRS = { 'node_modules': 1, '.git': 1, 'tmp': 1, 'preview': 1, 'pay': 1 };

function listLua(dir, out) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
  for (const e of entries) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (!SKIP_DIRS[e.name]) listLua(p, out); }
    else if (e.name.slice(-4) === '.lua') out.push(p);
  }
  return out;
}

const arg = process.argv[2];
const files = arg ? [arg] : listLua(__dirname, []);
if (!files.length) { console.log('SYNTAX ERROR: no .lua files found'); process.exit(1); }

let bad = 0;
for (const f of files) {
  const src = fs.readFileSync(f);
  const L = lauxlib.luaL_newstate();
  const st = lauxlib.luaL_loadbuffer(L, src, src.length, to_luastring(path.basename(f)));
  if (st !== lua.LUA_OK) {
    console.log('SYNTAX ERROR [' + path.relative(__dirname, f) + ']: ' + lua.lua_tojsstring(L, -1));
    bad++;
  }
}
if (bad) { console.log('SYNTAX FAIL: ' + bad + '/' + files.length + ' files'); process.exit(1); }
console.log('SYNTAX OK: ' + files.length + ' files checked');
