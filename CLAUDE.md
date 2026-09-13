# EVAL_HELP 插件项目记忆（EmberVeil 职业操作工具）

## 项目位置与现状
- 插件目录：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EVAL_HELP\`
- 当前版本：**1.20.3**（每次改动递增版本号：lua 头注释 + `local VERSION` + toc `## Version` 三处同步）
- 文件：`EVAL_HELP.lua`（主文件 ~2900 行，单文件架构）、`EVAL_HELP.toc`、`README.md`、`example\zs_wq.md`（武器战初始方案）
- 游戏：EmberVeil（1.12.1 客户端 UE 版，Lua 5.1）；插件名 EVAL_HELP，战士一键宏函数 **`EVAL_GO()`**（1.16.0 由 EVAL_ZS_WQ 改名；参数 0/不传=激活方案，1-4 或方案名=直触），斜杠 `/eh`

## ⚠️ 最重要教训：改完必须跑语法检查
- **Lua 整文件编译**：任何一处语法错误 → 整个插件无法载入，且 UE 日志里看不到（%LOCALAPPDATA%\Azeroth\Saved\Logs 是空的）
- 1.9.0 曾有两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 1.9.0~1.11.0 全部功能实际未生效
- 旧 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助
- **每次改完 .lua 必跑**：`node luacheck.js`（工作区根目录，fengari 真实 Lua 解析，报错带行号；显示 SYNTAX OK 才算完）
- fengari 已装在工作区 node_modules（npm 走代理 127.0.0.1:10809）

## 本客户端已实测的 UI 配方（UnrealQuest ClientAPI.lua 验证）
1. **拖动柄必须用 Button**（Frame 的 OnDragStart 不触发）；SetFrameLevel(父+10) 抬高（用 strata 抬高是记录在案的失败做法）；EnableMouse + RegisterForClicks("LeftButtonUp") + RegisterForDrag("LeftButton")；StartMoving 前 warm-up 两步（StartMoving→StopMovingOrSizing→StartMoving）
8. **strata 层级陷阱**：配置窗是 DIALOG；其上方弹窗（技能编辑窗/导入导出窗）必须同 DIALOG + SetFrameLevel(90~100)，MEDIUM/HIGH 都会被 DIALOG 盖住（1.11.2 实测修复）；弹窗也要 uiOffscreen 越界回归
2. **纯色纹理**只有 `Interface\Buttons\WHITE8X8` + SetVertexColor 可靠
3. **无原生 Slider / 无下拉控件**：滑条=自制轨道+拇指；**下拉一律用全局件 EVAL_DD_OPEN(锚点,选项表,回调)**（1.19.0 由 SE 专用泛化，UIParent+DIALOG+level250，多列 12 行/列，贴屏底自动上翻；宿主窗口 OnHide 里调 EVAL_DD_HIDE()）；1.19.0 起插件内所有 [<][>] 循环器已全部改下拉
4. **可见性契约**：显隐走显式控件清单 Show/Hide，不靠父子传播（容器 EnableMouse(false)，交互件单独 EnableMouse(true)）
5. **位置记忆**：GetCenter/GetLeft 含缩放，存取要除 GetEffectiveScale；每个记忆位置的窗口都要 uiOffscreen 越界回归
6. **禁用 SetScale**（点击框漂移），缩放=按 z 系数几何重建；字体链 FZLBJW→FRIZQT→ARIALN 全程 pcall
7. 小地图按钮父级必须是 UIParent（不能是 Minimap）；悬停用 OnEnter/OnLeave + GameTooltip，不用 SetHighlightTexture

## 架构要点（改代码前先读这段）
- **状态表 st（EVAL_HELP_STATE）**：所有判定数据走 UPDATE_STATE() 一次刷新、各处只读（Cat 思路，不重复调 API）；含 playerBuffs/targetDebuffs 纹理集合、castLog 释放日志（最近 5 条带条件 trace）
- **规则引擎**：规则 = { skill, enabled, groups }；groups = 组内 & 、组间 | ；EVAL_RULE_RUN 顺序执行第一条全过的；兼容旧 when={} 格式；condOne/groupsOK/EVAL_PARSE_CONDS/EVAL_COND_STR/EVAL_GROUP_STR 是核心
- **方案数据**：cfg.war.profiles（最多 4 个）+ activeProfile；EVAL_WAR_ENSURE_PROFILES 做缺省迁移；SavedVariables 自动持久化
- **方案切换四入口联动**：配置窗侧栏按钮 / 激活方案 [<][>] 选择器 / 战斗信息UI 方案行 / Shift+按宏（Shift 已被切换占用，方案条件里别用 Shift，用 Alt/Ctrl）
- **文本格式**（导入导出/ zs_wq.md）：`# 方案: 名` + `- 技能 | 条件` 行；技能名前 `!` = 停用；解析容忍 md 杂物行
- **函数作用域陷阱**：warCfg/c() 是配置段 local，战斗信息UI 段在其之前 → UI 段用 uiWarCfg()（直接走 EVAL_HELP_CONFIG 全局）；wslots/WAR_SKILLS 是战士段 local，配置段在其后可用
- 受保护函数（CastSpellByName 等）插件**不能调**，施法一律 UseAction(slot) + pcall；谓词返回 true/false/nil，绝不 ==1
- 本客户端无 UnitCastingInfo（打断条件做不了）、无 SuperWoW（距离/挥击计时做不了）
- **EditBox 疑似不渲染**（1.15.1 用户报告 IO 窗口空白：pcall 全"成功"但什么都不可见）→ IO 窗加 FontString 保底预览区（EVAL_HELP_IO_REFRESH）；EditBox 字体链先试 SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)；文本类 UI 一律给 FontString 保底；单行输入弹窗用**回声行**保底（OnTextChanged 镜像到 FontString，1.17.0 重命名弹窗 EVAL_HELP_RP_* 范式）

## 编辑工具注意事项
- run_code 里**没有 require**；node 脚本一律写工作区 .js 文件再 `pwsh node xx.js`（内联 -e 引号会炸），pwsh 要加 `2>&1 | Out-String` 否则 stderr 丢失
- edit 工具：本会话内须先 read 过该文件；old_string 要精确（注意缩进空格数，批量失败先 grep 核对实际状态再重试）；node 外部改过文件后必须重新 read 才能 edit
- 大块插入用「写块文件 + node 边界替换脚本」，小改动用 edit 工具逐处替换
- 写文件若报 "file no longer exists"：换文件名重建（fs-observation 缓存）
- DSH 策略 danger-full-access、审批关闭 → 可直接写游戏 AddOns 目录
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EVAL_HELP.lua`（小退/重载时客户端写入；IO 窗底部有该路径的兜底提示，1.20.2）

## 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行+方案技能行+条件tooltip+实时条件亮金）| `/eh st` 状态信息UI（状态变量+最近释放条件明细）
- `/eh cfg` 配置窗 560×420：全局 Tab / 一键宏设置 Tab（方案栏+技能列表+[添加技能]+[导入导出]；1.20.0 起底部图标选择器/条件输入框/EVAL_WAR_ADD_FROM_UI 已删除，新增技能=编辑窗）
- 技能编辑窗：点 [编] 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 &/|
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单目前内置战士 10 技能，其他职业扩展技能表即可）；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（直触指定方案不切激活，绑多按键）；技能需拖上动作条，改动后 `/eh war rescan`；内部函数 1.20.3 起也已改名 EVAL_GO_RESCAN/EVAL_GO_STATUS（EVAL_ZS_WQ 前缀全清）
- 调试：`/eh wdebug`（跳过原因+触发 trace）| `/eh war list` | UELog 动作日志

## 参考代码
- UnrealQuest：`...\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（本客户端实测配方库）
- Cat（TurtleWoW）：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计：宏只读缓存全局）
- OneJudge：`...\AddOns\OneJudge\OneJudge.lua`（最初的参考）
