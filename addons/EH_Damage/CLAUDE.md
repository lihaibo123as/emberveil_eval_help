# EH_Damage 子插件记忆体（铁律 / 判据 / 锚点）

> ★本文件 = **EH_Damage 自己的记忆体**（与宿主 `CLAUDE.md` 分目录存储，用户定）。
> · 面向使用者 = 同目录 `README.md`；逐版本改动 = 同目录 `CHANGELOG.md`。
> · 宿主 `CLAUDE.md` 的通用铁律照旧适用（`node luacheck.js` 闸门 · 不许子代理 · 答复中文 · 改完同步 · 不自动提交…），本文件不重复。

## 本目录构成与同步

| 文件 | 作用 |
| :-- | :-- |
| `EH_Damage.lua` | 主实现（配置 / 动画槽池 / 事件解析 / 编辑模式模拟战斗 / 配置面板 / 命令） |
| `EH_Damage.toc` | 载入清单 + `## Version` + `## SavedVariables: EH_DAMAGE_CFG` |
| `README.md` / `CLAUDE.md` / `CHANGELOG.md` | 使用者说明 / 本文件 / 改动记录（`0.1.x` ↔ 宿主 `1.75.y`） |

★本子插件**没有 `media\`**（不需要素材）。★同步 = `node sync_game.js`（整目录拷到插件同级）+ `node tmp/verify_sync.js` 逐字节核对。

## 判据正文

- ★★★**事件源只能是 SCT 模式（CHAT_MSG_ 文本解析）**；**姓名板附着做不到**（见下一条反向钉）：本客户端无 Nampower 结构化战斗事件、无 GUID API、
  姓名板非 Lua widget（三轮调研定案，见宿主 CLAUDE.md 与 `tmp/DamageEx for Nampower 2026-04-16` 分析）。
  ⇒ ① 事件名与文本格式**不许猜**（铁律 5）：模式表是 zhCN 尽力而为，未识别的战斗文本走**捕获环**
  （`/edmg 捕获` 开 → 原文落 `EH_DAMAGE_CFG.ring` 有界 40 → `/edmg 事件` 查看）供真机逐条校准；
  ② **绝不引入** `GetUnitGUID`/姓名板附着/TargetLine 这类 Nampower 依赖（反向钉）。
  ★**证据（exe 侧，可复核）**：`RAW_COMBATLOG`（Nampower 的结构化战斗事件口）**0 命中**，同批 `CHAT_MSG_*`/
  `PLAYER_ENTERING_WORLD` 各 1 命中 ⇒ 事件注册表确实编译在 exe 里；`UnitGUID`/`GetNameplateGUID` 同样 0 命中。
  取证工具 = `node tmp/client_sym_scan.js <符号名>`（支持 `--ctx`）。
  ★**判据边界**：exe 只装**引擎侧**事件名与 C API；FrameXML 的 Lua 全局名在 Content 包里 ⇒ exe 查不到 ≠ 不存在。
- ★★★**「提不出数字不硬显示」是全局尺子**（用户真机反馈「两个没有伤害的技能会显示之前的Cat 伤害信息」）：
  任何战斗文本处理器**提不出数字就一个字节都不画**，并把该句的**句形**落环供校准 ——
  ★**反向钉：全文件不许再出现 `numOf(m) or m`**（旧写法会把整句原文当伤害值画在屏幕上；真机例
  「你施放毒蛇钉刺失败：尚未恢复」「Cat的撕咬没有击中雌性草原狮。」）。结构钉守着这条。
- ★★★**自我受击（incoming）有归属门**（真机例「雌性草原狮击中Cat造成8点伤害。」= 宠物挨打）：
  整句必须含「你」才显示 —— 否则宠物/别人的挨打会显示成红色「-X」当作我受到的伤害（`inHit`/`inMiss` 都加）。
- ★★★**姓名板附着做不了（2026-10-08 定案，别再重做）**：用户需求 = 把伤害数字锚到**怪头顶那条浮动姓名板**。
  取证：本客户端姓名板是 **UE 引擎 widget**（exe 里 `AzerothNameplateWidget` / `AzerothNameplateWidgetComponent` /
  `HealthPlateComponent`），**Lua 侧只有 `ShowNameplates`/`HideNameplates`/`ShowFriendNameplates`/`HideFriendNameplates`
  四个开关函数**；无 `GetNameplateGUID`/`UnitGUID`/`UnitPosition`/`GetCameraPosition`（exe 0 命中，
  `node tmp/client_sym_scan.js` 可复核）、无 Lua 侧 `WorldToScreen`（只有 UE 内部 `ProjectWorldToScreen` 符号）、
  `_G["NamePlate1"]` 也不存在 ⇒ **没有句柄、没有单位世界坐标、没有世界→屏幕转换**，三样都没有就锚不上。
  同族旁证：unrealUI 的姓名板模块（WORKING_SOURCE 抄 UnrealPfUI）在本客户端首轮实测 **28 子件 / 0 plates / 28 rejected**；
  UnrealQuest 记 `world.nameplates_are_not_lua_widgets`（WorldFrame 26 子件全是 FrameXML 家具）+ 一次**假姓名板**事故
  （5 个子件被认成姓名板、1204 次读名字全读出 "Item Name"）；本机也没装 pfUI/ShaguPlates 这类自带 Lua 姓名板的插件可挂靠。
  ★曾按「有血条呈现 + 名字匹配就把数字锚到**目标框体血条**重心」实现并真机跑通（贴到血条 15 条），
  但用户要的是浮动姓名板 ⇒ **整条回退**（代码里已无残留；`/edmg 锚点`、`/edmg 姓名板` 两条探针一并撤）。
- ★★★**宠物技能图标**（用户问「宠物技能击中能显示对应图标吗?」）：图标缓存（`D.iconScan`）除玩家法术书外，
  再扫 **宠物动作条 `GetPetActionInfo(i)`**（Pet 类 API，本客户端在案；vanilla 形状 = name, subtext, texture,
  isToken,…；token 名字经 `_G` 转本地化名）+ 宠物法术书 `GetSpellName(i,"pet")` 兜底；
  技能名由 **`spellFromMsg(m)`** 按真机句式取（宠物技能「Cat的撕咬击中X造成8点伤害。」⇒ 撕咬 ·
  用 `UnitName("pet")` 锚定宠物名，不做任何「猜技能」；宠物普攻「Cat击中X…」与玩家平砍「你击中X…」**不给名**）。
  ★`PET_BAR_UPDATE` / `UNIT_PET` 时重扫（新学的技能不用 /reload）；**查不到就一个图标都不画**（绝不画 ? 图）。
- ★★★**动画 = 绝对时间驱动**（`t = now - t0`，与帧率无关）：smoothstep 淡入淡出 `t*t*(3-2*t)`（前 10% 入 / 后 50% 出）·
  暴击 = 0.35s 窗口内抬一档字号（0.2.0 起；旧「三段缩放」随字号机制一起作废）· 彩虹弧线 `y = y0 + 240t − 200t²`
  （0.2.1 加高：峰值 ~72px · 0.6s 到顶 · 落到锚点以下；旧 `140t − 240t²` 峰值仅 ~20px）+ 侧漂。
- ★**滚动方向 11 种**（0.2.2 八种 + 0.2.23 蹦出系三种，`DIRS`/`DIR_ZH` 两表同步是判据）：up / down / arc /
  angleUp（斜上抛物）/ angleDown（斜下抛物）/ horiz（水平散开）/ sprinkler（洒水散开，分段：0.3s 斜喷→缓升微摆）/
  sine（正弦上升）/ **burst / burstL / burstR（极速蹦出·直上/斜左/斜右）**；
  全部 `t` 绝对时间驱动（★别退回 DamageEx 的逐帧累加写法 —— 帧率一变手感就变）；新增方向必须进两表 + harness ④d/④e 位移签名钉。
- ★**暴击变红**（0.2.26；用户：「暴击的时候将伤害值变红色」）：判定走 **`s.critTxt`（暴击文字身份，
  与「暴击动画」开关 critAnim **解耦** —— 0.2.26b；首版挂在 s.crit 上被开关挡住 ⇒ 关着动画的人看不到红，
  用户报障「致命一击 没有标红」）**：crit 文本 ⇒ `addText` 里该条字**整条变红**（`1, 0.15, 0.1`）；
  字号抬档仍走 `s.crit`（开关只管动画、不管颜色）；槽复用不串色（颜色每次出生都重写）。harness ④g/④g2 五条钉。
- ★★**移动上限 + 屏界保险丝**（0.2.25；用户：「动画移动的上限或者下限占屏幕百分百?有时候技能都飘到屏幕外面去了」→ A+B）：
  tick 里轨迹算完的**最后一步**两道夹取：⒜ **行程夹取** `|x−x0| ≤ 屏宽×clampPct%`、`|y−y0| ≤ 屏高×clampPct%`
  （到顶原地停住继续淡出；与方向/曲线/速度/时长全兼容）；⒝ **屏界夹取** 最终坐标恒在屏内（CENTER 锚口径 ±宽/2、±高/2）。
  配置 `clampPct` 默认 **30**（5~60，面板「曲线」右边空槽 ±5 步进）；屏尺寸读不到 ⇒ 回落 1024×768。
  ★桩里 UIParent 无 `GetWidth/GetHeight` ⇒ 回落值生效 —— harness ④f 三条钉按 768 算 230.4。
- ★★★**两个锚点 + 受击下移（0.2.28；用户真机报障「受到的伤害数字太下面的.距离锚点太远了.」）**：
  **车道 ↔ 锚点是一对一** —— 金色锚点（`EH_DMG_ANCHOR`，写 `posX/posY`）管 `lane="out"`（伤害/治疗/效果），
  **红色锚点**（`EH_DMG_INANCHOR`，只认垂直位移、直接写 `inOffY`）管 `lane="in"`（受击/治疗/能量）。
  **同一字段只有一个算式**：受击行起点 = `posY + inOffY`，`addText` / `editPlace` / 面板步进 / 拖拽四处**共用**
  它，范围常量也共用 `D.INOFF_MIN/MAX`（-400~-20）—— **绝不各写一份**（改一处漏三处 = 定了位置又跳回去）。
  ★**默认值 -120**（旧默认 -170 在中线以下 230px，再叠 `down` 车道向下漂移 ⇒ 整段落到动作条那带）；
  老存档迁移**只升级 -170 这个确切值** + `inOffMig` 一次性 + 如实出声（面板此前没有这个旋钮 ⇒ 出现 -170 必是旧默认）。
  ★**数字还会往下漂** ⇒ 「离锚点多远」由 `clampPct`（移动上限，5~60%）决定，锚点只定**起点**；
  两个旋钮要一起说（用户问「太远」时先给锚点、再说移动上限）。
  ★★★**受击下移 = 整数**（用户：「受击位移只 int 类型处理下不需要保留小数位」—— 面板曾显示 `-43.86591064453` 折两行）：
  **三个写入口全部取整**（红锚点拖拽 `math.floor(光标差+0.5)` 再夹 / 面板步进先归整再加 ±10 / `cfgEnsure` 把已存的浮点老值
  一次性归整），显示也按整数（面板 + `/edmg 状态`）—— ★光标是浮点是本客户端既有口径 ⇒ **凡是把光标差写进存档的字段，
  都要问一句「它该不该是小数」**（`posX/posY` 保持原样：它们不进面板、只按整数打印）。
  ★改面板高度记得同步 harness 那条钉（`panel._h` 424 → **448**，参数区 3 行 → 4 行）。
- ★★**dot/周期伤害归属门**（0.2.24；用户真机报障「某些其他骑士的奉献神圣伤害会在牧师的伤害界面上显示?」）：
  `CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE` / `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE` 这族事件的
  「目标类别」= 敌对玩家/生物、**来源不限**（vanilla 语义：附近任何人的 DoT 都会进战斗日志）⇒ 别人的奉献
  （范围周期神圣伤害）会显示成我们的 dot ⇒ **归属门 = 消息必须以「你」开头**（真机已校准句式一律「你的 …」），
  不是 ⇒ 跳过 + `capture("DOT-OTHER", m)`。★反向钉：这条门**不许再删**（删了 = 报障复发）；
  harness ⑦e 三条钉（别人的不显示 · 落环 · 自己的不误伤）。
- ★★**曲线函数库 + 配置项**（0.2.23；用户：「模仿官方的伤害展现方式…有哪些曲线函数支持吗?增加专门曲线函数的配置项?」）：
  官方 FCT 手感 = **缓出**（快起慢收）；`CURVES` 四种 = 缓出立方（默认，`1-(1-t)³`）· 缓出平方 · **回弹过冲 `back`
  （c1=1.70158/c3=2.70158，途中过冲到终点以上 ~1.10 再回落 = 「蹦」）**· 指数缓出（起步最暴）；
  配置真值 `c.curve`（唯一写口 = 面板「曲线」行循环，`-` 反向）；**曲线吃进度分数 `t/dur`（0..1），不是秒**
  （tick 里 t 是秒 ⇒ 崩出系方向必须先 `f = t / s.dur`，0.2.23 首版就错在这里被 harness 抓到）；
  行程 = `速度 × 时长 × 0.45`（比例恒定）；曲线只对 burst 系生效（其余 8 种轨迹各有自形，不串）。
- ★★★**防重叠 = 新字恒从锚点出发**（0.1.2 重写；真机报障「技能伤害定位越来越高」换来的）：先到的字已漂走、天然不叠；
  只有「同一瞬间连发」（同车道最近一条**当前 y** 离锚点不足一个行距）才往上/下摞一格 —— 判据从活动槽的
  **`s.cy`（当前 y）** 现算，槽出生即写 `s.cy`（复用槽不吃上一条命的残值）。★**反向钉：绝不许再用「黏性游标
  只有车道全空才复位」那版**（连续战斗时车道永远不空 ⇒ 每条 +行距 ⇒ 无限爬高）。回归钉 = harness ④b 三条。
- ★★★**关断四件事**（宿主 §4.1 尺子）：关总开关 `D.setMaster(false)` = ① 槽全收（`slotReleaseAll`，1.12 无销毁 API ⇒ Hide+清账）
  ② 节拍真摘（唯一入口 `beatSync`，`SetScript(D.frame,"OnUpdate",nil)`；再开重挂同一 handler，不用 /reload）
  ③ 数据重置（游标/拖拽/低血武装复位）④ 图层清理（编辑锚点 Hide + 摘全部事件 `eventSync`）。
  判据 = `tmp/ehdmg_harness.js` ⑩ 组（关后 `addText` 被拒 / 节拍 nil / 事件摘除 / 再开全恢复）。
- ★★★**记忆体分离**（宿主契约 ②）：本插件**只**读写 `EH_DAMAGE_CFG`；文件里**一个字都不许提**
  `EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR`（`tmp/ehdmg_wiring_check.js` 有钉）。
- ★★★**资源独立性（0.2.x 全仓审计定案）**：本插件**零外部插件资源依赖** —— 引用的全部是**客户端内建资源**
  （`Interface\Buttons\WHITE8X8` · 客户端 Fonts 目录 · Fonts.xml 分档字体对象 · `GetSpellTexture` 图标库 ·
  `GameFontNormalSmall` 模板），**对宿主插件路径与 `EVAL_HELP_*` 全局零引用**。★判据：客户端内建资源**不复制**
  （复制 = 冗余）；今后若新增对任何**插件侧**素材的依赖（含宿主 media），一律先复制进本目录 `media\` 再引用，
  并把依赖写进本节；`EVAL_EDMG_*` 全局口是本插件自定义，不是宿主桥。
- ★★★**Lua 模式的多字节陷阱**：`?`/`-` 等量词按字节作用 ⇒ 「了?」会切掉半个汉字（宿主老坑）⇒
  可选字一律**写两条模式分别试**（锚点 = `CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS` 处理器里的注释）。
- ★★★**字号终案 = 分档字体对象**（0.2.0 定案，0.2.17 全部通道封死）：**文字放大封顶 = 6 档**（`D.TIER`
  小/中/大/特大/巨大/超大），特大档数字行（`KIND_NUMERIC`）走 `NumberFontNormalHuge`、中文行走 `GameFontNormalHuge`，
  缺字体对象逐级向下回退；暴击 = 0.35s 窗口内抬一档（封顶超大）；行距 = `D.TIER_H[tier]`。
  ★**已证死的通道（别再回头）**：`SetFont(路径,号)` · `SetTextHeight` · 帧 `SetScale`（只放大框体/纹理，不传导文字）
  · `_G[自动名]` 真对象 `SetScale`（0.2.17 A 组实证一样小）· **Button 标题**（`GetFontString` = **false** —
  本客户端按钮没有文字通道，`SetText` 白返回）· **按钮 + 子 FontString + `SetScale`**（0.2.19 匿名包装 ·
  0.2.21 **具名 `EH_DMG_SPB<n>` + `_G[名]` 按名缩放 —— 与 DebugBox 缩放锚点完全同一条路，文字照样不动；
  锚点「文字变大」的观感 = DebugBox 自己的 `scaleDeep` 逐节点下探路径，插件侧复制不出来）。★反向钉：档位语义只经
  `sizeApply(fs, tier, kind)`，不许再退回任何「改字号/缩放」写法当主机制。★**探针已清理（0.2.22）**：
  终局封死后 `/edmg 字号探针` · `/edmg 缩放探针` · `/edmg 字体` 三个探索性探针整条移除（同 EH_Bag 0.3.31
  `glowDbg` / 0.3.38 `iconProbe` 的「收口后清调试指令」先例）—— 要复核结论去翻 CHANGELOG 0.2.0~0.2.21 与
  本条的证据链，别再把探针加回来。
- ★**显示项真值** = `EH_DAMAGE_CFG["it_"..id]`（15 项 + incoming 附加项，默认照暴雪「浮动战斗信息」截图）；
  唯一写口 = 配置面板勾选 / 恢复默认按钮；kind→显示项的门 = `KIND_ITEM` 表（**新 kind 必须进表**，否则不受开关管）。

## 本子插件专属闸门（`tmp/`，只在统一推送时跑）

| 脚本 | 作用 |
| :-- | :-- |
| `tmp/ehdmg_harness.js` | 离线真跑（fengari）：载入零副作用 · VLA 武装 · 动画推进 · 事件解析 · 捕获环 · 编辑模式 · 关断四件事 |
| `tmp/ehdmg_wiring_check.js` | 接线结构钉（五处契约 + 记忆体分离 + 一个节拍帧） |
| `tmp/ehdmg_rules_harness.js` | **伤害文本规则匹配修复专项**（离线真跑 · 保真桩 + 真源码切片）：宠物技能图标三态与 `spellFromMsg` 五条真机句式 · 三条无伤害文本一条都不画且句形入环 · 受到伤害归属门（宠物挨打不显示 / 真·我挨打照旧 −9）· 句形去重与有界 · 关断四件事与句形表清 · 读值口/状态行不含已删字段 · 剥注释后的反向钉（无已删定位实现 / 无 GUID·姓名板 API / 无 `numOf(m) or m`）= **行为 40 + 结构钉 9** |

★**本工作副本（D 盘仓库）的 `tmp/` 里只有 `ehdmg_rules_harness.js`** —— 上面那两个（`ehdmg_harness.js` /
`ehdmg_wiring_check.js`）是**另一台机器**上的成套闸门，`tmp/` 本身被 `.gitignore` 忽略、不随仓库走。
⇒ 在本机核对本插件改动时，**能跑的就是这一个**；不要把「本机跑不了那两个」误读成「闸门不存在」。
★取证类工具同目录：`tmp/client_sym_scan.js`（查客户端 exe 里有没有某个 API/事件符号，判据边界见上）。

★功能修改过程中只跑 `node luacheck.js` + `node sync_game.js`；那一轮不得声称「过了全套闸门」。

## 发布打包

· 独立打包两份：`EH_Damage-v<子版本>.zip` + 固定名 `EH_Damage.zip`（子版本现读 toc `## Version`）；
进包 = toc 列的 `.lua` + `README.md` + `CHANGELOG.md`；不进包 = `CLAUDE.md`。规矩全文 = 宿主 `CLAUDE.md` §4.3。
