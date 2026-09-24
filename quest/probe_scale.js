/**
 * quest/probe_scale.js —— 抓取规模探针（只读，不改任何数据）
 *
 * 目的（用户 1.75.9「验证可行想，开始进行数据抓取」）：
 *   ① 站点每页多少条、等级区间一共有多少页（决定抓取耗时）
 *   ② 列表页是否自带「装备/物品奖励」信息（有就不必逐条拉详情页）
 *   ③ 详情页的「本系列第 N/M 部分」覆盖率（决定任务线能否自动拼）
 *
 * 用法：node quest/probe_scale.js [lo hi] ...
 */
'use strict';
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const BANDS = process.argv.slice(2).map(Number).filter(n => n > 0);
const RANGES = BANDS.length >= 2 ? [[BANDS[0], BANDS[1]]] : [[10, 19], [20, 29], [30, 39], [40, 49], [50, 60]];

(async () => {
  for (const [lo, hi] of RANGES) {
    const t0 = Date.now();
    const html = await Q.fetchText(`${Q.BASE}/quests?min_level=${lo}&max_level=${hi}&page=1`);
    const rows = Q.parseQuestList(html);
    // 每页条数 / 是否有分页
    const pages = [...html.matchAll(/[?&]page=(\d+)/g)].map(m => +m[1]);
    const maxPage = pages.length ? Math.max(...pages) : 1;
    // 列表页里有没有物品链接（有 = 奖励就在列表里）
    const items = Q.itemLinks(html);
    // 类型筛选参数（站点支持哪些 type）
    const types = [...new Set([...html.matchAll(/[?&]type=([a-z_]+)/g)].map(m => m[1]))];
    console.log(`[${lo}-${hi}] 首页 ${rows.length} 条 · 站点分页最大号 ${maxPage} · 首页物品链接 ${items.length} 个 · type 参数 [${types.join(',')}] · ${Date.now() - t0}ms`);
    console.log('    首行样例:', JSON.stringify(rows[0]));
  }
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
