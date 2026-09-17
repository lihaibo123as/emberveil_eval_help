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
  const files = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconBrowser.lua"];
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
  for (const f of ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconBrowser.lua"]) {
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
  for (const f of ["DataSearch.lua", "Toolbox.lua"]) {
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
  console.log("LANG SOURCE CHECK: DataSearch/Toolbox read the language via EVAL_GET_LANG()");
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
  const files = ["EvalHelp.lua", "DataSearch.lua", "Toolbox.lua", "Core.lua", "Engine.lua", "Share.lua", "IconBrowser.lua",
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
  const expect = ["战士", "法师", "通用法系", "盗贼", "猎人", "骑士", "牧师", "德鲁伊", "术士", "萨满", "队伍/团队"];
  const got = listed.map(f => { const m = fs.readFileSync(path.join(dir, f), "utf8").match(/cls\s*=\s*"([^"]+)"/); return m ? m[1] : "?"; });
  if (got.join(",") !== expect.join(",")) {
    console.log("EXAMPLES TOC CHECK: FAIL - toc order gives [" + got.join("/") + "], expected [" + expect.join("/") + "]");
    process.exit(1);
  }
  // ① 模版数据只能住在 examples/：别的生产文件里再出现 cls = " 就是「又搬回去了 / 多了一份」
  //   （同一个东西两份真值，正是本项目反复踩的坑：改一处漏一处、后写的静默获胜）。
  const prodFiles = ["EvalHelp.lua", "Core.lua", "Engine.lua", "Toolbox.lua", "DataSearch.lua", "Share.lua", "IconBrowser.lua"];
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
  if (sites.length < 7) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - expected >=7 wiring sites, found " + sites.length + " (" + sites.join(", ") + ")");
    process.exitCode = 1;
    return;
  }
  if (bad.length) {
    console.log("STOP ATTACK WIRING CHECK: FAIL - special-behaviour wiring missing next to cancelCastOf at: " + bad.join(", "));
    process.exitCode = 1;
    return;
  }
  console.log("STOP ATTACK WIRING CHECK: stopAllOf + followOf wired alongside cancelCastOf at all " + sites.length + " sites");
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

// ===== MILESTONE CHECK（1.72.0）：里程碑是「归纳」不是「罗列」，每个小节 <=10 条 =====
// ★背景（用户 1.72.0 明确）：「里程碑是要你总结上个里程碑到最新版本的信息归纳，而不是把版本信息全部罗列，
//   不然内容太多了 —— 每次里程碑归纳内容最终控制在 10 条以内。」
//   → 这条规则光写进记忆体（CLAUDE.md）挡不住：记忆体是给人/AI 读的提醒，不是闸门。
//     本项目铁律：**审计/排查必须落成可执行闸门**，所以这里钉死三件事。
// 判据：① 3 个 README 都有「里程碑」板块（## 🏁 …）
//       ② 板块标题的版本范围末端 == 当前 VERSION，且**最新那个小节**的范围末端也 == 当前 VERSION
//          （守着「发版只更新了 CHANGELOG、忘了改里程碑范围」）
//       ③ 每个小节（### / ####）的条目数 1..10（守着「又写成版本流水账」）
// ★条目判据 = 行首为 ** 的段落（三个语种写法一致：**emoji 主题**（版本范围）：…）。
(function () {
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  const vm = toc.match(/##\s*Version:\s*([0-9.]+)/);
  if (!vm) { console.log("MILESTONE CHECK: skipped (no ## Version in toc)"); return; }
  const ver = vm[1];
  const bad = [];
  for (const f of ["README.md", "README_en.md", "README_ru.md"]) {
    const p = path.join(__dirname, f);
    if (!fs.existsSync(p)) { bad.push(f + " missing"); continue; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const h = lines.findIndex((l) => /^##\s*🏁/.test(l));
    if (h < 0) { bad.push(f + " has no milestone section"); continue; }
    let e = lines.length;
    for (let i = h + 1; i < lines.length; i++) { if (/^##\s/.test(lines[i])) { e = i; break; } }
    const headVer = (lines[h].match(/[0-9]+\.[0-9]+\.[0-9]+/g) || []);
    if (!headVer.length || headVer[headVer.length - 1] !== ver) {
      bad.push(f + " milestone heading range does not end at " + ver);
    }
    let cur = null, n = 0, first = null;
    const flush = () => { if (cur !== null && (n < 1 || n > 10)) bad.push(f + " '" + cur + "' has " + n + " entries (need 1..10)"); };
    for (let i = h + 1; i < e; i++) {
      const m = lines[i].match(/^#{3,4}\s+(.*)$/);
      if (m) { flush(); cur = m[1].trim(); n = 0; if (first === null) first = cur; continue; }
      if (/^\*\*/.test(lines[i])) n++;
    }
    flush();
    if (first !== null) {
      const fv = first.match(/[0-9]+\.[0-9]+\.[0-9]+/g) || [];
      if (!fv.length || fv[fv.length - 1] !== ver) bad.push(f + " newest milestone subsection does not end at " + ver);
    }
  }
  if (bad.length) { console.log("MILESTONE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
  console.log("MILESTONE CHECK: 3 READMEs, range ends at " + ver + ", every subsection has 1..10 entries");
})();

checkIconAssets();

const L=lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for(const f of ['test_stub.lua','Locales/zhCN.lua','Locales/enUS.lua','Locales/ruRU.lua','Core.lua','Engine.lua','EvalHelp.lua','examples/warrior.lua','examples/mage.lua','examples/caster.lua','examples/rogue.lua','examples/hunter.lua','examples/paladin.lua','examples/priest.lua','examples/druid.lua','examples/warlock.lua','examples/shaman.lua','examples/group.lua','Toolbox.lua','DataSearch.lua','Share.lua','IconBrowser.lua','test_assert.lua']){
  const src=fs.readFileSync(f);
  const st=lauxlib.luaL_loadbuffer(L,src,src.length,to_luastring(f));
  if(st!==lua.LUA_OK){ console.log('LOAD ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
  if(lua.lua_pcall(L,0,0,0)!==lua.LUA_OK){ console.log('RUNTIME ERROR ['+f+']:',lua.lua_tojsstring(L,-1)); process.exit(1); }
}
console.log('DONE');
