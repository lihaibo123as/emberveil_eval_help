// tests/checks/SimpleMap.js
// 【工具模块自带测试 · 源码检查】地图工具（tools/SimpleMap.lua）—— 「缩放大地图」那一行的 [设置] 下拉。
// 用户 1.74.35-3：「缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图
//   切换到其他地图后自动刷新到当前地图,,默认关闭.」
// ★为什么必须用源码检查（这类失效**全是静默的**）：
//   ① 真值被写成「nil 也算开」⇒ 用户没勾也生效（默认关变成默认开），只有真机才看得出来；
//   ② 判据出现第二份（`~= false` / `or true`）⇒ 下拉勾选态与开图行为**分叉**，看着都对；
//   ③ 有人把「副作用提示」删空 ⇒ 用户再也看不到「切图后会被刷新回当前地图」这句警告（用户明确要求提示）；
//   ④ 老键 `showGUI` 忘了清 ⇒ 存档里留一份没人读的配置（下次又被当成真值）；
//   ⑤ 行登记名字写错 / 工具箱里又混进模块内部件 ⇒ 那一行点不动（TB MOD ROW CHECK 守通用面，这里守本模块面）。
module.exports = function (root) {
  const fs = require("fs");
  const path = require("path");
  const __dirname = root;
  const strip = t => t.split(/\r?\n/).map(l => { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");

  // ===== SM GUIREOPEN WIRING CHECK（1.74.35-3）=====
  (function () {
    const bad = [];
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM GUIREOPEN WIRING CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const smRaw = fs.readFileSync(p, "utf8");
    const sm = strip(smRaw);
    const tbRaw = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
    const tb = strip(tbRaw);

    // ① 判据唯一且**默认关**：只认 `SM_CFG.guiReopen == true`
    const onCalls = (sm.match(/SM_CFG\.guiReopen\s*==\s*true/g) || []).length;
    if (onCalls !== 1) bad.push("「开着」的判据出现了 " + onCalls + " 处（应当恰好 1 处：`SM_CFG.guiReopen == true`）");
    for (const evil of ["SM_CFG.guiReopen ~= false", "SM_CFG.guiReopen or ", "guiReopen == nil and true"]) {
      if (sm.indexOf(evil) >= 0) bad.push("出现「nil 也算开」的写法 " + evil + " ⇒ 默认关会变成默认开");
    }
    // ② 真值写入点**可数**：只认下列 6 个合法写法（迁移里的 true/false/表值 3 + 设置入口 1 +
    //      地图设置面板 1 + 默认档 smApplyDefaults 1），
    //      外加测试读值口里 1 处清空（= nil）。★为什么不数 `SM_CFG.guiReopen =` 的次数：提示串里
    //      也有 `guiReopen=…`（本项目纪律：比对前必须先剥字符串字面量）；白名单等价达到目的，
    //      而且顺便钉住「每个写入点写的是什么值」（写布尔，绝不把表值/nil 混进去）。
    const forms = [
      /SM_CFG\.guiReopen = true/g,
      /SM_CFG\.guiReopen = false/g,
      /SM_CFG\.guiReopen = any/g,
      /SM_CFG\.guiReopen = on and true or false/g,
      /SM_CFG\.guiReopen = \(not smReopenOn\(\)\)/g,
      /SM_CFG\.guiReopen = SM_DEF_GUIREOPEN and true or false/g,
    ];
    const writes = forms.reduce(function (n, re) { return n + (sm.match(re) || []).length; }, 0);
    const clears = (sm.match(/SM_CFG\.guiReopen = nil/g) || []).length;
    if (writes !== 6) bad.push("合法写入点应为 6 个（迁移 3 + 设置入口 1 + 面板开关 1 + 默认档 1），实测 " + writes);
    if (clears !== 1) bad.push("清空（= nil）应当只有 1 处（测试读值口），实测 " + clears);
    // ③ 老键必须清掉（迁移后不留没人读的配置）
    // ★锚在**载入期迁移调用之后紧跟的那一行**（不能只找子串：测试读值口里也有一份 `SM_CFG.showGUI = nil`，
//   只找子串会让「真清理点被删」照样全绿 —— 这正是本检查第一版的假阳性，实测抓出来的）。
if (!/\nsmMigrateReopen\(\)\r?\nSM_CFG\.showGUI = nil\r?\n/.test(sm)) {
  bad.push("载入期没有在 smMigrateReopen() 之后紧跟清掉老键 SM_CFG.showGUI（存档里会留一份没人读的配置）");
}
    // ④ 开图路径：判据必须在**动作之前**（先问再动，且两处都问：开图一次 + 开图期间每 tick）
    const guards = (sm.match(/if smReopenOn\(\) then/g) || []).length;
    if (guards < 2) bad.push("开图路径上的 smReopenOn() 门只有 " + guards + " 处（应为 2：featApply 与 featKeep 各一道）");
    const callIdx = sm.indexOf("featShowGUI()");
    if (callIdx < 0) bad.push("找不到 featShowGUI 的调用（功能没接线）");
    if (sm.indexOf("if smReopenOn() then\n    local vis, blocked = featShowGUI()") < 0) {
      bad.push("featApply 里不是「先判据再动作」（关掉时必须一个动作都不发）");
    }
    // ⑤ 副作用提示必须**非空且含关键信息**（用户明确要求「提示」）
    for (const f of ["Locales/zhCN.lua", "Locales/enUS.lua", "Locales/ruRU.lua"]) {
      const loc = fs.readFileSync(path.join(__dirname, f), "utf8");
      for (const k of ["TB_SM_GUIREOPEN", "TB_SM_GUIREOPEN_TIP1", "TB_SM_GUIREOPEN_TIP2", "TB_SM_GUIREOPEN_TIP3"]) {
        if (!new RegExp("^\\s*" + k + "\\s*=", "m").test(loc)) bad.push(f + " 缺键 " + k);
      }
    }
    const zh = fs.readFileSync(path.join(__dirname, "Locales", "zhCN.lua"), "utf8");
    const tip2 = (zh.match(/^\s*TB_SM_GUIREOPEN_TIP2\s*=\s*"(.*)",\s*$/m) || [])[1] || "";
    if (tip2.indexOf("自动刷新") < 0) bad.push("中文副作用提示里没有「自动刷新」这句（用户要的就是这个提示）");
    if (tip2.indexOf("当前所在地图") < 0) bad.push("中文副作用提示里没有说清「会回到当前所在地图」");
    // ⑥ 行登记 + 本模块反向哨兵
    if (sm.indexOf('["simpleMap"] = smRow') < 0) bad.push("模块没有登记 EVAL_TB_MOD_ROWS[\"simpleMap\"]");
    if (sm.indexOf("function EVAL_SM_TB_REGISTER") < 0) bad.push("模块没有提供 EVAL_SM_TB_REGISTER（函数口登记）");
    if (tb.indexOf("EVAL_SM_") >= 0) bad.push("Toolbox.lua 代码里又出现了模块内部件 EVAL_SM_（模块行只留一行数据）");
    if (!/t = "mod",\s*mod = "simpleMap",\s*key = "simpleMap"/.test(tb)) bad.push('Toolbox 里「缩放大地图」不是模块行（应为 t = "mod", mod = "simpleMap", key = "simpleMap"）');
    // ⑦ 读值口齐全（测试靠它们，缺一个 = 断言静默跳过）
    for (const f of ["EVAL_SM_TEST_GUIREOPEN", "EVAL_SM_TEST_GUI_CALLS", "EVAL_SM_TEST_GUI_CALLS_RESET",
                     "EVAL_SM_TEST_MENU_RAW", "EVAL_SM_TEST_ROW", "EVAL_SM_TEST_MIGRATE", "EVAL_SM_SUMMARY"]) {
      if (sm.indexOf("function " + f) < 0) bad.push("缺读值口 " + f);
    }
    if (bad.length) { console.log("SM GUIREOPEN WIRING CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM GUIREOPEN WIRING CHECK: 真值唯一且**默认关**（只认 guiReopen == true，无 nil 当开）· 老键 showGUI 已清 · " +
      "开图两道门（先判据后动作，关掉零动作）· 三语言提示齐全且中文含「自动刷新…当前所在地图」· 行是模块行且工具箱无模块内部件");
  })();

  // ===== SM DEFAULT TIER CHECK（1.74.36-3）= 「开启即套默认档 0.7 / 0.7 / GUI 不启用」 =====
  // 用户原话：「工具箱 →『缩放大地图』 开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」
  // ★为什么必须用源码检查（这几条失效全是静默的）：
  //   ① 默认值被散写成字面量（0.7 又写一遍 / 写成 0.75）⇒ 面板、摘要、默认档各说各的，看着都对；
  //   ② 开启路径忘了调 smApplyDefaults（或调了却不应用）⇒ 开关勾上但地图还是 1/1 全尺寸不透明；
  //   ③ GUI重开 在默认档里被写成「开」（或写成 `or true`）⇒ 用户明确要的「不启用GUI」反了；
  //   ④ 默认档把「叠加层适配」（另一项默认开的功能）一起关掉 ⇒ 顺手破坏别的功能；
  //   ⑤ 面板值标签不刷 ⇒ 界面显示上一轮旧数字（真机上就是「默认值没生效」的观感）。
  (function () {
    const bad = [];
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM DEFAULT TIER CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const sm = strip(fs.readFileSync(p, "utf8"));
    // ① 默认档常量 = 用户定稿（数字本身就是需求），且**只有这一处**定义
    const def = /local SM_DEF_ALPHA, SM_DEF_SCALE, SM_DEF_GUIREOPEN = ([0-9.]+), ([0-9.]+), (true|false)/.exec(sm);
    if (!def) bad.push("找不到默认档常量行（SM_DEF_ALPHA / SM_DEF_SCALE / SM_DEF_GUIREOPEN）");
    else {
      if (parseFloat(def[1]) !== 0.7) bad.push("默认透明度不是 0.7（实测 " + def[1] + "）");
      if (parseFloat(def[2]) !== 0.7) bad.push("默认缩放不是 0.7（实测 " + def[2] + "）");
      if (def[3] !== "false") bad.push("默认档里 GUI重开 不是 false（用户明确「不启用GUI」，实测 " + def[3] + "）");
    }
    const defs = (sm.match(/local SM_DEF_ALPHA/g) || []).length;
    if (defs !== 1) bad.push("默认档常量被定义了 " + defs + " 次（应恰好 1 次 = 单一来源）");
    // ② 载入期默认值也走同一常量（不许再写 0.7 字面量）
    if (!/SM_CFG\.alpha = tonumber\(SM_CFG\.alpha\) or SM_DEF_ALPHA/.test(sm)) bad.push("载入期透明度默认值没走 SM_DEF_ALPHA（第二份字面量）");
    if (!/SM_CFG\.scale = tonumber\(SM_CFG\.scale\) or SM_DEF_SCALE/.test(sm)) bad.push("载入期缩放默认值没走 SM_DEF_SCALE（第二份字面量）");
    // ③ 默认档执行口：写真值 + 立刻应用 + 刷面板（三步都不许少）
    if (sm.indexOf("local function smApplyDefaults()") < 0) bad.push("缺默认档执行口 smApplyDefaults");
    if (sm.indexOf("featApplyAlpha(SM_DEF_ALPHA)") < 0 || sm.indexOf("featApplyScale(SM_DEF_SCALE)") < 0) {
      bad.push("默认档只写配置没**应用**（勾上开关地图还是 1/1 全尺寸不透明）");
    }
    if (!/if type\(smPanelSync\) == "function" then pcall\(smPanelSync\) end/.test(sm)) {
      bad.push("默认档没有刷新地图设置面板（面板会一直显示上一轮的旧数字）");
    }
    // ④ 开启路径必须先套默认档（锚在 EVAL_SM_SET 的 on 分支第一行）
    if (!/if on then\r?\n\s*--[^\n]*\r?\n\s*--[^\n]*\r?\n\s*local a, s = smApplyDefaults\(\)/.test(sm)
        && sm.indexOf("local a, s = smApplyDefaults()") < 0) {
      bad.push("EVAL_SM_SET 的开启分支没有调 smApplyDefaults（「开启即套默认档」没接线）");
    }
    if (!/smApplyDefaults\(\)\r?\n\s*pcall\(featKeep\)/.test(sm)) {
      bad.push("开启分支不是「先套默认档 → 再 featKeep/featApply」（顺序反了会把默认值又覆盖回去）");
    }
    // ⑤ 反向哨兵：默认档**不许碰**叠加层适配（那是另一项默认开的功能）
    //   ★绝不能拿**注释标记**做切片边界：strip() 会把纯注释行清成空行 ⇒ 标记永远找不到 ⇒
    //     切片变成「到文件末尾」，正好把末尾的 EVAL_SM_TEST_MAPFIT_* 读值口切进来 = 自己制造假阳性
    //     （本检查第一版就是这样红的）。⇒ 按**函数体**取，边界写死在语法结构上。
    const bodyM = /local function smApplyDefaults\(\)([\s\S]*?)\nend\n/.exec(sm);
    if (!bodyM) bad.push("取不到 smApplyDefaults 的函数体（mapFit 反向哨兵无从下手）");
    else if (bodyM[1].indexOf("mapFit") >= 0) {
      bad.push("默认档里出现了 mapFit（会把「叠加层适配」顺手关掉 = 破坏另一项功能）");
    }
    // ⑥ 读值口齐全（测试靠它们；缺一个 = 断言静默跳过）
    for (const f of ["EVAL_SM_TEST_DEFAULTS", "EVAL_SM_TEST_PANEL", "EVAL_SM_DEF_TIP", "EVAL_SM_TEST_APPLY"]) {
      if (sm.indexOf("function " + f) < 0) bad.push("缺读值口 " + f);
    }
    if (bad.length) { console.log("SM DEFAULT TIER CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM DEFAULT TIER CHECK: 默认档唯一来源 0.7/0.7/GUI不启用 · 载入期也走同一常量 · " +
      "开启分支「先套默认档→再应用」· 面板标签跟着刷 · 不碰叠加层适配（反向哨兵）");
  })();

  // ===== SM MAPFIT WIRING CHECK（1.74.35-4）：叠加层「跟随地图缩放」适配**属本模块 + 默认开** =====
  // 用户 1.74.35-4：「开图/es 变化后 0.1s 高频爆发期（持续 2 秒）＋之后降到 0.3 稳态巡检」是
  //   **工具箱→大地图缩放**要默认启动的功能，**不是给图层调试工具内使用的**（「调试工具只是个调试工具，不需要」）。
  // ★为什么必须用源码检查（这几条失效全是静默的）：
  //   ① 「默认开」被写成 `mapFit == true` ⇒ **nil 变成关** = 用户没动过却默认不生效（与「默认启动」正好相反）；
  //   ② 节奏常量被改/被抄成第二份（0.5 / 1.0 之类）⇒ 用户定稿的「0.1 爆发 2 秒 → 0.3 稳态」再也不成立；
  //   ③ 过渡检测不再把节拍顶满 ⇒ 开图后要等一个（甚至两个）周期才动手，观感就是「不跟手」；
  //   ④ 瓦片前缀判据写反/被删 ⇒ 连 12 张底瓦片一起折算 = 底图整体错位（它们本来就对）；
  //   ⑤ **功能回流到调试工具**（子插件里又出现 ticker/自动适配）⇒ 两个插件抢着写同一批几何。
  (function () {
    const bad = [];
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM MAPFIT WIRING CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const sm = strip(fs.readFileSync(p, "utf8"));
    // ① 默认开：只认 `SM_CFG.mapFit ~= false`（恰好 1 处）；禁止「nil 也算关」的写法
    const onForm = (sm.match(/SM_CFG\.mapFit ~= false/g) || []).length;
    if (onForm !== 1) bad.push("「默认开」的判据出现 " + onForm + " 处（应恰好 1 处：`SM_CFG.mapFit ~= false`）");
    for (const evil of ["SM_CFG.mapFit == true", "SM_CFG.mapFit == nil", "SM_CFG.mapFit or false",
                        "not SM_CFG.mapFit", "SM_CFG.mapFit and true"]) {
      if (sm.indexOf(evil) >= 0) bad.push("出现「把 nil 当关」的写法 " + evil + " ⇒ 默认开会变成默认关");
    }
    // ② 节奏常量唯一且 = 用户定稿（数字本身就是需求）
    const cad = /local SMFIT_BURST_GAP, SMFIT_BURST_SEC, SMFIT_IDLE_GAP = ([0-9.]+), ([0-9.]+), ([0-9.]+)/.exec(sm);
    if (!cad) bad.push("找不到节奏常量行（SMFIT_BURST_GAP/SEC/IDLE_GAP）");
    else if (!(parseFloat(cad[1]) === 0.1 && parseFloat(cad[2]) === 2.0 && parseFloat(cad[3]) === 0.3)) {
      bad.push("节奏常量不是用户定稿的 0.1 / 2.0 / 0.3（实测 " + cad[1] + " / " + cad[2] + " / " + cad[3] + "）");
    }
    // ③ 过渡（开图 / es 变化）必须**把节拍顶满**；tick 里按 burst 在 0.1 与 0.3 之间取 gap
    const bursts = (sm.match(/SMFIT\.burst = SMFIT_BURST_SEC/g) || []).length;
    if (bursts < 2) bad.push("tick 里「进爆发期」只有 " + bursts + " 处（应 ≥2：开图 + es 变化各一处）");
    if (sm.indexOf("accFit = 1e9") < 0) bad.push("过渡时没有把节拍**顶满**（缺 accFit = 1e9 ⇒ 开图后要等一个周期才动手）");
    if (sm.indexOf("(SMFIT.burst") >= 0 && sm.indexOf("SMFIT_BURST_GAP or SMFIT_IDLE_GAP") < 0) {
      bad.push("tick 里没有「burst 期用 0.1s / 稳态用 0.3s」的取 gap 逻辑");
    }
    if (sm.indexOf("SMFIT_BURST_GAP or SMFIT_IDLE_GAP") < 0) bad.push("缺「按 burst 取 gap」那一行（节奏会退化成单一节拍）");
    // ④ 底瓦片必须**跳过**（跳过判据只能是「名字以 WorldMapDetailTile 开头」）
    if (sm.indexOf('string.sub(nm, 1, 18) == "WorldMapDetailTile"') < 0) {
      bad.push("缺「底瓦片前缀」判据（WorldMapDetailTile）⇒ 会把 12 张底瓦片一起折算");
    }
    if (!/not \(type\(nm\) == "string" and string\.sub\(nm, 1, 18\) == "WorldMapDetailTile"\)/.test(sm)) {
      bad.push("底瓦片判据不是「不是瓦片才处理」的写法（反了就整片错位）");
    }
    // ⑤ 方向 ×es（真机定案）：偏移与宽高都乘 es，别写成除法
    if (!/local wantX, wantY = r\.x \* es, r\.y \* es/.test(sm) || !/local wantW, wantH = r\.w \* es, r\.h \* es/.test(sm)) {
      bad.push("折算口径不是「偏移与宽高 ×es」（真机定案：×es 有效、÷es 无效）");
    }
    // ⑥ 开关是唯一闸门：先判据再动作
    if (sm.indexOf("if not smFitOn() then return end") < 0) bad.push("tick 里缺 `if not smFitOn() then return end`（关掉时必须一个动作都不发）");
    // ⑦ 读值口齐全（测试靠它们；缺一个 = 断言静默跳过）
    for (const f of ["EVAL_SM_MAPFIT_ON", "EVAL_SM_MAPFIT_SET", "EVAL_SM_MAPFIT_TIP",
                     "EVAL_SM_TEST_MAPFIT", "EVAL_SM_TEST_MAPFIT_GAPS", "EVAL_SM_TEST_MAPFIT_TARGETS",
                     "EVAL_SM_TEST_MAPFIT_APPLY", "EVAL_SM_TEST_MAPFIT_ORIG", "EVAL_SM_TEST_MAPFIT_RESET"]) {
      if (sm.indexOf("function " + f) < 0) bad.push("缺读值口 " + f);
    }
    // ⑧ ★反向哨兵：**调试工具不许再把自动适配做回去**（用户：「图层调试工具只是个调试工具，不需要」）
    const dbx = path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua");
    if (fs.existsSync(dbx)) {
      const d = strip(fs.readFileSync(dbx, "utf8"));
      for (const evil of ["mapFitTickEnsure", "mapFitApply", "EH_DB_MAPFIT", "ui.mapFit"]) {
        if (d.indexOf(evil) >= 0) bad.push("子插件里又出现了自动适配件 " + evil + " ⇒ 功能回流到调试工具了");
      }
      // ★注意：`\s*[^n]` 会被「空格」骗过（`= nil` 里的空格也算 [^n]）⇒ 这里直接取等号右边整段来比
      const dbxWrites = [...d.matchAll(/EH_DEBUGBOX_CFG\.mapFit[A-Za-z]*\s*=\s*([^\n]*)/g)]
        .map(m => m[1].trim().replace(/;.*$/, ""));
      if (!dbxWrites.length) bad.push("子插件里连一次性清键都没有（老存档会留一份没人读的 mapFit）");
      dbxWrites.forEach(v => {
        if (v !== "nil") bad.push("子插件又把 mapFit 当真值写了（= " + v + "）；应当只剩一次性清键 = nil");
      });
    }
    if (bad.length) { console.log("SM MAPFIT WIRING CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM MAPFIT WIRING CHECK: 属**缩放大地图**且默认开（只认 mapFit ~= false，nil⇒开）· 节奏 0.1/2.0/0.3 唯一来源 · " +
      "过渡顶满节拍 · 底瓦片跳过 · 方向 ×es · 关掉零动作 · 调试工具里已无自动适配（反向哨兵）");
  })();

  // ===== SM GROUP ROSTER CHECK：本模块测试文件的**组号清单**不许静默少一个（与 DF 那套同族）=====
  (function () {
    const WANT = [224, 225, 226];
    const p = path.join(__dirname, "tests", "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM GROUP ROSTER CHECK: FAIL - 找不到 tests/tools/SimpleMap.lua"); process.exitCode = 1; return; }
    const s = fs.readFileSync(p, "utf8");
    const bad = [];
    const pos = [];
    for (const m of s.matchAll(/-- ===== 组 (\d+)/g)) pos.push({ n: +m[1], i: m.index });
    const got = pos.map(x => x.n);
    if (got.length !== WANT.length) bad.push("组数 " + got.length + " ≠ 期望 " + WANT.length);
    const missing = WANT.filter(n => got.indexOf(n) < 0), extra = got.filter(n => WANT.indexOf(n) < 0);
    if (missing.length) bad.push("少了组 " + missing.join(","));
    if (extra.length) bad.push("多了组 " + extra.join(","));
    if (got.join(",") !== got.slice().sort((a, b) => a - b).join(",")) bad.push("组号没按升序排");
    pos.forEach((x, k) => {
      const seg = s.slice(x.i, k + 1 < pos.length ? pos[k + 1].i : s.length);
      if (seg.indexOf("eq(") < 0) bad.push("组 " + x.n + " 区间里一条 eq( 都没有（整组被掏空？）");
      if (seg.indexOf('print("GROUP ' + x.n) < 0) bad.push("组 " + x.n + " 缺 print(\"GROUP " + x.n + " …: PASS\") 收尾行");
    });
    if (bad.length) { console.log("SM GROUP ROSTER CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM GROUP ROSTER CHECK: " + got.length + " 个组号与期望完全一致且升序 · 每组都有真实断言与 PASS 收尾行（" + got.join("/") + "）");
  })();

  // ===== SM ROW SUMMARY CHECK（1.74.36）：配置项**只在 tooltip 里** =====
  // 用户原话：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」
  (function () {
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM ROW SUMMARY CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const s = fs.readFileSync(p, "utf8");
    const bad = [];
    if (/extra\s*:\s*SetText/.test(s)) bad.push("SimpleMap.lua 里出现 extra:SetText（配置项不许写到行上）");
    if (!/extra\s*:\s*Hide\(\)/.test(s)) bad.push("SimpleMap.lua 里没有显式 r.extra:Hide()");
    if (!/tip\.AddLine,\s*tip,\s*EVAL_SM_SUMMARY\(\)/.test(s)) bad.push("悬停说明里没有 EVAL_SM_SUMMARY()（行上不显示了，tooltip 里必须有）");
    const tips = (s.match(/tip\.AddLine,\s*tip,\s*L\("TB_SM_GUIREOPEN_TIP/g) || []).length;
    if (tips < 1) bad.push("悬停说明里没有「GUI重开」的副作用提示（提示不许只在菜单里）");
    if (bad.length) { console.log("SM ROW SUMMARY CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM ROW SUMMARY CHECK: 行上不写配置（extra 只 Hide）· 悬停里带当前配置 + GUI重开副作用提示");
  })();
};
