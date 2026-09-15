# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

## 项目位置与现状
- 插件目录：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp\`（1.21 后用户改名 EVAL_HELP→**EvalHelp**；toc 已同步 EvalHelp.toc——目录名==toc基名才加载；改名时游戏必须关闭否则 Access denied）
- 当前版本：**1.64.0**（★真凶根治：s and pcall(...) 逻辑表达式截断多返回——u/noMana/q 恒 nil，可用性恒 false+已排队失效（4 处全修）；1.62.0 接管时序结论修正（接管后移保留作防御）；可用性只信 noMana 资源信号；测试组 40——教训：and/or 包住 pcall 会吃掉多返回，条件执行路径必须入测试）｜**1.63.0**（可流血改免疫驱动：默认 true、免疫表命中流血技能（撕裂/割裂/绞袭/斜掠/撕扯+英文）→ false；BLEED_BAD_TYPES 类型硬排除删除（本客户端 UnitCreatureType 不可靠，黑暗犬误判）；黑白名单保留覆盖；测试组 39）｜**1.62.0**（★冲锋疑案真凶=接管时序：AttackTarget 先于规则开弓/进战→冲锋脱战限定可用性瞬翻 false（探针 true+手动可放+存档无 inv 三连实锤）；接管块拆分——st.autoAttack 采集原位、接管动作后移到 RULE_RUN 后（无出手才补）；测试组 29/32 空方案驱动）｜**1.61.4**（可用性疑案结案：探针实证 IsUsableAction 正常，false+noMana=true=资源不足（怒气）；早前冲锋跳过系 reload/姿态切换后缓存滞后；跳过原因细分 不可用:资源不足（两处 usable 判定同改））｜**1.61.3**（关系列内联 "||" 漏网同换全角竖线——教训：同一修复有多种写法的路径要全量 grep）｜**1.61.2**（竖线显示修复²：|| 转义在本客户端渲染异常→改全角竖线 U+FF5C（FZLBJW 自带，非转义符））｜**1.61.1**（条件关系 | 显示修复：| 是 WoW 颜色转义符被吞→uiEsc() || 转义全覆盖（关系列/条件列/预览/say/IO预览），数据层不动；EditBox 原文不转义）｜**1.61.0**（技能行新增 v 下移按钮（上 文本改 ^ 成对箭头）；行操作 [^][v][编][删]，widgets 清单加 row.dn）｜**1.60.1**（可用性探针 /eh go probe usable [技能]：dump usable/noMana/inRange/cd/HasAction 原始值——IsUsableAction 本客户端走缓存态（wiki 原文），「可用却跳过」疑案取证用，待用户回报探针数据再定矫正）｜**1.60.0**（技能列表行数动态化 ROWS=floor((H-120)/24)（420高=12行，旧固定 8）；scrollDn 跟随最后一行（旧硬编码 -242））｜**1.59.0**（条件姿态下拉动态化：GetNumShapeshiftForms 枚举带名称，无姿态栏兜底 1；★去除公共CD终止——gcdSkill 删除，符合的规则全部顺序 wuse，客户端自行决定落地（GCD 静默失败）；测试组 34 语义更新）｜**1.58.1**（布局双修：方案栏 delB 间距 21→19（旧间距每行多 2px 逐行下沉错位）；战斗UI 方案行后续行按整行容量定宽——不满行同宽左对齐不再拉伸）｜**1.58.0**（时间型条件步进 0.1、区间 0-10、初始 0.1、%.1f 显示——SE_TIME_K 集合）｜**1.57.0**（新条件 swingLeft 距下次攻击：复用挥击计时 EVAL_SWING_REMAIN，无数据=false；文本 距攻击>1/<0.5；CTG_1；测试组 38）｜**1.56.1**（法师案例×2：法师一键（选敌/寒冰箭射程/火球/霜甲/智慧）+周围补buff（最近友方+无目标buff）；★修导入技能名守卫 24B→48B——带前缀名（选取目标:指定名称=39B/物品长名=36B）被静默丢行）｜**1.56.0**（战斗UI 方案切换行自适应：右缘与状态条对齐、minBW 34px 首行扣标签/后续整行容量、超了自动换行≤3行、每行按钮拉伸填满、高度随行数撑高）｜**1.55.0**（挥击计时：CHAT_MSG_COMBAT_SELF_HITS「你击中/爆击|You hit/crit」锚定 lastSwing + UPDATE_STATE 采 UnitAttackSpeed→st.atkSpd(/Off)；EVAL_SWING_REMAIN 锚点=max(lastSwing,castUntil) 施法推迟；战斗UI 金色挥击条（读条下方）+状态UI 攻速行；事件名不符静默无效；测试组 37）｜**1.54.4**（连击点数默认参数 3→1）｜**1.54.3**（连击点数参数步进限定 1-5（k=="combo" 专属 ±1）——通用步进器 0~300 会步进出永不满足的死条件）｜**1.54.2**（去抖窗口可配 cfg.goDebounce 默认 0.3（全局 Tab 一键宏组 ±0.05 步进 0~1.0，0=关）；执行追踪器 EVAL_GO_TRACE 12 条 + /eh go trace（新→旧间隔 ms+执行/丢弃标记）——偶发「按一下执行两次」待用户 trace 取证：间隔<窗口=队列冲刷，>窗口=按下/松开双触发嫌疑；测试组 36 窗口显式 0.2+浮点余量）｜**1.54.1**（执行去抖：EVAL_GO 入口 0.2s 窗口——/run 宏走 RunScript pending 队列（wiki 证实），连按堆积松手后陈旧调用冲刷=目标狂切；EVAL_GO_LAST 全局（测试可重置）；测试组 36 用 castLog 计数避接管 2s 节流干扰）｜**1.54.0**（光环检查四型：hasBuff/hasDebuff 合并 v 切换（旧 noBuff/noDebuff 仅兼容存量）；新增 tBuff 目标buff/pDebuff 自身debuff 检查；状态表补 targetBuffs/playerDebuffs；wScanAuras 通用扫描 ●▲ 实时项；解析 无buff→hasBuff v=false 回环保真；测试组 35）｜**1.53.0**（并行执行模型：gcdSkill=wslots且非攻击/自动射击/射击 才 return true 终止；角色行为/宠物/选目标/物品全部续行+UPDATE_STATE——一键=切目标+宠攻+喝药+法术；测试组 34 五连链+终止）｜**1.52.1**（选取目标不消耗按键：targetSel 出手后 UPDATE_STATE 刷新+继续评估后续规则——旧行为恒过选目标规则堵死后续技能（用户实测切友永放不出奥术智慧）；仍单 GCD/次；测试组 33）｜**1.52.0**（自动攻击距离检测：远程档（自动射击/魔杖）叠 IsActionInRange——IsUsableAction 不含射程判定，明确 0=超程降档近战；nil 放行；测试组 32 用 GetTime 前移绕接管 2s 节流）｜**1.51.0**（新条件 自动射击/魔杖射击（IsCurrentAction 直查 bool）；★修 COND_BOOL 取反优先级 bug——neg and (not b[2]) or b[2] 对全 true 条目恒失效，!普攻/!可攻击 等取反静默无效；补 未普攻 解析缺口；测试组 31）｜**1.50.0**（自动普攻接管→改名「自动攻击」+优先级制：自动射击>射击(魔杖)>攻击，前两档 IsUsableAction 可用才入选（无远程武器/魔杖自动降档），近战兜底；cfgCheck 加 tip 悬停参数首用；日志带通道名）｜**1.49.3**（取消施法修复：SpellStopCasting 本客户端 Protected 插件直调无效→改 RunScript 聊天脚本同路径（pending script，wiki 无保护标注）；Protected 函数绕行范式=RunScript 队列）｜**1.49.2**（战士残留审计二轮：接管泛化支持猎人自动射击（无攻击→UseAction 兜底）；EVAL_T_RANGE 重复定义两份删一+参照技能多职业化；日志 怒气/战斗姿态 硬编码→EVAL_POWERLABEL/st.form 动态；COND_STR power 名动态；example/zs_wq.md 删除（模版已游戏内置））｜**1.49.1**（空条件=直接执行：groupsOK 开头无组即过——旧行为空 groups 表恒 false，编辑窗不配条件/导入空条件串的技能变死条目；测试组 30 三种空形态）｜**1.49.0**（删 EVAL_GO 选敌硬编码前置——与 选取目标:最近友方 类规则抢目标（用户实测日志先选敌再选友）；选敌走规则 选取目标:最近敌人 | 无目标；与 1.22.0 姿态/冲锋前置删除同性质）｜**1.48.0**（战士硬编码清零：WAR_SKILLS 白名单定义/引用/导出全删，技能+光环参数下拉开纯动作条扫描；新装默认方案去战士化=空方案+案例模版引导；war 阈值缺省键（hsRage 等）无消费者已清）｜**1.47.0**（角色行为扩充：取消施法=SpellStopCasting 特殊行为（未读条跳过）/自动射击/射击入 cat1（走 wslots 通道需上条）；姿态兼容序号 姿态:2；★审计修复 st.autoAttack 采集与接管开关解耦——旧码开关关时 普攻 条件恒 false 致「攻击」规则每按翻转；结论：接管开关≈无条件的 攻击|未普攻（2s节流），与规则不冲突但同效二选一）｜**1.46.0**（战斗UI 两行图标带合一：方案行下方单条技能带，8格/行换行≤16格，冷却数字并入；★修 RESCAN 重新赋值 wslots 致 EVAL_WSLOTS 表引用失效——改原地清空，导出表一律原地更新不许重赋值）｜**1.45.1**（cfgCheck 勾选框文字对齐修复：父级 y-3 估算 → LEFT/RIGHT 共中心线锚定）｜**1.45.0**（方案驱动显示：战斗UI技能图标行废弃固定战士清单 UI_ICONS→8格动态跟随激活方案（wicon 统一图标/groupsOK dry 亮金/冷却数字/空位隐藏）；重扫核对报告+EVAL_GO_STATUS 同改方案驱动；RESCAN 定义早于 petCmdOf 等 local → 报告体走全局导出（作用域陷阱实例））｜**1.44.1**（宏入口兜底：EVAL_GO nil 红框排查结论=改码中途 /reload 读到半成品 Engine.lua；Core 末尾加兜底 EVAL_GO 改聊天提示，Engine 正常加载覆盖之）｜**1.44.0**（IO 弹窗「案例模版」：EVAL_IO_TEMPLATES 按职业分组（cls/list.name/desc/text），选单弹窗 frameLevel 95 点击即导入；原武器战示例按钮并入模版库；★修复两存量 bug——导入按钮方案上限残留 4（应 12）、EVAL_PROFILE_FROM_TEXT 裸 condTrim 漏桥（测试组 26 抓出））｜**1.43.0**（角色行为新增特殊技能「姿态:名称」：姿态栏直切 CastShapeshiftForm——官方文档明确 Not protected 插件可直调，不占动作条；已激活守门（战士姿态重复按 no-op/德鲁伊形态再按会取消 aura）；wready 走 GetShapeshiftFormInfo active/castable+GetShapeshiftFormCooldown；wFindStance 实时枚举栏位；UI 五处接入（别名/亮金/缺失豁免/分类回显×2/光环下拉排除）；测试桩 TEST.stances 驱动四 API；README 速览表与 CHANGELOG 按用户要求裁到 1.52.0 起（更早历史见 git 提交））｜**1.42.0**（方案上限 4→12：EVAL_GO1~12）｜**1.41.0**（自身施法三条件扩展：casting 空参数=任意施法+castEl/castLeft 自身读条进行/剩余（事件自带精确时长无需学习）；★热修 1.39.0 拆分漏桥：ehResolveLang 是 Core local 而 init 在主文件调用→游戏内报错，已加 EVAL_RESOLVE_LANG 导出+主文件别名；拆分后跨文件 local 必须过导出清单审查）｜**1.40.0**（目标施法状态三条件：tCasting（任意/指定技能 是/否）+tCastEl 读条已进行+tCastLeft 读条剩余——CHAT_MSG_SPELL_CREATURE_VS_* 文本事件 EVAL_TCAST_EVENT 解析「X开始施放Y。」/「Y击中你」；读条总时长自学习 war.castTime[技能]=秒（0.2~30s 合理窗）；无目标/12s 超时清理；SE 空参数=任意施法）｜**1.39.0**（模块化重构：4758 行单文件拆 Core.lua(输出/i18n/状态)/Engine.lua(引擎)/EvalHelp.lua(UI+斜杠+init)；toc 顺序 Locales→Core→Engine→EvalHelp；跨文件共享=全局桥导出（Core: EVAL_SAY/LOGLINE/UIOFFSCREEN/POWERLABEL/CURRENTFORM/AUTOFRAME/ON_COMBAT/FORMAT_STATS/COLLECT_STATS；Engine: EVAL_WSLOTS/WICON/GROUPS_OK/AURA_TEX/PET_OF/TGT_OF/ITEM_OF/TARGET_SEL/TSEL_NAME/CLASS_LIST/WAR_SKILLS）+UI 文件顶部别名块；cfg 跨文件引用全部改 EVAL_HELP_CONFIG 全局直读；test_engine 加载链已含三模块）｜**1.38.1**（战斗信息UI 读条进度条：castStart/castUntil 进度反向消耗+剩余秒，插目标条下方细行（root:SetHeight(y) 自动撑高）；探针实测 SPELLCAST_START arg1=名 arg2=时长ms 与实现一致 ✅）｜**1.38.0**（条件「施法中:X」：无 UnitCastingInfo → SPELLCAST_START/STOP/FAILED/INTERRUPTED/DELAYED/CHANNEL_START/STOP 事件驱动 st.castName/castUntil（参数启发式：字符串=名/数字=时长ms）；UPDATE_STATE 过期清理；施法中行入状态UI；事件缺失则静默无效——SPELLCAST_* 未实测待游戏内验证）｜**1.37.0**（目标距离分档 EVAL_T_RANGE：IsActionInRange+参照技能（断筋等近战≤5码/冲锋8-25）→ st.tRange=近战/冲锋距/远程外，状态UI目标行+战斗UI目标条右缘显示；新条件「施法范围内」inRange 技能类（范围内:X/范围外:X，immBtn 复用为是/否钮）；精确码数本客户端做不了——CheckInteractDistance 不分档、无目标坐标）｜**1.36.4**（✅ i18n 分支已 fast-forward 合入 master（b72f957 含用户 info 图提交），双远程已推）——（热修：immBtn 块误嵌 sDrop seBtn 调用中间——语法合法但 immBtn 只在点击时才赋值，刷新即 nil 报错；教训：行号漂移后按行号锚定的插入必须重读上下文）｜**1.36.3**（免疫条件参数区加 免疫/未免疫 切换钮 row.immBtn（x250 w52，仅 cd.k=="immune" 显示，切 cd.v；语言键 IMM_Y/IMM_N））｜**1.36.2**（SE 预览区挪到 [+添加条件] 右侧同行——原在底部 y-254 与保存/取消按钮（BOTTOM+12）重叠）｜**1.36.1**（条件类型「免疫」：immune 条件读学习表 immune[技能@目标]——文本 免疫:X/未免疫:X（immune:/notimmune:），v=false=未免疫；condOne 内联读表（wImmuneTo 声明在 condOne 后，作用域不可达）；SE_TYPES skill 类+CTG_2 目标状态组）｜**1.36.0**（免疫学习器实装：探针实测 CHAT_MSG_SPELL_SELF_DAMAGE +「你的{技能}施放失败。{怪名}对此免疫。」解析（英文 Your X fails. Y is immune. ... (line truncated to 2000 chars)
- 文件：`EvalHelp.lua`（主文件 ~3000 行，单文件架构；1.29.0 由 EVAL_HELP.lua 改名统一 EvalHelp 系命名）、`EvalHelp.toc`、`README.md`、`example\zs_wq.md`（武器战初始方案）
- 游戏：EmberVeil（1.12.1 客户端 UE 版，Lua 5.1）；插件名 EVAL_HELP，战士一键宏函数 **`EVAL_GO()`**（1.16.0 由 EVAL_ZS_WQ 改名；参数 0/不传=激活方案，1-4 或方案名=直触），斜杠 `/eh`

## ⚠️ 最重要教训：改完必须跑语法检查
- **Lua 整文件编译**：任何一处语法错误 → 整个插件无法载入，且 UE 日志里看不到（%LOCALAPPDATA%\Azeroth\Saved\Logs 是空的）
- 1.9.0 曾有两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 1.9.0~1.11.0 全部功能实际未生效
- 旧 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助
- **每次改完 .lua 必跑**：`node luacheck.js`（工作区根目录，fengari 真实 Lua 解析，报错带行号；显示 SYNTAX OK 才算完）
- **1.26.0 起有逻辑冒烟测试**：`node test_engine.js`（test_stub.lua 打桩 WoW API/UI mock + 5.1 垫片，加载整个 EvalHelp.lua 后跑 test_assert.lua 断言：条件解析/显示回环/规则执行/副作用；改引擎必跑两条命令）
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
- **物品 API（wiki 已确认签名，游戏内实测待做）**：UseContainerItem(bag,slot) 消耗品直接用/装备自动穿（BoE 未绑弹确认）；GetContainerItemInfo→texture,count,locked,quality,readable；GetContainerItemLink→|Hitem..|h[名称]|h；GetContainerItemCooldown→start,duration,enable；GetItemInfo 第9返回值=纹理（只读本地缓存）。无 EquipItemByName/UseItemByName。注意：本客户端插件保护清单未文档化，UseContainerItem 是否被禁需实测——若被禁会静默失败（pcall 兜住不炸）
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
- 远程：origin=**git@gitee.com:xeval/emberveil_eval_help.git**；github=**git@github.com:lihaibo123as/emberveil_eval_help.git**（1.29.0 起双远程同步，每次推送两端都推：`git push origin master && git push github master`；本地仓库 = 插件目录本身）
- 推送用默认密钥 ~/.ssh/id_rsa（gitee_id_rsa 未被授权，别用 -i 指定它）
- 库内含：README.md（开源门面+preview/ 界面图）、CHANGELOG.md（更新日志详情）、DEVELOPMENT.md（开发者指南）、CLAUDE.md（AI 记忆体副本，改主记忆后同步过去）、luacheck.js、test_engine.js/test_stub.lua/test_assert.lua（冒烟测试）、example/zs_wq.md
- **更新日志维护规则（1.28.0 起，用户定）**：发新版本时——① 详情写 `CHANGELOG.md`（## 🎯 vX.Y.Z — 主题 小节：要点/典型用法/设计亮点，配一个 emoji）；② README 顶部「更新日志」速览表加一行（| **X.Y.Z** | emoji 主题 | 一句话亮点 |，最新在上）；③ README 不再放版本详情（保持精简，详情只进 CHANGELOG）
- **preview/ 图片只用用户提供的**（当前 main.png=全局页/cfg.png=一键宏设置页/skill_cfg.png=技能编辑窗/info.png=战斗信息UI+状态信息UI）；我加的截图已被用户要求删除——别再自行往里放图
- 帮助输出含：异常自救 /reload 提示 + gitee 反馈地址

## 官方 API 文档（用户提供 2026）
- **Lua API 清单：https://emberveil.org/wiki/lua**（1370 条目，页面内嵌全量 JSON 索引可脚本解析；分类页如 /wiki/lua/globals/Action 有签名+返回值文档）
- 自定义分类：Azeroth（20 条，含 GetUECVar/SetUECVar、语音、IsPlayerMoving 等）；无坐标类 API（GetPlayerMapPosition 在 Mapping 分类但目标坐标无入口）
- 文档列出 Slider 控件（与「无原生 Slider」实测记录矛盾——以实测为准，用前先在游戏内验证）
- 工作区排查工具：parse_api.js（关键词检索）/ dump_cat.js（按分类转储）+ api_*.html 缓存页
- 工作流说明：当前开发主机是临时的，G: 盘游戏目录在另一台主机；本机改码→检查→推送 gitee→另一台拉取实测

## 待开发计划（搁置项）
- **免疫学习器**（✅ 1.36.0 已完成实装：探针验证→事件解析→学习表→引擎跳过；探针 /eh go probe immune/dump 保留作诊断工具）：
  - 结论已排查：无 CombatLog API、无免疫查询函数、wiki 无事件文档页（/wiki/lua/events 404）；但 Frame:RegisterEvent/RegisterAllEvents 可用
  - 设计方向：订阅 CHAT_MSG_* 战斗文字事件，从消息串解析「免疫」→ cfg.war.immune["技能@怪名"] 持久化 → EVAL_RULE_RUN 对同名怪自动跳过该技能（可流血黑白名单 EVAL_BLEED_BLACKLIST 的自动化升级版）
  - 前置步骤：先做探针 /eh go probe（30s 事件抓取写 UELog）拿真实事件名+免疫文本格式，再写解析器；复用 autoFrame OnEvent 三态兼容范式（事件名在 1参/2参/全局 event）
  - 相关基建：st.canBleed 判定链（白名单>黑名单>生物类型排除）

## 参考代码
- UnrealQuest：`...\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（本客户端实测配方库）
- Cat（TurtleWoW）：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计：宏只读缓存全局）
- OneJudge：`...\AddOns\OneJudge\OneJudge.lua`（最初的参考）
