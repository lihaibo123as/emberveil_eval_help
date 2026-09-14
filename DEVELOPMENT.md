# DEVELOPMENT —— EVAL_HELP 开发指南

> 面向想参与开发的第三方（人类或 AI）。读完这份 + `CLAUDE.md`（AI 记忆体）即可上手。

## 项目概况

- EmberVeil 私服客户端（1.12.1 规则 / UE 引擎 / **Lua 5.1**）的 FrameXML 插件；
- 多文件架构（1.39.0 起，toc 顺序 Locales→**Core**→**Engine**→**EvalHelp**）：`Core.lua`（输出/i18n/状态采集+UPDATE_STATE/UI 越界助手）· `Engine.lua`（一键宏引擎：扫描/五分类/规则引擎/解析/免疫/光环/距离）· `EvalHelp.lua`（全部 UI 窗口+斜杠+初始化）；跨文件共享走全局桥：Core 导出 EVAL_SAY/EVAL_LOGLINE/EVAL_UIOFFSCREEN 等，Engine 导出 EVAL_WSLOTS/EVAL_WICON/EVAL_GROUPS_OK 等，UI 层文件顶部别名块本地化；**改动后务必 luacheck 三个 .lua + test_engine 全跑**
-  SavedVariables：`EVAL_HELP_CONFIG`（落盘于 `%LOCALAPPDATA%\Azeroth\Saved\Account\<账号>\SavedVariables\EVAL_HELP.lua`，小退/重载时写入）。

## ⚠️ 提交前必做

```
node luacheck.js     # fengari 全量 Lua 解析；SYNTAX OK 才算完（报错带行号）
node test_engine.js  # 逻辑冒烟测试：打桩 WoW API 加载整个插件，跑 test_assert.lua 断言；ALL TESTS PASS 才算完
```

**Lua 整文件编译**：一处语法错误 = 整个插件静默不载入，游戏日志看不到。曾有两处 `end)` 多括号导致三个版本白发。
版本号三处同步：lua 头注释 + `local VERSION` + toc `## Version`。

## 架构地图（`EvalHelp.lua` 段落顺序）

| 段 | 内容 |
|---|---|
| 状态模块 | `EVAL_HELP_STATE` / `UPDATE_STATE()`：所有判定数据一次刷新、各处只读（含 playerBuffs/targetDebuffs 纹理集合、castLog 释放日志） |
| 一键模块 | `WAR_SKILLS` 技能白名单、`wslots` 动作条扫描（`EVAL_GO_RESCAN`）、`wready/wuse/wlog` |
| 规则引擎 | `condOne/groupsOK/EVAL_RULE_RUN`（组内 & 组间 |，带 trace）；`EVAL_PARSE_CONDS` 中文+英文条件解析；兼容旧 when={} 格式 |
| 宏入口 | `EVAL_GO(profSel)`：0/不传=激活方案，1-4/方案名=直触；`EVAL_GO1~4` 便捷函数 |
| 战斗信息UI | `EVAL_HELP_UI_BUILD/TICK`：三条状态条+技能图标行+方案行+方案技能行 |
| 状态信息UI | `EVAL_HELP_ST_*`：状态变量总览+最近释放明细 |
| 配置窗 | `cfgBuild`：Tab{全局, 一键宏设置}；方案栏/技能列表/[添加技能]/[导入导出] |
| 技能编辑窗 | `EVAL_HELP_SE_*`：条件逐行配置（seGroupsToLinear/seLinearToGroups 线性↔分组） |
| 通用 UI 件 | `EVAL_DD_OPEN` 下拉面板 / `EVAL_HELP_RP_*` 输入弹窗（回声行范式） / `uiSolid/uiText/cfgCheck/cfgSlider` |
| IO | `EVAL_PROFILE_TO_TEXT/FROM_TEXT` md 文本互转；`EVAL_HELP_IO_*` 窗口（FontString 保底预览区） |

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
