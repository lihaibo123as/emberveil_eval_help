/**
 * quest/curate_classic.js —— 把 **30-60 经典任务线**整理进策展清单（quest/chains.js）
 *
 * 背景（用户 1.75.15）：「策展链（EVAL_QC_LIST）只有扫描到 30，现在再增加 30-60 的经典任务线整理扫描」。
 *   策展清单此前 22 条、lo 全 ≤30；30-60 只有站点自报系列（自动拼、无点评/无人工档位）。
 *
 * 做法（数据源唯一 = 站点抓下来的 QuestBulk.lua）：
 *   ① 取自报系列（名/lo/hi/地区/档位/步骤 id）
 *   ② **跳过已被现有策展链整条覆盖的系列**（避免列表里同一条线出两行）
 *   ③ 入选 = 步骤 ≥3 且（命中经典关键词 或 步骤 ≥6），且 hi ≥30、lo ≤60（30-60 段）
 *   ④ 按「步骤数」降序取前 N（默认 30），生成 chains.js 条目追加到生成块里
 *
 * 用法：node quest/curate_classic.js            # 干跑：只打印候选与统计（不改文件）
 *       node quest/curate_classic.js --write    # 写入 chains.js 的生成块（幂等：整块替换）
 *       node quest/curate_classic.js --write --max 40
 *
 * 写完要跑：node quest/build.js（重新生成 QuestData.lua）→ node quest/audit.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const BULK = path.join(__dirname, 'QuestBulk.lua');
const CHAINS = path.join(__dirname, 'chains.js');
const BEGIN = '  // ===== 30-60 经典线（quest/curate_classic.js 生成，勿手改；改完重跑该脚本）=====';
const END = '  // ===== 生成块结束 =====';

/** 经典关键词（命中系列名或地区即视为「经典线」） */
const KEYS = [
  '黑石', '深渊', '熔火', '奥妮克希亚', '黑龙', '龙火', '温德索尔', '达基萨斯', '比修',
  '安其拉', '流沙', '甲虫', '祖尔格拉布', '哈卡', '尤亚姆巴', '通灵', '斯坦索姆', '厄运',
  '玛拉顿', '祖尔法拉克', '沉没的神庙', '阿塔哈卡', '剃刀', '奥达曼', '诺莫瑞根',
  '冬泉', '霜刃', '西瘟疫', '东瘟疫', '燃烧平原', '费伍德', '安戈洛', '希利苏斯',
  '塔纳利斯', '辛特兰', '菲拉斯', '艾萨拉', '诅咒之地', '悲伤沼泽', '尘泥沼泽',
  '凄凉之地', '千针石林', '荆棘谷', '阿拉希', '奥特兰克', '荒芜之地',
  '弗丁', '白银之手', '提尔', '塞纳里奥', '木喉', '瑟银', '米拉', '泰坦', '龙王',
  '开门', '钥匙', '节杖', '史诗', '传说', '职业武器',
];

/** 节日/活动线不是「经典任务线」，剔掉 */
const SKIP = ['春节', '新年', '冬幕', '情人节', '儿童周', '收获节', '万圣节', '感恩节', '美酒节', '暗月'];

function parseBulk() {
  const src = fs.readFileSync(BULK, 'utf8');
  const grab = key => {
    const i = src.indexOf('\n' + key + '={');
    if (i < 0) return [];
    const j = src.indexOf('\n},', i);
    const body = src.slice(i, j < 0 ? src.length : j);
    const out = [];
    const re = /\[(\d+)\]="((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = re.exec(body))) out.push({ id: +m[1], p: m[2].split('|') });
    return out;
  };
  const arr = (key, endKey) => {
    const i = src.indexOf('\n' + key + '={');
    if (i < 0) return [];
    const j = endKey ? src.indexOf('\n' + endKey + '={', i) : -1;
    return (src.slice(i, j < 0 ? src.length : j).match(/"(?:[^"\\]|\\.)*"/g) || [])
      .map(s => s.slice(1, -1).split('|'));
  };
  const quests = {};
  for (const q of grab('q')) quests[q.id] = { n: q.p[0], lv: parseInt(q.p[1], 10) || 0, z: q.p[2] || '', f: q.p[3] || '', rw: (q.p[4] || '').split(',').map(Number).filter(Boolean) };
  const equip = {};
  for (const it of grab('i')) equip[it.id] = it.p[9] === '1';   // 第 10 段 = 是否装备（build_bulk 的 eq 标记）
  const items = {};
  for (const it of grab('i')) items[it.id] = { q: parseInt(it.p[1], 10) || 1, dps: parseFloat(it.p[3]) || 0, eq: it.p[9] === '1' };
  const series = arr('s', 'sn').map(p => ({
    n: p[0], lo: parseInt(p[1], 10) || 0, hi: parseInt(p[2], 10) || 0, z: p[3] || '',
    t: p[4] || 'B', open: p[5] === '1', steps: (p[6] || '').split(',').map(Number).filter(Boolean),
  }));
  return { quests, equip, items, series };
}

function main() {
  const write = process.argv.includes('--write');
  const mi = process.argv.indexOf('--max');
  const MAX = mi > 0 ? parseInt(process.argv[mi + 1], 10) || 30 : 30;

  const { quests, equip, items, series } = parseBulk();
  // ★「现有策展链」= **人手写的那部分**（把生成块先摘掉再数）——否则脚本第二次跑会把自己的产物
  //   当成「已覆盖」，候选池当场塌掉（首次实测：688 → 46 条候选）。
  const srcChains0 = fs.readFileSync(CHAINS, 'utf8');
  const bi = srcChains0.indexOf(BEGIN);
  const bj = bi >= 0 ? srcChains0.indexOf(END, bi) : -1;
  const handSrc = (bi >= 0 && bj > bi) ? srcChains0.slice(0, bi) + srcChains0.slice(bj + END.length) : srcChains0;
  const curated = [...handSrc.matchAll(/quests:\s*\[([^\]]*)\]/g)]
    .map(m => ({ quests: m[1].split(',').map(s => parseInt(s.trim(), 10)).filter(Boolean) }));
  const curatedSteps = new Set();
  for (const c of curated) for (const id of c.quests) curatedSteps.add(id);

  const covered = s => s.steps.length > 0 && s.steps.every(id => curatedSteps.has(id));
  const faction = s => {
    let a = false, h = false;
    for (const id of s.steps) { const q = quests[id]; if (!q) continue; if (q.f === 'A') a = true; else if (q.f === 'H') h = true; }
    return (a && !h) ? 'A' : (h && !a) ? 'H' : 'B';
  };
  const hitKey = s => KEYS.find(k => s.n.indexOf(k) >= 0 || s.z.indexOf(k) >= 0) || '';
  // ★弹窗是「任务线推荐 · **装备优先**」：步骤里一件装备都不给的线（纯经验/开门线）不进策展块 ——
  //   否则列表里会出现「一行没有任何奖励图标」的内容。判据走站点数据（q 的奖励 ∪ i 的装备标记）。
  const hasEquip = s => s.steps.some(id => ((quests[id] || {}).rw || []).some(i => equip[i]));
  // ★档位必须与**人工策展同一语义**（chains.js 头部注释：S=蓝色武器 / A=优秀武器(长链) / B=顺路单任务）——
  //   站点自报的 t 只按步骤数给（≥8 就 S），直接抄过来会让「S 级链首条奖励都是武器」这条判据当场失败，
  //   而且「档位」筛选在列表里会变得没有意义（一堆没武器的线都挂 S）。
  const tier = s => {
    let blue = false, any = false;
    for (const id of s.steps) {
      for (const iid of ((quests[id] || {}).rw || [])) {
        const it = items[iid];
        if (!it || !it.eq || !it.dps) continue;          // 只看**武器**
        any = true;
        if (it.q >= 3) blue = true;
      }
    }
    return blue ? 'S' : any ? 'A' : 'B';
  };

  const all = [];
  for (const s of series) {
    if (covered(s)) continue;
    if (!(s.hi >= 30 && s.lo <= 60)) continue;             // 30-60 段（hi 进 30+ 才算）
    if (s.steps.length < 3) continue;
    if (SKIP.some(k => s.n.indexOf(k) >= 0)) continue;     // 节日/活动线不是经典任务线
    if (!hasEquip(s)) continue;                            // 装备优先：一件装备都不给的不进策展块
    const k = hitKey(s);
    if (!k && s.steps.length < 6) continue;                // 无关键词就必须够长
    all.push({ s, k, n: s.steps.length, f: faction(s) });
  }
  // ★同名去重：站点上同名系列常有「联盟版/部落版/长短两版」——
  //   同阵营只留最长的那版；跨阵营则两版都留，并给名字加阵营后缀（否则列表里两行同名看不懂）。
  const byName = {};
  for (const r of all) (byName[r.s.n] = byName[r.s.n] || []).push(r);
  const picked0 = [];
  for (const nm of Object.keys(byName)) {
    const grp = byName[nm];
    const byF = {};
    for (const r of grp) if (!byF[r.f] || r.n > byF[r.f].n) byF[r.f] = r;
    const fs = Object.keys(byF).sort();
    for (const f of fs) {
      const r = byF[f];
      if (fs.length > 1) r.s = Object.assign({}, r.s, { n: nm + (f === 'A' ? '（联盟）' : f === 'H' ? '（部落）' : '') });
      picked0.push(r);
    }
  }
  picked0.sort((a, b) => (b.n - a.n) || (a.s.lo - b.s.lo) || a.s.n.localeCompare(b.s.n));
  const picked = picked0.slice(0, MAX);

  console.log('自报系列 ' + series.length + ' 条 · 现有策展链 ' + curated.length + ' 条');
  console.log('候选（30-60、≥3 步、未被策展覆盖、非节日、**有装备奖励**）' + all.length + ' 条 → 同名合并后 ' +
    picked0.length + ' 条 → 取前 ' + picked.length + ' 条\n');
  picked.forEach((r, i) => {
    console.log(String(i + 1).padStart(2) + '. [' + r.s.t + '] ' + r.s.n +
      ' · ' + r.s.z + ' · ' + r.s.lo + '-' + r.s.hi + ' · ' + r.n + ' 步' + (r.k ? ' · 关键词=' + r.k : ''));
  });
  const rest = all.length - picked.length;
  if (rest > 0) console.log('\n（还有 ' + rest + ' 条候选未取，--max 可调）');

  if (!write) { console.log('\n[干跑] 未改文件；加 --write 才写入 chains.js 生成块'); return; }

  const entries = picked.map((r, i) => {
    const s = r.s;
    const key = 'c' + s.lo + '_' + String(i + 1).padStart(2, '0');
    const note = '经典线（站点系列 ' + r.n + ' 步）· ' + s.z + ' · 等级 ' + s.lo + '-' + s.hi +
      (s.open ? ' · 开门/史诗' : '') + '；奖励以任务详情页为准。';
    return '  {\n' +
      "    key: '" + key + "', name: '" + s.n.replace(/'/g, "\\'") + "', f: '" + faction(s) + "', t: '" + tier(s) +
      "', zone: '" + s.z.replace(/'/g, "\\'") + "', lo: " + s.lo + ', hi: ' + s.hi + ',\n' +
      '    quests: [' + s.steps.join(', ') + '],\n' +
      "    note: '" + note.replace(/'/g, "\\'") + "',\n" +
      '  },';
  }).join('\n');

  const src = fs.readFileSync(CHAINS, 'utf8');
  const block = BEGIN + '\n' + entries + '\n' + END;
  let out;
  if (src.indexOf(BEGIN) >= 0) {
    const a = src.indexOf(BEGIN);
    const b = src.indexOf(END, a);
    if (b < 0) throw new Error('生成块标记不成对（有 BEGIN 没 END）');
    out = src.slice(0, a) + block + src.slice(b + END.length);
  } else {
    const marker = '\n];\n';
    const i = src.lastIndexOf(marker);
    if (i < 0) throw new Error('找不到数组结尾 "];"，无法插入');
    out = src.slice(0, i) + '\n' + block + src.slice(i);
  }
  fs.writeFileSync(CHAINS, out, 'utf8');
  console.log('\n已写入 ' + picked.length + ' 条到 chains.js 生成块 —— 接着跑：node quest/build.js');
}

main();
