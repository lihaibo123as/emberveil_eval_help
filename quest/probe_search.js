/** quest/probe_search.js —— 探站点的任务搜索参数（只读） */
'use strict';
const Q = require('./fetch.js');
Q.bootstrap(__filename);

(async () => {
  const tests = [
    '/quests?name=' + encodeURIComponent('安其拉'),
    '/quests?q=' + encodeURIComponent('安其拉'),
    '/quests?search=' + encodeURIComponent('安其拉'),
    '/quests?name=' + encodeURIComponent('Onyxia'),
    '/quests?name=Onyxia',
    '/quests?keyword=' + encodeURIComponent('安其拉'),
    '/quests?min_level=55&max_level=60&name=' + encodeURIComponent('安其拉'),
  ];
  for (const p of tests) {
    try {
      const html = await Q.fetchText(Q.BASE + p);
      const rows = Q.parseQuestList(html);
      const pm = html.match(/第 (\d+) \/ (\d+) 页/);
      console.log(p.slice(0, 70).padEnd(70), '→', rows.length, '条', pm ? ('共 ' + pm[2] + ' 页') : '');
      if (rows.length) console.log('     首条:', JSON.stringify(rows[0]).slice(0, 120));
    } catch (e) { console.log(p, 'ERR', e && e.message); }
  }
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
