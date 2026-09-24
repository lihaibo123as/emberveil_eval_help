/** quest/probe_row.js —— 打印一条完整列表行的 HTML（设计解析器用；只读） */
'use strict';
const fs = require('fs');
const path = require('path');
const Q = require('./fetch.js');
const f = process.argv[2] || path.join(Q.CACHE, '_probe_list_30_39_p1.html');
const html = fs.readFileSync(f, 'utf8');
const rows = [...html.matchAll(/<a[^>]+href="\/quest\/(\d+)"[\s\S]*?<\/a>/g)].map(m => m[0]);
console.log('行数 =', rows.length, '| 文件 =', f);
for (const r of rows.slice(0, 2)) console.log('\n-----\n' + r.replace(/></g, '>\n<'));
