# SimpleInfoBar 拉取 · 功能分析 · 整合与优化方案

> 结论先行：**功能值得整合，代码不能照抄**。它是一个 997 行、单文件、自包含的顶部信息条（区域 / 金钱 / 背包 / 帧率延迟 / 专业 / 内存），
> 用的 API 在本客户端**全部真实存在**（已逐条核对 1370 条本地索引 + emberveil wiki 原文）；
> 但它的**国际化只做了 ru/en**、**字体用的是纯拉丁字体**，在**本机 zhCN 客户端上：中文区名/技能名渲染不出来、界面文案全是英文、
> 副职业分类直接失效** —— 这三条必须重做，其余照搬即可。
>
> 仓库：`vivk-17/SimpleInfoBar` · 描述 "Compact info panel for Emberveil (WoW 1.12.1)" · MIT (Copyright (c) 2026 vivk-17) · 最新提交 `a07a2b4`（2026-08-29）
> 落点：`G:\game\u5wow\...\Interface\AddOns\SimpleInfoBar\`

---

## 一、拉取与安装状态

### 1.1 做了什么

```powershell
# 走本机代理（本机直连 GitHub 不通）
$env:HTTP_PROXY="http://127.0.0.1:10809"; $env:HTTPS_PROXY="http://127.0.0.1:10809"
git -c http.proxy=http://127.0.0.1:10809 clone https://github.com/vivk-17/SimpleInfoBar.git <AddOns>\SimpleInfoBar
```

克隆成功（`git status` 干净、与远端同步）。仓库只有 4 个文件：

| 路径 | 大小 | 说明 |
|---|---|---|
| `LICENSE` | 1 KB | MIT，Copyright (c) 2026 vivk-17 |
| `README.md` | 3.7 KB | 俄/英双语说明 |
| `SimpleInfoBar/SimpleInfoBar.lua` | 33644 B / 997 行 | 全部实现 |
| `SimpleInfoBar/SimpleInfoBar.toc` | 411 B | `## Interface: 11200` / `SavedVariables: SimpleInfoBarDB` |

### 1.2 ★ 目录结构有问题，已修（**这条不修，游戏里根本看不到这个插件**）

上游把**插件本体**放在仓库子目录里（`SimpleInfoBar/SimpleInfoBar.lua`），README/LICENSE 在仓库根 —— 而本客户端（1.12 系）只认
`Interface\AddOns\<名>\<名>.toc`。直接 clone 进 AddOns 得到的是 `AddOns\SimpleInfoBar\SimpleInfoBar\SimpleInfoBar.toc`，
**少一层 = 插件列表里不出现**。

已用 `git mv` 拉平（保留 git 历史，暂存为一次 rename）：

```
SimpleInfoBar/SimpleInfoBar.lua -> SimpleInfoBar.lua
SimpleInfoBar/SimpleInfoBar.toc -> SimpleInfoBar.toc
```

- **还原成上游原样**：`git -C <AddOns>\SimpleInfoBar reset --hard`
- **注意**：这是一次**未提交**的本地改动 ⇒ `git status` 会一直显示这两条 rename。以后 `git pull` 上游会因路径冲突而**报错拒绝**
  （不会静默搞坏），届时按上面的 `reset --hard` 还原、拉取、再拉平一次即可。
- 拉平后跑了本项目的语法闸门：`node luacheck.js <...>\SimpleInfoBar.lua` → **`SYNTAX OK: 1 files checked`**。

### 1.3 现在的实际形态

```
AddOns\
├─ EvalHelp\                     ← 我们自己的插件（本仓库）
├─ SimpleInfoBar\                ← 本次拉取（现在可被客户端识别）
│   ├─ .git\  LICENSE  README.md
│   ├─ SimpleInfoBar.toc
│   └─ SimpleInfoBar.lua
├─ EH_DebugBox\  OneBag\  OneBank\  UnrealQuest\  unrealUI\
```

> ⚠️ **和整合后会撞车**：整合完成后，EvalHelp 的信息条与 SimpleInfoBar 会**同时在屏幕顶部画两条**。
> 建议：实测完就把 SimpleInfoBar 留在插件列表里**不勾选**（或直接删掉），只保留 EvalHelp 那一份。

---

## 二、功能分析

### 2.1 它到底是什么

**一条 `Frame` + 一个 `FontString`，宽度随文本自适应**（`frame:SetWidth(text:GetStringWidth() + 18)`）。
六个「块」拼成一行，用 `|cff5a5a5a|||r` 风格的竖线分隔；每块都能单独关、顺序可调。

```
区域 贫瘠之地 · 陶拉祖营地 | 金钱 1g 81s 97c | 背包 23/60 | 网络 58 fps · 84 ms | 专业 制皮 145/150 | 内存 14 MB
```

### 2.2 六个块（数据源 / 着色 / 刷新）

| 键 | 标签 | 数据源 | 着色规则 | 备注 |
|---|---|---|---|---|
| `zone` | 区域 | `GetZoneText()` + `GetSubZoneText()` | 区名纯白、子区灰 `·` 前缀 | `GetSubZoneText()` 无子区时**返回零个值**，代码用 `if sub == nil then sub = ""` 正确处理（与 wiki 一致） |
| `money` | 金钱 | `GetMoney()`（铜）→ g/s/c | 金 1b 金 / 银 银灰 / 铜 橙 | 为 0 的更高位不显示 |
| `bags` | 背包 | `GetContainerNumSlots/GetContainerItemInfo`，包 0~4 | 白；**≤8 黄；≤3 红** | 空槽纹理是 `""`（Lua 里**真值**）⇒ 代码显式比 `nil or ""` |
| `net` | 网络 | `GetFramerate()`、`GetNetStats()` 第 3 返回 | FPS ≥50 绿 / ≥30 黄 / 否则红；延迟 ≤100 绿 / ≤250 黄 / 否则红 | 注释已写明「本客户端返回 **3 个**值：in/out/latency」——**核对无误** |
| `prof` | 专业 | `GetNumSkillLines` + `GetSkillLineInfo` | 距上限 **<10 红、<25 黄**（阈值可配 `/sib profbad\|profwarn N`） | 见 §5.1 的**重大缺陷** |
| `mem` | 内存 | `GetScriptMemory()`；<1MB 时退回 `collectgarbage("count")/1024` | 白 | 小于 10 显示一位小数 |

### 2.3 交互

- **左键**：拖动（`RegisterForDrag("LeftButton")` + 额外再挂一份 `OnMouseDown` —— 作者注释说客户端 `OnDragStart` 有 15px 阈值，所以补一条直按路径）。拖动结束 `SavePosition()` 把 `GetPoint(1)` 的 4 个值存盘。
- **右键**：自建菜单（**不是**客户端原生下拉）。结构 = 标题 + 「显示」6 个复选 + 「顺序」6 行（点一下上移一位）+ 标签/背景/锁定 3 个复选 + 「语言」3 个单选 + 重置位置 + 隐藏面板。
- **悬停**：`GameTooltip` 显示「空格数 / 是否锁定 / 拖动提示 / 右键提示」；同时把背景点亮成金边。
- **菜单自动关闭**：`OnEnter/OnLeave` 计 `hoverCount`，`OnUpdate` 里空闲 >1.5s 关。**没有**「点弹窗外即关」的全屏捕获层（本项目规范要求有）。
- **命令**：`/sib` 或 `/simpleinfobar`，支持 `menu / zone / money / bags / net / prof / mem / profwarn N / profbad N / show / hide / toggle / lock / unlock / bg / labels / lang ru|en|auto / pos X Y / reset / debug`。

### 2.4 存档（`SimpleInfoBarDB`，全局 SavedVariables）

`point/relPoint/x/y`（位置）· `locked` · `hidden` · `background` · `labels` · `lang` · `showZone/showMoney/showBags/showNet/showProf/showMem` · `profBad/profWarn` · `order`（逗号串，如 `"zone,money,bags,net,prof,mem"`）

> `order` 用**字符串**存、`OrderList()` 每次现解析 + 补齐缺失项 —— 这个设计很稳（表结构改了也不会崩），值得照抄。

---

## 三、API 核实（逐条对照，结论：全部可用）

本地 `api_*.html` 内嵌了完整的 **1370 条** API 索引，把它解析出来逐条比对：

| API | 索引 | emberveil wiki 原文核实 |
|---|---|---|
| `GetNetStats` | ✅ | 返回 3 个：in KB/s、out KB/s、**latency ms** ✅ 与代码第 3 返回取值一致 |
| `GetFramerate` | ✅ | — |
| `GetScriptMemory` | ✅ | 「GC 字节数换算成**向下取整的整 MB**」✅ 与代码 `mb < 1` 时退回 `collectgarbage("count")` 的兜底逻辑吻合 |
| `GetContainerNumSlots` / `GetContainerItemInfo` | ✅ | — |
| `GetNumSkillLines` / `GetSkillLineInfo` | ✅ | ★ 返回 **12 个值**：`skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost(nil), rankCost(nil), minLevel, skillCostType`。代码取 `name, header, _, _, _, _, maxRank, abandonable` ⇒ **第 7 = maxRank、第 8 = isAbandonable，位置完全正确** ✅ |
| `GetZoneText` / `GetSubZoneText` / `GetRealZoneText` | ✅ | 「`GetSubZoneText` 无子区时**不返回值**（不是 `""`）」✅ 代码已处理 |
| `GetMoney` / `GetLocale` / `GetTextWidth` / `GetStringWidth` / `SetFont` | ✅ | — |
| `SetBackdrop` / `SetBackdropColor` / `SetBackdropBorderColor` / `SetClampedToScreen` / `SetToplevel` / `IsMouseEnabled` / `RegisterForDrag` / `StartMoving` / `StopMovingOrSizing` / `GetPoint` / `EnableMouse` | ✅ | — |

另一条附带收益：wiki 明确 **`isExpanded` / `isAbandonable` 是 `1` / `nil`，不是 `true` / `false`** ——
代码里 `abandonable == 1` 的写法是**对的**（本项目铁律「谓词绝不 `==1`」是针对返回布尔/数字两可的自有判定，
这里 wiki 明说是 1/nil，照它写没问题）。

⚠️ **仍需真机确认的一条**（写代码前别猜）：**副职业分类**（见 §5.1 第 3 点）。

---

## 四、整合方案（落点：`/eh cfg` → **工具箱** Tab → 「UI 工具」组）

### 4.1 推荐路线 A：移植成自包含工具模块 `tools/InfoBar.lua`（**推荐**）

完全套用本项目已定型的**模块行**机制（与 `tools/SimpleMap.lua`、`tools/LootCursor.lua` 同一套），
`Toolbox.lua` 里**只加一行数据**，界面/控件/tooltip/下拉全在模块自己文件里：

```lua
-- Toolbox.lua「UI 工具」组内，紧跟 simpleMap / lootCursor 之后
{ t = "mod", mod = "infoBar", key = "infoBar", label = L("TB_INFOBAR"), tip = L("TB_INFOBAR_TIP") },
```

模块侧必须遵守的三条契约（本项目铁律，缺一条就是静默失效）：

1. **载入期零副作用**：顶层只准声明 + `IB_TB_ROWS["infoBar"] = ibRow` 登记（照 `tools/LootCursor.lua` 的写法：
   取 `rawget(_G,"EVAL_TB_MOD_ROWS")`，没有就现建一个再 `rawset`），**不建帧/不挂事件/不读存档**，首用才建。
2. **自带 `local function L(k)`**（内部走 `EVAL_L`），且**只调全局桥**（`EVAL_SAY` / `EVAL_TB_CFG` / `EVAL_HELP_CONFIG` / `EVAL_DD_OPEN`），绝不引用宿主 local。
3. **桥一律「调用时读」**（`c()` / `tbCfg()` 是懒代理，载入期那是空表 —— 本项目的老雷）。

#### 改动清单（6 处）

| # | 文件 | 改什么 | 量级 |
|---|---|---|---|
| 1 | `tools/InfoBar.lua` | **新建**：全部实现（真值 + 存档子树 + 界面 + 有界计时器 + `EVAL_IB_ENABLED/SET/RESET_POS/INSTALL` + 读值口 `EVAL_IB_TEST_*`） | ~450 行 |
| 2 | `EvalHelp.toc` | `tools\InfoBar.lua` 加一行 | 1 行 |
| 3 | `Toolbox.lua` | 上面那一行 `t = "mod"` 数据 | 1 行 |
| 4 | `Locales/zhCN.lua` `enUS.lua` `ruRU.lua` | 新增 `TB_INFOBAR` / `TB_INFOBAR_TIP` + 模块全部文案（约 40 键 × 3 语言） | ~120 行 |
| 5 | `tools/Probes.lua` | `/eh go 信息条 [状态\|开\|关\|重设\|诊断]` 探针（按 `PR[id]` 注册，宿主只留一行 `prRun`） | ~40 行 |
| 6 | `README*.md` / `CHANGELOG.md` | 功能与版本记录 | — |

> `node sync_game.js` **不用改**：toc 清单是脚本现算的，且本机形态下主插件本来就跳过复制。

#### 真值设计（单一来源，别再开第二份）

- **主开关**：`tbCfg().infoBar`（默认**关** = opt-in，与 simpleMap / lootCursor 一致），读写走模块的 `EVAL_IB_ENABLED()/EVAL_IB_SET(v)`。
- **子配置**：`EVAL_HELP_CONFIG.infoBarCfg`（模块自己的子树）—— 块开关、顺序、字号、透明度、背景、锁定、位置、专业阈值。
- **绝不**复用它的 `SimpleInfoBarDB`：键名不同、语义不同，导入只会带来两处真值打架。
- 位置记忆要按本项目铁律做**越界回归**（`uiOffscreen`），且**先抓原值再写新值**。

### 4.2 路线 B：把它当独立子插件挂进来（**不推荐**）

可行（`Toolbox.lua` 的 `SUBADDONS` 表 + `addons/` 目录 + `EVAL_PLUGIN_ENABLED/SET` 机制），但代价明确：

- 引入**第三方运行时依赖**：对方以后再改版，我们的面板会跟着变；
- **两套存档真值**（`SimpleInfoBarDB` 与 `EVAL_HELP_CONFIG`）、两套语言机制（它的 ru/en vs 我们的三语 `EVAL_L`）；
- 它自己的 `frame:SetWidth` / strata / 位置记忆**不受我们任何规范约束**（本项目踩过的坑它一个都没防）；
- 工具箱子插件行是「整包启停」，**没法做逐块开关**。

结论：**只有当你想「原样跑一跑做对比」时才用它**；正式落地走路线 A。

### 4.3 放置位置建议

工具箱「UI 工具」组内顺序建议：`缩放大地图` → `图层拖拽` → `图层隐藏` → `拾取贴手` → **`信息条`**。
理由：信息条是屏幕常驻件，与「地图/图层/拾取」同属 UI 类；与商人/社交/任务组无关。
默认位置别用它的 `TOP, -20`：本插件**战斗信息UI**（`cfg.ui`）默认在 `TOP, y=-180`，两者相距 160px 不会撞，
但若用户把战斗信息UI 往上挪就会压在一行 —— 信息条默认给 `TOP, -20`、并把「重设位置」做成模块 `[设置]` 里的一项即可。

---

## 五、优化方向

### 5.1 国际化（**最要紧，现状在本机基本不可用**）

本机存档 `EvalHelp.lua` 里 `["lang"] = "zhCN"`（且 `tools/IconGrid.lua` 的注释也写明「本客户端是 zhCN」）⇒ 现状：

| 问题 | 现状 | 后果 | 修法 |
|---|---|---|---|
| ★★ **字体** | 先 `CreateFontString(...,"GameFontNormalSmall")`，**只在字体对象取不到时才** `SetFont("Fonts\\FRIZQT__.TTF")` | ★**已实测推翻「中文渲染不出来」的判断**：真机截图里「贫瘠之地 · 十字路口」渲染正常 ⇒ 走**字体对象**这条路本身是对的，坏的是那个 `FRIZQT__` 兜底（纯拉丁） | **不写死任何 .ttf**：用客户端字体对象链 `GameFontNormalSmall → GameFontHighlightSmall → ChatFontNormal → GameFontNormal`；背景关掉时要描边，则从 `GetFont()` 读回路径/字号再写回（只改 flags）——见 §八 |
| ★★ **语言只有 ru/en** | `CurrentLang()`：`ruRU→ru`，其余一律 `en` | **中文客户端整条信息条与菜单全是英文**（真机截图实证：`Zone/Money/Bags/Net/Professions/Memory`） | 按本项目**国际化规范**：键全部进 `Locales/{zhCN,enUS,ruRU}.lua`，模块自带 `local function L(k, ...)` 走 `EVAL_L`（用户定稿：「信息最好做成当前插件的国际化规范」） |
| ★★★ **副职业靠本地化名字硬编码** | `SECONDARY_HINTS` 只列了 `Cooking/First Aid/Fishing/Кулинария/Первая помощь/Рыбная ловля/...` | zhCN 客户端「烹饪/急救/钓鱼」**一条都匹配不上** ⇒ 要么漏显示，要么混进不该显示的类别 | **别再加第三种语言的词表**（下次换个客户端又废）。两条正路：① 先真机探一次 `GetSkillLineInfo` 的 `isAbandonable` —— 若副职业也是 `1`，`SECONDARY_HINTS` **整块删掉**；② 若副职业 `isAbandonable` 是 `nil`，改用**结构性判据**（如「该分类下所有技能行 `maxRank ≤ 上限阈值`且不可遗忘」）或直接**按分类顺序/已知首技能 id 判定**，仍在 zhCN 名字以外找依据 |
| **货币单位** | 硬编码 `g / s / c` | 中文界面写「1g 81s 97c」 | 单位进语言包（`金/银/铜` 或英文 `g/s/c`），或直接换成宏图标里的金币图标 |
| **开关状态文案** | 命令回显里裸写 `"on"` / `"off"` | 中文界面英文回显 | 进语言包 |
| **toc** | 只有 `## Notes:` + `## Notes-ruRU:` | 中文插件列表看不到说明 | 加 `## Notes-zhCN:`（我们主插件已有先例） |

### 5.2 性能（它有实打实的浪费）

| 问题 | 现状 | 成本 | 建议 |
|---|---|---|---|
| ★★ **每 0.5s 全量扫包** | `Refresh()` → `ScanBags()` 遍历包 0~4、**逐格** `GetContainerItemInfo` | 满包约 **70 次 API/拍 ⇒ ≈140 次/秒**，**且背包块关掉时照样扫** | ① 背包块关闭时**一次都不扫**；② 只在 `BAG_UPDATE`/`ITEM_LOCK_CHANGED` 之后扫（事件驱动，本项目频率防护总则）；③ 保留节流 0.5s 兜底 |
| ★ **专业扫两遍** | 先 `ProfessionCategories()` 全表走一遍，再 `SegProf()` 又全表走一遍 | 2× `GetSkillLineInfo` | 合并成**一次遍历**同时产出「分类集合 + 文本」 |
| ★ **每拍重排一次** | `text:SetText(out)` + `text:GetStringWidth()` + `frame:SetWidth()` 无条件执行 | 布局抖动 / 字符串反复拼接 | 缓存上一次的 `out`：**内容没变就一个 API 都不发**（本项目铁律「数据刷新不许改可见性」的同类） |
| **14 个事件全置 `dirty`** | `OnEvent` 一律 `dirty = true` | 影响小，但语义糊 | 按块分派脏标记：金钱只认 `PLAYER_MONEY`、包只认 `BAG_UPDATE/BAG_CLOSED/ITEM_LOCK_CHANGED`、区域只认 `ZONE_CHANGED*`、专业只认 `SKILL_LINES_CHANGED/CHAT_MSG_SKILL`、网络走自己的 0.5s 拍 |
| **隐藏时不刷新** | `Refresh()` 开头 `if not frame:IsShown() then return end` | ✅ 这条是**对的**，照抄 | — |
| **`OnUpdate` 常驻** | 一个帧一个 `OnUpdate` 做累加器 | 单帧成本可忽略（与 `wAtkGuard` 同量级） | 可保留；若要更省，可只在**可见时**才注册 |

### 5.3 界面美化 / 交互规范（对齐本项目已有范式）

| 项 | 它的做法 | 本项目规范 | 建议 |
|---|---|---|---|
| 菜单 | **自建 Frame** + 池化 Button + hover 计时自动关 | **无原生下拉 ⇒ 一律 `EVAL_DD_OPEN(锚点, 选项, 回调)`**（多选 `multi=true` + `selected`）；「点弹窗外即关」= 宿主自建全屏捕获 Button（level = 弹窗 − 5） | 全部换成 `EVAL_DD_OPEN`；「显示哪几块」用多选、「块顺序」另开一项或做成上移/下移操作 |
| 纯色纹理 | `Interface\Tooltips\UI-Tooltip-Background` | **只有 `Interface\Buttons\WHITE8X8` + `SetVertexColor` 可靠** | 统一换 `WHITE8X8` |
| 拖动柄 | Frame 自己 `RegisterForDrag` + 补 `OnMouseDown` | **拖动柄必须用 `Button`**（Frame 的 `OnDragStart` 不触发）+ `SetFrameLevel(父+10)` | 做一个 `Button` 柄带（可用 346 号宏图标做抓手，与框拖拽工具同款） |
| 位置记忆 | 存 `GetPoint(1)` 的 4 值 | 要**越界回归** `uiOffscreen`；`GetCenter/GetLeft` 含缩放、存取要除 `GetEffectiveScale` | 拉平后照做；**禁用 `SetScale`**（点击框漂移） |
| 鼠标事件 | 整条 `frame:EnableMouse(true)` | 纹理/FontString 不吃鼠标 ⇒ 悬停要盖**透明 Button** | 顶部 22px 横条照样吃点击，建议**只让实际文本区吃鼠标**、或提供「锁定后穿透」 |
| 锁定反馈 | 只有 tooltip 一行字 | 应有可见反馈 | 锁定时给柄带换图标/变灰 + 播报 |
| 视觉 | 灰标签 + 白值 + 彩色分隔竖线 | 本项目有**品阶色板**（`SH_SEAL_TIERS`）与统一标题条配色 | 配色收进模块常量表；分隔符可换成「·」或小图标；每块前加 16×16 宏图标（金币/背包/网络…） |
| 可配项 | 只有块开关/顺序/标签/背景/锁定/语言 | 配置项集中在 `[设置]` 的悬停里有说明（模块行硬性要求：`r.extra:Hide()`） | 补：字号、整体透明度、块间距、锁定、面板宽度上限（长区名截断，按**字符**不按字节 —— 走 `uiClip`） |

### 5.4 功能扩展（可选，按价值排序）

1. **耐久度**（`GetInventoryItemDurability`）—— 与背包/金钱同组，实用度最高；
2. **经验/声望条**（已有 `EvalHelp.lua` 的条状绘制范式可复用）；
3. **目标/队友计数**、**公会在线人数**（`GetNumGuildMembers` 本项目已确认存在）；
4. **服务器时间 / 本地时间**（`GetGameTime` + `GetTime`，wiki 已确认存在）；
5. **任务日志剩余格数**（`GetNumQuestLogEntries` / `MAX_QUESTLOG_SLOTS`）；
6. **一键宏状态**（当前方案名 / 是否在战斗中）—— 与本插件主体联动，辨识度最高；
7. **每块点击 = 打开对应原生窗**（点金钱开背包、点背包开行囊）—— 交互增值明显。

---

## 六、风险与红线

1. **MIT 署名**：`Copyright (c) 2026 vivk-17`。移植代码**必须保留版权声明** —— 建议在我们 `tools/InfoBar.lua` 文件头注明
   「移植自 vivk-17/SimpleInfoBar (MIT)」，并在 `doc/` 或 README 里保留 LICENSE 全文引用。
2. **两条信息条**：整合后 SimpleInfoBar 仍在插件列表里 ⇒ 建议实测完就不勾选 / 删除。
3. **不要复用它的存档键** `SimpleInfoBarDB`。
4. **本项目没有测试兜底**（`tests/` 已按用户决定删除）⇒ 改完**只跑 `node luacheck.js`**，
   接线/渲染/存档类静默失效**没有自动判据** ⇒ 交付时必须写明「本轮只过了语法闸门」，**真机实测才是最终判据**。
5. **不要照抄它的 `SECONDARY_HINTS`**（见 §5.1）—— 这是唯一一处「照着抄就会在 zhCN 上错」的逻辑。

---

## 七、下一步（建议顺序）

1. （可选，**1 分钟**）真机跑一次副职业探针：打印 `GetSkillLineInfo` 全 12 个返回，逐行看「烹饪/急救/钓鱼」的
   `header / skillMaxRank / isAbandonable` ⇒ 决定 `SECONDARY_HINTS` 是**删掉**还是**换结构性判据**。
2. 确认口味：模块名 `信息条` vs `状态条`；默认开还是默认关；默认位置。
3. 我按 §4.1 的 6 处清单落地 `tools/InfoBar.lua`（三语 + 字体链 + 事件驱动 + `EVAL_DD_OPEN` 菜单 + 越界回归 + `/eh go 信息条` 探针）。
4. 过 `node luacheck.js` → `node sync_game.js` → 真机 `/eh cfg` 工具箱勾选实测 → 按实测结果迭代。

---

### 附：本次改动清单

| 路径 | 动作 |
|---|---|
| `AddOns\SimpleInfoBar\`（整仓） | 从 GitHub 克隆（`a07a2b4`） |
| `AddOns\SimpleInfoBar\SimpleInfoBar.lua` / `.toc` | `git mv` 从子目录拉平到仓库根（未提交） |
| `EvalHelp\tmp\sib_api_probe*.js` `sib_wiki*.js` | 一次性核对脚本：解析 `api_*.html` 内嵌的 1370 条索引 + 走代理抓 wiki 原文核返回签名 |
| `EvalHelp\doc\SimpleInfoBar-分析与整合方案.md` | 本文档 |

---

## 八、落地结果（1.75.40 已实现并真机跑通）

> 用户定稿的三条口径：**① 按本插件国际化规范（三语）② 不需要特殊字体（不写死 .ttf）③ 布局按设计重新做**。

### 8.1 新增 / 改动（6 处）

| # | 文件 | 改了什么 |
|---|---|---|
| 1 | `tools/InfoBar.lua` | **新增**（约 690 行）：全部实现 —— 真值/存档子树/皮肤/分块/刷新/事件/位置/下拉/探针/模块行 |
| 2 | `EvalHelp.toc` | `tools\InfoBar.lua` 加一行（`tools\LootCursor.lua` 之后） |
| 3 | `Toolbox.lua` | 「UI 工具」组加**一行数据** `{ t="mod", mod="infoBar", key="infoBar", … }` |
| 4 | `Locales/{zhCN,enUS,ruRU}.lua` | 各 +29 键（`TB_INFOBAR` / `TB_INFOBAR_TIP` + 27 个 `IB_*`） |
| 5 | `tools/Probes.lua` | `PR["IB"]` 转发到模块的 `EVAL_IB_CMD`（命令本体留在模块自己文件里） |
| 6 | `EvalHelp.lua` · `Core.lua` | `VARIABLES_LOADED` 里 `pcall(EVAL_IB_INSTALL)`；`/eh go 信息条` 别名；残渣键清单 + `ibProbe` |

### 8.2 与"原版"的差异（都是有意为之）

| 项 | 原版 SimpleInfoBar | 本实现 |
|---|---|---|
| 文案 | 只 ru/en，硬编码在文件里 | 三语语言包 + `L()`（本插件国际化规范） |
| 字体 | `GameFontNormalSmall`，取不到则回退 `FRIZQT__.TTF`（纯拉丁） | **只走客户端字体对象链**，一个 .ttf 路径都不写死 |
| 拖动柄 | Frame 自己 `RegisterForDrag` + 补一份 `OnMouseDown` | **Button**（本项目铁律：Frame 的 `OnDragStart` 不触发） |
| 右键菜单 | 自建 Frame + 池化 Button + hover 计时自动关 | `EVAL_DD_OPEN` 多选下拉（宿主统一弹层，含"点外部即关"的捕获层） |
| 背景/边框 | `Tooltips\UI-Tooltip-Background` 整块 `SetBackdrop` | `WHITE8X8` + `SetVertexColor` 手搓（深色玻璃板 + 1px 细金框；**本项目唯一可靠的纯色纹理**） |
| 刷新 | 每 0.5s **无条件全量扫包**（满包 ≈140 次 API/秒），且背包块关着也扫 | **事件驱动 + 分块脏标记**：背包只在 `BAG_UPDATE` 系列后扫；`net/mem` 才走 0.5s 节拍 |
| 内容不变 | 每拍都 `SetText` + `GetStringWidth` + `SetWidth` | 文本没变**一个 API 都不发** |
| 专业扫描 | 两遍 `GetSkillLineInfo` | 一遍 API + 一遍纯表 |
| 专业分类 | `isAbandonable==1` **或** 硬编码的 en/ru 次要技能名表 | 只用 `isAbandonable==1`（locale-free）+ **自诊断**把没归类的技能行摊出来 |
| 专业阈值 | 硬编码 10/25，只能 `/sib profwarn N` 设 | 三档预设（宽松 5/15 · 标准 10/25 · 严格 20/40），`[设置]` 菜单里直接选 |
| ★★★ **内存口径** | 显示 `GetScriptMemory()`（本机恒 **999**） | ★**它读错了**：wiki（Addon 页 SetScriptMemory 段）原文「…that stored integer is returned. Otherwise this is the Lua GC byte count…」⇒ `GetScriptMemory()` 优先返回**客户端存过的那个整数 = 脚本内存上限**，不是占用。现改为条上显示 **Lua 堆实际占用**（`collectgarbage("count")`），限值挪进 tooltip；GC 取不到就如实显示「不可用」，**绝不拿限值冒充用量** |
| 右键菜单 | 一个自建菜单混装「勾选 + 动作」 | 拆成**两个**：`[显示]` 多选（勾选类）· `[设置]` 非多选（顺序上移 / 阈值 / 重设 / 隐藏）。★因为 `EVAL_DD_OPEN` 的多选模式**每行都是勾选框、`locked` 行连 OnClick 都没有**，没有「动作项」概念 —— 动作塞进多选会「看着像开关、点了执行动作」。非多选点一下就 `dd:Hide()`，所以动作执行后**立刻重开自己**（等价原版的 `keep=true`，菜单不关） |
| 位置记忆 | 存 4 个锚点值 | 多一条**越界回归**（换分辨率后跑到屏幕外 → 回默认并播报） |
| 锁定反馈 | 只有 tooltip 一行字 | 边框由金变灰 + tooltip 说明 |
| 关掉 | 仍留一个 0.5s `OnUpdate` | 摘事件 + **摘 OnUpdate** ⇒ 真的零动作 |
| 关掉时的空条 | 显示插件名 | 显示「没有启用任何分块（右键打开设置）」 |

### 8.3 怎么用

- `/eh cfg` → **工具箱** → 「UI 工具」→ **顶部信息条** 勾选（默认**关**，opt-in）。
- 屏幕上：**左键拖动**（位置记忆）· **右键多选设置**（哪几块 / 标签 / 背景 / 锁定）。
- 行右侧两个按钮：
  - **`[显示]`** = 多选下拉：区域 · 金钱 · 背包 · 网络 · 专业 · 内存 · 标签文字 · 面板背景 · 锁定位置。
  - **`[设置]`** = 动作下拉（非多选，点完菜单不关，共 17 行）：`1..6 顺序（点一下上移）` · **专业阈值三档**（宽松/标准/严格，当前档带 ●）· **外观 3 行循环切换**（边框颜色 白/金/青/紫/暗灰 · 边框浓度 淡/中/明显 · 面板浓度 半透明/标准/实）· `重设位置与顺序` · `隐藏面板`。
    - ★「隐藏面板」= **关掉总开关**（工具箱那一行的勾选框同步取消），不另开 `hidden` 状态；并如实播报回头路。
- 命令：`/eh go 信息条 [状态 | 开 | 关 | 重设 | 顺序 zone,money,… | 诊断 | 存档 | 清]`。
  - ★**`诊断`** 是专业分类的判据入口：它会把「`maxRank>1` 却没被判成专业」的技能行逐条点名 ——
    真机跑一次就知道本客户端的**次要技能（烹饪/急救/钓鱼）`isAbandonable` 到底是不是 1**，
    若不是，就照这份清单换判据（**别再往里加第三种语言的技能名**）。它同时把**内存的两个读数**
    （`collectgarbage` 堆占用 vs `GetScriptMemory` 限值）分开报出来，取证用。

### 8.4 真机报障与修复（首轮实测后，用户三条）

| # | 用户原话 | 根因 | 修法 | 判据 |
|---|---|---|---|---|
| 1 | 「信息条他有右键配置功能吗？**我这边无法打开**」 | ★**真 bug**：`OnClick` 里只判了回调第 2 形参 `button == "RightButton"`，而**本客户端把按键名放在全局 `arg1`** ⇒ `button` 是 nil ⇒ 分派代码永远进不去 | 换成项目已验证的**三元探测**（照 `EvalHelp.lua:699/789/909/1753/5682` 五处）：`(type(a)=="string" and a) or (type(b)=="string" and b) or (type(arg1)=="string" and arg1) or "LeftButton"` | harness ⑲（三种投递方式都要能开 + 左键不误开）+ **变异验证** `node tmp/infobar_mutate.js`（改回旧写法 ⇒ 恰好 2 条变红 ⇒ 断言不是摆设） |
| 2 | 「右侧的文字**溢出了**」+「提示信息现在如果没有设置功能，可以直接隐藏」 | 悬停里有「脚本内存上限 999 MB（那是限值…）」这种**长信息句**，真机上撑破提示框右缘；且这些行**都不是可操作项** | 悬停**只留操作说明**（标题 / 左键拖动位置 / 右键打开设置）；「背包空格」与「内存上限」两行**不再上屏**（背包数条上本来就有；限值要看走 `/eh go 信息条 诊断`）。两个语言键保留备用 | harness ⑬：悬停恰好 3 行 · 不含 `IB_TIP_FREE` / `IB_TIP_MEMLIM` |
| 3 | 「尺寸可以宽一点」 | — | `IB_PAD 10 → 16`、`IB_H 20 → 22`（12pt 中文上下更透气） | 真机截图 |
| 4 | 「**还是溢出**」 | ★**根因**：本客户端 `GetStringWidth()` 对**中文偏窄**（harness 实测：同一条文本 `GetStringWidth` 给出真实排版宽的 **86%**）⇒ 算出来的框比渲染窄一成多，字就压出金边。**只靠它一个读数永远不够** | **三读数取最大 + 量回自证收敛**（最多 3 轮）**+ 有界重申窗口**（文字变后 3 拍再量，兜住「排版晚一拍」）**+ 第三道保险：自估宽度**（剥掉 `\|c…`/`\|r`/`\|\|` 色码后按 UTF-8 首字节估：中日韩 1.0 em · 拉丁扩展 0.5 em · 空格 0.3 em · 其余 ASCII 0.5 em） | harness ⑳（定宽/帧实测宽都必须 ≥ **真实排版宽** + 2×内边距；并核自估没被色码估虚高）+ **变异验证**（改回「只看 GetStringWidth」⇒ ⑤条变红）；`/eh go 信息条 状态` 现报**四个宽度读数** |
| 5 | 「背景框**圆角背景**参考 → 工具箱 → 姓名右键弹窗设计」 | 原实现是「WHITE8X8 方形底 + 四条 1px 平边」，方角 | **整套照抄 `tbMenuChrome`**：原生 `bgFile = UI-Tooltip-Background` + `edgeFile = UI-Tooltip-Border` + `tile/tileSize/edgeSize = 16`（整数）+ `insets 4`，底色/边框色也用该弹窗同款（`0.01,0.01,0.02` + 白高亮）；★**圆角档下必须藏掉自绘方底与四条平边**（Toolbox 原注释：叠方底会发黑、还盖住圆角）；挂不上 ⇒ 退回原来的方形底+平边 | harness ㉑（挂上的是不是那张边贴图 · insets/edgeSize/tile · 方底与平边已藏 · 底色 0.88）+ ⑰（**新开一个 Lua 状态**模拟 `GetBackdrop` 读不到 ⇒ 必须走退化路径且四条平边都在）；alpha 老存档 `0.62 → 0.88` 用 `skinVer` **一次性迁移** —— ★迁移必须排在「补默认值」**之前**（DEF 里也有 skinVer，先补就把迁移条件抹平了，harness 当场抓到） |
| 6 | 「**左侧空白有点多**」 | ★★★**我自己的反馈环**：`ibFit` 里拿 `FontString:GetWidth()` 做「量回自证收敛」，而**本客户端对「居中且无显式宽度」的 FontString 回的就是帧宽回声**（≈ 我们刚设的宽）⇒ `need = tw + 2×PAD + SLACK` **每轮都比上一轮大** = 正反馈，3 轮多出上百像素；字居中 ⇒ 两侧各多出几十像素（用户看到的就是"空白多"） | **定宽只用两个互相独立的读数取大**：客户端 `GetStringWidth()`（真机对中文偏窄 14%）· **自估**（剥色码 + 按 UTF-8 字符算）；**`GetWidth()` 退居探针读数、绝不进计算**（删除收敛环与「有界重申」） | harness ⑳（定宽/帧宽必须 **≥ 真实排版宽 + 32** 且 **≤ 真实排版宽 + 52** —— 后半条就是「空白过多」的守门员）+ **两条变异**（丢掉自估 / 凭空加宽 120px，都必须变红） |
| 7 | 「**边框颜色能设置么?**」+「**边框透明度可以低一点**」 | 边框颜色与浓度都是写死的（白 · 0.75） | `[设置]` 菜单加**外观段 3 行循环切换**（点一下换下一个；比 5 色×3 浓度×3 面板 = 14 行的多选项省得多，也不会把下拉撑成两列）：**边框颜色** 白/金/青/紫/暗灰 · **边框浓度** 淡 0.25 / **中 0.40（新默认，原 0.75）** / 明显 0.70 · **面板浓度** 半透明 0.55 / 标准 0.88 / 实 0.96。悬停 = 基准 +0.30，锁定 = 冷灰（与所选颜色无关，保证锁定反馈始终可见） | harness ㉓（默认 0.40 且真写进 backdrop · 颜色循环 5 档并能绕回 · 浓度循环 · 面板浓度循环 · 重设不动外观）；`skinVer` 迁移只顶面板 alpha，不碰边框设置 |
| 8 | 「**左侧空白还是很多。不能左对齐吗?**」→（改完）「**右边位置不要设置边距试下，缩小点**」 | ① 定宽是**估**出来的、估多出来的余量在**居中**布局下会**左右各摊一半** ⇒ 左缘永远有一段看不见的空白；② 左对齐之后，右侧又剩下「右内边距 16 + 余量 6 = 22px」显得空 | ① **文本改左对齐**（用户定稿）：`text:SetPoint("LEFT", root, "LEFT", IB_PAD, 0)` + `SetJustifyH("LEFT")` ⇒ **左缘恒为 16px 内边距，一个像素都不多**；② **右内边距由 16+6 收到 `IB_RPAD = 4`**（定宽 = `w + IB_PAD + IB_RPAD`）⇒ 右侧只剩 4px。★左右内边距拆成两个常量（`IB_PAD` / `IB_RPAD`），不再共用一个 | harness ㉔（锚点 LEFT · 左缘 16 · JustifyH LEFT）+ ⑳ 上下界改为 **`trueW+16` ~ `trueW+28`**（下界护"压边框"、上界护"右侧留白过多"）+ **变异**（改回居中 ⇒ ㉔ 红 3 条；凭空加宽 120 ⇒ ⑳ 红 2 条） |
| 9 | 「**这个信息显示的位置不对**」（悬停提示跑到屏幕中下方，离条两百多像素） | `ibTip` 只给了 `GameTooltip:SetOwner(root, "ANCHOR_BOTTOM")` 一个锚点**名**，本客户端对 **Button 宿主 + 该锚点名**的自动摆位不按预期走 | **显式摆位**：`SetOwner` 之后 `ClearAllPoints()` + `SetPoint("TOP", owner, "BOTTOM", 0, -4)` ⇒ 永远钉在条的下缘 4px，位置可预期 | harness ⑬（摆位锚点 TOP · 基准 = 条本身 · 贴下缘 · 下让 4px；★断言写成**空安全**——变异版里 `_pt` 是 nil，直接索引会把整份 harness 打挂而不是报红）+ **变异**（删掉显式摆位 ⇒ ⑬ 红 5 条） |

> ★第 1 条是本轮**最有价值的教训**：这个「按键名走 `arg1`」的坑在本项目里**已经踩过一次**（`EvalHelp.lua` 里那五处三元探测就是它的化石），
> 我写新模块时没套用既有配方 ⇒ 真机立刻复现。**新增任何鼠标按键分派之前，先 grep 一遍项目里的既有写法**。

### 8.5 验证状态（如实）

- `node luacheck.js` → **`SYNTAX OK: 44 files checked`**；`node probe_localorder.js` → 模块 OK；
  `node tmp/check_ib_locale.js` → **三语 41 键齐全**。
- `node tmp/infobar_harness.js`（fengari 真跑，**157 条断言**，过程中真抓到并修掉的问题：
  ① 桩把一个分类头塞了三种技能 ⇒ 暴露"分类粒度"这条语义；② harness 自己把 `self` 传重了 ⇒ 右键进不去菜单；
  ③ `local` 写在 chunk 里跨 chunk 读不到 ⇒ 跨 chunk 共享必须用全局；
  ④ `skinVer` 迁移排在「补默认值」之后 ⇒ 被 DEF 里同名的键补成 2、迁移永不触发；
  ⑤ ★`GetWidth()` 帧宽回声进收敛环 ⇒ 越量越宽（真机「左侧空白有点多」的根因，已由 ⑳ 的两条边界断言钉死））：
  覆盖**载入期零副作用 · 关掉零动作 · 六段文本与段序 · 全关提示行 · 背包不被反复扫 · 内容不变不写 ·
  下拉真实回调 · 位置越界回归 · 关掉后事件/API 全静默 · 专业自诊断 · 顺序命令 · 工具箱模块行（两个按钮）·
  内存口径（条上必须是堆占用 12.3、绝不能是 999）· 悬停只剩 3 行操作说明 · 动作菜单 17 项结构 ·
  顺序上移 + 菜单重开 · 阈值三档换色 · 外观三行循环（颜色/边框浓度/面板浓度）· 隐藏面板（单一真值 + 不重开）·
  右键三种投递方式 · 宽度两读数取大（下界与上界都断言）· 自估宽度贴近真实排版宽 · 圆角 backdrop 全部参数 ·
  圆角档藏方底藏平边 · 退化路径（新开 Lua 状态）· 底色一次性迁移**。
- `node tmp/infobar_mutate.js` → **三组变异验证**（`MUTATION ALL OK`）：
  ① 右键分派改回旧写法 ⇒ ⑲ 红 2 条；② 丢掉自估只用 `GetStringWidth` ⇒ ⑳ 红 2 条
  （`fitW=1031.8` < 所需）；③ **凭空加宽 120px**（模拟「越量越宽/空白过多」）⇒ ⑳ 红 2 条（`fitW=1313.6`）。
  ★这一步是必须的 —— 「能过的断言」不等于「能失败的断言」。
- `node sync_game.js` → 本机形态（仓库本址在游戏 AddOns 内）⇒ 主插件跳过、子插件 0 改动。
- ★**仍未覆盖**：真机只有"看得到"这一条证据（用户截图 ✔，且据此把 IB_PAD 10→16、IB_H 20→22）。
  **次要技能分类**必须跑一次 `诊断` 才能定案。
