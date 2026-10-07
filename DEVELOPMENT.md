# DEVELOPMENT —— EVAL_HELP 开发指南

> 面向想参与开发的第三方（人类或 AI）。读完这份 + `CLAUDE.md`（AI 记忆体）即可上手。

## 项目概况

- EmberVeil 私服客户端（1.12.1 规则 / UE 引擎 / **Lua 5.1**）的 FrameXML 插件；
- **多文件架构**（1.39.0 起模块化；**真实载入顺序 = `EvalHelp.toc` 的顺序，以 .toc 为唯一真值**）：
  `Locales/{zhCN,enUS,ruRU}` → `Core.lua`（输出/i18n/状态采集+UPDATE_STATE/UI 越界助手）→ `Engine.lua`（一键宏引擎：扫描/五分类/规则引擎/解析/免疫/光环/距离/队伍扫描）
  → `EvalHelp.lua`（全部 UI 窗口+斜杠+初始化）→ `examples/*.lua`（12 个案例模版数据文件）→ `Toolbox.lua`（Tab3 工具箱）
  → **`quest/` 数据层（4 个**只读数据文件**，顺序不能换）**：`QuestData.lua`（策展链）→ `QuestBulk.lua`（全量任务/装备生成物）→
    **`QuestAll.lua`（全量任务表生成物：4018 条任务 + 奖励/需要等级 + 父子任务 + 需求材料，1.75.14 起）** → `QuestChains.lua`（上述三张表的数据层封装：搜索/筛选/树/详情）
    —— ★同目录的 `fetch.js`/`build*.js`/`sweep*.js`/`audit.js`/`chains.js`/`cache/` 都是**开发脚本与抓取缓存**，**不进发布包**
  → `DataSearch.lua`（Tab4 任务线 & 装备）→ `Share.lua`（方案分享）→ `IconSem.lua`（图标语义表，1.73.5）
  → `IconBrowser.lua`（Tab5 图标库）→ `PetData.lua`/`PetHelper.lua`（Tab6 抓宠帮手，1.73.0）→ **`ItemPriceData.lua`（物品价基准价**生成物**：13,994 条 vanilla 价，1.75.43；生成器 = `gen_itemprices.js`，**绝不手改**）**
  → **`MapOverlayData.lua`（世界地图探索层区域表**生成物**：53 图 / 707 区，1.75.51；生成器 = `gen_mapoverlay.js`，源 = 本仓库快照 `doc/地图层数据-源快照.txt`，**绝不手改**）**
  → **`MapOverlayOffset.lua`（「本游戏专属坐标补偿」独立偏移量数据库**生成物**：生效次序 = 存档 > 文件 > 无；口令「同步偏移量」= `node gen_mapoffset.js --account <账号>`（点名某张图 = 整图替换），1.75.60）**
  → **`MapOverlayJPGData.lua`（「区域实景」定位基线**生成物**：**56 图**各一条 `{1002,668,0,0}`（1.75.71 换成 AI 高清重绘版后删掉 `Balor`，57 → 56），生成器 = `tmp/gen_mapjpgdata.js`，1.75.64~1.75.71）+ `MapOverlayOffsetJPG.lua`（实景那一套偏移库，与上一份完全对称，生成器 = `node gen_mapoffset.js --jpg`）** —— ★这三份都是**生成物、绝不手改**，且 toc 里必须排在其消费方 `tools\WorldFog.lua` **之前**
  → **`tools/` 工具模块（14 个，顺序照 `.toc`）**：`SimpleMap.lua`（缩放大地图 + **探索层折算**）→ **`WorldFog.lua`（世界迷雾独立模块：工具箱行「**关闭世界迷雾**」+ 表驱动全渲染 + 接管守护 + 残留清理 + **自带节拍帧** `EH_WF_FEAT`，1.75.56；★1.75.64 起含**「区域彩图 / 区域实景」双图层**（实景 = `media/WorldMapJpg` 整区一张 JPG、写 `OVERLAY` 绘制层；两套补偿分家 = `edit`/`editJpg` + `MapOverlayOffset`/`MapOverlayOffsetJPG` 换存储根、基表按模式分派；切换 = 一次「关断四件事」，先 `release` 再换真值；1.75.64~1.75.70）；与缩放大地图只走一行桥白名单）** → `IconGrid.lua`（通用图标网格选择器：单选/多选 · 高度自适应 · 分页滚轮夹取，1.74.5）→ `HunterHelper.lua`（猎人助手 · 一键喂食，1.74.5）→ `ConsumableHelper.lua`（消耗品助手 · 多选横排各自点用，1.74.5）→ `DismountHelper.lua`（骑乘助手 · 一键下马，1.74.7）→ `RareWatch.lua`（稀有提醒转播独立模块，1.74.27）→ `DragFrames.lua`（图层拖拽，1.74.30）→ `LayerFix.lua`（图层隐藏，1.74.34）→ **`LootCursor.lua`（拾取贴手 · 搬窗贴手 + 点一次换下一件 + 品质角标，1.75.26）** → **`InfoBar.lua`（顶部信息条：六段 · 移植自开源 SimpleInfoBar/MIT，1.75.40）** → **`ItemPrice.lua`（物品价：商人处学真价 + 悬停价格行 + 背包·银行估值，1.75.43）** → **`EquipCompare.lua`（装备比较：自建对比框 + 部位判定 + 差异染色 + 换装差值汇总，1.75.45）** → **`Probes.lua`（探针命令集中地：`PR[id]` 注册表 + 宿主一行 `prRun`；toc 预载但**载入期零副作用**、首用才建，1.75.35）**
    ★工具模块一律**自包含**（真值 + 自己的存档子树 + 界面控件 + 读值口 + 自己的**有界**计时器）；`Toolbox.lua` 里只留「一行数据 + 模块行注册表 `EVAL_TB_MOD_ROWS[mod]`」，渲染/下拉/结算全在模块里。
  → **`media/`（运行期贴图）**：`Flags/`（旗帜）· `icons/`（图标）· **`WorldMap/<地图>/<区域><块号>.blp`（「打开世界迷雾」的**可选**自带贴图，1.75.53；生成器 = `gen_worldmap_media.js --from <interface.MPQ> --full-only`，**只放整张齐全的图**、逐字节可复现）** · **`WorldMapJpg/<地图>.jpg`（「区域实景」图库：**56 图** = 53 区域 + 露天主城 3 座（暴风城 / 达纳苏斯 / 雷霆崖）；生成器 = `tmp/make_city_jpg.js`（主城）/ `tmp/minimap_stitch.js`（区域）；★**素材规格 = 宽 ≤1500**（`tmp/jpg_cap1500.js`；1.75.70 另做过一轮质量门控压缩 `tmp/jpg_compress.js`，1.75.71 整库换成 AI 高清重绘版后**只封顶、不再压**）：**当前 56 图 / 44.8 MB**，1.75.64~1.75.71）**
    —— ★贴图**自带优先**，加载不出来退回客户端 `Interface\WorldMap\…`；两份都加载不出来 ⇒ **这张图不接管**（绝不画空白图）；判据见 `tools/SimpleMap.lua` 的 `MDQ.srcKey`/`MDQ.probeTrust`（**探针必须带负对照**：本客户端对不存在的文件也报尺寸）
  → **`addons/`（四个独立子插件，各自 toc / 存档 / 文档）**：`EH_Bag\`（**整合背包**，与 OneBag 逐项对齐：连续排布 · 品质辉光 · 一键整理 · 跨角色总览 · 冷却倒计时 · 金币金钱行 · 资源绝对自包含；`EH_Bag.toc` 列 `EH_Bag.lua` + `EH_BagSort.lua`）· `EH_DebugBox\`（图层调试，`/edb`）· `EH_Damage\`（增强伤害显示 / 浮动战斗信息，`/edmg`：19 项显示勾选 · 11 种滚动方向 · 4 种缓出曲线 · 6 档分档字体对象 · 技能图标 · 编辑模式模拟战斗）· `EH_DPS\`（**队伍级伤害统计**，`/edps`：全部数据来自战斗日志文本解析 —— **9 个视图全部按玩家出条目**（伤害/DPS/治疗/HPS/承受/受疗/能量/击杀/施放）· 职业染色 · 点条目下钻该玩家技能分解 · 双段 + 各自活跃时间 EDPS · 报告限频 · 窗口拖拽/改尺寸/Ctrl+滚轮缩放/右键视图菜单/[设] 配置）
    ★**子插件与主插件是两套 LoadAddOn、两套 SavedVariables**（`EH_BAG_CFG` / `EH_DEBUGBOX_CFG` / `EH_DAMAGE_CFG` / `EH_DPS_CFG`，宿主绝不碰）；子插件**不得**读写 `EVAL_HELP_CONFIG`/`EVAL_HELP_CHAR`（常驻闸门 `tmp/mem_sep_probe.js`，命中必须 0 处）
    ★`node sync_game.js` 把 `addons\<名>\` 拷到插件**同级**游戏目录（勾选才 `EnableAddOn` + `/reload` 载入）；**release 时各自独立打包两份**（`<名>-v<子版本>.zip` + 固定名 `<名>.zip`，内容逐字节相同）一起传到同一个 Release
    ★文档各自成套：`README.md`（面向使用者）· `CLAUDE.md`（**子插件自己的记忆体**，与宿主记忆分文件）· `CHANGELOG.md`（`0.3.x` ↔ 宿主 `1.75.y` 同轮升级）；宿主只留指针，**绝不复制子插件正文**
  跨文件共享走全局桥：Core 导出 EVAL_SAY/EVAL_LOGLINE/EVAL_UIOFFSCREEN 等，Engine 导出 EVAL_WSLOTS/EVAL_WICON/EVAL_GROUPS_OK 等，
  UI 层文件顶部别名块本地化；
  ★**新增 .lua 模块要同时改两处**：`EvalHelp.toc`（顺序 = 载入顺序，共用件放前面）+ **发布包清单**（参考卷打包脚本的 Copy-Item 行；子目录模块尤其容易漏）。
  ★**新增 `examples/*.lua` 只需一处**：`EvalHelp.toc`（它们没有顶层 local）。
  ★**改动后只跑一个命令**：`node luacheck.js`（fengari 逐文件真解析 —— **唯一的语法闸门**）。
  ★**另外三个按需手动跑的静态助手**（都不是自动闸门，但改到相区域必须跑一遍）：
  `node scan_dangling.js`（**第二段·全仓**：找出「被调用、但全项目没有定义」的名字 —— 客户端 API 白名单 + 一趟扫的 Lua 清洗器 + **区分「无守卫＝真机必崩」与「有守卫＝静默死」**；1.75.42 新增，起因 = 1.75.34 孤儿清理误删 7 个定义）·
  `node probe_localorder.js`（文件内 local「先用后声明」）· `node scan_dangling.js` 第一段（`addons/` 子插件的可疑未定义调用）。
  ★★**本项目没有测试**（用户 2026-09-26 定案：「删除tests/下的文件.也不需要测试」）：`tests/`、`test_assert.lua`、`test_engine.js`、`check.js`、`mutate.js` 已全部删除
  ⇒ 行为/接线/渲染/存档这类**静默失效没有自动判据兜底**，改完请**自查调用点**并**进游戏实测**。
-  SavedVariables：`EVAL_HELP_CONFIG`（落盘于 `%LOCALAPPDATA%\Azeroth\Saved\Account\<账号>\SavedVariables\EvalHelp.lua`，小退/重载时写入；★**账号目录不固定**，读存档要取「所有账号里 mtime 最新那份」）。
  子插件各有自己的存档文件（`addons\EH_Bag` → `EH_BAG_CFG`、`addons\EH_DebugBox` → `EH_DEBUGBOX_CFG`、`addons\EH_Damage` → `EH_DAMAGE_CFG`、`addons\EH_DPS` → `EH_DPS_CFG`）—— **两套 LoadAddOn、两套记忆体，绝不互碰**（宿主代码里出现子插件存档键 = 0 处，常驻闸门 `tmp/mem_sep_probe.js`）。

## ⚠️ 提交前必做

```
node luacheck.js     # fengari 逐文件全量 Lua 解析；SYNTAX OK 才算完（报错带文件名 + 行号）
```
★**测试已于 2026-09-26 全部删除**（用户定案「删除tests/下的文件.也不需要测试」）——原先的 `node test_engine.js`（打桩加载整棵树 + 断言 + 源码检查）**不再存在**；
所以除语法外的失效（接线漏接、渲染不对、存档键写错、清单过时）**只能靠自查 + 真机实测**，请务必在 `/reload` 后按改动点自己走一遍。

**Lua 整文件编译**：一处语法错误 = 整个插件静默不载入，游戏日志看不到。曾有两处 `end)` 多括号导致三个版本白发。
**版本号有三处、必须一致**：`EvalHelp.lua` 的 `local VERSION` + `EvalHelp.toc` 的 `## Version` + `tools/WorldFog.lua` 的 `MDQ.BUILD`（后者 = 存档里 `worldFogCfg.buildTag`，是「客户端跑的是哪一份代码」的唯一记号）。原先的 `VERSION CHECK` 已随 `tests/` 删除，**判据已搬进 `tmp/swm_harness.js` 的 AUDIT**（三处一致），别裸奔。
★文件头**不再写版本号**：旧写法（`-- EvalHelp 1.70.44`）实际漂移了十几个版本都没人发现，因为源码检查只比对那两处。

## 🚀 发布流程（用户定，**9 步**；每次发版必做）

> ★★★**出包源目录 = 仓库、不是 AddOns 那份**（1.75.35 实测：sync 口径不含 `*.md` ⇒ 从 AddOns 出包会把**旧 README/CHANGELOG** 打进包；出包后要开箱验文档含本版小节，不只是数条目数）。

> ★★**「release」= 下面 9 步全做完**，不是只 `git push`（用户 1.72.0 明确）。

1. **统计里程碑**：从「上一次 release 版本」到最新，**逐版本列里程碑**（发布了什么、跨了哪些版本）。
   ★产物有两个去处：**① README 的「里程碑」板块**（面向用户、只讲这一批的故事）**② 注解 tag 的说明**（Release 页正文）；
2. **项目说明更新**：`README.md` / `README_en.md` / `README_ru.md` —— ★版本记录**只保留最近 10 个**；
   ★★**板块顺序**：`## 🏁 里程碑` 在 `## 更新日志` **上面**（更新日志在里程碑下面），顺序由 `MILESTONE CHECK` 守着；
3. **扫描旧版信息**：全仓库排查版本号、文件结构、功能清单、过时描述（新窗口 / 新 Tab / 新条件要补上），逐一清理；
4. **更新对应板块**：按「上次 release → 最新」的信息更新 README 的功能·用法板块、DEVELOPMENT 的架构板块等；
   ★★★**工具箱说明必须逐行罗列**（用户 1.75.59d）：三语 README 的「工具箱」= `Toolbox.lua` 的 `tbModel()` 行清单镜像
     （组标题 + 行名 + 行数/组数；概括词不算）；★`preview/` 文件集合必须 == 三语引用集合（删图要连说明一起删，否则是死图）；
   ★★★**图片同步（用户 1.75.35 定）**：按 `./preview` 里**最新那批图**更新对应说明文件 —— 最新图必须都进三语 README 的「界面预览」板块
     （判据 = `preview/` 文件名集合 ⊆ 三语引用集合）、说明文字必须与当前功能一致、**图比功能旧就点名让用户重拍**（不许旧图配新文案）；
   ★★**README 的 `## 🏁 里程碑` 必须同步**：标题范围改成最新版本；★**整个板块只留 10 条、每条一行**
     （用户定：「控制在 **10 个点、10 行文字以内**」，**不再分 `###` 小节**）——最新的写最前面，超出就删最旧的；
     每条 = `- **emoji 主题**（版本范围）：说清做了什么 + 一句关键判据/教训`；
     ★★★**每条必须以 `- ` 开头（列表项）**：连续普通段落行会被 Markdown **合并成一大段**（1.72.0 实事故，
     用户在 GitHub 上看到「排版混乱」）；`MILESTONE CHECK` 第⑤条守着（去掉任一条的 `- ` 就 FAIL）；
   ★★★**是「归纳」不是「罗列」**（用户定）：细节留给 `CHANGELOG.md`，板块里每条只留一句话；
   ★**三语言同步**：zh / en / ru 都有该板块（1.72.0 起），**不许只补一个语种**（会孤悬）——
   源码检查 `MILESTONE CHECK` 守着**这三点 + 板块顺序**（里程碑必须在更新日志之上）；
5. **版本记录**：`CHANGELOG.md` 写 `## 🎯 vX.Y.Z — 主题` 详情小节（**完整记录，不删旧条目**）；
   `EvalHelp.lua` 的 `local VERSION` 与 `EvalHelp.toc` 的 `## Version` 同步；
6. **审计记忆体**：`CLAUDE.md` —— 版本要点**汇总统计后放到文档末尾**；★头部只保留**比较新的记忆注意事项（最多 20 个版本）**，
   ★不许再把一堆版本记录堆到记忆体头部（那会让整份记忆体超预算、被截断掉文末的项目现状）。
      ★★★并且**做一次「清账」= 发布流程里的固定一步**（用户定：「**清理 Claude.md 版本流水账.提取有价值的最终解决方案的相关信息保留**」+「**清理流程账记录.加入操作流程**」）：
   **三份一起清**（宿主 `CLAUDE.md` · `CLAUDE_REFERENCE.md` 正文 · **每个子插件自己的 `CLAUDE.md`**）→
   先 `Copy-Item` 备份到 `tmp\CLAUDE.before_cleanup_<版本>.md`（★只复制、不要在 PS 里读进来再写）并记字节/行数 →
   只留「**最终方案 + 判据 + 锚点 + 欠账清单**」，删「报障经过 / 时间线 / 逐版本流水 / 已删测试的组号与变异号 / **流程账**（怎么查的 · 临时脚本名 · 中途待办）」→
   细节搬 `CHANGELOG.md` 与参考卷附录 R，长条目拆成多条独立判据；
   ★判据 = **`node tmp/mem_cleanup_diff.js <before.md> <after.md>` 报「❌ 0」且 `exit 0`**（逐个查消失的硬锚点是「已搬迁 / 可删 / 丢锚点」）
   + 人眼一条「没有一条只写当时发生了什么、不写以后怎么做」；交付说明里报 before→after 字节数与删掉的类别。
7. **提交 + 打「附注」标签**：`git tag -a vX.Y.Z -F <说明文件>` —— ★**必须 `-a`**（轻量标签没有说明，Release 页要用它当正文）；
   ★说明文件**不能用 PowerShell `>` 重定向写**（那是 UTF-16LE → 标签说明整段乱码），要用 UTF-8 写并**回读复核**；
8. **推送（分支 + 标签都要推）**：`git push origin master && git push github master`，再 `git push origin --tags && git push github --tags`；
   ★★**两个库一律走 SSH（`git@xxx`）+ 本机默认密钥**（用户定）：不用 HTTPS/token、不用 `-i` 另指密钥；
   推送前先 `git remote -v` 确认两个远端都是 `git@` 形式（`origin`=gitee、`github`=github），可用 `ssh -T` 双端验签；
9. **出发布包 + 建 Release 页**：打包 `EvalHelp-vX.Y.Z.zip`（放 `Interface/AddOns/` 下，顶层一个 `EvalHelp\`，内容 = `.toc` 实际清单，
   ★装完核对条目数）→ ★★**再复制一份不带版本号的 `EvalHelp.zip`**（同一目录、**内容逐字节相同**）——
   用户定：「**9 出包还要对应复制一个没有版本号的包 EvalHelp.zip**」＝ 固定名字的下载口 → 在 gitee / github 网页建 Release
   （**Release 页与附件现在由 AI 自动建/自动传** —— 见参考卷发布段「Release 页 = 现在由 AI 自动建」；★★**子插件也各自独立打包两份**（`<名>-v<子版本>.zip` + 固定名 `<名>.zip`，内容逐字节相同），与主插件那两份**一起传到同一个 Release**（用户 2026-10-05 定：「release 子插件要独立压缩包打包并且配置独立无版本号的压缩包.一同上传到对应插件版本发布内」；口径见参考卷「子插件独立打包」）。

> ★发布前必跑：`node luacheck.js`（`SYNTAX OK`）—— ★测试框架已于 2026-09-26 删除，**再没有第二道闸门**；提交用 `git add <明确路径>`（**不要** `git add -A`）。
> ★推送：分支 `master`；远端 `origin`=gitee、`github`=github（用默认密钥 `~/.ssh/id_rsa`，别指定 `gitee_id_rsa`）。

## 架构地图（`EvalHelp.lua` 段落顺序）

| 段 | 内容 |
|---|---|
| 状态模块 | `EVAL_HELP_STATE` / `UPDATE_STATE()`：所有判定数据一次刷新、各处只读（含 playerBuffs/targetDebuffs 纹理集合、castLog 释放日志） |
| 一键模块 | `WAR_SKILLS` 技能白名单、`wslots` 动作条扫描（`EVAL_GO_RESCAN`）、`wready/wuse/wlog` |
| 规则引擎 | `condOne/groupsOK/EVAL_RULE_RUN`（组内 & 组间 |，带 trace）；`EVAL_PARSE_CONDS` 中文+英文条件解析；兼容旧 when={} 格式 |
| 宏入口 | `EVAL_GO(profSel)`：0/不传=激活方案，1-4/方案名=直触；`EVAL_GO1~4` 便捷函数 |
| 战斗信息UI | `EVAL_HELP_UI_BUILD/TICK`：标题=玩家名（取不到退回语言包文案）；两大区块（**战斗区**=血/能量/连击/目标条+读条+挥击条+状态行，**方案区**=方案切换行+技能图标带）各有独立子开关 `cfg.ui.subCombat/subScheme`（1.71.12，nil=开，关=整块不画、布局随之前移、帧高跟着变；tick 只认 BUILD 时定下的 `ui.combatOn/schemeOn`，普攻判定不随区块跳过） |
| 状态信息UI | `EVAL_HELP_ST_*`：状态变量总览+最近释放明细 |
| 配置窗 | `cfgBuild`：**七个 Tab** = 全局 · 一键宏设置 · 工具箱 · 任务线 & 装备 · 图标库 · 抓宠帮手 · 子插件；方案栏/技能列表/[添加技能]/[导入导出] |
| 技能编辑窗 | `EVAL_HELP_SE_*`：条件逐行配置（1.75.28 起规则存**线性 `expr`**：项内 `&` / 项内或 `｜` / 项间与 `&&` / 段间或 `｜｜`，解析 `EVAL_PARSE_CONDS`、回写 `EVAL_EXPR_STR`；旧 `groups` 存档现场推导、编辑保存才落新格式）· 条件行 ▲/▼ 调序（1.75.79）· 「关系运算符说明」= 一份说明三处共用（1.75.80）· 底行三颗按钮同一条带（1.75.81） |
| 通用 UI 件 | `EVAL_DD_OPEN` 下拉面板 / **`EVAL_PM_*` 方案管理弹窗**（1.71.24：改名+快捷键合并成一个窗，**旧的 `EVAL_HELP_RP_*` 重命名窗与绑定窗都已删除、不留别名**；回声行范式） / `uiSolid/uiText/cfgCheck/cfgSlider` / `EVAL_HELP_MB_*` 小地图图标钮（1.71.13：按钮=宏图标本身 26×26 无边框，`EVAL_HELP_MB_PICKICON` 纯函数按名字优先级挑图标，挑不到退回「金框 + EH」兜底） |
| 方案快捷键派发 | `EVAL_BIND_*`（1.71.22 定案）：命令名 = 客户端自带的 `ACTIONBUTTON<n>`，插件**接管全局 `ActionButtonDown/Up`** 把格号翻成 `EVAL_GO(方案号)`；`EVAL_BIND_INSTALL/UNINSTALL`、`EVAL_BIND_SLOT_MAP`、`EVAL_BIND_MODIFIER_STOLEN`（组合键守卫）、`EVAL_BIND_TEXT_BLOCKS`。★`Bindings.xml` 路线已在 1.71.22 被对照实验证伪并删除 |
| IO | `EVAL_PROFILE_TO_TEXT/FROM_TEXT` md 文本互转；`EVAL_HELP_IO_*` 窗口（FontString 保底预览区） |
| 案例模版窗 | `EVAL_HELP_TPL_*`：读 `examples/*.lua` 的数据渲染成**分组分两列 + 组内同行自动换行**（版式由纯函数 `tplTwoColPlan` 算），点击即导入 |
| 工具箱 Tab3 | `Toolbox.lua`：`EVAL_TB_BUILD(root, page, refreshes)`；行清单 = `tbModel()`（**37 行 / 8 组**：UI 工具 · 商人助手 · 队伍/社交 · 任务 · 猎人助手 · 消耗品助手 · 骑乘助手 · 稀有提醒），三语 README 的「工具箱」是它的镜像；动作全部走限频队列（0.3s/笔 + 逐笔核对）；模块行由 `EVAL_TB_MOD_ROWS[mod]` 自登记 ⇒ 与 toc 顺序无关 |
| 任务线 & 装备 Tab4 | `DataSearch.lua`：`EVAL_DS_BUILD`；逻辑层 `EVAL_DS_SEARCH/DETAIL/SHOWMAP` 与 UI 分离、可 node 直测；**任务线视图 + 装备视图**（装备优先 → 反查任务线）与四类检索同页；地图标注层硬依赖 UnrealQuest |
| 方案分享 | `Share.lua`：公会 / 队伍 / 说 三频道分片直发直收（`SH_CHANS` 白名单是唯一真值）+ 接收规则（只留最新一笔 + 四道上限）；1.74.0 起含**品阶封皮**（`[品阶秘籍·名]` 可点链接 + 弹窗确认）+ **品阶评分**（`SH_SEAL_TIERS` 单一来源）+ **头衔抽卡**（`EVAL_TITLE_*`）+ 彩蛋「创世者亲临」+ **角色扮演反应**（`SH_FUN_IMP/IGN` 嵌套表 + `shSendReaction` 按来源频道） |
| 图标库 Tab5 | `IconBrowser.lua`：读客户端内置宏图标表，按前缀分组 / tooltip 显示路径 / **先过滤再分页** |

## 本客户端实测配方（踩坑沉淀，新增 UI 必守）

1. 拖动柄必须 `CreateFrame("Button")` + SetFrameLevel(父+10) + EnableMouse + RegisterForClicks("LeftButtonUp") + RegisterForDrag("LeftButton") + warm-up 两步；
2. 纯色纹理只有 `Interface\Buttons\WHITE8X8` + SetVertexColor 可靠；
3. **无原生 Slider/下拉**：滑条=轨道+拇指自绘；下拉=全局件 `EVAL_DD_OPEN(锚点,选项表,回调)`（宿主窗 OnHide 里调 `EVAL_DD_HIDE()`）；
4. **strata 层级**：配置窗是 DIALOG；其上方弹窗必须同 DIALOG + SetFrameLevel(90~120)，下拉面板 level 250；
5. 显隐走显式控件清单（不靠父子传播）；容器 EnableMouse(false)，交互件单独开；
6. 位置记忆除以 GetEffectiveScale；每个记忆位置窗口都要 uiOffscreen 越界回归（含顶边剪裁检测）；
7. 禁用 SetScale（点击框漂移）：缩放=按系数几何重建；字体链 FZLBJW→FRIZQT→ARIALN 或 SetFontObject(GameFontHighlightSmall…) 全程 pcall；
8. **EditBox 在本客户端疑似不渲染**：文本展示一律给 FontString 保底；单行输入用「回声行」范式（OnTextChanged 镜像到 FontString）；
9. 小地图按钮父级 UIParent；悬停 GameTooltip 走 OnEnter/OnLeave，不用 SetHighlightTexture。

## 能力边界（本客户端没有）

- 受保护函数（CastSpellByName 等）插件不可调 → 施法一律 `UseAction(slot)` + pcall；技能必须拖上动作条；
- 谓词返回 true/false/nil，宽松真值判断，绝不 ==1；
- 无 UnitCastingInfo/UnitChannelInfo（打断条件做不了）；无 SuperWoW（距离/挥击计时做不了）→ 猛击用 Alt 代替出手时机。

## 扩展新职业

1. 在 `WAR_SKILLS` 旁加对应职业技能表（或泛化成按职业选表）；
2. 条件目录 `SE_TYPES`/解析器 `EVAL_PARSE_ONE` 加职业专属词（如 连击点/法力%）；
3. 规则引擎、方案系统、UI 全部职业无关，不用动。

## 参考实现

- UnrealQuest `Compatibility/ClientAPI.lua`（本客户端实测配方库）
- Cat（TurtleWoW 插件，状态变量设计）
- OneJudge（最初参考）
