# EH_Mail 子插件记忆体（判据 / 铁律 / 锚点）

> ★本文件 = **EH_Mail 自己的记忆体**，与宿主记忆分目录、分文件存储（用户定：
> 「子插件的记忆体放置在子插件对应目录.自己管理自己的记忆体.不要和当前插件记忆体混合」）。
> 宿主 `CLAUDE.md` 的通用铁律照旧适用、本文件不重复：`node luacheck.js` 语法闸门 · 不许用子代理 ·
> 答复一律中文 · 改完 `node sync_game.js` · **不自动提交** · `tmp/` 判据只在「统一推送」时跑 · 发布 10 步。
>
> ★★★**子插件之间的隔离性（开发规范 = 宿主 `CLAUDE.md` §4.3 宿主契约 ⑤）**：跨插件口一律
> 「**运行期现读**（`rawget(_G,"名字")`）· **对象在 ∧ 方法在**（`type` 两道）· **调用 `pcall`** · **拿不到就 fail-open + 如实降级**」；
> **对手方不存在 / 是空表 / 没那个口 / 口会抛错 ⇒ 一律不许报错**，也不许写别人的存档根。
> 常驻闸门 = **`node tmp/subaddon_isolation_probe.js`**（★新增跨插件口要同步它的 `LIST`，否则清单腿报红）。
> 本子插件的口 = ① 对 EH_Bag：`m.multi_tell_bag()`（`rawget(_G,"EH_BAG")` + `.mailMarkRefresh` 是 function + `pcall`）；
> ② 对宿主：`EVAL_DD_OPEN`（`type(...) == "function"` 早退 + 如实出声）· `EVAL_SAY_FORCE`。
>
> ★★★**命名与播报口径（开发规范 = 宿主 `CLAUDE.md` §4.3 宿主契约 ⑥）**：面向玩家的前缀一律 **`[EH_Mail]`**（= 目录名）；
> **内部表名 / 文件名（`EHMailTM` 这种第三方搬进来的名字）只许出现在代码里**（函数名 / 帧名 / 存档键前缀），
> **绝不许当聊天前缀**（用户 2026-10-10：「子插件命名统一采用 EH_xxx 方式」）。★唯一来源 = `m.ADDON_NAME`。
> 常驻闸门 = **`node tmp/subaddon_naming_probe.js`**。

## 本目录构成

本目录 = **两部分**：体检探针（本项目自己写的）+ 邮箱增强（移植版）（第三方代码搬进来的）。

| 文件 | 作用 |
|---|---|
| `EH_Mail.lua` | **探针**（体检名单 + 有界落盘环 + 唯一节拍帧 + `/email` 命令）—— 载入期零副作用 |
| `EH_Mail.toc` | 载入清单（顺序 = `EH_Mail.lua` → `EHMailTM_Saved.lua` → `EHMailTM.xml`）+ `## Version`（= 源码常量 `EH_MAIL_BUILD`）+ **两个**存档声明（`EH_MAIL_CFG` 账号级 / `EH_MAIL_CHAR` 角色级，**各只有一个名字**） |
| `EHMailTM_Saved.lua` | **存档绑定 + `m.api` 代理**：把 9 个存档键收进两个存档根（见下「存档」条），并给裸访问的表类做别名 |
| `EHMailTM.xml` + `EHMailTM.lua` | **移植版主体**（XML 里 6 条 `<Script>` 再拉起下面几个 lua）；`EHMailTM.lua` ≈3000 行 |
| `Calendar.lua` · `MailTo.lua` · `localization.lua` · `localization.cn.lua` | 移植版附属（日志日历 / 收件人下拉 / 英中本地化） |
| `EHMailTM-AH.blp` · `EHMailTM-RetArrow.blp` · `EHMailTM-DownArrow.tga` | 移植版自带素材（**二进制，改动时别当文本处理**） |
| `README.md` | 面向使用者（两部分：`/email` 体检 + `/tm` 邮箱增强） |
| `CLAUDE.md` | **本文件** = 开发记忆体 |
| `CHANGELOG.md` | 改动记录（`0.1.x` / `0.2.x` ↔ 宿主 `1.75.y`） |

★ `pfui-skin.lua` **已删**（用户 2026-10-10：「pfui 相关的抛弃.只移植原始Ui的功能」）—— **别再加回来**。

## 这一版是什么

**0.3.0 = 体检探针 + 邮箱增强（移植版）**：① 探针用**真机**回答「上游邮箱插件搬到 EmberVeil，
**FrameXML / 具名帧那一层**缺什么」（**已跑一轮**，结论见下）；② **移植版已落地**（邮箱增强本体，命令 `/tm`）——
见下一节「增强版（移植版）」。
调研与结论 = 宿主 `doc/TurtleMail-API支持度调研.md`（离线证据链 + 风险 **R1~R11**）· 探针名单来源 = `tmp/tm_probe_names.txt`。

★★★**首轮真机读数（2026-10-09 · 账号 LIHAIBOAS2 · 读的是 0.1.0 那版）= 共 115 项 ｜ 缺 1 项**：
* 唯一缺失 = `FRAME:SendMailStationeryButton` —— 它在客户端**确实不存在**，但 **上游源码零引用**
  （只有 `StationeryBackgroundLeft/Right`，实测都在）⇒ **与移植无关**；0.1.1 起已移出名单（`FRAME` 46 ⇒ 合计 **114 项**）。
* ✅ **R1 排除**：10 个 FrameXML 挂钩全局**全部 `function`**。✅ **R4 排除**：8 个 `$parent` 派生名全在
  （含离线时「基础 MPQ 查无此名」的 `SendMailMoneyGold/Silver/CopperRight`）。✅ **R3 排除**：模板与页签前提齐备。
* ❌ **R11（本次唯一真问题 = 移植第一步必须先改）**：`SendMailMoneyGold/Silver/Copper` 的 `GetRegions()`
  实测**各 N=4**，而 `TurtleMail.lua:2097/2101/2105` 取 **`[9]`** ⇒ nil 索引；那三行**无 `pcall`**、跑在
  `ADDON_LOADED → sendmail_load()` 里 ⇒ **会中断其后 3 个 load**（`log.load` / `batch_load` / `pfui_skin`）。
  ⇒ 改法 = `local rs = { f:GetRegions() }; if rs[9] and type(rs[9].SetDrawLayer) == "function" then … end`
  —— **别写死别的下标**，要的是「够就设、不够就跳过」。
  ★ 反例（安全）：`SendMailPackageButton`（源码取 `[1]`/`[3]`，实测 N=3）与 `SendMailScrollFrame`（取 `[3]`，N=3）**都够**。

## 增强版（移植版）—— 0.3.0 落地

**形态 = 最小改动**：保留原始文件名 ⇒ XML 里 6 条 `<Script file="…">` **一个字都不用改**；
全部平铺在本目录（与探针同级）⇒ 相对路径天然成立；`EH_Mail.toc` 只多一行 `EHMailTM.xml`。
★**顺序即判据**：`EH_Mail.lua` 必须排在 `EHMailTM.xml` **之前** ——
体检探针是**诊断腿**，XML 万一载入失败时它得还活着（否则连「为什么坏」都看不到）。

**七条适配（少一条就白搬）**：

| # | 改什么 | 不改的后果 |
|---|---|---|
| ① | `arg1 ~= "<旧插件名>"` ⇒ `"EH_Mail"`（+ `GetAddOnMetadata( "EH_Mail", … )`）—— ★旧名已按用户要求清干净，这里只写占位 | `ADDON_LOADED` **第一行就 return** ⇒ 初始化一个字节都不执行（**看着载入了、界面毫无变化**，最难查的一类） |
| ② | R11：三处 `[{ f:GetRegions() }][ 9 ]` ⇒ `local rs = {…}` + 「**对象在 ∧ 有 `SetDrawLayer`**」才设（判读判据见 ⑦ 条下面） | 载入期 nil 索引 ⇒ **中断其后 3 个 load**（日志 / 批量 / 皮肤全不初始化） |
| ③ | pfUI 整条剔除（删文件 + XML 行 + 3 处 `m.pfui_skin()` + 显式 `= false`） | `attempt to call nil`（`m.pfui_skin` 随文件一起没了） |
| ④ | 自带素材路径 5 处 ⇒ `Interface\AddOns\EH_Mail\` | 三道贴图全部找不到（**静默画空**） |
| ⑤ | **存档全局不许无条件覆盖**（三处 ⇒ 「缺什么补什么」/`or {}`） | 数据**每次登录丢光**：日志历史 · 自动补全名字 · 收件人历史（★原版注释写着「仅对没有存档的新角色生效」，代码却无条件覆盖 = 代码与注释不符） |
| ⑥ | ★★★**toc 的 `## SavedVariables` 一行只许写一个名字** + 9 个存档键收进两个存档根 | **真机红框**：写成 `A B C` 时客户端把整串当**一个**超长名字写进存档 ⇒ 读回来 `'=' expected`，**每次登录弹一次**（2026-10-10 实踩，见下） |
| ⑦ | ★★★**所有 `GetRegions()[N]` 一律「够了才用」**（全项目共 **6** 处）；★判据 = **对象在 ∧ 那个方法在**（`type(o.M) == "function"`），**只判 nil 不算修好** | **真机红框**（0.3.1/0.3.2 两轮才修对）：数量**随控件状态变**、**元素还不保证是 Texture**（本客户端那一格给的是 FontString）⇒ `attempt to call method 'SetTexCoord' (a nil value)`，**一收信/开邮箱就弹**（栈 = `SendMailFrame_Update` ← `MailFrame.lua:558`） |

★★★**判读判据：`attempt to call method 'X' (a nil value)` ≠ 对象是 nil**（0.3.1 走了一大圈换来的）：
**对象本身是 nil** 时报的是 `attempt to index a nil value`（索引失败）；报 `attempt to call method 'X' (a nil value)`
说明**对象在、`对象.X` 是 nil** = **类型不对**（本客户端 `GetRegions()` 交出来的元素可能是 FontString ——
它有 `SetHeight` 却没有 Texture 专属的 `SetTexCoord` / `SetDrawLayer`）。
⇒ 这一族的一切守卫一律写成「**对象在 ∧ 方法在**」（`and type(o.M) == "function"`），**只判 `if o then` 不算修好**；
★真机复现路径 = `/reload` → 开邮箱或收一封信（`SendMailFrame_Update`）。判据 = `tmp/ehmail_wiring_check.js`
三条升级后的钉 + 一条反向钉（不许退回「只判对象存在」）。

★★★**两个存档根（0.3.0 定案，别再退回多个全局）**：本客户端 `## SavedVariables:` **一行只认一个变量名**。
写成 `## SavedVariables: A B C` 时，它把「A B C」当成一个名字写进存档文件，读回来就是语法错 ⇒ 每次登录红框。
⇒ 现在只声明**两个**：`EH_MAIL_CFG`（账号级）+ `EH_MAIL_CHAR`（角色级，`## SavedVariablesPerCharacter`）；
增强版那 9 个存档键（`EHMailTM_Log` / `_AutoCompleteNames` / `_MailToList` / `_PanelOffset` / `_PanelOffsetPF` /
`_To` / `_Point` / `_AutoCOD` / `_PanelHidden`）作为它们的**字段**存在，由 `EHMailTM_Saved.lua` 的**代理**转发：
`EHMailTM.api = EHMailTM_SAVED_PROXY or getfenv()`（代理只拦这 9 个名字，其余全局照旧走 `_G`；拿不到就 fail-open）。
★判据 = `tmp/ehmail_wiring_check.js` 的「toc 的 ## SavedVariables 只声明 1 个名字」两条钉 + 代理三条钉。
★★**每个键属于哪个根（用户 2026-10-10 定）**：**账号级** = `tm_log` 邮件日志 · `tm_autoNames` 自动补全 ·
**`tm_mailToList` 收件人历史（通讯录，同账号所有角色共用）** · `tm_panelOffset` / `tm_panelOffsetPF`；
**角色级** = `tm_to` 上次收件人 · `tm_point`（已不再写）· `tm_autoCOD` · `tm_panelHidden`。
★判据 = wiring check 两条（别名/MAP 都指向 `EH_MAIL_CFG` · **迁移**幂等）。

★★**pfUI 剔除的口径 —— 只删「不可达/必崩」，别过度清理**：
全文件那十几处 `m.pfui_skin_enabled and <pfUI 值> or <原版值>` **刻意保留** ——
它们另一半就是「**原版保底值**」，而 `m.pfui_skin_enabled = false` 让它们**恒走原版分支**；
4 处 `m.api.pfUI` 引用（1 处完整守卫 `if m.api.pfUI and m.api.pfUI.api and …`、3 处短路三元）同样**不动**。

**判据** = `tmp/ehmail_wiring_check.js` 末段结构钉（0.3.1 起；0.3.2 把 region 判据升级成「对象在 ∧ 方法在」、
0.3.3 加 8 条拖拽/日志/寄送钉 + 3 条收件人下拉钉 + 3 条日志字体钉 + 1 条附件失败取证钉 + 3 条批量限频钉 +
4 条存档绑定钉 + 2 条账号级/迁移钉 + 10 条原生 CheckButton 钉；★本轮再补 7 条 —— 放回队首恰 2 处 ·
失败分流两支 · 开批复位三计数 · 附件栏残留**硬停**（两句都在）· 「拿起后」量在取件与放置之间）：toc 顺序 / 两个存档根 / 插件名适配 /
**清痕迹（代码/XML/toc 零旧插件名）** / R11 + 反向 / pfUI 4 条 / 素材 3 条 / 存档全局 4 条 /
**toc 单名字 2 条 + 代理 3 条**（本次真机红框换来的）。
★★**总数不写死**（脚本自己会印 OK/FAIL 计数；实测本轮 = 119 条，其中 **5 条是既有欠账**
= 存档代理 / 容器根 / VLA 别名 / 无模板 CheckButton / 勾选框贴图反向钉，与本轮改动无关）。
★★**移植版没有行为闸门**（第三方 3000 行 + 强依赖客户端邮件窗，离线跑不了）⇒ 行为只能**真机判**。

**移植前审计脚本**（纯读，可复算）：`tmp/tm_port_audit.js`（XML 拉起哪些脚本 / inherits 模板 / 自建帧 / 素材）·
`tmp/tm_port_audit2.js`（**模板三分类**：插件自建 / 同血统标准 / ★两处都没有）·
`tmp/tm_port_audit3.js`（按序号取子件 / 硬编码路径 / include）。
**首轮结论**：17 个 `inherits` ⇒ 自建 6 · 同血统标准 11 · **两处都没有 0** ⇒ **移植前未知项 = 0**。

## 铁律（动本文件前先读）

1. ★★★**体检必须全只读**：不写游戏状态、不碰客户端全局、**不建常驻帧、不挂事件**；
   载入期**唯一**动作 = 注册斜杠命令；帧与节拍**首用才建**（范式 = 宿主 `tools/HunterHelper.lua`）。
   ★**唯一例外 = `TEMPLATE` 探针**：要 `pcall(CreateFrame, "Frame", nil, UIParent, 模板名)` 试一次
   （1.12 **没有销毁帧的 API**）⇒ 建出来当场 `Hide` + **不留引用**，并在聊天里如实报「探针临时帧 N 个」。
2. ★★★**一个模块只许一个节拍帧**：全文只有 `EH_MailTick` 一个 `OnUpdate`；
   挂/摘走**唯一入口** `tickSync()`（有待办才挂、到点执行完当场 `SetScript(...,"OnUpdate",nil)` 真摘）。
   判据 = 结构钉「`SetScript` 的 `"OnUpdate"` 只出现 1 处」+ 行为断言「`GetTime` 未到不 `RunScript`」。
3. ★★★**自动 `/reload` 必须延后**（`RELOAD_SEC = 6`）：本客户端 `/reload` **会清空聊天框** ⇒
   立刻重载等于把刚打出来的结论当场抹掉（1.75.59m 教训）。且**结论先上屏、倒计时后盖章**。
4. ★★★**记忆体分离**（宿主契约②）：只读写自己的 `EH_MAIL_CFG`；
   `EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR` 命中 **0 处**（常驻闸门 `tmp/mem_sep_probe.js` 守着）。
5. ★★**名单与口径必须同源**：`G_FUNC/G_FRAME/G_MISC/G_CONST/G_FONT/G_PARENT/G_TEMPLATE/G_REGIONS`
   这 8 张表 = `tmp/tm_probe_names.txt` **人工去噪后**的客户端侧名字。
   加/减条目要**同时**改这里与 `tmp/tm_probe_names.js` 的抽取口径，否则以后两边对不上。
   ★★**`G_REGIONS` 是唯一的例外形态**（0.1.1 起）：条目 = **`{ 名字, 源码要取的最大下标 }`**，
   源码不读 region 的写 `0`。它是**判据组、不进 total**（`114 = 22+46+7+21+5+8+5`）。
   ★成因：上游插件里 `({ f:GetRegions() })[N]` **全是裸索引、没有 `pcall`** ⇒ 「名字在」**不等于**「下标够」
   （首轮真机正是靠这一组才抓到 `[9] > N=4`）⇒ 只报数量没有意义，必须**直接给「可及 / ★越界」结论**。
   ★结构钉（`ehmail_wiring_check.js`）：不许退回「裸名字」形态 · 必须覆盖源码真正取过下标的那 5 个帧 ·
   越界必须能**上屏 + 进环**。
6. ★★**聊天只回 3 行**（结论 / 缺失点名 / 倒计时+临时帧数），全量走 `/email 明细`；
   **环里不许有 nil**（nil 会截断后面的行 —— 分隔行写 `""`）。
7. ★**注释独占一行**、**对象/全局守卫用 `type()`**、**前向声明 + 定义处赋值**（本文件踩过：
   `tickSync`/`onTick`/`reloadAt` 若声明在 `runProbe` 之后，引用点会绑**全局 nil** ——
   这是宿主记忆体的 R2 老雷，`luacheck` 照不到）。

## 判据 / 锚点

| 判据 | 锚点 |
|---|---|
| 只读哨兵（体检一个字节都不改业务状态） | `tmp/ehmail_harness.js` 组 **②**（前后逐个比**对象身份**） |
| 全给 → 缺 0 / 缺 1 项 → 只点名它 / 模板三态 | 同文件组 **①③④** |
| 有界环（连跑 6 轮 ≤ `RING_MAX`，最新在后；环里无 nil） | 同文件组 **⑥** |
| 聊天恰 3 行 + 缺失点名 + 倒计时 | 同文件组 **①③** |
| 延后重载（未到点不执行、到点**恰一次**、执行后真摘节拍） | 同文件组 **⑤** |
| **区域下标判据**（判不出不报 / 三处越界数得出且上屏进环 / 给够不误报） | 同文件组 **⑪⑫⑬** |
| 三语键同集（zhCN/enUS/ruRU 键集逐字相等、无空值） | 同文件「三语键集」段 + `tmp/ehmail_wiring_check.js` |
| 宿主接线（SUBADDONS 行 / mail 分组渲染 / 三语 `SUB_*` / `probe_localorder` 清单） | `tmp/ehmail_wiring_check.js`（**先剥注释再比对**） |
| 8 张表条数与合计（22/46/7/21/5/8/5 + REGIONS 6） | 同文件「名单条数」段（**现读** ⇒ 改名单会被抓） |
| 记忆体分离 / 一个节拍帧 / 不直接 `ReloadUI` | 同文件反向钉 |
| 同步逐字节 | `node sync_game.js` + `tmp/verify_sync.js`（不一致 0） |

★**运行闸门**（按纪律：功能修改过程中只跑 `luacheck` + `sync_game`；下面批在「统一推送」时跑）：
`node tmp/ehmail_harness.js` · `node tmp/ehmail_wiring_check.js`（★**过期判据**：它钉的还是 0.3.3~0.3.10 那套架构，
0.3.11 重写后带 **47 条既有红**（0.3.15 时报 46，本轮逐条核过**没有一条**涉及 `batch_panel` / `PanelHidden` /
`panel_toggle_*` / `PANEL_TOGGLE_*`）—— 别把它的红当成本轮信号）·
`node tmp/ehmail_attach_probe.js` · `node tmp/ehmail_multi_probe.js` · `node tmp/ehmail_cursor_probe.js`（0.3.12）·
`node tmp/ehmail_attachguide_probe.js`（0.3.13）· `node tmp/ehmail_loggrid_probe.js`（0.3.14）·
`node tmp/ehmail_closeclean_probe.js`（0.3.15）· **`node tmp/ehmail_batchpanel_probe.js`（0.3.16）** ·
`node tmp/subaddon_isolation_probe.js`（**子插件隔离性**，宿主契约 ⑤）· **`node tmp/subaddon_naming_probe.js`**
（**子插件命名口径**，宿主契约 ⑥：目录名 = `EH_<名>` · 前缀 = `[EH_<目录名>]` · 内部名不当前缀）·
`node tmp/mem_sep_probe.js` · `node probe_localorder.js` · `node scan_dangling.js` · `node tmp/check_backticks.js` · **`node tmp/toc_savedvars_check.js`**（全项目 toc 存档声明：每条**恰好 1 个名字** ⇒ `TOC SAVEDVARS OK`）· `node tmp/verify_sync.js`。

## 0.3.3 真机报障定案（拖拽误触 / 日志不记 / 批量寄送漏寄）

> ★★**0.3.11 起本节的「附件挂载」部分已过时**（保留作历史）：`sendmail_set_attachment` /
> `sendmail_pickup_mailable` / `sendmail_forget` / `sendmail_remove_attachment` **四个函数已整条删除**，
> 右键背包物品改成**纯数据入列表**（不再有任何拿放）。**现行口径一律看文末
> 「0.3.11 附件 = 纯数据列表」那一节**；下面关于「挂件序列 / 残留硬停 / 跳过汇总 / 限频」的判据仍然有效。

★★★**本插件不提供任何窗口拖拽**（用户定：「子插件内置的拖拽功能关闭.已经有工具箱->拖拽图层 支持拖拽了」）：
上游为了让「背景处也能拖」，把 `InboxFrame` / `SendMailFrame` 的鼠标整个关掉（两处 `EnableMouse( false )`），
而本客户端只要在 `MailFrame` 上按下有位移就起拖 ⇒ **收件箱/写信页几乎整片空白都是拖拽热区**
（用户原话：「在收件箱 tab 就会出现拖拽. 任意地方都会出现」）⇒ **注册与处理体一起撤**，
连中途加过的标题栏柄、以及位置记忆（`restore_position` / `on_drag_stop` / `UpdateUIPanelPositions` 钩子 /
关窗记点）全部删除。
★**为什么位置记忆也必须删**：宿主「拖拽图层」的真机存档里就有 `["MailFrame"] = { dx, dy, base }`
（**没有** `axAuto` ⇒ 属用户自定义 ⇒ 宿主每 0.3s 守它）⇒ 两边同时写位置必然互抢（拖了被拉回）。
★判据 = wiring check 三条（整窗注册 0 处 · `pcall` 撤注册与两个处理体置 nil · **反向钉**七个标识符全 0 处）。

★★★**批量寄送 = 参考插件的挂件序列原样 + 只把「失败即整批卡死」改成「有界重试」**（0.3.3）：
· ★★★**先记事实：移植没有抄错**。用户报「发送多封偶尔报一次错」后要求「查看参考插件是如何邮寄逻辑的」⇒
  机械对照（`node tmp/tm_sendmail_diff.js`：按函数切块、剥注释、逐行比；可复算）——**邮寄链上真正决定行为的**
  **函数全部「代码逐行相同」**：`sendmail_attached` / `show_send_tab` / `attachment_button_on_click` /
  `remove_attachment` / `set_attachment` / `pickup_mailable` / `num_attachments` / `attachments` / `clear` /
  `queue_update` / `send_mail_button_onclick` / `UI_ERROR_MESSAGE` / `MAIL_SEND_SUCCESS` / `set_cursor_item` /
  `get_cursor_item` + 六个 `hook.*`；另有差异的 5 个全部是**已知移植适配或本轮改动**（`sendmail_load` /
  `MAIL_SHOW` = R11 的 region 守卫；`MAIL_CLOSED` = 删位置记忆；`on_update` = 批量限频闸；`sendmail_send` =
  失败分支）⇒ **再遇到「邮寄坏了」先跑这个对照脚本，别从零猜。**
· **真根因 = 参考插件失败之后的行为**：挂件序列之后只 `not GetSendMailItem()` 判定，失败就往聊天框打一行
  `ERROR_CAPS`（zhCN「错误」/ enUS「ERROR」—— **源码里搜不到「错误」二字**）然后 `return`，
  而 `m.sendmail_sending` 仍为 true、`sendmail_update` 再没人设 ⇒ **这一批静默卡死**（后面的件永远不再发，
  界面上却像还在发）。
· **处置（挂件序列与成功路径一字未改，只改失败路径）**：
  ① 进函数**先查光标**（`CursorHasItem` 有东西就如实报一声停下、**绝不清光标** —— 与子插件 `EH_Bag` 的
     `DROP_CURSOR` 同一口径）。
  ①b ★★★**开批处（`send_mail_button_onclick`）看到客户端附件栏有残留 ⇒ 本批直接停下、一个字节都不碰**
     （`GetSendMailItem()` 非空 = 我们没放过的残留）：**绝不是「提示一句照旧往下跑」** ——
     上游清空附件栏那三步（`ClearCursor` → `ClickSendMailItemButton` → `ClearCursor`）会把**玩家的残留物
     从附件栏拿到光标上又清掉**，此后客户端进入「**光标忙**」状态：`CursorHasItem()` 报**空**
     （我们的光标守卫完全看不见它），但**之后每一次 `PickupContainerItem` 都被客户端拒绝**
     ⇒ 全批「拿不起来」。真机读数（0.3.3 第三轮）= `该格现在= [清凉的泉水] ｜ 拿起后=空 ｜ 寄件栏=空 ｜ 连试 4 次`
     —— **物品从未离开背包**；子插件 `EH_Bag` 的「右键直投 → 邮件附件栏」同时报同款失败也是它。
     ★**这就是「是否是发送频率」的答案：不是频限** —— 0.5s 闸门只会**延迟**写动作，绝不会让
     `PickupContainerItem` 变成空操作；`拿起后=空` 才是判据。
  ② 挂件前**校验那一格现在还有没有东西**（记账只记 `{bag,slot}`、不记身份）：空 ⇒ 计入 `m.sendmail_skipped`
     并**跳过这一件、继续发后面的**（绝不是「停下」）。
  ③ 挂不上寄件栏 ⇒ **放回队首 + 延迟一帧重试**（同一帧里紧挨着的 `ClearCursor` / `PickupContainerItem`
     会撞客户端的物品锁，下一帧锁就松）⇒ 一次抖动不再让整批中断；**连续**失败到 `m.sendmail_retry_max`(3)
     之后才分流：**光标上还留着东西 ⇒ 硬停**（后面必然连锁失败）；**光标干净却拿不起来 ⇒ 计入
     `m.sendmail_failed` 并跳过这一件、继续发后面的**（★这一支**绝不执行 `SendMail`** ⇒ 不会寄出空邮件）。
  ③b ★★★**失败点的诊断必须先量「拿起之后的光标」**（`pickedUp`，在 `PickupContainerItem` 与放置点击
     **之间**读一次）：`拿起后=空` ⇒ **客户端拒绝了这次取件**（物品从未离开背包，与放置序列无关）；
     `拿起后=有` ⇒ 取起来了、是**放置**那一步失败。**不许靠猜**（这一族两轮的教训）。
  ④ 整批收尾（附件队列空）打一行汇总：`本次共跳过 N 件（拿不起来 M ｜ 已不在原处 K）`，然后**清掉三个计数**；
     成功挂上一件 ⇒ 连续失败计数清零（有界）。★★★**三个会话计数必须在开批处复位**
     （`m.sendmail_skipped` / `m.sendmail_failed` / `m.sendmail_retry`）—— 不复位则上一批硬停时攒下的数
     会算进这一批的汇总，而 `sendmail_retry` 会带着上一批的连败数起跑 ⇒ **这一批第一件一失败就被判超限**。
· ★★★**`hook.PickupContainerItem` 会劫持「别人的右键」**（0.3.3 第三轮查明的**第二个**独立故障源）：
  hook 在 `arg1 == "RightButton"` 时**不真取件**，而是走 `sendmail_set_attachment` / `sendmail_remove_attachment`
  （这是上游「右键点背包物品 = 挂到附件栏」的主用法，**不能删**）；而 `EH_Bag` 的「右键直投 → 邮件附件栏」
  也是右键 ⇒ **被同一个 hook 吃掉**、物品一点没动 ⇒ `EH_Bag` 报「没能把这件物品拿起来（邮件附件栏）」。
  ★两者**无法靠 `arg1` 区分**（都是右键、邮件窗都开着）⇒ 正解 = 由 EH_Mail 把**未经 hook 的原函数**
  作为桥交出去（`EVAL_MAIL_PICKUP_RAW`），`EH_Bag` 走它；**在桥接上之前，`EH_Bag` 的邮件直投在
  EH_Mail 启用时不可用**（如实记在案，别当新 bug 查）。
· ⚠️**已知风险（参考插件同样有、本轮未改，别再当新 bug 查）**：判定只看 `GetSendMailItem()` 非空 ⇒
  附件格快照失效（那格换成了别的物品 / 客户端附件栏本来就有残留）时会把**别的东西**寄出去且判为「成功」；
  要根治得比对寄出前后的物品链接。★开批处那条残留硬停就是为此准备的**唯一可见信号**。
· ★判据 = wiring check 七条（含反向钉 `m.api.ERROR_CAPS` 0 处 · 开批复位三计数 · 附件栏残留**硬停** ·
  「拿起后」量在取件与放置之间 · 失败分流两支都在 · 跳过汇总行在）+ 对照脚本 `tmp/tm_sendmail_diff.js`。

★★**日志口径 = 未读也要记**（用户定）：原 `if ( read or manual )` 让**批量取件时未读邮件一条都不记**
（真机证据：存档 `tm_log.Received` / `tm_log.Sent` **两个族都空**，而收件箱里有邮件）⇒ 一律记；
★同时堵上游老毛病「同一封邮件反复打开重复入账」⇒ **内容键 + 2 秒窗**去重（`m.log_last_key` / `m.log_last_at`）。

★★**日志为空时界面也要清干净**：`log.populate` 原来 `if not log then return end` ⇒ 页面留着**上一次的残留**
（用户截图「显示1-2，总共2」而列表全黑就是它）⇒ 改成 `if not log then log = {} end`。

★★**判读判据：`EHMailTM：错误` 这类行是客户端本地化常量**（`m.api.ERROR_CAPS` = zhCN「错误」/ enUS「ERROR」）
⇒ 在源码里搜中文「错误」**一个字都搜不到**；遇到这种没有信息量的报障行，先去 `grep ERROR_CAPS` 这类常量。

★★★**收件人下拉的位置 = 必须走 `ToggleDropDownMenu` 的 `anchorName` 那一支**（0.3.3 真机报障「下拉没在
收件人名称下方」）：本客户端 `UIDropDownMenu.lua` **只在「不传 anchorName」时**才读 `dropDownFrame` 的
`point` / `relativeTo` / `relativePoint`（555~573 行），而客户端自己那一支用的是**帧名字符串**（569 行）；
更关键的是 **`SendMailNameEditBox` 本体只有 122x20**（`MailFrame.xml:662-665`），可见的输入框装饰比它宽得多
⇒ 拿它的 `BOTTOMRIGHT` 当锚点，菜单会从**可见框中间**开始（用户看到的就是「跑到右边」）。
⇒ 正解 = `ToggleDropDownMenu( nil, nil, menu, "SendMailNameEditBox", 0, 0 )` ⇒ `relativeTo` 是帧名、
位置取默认 **TOPLEFT 贴 BOTTOMLEFT** = 正下方左对齐。★那 5 个位置字段传 anchorName 时**一个都不生效**，
留着只会误导（已删）。
★通用判据：**本客户端凡是「按帧本体算几何」的地方，都要先问「本体与可见装饰是不是同一个矩形」**
（同族先例：`MailFrame.R 467` vs `MailItem7.R 411`、EditBox 122 宽 vs 可见框更宽）。
★判据 = wiring check 三条（幂等 ensure · anchorName 调用恰 1 处 · **反向钉**：裸传 / 位置字段 / parent 用 this 全 0 处）。

★★★**日志列表「一个字都没有」= 字体链被「读回自证」的旧客户端分支切断**（0.3.3 **两轮**定案；
一轮那条「路径大小写」只解释了一半 —— 改完大小写**仍然没字**）：
· **一轮**：日志行那 4 个 FontString 原写 `"FONTS\\ARIALN.TTF"`（**目录名全大写**，全仓唯一一处）⇒ 按
  「本客户端字体路径大小写敏感」改掉大小写 + 改走项目字体链（与宿主 `EvalHelp.lua:173` 同款）。
· **二轮**（真机截图：已发送页有 3 条、底下计数器「显示1-3，总共3」**正常**，而**每行仍一个字都没有**）——
  **真根因不在大小写**：本客户端 `FontString` **没有 `GetFont`**，而 `fontSet` 当时写着「读不回就当这一步成功」
  ⇒ 它在**链首 `FZLBJW` 那一步就 `return true`** ⇒ **链尾（真正可用的那条）从未被设过**。
· ★**读回自证的唯一正确写法**：`canRead = (type(fs.GetFont) == "function")`；**读不回 ⇒ 把整条链设完**
  （最后一条生效）；读得回 ⇒ 逐条比对、都不对才退 `SetFontObject(GameFontNormal)`。
  **绝不许在读不回时提前 return** —— 那等于「只设了链首」。
· ★★**链尾那条必须真机验证可用**（比「链序」更重要）：链尾 = `Fonts\ARIALN.TTF` —— 宿主主插件
  `EvalHelp.lua:173` 的链判据是 `pcall` 的**第二返回值**（`SetFont` 无返回值 ⇒ 恒假）⇒ 它**实际恒落到链尾
  ARIALN**，而主插件全界面（含中文）显示正常 ⇒ **ARIALN 真机可用** = 「读不回时链尾兜底」的依据。
  ★**别以为「第一条通常是好的」** —— 二轮就是栽在这个假设上。
· ★**同页对照证据（定案手法）**：底部计数行的 `SetFont( "Fonts\\FRIZQT__.TTF", 10 )` 显示正常（中文也正常）
  ⇒ `log.load` 确实跑到了、`SetFont(path,size)` 两参数可用、路径写法也对 ⇒ 剩下的变量只有「链走到哪一条」。
· ★**两个页签（已收到 / 已发送）共用同一批 10 个行控件与同一份字体设置**（`log.load` 只跑一次、
  `log.populate` 两个类型走同一个渲染循环）⇒ **修一处两页同时生效**（用户说「已收到也要相同修复」时别改两遍）。
· 唯一实现 `m.log.fontSet`（挂 `m.log` 表，零新增文件级 local）。
· ★判据 = wiring check 三条（**反向钉**：全仓不许再有 `FONTS\` · 4 处都走 `fontSet` · 字体链与读回自证口径）。

★★★**勾选框 = 客户端原生 `CheckButton` 控件 + 全自绘样式**（0.3.3 三轮试出来的组合，别拆开用）：
· **控件必须是原生 `CheckButton`**（别自绘普通 `Button`）：checked 态与**命中区都由客户端算**，
  按钮宽度设成**整格 `CELL_W`** ⇒ **点方框、点文字都是点它**。自绘 `Button` 那版是「16x16 方框 + 独立标签按钮」，
  文字区**不是按钮的一部分** ⇒ 点方框/点文字都点不着（命中区与层级各修一轮都没救）。
· **样式全自绘**：不用 `OptionsCheckButtonTemplate`（自带 32x32 贴图 + 居中锚文字，会撑坏布局：方框被撑大、
  文字跑到老远）；也不用客户端那批 `UI-CheckBox-*`（**非方图 / 是横向图集**，按 16x16 切只会截到**框的一角** ——
  真机表现是「方框只剩左边一条竖线」，而**图集切哪儿不能靠猜**）。
  改用项目唯一可靠的纯色纹理 `Interface\Buttons\WHITE8X8` + `SetVertexColor`：
  **暗底 + 四条 1px 亮边（上下拉满宽、左右拉满高，`EDGES` 数据表 + 一个循环）+ 选中亮绿实心块（内缩 3px）+ 悬停提亮**；
  文字自己建并锚 `LEFT / cb / LEFT / CHECK_BOX+4`。
· ★**「勾」自己画、显隐只在一处 `syncMark()`**：读客户端的 `GetChecked()`（**不自己存变量**），
  `OnClick` 与「包一层 `SetChecked`」两条路都调它 ⇒ 外面（`inbox_refresh_checkboxes` / `/tm filter`）改状态也跟得上；
  选中态用**实心色块**而不是「勾字符」（避开字形/编码风险）。
· ★**本客户端并非每个 `Set*Texture` 都有**：`SetCheckedTexture` 就没有（1.12 把「勾」放在 XML 的 `<CheckedTexture>` 里
  声明，**没有运行期 API**）⇒ 真机红框 `attempt to call method 'SetCheckedTexture' (a nil value)`；
  凡是要给控件设客户端贴图的地方**一律 `pcall`**。
· ★**两个入口共用一个写口** `batch_set_filter(key, on)`：面板勾选框 ⇄ 「筛选」按钮弹出的多选窗
  （宿主 `EVAL_DD_OPEN` multi，保留为第二入口）；回调统一**只传新状态**，**绝不用「切换」语义**（会双翻转）。
· ★同族可复用判据：**别人的模板会带来它自己的尺寸与锚点口径**（要用它的命中/状态逻辑，就别用它自带的贴图与文字）·
  **背景板面板 `EnableMouse( false )`** · **子件逐个 `SetFrameLevel`** · **中文量宽不可靠**（改用布局常量）。
· ★判据 = wiring check 10 条（无模板 CheckButton · 命中区 = 整格 · **反向钉：`UI-CheckBox-` 与 `SetNormalTexture` 均 0 处** ·
  `EDGES` 四条边 · 选中块色值 · `syncMark` 只在两处被调 · 悬停提亮 · 文字自己建 · 回调只传状态 · 两入口同写口 ·
  弹窗第二入口 · 全选回推 + 面板高度原式）。
★★★**邮件附件的真实机制（读码定案，别再猜）**：上游**不用真实附件栏** —— 挂件 = 纯 Lua 记账
（`MailAttachmentN.item = { bag, slot }`），再用 `hook.GetContainerItemInfo` 把那些格子伪造成 `locked = 1`
（`ret[3] = ret[3] or m.sendmail_attached(bag,slot) and 1 or nil`）；**只有真寄出**（`sendmail_send`）才把物品
经光标放进客户端寄件栏：`ClearCursor` → `ClickSendMailItemButton` → `PickupContainerItem` →
`ClickSendMailItemButton` → `GetSendMailItem()` 读回判定。
★★**「拿不起来」的判读（0.3.3 第三轮改判，别再沿用旧猜法）**：旧结论「物品留在光标上 ⇒ 光标非空 ⇒ 之后
  什么都拿不起来」**只覆盖一种情形**；真机第三轮的读数是 `该格现在= [清凉的泉水] ｜ 拿起后=空 ｜ 寄件栏=空`
  ⇒ **光标一直是空的**，是**客户端直接拒绝了取件**（真凶 = 附件栏残留被上游那三步清掉后留下的「光标忙」态，
  见上面 ①b 与 `hook.PickupContainerItem` 劫持两条）。⇒ 判据一律看**「拿起后」那一格**，不要看「现在光标」。
★**恢复方法（给玩家的原话）**：点一下寄件栏把里面的东西取出来（或重启客户端），然后重来。
★★★**纪律：这一族「拿不起来」的问题，先取证再改** —— 失败点必须打出可截图的诊断
「格子 bag/slot ｜ 该格现在=<链接> ｜ **拿起后**=有/空 ｜ 现在光标=有/空 ｜ 寄件栏=有/空 ｜ 连试 N 次」，
用来区分三种情形：① 那一格已不是原来那件东西（(bag,slot) 快照失效，多见于批量连续寄送）；
② **客户端拒绝了取件**（`拿起后=空` 且该格还在 —— 真机第三轮就是这一支，见上文「附件栏残留」与
「hook 劫持右键」两条）；③ 取起来了但**放置**失败（`拿起后=有`）。
**三种情形的修法完全不同**，不要凭猜测改上游流程。
★同族铁律（宿主记忆体）：**留下光标物品时绝不清光标**（清掉就是丢件 —— `EH_Bag` 整理引擎实测丢过两件）
⇒ `sendmail_send` 里上游那两处 `ClearCursor()` 属**待评估**（本轮刻意未动）。
★判据 = wiring check 一条（诊断串在 + 光标守卫 ≥2 处）。


★★★**附件格的鼠标必须由我们接管 —— 上游那个处理体是「死函数」**（0.3.3 真机报障「多邮件发送异常 /
内部数据没更新 / 放到第二件就失败」的**主根因**）：
· **证据（静态、可复算）**：`grep -n attachment_button_on_click EHMailTM.lua` ⇒ **只有定义那一处**、
  **没有任何 `SetScript( "OnClick", … )`** ⇒ 上游写好了却**忘了挂** ⇒ 附件格的 OnClick / OnReceiveDrag
  **仍是客户端自己的行为**：
  ① 拖着物品放到附件格 ⇒ 客户端**真的**把它放进客户端附件栏（不经过记账）⇒ 界面 / 记账 / 背包三份状态各说各话；
  ② 点附件格拿东西 ⇒ 走客户端逻辑、**记账一个字不动** ⇒ 用户原话「内部的数据没有更新 / 发出去的还是第一次那件」；
  ③ 真进了附件栏的物品，客户端会**把整个取件通道堵住** ⇒ 之后 `PickupContainerItem` **拿不起来**
     （真机诊断：连试 4 次都是空手而归）—— ★**读法见上一条「拿不起来」的判读（看 `拿起后=`）**。
· **修法（`sendmail_load` 尾部）**：`MailAttachment1..ATTACHMENTS_MAX` 逐个
  `SetScript( "OnClick", m.attachment_button_on_click )` + `RegisterForClicks( "LeftButtonUp", "RightButtonUp" )`
  + `SetScript( "OnReceiveDrag", nil )` + `SetScript( "OnDragStart", nil )` + `pcall( btn.RegisterForDrag, btn )`
  （不传键名 = 撤掉拖拽注册）⇒ **附件格只服务于我们的记账**；挂载方式不变（右键点背包物品）。
· ★**记账必须跟着「物品离开那格」一起清**（唯一实现 `sendmail_forget(bag,slot)`，**不动物品、不碰光标**，
  定义 1 处）：调用点 = `hook.PickupContainerItem` 的**左键拿起已挂载件**那一支（附件格自己的交换路径由
  上游 `attachment_button_on_click` 里的 `sendmail_set_attachment` 负责清，两条路各清各的）。
  ★**代价如实**：拿起后又放回原处 = 需要重新挂一次（宁可少挂，也绝不能拿旧记账去发错东西）。
· ★**挂件前必须校验「那一格现在还有没有东西」**（`sendmail_send`）：记账只记 {bag,slot}、**不记身份**，
  用户批量进行中把物品拿走 ⇒ 对着空位死重试毫无意义、还会把整批拖住（真机「连试 4 次」）
  ⇒ 校验不过就**如实跳过这一件**并继续；整批收尾再报「本次共跳过 N 件」（**绝不静默漏寄**）。
· ★判据 = wiring check 五条（`attachment_button_on_click` **必须被引用**（**反向钉：不许再是死函数**）·
  `OnReceiveDrag` 置 nil · `sendmail_forget` 定义 1 处、调用 ≥1 处 · 挂件前校验在 · 跳过汇总行在）。

★★★**批量操作限频 = 一个共用闸 `m.batch_rate_ok()`（0.3.3，用户要求，默认生效）**：
现状原本**没有真正的限频** —— 批量推进挂在常驻 `on_update`（每帧最多一步），唯一刹车是「等
`GetInboxNumItems` 掉下来」⇒ **节奏只受服务器确认速度限制**（★别把 `m.timer = 200` 当限频：那是
**收件箱刷新**节流，见 `on_update` 尾部那三行）。本项目铁律 = 「服务器写动作 > ~1-2 次/s 必限频」
（1.75.x 实测：一帧 24 次 `UseContainerItem` 被反滥用踢线）。
⇒ 间隔 `m.batch_rate = 0.5s`（≈2 次/s）· **四处写动作全部过闸**：`batch_step`（批量取件/退信/删除）·
「接收所有邮件」逐封路径 · 「选择取件」路径 · `sendmail_send`（批量寄送）。
★三条口径（改这里必看）：① **没到点原样排队、下一帧再来**（绝不丢队列、绝不吞操作）；
② **闸只挡写动作**（越界/跳过/GM 邮件分支不占闸）；③ **每批开始复位**（`m.batch_last_at = 0`）⇒
第一批第一件永远立刻执行，不因上一轮尾巴而「点了没反应」。
★判据 = wiring check 三条（闸在 + **调用恰 4 处** · 复位恰 1 处 · `if not m.batch_rate_ok() then` 恰 4 处）。

★★★**存档绑定不许在文件执行期抓容器根的引用（孤儿表老雷）**（0.3.3 真机报障「收件人历史添加成功、
`/reload` 后没了」）：本项目有老雷 —— **文件执行期读存档可能拿到空表，客户端随后才把真表换到
`EH_MAIL_CFG` / `EH_MAIL_CHAR` 这两个全局上** ⇒ 在文件执行期 `local CFG, CHR = EH_MAIL_CFG, EH_MAIL_CHAR`
抓住的引用会变成**孤儿表**（写进去永远不落盘）。真机证据：同一段代码，`Iosol` 存住了 `tm_mailToList`、
`Ionol` 只有空桶 ⇒ **时好时坏**正是「时机不定」的特征。
⇒ 两条口径（`EHMailTM_Saved.lua`）：① **容器根「用的时候现读全局」**（`_G["EH_MAIL_CFG"]`，代理与
`tbl()` 全走它）；② **裸全局别名在 `VARIABLES_LOADED` 再确认一次**（幂等 + `mergeInto` 把旧表已有数据
并进新表）⇒ 无论客户端哪一刻换表，别名最终都指向真表。
★**取证判据**（用户可截图）：添加收件人时打 `收件人表==存档表? <true/false> ｜ 服务器=… ｜ 桶内=N`；
`false` ⇒ 正是这条老雷。★同族：`MailTo_ToList_Init` 里**桶缺失要自愈建桶**（否则直接索引 nil 报错、
下拉一项都没有）。
★判据 = wiring check 四条（现读全局 · VLA 再绑 + 合并 · **反向钉 `local CFG` 不许回来** · 取证行在）。

★★★**收件人历史 = 账号级（通讯录，同账号共用）**（0.3.3 用户定：「收件人设置账号级别存储. 同个账号都可直接复用」）：
`tm_mailToList` 从角色级（`EH_MAIL_CHAR`）搬到**账号级**（`EH_MAIL_CFG`）—— **别名绑定与 `MAP` 两处必须一起改**；
桶结构保留按**服务器名**分桶（跨服名字不混）。
★★**搬存储根必须带迁移**（`migrateMailToList`）：把旧位置（角色级）的历史搬进账号级，**只补不覆盖 ·
跳过非字符串垃圾 · 同服去重 · 搬完排序 · 清掉旧位置**；在文件执行期与 `VARIABLES_LOADED` **两个时机各跑一次**且
**幂等**（与 `EHMailTM_SavedBind` 同一节奏，理由同上条老雷）。★不迁移 = 用户之前加过的收件人「凭空消失」。
★**改存储根时必查三处**：① `ALIAS` ② `MAP` ③ **任何把根名写死的诊断/判据**（本次取证行与 wiring 钉里都写死了
`EH_MAIL_CHAR.tm_mailToList`，不同步改就会永远报 `false` —— 那是**假的失败信号**）。
★判据 = wiring check 两条（别名与 MAP 都指向 `EH_MAIL_CFG` · 迁移定义 1 处 + 调用 2 处 + 清旧位置 1 处）。

★★★**背景板面板不许吃鼠标**（0.3.3，仍然有效、与勾选框形式无关）：`EHMailTMBatchPanel` 只是背景板、
**没有任何鼠标处理体** ⇒ 必须 `EnableMouse( false )`。本项目在案「**层级同时决定点击命中**（透明/无贴图的帧
照样吃点击）」⇒ 面板只要在子件之上就会把整片点击全吃掉。
★同族两条（留着当判据）：**子件要逐个 `SetFrameLevel`**（抬高父帧不带动子件）·
**中文量宽不可靠**（要改用布局常量或 max(实测, 估宽)）。
★**已撤掉的是「自绘 `Button` 那一版实现」**（`checkbox()` 里「方框 16×16 + 独立标签按钮」那种拼法、
以及配套的「标签命中区」判据与 `/tm cb` 自检口）—— **勾选框本身没撤**，它现在是客户端原生 `CheckButton`
（见上一条），并且**仍然平铺在面板上**（11 个筛选 + 本页全选）。
★判据 = wiring check 一条（面板不吃鼠标 + **反向钉：不许开回来**）。

## 0.3.11 附件 = 纯数据列表（★现行架构；0.3.10 那版「记账投影 + 右键物理挂载」已作废）

★**这一节的全部代码**：列表核心 + 投影 + 命令体在 `EHMailTM.lua` **末尾那一节**（注释头
`0.3.11 附件选择列表（**纯数据**）+ 发送指令`）；**入口与发送**在文件中部（`hook.PickupContainerItem` ·
`attachment_button_on_click` · `sendmail_clear` · `send_mail_button_onclick` · `sendmail_send`）。
接线三处 = `slash_command` 顶部三条分派（`^发送背包` / `^附件` / `^多选`，**都排在 `^panel` 之前**）·
`hook.MailFrameTab_OnClick` 尾部（`tab == 2` 自动投影）· `sendmail_load` 里【发送】按钮拦截两条腿。

| 判据 | 锚点 |
|---|---|
| **列表 = 唯一真值**：条目 `{ 包号, 格号, 选择时的链接 }`；容量 `m.multi_cap`（7×3 = **21**，现算不写死） | `m.multi_list` / `m.multi_cap` |
| **附件格 = 投影**：唯一写入者 `m.multi_project()`（**全量重建**，只投影「这一刻真的还在那格」的条目） | `m.multi_project` |
| 选择阶段**零物品操作**（不 `PickupContainerItem` / 不 `ClearCursor` / 不 `ClickSendMailItemButton`） | `hook.PickupContainerItem` · `attachment_button_on_click` · `sendmail_clear` |
| 加 / 删 / 幂等 / 满 21 拒绝 / 身份核对 | `m.multi_add` / `m.multi_del` / `m.multi_has` / `m.multi_alive` / `m.multi_prune` |
| 【发送】拦截两条腿（全局 `SendMailMailButton_OnClick` + 真按钮 OnClick 脚本） | `sendmail_load`（`MailMailButton.SetScript…"OnClick"`） |
| 发送 = **已验证序列**（逐件真切进客户端寄件栏）+ 批末把已寄出的条目从列表摘除 | `send_mail_button_onclick` / `sendmail_send`（`m.multi_sent`） |
| 超出容量 tooltip（附件格悬停 + 计数框悬停，**同一句**） | `m.multi_overflow_line` / `m.multi_tip_wrap` / `m.multi_tip_lines` |
| 离线真跑：列表 **39 条** · 入口/发送 **22 条行为 + 8 条源码钉** | `tmp/ehmail_multi_probe.js` · `tmp/ehmail_attach_probe.js` |

★★★**四条口径（改这一族必看）**：
1. **绝不碰「拿起放下」**（用户 2026-10-10 原话：「不预警，让邮件发送自身函数报错/提示，
   **绝不碰鼠标拿起放下的行为.容易卡住物品**」）：加/删/投影/清 **一律纯数据**；只有点【发送】那一刻
   才真切进客户端寄件栏（那是唯一必须的物理动作，也就是**已验证过的那条路**）。
   ★全程客户端寄件栏都是空的 ⇒ 「拿不起来 / 光标忙 / 附件格锁住」那一族现象从根上不存在。
2. **四个「碰物品」的老函数已整条删除，别往回加**：`sendmail_set_attachment` · `sendmail_pickup_mailable` ·
   `sendmail_forget` · `sendmail_remove_attachment`（判据 = 剥注释后全文件 0 命中，见 attach probe 源码钉）。
3. **投影 = 全量重建**（0.3.10 的「只加不删」作废）：现在只有列表一个写入者 ⇒ 全量重建不会误删任何东西，
   而且「显示 = 列表」必然成立。**读到空的条目一律留在列表里**（只在发送那一步「跳过 + 点名」），
   只有「那一格换成了**别的**链接」才由 `m.multi_prune` 摘掉（读到空 ⇒ 保留，绝不因为一次读不到就清空）。
4. **条目带链接 ⇒ 交给客户端的调用只传两个参数**（`item[1], item[2]`；第三字段是给我们核对身份的，
   当第三个实参传给客户端 API 没有意义）。

★**交互事实（有意为之，别当 bug）**：
* **右键背包物品 = 切换**：不在列表 ⇒ 加；已在列表 ⇒ 移（上游也是这个交互，且格子上的 `locked` 图标就是选中反馈）。
  命令口 `/tm 附件 加` 是**幂等**的（不切换）。
* **左键附件格 = 删**（用户定「删」）；**左键背包物品 = 完全交回客户端**（拿起/放下），列表条目**留着**
  —— 物品若放回原处，链接对得上，这一条照样有效。
* **Alt+左键** = 同 id 物品批量入列表（纯数据）。
* 列表**不落盘**（会话态）：`sendmail_clear` 只抹投影、**不清列表**；换角色/重载后为空；
  ★★**但「关邮箱」会整体作废**（0.3.15 起，见下面那一节）—— 「不清列表」只对 `sendmail_clear` 成立。
* 计数框 `EnableMouse( true )` 是悬停热区 ⇒ 它盖住的区域点不到别的东西；`/tm 附件 偏移 <dx> <dy>` 挪开。
* 附件格条目仍会通过 `hook.GetContainerItemInfo` 让背包里对应格显示 `locked`（= 选中反馈）；
  `hook.SplitContainerItem` / `hook.UseContainerItem` 对已选中的格子仍**拦下**（沿用上游，属已知副作用）。

★**变量/常量一律挂 `m` 表**（`m.multi_*` / `m.MULTI_BOX_*`）—— **本文件主 chunk 局部量有上限，
这一族不许新增文件级 `local`**（切词、默认列表、字体、计数、投影、命令体全是 `m.X = function` 形态）。

## 0.3.12 光标拖拽 = 「认得出源格就放回去」（绝不 ClearCursor）+ 附件框接收拖放 + 发件前清理

★★★**用户三条需求（2026-10-10）**：
①「子插件邮箱**发件附件框检测**. 如果有用户**拖拽物品点击到这个窗**则进行**添加对应物品到列表**的行为.
  并且**取消掉物品的拖拽物品操作**」·
②「**发件前**检测用户是否有**拖拽物品在鼠标上**的行为. 也**清理掉拖拽物品的行为**. **查看API是否支持**」·
③「邮箱组件在插件有子插件**背包整合**存在的情况下. 邮件**添加物品列表**的时候将这个物品在背包内的图标上
  添加个**半透明层备注文字, 附件遮盖**。」

★★★**API 事实（查的是本机 `api_cursor.html` 的客户端索引，**不许猜**）**：
* `CursorHasItem()` —— **有**：唯一的「光标上有没有物品」判定口（官方口径：只认背包物品/拆分堆/弹药，
  **不认**钱/法术/宏/商人物品）。
* `ClearCursor()` —— **有，但这一族一律不用它**：它是「把光标上的东西丢下」，而本项目在案的事故里
  「清光标 = 丢件」（`EH_Bag` 整理引擎实测丢过两件）⇒ **绝不用它当兜底**。
* `GetCursorInfo()` —— **本客户端索引里没有**（全表无此名）⇒「光标上是哪一件」**读不出来**，只能靠**源格**反推。
* **源格怎么认**：客户端把被拖走的那一格**锁上** —— `GetContainerItemInfo` 第 3 个返回 = `locked`
  （`api_container.html` 的官方口径）⇒ 被拖走的那件东西的家 = **锁着的那个格子**。
  ★必须用**未 hook 的原函数**（`m.orig.GetContainerItemInfo`）—— hook 版会给「已在选择列表里的格子」伪报
  `locked`（那是附件格子的选中反馈），拿它当判据就会**自己骗自己**。

★★★**三条口径（改动这一族必看）**：
1. **只认「恰好一个锁着的格子」**：0 个（判不出它从哪来）或 ≥2 个（分不清是哪一格）⇒ **一个字节都不碰**，
   如实说一句就收工（绝不猜、绝不拿别的格子当它的家）。
2. **放回 = `PickupContainerItem(源包, 源格)`**（= 玩家再点一次同一格的效果，是客户端认得的**普通移动**，
   永远不可能销毁物品）⇒ 放完**读回自证** `CursorHasItem()`：空了 = 取消成功；
   **还拿着** ⇒ 如实说「请你手动放一下」，**绝不改走 ClearCursor**。
   ③ **一律走 `m.orig.*`**：本插件的 `hook.PickupContainerItem` 会拦右键，而这一族是在我们自己的处理体里调它
   —— 走 hook 就会被自己拦一次（物品一点没动）。
3. **只在这三个入口动手**：附件框接收拖放 / 点【发送】前 / 只读探针（不动物品）。
   选择列表的加/删/投影照旧**纯数据**（0.3.11 的口径一个字节没改）。

★**四个唯一口（全挂 `m` 表，零新增文件级 local）**：
`m.cursor_homes()`（只读：扫 `0~4` 背包 + 钥匙链 + 银行主格与 5~10 银行包，收「锁着的格子」；
返回 `列表, 计数`，**`-1` = 判不出**）· `m.cursor_home()`（恰好一个才认）· `m.cursor_putback(home)`（唯一放回口）·
`m.cursor_why(n)`（「认不出源格」三态**共用一份措辞**）· `m.cursor_clear(tag)`（发件前清理：返回 true = 光标干净）·
`EHMailTM.attachment_receive_drag()`（附件框的拖放处理体）· `m.multi_tell_bag()`（③ 的桥，见下）。

★**三条接线**：
* **附件格 `MailAttachment1..21`**（本插件自己的 XML 模板建的 37×37 按钮）：
  `sendmail_load` 里 `btn:SetScript( "OnReceiveDrag", m.attachment_receive_drag )`
  —— ★上游 XML 模板那条 `OnReceiveDrag` 指的是同一个函数名（**0.3.3 的「死函数」结论只对 .lua 成立，
  XML 里其实是挂着的**），现在被这一行覆盖；`OnClick` / `RegisterForClicks` / 撤拖拽注册照旧。
* **选择列表计数框**（`EHMailTMMultiBox`）也接同一个处理体（它也是「附件框」的一部分；照旧只做悬停热区、不接点击）。
* **点【发送】**：`send_mail_button_onclick` 开头（**排在投影与「寄件栏残留硬停」之前**）调
  `m.cursor_clear("发件前清理光标上的拖拽")`；返回 false ⇒ 如实说一句 + **停下、一件都不寄**
  （`m.sendmail_sending = false`）。★理由：我们那串 `ClearCursor → ClickSendMailItemButton → PickupContainerItem`
  的挂件序列正好会与「手里那件东西」抢同一个光标（历史上就是「光标忙 / 之后什么都拿不起来」那一族）。
* **只读探针 `/tm 附件 光标`**（别名 `拖拽`）：把「光标上有没有东西 / 锁着的格子是哪些 / 认不认得出它的家」
  一条命令摊开，**零副作用**；`/tm 附件 状态` 的现场读数也加了「拖拽源格=」一行。

★★★**③ 的桥 = 背包整合那边的「附件」遮盖层**：助手改完选择列表后调
`EH_BAG.mailMarkRefresh()`（`rawget(_G,"EH_BAG")` 是 table ∧ `.mailMarkRefresh` 是 function ⇒ `pcall` 调；
不在场/没这个口 ⇒ **一个字节都不动**）。调用点两处 = **`m.multi_project()` 开头**（列表一变就通知；含加/删/清/
默认档全路径）+ **批末把已寄出的条目摘掉之后**。★背包侧只读本插件自己的 `multi_has`（纯读）⇒ 两边不互相写状态。

★判据 = **新增 `tmp/ehmail_cursor_probe.js`（行为 15 组 + 源码钉 13 全过）**：
光标空 ⇒ 放行 · 恰好一个锁着 ⇒ 包/格/链接齐全 + 放回**恰 1 次、参数只有两个** + 读回自证 +
**ClearCursor 0 次** · 放回后光标还有东西 ⇒ false + 两句话都在 · 两个锁着 ⇒ 认不出 + 零取件 + 零清光标 ·
一个都没锁 ⇒ 计数 0 + 点名「锁着的」· 连原函数都没有 ⇒ `-1` + 说「判不出」 · 附件框拖放（认得出 ⇒ 加列表 +
取消拖拽；空手 ⇒ 什么都不做；认不出 ⇒ 不加不碰） · 桥三态 · **全程 ClearCursor 总调用 = 0**。
源码钉含：附件格真的挂上 `OnReceiveDrag = m.attachment_receive_drag` + **反向钉**「不许再置 nil」
（唯一允许的一处 = 客户端自己那个寄件栏按钮 `SendMailPackageButton`）· 发件前清理**排在投影之前** ·
块内 ClearCursor 0 处 · 全文件无 `GetCursorInfo` · 判定读的是 `m.orig.GetContainerItemInfo` · 两处桥调用 ·
`/tm 附件 光标` 在 · 版本现读互比。
★**原有两条探针仍全过**：`tmp/ehmail_attach_probe.js`（0.3.11 的入口/发送路径，含「选择阶段一个物品操作都不做」）
与 `tmp/ehmail_multi_probe.js`（列表 39 条）。

★★★**必须真机复验的点**（离线判据测不到「客户端到底认不认这一下」）：
① 从背包拖一件物品**松手落在附件格上** ⇒ 该件**进选择列表**、附件格出现它、**这件东西回到原格、光标清空**
   （不是「挂在光标上」）；落空手/从银行主格或装备栏拖来的 ⇒ **一件都不加** + 一行如实说明。
② 光标上拿着东西时点【发送】⇒ 先出现「已放回原处（包 X 格 Y）」再开始寄；若认不出源格 ⇒ 一行如实说明
   且**一件都不寄**（`sending=false`）。
③ 背包整合在场时：那一件在背包格上出现**半透明遮盖 + 「附件」两字**；把它从列表移走 ⇒ 遮盖当场消失。
④ 全程**客户端寄件栏在发送前是空的**、光标上没有残留。

## 0.3.13 附件框的信息引导（tooltip）+ 快速删除

★**用户原话**：「附件框内做好**信息引导提示**. **推荐直接在背包内完成**邮件快速选择. 操作.
**邮件附件快速删除操作**.」

★★★**三条口径（改这一族必看）**：
1. **引导只有一份**：`m.attach_tip_lines()` 产出全部引导行（标题 / 背包流推荐 / 拖放 / 单格删 /
   整批清空 / 发送），**附件格悬停与计数框悬停共用同一份** —— 两处各写一份 = 下一个漏改点。
2. **占用格的气泡 = 客户端的物品信息 + 只追加**（`SetBagItem(包, 格)` 照旧先出那一件的完整信息，
   我们只在后面补「点这一格 = 从列表移除」+「推荐在背包里选」两行；**绝不 `ClearLines`** ——
   那会把客户端的属性 / 商人价全抹掉，是 0.3.4~0.3.8 那一族的老雷）。**空格才 `ClearLines`**：
   客户端 XML 模板那句 `ATTACHMENT_TEXT` 是句没有信息量的大白话，换成我们的引导（这是「信息引导」的落点）。
3. **删除两档，都不碰物品**：单格 = **点附件格**（左键 / 右键都行，0.3.11 起就是纯数据）；
   整批 = **右键那个计数框** ⇒ 唯一动作口 `m.multi_clear()`（只抹列表数据 + 重投影），
   清完如实报「已清空选择列表（N 条）—— 背包里的东西一件都没动」；本来就是空 ⇒ 如实说一句、不假装做了事。

★**接线四处**：`sendmail_load` 的附件格循环里多两行 `SetScript( "OnEnter" /
"OnLeave", m.attachment_button_on_enter / _on_leave )`（覆盖 XML 模板那两个处理体；
★XML 模板的 OnClick 末尾那句 `this:GetScript('OnEnter')()` 照旧成立 —— 它现在调到的是我们这份）·
`m.multi_box_build` 的计数框 `OnEnter` 在列表内容之后**追加**同一份引导 + 新挂 `OnMouseUp`
（**鼠标键按本项目 idiom 取**：先看处理体第二个实参、再退回全局 `arg1`）·
`/tm 附件 帮助`（别名 `提示`）把引导摊到聊天框 · 悬停提示行也加了两行用法。

★★★**文案 = 短键，两套语言包都必须给值**（`ATT_*` 共 9 个键）：本移植版的本地化是「`localization.lua`
（EN，值写 `nil` 表示「键名即英文」）+ `localization.cn.lua`（CN，覆盖整张表）」，两边**都读**、
后者生效 ⇒ ★**短键绝不许只在一边给值** —— 缺了就会命中 `__index` 兜底，把 `ATT_TIP_TITLE` 这种
**键名直接画到气泡上**（判据 = 探针把两套语言包都跑一遍，逐键核「有值且不是 `nil`」）。

★判据 = **新增 `tmp/ehmail_attachguide_probe.js`（行为 6 组 + 语言包 9 键 + 源码钉 7 全过）**：
引导 ≥6 行且**不含键名**（`ATT_` 命中 = 假文案）· 推荐行点名「背包」· 占用格 = `SetBagItem` +
**ClearLines 0 次** + 追加两行 + `SetOwner` 恰 1 次 · 空格 = `ClearLines` 恰 1 次 + 不调 `SetBagItem`
+ 整份引导 · `OnLeave` 收气泡 · 整批删除 = `m.multi_clear` 恰 1 次 + 零物品操作 + 返回条数 + 如实出声 ·
空列表 ⇒ 返回 0 且**不调** `multi_clear` · **引导块里 ClearCursor / PickupContainerItem / `m.multi_list = {}` 各 0 处**
（纯数据 + 不许绕开唯一动作口）· `/tm 附件 帮助` 在 · 版本现读互比。
★★**这条探针当场抓到一处真 bug**：占用格那三行 `AddLine` 写成了 `pcall( tip.AddLine, "…" )` ——
**漏了 self**（`pcall(f, …)` 不会自动带对象）⇒ 真机上那两行提示根本出不来。
**纪律**：本文件里凡 `pcall( 对象.方法, … )` 一律要把**对象自己**当第一个实参（判据已覆盖这一族）。

## 0.3.14 日志页 = 小图标方格聚合展示（照宿主图标库的布局形式）

★**用户原话**：「子插件邮箱已发送日志tab: 已发送和已收到进行**小图标方格聚合展示**. **参考图标库的布局形式**,
tooltip 信息提示是这个邮件的**发件人.附件信息.金币**等等, 然后**点击这个日志图标可以快速切换到发件箱**.
**填充这个日志邮件的发件人**操作.」

★★★**四条口径（改这一族必看）**：
1. **一格 = 一封邮件**（同名不合并 —— 合并了就没法回答「点这一格是回哪一封」）；网格 = **9 列 × 10 行 = 90 格**
   （`m.LOG_COLS/ROWS/CELL/TILE/ICON/PAD`，**唯一几何来源**：格子 28 + 步进 30 + 内边距 4 ⇒
   宽 4+9*30-2=272 ≤ 296、高 4+10*30-2=302 ≤ 312，正好铺满滚动框）。
2. **池子建一次、脚本设一次**（照 `IconBrowser` 的写法）：数据走 `c.entry` 现读，**绝不每页重设 `SetScript`**
   （本客户端 `SetScript` 是单槽位）。★池子复用 ⇒ **每一趟 `populate` 都要显式 Show/Hide**（`log[i]` 为 nil 就收起）。
3. **tooltip = 这一封的全部信息**（对方 / 主题 / 附件 / 金币 / 到付 / 时间）+ **末行写清「点一下会做什么」**；
   图标兜底顺位 = **物品贴图 → 拍卖行图章 → 退回图章 → 通用便签**；右上角小图章 = 拍卖行 / 退回；
   右下角小色块 = **到付（橙 1/0.55）· 有钱（金 1/0.82）**，都没有就收起。
4. **点一下 = 先切到写邮件页、再把收件人填成「对方」**（`m.log.tile_click`；**顺序即判据** ——
   切页会触发一次 `SendMailFrame_Update`，先填后切会被它擦掉）。「对方」= `entry.participant`：
   已发送那页是**当年的收件人**（再寄给他）、已收到那页是**来信的发件人**（回信给他）；
   **拍卖行 / 系统寄来的没有对方 ⇒ 只切页面 + 如实说一句**（绝不编一个名字填进去）。

★★★**滚动/分页单位从「10 行文字」改成「行」**：`populate(type, index)` 的 `index` = **首个可见行号**，
滚动条 `SetMinMaxValues(0, ceil(N/COLS) - ROWS)`、`SetValueStep(1)`；滚轮 = `arg1*3` 行、上下按钮 = 一整页（`m.LOG_ROWS` 行）；
不给 index ⇒ 落在**最新一页**（老写法那条「下一拍补一次滚动条」的 hack 原样保留）。

★★★**旧的那套「10 行文字行控件」整条退场**（不是留着不用）：`EHMailTMLogItemTemplate` + `EHMailTMLogItem1..10`
**从 XML 里删掉**（129 + 12 行），`log.load` 里的逐行字体/颜色/锚点块与 `populate` 里的逐行渲染/逐行 `SetScript`
一并删除；宿主 `EHMailTMLogEntriesFrame` 尺寸改成 **292×306**（网格铺满）。
★删除脚本自带**配平自证**（逐标签数「删掉那一段里开 == 闭」+「整份文件净开合删前删后一致」+「残留引用 0」），
**不平就整份不写盘**（一次性脚本用完即删）。
★`m.log.fontSet` 因此只剩一个调用者 —— 日志页现在唯一的文字是**状态行**，它继续走这条字体链（0.3.3 的判据不悬空）。

★判据 = **新增 `tmp/ehmail_loggrid_probe.js`（行为 6 组 + 语言包 14 键 + 源码钉 8 全过）**：
池子 90 格 + 行优先锚点（首格 4,-4 ｜ 第 10 格 4,-34 ｜ 末格 244,-274）+ 幂等（再建 0 个）· 三件脚本建池时设一次 ·
图标兜底四态 + 两个角标（含色值）· 空格收起并清账 · **悬停 = 五行信息 + 末行「点一下会做什么」+ Show** ·
悬停提亮/离开恢复 + 收气泡 · **点一下：切页 1 次 + 收件人 = 对方 + 聚焦 + 出声**；
对方为空 ⇒ 切页但**一个字都不填**；空格点了零动作 · populate 行单位分页（`max = ceil(100/9)-10 = 2`）·
状态行 = `共 N 封 ｜ 当前显示第 a-b 封` · 不给 index 落最新一页（尾部空格收起）· 空日志 ⇒ 90 格全收起 + 0/0/0 ·
**旧控件在 Lua 与 XML 里都 0 命中** · XML 宿主尺寸 292×306 · **顺序钉「先切页后填名」** ·
**`pcall( tip.X,` 全部带 `, tip`**（0.3.13 那条 self 教训的延续）· 版本现读互比。
★桩的两条保真点：客户端是 **Lua 5.1（有 `math.mod`）**、fengari 是 5.3（没有）⇒ 探针补 `math.mod`；
`pairs{ icon = nil }` 在 Lua 里是**空表**（nil 值 = 键不存在）⇒ 造「没有物品贴图」的夹具必须**显式赋 nil**。

## 0.3.15 关邮箱 = 附件选择**整体作废**（背包里的「附件锁定」必须一起清干净）

★**用户原话**：「在邮箱关闭之后. 要做好**背包内附件锁定清理**的流程.」（口径由用户选定 = **整体作废**）

★★★**为什么关邮箱必须清理 —— 两处外观都由这份选择列表派生，而它们谁都不会自己复位**：
1. **背包整合（EH_Bag 0.3.48）那层「附件」遮盖 + 备注文字**：判定口 `B.mailListOn` 只问
   `EHMailTM.multi_has(包, 格)` ⇒ **列表不空 ⇒ 关掉邮箱之后遮盖照旧画在背包格上**（它的重画要人来喊）。
2. **客户端自己的背包格**：`hook.GetContainerItemInfo` 给选中格伪报 `locked`（= 选中反馈），而客户端是
   **画的那一拍**读它 —— `ContainerFrame_Update` 里 `SetItemButtonDesaturated( itemButton, locked, 0.5, 0.5, 0.5 )`
   （客户端 `ContainerFrame.lua:246`，**离线证据** = `tmp/mpq_out/Interface/FrameXML/ContainerFrame.lua`）
   把图标压灰 ⇒ **关邮箱之后没有任何事件让它重画**，最后一次画上去的灰化就留在屏上。

★★★**唯一清理口 `m.multi_release( why )`**（`MAIL_CLOSED` 除了原来的 `inbox_abort` / `sendmail_sending=false` /
`sendmail_clear()` 之外**只多一行**调它），四步**顺序即判据**：
① 数据整体作废（`m.multi_list = {}`）→ ② `m.multi_project()`（邮箱关着时它只做开头那一步
`m.multi_tell_bag()` ⇒ **背包整合的遮盖当场收起**）→ ③ `m.bag_repaint()`（★见下）→ ④ 如实出声
（**只有真清掉了东西才说**，`REL_CLOSED` 一句、`%d` = 条数；本来就是空 ⇒ 一声不出，不刷屏）。
★**先清数据再清外观**：反过来的话，重画那一刻列表还在 ⇒ 遮盖会被照旧算出来画上。
★**全程纯数据**：不碰光标 / 不碰客户端寄件栏 / 一件物品都不动（0.3.11 的口径一个字节没改）。

★★★**`m.bag_repaint()` = 让背包格重画一次**（本客户端**没有**「主动刷新某个格子」的 API，只能这样）：
- 读 `m.api.ContainerFrame_Update`（客户端的 FrameXML 更新口）；**不是 function 就返回 0**；
- 遍历 `ContainerFrame1..12`（客户端容器帧的**具名族**，实测见 `tmp/mpq_out/.../ContainerFrame.xml`
  = `ContainerFrame1..12`），**只对 `rawget(_G, 名) ~= nil` 的帧**逐个 `pcall( upd, fr )`；返回真调过的帧数；
- ★★★**绝不给任何全局赋值**（不硬造 `ContainerFrame_Update`、不写别人的帧）—— 拿不到就**一个字节都不碰**：
  真机上后果只是「外观留到下一次背包刷新」，**绝不是丢东西**（拿不到证据就一个字节都不碰）；
- 背包整合在场时那一趟是**它的包装**（只 `Hide`），外观长在它自己那批按钮上 —— 由 ② 那一步的桥负责。

★**取证/诊断**：`/tm 附件 状态` 的现场读数多一行「上次清理：清空 N 条 ｜ 重画客户端背包帧 M 个 ｜ 原因=…」
（纯读、不落存档；真机上「背包还锁着」时这一行直接给答案）。

★判据 = **新增 `tmp/ehmail_closeclean_probe.js`（行为 8 组 + 语言包 1 键 + 源码钉 10 全过）**：
关邮箱 ⇒ 列表清空 + 原先答「在列表里」的那格现在答「不在」· `sendmail_clear`/`inbox_abort` 各 1 次 ·
桥恰 1 次 + 真调过 3 个容器帧（只对**存在**的帧）· **通知那一刻与重画那一刻列表都已空**（顺序两条）·
出声恰 1 次且点名条数与「一件都没动」· 列表本来就空 ⇒ **一声不出**但桥照旧 · 邮箱开着时走同一个口 ⇒
21 格投影全收起 · 关着时直接走它 ⇒ 投影**一个字节都不写** · 没有那个更新口 ⇒ 0 帧且**不硬造全局** ·
某帧抛错 ⇒ 计数只算成功的、其余照跑 · 桥三态（不在场 / 没这个口 / 会抛错）不崩 ·
**全程物品操作 0 次** · 语言包 EN/CN 都有值且都带 `%d`；
源码钉含 `multi_release` 排在 `sendmail_clear` 之后 · 块内两条 `indexOf` 顺序钉 ·
**反向钉「重画口不给全局赋值」** · **反向钉「一个物品操作都没有」** · `multi_project` 开头那句桥在早退之前。

★★★**真机复验点**：① 选几件 → 关邮箱 ⇒ 聊天出现「邮箱已关闭 ⇒ 已清空附件选择列表 N 条…」，
**背包格上的「附件」遮盖当场消失**（背包窗开着时看得见）、客户端自己的背包格**灰化也消失**；
② 再开邮箱 ⇒ 附件格是空的、选择从零开始（这是选定口径）；③ 空手关邮箱 ⇒ **不该有任何一行字**。

## 0.3.16 批量面板 = 默认关（判据收在一处）+ 触发按钮带图标（**自绘**，占地不变）

★**用户原话（两轮）**：「批量面板,默认关闭.触发的按钮添加个图标宏图标序号:454这个图标」→
真机复验后：「图标未显示.并且超过界限」+「**图标可以换成我插件自定义规范的图标按钮也可以**」

★★★**五条口径（改这一族必看）**：
1. **默认档的判据只此一处**：`EHMailTM.batch_panel_want_open()` ——
   **显式 `false` = 「玩家打开过」**；缺键 / `nil` / `1` / `0` / 任何垃圾值一律按**关**处理。
   ★★**判据必须写 `== false`、绝不能写真值性判断**：`0` 在 Lua 里是**真值**；
   ★**写入口径**：打开 = **显式 `false`**（记住这次选择）· 收起 = `1`。
2. **两个落点都走它**：`batch_load` 的**早退支**（已有面板时不再无条件 `Show()`）+ **首次建好的尾巴**
   （`if not m.batch_panel_want_open() then panel:Hide() end` —— 客户端建出来的帧**默认是显示的**，
   这一句才是「默认关」真正的落点，少它 ⇒ 第一次开邮箱照样弹出来）。
3. ★★★**占地 = 原来的 22×26，绝不再加宽**（`m.PANEL_TOGGLE_W/H`）：第一版按图标号把按钮加宽到 34 ⇒
   **真机报障「超过界限」**（按钮顶到邮箱可见边框外面）。**反向钉**守着不许再加宽。
4. ★★★**图标 = 自绘**：`m.PANEL_TOGGLE_TEX` = `Interface\Buttons\WHITE8X8`（本项目**唯一可靠**的贴图）
   + `SetVertexColor` 金色 `1,0.82,0.25`，`m.PANEL_TOGGLE_BARS` **6 条纯色纹理** =
   外框四条 1px + 里面两条短横线（「面板 / 列表」）。
   ★**第一版走宏图标 454 的路径 ⇒ 真机「图标未显示」还画出一块占满按钮的红**（= 贴图加载失败，
   本项目在案「配好了却看不见 / 一次都没贴上过」那一族；`doc\图标路径清单.txt` 是按字母排序的，
   **行号 ≠ 宏图标号**）⇒ 现在**不依赖任何图标路径**（反向钉：全文件 `GetMacroIconInfo` /
   `/Game/Interface/Icons` / `INV_Gizmo` **各 0 处**），结构上不可能再贴不上。
5. ★★★**「隐藏态写属性不落地」这条老雷必须防住**（EH_Bag 0.3.21/0.3.25 在案，本插件同类）：
   这个按钮在 `ADDON_LOADED` 里建，**那一刻邮箱窗还没显示** ⇒ 那时写的尺寸/锚点**不生效**
   （真机症状 = 图标看不见 / 控件跑到框外；第一版连 » 都看不见就是它 —— **没有锚点的 FontString
   什么都不画**）⇒ **全部几何收在一处 `m.panel_toggle_apply_icon()`**（幂等、可重复调用），
   除建时一次外**三条重申腿**：① 按钮自己的 `OnShow`；② `MAIL_SHOW`；③ `hook.InboxFrame_Update`
   （**自终止**：`apply_icon` 只在按钮**真的可见**时置 `m.toggle_visual_ok`，在那之前每 tick 再来一遍）。
   ★两态箭头 `» / «`（金光，捞哥要求不做变灰）**保留**，画在**自建**的那条 FontString 上
   （按钮模板自带的文字居中、会压住图标）；拿不到它 ⇒ 退回按钮自己的文字（fail-open）。
   ★对象守卫一律按 `type` 判 table/userdata（宽容桩「没设过的字段回函数」写 `~= nil` 会当场
   `attempt to index a function value`）；每条纹理的 `SetTexture/SetWidth/SetHeight/ClearAllPoints/SetPoint/
   SetVertexColor/Show` **一律 `pcall`**（客户端的 `Set*` 静默失败族）。

★**几何/常量一律挂 `m` 表**（`m.PANEL_TOGGLE_W/H/ICON/TEX/GOLD/BARS`）—— 本文件主 chunk 局部量有上限，
**不新增文件级 local**。

★判据 = **`tmp/ehmail_batchpanel_probe.js`（行为 30 + 源码钉 16 全过）**：
默认档五态 · **自绘图标 6 条逐条核对**（贴图 = WHITE8X8 · 上/下 10×1 锚 `(+1,-8)/(+1,-17)` ·
内两条 6×1 锚 `(+3,-11)` · 金色 `1.00/0.82/0.25` · 各 `Show` 一次）· **幂等（连调两次值不变）** ·
**自终止门两态**（可见 ⇒ 置 / 不可见 ⇒ 不置）· 坏对象/坏数据六态不报错 · 两态文案三态（含 fail-open 退回）·
**两个落点用真源码切片真跑**（缺键 ⇒ 0 次 `Show` / 1 次 `Hide`；显式 false ⇒ 1 次 `Show` / 0 次 `Hide`）；
常量与图标表**从真源码现读**（防探针漂移）；反向钉：占地必须 22×26 · 不许出现任何图标路径/宏图标口 ·
不许退回手工纹理句柄 `m.panel_toggle_icon` · 不许直读标志真值性 · 三条重申腿各 1 处 · 版本互比。
★★**变异自检（当场做、做完还原并核过逐字节）**：① 去掉 `pcall(bar.Show, bar)` ⇒ **3 条转红**；
② 占地改回 `34` ⇒ 占地那**1 条转红**（正是用户报障那条）。
★★★**真机复验点**：① 开邮箱 ⇒ **批量面板是收起的**（按钮上是 «）；② 按钮左侧有**金色自绘图标**
（外框 + 两条短横线；若看不见 = 「隐藏态写属性不落地」那条重申腿没生效，去核
`/tm` 之外的三条腿）；③ 点按钮 ⇒ 展开、变 »、悬停写明「收起批量面板」，再点收起；
④ 按钮**不越过邮箱可见边框**（占地与加图标之前一模一样）；⑤ 展开过一次后 `/reload` ⇒ 照旧展开（记住选择）。

## 0.3.17 播报前缀 = 插件目录名 `[EH_Mail]`（不再用内部表名 `EHMailTM`）

★**用户原话**：「调整邮件载入信息命名,子插件命名统一采用 EH_xxx 方式.**将这项规定加入子插件开发规范记忆体**」
（起因 = 真机截图里那行 `EHMailTM: Loaded (v0.3.16)`，别的子插件都是 `[EH_Bag]` / `[EH_Damage]` / `[EH_DPS]` / `[EH_DebugBox]`）。

★★★**三条口径**：
1. **唯一来源 = `m.ADDON_NAME = "EH_Mail"`**（`EHMailTM.lua` 文件头，紧跟 `local m = EHMailTM`）—— 三处播报全走它：
   帮助头一行（`L["Help"]`）· `m.info` · `m.debug`（`string.format("|cff66ccff[%s]|r %s", m.ADDON_NAME, …)`）；
   `MailTo.lua` 那条「收件人下拉建不出来」的报障行同样取 `EHMailTM.ADDON_NAME`（拿不到 ⇒ 退回字面量 `"EH_Mail"`）。
   ★要改名只改这一处（宿主契约 ⑥ 的 ③）。
2. ★★★**内部表名 / 文件名一个字节都没改**：`EHMailTM` 照旧是表名 / 帧名 / 存档键前缀，`EHMailTM.lua` /
   `EHMailTM.xml` / `EHMailTM_Saved.lua` 照旧是文件名 —— **改的只是「面向玩家的聊天前缀」**
   （宿主契约 ⑥ 的 ②：第三方搬进来的内部名**只许出现在代码里**）。颜色 `|cff66ccff` 不变。
3. **探针部分**（`EH_Mail.lua`）本来就是 `[EH_Mail]` ⇒ 现在两部分同名同前缀。★**行为改变已出声**（写进 `CHANGELOG.md`）。

★判据 = **`node tmp/subaddon_naming_probe.js`（纯读、5 个目录全绿）**：① 目录名形态 · ② 该目录里**所有** `[EH_xxx]`
前缀逐字等于目录名 · ③ 名字 → 前缀的**单一来源**（本插件 = 字面量 `[EH_Mail]`；EH_Damage 是 `"[" .. ADDON_NAME`
那一支，两种都收）· ④ **反向钉**：剥掉颜色码后，聊天字面量里不许出现「内部名 / 别人的名字**当前缀**」
（本插件内部名清单 = `Calendar` / `EHMailTM` / `EHMailTM_Saved` / `MailTo` / `localization` / `localization.cn`，全 0 处）。
★**变异自检（当场做、做完还原）**：把 `m.info` 前缀改回 `|cffabd473EHMailTM|r: %s` ⇒ ④ 当场转红并点名字面量。

## 已知欠账

* ★**0.3.17（前缀改 `[EH_Mail]`）真机一眼可验**：`/reload` 后载入那行应是 `[EH_Mail] …`（不再是 `EHMailTM: …`），
  帮助头一行、之后的报错/诊断行同样 —— 改的只是**聊天前缀**，功能行为一个字节没动。
* ★★★**0.3.15（关邮箱 = 附件选择整体作废）必须真机复验**：复验点见上面那一节末尾三条 ——
  关键判据 = **关邮箱后背包格上的「附件」遮盖与客户端灰化一起消失**（背包窗开着时肉眼看得见），
  且**空手关邮箱一声不出**。★离线判据只能证明「桥被喊了、容器帧被重画了」，
  **证明不了「客户端认不认那一下重画」**（`ContainerFrame_Update` 在本客户端到底在不在也靠真机看）。
* ★★★**0.3.11（纯数据附件）必须真机复验**（复验点 = `/reload` 后：① 右键背包物品 ⇒ 附件格立刻出现那一件，
  **背包里没有任何物品被拿起来、光标不动、也没有 `ITEM_LOCK_CHANGED` 卡顿**；再右键同一件 ⇒ 从列表消失；
  ② 左键点背包物品 ⇒ 客户端原样拿起/放下，附件格里那一件**跟着消失/回来**（放回原处就回来）；
  ③ 左键与右键点附件格 ⇒ 只从列表删掉那一格；④ 点【发送】⇒ 逐件寄出，收尾出现
  「已寄出 N 件已从选择列表移除（列表还剩 M 条）」；⑤ **客户端寄件栏全程是空的**（只在寄的瞬间短暂占用）；
  ⑥ 若某件寄不出去 ⇒ 出现一行「附件（包 X / 格 Y）…—— 跳过这一件」，且**光标上没有残留物品**）。
* ★★★**0.3.1~0.3.3 的改动尚未真机复验**（复验点 = `/reload` 后：① 收件箱/写信页**任意地方拖不动**、
  标题栏也拖不动（拖窗口改用宿主工具箱「拖拽图层」）；② region 守卫后不再弹 `SetTexCoord` 红字；
  ③ 日志页（0.3.14 起 = **小图标方格**）：两个页签都能铺满一屏图标、悬停出那一封的全部信息、
     点一下切到写邮件页并把对方填进收件人；**空日志**时一个格子都不留残影、状态行显示 `共 0 封 ｜ 当前显示第 0-0 封`；
  ④ 批量寄送多封（**本轮重定为「跳过并继续」**）：偶发一次挂不上寄件栏 ⇒ **自动重试**（连续 3 次上限）；
     仍挂不上且**光标干净** ⇒ **跳过这一件、继续发后面的**（不是整批停下），收尾打一行
     `本次共跳过 N 件（拿不起来 M ｜ 已不在原处 K）`；只有**光标上还留着东西**才硬停（点名物品）。
     ★★**开批前若客户端寄件栏里已经有东西（不是本插件放的）⇒ 现在会直接停下、一件都不发**并提示玩家
     先取出（`不是本插件放的` / `已停下，没有寄出` / `然后再发一次` 三句）—— **这是有意为之**：
     照旧往下跑会把那件残留吃掉、并让客户端此后拒绝一切取件（见上文本条 ①b）。
     ★**这就是第三轮真机报障（`发送出去了一半`）的修法**：残留吃掉后全批拿不起来 ⇒ 只有先前批次发出去的那半；
     现在改为**当批停下 + 让玩家清干净再发**。
     ★对照判读：界面上「还在发」而物品没寄出 = 老版静默卡死；现在必须**看到那行跳过汇总**才算生效；
  ⑤ 写信页收件人右侧下箭头的下拉**落在输入框正下方左对齐**；
  ⑥ ~~日志页每一行文字齐全~~（**已被 0.3.14 取代**：日志页现在没有文字行了 —— 详情全在图标悬停气泡里）；
  ⑦ 批量寄送失败时**打出可截图的诊断**（格子 / 该格链接 / **拿起后**光标 / 现在光标 / 寄件栏 / 连试次数），
     按「拿起后=空 ⇒ 客户端拒绝取件」与「拿起后=有 ⇒ 放置失败」两条分流；
  ⑧ 批量操作**限频生效**（0.5s/件，四处写动作共用同一个闸；感受上批量会变慢，属预期）；
  ⑨ 收件人历史**`/reload` 后还在**且**换角色也在**（已改账号级 + 老数据迁移；添加时会打一行取证，`==存档表?` 必须 true）；
  ⑩ 右侧筛选勾选框（含「本页全选」）**点方框或点文字都能勾上**（已换成客户端原生 CheckButton、命中区 = 整格）；
      点「筛选」按钮还能弹出多选框（第二入口，状态与面板同步）。
  **行号会变，别拿行号当判据**）。
* ★★★**真机已跑过一轮（0.2.0 那次）⇒ 暴露了存档红框（已修，见「两个存档根」条）**；
  **0.3.0 改了存档层与全部标识符 ⇒ 必须再验一次**，看四处：
  ① **进游戏不弹红框**（这是 0.3.0 的头号判据：`## SavedVariables` 单名字 + 坏存档已删）·
  ② 有没有别的红字（`ADDON_LOADED` / `MAIL_SHOW` / `SendMailFrame_Update` 三条路径）·
  ③ 邮箱界面变成增强版（第 3 个页签「Log」、批量按钮、多附件）·
  ④ **存档能持久**：发/收一封邮件留条日志 → `/reload` → 日志、收件人下拉历史、自动补全名字**还在**
     （验两个存档根 + 代理真的在写；看不到就是代理或绑定那一步没生效）。
  ★若「XML 整份载入失败」（客户端在插件列表点名）⇒ `/email` **仍然可用**（探针排在前），
  用它 + 探针读数定位；必要时把 `EH_Mail.toc` 里 `EHMailTM.xml` 那一行注释掉即可**单独回退增强版**。
  ★金额框那三根边框线（R11 的 `SetDrawLayer`）**可能本来就没有** —— 够才设 ⇒ 看不出来属**预期**，不是故障。
* ★★★**R11 已在移植版里修掉**（`rs[ 9 ]` 守卫），但**探针仍会照旧报那 3 处越界** ——
  探针量的是**客户端原始控件**的属性，与移植版改没改代码无关 ⇒ 那是**正确读数**，不是探针坏了。
* **只报「在不在」、不报「行为对不对」**：「名字在」≠「表现和 TurtleWoW 一致」—— **R11 就是活证据**
  （名字全在，但「第 9 个 region」这个**口径**不同）⇒ 真机装载一次上游插件看红字仍是最终判据。
* 本版**不判断第三方插件冲突**（例如以后启用 unrealUI 的邮件皮肤 ⇒ 可能改 region 顺序，`REGIONS` 组会先报出来）。
* **功能本体（邮箱增强）已落地**（0.3.0，见上节）——
  名字层已排除 R1/R3/R4、R11 已修、pfUI 已剔除；**剩下的只有真机验收**。
  ★ 移植版里 `/tm` 的少数**诊断回显**仍带 pfUI 字样（如 `/tm paneloff` 的状态行）——
  那是**只读回显**、不是皮肤功能，刻意不删（删它要动命令体、零收益）；别把它当成"pfUI 没剔干净"。
* ★**夹具欠账已清**（0.1.1）：`ehmail_harness.js` 的 ④ 组原先把 `TEMPLATES` 白名单砍到 1 个且**没复原**
  ⇒ 此后每轮都带回 4 条模板缺失（会把「缺 0 项」的读数污染掉）；现在 ⑪ 组开头先复原白名单。
