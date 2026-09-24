/**
 * quest/fetch.js —— EmberVeil 任务数据库抓取器（独立脚本，不参与插件运行）
 *
 * 设计原则（用户要求「做好解耦、脚本独立」）：
 *   · 本文件与插件源码**零耦合**：不 require 插件、不改插件、不读插件配置；
 *   · 只做一件事：把 database.emberveil.org 的页面抓下来并解析成 JSON，落到 quest/cache/；
 *   · 生成的 JSON 是后续 quest/build.js 的唯一输入；插件运行期**完全不依赖本脚本**。
 *
 * 用法（在本仓库根目录执行）：
 *   node quest/fetch.js probe                  # 连通性自检（报代理/站点/中文）
 *   node quest/fetch.js list                   # 抓 10-30 级任务列表 → cache/quest_list.json
 *   node quest/fetch.js search <名字>          # 按名搜索任务，打印 id（策展时用）
 *   node quest/fetch.js quest <id> [id...]     # 抓任务详情 → cache/quest_<id>.json
 *   node quest/fetch.js item  <id> [id...]     # 抓物品详情 → cache/item_<id>.json
 *   node quest/fetch.js all                    # 按 chains.js 的策展清单抓全套（任务+物品）
 *   加 --force 可忽略缓存重抓；加 --en 抓英文（默认中文）
 *
 * 外网：按本机规则走本地代理 127.0.0.1:10809（可用 QC_PROXY 环境变量覆盖）。
 *   —— Node 的 fetch 只认「启动前」的环境变量，所以本脚本会在需要时**用 inherit 方式重启自己一次**，
 *      把代理环境变量喂进去（不依赖任何第三方库）。
 */
'use strict';

const fs = require('fs');
const path = require('path');

const BASE = 'https://database.emberveil.org';
const PROXY = process.env.QC_PROXY || 'http://127.0.0.1:10809';
const CACHE = path.join(__dirname, 'cache');
const SLEEP_MS = 200; // 限速：不给对方服务器压力

// ---------- 代理自举：Node 的 fetch 只认「启动前」的环境变量 ----------
// 入口脚本（本文件 CLI 或 build.js）调用 bootstrap(entry)：还没喂代理就用 inherit 方式重启自己一次，
// 不依赖任何第三方库。（require 本模块的脚本不会被误重启。）
function bootstrap(entry) {
  if (process.env.__QC_PROXY_READY) return;
  const { spawnSync } = require('child_process');
  const r = spawnSync(process.execPath, [entry, ...process.argv.slice(2)], {
    stdio: 'inherit',
    env: {
      ...process.env,
      HTTP_PROXY: process.env.HTTP_PROXY || PROXY,
      HTTPS_PROXY: process.env.HTTPS_PROXY || PROXY,
      NODE_USE_ENV_PROXY: '1',
      __QC_PROXY_READY: '1',
    },
  });
  process.exit(r.status === null ? 1 : r.status);
}

const ARGS = process.argv.slice(2);
const FORCE = ARGS.includes('--force');
const EN = ARGS.includes('--en');
const REST = ARGS.filter(a => !a.startsWith('--'));
const HEADERS = EN ? {} : { Cookie: 'lang=zhCN; locale=zhCN' };

const sleep = ms => new Promise(r => setTimeout(r, ms));

function ensureCache() {
  if (!fs.existsSync(CACHE)) fs.mkdirSync(CACHE, { recursive: true });
}

/** 抓一个 URL（自动重试 2 次） */
async function fetchText(url, tries = 3) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, { signal: AbortSignal.timeout(25000), headers: HEADERS });
      if (r.status !== 200) throw new Error('HTTP ' + r.status);
      return await r.text();
    } catch (e) {
      lastErr = e;
      await sleep(400 * (i + 1));
    }
  }
  throw new Error('抓取失败 ' + url + ' :: ' + (lastErr && (lastErr.cause?.code || lastErr.message)));
}

/** 带缓存的抓取：cache/<name>.json 存在就直接读（除非 --force） */
async function cached(name, url, parse) {
  ensureCache();
  const file = path.join(CACHE, name + '.json');
  if (!FORCE && fs.existsSync(file)) {
    try {
      return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (e) { /* 缓存坏了就重抓 */ }
  }
  const html = await fetchText(url);
  const data = parse(html);
  fs.writeFileSync(file, JSON.stringify(data, null, 1));
  await sleep(SLEEP_MS);
  return data;
}

// ---------------- 解析（HTML 结构 → 纯 JSON） ----------------

/** 可见文本行（去 script/style/标签），任务与物品页共用 */
function visibleLines(html) {
  return html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/g, ' ')
    .replace(/<style[^>]*>[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, '\n')
    .replace(/&amp;/g, '&')
    .replace(/&#x27;/g, "'")
    .replace(/&quot;/g, '"')
    .split('\n')
    .map(s => s.trim())
    .filter(Boolean);
}

/** 页面里的 /item/ 链接 → [{id,name}]（奖励物品的名字↔ID 配对靠它） */
function itemLinks(html) {
  const out = [];
  for (const m of html.matchAll(/<a[^>]+href="\/item\/(\d+)"[^>]*>([\s\S]*?)<\/a>/g)) {
    out.push({ id: +m[1], name: m[2].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() });
  }
  // 去重保序
  const seen = new Set();
  return out.filter(x => !seen.has(x.id) && seen.add(x.id));
}

/** 任务列表页 → [{id, row}]；row 是行文本（含等级/阵营/XP/地区） */
function parseQuestList(html) {
  const out = [];
  const seen = new Set();
  for (const m of html.matchAll(/<a[^>]+href="\/quest\/(\d+)"[^>]*>([\s\S]*?)<\/a>/g)) {
    const id = +m[1];
    if (seen.has(id)) continue;
    seen.add(id);
    out.push({ id, row: m[2].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim() });
  }
  return out;
}

/** 任务详情页 → 结构化对象 */
function parseQuestDetail(html, id) {
  const v = visibleLines(html);
  const li = v.findIndex(l => /^等级 \d+/.test(l));
  if (li < 0) return { id, error: 'no-level-line' };
  const rec = { id, title: v[li - 1], level: +(v[li].match(/^等级 (\d+)/) || [0, 0])[1] };
  rec.tags = v[li].replace(/^等级 \d+\s*[·]?\s*/, '');
  rec.zone = v[li + 1] || '';

  // 系列（上/下级链）：★**结构性解析**（1.75.9 修，见下）
  //   站点把整条系列列成一块：除「你在这里」那一步外，每一步都是 `<a href="/quest/ID">名字</a>`。
  //   ⇒ 按**文档顺序**取块内任务链接就是步骤表；当前页那一步按 part 号插回去。
  //   ★旧实现按可见行「数字 换行 名字」对齐，在部分页面上整块错位：实测 #8949 把 24 步全读成同一个
  //     名字、只解出 1 个 id（#1170 奥妮克希亚同样）⇒ 生成出一堆「假任务线」。这是数据质量事故，
  //     所以判据也改成「步骤名不许大量重复」（见 build_bulk.js 的体检）。
  const si = v.findIndex(l => /^本系列第 (\d+)\/(\d+) 部分/.test(l));
  if (si >= 0) {
    const mm = v[si].match(/^本系列第 (\d+)\/(\d+) 部分/);
    const part = +mm[1], total = +mm[2];
    const hIdx = html.indexOf('本系列第');
    const block = hIdx >= 0 ? html.slice(hIdx, hIdx + 24000) : '';
    const endIdx = block.search(/任务提供|Quest offer/);
    const cut = endIdx > 0 ? block.slice(0, endIdx) : block;
    const strip = s => s.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    const seenId = {};
    const links = [];
    for (const m of cut.matchAll(/href="\/quest\/(\d+)"[^>]*>([\s\S]*?)<\/a>/g)) {
      const lid = +m[1], nm = strip(m[2]);
      if (!nm || seenId[lid]) continue;
      seenId[lid] = 1;
      links.push({ id: lid, name: nm });
    }
    // ★可见文本里的「数字 → 名字」序列：站点的系列块**有时只给纯文本步骤、不给链接**
    //   （实测：迪菲亚兄弟会 / 莱恩的净化 / 大地之冠 全是这种页）——名字必须从这里捞，
    //   否则 steps 只剩「你在这里」那一步（id 1/N），经典线整条消失。
    const vNames = {};
    for (let i = si + 1; i < Math.min(si + 200, v.length); i++) {
      if (/^任务提供|^Quest offer/.test(v[i])) break;
      if (/^\d+$/.test(v[i])) {
        const n = +v[i], nm = v[i + 1] || '';
        if (n >= 1 && n <= total && nm && !/^\d+$/.test(nm) && nm !== '（你在这里）' && nm !== '(you are here)' && !vNames[n]) {
          vNames[n] = nm;
        }
      }
    }
    const used = {};
    const steps = [];
    if (links.length === total) {
      links.forEach((l, i) => steps.push({ n: i + 1, id: l.id, name: l.name, here: l.id === id }));
    } else {
      for (let i = 1; i <= total; i++) {
        let nm = vNames[i] || '';
        let lid = null;
        if (i === part) { lid = id; if (!nm) nm = rec.title; }
        else {
          let li = links.findIndex((l, k) => !used[k] && nm && l.name === nm);
          if (li < 0) li = links.findIndex((l, k) => !used[k]);
          if (li >= 0) { used[li] = 1; lid = links[li].id; if (!nm) nm = links[li].name; }
        }
        steps.push({ n: i, id: lid, name: nm, here: i === part });
      }
    }
    // 体检：**id 覆盖率**是可信判据（名字重复不算 —— 站点上「斯塔文的传说」13 步本来就同名）。
    //   id 覆盖不足 ⇒ 该页没有链接，交给 resolve.js 用「任务名 → id」补（补的时候要过 part/total 交叉验证）。
    const idN = steps.filter(s => s.id).length;
    rec.series = { part, total, steps, trusted: (idN >= Math.ceil(total * 0.5)) };

  }

  const links = itemLinks(html);
  const pair = arr => (arr || []).map(n => {
    const hit = links.find(l => l.name === n);
    return hit ? { id: hit.id, name: n } : { name: n };
  });
  // 选择一件
  const ri = v.findIndex(l => /你可以从这些奖励品中选择一件/.test(l));
  if (ri >= 0) {
    const arr = [];
    for (let i = ri + 1; i < v.length && !/^经验值/.test(v[i]); i++) arr.push(v[i]);
    rec.choose = pair(arr);
  }
  // 直接给予
  const gi = v.findIndex(l => /^你将(得到|获得)/.test(l));
  if (gi >= 0) {
    const arr = [];
    for (let i = gi + 1; i < v.length && !/^经验值/.test(v[i]); i++) arr.push(v[i]);
    rec.receive = pair(arr);
  }
  const xi = v.findIndex(l => /^经验值/.test(l));
  if (xi >= 0) rec.xp = v[xi + 1];
  const qi = v.findIndex(l => /^需要等级 \d+/.test(l));
  if (qi >= 0) rec.requires = +(v[qi].match(/需要等级 (\d+)/) || [0, 0])[1];
  // 发布者（开始/结束 NPC）
  const gi2 = v.findIndex(l => /^任务发布者/.test(l));
  if (gi2 >= 0) {
    const names = [];
    for (let i = gi2 + 1; i < Math.min(gi2 + 60, v.length); i++) {
      if (/^要求$/.test(v[i])) break;
      if (/^[!?]{1,2}$/.test(v[i])) continue;
      if (/^(开始|结束|开始与结束)$/.test(v[i])) { names.push({ how: v[i], name: names.pop() || '' }); continue; }
      if (v[i].length > 1 && !/^\d+$/.test(v[i]) && !/^（.*）$/.test(v[i]) && !/^\(.*\)$/.test(v[i])) names.push(v[i]);
    }
    rec.givers = names.filter(n => typeof n === 'object');
  }
  return rec;
}

/** 物品详情页 → 结构化对象（品质取自 RSC 的 qualityColor） */
const QCOLOR = { '9d9d9d': 0, ffffff: 1, '1eff00': 2, '0070dd': 3, a335ee: 4, ff8000: 5 };
function parseItemDetail(html, id) {
  const v = visibleLines(html);
  const bi = v.findIndex(l => /^拾取后绑定|^装备后绑定|^不绑定/.test(l));
  const rec = { id, name: bi > 0 ? v[bi - 1] : '' };
  const cm = html.match(/qualityColor[^#]{0,20}#([0-9a-fA-F]{6})/);
  rec.q = cm ? (QCOLOR[cm[1].toLowerCase()] ?? 1) : 1;
  const il = v.findIndex(l => /^等级 \d+$/.test(l));
  if (il >= 0) rec.ilvl = +v[il].match(/^等级 (\d+)$/)[1];
  const joined = v.join('|');
  const dm = joined.match(/每秒伤害([\d.]+)/);
  if (dm) rec.dps = +dm[1];
  const sm = joined.match(/速度\|([\d.]+)/);
  if (sm) rec.speed = +sm[1];
  const si = v.findIndex(l => /^(双手|单手|主手|副手|远程|脚|腿|胸|手|头|肩|手腕|腰|背部|手指|饰品|颈部|箭袋|弹药包)$/.test(l));
  if (si >= 0) { rec.slot = v[si]; rec.kind = v[si + 1] || ''; }
  const stats = [];
  for (const m of joined.matchAll(/\+\|(\d+)\|(力量|敏捷|耐力|智力|精神)/g)) stats.push('+' + m[1] + m[2]);
  rec.stats = stats.join(' ');
  // 反向引用：本物品是哪些任务的奖励（物品页「可选奖励来自 / 奖励来自」）
  const from = [];
  const fi = v.findIndex(l => /奖励来自|可选奖励来自/.test(l));
  if (fi >= 0) for (let i = fi + 1; i < Math.min(fi + 8, v.length); i++) if (v[i].length > 1 && !/^\(|^（|^\d+$/.test(v[i])) { from.push(v[i]); break; }
  if (from.length) rec.rewardFrom = from[0];
  return rec;
}

// ---------------- 对外 API ----------------

const API = {
  BASE, CACHE, ensureCache, fetchText, cached, bootstrap,
  visibleLines, itemLinks, parseQuestList, parseQuestDetail, parseItemDetail,
  /** 任务列表（10-30 级，全部分页） */
  async questList(minLevel = 10, maxLevel = 30) {
    ensureCache();
    const file = path.join(CACHE, `quest_list_${minLevel}_${maxLevel}.json`);
    if (!FORCE && fs.existsSync(file)) return JSON.parse(fs.readFileSync(file, 'utf8'));
    const all = [];
    for (let page = 1; page <= 40; page++) {
      const html = await fetchText(`${BASE}/quests?min_level=${minLevel}&max_level=${maxLevel}&page=${page}`);
      const rows = parseQuestList(html);
      if (!rows.length) break;
      all.push(...rows);
      if (page % 5 === 0) console.log('  list page', page, 'cum', all.length);
      await sleep(SLEEP_MS);
    }
    const seen = new Set();
    const uniq = all.filter(r => !seen.has(r.id) && seen.add(r.id));
    fs.writeFileSync(file, JSON.stringify(uniq, null, 1));
    return uniq;
  },
  /** 任务详情（带缓存） */
  quest(id) { return cached('quest_' + id, `${BASE}/quest/${id}`, h => parseQuestDetail(h, id)); },
  /** 物品详情（带缓存） */
  item(id) { return cached('item_' + id, `${BASE}/item/${id}`, h => parseItemDetail(h, id)); },
  /** 按名搜索任务 → id 数组 */
  async searchQuest(name) {
    const html = await fetchText(`${BASE}/quests?name=${encodeURIComponent(name)}`);
    return parseQuestList(html).map(r => r.id);
  },
};

module.exports = API;

// ---------------- CLI ----------------

if (require.main === module) {
  bootstrap(__filename);
  (async () => {
    const cmd = REST[0];
    const nums = REST.slice(1).map(Number).filter(n => n > 0);
    if (cmd === 'probe') {
      console.log('代理:', PROXY, '| NODE_USE_ENV_PROXY =', process.env.NODE_USE_ENV_PROXY);
      const html = await fetchText(`${BASE}/quest/166`);
      const v = visibleLines(html);
      const li = v.findIndex(l => /^等级 \d+/.test(l));
      console.log('站点可达 ✓  任务页标题 =', v[li - 1], '| 等级行 =', v[li]);
      console.log('中文模式 =', EN ? 'off' : 'on', '| 缓存目录 =', CACHE);
      return;
    }
    if (cmd === 'list') {
      const rows = await API.questList();
      console.log('任务列表:', rows.length, '条 →', path.join(CACHE, 'quest_list_10_30.json'));
      return;
    }
    if (cmd === 'search') {
      const ids = await API.searchQuest(REST[1] || '');
      console.log(REST[1], '->', JSON.stringify(ids));
      return;
    }
    if (cmd === 'quest' || cmd === 'item') {
      if (!nums.length) { console.error('用法: node quest/fetch.js ' + cmd + ' <id> [id...]'); process.exit(1); }
      for (const id of nums) {
        const rec = cmd === 'quest' ? await API.quest(id) : await API.item(id);
        console.log(cmd, id, '->', JSON.stringify(rec).slice(0, 220));
      }
      return;
    }
    if (cmd === 'all') {
      const chains = require('./chains.js');
      const qids = new Set(), iids = new Set();
      for (const c of chains.CHAINS) { c.quests.forEach(q => qids.add(q)); (c.rewards || []).forEach(i => iids.add(i)); }
      console.log('策展清单:', chains.CHAINS.length, '条链 /', qids.size, '个任务');
      for (const id of qids) {
        const rec = await API.quest(id);
        (rec.choose || []).forEach(x => x.id && iids.add(x.id));
        (rec.receive || []).forEach(x => x.id && iids.add(x.id));
      }
      console.log('任务抓完；待抓物品', iids.size, '件');
      for (const id of iids) await API.item(id);
      console.log('全部完成 →', CACHE);
      return;
    }
    console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].split('/**')[1]);
  })().catch(e => { console.error('ERR:', e.message); process.exit(1); });
}
