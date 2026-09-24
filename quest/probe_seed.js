/** quest/probe_seed.js —— 用英文关键词找大型/开门任务线（只读探针） */
'use strict';
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const KWS = ['Scepter of the Shifting Sands', 'Ahn\'Qiraj', 'Naxxramas', 'Blackwing Lair', 'Onyxia',
  'Molten Core', 'Blackrock Depths', 'Quel\'Serrar', 'Thunderfury', 'Darrowshire', 'Linken',
  'Scholomance', 'Stratholme', 'Dire Maul', 'Zul\'Gurub', 'Sunken Temple', 'Maraudon',
  'Razorfen', 'Uldaman', 'Zul\'Farrak', 'Scarlet Monastery', 'Gnomeregan', 'Wailing Caverns',
  'Deadmines', 'Stockade', 'Shadowfang', 'Ashbringer', 'Temple of Atal\'Hakkar', 'Hakkar',
  'Eranikus', 'Malfurion', 'Sillithus', 'Cenarion', 'Argent Dawn', 'Tirion', 'Fordring'];

(async () => {
  const found = [];
  for (const kw of KWS) {
    let rows = [];
    try { rows = Q.parseQuestList(await Q.fetchText(`${Q.BASE}/quests?name=${encodeURIComponent(kw)}`)); } catch (e) {}
    console.log(kw.padEnd(34), '→', rows.length, rows.slice(0, 3).map(r => r.id).join(','));
    for (const r of rows.slice(0, 3)) found.push(r.id);
  }
  console.log('候选 id 数 =', found.length);
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
