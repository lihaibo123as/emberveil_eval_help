# S_ChatBar 整合调研结论（原计划：子插件 EH_ChatBar · **已废弃**）

> **状态：暂停开发 · 子插件 EH_ChatBar 废弃**（用户 2026-10-09 决定：「暂停开发.废弃这个子插件」）
> **本文件 = 调研档案**，把**真机读数**与**落地清单**留档 ⇒ 将来若要恢复，**不必重跑那一轮探针**（脚手架与还原步骤见 §3）。
> 调研对象 = `tmp/S_ChatBar/`（`S_ChatBar.toc` + `ChatBar.lua` 1696 行 + `EasyChannel.lua` 220 行 + `Tracking.lua` 261 行，`SavedVariablesPerCharacter: S_ChatBarDB`，作者 Gustave 等，TurtleWoW 血统）。

---

## 1. 真机读数（2026-10-09 19:36，账号 LIHAIBOAS2，角色所在地：Duskwood 暮色森林）

来源 = 宿主只读探针 `/eh go 快捷栏`（已按本次决定收回，见 §3），读数落有界环 `cfg.chatbarProbe`，**存档 mtime 与命令时间戳相差正好 20 秒**（= 延后自动 `/reload` 落盘链路自证通过）。

### 1.1 ★本服到底有哪些频道（本次最核心的结论）

**口径**：频道 id **随加入顺序变化**，只能运行期现读；下表是**该角色当时的实况**。

| id | 客户端报的名字（**原文**） | 来源 | 状态 |
|---|---|---|---|
| **1** | `综合 - 暮色森林` | `GetChannelList` + 序号/按名两路交叉 | 已加入（聊天窗 1 订阅） |
| **2** | *（空串）* | 按名查 `交易` 命中 id=2、但返回名为空 | **编号占位：`GetChannelList` 与窗口订阅里都没有它 ⇒ 当前未加入** |
| **3** | `本地防务 - 暮色森林` | 同上 | 已加入 |
| **4** | `世界防务` | 同上 | 已加入（**服务端自定义频道**，不在 vanilla 默认四个之列） |
| **5** | `寻求组队` | 同上 | 已加入 |
| **6** | *（空串）* | 序号 6 报 id=6 名="" | 无名占位槽 |

**按名字查的命中情况**（`GetChannelName(名)`）：

- ✅ 命中：`综合`=1 · `交易`=2 · `本地防务`=3 · `世界防务`=4 · `寻求组队`=5
- ❌ **一个都没命中**：`General` · `Trade` · `世界` · `世界频道` · `world` · `World` · `中国` · `China` · `LocalDefense` · `defense` · `组队` · `LookingForGroup`

⇒ **本服没有「世界频道 / 中文频道」这类自定义大频道**（S_ChatBar 的「世」「中」两个按钮在本服无对应频道，它原逻辑会去 `JoinChannelByName("世界")` 硬加）。

⇒ **本服频道名带区域后缀**（`综合 - 暮色森林`）⇒ 名字匹配**必须走 `GetChannelName(名)` 的官方查找**；自己写全等比对（`string.lower(name) == "综合"`）**当场失效**。

### 1.2 聊天编辑框内部件（决定「13 个频道按钮」能否照搬）

| 项 | 读数 | 含义 |
|---|---|---|
| `ChatFrameEditBox` | **table** | 主路可用 |
| `ChatFrame1EditBox` | **nil** | 宿主 `Toolbox.lua` 那条 `_G.ChatFrameEditBox or _G.ChatFrame1EditBox` 兜底**在本机是死的**（主路在，无影响） |
| `editBox.chatType` | `SAY`（**读得到**） | ★核心机制成立 |
| `editBox.channelTarget` / `editBox.tellTarget` | `nil` / `nil`（字段存在，当前无值） | 同上 |
| `ChatFrameEditBox:GetScript("OnTabPressed")` | **function** | ★★**客户端自己挂了 Tab 处理体** |
| 全局 `ChatEdit_OnTabPressed` | **function** | 同上（vanilla 语义 = 密语对象循环 + `/命令` 补全） |

⇒ **结论**：S_ChatBar 那条原路（设 `chatType`/`channelTarget` + `ChatEdit_UpdateHeader`）**接口面齐全、成立**；
⇒ 但 **Tab 键频道循环绝不能直接 `SetScript` 覆盖**（会吃掉客户端原生 Tab 行为）⇒ 必须**链式保留 + 可关**。

### 1.3 FrameXML 全局体检（23 条：**20 在 / 3 不在**）

| ✅ 在 | ❌ 不在 |
|---|---|
| `ChatEdit_UpdateHeader` · `ChatEdit_GetLastTellTarget` · `ChatEdit_SendText` · `ChatEdit_OnTabPressed` · `ChatFrame_OpenChat` · `ChatFrame_SendTell` · `ChatFrame_AddChannel` · `ChatFrame_RemoveMessageGroup` · `ChatFrame_AddMessageGroup` · `SELECTED_DOCK_FRAME` · `ChatFrame_OnEvent` · `SetItemRef` · `DoEmote` · `GetDefaultLanguage` · `GetLanguageByIndex` · `AddChatWindowChannel` · `RemoveChatWindowChannel` · `EnumerateServerChannels` · `ListChannels` · `ListChannelByName` | **`ChatEdit_ActivateChat`** · **`ChatEdit_InsertLink`** · `RegisterAddonMessagePrefix` |

两条**顺带查明的既有隐患**（与本子插件存废无关，值得记一笔）：

1. **`ChatEdit_InsertLink` 不存在** ⇒ `EH_Bag`（`EH_Bag.lua:2513`）与 `unrealUI/professions.lua:291` 那两处「prefer `ChatEdit_InsertLink`」的写法在本机**永远走兜底路**（不是 bug，但说明那条分支是死分支）。
2. **`ChatEdit_ActivateChat` 不存在** ⇒ 宿主 `Toolbox.lua` 的「`ChatFrame_OpenChat` 失败 → 退回 `ChatEdit_ActivateChat` + 编辑框」**那条兜底在本机是死的**（主路 `ChatFrame_OpenChat` 在）。

### 1.4 原生下拉族：**7 个函数全在**（推翻项目旧判据）

```
UIDropDownMenu_Initialize = function · UIDropDownMenu_AddButton = function
UIDropDownMenu_SetText = function · UIDropDownMenu_SetSelectedID = function
UIDropDownMenu_Refresh = function · ToggleDropDownMenu = function
CloseDropDownMenus = function · UIDROPDOWNMENU_MAXBUTTONS = number
```

（`UIDropDownMenuTemplate` / `UIDROPDOWNMENU_OPEN_MENU` / `UIDROPDOWNMENU_MENU_VALUE` 报 nil 属正常：前者是 XML 模板名不是全局，后两者只在菜单打开时才赋值。）

⇒ **确证**：`CLAUDE.md` §三.4 / `Toolbox.lua:1395` / `CLAUDE_REFERENCE.md:715` 那句「本客户端**没有** `UIDropDownMenu`」是**错判**。

**证据链（三条独立，均可复算）**：

1. **客户端自己的 Lua 报错栈**（真机运行记录，`…\Account\LIHAIBOAS2\SavedVariables\MobileDesignFix.lua`）：
   `…\Blizzard_TrainerUI\…:1766: in function 'initFunction'` → **`Interface\FrameXML\UIDropDownMenu.lua:50: in function 'UIDropDownMenu_Initialize'`**
2. **客户端崩溃转储里的 Lua 文件表**：`UIDropDownMenu.lua` / `UIDropDownMenu.xml` / `UIDropDownMenuTemplates.xml` 都在册。
3. **上面的探针三度确认**（7 函数 + `UIDROPDOWNMENU_MAXBUTTONS`）。

★**根因**：`api_*.html`（客户端 API 参考索引）**不收 FrameXML 函数** —— 连已确证可用的 `ChatFrame_OpenChat`、`ChatEdit_InsertLink`、`UIDropDownMenu_Initialize` 在索引里都查不到。
⇒ **判据（建议进记忆体）**：索引只能用于「客户端 C API 有没有」，**不能用来否证 FrameXML 函数的存在性**；判 FrameXML 一律真机探 / 读真机报错栈 / 读崩溃转储文件表。

### 1.5 帧存在性

`ChatFrame1 .. ChatFrame7` **全部存在**（我原先推测 `ChatFrame3` 可能 nil，**被实测推翻**）· `MiniMapTrackingFrame` = table。

### 1.6 两条方法论踩坑（探针自己留下的教训）

1. **`IsEventRegistered` 是全局函数、不是帧方法**：`pf:IsEventRegistered(ev)` 在本客户端**不存在**（探针的注册回读整列报 `?`）⇒ 回读要写 `IsEventRegistered(frame, ev)`（★且项目在案：它返 **`1` 不是 `true`**）。
2. **事件原文那轮没抓到有效样本**：20 秒窗口里只收到 2 条 `CHAT_MSG_CHANNEL_LEAVE`，且 `arg1/arg2/arg3` **全为空**（很可能来自 `/reload` 自身退频道）⇒ 「抓 `/roll` 文本格式 / 频道通知真名 / `CHAT_MSG_ADDON` 收包」这三条**仍未取证**（下次要么放长窗口 + 逐位摊开 `arg1..arg8`，要么请玩家顺手 `/roll` 一次）。

---

## 2. 落地清单（若将来恢复，按这份做）

### A 档 · 可照搬

| 功能 | 真机判据 | 要点 |
|---|---|---|
| 频道切换按钮 | §1.2 + `ChatEdit_UpdateHeader`/`SELECTED_DOCK_FRAME` 在 | S_ChatBar 原路成立；**按钮清单按 §1.1 重列** |
| 密语按钮 / 预填框 | `ChatEdit_GetLastTellTarget` · `ChatEdit_SendText` · `ChatFrame_SendTell` 在 | 照搬 |
| 按钮条锚点 | `ChatFrame1..7` 全在 | 照搬（仍留 `DEFAULT_CHAT_FRAME` 兜底） |
| 表情菜单 | `DoEmote` = function | 可走 `DoEmote`；`/dancespecial` 之类未必有对应表情 ⇒ **保留「填命令 + `ChatEdit_SendText`」兜底** |
| 原生下拉（配置/表情/追踪菜单） | §1.4 七函数全在 | 技术可照搬；**建议改走宿主 `EVAL_DD_OPEN`**（多列/搜索/滚动/观感统一），原生留兜底 |
| 就位确认 | `DoReadyCheck`（索引 Group 类） | 照搬（宿主已有「就位**自动确认**」，发起 ≠ 确认，不冲突） |
| Roll 骰子 / 倒计时 | 聊天窗 1 消息组含 `SYSTEM` ⇒ `/roll` 文本进得了窗 | **发送侧必须改**（见 B 档） |

### B 档 · 必须重写

1. **Tab 键频道循环** ★最高风险：客户端自挂 `OnTabPressed`（§1.2）⇒ **链式保留 + 可关**，关掉还原原生。
2. **`SendChatMessage`** 全改 `RunScript` + 限频队列（Roll 播报 / 倒计时 / `RAID_WARNING`）。
3. **`CastSpellByName`**（追踪菜单）改 `UseAction(槽)` 或 `RunScript`（项目 TRK 已定案）。
4. **`C_Timer.After` 不存在** ⇒ 自建延迟帧（S_ChatBar 在 `PLAYER_LOGIN` 里那句会中断该分支）。
5. **每帧常驻的 `rollDetectFrame:SetScript("OnUpdate")`** ⇒ 改「用时才挂、不用**真摘**」（项目第一原则）。
6. **`ChatEdit_ActivateChat` / `ChatEdit_InsertLink` 不存在** ⇒ 别照抄那两条兜底。
7. `processString` 等**全局名收进 local**；存档改 `EH_CHATBAR_CFG`（子插件记忆体分离：不碰 `EVAL_HELP_CONFIG`/`EVAL_HELP_CHAR`）。
8. 通用事实：**回读事件别用帧方法**（见 §1.6①）。

### C 档 · 直接砍

- **15 个第三方插件启动器按钮**（Meeting/LFT · RaidProgress · XyTracker · AtlasLoot/InstanceJournal · SuperMacro · ActionBarProfiles · Outfitter · TrinketMenu · RaidCheck · SpiritSenseRec · BetterCharacterStats · AutoMarker · Automaton · SilverDragonRadar · CatPotion）—— 目标插件在本机**一个都没装**（游戏 `AddOns` 只有 `EvalHelp` + 4 个 `EH_*` + `MobileDesignFix` + `UnrealQuest` + `unrealUI`）。
- **「世」「中」两个频道按钮**（§1.1：本服无此频道）。
- pfUI / WIM 互操作 · `ToggleFrame` · `message()` · `IsTurtleServer()`（`GetBuildInfo` 版本号判乌龟服在本机无意义）· Turtle 专属战场区名表（`阳光林地/血环竞技场/荆棘峡谷`）。

### 恢复时仍待真机验证（两条）

| # | 待验 | 兜底方案 |
|---|---|---|
| 1 | 切频道**写进去是否真生效**（`editBox.chatType="CHANNEL"` + `channelTarget=id` + `ChatEdit_UpdateHeader`）—— 「读得到」≠「写进去客户端照做」 | 子插件自带**有界取证环**（记原 `chatType` → 写 → 读回）；无效则退回 `ChatFrame_OpenChat("/N ")` 那条路 |
| 2 | `/roll` 真实文本格式（Roll 统计正则） | 命令自带专属环记原文；玩家 `/roll` 一次后 AI 读存档 |

★**已用设计绕开的一条**：`GetChatWindowChannels` 的返回顺序与 `GetChannelList` **相反**（前者返回「名,id」、后者「id,名」，且未加入的给 0）—— 落地**不必用它**（只用 `GetChannelList` + `GetChannelName`）⇒ 无需再测。

---

## 3. 脚手架：已收回 + 在哪 + 怎么装回

**收回时间**：2026-10-09（用户宣布废弃之后）。**收回判据 = `tools/Probes.lua` 对 HEAD 的 `git diff` 为空**（逐字节一致）。

| 从哪来 | 内容 | 备份文件（`tmp/chatbar_backup/`） |
|---|---|---|
| `tools/Probes.lua` | `PR["CHATBAR"]` 整块（含文件头注释，234 行） | `Probes_CHATBAR_block.lua` |
| `EvalHelp.lua` | `/eh go 快捷栏` / `go chatbar` 别名分支（9 行） | `EvalHelp_alias_branch.lua` |
| `Core.lua` | `LOAD_RESIDUE_KEYS` 里的 `"chatbarProbe"`（7 行） | `Core_residue_key.lua` |

**装回三步**（每份备份文件的第一行都写了「插回位置」）：

1. `Probes_CHATBAR_block.lua` 的内容插回 `tools/Probes.lua` 末尾、**紧接最后一行 `end` 之后、`-- 载入期到此结束…` 之前**（去掉备份文件第一行的「插回位置」注释）。
2. `EvalHelp_alias_branch.lua` 的内容插回 `/eh` 链里、**`elseif msg == "go 频道"` 那一支之前**。
3. `Core_residue_key.lua` 的内容插回 `Core.lua` 的 `LOAD_RESIDUE_KEYS` 表尾（`"shotEvProbe",` 之后、`}` 之前）。
4. 然后：`node luacheck.js`（要 `SYNTAX OK`）+ `node sync_game.js`。★子插件形态还要做宿主契约①的 5 处（`addons/EH_ChatBar/` · `Toolbox.lua` 的 `SUBADDONS` · 三语 `SUB_*` 键 · `probe_localorder.js` 清单 · `tmp/*_harness.js` + `tmp/*_wiring_check.js`）。

**同目录还有**：`chatbar_probe_harness.js`（探针的 fengari 离线真跑闸门，18 条断言，含「只读哨兵 = 0 写入」/「延后重载只到点触发一次」）· `read_chatbarprobe.js`（AI 侧读存档脚本，按数字键序排）· `chatbar_rollback.js` / `chatbar_verify.js` / `chatbar_restore_tail*.js`（本次收回用的三个一次性脚本）· `ROLLBACK.md`（备份清单）。

**仍在 `tmp/`（与子插件无关，可复算本次 API 结论）**：`scb_api_check.js` · `scb_api_check2.js` · `scb_api_entries.js` · `scb_chan_api.js` · `scb_dmp_names.js` · `scb_dd_evidence.js` · `scb_tbrows.js` · `scb_aliases2.js` · `scb_pak_scan.js`（★最后这一个的结论**无效**：pak 内容被压缩，连已确证的 `ChatFrame_OnEvent` 都搜不到，不能作否证）。
