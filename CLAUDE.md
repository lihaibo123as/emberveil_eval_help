# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md` 与 git 提交历史，不进这里。
> ★★**本文件是「常驻卷」**（要保证 100% 落在工作区指令预算内）——其余整卷在**同目录的 `CLAUDE_REFERENCE.md`（参考卷，不自动载入）**：
> · 发布 release 流程 **9 步全文 + 打包脚本 + 推送信息** · §六 历史教训汇总 · §七 开源仓库 / 官方 API 文档 / 待开发计划
> · §八 项目位置与现状（文件结构 · toc 载入顺序 · **新增模块要改哪几处** · 数据检索设计 · **当前版本**）· §九 版本要点汇总
> · **§十 常驻卷瘦身移出的明细**（§3 的「按问题查哪个文件」对照表 · §5.2 两条长案例 · **§5.4 UI 与布局全部逐条** · **§5.5 API 事实全部逐条**）
> ★**什么时候必须去读参考卷**：要**发布 release**、要查**项目位置 / 当前版本 / 工作流纪律**、要查**历史教训 / 官方文档 / 待开发计划**时。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**；★**新条目先判它属「常驻卷」还是「参考卷」**（常驻卷只放必须随时可见的铁律与判据）。
> ★要查「某个功能/某个坑现在怎么写」→ 先看第五节的判据，再看 `DEVELOPMENT.md` 与源码。

## ★★★答复语种 = **中文**（用户明确定）

- **用户原话**：「将会话答复语种是中文加入全局记忆」「英文我看不懂」。
- **规则**：本会话及后续所有答复一律用**中文**（含报告、分析、解释、清单）；代码标识符 / API 名 / 事件名 / 英文术语原样保留，不翻译。
- **范围**：这条只管「我用什么语种回答你」，与插件本身的三语言（zhCN/enUS/ruRU）无关。

## ★★★改完代码**自动同步到本机游戏目录**（用户 1.74.8 明确要求）

- **用户原话**：「在修改代码完成之后自动将插件相关文件复制到 本机游戏目录：`E:\soft\game\eb\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns` 方便真机调试」。
- **触发条件**：**每次改完插件代码**（.lua / .toc / 素材）之后，**自动**把插件相关文件复制过去 —— 不必等用户开口，也不要在最后才想起来。
- **目标路径**（本机就绪，目录已存在，同级已有 `UnrealQuest`）：
  `E:\soft\game\eb\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns`
- ★**路径随机器而异（两台电脑 · 1.74.9）**：上面这个 `E:\soft\game\eb\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns` 是**另一台**的路径；本工作区那台的仓库**本身就在游戏的 `AddOns\EvalHelp` 里** —— 那里 `git pull` / 就地改文件**即等于**同步，**不需要**再复制。
  ★判据：**目标目录不存在 ≠ 出错**（`sync_game.js` 会自检仓库是否已在某个 `AddOns\EvalHelp` 内、如实打「本机无需同步」，exit 0）；换机器只改脚本里那一行 `DST`。
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
- **「提交版本」= 只做**：`git add <显式路径>` + `git commit`（+ 用户要求时 `git push origin master && git push github master`）。
- **「release / 发布版本」= 才做 9 步全套**：统计里程碑 → 三语言 README 更新 → 旧版信息扫描 → 里程碑同步 → 版本号与 CHANGELOG → 记忆体审计 → **打附注标签** → **推标签** → **出 zip 发布包 + 建 Release 页**。
- ★**判据**：只有用户**明确说出「release / 发布 / 出包 / 建 Release」**时才进第 7~9 步；只听到「提交版本」「提交」「commit」一律停在第 7 步的 commit（推送仅在用户同时要求时做）。
- ★**代价记录（1.72.1）**：用户说「提交版本」而我按 9 步跑完了全套（tag v1.72.1 已推两端 + zip 已出）——多做了用户没要求的事。**不确定时先问一句「要不要一并打标签/出包」，不要自行升级到 release**。
## ★★★发布 release = 9 步全套（**详细步骤 / 打包脚本 / 推送信息见 `CLAUDE_REFERENCE.md` 的「发布 release 流程」**）

- **9 步**：① 统计里程碑 → ② 三语言 README（**版本表只留最近 10 个**；★版本行必须插进「## 更新日志」那张表，**不是**开头那张功能表）→ ③ 扫描项目内的旧版信息 → ④ 三语言 README 的 `## 🏁 里程碑` 必须同步（**在更新日志之上** · 只 10 条 · **每条一行且以 `- ` 开头** · 是**归纳不是罗列**）→ ⑤ `local VERSION` 与 `## Version` 同步、`CHANGELOG.md` 保留完整历史 → ⑥ 审计记忆体（本文件）→ ⑦ commit + **附注标签**（`git tag -a vX.Y.Z -F 文件`；★说明文件必须 UTF-8 无 BOM —— **绝不用 PowerShell 的 `>` 重定向**，会写成 UTF-16LE 导致标签乱码；打完回读复核）→ ⑧ 推分支 + **推标签** → ⑨ 出 zip + 建 Release 页。
- **守这三步的源码检查**：`README TABLE CHECK`（3 个 README × 版本行在更新日志表里、恰好 10 行）· `MILESTONE CHECK`（里程碑在更新日志之上 + 末版 == VERSION + 正文 1..10 行 + 每条 `- `）· `PACK LIST CHECK`（发布包模块清单与 `.toc` 逐个一致 + 条目数基准现算）。
- **发布包**：`EvalHelp-vX.Y.Z.zip` 放 `Interface/AddOns/` 下（**不进仓库**），顶层 `EvalHelp\`；★装完必须核对条目数（写这份时基准 **63**，永远以 `.toc` 现算为准）。
- **Release 页我做不了**（本机无 `gh`、无任何 token，`POST /releases` 401）→ **如实请用户去网页建**，并把 URL / 标题 / 说明 / 附件给全。
- **推送**：两个远端都必须是 `git@` 形式（`origin`=gitee、`github`=github）+ 默认密钥；`git push origin master && git push github master`，标签也要 `--tags` 两端都推。

## 一、铁律

### 1. ★★★改完必须跑语法检查 + 测试（本项目因它白丢过好几个版本的功能）
- **Lua 整文件编译**：任何一处语法错误 → **整个插件无法载入**，且 UE 日志里**看不到**（`%LOCALAPPDATA%\Azeroth\Saved\Logs` 是空目录——本客户端落盘日志通道全废）。
  1.9.0 曾有两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 **1.9.0~1.11.0 全部功能实际未生效**；旧的 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助。
- **每次改完 .lua 必跑两条，两条都要 exit 0**：`node luacheck.js`（fengari 真实 Lua 解析，报错带行号，显示 **SYNTAX OK** 才算完）+ `node test_engine.js`（`test_stub.lua` 打桩 WoW API/UI mock + 5.1 垫片，加载整个 `EvalHelp.lua` 后跑 `test_assert.lua`，显示 **ALL TESTS PASS**）。
  fengari 已装在工作区 node_modules（npm 走代理 `127.0.0.1:10809`）。
- ★★**判据必须同时看「退出码」与「输出文本」**：源码检查失败走 `process.exitCode = 1` 而**脚本照跑到底**，于是 `ALL TESTS PASS` **照样打印**——只看这句话会**漏报**。
  行为断言失败打的是 **`ASSERT FAIL`**，源码检查失败打的是 **`: FAIL`**（两者都要在输出里找）。
- **源码级检查**（`test_engine.js` 内，**改了对应区域就必须让它们继续通过**）：`WIN WIDTH`（窗口宽度单一来源）· `DECL ORDER`（**9 个文件**的顶层 local 声明早于使用——1.73.0 起含 PetData/PetHelper）· `LAYOUT`（`EVAL_DS_BUILD` 布局常量）· `VERSION`（源码 VERSION == toc）· `LANG KEY`（`L("字面量")` 三语言齐全）· `LANG SOURCE`（取语言只认 `EVAL_GET_LANG`）· `WINDOW SIZE`（自建窗真的设了宽与高）· `COMMENT SWALLOW`（语句没被行尾注释吞掉）· `ICON`（图标素材真实存在）。
  后续又加到 **18 道以上**：`STOP ATTACK WIRING`（第 13 道：`stopAllOf`/`followOf` 那 7 个站点接线）· `UI ICON`（第 14 道：纹理路径逐个核到磁盘 + 类别图标不许撞图）· `CHAN RETRY WIRING`（第 15 道：`tbChanRetry()` ≥3 处接线 + 手动重试入口）· `EXAMPLES TOC`（磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序 + 数据不许搬回生产文件）· `README TABLE`（第 16 道：3 个 README 的版本行必须全在「更新日志」表里、恰好 10 行；CHANGELOG 保留完整历史 —— 守「发版脚本把版本行插错表」这类**不报错只是位置不对**的事故）· `MILESTONE`（第 17 道：3 个 README 都有 🏁 板块 + **里程碑在更新日志之上** + 标题范围末端 == 当前 VERSION + **板块正文 1..10 行**（10 个点、一条一行）+ **每条都是 `- ` 列表项**—— 守「顺序反了 / 里程碑又写成版本流水账 / 只更新了 CHANGELOG 忘了里程碑范围 / 排版被合并成一大段」）。
  ★判据：**行为断言照不到 UI 接线（漏接不报错、只是显示不对）→ 必须用源码检查补位**；两类检查互补，缺一就有盲区。
- **断言组 1~66+**：覆盖解析/引擎/UI/布局/语言/标注层；**新增功能请顺带加组**（写在 `test_assert.lua` 末尾 `print("ALL TESTS PASS")` 之前）。

### 2. ★★★任务/地图类问题 → 先读 UnrealQuest 对应流程代码（用户明确定，1.70.40）
- **用户原话**：「记住下次碰到任务地图相关的问题优先排查任务插件的对应流程代码」。
- **触发条件**：凡是涉及 **任务 / 地图 / 标注 / 世界地图 / 地图坐标 / 地图切换** 的问题——**第一个动作是去读 UnrealQuest 的对应流程代码**，不要先自己推断，也不要先往日志上加东西。
- **读哪里（按问题类型）**：

  | 问题 | 先读 |
  |---|---|
  | 定时/刷新不生效、生命周期 | `Core/Driver.lua`（**帧父级、OnUpdate 派发**——1.70.39 的坑就在这） |
  | 当前看的是哪张图 | `Map/MapContext.lua`（`GetViewedZone` / `Inspect`） |
  | 怎么画、什么时候重绘 | `Map/WorldMapPins.lua`（`ViewSignature` ~678、`Refresh` ~4449） |
  | 某个 API 在本客户端能不能用 | `Compatibility/ClientAPI.lua`（**实测配方库**，含大量「本客户端不支持 X」的明文） |
  | 图标素材路径 | `Map/NpcPins.lua`（CATEGORIES 表 + `IconForLocation`） |

- **怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库**信息密度最高**的内容。
- **停下信号**：当发现自己在「加日志 → 看日志 → 猜 → 再加日志」里转第二圈，**立刻停手去读对方代码**；**若读完仍未解决 → 转入下方铁律 4「取证协议」**。
- **两次代价（都是绕了远路）**：**1.70.17** 自己发明用 `IsShown` 判地图可见性，而对方 `ClientAPI.lua:8664` 早写明这 API 在本客户端**不可靠** → 引入回归；**1.70.39** tick 挂 `UIParent` 导致开图时 OnUpdate 停摆，而对方 `Driver.lua:467-482` 把机理和正确做法全写在注释里——用日志推断**五轮**没找到，**用户一句「可以查看任务插件…」当场破案**。

### 3. ★★★队伍/团队·血量/蓝量·buff/debuff 检测 → 先读 Heart（及它依赖的 C 库）（用户明确定，1.70.46）

- **用户原话**：「涉及到团队/队伍信息获取，血量，蓝量，buff/debuff 等检测 参考 `D:\game\TurtleWoW\Interface\AddOns\Heart` 插件的实现机制」。
- **触发条件**：涉及 **队伍/团队枚举 · 名字↔unit id 解析 · 血量/蓝量/资源与百分比 · buff/debuff（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——**第一个动作是去读 Heart 与 C 的对应实现**，不要自己从零推。
- ★**本机就是游戏主机**：EmberVeil（`G:\...\Emberveil\live\Azeroth`）与 TurtleWoW（`D:\game\TurtleWoW`）都在本机 —— **可直接读对方源码、也可直接进游戏实测**。
- **★必抄的五个机制**：① **隐形 tooltip 当 API 用**（`C.xml` 的 `C_Tooltip`：先清行再 `SetUnitBuff`/`SetUnitDebuff`/`SetSpell`，再 `GetText()` 取行）；② **Tick 新鲜度**（要求 `Tick == CurrentTick` 才算「现在有」，从结构上杜绝把过期数据当现行状态）；③ **贵调用只在「新出现」时做**（层数未变不重读、buff 与 debuff 槽都空就提前 return）；④ **名字↔unit**：先缓存再慢查、宠物＝`主人名-宠物名`、**缓存命中也要 `UnitExists` + 名字复核**；⑤ **共用更新函数的单调用者仲裁**（`C_UpdatePlayerData`，`GetTime()` 计时）。
- **⚠️ 边界**：Heart/C 是 **TurtleWoW** 插件，本项目跑 **EmberVeil**；本机 `C\C.lua` 已被用户改写且依赖 **SuperWoW** ⇒ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（别因为 Heart 能用就假定我们也能用）。
- **★「按问题查哪个文件」的完整对照表**（`C_GetUnitID` · `C_AKA` · `C_SetPlayerData` · `C_UpdatePlayerData` · `C_UnitGotBuff|Debuff` · `C.xml` · `Heart`/`Heart_Helper` · `Heart_event` · `Heart_Totem` 共 9 行）→ **参考卷 §十**。

### 4. ★★★同一个问题**两三轮没解决** → 立刻转「操作日志 + 测试流程」，让用户配合取证（用户明确定，1.70.46）
- **用户原话**：「碰到两三轮提问都无法解决的，尽快用记录操作日志的方式 + 提供测试流程。我会配合你完成问题排查。」
- **触发条件（硬性计数，不许糊弄）**：**同一个现象**已经来回「改一版 → 让用户再试 → 还是不对」**第 2 轮结束时就要准备取证，第 3 轮必须转取证模式**。继续凭猜测改代码 = 浪费时间且可能引入新回归（本项目已有两次代价）。
- **转入取证模式 = 一次交付这三样（缺一不可）**：
  1. **操作日志（插桩点选在分叉处）**：记录「输入是什么 → 判据取值是什么 → 走了哪个分支 → 结果是什么」。★核心要求：日志必须能**区分「代码没跑」和「条件没满足」**（1.70.16 教训：心跳日志被写在 `if not 开关 then return end` **之后**，整条链路静默，白猜三轮）。用 `dsLogAlways` 这类**不受 trace 开关门控**的通道记用户点击与异常路径。
  2. **测试流程（编号、可照抄、含期望现象）**：从**干净状态**开始（`/reload` 或重进游戏），一步一件事，每步写「做什么 → 期望看到什么」；需要多场景就分开列（场景A 首次打开 / 场景B 切换 / 场景C 关闭再开）。★**异常时也要让用户把剩下的步骤走完**（出错那一刻之后的行为同样是证据）。
  3. **回传物说明**：日志怎么拿（`/eh logdump` 打聊天框，或直接读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）+ **提醒本客户端日志只在 `/reload`/退出时落盘**，所以要先 `/reload`；再加现象描述/截图更佳。
- ★**能做成命令就别让用户手工复现**：给「一键探针」而不是「请你试十遍」——本项目已有范式：`/eh ds rnd`（随机点探针、如实统计成败）、`/eh ds hud`（把状态画在屏幕上）、`/eh ds trace`、`/eh go probe`。**把取证做成命令，是效率最高的协作方式**（1.70.35~38 正是靠它一行定案）。
- **取证模式的纪律**：**一次只验一个假设**（同时改多处 → 分不清是谁生效）；**不要只丢一句「把日志发我」**（必须带完整测试流程，否则用户不知道要复现什么）；拿到日志先**对齐时间轴**（日志行自带相对时间戳 `"%.3f 消息"`，按时间戳重排看事件先后——1.70.31 正是重排后一眼看出 `map=nil`）；日志里出现**两句自相矛盾**的话（如「层已关且无覆盖层」与「覆盖=草刺野猪」）→ 立刻怀疑**同一变量的两个绑定**（1.70.44 的定案方式）。
  ★**用户配合是已知条件**：本机就是游戏主机，可直接 `/reload` 实测，**不要吝啬开口要日志**，也不要因为怕麻烦用户而继续盲改。

### 5. ★★★返工的功能涉及 API → 先核「官方 API / Lua 函数调用本身对不对」，再动逻辑（用户明确定）
- **用户原话**：「记住碰到返工的功能涉及到API 函数优先查看官方API LUA 函数调用是否正确」。
- **触发条件**：凡是**返工**（重做 / 改判据 / 换实现）且**涉及客户端 API 函数**（含**事件名、消息组、SendChatMessage、Protected 绕行**这类）的功能——**第一个动作是逐个核对每个 API 调用本身对不对**，不要先改逻辑、也不要先怀疑数据。
- **核对清单（逐条问）**：
  ① 这个函数 / 事件名在本客户端**真的存在吗**（`api_*.html` 全表 1370 条索引 · UnrealQuest `Compatibility/ClientAPI.lua` 的**实测配方库** · `emberveil.org/wiki/lua`）；
  ② **参数个数 / 顺序 / 类型**对不对（如 `SendChatMessage(文, 类型, 语言, 频道号)` 第 4 参是**频道号不是频道名**——喂错就是「Channel is missing!」那一族）；
  ③ **返回值 / 语义**对不对（如 `AddChatWindowMessages` 收的是**单个组名**，塞整串不是它的用法 → 集合重复）；
  ④ 事件名 / 消息组名是不是**猜的**（本客户端通知事件名未必叫 `CHAT_MSG_*`、组名清单 api 索引里没有 → **不许猜**，现场用 `GetChatWindowMessages` / 探针实测）。
- **配套**：拿不准函数行为就**先写探针取证**（`/eh go 频道` 这类）用真机返回值定案，不凭印象；★这条与铁律 2/3（先读参考实现）是同族——**先在 API 这一层把「调用对不对」定死，再往逻辑/数据查**。
- **首案**：频道进出屏蔽返工三次（文本判据 → 官方消息组 → 事件名判据），最后靠核 API 调用 + 探针才定案；而那次「Channel is missing!」报错，核完 API 后确认**插件根本没拿 CHANNEL 发过消息**、错在客户端的频道成员状态 —— 不是插件把 API 调用写错。

## 二、频率防护总则（高频 API 调用场景）

- **原则**：凡是可能**高频触发**的 API 调用流程，设计阶段就必须考虑频率防护——**不要等被踢线/刷屏/翻倍后再补**。
- **判定方法**：设想最坏情况「一帧/一秒内会被触发多少次」；服务器写动作超过 **~1-2 次/s** 的一律限频，客户端事件**先假设会连发**。
- **三类范式（已有实现直接复用）**：
  1. **服务器写动作 → 限频队列**：`tbQ` + OnUpdate 滴出 `TB_RATE=0.3s`（1.68.2：一帧 24 次 `UseContainerItem` 被服务器反滥用踢线；1.69.0 交接 API/任务通知同入队）。配套：逐笔验证状态机 `tbPending`（槽位物品消失=成功 / 超时 2s=失败）、执行前二次校验防槽位变动、`MERCHANT_HIDE` 清待办防「卖变用」。
  2. **事件驱动 → 去抖窗口/节流**：`MERCHANT_SHOW` 本客户端连发两次（1.68.1 加 1.5s 去重窗 `tbMerchantLast`）；`BAG_UPDATE` 0.5s 节流（1.68.0）。教训：事件驱动功能上线后**一律假设事件连发**，高频事件必去抖。
  3. **执行入口 → 去抖窗口**：`EVAL_GO` 入口 0.2s 窗口（1.54.1：`/run` 宏走 RunScript pending 队列，连按堆积、松手后陈旧调用冲刷 = 目标狂切）；窗口可配 `cfg.goDebounce` 0~1.0（1.54.2），附 `EVAL_GO_TRACE` 追踪器取证。
- ★★★1.72.3 **分享分片必须限频发送**（用户实测：「长方案对方有时候接收不到」，短方案 1 片从不出问题）。
  【根因】`Share.lua` 原实现在一个 for 循环里**连着 `RunScript('SendChatMessage(...)')`** 把 N 片一次发完
  （同一帧 N 条聊天）→ 撞反刷屏限流被吞一片 → 接收端**永远收不齐**（而收不齐当时还是静默丢弃，见 5.2）。
  ★这正是本节早就写明的铁律的又一次违反：「**RunScript 本身也是队列，连发聊天同样会被反滥用踢线**，通知类输出也要入限频队列」。
  【修法】第 1 片立即发（手感不变），其余进 FIFO 由 OnUpdate 每 `SH_SEND_RATE=0.5s` 滴一片（**2 条/秒**，给服务器留余量），
  队列上限 `SH_MAX_QUEUE=200`（超出如实取消）；★**绝不在瞬间倾泻大量文字**（用户明确：不然服务器被触发预警）。
  ★判据 = 断言组 106（只准立即发 1 片 + 同刻 tick 也抽不干 + 分时发完）；变异 M7（退回一帧全发）→ 当场 got=9 want=1。
- **Protected 函数**（`SendChatMessage`/`SpellStopCasting` 等）绕行 = `RunScript` 聊天脚本（pending script 队列）——注意 **RunScript 本身也是队列**，连发聊天同样会被反滥用踢线，通知类输出也要入限频队列。

## 三、本客户端已实测的 UI 配方（UnrealQuest ClientAPI.lua 验证）

1. **拖动柄必须用 Button**（Frame 的 `OnDragStart` 不触发）；`SetFrameLevel(父+10)` 抬高（**用 strata 抬高是记录在案的失败做法**）；`EnableMouse` + `RegisterForClicks("LeftButtonUp")` + `RegisterForDrag("LeftButton")`；`StartMoving` 前 warm-up 两步（StartMoving→StopMovingOrSizing→StartMoving）。
2. **strata 层级陷阱**：配置窗是 DIALOG；其上方弹窗（技能编辑窗/导入导出窗）**必须同 DIALOG + `SetFrameLevel(90~100)`**，MEDIUM/HIGH 都会被 DIALOG 盖住（1.11.2 实测修复）；弹窗也要 `uiOffscreen` 越界回归。
3. **纯色纹理**只有 `Interface\Buttons\WHITE8X8` + `SetVertexColor` 可靠。
4. **无原生 Slider / 无下拉控件**：滑条 = 自制轨道 + 拇指；**下拉一律用全局件 `EVAL_DD_OPEN(锚点,选项表,回调)`**（1.19.0 由 SE 专用泛化；UIParent+DIALOG+level250，多列 12 行/列，贴屏底自动上翻；宿主窗口 `OnHide` 里调 `EVAL_DD_HIDE()`）；1.19.0 起插件内所有 `[<][>]` 循环器已全部改下拉。
5. **可见性契约**：显隐走**显式控件清单** Show/Hide，不靠父子传播（容器 `EnableMouse(false)`，交互件单独 `EnableMouse(true)`）。
6. **位置记忆**：`GetCenter`/`GetLeft` **含缩放**，存取要除 `GetEffectiveScale`；每个记忆位置的窗口都要 `uiOffscreen` 越界回归。
7. **禁用 `SetScale`**（点击框漂移），缩放 = 按 z 系数**几何重建**；字体链 `FZLBJW→FRIZQT→ARIALN` 全程 `pcall`。
8. **小地图按钮父级必须是 `UIParent`**（不能是 Minimap）；悬停用 `OnEnter`/`OnLeave` + GameTooltip，**不用 `SetHighlightTexture`**。


## 四、架构要点 + 编辑工具注意事项 + 当前功能地图

### 4.1 架构要点（改代码前先读这段）
- **状态表 `st`（`EVAL_HELP_STATE`）**：所有判定数据走 `UPDATE_STATE()` **一次刷新、各处只读**（Cat 思路，不重复调 API）；含 `playerBuffs`/`targetDebuffs` 纹理集合、`castLog` 释放日志（最近 5 条带条件 trace）。
- **规则引擎**：规则 = `{ skill, enabled, groups }`；`groups` = 组内 `&`、组间 `|`；`EVAL_RULE_RUN` 顺序执行第一条全过的；兼容旧 `when={}` 格式；`condOne`/`groupsOK`/`EVAL_PARSE_CONDS`/`EVAL_COND_STR`/`EVAL_GROUP_STR` 是核心。
- **方案数据**：`cfg.war.profiles` + `activeProfile`；`EVAL_WAR_ENSURE_PROFILES` 做缺省迁移；SavedVariables 自动持久化。
- **方案切换**：配置窗侧栏按钮 / 激活方案 `[<][>]` 选择器 / 战斗信息UI 方案行 / **Shift+按宏**（★Shift 已被切换占用，**方案条件里别用 Shift**，用 Alt/Ctrl）。
- **文本格式**（导入导出 / `zs_wq.md`）：`# 方案: 名` + `- 技能 | 条件` 行；技能名前 `!` = 停用；解析容忍 md 杂物行。
- **函数作用域陷阱**：`warCfg`/`c()` 是配置段 local，战斗信息UI 段在其之前 → UI 段用 `uiWarCfg()`（直接走 `EVAL_HELP_CONFIG` 全局）；`wslots`/`WAR_SKILLS` 是战士段 local，配置段在其后可用。
- 受保护函数（`CastSpellByName` 等）插件**不能调**，施法一律 `UseAction(slot)` + `pcall`；谓词返回 `true/false/nil`，**绝不 `==1`**。
- **`EVAL_GO` 目标门槛教训（1.21.7）**：规则引擎化后**不能有**「无可攻击目标就 return」的全局前置——是否需目标交给**每条规则的条件**；否则纯自身 buff 方案（如只有战斗怒吼）永远执行不到。
- 本客户端**无 `UnitCastingInfo`**（打断条件做不了）、**无 SuperWoW**（无精确距离数值/挥击计时）。
- **射程检测已有官方 API**（排查 emberveil.org/wiki/lua 确认）：`IsActionInRange(slot)` 已实现——`true`=在射程内 / `0`=超出射程 / `1`=自动攻击(不测距) / `nil`=无目标或技能解析失败；`ActionHasRange(slot)` 返回技能是否有射程；`CheckInteractDistance(unit,idx)` 已实现但客户端不分档码数（`idx<4` 统一交互距离，4 恒 false）——可做规则引擎「在射程内」条件，技能本来就在动作条上直接传 slot。
- **物品 API**（wiki 已确认签名，游戏内实测待做）：`UseContainerItem(bag,slot)` 消耗品直接用/装备自动穿（BoE 未绑弹确认）；`GetContainerItemInfo`→texture,count,locked,quality,readable；`GetContainerItemLink`→`|Hitem..|h[名称]|h`；`GetContainerItemCooldown`→start,duration,enable；`GetItemInfo` 第 9 返回值 = 纹理（只读本地缓存）。**无 `EquipItemByName`/`UseItemByName`**。★本客户端插件保护清单未文档化，`UseContainerItem` 是否被禁需实测——若被禁会**静默失败**（`pcall` 兜住不炸）。
- **`seBtn` 返回包裹表 `{btn,bg,text}` 不是按钮本体**：锚下拉/加 FontString 必须用 `.btn`（`mkSmall` 相反：直接返回 `b,bt`）——1.21.4 修复 SE 技能名按钮把包裹表当按钮用（`uiText` 炸 CreateFontString、SE_BUILD 半成品窗口）。
- **Lua local 作用域从声明语句【之后】开始**：RHS 里的闭包**捕获不到正在声明的 local 自己** → `local b = mk(..., function() ...引用b... end)` 的 `b` 是**全局 nil**！OnClick 要等赋值完再单独 `SetScript` 挂——1.21.4 修复激活方案下拉（`DD_OPEN` anchorBtn nil）。
- **EditBox 疑似不渲染**（1.15.1 用户报告 IO 窗口空白：`pcall` 全「成功」但什么都不可见）→ IO 窗加 FontString 保底预览区（`EVAL_HELP_IO_REFRESH`）；EditBox 字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`；**文本类 UI 一律给 FontString 保底**；单行输入弹窗用**回声行**保底（`OnTextChanged` 镜像到 FontString，1.17.0 重命名弹窗 `EVAL_HELP_RP_*` 范式）。

### 4.2 编辑工具注意事项
- `run_code` 里**没有 `require`**；node 脚本一律写工作区 `.js` 文件再 `pwsh node xx.js`（内联 `-e` 引号会炸）；`pwsh` 要加 `2>&1 | Out-String` 否则 stderr 丢失。
- `edit` 工具：本会话内须先 `read` 过该文件；`old_string` 要精确（注意缩进空格数；批量失败先 `grep` 核对实际状态再重试）；**node 外部改过文件后必须重新 read 才能 edit**。
- 大块插入用「写块文件 + node 边界替换脚本」，小改动用 `edit` 工具逐处替换。
- 写文件若报 `file no longer exists`：换文件名重建（fs-observation 缓存）。
- ★★★1.73.28 **别在 Lua 源码里手写转义**（本轮代价）：想写「引号 + 反斜杠」时手写 `"` / `\\` 极易写坏
  （实测把 `string.gsub(name, "[\"\\\\]", "")` 写成了 `"["\]"`）→ 而且 **luacheck 当时只查主文件、照样报 SYNTAX OK**，
  直到运行时 load 才炸（LOAD ERROR ... expected ')' near backslash）。正解 = 用 `string.char(34)` / `string.char(92)` 构造这类字符，
  抽成一个小函数（`tbSafeName`）复用；★同时把 `luacheck.js` 改成**逐个文件**检查（27 个 .lua），语法错误再也漏不过去。
- DSH 策略 danger-full-access、审批关闭 → **可直接写游戏 AddOns 目录**。
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（★**文件名是 `EvalHelp.lua` 不是 `EVAL_HELP.lua`**，1.29.0 改名后旧文件 `EVAL_HELP.lua` 是历史残留；小退/reload 时客户端写入）——**这也是现在读调试日志的地方**。

### 4.3 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行 + 方案技能行 + 条件 tooltip + 实时条件亮金）| `/eh st` 状态信息UI（状态变量 + 最近释放条件明细）。
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**六个 Tab**：① 全局（日志/界面/帮助）② 一键宏设置（方案栏 + 技能列表 + `[添加技能]` + `[导入导出]`；1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**）③ 工具箱（`Toolbox.lua`，1.68.0；1.74.5 起含**猎人助手 → 一键喂食**）④ 数据检索（`DataSearch.lua`）⑤ **图标库**（`IconBrowser.lua`，1.71.3）⑥ **抓宠帮手**（`PetHelper.lua` + `PetData.lua`，1.73.0：检索宠物技能 → 详情页驯服来源 → 放大镜跳数据检索）。
- 技能编辑窗：点 `[编]` 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 `&`/`|`；条件类型分 5 组（`CTG_5` = **队友/团员状态**：队友血量%/队友蓝量%/队友debuff/队友缺buff + 团员同名四型）。
- **队友/团员怎么用（1.70.47）**——两种用法都能独立工作：① **只配条件**（最省事）：技能行加 `队友血量% <60` → 条件自己**扫描全队取血最低者**、切目标、记 `st.allyUnit`，技能就打在他身上；解魔法同理。② **要自定义筛选**：加一行行为 `选取目标:队伍成员`（或 `团队成员`），把筛选条件写在这**一行**上（`目标血量<N%` / `目标buff:名` / `目标debuff:名`）→ 按血量升序逐候选判定，选第一个全过的。**规则按顺序全部执行**，所以「选取器 → 治疗 → 驱散」在一次按键里依次生效。
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单仅作下拉置顶，1.24.0 起重扫记录全部上条技能，任意技能可入方案/条件）；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（执行指定方案并且激活，绑多按键）；技能需拖上动作条，改动后 `/eh go rescan`；`/eh war` 是旧命令别名（1.21.1 起改名 `/eh go`，handler 里仍兼容）。
- 调试：`/eh debug`（跳过原因 + 触发 trace）| `/eh go list` | `/eh logdump` 调试日志 | `/eh ds`、`/eh ds trace` 数据检索诊断。
- **命令组 1.21.1 改名 `/eh war` → `/eh go`**（handler 入口 `string.gsub(msg,"^war","go")` 兼容旧命令；sub 偏移量随 war→go 长度差 -1 已同步）。

## 五、关键判据汇总（按主题）

> ★本节是**判据总表**：每条 = 一句规则 + 追溯锚点（判据组号 / 源码检查名 / 关键标识符）。
> 各条的踩坑经过与逐版本流水一律在 `CHANGELOG.md` 与同目录的 `CLAUDE_REFERENCE.md`（参考卷）。

### 5.1 Lua / 解析

- 多字节字符禁入 Lua `[...]`（按字节匹配）、`|` 非交替：`[:：]` 吃「：」首字节 → 目标/物品/宠物/姿态/条件解析全线静默失效；`colonNorm()` 入口归一。★`string.sub` 同样按**字节**取（`"go 喂食"`=9 字节 → 前缀判据写 `1,5` 恒不等 = 命令静默失效；1.74.5 实踩）。
- 模式里 `%` 是转义符：`%.`字面点、`%%`字面百分号（写错则分支永死）；plain 模式找 `%` 写 `"%"`，`"%%"` 找不到。
- 方括号组成对解析（`(.-)` 吞 `[职业:术士][队伍:2]`）→ 用 `[^%]]-`、半/全角分匹配；空集 ≠ 没写。
- 主 chunk ≤200 局部队变量、`do...end` 不开函数作用域；`ipairs` 遇 nil 即停。
- 1.73.15 `cond and f() or fallback` 在 `f()` 返 false 时恒取 fallback → 分两步 `local on=true; if type(f)=="function" then on = f() and true or false end`。
- 空串是真值（`""` 也算有键）→「键存在」≠「有内容」；`string.len` 是字节数 → 宽度按字符估。

### 5.2 静默失败族（数据 / 序列化 / 开关）

- ★★★**「自己方案回声忽略」的判据必须锚在「发送者是我」**（`shIsSelfEcho(sender)`，剥色码 / 剥「-服务器」后缀），**不能锚在「内容像我」** —— 锚内容时只要接收方库里已有同款（同账号共享库 / 以前导入过），就会把**别人发的**误判成自己的回声吞掉、不弹窗（1.74.5 真凶）。`EVAL_SHARE_IS_MINE` 函数保留但不再用于这一刀；组 82 ①/①b/③；变异 M569/M570。
  ★**「按日志判没发生」≠ 真没发生**（日志是环缓冲会覆盖）—— 上轮就是据此误判，最后靠探针 ⑤ 一屏定案它其实触发了。
- ★★**「分片到了却不弹」一律先取证再猜**：`SH.dbgChunks`（环形 8 条）+ `shDbgChunk(stage,…)` 在 `shOnMsg` 的**解析 / 入缓冲 / 收齐 / hex 还原失败 / 过大 / 回声忽略 / 弹窗**各分叉记**原文 + 走到哪一步**，用 `/eh go 分享事件` ⑤ 摊开（只记含 `EHPF` 的低量消息，不碰普通聊天）。
  ★探针**别用 `== true` 判事件注册**：本客户端 `IsEventRegistered` 返回 **`1` 不是 `true`**，要判 `(r == true or r == 1)`（旧探针全显示「未注册」，与实际收到事件自相矛盾、把排查带偏）。
- 1.72.2 具名帧顶掉同名全局函数 → `type(X)=="function"` 不成立 → 命令静默失效；桩须把具名帧挂全局；`FRAME NAME CLASH CHECK`；组 54。
- 1.72.3 分享接收 = 冗余时长 + 只认标识（用户「加冗余时长、只识别特定标识」）：>2s（`SH_RECV_TOLERANCE`）未收齐如实提醒但不删缓冲、晚到补齐仍弹窗；>60s（`SH_BUF_TIMEOUT`）才丢；只认 `[EHPF#<id> i/n]<hex>`；组 106/组 107。
- 「查不到」≠「没有」：查不到必须如实报错，否则 `cnt=0` → 「否/无」成立 → 规则无限重放刷屏。
- 静默丢弃 = 那行变无条件施法 → 写几条成员条件、解析后就必须几条；数据类错误全静默。
- 导出形态与解析侧必须成对验（读不回 = 导入即丢条件）；「有过滤」≠「过滤得住」（`itemOf(n)` 只认「物品:名」）。
- 两个日志开关不能合并（`cfg.log.on` 数据层总闸门 / `cfg.wdebug` 输出层）；静默 = 只进日志、不上屏、不走 `EVAL_SAY`。
- 判据表照客户端真实文案抄（「进入频道。」vs「加入」）；「尝试过」≠「挂上了」→ 载入即挂必须失败重试。
- 1.73.25 按序号做键的表删中间项要整体左移（用户「方案删除 要删除对应绑定的按键信息」）：`cfg.war.bindKeys`/`bindSlots` 解绑 + idx 之后左移一格 + `SaveBindings`；组 131。
- function 不是 table（身份判定用 `cur == TB.chanWrapper`）；标记只加显示串（`[物]` 只改显示、取值裸名）；「还原/撤回」≠ 回退到有 bug 状态。
- 1.73.14 借别人的 UI 对象 = 静默破坏界面：`local WTT = GameTooltip` 读数会清空玩家 tooltip → 自建 `EVAL_HELP_WTT`、读自家 `TextLeft1`、守卫 `EVAL_WTT_MAY_READ_PURE`；`WTT ISOLATION CHECK`；组 126；桩不加 `__index`（连带组 70 失效）。
- 1.73.12「写成功」≠「写进去生效」：`frame.AddMessage=wrapper` 写入被吞 → 必须写完读回确认（`_G.ChatFrame_OnEvent ~= wrapper`）+ 改挂普通全局函数入口（新文本回写全局 `arg1`）+ 非聊天事件放行；`CHAT COLOR WIRING CHECK`；组 123/组 124⑧。
- 深入 API + 参考插件（用户「深入分析 API 与参考插件」）：`GetChatWindowMessages`/`RemoveChatWindowMessages`/`AddChatWindowMessages` = 官方「某类消息不显示」开关（组名不许猜）；`ChatMOD.lua:514-517` 对 `this` 懒挂载 + 记账。
- 名字着色族（1.73.18~23/51）：名字在 `arg2`；名字槽不吃富文本 → 吞行自拼；色码必须 8 位 → `COLOR CODE LEN CHECK`；缓存 = 名字→职业 token（`tbNameClassPut`）；四来源 = 白拿 / `EVAL_TB_NAMECLASS_HARVEST(kind)` / /who / 事件；名册懒加载（`GetNumGuildMembers()` 恒 0）→ 自愈 `EVAL_TB_NAMECLASS_HEAL()` + 一发 `GuildRoster()`（四门）；`TB_NAMECOLOR_WRITE=false`；组 129b/组 129d③/组 161/组 161④⑤ + `NAME CACHE PROBE WIRING CHECK`。
- 1.73.43 分享行形态：只有「一段色码 + 链接」能画；色码无链接 / 链接打头无色码整条不画；6 位码画出原文、7 位整条被吞 → 色码打头 + 带链接 + 每条一段 8 位码 + 间隔 ≥1s（`SH_SEND_RATE=1.0`）；身份只在 A 行；组 144/组 144① + `SHARE MSG SHAPE CHECK`；色清单从 `SH_CHUNK_COLOR`/`SH_SEAL_TIERS`/`SH_TITLE_COLORS`/`SH_TITLE_CUSTOM_COLOR` 现取 → 组 158 + `SHARE PALETTE CHECK`；名号色默认 = 候选第 1 项、只认 8 位 `shTitleCustomColor()`；组 159。
- 1.73.24 右键菜单：有 `GuildInviteByName`/`CanGuildInvite`；无剪贴板接口、无 `UIDropDownMenu`；`SetItemRef` 可写 → 包它 + 读回确认 + 幂等，只认 `player:` 右键；`/s` 走 `RunScript` + 0.5s 去抖；组 130。
- 1.73.27 资源名必须显示时现算：`UnitPowerType` 0 法力/1 怒气/2 集中值/3 能量、随形态变 → 写死在表（`COND_NUMNAME.powerPct`）即错；显示名一律 `EVAL_POWERLABEL()`、四处同源；改显示名＝改导出文本 → 解析侧同时认新写法；组 132。
- 1.73.29「填进输入框」≠「替用户发送」（用户「只打开输入框，不要打印出去」）：只预填不回车、不碰 `SendChatMessage`/`RunScript`；判据双向：内容对 + 一个字都没发；共用 `tbMenuPrefill`。
- 1.73.30 标题栏宽度自适应 = 纯函数拼分隔条：`EVAL_TB_HDR_TEXT(标题,列宽)` 剥装饰后按列宽补破折号；读值口 `EVAL_TEST_TB_HDR_TEXT` 读真控件、逐字相同；「—」三字节 → 绝不写 `[—]`。
- 1.73.31~36 弹窗规程：层级全 `DIALOG`（10~250 八级，`EVAL_TN` 220、`EVAL_DD_OPEN` 250 最高）；①子弹窗层级必须高于父弹窗；②只设 strata 没设 frame level = 点击不到 → `SetFrameLevel(root,200)` + `EnableMouse(true)`；③可拖拽 = Button 柄 + 三件套 + level=窗口+1 + warm-up；④布局跟窗宽走、不写死 x、文案由调用方给；⑤位置按字面拆（用户「相对点击位置的右上角」）= 左下角贴光标 + 坐标除缩放。
- 1.73.33 布局异常：①锚点偏移算错（距右边误填距左边的数 → 列头叠画）→ 列几何单一来源（全用「距左边」、列头宽度 = 本列宽度）；判据 = 列头右边缘 == 该列数据右边缘 + 列头互不重叠；②能不能拖先问「有没有柄」。
- 1.73.34 滚动条规范：①滚轮要显式 `EnableMouseWheel(true)` + `SetScript("OnMouseWheel")`，方向单一来源 `EVAL_WHEEL_DIR(a,b)`；②`off` 双侧夹；③到顶/底、空列表藏箭头；④▲▼不许压数据列 → 专用滚动槽；⑤页码必须整数（浮点除被静默截断）、末页特判；⑥箭头与指示同一口径。
- 1.73.35 右键菜单条件门 + 名字→unit：①条目出不出现由 `CanGuildRemove()`/`CanGuildInvite()`/`GetNumPartyMembers()>0` 在建菜单时决定；②名字→unit 只扫本机看得到的单位，解析不到如实退回；③查询不许直调 `SendWho` → 走 `EVAL_TB_WHO_ENQUEUE`；④两列 + 宽高由条目数算（`EVAL_TB_MENU_LAYOUT`）。
- 1.73.35 聊天提示搬进弹窗 = 判据跟着落点走：判据改到弹窗正文 + 「知道了 → `cfg.loadMsgSeen=true` → `EVAL_LOADPOP_SHOW()` 返 false」；按钮判据走真实 `GetScript("OnClick")`。
- 1.73.37「点了没反应」两根因：①闭包捕获建菜单那一刻的名字快照（首次右键 nil）→ 名字先写再建 + 闭包改点击时才读；②「关闭」传空函数。判据必须走真实 `OnClick` → `EVAL_TEST_TB_MENU_CLICK(标签)`；测试先用 `EVAL_TEST_TB_MENU_DROP()`；冗余守卫要整组拆。
- 1.73.38「接收方要支持私聊」：接收帧本来就注册 `CHAT_MSG_WHISPER`；`IsEventRegistered("CHAT_MSG_WHISPER")` + 用真实路径 `EVAL_SHARE_ONMSG(msg,sender,"CHAT_MSG_WHISPER")` 喂密语分片。
- 1.73.38 tooltip 也要列全 + 分层：金色标题 + 每功能一行 + 灰色注意行，用 `\n` 在一条 `AddLine` 里分行；判据 = 逐个功能名都出现 + 含颜色码 + 含换行。
- 1.73.39「加个边框」也要读顶点色：四条 1px 纹理（BORDER 层）`tbSolid(1,1,1,0.75)`；判据 = 四条 + 顶点色 ≥0.9 + 跨满窗宽高。
- 1.73.39「A ↔ B 对调位置」= 改数据顺序不是改坐标；判据直接读渲染出的条目文字，别比 x/y。
- 1.73.40「圆角」只能来自原生边贴图：`SetBackdrop` + `edgeFile = UI-Tooltip-Border`（`edgeSize 16` 整数、`insets 4`）；判据 `MENU ROUND CHROME CHECK` + 两条路都验。
- 1.73.40「末行按钮吊在框外」= 高度公式漏算末行自身高度；正解 `h = -TOP + rows*行距 + PAD`；判据别用同一公式自证 → 独立包含性断言：每条按钮落在 `[0,W]×[-H,0]` 内。
- 1.73.40 悬停高亮走 `OnEnter`/`OnLeave` 改颜色（禁用 `SetHighlightTexture`）：底色/文字两处都改、离开逐值复原；判据读真控件 + 每条都挂了两个脚本。
- 1.73.40 计数必须由闸门守：「案例模版 11 组 N 条」散在 4 处（`.toc` + 三语 README）；判据 `TEMPLATE COUNT CHECK`。
- 1.73.40 样式需求会被下一轮推翻 → 断言跟着改方向：新判据 = ①悬停背景逐值没变 ②文字真变白；桩要能读回文字色。
- 1.73.40「框增加 padding」= 宽高/标题/条目位置全由同一组常量算：`TB_MENU_PAD`/`TB_MENU_TOP`；判据用独立阈值，不用生产常量自证。
- 1.73.41 同一内容不要两处各写：入口全走 `EVAL_HELP_GUIDE`，内部优先 `EVAL_LOADPOP_SHOW`、弹窗不可用才退回聊天打印；判据让 force 承重：`cfg.loadMsgSeen=true` 再点「使用引导」仍必须弹。


### 5.3 测试与断言
- ★桩默认值也属桩（真帧默认显示、桩 `shown=false` ⇒「没 Hide 却断言 `IsShown()==false`」恒真）；隐式前置改显式建立（`pcall(root.Show,root)`、`EVAL_WAR_TAB_REFRESH()`）；桩要记每状态（`TEST.targetUnit`）。组 110①⑧⑨、组 64/93。
- 测试够不着生产 local ⇒ 加钩子走真实 OnEnter；桩对无效调用要如实无效（`castStoppedDirect`/`castStopped`）、模拟 `SetText` 再触发 `OnTextChanged`；tooltip 桩＝另建对象＋真 GameTooltip 记账＋普通 table。
- 断言打真实调用点/入口＋反向哨兵；模块级状态入 `EVAL_TB_TEST_RESET_TIMERS`（文件末尾，否则 `DECL ORDER CHECK` 抓 FAIL）；「没执行」≠「没入队」⇒`EVAL_TB_TEST_QUEUED_QUESTS()`；写死布局常量＝测自己⇒`EVAL_TEST_CFG_LAYOUT()`。
- 期望值不许用语言包、不许同源自比（`EVAL_SHARE_SEAL_TIER(13).name` vs `EVAL_LOCALES[lg]`）⇒字面/绝对值夹具；颜色断言三通道一起比；弱判据两例：页码夹取替断言把事做掉、递归被 `pcall` 吞⇒让桩计数；夹具走 `EVAL_PROFILE_FROM_TEXT`。
- 变异：冗余防护整组拆；锚点唯一定位（整行/命中==1/摘 CR/语法合法）；先过 luacheck；还原用运行前内存原文（绝不 `git show HEAD:<file>`）；判捕获看退出码＋文本（`: FAIL`/`ASSERT FAIL`；`LANG KEY CHECK`）；新 CHECK 锚在外层 `})();` 后。

### 5.4 UI 与布局（★逐条明细已移入**参考卷 §十**；这里只留「动手前必看」的索引与铁律）

- ★★★**动手前先查参考卷 §十**（按标题搜）：标题栏（两窗同一实现）· 品阶色与显示 · **评分口径** · **覆盖封顶** · **头衔晋升** · **配置分角色存档** · 滚动/翻页/分页 · 滚轮方向 · 视图切换 · 弹窗层级/位置/高度 · 分列与换行 · 悬停高亮 · 导出 token 与本地化 · 聊天窗名字着色 · 主动查询四道闸门 · 彩蛋与创世者闸门 · 队伍菜单三条 · 技能格按键分派。
- ★★★**这几条是铁律（改 UI/布局前必须记住）**：
  ① **布局常量单一来源**；判据**验性质不验数字**、相对量验相对量、同一行中线对齐、中文宽度按字符数估（`string.len` 是字节）。
  ② **滚轮方向唯一源** `EVAL_WHEEL_DIR(a,b)`（禁位移与方向同号）；滚动/分页几何唯一源 `EVAL_HELP_CFG_BOTTOM()`。
  ③ **数据刷新不许改可见性**（可见性只由 Tab 切换的清单负责）；视图切换要把另一视图控件**整块** Show/Hide，`Hide` 过的要**逐个** `Show`。
  ④ **读值口绝不许复刻映射逻辑**（复刻一遍 ⇒ 变异存活＝自证）。
  ⑤ 弹窗层级全 `DIALOG`（10~250 八级）；**子弹窗必须高于父弹窗**，只设 strata 不设 frameLevel ＝点不到。
  ⑥ 「隐藏」＝**不画**（背板 + 挪出可视区），不是 `Hide()`；入口控件永远不许藏。
  ⑦ 改 UI 文案/样式 ⇒ **同步反转旧判据**（需求会被下一轮推翻，断言跟着改方向）。
- ★守它们的**源码检查**（改了对应区域必须继续过）：`UI TITLEBAR`/`UI TIER BADGE`/`UI TITLE NAME`/`UI CELL MOUSE`/`WHEEL DIRECTION`/`COVERAGE CAP WIRING`/`COND WEIGHT`/`SAVEDVARS SPLIT`/`SHARE PALETTE`/`PAINT WIRING`/`CHAT COLOR WIRING`/`NAME CACHE PROBE WIRING`/`PROF ICON PROBE WIRING`/`MENU ROUND CHROME`/`CREATOR GATE`。

### 5.5 API 与客户端事实（★明细已移入**参考卷 §十**；下面几条最常踩，必须常驻）

- 本客户端**无 `UnitCastingInfo`**（打断条件做不了）· **无 SuperWoW**（无精确距离数值/挥击计时）· **无文件读取 API**（无 io/os ⇒ 载入文件唯一形式＝列进 `.toc`；★`LoadAddOn` 是 **Protected** ⇒ **文件级懒加载不可能**，范式＝「toc 预载 + 载入期零副作用 + 首用才建帧」）。
- 施法 API **全 Protected**（`CastSpellByName` 等 ⇒ 一律 `RunScript` 兜；`SpellStopCasting` 直调无效）；`TargetUnit` 非 Protected，是「切目标→`UseAction(slot)`→还原」的唯一路径。
- ★★★`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` 是**独立事件**（只注册 `PARTY`/`RAID` ⇒ 队长一分享**一片都进不来**，接收端静默、发送端照样报「已发送 N 片」）。
- `UnitDebuff` 第 3 返回＝dispel token；`UnitMana` 是主能量且有显示缩放（怒气÷10、幸福÷1000）⇒ **判蓝量前先 `UnitPowerType(unit)==0`**。
- `GetQuestReward` 会再触发 `QUEST_COMPLETE` ⇒ 须三层防护（同名去重 / 领取窗口闸门 / 全局频率上限）。
- 1370 条 API 里**无 aura 专用函数**；`GetPlayerBuff(i,f)` 是增益条 **0 基**下标。
- **要查就来这里翻参考卷 §十**：`IsActionInRange`/`ActionHasRange`/`CheckInteractDistance` 的语义 · 物品 API 全签名 · 纹理路径与 `IconSem` 白名单 · `api_*.html` 索引的「有/无」清单 · Movement 族 Protected 边界 · `GetRaidRosterInfo` 九返回 · `AttackTarget`/`FollowByName` 细节。

### 5.6 内容 / 数据质量
- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28，用户「弹窗选的物品项目要过滤一下.不要显示武器,装备.灰色物品,草药,矿物,任务物品,材料等等非可使用的物品,验证可行性.」）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，**完全不依赖缓存**）⇒ 灰色一律剔；② **`GetItemInfo`**：★传参**先用物品链接**（`GetContainerItemLink` 给的 `|Hitem:…|h[名]|h` = 客户端的**缓存键**），nil 再退回名字；读第 5/6/8 返回 = 主类型/子类型/**装备槽**（装备槽非空 ⇒ 算护甲，比类型词更硬）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 读守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`**（已核在官方 API 索引里）读**类型行** —— ★★这一步会**把物品写进客户端缓存** ⇒ 下次 `GetItemInfo` 直接命中 = **自愈**（`probed` 计数会掉下来）。
  ★**剔除表** `IG_KIND_DROP`：武器 · 护甲(装备) · 灰色 · **材料（草药/矿物/布料/皮革/附魔材料）** · 任务物品 · 容器 · 箭矢弹药 · 钥匙 · 配方图纸；★**判不出就不剔**（铁律「查不到 ≠ 没有」：宁可多显示一件，也不把真食物藏起来）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」这条路径开**（`EVAL_IG_SCAN_BAGS(bags, { classify = true })`）——按名字解析包格那条路（`EVAL_CH_FIND` / `EVAL_HH_FIND_FOOD`）**绝不过滤**：判错一类 → 用户已配置的物品会**静默找不到**（本项目最恨的失败型）。
  ★★**tooltip 只读 TextLeft2 起**（**跳过 TextLeft1 = 物品名**）：名字里可能含类型词（「草药烤鱼」含「草药」）会污染判定；词表 `IG_KIND_WORDS` 按**真机实测文案**维护（本客户端 zhCN）。
  ★**验证入口**（「验证可行性」= 一条命令）：`/eh go 消耗品探针 过滤` ｜ `/eh go 喂食探针 过滤` → 逐件打出**判定依据**（品质 / 缓存主类型·子类型·装备槽 / tooltip 读到的真实类型行 / 最终判定）+ 统计行（剔除/保留/判不出/缓存命中/未缓存/tooltip 探了几次），上限 30 行并如实报「还有 N 条未显示」；★它同时是**补词表的依据**。
  ★**新增文件/新代码要同步的清单**（本轮 `DECL ORDER` 当场抓到）：报告函数被插到 `IG_KIND_*` **local 声明之前** → 真机上读到**全局 nil**；★凡是新函数引用文件内 local，一律确认声明在前（`DECL ORDER CHECK` 扫全部 14 个生产 .lua）。
  判据 = 组 187（旧档 ①~⑥ + 新档 ⑦~⑩：白色**材料**/任务/容器/箭矢/钥匙/配方逐项剔、tooltip 兜底真的收到 `SetBagItem(bag,slot)`、**缓存自愈后不再探**、判不出不剔但记账、关掉 `classify` 行为不变）。
- 可驱散「负面类型」多选（1.73.2；**1.74.6 扩到自身/目标 debuff**，用户：「自身/目标debuff 要参考队伍debuff 支持负面类型」）：`cd.dt`=nil/串/集合（空集=任意）；**求值一律走 `dispelMatch` 按类型过滤**（名字对上但类型不符 = **没有**）；**名称留空 + 类型 = 「有任意该类型」**（层数取命中项最大值）；类型存平行表 `st.{player,target}DebuffType`（层数表仍是数字）；格式化同一份 `dtSuffix()`（导出 token / 显示本地化名）；编辑窗类型格四族都有、**buff 行不许有**；组 114＋组 181（变异 M181 捕获）。
- 指定等级=技能名(等级 3)（与法术书 subtext 逐字相符；跨语言不通用→没该串即如实失败；只有真法术名才拆括号，前缀名括号属名字本身）；下拉按等级数字升序、无 subtext 排最后，table.sort 在 5.1 不稳定须「数字+原下标」装饰排序（组 108①b+组 110②；组 111）。
- 不占动作条唯一判据 skillNoSlotOk（EVAL_NO_SLOT_OK）（STOP ATTACK WIRING CHECK；组 111⑤）。
- CLASS_LIST 缺圣骑士→模版 [职业:圣骑士] 静默丢弃；须末尾追加 PALADIN/圣骑士（组 111⑥+组 2）。
- 模版四条体检：名字非空 / 同组不重名 / 首行 # 方案: X 等于模版名 / ≥1 条技能行。
- 职业过滤：解析白名单+导出 teamFilterSuffix+编辑器格三处一起放开；单条条件按自己 cs/gs、选取器行按行内条件并集。
- 成员过滤空集=不过滤（与「目标职业」空=永不满足正好相反，不共用判据/文案）；成员类条件必须写在一行最前面（它负责扫人+切目标；写在后面=后面条件拿切之前的目标求值，静默出错）。
- 拆数据文件=一处真值变两处同步（磁盘+.toc），漏任一处都静默；EXAMPLES TOC CHECK 四条（磁盘↔.toc 双向一致 missing/ghost · toc 顺序=选单顺序 · 数据不许搬回生产文件 · examples 排在 EvalHelp.lua 之后）。
- LANG KEY CHECK：菜单标签运行时拼键→须配逐语言无重名/无缺键；文本往返单一通道（EVAL_PARSE_ONE 剥/teamFilterSuffix 写）。
- 光环判定=两级+三态：①纹理快路径（学习表>动作条）②名字慢路径（auraNameHit 0.5s 缓存、命中即 learnAuraTex 自愈）③两条都不可用才如实失败（查不到≠没有）；扫描可信度三态 true=命中/false=扫描干净确实没有/nil=不可信（组 70③/103①）；诊断 /eh go tex|texdel|texclear|texscan；桩补 SlashCmdList+组 104。

### 5.7 流程与纪律
- 载入提示与新手引导每次加载都打（cfg.guideSeen 已废弃）；组 105：VARIABLES_LOADED 第二次仍须打出引导标题与步骤；/eh guide 可重看。
- 审计/排查须落成可执行闸门；数据变的刷新放写入点（ioImportText）；组归属是用户偏好，需求一改须钉新归属与顺序。
- 只有 quiet=true 且带 why 写日志；接收端只有同一发送者开新的一笔才作废旧缓冲（绝不跨发送者），四道上限超限整笔拒收，提示限频 5s。

### 5.8 队伍 / 团队·目标切换
- 唯一路径=TargetUnit（非 Protected）切目标→UseAction→还原；条件命中即记人+切目标（st.allyUnit，单条 队友血量<60 自足）；只在非 dry 时切（dry=0.15s 预览求值）；EVAL_GO 开头清空 st.allyUnit。
- 切目标只在有意义方向（血量/蓝量、debuff 有、缺 buff）；存在性判定不切；选取器=扫描+过滤（血量% 升序、须真切过去判定）；全员不满足须还原（UnitIsUnit 反查 unit id 优先；TargetByName 只认「附近」）。
- 成员选取器跳过常规条件预判（TARGET_SEL_TEAMSEL，不经 condOne→两处都要测）；UPDATE_STATE 只丢缓存不扫描，真扫描在 EVAL_HELP_TEAM_ENSURE（缓存复用）；诚实失败。
### 5.9 关键标识符索引（按名字找代码 / 找测试读值口；完整清单见 `test_engine.js` 与 `test_assert.lua`）

- 配置 / 语言：`EVAL_HELP_CONFIG`（全局配置表）· `EVAL_HELP_CFGWIN`（配置窗根，DECL ORDER 走 `rawget(_G,"EVAL_HELP_CFGWIN")`）· `EVAL_HELP_CFG_TOGGLE` · `EVAL_RESOLVE_LANG` · `EVAL_IO_TEMPLATES`。
- 解析 / 条件 / 品阶算分：`EVAL_PARSE_CONDS` · `EVAL_PROFILE_SCORE` · `EVAL_CLASS_LIST`。
- 分享 / 封皮 / 色表：`EVAL_SHARE_SEAL_INFO` · `EVAL_SHARE_SEAL_DEMO` · `EVAL_SHARE_SEAL_SYMBOL` · `EVAL_SHARE_SEAL_TIER_RGB` · `EVAL_SHARE_DISPATCH` · `SH_POP_GOT_NAME`。
- 头衔 / 彩蛋闸门：`EVAL_TITLE_STATE` · `EVAL_TITLE_REFRESH` · `EVAL_TITLE_SET_CUSTOM`（**只认第一次**）· `EVAL_TITLE_CREATOR_GATE` · `cfg.title.customColor` · `cfg.title.creatorOffered`。
- 聊天 / 名字缓存：`tbNcHarvest` · `tbNcAt` · `tbNameClassEnsureRoster` · `tbCeSenderOf` · `EVAL_TB_NAMECLASS_PROBE`。
- 工具箱 / 菜单 / 任务迁移：`tbBtn` · `tbText` · `tbMenuBuild` · `tbMigrateQuest` · `tbQPump` · `EVAL_TB_MENU_SHOW` · `EVAL_TB_HOLD_ACTIVE` · `EVAL_TB_NAME_SAY` · `EVAL_TB_PAINT_ROW` · `EVAL_TB_PAINT_STATE`。
- 图标库 / 下拉：`EVAL_IB_SET_QUERY` · `EVAL_IB_TEST_MATCH_GROUPS` · `EVAL_DD_SYNC` · `EVAL_DD_TEST_BUILD_SEARCH`。
- 数据检索 / 调试：`EVAL_DS_HUD`。
- 测试读值口：`EVAL_TEST_ST_TITLEBAR` · `EVAL_TEST_UI_TITLEBAR` · `EVAL_TEST_SE_RANK_TIP` · `EVAL_TEST_SHARE_DRAIN` · `EVAL_TEST_TB_MIGRATE` · `EVAL_TEST_TPL_PLAN_FAKE` · `EVAL_TEST_WAR_PROF_ROWS` · `EVAL_TEST_WAR_TIER_CALC_COUNT`。
- ★组号在本节里有**紧凑写法**（如 `组 162/163/164/166/168`、`组 160⑥⑦`）——搜索单个号码时按数字搜，别按「组 N」整串搜。

### 5.10 速查：分享消息模板 / 取证命令 / 关键 CHECK 明细

**分享消息（三段形态，全部「色码打头 + 带链接 + 每条一段 8 位色码」，间隔 ≥1s）**
- 分片：`|cff9ad4ff|HEHPF:<id> <i>/<n>:<hex>|h[秘籍传输中...p%]|h|r`（标签只报进度、不带方案名，走 `SH_CHUNK_LABEL` 三语言）
- A 身份行：`|c<身份色>|HEHPF:<id> 0/1:0|h[<头衔>]|h|r <名字> 分享了`
- B 品阶行（也是最后一条信息行）：`|c<品阶色>|HEHPF:<id> 0/1:1|h[<符号><品阶>秘籍·<名>]|h|r  <评语>`（★1.73.50 起**不带头衔尾巴**；身份只在 A 行出现一次）

**取证命令（本项目纪律：能做成命令就别让用户手工复现）**
- 光环：`/eh go tex`（看学习表）· `texdel 名字`（大小写不敏感；删完下次判定会自动扫描学回来）· `texclear` · `texscan`
- 名字着色：`/eh go 名字缓存`（`EVAL_TB_NAMECLASS_PROBE`：每个来源的 API 有无 / 本地条数 / 首条职业原文→token · 缓存条数 · 聊天入口包装帧数与上色计数一次摊开）· `/eh go 聊天 色测`（5 种名字写法让客户端自己渲染 + 打印客户端格式串）
- 分享：`/eh go 封皮测`（编号 A/B 变异测，回报「哪些编号出现了」即可定案）· `分享探针`（发送留痕：脚本原文/是否弹出/队列）· `色码测`（别名 `colortest`/`颜色测`/`palette`：把在用色码逐条编号实发；★跑完等 ≥30 秒再跑第二次）· `名号色`（候选逐条预览）· `名号色 <n>`（当场选用并存档）
- 其它：`/eh ds hud`（`EVAL_DS_HUD`，把状态画屏上）· `/eh ds trace` · `/eh ds rnd` · `/eh go probe` · `/eh go bind`（只读现状）· `/eh go diag` · `/eh logdump` · `/eh guide`

**关键源码检查在守什么**（一句话；全清单见 `test_engine.js`）：`FRAME NAME CLASH`（21 具名帧 × 全部 `function NAME(`）· `WTT ISOLATION`（禁 `local WTT = GameTooltip` + 自建 + 读自家 FontString + 守卫/诊断，★扫描前摘注释）· `CHAT COLOR WIRING`（读回确认 + 幂等守卫）· `COLOR CODE LEN`（禁 `"|c"..string.sub(` + 职业色表 8 位）· `SHARE MSG SHAPE`（逐条数字面量）· `SHARE PALETTE`（色表 8 位 + 引用四表 + 无字面色码 + 接线）· `MENU ROUND CHROME`（整数 edgeSize / 白框 / 读回 / 平边退化 / 禁 `GetBackdropColor`）· `TEMPLATE COUNT`（`{ name = "` 条数 == 文档数字）· `WHEEL DIRECTION`（禁位移与方向同号）· `SHARE RECV EVENTS`（接收帧七事件全注册 + 探针接线）· `UI CELL MOUSE`（技能格左右键分派）
- 其余：`EXAMPLES TOC`（四条）· `STOP ATTACK WIRING`（名单 7/7 + 接线 ≥3）· `PET ICON` · `LANG KEY` · `DECL ORDER`（9 文件）· `PAINT WIRING` · `DEBUFF DISPLAY` · `CREATOR GATE` · `SH FUN` · `PROF ICON PROBE WIRING` · `UI TITLE BADGES`/`UI TIER BADGE`/`UI TITLEBAR`/`UI TITLE NAME`（全清单见 `test_engine.js`）

## 六、§六 ~ §九 已移到同目录的 `CLAUDE_REFERENCE.md`（参考卷）

> ★**为什么**：工作区指令预算只有 **65,536 字节**，超出的部分 AI **完全读不到**（截断点落在文档中段）——
> 所以把「历史教训 / 仓库与文档 / 项目位置与现状 / 版本要点」这四节整卷移出去，本文件只留铁律与判据。
> ★**1.74.9 又做了一次瘦身**（86,364 → 约 62,000 字节）：把**明细整段**搬到参考卷 **§十**（原文照存、一字未改），本文件只留索引 + 铁律 —— 因为超预算的部分 AI **完全读不到**。
> ★**什么时候必须去读 `CLAUDE_REFERENCE.md`**：
> · **项目位置 / 文件结构 / 新增 .lua 模块要改哪几处 / toc 载入顺序 / 数据检索 Tab 设计** → 它的 §八
> · **工作流纪律**（默认不发版不推送 · 本地测试双绿可直接 commit · 推送需明确要求） → 它的 §八 末段
> · **历史教训**（local 作用域、合并冲突静默获胜、桩太宽松、对齐、API 真伪清单、官方文档核对） → 它的 §六
> · **官方 API 文档地址 / 待开发计划（免疫学习器等）/ 开源仓库内容清单** → 它的 §七
> · **某个版本做了什么（最近 10 版，一行一条）** → 它的 §九（完整历史看 `CHANGELOG.md`）
> · **§3 的「按问题查哪个文件」9 行对照表 / §5.4 UI 与布局全部逐条（品阶色·评分口径·覆盖封顶·头衔晋升·分角色存档·滚动分页·滚轮·弹窗·菜单·技能格）/ §5.5 API 事实全部逐条 / §5.2 的两条长案例** → 它的 **§十**（1.74.9 瘦身时移出，原文照存）
> · **当前版本**：以源码为唯一真值 —— `EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version`（搬移时 = **1.74.0**）。
