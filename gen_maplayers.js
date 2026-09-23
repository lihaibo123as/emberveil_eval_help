// 解析 EH_MapScale 存档里的全层清单 → 生成自查文档（doc/自查/地图层清单.md）
// ★铁律：node 脚本写文件再跑，不内联 -e
// ★解析方式：存档是**我们自己写出的规整格式**（每个 layer 是扁平块，无嵌套表）
//   → 用正则抓块 + 抓字段，比 fengari 的嵌套 lua_next 稳（实测 nested next 会 PANIC）。
const fs = require('fs');
const path = require('path');

const SRC = path.join(process.env.LOCALAPPDATA, 'Azeroth', 'Saved', 'Account', 'LIHAIBOAS1', 'SavedVariables', 'EH_MapScale.lua');
if (!fs.existsSync(SRC)) { console.log('MISSING: ' + SRC); process.exit(1); }
const raw = fs.readFileSync(SRC, 'utf8').replace(/^\uFEFF/, '');

function field(block, key) {
  const m = block.match(new RegExp('\\["' + key + '\\"\\]\\s*=\\s*("?)([^",\\n]*)\\1'));
  return m ? m[2] : undefined;
}

const layers = [];
const top = [];
const blockRe = /\{[^{}]*\}/g;
let bm;
while ((bm = blockRe.exec(raw)) !== null) {
  const b = bm[0];
  if (!/\["path"\]/.test(b)) continue;
  const l = {
    i: Number(field(b, 'i')),
    path: field(b, 'path'),
    type: field(b, 'type'),
    w: field(b, 'w'),
    h: field(b, 'h'),
    level: field(b, 'level'),
    strata: field(b, 'strata'),
    parent: field(b, 'parent'),
    scale: field(b, 'scale'),
    scaleable: /\["scaleable"\]\s*=\s*true/.test(b),
  };
  // 顶层段：采集时 i 固定写 0（树内层 i ≥ 1）
  if (l.i === 0) top.push(l); else layers.push(l);
}
const atM = raw.match(/\["at"\]\s*=\s*"([^"]*)"/);
const cfg = { at: atM ? atM[1] : '?', layers };
console.log('layers=' + layers.length + ' at=' + cfg.at);
console.log('layers=' + layers.length + ' at=' + cfg.at);

// ---- 语义分组（按名字/路径模式） ----
function groupOf(l) {
  const p = l.path || '';
  const leaf = p.split('/').pop().replace(/^region:/, '');
  if (/^WorldMap/i.test(leaf)) return 'WorldMap* 原生地图件';
  if (/^Blackout|WorldMapBlackout/i.test(leaf)) return '黑幕层';
  if (/^UnrealQuest/i.test(leaf)) return 'UnrealQuest 标记';
  if (/^EVAL_/i.test(leaf)) return 'EvalHelp 自家';
  if (/^GeneratedLuaUIObject/i.test(leaf)) return '引擎生成对象(GeneratedLuaUIObject)';
  if (/^region:/.test(p.split('/').pop())) return '纯图层(region)';
  if (/^MiniMap|^Minimap/i.test(leaf)) return '小地图件';
  if (/^(GameTooltip|WorldMapTooltip)/i.test(leaf)) return '提示框';
  return '其他';
}

const groups = {};
for (const l of layers) {
  const g = groupOf(l);
  (groups[g] = groups[g] || []).push(l);
}

const scalable = layers.filter(l => l.scaleable === true);
const notScalable = layers.filter(l => l.scaleable !== true);

// ---- 用途语义预估 ----
const PURPOSE = [
  ['WorldMapFrame', '世界地图主窗（全屏面板；移动/透明度的主体）'],
  ['WorldMapButton', '地图画布本体（引擎绘制的区域贴图挂在这；pin 也画在它上面）'],
  ['WorldMapDetailFrame', '画布容器（区域贴图/探索图层在它内部）'],
  ['WorldMapPositioningGuide', '定位导引（玩家/鼠标定位辅助层，UnrealQuest 也挂东西）'],
  ['WorldMapFrameAreaFrame', '区域标签容器（悬停区域名的宿主）'],
  ['WorldMapFrameAreaLabel', '悬停区域名文本（判漂移的关键读数口）'],
  ['WorldMapFrameAreaDescription', '区域描述文本'],
  ['WorldMapParty', '队伍成员在地图上的点（1~4）'],
  ['WorldMapRaid', '团队成员在地图上的点（1~40）'],
  ['BlackoutWorld', '开图时的世界黑幕（probe4/5 藏过，不是真凶）'],
  ['WorldMapBlackout', '★真正的黑幕层（probe8 定案；父级 WorldFrame）'],
  ['WorldMapTooltip', '地图专用 tooltip（pin 悬停用）'],
  ['GeneratedLuaUIObject', '引擎为该客户端生成的对象（地图 tile/探索覆盖层的候选）'],
  ['region:Texture', '纯纹理图层（不可 SetScale，只能改尺寸/坐标）'],
];

function esc(s) { return String(s == null ? '' : s).replace(/\|/g, '\\|'); }

const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
let md = '';
md += '# 地图层清单（自查文档）\n\n';
md += '> 数据来源：游戏内 `/ems list` 落到存档 `SavedVariables\\EH_MapScale.lua` 的 `EH_MAPSCALE_CFG.layers`。\n';
md += '> 由 `gen_maplayers.js` 生成（可重跑：游戏内 `/ems list` → `/reload` → `node gen_maplayers.js`）。\n\n';
md += '- 采集时间戳（游戏内 GetTime）：' + cfg.at + '\n';
md += '- 生成时间：' + now + '\n';
md += '- 扫描根：`WorldMapFrame`（递归子帧 + 图层，深度 ≤4）\n';
md += '- **总层数：' + layers.length + '**；可 SetScale：**' + scalable.length + '**；不可缩（图层/纹理/文本）：**' + notScalable.length + '**\n\n';

md += '## 一、语义分组统计\n\n| 分组 | 层数 | 可缩 |\n| :-- | --: | --: |\n';
for (const g of Object.keys(groups).sort((a, b) => groups[b].length - groups[a].length)) {
  const arr = groups[g];
  md += '| ' + esc(g) + ' | ' + arr.length + ' | ' + arr.filter(l => l.scaleable === true).length + ' |\n';
}

md += '\n## 二、用途语义预估（按名字）\n\n| 名字模式 | 预估用途 |\n| :-- | :-- |\n';
for (const [n, p] of PURPOSE) md += '| `' + n + '` | ' + p + ' |\n';

md += '\n## 三、可缩放的层（' + scalable.length + ' 个，按路径排序）\n\n';
md += '> 说明：UnrealQuest 的世界地图图钉（`UnrealQuestWorldMapPin*` / 描边层）数量大且与本插件无关，单独折叠在第五节。\n\n';
md += '| # | 路径 | 类型 | 尺寸 | 层级 | strata | 父级 |\n| --: | :-- | :-- | :-- | --: | :-- | :-- |\n';
const isUQPin = (p) => /UnrealQuest/i.test(String(p));
const sortedScalable = scalable.filter(l => !isUQPin(l.path)).sort((a, b) => String(a.path).localeCompare(String(b.path)));
for (const l of sortedScalable) {
  md += '| ' + l.i + ' | `' + esc(l.path) + '` | ' + esc(l.type) + ' | ' + esc(l.w) + 'x' + esc(l.h) + ' | ' + esc(l.level) + ' | ' + esc(l.strata) + ' | ' + esc(l.parent) + ' |\n';
}
md += '\n（另有 UnrealQuest 图钉类可缩层 ' + scalable.filter(l => isUQPin(l.path)).length + ' 个，见第五节）\n';

md += '\n## 四、不可缩放的层（' + notScalable.length + ' 个 —— 全是纹理/文本图层，只能改尺寸；按父级分组统计）\n\n';
const byParent = {};
for (const l of notScalable) {
  const p = l.parent || '?';
  (byParent[p] = byParent[p] || []).push(l);
}
md += '| 父级 | 层数 | 尺寸样本 |\n| :-- | --: | :-- |\n';
for (const p of Object.keys(byParent).sort((a, b) => byParent[b].length - byParent[a].length)) {
  const arr = byParent[p];
  const sample = arr.slice(0, 3).map(l => l.w + 'x' + l.h).join(', ');
  md += '| `' + esc(p) + '` | ' + arr.length + ' | ' + esc(sample) + ' |\n';
}

md += '\n## 五、UnrealQuest 图钉类（' + layers.filter(l => isUQPin(l.path)).length + ' 个，折叠）\n\n';
md += '名字模式：`UnrealQuestWorldMapPin*`（图钉/目标点）、`UnrealQuestPatrolStrokeLayer`（路线描边层）。\n';
md += '这些是任务插件画在地图画布上的标记，**缩放时会跟着画布一起缩放**；它们不是漂移的原因，但会放大/缩小视觉。\n';

md += '\n## 六、顶层相关帧（' + top.length + ' 个 —— 不在 WorldMapFrame 树的 GetChildren 结果里，需点名采集）\n\n';
md += '> ★为什么单列这一段：本客户端 `WorldMapFrame:GetChildren()` **漏报**了 `WorldMapDetailFrame`（它 parent 明明是 WorldMapFrame），\n';
md += '> 而 `BlackoutWorld` 根本不是帧 —— 它是一个 **Texture**。两者都只能在顶层点名采集。\n\n';
md += '| 名字 | 类型 | 尺寸 | 层级 | strata | 父级 | 可缩 | 预估用途 |\n| :-- | :-- | :-- | --: | :-- | :-- | :-- | :-- |\n';
const TOP_PURPOSE = {
  WorldMapFrame: '世界地图主窗（面板本体；移动/透明度的主体）',
  WorldMapDetailFrame: '画布容器（与 WorldMapButton 同尺寸 1002×668，区域贴图/探索覆盖层的宿主）',
  WorldMapButton: '地图画布（引擎绘制区域贴图 + 挂 pin 的宿主）',
  WorldMapPositioningGuide: '定位导引层（1024×768 满窗，玩家/鼠标定位辅助）',
  WorldMapTooltip: '地图专用 tooltip（GameTooltip 子类，pin 悬停提示）',
  BlackoutWorld: '★开图黑幕之一，但是**纹理**（不可缩）—— probe4/5 藏过它，不是真凶',
  WorldMapBlackout: '★★真正的黑幕层（probe8 定案）—— Frame，父级 WorldFrame，level 0',
  WorldMapFrameAreaFrame: '悬停区域标签容器（400×128）',
  WorldMapFrameAreaLabel: '悬停区域名文本（FontString，判漂移的读数口）',
  WorldMapFrameAreaDescription: '区域描述文本（FontString）',
  WorldMapPlayer: '玩家自己在地图上的点',
  WorldMapCorpse: '尸体位置标记',
  WorldMapPing: '地图信号（Model，50×50）',
  WorldMapFlag1: '地图旗帜标记 1', WorldMapFlag2: '地图旗帜标记 2',
  MinimapCluster: '小地图组件簇（与小地图相关，不参与世界地图缩放）',
  WorldFrame: '3D 世界渲染帧（UI 的父级之一）',
  UIParent: '全部 UI 的根',
};
for (const t of top.slice().sort((a, b) => String(a.path).localeCompare(String(b.path)))) {
  md += '| `' + esc(t.path) + '` | ' + esc(t.type) + ' | ' + esc(t.w) + 'x' + esc(t.h) + ' | ' + esc(t.level) + ' | ' + esc(t.strata)
    + ' | ' + esc(t.parent) + ' | ' + (t.scaleable ? '可缩' : '不可缩') + ' | ' + esc(TOP_PURPOSE[t.path] || '（未登记，按名字预估：原生地图件）') + ' |\n';
}

md += '\n## 七、结论：为什么缩放会漂移（结构层证据）\n\n';
md += '1. **地图的区域贴图与探索覆盖层不是 Lua 对象** —— 树内 651 个节点里，' + notScalable.length + ' 个是 region/纹理/文本（不可 SetScale），可缩的 ' + scalable.length + ' 个是帧；引擎绘制的贴图根本不在其中。\n';
md += '2. **`BlackoutWorld` 是纹理、`WorldMapBlackout` 是帧** —— 前者不可缩、后者可缩，这就是 probe9 的 deep 日志里只看到 `WorldMapBlackout` 被缩的原因。\n';
md += '3. **`GetChildren()` 漏报 `WorldMapDetailFrame`** —— 说明本客户端原生地图的树结构不可全信，"遍历所有子帧"本身就不完整；想「全层同缩」也缩不全。\n';
md += '4. 于是缩放后：渲染按引擎自己的几何画贴图/命中、Lua 帧按 SetScale 缩放 → **两套几何** → 悬停/点击漂移，且探索覆盖层错位。\n';
md += '5. 可行的方向（待验证）：\n';
md += '   - 不改缩放，改用「原生缩小按钮/原生缩放」的实现（引擎自己做的缩放，命中与覆盖层都正确）；\n';
md += '   - 或只做「窗口化 + 透明度」（已实测可行），缩放交还原生按钮。\n';

md += '\n## 五、与「缩放漂移」相关的推论\n\n';
md += '1. 可 SetScale 的只有 **Frame**（' + scalable.length + ' 个）；不可缩的 ' + notScalable.length + ' 个是 texture/FontString 图层 —— 它们**只能改尺寸**，而本项目已实测 `SetWidth/SetHeight` 在原生地图上**渲染不跟**（probe2/probe3-C）。\n';
md += '2. 因此「引擎命中不跟 Lua 缩放」的根源是：地图的**区域贴图与探索覆盖层**（region:Texture / GeneratedLuaUIObject）不参与 Lua 缩放，缩放后渲染与命中用两套几何。\n';
md += '3. 黑幕两层里 `WorldMapBlackout`（父级 WorldFrame）可缩、`BlackoutWorld` 不可缩（probe9 的 deep 日志里它没被缩，就是因为它没有 SetScale）。\n';

const outDir = path.join(__dirname, 'doc', '自查');
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, '地图层清单.md');
fs.writeFileSync(outFile, md, 'utf8');
console.log('WROTE: ' + outFile + ' (' + md.length + ' chars)');
console.log('scalable=' + scalable.length + ' notScalable=' + notScalable.length);
for (const g of Object.keys(groups).sort((a, b) => groups[b].length - groups[a].length)) {
  console.log('  ' + g + ': ' + groups[g].length + '（可缩 ' + groups[g].filter(l => l.scaleable === true).length + '）');
}
