// tests/checks/Track.js —— 追踪候选表 + 追踪条件语言键的源码检查（1.75.3 建，1.75.6 扩）
// 用户需求：「分析API 排查 玩家追踪效果.草药,采矿,野兽之类的」→「条件类型 → 自身状态 → 追踪类型，下拉单选」。
// 为什么必须是源码检查：TRK.hint 是**纯数据**（探针与条件求值都拿它比对），写错一格的表现是
//   「③ 种类：没命中候选表」或「条件永远不成立」——看着像「客户端没这个追踪 / 没在追踪」，其实是表里错了一个字母。
// 判据：
//   ① Engine.lua 的 TRK.hint 必须是 4 列（id / 基础名 / 英文名 / 中文名）+ 13 条 + id 与基础名都不重复；
//   ② 每个基础名必须在**本机图标清单**（doc/图标路径清单.txt，真机 /eh go icons 采集）里逐条存在；
//   ③ 反向哨兵：基础名列不许出现路径或 _TEX 后缀（匹配走 EVAL_TRACK_BASE 归一，表里只放基础名）；
//   ④ id 是**语言无关的稳定键**，界面标签走运行时拼键 L(TRK_ 拼接 ID) ⇒ LANG KEY CHECK 扫不到它，
//      所以这里**逐条核对三语包齐全**（缺一个键 = 界面直接显示 TRK_BEAST 这种内部标识，纯静默失败）。
module.exports = function (root) {
  const fs = require('fs');
  const path = require('path');
  const engPath = path.join(root, 'Engine.lua');
  if (!fs.existsSync(engPath)) { console.log('TRACK ICON CHECK: skipped (no Engine.lua)'); return; }
  const eng = fs.readFileSync(engPath, 'utf8');
  const listPath = path.join(root, 'doc', '图标路径清单.txt');
  if (!fs.existsSync(listPath)) {
    console.log('TRACK ICON CHECK: FAIL - 缺少 doc/图标路径清单.txt（游戏内 /eh go icons 采集所得，是图标存在性的唯一依据）');
    process.exitCode = 1;
    return;
  }
  const bad = [];
  const iS = eng.indexOf('hint = {');
  const iE = iS >= 0 ? eng.indexOf('\n  },', iS) : -1;
  if (iS < 0 || iE < 0) {
    console.log('TRACK ICON CHECK: FAIL - Engine.lua 里找不到 TRK.hint 表（探针/条件的候选表被删了？）');
    process.exitCode = 1;
    return;
  }
  const body = eng.slice(iS, iE);
  const rows = [];
  for (const m of body.matchAll(/\{\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\s*\}/g)) {
    rows.push({ id: m[1], base: m[2], en: m[3], zh: m[4] });
  }
  if (rows.length !== 13) bad.push('候选表应为 13 条（官方数据库实证的追踪法术数），实际 ' + rows.length + ' 条');
  const seenId = {}, seenBase = {}, have = {};
  for (const line of fs.readFileSync(listPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t[0] === '#') continue;
    const b = t.replace(/^.*\//, '').replace(/_TEX$/i, '').toLowerCase();
    if (b) have[b] = 1;
  }
  for (const r of rows) {
    if (!/^[a-z][a-z0-9_]*$/.test(r.id)) bad.push('候选表第 1 列必须是**稳定 id**（小写 ascii）：' + r.id);
    if (seenId[r.id]) bad.push('候选表里 id 重复：' + r.id);
    seenId[r.id] = 1;
    if (!r.base) bad.push('候选表有一行缺基础名');
    if (seenBase[r.base]) bad.push('候选表里基础名重复：' + r.base);
    seenBase[r.base] = 1;
    if (r.base.indexOf('/') >= 0 || /_TEX$/i.test(r.base)) {
      bad.push('候选表只能放**基础名**（' + r.base + '）：匹配走 EVAL_TRACK_BASE 归一，别在表里写路径/后缀');
    }
    if (!have[r.base.toLowerCase()]) bad.push('本机图标清单里**没有**这个图标：' + r.base + '（' + r.id + '）⇒ 真机上永远匹配不上');
  }
  const packs = {};
  for (const lg of ['zhCN', 'enUS', 'ruRU']) {
    const f = path.join(root, 'Locales', lg + '.lua');
    // ★必须先剥注释再查键：把 `-- TRK_HERB = "采药"` 注释掉的那种「键没了」也是缺键
    //   （变异 M3 实测：不剥注释时这一条**漏网** —— 正则照样在注释行里匹配到 TRK_HERB =）
    packs[lg] = fs.existsSync(f)
      ? fs.readFileSync(f, 'utf8').split(/\r?\n/).map(l => l.replace(/--.*$/, '')).join('\n')
      : '';
  }
  const keys = ['TRK_ANY', 'CT_TRACKING', 'TRK_LIVE_FMT', 'TRK_NONE'];
  for (const r of rows) keys.push('TRK_' + r.id.toUpperCase());
  for (const k of keys) {
    for (const lg of ['zhCN', 'enUS', 'ruRU']) {
      const re = new RegExp('(^|[\\s,])' + k + '\\s*=');
      if (!re.test(packs[lg])) bad.push('语言包缺键：' + k + '@' + lg + '（L() 会直接显示键名 = 静默失败）');
    }
  }
  if (bad.length) {
    for (const b of bad.slice(0, 12)) console.log('TRACK ICON CHECK: FAIL - ' + b);
    process.exitCode = 1;
    return;
  }
  console.log('TRACK ICON CHECK: ' + rows.length + ' 条追踪候选图标（id/基础名/en/zh 四列）逐条在本机图标清单里存在 · '
    + keys.length + ' 个追踪语言键三语齐全');
};
