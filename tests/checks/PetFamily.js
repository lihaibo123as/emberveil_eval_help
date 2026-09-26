// tests/checks/PetFamily.js —— 宠物家族属性表 + 家族探针的源码检查（1.75.3 建）
// 用户需求：「查看 doc 下面那个图片（猎人宠物属性和技能图.jpg），分析下数据，看下如何整合到现在的抓宠助手内」。
// 为什么必须是源码检查：
//   ① 家族卡是**纯数据**（三加成 / 食物 / 天生技能三列），写错一格的表现是界面上一切正常、只是数字/技能不对；
//   ② 图片的「家族→技能」三列是**现成的约束表** —— 拿它反向校验 `ranks` 里 280 条驯服来源的 fam 标注，
//      能抓到生成期关键字猜错的那一类静默错标（e.g. 名字里带「狼」的**狼蛛**被判成狼族）。
//      本轮先**冻结现状冲突数**（只许减不许增），修正留给真机探针轮；
//   ③ 探针的接线（命令分支 / 存档残渣键 / 有界读数环）漏一处，游戏里就是「敲了命令没反应」而不报错。
// 判据：
//   ① families 表 = 图片 17 条（famOrder 顺序 = 图片行序）+ `other`（**故意没有三加成**：未收录 ≠ 0）；
//   ② 三加成 = 图片**绝对值夹具**（17×3，逐格）；食物 ⊆ 六类；每条家族至少一类食物；
//   ③ 技能三列里的技能名必须都存在于 `skills` 表（写野名字当场 FAIL —— 图片写「狂怒之嚎」而本表用「嚎叫」）；
//   ④ 家族图标逐条存在于本机图标清单（doc/图标路径清单.txt）；
//   ⑤ cname 别名不跨家族重复（一个别名只能属于一个家族，否则对账会随机命中）；
//   ⑥ **冲突基线**：图片技能列 → 允许家族集合；ranks 里每个驯服来源的 fam 必须落在集合内，冲突数 ≤ BASE；
//   ⑦ 探针接线：命令分支（含 /eh pet fam 别名）+ EVAL_PH_FAM_CMD + petProbe 残渣键 + 有界读数环；
//   ⑧ 三语齐全 4 个**动态拼接**的 PH_FAM_W_* 键（LANG KEY CHECK 扫不到拼接键）；
//   ⑨ 反向哨兵：PetData.lua 是生成物（手改会被下次生成冲掉）⇒ 文件头必须声明 + 生成器里必须有 FAM_STATS。
module.exports = function (root) {
  const fs = require('fs');
  const path = require('path');
  const p = path.join(root, 'PetData.lua');
  if (!fs.existsSync(p)) { console.log('PET FAMILY CHECK: skipped (no PetData.lua)'); return; }
  const src = fs.readFileSync(p, 'utf8');
  const genPath = path.join(root, 'gen_petdata.js');
  const phPath = path.join(root, 'PetHelper.lua');
  const bad = [];

  // ===== 图片夹具（doc/猎人宠物家族属性.md 的 17 行；dmg/armor/hp 绝对值）=====
  const IMG = [
    ['cat',         '猫科',   10,  0, -2],
    ['raptor',      '迅猛龙', 10,  3, -5],
    ['bat',         '蝙蝠',    7,  0,  0],
    ['owl',         '猫头鹰',  7,  0,  0],
    ['spider',      '蜘蛛',    7,  0,  0],
    ['windserpent', '风蛇',    7,  0,  0],
    ['gorilla',     '猩猩',    2,  0,  4],
    ['crab',        '螃蟹',   -5, 13, -4],
    ['scorpid',     '蝎子',   -6, 10,  0],
    ['bear',        '熊',     -9,  5,  8],
    ['boar',        '猪',    -10,  9,  4],
    ['turtle',      '乌龟',  -10, 13,  0],
    ['bird',        '食腐鸟',  0,  5,  0],
    ['crocolisk',   '鳄鱼',    0, 10, -5],
    ['hyena',       '土狼',    0,  5,  0],
    ['tallstrider', '陆行鸟',  0,  0,  5],
    ['wolf',        '狼',      0,  5,  0],
  ];
  const FOODS = ['面包', '奶酪', '鱼', '水果', '蘑菇', '肉'];
  const CONFLICT_BASE = 64; // ★冻结基线（1.75.3 实测）：只许减不许增；修正见 doc/猎人宠物家族属性.md §二

  // ===== 解析生成物：famOrder + families 段 =====
  const q = (s) => (s.match(/"([^"]*)"/g) || []).map(x => x.slice(1, -1));
  const om = src.match(/EVAL_PET_DB\.famOrder = \{ ([^}]*) \}/);
  if (!om) { console.log('PET FAMILY CHECK: FAIL - PetData.lua 里找不到 famOrder（生成器没 regenerate？）'); process.exitCode = 1; return; }
  const order = q(om[1]);
  const famSeg = src.slice(src.indexOf('EVAL_PET_DB.families'));
  const cards = {};
  // ★量词必须**懒惰**（`*?`）：`([^}]*) \}` 那种写法里贪婪量词会把 `\}` 前那个空格也吃掉 ⇒ 永远匹配不上
  //   （这里正好有「解析 0 条 ⇒ FAIL」的兜底，才没变成静默通过）。
  //   ★另一处同样的坑：`\},\s*\r?\n\s*dmg` 里贪婪的 `\s*` 会把换行也吃掉、后面的 `\r?\n` 就永远等不到
  //   ⇒ 段间一律只写 `\s*`（`\s` 本身就含换行），不再叠加 `\r?\n`；生成物是 LF，这样两种换行都吃得住。
  //   ★第三处：卡尾是 **三层收尾**（`sp` 表 + `sk` 表 + 家族表），少写一个 `\}` 就永远匹配不上。
  const cre = /(\w+) = \{ label = "([^"]+)", icon = "([^"]+)", cname = \{ ([^}]*?) \},\s*dmg = (-?\d+), armor = (-?\d+), hp = (-?\d+), foods = \{ ([^}]*?) \},\s*sk = \{ dmg = \{ ([^}]*?) \}, spd = \{ ([^}]*?) \}, sp = \{ ([^}]*?) \} \} \},/g;
  let m;
  while ((m = cre.exec(famSeg))) {
    cards[m[1]] = { label: m[2], icon: m[3], cname: q(m[4]), dmg: +m[5], armor: +m[6], hp: +m[7],
                    foods: q(m[8]), sk: { dmg: q(m[9]), spd: q(m[10]), sp: q(m[11]) } };
  }
  if (Object.keys(cards).length !== IMG.length) {
    console.log('PET FAMILY CHECK: FAIL - 家族卡解析出 ' + Object.keys(cards).length + ' 条，应为 ' + IMG.length +
      ' 条（★解析不到就 FAIL，绝不允许「匹配 0 条」被当成通过）');
    process.exitCode = 1;
    return;
  }
  // ① id / 顺序 / other 的反向哨兵
  if (order.length !== IMG.length) bad.push('famOrder 应为 ' + IMG.length + ' 条（图片行序），实际 ' + order.length);
  IMG.forEach(function (row, i) {
    if (order[i] !== row[0]) bad.push('famOrder 第 ' + (i + 1) + ' 项应为 ' + row[0] + '（图片行序），实际 ' + order[i]);
  });
  if (!/other = \{ label = "其他", icon = "[^"]+" \},/.test(famSeg)) {
    bad.push('families 里必须有 `other`（未归类桶）且**不带 dmg/armor/hp**（未收录 ≠ 0）');
  }
  if (/\n\s*other = \{[^}]*dmg = /.test(famSeg)) bad.push('`other` 不许带三加成字段（读不到就该说「未收录」，不能是 0）');

  // ② 三加成 = 图片夹具 + ③ 食物 + 技能名 =====
  const skillNames = {};
  const skSeg = src.slice(src.indexOf('EVAL_PET_DB.skills'), src.indexOf('EVAL_PET_DB.ranks'));
  for (const mm of skSeg.matchAll(/name = "([^"]+)"/g)) skillNames[mm[1]] = 1;
  const aliasOwner = {};
  for (const row of IMG) {
    const id = row[0], card = cards[id];
    if (!card) { bad.push('缺家族卡：' + id); continue; }
    if (card.label !== row[1]) bad.push(id + ' 名称应为图片用名「' + row[1] + '」，实际「' + card.label + '」');
    if (card.dmg !== row[2] || card.armor !== row[3] || card.hp !== row[4]) {
      bad.push(id + ' 三加成与图片不符：得到 ' + card.dmg + '/' + card.armor + '/' + card.hp +
        '，图片为 ' + row[2] + '/' + row[3] + '/' + row[4]);
    }
    if (!card.foods.length) bad.push(id + ' 食物列为空（图片里每族都有食物）');
    for (const f of card.foods) if (FOODS.indexOf(f) < 0) bad.push(id + ' 的食物「' + f + '」不在六类里（' + FOODS.join('/') + '）');
    for (const grp of ['dmg', 'spd', 'sp']) {
      for (const sk of card.sk[grp]) {
        if (!skillNames[sk]) bad.push(id + ' 的 ' + grp + ' 列技能「' + sk + '」不在 skills 表里（图片写「狂怒之嚎」而本表用「嚎叫」这类差异必须在此定案）');
      }
    }
    for (const al of card.cname) {
      if (aliasOwner[al] && aliasOwner[al] !== id) bad.push('家族别名「' + al + '」同时属于 ' + aliasOwner[al] + ' 与 ' + id + '（对账会随机命中）');
      aliasOwner[al] = id;
    }
  }

  // ④ 图标存在性（本机图标清单 = 游戏内 /eh go icons 采集）
  const wlPath = path.join(root, 'doc', '图标路径清单.txt');
  if (!fs.existsSync(wlPath)) bad.push('缺少 doc/图标路径清单.txt（图标存在性的唯一依据）');
  else {
    const have = {};
    for (const line of fs.readFileSync(wlPath, 'utf8').split(/\r?\n/)) {
      const t = line.trim();
      if (t && t[0] !== '#') have[t] = 1;
    }
    for (const id of Object.keys(cards)) if (!have[cards[id].icon]) bad.push(id + ' 的图标不在本机图标清单里：' + cards[id].icon);
  }

  // ⑥ 家族标注对账（图片「家族→技能」三列 = 约束表）
  //   口径（1.75.3 第二轮按用户「以最新的图片为准」重标后定）：
  //     · **具体家族**与图片冲突 ⇒ 必须**精确等于**已知例外表（多一条、少一条都 FAIL —— 少一条说明该更新例外表）
  //     · `other`（未归类）**不算冲突**：它是「图片给不出信号、待真机探针定案」的诚实表达 ⇒ **单独冻结条数**、只许减少
  //     · 图片与来源表真冲突、已排除出判据的技能 = 生成物里的 `skNoJudge`（**唯一来源**，不在这里再写一份）
  const skipSeg = src.match(/EVAL_PET_DB\.skNoJudge = \{([^}]*)\}/);
  if (!skipSeg) { console.log('PET FAMILY CHECK: FAIL - PetData.lua 里没有 skNoJudge（生成器没 regenerate？）'); process.exitCode = 1; return; }
  const noJudge = q(skipSeg[1]);
  if (noJudge.length !== 1 || noJudge[0] !== '畏缩') {
    bad.push('skNoJudge 应恰为 { 畏缩 }（图片只把畏缩列在猫科，而 12 条来源都教它）——实际 [' + noJudge.join(',') + ']');
  }
  const allowed = {};
  const imgSkills = {};
  for (const row of IMG) {
    const card = cards[row[0]];
    if (!card) continue;
    for (const grp of ['dmg', 'spd', 'sp']) for (const sk of card.sk[grp]) {
      imgSkills[sk] = 1;
      if (noJudge.indexOf(sk) >= 0) continue;      // ★非判据技能不参与约束
      (allowed[sk] = allowed[sk] || {})[row[0]] = 1;
    }
  }
  const CONFLICT_EXPECT = ['爪击 ← 尘泥钳嘴鳄鱼', '爪击 ← 猎行蛛', '爪击 ← 癞爪']; // 名字硬证据 2 条 + 用户定案 1 条（已核可）
  const UNCLASSIFIED_BASE = 0;  // ★1.75.3 收尾：10 只由用户逐只点名定案 ⇒ **未归类归零**（只许保持 0）
  const rankSeg = src.slice(src.indexOf('EVAL_PET_DB.ranks'), src.indexOf('EVAL_PET_DB.famOrder'));
  let cur = null, total = 0, unclassified = 0, nonImg = 0;
  const conflicts = [], seenFam = {};
  for (const line of rankSeg.split(/\r?\n/)) {
    const s = line.match(/^\s*\["([^"]+)"\] = \{\s*$/);
    if (s) { cur = s[1]; continue; }
    const b = line.match(/zone = "([^"]*)", name = "([^"]*)", level = "([^"]*)", fam = "([a-z]+)"/);
    if (b) {
      total++;
      seenFam[b[2]] = b[4];
      if (b[4] === 'other') { unclassified++; continue; }
      if (noJudge.indexOf(cur) >= 0) continue;            // 非判据技能（畏缩）不对账
      if (!imgSkills[cur]) { nonImg++; continue; }         // 图片三列里没有的技能（训练师技能等）不对账
      if (!allowed[cur] || !allowed[cur][b[4]]) conflicts.push(cur + ' ← ' + b[2]);
    }
  }
  if (total !== 280) bad.push('驯服来源条目数应为 280，实际 ' + total + '（解析口径变了？）');
  if (nonImg > 0) bad.push('有 ' + nonImg + ' 条来源挂在**图片三列里没有的技能**上（新技能没进图片约束表？）');
  const cs = conflicts.slice().sort(), ce = CONFLICT_EXPECT.slice().sort();
  if (cs.join('|') !== ce.join('|')) {
    bad.push('fam 标注与图片的冲突清单变了：得到 [' + cs.join('、') + ']，期望恰为 [' + ce.join('、') + ']' +
             '（新增冲突 = 有人改坏了标注；减少 = 该把例外表一起更新）');
  }
  if (unclassified > UNCLASSIFIED_BASE) {
    bad.push('未归类（fam=other）条数 ' + unclassified + ' > 冻结基线 ' + UNCLASSIFIED_BASE + '（只许减少）');
  }
  // ★抽查夹具：三种定案方式各取样 —— 谁把生成器退回旧版，这里当场红
  const SPOT = { '死亡狼蛛': 'spider', '疱爪土狼': 'hyena', '变异刺喉蛇': 'windserpent', '冬泉鸣枭': 'bird',
                 '鲁伯斯': 'wolf', '尘泥钳嘴鳄鱼': 'crocolisk', '山狗首领': 'wolf', '贝利格拉布': 'boar',
                 // ★用户 2026-09-25 逐只点名定案的（`FAM_USER`，优先级最高）：抽 3 只钉住
                 '癞爪': 'wolf', '森林潜伏者': 'spider', '邪恶的基塞伊斯': 'cat' };
  for (const nm of Object.keys(SPOT)) {
    if (seenFam[nm] === undefined) bad.push('抽查夹具里的野兽没找到：' + nm + '（来源表变了？）');
    else if (seenFam[nm] !== SPOT[nm]) bad.push('抽查不符：' + nm + ' 应为 ' + SPOT[nm] + '，实际 ' + seenFam[nm]);
  }

  // ⑦ 探针接线（漏一处 = 游戏里敲命令没反应，不报错）
  const ph = fs.existsSync(phPath) ? fs.readFileSync(phPath, 'utf8') : '';
  const eh = fs.readFileSync(path.join(root, 'EvalHelp.lua'), 'utf8');
  const core = fs.readFileSync(path.join(root, 'Core.lua'), 'utf8');
  if (ph.indexOf('function EVAL_PH_FAM_PROBE()') < 0) bad.push('PetHelper.lua 没有唯一读数入口 EVAL_PH_FAM_PROBE');
  if (ph.indexOf('function EVAL_PH_FAM_CMD(') < 0) bad.push('PetHelper.lua 没有命令入口 EVAL_PH_FAM_CMD');
  if (eh.indexOf('"^go 宠物家族"') < 0) bad.push('EvalHelp.lua 没有 /eh go 宠物家族 命令分支');
  if (eh.indexOf('"^pet fam"') < 0) bad.push('EvalHelp.lua 没有 /eh pet fam 别名分支');
  if (eh.indexOf('EVAL_PH_FAM_CMD(subF)') < 0) bad.push('命令分支没调用 EVAL_PH_FAM_CMD（敲了不会有反应）');
  if (core.indexOf('"petProbe"') < 0) bad.push('Core.lua 的调试残渣键清单里没有 petProbe（/eh 存档清理清不掉它）');
  if (!/table\.getn\(box\.out\) > PH_FAM_MAX/.test(ph)) bad.push('PetHelper.lua 的专属读数不是有界环（没有 PH_FAM_MAX 裁剪）');
  if (ph.indexOf('cfg.petProbe') < 0) bad.push('探针没有落存档 cfg.petProbe（调试日志环会被 [DS] 冲掉 ⇒ 事后读不回）');
  // ⑦b 家族图标 tooltip 的**接线**（用户截图需求）——纯函数写好了但没挂到真实 OnEnter = 悬停没反应，且不报错
  if (ph.indexOf('function EVAL_PH_FAM_TIP_LINES(') < 0) bad.push('PetHelper.lua 没有 tooltip 内容唯一来源 EVAL_PH_FAM_TIP_LINES');
  const iEnter = ph.indexOf('pcall(ib.SetScript, ib, "OnEnter"');
  if (iEnter < 0) bad.push('家族图标按钮没有挂 OnEnter（★纹理不吃鼠标事件 ⇒ 必须用覆盖它的 Button 才有 tooltip）');
  else {
    const enterBody = ph.slice(iEnter, iEnter + 700);
    if (enterBody.indexOf('EVAL_PH_FAM_TIP_LINES(') < 0) bad.push('图标 OnEnter 没有调 EVAL_PH_FAM_TIP_LINES（悬停出的是别的文案 = 两处真值）');
    if (enterBody.indexOf('PH.detRows[i]') < 0) bad.push('图标 OnEnter 没有按**当前行**取宠物（悬停会报别人家的家族）');
  }
  if (ph.indexOf('table.insert(PH.detWidgets, r.iconBtn)') < 0) bad.push('图标按钮没进 detWidgets 显式可见性清单（切视图会残留/不显示）');
  if (!/for _, w in ipairs\(\{ row\.bg, row\.icon, row\.iconBtn,/.test(ph)) bad.push('刷新时的隐藏清单漏了 iconBtn');
  // ★★「只 Hide 不 Show」= 1.73.1 那族事故（宠物行的名字元信息就是这么永远不显示的）⇒ 两处必须成对钉住
  if (ph.indexOf('pcall(row.iconBtn.Show, row.iconBtn)') < 0) bad.push('图标按钮只进了隐藏清单、没进显示清单（那一格永远不显示 —— 1.73.1 同款事故）');
  if (ph.indexOf('row.beast = nil') < 0) bad.push('空行没有清 row.beast（tooltip 会报上一屏那只宠物的家族）');

  // ⑦c 技能图标 = **宏图标号**（用户指定 6 个；号来自图标库悬停的「宏图标序号」）
  //   ★为什么必须源码级钉住：号**不能离线翻路径**（清单是按字母排序的白名单，行号 ≠ 号）⇒ 只能运行期解析；
  //     而「渲染忘了走解析口」= 界面照旧显示旧图标、**不报错**（本项目「接线漏接」那一族）。
  const SKILL_IDX_EXPECT = { bite: 139, claw: 255, howl: 695, charge: 700, shell: 710, shadowres: 133 };
  const skSeg2 = src.slice(src.indexOf('EVAL_PET_DB.skills'), src.indexOf('EVAL_PET_DB.ranks'));
  const idxSeen = {};
  for (const line of skSeg2.split(/\r?\n/)) {
    const mi = line.match(/\{ id = "(\w+)".*iconIdx = (\d+) \},/);
    if (mi) idxSeen[mi[1]] = +mi[2];
  }
  for (const id of Object.keys(SKILL_IDX_EXPECT)) {
    if (idxSeen[id] !== SKILL_IDX_EXPECT[id]) {
      bad.push('技能 ' + id + ' 的 iconIdx 应为 ' + SKILL_IDX_EXPECT[id] + '（用户指定），实际 ' + idxSeen[id]);
    }
  }
  for (const id of Object.keys(idxSeen)) {
    if (SKILL_IDX_EXPECT[id] === undefined) bad.push('技能 ' + id + ' 多了 iconIdx（只有用户指定的 6 个才该有号）');
  }
  // ⑦d 6 个号的**兜底纹理**必须是真机读数那一张（2026-09-25 用户配合跑出 `cfg.iconIdxProbe`）：
  //   号只是运行期解析入口；解析不到时退回 `skills[].icon` —— 兜底写错的表现是「界面上显示的是别的图」且不报错。
  //   真机读数（`/eh go 图标号` → 存档 cfg.iconIdxProbe）：
  //     撕咬 139 → Ability_Racial_Cannibalize ｜ 爪击 255 → Ability_Druid_Rake
  //     冲锋 700 → Ability_Hunter_Pet_Boar     ｜ 嚎叫 695 → Ability_Hunter_Pet_Wolf
  //     甲壳护盾 710 → Ability_Hunter_Pet_Turtle ｜ 暗影抗性 133 → Spell_Shadow_SealOfKings
  const SKILL_ICON_EXPECT = {
    bite: 'Ability_Racial_Cannibalize', claw: 'Ability_Druid_Rake', charge: 'Ability_Hunter_Pet_Boar',
    howl: 'Ability_Hunter_Pet_Wolf', shell: 'Ability_Hunter_Pet_Turtle', shadowres: 'Spell_Shadow_SealOfKings',
  };
  const iconSeen = {};
  for (const line of skSeg2.split(/\r?\n/)) {
    const mi = line.match(/\{ id = "(\w+)".*icon = "([^"]+)".*iconIdx = (\d+) \},/);
    if (mi) iconSeen[mi[1]] = mi[2];
  }
  for (const id of Object.keys(SKILL_ICON_EXPECT)) {
    const want = '/Game/Interface/Icons/' + SKILL_ICON_EXPECT[id] + '_TEX';
    if (iconSeen[id] !== want) bad.push('技能 ' + id + ' 的兜底纹理应为真机读数 ' + want + '，实际 ' + iconSeen[id]);
  }
  //   兜底纹理也得真存在于本机图标清单（写错路径 → 界面显示「?」，同样不报错）
  if (fs.existsSync(wlPath)) {
    const have2 = {};
    for (const line of fs.readFileSync(wlPath, 'utf8').split(/\r?\n/)) {
      const t = line.trim();
      if (t && t[0] !== '#') have2[t] = 1;
    }
    for (const v of Object.values(iconSeen)) if (!have2[v]) bad.push('技能兜底纹理不在本机图标清单里：' + v);
  }
  if (ph.indexOf('function EVAL_PH_SKILL_ICON(sk)') < 0) bad.push('PetHelper.lua 没有技能图标唯一解析口 EVAL_PH_SKILL_ICON');
  const iRes = ph.indexOf('function EVAL_PH_SKILL_ICON(sk)');
  const resBody = iRes >= 0 ? ph.slice(iRes, iRes + 900) : '';
  if (resBody.indexOf('GetMacroIconInfo') < 0) bad.push('解析口没用 GetMacroIconInfo（宏图标号的唯一合法入口）');
  // ★缓存检查要查**真正的读 + 写 + 命中即返回**三步，不能只查「名字出现过」——
  //   （实测：把 `local hit = PH_ICON_CACHE[idx]` 改成 `local hit = nil` 时，只查名字的版本照样通过 = 假绿）
  if (resBody.indexOf('local hit = PH_ICON_CACHE[idx]') < 0) bad.push('解析口没有**读**缓存（每次渲染都要问一遍宏图标表）');
  if (resBody.indexOf('PH_ICON_CACHE[idx] = hit') < 0) bad.push('解析口没有**写**缓存');
  if (resBody.indexOf('if hit then return hit end') < 0) bad.push('解析口缺少「命中即返回」（读出来却没用上）');
  if (/return sk\.icon/.test(resBody) === false) bad.push('解析口没有兜底（取不到号时必须退回语义路径，绝不编路径/留空白）');
  // ★渲染接线：两处渲染**必须**走解析口，且旧的「直接读 sk.icon」写法不许残留
  if (ph.indexOf('EVAL_PH_SKILL_ICON(e.skill)') < 0) bad.push('列表行图标没走解析口（界面会照旧显示旧图标且不报错）');
  if (ph.indexOf('EVAL_PH_SKILL_ICON(sk)') < 0) bad.push('详情大图标没走解析口');
  if (ph.indexOf('pcall(row.icon.SetTexture, row.icon, e.skill.icon)') >= 0) bad.push('列表行图标仍有一条绕过解析口的旧写法');
  if (ph.indexOf('pcall(PH.detIcon.SetTexture, PH.detIcon, sk.icon)') >= 0) bad.push('详情图标仍有一条绕过解析口的旧写法');
  // 取证命令 `/eh go 图标号`（用户 2026-09-25：「可以自己写命令我配合你扫一下」）：
  //   它默认报的必须是**界面渲染同一个解析口**的值（否则「命令说 A、界面画 B」= 两处真值）
  if (eh.indexOf('"^go 图标号"') < 0) bad.push('EvalHelp.lua 没有取证命令 `/eh go 图标号`（宏图标号离线查不出来，只能真机读）');
  //   ★两种写法都认：**裸调**（`EVAL_PH_SKILL_ICON(sk)`）与 **pcall 形态**（`pcall(EVAL_PH_SKILL_ICON, sk)` ——
  //     本项目 `PCALL CALL CHECK` 明确禁止把方法调用写进 pcall 里，探针里用的是后者）
  if (!/EVAL_PH_SKILL_ICON\(\s*sk\s*\)|EVAL_PH_SKILL_ICON,\s*sk/.test(eh)) bad.push('取证命令没有走渲染同一个解析口（会与界面显示不一致）');
  if (eh.indexOf('"^go icons "') < 0) bad.push('取证命令没有接 `go icons <号>` 这种写法');
  //   探针的「如实」三件套 + 截断 + **专属落盘**（少一件就变成静默/刷屏/AI 读不到）
  {
    const iIdx = eh.indexOf('"^go 图标号"');
    const body = iIdx >= 0 ? eh.slice(iIdx, iIdx + 6000) : '';
    // ★★★先剥注释：本段注释里**正当地**提到了 `iconIdxProbe` / `IDX_OUT_MAX` / 那些提示文案
    //   ⇒ 不剥注释时，把真正那几行删掉照样「通过」（变异 M29/M30 实测的**假绿**）。
    //   同族纪律见 `IO BTN LABEL CHECK` / `COMMENT SWALLOW`：**看代码，不看注释**。
    const code = body.split(/\r?\n/).map(l => { const i = l.indexOf('--'); return i >= 0 ? l.slice(0, i) : l; }).join('\n');
    // ★★★再剥**字符串字面量**（只给「接线类」判据用）：那句提示文案 `"读数已落存档 cfg.iconIdxProbe…"` 本身就是字符串，
    //   不剥的话把真正写环那一行删掉、只留文案，照样「通过」（变异 M29 实测的假绿）。
    //   ★但「如实文案」类判据（接口不存在 / 取不到 / 只报前）**恰恰要**在字符串里找 ⇒ 两者用不同的串，别一刀切。
    const codeNoStr = code.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/'(?:[^'\\]|\\.)*'/g, "''");
    const need = [['接口缺失如实报', '接口不存在'], ['号越界如实报', '取不到（号越界'], ['上限截断', '只报前 %d 个']];
    for (const [label, tok] of need) if (code.indexOf(tok) < 0) bad.push('取证命令缺「' + label + '」（' + tok + '）');
    // ★★读数必须**专属落盘**：1.75.9 实测——`say` 只进聊天框、**不落日志环**（say 与 logLine 是两个出口），
    //   而存档只在 /reload 落盘 ⇒ 探针不自己存一份，AI 侧就「一个字节都读不到」（用户跑完也只能干瞪眼）。
    //   ★判据一律盯**非字符串的代码**：① 真读/真写 `cfg.iconIdxProbe`；② 真的往环里 insert；③ 真有上限裁剪那条 while。
    if (!/\.iconIdxProbe\b/.test(codeNoStr)) bad.push('取证命令没有专属持久读数（cfg.iconIdxProbe）—— 聊天框 AI 读不到、日志环会被冲掉');
    if (!/table\.insert\(box\.out,\s*s\)/.test(codeNoStr)) bad.push('专属读数没有真的写入环（缺 table.insert(box.out, s)）');
    if (!/while\s+table\.getn\(box\.out\)\s*>\s*IDX_OUT_MAX/.test(codeNoStr)) bad.push('专属读数不是有界环（缺「> IDX_OUT_MAX 就 remove」那条 while）');
    if (core.indexOf('"iconIdxProbe"') < 0) bad.push('Core.lua 的调试残渣键清单里没有 iconIdxProbe（/eh 存档清理清不掉它）');
  }
  // ⑨ 生成物声明 + 生成器里的家族属性表（防手改 PetData.lua）
  if (src.indexOf('本文件是**生成物**') < 0) bad.push('PetData.lua 文件头没声明「生成物 + 生成器」（后人会直接手改，下次生成被冲掉）');
  if (!fs.existsSync(genPath)) bad.push('缺少生成器 gen_petdata.js');
  else {
    const gen = fs.readFileSync(genPath, 'utf8');
    if (gen.indexOf('const FAM_STATS = {') < 0) bad.push('gen_petdata.js 里没有 FAM_STATS（家族属性表必须在生成器里，而不是手写进生成物）');
    if (gen.indexOf('const FAM_ORDER = [') < 0) bad.push('gen_petdata.js 里没有 FAM_ORDER（图片行序的唯一来源）');
  }

  // ⑧ 动态拼接的语言键（LANG KEY CHECK 扫不到 "PH_FAM_W_" .. why 这种）必须在三语包里齐全
  const packs = {};
  for (const lg of ['zhCN', 'enUS', 'ruRU']) {
    const f = path.join(root, 'Locales', lg + '.lua');
    packs[lg] = fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split(/\r?\n/).map(l => l.replace(/--.*$/, '')).join('\n') : '';
  }
  for (const k of ['PH_FAM_W_NOAPI', 'PH_FAM_W_EMPTY', 'PH_FAM_W_ERROR', 'PH_FAM_W_NOTSTR']) {
    for (const lg of ['zhCN', 'enUS', 'ruRU']) {
      if (!new RegExp('(^|[\\s,])' + k + '\\s*=').test(packs[lg])) bad.push('语言包缺动态键：' + k + '@' + lg);
    }
  }

  if (bad.length) {
    for (const b of bad.slice(0, 12)) console.log('PET FAMILY CHECK: FAIL - ' + b);
    if (bad.length > 12) console.log('PET FAMILY CHECK: FAIL - ... 另有 ' + (bad.length - 12) + ' 条');
    process.exitCode = 1;
    return;
  }
  console.log('PET FAMILY CHECK: 家族卡 ' + IMG.length + ' 条（三加成 = 图片夹具 · 食物 ⊆ 六类 · 技能三列全在 skills 表 · 图标全在本机清单）· '
    + '别名不跨族 · fam 标注：冲突 ' + conflicts.length + ' 条（= 已核可例外表）· 未归类 ' + unclassified + '/' + total
    + '（冻结 ' + UNCLASSIFIED_BASE + '）· skNoJudge=[' + noJudge.join(',') + '] · 抽查 ' + Object.keys(SPOT).length
    + ' 只 · 探针与图标 tooltip 接线齐 + 动态语言键三语齐全');
};
