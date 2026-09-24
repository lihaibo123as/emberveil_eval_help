/** quest/probe_reparse.js —— 用新解析器**重新抓**几个任务页，检查系列解析质量（只读探针） */
'use strict';
const Q = require('./fetch.js');
Q.bootstrap(__filename);

(async () => {
  for (const id of [1170, 1171, 8949, 7508, 5211, 873, 98, 913]) {
    const html = await Q.fetchText(`${Q.BASE}/quest/${id}`);
    const r = Q.parseQuestDetail(html, id);
    const st = (r.series && r.series.steps) || [];
    const uniq = new Set(st.map(s => s.name).filter(Boolean)).size;
    const ids = st.filter(s => s.id).length;
    console.log(`#${id} ${r.title} | ${r.series ? r.series.part + '/' + r.series.total : '-'} | steps ${st.length} | 唯一名 ${uniq} | 有id ${ids} | trusted ${r.series && r.series.trusted}`);
    console.log('     ' + st.slice(0, 8).map(s => s.n + ':' + s.name + (s.id ? '(' + s.id + ')' : '')).join(' , '));
    await new Promise(res => setTimeout(res, 250));
  }
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
