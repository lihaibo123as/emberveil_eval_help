# TurtleMail 插件 API 支持度调研（EmberVeil 客户端）

> **状态：离线调研 ✅ + 真机实测 ✅（2026-10-09 · 账号 LIHAIBOAS2）**。产出 = 本文件 + `tmp/tm_*.js` 一整套**可复算**的只读脚本 + `tmp/tm_api_index.json` / `tmp/tm_cross.csv` / `tmp/tm_probe_names.txt` + 真机探针子插件 `addons/EH_Mail/`（v0.1.1）。
> ★★**真机一句话结论 = 「114 项，缺 0」**：`FUNC` 那 **10 个 FrameXML 挂钩全局全部在** ⇒ **R1 排除**；`$parent` 派生名 8 个全在（含原先因「基础 MPQ 查不到」被怀疑的 `SendMailMoneyGold/Silver/CopperRight`）⇒ **R4 排除**；`FriendsFrameTabTemplate` + `PanelTemplates_SetNumTabs` 都在、`MailFrameTab3` 本来由插件自带 XML 定义 ⇒ **R3 排除**。
> ★★★**唯一实测到的真问题 = 区域下标越界（§6 R11）**：`SendMailMoneyGold/Silver/Copper` 的 `GetRegions()` 实测**各只有 4 个**，而源码取 **`[9]`** ⇒ nil 索引，且这三行**没有 `pcall`**、位于 `ADDON_LOADED → sendmail_load()` 里 ⇒ 会**整段中断后面 3 个 load**。**移植前必须先改这三行。**
> **调研对象** = `tmp/TurtleMail/`（TurtleWoW 血统的邮箱增强插件 · 「小疯子修改版」`2026.10.9.11`，另有同内容压缩包 `tmp/TurtleMail小疯子修改版10.9.zip`）。
> **一句话问题**：这个插件搬到 EmberVeil 客户端，API 层面能不能跑、会在哪儿坏。

---

## 0. 结论速览（三句话）

| 层 | 支持度 | 依据 |
|---|---|---|
| **客户端 C API（Lua 函数）** | ✅ **全支持** | 用到的 **49 个**客户端函数**逐个都在** EmberVeil 官方 API 索引（`api_*.html`，去重 1329 条）里；**邮件类 31 条一条不缺**（含 `GetInboxInvoiceInfo` / `GetNumPackages` / `SelectPackage` / `GetStationeryInfo` 这些 1.12 原生件） |
| **FrameXML / 具名帧**（真正决定成败的一层） | ✅ **真机实测通过：114 项 / 缺 0** | 判据 = `addons/EH_Mail/` 真机探针（2026-10-09）。**10 个 FrameXML 挂钩全局**逐个 `type()=="function"` 全部命中 ⇒ **R1 排除**；`$parent` 派生名 8 个全在 ⇒ **R4 排除**；模板与页签前提全在 ⇒ **R3 排除**。§2 那四条离线边界至此**全部被真机越过**（点名要看的就是它们） |
| **总体判断** | **能跑；但有一条已实测的必修项（R11）** | 客户端**名字层一个不缺**；**唯一真问题 = 区域下标**：`SendMailMoneyGold/Silver/Copper` 的 `GetRegions()` 实测 **N=4**，源码却取 **`[9]`** ⇒ 越界 nil、**无 `pcall`**、跑在 `ADDON_LOADED → sendmail_load()` 里 ⇒ 中断其后 3 个 load |

**⇒ 结论：可以动手移植，但第一步必须先把 §6 R11 那三行改掉**（包 `pcall`，或按 `#GetRegions()` 判可及再写）—— 否则插件一载入就红字，而且日志面板 / 批量取件 / 皮肤三块**全都不初始化**。

★ 顺带一条**只读事实**：客户端确实**没有** `SendMailStationeryButton` 这个帧（探针首轮报的唯一「缺失」项），但它在 TurtleMail 源码里**零引用**（只有 `StationeryBackgroundLeft/Right` 两个背景纹理，实测都在）⇒ 与移植无关，v0.1.1 起已从名单移出，事实记在 `addons/EH_Mail/CLAUDE.md`。

---

## 1. 调研对象构成

| 文件 | 规模 | 作用 |
|---|---|---|
| `TurtleMail.lua` | 2901 行 / 108 KB | 主实现：邮件分类/日志/批量取件/退信/删除、收件箱多选、写邮件多附件（**一封一个附件，连发 N 封**）、自动补全、日历、`/tm` 命令 |
| `TurtleMail.xml` | 880 行 / 28 KB | **自己重建**一大批邮件 UI 件：`MailFrameTab3`（第 3 个页签「Log」）、`MailAttachment1..21`（多附件格）、`MailAutoCompleteBox/Button1..5`、`TurtleMailLog*` 日志面板、批量按钮、`SendMailCODAllButton`、`MoneyReceived`、`TurtleMailAuctionIcon1..7`、`TurtleMailReturnedArrow1..7` |
| `Calendar.lua` | 292 行 | 日志筛选用的日历/日期下拉 |
| `MailTo.lua` | 137 行 | 收件人历史下拉（`UIDropDownMenu` 族） |
| `pfui-skin.lua` | 236 行 | **pfUI 美化**（外部插件，本机没有 pfUI，见 R8） |
| `localization.lua` / `localization.cn.lua` | 33 / 73 行 | 英文 / 中文（本客户端 zhCN ⇒ 走中文） |
| `TurtleMail.toc` | — | `## Interface: 11200`（与 `EvalHelp.toc` / `UnrealQuest.toc` **一致** ⇒ 版本号没问题） |

---

## 2. 方法与判据口径（**四条边界，先记住再看下面的表**）

1. **`api_*.html` 只能判「客户端 C API 有没有」，不能判 FrameXML**
   （本项目在案：连已确证可用的 `ChatFrame_OpenChat` / `UIDropDownMenu_Initialize` 在索引里都查不到 —— 见 `doc/S_ChatBar-整合调研结论.md` §1.4）。⇒ 判 FrameXML 一律**真机探 / 真机报错栈 / 崩溃转储**。
2. **客户端 `Content/Paks/*.ucas` 内容是压缩的**：原始字节扫描**连已确证的 `ChatFrame_OnEvent` 都搜不到** ⇒ 搜不到**不能**当否证（在案脚本 `tmp/scb_pak_scan.js` 的无效结论）。
3. **崩溃转储只能「证实」不能「否证」**：本轮自校验里，三个**已确证存在**的正对照（`ChatFrame_OpenChat` / `UIDropDownMenu_Initialize` / `ChatFrame_OnEvent`）在 65 个转储里**0 命中** ⇒ 转储只抓了部分内存页，**没命中 ≠ 不存在**（`tmp/tm_dmp_probe.js` 输出即证据）。
4. **`tmp/mpq_out/` 是「同血统旁证」、不是本客户端**：它是从 **TurtleWoW `Data\interface.MPQ`（基础 MPQ，不含 `patch-*.MPQ`）** 解出的 FrameXML（脚本 `tmp/probe_framexml.js`），**另一台客户端 + 可能是旧版本**。用它只能判「这个名字是不是原版 1.12 血统的标准名」，**不能判 EmberVeil 有没有**。
   ★ 本轮就踩到一次它的边界：`SendMailMoneyGoldRight/SilverRight/CopperRight` 在基础 MPQ 里**查无此名**，而插件显然在正常使用它们 ⇒ 那个名字应当来自**补丁层 MPQ**（本机没解）。**故「mpq_out 里没有」≠「客户端没有」。**

> 复算脚本（全部只读、不写游戏目录）：`tmp/tm_api_dump.js`（导出索引）· `tmp/tm_usage2.js` / `tmp/tm_surface.js`（抽接口面）· `tmp/tm_cross.js`（三向对照）· `tmp/tm_c2.js` / `tmp/tm_c3.js`（把「查无此名」逐个定性）· `tmp/tm_tally.js`（计数）· `tmp/tm_dmp_probe.js` / `tmp/tm_dmp2.js` / `tmp/tm_dmp_strings.js` / `tmp/tm_dmp_ctx.js` / `tmp/tm_dmp_files.js`（转储取证）· `tmp/tm_probe_names.js`（生成真机探针名单）。

---

## 3. C API 层：**49 个函数全部命中**（按官方索引分类）

> 口径：只要在 `api_*.html` 索引里出现就算「本客户端文档承认有」。**全部 49 个都在。**

| 分类 | 函数 |
|---|---|
| **Mail（16）** | `CheckInbox` `ClickSendMailItemButton` `DeleteInboxItem` `GetInboxHeaderInfo` `GetInboxInvoiceInfo` `GetInboxItem` `GetInboxNumItems` `GetInboxText` `GetSendMailItem` `GetSendMailPrice` `ReturnInboxItem` `SendMail` `SetSendMailCOD` `SetSendMailMoney` `TakeInboxItem` `TakeInboxMoney` |
| **Container（6）** | `GetContainerItemInfo` `GetContainerItemLink` `GetContainerNumSlots` `PickupContainerItem` `SplitContainerItem` `UseContainerItem` |
| **Cursor（2）** | `ClearCursor` `GetCursorPosition` |
| **System（6）** | `GetLocale` `GetRealmName` `GetTime` `IsAltKeyDown` `IsControlKeyDown` `IsShiftKeyDown` `PlaySound` |
| **Trading（2）** | `ClickTradeButton` `GetTradePlayerItemLink` |
| **Item（2）** | `GetItemInfo` `GetItemQualityColor` |
| **Friend/Guild（4）** | `GetFriendInfo` `GetNumFriends` `GetGuildRosterInfo` `GetNumGuildMembers` |
| **Unit（2）** | `UnitFactionGroup` `UnitName` |
| **Addon（2）** | `GetAddOnMetadata` `IsAddOnLoaded` |
| **Character / Settings / Frame（3）** | `GetMoney` `GetCVar` `CreateFrame` |
| 辅助（Helpers） | `date` `time` `getglobal` |

**专项核对（邮件 31 条索引全貌）**：`api_*.html` 的 Mail 类共 31 条 = 上表 16 条 + `ClearSendMail` `CloseMail` `GetCoinIcon` `GetNumPackages` `GetNumStationeries` `GetPackageInfo` `GetSelectedStationeryTexture` `GetSendMailCOD` `GetSendMailMoney` `GetStationeryInfo` `HasNewMail` `InboxItemCanDelete` `SelectPackage` `SelectStationery` `TakeInboxTextItem` —— 这是**完整的一整套 1.12 邮件 API**（TurtleMail 只用其中 16 条，其余可用作改造余量）。
★ **索引里这些条目都没有 Protected 行** ⇒ 插件可直调；只有 `SendChatMessage`/`SpellStopCasting`/`ReloadUI`/`LoadAddOn` 这类才是 Protected（与邮件无关）。
★ **widget 方法另计 71 个**（`SetPoint` / `SetText` / `SetScript` / `GetRegions` / `CreateTexture` …）—— 全是 1.12 标准件，本项目**已在真机大量验证**。

---

## 4. FrameXML / 具名帧层（**这是唯一风险面**）

### 4.1 依赖全景（四族 + 挂钩点）

| 族 | 数量 | 说明 | 本机证据状态 |
|---|---|---|---|
| **具名帧 / 纹理**（`_G[名]`） | ~45（客户端侧） | `MailFrame` `InboxFrame` `SendMailFrame` `OpenMailFrame` `MailFrameTab1/2` `MailItem1..7` `SendMailNameEditBox` `SendMailSubjectEditBox` `SendMailBodyEditBox` `SendMailMoney` `SendMailMoneyGold/Silver/Copper` `SendMailMoneyText` `SendMailCODButton` `SendMailPackageButton` `SendMailMailButton` `SendMailScrollFrame` `SendMailScrollChildFrame` `SendMailSendMoneyButton` `SendMailCODButtonText` `SendMailCostMoneyFrame` `MailFrameTopLeft/TopRight/BotLeft/BotRight` `StationeryBackgroundLeft/Right` `InboxTitleText` `OpenMailDepositMoneyFrame` `OpenMailMoneyButton` `OpenMailPackageButton` `OpenMailReplyButton` `OpenMailBodyText` `OpenMailSender` `OpenMailSubject` `OpenMailScrollFrame` `UIPanelWindows` `UISpecialFrames` `DEFAULT_CHAT_FRAME` `GameTooltip` `WorldFrame` `TradeFrame` `SlashCmdList` | 部分**转储实证**：`MailFrame` `SendMailFrame` `TradeFrame` `MailItem1` `SendMailMoney` `GameTooltip` `WorldFrame` `UIPanelWindows` 命中；★`InboxFrame`/`OpenMailFrame` 及大部分子件**未命中 ≠ 没有**（§2 边界 3）。<br>★ EvalHelp 自家也有两处在**用**邮件帧（`addons/EH_Bag/EH_Bag.lua:5002-5013` 右键直投写邮件页、`tools/DragFrames.lua:243/318` 的「邮箱」拖拽目标），但**两处都是 `type()`/`rawget` 守卫 + 失败静默降级** ⇒ 只能算「代码在用」，**不能**当作「真机验收过」的证据（真机存档 `SavedVariables\EvalHelp.lua` 里的 `MailFrame` 只是 DragFrames 的**全量候选快照**，不含存在性信息） |
| **FrameXML 全局函数** | 14 + 挂钩 10 = ~19 | 见 4.2 | `SendMailFrame_CanSend` **转储实证**；`PanelTemplates_*` / `UIDropDownMenu_*` **有间接实证**（见 4.2 表末两行） |
| **全局字符串常量** | 22 | `AMOUNT_TO_SEND` `COD_AMOUNT` `EMPTY` `INBOX` `INBOXITEMS_TO_DISPLAY` `ITEM_OPENABLE` `NO_ATTACHMENTS` `ERROR_CAPS` `GRAY_FONT_COLOR` `NORMAL_FONT_COLOR` `ERR_INV_FULL` `ERR_ITEM_MAX_COUNT` `ERR_MAIL_REACHED_CAP` `ERR_MAIL_TARGET_NOT_FOUND` `ERR_MAIL_TO_SELF` `ERR_PLAYER_WRONG_FACTION` `AUCTION_SOLD/REMOVED/WON/OUTBID/EXPIRED_MAIL_SUBJECT` | 只有 `NORMAL_FONT_COLOR` 转储命中；**全部是原版 `GlobalStrings.lua` 的标准键**（同血统旁证）= 本层「未证但风险低」（缺一个只影响一行文案，见 R5） |
| **XML 模板**（`inherits=`） | 6 | `UIPanelButtonTemplate` `UIPanelScrollFrameTemplate` `UIDropDownMenuTemplate` `OptionsCheckButtonTemplate` `FriendsFrameTabTemplate` `UIPanelButtonHighlightTexture`；另加字体对象 `GameFontNormal/Highlight/Disable/DisableSmall` `NumberFontNormal` | `UIDropDownMenuTemplate` **转储命中**；字体对象里 `NumberFontNormal` 被本机插件 `EH_Damage` 真机使用 ✓、`UIDropDownMenu.lua` / `UIDropDownMenuTemplates.xml` / `UIPanelTemplates.lua` **都在转储的文件名表里** ⇒ 这两个模板族可用 |
| **挂钩点（16）** | 见 4.2 | 装在 `PLAYER_LOGIN`，**无守卫** | 见 R1 |

### 4.2 挂钩点（16 个）——**这是本插件最硬的契约**

安装代码在 `TurtleMail.lua:679-682`：

```lua
for k, v in m.hooks do
  m.orig[ k ] = m.api[ k ]      -- m.api = getfenv()（第 95 行）= 全局环境
  m.api[ k ] = v                -- 无条件覆盖
end
```

★★★ **关键点：`m.orig[k]` 没有 nil 守卫** ⇒ 只要某个全局**不存在**，`m.orig[k]` 就是 `nil`，而包装体里全是 `m.orig.X(...)`（例：`TurtleMail.lua:1719` `return m.orig.GetInboxHeaderInfo( unpack( arg ) )`、`:1728` `m.orig.InboxFrame_Update()`、`:622` `m.orig.ClickSendMailItemButton()`）⇒ **缺一个就是运行时红字**，不是静默降级。

| # | 挂钩全局 | 归属 | 本机证据 |
|---|---|---|---|
| 1 | `ClickSendMailItemButton` | C API（索引里有；`ContainerFrame.lua` 也在引用） | ✅ 索引命中 |
| 2 | `GetContainerItemInfo` | C API | ✅ 本项目到处在用 |
| 3 | `GetInboxHeaderInfo` | C API | ✅ 索引命中 |
| 4 | `PickupContainerItem` | C API | ✅ 本项目到处在用 |
| 5 | `SplitContainerItem` | C API | ✅ 索引命中 |
| 6 | `UseContainerItem` | C API | ✅ 本项目到处在用 |
| 7 | `InboxFrame_OnClick` | **FrameXML（`MailFrame.lua`）** | 转储未命中（≠没有） |
| 8 | `InboxFrame_Update` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 9 | `InboxFrameItem_OnEnter` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 10 | `MailFrameTab_OnClick` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 11 | `OpenMail_Reply` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 12 | `OpenMailFrame_OnHide` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 13 | `SendMailFrame_CanSend` | **FrameXML（`MailFrame.lua`）** | ✅ **转储实证**：转储里有 `SendMailFrame_CanSend();`（= 客户端 `MailFrame.xml` 的脚本片段原文） |
| 14 | `SendMailFrame_Update` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 15 | `SendMailRadioButton_OnClick` | **FrameXML（`MailFrame.lua`）** | 转储未命中 |
| 16 | `UpdateUIPanelPositions` | **FrameXML（`UIParent.lua`）** | 间接实证：转储有 `UIParent.lua` 文件名；且 `SavedVariables\MobileDesignFix.lua` 的真机报错栈里就写着 `Interface\FrameXML\UIParent.lua:600: in function 'UIParent_OnEvent'` |

★★ **第 7~15 号全部定义在同一个文件 `MailFrame.lua`**（已用 `tmp/mpq_out` 全树逐名核对）；而该文件不是被 toc 单独列的，是由 **`MailFrame.xml` 第 3 行 `<Script file="MailFrame.lua"/>`** 拉起的 ⇒ **「客户端装载了 `MailFrame.xml`」这一条实证，等价于「这 9 个函数可用的概率很高」**（客户端自己的邮件窗要能工作就必然装载它）。这就是 §0 那句判断的全部依据 —— **是强推断，不是实测**。

### 4.3 其它 FrameXML 全局（非挂钩，14 个）

| 名字 | 定义处（同血统） | 本机证据 |
|---|---|---|
| `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab` | `UIPanelTemplates.lua` | ✅ 转储**文件名表**里有 `UIPanelTemplates.lua` + `.xml` |
| `UIDropDownMenu_Initialize/AddButton/SetText/SetWidth`、`ToggleDropDownMenu`、`CloseDropDownMenus` | `UIDropDownMenu.lua` / `UIDropDownMenuTemplates.xml` | ✅ 转储文件名表里有这两份；`ToggleDropDownMenu`/`CloseDropDownMenus` 直接命中；**且 `doc/S_ChatBar-整合调研结论.md` §1.4 已真机实测「7 个下拉函数全在」**（推翻旧判据） |
| `UpdateUIPanelPositions` / `MouseIsOver` | `UIParent.lua` | 见 4.2 #16 |
| `MoneyFrame_Update` | `MoneyFrame.lua` | 未证（原版标准名） |
| `MoneyInputFrame_GetCopper` / `MoneyInputFrame_ResetMoney` | `MoneyInputFrame.lua` | 未证（原版标准名） |
| `SetItemRef` 之类 | — | 本插件**不用** |

---

## 5. 「查无此名」逐条定性（**没有一条是真缺失**）

静态扫出 265 个「不在 API 索引」的名字，逐个定性后：

| 类 | 数量 | 结论 |
|---|---|---|
| 本插件自有（`TurtleMail.xml` 的 `name=` / `CreateFrame` 具名 / Lua 内 `function`） | ~124 | **不是客户端依赖**（如 `MailAttachment1..21`、`MailAutoCompleteBox`、`MailFrameTab3`、`TurtleMailLog*`、`MoneyReceived`、`SendMailCODAllButton`、`MailHorizontalBarLeft/Right`（第 2079/2085 行自己 `CreateTexture`）、以及 `MailTo_*` / `Calendar.lua` 的内部函数） |
| XML 的 `$parentXxx` 占位（`$parentButton`/`$parentLeft`/`$parentText`…） | 20 | XML 语法件，运行期由客户端展开，**不需要探** |
| **`$parent` 派生名**（静态 grep 天生看不见，**运行期才存在**） | 8 | `SendMailMoneyGold/Silver/Copper` ← `MoneyInputFrame.xml` 的 `name="$parentGold/Silver/Copper"`；`SendMailNameEditBoxMiddle/Right`、`SendMailMoney*Right`、`SendMailCODAllButtonText` 同理（模板 `$parent` 展开）。★**这 8 条必须真机探**（R4） |
| 外部插件 / 存档键 | `pfUI` `pfUI_config` + `TurtleMail_*` 一批 | `TurtleMail_*` 是 `## SavedVariables` 声明的存档全局（正常）；`pfUI` 有**完备守卫**（见 R8） |
| **真·查无任何定义** | **0** | — |

---

## 6. 风险清单（按「会不会坏 / 坏成什么样」分级）

> 这一节是本次调研**最该被复用的部分**：每一条都写清 **锚点 + 缺失后的症状**。

### R1 ✅ **已排除**（真机实测 2026-10-09）—— 10 个 FrameXML 挂钩全局
- **锚点**：`TurtleMail.lua:679-682`（无条件覆盖）+ 15 处 `m.orig.X(...)` 调用。
- **离线时的担心**：`attempt to call field 'X' (a nil value)` —— 一开邮箱/一收信就红字，**部分路径连原生邮件窗都受影响**（因为我们替换了原生处理体）。
- **★真机结果**：这 10 个**全部 `type()=="function"`，缺 0** —— `SendMailFrame_CanSend` / `SendMailFrame_Update` / `SendMailRadioButton_OnClick` / `InboxFrame_Update` / `InboxFrame_OnClick` / `InboxFrameItem_OnEnter` / `MailFrameTab_OnClick` / `OpenMail_Reply` / `OpenMailFrame_OnHide` / `UpdateUIPanelPositions` ⇒ 原推断（它们都定义在 `MailFrame.lua`，而该文件被客户端装载）**成立**。
- **判据**：探针 `FUNC` 组前 10 项 + 真机读数。

### R2 ★★★ `sendmail_load()` 里三处「按区域序号/按名字取件」的版本脆弱点 —— **真机逐条实测**
| 行 | 代码 | 真机实测（2026-10-09） |
|---|---|---|
| `:2096/2100/2104` | `m.api.SendMailMoneyGoldRight:SetPoint(...)`（`SilverRight`/`CopperRight` 同款） | ✅ **三个名字都在** —— 离线时「基础 MPQ 查不到 ⇒ 可能没有」的怀疑被实测推翻（它们是**补丁层 MPQ** 里的名字，正是 §2 边界 4 说的那种情形） |
| `:2097/2101/2105` | `({ m.api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" )` | ❌ **越界**：实测 `Gold`/`Silver`/`Copper` **各 N=4**，取 `[9]` = nil ⇒ `index a nil value`；**无 `pcall`** ⇒ 见 **R11**（本次唯一实测到的真问题） |
| `:580-586` | `({ SendMailPackageButton:GetRegions() })[1]:Hide()` / `[3]:Hide()` | ✅ 实测 `SendMailPackageButton` **N=3** ⇒ `[1]`/`[3]` 都够 |
| `:1858` | `({ m.api.SendMailScrollFrame:GetRegions() })[ 3 ]` | ✅ 实测 `SendMailScrollFrame` **N=3** ⇒ `[3]` 够（v0.1.1 起探针按「源码要取的下标」直接判可及） |
- **判据**：探针 `REGIONS` 组（v0.1.1 起 **6 条**，每条 = `{ 名字, 源码要取的最大下标 }`，直接报「**可及 / ★越界**」，且越界会**点名进落盘环 + 聊天第 2 行**）+ 真机开一次邮箱看有没有红字。

### R3 ✅ **已排除**（真机实测）—— `MailFrameTab3` + `FriendsFrameTabTemplate` + `PanelTemplates_SetNumTabs(MailFrame, 3)`
- **锚点**：`TurtleMail.xml:866` **自己建** `MailFrameTab3`（`inherits="FriendsFrameTabTemplate"`、`parent="MailFrame"`；★它本来就**不在客户端全局里**，缺它是正常的）；`TurtleMail.lua:664` 把页签数设成 3；`:590/592` 按日志开关 Show/Hide。
- **离线时的担心**：模板缺失 ⇒ **整个 XML 载入失败**（`inherits` 失败会让该文件报错）；`PanelTemplates_SetNumTabs` 缺失 ⇒ 第 3 个页签永远点不到（静默）。
- **★真机结果**：`FriendsFrameTabTemplate` ✅（`pcall(CreateFrame, …, 模板名)` 真建成）、`PanelTemplates_SetNumTabs` ✅ `function`、`MailFrameTab1/Tab2` ✅ 都在 ⇒ 前提齐备。
- **判据**：探针 `TEMPLATE` 组 + `FUNC`/`FRAME` 组。

### R4 ✅ **已排除**（真机实测）—— `$parent` 派生名（8 个，**静态一概看不见**）
`MailItem1Button`、`SendMailMoneySilver/Copper`、`SendMailMoneyGold/Silver/CopperRight`、`SendMailNameEditBoxMiddle/Right`。
- **★真机结果**：**8 个全部命中**。尤其 `*Right` 三个 —— 离线时它们在基础 MPQ 里**查无此名**（§2 边界 4），当时只能推「应当来自补丁层 MPQ」；真机证明它们**确实存在** ⇒ 那条边界判据是**被实证**的，不是被绕过的。
- **判据**：探针 `PARENT` 组（**必须运行期探**，已做）。

### R5 ★ 22 个全局字符串常量
缺一个的后果**只影响一行文案/一个判定**（唯一例外：`ITEM_OPENABLE` 与 `INBOXITEMS_TO_DISPLAY` 参与逻辑判定，缺了会让「可打开物品」判定失真）。
- **判据**：探针第 ② 组（`type(...) ~= "nil"`）。

### R6 ★ TurtleMail 会**顶掉几个客户端全局**（`MailMailButton`、`SendMailSubjectEditBox`、`MailSubjectEditBox`、`SendMailMailButton` 等）
- **锚点**：`TurtleMail.lua:2110-2120`（拿 `setmetatable({}, {__index = 空函数})` 顶掉原生全局，再自己派发）。
- **风险**：这是**故意行为**（绕开原生「自动设主题/禁用按钮」的怪代码）。在**没有同类邮件插件**的环境里没问题；**若本机再装一个改邮件窗的插件**（如 WIM 类、pfUI、unrealUI 的邮件皮肤）就会互相顶。
- ★ **本机 `Interface\AddOns.Disabled\unrealUI` 已停用**，`AddOns` 里当前没有邮件类插件 ⇒ 目前无冲突。

### R7 ★ 与 unrealUI（若启用）的层次/皮肤冲突
unrealUI 是**客户端皮肤框架**（另一台机器上与本项目无关）。若用户以后启用它并给它加了邮件皮肤，**R2 的区域序号假设**是最可能先坏的（改皮肤常动 region 顺序）。
- **判据**：启用 unrealUI 后重跑 §7 探针 + 看 R2。

### R8 ✅ pfUI 分支**已完备守卫**（无害）
`pfui-skin.lua:10-13`：`if not ( IsAddOnLoaded("pfUI") and pfUI and pfUI.api and pfUI.env and pfUI.env.C ) then return end`；`pfui_skin_enabled`（唯一置 true 处 = `pfui-skin.lua:20`）只在 pfUI 回调里才为真。
⇒ 本机没有 pfUI（用的是 unrealUI）⇒ 走「原版皮肤」分支，**这条依赖等于不存在**。

### R9 ✦ 事件层（9 个自注册事件）
`ADDON_LOADED` `PLAYER_LOGIN` `UI_ERROR_MESSAGE` `CURSOR_UPDATE` `BAG_UPDATE` `MAIL_SHOW` `MAIL_CLOSED` `MAIL_SEND_SUCCESS` `MAIL_INBOX_UPDATE`（`TurtleMail.lua:117`）。
- 事件名**不在 API 索引里**（索引不收事件）⇒ 离线不可判；但这 9 个**全是 1.12 标准事件**，其中 `MAIL_INBOX_UPDATE` / `MAIL_SHOW` / `MAIL_CLOSED` 就是邮件窗自身的事件（客户端邮件窗要用它们）⇒ 风险低。
- **判据**：探针第 ⑤ 组（`IsEventRegistered(frame, 名)` 回读；注意本项目在案：它返 **`1` 不是 `true`**）。

### R10 ✦ Lua 语言层
`getfenv()`（95 行，取全局环境）· `unpack` · `table.getn` · `string.gmatch`（注释里还专门写了「1.12 无 string.gfind」）⇒ 全是 **Lua 5.1** 用法，与本客户端一致（本项目已在 5.1 上跑了 1.75.x 全部功能）⇒ **无风险**。

### R11 ★★★ 区域下标越界 —— **本次唯一实测到的真问题**（2026-10-09 真机定案）
- **锚点**：`TurtleMail.lua:2097 / 2101 / 2105`（`({ m.api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" )`，Silver / Copper 同款）。
- **实测**：本客户端 `SendMailMoneyGold` / `Silver` / `Copper` 的 `GetRegions()` **各只有 4 个**区域；源码假定**至少 9 个**（作者在 TurtleWoW 上量到的口径）⇒ `[9]` = **nil** ⇒ `attempt to index a nil value`。
- **为什么这是「必修」而不是「一处红字」**：这三行是**裸 `do ... end` 块、没有 `pcall`**，且跑在 `ADDON_LOADED`（`:627`）→ `sendmail_load()`（`:667`）里；而 `:667` 之后还有 **3 个 load**（`m.log.load()` / `m.batch_load()` / `m.pfui_skin()`）⇒ **一处越界 = 整段中断**：日志面板、批量取件、皮肤三块**全部不初始化**（症状是「插件像半死」，而不只是某个按钮画错）。
- **改法（移植时二选一，别原样抄）**：① 三行各包 `pcall`；② 更稳 = 先判可及再写
  （`local rs = { f:GetRegions() }; if rs[9] then rs[9]:SetDrawLayer("BORDER") end`）。
  两者都要保留「**够就设、不够就跳过**」的语义，**不要**改成写死另一个下标。
- **判据**：探针 `REGIONS` 组报 `SendMailMoneyGold N=4 要取[9] ★越界`，聊天第 2 行点名（v0.1.1 起）；环里记 `区域下标越界：…`。
- **同类待防**：真正要防的是**其它**`[N]` 裸索引在**换皮肤**（unrealUI 邮件皮肤会重排 region）之后顺序变化 —— 见 R7；探针每次重跑都能把它们重新量出来。

---

## 7. 真机验证方案 = **已落地为 EH_Mail 子插件**（一条命令、零步骤、自己落盘）

> 按本项目铁律：玩家只做「**在 ⑦ 子插件 Tab 勾选 EH_Mail** → `/reload` → **敲一条命令** `/email`」，
> 其余（落盘、重载、读数）全由命令自己完成，**AI 自己去读存档**（`node tmp/read_ehmailprobe.js`），聊天框只回 3 行。
>
> **实现** = `addons/EH_Mail/`（**v0.1.1** 体检版，记忆体 = 该目录 `CLAUDE.md`）；离线判据 = `tmp/ehmail_harness.js`（行为，49 条）+ `tmp/ehmail_wiring_check.js`（接线结构钉，46 条）。
>
> ★★**首轮真机读数（2026-10-09 · 账号 LIHAIBOAS2）= 共 114 项 ｜ 缺 0 项**（落盘 `EH_Mail.lua` · `build 0.1.0` · 246 行环 / 历次 2 轮）。
> 唯一点名的「缺失」= `FRAME:SendMailStationeryButton`，而它**在 TurtleMail 源码里零引用** ⇒ 与移植无关，v0.1.1 起已移出名单。

**体检做的事（纯只读，114 项 = 109 个名字 + 5 个模板探针）**：
1. `FUNC` 22（FrameXML 全局函数；**前 10 个 = TurtleMail 的挂钩点**）· `FRAME` 46（具名帧）· `MISC` 7（辅助全局）· `CONST` 21（全局字符串常量）· `FONT` 5（字体对象）· `PARENT` 8（**`$parent` 派生名**，静态看不见）→ 逐个 `rawget(_G, 名)` / `type(...)`。
2. `TEMPLATE` 5 → `pcall(CreateFrame, "Frame", nil, UIParent, 模板名)`（**成功即模板在**；未知模板会抛错 ⇒ 如实判「不在」；建出来的帧当场 `Hide`、不留引用，并在聊天里报「探针临时帧 N 个」）。
3. `REGIONS` **6** → 每条 = `{ 名字, 源码要取的最大下标 }`，报 `#GetRegions()` 数字并**直接给结论**：`可及` / `★越界` / `判不出`（v0.1.0 只报数、不下结论 ⇒ 首轮得靠 AI 手工比对才看出 `[9] > 4`；v0.1.1 把它变成探针自己的判据）。
4. 结果进**自己的有界落盘环** `EH_MAIL_CFG.probe`（上限 260 行，最新在后，行格式 `类别 名字 结论 备注`）；
   聊天只回 3 行（结论 / 缺失点名 / 「6 秒后自动 /reload」+ 临时帧数）。
5. 末尾**延后 6 秒自动 `/reload`** 落盘（唯一节拍帧 `EH_MailTick` 到点执行 `RunScript("ReloadUI()")` 后**真摘**）。

**判读表**（AI 读到环后一眼定案）：

| 读数 | 结论 |
|---|---|
| 「缺 0 项」 | ✅ 名字层可直接用；**R1 / R3 / R4 结论 = 排除**（首轮实测即是此） |
| **`REGIONS` 里出现「★越界」** | ❌ **R11 必修**：那几行的裸索引 `[N]` 会在 `sendmail_load()` 里 nil 索引 ⇒ **中断其后 3 个 load**；改法 = 包 `pcall` 或先判可及 |
| 缺 `FUNC` 里任一挂钩全局 | ❌ R1 **必须打补丁**（加 `type()` 守卫 / 或放弃对应功能），否则一开邮箱就红字 |
| 缺 `SendMailMoney*Right` | ⚠️ R2：`sendmail_load` 会中断 ⇒ 写邮件页「半装修」；改法同上 |
| 缺 `FriendsFrameTabTemplate` | ⚠️ R3：第 3 页签「Log」/ XML 载入失败 |
| 缺 `PARENT` 组 | ⚠️ R4：按缺失点名定位到具体控件，逐个加守卫 |

**首轮真机 `REGIONS` 读数（原始）**：`SendMailMoney N=0（源码不读 region）` · `SendMailMoneyGold N=4 要取[9] ★越界` · `SendMailMoneySilver N=4 要取[9] ★越界` · `SendMailMoneyCopper N=4 要取[9] ★越界` · `SendMailPackageButton N=3 要取[3] 可及` · `SendMailScrollFrame N=3 要取[3] 可及`。

★ 名单来源 = `tmp/tm_probe_names.txt`（152 条含噪声 → 人工去噪成子插件里的 8 张表，**条数由 wiring check 现读钉住**：22/46/7/21/5/8/5 + REGIONS 6）。
★ 子插件**不写宿主存档**（`EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR` 命中 0 处，常驻闸门 `tmp/mem_sep_probe.js` 守着）。

---

## 7b. 移植已落地（0.2.0）—— 与上游的四处差异 + pfUI 剔除

> 用户 2026-10-10：「**pfui 相关的抛弃.只移植原始Ui的功能**」。

| # | 改动 | 为什么必须改（不改的后果） |
|---|---|---|
| ① | 插件名 `TurtleMail` ⇒ `EH_Mail`（`ADDON_LOADED` 的 `arg1`、`GetAddOnMetadata`） | 客户端发的 `arg1` 是**本插件真名** ⇒ 不改则初始化整段 `return`（**看着载入了、界面毫无变化**，最难查的一类） |
| ② | **R11**：三处 `[{ f:GetRegions() }][ 9 ]` ⇒ 「够才设」 | 载入期 nil 索引 ⇒ **中断其后 3 个 load**（日志 / 批量 / 皮肤全不初始化） |
| ③ | **pfUI 整条剔除**（皮肤文件 + XML 引用 + 3 处调用 + 显式 `= false`） | `m.pfui_skin` 随文件删除 ⇒ 留着就是 `attempt to call nil` |
| ④ | 自带素材路径 5 处 ⇒ `Interface\AddOns\EH_Mail\` | 目录名变了 ⇒ 三道贴图**静默画空** |

**移植形态**：保留原始文件名（XML 里 6 条 `<Script file>` **一字不改**）· 全部平铺在 `addons/EH_Mail/` ·
`EH_Mail.toc` 追加一行 `TurtleMail.xml`，且**排在体检探针 `EH_Mail.lua` 之后**
⇒ 万一 XML 整份载入失败，**诊断腿（`/email`）仍然活着**（否则连「为什么坏」都查不到）。

**移植前把未知项问完**（`tmp/tm_port_audit.js` / `audit2.js` / `audit3.js`，纯读）：
17 个 `inherits` 三分类 ⇒ **自建 6**（含 `MailAttachment ×21` —— 确认是插件自建、**不是**客户端依赖）·
**同血统标准 11**（其中 5 模板 + 5 字体已被真机验过；剩下的 `UIPanelButtonHighlightTexture` 与已验过的
`UIPanelButtonTemplate` 在 `UIPanelTemplates.xml` 里**同文件相隔 3 行** ⇒ 随它原子载入）· **两处都没有 0**
⇒ **移植前未知项 = 0**。另：自建 79 个具名帧里只有 `MailFrameTab3` 非 TurtleMail 前缀，而客户端本来就没有它 ⇒ **不撞名**。

**pfUI 剔除的口径（只删「不可达/必崩」，不逐处重写）**：十几处 `m.pfui_skin_enabled and <pfUI 值> or <原版值>`
**刻意保留** —— 另一半就是「原版保底值」，而 `m.pfui_skin_enabled = false` 让它们**恒走原版分支**；
4 处 `m.api.pfUI` 引用（1 处完整守卫 + 3 处短路三元）同样不动。

**判据**：`tmp/ehmail_wiring_check.js` 末段 **14 条移植版结构钉**（toc 顺序 / 存档键声明 / 插件名 2 + 反向 2 /
R11 + 反向 / pfUI 5 条 / 素材 2 + 3 个素材在）。
★★**移植版没有行为闸门**（第三方 3000 行 + 强依赖客户端邮件窗，离线跑不了）⇒ 行为对不对 = **真机载入一次看红字**。

---

## 8. 复算脚本与产物

| 脚本（`tmp/`） | 作用 | 产物 |
|---|---|---|
| `tm_api_dump.js` | 汇总 `api_*.html` 内嵌索引 | `tm_api_index.json`（**1329 条**去重） |
| `tm_usage2.js` / `tm_surface.js` | 抽接口面（`m.api.X` = 全局 X，因 `TurtleMail.api = getfenv()`） | 控制台 |
| `tm_cross.js` | 三向对照（插件引用 / TurtleWoW FrameXML / 崩溃转储） | `tm_cross.csv`（307 名） |
| `tm_c2.js` / `tm_c3.js` | 「查无此名」逐个定性（自有 / `$parent` / 外部 / 真未知） | 控制台 |
| `tm_tally.js` | 精确计数（49 API / 71 方法 / 10 个 FrameXML 挂钩） | 控制台 |
| `tm_probe_names.js` | 生成真机探针名单 | `tm_probe_names.txt` |
| `tm_dmp_probe.js` / `tm_dmp2.js` | 转储探针（**带正/负对照**，自证方法不可否证） | 控制台 |
| `tm_dmp_strings.js` | 转储字符串穷举（发现了 `SendMailFrame_CanSend()` 等） | 控制台 |
| `tm_dmp_ctx.js` | 命中点上下文（辨别「客户端 XML 原文」vs 别的来源） | 控制台 |
| `tm_dmp_files.js` | 转储里的 `*.lua/*.xml` 文件名表（**客户端 FrameXML 装载表的部分切片**） | 控制台 |

---

## 9. 结论与建议

1. **API 支持度：C API 层满分**（49/49）。这个插件**不需要**任何 EmberVeil 没有的客户端函数；它也不依赖 SuperWoW / Nampower / pfUI 之类的 TurtleWoW 专属增强（pfUI 有守卫、其余是原版）。
2. **能不能跑，取决于 FrameXML 那一层**，而这一层**离线判不了**（三条边界见 §2）。当前**正向证据足够多**（客户端装载原版 `MailFrame.xml` 已实证；9 个挂钩全局全在它拉起的 `MailFrame.lua` 里；`UIParent.lua`/`UIDropDownMenu.lua`/`UIPanelTemplates.lua` 都在转储文件名表里）⇒ **主流程可用的概率高**。
3. **风险集中在 4 处**：R1（10 个挂钩全局，缺一即红字）· R2（`SendMailMoney*Right` + `GetRegions()[9]/[1]/[3]` 的序号假设）· R3（第 3 页签依赖 `FriendsFrameTabTemplate`）· R4（8 个 `$parent` 派生名）。**这 4 处正好是探针要一次全查完的东西。**
4. **下一步（建议顺序）**：
   ① 跑 §7 探针（需实现，一条命令）；
   ② 若「缺 0 条」⇒ 这个插件可以直接用，无需改一行代码；只在需要「不依赖原版 UI 结构」时才考虑把 R2 的三处包 `pcall`；
   ③ 若有缺失 ⇒ 按 R 编号定位，最小改法是**加 `type()` 守卫 + 缺失时如实跳过该块**（不要改成「假装成功」）。
