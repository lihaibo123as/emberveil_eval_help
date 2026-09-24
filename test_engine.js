const fs=require('fs'), path=require('path');
const fengari=require('fengari');
const {lua,lauxlib,lualib,to_luastring}=fengari;

// ── Icon asset verification (1.70.26) ────────────────────────────────────────────────
// This client SILENTLY DRAWS NOTHING when an addon texture path is wrong (missing .tga
// suffix rules, wrong case, bad file name). Nothing in Lua can catch that -- the call
// succeeds and the texture is just empty. So verify every category icon referenced by
// DataSearch actually exists on disk, before running the suite.
// Skipped gracefully when the UnrealQuest addon is not checked out next to us.
function checkIconAssets() {
  const dsPath = 'DataSearch.lua';
  if (!fs.existsSync(dsPath)) return null;
  const ds = fs.readFileSync(dsPath, 'utf8');
  const rootMatch = ds.match(/DS_ANN_ICON_ROOT\s*=\s*"([^"]+)"/);
// ===== WIN WIDTH CHECK: one width source, both windows use it =====
// ★ 1.70.45 用户要求：配置窗加宽 ~100，且技能编辑窗与它同宽。
// 两个窗口各写一份宽度就是本项目反复踩的「两份数据」坑（版本号/声明顺序同理），故用源码检查钉死。
(function () {
  const src = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const nl = src.split(String.fromCharCode(10));
  // 1) 来源函数存在且返回 800/660
  const fnIdx = nl.findIndex(l => l.indexOf("local function cfWinWidth()") === 0);
  if (fnIdx < 0) { console.log("WIN WIDTH CHECK: FAIL - cfWinWidth() is missing"); process.exitCode = 1; return; }
  const body = nl.slice(fnIdx, fnIdx + 3).join(" ");
  if (body.indexOf("800 or 660") < 0) {
    console.log("WIN WIDTH CHECK: FAIL - cfWinWidth() must return 800 (wide langs) or 660 (zhCN); got: " + body.trim());
    process.exitCode = 1;
    return;
  }
  // 2) 恰好三个构建点调用它（配置窗 + 技能编辑窗 + 案例模版窗）—— ★1.71.3 模版窗从固定 330 改成同源宽度后变 3。
  //    ★这个「数个数」不是宽度正确性的证明，而是**新窗口必须来这里登记**的哨兵（免得多出一处悄悄写死的宽度）。
  //      真正的判据是上面第 1 条（唯一来源）与下面第 3 条（旧字面量不得残留）。
  // 只数「窗口宽度赋值」这种形态。★不能用 / = cfWinWidth\(\)/ ——
  //   那会把「用窗口宽度做布局换算」的调用也算进来（如 closeLeft = cfWinWidth() - 12 - 64），
  //   而那是**正确的用法**（读同一个来源做布局），不是多出来的构建点（本轮实测误报）。
  //   判据：检查要盯「宽度**被赋值**」这个语义，而不是「文本里出现了这个调用」。
  const calls = (src.match(/(local\s+[\w, ]*?W[\w, ]*?)\s*=\s*cfWinWidth\(\)/g) || []).length +
                (src.match(/WIDE and cfWinWidth\(\)|cfWinWidth\(\)/g) || []).length * 0;
  if (calls !== 3) {
    console.log("WIN WIDTH CHECK: FAIL - expected exactly 3 build sites calling cfWinWidth() (config / skill editor / template), found " + calls);
    process.exitCode = 1;
    return;
  }
  // 3) 旧字面量不得残留
  const stale = ["WIDE and 700 or 560", "local W, H = 470, 280"];
  const bad = stale.filter(x => src.indexOf(x) >= 0);
  if (bad.length) {
    console.log("WIN WIDTH CHECK: FAIL - stale hardcoded width still present: " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("WIN WIDTH CHECK: single source, " + calls + " build sites, 800/660");
})();

// ===== DECL ORDER CHECK: every top-level local must be declared before its first use =====
// ★★1.70.44 用户实测定案：「点定位后地图空白」的真凶是一个变量被两批函数分别绑到了两个位置：
//   dsOverlayStr/dsSetOverlay 定义在 local dsAnnOverlay 之前 → 绑全局（写入成功）；
//   dsAnnDraw/REFRESH 定义在其后 → 读局部（恒 nil）。
//   Lua 不报错、pcall 全成功，只是行为错——而日志里两个读者会给出相反的答案。
//   ★Lua 的作用域是**词法**的：引用点若在 local 声明之前，永远看不到它（与调用顺序无关）——
//     所以「声明在引用之后」一定是真 bug，不存在误报式的「其实运行时能拿到」。
// ★★1.70.46 两处扩展（本轮的坑正是踩在这两点上）：
//   ① 覆盖面：从只扫 DataSearch.lua 扩到**全部生产 .lua 文件**。
//      事故：seSecKinds 声明在 EVAL_HELP_SE_REFRESH 之后 → 用户点「自身buff检查」直接红字
//      attempt to call global 'seSecKinds' (a nil value)。旧检查只扫 DataSearch.lua，完全看不见。
//      **检查存在 ≠ 覆盖到位**：一个只保护一个文件的检查，对其它文件等于没有。
//   ② 跳过「同名还有函数内 local 声明」的短名（W / H / x / y 这类）：它们在文件里是**多个不同的变量**，
//      按名字比对必然误报（首版就误报了 EvalHelp.lua:153 的 local W —— 那是另一个函数里的 W）。
function declOrderScanFiles(files) {
  const bad = [];
  let totalLocals = 0;
  const isName = (s) => new RegExp("^[A-Za-z_][A-Za-z0-9_]*$").test(s);
  for (const f of files) {
    const p = path.isAbsolute(f) ? f : path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const label = path.isAbsolute(f) ? path.relative(__dirname, f).replace(/\\/g, "/") : f;
    const lines = fs.readFileSync(p, "utf8").split(String.fromCharCode(10));
    // ★1.70.47 本仓库是 **CRLF** 文件：按 "\n" 切行后行尾还留一个 "\r"。
    //   对 `local x` 这种「整行都是模式」的匹配来说，`(.+)$` 会把 "\r" 一起抓进名字里 →
    //   isName 判定失败 → 该声明**对检查不可见**（正是 auraTexOf 前置声明漏网的原因）。
    const strip = (l) => { const i = l.indexOf("--"); const s = i >= 0 ? l.slice(0, i) : l; return s.replace(/\r+$/, ""); };
    // 收集「函数内」的 local 名字（行首有缩进）→ 这些名字有歧义，跳过
    const inner = new Set();
    for (let i = 0; i < lines.length; i++) {
      const code = strip(lines[i]);
      let m = code.match(new RegExp("^[ ]+local" + "[ ]+" + "function" + "[ ]+" + "([A-Za-z_][A-Za-z0-9_]*)"));
      if (m) { inner.add(m[1]); continue; }
      m = code.match(new RegExp("^[ ]+local" + "[ ]+(.+?)="));
      if (m) for (const raw of m[1].split(",")) { const nm = raw.trim(); if (isName(nm)) inner.add(nm); }
    }
    // 收集顶层 local 声明（含多名字、local function、以及**无初始值的纯前置声明**）
    // ★★1.70.47 补第三种形态：`local auraTexOf`（无 `=` 的前置声明）。
    //   事故：队伍选人判据要在 auraTexOf 之前用它（Lua 词法作用域 → 会绑到全局 nil），
    //   修法是**前置声明**；但旧正则只认 `local x = ...` 与 `local function x`，
    //   于是「前置声明」这个写法本身对检查**完全不可见**——检查静默通过，运行期才炸
    //   （而且被 pcall 吞成「选人结果不对」，不是红字，最难查）。
    //   ★教训：检查器要覆盖**它自己那套写法**的所有变体，否则修 bug 的手法会顺手挖出新盲区。
    const decls = {};
    for (let i = 0; i < lines.length; i++) {
      const code = strip(lines[i]);
      let m = code.match(new RegExp("^local" + "[ ]+" + "function" + "[ ]+" + "([A-Za-z_][A-Za-z0-9_]*)"));
      if (m) { if (decls[m[1]] === undefined) decls[m[1]] = i + 1; continue; }
      m = code.match(new RegExp("^local" + "[ ]+(.+?)="));
      if (m) {
        for (const raw of m[1].split(",")) {
          const nm = raw.trim();
          if (isName(nm) && decls[nm] === undefined) decls[nm] = i + 1;
        }
        continue;
      }
      m = code.match(new RegExp("^local" + "[ ]+(.+)$"));
      if (m) {
        for (const raw of m[1].split(",")) {
          const nm = raw.trim();
          if (isName(nm) && decls[nm] === undefined) decls[nm] = i + 1;
        }
      }
    }
    totalLocals += Object.keys(decls).length;
    // ★用法比对前要**先剥字符串字面量**：`SetPoint(fs,"TOP",...)` 里的 "TOP" 不是变量用法
    //   （首版没剥 → 当场误报 addons/EH_MapScale 的 TOP 变量；检查器的假红同样浪费轮次）
    const stripUse = (l) => strip(l)
      .replace(/"(?:[^"\\]|\\.)*"/g, '""')
      .replace(/'(?:[^'\\]|\\.)*'/g, "''")
      // ★剔除「赋值目标」：表字段 `name = v` / 普通赋值 `name = v` 都不是「读取该名字」
      //   （本轮误报：ui 表里的 `tipDbg = false,` 被当成 tipDbg 的用法）
      .replace(/(^|[,({\[])\s*[A-Za-z_][A-Za-z0-9_]*(\s*=[^=])/g, "$1$2");
    for (const nm of Object.keys(decls)) {
      if (inner.has(nm)) continue; // 名字在文件内有多个绑定 → 无法按名字判定，跳过
      const d = decls[nm];
      const re = new RegExp("(^|[^A-Za-z0-9_])" + nm + "([^A-Za-z0-9_]|$)");
      for (let i = 0; i < d - 1; i++) {
        if (re.test(stripUse(lines[i]))) { bad.push(label + ": " + nm + " used at " + (i + 1) + " but declared at " + d); break; }
      }
    }
  }
  return { bad: bad, totalLocals: totalLocals };
}

(function () {
  const files = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/DismountHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua", "quest/QuestData.lua", "quest/QuestBulk.lua", "quest/QuestChains.lua"];
  const r = declOrderScanFiles(files);
  const bad = r.bad, totalLocals = r.totalLocals;
  if (bad.length) {
    for (const b of bad.slice(0, 12)) console.log("DECL ORDER CHECK: FAIL - " + b);
    if (bad.length > 12) console.log("DECL ORDER CHECK: FAIL - ... and " + (bad.length - 12) + " more");
    process.exitCode = 1;
    return;
  }
  console.log("DECL ORDER CHECK: " + totalLocals + " top-level locals declare before use (" + files.length + " files)");
})();

// ===== ADDON DECL ORDER CHECK: 独立插件目录 addons/**/*.lua 同款检查 =====
// ★★★1.74.29（probe/map-scale 分支）用户原话：「频繁遇到这个坑就要记住」——
//   本轮在 addons/EH_SimpleMap 与 addons/EH_MapScale 上**连踩三次**同一个坑：
//     ① pb8Start 调 autoEnsureLabel（声明在文件后半）→ attempt to call global 'autoEnsureLabel'
//     ② pb9SetAll 调 featWm（同上）→ attempt to call global 'featWm'
//     ③ uiRefresh 调 hlApplySelected（高亮段被插到 ui 段之后）→ attempt to call global 'hlApplySelected'
//   共同点：**新段插到旧段之后**，却调用了旧段后面才声明的 local。luacheck 只查语法、查不出它；
//   而本项目原有的 DECL ORDER CHECK 只扫 EvalHelp 的 15 个生产文件，**独立插件目录完全没覆盖**
//   → 检查存在 ≠ 覆盖到位（1.70.46 的老教训）。这里补齐：addons/ 下每个 .lua 都扫。
(function () {
  const addonDir = path.join(__dirname, "addons");
  if (!fs.existsSync(addonDir)) { console.log("ADDON DECL ORDER CHECK: (无 addons/ 目录，跳过)"); return; }
  const files = [];
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (e.name.slice(-4) === ".lua") files.push(p);
    }
  })(addonDir);
  if (!files.length) { console.log("ADDON DECL ORDER CHECK: (无 addons/**/*.lua，跳过)"); return; }
  const r = declOrderScanFiles(files);
  if (r.bad.length) {
    for (const b of r.bad.slice(0, 12)) console.log("ADDON DECL ORDER CHECK: FAIL - " + b);
    if (r.bad.length > 12) console.log("ADDON DECL ORDER CHECK: FAIL - ... and " + (r.bad.length - 12) + " more");
    process.exitCode = 1;
    return;
  }
  console.log("ADDON DECL ORDER CHECK: " + r.totalLocals + " top-level locals declare before use (" + files.length + " addon files)");
})();

// ===== LAYOUT CHECK: a local must be declared before the code that reads it =====
// ★1.70.41 用户截图「应该有个按钮没了」——「类型: 全部」过滤钮不显示。
//   根因：filterBtn 用 DSL_ROW_BTN_Y 定位，而该 local 在 35 行之后才声明 →
//   那里读到全局 nil → SetPoint("TOPLEFT", parent, "TOPLEFT", x, nil) →
//   本客户端对 nil 锚点不做任何定位、也不报错 → 按钮落在未定义位置。
//   这是本项目第 10 次 local 作用域坑，也是「不报错的空操作」的又一实例。
//   桩不校验 SetPoint 的坐标参数，行为层测不到，所以在能读文件的一侧做源码检查。
(function () {
  const src = fs.readFileSync(path.join(__dirname, "DataSearch.lua"), "utf8");
  const lines = src.split(String.fromCharCode(10));
  const LOCAL_RE = new RegExp("^" + "[ ]*" + "local" + "[ ]+" + "([A-Za-z_][A-Za-z0-9_]*)" + "[ ]*=");
  const END_RE = new RegExp("^" + "end" + "[ ]*$");
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].indexOf("function EVAL_DS_BUILD") === 0) { start = i; break; }
  }
  if (start < 0) { console.log("LAYOUT CHECK: skipped (EVAL_DS_BUILD not found)"); return; }
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (END_RE.test(lines[i])) { end = i; break; }
  }
  const decls = {};
  for (let i = start; i < end; i++) {
    const m = lines[i].match(LOCAL_RE);
    if (m && decls[m[1]] === undefined) decls[m[1]] = i + 1;
  }
  const names = ["DSL_ROW_CY", "DSL_BTN_H", "DSL_BOX_H", "DSL_ROW_BTN_Y", "DSL_ROW_BOX_Y"];
  let bad = 0;
  for (const n of names) {
    const d = decls[n];
    if (d === undefined) { console.log("LAYOUT CHECK: FAIL - local " + n + " is never declared in EVAL_DS_BUILD"); bad++; continue; }
    const USE_RE = new RegExp("(^|[^A-Za-z0-9_])" + n + "([^A-Za-z0-9_]|$)");
    let first = -1;
    for (let i = start; i < end; i++) {
      if (i + 1 === d) continue;
      // ★必须跳过注释行：解释这个 bug 的注释里就写着这些变量名，
      //   不排除的话会把注释当成「使用」而误报（首版即如此）。
      const t = lines[i].replace(/^[ ]+/, "");
      if (t.indexOf("--") === 0) continue;
      if (USE_RE.test(lines[i])) { first = i + 1; break; }
    }
    if (first >= 0 && first < d) {
      console.log("LAYOUT CHECK: FAIL - " + n + " used at line " + first + " but declared at line " + d + " (reads global nil)");
      bad++;
    }
  }
  if (bad > 0) { process.exitCode = 1; return; }
  console.log("LAYOUT CHECK: " + names.length + " row constants declared before first use");
})();

// ===== VERSION CHECK: the source constant and the .toc must agree =====
// ★1.70.40 教训：发版时我只改了 EvalHelp.toc 的 ## Version，忘了源码里的
//   local VERSION —— 标题栏显示的是 VERSION 常量，于是实测截图里版本号还是旧值。
//   版本号有两份就必须有一条断言盯着它们相等。
(function () {
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  const m = toc.match(/##\s*Version:\s*([0-9.]+)/);
  if (!m) { console.log("VERSION CHECK: skipped (no ## Version in toc)"); return; }
  const tocVer = m[1];
  const src = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sm = src.match(/local VERSION\s*=\s*"([0-9.]+)"/);
  if (!sm) { console.log("VERSION CHECK: FAIL - could not find local VERSION in EvalHelp.lua"); process.exitCode = 1; return; }
  if (sm[1] !== tocVer) {
    console.log("VERSION CHECK: FAIL - EvalHelp.lua VERSION=" + sm[1] + " but EvalHelp.toc Version=" + tocVer);
    process.exitCode = 1;
    return;
  }
  console.log("VERSION CHECK: " + tocVer + " (source and toc agree)");
})();

// ===== LANG KEY CHECK: every literal L("KEY") must exist in all three locale packs =====
// ★为什么需要它：L() 找不到键时**返回键名本身**，于是界面上直接显示 "DS_DEP_OFF" 这种
//   内部标识——不报错、不崩溃，纯静默失败（本项目最典型的 bug 家族）。
//   键分散在 5 个源文件 × 3 个语言包里，靠人眼同步必然漏（1.70.28/1.70.45 都靠手工补键）。
// ★两处必须注意：① 语言包**一行多个键**，正则不能按行首锚定（我第一版就因此误报一片）；
//   ② `L("CT_" .. k)` 这类**拼接前缀**不是键，必须排除，否则同样误报。
(function () {
  const langs = ["zhCN", "enUS", "ruRU"];
  const packs = {};
  for (const lg of langs) {
    const s = fs.readFileSync(path.join(__dirname, "Locales", lg + ".lua"), "utf8");
    const set = new Set();
    for (const line of s.split(/\r?\n/)) {
      const code = line.replace(/--.*$/, "");
      let m; const re = /([A-Za-z_][A-Za-z0-9_]*)\s*=/g;
      while ((m = re.exec(code))) set.add(m[1]);
    }
    packs[lg] = set;
  }
  const used = new Set();
  // ★1.71.3 补上 Share.lua：它此前**不在扫描名单里**（与 DECL ORDER 的已知盲区同源）——
  //   于是「Share 用了某个键、只改了两种语言」永远是盲区（本轮 SH_CH_OFF 正好落在这里）。
  // ★★★1.74.31 补上 addons/EH_DebugBox/EH_DebugBox.lua：该子插件本轮**开始用 L("键")**（图层调试面板的
  //   「只显示有名」开关），不在名单里 = 新键只有两种语言的静默失败**永远不会红**（同 Share 那次盲区）。
  //   ★子插件不加载 Locales/*.lua（那是主插件的模块），运行期走全局 EVAL_L —— 键仍取自同一份三语包，
  //     所以「必须三语齐全」这条对它同样成立，必须进闸门。
  for (const f of ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua", "addons/EH_DebugBox/EH_DebugBox.lua", 'quest/QuestData.lua', 'quest/QuestBulk.lua', 'quest/QuestChains.lua' ]) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const src = fs.readFileSync(p, "utf8");
    for (const line of src.split(/\r?\n/)) {
      const code = line.replace(/--.*$/, ""); // 注释里出现的 L("KEY") 不算（Core.lua 的说明注释里有）
      let m; const re = /L\(\s*"([A-Za-z0-9_]+)"(\s*\.\.)?/g;
      while ((m = re.exec(code))) if (!m[2]) used.add(m[1]); // m[2] 有值 = 拼接前缀，不是整键
    }
  }
  const missing = [];
  for (const k of used) for (const lg of langs) if (!packs[lg].has(k)) missing.push(k + "@" + lg);
  if (missing.length) {
    console.log("LANG KEY CHECK: FAIL - " + missing.length + " key(s) missing; L() would show the bare key:");
    for (const k of missing.slice(0, 20)) console.log("    " + k);
    process.exitCode = 1;
    return;
  }
  console.log("LANG KEY CHECK: " + used.size + " keys present in all 3 languages");
})();

// ===== LANG SOURCE CHECK: 取语言必须用读取器 EVAL_GET_LANG()，不能用写入器 EVAL_RESOLVE_LANG() =====
// ★1.70.46 发现真 bug：DataSearch.lua / Toolbox.lua 都写成
//   `(type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"`，
//   而 Core.lua 的 ehResolveLang() **没有任何返回值**——它只把语言写进 local EH_LANG
//   （每个分支都是裸 return，末尾以 EH_LANG = "zhCN" 收尾）。
//   于是 `nil or "zhCN"` 兜底 → 工具箱/数据检索在英俄客户端**恒显示中文**，
//   且 dsLang() 永远去取 `*_zhCN` 子表（物品/怪物/任务名全中文），全程不报错。
// ★写入器与读取器混用 = 典型静默失败：调用点拿到 nil，被 `or 默认值` 吞掉。
//   放在能读文件的一侧：这两个文件里除注释外不允许再出现 EVAL_RESOLVE_LANG。
(function () {
  const bad = [];
  // ★★★1.73.42j 扫描面从「两个已知文件」扩成**所有自建 local L(k) 的模块**：
  //   本轮发现 Share.lua 也犯了同一个错（分享模块在英俄客户端恒显示中文）——写死文件名就是盲区，
  //   改成按「谁定义了 L() 就查谁」，新增模块漏改也拦得住。
  // ★1.74.5 扫描面含 tools/ 子目录（新增模块放子目录里时，这个「按谁定义 L() 就查谁」的自动发现不能瞎）
  const _lFiles = fs.readdirSync(__dirname).filter(function (f) { return /\.lua$/.test(f); })
    .concat((fs.existsSync(path.join(__dirname, 'tools')) ? fs.readdirSync(path.join(__dirname, 'tools')) : [])
      .filter(function (f) { return /\.lua$/.test(f); }).map(function (f) { return 'tools/' + f; }));
  const _targets = ["DataSearch.lua", "Toolbox.lua"];
  _lFiles.forEach(function (f) {
    const src = fs.readFileSync(path.join(__dirname, f), "utf8");
    if (/local\s+function\s+L\s*\(/.test(src) && _targets.indexOf(f) < 0) _targets.push(f);
  });
  for (const f of _targets) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const code = lines[i].replace(/--.*$/, "");
      if (code.indexOf("EVAL_RESOLVE_LANG") >= 0) bad.push(f + ":" + (i + 1));
    }
  }
  if (bad.length) {
    console.log("LANG SOURCE CHECK: FAIL - EVAL_RESOLVE_LANG is a WRITER (no return value); use EVAL_GET_LANG(): " + bad.join(", "));
    process.exitCode = 1;
    return;
  }
  console.log("LANG SOURCE CHECK: " + _targets.join("/") + " read the language via EVAL_GET_LANG() only");
})();

// ===== WINDOW SIZE CHECK: 每个自建窗都必须**真的**设置宽与高 =====
// ★1.70.46 实测事故（用户截图）：技能编辑窗变成一块几乎全黑的大窗并盖住配置窗。
//   根因：`seUI.W = W -- 1.70.45 注释...` 与同一行的 `root:SetHeight(H)` 挤在一起后，
//   SetHeight 落在 `--` 之后 → **被行尾注释吞掉** → 窗口从未设置高度 → 客户端给了接近整屏的默认高度。
//   ★宽度完全正常、只有高度异常；语法合法、luacheck 通过、测试全绿（当时只有宽度断言）。
//   两处 SetWidth/SetHeight 判断都**先剥掉行尾注释**，再找活语句。
(function () {
  const src = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const lines = src.split(/\r?\n/);
  const live = s => s.replace(/--.*$/, "");
  const bad = [];
  for (const fn of ["local function cfgBuild()", "local function SE_BUILD()"]) {
    const i = lines.findIndex(l => l.trim() === fn);
    if (i < 0) { bad.push(fn + ": not found"); continue; }
    let w = false, h = false;
    for (let j = i; j < Math.min(i + 25, lines.length); j++) {
      if (/:SetWidth\s*\(/.test(live(lines[j]))) w = true;
      if (/:SetHeight\s*\(/.test(live(lines[j]))) h = true;
    }
    if (!w) bad.push(fn + ": no LIVE :SetWidth(");
    if (!h) bad.push(fn + ": no LIVE :SetHeight( -- swallowed by a line comment?");
  }
  if (bad.length) {
    console.log("WINDOW SIZE CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("WINDOW SIZE CHECK: both windows set width and height");
})();

// ===== COMMENT SWALLOW CHECK: 语句不能被同一行的行尾注释吞掉 =====
// ★通用防线。触发条件：一行里 `--` **前面是非空代码**（即「代码 + 行尾注释」），
//   而注释文本里还跟着一个**方法调用**（形如 `xxx:Method(` 或 `xxx.Method(`）。
//   这几乎只可能是「本该独立成句的代码被注释掉」。
//   ★只扫 .lua（JS 里的 `--` 是自减运算符，扫 JS 会误报——第一版就误报了 test_engine.js）。
//   ★注释里提到 `SomeCall()` 属于正常（本仓库有大量 API 说明注释），故必须要求「方法调用」
//   （带 `:` / `.`）而不是裸调用，否则误报成片（实测：裸调用规则会命中 test_assert.lua:240）。
(function () {
  const files = ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/DragFrames.lua", "tools/LayerFix.lua",
    'quest/QuestData.lua', 'quest/QuestBulk.lua', 'quest/QuestChains.lua',
                 "Locales/zhCN.lua", "Locales/enUS.lua", "Locales/ruRU.lua", "test_assert.lua", "test_stub.lua"];
  const bad = [];
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const ci = lines[i].indexOf("--");
      if (ci <= 0) continue;
      if (lines[i].slice(0, ci).trim() === "") continue;
      const tail = lines[i].slice(ci + 2);
      if (/[A-Za-z_][A-Za-z0-9_]*\s*[:.]\s*[A-Za-z_][A-Za-z0-9_]*\s*\(/.test(tail)) bad.push(f + ":" + (i + 1));
    }
  }
  if (bad.length) {
    console.log("COMMENT SWALLOW CHECK: FAIL - code looks commented out by a trailing -- at: " + bad.join(", "));
    process.exitCode = 1;
    return;
  }
  console.log("COMMENT SWALLOW CHECK: no statement lost to a trailing comment");
})();

// ===== IO BTN LABEL WIDTH CHECK（1.71.2）：IO 窗底部按钮的文字必须显式限宽 =====
// ★背景：用户截图里按钮被排成两排、还被提示文字压住。修完后有一类**回归无法被行为断言抓住**——
//   「标签 FontString 忘了 SetWidth」：不限宽时宽度由内容决定，换语言（英文/俄文更长）就会
//   溢出压到相邻按钮，而 Lua 侧一切正常（不报错、位置也对）。
// 判据：ioBtn 里必须同时出现 SetWidth 与 SetNonSpaceWrap（限宽 + 禁止折行）。
(function () {
  const p = path.join(__dirname, 'EvalHelp.lua');
  if (!fs.existsSync(p)) { console.log('IO BTN LABEL CHECK: file missing'); process.exit(1); }
  const src = fs.readFileSync(p, 'utf8');
  const i = src.indexOf('local function ioBtn(');
  if (i < 0) { console.log('IO BTN LABEL CHECK: FAIL - ioBtn not found'); process.exit(1); }
  const body = src.slice(i, src.indexOf(String.fromCharCode(10) + '  end', i));
  // ★必须剥掉注释再匹配：直接扫原文会被**注释里提到的 SetWidth** 骗过
  //   （本轮实测：把调用注释掉、注释里仍留着方法名的变异体**存活**）。
  //   判据：源码检查也要「看代码，不看注释」——与 COMMENT SWALLOW CHECK 同一类纪律。
  const code = body.split(/\r?\n/).map(l => {
    const ci = l.indexOf('--');
    return ci >= 0 ? l.slice(0, ci) : l;
  }).join('\n');
  // ★必须精确到**标签**那个变量（bt），不能只匹配方法名：
  //   按钮本体也有 b:SetWidth(w)，只写 /SetWidth/ 时「标签限宽被删掉」的变异体照样通过
  //   （本轮实测存活）。判据：源码检查要盯**目标对象**，不是「文件里出现过这个方法」。
  const okW = /SetWidth\s*,\s*bt\b|\bbt:SetWidth\b/.test(code);
  const okN = /SetNonSpaceWrap\s*,\s*bt\b|\bbt:SetNonSpaceWrap\b/.test(code);
  if (!okW || !okN) {
    console.log('IO BTN LABEL CHECK: FAIL - label must be width-limited and non-wrapping (SetWidth=' + okW + ' SetNonSpaceWrap=' + okN + ')');
    process.exit(1);
  }
  console.log('IO BTN LABEL CHECK: button labels are width-limited and non-wrapping');
})();

// ===== AURA SEARCH CHECK（1.71.2 第八轮）：光环下拉必须**启用面板内搜索框** =====
// ★背景：用户要求「这个功能还原，到输入框格保持在下拉内，
//   并且支持打字过滤和自定义输入」。
//   实现 = 光环下拉传 opts.search = true（面板内搜索框）+ onFreeText（自定义输入）。
// ★为什么需要源码级检查：行为断言直接调 EVAL_DD_TEST_OPEN_SEARCH，
//   **绕过了光环菜单那个真实调用点** —— 把 search = true 改成 nil 时行为断言照样全绿
//   （同 1.71.2 第二轮的教训：组件能力 ≠ 调用点接线，两件事必须各测一条）。
(function () {
  const p = path.join(__dirname, 'EvalHelp.lua');
  if (!fs.existsSync(p)) { console.log('AURA SEARCH CHECK: file missing'); process.exit(1); }
  const src = fs.readFileSync(p, 'utf8');
  const lines = src.split(/\r?\n/);
  // ★★必须**锚定到光环那个真实调用点**，不能全文件找 "search = true"：
  //   实测该串在文件里另有 2 处（一个测试钩子 2785、一句注释 3581）——
  //   全文件搜索时把调用点改掉**照样通过**（假绿）。
  //   ★判据同 IO BTN LABEL CHECK：**源码检查要盯「目标位置上的那次调用」**，
  //     不是「文件里出现过这个字符串」。
  const anchor = lines.findIndex(l => l.includes('SE_AURA_MENU(it.cd.k)'));
  if (anchor < 0) {
    console.log('AURA SEARCH CHECK: FAIL - cannot locate the aura menu call site (SE_AURA_MENU)');
    process.exit(1);
  }
  // 调用点之后 30 行内必须出现 search = true（即 opts 表里真的开了搜索框）
  let found = false, staleKw = false;
  for (let i = anchor; i < Math.min(anchor + 30, lines.length); i++) {
    if (lines[i].includes('search = true')) found = true;
    if (lines[i].includes('kw = it.cd._kw')) staleKw = true;
  }
  if (!found) {
    console.log('AURA SEARCH CHECK: FAIL - the aura dropdown call site does not enable the in-panel search box');
    process.exit(1);
  }
  if (staleKw) {
    console.log('AURA SEARCH CHECK: FAIL - stale host-keyword wiring still present (kw = it.cd._kw)');
    process.exit(1);
  }
  console.log('AURA SEARCH CHECK: the aura dropdown enables the in-panel search box');
})();

  if (!rootMatch) { console.log('ICON CHECK: no DS_ANN_ICON_ROOT found'); process.exit(1); }
  const rootWin = rootMatch[1];
  // Texture paths are game-relative and start with Interface\AddOns\<addon>\...
  // We are inside .../Interface/AddOns/EvalHelp, so strip that prefix and use the rest
  // relative to our PARENT (the AddOns directory).
  const parts = rootWin.split('\\').filter(Boolean); // ["Interface","AddOns","unrealQuest","media","icons"]
  const afterAddons = parts.slice(2).join('/');       // "unrealQuest/media/icons"
  const dir = path.join('..', afterAddons);
  if (!fs.existsSync(dir)) { console.log('ICON CHECK: skipped (no UnrealQuest assets at ' + dir + ')'); return null; }

  const names = [];
  const re = /icon = "([^"]+)"/g;
  let m;
  while ((m = re.exec(ds)) !== null) names.push(m[1]);
  let missing = [];
  for (const n of names) {
    if (!fs.existsSync(path.join(dir, n + '.tga'))) missing.push(n);
  }
  console.log('ICON CHECK: ' + names.length + ' category icons, ' + missing.length + ' missing');
  if (missing.length) {
    console.log('  MISSING: ' + missing.join(', '));
    console.log('  (this client draws NOTHING for a wrong path -- fix before shipping)');
    process.exit(1);
  }
  return names.length;
}

// ===== CHAN RETRY WIRING CHECK（1.71.3）：频道屏蔽的「挂载失败重试」必须在多处接线 =====
// 背景：用户实测「屏蔽频道进出信息未能正确工作」的根因就是**只挂一次、失败后没人重试**
//   （Toolbox.lua 载入时 DEFAULT_CHAT_FRAME 往往还没建好）——这是**静默失效**：
//   行为断言只在测试里跑，照不到「生产里到底有没有接线」。
// 判据：Toolbox.lua 里 tbChanRetry() 至少 3 处（定义 + 每帧兜底 + 事件驱动），
//   并且诊断命令里有手动重试入口（/eh go 频道 装）。
(function () {
  const tb = fs.readFileSync(path.join(__dirname, 'Toolbox.lua'), 'utf8');
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const sites = (tb.match(/tbChanRetry\(\)/g) || []).length;
  const bad = [];
  if (sites < 3) bad.push('tbChanRetry() 只有 ' + sites + " 处（要 ≥3：定义 + 每帧 + 事件）");
  if (!/EVAL_TB_CHAN_RETRY = tbChanRetry/.test(tb)) bad.push("没有导出 EVAL_TB_CHAN_RETRY");
  if (!/EVAL_TB_CHAN_INSTALL\(\) and true or false/.test(eh)) bad.push("诊断命令里没有手动重试入口（/eh go 频道 装）");
  if (bad.length) {
    console.log('CHAN RETRY WIRING CHECK: FAIL - ' + bad.join('; '));
    process.exit(1);
  }
  console.log('CHAN RETRY WIRING CHECK: retry wired at ' + sites + ' sites + manual command');
})();

// ===== PAINT WIRING CHECK（1.73.10）：职业着色的「接线 + 不用本客户端没有的 API」 =====
// 背景：着色是**静默失败**大户——窗口不存在/控件改名/漏接线时，游戏里就是「没颜色」，不报错、不崩。
//   行为断言只在测试里跑，照不到「生产里到底有没有接线」以及「有没有用了不可用的 API」。
// 判据：
//   ① tbPaintRetry() 至少 2 处（定义 + 每帧兜底/事件驱动之一）——与频道屏蔽同一条纪律；
//   ② 三个窗口刷新函数名都在描述表里（GuildStatus_Update / WhoList_Update / FriendsList_Update）；
//   ③ ★原函数备份**必须是 local**：不许出现 XGuild 那种 oldGuildStatus_Update = … 的全局赋值；
//   ④ ★禁用本客户端**没有**的 hooksecurefunc（本机 api_*.html 全表 0 命中）；
//   ⑤ 有手动诊断入口 /eh go 着色。
(function () {
  const tb = fs.readFileSync(path.join(__dirname, 'Toolbox.lua'), 'utf8');
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const bad = [];
  const sites = (tb.match(/tbPaintRetry\(\)/g) || []).length;
  if (sites < 2) bad.push('tbPaintRetry() 只有 ' + sites + ' 处（要 >=2：定义 + 每帧/事件之一）');
  if (!/EVAL_TB_PAINT_RETRY = tbPaintRetry/.test(tb)) bad.push('没有导出 EVAL_TB_PAINT_RETRY');
  for (const fn of ['GuildStatus_Update', 'WhoList_Update', 'FriendsList_Update']) {
    if (tb.indexOf('"' + fn + '"') < 0) bad.push('描述表里没有 ' + fn);
  }
  // ③ 备份不许是全局（XGuild 的毛病：oldGuildStatus_Update 之类挂到 _G 上）
  const globalBackup = tb.match(/^\s*old[A-Za-z_]+\s*=/gm) || [];
  if (globalBackup.length) bad.push('发现全局备份赋值：' + globalBackup.join(' / '));
  if (!/local tbPaintBackup/.test(tb)) bad.push('没有 local tbPaintBackup（原函数备份必须存 local）');
  // ④ 禁用的 API
  for (const f of ['hooksecurefunc']) {
    if (tb.indexOf(f) >= 0 || eh.indexOf(f) >= 0) bad.push('用了本客户端不存在的 ' + f);
  }
  // ⑤ 诊断入口
  if (!/go 着色/.test(eh)) bad.push('没有手动诊断入口（/eh go 着色）');
  if (bad.length) { console.log('PAINT WIRING CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('PAINT WIRING CHECK: 三窗口接线 + local 备份 + 无不可用 API + 诊断入口（retry ' + sites + ' 处）');
})();

// ===== UI CELL MOUSE CHECK（1.74.2）：战斗信息UI 技能格「左键切启用/停用 · 右键开配置弹窗」的接线 =====
// 背景：按键分派写在构建闭包里 —— 忘注册右键 / 分派写反 / 左键没写 r.enabled，游戏里都不报错，
//   只是「右键没反应」或「左键没切换」（本项目「行为断言照不到 UI 接线 → 源码检查补位」的纪律）。
// 判据：
//   ① 技能带格子注册了 RightButtonUp（光注册左键 = 右键永远到不了分派代码）；
//   ② 右键分派 → EVAL_HELP_SE_OPEN(prof, ci)；
//   ③ 左键路径真的写 r.enabled（快速切换启用/停用，写的是配置真值）；
//   ④ 切换后双刷新：EVAL_WAR_TAB_REFRESH()（配置窗列表同一份真值）+ EVAL_HELP_UI_TICK()（战斗UI 即时重画）。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const bad = [];
  // ① 注册右键（锚：技能带那行 RegisterForClicks）
  if (!/pcall\(cb\.RegisterForClicks, cb, "LeftButtonUp", "RightButtonUp"\)/.test(eh)) {
    bad.push('技能带格子没注册 RightButtonUp（右键到不了分派代码）');
  }
  // ② 右键 → 编辑窗
  if (!/mbtn == "RightButton" then\s*EVAL_HELP_SE_OPEN\(prof, ci\)/.test(eh)) {
    bad.push('右键分派没有开 EVAL_HELP_SE_OPEN(prof, ci)');
  }
  // ③ 左键写配置真值
  if (!/local on = r\.enabled ~= false\s*r\.enabled = not on/.test(eh)) {
    bad.push('左键路径没有写 r.enabled（快速切换启用/停用）');
  }
  // ④ 切换后的双刷新（必须出现在写值之后的那段里）
  const seg = (eh.split('r.enabled = not on')[1] || '').slice(0, 400);
  if (seg.indexOf('EVAL_WAR_TAB_REFRESH()') < 0) bad.push('切换后没有 EVAL_WAR_TAB_REFRESH()（配置窗列表不会同步真值）');
  if (seg.indexOf('EVAL_HELP_UI_TICK()') < 0) bad.push('切换后没有 EVAL_HELP_UI_TICK()（战斗UI 要等下个心跳才重画）');
  if (bad.length) { console.log('UI CELL MOUSE CHECK: FAIL - ' + bad.join(' | ')); process.exit(1); }
  console.log('UI CELL MOUSE CHECK: 技能格已注册右键 · 右键→编辑窗 · 左键→写 r.enabled 真值 · 切换后双刷新');
})();

// ===== SHARE RECV EVENTS CHECK（1.74.3）：分享接收帧的**事件注册全套** =====
// 背景（用户报「队伍频道接收完方案不弹窗」）：
//   1.12 里**队长/团长**发的队伍/团队消息走独立事件 CHAT_MSG_PARTY_LEADER / CHAT_MSG_RAID_LEADER，
//   而接收帧原来只注册 CHAT_MSG_PARTY / CHAT_MSG_RAID ⇒ 发送者是队长时分片**一片都进不来**：
//   接收端静默、发送端照样报「已发送 N 片」。**接线漏接不报错** → 只能靠源码检查守。
// 判据：
//   ① 接收帧把七个频道事件都注册上（GUILD / PARTY / PARTY_**LEADER** / RAID / RAID_**LEADER** / SAY / WHISPER）；
//   ② 单一来源表 SH_EV_ALL 含这七个（诊断命令与检查共用一份口径，加频道只改一处）；
//   ③ `/eh go 分享事件` 命令真的接上并调用 EVAL_SHARE_RECV_PROBE（命令没接线 = 敲了静默无反应）；
//   ④ OnEvent 记下「最近真收到的事件名」（探针第③项的证据来源，否则真机发哪个事件无从定案）。
(function () {
  const sh = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const bad = [];
  const want = ['CHAT_MSG_GUILD', 'CHAT_MSG_PARTY', 'CHAT_MSG_PARTY_LEADER',
                'CHAT_MSG_RAID', 'CHAT_MSG_RAID_LEADER', 'CHAT_MSG_SAY', 'CHAT_MSG_WHISPER'];
  const block = (sh.split('local shf = CreateFrame("Frame", "EVAL_SHARE_EVENTS", UIParent)')[1] || '');
  const reg = (block.split('shf:SetScript("OnEvent"')[0] || '');
  // ★★★必须是「在 RegisterEvent 那一行」出现，不能只查整段里有没有这个字符串 ——
  //   本段里就有单一来源表 SH_EV_ALL，它含全部事件名：只查字符串的话，**删掉注册行照样绿**
  //   （M571 实测：删掉队长版注册，弱判据 SURVIVED）。这就是本项目「含 X 会被同段示例顶住」那一族。
  const regLines = reg.split(/\r?\n/).filter(l => l.indexOf('RegisterEvent') >= 0);
  for (const e of want) {
    if (!regLines.some(l => l.indexOf('"' + e + '"') >= 0)) bad.push('接收帧没注册 ' + e + '（RegisterEvent 行里找不到）');
  }
  // ② 单一来源表（供诊断命令列出）
  const tbl = (sh.match(/local SH_EV_ALL = \{[\s\S]{0,400}?\}/) || [''])[0];
  for (const e of want) {
    if (tbl.indexOf('"' + e + '"') < 0) bad.push('SH_EV_ALL 里缺 ' + e);
  }
  // ③ 命令接线
  if (!/go 分享事件/.test(eh)) bad.push('没有 /eh go 分享事件 命令');
  if (!/EVAL_SHARE_RECV_PROBE\(\)/.test(eh)) bad.push('命令没调用 EVAL_SHARE_RECV_PROBE');
  // ④ 最近收到的事件名有记账（探针要能如实报「真机发的是哪个事件」）
  if (sh.indexOf('SH_EV_SEEN = ev') < 0) bad.push('OnEvent 没记 SH_EV_SEEN（探针第③项没有证据）');
  if (bad.length) { console.log('SHARE RECV EVENTS CHECK: FAIL - ' + bad.join(' | ')); process.exit(1); }
  console.log('SHARE RECV EVENTS CHECK: 七频道事件全注册（含队长版）· SH_EV_ALL 单一来源 · /eh go 分享事件 已接线 · 记最近事件名');
})();

// ===== CHAT COLOR WIRING CHECK（1.73.12）：聊天窗名字着色的「接线 + 频率防护」 =====
// 背景：名字着色与职业着色一样是**静默失败**大户 —— 没接上/格式不认，游戏里就是「没颜色」，不报错不崩。
//   纯函数写得再好，只要没接在聊天打印入口上，行为断言照样全绿（本项目「源码检查补位 UI 接线」的纪律）。
// 判据：
//   ① 名字着色**必须在 AddMessage 包装体内部**被调用（与频道屏蔽共用一个包装体）；
//   ② 缓存「白拿」那一笔必须在 EVAL_TB_PAINT_ROW 里（上色时顺手写，零额外调用）；
//   ③ ★频率防护：Toolbox.lua **不许**向服务器发查询（SendWho / GuildRoster() / ShowFriends()）——
//      「查不到的名字就不上色」是刻意的取舍，不许被后人悄悄改成自动 /who；
//   ④ 采集必须走**限频**入口，且被事件分派 EVAL_TB_ONEVENT 接线；
//   ⑤ 有诊断入口 /eh go 聊天（格式校准 + 挂载状态）。
(function () {
  const rawTb = fs.readFileSync(path.join(__dirname, 'Toolbox.lua'), 'utf8');
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  // ★★★「看代码，不看注释」：本文件里到处写着「不做自动 /who（SendWho）」这类**说明性**注释，
  //   直接扫全文会把说明当成违规 → 先把行尾注释摘掉再判（与 COMMENT SWALLOW/IO BTN LABEL 同一条纪律）。
  const tb = rawTb.split(/\r?\n/).map(function (l) {
    const i = l.indexOf('--');
    return i >= 0 ? l.slice(0, i) : l;
  }).join('\n');
  const bad = [];
  // ① 包装体内调用
  const iWrapper = tb.indexOf('local function wrapper(self, msg, ...)');
  const iWrapped = tb.indexOf('TB.chanWrappers[key] = wrapper');
  const iColorCall = tb.indexOf('EVAL_TB_CHAT_COLOR_LINE, msg');
  if (iWrapper < 0 || iWrapped < 0 || iColorCall < 0)
    bad.push('找不到包装体或名字着色调用点（wrapper=' + iWrapper + ' end=' + iWrapped + ' call=' + iColorCall + '）');
  else if (!(iColorCall > iWrapper && iColorCall < iWrapped))
    bad.push('EVAL_TB_CHAT_COLOR_LINE 不在聊天打印包装体内部（没接上入口 = 纯函数白写）');
  // ② 白拿
  const iRow = tb.indexOf('function EVAL_TB_PAINT_ROW');
  const iNextFn = tb.indexOf('\nfunction ', iRow + 10);
  const rowBody = (iRow >= 0) ? tb.slice(iRow, iNextFn > 0 ? iNextFn : iRow + 2000) : '';
  if (!/tbNameClassPut\(d\.name/.test(rowBody))
    bad.push('EVAL_TB_PAINT_ROW 里没有「白拿」写缓存（tbNameClassPut(d.name, ...)）');
  // ③ ★频率防护（1.73.12 用户追加要求「未缓存角色默认开启主动查询」后的新判据）：
  //   SendWho 是**服务器查询**，可以存在，但**只允许出现在限频滴出 tbWhoTick 里**——
  //   聊天热路径（AddMessage 包装体）里直接发 = 一句话一发 = 必被服务器反滥用（本项目 1.68.2 被踢线的同族教训）。
  //   并且 tbWhoTick 里四道闸门必须都在：频率下限 / 单飞 / 负缓存 / 队列上限。
  //   ★★★1.73.52 更新（用户真机取证后开放）：**GuildRoster() 也允许，但只许出现在 `tbNameClassEnsureRoster` 里**，
  //     且那个函数必须四道闸门齐全：① 受「主动查询」开关把关（EVAL_TB_WHO_ON）② 在公会里（IsInGuild）
  //     ③ 本地名册确实为空（GetNumGuildMembers 判 >0 就退出）④ 本会话只发一次（TB.rosterAsked）。
  //     为什么开放：真机探针显示「公会名册本地条数=0（懒加载）」→ 不开公会窗时公会聊天里的人名**任何来源都没有**，
  //     而那正是玩家最常看到的聊天；一次登录一发的查询开销 ≪ 已有的按名字 /who。
  //   ShowFriends() 仍然**一律禁止**（不是用户要的，纯粹白打扰服务器）。
  const forbidden = tb.match(/\bShowFriends\s*\(/g) || [];
  if (forbidden.length) bad.push('出现了未被允许的服务器查询：' + forbidden.join(', '));
  const iRosterFn = tb.indexOf('local function tbNameClassEnsureRoster()');
  const iRosterFnEnd = (iRosterFn >= 0) ? tb.indexOf('\nfunction ', iRosterFn + 10) : -1;
  if (iRosterFn < 0) bad.push('找不到 tbNameClassEnsureRoster（名册查询的唯一入口）');
  else {
    const rb = tb.slice(iRosterFn, iRosterFnEnd > 0 ? iRosterFnEnd : iRosterFn + 2000);
    if (rb.indexOf('GuildRoster') < 0) bad.push('tbNameClassEnsureRoster 里没有 GuildRoster()（那这个函数就没意义了）');
    const gates = [["主动查询开关", "EVAL_TB_WHO_ON"], ["在公会里", "IsInGuild"],
                   ["本地名册为空", "GetNumGuildMembers"], ["本会话只发一次", "TB.rosterAsked"]];
    for (const [label, tok] of gates) if (rb.indexOf(tok) < 0) bad.push('名册查询缺少「' + label + '」这道闸门（' + tok + '）');
  }
  // GuildRoster( 只许出现在那一个函数体内（别处一律禁止）
  for (let p2 = 0; (p2 = tb.indexOf('GuildRoster(', p2)) >= 0; p2++) {
    if (!(iRosterFn >= 0 && p2 > iRosterFn && (iRosterFnEnd < 0 || p2 < iRosterFnEnd)))
      bad.push('GuildRoster() 出现在 tbNameClassEnsureRoster 之外');
  }
  const iTick = tb.indexOf('local function tbWhoTick()');
  const iTickEnd = tb.indexOf('EVAL_TB_WHO_TICK = tbWhoTick');
  const iSend = tb.indexOf('SendWho');
  if (iSend < 0) bad.push('没有 SendWho（用户要求「未缓存角色默认开启主动查询」）');
  else if (!(iTick > 0 && iTickEnd > iTick && iSend > iTick && iSend < iTickEnd))
    bad.push('SendWho 出现在限频滴出 tbWhoTick 之外（热路径直接发查询 = 会被服务器反滥用）');
  if (iTick > 0 && iTickEnd > iTick) {
    const tickBody = tb.slice(iTick, iTickEnd);
    // 「发不发」的两道闸门必须在**发送处**：频率下限 + 单飞
    if (tickBody.indexOf('TB_WHO_GAP') < 0) bad.push('tbWhoTick 里没有频率下限 TB_WHO_GAP');
    if (tickBody.indexOf('TB.whoPending') < 0) bad.push('tbWhoTick 里没有单飞判据 TB.whoPending');
  }
  // 「该不该入队」的两道闸门必须在**入队口**（唯一入队口）：负缓存 + 队列上限
  const iEnq = tb.indexOf('function EVAL_TB_WHO_ENQUEUE');
  const iEnqEnd = iTick; // 入队口的下一个代码块就是滴出函数（★注释已被摘掉，不能拿注释当锚点）
  if (!(iEnq > 0 && iEnqEnd > iEnq)) bad.push('找不到唯一的入队口 EVAL_TB_WHO_ENQUEUE');
  else {
    const enqBody = tb.slice(iEnq, iEnqEnd);
    if (enqBody.indexOf('EVAL_TB_WHO_ISMISS') < 0) bad.push('入队口没有负缓存判据（查不到的名字会被反复查）');
    if (enqBody.indexOf('TB_WHO_QMAX') < 0) bad.push('入队口没有队列上限判据');
  }
  const inserts = (tb.match(/table\.insert\(tbWhoQ,/g) || []).length;
  if (inserts !== 1) bad.push('入队口不唯一（table.insert(tbWhoQ, ...) 出现 ' + inserts + ' 次；入队只允许一条路）');
  // ④ 限频入口 + 事件接线
  const throttleSites = (tb.match(/tbNcHarvest\(/g) || []).length;
  if (throttleSites < 5) bad.push('tbNcHarvest 只有 ' + throttleSites + ' 处（要 >=5：定义 + 导出 + 至少 4 个事件分派）');
  if (!/EVAL_TB_NAMECLASS_HARVEST_THROTTLED = tbNcHarvest/.test(tb)) bad.push('没有导出 EVAL_TB_NAMECLASS_HARVEST_THROTTLED');
  // ⑤ 诊断入口
  if (!/go 聊天/.test(eh)) bad.push('没有诊断入口（/eh go 聊天）');
  if (eh.indexOf('string.find(sarg, "^试")') < 0) bad.push('诊断里没有「试」自检分支（/eh go 聊天 试 <文本>）');
  // ⑥ ★★★1.73.12 第二入口的**读回确认**：真机实测 frame.AddMessage「写成功但不生效」——
  //   凡挂入口都必须写完**读回来确认**（这是那类「静默失效」的唯一自动化防线），并且要有幂等守卫。
  if (tb.indexOf('_G.ChatFrame_OnEvent = wrapper') < 0) bad.push('没有挂第二入口 ChatFrame_OnEvent');
  if (tb.indexOf('if _G.ChatFrame_OnEvent ~= wrapper then return false end') < 0)
    bad.push('挂 ChatFrame_OnEvent 后**没有读回确认**（真机吃过「写成功但不生效」的亏）');
  if (tb.indexOf('if cur == TB.ceWrapper then return true end') < 0)
    bad.push('第二入口没有幂等守卫（会重复包装、同一条消息被处理两次）');
  // ⑦ ChatMOD 的做法（参考插件实证）：在事件里对 this 帧懒挂载，且**读回确认**（写不进就记 thisStuck）
  if (tb.indexOf('function EVAL_TB_THIS_HOOK(f)') < 0) bad.push('没有 this 帧懒挂载（ChatMOD 的做法）');
  if (tb.indexOf('back == wrapper') < 0) bad.push('this 帧懒挂载没有读回确认');
  if (tb.indexOf('TB.thisStuck') < 0) bad.push('this 帧懒挂载不记账「写不进去」（真机就分不出成败）');
  // ⑧ 官方「消息组」屏蔽（与走不走 Lua 无关的那条路）：必须有应用 + 撤销 + 探测
  for (const fn of ['EVAL_TB_CHAN_OFFICIAL_APPLY', 'EVAL_TB_CHAN_OFFICIAL_SYNC', 'EVAL_TB_CHAN_GROUPS']) {
    if (tb.indexOf('function ' + fn) < 0) bad.push('缺少官方消息组接口：' + fn);
  }
  if (tb.indexOf('RemoveChatWindowMessages') < 0 || tb.indexOf('AddChatWindowMessages') < 0)
    bad.push('官方消息组屏蔽缺少 摘掉/加回 两侧（撤不回去就是残状态）');
  if (eh.indexOf('官方消息组') < 0) bad.push('诊断里没有官方消息组的状态（看不出这条路生没生效）');
  if (bad.length) { console.log('CHAT COLOR WIRING CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('CHAT COLOR WIRING CHECK: 挂在聊天入口内 + 白拿缓存 + SendWho 只在限频滴出（四道闸门齐）+ 限频采集 + 诊断入口');
})();

// ===== DEBUFF DISPLAY CHECK（1.73.12）：类型集合「界面本地化、导出 token」两条腿不能走丢 =====
// 背景：用户报「debuff 格式化是否没做好」——编辑窗底部预览吐的是**导出用的英文 token**（Magic/Curse），
//   而格子里是「魔法/诅咒/毒」。正解 = 同一份格式化 + 一个 disp 开关；两类检查互补：
//   · 行为断言（组 114/125）盯「导出逐字不变」与「显示本地化 + 能解析回」；
//   · 源码检查盯**接线**（显示路径必须真的传 disp=true —— 漏传不报错、只是界面又变回 token）。
(function () {
  const en = fs.readFileSync(path.join(__dirname, 'Engine.lua'), 'utf8');
  const eh = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const bad = [];
  if (en.indexOf('local function dispelLabel(dt, disp)') < 0) bad.push('Engine 没有 dispelLabel（显示用本地化标签）');
  if (en.indexOf('dispelLabel(cd.dt, disp)') < 0) bad.push('teamDebuff 的导出/显示没有共用 dispelLabel（会复制出第二份格式化逻辑）');
  if (en.indexOf('function EVAL_COND_STR(cd, disp)') < 0) bad.push('EVAL_COND_STR 没有 disp 开关');
  if (en.indexOf('function EVAL_GROUP_STR(groups, disp)') < 0) bad.push('EVAL_GROUP_STR 没有把 disp 传下去');
  if (eh.indexOf('EVAL_GROUP_STR(seLinearToGroups(ed.conds), true)') < 0) bad.push('编辑窗底部预览没有走本地化显示（漏传 true 就会又变回 token）');
  if (eh.indexOf('EVAL_GROUP_STR(r.groups, true)') < 0) bad.push('配置窗方案行的条件文本没有走本地化显示');
  if (eh.indexOf('EVAL_COND_STR(cd, true)') < 0) bad.push('行内预览没有走本地化显示');
  if (eh.indexOf('function EVAL_TEST_SE_PREVIEW()') < 0) bad.push('没有预览读值口（断言读不到真实 FontString）');
  if (bad.length) { console.log('DEBUFF DISPLAY CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('DEBUFF DISPLAY CHECK: 显示走本地化名（预览/方案行/行内）+ 导出仍走 token + 只此一份格式化');
})();

// ===== WTT ISOLATION CHECK（1.73.14）：读数用的隐形 tooltip 绝不能是真实 GameTooltip =====
// 背景（用户报「开启战斗UI 后物品 tooltip 显示几秒就自动隐藏」）：Engine 原来是 `local WTT = GameTooltip`，
//   而每次读光环/技能都要 SetOwner → ClearLines → 填内容 → Hide → **玩家正看的 tooltip 被清空并关掉**；
//   战斗UI/状态UI 的定时刷新（条件求值要读光环）会周期性触发 → 几秒一次。
// 判据（行为断言照不到「借用了哪个对象」，只能靠源码检查补位）：
//   ① 不许再出现 `local WTT = GameTooltip`；② 必须自建隐形 tooltip；③ 必须读**自家**那个 TextLeft1；
//   ④ 退化路径必须有「真实 tooltip 正显示就不读」的纯函数守卫；⑤ 要有读值口与诊断入口。
(function () {
  // ★★扫描前**先摘行尾注释**（本检查的说明里就写着那句反面教材 `local WTT = GameTooltip`；
  //   不摘注释 = 说明文字被当成违规 → 假 FAIL。本项目 CHAT COLOR WIRING CHECK 踩过同一个坑）
  const strip = (s) => s.split(/\r?\n/).map(function (l) {
    const i = l.indexOf('--');
    return i >= 0 ? l.slice(0, i) : l;
  }).join('\n');
  const en = strip(fs.readFileSync(path.join(__dirname, 'Engine.lua'), 'utf8'));
  const eh = strip(fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8'));
  const bad = [];
  if (/local WTT = GameTooltip/.test(en)) bad.push('WTT 又借用了真实 GameTooltip（读数会清空/关闭玩家的 tooltip）');
  if (en.indexOf('CreateFrame("GameTooltip", "EVAL_HELP_WTT"') < 0) bad.push('没有自建隐形 tooltip（照 Heart/C 的 C_Tooltip 范式）');
  if (/getglobal\("GameTooltipTextLeft1"\)/.test(en)) bad.push('还在读 GameTooltipTextLeft1（应读自家 tooltip 自己的 TextLeft1）');
  if (en.indexOf('EVAL_WTT_MAY_READ_PURE') < 0) bad.push('没有「真实 tooltip 正显示就不读」的纯函数守卫');
  if (en.indexOf('EVAL_WTT_MAY_READ()') < 0) bad.push('读口没有调用守卫');
  if (en.indexOf('function EVAL_TEST_WTT()') < 0) bad.push('没有 EVAL_TEST_WTT() 读值口（测试改不动真正在用的那个 tooltip）');
  if (eh.indexOf('go wtt') < 0) bad.push('没有 /eh go wtt 诊断入口');
  if (bad.length) { console.log('WTT ISOLATION CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('WTT ISOLATION CHECK: 自建隐形 tooltip + 读自家 TextLeft1 + 退化有守卫 + 读值口/诊断齐');
})();

// ===== UI ICON CHECK（1.71.3）：新 UI 用的**自包含**图标必须真的在磁盘上 =====
// 背景：本客户端纹理路径写错时**什么都不画**（不报错、不崩，只是空白）——而本轮新增的
//   「类别图标 / 弹窗标题图标」都是刚从 UnrealQuest 拷进本插件的 .tga：漏拷一个、
//   或文件名写成单数/复数不一致，游戏里就是一条空白，而行为断言照样全绿。
// 判据：把生产代码里引用的每个文件名解析到 EvalHelp/media/icons/，逐个核对文件存在 + 类别图标不许重复。
(function () {
  const BS = String.fromCharCode(92);
  const eng = fs.readFileSync(path.join(__dirname, 'Engine.lua'), 'utf8');
  const shr = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const names = [];
  let m;
  const reCat = /CAT_ICON_ROOT\s*\.\.\s*"([^"]+)"/g;
  while ((m = reCat.exec(eng)) !== null) names.push({ file: m[1], from: 'Engine.lua 类别图标' });
  // ★1.71.3 「选取目标:」族的 11 张图标也在同一张自包含表里（用户反馈一排红问号 → 换成可辨认的图）
  const reTse = /TSE_ICON_ROOT\s*\.\.\s*"([^"]+)"/g;
  // ★1.71.3 「跟随」那张（角色行为里非动作条动作的图标）走**另一个根名** ACT_ICON_ROOT：
  //   同根会被下面的「按组查撞图」当成选取目标那族去查重（该文件与「上一目标」共用 boots 是有意的），
  //   所以另立根名 + 在这里单独收一遍，保证它同样「必须在磁盘上存在」。
  const reAct = /ACT_ICON_ROOT\s*\.\.\s*"([^"]+)"/g;
  while ((m = reAct.exec(eng)) !== null) names.push({ file: m[1], from: "Engine.lua 行为图标" });
  // ★1.71.3 状态标记（白=不可用 / 黄=待测试）也在同一张自包含表里（EvalHelp.lua 的 SE_MEDIA_ROOT）。
  //   理由同类别图标：本客户端**纹理路径写错时什么都不画**，而这两枚是新加的图标文件，
  //   漏拷/写错名在行为断言里完全看不见（DD 行只断言「有贴图」，不断言那张图在磁盘上）。
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const reMark = /SE_MEDIA_ROOT\s*\.\.\s*"([^"]+)"/g;
  while ((m = reMark.exec(eh)) !== null) names.push({ file: m[1], from: "EvalHelp.lua 状态标记" });
  while ((m = reTse.exec(eng)) !== null) names.push({ file: m[1], from: 'Engine.lua 选取目标图标' });
  const pLine = shr.split(/\r?\n/).find(l => l.indexOf('local SH_POP_ICON') >= 0) || '';
  const pVal = (pLine.match(/"([^"]+)"/) || [])[1] || '';
  if (pVal) names.push({ file: pVal.split(BS).pop(), from: 'Share.lua 弹窗标题图标' });
  const inner = 'EvalHelp' + BS + BS + 'media' + BS + BS + 'icons' + BS + BS;
  if (!pVal || pVal.indexOf(inner) < 0) {
    console.log('UI ICON CHECK: FAIL - popup icon is not our own self-contained media path: ' + pVal);
    process.exit(1);
  }
  if (names.length < 20) {
    console.log('UI ICON CHECK: FAIL - expected >= 20 icon refs (5 categories + 1 popup + 11 target-select + 2 status marks + 1 follow), got ' + names.length);
    process.exit(1);
  }
  const dir = path.join(__dirname, 'media', 'icons');
  const missing = names.filter(n => !fs.existsSync(path.join(dir, n.file + '.tga')));
  console.log('UI ICON CHECK: ' + names.length + ' self-contained icons, ' + missing.length + ' missing');
  if (missing.length) {
    console.log('  MISSING: ' + missing.map(n => n.file + ' (' + n.from + ')').join(', '));
    console.log('  (this client draws NOTHING for a wrong path -- fix before shipping)');
    process.exit(1);
  }
  // ★只查**类别**图标之间不许重复：弹窗标题图标与某个类别共用同一张图是允许的（同一套风格）
  const seen = {};
  const dup = [];
  // ★每组内部不许撞图（跨组允许：例如「目标选取」类别图标与 byName 都用 database 属同一族风格）
  for (const grp of ['类别', '选取目标']) {
    const seen2 = {}, dup2 = [];
    names.filter(n => n.from.indexOf(grp) >= 0).forEach(n => { if (seen2[n.file]) dup2.push(n.file); seen2[n.file] = true; });
    if (dup2.length) { console.log('UI ICON CHECK: FAIL - duplicate ' + grp + ' icons (must differ): ' + dup2.join(', ')); process.exit(1); }
  }

})();
// ===== TPL TIER ICON CHECK（1.73.42e）：案例模版窗每个方案必须按**同一套品阶判定**显示图标 =====
// 背景（用户要求）：「案例模版内的方案根据以上方案等级配置对应的图标显示」。
//   行为断言照不到「模版窗到底有没有画图标」（那是 UI 接线：漏了不报错、只是没图标）→ 源码检查补位：
//   ① 模版窗必须调用 EVAL_SHARE_SEAL_PARTS（评分 **+ 覆盖大类数**）与 EVAL_SHARE_SEAL_ICON（取图标）；
//      ★1.74.19 改成 PARTS：只看分数会把**覆盖封顶**漏掉（模版窗里的品阶会与分享行不一致，且是静默的）；
//   ② tooltip 必须给出品阶（不然用户不知道为什么是这个图标）。
(function () {
  const t = fs.readFileSync(path.join(__dirname, 'EvalHelp.lua'), 'utf8');
  const bad = [];
  // ★1.74.19：模版窗必须走 PARTS（拿得到覆盖数）→ 档位判定才能带上覆盖封顶
  if (t.indexOf('EVAL_SHARE_SEAL_PARTS(p.text)') < 0) bad.push('模版窗没有按品阶评分（EVAL_SHARE_SEAL_PARTS(p.text)）');
  if (t.indexOf('EVAL_SHARE_SEAL_TIER(sScore, sParts.nClasses)') < 0) bad.push('模版窗的档位判定没带覆盖数（★覆盖封顶会静默失效）');
  if (t.indexOf('EVAL_SHARE_SEAL_ICON(tiIdx)') < 0) bad.push('模版窗没有取品阶图标（EVAL_SHARE_SEAL_ICON）');
  if (t.indexOf('品阶：') < 0) bad.push('模版 tooltip 没有给出品阶说明');
  // ★★★1.73.42l 用户：「名称和颜色背景都要符合以上规则」——名称文字色与行背景色的接线也必须守着
  //   （漏了不报错、只是全窗一个色 → 正是源码检查要补的盲区）
  if (t.indexOf('EVAL_SHARE_SEAL_TIER_RGB(tiIdx)') < 0) bad.push('模版行没有按品阶取 RGB（名称/背景不会跟品阶变色）');
  if (t.indexOf('SetTextColor, bt, tiRGB.r') < 0) bad.push('模版行的名称没有上品阶色');
  if (t.indexOf('SetVertexColor, bb, br, bgc, bbc') < 0) bad.push('模版行的背景没有上品阶暗色调');
  if (bad.length) { console.log('TPL TIER ICON CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('TPL TIER ICON CHECK: 模版窗按品阶评分 + 图标 + tooltip 品阶行');
})();
// ===== SHARE SEAL ROW CHECK（1.73.42i）：接收弹窗的「品阶栏」必须是真控件 + 真数据 ===== 
// 背景（用户要求，项 1）：「收到分享的详情弹窗里加一栏：品阶图标 + 符号 + 境界 + 品阶 + 评语」。
//   这是**UI 接线**（漏接不报错、只是不显示）→ 行为断言之外还要源码检查补位：
//   ① 弹窗必须走**同一个**读值口（EVAL_SHARE_SEAL_ROW）取数据，图标必须是 UI 纹理
//      （`|T` 内联标记已实测在本客户端不可用，1.73.42d）；
//   ② 读值口必须复用同一套品阶判定（评分 → 档位 → 图标/符号），不许另写一份；
//   ③ **诚实兜底**：发送端信息（境界/评语）拿不到时必须写「未知」——绝不用本机角色的境界或
//      本机随机抽的评语冒充（那会让用户以为看到的是发送端的数据）。
(function () {
  const t = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const bad = [];
  const popStart = t.indexOf('local function shPopupBuild');
  const popEnd = t.indexOf('function EVAL_SH_POPUP(');
  const pop = (popStart >= 0 && popEnd > popStart) ? t.slice(popStart, popEnd) : '';
  if (!pop) bad.push('找不到弹窗构建段（锚点变了？）');
  if (pop.indexOf('EVAL_SHARE_SEAL_ROW(') < 0) bad.push('弹窗没有调用 EVAL_SHARE_SEAL_ROW（品阶栏数据来源断了）');
  if (pop.indexOf('shp.sealIcon') < 0) bad.push('弹窗没有品阶图标控件');
  if (pop.indexOf('CreateTexture') < 0) bad.push('品阶图标不是 UI 纹理（|T 内联标记本客户端不可用）');
  const rfStart = t.indexOf('function EVAL_SHARE_SEAL_ROW(');
  const rfEnd = t.indexOf('\nfunction ', rfStart + 10);
  const rf = (rfStart >= 0 && rfEnd > rfStart) ? t.slice(rfStart, rfEnd) : '';
  if (!rf) bad.push('找不到 EVAL_SHARE_SEAL_ROW 实现');
  // ★1.74.19 改成 PARTS：品阶栏也必须拿**覆盖大类数**（否则覆盖封顶在接收端静默失效）
  ['EVAL_SHARE_SEAL_PARTS(', 'EVAL_SHARE_SEAL_TIER(', 'EVAL_SHARE_SEAL_ICON(', 'EVAL_SHARE_SEAL_SYMBOL('].forEach(function (k) {
    if (rf && rf.indexOf(k) < 0) bad.push('品阶栏读值口没有复用 ' + k);
  });
  if (rf && rf.indexOf('EVAL_SHARE_SEAL_TIER(score, parts.nClasses)') < 0)
    bad.push('品阶栏的档位判定没带覆盖数（★覆盖封顶会静默失效）');
  if (rf && rf.indexOf('未知') < 0) bad.push('品阶栏没有「未知」兜底（拿不到封皮行时会编数据）');
  if (t.indexOf('SH.sealMeta[sid]') < 0) bad.push('封皮行没有解析出发送端信息（SH.sealMeta）');
  if (bad.length) { console.log('SHARE SEAL ROW CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('SHARE SEAL ROW CHECK: 弹窗品阶栏 = 真纹理图标 + 同源品阶判定 + 未知兜底 + 封皮元数据');
})();
// ===== SEAL SYMBOL CHECK（1.73.42o）：品阶符号必须是**本客户端字体真有的字形** =====
// 背景（用户真机反馈）：「字符图标,珍稀,源代码级别没生效」——`✦`(U+2726) 与 `✸`(U+2738) 都在 **Dingbats 块**
//   (U+2700–U+27BF)，本客户端字体没带这半边 → 聊天里**一个像素都不显示**（而且不报错，肉眼才发现）。
//   ★教训推广：这一类「客户端字体没有的字形」行为断言照不到（字符串比的是我们自己写的），必须源码检查钉住区块。
(function () {
  const shr = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const m = shr.match(/local SH_SEAL_SYMBOLS = \{([^}]*)\}/);
  if (!m) { console.log('SEAL SYMBOL CHECK: FAIL - 找不到 SH_SEAL_SYMBOLS'); process.exit(1); }
  const syms = (m[1].match(/"([^"]+)"/g) || []).map(function (s) { return s.slice(1, -1); });
  const bad = [];
  if (syms.length !== 5) bad.push('符号不是 5 个（' + syms.length + '）');
  const seen = {};
  syms.forEach(function (s) {
    const cps = Array.from(s);
    if (cps.length !== 1) { bad.push('"' + s + '" 不是单字形（' + cps.length + ' 个码点）'); return; }
    const cp = s.codePointAt(0);
    if (cp >= 0x2700 && cp <= 0x27BF) bad.push('"' + s + '" 落在 Dingbats 块 U+' + cp.toString(16).toUpperCase() + '（本客户端不显示）');
    if (seen[s]) bad.push('符号重复：' + s);
    seen[s] = true;
  });
  if (bad.length) { console.log('SEAL SYMBOL CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('SEAL SYMBOL CHECK: 5 个符号都是单字形且不在 Dingbats 块（' + syms.join(' ') + '）');
})();
// ===== SAVEDVARS SPLIT CHECK（1.74.20）：三个助手的配置**按角色存**，且只有一份真值 =====
// 背景（用户：「消耗品助手 + 喂食助手 + 骑乘助手整块按角色。配置按照角色存储」）：
//   新增角色级存档 EVAL_HELP_CHAR + tbCfg() 的**路由代理**之后，最容易出的静默错有三种：
//     ① toc 忘了声明 SavedVariablesPerCharacter → 运行期 EVAL_HELP_CHAR 恒 nil（配置**每次都丢**，不报错）；
//     ② 哪个生产文件直接读 EVAL_HELP_CONFIG.tb.<角色键> → 读到的是**账号表**（老值/空值），两份真值；
//     ③ 三个助手没接上角色表（还是读写账号表）→ 用户以为按角色存了、其实还是共用。
(function () {
  const bad = [];
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  if (!/^##\s*SavedVariablesPerCharacter:\s*EVAL_HELP_CHAR\b/m.test(toc))
    bad.push("EvalHelp.toc 没有声明 ## SavedVariablesPerCharacter: EVAL_HELP_CHAR（角色级存档会恒为 nil）");
  const tb = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
  if (tb.indexOf("local TB_CHAR_KEYS = {") < 0) bad.push("找不到角色键清单 TB_CHAR_KEYS（唯一来源）");
  if (tb.indexOf("return tbMakeRouter()") < 0) bad.push("tbCfg() 没有返回路由代理（角色键会落回账号表）");
  ["function EVAL_TB_CHAR_STORE(", "function EVAL_TB_CHAR_MIGRATE(", "function EVAL_TB_IS_CHAR_KEY(",
   "function EVAL_TB_CHAR_KEY_LIST(", "function EVAL_TB_CHAR_RESET("].forEach(function (k) {
    if (tb.indexOf(k) < 0) bad.push("Toolbox.lua 缺读值口/入口：" + k);
  });
  // ★router 的 __index 里绝不许出现「and at[k] or ...」（false or nil 还是 nil → 用户关掉的开关自己又开）
  const ri = tb.indexOf("__index = function(_, k)");
  const rj = tb.indexOf("__newindex", ri);
  // ★判据必须**先摘注释**：本轮那次事故的注释里就写着那个错误写法（`at and at[k] or nil`），
  //   不摘注释会让检查**假红**（本项目 DECL ORDER / CHAT COLOR WIRING 等都踩过同一坑）。
  const nocomment = function (s) { return s.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n"); };
  const seg = (ri >= 0 && rj > ri) ? nocomment(tb.slice(ri, rj)) : "";
  if (!seg) bad.push("取不到路由代理的 __index 段");
  if (/and\s+at\s*\[\s*k\s*\]\s*or/.test(seg)) bad.push("路由代理的 __index 用了 and/or 的写法（false 会被吞成 nil）");
  // 三个助手必须走角色存档
  [["ConsumableHelper.lua", "消耗品助手"], ["HunterHelper.lua", "喂食助手"], ["DismountHelper.lua", "骑乘助手"]]
    .forEach(function (pair) {
      const p = path.join(__dirname, "tools", pair[0]);
      if (!fs.existsSync(p)) { bad.push("找不到 " + p); return; }
      const src = nocomment(fs.readFileSync(p, "utf8")); // ★摘注释（文件头注释里就写着这个键名）
      if (src.indexOf("EVAL_TB_CHAR_STORE()") < 0) bad.push(pair[1] + " 没接角色存档（EVAL_TB_CHAR_STORE）");
      if (/EVAL_HELP_CONFIG\s*\.\s*tb/.test(src)) bad.push(pair[1] + " 还在直接读 EVAL_HELP_CONFIG.tb（会读到账号表）");
    });
  // 生产文件里不许直接按角色键读账号表
  const m = tb.match(/local TB_CHAR_KEYS = \{([\s\S]*?)\n\}/);
  const charKeys = m ? ((m[1].match(/([A-Za-z_][A-Za-z0-9_]*)\s*=\s*true/g) || []).map(function (x) { return x.split("=")[0].trim(); })) : [];
  if (charKeys.length < 10) bad.push("角色键清单解出来太少（" + charKeys.length + "）—— 锚点变了？");
  const prodFiles = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua",
                     "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua",
                     "tools/ConsumableHelper.lua", "tools/HunterHelper.lua", "tools/DismountHelper.lua", "tools/IconGrid.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua"];
  const leaks = [];
  prodFiles.forEach(function (f) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) return;
    const src = fs.readFileSync(p, "utf8").split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    charKeys.forEach(function (k) {
      const re = new RegExp("EVAL_HELP_CONFIG\\s*\\.\\s*tb\\s*\\.\\s*" + k + "\\b");
      if (re.test(src)) leaks.push(f + ":" + k);
    });
  });
  if (leaks.length) bad.push("这些地方直接按角色键读了**账号表**（会读到老值/空值，两份真值）：" + leaks.join(","));
  // 迁移必须挂在 VARIABLES_LOADED（早调会从空表继承出空配置、还把标志立上）
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  if (eh.indexOf("EVAL_TB_CHAR_MIGRATE") < 0) bad.push("EvalHelp.lua 没在 VARIABLES_LOADED 里触发角色配置迁移");
  if (bad.length) { console.log("SAVEDVARS SPLIT CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("SAVEDVARS SPLIT CHECK: toc 声明角色级存档 · 角色键清单 " + charKeys.length + " 个（唯一来源）· tbCfg 走路由代理（无 and/or 吞 false）· 三个助手都接角色存档 · 无「按角色键读账号表」的泄漏 · 迁移挂在 VARIABLES_LOADED");
})();
// ===== COND WEIGHT CHECK（1.74.19）：评分用的「条件权重 / 覆盖大类」**只有一个来源** =====
// 背景（用户：「审计方案的评级标准…增加评级难度」）：评分口径重做成「空技能不计分 + 条件按类加权 +
//   覆盖封顶」后，权重表成了判定的核心。最容易出的静默错有两种：
//     ① 另开一张「条件→权重」表 → 以后往 SE_TYPES 加条件类型时**漏配 = 静默按 0 分算**（也不计覆盖）；
//     ② Share.lua 自己抄一份权重（两份真值迟早漂移）。
//   ⇒ 判据：① SE_TYPES 里的**每一个** id 都出现在 SE_TYPE_GROUPS 的某个分组里；
//     ② 每个分组都配了 w（权重）与 cov（覆盖大类）且 5 个大类都非空；
//     ③ 权重表**由分组表派生**（SE_COND_W[id] = grp.w），Share.lua 只走读值口。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  const bad = [];
  const ti = eh.indexOf("local SE_TYPES = {");
  const tj = eh.indexOf("\n}", ti);
  const typesSeg = (ti >= 0 && tj > ti) ? eh.slice(ti, tj) : "";
  const ids = (typesSeg.match(/id\s*=\s*"([A-Za-z]+)"/g) || []).map(function (x) { return x.match(/"([A-Za-z]+)"/)[1]; });
  if (ids.length < 50) bad.push("SE_TYPES 解出来的条件类型太少（" + ids.length + "）—— 锚点变了？");
  const gi = eh.indexOf("local SE_TYPE_GROUPS = {");
  const gj = eh.indexOf("\n}", gi);
  const grpSeg = (gi >= 0 && gj > gi) ? eh.slice(gi, gj) : "";
  if (!grpSeg) bad.push("找不到 SE_TYPE_GROUPS");
  // ★按**条目整块**解析（不按行切）：一组写成多行也照样查得出来（写成一行的也行）
  const entryRe = /\{\s*label\s*=\s*"(CTG_\d+)"[\s\S]*?ids\s*=\s*\{([\s\S]*?)\}\s*\}/g;
  const classes = {};
  const covered = {};
  let em, grpN = 0;
  while ((em = entryRe.exec(grpSeg)) !== null) {
    grpN++;
    const whole = em[0];
    if (!/w\s*=\s*\d+/.test(whole)) bad.push("分组 " + em[1] + " 没配权重 w");
    const c = whole.match(/cov\s*=\s*"([A-E])"/);
    if (!c) bad.push("分组 " + em[1] + " 没配覆盖大类 cov");
    else classes[c[1]] = true;
    (em[2].match(/"[A-Za-z]+"/g) || []).forEach(function (q) { covered[q.slice(1, -1)] = true; });
  }
  if (grpN !== 6) bad.push("条件分组不是 6 组（实际 " + grpN + "）—— 下拉分组被改坏了");
  ["A", "B", "C", "D", "E"].forEach(function (k) { if (!classes[k]) bad.push("覆盖大类 " + k + " 是空的（没有任何条件类型）"); });
  const miss = ids.filter(function (k) { return !covered[k]; });
  if (miss.length) bad.push("这些条件类型**没进任何分组**（⇒ 评分按 0 分、也不计覆盖）：" + miss.join(","));
  if (eh.indexOf("SE_COND_W[id] = grp.w") < 0) bad.push("权重不是从分组表派生的（SE_COND_W[id] = grp.w 不见了）");
  if (eh.indexOf("function EVAL_COND_WEIGHT(") < 0 || eh.indexOf("function EVAL_COND_CLASS(") < 0) bad.push("缺 EVAL_COND_WEIGHT / EVAL_COND_CLASS 读值口");
  if (sh.indexOf("EVAL_COND_WEIGHT(") < 0 || sh.indexOf("EVAL_COND_CLASS(") < 0) bad.push("Share.lua 的评分没走权重/大类读值口（自己抄了一份？）");
  if (bad.length) { console.log("COND WEIGHT CHECK: FAIL - " + bad.join("; ")); process.exitCode = 1; return; }
  console.log("COND WEIGHT CHECK: " + ids.length + " 个条件类型全部归组 · " + grpN + " 组各配权重与覆盖大类 · 权重由分组表派生（单一来源）");
})();
// ===== COVERAGE CAP WIRING CHECK（1.74.19）：覆盖封顶必须**真的接上** =====
// 为什么要有它：封顶是「带 coverage 参数才生效」的 —— 有人写成
//   EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p)) 就会把封顶整个漏掉，
//   而**分数与档位看起来都正常**（只是天花板没生效）= 典型的静默失败。
//   判据：① 单一入口 EVAL_PROFILE_TIER 与 shCoverCap 在；② 没人在方案表上直接调「只传分数」的老写法；
//     ③ 晋升统计与 UI 品阶读值口都走单入口。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  const bad = [];
  const nocomment = function (s) { return s.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n"); };
  const ehNo = nocomment(eh), shNo = nocomment(sh);
  if (shNo.indexOf("function EVAL_PROFILE_TIER(") < 0) bad.push("找不到单入口 EVAL_PROFILE_TIER");
  if (shNo.indexOf("local function shCoverCap(") < 0) bad.push("找不到封顶函数 shCoverCap");
  if (shNo.indexOf("EVAL_PROFILE_TIER(p)") < 0) bad.push("晋升统计没走单入口（EVAL_TITLE_COUNTS 会把封顶漏掉）");
  if (ehNo.indexOf("EVAL_PROFILE_TIER, prof") < 0) bad.push("品阶读值口没走单入口（uiProfileTierRGB）");
  const offenders = [];
  [["EvalHelp.lua", ehNo], ["Share.lua", shNo]].forEach(function (pair) {
    const re = /EVAL_SHARE_SEAL_TIER\(\s*EVAL_PROFILE_SCORE\(/g;
    let m;
    while ((m = re.exec(pair[1])) !== null) offenders.push(pair[0]);
  });
  if (offenders.length) bad.push("还在用「只传分数」的老写法（★封顶会静默失效）：" + offenders.join(","));
  if (bad.length) { console.log("COVERAGE CAP WIRING CHECK: FAIL - " + bad.join("; ")); process.exitCode = 1; return; }
  console.log("COVERAGE CAP WIRING CHECK: 单入口 EVAL_PROFILE_TIER + shCoverCap 在位 · 无「只传分数」的老写法 · 晋升统计与 UI 读值口都走单入口");
})();

// ===== TITLE GACHA CHECK（1.73.42n）：头衔抽卡的**结构与单一来源**必须钉死 =====
// 背景（用户定稿）：「5 档（= 方案稀有度档数）× 每档 15 张」「每档只抽一次、不重复、唯一不变」「只升不降」
//   + 彩蛋预留：自定义头衔优先度最高、**只有一次**修改机会。
//   ★行为断言能验「现在跑得对」，但验不了「以后改表改坏」→ 结构类事实交给源码检查：
//     ① 卡池 5×15=75 个键，且三语言都齐；② 评分只有**一个**来源（EVAL_PROFILE_SCORE）；
//     ③ 「已抽过就不重抽」的守卫必须在；④ 彩蛋自定义的「只有一次」守卫必须在；
//     ⑤ 分享行必须用 EVAL_TITLE_CURRENT() 取身份（不许各处自己拼头衔）。
(function () {
  const shr = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const bad = [];
  const m = shr.match(/local SH_TITLES = \{([\s\S]*?)\n\}/);
  if (!m) { console.log('TITLE GACHA CHECK: FAIL - 找不到 SH_TITLES'); process.exit(1); }
  const keys = (m[1].match(/"(TITLE_\d+_\d+)"/g) || []).map(function (s) { return s.slice(1, -1); });
  if (keys.length !== 75) bad.push('卡池不是 75 个键（实际 ' + keys.length + '）');
  const byTier = {};
  const dup = {};
  keys.forEach(function (k) {
    const mm = k.match(/^TITLE_(\d+)_(\d+)$/);
    if (!mm) { bad.push('键名不规范：' + k); return; }
    const t = Number(mm[1]);
    byTier[t] = (byTier[t] || 0) + 1;
    if (dup[k]) bad.push('键重复：' + k);
    dup[k] = true;
  });
  for (let t = 1; t <= 5; t++) if (byTier[t] !== 15) bad.push('第 ' + t + ' 档不是 15 张（' + (byTier[t] || 0) + '）');
  for (const lg of ['zhCN', 'enUS', 'ruRU']) {
    const loc = fs.readFileSync(path.join(__dirname, 'Locales', lg + '.lua'), 'utf8');
    const miss = keys.filter(function (k) { return loc.indexOf(k + ' = ') < 0; });
    if (miss.length) bad.push(lg + ' 缺 ' + miss.length + ' 个头衔键（如 ' + miss[0] + '）');
  }
  // ② 评分单一来源：品阶评分与晋升统计都得走 EVAL_PROFILE_SCORE
  // ★1.74.19 文本路径改走 PARTS（分数 + 覆盖数同源）—— 仍然只此一份评分实现，且档位判定带得上覆盖封顶
  if (shr.indexOf('return EVAL_PROFILE_PARTS(p)') < 0) bad.push('文本评分没有复用 EVAL_PROFILE_PARTS（会各算一套）');
  if (shr.indexOf('EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p))') < 0) bad.push('晋升统计没有用同一个评分函数');
  // ③ 每档只抽一次
  if (shr.indexOf('if t.draws[k] == nil then') < 0) bad.push('没有「已抽过就不重抽」的守卫（每档只抽一次）');
  // ④ 彩蛋：只有一次
  if (shr.indexOf('if type(t.custom) == "string" and t.custom ~= "" then return false end') < 0)
    bad.push('彩蛋自定义没有「只有一次」守卫');
  // ⑤ 分享行取身份的唯一入口
  if (shr.indexOf('local tt = EVAL_TITLE_CURRENT()') < 0) bad.push('分享行没有用 EVAL_TITLE_CURRENT() 取头衔');
  // ⑥ 彩蛋「创世者亲临」（1.73.42p）：窗口入口 · 专属色 · 文案走 Locales（不许把霸道文案写死在代码里）·
  //    四句道白是**拼出来的键**（CREATOR_L..i）→ LANG KEY CHECK 看不见，这里按清单逐个核三语言。
  if (shr.indexOf('function EVAL_TITLE_CREATOR_OPEN()') < 0) bad.push('没有彩蛋窗口的打开入口');
  // ★1.73.42q 用户真机报「没输入框」：EditBox 必须 ①收鼠标（否则点不进焦点）②有**字体路径兜底链**
  //   （字体对象缺失时一个字都画不出 —— 看着就是「没有输入框」）。
  //   ★★★检查必须**收窄到彩蛋窗口的构建段**：`Fonts\...` 与 `fieldHit` 这两个词别处也有
  //   （shText 自己的字体链、测试钩子里的 fieldHit）→ 全文件找会让变异**存活**（本轮实测 M403/M404 SURVIVED）。
  const cbStart = shr.indexOf('local function shCreatorBuild()');
  const cbEnd = shr.indexOf('function EVAL_TITLE_CREATOR_OPEN()', cbStart);
  const creator = (cbStart >= 0 && cbEnd > cbStart) ? shr.slice(cbStart, cbEnd) : '';
  if (!creator) bad.push('找不到彩蛋窗口构建段（锚点变了？）');
  if (creator && creator.indexOf('pcall(eb.EnableMouse, eb, true)') < 0) bad.push('彩蛋输入框没有 EnableMouse（点不进焦点 → 打不了字）');
  if (creator && creator.indexOf('Fonts\\\\FZLBJW.TTF') < 0) bad.push('彩蛋输入框没有字体路径兜底链（字体对象缺失时一个字都画不出）');
  if (creator && creator.indexOf('shCreator.fieldHit = hit') < 0) bad.push('彩蛋输入框没有点击聚焦层（本客户端 EditBox 自己收鼠标不保险）');
  if (shr.indexOf('SH_TITLE_CUSTOM_COLOR') < 0) bad.push('自定义名号没有专属色（与抽卡色分不开）');
  if (shr.indexOf('local lineKeys = { "CREATOR_L1"') < 0) bad.push('四条道白没有走 Locales 键表');
  ['CREATOR_T', 'CREATOR_L1', 'CREATOR_L2', 'CREATOR_L3', 'CREATOR_L4', 'CREATOR_HINT', 'CREATOR_OK',
   'CREATOR_CANCEL', 'CREATOR_ONE', 'CREATOR_USED', 'CREATOR_DONE', 'CREATOR_ERR', 'CREATOR_CLOSED', 'CREATOR_CUR'
  ].forEach(function (k) {
    for (const lg of ['zhCN', 'enUS', 'ruRU']) {
      const loc = fs.readFileSync(path.join(__dirname, 'Locales', lg + '.lua'), 'utf8');
      if (loc.indexOf('  ' + k + ' = ') < 0) bad.push(lg + ' 缺彩蛋文案键 ' + k);
    }
  });
  if (bad.length) { console.log('TITLE GACHA CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('TITLE GACHA CHECK: 5×15=75 头衔（三语言齐）· 评分单一来源 · 每档只抽一次 · 彩蛋仅一次 · 身份走单一入口');

// ===== CREATOR GATE CHECK（1.73.63）：彩蛋「创世者亲临」的触发条件 =====
// ★背景：用户「排查下 之前的彩蛋是如何触发的. 调整彩蛋触发规则」——排查结论 = **以前根本没有条件**，
//   只有一条命令 `/eh go 创世`（源码原话「触发机制以后再接」）。现在用户定了三条件：
//   ① 手动创建的方案里有一个达到神级（≥25 分）② 手动创建的方案 ≥3 个 ③ 头衔满档（5 档）。
//   ★这类「加一道闸门」最容易出的两种静默错：a) 只堵窗口那条路、`TRY`（命令后路）留了后门；
//     b) 闸门函数写了但没人调（等于没有）。行为断言组 169 能抓，源码检查再钉一层。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  const noComment = function (s) { return s.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n"); };
  const shNo = noComment(sh), ehNo = noComment(eh);
  const bad = [];
  // ① 闸门函数存在，且**三条条件都在**（少一条 = 条件被悄悄放宽）
  if (shNo.indexOf("function EVAL_TITLE_CREATOR_GATE(") < 0) bad.push("找不到闸门函数 EVAL_TITLE_CREATOR_GATE");
  const gi = shNo.indexOf("function EVAL_TITLE_CREATOR_GATE(");
  const gEnd = shNo.indexOf("\nend", gi);
  const gateBody = (gi >= 0 && gEnd > gi) ? shNo.slice(gi, gEnd) : "";
  ["src ~= \"text\"", ">= out.needScore", "out.manualN >= out.needN", "out.titleTier >= out.needTier"]
    .forEach(function (k) { if (gateBody.indexOf(k) < 0) bad.push("闸门里少了条件：" + k); });
  // ② **两条路都要过闸门**：窗口入口 + 命令后路（只堵一条 = 后门）
  if (shNo.indexOf("if not gGate.ok then") < 0) bad.push("EVAL_TITLE_CREATOR_OPEN 没先查闸门（旧行为：无条件开窗）");
  if (shNo.indexOf("if not gTry.ok then") < 0) bad.push("EVAL_TITLE_CREATOR_TRY 没查闸门（/eh go 创世 <名号> 会绕过条件）");
  // ③ 来源标记：解析出口盖 text、手工插入点盖 manual
  if (shNo.indexOf("src = \"text\"") >= 0) bad.push("src=text 不该在 Share.lua（解析出口在 EvalHelp.lua）");
  if (ehNo.indexOf("src = \"text\"") < 0) bad.push("EVAL_PROFILE_FROM_TEXT 没盖 src=text（导入来的会被当成自己写的）");
  const manualN = (ehNo.match(/src = "manual"/g) || []).length;
  if (manualN < 2) bad.push("手工创建方案的插入点只打了 " + manualN + " 处 src=manual（应为 2：配置窗 [+] 与 /eh go newprof）");
  // ④ 自动触发检查必须**接线**（写在 Share.lua 里却没人调 = 等于没有）
  if (shNo.indexOf("function EVAL_TITLE_EGG_CHECK(") < 0) bad.push("找不到自动触发检查 EVAL_TITLE_EGG_CHECK");
  const wired = (ehNo.match(/EVAL_TITLE_EGG_CHECK/g) || []).length;
  if (wired < 2) bad.push("EVAL_TITLE_EGG_CHECK 只接了 " + wired + " 处（方案/技能改动后 + 登录，两处都要）");
  if (bad.length) { console.log("CREATOR GATE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("CREATOR GATE CHECK: 三条件闸门（手动方案≥3 + 一个神级 + 头衔满档）· 窗口与命令后路都过闸 · 来源标记齐 · 自动触发已接线");
})();
})();

// ===== SH FUN CHECK（1.73.64 建立 / 1.74.5 改）：彩蛋「角色扮演反应」——**功能保留，当前不接线** =====
// ★背景：用户「根据当前秘籍等级 和接收者自身的头衔等级 做出导入/忽略的符合角色扮演语境反应会话」+「说/队伍 加入」。
//   最易出的静默错：① 频道映射漏了（说/队伍不发）；② 抽奖写成恒取第 1 条；③ 两个按钮传错 op；④ 语气档位算错。
// ★★1.74.5 用户「取消彩蛋」，随后明确「**不是把彩蛋功能删除**」⇒ **这一条流程**（导入/忽略）不再发反应句，改发
//   「场景描述」（见 SHARE SCENE WIRING CHECK）。机制 / 频道表 / 抽奖 / 名链接 / 三语言 50 格文案**全部保留**，
//   只把两处调用点摘掉 ⇒ 本检查现在钉的是「**机制都在 且 调用点确实没接**」。
//   ★要恢复接线：把 shSendReaction("imp"/"ign") 加回按钮回调，并**同步改本检查**（否则它会红 —— 这是故意的）。
(function () {
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  const noComment = sh.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  const bad = [];
  if (noComment.indexOf("local SH_FUN_CHAN = {") < 0) bad.push("找不到频道映射 SH_FUN_CHAN");
  ["CHAT_MSG_GUILD = \"GUILD\"", "CHAT_MSG_PARTY = \"PARTY\"", "CHAT_MSG_SAY = \"SAY\""]
    .forEach(function (k) { if (noComment.indexOf(k) < 0) bad.push("频道映射缺：" + k); });
  if (noComment.indexOf("local function shSendReaction(") < 0) bad.push("找不到反应函数 shSendReaction");
  if (noComment.indexOf("math.random(1, table.getn(pool))") < 0) bad.push("反应不是抽奖式随机（应在 10 条候选里随机挑）");
  if (noComment.indexOf('L(op == "ign" and "SH_FUN_IGN" or "SH_FUN_IMP")') < 0) bad.push("反应没按 op 选 SH_FUN_IMP/SH_FUN_IGN 那张表");
  if (noComment.indexOf("EVAL_TITLE_STATE") < 0) bad.push("反应没读接收者头衔档（EVAL_TITLE_STATE）");
  if (noComment.indexOf("EVAL_SHARE_SEAL_SCORE") < 0) bad.push("反应没现算秘籍品阶档（EVAL_SHARE_SEAL_SCORE）");
  if (noComment.indexOf("local function shReactionNameLink(") < 0) bad.push("找不到反应名链接函数 shReactionNameLink");
  if (noComment.indexOf('.. "|HEHPF:" .. p.idh .. " 0/1:1|h["') < 0) bad.push("反应名没造 |HEHPF:<传输id> 链接（点了打不开接收页）");
  if (noComment.indexOf("shReactionNameLink(p)") < 0) bad.push("反应句没把方案名换成链接（shReactionNameLink(p) 没被调用）");
  if (noComment.indexOf("> SH_MSG_MAX") < 0) bad.push("带链接后没有「超长退回纯名字」守卫（整条可能被客户端吞）");
  // ★1.74.5：两处调用点必须**不在**（用户要求这条流程改发场景描述）
  if (noComment.indexOf('shSendReaction("imp")') >= 0) bad.push("[导入] 又接上了 shSendReaction（1.74.5 起改发场景描述；恢复接线请同步改本检查）");
  if (noComment.indexOf('shSendReaction("ign")') >= 0) bad.push("[忽略] 又接上了 shSendReaction（同上）");
  if (bad.length) { console.log("SH FUN CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("SH FUN CHECK: 机制都在（频道映射/两表/抽奖/名链接/超长守卫）· 导入与忽略**未接线**（1.74.5 起改发场景描述）");
})();
// ===== SEAL ICON NAMES CHECK（1.73.42l）：品阶图标的**名字**必须是客户端真有的（用户指定的五张） =====
// 背景：图标由用户点名（截图里是 `.../INV_Misc_ShadowEgg_TEX` 这种**资源名**）——
//   ① `_TEX` 是客户端资源命名，插件侧路径一律 `Interface\\Icons\\<裸名>`，带上后缀真机**画不出东西**；
//   ② 拼错一个字母同样「不报错、只是空白」→ 必须拿 IconSem.lua（客户端图标清单）逐个核。
(function () {
  const t = fs.readFileSync(path.join(__dirname, 'Share.lua'), 'utf8');
  const sem = fs.readFileSync(path.join(__dirname, 'IconSem.lua'), 'utf8');
  const m = t.match(/local SH_SEAL_ICONS = \{([\s\S]*?)\}/);
  if (!m) { console.log('SEAL ICON NAMES CHECK: FAIL - 找不到 SH_SEAL_ICONS 表'); process.exit(1); }
  const names = (m[1].match(/"([^"]+)"/g) || []).map(function (s) { return s.slice(1, -1); });
  const bad = [];
  if (names.length !== 5) bad.push('品阶图标不是 5 个（实际 ' + names.length + '）');
  names.forEach(function (n) {
    if (n.indexOf('_TEX') >= 0) bad.push(n + ' 带了 _TEX 后缀（插件路径只用裸名）');
    if (sem.indexOf('["' + n + '"]') < 0) bad.push(n + ' 不在 IconSem.lua（客户端图标清单）里，真机会画不出东西');
  });
  if (bad.length) { console.log('SEAL ICON NAMES CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('SEAL ICON NAMES CHECK: 品阶图标 5 张都在客户端图标清单里（裸名，无 _TEX）');
})();
// ===== TEMPLATE COUNT CHECK（1.73.40）：文档里那句「案例模版 N 条」必须等于 examples/ 里的**真实条数** =====
// 背景（用户「将当前方案添加到案例模版」）：模版数据在 examples/*.lua，而「一共有多少条」这句话**散在 4 个地方**
//   （.toc 的 Notes + 三语言 README 各若干处）→ 加/删一条模版只改数据不改文档，玩家看到的数量就是**骗人的**，
//   而且**不报错**（正是本项目最怕的那一类：信息过时、位置不对、静默）。
// 判据：① 按「每条模版都以 `{ name = "` 开头」数真实条数；② 四处文档里的数字必须**都等于**它（一个都不能漏）。
(function () {
  const dir = path.join(__dirname, 'examples');
  const files = fs.readdirSync(dir).filter(function (f) { return /\.lua$/.test(f); });
  let real = 0;
  files.forEach(function (f) {
    fs.readFileSync(path.join(dir, f), 'utf8').split(/\r?\n/).forEach(function (l) {
      if (/^\s*\{\s*name\s*=\s*"/.test(l)) real++;
    });
  });
  const bad = [];
  if (real < 20) bad.push('模版条数只数出 ' + real + ' 条（扫描口径过时？）');
  const wants = [
    ['EvalHelp.toc', /12\s*\u7ec4\s*(\d+)\s*\u6761/g],
    ['README.md', /12\s*\u7ec4\s*(\d+)\s*\u6761/g],
    ['README_en.md', /12 groups[^0-9]{0,12}(\d+)/g],
    ['README_ru.md', /12 \u0433\u0440\u0443\u043f\u043f[^0-9]{0,12}(\d+)/g],
  ];
  wants.forEach(function (w) {
    const s = fs.readFileSync(path.join(__dirname, w[0]), 'utf8');
    const nums = [];
    let m;
    while ((m = w[1].exec(s)) !== null) nums.push(Number(m[1]));
    if (!nums.length) bad.push(w[0] + ' \u91cc\u627e\u4e0d\u5230\u300c12 \u7ec4 N \u6761\u300d\u8fd9\u53e5\u8bdd');
    nums.forEach(function (n) { if (n !== real) bad.push(w[0] + ' \u5199 ' + n + ' \u6761\uff0c\u5b9e\u9645 ' + real + ' \u6761'); });
  });
  if (bad.length) { console.log('TEMPLATE COUNT CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('TEMPLATE COUNT CHECK: \u771f\u5b9e ' + real + ' \u6761 == toc Notes + \u4e09\u8bed\u8a00 README \u7684\u5199\u6cd5');
// ===== TPL AUTHOR WIRING CHECK（1.74.22）：模版条目的「作者/备注」必须真的显示 + 导入时真的带上署名 =====
// 背景（用户「作者备注: Rainbow / 案例备注: 来自龙之国度的LM-Rainbow-骑士无私分享」）：
//   数据字段进 examples 只完成了「存下来」；**能不能显示出来、导入时带不带**是 UI 接线——
//   漏接不报错、只是悬停少两行 / 方案来源记成「技能学院」（静默）⇒ 源码检查补位。
(function () {
  const t = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const bad = [];
  if (t.indexOf('type(p.author) == "string"') < 0) bad.push("模版 tooltip 没有读 p.author（作者备注不会显示）");
  if (t.indexOf('type(p.note) == "string"') < 0) bad.push("模版 tooltip 没有读 p.note（案例备注不会显示）");
  if (t.indexOf('L("TPL_AUTHOR")') < 0 || t.indexOf('L("TPL_NOTE")') < 0) bad.push("作者/备注两行没走语言包（L(TPL_AUTHOR)/L(TPL_NOTE)）");
  if (t.indexOf('ioImportText(p.text, p.author or "技能学院")') < 0) bad.push("导入没带上模版署名（作者备注形同虚设）");
  for (const lg of ["zhCN", "enUS", "ruRU"]) {
    const loc = fs.readFileSync(path.join(__dirname, "Locales", lg + ".lua"), "utf8");
    if (loc.indexOf("TPL_AUTHOR") < 0 || loc.indexOf("TPL_NOTE") < 0) bad.push(lg + " 缺 TPL_AUTHOR / TPL_NOTE");
  }
  const dir = path.join(__dirname, "examples");
  let withAuthor = 0;
  for (const f of fs.readdirSync(dir).filter(function (f) { return /\.lua$/.test(f); })) {
    const s = fs.readFileSync(path.join(dir, f), "utf8");
    withAuthor += (s.match(/^\s*\{\s*name\s*=\s*"[^"]*",\s*author\s*=\s*"/gm) || []).length;
  }
  if (withAuthor < 1) bad.push("examples 里没有任何带 author 的模版条目（这条通道没有数据在走）");
  if (bad.length) { console.log("TPL AUTHOR WIRING CHECK: FAIL - " + bad.join("; ")); process.exitCode = 1; return; }
  console.log("TPL AUTHOR WIRING CHECK: 作者/备注显示 + 导入署名 + 三语言标签 + " + withAuthor + " 条带 author 的模版");
})();
})();
// ===== MENU ROUND CHROME CHECK（1.73.40）：右键菜单的「圆角边框」只能走客户端原生圆角边贴图 =====
// 背景（用户「圆角」）：1.12 没有圆角控件，圆角只能来自客户端的边贴图 Interface\Tooltips\UI-Tooltip-Border
//   （vanilla 右键菜单/提示框就是 bgFile=UI-Tooltip-Background + edgeFile=UI-Tooltip-Border + edgeSize 16 + insets）。
// 判据（行为断言照不到「客户端约定」，只能靠源码检查补位）：
//   ① 必须显式给 edgeFile（参考插件 Agent 实测：backdrop 表里不给 edgeFile，边框贴图会留在表里继续画）；
//   ② edgeSize 必须是**整数**（实测：小数在本客户端栅格化不可靠）；
//   ③ 必须 SetBackdropBorderColor 成白色高亮（不给就保持客户端默认色）；
//   ④ 必须 GetBackdrop 读回确认 + 有「挂不上退回四条平边」的退化路径；
//   ⑤ 绝不许调 GetBackdropColor / GetBackdropBorderColor（本客户端**没有**这两个读值口 → 调了静默 nil）。
(function () {
  const strip = (s) => s.split(/\r?\n/).map(function (l) { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
  const tb = strip(fs.readFileSync(path.join(__dirname, 'Toolbox.lua'), 'utf8'));
  const bad = [];
  if (tb.indexOf('SetBackdrop') < 0) bad.push('没有用 SetBackdrop（圆角边贴图没处挂）');
  if (tb.indexOf('UI-Tooltip-Border') < 0) bad.push('没有用客户端的圆角边贴图 UI-Tooltip-Border');
  if (tb.indexOf('edgeFile') < 0) bad.push('backdrop 表里没给 edgeFile');
  const me = tb.match(/TB_MENU_EDGE\s*=\s*([0-9.]+)/);
  if (!me || !/^[0-9]+$/.test(me[1])) bad.push('TB_MENU_EDGE 必须是整数常量（实测小数栅格化不可靠）: ' + (me && me[1]));
  const m = tb.match(/edgeSize\s*=\s*([A-Za-z0-9_.]+)/);
  if (!m) bad.push('没有 edgeSize');
  else if (!/_EDGE$/.test(m[1]) && !/^[0-9]+$/.test(m[1])) bad.push('edgeSize 不是整数常量: ' + m[1]);
  if (tb.indexOf('SetBackdropBorderColor') < 0) bad.push('没有 SetBackdropBorderColor（边框会保持客户端默认色）');
  // ★边框色现在走**单一常量**（TB_MENU_COLORS.borderRGBA）→ 两边都要钉：常量本身是白色 + 调用点真的用它
  const bwDef = tb.match(/borderRGBA\s*=\s*\{\s*([0-9.]+),\s*([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\s*\}/);
  if (!bwDef || Number(bwDef[1]) < 0.9 || Number(bwDef[2]) < 0.9 || Number(bwDef[3]) < 0.9 || Number(bwDef[4]) < 0.5) bad.push('边框色常量不是白色高亮: ' + (bwDef && bwDef.slice(1).join('/')));
  if (tb.indexOf('SetBackdropBorderColor, f, TB_MENU_COLORS.borderRGBA') < 0) bad.push('调用点没走白色边框常量（写死别的色也能过）');
  if (tb.indexOf('GetBackdrop') < 0) bad.push('没有 GetBackdrop 读回确认（挂没挂上不可知）');
  if (tb.indexOf('kind = "flat"') < 0 && tb.indexOf('edgeTex') < 0) bad.push('没有「挂不上就退回四条平边」的退化路径');
  if (/GetBackdropColor|GetBackdropBorderColor/.test(tb)) bad.push('调了本客户端不存在的读值口 GetBackdropColor/GetBackdropBorderColor');
  if (bad.length) { console.log('MENU ROUND CHROME CHECK: FAIL - ' + bad.join('; ')); process.exit(1); }
  console.log('MENU ROUND CHROME CHECK: 原生圆角边贴图 + 整数 edgeSize + 白色边框色 + 读回确认 + 平边退化');
})();

// ===== EXAMPLES TOC CHECK（1.71.2）：模版数据文件必须都在 .toc 里，且顺序 = 选单顺序 =====
// 背景：模版数据从 EvalHelp.lua 拆到 examples/*.lua，靠 EvalHelp.toc 载入（本客户端没有文件读取 API）。
//   → 「新增一个职业模版」现在要动两处：磁盘上的文件 + .toc 里的一行。
//   漏掉任何一处都是静默的：漏 .toc = 模版选单里永远少一组（不报错）；漏文件 = 载入报错或少内容。
// 判据：磁盘 <-> .toc 集合相等（两个方向都查）+ .toc 顺序给出预期职业顺序 + 数据不许搬回生产文件 + 载入顺序。
(function () {
  const dir = path.join(__dirname, "examples");
  if (!fs.existsSync(dir)) { console.log("EXAMPLES TOC CHECK: FAIL - examples/ directory is missing"); process.exit(1); }
  const onDisk = fs.readdirSync(dir).filter(f => f.slice(-4) === ".lua").sort();
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8").split(/\r?\n/).map(s => s.trim());
  const listed = toc.filter(l => /^examples[\\/].+\.lua$/.test(l)).map(l => l.replace(/^examples[\\/]/, ""));
  const missing = onDisk.filter(f => listed.indexOf(f) < 0);
  const ghost = listed.filter(f => onDisk.indexOf(f) < 0);
  if (missing.length || ghost.length) {
    console.log("EXAMPLES TOC CHECK: FAIL - disk/toc mismatch; not-listed=[" + missing.join(",") + "] not-on-disk=[" + ghost.join(",") + "]");
    process.exit(1);
  }
  // ★1.71.3 新增 4 个职业组（牧师/德鲁伊/术士/萨满）+ 1 个功能组（队伍/团队）。
  const expect = ["战士", "法师", "通用法系", "通用", "盗贼", "猎人", "骑士", "牧师", "德鲁伊", "术士", "萨满", "队伍/团队"];
  const got = listed.map(f => { const m = fs.readFileSync(path.join(dir, f), "utf8").match(/cls\s*=\s*"([^"]+)"/); return m ? m[1] : "?"; });
  if (got.join(",") !== expect.join(",")) {
    console.log("EXAMPLES TOC CHECK: FAIL - toc order gives [" + got.join("/") + "], expected [" + expect.join("/") + "]");
    process.exit(1);
  }
  // ① 模版数据只能住在 examples/：别的生产文件里再出现 cls = " 就是「又搬回去了 / 多了一份」
  //   （同一个东西两份真值，正是本项目反复踩的坑：改一处漏一处、后写的静默获胜）。
  const prodFiles = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua"];
  const leaked = prodFiles.filter(f => { const p = path.join(__dirname, f); return fs.existsSync(p) && /cls\s*=\s*"/.test(fs.readFileSync(p, "utf8")); });
  if (leaked.length) { console.log("EXAMPLES TOC CHECK: FAIL - template data leaked back into " + leaked.join(",")); process.exit(1); }
  // ② 载入顺序：examples 必须排在 EvalHelp.lua 之后（引擎里的初始化先跑）。
  //   顺序颠倒了也不会丢数据（那行是 `or {}`），可一旦有人把它写成 `= {}`，颠倒就会静默清空全部模版
  //   —— 所以把顺序本身也钉住，别让这个前提悄悄漂掉。
  const iEngine = toc.findIndex(l => l === "EvalHelp.lua");
  const iFirst = toc.findIndex(l => /^examples[\\/]/.test(l));
  if (iEngine < 0 || iFirst < 0 || iFirst < iEngine) {
    console.log("EXAMPLES TOC CHECK: FAIL - examples must be listed AFTER EvalHelp.lua (engine=" + iEngine + " firstExample=" + iFirst + ")");
    process.exit(1);
  }
  console.log("EXAMPLES TOC CHECK: " + listed.length + " example data files, order = " + got.join(" / "));
})();

// ===== QUEST TOC CHECK（1.75.0 / 1.75.9）：任务线数据/逻辑文件必须在 .toc 里、且在 DataSearch 之前 =====
// 背景：quest/ 是**独立目录**（脚本 + 数据 + 逻辑），插件只靠 .toc 载入（本客户端没有文件读取 API）。
//   漏 .toc = 任务线检索永远查不到（不报错，静默失效）；顺序错 = DataSearch 里 EVAL_QC_* 还是 nil（同样静默）。
//   旧判据只看 examples/，quest/ 是新目录 —— 不补这一道就是「检查存在 ≠ 覆盖到位」的老坑。
//   ★1.75.9 新增 QuestBulk.lua（全量 10-60+ 任务/装备），漏它 = 装备视图静默退回只有策展链那几十件。
(function () {
const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8").split(/\r?\n/).map(s => s.trim());
const need = ["quest\\QuestData.lua", "quest\\QuestBulk.lua", "quest\\QuestChains.lua"];
const pos = [];
for (const f of need) {
  const i = toc.indexOf(f);
  if (i < 0) { console.log("QUEST TOC CHECK: FAIL - EvalHelp.toc 没列 " + f); process.exitCode = 1; return; }
  pos.push(i);
}
const ds = toc.indexOf("DataSearch.lua");
if (ds < 0) { console.log("QUEST TOC CHECK: FAIL - EvalHelp.toc 没列 DataSearch.lua"); process.exitCode = 1; return; }
if (!pos.every(p => p < ds)) {
  console.log("QUEST TOC CHECK: FAIL - quest/ 数据与逻辑必须排在 DataSearch.lua 之前（否则检索逻辑读到 nil）");
  process.exitCode = 1; return;
}
if (!(pos[0] < pos[1] && pos[1] < pos[2])) {
  console.log("QUEST TOC CHECK: FAIL - quest/ 顺序必须是 QuestData → QuestBulk → QuestChains（数据→逻辑）");
  process.exitCode = 1; return;
}
// 磁盘 ↔ .toc 双向一致（quest/ 下的 .lua 全部要列；列出的必须真在磁盘）
const qdir = path.join(__dirname, "quest");
if (!fs.existsSync(qdir)) { console.log("QUEST TOC CHECK: FAIL - quest/ 目录缺失"); process.exitCode = 1; return; }
const onDisk = fs.readdirSync(qdir).filter(f => f.slice(-4) === ".lua").map(f => "quest\\" + f);
const listed = toc.filter(l => /^quest[\\/].+\.lua$/.test(l));
const missing = onDisk.filter(f => listed.indexOf(f) < 0);
const ghost = listed.filter(f => onDisk.indexOf(f) < 0);
if (missing.length) { console.log("QUEST TOC CHECK: FAIL - 磁盘有但 .toc 没列: [" + missing.join(",") + "]"); process.exitCode = 1; return; }
if (ghost.length) { console.log("QUEST TOC CHECK: FAIL - .toc 列了但磁盘没有: [" + ghost.join(",") + "]"); process.exitCode = 1; return; }
// 生成物必须是**纯数据**（解耦约定：脚本产物只放表，逻辑在 QuestChains.lua）
for (const f of ["QuestData.lua", "QuestBulk.lua"]) {
  const dataSrc = fs.readFileSync(path.join(__dirname, "quest", f), "utf8").replace(/--[^\n]*/g, "");
  if (/\bfunction\b/.test(dataSrc)) {
    console.log("QUEST TOC CHECK: FAIL - " + f + " 里出现 function（生成物必须是纯数据）");
    process.exitCode = 1; return;
  }
}
// 全量数据必须真的有货（空表 = 界面看着像坏了，且没有任何报错）
{
  const bulk = fs.readFileSync(path.join(__dirname, "quest", "QuestBulk.lua"), "utf8");
  const sect = (name) => {
    const m = bulk.match(new RegExp("\\n" + name + "=\\{\\r?\\n([\\s\\S]*?)\\r?\\n\\},"));
    return m ? m[1] : "";
  };
  const qRows = (sect("q").match(/^\s*\[\d+\]=/gm) || []).length;
  const iRows = (sect("i").match(/^\s*\[\d+\]=/gm) || []).length;
  const sRows = (sect("s").match(/^\s*"/gm) || []).length;
  if (qRows < 200) { console.log("QUEST TOC CHECK: FAIL - QuestBulk 任务行只有 " + qRows + " 条（10-60 带装备奖励的任务应 ≥200）"); process.exitCode = 1; return; }
  if (iRows < 300) { console.log("QUEST TOC CHECK: FAIL - QuestBulk 物品行只有 " + iRows + " 条（绿装+奖励物品应 ≥300）"); process.exitCode = 1; return; }
  if (sRows < 20) { console.log("QUEST TOC CHECK: FAIL - QuestBulk 自动任务线只有 " + sRows + " 条（站点系列应 ≥20，含 30-60 与开门线）"); process.exitCode = 1; return; }
  if (!/EVAL_QC_BULK\s*=/.test(bulk) || !/meta=\{/.test(bulk)) { console.log("QUEST TOC CHECK: FAIL - QuestBulk 缺 EVAL_QC_BULK/meta"); process.exitCode = 1; return; }
  // 分隔符纪律：生成器保证名字里没有 '|'，但**判定要独立**（自己再扫一遍 s/q/i 的字段数）
  const badLine = (sect("q").match(/^\s*\[\d+\]="([^"]*)"/gm) || []).find(l => (l.match(/\|/g) || []).length !== 4);
  if (badLine) { console.log("QUEST TOC CHECK: FAIL - QuestBulk 任务行字段数不对（应 4 个分隔符）: " + badLine); process.exitCode = 1; return; }
}
// ★1.75.9 实测踩到的坑：test_engine.js 里有 **5 处硬编码载入清单**，新增 quest/QuestBulk.lua 时
//   一处没加 → 测试环境里「全量数据」恒为 nil（界面退回策展兜底），断言看着像**数据不对**。
//   把「每处清单都必须与 toc 的 quest/ 逐个一致（含顺序）」变成判据。
{
  const eng = fs.readFileSync(path.join(__dirname, "test_engine.js"), "utf8");
  const tocQuest = toc.filter(l => /^quest[\\/].+\.lua$/.test(l)).map(l => l.replace(/\\/g, "/"));
  const listRe = /\[((?:['"][^'"]*['"]\s*,\s*)*['"]quest\/QuestData\.lua['"][^\]]*)\]/g;
  let m, checked = 0;
  while ((m = listRe.exec(eng)) !== null) {
    const order = (m[1].match(/['"]quest\/[^'"]+\.lua['"]/g) || []).map(s => s.replace(/['"]/g, ""));
    checked++;
    if (order.join(",") !== tocQuest.join(",")) {
      console.log("QUEST TOC CHECK: FAIL - test_engine.js 第 " + checked + " 处硬编码清单与 toc 的 quest/ 不一致：清单=[" +
        order.join(",") + "] toc=[" + tocQuest.join(",") + "]（新增模块必须**每处**都加）");
      process.exitCode = 1; return;
    }
  }
  if (checked < 5) { console.log("QUEST TOC CHECK: FAIL - 只找到 " + checked + " 处 quest/ 载入清单（应为 5 处，形状变了要人工核对）"); process.exitCode = 1; return; }
}
console.log("QUEST TOC CHECK: quest/ 三文件在 toc 且顺序 Data→Bulk→Chains 且在 DataSearch 之前 + 磁盘双向一致 + 生成物纯数据且有货");
})();

// ===== QUEST WIRING CHECK（1.75.0）：任务线检索的接线点，漏一处都**不报错、只是查不到** =====
// 背景：任务线是「自带数据 + 只在数据检索里用」的解耦设计 —— 数据进了 toc 不代表能用：
//   ① DataSearch 没有 chain 分支 → 选「任务线」过滤永远空（不报错）
//   ② 空查询没放行 → 首屏永远空白（用户以为坏了）
//   ③ 结果行 id 用字符串键 → 与数字 id 在排序里混比（attempt to compare number with string）
//   ④ 语言键是**运行时拼**的（"DS_T_"..kind）→ LANG KEY CHECK 扫不到，缺键时界面直接显示键名
//   ⑤ 搜索与详情走了两套顺序 → 点进去打开的是**另一条链**（最阴的一种错）
//   ⑥ dsChainInto 一旦依赖 dsDb()，UnrealQuest 缺席时任务线也一起失效（解耦白做）
(function () {
  const ds = fs.readFileSync(path.join(__dirname, "DataSearch.lua"), "utf8");
  const qcPath = path.join(__dirname, "quest", "QuestChains.lua");
  if (!fs.existsSync(qcPath)) { console.log("QUEST WIRING CHECK: FAIL - quest/QuestChains.lua 缺失"); process.exitCode = 1; return; }
  const qc = fs.readFileSync(qcPath, "utf8");
  const bad = [];
  if (!/if ftype == "chain" then/.test(ds)) bad.push("DataSearch 没有 ftype==chain 分支");
  if (!/if kind == "chain" then return dsChainDetail\(id\) end/.test(ds)) bad.push("EVAL_DS_DETAIL 没有 chain 分支");
  if (!/\(DS\.filter == "chain"\)/.test(ds)) bad.push("空查询没给任务线放行（首屏会永远空白）");
  if (!/if ql == "" then/.test(ds)) bad.push("chain 分支没有「空查询=列全部」处理");
  if (!/id = h\.idx/.test(ds)) bad.push("chain 结果行没用数字位次 h.idx（会与数字 id 混排比较）");
  if (!/if DS\.filter == "chain" then/.test(ds)) bad.push("切换过滤到任务线后没有立即出首屏");
  if (!/DS_F_CHAIN/.test(ds)) bad.push("过滤下拉没接任务线（DS_F_CHAIN）");
  const fn = ds.match(/local function dsChainInto\(out, ql\)([\s\S]*?)\r?\nend\r?\n/);
  if (!fn) bad.push("找不到 dsChainInto");
  else if (/dsDb\(\)/.test(fn[1])) bad.push("dsChainInto 依赖 dsDb（UnrealQuest 缺席时任务线会一起失效）");
  if (!/local sorted = EVAL_QC_LIST\(filter\)/.test(qc)) bad.push("搜索没走 EVAL_QC_LIST(filter)（与详情不同序 → 点进去是另一条链）");
  if (!/return qcDetailOf\(qcChainAt\(key\)\)/.test(qc)) bad.push("详情没走 qcChainAt（位次↔键两条路会分叉）");
  // ★1.75.8 种类**多选**过滤：判定只准有一处（数据层），界面传集合、不复刻
  // ★1.75.18 装备视图走 EVAL_QC_KIND_PASS（全局单一来源），任务线视图走 qcRecKindsOK → 同一个 PASS
  if (!/EVAL_QC_KIND_PASS\(f\.kinds, EVAL_QC_ITEM_KIND\(it\)\)/.test(qc)) bad.push("装备视图没按 kinds 集合过滤（界面传了也白传）");
  if (!/local function qcRecKindsOK\(c, kset\)/.test(qc)) bad.push("缺 qcRecKindsOK（任务线的种类筛选没落数据层）");
  if (!/if hit and lvOK\(c\) and qcRecKindsOK\(c, kinds\) then/.test(qc)) bad.push("策展链搜索没接种类筛选");
  if (!/if qcRecKindsOK\(rec, kinds\) then/.test(qc)) bad.push("自报系列搜索没接种类筛选");
  if (!/function EVAL_QC_KIND_PASS\(set, k\)/.test(qc)) bad.push("kinds 判定没抽成全局单一来源 EVAL_QC_KIND_PASS");
  if (!/return set\[k\] and true or false/.test(qc)) bad.push("kinds 集合判定没写成显式布尔（会返回 nil/true 混值）");
  if (!/if not any then return true end/.test(qc)) bad.push("kinds 空集没当成「不过滤」（一个都没勾会变成什么都不显示）");
  // ★1.75.9 全量数据层（QuestBulk.lua）：读取接口 + 统一入口 + 全量优先/策展兜底
  for (const fn of ["EVAL_QC_BULK_READY", "EVAL_QC_BULK_QUEST", "EVAL_QC_BULK_ITEM", "EVAL_QC_BULK_ITEM_ROWS",
                    "EVAL_QC_BULK_SOURCES", "EVAL_QC_SERIES_LIST", "EVAL_QC_SERIES_DETAIL", "EVAL_QC_SERIES_FACTION"]) {
    if (!(new RegExp("function " + fn + "\\(")).test(qc)) bad.push("数据层缺 " + fn + "（全量数据/自动任务线接口）");
  }
  if (!/function EVAL_QC_ITEM_ROWS\(filter\)\r?\n\s*if EVAL_QC_BULK_READY\(\) then return EVAL_QC_BULK_ITEM_ROWS\(filter\) end\r?\n\s*return qcChainItemRows\(filter\)/.test(qc)) {
    bad.push("EVAL_QC_ITEM_ROWS 没写成「全量优先 + 策展兜底」（两处各写一份判定迟早漂移）");
  }
  if (!/local function qcChainItemRows\(filter\)/.test(qc)) bad.push("策展派生的兜底函数没保留（全量缺席时界面会空白）");
  if (!/local function qcCurItemIndex\(\)/.test(qc)) bad.push("策展链反查没走反向索引（EVAL_QC_ITEM_CHAINS 会退回慢路径/形状不符）");
  if (/function EVAL_QC_ITEM_CHAINS\(itemId\)\r?\n\s*local rows = EVAL_QC_ITEM_ROWS/.test(qc)) {
    bad.push("EVAL_QC_ITEM_CHAINS 又借道 EVAL_QC_ITEM_ROWS（全量行形状不同 → 静默 nil）");
  }
  if (!/string.find\(s, "\|", p, true\)/.test(qc)) bad.push("紧凑串解析没用 plain 查找（'|' 在模式里不是普通字符）");
  if (!/local b = \(type\(EVAL_QC_BULK_ITEM\) == "function"\) and EVAL_QC_BULK_ITEM\(id\) or nil/.test(qc)) {
    bad.push("EVAL_QC_ITEM 没有「策展表没有 → 退回全量物品表」的兜底（30-60 装备详情会查不到）");
  }
  // ★1.75.10 稀有度（魔兽品质色）+ 按等级排序：判定与颜色都在数据层，界面只准读
  {
    const pal = { LEG: [1.00, 0.50, 0.00], EPIC: [0.64, 0.21, 0.93], RARE: [0.00, 0.44, 0.87],
      UNCOMMON: [0.12, 1.00, 0.00], COMMON: [1.00, 1.00, 1.00], POOR: [0.62, 0.62, 0.62] };
    for (const k of Object.keys(pal)) {
      const re = new RegExp("(?<![A-Z_])" + k + "\\s*=\\s*\\{\\s*([\\d.]+)\\s*,\\s*([\\d.]+)\\s*,\\s*([\\d.]+)\\s*\\}");
      const m = qc.match(re);
      if (!m) { bad.push("稀有度调色板缺 " + k); continue; }
      const got = [Number(m[1]), Number(m[2]), Number(m[3])];
      if (got.some((v, i) => Math.abs(v - pal[k][i]) > 0.005)) {
        bad.push("稀有度 " + k + " 不是魔兽品质色（实际 " + got.join(",") + "，应为 " + pal[k].join(",") + "）");
      }
    }
    if (!/function EVAL_QC_RARITY\(rec\)/.test(qc)) bad.push("缺 EVAL_QC_RARITY（稀有度单一来源）");
    if (!/function EVAL_QC_RARITY_RGB\(token\)/.test(qc)) bad.push("缺 EVAL_QC_RARITY_RGB 读值口");
    if (!/local QC_LEG_KEYS = \{ "雷霆之怒"/.test(qc)) bad.push("传说关键词表没了（橙色档会全灭 —— 用户点名「史诗风剑之类」）");
    if (!/local function qcHasAny\(hay, keys\)/.test(qc)) bad.push("稀有度关键词匹配没走 qcHasAny（Lua 模式里 | 不是交替，必须 plain 逐词）");
    // 排序：等级第一键（列表与自动任务线两处都要）；旧「开门优先」写法已被用户反转
    if (!/if a\.lo ~= b\.lo then return a\.lo < b\.lo end\r?\n\s*if a\.r ~= b\.r then return a\.r < b\.r end/.test(qc)) {
      bad.push("EVAL_QC_LIST 不是「等级 → 稀有度」排序（用户要求任务线也按等级排序）");
    }
    // ★只看**自动任务线**那一段的排序（装备行的「武器优先」排序是另一回事，别误伤）
    {
      const serFn = qc.match(/function EVAL_QC_SERIES_LIST\(\)([\s\S]*?)\r?\nend\r?\n/);
      if (!serFn) bad.push("找不到 EVAL_QC_SERIES_LIST");
      else {
        if (!/if a\.lo ~= b\.lo then return a\.lo < b\.lo end/.test(serFn[1])) bad.push("自动任务线没按等级排序");
        if (/open and 0 or 1/.test(serFn[1]) || /a\.t ~= b\.t then return a\.t < b\.t/.test(serFn[1])) {
          bad.push("自动任务线排序退回「开门优先 / 档位优先」（已被用户「按等级排序」反转）");
        }
      }
    }
    if (!/qs = sids, open = s\.open/.test(qc)) bad.push("EVAL_QC_SEARCH 的系列行没带 qs/open（稀有度会判成普通）");
    if (!/open = \(p\[6\] == "1"\), steps = steps, qs = sids,/.test(qc)) bad.push("EVAL_QC_SERIES_LIST 的记录没带 qs（稀有度拿不到步骤数）");
  }
  // 运行时拼键的四个语言键：LANG KEY CHECK 只看字面量，扫不到这些
  for (const lg of ["zhCN", "enUS", "ruRU"]) {
    const p = path.join(__dirname, "Locales", lg + ".lua");
    if (!fs.existsSync(p)) { bad.push("缺语言包 " + lg); continue; }
    const loc = fs.readFileSync(p, "utf8");
    for (const k of ["DS_F_CHAIN", "DS_T_CHAIN", "DS_CHAIN_REWARD", "DS_CHAIN_STEPS"]) {
      if (!(new RegExp("\\b" + k + "\\s*=")).test(loc)) bad.push(lg + " 缺语言键 " + k);
    }
  }
  if (bad.length) {
    console.log("QUEST WIRING CHECK: FAIL - " + bad.join("；"));
    process.exitCode = 1;
    return;
  }
  console.log("QUEST WIRING CHECK: chain 两分支 + 空查询放行 + 数字位次 id + 过滤/语言四键 + 搜索详情同序 + 不依赖 UnrealQuest + 种类多选只判定一处 + 稀有度调色板/按等级排序");
})();

// ===== QUEST PANEL CHECK（1.75.1）：任务线推荐弹窗的接线/规程/布局，漏一处都是**静默失效** =====
// 背景（v1 的真实事故，逐条对应下面的判据）：
//   ① 控件用进它自己的构造参数 → 闭包读到**全局 nil** → 点按钮当场红字（DataSearch:2840）
//   ② 按钮 label 传空串 → 界面上一排**空白按钮**（用户截图）
//   ③ 只设 strata 不设 frameLevel → 被父窗行按钮盖住、点不到
//   ④ 弹窗 OnHide 不收全局下拉 → 孤儿下拉浮在别处
//   ⑤ 两视图没整块 Show/Hide → 切详情后列表还叠着；⑥ 默认不 Hide → 载入就弹
//   ⑦ 底部按钮与详情行重叠 → 末行按钮被文字压住（用户截图）
//   ⑧ 装备条目没带 item id / 直连没走已验证入口 → 「装备↔任务」这条主线断掉
(function () {
  const ds = fs.readFileSync(path.join(__dirname, "DataSearch.lua"), "utf8");
  const bad = [];
  if (!/DS\.qlBtn = dsBtn\(root, LX \+ 310 \+ 214 \+ 8/.test(ds)) bad.push("任务线推荐按钮不在「地图标注」右侧（应为 LX+310+214+8）");
  if (!/table\.insert\(DS\.searchWidgets, DS\.qlBtn\.btn\)/.test(ds)) bad.push("按钮没进 Tab 显隐清单（切页后会留在屏上）");
  if (!/table\.insert\(DS\.controlRow\.buttons, \{ name = "任务线推荐"/.test(ds)) bad.push("按钮没登记到控制行几何表");
  if (!/SetFrameStrata, qp, "DIALOG"/.test(ds)) bad.push("弹窗没设 DIALOG strata");
  if (!/qp:SetFrameLevel\(\(root:GetFrameLevel\(\) or 1\) \+ 100\)/.test(ds)) bad.push("弹窗没显式抬 frameLevel（只设 strata = 点不到）");
  if (!/RegisterForDrag, qpBar, "LeftButton"/.test(ds)) bad.push("拖动柄没注册 RegisterForDrag");
  if (!/RegisterForClicks, qpBar, "LeftButtonUp"/.test(ds)) bad.push("拖动柄没注册 RegisterForClicks");
  if (!/OnDragStart[\s\S]{0,260}?StartMoving[\s\S]{0,120}?StopMovingOrSizing[\s\S]{0,120}?StartMoving/.test(ds)) bad.push("拖动没走 warm-up 两步");
  if (!/SetScript\("OnHide"[\s\S]{0,200}?EVAL_DD_HIDE/.test(ds)) bad.push("弹窗 OnHide 没收起全局下拉");
  if (!/listWidgets[\s\S]{0,200}?detWidgets/.test(ds)) bad.push("两视图没走整块显隐清单");
  if (!/qp:Hide\(\) -- 默认关/.test(ds)) bad.push("弹窗默认没隐藏");
  if (!/if not EVAL_QC_ITEM\(itemId\) then return end/.test(ds)) bad.push("装备详情没做诚实失败（查不到也切视图）");
  if (!/if not EVAL_QC_DETAIL\(key\) then return end/.test(ds)) bad.push("任务线详情没做诚实失败");
  if (!/EVAL_WHEEL_DIR\(a, b\)/.test(ds)) bad.push("弹窗滚轮没走方向单一来源 EVAL_WHEEL_DIR");
  // ② 不许有空白按钮：dsBtn(qp, ..., "") 一律 FAIL
  if (/dsBtn\(qp, [^\n]*?,\s*""/.test(ds)) bad.push("弹窗里有空白按钮（label 传了空串）");
  // ① 控件不许用进它自己的构造参数（v1 事故：闭包读到全局 nil）
  const selfRef = ds.match(/local (\w+) = dsBtn\(qp[^\n]*\b\1\b/);
  if (selfRef) bad.push("控件 " + selfRef[1] + " 被用进了自己的构造参数（闭包会读到全局 nil —— v1 红字事故）");
  // ⑧ 装备主线：行带 item、点击进装备详情、直连走 EVAL_DS_SEARCH_NAME
  if (!/row\.item = h\.id/.test(ds)) bad.push("装备行没带物品 ID");
  if (!/EVAL_QP_ITEM_DETAIL\(row\.item\)/.test(ds)) bad.push("装备行点击没进装备详情");
  const goDs = ds.match(/function EVAL_QP_GOTO_DS\(\)([\s\S]*?)\n  end/);
  if (!goDs || !/EVAL_DS_SEARCH_NAME/.test(goDs[1])) bad.push("直连数据检索没走 EVAL_DS_SEARCH_NAME（已验证入口）");
  if (!/EVAL_QC_ITEM_CHAINS/.test(ds)) bad.push("装备详情没反查来源任务线（用户核心需求）");
  // 用户要求：任务节点放大镜（按任务名直达数据检索）+ 阵营严格三分类
  // ★1.75.3 用户指定：放大镜用**本插件自带**素材（图标库/数据检索同一个 database 图标）
  if (!/media\\\\icons\\\\database/.test(ds)) bad.push("放大镜没用本插件自带的 database 素材");
  if (!/QP_ZOOM_ICON/.test(ds)) bad.push("放大镜素材没走常量");
  // ★反向哨兵：放大镜点击**不许关窗**（用户要求保留任务线窗口）
  {
    const zc = ds.match(/zb:SetScript\("OnClick"[\s\S]{0,700}?\n    \}\)/);
    if (zc && /EVAL_QP_HIDE\(\)/.test(zc[0])) bad.push("放大镜点击把弹窗关了（用户要求不关窗）");
    if (!/DS\.qp\.hint/.test(ds)) bad.push("放大镜没给「已送数据检索」回执");
  }
  if (!/EVAL_DS_SEARCH_NAME\(word\)/.test(ds)) bad.push("放大镜点击没走 EVAL_DS_SEARCH_NAME（按任务名检索）");
  if (!/zoom = \(qn and qn ~= ""\) and qn or nil/.test(ds)) bad.push("步骤行没带任务名（放大镜会查错词）");
  if (!/faction = DS\.qpFact/.test(ds)) bad.push("装备视图没把阵营传进筛选");
  // ★1.75.8 用户要求：「装备筛选种类细分,支持种类子类型.武器子类型支持.并且支持多选.」
  //   ① 选项**由数据现算**（写死种类表＝与数据脱节）② 多选走 multi 下拉 ③ 分组标题 locked ④ 空集=全部
  if (/local QP_KIND = \{ "ALL"/.test(ds)) bad.push("还残留类型三态单选表 QP_KIND（用户要求细分到子类型 + 多选）");
  if (!/kinds = DS\.qpKinds/.test(ds)) bad.push("装备列表没把种类多选集合交给数据层（界面自己复刻判定＝两处漂移）");
  if (!/EVAL_DD_OPEN\(DS\.qp\.f2\.btn, items, function\(pi, on\)/.test(ds)) bad.push("类型筛选没走多选回调 onPick(序号, 是否勾选)");
  if (!/\{ multi = true, selected = sel, locked = locked \}/.test(ds)) bad.push("类型筛选没开 multi 多选（分组标题也会变成可勾行）");
  if (!/if on == true then DS\.qpKinds\[m\.kind\] = true else DS\.qpKinds\[m\.kind\] = nil end/.test(ds)) {
    bad.push("多选回调没写成两步布尔（`on and true or nil` 这类 and/or 写法会把它写反 —— 项目记过这个坑）");
  }
  if (!/if n == 0 then return L\("DS_QP_KIND_ALL"\) end/.test(ds)) bad.push("类型按钮文字没处理「一个都没勾」（会显示空白按钮）");
  // ★1.75.9 用户要求「经典任务线衍生到 30-60 范围」+「任务奖励只要有装备/武器的都采集（单任务也算）」：
  //   ① 等级档到 50+（≥5 档）且**由 QP_LV 现算**（写死四项 = 加档必漏一处）
  //   ② 装备行来源 = **任务名**（全量任务的来源），不再是「策展链名」
  //   ③ 装备详情里来源任务是可跳转行（放大镜）④ 审计入口（以游戏内信息为准）
  {
    const lv = ds.match(/local QP_LV = \{([\s\S]{0,400}?)\n  \}/);
    if (!lv) bad.push("找不到 QP_LV 等级档表");
    else {
      const bands = (lv[1].match(/\{ k = "L\d"/g) || []).length;
      // ★1.75.15 用户要求「等级过滤增加个独立档位 60」⇒ 6 档（L1..L6），50-59 与 60+ 分开
      if (bands < 6) bad.push("等级档只有 " + bands + " 档（用户要求 60 独立成档，应 ≥6 档：L1..L6）");
      if (!/"L5", lo = 50, hi = 59/.test(lv[1])) bad.push("L5 不是 50-59（60 档拆出来就得把 50+ 收成 50-59）");
      if (!/"L6", lo = 60, hi = 999/.test(lv[1])) bad.push("缺独立的 60+ 档（hi=999 才装得下 60-69 的团本/开门任务）");
    }
    if (!/for i = 1, table\.getn\(QP_LV\) do labels\[i\] = L\("DS_QP_LV_" \.\. QP_LV\[i\]\.k\) end/.test(ds)) {
      bad.push("等级下拉没由 QP_LV 现算（写死标签会在加档时漏掉新档）");
    }
    // ★1.75.18 任务线视图的按钮位次 = **F1 等级 · F2 类型（与装备视图同一份种类多选）· F3 阵营**
    //   （用户：「等级筛选按钮移动到最左侧」+「档位过滤使用装备那边的种类过滤」）
    if (!/st\.f1\.text:SetText\(L\("DS_QP_F1_CHAIN"\) \.\. ": " \.\. L\("DS_QP_LV_" \.\. qpLvEntry\(\)\.k\)\)/.test(ds)) {
      bad.push("任务线视图的等级标签没现算（写死档位 = 加档必漏一处）");
    }
    if (!/st\.f2\.text:SetText\(L\("DS_QP_F2_CHAIN"\) \.\. ": " \.\. qpKindLabel\(\)\)/.test(ds)) {
      bad.push("任务线视图的「类型」标签没走种类单一来源 qpKindLabel（档位筛选应已被种类取代）");
    }
    // ★扫描前**摘注释**：上面的说明注释里就写着 `QP_TIER / DS.qpTier`、`local labels` 这些字面量，
    //   不摘会把注释当代码（本项目已因同类问题误报过两次）。
    const dsNoC = ds.replace(/--[^\n]*/g, "");
    if (/QP_TIER|DS\.qpTier/.test(dsNoC)) bad.push("档位筛选（QP_TIER / DS.qpTier）已被种类取代，源码里还有残留");
    if (!/if isList then st\.f3\.btn:Show\(/.test(ds)) {
      bad.push("第三个过滤按钮没在两个视图都显示（任务线视图的阵营过滤点不到）");
    }
    // 等级下拉：F1 在**两个视图共用**（不再按 tab 分支）⇒ 处理段里必须只出现一次 QP_LV 标签循环
    {
      const f1m = dsNoC.match(/qpF1\.btn:SetScript\("OnClick"[\s\S]{0,1200}?\n  end\)/);
      if (!f1m) bad.push("找不到 F1（等级筛选）处理段");
      else if (!/for i = 1, table\.getn\(QP_LV\) do labels\[i\] = L\("DS_QP_LV_" \.\. QP_LV\[i\]\.k\) end/.test(f1m[0])) {
        bad.push("F1 处理段没由 QP_LV 现算等级档");
      } else if (!/DS\.qpLv = QP_LV\[pi\]/.test(f1m[0])) {
        bad.push("F1 处理段没把选择写回 DS.qpLv（点了不生效）");
      }
    }
    if (!/EVAL_QC_SEARCH\(q, QP_CHAIN_MAX, \{ faction = DS\.qpFact, kinds = DS\.qpKinds, loMin = lv\.lo, loMax = lv\.hi \}\)/.test(ds)) {
      bad.push("任务线搜索没把等级区间 + 种类集合传进数据层（过滤只改了显示）");
    }
    // 种类菜单**两个视图共用**（不再按 tab 分支）：F2 处理段里应只有一处 EVAL_DD_OPEN
    {
      const f2m = dsNoC.match(/qpF2\.btn:SetScript\("OnClick"[\s\S]{0,1600}?\n  end\)/);
      if (!f2m) bad.push("找不到 F2（类型筛选）处理段");
      else {
        const nDrop = (f2m[0].match(/EVAL_DD_OPEN\(/g) || []).length;
        if (nDrop !== 1) bad.push("F2 处理段里有 " + nDrop + " 个下拉（任务线应共用装备那份种类菜单）");
      }
    }
    if (/labels = \{ L\("DS_F_ALL"\), L\("DS_QP_LV_L1"\)/.test(ds)) bad.push("等级下拉还写着硬编码的四项标签");
    if (!/local nSrc = table\.getn\(h\.quests or \{\}\)/.test(ds)) bad.push("装备行没按「全量任务来源」写来源（用户要求单任务也算来源）");
    if (!/for j = 1, table\.getn\(e\.quests or \{\}\) do if hitName\(e\.quests\[j\]\.n\) then hit = true break end end/.test(ds)) {
      bad.push("装备搜索没命中「来源任务名」（按任务名找装备会查不到）");
    }
    if (!/EVAL_QC_BULK_SOURCES\(id\)/.test(ds)) bad.push("装备详情没列全量来源任务（由装备反查要做哪些任务这条主线断了）");
    if (!/zoom = \(sq\.n ~= ""\) and sq\.n or nil/.test(ds)) bad.push("来源任务行没挂放大镜（点它应该按任务名直达数据检索）");
    if (!/function EVAL_DS_QC_AUDIT\(limit, quiet\)/.test(ds)) bad.push("缺装备审计 EVAL_DS_QC_AUDIT（用户要求审计装备链接是否与游戏内一致）");
    if (!/if tostring\(nm\) == tostring\(e\.it\.n\) then st\.nameOK = st\.nameOK \+ 1/.test(ds)) bad.push("审计没做「游戏内名字 vs 数据名字」对账");
    const ehSrc2 = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
    if (!/ds 任务线 审计/.test(ehSrc2)) bad.push("/eh ds 任务线 审计 命令没接线");
  }
  // ★1.75.10 用户要求：① 任务线按稀有度染色（橙=传说风剑之类）② 奖励行配图标 + 链接 tooltip
  {
    // ① 列表行：稀有度必须来自数据层（界面写死颜色 = 变异存活）
    const chainRow = ds.match(/else\r?\n\s*local c = h\.c or \{\}[\s\S]{0,900}?pcall\(row\.icon\.Hide, row\.icon\)/);
    if (!chainRow) bad.push("找不到任务线列表行的渲染段");
    else {
      if (!/local rt, rr, rg, rb = EVAL_QC_RARITY\(c\)/.test(chainRow[0])) bad.push("任务线行没读数据层稀有度（EVAL_QC_RARITY）");
      if (!/L\("DS_QP_RAR_" \.\. rt\)/.test(chainRow[0])) bad.push("任务线行没打稀有度标签（[档位·稀有度]）");
      if (!/if type\(rr\) == "number" then row\.text:SetTextColor\(rr, rg, rb\)/.test(chainRow[0])) {
        bad.push("任务线行没用稀有度三通道上色（写死颜色 = 用户要的染色机制失效）");
      }
      if (/row\.text:SetTextColor\(0\.92, 0\.88, 0\.76\)\r?\n\s*pcall\(row\.icon\.Hide/.test(chainRow[0])) {
        bad.push("任务线行还留着旧的写死颜色");
      }
    }
    // ①b 详情标题也要按稀有度染色
    if (!/local rt, rr, rg, rb = EVAL_QC_RARITY\(rec and rec\.c or nil\)/.test(ds)) bad.push("任务线详情标题没按稀有度染色");
    // ② 奖励行：图标与热区控件 + 同源图标函数 + tooltip/点击接线
    if (!/local qpDetIcons, qpDetHover = \{\}, \{\}/.test(ds)) bad.push("详情行没有图标/热区控件池");
    // ② 奖励行/来源行/步骤行**统一**由 qpDrawDetailBody 绘制（1.75.11 起——两处各写一份会漂移）
    if (!/local function qpDrawDetailBody\(body\)/.test(ds)) bad.push("缺详情正文统一绘制件 qpDrawDetailBody（两视图各写一份必然漂移）");
    const drawer = ds.match(/local function qpDrawDetailBody\(body\)([\s\S]*?)\n  end\r?\n/);
    if (!drawer) bad.push("找不到 qpDrawDetailBody 函数体");
    else {
      if (!/local tex, isPh = qpItemTexPh\(e\.item\)/.test(drawer[1])) bad.push("奖励行没走 qpItemTexPh（与武器列表同一套图标 + 未扫描时占位）");
      if (!/st\.detItem\[i\] = e\.item/.test(drawer[1])) bad.push("奖励行没记装备 id（tooltip/点击都拿不到）");
      if (!/st\.detZoom\[i\] = e\.zoom/.test(drawer[1])) bad.push("任务名没记进 detZoom（放大镜会查错词）");
      if (!/st\.detPh\[i\] = true/.test(drawer[1])) bad.push("奖励行没记「这是占位图」标记（点击优先刷新会失效）");
      if (!/if e\.item then/.test(drawer[1])) bad.push("绘制件没按「有装备 id」分支上图标/热区");
    }
    // 两个 builder 必须把 item/zoom 填进 body 条目
    if (!/body\[table\.getn\(body\) \+ 1\] = \{ text = txt, r = r, g = g, b = b, item = src\.id \}/.test(ds)) {
      bad.push("任务线详情的奖励条目没带 item（图标/链接 tooltip 都拿不到）");
    }
    if (!/if DS\.qp\.detPh\[zi\] then qpShowLoadingTip\(hb\) else qpItemTooltip\(hb, id\) end/.test(ds)) {
      bad.push("奖励行悬停没分「占位（数据更新中）/ 已扫到（物品链接）」两支");
    }
    if (!/if DS\.qp\.detPh\[zi\] then qpReqPriority\(id\) else EVAL_QP_ITEM_DETAIL\(id\) end/.test(ds)) {
      bad.push("奖励行点击没分「占位→优先刷新 / 已扫到→装备详情」两支");
    }
    if (!/pcall\(st\.detIcons\[i\]\.Hide, st\.detIcons\[i\]\)/.test(ds)) bad.push("qpClearDet 没逐行清图标（行池复用会残留）");
    if (!/pcall\(st\.detHover\[i\]\.Hide, st\.detHover\[i\]\)/.test(ds)) bad.push("qpClearDet 没逐行清热区（行池复用会残留）");
  }
  // ★1.75.11 用户要求：「装备和任务线滚动机制参考抓宠助手的滚动方式，顺滑滚动」
  {
    if (!/if dir ~= 0 then EVAL_QP_SCROLL\(-dir\) end/.test(ds)) bad.push("滚轮没走「1 行/格」的 EVAL_QP_SCROLL（旧实现一格跳整页）");
    if (/OnMouseWheel[\s\S]{0,300}?EVAL_QP_PAGE\(-dir\)/.test(ds)) bad.push("滚轮还挂在整页跳上（用户要求顺滑滚动）");
    if (!/function EVAL_QP_SCROLL\(step\)/.test(ds)) bad.push("缺 EVAL_QP_SCROLL");
    if (!/local QP_ANIM_DECAY, QP_ANIM_SNAP = /.test(ds)) bad.push("缺滑动动画常量（QP_ANIM_DECAY/QP_ANIM_SNAP）");
    if (!/local function qpLayoutRows\(\)/.test(ds)) bad.push("缺 qpLayoutRows（像素错位靠它摆行）");
    if (!/pcall\(qpAnimFrame\.SetScript, qpAnimFrame, "OnUpdate", qpAnimTick\)/.test(ds)) bad.push("动画 tick 没挂上");
    if (!/pcall\(qpAnimFrame\.SetScript, qpAnimFrame, "OnUpdate", nil\)/.test(ds)) bad.push("动画到零没摘钩（会常驻空转）");
    // ★OnUpdate 零参数（1.74.31 实测）：tick 函数**不许带参数**，也绝不许拿参当帧用
    if (!/local function qpAnimTick\(\)/.test(ds)) {
      bad.push("动画 tick 带参数了（本客户端 OnUpdate 不传参 ⇒ 参数恒 nil，绝不能拿它当帧用）");
    }
    if (/SetScript\("OnUpdate", function\(f\)/.test(ds)) bad.push("动画 tick 写成 function(f) 再索引 f（真机 f=nil 当场红字）");
    if (!/pcall\(btn\.ClearAllPoints, btn\)/.test(ds)) bad.push("qpLayoutRows 没有 ClearAllPoints（每帧追加锚点 = 布局漂移）");
    if (!/DS\.qpOff = new\r?\n    qpFillList\(\)\r?\n    qpAnimKick\(\(new - old\) \* QP_ROW_H\)/.test(ds)) {
      bad.push("列表滚动没有「换行 + 像素动画」两件套");
    }
    // 夹取必须**两条分支各一次**（列表 + 详情）：详情那条若丢了，滚过头只能靠绘制件兜底（掩盖问题）
    {
      const sc = ds.match(/function EVAL_QP_SCROLL\(step\)([\s\S]*?)\n  end\r?\n/);
      if (!sc) bad.push("找不到 EVAL_QP_SCROLL 函数体");
      else {
        const clamps = (sc[1].match(/if new > maxOff then new = maxOff end/g) || []).length;
        if (clamps < 2) bad.push("EVAL_QP_SCROLL 的越界夹取只在 " + clamps + " 条分支里（列表/详情各要一次）");
      }
    }
    if (!/if DS\.qpMode == "detail" then/.test(ds)) bad.push("详情视图没接滚轮滚动");
  }
  // ★1.75.12 用户四条：任务等级+黄色感叹号 / 放大镜不红字 / 放大镜自动切 tab / 只检索可见项 + 限频
  {
    const ehSrc3 = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
    const qcSrc3 = fs.readFileSync(path.join(__dirname, "quest", "QuestChains.lua"), "utf8");
    // ② 红字兜底：两处 nil 守卫（真机 `bad argument #1 to 'getn'`）
    if (!/if type\(items\) ~= "table" then return end/.test(ehSrc3)) bad.push("EVAL_DD_OPEN 没有 nil 条目守卫（真机红字兜底）");
    if (!/if type\(items\) ~= "table" then return \{\} end/.test(ehSrc3)) bad.push("DD_FILTER 没有 nil 守卫（getn(nil) 会糊屏）");
    // ① 任务行：黄色感叹号 + 等级
    if (!/local QP_QUEST_ICON = DS_ICON_ROOT \.\. "questIcon"/.test(ds)) bad.push("任务行没定义黄色感叹号素材（照数据检索列表同一张图）");
    if (!/elseif e\.quest then/.test(ds)) bad.push("详情绘制件没有「任务行」分支（感叹号画不出来）");
    if (!/pcall\(st\.detIcons\[i\]\.SetTexture, st\.detIcons\[i\], QP_QUEST_ICON\)/.test(ds)) bad.push("任务行没把感叹号贴到左侧图标槽");
    {
      const questMarks = (ds.match(/quest = true/g) || []).length;
      if (questMarks < 3) bad.push("标记为任务行的只有 " + questMarks + " 处（来源行/链步骤行/任务线步骤行都要）");
    }
    if (!/if lv then txt = txt \.\. "  Lv" \.\. tostring\(lv\) end/.test(ds)) bad.push("步骤行没拼上任务等级（Lv）");
    if (!/function EVAL_QC_QUEST_LEVEL\(id\)/.test(qcSrc3)) bad.push("数据层缺 EVAL_QC_QUEST_LEVEL（拿不到任务等级）");
    // ③ 放大镜 → 自动切到数据检索 tab（照抓宠帮手 EVAL_PH_JUMP 范式）
    if (!/pcall\(EVAL_HELP_CFG_SETTAB, 4\)/.test(ds)) bad.push("放大镜点击没切到数据检索 tab（用户要求自动打开）");
    // ④ 只检索可见项 + 限频
    if (!/DS\.qcReq\.q = \{\}/.test(ds)) bad.push("请求队列没有被**重建**（会累积成「把所有装备顺序问一遍」）");
    if (!/qpReqBegin\(\)          -- ★1\.75\.12 只让「这一屏要画的装备」进请求队列/.test(ds)) bad.push("列表重绘没重置请求队列");
    if (!/qpReqBegin\(\)          -- ★1\.75\.12 详情同理/.test(ds)) bad.push("详情重绘没重置请求队列");
    if (!/local QP_REQ_RATE, QP_REQ_MAX = 2\.0, \d+/.test(ds)) bad.push("请求限频不是 ≥2.0 秒/件（用户要求「不要太频繁」）");
    if (!/function EVAL_QP_REQ_STATE\(\)/.test(ds)) bad.push("缺 EVAL_QP_REQ_STATE 读值口（缓存/队列状态看不到）");
  }
  // ★1.75.10 追加要求：「同个任务线多个装备奖励就都显示，并排在任务标题右边、左对齐」+ 悬停预览链接
  {
    // 这一段在 QUEST PANEL CHECK 里（作用域只有 ds）⇒ 数据层那两个断言要**自己读** QuestChains.lua
    const qcSrc2 = fs.readFileSync(path.join(__dirname, "quest", "QuestChains.lua"), "utf8");
    if (!/function EVAL_QC_CHAIN_REWARDS\(key, max\)/.test(qcSrc2)) bad.push("数据层缺 EVAL_QC_CHAIN_REWARDS（行尾奖励图标拿不到数据）");
    if (!/local QP_RW_MAX, QP_RW_STEP = \d+, \d+/.test(ds)) bad.push("缺奖励图标带常量 QP_RW_MAX/QP_RW_STEP");
    if (!/local rw = \{\}/.test(ds) || !/table\.insert\(qpListWidgets, bj\)/.test(ds)) {
      bad.push("奖励图标槽没建/没进列表显隐清单（切视图会留在屏上）");
    }
    if (!/pcall\(row\.rw\[j\]\.tex\.Hide, row\.rw\[j\]\.tex\)/.test(ds)) bad.push("行填充没逐槽清奖励图标（上一页残留）");
    if (!/row\.rwIds\[j\] = nil/.test(ds)) bad.push("行填充没清 rwIds（装备行会带着旧奖励 id 出 tooltip）");
    if (!/local ids, total = EVAL_QC_CHAIN_REWARDS\(c\.k, QP_RW_MAX\)/.test(ds)) bad.push("任务线行没取奖励列表");
    if (!/local tex, isPh = qpItemTexPh\(ids\[j\]\)/.test(ds)) bad.push("奖励图标没走 qpItemTexPh（与武器列表不同套 ⇒ 用户要的「相同效果」做不到）");
    // ★1.75.18 占位图标（宏 961）：未扫描出的装备不许「什么都不画」
    if (!/local QP_PH_MACRO_ICON = 961/.test(ds)) bad.push("缺占位图标常量（用户指定**宏 961**）");
    if (!/GetMacroIconInfo, QP_PH_MACRO_ICON/.test(ds)) bad.push("占位图标没走游戏内宏图标 API（GetMacroIconInfo(961)）");
    if (!/if isPh then row\.rwPh\[shown\] = true end/.test(ds)) bad.push("行上没记「这一格是占位图」（点击优先刷新会失效）");
    if (!/if isPh then pcall\(row\.rw\[shown\]\.tex\.SetVertexColor, row\.rw\[shown\]\.tex, 0\.55, 0\.55, 0\.55\)/.test(ds)) {
      bad.push("占位图没置灰（与已扫到的图标分不开）");
    }
    if (!/pcall\(row\.rw\[shown\]\.tex\.SetPoint, row\.rw\[shown\]\.tex, "LEFT", row\.btn, "LEFT", px, 0\)/.test(ds)) {
      bad.push("奖励图标没做成「紧跟标题、左对齐」（必须 LEFT 锚 + 现算 px）");
    }
    if (!/local x0 = 22 \+ qpTextWidth\(row\.text, label, 9\) \+ 8/.test(ds)) {
      bad.push("奖励图标起点没按文本宽度现算（会盖住标题或离得太远）");
    }
    if (!/local function qpTextWidth\(fs, label, perChar\)/.test(ds)) bad.push("缺文本宽度单一来源 qpTextWidth");
    if (!/elseif b >= 192 then i = i \+ 2 w = w \+ pc/.test(ds)) bad.push("qpTextWidth 没按 UTF-8 逐字节判宽（中文会被按字节算成 3 倍）");
    if (!/row\.rwMore, "\+" \.\. tostring\(total - shown\)/.test(ds)) bad.push("装不下的奖励没给「+N」如实提示");
    if (!/if row\.rwPh\[slot\] then qpShowLoadingTip\(bj\) else qpItemTooltip\(bj, id\) end/.test(ds)) {
      bad.push("奖励图标悬停没分「占位（数据更新中）/ 已扫到（物品链接）」两支");
    }
    if (!/if row\.rwPh\[slot\] then qpReqPriority\(id\) else EVAL_QP_ITEM_DETAIL\(id\) end/.test(ds)) {
      bad.push("奖励图标点击没分「占位→优先刷新 / 已扫到→装备详情」两支");
    }
    if (!/local function qpReqPriority\(id\)[\s\S]{0,600}?table\.insert\(q, 1, id\)/.test(ds)) {
      bad.push("优先刷新没把装备插到**队首**（用户要求「加入检索队列最前面、优先扫描」）");
    }
  }
  // ★1.75.11 实测事故：「等级筛选点不动」= 处理函数里写了 `local labels`，遮蔽外层 labels ⇒
  //   EVAL_DD_OPEN 收到 nil（下拉建不出来、点了毫无反应）。静态守住这个形状。
  {
    const f1 = ds.replace(/--[^\n]*/g, "").match(/qpF1\.btn:SetScript\("OnClick"[\s\S]{0,2000}?\n  end\)/);
    if (!f1) bad.push("找不到等级筛选的 OnClick 处理段");
    else {
      const block = f1[0];
      // ★1.75.11 实测的「点不动」= 内层 `local labels` 遮蔽外层 ⇒ 这里数**声明次数**：
      //   1 次 = 正常（本段自己建表）；≥2 次 = 遮蔽事故（EVAL_DD_OPEN 收到 nil）。
      const nDecl = (block.match(/local labels/g) || []).length;
      if (nDecl < 1) bad.push("等级筛选处理段没有 `local labels`（标签表没建）");
      if (nDecl > 1) bad.push("等级筛选处理段里 `local labels` 出现 " + nDecl + " 次（内层遮蔽外层 ⇒ 点了没反应）");
      if (!/labels = \{\}/.test(block)) bad.push("等级标签没走「由 QP_LV 现算」的 labels = {}");
    }
  }
  // 稀有度语言键（运行时拼键：LANG KEY CHECK 只看字面量，扫不到 DS_QP_RAR_ .. token）
  for (const lg of ["zhCN", "enUS", "ruRU"]) {
    const p = path.join(__dirname, "Locales", lg + ".lua");
    if (!fs.existsSync(p)) { bad.push("缺语言包 " + lg); continue; }
    const loc = fs.readFileSync(p, "utf8");
    for (const t of ["LEG", "EPIC", "RARE", "UNCOMMON", "COMMON", "POOR"]) {
      if (!(new RegExp("\\bDS_QP_RAR_" + t + "\\s*=")).test(loc)) bad.push(lg + " 缺稀有度语言键 DS_QP_RAR_" + t);
    }
  }
  // ★★★1.75.9 用户实测「图片内的输入框无法输入」：弹窗 EditBox 必须照**主搜索框已验证配方**三件套
  //   ① EnableMouse（本客户端不显式开鼠标 = 收不到点击 = 拿不到焦点 = 一个字都打不进 —— 本次真凶）
  //   ② 点击即聚焦的兜底按钮 ③ 左对齐 + 字体链三级兜底（全失败才启用回声行）
  {
    const ebBlock = ds.match(/local qpEb = CreateFrame\("EditBox"[\s\S]{0,1800}?local qpEbFocus = CreateFrame/);
    if (!ebBlock) bad.push("找不到弹窗 EditBox 的构建段（输入框配方无从校验）");
    else {
      if (!/pcall\(qpEb\.EnableMouse, qpEb, true\)/.test(ebBlock[0])) bad.push("弹窗 EditBox 没显式 EnableMouse（本客户端 = 收不到点击、打不了字）");
      if (!/pcall\(qpEb\.SetJustifyH, qpEb, "LEFT"\)/.test(ebBlock[0])) bad.push("弹窗 EditBox 没左对齐（本客户端默认居中偏右）");
      if (!/Fonts\\\\FZLBJW\.TTF/.test(ebBlock[0])) bad.push("弹窗 EditBox 没有字体链兜底（疑似不渲染时没有回声依据）");
    }
    if (!/local qpEbFocus = CreateFrame\("Button", nil, qp\)/.test(ds)) bad.push("缺「点击即聚焦」兜底按钮（主搜索框同款；没有它点框沿拿不到焦点）");
    if (!/qpEbFocus:SetScript\("OnClick", function\(\) pcall\(qpEb\.SetFocus, qpEb\) end\)/.test(ds)) bad.push("聚焦按钮没挂 SetFocus（点了没反应）");
    if (!/qpEb:SetScript\("OnEnterPressed"/.test(ds)) bad.push("弹窗输入框没有 OnEnterPressed");
    if (!/qpEb:SetScript\("OnEscapePressed"/.test(ds)) bad.push("弹窗输入框没有 OnEscapePressed");
  }
  if (!/put\(L\("DS_QP_KIND_WP"\), true\)/.test(ds) || !/put\(L\("DS_QP_KIND_OT"\), true\)/.test(ds)) {
    bad.push("类型菜单没挂「武器/其它」两个 locked 分组标题");
  }
  if (!/local wp, ot = EVAL_QC_KIND_GROUPS\(\)|if type\(EVAL_QC_KIND_GROUPS\) == "function" then wp, ot = EVAL_QC_KIND_GROUPS\(\) end/.test(ds)) {
    bad.push("类型菜单没走数据层分组的单一来源 EVAL_QC_KIND_GROUPS");
  }
  // ★用户要求（1.75.2）：装备信息只走客户端 API；图标以**游戏内链**为准、少用自定义图标
  if (!/local function qpItemInfo\(id\)/.test(ds)) bad.push("缺 qpItemInfo（应走 GetItemInfo 实测配方）");
  if (!/interface\[\/\\\\\]/.test(ds)) bad.push("图标没按实测配方扫描 interface[/\\] 路径");
  if (/EVAL_ICON_SEM/.test(ds)) bad.push("弹窗里出现 ICON SEM 自造图标（用户要求减少自定义图标）");
  if (!/if tex then return tex end/.test(ds)) bad.push("图标命中判断缺失");
  // ★正则要容忍多变量赋值行（`local QP_REQ_RATE, QP_REQ_MAX = 1.5, 24` 里 QP_REQ_RATE 后面是逗号）——本类坑第二次踩
  if (!/QP_REQ_RATE\s*[,=]/.test(ds)) bad.push("缺限频常量 QP_REQ_RATE（向服务器要物品必须限频）");
  if (!/rawget\(_G, "EVAL_HELP_WTT"\)/.test(ds)) bad.push("请求没走自建隐藏 tooltip（WTT ISOLATION 禁借 GameTooltip 读数）");
  if (!/function EVAL_DS_QC_PROBE/.test(ds)) bad.push("缺 API 探针 EVAL_DS_QC_PROBE");
  if (!/if nm then[\s\S]{0,240}?SetHyperlink/.test(ds)) bad.push("tooltip 没做「客户端认识就用原生详情」");
  if (!/qpItemTooltip\(row\.btn, row\.item\)/.test(ds)) bad.push("装备行悬停没挂装备详情");
  // ★1.75.4 用户要求：翻页=文字按钮（照图标库 IB_PREV/IB_NEXT），放底部 [返回] 旁边左对齐
  if (!/dsBtn\(qp, QP_NAV_X, QP_BOTTOM, QP_BTN_W, L\("IB_PREV"\)/.test(ds)) bad.push("上一页不是「底部左对齐的文字按钮」");
  if (!/dsBtn\(qp, QP_NAV_X \+ QP_BTN_W \+ QP_BTN_GAP, QP_BOTTOM, QP_BTN_W, L\("IB_NEXT"\)/.test(ds)) bad.push("下一页不是「底部左对齐的文字按钮」");
  if (/dsBtn\(qp, QP_W - 48, QP_PAGE_Y, 18, "\^"/.test(ds)) bad.push("还残留图标式翻页按钮（用户要求换文字按钮）");
  // ★1.75.7 用户要求：三个按钮**整体左对齐**，顺序 [上页][下页][← 返回]（返回在下一页右边）
  if (!/local QP_NAV_X = QP_PAD\b/.test(ds)) bad.push("按钮组起点不是内边距（整体左对齐会漂）");
  if (!/local qpBack = dsBtn\(qp, QP_NAV_X \+ \(QP_BTN_W \+ QP_BTN_GAP\) \* 2, QP_BOTTOM/.test(ds)) {
    bad.push("返回按钮没放在「下一页右边」（用户要求顺序 上页·下页·返回）");
  }
  // ★1.75.5 事故：翻页按钮同时进两份互斥清单 ⇒ 被后处理的 detWidgets「Hide」掉、列表视图里整个消失
  if (/table\.insert\(qpListWidgets, qpUp\.btn\)/.test(ds) || /table\.insert\(qpDetWidgets, qpUp\.btn\)/.test(ds)) {
    bad.push("翻页按钮被塞进互斥显隐清单（会被后处理那份 Hide 掉 —— 1.75.5 实测翻页按钮消失）");
  }
  if (!/if st\.navPrev then pcall\(st\.navPrev\.btn\.Show/.test(ds)) bad.push("qpShowView 末尾没显式 Show 翻页按钮");
  if (!/if st\.navNext then pcall\(st\.navNext\.btn\.Show/.test(ds)) bad.push("qpShowView 末尾没显式 Show 下一个翻页按钮");
  // ★1.75.6 用户截图「样式有点重叠」：详情标题/副标题必须**以图标右上为锚、垂直依次排**
  //   （旧写法标题 LEFT 锚在 36 高图标上 = 垂直居中，与副标题同一行 ⇒ 必然压字）
  if (!/qpDetTitle:SetPoint\("TOPLEFT", qpDetIcon, "TOPRIGHT"/.test(ds)) bad.push("详情标题没以图标右上为锚（会垂直居中压住副标题）");
  if (!/qpDetSub:SetPoint\("TOPLEFT", qpDetIcon, "TOPRIGHT"/.test(ds)) bad.push("详情副标题没以图标右上为锚");
  if (/qpDetTitle:SetPoint\("LEFT", qpDetIcon/.test(ds)) bad.push("详情标题又写回「LEFT 锚图标」的旧写法（与副标题重叠）");
  // ★焦点移开必须隐藏装备信息（只复原底色＝残留）
  {
    const lv = ds.match(/row\.btn:SetScript\("OnLeave"[\s\S]{0,700}?\n    end\)/);
    if (!lv || !/GameTooltip\.Hide/.test(lv[0])) bad.push("列表行移开焦点没隐藏装备信息（tooltip 会残留）");
    const ib = ds.match(/qpDetIconBtn:SetScript\("OnEnter"[\s\S]{0,220}?\n  end\)/);
    if (!ib || !/qpItemTooltip/.test(ib[0])) bad.push("详情大图标获取焦点没显示装备信息");
    if (!/qpDetIconBtn:SetScript\("OnLeave"/.test(ds)) bad.push("详情大图标离开没隐藏装备信息");
  }
  if (!/qpShowView\(DS\.qpMode or "list"\)/.test(ds)) bad.push("首次打开没走视图显隐（详情专用控件会在列表视图露着）");
  {
    const ehSrc = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
    if (!/ds 任务线|ds qc/.test(ehSrc)) bad.push("/eh ds 任务线 探针命令没接线");
  }
  {
    const qcSrc = fs.readFileSync(path.join(__dirname, "quest", "QuestChains.lua"), "utf8");
    if (/c\.f ~= f\.faction and c\.f ~= "B"/.test(qcSrc)) bad.push("阵营筛选退回宽松写法（把「共有」并进联盟/部落）");
    if (!/c\.f ~= f\.faction then ok = false end/.test(qcSrc)) bad.push("EVAL_QC_LIST 没有严格阵营筛选");
    if (!/faction and f\.faction ~= "ALL" and c\.f ~= f\.faction then facOK = false end/.test(qcSrc)) bad.push("装备视图没有按阵营过滤链");
    if (!/function EVAL_QC_KIND_LIST/.test(qcSrc)) bad.push("数据层缺种类清单现算 EVAL_QC_KIND_LIST（写死种类表＝与数据脱节）");
    if (!/function EVAL_QC_KIND_GROUPS/.test(qcSrc)) bad.push("数据层缺分组单一来源 EVAL_QC_KIND_GROUPS");
    // ★1.75.17/18 种类唯一来源仍是生成数据的 `k`，但「其它/空」时按**部位**补细分
    //   （用户：「其它 能否细分为 戒指/项链/饰品」）；映射表 + 落回 k 两处都要在。
    if (!/local QC_SLOT_KIND = \{ \["手指"\] = "戒指", \["颈部"\] = "项链", \["饰品"\] = "饰品" \}/.test(qcSrc)) {
      bad.push("缺部位→种类映射 QC_SLOT_KIND（戒指/项链/饰品 细分不了）");
    }
    if (!/local s = QC_SLOT_KIND\[rec\.s or ""\]/.test(qcSrc)) bad.push("种类推导没按部位细分（其它 里仍混着戒指/项链/饰品）");
    if (!/return k\r?\nend/.test(qcSrc)) bad.push("种类没在最后落回生成数据的 k（唯一来源）");
    // ★1.75.15 等级过滤落在数据层，且必须是**区间重叠**（写「lo 落在档内」会让跨档长线在 40-49 档整条消失）
    if (!/local function lvOK\(c\)/.test(qcSrc) || !/\(hi >= lvLo\) and \(lo <= \(lvHi or 999\)\)/.test(qcSrc)) {
      bad.push("EVAL_QC_SEARCH 没按「区间重叠」过滤等级（跨档长线会查不到）");
    }
    // ★1.75.14 用户问「任务线有按照任务最低等级排序吗?」：搜索结果是**两个来源拼接**的，
    //   必须**跨块统一排序**（旧实现两个块各自排好直接拼 ⇒ 第 22/23 条之间 30 → 4 的回头）。
    //   判据 = ① 有统一排序件（装饰排序 dec + 等级键）② **不许**再出现「各自早截断」的旧形状。
    if (!/table\.sort\(dec, function\(a, b\)[\s\S]{0,120}if a\.lo ~= b\.lo then return a\.lo < b\.lo end/.test(qcSrc)) {
      bad.push("EVAL_QC_SEARCH 没有跨块统一排序（两块拼接会 30 → 4 回头）");
    }
    if (/if table\.getn\(out\) < max then\r?\n\s*table\.insert\(out,/.test(qcSrc)) {
      bad.push("EVAL_QC_SEARCH 又变成「边收边截断」（截断必须在统一排序**之后**）");
    }
    // ★1.75.14 自动任务线记录**单一来源**：列表行与详情必须走同一个 qcSeriesRec
    //   （旧实现详情少给 qs ⇒ 同一条线「列表行色 ≠ 详情色」，组 192 ⑦ 抓到）
    if (!/c = qcSeriesRec\(s, i\)/.test(qcSrc) || !/c = qcSeriesRec\(s, idx\)/.test(qcSrc)) {
      bad.push("自动任务线记录不是单一来源（列表行 / 详情各拼一份 ⇒ 行色 ≠ 详情色）");
    }
  }
  // ⑦ 布局：详情最后一行必须在底部按钮之上（用生产常量独立验算，不复刻坐标公式）
  const num = (re) => { const m = ds.match(re); return m ? Number(m[1]) : null; }; // 仍用于读窗口高
  // ★1.75.3 用户要求「滚动区铺满窗口」⇒ 行数**按窗口高度现算**（图标库那种写死 IB_ROWS=9 会留白）
  if (!/function EVAL_QP_ROWS_FOR\(h, top, rowH, tail\)/.test(ds)) bad.push("缺 EVAL_QP_ROWS_FOR（行数必须按窗口高度现算）");
  if (!/local QP_ROWS = EVAL_QP_ROWS_FOR\(/.test(ds)) bad.push("QP_ROWS 没走 EVAL_QP_ROWS_FOR（写死会留白）");
  if (!/local QP_DET_ROWS = EVAL_QP_ROWS_FOR\(/.test(ds)) bad.push("QP_DET_ROWS 没走 EVAL_QP_ROWS_FOR");
  if (/local QP_ROWS = \d+/.test(ds)) bad.push("QP_ROWS 被写死（应现算）");
  const ROWH = num(/local QP_ROW_H = (\d+)/);
  const TOP = num(/local QP_LIST_TOP = (-?\d+)/);
  const H = num(/QP_H = \d+,\s*(\d+)/) || num(/local QP_H = (\d+)/); // ★多变量赋值行：别把 QP_H 读成前一个数
  if (!ROWH || !TOP || !H) bad.push("读不到弹窗布局常量（窗口高/行高/列表顶边）");
  // ★行数自 1.75.3 起**按窗口高度现算**（用户要求铺满）⇒「末行不压底部按钮」改由
  //   组 192 ⑧g 读**真几何**（EVAL_QP_GEOM）负责；静态这边只保证「现算」已接线（见上面的检查）。
  // 运行时拼键的语言键（LANG KEY CHECK 只看字面量，扫不到这些）
  for (const lg of ["zhCN", "enUS", "ruRU"]) {
    const p = path.join(__dirname, "Locales", lg + ".lua");
    if (!fs.existsSync(p)) { bad.push("缺语言包 " + lg); continue; }
    const loc = fs.readFileSync(p, "utf8");
    for (const k of ["DS_QP_TITLE", "DS_QP_TAB_ITEM", "DS_QP_TAB_CHAIN", "DS_QP_GOTO_DS", "DS_QP_SRC",
                     "DS_QP_LV_ALL", "DS_QP_LV_L1", "DS_QP_LV_L2", "DS_QP_LV_L3", "DS_QP_LV_L4",
                     "DS_QP_LV_L5", "DS_QP_LV_L6", "DS_QP_F3_CHAIN",
                     "DS_QP_KIND_ALL", "DS_QP_KIND_WP", "DS_QP_KIND_OT", "DS_QP_F3_ITEM", "DS_QP_ZOOM_TIP"]) {
      if (!(new RegExp("\\b" + k + "\\s*=")).test(loc)) bad.push(lg + " 缺语言键 " + k);
    }
  }
  // ★1.75.13 用户实测报了两件事，两件都属「不报错的静默事故」，只能用源码检查守：
  //   ① 看装备时红字 `attempt to call global 'qpFillList' (a nil value)` → 根因是「局部函数**声明位置**即契约」
  //      （EVAL_QP_SCROLL 排在 `local function qpFillList` 之前 ⇒ 那里捕获的是全局 nil）⇒ 改前向声明。
  //   ② 「任务线最高只有 30 级」→ 根因是列表写死条数上限 × 等级升序 ⇒ 高等级线被整段截掉。
  {
    const qcSrc2 = fs.readFileSync(path.join(__dirname, "quest", "QuestChains.lua"), "utf8");
    // ★扫描前**摘注释**：上面那段修复说明的注释里本身就写着 `local function qpFillList()` 与 `qpFillList()`，
    //   不摘就会把「注释里的字面量」当成代码（本 CHECK 首轮就是这么误报的）。
    const dsNC = ds.replace(/--[^\n]*/g, "");
    const decl = dsNC.search(/local qpFillList\b/);
    const def = dsNC.search(/\r?\n  qpFillList = function\(\)/);
    const scroll = dsNC.search(/function EVAL_QP_SCROLL\(step\)/);
    if (decl < 0) bad.push("缺 qpFillList 前向声明（声明位置一错就抓全局 nil）");
    if (def < 0) bad.push("qpFillList 不是「先声明后赋值」的写法（写回 local function 即回到顺序敏感）");
    if (/local function qpFillList\(\)/.test(dsNC)) bad.push("qpFillList 又写回 local function（前向声明失效）");
    if (decl >= 0 && scroll >= 0 && decl > scroll) bad.push("qpFillList 声明排在 EVAL_QP_SCROLL 之后（真机抓 nil）");
    {
      let m, nBad = 0;
      const re = /qpFillList\(\)/g;
      while ((m = re.exec(dsNC))) { if (decl < 0 || m.index < decl) nBad++; }
      if (nBad > 0) bad.push("有 " + nBad + " 处 qpFillList() 出现在声明之前（真机抓 nil）");
    }
    if (/EVAL_QC_SEARCH\(q, \d/.test(dsNC)) bad.push("任务线列表又写死条数上限（等级升序 ⇒ 高等级线被静默截掉）");
    if (!/EVAL_QC_SEARCH\(q, QP_CHAIN_MAX, /.test(dsNC)) bad.push("任务线列表没走 QP_CHAIN_MAX 单一来源");
    if (!/local QP_CHAIN_MAX = 0\b/.test(dsNC)) bad.push("QP_CHAIN_MAX 必须是 0（不限条数 = 全量浏览）");
    if (!/if max <= 0 then max = math\.huge end/.test(qcSrc2)) bad.push("EVAL_QC_SEARCH 不认 cap≤0=不限（QuestChains 侧）");
  }
  // ★1.75.16 用户实测「任务线当前页**不再检索装备**了」：根因是**请求泵**这一环，
  //   而旧判据只断言「队列 ≤ 一页 / 限频 ≥2s」——泵即使彻底停摆也照样全绿。
  //   四条硬要求：① 泵挂 UIParent（挂弹窗子级时，OnUpdate 只在帧可见时触发 ⇒ 弹窗显隐一异常泵就静静死掉）
  //   ② 工具柄走 Engine 单一来源（读全局名 `EVAL_HELP_WTT` 在「自建失败退化用 GameTooltip」那条路上恒 nil）
  //   ③ 取柄失败**不许消费队列**（旧写法先 remove 再取柄 ⇒ 静默丢件）
  //   ④ 读值口 / 探针必须能看出「泵到底有没有在要」。
  {
    const engSrc = fs.readFileSync(path.join(__dirname, "Engine.lua"), "utf8");
    if (!/function EVAL_WTT_HANDLE\(\)/.test(engSrc)) bad.push("Engine 没导出 EVAL_WTT_HANDLE（工具柄没有单一来源）");
    if (!/local qpPump = CreateFrame\("Frame", nil, UIParent\)/.test(ds)) {
      bad.push("请求泵没挂 UIParent（挂弹窗子级 ⇒ OnUpdate 随弹窗显隐静默停摆）");
    }
    if (/type\(EVAL_WTT_HANDLE\) == "function"\) and EVAL_WTT_HANDLE\(\) or rawget/.test(ds)) {
      bad.push("工具柄用了 `A and f() or 全局`（f() 返 nil 时 Lua 会静默回落，1.73.15 记过这个形状）");
    }
    if (!/if type\(EVAL_WTT_HANDLE\) == "function" then wtt = EVAL_WTT_HANDLE\(\)/.test(ds)) {
      bad.push("工具柄没走 EVAL_WTT_HANDLE（读全局名在「退化用 GameTooltip」时恒 nil ⇒ 泵静默什么也不做）");
    }
    if (!/if not wtt or not may[\s\S]{0,300}?table\.remove\(st\.q, idx\)/.test(ds)) {
      bad.push("取柄失败时仍然消费队列（静默丢件：用户看到「不再检索装备」却查不出原因）");
    }
    if (!/\[请求泵\] 已请求 %d 件/.test(ds)) bad.push("探针没报「请求泵」状态（分不清泵在抽还是泵死了）");
    if (!/req = st\.req or 0, blocked = st\.blocked or 0/.test(ds)) bad.push("读值口没暴露 req/blocked（泵活性不可观测）");
    if (!/pcall\(qpPump\.Show, qpPump\)/.test(ds)) bad.push("请求泵没常驻开启（帧一 Hide，OnUpdate 就不触发 ⇒ 泵可能永远停摆）");
    if (/st\.qcPump:Hide\(\)/.test(ds)) bad.push("EVAL_QP_HIDE 又去 Hide 请求泵（弹窗显隐一漏，泵就静静死掉）");
  }
  if (bad.length) { console.log("QUEST PANEL CHECK: FAIL - " + bad.join("；")); process.exitCode = 1; return; }
  console.log("QUEST PANEL CHECK: 按钮位/清单 + DIALOG&level + 拖动三件套 + OnHide 收下拉 + 两视图整块显隐 + 无空白按钮 + 无自引用 + 装备主线(反查/直连) + 种类多选(数据现算/multi/locked 分组/空集=全部) + 稀有度染色(数据层配色/标签/六语言键) + 奖励行图标与链接 tooltip + 布局不重叠 + 拼键语言键齐");
})();

// ===== LOCAL ORDER CHECK（1.75.13）：局部量「先引用后声明」=====================
// 背景：1.75.12 真机红字 `attempt to call global 'qpFillList' (a nil value)` —— 局部函数的**声明位置**即契约
//   （EVAL_QP_SCROLL 排在 `local function qpFillList` 之前 ⇒ 里面捕获的是全局 nil）。
//   这类事故**不报错**，只在用户面前弹红字；行为断言也照不到「另一种写法同样能跑」的形状
//   ⇒ 用词法作用域分析静态扫**所有载入的 .lua**（审计器自带 --selftest，并已用真实事故形状验证过）。
{
  const { scan } = require("./probe_localorder.js");
  const luaFiles = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8")
    .split(/\r?\n/).map(s => s.trim())
    .filter(s => s && s.charAt(0) !== "#" && /\.lua$/i.test(s))
    .map(s => s.replace(/\\/g, "/"));
  const bad = [];
  for (const f of luaFiles) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    for (const b of scan(fs.readFileSync(p, "utf8"))) {
      bad.push(f + ":" + b.useLine + " " + b.n + "（声明@第 " + b.declLine + " 行）");
    }
  }
  if (bad.length) {
    console.log("LOCAL ORDER CHECK: FAIL - " + bad.slice(0, 6).join("；"));
    process.exitCode = 1;
  } else {
    console.log("LOCAL ORDER CHECK: 无「先引用后声明」的局部量（作用域分析扫 " + luaFiles.length + " 个 .lua）");
  }
}

// ===== STOP ATTACK WIRING CHECK（1.71.3）：新增「特殊行为」时它的判定必须与「取消施法」逐处同列 =====
// ★背景：1.71.3 新增「停止攻击」（与 取消施法 同族：不占动作条的特殊行为）。这类行为要在 7 处接线：
//   引擎 2 处（规则预判 / /eh war 状态总览）+ UI 5 处（亮金 / 缺技能问号 / 光环候选 / 分类标签 ×2）。
//   ★本项目最典型的失败模式就是「改一处漏一处」，而这些接线点**行为上互不牵连**：
//   漏掉 UI 那几处不报错、只是显示不对，行为断言照不到（除非为每一处都写一套 UI 用例）。
// 判据：凡是「cancelCastOf 与 petCmdOf/targetSelOf 同列」或「cancelCastOf 与 stanceOf 同列」的那行，
//   必须同时出现 stopAllOf —— 这两条模式正好命中全部 7 个接线点；
//   而定义处 / wicon / wready / wuse 分支 / 导出处都不含这些邻居函数名，天然不会误伤。
(function () {
  const files = ["Engine.lua", "EvalHelp.lua"];
  const sites = [];
  const bad = [];
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const code = lines[i].split("--")[0];
      if (!/cancelCastOf\s*\(/.test(code)) continue;
      const family = /(petCmdOf|targetSelOf)\s*\(/.test(code) || /stanceOf\s*\(/.test(code);
      if (!family) continue;
      sites.push(f + ":" + (i + 1));
      if (!/stopAllOf\s*\(/.test(code)) bad.push(f + ":" + (i + 1) + " 缺 stopAllOf");
      // ★1.71.3 同类新增：「跟随」也是不占动作条的特殊行为，同样要在**这 7 处**接线
      //   （漏接不报错、只是亮金/缺技能问号/分类标签显示不对，行为断言照不到）。
      if (!/followOf\s*\(/.test(code)) bad.push(f + ":" + (i + 1) + " 缺 followOf");
    }
  }
  // ★1.72.4 「指定等级」让这类名单出现了第 8 个成员，而它同时暴露了**名单被抄了三份**：
  //   引擎闸门 / 亮金白名单 / 缺技能问号白名单 各写了一遍（新增成员时只改一处，另两处静默不同步）。
  //   已把那份名单抽成 Engine.lua 的 **skillNoSlotOk(skill, rank)** 单一来源 → 本检查随之升级为三段：
  //   ① 判据本体必须列全 7 个特殊行为（名字清单不许漏）；
  //   ② 判据必须真的被接线（引擎 + 两个 UI 站点 ≥ 3 处调用）——「定义了没人用」等于没定义；
  //   ③ 老写法不许复活：仍按「一行里 cancelCastOf 与邻居同列 → 必须也有 stopAllOf/followOf」守住剩余站点。
  const eng = fs.readFileSync(path.join(__dirname, "Engine.lua"), "utf8").split(/\r?\n/);
  const defStart = eng.findIndex(l => /^function skillNoSlotOk\s*\(/.test(l));
  if (defStart < 0) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - 找不到单一判据 skillNoSlotOk(skill, rank)（Engine.lua）");
    process.exitCode = 1;
    return;
  }
  let defEnd = defStart;
  while (defEnd < eng.length && !/^end\s*$/.test(eng[defEnd])) defEnd++;
  const defBody = eng.slice(defStart, defEnd + 1).join("\n");
  const members = ["petCmdOf", "targetSelOf", "itemOf", "stanceOf", "cancelCastOf", "stopAllOf", "followOf"];
  const missMem = members.filter(n => defBody.indexOf(n + "(") < 0);
  if (missMem.length || defBody.indexOf("rank") < 0) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - skillNoSlotOk 名单不全（缺 " + missMem.join(",") + (defBody.indexOf("rank") < 0 ? ",rank" : "") + "）");
    process.exitCode = 1;
    return;
  }
  let callers = 0;
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
      const code = line.split("--")[0];
      // 引擎侧叫 skillNoSlotOk，UI 侧是同一函数的本地别名 noSlotOk（两者都算接线）
      if (/(^|[^A-Za-z_])(skillNoSlotOk|noSlotOk)\s*\(/.test(code)) callers++;
    }
  }
  if (callers < 3) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - 单一判据只被调用 " + callers + " 处（引擎闸门 + 亮金 + 缺技能问号 应为 3 处）");
    process.exitCode = 1;
    return;
  }
  if (sites.length < 5) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - expected >=5 remaining wiring sites, found " + sites.length + " (" + sites.join(", ") + ")");
    process.exitCode = 1;
    return;
  }
  if (bad.length) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - special-behaviour wiring missing next to cancelCastOf at: " + bad.join(", "));
    process.exitCode = 1;
    return;
  }
  console.log("STOP ATTACK WIRING CHECK: skillNoSlotOk 名单 7/7 + 被接线 " + callers + " 处 + 其余 " + sites.length + " 个站点逐行含 stopAllOf/followOf");
})();

// ===== ICON SEM CHECK（1.73.5）：图标语义表必须与客户端清单**一一对应**，且真的被载入 =====
// ★背景（用户要求）：「对存储下来的图标路径进行语义识别,对应一个名称,语义tag 一个图标可以设置多个」
//   语义表是**生成物**（gen_iconsem.js 从 doc/图标路径清单.txt 生成）→ 两份文件必须逐条对齐：
//   ① 清单里每条都要有语义记录（少一条 = 过滤/显示查不到它）；② 语义表里不许有清单外的孤儿；
//   ③ 每条都要有名称与至少 1 个标签；④ 中文名覆盖率有下限（词表退化会当场响）；⑤ 必须列进 .toc（否则运行期满盘皆 nil）。
(function () {
  const wlPath = path.join(__dirname, 'doc', '图标路径清单.txt');
  const semPath = path.join(__dirname, 'IconSem.lua');
  if (!fs.existsSync(wlPath)) { console.log('ICON SEM CHECK: FAIL - 缺少 doc/图标路径清单.txt'); process.exitCode = 1; return; }
  if (!fs.existsSync(semPath)) { console.log('ICON SEM CHECK: FAIL - 缺少 IconSem.lua'); process.exitCode = 1; return; }
  const bases = fs.readFileSync(wlPath, 'utf8').split(/\r?\n/).map(s => s.trim())
    .filter(s => s && s.charAt(0) !== '#').map(p => p.replace('/Game/Interface/Icons/', '').replace(/_TEX$/, ''));
  const want = new Set(bases);
  const sem = fs.readFileSync(semPath, 'utf8');
  const got = new Set();
  const re = /\["([^"]+)"\] = "([^"]*)",/g;
  let m, named = 0, noName = 0, noTag = 0;
  while ((m = re.exec(sem)) !== null) {
    const key = m[1], val = m[2];
    got.add(key);
    const bar = val.indexOf('|');
    const nm = bar >= 0 ? val.slice(0, bar) : '';
    const tags = bar >= 0 ? val.slice(bar + 1) : '';
    if (!nm) noName++;
    if (nm === key) { /* 英文名退回，如实 */ } else named++;
    if (!tags) noTag++;
  }
  const missing = [...want].filter(x => !got.has(x));
  const ghost = [...got].filter(x => !want.has(x));
  const toc = fs.readFileSync(path.join(__dirname, 'EvalHelp.toc'), 'utf8');
  const inToc = toc.split(/\r?\n/).some(l => l.trim() === 'IconSem.lua');
  console.log('ICON SEM CHECK: ' + got.size + ' entries, ' + named + ' named, ' + missing.length + ' missing, ' + ghost.length + ' orphan, ' + (noName + noTag) + ' empty');
  if (!inToc) { console.log('ICON SEM CHECK: FAIL - IconSem.lua 没有列进 EvalHelp.toc（运行期读不到）'); process.exitCode = 1; return; }
  if (missing.length) { console.log('ICON SEM CHECK: FAIL - 清单里有 ' + missing.length + ' 条没语义记录，例如 ' + missing.slice(0, 3).join(', ')); process.exitCode = 1; return; }
  if (ghost.length) { console.log('ICON SEM CHECK: FAIL - 语义表里有 ' + ghost.length + ' 条不在客户端清单里（幽灵条目），例如 ' + ghost.slice(0, 3).join(', ')); process.exitCode = 1; return; }
  if (noName || noTag) { console.log('ICON SEM CHECK: FAIL - ' + noName + ' 条没名称 / ' + noTag + ' 条没标签'); process.exitCode = 1; return; }
  if (named < 700) { console.log('ICON SEM CHECK: FAIL - 中文名只有 ' + named + ' 条（词表退化？下限 700）'); process.exitCode = 1; return; }
})();
// ===== WHEEL DIRECTION CHECK（1.73.3）：滚轮方向必须**单一来源**，且不许出现反向写法 =====
// ★背景（用户实测）：「图标库的滚动监测鼠标滚动方向和滚动效果相反了」——5 处滚轮里 4 处是「off - d」
//   （上滚 = 回到前面），图标库写成了「d > 0 → 下一页」= 反的；更糟的是**当时的断言把 -1 当「向上」**，
//   把反向 bug 一起验过去了。★教训：方向这种「全局约定」必须有单一来源 + 源码检查兜底，
//   否则每个新列表都会各写一遍、错一个没人发现。
(function () {
  const files = ["EvalHelp.lua", "Toolbox.lua", "DataSearch.lua", "IconBrowser.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua"];
  const sites = [];
  const bad = [];
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      // 两种写法都要认：obj:SetScript("OnMouseWheel", fn) 与 pcall(obj.SetScript, obj, "OnMouseWheel", fn)
      if (!/SetScript[^\n]*"OnMouseWheel"/.test(lines[i])) continue;
      const body = lines.slice(i, Math.min(lines.length, i + 14)).join("\n");
      sites.push(f + ":" + (i + 1));
      if (body.indexOf("EVAL_WHEEL_DIR(") < 0) bad.push(f + ":" + (i + 1) + " 没有走 EVAL_WHEEL_DIR");
      if (/\+\s*(dir|d)\b/.test(body.replace(/EVAL_WHEEL_DIR/g, ""))) bad.push(f + ":" + (i + 1) + " 位移与方向同号（上滚往后 = 反了）");
      if (/d\s*>\s*0\s*and\s*1\s*or\s*-1/.test(body)) bad.push(f + ":" + (i + 1) + " 还在用旧的反向写法");
    }
  }
  if (sites.length < 5) {
    console.log("WHEEL DIRECTION CHECK: FAIL - 只找到 " + sites.length + " 处滚轮处理器（应 >= 5）(" + sites.join(", ") + ")");
    process.exitCode = 1;
    return;
  }
  if (bad.length) {
    console.log("WHEEL DIRECTION CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("WHEEL DIRECTION CHECK: " + sites.length + " 处滚轮处理器全部走 EVAL_WHEEL_DIR（上滚 = 回到前面）");
})();

// ===== COLOR CODE LEN CHECK（1.73.19）：聊天里的颜色码必须是 **8 位 aarrggbb** =====
// ★背景（用户真机截图定案）：工具箱里「表」存的是 8 位（`fff58cba`），而写进聊天文本时用了
//   `string.sub(hex, 3)` 把 **alpha 两位切掉** → 变成 6 位的 `|cf58cba` —— 本客户端**不解析**这种码，
//   于是名字以**原文**画出来：「[|cf58cbaIonol|r]说: 1」（用户截图可见）。
//   ★教训：颜色码长度是**客户端约定**（1.12 = |cAARRGGBB），行为断言里比的是「我们写的串」→
//     再怎么比也验不到「客户端认不认」；只能把约定写成**源码检查**：禁止 sub(hex,3) 这种切码写法 +
//     职业色表逐项必须是 8 位。
(function () {
  const files = ["EvalHelp.lua", "Toolbox.lua", "Engine.lua", "Core.lua", "Share.lua", "DataSearch.lua", "IconBrowser.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua"];
  const bad = [];
  let uses = 0;
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const ln = lines[i];
      if (/^\s*--/.test(ln)) continue; // 注释行不算（说明文字里就写着反面教材）
      if (/"\|c"\s*\.\.\s*string\.sub\(/.test(ln)) bad.push(f + ":" + (i + 1) + " 颜色码被切短（|c + sub(hex,3) = 6 位）");
      if (/"\|c"\s*\.\.\s*(hex|col|cls|color)\b/.test(ln)) uses++;
    }
  }
  const tb = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
  const tbl = (tb.match(/local TB_PAINT_CLASS_COLOR = \{[\s\S]*?\n\}/) || [""])[0];
  const entries = (tbl.match(/"[0-9a-fA-F]+"/g) || []).map(function (s) { return s.replace(/"/g, ""); });
  const badLen = entries.filter(function (s) { return s.length !== 8; });
  if (bad.length) { console.log("COLOR CODE LEN CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  // ★★★1.73.43e 新增：**写在字面量里的色码必须是 8 位**。
  //   背景（用户真机「变异测」一测定案）：我在变异测里手打了一个 **7 位**色码（`|cffff2c8`），
  //   结果那一条消息**整个没出现**（同一批的 1/2/3/5/6 都出来了）⇒ 客户端遇到不合法的颜色码会**吞掉整条消息**
  //   （不报错、不显示）。★这与 1.73.19 是同一族：**客户端约定类的错误，行为断言天然验不到**（我们发的串自己也认）
  //   ⇒ 只能写成源码检查。
  //   ★排除两类**合法**写法：① 注释行；② 动态拼接（`"|cff" .. h(r) .. ...`，色码本身不完整是正常的）。
  const typo = [];
  for (const f of files) {
    const p2 = path.join(__dirname, f);
    if (!fs.existsSync(p2)) continue;
    const ls2 = fs.readFileSync(p2, "utf8").split(/\r?\n/);
    for (let i2 = 0; i2 < ls2.length; i2++) {
      const ln2 = ls2[i2];
      if (/^\s*--/.test(ln2)) continue;
      const re2 = /\|c([0-9a-fA-F]+)/g;
      let m2;
      while ((m2 = re2.exec(ln2))) {
        let hex2 = m2[1];
        const after2 = ln2.slice(m2.index + m2[0].length);
        // 动态拼接（色码正好结束在字符串末尾，紧跟着 .. ）→ 跳过
        if (/^"\s*\.\./.test(after2)) continue;
        // `|cff66ccffEVAL_HELP` 这种：多出来的是紧接着的**文字**，取前 8 位即可
        if (hex2.length > 8) hex2 = hex2.slice(0, 8);
        if (hex2.length !== 8) typo.push(f + ":" + (i2 + 1) + " |c" + hex2 + "（" + hex2.length + " 位）");
      }
    }
  }
  if (typo.length) {
    console.log("COLOR CODE LEN CHECK: FAIL - 字面量色码不是 8 位（客户端会吞掉整条消息）：" + typo.slice(0, 5).join(" | "));
    process.exitCode = 1; return;
  }
  if (uses < 3) { console.log("COLOR CODE LEN CHECK: FAIL - 只找到 " + uses + " 处 |c + 完整色码（应 >= 3）"); process.exitCode = 1; return; }
  if (entries.length < 9 || badLen.length) {
    console.log("COLOR CODE LEN CHECK: FAIL - 职业色表 " + entries.length + " 项里有 " + badLen.length + " 项不是 8 位（" + badLen.slice(0, 3).join(",") + "）");
    process.exitCode = 1;
    return;
  }
  console.log("COLOR CODE LEN CHECK: " + uses + " 处颜色码全走 8 位 aarrggbb；职业色表 " + entries.length + " 项逐项 8 位（6 位码客户端不解析 → 会显示成原文）");
})();

// ===== SHARE MSG SHAPE CHECK（1.73.43h）：分享信息每条消息**最多一段色码** =====
// ★真机变异测定案（用户跑 `/eh go 封皮测`，10 条编号回来只有 [1][4][10] 出现）：
//   · 能画的三条 = 「一段色码 + 链接」「纯文本 + 一段色码 + 链接 + 标签 + 评语」「纯文本」；
//   · 被吞的那些 = 「两段色码 + 链接」「完整封皮（两三段色码）」以及**带方括号身份前缀**的写法。
//   ⇒ 这个客户端会**整条吞掉「一条消息里塞了多段色码/多要素」的消息**（与「7 位色码吞整条」同一族）。
//   ⇒ 分享信息因此拆成两条（A 身份行 / B 品阶行），每条只允许**一段色码**。
//   ★客户端约定类的错误，行为断言天然验不到（我们发的串自己也认）→ 只能源码检查。
(function () {
  const p = path.join(__dirname, "Share.lua");
  const src = fs.readFileSync(p, "utf8");
  if (!/sealA\s*=/.test(src) || !/sealB\s*=/.test(src)) {
    console.log("SHARE MSG SHAPE CHECK: FAIL - 找不到分享信息构造（sealA/sealB，改名了？）");
    process.exitCode = 1; return;
  }
  const bad = [];
  const lines = src.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    if (/^\s*--/.test(ln)) continue;
    if (!/seal[AB]\s*=/.test(ln)) continue;
    const c = (ln.match(/\|c/g) || []).length;
    if (c > 1) bad.push("Share.lua:" + (i + 1) + " 有 " + c + " 段色码");
  }
  if (bad.length) {
    console.log("SHARE MSG SHAPE CHECK: FAIL - 分享信息每条最多**一段色码**（多段会被客户端整条吞掉，真机实测）：" + bad.join(" | "));
    process.exitCode = 1; return;
  }
  console.log("SHARE MSG SHAPE CHECK: 分享信息两条各自 <=1 段色码（客户端会吞多段色码的消息，已实测定案）");
})();

// ===== UI TITLEBAR CHECK（1.73.54）：HUD 标题栏 = 标题左对齐 + 右侧两个快捷开关（与配置窗同一份真值） =====
// ★背景（用户）：「将上面两个开关（战斗区/方案区）在标题栏右侧对应添加两个开关，快速开启关闭；标题左对齐、控制开关右对齐」。
//   ★这类「加个开关」的改动最容易出的两种静默错：① 开关只是画上去、点了没接线；② 接到**同一个键**上（两个开关联动）。
//     行为断言能抓（走真实 OnClick），源码检查再钉一层「两个开关各自绑自己的键 + 提示走语言包」。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const bad = [];
  if (eh.indexOf('title:SetPoint("LEFT", titleBar') < 0) bad.push("标题没有左对齐（应锚 titleBar 左端）");
  if (eh.indexOf('ui.tglCombat = uiTitleToggle(') < 0) bad.push("找不到战斗区快捷开关 ui.tglCombat");
  if (eh.indexOf('ui.tglScheme = uiTitleToggle(') < 0) bad.push("找不到方案区快捷开关 ui.tglScheme");
  // 两个开关必须各自写自己的键（接到同一个键上 = 两个开关联动，用户没法分别控制）
  const iC = eh.indexOf("ui.tglCombat = uiTitleToggle(");
  const iS = eh.indexOf("ui.tglScheme = uiTitleToggle(");
  const segC = eh.slice(iC, eh.indexOf("end)", iC) > 0 ? eh.indexOf("end)", iC) : iC + 900);
  const segS = eh.slice(iS, eh.indexOf("end)", iS) > 0 ? eh.indexOf("end)", iS) : iS + 900);
  if (segC.indexOf("subCombat") < 0) bad.push("战斗区开关没写 subCombat（会接到别的键上）");
  if (segS.indexOf("subScheme") < 0) bad.push("方案区开关没写 subScheme（会接到同一个键上）");
  if (eh.indexOf('L("G_UI_SUBC_TIP")') < 0 || eh.indexOf('L("G_UI_SUBS_TIP")') < 0) bad.push("开关提示没走配置窗那两条文案（应单一来源）");
  if (bad.length) { console.log("UI TITLEBAR CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("UI TITLEBAR CHECK: 标题左对齐 + 两个快捷开关各自绑自己的键 + 提示复用配置窗文案");
})();

// ===== UI TITLE BADGES CHECK（1.73.55 / 1.73.57）：标题栏中段的**方案档位**徽标 + **玩家头衔** =====
// ★背景（1.73.55，用户：「这位置增加显示玩家方案的档位」）：档位是个**算出来的**东西，最容易出的三种静默错：
//   ① 抄一份自己的品阶表/色码（迟早和 Share.lua 漂移）；② 只在 BUILD 时算一次（换方案/改内容后标题上挂着
//   上一档的徽标 = 界面与真值自相矛盾）；③ 算不出时**硬编一个档位**（本项目「查不到与没有是两件事」的老账）。
// ★背景（1.73.57，用户：「显示玩家的头衔」）：头衔同理 —— 它由 Share.lua 的抽卡系统决定（彩蛋自定义优先、
//   抽卡头衔兜底、没入档如实 nil），UI 侧**只许读**、不许自己判一次档位/卡池；颜色也要走同一个色码解析口。
//   行为断言能抓 ②③（组 164 / 组 166），源码检查再钉一层「只此一张表 + 单一个色码解析口 + 两处都接上」。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  const noComment = eh.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  const bad = [];
  if (noComment.indexOf("local function uiProfileTierRGB(") < 0) bad.push("找不到品阶读值口 uiProfileTierRGB（档位必须由当前方案现算）");
  if (noComment.indexOf("local function uiProfileTierText(") < 0) bad.push("找不到档位算法 uiProfileTierText（档位必须由当前方案现算）");
  if (noComment.indexOf("local function uiPlayerTitle(") < 0) bad.push("找不到头衔读值口 uiPlayerTitle（头衔必须由抽卡系统给）");
  if (noComment.indexOf("local function uiTitleBadgeRefresh(") < 0) bad.push("找不到两个徽标的刷新口 uiTitleBadgeRefresh");
  // ★1.73.59 用户：「状态信息名称和头衔 参考战斗信息做相同的布局」——两个窗口必须**共用同一个建徽标件**
  //   （各写一遍「名字 → [品阶] → 头衔」= 迟早漂移，本项目「同一规则两处实现」的老账）。
  if (noComment.indexOf("local function uiTitleBadgesMake(") < 0) bad.push("找不到公用件 uiTitleBadgesMake（两个窗口的徽标必须同一份实现）");
  // ★1.73.62 顺序 = 玩家名 → 头衔 → 品阶 → 方案名（用户：「品阶和头衔 位置对调. 描述调整 头衔 品阶.方案名称」）
  if (noComment.indexOf('ifs:SetPoint("LEFT", titleFs, "RIGHT"') < 0) bad.push("头衔没锚在玩家名（标题文字）的右边缘（公用件里）");
  if (noComment.indexOf('tfs:SetPoint("LEFT", ifs, "RIGHT"') < 0) bad.push("品阶没锚在头衔的右边缘（顺序必须是 名字→头衔→品阶→方案名）");
  if (noComment.indexOf('pfs:SetPoint("LEFT", tfs, "RIGHT"') < 0) bad.push("方案名没锚在品阶的右边缘（顺序必须是 名字→头衔→品阶→方案名）");
  if (noComment.indexOf('uiTitleBadgesMake("ui", titleBar') < 0) bad.push("战斗信息UI 没走公用件建徽标");
  if (noComment.indexOf('uiTitleBadgesMake("st", titleBar') < 0) bad.push("状态信息UI 没走公用件建徽标（用户要求与战斗信息同一套布局）");
  if (noComment.indexOf('title:SetPoint("LEFT", titleBar, "LEFT", 6, 0)') < 0) bad.push("状态信息UI 标题没贴左（用户要求参考战斗信息的布局）");
  // ★刷新必须**每处都接**：两个窗口 ×（BUILD 那一刻 + tick 跟着变）
  const calls = (noComment.match(/uiTitleBadgeRefresh\(\)/g) || []).length;
  if (calls < 4) bad.push("uiTitleBadgeRefresh 只接了 " + calls + " 处（两个窗口的 BUILD + tick 都必须接）");
  // ★整段徽标代码（两个算法 + 刷新口）取出来，逐项钉「只走 Share.lua 的读值口」——
  //   不这么切的话，本文件别处（分享/模版）的同类调用会让检查**假通过**（1.73.55 实测：漏了 SYMBOL 还是绿的）。
  const i0 = noComment.indexOf("local function uiProfileTierRGB(");
  const i1 = noComment.indexOf("local function uiTitleToggle(");
  const seg = (i0 >= 0 && i1 > i0) ? noComment.slice(i0, i1) : "";
  if (seg === "") bad.push("取不到徽标代码段（函数被改名或被挪走？）");
  // ★1.74.19 档位改走**单一入口** EVAL_PROFILE_TIER（它自带覆盖封顶）——旧写法只认 EVAL_PROFILE_SCORE，
  //   而「只取分数」正是封顶静默失效的入口，必须由检查挡住。
  ["EVAL_PROFILE_TIER", "EVAL_SHARE_SEAL_TIER", "EVAL_SHARE_SEAL_SYMBOL", "EVAL_SHARE_SEAL_TIER_RGB",
   "EVAL_TITLE_CURRENT", "EVAL_COLOR_RGB"]
    .forEach(function (k) { if (seg.indexOf(k) < 0) bad.push("档位/头衔没走 " + k + "（徽标段内找不到）"); });
  if (seg.indexOf("EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(") >= 0)
    bad.push("徽标段内还在用「只传分数」的旧写法（★会把覆盖封顶整个漏掉）");
  if (/SH_SEAL_TIERS\s*=/.test(noComment)) bad.push("EvalHelp.lua 里又声明了一张品阶表（品阶表只许 Share.lua 一张）");
  if (/SH_TITLES\s*=/.test(noComment)) bad.push("EvalHelp.lua 里又声明了一张头衔卡池（卡池只许 Share.lua 一张）");
  if (/\|c[0-9a-fA-F]{8}/.test(seg)) bad.push("徽标色码写死在 UI 侧（应取自 EVAL_SHARE_SEAL_TIER_RGB / EVAL_COLOR_RGB）");
  // ★色码 → RGB 只许有**一个**解析口（EVAL_COLOR_RGB）：1.73.57 把品阶色那份实现抽了出来，
  //   头衔色直接复用 —— 再加一份就是「同一规则两处实现」（本项目的老账）。
  if (sh.indexOf("function EVAL_COLOR_RGB(") < 0) bad.push("Share.lua 里没有统一的色码解析口 EVAL_COLOR_RGB");
  const parseCount = (sh.match(/string\.sub\(code, 5, 6\)/g) || []).length;
  if (parseCount !== 1) bad.push("Share.lua 里有 " + parseCount + " 处 8 位色码解析（只许 EVAL_COLOR_RGB 一处）");
  if (!/EVAL_SHARE_SEAL_TIER_RGB[\s\S]{0,400}?EVAL_COLOR_RGB\(/.test(sh)) bad.push("EVAL_SHARE_SEAL_TIER_RGB 没复用 EVAL_COLOR_RGB（两条实现）");
  if (bad.length) { console.log("UI TITLE BADGES CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("UI TITLE BADGES CHECK: 两个窗口共用一套徽标件（档位现算 + 头衔走抽卡读值口 + 名字→档位→头衔依次锚右缘）· 单一个色码解析口 · 两窗口的 BUILD/tick 都刷新");
})();

// ===== UI TITLE NAME CHECK（1.73.53）：两个窗口的标题都要显示玩家角色名、且**同一条规矩只写一遍** =====
// ★背景：用户 1.71.12 要求「战斗信息 标题换成用户名字」，1.73.53 又要求「状态信息UI 标题也显示玩家角色」。
//   两份各自写一遍 = 迟早漂移（本项目「同一规则两处实现」的老账）⇒ 必须共用 `uiTitleName()`；
//   而且**取不到名字要如实退回窗口名**（空标题比旧文案更糟）——这条只靠源码检查才守得住（行为断言要能造出 nil）。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const noComment = eh.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  const bad = [];
  if (noComment.indexOf("local function uiTitleName(") < 0) bad.push("找不到标题取名函数 uiTitleName（两处共用的那个）");
  if (noComment.indexOf('uiTitleName("G_UI_TITLE")') < 0) bad.push("战斗信息UI 标题没走 uiTitleName(\"G_UI_TITLE\")");
  if (noComment.indexOf('uiTitleName("G_ST_TITLE")') < 0) bad.push("状态信息UI 标题没走 uiTitleName(\"G_ST_TITLE\")");
  if (/title:SetText\("[^"]/.test(noComment)) bad.push("还有窗口把标题写死成字面量（应走语言包 + 玩家名）");
  if (bad.length) { console.log("UI TITLE NAME CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("UI TITLE NAME CHECK: 两个窗口标题共用 uiTitleName（玩家名优先 / 如实退回窗口名 / 无硬编码标题）");
})();

// ===== NAME CACHE PROBE WIRING CHECK（1.73.51）：名字染色缓存探针要真的接在 /eh go 上 =====
// ★背景：用户报「刚载入不染色、查询完成还是不染色、只有打开公会信息才开始」——真机上这三句话对应三个不同的根因，
//   只能靠**当场读各来源的条数与职业原文**分辨 ⇒ 必须给用户一条能跑的命令（写错前缀 = 敲了静默无反应）。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  if (!/msg == "go 名字缓存"/.test(eh) || !/EVAL_TB_NAMECLASS_PROBE\(\)/.test(eh)) {
    console.log("NAME CACHE PROBE WIRING CHECK: FAIL - /eh go 名字缓存 没接到命令入口（敲了会静默无反应）");
    process.exitCode = 1; return;
  }
  console.log("NAME CACHE PROBE WIRING CHECK: /eh go 名字缓存 已接上（读各来源条数与职业原文）");
})();

// ===== PROF ICON PROBE WIRING CHECK（1.73.49）：方案图标取证命令要真的接在 /eh go 上 =====
// ★背景：用户报「方案左侧的图片还没显示」，而真机上「没请求 / 请求了没生效 / 生效了没画出来」三种原因
//   只能靠**读回来的纹理路径**分辨 ⇒ 必须给用户一条能跑的命令。命令写错前缀 = 敲了静默无反应（本项目真事故）。
(function () {
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  if (!/msg == "go 方案图标"/.test(eh) || !/EVAL_WAR_PROF_ICON_PROBE\(\)/.test(eh)) {
    console.log("PROF ICON PROBE WIRING CHECK: FAIL - /eh go 方案图标 没接到命令入口（敲了会静默无反应）");
    process.exitCode = 1; return;
  }
  console.log("PROF ICON PROBE WIRING CHECK: /eh go 方案图标 已接上（读回纹理/传参/显示）");
})();

// ===== SHARE LABEL I18N CHECK（1.73.47）：分片标签必须**走 Locales**，不许在源码里硬编码 =====
// ★背景（用户：「方案:xxx 传输中 -> 秘籍传输中...」）：分片标签是**玩家看得见的文案**——
//   硬编码中文 = 英/俄玩家看到中文（而且不报错，只是不同步，正是本项目最恨的一族）。
//   判据：① Share.lua 里必须调 `L("SH_CHUNK_LABEL")`；② **剥掉注释后**源码里不许再出现「传输中」这个字面量。
//   ★先剥注释再扫（说明文字里就会写「秘籍传输中...」——不剥就是假 FAIL，本项目 WTT 隔离检查踩过同款）。
(function () {
  const src = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  if (src.indexOf('L("SH_CHUNK_LABEL")') < 0) {
    console.log("SHARE LABEL I18N CHECK: FAIL - 分片标签没有走 Locales（L(\"SH_CHUNK_LABEL\")）—— 三语言会不同步");
    process.exitCode = 1; return;
  }
  const noComment = src.split(/\r?\n/).map(function (ln) { return ln.replace(/--.*$/, ""); }).join("\n");
  if (/传输中/.test(noComment)) {
    console.log("SHARE LABEL I18N CHECK: FAIL - 源码里还有硬编码的「传输中」文案（应走语言包）");
    process.exitCode = 1; return;
  }
  console.log("SHARE LABEL I18N CHECK: 分片标签走 Locales（SH_CHUNK_LABEL），源码里无硬编码文案");
})();

// ===== SHARE PALETTE CHECK（1.73.44）：分享**在用的每一个色码**都必须 8 位，且「色码测」命令要从色表现取 =====
// ★背景（用户要求：「将现在所使用的所有颜色色码都测试下」）：色码是这个客户端最容易「整条吞掉消息」的成分，
//   而三种坑**症状相同、根因不同**（非 8 位吞整条 1.73.43e · 一条多段吞整条 1.73.43h · 有色码无链接不画 1.73.43p）。
//   ★这一条守的是「**测试清单不能写死**」：命令若把 12 个色码抄在函数里，往色表里加/改一个色码，
//     命令照旧只测老的 12 个 —— **不报错、只是漏测**（正是本项目反复踩的那类静默失败）。
//     ⇒ 源码检查：色表逐项 8 位 + 命令必须**引用四张色表**（分片色 / 品阶 / 头衔 / 彩蛋）+ 命令里不许出现字面色码。
(function () {
  const p = path.join(__dirname, "Share.lua");
  const src = fs.readFileSync(p, "utf8");
  const need = [
    ["分片传输色 SH_CHUNK_COLOR", /local SH_CHUNK_COLOR = "\|c([0-9a-fA-F]+)"/],
    ["品阶色表 SH_SEAL_TIERS", /local SH_SEAL_TIERS = \{[\s\S]*?\n\}/],
    ["头衔色表 SH_TITLE_COLORS", /local SH_TITLE_COLORS = \{([^}]*)\}/],
    ["彩蛋名号色候选表 SH_TITLE_CUSTOM_COLORS", /local SH_TITLE_CUSTOM_COLORS = \{[\s\S]*?\n\}/],
  ];
  const bad = [];
  for (const item of need) if (!item[1].test(src)) bad.push("找不到 " + item[0] + "（改名了？色码测会漏测）");
  if (bad.length) { console.log("SHARE PALETTE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }

  const codes = [];
  codes.push(["SH_CHUNK_COLOR", src.match(/local SH_CHUNK_COLOR = "\|c([0-9a-fA-F]+)"/)[1]]);
  const tierBlock = src.match(/local SH_SEAL_TIERS = \{[\s\S]*?\n\}/)[0];
  const tierCols = (tierBlock.match(/color = "\|c([0-9a-fA-F]+)"/g) || []).map(function (s) { return s.replace(/.*"\|c/, "").replace(/"/, ""); });
  if (tierCols.length !== 5) bad.push("品阶色表应为 5 档，实际 " + tierCols.length + " 项");
  tierCols.forEach(function (c, i) { codes.push(["品阶" + (i + 1), c]); });
  const titleBlock = src.match(/local SH_TITLE_COLORS = \{([^}]*)\}/)[1];
  const titleCols = (titleBlock.match(/\|c[0-9a-fA-F]{8}/g) || []).map(function (s) { return s.replace("|c", ""); });
  if (titleCols.length !== 5) bad.push("头衔色表应为 5 档，实际 " + titleCols.length + " 项");
  titleCols.forEach(function (c, i) { codes.push(["头衔" + (i + 1), c]); });
  // ★1.73.45 彩蛋名号色现在是**候选表**（用户：「彩蛋头衔 颜色设置霸气一点」）：
  //   ① 每个候选都要 8 位；② **默认色 == 候选 1**（单一来源，改表即改默认，永远不漂移）；
  //   ③ 候选与品阶/头衔**两两不撞**（同屏糊在一起就分不清「这不是抽来的」）。
  const custBlock = src.match(/local SH_TITLE_CUSTOM_COLORS = \{[\s\S]*?\n\}/)[0];
  const custCols = (custBlock.match(/code = "\|c([0-9a-fA-F]+)"/g) || []).map(function (s) { return s.replace(/.*"\|c/, "").replace(/"/, ""); });
  if (custCols.length < 3) bad.push("彩蛋名号色候选应 >=3 个，实际 " + custCols.length + " 个");
  custCols.forEach(function (c, i) { codes.push(["名号色" + (i + 1), c]); });
  if (!/local SH_TITLE_CUSTOM_COLOR = SH_TITLE_CUSTOM_COLORS\[1\]\.code/.test(src)) {
    bad.push("默认名号色必须取自候选表第 1 项（SH_TITLE_CUSTOM_COLORS[1].code）—— 否则默认与候选会漂移");
  }
  const dupCodes = codes.map(function (c) { return c[1]; }).filter(function (v, i, a) { return a.indexOf(v) !== i; });
  if (dupCodes.length) bad.push("色码撞车（同屏会分不清）：" + dupCodes.join(","));
  // ★档数不对（色表被改坏/解析失效）也要当场响，不能只算长度
  if (bad.length) { console.log("SHARE PALETTE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  // ★每项必须**正好 8 位**（6 位客户端不解析 · 7 位吞整条）
  const badLen = codes.filter(function (c) { return c[1].length !== 8; });
  if (badLen.length) {
    console.log("SHARE PALETTE CHECK: FAIL - 在用色码不是 8 位（客户端不解析/吞整条）：" +
      badLen.map(function (c) { return c[0] + "=" + c[1] + "(" + c[1].length + "位)"; }).join(" | "));
    process.exitCode = 1; return;
  }
  // ★「色码测」命令必须**从色表现取**（引用四张表）+ 不许字面色码（写死 = 改色表就漏测）
  const pm = src.match(/function EVAL_SHARE_COLOR_PROBE\(\)[\s\S]*?\nend/);
  if (!pm) { console.log("SHARE PALETTE CHECK: FAIL - 找不到色码测命令 EVAL_SHARE_COLOR_PROBE（改名了？）"); process.exitCode = 1; return; }
  const probe = pm[0];
  const refs = ["SH_CHUNK_COLOR", "SH_SEAL_TIERS", "SH_TITLE_COLORS", "SH_MSG_MAX", "shTxQ", "shEnsureTxTicker"];
  const missRef = refs.filter(function (r) { return probe.indexOf(r) < 0; });
  if (probe.indexOf("SH_TITLE_CUSTOM_COLOR") < 0 && probe.indexOf("shTitleCustomColor") < 0) missRef.push("SH_TITLE_CUSTOM_COLOR/shTitleCustomColor");
  if (missRef.length) {
    console.log("SHARE PALETTE CHECK: FAIL - 色码测命令没有引用 " + missRef.join("/") + "（写死清单 = 改色表就漏测）");
    process.exitCode = 1; return;
  }
  if (/"[^"]*\|c[0-9a-fA-F]/.test(probe)) {
    console.log("SHARE PALETTE CHECK: FAIL - 色码测命令里出现了**字面色码**（应当从色表取色，否则加/改色码就漏测）");
    process.exitCode = 1; return;
  }
  // ★接线：命令入口要真的能调到它（真事故：前缀写错 → 敲了静默无反应）
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  // ★用**精确分支写法**（msg == "go 色码测"）而不是「含 go 色码测」：带我踩过的弱判据坑 ——
  //   分支被改坏时，同屏那句 `string.find(msg, "^go 色码测%s")` 里照样含这个子串 → 「含」判据会假绿（M457 实测 SURVIVED）。
  if (!/msg == "go 色码测"/.test(eh) || !/EVAL_SHARE_COLOR_PROBE\(\)/.test(eh)) {
    console.log("SHARE PALETTE CHECK: FAIL - /eh go 色码测 没接到命令入口（敲了会静默无反应）");
    process.exitCode = 1; return;
  }
  // ★1.73.45 「名号色」命令同样是**从候选表现取**（`/eh go 名号色` 逐条编号预览 / `<n>` 选用并存档）
  const tm = src.match(/function EVAL_SHARE_TITLE_COLOR_PROBE\(\)[\s\S]*?\nend/);
  if (!tm) { console.log("SHARE PALETTE CHECK: FAIL - 找不到名号色命令 EVAL_SHARE_TITLE_COLOR_PROBE（改名了？）"); process.exitCode = 1; return; }
  const tprobe = tm[0];
  const trefs = ["EVAL_TITLE_CUSTOM_COLOR_LIST", "SH_MSG_MAX", "shTxQ", "shEnsureTxTicker"];
  const tmiss = trefs.filter(function (r) { return tprobe.indexOf(r) < 0; });
  if (tmiss.length) {
    console.log("SHARE PALETTE CHECK: FAIL - 名号色命令没有引用 " + tmiss.join("/") + "（写死清单 = 改候选表就漏测）");
    process.exitCode = 1; return;
  }
  if (/"[^"]*\|c[0-9a-fA-F]/.test(tprobe)) {
    console.log("SHARE PALETTE CHECK: FAIL - 名号色命令里出现了**字面色码**（应当从候选表取色）");
    process.exitCode = 1; return;
  }
  // ★同样用精确分支写法：`string.find(msg, "^go 名号色%s")`（带参数那条路）里也含这个子串，弱判据会假绿。
  if (!/msg == "go 名号色"/.test(eh) || !/EVAL_SHARE_TITLE_COLOR_PROBE\(\)/.test(eh) || !/EVAL_TITLE_SET_CUSTOM_COLOR\(/.test(eh)) {
    console.log("SHARE PALETTE CHECK: FAIL - /eh go 名号色 没接上入口（预览与选用两条都要接）");
    process.exitCode = 1; return;
  }
  console.log("SHARE PALETTE CHECK: 在用色码 " + codes.length + " 个逐项 8 位且互不撞色（含 " + custCols.length + " 个名号色候选）；色码测/名号色两条命令都从色表现取（无字面色码）且已接上入口");
})();

// ===== PACK LIST CHECK（1.73.0）：发布包清单必须**跟着 .toc 走**，条目数基准也要对得上 =====
// ★背景两笔代价：① 1.72.0 发现随包的 zip **只有 25 个文件**（缺 IconBrowser.lua + 5 个 examples）
//   —— 用户装了会**直接报错**；② 1.73.0 新增 PetData.lua / PetHelper.lua 后，记忆体第 9 步里的打包脚本
//   仍写着「7 个 .lua 模块」、基准仍写着 60 —— 这类「**不报错、只是清单过时**」正是本项目最恨的一族
//   （与 README 版本行插错表同类：结构假设错了，跑起来毫无提示）。
// 判据：CLAUDE.md 发布包 Copy-Item 行里的**顶层 .lua 名单** == EvalHelp.toc 的顶层 .lua 名单（逐个一致），
//   且记忆体里写的**条目数基准** == 按打包脚本口径算出来的真实集合大小（toc + 顶层 .lua + 5 份文档
//   + Locales/* + examples/* + media/* 去掉 media/Textures）。
// ★变异验证：从 CLAUDE.md 删掉 PetData.lua → 当场 FAIL；把基准数改成 60 → 当场 FAIL。
(function () {
  // ★1.74.0 起发布流程第 9 步（打包清单 + 基准数）在**参考卷** `CLAUDE_REFERENCE.md`（常驻卷 CLAUDE.md 瘦身时被移出）；
  //   参考卷不在则退回常驻卷 CLAUDE.md（兼容未提交参考卷的旧布局 —— 别让检查依赖「参考卷是否已入库」）。
  let cpath = path.join(__dirname, "CLAUDE_REFERENCE.md");
  if (!fs.existsSync(cpath)) cpath = path.join(__dirname, "CLAUDE.md");
  if (!fs.existsSync(cpath)) {
    console.log("PACK LIST CHECK: FAIL - 找不到 CLAUDE_REFERENCE.md / CLAUDE.md（发布流程第 9 步的打包清单在里面）");
    process.exitCode = 1;
    return;
  }
  const claude = fs.readFileSync(cpath, "utf8");
  const packLine = claude.split(/\r?\n/).find(l => /Copy-Item .*EvalHelp\.toc.*\$staging/.test(l));
  if (!packLine) {
    console.log("PACK LIST CHECK: FAIL - CLAUDE_REFERENCE.md 第 9 步里找不到打包 Copy-Item 行");
    process.exitCode = 1;
    return;
  }
  const listed = (packLine.match(/\$src\\([A-Za-z0-9_]+\.lua)/g) || []).map(s => s.replace("$src\\", ""));
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8")
    .split(/\r?\n/).map(s => s.trim()).filter(s => s && s.charAt(0) !== "#");
  const topLua = toc.filter(f => /\.lua$/i.test(f) && f.indexOf("/") < 0 && f.indexOf("\\") < 0);
  // ★1.74.5 新增：**子目录里的模块**（如 tools/HunterHelper.lua）也必须进包 ——
  //   旧判据只看「顶层 .lua」，于是把模块放进子目录后本地测试全绿、**出包却缺文件**（用户装了直接报错）。
  //   判据：toc 里带路径的 .lua，要么被打包行逐个列出，要么它所在目录被 Copy-Item -Recurse 整目录拷。
  const subLua = toc.filter(f => /\.lua$/i.test(f) && (f.indexOf("/") >= 0 || f.indexOf("\\") >= 0));
  const dirCopied = dir => new RegExp("Copy-Item[^\\n]*\\$src\\\\" + dir).test(claude);
  const subMissing = subLua.filter(f => {
    const dir = f.split(/[\\/]/)[0];
    return listed.indexOf(f) < 0 && !dirCopied(dir);
  });
  if (subMissing.length) {
    console.log("PACK LIST CHECK: FAIL - 子目录模块没进发布包（打包脚本既没逐个列出、也没整目录拷）：[" + subMissing.join(",") + "]");
    process.exitCode = 1;
    return;
  }
  const missing = topLua.filter(f => listed.indexOf(f) < 0);
  const ghost = listed.filter(f => topLua.indexOf(f) < 0);
  if (missing.length || ghost.length) {
    console.log("PACK LIST CHECK: FAIL - CLAUDE_REFERENCE.md 打包清单与 .toc 不一致；清单缺=[" + missing.join(",") + "] 清单多余=[" + ghost.join(",") + "]");
    process.exitCode = 1;
    return;
  }
  // 条目数基准：按打包脚本的同一口径数一遍
  const set = [];
  const push = p => { if (set.indexOf(p) < 0) set.push(p); };
  push("EvalHelp.toc");
  topLua.forEach(push);
  ["README.md", "README_en.md", "README_ru.md", "CHANGELOG.md", "DEVELOPMENT.md"].forEach(push);
  const walk = (dir, rel) => {
    if (!fs.existsSync(dir)) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (/Textures$/.test(p)) continue; walk(p, rel + "/" + e.name); }
      else push(rel + "/" + e.name);
    }
  };
  walk(path.join(__dirname, "Locales"), "Locales");
  walk(path.join(__dirname, "examples"), "examples");
  walk(path.join(__dirname, "media"), "media");
  walk(path.join(__dirname, "tools"), "tools"); // ★1.74.5 子目录模块也计入条目数基准
  // ★1.75.0 quest/ 只把两个 .lua 打进发布包（抓取脚本与 cache 是开发工具，不进包 —— 故不用 walk 全目录）
  const qDir = path.join(__dirname, "quest");
  if (fs.existsSync(qDir)) {
    for (const e of fs.readdirSync(qDir, { withFileTypes: true })) {
      if (!e.isDirectory() && /\.lua$/i.test(e.name)) push("quest/" + e.name);
    }
  }
  const real = set.length;
  const mNum = claude.match(/基准\s*=\s*\*\*(\d+)\s*个\*\*/);
  if (!mNum) {
    console.log("PACK LIST CHECK: FAIL - CLAUDE_REFERENCE.md 里读不到「基准 = **N 个**」这一条（装完没得核对）");
    process.exitCode = 1;
    return;
  }
  if (parseInt(mNum[1], 10) !== real) {
    console.log("PACK LIST CHECK: FAIL - 条目数基准过期：参考卷写 " + mNum[1] + " 个，实际按打包口径是 " + real + " 个");
    process.exitCode = 1;
    return;
  }
  console.log("PACK LIST CHECK: 打包清单 " + listed.length + " 个模块与 .toc 一致，条目数基准 " + real + " 个");
})();

// ===== HH WIRING CHECK（1.74.5）：猎人助手的四处接线，漏一处都**不报错、只是功能没有** =====
// 背景：新增模块最常见的失败模式是「文件写了但没接上」——
//   ① 没进 .toc → 运行期这个模块根本不存在（本客户端没有文件读取 API，只能靠 toc）；
//   ② 工具箱没有那一行 → 用户找不到开关；
//   ③ 勾选后不调 EVAL_HH_TOGGLE → 图标永远不出现（看着像坏了，且不报错）；
//   ④ /eh go 喂食* 没接 → 命令静默无反应（本项目 1.73.42 已有同族教训）。
// 这四类**行为断言照不到**（要么得跑整套 UI），故落成源码检查。
(function () {
  const bad = [];
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  if (!/tools[\\/]HunterHelper\.lua/.test(toc)) bad.push("EvalHelp.toc 没列 tools/HunterHelper.lua");
  if (toc.indexOf("IconGrid.lua") < 0) bad.push("EvalHelp.toc 没列 tools/IconGrid.lua（共用网格件）");
  if (toc.indexOf("ConsumableHelper.lua") < 0) bad.push("EvalHelp.toc 没列 tools/ConsumableHelper.lua");
  const tb = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
  if (!/key\s*=\s*"feedPet"/.test(tb)) bad.push('Toolbox.lua 行模型里没有 key="feedPet" 的开关行');
  if (!/modelKey\s*==\s*"feedPet"/.test(tb) || tb.indexOf("EVAL_HH_TOGGLE") < 0) {
    bad.push("Toolbox.lua 勾选后没有调 EVAL_HH_TOGGLE（图标不会出现）");
  }
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  if (eh.indexOf("EVAL_HH_CMD") < 0) bad.push("EvalHelp.lua 没接 /eh go 喂食* 命令");
  // ★1.74.7 骑乘助手（tools/DismountHelper.lua）同四条接线：toc / 工具箱开关行 / 勾选副作用 / 命令 + 登录恢复
  if (!/tools[\\/]DismountHelper\.lua/.test(toc)) bad.push("EvalHelp.toc 没列 tools/DismountHelper.lua");
  if (!/key\s*=\s*"dismount"/.test(tb)) bad.push('Toolbox.lua 行模型里没有 key="dismount" 的开关行');
  if (!/modelKey\s*==\s*"dismount"/.test(tb) || tb.indexOf("EVAL_DH_TOGGLE") < 0) {
    bad.push("Toolbox.lua 勾选后没有调 EVAL_DH_TOGGLE（下马图标不会出现）");
  }
  if (!/modelKey\s*==\s*"dismountAuto"/.test(tb)) bad.push('Toolbox.lua 缺「自动下马」开关行（key="dismountAuto"）');
  if (eh.indexOf("EVAL_DH_CMD") < 0) bad.push("EvalHelp.lua 没接 /eh go 下马* 命令");
  if (eh.indexOf("EVAL_DH_RESTORE") < 0) bad.push("EvalHelp.lua 登录时没恢复骑乘助手图标（/reload 后图标会消失）");
  // ★1.75.x 用户要求：「工具→宠物助手→ 内的信息提示调整成未选择喂养宠物技能的提示」
  //   提示行现在是**唯一来源** `EVAL_HH_TIP_LINES()`（悬浮提示照它渲染、断言直接读它）——
  //   源码级守三条（漏了都不报错，只是提示又变回含糊的「未识别」/ 或两处文本悄悄漂移）：
  //     ① 读值口存在；② `hhTip` 必须走读值口；③ 三语的 HH_TT_SPELL_NONE 都不许是旧文案。
  const hhSrc = fs.readFileSync(path.join(__dirname, "tools", "HunterHelper.lua"), "utf8");
  if (hhSrc.indexOf("function EVAL_HH_TIP_LINES(") < 0) bad.push("HunterHelper 缺提示行读值口 EVAL_HH_TIP_LINES（渲染与断言会各拼一份）");
  if (hhSrc.indexOf("local lines = EVAL_HH_TIP_LINES()") < 0) bad.push("hhTip 没走读值口 EVAL_HH_TIP_LINES（两处各拼一份 ⇒ 迟早漂移）");
  if (hhSrc.indexOf("HH_TT_SPELL_NONE") < 0) bad.push("没选喂养技能那条分支没用 HH_TT_SPELL_NONE（用户点名的提示语没了）");
  ["zhCN", "enUS", "ruRU"].forEach(function (lg) {
    const p = path.join(__dirname, "Locales", lg + ".lua");
    const s = fs.readFileSync(p, "utf8");
    const m = s.match(/HH_TT_SPELL_NONE\s*=\s*"([^"]*)"/);
    if (!m) { bad.push(lg + " 缺 HH_TT_SPELL_NONE"); return; }
    const stale = ["未识别", "not identified", "не определено"];
    if (stale.indexOf(m[1]) >= 0) bad.push(lg + " 的 HH_TT_SPELL_NONE 还是旧文案（" + m[1] + "）—— 用户要的是「未选择喂养宠物技能」的提示");
  });
  if (bad.length) {
    console.log("HH WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("HH WIRING CHECK: tools 模块进了 .toc · 工具箱有开关行且勾选接 EVAL_HH_TOGGLE/EVAL_DH_TOGGLE · /eh go 喂食*/下马* 已接 · 两个助手都接了登录恢复 · 喂食提示行走单一来源且三语提示语已更新");
})();

// ===== 拖拽模块（tools/DragFrames.lua）自带的源码检查：已迁到 tests/checks/DragFrames.js =====
// 用户 1.74.34：「拖拽图层模块（DragFrames）代码也排查下归类到自身文件内。」
//   9 道 DF/DRAG 检查（ANCHOR ID / BARS / ROSTER / OPEN HOOK / PROBE SAFE / GLOBAL SCAN GUARD /
//   DRAG FRAMES WIRING / PICK WIRING / ICON ART）全部搬进 tests/checks/DragFrames.js，harness 只留这一行。
// ★TB MOD ROW CHECK 仍在本文件：它是「工具箱模块行」的**框架契约**（服务所有工具模块），不属于某一个模块。
require("./tests/checks/DragFrames.js")(__dirname);

// ===== 地图工具（tools/SimpleMap.lua）自带的源码检查（1.74.35-3）=====
// 用户 1.74.35-3：「缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图
//   切换到其他地图后自动刷新到当前地图,,默认关闭.」
//   两道：SM GUIREOPEN WIRING CHECK（默认关是否真的是默认关 / 提示是否还在 / 开图门是否先判据后动作）
//        + SM GROUP ROSTER CHECK（本模块组号清单，防「整组被删」）。
require("./tests/checks/SimpleMap.js")(__dirname);

// ===== MODULE HOST LOCAL CHECK（1.74.36-2）：模块不许调用「宿主文件的文件局部」名字 =====
// ★真机 bug 起因：`tbCfg` 是 Toolbox.lua 的 **local**，模块里裸调 ⇒ 全局 nil ⇒ 读永远 false、写一次都不生效，
//   而界面/聊天框照样播报「已启用」⇒ 用户看到「勾选框点了不会勾上」。同族还有 `say` / `logLine`（Core/Toolbox 的 local）：
//   模块里它们全是 nil，于是**所有「如实播报」静默消失**（DragFrames 80 处 / RareWatch 30 处 …）。
//   三个闸门此前全绿：Lua 语法没问题、行为断言测的是模块自己的纯函数、源码检查只查接线名字 ⇒ 谁都没排到这一层。
// 判据：把宿主文件（Toolbox/EvalHelp/Core/Engine）里 `local function X` / `local X =` 的名字收集起来，
//   模块自己**没定义同名 local** 却调用了 `X(` ⇒ FAIL（跨文件它们只能是全局 nil）。
(function () {
  const dir = path.join(__dirname, "tools");
  if (!fs.existsSync(dir)) { console.log("MODULE HOST LOCAL CHECK: (无 tools/，跳过)"); return; }
  const strip = t => t.split(/\r?\n/).map(l => { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  const hosts = ["Toolbox.lua", "EvalHelp.lua", "Core.lua", "Engine.lua"].filter(f => fs.existsSync(path.join(__dirname, f)));
  const hostLocals = new Map();
  for (const h of hosts) {
    const code = strip(fs.readFileSync(path.join(__dirname, h), "utf8"));
    for (const m of code.matchAll(/^local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) if (!hostLocals.has(m[1])) hostLocals.set(m[1], h);
    for (const m of code.matchAll(/^local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=/gm)) if (!hostLocals.has(m[1])) hostLocals.set(m[1], h);
  }
  const bad = [];
  let checked = 0;
  for (const f of fs.readdirSync(dir).filter(x => /\.lua$/.test(x)).sort()) {
    const code = strip(fs.readFileSync(path.join(dir, f), "utf8"));
    const own = new Set();
    for (const m of code.matchAll(/^local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)/gm)) own.add(m[1]);
    for (const m of code.matchAll(/^local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=/gm)) own.add(m[1]);
    checked++;
    for (const [name, host] of hostLocals) {
      if (own.has(name) || name.length < 3) continue;
      if (new RegExp("(^|[^A-Za-z0-9_.:])" + name + "\\s*\\(", "m").test(code)) {
        bad.push(f + " 调用了 " + name + "(（它是 " + host + " 的**文件局部** ⇒ 跨文件是全局 nil）");
      }
    }
  }
  if (bad.length) {
    console.log("MODULE HOST LOCAL CHECK: FAIL - " + bad.join(" · ") +
      " ⇒ 这些调用在真机上是 nil（读永远失败/播报静默消失）；改用全局桥（EVAL_TB_CFG / EVAL_SAY / EVAL_LOGLINE）或自带同名 local");
    process.exitCode = 1;
    return;
  }
  console.log("MODULE HOST LOCAL CHECK: " + checked + " 个模块都没有引用宿主文件的 local（" + hostLocals.size +
    " 个宿主 local 名逐个比对；跨模块只认全局桥 EVAL_*）");
})();

// ===== MODULE L SCOPE CHECK（1.74.35-3）：工具模块的本地化取词必须**自带**（不许裸调全局 L）=====
// 本轮实测抓到的静默失效：tools/LayerFix.lua 与 tools/DragFrames.lua 的行渲染直接调 `L("TB_…")`，
//   但项目里 `L` **一律是文件局部**（9 处全是 `local function L`），全仓与游戏目录其它插件都**没有全局 L**。
//   ⇒ 这些调用要么当场报错、要么靠一个外部全局（铁律 5：不许猜 API 存在）。更糟的是它在工具箱里被
//     `pcall(fn, r, it)` **吞掉** —— 表现是「按钮文案没设上 / 点击处理器没挂」而那一行看着完全正常。
// 判据：tools/ 下任何模块只要出现 `L(` 调用，就必须有 `local function L(`，且**必须走全局 EVAL_L**。
(function () {
  const dir = path.join(__dirname, "tools");
  if (!fs.existsSync(dir)) { console.log("MODULE L SCOPE CHECK: (无 tools/，跳过)"); return; }
  const bad = [];
  let checked = 0;
  for (const f of fs.readdirSync(dir).filter(x => /\.lua$/.test(x)).sort()) {
    const src = fs.readFileSync(path.join(dir, f), "utf8");
    // 剥注释（只看真代码）
    const code = src.split(/\r?\n/).map(l => { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    const calls = [...code.matchAll(/(^|[^A-Za-z_.])L\s*\(/g)].length;
    if (!calls) continue;
    checked++;
    if (!/^local function L\(/m.test(code)) {
      bad.push(f + " 调用了 L( " + calls + " 次，但没有自带的 `local function L(`（裸调全局 L ⇒ 被 pcall 吞掉的静默失效）");
      continue;
    }
    if (!/EVAL_L/.test(code)) bad.push(f + " 自带的 L 没有走全局 EVAL_L（本地化取词必须单一来源）");
  }
  if (bad.length) { console.log("MODULE L SCOPE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("MODULE L SCOPE CHECK: " + checked + " 个用到 L( 的工具模块都自带了局部 L 且走全局 EVAL_L（不再裸调全局 L）");
})();
// （DF BARS WIRING CHECK（1.74.31）：动作条1~4 的**候选名解析* … 已迁到 tests/checks/DragFrames.js）
// （DF ROSTER WIRING CHECK（1.74.32）：队伍层/团队层「按需出现」的 … 已迁到 tests/checks/DragFrames.js）
// （DF OPEN HOOK CHECK（1.74.33）：方案 A/C 的四条**源码级**契 … 已迁到 tests/checks/DragFrames.js）
// （DF PROBE SAFE CHECK（1.74.32）：取证命令**绝不许静默** === … 已迁到 tests/checks/DragFrames.js）
// （DF GLOBAL SCAN GUARD CHECK（1.74.32）：全 `_G` 扫描必 … 已迁到 tests/checks/DragFrames.js）
// ===== GO ALIAS UNIQUE CHECK（1.74.32）：`/eh go <别名>` 的别名**不许两家共用** =====
// 真机实案（本轮自己踩的）：新加的「被动窗口图标」分支写了 `msg == "go icons"` 当英文别名 ——
//   而 `go icons` **早就被组 116 的「图标路径采集」占了**（`/eh go icons` = 把客户端真实图标路径采集进存档）。
//   后果：那条命令被**静默顶掉**（分派是 elseif 链，先命中的赢），用户跑 `/eh go icons` 会得到完全不相干的行为。
// ★为什么用源码检查：这类冲突**不报错**，只是"跑到另一家去了"（本项目最恨的静默冲突族）；
//   断言只在"正好有人测了那条命令"时才照得到，源码检查则能覆盖**全部**别名。
// 判据：把 `/eh go` 分派链里所有 `msg == "go XXX"` 的字面量收集起来，**跨分支**重复即 FAIL。
//   ★★注意「同一分支内」不算冲突：一个分支常写成 `msg == "go mbicon reset" or string.find(msg, "^go mbicon reset ") == 1`
//     —— 同一个别名在**同一条分支**里出现两次是正常写法（第一版没按分支分组，把这两句误报成冲突）。
(function () {
  const p = path.join(__dirname, "EvalHelp.lua");
  if (!fs.existsSync(p)) { console.log("GO ALIAS UNIQUE CHECK: (无 EvalHelp.lua，跳过)"); return; }
  const code = fs.readFileSync(p, "utf8").split(/\r?\n/)
    .map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
  // ★★怎么算「一条分支」：只看**分派链那一层**的 if/elseif（缩进最浅的那些），
  //   同一分支里的**嵌套 if**（缩进更深）算同一分支 —— 第一版没区分，把
  //   `elseif msg == "go mbicon" or msg == "go mbicon reset"` 与它内部的
  //   `if msg == "go mbicon reset"`（同一分支的子情形）误报成两家冲突。
  const starts = [];
  for (let i = 0; i < code.length; i++) {
    const m = /^(\s*)(if|elseif)\b/.exec(code[i]);
    if (m && /msg\s*==/.test(code[i]) && /"[^"]*\bgo [^"]*"/.test(code[i])) {
      starts.push({ line: i, indent: m[1].length });
    }
  }
  if (!starts.length) { console.log("GO ALIAS UNIQUE CHECK: 没找到 /eh go 分派链（跳过）"); return; }
  const minIndent = Math.min.apply(null, starts.map(function (s) { return s.indent; }));
  const chain = starts.filter(function (s) { return s.indent === minIndent; });
  const seen = new Map(); // alias -> 分支序号
  const dup = [];
  for (let b = 0; b < chain.length; b++) {
    const from = chain[b].line;
    const to = (b + 1 < chain.length) ? chain[b + 1].line : code.length;
    for (let i = from; i < to; i++) {
      const re = /"(go [^"]*)"/g;
      let m;
      while ((m = re.exec(code[i]))) {
        const alias = m[1];
        if (seen.has(alias) && seen.get(alias) !== b) {
          dup.push(alias + "（分支 #" + (seen.get(alias) + 1) + " 第 " + (chain[seen.get(alias)].line + 1) +
            " 行 与 分支 #" + (b + 1) + " 第 " + (from + 1) + " 行）");
        } else if (!seen.has(alias)) seen.set(alias, b);
      }
    }
  }
  if (dup.length) {
    console.log("GO ALIAS UNIQUE CHECK: FAIL - 别名被两家共用（elseif 链先命中的赢，另一家被**静默顶掉**）：" + dup.join(" · "));
    process.exitCode = 1;
    return;
  }
  console.log("GO ALIAS UNIQUE CHECK: /eh go 分派链 " + chain.length + " 条分支 · 别名 " + seen.size +
    " 个跨分支无重复（不再有「命令被静默顶掉」）");
})();

// （DRAG FRAMES WIRING CHECK（1.74.30）：框拖拽抽成 tools/ … 已迁到 tests/checks/DragFrames.js）
// ===== DBX NAMED FILTER CHECK（1.74.31）：子插件的「只显示有名」判据必须是**唯一来源** =====
// 为什么必须用源码检查：这个开关的判据有**两条路径**能写 `e.named`（uiScanState 的实时刷新 / uiEntryNamed 的懒算），
//   而 uiEntryNamed 只在 `e.named == nil` 时才计算 ⇒ 只要 uiScanState 那侧先写下一个**更弱的**判据
//   （历史写法 `e.named = (uiFrameName(e.f) ~= nil)`：不看区域层、也不看合成名），
//   uiEntryNamed 里那两条判据就**永远不会被走到** —— 开关看着生效（真值/文案/播报全对），
//   实际只藏住了「GetName 真返回空」的那些，用户截图里那一片 `纹理:Texture` 照旧列出来。
//   用户为此连报**三次**（第三次带截图）。这类「第二份判据静默短路唯一来源」行为断言很难守住
//   （要看具体条目才判得出来）⇒ 用源码检查钉住「写入点恰好一处、且在 uiEntryNamed 体内」。
(function () {
  const p = path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua");
  if (!fs.existsSync(p)) { console.log("DBX NAMED FILTER CHECK: (无 addons/EH_DebugBox/EH_DebugBox.lua，跳过)"); return; }
  const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
  const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
  const bad = [];
  let decl = -1;
  for (let i = 0; i < code.length; i++) { if (code[i].indexOf("local function uiEntryNamed(") >= 0) { decl = i; break; } }
  if (decl < 0) {
    bad.push("找不到 local function uiEntryNamed（判据的唯一来源没了）");
  } else {
    let endAt = -1;
    for (let i = decl + 1; i < code.length; i++) { if (code[i] === "end") { endAt = i; break; } }
    const writers = [];
    // ★负向环视排除 `== nil`（否则「读」会被当成「写」，检查器自己先假红）
    for (let i = 0; i < code.length; i++) { if (/\be\.named\s*=(?!=)/.test(code[i])) writers.push(i); }
    if (writers.length !== 1) {
      bad.push("e.named 的写入点有 " + writers.length + " 处（应恰好 1 处 —— 多出来的那份判据会短路唯一来源）");
    } else if (!(writers[0] > decl && writers[0] < endAt)) {
      bad.push("e.named 被写在 uiEntryNamed 之外（行 " + (writers[0] + 1) + "）");
    }
  }
  if (!code.some(function (l) { return /e\.named,\s*e\.isRegion,\s*e\.fakeName\s*=\s*nil,\s*nil,\s*nil/.test(l); })) {
    bad.push("uiScanState 没有把 e.named 置 nil（改回「自己判一次」= 用户报过三次的那个 bug 复发）");
  }
  if (!code.some(function (l) { return l.indexOf("uiEntryNamed(e)") >= 0; })) {
    bad.push("uiFiltered 的 okNamed 没走 uiEntryNamed（过滤可能绕开了唯一判据）");
  }
  const te = fs.readFileSync(path.join(__dirname, "test_engine.js"), "utf8");
  // ★判据要盯「**运行器的载入清单**」那一段，而不是「文件里出现过这个路径」：
  //   本文件里 EH_DebugBox 的路径还出现在 LANG KEY CHECK 的扫描清单里 ⇒ 全文子串匹配等于没查
  //   （把它从运行器清单里删掉，检查照样绿 = 假绿，比没有更坏）。
  //   ★★★锚点必须**拼出来**（"for(const f of" + " ["）：直接写完整字面量的话，
  //   这段检查自己的源码里就含那个字面量 ⇒ indexOf 会命中**自己**，而那个窗口里又必然含有
  //   "test_stub.lua" 与 "EH_DebugBox.lua" 两个关键字 ⇒ 这条检查永远绿。
  //   （本检查首版就是这样假绿的，被「删掉运行器条目应当报 FAIL」的变异验证当场抓住。）
  const anchor = "for(const f of" + " [";
  const ri = te.indexOf(anchor);
  const runner = ri >= 0 ? te.slice(ri, ri + 5000) : "";
  if (ri < 0 || runner.indexOf("test_stub.lua") < 0 || runner.indexOf("EH_DebugBox.lua") < 0) {
    bad.push("子插件没进测试桩运行器的载入清单（行为断言根本跑不到它 —— 组 203 会静默变成空转）");
  }
  // ⑤ 顶栏文案必须**按真值现算**（用户截图问的那件事：文案写「开」，真值就必须是 true）：
  //   ① 文案函数要暴露给「恢复存档」流程；② 恢复存档时必须按真值重写一次（否则存档里是关、文案停在开）；
  //   ③ 不许硬编码「只显示有名:」—— 硬编码就会出现「存档里是关、文案却写着开」这种自相矛盾（「两处真值」老族）。
  //   ★不数 `namedLabel()` 的出现次数：函数声明 `local function namedLabel()` 本身也算一次，
  //   数出来的是「声明 + 调用」的混合量 —— 那样的阈值连「建按钮那处被硬编码」都拦不住（实测放过过一次）。
  const joined = code.join("\n");
  if (joined.indexOf("ui.namedLabel = namedLabel") < 0) {
    bad.push("按钮文案没暴露给「恢复存档」流程（缺 ui.namedLabel = namedLabel）");
  }
  if (joined.indexOf("ui.namedLabel()") < 0) {
    bad.push("恢复存档时没按真值重写按钮文案（ui.namedLabel() 缺席 ⇒ 存档里是关、文案会停在开）");
  }
  if (code.some(function (l) { return /只显示有名:/.test(l); })) {
    bad.push("按钮文案被硬编码（应走语言包 L(\"DBX_NAMED_ON\") / L(\"DBX_NAMED_OFF\")）");
  }
  if (bad.length) {
    console.log("DBX NAMED FILTER CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("DBX NAMED FILTER CHECK: 判据唯一来源 uiEntryNamed（写入点恰好 1 处）· uiScanState 只失效不判定 · " +
    "过滤行接了它 · 子插件在桩的载入清单里");
})();

// ===== DBX TREE WIRING CHECK（1.74.31 第二步）：图层列表的**可折叠树**接线 =====
// 为什么用源码检查：这一批几乎全是**接线**，漏了不报错、只是功能悄悄没有（行为断言也要跑完整面板才照得到）：
//   ① 扫描时必须写下**层号**（`d = depth + 1`）—— 没有它，缩进/父子就只能靠「数路径里的 '/'」猜，
//      而带前缀的扫描源（`[界面] UIParent/（本体）`）会被多算一层（层深:1 在那些源上什么都显示不出来）；
//   ② 条目必须把层号带过来（uiBuildEntries 的 `depth = tonumber(nd.d)`）；
//   ③ 父子关系必须由 uiTreePass（扫描层号 + DFS 相邻性）算，且 uiFiltered **真的要按折叠过滤**；
//   ④ 行上必须真的有折叠控件（create + row.tw + OnClick 走 uiTreeToggle + 每次刷新按层号缩进）；
//   ⑤ 叶子层不许有开关（条件里必须有 `(e.kids or 0) > 0`）；
//   ⑥ 折叠状态必须**落存档 + 读回**（用户要求「折叠状态跨 reload 保持」）；
//   ⑦ 「层深」必须**只有一个写入点**（uiDepthApply）—— 否则「展开到第 N 层」这种联动会有一半路径不生效；
//   ⑧ 状态行不许是**死代码**：uiRefresh 一直在算那行状态却写进一个从没被创建过的 `ui.pageLbl`
//      （老坑：那句话永远是空写 ⇒ 用户看不到「为什么列表变少了」）。
(function () {
  const p = path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua");
  if (!fs.existsSync(p)) { console.log("DBX TREE WIRING CHECK: (无 addons/EH_DebugBox/EH_DebugBox.lua，跳过)"); return; }
  const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
  const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
  const joined = code.join("\n");
  const bad = [];
  const count = function (re) { let n = 0; for (const l of code) if (re.test(l)) n++; return n; };

  // ① 层号写在扫描里
  const dInc = count(/\bd\s*=\s*depth\s*\+\s*1\b/);
  if (dInc !== 2) bad.push("扫描时写层号的地方有 " + dInc + " 处（区域 + 子件应恰好 2 处 `d = depth + 1`）");
  const dRoot = count(/src\s*=\s*src\.k,\s*d\s*=\s*1|\bsrc\s*=\s*"map",\s*d\s*=\s*1/);
  if (dRoot !== 2) bad.push("根节点的层号有 " + dRoot + " 处（两个建根的分支都该写 `d = 1`）");
  // ② 条目带层号
  if (joined.indexOf("depth = tonumber(nd.d)") < 0) bad.push("uiBuildEntries 没把扫描层号带进条目（缩进与层深就失去唯一口径）");
  // ③ 树 pass + 过滤
  if (joined.indexOf("local function uiTreePass(") < 0) bad.push("没有 uiTreePass（父子关系没地方算）");
  if (!/uiEntryDepth\(stack\[table\.getn\(stack\)\]\)\s*>=\s*d/.test(joined)) bad.push("uiTreePass 没有「弹栈」步骤（父子关系会算错）");
  if (joined.indexOf("if not ui.treeDone then uiTreePass() end") < 0) bad.push("uiFiltered 没有懒调 uiTreePass（列表可能按没算过的父子关系过滤）");
  if (joined.indexOf("if not uiTreeHidden(e) then table.insert(out, e) end") < 0) bad.push("uiFiltered 没有按树折叠过滤（折叠点了不会少东西）");
  if (joined.indexOf("p.visKid = true") < 0) bad.push("uiFiltered 没给祖先记「有能显示的子层」（会出现点了没反应的假开关）");
  // ④ 行上的折叠控件
  if (joined.indexOf("local tw = uiBtn(row, 12, 15, UI_TREE_OPEN)") < 0) bad.push("行上没有创建折叠开关控件");
  if (joined.indexOf("row.tw = ") < 0) bad.push("折叠开关没挂到 row.tw（刷新时找不到它）");
  if (joined.indexOf("uiTreeToggle(e)") < 0) bad.push("折叠开关的 OnClick 没走 uiTreeToggle");
  if (joined.indexOf("UI_TREE_TX + ind") < 0) bad.push("行文字没有按层号缩进");
  if (joined.indexOf("UI_TREE_X0 + ind") < 0) bad.push("折叠开关没有跟着缩进");
  // ⑤ 只给有子层的行画
  if (joined.indexOf("((e.kids or 0) > 0) and (shut or e.visKid)") < 0) bad.push("折叠开关没按「有子层」判断（叶子层会冒出个假开关）");
  // ⑥ 落存档 + 读回
  if (!/treeCollapsed\s*=\s*ui\.treeCollapsed\b/.test(joined)) bad.push("uiSaveSettings 没存 treeCollapsed（折叠状态跨 reload 会丢）");
  if (joined.indexOf("if type(c.treeCollapsed) == \"table\" then") < 0) bad.push("uiLoadSettings 没读 treeCollapsed");
  // ⑦ 层深单一入口
  const dWrites = count(/\bui\.depthMax\s*=(?!=)/);
  if (dWrites !== 2) bad.push("ui.depthMax 的写入点有 " + dWrites + " 处（应恰好 2 处：读存档 + uiDepthApply 单入口）");
  const dApply = count(/uiDepthApply\(/);
  if (dApply < 3) bad.push("uiDepthApply 的调用点只有 " + dApply + " 处（顶栏按钮 + 折叠展开两条路都要走它）");
  if (joined.indexOf("ui.depthSync = depthSync") < 0) bad.push("层深按钮文案没暴露给「恢复存档」流程（缺 ui.depthSync = depthSync）");
  if (count(/pcall\(ui\.depthSync\)/) < 2) bad.push("ui.depthSync 只在建按钮时调过（存档读回来的层深会让文案停在旧值）");
  // ⑧ 状态行不许是死代码
  if (count(/\bui\.pageLbl\b/) !== 0) bad.push("又出现了 ui.pageLbl（那个控件从来没被创建过 = 状态行是死代码）");
  if (count(/ui\.statLbl\s*=\s*uiFont\(/) !== 1) bad.push("状态行（计数/地图状态）没有真的被创建");
  if (count(/ui\.filterLbl\s*=\s*uiFont\(/) !== 1) bad.push("过滤条件行（层深/树折叠/无名过滤）没有真的被创建");

  if (bad.length) {
    console.log("DBX TREE WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("DBX TREE WIRING CHECK: 扫描层号 2+2 处 · 条目带层号 · uiTreePass(弹栈)+uiFiltered(折叠/记账) · " +
    "行控件与缩进接线齐 · 叶子无开关 · 折叠落存档并读回 · 层深单入口(2 写/3 调) · 状态行真的画出来（无 pageLbl 死代码）");
})();

// ===== SHARE AUTHOR WIRING CHECK（1.74.5）：方案「作者/来源」与「不弹窗原因落日志」的接线 =====
// 为什么用源码检查：这几处**都是接线** —— 漏了不报错、只是功能悄悄没有（行为断言要跑整套 UI / 接收流程才照得到）：
//   ① 案例模版选单导入必须盖作者 —— ★1.74.22 起：条目自带 `author`（玩家贡献的模版）就用它署名，
//      没带才退回 "技能学院"（否则模版方案会被当成「导入」）；两种写法都必须存在，缺一个就是静默丢来源；
//   ② 手建方案必须盖玩家名；③ 分享导入必须盖发送者名；
//   ④ 方案列表 tooltip 必须走**唯一**的作者标签函数（不许在 UI 里另拼一份文案）；
//   ⑤ 头衔评定必须锚在「自创」（src ~= "text"）；⑥ 「不弹窗」必须走统一日志前缀（否则查不到原因）。
(function () {
  const bad = [];
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  if (eh.indexOf('ioImportText(p.text, p.author or "技能学院")') < 0) bad.push("案例模版选单导入没盖作者（应是 p.author or 技能学院 —— 缺 author 的模版才退回技能学院）");
  if (!/author\s*=\s*\(type\(UnitName\)/.test(eh)) bad.push("手建方案没盖作者名（UnitName）");
  if (sh.indexOf("EVAL_IMPORT_TEXT(p.text, p.sender)") < 0) bad.push("分享导入没盖发送者名");
  if (eh.indexOf("EVAL_PROF_AUTHOR_LABEL(prof)") < 0) bad.push("方案列表 tooltip 没走 EVAL_PROF_AUTHOR_LABEL（单一来源）");
  if (sh.indexOf('p.src ~= "text"') < 0) bad.push("头衔评定没锚在「自创」（src ~= text）");
  if (sh.indexOf('"[分享] 不弹窗："') < 0) bad.push("分享「不弹窗」没有统一日志前缀（查不到原因）");
  if (sh.indexOf("弹出方案分享窗") < 0) bad.push("分享弹窗成功时没有写日志");
  if (bad.length) {
    console.log("SHARE AUTHOR WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("SHARE AUTHOR WIRING CHECK: 三处导入点都盖作者 · tooltip 走单一标签函数 · 头衔只算自创 · 不弹窗原因统一落日志");
})();

// ===== SHARE SCENE WIRING CHECK（1.74.5）：场景描述（接收/拒绝 × 有/无目标）的接线 =====
// 这几处漏了**不报错、只是没那句话**（行为断言要跑完整接收+导入流程才照得到）：
//   ① 两个按钮回调都得调 shSendScene（导入 / 忽略各一组文案）；
//   ② 四张表必须三语言齐（少一种语言 = 那种语言下抽不到句子）；
//   ③ 头衔色必须走 EVAL_TITLE_CURRENT()（唯一来源，不许另写色表）；
//   ④ 场景描述必须**进限频队列**（shTxQ），不许直发 —— 与彩蛋反应同帧倾泻会被客户端吞（实测定案）。
(function () {
  const bad = [];
  const sh = fs.readFileSync(path.join(__dirname, "Share.lua"), "utf8");
  if (sh.indexOf('shSendScene("imp")') < 0) bad.push("导入回调没接 shSendScene(\"imp\")");
  if (sh.indexOf('shSendScene("ign")') < 0) bad.push("忽略回调没接 shSendScene(\"ign\")");
  if (sh.indexOf("EVAL_TITLE_CURRENT") < 0) bad.push("场景描述没走 EVAL_TITLE_CURRENT（头衔色单一来源）");
  if (sh.indexOf("table.insert(shTxQ, { body = txt, chan = chan })") < 0) {
    bad.push("场景描述没进限频队列 shTxQ（直发会被客户端吞/刷屏）");
  }
  const keys = ["SH_SCENE_IMP_IDLE", "SH_SCENE_IMP_TGT", "SH_SCENE_IGN_IDLE", "SH_SCENE_IGN_TGT", "SH_SCENE_ZONE_FALLBACK"];
  for (const lf of ["Locales/zhCN.lua", "Locales/enUS.lua", "Locales/ruRU.lua"]) {
    const src = fs.readFileSync(path.join(__dirname, lf), "utf8");
    for (const k of keys) {
      if (src.indexOf(k + " = ") < 0 && src.indexOf(k + " =") < 0) bad.push(lf + " 缺 " + k);
    }
  }
  if (bad.length) {
    console.log("SHARE SCENE WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("SHARE SCENE WIRING CHECK: 导入/忽略两处已接 · 四表三语言齐 · 头衔色走单一来源 · 场景描述进限频队列");
})();

// ===== README TABLE CHECK（1.72.0）：版本行必须落在「更新日志」表里，不能落进「模块」表 =====
// ★背景（1.72.0 实事故）：发版时用脚本往 README 插版本行，脚本按「第一张表的表头分隔行」定位，
//   把 1.72.0 / 1.71.24 / 1.71.23 / 1.71.22 **四行插进了开头的「模块」功能表**里，
//   而真正的「更新日志」表在 20 多行之下 —— 用户在 GitHub 首页一眼看到功能表里混着版本号。
//   ★这是典型的「脚本按结构定位、但结构假设错了」：**不报错、只是位置不对**，行为断言照不到，
//     所以必须落成源码级检查（本项目铁律：审计/排查必须变成可执行闸门）。
// 判据：① 每个 README 的版本行**全部出现在「更新日志」标题之后**（出现在之前 = 落错表）
//       ② 每个 README 的版本行**恰好 10 行**（发布规则：README 只保留最近 10 个）
//       ③ CHANGELOG.md 自己的版本表**保留完整历史**（>= 20 行）——它不受「10 行」规则约束
(function () {
  const READMES = [
    ["README.md", /^##\s*更新日志/],
    ["README_en.md", /^##\s*Changelog/],
    ["README_ru.md", /^##\s*Журнал обновлений/],
  ];
  const VER_ROW = /^\|\s*\*\*\d/;
  const bad = [];
  for (const [f, h2re] of READMES) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) { bad.push(f + " missing"); continue; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    let h2 = -1;
    for (let i = 0; i < lines.length; i++) if (h2re.test(lines[i])) { h2 = i; break; }
    if (h2 < 0) { bad.push(f + " has no changelog heading"); continue; }
    let rows = 0, misplaced = 0;
    for (let i = 0; i < lines.length; i++) {
      if (!VER_ROW.test(lines[i])) continue;
      rows++;
      if (i < h2) misplaced++;   // ★出现在「更新日志」标题之前 = 插错表了
    }
    if (misplaced > 0) bad.push(f + " has " + misplaced + " version row(s) ABOVE the changelog table (wrong table)");
    if (rows !== 10) bad.push(f + " has " + rows + " version rows (expected exactly 10)");
  }
  // ③ CHANGELOG 保留完整历史
  const cp = path.join(__dirname, "CHANGELOG.md");
  if (fs.existsSync(cp)) {
    const rows = fs.readFileSync(cp, "utf8").split(/\r?\n/).filter((l) => VER_ROW.test(l)).length;
    if (rows < 20) bad.push("CHANGELOG.md has only " + rows + " version rows (should keep full history, >=20)");
  }
  if (bad.length) {
    console.log("README TABLE CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("README TABLE CHECK: 3 READMEs x 10 version rows, all inside the changelog table");
})();

// ===== MILESTONE CHECK（1.72.0）：里程碑「在上、归纳为主、每节 <=10 条」 =====
// ★背景（用户 1.72.0 明确）：「里程碑是要你总结上个里程碑到最新版本的信息归纳，而不是把版本信息全部罗列，
//   不然内容太多了 —— 每次里程碑归纳内容最终控制在 10 条以内。」
//   ＋「项目文件内的更新日志在里程碑下面」——即 README 的板块顺序是
//   **## 🏁 里程碑 在上、## 更新日志 在下**（1.72.0 起把里程碑整块移到更新日志之前）。
//   → 这两条规则光写进记忆体（CLAUDE.md）挡不住：记忆体是给人/AI 读的提醒，不是闸门。
//     本项目铁律：**审计/排查必须落成可执行闸门**，所以这里钉死四件事。
// 判据：① 3 个 README 都有「里程碑」板块（## 🏁 …）
//       ② 里程碑板块位于「更新日志」板块**之前**（顺序反了 = 更新日志跑到里程碑上面，用户定的版式）
//       ③ 板块标题的版本范围末端 == 当前 VERSION，且**最新那个小节**的范围末端也 == 当前 VERSION
//          （守着「发版只更新了 CHANGELOG、忘了改里程碑范围」）
//       ④ 板块正文（不含标题本身）的**非空行 1..10**（用户定：「10 个点、10 行文字以内」，一条 = 一行；
//          守着「又想把版本流水账搬回来」——超过 10 行就是要罗列了）
//       ⑤ 每条必须是 **`- ` 列表项**（守「排版」：连续普通段落行会被 Markdown 合并成一大段 —— 1.72.0 实事故）
// ★条目判据 = 板块里每行就是一条（三个语种写法一致：**emoji 主题**（版本范围）：做了什么 + 判据）。
(function () {
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  const vm = toc.match(/##\s*Version:\s*([0-9.]+)/);
  if (!vm) { console.log("MILESTONE CHECK: skipped (no ## Version in toc)"); return; }
  const ver = vm[1];
  const bad = [];
  const READMES = [
    ["README.md", /^##\s*更新日志/],
    ["README_en.md", /^##\s*Changelog/],
    ["README_ru.md", /^##\s*Журнал обновлений/],
  ];
  for (const [f, chgRe] of READMES) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) { bad.push(f + " missing"); continue; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const h = lines.findIndex((l) => /^##\s*🏁/.test(l));
    if (h < 0) { bad.push(f + " has no milestone section"); continue; }
    // ★2：里程碑必须在「更新日志」之上（用户定：更新日志在里程碑下面）
    const chg = lines.findIndex((l) => chgRe.test(l));
    if (chg < 0) bad.push(f + " has no changelog heading");
    else if (h > chg) bad.push(f + " puts the milestone section BELOW the changelog (must be above)");
    let e = lines.length;
    for (let i = h + 1; i < lines.length; i++) { if (/^##\s/.test(lines[i])) { e = i; break; } }
    const headVer = (lines[h].match(/[0-9]+\.[0-9]+\.[0-9]+/g) || []);
    if (!headVer.length || headVer[headVer.length - 1] !== ver) {
      bad.push(f + " milestone heading range does not end at " + ver);
    }
    // ★④ 板块正文（不含标题本身）的**非空行**必须 1..10 —— 用户 1.72.0 定：
    //   「里程碑控制在 10 个点、10 行文字以内」；★**一条 = 一行**（写成一段四五行的细节就算超），
    //   这就是「归纳不罗列」的可执行形态：超过 10 行说明又想把版本流水账搬回来了。
    const body = [];
    for (let i = h + 1; i < e; i++) { if (lines[i].trim() !== "") body.push(lines[i]); }
    if (body.length < 1 || body.length > 10) {
      bad.push(f + " milestone body has " + body.length + " lines (need 1..10: 10 points, 1 line each)");
    }
    // ★⑤ 每条必须是**列表项**（`- ` 开头）—— 1.72.0 实事故：10 条写成连续**普通段落行**，
    //   Markdown 把相邻行**合并成一大段**（用户在 GitHub 上看到的就是「排版混乱」一大坨），
    //   列表项才会各占一行。★这条正是「行为/内容都对、只是渲染不对」的典型，只能靠结构检查守。
    const notList = body.filter((l) => !/^-\s+/.test(l));
    if (notList.length) {
      bad.push(f + " has " + notList.length + " milestone line(s) that are NOT list items (Markdown would merge them into one paragraph)");
    }
  }
  if (bad.length) { console.log("MILESTONE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("MILESTONE CHECK: 3 READMEs, milestone above changelog, range ends at " + ver + ", body <=10 list items");
})();

// ===== FRAME NAME CLASH CHECK（1.72.2）：具名帧会占用同名全局，绝不能与插件内全局函数同名 =====
// ★背景（1.72.2 实事故）：DataSearch.lua 里 `function EVAL_DS_HUD(on)` 与
//   `CreateFrame("Frame","EVAL_DS_HUD",canvas)` **同名** → 真客户端里具名帧会成为同名全局、
//   把函数顶掉 → `/eh ds hud` 入口的 `if type(EVAL_DS_HUD)=="function"` 不成立
//   → **命令静默失效**（HUD 打开后再也关不掉，且没有任何报错/提示）。
//   ★为什么以前一直没发现：测试桩的 CreateFrame 只存 __name、**不挂全局** → 「同名冲突」在测试里根本不存在。
//   1.72.2 把桩改成真客户端行为（具名帧挂全局）后，组 54 当场报 `attempt to call a table value` —— 这就是暴露途径。
// 判据：全仓扫描 `CreateFrame(..., "NAME", ...)` 的第二参，不得与任何 `function NAME(` 同名。
(function () {
  const files = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua", "tools/DragFrames.lua", "tools/LayerFix.lua", 'quest/QuestData.lua', 'quest/QuestBulk.lua', 'quest/QuestChains.lua' ];
  const funcs = {}, frames = [];
  for (const f of files) {
    if (!fs.existsSync(path.join(__dirname, f))) continue;
    const lines = fs.readFileSync(path.join(__dirname, f), "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const fm = lines[i].match(/^\s*function\s+([A-Za-z_]\w*)\s*\(/);
      if (fm) funcs[fm[1]] = f + ":" + (i + 1);
      const cm = lines[i].match(/CreateFrame\s*\(\s*[^,]+,\s*"([^"]+)"/);
      if (cm) frames.push([cm[1], f + ":" + (i + 1)]);
    }
  }
  if (!frames.length) {
    console.log("FRAME NAME CLASH CHECK: FAIL - no named frames found (the scan pattern must have gone stale)");
    process.exitCode = 1;
    return;
  }
  const bad = frames.filter(function (p) { return funcs[p[0]]; })
    .map(function (p) { return p[0] + " (" + p[1] + " shadows function at " + funcs[p[0]] + ")"; });
  if (bad.length) {
    console.log("FRAME NAME CLASH CHECK: FAIL - a named frame shadows an addon global function: " + bad.join(", "));
    process.exitCode = 1;
    return;
  }
  console.log("FRAME NAME CLASH CHECK: " + frames.length + " named frames, none shadows an addon global function");
})();

// ===== PET ICON CHECK（1.73.4）：抓宠帮手的图标必须是**客户端清单里真的存在**的路径 =====
// ★★1.73.4 事实更正（这一条推翻了 1.73.0 的假设）：本客户端的纹理路径是 **Unreal 资产路径**
//   `/Game/Interface/Icons/<名字>_TEX`，而**不是** 1.12 的 `Interface\Icons\<名字>`——
//   写成后者不会"不画"，而是显示成引擎的**「?」缺图占位**（用户截图里那一屏问号就是这么来的）。
//   ★而且「内置图标磁盘取不到」只对了一半：**宏图标表**（GetNumMacroIcons/GetMacroIconInfo）
//   能把整表路径吐出来 → `/eh go icons` 采集进 `doc/图标路径清单.txt`（1018 条）。
//   所以现在这条检查可以做到**真正的存在性校验**：逐个精确匹配白名单，写错一个当场 FAIL。
// 判据：① 每个 icon 都以 /Game/Interface/Icons/ 开头、_TEX 结尾；② **逐条存在于白名单**；
//   ③ 没有扩展名（本客户端约定）；④ 数量 ≥ 20；⑤ 技能之间不撞图、家族之间不撞图（防复制粘贴错）。
(function () {
  const p = path.join(__dirname, 'PetData.lua');
  if (!fs.existsSync(p)) { console.log('PET ICON CHECK: skipped (no PetData.lua)'); return; }
  const wl = path.join(__dirname, 'doc', '图标路径清单.txt');
  if (!fs.existsSync(wl)) {
    console.log('PET ICON CHECK: FAIL - 缺少 doc/图标路径清单.txt（游戏内 /eh go icons 采集所得，是图标存在性的唯一依据）');
    process.exitCode = 1;
    return;
  }
  const white = new Set(fs.readFileSync(wl, 'utf8').split(/\r?\n/).map(s => s.trim()).filter(s => s && s.charAt(0) !== '#'));
  const src = fs.readFileSync(p, 'utf8');
  const PREFIX = '/Game/Interface/Icons/';
  const SUFFIX = '_TEX';
  const icons = [];
  const re = /icon = "([^"\r\n]+)"/g;
  let m;
  while ((m = re.exec(src)) !== null) icons.push(m[1]);
  const badForm = icons.filter(v => v.indexOf(PREFIX) !== 0 || v.slice(-SUFFIX.length) !== SUFFIX);
  const notInWhite = icons.filter(v => !white.has(v));
  const withExt = icons.filter(v => /\.(tga|blp|png)$/i.test(v));
  const legacy = icons.filter(v => v.indexOf('Interface\\Icons') === 0);
  // ★★1.73.6 覆盖面修正（本轮实事故）：本检查原来**只扫 PetData.lua 的 icon = "…"** —— 于是
  //   PetHelper.lua 里那行 local PH_ZOOM_ICON = "Interface\Icons\INV_Misc_Spyglass_02" **从未被检查过**，
  //   它同时犯了两个错（① 1.12 老前缀 ② 客户端里根本没有 _02，清单里只有 _01）却一路绿灯；
  //   用户看到的就是引擎的「?」缺图占位 + 露在外面的保底文字「查」（截图圈出处）。
  //   → 现在 PetHelper.lua 里**任何**客户端纹理字面量（老形态或 Unreal 形态）都必须精确在白名单里。
  const phPath = path.join(__dirname, 'PetHelper.lua');
  const phIcons = [];
  if (fs.existsSync(phPath)) {
    const phSrc = fs.readFileSync(phPath, 'utf8');
    // ★★注意「源码里的转义」：Lua 源文件里写的是 "Interface\\Icons\\X"（两个反斜杠），
    //   所以正则必须匹配 **两** 个反斜杠（regex 的 \\\\），取出来后再 unesc 还原成单反斜杠再比对 ——
    //   第一版这里只写了一个反斜杠 → 老形态**永远匹配不到**，于是「LEGACY」这条判据其实是死的
    //   （变异实测：M75 被下面的「0 个纹理」覆盖面守卫挡住，看着像捕获、其实走的是另一条路）。
    const rePh = /"((?:Interface\\\\Icons\\\\|\/Game\/Interface\/Icons\/)[^"\r\n]*)"/g;
    let mph;
    while ((mph = rePh.exec(phSrc)) !== null) phIcons.push(mph[1]);
  }
  const unesc = (s) => s.split('\\\\').join('\\'); // 源码转义 → 运行时真值（Unreal 形态没有反斜杠，原样返回）
  const phLegacy = phIcons.filter(v => unesc(v).indexOf('Interface\\Icons') === 0);
  const phBad = phIcons.filter(v => { const u = unesc(v); return u.indexOf(PREFIX) !== 0 || u.slice(-SUFFIX.length) !== SUFFIX; });
  const phNotWhite = phIcons.filter(v => !white.has(unesc(v)));
  // 技能段（skills 表）与家族段（families 表）分别查重
  const skillsSeg = src.slice(src.indexOf('EVAL_PET_DB.skills'), src.indexOf('EVAL_PET_DB.ranks') > 0 ? src.indexOf('EVAL_PET_DB.ranks') : src.length);
  const famSeg = src.slice(src.indexOf('EVAL_PET_DB.families'));
  const segIcons = seg => { const out = []; const rr = /icon = "([^"\r\n]+)"/g; let mm; while ((mm = rr.exec(seg)) !== null) out.push(mm[1]); return out; };
  const skIcons = segIcons(skillsSeg), famIcons = segIcons(famSeg);
  const dupSk = skIcons.filter((v, i) => skIcons.indexOf(v) !== i);
  const dupFam = famIcons.filter((v, i) => famIcons.indexOf(v) !== i);
  console.log('PET ICON CHECK: ' + icons.length + ' icon refs (PetData) + ' + phIcons.length + ' (PetHelper), ' +
    (badForm.length + phBad.length) + ' bad format, ' + (notInWhite.length + phNotWhite.length) +
    ' not in client list, ' + withExt.length + ' with extension, ' + (dupSk.length + dupFam.length) + ' duplicated');
  if (legacy.length || phLegacy.length) {
    console.log('  LEGACY 1.12 PATH: ' + legacy.concat(phLegacy).slice(0, 3).join(' | ') + '  → 本客户端会显示成「?」缺图占位');
    process.exitCode = 1;
    return;
  }
  if (phIcons.length < 1) {
    console.log('  FAIL - PetHelper.lua 里一个客户端纹理都没扫到：要么放大镜图标被删了，要么扫描正则又不匹配了');
    process.exitCode = 1;
    return;
  }
  if (phBad.length) {
    console.log('  BAD FORMAT (PetHelper): ' + phBad.slice(0, 3).join(' | '));
    process.exitCode = 1;
    return;
  }
  if (phNotWhite.length) {
    console.log('  NOT IN CLIENT LIST (PetHelper): ' + phNotWhite.slice(0, 3).join(' | ') + '  (写错路径 = 引擎画「?」)');
    process.exitCode = 1;
    return;
  }
  if (badForm.length) {
    console.log('  BAD FORMAT: ' + badForm.slice(0, 3).join(' | ') + '  (want ' + PREFIX + '<name>' + SUFFIX + ')');
    process.exitCode = 1;
    return;
  }
  if (notInWhite.length) {
    console.log('  NOT IN CLIENT LIST: ' + notInWhite.slice(0, 3).join(' | ') + '  (写错路径 = 引擎画「?」)');
    process.exitCode = 1;
    return;
  }
  if (withExt.length) {
    console.log('  HAS EXTENSION: ' + withExt.slice(0, 3).join(' | ') + '  (this client wants no extension)');
    process.exitCode = 1;
    return;
  }
  if (dupSk.length || dupFam.length) {
    console.log('  DUPLICATED: skills=[' + dupSk.slice(0, 2).join(',') + '] families=[' + dupFam.slice(0, 2).join(',') + ']');
    process.exitCode = 1;
    return;
  }
  if (icons.length < 20) { console.log('PET ICON CHECK: FAIL - expected >= 20 icon refs, got ' + icons.length); process.exitCode = 1; return; }
})();
checkIconAssets();

// ===== CHANKEY WIRING CHECK（1.74.0）：拦截关键字的**配置接线**（用户要的下拉多选 + 输入框） =====
// 背景：关键字配置是典型的「UI 接线」型功能 —— 行上没按钮、下拉不是多选、输入框没接上回调，
//   行为断言照样全绿，而用户在界面里**根本配不了**（本项目「漏接不报错、只是显示不对」的老坑）。
// 判据：
//   ① 那一行必须是复合行 kw，且值按钮的真实 OnClick 调 EVAL_TB_CHANKEYS_OPEN；
//   ② 打开时 multi/selected/locked/search/onFreeText 五个参数必须齐（多选 + 输入框的最小充分条件）；
//   ③ 输入框回调只许走唯一入口 EVAL_TB_CHANKEY_ADD（别处再写一份 = 两处逻辑漂移）；
//   ④ 文本判据必须读**可配置**的关键字（EVAL_TB_CHAN_KEYS），不许退回硬编码表；
//   ⑤ 事件名判据必须覆盖用户要的**两种**（自己进出 NOTICE + 玩家进出 JOIN/LEAVE）。
(function () {
  const raw = fs.readFileSync(path.join(__dirname, 'Toolbox.lua'), 'utf8');
  // ★先摘行尾注释：本文件里到处写着这些名字的**说明**，不摘就是假 FAIL（与 CHAT COLOR WIRING 同一条纪律）
  const tb = raw.split(/\r?\n/).map(function (l) { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
  const bad = [];
  // ① 复合行 + 值按钮接线
  if (tb.indexOf('{ t = "kw", key = "chanJoin"') < 0) bad.push('行模型里没有复合行 { t = "kw", key = "chanJoin" }');
  if (tb.indexOf('EVAL_TB_CHANKEYS_OPEN(r.chv.btn)') < 0) bad.push('值按钮的 OnClick 没接 EVAL_TB_CHANKEYS_OPEN');
  if (tb.indexOf('r.chv.text:SetText((EVAL_TB_CHANKEY_SUMMARY()))') < 0) bad.push('值按钮文案没走 EVAL_TB_CHANKEY_SUMMARY（用户看不到「关键字(N)」）');
  // ② 多选 + 输入框的五个参数
  for (const tok of ['multi = true', 'selected = sel', 'locked = locked', 'search = true', 'onFreeText =']) {
    if (tb.indexOf(tok) < 0) bad.push('EVAL_TB_CHANKEYS_OPEN 缺少「' + tok + '」（多选下拉/输入框的最小充分条件）');
  }
  // ③ 加词的唯一入口
  const addSites = (tb.match(/EVAL_TB_CHANKEY_ADD\(/g) || []).length;
  if (addSites !== 2) bad.push('EVAL_TB_CHANKEY_ADD 出现 ' + addSites + ' 次（要 2：定义 + onFreeText 回调；多一处就是第二份加词逻辑）');
  // ④ 判据读可配置关键字
  if (tb.indexOf('function EVAL_TB_CHAN_KEYS()') < 0) bad.push('没有 EVAL_TB_CHAN_KEYS（可配置关键字的唯一真源）');
  if (tb.indexOf('local k = EVAL_TB_CHAN_KEYS()') < 0) bad.push('EVAL_TB_CHAN_BLOCK 没有读可配置关键字（退回硬编码表 = 配置无效）');
  if (tb.indexOf('TB_CHAN_KEY_GROUPS') < 0) bad.push('没有关键字分组表 TB_CHAN_KEY_GROUPS');
  // ⑤ 两种事件都在判据里
  for (const ev of ['CHAT_MSG_CHANNEL_NOTICE', 'CHAT_MSG_CHANNEL_JOIN', 'CHAT_MSG_CHANNEL_LEAVE']) {
    if (tb.indexOf(ev) < 0) bad.push('事件名判据缺少 ' + ev + '（用户要求两种都拦）');
  }
  if (bad.length) { console.log('CHANKEY WIRING CHECK: FAIL - ' + bad.join('; ')); process.exitCode = 1; return; }
  console.log('CHANKEY WIRING CHECK: 复合行 kw + 多选下拉（multi/selected/locked）+ 输入框（search/onFreeText）+ 加词唯一入口 + 判据读可配置词 + 两种事件都拦');
})();


// ===== RARE WATCH WIRING CHECK（1.74.23）：稀有提醒转播的四处接线，漏一处都是**静默**失效 =====
// ★为什么必须源码级（行为断言照不到「没接上」）：
//   ① 安装调用点若不在 VARIABLES_LOADED 分支里 → 载入期全局 UnrealQuest 还不存在（目录名排序
//      EvalHelp(E) 先于 UnrealQuest(U)）→ 功能永远不装，且**不报错**；
//   ② 命令前缀必须按**字节**写对（string.sub 是字节下标 —— 1.74.5 在「go 喂食」上正是栽在这里）；
//   ③ 包装 Show 必须**透传返回值**且**照原样抛出对方的错误**（吞掉别人的错 = 把别人的 bug 藏起来）；
//   ④ 兜底轮询帧的父级必须是 WorldFrame（挂 UIParent 时开全屏世界地图会整个停摆 —— 1.70.39 的坑）。
(function () {
  // ★1.74.27 稀有提醒转播**已提取到 tools/RareWatch.lua**（用户：「将以上功能提取到独立文件内 ./tools」）⇒
  //   本检查分两段扫：**接线点**（安装调用 / 命令前缀 / SetItemRef 分派）仍在主文件与 Toolbox.lua；
  //   **实现模式**（包装 / 透传 / 照抛 / 兜底父级 / 色表 / 链接形态）搬到了新模块 —— 两段都必须扫到，
  //   否则「文件搬走了、检查却还只看老文件」会变成一条永远为 FAIL 或永远为 PASS 的死检查。
  const main = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  const rwRel = "tools/RareWatch.lua";
  const rwAbs = path.join(__dirname, rwRel);
  const bad = [];
  if (!fs.existsSync(rwAbs)) bad.push("找不到 " + rwRel + "（稀有提醒转播应住在这里）");
  const src = main + "\n" + (fs.existsSync(rwAbs) ? fs.readFileSync(rwAbs, "utf8") : "");
  const atInit = main.indexOf("EVAL_HELPInitFrame");
  const atInstall = src.indexOf("pcall(EVAL_RW_INSTALL)");
  const atAuto = src.indexOf('pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_REGEN_DISABLED")');
  if (atInit < 0) bad.push("找不到初始化帧 EVAL_HELPInitFrame");
  else if (atInstall < 0) bad.push("VARIABLES_LOADED 处理里没有 pcall(EVAL_RW_INSTALL)（功能永远不装）");
  else if (atAuto > 0 && atInstall > atAuto) bad.push("EVAL_RW_INSTALL 不在 VARIABLES_LOADED 分支里（跑到注册事件之后了）");
  const wantPrefix = 'string.sub(msg, 1, 9) == "go 稀有"'; // 命令分支仍留在主文件（命令表在那里）
  if (src.indexOf(wantPrefix) < 0) {
    bad.push("命令分支不是 " + wantPrefix + "（字节数写错 = 命令静默无反应）");
  } else if (Buffer.byteLength("go 稀有", "utf8") !== 9) {
    bad.push("前缀字节数基准漂了：实际 " + Buffer.byteLength("go 稀有", "utf8"));
  }
  if (src.indexOf("RA.Show = function") < 0) bad.push("没有包装 RA.Show（主路缺失）");
  if (src.indexOf("return a, b, c, d") < 0) bad.push("包装没有透传原函数返回值");
  if (src.indexOf("error(a, 0)") < 0) bad.push("包装没有按原语义抛出对方错误（会吞掉别人的 bug）");
  if (src.indexOf('rawget(_G, "WorldFrame")') < 0) bad.push("兜底 tick 的父级不是 WorldFrame（开全屏地图会停摆）");
  // ⑤ 1.74.24：品阶染色（4 档 · 每档 |c + 8 位）+ 名字链接（色码在外、链接在里）
  const colorBlock = src.match(/EVAL_RW_RANK_COLOR_MAP = \{[\s\S]*?\n\}/);
  if (!colorBlock) {
    bad.push("找不到 EVAL_RW_RANK_COLOR_MAP（品阶染色表）");
  } else {
    const cols = (colorBlock[0].match(/\|c[0-9a-fA-F]+/g) || []);
    if (cols.length !== 4) bad.push("品阶色表应为 4 档，实际 " + cols.length + " 项");
    const badLen = cols.filter(function (c) { return c.length !== 10; }); // "|c" + 8 位
    if (badLen.length) bad.push("品阶色码不是 8 位（6 位不解析 / 7 位吞整条）：" + badLen.join(","));
  }
  if (src.indexOf('color .. "|H" .. token .. "|h["') < 0) bad.push("名字链接形态不是「色码在外 + 链接在里」（|c..|H..|h[名]|h|r）");
  if (src.indexOf("function EVAL_RW_LINK_CLICK") < 0) bad.push("没有 EVAL_RW_LINK_CLICK（SetItemRef 分派入口）");
  // ★1.74.26 用户定案「不要和那边插件的机制管理」：稀有转播里**不许**再出现地图/坐标耦合
  if (src.indexOf("EVAL_DS_SHOWMAP") >= 0 || src.indexOf("EVAL_RW_NEAREST_LOC") >= 0 || src.indexOf("GetCurrentZoneView") >= 0) {
    bad.push("稀有转播又跟那边插件的地图机制耦合了（EVAL_DS_SHOWMAP / NEAREST_LOC / GetCurrentZoneView）");
  }
  if (src.indexOf("function EVAL_RW_TARGET(") < 0) bad.push("没有 EVAL_RW_TARGET（左键 = 切目标）");
  const tb = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
  // ★必须要求「语句**以**它开头」：只查「文件里出现过这串」的话，把整行改成 `if false and string.find(...)`
  //   照样能骗过检查（本轮变异测当场撞到）—— 一个能自欺的守卫等于没有守卫。
  const ehrwStmt = 'if string.find(link, "^EHRW:") then';
  const hasEhrw = tb.split(/\r?\n/).some(function (l) { return l.trim().indexOf(ehrwStmt) === 0; });
  if (!hasEhrw) bad.push("Toolbox 的 SetItemRef 分派里没有 EHRW: 分支（语句必须直接以它开头；点了名字什么都不会发生）");
  if (bad.length) {
    console.log("RARE WATCH WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("RARE WATCH WIRING CHECK: 安装点(VARIABLES_LOADED) · 命令前缀 9 字节 · Show 包装(透传+照抛) · 兜底 tick 父级=WorldFrame · 品阶 4 色 8 位 · 名字链接形态 · SetItemRef 分派");
})();
// ===== ONUPDATE ARG CHECK（1.74.31）：OnUpdate 回调**一个参数都不传** —— 绝不许拿参数当帧用 =====
// 背景（真机事故）：载入报告帧写成 `frame:SetScript("OnUpdate", function(f) pcall(f.SetScript, f, "OnUpdate", nil) end)`
//   ⇒ 本客户端调 OnUpdate 时**不传任何参数** ⇒ f = nil ⇒ 当场
//   `EvalHelp.lua:9495: attempt to index local 'f' (a nil value)`（用户截图，红字弹窗）。
//   ★为什么行为断言照不到：测试里从来没有人**按真机的方式**去调那个回调（要么直调被调函数、
//     要么调用点自己把帧传进去）——「接线对不对」这一类只有源码检查 + 一条「零参数调用」的行为断言能补位。
//   ★同类风险：全项目十几处 OnUpdate 注册点，只要有一处收参数并按参数用，就是同一个 bug 的下一次复发。
//   判据：① 匿名回调 `function(<非空参数>)` → FAIL；② 具名回调（`SetScript("OnUpdate", name)`）在
//   本项目里 `function name(<非空参数>)` → FAIL；③ 注册点数量下限（少于 10 处 = 正则已失效 ⇒ 必须 FAIL，
//   一条永远为 PASS 的死检查比没有更糟）。
(function () {
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  const mods = toc.split(/\r?\n/)
    .map(function (l) { return l.trim(); })
    .filter(function (l) { return l && l.charAt(0) !== "#" && /\.lua$/i.test(l); })
    .map(function (l) { return l.replace(/\\/g, "/"); });
  const bad = [];
  if (mods.length < 30) bad.push("从 toc 解出的模块太少（" + mods.length + "）—— 锚点变了？");
  const nocomment = function (s) {
    return s.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  };
  const named = {};
  const anon = [];
  const regs = [];
  mods.forEach(function (rel) {
    const p = path.join(__dirname, rel);
    if (!fs.existsSync(p)) { bad.push("toc 里列了但磁盘上没有：" + rel); return; }
    nocomment(fs.readFileSync(p, "utf8")).split("\n").forEach(function (l, i) {
      const mDef = l.match(/function\s+([A-Za-z_][\w.:]*)\s*\(([^)]*)\)/);
      if (mDef) named[mDef[1].split(/[.:]/).pop()] = mDef[2];
      const mReg = l.match(/SetScript\s*\(\s*["']OnUpdate["']\s*,\s*(function\s*\(([^)]*)\)|[A-Za-z_][\w.:]*)/);
      if (!mReg) return;
      regs.push({ file: rel, line: i + 1, handler: mReg[1], params: mReg[2] });
      if (mReg[2] !== undefined && mReg[2].trim() !== "") {
        anon.push({ file: rel, line: i + 1, params: mReg[2].trim() });
      }
    });
  });
  anon.forEach(function (a) {
    bad.push(a.file + ":" + a.line + " 匿名 OnUpdate 回调收了参数（" + a.params + "）—— 本客户端不传参，索引它必炸");
  });
  regs.forEach(function (r) {
    if (r.params !== undefined) return;
    const nm = r.handler.split(/[.:]/).pop();
    if (nm === "nil" || nm === "true" || nm === "false") return; // 摘钩子（SetScript("OnUpdate", nil)）
    if (!(nm in named)) {
      bad.push(r.file + ":" + r.line + " 具名回调 " + nm + " 在本项目里找不到 function 定义（无法核对参数）");
      return;
    }
    if (String(named[nm]).trim() !== "") {
      bad.push(r.file + ":" + r.line + " 具名回调 " + nm + "(" + named[nm] + ") 收了参数 —— 本客户端不传参");
    }
  });
  if (regs.length < 10) bad.push("全项目只找到 " + regs.length + " 处 OnUpdate 注册（判据锚点失效 ⇒ 拒绝放行）");
  if (bad.length) {
    console.log("ONUPDATE ARG CHECK: FAIL - " + bad.slice(0, 6).join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("ONUPDATE ARG CHECK: " + regs.length + " 处 OnUpdate 回调全部零参数（本客户端不传帧，禁 function(x) 形态）");
})();

// ★1.73.5 把 doc/图标路径清单.txt（客户端采集的 1018 条**真实路径**）注入成测试素材：
//   图标库的语义名/关键字过滤必须拿**生产形态**（/Game/Interface/Icons/X_TEX）来验 ——
//   只喂编出来的短名，会把「_TEX 后缀没剥 / 路径前缀不同」这类**只有真机才犯、且一声不响**的错一起放过。
const iconFixture = (function () {
  try {
    const p = path.join(__dirname, 'doc', '图标路径清单.txt');
    const names = fs.readFileSync(p, 'utf8').split(/\r?\n/)
      .map(s => s.trim())
      .filter(s => s && s.charAt(0) !== '#')
      .filter(s => /^\/Game\/Interface\/Icons\/[A-Za-z0-9_]+_TEX$/.test(s));
    if (names.length < 1000) return null;
    return 'TEST_ICON_FIXTURE = {"' + names.join('","') + '"}';
  } catch (e) { return null; }
})();
const L=lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// ★★省时模式（1.75.21）：组 192（任务线推荐弹窗，约 1300 行）独占全套 28s 里的 ~22s
//   （每次刷新都要在 fengari 里跑一遍 673 条全量检索 + 17 行重绘）。
//   日常小改用 --quick 或 EVAL_TEST_QUICK=1 跳过它；发版前 / 改动任务线·弹窗·数据层时跑全量。
//   ★跳过的组会**如实打印 SKIPPED**（绝不静默变绿）。
const QUICK_MODE = process.argv.includes("--quick") || process.env.EVAL_TEST_QUICK === "1";
if (QUICK_MODE) {
  console.log("★ 省时模式（--quick）：跳过 GROUP 192（任务线推荐弹窗）—— 改动任务线/弹窗/数据层时请跑全量 node test_engine.js");
  if (lauxlib.luaL_dostring(L, to_luastring("EVAL_TEST_SKIP_HEAVY = true")) !== lua.LUA_OK) {
    console.log("LOAD ERROR [quick flag]: " + lua.lua_tojsstring(L, -1)); process.exit(1);
  }
}
// ===== TEST LOAD ORDER CHECK（1.75.1）：`test_assert.lua` 必须排在**所有** `tools/*.lua` 之后 =====
// 背景（合并两支时当场踩到）：工具模块在**自己的文件里、载入期**把渲染函数登记进 `EVAL_TB_MOD_ROWS`，
//   而 `test_assert.lua` 里的工具箱断言（组 200）走**真实渲染路径**去取它 —— 模块排在 test_assert 后面
//   时那一刻注册表还不存在 ⇒ 组 200 报 `got=false want=true`，模块本身却完全正常（toc 里没这个问题，
//   只有本 harness 的清单会踩，所以行为断言照不到，必须源码检查补位）。
//   ★判据：① 清单里必须有 test_assert.lua；② 每个 `tools/*.lua` 的下标都要**小于**它；
//     ③ 锚点自检：清单里至少 5 个 tools 模块（少了 = 正则失效 ⇒ 拒绝放行，一条永远为 PASS 的死检查比没有更糟）。
(function () {
  const self = fs.readFileSync(__filename, "utf8");
  // ★挑「真正的载入清单」：文件里还有别的 `for (const f of [...])` 循环，只认含 test_stub.lua 的那个
  //   （第一版只取第一个匹配 ⇒ 抓到别的清单 ⇒ 误报「没有 test_assert.lua」，当场被抓）。
  const reList = /for\s*\(\s*const\s+f\s+of\s*\[([\s\S]*?)\]\s*\)\s*\{/g;
  let m, body = null, cand = 0;
  while ((m = reList.exec(self))) {
    if (m[1].indexOf("test_stub.lua") >= 0) { body = m[1]; cand += 1; }
  }
  if (body === null) {
    console.log("TEST LOAD ORDER CHECK: FAIL - 找不到载入清单（锚点失效 ⇒ 拒绝放行）");
    process.exitCode = 1;
    return;
  }
  const list = body.split(",").map(function (s) { return s.trim().replace(/^['"]|['"]$/g, ""); }).filter(Boolean);
  const iAssert = list.indexOf("test_assert.lua");
  const bad = [];
  if (cand !== 1) bad.push("含 test_stub.lua 的载入清单有 " + cand + " 个（应为 1，锚点二义 ⇒ 拒绝放行）");
  if (iAssert < 0) bad.push("载入清单里没有 test_assert.lua");
  const toolsIdx = [];
  list.forEach(function (f, i) { if (/^tools\/.*\.lua$/.test(f)) toolsIdx.push([f, i]); });
  if (toolsIdx.length < 5) bad.push("清单里的 tools/*.lua 只有 " + toolsIdx.length + " 个（锚点失效 ⇒ 拒绝放行）");
  if (iAssert >= 0) {
    toolsIdx.forEach(function (t) {
      if (t[1] > iAssert) bad.push(t[0] + "（第 " + (t[1] + 1) + " 项）排在 test_assert.lua（第 " + (iAssert + 1) + " 项）之后");
    });
  }
  if (bad.length) {
    console.log("TEST LOAD ORDER CHECK: FAIL - " + bad.slice(0, 6).join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("TEST LOAD ORDER CHECK: " + toolsIdx.length + " 个 tools/*.lua 全部排在 test_assert.lua（第 " + (iAssert + 1) + " 项）之前");
})();

for(const f of ['test_stub.lua','Locales/zhCN.lua','Locales/enUS.lua','Locales/ruRU.lua','Core.lua','Engine.lua','EvalHelp.lua','examples/warrior.lua','examples/mage.lua','examples/caster.lua','examples/general.lua','examples/rogue.lua','examples/hunter.lua','examples/paladin.lua','examples/priest.lua','examples/druid.lua','examples/warlock.lua','examples/shaman.lua','examples/group.lua','Toolbox.lua','quest/QuestData.lua','quest/QuestBulk.lua','quest/QuestChains.lua','DataSearch.lua','Share.lua','IconSem.lua','IconBrowser.lua','PetData.lua','PetHelper.lua','tools/IconGrid.lua','tools/HunterHelper.lua','tools/ConsumableHelper.lua','tools/DismountHelper.lua','tools/RareWatch.lua','tools/DragFrames.lua','tools/LayerFix.lua','tools/SimpleMap.lua','addons/EH_DebugBox/EH_DebugBox.lua','test_assert.lua']){
  if(f==='test_assert.lua' && iconFixture){
    const fx=to_luastring(iconFixture);
    const stx=lauxlib.luaL_loadbuffer(L,fx,fx.length,to_luastring('icon_fixture'));
    if(stx!==lua.LUA_OK){ console.log('LOAD ERROR [icon_fixture]:',lua.lua_tojsstring(L,-1)); process.exit(1); }
    if(lua.lua_pcall(L,0,0,0)!==lua.LUA_OK){ console.log('RUNTIME ERROR [icon_fixture]:',lua.lua_tojsstring(L,-1)); process.exit(1); }
  }
  const src=fs.readFileSync(f);
  const st=lauxlib.luaL_loadbuffer(L,src,src.length,to_luastring(f));
  if(st!==lua.LUA_OK){ console.log('LOAD ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
  if(lua.lua_pcall(L,0,0,0)!==lua.LUA_OK){ console.log('RUNTIME ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
}

// ===== 工具模块自带的断言组（tests/tools/*.lua，1.74.34）=====
// 用户 1.74.34：「test 相关的搬迁到对应工具类子文件内自身管理。」
//   ⇒ 每个工具模块的断言组收在 tests/tools/<模块>.lua，在 test_assert.lua **之后**加载（要用它暴露的 EVAL_TEST_EQ）。
// ★★「少跑一个文件 = 整组断言静默消失」必须能抓：每个测试文件**最后一行**调 EVAL_TEST_MOD_DONE("<模块名>")，
//   这里把「实际跑到底的文件数」与「磁盘上的文件数」**当场对账** —— 对不上就打 FAIL 并以退出码 1 结束，
//   绝不允许「整组没跑」却照样打印 ALL TESTS PASS。
// ★★载入次序铁律（1.75.1 合并时踩到）：`test_assert.lua` **必须排在所有工具模块之后**。
//   工具模块在自己文件里、**载入期**把渲染函数登记进 `EVAL_TB_MOD_ROWS`；`test_assert.lua` 里的工具箱断言
//   （组 200 等）走真实渲染路径去取它 ⇒ 模块排在 `test_assert.lua` 后面时那一刻注册表还不存在，
//   表现是「组 200 报 got=false want=true」而模块本身完全正常（toc 顺序无此问题，只有本 harness 的清单会踩）。
const modTestDir = path.join(__dirname, 'tests', 'tools');
const modTests = fs.existsSync(modTestDir)
  ? fs.readdirSync(modTestDir).filter(f => /\.lua$/.test(f)).sort() : [];
for (const mf of modTests) {
  const rel = 'tests/tools/' + mf;
  const msrc = fs.readFileSync(path.join(modTestDir, mf));
  const mst = lauxlib.luaL_loadbuffer(L, msrc, msrc.length, to_luastring(rel));
  if (mst !== lua.LUA_OK) { console.log('LOAD ERROR [' + rel + ']:', lua.lua_tojsstring(L, -1)); process.exit(1); }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) { console.log('RUNTIME ERROR [' + rel + ']:', lua.lua_tojsstring(L, -1)); process.exit(1); }
}
{
  const summary = 'print(string.format("MODULE TESTS: %d/%d（%s）", EVAL_TEST_MOD_N or -1, ' + modTests.length +
    ', table.concat(EVAL_TEST_MOD_NAMES or {}, ", ")))';
  const st1 = lauxlib.luaL_loadbuffer(L, to_luastring(summary), summary.length, to_luastring('mod_test_summary'));
  if (st1 !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.log('RUNTIME ERROR [mod_test_summary]:', lua.lua_tojsstring(L, -1)); process.exit(1);
  }
  const hand = 'local n = ' + modTests.length +
    ' if (EVAL_TEST_MOD_N or -1) ~= n then error(string.format(' +
    ' "工具测试文件少跑了：磁盘 %d 个，实际跑到底 %d 个（跑到底的：%s）", n, EVAL_TEST_MOD_N or -1, ' +
    ' table.concat(EVAL_TEST_MOD_NAMES or {}, ", ")), 0) end';
  const st2 = lauxlib.luaL_loadbuffer(L, to_luastring(hand), hand.length, to_luastring('mod_test_handshake'));
  if (st2 !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.log('TOOL TEST FILES CHECK: FAIL - ' + lua.lua_tojsstring(L, -1),
      '⇒ 有整组断言**静默消失**了（文件没被加载，或文件中途 return／报错被吞）');
    process.exit(1);
  }
}
console.log('DONE');

// ===== TOOL TEST FILES CHECK（1.74.34）：工具模块自带测试的**接线** ===== 
// 用户 1.74.34：「test 相关的搬迁到对应工具类子文件内自身管理。」
// 为什么必须用源码检查：这类「文件存在但没人跑」全是**静默**失效 ——
//   ① tests/tools/*.lua 没被 harness 加载 ⇒ 整组断言消失，套件照样打印 ALL TESTS PASS；
//   ② tests/checks/*.js 没被 require ⇒ 源码检查消失，同样不报错；
//   ③ 测试文件自造一套断言（不用 EVAL_TEST_EQ）⇒ 失败格式与其它组不一致，读日志的人会误判；
//   ④ tests/ 被列进 .toc 或发布清单 ⇒ **测试代码随包发给用户**（发布包里不该有它）。
(function () {
  const bad = [];
  const tdir = path.join(__dirname, 'tests');
  const dirTools = path.join(tdir, 'tools');
  const dirChecks = path.join(tdir, 'checks');
  const list = d => fs.existsSync(d) ? fs.readdirSync(d).sort() : [];
  const te = fs.readFileSync(path.join(__dirname, 'test_engine.js'), 'utf8');
  const toc = fs.readFileSync(path.join(__dirname, 'EvalHelp.toc'), 'utf8');
  // ① 断言文件：必须用共用 eq、必须有「跑到底」握手、必须有 PASS 收尾行
  const luaFiles = list(dirTools).filter(f => /\.lua$/.test(f));
  if (!luaFiles.length) bad.push('tests/tools/ 里一个断言文件都没有（工具模块的测试都塞回 test_assert.lua 了？）');
  for (const f of luaFiles) {
    const s = fs.readFileSync(path.join(dirTools, f), 'utf8');
    if (s.indexOf('local eq = EVAL_TEST_EQ') < 0) bad.push(f + ' 没有用共用的 EVAL_TEST_EQ（自造判定 = 两套口径）');
    if (!/EVAL_TEST_MOD_DONE\("/.test(s)) bad.push(f + ' 缺 EVAL_TEST_MOD_DONE("模块名") 握手（少跑一个文件就没人发现）');
    if (!/GROUP /.test(s)) bad.push(f + ' 没有 GROUP ...: PASS 收尾行（跑没跑到底看不出来）');
  }
  // ② 源码检查文件：必须导出函数、且 harness 里必须有一行 require+调用
  const jsFiles = list(dirChecks).filter(f => /\.js$/.test(f));
  for (const f of jsFiles) {
    const s = fs.readFileSync(path.join(dirChecks, f), 'utf8');
    if (s.indexOf('module.exports = function') < 0) bad.push(f + ' 没有 module.exports = function（harness 调不动它）');
    // ★★1.74.36 实测抓到的死代码：导出函数里写 `return (function () {…})();` 之后，**再追加的检查永不执行**
    //   —— 文件里看得到、日志里从不打印（LF ROW SUMMARY CHECK 就这么被吞了一整轮）。判据：导出函数体内不许有
    //   顶层 `return`（缩进 ≤4 且形如 `return (` / `return;` / `return (`）；要早退就写进 IIFE 里。
    //   ★1.74.36 修（当场踩到自己的误报）：**导出函数体的缩进就是 2 空格**，而 IIFE 里的 `return;` 是 4 空格
    //     （LayerFix.js 的 `if (bad.length) { … return; }` 就在 IIFE 内，是**合法**早退）⇒ 只认 2 空格那档；
    //     写成 `{2,4}` 会把所有检查文件里合法的 IIFE 早退全判成死代码（真死代码反而看不出来）。
    const dead = s.split(/\r?\n/).findIndex(l => /^ {2}return\s*(\(|;|$)/.test(l) && l.trim().indexOf('//') !== 0);
    if (dead >= 0) {
      bad.push(f + " 第 " + (dead + 1) + " 行有顶层 return（它后面的检查全是**死代码**，永不执行）");
    }
    // ★必须**按行**精确匹配：注释掉那一行后，行文本里**照样**含这串子串（indexOf 会假阳性，
    //   变异 M5 当场漏网过一次）⇒ 只认「独立成行、且不是注释」的那一行。
    const need = 'require("./tests/checks/' + f + '")(__dirname)';
    const teLines = te.split(/\r?\n/).map(l => l.trim());
    if (!teLines.some(l => l.indexOf(need) === 0 && l.indexOf('//') !== 0)) {
      bad.push(f + ' 在 test_engine.js 里**没有被 require+调用** ⇒ 这条检查静默缺席');
    }
  }
  // ③ 反向哨兵：测试代码**不进包**（.toc 与发布清单里不许出现 tests/）
  if (/^tests[\\/]/m.test(toc)) bad.push('EvalHelp.toc 里出现了 tests/（测试代码会被当成插件模块载入！）');
  const refPath = path.join(__dirname, 'CLAUDE_REFERENCE.md');
  const ref = fs.existsSync(refPath) ? fs.readFileSync(refPath, 'utf8') : '';
  const packLine = ref.split(/\r?\n/).find(l => /EvalHelp\.toc/.test(l) && /Copy-Item/.test(l)) || '';
  if (/tests/.test(packLine)) bad.push('发布打包行里出现了 tests（测试代码不该随包发给用户）');
  if (bad.length) {
    console.log('TOOL TEST FILES CHECK: FAIL - ' + bad.join(' | '));
    process.exitCode = 1;
    return;
  }
  console.log('TOOL TEST FILES CHECK: ' + luaFiles.length + ' 个工具断言文件（共用 EVAL_TEST_EQ + 跑到底握手 + PASS 行）· ' +
    jsFiles.length + ' 个工具源码检查都在 harness 里被 require+调用 · tests/ 不在 .toc 与发布清单里');
})();

// ===== PCALL CALL CHECK：禁止「把方法调用写在 pcall 里面」 =====
// ★★★1.74.29 事故（用户截图红字）：`pcall(lbl.SetWidth(240))` —— 这是**先调用**再交给 pcall，
//   等效于 SetWidth(nil)，运行期报 `sol: received nil for 'self' argument`（pcall 完全没兜住，
//   因为它兜的是「这次调用」，而方法早已被无 self 调过一次）。正解 = 方法与 self 都当参数传：
//   `pcall(lbl.SetWidth, lbl, 240)`。此类写法**语法合法、luacheck 也过**，只能靠源码检查拦。
(function () {
  const SKIP = { "node_modules": 1, ".git": 1, "tmp": 1, "preview": 1, "pay": 1, ".dsh": 1 };
  function listLua(dir, out) {
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (!SKIP[e.name]) listLua(p, out); }
      else if (e.name.slice(-4) === ".lua" && e.name.indexOf("test_") !== 0) out.push(p);
    }
    return out;
  }
  const files = listLua(__dirname, []);
  const re = /pcall\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\s*\(/;
  const bad = [];
  for (const f of files) {
    const lines = fs.readFileSync(f, "utf8").split(String.fromCharCode(10));
    for (let i = 0; i < lines.length; i++) {
      const ci = lines[i].indexOf("--");
      const code = (ci >= 0 ? lines[i].slice(0, ci) : lines[i]).replace(/\r+$/, "");
      if (re.test(code)) {
        bad.push(path.relative(__dirname, f).replace(/\\/g, "/") + ":" + (i + 1) + " - " + code.trim().slice(0, 80));
      }
    }
  }
  if (bad.length) {
    for (const b of bad.slice(0, 10)) console.log("PCALL CALL CHECK: FAIL - " + b);
    if (bad.length > 10) console.log("PCALL CALL CHECK: FAIL - ... and " + (bad.length - 10) + " more");
    process.exitCode = 1;
    return;
  }
  console.log("PCALL CALL CHECK: " + files.length + " files, no method-call-inside-pcall");
})();

// （DF PICK WIRING CHECK（1.74.33）：图层**选中名单**（工具箱 [ … 已迁到 tests/checks/DragFrames.js）
// ===== TB MOD ROW CHECK（1.74.34）：工具箱「模块行」（`t = "mod"`）的通用契约 =====
// 用户要求（两次同款）：「尽量少的在 ToolBox 文件内修改.只要加入嵌入点进行函数调用」
//   ⇒ 工具箱侧只留**一行数据 + 一个通用分支**，模块自己把渲染函数登记进 `EVAL_TB_MOD_ROWS[mod]`。
// 为什么必须用源码检查：这类「名字/嵌入点对不上」全是**静默**失效 ——
//   ① 模型写 `mod = "x"`、模块登记 `["y"]` ⇒ 那一行**点不动**，且不报错；
//   ② 通用分支没真调模块函数 ⇒ 行还在、按钮没有（看着像「这功能没做」）；
//   ③ 行数据没有 `key` ⇒ 读值口（`EVAL_TB_TEST_*_FOR(key)`）找不到那一行，**断言会静默跳过**（绿得可疑）。
(function () {
  const tbPath = path.join(__dirname, "Toolbox.lua");
  if (!fs.existsSync(tbPath)) { console.log("TB MOD ROW CHECK: (无 Toolbox.lua，跳过)"); return; }
  const bad = [];
  const strip = t => t.split(/\r?\n/).map(l => { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  const tbRaw = fs.readFileSync(tbPath, "utf8");
  const tb = strip(tbRaw);
  // ① 通用嵌入点（唯一）必须在，且真的调用、且未登记时如实上报
  const iS = tbRaw.indexOf('elseif it.t == "mod" then');
  const iE = tbRaw.indexOf('elseif it.t == "rw" then');
  const seg = (iS >= 0 && iE > iS) ? strip(tbRaw.slice(iS, iE)) : "";
  if (!seg) bad.push('找不到模块行通用分支（elseif it.t == "mod" then …）');
  else {
    if (seg.indexOf("EVAL_TB_MOD_ROWS") < 0) bad.push("通用分支没从注册表 EVAL_TB_MOD_ROWS 取渲染函数");
    if (!/pcall\(fn, r, it\)/.test(seg)) bad.push("通用分支没有真的调用模块的渲染函数（pcall(fn, r, it) 缺席）");
    if (seg.indexOf("EVAL_SAY") < 0) bad.push("通用分支没有「模块没登记」时的如实上报（会静默留一行空白）");
  }
  // ② 模型里每个模块行：必须有 key；`mod` 必须在 tools/*.lua 里有**同名登记**
  const rows = [...tb.matchAll(/t = "mod",\s*mod = "([^"]+)"([^\n]*)/g)].map(m => ({ mod: m[1], rest: m[2] }));
  if (!rows.length) bad.push('模型里一个模块行都没有（t = "mod"）');
  const toolDir = path.join(__dirname, "tools");
  const srcAll = fs.readdirSync(toolDir).filter(f => /\.lua$/.test(f))
    .map(f => fs.readFileSync(path.join(toolDir, f), "utf8")).join("\n");
  const seen = new Set();
  for (const r of rows) {
    if (seen.has(r.mod)) bad.push("模块行 mod 重复：" + r.mod);
    seen.add(r.mod);
    if (!/key\s*=/.test(r.rest)) bad.push("模块行 " + r.mod + " 没有 key（读值口按 key 找行 ⇒ 断言会静默跳过）");
    if (srcAll.indexOf('["' + r.mod + '"] =') < 0) {
      bad.push("模块行 " + r.mod + " 在 tools/*.lua 里找不到同名登记（名字对不上 ⇒ 那一行点不动且不报错）");
    }
  }
  // ④ 行上不许再重复显示「配置项摘要」（用户 1.74.36：「配置项不需要再外部显示，已经在 tooltip 设置内显示了」）
  //   判据：tools/*.lua 里不许出现 `extra:SetText` —— 那一格是**工具箱自己的列表行**（t="l"，如喂食物品）在用的；
  //   模块行必须把配置项收进 [设置]/[重置] 的悬停说明（`tip.AddLine`），否则行上会出现两处同源文本、早晚打架。
  if (/extra\s*:\s*SetText/.test(srcAll)) {
    bad.push('tools/*.lua 里出现 `extra:SetText`（模块行不许把配置项写到行上 —— 配置项只在 [设置] 悬停说明里显示）');
  }
  // ③ 反向哨兵：工具箱里不许再认识任何模块内部件（「搬干净」的判据）
  for (const n of ["EVAL_DF_", "LF_FIXES", "EVAL_LF_", "EVAL_SM_"]) {
    if (tb.indexOf(n) >= 0) bad.push("Toolbox.lua 里出现了模块内部件 " + n + "（模块行只留一行数据 + 一个通用分支）");
  }
  if (bad.length) {
    console.log("TB MOD ROW CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("TB MOD ROW CHECK: 通用嵌入点（注册表取值 + 真调用 + 未登记时如实上报）· " + rows.length +
    " 个模块行都有 key 且名字在 tools/*.lua 里有同名登记 · 工具箱不认识模块内部件");
})();

// ===== 工具模块自带的源码检查（tests/checks/*.js，1.74.34）=====
// 用户 1.74.34：「test 相关的搬迁到对应工具类子文件内自身管理。」
//   ⇒ 每个工具模块的检查收在 tests/checks/<模块>.js；harness 只负责 require + 调用（一行一个）——
//     **漏一个**由 `TOOL TEST FILES CHECK` 对账抓到。★新增工具模块时：这里加一行 + tests/checks/ 建同名文件。
require("./tests/checks/LayerFix.js")(__dirname);
// （DF ICON ART CHECK（1.74.33）：窗口图标「画法 + 左键/右键分工」的 … 已迁到 tests/checks/DragFrames.js）