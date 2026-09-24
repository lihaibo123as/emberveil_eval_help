/**
 * quest/probe_page.js —— 深挖列表页载荷（只读）
 * 目的：① 找出总条数/分页机制 ② 找出奖励信息是否已在列表 RSC 载荷里（有就不必逐条拉详情）
 * 用法：node quest/probe_page.js [lo hi] [page]
 */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const lo = Number(process.argv[2] || 30), hi = Number(process.argv[3] || 39), page = Number(process.argv[4] || 1);

(async () => {
  const url = `${Q.BASE}/quests?min_level=${lo}&max_level=${hi}&page=${page}`;
  const html = await Q.fetchText(url);
  const out = path.join(Q.CACHE, `_probe_list_${lo}_${hi}_p${page}.html`);
  Q.ensureCache();
  fs.writeFileSync(out, html);
  console.log('HTML 字节 =', html.length, '→', out);
  const keys = ['total', 'totalCount', 'totalPages', 'count', 'rewards', 'reward', 'items', '/item/', 'itemId', 'qualityColor', 'pageCount', 'hasNext', 'nextPage'];
  for (const k of keys) {
    const n = html.split(k).length - 1;
    console.log('  ' + k.padEnd(12), n);
  }
  // 分页控件长什么样
  const m = html.match(/.{0,160}(?:下一页|previous|Next|chevron|page=2).{0,160}/g);
  if (m) console.log('分页线索样例:', JSON.stringify(m.slice(0, 3)));
  // 第一条任务行的载荷上下文
  const first = html.match(/<a[^>]+href="\/quest\/(\d+)"[\s\S]{0,600}?<\/a>/);
  if (first) console.log('首行上下文:', first[0].replace(/\s+/g, ' ').slice(0, 500));
})().catch(e => { console.error('ERR', e && (e.stack || e.message)); process.exitCode = 1; });
