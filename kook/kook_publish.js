#!/usr/bin/env node
/**
 * kook_publish.js —— 每次 release 时把打包产物自动发到 KOOK「插件发布频道」
 *
 * 需求来源：用户 2026-10-09「这是我创建的频道 …/app/channels/7071527711947717/8320814423228312
 *           需求是在每次 release 的时候自动上传插件到插件发布频道」
 *
 * 接口链路（依据官方文档，抓取于 2026-10-09，详见 kook/01-频道维护接口调研.md）：
 *   1) POST /api/v3/asset/create    （multipart/form-data，字段名 file）→ 返回 { url }
 *      —— KOOK 硬性要求：消息里的文件/图片必须由机器人自己上传过，否则报「找不到资源」；
 *         且资源上传后默认「不可见」，只有作为卡片元素（file/image…）发出去才刷新可见状态。
 *   2) POST /api/v3/message/create  （type=10 卡片消息，content = 卡片 JSON 字符串）
 *      卡片内用 file 模块承载每个包：{ type:"file", src:"<asset url>", title:"…" }
 *      —— 一条卡片可放多个 file 模块（一卡最多 50 个模块）⇒ **所有包一条消息发完**。
 *      备选：--mode file 走 type=4 文件消息（每个包一条，content = url）。
 *
 * 用法：
 *   node kook/kook_publish.js                 # 默认 dry-run：列出将上传的文件 + 打印卡片 JSON + 请求清单（不发任何东西）
 *   node kook/kook_publish.js --check         # 只读自检：token 身份 / 机器人在服务器 / 目标频道 / 权限位预估
 *   node kook/kook_publish.js --send          # 真发：上传 asset → 发卡片消息
 *   node kook/kook_publish.js --send --mode file   # 备选通道：每个包一条文件消息
 *
 * 参数：--dir <打包产物目录> | --files a.zip,b.zip | --assets versioned|both | --version <v>
 *       --title <标题> | --notes <文案文件> | --notes-auto | --no-notes
 *       --guild <id> | --channel <id> | --token-file <路径> | --min-interval <ms> | --json | --print-card
 *
 * 更新文案（用户 2026-10-09 定：「需要总结，不要做版本流水账」）：
 *   ① kook/notes/<版本>.md  —— 首选：人/AI 写好的对外总结（只发这一份内容）
 *   ② 退路 = 自动摘要：只抽 CHANGELOG 该版本段的**标题行**，丢掉正文细节与版本跨越叙事
 *   ③ --no-notes 不附；--notes-auto 强制看自动摘要；--notes <文件> 临时指定
 *   发布包只发**带完整版本号**的那份（<名>-v<版本>.zip）；固定名包默认不发（--assets both 才发）。
 *
 * 纪律（本项目铁律）：
 *   · 默认只读；写操作必须显式 --send。
 *   · 版本号一律**现读** .toc，绝不写死；期望的包名由版本现算。
 *   · 期望的包不存在 ⇒ 直接失败并提示「先跑打包脚本」（防止把过期包当新版发出去）。
 *   · token 只从 token/kook.txt（.gitignore 已忽略 /token）或环境变量 KOOK_TOKEN 读，**永不打印**。
 */

"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");          // 仓库根
const API = "https://www.kookapp.cn/api/v3";

// ───────────────────────────── CLI ─────────────────────────────
function parseArgs(argv) {
  const o = { mode: "card", assets: "versioned", send: false, check: false, json: false,
              notes: null, notesAuto: false, minInterval: 400, files: null, dir: null, version: null, title: null, printCard: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    switch (a) {
      case "--send":        o.send = true; break;
      case "--check":       o.check = true; break;
      case "--dry-run":     o.send = false; break;
      case "--json":        o.json = true; break;
      case "--print-card":  o.printCard = true; break;
      case "--thread-view": o.threadView = next(); break;      // 回读帖子（验 status/分区/媒体）
      case "--thread-delete": o.threadDelete = next(); break;  // 删帖（必须同时给 --send）
      case "--mode":        o.mode = next(); break;                 // card | file（文字频道的发法）
      case "--attach":      o.attach = next(); break;                // link（默认，只放链接）| file（上传附件）
      case "--assets":      o.assets = next(); break;               // versioned | both
      case "--dir":         o.dir = next(); break;
      case "--files":       o.files = next().split(",").map(s => s.trim()).filter(Boolean); break;
      case "--version":     o.version = next(); break;
      case "--title":       o.title = next(); break;
      case "--notes":       o.notes = next(); break;
      case "--notes-auto":  o.notesAuto = true; break;
      case "--no-notes":    o.notes = ""; break;
      case "--guild":       o.guild = next(); break;
      case "--channel":     o.channel = next(); break;
      case "--token-file":  o.tokenFile = next(); break;
      case "--min-interval":o.minInterval = parseInt(next(), 10); break;
      case "-h": case "--help":
        console.log(fs.readFileSync(__filename, "utf8").split("*/")[0].replace(/^\/\*\*?/, ""));
        process.exit(0);
      default:
        console.error("未知参数: " + a + "（用 --help 看用法）");
        process.exit(2);
    }
  }
  return o;
}

const args = parseArgs(process.argv);
const say = (s) => { if (!args.json) console.log(s); };

// ─────────────────────────── 配置 / token ───────────────────────────
function loadConfig() {
  const p = path.join(__dirname, "config.json");
  let cfg = {};
  if (fs.existsSync(p)) {
    try { cfg = JSON.parse(fs.readFileSync(p, "utf8")); }
    catch (e) { throw new Error("kook/config.json 不是合法 JSON: " + e.message); }
  }
  const merged = Object.assign({
    guild_id: "", channel_id: "",
    token_file: "token/kook.txt",
    pack_dir: "E:\\soft\\game\\eb\\Azeroth\\Binaries\\Win64\\Games\\Emberveil\\live\\Azeroth\\Interface\\AddOns",
    assets: "versioned",
    card: { theme: "primary", size: "lg", header: "EvalHelp v{ver} 发布" },
    links: {},
    changelog_file: "CHANGELOG.md",
    notes_max_chars: 900,
  }, cfg);
  if (args.guild) merged.guild_id = args.guild;
  if (args.channel) merged.channel_id = args.channel;
  if (args.dir) merged.pack_dir = args.dir;
  if (args.assets) merged.assets = args.assets;
  return merged;
}

function readToken(cfg) {
  const fromEnv = process.env.KOOK_TOKEN && process.env.KOOK_TOKEN.trim();
  if (fromEnv) return { token: fromEnv, from: "环境变量 KOOK_TOKEN" };
  const p = path.resolve(ROOT, args.tokenFile || cfg.token_file);
  if (fs.existsSync(p)) {
    const t = fs.readFileSync(p, "utf8").trim();
    if (t) return { token: t, from: path.relative(ROOT, p) };
  }
  return null;
}

// ───────────────────────── 版本与文件发现（全部现读） ─────────────────────────
function tocVersion(tocPath) {
  const s = fs.readFileSync(tocPath, "utf8");
  const m = s.match(/^##\s*Version:\s*(\S+)/m);
  return m ? m[1].trim() : null;
}

function discoverVersions() {
  const mainToc = path.join(ROOT, "EvalHelp.toc");
  if (!fs.existsSync(mainToc)) throw new Error("找不到 EvalHelp.toc（仓库根不对？）");
  const mainVer = tocVersion(mainToc);
  if (!mainVer) throw new Error("EvalHelp.toc 里读不到 ## Version");
  const subs = [];
  const addonsDir = path.join(ROOT, "addons");
  if (fs.existsSync(addonsDir)) {
    for (const name of fs.readdirSync(addonsDir).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()))) {
      const d = path.join(addonsDir, name);
      if (!fs.statSync(d).isDirectory()) continue;
      const toc = path.join(d, name + ".toc");
      if (!fs.existsSync(toc)) continue;
      const v = tocVersion(toc);
      if (v) subs.push({ name, version: v });
    }
  }
  return { mainVer, subs };
}

function resolveAssets(cfg, ver, filesOverride) {
  const dir = cfg.pack_dir;
  const out = { dir, wanted: [], missing: [], stale: [], files: [] };

  if (filesOverride) {
    for (const f of filesOverride) {
      const abs = path.isAbsolute(f) ? f : path.resolve(ROOT, f);
      if (!fs.existsSync(abs)) { out.missing.push(abs); continue; }
      const base = path.basename(abs);
      const m = base.match(/^(.+?)-v[\d.]+[a-z]?\.zip$/i);
      out.files.push({ name: base, abs, role: "手动指定", plugin: m ? m[1] : base.replace(/\.zip$/i, "") });
    }
    return out;
  }

  if (!fs.existsSync(dir)) {
    throw new Error("打包产物目录不存在：" + dir + "（用 --dir 指定，或先跑打包脚本）");
  }

  const want = [{ name: "EvalHelp", version: ver.mainVer, role: "主插件" }];
  for (const s of ver.subs) want.push({ name: s.name, version: s.version, role: "子插件" });

  for (const w of want) {
    const versioned = path.join(dir, `${w.name}-v${w.version}.zip`);
    const fixed = path.join(dir, `${w.name}.zip`);
    out.wanted.push({ ...w, versioned, fixed });

    if (fs.existsSync(versioned)) {
      out.files.push({ name: path.basename(versioned), abs: versioned, role: w.role, plugin: w.name });
      if (cfg.assets === "both" && fs.existsSync(fixed)) {
        out.files.push({ name: path.basename(fixed), abs: fixed, role: w.role + "（固定名）", plugin: w.name });
      }
    } else {
      out.missing.push(path.basename(versioned));
    }
  }

  // 过期包体检：包里名字带的版本 != toc 现读版本 ⇒ 提醒（防止把旧包当新包发）
  for (const f of fs.readdirSync(dir)) {
    const m = f.match(/^(.+)-v(.+)\.zip$/i);
    if (!m) continue;
    const w = want.find(x => x.name === m[1]);
    if (w && w.version !== m[2]) out.stale.push({ file: f, declared: m[2], expected: w.version });
    if (!w && /^EvalHelp$/i.test(m[1])) out.stale.push({ file: f, declared: m[2], expected: ver.mainVer });
  }
  return out;
}

function sha256(p) {
  return crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex").toUpperCase();
}

// 体积显示：≥1 MiB 用 MB，否则用 KB（EH_DPS 这种 26 KB 的包不该显示成 0.0 MB）
function fmtSize(b) {
  return b >= 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.round(b / 1024) + " KB";
}


// ───────────────────── 发布帖拆分（按插件分类进不同分区） ─────────────────────
// 用户 2026-10-09 定：「将插件自动发布包对应插件分类内」⇒ 一版发布 = 多条帖，
// 每条帖进它自己的**帖子分区**，只带 config.json `posts[].plugins` 里列的那几个插件的包。
function resolvePosts(cfg, ver, files) {
  const all = [{ name: "EvalHelp", version: ver.mainVer, role: "主插件" }]
    .concat(ver.subs.map(s => ({ name: s.name, version: s.version, role: "子插件" })));
  const byName = {};
  for (const f of files) byName[f.plugin] = f;

  const defs = (Array.isArray(cfg.posts) && cfg.posts.length) ? cfg.posts
    : [{ name: "全部", category_id: cfg.category_id || "", title: cfg.card.header, plugins: all.map(p => p.name) }];

  const posts = [], count = {};
  for (const d of defs) {
    const plugins = (d.plugins || []).map(n => all.find(p => p.name === n)).filter(Boolean);
    for (const p of plugins) count[p.name] = (count[p.name] || 0) + 1;
    const own = plugins.map(p => byName[p.name]).filter(Boolean);
    posts.push({
      name: d.name || "(未命名)", category_id: d.category_id || "", plugins, files: own,
      cover: d.cover || null, images: d.images || null,
      title: String(d.title || cfg.card.header)
        .replace("{ver}", ver.mainVer)
        .replace("{sub}", (plugins.find(p => p.name !== "EvalHelp") || {}).version || "")
        .replace("{names}", plugins.map(p => p.name).join(" / ")),
    });
  }
  const unassigned = all.filter(p => !count[p.name]).map(p => p.name);
  const dup = Object.keys(count).filter(n => count[n] > 1);
  return { posts, unassigned, dup, all };
}

// ───────────────────────── 更新文案（总结制，不是流水账） ─────────────────────────
// 用户 2026-10-09 定：「kook 更新文案需要总结，不要做版本流水账记录」⇒
//   ① 首选 kook/notes/<版本>.md —— 人（或 AI 在 release 时）写好的**对外总结**；
//   ② 退路 = 从 CHANGELOG 该版本段落里**只抽标题行**自动汇总（丢掉正文细节、引用块、版本跨越叙事）；
//   ③ --no-notes 完全不附；--notes-auto 强制看自动摘要长什么样。
function clip(s, max) {
  s = (s || "").replace(/\r\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
  if (!s) return null;
  if (max && s.length > max) s = s.slice(0, max).trimEnd() + " …";
  return s;
}

function readNotesFile(p, max) {
  if (!fs.existsSync(p)) return null;
  return clip(fs.readFileSync(p, "utf8"), max);
}

// 取 CHANGELOG 里当前版本那一段（到下一个同级/更高级标题为止）
function changelogSection(cfg, ver) {
  const file = path.join(ROOT, cfg.changelog_file);
  if (!fs.existsSync(file)) return null;
  const lines = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n").split("\n");
  let start = -1, level = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/^(#{1,6})\s*(.*)$/);
    if (m && m[2].includes(ver.mainVer)) { start = i; level = m[1].length; break; }
  }
  if (start < 0) return null;
  const body = [];
  for (let i = start + 1; i < lines.length; i++) {
    const m = lines[i].match(/^(#{1,6})\s/);
    if (m && m[1].length <= level) break;
    body.push(lines[i]);
  }
  return body.join("\n");
}

// 自动摘要 = 只抽「独占一行的粗体标题行」，并过滤掉内部口吻/版本流水
const AUTO_SKIP = /(判据|交付|真因|调研|探针|存档|闸门|收口|接线|源码|回归|结案|自证|落盘|闸门|本地|测试|验证)/;
const VER_RE = /\d+\.\d+\.\d+/;
function autoSummary(section, maxLines) {
  const out = [];
  for (const raw of section.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith(">") || line.startsWith("|")) continue;   // 引用块/表格 = 流水账与索引
    const m = line.match(/^\*\*\s*(?:[①-⑳]|\d+[.、)]?)?\s*([^*]{4,140}?)\s*\*\*$/) ||
              line.match(/^\*\*\s*(?:[①-⑳])?\s*([^*]{4,140}?)\s*\*\*/);
    if (!m) continue;
    let t = m[1]
      .replace(/[（(][^（）()]*\d+\.\d+\.\d+[^（）()]*[)）]/g, "")   // 去掉任何带版本号的括号（含「0.2.28 → 0.2.36」这类）
      .replace(/^\d+[.、)]\s*/, "")
      .replace(/\s{2,}/g, " ")
      .trim();
    if (t.length < 4) continue;
    if (VER_RE.test(t)) continue;          // 仍带版本号 ⇒ 是流水账，丢掉
    if (AUTO_SKIP.test(t)) continue;       // 内部口吻 ⇒ 丢掉
    if (!out.includes(t)) out.push(t);
    if (out.length >= (maxLines || 5)) break;
  }
  return out.length ? out.map(t => "- " + t).join("\n") : null;
}

// 文案支持**按插件分段**（用户 2026-10-09 定：「概要记录每次插件发布的修改」）：
//   kook/notes/<版本>.md 里用 `## 插件名` 分段；每条帖只取它自己那几个插件的段落。
//   首个 `##` 之前的内容 = 整体开场，只放进第一条帖。
function parseNoteSections(text) {
  if (!text) return { sections: null, generic: null };
  const sections = {};
  let cur = null, buf = [], generic = null;
  const flush = () => {
    if (cur) sections[cur] = ((sections[cur] || "") + "\n" + buf.join("\n").trim()).trim();
    buf = [];
  };
  for (const ln of text.split("\n")) {
    const m = ln.match(/^##\s+(.+?)\s*$/);
    if (m) { flush(); cur = m[1].trim(); continue; }
    if (cur) buf.push(ln);
    else generic = (generic === null ? "" : generic) + ln + "\n";
  }
  flush();
  const names = Object.keys(sections);
  if (!names.length) return { sections: null, generic: null };
  return { sections, generic: generic && generic.trim() ? clip(generic, null) : null };
}

function resolveNotes(cfg, ver) {
  if (args.notes === "") return { text: null, sections: null, generic: null, source: "命令行 --no-notes（不附更新说明）" };

  if (args.notes) {
    const t = readNotesFile(path.resolve(ROOT, args.notes), cfg.notes_max_chars);
    return Object.assign({ text: t, source: `--notes 指定的文件：${args.notes}` }, parseNoteSections(t));
  }

  const per = path.join(__dirname, "notes", ver.mainVer + ".md");
  if (!args.notesAuto && fs.existsSync(per)) {
    const t = readNotesFile(per, cfg.notes_max_chars);
    const sec = parseNoteSections(t);
    return Object.assign({ text: t, source: `对外文案文件 kook/notes/${ver.mainVer}.md（推荐路径）` }, sec,
      { source: sec.sections ? `对外文案文件 kook/notes/${ver.mainVer}.md（按插件分段）` : `对外文案文件 kook/notes/${ver.mainVer}.md（未分段 ⇒ 只放进第一条帖）` });
  }

  const sec = changelogSection(cfg, ver);
  const auto = (cfg.notes_fallback === "none") ? null : (sec ? autoSummary(sec) : null);
  return { text: auto, sections: null, generic: null, source: auto
    ? `⚠ 自动摘要（只抽 CHANGELOG 标题行，已滤掉版本流水/内部口吻）——建议手写一份 kook/notes/${ver.mainVer}.md 当对外文案`
    : `⚠ 没有 kook/notes/${ver.mainVer}.md，本次不附更新说明（config.json 的 notes_fallback 可改自动摘要/不附）` };
}

// 取某条帖该显示的文案
function notesForPost(notesInfo, plugins, isFirst) {
  if (!notesInfo) return null;
  if (!notesInfo.sections) return isFirst ? (notesInfo.text || null) : null;
  const parts = [];
  if (isFirst && notesInfo.generic) parts.push(notesInfo.generic.trim());
  for (const p of plugins) {
    const sec = notesInfo.sections[p.name];
    if (sec) parts.push(`**${p.name}**\n${sec.trim()}`);
  }
  return parts.length ? parts.join("\n\n") : null;
}

// ───────────────────────────── HTTP（零依赖） ─────────────────────────────
const rateState = { last: null, minInterval: args.minInterval, consecutive429: 0 };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
function maskToken(s) {
  const t = process.env.KOOK_TOKEN;
  return typeof s === "string" ? s.replace(/Bot\s+\S+/g, "Bot ***") : s;
}
function noteRate(h) {
  const g = (k) => h.get("x-rate-limit-" + k);
  rateState.last = { limit: g("limit"), remaining: g("remaining"), reset: g("reset"), bucket: g("bucket"), global: h.get("x-rate-limit-global") };
  return rateState.last;
}

async function apiFetch(method, url, { token, body, formData, retry = 0 } = {}) {
  const headers = { Authorization: "Bot " + token, "Accept-Language": "zh-CN" };
  if (body !== undefined) headers["Content-Type"] = "application/json; charset=utf-8";
  await sleep(rateState.minInterval);
  const res = await fetch(url, { method, headers, body: formData || (body !== undefined ? JSON.stringify(body) : undefined) });
  const rl = noteRate(res.headers);

  if (res.status === 429) {
    rateState.consecutive429++;
    const wait = (parseInt(rl.reset || "5", 10) + 1) * 1000;
    console.error(`[限流] HTTP 429（bucket=${rl.bucket || "?"} reset=${rl.reset}s）→ 等待 ${wait}ms 后重试`);
    if (rateState.consecutive429 >= 3 || retry >= 2) {
      throw new Error("连续触发限流，主动中止（官方明确多次超速可能禁用 bot）");
    }
    await sleep(wait);
    return apiFetch(method, url, { token, body, formData, retry: retry + 1 });
  }

  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* 非 JSON（如网关错误页） */ }
  const stamp = `[${res.status}] ${method} ${url.replace(API, "/api/v3")}` +
                (rl.limit ? `  ratelimit=${rl.remaining}/${rl.limit} reset=${rl.reset}s bucket=${rl.bucket || "?"}` : "");
  say(stamp);
  if (!json) throw new Error(`${stamp}\n响应不是 JSON：${maskToken(text.slice(0, 300))}`);
  if (json.code !== 0) {
    const err = new Error(`${stamp}\ncode=${json.code} message=${json.message}`);
    err.kookCode = json.code;
    throw err;
  }
  // 头里 Limit 存在 ⇒ 说明是受控接口；正常路径也回报剩余额度便于观察
  return json.data;
}

// ───────────────────────────── 卡片组装 ─────────────────────────────
function buildCard(cfg, ver, files, notes, extra, post, images) {
  post = post || { title: cfg.card.header,
                   plugins: [{ name: "EvalHelp", version: ver.mainVer }].concat(ver.subs) };
  const title = String(post.title || cfg.card.header).replace("{ver}", ver.mainVer);
  const modules = [];
  modules.push({ type: "header", text: { type: "plain-text", content: title } });

  // 版本行只列**本条帖带的插件**（一版拆成多条帖后，每条只讲自己那几个）
  const plugins = post.plugins || [];
  const main = plugins.find(p => p.name === "EvalHelp");
  const subs = plugins.filter(p => p.name !== "EvalHelp");
  const lines = [];
  if (main) lines.push(`**版本**：EvalHelp \`${main.version}\``);
  if (main && subs.length) lines.push(`**子插件**：` + subs.map(s => `${s.name} \`${s.version}\``).join(" · "));
  if (!main && plugins.length) lines.push(`**插件**：` + plugins.map(s => `${s.name} \`${s.version}\``).join(" · "));
  lines.push(`**发布时间**：${new Date().toLocaleString("zh-CN", { hour12: false, timeZone: "Asia/Shanghai" })}（北京时间）`);
  const links = [];
  if (cfg.links.github) links.push(`[GitHub](${cfg.links.github.replace("{ver}", ver.mainVer)})`);
  if (cfg.links.gitee) links.push(`[Gitee](${cfg.links.gitee.replace("{ver}", ver.mainVer)})`);
  if (links.length) lines.push(`**发布页（本次 v${ver.mainVer}）**：` + links.join(" ｜ "));
  modules.push({ type: "section", text: { type: "kmarkdown", content: lines.join("\n") } });

  if (notes) {
    modules.push({ type: "divider" });
    // 文案自带头部（以 ** 开头）就原样用；否则补一个「本次更新」小标题
    const body = notes.trimStart().startsWith("**") ? notes : "**本次更新**\n" + notes;
    modules.push({ type: "section", text: { type: "kmarkdown", content: body } });
  }

  modules.push({ type: "divider" });
  if (images && images.length) {
    // 正文配图（KOOK 卡片：image-group 支持 1~9 张；src 必须是本机器人上传过的资源）
    modules.push({ type: "image-group", elements: images.map(u => ({ type: "image", src: u.url || u.src })) });
  }
  const attached = files.filter(f => f.url);
  if (attached.length) {
    for (const u of attached) {
      modules.push({ type: "file", src: u.url, title: `${u.name}（${u.role}）` });
    }
  }
  // 下载区（link 模式 = 主通道；file 模式里超上限的包也走这里）
  const linked = files.filter(f => !f.url);
  if (linked.length) {
    const dl = cfg.download_base || {};
    const dlLines = linked.map(f => {
      const pairs = [];
      if (dl.gitee) pairs.push(`[Gitee](${dl.gitee.replace("{ver}", ver.mainVer).replace("{name}", f.name)})`);
      if (dl.github) pairs.push(`[GitHub](${dl.github.replace("{ver}", ver.mainVer).replace("{name}", f.name)})`);
      const mb = f.bytes ? ` · ${f.bytes >= 1048576 ? (f.bytes / 1048576).toFixed(1) + " MB" : Math.round(f.bytes / 1024) + " KB"}` : "";
      return `- **${f.name}**（${f.role}${mb}）\n  ${pairs.join(" ｜ ") || "（未配置下载链接模板）"}`;
    });
    modules.push({ type: "section", text: { type: "kmarkdown",
      content: `**下载**（点开即下，Gitee 为主 / GitHub 备用）\n` + dlLines.join("\n") } });
  }
  if (files.length) {
    const hashLines = files.map(u => `${u.name}\nSHA256 ${String(u.sha256).slice(0, 16)}…`).join("\n");
    modules.push({ type: "context", elements: [{ type: "kmarkdown", content: hashLines }] });
  }
  if (extra) modules.push({ type: "context", elements: [{ type: "kmarkdown", content: extra }] });

  return [{ type: "card", theme: cfg.card.theme, size: cfg.card.size, modules }];
}

// ───────────────── 封面 / 正文配图（取该帖插件自己的 ./preview） ─────────────────
// 用户 2026-10-09 定：「kook 发帖需要添加一张封面.从对应插件的 ./preview 内取一张 … 将对应插件内的
// ./preview 内的图片上传」⇒ 图片必须先 asset/create 上传，再把 url 放进卡片 image-group；
// ★封面也放进正文配图 —— KOOK 官方规则：资源只有作为**卡片图片元素**发出去才刷新可见状态。
// ★卡片 image 只吃 jpeg/gif/png（preview 里本来都是 png）。
function previewDirFor(pluginName) {
  return pluginName === "EvalHelp" ? path.join(ROOT, "preview")
                                    : path.join(ROOT, "addons", pluginName, "preview");
}
function listPreviewImages(pluginName) {
  const d = previewDirFor(pluginName);
  if (!fs.existsSync(d)) return [];
  return fs.readdirSync(d)
    .filter(f => /\.(png|jpe?g|gif)$/i.test(f))
    .map(f => {
      const abs = path.join(d, f);
      const st = fs.statSync(abs);
      return { name: f, abs, plugin: pluginName, bytes: st.size, mtime: st.mtimeMs };
    })
    .sort((a, b) => b.mtime - a.mtime);          // 新的在前
}

// 取某条帖的封面与配图：config 里写了 images/cover 就按名字取（跨该帖各插件的 preview 找）；
// 没写就自动挑（按 preview.prefer 列表，再按 mtime 最新）
function pickPreview(cfg, post) {
  const pv = cfg.preview || {};
  if (pv.enabled === false) return { cover: null, images: [] };
  const perPlugin = {};
  for (const p of post.plugins) {
    const all = listPreviewImages(p.name);
    if (!all.length) continue;
    const ordered = [];
    for (const want of (pv.prefer || [])) {
      const hit = all.find(x => x.name.toLowerCase() === String(want).toLowerCase());
      if (hit && !ordered.includes(hit)) ordered.push(hit);
    }
    for (const x of all) if (!ordered.includes(x)) ordered.push(x);
    perPlugin[p.name] = ordered;
  }
  const findByName = (nm) => {
    for (const p of post.plugins) {
      const hit = (perPlugin[p.name] || []).find(x => x.name.toLowerCase() === String(nm).toLowerCase());
      if (hit) return hit;
    }
    return null;
  };

  let images = [];
  if (Array.isArray(post.images) && post.images.length) {
    images = post.images.map(findByName).filter(Boolean);
    for (const nm of post.images) if (!findByName(nm)) say(`   ⚠ preview 里找不到配图「${nm}」（该帖插件：${post.plugins.map(p => p.name).join("/")}）`);
  } else {
    const cap = Number(pv.max_per_post || 3);
    for (const p of post.plugins) {
      const first = (perPlugin[p.name] || [])[0];
      if (first && !images.includes(first)) images.push(first);
      if (images.length >= cap) break;
    }
  }
  const cover = post.cover ? findByName(post.cover) : (images[0] || null);
  if (post.cover && !cover) say(`   ⚠ preview 里找不到封面「${post.cover}」`);
  if (cover && !images.includes(cover)) images.unshift(cover);
  return { cover, images };
}

// ───────────────────────────── 主流程 ─────────────────────────────
function printPlan(cfg, ver, assets, postsInfo, notesInfo) {
  const { posts } = postsInfo;
  say("── 发布计划（dry-run，未发送任何请求） ─────────────────────────");
  say(`服务器 : ${cfg.guild_id}    频道 : ${cfg.channel_id}`);
  say(`频道链接: https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}`);
  say(`产物目录: ${assets.dir}`);
  say(`版本    : EvalHelp ${ver.mainVer}` + (ver.subs.length ? " + " + ver.subs.map(s => `${s.name} ${s.version}`).join(", ") : ""));
  say(`拆成 ${posts.length} 条帖（按插件分类进各自分区）：`);
  posts.forEach((p, i) => {
    say("");
    say(`  帖 ${i + 1}【${p.name}】分区=${p.category_id || "（综合）"}  标题=「${p.title}」`);
    say(`      插件：${p.plugins.map(x => `${x.name} ${x.version}`).join(" · ") || "（无）"}`);
    for (const f of p.files) say(`      包：${f.name}  ${(fs.statSync(f.abs).size / 1024).toFixed(1)} KB  sha256=${sha256(f.abs).slice(0, 16)}…`);
    const nt = notesForPost(notesInfo, p.plugins, i === 0);
    const ntInfo = nt ? (nt.split("\n").length + " 行（来源：" + notesInfo.source + "）") : "（无）";
    say(`      概要：${ntInfo}`);
    const pick = pickPreview(cfg, p);
    say(`      封面：${pick.cover ? `${pick.cover.plugin}/${pick.cover.name}（${fmtSize(pick.cover.bytes)}）` : "（无）"}`);
    say(`      配图：${pick.images.length ? pick.images.map(x => `${x.plugin}/${x.name}(${fmtSize(x.bytes)})`).join(" · ") : "（无）"}`);
  });
  if (postsInfo.unassigned.length) {
    say("");
    say(`⚠ 这些插件没有被任何一条帖认领（它们的包不会发出去）：${postsInfo.unassigned.join(", ")}`);
  }
  if (postsInfo.dup.length) say(`⚠ 这些插件被多条帖重复认领：${postsInfo.dup.join(", ")}`);
  if (assets.stale.length) {
    say("");
    say("⚠ 目录里存在版本号与 .toc 不一致的旧包（本次不会上传，但说明打包可能没重跑）：");
    for (const s of assets.stale) say(`  · ${s.file}（包名 ${s.declared} ≠ toc ${s.expected}）`);
  }
  say("");
  say(`文案来源：${notesInfo.source}`);
  const firstNotes = notesForPost(notesInfo, posts[0].plugins, true);
  if (firstNotes) { say("帖 1 的概要正文："); say(firstNotes.split("\n").map(l => "  " + l).join("\n")); }
  else say("  （帖 1 也没有概要正文）");
  say("");
  const am = String(args.attach || cfg.attach_mode || "link").toLowerCase();
  say(`附件模式：${am === "file" ? "上传附件" : "link —— 帖子里只放下载链接，不上传任何文件"}` +
      (am === "file" ? "" : "（实测 KOOK 单文件上限 ≈30 MiB，主插件包 63.8 MB 传不上去）"));
  say("将发出的请求（真发时会先读一次 channel/view，按频道类型选通道）：");
  if (am === "file") {
    for (const p of posts) for (const f of p.files) say(`  POST /api/v3/asset/create      file=${f.name}`);
  } else {
    say("  （无 asset/create —— link 模式不传文件）");
  }
  say(`  帖子频道(type=4) ⇒ POST /api/v3/thread/create × ${posts.length}（各带 category_id）`);
  say(`  文字频道(type=1) ⇒ POST /api/v3/message/create type=10 × ${posts.length}`);
  say("");
  say("确认无误后加 --send 真发（脚本不会替你决定）。");
}

async function doCheck(cfg, token) {
  say("── 只读自检 ───────────────────────────────────────────────");
  const me = await apiFetch("GET", `${API}/user/me`, { token });
  say(`机器人  : ${me.username}#${me.identify_num}  id=${me.id}`);
  say(`在线    : ${me.online}   os=${me.os || "-"}   bot=${me.bot}   intent=${me.intent}（事件订阅掩码，-1=收全部）`);
  say("（HTTP 发消息不要求机器人「在线」；要收事件才需要连 WebSocket）");

  // ★ 决定成败的一条：机器人到底在不在这个服务器里（不在 ⇒ 一切写操作都无从谈起）
  const guilds = await apiFetch("GET", `${API}/guild/list?page_size=50`, { token });
  const gItems = guilds.items || [];
  const inGuild = gItems.some(g => String(g.id) === String(cfg.guild_id));
  say(`机器人所在服务器（${gItems.length} 个）：` + (gItems.map(g => `${g.name}(${g.id})`).join(" · ") || "（一个都没有）"));
  if (!inGuild) {
    say("");
    say(`  ⚠⚠ 机器人**不在**目标服务器 ${cfg.guild_id} 里 ⇒ 现在发不了任何消息。`);
    say("     去开发者后台 → 机器人 → 「邀请链接」把机器人拉进该服务器（机器人是公共机器人时任何人可加）。");
    say("");
  }

  const guild = await apiFetch("GET", `${API}/guild/view?guild_id=${cfg.guild_id}`, { token });
  say(`服务器  : ${guild.name}  (${guild.id})  频道 ${guild.channels ? guild.channels.length : 0} 个 / 角色 ${guild.roles ? guild.roles.length : 0} 个`);

  // 频道清单（用 guild/view 一次性拿到的数据）——用来核对「配置的频道 id 是不是你想的那个频道」
  const catName = {};
  for (const c of (guild.channels || [])) if (c.is_category) catName[c.id] = c.name;
  say("");
  say("服务器频道清单（◀ = config.json 里配置的目标频道）：");
  const chans = (guild.channels || []).slice().sort((a, b) => (a.is_category === b.is_category)
    ? String(a.parent_id || "").localeCompare(String(b.parent_id || "")) || (a.level - b.level) || a.name.localeCompare(b.name)
    : (a.is_category ? -1 : 1));
  for (const c of chans) {
    const kind = c.is_category ? "分组" : (c.type === 2 ? "语音" : (c.type === 1 ? "文字" : (c.type === 4 ? "帖子" : "type" + c.type)));
    const parent = c.parent_id ? `  ↳${catName[c.parent_id] || c.parent_id}` : "";
    const mark = String(c.id) === String(cfg.channel_id) ? "  ◀ 配置的目标频道" : "";
    say(`  [${kind}] ${String(c.name).padEnd(14)} id=${c.id}${parent}${mark}`);
  }

  const ch = await apiFetch("GET", `${API}/channel/view?target_id=${cfg.channel_id}`, { token });
  say("");
  say(`目标频道: ${ch.name}  type=${ch.type} is_category=${ch.is_category} parent=${ch.parent_id || "-"} topic=${ch.topic ? ch.topic.slice(0, 40) : "-"}`);
  if (ch.type !== 1) {
    if (ch.type === 4) {
      say("ℹ 目标频道是**帖子频道**（type=4）：发布走 `thread/create` 发帖，不是普通频道消息（脚本已自动识别）。");
      // 帖子分区（Category）：不选分区 ⇒ 只出现在「综合」页
      try {
        const cats = await apiFetch("GET", `${API}/category/list?channel_id=${cfg.channel_id}`, { token });
        const list = cats.list || cats.items || [];
        say(`  帖子分区（${list.length} 个）：` + (list.map(c => `${c.name}(id=${c.id})`).join(" · ") || "（无自定义分区，发帖即「综合」）"));
        if (cfg.category_id) say(`  config.json 指定分区 category_id=${cfg.category_id}（发帖会带这个分区）`);
      } catch (e) { say("  ⓘ 分区列表读不到：" + String(e.message).split("\n").slice(-1)[0]); }
    } else say("⚠ 目标频道不是文字频道（type≠1）—— 普通卡片/文件消息可能发不进去");
  }

  // 机器人在**本服务器**里的角色：按可靠度依次尝试
  //   ① user/view?user_id=&guild_id= —— 文档明确返回「用户在当前服务器中的角色 id 列表」（最对路）
  //   ② guild/user-list?filter_user_id=（实测本机器人返回非 0 code ⇒ 打印原因后跳过）
  //   ③ user/me 的 roles（文档未说明归属服务器）
  let roleIds = [];
  let roleSrc = "";
  const probe = async (label, fn) => {
    try { const r = await fn(); return r; }
    catch (e) { say(`  ⓘ ${label} 不可用：${String(e.message).split("\n").slice(-1)[0]}`); return null; }
  };

  const uv = await probe("user/view", () => apiFetch("GET", `${API}/user/view?user_id=${me.id}&guild_id=${cfg.guild_id}`, { token }));
  if (uv && Array.isArray(uv.roles) && uv.roles.length) { roleIds = uv.roles; roleSrc = "user/view（本服务器角色，文档化路径）"; }

  if (!roleIds.length) {
    const gu = await probe("guild/user-list", () => apiFetch("GET", `${API}/guild/user-list?guild_id=${cfg.guild_id}&filter_user_id=${me.id}`, { token }));
    const item = gu && (gu.items || [])[0];
    if (item && Array.isArray(item.roles) && item.roles.length) { roleIds = item.roles; roleSrc = "guild/user-list"; }
  }

  if (!roleIds.length) {
    if (Array.isArray(me.roles) && me.roles.length) { roleIds = me.roles; roleSrc = "user/me 的 roles"; }
    else if (me.roles && typeof me.roles === "object" && Object.keys(me.roles).length) {
      roleIds = Object.values(me.roles).map(r => (r && r.role_id) || r); roleSrc = "user/me 的 roles(map)";
    }
  }
  if (!roleIds.length) roleSrc = "读不到（机器人可能一个角色都没有 ⇒ 只有 @全体成员 的权限）";

  // 角色权限表用 guild/view 已经返回的 roles[]：
  // ★ guild-role/list 需要「管理角色权限」(bit10)，纯发布机器人没有该权限 ⇒ 实测返回 403「你没有权限进行此操作」，
  //   所以不要去调它（这也是本项目「先核调用本身对不对」的又一例）。
  const roles = { items: guild.roles || [] };
  const BITS = { 1: "管理员", 32: "频道管理", 2048: "查看频道", 4096: "发布消息", 8192: "管理消息", 16384: "上传文件" };
  let perms = 0;
  for (const r of (roles.items || [])) if (roleIds.includes(r.role_id)) perms |= r.permissions;
  say(`  角色来源=${roleSrc} · 机器人 roles=${JSON.stringify(roleIds)} · user/me.roles=${JSON.stringify(me.roles)}`);
  say(`  服务器角色表（${roles.items.length} 个）：` + (roles.items.map(r => `${r.name}(id=${r.role_id},perms=${r.permissions})`).join(" · ") || "（空）"));
  say("");
  say("机器人角色权限位（服务器级；频道级覆写可能再收紧，无接口可算最终值）：");
  for (const v of Object.keys(BITS).map(Number).sort((a, b) => a - b)) {
    say(`  ${BITS[v].padEnd(6)} = ${String(v).padStart(7)}  ${(perms & v) === v ? "✔ 有" : "✘ 无"}`);
  }
  say(`  机器人 roles=${JSON.stringify(roleIds)}  perms=${perms}`);
  say("（bit12 发布消息 + bit11 查看频道 是发消息的下限；上传文件建议有 bit14）");
}

// 发完回读确认 status（实测：创建瞬间可能是 1 审核中，稍后变 2）
async function waitThreadApproved(cfg, token, threadId, tries = 4, gapMs = 2500) {
  let last = null;
  for (let i = 0; i < tries; i++) {
    const d = await apiFetch("GET", `${API}/thread/view?channel_id=${cfg.channel_id}&thread_id=${threadId}`, { token });
    last = d && d.status;
    if (last === 2) return { status: last, tries: i + 1 };
    await sleep(gapMs);
  }
  return { status: last, tries };
}

async function doSend(cfg, token, ver, postsInfo, notesInfo) {
  // ★ 目标频道类型决定走哪套接口（实测：用户服务器里的「插件发布」是 type=4 ⇒ 帖子频道）：
  //   type=4 帖子频道 ⇒ 只能用 /thread/create 发**帖子**（普通 message/create 发不进去）
  //   其它（type=1 文字） ⇒ /message/create
  const chInfo = await apiFetch("GET", `${API}/channel/view?target_id=${cfg.channel_id}`, { token });
  const isThreadChannel = chInfo.type === 4;
  say(`目标频道：${chInfo.name}  type=${chInfo.type}${isThreadChannel ? "（帖子频道 ⇒ 走 thread/create 发帖）" : "（普通频道 ⇒ 走 message/create）"}`);
  say(`本次发布 = ${postsInfo.posts.length} 条帖`);
  // 附件模式（用户 2026-10-09 定：link = 只放 Gitee/GitHub 下载链接，不上传任何文件）
  //   ★实测 KOOK 单文件上限 ≈30 MiB ⇒ 主插件包 63.8 MB 本来就传不上去（nginx 413 / 业务码 40014）
  const attachMode = String(args.attach || cfg.attach_mode || "link").toLowerCase();
  const maxAssetMB = Number(cfg.max_asset_mb || 30);
  say(`附件模式：${attachMode === "file" ? `上传附件（单文件上限按 ${maxAssetMB} MB 兜底）` : "link（只放下载链接，不上传任何文件）"}`);
  const footer = "本消息由 release 脚本自动发布 · kook/kook_publish.js";
  const result = [];

  for (let i = 0; i < postsInfo.posts.length; i++) {
    const post = postsInfo.posts[i];
    const notes = notesForPost(notesInfo, post.plugins, i === 0);
    say("");
    say(`══ 帖 ${i + 1}/${postsInfo.posts.length}【${post.name}】分区=${post.category_id || "（综合）"} ══`);
    say(`   标题：${post.title}`);

    // 1) 组装本条的包清单；file 模式下逐个上传（超上限自动降级为下载链接）
    const files = [];
    for (const f of post.files) {
      const bytes = fs.statSync(f.abs).size;
      const rec = { name: f.name, role: f.role, bytes, sha256: sha256(f.abs) };
      const oversize = bytes > maxAssetMB * 1024 * 1024;
      if (attachMode !== "file") {
        say(`   · ${f.name}（${fmtSize(bytes)}）⇒ 下载链接`);
      } else if (oversize) {
        say(`   · ${f.name}（${fmtSize(bytes)}）★超 ${maxAssetMB} MB 上限 ⇒ 降级为下载链接`);
      } else {
        const fd = new FormData();
        // 注意：不要手动设置 Content-Type，否则 boundary 丢失 ⇒ 接口按官方要求必须是 form-data
        fd.append("file", new Blob([fs.readFileSync(f.abs)]), f.name);
        const data = await apiFetch("POST", `${API}/asset/create`, { token, formData: fd });
        const url = data && data.url;
        if (!url) throw new Error("asset/create 没返回 url：" + JSON.stringify(data));
        // 实测：KOOK 会把上传的文件名改成随机串 ⇒ 频道里的显示名**只来自卡片 file 模块的 title**
        rec.url = url;
        say(`   ✔ 上传 ${f.name} → ${url}`);
      }
      files.push(rec);
    }

    // 1.5) 封面 / 正文配图：从该帖插件自己的 ./preview 取 → asset/create 上传（KOOK 只认本机器人上传过的资源）
    const pick = pickPreview(cfg, post);
    const images = [];
    if (pick.cover) say(`   ● 封面：${pick.cover.plugin}/${pick.cover.name}（${fmtSize(pick.cover.bytes)}）`);
    for (const im of pick.images) {
      const bytes = im.bytes;
      const oversize = bytes > maxAssetMB * 1024 * 1024;
      if (oversize) { say(`   · 配图 ${im.plugin}/${im.name}（${fmtSize(bytes)}）★超 ${maxAssetMB} MB 上限 ⇒ 跳过`); continue; }
      const fd = new FormData();
      fd.append("file", new Blob([fs.readFileSync(im.abs)]), im.name);
      const data = await apiFetch("POST", `${API}/asset/create`, { token, formData: fd });
      const url = data && data.url;
      if (!url) throw new Error("配图 asset/create 没返回 url：" + JSON.stringify(data));
      images.push({ ...im, url });
      say(`   ✔ 配图上传 ${im.plugin}/${im.name}（${fmtSize(bytes)}）→ ${url}`);
    }
    const coverUrl = (pick.cover && (images.find(x => x.abs === pick.cover.abs) || {}).url) || null;

    // 2) 发帖 / 发消息
    if (isThreadChannel) {
      const card = buildCard(cfg, ver, files, notes, footer, post, images);
      const data = await apiFetch("POST", `${API}/thread/create`, {
        token,
        body: Object.assign(
          { channel_id: cfg.channel_id, guild_id: cfg.guild_id, title: post.title, content: JSON.stringify(card) },
          post.category_id ? { category_id: String(post.category_id) } : {},
          coverUrl ? { cover: coverUrl } : {}),
      });
      say(`   ✔ 帖子 id=${data.id}  status=${data.status}（创建瞬间；1 审核中 / 2 通过 / 3 编辑审核中）` +
          (coverUrl ? "  封面已带" : "  ⚠ 未带封面"));
      if (data.status !== 2) {
        const w = await waitThreadApproved(cfg, token, data.id);
        say(`   回读 thread/view：status=${w.status}（第 ${w.tries} 次）` +
            (w.status === 2 ? " ✔ 已通过，频道里可见" : ` ⚠ 仍未通过 ⇒ 需在客户端放行`));
      }
      result.push({ post: post.name, category_id: post.category_id, thread_id: data.id, title: post.title,
                    files: files.map(u => ({ name: u.name, url: u.url || null, bytes: u.bytes })) });
    } else if (args.mode === "file") {
      for (const u of files.filter(x => x.url)) {
        await apiFetch("POST", `${API}/message/create`, { token, body: { type: 4, target_id: cfg.channel_id, content: u.url } });
        say(`   ✔ 已发文件消息：${u.name}`);
      }
      result.push({ post: post.name, files: files.map(u => ({ name: u.name, url: u.url || null })) });
    } else {
      const card = buildCard(cfg, ver, files, notes, footer, post);
      const data = await apiFetch("POST", `${API}/message/create`, {
        token, body: { type: 10, target_id: cfg.channel_id, content: JSON.stringify(card) },
      });
      say(`   ✔ msg_id=${data.msg_id || JSON.stringify(data)}`);
      result.push({ post: post.name, files: files.map(u => ({ name: u.name, url: u.url || null })) });
    }
  }

  say("");
  say(`完成：共 ${result.length} 条帖。频道：https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}`);
  // ★把「版本 → 帖子 id」记账（kook/state/releases.json，读-改-写；供 kook_guide.js --done 配发布链接用）
  try {
    const p = path.join(__dirname, "state", "releases.json");
    let rel = {};
    if (fs.existsSync(p)) { try { rel = JSON.parse(fs.readFileSync(p, "utf8")); } catch {} }
    rel[ver.mainVer] = {
      at: Date.now(),
      channel_id: cfg.channel_id,
      threads: result.map(r => ({ post: r.post, id: r.thread_id || null, title: r.title || null, files: (r.files || []).map(f => f.name) })),
    };
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, JSON.stringify(rel, null, 2), "utf8");
    say(`（已记账：kook/state/releases.json → v${ver.mainVer} 共 ${result.length} 条帖，供「完成回填」配发布链接）`);
  } catch (e) { console.error("⚠ 发布记账失败（不影响发布本身）：" + e.message); }
  return result;
}

(async function main() {
  try {
    const cfg = loadConfig();
    if (!cfg.guild_id || !cfg.channel_id) throw new Error("config.json 里缺 guild_id / channel_id");

    if (process.env.HTTPS_PROXY || process.env.HTTP_PROXY) {
      if (process.env.NODE_USE_ENV_PROXY) {
        say("⚠ 检测到 NODE_USE_ENV_PROXY：node 会走代理访问 kookapp.cn（国内站走代理常失败）。必要时 unset。");
      }
    }

    const tokenInfo = readToken(cfg);
    const ver = discoverVersions();

    // token 就位检查（--check/--send 需要）
    if (args.check || args.send) {
      if (!tokenInfo) {
        console.error("✘ 找不到 KOOK bot token。任选一种：");
        console.error("   ① 把 token 写进 " + path.resolve(ROOT, cfg.token_file) + "（该目录已被 .gitignore 忽略）");
        console.error("   ② 设置环境变量 KOOK_TOKEN");
        process.exit(2);
      }
      say(`token 来源：${tokenInfo.from}（值不打印）`);
      say("");
    }

    // --check 是「只读自检」：**先于打包产物检查**独立跑（自检的意义就是先确认身份/频道/权限）
    if (args.check) {
      await doCheck(cfg, tokenInfo.token);
      say("");
      if (!args.send) return;
    }

    // 帖子频道辅助动作（回读 / 删除）—— 与发布主流程无关，先处理
    if (args.threadView) {
      const d = await apiFetch("GET", `${API}/thread/view?channel_id=${cfg.channel_id}&thread_id=${args.threadView}`, { token: tokenInfo.token });
      say(`帖子 ${d.id}  「${d.title}」`);
      say(`  status=${d.status}（1 审核中 / 2 通过 / 3 编辑审核中）  post_count=${d.post_count}  收藏=${d.collect_num || 0}`);
      say(`  分区=${d.category ? (d.category.name || d.category.id) : "（综合）"}  封面=${d.cover || "-"}`);
      say(`  预览=${String(d.preview_content || "").slice(0, 120)}`);
      say(`  medias=${JSON.stringify(d.medias || [])}`);
      say(`  建帖时间=${d.create_time}  最后活跃=${d.latest_active_time}`);
      if (d.status !== 2) say("  ⚠ status≠2 ⇒ 频道里可能还看不到（该帖子频道开了审核，需在客户端放行）");
      return;
    }
    if (args.threadDelete) {
      if (!args.send) { console.error("✘ 删帖是写操作：请同时加 --send 明确表示要删"); process.exit(2); }
      const d = await apiFetch("POST", `${API}/thread/delete`, { token: tokenInfo.token, body: { channel_id: cfg.channel_id, thread_id: args.threadDelete } });
      say(`✔ 已删除帖子 ${args.threadDelete}（返回 ${JSON.stringify(d)}）`);
      return;
    }

    const assets = resolveAssets(cfg, ver, args.files);
    const notesInfo = resolveNotes(cfg, ver);
    const notes = notesInfo.text;
    const postsInfo = resolvePosts(cfg, ver, assets.files);

    if (assets.missing.length) {
      console.error("✘ 缺包（先跑打包脚本，别发旧包）：");
      for (const m of assets.missing) console.error("   " + m);
      if (assets.stale.length) {
        console.error("   目录里下列包的版本号与 .toc 现读版本不一致 ⇒ 打包没重跑：");
        for (const s of assets.stale) console.error(`     ${s.file}（包名 ${s.declared} ≠ toc ${s.expected}）`);
      }
      console.error("   打包：powershell -NoProfile -ExecutionPolicy Bypass -File tmp\\pack_subaddons.ps1");
      process.exit(2);
    }
    if (!assets.files.length) throw new Error("没有可上传的文件（用 --files 或 --dir 指定）");
    if (postsInfo.unassigned.length) {
      console.error("✘ 这些插件没被 config.json 的 posts[] 认领（包发不出去）：" + postsInfo.unassigned.join(", "));
      console.error("  请在 kook/config.json 的 posts[].plugins 里把它们归到某条帖。");
      process.exit(2);
    }
    if (postsInfo.dup.length) {
      console.error("✘ 这些插件被多条帖重复认领（会重复上传）：" + postsInfo.dup.join(", "));
      process.exit(2);
    }

    if (args.json) {
      const out = {
        guild_id: cfg.guild_id, channel_id: cfg.channel_id,
        version: ver.mainVer, sub_addons: ver.subs,
        posts: postsInfo.posts.map(p => ({ name: p.name, category_id: p.category_id, title: p.title,
          plugins: p.plugins.map(x => `${x.name} ${x.version}`),
          files: p.files.map(f => ({ name: f.name, role: f.role, bytes: fs.statSync(f.abs).size, sha256: sha256(f.abs) })) })),
        stale: assets.stale, mode: args.mode, sent: false,
        notes: { source: notesInfo.source, per_plugin: !!notesInfo.sections },
      };
      if (args.send) {
        out.sent = true; out.results = await doSend(cfg, tokenInfo.token, ver, postsInfo, notesInfo);
      }
      console.log(JSON.stringify(out, null, 2));
      return;
    }

    if (args.send)  { await doSend(cfg, tokenInfo.token, ver, postsInfo, notesInfo); }
    else            {
      printPlan(cfg, ver, assets, postsInfo, notesInfo);
      if (args.printCard) {
        // 离线检视卡片结构：src 用占位串（真实 url 只有上传后才存在）
        say("");
        say("── 各帖卡片 JSON（type=10 / thread 主楼的 content，src 为占位） ──");
        postsInfo.posts.forEach((p, i) => {
          const placeholders = p.files.map(f => ({ name: f.name, role: f.role, bytes: fs.statSync(f.abs).size,
                                                    sha256: sha256(f.abs),
                                                    url: (args.attach || cfg.attach_mode) === "file" ? "<asset url>" : undefined }));
          const card = buildCard(cfg, ver, placeholders, notesForPost(notesInfo, p.plugins, i === 0),
                                 "本消息由 release 脚本自动发布 · kook/kook_publish.js", p);
          console.log(`── 帖 ${i + 1}【${p.name}】 ──`);
          console.log(JSON.stringify(card, null, 2));
        });
      }
    }
  } catch (e) {
    console.error("✘ " + maskToken(e.message));
    process.exit(e.kookCode ? 3 : 2);
  }
})();
