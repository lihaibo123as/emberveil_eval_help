# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

> **本文件只记「关键注意项 / 铁律 / 判据」**：逐版本细节不进这里（在 `CHANGELOG.md` 与 git 提交历史）。
> 只保留**最近 10 个版本**的要点，更早的按**主题合并**进「历史教训汇总」。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**。
> ★**要找「项目位置 / 当前版本 / 在途状态」→ 见文末**（故意放末尾：超预算时**截断发生在文末**，这样铁律与教训优先保留）。

## 当前版本要点（最近 10 版；更早的见「历史教训汇总」，逐版本细节见 CHANGELOG/git log）

- **1.70.47**（在途）：**队友/团员扫描 + 四种状态条件**（用户两轮确认的需求）
  - **行为类型**（用户原话）：`选取目标: 队伍成员` / `选取目标: 团队成员`——**自动实施扫描**。
  - **条件类型「队友/团员状态」**（用户原话）：`队友血量% / 队友蓝量% / 队友debuff / 队友缺buff`，
    团队范围同名 `团员血量% / 团员蓝量% / 团员debuff / 团员缺buff`（共 8 行；引擎侧仍是 4 个 k + `cd.name` 携带范围）。
    debuff 型带**类型下拉**（任意/**魔法/诅咒/毒/疾病**），配置方式对齐已有的 目标debuff/目标buff。
  - ★★★**选取器 = 扫描器 + 过滤器**（用户方案示例的核心机制）：它用**这一行自己的条件列表**逐个候选过滤
    （示例：`目标血量<N%` / `目标buff:名` / `目标debuff:名`），命中者 `TargetUnit` 过去并记 `st.allyUnit`。
    - 候选顺序 = **血量%升序**（最危险优先）→ 天然满足「扫描全员取最低」
    - **过滤要真的切过去再判定**（切 + `UPDATE_STATE` + 跑这一行的条件组）：条件里的「目标血量/目标buff/目标debuff」
      读的就是当前目标；不切就只能靠扫描记录猜，职业/类型/精英类条件根本答不出来
    - 全员都不满足 → **还原原目标**（绝不把目标丢在最后一个候选身上就算完）：先用 `UnitIsUnit` 反查出原目标的
      **unit id 做精确还原**（原目标是队友/自己时最可靠），查不到才退化为 `TargetByName`——
      ★文档明写 TargetByName **只认「附近」单位**，远目标的按名字还原会静默失败（那条路有日志说明）
    - ★`EVAL_RULE_RUN` 对成员选取器**跳过常规条件预判**（那些条件是对「当前目标」说的，一个都过不了）→ 直接进 wuse
      （`TARGET_SEL_TEAMSEL` 标记）。★这条路径**不经过 condOne**；condOne 的 target 分支是**另一个调用点**（存量/文本导入形态），两处都要测。
  - ★★**条件命中即「记人 + 切目标」**（用户要求「扫描全员取最低，记下 unitID → st.allyUnit」）：
    单条 `队友血量<60` 就能自足完成「找出该治的人 → 后续技能行 UseAction 打在他身上」，不强制再配一行选取目标。
    - 切目标只发生在**有意义的方向**：血量/蓝量（该治的人）、debuff「有」（该解的人）、缺buff（该补的人）；
      debuff「无」/ buff「有」是**存在性**判定 → **不切目标**
    - ★**只在非 dry 时切**（dry = 战斗信息UI 每 0.15s 的预览求值，切了就是乱切）——四种类型各测一遍
    - `EVAL_GO` **每次按键开头清空 st.allyUnit**（否则上一轮的人冒充本轮命中），用**真实入口 EVAL_GO** 断言
  - ★**规则按顺序全部执行**（1.59.0 起），所以「选取器 → 治疗 → 驱散」三行在**一次按键**里依次生效；
    后写的条件/选取器决定最终目标（确定性的「后者覆盖前者」）
  - ★**施法路径只有一条**：`TargetUnit`（非 Protected）切到该成员 → 技能行 `UseAction` 打当前目标；`CastSpellByName`/`SpellTargetUnit` 都是 Protected 且没有「指定队友」的形式（详见 F2 节）
  - ★**惰性扫描（频率防护）**：`UPDATE_STATE` 只做「序号+1、丢弃缓存」，**绝不扫描**（它被战斗信息UI 每 0.15s 调一次）；
    真正扫描在 `EVAL_HELP_TEAM_ENSURE(scope)`，**按宏那一轮触发一次**，缓存被复用（有 API 调用计数断言守着）
  - ★**诚实失败**：不在队/团里、成员无蓝（怒气能量职业）、无人符合 → 返回 false **并给出原因**，绝不退回自身血量
  - ★**类型匹配双向容忍**：客户端 `UnitDebuff` 第三返回值可能是本地化 token（中文客户端「魔法」）→ `dispelMatch` 三级兜底；入库统一存英文 id
  - 数据来源：`UnitHealth/UnitMana/UnitPowerType`（**超距离走 roster 数据**）+ `UnitBuff(1..32)` + `UnitDebuff(1..16, 第3返回=类型)`
  - 测试：组 66（扫描/缓存复用/选取器过滤三形态/条件自足记人+切目标/dry 四型不切/**端到端一键奶真跑 EVAL_RULE_RUN**/诚实失败/往返含范围/UI 8 行/下拉列出四型/三语言/原目标精确还原/团队里 party 上界夹到 4）；**变异 33/33 全捕获**
  - ★**官方文档逐条核对过**（1.70.47 现场查 emberveil.org，结论见下方 **F3 节**）——核对过程中查出**两个真 bug**：
    ① `GetNumPartyMembers()` 在团队里返回「团人数-1」（不是 0），而 party 索引只到 `party4`
       → 拿它当循环上界会让 40 人团去试 party1..party39（已夹到 4，并用 UnitExists 调用计数断言守住）
    ② `TargetByName` 只认**附近**单位 → 不能当作「还原原目标」的唯一手段（已改为 UnitIsUnit 精确还原优先）
  - ★**测试桩必须模拟「切过去」**：旧桩里 `UnitBuff("target")` 恒读固定怪的数据 → 「切过去再按目标条件判定」在测试里永远得出与真机相反的结论。
    已给桩加「当前目标 → 单位」映射（`TEST.targetUnit`，不设时行为完全不变）
  - ★★**本轮踩的 4 个新坑（都写进教训了）**：① `ipairs({st.team, st.teamRaid})` 遇 nil 洞**立刻停**（不是跳过）→ 团队成员查不到；
    ② **Lua 模式没有 `|` 交替**、**字符组 `[伍团]` 按字节匹配**装不下多字节字 → 队伍/团队条件**全部解析不出**（往返断言当场抓住）；
    ③ 团队选人判据里用了 `condOne` 的**局部** `texOf`（在本函数是全局 nil）→ 修法是**前置声明 `local auraTexOf`**，
    而 DECL ORDER CHECK **看不见「无 `=` 的前置声明」**、且 CRLF 行尾的 CR 被 `(.+)$` 抓进名字 → 检查静默通过（已修：正则加「纯声明」形态 + strip 去掉行尾 CR，并用「撤销前置声明」的变异自测证明能抓）
    ④ `if pfx == "队伍"` 这类判定在**被 pcall 包住**时只会表现为「选人结果不对」而不是红字 → 必须靠**执行真实路径的断言**才抓得到
  - ⚠️ **待游戏内实测 3 点**：① 队友 `UnitDebuff` 第三返回值的真实取值域 ② `TargetUnit` 战斗中是否可用 ③ 切目标后 `UseAction` 是否按新目标施法
- **1.70.46**（在途）：
  - UnrealQuest 依赖的 **5 状态探测**（就绪/未安装/已装未启用/已启用未就绪/无 Addon API）+ 友好引导面板；依赖缺席时**收起交互控件**而不是留个能打字却永远 0 条的框
  - **LANG KEY CHECK** 静态扫 `L("字面量")` 是否三语言齐全；★它**看不见动态键**（`L(dsDepText(st))`）→ 必须再补运行时的「逐语言断言文案 == 该语言包的值」
  - **真 bug（历史遗留）**：`DataSearch`/`Toolbox` 的 `L()` 用**写入器** `EVAL_RESOLVE_LANG()`（它没有返回值）→ 被 `or "zhCN"` 兜底 → 英俄客户端整页中文、`dsLang()` 永远取 `*_zhCN` 子表。**取语言只认读取器 `EVAL_GET_LANG()`**（LANG SOURCE CHECK 守着）
  - **两个我自己引入的回归**：① `root:SetHeight(H)` 被**同一行的行尾注释吞掉** → 技能编辑窗高得离谱；② `seSecKinds` 声明在 `EVAL_HELP_SE_REFRESH` **之后** → 点「自身buff」直接红字 nil。新增 **WINDOW SIZE CHECK** / **COMMENT SWALLOW CHECK**，DECL ORDER CHECK **扩到 5 个生产文件**
  - **★教训**：这两次都不是断言写错，而是**断言覆盖范围不够**（漏了「高度」这一维 / 漏了「EvalHelp.lua + hasBuff 分支」）。加新代码前先自问：**这条新路径，究竟有哪条断言会真的执行它？**
- **1.70.45**（在途）：配置窗加宽到中 660 / 西文 800（`cfWinWidth()` **单一来源**，技能编辑窗同宽）；条件行新增「**剩余时间**」参数（秒/步进 1/区间 1-300，**仅自身 buff/debuff**——客户端只有自身光环有时长 API）
- **1.70.44**：定案「点定位后地图空白」= `dsAnnOverlay` 被两批函数**分别绑到全局与局部**（同一变量两个绑定）；新增 **DECL ORDER CHECK**，顺带查出 `DS_MAX_PINS` / `dsRndOn` 两处同类
- **1.70.43**：猎人案例模版；修「导出→导入」**静默丢弃**（11 个取反条件无法解析 + 无条件技能行被丢）
- **1.70.42**：自愈语义收敛——只在「本该有钉子却一个都没显示」时才重建（不是盲目重建）
- **1.70.41**：「类型: 全部」按钮整颗不显示（layout 常量 local 作用域，第 10 次）；实体色改为 **id 派生的确定性哈希**（不能每次现摇随机，否则颜色留不住）
- **1.70.40**：**删掉**「定时强刷 1.5s / 慢速兜底 5s / 稳定期闸门 0.8s」三件套 → 签名一变立刻重绘（用户选 A 方案）
- **1.70.39**：**根因定案**——tick 帧挂 `UIParent`，而本客户端打开全屏世界地图会隐藏 UIParent → OnUpdate 停摆；改挂 **`WorldFrame`**（3D 视口，永不被 UI 隐藏）
- **1.70.38**：地图诊断浮层 `/eh ds hud`（把状态直接画在画面上，替代反复猜日志）；**诚实放置**（`PositionWorldMapPin` 失败就不 Show、不算成功）
- **1.70.37**：稳定期闸门（**已于 1.70.40 删除**——它把重绘全吞了，是「切图不更新」的主因）

## 历史教训汇总（1.70.0 ~ 1.70.36，按主题去重；不再逐版本记录）

### A. Lua `local` 作用域（累计 13 次，头号杀手）
- **判据（记住这一条就够）**：Lua 的作用域是**词法**的——引用点若在 `local` 声明之前，那个名字**永远**解析成全局，**与运行时调用顺序无关**。所以「声明晚于引用」一定是真 bug，不存在「其实运行时能拿到」。
- **典型形态**：① 函数读到全局 nil（按钮不显示 / 点一下红字报 nil）；② **同一变量两个绑定并存**（一批函数写全局、另一批读局部，日志里两个读者给出相反答案）；③ 状态变量声明在使用它的函数之后（HUD 恒 nil）；④ 导出/访问器函数放在它引用的 `local function` 之前。
- **防法**：`EVAL_DS_*`/`EVAL_TEST_*` 导出函数一律**物理定义在被引用的 local 之后**；一组互相引用的布局常量集中在函数**开头**；状态块整体上移到所有使用点之前。**DECL ORDER CHECK 会自动扫（5 个文件）**。
- **例外：不得不提前引用时，用「前置声明」**——`local f`（**无 `=`**）放在使用点之前，真正实现处写 `function f(...)`（**不带 `local`**，否则是新建第二个绑定）。
  ★1.70.47 实战：队伍选人判据要用 `auraTexOf`，而它在文件后半段才定义。
- **★★检查器自身的盲区（1.70.47 两次踩中，比 bug 本身更值得记）**：
  ① **它看不见「无 `=` 的前置声明」这个写法**——旧正则只认 `local x = ...` 与 `local function x`；
     于是「按它的建议去修」反而让名字**彻底脱离检查范围**（从「会误报」变成「永不检查」）。
  ② **CRLF 行尾的 CR 会被 `(.+)$` 吃进名字** → `isName` 判定失败 → 声明不可见。
  ★判据：**检查器必须覆盖「它自己推荐的那套写法」的所有变体**，并且**要用变异证明它真的会响**
  （本轮就用「撤销前置声明」的变异自测：`DECL ORDER CHECK: FAIL - Engine.lua: auraTexOf used at 326 but declared at 505`）。
  改检查器 ≠ 检查生效——**没被变异验证过的检查，等于没有**。
- **★★仍存在的盲区（记着，别以为有它就安全）**：DECL ORDER CHECK 按**名字**判定，所以
  「某名字在 A 函数里是 local、在 B 函数里被当全局用」它**看不见**（同名有函数内 local 就整条跳过）。
  1.70.47 的 `texOf` 正是这样漏的（`condOne` 的局部函数，在 `teamCriteriaFor` 里是全局 nil），
  而且因为外层有 `pcall`，**不报红字、只表现为「选人结果不对」**——只有**执行真实路径的断言**才抓到。

### B. 静默失败族（本项目的 bug 主要形态：不报错、pcall 全成功、行为却错）
- **注释吞语句**：本仓库有「一行两句」写法（`root:SetWidth(W) root:SetHeight(H)`，共 6 处）——在行内插入内容/加行尾注释会把后一句吞掉。**COMMENT SWALLOW CHECK 守着**；edit 工具插行要插在**完整语句边界之外**。
- **写入器当读取器**：调用点拿到 nil → 被 `or 默认值` 吞掉（见 1.70.46）。凡是「取了值又被 `or` 兜底」的地方，先问那个函数**到底返不返回值**。
- **派生值当缓存**：一个状态有「真值」和「派生值」两份时，**恢复/序列化只能信真值**（`dsAnnOn` 由类别集合派生，却去读过期镜像 `cfg.ds.nodes`，两轮都出 bug）。
- **缺键显示键名**：`L()` 找不到键会**把键名本身**显示给用户 → LANG KEY CHECK + 运行时逐语言断言。两类检查各管一侧（静态管字面量、运行时装管动态键）。
- **素材路径**：写错**不报错、纹理空白**并静默不画 → ICON CHECK 用真实文件系统逐个 `existsSync`。
- **显隐要按整套控件**：漏藏一个子钮就会在别的视图里叠出一列图标（行 = btn + iconBtn + mapBtn，一个都不能漏）。
- **关一个图层必须回收已画出的东西**：「不再画新的」和「清理已画的」是两件事，漏后者就是「关不掉/旧数据」。

### C. 断言与测试（「绿」不代表对——本项目反复栽在同一处）
- **桩太宽松**：mock 的 Show/Hide 是空操作、IsShown 恒 nil、CreateFrame 丢 parent、GetWidth/GetHeight 恒 nil、SetWidth/SetHeight 不记录 → 「行为级」「父级」「尺寸」类断言全部无法生效。**写断言前先确认桩有状态**。
- **只测解析函数、不测调用点**（第 4 次发作）：断言 `dsEntityColor(id)` 抓不到调用点现摇随机；断言判定函数抓不到 UI 分支里引用错名字。**凡是「A 产出配置、B 消费配置」，两边都要断言**；能点就点**真实按钮**（走它自己的 OnClick 闭包）。
- **测试里复刻逻辑**：断言自己再实现一遍顺序/过滤，被测代码怎么变异都测不出来 → 把逻辑抽成 UI 与测试**共用**的一份。
- **等价变异 / 变异体没落地**：新旧实现结果相同的用例证明不了任何事；CRLF 文件上用 `\n` 锚点会静默替换失败（**变异后必须回读确认结构真的变了**）。
- **★★锚点必须"整行精确 + 命中数唯一"（1.70.47 被这个骗过一次）**：我用的锚点 `      teamPickArg.rule = r`
  **是另一行（8 空格缩进那行）的子串** → `String.replace` 改的是**不是我想改的那行**，
  变异体等于没落地 → 报告"存活"，我差点去为它补一堆没必要的断言。
  ★判据：变异脚本必须 ① 按**整行**匹配（`^...$`）② **断言命中数 == 1**（≠1 直接报错，不许静默跳过）
  ③ CRLF 文件先把行尾 CR 摘掉再匹配、写回时补回去。
  **"变异存活"可能是锚点没打中，不是测试没覆盖**——先证明打中了，再谈覆盖。
- **模块级状态跨用例残留**：池子/缓存/被替换的全局必须用 `EVAL_DS_TEST_RESET_PINS()` 之类先重置、用完 save/restore（**跨小节残留**也要还原）。
- **断言要盯「要保的那条性质本身」**：色相多样性 ≠ 三元组不相等；文案来自哪个语言包 ≠ 四条互不相同。**别用弱代理代替性质**。

### D. 布局与 UI（本客户端实测）
- **同一行/栏混用「顶边对齐」与「中线对齐」必然错位**——要么全顶边、要么全中线；**按中线更稳**（字体链不同时行高会变）。公式：`中线 = 顶边 - 高度/2`（y 越往下越负）。
- **FontString 一律显式 `SetWidth`**，否则宽度由内容决定，换语言/改文案就溢出压到别的控件。
- **改布局要一起改「隐形跟随件」**：占位提示、聚焦热区、背景纹理的宽度往往跟着某个控件写死（grep 旧宽度值能找出来）。
- **可点区域一律用 Button**：纹理不接收鼠标（图标点不动）、同层重叠时后建者不一定在上（显式抬 `frameLevel`）。
- **本客户端 EditBox 默认不左对齐**：必须 `SetJustifyH("LEFT") + SetJustifyV("MIDDLE") + SetTextInsets(2,0,0,0)`。
- **世界地图画布上的 tooltip 必须用 `WorldMapTooltip`**（GameTooltip 挂在 WorldMapButton 子帧上什么都不显示）。
- **`root:SetScript` 是单槽位**：多 Tab 共用根帧时，先 `GetScript` 取旧处理器做**链式转发**，否则静默顶掉别人的滚轮。
- **无原生 Slider、无原生下拉**：滑条自制，下拉一律走全局件 `EVAL_DD_OPEN`。

### E. 兜底机制的设计纪律
- **前提被证伪的兜底必须删掉**（不能因为「留着无害」而保留——5s 全量重建、稳定期闸门都在空转还让人以为有保护）。
- **先校验再修复**：无条件重做 = 用性能换一个不存在的收益。
- **兜底必须排在快路径之后**，否则它会吞掉快路径的延迟优势。
- **证据要自检**：曾据一条自相矛盾的数字（13.7s ÷ 0.25s ≈ 55 tick）加了两个版本的兜底。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`。开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`MapContext:GetViewedZone()` 关图后不清**（仍返回上次区域）；`GetMapZones` **忽略参数**只答当前选中大陆。
- **所有落盘日志通道都是死的**（`UELog` 只进内存 Lua log 分类；`RLog` 无 debug 构建时 no-op；Shipped 且无 `-log`）→ 日志走 `EVAL_HELP_CONFIG.log` 环形缓冲（SavedVariables，**只在 /reload/退出 落盘**）。
- **附加素材路径必须「无扩展名 + 插件名小写」**，否则静默不画。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数，没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」），匹配要剥掉「生物」再比。
- **`GetItemInfo` 只有 9 个返回值、无售价**；`Client.SetWorldMapPinPosition` **不存在**（真实的是 `PositionWorldMapPin`）。
- **无 CombatLog API、无免疫查询函数、无 UnitCastingInfo、无 SuperWoW**（精确距离/挥击计时做不了）。
- **`LoadAddOn` 是 Protected**：插件不能自行加载别的插件（依赖缺失只能引导，不能一键加载）。

### F3. 官方文档**现场核对记录**（1.70.47 逐条查 emberveil.org，2026-09）
> 怎么查：本地 `api_*.html` 缓存**内嵌完整正文**（不是只有目录），可直接 `node` 抓 `id="函数名"` 那一段；
> 缓存里没有的类别（Group/Raid）用**共享浏览器**打开真页面再 `browser_execute` 取 `#anchor` 的兄弟节点——
> `web_fetch` 会在 100k 字符处截断，正好把正文截掉（本页大量内容在页面后半段）。
> 缓存时间：api_unit/targetting/action/spell 均为 2026-09-14~17。
- **签名与返回值（逐条核对过）**：`UnitHealth/UnitHealthMax/UnitMana/UnitManaMax(unit)`、`UnitPowerType(unit)`、
  `UnitBuff(unit,index[,raidFilter])`、`UnitDebuff(unit,index[,raidFilter])`、`UnitExists(unit)`、`UnitName(unit)`、
  `UnitIsUnit(unit,other)`、`TargetUnit(unit)`、`TargetByName(name)`、`ClearTarget()`、`UseAction(slot[,clicked[,onSelf]])`、
  `GetNumPartyMembers()`、`GetNumRaidMembers()`。
- **Protected（文档明写 Protected: addons cannot call this）**：`CastSpellByName`、`SpellTargetUnit`、`SpellStopCasting`；
  ★`TargetUnit`/`TargetByName`/`ClearTarget`/`UseAction`/`IsUsableAction`/`IsActionInRange` 的条目里**都没有 Protected 标记**——
  这正是「切目标 → UseAction」这条唯一可行路径的依据（文档给 Protected 函数是会明确标注的）。
- **★`UnitIsUnit` 相同返回 `true`、不同返回 `nil`（文档原话 never false）** → 判定只能看真值，**不能写 `== true`**。
- **★`GetNumPartyMembers()` 在团队里返回「团队人数 - 1」，不是 0**；而 **party 索引只有 `party1..party4` 且不含自己**。
  → **不能拿它当 `party` 循环上界**（40 人团会去试 party1..party39）。已夹到 4，并有调用计数断言守着。
- **`GetNumRaidMembers()` = 团队人数含自己，非团队时 0** → raid 范围直接 `raid1..N`，不需要再补 `player`。
- **★`TargetByName` 只认「附近(nearby)」单位** → 拿它当「还原原目标」的唯一手段会在原目标较远时**静默失败**；
  已改为优先用 `UnitIsUnit` 反查 unit id 做精确还原，按名字只是兜底（并有日志说明）。
- `UseAction` 的第 3 参 `onSelf` = 对**自己**施法（否则打当前目标）——这是「插件只能打当前目标」的文档依据。
- **超级采样（Swipe/SuperWoW 之类）与 `UnitDebuff` 第 3 返回**：文档明写第 3 返回是 **dispel-type token（例如 Magic）**，
  但**中文客户端实际给什么**仍以游戏内实测为准（本项目的三级兜底就是为这个不确定性准备的）。

### G. 任务/地图专题的关键事实（详见下方铁律节）
- tick 帧必须挂 **`WorldFrame`**；视图签名必须含 **areaId + mapFile + continent + zoneIndex**（只比 areaId 会让「关图再开同一张图」被判「未变」）。
- 采集点数据在 `meta.herbs/mines/chests/fish` 里是**负 ID**（负号 = 类型编码），查 objects 表要取反。
- 对方地图标注层**没有地图事件可用，全靠 `REFRESH_INTERVAL=0.25` 轮询**——不要自己发明事件层。

### H. Lua 5.1 / 本客户端语言坑
- `string.find(s, "^14|", 1, true)`：**plain=true 会把 `^` 也当普通字符**；`|` 在 Lua 模式里是**字面量**（不是交替）。
- ★★**中文/多字节串上的模式匹配（1.70.47 一次踩中两个，代价是「整类条件解析不出来」）**：
  ① **`|` 不是交替**（同上）——写 `(队伍|团队)` 只在匹配**字面串**「队伍|团队」时成立。
  ② **字符组 `[伍团]` 按字节匹配**——Lua 的 set 只吃**一个字节**，`[伍团]` 实际是
     `{228,188,141,229,155,162}`；匹配到「伍」的首字节后，剩下两个尾字节对不上后续的 `buff`，照样失败。
  **正确写法：用 `(.+)` 抓下来，再用 `==` 做字符串比较**（`if pfx == "队伍" or pfx == "团队" then`）。
  ★症状具有欺骗性：**编辑窗里能存、导出文本也正常，但重新导入时条件静默消失**（解析返回 nil → 被丢弃）。
  ★只有「导出→导入」**往返断言**能抓住它——本轮就是靠组 66 的往返用例当场定位。
- `and/or` 惯用法**无法表达 `false`**（`x and false or y` → y），要显式 `if x == nil then`。
- 无 `#`/`select`/`gmatch` 依赖：用 `table.getn`；字符串替换用 `string.gsub` 的 `%` 转义。
- 用户输入/文本拼接后要 `uiEsc`（`|` 是转义符，会吃掉后续颜色码）。

### I. 参考代码路径（**先读对方**，见下方铁律节）
- **UnrealQuest**：`...\Interface\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（实测配方库 + 行为库，注释里全是坑）、`Core/Driver.lua`（帧父级/生命周期）、`Map/MapContext.lua`、`Map/WorldMapPins.lua`、`Map/NpcPins.lua`（CATEGORIES/RANK_ICONS）
- **Cat（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计参考）
- **OneJudge**：`...\AddOns\OneJudge\OneJudge.lua`（最初的参考：纯色纹理配方）
- **Heart + C（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Heart`（团队/治疗框架）与它依赖的共享库 `...\AddOns\C`（隐形 tooltip + 单位/buff 采集）——**队伍/血量蓝量/buff 检测看下方专节**

## ⚠️ 最重要教训：改完必须跑语法检查
- **Lua 整文件编译**：任何一处语法错误 → 整个插件无法载入，且 UE 日志里看不到（%LOCALAPPDATA%\Azeroth\Saved\Logs 是空目录——本客户端落盘日志通道全废，见上方 **F 节**（本客户端 API / 素材真伪清单））
- 1.9.0 曾有两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 1.9.0~1.11.0 全部功能实际未生效
- 旧 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助
- **每次改完 .lua 必跑**：`node luacheck.js`（工作区根目录，fengari 真实 Lua 解析，报错带行号；显示 SYNTAX OK 才算完）
- **1.26.0 起有逻辑冒烟测试**：`node test_engine.js`（test_stub.lua 打桩 WoW API/UI mock + 5.1 垫片，加载整个 EvalHelp.lua 后跑 test_assert.lua 断言：条件解析/显示回环/规则执行/副作用；改引擎必跑两条命令）
- fengari 已装在工作区 node_modules（npm 走代理 127.0.0.1:10809）
- **test_engine.js 现在含 9 道源码级检查**（改了对应区域就必须让它们继续通过）：
  `WIN WIDTH`（窗口宽度单一来源）· `DECL ORDER`（5 个文件的顶层 local 声明早于使用）· `LAYOUT`（EVAL_DS_BUILD 布局常量）· `VERSION`（源码 VERSION == toc）· `LANG KEY`（`L("字面量")` 三语言齐全）· `LANG SOURCE`（取语言只认 EVAL_GET_LANG）· `WINDOW SIZE`（两个自建窗真的设了宽与高）· `COMMENT SWALLOW`（语句没被行尾注释吞掉）· `ICON`（分类图标素材真实存在）
- **断言组 1~66**：覆盖解析/引擎/UI/布局/语言/标注层；新增功能请顺带加组（写在 test_assert.lua 末尾 `print("ALL TESTS PASS")` 之前）

### F2. 队伍/团队·目标切换相关 API（1.70.46 文档核对，可行性评估已验证）

- **`UnitDebuff(unit, index)` 有第三个返回值 = dispel 类型 token**（`Magic`/`Curse`/`Disease`/`Poison`/…，可能是 nil）——**对任意单位都返回**，所以「解魔法/解诅咒/解毒/解疾病」的下拉**不需要 tooltip 扫描、也不需要自建名字表**（index 1..16；第三参 raidFilter 为真时只列「玩家能驱散的」）。`UnitBuff(unit,index)` 只有 icon+层数（1..32，第三参 = 只列 raid 可施放的）。
- **`UnitHealth`/`UnitHealthMax`/`UnitMana`/`UnitManaMax`/`UnitPowerType(unit)` 对队伍/团队成员有效，且超距离时用 roster 数据**（partypetN 用宠物数据）。★`UnitMana` 是「主能量」且有显示缩放（怒气 ÷10、幸福 ÷1000）→ **「蓝量」类条件必须先判 `UnitPowerType(unit)==0`**（0 mana / 1 rage / 2 focus / 3 energy / 4 happiness）。
- **施法 API 的保护状态（关键）**：`CastSpellByName(name,onSelf)` **Protected**，且**只有 onSelf、没有「指定队友」的形式**；`CastSpell` **Protected**；`SpellTargetUnit(unit)` / `SpellStopTargeting` / `SpellStopCasting` **都 Protected** → **插件无法直接把法术打给队友**。
- **`TargetUnit(unit)` 非 Protected**（文档无 Protected 标注；同页 CastShapeshiftForm 还特意写 Not protected）→ **唯一可行路径：先 `TargetUnit("party1")` 切目标 → `UseAction(slot)` 施法 → 还原原目标**。`UseAction(slot[,clicked[,onSelf]])` 同样非 Protected，但也只有「当前目标 / 自己」两种落点。
- `Targetting` 分类备有：`TargetLastTarget` / `TargetLastEnemy` / `ClearTarget` / `TargetByName` / `TargetNearestPartyMember` / `TargetNearestRaidMember` / `TargetNearestFriend`（恢复与自动选人可用）。
- ★**本项目的「选取目标」副作用条件已实现「切目标 + 还原」**（`Engine.lua` 1.25.0 起：targetTarget = `TargetUnit("targettarget")`、byName = `TargetByName` 且名字存 `cd.nm`；求值时先存原目标、切换、必要时还原）→ **队伍/团队目标选取可直接复用这套框架**。
- ⚠️ 待实测（文档说支持，但要在 EmberVeil 里跑一遍）：① `UnitDebuff` 第三返回值对**队友**是否真返回 token 及取值域；② `TargetUnit` 战斗中是否仍可用；③ 切目标后 `UseAction` 是否按新目标施法、失败后目标是否已被切走。

## ★★★铁律：任务/地图类问题，先读 UnrealQuest 对应流程代码（用户明确定，1.70.40）
- **用户原话**：「记住下次碰到任务地图相关的问题优先排查任务插件的对应流程代码」。
- **触发条件**：凡是涉及 **任务 / 地图 / 标注 / 世界地图 / 地图坐标 / 地图切换** 的问题——**第一个动作是去读 UnrealQuest 的对应流程代码**，不要先自己推断，也不要先往日志上加东西。
- **读哪里（按问题类型）**：
  | 问题 | 先读 |
  |---|---|
  | 定时/刷新不生效、生命周期 | `Core/Driver.lua`（**帧父级、OnUpdate 派发**——1.70.39 的坑就在这） |
  | 当前看的是哪张图 | `Map/MapContext.lua`（`GetViewedZone` / `Inspect`） |
  | 怎么画、什么时候重绘 | `Map/WorldMapPins.lua`（`ViewSignature` ~678、`Refresh` ~4449） |
  | 某个 API 在本客户端能不能用 | `Compatibility/ClientAPI.lua`（实测配方库，含大量「本客户端不支持 X」的明文） |
  | 图标素材路径 | `Map/NpcPins.lua`（CATEGORIES 表 + `IconForLocation`） |
- **怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库信息密度最高的内容。
- **停下信号**：当你发现自己在「加日志 → 看日志 → 猜 → 再加日志」里转第二圈，**立刻停手去读对方代码**；**若读完仍未解决 → 转入下方「取证协议」铁律**（操作日志 + 测试流程，用户配合取证）。
- **两次代价（都是绕了远路）**：**1.70.17** 我自己发明 `IsShown` 判地图可见性，而对方 `ClientAPI.lua:8664` 早写明这 API 在本客户端不可靠 → 引入回归；**1.70.39** tick 挂 `UIParent` 导致开图时 OnUpdate 停摆，而对方 `Driver.lua:467-482` 把机理和正确做法全写在注释里 —— 我用日志推断**五轮**没找到，**用户一句「可以查看任务插件…」当场破案**。

## ★★★铁律：队伍/团队·血量/蓝量·buff/debuff 检测 → 先读 Heart（及它依赖的 C 库）（用户明确定，1.70.46）

- **用户原话**：「涉及到团队/队伍信息获取，血量，蓝量，buff/debuff 等检测 参考 `D:\game\TurtleWoW\Interface\AddOns\Heart` 插件的实现机制。」
- **触发条件**：凡涉及 **队伍/团队（party/raid）成员枚举 · 单位解析（名字 ↔ unit id）· 血量/蓝量/资源与百分比 · buff/debuff 检测（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——第一个动作是去读 Heart 与 C 的对应实现，不要自己从零推。
- **★本机就是游戏主机**（用户 1.70.46 明确）：**EmberVeil**（`G:\...\Emberveil\live\Azeroth`）与 **TurtleWoW**（`D:\game\TurtleWoW`）都在本机，**可直接读对方源码、也可直接进游戏实测**——不存在「另一台机器」，不要再拿远端当借口。
- **读哪里（按问题定位）**：

  | 问题 | 先读 |
  |---|---|
  | 名字 → unit id（从聊天/战斗文字里的人名反查单位） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 「慢查」遍历 `raid1..N`/`raidpetN`、`party1..N`/`partypetN`、`player`/`pet`、`target`/`targettarget`/`mouseover`） |
  | `target`/`mouseover` → 具体队伍成员 | `C\C_AKA.lua`（用 `UnitIsUnit` 逐个比对，返回 `raid3`/`party1` 之类；便于把当前目标当成员查数据） |
  | buff/debuff 全量采集的数据结构 | `C\C_SetPlayerData.lua`（**16 buff + 16 debuff 槽**扫描 → `C_player_data[名字].Buff[纹理] = {Name,Type,Text,Count,Tick,Time}`） |
  | 采集驱动 + 多插件共用时的仲裁 | `C\C_UpdatePlayerData.lua`（遍历 raid/party/target/targettarget/mouseover/pet；★**同一轮更新只允许一个调用者**） |
  | 「某单位有没有某 buff/debuff」 | `C\C_UnitGotBuff.lua` / `C\C_UnitGotDebuff.lua`（按**名字**查 `C_buff_texture_map` → 纹理 → **要求 `Tick == CurrentTick`** 才算「有」，且返回**数据条目**而非布尔） |
  | **用 tooltip 读客户端没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData` / `C_GetDebuffData` / `C_GetSpellData` |
  | 队伍/团队主逻辑、血量优先级与治疗决策 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`UnitHealth`/`UnitHealthMax`/`UnitMana`/`UnitPowerType`；`hpDeficit = UnitHealthMax - UnitHealth`、`priority * (healvalue / UnitHealthMax)` 的权重算法） |
  | 事件与跨插件通信 | `Heart\Heart_event.lua`（`RegisterEvent` / `SendAddonMessage`）、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua`（**钩各种单位框插件**，十几种单位的适配都在这里） |
  | 图腾 / 需要 tooltip 扫描的跟踪 | `Heart\Heart_Totem.lua`（31 处 tooltip 调用） |

- **★必抄的五个机制（这才是「实现机制」的干货）**：
  1. **隐形 tooltip 当 API 用**（`C.xml`）：`<GameTooltip name="C_Tooltip" hidden="true" inherits="GameTooltipTemplate">` + `PLAYER_LOGIN` 时 `SetOwner(UIParent,"ANCHOR_NONE")`（1.10 hack）与 `SetClampedToScreen(0)`（1.11 hack）。读取时**先清要用的行再 Set**（`C_TooltipTextLeft1:SetText()` 无参 = 清空），再 `C_Tooltip:SetUnitBuff(unit, slot)` / `SetUnitDebuff` / `SetSpell` / `SetAction`，然后 `GetText()` 取行——**buff 的名称/类型、第二行文本（常含剩余时长）、法术的耗蓝/射程/施法时间都从这里来**。
  2. **Tick 新鲜度**：每轮刷新把 `CurrentTick + 1`；查询侧要求 `entry.Tick == CurrentTick` 才算「现在有」——**从结构上杜绝把上一轮/过期数据当成现行状态**（比「加时间戳自己判过期」更简单可靠）。
  3. **贵调用只在「新出现」时做**：tooltip 调用很贵 → 只有**首次见到**该 buff 才去读；已知且**层数未变**时只刷新 Tick 并累加 `Time`，不做 tooltip；扫描时 **buff 与 debuff 槽都空就提前 return**。（正合本项目的「频率防护总则」）
  4. **名字 ↔ unit 解析与宠物命名约定**：宠物一律 `主人名-宠物名`（自己宠物 = `UnitName("player").."-"..UnitName("pet")`，队友宠物 = `UnitName("party1").."-"..UnitName("partypet1")`）；反查先走缓存再「慢查」，**缓存命中也要用 `UnitExists` + 名字复核**（unit id 会变）。
  5. **共用更新函数的单调用者仲裁**：`C_UpdatePlayerData` 用 `C_last_update_player_data_caller == this:GetName()` 判断，**别人正在这一轮更新就直接 return**，并用 `GetTime()` 统计本次耗时（`C_update_player_data_interval`）——多插件共用一份数据时的去重与自测。

- **⚠️ 重要边界（别抄错东西）**：Heart/C 是 **TurtleWoW** 客户端插件，本项目跑在 **EmberVeil**；本机的 `C\C.lua` **已被用户改写**成「治疗施法监控（CastingSpeed）」，依赖 **SuperWoW** 扩展（`SUPERWOW_STRING`、`UNIT_CASTEVENT`、`UnitExists(unit)` 第二返回值 = GUID）。→ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（本项目另有「EmberVeil 无 SuperWoW / 无 UnitCastingInfo」的记录，别因为 Heart 能用就假定我们也能用）。

## ★★★铁律：同一个问题**两三轮没解决** → 立刻转「操作日志 + 测试流程」，让用户配合取证（用户明确定，1.70.46）

- **用户原话**：「碰到两三轮提问都无法解决的，尽快用记录操作日志的方式 + 提供测试流程。我会配合你完成问题排查。」
- **触发条件（硬性计数，不许糊弄）**：**同一个现象**我已经来回「改一版 → 让用户再试 → 还是不对」**第 2 轮结束时就要准备取证，第 3 轮必须转取证模式**。继续凭猜测改代码 = 浪费时间且可能引入新回归（本项目已有两次代价）。
- **转入取证模式 = 一次交付这三样（缺一不可）**：
  1. **操作日志（插桩点要选在分叉处）**：记录「输入是什么 → 判据取值是什么 → 走了哪个分支 → 结果是什么」。★核心要求：日志必须能**区分「代码没跑」和「条件没满足」**（1.70.16 的教训：心跳日志被写在 `if not 开关 then return end` 之后，整条链路静默，白猜三轮）。用 `dsLogAlways` 这类**不受 trace 开关门控**的通道记用户点击与异常路径。
  2. **测试流程（编号、可照抄、含期望现象）**：从**干净状态**开始（`/reload` 或重进游戏），一步一件事，每步写「做什么 → 期望看到什么」；需要多场景就分开列（如 场景A 首次打开 / 场景B 切换 / 场景C 关闭再开）。★**异常时也要让用户把剩下的步骤走完**（出错那一刻之后的行为同样是证据）。
  3. **回传物说明**：日志怎么拿（`/eh logdump` 打聊天框，或直接读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）+ **注意本客户端日志只在 `/reload`/退出时落盘**，所以要提醒用户先 `/reload`；再加现象描述/截图更佳。
- **能做成命令就别让用户手工复现**：优先给「一键探针」而不是「请你试十遍」——本项目已有的范式：`/eh ds rnd`（随机点探针、如实统计成败）、`/eh ds hud`（把状态画在屏幕上）、`/eh ds trace`、`/eh go probe`。**把取证做成命令，是效率最高的协作方式**（1.70.35~38 正是靠它一行定案）。
- **取证模式的纪律**：
  - **一次只验一个假设**；同时改多处 → 分不清是谁生效。
  - **不要只丢一句「把日志发我」**——必须带完整测试流程，否则用户不知道要复现什么。
  - 拿到日志先**对齐时间轴**（日志行自带相对时间戳 `"%.3f 消息"`），并按「时间戳重排」看事件先后（1.70.31 正是重排后一眼看出 `map=nil`）。
  - 日志里出现**两句自相矛盾**的话（如「层已关且无覆盖层」与「覆盖=草刺野猪」）→ 立刻怀疑**同一变量的两个绑定**（1.70.44 的定案方式）。
  - 用户配合是**已知条件**：本机就是游戏主机，可直接 `/reload` 实测，**不要吝啬开口要日志**，也不要因为怕麻烦用户而继续盲改。

## ⚠️ 频率防护总则（高频 API 调用场景）
- **原则**：凡是可能高频触发的 API 调用流程，设计阶段就必须考虑频率防护——不要等被踢线/刷屏/翻倍后再补
- **判定方法**：设想最坏情况「一帧/一秒内会被触发多少次」；服务器写动作超过 ~1-2 次/s 的一律限频，客户端事件先假设会连发
- **三类范式**（已有实现直接复用）：
  1. **服务器写动作 → 限频队列**：tbQ + OnUpdate 滴出 TB_RATE=0.3s（1.68.2：一帧 24 次 UseContainerItem 被服务器反滥用踢线；1.69.0 交接 API/任务通知同入队）。配套：逐笔验证状态机 tbPending（槽位物品消失=成功/超时 2s=失败）、执行前二次校验防槽位变动、MERCHANT_HIDE 清待办防「卖变用」
  2. **事件驱动 → 去抖窗口/节流**：MERCHANT_SHOW 本客户端连发两次（1.68.1 加 1.5s 去重窗 tbMerchantLast）；BAG_UPDATE 0.5s 节流（1.68.0）。教训：事件驱动功能上线后一律假设事件连发，高频事件必去抖
  3. **执行入口 → 去抖窗口**：EVAL_GO 入口 0.2s 窗口（1.54.1：/run 宏走 RunScript pending 队列，连按堆积松手后陈旧调用冲刷=目标狂切）；窗口可配 cfg.goDebounce 0~1.0（1.54.2），附 EVAL_GO_TRACE 追踪器取证
- **Protected 函数**（SendChatMessage/SpellStopCasting 等）绕行=RunScript 聊天脚本（pending script 队列）——注意 RunScript 本身也是队列，连发聊天同样会被反滥用踢线，通知类输出也要入限频队列

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
- **方案数据**：cfg.war.profiles + activeProfile；EVAL_WAR_ENSURE_PROFILES 做缺省迁移；SavedVariables 自动持久化
- **方案切换**：配置窗侧栏按钮 / 激活方案 [<][>] 选择器 / 战斗信息UI 方案行 / Shift+按宏（Shift 已被切换占用，方案条件里别用 Shift，用 Alt/Ctrl）
- **文本格式**（导入导出/ zs_wq.md）：`# 方案: 名` + `- 技能 | 条件` 行；技能名前 `!` = 停用；解析容忍 md 杂物行
- **函数作用域陷阱**：warCfg/c() 是配置段 local，战斗信息UI 段在其之前 → UI 段用 uiWarCfg()（直接走 EVAL_HELP_CONFIG 全局）；wslots/WAR_SKILLS 是战士段 local，配置段在其后可用
- 受保护函数（CastSpellByName 等）插件**不能调**，施法一律 UseAction(slot) + pcall；谓词返回 true/false/nil，绝不 ==1
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
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（**注意文件名是 EvalHelp.lua 不是 EVAL_HELP.lua**，1.29.0 改名后旧文件 EVAL_HELP.lua 是历史残留；小退/reload 时客户端写入）——**这也是现在读调试日志的地方**（见上方 **F 节**（本客户端 API / 素材真伪清单））

## 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行+方案技能行+条件tooltip+实时条件亮金）| `/eh st` 状态信息UI（状态变量+最近释放条件明细）
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**四个 Tab**：① 全局（日志/界面/帮助）② 一键宏设置（方案栏+技能列表+[添加技能]+[导入导出]；1.20.0 起底部图标选择器/条件输入框/EVAL_WAR_ADD_FROM_UI 已删除，新增技能走编辑窗）③ 工具箱（Toolbox.lua，1.68.0）④ 数据检索（DataSearch.lua，在途）
- 技能编辑窗：点 [编] 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 &/|；条件类型分 5 组（`CTG_5` = **队友/团员状态**：队友血量%/队友蓝量%/队友debuff/队友缺buff + 团员同名四型）
- **队友/团员怎么用**（1.70.47）——两种用法都能独立工作：
  1. **只配条件**（最省事）：技能行加 `队友血量% <60` → 条件自己**扫描全队取血最低者**、切目标、记 `st.allyUnit`，技能就打在他身上。
     解魔法同理：`队友debuff(魔法)` → 找到中魔法的人 → 切过去 → 解他。
  2. **要自定义筛选**：加一行行为 `选取目标:队伍成员`（或 `团队成员`），把筛选条件写在这**一行**上
     （`目标血量<N%` / `目标buff:名` / `目标debuff:名`）→ 按血量升序逐候选判定，选第一个全过的。
  规则按顺序全部执行，所以「选取器 → 治疗 → 驱散」在一次按键里依次生效。
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单仅作下拉置顶（1.24.0 起重扫记录全部上条技能，任意技能可入方案/条件））；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（执行指定方案并且激活，绑多按键）；技能需拖上动作条，改动后 `/eh go rescan`（`/eh war` 是旧命令别名，1.21.1 起已改名 `/eh go`，handler 里仍兼容）；
- 调试：`/eh debug`（跳过原因+触发 trace）| `/eh go list` | `/eh logdump` 调试日志 | `/eh ds`、`/eh ds trace` 数据检索诊断
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
- **本机就是游戏主机**（用户 1.70.46 明确）：EmberVeil 与 TurtleWoW 都在本机，改码 → `node luacheck.js`/`test_engine.js` → `/reload` 实测都在同一台机器上完成（推送 gitee 仅为备份/发布）

## 待开发计划（搁置项）
- **免疫学习器**（✅ 1.36.0 已完成实装：探针验证→事件解析→学习表→引擎跳过；探针 /eh go probe immune/dump 保留作诊断工具）：
  - 结论已排查：无 CombatLog API、无免疫查询函数、wiki 无事件文档页（/wiki/lua/events 404）；但 Frame:RegisterEvent/RegisterAllEvents 可用
  - 设计方向：订阅 CHAT_MSG_* 战斗文字事件，从消息串解析「免疫」→ cfg.war.immune["技能@怪名"] 持久化 → EVAL_RULE_RUN 对同名怪自动跳过该技能（可流血黑白名单 EVAL_BLEED_BLACKLIST 的自动化升级版）
  - 前置步骤：先做探针 /eh go probe（30s 事件抓取写调试日志缓存）拿真实事件名+免疫文本格式，再写解析器；复用 autoFrame OnEvent 三态兼容范式（事件名在 1参/2参/全局 event）
  - 相关基建：st.canBleed 判定链（白名单>黑名单>生物类型排除）

## 项目位置与现状

- **插件目录**：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp\`（1.21 后由 EVAL_HELP 改名 **EvalHelp**；**目录名 == toc 基名**才加载；改名时游戏必须关闭，否则 Access denied）
- **文件结构（1.39.0 起模块化，不是单文件）**：`EvalHelp.toc`（载入顺序 Locales→Core→Engine→EvalHelp→Toolbox→DataSearch）+ `Locales/{zhCN,enUS,ruRU}.lua` + `Core.lua`（输出/i18n/状态采集）+ `Engine.lua`（规则引擎）+ `EvalHelp.lua`（UI/斜杠命令/init）+ `Toolbox.lua`（工具箱 Tab3）+ `DataSearch.lua`（数据检索 Tab4）；配套 `README.md`/`CHANGELOG.md`/`DEVELOPMENT.md` + 测试 `luacheck.js`/`test_engine.js`/`test_stub.lua`/`test_assert.lua`。**行数随开发变化，别当固定值引用**
- **当前版本**：**1.70.44**（已快进合并 master 并推送 origin/gitee）。**在途未提交**：1.70.45（配置窗加宽 + 条件「剩余时间」参数）、1.70.46（UnrealQuest 依赖提示 / 语言来源真 bug / 技能编辑窗高度回归）、1.70.47（队友/团员扫描选取器 + 队友/团员四种状态条件 + debuff 类型下拉）。版本号、CHANGELOG、README 速览表全部**等用户实测确认后再动**
- **★工作流铁律（用户明确定，1.70.15）**：**用户实测验证通过之前，一律不提交、不发版、不推送**——改动只落工作区文件，让用户 `/reload` 直接实测；**报告里也不要催促提交**
- **数据检索 Tab4（在途主功能）**：
  - **数据源**：`UnrealQuestData` 全局表**懒惰读取**（EvalHelp 载入早于 UnrealQuest，载入期拿不到）；对方缺席时整页只显示**安装引导**并**收起全部交互控件**（1.70.46）
  - **硬依赖**：地图/图钉/坐标/tooltip 全部复用 UnrealQuest API（1.70.9 用户拍板，自实现回退已删）；引用它的素材必须**原样抄它的路径常量**
  - **分层**：`EVAL_DS_SEARCH`/`DETAIL`/`SHOWMAP` 逻辑层与 UI 分离，可 node 直测；反查索引懒构建 + 会话缓存
  - **标注层**：统一单池 + 16 类别 + 地图绑定（`DS_ANN_MAX=500`）；**tick 帧必须挂 `WorldFrame`**（挂 UIParent 会因全屏地图隐藏 UI 而整个停摆）
  - **测试**：组 42 系列（搜索/详情/地图/标注层/日志通道）+ 组 61~65（窗口尺寸/剩余时间/依赖提示/真实接线）
- **自查清单**：任何 .lua 改完必跑 `node luacheck.js` + `node test_engine.js`（见上方「⚠️ 最重要教训：改完必须跑语法检查」节）
