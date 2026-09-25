# EVAL_HELP 插件项目记忆（EmberVeil 全职业工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md` 与 git 提交历史，不进这里。
> ★★★**指令预算 = 1 MiB**：唯一有效修法 = **web profile 补丁层按 id 覆盖 preset 声明行** —— `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` 里的 `- id: preset-standard / preset-ptc / preset-cordis` 覆盖块（完整重述 `config`，其 `plugins` 内 `agent-instructions.config.maxBytes: 1048576`）。
> 　· **谁生成 / 谁验证**：仓库根目录 **`dsh_memory_budget.js`**（`apply` = 按当前安装内 shipped preset 重生成 + 先备份；`check` = 闸门；`status` = 列候选安装）。★`check` 用「**临时 `DSH_HOME` + 官方 `dsh --profile web --dump-config`**」自证，纯读、不起服务、不碰真实 profile。
> 　· ★★**两条死路（2026-09-25 都白花过时间）**：① 改安装内的 `dsh-web-app\presets\<id>.patch.yml`（0.1.7 的 preset 就声明在这里）—— 升级 / 换 `_npx` hash 即回 65536；② profile 补丁里只写**单层** `- id: agent-instructions` —— 宿主那一行被 web-app bundle 补丁 `disabled: true` 关掉了，`dump-config` 实证**写了也不生效**。
> 　· ★**覆盖会替换整个 `config`**（官方 `dsh-agent-preset` 的 `skills/editing-cordis-compositions`）：**少写字段 = preset 激活失败**（2026-09-25 早上 GUI 崩过一次就是这个）⇒ 一律脚本生成，别手改。
> 　· **判定「现在跑的是哪一份安装」别猜 `_npx` hash**：★指纹 = **自己有没有 `ralph` 工具**（0.1.5 的 standard preset 开着 `tool-ralph`，0.1.7-rc.2 的 standard/ptc **关着**）⇒ 2026-09-25 实测 = **全局 `%APPDATA%\npm\node_modules\@deepseek-ai\dsh`（0.1.7-rc.2）**；`profiles\node_modules` 里指向 `_npx\<hash>` 的 junction 只是旧痕迹。
> 　· **生效时机**：`patchReload = startup` ⇒ **必须重启 GUI**，且只对**新开会话**生效（旧会话保持原预算）。
> 　· **验证**：把本文件临时撑过旧上限（>65,536），看下一次注入有没有 `Workspace instruction budget … truncated`、尾部标记是否还在（只看「没报错」不算）；旧上限下软上限 ≈ **65,240 字节**（超了从尾部截断，尾部铁律 AI 看不到）。全案见参考卷 **附录 R17**。
> ★★**本文件是「常驻卷」**——其余整卷在**同目录的 `CLAUDE_REFERENCE.md`（参考卷，不自动载入）**：
> · 发布 release 流程 **9 步全文 + 打包脚本 + 推送信息** · §六 历史教训汇总 · §七 开源仓库 / 官方 API 文档 / 待开发计划
> · §八 项目位置与现状（文件结构 · toc 载入顺序 · **新增模块要改哪几处** · 任务线 & 装备设计 · **当前版本**）· §九 版本要点汇总
> · **附录 R：各判据的踩坑全案 / 版本经过**（清理时从本文件迁入；条目里写「全案见参考卷附录 Rx」的就是它）。
> ★**什么时候必须去读参考卷**：要**发布 release**、要查**项目位置 / 当前版本 / 工作流纪律**、要查**历史教训 / 官方文档 / 待开发计划 / 某条判据的完整经过**时。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**；★**新条目先判它属「常驻卷」还是「参考卷」**（常驻卷只放必须随时可见的铁律与判据；**踩坑经过、版本叙事、截图佐证一律进参考卷附录 R**）。
> ★查「某功能/坑现在怎么写」→ 先看第五节判据，再看源码。

## ★★★**不许用子代理处理本项目任务**（用户 1.74.31 明确：「记住不要使用子代理模式处理任务」）

- **规则**：本项目的开发/排查/改代码**一律由我本人直接完成** —— **不许**再调用 `subagent` / `subagent_fork` / `workflow` / `ralph` 这类"把任务外包给另一个 agent"的模式。
- **范围**：包括看起来"很适合并行/很费上下文"的大改造（重构、批量改文件、跨多文件审计）也一样，自己动手。
- **替代做法**：上下文紧张时用「先缩小范围 / 分段做 / 每段跑闸门」的方式自己推进，而不是外包；必要的话先向用户说明进度与取舍。

## ★★★答复语种 = **中文**（用户明确定）

- **用户原话**：「将会话答复语种是中文加入全局记忆」「英文我看不懂」。
- **规则**：本会话及后续所有答复一律用**中文**（含报告、分析、解释、清单）；代码标识符 / API 名 / 事件名 / 英文术语原样保留，不翻译。
- **范围**：这条只管「我用什么语种回答你」，与插件本身的三语言（zhCN/enUS/ruRU）无关。

## ★★★改完代码**自动同步到本机游戏目录**（用户 1.74.8 明确要求）

- **触发条件**：**每次改完插件代码**（.lua / .toc / 素材）之后，**自动**把插件相关文件复制过去 —— 不必等用户开口。
- **本机形态（★2026-09-25 实测修正）**：全盘只有一份安装，**工作区就在它里面**
  （`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp`）
  ⇒ **主插件不用复制**（改完 `/reload` 即生效）；旧记忆里的 `E:\soft\game\eb\...` 本机**不存在**。
- ★★★**但 `addons\` 里的子插件必须复制到「当前插件同级目录」**（用户 2026-09-25 明确）：
  仓库的 `addons\<名>\`（现 `EH_DebugBox`，自带 `.toc`、独立载入）要落到 `Interface\AddOns\<名>\`
  （= 当前插件的**同级**）；否则游戏里跑的是**老的那份子插件**（新模块 + 老实现两套逻辑同时改锚点
  = 1.74.30 修过的那类「两处真值打架」事故）。
  ⇒ **本机也照样跑 `node sync_game.js`**：本机分支 = 主插件跳过 + 子插件复制到同级，并如实报数
  （只复制**内容变了**的文件，可反复跑、幂等；2026-09-25 实测第二次 = 改 0 / 同 4）。
- **复制口径**：以 `EvalHelp.toc` 现算的模块清单为准（与发布包 PACK LIST 同一口径），落到 `AddOns\EvalHelp\`；
  ★**连同子目录**（`tools\`、`Locales\`、`examples\`）一起递归复制；★**不要**把仓库里的测试文件
  （`test_*.lua`、`luacheck.js`、`tmp\`、`preview\`、`doc\`、`.git`）带过去。
- **次序**：**先跑完两道闸门**（`node luacheck.js` + `node test_engine.js`，都要 exit 0）**再复制** ——
  否则会把一个**载不进去的插件**同步进游戏目录，真机表现是「整个插件失效」且 UE 日志看不到原因（铁律 1）。
- **同类判据**：这与「发布包」是**两条独立出口**（发布包出 zip、这个直接进游戏目录），别互相替代；
  游戏目录那次**不是** release 的一部分，**不需要**打标签/出包/建 Release。
- ★**注意**：这是**用户主机上的真实游戏目录**（本机即游戏主机，见铁律 3），复制是**覆盖写**；
  不要删除目标目录里别的东西（那边还有 `UnrealQuest` 与 `.emberveil-addons.json`）。

## ★★★「提交版本」≠「release」（用户 1.72.1 明确划定）

- **用户原话**：「提交版本不要触发 release。在我明确要求 release 才进入这个环节」。
- **「提交版本」= 只做**：`git add <显式路径>` + `git commit`（+ 用户要求时才 `git push origin master && git push github master`）。
- ★**判据**：只有用户**明确说出「release / 发布 / 出包 / 建 Release」**时才进 9 步全套；「提交版本」「提交」「commit」一律停在 commit。**不确定时先问一句，不要自行升级到 release**（1.72.1 多做的代价）。

## ★★★发布 release = 9 步全套（**详细步骤 / 打包脚本 / 推送信息见 `CLAUDE_REFERENCE.md` 的「发布 release 流程」**）

- **9 步**：① 统计里程碑 → ② 三语言 README（版本表只留最近 10 个；版本行插进「## 更新日志」表）→ ③ 扫描旧版信息 → ④ 三语言 `## 🏁 里程碑` 同步（在更新日志之上 · 只 10 条 · 每条一行 `- ` · 归纳不罗列）→ ⑤ `local VERSION` 与 `## Version` 同步、CHANGELOG 留完整历史 → ⑥ 审计记忆体→ ⑦ commit + 附注标签（`git tag -a vX.Y.Z -F 文件`；说明文件必须 UTF-8 无 BOM，**绝不用 PowerShell `>` 重定向**；打完回读复核）→ ⑧ 推分支 + 推标签 → ⑨ 出 zip + 建 Release 页。
- **守这三步的源码检查**：`README TABLE CHECK` · `MILESTONE CHECK` · `PACK LIST CHECK`；发布包 zip 放 `Interface/AddOns/` 下（不进仓库），装完必须核对条目数（以 `.toc` 现算为准，参考卷有当前基准）。
- **Release 页我做不了**（无 gh/token，401）→ 如实请用户网页建并把 URL/标题/说明/附件给全；推送两端都走 `git@` + 默认密钥 + `--tags`。

## 一、铁律

### 1. ★★★改完必须跑语法检查 + 测试（本项目因它白丢过好几个版本的功能）
- **Lua 整文件编译**：任何一处语法错误 → **整个插件无法载入**，且 UE 日志里**看不到**（`%LOCALAPPDATA%\Azeroth\Saved\Logs` 是空目录——本客户端落盘日志通道全废）。
  曾因两处 `local function` 误用 `end)` 收尾导致**连续多个版本全部功能实际未生效**（全案见参考卷附录 R6）；旧的 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助。
- **每次改完 .lua 必跑两条，两条都要 exit 0**：`node luacheck.js`（fengari 真实 Lua 解析，报错带行号，显示 **SYNTAX OK** 才算完）+ `node test_engine.js`（`test_stub.lua` 打桩 WoW API/UI mock + 5.1 垫片，加载整个 `EvalHelp.lua` 后跑 `test_assert.lua`，显示 **ALL TESTS PASS**）。
  fengari 已装在工作区 node_modules（npm 走代理 `127.0.0.1:10809`）。
- ★★★**测试纪律（用户 1.74.36-2 明确，2026-09-25 再次收紧）**：
  · 用户原话（1.74.36-2）：「不用测试，在碰到异常的时候再测试」「检查语法就可以，或者减少测试等待时间」。
  · ★★★用户原话（2026-09-25）：「**每次任务能否不要进行编译测试.等发现问题了再进行测试.现在每次测试太影响任务处理速度了**。」
  ⇒ **默认什么都不跑**（连 `luacheck.js` 也不必每次跑）：只在「改动跨文件 / 动的是**载入期**代码 / 我自己判断语法风险高」时跑一次 luacheck（<1 秒）。
  ⇒ **`test_engine.js`（整轮约 32 秒）一律等到「发现问题」再跑**：用户报障、我自己看到异常、或改动**直接动了接线/存档读写**。
  ⇒ **变异验证不再例行做**：只在**新增或改写一条判据**时做一次，且**能跑单项检查就别跑整套**（`node -e "require(./tests/checks/X.js)(process.cwd())"` 是秒级的）。
  ★代价要认：语法闸门照不到接线/渲染/存档这类**静默失效**（1.74.36-2 的真机 bug 就是 luacheck 全绿）；所以这几类改动收尾仍要补一次 test_engine。
  ★**但必须记住语法闸门照不到什么**：本次真机 bug（勾选框点了不勾）就是 **luacheck 全绿**、而模块↔宿主接线是坏的 ⇒ 凡是**动了模块/宿主的接线、UI 渲染、存档读写、路径**，收尾补跑一次 test_engine（或至少想想哪条断言会照到它）。
- ★★**判据必须同时看「退出码」与「输出文本」**：源码检查失败走 `process.exitCode = 1` 而**脚本照跑到底**，于是 `ALL TESTS PASS` **照样打印**——只看这句话会**漏报**。
  行为断言失败打的是 **`ASSERT FAIL`**，源码检查失败打的是 **`: FAIL`**（两者都要在输出里找）。
- **源码级检查**（`test_engine.js` 内，**改了对应区域就必须让它们继续通过**，共 20 道以上；逐条清单见参考卷附录 R13）：`WIN WIDTH` · `DECL ORDER`（顶层 local 声明早于使用）· **`ADDON DECL ORDER`**（同款覆盖 `addons/**/*.lua`）· `LAYOUT` · `VERSION`（源码 == toc）· `LANG KEY` · `WINDOW SIZE` · `COMMENT SWALLOW` · `ICON` · `EXAMPLES TOC` · `README TABLE` · `MILESTONE` 等。
  ★判据：**行为断言照不到 UI 接线（漏接不报错、只是显示不对）→ 必须用源码检查补位**；两类检查互补，缺一就有盲区。
- **断言组 1~200+**：覆盖解析/引擎/UI/布局/语言/标注层；**新增功能请顺带加组**（写在 `test_assert.lua` 末尾）。

### 2. ★★★任务/地图类问题 → 先读 UnrealQuest 对应流程代码（用户明确定，1.70.40）
- **用户原话**：「记住下次碰到任务地图相关的问题优先排查任务插件的对应流程代码」。
- **触发条件**：凡是涉及 **任务 / 地图 / 标注 / 世界地图 / 地图坐标 / 地图切换** 的问题——**第一个动作是去读 UnrealQuest 的对应流程代码**，不要先自己推断，也不要先往日志上加东西。
- **读哪里（按问题类型）**：定时/刷新与生命周期 → `Core/Driver.lua`（帧父级、OnUpdate 派发）· 当前看的是哪张图 → `Map/MapContext.lua`（`GetViewedZone`/`Inspect`）· 怎么画/何时重绘 → `Map/WorldMapPins.lua`（`ViewSignature`/`Refresh`）· **某 API 在本客户端能不能用** → `Compatibility/ClientAPI.lua`（**实测配方库**，含大量「本客户端不支持 X」明文）· 图标素材路径 → `Map/NpcPins.lua`（CATEGORIES + `IconForLocation`）。

- **怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库**信息密度最高**的内容。
- **停下信号**：当发现自己在「加日志 → 看日志 → 猜 → 再加日志」里转第二圈，**立刻停手去读对方代码**；**若读完仍未解决 → 转入下方铁律 4「取证协议」**。
- **代价**：两次绕远路（自造 `IsShown` 判地图可见性引入回归；tick 挂 `UIParent` 开图停摆）都是对方代码/注释里早已写明答案（全案见参考卷附录 R6）。

### 3. ★★★队伍/团队·血量/蓝量·buff/debuff 检测 → 先读 Heart（及它依赖的 C 库）（用户明确定，1.70.46）
- **用户原话**：「涉及到团队/队伍信息获取，血量，蓝量，buff/debuff 等检测 参考 `D:\game\TurtleWoW\Interface\AddOns\Heart` 插件的实现机制」。
- **触发条件**：凡涉及 **队伍/团队（party/raid）成员枚举 · 单位解析（名字 ↔ unit id）· 血量/蓝量/资源与百分比 · buff/debuff 检测（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——第一个动作是去读 Heart 与 C 的对应实现，不要自己从零推。
- ★**本机就是游戏主机**：**EmberVeil** 与 **TurtleWoW**（`D:\game\TurtleWoW`）都在本机，**可直接读对方源码、也可直接进游戏实测**——不存在「另一台机器」。
- **读哪里（按问题定位 · 一行一入口；★完整对照表见参考卷 R16）**：名字↔unit（聊天/战斗文字反查）→ `C\C_GetUnitID.lua`；`target`/`mouseover` 反查成员 → `C\C_AKA.lua`；buff/debuff 全量采集结构 → `C\C_SetPlayerData.lua`；采集驱动/多插件仲裁 → `C\C_UpdatePlayerData.lua`；「有没有某 buff」→ `C\C_UnitGotBuff.lua`/`C_UnitGotDebuff.lua`；**tooltip 读未暴露信息** → `C\C.xml` + `C_GetBuffData`/`C_GetDebuffData`/`C_GetSpellData`；团队主逻辑与血量优先级 → `Heart\Heart.lua`/`Heart_Helper.lua`；事件与跨插件 → `Heart_event/Hooks.lua` + `Plugins\*_Clicks.lua`；图腾与 tooltip 扫描跟踪 → `Heart_Totem.lua`。

- **★必抄的五个机制（「实现机制」的干货）**：
  1. **隐形 tooltip 当 API 用**（`C.xml`）：`<GameTooltip name="C_Tooltip" hidden="true" inherits="GameTooltipTemplate">` + `SetOwner(UIParent,"ANCHOR_NONE")` + `SetClampedToScreen(0)`。读取时**先清要用的行再 Set**（`C_TooltipTextLeft1:SetText()` 无参 = 清空），再 `SetUnitBuff/SetUnitDebuff/SetSpell/SetAction`，然后 `GetText()` 取行。
  2. **Tick 新鲜度**：每轮刷新把 `CurrentTick + 1`；查询侧要求 `entry.Tick == CurrentTick` 才算「现在有」——**从结构上杜绝把过期数据当成现行状态**。
  3. **贵调用只在「新出现」时做**：tooltip 调用很贵 → 只有**首次见到**该 buff 才去读；层数未变只刷新 Tick；**buff 与 debuff 槽都空就提前 return**。
  4. **名字 ↔ unit 解析与宠物命名约定**：宠物一律 `主人名-宠物名`；反查先走缓存再「慢查」，**缓存命中也要用 `UnitExists` + 名字复核**（unit id 会变）。
  5. **共用更新函数的单调用者仲裁**：`C_last_update_player_data_caller == this:GetName()`，**别人正在这一轮更新就直接 return**。
- **⚠️ 重要边界（别抄错东西）**：Heart/C 是 **TurtleWoW** 客户端插件，本项目跑在 **EmberVeil**；本机的 `C\C.lua` 已被用户改写成「治疗施法监控」并依赖 **SuperWoW**。→ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（本项目另有「EmberVeil 无 SuperWoW / 无 UnitCastingInfo」的记录）。

### 4. ★★★同一个问题**两三轮没解决** → 立刻转「操作日志 + 测试流程」，让用户配合取证（用户明确定，1.70.46）
- **用户原话**：「碰到两三轮提问都无法解决的，尽快用记录操作日志的方式 + 提供测试流程。我会配合你完成问题排查。」
- **触发条件（硬性计数，不许糊弄）**：**同一个现象**已经来回「改一版 → 让用户再试 → 还是不对」**第 2 轮结束时就要准备取证，第 3 轮必须转取证模式**。
- **转入取证模式 = 一次交付这三样（缺一不可）**：
  1. **操作日志（插桩点选在分叉处）**：记录「输入是什么 → 判据取值是什么 → 走了哪个分支 → 结果是什么」。★核心要求：日志必须能**区分「代码没跑」和「条件没满足」**（教训：心跳日志写在 `if not 开关 then return end` **之后**会整条链路静默）。用 `dsLogAlways` 这类**不受 trace 开关门控**的通道记用户点击与异常路径。
  2. **测试流程（编号、可照抄、含期望现象）**：从**干净状态**开始（`/reload` 或重进游戏），一步一件事，每步写「做什么 → 期望看到什么」。★**异常时也要让用户把剩下的步骤走完**（出错那一刻之后的行为同样是证据）。
  3. **回传物说明**：日志怎么拿（`/eh logdump` 打聊天框，或读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）+ **本客户端日志只在 `/reload`/退出时落盘**，要先 `/reload`。
- ★**能做成命令就别让用户手工复现**：给「一键探针」而不是「请你试十遍」——本项目已有范式：`/eh ds rnd`、`/eh ds hud`、`/eh ds trace`、`/eh go probe`。
- **取证模式的纪律**：**一次只验一个假设**（同时改多处 → 分不清是谁生效）；**不要只丢一句「把日志发我」**（必须带完整测试流程）；拿到日志先**对齐时间轴**（日志行自带相对时间戳 `"%.3f 消息"`，按时间戳重排看事件先后）；日志里出现**两句自相矛盾**的话 → 立刻怀疑**同一变量的两个绑定**。
  ★**用户配合是已知条件**：本机就是游戏主机，可直接 `/reload` 实测，**不要吝啬开口要日志**，也不要因为怕麻烦用户而继续盲改。

### 5. ★★★返工的功能涉及 API → 先核「官方 API / Lua 函数调用本身对不对」，再动逻辑（用户明确定）
- **用户原话**：「记住碰到返工的功能涉及到API 函数优先查看官方API LUA 函数调用是否正确」。
- **触发条件**：凡是**返工**（重做 / 改判据 / 换实现）且**涉及客户端 API 函数**（含**事件名、消息组、SendChatMessage、Protected 绕行**这类）的功能——**第一个动作是逐个核对每个 API 调用本身对不对**，不要先改逻辑、也不要先怀疑数据。
- **核对清单（逐条问）**：
  ① 这个函数 / 事件名在本客户端**真的存在吗**（`api_*.html` 全表 1370 条索引 · UnrealQuest `Compatibility/ClientAPI.lua` 的**实测配方库** · `emberveil.org/wiki/lua`）；
  ② **参数个数 / 顺序 / 类型**对不对（如 `SendChatMessage(文, 类型, 语言, 频道号)` 第 4 参是**频道号不是频道名**）；
  ③ **返回值 / 语义**对不对（如 `AddChatWindowMessages` 收的是**单个组名**，塞整串不是它的用法）；
  ④ 事件名 / 消息组名是不是**猜的**（本客户端通知事件名未必叫 `CHAT_MSG_*` → **不许猜**，现场用 `GetChatWindowMessages` / 探针实测）。
- **配套**：拿不准函数行为就**先写探针取证**用真机返回值定案，不凭印象；★这条与铁律 2/3（先读参考实现）是同族——**先在 API 这一层把「调用对不对」定死，再往逻辑/数据查**。
- **首案**：频道进出屏蔽返工三次，最后靠核 API + 探针才定案；那次「Channel is missing!」其实是客户端频道成员状态，不是插件调用写错（全案见参考卷附录 R7）。

## 二、频率防护总则（高频 API 调用场景）

- **原则**：凡是可能**高频触发**的 API 调用流程，设计阶段就必须考虑频率防护——**不要等被踢线/刷屏/翻倍后再补**。
- **判定方法**：设想最坏情况「一帧/一秒内会被触发多少次」；服务器写动作超过 **~1-2 次/s** 的一律限频，客户端事件**先假设会连发**。
- **三类范式（已有实现直接复用）**：
  1. **服务器写动作 → 限频队列**：`tbQ` + OnUpdate 滴出 `TB_RATE=0.3s`（教训：一帧 24 次 `UseContainerItem` 被服务器反滥用踢线）。配套：逐笔验证状态机 `tbPending`（槽位物品消失=成功 / 超时 2s=失败）、执行前二次校验防槽位变动、`MERCHANT_HIDE` 清待办防「卖变用」。
  2. **事件驱动 → 去抖窗口/节流**：`MERCHANT_SHOW` 本客户端连发两次（加 1.5s 去重窗 `tbMerchantLast`）；`BAG_UPDATE` 0.5s 节流。教训：事件驱动功能上线后**一律假设事件连发**，高频事件必去抖。
  3. **执行入口 → 去抖窗口**：`EVAL_GO` 入口 0.2s 窗口（`/run` 宏走 RunScript pending 队列，连按堆积、松手后陈旧调用冲刷 = 目标狂切）；窗口可配 `cfg.goDebounce` 0~1.0，附 `EVAL_GO_TRACE` 追踪器取证。
- ★★★**分享分片必须限频发送**：一帧连发 N 片会撞反刷屏限流被吞片 → 接收端**永远收不齐**（1.72.3 实案）。修法 = 第 1 片立即发，其余进 FIFO 由 OnUpdate 每 `SH_SEND_RATE=0.5s` 滴一片（**2 条/秒**），队列上限 `SH_MAX_QUEUE=200`；★**绝不在瞬间倾泻大量文字**。判据 = 断言组 106 + 变异 M7（退回一帧全发当场捕获）。（根因全案见参考卷附录 R8）
- **Protected 函数**（`SendChatMessage`/`SpellStopCasting` 等）绕行 = `RunScript` 聊天脚本（pending script 队列）——注意 **RunScript 本身也是队列**，连发聊天同样会被反滥用踢线，通知类输出也要入限频队列。

## 三、本客户端已实测的 UI 配方（UnrealQuest ClientAPI.lua 验证）

1. **拖动柄必须用 Button**（Frame 的 `OnDragStart` 不触发）；`SetFrameLevel(父+10)` 抬高（**用 strata 抬高是记录在案的失败做法**）；`EnableMouse` + `RegisterForClicks("LeftButtonUp")` + `RegisterForDrag("LeftButton")`；`StartMoving` 前 warm-up 两步（StartMoving→StopMovingOrSizing→StartMoving）。
2. **strata 层级陷阱**：配置窗是 DIALOG；其上方弹窗（技能编辑窗/导入导出窗）**必须同 DIALOG + `SetFrameLevel(90~100)`**，MEDIUM/HIGH 都会被 DIALOG 盖住；弹窗也要 `uiOffscreen` 越界回归。
3. **纯色纹理**只有 `Interface\Buttons\WHITE8X8` + `SetVertexColor` 可靠。
4. **无原生 Slider / 无下拉控件**：滑条 = 自制轨道 + 拇指；**下拉一律用全局件 `EVAL_DD_OPEN(锚点,选项表,回调)`**（UIParent+DIALOG+level250，多列 12 行/列，贴屏底自动上翻；宿主窗口 `OnHide` 里调 `EVAL_DD_HIDE()`）；插件内所有 `[<][>]` 循环器已全部改下拉。
5. **可见性契约**：显隐走**显式控件清单** Show/Hide，不靠父子传播（容器 `EnableMouse(false)`，交互件单独 `EnableMouse(true)`）。
6. **位置记忆**：`GetCenter`/`GetLeft` **含缩放**，存取要除 `GetEffectiveScale`；每个记忆位置的窗口都要 `uiOffscreen` 越界回归。
7. **禁用 `SetScale`**（点击框漂移），缩放 = 按 z 系数**几何重建**；字体链 `FZLBJW→FRIZQT→ARIALN` 全程 `pcall`。
8. **小地图按钮父级必须是 `UIParent`**（不能是 Minimap）；悬停用 `OnEnter`/`OnLeave` + GameTooltip，**不用 `SetHighlightTexture`**。


## 四、架构要点 + 编辑工具注意事项 + 当前功能地图

### 4.1 架构要点（改代码前先读这段）
- ★★★**工具类功能一律独立文件，`Toolbox.lua` 只做「开启/配置入口的引入」**（用户 1.74.34：「以上工具类的整理要加入项目记忆。尽量单独文件进行管理，在 Toolbox.lua 内只做开启/配置入口的引入」）：`./tools/<模块>.lua` 自包含（真值 + **自己的存档子树** + 界面控件 + 读值口 + 自己的**有界**计时器）；Toolbox 里**只允许**「模型行数据 `t = "mod", mod = "<名>", key = "<键>"`」与「入口按钮（点了就**调模块函数**）」；**不许**写整窗 UI / 事件帧 / 解析与状态机。
  机制 = **模块行注册表** `EVAL_TB_MOD_ROWS[mod]`（模块载入期自建自登记 ⇒ 与 toc 顺序无关；渲染段一个**通用分支**按名字取，没登记就**如实说一句**）；判据 = 通用 **`TB MOD ROW CHECK`**（模块行要有 `key` + 名字在 `tools/*.lua` 里有**同名登记** + 工具箱不许出现模块内部件）+ 各模块自查里那条**反向哨兵**。现有实例 = `LayerFix.lua` / `DragFrames.lua`（含那一行）；**尚未搬的清单与次序见参考卷 R15 ⑥h**。
- ★★★**工具模块的测试三件套也归模块自己管**（1.74.34 用户：「test 相关的搬迁到对应工具类子文件内自身管理」）：**读值口**在 `tools/<模块>.lua`（`EVAL_LF_TEST_*` 样式）· **断言组**在 `tests/tools/<模块>.lua` · **源码检查**在 `tests/checks/<模块>.js`（`module.exports = function (root) {…}`，harness 里一行 `require("./tests/checks/X.js")(__dirname);`）；`test_engine.js` **自动加载** `tests/tools/*.lua` 并与磁盘文件数**当场对账**；`tests/` **绝不进 toc / 发布清单**。判据 = `TOOL TEST FILES CHECK`；实例 = LayerFix（组 223）· DragFrames（18 组 + 9 道 DF 检查）· 地图工具（`tools/SimpleMap.lua`：「缩放大地图」行 = 模块行 + `[设置]` 多选下拉「GUI重开」，★默认关）；全案见 R15 ⑥j/⑥n。
- **状态表 `st`（`EVAL_HELP_STATE`）**：所有判定数据走 `UPDATE_STATE()` **一次刷新、各处只读**（Cat 思路）；含 `playerBuffs`/`targetDebuffs` 纹理集合、`castLog`（近 5 条带条件 trace）。
- **规则引擎**：规则 = `{ skill, enabled, groups }`；`groups` = 组内 `&`、组间 `|`；`EVAL_RULE_RUN` 顺序执行第一条全过的；兼容旧 `when={}` 格式；`condOne`/`groupsOK`/`EVAL_PARSE_CONDS`/`EVAL_COND_STR`/`EVAL_GROUP_STR` 是核心。
- **方案数据**：`cfg.war.profiles` + `activeProfile`；`EVAL_WAR_ENSURE_PROFILES` 做缺省迁移。
- **方案切换**：配置窗侧栏按钮 / 激活方案 `[<][>]` 选择器 / 战斗信息UI 方案行 / **Shift+按宏**（★Shift 已被切换占用，方案条件里用 Alt/Ctrl）。
- **文本格式**（导入导出 / `zs_wq.md`）：`# 方案: 名` + `- 技能 | 条件` 行；技能名前 `!` = 停用；解析容忍 md 杂物行。
- **函数作用域陷阱**：`warCfg`/`c()` 是配置段 local，战斗信息UI 段在其之前 → UI 段用 `uiWarCfg()`（直接走 `EVAL_HELP_CONFIG` 全局）；`wslots`/`WAR_SKILLS` 是战士段 local，配置段在其后可用。
- 受保护函数（`CastSpellByName` 等）插件**不能调**，施法一律 `UseAction(slot)` + `pcall`；谓词返回 `true/false/nil`，**绝不 `==1`**。
- **`EVAL_GO` 目标门槛教训（1.21.7）**：规则引擎化后**不能有**「无可攻击目标就 return」的全局前置——是否需目标交给**每条规则的条件**；否则纯自身 buff 方案（如只有战斗怒吼）永远执行不到。
- 本客户端**无 `UnitCastingInfo`**（打断条件做不了）、**无 SuperWoW**（无精确距离数值/挥击计时）。
- **射程 API**（wiki 确认）：`IsActionInRange(slot)`→`true`/`0`（超程）/`1`（自动攻击不测距）/`nil`；`ActionHasRange(slot)`；`CheckInteractDistance(unit,idx)` 不分档码数（`idx<4` 统一交互距离）。
- **物品 API**（wiki 已确认签名、实测待做）：`UseContainerItem(bag,slot)` 直接用/自动穿；`GetContainerItemInfo`→texture,count,locked,quality,readable；`GetContainerItemLink`；`GetContainerItemCooldown`；`GetItemInfo` 第 9 返回 = 纹理（只读本地缓存）。**无 `EquipItemByName`/`UseItemByName`**。★保护清单未文档化，`UseContainerItem` 是否被禁需实测——被禁会**静默失败**（`pcall` 兜住）。
- **`seBtn` 返回包裹表 `{btn,bg,text}` 不是按钮本体**：锚下拉/加 FontString 必须用 `.btn`（`mkSmall` 相反：直接返回 `b,bt`）——曾把包裹表当按钮用导致 `uiText` 炸 CreateFontString。
- **Lua local 作用域从声明语句【之后】开始**：RHS 里的闭包**捕获不到正在声明的 local 自己** → `local b = mk(..., function() ...引用b... end)` 的 `b` 是**全局 nil**！OnClick 要等赋值完再单独 `SetScript` 挂。
- **EditBox 疑似不渲染**（pcall 全「成功」但什么都不可见）→ **文本类 UI 一律给 FontString 保底**（IO 窗 `EVAL_HELP_IO_REFRESH` 预览区；单行输入弹窗用**回声行** `OnTextChanged` 镜像，1.17.0 `EVAL_HELP_RP_*` 范式）；EditBox 字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`。

### 4.2 编辑工具注意事项
- `run_code` 里**没有 `require`**；node 脚本一律写工作区 `.js` 文件再 `pwsh node xx.js`（内联 `-e` 引号会炸）；`pwsh` 要加 `2>&1 | Out-String` 否则 stderr 丢失。
- `edit` 工具：本会话内须先 `read` 过该文件；`old_string` 要精确（注意缩进空格数；批量失败先 `grep` 核对实际状态再重试）；**node 外部改过文件后必须重新 read 才能 edit**。
- 大块插入用「写块文件 + node 边界替换脚本」，小改动用 `edit` 工具逐处替换。
- 写文件若报 `file no longer exists`：换文件名重建（fs-observation 缓存）。
- ★★★**别在 Lua 源码里手写转义**（`"`/`\\` 极易写坏，且曾因此漏检到运行时才炸）：用 `string.char(34)`/`string.char(92)` 构造、抽小函数（`tbSafeName`）复用；★`luacheck.js` 是**逐个文件**检查（全案见参考卷附录 R10）。
- DSH 策略 danger-full-access、审批关闭 → **可直接写游戏 AddOns 目录**。
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（★**文件名是 `EvalHelp.lua` 不是 `EVAL_HELP.lua`**，旧文件是历史残留；小退/reload 时客户端写入）——**这也是现在读调试日志的地方**。

- ★★★**绝不用 PowerShell 读/写文本**（1.75.1 实测）：`Get-Content` 会把**无 BOM 的 UTF-8 读成 GBK**（满屏乱码，如 `# 鏇存柊鏃ュ織`）、`Set-Content`/`>` 重定向会把输出写成 **UTF-16LE + BOM**（`fffe` 开头；node 按 utf8 读全是乱码）。★含中文文件的往返**不可逆写坏**（曾把探针写成 103 处 U+FFFD）。⇒ 读/写/统计一律走 node（`fs.readFileSync(p,"utf8")`）或 `read`/`edit` 工具；要看 git 里某个版本就在 node 里 `execSync("git show rev:file")`，**绝不用** `git show rev:file > 文件`。
### 4.3 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行 + 方案技能行 + 条件 tooltip + 实时条件亮金）| `/eh st` 状态信息UI（状态变量 + 最近释放条件明细）。
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**七个 Tab**（Tab 宽 84/间距 88）：① 全局 ② 一键宏设置（方案栏 + 技能列表 + `[添加技能]` + `[导入导出]`）③ 工具箱（`Toolbox.lua`；含**猎人助手 → 一键喂食**等助手）④ **任务线 & 装备**（`DataSearch.lua`；1.75.x 由「数据检索」改名）⑤ **图标库**（`IconBrowser.lua`）⑥ **抓宠帮手**（`PetHelper.lua`+`PetData.lua`）⑦ **子插件**（可选子插件开关）。
- 技能编辑窗：点 `[编]` 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 `&`/`|`；条件类型分 5 组（`CTG_5` = **队友/团员状态**：队友血量%/队友蓝量%/队友debuff/队友缺buff + 团员同名四型）。
- **队友/团员怎么用（1.70.47）**：① 最省事 = **只配条件**（技能行加 `队友血量% <60` ⇒ 条件自己扫全队取血最低者、切目标、记 `st.allyUnit`，解魔法同理）；② 要自定义筛选 = 加一行 `选取目标:队伍成员`，筛选条件（`目标血量<N%`/`目标buff:名`）写在这**一行**上，按血量升序取第一个全过的；**规则按顺序执行** ⇒「选取器 → 治疗 → 驱散」一次按键依次生效。
- **定位：通用职业一键宏框架**（技能白名单仅作下拉置顶，任意技能可入方案/条件）；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（执行指定方案并且激活，绑多按键）；技能需拖上动作条，改动后 `/eh go rescan`；`/eh war` 是旧命令别名（改名 `/eh go`，handler 里仍兼容，`string.gsub(msg,"^war","go")`）。
- 调试：`/eh debug`（跳过原因 + 触发 trace）| `/eh go list` | `/eh logdump` 调试日志 | `/eh ds`、`/eh ds trace` 任务线 & 装备诊断。

## 五、关键判据汇总（按主题）

> ★本节是**判据总表**：每条 = 一句规则 + 追溯锚点（判据组号 / 源码检查名 / 关键标识符）。
> 各条踩坑经过与逐版本流水见 `CHANGELOG.md` 与参考卷（含附录 R）。

### 5.1 Lua / 解析

- ★★★**local 声明顺序 = 词法作用域，不是调用顺序**（1.74.29 用户：「频繁遇到这个坑就要记住」）：引用点写在 `local` 声明**之前** → 闭包里那个名字**绑成全局 nil**，运行时 `attempt to call global 'X' (a nil value)`（**不是**语法错误，luacheck 照样 SYNTAX OK）。
  【判据】① 插入新段前先问「它用到的东西声明在哪」；② 跨段共享件（`*Wm`/`*Big`/`*Ensure*`/`*Apply*`）**一律放在所有使用方之前**，或改成 `_G[...]` 直取；③ **闸门兜底 = `DECL ORDER CHECK`（主仓）+ `ADDON DECL ORDER CHECK`（扫 `addons/**/*.lua`）**——**检查存在 ≠ 覆盖到位**（旧检查曾漏扫独立插件目录）。
  ★★**该检查的已知盲区**：按**名字**比对，文件内还有**缩进的**同名 local（如函数体内的 `local function add`）就整名跳过（防误报）⇒ 顶层「先用后声明」会漏网 —— 「闸门绿 ≠ 这类没问题」，仍要用 `scan_dangling.js` + 真机红字反查。
  【纪律】① 别在函数体里用可能与别处同名的短名助手（`add`/`txt`/`row`），要么换名、要么定义在最前；② 同名收集器/助手一律**先声明再用**；③ 用法比对前**必须先剥字符串字面量**（首版误报过 `SetPoint(fs,"TOP",...)`）；④ 新增检查一律先做变异验证（临时造一个「先用后声明」的文件，确认真报 FAIL 再删）。连踩实例见参考卷附录 R2。
- ★★★**工具模块必须自带 `local function L(k)`（走全局 `EVAL_L`）**（1.74.35-3 实测抓到）：项目里 `L` **一律是文件局部**（9 处 `local function L`），全仓与游戏目录其它插件都**没有全局 `L`**；`tools/LayerFix.lua`/`DragFrames.lua`/`RareWatch.lua`/`SimpleMap.lua` 曾裸调 `L("TB_…")` ⇒ 在工具箱里被 `pcall(fn, r, it)` **吞掉**，表现是「按钮文案没设上 / 点击处理器没挂」而那一行看着完全正常（本项目最恨的静默族）。判据 = **`MODULE L SCOPE CHECK`**（`tools/*.lua` 只要调 `L(` 就必须自带局部 L 且走 `EVAL_L`）；写法照 `tools/ConsumableHelper.lua` 抄。
- ★★★**模块只准调「全局桥」，绝不许调宿主文件的 local**（1.74.36-2 真机 bug 的根因）：`tbCfg`（Toolbox 的 local）/`say`/`logLine`（Core 与 Toolbox 的 local）在模块里全是**全局 nil** ⇒ 「读永远 false、写一次不生效、播报静默消失」，而界面照样说成功（**本次症状 = 工具箱→缩放大地图的勾选框点了不勾**；`say` 那一族的死法是 DragFrames 80 处 / RareWatch 30 处的「如实播报」全哑）。⇒ 跨文件一律走 `EVAL_*` 全局桥（`EVAL_TB_CFG`/`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`），或在模块里**自带同名 local**；判据 = **`MODULE HOST LOCAL CHECK`**（把宿主 367 个 local 名逐个比对模块里的调用）。
- ★★★**「关掉零动作」= 总开关必须闸在**任何探测/读写之前**（1.75.7 用户排查：「缩放大地图未开启时，会不会还在监听探索层的缩放操作」）**：
  修前实测（关闭状态 + 点 10 拍 tick）：读了 10 次 `IsShown` + 10 次 `GetEffectiveScale`，还把叠加层几何**折了 8 次**
  （355/-320/215×215 → ×0.7 的 248.5/-224/150.5×150.5）、记下 2 条原值 —— **不只是监听，是在动手**。
  根因两条（这类事故的通式）：① **tick 是载入期无条件建的** ⇒ 与开关无关地一直跑；② 子开关（`mapFit`，**nil = 默认开**）
  被当成了判据，真正的总开关压根没参与。
  【判据】① 闸门放在**第一次读/写之前**，且闸门块要**清「已应用」标记 + `return`**；
  ② 「关掉时把改过的几何还回去」必须**当场做**（寄托在常驻 tick 上 = 关掉还在跑的来源）；
  ③ 闸门 = **组 230**（关闭：读 0 次 / 几何 0 次 / 关闭即还原；开启：照常监听折算 —— 反向哨兵不许把功能关死）
  ＋ **`SM OFF SILENT CHECK`**（源码级钉「闸门在探测之前 + 有 return + 清 applied + 关闭路径真的调 `pcall(smFitRestore…`」；变异 5/5）。
- ★★★**「探索层/叠加层纹理」折算前必须先探测「客户端自己会不会跟随缩放」**（1.75.9 用户实测：**两种情形都会把那批纹理缩两遍** ——
  ① 载入时未开、点开启；② 开着载入、关掉再开；「WorldMapDetailFrame 下 **12 号之后**的纹理」= `smFitTargets()` 那批）：
  真机证据（用户 DebugBox 截图）：`WorldMapOverlay1 = 105×105／锚 174,-157` = 我们写的 `150.5／248.5` **再 ×0.7**
  （`WorldMapDetailFrame 701×468` = `1002×668×0.7` 同理）⇒ **本客户端几何读回含父帧缩放，且客户端自己会级联**。
  【判据】① 动手前先**只读探测**（`smFitDetect`：外框缩放在 `1→0.7` 走一档，看屏幕几何跟不跟）；
  ② 只有结论 `true`（需要我们折）才折算，**`nil`/`false` 一律一个几何都不碰**；③ 原值**只在自然档抓一次**
  （`smFitCapture` 临时 `SetScale 1` 读）；**`smFitApply` 里绝不记原值**、**`smFitRestore` 绝不清 `SMFIT.rec`**；
  ④ 记录键用**纹理名**（枚举序号会随换区重建漂移 ⇒ 还原写到别的纹理上）；⑤ `featApplyScale` **读回自证**（同档不重写）；
  ⑥ **开启/关闭都要收钩子**（`featTeardown`：坐标行 OnUpdate / 拖拽柄 / `UISpecialFrames` 里我们插的那项；滚轮与坐标行各一道 enabled 门）。
  闸门 = **组 232** ＋ **`SM FIT CASCADE CHECK`**（变异 10/10，含「检查只匹配到一处门」那次当场漏网的补洞）；全案见参考卷 **R20**。
  · ★同一案附带修掉的一颗雷：模块在**文件执行期**缓存了 `EVAL_HELP_CONFIG.simpleMapCfg`（本项目已定案：那时它还是**空表**）
    ⇒ 设置与「原值记录」**一个都没落盘**（真机证据：存档里 `tb.simpleMap = true` 在、`simpleMapCfg` **整块不存在**）⇒ 已改**懒代理**。
- 多字节字符禁入 Lua `[...]`（按字节匹配）、`|` 非交替：`[:：]` 吃「：」首字节 → 目标/物品/宠物/姿态/条件解析全线静默失效；`colonNorm()` 入口归一。★`string.sub` 同样按**字节**取（`"go 喂食"`=9 字节 → 前缀判据写 `1,5` 恒不等 = 命令静默失效；1.74.5 实踩）。
- 模式里 `%` 是转义符：`%.`字面点、`%%`字面百分号（写错则分支永死）；plain 模式找 `%` 写 `"%"`，`"%%"` 找不到。
- 方括号组成对解析（`(.-)` 吞 `[职业:术士][队伍:2]`）→ 用 `[^%]]-`、半/全角分匹配；空集 ≠ 没写。
- 主 chunk ≤200 局部队变量、`do...end` 不开函数作用域；`ipairs` 遇 nil 即停。
- `cond and f() or fallback` 在 `f()` 返 false 时恒取 fallback → 分两步 `local on=true; if type(f)=="function" then on = f() and true or false end`（1.73.15）。
- 空串是真值（`""` 也算有键）→「键存在」≠「有内容」；`string.len` 是字节数 → 宽度按字符估。

- ★★★**OnUpdate 回调「一个参数都不传」**（1.74.31 真机事故：写成 `function(f) pcall(f.SetScript, f, …)` ⇒ 本客户端不传参 ⇒ `f=nil` ⇒ 红字）：**回调一律零形参**，dt **只能**从全局 `arg1` 取。判据 = **`ONUPDATE ARG CHECK`**（匿名回调非空形参 / **直接注册**的具名回调其定义有形参 ⇒ FAIL）；
  ★★**该检查有漏网**：间接注册（`pcall(f.SetScript, f, "OnUpdate", h)`）正则抓不到 ⇒ 「闸门绿」不等于这类没问题（`dfOpenOnUpdate(dt)`/`dfAttrPOnUpdate(dt)` 就是靠这条漏网活着的「步进体」，它们由读值口直接驱动，属既有范式）。
  ★★★**测试要注入 dt 也必须走真机通道**：桩件 **`EVAL_TEST_FIRE_UPDATE(frame, dt)`**（设 `arg1` → **零参数**点火 → 还原；返回「当时真点到了脚本」—— 组 204/223 的「跑满次数就摘钩」靠它）。★`pcall(f, dt)` 对零形参回调**等于什么都没传**，dt 静默退回 0.05（1.75.1 就是它把组 204 点红：点火 7 次而期望 5 次）。
### 5.2 静默失败族（数据 / 序列化 / 开关）

- ★★★分享「自我回声」判据**必须锚在「发送者是我」**（`shIsSelfEcho(sender)`，剥色码/后缀），**不能锚在「内容像我」**（会把「别人发的同款方案」误杀吞掉不弹窗）；组 82 ①/①b/③ + 变异 M569/M570。★「按日志判没发生」≠ 真没发生：**日志是环缓冲会覆盖**。全案见 R1。
- ★★分享分片取证探针：`SH.dbgChunks`（环形 8 条）在 `shOnMsg` 各分叉点记原文+走到哪一步，`/eh go 分享事件` ⑤ 摊开。★本客户端 `IsEventRegistered` 返 **`1` 不是 `true`**，判据写 `(r == true or r == 1)`。全案见 R1。

- 具名帧顶掉同名全局函数 → `type(X)=="function"` 不成立 → 命令静默失效；桩须把具名帧挂全局；`FRAME NAME CLASH CHECK`；组 54。
- 分享接收（1.72.3）：>2s 未收齐如实提醒但不删缓冲；>60s 才丢；只认 `[EHPF#<id> i/n]<hex>`；组 106/107。
- 「查不到」≠「没有」：查不到必须如实报错，否则 `cnt=0` → 「否/无」成立 → 规则无限重放刷屏。
- 静默丢弃 = 那行变无条件施法 → 写几条成员条件、解析后就必须几条；数据类错误全静默。
- 导出形态与解析侧必须成对验（读不回 = 导入即丢条件）；「有过滤」≠「过滤得住」（`itemOf(n)` 只认「物品:名」）。
- ★★★**聊天输出总闸门 = 配置项「调试日志」(`cfg.log.on`)，`say`/`EVAL_SAY` 跟它联动**（用户 1.75.8：「say 函数能否根据全局配置->调试日志状态开关要不要打印」＋「记录调试日志重命名->调试日志」）：
  关掉 ⇒ **整个插件一个字都不往聊天框刷**（模块自带的 say 全部委托 `EVAL_SAY` ⇒ 一处门控全生效）；★**同一判据也是数据层闸门**（`logLine` 一个字都不记）。
  ★**闸门必须放在第一次输出之前**（与 §5.1「关掉零动作」同族）；★**关掉时必须留一条看得见的回头路** ——
  日志开关**自己**的确认行 + 「引擎未加载完整」兜底走 **`EVAL_SAY_FORCE`**（常开），否则用户再也看不到「怎么开回来」（静默族）。
  · `cfg.wdebug`（配置项**「方案技能日志」**）＝更细的一层（Engine 里那批决策原因同步刷屏），**不是**总闸门；两条分工仍在，但总闸门现在**同时管「说不说话」**。
  · 自建打印口的模块（`tools/SimpleMap.lua` 的 `P`）读 **`EVAL_CHAT_ON()`**；其余模块的 say 早已「优先 EVAL_SAY」⇒ 委托即门控（有意例外：子插件 `EH_DebugBox`）。
  · 判据 = **组 231** ＋ **`CHAT GATE CHECK`**（变异 6/6；全案见参考卷 **R19**）。
- 判据表照客户端真实文案抄（「进入频道。」vs「加入」）；「尝试过」≠「挂上了」→ 载入即挂必须失败重试。
- 按序号做键的表删中间项要整体左移（1.73.25）：`bindKeys`/`bindSlots` 解绑 + idx 之后左移一格 + `SaveBindings`；组 131。
- function 不是 table（身份判定用 `cur == TB.chanWrapper`）；标记只加显示串（`[物]` 只改显示、取值裸名）；「还原/撤回」≠ 回退到有 bug 状态。
- 借别人的 UI 对象 = 静默破坏界面（1.73.14）：`local WTT = GameTooltip` 读数会清空玩家 tooltip → 自建 `EVAL_HELP_WTT`、读自家 `TextLeft1`、守卫 `EVAL_WTT_MAY_READ_PURE`；`WTT ISOLATION CHECK`；组 126。
- 「写成功」≠「写进去生效」（1.73.12）：`frame.AddMessage=wrapper` 写入被吞 → 必须写完读回确认（`_G.ChatFrame_OnEvent ~= wrapper`）+ 改挂普通全局函数入口（新文本回写全局 `arg1`）+ 非聊天事件放行；`CHAT COLOR WIRING CHECK`；组 123/组 124⑧。
- ★★★**改属性前必须先把「原始值」读下来**（1.74.31 组 206 当场抓到）：宽/高这类**没有「系统默认值」可退回**的属性，重置只能靠「第一次改之前记下的原值」（`rec.ow/oh`）⇒ 在 `SetWidth` **之后**才读，记下的是刚设进去的新值，重置就「还原成用户刚设的值」= 等于没还原（且看起来一切正常）。
  【判据】读原值 → 写新值 → 读回自证，**顺序不许换**；原值缺失时**如实说「无法还原」并保留字段**（绝不拿当前值冒充）；组 206 的 3 个变异全部被捕获。
- 深入 API：`GetChatWindowMessages`/`Remove`/`AddChatWindowMessages` = 官方「某类消息不显示」开关（组名不许猜）。
- 分享行形态（1.73.43）：只有「一段色码 + 链接」能画 ⇒ 色码打头 + 带链接 + 每条一段 8 位码 + 间隔 ≥1s；色清单从 `SH_CHUNK_COLOR`/`SH_SEAL_TIERS`/`SH_TITLE_COLORS` 现取；组 144/158/159。
- ★1.73.24~41 弹窗/菜单/滚动条细则见 R11。


### 5.3 测试与断言
- ★桩默认值也属桩（真帧默认显示、桩 `shown=false` ⇒「没 Hide 却断言 `IsShown()==false`」恒真）；隐式前置改显式建立（`pcall(root.Show,root)`）；桩要记每状态。组 110①⑧⑨、组 64/93。
  ★★**桩的帧 mock 对未知键返回函数**（truthy）⇒ 判「是不是我们的控件」必须写 `字段 == true` / `rawget`（真值判断会把**每条普通柄**误判成图标；1.74.33 实测：普通柄「拖完该弹属性窗」那条断言当场变红）。
- 测试够不着生产 local ⇒ 加钩子走真实 OnEnter；桩对无效调用要如实无效（`castStoppedDirect`/`castStopped`）、模拟 `SetText` 再触发 `OnTextChanged`；tooltip 桩＝另建对象＋真 GameTooltip 记账＋普通 table。
- 断言打真实调用点/入口＋反向哨兵；模块级状态入 `EVAL_TB_TEST_RESET_TIMERS`（文件末尾，否则 `DECL ORDER CHECK` 抓 FAIL）；「没执行」≠「没入队」⇒`EVAL_TB_TEST_QUEUED_QUESTS()`；写死布局常量＝测自己⇒`EVAL_TEST_CFG_LAYOUT()`。
- 期望值不许用语言包、不许同源自比（`EVAL_SHARE_SEAL_TIER(13).name` vs `EVAL_LOCALES[lg]`）⇒字面/绝对值夹具；颜色断言三通道一起比；弱判据两例：页码夹取替断言、递归被 `pcall` 吞⇒让桩计数；夹具走 `EVAL_PROFILE_FROM_TEXT`。
- 变异：冗余防护整组拆；锚点唯一定位（整行/命中==1/摘 CR/语法合法）；先过 luacheck；还原用运行前内存原文（绝不 `git show HEAD:<file>`）；判捕获看退出码＋文本（`: FAIL`/`ASSERT FAIL`；`LANG KEY CHECK`）；新 CHECK 锚在外层 `})();` 后。
- ★★★**「测试文件存在但没人跑」是头号静默失效**（1.74.34）：harness 漏加载一个 `tests/tools/*.lua` ⇒ 整组断言消失、套件照样 `ALL TESTS PASS`；源码检查漏 require 同理。⇒ **跑到底握手**（末行 `EVAL_TEST_MOD_DONE("模块")`）+ **文件数对账** + **`TOOL TEST FILES CHECK`**（含「每个 `tests/checks/*.js` 都被 require+调用」「`tests/` 不进 toc」）+ **`DF GROUP ROSTER CHECK`**（组号集合 + 升序 + 每组都有真 `eq(` 与 PASS 收尾行 —— 「整组被删/被掏空」只有它抓得住）钉住；变异 `tmp/mut_tests.js` 10/10。
- ★★★**检查文件（`tests/checks/*.js`）的导出函数里不许有顶层 `return`**（1.74.36 实测抓到）：写成 `return (function () {…})();` 之后，**再追加的检查全是死代码** —— 文件里看得到、日志里**从不打印**（`LF ROW SUMMARY CHECK` 就这么被静默吞了一整轮）。⇒ 要早退就写进 IIFE 里；判据 = `TOOL TEST FILES CHECK` 的「顶层 return」一条。
- ★★★**测试里的「跳过分支」= 静默逃生口**（1.74.36-2 实测）：组 224 写过 `type(tbCfg)=="function" and tbCfg() or nil` 再 `if tb0 then … else eq(true,true,"（无 tbCfg，跳过）") end` —— 条件**永远 false** ⇒ 那条真值往返断言在真机全坏时照样「绿」。⇒ 前置一律**断言存在**（`eq(type(EVAL_TB_CFG)=="function", true, …)`），**不许**用 `if 条件 then 断言 else 跳过 end`。
- ★★★**读值口要按「稳定键」找条目，不许缓存「条目对象」**（1.74.31 实测栽过）：列表的条目表**每次重扫整体重建**⇒ 测试缓存的 `e = entryOf(obj)` 在 `/edb scan` 后**全部失效**，采到假数字且不报错。
  【判据】① 查找一律按**帧对象**而不是条目表；② 找行 = 找「行里的条目指向哪个帧」（`rawget(row,"entry").f == obj`）；③ 跨重扫的采集要在**同一代**重新取；④ 测试脚本 restore **不许删自己的备份**（全部变异跑完才删）。

- ★★★**harness 载入清单里 `test_assert.lua` 必须排在所有 `tools/*.lua` 之后**（1.75.1 合并两支时踩到）：工具模块在**载入期**自登记 `EVAL_TB_MOD_ROWS`，而 `test_assert.lua` 的工具箱断言（组 200）走**真实渲染路径**去取它 ⇒ 顺序反了就出现「组 200 `got=false want=true` 而模块完全正常」（toc 无此问题，只有 harness 清单会踩）。判据 = **`TEST LOAD ORDER CHECK`**（含「含 test_stub.lua 的清单必须唯一」的锚点自检）。
  ★★**同一机制的第二个后果**：`test_assert.lua` 里**任何一条**断言抛错，harness 立刻 `process.exit(1)` ⇒ 排在它后面的 **`tests/tools/*.lua` 整批不跑**（表现为「修好一个红点就冒出下一批红点」——那不是新 bug，是被挡住的老红点）。
### 5.4 UI 与布局
- ★★★标题栏（两窗同一实现）＝玩家名→头衔→品阶徽标→方案名＋右侧两开关；两窗各自 BUILD＋tick 刷（只开状态UI 也要跟·组 168⑤）；头衔取 `EVAL_TITLE_CURRENT()`；色码→RGB `EVAL_COLOR_RGB`（8 位）；CHECK `UI TITLE*` 四道；组 162/163/164/166/168。
- ★★品阶唯一源 `SH_SEAL_TIERS`：≤11 普通/12-23 稀有/24-35 珍稀/36-49 绝版/**≥50 神级**；色走 `SH_SEAL_TIERS[].color`（**神级 = 亮蓝 |cff00bfff**）；`SHARE PALETTE CHECK` 守色码不重复；组 143/146/147/195/196。
- ★★★**评分口径（1.74.19 重做）**：`EVAL_PROFILE_SCORE` = Σ(每条技能)[ 有条件 ? 1+Σ条件权重 : 0 ]；**空技能 0 分**；条件按类加权 **自身/技能 1 · 目标/光环 2 · 队伍/候选 3**（`SE_TYPE_GROUPS` 的 `w`/`cov` 是**唯一来源**）；单条上限 12 分；同一行里**完全一样**的条件只算一次；★`EVAL_NO_SLOT_OK` 的技能无条件**保留 1 分**。
- ★★★**覆盖封顶**：覆盖 1/2/3 个大类分别封顶 **23/35/49**（值从 `SH_SEAL_TIERS[n+1].max` **现算**），**≥4 类才不封顶** ⇒ 神级必须跨类写；★带方案表的调用点一律走单入口 `EVAL_PROFILE_TIER(p)`（**coverage 传 nil = 不封顶**）；`COVERAGE CAP WIRING CHECK` 守「没人再写 `EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p))`」。
- ★★★**头衔晋升（1.74.19）**：`SH_TITLE_REQ = { 1, 2, 3, 3, 2 }`（稀有+≥2 · 珍稀+≥3 · 绝版+≥3 · 神级≥2）＋**逐级满足**；★命令/闸门/样例的分数**一律现算**（`EVAL_SEAL_GOD_SCORE()` / `EVAL_SEAL_TIER_SAMPLE(i)`），不写死（旧口径见 R3）。
- ★★★**配置分角色存（1.74.20）**：角色级存档 `EVAL_HELP_CHAR`（toc 有 `## SavedVariablesPerCharacter`）；**角色键唯一来源 = `Toolbox.lua` 的 `TB_CHAR_KEYS`**；`tbCfg()` 是**路由代理**（角色键落角色表、其余落账号表）⇒ 上百处 `tb.xxx` 一行未改；★★**代理 `__index` 绝不能写 `at and at[k] or nil`**（`false or nil` 仍是 nil ⇒ 用户关掉的开关自己又开了；组 79 抓到）；判据 `SAVEDVARS SPLIT CHECK` ＋组 197（细节见参考卷）。
- ★★★**图层树的层级只能来自「扫描时写下的层号」，不许数路径里的 `/`**（1.74.31）：`scanTree` 写层号进节点 ⇒ 缩进与「层深」过滤**同一口径**；折叠 `ui.treeCollapsed[路径]` 落存档；层深唯一写入点 `uiDepthApply`（`0` = 一个标记都不清）。判据 `DBX TREE WIRING CHECK` ＋ **组 205**（详见 R15 ④）。
- ★★★**「算出来却写进一个从没被创建过的控件」= 静默死代码**（1.74.31 实测）：`uiRefresh` 一直算状态行却写进从未创建的 `ui.pageLbl` ⇒ 永远空写，用户看不到「为什么列表变少了」。
  【纪律】① 写完 UI 文案要问「**这个控件存在吗**」——`if ui.X then` 守卫会让「控件名写错」与「条件不满足」长得一模一样；② 这类坑行为断言照不到（有守卫就不报错）⇒ 用源码检查钉住（`ui.pageLbl` 出现即 FAIL + `ui.statLbl`/`ui.filterLbl` 必须各有**创建点**）；③ 通用形态 = **凡是被写入的 UI 句柄，都必须有一个赋值点**。
- ★`COND WEIGHT CHECK`（条件权重漏组）· `/eh go` 别名不许两家共用（`GO ALIAS UNIQUE CHECK` 守，`go icons` 曾撞车）；品阶显示现算等细则见 R15 ⑦⑧。
- ★★★**滚动模式唯一标准（连续窗口）**（用户 1.74.30 定）：范式 = `PetHelper.lua` 约 566~595。① `off` = **行偏移**、双侧夹 `0..max(0, n-cap)`；② 滚轮**逐行**（≠ 页容量）；③ 滚轮**链式接管**（存原脚本，本 Tab 才消费）；④ 按钮一屏但**夹到 `maxOff`**；⑤ 容量 `cap` **恒定**（绝不因「组不拆」收缩）；⑥ 计数器常显；⑦ 切分优先组边界。**禁止**：整页跳 / 变长页 / 覆盖式接管滚轮。判据 = 组 120 + **组 201**；读值口 `EVAL_TB_TEST_WHEEL/WHEEL_PREV/LAYOUT`（**不许复刻映射逻辑**）。
- ★**滚动/翻页/分页三段布局细则**（计数器 ←8px→ 按钮组 ←10px→ 关闭 · 几何唯一源 `EVAL_HELP_CFG_BOTTOM()` · 组 92/118）→ 参考卷 R15 ⑥l。
- ★★★滚轮方向唯一源 `EVAL_WHEEL_DIR(a,b)`（归一 ±1）；6 处全走它；`WHEEL DIRECTION CHECK`（禁位移与方向同号）＋组 115；★断言把方向写反⇒反向 bug 被「验证」通过。
- ★★★数据刷新不许改可见性：`EVAL_WAR_TAB_REFRESH()` 又被开配置窗与 `EVAL_PM_APPLY` 调用⇒可见性只由 Tab 切换负责（`EVAL_HELP_CFG_SETTAB` 的清单）；数据照旧每次刷；组 165＋`EVAL_TEST_WAR_ROWS()`。
- ★**视图切换 / 入口控件 / 分列切点 / 工具箱两列 / 弹窗高度自适应 / 职业着色 / 聊天窗名字着色（组 129b/161）/ 主动查询四闸门 等细则 → 参考卷 R12/R15**。
- ★★★**索引「任意全局」/ 走父子链的扫描，动手前先看参考卷 R15 ⑥k**（1.74.32 真机栽过一整轮）：① 索引前先过守卫（不可索引的 userdata 会抛错、**打断整个探针**；只收 `GetObjectType()` 报 Frame 的）；② **匿名窗口 `_G` 扫描永远看不到** ⇒ 只能靠 `GetChildren()` 父子链 + **具名子件当指纹**；③ 真机存档**带 BOM**、`a and f()` **只保留第一个返回值**、桩里 `unpack` 在 fengari **不存在** —— 都表现为「静默取不到值」。判据 = `DF GLOBAL SCAN GUARD CHECK` + 组 209/211/213。
- ★★**判定「别人的帧」时用对象身份、别用名字**（1.74.32 实测栽过）：`GetName()` 可能返回 nil（桩里 `UIParent` 就是匿名帧）⇒ 按父级**名字**筛会一条都匹配不上；判据 = 比对象（`p == rawget(_G,"UIParent")`）；组 209⑤ + `DF BARS WIRING CHECK`。★同族哨兵做法见参考卷 R15 ⑤。
- ★★★**框拖拽（`tools/DragFrames.lua`）/ 图层工具（`tools/LayerFix.lua`）判据总表**（★**原文已整批迁参考卷 §十六**，要查踩坑经过/完整写法去那里）：
  ① **图层选择**名单：真值 `dragFrames.pick[名]=true`（**表不存在 = 全选**）；唯一写入口 `EVAL_DF_PICK_SET`（★**首写先物化全选快照**，否则一次取消勾选 = 其余几十层静默全关）；菜单唯一来源 `EVAL_DF_PICK_MENU`；判据 = 组 214 + `DF PICK WIRING CHECK`。
  ② **窗口图标 / 头部拖拽带**：图标 = **346 号宏图标**（按号现取、取不到退回「配」）；**左键只拖窗口、属性窗挂右键**；分工收在 `dfBindDragButton`；判据 = 组 212/215 + `DF ICON ART CHECK`。
  ③ **位移一律「按屏幕算 + 量回自证」**：`base.l/base.b` = 拖前**实测屏幕位置**；落锚唯一入口 `dfPlaceFrom`（首猜按 `GetEffectiveScale` 折算 → **量回** → **手量折算**修正）；★必须**解仿射**；判据 = 组 217①~⑦。
  ④ ★★★**宽/高只对「聊天窗」开放 + 持久化**（1.75.1 用户第三次改口径：「工具箱->图层拖拽->只有针对聊天窗才支持长宽设置.并且持久化」；1.74.33 的「所有窗口都不给」已收窄）：**唯一真值 = `dfSizeOK(name)`**（`^ChatFrame%d+$`，该正则**只许出现一次**）⇒ 目标表项 `noSize` 由它现算；读它三处 = 属性弹窗（聊天窗**建并显示**宽/高两行 + 窗高 `DF_POP_H_SIZE`；其余 **Hide** 两行 + 窗高收回 —— **不是灰掉**）· `dfAttrsApply` 的 **`allowSize` 门**（没给 tgt 按**不允许**处理）· 启动清理（**只清 `noSize == true` 的**目标并还原 `ow/oh`，没原值**不去猜**；**聊天窗的 w/h 一个字段都不动**）。★保存顺序铁律：**先抓原值（改动前实测尺寸）→ 再写新值**，反了就等于没还原。位置仍是 X/Y 两行绝对屏幕坐标走 `dfPlaceFrom` + A 链式 `OnShow` + C 有界短复查。判据 = 组 206 / 组 208④⑥ / 组 220①~④ / 组 222 + `DF OPEN HOOK CHECK`。
  ⑤ **「图层特殊处理」**：规范表 `LF_FIXES`；真值 = `layerFix.fix[key]`（★**表不存在 = 一条都不选**，与 pick「不存在=全选」**相反**）；三处执行（勾选当场 / 载入期 / 有界复查到点摘脚本）；**层不在或对象数不够 ⇒ 一个都不动 + 如实播报**；判据 = 组 223 + `LAYER FIX WIRING CHECK` / `TB MOD ROW CHECK`。
  ⑥ **工具箱模块行的配置项只在 `[设置]` 的悬停说明里显示**（行上不许重复）：模块行必须 `r.extra:Hide()`；判据 = **`TB MOD ROW CHECK ④`**（`tools/*.lua` 里出现 `extra:SetText` 即 FAIL）。
  ⑦ ★**「柄」按池位号复用** ⇒ 验「某目标有没有柄」要按**目标名**查当前**显示中**的那条；★**同一带上的两个控件 = 遮挡（断言盲区）**。
- ★★★队伍菜单三条条件（1.74.1/1.74.4 定案）：**邀请队伍** = 对方不在我队伍/团队里 且（我不在队伍 或 我是队长）· **踢出队伍** = 我是队长 且 被右键的是队友 · **离开队伍** = 在队伍内显示（`LeaveParty()`）；判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`（助理踢人无 `IsRaidAssistant` 可判 → 如实接受边界）；成员判定 `EVAL_TB_NAME_INMYGROUP`（party 只扫 1..4）。组 130⑥e/⑥e3 + 组 173；变异 M564~M568；定案经过见参考卷附录 R5。
- ★★★技能格按键分派（1.74.2 用户定）：战斗信息UI 技能小图标 **左键 = 切换启用/停用**（写 `r.enabled` **配置真值** + 如实播报 + 双刷新）· **右键 = 技能配置弹窗**（开被点那格、不动状态）；格子必须注册 `RightButtonUp`（光注册左键 = 右键永远到不了分派代码）；读值口 `EVAL_TEST_UI_CLICK_CELL`/`EVAL_TEST_SE_SHOWN`；`UI CELL MOUSE CHECK`；组 174。
- ★布局总纪律：需求验性质不验数字；同一行中线对齐；中文宽度按字符数估；布局常量单一源（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。


### 5.5 API 与客户端事实
- SpellStopCasting()：读条/自动射击/魔杖三类全覆；Protected→须 RunScript；「进度条没了」≠取消。
- AttackTarget()=Toggles 须 IsCurrentAction(攻击格)；Movement 仅 FollowByName/FollowUnit 非 Protected（MoveForwardStart/Stop、TurnLeftStart 是）；FollowByName 空名=当前目标、只搜已知玩家、无返回值、不走 RunScript。
- GetRaidRosterInfo(i) 九返回；越界/非团队只回 nil。
- 1370 API 无 aura 专用函数；GetPlayerBuff(i,f)=增益条 0 基下标；无文件读取 API ⇒ 载入唯一形式 = 列进 `.toc`；★`LoadAddOn` 是 **Protected** ⇒ 文件级懒加载不可能，只能「toc 预载 + 载入期零副作用 + 首用才建帧」（范式 `tools/HunterHelper.lua`）。
- GetQuestReward 会再触发 QUEST_COMPLETE→须三层防护（同名去重/领取窗口闸门/全局频率上限）；UnitDebuff 第 3 返回=dispel token；UnitMana=主能量且有显示缩放（怒气÷10、幸福÷1000）→判蓝量前先 UnitPowerType(unit)==0。
- 施法 API 全 Protected（CastSpellByName 仅 onSelf/CastSpell/SpellTargetUnit/SpellStopTargeting/SpellStopCasting）；TargetUnit 非 Protected=唯一路径（切目标→UseAction(slot)→还原）；Targetting 另有 TargetLastTarget/ClearTarget/TargetByName/TargetNearestPartyMember。
- ★★★`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` 是**独立事件**（队长/团长发言）：接收帧**必须也注册**这两个——只注册 `CHAT_MSG_PARTY`/`RAID` 时队长一分享**一片都进不来**（接收端静默）；来源判据=触发事件名；发送侧只留 公会/队伍/说；自查 `/eh go 分享事件`；`SHARE RECV EVENTS CHECK`；组 175。
- 纹理路径=/Game/Interface/Icons/<名>_TEX，写错显 ?；GetNumMacroIcons/GetMacroIconInfo=唯一合法路径入口（1018 条 → doc/图标路径清单.txt）；PET ICON CHECK 校验真存在。
- IconSem.lua：基础名须剥 _TEX（组 117①b）；过滤=四命中+分组叠加；纹理字面量须在白名单（PET ICON CHECK）；两反斜杠须按两反斜杠匹配（组 112）。
- api_*.html=1370 条索引；无：PlaySoundFile（只有 `PlaySound`）/hooksecurefunc/**`Frame:HookScript`**/UIDropDownMenu_GetSelectedID（`GetDifficultyColor` 有垫片）；有：GuildRoster/Who/Friend/NumGuildMembers/NumWhoResults/NumFriends/GuildControlGetNumRanks/GetRealZoneText/RemoveChatWindowMessages/`GameTooltip:SetMinimumWidth`。★`GetWidth`/`GetHeight` **含缩放**（384×512+0.7 ⇒ 268.8×358.4）⇒ 与未缩放配置值直接比会假报不符（R15 ⑥d）。
- ★★★**帧名未知的层（候选名解析 + 探针）与「按需出现」的层**（1.74.31/32）：帧名只能**现场探**（UI 编译在 pak 里）⇒ `cands` 候选表 + 唯一解析口 `dfTargetFrame` + 探针 `/edb bars`（别名 `frames`，**先报队友/团员数**；单人时「候选全不在」是正常的）；候选全落空就**如实缺席**（`DF BARS WIRING CHECK` + 组 207）。★**解析到 ≠ 补上了**：队伍/团队框「按需出现」，只做候选解析会**永远不出现**且存档位置**静默不生效** ⇒ 配**事件驱动**跟随 `DF_ROSTER_EVENTS`（★`GROUP_ROSTER_UPDATE` 不许当注册依据；★1.75.1 起队伍/团队 **+ 宠物动作条** · 事件 `UNIT_PET`）→ 出现即 `dfApplyOne` + 重贴柄；**有界** `DF_ROSTER_TRIES`（不做常驻轮询）；判据 `DF ROSTER WIRING CHECK` + 组 208。细节全案见参考卷 R15 ⑤/⑥d。

- ★★★**跨插件：捕获 UnrealQuest 稀有提醒 → 独立模块 `tools/RareWatch.lua`**（主文件只两处接线：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)` + 命令 `/eh go 稀有`；开关单一来源 `EVAL_RW_ENABLED/SET`）：捕获点 = 包住对方弹窗唯一出口 `RareAlert:Show(...)`（**安装必须等 VARIABLES_LOADED**）、返回值逐个透传 + 抛错照原样 `error(a,0)`、兜底轮询 `GetStatus().alerts`（tick 父级必须 **WorldFrame**）；名字按品阶染色 + 整条**只许一段 8 位色码**，点名字 = 一次 `TargetByName` **并核对**（`UnitName("target")` 只认附近单位、远了静默失败），「选不到」要同时报距离+下一步。判据 = 组 199 + `RARE WATCH WIRING CHECK`（反向守「不许再耦合地图机制」）；**新增文件要同步 9 处清单**；全案见 R4。


- ★★★**任务线线（1.75.0~1.75.21，明细 → 参考卷 §十四）**：数据以 `database.emberveil.org/quests` 为准、`quest/QuestData.lua` 是**生成物**（改 `chains.js` → `node quest/build.js` 重建，**绝不手改**）；列表 **cap=0 全量 + 跨块统一排序**、系列记录单一来源 `qcSeriesRec`、等级档 **L6=60+**、缺图占位 = **宏 961**（点击插队优先）、请求队列**按列排** + 请求泵**常驻开启**（弹窗 Hide ⇒ OnUpdate 停摆）；判据 = `QUEST TOC CHECK` + 组 191/192；**闸门 = `node check.js`**（`--full` 另加 `quest/audit.js`）。★**步骤名判据 = 不在「进包任务表」**（不是「列表页」）—— 反了会把「有页但无装备奖励」的步骤名丢光（退化成 `#id` ⇒ 按步骤名搜不到；1.75.1「爱与家庭」实测 1585/1834 步无名）；闸门 = **audit H 段**（解析**生成物**，阈值 0）★先确认表形态（`s` 是**序列**无 `[n]=`，按错形态 ⇒ 0 条 = **假绿**）。★**同一个名字坑有两层**：生成期按「进包任务表」判 + **运行期必须把名字传下去**（详情/行模型别只认 q 表）—— 修一处不算修好；判据 = **组 228**。
- ★★★**追踪状态（草药 / 采矿 / 野兽 / 人型…）只有三条 API，没有枚举接口**（1.75.3 实证；全案见参考卷 R18）：
  ① `GetTrackingTexture()`（Mapping）= 当前追踪的**图标纹理**，什么都没追踪 = `nil` ⇒ 判「在不在追踪」；
  ② `GameTooltip:SetTrackingSpell()`（widget；读它走**自建隐形 tooltip** `EVAL_HELP_WTT`）= **唯一**能拿到「是哪种追踪」**本地化名字**的入口；
  ③ `CancelTrackingBuff()`（Buff）= 取消当前追踪。★三条官方页**都没有 Protected 行** ⇒ 插件可直接调；
  而 `CastSpell`/`CastSpellByName` 是 Protected ⇒ **开追踪只能走动作条 `UseAction(slot)`**。
  · **不存在**：`GetNumTrackingTypes`/`GetTrackingInfo`/`SetTracking`（别照 1.12 抄）；**小地图圆点无法枚举**
    （Minimap 只有 `SetBlipTexture`/`SetIconTexture` 两个纯外观 setter）；**事件名官方未公开**（wiki `/wiki/lua/Events` = 404）
    ⇒ 「切换追踪时哪条事件会来」**只能实测**（别抄 pfUI 的 `PLAYER_AURAS_CHANGED`，那是 TurtleWoW 的值）。
  · 官方另两条硬事实（别再绕）：`GetPlayerBuff` **skip** hidden/tracking auras、Buff 页明文
    「Tracking auras are **not** listed here」⇒ **光环路线只能当旁证**，不能当判据。
  · **纹理 → 种类一律走 `EVAL_TRACK_BASE`（剥目录/扩展名/`_TEX`、转小写）+ 全等比对 `TRK.hint`**（13 条实证表）
    —— **不许子串匹配**（`INV_Misc_Flower_02` 会假命中 `..._02_Copy`）；表逐条由 **`TRACK ICON CHECK`** 钉在
    `doc/图标路径清单.txt` 上（本机图标清单里没有的图标 = 真机永远匹配不上）；名字备用路
    `EVAL_TRACK_KIND_BY_NAME`（zhCN/enUS，认不出就 nil，**不猜**）。
  · ★★**1.75.4 真机首轮读数的教训：报告必须「分三态」，否则就是误报** ——
    ① 打「**类型 + 原文**」（`GetTrackingTexture` 返回非字符串时**不许**静默当「没追踪」）；
    ② 名字路**独立于①**（why = `ok`/`empty`/`noguard`/`noapi` 四态，tooltip 两行原文一起打）；
    ⑤ 增益条光环**连名字一起读**（`EVAL_PLAYER_BUFF_NAME`）；另加**第三条独立路** ⑩ 默认 UI 追踪按钮
    （候选名 + 有界 `_G` 扫描 + ⑪ 一行快照）；`监听` 升级为 **`RegisterAllEvents` 全事件抓取**（关掉时**按次数升序**列出，
    少的就是候选 —— 事件名官方没公开，猜 4 条不如全收）。
    ★判据（当场踩到）：**`pcall` 的第一个返回是「成功标志」**，而 `RegisterAllEvents` 真机**不返回值** ⇒
    一律按「**接口在不在** + **抛没抛错**」判，**绝不写** `pcall(f.RegisterAllEvents, f) and true or false`。
  · ★★★**1.75.5 真机实测形态（本项目实测值，别再按 1.12 的形态想）**：`GetTrackingTexture()` 返回
    `/Game/Interface/Icons/<Base>_TEX.<Base>_TEX`（**资产路径 _TEX + 「.」 + 对象名 _TEX**）⇒ `EVAL_TRACK_BASE`
    取最后一段后**只认第一个「.」之前**（否则归一成 `x_tex.x` 永远命中不了候选表）。
    真机三条路都通：① 纹理（`GetTrackingTexture`）· ② 本地化名字（`SetTrackingSpell`：读到「追踪野兽」+ 第二行「正在追踪野兽。」）·
    ⑩ 默认 UI 追踪按钮 `MiniMapTrackingIcon`（Texture，纹理与①相同、`IsShown=true`；`MiniMapTrackingFrame`/`MiniMapTrackingBorder` 也在）。
    ★**追踪不占增益条**（开了追踪时增益条里只有别的光环）⇒ 光环那条路只能当旁证；
    ★**事件名仍未实测出**（监听输出没留下）⇒ 实时刷新**不必依赖事件**：1s 轮询纹理、**变了才读名字**（贵调用只在变化时做）。
  · ★★★**1.75.6 落地成条件类型**（用户：「一键宏 → 技能编辑 → 条件类型 → 自身状态 → 追踪类型，下拉单选」）：
    `SE_TYPES` 新增 `{ id = "tracking", kind = "track", s = "any" }`（**单选下拉**，值 = 候选表 id），归 **CTG_1「自身状态」**；
    求值唯一入口 `EVAL_TRACK_MATCH(id)`（内部 `EVAL_TRACK_NOW()` **按纹理缓存** ⇒ 贵调用只在追踪变化时做一次），
    分支在 `condOne`（`cd.v == false` = 反向「未追踪:X」）；文本 **导出走 id**（`追踪:beast` / `未追踪:beast`）、
    **界面走本地化标签**；解析认 id / 基础名 / en / zh / 标签（认不出**整条丢弃**，不静默留半个条件）。
    ★★两个当场踩到的坑：① **函数名以 `L` 结尾 + 字面量参数**（`EVAL_TRACK_LABEL("any")`）会被 `LANG KEY CHECK`
    的正则当成语言键 `any`（它按 `L("KEY")` **子串**扫，不看前一个标识符）⇒ 改成走局部变量；
    ② `EVAL_DD_OPEN` 的 `opts.selected` **只在 `multi = true` 时生效** ⇒ 单选下拉的「当前值」得自己加标记（金色圆点）。
    闸门 = **组 229**（id/标签/清单 · 求值+缓存 · 文本往返 · 真实 condOne · 归组权重 · 真控件单选下拉）
    ＋ `TRACK ICON CHECK`（候选表 4 列 + **17 个 TRK 语言键三语齐全**；查键前**必须先剥注释**，否则注释掉一个键照样算有 —— 变异 M3 实测）。
  【取证】`/eh go 追踪探针`（读一次）·`监听`（事件实测）·`表`（13 条摊开）·`存档`（专属持久读数 `cfg.trkProbe`，不被 [DS] 冲掉）；断言 = **组 189**。

### 5.6 内容 / 数据质量
- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28）：判定收在共用件 `EVAL_IG_ITEM_KIND`（三级早停）；★**判不出就不剔**；★★**只在「弹窗候选」路径开**（按名解析包格那条路**绝不过滤** = 判错一类就静默找不到）；判据 = 组 187；细则见 R15 ⑥f。
- ★★★**可驱散「负面类型」多选**（1.73.2；1.74.6 扩到自身/目标 debuff）：`cd.dt` 空集 = 任意；求值**一律走 `dispelMatch`**（名字对上但类型不符 = **没有**）；**名称留空 + 类型 = 「有任意该类型」**；**buff 行不许有类型格**；组 114/181；细则见 R15 ⑥i。
- 指定等级=技能名(等级 3)（与法术书 subtext 逐字相符；跨语言不通用 ⇒ 没该串即如实失败）；下拉按等级升序、无 subtext 排最后，`table.sort` 在 5.1 不稳定须「数字+原下标」装饰排序（组 108①b/110②/111）。
- 不占动作条唯一判据 skillNoSlotOk（EVAL_NO_SLOT_OK）（STOP ATTACK WIRING CHECK；组 111⑤）。
- CLASS_LIST 缺圣骑士→模版 [职业:圣骑士] 静默丢弃；须末尾追加 PALADIN/圣骑士（组 111⑥+组 2）。
- 模版四条体检：名字非空 / 同组不重名 / 首行 # 方案: X 等于模版名 / ≥1 条技能行。
- 职业过滤：解析白名单+导出 teamFilterSuffix+编辑器格三处一起放开；单条条件按自己 cs/gs、选取器行按行内条件并集。
- 成员过滤空集=不过滤（与「目标职业」空=永不满足正好相反，不共用判据/文案）；成员类条件必须写在一行最前面（它负责扫人+切目标；写在后面=后面条件拿切之前的目标求值，静默出错）。
- 拆数据文件=一处真值变两处同步（磁盘+.toc），漏任一处都静默；EXAMPLES TOC CHECK 四条（双向一致 · toc 顺序=选单顺序 · 数据不搬回生产文件 · examples 在 EvalHelp.lua 之后）。
- LANG KEY CHECK：菜单标签运行时拼键→须配逐语言无重名/无缺键；文本往返单一通道（EVAL_PARSE_ONE 剥/teamFilterSuffix 写）。
- 光环判定=两级+三态：①纹理快路径（学习表>动作条）②名字慢路径（auraNameHit 0.5s 缓存、命中即 learnAuraTex 自愈）③两条都不可用才如实失败（查不到≠没有）；扫描可信度三态 true=命中/false=扫描干净确实没有/nil=不可信（组 70③/103①）；诊断 /eh go tex|texdel|texclear|texscan；桩补 SlashCmdList+组 104。

### 5.7 流程与纪律
- 载入提示与新手引导每次加载都打（cfg.guideSeen 已废弃）；组 105：VARIABLES_LOADED 第二次仍须打出引导标题与步骤。
- 审计/排查须落成可执行闸门；数据变的刷新放写入点（ioImportText）；组归属是用户偏好，需求一改须钉新归属与顺序。
- 只有 quiet=true 且带 why 写日志；接收端只有同一发送者开新的一笔才作废旧缓冲；四道上限超限整笔拒收、提示限频 5s。

### 5.8 队伍 / 团队·目标切换
- 唯一路径=TargetUnit（非 Protected）切目标→UseAction→还原；条件命中即记人+切目标（st.allyUnit，单条 队友血量<60 自足）；只在非 dry 时切（dry=0.15s 预览求值）；EVAL_GO 开头清空 st.allyUnit。
- 切目标只在有意义方向（血量/蓝量、debuff 有、缺 buff）；存在性判定不切；选取器=扫描+过滤（血量% 升序、须真切过去判定）；全员不满足须还原（UnitIsUnit 反查 unit id 优先；TargetByName 只认「附近」）。
- 成员选取器跳过常规条件预判（TARGET_SEL_TEAMSEL，不经 condOne→两处都要测）；UPDATE_STATE 只丢缓存不扫描，真扫描在 EVAL_HELP_TEAM_ENSURE（缓存复用）；诚实失败。

### 5.9 / 5.10 已整段迁参考卷
- **关键标识符索引** → §十七；**分享消息模板 / 取证命令全表 / 关键源码检查清单** → §十五。
## 六、§六 ~ §九 已移到同目录的 `CLAUDE_REFERENCE.md`（参考卷）

> ★**何时必须去读它**：项目位置/文件结构/新增模块/toc 顺序/工作流纪律 → §八；历史教训 / API 真伪 → §六；官方文档 / 待开发计划 / 开源仓库 → §七；某版本做了什么 → §九；判据踩坑全案 → 附录 R；各 CHECK 守什么 → 附录 R13。

