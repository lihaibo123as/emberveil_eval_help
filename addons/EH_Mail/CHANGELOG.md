# EH_Mail 改动记录

> 版本口径：子插件 `0.1.x` / `0.2.x` ↔ 宿主 `EvalHelp 1.75.y`（同轮一起改）。
> 判据与锚点 = `addons/EH_Mail/CLAUDE.md`；离线调研与风险清单 = `doc/TurtleMail-API支持度调研.md`。

## 0.3.3（宿主 1.75.112 同轮 · 2026-10-10）

**真机第三轮报障：窗口到处都能拖 / 日志不记 / 批量寄送有一次「错误」。**

### 1. 内置拖拽整条关掉（用户定：宿主工具箱已有「拖拽图层」）

* 现象（用户原话）：「在收件箱 tab 就会出现拖拽，**任意地方**都会出现」。
* 根因：上游为了让「背景处也能拖」，把 `InboxFrame` / `SendMailFrame` 的鼠标整个关掉
  （两处 `EnableMouse( false )`），而本客户端只要在 `MailFrame` 上按下有位移就起拖
  ⇒ **收件箱/写信页几乎整片空白都是拖拽热区**。
* 处置：**注册与处理体一起撤**（`pcall` 撤 `RegisterForDrag` + `OnDragStart`/`OnDragStop` 置 nil），
  连中途加过的「标题栏拖拽柄」也一并删；**位置记忆也全删**（`restore_position` / `on_drag_stop` /
  `UpdateUIPanelPositions` 钩子 / 关窗记点）。
* ★**为什么位置记忆必须删**：宿主「拖拽图层」的真机存档里就有
  `["MailFrame"] = { dx, dy, base = … }`（且**没有** `axAuto` ⇒ 属用户自定义 ⇒ 宿主每 0.3s 守它）
  ⇒ 两边同时写位置 = 必然互抢（拖了被拉回）。现在位置完全归客户端与宿主。

### 2. 批量寄送失败：从「整批静默卡死」改为「有界重试 ⇒ 拿不起来就跳过、继续发后面的」

* 现象（用户）：① 发送多封时偶发 `EHMailTM：错误`（源码里搜不到「错误」二字 —— 它是客户端本地化常量
  `m.api.ERROR_CAPS`，zhCN 即「错误」）；② 「在多邮件内方式无之后.将物品有拿出了.然后在放入其他物.
  但是内部的数据没有更新.当发送的时候发送的还是第一次的物品.然后再放第二个的时候就提示图2的情况.
  无法发送物品.导致批量发送失败」。
* ★★★**逐行对照参考插件后的定案**（用户：「之前邮寄是可行. 查看参考插件是如何邮寄逻辑的」）：
  参考插件 `tmp/TurtleMail/TurtleMail.lua` 的 `sendmail_send` 与移植版**逐字一致**
  （ClearCursor → ClickSendMailItemButton → ClearCursor → PickupContainerItem →
  ClickSendMailItemButton → not GetSendMailItem() 判定）⇒ **移植没有抄错，这个报错不是移植引入的**。
  对照是机械做的、可复算：`node tmp/tm_sendmail_diff.js` —— 邮寄链上真正决定行为的函数**全部「代码逐行相同」**，
  有差异的 5 个全是已知移植适配（R11 region 守卫 / 删位置记忆 / 批量限频闸）或**本条的失败分支本身**。
* 真根因 = **参考插件失败之后的行为**：只打一行 `ERROR_CAPS` 就 `return`，而 `m.sendmail_sending` 仍是 true、
  `sendmail_update` 再没人设 ⇒ **这一批静默卡死**（后面的件永远不再发，界面上却像还在发）。
* ★★★**「内部数据没更新」的主根因 = 附件格的处理体从来没被挂上**（详见第 17 项）——
  拖着物品放进附件格时走的是**客户端自己的行为**，物品真的进了客户端附件栏 ⇒ 界面 / 记账 / 背包三份状态各说各话；
  而**进过客户端附件栏的物品会被客户端锁住**，之后 `PickupContainerItem` 拿不起来（真机「连试 4 次」）。
* 处置（**挂件序列与成功路径一字未改**，只改失败路径）：
  ① 进函数**先查光标**（有东西就如实报一声停下，绝不清光标 —— 与子插件 `EH_Bag` 的 `DROP_CURSOR` 同一口径）；
     开批处（`send_mail_button_onclick`）另**看一眼客户端附件栏**：`GetSendMailItem()` 非空 =
     玩家以前拖放进去的残留 ⇒ 如实提示「建议先取出，或重启客户端再发」，**绝不替他取出**。
  ② 挂件前**校验那一格现在还有没有东西**（记账只记 `{bag,slot}`、不记身份）：空 ⇒ 计入 `m.sendmail_skipped`
     并**跳过这一件、继续发后面的**。
  ③ 挂不上寄件栏 ⇒ **放回队首 + 延迟一帧重试**（同一帧里紧挨着的 `ClearCursor`/`PickupContainerItem`
     会撞客户端的物品锁，下一帧锁就松）⇒ 一次抖动不再让整批中断；**连续**失败到 `m.sendmail_retry_max`（= 3）
     之后才分流：**光标上还留着东西 ⇒ 硬停**（后面必然连锁失败）；**光标干净却拿不起来 ⇒ 计入
     `m.sendmail_failed` 并跳过这一件、继续发后面的**（这一支**绝不执行 `SendMail`** ⇒ 不会寄出空邮件）。
  ④ 失败点照旧打出**可截图的现场诊断**：`诊断：格子 bag/slot ｜ 该格现在=<链接> ｜ 光标上=有/空 ｜
     寄件栏=有/空 ｜ 连试 N 次` —— 用来区分「格子快照失效 / 光标连锁 / 寄件栏残留」三种根因。
  ⑤ 整批收尾（附件队列空）打一行汇总 `本次共跳过 N 件（拿不起来 M ｜ 已不在原处 K）`，然后清掉计数；
     成功挂上一件即把连续失败计数清零（有界，绝不死循环）。
  ★★★**三个会话计数在开批处复位**（`m.sendmail_skipped` / `m.sendmail_failed` / `m.sendmail_retry`）——
     不复位则上一批硬停时攒下的数会算进这一批的汇总，而 `sendmail_retry` 会带着上一批的连败数起跑
     ⇒ **这一批第一件一失败就被判超限、整批直接跳过**。
  ★★★**「拿不起来」= 客户端锁件**（本轮决定性证据）：同一格、同一时刻，**子插件 `EH_Bag` 的
     「右键直投 → 邮件附件栏」也报同一句失败**（`EH_Bag` 打「没能把这件物品拿起来」）⇒ 两个插件都拿不起来、
     且光标是空的 ⇒ 那件物品被**客户端自己**锁住了，**只有重启客户端才解**；重试多少次都不会好
     ⇒ 必须**跳过并继续**，否则整批被一件死锁件拖死。
* 语言键：新增中性措辞 `Could not attach %s - this mail was not sent`（旧键那串「东西还在光标上」留给
  **光标守卫**那一路 —— 它那一路措辞是准确的）。
* ⚠️**已知风险（参考插件同样有，本轮未改）**：判定只看 `GetSendMailItem()` 非空 ⇒ 若附件格快照已失效
  （那格换成了别的物品 / 客户端附件栏本来就有残留），会把**别的东西**寄出去并且判定为「成功」；
  开批处那条残留提示就是为此准备的**唯一可见信号**；要根治得加「寄出前后比对物品链接」，属下一步。
* 判据：`luacheck` **SYNTAX OK** · wiring 该段（寄送）新增/改写 5 条（放回队首恰 2 处 · 失败分流两支 ·
  开批复位三计数 · 附件栏残留提示 · 跳过汇总行含两类根因 + 诊断行在 + 反向钉 `m.api.ERROR_CAPS` 0 处）。

### 3. 日志：未读邮件也记 + 去重 + 空数据也清界面

* 口径（用户定）：未读也要记 —— 原条件 `if ( read or manual )` 让**批量取件时未读邮件一条都不记**
  （真机证据：存档 `tm_log.Received` / `tm_log.Sent` **两个族都是空表**，而收件箱里明明有邮件）。
* 顺带堵上游老毛病：同一封邮件反复打开会**重复入账** ⇒ 内容键 + **2 秒窗**去重。
* `log.populate` 原来 `if not log then return end` ⇒ **页面留着上一次的残留**（用户截图里的
  「显示1-2，总共2」而列表全黑就是它）⇒ 改成 `if not log then log = {} end`，空数据也走完渲染
  （10 行全 `Hide` + 计数归零 `显示0-0，总共0`）。

### 16. 勾选框样式全自绘（用户：「选中框的样式还有点欠缺」）

* 现象（用户截图）：勾选框能勾了，但**方框只剩左边一条竖线**。
* 根因：第 14 项那条「非方图才按比例裁切」的逻辑 —— **客户端那批 `UI-CheckBox-*` 不是正方形**
  （多为横向图集）⇒ 按 16x16 取左上角只截到了框的一角。★图集怎么切**不能靠猜**，所以不再用它。
* 处置：**样式全部自绘**（本项目在案的纯色纹理只有 `Interface\\Buttons\\WHITE8X8` + `SetVertexColor` 可靠）：
  · **方框** = 暗底（`0.06/0.06/0.06/0.85`）；
  · **框线** = 四条 **1px 亮边**（上/下各拉满宽、左/右各拉满高，`EDGES` 数据表 + 一个循环，颜色 `0.62`）；
  · **选中态** = 内部一块**亮绿实心块**（内缩 3px，`0.25/0.85/0.35`）—— 用实心块而不是「勾字符」，
    避免字形/编码风险；
  · **悬停** = 暗底提亮（纯显示，不改状态）。
* ★**控件仍然是客户端原生 `CheckButton`**（checked 态与命中区由客户端管 —— 「点得着」的关键），
  我们只接「画」这一层；选中块的显隐仍只在一处 `syncMark()` 同步（读客户端 `GetChecked()`）。
* 判据：`luacheck` **SYNTAX OK**（现 67 个文件 —— 其中 2 个是别的会话新增的，与本次无关）·
  wiring 该段 10 条（含反向钉「不使用客户端勾选框贴图」）· `sync_game` 改 3。
### 15. 真机红框：`SetCheckedTexture` 在本客户端不存在 ⇒ 勾自己画 + 贴图全 pcall

* 红线原文：`EHMailTM.lua:1272: attempt to call method 'SetCheckedTexture' (a nil value)`
  （栈：`checkbox` ← `batch_load`）—— 按本项目那条判读判据，这句的意思是**对象在、方法不存在**。
* 根因：**1.12 的勾选框把那个「勾」放在 XML 的 `<CheckedTexture>` 里声明**，
  **没有运行期 API**（`SetCheckedTexture`）⇒ 直接调用必崩。
* 处置两条：
  ① **贴图一律 `pcall`**（`SetNormalTexture` / `SetPushedTexture` / `SetHighlightTexture`）——
     本客户端并非每个 `Set*Texture` 都有，能设就设、设不上也不崩；
  ② **「勾」由我们自己画**（`CreateTexture(..., "ARTWORK")` + `UI-CheckBox-Check`，也过 `fitTex` 定尺寸），
     显隐**只在一处同步** `syncMark()`（读客户端的 `GetChecked()`，不自己存变量）——
     `OnClick` 与「包一层 `SetChecked`」两条路都调它 ⇒ 外面（`inbox_refresh_checkboxes` / `/tm filter`）
     改状态时勾也跟得上。
* ★**控件仍然是客户端原生 `CheckButton`**（checked 态与命中区由客户端管 —— 那是「点得着」的关键），
  我们只接「画」这一层：贴图尺寸 / 文字锚点 / 勾的显隐。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 该段 8 条 → **10 条**（含反向钉「`SetCheckedTexture` 不许回来」）·
  `sync_game` 改 1。
### 14. 勾选框版式修正（用户：「位置和尺寸调整下」）—— 去掉模板，贴图与文字自己定

* 现象（用户截图）：勾选框**已经能勾上**（√ 正常），但版式不对 —— 方框被撑得很大、
  「本页全选」的文字跑到方框老远，第二列看着像「文字在左、方框在右」。
* 根因：`OptionsCheckButtonTemplate` **自带 32x32 贴图 + 居中锚的文字** ⇒ 我们给按钮设的
  「16 高 / 92 宽」**压不住模板自己的口径**（贴图按文件尺寸画、文字按模板锚点画）。
* 处置：**干脆不用模板** —— `CreateFrame("CheckButton", name, panel)` + 自己贴四条贴图，
  并**把贴图按 16x16 贴到按钮左侧**（`fitTex()` 唯一实现，四个 Getter 都过它），
  **文字自己建**并锚在贴图右侧 4px。这样贴图尺寸、文字位置、命中区三样都在我们手里。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 该段 8 条（新增「无模板」「四条贴图都过 fitTex」
  「文字自己建并紧贴方框」）· `sync_game` 改 2。
### 13. 勾选框还原到面板上 —— 控件换成**客户端原生 CheckButton**（用户定）

* 用户选择：「我更想在面板上直接看到勾选框」（而不是只在弹窗里选）。
* 还原：11 个筛选勾选框 + 「本页全选」勾选框**都回到面板上**（面板高度也照原式算回来），
  「筛选」按钮弹出的多选窗**保留为第二入口**（两个入口共用一个写口 `batch_set_filter`，勾选状态双向同步）。
* ★★**控件换了**：不再用上一版自绘的普通 `Button`，改用**客户端原生 `CheckButton`** —— 两处关键差异：
  ① **checked 状态由客户端管**（不用自己实现 `SetChecked`/`GetChecked`、也不用自己显示那个勾）；
  ② **命中区由客户端算**，而我们把按钮宽度设成**整格 `CELL_W`** ⇒ **点方框、点文字都是点它**。
     （原来「16x16 方框 + 独立标签按钮」那种拼法，正是「点方框没反应／点文字点不到」的根源。）
* ★绕开上游那个坑：注释里说 `OptionsCheckButtonTemplate`「在不同客户端会错位」—— 那是**模板自带尺寸/锚点**
  造成的；我们**建完读回自证**（`GetNormalTexture()` 拿不到就自己贴一套四条贴图），尺寸与锚点全由我们定 ⇒ 无从错位。
  模板名本身若不可用，`pcall(CreateFrame, ...)` 兜住后退回「无模板建」。
* 回调统一成**只传新状态**（`onclick( cb:GetChecked() and true or false )`）⇒ 与弹窗那条入口同签名，
  `batch_set_filter(key, on)` 一处写、两处显示。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 该段由 7 条改为 **8 条**（含「命中区 = 整格」「贴图自证」
  「两入口同写口」）· `sync_game` 改 2。
### 12. 筛选条件换成「常规弹窗多选」形式（用户定），自绘勾选框整段撤掉

* 用户原话：「如果是UI有问题. 那就换成当前插件的常规弹窗多选正方形形式.」
* 处置：**不再跟那个自绘控件纠缠**，改用本插件已验证的组件 —— 宿主 `EVAL_DD_OPEN` 的 **multi 模式**
  （每行一个正方形勾；宿主的条件编辑器 / 工具箱 / 数据检索都在用它）。
* 具体形态：
  ① **筛选条件**（原 10 个勾选框）⇒ 点面板顶部那颗**「筛选」按钮**弹出多选窗
     —— 那颗按钮原本就是个**空函数**（设计上就是给菜单用的），现在正好接上；
  ② **「本页全选」**（原 1 个勾选框）⇒ 换成一颗**模板按钮**（与批量按钮同款，真机验证过好使），
     点击 = 现算目标态（本页已全选就取消，否则全选），文案随状态在「本页全选 / 取消全选」之间变；
  ③ 面板高度按新内容重算（不再留那片勾选框的位置）。
* ★**口径要点**：宿主 multi 下拉点一行时**它自己已经翻过一次勾** ⇒ 我们的回调必须**按目标态赋值**
  （`on` 参数），**不能再用「切换」语义**（会双翻转）；原来的 `batch_toggle_filter` 已改名语义为
  `batch_set_filter(key, on)`。★拿不到下拉组件时**如实报一声**（不静默、也不假装打开了）。
* 连带清理：删掉上一轮加的 `/tm cb` 自检口（它引用的两个帧已随本次改造消失）、删掉标签命中区与抬层那两段
  已失效的判据，补 3 个语言键（`Unselect all` / `Select all tip` / `Filter menu unavailable`）。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 该段由 5 条改为 **7 条**（含反向钉：自绘勾选框不许回来）·
  `sync_game` 改 3。
### 11. 筛选勾选框仍点不动 —— 面板不吃鼠标 + 子件显式抬层 + 自检口

* 现象（用户）：「图中的多选框还不可点击选择.」（改完标签命中区之后仍然点不动 ⇒ 不是命中区的事）。
* ★**分歧点（推理依据）**：同一块面板上，用 `UIPanelButtonTemplate` 的批量按钮**好使**，
  而自绘勾选框（裸 `Button`）**不好使** —— 两者都是 `panel` 的子件 ⇒ 差别只剩「模板 vs 裸 Button」与**层级**。
  本项目有两条在案判据：**「层级同时决定点击命中」**（透明/无贴图的帧照样吃点击）、
  **「抬高父帧不带动子件」（子件要逐个 `SetFrameLevel`）** —— 本项目为此踩过两次「看得见、点不着」。
* 处置两条（都是确定性加固，互不依赖）：
  ① `panel:EnableMouse( true )` ⇒ **`false`** —— 那块面板只是背景板，**没有任何鼠标处理体**，
     开着鼠标只可能在子件之上把整片点击吃掉（点了要么落到子件、要么穿到底下同样不吃鼠标的 `InboxFrame`）；
  ② 勾选框本体与文字标签**各自显式抬层**（`SetFrameLevel( panel:GetFrameLevel() + 2 )`）。
* ★新增**自检口 `/tm cb`**（一条命令）：把「面板 / 全选 / 框1」的**层级 · 显隐 · 有没有 OnClick**
  以及**当前鼠标底下的帧**一次打出来 ⇒ 一次分清「点击被别的帧吃了」与「按钮根本没收到点击」。
  用法：把鼠标**悬停**在那片勾选框上 → 敲 `/tm cb` → 把那一行发回来。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 新增 3 条（含反向钉：不许把面板鼠标开回来）。
### 10. 收件人历史改**账号级**（用户要求：同账号所有角色都可直接复用）

* 需求（用户原话）：「收件人设置账号级别存储. 同个账号都可直接复用.」
* 改动：`tm_mailToList` 从**角色级**（`EH_MAIL_CHAR`）搬到**账号级**（`EH_MAIL_CFG`）——
  别名绑定与 `MAP` 两处一起改（`EHMailTM_MailToList` 现在指向 `EH_MAIL_CFG.tm_mailToList`）。
  ★桶结构保留按**服务器名**分桶（同账号在不同服务器有角色时名字不会混）。
* ★★**老存档一次性迁移**（`migrateMailToList`）：把 `EH_MAIL_CHAR.tm_mailToList` 里的历史搬进账号级 ——
  **只补不覆盖 · 跳过非字符串垃圾 · 同服去重 · 搬完排序 · 清掉旧位置**（避免数据分家与重复搬）；
  在**两个时机**各跑一次（文件执行期 + `VARIABLES_LOADED`）且**幂等** ⇒ 无论客户端哪一刻换表都搬得到。
  ★不迁移的话，你**之前加过的收件人**会因为换了存储根而「看不见」—— 所以这一步必须有。
* 同步：取证行与接线钉里的存档根名一起改（原来写死 `EH_MAIL_CHAR.tm_mailToList` ⇒ 不改会永远报 false）。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 新增 2 条（账号级 · 迁移幂等）· `sync_game` 改 2。
### 9. 收件人历史「添加成功、/reload 后没了」—— 存档绑定治本 + 取证

* 现象（用户）：「收件人. 添加完成的. 在/reload 之后没了」。
* ★**先给真机存档读数**（两份都是好的那一半）：`lihaiboas3 / Iosol` 的角色级存档里
  `tm_mailToList = { Emberveil = { [1] = "ioiol" } }` —— **存住了**；而 `LIHAIBOAS1 / Ionol` 是**空桶**
  `{ Emberveil = {} }`。**同一段代码、一个角色成功一个失败** ⇒ 指向**绑定时机**（不稳定），不是写入逻辑。
* ★**否证了一条假设**：下拉回调**不传帧对象** —— 客户端 `UIDropDownMenu.lua:489` 是
  `func(this.arg1, this.arg2)`（我们没设 arg1/arg2 ⇒ 两个 nil）⇒ `MailTo_ListAdd` 走的是
  `name = MailTo_Name`（字符串）⇒ 写入逻辑本身没问题。
* ★**治本**（`EHMailTM_Saved.lua` 重写两处）：
  ① **容器根一律「用的时候现读全局」**（`_G["EH_MAIL_CFG"]`），不再在文件执行期抓住引用 ——
     本项目老雷：文件执行期读存档可能拿到**空表**，客户端**随后**才把真表换上，抓住的引用就成了
     **孤儿表**（写进去永远不落盘）；
  ② **裸别名在 `VARIABLES_LOADED` 再确认一次**（幂等 + 把旧表已有数据并进新表）⇒
     无论客户端在哪一刻换表，别名最终都指向**真正的存档表**。
* ★**取证行**（`MailTo_ListAdd`，添加时打一行）：`[EH_Mail] 收件人表==存档表? … ｜ 服务器=… ｜ 桶内=…`
  —— 若显示 `false` 就正是本次治本修掉的那件事；若 `true` 且桶内已加、`/reload` 后仍消失，
  则是另一条路（再查）。
* 顺带修：`MailTo_ToList_Init` 里**桶缺失时自愈建桶**（原来会直接索引 nil 报错 ⇒ 下拉里一项都没有）。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 新增 4 条（含一条反向钉）· `sync_game` 改 2。
### 8. 批量操作限频（用户要求，默认生效）

* 需求（用户原话）：「批量操作要添加限频措施. 子插件邮箱存在的话默认开启.」
* ★**现状是「没有真正的限频」**：批量推进挂在常驻 `on_update` 上（每帧最多一步），唯一的刹车是
  「等 `GetInboxNumItems` 掉下来」⇒ **节奏只受服务器确认速度限制**，服务器回得快时一帧就能连发多件写动作。
  （`m.timer = 200` 那个 200 帧是**收件箱刷新**节流，与批量无关 —— 别把它当限频。）
* 本项目铁律 = 「服务器写动作 > ~1-2 次/s 必限频」（1.75.x 实测：一帧 24 次 `UseContainerItem` 被反滥用踢线）。
* 处置：加**一个共用闸** `m.batch_rate_ok()`（间隔 `m.batch_rate = 0.5s`，≈2 次/s），**默认生效、不需要任何配置**；
  **四处写动作全部过闸**：`batch_step`（批量取件/退信/删除）· 「接收所有邮件」逐封路径 ·
  「选择取件」路径 · `sendmail_send`（批量寄送）。
* ★三条设计口径：① **没到点就原样排队、下一帧再来**（绝不丢队列、绝不吞掉用户操作）；
  ② **闸只挡写动作**（越界/跳过/GM 邮件那些分支不占闸，不影响扫描推进）；
  ③ **每一批开始时复位限频账**（`m.batch_last_at = 0`）⇒ 第一批第一件永远立刻执行，
  不会因为上一轮的尾巴而「点了没反应」。
* 判据：`luacheck` **SYNTAX OK: 65** · wiring 新增 3 条 · 自证「`m.batch_rate_ok()` 调用恰 4 处」。
### 7. 批量寄送「放进寄件栏」失败 —— 查机制 + 加取证（不改上游流程）

* 现象（用户）：批量选择物品寄送时弹「没能把「银线腰带」放进寄件栏：东西还在光标上…」，
  **之后**再选同一件物品，连子插件 `EH_Bag` 也报「没能把这件物品拿起来（邮件附件栏）」，
  「无法选择物品到邮件栏内」。
* ★**机制（读码定案）**：上游**不用真实附件栏**，而是纯 Lua 记账
  （`MailAttachmentN.item = {bag,slot}`，再用 `hook.GetContainerItemInfo` 把那些格子伪造成 `locked`）；
  只有**真寄出**那一步才把物品经光标放进客户端寄件栏（`ClearCursor` → `ClickSendMailItemButton` →
  `PickupContainerItem` → `ClickSendMailItemButton` → `GetSendMailItem()` 读回判定）。
* ★★**EH_Bag 那两行是「结果」不是独立故障**：第一次失败后物品**留在光标上**，而光标非空时任何
  `PickupContainerItem` 都拿不起东西 ⇒ 之后 EH_Mail 与 EH_Bag 一起失败（同一根因）。
* ★**本轮不擅自改上游寄件流程**（项目铁律：留光标物品时绝不清光标，清掉就是丢件 —— EH_Bag 整理引擎
  实测丢过两件），改为**在失败点补取证**：打印「格子 bag/slot ｜ 该格现在=<链接> ｜ 光标上=有/空 ｜
  寄件栏=有/空」，用来区分三种情形 —— ① 那一格已不是原来那件东西（快照失效）② 光标上已经有东西
  （连锁失败）③ 寄件栏里还有残留。
* 文案同步改清楚**怎么放下**：「…东西还在光标上 —— 请在背包里点一个空格把它放下（这一封没有寄出）」。
* ★**待用户复现一次**（把诊断行截图）：三种情形对应的修法完全不同，拿到数据再动。
### 6. 右侧筛选条件（本页全选 / 到付 / 带附件 / …）都无法勾选

* 现象（用户）：「图中部分都无法勾选」—— 上方的批量按钮（筛选 / 批量取件 / 批量退信 / 批量删除）是好的，
  只有下面那一片勾选框点不动。
* 根因 = **标签的命中区被量窄了**：`checkbox()` 里按文字实宽收窄命中区（`tw = fs:GetWidth()`），
  而**本客户端对中文的 `GetWidth()` 会报小值**（本项目已定案：FontString 建出来挂的是拉丁字体、
  中文靠回退字形渲染 ⇒ 量出来的宽度与实际字宽不是一回事）⇒ 标签命中区可能只剩几个像素
  ⇒ **点文字全都点不到**，只有点 16x16 的方框才有效 —— 用户看到的正是「都无法勾选」。
* 处置：改用与两列布局**同源**的确定宽度 `CELL_W - CHECK_BOX - 4`（= 72px）——
  左列标签右缘正好落在右列方框左缘上，既不重叠也不留下打不到的缝。
* ★**待真机复验**：若修完仍点不动，请把鼠标**悬停**在勾选框上敲宿主现成命令 `/eh go 层级`
  （它打印「光标下的帧 + 父链 + 层级」）—— 那一步能立刻区分「点击被别的帧吃掉」与「根本没收到点击」。
### 5. 日志列表只显示两个图标，信息全都没有（两轮定案）

* 现象（一轮）：「现在就显示两个图标其他信息都没有」；**二轮**真机截图：已发送页有 3 条、
  底部计数器「显示1-3，总共3」**正常**，而**每行仍然一个字都没有**。
* **一轮**根因 = 字体路径的**目录名大小写**：那 4 个 FontString 设的是 `"FONTS\\ARIALN.TTF"`（**全大写**），
  而全项目都写 `Fonts\\` —— 本客户端字体路径**大小写敏感** ⇒ `SetFont` 静默失败
  （图标是 Texture，不受影响 ⇒ 于是只剩图标）。处置 = 改掉大小写 + 改走项目字体链 + 读回自证。
* ★★★**二轮真根因（= 一轮为什么没修好）= 读回自证把字体链切断了**：本客户端 `FontString` **没有 `GetFont`**，
  而当时的 `fontSet` 写着「读不回就当这一步成功」⇒ 它在**链首 `FZLBJW` 那一步就 `return true`**，
  链子一步没往下走 ⇒ **链尾（真正可用的那条）从未被设过**。
* ★**同一文件内的对照证据**（这条证据最硬，也是定案手法）：`log.load` 结尾给底部计数设的
  `"Fonts\\FRIZQT__.TTF"` **显示正常**（中文也正常）⇒ 说明 `log.load` 跑到了、`SetFont(path,size)`
  两参数可用、路径写法也对 ⇒ 剩下的变量只有「链走到哪一条」。
* 处置（二轮）：**读不回 ⇒ 把整条链设完**（最后一条生效 = 链尾）；读得回 ⇒ 逐条比对、都不对才退
  `SetFontObject(GameFontNormal)`；**读不回时绝不提前 return**。
  ★链尾 `Fonts\ARIALN.TTF` 是**真机验证可用**的那条：宿主主插件 `EvalHelp.lua:173` 的链判据是 `pcall`
  的第二返回值（恒假）⇒ 它**实际恒落到 ARIALN**，而主插件全界面正常。
* ★**两个页签（已收到 / 已发送）共用同一批行控件与同一份字体设置**（`log.load` 只跑一次）
  ⇒ 修一处两页同时生效。
### 4. 收件人下拉弹出来了、但位置不对（没在收件人名称下方）

* 现象（用户）：下箭头点了能弹，但菜单跑到右边；要求「放置在收件人名称下方」。
* 根因（两条，都有源码证据）：
  ① 本客户端 `UIDropDownMenu.lua` **只有「不传 anchorName」时**才读 `dropDownFrame` 的
     `point` / `relativeTo` / `relativePoint`（555~573 行），而原写法正是走那一支、且 `relativeTo` 塞的是
     **帧对象**（客户端自己那一支用的是**帧名字符串**，569 行）；
  ② 我们锚的是 `SendMailNameEditBox` 的 `BOTTOMRIGHT`，而**它的本体只有 122x20**
     （客户端 `MailFrame.xml:662-665`）—— 可见的那个输入框装饰比它宽得多 ⇒ 菜单从**可见框中间**开始。
* 处置：改走 **anchorName 那一支**（`ToggleDropDownMenu(nil, nil, menu, "SendMailNameEditBox", 0, 0)`）
  ⇒ `relativeTo` 直接是帧名，位置取默认 **TOPLEFT 贴 BOTTOMLEFT** = **输入框正下方、左对齐**。
  同时把原来那 5 个位置字段删掉（传 anchorName 时它们一个都不生效，留着只会误导），
  并把建菜单抽成幂等的 `MailTo_MenuEnsure()`（`OnShow` 与 `OnClick` 都过它；parent 不再用 `this`）。
* 判据：`luacheck` **SYNTAX OK: 65** · `ehmail_wiring_check` 新增 8 条（含两条反向钉）·
  自证残留扫描：`restore_position`/`on_drag_stop`/`dragbar_load`/`EHMailTMDragBar`/`MAIL_DRAGBAR_H`/
  `StopMovingOrSizing` **全 0 处**（`StartMoving` 仅剩上游一句注释）。
* ★**真机复验点（未做）**：① 收件箱/写信页**任意地方拖不动**；② 日志页有数据时逐条显示、
  无数据时显示 `显示0-0，总共0`；③ 批量寄送多封若失败会**点名物品**并停下（不再只弹「错误」）。

#
#
### 17. 多邮件发送异常：附件格被客户端「抢管」+ 记账不随物品同步

* 现象（用户）：「将物品拿出来了、然后再放入其他物，但**内部的数据没有更新**，发送时**发送的还是第一次的物品**；
  再放第二个就报错（诊断：`格子 1/7 ｜ 该格现在=[银线腰带] ｜ 光标上=空 ｜ 寄件栏=空 ｜ **连试 4 次**`）
  ⇒ 批量发送失败」。
* ★根因（静态取证）：上游写好的 `attachment_button_on_click`（点附件格 = 拿出 / 与光标物品交换）
  **全文件零引用**（只有定义那一处）⇒ 附件格的点击与拖放**仍是客户端自己的行为**
  ⇒ 玩家一拖放，物品**真的**进了客户端附件栏，而我们的 Lua 记账（只记 `{bag,slot}`）**一个字都不动**
  ⇒ 界面 / 记账 / 背包三份状态各说各话；真进了附件栏的物品在客户端里是「已附加」状态
  ⇒ 之后 `PickupContainerItem` **拿不起来**（「连试 4 次」的来源）。
* 处置（五处）：① 附件格整条接管（挂 OnClick + 禁 `OnReceiveDrag` + 撤拖拽注册）；
  ② 新增 `sendmail_forget`（清记账、不动物品），左键拿起已挂载件时同步清；
  ③ `sendmail_send` 挂件前校验那一格还在不在，不在 ⇒ **如实跳过这一件并继续**（不再死重试）；
  ④ 整批收尾报「本次共跳过 N 件」；⑤ 源码注释如实记下这条根因。
* ★**代价如实**：拿起后又放回原处 = 需要重新挂一次（宁可少挂，也绝不能拿旧记账发错东西）。
* ★★★**「拿不起来」= 客户端锁件，不是我们的 bug —— 决定性证据**：同一格、同一时刻，
  **子插件 `EH_Bag` 的「右键直投 → 邮件附件栏」也报同一句失败**（`EH_Bag` 打「没能把这件物品拿起来」）
  ⇒ 两个插件都拿不起来、且光标是空的 ⇒ 那件物品是被**客户端自己**锁住的（此前被拖进过客户端附件栏），
  **只有重启客户端才解**；重试多少次都不会好 ⇒ 失败路径必须**跳过并继续**（见第 2 项 ③），
  否则整批被一件死锁件拖死。★这也是 `EH_Bag` 那两行 `DROP_FAIL` 的真正来源 —— 它是**结果**、不是独立故障。
* ⚠️**遗留**：玩家以前用拖放塞进客户端附件栏的真物品可能还在（客户端侧；插件读得到但**不敢替他取出**
  —— 取出要走客户端行为、有丢件风险）⇒ **开批时检测到就当场停下、这一批一件都不发**并提示先取出
  （见第 18 项）；若发现「多寄了东西」，先重启客户端清掉附件栏状态。

### 18. 真机第四轮：`发送出去了一半` —— 附件栏残留必须**当批停下**（不是提示一句）

* 现象（用户）：批量寄送时 `本次共跳过 4 件（拿不起来 3 ｜ 已不在原处 1）`，
  每件的诊断都是 `该格现在= [清凉的泉水] ｜ 光标上=空 ｜ 寄件栏=空 ｜ 连试 4 次`
  —— **物品从未离开背包**，而 `EH_Bag` 同时打了 7 行「没能把这件物品拿起来（邮件附件栏）」；
  用户问「是否是发送频率？**发送出去了一半**」。
* ★★★**先答那个问题：不是频限。** 0.5s 闸门（`m.batch_rate_ok`）只会把写动作**推迟**，
  **绝不会**让 `PickupContainerItem` 变成空操作；`连试 4 次` 每次都是「取件没发生」，
  与节奏无关。真正要看的是**「拿起之后那一瞬间的光标」**。
* ★★★**真凶 = 开批前那条「寄件栏里已经有一件东西」的残留**：那一版只**提示**一句就照旧往下跑，
  而上游清空附件栏的三步（`ClearCursor` → `ClickSendMailItemButton` → `ClearCursor`）会把**玩家的残留物
  从附件栏拿到光标上又清掉** ⇒ 此后客户端进入「**光标忙**」状态：`CursorHasItem()` 报**空**
  （我们的光标守卫完全看不见它），但**之后每一次 `PickupContainerItem` 都被客户端拒绝**
  ⇒ 整批「拿不起来」；只有先前批次已经挂上的那几件寄了出去 = 用户看到的「一半」。
  子插件 `EH_Bag` 的「右键直投 → 邮件附件栏」同时失败也是它（**另一个独立原因**见下一条）。
* **处置一（当批停下）**：`send_mail_button_onclick` 里那条检查改成**硬停** ——
  `GetSendMailItem()` 非空 ⇒ 打两行（`寄件栏里已经有一件东西（不是本插件放的）—— 已停下，没有寄出` /
  `请先点一下寄件栏把那件东西取出（或重启客户端），然后再发一次`）+ `m.sendmail_sending = false` + `return`。
  ★依据 = 本项目铁律「**拿不到证据就一个字节都不碰**」：附件栏里的东西不是我们放的 ⇒ 不替他清、也不发这一批。
* **处置二（决定性取证）**：失败诊断加一格 **`拿起后=有/空`** —— 在 `PickupContainerItem` 与放置点击
  **之间**读一次光标。`拿起后=空` ⇒ **客户端拒绝了这次取件**（物品从未离开背包，与放置序列无关）；
  `拿起后=有` ⇒ 取起来了、是**放置**那一步失败。**下一轮真机一眼可判，不许再猜。**
* **顺带查明的第二个故障源**：`hook.PickupContainerItem` 在 `arg1 == "RightButton"` 时**不真取件**
  （走 `sendmail_set_attachment` / `sendmail_remove_attachment` —— 这是上游「右键点背包物品 = 挂到附件栏」的
  主用法，**不能删**）；而 `EH_Bag` 的「右键直投 → 邮件附件栏」也是右键 ⇒ **被同一个 hook 吃掉** ⇒
  `EH_Bag` 报「没能把这件物品拿起来」。两者**无法靠 `arg1` 区分** ⇒
  正解 = EH_Mail 把**未经 hook 的原函数**作为桥交出去（`EVAL_MAIL_PICKUP_RAW`），`EH_Bag` 走它；
  在桥接上之前，`EH_Bag` 的邮件直投在 EH_Mail 启用时**不可用**（如实记在案，别当新 bug 查）。
* 判据：`node luacheck.js` **SYNTAX OK: 68** · wiring 该段 4 条 → **7 条**（附件栏残留硬停两句都在 ·
  「拿起后」量在取件与放置之间 · 放回队首恰 2 处 · 失败分流两支）· `node sync_game.js` + `verify_sync`
  **不一致 0**。



## 0.3.2（宿主 1.75.112 同轮 · 2026-10-10）

**修掉真机第三个红框：同一个 `SetTexCoord` 报错换了个行号又回来了**（0.3.1 修完仍弹 `EHMailTM.lua:1880`，
栈与 0.3.1 完全相同 = `SendMailFrame_Update` ← `MailFrame.lua:558`）。

* ★★★**根因不是「对象是 nil」，是「对象的类型不对」—— 0.3.1 的判读错了**：
  `attempt to call method 'X' (a nil value)` 的含义是**对象在、方法不在**（对象本身是 nil 时才会报
  `attempt to index a nil value`）⇒ `GetRegions()` 在那一格交出来的是个**有 `SetHeight` 却没有 `SetTexCoord` 的 region**
  （本客户端给的是 FontString 之类，不是 Texture）。行号从 1871 挪到 1880 恰好证明客户端跑的**确实是新代码**。
* 修法 = **六处守卫全部升级成「对象在 ∧ 方法在」**（`and type(o.M) == "function"`）：
  `SetDrawLayer` 三处（金额框）· `SetTexCoord` 一处（滚动框顶部那条线，真机报错点）· `Hide` 两处（寄件包背景与计数）。
  拿不到就跳过那一条皮肤线 —— 界面照旧可用（与 0.3.1 同一取向：宁可少画一根线，绝不中断 `SendMailFrame_Update`）。
* 判据：`luacheck` **65 files** · `ehmail_wiring_check` 三条钉升级 + **新增一条反向钉**（不许退回「只判对象存在」）·
  `sync_game` EH_Mail 改 3。
* ★**真机复验点（未做）**：`/reload` → 开邮箱 + 收一封信，看聊天框还弹不弹 `SetTexCoord` / `SetDrawLayer` 红字。

## 0.3.1（宿主 1.75.112 同轮 · 2026-10-10）

**修掉真机第二个红框：`GetRegions()` 索引对 nil 调用**（用户真机截图：
`Interface/AddOns/EH_Mail/EHMailTM.lua:1871: attempt to call method 'SetTexCoord' (a nil value)`，
栈 = `SendMailFrame_Update` ← `MailFrame.lua:558 SendMailFrame_Reset` ← **一收信/开邮箱就弹**）。

* ★★★**根因 = `GetRegions()` 的数量会随控件状态变化**：探针在 PLAYER_LOGIN 那一刻量到 `SendMailScrollFrame` 有 **3** 个 region，
  而真机在 `SendMailFrame_Update` 里取 `[3]` 拿到的是 **nil**。
  ⇒ **探针的 REGIONS 读数只能当参考、不能当保证**（这条已写进 `EH_Mail.lua` 的 `G_REGIONS` 注释与 `CLAUDE.md`）。
* 修法 = 把剩下三处也改成「**够了才用**」（R11 那三处 0.3.0 已修）：
  · `SendMailScrollFrame [3]`（真机报错点）⇒ 先收进局部表再判存在，拿不到就跳过（皮肤线画不出来，界面照旧可用）；
  · `SendMailPackageButton [1] / [3]` ⇒ ★原写法**调了两次 `GetRegions()`**（两次之间数量可能不同 = 同类隐患）
    ⇒ 改成**一次调用收进局部表、各自守卫**。
* 现在全文件 **0 处裸索引** `GetRegions() })[ N ]`（判据 = wiring check 的「全文件零裸索引」反向钉 + 两条写法钉）。
* 判据：`luacheck` **65 files** · `ehmail_wiring_check` **全绿**（新增/升级 3 条）· `ehmail_harness` 49 条未受影响 ·
  `sync_game` + `verify_sync` 不一致 0。

## 0.3.0（宿主 1.75.112 同轮 · 2026-10-10）

**清掉所有旧插件名痕迹 + 修掉真机存档红框**（用户 2026-10-10：「要清理掉所有 TurtleMail 的痕迹」）。

★ **真机报障（先修的）**：进游戏弹红框
`[string "…Saved/Account/LIHAIBOAS2/Sa…"]:1: '=' expected near 'TurtleMail_AutoCompleteNames'`
* **根因 = toc 的 `## SavedVariables` 写了多个名字**：本客户端**一行只认一个变量名** ——
  0.2.0 那句 `## SavedVariables: EH_MAIL_CFG TurtleMail_AutoCompleteNames TurtleMail_PanelOffset TurtleMail_PanelOffsetPF`
  被客户端当成**一个**超长名字写进存档文件（实测存档内容就是那一整行 + ` = nil`）⇒ 读回来语法错、**每次登录弹一次**。
  ★ 判据：本项目**所有**其它 toc（宿主 `EvalHelp.toc` + 另外 4 个子插件）的 `## SavedVariables` 全是**一个名字** ——
  这是本客户端的硬约束，不是可选项。
* **修法 = 两个存档根 + `m.api` 代理**（新增 `EHMailTM_Saved.lua`）：
  只声明 `EH_MAIL_CFG`（账号级）与 `EH_MAIL_CHAR`（角色级，`## SavedVariablesPerCharacter`）；
  增强版那 **9 个**原本各自独立的存档键作为它们的**字段**存在。
  而增强版访问存档**几乎全走 `m.api.X`**（`m.api = getfenv()`）⇒ 把 `m.api` 换成一个**代理表**，
  由 `__index` / `__newindex` 把 9 个名字转发到两个存档根 ⇒ **代码零改动收容器**。
  代理**只拦这 9 个名字**，其余全局照旧走 `_G`（「按名顶掉客户端全局」那类写法行为不变）；
  拿不到代理就 `or getfenv()` fail-open。
  ★ 裸访问的 `EHMailTM_MailToList`（`MailTo.lua`，表类）用**别名绑定**（引用共享）；
  简单值类**没有**裸访问（`tmp/tm_saved_scan.js` 逐个核过）⇒ 不需要别名。
* **坏存档已处理**：`Saved/Account/<账号>/SavedVariables/EH_Mail.lua` 那份畸形文件已备份到
  `tmp/bad_savedvars_<账号>_EH_Mail.txt` 并删除（客户端会重建）。
* ★★**清痕迹（代码与 XML 443 处 + 通用名 12 处 + 5 个文件）**：`TurtleMail` ⇒ **`EHMailTM`**
  （全局表 / 具名帧 / 自建模板 / 控件名 / 存档键 / 贴图路径），命令别名 `/turtlemail` ⇒ `/ehmail`，
  `S_MailTo_List` ⇒ `EHMailTM_MailToList`；文件改名 `TurtleMail.lua/.xml` ⇒ `EHMailTM.lua/.xml`，
  素材 3 个 ⇒ `EHMailTM-*.blp/.tga`（**逐字节**保留）。三语 `SUB_MAIL_TIP` 与探针里**玩家可见**的 `OVER` 文案一并去掉旧名。
  ★ **有意保留**的：`doc/TurtleMail-API支持度调研.md`（真实文件名）· `tmp/TurtleMail/`（上游素材目录）·
  文档里的 `TurtleMail.lua:NNNN` 源码锚点（**证据链**，删了没法追溯）。
* ★**改完之后必验的一件事**：toc 的 `## SavedVariables` 一旦再多写一个名字，红框就会回来 ——
  判据已进 `tmp/ehmail_wiring_check.js`（两条钉 + 一条说明钉）。

## 0.2.0（宿主 1.75.112 同轮 · 2026-10-10）

**上游插件 移植落地**（用户 2026-10-10：「pfui 相关的抛弃.只移植原始Ui的功能」）。

* **移植形态 = 最小改动、最低风险**（全部落在 `addons/EH_Mail/`）：
  * **保留 上游插件 的原始文件名**（`TurtleMail.lua` / `TurtleMail.xml` / `Calendar.lua` / `MailTo.lua` /
    `localization.lua` / `localization.cn.lua`）⇒ XML 里那 6 条 `<Script file="xxx.lua">` **一个字都不用改**
    （同目录 ⇒ 相对路径天然成立）。
  * `EH_Mail.toc` 追加一行 `TurtleMail.xml`，并**排在 `EH_Mail.lua` 之后** ——
    ★刻意让体检探针先载入：万一 XML 载入失败，**诊断腿（`/email`）仍然活着**，否则连「为什么坏」都看不到。
  * 存档：toc 合并声明两组 —— 探针的 `EH_MAIL_CFG` + 上游插件 的 3 个账号级键与 6 个角色级键。
* **适配五条**（每条都有结构钉 + 反向钉，见 `tmp/ehmail_wiring_check.js` 末段）：
  ① ★★★**插件名**（不改编 = 移植**完全无效**）：`arg1 ~= "上游插件"` ⇒ `"EH_Mail"`；
     `GetAddOnMetadata( "上游插件", "Version" )` ⇒ `"EH_Mail"`。
     **理由**：客户端发 `ADDON_LOADED` 时 `arg1` 是**本插件真名**，而移植后本插件叫 `EH_Mail`
     ⇒ 不改这一句，`上游插件.ADDON_LOADED()` **第一行就 return**，初始化一个字节都不执行
     （症状最阴：插件看着载入了、邮箱界面却毫无变化）。
  ② ★★★**R11**：原 `TurtleMail.lua` 的 `:2097/2101/2105` 三行
     `do ({ f:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end` ⇒ 真机实测该 EditBox 只有 **4** 个 region
     ⇒ nil 索引，且**无 `pcall`**、跑在 `ADDON_LOADED → sendmail_load()` 里（会**中断其后 3 个 load**）
     ⇒ 改成 `do local rs = { … } if rs[ 9 ] then rs[ 9 ]:SetDrawLayer( "BORDER" ) end end`
     （**够才设**，语义一字不变）。
  ③ **pfUI 整条剔除**（用户指令）：删 `pfui-skin.lua`（整份 12.8 KB 皮肤）+ XML 那条 `<Script>` +
     3 处 `m.pfui_skin()` 调用（函数随文件删除，留着就是 `attempt to call nil`）+
     显式落 `m.pfui_skin_enabled = false`（全文件十几处 `… and <pfUI 值> or <原版值>` 因此**恒走原版 UI 分支**）+
     顺手清掉三处**纯 pfUI 死代码**（Calendar 的 `pfui_skin()` 局部函数与其调用 · MailTo 的
     `if pfUI and pfUI.env` 取偏移 · MAIL_SHOW 里那段 pfUI-only 的 `StripTextures`）。
     ★**刻意保留**的：那十几处三元判断 + 4 处带守卫/短路的 `m.api.pfUI` 引用 ——
     它们另一半就是「**原版保底值**」，删掉要重写十几处、白担风险（`m.api.pfUI and …` 与
     `m.pfui_skin_enabled and …` 在 pfUI 不存在时都**短路**，实测全部不可达）。
  ④ **自带素材路径 5 处**：`Interface\<Addons>\上游插件\` ⇒ `Interface\AddOns\EH_Mail\`
     （Lua 2 处 + XML 3 处），3 个素材（`上游插件-AH.blp` / `上游插件-RetArrow.blp` / `上游插件-DownArrow.tga`）
     **逐字节**拷入。★不改 = 三道贴图全部找不到（静默画空）。
  ⑤ ★★★**存档全局的「无条件覆盖」三处**（症状不是崩溃，而是**数据每次登录丢光**，用户一定会碰到）：
     客户端是「**先把存档恢复成全局、再执行插件文件**」⇒ 下面三处无条件赋值会把刚恢复的存档当场覆盖：
     · `TurtleMail.lua` 的 `m.api.上游插件_Log = { Sent={}, Received={}, Settings={…} }`
       —— ★它自己的注释写着「仅对没有存档的新角色生效」，**代码与注释不符** ⇒ 日志历史每次登录清空；
     · 同处 `m.api.上游插件_AutoCompleteNames = {}` ⇒ 账号级自动补全名字历史清空
       （`PLAYER_LOGIN` 里那段「30 天过期清理」因此形同虚设）；
     · `MailTo.lua:19` 的 `S_MailTo_List = {}` ⇒ 角色级收件人历史清空。
     ⇒ 一律改成「**缺什么补什么**」（`if X == nil then … else 逐段补 end` / `X = X or {}`）——
     ★这个写法在**两种** SavedVariables 时机下都正确（先恢复 ⇒ 保住历史；后恢复 ⇒ 与原来等价），
     严格优于原版、无下行风险。
* **移植前先把未知项问完**（`tmp/tm_port_audit.js` / `audit2.js` / `audit3.js`，纯读）：
  17 个 `inherits` 全量定性 ⇒ **A 类自建 6 个**（含 `MailAttachment` ×21 —— 确认是插件自建而非客户端依赖）·
  **B 类同血统标准 11 个**（其中 5 模板 + 5 字体已被真机验过；剩下的 `UIPanelButtonHighlightTexture`
  与**已被真机验过的** `UIPanelButtonTemplate` 在 `UIPanelTemplates.xml` 里**同文件相隔 3 行** ⇒ 随它一起原子载入）·
  **C 类 = 0 个** ⇒ **移植前未知项 = 0**。
  另：XML 自建 79 个具名帧里只有 `MailFrameTab3` 非 上游插件 前缀，而客户端本来就没有它（插件自带 XML 定义）⇒ **不撞名**。
* 判据：`node luacheck.js` **SYNTAX OK: 64**（`pfui-skin.lua` 删除后由 65 → 64）·
  `tmp/ehmail_harness.js` **49 条全过**（探针本体未动）·
  `tmp/ehmail_wiring_check.js` **64 条全过**（新增 **18 条移植版结构钉**：toc 顺序 · 存档键声明 ·
  插件名适配 2 条 + 2 条反向钉 · R11 修复 + 反向钉 · pfUI 剔除 5 条 · 素材路径 2 条 + 3 个素材在 ·
  **存档全局不许被无条件覆盖 4 条**）。
* ★★★**如实说明**：移植版是**第三方代码**（3000 行 + 强依赖客户端邮件窗）⇒ **没有行为闸门**，
  只有上列结构钉；「**行为对不对**」= **真机载入一次看红字**（下一步，见 `CLAUDE.md` 的待验证项）。

## 0.1.1（宿主 1.75.112 同轮 · 2026-10-10）

**真机首轮读数落地 + 把「区域下标」变成探针自己的判据**（用户 2026-10-09 真机跑出读数后同轮改）。

* ★★ **真机结果（账号 LIHAIBOAS2，读的是 0.1.0 那版）= 共 115 项 ｜ 缺 1 项**：唯一缺失 = `FRAME:SendMailStationeryButton`。
  * ✅ **R1 排除**：10 个 FrameXML 挂钩全局**全部 `function`**（离线那份「它们都在 `MailFrame.lua`」的推断成立）。
  * ✅ **R4 排除**：8 个 `$parent` 派生名全在 —— 含离线时「基础 MPQ 查无此名」的 `SendMailMoneyGold/Silver/CopperRight`。
  * ✅ **R3 排除**：`FriendsFrameTabTemplate`（`CreateFrame` 真建成）· `PanelTemplates_SetNumTabs` · `MailFrameTab1/Tab2` 都在。
  * ❌ **新发现 = R11（本次唯一真问题）**：`SendMailMoneyGold/Silver/Copper` 的 `GetRegions()` 实测**各 N=4**，
    而 `TurtleMail.lua:2097/2101/2105` 取 **`[9]`** ⇒ nil 索引；那三行**无 `pcall`**、跑在
    `ADDON_LOADED → sendmail_load()` 里 ⇒ **会中断其后 3 个 load**（`log.load` / `batch_load` / `pfui_skin`）。
    ⇒ **移植前必须先改这三行**（包 `pcall`，或先判 `rs[9]` 再写）。
  * `SendMailPackageButton`（源码取 `[1]`/`[3]`，实测 N=3）与 `SendMailScrollFrame`（取 `[3]`，实测 N=3）**都够**。
* **`SendMailStationeryButton` 移出名单**：它在客户端**确实不存在**，但**上游插件 源码零引用**
  （只有 `StationeryBackgroundLeft/Right` 两个背景纹理，实测都在）⇒ 留着只会每轮报一条无关「缺失」、把真缺口淹掉。
  事实记进本节与 `doc/TurtleMail-API支持度调研.md`，不占探针名额。
* **`REGIONS` 组升级：从「只报数字」改成「直接给结论」** —— 条目形态改为 `{ 名字, 源码要取的最大下标 }`
  （**6** 条，新增 `SendMailScrollFrame`），输出 `N=x 要取[n] 可及` / `★越界` / `判不出`。
  ★ 0.1.0 只报 `N=4`、不下结论 ⇒ 首轮是 AI 人工比对才看出 `[9] > 4`；现在越界会**点名上屏（聊天第 2 行）**
  并写进落盘环（`区域下标越界：…`），数值另存 `EH_MAIL_CFG.lastOver`。
  ★ 三态齐全：**判不出（该帧没有 `GetRegions`）⇒ 不报越界、不下结论**（fail-open 的反向：拿不到证据就不下结论）。
* **`FRAME` 47 → 46 · 合计 115 → 114 项**；三语 `SUB_MAIL_TIP` 与 README 同步（含风险号 R11）。
* 判据：`tmp/ehmail_harness.js` **49 条全过**（新增 ⑪⑫⑬ 组：判不出不报 / 三处越界被数出并上屏进环 / 给够不误报；
  ★顺带修掉一处**夹具欠账** —— ④ 组把 `TEMPLATES` 白名单砍到 1 个且**没复原**，此后每轮都带回 4 条模板缺失）
  + `tmp/ehmail_wiring_check.js` **46 条全过**（新增 3 条结构钉：`G_REGIONS` 不许退回裸名字形态 ·
  必须覆盖源码真正取过下标的那 5 个帧 · 越界必须能上屏 + 进环）+ `node luacheck.js`（SYNTAX OK: 59）。
* 同步：`node sync_game.js`（EH_Mail 改 5 文件）+ `node tmp/verify_sync.js`（**同 128 / 不一致 0**）。

## 0.1.0（宿主 1.75.112 同轮 · 2026-10-10）

**新建子插件**（用户定：「作为 EH_Mail 子插件」测试）。

* 目的：上游插件（TurtleWoW 血统的邮箱增强插件）的 **C API 层已被离线证明全支持**，
  唯一判不了的是 **FrameXML / 具名帧那一层** ⇒ 本子插件用真机给出这一层的读数。
* 实现：`EH_Mail.lua` —— `/email`（别名 `/eh邮件`）跑一次**只读**体检：
  * 8 个类别 / **115 项**客户端名字：`FUNC` 22 · `FRAME` 47 · `MISC` 7 · `CONST` 21 · `FONT` 5 ·
    `PARENT` 8 · `TEMPLATE` 5（`pcall(CreateFrame …)` 探模板）· `REGIONS` 5（报 `#GetRegions()` 数字）
  * 结果写进**自己的**有界落盘环 `EH_MAIL_CFG.probe`（上限 260 行，最新在后，环内无 nil）
  * 聊天只回 **3 行**（结论 / 缺失点名 / 「N 秒后自动 /reload」+ 临时帧数）
  * **延后 6 秒自动 `/reload`** 落盘（`RunScript` + 唯一节拍帧 `EH_MailTick`；到点执行后真摘）
  * 子命令：`明细` / `状态` / `清`
* 铁律：全只读（唯一例外 = 模板探针建临时帧，当场 `Hide` 不留引用）· 一个节拍帧 · 记忆体分离
  （只碰 `EH_MAIL_CFG`）· 载入期唯一动作 = 注册斜杠命令（帧与节拍首用才建）。
* 宿主接线（宿主契约① 5 处）：`addons/EH_Mail/` 全目录 · `Toolbox.lua` 的 `SUBADDONS` 行 +
  `EVAL_SUBADDONS_BUILD` 的「邮箱」分组 · 三语 `SUB_GROUP_MAIL` / `SUB_MAIL` / `SUB_MAIL_TIP` ·
  `probe_localorder.js` 默认清单 · `tmp/ehmail_harness.js` + `tmp/ehmail_wiring_check.js`。
* 附带产物（离线调研，与子插件同轮）：`doc/TurtleMail-API支持度调研.md` +
  `tmp/tm_api_dump.js` / `tm_usage2.js` / `tm_surface.js` / `tm_cross.js` / `tm_c2.js` / `tm_c3.js` /
  `tm_tally.js` / `tm_probe_names.js` / `tm_dmp_probe.js` / `tm_dmp2.js` / `tm_dmp_strings.js` /
  `tm_dmp_ctx.js` / `tm_dmp_files.js` + `tm_api_index.json` / `tm_cross.csv` / `tm_probe_names.txt`。
* **待做**：① 真机跑一次 `/email` 并读存档（`node tmp/read_ehmailprobe.js`）；
  ② 按 R1~R4 的缺口决定 上游插件 功能本体做多少。
