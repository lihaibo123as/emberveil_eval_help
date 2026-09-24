/**
 * quest/resolve.js —— 任务线步骤的 **id 补全**（build_bulk.js 与 audit.js 共用，避免两处口径漂移）
 *
 * 背景（1.75.9 审计实证）：站点的「本系列第 N/M 部分」块**有时只给步骤名、不给链接**
 *   （实测：迪菲亚兄弟会 / 莱恩的净化 / 大地之冠 等经典线的页面全是纯文本步骤，解出 id = 1/5、1/9、0/7）。
 *   光靠这个块 ⇒ 这些线要么被丢弃，要么只剩 1 步。
 *
 * 补全办法（**有强判据、可自证**）：用「任务名 → id」索引把缺 id 的步骤补上，但候选必须过三关：
 *   ① 强判据：候选项**自己的**系列记录能对上（`part == 步骤号` 且 `total` 相同）——同名任务再多也不会错配；
 *   ② 次判据：候选自己的系列记录存在且 `total` 相同；
 *   ③ 兜底：按等级接近当前系列已知等级、再按 id 升序。
 *   补出来的 id 打 `byName = true` 标记（审计里如实统计，便于人工复核）。
 *
 * ★为什么必须做：用户要求「任务线是否完整」「经典任务线不许遗漏」——不给链接的页面占了相当一部分。
 */
'use strict';
const fs = require('fs');
const path = require('path');

/** 名字 → 候选 id 表（来源：任务列表行 + 全部任务详情缓存；同名给多个候选） */
function buildNameIndex(cacheDir, sweepQuests) {
  const idx = {};
  const put = (name, id, lv) => {
    if (!name || !id) return;
    (idx[name] = idx[name] || []).push({ id: +id, lv: lv || 0 });
  };
  for (const q of (sweepQuests || [])) put(q.name, q.id, q.lv);
  for (const f of fs.readdirSync(cacheDir)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    try {
      const r = JSON.parse(fs.readFileSync(path.join(cacheDir, f), 'utf8'));
      if (r && r.id) put(r.title, r.id, r.level);
    } catch (e) {}
  }
  return idx;
}

/** 系列记录表：id → {part,total,steps}（补全时用候选自己那页的系列信息做交叉验证） */
function buildSeriesById(cacheDir) {
  const byId = {};
  for (const f of fs.readdirSync(cacheDir)) {
    if (!/^quest_\d+\.json$/.test(f)) continue;
    try {
      const r = JSON.parse(fs.readFileSync(path.join(cacheDir, f), 'utf8'));
      if (r && r.id && r.series && r.series.steps && r.series.steps.length >= 2) {
        byId[r.id] = { part: r.series.part, total: r.series.total, steps: r.series.steps };
      }
    } catch (e) {}
  }
  return byId;
}

/**
 * 把一条系列记录里缺 id 的步骤补上。
 * @returns {{steps:Array, filled:number, byName:number, resolved:number, total:number, trusted:boolean}}
 */
function fillSeriesIds(rec, nameIndex, seriesById) {
  const steps = (rec.steps || []).map(s => ({ n: s.n, id: s.id || null, name: s.name || '', here: !!s.here }));
  const total = rec.total || steps.length;
  const used = new Set(steps.filter(s => s.id).map(s => s.id));
  const known = steps.filter(s => s.id).map(s => (seriesById[s.id] && seriesById[s.id].total) || 0).filter(Boolean);
  let byName = 0;
  for (const s of steps) {
    if (s.id || !s.name) continue;
    const cands = (nameIndex[s.name] || []).filter(c => !used.has(c.id));
    if (!cands.length) continue;
    let pick = cands.find(c => { const r2 = seriesById[c.id]; return r2 && r2.total === total && r2.part === s.n; });
    if (!pick) pick = cands.find(c => { const r2 = seriesById[c.id]; return r2 && r2.total === total; });
    if (!pick) {
      const ref = known.length ? Math.min(...known) : 0;
      pick = cands.slice().sort((a, b) => Math.abs((a.lv || 0) - ref) - Math.abs((b.lv || 0) - ref) || a.id - b.id)[0];
    }
    if (pick) { s.id = pick.id; s.byName = true; byName++; used.add(pick.id); }
  }
  const resolved = steps.filter(s => s.id).length;
  return { steps, byName, resolved, total, trusted: resolved >= Math.ceil(total * 0.5) };
}

module.exports = { buildNameIndex, buildSeriesById, fillSeriesIds };
