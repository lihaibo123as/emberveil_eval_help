/** quest/probe_classic.js —— 经典任务线关键词命中探测（只读）：找「还没进数据」的著名线 */
'use strict';
const Q = require('./fetch.js');
Q.bootstrap(__filename);

const KWS = ['Stratholme', 'Desperate', 'Archivist', 'Aurius', 'Rivendare', 'Cannon', 'Masterwork', 'Kirtonos',
  'Zul\'Farrak', 'Tiara', 'Nekrum', 'Gahz', 'Mosh', 'Divino', 'Troll Temper', 'Zul\'Gurub', 'Gurubashi',
  'Blackwing', 'Nefarian', 'Ashbringer', 'Fordring', 'Love and Family', 'Corruption', 'Light\'s Hope',
  'Ahn', 'Qiraji', 'Scepter', 'Shifting Sands', 'Bronze', 'Anachronos', 'Azuregos',
  'Molten', 'Onyxia', 'Naxxramas', 'Echoes', 'Kel\'Thuzad', 'Kel', 'Plaguelands', 'Argent',
  'Scarlet', 'Scholomance', 'Caer', 'Timbermaw', 'Brood', 'Dragonscale', 'Thorium',
  'Winterspring', 'Silithus', 'Un\'Goro', 'Cenarion', 'Darnassus', 'Stormwind', 'Ironforge', 'Orgrimmar'];

(async () => {
  const found = {};
  for (const kw of KWS) {
    let rows = [];
    try { rows = Q.parseQuestList(await Q.fetchText(`${Q.BASE}/quests?name=${encodeURIComponent(kw)}`)); } catch (e) {}
    if (rows.length) {
      found[kw] = rows.slice(0, 8).map(r => r.id);
      console.log(kw.padEnd(18), rows.length, rows.slice(0, 4).map(r => '#' + r.id + ' ' + r.row.slice(0, 42)).join(' | '));
    } else console.log(kw.padEnd(18), 0);
    await new Promise(r => setTimeout(r, 200));
  }
  const ids = [...new Set(Object.values(found).flat())];
  console.log('\n候选 id 共', ids.length, ':', ids.join(','));
})().catch(e => { console.error('ERR', e && e.message); process.exitCode = 1; });
