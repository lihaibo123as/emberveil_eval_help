// tests/checks/MinimapBtn.js —— 小地图「EH」配置按钮图标的源码检查（1.75.10 建）
// 用户报障原话：「插件配置的图标初始使用: 现在是黑色的没有图标.」
// ★真机症状已定案（截图取色 #1D180E ≈ 创建时的 `WHITE8X8 × 0.12/0.10/0.06`；一色占 95% 像素、无字无框）
//   ⇒ 那是「**一次都没贴上过图标**」的暗底 —— **不是**「贴了一张黑图」。
// ★为什么必须源码级钉（这四条全是**静默**的，行为断言只在特定夹具下才照得到）：
//   ① 贴图那两行是 `pcall` ⇒ 失败不报错，界面上只表现为一块黑方块（本项目最恨的那族）；
//   ② 兜底样式的金框画在 **BACKGROUND**，而那块暗底是**不透明、同尺寸的 ARTWORK**
//      ⇒ 金框被 100% 盖住 = 真机上「图标拿不到」时用户看到的**还是**黑方块（「不许留空白按钮」没落地）；
//   ③ 贴图只在 **VARIABLES_LOADED 打一次**，而那一刻宏图标表/存档未必就绪（本文件 3237 行注释自己写着）
//      ⇒ 必须另有自愈时机（**进世界** + **悬停**），且自愈要**幂等**（已贴上就一次都不发）；
//   ④ 读数（读回 / 判定原因）不落盘的话，真机出错时只能靠用户截图猜（`say` 不落日志环的教训）。
module.exports = function (root) {
  const fs = require("fs");
  const path = require("path");
  (function () {
    const bad = [];
    const p = path.join(root, "EvalHelp.lua");
    if (!fs.existsSync(p)) { console.log("MB ICON WIRING CHECK: (无 EvalHelp.lua，跳过)"); return; }
    const raw = fs.readFileSync(p, "utf8");
    const sm = raw.split(/\r?\n/).map(l => { const i = l.indexOf("--"); return i >= 0 ? l.slice(0, i) : l; }).join("\n");
    const core = fs.readFileSync(path.join(root, "Core.lua"), "utf8");

    // ① 贴图口：设纹理 + 顶点色归白 + **alpha 还原** + **读回**（贴上了没有的唯一凭据）
    const iApply = sm.indexOf("local function mbApplyIcon(");
    const iApplyEnd = iApply >= 0 ? sm.indexOf("\nend", iApply) : -1;
    const applySeg = (iApply >= 0 && iApplyEnd > iApply) ? sm.slice(iApply, iApplyEnd) : "";
    if (!applySeg) bad.push("找不到 mbApplyIcon（贴图唯一出口）");
    else {
      if (!/SetTexture,\s*mbIconTex,\s*path/.test(applySeg)) bad.push("mbApplyIcon 没有把 path 贴上去");
      if (!/SetVertexColor,\s*mbIconTex,\s*1,\s*1,\s*1/.test(applySeg)) bad.push("mbApplyIcon 没有把顶点色归白（残留的暗底顶点色会把图标乘成黑的）");
      if (!/SetAlpha,\s*mbIconTex,\s*1/.test(applySeg)) bad.push("mbApplyIcon 没有还原 alpha=1 ⇒ 从兜底（暗底已 SetAlpha(0)）切回图标时整块透明（换个花样的黑方块）");
      if (applySeg.indexOf("mbIconBackOf()") < 0) bad.push("mbApplyIcon 没有读回（`mbIconBackOf()`）⇒ 「贴上没贴上」没有凭据");
    }
    if (sm.indexOf("local function mbIconBackOf()") < 0) bad.push("没有 mbIconBackOf（客户端读回的唯一来源）");

    // ② 兜底必须**真的看得见**：暗底 SetAlpha(0) + 每次进兜底把「EH」字写回
    const iSet = sm.indexOf("function EVAL_HELP_MB_SETICON(");
    const iSetEnd = iSet >= 0 ? sm.indexOf("\nend", iSet) : -1;
    const setSeg = (iSet >= 0 && iSetEnd > iSet) ? sm.slice(iSet, iSetEnd) : "";
    if (!setSeg) bad.push("找不到 EVAL_HELP_MB_SETICON");
    else {
      if (!/SetAlpha,\s*mbIconTex,\s*0/.test(setSeg)) {
        bad.push("兜底分支没有把暗底 SetAlpha(0) ⇒ 金框在 BACKGROUND、暗底是**不透明同尺寸 ARTWORK**，金框被完全盖住（真机上仍是一块黑方块）");
      }
      if (!/mbText\.SetText,\s*mbText,\s*"EH"/.test(setSeg)) bad.push('兜底没有每次把「EH」字写回（贴过图标后它被清空 ⇒ 再回兜底只剩金框没有字）');
      if (!/mbWhy/.test(setSeg)) bad.push("SETICON 没有记判定原因 mbWhy（诊断口径缺失）");
    }

    // ③ 自愈：幂等口 + 两个时机（进世界 / 悬停）
    const iRetry = sm.indexOf("function EVAL_HELP_MB_RETRY()");
    const iRetryEnd = iRetry >= 0 ? sm.indexOf("\nend", iRetry) : -1;
    const retrySeg = (iRetry >= 0 && iRetryEnd > iRetry) ? sm.slice(iRetry, iRetryEnd) : "";
    if (!retrySeg) bad.push("没有 EVAL_HELP_MB_RETRY（自愈口）");
    else if (!/if mbIconPath then return true end/.test(retrySeg)) {
      bad.push("自愈口没有「已贴上就早退」⇒ 每次悬停都重贴（正常路径不再零动作）");
    }
    const iEnter = sm.indexOf('mb:SetScript("OnEnter"');
    const enterSeg = iEnter >= 0 ? sm.slice(iEnter, iEnter + 400) : "";
    if (iEnter < 0) bad.push("找不到小地图按钮的 OnEnter 脚本（悬停自愈的接线点）");
    else if (enterSeg.indexOf("EVAL_HELP_MB_RETRY") < 0) bad.push("OnEnter 没有调自愈口 ⇒ 载入那次没贴上时，悬停也不会自己好");
    const iPew = sm.indexOf('en == "PLAYER_ENTERING_WORLD"');
    const pewSeg = iPew >= 0 ? sm.slice(iPew, iPew + 700) : "";
    if (iPew < 0) bad.push("找不到 PLAYER_ENTERING_WORLD 分支（进世界自愈的接线点）");
    else if (pewSeg.indexOf("EVAL_HELP_MB_RETRY") < 0) bad.push("PLAYER_ENTERING_WORLD 分支没有调自愈口 ⇒ 载入没贴上就一直是黑方块（用户报障的那条路）");

    // ④ 取证命令：读数摊开 + 按宏图标号设 + 专属落盘（有界）
    const iCmd = sm.indexOf('msg == "go mbicon"');
    const cmdSeg = iCmd >= 0 ? sm.slice(iCmd, iCmd + 4200) : "";
    if (iCmd < 0) bad.push("找不到 `/eh go mbicon` 命令分支");
    else {
      //   ★★★只查「标签字样在不在」会被**改值**的变异顶住（M8/M8b 实测两次漏网）⇒ 判据一律
      //     「标签 + **紧跟的取值表达式**」一起匹配（同「先剥注释再剥字符串、只盯目标语句」那套纪律）。
      const pairs = [
        ['存档=', /存档="\s*\.\.\s*tostring\(c\(\)\.mbIcon\)/],
        ['已贴=', /已贴="\s*\.\.\s*tostring\(v\.icon\)/],
        ['读回=', /读回="\s*\.\.\s*tostring\(v\.back\)/],
        ['判定=', /判定="\s*\.\.\s*tostring\(v\.why\)/],
        ['自动挑=', /自动挑="\s*\.\.\s*pick/],
      ];
      for (const [key, re] of pairs) {
        if (cmdSeg.indexOf(key) < 0) bad.push("探针输出缺「" + key + "」这一段（真机出错时看不出是哪一环）");
        else if (!re.test(cmdSeg)) bad.push("探针的「" + key + "」没接上**真值取值**（只剩标签 = 变异的假绿）");
      }
      if (cmdSeg.indexOf(".mbProbe") < 0) bad.push("探针没有专属落盘 cfg.mbProbe（`say` 只进聊天框 ⇒ AI 侧读不到）");
      //   ★只查「.mbProbe 出现过」不够（变异 M9 实测漏网）：那句 `c().mbProbe = box` 是**建箱**，
      //     真正把读数写进去的是 append 那一行 ⇒ 两件都要钉（同「读 + 写 + 命中即返回」那套纪律）。
      if (!/box\.out\[table\.getn\(box\.out\) \+ 1\] = s/.test(cmdSeg)) bad.push("探针没有把读数**真的 append 进** cfg.mbProbe.out（只建了空箱子）");
      if (!/while table\.getn\(box\.out\) > MB_OUT_MAX/.test(cmdSeg)) bad.push("mbProbe 没有上限裁剪（有界环）");
      if (cmdSeg.indexOf("GetMacroIconInfo") < 0) bad.push("探针不支持按宏图标号设定（用户截图给的就是序号：头龙 670）");
      if (cmdSeg.indexOf("取不到") < 0) bad.push("探针没有「号越界 ⇒ 如实说取不到」这一态");
    }
    if (core.indexOf('"mbProbe"') < 0) bad.push("Core.lua 的调试残渣键清单里没有 mbProbe");
    if (sm.indexOf("function EVAL_TEST_MB_ICON_RESET()") < 0) bad.push("缺读值口 EVAL_TEST_MB_ICON_RESET（「未贴→自愈」那条路只有靠它才验得到）");
    if (sm.indexOf("plateAlpha = nil") < 0 || sm.indexOf("back = mbBack") < 0) {
      bad.push("EVAL_TEST_MB_VISUAL 没有暴露 back/plateAlpha（贴上了没有 / 兜底看不看得见都没法断言）");
    }

    // ⑨ ★★★默认图标 = **头龙**（用户 2026-09-25 定稿：「头龙 配置为插件默认图标」）：
    //   候选表的**第一条**必须是 `^INV_MISC_HEAD_DRAGON_01`（且必须带 `_01` —— Black/Blue/… 不算命中），
    //   力量祝福退居**第二**（某客户端没头龙那枚时不至于掉到扳手）。★顺序即判据 ⇒ 源码级钉住，防被顺手重排。
    const iPick = sm.indexOf("function EVAL_HELP_MB_PICKICON(");
    const pickSeg = iPick >= 0 ? sm.slice(iPick, iPick + 1400) : "";
    const iCands = pickSeg.indexOf("local CANDS = {");
    if (iCands < 0) bad.push("找不到候选前缀表 CANDS（默认图标的唯一来源）");
    else {
      const cands = (pickSeg.slice(iCands, pickSeg.indexOf("}", iCands)).match(/"(\^[A-Z0-9_]+)"/g) || [])
        .map(s => s.replace(/"/g, ""));
      if (cands[0] !== "^INV_MISC_HEAD_DRAGON_01") {
        bad.push("默认图标候选第一条不是 ^INV_MISC_HEAD_DRAGON_01（实测 " + String(cands[0]) + "）⇒ 用户 2026-09-25 定稿的「头龙」被挤掉了");
      }
      if (cands[1] !== "^SPELL_HOLY_BLESSINGOFSTRENGTH") {
        bad.push("第二顺位不是力量祝福（实测 " + String(cands[1]) + "）⇒ 头龙缺席时会掉到扳手，不是 1.71.17 定的那枚");
      }
    }
    //   ★一次性迁移：存档里那枚「设了却显示成黑方块」的自定义图标要被清掉（只清那一个确切值 + 如实播报）
    if (sm.indexOf('cfg.mbIcon == "/Game/Interface/Icons/INV_Misc_ShadowEgg_TEX"') < 0) {
      bad.push("没有清掉旧自定义图标 ShadowEgg 的一次性迁移 ⇒ 用户存档里那份自定义仍然压着默认图标（他永远看不到头龙）");
    }

    if (bad.length) { console.log("MB ICON WIRING CHECK: FAIL - " + bad.join(" | ")); process.exitCode = 1; return; }
    console.log("MB ICON WIRING CHECK: 贴图口读回自证 + alpha 还原 · 兜底可见（暗底透明 + EH 字写回）· " +
      "自愈幂等且进世界/悬停两处接线 · 取证命令读数摊开 + 按号设定 + 专属有界落盘/残渣键 · " +
      "**默认图标 = 头龙**（用户定稿，次位力量祝福）· 旧 ShadowEgg 自定义一次性清掉");
  })();
};
