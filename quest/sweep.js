/**
 * quest/sweep.js —— 全量「任务列表」抓取（独立脚本，与插件零耦合）
 *
 * 目的（用户 1.75.9）：
 *   ① 把 10-60 级**所有任务**扫一遍（不再只有人工策展的 22 条链）
 *   ② 列表页本身就带奖励物品（`data-tooltip-entry` = 物品 id、`border-color` = 品质、`src` = 图标文件名）
 *      ⇒ 任务 → 装备 的对应关系**不必逐条拉详情页**，几十页就能扫完
 *   ③ 单任务（不属于任何链）也照样收；带装备奖励的才算「装备来源」
 *
 * 用法：node quest/sweep.js [lo] [hi]      # 默认 10 60
 * 产物：quest/cache/list_<lo>_<hi>_p<N>.html（页缓存，可重跑）
 *       quest/cache/sweep_<lo>_<hi>.json     （结构化行，含奖励物品）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const SLEEP = 250;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const QCOLOR = { '9d9d9d': 0, ffffff: 1, '1eff00': 2, '0070dd': 3, a335ee: 4, ff8000: 5 };

/** 一页列表 → 结构化行（含奖励物品 id/品质/图标） */
function parseRows(html) {
  const out = [];
  for (const m of html.matchAll(/<a[^>]+href="\/quest\/(\d+)"[\s\S]*?<\/a>/g)) {
    const id = +m[1], b = m[0];
    const pick = (re) => { const x = b.match(re); return x ? x[1].trim() : ''; };
    const lv = +(pick(/w-10[^>]*>(\d+)</) || 0);
    const name = pick(/text-quest[^>]*>([^<]*)</);
    const zone = pick(/w-36[^>]*>([^<]*)</);
    const xp = pick(/>([\d,]+)<!-- --> <!-- -->经验/);
    const tag1 = pick(/w-4 shrink-0[^>]*>([\s\S]*?)<\/span>/).replace(/<[^>]+>/g, '').trim();
    const typeTag = pick(/w-20[^>]*>([^<]*)</);
    // ★奖励图标：**整行**扫 `data-tooltip-type="item"` 的图标，不依赖 title 分组的 span 边界。
    //   实测坑（1.75.9）：#451 致命的配方 的「直接给予」那枚图标在分组 span **之外**
    //   ⇒ 旧实现（按 title 分组 + 非贪婪 </span>）会把这类奖励漏掉，任务详情页却有它 —— 审计当场抓出 68 条。
    const rewards = [];
    for (const im of b.matchAll(/<img[^>]*data-tooltip-type="item"[^>]*data-tooltip-entry="(\d+)"[^>]*>/g)) {
      const tag = im[0];
      const qm = tag.match(/border-color:#([0-9a-fA-F]{6})/);
      const sm = tag.match(/src="([^"]+)"/);
      rewards.push({
        id: +im[1],
        q: qm && QCOLOR[qm[1].toLowerCase()] != null ? QCOLOR[qm[1].toLowerCase()] : 1,
        icon: sm ? (sm[1].match(/\/([^/]+)\.png$/) || [, ''])[1] : '',
        kind: /选择/.test(b.slice(0, im.index)) ? 'choose' : 'receive',
      });
    }
    if (!id || !lv) continue;
    out.push({ id, lv, name, zone, xp, tag: tag1, type: typeTag, rewards });
  }
  return out;
}

async function page(lo, hi, p, force) {
  const file = path.join(Q.CACHE, `list_${lo}_${hi}_p${p}.html`);
  if (!force && fs.existsSync(file)) return fs.readFileSync(file, 'utf8');
  const html = await Q.fetchText(`${Q.BASE}/quests?min_level=${lo}&max_level=${hi}&page=${p}`);
  Q.ensureCache();
  fs.writeFileSync(file, html);
  await sleep(SLEEP);
  return html;
}

(async () => {
  const lo = Number(process.argv[2] || 10), hi = Number(process.argv[3] || 60);
  Q.ensureCache();
  const first = await page(lo, hi, 1);
  const pm = first.match(/第 (\d+) \/ (\d+) 页/);
  const totalPages = pm ? +pm[2] : 1;
  console.log(`[${lo}-${hi}] 站点自报共 ${totalPages} 页 × 50 条`);
  const all = [];
  for (let p = 1; p <= totalPages; p++) {
    const html = p === 1 ? first : await page(lo, hi, p);
    const rows = parseRows(html);
    all.push(...rows);
    if (p % 10 === 0 || p === totalPages) console.log(`  p${p}/${totalPages} 累计 ${all.length}`);
  }
  const seen = new Set();
  const uniq = all.filter(r => !seen.has(r.id) && seen.add(r.id));
  const inv = {};
  for (const r of uniq) for (const it of r.rewards) inv[it.id] = it;
  const withEq = uniq.filter(r => r.rewards.some(i => i.q >= 2));
  const ids = Object.values(inv);
  const byQ = {};
  for (const it of ids) byQ[it.q] = (byQ[it.q] || 0) + 1;
  const out = path.join(Q.CACHE, `sweep_${lo}_${hi}.json`);
  fs.writeFileSync(out, JSON.stringify({ lo, hi, pages: totalPages, quests: uniq }, null, 0));
  console.log('————————————————————————');
  console.log('任务总数        =', uniq.length, '（去重后）');
  console.log('带奖励的任务    =', uniq.filter(r => r.rewards.length).length);
  console.log('带绿装+的任务   =', withEq.length);
  console.log('不同奖励物品数  =', ids.length, '品质分布', JSON.stringify(byQ));
  console.log('绿装+物品数     =', ids.filter(i => i.q >= 2).length);
  console.log('产物 =', out);
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
