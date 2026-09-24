// tests/checks/LayerFix.js
// 【工具模块自带测试】图层特殊处理（tools/LayerFix.lua）的**源码检查**（原 test_engine.js 里的 `LAYER FIX WIRING CHECK`）。
// 用户 1.74.34：「test 相关的搬迁到对应工具类子文件内自身管理。」
//   ⇒ 测试三件套都归模块自己管：读值口在 tools/LayerFix.lua · 断言组在 tests/tools/LayerFix.lua · 源码检查就是本文件。
// ★纪律：
//   ① 本文件**不进 toc、不随包发布**（tests/ 不在发布清单里）；
//   ② 只导出**一个函数**（接收 repo 根目录），**不在这里自调用** —— 由 harness（test_engine.js）统一 require + 调用，
//      于是「检查有没有被跑」是**一处可数**的：漏 require 由 `TOOL TEST FILES CHECK` 当场 FAIL；
//   ③ 判定失败只设 `process.exitCode = 1`（与其它检查同一口径），不 `throw`、不 `process.exit` ——
//      好让套件把剩下的检查跑完、一次看全所有 FAIL；
//   ④ 只读文件、不改文件（变异脚本负责造变异，检查只负责抓）。
const fs = require("fs");
const path = require("path");

module.exports = function (root) {
  // ★函数体**原样搬迁**（沿用里面的 `__dirname` 写法：由形参补齐，少改动 = 少出错）
  const __dirname = root;
  // ★1.74.36：原来这里是 `return (function () {…})();` —— 在它**后面**追加的检查全是**死代码**（永不执行）。
  //   实测抓到的：新加的 LF ROW SUMMARY CHECK 一直没打印（文件里看得到、日志里从不出现）= 静默失效。
  (function () {
  const p = path.join(__dirname, "tools", "LayerFix.lua");
  if (!fs.existsSync(p)) { console.log("LAYER FIX WIRING CHECK: (无 tools/LayerFix.lua，跳过)"); return; }
  const strip = function (txt) {
    return txt.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
  };
  const raw = fs.readFileSync(p, "utf8");
  const code = strip(raw).split("\n");
  const joined = code.join("\n");
  const bad = [];
  const bodyOf = function (srcLines, name) {
    const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const re = new RegExp("^(local\\s+)?(function\\s+" + esc + "\\s*\\(|" + esc + "\\s*=\\s*function\\s*\\()");
    let start = -1;
    for (let i = 0; i < srcLines.length; i++) if (re.test(srcLines[i])) { start = i; break; }
    if (start < 0) return null;
    for (let i = start + 1; i < srcLines.length; i++) if (/^end\s*$/.test(srcLines[i])) return srcLines.slice(start, i + 1).join("\n");
    return null;
  };
  // ① 定义表（唯一来源）与执行器都在
  const mFix = joined.match(/^local LF_FIXES = \{$[\s\S]*?^\}$/m);
  if (!mFix) bad.push("找不到 LF_FIXES 定义表（特殊处理的唯一来源）");
  else {
    const tbl = mFix[0];
    const keys = (tbl.match(/key = "([^"]+)"/g) || []).map(function (s) { return s.replace(/key = "|"/g, ""); });
    if (!keys.length) bad.push("LF_FIXES 里一条处理都没有");
    for (const f of ["kind = ", "layer = ", "pick = ", "label = function", "tip = function"]) {
      const c = (tbl.split(f).length - 1);
      if (c !== keys.length) {
        bad.push("LF_FIXES 有 " + keys.length + " 条处理，但 `" + f.trim() + "` 出现 " + c + " 次 ⇒ 有条目缺这项（规范里的必填字段）");
      }
    }
    if (new Set(keys).size !== keys.length) bad.push("LF_FIXES 的 key 有重复（存档按 key 记，重名必串）");
  }
  for (const n of ["lfStore", "lfFixTbl", "lfFixOn", "lfFixOf", "lfFixWord", "lfFixLayer", "lfTexPath",
                   "lfTextures", "lfPickObjs", "lfMsg", "lfApplyOne", "lfResetOne", "lfSync", "lfTick",
                   "lfStop", "lfOnUpdate", "lfArm", "lfMigrate", "lfRow",
                   "EVAL_LF_INSTALL", "EVAL_LF_ENABLED", "EVAL_LF_SET", "EVAL_LF_COUNT", "EVAL_LF_MENU",
                   "EVAL_LF_SUMMARY", "EVAL_LF_SYNC", "EVAL_LF_RESET",
                   "EVAL_LF_TEST_FIXES_RAW", "EVAL_LF_TEST_FIX_STATE", "EVAL_LF_TEST_STATE",
                   "EVAL_LF_TEST_LIMITS", "EVAL_LF_TEST_ARM", "EVAL_LF_TEST_TICK"]) {
    if (joined.indexOf("function " + n + "(") < 0 && joined.indexOf(n + " = function(") < 0) {
      bad.push("tools/LayerFix.lua 缺 " + n);
    }
  }
  // ② 默认**一条都不选**（与「图层选择」的「表不存在 = 全选」相反）
  const onBody = bodyOf(code, "lfFixOn");
  if (!onBody) bad.push("找不到 lfFixOn");
  else {
    if (onBody.indexOf("t[key] == true") < 0) bad.push("lfFixOn 不是按 `t[key] == true` 取真值");
    if (/if type\(t\) ~= "table" then return true end/.test(onBody)) {
      bad.push("lfFixOn 在真值表不存在时返回 true —— 那是「图层选择」的全选语义；特殊处理**默认必须一条都不选**");
    }
    if (onBody.indexOf("return false") < 0) bad.push("lfFixOn 的表缺失分支没有 `return false`");
  }
  // ③ 写入口只认现有键
  const setBody = bodyOf(code, "lfSet");
  if (!setBody) bad.push("找不到 lfSet");
  else if (setBody.indexOf("lfFixOf(key)") < 0) bad.push("lfSet 不校验 key（陌生键会被写进存档，谁都不认得）");
  // ④ 菜单唯一来源 = LF_FIXES
  const menuBody = bodyOf(code, "EVAL_LF_MENU");
  if (menuBody && menuBody.indexOf("LF_FIXES[i]") < 0) {
    bad.push("EVAL_LF_MENU 不是从 LF_FIXES 现生成（以后新加的处理会漏出设置，永远选不上）");
  }
  // ⑤ 模块自包含（不许再回头引用框拖拽模块的内部件）
  for (const n of ["DF_TARGETS", "dfPicked", "dfStore", "dfTargetFrame", "dfPlaceFrom", "dfKeepTick", "dfApplyOne"]) {
    if (joined.indexOf(n) >= 0) bad.push("tools/LayerFix.lua 引用了 DragFrames 的内部件 " + n + "（独立模块不许回头耦合）");
  }
  // ⑥ 有界复查窗口：必须**到点摘脚本**，不许留常驻 tick
  const stopBody = bodyOf(code, "lfStop");
  if (!stopBody) bad.push("找不到 lfStop（有界窗口的停止口）");
  else if (!/SetScript[^\n]*"OnUpdate", nil/.test(stopBody)) {
    bad.push("lfStop 没有摘掉 OnUpdate 脚本（= 留了个常驻 tick；本项目纪律：不做没人叫停的后台周期任务）");
  }
  // ⑦ 载入期嵌入点（EvalHelp）+ toc
  const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
  // ★★★判据必须钉**可执行的那一句**，不能只找名字：变异 M9（把 `if type(...) == "function"` 改成 `if false`）
  //   名字还在、调用还在，但那条路**永远走不到** —— 只查 `indexOf("EVAL_LF_INSTALL")` 的版本当场漏过（实测）。
  const ehLine = eh.split(/\r?\n/).find(l => l.indexOf("EVAL_LF_INSTALL") >= 0) || "";
  if (!/if type\(EVAL_LF_INSTALL\) == "function" then pcall\(EVAL_LF_INSTALL\) end/.test(ehLine)) {
    bad.push("EvalHelp.lua 的 VARIABLES_LOADED 里没有**可执行**的 `if type(EVAL_LF_INSTALL) == \"function\" then pcall(EVAL_LF_INSTALL) end`" +
      "（被注释掉、或被 `if false` 之类短路 = 重进游戏不再应用存档，而名字还在 ⇒ 光查名字查不出来）");
  }
  const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
  if (!/tools[\\/]LayerFix\.lua/.test(toc)) bad.push("EvalHelp.toc 没列 tools\\LayerFix.lua（模块根本不会载入）");
  // ⑧ 工具箱侧：只有**一行数据 + 一个通用嵌入点**，不许再认识任何模块内部件
  const tbPath = path.join(__dirname, "Toolbox.lua");
  const tbRaw = fs.readFileSync(tbPath, "utf8");
  const tb = strip(tbRaw);
  for (const n of ["LF_FIXES", "EVAL_LF_", "EVAL_DF_FIX", "gryphon", "MainMenuBar"]) {
    if (tb.indexOf(n) >= 0) bad.push("Toolbox.lua 里出现了模块内部件 " + n + "（用户要求：Toolbox 只留嵌入点，不许认识模块内部）");
  }
  if (!/if not it\.noChk then r\.chk:Show\(\) end/.test(tb)) {
    bad.push("渲染段没有 `if not it.noChk then r.chk:Show() end` —— noChk 行会长出一个点了没反应的死勾选框");
  }
  const iS = tbRaw.indexOf('elseif it.t == "mod" then');
  const iE = tbRaw.indexOf('elseif it.t == "rw" then');
  const seg = (iS >= 0 && iE > iS) ? strip(tbRaw.slice(iS, iE)) : "";
  if (!seg) bad.push('找不到模块行嵌入点（elseif it.t == "mod" then …）');
  else {
    if (seg.indexOf("EVAL_TB_MOD_ROWS") < 0) bad.push("嵌入点没从注册表 EVAL_TB_MOD_ROWS 取渲染函数");
    if (!/pcall\(fn, r, it\)/.test(seg)) bad.push("嵌入点没有真的调用模块的渲染函数（pcall(fn, r, it) 缺席）");
    if (seg.indexOf("EVAL_SAY") < 0) bad.push("嵌入点没有「模块没登记」时的如实上报（会静默留一行空白）");
  }
  // ⑨ ★名字必须两边一致（对不上 ⇒ 那一行点不动，且不报错）—— 这里只钉 layerFix 自己那一对；
  //   通用契约（每个模块行都要有同名登记 + key）由 `TB MOD ROW CHECK` 统一守。
  if (joined.indexOf('LF_TB_ROWS["layerFix"] =') < 0) bad.push("模块没有把渲染函数登记进 LF_TB_ROWS（那一行会没人画）");
  if (tb.indexOf('mod = "layerFix"') < 0) {
    bad.push('工具箱模型里找不到模块行 `mod = "layerFix"`（那一行会被判成「模块未载入」）');
  }
  // ⑩ 老位置必须**一份都不剩**（两份真值 = 谁先跑谁说了算）
  const dfPath = path.join(__dirname, "tools", "DragFrames.lua");
  if (fs.existsSync(dfPath)) {
    const df = fs.readFileSync(dfPath, "utf8");
    for (const n of ["DF_FIXES", "dfFix", "EVAL_DF_FIX", "图层特殊处理"]) {
      if (df.indexOf(n) >= 0) bad.push("tools/DragFrames.lua 里还有 " + n + " 残留（搬走后必须一份不剩：两份真值会互相打架）");
    }
  }
  if (bad.length) {
    console.log("LAYER FIX WIRING CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("LAYER FIX WIRING CHECK: 独立模块 tools/LayerFix.lua（LF_FIXES 规范表 · 默认全不选 · 陌生键拒写 · " +
    "菜单现生成 · 有界复查到点摘脚本 · 与 DragFrames 零耦合 · 老位置无残留）· 载入期一句 pcall(EVAL_LF_INSTALL) · " +
    "工具箱只留「一行数据 + 一个通用嵌入点」（mod 名字两边一致，未登记时如实上报）");

  })();

  // ===== LF ROW SUMMARY CHECK（1.74.36）：配置项**只在 tooltip 里**，行上不再重复显示 =====
  // 用户原话：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」
  //   ⇒ ① 模块行不许把摘要写到行上（`extra:SetText`）—— 行上出现两处同源文本早晚打架；
  //     ② 但状态**不能丢**：它必须出现在 [设置]/[重置] 的悬停说明里（`tip.AddLine, tip, EVAL_LF_SUMMARY()`）。
  (function () {
    const p = path.join(__dirname, "tools", "LayerFix.lua");
    if (!fs.existsSync(p)) { console.log("LF ROW SUMMARY CHECK: (无 tools/LayerFix.lua，跳过)"); return; }
    const s = fs.readFileSync(p, "utf8");
    const bad = [];
    if (/extra\s*:\s*SetText/.test(s)) bad.push("LayerFix.lua 里出现 extra:SetText（配置项不许写到行上，只在 [设置]/[重置] 悬停里显示）");
    if (!/extra\s*:\s*Hide\(\)/.test(s)) bad.push("LayerFix.lua 里没有显式 r.extra:Hide()（这一行不用那一格，要写清）");
    const tipHits = (s.match(/tip\.AddLine,\s*tip,\s*EVAL_LF_SUMMARY\(\)/g) || []).length;
    if (tipHits < 2) bad.push("悬停说明里引用 EVAL_LF_SUMMARY() 只有 " + tipHits + " 处（[设置] 与 [重置] 各该有一处）");
    if (bad.length) { console.log("LF ROW SUMMARY CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("LF ROW SUMMARY CHECK: 行上不写配置（extra 只 Hide）· 状态只由悬停说明承载（[设置]/[重置] 各一处现读）");
  })();
};

// ===== LAYER FIX WIRING CHECK（1.74.34）：图层特殊处理**独立模块**（tools/LayerFix.lua）的接线 =====
// 用户要求：「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.
//   只要加入嵌入点进行函数调用?」
// 为什么用源码检查：这次改动**几乎全是接线**，而「搬出模块」这种重构最容易留下三类**静默**问题：
//   ① **两份真值**：老位置（DragFrames）没删干净 → 两边都能写、用户看到的行为取决于哪边先跑；
//   ② **名字对不上**：工具箱模型里 `mod = "layerFix"` 与模块登记的名字不一致 → 那一行点不动、**不报错**；
//   ③ **嵌入点没接**：EvalHelp 载入期没调 `EVAL_LF_INSTALL` → 重进游戏不再应用存档（用户点了勾、重开却没生效）。
// 另外三条是模块自身的硬规矩（真机上直接看得见后果）：默认**一条都不选** · 陌生键拒写 · 菜单只从 LF_FIXES 现生成。
