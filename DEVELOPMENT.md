# DEVELOPMENT —— EVAL_HELP 开发指南

> 面向想参与开发的第三方（人类或 AI）。读完这份 + `CLAUDE.md`（AI 记忆体）即可上手。

## 项目概况

- EmberVeil 私服客户端（1.12.1 规则 / UE 引擎 / **Lua 5.1**）的 FrameXML 插件；
- **多文件架构**（1.39.0 起模块化；**真实载入顺序 = `EvalHelp.toc` 的顺序，以 .toc 为唯一真值**）：
  `Locales/{zhCN,enUS,ruRU}` → `Core.lua`（输出/i18n/状态采集+UPDATE_STATE/UI 越界助手）→ `Engine.lua`（一键宏引擎：扫描/五分类/规则引擎/解析/免疫/光环/距离/队伍扫描）
  → `EvalHelp.lua`（全部 UI 窗口+斜杠+初始化）→ `examples/*.lua`（11 个案例模版数据文件）→ `Toolbox.lua`（Tab3 工具箱）
  → `DataSearch.lua`（Tab4 数据检索）→ `Share.lua`（方案分享）→ `IconBrowser.lua`（Tab5 图标库）。
  跨文件共享走全局桥：Core 导出 EVAL_SAY/EVAL_LOGLINE/EVAL_UIOFFSCREEN 等，Engine 导出 EVAL_WSLOTS/EVAL_WICON/EVAL_GROUPS_OK 等，
  UI 层文件顶部别名块本地化；
  ★**新增 .lua 模块要同时改三处**：`EvalHelp.toc`、`test_engine.js` 的装载数组、`DECL ORDER CHECK` 的文件清单；
  ★**新增 `examples/*.lua` 只需两处**：`EvalHelp.toc` + `test_engine.js` 装载数组（它们没有顶层 local）。
  ★**改动后两个命令全跑**：`node luacheck.js`（只做 EvalHelp.lua 的整文件语法编译）+ `node test_engine.js`
  （打桩加载**整棵树**并跑断言 —— 其它文件的语法错误也在这一步暴露）。
-  SavedVariables：`EVAL_HELP_CONFIG`（落盘于 `%LOCALAPPDATA%\Azeroth\Saved\Account\<账号>\SavedVariables\EVAL_HELP.lua`，小退/重载时写入）。

## ⚠️ 提交前必做

```
node luacheck.js     # fengari 全量 Lua 解析；SYNTAX OK 才算完（报错带行号）
node test_engine.js  # 逻辑冒烟测试：打桩 WoW API 加载整个插件，跑 test_assert.lua 断言；ALL TESTS PASS 才算完
```

**Lua 整文件编译**：一处语法错误 = 整个插件静默不载入，游戏日志看不到。曾有两处 `end)` 多括号导致三个版本白发。
**版本号只有两处**：`EvalHelp.lua` 的 `local VERSION` + `EvalHelp.toc` 的 `## Version`（`VERSION CHECK` 守着两侧一致）。
★文件头**不再写版本号**：旧写法（`-- EvalHelp 1.70.44`）实际漂移了十几个版本都没人发现，因为源码检查只比对那两处。

## 🚀 发布流程（用户定，**9 步**；每次发版必做）

> ★★**「release」= 下面 9 步全做完**，不是只 `git push`（用户 1.72.0 明确）。

1. **统计里程碑**：从「上一次 release 版本」到最新，**逐版本列里程碑**（发布了什么、跨了哪些版本）。
   ★产物有两个去处：**① README 的「里程碑」板块**（面向用户、只讲这一批的故事）**② 注解 tag 的说明**（Release 页正文）；
2. **项目说明更新**：`README.md` / `README_en.md` / `README_ru.md` —— ★版本记录**只保留最近 10 个**；
3. **扫描旧版信息**：全仓库排查版本号、文件结构、功能清单、过时描述（新窗口 / 新 Tab / 新条件要补上），逐一清理；
4. **更新对应板块**：按「上次 release → 最新」的信息更新 README 的功能·用法板块、DEVELOPMENT 的架构板块等；
   ★★**README 的 `## 🏁 里程碑` 必须同步**：标题范围改成最新版本，并在**最前面**插入本次的 `### <上次> → <最新>` 小节
     （**新版本在前**，与既有小节顺序一致）；每条 = `**emoji 主题**（版本范围）：说清做了什么 + 关键判据/教训`；
   ★★★**是「归纳」不是「罗列」**（用户定）：**每个小节控制在 10 条以内**、每条一行，细节留给 `CHANGELOG.md`；
   ★**三语言同步**：zh / en / ru 都有该板块（1.72.0 起），**不许只补一个语种**（会孤悬）—— 源码检查 `MILESTONE CHECK` 守着这三点；
5. **版本记录**：`CHANGELOG.md` 写 `## 🎯 vX.Y.Z — 主题` 详情小节（**完整记录，不删旧条目**）；
   `EvalHelp.lua` 的 `local VERSION` 与 `EvalHelp.toc` 的 `## Version` 同步；
6. **审计记忆体**：`CLAUDE.md` —— 版本要点**汇总统计后放到文档末尾**；★头部只保留**比较新的记忆注意事项（最多 20 个版本）**，
   ★不许再把一堆版本记录堆到记忆体头部（那会让整份记忆体超预算、被截断掉文末的项目现状）。
7. **提交 + 打「附注」标签**：`git tag -a vX.Y.Z -F <说明文件>` —— ★**必须 `-a`**（轻量标签没有说明，Release 页要用它当正文）；
   ★说明文件**不能用 PowerShell `>` 重定向写**（那是 UTF-16LE → 标签说明整段乱码），要用 UTF-8 写并**回读复核**；
8. **推送（分支 + 标签都要推）**：`git push origin master && git push github master`，再 `git push origin --tags && git push github --tags`；
9. **出发布包 + 建 Release 页**：打包 `EvalHelp-vX.Y.Z.zip`（放 `Interface/AddOns/` 下，顶层一个 `EvalHelp\`，内容 = `.toc` 实际清单，
   ★装完核对条目数）→ 在 gitee / github 网页建 Release（**需要 API token，AI 做不了** → 如实告知用户去建，并给全 URL/标题/说明/附件）。

> ★发布前必跑：`node luacheck.js` + `node test_engine.js` 双绿；提交用 `git add <明确路径>`（**不要** `git add -A`）。
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
| 配置窗 | `cfgBuild`：Tab{全局, 一键宏设置}；方案栏/技能列表/[添加技能]/[导入导出] |
| 技能编辑窗 | `EVAL_HELP_SE_*`：条件逐行配置（seGroupsToLinear/seLinearToGroups 线性↔分组） |
| 通用 UI 件 | `EVAL_DD_OPEN` 下拉面板 / **`EVAL_PM_*` 方案管理弹窗**（1.71.24：改名+快捷键合并成一个窗，**旧的 `EVAL_HELP_RP_*` 重命名窗与绑定窗都已删除、不留别名**；回声行范式） / `uiSolid/uiText/cfgCheck/cfgSlider` / `EVAL_HELP_MB_*` 小地图图标钮（1.71.13：按钮=宏图标本身 26×26 无边框，`EVAL_HELP_MB_PICKICON` 纯函数按名字优先级挑图标，挑不到退回「金框 + EH」兜底） |
| 方案快捷键派发 | `EVAL_BIND_*`（1.71.22 定案）：命令名 = 客户端自带的 `ACTIONBUTTON<n>`，插件**接管全局 `ActionButtonDown/Up`** 把格号翻成 `EVAL_GO(方案号)`；`EVAL_BIND_INSTALL/UNINSTALL`、`EVAL_BIND_SLOT_MAP`、`EVAL_BIND_MODIFIER_STOLEN`（组合键守卫）、`EVAL_BIND_TEXT_BLOCKS`。★`Bindings.xml` 路线已在 1.71.22 被对照实验证伪并删除 |
| IO | `EVAL_PROFILE_TO_TEXT/FROM_TEXT` md 文本互转；`EVAL_HELP_IO_*` 窗口（FontString 保底预览区） |
| 案例模版窗 | `EVAL_HELP_TPL_*`：读 `examples/*.lua` 的数据渲染成**分组分两列 + 组内同行自动换行**（版式由纯函数 `tplTwoColPlan` 算），点击即导入 |
| 工具箱 Tab3 | `Toolbox.lua`：`EVAL_TB_BUILD(root, page, refreshes)`；商人 / 队伍社交 / 任务三组，动作全部走限频队列（0.3s/笔 + 逐笔核对） |
| 数据检索 Tab4 | `DataSearch.lua`：`EVAL_DS_BUILD`；逻辑层 `EVAL_DS_SEARCH/DETAIL/SHOWMAP` 与 UI 分离、可 node 直测；地图标注层硬依赖 UnrealQuest |
| 方案分享 | `Share.lua`：公会 / 队伍 / 说 三频道分片直发直收（`SH_CHANS` 白名单是唯一真值）+ 接收规则（只留最新一笔 + 四道上限） |
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
