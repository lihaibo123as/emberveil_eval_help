// sync_game.js —— 把插件文件同步到本机游戏目录（用户 1.74.8 要求，方便真机调试）
// ★口径：以 EvalHelp.toc 现算的模块清单为准（与发布包 PACK LIST 同一口径），
//   再补上 media\ 素材（.tga 图标）—— 两者合起来就是「插件实际需要的东西」。
// ★绝不带过去：test_*.lua / luacheck.js / gen_*.js / parse_api.js / dump_cat.js /
//   tmp\ / preview\ / doc\ / .git\ / .dsh\ / pay\ / _icons_scan\ / *.md / api_*.html
const fs = require('fs');
const path = require('path');

const SRC = __dirname;
// ★下面这个 DST 是**另一台电脑**上的游戏目录（用户 1.74.9 说明）——本机没有它属正常，不是出错。
//   本机那一台的仓库**本身就放在游戏的 AddOns\EvalHelp 里**，git pull 即等于同步到游戏、无需再复制；
//   所以路径不存在时只如实报告并退出（不报错、不动任何文件）。换机器时改这一行即可。
const DST = 'E:\\soft\\game\\eb\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns\\EvalHelp';

if (!fs.existsSync(path.dirname(DST))) {
  // 自检：本仓库自己是不是已经躺在某个游戏 AddOns\EvalHelp 里（本机正是这种情形）
  const selfInAddons = /[\\/]Interface[\\/]AddOns[\\/]EvalHelp$/i.test(SRC);
  console.log('SKIP: 目标游戏 AddOns 目录不存在 -> ' + path.dirname(DST));
  console.log(selfInAddons
    ? '  本机无需同步：仓库本址已在游戏 AddOns 内（' + SRC + '）—— git pull 即等于同步到游戏。'
    : '  本仓库不在任何游戏 AddOns 内：若本机确有游戏安装在别处，请改上面的 DST。');
  process.exit(0);
}

// ① 从 .toc 现算模块清单（唯一真值，别另写一份名单）
const toc = fs.readFileSync(path.join(SRC, 'EvalHelp.toc'), 'utf8');
const mods = [];
for (const raw of toc.split(/\r?\n/)) {
  const line = raw.trim();
  if (!line || line.startsWith('#')) continue;
  mods.push(line.replace(/[\\]/g, path.sep)); // toc 里是 反斜杠 路径
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

// ④ 独立子插件目录 addons\<名>\ → Interface\AddOns\<名>\（1.74.30 补）
//   ★为什么必须有这一步：`.toc` 只覆盖主插件的模块清单，而本仓库**还有子插件**（addons/EH_DebugBox）。
//   1.74.30 把框拖拽整块搬进主插件、子插件那侧改成瘦转发 —— 若只同步主插件，游戏里跑的就是
//   「新模块 + 老实现」两套逻辑同时改锚点（正是本次要修的那类「两处真值打架」）。
const addonsRoot = path.join(SRC, 'addons');
const addonsDst = path.dirname(DST);
let addonCopied = 0;
const addonNames = [];
if (fs.existsSync(addonsRoot)) {
  for (const e of fs.readdirSync(addonsRoot, { withFileTypes: true })) {
    if (!e.isDirectory()) continue;
    addonNames.push(e.name);
    const from = path.join(addonsRoot, e.name);
    for (const f of walk(from, [])) {
      const to = path.join(addonsDst, e.name, path.relative(from, f));
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(f, to);
      addonCopied++;
    }
  }
  console.log('SYNC OK: ' + addonCopied + ' 个文件 -> ' + addonsDst + '\\[' + addonNames.join(', ') + ']\\');
}
if (missing.length) console.log('MISSING (' + missing.length + '): ' + missing.join(', '));
