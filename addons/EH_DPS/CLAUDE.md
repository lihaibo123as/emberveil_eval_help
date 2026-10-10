# EH_DPS 子插件记忆体（铁律 / 判据 / 锚点）

> ★本文件 = **EH_DPS 自己的记忆体**（与宿主 `CLAUDE.md` 分目录存储，用户定）。
> · 面向使用者 = 同目录 `README.md`；逐版本改动 = 同目录 `CHANGELOG.md`。
> · 宿主 `CLAUDE.md` 的通用铁律照旧适用（`node luacheck.js` 闸门 · 不许子代理 · 答复中文 · 改完同步 · 不自动提交…），本文件不重复。
>
> ★★★**子插件之间的隔离性（开发规范 = 宿主 `CLAUDE.md` §4.3 宿主契约 ⑤）**：跨插件口一律
> 「**运行期现读**（`rawget(_G,"名字")`）· **对象在 ∧ 方法在**（`type` 两道）· **调用 `pcall`** · **拿不到就 fail-open + 如实降级**」；
> **对手方不存在 / 是空表 / 没那个口 / 口会抛错 ⇒ 一律不许报错**，也不许写别人的存档根。
> 常驻闸门 = **`node tmp/subaddon_isolation_probe.js`**（★新增跨插件口要同步它的 `LIST`，否则清单腿报红）。
> ★本子插件的跨插件口**实测 = 0 处**（全仓边界引用清单里 `EVAL_*` / `EH_*` 命中 0；资源独立性那条已定案：
> 只用客户端内建资源、对宿主与别的子插件零引用）⇒ 今后**若新增**任何口，必须照上面这套口径写并把清单同步进去。
>
> ★★★**命名与播报口径（开发规范 = 宿主 `CLAUDE.md` §4.3 宿主契约 ⑥）**：面向玩家的前缀一律 **`[EH_DPS]`**（= 目录名）
> —— 载入信息 · 命令回显 · 错误/诊断行 · 帮助头一行全在内（★本插件**内部表名恰好也叫 `EH_DPS`**，不是反例：
> 判据看的是「面向玩家的前缀 == 目录名」，两份合一照样只在**一处**拼前缀）。
> 常驻闸门 = **`node tmp/subaddon_naming_probe.js`**。

## 本目录构成与同步

| 文件 | 作用 |
| :-- | :-- |
| `EH_DPS.lua` | 主实现（配置 / 数据采集 / 双段数据模型 / 进度条窗口 / 报告 / 命令） |
| `EH_DPS.toc` | 载入清单 + `## Version` + `## SavedVariables: EH_DPS_CFG` |
| `README.md` / `CLAUDE.md` / `CHANGELOG.md` | 使用者说明 / 本文件 / 改动记录（`0.1.x` ↔ 宿主 `1.75.y`） |

★本子插件**没有 `media\`**（纯 WHITE8X8 纯色纹理 + 分档字体对象）。★同步 = `node sync_game.js`（整目录拷到插件同级）+ `node tmp/verify_sync.js` 逐字节核对。

## 判据正文

- ★★★**事件源只能是 SCT 模式（CHAT_MSG_ 文本解析）**：本客户端无结构化战斗事件、无 GUID API
  （1329 条 API 索引在案；与 EH_Damage 同一三轮调研定案）⇒ ① 事件名与文本格式**不许猜**（铁律 5）：
  模式表照 EH_Damage 真机校准句式起手，未识别的战斗文本走**捕获环**
  （`/edps 捕获` 开 → 原文落 `EH_DPS_CFG.ring` 有界 40 → `/edps 事件` 查看）；
  ② **绝不引入** `GetUnitGUID`/Nampower 依赖（反向钉）。
- ★★★**定位 = 全队伍级（0.2.0 起）**：数据模型 = `seg.p[玩家名]` 记录（七项总量
  `dmg/heal/taken/healT/ener/kills/casts` + 明细 `dmgD/healD/takenD/healTD/enerD/castD/killD`
  + 各自 `actT/actTick`），字段↔视图键唯一映射口 = `PKEY` 表；记账唯一口 `bumpP(kind, name, n, spell, active)`
  （**名册闸在里面**：不在 `D.partyNames` 的一律不记）。名册在 VLA / `PARTY_MEMBERS_CHANGED` /
  `RAID_ROSTER_UPDATE` / `PLAYER_ENTERING_WORLD` 重建（顺带记职业 token）。**击杀/能量/施放只有自己**
  （战斗文本不署别人的名，如实告知）。**承受伤害队伍级** = 怪打队友事件
  （`CREATURE_VS_PARTY_HITS` 真机已实证 + `SPELL_CREATURE_VS_PARTY_DAMAGE`），按受害者记。
  ★**治疗统一解析 `healMsg`**：治疗者进 heal、被治疗者进 healT，三族 BUFF 事件共用
  （「你因 X 的 Y 而获得」/「X 的 Y 治疗了 Z」/「为 Z 恢复」都认）。
  ★**击杀剥尾号绝不许用 `[！!]` 字符集**（按字节 ⇒ 全角「！」拆半个进名字、去重失效，harness 抓到）；
  用整字后缀 `gsub("！$","")`。
  ★**DoT 归属门**（EH_Damage 0.2.24 真机定案移植）：`PERIODIC_*_DAMAGE` 族来源不限 ⇒ 自己的 DoT 处理器
  不是「你」开头一律不记 + `capture("DOT-OTHER")`（反向钉，删了 = 别人的奉献进自己的账）。
  ★句式是 zhCN 尽力而为 ⇒ 真机校准靠捕获环；团队（40 人）句式和队伍同族。
  ★**职业染色**：`classRGB`（认不出 = 灰）；总览/下钻都按职业染。★**0.2.5 定稿：标准职业色 + 不透明**
  （用户：「职业色按照正常的职业则.不要添加透明度」⇒ 提亮系数 `CLASS_LIFT` 已删（0.1.4/0.2.2 的提亮方案作废）、
  条目条 alpha **1.0**；wiring 反向钉守着）。
  ★**旧档兼容**：0.2.0 模型换代 ⇒ `LoadData` 只认带 `p` 键的新档，旧扁平档丢弃 + 如实播报一次。
- ★★**外观（0.1.2 用户定，0.2.2 微调定稿）**：边框与**标题栏底** = 黑色 0.85 透明、背景 = 黑底
  （透明度 `bgAlpha` 0.30~1.00 可配，**默认 0.50**；旧默认 0.85 一次性迁移 `bgAlphaMig` + 播报，自调档不动）、
  **每个视图标题配不同鲜艳色**（`VIEWS[].col`；伤害量亮金黄 0.2.1）；**条目文字白色**（0.2.4 定：
  0.2.2 的黑字方案退回——条短的时候文字超出条尾落在黑底上直接消失）；
  条目高度 `rowH`（**22~30，默认 22**，clamp 下界兼做旧档迁移）；**文字一律去阴影**
  （`mkFont` 统一 `SetShadowColor(0,0,0,0)`+`SetShadowOffset(0,0)`）。
  ★**配置面板 `EH_DPS_CFGPANEL`**（标题 [设] 钮）：与视图菜单**共用同一个捕手** `EH_DPS_MENUCATCH`、
  互斥开关；显示值重画唯一口 `D.CfgPaint`；`D.ViewMenuHide` 一把收（菜单 + 配置 + 捕手）。
  ★**下钻态 `D.detail`**：进出只两处（行 OnClick 进 / 返钮·换视图·换段退）。
  ★**默认开窗（0.1.2b 用户定）**：载入期「总开关开 ∧ `winShown ~= false`」⇒ 自动摆出；
  [×] 写 `winShown=false`（记住关过），`/edps`/`/edps 开` 恢复；`setMaster(true)` 也摆窗。
- ★★**标题右键 = 视图下拉菜单**（0.1.1）：`EH_DPS_HDR` 注册 `LeftButtonUp/RightButtonUp`，
  鼠标键从全局 `arg1` 取（项目 idiom）；菜单 `EH_DPS_VIEWMENU`（DIALOG/300）+ 点外面即关捕手
  `EH_DPS_MENUCATCH`（290）；当前行金色（唯一绘制口 `D.ViewMenuPaint`，OnLeave 也回这里重画）；
  关断时 `setMaster(false)` 连带收菜单。
- ★★**数据模型 = 双段**（`D.data[0]`全程 / `[1]`当前战斗）：进战（`PLAYER_REGEN_DISABLED`）重置当前段，
  脱战记 `fightT` 并 `D.SaveData()` 持久化（跨 /reload 恢复全程段）；**活跃时间 EDPS = 5 秒规则**
  （`touchActive`：距上次 >5s 按 +5s 计，否则按实际差——抄 ShaguDPS `_ctime` 算法）。
- ★★**击杀去重**：`CHAT_MSG_COMBAT_HOSTILE_DEATH` 对同一只怪发**两条**
  （「你杀死了X！」+「X死亡了。」，本项目在案事实）⇒ `killOnce` 同名 2s 窗去重。
- ★★**裸名字负载守卫**：incoming 族事件的 arg1 可能是**裸名字**而非整句（EH_Damage 0.2.4 真机实锤）
  ⇒ 提不出数字一律不记、原文落环（治疗/DoT/承受伤害同一把尺子）。
- ★★★**Lua 模式多字节陷阱**：`?` 等量词按字节作用 ⇒ 可选字写两条模式分别试
  （能量获取「获得/获得了」族就是这么写的）。
- ★★★**关断四件事**（宿主 §4.1 尺子）：`D.setMaster(false)` = ① 收窗 ② 真摘节拍
  （`D.frame` 唯一节拍帧，`beatSync` 唯一挂/摘入口；节拍职责 = 节流刷新 + 报告队列滴出）
  ③ 会话态重置（`reportQ`/`killRecent`/`dirty`）④ 摘全部事件（`eventSync`）。数据保留在存档。
- ★★★**记忆体分离**（宿主契约 ②）：只读写 `EH_DPS_CFG`；文件里一个字都不许提
  `EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR`。
- ★★★**资源独立性**：只用客户端内建资源（`Interface\Buttons\WHITE8X8` · Fonts 字体对象），
  对宿主路径与 `EVAL_*` 全局零引用；`EH_DPS` 全局表是本插件自定义调试口。
- ★★**报告 = Protected 绕行 + 限频**：`SendChatMessage` 是 Protected ⇒ `pcall(RunScript, ...)`，
  0.6s 滴出（RunScript 也是队列，连发会被踢）；失败如实兜底聊天行，绝不静默。
  ★★★**断线审计收口（0.1.0，用户报「刚开起来就断线」后的全量调用面审计）**：
  ① **本插件唯一的服务器写动作 = 聊天报告**，其余全部是本地读 ⇒ 载入/开窗路径**零服务器写**，
  「没点报告却被踢」就要往别处查（RunScript 是**共享队列**，宿主一键宏也在用，两边叠加才会撞限）；
  ② **报告防叠加**：队列非空时拒绝新报告并如实播报（队列无上限叠加 = 持续数分钟的发送链 = 真踢线风险）；
  ③ 报告内容**剥引号**（名字含 `"` 会截断 RunScript 串）；④ `killRecent` **有界**（>100 整表清，
  2s 去重窗短、清了无害）；⑤ 尺寸拖拽 `Layout` 0.05s 节流（本地 CPU，不涉服务器）。
  判据 = harness ⑦ 组新增「队列非空拒绝」「去重表有界」+ wiring 四钉。
- ★**窗口配方**：拖动柄 = 标题栏 Button（`RegisterForDrag` + `StartMoving`）；
  位置记忆 = 左上角 `GetLeft/GetTop` ÷ `GetEffectiveScale` 存、`TOPLEFT/BOTTOMLEFT` 恢复
  （旧中心档一次性作废 `posV2`；★**绝不许退回 GetCenter/CENTER** —— 锚居中会让右下改尺寸时整窗抖动）；
  行 = 纯色纹理条 + FontString。
  ★**字形坑（0.1.0 真机截图定案）**：本客户端字体链**没有 ◀ ▶ 图形字形**（画出来是空白方块）⇒
  视图循环按钮用 ASCII `<` `>`（宿主「▲/▼」那对字形是可用的，但左右箭头不可用）；wiring 有反向钉。
  ★**右下角尺寸拖拽柄 `EH_DPS_RESIZE`**：宽 180~400（`W_MIN/W_MAX`）· 行数 4~20（`ROW_MIN/ROW_MAX`），
  真值 `pw/pr` 落存档；几何唯一口 `D.Layout`，行池 `ROW_MAX=20` 建一次只 Show/Hide。
  ★★**收尾三条路（0.1.0 真机报障「释放不稳」定案）**：柄 `OnMouseUp` / **全屏接盘 `EH_DPS_RSCATCH`**
  （起拖时盖上，任意位置松开都收尾）/ 节拍键状态 —— 全部汇到唯一收尾口 `D.ResizeEnd`（幂等）。
  ★★**窗口锚 = 左上角**（0.1.0 真机报障「居中调整尺寸 ⇒ 抖动」定案）：位置记忆存 `GetLeft/GetTop`
  （旧中心档一次性作废 `posV2`），改尺寸只往右下长；反向钉守着「不许退回 GetCenter」。
  ★★**Ctrl+滚轮 = 整窗缩放**：真值 `scale`（0.6~1.6，`Z_MIN/Z_MAX`）落存档；**几何重建**（Layout 按 z
  现算全部尺寸，**禁用 SetScale** —— 项目铁律「点击框漂移」）；缩放要除进拖拽口径（`es*z`）。
  ★**字号不随缩放变** = 客户端限制（FontString 不吃任何缩放/改字号，EH_Damage 探针定案），如实告知。

## 本子插件专属闸门（`tmp/`，只在统一推送时跑）

| 脚本 | 作用 |
| :-- | :-- |
| `tmp/ehdps_harness.js` | 离线真跑（fengari）：载入零副作用 · 句式解析 · 双段与战斗时长 · EDPS · 击杀去重 · 报告限频 · 关断四件事 |
| `tmp/ehdps_wiring_check.js` | 接线结构钉（SUBADDONS / 三语键 / toc / probe 清单 / 记忆体分离 / 一个节拍帧） |
| `tmp/subaddon_isolation_probe.js` | **子插件之间的隔离性常驻闸门**（宿主契约 ⑤，全项目共用）：边界引用清单逐条比对 · 每处守卫（`type` + `pcall` + `rawget`）· **对手方缺席/空表/口坏掉真跑不报错** · 不许写别人的存档根。★**新增跨插件口要同步它的 `LIST`**（本子插件现为 0 处） |
| `tmp/subaddon_naming_probe.js` | **命名与播报口径常驻闸门**（宿主契约 ⑥，全项目共用）：目录名形态 = `EH_<名>` · 该目录里**所有** `[EH_xxx]` 前缀逐字等于目录名 · 名字 → 前缀的**单一来源** · **反向钉**：内部名**当前缀** = 0 处（本插件内部表名恰好 = `EH_DPS`，两份合一） |

★功能修改过程中只跑 `node luacheck.js` + `node sync_game.js`；那一轮不得声称「过了全套闸门」。

## 发布打包

· 独立打包两份：`EH_DPS-v<子版本>.zip` + 固定名 `EH_DPS.zip`（子版本现读 toc `## Version`）；
进包 = toc 列的 `.lua` + `README.md` + `CHANGELOG.md`；不进包 = `CLAUDE.md`。规矩全文 = 宿主 `CLAUDE.md` §4.3。
