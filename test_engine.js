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
(function () {
  const files = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/DismountHelper.lua", "tools/RareWatch.lua"];
  const bad = [];
  let totalLocals = 0;
  const isName = (s) => new RegExp("^[A-Za-z_][A-Za-z0-9_]*$").test(s);
  for (const f of files) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) continue;
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
    for (const nm of Object.keys(decls)) {
      if (inner.has(nm)) continue; // 名字在文件内有多个绑定 → 无法按名字判定，跳过
      const d = decls[nm];
      const re = new RegExp("(^|[^A-Za-z0-9_])" + nm + "([^A-Za-z0-9_]|$)");
      for (let i = 0; i < d - 1; i++) {
        if (re.test(strip(lines[i]))) { bad.push(f + ": " + nm + " used at " + (i + 1) + " but declared at " + d); break; }
      }
    }
  }
  if (bad.length) {
    for (const b of bad.slice(0, 12)) console.log("DECL ORDER CHECK: FAIL - " + b);
    if (bad.length > 12) console.log("DECL ORDER CHECK: FAIL - ... and " + (bad.length - 12) + " more");
    process.exitCode = 1;
    return;
  }
  console.log("DECL ORDER CHECK: " + totalLocals + " top-level locals declare before use (" + files.length + " files)");
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
  for (const f of ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua"]) {
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
  const files = ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua",
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
                     "tools/ConsumableHelper.lua", "tools/HunterHelper.lua", "tools/DismountHelper.lua", "tools/IconGrid.lua", "tools/RareWatch.lua"];
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
  const prodFiles = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua"];
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
  const files = ["EvalHelp.lua", "Toolbox.lua", "DataSearch.lua", "IconBrowser.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua"];
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
  const files = ["EvalHelp.lua", "Toolbox.lua", "Engine.lua", "Core.lua", "Share.lua", "DataSearch.lua", "IconBrowser.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua"];
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
  if (bad.length) {
    console.log("HH WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("HH WIRING CHECK: tools 模块进了 .toc · 工具箱有开关行且勾选接 EVAL_HH_TOGGLE/EVAL_DH_TOGGLE · /eh go 喂食*/下马* 已接 · 两个助手都接了登录恢复");
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
  const files = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconSem.lua", "IconBrowser.lua", "PetData.lua", "PetHelper.lua", "tools/IconGrid.lua", "tools/HunterHelper.lua", "tools/ConsumableHelper.lua", "tools/RareWatch.lua"];
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
for(const f of ['test_stub.lua','Locales/zhCN.lua','Locales/enUS.lua','Locales/ruRU.lua','Core.lua','Engine.lua','EvalHelp.lua','examples/warrior.lua','examples/mage.lua','examples/caster.lua','examples/general.lua','examples/rogue.lua','examples/hunter.lua','examples/paladin.lua','examples/priest.lua','examples/druid.lua','examples/warlock.lua','examples/shaman.lua','examples/group.lua','Toolbox.lua','DataSearch.lua','Share.lua','IconSem.lua','IconBrowser.lua','PetData.lua','PetHelper.lua','tools/IconGrid.lua','tools/HunterHelper.lua','tools/ConsumableHelper.lua','tools/DismountHelper.lua','tools/RareWatch.lua','test_assert.lua']){
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
console.log('DONE');
