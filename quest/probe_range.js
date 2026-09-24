// 探针：全量任务线/装备的等级覆盖（只读生成物 QuestBulk.lua，不联网）
// 用途：回答「任务线是否收集齐 / 最高只到 30 级」这类问题 —— 用数据说话。
const fs = require("fs");
const src = fs.readFileSync("quest/QuestBulk.lua", "utf8");

const metaM = src.match(/meta=\{[^}]*\}/);
console.log("meta: " + (metaM ? metaM[0] : "?") );

function grab(key) {
  const i = src.indexOf("\n" + key + "={");
  if (i < 0) return [];
  const j = src.indexOf("\n},", i);
  const body = src.slice(i, j < 0 ? src.length : j);
  const out = [];
  const re = /\[(\d+)\]="((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(body))) out.push({ id: +m[1], p: m[2].split("|") });
  return out;
}

// s 段是**纯数组**（"名|lo|hi|区域|档|open|步骤"），与 q/i 的 [id]=" " 形式不同
function grabArr(key, endKey) {
  const i = src.indexOf("\n" + key + "={");
  if (i < 0) return [];
  const j = endKey ? src.indexOf("\n" + endKey + "={", i) : -1;
  const body = src.slice(i, j < 0 ? src.length : j);
  return (body.match(/"(?:[^"\\]|\\.)*"/g) || []).map(s => ({ p: s.slice(1, -1).split("|") }));
}

const quests = grab("q"), items = grab("i"), series = grabArr("s", "sn");
const bands = [[0, 9], [10, 19], [20, 29], [30, 39], [40, 49], [50, 59], [60, 200]];
const hist = (rows, lvOf) => bands.map(([a, b]) =>
  `${a}-${b}:${rows.filter(r => { const lv = lvOf(r); return lv >= a && lv <= b; }).length}`).join("  ");

const qlv = quests.map(r => parseInt(r.p[1], 10)).filter(n => !isNaN(n));
console.log("任务(全量) " + quests.length + " 条 · 等级 " + Math.min(...qlv) + "~" + Math.max(...qlv));
console.log("  等级分布 " + hist(quests, r => parseInt(r.p[1], 10)));
console.log("装备(全量) " + items.length + " 件（其中装备类 " + items.filter(r => r.p[9] === "1").length + "）");

const slo = series.map(r => parseInt(r.p[1], 10)), shi = series.map(r => parseInt(r.p[2], 10));
console.log("任务线(自报系列) " + series.length + " 条 · lo " + Math.min(...slo) + "~" + Math.max(...slo) +
  " · hi " + Math.min(...shi) + "~" + Math.max(...shi));
console.log("  按最低等级分布 " + hist(series, r => parseInt(r.p[1], 10)));
console.log("  lo>=31 的线 " + slo.filter(n => n >= 31).length + " 条 · hi>=50 的线 " + shi.filter(n => n >= 50).length + " 条");
console.log("  步骤数>=8 的大型线 " + series.filter(r => (r.p[6] || "").split(",").length >= 8).length + " 条");
