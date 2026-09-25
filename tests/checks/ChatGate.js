// tests/checks/ChatGate.js —— 聊天输出总闸门（1.75.8 建）
// 用户要求：「say 函数能否在 根据全局配置->记录调试日志状态开关要不要打印.? 记录调试日志重命名->调试日志」
// 为什么必须是源码检查：门控「漏了一处」全是**静默**的 —— 关掉开关后某个模块照旧刷屏；
//   行为断言只走单一入口（EVAL_SAY），照不到「自己直接写 DEFAULT_CHAT_FRAME」的旁路，也照不到新模块忘了加门控。
// 判据：
//   ① Core.lua：say **先门控再输出**（logEnabled() → chatOut()），两个出口都导出（EVAL_SAY_FORCE / EVAL_CHAT_ON）；
//   ② 声明顺序：logEnabled 必须在 say 之前（引用点写在 local 之前 = 绑成全局 nil，运行时才炸 —— 本项目老坑）；
//   ③ /eh log 分支的确认行必须走常开出口（关掉那一刻要让人看得到「怎么开回来」）；
//   ④ 模块自建打印口（自己直接写 DEFAULT_CHAT_FRAME 的那个）必须读 EVAL_CHAT_ON；
//   ⑤ 三语标签 G_LOG_FILE 都在，且 zhCN 已改名（旧名「记录调试日志」不许回来）。
module.exports = function (root) {
  const fs = require("fs");
  const path = require("path");
  const read = p => { const f = path.join(root, p); return fs.existsSync(f) ? fs.readFileSync(f, "utf8") : ""; };
  const core = read("Core.lua");
  if (!core) { console.log("CHAT GATE CHECK: skipped (no Core.lua)"); return; }
  const bad = [];
  // ① say 门控 + 两个出口
  if (!/local function say\(msg\)[\s\S]{0,200}?if not logEnabled\(\) then return end[\s\S]{0,80}?chatOut\(msg\)/.test(core)) {
    bad.push("Core.lua 的 say 没有「先门控再输出」（必须 if not logEnabled() then return end → chatOut(msg)）");
  }
  if (!/EVAL_SAY_FORCE\s*=\s*chatOut/.test(core)) bad.push("Core.lua 没导出 EVAL_SAY_FORCE（关掉开关后连确认行都看不见 = 静默族）");
  if (!/EVAL_CHAT_ON\s*=\s*logEnabled/.test(core)) bad.push("Core.lua 没导出 EVAL_CHAT_ON（自建打印口的模块读不到总闸门）");
  if (!/EVAL_SAY_FORCE\(".*引擎未加载完整/.test(core)) bad.push("「引擎未加载完整」兜底没走常开出口（插件坏掉时反而没声）");
  // ② 声明顺序（DECL ORDER 的同族盲区：这里是**函数声明**对，名字对不上就漏）
  const iDecl = core.indexOf("local function logEnabled");
  const iSay = core.indexOf("local function say(");
  if (iDecl < 0 || iSay < 0 || iDecl > iSay) bad.push("Core.lua 里 logEnabled 声明在 say 之后（DECL ORDER：会绑成全局 nil）");
  // ③ /eh log 的确认行走常开出口
  const eh = read("EvalHelp.lua");
  const iLog = eh.indexOf("if msg == " + JSON.stringify("log") + " then");
  const iDump = eh.indexOf("elseif msg == " + JSON.stringify("logdump") + "");
  const seg = (iLog >= 0 && iDump > iLog) ? eh.slice(iLog, iDump) : "";
  if (!seg) bad.push("EvalHelp.lua 找不到 /eh log 分支");
  else {
    if (seg.indexOf("fsay(") < 0) bad.push("/eh log 的确认行没走常开出口（关掉那一刻会静默）");
    if (/^ {6}say\(/m.test(seg)) bad.push("/eh log 分支里仍有受门控的 say");
  }
  // ④ 模块自建打印口必须读总闸门（SimpleMap 的 P 是唯一直接写聊天框的模块口）
  const sm = read(path.join("tools", "SimpleMap.lua"));
  if (!sm) bad.push("缺少 tools/SimpleMap.lua");
  else {
    const iP = sm.indexOf("local function P(msg)");
    const pSeg = iP >= 0 ? sm.slice(iP, iP + 700) : "";
    if (!pSeg) bad.push("tools/SimpleMap.lua 找不到 P（模块自己的播报口）");
    else if (pSeg.indexOf("EVAL_CHAT_ON") < 0) bad.push("tools/SimpleMap.lua 的 P 没读总闸门 EVAL_CHAT_ON（关掉开关仍会刷屏）");
  }
  // ⑤ 三语标签
  for (const lg of ["zhCN", "enUS", "ruRU"]) {
    const t = read(path.join("Locales", lg + ".lua"));
    if (!/G_LOG_FILE\s*=\s*"/.test(t)) bad.push("Locales/" + lg + ".lua 缺 G_LOG_FILE");
  }
  if (/G_LOG_FILE\s*=\s*"[^"\n]*记录调试日志/.test(read(path.join("Locales", "zhCN.lua")))) {
    bad.push("zhCN 的 G_LOG_FILE 还是旧名「记录调试日志」（用户要求改名「调试日志」）");
  }
  if (bad.length) {
    console.log("CHAT GATE CHECK: FAIL - " + bad.join(" | "));
    process.exitCode = 1;
    return;
  }
  console.log("CHAT GATE CHECK: say 门控（logEnabled→chatOut）· 两出口（FORCE/CHAT_ON）· 声明顺序 · /eh log 常开 · 模块 P 读闸门 · 三语标签已改名");
};
