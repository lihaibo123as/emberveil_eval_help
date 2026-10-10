#!/usr/bin/env node
/**
 * kook_guide.js —— KOOK 服务器「自动化引导」：新人欢迎词（事件驱动）+ 公告维护（幂等）
 *
 * 需求（用户 2026-10-09）：「现在可以完善下 以上两个信息的自动化引导.欢迎词,公告之类的」
 *   · 那两个信息 = 截图里红线下划的 **欢迎大厅的欢迎消息** 与 **公告与通知频道**。
 *
 * 事实（官方文档 + 真机只读实测，全部见 kook/CLAUDE.md）：
 *   · **新成员加入有事件**：`extra.type = "joined_guild"`（body = `{user_id, joined_at}`）⇒ 欢迎词可**事件驱动**，不必轮询。
 *     （`exited_guild` = 成员退出；`updated_guild_member` = 角色/昵称变化。）
 *   · 欢迎大厅里那条「系统通知#0001 … 但他还没有意识到问题的严重性…」是 **KOOK 原生欢迎频道**发的
 *     （服务器设置 `welcome_channel_id` = 欢迎大厅），**不是机器人发的**、也不是我们能改的 —— 我们这条欢迎词与它并存。
 *   · 事件只能经 **WebSocket**（或 Webhook，两者互斥）收；Gateway = `GET /api/v3/gateway/index?compress=0`。
 *   · 公告 = `message/create` → 记住 msg_id → 之后**原地 `message/update`**（幂等、不刷屏、不重复发）。
 *
 * 用法（默认 dry-run，写操作要 `--send`；常驻监听用 `--listen`）：
 *   node kook/kook_guide.js --check                      # 只读自检：token/机器人/两频道/现有公告/账本
 *   node kook/kook_guide.js --announce                   # 演练：打印将发/将改的公告正文与请求
 *   node kook/kook_guide.js --announce --send            # 真发（首次建，之后原地更新；--no-pin 可关置顶）
 *   node kook/kook_guide.js --topic                      # 演练：给「建议反馈」写**友好的使用说明**（频道简介 topic）
 *   node kook/kook_guide.js --topic --send               # 真改（幂等：与现有一致就跳过；--force 强写）
 *   node kook/kook_guide.js --update-announce            # 演练：本版更新公告（「公告与通知」频道，按版本记账）
 *   node kook/kook_guide.js --update-announce --send     # 真发（release 第 10 步发完帖之后跑；同版本重跑 = 原地更新）
 *   node kook/kook_guide.js --welcome <user_id> --send   # 手工发一条欢迎（补发/测试用）
 *   node kook/kook_guide.js --listen                     # 常驻：收 joined_guild → 发欢迎词（Ctrl+C 停）
 *   node kook/kook_guide.js --listen --dry              # 常驻但不真发（只打印「本会发什么」）
 *
 * 账本：`kook/state/guide.json`（公告 msg_id · 已欢迎过的成员 · WebSocket 的 maxSn/session_id，用于断线 resume）
 * 纪律：token 只从 `token/kook.txt` 或环境变量读，**绝不打印**；幂等（同名公告只建一次）；限频 + 429 退避。
 */

"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const ROOT = path.resolve(__dirname, "..");
const API = "https://www.kookapp.cn/api/v3";

// ───────────────────────────── CLI ─────────────────────────────
const args = { send: false, check: false, announce: false, listen: false, welcome: null,
               dry: false, noPin: false, scan: false, queue: false, plan: false, backfill: false,
               done: null, version: null, note: "", thread: null, noScan: false, simulate: null, minInterval: 500,
               topic: false, channel: null, updateAnnounce: false };
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  switch (a) {
    case "--send":     args.send = true; break;
    case "--check":    args.check = true; break;
    case "--announce": args.announce = true; break;
    case "--update-announce": args.updateAnnounce = true; break;
    case "--topic":    args.topic = true; break;
    case "--channel":  args.channel = process.argv[++i]; break;
    case "--listen":   args.listen = true; break;
    case "--welcome":  args.welcome = process.argv[++i]; break;
    case "--scan":     args.scan = true; break;
    case "--queue":    args.queue = true; break;
    case "--plan":     args.plan = true; break;
    case "--simulate": args.simulate = process.argv[++i]; break;
    case "--backfill": args.backfill = true; break;
    case "--no-scan":  args.noScan = true; break;
    case "--force":    args.force = true; break;
    case "--done":     args.done = process.argv[++i]; break;
    case "--version":  args.version = process.argv[++i]; break;
    case "--note":     args.note = process.argv[++i]; break;
    case "--msg-delete": (args.msgDelete = args.msgDelete || []).push(process.argv[++i]); break;
    case "--thread":   args.thread = process.argv[++i]; break;
    case "--dry":      args.dry = true; break;
    case "--no-pin":   args.noPin = true; break;
    case "--min-interval": args.minInterval = parseInt(process.argv[++i], 10); break;
    case "-h": case "--help":
      console.log(fs.readFileSync(__filename, "utf8").split("*/")[0].replace(/^\/\*\*?/, "")); process.exit(0);
    default: console.error("未知参数：" + a); process.exit(2);
  }
}
const say = (...a) => console.log(...a);

// ───────────────────────── 配置 / token / 账本 ─────────────────────────
function loadConfig() {
  const p = path.join(ROOT, "kook", "config.json");
  const cfg = JSON.parse(fs.readFileSync(p, "utf8").replace(/^\s*\/\/.*$/gm, ""));
  cfg.guide = Object.assign({
    welcome_channel_id: "8320814423228312",
    announce_channel_id: "1294357982211130",
    feedback_channel_id: "8514014383612159",
    // ★★★2026-10-10 用户定：「eval 就是我」⇒ 本人（作者）的 KOOK id 列表：这些人的发言**一律不入队**
    //   （「我的回复不需要理解为需求」）；其中对某条需求的**结论性答复**用于把那条判 `rejected`
    //   （那一判在复核时人工做，见 INBOX 处理指引第 0 条）。
    owner_ids: [],
    welcome_file: "kook/guide/welcome.md",
    announce_file: "kook/guide/announce.md",
    update_file: "kook/guide/update.md",
    feedback_file: "kook/guide/feedback.md",
    state_file: "kook/state/guide.json",
    queue_file: "kook/queue/feedback.json",
    inbox_file: "kook/queue/INBOX.md",
    releases_file: "kook/state/releases.json",
    pin_announce: true,
    cooldown_sec: 8,
  }, cfg.guide || {});
  return cfg;
}
function readToken(cfg) {
  if (process.env.KOOK_TOKEN && process.env.KOOK_TOKEN.trim()) return { token: process.env.KOOK_TOKEN.trim(), from: "环境变量 KOOK_TOKEN" };
  const p = path.resolve(ROOT, cfg.token_file || "token/kook.txt");
  const t = fs.existsSync(p) ? fs.readFileSync(p, "utf8").trim() : "";
  return t ? { token: t, from: path.relative(ROOT, p) } : null;
}
function statePath(cfg) { return path.resolve(ROOT, cfg.guide.state_file); }
function loadState(cfg) {
  const p = statePath(cfg);
  if (!fs.existsSync(p)) return {};
  try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return {}; }
}
function saveState(cfg, st) {
  const p = statePath(cfg);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(st, null, 2), "utf8");
}
// ★★★**提交前必须先读回再合并**（2026-10-09 真机踩到）：监听进程常驻、每个事件都写 max_sn，
//   而公告/欢迎是**另一个进程**在写同一个 state 文件 ⇒ 直接 saveState(内存里的旧副本) 会把对方的
//   `announce_msg_id` 覆盖掉（实测：公告发成功、账本里却没有 msg_id ⇒ 下次发布会**重复新建一条公告**）。
//   ⇒ 一律走 saveStatePatch（读-改-写），**绝不再直接写整份内存快照**。
function saveStatePatch(cfg, patch) {
  const cur = loadState(cfg);
  Object.assign(cur, patch);
  saveState(cfg, cur);
  return cur;
}
function readTemplate(cfg, which, repl) {
  const p = path.resolve(ROOT, cfg.guide[which + "_file"]);
  if (!fs.existsSync(p)) throw new Error("文案文件不存在：" + path.relative(ROOT, p));
  let s = fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n").trim();
  for (const [k, v] of Object.entries(repl || {})) s = s.split(k).join(v);
  return s;
}

// ───────────────────────────── HTTP（零依赖） ─────────────────────────────
const rt = { min: args.minInterval, consecutive429: 0 };
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
async function api(method, url, body, token, retry = 0) {
  const headers = { Authorization: "Bot " + token, "Accept-Language": "zh-CN" };
  if (body !== undefined) headers["Content-Type"] = "application/json; charset=utf-8";
  await sleep(rt.min);
  const res = await fetch(url, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const rl = res.headers.get("x-rate-limit-limit")
    ? `ratelimit=${res.headers.get("x-rate-limit-remaining")}/${res.headers.get("x-rate-limit-limit")} reset=${res.headers.get("x-rate-limit-reset")}s bucket=${res.headers.get("x-rate-limit-bucket")}`
    : "";
  if (res.status === 429) {
    rt.consecutive429++;
    const wait = (parseInt(res.headers.get("x-rate-limit-reset") || "5", 10) + 1) * 1000;
    console.error(`[限流] 429 → 等 ${wait}ms 重试`);
    if (rt.consecutive429 >= 3 || retry >= 2) throw new Error("连续限流，主动中止（官方：多次超速可能禁用 bot）");
    await sleep(wait);
    return api(method, url, body, token, retry + 1);
  }
  const txt = await res.text();
  let json = null; try { json = JSON.parse(txt); } catch {}
  say(`  [${res.status}] ${method} ${url.replace(API, "/api/v3")} ${rl}`);
  if (!json) throw new Error(`响应不是 JSON：${txt.slice(0, 200)}`);
  if (json.code !== 0) { const e = new Error(`code=${json.code} message=${json.message}`); e.kookCode = json.code; throw e; }
  return json.data;
}

// ───────────────────────────── 公告（幂等） ─────────────────────────────
function announceBody(cfg) {
  const toc = fs.readFileSync(path.join(ROOT, "EvalHelp.toc"), "utf8");
  const ver = (toc.match(/^##\s*Version:\s*(\S+)/m) || [])[1] || "";
  const subs = fs.readdirSync(path.join(ROOT, "addons")).sort((a, b) => a.localeCompare(b)).map(n => {
    const t = path.join(ROOT, "addons", n, n + ".toc");
    const v = fs.existsSync(t) ? (fs.readFileSync(t, "utf8").match(/^##\s*Version:\s*(\S+)/m) || [])[1] : "";
    return v ? `${n} ${v}` : null;
  }).filter(Boolean);
  const vline = `当前版本：**EvalHelp v${ver}**` + (subs.length ? ` ｜ 子插件：${subs.join(" · ")}` : "");
  // 模板里写了 `{version_line}` 就插在那（推荐：放在末尾的维护说明块里）；没写则追加在最后（向后兼容）
  let body = readTemplate(cfg, "announce", { "{version_line}": vline });
  if (!body.includes(vline)) body += `\n\n> ${vline}`;
  return body;
}

async function doAnnounce(cfg, token) {
  const st = loadState(cfg);
  const content = announceBody(cfg);
  const target = cfg.guide.announce_channel_id;
  const existing = st.announce_msg_id || null;
  say(`公告频道 = ${target}；${existing ? `已有公告 msg_id=${existing} ⇒ 原地更新` : "首次发布 ⇒ 新建"}`);
  say("──────── 公告正文（KMarkdown） ────────");
  say(content);
  say("─────────────────────────────────────");
  if (!args.send || args.dry) { say("（dry-run：未发送。加 --send 真发）"); return; }
  let msgId;
  if (existing) {
    await api("POST", `${API}/message/update`, { msg_id: existing, content }, token);
    msgId = existing;
    say(`✔ 公告已**原地更新**（msg_id=${msgId}）`);
  } else {
    const d = await api("POST", `${API}/message/create`, { type: 9, target_id: target, content }, token);
    msgId = d.msg_id;
    saveStatePatch(cfg, { announce_msg_id: msgId });     // ★读-改-写（别覆盖监听进程写的 max_sn）
    say(`✔ 公告已发布（msg_id=${msgId}）`);
  }
  if (cfg.guide.pin_announce && !args.noPin) {
    try {
      await api("POST", `${API}/message/pin`, { msg_id: msgId, target_id: target }, token);
      say("✔ 已置顶（需要「管理消息」权限）");
    } catch (e) { console.error("⚠ 置顶失败（不影响公告本身）：" + e.message); }
  }
}

// ───────────────── 频道说明（「建议反馈」怎么提 = 频道简介 topic） ─────────────────
// 需求（用户 2026-10-09）：「kook 给建议反馈频道增加一个友好的使用说明频道说明」。
// 官方事实（kook/01 §3.4）：`topic` 只能在 `channel/update` 里改（创建时设不了），**仅文字频道有效**；
//   读 = `channel/view?target_id=`（也可从 `guild/view.channels[]` 一次拿全）。
// 口径：① **文案单一来源** = `kook/guide/feedback.md`（改文案只改这个文件，不写死在脚本里；
//   也**不随版本变** —— 它是「怎么提建议」的常青说明，版本流水请去「公告与通知」看）；
//   ② 幂等：与现有一致 ⇒ 跳过（除非 `--force`）；③ 写完**回读自证**，不一致就如实报错退出（绝不假装成功）。
const TOPIC_MAX = 200;   // 自定上限（官方未文档化长度限制，取一个保守值，超了就要求精简文案）
function feedbackTopicBody(cfg) {
  return readTemplate(cfg, "feedback", {});
}
async function doTopic(cfg, token, channelArg) {
  const target = channelArg || cfg.guide.feedback_channel_id;
  const body = feedbackTopicBody(cfg);
  const ch = await api("GET", `${API}/channel/view?target_id=${target}`, undefined, token);
  const old = String(ch.topic || "").replace(/\r\n/g, "\n").trim();
  say(`频道 = ${target}「${ch.name}」type=${ch.type}${ch.type === 1 ? "" : "（★非文字频道 ⇒ topic 无效，别写）"}`);
  say(`当前简介（${old.length} 字）：${old ? old.split("\n").map(l => "    " + l).join("\n") : "（空）"}`);
  say(`拟写入（${body.length} 字）：`);
  say(body.split("\n").map(l => "    " + l).join("\n"));
  if (body.length > TOPIC_MAX) {
    console.error(`✘ 文案 ${body.length} 字 > 自定上限 ${TOPIC_MAX} 字 ⇒ 请精简 ${path.relative(ROOT, path.resolve(ROOT, cfg.guide.feedback_file))}`);
    process.exit(2);
  }
  if (ch.type !== 1) { console.error("✘ 只有文字频道（type=1）能写 topic ⇒ 已中止（一个字节都不写）"); process.exit(2); }
  if (old === body && !args.force) { say("= 与现有一致 ⇒ 跳过写入（要强写加 --force）"); return; }
  if (!args.send || args.dry) { say(`（dry-run：未写入。加 --send 真改；请求 = POST /channel/update {channel_id:${target}, topic:…}）`); return; }
  await api("POST", `${API}/channel/update`, { channel_id: target, topic: body }, token);
  say("✔ 已写入");
  const back = await api("GET", `${API}/channel/view?target_id=${target}`, undefined, token);
  const got = String(back.topic || "").replace(/\r\n/g, "\n").trim();
  if (got === body) say(`✔ 回读一致（${got.length} 字）`);
  else { console.error(`⚠ 回读不一致（服务端可能截断/改写）\n  期望 ${body.length} 字：${body}\n  实得 ${got.length} 字：${got}`); process.exit(3); }
}

// ───────── 本版更新公告（release 第 10 步之后发到「公告与通知」） ─────────
// 需求（用户 2026-10-10）：「在每次 release 完成之后，对 kook 新插件发布之后，需要再在公告通知内发布对应插件更新信息」。
// 与常驻引导公告（`--announce`）**是两条不同的消息**，互不覆盖：
//   · `--announce` = **常青**的服务器指引（一条，原地更新 + 置顶，msg_id 存 `state.announce_msg_id`）；
//   · `--update-announce` = **每版一条**的更新通知（按版本记账 `state.update_announce[<版本>] = msg_id`，
//     同一版本重跑 = **原地更新**，绝不重复发帖；**不置顶**（置顶位留给常青公告））。
// 三条口径：① 正文来源 = `kook/guide/update.md` 模板 + **`kook/notes/<版本>.md` 原文**（与 KOOK 发布帖同一份
//   对外概要 —— 单一来源，绝不另写一份）；② **只列本版真有变化的插件**：从 `state/releases.json[版本]` 的
//   `threads[]`（真发了帖的）与 `skipped[]`（版本没变、按规范没发的）现读；没有记录 ⇒ 如实说「见帖子」；
//   ③ **写完回读自证**（`message/view`），不一致如实报，不假装成功。
const UPDATE_NOTES_MAX = 1800;   // 正文里 notes 段的自定上限（超了就截到段落边界 + 指路「插件发布」）
function notesPath(cfg, ver) { return path.join(ROOT, "kook", "notes", ver + ".md"); }
// 帖名 → 该帖带哪些插件（主插件帖的 post 名是「主插件」，插件名是 EvalHelp ⇒ 必须过这张表，别拿帖名当插件名）
function pluginsOfPost(cfg, postName) {
  const p = (cfg.posts || []).find(x => x.name === postName);
  return p && p.plugins && p.plugins.length ? p.plugins : [postName];
}
function changedPluginsFor(cfg, ver) {
  const rel = loadReleases(cfg)[ver];
  const changed = [], skipped = [];
  if (rel) {
    for (const t of (rel.threads || [])) {
      if (t.deleted) continue;
      for (const n of pluginsOfPost(cfg, t.post)) if (changed.indexOf(n) < 0) changed.push(n);
    }
    for (const s of (rel.skipped || [])) if (skipped.indexOf(s) < 0) skipped.push(s);
  }
  return { changed, skipped, rel: rel || null };
}
// ★★★插件名 → **可点详情链接**（用户 2026-10-10 看图提：「子插件需要一超链接的形式可点击跳转对应插件详情」，
//   随后澄清：「**超链接是内联；链接跳转的是 KOOK 内部的插件发布详情**」）⇒ 目标一律 = **该插件在「插件发布」频道里的详情帖**：
//   ① **优先 KOOK 帖**：`releases.json` 按 `at` 倒序找**含这个插件的、未删的帖** ⇒ 帖子深链
//      （本版有变化的插件就命中本版的那条帖；**本版未变动的插件** ⇒ 命中它**最近一次**发过的那条帖，
//       这也正是「该插件的详情」——玩家点进去看到的就是这个插件的说明与下载）；
//   ② 兜底 `config.json` 的 **`plugin_links[<插件名>]`**（Emberveil 平台详情页）—— **只在完全没发过帖时**才用
//      （正常情况一个插件至少有历史帖；★平台页 2026-10-10 逐条实测：`addon` / 四个子插件 = 200，`evalhelp-eh-mail` = 404）；
//   ③ 都没有 ⇒ **纯文字**（**绝不编链接** —— 点进去 404 比不可点更糟）。
function pluginLink(cfg, name) {
  const rel = loadReleases(cfg);
  const vers = Object.keys(rel).sort((a, b) => (rel[b].at || 0) - (rel[a].at || 0));
  for (const v of vers) {
    for (const t of (rel[v].threads || [])) {
      if (t.deleted || !t.id) continue;
      const hitPost = pluginsOfPost(cfg, t.post).indexOf(name) >= 0;
      const hitFile = (t.files || []).some(f => f.indexOf(name + "-v") === 0);
      if (hitPost || hitFile) {
        return `https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}/${t.id}`;
      }
    }
  }
  const fallback = (cfg.plugin_links || {})[name];
  return fallback || null;
}
function nameLink(cfg, name) {
  const u = pluginLink(cfg, name);
  return u ? `[${name}](${u})` : name;
}
function updateNoticeBody(cfg, ver) {
  const { changed, skipped } = changedPluginsFor(cfg, ver);
  let notes;
  const np = notesPath(cfg, ver);
  if (fs.existsSync(np)) {
    notes = fs.readFileSync(np, "utf8").replace(/\r\n/g, "\n").trim();
    if (notes.length > UPDATE_NOTES_MAX) {
      notes = notes.slice(0, UPDATE_NOTES_MAX).replace(/\n[^\n]*$/, "") + "\n……（完整说明见「插件发布」频道本版帖子）";
    }
  } else {
    notes = `（本版更新要点见「插件发布」频道 v${ver} 的帖子）`;
  }
  const link = versionLink(cfg, ver, null);
  return readTemplate(cfg, "update", {
    "{ver}": ver,
    // ★插件名一律渲染成 `[名字](详情页)`（见 nameLink：平台详情页 → 退回该插件最近发布帖 → 纯文字）
    "{changed}": changed.length ? changed.map(n => nameLink(cfg, n)).join(" · ") : "（见「插件发布」频道本版帖子）",
    "{unchanged}": skipped.length ? `\n本版未变动：${skipped.map(n => nameLink(cfg, n)).join(" · ")}` : "",
    "{notes}": notes,
    // ★★链接一律走 KMarkdown，**长 URL 绝不裸放**（裸链接又长又不一定可点）：
    //   {link} = 帖子深链（模板里套进 `[文字](url)`）；{channel} = `#频道` 卡片链接
    //   （`(chn)id(chn)` 由客户端渲染成可点的频道名，本客户端已实测可用 —— 欢迎语里同款）。
    "{link}": link || `https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}`,
    "{channel}": `(chn)${cfg.channel_id}(chn)`,
  }).replace(/\n{3,}/g, "\n\n");
}
function tocVersion() {
  return (fs.readFileSync(path.join(ROOT, "EvalHelp.toc"), "utf8").match(/^##\s*Version:\s*(\S+)/m) || [])[1] || "";
}
async function doUpdateAnnounce(cfg, token, verArg) {
  const ver = verArg || tocVersion();
  if (!ver) { console.error("✘ 读不到版本号（用 --version <版本> 显式指定，或检查 EvalHelp.toc 的 ## Version）"); process.exit(2); }
  const target = cfg.guide.announce_channel_id;
  const st = loadState(cfg);
  const existing = (st.update_announce || {})[ver] || null;
  const { changed, skipped, rel } = changedPluginsFor(cfg, ver);
  const content = updateNoticeBody(cfg, ver);
  say(`本版 = v${ver}（${verArg ? "显式指定" : "现读 EvalHelp.toc"}）；公告频道 = ${target}`);
  say(`releases.json 里${rel ? "有" : "**没有**"}本版记录 ⇒ 本版有变化的插件（真发过帖的）：${changed.join(" · ") || "（无记录）"}`);
  if (skipped.length) say(`本版无变化（按规范没发帖）：${skipped.join(" · ")}`);
  say(existing ? `已有本版更新公告 msg_id=${existing} ⇒ 原地更新（不重复发帖）` : "首次发布本版更新公告 ⇒ 新建一条（不置顶）");
  say("──────── 本版更新公告正文（KMarkdown） ────────");
  say(content);
  say("───────────────────────────────────────────");
  if (!args.send || args.dry) { say("（dry-run：未发送。加 --send 真发）"); return; }
  let msgId;
  if (existing) {
    await api("POST", `${API}/message/update`, { msg_id: existing, content }, token);
    msgId = existing;
    say(`✔ 已**原地更新**（msg_id=${msgId}）`);
  } else {
    const d = await api("POST", `${API}/message/create`, { type: 9, target_id: target, content }, token);
    msgId = d.msg_id;
    const cur = Object.assign({}, loadState(cfg).update_announce || {}, { [ver]: msgId });
    saveStatePatch(cfg, { update_announce: cur });      // ★读-改-写（别覆盖监听进程写的 max_sn）
    say(`✔ 已发布（msg_id=${msgId}）`);
  }
  try {
    const m = await api("GET", `${API}/message/view?msg_id=${msgId}`, undefined, token);
    const got = String(m.content || "").replace(/\r\n/g, "\n").trim();
    const stamp = new Date(m.updated_at || m.create_at).toLocaleString("zh-CN", { hour12: false });
    if (got === content.trim()) say(`✔ 回读一致（${got.length} 字 · 最后更新 ${stamp}）`);
    else console.error(`⚠ 回读不一致（服务端可能改写/截断，消息已发出、未回滚）\n  期望 ${content.trim().length} 字｜实得 ${got.length} 字`);
  } catch (e) { console.error("⚠ 回读失败（不影响已发出的公告）：" + e.message); }
}

// ───────────────────────────── 欢迎词 ─────────────────────────────
function welcomeBody(cfg, userId) {
  return readTemplate(cfg, "welcome", { "{user}": `(met)${userId}(met)` });
}
async function doWelcome(cfg, token, userId, st) {
  const content = welcomeBody(cfg, userId);
  const target = cfg.guide.welcome_channel_id;
  say(`欢迎 ${userId} ⇒ ${target}`);
  if (!args.send || args.dry) { say("  （dry-run：本会发送）\n" + content.split("\n").map(l => "    " + l).join("\n")); return; }
  const d = await api("POST", `${API}/message/create`, { type: 9, target_id: target, content }, token);
  say(`  ✔ 已发欢迎词 msg_id=${d.msg_id}`);
  const cur = loadState(cfg);
  saveStatePatch(cfg, { welcomed: Object.assign({}, cur.welcomed || {}, { [userId]: Date.now() }) });
}

// ───────────────────────────── 常驻监听（WebSocket） ─────────────────────────────
// 信令：0 事件 · 1 HELLO · 2 PING(c→s) · 3 PONG · 5 RECONNECT(清 sn) · 6 RESUME ACK
async function doListen(cfg, token) {
  const me = await api("GET", `${API}/user/me`, undefined, token);
  say(`机器人 ${me.username}#${me.identify_num}（id=${me.id}）  intent=${me.intent}`);
  say(`欢迎频道 = ${cfg.guide.welcome_channel_id}（欢迎词${args.send && !args.dry ? "会真发" : "只演练"}）`);
  const st = loadState(cfg);
  let maxSn = Number(st.max_sn || 0);
  let sessionId = st.session_id || null;
  let ws = null, hb = null, closed = false;

  async function connect(resume) {
    const g = await api("GET", `${API}/gateway/index?compress=0`, undefined, token);
    let url = g.url;
    if (resume && sessionId) url += `&resume=1&sn=${maxSn}&session_id=${encodeURIComponent(sessionId)}`;
    say(`连接 gateway…${resume ? `（resume sn=${maxSn}）` : ""}`);
    ws = new WebSocket(url);

    ws.addEventListener("open", () => say("  ws 已连接，等 HELLO"));
    ws.addEventListener("message", async (ev) => {
      let m; try { m = JSON.parse(typeof ev.data === "string" ? ev.data : String(ev.data)); } catch { return; }
      if (m.s === 1) {
        if (m.d.code !== 0) { say(`  HELLO 失败 code=${m.d.code}（40101 无效 token / 40103 过期）`); return; }
        sessionId = m.d.session_id; saveStatePatch(cfg, { session_id: sessionId });
        say(`  HELLO ok session=${sessionId}`);
        clearInterval(hb);
        hb = setInterval(() => { try { ws.send(JSON.stringify({ s: 2, sn: maxSn })); } catch {} }, 30000);
        return;
      }
      if (m.s === 3) return;                                     // PONG
      if (m.s === 5) { say(`  ⚠ RECONNECT（${m.d && m.d.code}）⇒ 清 sn 与队列后重连`); maxSn = 0; sessionId = null; saveStatePatch(cfg, { max_sn: 0, session_id: null }); try { ws.close(); } catch {} return; }
      if (m.s === 6) { say("  RESUME ACK：离线消息已补齐"); return; }
      if (m.s !== 0) return;

      const sn = Number(m.sn || 0);
      if (sn && sn <= maxSn) return;                             // 重投：丢弃
      if (sn) { maxSn = sn; saveStatePatch(cfg, { max_sn: sn }); }
      const d = m.d || {}, t = d.extra && d.extra.type;
      const body = (d.extra && d.extra.body) || {};
      say(`  ← 事件 extra.type=${t || "?"} (type=${d.type}, channel_type=${d.channel_type}, sn=${sn})`);
      // 建议反馈频道：玩家的普通消息**实时入队**（机器人自己的 / 系统消息 / **本人（作者）的**不入）
      const ownerMsg = isOwner(cfg, d.author_id);
      if (ownerMsg) say("    （本人/作者发言 ⇒ 不入队；若是结论性答复 ⇒ 复核时把对应需求判 rejected）");
      if (d.channel_type === "GROUP" && String(d.target_id) === String(cfg.guide.feedback_channel_id)
          && d.type !== 255 && String(d.author_id) !== String(me.id) && !ownerMsg) {
        const q = loadQueue(cfg);
        const text = String(d.content || "").replace(/\s+/g, " ").trim();
        const au = (d.extra && d.extra.author) || {};
        if (text && enqueue(cfg, q, { msg_id: d.msg_id, user_id: String(d.author_id),
              user: au.nickname || au.username || "", at: d.msg_timestamp || Date.now(), text, source: "live" })) {
          saveQueue(cfg, q);
          say(`    ✔ 建议入队（队列共 ${q.items.length} 条；标签 ${tagOf(text).join("/")}）`);
        }
      }
      if (t === "joined_guild") {
        const uid = String(body.user_id || "");
        if (!uid) return;
        if (uid === String(me.id)) { say("    （是我自己进服，跳过）"); return; }
        const curW = loadState(cfg).welcomed || {};
        if (curW[uid]) { say(`    （${uid} 已欢迎过，跳过）`); return; }
        try { await doWelcome(cfg, token, uid); } catch (e) { console.error("  ✘ 欢迎词发送失败：" + e.message); }
      } else if (t === "exited_guild") {
        say(`    （成员退出 ${body.user_id}）`);
      }
    });
    ws.addEventListener("close", async () => {
      clearInterval(hb);
      if (closed) return;
      say("  ws 断开 ⇒ 指数退避重连（先 resume，失败再重取 gateway）");
      for (const wait of [2000, 4000, 8000, 16000, 30000, 60000]) {
        await sleep(wait);
        try { await connect(!!sessionId); return; } catch (e) { say("  重连失败：" + e.message); }
      }
      say("  ✘ 连续重连失败，退出（请检查网络/机器人状态）");
      process.exit(1);
    });
    ws.addEventListener("error", (e) => say("  ws error：" + (e.message || e.type)));
  }

  await connect(!!sessionId);
  process.on("SIGINT", () => { closed = true; try { ws.close(); } catch {}; say("\n已停止监听。"); process.exit(0); });
}

// ─────────────── 建议反馈 → 优化队列（用户 2026-10-09 定：「将意见建议自动进行 AI 问题汇总
//              会加入插件优化队列.做自动化优化流程」） ───────────────
// 入口两条：① 常驻监听（`--listen`）收到该频道的消息**实时入队**；
//           ② `--scan` 回扫该频道最近 N 条（补历史/补掉线期间漏的）。
// 产物两份：`kook/queue/feedback.json`（机器账本：msg_id 去重 + 状态）·
//           `kook/queue/INBOX.md`（**AI 可读汇总**：按状态/标签分组，供下一个会话直接读着干活）。
const TAGS = [
  ["缺陷/报错", /(报错|错误|失效|不生效|没用|没反应|卡死|卡住|崩|闪退|掉线|断线|丢失|丢了|乱码|空|不对|异常|bug|BUG|error)/],
  ["功能请求", /(希望|想要|建议|能不能|能否|可以加|增加|新增|支持|加个|加一个|做成|也许可以)/],
  ["体验/界面", /(界面|ui|UI|字体|颜色|位置|大小|布局|遮挡|看不清|太小|太大|透明度|美化)/],
  ["平衡/数值", /(伤害|血量|数值|平衡|太强|太弱|削弱|加强)/],
  ["疑问/求助", /(怎么|如何|为什么|求助|请问|哪里|在哪)/],
];
function tagOf(text) {
  const hit = TAGS.filter(([, re]) => re.test(text)).map(([n]) => n);
  return hit.length ? hit : ["未分类"];
}
function queuePaths(cfg) {
  return { json: path.resolve(ROOT, cfg.guide.queue_file), md: path.resolve(ROOT, cfg.guide.inbox_file) };
}
function loadQueue(cfg) {
  const p = queuePaths(cfg).json;
  if (!fs.existsSync(p)) return { updated: 0, items: [] };
  try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return { updated: 0, items: [] }; }
}
function saveQueue(cfg, q) {
  const p = queuePaths(cfg).json;
  fs.mkdirSync(path.dirname(p), { recursive: true });
  q.updated = Date.now();
  fs.writeFileSync(p, JSON.stringify(q, null, 2), "utf8");
  renderInbox(cfg, q);
}
// ★本人（作者）判定：`cfg.guide.owner_ids` 里列出的人 = 用户自己（如 eval）—— 他的发言**不是需求**。
//   ★判不出（列表空 / 没有 id）⇒ 一律**按「不是本人」**处理（老行为一字不变，绝不因为配置缺失就把玩家需求吞掉）。
function isOwner(cfg, uid) {
  if (uid === undefined || uid === null || uid === "") return false;
  const ids = (cfg.guide && cfg.guide.owner_ids) || [];
  return ids.some(x => String(x) === String(uid));
}
// 入队（msg_id 去重；机器人自己的消息不入队）
function enqueue(cfg, q, rec) {
  if (!rec.msg_id || !rec.text) return false;
  if (q.items.some(x => x.msg_id === rec.msg_id)) return false;
  q.items.push(Object.assign({ status: "new", note: "", tags: tagOf(rec.text) }, rec));
  q.items.sort((a, b) => a.at - b.at);
  return true;
}
function renderInbox(cfg, q) {
  const byStatus = {};
  for (const it of q.items) (byStatus[it.status] = byStatus[it.status] || []).push(it);
  const tagCount = {};
  for (const it of q.items) for (const t of (it.tags || [])) tagCount[t] = (tagCount[t] || 0) + 1;
  const fmt = (ms) => new Date(ms).toLocaleString("zh-CN", { hour12: false });
  const lines = [];
  lines.push("# KOOK「建议反馈」→ 插件优化队列（AI 汇总收件箱）");
  lines.push("");
  lines.push(`> 本文件由 \`kook/kook_guide.js\` **自动生成**（实时入队 + \`--scan\` 回扫；机器账本 = \`feedback.json\`）。`);
  lines.push(`> 更新：${fmt(q.updated)} ｜ 合计 **${q.items.length}** 条 ｜ 状态：` +
    Object.entries(byStatus).map(([k, v]) => `${k} ${v.length}`).join(" · "));
  lines.push("");
  lines.push("## AI 处理指引（每次读这个文件时按此办）");
  lines.push("0. ★★**本人（作者）的发言不是需求**：`kook/config.json` 的 `guide.owner_ids` 里那些人（= eval / 作者本人）的消息**一律不入队**；他的发言若是对某条需求的**结论性答复**（「无法实现 / 不做 / 已做 / 重复」这类）⇒ 把**那条**判 `rejected` 并在 `note` 里写明原因（用户 2026-10-10 定：「我(eval)回复的并且是完整结论性答复的可以标记这个需求不需要加入队列,并且标记状态拒绝」）；`--scan` 会把本人发言单独列出来供核对。");
  lines.push("1. **先分析、后动手**：`new` 的条目按项目铁律做**可行性验证**（先核 API 存在性 → 写探针 → 判真伪/代价），结论写进该条 `feasibility`（`verdict`/`cost`/`basis`/`plan`），status 改 `triaged`；");
  lines.push("2. ★★**分析完停下来等用户确认** —— 【已分析 · 等你确认】那一组就是等点头的清单；**没确认不许进 `planned`、更不许改代码**（用户 2026-10-09 定：「在获取需求的时候先分析验证修复可能性.待我确认」）；");
  lines.push("3. 用户点头后才 `status=planned` 并实施；做完 `--done`（原帖 ✅ + 回复带版本发布链接）；");
  lines.push("4. **发版时对账**：`done` 的条目应在该版 `kook/notes/<版本>.md` 的概要里有对应一句（玩家能看见「我提的被做了」）。");
  lines.push("");
  lines.push("## 标签统计");
  lines.push(Object.keys(tagCount).length
    ? Object.entries(tagCount).sort((a, b) => b[1] - a[1]).map(([k, v]) => `- ${k}：${v}`).join("\n")
    : "- （暂无）");
  for (const st of ["new", "triaged", "planned", "done", "rejected"]) {
    const arr = byStatus[st] || [];
    if (!arr.length) continue;
    lines.push("");
    lines.push(`## ${st}（${arr.length}）`);
    for (const it of arr) {
      const txt = String(it.text).replace(/\s+/g, " ").slice(0, 300);
      lines.push(`- [${fmt(it.at)}] **${it.user || it.user_id}**（${(it.tags || []).join("/")}）${txt}` +
        (it.note ? `　→ **结论**：${it.note}` : "") + `　\`msg_id=${it.msg_id}\``);
    }
  }
  lines.push("");
  const p = queuePaths(cfg).md;
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, lines.join("\n"), "utf8");
}
// 回扫：拉该频道最近消息入队（message/list 非标准分页：不传 msg_id 即最新 N 条）
async function doScan(cfg, token) {
  const q = loadQueue(cfg);
  const before = q.items.length;
  const target = cfg.guide.feedback_channel_id;
  say(`回扫「建议反馈」频道 ${target}（最近 50 条）…`);
  const me = await api("GET", `${API}/user/me`, undefined, token);
  const d = await api("GET", `${API}/message/list?target_id=${target}&page_size=50`, undefined, token);
  let added = 0;
  const ownerSaid = [];
  for (const m of (d.items || [])) {
    if (m.type === 255) continue;                                    // 系统消息不入队
    if (m.author && m.author.id === me.id) continue;                 // 机器人自己的不入队
    const text = String(m.content || "").replace(/\s+/g, " ").trim();
    if (!text) continue;
    if (m.author && isOwner(cfg, m.author.id)) {                     // ★本人（作者）的发言不是需求
      ownerSaid.push({ user: (m.author.nickname || m.author.username || ""), text });
      continue;
    }
    if (enqueue(cfg, q, {
      msg_id: m.id, user_id: m.author ? m.author.id : "", user: m.author ? (m.author.nickname || m.author.username) : "",
      at: m.create_at, text, source: "scan",
    })) added++;
  }
  saveQueue(cfg, q);
  say(`✔ 队列：${before} → ${q.items.length} 条（新增 ${added}）`);
  // ★本人/作者发言**不入队**，但要让复核看得到（否则「他已经回过结论了」在 --plan 里完全不可见）
  if (ownerSaid.length) {
    say(`ℹ 本人/作者发言 ${ownerSaid.length} 条（**不入队**；若是对某条需求的结论性答复 ⇒ 把那条判 rejected 并写明原因）：`);
    for (const s of ownerSaid.slice(-5)) say(`  · ${s.user}：${s.text.slice(0, 110)}`);
  }
  say(`  ${path.relative(ROOT, queuePaths(cfg).json)} · ${path.relative(ROOT, queuePaths(cfg).md)}`);
}
function doQueue(cfg) {
  const q = loadQueue(cfg);
  renderInbox(cfg, q);
  const by = {};
  for (const it of q.items) by[it.status] = (by[it.status] || 0) + 1;
  say(`队列合计 ${q.items.length} 条：` + (Object.entries(by).map(([k, v]) => `${k} ${v}`).join(" · ") || "（空）"));
  say(`已刷新 ${path.relative(ROOT, queuePaths(cfg).md)}`);
}

// ───────── 「开发计划收集 + 完成回填」闭环（用户 2026-10-09 定：「收集kook 开发计划的触发点在每次
//   我问『kook 有什么优化需求吗?』类似问题的时候.就去收集开发计划。如果某一项计划已经完成的.可以将
//   反馈意见那个帖子标记成已完成.并且配备对应的插件优化版本发布链接」） ─────────
const RX_DONE = "[#9989;]";        // ✅ = U+2705 = 9989（实测可用：add-reaction / reaction-list / delete-reaction 全通）
function releasesPath(cfg) { return path.resolve(ROOT, cfg.guide.releases_file || "kook/state/releases.json"); }
function loadReleases(cfg) {
  const p = releasesPath(cfg);
  if (!fs.existsSync(p)) return {};
  try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return {}; }
}
// 某版本的发布链接：① 显式 --thread ② releases.json 里该版本的主插件帖 ③ 退回 GitHub/Gitee 发布页
function versionLink(cfg, ver, threadArg) {
  if (threadArg) return `https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}/${threadArg}`;
  const rel = loadReleases(cfg)[ver];
  if (rel && rel.threads && rel.threads.length) {
    const main = rel.threads.find(x => /主插件|EvalHelp/i.test(x.post)) || rel.threads[0];
    return `https://www.kookapp.cn/app/channels/${cfg.guild_id}/${cfg.channel_id}/${main.id}`;
  }
  const gh = (cfg.links && cfg.links.github || "").replace("{ver}", ver);
  const gt = (cfg.links && cfg.links.gitee || "").replace("{ver}", ver);
  return [gh, gt].filter(Boolean).join(" ｜ ") || "";
}

// ★触发点：用户问「kook 有什么优化需求吗?」这类问题时**先跑这个**（现读，不许凭印象答）
async function doPlan(cfg, token) {
  say("── 收集开发计划（现读：先回扫建议反馈频道，再列队列） ─────────");
  if (!args.noScan) { try { await doScan(cfg, token); } catch (e) { say("（回扫失败，改用本地队列：" + e.message + "）"); } }
  const q = loadQueue(cfg);
  const by = {}; for (const it of q.items) (by[it.status] = by[it.status] || []).push(it);
  const fmt = (ms) => new Date(ms).toLocaleString("zh-CN", { hour12: false });
  const show = (st, title) => {
    const arr = by[st] || [];
    if (!arr.length) return;
    say("");
    say(`【${title}】${arr.length} 条`);
    for (const it of arr) {
      say(`  · [${fmt(it.at)}] ${it.user || it.user_id}（${(it.tags || []).join("/")}）：${String(it.text).replace(/\s+/g, " ").slice(0, 110)}`);
      say(`      msg_id=${it.msg_id}`);
      if (it.feasibility) {
        const f = it.feasibility;
        say(`      ▸ 可行性：${f.verdict || "?"}${f.cost ? ` · 成本 ${f.cost}` : ""}${f.basis ? ` · 依据：${f.basis}` : ""}`);
        if (f.plan) say(`      ▸ 做法：${f.plan}`);
      }
      if (it.note) say(`      ▸ 备注：${it.note}`);
    }
  };
  show("new", "待分析（先做可行性验证，别急着重写代码）");
  show("triaged", "★已分析 · 等你确认（确认了才进 planned）");
  show("planned", "已确认 · 已排期（做完要回填）");
  show("done", "已完成");
  show("rejected", "已否决");
  const pending = q.items.filter(x => x.status === "done" && !x.notified);
  say("");
  say(`★待回填（已完成但还没在玩家原帖上标记 + 附版本链接）：${pending.length} 条` +
      (pending.length ? " ⇒ 跑 `--backfill --send`" : "（无）"));
  say("");
  say("处置四步（本清单就是回答「有什么优化需求」的依据）：");
  say("  1) `new`：按项目铁律做**可行性验证**（先核 API 存在性 → 写探针 → 判真伪/代价），结论写进该条 `feasibility`，然后 status=triaged；");
  say("  2) ★**停下来等用户确认** —— 【已分析 · 等你确认】那一组就是等点头的清单；**没确认不许进 planned、更不许动代码**；");
  say("  3) 用户点头后 status=planned；做完了：`--done <msg_id> --version <版本> --note \"一句话做了啥\" --send`；");
  say("  4) 批量补：`--backfill --send`；最后 `--queue` 刷新 INBOX.md。");
  say(`队列合计 ${q.items.length} 条 ⇒ ${path.relative(ROOT, queuePaths(cfg).md)}`);
}

// 标记完成：① 原帖加 ✅ 反应 ② 回复原帖（带版本发布链接）③ 队列状态 done + 记账（幂等）
async function markDone(cfg, token, msgId, ver, note, threadArg, me) {
  const q = loadQueue(cfg);
  const it = q.items.find(x => x.msg_id === msgId);
  // ★★★重复执行守卫（2026-10-09 演练发现）：反应是幂等的，**回复不是** —— 队列里已 notified=true
  //   说明这条已经回填过 ⇒ 默认**跳过**，除非显式 --force（否则重跑一次就在玩家帖下多一条重复回复）。
  if (it && it.notified && !args.force) {
    say(`= ${msgId} 已回填过（notified=true，note=${it.note || "-"}）⇒ 跳过。要强制再发一次加 --force`);
    return;
  }
  const link = versionLink(cfg, ver, threadArg);
  const reply = `✅ **这条已在 v${ver} 落地**\n${note ? note + "\n" : ""}${link ? `发布帖 / 下载：${link}` : ""}`;
  say(`—— 标记完成 ——`);
  say(`  建议 msg_id = ${msgId}${it ? "" : "（不在队列里：仍会标记，但不记队列）"}`);
  say(`  版本 = v${ver}　链接 = ${link || "（没找到！请用 --thread 或先发布该版本）"}`);
  say(`  原帖加反应 = ${RX_DONE}（✅）`);
  say(`  回复内容：\n${reply.split("\n").map(l => "    " + l).join("\n")}`);
  if (!args.send || args.dry) { say("  （dry-run：未发送）"); return; }

  // ① 反应（幂等：先查 reaction-list，机器人已加过就不再加）
  let already = false;
  try {
    const l = await api("GET", `${API}/message/reaction-list?msg_id=${msgId}&emoji=${encodeURIComponent(RX_DONE)}`, undefined, token);
    already = (l || []).some(u => String(u.id) === String(me.id));
  } catch (e) { say("  ⚠ 读反应列表失败（按未加处理）：" + e.message); }
  if (already) say("  = 反应已存在，跳过");
  else { await api("POST", `${API}/message/add-reaction`, { msg_id: msgId, emoji: RX_DONE }, token); say("  ✔ 已加 ✅"); }

  // ② 回复原帖（quote = 原消息；话题频道另说）
  const fbCh = cfg.guide.feedback_channel_id;
  await api("POST", `${API}/message/create`, { type: 9, target_id: fbCh, content: reply, quote: msgId }, token);
  say("  ✔ 已回复原帖（带版本发布链接）");

  // ③ 队列状态 + 记账
  if (it) {
    it.status = "done"; it.notified = true; it.note = `v${ver}${note ? " · " + note : ""}`; it.done_at = Date.now();
    if (link) it.link = link;
    saveQueue(cfg, q);
    say("  ✔ 队列已更新（status=done, notified=true）");
  }
}
async function doDone(cfg, token, msgId, ver, note, threadArg) {
  if (!msgId || !ver) { console.error("用法：--done <msg_id> --version <版本> [--note \"做了啥\"] [--thread <帖子id>] [--send]"); process.exit(2); }
  const me = await api("GET", `${API}/user/me`, undefined, token);
  await markDone(cfg, token, msgId, ver, note, threadArg, me);
}
async function doBackfill(cfg, token) {
  const q = loadQueue(cfg);
  const pend = q.items.filter(x => x.status === "done" && !x.notified);
  if (!pend.length) { say("没有待回填的条目。"); return; }
  const me = await api("GET", `${API}/user/me`, undefined, token);
  const defVer = (fs.readFileSync(path.join(ROOT, "EvalHelp.toc"), "utf8").match(/^##\s*Version:\s*(\S+)/m) || [])[1] || "";
  say(`待回填 ${pend.length} 条（默认版本 v${defVer}；每条也可在 feedback.json 里写 ver 字段指定）`);
  for (const it of pend) {
    const ver = it.ver || defVer;
    try { await markDone(cfg, token, it.msg_id, ver, it.note || "", null, me); }
    catch (e) { console.error(`  ✘ ${it.msg_id} 回填失败：${e.message}`); }
  }
}

// 模拟：机器人替「玩家」在建议反馈频道发一条需求并直接入队（绕过「排除机器人自己」的过滤）
// 用途 = 用户要求「先模拟流程」时端到端跑一遍（真实场景里这条消息由玩家发出、由 --listen/--scan 收进来）
async function doSimulate(cfg, token, text) {
  if (text && text.startsWith("@")) {                    // --simulate @文件（免去 PowerShell 引号地狱）
    const p = path.resolve(ROOT, text.slice(1));
    text = fs.readFileSync(p, "utf8").replace(/\r\n/g, "\n").trim();
  }
  if (!text) { console.error('用法：--simulate "建议文本"（或 @tmp/xxx.txt）--send'); process.exit(2); }
  const me = await api("GET", `${API}/user/me`, undefined, token);
  say(`模拟发布需求到建议反馈频道 ${cfg.guide.feedback_channel_id}：`);
  say("  " + text);
  if (!args.send || args.dry) { say("  （dry-run：未发送）"); return; }
  const d = await api("POST", `${API}/message/create`, { type: 9, target_id: cfg.guide.feedback_channel_id, content: text }, token);
  say(`  ✔ 已发布 msg_id=${d.msg_id}`);
  const q = loadQueue(cfg);
  const added = enqueue(cfg, q, { msg_id: d.msg_id, user_id: me.id, user: `${me.username}（模拟玩家）`,
                                  at: Date.now(), text, source: "sim" });
  saveQueue(cfg, q);
  say(`  ✔ 入队 ${added ? "成功" : "（已存在，跳过）"}：status=new，标签=${tagOf(text).join("/")}，队列共 ${q.items.length} 条`);
}

// 删消息（只能删机器人自己发的；用于清理演练/发错的痕迹）
async function doMsgDelete(cfg, token, ids) {
  if (!ids || !ids.length) { console.error("用法：--msg-delete <msg_id> [--msg-delete <msg_id> …] --send"); process.exit(2); }
  for (const id of ids) {
    say(`删除消息 ${id}`);
    if (!args.send || args.dry) { say("  （dry-run：未删除）"); continue; }
    try {
      await api("POST", `${API}/message/delete`, { msg_id: id }, token);
      say("  ✔ 已删除");
    } catch (e) { console.error("  ✘ 删除失败：" + e.message); }
  }
  // 队列里若引用了被删的消息，一并标注（不静默留一条指向已删消息的条目）
  const q = loadQueue(cfg);
  let touched = 0;
  for (const it of q.items) if (ids.includes(it.msg_id) && !/【已删除】/.test(it.note || "")) { it.note = (it.note ? it.note + " " : "") + "【已删除】消息已从频道删除"; touched++; }
  if (touched) { saveQueue(cfg, q); say(`（队列里 ${touched} 条已标注【已删除】）`); }
}

// ───────────────────────────── 只读自检 ─────────────────────────────
async function doCheck(cfg, token) {
  const me = await api("GET", `${API}/user/me`, undefined, token);
  say(`机器人：${me.username}#${me.identify_num}（id=${me.id}）intent=${me.intent}`);
  const g = await api("GET", `${API}/guild/view?guild_id=${cfg.guild_id}`, undefined, token);
  const byId = {}; for (const c of (g.channels || [])) byId[c.id] = c;
  say(`服务器：${g.name}`);
  const wc = byId[g.welcome_channel_id];
  const dc = byId[g.default_channel_id];
  say(`  KOOK 原生欢迎频道 = ${g.welcome_channel_id} ${wc ? "「" + wc.name + "」" : "（不存在/未设）"}`);
  say(`  默认落地频道     = ${g.default_channel_id} ${dc ? "「" + dc.name + "」" : ""}`);
  const gd = cfg.guide;
  const w = byId[gd.welcome_channel_id], an = byId[gd.announce_channel_id], fb = byId[gd.feedback_channel_id];
  say(`  guide.welcome_channel_id  = ${gd.welcome_channel_id} ${w ? "「" + w.name + "」type=" + w.type : "★找不到"}`);
  say(`  guide.announce_channel_id = ${gd.announce_channel_id} ${an ? "「" + an.name + "」type=" + an.type : "★找不到"}`);
  say(`  guide.feedback_channel_id = ${gd.feedback_channel_id} ${fb ? "「" + fb.name + "」type=" + fb.type + "（建议实时入队 + --scan 回扫）" : "★找不到"}`);
  say(`  guide.owner_ids = ${(gd.owner_ids || []).join(",") || "（空 ⇒ 没有「本人」过滤）"}（本人/作者发言 ⇒ **不入队**）`);
  // ★频道说明（「怎么提建议」）：现读现比 —— 与模板不一致就点名提醒（修好只要一条 `--topic --send`）
  if (fb) {
    let want = ""; try { want = feedbackTopicBody(cfg); } catch { want = ""; }
    const cur = String(fb.topic || "").replace(/\r\n/g, "\n").trim();
    say(`    频道说明：${cur ? `「${cur.split("\n")[0].slice(0, 40)}…」${cur.length} 字` : "（空）"}` +
        (want ? (cur === want ? " · 与 kook/guide/feedback.md 一致 ✅"
                              : (cur ? " · ★与模板不一致 ⇒ 跑 `--topic --send` 更新"
                                     : " · 还没写 ⇒ 跑 `--topic --send` 写入使用说明")) : ""));
  }
  const q = loadQueue(cfg);
  const qby = {}; for (const it of q.items) qby[it.status] = (qby[it.status] || 0) + 1;
  say(`  优化队列：${q.items.length} 条（` + (Object.entries(qby).map(([k, v]) => `${k} ${v}`).join(" · ") || "空") +
      `）⇒ ${path.relative(ROOT, queuePaths(cfg).md)}`);
  if (w && w.type !== 1) say("  ⚠ 欢迎频道不是文字频道（type≠1）—— 欢迎词发不进去");
  if (an && an.type !== 1) say("  ⚠ 公告频道不是文字频道（type≠1）—— 公告发不进去");
  const st = loadState(cfg);
  say(`账本：${path.relative(ROOT, statePath(cfg))}`);
  say(`  公告 msg_id = ${st.announce_msg_id || "（还没有 ⇒ 会新建）"}`);
  say(`  已欢迎成员 = ${Object.keys(st.welcomed || {}).length} 人 · max_sn = ${st.max_sn || 0} · session = ${st.session_id ? "有" : "无"}`);
  const m = await api("GET", `${API}/message/view?msg_id=${st.announce_msg_id || "0"}`, undefined, token).catch(() => null);
  if (st.announce_msg_id && m) say(`  公告仍在（最后更新 ${new Date(m.updated_at || m.create_at).toLocaleString("zh-CN", { hour12: false })}）`);
  else if (st.announce_msg_id) say("  ⚠ 账本里的公告 msg_id 已取不到（被删了？）⇒ 下次发布会新建一条");
  // ★本版更新公告（每版一条；与常青公告分开记账）
  const curVer = tocVersion();
  const ua = (st.update_announce || {})[curVer];
  say(`  更新公告（v${curVer}）= ${ua || `（还没有 ⇒ 发完 KOOK 发布帖后跑 \`--update-announce --send\`）`}` +
      `　· 已发版本：${Object.keys(st.update_announce || {}).join(", ") || "无"}`);
  if (ua) {
    const um = await api("GET", `${API}/message/view?msg_id=${ua}`, undefined, token).catch(() => null);
    if (um) say(`    仍在（最后更新 ${new Date(um.updated_at || um.create_at).toLocaleString("zh-CN", { hour12: false })}）`);
    else say("    ⚠ 账本里的更新公告 msg_id 已取不到（被删了？）⇒ 重跑 --update-announce --send 会新建一条");
  }
  say("提示：欢迎大厅里那条「系统通知#0001 …」是 KOOK 原生欢迎频道发的，与机器人无关；文案可在客户端「服务器设置 → 概览/欢迎」里改。");
}

// ───────────────────────────── main ─────────────────────────────
(async () => {
  try {
    const cfg = loadConfig();
    const tk = readToken(cfg);
    if (args.check || args.announce || args.listen || args.welcome || args.scan
        || args.plan || args.done || args.backfill || args.simulate || args.msgDelete || args.topic
        || args.updateAnnounce) {
      if (!tk) { console.error("✘ 找不到 KOOK token（token/kook.txt 或 KOOK_TOKEN）"); process.exit(2); }
      if (!args.listen) say(`token 来源：${tk.from}（值不打印）`);
    }
    if (args.check)    return doCheck(cfg, tk.token);
    if (args.topic)    return doTopic(cfg, tk.token, args.channel);
    if (args.updateAnnounce) return doUpdateAnnounce(cfg, tk.token, args.version);
    if (args.msgDelete) return doMsgDelete(cfg, tk.token, args.msgDelete);
    if (args.simulate) return doSimulate(cfg, tk.token, args.simulate);
    if (args.plan)     return doPlan(cfg, tk.token);
    if (args.done)     return doDone(cfg, tk.token, args.done, args.version, args.note, args.thread);
    if (args.backfill) return doBackfill(cfg, tk.token);
    if (args.scan)     return doScan(cfg, tk.token);
    if (args.queue)    return doQueue(cfg);
    if (args.welcome)  return doWelcome(cfg, tk.token, args.welcome, loadState(cfg));
    if (args.announce) return doAnnounce(cfg, tk.token);
    if (args.listen)   return doListen(cfg, tk.token);
    console.error("用法：--check | --plan | --scan | --queue | --done <msg_id> --version <版本> [--note …] [--thread …] | --backfill | --announce [--send] | --update-announce [--version <版本>] [--send] | --topic [--channel <id>] [--send] [--force] | --welcome <user_id> [--send] | --listen [--dry]");
    process.exit(2);
  } catch (e) {
    console.error("✘ " + e.message);
    process.exit(e.kookCode ? 3 : 2);
  }
})();
