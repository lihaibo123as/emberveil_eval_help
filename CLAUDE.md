# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

## 项目位置与现状
- 插件目录：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp\`（1.21 后用户改名 EVAL_HELP→**EvalHelp**；toc 已同步 EvalHelp.toc——目录名==toc基名才加载；改名时游戏必须关闭否则 Access denied）
- 当前版本：**1.25.0**（新增条件类型「选取目标」：TargetNearestEnemy/nearFriend/nearParty/nearRaid/lastEnemy/lastTarget/clear 七种下拉——副作用条件恒 true，condOne/groupsOK 加 dry 参数，战斗信息UI 亮金预览 groupsOK(r,true) 不执行切换；文本格式 `选取目标:最近敌人`/`target:nearEnemy`；编辑窗 24 种类型）（重扫泛化：动作条全部非宏技能入 wslots，不限 WAR_SKILLS——buff/debuff 条件与方案规则支持任意上条技能；EVAL_GO_SKILL_CHOICES() 合并清单供编辑窗下拉）（每次改动递增版本号：lua 头注释 + `local VERSION` + toc `## Version` 三处同步）
- 文件：`EVAL_HELP.lua`（主文件 ~2900 行，单文件架构）、`EvalHelp.toc`、`README.md`、`example\zs_wq.md`（武器战初始方案）
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
- **1.22.0 硬编码前置清零**：EVAL_GO 里「非战斗切姿态/冲锋」旧战士宏残留已删（用户实测：测试方案只有怒吼却被迫冲锋）；规则化写法 战斗姿态|非战斗 & 非姿态1 & 可攻击；冲锋|非战斗 & 姿态1 & 可攻击 & 就绪
- **EVAL_GO 目标门槛教训（1.21.7）**：规则引擎化后不能有「无可攻击目标就 return」的全局前置——是否需目标交给每条规则的条件；否则纯自身buff方案（如只有战斗怒吼）永远执行不到
- 本客户端无 UnitCastingInfo（打断条件做不了）、无 SuperWoW（无精确距离数值/挥击计时）
- **射程检测已有官方 API（排查 emberveil.org/wiki/lua 确认）**：IsActionInRange(slot) 已实现——返回 true=在射程内 / 0=超出射程 / 1=自动攻击(不测距) / nil=无目标或技能解析失败；ActionHasRange(slot) 返回技能是否有射程；CheckInteractDistance(unit,idx) 已实现但客户端不分档码数（idx<4 统一交互距离，4 恒 false）——可做规则引擎「在射程内」条件，技能本来就在动作条上直接传 slot
- **seBtn 返回包裹表 {btn,bg,text} 不是按钮本体**：锚下拉/加 FontString 必须用 .btn（mkSmall 相反：直接返回 b,bt）——1.21.4 修复 SE 技能名按钮把包裹表当按钮用（uiText 炸 CreateFontString、SE_BUILD 半成品窗口）
- **Lua local 作用域从声明语句【之后】开始**：RHS 里的闭包捕获不到正在声明的 local 自己 → local b = mk(..., function() ...引用b... end) 的 b 是全局 nil！OnClick 要赋值完后单独 SetScript 挂——1.21.4 修复激活方案下拉（DD_OPEN anchorBtn nil）
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
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单仅作下拉置顶（1.24.0 起重扫记录全部上条技能，任意技能可入方案/条件））；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（直触指定方案不切激活，绑多按键）；技能需拖上动作条，改动后 `/eh war rescan`；内部函数 1.20.3 起也已改名 EVAL_GO_RESCAN/EVAL_GO_STATUS（EVAL_ZS_WQ 前缀全清）
- 调试：`/eh debug`（跳过原因+触发 trace）| `/eh go list` | UELog 动作日志
- **命令组 1.21.1 改名 /eh war → /eh go**（handler 入口 string.gsub(msg,"^war","go") 兼容旧命令；sub 偏移量随 war→go 长度差 -1 已同步）

## 开源仓库（1.21.0 起）
- 远程：**git@gitee.com:xeval/emberveil_eval_help.git**（master 已推送；本地仓库 = 插件目录本身）
- 推送用默认密钥 ~/.ssh/id_rsa（gitee_id_rsa 未被授权，别用 -i 指定它）
- 库内含：README.md（开源门面+preview/ 界面图）、DEVELOPMENT.md（开发者指南）、CLAUDE.md（AI 记忆体副本，改主记忆后同步过去）、luacheck.js、example/zs_wq.md
- **preview/ 图片只用用户提供的**（当前 main.png=全局页/cfg.png=一键宏设置页/skill_cfg.png=技能编辑窗/info.png=战斗信息UI+状态信息UI）；我加的截图已被用户要求删除——别再自行往里放图
- 帮助输出含：异常自救 /reload 提示 + gitee 反馈地址

## 官方 API 文档（用户提供 2026）
- **Lua API 清单：https://emberveil.org/wiki/lua**（1370 条目，页面内嵌全量 JSON 索引可脚本解析；分类页如 /wiki/lua/globals/Action 有签名+返回值文档）
- 自定义分类：Azeroth（20 条，含 GetUECVar/SetUECVar、语音、IsPlayerMoving 等）；无坐标类 API（GetPlayerMapPosition 在 Mapping 分类但目标坐标无入口）
- 文档列出 Slider 控件（与「无原生 Slider」实测记录矛盾——以实测为准，用前先在游戏内验证）
- 工作区排查工具：parse_api.js（关键词检索）/ dump_cat.js（按分类转储）+ api_*.html 缓存页
- 工作流说明：当前开发主机是临时的，G: 盘游戏目录在另一台主机；本机改码→检查→推送 gitee→另一台拉取实测

## 参考代码
- UnrealQuest：`...\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（本客户端实测配方库）
- Cat（TurtleWoW）：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计：宏只读缓存全局）
- OneJudge：`...\AddOns\OneJudge\OneJudge.lua`（最初的参考）
