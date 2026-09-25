// sync_game.js —— 把插件文件同步到本机游戏目录（用户 1.74.8 要求，方便真机调试）
// ★口径：以 EvalHelp.toc 现算的模块清单为准（与发布包 PACK LIST 同一口径），
//   再补上 media\ 素材（.tga 图标）—— 两者合起来就是「插件实际需要的东西」。
// ★绝不带过去：test_*.lua / luacheck.js / gen_*.js / parse_api.js / dump_cat.js /
//   tmp\ / preview\ / doc\ / .git\ / .dsh\ / pay\ / _icons_scan\ / *.md / api_*.html
//
// ★★两种机器形态（1.75.3 补第二种；用户 2026-09-25 明确）：
//   ① **另一台电脑**：仓库不在游戏目录里 ⇒ 全量复制主插件到 DST（下面那行常量）。
//   ② **本机**：仓库本址就在 `...\Interface\AddOns\EvalHelp` ⇒ 主插件**不用复制**（git pull / 改文件即同步），
//      但 **`addons\` 里的子插件必须复制到「当前插件同级目录」**（= `Interface\AddOns\<子插件名>\`）。
//      否则游戏里跑的是**老的那份子插件** —— 新模块 + 老实现两套逻辑同时改锚点，
//      正是 1.74.30 修过的那类「两处真值打架」事故。
//      ⇒ **本机也要跑本脚本**（`node sync_game.js`）：走「本机分支」，主插件跳过、子插件复制到同级，并如实报数。
const fs = require('fs');
const path = require('path');

const SRC = __dirname;
// ★这个 DST 是**另一台电脑**上的游戏目录 —— 本机没有它属正常，不是出错。
const DST = 'E:\\soft\\game\\eb\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns\\EvalHelp';

// 本仓库自己是不是已经躺在某个游戏 AddOns\EvalHelp 里（本机正是这种情形）
const SELF_IN_ADDONS = /[\\/]Interface[\\/]AddOns[\\/]EvalHelp$/i.test(SRC);
const dstParent = path.dirname(DST);
const mainTarget = fs.existsSync(dstParent) ? DST : null;                 // null = 本机形态：主插件跳过
const addonsDst = mainTarget ? dstParent : (SELF_IN_ADDONS ? path.dirname(SRC) : null);

if (mainTarget === null) {
  console.log('SKIP(主插件): 目标游戏 AddOns 目录不存在 -> ' + dstParent);
  console.log(SELF_IN_ADDONS
    ? '  本机无需同步主插件：仓库本址已在游戏 AddOns 内（' + SRC + '）—— 改文件 / git pull 即等于同步到游戏。'
    : '  本仓库不在任何游戏 AddOns 内：若本机确有游戏安装在别处，请改上面的 DST。');
}
if (addonsDst === null) {
  console.log('SKIP(子插件): 不知道把 addons\\ 复制到哪（既没有 DST，本仓库也不在 AddOns\\EvalHelp 内）');
  process.exit(0);
}

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// ★只复制**内容变了**的文件（可反复跑；同内容不算复制，报告里单独计「同」）
function copyIfChanged(from, to) {
  try {
    if (fs.existsSync(to) && fs.readFileSync(to).equals(fs.readFileSync(from))) return false;
  } catch (e) { /* 读不了就照常覆盖 */ }
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  return true;
}

// ===== ① ~ ③ 主插件：另一台电脑才需要 =====
if (mainTarget !== null) {
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
  const mediaRoot = path.join(SRC, 'media');
  if (fs.existsSync(mediaRoot)) {
    for (const p of walk(mediaRoot, [])) mods.push(path.relative(SRC, p));
  }

  // ③ 复制（保留子目录结构）
  let copied = 0, same = 0, missing = [];
  for (const rel of mods) {
    const from = path.join(SRC, rel);
    if (!fs.existsSync(from)) { missing.push(rel); continue; }
    if (copyIfChanged(from, path.join(mainTarget, rel))) copied++; else same++;
  }
  console.log('SYNC OK(主插件): 改 ' + copied + ' / 同 ' + same + ' 个文件 -> ' + mainTarget);
  if (missing.length) console.log('MISSING (' + missing.length + '): ' + missing.join(', '));
}

// ===== ④ 独立子插件目录 addons\<名>\ → <当前插件同级目录>\<名>\ =====
//   ★为什么必须有这一步：`.toc` 只覆盖主插件的模块清单，而本仓库**还有子插件**（addons/EH_DebugBox）。
//   1.74.30 把框拖拽整块搬进主插件、子插件那侧改成瘦转发 —— 若只同步主插件，游戏里跑的就是
//   「新模块 + 老实现」两套逻辑同时改锚点（正是本次要修的那类「两处真值打架」）。
const addonsRoot = path.join(SRC, 'addons');
if (!fs.existsSync(addonsRoot)) {
  console.log('（没有 addons\\ 目录：没有子插件要复制）');
  process.exit(0);
}
const addonNames = [], addonDetail = [];
let addonCopied = 0, addonSame = 0;
for (const e of fs.readdirSync(addonsRoot, { withFileTypes: true })) {
  if (!e.isDirectory()) continue;
  addonNames.push(e.name);
  const from = path.join(addonsRoot, e.name);
  let c = 0, s = 0;
  for (const f of walk(from, [])) {
    const to = path.join(addonsDst, e.name, path.relative(from, f));
    if (copyIfChanged(f, to)) { addonCopied++; c++; } else { addonSame++; s++; }
  }
  addonDetail.push(e.name + '(改' + c + '/同' + s + ')');
}
console.log('SYNC OK(子插件): ' + addonCopied + ' 个文件改动 -> ' + addonsDst + path.sep + '[' + addonNames.join(', ') + ']'
  + '  明细：' + addonDetail.join(' · ') + '（同内容 ' + addonSame + ' 个未重写）');
