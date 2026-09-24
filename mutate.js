// ===== 用法（★默认**不跑全量**：全量 ≈ 每条 2 道闸门 × 26 条，很费时间，只在发版前或大改后跑）=====
//   node mutate.js --check        锚点自检（1 秒）：找出「锚点在源码里已不存在」的过期条目
//   node mutate.js M80            只跑指定编号（**加新判据时只跑这一条**）
//   node mutate.js M80 --fast     只跑 test_engine（跳过 luacheck，省一半时间；产出会明示）
//   node mutate.js --all          跑全部（慢！发版前 / 大改后才需要）
//   node mutate.js --list         只列清单（编号 + 说明）
//   不带参数 = 打印用法 + 跑一次锚点自检（避免误触全量）
// ★中断安全：跑之前把原文留在内存，SIGINT / 异常 / 正常退出都会**自动还原**
//   （本轮实测：全量跑被中断在 M72 ⇒ 源码被留在「泵不常驻开启」的变异态；现在由这里兜住）
const fs = require("fs");
const cp = require("child_process");

const MUT = [
  { id: "M56", why: "任务线列表退回写死 200 条上限（等级升序 ⇒ 30 级以上被截光）", file: "DataSearch.lua",
    from: "local QP_CHAIN_MAX = 0", to: "local QP_CHAIN_MAX = 200" },
  { id: "M57", why: "qpFillList 退回「局部函数声明位置即契约」（声明之后才赋值 ⇒ EVAL_QP_SCROLL 抓 nil）", file: "DataSearch.lua",
    from: "\n  qpFillList = function()", to: "\n  local function qpFillList()" },
  { id: "M58", why: "EVAL_QC_SEARCH 不再认 cap≤0=不限（浏览被截断）", file: "quest/QuestChains.lua",
    from: "\n  if max <= 0 then max = math.huge end", to: "" },
  { id: "M59", why: "列表调用退回字面量 200（绕过 QP_CHAIN_MAX 单一来源）", file: "DataSearch.lua",
    from: "EVAL_QC_SEARCH(q, QP_CHAIN_MAX, ", to: "EVAL_QC_SEARCH(q, 200, " },
  { id: "M60", why: "只保留前向声明、去掉「先声明后赋值」的注释守卫（结构不变式仍在，但写法退化）", file: "DataSearch.lua",
    from: "  local qpFillList\r\n", to: "" },
  { id: "M61", why: "在 qpFillList 声明之前引用它（LOCAL ORDER CHECK 必须抓：真机就是红字 attempt to call global）", file: "DataSearch.lua",
    from: "  local QP_ANIM_DECAY, QP_ANIM_SNAP = 0.55, 0.6",
    to: "  local function qpEarlyProbeM61() qpFillList() end\r\n  local QP_ANIM_DECAY, QP_ANIM_SNAP = 0.55, 0.6" },
  { id: "M62", why: "探针自查行把任务线条数写死 200（用户就再也分不清载入的是哪一版）", file: "DataSearch.lua",
    from: "      table.getn(qAll), table.getn(EVAL_QC_LIST() or {}), qSer, qTop))",
    to: "      200, table.getn(EVAL_QC_LIST() or {}), qSer, qTop))" },
  { id: "M63", why: "统一排序去掉「等级」这一键（退回两块拼接顺序 ⇒ 30 → 4 的回头）", file: "quest/QuestChains.lua",
    from: "  table.sort(dec, function(a, b)\n    if a.lo ~= b.lo then return a.lo < b.lo end\n    if a.r ~= b.r then return a.r < b.r end\n    return a.n < b.n\n  end)\n  local out = {}",
    to: "  table.sort(dec, function(a, b)\n    if false then return a.lo < b.lo end\n    if a.r ~= b.r then return a.r < b.r end\n    return a.n < b.n\n  end)\n  local out = {}" },
  { id: "M64", why: "详情记录退回「另拼一份」（少给 qs ⇒ 同一条线 列表行色 ≠ 详情色）", file: "quest/QuestChains.lua",
    from: "    c = qcSeriesRec(s, idx),",
    to: "    c = { k = key, n = s.n, t = s.t, z = s.z, lo = s.lo, hi = s.hi, open = s.open }," },
  { id: "M65", why: "等级档退回 6 档（50+ 吞掉 60 档）", file: "DataSearch.lua",
    from: "    { k = \"L3\", lo = 30, hi = 39 }, { k = \"L4\", lo = 40, hi = 49 }, { k = \"L5\", lo = 50, hi = 59 },\r\n    { k = \"L6\", lo = 60, hi = 999 },\r\n  }",
    to: "    { k = \"L3\", lo = 30, hi = 39 }, { k = \"L4\", lo = 40, hi = 49 }, { k = \"L5\", lo = 50, hi = 999 },\r\n  }" },
  { id: "M66", why: "等级筛选选择不生效（F1 写死 ALL ⇒ 用户要求「等级筛选在最左」形同虚设）", file: "DataSearch.lua",
    from: "      DS.qpLv = QP_LV[pi] and QP_LV[pi].k or \"ALL\"",
    to: "      DS.qpLv = \"ALL\"" },
  { id: "M67", why: "去掉「策展链 ↔ 自报系列」去重（列表里同一条线出两行同名）", file: "quest/QuestChains.lua",
    from: "      if table.getn(steps) >= 2 and not qcSeriesCovered(steps, p[1]) then",
    to: "      if table.getn(steps) >= 2 then" },
  { id: "M68", why: "请求泵「先消费队列再取工具柄」（拿不到柄时静默丢件 = 用户报的「不再检索装备」）", file: "DataSearch.lua",
    from: "    if not wtt or not may or type(wtt.SetHyperlink) ~= \"function\" then\r\n      st.blocked = (st.blocked or 0) + 1          -- 如实记「这次没法要」；队列**不动**\r\n      st.at = now                                  -- 这条路径也限频，别每帧刷\r\n      return\r\n    end\r\n    table.remove(st.q, idx)\r\n",
    to: "    table.remove(st.q, idx)\r\n    if not wtt or not may or type(wtt.SetHyperlink) ~= \"function\" then\r\n      st.blocked = (st.blocked or 0) + 1\r\n      st.at = now\r\n      return\r\n    end\r\n" },
  { id: "M69", why: "请求泵不限频（每帧抽一件 ⇒ 轰服务器）", file: "DataSearch.lua",
    from: "    if (now - (st.at or 0)) < QP_REQ_RATE then return end",
    to: "    if (now - (st.at or 0)) < 0 then return end" },
  { id: "M70", why: "请求泵挂回弹窗子级（弹窗显隐一异常，OnUpdate 就静默停摆）", file: "DataSearch.lua",
    from: "local qpPump = CreateFrame(\"Frame\", nil, UIParent)",
    to: "local qpPump = CreateFrame(\"Frame\", nil, qp)" },
  { id: "M71", why: "工具柄退回读全局名 EVAL_HELP_WTT（退化路径下恒 nil ⇒ 泵什么都不做）", file: "DataSearch.lua",
    from: "    if type(EVAL_WTT_HANDLE) == \"function\" then wtt = EVAL_WTT_HANDLE()\r\n    else wtt = rawget(_G, \"EVAL_HELP_WTT\") end",
    to: "    wtt = rawget(_G, \"EVAL_HELP_WTT\")" },
  { id: "M72", why: "请求泵不常驻开启（退回「随弹窗 Hide」⇒ 显隐漏一处泵就永远停摆）", file: "DataSearch.lua",
    from: "  pcall(qpPump.Show, qpPump)\r\n", to: "" },
  { id: "M73", why: "EVAL_QP_HIDE 又去 Hide 请求泵", file: "DataSearch.lua",
    from: "    st.frame:Hide()\r\n  end\r\n\r\n  function EVAL_QP_TOGGLE()",
    to: "    if st.qcPump then st.qcPump:Hide() end\r\n    st.frame:Hide()\r\n  end\r\n\r\n  function EVAL_QP_TOGGLE()" },
  { id: "M74", why: "任务线搜索不把种类集合传进数据层（用户要求「档位过滤改用装备那边的种类过滤」失效）", file: "DataSearch.lua",
    from: "EVAL_QC_SEARCH(q, QP_CHAIN_MAX, { faction = DS.qpFact, kinds = DS.qpKinds, loMin = lv.lo, loMax = lv.hi })",
    to: "EVAL_QC_SEARCH(q, QP_CHAIN_MAX, { faction = DS.qpFact, loMin = lv.lo, loMax = lv.hi })" },
  { id: "M75", why: "数据层种类判据恒真（任务线「类型」筛选形同虚设）", file: "quest/QuestChains.lua",
    from: "    if it and EVAL_QC_KIND_PASS(kset, EVAL_QC_ITEM_KIND(it)) then return true end\n  end\n  return false\nend",
    to: "    if it and EVAL_QC_KIND_PASS(kset, EVAL_QC_ITEM_KIND(it)) then return true end\n  end\n  return true\nend" },
  { id: "M76", why: "点占位图标直接开详情（用户要求：点它 = 插队优先扫描）", file: "DataSearch.lua",
    from: "        if row.rwPh[slot] then qpReqPriority(id) else EVAL_QP_ITEM_DETAIL(id) end",
    to: "        EVAL_QP_ITEM_DETAIL(id)" },
  { id: "M77", why: "优先刷新插到队**尾**而不是队首（「优先扫描」失效）", file: "DataSearch.lua",
    from: "    table.insert(q, 1, id)",
    to: "    table.insert(q, id)" },
  { id: "M78", why: "未扫描出的装备不画占位图（回到「什么都不画」）", file: "DataSearch.lua",
    from: "          local tex, isPh = qpItemTexPh(ids[j])\r\n          if tex then",
    to: "          local tex, isPh = qpItemTex(ids[j]), false\r\n          if tex then" },
  { id: "M79", why: "队列重排退化成「只过滤不排序」（顺序仍是行序 ⇒ 后面的行图标迟迟不出）", file: "DataSearch.lua",
    from: "        table.sort(dec, function(a, b) return a.r < b.r end)\r\n",
    to: "" },
  { id: "M80", why: "上限退回「入队时按行序截断 24」（后面的行连排队资格都没有 ⇒ ⑧bb 必须红）", file: "DataSearch.lua",
    from: "      if not dup then table.insert(st.q, id) end",
    to: "      if table.getn(st.q) >= QP_REQ_MAX then return nil end\r\n      if not dup then table.insert(st.q, id) end" },
  { id: "M81", why: "截断挪到**排序之前**（等于只重排已按行序占满的那 24 格 ⇒ 后面的行照样排不上）", file: "DataSearch.lua",
    from: "        local dec = {}",
    to: "        qpReqTrim()\r\n        local dec = {}" },
];

// ===== 中断安全：原文常驻内存，任何退出路径都先还原 =====
let DIRTY = null;                        // { file, orig }
function restoreNow() {
  if (DIRTY) { try { fs.writeFileSync(DIRTY.file, DIRTY.orig); } catch (e) { /* 尽力而为 */ } DIRTY = null; }
}
process.on("exit", restoreNow);
process.on("SIGINT", () => { restoreNow(); console.log("\n★ 收到中断 → 已还原源码"); process.exit(130); });
process.on("SIGTERM", () => { restoreNow(); process.exit(143); });
process.on("uncaughtException", (e) => { restoreNow(); console.error("★ 异常 → 已还原源码: " + (e && e.message)); process.exit(1); });

const GATES = [["node", ["luacheck.js"]], ["node", ["test_engine.js"]]];
function runGate(cmd, args) {
  return new Promise((res) => {
    cp.execFile(cmd, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
      let code = 0;
      if (err) code = (typeof err.code === "number") ? err.code : 99;
      res({ name: args[0], code, txt: String(stdout || "") + String(stderr || "") });
    });
  });
}
// 两道闸门**并行**跑（互不依赖）——比串行省近一半时间；--fast 只跑 test_engine
function gates(fast) {
  const list = fast ? [GATES[1]] : GATES;
  return Promise.all(list.map(([c, a]) => runGate(c, a)));
}

const argv = process.argv.slice(2);
const fast = argv.includes("--fast");
const want = argv.filter(a => a[0] !== "-");
// 锚点自检：条目所锚的源码若已被后续版本改写，这条变异就**永远 SKIP**（过期套件，只会白占清单）
//   node mutate.js --check
function anchorCheck() {
  let stale = 0, live = 0;
  for (const m of MUT) {
    const src = fs.readFileSync(m.file, "utf8");
    if (src.indexOf(m.from) < 0) { stale++; console.log("STALE  " + m.id + "  " + m.file + "  " + m.why); }
    else live++;
  }
  console.log("锚点自检: 有效 " + live + " / 过期 " + stale + " / 共 " + MUT.length);
  return stale;
}
if (argv.includes("--list")) {
  for (const m of MUT) console.log(m.id + "  " + m.file + "  " + m.why);
  console.log("共 " + MUT.length + " 条（加新判据时只跑你新加的那条：node mutate.js M80）");
  process.exit(0);
}
if (argv.includes("--check")) process.exit(anchorCheck() ? 1 : 0);
if (!want.length || argv.includes("--all")) {
  if (!want.length) {
    console.log("用法：--check 锚点自检 · M80 只跑指定编号 · --all 全量（慢）· --list 列清单 · 追加 --fast 只跑 test_engine");
    console.log("（不带参数**不再**默认全量：全量 = " + MUT.length + " 条 × 2 道闸门，只在发版前/大改后跑）\n");
    process.exit(anchorCheck() ? 1 : 0);
  }
  console.log("★ 全量 " + MUT.length + " 条" + (fast ? "（--fast：只跑 test_engine）" : "（两道闸门，逐条跑）") + "…");
}
let survived = 0;
const failRe = /: FAIL|ASSERT FAIL|LOAD ERROR|RUNTIME ERROR/;
for (const m of MUT) {
  if (want.length && !want.includes(m.id)) continue;
  const orig = fs.readFileSync(m.file, "utf8");
  if (orig.indexOf(m.from) < 0) { console.log(m.id + "  SKIP：找不到锚点（" + m.file + "）"); continue; }
  DIRTY = { file: m.file, orig };
  fs.writeFileSync(m.file, orig.replace(m.from, m.to));
  const res = await gates(fast);
  const hit = res.filter(r => r.code !== 0 || failRe.test(r.txt));
  const detail = hit.map(r => r.name + "=" + r.code + (failRe.test(r.txt) ? "(文本含失败)" : "")).join(" · ");
  console.log(m.id + "  " + (hit.length ? "CAPTURED" : "SURVIVED") + "  [" + detail + "]  " + m.why);
  // 把「是哪张网抓到的」也摊开（源码检查 / 行为断言互补，缺一就有盲区）
  for (const r of res) {
    const lines = r.txt.split(/\r?\n/).filter(l => failRe.test(l)).slice(0, 5);
    for (const l of lines) console.log("      " + r.name + " | " + l.trim().slice(0, 170));
  }
  if (!hit.length) survived++;
  fs.writeFileSync(m.file, orig);   // 还原：用运行前内存原文
  DIRTY = null;
}
// 还原后再跑一遍，确认环境已复原
const back = await gates(fast);
console.log("还原后: " + back.map(r => r.name + "=" + r.code).join(" ") + (survived ? "  ★ 有 " + survived + " 条存活" : ""));
