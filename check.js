// ===== check.js —— 一条命令跑完所有闸门（★把「全套任务」合并成一次调用）=====
// 用法：
//   node check.js                日常：luacheck + test_engine（**两组并行**，全套断言）
//   node check.js --quick        省时：luacheck + test_engine --quick（跳过 22s 的任务线弹窗组，约 6~8s）
//   node check.js --full         发版前：再加 quest/audit.js（数据闸门：装备/任务线链接一致性）
//   node check.js --selftest     自检：用一条必然失败的命令验「失败会被如实报出来」
// 退出码：任一闸门失败 = 1（可直接用在脚本/发布流程里）。
//
// ★为什么合并成一个脚本：以前「跑全套」要在脑子里记住三条命令、挨个敲、还要自己拼输出；
//   现在一次调用并行跑完，末尾给一张表（每条闸门 / 退出码 / 耗时 / 结论）。
// ★为什么并行：三条闸门互不依赖（各自读源码/数据，互不写文件），并行后墙钟 ≈ 最慢那条。
// ★变异跑手（mutate.js）**不在这里**：它是「验证判据能不能抓到 bug」的一次性工具，
//   加新判据时只跑那一条（node mutate.js M80），全量 26 条只在发版前 / 大改后跑。
const cp = require('child_process');

const argv = process.argv.slice(2);
const quick = argv.includes('--quick');
const full = argv.includes('--full');
const selfTest = argv.includes('--selftest');

// 闸门清单：[显示名, 命令, 参数, 判据说明]
const GATES = [
  ['luacheck', 'node', ['luacheck.js'],
    'fengari 真实解析每个 .lua（语法错 = 整插件载不进去，且 UE 日志看不到）'],
  ['test_engine', 'node', quick ? ['test_engine.js', '--quick'] : ['test_engine.js'],
    quick ? '断言全套（省时模式：跳过 22s 的任务线弹窗组）' : '断言全套 + 18 道源码检查'],
];
if (full) GATES.push(['quest/audit', 'node', ['quest/audit.js'],
  '任务线/装备数据闸门（链接与列表↔详情一致性）']);
if (selfTest) {
  GATES.length = 0;
  GATES.push(['故意失败的自检', 'node', ['-e', 'console.log("SELFTEST 失败样例"); process.exit(3)'], '自检：必须报 FAIL 且退出码非 0']);
  GATES.push(['正常样例', 'node', ['-e', 'console.log("SELFTEST 正常样例")'], '自检：必须报 PASS']);
}

function run(g) {
  return new Promise((res) => {
    const t0 = Date.now();
    cp.execFile(g[1], g[2], { cwd: __dirname, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof err.code === 'number' ? err.code : 99) : 0;
      res({ name: g[0], code, ms: Date.now() - t0, txt: String(stdout || '') + String(stderr || ''), why: g[3] });
    });
  });
}

// 判定：退出码非 0，或输出里出现失败标记（★只看「ALL TESTS PASS」会漏报：源码检查失败走 exitCode=1 而脚本照跑到底）
const FAIL_RE = /: FAIL|ASSERT FAIL|LOAD ERROR|RUNTIME ERROR|RUN FAIL/;
function verdict(r) {
  if (r.code !== 0) return 'FAIL';
  if (FAIL_RE.test(r.txt)) return 'FAIL';
  return 'PASS';
}

async function main() {
const t0 = Date.now();
const results = await Promise.all(GATES.map(run));
const total = ((Date.now() - t0) / 1000).toFixed(1);
let bad = 0;
// 表格对齐：中文按 2 列宽算（padEnd 数的是码元，中文标签会把表格顶歪）
function dispWidth(s) { let n = 0; for (const ch of String(s)) n += (ch.charCodeAt(0) > 0x2e80) ? 2 : 1; return n; }
function pad(s, n) { const w = dispWidth(s); return s + ' '.repeat(Math.max(1, n - w)); }
console.log('');
console.log(pad('闸门', 18) + pad('结论', 9) + pad('耗时', 10) + '说明');
console.log('---------------------------------------------------------------');
for (const r of results) {
  const v = verdict(r);
  if (v === 'FAIL') bad++;
  console.log(pad(r.name, 18) + pad(v, 9) + pad((r.ms / 1000).toFixed(1) + 's', 10) + r.why);
}
console.log('---------------------------------------------------------------');
// 失败时把失败行摊开（每个闸门最多 6 行），成功时只给一行小结
for (const r of results) {
  if (verdict(r) !== 'FAIL') continue;
  console.log('\n★ ' + r.name + ' 失败明细（exit=' + r.code + '）：');
  const lines = r.txt.split(/\r?\n/).filter(l => FAIL_RE.test(l)).slice(0, 6);
  if (!lines.length) console.log('  ' + r.txt.trim().split(/\r?\n/).slice(-6).join('\n  '));
  for (const l of lines) console.log('  ' + l.trim().slice(0, 180));
}
console.log('\n' + (bad ? ('✗ ' + bad + ' 条闸门失败') : '✓ 全部闸门通过') + '（' + total + 's'
  + (quick ? ' · 省时模式：任务线弹窗组已跳过 —— 改动任务线/弹窗/数据层时跑 node check.js' : '')
  + (full ? ' · 含数据审计' : ' · 数据审计未跑（发版前加 --full）') + '）');
if (selfTest) console.log('自检期望：故意失败那条必须 FAIL、正常样例必须 PASS。');
process.exit(bad ? 1 : 0);
}
main();
