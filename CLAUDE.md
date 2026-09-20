# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md` 与 git 提交历史，不进这里。
> ★★**本文件是「常驻卷」**（要保证 100% 落在工作区指令预算内）——其余整卷在**同目录的 `CLAUDE_REFERENCE.md`（参考卷，不自动载入）**：
> · 发布 release 流程 **9 步全文 + 打包脚本 + 推送信息** · §六 历史教训汇总 · §七 开源仓库 / 官方 API 文档 / 待开发计划
> · §八 项目位置与现状（文件结构 · toc 载入顺序 · **新增模块要改哪几处** · 数据检索设计 · **当前版本**）· §九 版本要点汇总
> ★**什么时候必须去读参考卷**：要**发布 release**、要查**项目位置 / 当前版本 / 工作流纪律**、要查**历史教训 / 官方文档 / 待开发计划**时。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**；★**新条目先判它属「常驻卷」还是「参考卷」**（常驻卷只放必须随时可见的铁律与判据）。
> ★要查「某个功能/某个坑现在怎么写」→ 先看第五节的判据，再看 `DEVELOPMENT.md` 与源码。

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
- **触发条件**：凡涉及 **队伍/团队（party/raid）成员枚举 · 单位解析（名字 ↔ unit id）· 血量/蓝量/资源与百分比 · buff/debuff 检测（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——第一个动作是去读 Heart 与 C 的对应实现，不要自己从零推。
- ★**本机就是游戏主机**（用户 1.70.46 明确）：**EmberVeil**（`G:\...\Emberveil\live\Azeroth`）与 **TurtleWoW**（`D:\game\TurtleWoW`）都在本机，**可直接读对方源码、也可直接进游戏实测**——不存在「另一台机器」，不要再拿远端当借口。
- **读哪里（按问题定位）**：

  | 问题 | 先读 |
  |---|---|
  | 名字 → unit id（从聊天/战斗文字里的人名反查单位） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 「慢查」遍历 `raid1..N`/`raidpetN`、`party1..N`/`partypetN`、`player`/`pet`、`target`/`targettarget`/`mouseover`） |
  | `target`/`mouseover` → 具体队伍成员 | `C\C_AKA.lua`（用 `UnitIsUnit` 逐个比对，返回 `raid3`/`party1` 之类；便于把当前目标当成员查数据） |
  | buff/debuff 全量采集的数据结构 | `C\C_SetPlayerData.lua`（**16 buff + 16 debuff 槽**扫描 → `C_player_data[名字].Buff[纹理] = {Name,Type,Text,Count,Tick,Time}`） |
  | 采集驱动 + 多插件共用时的仲裁 | `C\C_UpdatePlayerData.lua`（遍历 raid/party/target/targettarget/mouseover/pet；★**同一轮更新只允许一个调用者**） |
  | 「某单位有没有某 buff/debuff」 | `C\C_UnitGotBuff.lua` / `C\C_UnitGotDebuff.lua`（按**名字**查 `C_buff_texture_map` → 纹理 → **要求 `Tick == CurrentTick`** 才算「有」，且返回**数据条目**而非布尔） |
  | **用 tooltip 读客户端没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData` / `C_GetDebuffData` / `C_GetSpellData` |
  | 队伍/团队主逻辑、血量优先级与治疗决策 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`UnitHealth`/`UnitHealthMax`/`UnitMana`/`UnitPowerType`；`hpDeficit = UnitHealthMax - UnitHealth`、`priority * (healvalue / UnitHealthMax)` 的权重算法） |
  | 事件与跨插件通信 | `Heart\Heart_event.lua`（`RegisterEvent` / `SendAddonMessage`）、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua`（**钩各种单位框插件**） |
  | 图腾 / 需要 tooltip 扫描的跟踪 | `Heart\Heart_Totem.lua`（31 处 tooltip 调用） |

- **★必抄的五个机制（「实现机制」的干货）**：
  1. **隐形 tooltip 当 API 用**（`C.xml`）：`<GameTooltip name="C_Tooltip" hidden="true" inherits="GameTooltipTemplate">` + `PLAYER_LOGIN` 时 `SetOwner(UIParent,"ANCHOR_NONE")`（1.10 hack）与 `SetClampedToScreen(0)`（1.11 hack）。读取时**先清要用的行再 Set**（`C_TooltipTextLeft1:SetText()` 无参 = 清空），再 `C_Tooltip:SetUnitBuff(unit, slot)` / `SetUnitDebuff` / `SetSpell` / `SetAction`，然后 `GetText()` 取行——**buff 的名称/类型、第二行文本（常含剩余时长）、法术的耗蓝/射程/施法时间都从这里来**。
  2. **Tick 新鲜度**：每轮刷新把 `CurrentTick + 1`；查询侧要求 `entry.Tick == CurrentTick` 才算「现在有」——**从结构上杜绝把上一轮/过期数据当成现行状态**（比「加时间戳自己判过期」更简单可靠）。
  3. **贵调用只在「新出现」时做**：tooltip 调用很贵 → 只有**首次见到**该 buff 才去读；已知且**层数未变**时只刷新 Tick 并累加 `Time`，不做 tooltip；扫描时 **buff 与 debuff 槽都空就提前 return**（正合「频率防护总则」）。
  4. **名字 ↔ unit 解析与宠物命名约定**：宠物一律 `主人名-宠物名`；反查先走缓存再「慢查」，**缓存命中也要用 `UnitExists` + 名字复核**（unit id 会变）。
  5. **共用更新函数的单调用者仲裁**：`C_UpdatePlayerData` 用 `C_last_update_player_data_caller == this:GetName()` 判断，**别人正在这一轮更新就直接 return**，并用 `GetTime()` 统计本次耗时——多插件共用一份数据时的去重与自测。
- **⚠️ 重要边界（别抄错东西）**：Heart/C 是 **TurtleWoW** 客户端插件，本项目跑在 **EmberVeil**；本机的 `C\C.lua` **已被用户改写**成「治疗施法监控（CastingSpeed）」并依赖 **SuperWoW** 扩展（`SUPERWOW_STRING`、`UNIT_CASTEVENT`、`UnitExists(unit)` 第二返回值 = GUID）。→ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（本项目另有「EmberVeil 无 SuperWoW / 无 UnitCastingInfo」的记录，别因为 Heart 能用就假定我们也能用）。

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
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**六个 Tab**：① 全局（日志/界面/帮助）② 一键宏设置（方案栏 + 技能列表 + `[添加技能]` + `[导入导出]`；1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**）③ 工具箱（`Toolbox.lua`，1.68.0）④ 数据检索（`DataSearch.lua`）⑤ **图标库**（`IconBrowser.lua`，1.71.3）⑥ **抓宠帮手**（`PetHelper.lua` + `PetData.lua`，1.73.0：检索宠物技能 → 详情页驯服来源 → 放大镜跳数据检索）。
- 技能编辑窗：点 `[编]` 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 `&`/`|`；条件类型分 5 组（`CTG_5` = **队友/团员状态**：队友血量%/队友蓝量%/队友debuff/队友缺buff + 团员同名四型）。
- **队友/团员怎么用（1.70.47）**——两种用法都能独立工作：① **只配条件**（最省事）：技能行加 `队友血量% <60` → 条件自己**扫描全队取血最低者**、切目标、记 `st.allyUnit`，技能就打在他身上；解魔法同理。② **要自定义筛选**：加一行行为 `选取目标:队伍成员`（或 `团队成员`），把筛选条件写在这**一行**上（`目标血量<N%` / `目标buff:名` / `目标debuff:名`）→ 按血量升序逐候选判定，选第一个全过的。**规则按顺序全部执行**，所以「选取器 → 治疗 → 驱散」在一次按键里依次生效。
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单仅作下拉置顶，1.24.0 起重扫记录全部上条技能，任意技能可入方案/条件）；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（执行指定方案并且激活，绑多按键）；技能需拖上动作条，改动后 `/eh go rescan`；`/eh war` 是旧命令别名（1.21.1 起改名 `/eh go`，handler 里仍兼容）。
- 调试：`/eh debug`（跳过原因 + 触发 trace）| `/eh go list` | `/eh logdump` 调试日志 | `/eh ds`、`/eh ds trace` 数据检索诊断。
- **命令组 1.21.1 改名 `/eh war` → `/eh go`**（handler 入口 `string.gsub(msg,"^war","go")` 兼容旧命令；sub 偏移量随 war→go 长度差 -1 已同步）。

## 五、关键判据汇总（按主题）

> ★本节是**判据总表**：每条 = 一句规则 + 追溯锚点（判据组号 / 源码检查名 / 关键标识符）。
> 各条的踩坑经过与逐版本流水一律在 `CHANGELOG.md` 与同目录的 `CLAUDE_REFERENCE.md`（参考卷）。

### 5.1 Lua / 解析

- 多字节字符禁入 Lua `[...]`（按字节匹配）、`|` 非交替：`[:：]` 吃「：」首字节 → 目标/物品/宠物/姿态/条件解析全线静默失效；`colonNorm()` 入口归一。
- 模式里 `%` 是转义符：`%.`字面点、`%%`字面百分号（写错则分支永死）；plain 模式找 `%` 写 `"%"`，`"%%"` 找不到。
- 方括号组成对解析（`(.-)` 吞 `[职业:术士][队伍:2]`）→ 用 `[^%]]-`、半/全角分匹配；空集 ≠ 没写。
- 主 chunk ≤200 局部队变量、`do...end` 不开函数作用域；`ipairs` 遇 nil 即停。
- 1.73.15 `cond and f() or fallback` 在 `f()` 返 false 时恒取 fallback → 分两步 `local on=true; if type(f)=="function" then on = f() and true or false end`。
- 空串是真值（`""` 也算有键）→「键存在」≠「有内容」；`string.len` 是字节数 → 宽度按字符估。

### 5.2 静默失败族（数据 / 序列化 / 开关）

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

### 5.4 UI 与布局
- ★★★标题栏（两窗同一实现）＝玩家名→头衔→品阶徽标→方案名＋右侧两开关；两窗各自 BUILD＋tick 刷（只开状态UI 也要跟·组 168⑤）；头衔取 `EVAL_TITLE_CURRENT()`；色码→RGB `EVAL_COLOR_RGB`（8 位）；CHECK `UI TITLE BADGES CHECK`/`UI TIER BADGE CHECK`/`UI TITLEBAR CHECK`/`UI TITLE NAME CHECK`；组 162/163/164/166/168。
- ★★品阶唯一源 `SH_SEAL_TIERS`：≤6 普通/7-12 稀有/13-18 珍稀/19-24 绝版/≥25 神级；色走 `SH_SEAL_TIERS[].color`；源代码→神级、00bfff→c00000；`SHARE PALETTE CHECK` 守色码不重复；判据钉边界两侧（6/7·12/13·18/19·24/25）；组 146/164/167/168。
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★纯黑＝`EVAL_SHARE_SEAL_ICON` 两返回值内联进 `pcall(t.SetTexture,…)`⇒多返回值禁内联进可变参数调用；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。
- ★★★滚轮方向唯一源 `EVAL_WHEEL_DIR(a,b)`（幅度归一 ±1）；6 处全走它；`WHEEL DIRECTION CHECK`（禁位移与方向同号）＋组 115；★断言把方向写反⇒反向 bug 被「验证」通过。
- ★★★数据刷新不许改可见性：`EVAL_WAR_TAB_REFRESH()` 又被开配置窗与 `EVAL_PM_APPLY` 调用⇒可见性只由 Tab 切换负责（`EVAL_HELP_CFG_SETTAB` 的清单）；数据照旧每次刷；组 165＋`EVAL_TEST_WAR_ROWS()`。
- ★★视图切换要把另一视图控件整块隐藏（整表 Show/Hide·组 113②）；`Hide` 过的逐个 `Show`（少一个＝永久不显示·组 113③）；布局审查读真实矩形（`EVAL_PH_TEST_GEOM()`·组 113④）；输入框唯一入口 `EVAL_PH_SET_QUERY`（退回列表）、回写前 `GetText` 比对（否则递归）。
- ★入口控件永远不许藏（默认文案「不限」）；查不到≠没有⇒如实说明（`SE_RANK_NONE`）、不弹单项下拉（组 110⑨）；「隐藏」＝不画不是 `Hide()`⇒背板＋挪出可视区 `DD_SEARCH_PARK=-4000`；锚点＝邻居哪条边（`Minimap` 是圆的⇒`RIGHT` 对 `LEFT`）。
- ★分列切点＝允许切点里两列行数差最小；组是不拆的最小单位；版式抽纯函数；组标题不许孤悬行尾；绝不静默截断（`DD_MAX_ROWS=96` 末行「…… 还有 N 项未显示」、`SH_DETAIL_MAX=6`）；不变量读真实几何（本列内/同 y 两列各自成行/不跨列/行数差 ≤2）。
- ★★类别独立一行＝标题独占一行＋本组按钮从下一行排、放不下换行；窗高变高（660×240→660×340）；`rowsOf` 与摆放循环必须逐字一致，用「自报 `rowsL/rowsR` vs 真实控件行数」钉住（组 91）。
- ★工具箱两列（按组边界切、取两列行数差最小）：列宽＝(可用宽−列缝×(列数−1))/列数、< 200 退单列；列不相交要几何断言（每控件显式限宽·组 120③）；★★★读值口绝不许复刻映射逻辑（`EVAL_TB_TEST_LAYOUT` 又算一遍⇒变异存活）。
- ★弹窗高度自适应条目：唯一源 `EVAL_TB_MENU_HEIGHT(条数)`；判据要换一组条目再比；同一行 y 单一源⇒`TB_ROW_TXT_DY`；判据读真实控件顶边；★别用 FontString 高度算中心⇒配反向哨兵。
- ★自绘风格两步：① 先问能否借用官方件（`UnitPopupMenus`/`UnitPopupButtons`）但必须先取证；② 不成则半透明底、宽度上限 ≤4 汉字＝62px、条目 ≤4 字、保留原有入口。
- ★多段一行居中（弹窗「接收方案」勾选）：与配置窗同一开关同一真值＋弹出时刷新；判据两段（生产数字验居中＋真实控件验落地）；标签宽实测优先 `GetStringWidth`、拿不到按字符数估（`string.len` 是字节）。
- ★导出 token、界面本地化＝同一份格式化＋一个开关：`EVAL_COND_STR(cd,disp)`/`EVAL_GROUP_STR(groups,disp)` 让界面走语言包、导出与往返一律 false⇒英文 token 逐字不变；读值口 `EVAL_TEST_SE_PREVIEW()`＋反向哨兵；组 125＋`DEBUFF DISPLAY CHECK`。
- ★职业着色＝描述表 `TB_PAINT_LISTS`＋painter＋三纯函数；包装＝先调原函数再叠色＋幂等守卫＋备份存 local；开关关掉＝不再叠色＋立刻重刷；禁用 `hooksecurefunc`；拿不到就不猜；组 119＋`PAINT WIRING CHECK`。
- ★★聊天窗名字着色：一个包装体管两功能（`EVAL_TB_CHAN_INSTALL_ONE`）不叠两层；覆盖所有窗（`ChatFrame1`＝`DEFAULT_CHAT_FRAME`，幂等按入口判、不按名字去重）；缓存唯一 `tbNameClass`；不做自动 /who（`SendWho` 等都是服务器查询）⇒查不到不上色；纯函数 `EVAL_TB_CHAT_COLOR_LINE` 拿不准就不碰；三坑：前 11 字节判富文本会染链接名·字符数≠字节数·`EVAL_SAY` 行不着色；颜色码长度禁写死（`|c%x+`）、诊断分开打（`EVAL_TB_CHATCOLOR_ROUTES`）；`CHAT COLOR WIRING CHECK`（先摘注释）；组 121①⑭。
- ★主动查询（四道闸门）：`TB_WHO_GAP=5s`、`TB_WHO_PEND=8s`、`TB_WHO_MISS_TTL=1800s`、`TB_WHO_QMAX=20`；查询日志只进调试日志（`EVAL_LOGLINE`⇒`/eh logdump`）；「查谁」更严：只认发送者位置的方括号名；`SendWho` 只许在 `tbWhoTick` 里。
- ★分享弹窗：摘要行⇒「X 分享的 [品阶秘籍·名]」带品阶色；品阶行只留图标、删重复文字、没连图标一起删（`EVAL_SHARE_SEAL_ROW` 被组 145 等用）；坐标 `SH_SEAL_ROW_Y` -50→-46·`SH_DETAIL_Y1` -74→-66·dPanel 顶 -46→-42；组 145；★改 UI 文案要同步反转旧判据。
- ★反应句方案名＝可点品阶色链接：`shReactionNameLink(p)` 造回 B 行同款 `<色>|HEHPF:<传输id> 0/1:1|h[<符号><品阶>秘籍·<名>]|h|r`；点它靠 `EVAL_SHARE_CLICK_OPEN("EHPF:<id>")` 在 `SH.recent` 找（用 `SH.pending.idh`）；超 `SH_MSG_MAX`/缺 id⇒退回纯名字；组 82⑤b＋⑦c＋`SH FUN CHECK`。
- ★彩蛋角色扮演反应：[导入]/[忽略] 按头衔档×收到品阶档从 50 格（5×5）抽奖式挑一句发来源频道（公会/说/队伍，`SH_FUN_CHAN`）；文案用嵌套表 `SH_FUN_IMP`/`SH_FUN_IGN`（每语言一键·前提 `L()` 能返回表）；每条恰 2 个 `%s`（发送者、方案名，顺序不能错）；组 82＋组 170＋`SH FUN CHECK`。
- ★彩蛋创世者亲临闸门：手动创建的方案有 ≥25 分神级 · 手动方案 ≥3 个 · 头衔满档 5；`src`：手工点写 `"manual"`、文本解析在唯一出口 `EVAL_PROFILE_FROM_TEXT` 盖 `"text"`、老存档无 `src`⇒按手动；堵两条路 `EVAL_TITLE_CREATOR_OPEN` 与 `EVAL_TITLE_CREATOR_TRY`；`EVAL_TITLE_EGG_CHECK()` 挂 `EVAL_WAR_TAB_REFRESH`＋登录、只播一次；组 169＋组 150/150⑥＋`CREATOR GATE CHECK`。
- ★★★队伍菜单三条条件（1.74.1，审计定案）：**邀请队伍** = 不在队伍 或 我是队长（修「队长反而邀不了人」的旧 bug）；
  **踢出队伍** = 我是队长 且 被右键的是队友（非队长根本不出现这条，不再是「点了才说不是队长」）；**离开队伍** = 在队伍内显示
  （退队不需权限，与右键的人无关，动作 `LeaveParty()`）。判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`；★助理踢人没有
  `IsRaidAssistant` 接口可判 → 如实接受边界（助理看不到这条，动作里仍有「不是队长」兜底）。成员判定 = `EVAL_TB_NAME_INMYGROUP`
  （UnitInParty/UnitInRaid 反查，party 只扫 1..4）。组 130⑥e/⑥e2/⑥e3 + 组 173 + ⑤b；变异 M564~M567 捕获。
- ★布局总纪律：需求验性质不验数字；相对量验相对量；同一行中线对齐；中文宽度按字符数估；布局常量单一源（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。


### 5.5 API 与客户端事实
- SpellStopCasting()：读条/自动射击/魔杖三类全覆；Protected→须 RunScript（直调无效）；「进度条没了」≠取消。
- AttackTarget()=Toggles 须 IsCurrentAction(攻击格)；Movement 仅 FollowByName/FollowUnit 非 Protected（MoveForwardStart/Stop、TurnLeftStart 是）；FollowByName 空名=当前目标、只搜已知玩家、无返回值、不走 RunScript。
- GetRaidRosterInfo(i) 九返回；越界/非团队只回 nil。
- 1370 API 无 aura 专用函数；GetPlayerBuff(i,f)=增益条 0 基下标；无文件读取 API（无 io/os）→载入文件唯一形式=列进 .toc。
- GetQuestReward 会再触发 QUEST_COMPLETE→须三层防护（同名去重/领取窗口闸门/全局频率上限）；UnitDebuff 第 3 返回=dispel token；UnitMana=主能量且有显示缩放（怒气÷10、幸福÷1000）→判蓝量前先 UnitPowerType(unit)==0。
- 施法 API 全 Protected（CastSpellByName 仅 onSelf/CastSpell/SpellTargetUnit/SpellStopTargeting/SpellStopCasting）；TargetUnit 非 Protected=唯一路径（切目标→UseAction(slot)→还原）；Targetting 另有 TargetLastTarget/ClearTarget/TargetByName/TargetNearestPartyMember。
- CHAT_MSG_PARTY_LEADER/CHAT_MSG_RAID_LEADER 独立事件→只注册 CHAT_MSG_PARTY/RAID 收不到（静默）；来源判据=触发事件名，发送侧只留 公会/队伍/说。
- 纹理路径=/Game/Interface/Icons/<名>_TEX，写错显 ?；GetNumMacroIcons/GetMacroIconInfo=唯一合法路径入口（1018 条 → doc/图标路径清单.txt）；PET ICON CHECK 校验真存在。
- IconSem.lua（用户要求：名称+多标签+按名/路径过滤）：基础名须剥 _TEX（组 117①b）；过滤=四命中+分组叠加；纹理字面量须在白名单（PET ICON CHECK）；两反斜杠须按两反斜杠匹配（组 112）。
- api_*.html=1370 条索引；无：GetDifficultyColor（有垫片）/PlaySoundFile（只有 PlaySound）/hooksecurefunc/UIDropDownMenu_GetSelectedID；有：GetGuildRosterInfo/GetWhoInfo/GetFriendInfo/GetNumGuildMembers/GetNumWhoResults/GetNumFriends/GuildControlGetNumRanks/GetRealZoneText/RemoveChatWindowMessages。

### 5.6 内容 / 数据质量
- 可驱散类型多选（用户要求：debuff/团队 debuff 多选）：cd.dt=nil/""/"any"/串/集合表，空集=任意；文本多选 (Magic/Poison)、单选 (Magic)；改动只在 dispelMatch+导出/解析（组 114）；互斥项须数据重算+整表重绘（组 114③）。
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

**关键源码检查在守什么（只列一句话判据；全清单见 `test_engine.js`）**
- `FRAME NAME CLASH CHECK`：21 个具名帧逐个与全部 `function NAME(` 比对
- `WTT ISOLATION CHECK`：禁 `local WTT = GameTooltip` + 必须自建 + 必须读自家 FontString + 必须有守卫与诊断（★扫描前先摘注释）
- `CHAT COLOR WIRING CHECK`：挂入口的「读回确认」+「幂等守卫」两条
- `COLOR CODE LEN CHECK`：禁 `"|c" .. string.sub(` 切码写法 + 职业色表逐项必须 8 位
- `SHARE MSG SHAPE CHECK`：逐条数字面量形态；`SHARE PALETTE CHECK`：色表逐项 8 位 + 命令必须引用四张色表 + 命令内不许出现字面色码 + 入口接线
- `MENU ROUND CHROME CHECK`：整数 `edgeSize` / 白色边框色 / 有 `GetBackdrop` 读回 / 有平边退化 / **禁调本客户端不存在的 `GetBackdropColor`**
- `TEMPLATE COUNT CHECK`：数 `examples/` 里以 `{ name = "` 开头的条目 == 4 处文档里的数字
- `WHEEL DIRECTION CHECK`：禁止「位移与方向同号」（写反会被断言的正确性掩盖）
- `EXAMPLES TOC CHECK` 四条 · `STOP ATTACK WIRING CHECK`（`skillNoSlotOk` 名单 7/7 + 接线 ≥3 处）· `PET ICON CHECK`（清单逐条 + `_TEX`）· `LANG KEY CHECK`（`L("字面量")` 三语言齐全）· `DECL ORDER CHECK`（9 个文件）· `PAINT WIRING CHECK` · `DEBUFF DISPLAY CHECK` · `CREATOR GATE CHECK` · `SH FUN CHECK` · `PROF ICON PROBE WIRING CHECK` · `UI TITLE BADGES` / `UI TIER BADGE` / `UI TITLEBAR` / `UI TITLE NAME CHECK`

## 六、§六 ~ §九 已移到同目录的 `CLAUDE_REFERENCE.md`（参考卷）

> ★**为什么**：工作区指令预算只有 **65,536 字节**，超出的部分 AI **完全读不到**（截断点落在文档中段）——
> 所以把「历史教训 / 仓库与文档 / 项目位置与现状 / 版本要点」这四节整卷移出去，本文件只留铁律与判据。
> ★**什么时候必须去读 `CLAUDE_REFERENCE.md`**：
> · **项目位置 / 文件结构 / 新增 .lua 模块要改哪几处 / toc 载入顺序 / 数据检索 Tab 设计** → 它的 §八
> · **工作流纪律**（默认不发版不推送 · 本地测试双绿可直接 commit · 推送需明确要求） → 它的 §八 末段
> · **历史教训**（local 作用域、合并冲突静默获胜、桩太宽松、对齐、API 真伪清单、官方文档核对） → 它的 §六
> · **官方 API 文档地址 / 待开发计划（免疫学习器等）/ 开源仓库内容清单** → 它的 §七
> · **某个版本做了什么（最近 10 版，一行一条）** → 它的 §九（完整历史看 `CHANGELOG.md`）
> · **当前版本**：以源码为唯一真值 —— `EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version`（搬移时 = **1.74.0**）。
