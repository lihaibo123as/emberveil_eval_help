// dsh_memory_budget.js —— DSH「常驻指令（CLAUDE.md）字节预算」的持久修法 + 闸门
//   node dsh_memory_budget.js status   # 列出候选安装 / 现在生效的 agent-instructions maxBytes
//   node dsh_memory_budget.js check    # 闸门：按真实 profile 补丁在临时 DSH_HOME 里跑官方 --dump-config 自证
//   node dsh_memory_budget.js apply    # 从安装内 shipped preset 机械重生成覆盖块并写入 profile 补丁（先备份）
//
// ★为什么不能在安装内改：preset 是 bundle（dsh-web-app\presets\<id>.patch.yml）里的声明行，升级即回 65536。
// ★为什么要用 profile 补丁层：官方 skills/editing-cordis-compositions 明确——
//   「按 Loader 行 id 覆盖（- id: preset-<id>）」，且**覆盖会替换整个 config**，必须完整重述
//   id / order / plugins；profile 补丁是最后一层用户层，升级 dsh 不会丢。
// ★为什么单层 `- id: agent-instructions` 没用：宿主行被 dsh-web-app 的 bundle 补丁 `disabled: true` 关掉了，
//   在它上面写 config 是「改了等于没改」（2026-09-25 实测，dump-config 里该行仍是 disabled: true）。
// ★闸门原理：把真实 profile 补丁复制进工作区内的临时 $DSH_HOME，跑 `dsh --profile web --dump-config`
//   （纯读、不起服务、不碰真实 profile），断言每个 preset 声明里的 agent-instructions maxBytes。
//   dump 里残留的 65536 只允许出现在 disabled 行里（那是被关掉的宿主行默认值）。
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const BUDGET = 1048576;                                   // 1 MiB（旧上限 65536，从 dsh 0.1.2-rc.1 起）
const HOME = process.env.USERPROFILE || process.env.HOME;
const DSH_HOME = path.join(HOME, '.dsh');
const PROFILE_PATCH = path.join(DSH_HOME, 'profiles', 'web', 'cordis.patch.yml');
const GATE_HOME = path.join(__dirname, 'tmp', 'dsh_gate_home');
const PROFILE_FILES = ['package.json', 'cordis.yml', 'cordis.patch.yml', 'pnpm-workspace.yaml', 'pnpm-lock.yaml'];
const MARK_BEGIN = '# >>> DSH 常驻指令预算覆盖（dsh_memory_budget.js 生成，勿手改）>>>';
const MARK_END = '# <<< DSH 常驻指令预算覆盖 <<<';

const bad = [];
const warn = (m) => bad.push(m);
const log = (...a) => console.log(...a);

// ── ① 找「可能正在跑的那份安装」：全局优先，其次 _npx 缓存里最新的 ─────────────
function candidates() {
  const list = [];
  const add = (root, why) => {
    if (!root) return;
    const bin = path.join(root, 'lib', 'bin.js');
    const presets = path.join(root, 'node_modules', '@deepseek-ai', 'dsh-web-app', 'presets');
    let version = '?';
    try { version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version; } catch { }
    list.push({ root, bin, presets, version, ok: fs.existsSync(bin) && fs.existsSync(presets), why });
  };
  add(path.join(process.env.APPDATA || '', 'npm', 'node_modules', '@deepseek-ai', 'dsh'), '全局 npm');
  const npx = path.join(process.env.LOCALAPPDATA || '', 'npm-cache', '_npx');
  try {
    for (const d of fs.readdirSync(npx)) {
      const p = path.join(npx, d);
      add(path.join(p, 'node_modules', '@deepseek-ai', 'dsh'), 'npx ' + d);
      add(path.join(p, 'node_modules', '@deepseek-ai', 'dsh', 'node_modules', '@deepseek-ai'), 'npx ' + d + '（旧布局，非安装根）');
    }
  } catch { }
  return list.filter((c) => c.ok);
}

function pickInstall(prefer) {
  const all = candidates();
  if (prefer) {
    const hit = all.find((c) => c.root === prefer);
    if (hit) return hit;
  }
  const g = all.find((c) => c.why === '全局 npm');
  return g || all[0];
}

// ── ② 从 shipped preset 生成覆盖条目（只动 maxBytes，其余逐字照抄）───────────
function buildOverride(install) {
  const files = fs.readdirSync(install.presets).filter((f) => f.endsWith('.patch.yml'));
  const parts = [MARK_BEGIN];
  const presets = [];
  for (const f of files.sort()) {
    const text = fs.readFileSync(path.join(install.presets, f), 'utf8');
    if (!text.includes('agent-instructions')) continue;             // minimal 之类没有常驻指令行，跳过
    const idm = text.match(/^-\s*insert:\s*\n\s*-\s*id:\s*preset-([a-z0-9-]+)/m);
    if (!idm) { warn(f + ': 未找到 `- insert:` + `- id: preset-<id>` 结构'); continue; }
    const id = idm[1];
    const hits = (text.match(/(maxBytes:\s*)(\d+)/g) || []);
    if (hits.length !== 1) { warn(`${f}: 期望恰好 1 处 maxBytes，实际 ${hits.length}`); continue; }
    const patched = text.replace(/(\d+)(\s*)$/m, '$1');             // no-op，保持可读
    const flipped = text.replace(/(maxBytes:\s*)\d+/, '$1' + BUDGET);
    const lines = flipped.split('\n');
    const at = lines.findIndex((l) => /^- insert:/.test(l));
    if (at < 0) { warn(f + ': 未找到顶层 `- insert:`'); continue; }
    const body = lines.slice(at + 1)
      .map((l) => (l.startsWith('    ') ? l.slice(4) : l.trim() === '' ? '' : l));
    while (body.length && body[body.length - 1].trim() === '') body.pop();
    if (!new RegExp('^-\\s*id:\\s*preset-' + id + '\\s*$').test(body[0])) { warn(f + ': 覆盖条目首行异常'); continue; }
    presets.push({ id, file: f, rows: body.length, ids: (body.join('\n').match(/^\s*- id:\s*([\w.-]+)/gm) || []).map((s) => s.replace(/^\s*- id:\s*/, '')) });
    parts.push(...body, '');
  }
  parts.push(MARK_END);
  return { text: parts.join('\n'), presets };
}

// 文件头（由脚本统一维护，apply 时会重写顶部注释段）
const HEADER = [
  '# 本机 dsh web profile 的**用户补丁层**（覆盖顺序：bundle → 本文件 → home patch → --patch）',
  '#',
  '# ★★★「常驻指令（CLAUDE.md）字节预算」的唯一有效修法 = 文件末尾那个覆盖块，别在别处改：',
  '#   · 只写单层 `- id: agent-instructions` 是**无效**的：宿主那行被 @deepseek-ai/dsh-web-app 的',
  '#     bundle 补丁 `disabled: true` 关掉了，在它上面写 config 等于没写（2026-09-25 dump-config 实测）。',
  '#   · 真正生效的是 preset 声明行 preset-standard/ptc/cordis 的 config.plugins 里的',
  '#     agent-instructions.config.maxBytes。官方（dsh-agent-preset 的 skills/editing-cordis-compositions）',
  '#     要求「按 Loader 行 id 覆盖」，且**覆盖会替换整个 config** ⇒ 必须完整重述 id/order/plugins；',
  '#     少写字段 = preset 激活失败（2026-09-25 早上 GUI 崩过一次，就是这个原因）。',
  '#   · 末尾覆盖块由仓库根目录 dsh_memory_budget.js 生成，**不要手改**；dsh 升级/换 npx hash 后：',
  '#       node dsh_memory_budget.js apply   # 按当前安装内 shipped preset 重新生成（先备份）',
  '#       node dsh_memory_budget.js check   # 闸门：临时 DSH_HOME + 官方 --dump-config 自证',
  '#   · 生效时机：patchReload = startup ⇒ 改完**必须重启 GUI**，且只对**新开的会话**生效。',
].join('\n');

// 把覆盖块写进（或替换进）profile 补丁；顺带清掉那条「无效的单层 agent-instructions」
// ★剥离用「任何生成过的块」的通用正则，不认死某一版标记文字——否则换过标记文字后会**重复追加**（已踩过）
const BLOCK_RE = /^# >>>[^\n]*常驻指令预算覆盖[\s\S]*?^# <<<[^\n]*\n?/gm;
function composePatch(current, override) {
  const blocks = (current.match(BLOCK_RE) || []).length;
  const withoutBlocks = current.replace(BLOCK_RE, '');
  const lines = withoutBlocks.split('\n');
  // 顶部注释段由本脚本重写（HEADER 是唯一说明来源）
  let start = 0;
  while (start < lines.length && (lines[start].trim() === '' || lines[start].startsWith('#'))) start++;
  const kept = [];
  const dropped = [];
  for (let i = start; i < lines.length; i++) {
    const l = lines[i];
    if (/^-\s*id:\s*agent-instructions\s*$/.test(l)) {           // 宿主行是 disabled，写它没用
      dropped.push(l.trim());
      i++;
      while (i < lines.length && !/^-\s/.test(lines[i])) { dropped.push(lines[i].trim()); i++; }
      i--;
      continue;
    }
    kept.push(l);
  }
  const entries = kept.join('\n').replace(/^\s*\n+/, '').replace(/\s*$/, '');
  const text = HEADER + '\n' + entries + '\n\n' + override.text + '\n';
  const after = (text.match(BLOCK_RE) || []).length;
  if (after !== 1) warn(`覆盖块数量异常：写入前 ${blocks} 个、写入后 ${after} 个（应为 1）`);
  return { text, dropped, blocksBefore: blocks };
}

// ── ③ 闸门：临时 DSH_HOME 里跑官方 --dump-config ──────────────────────────────
function gate(patchText) {
  fs.mkdirSync(path.join(GATE_HOME, 'profiles', 'web'), { recursive: true });
  for (const f of PROFILE_FILES) {
    const src = path.join(DSH_HOME, 'profiles', 'web', f);
    const dst = path.join(GATE_HOME, 'profiles', 'web', f);
    if (f === 'cordis.patch.yml') continue;
    try { fs.copyFileSync(src, dst); } catch { }
  }
  fs.writeFileSync(path.join(GATE_HOME, 'profiles', 'web', 'cordis.patch.yml'), patchText, 'utf8');

  const install = pickInstall();
  const dumpFile = path.join(__dirname, 'tmp', 'dsh_dump_config.txt');
  const fd = fs.openSync(dumpFile, 'w');
  const res = spawnSync(process.execPath, [install.bin, '--profile', 'web', '--dump-config'], {
    env: { ...process.env, DSH_HOME: GATE_HOME },
    stdio: ['ignore', fd, fd],
    timeout: 120000,
  });
  fs.closeSync(fd);
  const dump = fs.readFileSync(dumpFile, 'utf8');
  fs.unlinkSync(dumpFile);
  if (res.status !== 0) { warn('dump-config 退出码 ' + res.status + '（补丁可能无法解析）'); }
  if (/skipping profile bundle/.test(dump)) log('  （临时 HOME 缺 dsh-builtin-browser，已有警告但属正常）');

  const lines = dump.split('\n');
  const tops = [];
  lines.forEach((l, i) => { if (/^- id: /.test(l)) tops.push({ i, id: l.replace(/^- id:\s*/, '').trim() }); });
  // 从「某个顶层行自己」到下一个顶层行：preset 块的正确范围（★不能从上一行起，否则会串到上一个 preset）
  const rowBlock = (idx) => {
    const next = tops.find((t) => t.i > idx);
    return lines.slice(idx, next ? next.i : lines.length).join('\n');
  };
  // 包含第 i 行的顶层块：用于判断某个 maxBytes 行属不属于 disabled 行
  const containingBlock = (i) => {
    let s = 0; let e = lines.length;
    for (const t of tops) { if (t.i <= i) s = t.i; else { e = t.i; break; } }
    return lines.slice(s, e).join('\n');
  };

  const found = [];
  for (const t of tops) {
    if (!/^preset-/.test(t.id)) continue;
    const block = rowBlock(t.i);
    const m = block.match(/- id: agent-instructions[\s\S]{0,300}?maxBytes:\s*(\d+)/);
    const val = m ? Number(m[1]) : null;
    found.push({ preset: t.id, maxBytes: val });
    log(`  ${t.id}: agent-instructions maxBytes = ${val === null ? '(未配置，该 preset 无常驻指令行)' : val}${val === BUDGET ? ' ✓' : val === null ? '' : ' ✗'}`);
    if (val === null && /agent-instructions/.test(block)) warn(`${t.id} 有 agent-instructions 行但读不到 maxBytes`);
    if (val !== null && val !== BUDGET) warn(`${t.id} 的 agent-instructions maxBytes = ${val}，期望 ${BUDGET}`);
  }
  if (!found.length) warn('dump 里一个 preset 声明行都没有（结构变了？）');
  const withInstructions = found.filter((f) => f.maxBytes !== null);
  if (!withInstructions.length) warn('没有任何 preset 配了 agent-instructions —— 预算无处生效');

  let stray = 0;
  lines.forEach((l, i) => {
    const m = l.match(/maxBytes:\s*(\d+)/);
    if (!m || Number(m[1]) === BUDGET) return;
    const block = containingBlock(i);
    if (!/disabled:\s*true/.test(block)) { stray++; warn(`行 ${i + 1} 有一个未被禁用的 maxBytes: ${m[1]}（${l.trim()}）`); }
  });
  log(`  残留非 ${BUDGET} 且未禁用的 maxBytes 行数 = ${stray}`);
  return found;
}

// 漂移检测：profile 补丁里重述的行 id 与 shipped 是否一致（上游改 preset 会被我们的覆盖遮住）
function drift(patchText, install) {
  const override = buildOverride(install);
  const seq = (t, id) => {
    const re = new RegExp('^-\\s*id:\\s*preset-' + id + '\\s*$', 'm');
    const m = re.exec(t);
    if (!m) return null;
    const rest = t.slice(m.index);
    const next = /^- id: preset-/m.exec(rest.slice(1));
    const seg = next ? rest.slice(0, next.index + 1) : rest;
    return (seg.match(/^\s*- id:\s*([\w.-]+)/gm) || []).map((s) => s.replace(/^\s*- id:\s*/, '')).join(',');
  };
  for (const p of override.presets) {
    const a = seq(patchText, p.id);
    const b = seq(override.text, p.id);
    if (a === null || b === null) { warn(`preset-${p.id}: 定位失败（补丁侧=${a === null ? '缺' : 'ok'}，shipped 侧=${b === null ? '缺' : 'ok'}）`); continue; }
    if (a !== b) warn(`preset-${p.id}: 覆盖块与当前安装内 shipped 声明不一致（上游改过 preset，需要重新 apply 以同步新增/移除的行）`);
  }
}

// ── 主流程 ──────────────────────────────────────────────────────────────────
const mode = (process.argv[2] || 'check').toLowerCase();
const install = pickInstall();
log('候选安装:');
for (const c of candidates()) log(`  - ${c.version.padEnd(12)} ${c.why}  ${c.root}${c === install ? '   <= 采用' : ''}`);
log(`采用安装: ${install.version}  ${install.root}`);
log(`profile 补丁: ${PROFILE_PATCH}`);
log('');

if (!fs.existsSync(PROFILE_PATCH)) { warn('profile 补丁不存在：' + PROFILE_PATCH); }
const current = fs.existsSync(PROFILE_PATCH) ? fs.readFileSync(PROFILE_PATCH, 'utf8') : '';

if (mode === 'apply') {
  const override = buildOverride(install);
  log(`生成覆盖条目: ${override.presets.map((p) => `preset-${p.id}(${p.rows} 行)`).join(' / ')}`);
  const next = composePatch(current, override);
  if (next.dropped.length) log(`移除无效单层条目 ${next.dropped.length} 行: ${next.dropped[0]}`);
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = path.join(__dirname, 'tmp', 'dsh_profile_patch_backup_' + ts + '.yml');
  fs.mkdirSync(path.dirname(backup), { recursive: true });
  if (current) fs.writeFileSync(backup, current, 'utf8');
  fs.writeFileSync(PROFILE_PATCH, next.text, 'utf8');
  log(`已写入（备份 ${path.relative(__dirname, backup)}，${Buffer.byteLength(next.text)} 字节）`);
  log('');
}

if (mode === 'apply' || mode === 'check') {
  const patchText = fs.readFileSync(PROFILE_PATCH, 'utf8');
  log('闸门（临时 DSH_HOME + 官方 --dump-config）:');
  gate(patchText);
  log('');
  log('漂移检测:');
  drift(patchText, install);
  log('');
  log(bad.length ? '结果: FAIL' : '结果: PASS');
  for (const b of bad) log('  ! ' + b);
  process.exit(bad.length ? 1 : 0);
}
