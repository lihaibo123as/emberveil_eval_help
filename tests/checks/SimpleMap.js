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
                     "EVAL_SM_TEST_MAPFIT_APPLY", "EVAL_SM_TEST_MAPFIT_ORIG", "EVAL_SM_TEST_MAPFIT_RESET",
                     "EVAL_SM_TEST_MAPFIT_MAPKEY", "EVAL_SM_TEST_MAPFIT_INUSE", "EVAL_SM_TEST_MAPFIT_WROTE",
                     "EVAL_SM_TEST_MAPFIT_DUMP", "EVAL_SM_TEST_MAPFIT_BUCKET",
                     "EVAL_SM_TEST_MAPFIT_CAPSTATE", "EVAL_SM_TEST_MAPFIT_SOFT_RESET"]) {
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

  // ===== SM POS CENTER CHECK（1.75.10）：世界地图的**初始位置**口径 = 每次载入的第一次开图一律居中 =====
  // 用户报障原话：「世界地图缩放开启之后,每次插件重载的初始位置能否居中.现在他有时候会乱跳到左下角位置」
  // ★为什么必须源码级钉（这一案全是静默的）：
  //   ① 存档里的 `px/py` 是**跨会话继承**的屏幕中心偏移 —— 本客户端几何读回含缩放（见 smEffScale 注释），
  //      折算口径一旦对不上，这个值会被永久沿用 ⇒ 每次开图都按它摆位置（还会累积），表现就是「乱跳」；
  //      而代码里看着完全正常（一个 nil 判断 + 一次 SetPoint），行为断言也照不到「上次会话留下的脏值」。
  //   ② 居中**只做一次是不够的**：客户端自己的开图流程可能在我们 apply **之后**才摆位置（与黑幕那条竞态同族）
  //      ⇒ 必须有**有界**的窗口期重申；但窗口期又必须能被用户拖拽打断（否则就是跟用户抢位置）。
  //   ③ 这一位（`FEAT.posArmed`）必须在**载入期就是 true** —— 它等于「本次会话还没居中过」，写反了就没居中。
  (function () {
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM POS CENTER CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const sm = strip(fs.readFileSync(p, "utf8"));
    const bad = [];
    // ① 载入期的两位（本次会话还没居中过 / 窗口拍数）
    const featM = /local FEAT = \{[\s\S]*?\}/.exec(sm);
    if (!featM) bad.push("找不到 FEAT 初始化表（位置口径的两位状态就在那里）");
    else {
      if (!/posArmed = true/.test(featM[0])) bad.push("FEAT 初始化里没有 `posArmed = true` ⇒ /reload 后第一次开图不会居中（判据反了）");
      if (!/recenter = 0/.test(featM[0])) bad.push("FEAT 初始化里没有 `recenter = 0`（窗口期起点）");
    }
    if (!/local SM_RECENTER_TICKS = \d+/.test(sm)) bad.push("没有居中窗口期常量 SM_RECENTER_TICKS（窗口期必须**有界**，不许常驻重申）");
    // ② featCenterNow = 纯动作：清锚点 + 摆正中；且「已居中就不写」（读不到锚点才退回盲写）
    const iNow = sm.indexOf("local function featCenterNow(");
    const nowEnd = iNow >= 0 ? sm.indexOf("\nlocal function ", iNow + 10) : -1;
    const nowSeg = (iNow >= 0 && nowEnd > iNow) ? sm.slice(iNow, nowEnd) : "";
    if (!nowSeg) bad.push("没有 featCenterNow（把地图摆回正中的纯动作口）");
    else {
      if (nowSeg.indexOf("ClearAllPoints") < 0 || nowSeg.indexOf('SetPoint, wm, "CENTER", UIParent, "CENTER", 0, 0') < 0) {
        bad.push("featCenterNow 没有真的把地图摆到 CENTER/UIParent/CENTER 0,0");
      }
      if (nowSeg.indexOf("GetPoint") < 0) bad.push("featCenterNow 没有读回自证（已居中就不写）⇒ 窗口期内每拍盲写一次锚点");
    }
    // ③ featCenterOnce = 清存档偏移 + 居中 + 关闩 + 开窗口
    const iOnce = sm.indexOf("local function featCenterOnce(");
    const onceEnd = iOnce >= 0 ? sm.indexOf("\nlocal function ", iOnce + 10) : -1;
    const onceSeg = (iOnce >= 0 && onceEnd > iOnce) ? sm.slice(iOnce, onceEnd) : "";
    if (!onceSeg) bad.push("没有 featCenterOnce（本次会话第一次开图的口）");
    else {
      if (onceSeg.indexOf("SM_CFG.px, SM_CFG.py = nil, nil") < 0) bad.push("featCenterOnce 没有清掉存档里的历史偏移 ⇒ 下次开图又被那个会漂的值摆走（用户报的「乱跳」根因）");
      if (onceSeg.indexOf("featCenterNow(wm)") < 0) bad.push("featCenterOnce 没有调 featCenterNow");
      if (onceSeg.indexOf("FEAT.posArmed = false") < 0) bad.push("featCenterOnce 没有关掉「本次会话还没居中过」这一位（会每拍都重清）");
      if (!/FEAT\.recenter = SM_RECENTER_TICKS/.test(onceSeg)) bad.push("featCenterOnce 没有开居中窗口期（客户端在我们之后摆位置时又白做一次）");
    }
    // ④ featApply 里的**顺序**：先判「本次会话第一次」⇒ 居中；否则才走位置记忆（顺序即判据）
    const iAp = sm.indexOf("local function featApply()");
    const apEnd = iAp >= 0 ? sm.indexOf("\nend", iAp) : -1;
    const apSeg = (iAp >= 0 && apEnd > iAp) ? sm.slice(iAp, apEnd) : "";
    if (!apSeg) bad.push("找不到 featApply");
    else {
      const iArm = apSeg.indexOf("if FEAT.posArmed then");
      const iMem = apSeg.indexOf("SM_CFG.px, SM_CFG.py");
      if (iArm < 0) bad.push("featApply 里没有 `if FEAT.posArmed then`（第一次开图居中这条判据没接线）");
      if (iArm >= 0 && apSeg.indexOf("featCenterOnce") < 0) bad.push("featApply 的 posArmed 分支没调 featCenterOnce");
      if (iArm < 0 || iMem < 0 || iArm > iMem) bad.push("featApply 里「首次居中」不是排在**位置记忆之前**（顺序反了 ⇒ 脏偏移先摆上去、再被居中覆盖，看着像居中但白做一次）");
    }
    // ⑤ featKeep 的窗口块：逐拍重申居中（有界）
    const iKeep = sm.indexOf("local function featKeep()");
    const keepEnd = iKeep >= 0 ? sm.indexOf("\nend", iKeep) : -1;
    const keepSeg = (iKeep >= 0 && keepEnd > iKeep) ? sm.slice(iKeep, keepEnd) : "";
    if (!keepSeg) bad.push("找不到 featKeep");
    else {
      if (keepSeg.indexOf("FEAT.recenter") < 0) bad.push("featKeep 里没有居中窗口期的重申（客户端在我们之后摆位置时就会「有时候没居上」）");
      if (keepSeg.indexOf("featCenterNow") < 0) bad.push("featKeep 的窗口期没有调 featCenterNow");
      if (!/FEAT\.recenter = FEAT\.recenter - 1/.test(keepSeg)) bad.push("窗口期没有递减 ⇒ 变成常驻重申（跟用户抢位置）");
    }
    // ⑥ 用户一拖拽就让出窗口期（否则窗口期内拖完立刻被拉回正中）
    //   ★锚点必须从 `featBuild` 往后找：文件里还有 probe 段的拖拽柄（另两处 OnDragStart），
    //     取第一个命中会**验错对象**（这属于「检查只匹配到一处门」那族假绿）。
    const iBuild = sm.indexOf("local function featBuild(");
    const iDrag = iBuild >= 0 ? sm.indexOf('"OnDragStart"', iBuild) : -1;
    const dragSeg = iDrag >= 0 ? sm.slice(iDrag, iDrag + 400) : "";
    if (iBuild < 0) bad.push("找不到 featBuild（本检查要验它建的拖拽柄）");
    else if (iDrag < 0) bad.push("featBuild 里找不到拖拽柄的 OnDragStart（本检查要验「拖拽让出窗口期」）");
    else if (dragSeg.indexOf("FEAT.recenter = 0") < 0) bad.push("OnDragStart 没有清居中窗口期 ⇒ 用户拖到哪都被拉回正中（与用户抢位置）");
    // ⑦ 复位也要开窗口期（复位 = 居中，同样会被客户端的开图流程覆盖掉）
    const iReset = sm.indexOf("function featReset()");
    const resetSeg = iReset >= 0 ? sm.slice(iReset, iReset + 700) : "";
    if (iReset < 0) bad.push("找不到 featReset");
    else if (!/FEAT\.recenter = SM_RECENTER_TICKS/.test(resetSeg)) bad.push("featReset 没有开居中窗口期 ⇒ 复位后客户端一摆位置就白复位");
    // ⑧ 读值口在位（组 237 全靠它们，缺一个那条断言就会静默跳过）
    for (const f of ["EVAL_SM_TEST_POS_STATE", "EVAL_SM_TEST_POS_REARM", "EVAL_SM_TEST_DRAG"]) {
      if (sm.indexOf("function " + f) < 0) bad.push("缺读值口 " + f);
    }
    if (bad.length) { console.log("SM POS CENTER CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM POS CENTER CHECK: 载入期 posArmed=true（首次开图必居中）· 清掉跨会话历史偏移 · 有界窗口期重申 + 拖拽即让位 · 复位同口径 · 读值口齐");
  })();

  // ===== SM MAP KEY CHECK（1.75.13）：「探索层坐标丢失 / 全部图层挤在左下重叠」的源码级判据 =====
  // 用户报障原话：「排查工具箱->缩放大地图->探索层额外处理异常: 某些地图打开之后会将探索层的坐标丢失.
  //   全部图层都集中在左下区域重叠」。
  // 真机存档实证（LIHAIBOAS2 / `simpleMapCfg.mapFitOrig`）：8 条原值里 **6 条完全相同**（155,-403 240×185），
  //   而 `WorldMapOverlay1..N` 是客户端**按序号逐图复用**的（一图一套矩形，用不到的 `:Hide()` 且不清几何）
  //   ⇒ 任何真实版式都不可能是「6 条同一矩形」；那批值就是「客户端还没布局 / 本图不用」的残留几何。
  // ★为什么必须源码级钉（这一案全是静默的）：
  //   ① 原值只按**纹理名**存一份（平表）⇒ 同一个名字在别的图上代表别的矩形，开别的图就把那套盖回去；
  //   ② 换图不作废记录 ⇒ 新图刚摆好的坐标 0.3s 内被顶掉（用户看到的「坐标丢失」）；
  //   ③ 对隐藏/没贴图的层照写 ⇒ 本图不用的层全停在同一个坐标（用户看到的「全部重叠」）；
  //   ④ 抓原值不等版式稳定 ⇒ 抓到的就是残留几何（① 的来源）；
  //   ⑤ 还原不区分「我们写过的」⇒ 关掉/还原时又写一遍别的图的矩形（用户自己救不回来）。
  (function () {
    const bad = [];
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM MAP KEY CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const raw = fs.readFileSync(p, "utf8");
    const sm = strip(raw);
    const seg = function (start, nextRe) {
      const i = sm.indexOf(start);
      if (i < 0) return "";
      const j = sm.indexOf(nextRe, i + start.length);
      return sm.slice(i, j > i ? j : i + 4000);
    };
    // ① 地图身份：必须走「包一层函数」的 pcall（本项目铁律：pcall 只留第一个返回值）
    if (sm.indexOf("local function smMapInfo()") < 0) bad.push("没有 smMapInfo（地图身份读取口）");
    if (sm.indexOf("pcall(function() return GetMapInfo() end)") < 0) {
      bad.push("读 GetMapInfo 不是「包一层函数」的 pcall ⇒ 多返回被截断，地图身份恒为 nil（跨图复用照旧）");
    }
    if (sm.indexOf("local function smMapKey()") < 0) bad.push("没有 smMapKey（地图身份 = 文件名 + 纹理尺寸）");
    if (sm.indexOf("local function smNumOverlays()") < 0) bad.push("没有 smNumOverlays（客户端自己的叠加层条数）");
    // ② ★★★1.75.5 定案（用户提问）：「定位信息**不落存档**」—— 客户端每次开图都会自己重摆这批纹理，
    //   存盘只会带来跨会话脏值（旧 schema 的跨图污染、版本戳迁移、以及 1.75.4 那场「存档已齐 ⇒ 每帧抖缩放」）。
    //   判据：① 文件里**不许**再出现把记录写进 `SM_CFG.mapFitOrig` 的代码（只在一次性清理里可以出现）；
    //        ② 记录只能落在**会话内存** `SMFIT.rec` / `SMFIT.recMap`；
    //        ③ 迁移只剩「老键还在就丢」这一条（天然幂等，不写版本戳 ⇒ 少一个会过期的字段）。
    const origUse = (sm.match(/SM_CFG\.mapFitOrig/g) || []).length;
    // ★只许出现「一次性清理」那种形态：读一次判空 + 置 nil（外加测试读值口里的清空）——
    //   任何**建表/写桶**的形态都是「定位信息又开始落存档」。
    if (/SM_CFG\.mapFitOrig\s*=\s*(\{|SM_CFG)/.test(sm)) bad.push("又把 `mapFitOrig` 建表/赋值（定位信息又开始落存档）");
    if (/SM_CFG\.mapFitOrig\[[^\]]*\]\s*=/.test(sm)) bad.push("又往 `mapFitOrig[...]` 写桶（跨会话缓存回来了）");
    if (origUse > 3) bad.push("`SM_CFG.mapFitOrig` 出现 " + origUse + " 处（应当只在一次性清理 + 测试清空里出现 ≤3 处）");
    if (!/SM_CFG\.mapFitOrig = nil/.test(sm)) bad.push("没有把老存档里那份 `mapFitOrig` **一次性清掉**（会留一份没人再读的缓存）");
    // ★正则陷阱：`~=` 里也含 `=`、`\s*` 会回溯 ⇒ 先把合法的 `= nil` 全部抹掉，再看还有没有赋值（本检查第一版就这么假红过）
    const mvLeft = sm.replace(/SM_CFG\.mapFitVer\s*=\s*nil/g, "");
    if (/SM_CFG\.mapFitVer\s*=/.test(mvLeft)) bad.push("还在写版本戳 `mapFitVer`（定位信息已不落存档 ⇒ 版本戳没有存在意义）");
    if (!/SM_CFG\.mapFitVer = nil/.test(sm)) bad.push("没有把老存档里那份 `mapFitVer` 一并清掉");
    if (sm.indexOf("local function smFitMigrate()") < 0) bad.push("没有 smFitMigrate（老存档键的一次性清理口）");
    if (sm.indexOf("SMFIT.recMap") < 0) bad.push("没有会话内存按图缓存 `SMFIT.recMap`（切回同一张图时会把折后值当原值再折一遍）");
    const applies = seg("local function smFitApply(", "\nlocal function ");
    if (applies.indexOf("SMFIT.recMap") < 0 && sm.indexOf("smFitBindMap(mk)") < 0) {
      bad.push("apply 没有把本图记录绑到会话内存（缺 `smFitBindMap(mk)`）");
    }
    // ③ 记录的唯一写入点是**抓原值**（apply 只读、绝不记原值）
    if (/SMFIT\.rec\[it\.key\]\s*=\s*\{/.test(applies)) bad.push("smFitApply 里又在写原值（`SMFIT.rec[it.key] = {`）⇒ 「折过的值被当原值」那类坑会回来");
    if (sm.indexOf("SMFIT.rec[it.key] = { o = o, idx = it.key") < 0) bad.push("smFitCapture 没有把记录写进 `SMFIT.rec`（唯一写入点）");
    // ④ 换图 = 换一套记录（会话内存按图：切走存回、切回取出）
    if (sm.indexOf("local function smFitNewMap(") < 0) bad.push("没有 smFitNewMap（换图换一套原值）");
    else {
      const nseg = seg("local function smFitNewMap(", "\nlocal function ");
      if (nseg.indexOf("SMFIT.recMap[old] = SMFIT.rec") < 0) bad.push("smFitNewMap 没有把旧图的记录**存回** recMap（切回来时会被迫重抓）");
      if (nseg.indexOf("SMFIT.rec = SMFIT.recMap[mk] or {}") < 0) bad.push("smFitNewMap 没有从 recMap **取回**本图的记录");
      if (nseg.indexOf("SMFIT.captured = false") < 0) bad.push("smFitNewMap 没有重置 captured ⇒ 本图不会再抓原值（用的还是上一张图的）");
    }
    if (sm.indexOf("pcall(smFitNewMap, mkNow)") < 0) bad.push("tick 里没有「地图身份变了 ⇒ 作废旧原值」（跨图沿用照旧）");
    if (sm.indexOf("local mkNow = smMapKey()") < 0) bad.push("tick 里没有取当前地图身份（换图检测形同虚设）");
    if (sm.indexOf("pcall(smFitNewMap, mk0)") < 0) bad.push("开启路径（smFitPrepare）没有对齐地图身份");
    // ⑤ 本图*在用*判定：IsShown + GetTexture 两条，且 apply / capture **各**要过它
    if (sm.indexOf("local function smFitInUse(o)") < 0) bad.push("没有 smFitInUse（本图在用的层判定）");
    else {
      const use = seg("local function smFitInUse(o)", "\nlocal function ");
      if (use.indexOf("IsShown") < 0) bad.push("smFitInUse 没看 IsShown（客户端本图不用的层会被我们改）");
      if (use.indexOf("GetTexture") < 0) bad.push("smFitInUse 没看 GetTexture（没贴图的层会被我们改）");
    }
    const applySeg = seg("local function smFitApply(", "\nlocal function ");
    const capSeg = seg("local function smFitCapture(", "\n" + "local function ");
    if (applySeg.indexOf("smFitInUse(") < 0) bad.push("smFitApply 没有过「本图在用」闸门 ⇒ 隐藏/本图不用的层照写（= 用户看到的重叠）");
    // ★★★变异 M1 实测教训：只验「调了这个函数」不够 —— 它必须**真的闸住写路径**（`if use and …` 这一行）。
    //   去掉 `use and` 时 `smFitInUse(` 还在（`local use = smFitInUse(o)` 那行）⇒ 只查调用会漏网（本项目 M8 同型）。
    if (!/if use and okp and p and okw and okh/.test(applySeg)) {
      bad.push("smFitApply 里「本图在用」没有闸住读写块（缺 `if use and okp and p and okw and okh`）⇒ 隐藏/本图不用的层照样被处理");
    }
    if (capSeg.indexOf("smFitInUse(") < 0) bad.push("smFitCapture 没有过「本图在用」闸门 ⇒ 抓原值会把别的图的残留几何记下来");
    // ⑥ 客户端说「本图 0 条叠加层」⇒ 一个几何都不碰（apply / capture 各一道）
    const zeroGates = (sm.match(/smNumOverlays\(\) == 0/g) || []).length;
    if (zeroGates < 2) bad.push("`smNumOverlays() == 0` 闸门只有 " + zeroGates + " 处（apply 与 capture 各要一处：零条叠加层的地图一个几何都不该碰）");
    // ⑦ 抓原值要**等版式稳定**（否则抓到的还是残留几何）
    if (!/local SMFIT_SETTLE = [0-9.]+/.test(sm)) bad.push("没有版式稳定等待常量 SMFIT_SETTLE");
    if (sm.indexOf("SMFIT.mapAge >= SMFIT_SETTLE") < 0) bad.push("tick 抓原值前没有等版式稳定（`SMFIT.mapAge >= SMFIT_SETTLE`）");
    if (sm.indexOf("SMFIT.mapAge = (tonumber(SMFIT.mapAge) or 0) + dt") < 0) bad.push("版式计时没有累加（等稳定形同虚设）");
    if (sm.indexOf("SMFIT.mapAge = 0") < 0) bad.push("地图关着/换图时没有把版式计时归零");
    // ⑧ 还原只还**本图我们写过的**层（逐层记账）
    if (sm.indexOf("SMFIT.wroteKeys[it.key] = mk") < 0) bad.push("折算时没有逐层记账（`SMFIT.wroteKeys[it.key] = mk`）⇒ 还原会去动没写过的层");
    const resSeg = seg("local function smFitRestore(", "\nlocal function ");
    if (resSeg.indexOf("SMFIT.wroteKeys[it.key] ~= mk") < 0) bad.push("smFitRestore 没有「只还本图写过的层」判据");
    // ⑨ 取证清单（只读）+ 命令 + 用法
    if (sm.indexOf("local function smFitDumpLines()") < 0) bad.push("没有 smFitDumpLines（取证清单的内容生成口）");
    else {
      const dseg = seg("local function smFitDumpLines()", "\nlocal function ");
      for (const k of ["GetNumMapOverlays", "GetMapOverlayInfo", "本图在用", "本图已写"]) {
        if (dseg.indexOf(k) < 0) bad.push("取证清单里缺关键读数 " + k + "（「谁写的、该是多少」判不出来）");
      }
    }
    if (!/sub == "dump"/.test(sm)) bad.push("`/ehm mapfit` 没有 dump 子命令（真机没法取证）");
    if (sm.indexOf("| dump（只读清单）|") < 0) bad.push("mapfit 用法说明里没有 dump（用户不知道有这个口）");
    // ⑩ ★★★1.75.5 事故（用户：「换了一个账号之后…地图缩放不正常了」＋「/reload 后探索层不生效、关/开一次才正常」）：
    //   ① 抓原值**不许每帧重跑**（真机证据：trace 60 条环 1 秒被刷满 ⇒ 每帧 ≈55 次/秒）；
    //   ② ★★★抓原值**绝不许翻转外框缩放** —— 旧写法「同一帧 SetScale(1) → 立刻读 → 放回」在外框已是 0.70 时
    //      是一次**真改动** ⇒ 客户端立刻重排/清锚点 ⇒ 紧接着的读**全部读不到**（且静默）= 用户「/reload 后探索层不生效」；
    //      关/开之所以能成，是因为关的时候 `featReset` 已把外框复位成真 1.00 ⇒ 那句 SetScale(1) 是空操作。
    //      ⇒ 正解 = **不翻转，按 es 归一**（本客户端实测「读回 = 逻辑×es」）。
    if (capSeg.indexOf("local todo, skipUse = {}, 0") < 0) bad.push("smFitCapture 没有「先筛候选」的 todo 列表（顺序判据的锚点）");
    else {
      const iTodo = capSeg.indexOf("if table.getn(todo) == 0 then");
      if (iTodo < 0) bad.push("smFitCapture 没有「候选为空 ⇒ 当场返回」的判据");
      const seg2 = iTodo >= 0 ? capSeg.slice(iTodo, iTodo + 320) : "";
      if (seg2.indexOf("SMFIT.captured = true") < 0) bad.push("候选为空时没有**落闩**（`SMFIT.captured = true`）⇒ tick 每帧重跑");
      if (capSeg.indexOf("if n >= table.getn(todo) then SMFIT.captured = true end") < 0) {
        bad.push("落闩判据不是「本轮目标**全部**拿到」（`n >= table.getn(todo)`）⇒ 要么永不落闩、要么读不出也当抓完");
      }
      // ★不许翻转 + 必须按 es 归一 + 读失败必须计数并如实播报
      if (/SetScale\s*,\s*\w+\s*,\s*1\b/.test(capSeg)) {
        bad.push("smFitCapture 里又在「临时把外框缩放置 1」⇒ 外框已是 0.70 时这句会惊动客户端、紧接着的读全读不到（1.75.5 实案）");
      }
      if (capSeg.indexOf("/ norm") < 0 || capSeg.indexOf('(SMFIT.needFold == true) and 1 or esC') < 0) {
        bad.push("smFitCapture 没有「按读回口径归一」（`norm`：needFold==true ⇒ 1，否则 ÷es）");
      }
      if (capSeg.indexOf("抓原值读不到") < 0 || capSeg.indexOf("SMFIT.capFails") < 0) {
        bad.push("smFitCapture 读不到时仍然**静默**（缺「抓原值读不到」日志 / `SMFIT.capFails` 计数）⇒ 下次再出问题又要靠猜");
      }
    }
    if (!/local SMFIT_CAP_GAP = [0-9.]+/.test(sm)) bad.push("没有抓原值的**有界重试**间隔常量 SMFIT_CAP_GAP");
    if (sm.indexOf("SMFIT.capAge >= SMFIT_CAP_GAP") < 0) bad.push("tick 里没有有界重试门（`SMFIT.capAge >= SMFIT_CAP_GAP`）⇒ 抓不出来时会每帧重试");
    // ⑪ ★★★1.75.5 另外两条硬化：瞬态 es 暂缓 + 两种读回口径都认（否则「每拍重写」的刷屏会回来）
    if (sm.indexOf("折算暂缓：读回 es=1.000 而设置值 scale=%s") < 0) {
      bad.push("缺「瞬态 es=1.000 而设置值≠1 ⇒ 暂缓折算」的判据 ⇒ 同一次开图会写两遍不同值");
    }
    // ★1.75.5 追加（真机日志：7 分钟内反复出现该瞬态）⇒ 暂缓这一拍要**主动把缩放掰回去**（下一拍就恢复），
    //   并且取证行要摊出「自身 GetScale / 父帧有没有」——那是区分「客户端重置缩放」与「父链一时读不到」的唯一证据。
    if (!/if math\.abs\(es - 1\) <= 0\.001[\s\S]{0,500}?pcall\(featApplyScale/.test(sm)) {
      bad.push("瞬态 es=1.000 时没有主动掰回缩放（`pcall(featApplyScale, …)`）⇒ 瞬态会拖很多拍");
    }
    if (sm.indexOf("自身 GetScale=%s ｜ 父帧=%s") < 0) bad.push("瞬态暂缓的取证行没摊出「自身 GetScale / 父帧」⇒ 分不清是哪一种瞬态");
    // ★★★1.75.5 追加（真机日志实证 `自身 GetScale=1.000 ｜ 父帧=有`）：**客户端会自己把地图帧缩放重置回 1.0**
    //   ⇒ 光靠 0.2s 节拍守不住（开图/换图后有一段「没缩放」窗口 = 用户报的「载入时缩放异常」）⇒ tick 里必须**每帧守**。
    if (!/if open then pcall\(featApplyScale, tonumber\(SM_CFG\.scale\) or 1\) end/.test(sm)) {
      bad.push("tick 里没有**每帧守缩放**（`if open then pcall(featApplyScale, …) end`）⇒ 客户端重置缩放后要等 0.2s 才掰回，用户会看到「载入时缩放异常」");
    }
    // ★★★顺序即判据（1.75.5 第二次修）：守缩放必须排在**读 es 之前** —— 先读后守 ⇒ 开图第一拍必读到客户端重置的
    //   1.000 ⇒ 触发「折算暂缓」、折算晚一拍；客户端若每帧重置就**一直晚**（用户现象：载入后要关开一次才正常）。
    const iGuard2 = sm.indexOf("if open then pcall(featApplyScale, tonumber(SM_CFG.scale) or 1) end");
    // ★`local eff = smEffScale(fr)` 在 `smFitApply` 的折算口径日志里也有一处 ⇒ 必须取**最后一次**出现（= tick 里那次），
    //   否则会拿 apply 里那处的下标去比 ⇒ 假红（本检查第一版就这么红了，别再用 indexOf）。
    const iEsRead = sm.lastIndexOf("local eff = smEffScale(fr)");
    if (iGuard2 >= 0 && iEsRead >= 0 && iGuard2 > iEsRead) {
      bad.push("tick 里「先读 es、后守缩放」顺序反了 ⇒ 开图第一拍必读到 1.000、折算晚一拍（客户端每帧重置时一直晚）");
    }
    if (applySeg.indexOf("local okB = near(x, wantX * es)") < 0) {
      bad.push("smFitApply 没有「读回 = 逻辑×es」这一种口径的接受判据（`okB`）⇒ 本客户端上每一拍都判「要改」而反复重写");
    }
    if (applySeg.indexOf("local okA = near(x, wantX)") < 0) bad.push("smFitApply 缺「读回 = 逻辑值」那一侧的接受判据（`okA`）");
    // ⑫ ★★★1.75.5 实案（用户跑 `/ehm mapfit diag` 当场弹红字）：`smFitDiag` 里在 `local changed, ready = 0, 0`
    //   **之前**引用了 `ready` ⇒ 绑成**全局 nil** ⇒ `string.format("…%d", nil)` 抛 bad argument（正是本项目头号杀手）。
    //   ★`DECL ORDER CHECK` 抓不到它：它按**顶层 local** 比对，函数内缩进的同名局部会被整名跳过（记忆里写明的盲区）
    //   ⇒ 这里按「首次出现」钉住这一条。
    const diagSeg = seg("local function smFitDiag(", "\nlocal function ");
    if (!diagSeg) bad.push("找不到 smFitDiag（本检查要验「local 之前不许引用」）");
    else {
      const iDecl = diagSeg.indexOf("local changed, ready");
      if (iDecl < 0) bad.push("smFitDiag 里找不到 `local changed, ready` 声明行（本检查的锚点）");
      else if (/\bready\b/.test(diagSeg.slice(0, iDecl))) {
        bad.push("smFitDiag 在声明 `local changed, ready` **之前**就用了 `ready` ⇒ 绑全局 nil，`%d` 会收到 nil 当场报错");
      }
    }
    // ⑬ ★★★1.75.5 实案修复：折算策略（诊断档）**不跨会话** —— 必须挂 `VARIABLES_LOADED` 把上一会话遗留的那份清掉，
    //   否则 `nofold` 会永久留在存档里（而主开关「关→开」只写 mapFit、**从不复位策略**）⇒ 用户「关闭/开启 缩放始终不生效」。
    //   ★为什么挂事件而不是文件执行期：文件执行期存档表还是空的（本项目既有教训）⇒ 清了也白清。
    const iMg = sm.indexOf('CreateFrame("Frame", "EH_SM_MODEGUARD"');
    if (iMg < 0) bad.push("没有策略守卫帧 EH_SM_MODEGUARD（诊断档会跨会话 ⇒ 功能可能被永久关死）");
    else {
      const mgSeg = sm.slice(iMg, iMg + 900);
      if (mgSeg.indexOf('RegisterEvent("VARIABLES_LOADED")') < 0) bad.push("策略守卫帧没挂 VARIABLES_LOADED（执行期读不到存档 ⇒ 清了也白清）");
      if (mgSeg.indexOf("SM_CFG.mapFitMode = nil") < 0) bad.push("策略守卫帧没有把 `SM_CFG.mapFitMode` 清成 nil（诊断档仍会跨会话）");
    }
    // 切到 nofold / 开启时**必须如实播报**（否则用户只会看到「开关坏了」，实案就是这样被误导的）
    if (sm.indexOf("这就是「关开都不生效」的原因") < 0) {
      bad.push("切到 nofold（或开启时）没有如实播报「一个几何都不碰」⇒ 用户会以为开关坏了");
    }
    // ⑭ ★★★1.75.5 真机定案（用户截图：**探索层贴图跑到游戏画面里**，右下角拼出一块丹莫罗地图）：
    //   写锚点**必须传帧对象** —— 本客户端把「字符串 / nil 相对帧」当成**锚到屏幕（UIParent）** ⇒ 纹理逃出地图窗口。
    //   （`smFitRestore` 一直是解析成对象的 ⇒ 两边行为不一致，这正是「关功能能救回来、开着就画到世界上」的真因。）
    if (/SetPoint,\s*o,\s*r\.p,\s*r\.rel,/.test(sm) || /SetPoint,\s*o,\s*r\.p,\s*r\.rel\b/.test(sm)) {
      bad.push("写锚点时把相对帧**名字/表字段 `r.rel` 直接**传给 SetPoint ⇒ 本客户端会锚到屏幕（探索层画到游戏画面上）");
    }
    if (sm.indexOf("local relObj = nil") < 0 || sm.indexOf("pcall(o.SetPoint, o, r.p, relObj, r.rp, wantX, wantY)") < 0) {
      bad.push("写锚点没有「先解析成帧对象再 SetPoint」（缺 `relObj` 那条路）");
    }
    // 捕获时要把**活对象**一起记下来（`relObj`），否则只能靠字符串（危险）
    if (sm.indexOf("relObj = rel") < 0) bad.push("抓原值没有把**活相对帧对象**记进记录（`relObj = rel`）⇒ 写回时只能靠字符串");
    // ⑮ ★★★1.75.5（**用户设计**，采纳）：「探索层不加缓存是否可以在 /reload 的时候不进行缩放,以获取原值,
    //   获取完成之后再进行缩放操作?」⇒ **本图还没有原值 ⇒ 先不缩放**（在自然档读原值），抓到立刻缩放；
    //   窗口必须**有界**（超时就先缩放，绝不把地图卡在满尺寸）。
    if (!/local SMFIT_HOLD_SEC = [0-9.]+/.test(sm)) bad.push("没有抓原值窗口上限常量 SMFIT_HOLD_SEC（窗口必须有界）");
    if (sm.indexOf("smFitHold") < 0) bad.push("没有 `smFitHold`（抓原值窗口；★必须是**提前声明的文件级 local**，放进 SMFIT 会绑全局 nil —— LOCAL ORDER CHECK 抓得到）");
    const iFs = sm.indexOf("local function featApplyScale(s)");
    const fsSeg = iFs >= 0 ? sm.slice(iFs, iFs + 1200) : "";
    if (!/if \(tonumber\(smFitHold\) or 0\) > 0 and math\.abs\(s - 1\) > 0\.001 then return end/.test(fsSeg)) {
      bad.push("featApplyScale 没有「抓原值窗口内先不缩放」的让位（缺 smFitHold 判据）⇒ 抓原值又要在缩放档里读了");
    }
    if (sm.indexOf("抓原值窗口开启") < 0 || sm.indexOf("抓原值窗口结束") < 0) bad.push("抓原值窗口没有「开/收」的取证行（用户看不到也就没法判）");
    if (sm.indexOf("**超时/没抓全**（先缩放，稍后由 1 秒一次的有界重试继续补抓）") < 0) {
      bad.push("抓原值窗口超时没有如实播报（少了它就可能把地图卡在满尺寸）");
    }
    // ⑰ ★★★1.75.5（用户先要「获取原值的地方添加日志信息,打印出来」，随后又要求「好的功能正常了.清理下这些调试日志」）：
    //   最终口径 = **安静档默认 + 详细档开关**：
    //   ① 抓原值必须**看得见**（走常开出口 `smFitSay` → `EVAL_SAY_FORCE`，不受「调试日志」闸门管；同时进 `mapFitTrace`）；
    //   ② 安静档每次开图只留**两条**（「已读到 N 条 ⇒ 落闩」+ 首次「折算已对齐」）、关图**一条**（清空）；真出问题（读不到 / 还回失败 / 没还回）**必须出声**；
    //   ③ 逐条原值 / 第 N 次尝试 / 每次重试 / 窗口开关 / 每次小结 / 每次折算 = **详细档**（`/ehm mapfit verbose on`，`SM_CFG.mapFitVerbose == true`，**nil = 关**）；
    //   ④ 无论哪档都进 `mapFitTrace` 取证环（安静档只是不上屏）。
    if (sm.indexOf("local function smFitSay(fmt, ...)") < 0) {
      bad.push("没有常开播报口 smFitSay（抓原值只用 mfLog ⇒ 关掉「调试日志」就一个字都不出声）");
    } else {
      const iSay = sm.indexOf("local function smFitSay(fmt, ...)");
      const saySeg = sm.slice(iSay, iSay + 700);
      if (saySeg.indexOf("EVAL_SAY_FORCE") < 0) bad.push("smFitSay 没走常开出口 EVAL_SAY_FORCE（等于还是被闸门管）");
      if (saySeg.indexOf("mfLog(") < 0) bad.push("smFitSay 没进取证环 mfLog（聊天框刷过去就再也查不到）");
    }
    // ③ 详细档口（默认关）
    if (!/local function smFitVerboseOn\(\)\s*\n\s*return SM_CFG\.mapFitVerbose == true/.test(sm)) {
      bad.push("没有 `smFitVerboseOn()`（真值只认 SM_CFG.mapFitVerbose == true ⇒ nil 必须是关）");
    }
    const iSayV = sm.indexOf("local function smFitSayV(fmt, ...)");
    if (iSayV < 0) bad.push("没有详细档出口 smFitSayV");
    else {
      const vSeg = sm.slice(iSayV, iSayV + 500);
      if (vSeg.indexOf("smFitVerboseOn()") < 0) bad.push("smFitSayV 没有过详细档开关（等于两个口子没区别）");
      if (vSeg.indexOf("mfLog(") < 0) bad.push("smFitSayV 没进取证环 mfLog（详细档关着时连取证都没了）");
    }
    const iCap2 = sm.indexOf("local function smFitCapture()");
    const iCapEnd2 = sm.indexOf("local function smFitRestore(");
    if (iCap2 < 0 || iCapEnd2 <= iCap2) bad.push("找不到 smFitCapture 的区间（抓原值播报判据无从检查）");
    else {
      const cap = sm.slice(iCap2, iCapEnd2);
      // ② 安静档必须留的两条（成功 + 关图由 dropOnClose 负责）
      if (cap.indexOf('smFitSay("抓原值：已读到 **%d 条**原值') < 0) {
        bad.push("安静档没有「已读到 N 条原值 ⇒ 落闩」那条成功播报（用户会以为压根没抓）");
      }
      // ①③ 详细行必须走 smFitSayV，不许占用安静档口子（反向哨兵：刷屏就是从这里回来的）
      for (const [lit, why] of [
        ["smFitSayV(\"抓原值 第%d次尝试", "「第 N 次尝试」必须走详细档（否则每次重试都上屏）"],
        ["smFitSayV(\"抓原值：%s 读回", "逐条原值必须走详细档（8~18 条一行一个 = 刷屏）"],
        ["smFitSayV(\"抓原值小结", "逐次小结必须走详细档"],
        ["smFitSayV(\"抓原值：本图 %d 个候选", "「候选都还没在用」的重试提示必须走详细档"],
      ]) {
        if (cap.indexOf(lit) < 0) bad.push(why);
      }
      if (/smFitSay\("抓原值 第%d次尝试/.test(cap)) bad.push("「第 N 次尝试」仍走安静档口子 ⇒ 又刷屏了");
      if (/smFitSay\("抓原值：%s 读回/.test(cap)) bad.push("逐条原值仍走安静档口子 ⇒ 又刷屏了");
      // 真出问题必须出声（读不到 / 一个都没读到时的最终结论）
      if (cap.indexOf('smFitSay("抓原值**读不到**') < 0) bad.push("抓原值**读不到**时没有安静档播报（真出问题就静默了）");
      if (cap.indexOf("SMFIT.saidFail") < 0) bad.push("「读不到」的播报没有一次门（每次重试都会再报一遍）");
    }
    // ② 折算那条「叠加层适配：对齐 N 个」必须**每次开图只报一次**（真机实测会重复 6 次以上）
    if (sm.indexOf("local firstFold = (not SMFIT.saidFold)") < 0) {
      bad.push("折算播报没有「每次开图只报一次」的门（真机实测重复 6 次以上）");
    }
    if (sm.indexOf("SMFIT.saidLatch, SMFIT.saidFail, SMFIT.saidEmpty, SMFIT.saidFold = false, false, false, false") < 0) {
      bad.push("「每次开图只报一次」的标记没有在换图/关图时归零（要么不报、要么一路刷）");
    }
    // ④ 命令口 + 读值口（用户要能自己开关详细档）
    if (sm.indexOf('string.find(sub, "^verbose")') < 0) bad.push("没有 `/ehm mapfit verbose on|off` 分支");
    if (sm.indexOf("SM_CFG.mapFitVerbose = true") < 0 || sm.indexOf("SM_CFG.mapFitVerbose = nil") < 0) {
      bad.push("详细档真值缺少读写点（on 写 true / off 写 nil）");
    }
    // ⑤ 详细档**不跨会话**（同 mapFitMode 的理由：它是排查用的，忘了关就一直刷屏）
    const iMg2 = sm.indexOf('CreateFrame("Frame", "EH_SM_MODEGUARD"');
    if (iMg2 > 0 && sm.slice(iMg2, iMg2 + 1800).indexOf("SM_CFG.mapFitVerbose = nil") < 0) {
      bad.push("策略守卫帧没有一起清 `mapFitVerbose`（详细档会跨会话 ⇒ 忘了关就一直刷屏）");
    }
    // 地图**没开**时，必须把「抓原值要等开图」说清楚（用户报的「重开后没重开地图」那一次，这就是唯一原因）
    if (sm.indexOf("**要等你把地图打开**才读得到") < 0) {
      bad.push("启用时没有说明「地图没开 ⇒ 抓原值要等开图」（用户看不到原因就只能猜）");
    }
    // ⑱ ★★★1.75.5（**用户要求**）：「每次地图关闭都把原值数据清理、不要保存这个值；每次打开地图都重新获取原值、重新缩放大地图」
    //   （+「每次 reload 载入也当第一次」—— 那条本来就成立：原值只在会话内存）。
    //   判据五条：① 真值唯一且**默认开**（只认 `mapFitFresh ~= false`，nil ⇒ 开）；
    //   ② 清空发生在**关图那一刻**（`closedNow`，不是每帧、也不是开图时）；③ 只动**本图**（别的分桶不许碰）；
    //   ④ **先还回自然档并严格自验，验不过就绝不清**（否则把折后的值当原值 = 折两遍）；⑤ 折算档门（nofold 不清）。
    if (!/local function smFitFreshOn\(\)\s*\n\s*return SM_CFG\.mapFitFresh ~= false/.test(sm)) {
      bad.push("没有 `smFitFreshOn()`（真值只认 SM_CFG.mapFitFresh ~= false，nil ⇒ 开）");
    }
    const iDrop = sm.indexOf("local function smFitDropOnClose(mk)");
    if (iDrop < 0) bad.push("没有 smFitDropOnClose（「关图即清空原值」无处落地）");
    else {
      const drop = sm.slice(iDrop, iDrop + 2800);
      const iBack = drop.indexOf("pcall(smFitRestore, true)");
      const iWipe = drop.indexOf("SMFIT.rec = {}");
      if (iBack < 0) bad.push("smFitDropOnClose 没有「先把折过的几何还回自然档」");
      else if (iWipe < 0 || iBack > iWipe) bad.push("smFitDropOnClose 的顺序错了：**先还回、再清空**（反过来就是把折后的值当原值）");
      if (drop.indexOf("没能还回自然档") < 0) bad.push("还回失败时没有安全阀（**保留**记录；清了下次开图会把折后的值当原值）");
      if (drop.indexOf("math.abs(tonumber(vx) - tonumber(r.x)) <= 0.75") < 0) {
        bad.push("还回后没有**按本档口径严格自验**（两种读回口径在数值上长得一样 ⇒ 只信 smFitRestore 的宽松判定会漏）");
      }
      if (drop.indexOf("SMFIT.recMap[mk] = {}") < 0) bad.push("smFitDropOnClose 没有只清**本图**分桶（`SMFIT.recMap[mk] = {}`）");
    }
    if (sm.indexOf("local closedNow = (not open) and SMFIT.open") < 0) bad.push("没有 closedNow（关图那一下；不许每帧清）");
    const iCloseGate = sm.indexOf("if closedNow and smFitOn() and smFitFreshOn() and smFitNeedFold() then");
    if (iCloseGate < 0) bad.push("tick 里没有「关图 + 适配开 + 折算档」的清空门");
    const iWin2 = sm.indexOf('smFitSay("抓原值窗口开启');
    if (iWin2 > 0 && iCloseGate > iWin2) bad.push("清空门排在「抓原值窗口」之后 ⇒ 开图那一拍窗口会按旧记录判成「已齐」而不开");
    // ★★「0 条也算已齐」那个真机 bug 的判据：todo 空的落闩必须**以「确有记录」为前提**
    if (sm.indexOf("if smFitRecCount() > 0 then") < 0) {
      bad.push("空候选仍然无条件落闩（真机 bug：0 条也报「已抓到原值」⇒ 之后再也不会抓）");
    }
    if (sm.indexOf("**不算抓到原值**") < 0) bad.push("「一个候选都不在用」时没有如实说明「不算抓到、不落闩、1 秒后重试」");
    if (sm.indexOf('string.format("**已抓到原值 %d 条**", nRecWin)') < 0) {
      bad.push("窗口收口的措辞没有与实际条数挂钩（0 条也报「已抓到原值」就是被这条坑的）");
    }
    // 抓原值窗口也必须只在**折算档**开（否则 nofold 的地图会白白满尺寸 2 秒）
    if (sm.indexOf("elseif smFitNeedFold() and (not SMFIT.captured) and next(SMFIT.rec or {}) == nil then") < 0) {
      bad.push("抓原值窗口没带 smFitNeedFold() 门（nofold 档会被按在自然档白等 2 秒）");
    }
    // 命令口 + 读值口（用户要能开关它做 A/B）
    if (sm.indexOf('string.find(sub, "^fresh")') < 0) bad.push("没有 `/ehm mapfit fresh on|off` 分支");
    if (sm.indexOf("function EVAL_SM_TEST_MAPFIT_FRESH()") < 0) bad.push("没有真值读值口 EVAL_SM_TEST_MAPFIT_FRESH");
    if (bad.length) { console.log("SM MAP KEY CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    // ⑯ ★★★1.75.5（**用户指定「本办法」**）：手动适配一条命令走完五步并**逐步打印**。
    //   用户原话：「缩放功能开启的情况下, 游戏首次载入, 可以做个调试命令执行. 打开地图, 等待2s, 获取原值.
    //   打印原值, 应用缩放. 打印缩放信息. 这样的调整过程.」
    //   ★为什么必须钉住：这是「出问题时看不出卡在哪一步」的唯一解 —— 五步缺任何一步，用户回传的那段日志就断链。
    const iFix = sm.indexOf("local function smFixDoCapture()");
    const iFixNow = sm.indexOf("local function smFixNow()");
    if (iFix < 0 || iFixNow < 0 || iFixNow <= iFix) {
      bad.push("没有手动适配的两个函数 smFixDoCapture / smFixNow（/ehm fitnow）");
    } else {
      const seg = sm.slice(iFix, iFixNow);
      // ① 第1步开图**只许 ShowUIPanel**（Toggle 会把已经开着的地图关掉 —— 本项目既有纪律）
      const segNow = sm.slice(iFixNow, iFixNow + 2200);
      if (segNow.indexOf("pcall(ShowUIPanel, wm)") < 0) bad.push("第1步没有用 `ShowUIPanel` 开图");
      if (/Toggle/i.test(segNow)) bad.push("第1步用了 Toggle 开图（会把握在手上的地图关掉）⇒ 必须只用 ShowUIPanel");
      // ② 第2步 = 置自然档 1.00 并等 2 秒（等的是客户端版式，别抢读）
      if (segNow.indexOf("pcall(featApplyScale, 1)") < 0) bad.push("第2步没有把外框放回**自然档 1.00**（不置回就会在缩放档里读原值）");
      if (!/>= 2\.0 then/.test(segNow)) bad.push("第2步没有「等满 2 秒」的计时判据（等不到版式稳定就抓，读数必错）");
      if (segNow.indexOf('EH_SM_FITFIX') < 0) bad.push("没有计时帧 EH_SM_FITFIX（2 秒等待无从实现）");
      // ③ 第3步读原值：**不翻转、不归一**（本段一个 SetScale 都不该有 —— 外框已是自然档，读回即原值）
      if (seg.indexOf("不翻转、不归一") < 0) bad.push("第3步没有写明「不翻转、不归一」的口径");
      if (/SetScale/.test(seg)) bad.push("第3步（读原值）里出现了 SetScale ⇒ 又变成「读的时候翻转外框」= 读不到");
      if (seg.indexOf('from = "fixnow"') < 0) bad.push("第3步写的记录没有打 `from = \"fixnow\"` 标记（事后分不清这份原值是谁抓的）");
      if (seg.indexOf("原值 %s = (%.1f,%.1f) %.1f×%.1f") < 0) bad.push("第3步没有**逐条打印原值**");
      // ④ 第4步套缩放并打印三个读数（设置值 / 自身 GetScale / 父链连乘）
      if (seg.indexOf("设置值=%.2f") < 0 || seg.indexOf("自身 GetScale=") < 0 || seg.indexOf("父链连乘=") < 0) {
        bad.push("第4步没有把「设置值 / 自身 GetScale / 父链连乘」三个读数一起打印（分不清是没写进去还是读不回来）");
      }
      // ⑤ 第5步折算并逐条打印「原值 → 写入」
      if (seg.indexOf("原值(%.1f,%.1f %.1f×%.1f) → 写入(") < 0) bad.push("第5步没有逐条打印「原值 → 写入」");
      // ⑥ **必须收尾把让位标记放掉**，否则自动逻辑被永久让位 = 新故障
      if (seg.indexOf("smFixActive = false") < 0) bad.push("手动适配结束时没有把 `smFixActive` 放掉（自动逻辑会被永久让位）");
      if (seg.indexOf("if SM_FIX.done then return 0 end") < 0) bad.push("手动适配没有重入闸 `SM_FIX.done`（计时帧 + 兜底两条路会各跑一遍）");
    }
    // ⑦ 自动 tick 必须**整段让位**（挡在最前面，连「每帧守缩放」「抓原值窗口」都不参与），且排在取 dt 之前
    const iLet = sm.indexOf("if smFixActive then return end");
    const iTkDt = sm.lastIndexOf("local dt = tonumber(arg1) or 0.05");
    if (iLet < 0) bad.push("自动 tick 没有「手动适配进行中 ⇒ 让位」的判据（手动过程会被自动逻辑抢写缩放）");
    else if (iTkDt >= 0 && iLet > iTkDt) bad.push("让位判据排在取 dt 之后（必须挡在 tick 最前面）");
    // ⑧ 命令入口 + 读值口（用户敲的就是它；没有入口 = 用户根本用不上）
    if (sm.indexOf('msg == "fitnow"') < 0) bad.push("没有 `/ehm fitnow` 分支（别名 适配 / 修正）");
    if (sm.indexOf("function EVAL_SM_TEST_FIX_STATE()") < 0 || sm.indexOf("function EVAL_SM_TEST_FIX_DO()") < 0) {
      bad.push("手动适配缺读值口 EVAL_SM_TEST_FIX_STATE / EVAL_SM_TEST_FIX_DO");
    }
    // ⑨ 夹具自清必须把让位标记放掉（否则上一段夹具会把**后面所有组**的 tick 关掉 —— 静默、且看着像功能坏了）
    if (!/smFixActive, SM_FIX\.t, SM_FIX\.done = false, 0, false/.test(sm)) {
      bad.push("夹具自清没有复位 `smFixActive`（上一段夹具会把后面所有组的自动 tick 关掉）");
    }
    if (bad.length) { console.log("SM MAP KEY CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM MAP KEY CHECK: 定位信息**不落存档**（会话内存按图）· 老缓存一次性清掉且不再写版本戳 · 换图换一套记录 · " +
      "只碰本图在用的层（IsShown/GetTexture）· 零叠加层不动手 · 抓原值等版式稳定 + **先筛候选再动缩放/落闩/有界重试** · " +
      "瞬态 es 不折算 · 两种读回口径都认 · 还原只还写过的层 · 取证清单+命令在位 · **手动适配（/ehm fitnow）五步齐**");
  })();

  // ===== SM PANEL SYNC CHECK（1.75.5）：地图设置面板的值 ↔ 快捷键（滚轮）**双向同步**、且只有一个刷新口 =====
  // 用户原话：「缩放大地图.在使用快捷键设置地图缩放和透明度之后,地图设置内的值要能同步更新.双向同步更新.根源数据保持统一」
  // ★为什么必须源码级钉：这属于**接线**（漏接不报错、只是界面数字不动），而真值本身没坏 ⇒ 行为断言照不到「滚轮那条路忘了刷面板」。
  (function () {
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM PANEL SYNC CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const sm = strip(fs.readFileSync(p, "utf8"));
    const bad = [];
    // ① 前向声明：`smPanelSync` 定义在面板构造里（滚轮之后）⇒ 不先声明成 local，滚轮里就会绑到全局 nil（同步静默失效）
    if (sm.indexOf("local smPanelSync = nil") < 0) {
      bad.push("smPanelSync 没有前向声明（缺 `local smPanelSync = nil`）⇒ 滚轮里那句绑全局 nil，同步会静默失效");
    }
    // ② 滚轮两个分支（Shift=透明度 / Ctrl=缩放）各要刷一次 —— 切片口径：从 featWheelOn 到 featBuild（期间不含面板构造）
    const iW = sm.indexOf("local function featWheelOn(");
    const iB = sm.indexOf("local function featBuild(");
    const wheelSeg = (iW >= 0 && iB > iW) ? sm.slice(iW, iB) : "";
    if (!wheelSeg) bad.push("找不到 featWheelOn 段（本检查要验「滚轮 → 面板同步」）");
    else {
      const n = (wheelSeg.match(/pcall\(smPanelSync\)/g) || []).length;
      if (n < 2) bad.push("滚轮处理器里只有 " + n + " 处刷新面板（Shift 透明度 / Ctrl 缩放 **各**要一处）");
    }
    // ③ 面板 [-] / [+] 也走同一个刷新口（单一来源）；总数 ≥4（滚轮 2 + 面板 2）
    const total = (sm.match(/pcall\(smPanelSync\)/g) || []).length;
    if (total < 4) bad.push("`pcall(smPanelSync)` 全文件只有 " + total + " 处（滚轮 2 + 面板 [-] / [+] 2）⇒ 有一侧没走统一刷新口");
    // ④ 反向哨兵：真值只认 `SM_CFG.alpha` / `SM_CFG.scale`（面板与滚轮写同一份），不许出现第二份「面板自己的值」
    if (/local\s+panelAlpha|local\s+panelScale/.test(sm)) bad.push("出现了面板自己的值副本（panelAlpha/panelScale）⇒ 真值分叉");
    if (bad.length) { console.log("SM PANEL SYNC CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM PANEL SYNC CHECK: 面板值 ↔ 滚轮**双向同步**（滚轮 2 处 + 面板 [-] / [+] 2 处都走统一刷新口 `smPanelSync`）· " +
      "前向声明在位（否则绑定全局 nil）· 真值唯一（SM_CFG.alpha / SM_CFG.scale）");
  })();

  // ===== SM GROUP ROSTER CHECK：本模块测试文件的**组号清单**不许静默少一个（与 DF 那套同族）=====
  (function () {
    const WANT = [224, 225, 226, 230, 232, 237, 253, 254, 255, 256];
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

  // ===== SM OFF SILENT CHECK（1.75.7）：「未开启缩放大地图」时**不许再监听探索层** ===== 
  // 用户排查原话：「排查缩放大地图功能.在未开启的情况下会不会监听探索层的缩放操作」
  // ★为什么必须用源码检查：这是**接线顺序**的性质（闸门必须在任何读/写之前），断言只能证明「这一次没动」，
  //   而源码检查能钉住「闸门就在最前面」——以后有人把探测挪到闸门之前，真机上就会每帧白读 GetEffectiveScale、
  //   甚至（像修前那样）在关闭状态下把叠加层几何折了（实测 8 次写入 + 2 条原值），而测试未必照得到。
  // 判据三条：
  //   ① EH_SM_FEAT 的 OnUpdate 里，`if not EVAL_SM_ENABLED() then … return end` 必须出现在
  //      **第一次 `featOpenNow()` / `GetEffectiveScale` 读取之前**（顺序即判据）；
  //   ② 该闸门块里必须有 `return`（漏了 return = 闸门形同虚设）；
  //   ③ 关闭路径（EVAL_SM_SET 的 else 分支）必须**当场还原**叠加层几何（`smFitRestore`）——
  //      旧设计把还原寄托在常驻 tick 上，正是「关掉还在跑」的根源。
  (function () {
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM OFF SILENT CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const sm = fs.readFileSync(p, "utf8");
    const bad = [];
    const iCreate = sm.indexOf("\"EH_SM_FEAT\"");
    // ★★★1.75.9：门控文本现在在文件里**出现多处**（滚轮处理器 / 坐标行 / tick 各一道门）⇒
    //   必须**从 tick 帧创建处往后**找；旧版的全文件 indexOf 会命中前面那两道门，
    //   于是「闸门在探测之前」这条顺序判据直接失效（本轮实测就是这个假红）。
    const iGuard = iCreate >= 0 ? sm.indexOf("if not EVAL_SM_ENABLED() then", iCreate) : -1;
    const iProbe = iCreate >= 0 ? sm.indexOf("local open = featOpenNow()", iCreate) : -1;
    if (iCreate < 0) bad.push("找不到 EH_SM_FEAT 那个 tick 帧（改名字了？本检查锚点是它）");
    if (iGuard < 0) bad.push("tick 里没有 `if not EVAL_SM_ENABLED() then` 免打扰闸门 ⇒ 关闭时照跑（修前实测：10 拍写 8 次几何）");
    if (iProbe < 0) bad.push("找不到 `local open = featOpenNow()`（tick 的探测入口被改名？本检查要钉住「闸门在探测之前」）");
    if (iCreate >= 0 && iGuard >= 0 && iGuard < iCreate) bad.push("闸门出现在 tick 帧创建**之前**（那是另一个函数里的？顺序判据失效）");
    if (iGuard >= 0 && iProbe >= 0 && iGuard > iProbe) bad.push("闸门排在**探测之后** ⇒ 关闭时照样每帧读 IsShown/GetEffectiveScale（= 用户问的那件事）");
    if (iGuard >= 0) {
      const seg = sm.slice(iGuard, iGuard + 400);
      if (seg.indexOf("return") < 0) bad.push("闸门块里没有 `return` ⇒ 闸门形同虚设（后面照样跑）");
      if (seg.indexOf("FEAT.applied") < 0) bad.push("闸门里没清 `FEAT.applied` ⇒ 重新开启时可能不重新应用");
    }
    // ③ 关闭路径必须当场还原几何
    const iSet = sm.indexOf("function EVAL_SM_SET(");
    const iNext = iSet >= 0 ? sm.indexOf("\nfunction ", iSet + 10) : -1;
    const setSeg = (iSet >= 0) ? sm.slice(iSet, iNext > iSet ? iNext : iSet + 2000) : "";
    if (iSet < 0) bad.push("找不到 EVAL_SM_SET（本检查要验关闭路径）");
    else if (setSeg.indexOf("pcall(smFitRestore") < 0) bad.push("关闭路径没有**真的调用** smFitRestore（只写 type() 探测不算）⇒ 关掉后叠加层永远停在被折算过的位置");
    if (bad.length) { console.log("SM OFF SILENT CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM OFF SILENT CHECK: 关闭即免打扰（闸门在探测之前 + 有 return + 清 applied）· 关闭路径当场还原叠加层几何");
  })();
  // ===== SM FIT CASCADE CHECK（1.75.9）：「探索层纹理被缩两遍」的源码级判据 =====
  // 用户实测原话：「现在确定是在未开启插件载入..的情况下打开大地图缩放, 和在开启插件载入之后重新关闭,又打开 ,
  //   这两种情况都会发生.纹理渲染层被缩放两次的问题」＋「在开启/关闭.大地图缩放要做好探索层纹理的事件清理」。
  // 真机证据（用户 DebugBox 截图）：WorldMapOverlay1 = 105×105／锚 174,-157 = 我们写的 150.5×0.7／248.5×0.7，
  //   DetailFrame 701×468 = 1002×668×0.7 ⇒ **几何读回含父帧缩放**，而客户端**自己会级联**。
  // ★为什么必须源码级钉：这一案的三条根因全是**静默**的 ——
  //   ① 在「会级联」的客户端上照样折算（第二遍，行为看着正常、只是位置尺寸不对）；
  //   ② 原值在**已缩过的状态**下记（读原值/写新值顺序反了）⇒ 每关开一轮连乘一次；
  //   ③ 关闭时不收钩子（坐标行 OnUpdate / 拖拽柄 / ESC 列表项）⇒ 关掉后照跑。
  (function () {
    const p = path.join(__dirname, "tools", "SimpleMap.lua");
    if (!fs.existsSync(p)) { console.log("SM FIT CASCADE CHECK: (无 tools/SimpleMap.lua，跳过)"); return; }
    const raw = fs.readFileSync(p, "utf8");
    const sm = strip(raw);
    const bad = [];
    // ① 折算前必须先探测，且只在 needFold == true 时动手
    if (sm.indexOf("local function smFitDetect()") < 0) bad.push("没有探测函数 smFitDetect ⇒ 无从判断客户端会不会级联");
    if (!/if not smFitNeedFold\(\) then return end/.test(sm)) bad.push("tick 里没有「折算策略闸门」（`if not smFitNeedFold() then return end`）");
    // ★★1.75.9 变异 M1 当场抓到：只匹配**一处**不够 —— `smFitApply` 还有**直接入口**（`/ehm mapfit diag`
    //   与读值口 `EVAL_SM_TEST_MAPFIT_APPLY`），那道门也必须独立钉住，否则「去掉 apply 里的门」会漏网。
    if (!/if not smFitNeedFold\(\) then return 0, 0, 0 end/.test(sm)) bad.push("smFitApply **自己**没有策略闸门 ⇒ 直接入口（diag / 读值口）会绕过");
    // ★★★1.75.9 回归：**默认档必须是 fold**（用户实测：「现在正常开启都无法生效缩放修正」= 把默认改成听探测引起的）
    //   ★注意本检查用的是**剥注释后**的文本（`strip`）⇒ 这里必须按**结构**断言，别指望注释里的字样。
    const iNF = sm.indexOf("local function smFitNeedFold()");
    const iNFend = iNF >= 0 ? sm.indexOf("\nend", iNF) : -1;
    const nfSeg = (iNF >= 0 && iNFend > iNF) ? sm.slice(iNF, iNFend) : "";
    if (!nfSeg) bad.push("找不到 smFitNeedFold（折算策略的唯一判据）");
    else {
      if (nfSeg.indexOf("if m == \"nofold\" then return false end") < 0) bad.push("smFitNeedFold 缺 nofold 分支（策略不能只做两档）");
      if (nfSeg.indexOf("return (SMFIT.needFold == true)") < 0) bad.push("smFitNeedFold 缺 auto 分支（听探测）");
      const lastLine = nfSeg.split("\n").map(l => l.trim()).filter(l => l !== "").pop() || "";
      if (lastLine !== "return true") bad.push("smFitNeedFold 默认分支不是「折算」（实测 " + lastLine + "）⇒ 正常开启会完全不生效（用户实测过的回归）");
    }
    if (sm.indexOf("function EVAL_SM_MAPFIT_MODE_SET(") < 0) bad.push("没有策略写口 EVAL_SM_MAPFIT_MODE_SET（用户就没法 A/B 定档）");
    if (sm.indexOf("SMFIT.needFold == nil then SMFIT.needFold = smFitDetect()") < 0) bad.push("tick 里没有「没探测过就先探一次」⇒ 开图后才开的功能永远不折算");
    // ② apply 里不许再记原值（记录统一归自然档抓）
    const iApply = sm.indexOf("local function smFitApply(");
    const iApplyEnd = iApply >= 0 ? sm.indexOf("\nlocal function ", iApply + 10) : -1;
    const applySeg = (iApply >= 0 && iApplyEnd > iApply) ? sm.slice(iApply, iApplyEnd) : "";
    if (!applySeg) bad.push("找不到 smFitApply 的函数体（本检查要验它不再记原值）");
    else {
      // ★1.75.5：记录**只由抓原值写**（不再有「从存档采纳」那条路）⇒ apply 里既不许写存档、也不许新建记录
      if (/saved\[it\.key\]\s*=/.test(applySeg)) bad.push("smFitApply 里仍在**写原值**（`saved[it.key] = …`）⇒ 又会把已折过的值当原值记下来（关一次开一次连乘）");
      if (/SMFIT\.rec\[it\.key\]\s*=\s*\{/.test(applySeg)) bad.push("smFitApply 里在**新建原值记录**（`SMFIT.rec[it.key] = {`）—— 唯一写入点必须是 smFitCapture");
      if (applySeg.indexOf("local r = SMFIT.rec[it.key]") < 0) bad.push("smFitApply 没有「读已有记录」的那条路（`local r = SMFIT.rec[it.key]`）");
    }
    // ③ ★★★1.75.5 反向（本条判据已**反转**）：抓原值**绝不许**「临时把外框缩放置 1」——
    //   外框已是 0.70 时那句是真改动 ⇒ 客户端重排/清锚点 ⇒ 紧接着的读全读不到（用户「/reload 后探索层不生效」的真因）；
    //   正解 = 不翻转、按读回口径归一（详见 `SM MAP KEY CHECK ⑩`）。
    const iCap = sm.indexOf("local function smFitCapture()");
    const iCapEnd = iCap >= 0 ? sm.indexOf("\nlocal function ", iCap + 10) : -1;
    const capSeg = (iCap >= 0 && iCapEnd > iCap) ? sm.slice(iCap, iCapEnd) : "";
    if (!capSeg) bad.push("没有 smFitCapture（原值必须在会话内存里记一次）");
    else if (/SetScale\s*,\s*\w+\s*,\s*1\b/.test(capSeg)) {
      bad.push("smFitCapture 又在翻转外框缩放（`SetScale …, 1`）⇒ 「/reload 后探索层不生效」会复发");
    }
    // ④ 还原里不许清记录（清了就等于允许重记）
    const iRes = sm.indexOf("local function smFitRestore(");
    const iResEnd = iRes >= 0 ? sm.indexOf("\nlocal function ", iRes + 10) : -1;
    const resSeg = (iRes >= 0 && iResEnd > iRes) ? sm.slice(iRes, iResEnd) : "";
    if (!resSeg) bad.push("找不到 smFitRestore");
    else if (resSeg.indexOf("SMFIT.rec = {}") >= 0) bad.push("smFitRestore 里清了 `SMFIT.rec` ⇒ 下次开启会把已折过的值当原值重记（旧版「缩两遍」的根因）");
    // ⑤ 开启路径：先准备（探测 + 抓原值）再套缩放
    const iSet = sm.indexOf("function EVAL_SM_SET(");
    const iSetEnd = iSet >= 0 ? sm.indexOf("\nfunction ", iSet + 10) : -1;
    const setSeg = (iSet >= 0 && iSetEnd > iSet) ? sm.slice(iSet, iSetEnd) : (iSet >= 0 ? sm.slice(iSet, iSet + 2600) : "");
    if (!setSeg) bad.push("找不到 EVAL_SM_SET");
    else {
      const iPrep = setSeg.indexOf("pcall(smFitPrepare)");
      const iDef = setSeg.indexOf("smApplyDefaults()");
      if (iPrep < 0) bad.push("开启路径没有调 smFitPrepare（探测 + 自然档抓原值）");
      if (iPrep >= 0 && iDef >= 0 && iPrep > iDef) bad.push("smFitPrepare 排在 smApplyDefaults **之后** ⇒ 又变成「先缩放再记原值」（顺序铁律反了）");
      if (setSeg.indexOf("SMFIT.needFold = nil") < 0) bad.push("开启时没有重置 SMFIT.needFold ⇒ 上一轮的探测结论会一直沿用");
      if (setSeg.indexOf("pcall(featTeardown)") < 0) bad.push("关闭路径没有调 featTeardown（用户要求：开启/关闭要做好事件清理）");
    }
    // ⑥b ★★★1.75.9 真机回归（用户：「这个界面在世界地图拖拽移动功能失效」）：**收钩子必须配「再武装」** ——
    //   关闭时 Hide 了拖拽柄/坐标行，而 featBuild 有一次性守卫 ⇒ 只收不还 = 永久消失。判据两条。
    // ★1.75.9：`featRearm` 必须是**前向声明 + 赋值**（`local featRearm = nil` … `featRearm = function()`）——
    //   写成定义在后的 `local function featRearm()` 时，`featApply` 里那句 `pcall(featRearm)` 调的是全局 nil，
    //   静默不做事（组 232⑥ 实测抓到）。两条都要钉：声明在位 + 赋值形态。
    if (sm.indexOf("local featRearm = nil") < 0) bad.push("featRearm 没有前向声明（定义在 featApply 之后 ⇒ 那里 pcall 到的是全局 nil，再武装静默失效）");
    if (sm.indexOf("featRearm = function()") < 0) bad.push("没有 featRearm 的函数体（关闭时藏起来的件再也回不来 ⇒ 拖拽移动失效）");
    const iAp = sm.indexOf("local function featApply()");
    const apSeg = iAp >= 0 ? sm.slice(iAp, iAp + 900) : "";
    if (apSeg.indexOf("featRearm") < 0) bad.push("featApply 里没调 featRearm ⇒ 再开启时拖拽柄/坐标行不会回来");
    const iTd = sm.indexOf("local function featTeardown()");
    const tdSeg = iTd >= 0 ? sm.slice(iTd, iTd + 900) : "";
    if (tdSeg.indexOf("OnUpdate") >= 0 && tdSeg.indexOf(", nil)") >= 0) bad.push("featTeardown 仍把 OnUpdate 摘成 nil（摘了就装不回来；「关掉零动作」应由处理器开头的 enabled 门保证）");
    // ⑥ 缩放只许按同一档写一次 + 两道 enabled 门（滚轮 / 坐标行）
    const iScale = sm.indexOf("local function featApplyScale(");
    const iScaleEnd = iScale >= 0 ? sm.indexOf("\nend", iScale) : -1;
    const scaleSeg = (iScale >= 0 && iScaleEnd > iScale) ? sm.slice(iScale, iScaleEnd) : "";
    if (!scaleSeg) bad.push("找不到 featApplyScale");
    else if (scaleSeg.indexOf("GetScale") < 0) bad.push("featApplyScale 没有读回自证（同一档会重复写；设置累乘的客户端上就是缩两遍）");
    const iWheel = sm.indexOf("OnMouseWheel");
    const iCoords = sm.indexOf("EH_SM_COORDS");
    if (iWheel < 0 || iCoords < 0) bad.push("找不到滚轮处理器或坐标行（清理判据的锚点）");
    else {
      const wheelSeg = sm.slice(iWheel, iWheel + 700);
      if (wheelSeg.indexOf("EVAL_SM_ENABLED()") < 0) bad.push("滚轮处理器没有 enabled 门 ⇒ 关掉后滚轮还在改透明度/缩放");
      const coordsSeg = sm.slice(iCoords, iCoords + 1500);
      if (coordsSeg.indexOf("EVAL_SM_ENABLED()") < 0) bad.push("坐标行的 OnUpdate 没有 enabled 门 ⇒ 关掉后每 0.1s 还在算");
    }
    if (bad.length) { console.log("SM FIT CASCADE CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM FIT CASCADE CHECK: 折算前先探测（needFold==true 才动手）· apply 不记原值 · 原值取自自然档 · 还原不清记录 · " +
      "开启先准备后缩放 · 关闭收钩子（featTeardown）· 缩放读回自证 · 滚轮/坐标行各一道 enabled 门");
  })();
};
