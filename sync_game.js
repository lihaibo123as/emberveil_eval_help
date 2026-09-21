// sync_game.js —— 把插件文件同步到本机游戏目录（用户 1.74.8 要求，方便真机调试）
// ★口径：以 EvalHelp.toc 现算的模块清单为准（与发布包 PACK LIST 同一口径），
//   再补上 media\ 素材（.tga 图标）—— 两者合起来就是「插件实际需要的东西」。
// ★绝不带过去：test_*.lua / luacheck.js / gen_*.js / parse_api.js / dump_cat.js /
//   tmp\ / preview\ / doc\ / .git\ / .dsh\ / pay\ / _icons_scan\ / *.md / api_*.html
const fs = require('fs');
const path = require('path');

const SRC = __dirname;
const DST = 'E:\\soft\\game\\eb\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns\\EvalHelp';

if (!fs.existsSync(path.dirname(DST))) {
  console.log('SKIP: 游戏 AddOns 目录不存在 -> ' + path.dirname(DST));
  process.exit(0);
}

// ① 从 .toc 现算模块清单（唯一真值，别另写一份名单）
const toc = fs.readFileSync(path.join(SRC, 'EvalHelp.toc'), 'utf8');
const mods = [];
for (const raw of toc.split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  mods.push(line.replace(/\\/g, path.sep)); // toc 里是 反斜杠 路径
}
mods.push('EvalHelp.toc'); // toc 自己也要（原名，不替换分隔符）

// ② media\ 下的所有素材（.tga）
function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}
const mediaRoot = path.join(SRC, 'media');
if (fs.existsSync(mediaRoot)) {
  for (const p of walk(mediaRoot, [])) mods.push(path.relative(SRC, p));
}

// ③ 复制（保留子目录结构）
let copied = 0, missing = [];
for (const rel of mods) {
  const from = path.join(SRC, rel);
  if (!fs.existsSync(from)) { missing.push(rel); continue; }
  const to = path.join(DST, rel);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  copied++;
}
console.log('SYNC OK: ' + copied + ' 个文件 -> ' + DST);
if (missing.length) console.log('MISSING (' + missing.length + '): ' + missing.join(', '));
