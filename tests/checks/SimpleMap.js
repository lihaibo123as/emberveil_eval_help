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
                     "EVAL_SM_TEST_MAPFIT_DUMP", "EVAL_SM_TEST_MAPFIT_BUCKET"]) {
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
    // ② 原值必须**按地图分桶**存：桶头出现 ≥2（apply + capture），且绝不出现旧的平表写法
    const buckets = (sm.match(/SM_CFG\.mapFitOrig\[mk\]/g) || []).length;
    if (buckets < 2) bad.push("按地图分桶取原值只出现 " + buckets + " 处（apply 与 capture 各要一处：`SM_CFG.mapFitOrig[mk]`）");
    if (/local saved = SM_CFG\.mapFitOrig(?!\[)/.test(sm)) bad.push("仍有「平表原值」写法 `local saved = SM_CFG.mapFitOrig` ⇒ 跨图复用（本轮的根因）会回来");
    // ③ 版本戳 3（旧 schema 一律丢弃自愈）+ 迁移里真的改戳
    if (sm.indexOf("SM_CFG.mapFitVer == 3") < 0) bad.push("迁移判据不是 `mapFitVer == 3` ⇒ 旧版（跨图污染）的原值不会被丢弃（用户修好代码也照样错）");
    if (sm.indexOf("SM_CFG.mapFitVer = 3") < 0) bad.push("迁移里没有把版本戳写成 3");
    if (sm.indexOf("SM_CFG.mapFitVer = 2") >= 0 || sm.indexOf("mapFitVer == 2") >= 0) bad.push("文件里还留着版本 2 的痕迹（旧 schema 又被认成有效）");
    // ④ 换图 = 当场作废（tick 里按 smMapKey 比较后调 smFitNewMap；prepare 也要对齐）
    if (sm.indexOf("local function smFitNewMap(") < 0) bad.push("没有 smFitNewMap（换图作废内存原值）");
    else {
      const nseg = seg("local function smFitNewMap(", "\nlocal function ");
      if (nseg.indexOf("SMFIT.rec = {}") < 0) bad.push("smFitNewMap 没有丢掉旧图的内存记录（`SMFIT.rec = {}`）");
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
    if (bad.length) { console.log("SM MAP KEY CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("SM MAP KEY CHECK: 原值按**地图身份**分桶（无平表复用）· 版本戳 3 丢弃旧污染 · 换图当场作废 · " +
      "只碰本图在用的层（IsShown/GetTexture）· 零叠加层不动手 · 抓原值等版式稳定 · 还原只还写过的层 · 取证清单+命令在位");
  })();

  // ===== SM GROUP ROSTER CHECK：本模块测试文件的**组号清单**不许静默少一个（与 DF 那套同族）=====
  (function () {
    const WANT = [224, 225, 226, 230, 232, 237, 253];
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
      if (/saved\[it\.key\]\s*=/.test(applySeg)) bad.push("smFitApply 里仍在**写原值**（`saved[it.key] = …`）⇒ 又会把已折过的值当原值记下来（关一次开一次连乘）");
      if (applySeg.indexOf("SMFIT.rec[it.key] = r") < 0) bad.push("smFitApply 没有「采纳已有原值」的那条路（只有它，才不会再记）");
    }
    // ③ 抓原值必须在自然档（临时把外框缩放置 1）
    const iCap = sm.indexOf("local function smFitCapture()");
    const iCapEnd = iCap >= 0 ? sm.indexOf("\nlocal function ", iCap + 10) : -1;
    const capSeg = (iCap >= 0 && iCapEnd > iCap) ? sm.slice(iCap, iCapEnd) : "";
    if (!capSeg) bad.push("没有 smFitCapture（原值必须在自然档抓一次）");
    else if (capSeg.indexOf("SetScale, wm, 1") < 0) bad.push("smFitCapture 没有「临时把外框缩放置 1」⇒ 抓到的原值可能已经是缩过的值（读回含缩放的客户端）");
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
