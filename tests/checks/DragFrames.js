// tests/checks/DragFrames.js
// 【工具模块自带测试 · 源码检查】拖拽图层模块（tools/DragFrames.lua）。
// 用户 1.74.34：「拖拽图层模块（DragFrames）代码也排查下归类到自身文件内。」
//   ⇒ 9 道 DF/DRAG 检查从 test_engine.js 逐字搬到这里；harness 里只留一行 require+调用：
//        require("./tests/checks/DragFrames.js")(__dirname);
// ★纪律（与 tests/tools/*.lua 同族）：
//   ① 本文件**不进 toc、不随包发布**（只在测试里被 harness require）；
//   ② `module.exports = function (root)`：harness 把仓库根目录传进来，本文件内部仍照原样用 __dirname；
//   ③ 每道检查**原封不动**搬进来（逐字），不做「顺便优化」——搬完必须仍打印同样的那一行；
//   ④ 本模块专属的检查才放这里；**框架契约**（TB MOD ROW CHECK / TOOL TEST FILES CHECK 等）留在 test_engine.js。
module.exports = function (root) {
  // ★这两行必须自己 require：在原文件里 `fs`/`path` 是 test_engine.js 的**模块级常量**，
  //   搬成独立文件后它们不在作用域里（第一版就是这里当场 `ReferenceError: path is not defined`）。
  const fs = require("fs");
  const path = require("path");
  const __dirname = root;
  // ===================== DF ANCHOR ID CHECK（1.74.31）：拖拽位移**不许跨锚点口径相减** =====================
  // ===== DF ANCHOR ID CHECK（1.74.31）：拖拽位移**不许跨锚点口径相减** =====
  // 用户实测：「某些拖拽会叠加额外的偏移量（头像/目标头像/小地图）」。
  // 真因：位移 = 拖后锚点 − 基准锚点，但只比了锚点**数量**、没比**身份**（point/rel/relPoint）→ 把尺寸差当成位移。
  // 判据：模块里必须有 sameId 身份比较、且不同时走「换新基准 rec.cur」而**不做减法**；应用/复查用 rec.cur、重置仍用 rec.base。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF ANCHOR ID CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const t = fs.readFileSync(p, "utf8");
    const bad = [];
    if (!/local sameId\s*=\s*\(b0\[1\]\s*==\s*f0\[1\]\)/.test(t)) bad.push("缺少锚点身份比较 sameId");
    if (!/if\s+not\s+sameId\s+then/.test(t)) bad.push("缺少「口径不同」分支");
    if (!/rec\.cur\s*=\s*fin/.test(t)) bad.push("口径不同时没有换新基准（rec.cur = fin）");
    if (!/local bcap = rec\.cur or rec\.base/.test(t)) bad.push("应用/复查没用当前基准 rec.cur or rec.base");
    // ★1.74.33：位移落点统一走闭环 `dfPlaceFrom`（落锚→量回→按实测系数折算），所以这里两种写法都认；
    //   检查的**意图不变**：重置必须用**原始锚点** `rec.base` 还原（不是 rec.cur、也不是当前锚点）。
    if (!/df(AnchorApply|PlaceFrom)\(fr, rec\.base, 0, 0\)/.test(t)) bad.push("重置没有用原始锚点 rec.base 还原");
    if (bad.length) {
      console.log("DF ANCHOR ID CHECK: FAIL - " + bad.join(" · "));
      process.exitCode = 1;
      return;
    }
    console.log("DF ANCHOR ID CHECK: 锚点身份比较在位 · 口径不同换新基准（不相减）· 应用用 rec.cur · 重置用 rec.base");
  })();

  // ===================== DF BARS WIRING CHECK（1.74.31）：动作条1~4 的**候选名解析**接线 ===== =====================
  // ===== DF BARS WIRING CHECK（1.74.31）：动作条1~4 的**候选名解析**接线 =====
  // 为什么用源码检查：用户要求「动作条1,2,3,4 也加入可拖拽项」，而本客户端的动作条**真实帧名未知**
  //   （客户端 UI 编译在 pak 里：磁盘上没有 FrameXML、别的插件一次也没引用过 MultiBar*，本地证据只有 MainMenuBar）
  //   ⇒ 实现改成「候选名解析」。这批改动几乎全是**接线**，漏一处不报错、只是某个动作条静默拖不动：
  //   ① 解析函数 `dfTargetFrame` 必须声明在 `dfFrameOf` **之后**（Lua local 作用域从声明之后开始——
  //      写在前面会绑成全局 nil，而外面套一个 `type()=="function"` 守卫时**完全静默**；本轮第一版就是这么写的）；
  //   ② 目标循环**一律**走解析口（还有 `dfFrameOf(tgt.name)` 残留 = 动作条永远解析不到）；
  //   ③ 四个动作条目标必须带候选名表（写死一个名字 = 又回到「猜」）；
  //   ④ 柄池上限必须**由目标数派生**（写死 8 时目标已到 10，最坏情况会悄悄少贴柄）；
  //   ⑤ 命中同一帧要去重（否则同帧两条柄 + 两条存档记录互相打架）；
  //   ⑥ 探针入口要接上（`/edb bars` + 模块导出 `EVAL_DF_PROBE_BARS`），否则真名无从取证；
  //   ⑦ 面板要按**命中的真实帧名**列出（面板自己 `_G[tgt.name]` 会拿候选第一名去查 → 查不到就不列）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF BARS WIRING CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
    const joined = code.join("\n");
    const bad = [];
    const idxOf = function (needle) { for (let i = 0; i < code.length; i++) if (code[i].indexOf(needle) >= 0) return i; return -1; };
    const iFrameOf = idxOf("local function dfFrameOf(");
    const iTargetFrame = idxOf("local function dfTargetFrame(");
    if (iFrameOf < 0) bad.push("找不到 dfFrameOf");
    if (iTargetFrame < 0) bad.push("找不到 dfTargetFrame（候选名解析没了）");
    if (iFrameOf >= 0 && iTargetFrame >= 0 && iTargetFrame < iFrameOf) {
      bad.push("dfTargetFrame 声明在 dfFrameOf **之前**（会绑成全局 nil ⇒ 动作条永远解析不到，且有 type 守卫时静默）");
    }
    // ② 目标循环不许再有直接 dfFrameOf(tgt.name)
    for (let i = 0; i < code.length; i++) {
      if (/dfFrameOf\((tgt|DF_TARGETS\[)/.test(code[i])) bad.push("第 " + (i + 1) + " 行还在用 dfFrameOf(目标) —— 必须走 dfTargetFrame（否则动作条解析不到）");
    }
    // ③ 动作条目标 + 候选表
    //   ★1.74.32：队伍层拆成「队伍成员1~4」、被动打开层（图标形态）也进了目标表 ⇒ 带候选名的目标
    //     从 6 个涨到 31 个。这里改成**分类断言**（动作条 4 个必须都在且都带候选名），比数总数更抗增长。
    const barLabels = ["动作条1", "动作条2", "动作条3", "动作条4"];
    const iTargets = idxOf("local DF_TARGETS = {");
    let iTargetsEnd = -1;
    if (iTargets >= 0) { for (let i = iTargets + 1; i < code.length; i++) { if (code[i] === "}") { iTargetsEnd = i; break; } } }
    if (iTargets < 0 || iTargetsEnd < 0) bad.push("找不到 DF_TARGETS 表");
    else {
      const body = code.slice(iTargets, iTargetsEnd + 1).join("\n");
      for (const lb of barLabels) if (body.indexOf('label = "' + lb + '"') < 0) bad.push("DF_TARGETS 里没有「" + lb + "」目标");
      const nCands = (body.match(/cands = \{/g) || []).length;
      if (nCands < 6) bad.push("带候选名表的目标只有 " + nCands + " 个（至少 6：动作条1~4 + 队伍成员 + 团队层）");
    }
    // ④ 柄池上限派生
    if (!/DF_POOL_MAX\s*=\s*table\.getn\(DF_TARGETS\)/.test(joined)) bad.push("柄池上限没由目标数派生（写死值会在目标变多时悄悄少贴柄）");
    // ⑤ 去重
    if (joined.indexOf("DF_CLAIM[f]") < 0) bad.push("没有「同一帧只让一个目标认领」的去重（同帧会拿到两条柄/两条记录）");
    // ⑥ 探针 + 入口
    if (joined.indexOf("function EVAL_DF_PROBE_BARS(") < 0) bad.push("没有动作条探针 EVAL_DF_PROBE_BARS");
    if (joined.indexOf('cfg.dragBars = dump') < 0) bad.push("探针结果没落存档（dragBars）—— AI 无法读回");
    // ⑥b ★1.74.32【第 1 步：只读取证】被动打开层探针接线
    //   为什么必须源码守：本轮**故意不改行为**（候选不进 DF_TARGETS），而「不小心接进去」正是最可能出的错 ——
    //   接进去不报错、只是这些窗口突然被贴上整条透明柄；反过来「探针少扫一类」也不报错、只是取证缺一块。
    if (joined.indexOf("local DF_WIN_CANDS = {") < 0) bad.push("没有被动打开层候选清单 DF_WIN_CANDS（取证入口没了）");
    for (const lb of ["公会", "属性", "拍卖", "邮箱", "任务", "技能树"]) {
      if (joined.indexOf('label = "' + lb + '"') < 0) bad.push("DF_WIN_CANDS 里缺用户点名的「" + lb + "」");
    }
    for (const kw of ['"guild"', '"paperdoll"', '"auction"', '"mail"', '"quest"', '"spellbook"', '"trainer"', '"tradeskill"', '"merchant"', '"friend"']) {
      if (joined.indexOf("string.find(s, " + kw) < 0) bad.push("dfFrameLikeGroup 缺关键词 " + kw + "（该组窗口永远扫不到）");
    }
    // ★★临时哨兵**已按计划撤除**（1.74.32 第 2 步）：第 1 步要求「被动层候选不许进 DF_TARGETS」，
    //   第 2 步（图标形态）正是要把探到的真名接进去 ⇒ 改成**反向**守「探到的真名确实接进去了」：
    //   用户点名的 6 类在 DF_TARGETS 里必须各有 `icon = true` 的目标（否则图标形态少做一类还不报错）。
    {
      const iT = idxOf("local DF_TARGETS = {");
      let iE = -1;
      if (iT >= 0) for (let i = iT + 1; i < code.length; i++) { if (code[i] === "}") { iE = i; break; } }
      if (iT < 0 || iE < 0) bad.push("找不到 DF_TARGETS 表");
      else {
        const tBody = code.slice(iT, iE + 1).join("\n");
        for (const lb of ["公会", "属性", "邮箱", "任务", "技能树", "交易技能", "商人", "好友", "银行"]) {
          const re = new RegExp('label = "' + lb + '"[^\\n]*icon = true');
          if (!re.test(tBody)) bad.push("DF_TARGETS 里缺带 `icon = true` 的「" + lb + "」（被动窗口图标形态少一类）");
        }
        if ((tBody.match(/icon = true/g) || []).length < 20) {
          bad.push("带 `icon = true` 的目标少于 20 个（用户选了 A+B+C：点名 6 类 + 附赠 4 类 + 标准窗口一族）");
        }
      }
    }
    // ⑥c 顶层大帧兜底的筛选必须**按对象身份**判（按父级名字判在桩/真机上都可能全空 —— 本轮实测踩到）
    if (joined.indexOf("local function dfTopHost(") < 0) bad.push("没有 dfTopHost（顶层大帧兜底的宿主判定）");
    else if (joined.indexOf('p == rawget(_G, "UIParent")') < 0 || joined.indexOf('p == rawget(_G, "WorldFrame")') < 0) {
      bad.push("dfTopHost 没按**对象身份**判宿主（按 GetName 判会一个都匹配不上）");
    }
    if (joined.indexOf("dump.top") < 0 || joined.indexOf("dump.cands") < 0) {
      bad.push("探针没把被动层结果落存档（cands / top）");
    }
    const sub = path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua");
    if (fs.existsSync(sub)) {
      const sc = fs.readFileSync(sub, "utf8").split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
      if (sc.indexOf('msg == "bars"') < 0) bad.push("子插件没接 /edb bars 命令（真名无从取证）");
      if (sc.indexOf("EVAL_DF_PROBE_BARS") < 0) bad.push("子插件没转发到 EVAL_DF_PROBE_BARS");
      // ⑦ 面板按命中帧名列（不许自己 _G[tgt.name]）
      if (/local fr = _G\[tgt\.name\]/.test(sc)) bad.push("面板还在自己 _G[tgt.name] 查帧（候选解析后名字可能不同 ⇒ 该目标不列）");
      if (sc.indexOf("tgt.frame or _G[tgt.name]") < 0) bad.push("面板没用模块交出来的 frame（应 `tgt.frame or _G[tgt.name]`）");
    } else {
      bad.push("找不到子插件文件");
    }
    if (bad.length) {
      console.log("DF BARS WIRING CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF BARS WIRING CHECK: dfTargetFrame 在 dfFrameOf 之后 · 目标循环全走解析口 · 4 个动作条各带候选名 · " +
      "柄池上限派生 · 撞同帧去重 · 探针与 /edb bars 已接 · 面板按命中帧名列");
  })();


  // ===================== DF ROSTER WIRING CHECK（1.74.32）：队伍层/团队层「按需出现」的跟随接线 ===== =====================
  // ===== DF ROSTER WIRING CHECK（1.74.32）：队伍层/团队层「按需出现」的跟随接线 =====
  // 为什么用源码检查：用户要求「拖拽图层再增加队伍层,团队层如果存在的话」。这两个目标**不是常驻帧**
  //   （单人时客户端不建/不显示队伍框），所以除候选名解析外还多一套「事件到了就补上」的接线。
  //   这批改动全是接线，漏一处**不报错、只是永远不出现或永远不生效**：
  //   ① `dfRosterArm` 必须**前向声明**在 `dfRosterEnsure` 之前（OnEvent 闭包里引用后声明的 local
  //      → 绑成全局 nil，而外面套 `type(...)=="function"` 守卫 ⇒ 事件来了静默什么都不做）；
  //   ② 两个目标必须带 `roster = true` + `cands`（roster 标记是「只碰这两个」的唯一依据）；
  //   ③ 注册的事件名**只许是已有本地证据的三个**（Toolbox.lua 在跑 PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE，
  //      PLAYER_ENTERING_WORLD 全项目在用）；★`GROUP_ROSTER_UPDATE` 只出现在子插件的**事件探测名单**里
  //      （拿 IsEventRegistered 逐个试的清单）——把探测名单当注册依据 = 猜事件名，**必须 FAIL**；
  //   ④ 跟随必须**有界**（事件后跟固定次数即停），且开关关掉时清零 —— 不许变成常驻后台周期任务；
  //   ⑤ INSTALL 与「本次会话刚把开关打开」两条路径都要接上（漏一条 = 那条路径下永远不补帧）；
  //   ⑥ 结算必须走**已有的** `dfApplyOne`（应用公式只许有一处，另写一套 = 两处真值打架）；
  //   ⑦ 探针要**先报组队状态**（GetNumPartyMembers / GetNumRaidMembers）并扫 party/raid 关键词 ——
  //      否则「候选全不在」在单人时无法与「帧名不对」区分（取证结论会错）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF ROSTER WIRING CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
    const joined = code.join("\n");
    const bad = [];
    const idxOf = function (needle) { for (let i = 0; i < code.length; i++) if (code[i].indexOf(needle) >= 0) return i; return -1; };
    // ① 前向声明在 dfRosterEnsure 之前
    const iDecl = idxOf("local dfRosterArm");
    const iEnsure = idxOf("local function dfRosterEnsure(");
    if (iDecl < 0) bad.push("没有 `local dfRosterArm` 前向声明（OnEvent 闭包会绑成全局 nil ⇒ 事件静默无效）");
    if (iEnsure < 0) bad.push("找不到 dfRosterEnsure（事件帧没建）");
    if (iDecl >= 0 && iEnsure >= 0 && iDecl > iEnsure) {
      bad.push("dfRosterArm 的前向声明在 dfRosterEnsure **之后**（闭包会绑全局 nil + type 守卫 ⇒ 整条静默）");
    }
    if (!/dfRosterArm\s*=\s*function/.test(joined)) bad.push("dfRosterArm 没有赋值点（前向声明的那个 local 一直是 nil）");
    // ② 目标带 roster + cands
    //   ★1.74.32 真机取证后改：本客户端**没有整队容器帧**（探针里 PartyFrame 一族全部「不在」），
    //     队伍就是 `PartyMemberFrame1~4` 四个独立帧 ⇒ 用户决定拆成「队伍成员1~4」+ 团队层 = **5 个** roster 目标。
    const iTargets = idxOf("local DF_TARGETS = {");
    let iTargetsEnd = -1;
    if (iTargets >= 0) { for (let i = iTargets + 1; i < code.length; i++) { if (code[i] === "}") { iTargetsEnd = i; break; } } }
    if (iTargets < 0 || iTargetsEnd < 0) bad.push("找不到 DF_TARGETS 表");
    else {
      const body = code.slice(iTargets, iTargetsEnd + 1).join("\n");
      for (const lb of ["队伍成员1", "队伍成员2", "队伍成员3", "队伍成员4", "团队层"]) {
        if (body.indexOf('label = "' + lb + '"') < 0) bad.push("DF_TARGETS 里没有「" + lb + "」目标");
      }
      const nRoster = (body.match(/roster = true/g) || []).length;
      if (nRoster !== 5) bad.push("带 `roster = true` 的目标有 " + nRoster + " 个（应恰好 5：队伍成员1~4 + 团队层）");
    }
    // ③ 事件名（只许有本地证据的；探测名单里的名字不许当注册依据）
    for (const ev of ["PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD"]) {
      if (joined.indexOf('"' + ev + '"') < 0) bad.push("注册名单里缺 " + ev + "（有本地证据的事件，别漏）");
    }
    if (joined.indexOf("GROUP_ROSTER_UPDATE") >= 0) {
      bad.push("出现了 GROUP_ROSTER_UPDATE —— 它只在子插件的事件**探测名单**里，没有本地证据 ⇒ 不许当注册依据（铁律 5④）");
    }
    if (joined.indexOf("RegisterEvent") < 0) bad.push("没在注册任何事件（跟随永远不会被触发）");
    // ④ 有界 + 关闭清零（★清零必须锚在 EVAL_DF_SET 体内：测试读值口里也有 `DF.rosterLeft = 0`，
    //   全文搜一遍会被那句「假绿」骗过去）
    if (!/DF\.rosterLeft\s*=\s*DF_ROSTER_TRIES/.test(joined)) bad.push("跟随没设次数上限（会变成常驻后台任务）");
    const iSet = idxOf("function EVAL_DF_SET(");
    if (iSet < 0) bad.push("找不到 EVAL_DF_SET（开关唯一入口）");
    else {
      let end = -1;
      for (let i = iSet + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      const body = code.slice(iSet, end + 1).join("\n");
      if (!/DF\.rosterLeft\s*=\s*0/.test(body)) bad.push("EVAL_DF_SET 里没把跟随清零（关掉开关后事件仍在跟 = 没人叫停的后台任务）");
    }
    // ⑤ 两条武装路径
    if (joined.indexOf('dfRosterArm("install")') < 0) bad.push("INSTALL 没接 dfRosterArm（登录时队伍/团队帧永远不补）");
    if (joined.indexOf('dfRosterArm("enable")') < 0) bad.push("开关打开那条路径没接 dfRosterArm（本次会话刚开开关时不补帧）");
    // ⑥ 结算走 dfApplyOne（应用公式只许一处）
    const iPass = idxOf("local function dfRosterPass(");
    if (iPass < 0) bad.push("找不到 dfRosterPass");
    else {
      let end = -1;
      for (let i = iPass + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      const body = code.slice(iPass, end + 1).join("\n");
      if (body.indexOf("dfApplyOne(") < 0) bad.push("dfRosterPass 没走 dfApplyOne（另写一套应用公式 = 两处真值打架）");
      if (body.indexOf("dfRefresh") < 0) bad.push("dfRosterPass 没重贴拖拽柄（目标在手、柄不出现）");
    }
    if (!/local function dfApplyOne\(/.test(joined)) bad.push("没有 dfApplyOne（出现即恢复存档参数的唯一入口）");
    // ⑦ 探针先报组队状态 + 扫 party/raid
    const iProbe = idxOf("function EVAL_DF_PROBE_BARS(");
    if (iProbe < 0) bad.push("找不到探针 EVAL_DF_PROBE_BARS");
    else {
      let end = -1;
      for (let i = iProbe + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      const body = code.slice(iProbe, end + 1).join("\n");
      if (body.indexOf("dfRosterCounts") < 0) {
        bad.push("探针没报组队状态（应调 dfRosterCounts）—— 单人时「候选全不在」无法与「帧名不对」区分");
      }
      if (body.indexOf("partyMembers") < 0 || body.indexOf("raidMembers") < 0) bad.push("探针没把组队状态落存档");
    }
    //   组队数由 dfRosterCounts 现读（两个接口都要 pcall 包，不许直接裸调）
    const iCnt = idxOf("local function dfRosterCounts(");
    if (iCnt < 0) bad.push("没有 dfRosterCounts（组队状态没处读）");
    else {
      let end = -1;
      for (let i = iCnt + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      const body = code.slice(iCnt, end + 1).join("\n");
      if (body.indexOf("GetNumPartyMembers") < 0) bad.push("dfRosterCounts 没读 GetNumPartyMembers");
      if (body.indexOf("GetNumRaidMembers") < 0) bad.push("dfRosterCounts 没读 GetNumRaidMembers");
      if (body.indexOf("pcall") < 0) bad.push("dfRosterCounts 没把客户端调用包在 pcall 里（真机缺接口会抛）");
    }
    if (joined.indexOf('string.find(s, "party"') < 0 || joined.indexOf('string.find(s, "raid"') < 0) {
      bad.push("全 _G 扫描没覆盖 party/raid 关键词（队伍/团队真名无从取证）");
    }
    if (bad.length) {
      console.log("DF ROSTER WIRING CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF ROSTER WIRING CHECK: 前向声明在 ensure 之前 · 队伍/团队各带 roster+cands · " +
      "只注册有证据的 3 个事件 · 跟随有界且关闭清零 · install/enable 双路径已接 · 结算走 dfApplyOne · 探针报组队状态");
  })();


  // ===================== DF OPEN HOOK CHECK（1.74.33）：方案 A/C 的四条**源码级**契约 ===== =====================
  // ===== DF OPEN HOOK CHECK（1.74.33）：方案 A/C 的四条**源码级**契约 =====
  // 1.74.33 用户拍板「被动窗口不能设置宽度（会撕裂内部布局）」+「A+C 实施」。行为断言（组 220）能照到绝大多数，
  //   但有两类**接线**照不到、而且错了不报错，只能用源码检查补位：
  //   ① **链式顺序**：OnShow 包装里必须**先调原生脚本**再干自己的事（覆盖式接管 = 直接破坏客户端自己的开窗逻辑，
  //      而 21/23 个被动窗口原生都有 OnShow —— 第一轮真机取证 R15 ⑥d 量出来的事实）；
  //   ② **宽高门**：`dfAttrsApply` 里 `allowSize` 必须真的守在两处 `SetWidth/SetHeight` 上（少守一处就回到撕裂）；
  //   ③ **卸链**：关掉功能/取消勾选要把 OnShow **还回原生那一个**（否则功能关了钩子还在）；
  //   ④ **C 有界**：到点必须**摘脚本**（隐藏帧的 OnUpdate 照样触发 ⇒ 只 Hide = 永远空转）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF OPEN HOOK CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
    const bad = [];
    const idxOf = function (needle) { for (let i = 0; i < code.length; i++) if (code[i].indexOf(needle) >= 0) return i; return -1; };
    // 取函数体：从声明行往下找到「同缩进或更浅的 end」为止（本项目体量下够用）
    const bodyOf = function (iStart) {
      if (iStart < 0) return "";
      for (let i = iStart + 1; i < code.length; i++) {
        // ★必须是**列 0 的 end**：缩进的 end 是内层 if/for 的收尾，用它截断会把函数体切半（第一版就因此报了一串假 FAIL）
        if (/^(end|end\))\s*$/.test(code[i])) return code.slice(iStart, i + 1).join("\n");
      }
      return code.slice(iStart).join("\n");
    };
    const joined = code.join("\n");

    // ① 链式顺序
    const iBoss = idxOf("local function dfOnShowBoss(");
    if (iBoss < 0) bad.push("找不到 OnShow 包装 dfOnShowBoss（方案 A 没装上？）");
    else {
      const body = bodyOf(iBoss);
      const iOrig = body.indexOf("pcall(orig, self)");
      const iMine = body.indexOf("dfApplyOne(tgt)");
      if (iOrig < 0) bad.push("dfOnShowBoss 里没有 pcall(orig, self) —— 原生 OnShow 没被链式调用（覆盖式接管！）");
      else if (iMine >= 0 && iOrig > iMine) bad.push("dfOnShowBoss 先干了自己的事才调原生脚本（顺序反了）");
      if (body.indexOf("dfOpenArm(tgt)") < 0) bad.push("dfOnShowBoss 没武装 C（开窗后短复查）");
    }
    // ② 装链必须先存原脚本
    const iEns = idxOf("local function dfOpenHookEnsure(");
    if (iEns < 0) bad.push("找不到 dfOpenHookEnsure（没法装链）");
    else {
      const body = bodyOf(iEns);
      if (body.indexOf("fr.GetScript, fr") < 0) bad.push("装链前没 GetScript 读原脚本");
      if (body.indexOf("DF.onShowOrig[fr] = cur") < 0) bad.push("没把原脚本存进 DF.onShowOrig（链断了就还不回去）");
      if (body.indexOf('"OnShow", DF.onShowBoss') < 0) bad.push("没把我们的链装上 OnShow");
    }
    // ③ 卸链
    const iRem = idxOf("local function dfOpenHookRemove(");
    if (iRem < 0) bad.push("找不到 dfOpenHookRemove（关掉功能后钩子摘不掉）");
    else if (bodyOf(iRem).indexOf('"OnShow", orig') < 0) bad.push("卸链没把 OnShow 还回原生那一个（orig）");
    // ④ 宽高门（★1.75.1 口径反转：**只有聊天窗**能改宽高 + 持久化；唯一真值 = dfSizeOK）
    const dfSrc = fs.readFileSync(path.join(__dirname, "tools", "DragFrames.lua"), "utf8");
    const iAttrs = idxOf("local function dfAttrsApply(");
    if (iAttrs < 0) bad.push("找不到 dfAttrsApply");
    else {
      const body = bodyOf(iAttrs);
      if (body.indexOf("local allowSize") < 0 || body.indexOf("tgt.noSize") < 0) {
        bad.push("dfAttrsApply 的 allowSize 门没接目标表项的 noSize（宽高又会无差别被写 ⇒ 撕裂回来）");
      }
      if (body.indexOf("if allowSize and type(rec.w)") < 0) bad.push("宽度写入没被 allowSize 守住");
      if (body.indexOf("if allowSize and type(rec.h)") < 0) bad.push("高度写入没被 allowSize 守住");
    }
    // ★「哪些名字算聊天窗」必须只有一处真值：dfSizeOK + DF_SIZE_PAT，且正则只许出现一次
    if (dfSrc.indexOf("local function dfSizeOK(") < 0) bad.push("没有 dfSizeOK（白名单唯一真值）");
    if (dfSrc.indexOf('local DF_SIZE_PAT = "^ChatFrame%d+$"') < 0) bad.push("没有聊天窗白名单 DF_SIZE_PAT");
    const chatHits = (dfSrc.match(/ChatFrame%d\+/g) || []).length;
    if (chatHits !== 1) bad.push("聊天窗白名单正则出现 " + chatHits + " 次（唯一真值，必须恰好 1 次）");
    if (dfSrc.indexOf("DF_TARGETS[i].noSize = not dfSizeOK(") < 0) bad.push("目标表没按 dfSizeOK 挂 noSize（读值口/判据要读它）");
    if (dfSrc.indexOf("local DF_NO_SIZE = true") >= 0) bad.push("又出现了旧真值 DF_NO_SIZE（口径已改成「只给聊天窗」）");
    if (dfSrc.indexOf('addRow(-174, "w"') < 0 || dfSrc.indexOf('addRow(-202, "h"') < 0) bad.push("属性弹窗缺宽/高两行（聊天窗要给这两行）");
    if (dfSrc.indexOf("local DF_POP_H_SIZE = DF_POP_H + 56") < 0) bad.push("聊天窗弹窗没有加高常量（宽/高两行会压到底部按钮上）");
    if (dfSrc.indexOf("pcall(p.root.SetHeight, p.root, allowSize and DF_POP_H_SIZE or DF_POP_H)") < 0) {
      bad.push("弹窗没按目标能力切窗高（非聊天窗会留两块空行）");
    }
    if (dfSrc.indexOf("if allowSize then pcall(c.Show, c) else pcall(c.Hide, c) end") < 0) {
      bad.push("宽/高两行没按目标能力显隐（建了不藏 = 非聊天窗也能点到）");
    }
    // ★持久化：只对允许的目标入库；不许改宽高的目标要走「自愈清掉」那一支
    if (dfSrc.indexOf("if p2.allowSize then") < 0 || dfSrc.indexOf("if vW then rec.w = vW end") < 0) {
      bad.push("聊天窗宽高没入库（用户要的「并且持久化」落不了地）");
    }
    // ★顺序哨兵（1.74.31 的教训）：抓原始值必须在 SetWidth **之前**
    const iCap = dfSrc.indexOf("rec0.ow = curW");
    const iSetW = dfSrc.indexOf("pcall(tgt.SetWidth, tgt, vW)");
    if (iCap < 0 || iSetW < 0 || iCap > iSetW) bad.push("抓原始值的顺序不对（写在 SetWidth 之后 = 记下的是新值，重置等于没还原）");
    // 清理必须**只清不许改宽高的目标**：聊天窗的 w/h 是持久化数据
    const iClean = idxOf("function EVAL_DF_SIZE_CLEAN(");
    if (iClean < 0) bad.push("没有老记录宽高清理（撕裂会一直跟着老用户）");
    else if (bodyOf(iClean).indexOf("tgt.noSize == true and type(rec)") < 0) {
      bad.push("宽高清理没按 noSize 过滤（会把聊天窗要持久化的宽高一起清掉）");
    }
    // ⑥ X/Y 坐标（用户第二次澄清要的就是它）：两行必须在、必须带 [−][+] 微调按钮、落锚必须走 dfPlaceFrom
    if (joined.indexOf("addXYRow(-118, \"x\", DF_X_PRESETS)") < 0
      || joined.indexOf("addXYRow(-146, \"y\", DF_Y_PRESETS)") < 0) {
      bad.push("缺少 X/Y 两行（用户明确：属性配置要支持调整的是窗口的 x,y 坐标值）");
    }
    if (joined.indexOf("row.nudgeMinus = nudgeBtn(") < 0 || joined.indexOf("row.nudgePlus = nudgeBtn(") < 0) {
      bad.push("X/Y 行缺少 [−][+] 微调按钮（用户选定的控件形式）");
    }
    if (joined.indexOf("local DF_XY_NUDGE_FINE = 1") < 0) bad.push("微调没有精调档（Shift ±1）");
    if (joined.indexOf("dfPlaceFrom(tgt, bXY, recXY.dx, recXY.dy)") < 0) {
      bad.push("X/Y 落锚没走 dfPlaceFrom（直接把绝对坐标当本地偏移 SetPoint 会偏 —— 上一轮真机栽过的老坑）");
    }
    // ⑤ C 有界 + 摘脚本
    const iStop = idxOf("local function dfOpenStop(");
    if (iStop < 0) bad.push("找不到 dfOpenStop（C 停不下来）");
    else if (bodyOf(iStop).indexOf('"OnUpdate", nil') < 0) bad.push("C 停的时候没摘 OnUpdate 脚本（隐藏帧的 OnUpdate 照样触发 ⇒ 永远空转）");
    if (joined.indexOf("local DF_OPEN_WALL = ") < 0) bad.push("C 没有绝对墙钟上限（可能停不下来）");
    if (bad.length) {
      console.log("DF OPEN HOOK CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF OPEN HOOK CHECK: A 链式（先调原生 · 装链存原脚本 · 卸链还原）· 宽高门 allowSize · 清理入口 · C 有界并摘脚本 · X/Y 两行与 [−][+] 微调 · X/Y 走 dfPlaceFrom");
  })();


  // ===================== DF PROBE SAFE CHECK（1.74.32）：取证命令**绝不许静默** ===== =====================
  // ===== DF PROBE SAFE CHECK（1.74.32）：取证命令**绝不许静默** =====
  // 真机踩到的实案：用户跑了 `/edb bars`，存档里**连 dragBars 键都没有** —— 子插件那句
  //   `pcall(EVAL_DF_PROBE_BARS)` 把内部错误吞掉了 ⇒ 既没报错也没痕迹，
  //   无法区分「命令压根没跑」与「跑了一半死了」（本项目最恨的静默失败族；当时是靠「只有 EvalHelp/UnrealQuest
  //   的存档被写、EH_DebugBox 的停在 17:28」这条旁证才定位到子插件可能没载入）。
  // 判据（三条契约，缺一条下次真机又会卡住）：
  //   ① 探针一进来就写阶段标记（start）· 跑完写 phase="done" ⇒ 三态可区分（start/error/done）；
  //   ② 安全入口 `EVAL_DF_PROBE_SAFE` 用 pcall 包住本体，失败时把错误原文**播报 + 落档**；
  //   ③ **两个入口**（主插件 `/eh go 框体探针`、子插件 `/edb bars`）都走 SAFE；不许再出现**裸 pcall**（吞错误）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF PROBE SAFE CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
    const joined = code.join("\n");
    const bad = [];
    const idxOf = function (needle) { for (let i = 0; i < code.length; i++) if (code[i].indexOf(needle) >= 0) return i; return -1; };
    const bodyOf = function (iStart) {
      if (iStart < 0) return "";
      let end = -1;
      for (let i = iStart + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      return code.slice(iStart, end + 1).join("\n");
    };
    // ① 阶段标记
    if (!/function EVAL_DF_PROBE_MARK\(/.test(joined)) bad.push("没有 EVAL_DF_PROBE_MARK（阶段标记口没了 ⇒ 半路死掉无痕）");
    const iProbe = idxOf("function EVAL_DF_PROBE_BARS(");
    if (iProbe < 0) bad.push("找不到探针本体 EVAL_DF_PROBE_BARS");
    else {
      // ★锚在**函数体内**而不是全文：全文搜会被 SAFE 里那句 MARK("start") 骗过去（那样就少了一层痕迹）
      const body = bodyOf(iProbe);
      if (body.indexOf('EVAL_DF_PROBE_MARK("start")') < 0) {
        bad.push("探针本体内没有开头标记 EVAL_DF_PROBE_MARK(\"start\")（只有 SAFE 里那句不够：直调本体时就没痕迹了）");
      }
      if (body.indexOf('dump.phase = "done"') < 0) bad.push("探针跑完没写 phase=\"done\"（三态少一态）");
    }
    // ①b ★1.74.33 开窗探针（第二个取证入口）同样守这三条 —— 新探针最容易漏的恰恰是「半路死掉无痕」：
    //   本体内 start 标记 + 结束写 phase="done"（三态齐全）、跑在 OnUpdate 里的那一步必须**被 pcall 包住**
    //   （OnUpdate 里抛错会每帧刷屏，而且刷屏会掩盖真正的原因 ⇒ 必须自己停 + 错误原文落档）。
    const iAttr = idxOf("function EVAL_DF_PROBE_ATTR(");
    if (iAttr < 0) bad.push("找不到开窗探针本体 EVAL_DF_PROBE_ATTR");
    else {
      const body = bodyOf(iAttr);
      if (body.indexOf('EVAL_DF_PROBE_MARK("start"') < 0) bad.push("开窗探针本体内没有开头标记（三态少一态）");
    }
    const iAttrTick = idxOf("local function dfAttrPOnUpdate(");
    if (iAttrTick < 0) bad.push("找不到开窗探针的心跳 dfAttrPOnUpdate");
    else {
      const body = bodyOf(iAttrTick);
      if (body.indexOf("pcall(dfAttrPStep") < 0) bad.push("开窗探针心跳没把步进体包 pcall（OnUpdate 抛错会每帧刷屏）");
      if (body.indexOf("dfAttrPStop(\"error\")") < 0) bad.push("开窗探针心跳出错时没停（会一直刷屏）");
    }
    const iAttrWrite = idxOf("local function dfAttrPWrite(");
    if (iAttrWrite < 0) bad.push("找不到开窗探针的落档口 dfAttrPWrite");
    else {
      const body = bodyOf(iAttrWrite);
      if (body.indexOf('phase = "done"') < 0) bad.push("开窗探针落档没写 phase=\"done\"");
      if (body.indexOf("cfg.dragAttr = dump") < 0) bad.push("开窗探针落档没落到 cfg.dragAttr（读的人找不到）");
    }
    // ② 安全入口
    const iSafe = idxOf("function EVAL_DF_PROBE_SAFE(");
    if (iSafe < 0) bad.push("没有安全入口 EVAL_DF_PROBE_SAFE");
    else {
      const body = bodyOf(iSafe);
      if (!/pcall\(EVAL_DF_PROBE_BARS\)/.test(body)) bad.push("EVAL_DF_PROBE_SAFE 没用 pcall 包住探针本体");
      if (body.indexOf('EVAL_DF_PROBE_MARK("error"') < 0) bad.push("EVAL_DF_PROBE_SAFE 失败时没落错误阶段（错误无痕）");
      if (body.indexOf("err") < 0) bad.push("EVAL_DF_PROBE_SAFE 没把错误原文交出来");
    }
    // ③ 两个入口都走 SAFE，且不许有裸 pcall
    //   ★★判据要锚「**走到**它」而不是「名字出现过」（变异 M3/M4 的教训）：把 `if type(X)=="function"` 改成
    //     `if false then` 时，调用语句还在源码里 —— 只搜名字会**假绿**。所以直接钉那行**守卫**。
    const SAFE_GUARD = 'if type(EVAL_DF_PROBE_SAFE) == "function" then';
    const main = path.join(__dirname, "EvalHelp.lua");
    if (fs.existsSync(main)) {
      const mRaw = fs.readFileSync(main, "utf8").split(/\r?\n/);
      const mc = mRaw.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
      const mi = mc.findIndex(function (l) { return l.indexOf('msg == "go 框体探针"') >= 0; });
      if (mi < 0) bad.push("主插件没有 `/eh go 框体探针` 入口（子插件没载入时就没路可走）");
      else {
        let me = mc.length - 1;
        for (let i = mi + 1; i < mc.length; i++) { if (mc[i].indexOf("elseif ") >= 0 && mc[i].indexOf("msg ==") >= 0) { me = i; break; } }
        const branch = mc.slice(mi, me).join("\n");
        if (branch.indexOf(SAFE_GUARD) < 0) bad.push("主插件 `go 框体探针` 分支没走 SAFE（缺守卫行 `" + SAFE_GUARD + "`）");
        if (!/EVAL_DF_PROBE_SAFE\(\)/.test(branch)) bad.push("主插件分支里没有真正调用 EVAL_DF_PROBE_SAFE()");
      }
    } else bad.push("找不到主插件 EvalHelp.lua");
    const sub = path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua");
    if (fs.existsSync(sub)) {
      const sLines = fs.readFileSync(sub, "utf8").split(/\r?\n/);
      const sc = sLines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
      const sj = sc.join("\n");
      if (sj.indexOf(SAFE_GUARD) < 0) bad.push("子插件 `/edb bars` 没走 SAFE（缺守卫行 `" + SAFE_GUARD + "`）");
      if (!/EVAL_DF_PROBE_SAFE\(\)/.test(sj)) bad.push("子插件里没有真正调用 EVAL_DF_PROBE_SAFE()");
      for (let i = 0; i < sc.length; i++) {
        if (/^\s*pcall\(EVAL_DF_PROBE_BARS\)\s*$/.test(sc[i])) {
          bad.push("第 " + (i + 1) + " 行是**裸 pcall**（吞错误、不留痕）—— 必须接 ok/err 并落档");
        }
      }
    } else bad.push("找不到子插件文件");
    if (bad.length) {
      console.log("DF PROBE SAFE CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF PROBE SAFE CHECK: 三态阶段标记（start/done/error）· 安全入口 pcall + 错误原文落档 · " +
      "主插件与子插件两个入口都走 SAFE · 无裸 pcall");
  })();


  // ===================== DF GLOBAL SCAN GUARD CHECK（1.74.32）：全 `_G` 扫描必须先过「能不能当帧用」的守卫 ===== =====================
  // ===== DF GLOBAL SCAN GUARD CHECK（1.74.32）：全 `_G` 扫描必须先过「能不能当帧用」的守卫 =====
  // 真机实案（用户截图，探针被当场打断、什么都没留下）：
  //   `DragFrames.lua:2003: attempt to index local 'f' (a userdata value)`
  //   —— `_G` 里有些全局是**不可索引的 userdata**（不是帧、也没有方法元表），一句 `f.GetParent` 就抛错。
  // ★为什么必须用源码检查：这个 bug 在测试环境里**造不出来** —— fengari 没有 `newproxy`，而 `io.stdout`
  //   那种 userdata 是可索引的；number/boolean/function 虽然索引会报错，却过不了 `dfFrameOf` 的类型门
  //   （它只放 table/userdata 过去）⇒ 行为断言**结构上照不到**这条路径（组 211 只能钉守卫的判定语义）。
  // 判据：
  //   ① `dfFrameUsable` 存在，且对 userdata **必须用 pcall 探测**（不许裸索引）；
  //   ② 两处 `_G` 扫描（关键词扫 / 顶层大帧扫）命中全局后都必须先过 `dfFrameUsable`；
  //   ③ `dfTopHost` 自己也要过守卫（它是被全扫描调用的，裸 `f.GetParent` 正是那行报错）；
  //   ④ 顶层大帧扫描只收字符串键（非字符串键 + table.sort 混排会抛错）；
  //   ⑤ ★「判不出类型不许丢」：`dfObjectType` 返回 nil 时必须**保留**该条目（查不到 ≠ 没有）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF GLOBAL SCAN GUARD CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
    const joined = code.join("\n");
    const bad = [];
    const idxOf = function (needle) { for (let i = 0; i < code.length; i++) if (code[i].indexOf(needle) >= 0) return i; return -1; };
    const bodyOf = function (iStart) {
      if (iStart < 0) return "";
      let end = -1;
      for (let i = iStart + 1; i < code.length; i++) { if (code[i] === "end") { end = i; break; } }
      return code.slice(iStart, end + 1).join("\n");
    };
    // ① 守卫本身
    const iFu = idxOf("local function dfFrameUsable(");
    if (iFu < 0) bad.push("没有 dfFrameUsable（全 _G 扫描的守卫没了 ⇒ 又会栽在不可索引的 userdata 上）");
    else {
      const body = bodyOf(iFu);
      if (body.indexOf("pcall(") < 0) bad.push("dfFrameUsable 没对 userdata 用 pcall 探测（裸索引会抛错）");
      if (body.indexOf('type(f) ~= "userdata"') < 0) bad.push("dfFrameUsable 没有 userdata 分支");
      if (body.indexOf('type(f) == "table"') < 0) bad.push("dfFrameUsable 丢了 table 分支（stub 帧/部分真机帧是表）");
    }
    // ② 两处扫描都过守卫
    const iProbe = idxOf("function EVAL_DF_PROBE_BARS(");
    if (iProbe < 0) bad.push("找不到探针本体");
    else {
      const body = bodyOf(iProbe);
      const nGuard = (body.match(/dfFrameUsable\(f\)/g) || []).length;
      if (nGuard < 2) bad.push("探针里只有 " + nGuard + " 处 `dfFrameUsable(f)` —— 两处全 _G 扫描（关键词扫 / 顶层大帧扫）都要过守卫");
      if (body.indexOf('type(k) == "string"') < 0) bad.push("顶层大帧扫描没收「只收字符串键」（非字符串键与 table.sort 混排会抛错）");
      if (body.indexOf('ot == nil or ot == "Frame"') < 0) {
        bad.push("顶层大帧扫描没做到「判不出类型时不许丢」（缺 `ot == nil or ot == \"Frame\"`）");
      }
      if (body.indexOf('ot ~= nil and ot ~= "Frame"') < 0) bad.push("关键词扫描没把非帧子件滤掉（真机上 3000+ 同名贴图会灌爆存档）");
    }
    // ③ dfTopHost 自己也要过守卫（那行报错就在它里面）
    const iTop = idxOf("local function dfTopHost(");
    if (iTop < 0) bad.push("没有 dfTopHost");
    else {
      const body = bodyOf(iTop);
      if (body.indexOf("dfFrameUsable(f)") < 0) bad.push("dfTopHost 没过守卫（裸 `f.GetParent` 就是真机报错那一行）");
    }
    // ④ 对象类型口：拿不到要么 pcall 保护
    const iOt = idxOf("local function dfObjectType(");
    if (iOt < 0) bad.push("没有 dfObjectType");
    else if (bodyOf(iOt).indexOf("pcall(") < 0) bad.push("dfObjectType 没走 pcall（拿不到类型时会抛）");
    // ⑤ ★★匿名窗口父子链取证（1.74.32）：`_G` 扫描看不见没有名字的窗口，只能靠 `GetChildren` 走。
    //   三个必须钉住的点（全是「不报错只是结果空/少」那种静默错）：
    //     ① `GetChildren()` 返回的是**多值不是表** ⇒ 必须 `{ pcall(...) }` 再遍历；
    //        写成 `local kids = fr:GetChildren()` 只会拿到**第一个**子件（静默少数据，本项目最恨那类）；
    //     ② 「像窗口」必须**宽高都 ≥200**（只用一个维度会被聊天框/条状件占满，真窗口反被上限挤掉 —— 实测过）；
    //     ③ 必须排除**满屏家具帧**（1228.8×768 = UIParent 尺寸的事件帧/遮罩），且阈值要**现算相对量**、不许写死。
    if (joined.indexOf("local function dfKidWalk(") < 0) bad.push("没有匿名窗口父子链遍历 dfKidWalk");
    if (joined.indexOf("local function dfKidNames(") < 0) bad.push("没有「具名子件当指纹」的 dfKidNames");
    //   ★★锚必须落在**各自的函数体内**：这两个函数都用 `{ pcall(GetChildren) }`，
    //     全文搜一次会被另一个函数命中 ⇒ 变异跑掉也看不出来（本轮实测：M1 就是这么漏的）。
    const iWalk = idxOf("local function dfKidWalk(");
    const walkBody = bodyOf(iWalk);
    if (iWalk < 0 || walkBody.indexOf("local rc = { pcall(fr.GetChildren, fr) }") < 0) {
      bad.push("dfKidWalk 里 GetChildren 没按**多值**取（`{ pcall(fr.GetChildren, fr) }`）—— 否则只拿到第一个子件，静默少数据");
    }
    const iNames = idxOf("local function dfKidNames(");
    if (iNames < 0 || bodyOf(iNames).indexOf("local rc = { pcall(fr.GetChildren, fr) }") < 0) {
      bad.push("dfKidNames 里 GetChildren 没按多值取（身份指纹会只剩一个子件）");
    }
    //   ③ 满屏过滤：**既要存在、也要真的被调用**（只定义不调用 = 静默死代码，本项目有专门判据）
    const iFull = idxOf("local function dfKidIsFullscreen(");
    if (iFull < 0) bad.push("没有满屏家具帧过滤 dfKidIsFullscreen");
    else {
      const fb = bodyOf(iFull);
      if (!/uw\s*\*\s*0\.99/.test(fb) || !/uh\s*\*\s*0\.99/.test(fb)) {
        bad.push("dfKidIsFullscreen 没按 UIParent 尺寸**现算**（写成 1228/768 这类死数字，换分辨率/缩放就错）");
      }
    }
    if (walkBody.indexOf("dfKidIsFullscreen(w, h)") < 0) {
      bad.push("dfKidWalk 没调用满屏过滤（过滤只定义不调用 = 真机清单仍被 1228.8x768 的内部帧占满）");
    }
    if (joined.indexOf("w >= 200 and h >= 200") < 0) {
      bad.push("父子链的「像窗口」判据不是**宽高都 ≥200**（只用一个维度会被条状件占满，实测过）");
    }
    //   ④ 落档必须是**赋值**（`dump.kids = {}`）；只搜 `dump.kids` 会被后面打印它的代码命中（M5 实测漏网）
    if (joined.indexOf("dump.kids = {}") < 0) bad.push("父子链结果没落存档（缺 `dump.kids = {}` 这个赋值）—— AI 读不到匿名窗口");
    if (joined.indexOf("DF_PROBE_KIDS_MAX") < 0) bad.push("父子链清单没有上限（存档会被灌大）");
    if (bad.length) {
      console.log("DF GLOBAL SCAN GUARD CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF GLOBAL SCAN GUARD CHECK: 守卫 pcall 探测（table/userdata 两分支）· 两处全 _G 扫描都过守卫 · " +
      "dfTopHost 自身过守卫 · 只收字符串键 · 判不出类型不丢弃 · 非帧子件过滤");
  })();


  // ===================== DRAG FRAMES WIRING CHECK（1.74.30）：框拖拽抽成 tools/DragFrames.lua 后的**接线**（源码检查）===== =====================
  // ===== DRAG FRAMES WIRING CHECK（1.74.30）：框拖拽抽成 tools/DragFrames.lua 后的**接线**（源码检查）=====
  // 为什么必须用源码检查：子插件 `addons/EH_DebugBox/` **不在测试桩的载入清单里**（它不依赖主插件也能跑），
  //   于是「子插件那侧是不是真的只留转发」「面板按钮有没有指向模块」「老代码有没有删干净」行为断言**照不到**——
  //   而这几处漏了都不会报错，只是「两处真值打架」或「开关点了没反应」（本项目最恨的一族）。
  // 判据：
  //   ① 模块进了 .toc（不然运行期根本不存在）；
  //   ② 模块对外接口齐全（EVAL_DF_ENABLED/SET/SUMMARY/RESET/APPLYALL —— 工具箱那一行就指它们）；
  //   ③ 工具箱那一行改指 EVAL_DF_*，**不再**指子插件的 EVAL_LD_*；
  //   ④ 主插件在 VARIABLES_LOADED 里调 EVAL_DF_INSTALL（读开关 + 迁移老存档 + 恢复位置）；
  //   ⑤ 子插件只留瘦转发：EVAL_LD_* 全走 EVAL_DF_*、且**已删掉的实现不许复活**
  //      （uiDragHandle / uiDragKeepTick / uiDragRefresh / uiDragCommitPop / dragPop / LD_DRAG_TARGETS / ui.dragOn）；
  //   ⑥ 子插件里没有任何 SetMovable/StartMoving 作用在拖拽目标上（那是崩溃路径）。
  (function () {
    const bad = [];
    const toc = fs.readFileSync(path.join(__dirname, "EvalHelp.toc"), "utf8");
    if (!/tools[\\/]DragFrames\.lua/.test(toc)) bad.push("EvalHelp.toc 没列 tools/DragFrames.lua");
    const df = fs.readFileSync(path.join(__dirname, "tools", "DragFrames.lua"), "utf8");
    ["function EVAL_DF_ENABLED(", "function EVAL_DF_SET(", "function EVAL_DF_SUMMARY(",
     "function EVAL_DF_RESET(", "function EVAL_DF_APPLYALL(", "function EVAL_DF_INSTALL("].forEach(function (k) {
      if (df.indexOf(k) < 0) bad.push("tools/DragFrames.lua 缺对外接口：" + k);
    });
    // ★存档必须落在模块自己的表里、且按**帧名字**存（opt 里只许存名字字符串）
    if (df.indexOf("EVAL_HELP_CONFIG") < 0 || df.indexOf("dragFrames") < 0) bad.push("模块没有自己的存档（EVAL_HELP_CONFIG.dragFrames）");
    // ★★★1.74.34：那一行的界面接线搬进了**本模块**（`dfRow`），Toolbox 只留「一行数据 + 通用分支」
    //   ⇒ 判据改成：模块里必须有 dfRow、且登记进注册表；Toolbox 侧**不许**再出现 `EVAL_DF_*`（反向哨兵）。
    if (df.indexOf("function dfRow(") < 0) bad.push("tools/DragFrames.lua 缺模块行渲染函数 dfRow（工具箱那一行没人画）");
    if (df.indexOf("function EVAL_DF_TEST_ROW(") < 0) bad.push("tools/DragFrames.lua 缺读值口 EVAL_DF_TEST_ROW（断言无法证明那一行是本函数画的）");
    if (!/DF_TB_ROWS\["dragFrames"\]\s*=\s*dfRow/.test(df)) bad.push("dfRow 没有登记进 EVAL_TB_MOD_ROWS（名字对不上 ⇒ 那一行点不动）");
    for (const k of ["EVAL_DF_ENABLED", "EVAL_DF_SET", "EVAL_DF_RESET", "EVAL_DF_SUMMARY"]) {
      if (df.indexOf(k) < 0) bad.push("模块里缺主开关/重置/清单的接口：" + k);
    }
    const tb = fs.readFileSync(path.join(__dirname, "Toolbox.lua"), "utf8");
    if (tb.indexOf("EVAL_DF_") >= 0) {
      bad.push("Toolbox.lua 里还有 EVAL_DF_*（那一行的界面接线应当已搬进 tools/DragFrames.lua 的 dfRow）");
    }
    if (!/t = "mod",\s*mod = "dragFrames"/.test(tb)) {
      bad.push('工具箱模型里没有模块行 `t = "mod", mod = "dragFrames"`（那一行不会被渲染）');
    }
    const eh = fs.readFileSync(path.join(__dirname, "EvalHelp.lua"), "utf8");
    if (eh.indexOf("EVAL_DF_INSTALL") < 0) bad.push("EvalHelp.lua 没在 VARIABLES_LOADED 里调 EVAL_DF_INSTALL");
    const ad = fs.readFileSync(path.join(__dirname, "addons", "EH_DebugBox", "EH_DebugBox.lua"), "utf8");
    ["EVAL_LD_DRAG_GET", "EVAL_LD_DRAG_SET", "EVAL_LD_CUSTOM_SUMMARY", "EVAL_LD_DRAG_RESET"].forEach(function (k) {
      if (ad.indexOf("function " + k + "(") < 0) bad.push("子插件缺瘦转发：" + k);
    });
    if (ad.indexOf("EVAL_DF_ENABLED") < 0 || ad.indexOf("EVAL_DF_RESET") < 0) bad.push("子插件的转发没有真的指向 EVAL_DF_*");
    // 已删掉的实现不许复活（这些名字在子插件里只应出现在注释里）
    const adCode = ad.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    ["uiDragHandle", "uiDragKeepTick", "uiDragRefresh", "uiDragCommitPop", "dragPop", "LD_DRAG_TARGETS",
     "DRAG_SCALE_PRESETS", "ui.dragOn"].forEach(function (k) {
      if (adCode.indexOf(k) >= 0) bad.push("子插件里 " + k + " 又活了（应当已搬进 tools/DragFrames.lua）");
    });
    // ★★禁止路径：拖拽工具**绝不许**用 SetMovable/StartMoving —— 用户实测那条路会把客户端弄崩（受保护帧），
    //   已明令禁止。判据只钉**模块自己**（子插件里那几处在它自己的面板窗/信息条上，与本工具无关）。
    //   ★先摘注释：模块文件头就写着「绝不用 SetMovable/StartMoving」——不摘注释会**假红**（本项目老坑）。
    const dfCode = df.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    if (/SetMovable|StartMoving|StopMovingOrSizing/.test(dfCode)) {
      bad.push("tools/DragFrames.lua 里出现了 SetMovable/StartMoving（拖拽目标上那条路会把客户端弄崩，明令禁止）");
    }
    if (bad.length) {
      console.log("DRAG FRAMES WIRING CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DRAG FRAMES WIRING CHECK: 模块进 .toc · 工具箱/子插件都改指 EVAL_DF_* · 登录接了 EVAL_DF_INSTALL · " +
      "子插件只留转发（旧实现未复活）· 模块自身无 SetMovable/StartMoving");
  })();


  // ===================== DF PICK WIRING CHECK（1.74.33）：图层**选中名单**（工具箱 [设置] 多选下拉）的接线 ===== =====================
  // ===== DF PICK WIRING CHECK（1.74.33）：图层**选中名单**（工具箱 [设置] 多选下拉）的接线 =====
  // 为什么用源码检查：用户要求「工具箱->拖拽图层 右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，
  //   选中的才开启配置和支持拖拽,等图层拖拽的能力」。这批改动几乎**全是接线**，漏一处**不报错**、
  //   只是静默失效（行为断言只照得到本组覆盖的那几条路径）：
  //   ① ★★★写入口必须先把「全选」快照**物化**再改这一项 —— 少了它，一次「取消勾选公会」会让**其余所有层
  //      一起变未选中**（表里没有键 = 未选中）⇒ 用户点一下，几十条拖拽全消失，且没有任何报错；
  //   ② 每条生效路径都必须过 `dfPicked(`：贴柄 `dfRefresh` · 挂图标 `dfIconsRefresh` · 应用存档
  //      `dfApplyAll` / `dfKeepTick` / `dfApplyOne` · 事件结算 `dfRosterPass` · 清理 `EVAL_DF_RESET` ——
  //      漏一处就是「没勾的层照样被改」或「勾了却不生效」，两种都不报错；
  //   ③ 菜单内容唯一来源 = 模块的 `EVAL_DF_PICK_MENU`（从 `DF_TARGETS` 现生成）；
  //      工具箱侧**不许另造一份目标表**（复刻必漂：以后加一类目标要改两处，漏一处 = 新层永远选不上）；
  //   ④ 工具箱那侧必须用**多选**下拉打开（`multi=true` + `locked` 交给分组标题行），否则「多选」这个需求没实现。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF PICK WIRING CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const strip = function (txt) {
      return txt.split(/\r?\n/).map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    };
    const code = strip(fs.readFileSync(p, "utf8")).split("\n");
    const joined = code.join("\n");
    const bad = [];
    // 顶层函数体提取（本文件的定义要么 `local function f(`、要么 `f = function(`；结尾是**顶格** end）
    const bodyOf = function (srcLines, name) {
      const esc = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const re = new RegExp("^(local\\s+)?(function\\s+" + esc + "\\s*\\(|" + esc + "\\s*=\\s*function\\s*\\()");
      let start = -1;
      for (let i = 0; i < srcLines.length; i++) if (re.test(srcLines[i])) { start = i; break; }
      if (start < 0) return null;
      for (let i = start + 1; i < srcLines.length; i++) if (/^end\s*$/.test(srcLines[i])) return srcLines.slice(start, i + 1).join("\n");
      return null;
    };
    // ① 该有的件都在
    for (const n of ["dfPickTbl", "dfPicked", "dfPickVirgin", "EVAL_DF_PICK_ENABLED", "EVAL_DF_PICK_SET",
                     "EVAL_DF_PICK_MENU", "EVAL_DF_PICK_COUNT", "EVAL_DF_PICK_REFRESH"]) {
      if (joined.indexOf("function " + n + "(") < 0 && joined.indexOf(n + " = function(") < 0) {
        bad.push("DragFrames.lua 缺 " + n);
      }
    }
    // ② ★★★物化哨兵（本检查最要紧的一条）
    const setBody = bodyOf(code, "EVAL_DF_PICK_SET");
    if (!setBody) bad.push("找不到 EVAL_DF_PICK_SET");
    else {
      const iV = setBody.indexOf("dfPickVirgin()");
      const iC = setBody.indexOf("dfPickTbl(true)");
      if (iV < 0) bad.push("EVAL_DF_PICK_SET 没有用 dfPickVirgin() 判「是不是第一次写」");
      if (iC < 0) bad.push("EVAL_DF_PICK_SET 没有创建/取得 pick 表");
      if (!/for i = 1, table\.getn\(DF_TARGETS\)/.test(setBody)) {
        bad.push("EVAL_DF_PICK_SET 少了「先把全选快照物化进表」那一步（一次取消勾选会静默关掉其余所有层）");
      }
      if (iV >= 0 && iC >= 0 && iV > iC) {
        bad.push("EVAL_DF_PICK_SET 在**创建表之后**才问「是不是第一次」（那时已经不是 virgin 了 ⇒ 快照永远是空的）");
      }
    }
    // ③ 每条生效路径都要按勾选过滤
    // ★★★1.74.33 **按「该路径自己的那道门」逐条核**，不是「函数体里出现过 dfPicked」——
    //   第一版就是后者，结果变异 M4（把 `dfIconsRefresh` 的正向门摘掉）**漏过**：函数体末尾那道
    //   「收起来」的循环里也有 `dfPicked(k)`，于是「出现过」照样成立。真机后果：未勾选的窗口
    //   **照样被建出图标**（只是随后被藏起来）——资源白建、`iconN` 计数虚高。
    const GATES = {
      // 函数名 → 它**必须**含有的那道判据写法（逐条对应各路径的真实门）
      dfRefresh: "(dfPicked(tgt.name) and not tgt.icon)",
      dfIconsRefresh: "tgt.icon and dfPicked(tgt.name)",
      dfApplyAll: "local fr = dfPicked(tgt.name) and dfTargetFrame(tgt) or nil",
      dfKeepTick: "local fr = dfPicked(tgt.name) and dfTargetFrame(tgt) or nil",
      dfApplyOne: "if not dfPicked(tgt.name) then return false end",
      dfRosterPass: "tgt.roster and dfPicked(tgt.name)",
      EVAL_DF_RESET: "not dfPicked(tgt.name)",
    };
    for (const n of Object.keys(GATES)) {
      const b = bodyOf(code, n);
      if (!b) { bad.push("找不到函数 " + n); continue; }
      if (b.indexOf(GATES[n]) < 0) {
        bad.push(n + " 缺它自己的那道勾选判据（应有 `" + GATES[n] + "`）—— 没勾的层照样被贴柄/挂图标/被改，或勾了不生效");
      }
    }
    // ④ 菜单从 DF_TARGETS 现生成（单一来源）
    const menuBody = bodyOf(code, "EVAL_DF_PICK_MENU");
    if (menuBody && menuBody.indexOf("DF_TARGETS[i]") < 0) {
      bad.push("EVAL_DF_PICK_MENU 不是从 DF_TARGETS 现生成（以后新加的目标会漏出设置，永远选不上）");
    }
    // ⑤ 界面接线（[设置] 多选下拉 + 两个按钮的槽位 + 不许有第二份目标表）
    //   ★★★1.74.34：这一段**搬进了 tools/DragFrames.lua 的 `dfRow`**（用户要求：Toolbox 只留一行数据 + 一个嵌入点）
    //   ⇒ 判据跟着搬到模块侧；工具箱那一侧只剩「一行数据 + 通用分支」，由 `TB MOD ROW CHECK` 守。
    const dfBody = bodyOf(code, "dfRow");
    if (!dfBody) bad.push("tools/DragFrames.lua 里找不到模块行渲染函数 dfRow（工具箱那一行没人画）");
    else {
      for (const [needle, why] of [["EVAL_DF_PICK_MENU", "[设置] 没调模块菜单（点了没菜单）"],
                                   ["EVAL_DF_PICK_SET", "[设置] 没调写入口（勾选写不进去）"],
                                   ["EVAL_DF_PICK_REFRESH", "[设置] 勾完没结算（不当场生效/收柄）"],
                                   ["EVAL_DF_PICK_COUNT", "[设置] 悬停没读「已勾选 n/总数」"],
                                   ["EVAL_DF_RESET", "[重置] 没接还原入口"],
                                   ["EVAL_DF_SUMMARY", "[重置] 悬停清单没读模块的自定义记录"],
                                   ["EVAL_DF_ENABLED", "主开关没读真值"],
                                   ["EVAL_DF_SET", "主开关没写入口"]]) {
        if (dfBody.indexOf(needle) < 0) bad.push(why);
      }
      if (!/multi\s*=\s*true/.test(dfBody)) bad.push("[设置] 的下拉不是多选（multi = true 缺席 ⇒「支持多选」这条需求没实现）");
      if (!/locked\s*=\s*locked/.test(dfBody)) bad.push("[设置] 的下拉没把 locked 交给分组标题行");
      if (!/selected\s*=\s*sel/.test(dfBody)) bad.push("[设置] 的下拉没把 selected 交给初始勾选（重开面板勾选会是错的）");
      // ★★几何哨兵（源码级）：这一行有两个右侧按钮 ⇒ [重置] 必须挂 `r.clr`、[设置] 必须挂 `r.add`，
      //   **绝不许**用 `r.chv`（88 宽、与 add 槽完全重叠 ⇒ 后建者压住前者、那个按钮永远点不到，
      //   而「按钮存在 + 脚本挂上」的行为断言照样全绿 —— 遮挡是断言照不到的盲区）。
      if (dfBody.indexOf("r.clr.btn:Show()") < 0) bad.push("模块行的 [重置] 没用 clr 槽（r.clr.btn:Show 缺席）");
      if (dfBody.indexOf("r.chv.btn") >= 0) bad.push("模块行用了 chv 槽（88 宽、与 add 槽完全重叠 ⇒ [设置] 点不到）");
    }
    if (!/DF_TB_ROWS\["dragFrames"\]\s*=\s*dfRow/.test(joined)) {
      bad.push("dfRow 没有登记进 EVAL_TB_MOD_ROWS（工具箱按名字取不到它 ⇒ 那一行点不动）");
    }
    // ★工具箱里**不许**出现目标帧名字面量（目标表只许有一份，在本模块里）
    const tbPath2 = path.join(__dirname, "Toolbox.lua");
    if (!fs.existsSync(tbPath2)) bad.push("找不到 Toolbox.lua");
    else {
      const tb2 = strip(fs.readFileSync(tbPath2, "utf8"));
      for (const n of ["PartyMemberFrame1", "GuildFrame", "SpellBookFrame", "MultiBarBottomLeft", "PlayerFrame"]) {
        if (tb2.indexOf('"' + n + '"') >= 0) bad.push("工具箱里出现了目标帧名字面量 " + n + "（目标表只许有一份，在 tools/DragFrames.lua）");
      }
    }
    if (bad.length) {
      console.log("DF PICK WIRING CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF PICK WIRING CHECK: 选中名单真值 + 写入口物化全选快照 · 七条生效路径都过 dfPicked · " +
      "菜单从 DF_TARGETS 现生成 · 工具箱 [设置] 走模块菜单的多选下拉（无第二份目标表）");
  })();


  // ===================== DF ICON ART CHECK（1.74.33）：窗口图标「画法 + 左键/右键分工」的接线 ===== =====================
  // ===== DF ICON ART CHECK（1.74.33）：窗口图标「画法 + 左键/右键分工」的接线 =====
  // 为什么用源码检查：用户两条要求（「窗口的拖拽使用图标 346 号宏图标」「左键不要触发弹窗效果」）
  //   落成的都只是**接线**，而且都极易被后来者「顺手改回去」而不报错：
  //   ① 画法必须**按号现取**（`GetMacroIconInfo(346)`）——写成纹理路径字面量就是两处真值（清单会漂）；
  //      号本身钉在 `DF_ICON_MACRO`（唯一来源），且必须留**取不到就退回文字**的退路（绝不静默变空白方块）；
  //   ② 左键**不许**弹属性窗：`OnClick` 里出现 `dfCommitPop` 即 FAIL（那是旧实现），
  //      `dfDragEnd` 的弹窗条件必须显式排除图标（`b.dfIcon ~= true`）——★判据写 `== true`/`~= true`，
  //      不许写真值判断：测试桩的帧 mock 对未知键返回函数，真值判断会把**每条普通柄**都误判成图标；
  //   ③ 右键必须**注册** RightButtonUp（只注册左键 = 右键事件永远到不了 OnMouseUp，本项目已记过这条）。
  (function () {
    const p = path.join(__dirname, "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF ICON ART CHECK: (无 tools/DragFrames.lua，跳过)"); return; }
    const lines = fs.readFileSync(p, "utf8").split(/\r?\n/);
    const code = lines.map(function (l) { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; });
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
    // ① 346 号 = 唯一来源 + 按号现取 + 退路
    if (!/local DF_ICON_MACRO\s*=\s*346\b/.test(joined)) bad.push("DF_ICON_MACRO 不是 346（用户指定的宏图标号；号只许写这一处）");
    if (joined.indexOf("local function dfMacroIconTex(") < 0) bad.push("没有 dfMacroIconTex（按号取纹理的唯一入口）");
    else {
      if (joined.indexOf("GetMacroIconInfo") < 0) bad.push("dfMacroIconTex 没走 GetMacroIconInfo（本客户端取宏图标纹理的唯一合法入口）");
      if (joined.indexOf("GetNumMacroIcons") < 0) bad.push("dfMacroIconTex 没先用 GetNumMacroIcons 挡越界（越界行为无本地证据，不许猜）");
    }
    const buildBody = bodyOf(code, "dfIconBuild");
    if (!buildBody) bad.push("找不到 dfIconBuild");
    else {
      if (buildBody.indexOf("dfMacroIconTex(DF_ICON_MACRO)") < 0) bad.push("dfIconBuild 没按号取纹理（可能写死了路径）");
      if (buildBody.indexOf("DF_ICON_LABEL") < 0) bad.push("dfIconBuild 没留「取不到就退回文字」的退路（会静默变空白方块）");
      // ② 左键不许弹属性窗 —— ★必须**按脚本分段**判，不能只看「函数体里有没有 dfCommitPop」：
      //   第一版就是后者，于是变异 M22（把 dfCommitPop 塞回 OnClick 退路）**整条漏过**
      //   （右键分支还在 ⇒「有 dfCommitPop 且没有右键分支」这个条件不成立）。
      //   属性弹窗只许活在 OnMouseUp 的右键分支里，OnClick 退路里出现即 FAIL。
      //   ★★1.74.33：鼠标分工抽成了**唯一实现** `dfBindDragButton`（图标本体与**头部拖拽带**共用），
      //     所以这一段判据要挂在那个函数上 —— 挂回 dfIconBuild 会变成「函数搬家 ⇒ 检查失明」。
      if (buildBody.indexOf("dfBindDragButton(") < 0) bad.push("dfIconBuild 没走共用的鼠标分工实现 dfBindDragButton");
    }
    const bindBody = bodyOf(code, "dfBindDragButton");
    if (!bindBody) bad.push("找不到 dfBindDragButton（图标与头部拖拽带的鼠标分工唯一实现）");
    else {
      if (bindBody.indexOf("b.dfIcon = true") < 0) bad.push("dfBindDragButton 没打 dfIcon 标记（dfDragEnd 的「左键不弹」就失效）");
      const iUp = bindBody.indexOf('SetScript("OnMouseUp"');
      const iUpEnd = bindBody.indexOf("SetScript(", iUp + 10);
      const upSeg = (iUp >= 0) ? bindBody.slice(iUp, iUpEnd > iUp ? iUpEnd : bindBody.length) : "";
      const iClk = bindBody.indexOf('SetScript("OnClick"');
      // ★OnClick 是**最后**一个挂的脚本（后面没有 SetScript 了）⇒ 找不到下一个锚点时必须取到函数体末尾，
      //   否则片段是空串、`dfCommitPop` 检查恒不成立 —— 变异 M22 第一版就是这么漏过去的。
      const iClkEnd = bindBody.indexOf("SetScript(", iClk + 10);
      const clkSeg = (iClk >= 0) ? bindBody.slice(iClk, iClkEnd > iClk ? iClkEnd : bindBody.length) : "";
      if (iClk < 0) bad.push("图标没有 OnClick 退路（老形态调用下点击语义就没了）");
      else if (clkSeg.indexOf("dfCommitPop") >= 0) {
        bad.push("图标 OnClick 里又出现 dfCommitPop（左键点击弹属性窗 = 用户明确不要的）");
      }
      // ★共用出口：属性弹窗只许有一个出口 `popup()`（内含唯一的 dfCommitPop），两条分派路都调它。
      //   ⇒ 「有没有右键入口」按**调没调那个出口**判，不按「片段里有没有 dfCommitPop 字面量」判。
      if (bindBody.indexOf("dfCommitPop") < 0) bad.push("图标哪里都不开属性窗（右键入口丢了）");
      if (!/local function popup\(\)/.test(bindBody)) bad.push("没有共用的 popup() 出口（两条分派路会各写一份、迟早漂移）");
      if (iUp < 0) bad.push("图标没有 OnMouseUp（拖动收尾与右键都挂在这里）");
      else {
        if (upSeg.indexOf("popup()") < 0) bad.push("图标的属性弹窗不在 OnMouseUp 里（右键入口丢了）");
        if (upSeg.indexOf("RightButton") < 0) bad.push("OnMouseUp 没有右键分支（属性配置就没了唯一入口）");
      }
      // ★★★2c 右键的**第二条分派路**（项目既有约定：右键在 OnClick 里分派）：允许 OnClick 调 popup()，
      //   但**必须在右键分支里** —— 左键调到即 FAIL（用户 1.74.33：「左键不要触发弹窗效果」）。
      if (clkSeg.indexOf("popup()") >= 0 && clkSeg.indexOf("RightButton") < 0) {
        bad.push("OnClick 里调了属性弹窗却不在右键分支里（左键点击会弹属性窗 = 用户明确不要的）");
      }
      // ★★★2d 鼠标键必须过 `dfMouseBtn` 归一化 —— 这是 1.74.33 的**真机 bug**：
      //   原来写 `function(a1) if a1 == "RightButton"`，而本客户端回调是 `handler(self, button)`
      //   ⇒ `a1` 拿到 **self** ⇒ 右键判定**永远不成立**（右键打不开配置）；测试直接喂字符串 ⇒ 照样全绿。
      if (joined.indexOf("local function dfMouseBtn(") < 0) bad.push("没有 dfMouseBtn（鼠标键归一化助手：回调第一个参数是 self）");
      if (bindBody.indexOf("dfMouseBtn(a1, a2)") < 0) bad.push("鼠标分工没用 dfMouseBtn(a1, a2) 解析按键（直接比第一个参数 = 真机上永远不成立）");
      // ③ 右键必须注册
      if (bindBody.indexOf('"RightButtonUp"') < 0) bad.push("图标没注册 RightButtonUp（右键事件到不了分派代码）");
    }
    // ④ 头部拖拽带（用户 1.74.33：「窗口拖拽的区域能否定位到 窗体头部红色部分?」）
    //   为什么必须源码守：它是**透明**控件 —— 建错位置/宽度不会报错，只会「悄悄吃掉关闭按钮的点击」
    //   或「某一段看着能拖却拖不动」，两种都不进任何行为断言。
    const headBody = bodyOf(code, "dfHeadBuild");
    if (!headBody) bad.push("没有 dfHeadBuild（头部拖拽带：整条标题栏都能拖窗口）");
    else if (headBody.indexOf("dfBindDragButton(") < 0) bad.push("头部拖拽带没走共用的鼠标分工（会与图标两套行为漂移）");
    const iconEnsureBody = bodyOf(code, "dfIconEnsure");
    if (!iconEnsureBody) bad.push("找不到 dfIconEnsure");
    else {
      if (iconEnsureBody.indexOf("DF_ICON_RIGHT") < 0) bad.push("头部拖拽带宽度没减掉**关闭按钮留空区**（DF_ICON_RIGHT）⇒ 会盖住关闭按钮");
      // ★★还得减掉**图标自身宽度**：只减留空区时带的右端正好落在图标右边界 ⇒ 带把图标整块盖住、
      //   右键点不到图标（组 215③ 的几何断言当场抓到过；与「[设置]/[重置] 同锚」是同一类遮挡事故）。
      if (iconEnsureBody.indexOf("DF_ICON_SIZE") < 0) bad.push("头部拖拽带宽度没减掉**图标自身宽度**（DF_ICON_SIZE）⇒ 带会盖住图标");
      // ★★按**表达式**核一遍宽度公式：只查「出现过这两个常量」是不够的（图标自己的锚点也用了 DF_ICON_RIGHT）
      //   ⇒ 漏减一项照样能过。这里要求三项相减的字面形态在位。
      if (!/DF_HEAD_LEFT\s*-\s*DF_ICON_RIGHT\s*-\s*DF_ICON_SIZE/.test(iconEnsureBody)) {
        bad.push("头部拖拽带宽度不是「窗口宽 − 左让开 − 关闭按钮留空区 − 图标宽」这个形态（有一项被漏减）");
      }
      if (iconEnsureBody.indexOf("rec.head") < 0) bad.push("dfIconEnsure 没保证头部拖拽带（rec.head）");
    }
    const iconsRefreshBody = bodyOf(code, "dfIconsRefresh");
    if (iconsRefreshBody && iconsRefreshBody.indexOf("rc.head") < 0 && iconsRefreshBody.indexOf("rec.head") < 0) {
      bad.push("取消勾选/关掉开关时没把头部拖拽带一起收起（会留下一条看不见却吃点击的带子）");
    }
    const endBody = bodyOf(code, "dfDragEnd");
    if (!endBody) bad.push("找不到 dfDragEnd");
    else {
      if (endBody.indexOf("b.dfIcon ~= true") < 0) bad.push("dfDragEnd 的弹窗条件没排除图标（左键松手照样弹 = 用户明确不要的）");
      if (/if\s+b\.dfIcon\s+and\s/.test(endBody)) bad.push("dfDragEnd 用了 dfIcon 的**真值判断**（桩对未知键返回函数 ⇒ 普通柄会被误判成图标）");
    }
    for (const n of ["EVAL_DF_TEST_MACRO_TEX", "EVAL_DF_TEST_ICON_ART", "EVAL_DF_TEST_ICON_DROP"]) {
      if (joined.indexOf("function " + n + "(") < 0) bad.push("缺读值口 " + n);
    }
    const eh = path.join(__dirname, "EvalHelp.lua");
    if (fs.existsSync(eh)) {
      const e = fs.readFileSync(eh, "utf8");
      if (e.indexOf("图标画法：346 号宏图标") < 0) bad.push("/eh go 框体图标 状态 没报出「346 号解析成什么纹理」（用户没法核对号对不对）");
    }
    if (bad.length) {
      console.log("DF ICON ART CHECK: FAIL - " + bad.join(" | "));
      process.exitCode = 1;
      return;
    }
    console.log("DF ICON ART CHECK: 346 号宏图标按号现取（含越界挡 + 退回文字退路）· 左键不弹属性窗 · 右键开窗且已注册 RightButtonUp");
  })();

  // ===== DF GROUP ROSTER CHECK（1.74.34）：搬进 tests/tools/DragFrames.lua 的**组号清单**不许静默少一个 =====
  // 为什么必须有它：行为断言与「跑到底握手」都照不到「整组被人删掉 / 掏空」——
  //   少跑一个组，套件照样打印 ALL TESTS PASS（本项目最恨的那种静默失效）。所以把**组号清单**钉在这里：
  //   ① 组号集合必须与期望**完全一致**（多一个少一个都 FAIL）；
  //   ② 必须**按编号升序**（组 204 的前置夹具帧是组 202 造的 ⇒ 顺序本身是契约）；
  //   ③ 每个组区间里必须**真的有断言**（出现 `eq(`）⇒「整组被删」与「被掏空成只剩注释」都会当场变红；
  //   ④ 每组必须有 `print("GROUP <n> …: PASS")` 收尾行 ⇒ 跑没跑到底、日志里一眼可判。
  (function () {
    const WANT = [202, 204, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 220, 221, 222];
    const p = path.join(__dirname, "tests", "tools", "DragFrames.lua");
    if (!fs.existsSync(p)) { console.log("DF GROUP ROSTER CHECK: FAIL - 找不到 tests/tools/DragFrames.lua"); process.exitCode = 1; return; }
    const s = fs.readFileSync(p, "utf8");
    const bad = [];
    const pos = [];
    for (const m of s.matchAll(/-- ===== 组 (\d+)/g)) pos.push({ n: +m[1], i: m.index });
    const got = pos.map(x => x.n);
    if (got.length !== WANT.length) bad.push("组数 " + got.length + " ≠ 期望 " + WANT.length);
    const missing = WANT.filter(n => got.indexOf(n) < 0);
    const extra = got.filter(n => WANT.indexOf(n) < 0);
    if (missing.length) bad.push("少了组 " + missing.join(","));
    if (extra.length) bad.push("多了组 " + extra.join(","));
    if (got.join(",") !== got.slice().sort((a, b) => a - b).join(",")) bad.push("组号没按升序排（组 204 依赖组 202 的夹具帧）");
    pos.forEach((x, k) => {
      const seg = s.slice(x.i, k + 1 < pos.length ? pos[k + 1].i : s.length);
      if (seg.indexOf("eq(") < 0) bad.push("组 " + x.n + " 区间里一条 eq( 都没有（整组被掏空？）");
      if (seg.indexOf('print("GROUP ' + x.n) < 0) bad.push("组 " + x.n + " 缺 print(\"GROUP " + x.n + " …: PASS\") 收尾行");
    });
    if (bad.length) { console.log("DF GROUP ROSTER CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("DF GROUP ROSTER CHECK: " + got.length + " 个组号与期望完全一致且升序 · 每组都有真实断言与 PASS 收尾行（" + got.join("/") + "）");
  })();

};
