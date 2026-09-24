/**
 * quest/audit.js —— 数据审计（离线，用户 1.75.9 要求）
 *
 * 审计四件事（全部以 https://database.emberveil.org/quests 抓下来的页面为凭据）：
 *   A 装备链接：每件装备的 id↔名称、品质、部位/类型是否自洽（名字空 = 硬错误）
 *   B 任务链接：每个任务的 id↔名称、等级是否合理；奖励物品 id 是否都在物品表里
 *   C 双向一致：**列表页的奖励** vs **任务详情页的「选择一件/直接给予」**（两个独立来源交叉验，
 *              站点自己不一致也会被抓出来 —— 这种差异要么是站点数据问题，要么是我抓取解析错）
 *   D 任务线完整性：自动任务线的步骤是否 1..M 齐全、成员任务的「本系列第 N/M 部分」是否自洽
 *
 * 用法：node quest/audit.js            # 用缓存（快）
 *       node quest/audit.js --online   # 额外抽查 20 任务 + 20 物品**重新抓一次**对账（防止缓存过期）
 * 退出码：有硬错误 → 1（可直接当闸门跑）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
if (process.argv.includes('--online')) Q.bootstrap(__filename);

const CACHE = path.join(__dirname, 'cache');
const readJson = f => JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8'));
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const sweep = readJson('sweep_10_60.json');
  const detail = readJson('eq_summary.json');
  const eq = detail.eq || {}, notEq = detail.notEq || {};
  // ★系列从**全部任务详情缓存**读（与 build_bulk.js 同一口径）——eq_summary.series 是早期那一轮的快照，
  //   解析器修好后它已过期（实测：D 检查只看到 20 条，真实是 245 条）。
  const seriesOf = {};
  for (const f of fs.readdirSync(CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    let rec = null;
    try { rec = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8')); } catch (e) { continue; }
    if (rec && rec.series && rec.series.steps && rec.series.steps.length >= 2) {
      seriesOf[rec.id] = { id: rec.id, title: rec.title, part: rec.series.part, total: rec.series.total,
        steps: rec.series.steps, trusted: rec.series.trusted };
    }
  }
  // ★与生成器同口径：站点没给链接的步骤用「任务名 → id」补全（见 quest/resolve.js）
  const R = require('./resolve.js');
  const nameIndex = R.buildNameIndex(CACHE, sweep.quests);
  const seriesById = R.buildSeriesById(CACHE);
  for (const id of Object.keys(seriesOf)) {
    const filled = R.fillSeriesIds(seriesOf[id], nameIndex, seriesById);
    seriesOf[id].steps = filled.steps;
    seriesOf[id].trusted = filled.trusted;
    seriesOf[id].byName = filled.byName;
  }
  const hard = [], soft = [];
  const itemName = {}, itemRow = {};
  // 物品页拿不到名字的（白/灰无「拾取后绑定」行）→ 用任务详情页奖励链接里的名字兜底（与生成器同口径）
  const questItemName = {};
  const detailRw = {};
  for (const f of fs.readdirSync(CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    try {
      const r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8'));
      if (!r || !r.id) continue;
      const all = [...(r.choose || []), ...(r.receive || [])];
      const ids = all.map(x => x.id).filter(Boolean);
      if (ids.length) detailRw[r.id] = ids;
      for (const x of all) if (x.id && x.name && !questItemName[x.id]) questItemName[x.id] = x.name;
    } catch (e) {}
  }
  for (const [id, r] of Object.entries({ ...eq, ...notEq })) {
    const nm = r.n || questItemName[id] || '';
    itemName[id] = nm;
    itemRow[id] = { ...r, n: nm };
  }
  const sweepById = {};
  for (const q of sweep.quests) sweepById[q.id] = q;
  // 等级表（清单里算每条线的等级区间）：详情缓存的 level 优先，列表行补
  const lvlOfAll = {};
  for (const f of fs.readdirSync(CACHE)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    try {
      const r = JSON.parse(fs.readFileSync(path.join(CACHE, f), 'utf8'));
      if (r && r.id && r.level) lvlOfAll[r.id] = r.level;
    } catch (e) {}
  }
  for (const q of sweep.quests) if (!lvlOfAll[q.id]) lvlOfAll[q.id] = q.lv;
  const rwOf = q => [...new Set([...(q.rewards || []).map(r => r.id), ...(detailRw[q.id] || [])])];

  // 只审计「会被插件打包进去的」那批（与生成器同口径）：奖励里含**装备**判定的任务
  const shipped = sweep.quests.filter(q => rwOf(q).some(id => eq[id]));
  console.log(`待审：任务 ${shipped.length} · 装备 ${Object.keys(eq).length}`);

  // ---------- A 装备 ----------
  // A 装备：名字取「物品页 ∪ 任务详情页奖励链接」，两边都拿不到 ⇒ 生成器会剔除，这里按**提示**报（不是硬错误）
  let eqNoName = 0, eqBadQ = 0, eqNoSlot = 0;
  for (const [id, r] of Object.entries(eq)) {
    if (!r.n && !questItemName[id]) { soft.push(`装备 #${id} 两份来源都拿不到名字（生成器已剔除）`); eqNoName++; }
    if (!(r.q >= 0 && r.q <= 5)) { hard.push(`装备 #${id} 品质越界 q=${r.q}`); eqBadQ++; }
    if (!r.s && !(r.dps > 0)) { soft.push(`装备 #${id} ${r.n} 既无部位也无 DPS（可能是饰品/戒指，站点未给部位）`); eqNoSlot++; }
    const meta = (sweep.quests.flatMap(q => q.rewards).find(x => x.id === +id) || {});
    if (meta.icon && !/^[a-z0-9_]+$/i.test(meta.icon)) soft.push(`装备 #${id} 图标名异常 ${meta.icon}`);
    if (itemRow[id] && meta.q != null && itemRow[id].q != null && meta.q !== itemRow[id].q) {
      soft.push(`装备 #${id} ${r.n || questItemName[id]} 品质两份来源不一致：列表页 ${meta.q} vs 物品页 ${itemRow[id].q}`);
    }
  }

  // ---------- B 任务 + 奖励 id ----------
  let qNoName = 0, qBadLv = 0, rwMissing = 0, orphan = 0;
  const shippedIds = new Set(shipped.map(q => q.id));
  for (const q of shipped) {
    if (!q.name) { hard.push(`任务 #${q.id} 没有名称`); qNoName++; }
    if (!(q.lv >= 1 && q.lv <= 70)) { hard.push(`任务 #${q.id} ${q.name} 等级越界 lv=${q.lv}`); qBadLv++; }
    for (const id of rwOf(q)) if (!itemName[id]) { hard.push(`任务 #${q.id} ${q.name} 的奖励 #${id} 不在物品表里`); rwMissing++; }
  }
  // 装备必须有来源任务（否则「装备→做哪些任务」这条主线断）。
  // ★来源集 = 发货任务 ∪ **全部任务详情缓存**：种子/低等级前置任务不在 10-60 列表行里，
  //   但它们同样给装备（只看列表会误报「孤立装备」——实测 4 件）。
  const usedItems = new Set(shipped.flatMap(q => rwOf(q)));
  for (const ids of Object.values(detailRw)) for (const id of ids) usedItems.add(id);
  for (const id of Object.keys(eq)) if (!usedItems.has(+id)) { hard.push(`装备 #${id} ${eq[id].n || questItemName[id]} 没有任何来源任务（孤立物品）`); orphan++; }

  // ---------- C 列表页 vs 任务详情页 ----------
  let cmpN = 0, cmpDiff = [];
  for (const q of shipped) {
    const f = path.join(CACHE, `quest_${q.id}.json`);
    if (!fs.existsSync(f)) continue;
    const rec = JSON.parse(fs.readFileSync(f, 'utf8'));
    if (rec.error) continue;
    cmpN++;
    const listSide = new Set(q.rewards.map(r => r.id));
    const detailSide = new Set((detailRw[q.id] || []));
    const onlyList = [...listSide].filter(x => !detailSide.has(x));
    const onlyDetail = [...detailSide].filter(x => !listSide.has(x));
    if (onlyList.length || onlyDetail.length) {
      cmpDiff.push(`#${q.id} ${q.name}：仅列表页 ${onlyList.join(',') || '-'} / 仅详情页 ${onlyDetail.join(',') || '-'}`);
    }
  }

  // ---------- D 任务线完整性 ----------
  // D 的聚类规则必须与生成器**同口径**（步数相同 + id 集重叠 ≥60%）：否则会把「16 步版」和「17 步版」
  //   合成一个簇，然后报一堆「成员自报 total 不一致」——那是审计自己的错，不是数据的错（实测 63 条假问题）。
  const clusters = [];
  for (const rec of Object.values(seriesOf)) {
    if (!rec.total || rec.total < 2 || !rec.steps || !rec.steps.length) continue;
    if (rec.trusted === false) continue;
    const ids = rec.steps.map(s => s.id).filter(Boolean);
    if (ids.length < 2 || ids.length !== rec.total) continue;   // 与生成器同口径：不全的不算
    const idSet = new Set(ids);
    let best = null, bestJ = 0;
    for (const c of clusters) {
      if (c.total !== rec.total) continue;
      let inter = 0;
      for (const id of idSet) if (c.ids.has(id)) inter++;
      const j = inter / (idSet.size + c.ids.size - inter);
      if (j > bestJ) { bestJ = j; best = c; }
    }
    if (best && bestJ >= 0.6) {
      for (const id of idSet) best.ids.add(id);
      best.members.push(rec);
      if (ids.length > best.rec.steps.filter(s => s.id).length) best.rec = rec;
    } else {
      clusters.push({ total: rec.total, ids: idSet, rec, members: [rec] });
    }
  }
  let serBad = [], serN = 0, bigN = 0;
  for (const c of clusters) {
    serN++;
    const rec = c.rec;
    const steps = rec.steps.filter(s => s.id).sort((a, b) => a.n - b.n);
    if (steps.length !== rec.total) serBad.push(`[${steps[0].name}] 步骤数 ${steps.length} ≠ 站点自报总数 ${rec.total}`);
    for (let i = 0; i < steps.length; i++) if (steps[i].n !== i + 1) serBad.push(`[${steps[0].name}] 步骤序号不连续：第 ${i + 1} 位是 ${steps[i].n}`);
    for (const s of steps) if (!s.name) serBad.push(`[${steps[0].name}] 步骤 #${s.id} 没有名字`);
    // 同簇成员（同一步数、id 高度重叠）自报 total 必须一致
    for (const m of c.members) if (m.total !== rec.total) serBad.push(`[${steps[0].name}] 同簇成员 #${m.id} 自报 total=${m.total} ≠ ${rec.total}`);
    if (steps.length >= 10) bigN++;
  }

  // ---------- E 策展链 vs 站点（用户要求：「任务线是否完整」——人工策展的 22 条也要对站核实） ----------
  //   判据：每条策展链的任务序列能否在站点自报系列里找到，且**不多不少**（站点系列比策展多 = 我们漏了步骤）。
  const curated = require('./chains.js').CHAINS;
  const curReport = [], curHard = [], curSoft = [];
  let curExtended = 0;
  for (const c of curated) {
    const cached = c.quests.filter(id => seriesOf[id]).length;
    const sers = c.quests.map(id => seriesOf[id]).filter(r => r && r.total >= 2);
    // ★取「与策展 id 重合最多」的那条站点系列来比：策展链是**人工精选的子集**，
    //   站点常有更长的母系列（例：尖牙德鲁伊 ⊂ 哀嚎洞穴长线）——「站点更长」只作**可补全提示**，不是错。
    let best = null, bestHit = -1;
    for (const s of sers) {
      const ids = s.steps.filter(x => x.id).map(x => x.id);
      const hit = ids.filter(id => c.quests.indexOf(id) >= 0).length;
      if (hit > bestHit) { bestHit = hit; best = s; }
    }
    const siteIds = best ? best.steps.filter(x => x.id).map(x => x.id) : [];
    const missing = siteIds.filter(id => c.quests.indexOf(id) < 0);
    const extra = c.quests.filter(id => siteIds.indexOf(id) < 0);
    if (!cached) curSoft.push(`[${c.name}] 策展 ${c.quests.length} 步：站点未给系列块（独立任务/单步任务，无法核对）`);
    else if (!siteIds.length) curSoft.push(`[${c.name}] 策展 ${c.quests.length} 步 · 抓到详情 ${cached} 条：站点未标系列（独立任务，无法核对）`);
    else if (missing.length) {
      curExtended++;
      curReport.push(`[${c.name}] 策展 ${c.quests.length} 步 · 站点同系列 ${siteIds.length} 步 · 站点更长：还有 ${missing.length} 步未进策展（${missing.slice(0, 6).join(',')}）`);
    } else {
      curReport.push(`[${c.name}] 策展 ${c.quests.length} 步 · 站点同系列 ${siteIds.length} 步 · ✓ 与站点一致`);
    }
    if (extra.length && siteIds.length) curSoft.push(`[${c.name}] 策展有 ${extra.length} 个不在该站点系列里的任务（多为收尾单任务）：${extra.join(',')}`);
    for (const d of c.quests) {
      if (!sweepById[d] && !lvlOfAll[d]) curHard.push(`策展链 ${c.name} 的任务 #${d} 既不在 10-60 任务列表、也没有详情缓存（链接可疑）`);
    }
  }
  const curBad = curReport.filter(r => /站点更长/.test(r));

  // ---------- F 装备 ↔ 任务 双向链接（物品页「奖励来自」 vs 我们的来源任务） ----------
  const linkDiff = [];
  for (const id of Object.keys(eq)) {
    const r = itemRow[id] || eq[id];
    if (!r || !r.from) continue;
    const srcs = new Set(shipped.filter(q => rwOf(q).indexOf(+id) >= 0).map(q => q.name));
    if (!srcs.size) continue;
    if (!srcs.has(r.from)) linkDiff.push(`装备 #${id} ${itemName[id]}：物品页写「奖励来自 ${r.from}」，我们记的来源是「${[...srcs].slice(0, 2).join('/')}」`);
  }

  // ---------- G 经典/有意思的任务线清单 + 遗漏检测 ----------
  const CLASSIC = ['奥妮克希亚', '纳克萨玛斯', '熔火之心', '黑翼', '安其拉', '流沙', '节杖', '达隆郡', '林克', '爱与家庭',
    '米拉', '灰烬使者', '雷霆之怒', '奎尔塞拉', '泰坦', '通灵学院', '斯坦索姆', '厄运', '祖尔格拉布', '沉没的神庙',
    '玛拉顿', '奥达曼', '祖尔法拉克', '剃刀', '血色', '诺莫瑞根', '黑暗深渊', '哀嚎', '死亡矿井', '监狱', '影牙',
    '圣洁之书', '水之召唤', '火焰的召唤', '噬魂者', '旋风', '维里甘', '新月', '墓碑', '翼刃', '逃犯', '西部荒野法杖',
    '大地之冠', '失踪的使节', '斯塔文', '斯温', '莱恩', '信仰的试炼', '新的边疆', '黑暗笼罩'];
  const serNames = new Set();
  for (const c of clusters) {
    const steps = c.rec.steps.filter(s => s.id);
    for (const s of steps) { serNames.add(s.name); }
  }
  for (const q of sweep.quests) serNames.add(q.name);                       // 单任务也算（链条外的任务名）
  for (const q of sweep.quests) if (q.zone) serNames.add(q.zone);            // ★区域名也算命中（祖尔法拉克/斯坦索姆这种线名不带地名）
  for (const c of curated) serNames.add(c.name);                            // 策展链名
  for (const id of Object.keys(itemRow)) if (itemName[id]) serNames.add(itemName[id]); // 装备名（武器奖励也算命中）
  // ★1.12 里本来就**没有长任务线**的那几个（不是遗漏，如实说明，别让用户以为漏抓）：
  const NOT_A_CHAIN = { '黑翼': '1.12 黑翼之巢没有开门任务线（进本靠 UBRS 流程，不是任务链）',
    '灰烬使者': '1.12 灰烬使者只有纳克萨玛斯掉落，没有任务线', '祖尔格拉布': '1.12 祖尔格拉布只有硬币/声望重复任务，无长线' };
  const missingClassic = CLASSIC.filter(k => ![...serNames].some(n => n && n.indexOf(k) >= 0));
  // ★按**区域**清点任务线（副本/团本覆盖一眼可见）：地图/副本名 → 该区域的线
  const ZONES = ['斯坦索姆', '通灵学院', '祖尔法拉克', '玛拉顿', '厄运之槌', '黑石深渊', '黑石塔', '熔火之心',
    '奥妮克希亚的巢穴', '纳克萨玛斯', '安其拉', '祖尔格拉布', '沉没的神庙', '剃刀高地', '剃刀沼泽', '奥达曼',
    '诺莫瑞根', '死亡矿井', '哀嚎洞穴', '黑暗深渊', '影牙城堡', '血色修道院', '暴风城监狱', '希利苏斯', '东瘟疫之地'];
  const zoneInv = {};
  for (const c of clusters) {
    const steps = c.rec.steps.filter(s => s.id);
    const zs = new Set();
    for (const s of steps) { const q = sweepById[s.id]; if (q && q.zone) zs.add(q.zone); }
    for (const z of zs) {
      for (const Z of ZONES) if (z.indexOf(Z) >= 0) {
        (zoneInv[Z] = zoneInv[Z] || []).push({ name: steps[0].name, steps: steps.length });
      }
    }
  }
  const zoneLines = Object.keys(zoneInv).sort((a, b) => zoneInv[b].length - zoneInv[a].length)
    .map(z => `${z}(${zoneInv[z].length} 条线，最长 ${Math.max(...zoneInv[z].map(x => x.steps))} 步：${zoneInv[z].sort((a, b) => b.steps - a.steps).slice(0, 3).map(x => x.name).join('/')})`);
  const inventory = clusters.map(c => {
    const steps = c.rec.steps.filter(s => s.id);
    const names = steps.map(s => s.name);
    const lvs = steps.map(s => (lvlOfAll[s.id] || 0)).filter(v => v > 0);
    const open = /之门|节杖|开门|门扉|钥匙|传送门|流沙|入侵|纳克萨玛斯|黑翼|熔火|安其拉|奥妮克希亚|克尔苏加德|泰坦|奎尔塞拉|雷霆之怒|风剑|灰烬|史诗|传说/.test(names.join(' '));
    return { name: names[0], steps: steps.length, lo: lvs.length ? Math.min(...lvs) : 0, hi: lvs.length ? Math.max(...lvs) : 0, open };
  }).sort((a, b) => b.steps - a.steps);

  // ---------- 在线抽查 ----------
  const online = [];
  if (process.argv.includes('--online')) {
    console.log('在线抽查（重新抓 20 任务 + 20 物品对账）…');
    const pickQ = shipped.filter((_, i) => i % Math.max(1, Math.floor(shipped.length / 20)) === 0).slice(0, 20);
    const pickI = Object.keys(eq).filter((_, i) => i % Math.max(1, Math.floor(Object.keys(eq).length / 20)) === 0).slice(0, 20);
    for (const q of pickQ) {
      const html = await Q.fetchText(`${Q.BASE}/quest/${q.id}`);
      const rec = Q.parseQuestDetail(html, q.id);
      const okName = rec.title === q.name;
      online.push(`${okName ? '✓' : '✗'} 任务 #${q.id} 站上=「${rec.title}」本地=「${q.name}」`);
      if (!okName) hard.push(`在线对账失败：任务 #${q.id} 站上「${rec.title}」≠ 本地「${q.name}」`);
      await sleep(250);
    }
    for (const id of pickI) {
      const html = await Q.fetchText(`${Q.BASE}/item/${id}`);
      const rec = Q.parseItemDetail(html, +id);
      const okName = rec.name === eq[id].n;
      online.push(`${okName ? '✓' : '✗'} 装备 #${id} 站上=「${rec.name}」本地=「${eq[id].n}」`);
      if (!okName) hard.push(`在线对账失败：装备 #${id} 站上「${rec.name}」≠ 本地「${eq[id].n}」`);
      await sleep(250);
    }
  }

  // ---------- 报告 ----------
  for (const h of curHard) hard.push(h);   // ★必须先并入再写报告（否则打印的硬错误数比报告里多 —— 实测踩到）
  const out = {
    at: new Date().toISOString(),
    counts: { quests: shipped.length, equip: Object.keys(eq).length, series: serN, bigSeries: bigN, detailCompared: cmpN,
              curated: curated.length, curatedMismatch: curBad.length, questCaches: Object.keys(seriesOf).length },
    hard, soft, seriesIssues: serBad, listVsDetail: cmpDiff, online,
    curatedCheck: curReport, curatedSoft: curSoft, itemQuestLinkDiff: linkDiff, missingClassic, inventory, zoneInventory: zoneLines,
    notAChain: NOT_A_CHAIN,
  };
  fs.writeFileSync(path.join(CACHE, 'audit_report.json'), JSON.stringify(out, null, 1));
  console.log('\n=== 审计结果 ===');
  console.log('A 装备：', Object.keys(eq).length, '件 · 无名称', eqNoName, '· 品质越界', eqBadQ, '· 缺部位且非武器', eqNoSlot);
  console.log('B 任务：', shipped.length, '条 · 无名称', qNoName, '· 等级越界', qBadLv, '· 奖励缺失', rwMissing, '· 孤立装备', orphan);
  console.log('C 双向一致：比对', cmpN, '条任务 · 不一致', cmpDiff.length, '条（列表页截断显示，数据取并集）');
  console.log('D 任务线：', serN, '条（其中 ≥10 步的大型线', bigN, '条）· 完整性问题', serBad.length, '个');
  console.log('E 策展链核对：', curated.length, '条 · 站点同系列更长', curBad.length, '条 · 无法核对', curSoft.length, '条');
  for (const r of curReport.filter(r => /站点更长/.test(r))) console.log('   ' + r);
  for (const r of curSoft.slice(0, 6)) console.log('   · ' + r);
  console.log('F 装备↔任务链接：物品页「奖励来自」与我们的来源不一致', linkDiff.length, '条');
  if (linkDiff.length) console.log('   样例:', linkDiff.slice(0, 4).join('\n         '));
  console.log('G 任务线清单：共', inventory.length, '条 · 其中开门/史诗', inventory.filter(x => x.open).length, '条');
  console.log('   最长 12 条:', inventory.slice(0, 12).map(x => `${x.name}(${x.steps}步·Lv${x.lo}-${x.hi}${x.open ? '·开门/史诗' : ''})`).join(' · '));
  console.log('   ≥10 步的线:', inventory.filter(x => x.steps >= 10).map(x => `${x.name}(${x.steps})`).join(' · ') || '(无)');
  console.log('   经典关键词**未命中**:', missingClassic.length ? missingClassic.map(k => k + (NOT_A_CHAIN[k] ? '（' + NOT_A_CHAIN[k] + '）' : '')).join('、') : '(全部命中)');
  console.log('   按区域清点:', zoneLines.length ? zoneLines.slice(0, 14).join(' · ') : '(无)');
  if (cmpDiff.length) console.log('  C 不一致样例:', cmpDiff.slice(0, 4).join('\n              '));
  if (serBad.length) console.log('  D 任务线问题样例:', serBad.slice(0, 6).join('\n              '));
  if (online.length) console.log('  在线抽查:', online.slice(0, 6).join('\n            '));
  if (soft.length) console.log('  提示（非硬错误）', soft.length, '条；样例:', soft.slice(0, 4).join(' | '));
  console.log('报告 =', path.join(CACHE, 'audit_report.json'));
  console.log(hard.length ? `✖ 硬错误 ${hard.length} 条` : '✓ 无硬错误');
  if (hard.length) process.exitCode = 1;
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
