-- EvalHelp · Core.lua —— 输出/i18n/状态采集(EVAL_HELP_STATE)/角色状态模块/UI 越界助手
-- 加载顺序见 EvalHelp.toc：Locales → Core → Engine → EvalHelp

-- EvalHelp 1.62.0 —— 全职业工具：通用一键宏（条件规则引擎） + 状态日志 + 战斗信息UI + 配置窗口
--   1.62.0: ★接管动作后移到规则评估之后——AttackTarget 先于规则开弓/进战，冲锋类脱战限定技能可用性瞬间翻 false（探针+存档+手动三连实锤）
--   1.63.0: 可流血改免疫体系驱动——默认 true；目标免疫表命中流血技能（撕裂/割裂/绞袭/斜掠/撕扯）→ false；生物类型硬排除删除（本客户端 UnitCreatureType 不可靠）
--   1.64.0: ★修 Lua 多返回截断——s and pcall(...) 只取第一返回，可用性恒 false/已排队检测失效（1.62.0 的接管时序结论修正：真凶是这个）；可用性只信 noMana 资源信号
--   1.59.0: 姿态下拉按角色姿态栏动态生成（带名称）；去除公共CD终止——符合的规则全部顺序执行，能不能放交给游戏内置
--   1.57.0: 新条件「距下次攻击」（swingLeft 数值比较，复用 1.55.0 挥击计时；无计时数据=不满足）
--   1.55.0: 挥击计时（施法学习同机制）：CHAT_MSG_COMBAT_SELF_HITS 锚定 lastSwing + UnitAttackSpeed 攻速 → 距下次攻击；战斗UI 金色细条+状态UI 攻速行
--   1.54.0: 光环检查四型——自身buff/目标debuff 合并为是/否检查型；新增 目标buff/自身debuff 检查（实时下拉 ●▲）；状态表补 targetBuffs/playerDebuffs
--   1.53.0: 并行执行模型——仅角色技能（动作条法术）占 GCD 终止按键；角色行为/宠物/选目标/物品全部出手后续行
--   1.51.0: 新条件 自动射击/魔杖射击（IsCurrentAction 直查，bool 是/否切换）；★修 COND_BOOL 取反优先级 bug（!普攻 等全部失效）+补 未普攻 解析缺口
--   1.50.0: 自动普攻接管→改名「自动攻击」+ 优先级制（自动射击>射击(魔杖)>攻击，IsUsableAction 不可用自动降档，近战兜底）；cfgCheck 加悬停提示参数（首用=自动攻击说明）
--   1.49.0: 删 EVAL_GO「无有效目标→TargetNearestEnemy」硬编码前置——与 选取目标:最近友方 类规则抢目标；选敌走规则（选取目标:最近敌人 | 无目标）
--   1.48.0: 战士白名单清零——WAR_SKILLS 定义/引用全删，技能清单纯动作条扫描；新装默认方案去战士化（空方案+案例模版引导）；war 阈值缺省键清理
--   1.47.0: 角色行为扩充——取消施法（SpellStopCasting 特殊行为）/自动射击/射击入 cat1；姿态支持序号（姿态:2）；★修 st.autoAttack 采集与接管开关耦合（开关关时 普攻 条件恒 false）
--   1.46.0: 战斗UI 两行图标带合一（方案行下方，8格/行超了换第二行≤16格，冷却数字并入）；★修 RESCAN 重新赋值 wslots 致 EVAL_WSLOTS 导出失效（重扫后 UI 全 ?）——改原地清空
--   1.45.0: 战斗UI技能图标行/重扫核对报告/go状态总览 全部以激活方案技能为准——旧版固定战士白名单（UI_ICONS/WAR_SKILLS 核对）废弃
--   1.44.0: IO 弹窗加「案例模版」选单（EVAL_IO_TEMPLATES 按职业分组，点击直接导入）；原武器战示例按钮并入；修导入上限残留 4→12
--   1.43.0: 角色行为新增「姿态:名称」——姿态栏直切（CastShapeshiftForm 不受保护），不占动作条，已激活守门
--   1.25.0: 新增条件类型「选取目标」（TargetNearestEnemy 等 7 种，官方 Targetting API）；编辑窗类型下拉 24 种
--   1.26.0: 新增条件类型「目标职业」（UnitClass 英文 token 比对，编辑窗多选下拉=或关系；文本格式 目标职业:战士/法师）
--   1.31.0: 目标debuff层数条件（UnitDebuff 第二返回值入 st.targetDebuffs[tex]=层数，非堆叠归一1；
--           有debuff:名>=N / 无debuff:名<N；编辑窗 debuff 条件行加「层」下拉 不限/2-5层）
--   1.30.0: 特殊技能「宠物指令」（rule.skill=宠物:攻击 等 8 种，不占动作条直调 Pet API；EVAL_RULE_RUN/wuse 豁免动作条检查；
--           图标 wicon 兜底 GetPetIcon/问号；战斗信息UI亮金放行；技能下拉追加宠物段；刻意不含放弃/改名/兽栏系）
--   1.29.0: 选取目标扩展「目标的目标」(TargetUnit targettarget) 与「指定名称」(TargetByName，cd.nm 存名)；
--           编辑窗名称下拉=最近5敌名(循环枚举EVAL_NEARBY_ENEMY_NAMES)+自定义输入弹窗EVAL_TN_OPEN；文本 选取目标:指定名称:名
--   1.28.0: 新增条件类型「连击点数」（GetComboPoints，盗贼/德鲁伊专用，数值比较型；文本格式 连击>=3）
--   1.27.0: 光环类条件下拉追加实时项（◆当前目标debuff/○当前自身buff，GameTooltip SetUnitDebuff/SetPlayerBuff 读名）；
--           名称→纹理即时学习持久化 cfg.war.debuffTex，texOf 学习表回退——非动作条光环也能做 有/无debuff/buff 比对
--
-- 参考 OneJudge 开发流程的关键约定：
--   1) 目录规则：Interface/AddOns/EvalHelp/EvalHelp.toc（文件夹名 == toc 基名）
--   2) 插件暴露全局函数，一键宏正文就一行：/run EVAL_HELP()
--   3) 本客户端判断函数返回 true/false/nil（不是老 1.12 的 1/nil），必须宽松真值判断，
--      旧写法 UnitAffectingCombat("player") == 1 在 true 面前永远判假！
--   4) 配置用 SavedVariables（EVAL_HELP_CONFIG），要等 VARIABLES_LOADED 事件后才读。
--   5) 聊天输出用 DEFAULT_CHAT_FRAME:AddMessage；日志走 SavedVariables 环形缓冲（见下）。
--   6) 本客户端没有 /startattack、/castsequence；插件不能调 Protected 函数
--      （CastSpellByName 等），施法走 UseAction(动作条格子)。
--
-- 用法（/eh help 随时查看）：
--   一键宏：游戏内新建宏，正文一行  /run EVAL_GO()   拖到按键上连按（全职业通用框架）
--     前置：把 攻击/战斗姿态/冲锋/压制/断筋/撕裂/战斗怒吼/血性狂暴/猛击/英勇打击 拖上动作条，
--           然后 /eh war rescan 让插件识别槽位（/eh war 查看识别结果）
--     猛击需按住 Alt 再按宏键（本客户端无挥击计时 API，用 Alt 代替出手时机）
--   配置：小地图左侧金色 EH 图标 或 /eh cfg —— 日志开关、一键开关、怒气/血量阈值滑条
--   战斗信息UI：/eh ui —— 血/能量/目标条 + 技能图标行，按住标题栏拖动，滚轮缩放
--   状态信息UI：/eh st —— Cat 式角色状态变量总览（EVAL_HELP_STATE 实时值）
--   其他命令：/eh 输出状态日志 | /eh log 写日志开关 | /eh auto 进出战斗自动输出
--   调试日志：/eh logdump 查看（SavedVariables 环形缓冲；/eh wdebug 后聊天框同步显示决策原因）

-- 1.72.2 删除死掉的 local VERSION = "1.38.1"（定义后从未被引用，属发布流程第 3 步「旧版信息」清理）；
--   版本号唯一来源 = EvalHelp.lua 的 local VERSION + EvalHelp.toc 的 ## Version（VERSION CHECK 守着）。

-- ============ 输出：聊天 + 调试日志 ============

-- ===== ★★★1.73.3 滚轮方向（**单一来源**）=====
-- 本客户端（1.12 系）OnMouseWheel 的方向约定：**向上滚 = +1，向下滚 = -1**（见 EvalHelp war 页脚本的老注释）。
--   ★三个坑必须在这一处解决，各页面自己取值必错一个：
--   ① 处理器既有 `function(a, b)` 写法，也有 `function()` + 全局 arg1 的老写法 → 三种都要认；
--   ② a/b 里还可能是 self（表格/userdata）→ 必须**类型检查**，不能直接当数字；
--   ③ 方向语义：**上滚 = 回到前面**（列表 offset 减、页码减）。1.73.3 实事故：图标库写成了
--      `d > 0 → 下一页`（方向反了），而其余 4 处都是 `off - d` 的正确写法。
--   ★用法：`local dir = EVAL_WHEEL_DIR(a, b)`（0 = 不是滚轮事件）；列表用 `off - dir`，翻页用 `STEP(-dir)`。
function EVAL_WHEEL_DIR(a, b)
  local d = 0
  if type(b) == "number" then d = b
  elseif type(a) == "number" then d = a
  elseif type(arg1) == "number" then d = arg1 end
  if d == 0 then return 0 end
  return (d > 0) and 1 or -1
end

-- ★是否记录 = 默认开；显式关过就尊重用户选择。用 rawget 读，避免被测试桩的元表干扰。
--   兼容三种历史形态：nil（默认开）/ false 布尔（旧 UELog 开关关）/ 表（新缓冲，看 .on）
-- ★★★1.75.8（用户要求）：「调试日志」升级为**整个插件往聊天框说话的总闸门** ——
--   `say`（= EVAL_SAY）跟它联动：关掉 ⇒ 一个字都不刷（命令回复 / 模块如实播报 / 探针输出 / 载入报告全静默）。
--   ★必须声明在 say **之前**：say 要读它（DECL ORDER：引用点写在 local 之前 = 绑成全局 nil，运行时才炸）。
local function logEnabled()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return true end
  local lg = c.log
  if lg == false then return false end
  if type(lg) == "table" then return lg.on ~= false end
  return true
end

-- 裸输出（**不门控**）：只给 EVAL_SAY_FORCE 用
local function chatOut(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffEVAL_HELP:|r " .. tostring(msg))
  end
end

-- 常规出口（**受门控**）。★两个例外必须走 EVAL_SAY_FORCE，否则关掉开关后就再也看不到反馈：
--   ① 日志开关自己的确认行（要让人看得到「怎么开回来」）；
--   ② 「引擎未加载完整」兜底红字（插件坏掉时恰恰最需要出声）。
--   ★与 cfg.wdebug（「方案技能日志」）分工不同：那个只管「说不说决策原因」，本闸门管「说不说话」。
local function say(msg)
  if not logEnabled() then return end
  chatOut(msg)
end

-- ============ 日志通道（1.70.12 重做）============
-- ★为什么不用 UELog：实测该客户端 UELog 调用成功但什么都不落盘——它是「写 Lua log category」，
--   而本客户端以 Shipped 构建运行（命令行无 -log）且 %LOCALAPPDATA%\Azeroth\Saved\Logs 为空目录，
--   日志进了内存/输出窗口就没了。RLog 更差（仅 debug 构建，Shipping 下是 no-op）。
--   结论：落盘通道在这个客户端上都是死的（wiki Helpers 页确认签名）。
-- ★现方案（A+B）：① 主通道 = 写 EVAL_HELP_CONFIG.log 环形缓冲，随 SavedVariables 落盘，
--   开发侧直接读 %LOCALAPPDATA%\Azeroth\Saved\Account\<账号>\SavedVariables\EvalHelp.lua；
--   ② 兜底 = 聊天框输出（/eh logdump 打印）。
--   落盘时机：/reload、小退、退出（SavedVariables 固有语义，无法更早）。
local EH_LOG_MAX = 100 -- ★1.74.31 载入审计：300 → 100（落盘体积 25.6KB → 约 8KB）
-- logEnabled() 已上移到本文件「输出：聊天」段之前 —— 那里的 say 要门控它
--   （DECL ORDER：引用点必须写在 local 之后，否则绑成全局 nil）。
-- 追加一行（带相对时间戳，便于把「我切了图」和日志对上时间轴）
local function logLine(msg)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return end
  if not logEnabled() then return end
  if type(c.log) ~= "table" then c.log = {} end -- 兼容旧布尔值：首次写入时替换成环形表
  local buf = c.log
  local t = (type(GetTime) == "function") and GetTime() or 0
  table.insert(buf, string.format("%.3f %s", t, tostring(msg)))
  while table.getn(buf) > EH_LOG_MAX do table.remove(buf, 1) end
end
-- 打印缓冲（/eh logdump）：环形缓冲按「新→旧」倒序看更顺手
function EVAL_LOG_DUMP(n)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local buf = (type(c) == "table" and type(c.log) == "table") and c.log or {}
  local total = table.getn(buf)
  if total == 0 then return 0 end
  n = tonumber(n) or total
  local from = total - n + 1
  if from < 1 then from = 1 end
  for i = from, total do
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
      DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[日志]|r " .. tostring(buf[i]))
    end
  end
  return total
end
function EVAL_LOG_CLEAR()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) == "table" then c.log = {} end
  return true
end
function EVAL_LOG_COUNT()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local buf = (type(c) == "table" and type(c.log) == "table") and c.log or {}
  return table.getn(buf)
end

-- ============ 国际化（1.34.0 P0，UnrealQuest 同款扁平键值 + 基准回退） ============
-- 契约：① Locales/*.lua 在 toc 里先于主文件加载，各自注册 EVAL_LOCALES[code]；
--       ② L() 只在运行期调用（构建 UI/打印消息时），绝不在文件作用域——加载时语言未解析；
--       ③ 只翻展示层：条件词表/技能名/方案文本/SavedVariables 键永不翻译（数据兼容）；
--       ④ 翻译文本禁用 string.len/sub 裁剪（多字节字符会切成半个）。
local EH_LANG = "zhCN"
local EH_LANG_OK = { zhCN = true, enUS = true, ruRU = true }
local EH_LANG_LABEL = { zhCN = "简体中文", enUS = "English", ruRU = "Русский" }

-- EVAL_L("KEY") / EVAL_L("KEY", a, b)：查当前语言包 → 回退 zhCN → 再缺显示 KEY 本身（可发现性）；
-- 带参数时 pcall 包裹 string.format（翻译文件丢了 %s 也不能炸界面）
function EVAL_L(key, ...)
  local all = EVAL_LOCALES
  local t = all and all[EH_LANG]
  local s = (t and t[key]) or (all and all.zhCN and all.zhCN[key]) or key
  if select("#", ...) == 0 then return s end
  local ok, f = pcall(string.format, s, ...)
  return (ok and type(f) == "string") and f or s
end
local L = EVAL_L

function EVAL_GET_LANG() return EH_LANG end

-- 国旗行透明度刷新（选中=1/未选=0.3）；走全局桥 EVAL_HELP_CFGWIN——cfgWin 是 1900+ 行文件 local，
-- 本函数定义在其声明之前看不到它（local 作用域从声明后开始，1.34.0 实测再踩）
function EVAL_HELP_LANG_REFRESH()
  local cw = EVAL_HELP_CFGWIN
  if not (cw and cw.langBtns) then return end
  for _, fb in ipairs(cw.langBtns) do
    pcall(fb.SetAlpha, fb, (fb.langCode == EH_LANG) and 1 or 0.3)
  end
end

-- 切语言：存 cfg.lang（白名单校验），聊条用新语言提示 /reload（标签构建期一次成型）
function EVAL_SET_LANG(code)
  if not EH_LANG_OK[code] then return false end
  EH_LANG = code
  if EVAL_HELP_CONFIG then EVAL_HELP_CONFIG.lang = code end
  say(L("LANG_RELOAD", EH_LANG_LABEL[code] or code))
  return true
end

-- 语言解析（VARIABLES_LOADED 后调用）：存配置优先 → GetLocale 四码 → GetClientLocale UE 风格 → zhCN
local function ehResolveLang()
  local saved = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.lang
  if type(saved) == "string" and EH_LANG_OK[saved] then EH_LANG = saved return end
  if type(GetLocale) == "function" then
    local ok, loc = pcall(GetLocale)
    if ok and EH_LANG_OK[loc] then EH_LANG = loc return end
  end
  if type(GetClientLocale) == "function" then
    local ok, cl = pcall(GetClientLocale)
    if ok and type(cl) == "string" then
      if string.find(cl, "^ru") then EH_LANG = "ruRU"
      elseif string.find(cl, "^en") then EH_LANG = "enUS"
      else EH_LANG = "zhCN" end
      return
    end
  end
  EH_LANG = "zhCN"
end


local function output(msg)
  say(msg)
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.log then logLine(msg) end
end

-- ============ 状态采集 ============

-- 能量类型名称（1.12 惯例：0=法力 1=怒气 2=集中值 3=能量）
local POWER_LABEL = { [0] = "法力", [1] = "怒气", [2] = "集中值", [3] = "能量" }
local function powerLabel()
  if type(UnitPowerType) == "function" then
    local ok, pt = pcall(UnitPowerType, "player")
    if ok and POWER_LABEL[pt] then return POWER_LABEL[pt] end
  end
  return "能量"
end

-- 当前姿态名（战士=战斗/防御/狂暴，德=形态；无姿态职业返回 nil）
local function currentForm()
  if type(GetNumShapeshiftForms) ~= "function" then return nil end
  local ok, n = pcall(GetNumShapeshiftForms)
  if not ok or not n then return nil end
  for i = 1, n do
    local _, name, active = GetShapeshiftFormInfo(i)
    if active then return name end
  end
  return nil
end

local function pct(cur, max)
  if not max or max <= 0 then return 0 end
  return math.floor(cur / max * 100 + 0.5)
end

-- 采集一组状态，返回 table（所有 API 调用都套 pcall 防御）
local function collectStats()
  local s = {}
  s.time = (type(date) == "function") and date("%H:%M:%S") or tostring(GetTime())

  local _, classEn = UnitClass("player")
  s.class = classEn or "?"
  s.level = UnitLevel("player") or 0

  s.hp     = UnitHealth("player")
  s.hpmax  = UnitHealthMax("player")
  s.hppct  = pct(s.hp, s.hpmax)

  s.power    = UnitMana("player")     -- 本客户端 UnitMana 返回主能量：战士=怒气 贼=能量
  s.powermax = UnitManaMax("player")
  s.powerpct = pct(s.power, s.powermax)
  s.powerlabel = powerLabel()

  -- 宽松真值：UnitAffectingCombat 返回 true/nil
  s.incombat = UnitAffectingCombat("player") and true or false
  s.form     = currentForm()

  if type(UnitAttackSpeed) == "function" then
    local ok, mh = pcall(UnitAttackSpeed, "player")
    if ok then s.swing = mh end
  end

  if UnitExists("target") then
    s.target  = UnitName("target")
    s.thpct   = pct(UnitHealth("target"), UnitHealthMax("target"))
    s.tdead   = UnitIsDead("target") and true or false
    s.tattack = UnitCanAttack("player", "target") and true or false
    if type(UnitClassification) == "function" then s.trank = UnitClassification("target") end
    if type(UnitCreatureType)   == "function" then s.ttype = UnitCreatureType("target") end
  end
  return s
end

-- 格式化成一行日志文本
local function formatStats(s)
  local parts = {}
  parts[#parts + 1] = s.time
  parts[#parts + 1] = string.format("Lv%d %s", s.level, s.class)
  parts[#parts + 1] = string.format("血量 %d/%d (%d%%)", s.hp, s.hpmax, s.hppct)
  parts[#parts + 1] = string.format("%s %d/%d (%d%%)", s.powerlabel, s.power, s.powermax, s.powerpct)
  parts[#parts + 1] = s.incombat and "战斗中" or "非战斗"
  if s.form  then parts[#parts + 1] = "姿态:" .. s.form end
  if s.swing then parts[#parts + 1] = string.format("主手速度:%.1fs", s.swing) end
  if s.target then
    parts[#parts + 1] = string.format("目标[%s] %d%%血 %s %s %s",
      tostring(s.target), s.thpct,
      s.tdead and "已死亡" or "存活",
      s.tattack and "可攻击" or "不可攻击",
      tostring(s.ttype or s.trank or ""))
  else
    parts[#parts + 1] = "无目标"
  end
  return table.concat(parts, " | ")
end

-- ============ 对外主函数（宏入口） ============

-- 一键宏正文：/run EVAL_HELP()
-- 每次调用输出一行状态日志；返回格式化字符串，方便别的插件/宏复用。
function EVAL_HELP()
  EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
  local line = formatStats(collectStats())
  output(line)
  return line
end

-- ============ 进出战斗自动输出 ============

local autoFrame = CreateFrame("Frame", "EVAL_HELPAutoFrame", UIParent)
local function onCombatEvent(entered)
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.auto then
    output((entered and "[进入战斗] " or "[离开战斗] ") .. formatStats(collectStats()))
  end
end

-- ============ 角色状态模块（参考 Cat 插件的全局状态变量设计） ============
-- 一张全局状态表 EVAL_HELP_STATE：每次按键宏入口 / UI 心跳 / 目标切换事件时刷新一次，
-- 一键宏只读这张表、不重复调 API——Cat 的「全局变量直接调用，提高宏的性能」同款思路。
-- 字段对照 Cat：
--   MPInCombat→inCombat  MPInCombatTime→combatTime  MPTargetBleed→canBleed
--   MPPlayerClass→class  MPPlayerRace→race  MPIsBossTarget→isBoss
--   MPAutoAttack→autoAttack（由战士模块补充，需要动作条槽位）
-- 本客户端没有 SuperWoW：MPGetTargetDistance / MPScanEnemy / MPGetMainHandLeft 无对应。

EVAL_HELP_STATE = EVAL_HELP_STATE or {}
local st = EVAL_HELP_STATE

-- 可流血名单（Cat 的 MPmonsterList / 白名单机制）：
--   /run EVAL_BLEED_BLACKLIST["怪名"]=true  → 该怪强制不可流血
--   /run EVAL_BLEED_WHITELIST["怪名"]=true  → 元素/机械里的例外，强制可流血
-- 1.64.1 兼容垫片：本客户端 FrameXML/TargetFrame.lua 引用全局 GetDifficultyColor 但客户端未提供
-- （UnrealQuest ClientAPI 已确认 absent；TargetFrame 懒加载晚于插件 → 全局垫片可到达）。
-- 按 vanilla 语义返回 {r,g,b,font} 难度色表：等级差分档，绿区取 GetQuestGreenRange（兜底 10）。
if type(GetDifficultyColor) ~= "function" then
  function GetDifficultyColor(level)
    local lv = (type(UnitLevel) == "function" and UnitLevel("player")) or 1
    local diff = (tonumber(level) or lv) - lv
    local green = 10
    if type(GetQuestGreenRange) == "function" then
      local okq, g = pcall(GetQuestGreenRange)
      if okq and type(g) == "number" and g > 0 then green = g end
    end
    local c
    if diff >= 5 then c = { r = 1.00, g = 0.10, b = 0.10 }         -- 红（远高于你）
    elseif diff >= 3 then c = { r = 1.00, g = 0.50, b = 0.25 }     -- 橙
    elseif diff >= -2 then c = { r = 1.00, g = 1.00, b = 0.00 }    -- 黄
    elseif -diff <= green then c = { r = 0.25, g = 0.75, b = 0.25 } -- 绿
    else c = { r = 0.50, g = 0.50, b = 0.50 } end                   -- 灰（无经验）
    c.font = "QuestDifficulty_Standard"
    return c
  end
end

EVAL_BLEED_BLACKLIST = EVAL_BLEED_BLACKLIST or {}
EVAL_BLEED_WHITELIST = EVAL_BLEED_WHITELIST or {}
-- 流血技能清单（1.63.0 免疫体系驱动可流血）：战士撕裂 / 贼割裂·绞袭 / 德斜掠·撕扯（含英文兜底）
local BLEED_SKILLS = { "撕裂", "割裂", "绞袭", "斜掠", "撕扯", "Rend", "Rupture", "Garrote", "Rake", "Rip" }

-- 刷新全部角色状态；返回状态表本身
-- ★1.70.47 队伍/团队成员状态：**惰性采集**（用户要求：一键扫描队伍 → 血量/蓝量/buff/debuff 条件）。
--   ★为什么不写在 UPDATE_STATE 里：那个函数被战斗信息UI 每 0.15s 调一次，而一次全团扫描
--     ≈ 40 人 × (32 buff + 16 debuff) ≈ 2000 次 API 调用 → 每秒上万次，违反频率防护总则。
--     所以 UPDATE_STATE 只失效缓存，真正的扫描在这里、由团队条件/团队目标选取触发一次。
--   ★数据来源（EmberVeil wiki globals/Unit，1.70.46 已逐条核对）：
--     · UnitHealth/UnitHealthMax/UnitMana/UnitManaMax/UnitPowerType(unit) 对队伍/团队成员有效，
--       **且超出距离时用 roster 数据**（partypetN 用宠物数据）→ 远处队友的血蓝也读得到。
--     · UnitBuff(unit,1..32) → 图标, 层数；UnitDebuff(unit,1..16) → 图标, 层数, **dispel 类型 token**。
--       ★第三返回值（Magic/Curse/Disease/Poison/…）正是「解魔法/解诅咒」的判据，客户端直接给。
-- ★1.70.47 scope："party"（默认）= 队伍（自己 + party1..N）；"raid" = 团队（raid1..N，已含自己）。
--   「团队」条件要求真在团队里（n==0 时返回空表 → 条件如实报「不在团队中」），
--   不拿队伍成员冒充团队成员；「队伍」在无队伍时退化为只有自己（自我治疗仍可用）。
-- ★★★官方文档现场核对（2026-09 查 emberveil.org/wiki/lua/globals/Group 与 /Raid），两条**反直觉**事实：
--   ① party 索引只有 party1..party4，且**不含自己**（原文 The local player is not a party index）。
--   ② ★GetNumPartyMembers() 在**团队里依然返回「团队人数 - 1」**（原文 In a raid it is still the
--      other-member count (raid size minus one), not 0）→ **不能拿它当 party 循环上界**：
--      40 人团会去试 party1..party39（大多根本不存在）。故这里夹到 4（= 文档给出的 party 索引域）；
--      语义上「队伍成员」= 自己所在小队（在团队里就是本小队）。
--   ③ GetNumRaidMembers() = 团队人数**含自己**（原文 including the local player），非团队时 0 →
--      raid 范围直接 raid1..N、不需要再补 player。
local TEAM_PARTY_MAX = 4
function EVAL_HELP_TEAM_ENSURE(scope)
  local isRaid = (scope == "raid")
  if isRaid then
    if st.teamRaid then return st.teamRaid end
  elseif st.team then
    return st.team
  end
  local list = {}
  local raidN = (type(GetNumRaidMembers) == "function") and (tonumber(GetNumRaidMembers()) or 0) or 0
  local partyN = (type(GetNumPartyMembers) == "function") and (tonumber(GetNumPartyMembers()) or 0) or 0
  local units = {}
  if isRaid then
    for i = 1, raidN do table.insert(units, "raid" .. i) end -- raidN 已含自己
  else
    table.insert(units, "player") -- ★partyN 是**别人**（文档：自己不是 party 索引），自己另算
    if partyN > TEAM_PARTY_MAX then partyN = TEAM_PARTY_MAX end -- ★团队里 partyN 会是「团人数-1」
    for i = 1, partyN do table.insert(units, "party" .. i) end
  end
  for ui, u in ipairs(units) do
    if UnitExists(u) then
      local rec = { unit = u, name = UnitName(u) or u }
      -- ★1.71.3 成员职业 / 小队号（供「职业多选」「队伍多选」过滤，用户要求）：
      --   团队优先问 GetRaidRosterInfo —— **一次调用同时拿到小队号与职业**。官方文档现场核对（Raid 页）：
      --   返回 name, rank, **subgroup(1-8；未知按 1)**, level, classLoc, **classFile(WARRIOR/MAGE/…)**, zone, online, isDead；
      --   ★非团队（或下标越界）时**只返回一个 nil** → 队伍成员走 UnitClass 那条路。
      --   队伍里没有「小队号」概念（小队多选只出现在**团员**条件上）→ 恒记 1。
      if isRaid and type(GetRaidRosterInfo) == "function" then
        local okr, _rn, _rr, sub, _rl, _rcl, rcfile = pcall(GetRaidRosterInfo, ui)
        if okr then
          rec.grp = tonumber(sub) or 1
          if type(rcfile) == "string" and rcfile ~= "" then rec.cls = rcfile end
        end
      end
      if not rec.cls and type(UnitClass) == "function" then
        local okc, _cl, cfile = pcall(UnitClass, u)
        if okc and type(cfile) == "string" and cfile ~= "" then rec.cls = cfile end
      end
      if not isRaid then rec.grp = 1 end
      local hp, hpmax = UnitHealth(u), UnitHealthMax(u)
      rec.hp, rec.hpMax = tonumber(hp) or 0, tonumber(hpmax) or 0
      rec.hpPct = (rec.hpMax > 0) and (rec.hp / rec.hpMax * 100) or 0
      local mp, mpmax = UnitMana(u), UnitManaMax(u)
      rec.power, rec.powerMax = tonumber(mp) or 0, tonumber(mpmax) or 0
      rec.powerPct = (rec.powerMax > 0) and (rec.power / rec.powerMax * 100) or 0
      if type(UnitPowerType) == "function" then
        local okp, pt = pcall(UnitPowerType, u)
        if okp then rec.powerType = pt end
      end
      rec.buffs, rec.debuffs = {}, {}
      if type(UnitBuff) == "function" then
        for i = 1, 32 do
          local okb, tex, apps = pcall(UnitBuff, u, i)
          if not okb or not tex then break end
          rec.buffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
        end
      end
      if type(UnitDebuff) == "function" then
        for i = 1, 16 do
          local okd, tex, apps, dtype = pcall(UnitDebuff, u, i)
          if not okd or not tex then break end
          rec.debuffs[tex] = {
            n = (type(apps) == "number" and apps > 0) and apps or 1,
            t = (type(dtype) == "string" and dtype ~= "") and dtype or nil,
          }
        end
      end
      table.insert(list, rec)
    end
  end
  if isRaid then st.teamRaid = list else st.team = list end
  return list
end

-- 按 unit 取已采集的成员记录（队伍/团队条件会设 st.teamCur，后续条件按它求值）
-- ★1.70.47 两个范围的表都要找（选的是 raidN 还是 partyN 由 cd.name 决定）
--   ★不要写成 ipairs({ st.team, st.teamRaid })——两个缓存里常有一个是 nil，
--     而 Lua 的 ipairs 遇到 nil 洞会**立刻停止**（不是跳过）→ 有团队缓存时会一个都找不到。
--     （组 66 当场抓到：只扫团队时 raid 成员查不到。）
function EVAL_HELP_TEAM_GET(unit)
  if not unit then return nil end
  if st.team then
    for _, r in ipairs(st.team) do if r.unit == unit then return r end end
  end
  if st.teamRaid then
    for _, r in ipairs(st.teamRaid) do if r.unit == unit then return r end end
  end
  return nil
end

function EVAL_HELP_UPDATE_STATE()
  local now = GetTime()
  st.now = now

  -- 玩家基础信息（Cat: MPPlayerClass / MPPlayerRace）
  st.playerName = UnitName("player")
  st.level = UnitLevel("player")
  if type(UnitClass) == "function" then
    local okc, loc, eng = pcall(UnitClass, "player")
    if okc then st.classLoc, st.class = loc, eng end
  end
  if type(UnitRace) == "function" then
    local okr, rloc, reng = pcall(UnitRace, "player")
    if okr then st.raceLoc, st.race = rloc, reng end
  end

  -- 血量 / 能量（数值 + 百分比）
  st.hp, st.hpMax = UnitHealth("player"), UnitHealthMax("player")
  st.hpPct = (st.hpMax and st.hpMax > 0) and (st.hp / st.hpMax * 100) or 0
  st.power, st.powerMax = UnitMana("player"), UnitManaMax("player")
  st.powerPct = (st.powerMax and st.powerMax > 0) and (st.power / st.powerMax * 100) or 0
  if type(UnitPowerType) == "function" then
    local okp, pt = pcall(UnitPowerType, "player")
    if okp then st.powerType = pt end -- 0法力 1怒气 2集中值 3能量
  end

  -- 连击点（1.28.0）：仅盗贼/德鲁伊有；当前目标非连击目标或非连击职业时 API 返回 0
  st.combo = (type(GetComboPoints) == "function") and GetComboPoints() or 0

  -- 战斗状态 + 进战时间（Cat: MPInCombat / MPInCombatTime）
  st.inCombat = UnitAffectingCombat("player") and true or false
  if st.inCombat then
    if not st.combatStart then st.combatStart = now end
    st.combatTime = now - st.combatStart
  else
    st.combatStart = nil
    st.combatTime = 0
  end

  -- 姿态 / 形态：formIndex=0 表示无姿态
  st.formIndex, st.form = 0, nil
  if type(GetShapeshiftFormInfo) == "function" then
    for i = 1, 4 do
      local okf, icon, fname, active = pcall(GetShapeshiftFormInfo, i)
      if not okf or not fname then break end
      if active then st.formIndex, st.form = i, fname break end
    end
  end

  -- 攻速（1.55.0 挥击计时）：UnitAttackSpeed 主手/副手秒每击（含急速修正）；无武器/查询失败=nil
  if type(UnitAttackSpeed) == "function" then
    local oks, mh, oh = pcall(UnitAttackSpeed, "player")
    st.atkSpd = (oks and type(mh) == "number" and mh > 0) and mh or nil
    st.atkSpdOff = (oks and type(oh) == "number" and oh > 0) and oh or nil
  end
  -- ★1.74.30 远程射速（1.74.30 射击计时）：`UnitRangedDamage("player")` 第 1 返回 = 秒/击（探针真机实测定案）
  --   与近战 atkSpd **并列**（不覆盖）：到底用哪个由 EVAL_SWING_KIND() 按「是否自动射击中」现算。
  if type(EVAL_SHOT_API_SPEED) == "function" then
    st.atkSpdRanged = EVAL_SHOT_API_SPEED()
  end

  -- 光环纹理集合（配置化条件的 hasBuff/noBuff/hasDebuff/noDebuff 用；
  -- 键 = 纹理路径，与「动作条图标 == 光环图标」比对法一致）
  st.playerBuffs = {}
  if type(GetPlayerBuff) == "function" then
    for i = 0, 31 do
      local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
      if not okb or type(bi) ~= "number" or bi < 0 then break end
      local okt, tex = pcall(GetPlayerBuffTexture, bi)
      if okt and tex then st.playerBuffs[tex] = true end
    end
  end
  -- 1.32.10 兜底：UnitBuff("player",i) 1 基索引枚举（与目标 debuff 的 UnitDebuff 同族，已验证可用）——
  -- 药品/食物类 buff 若被 GetPlayerBuff 过滤列表漏掉，这里补进纹理集合（条件匹配才找得到）
  if type(UnitBuff) == "function" then
    for i = 1, 32 do
      local oku, tex, apps = pcall(UnitBuff, "player", i) -- 1.70.1 起存层数（第二返回值；非堆叠归一 1）
      if not oku or not tex then break end
      st.playerBuffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
    end
  end
  st.targetDebuffs = {} -- 1.31.0 起存层数（数字）：UnitDebuff 第二返回值；非堆叠 debuff 返回 0 → 归一化为 1
  -- ★1.74.6 「负面类型」支持（用户：「自身/目标debuff 条件要参考队伍debuff 支持 debuff 负面类型」）：
  --   ★层数表**保持数字**（既有读侧一字不改），类型另存一张 tex→可驱散 token 的**平行表**（UnitDebuff 第 3 返回）。
  --     队伍/团员的记录本来就是 {t=类型, n=层数}，所以这张表只是把同一条信息补齐到自身/目标身上。
  st.targetDebuffType = {}
  if UnitExists("target") and type(UnitDebuff) == "function" then
    for i = 1, 16 do
      local okd, tex, apps, dtype = pcall(UnitDebuff, "target", i)
      if not okd or not tex then break end
      st.targetDebuffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
      if type(dtype) == "string" and dtype ~= "" then st.targetDebuffType[tex] = dtype end
    end
  end
  st.targetBuffs = {} -- 1.54.0 目标 buff 纹理集合（UnitBuff 1 基索引）；1.70.1 起存层数
  if UnitExists("target") and type(UnitBuff) == "function" then
    for i = 1, 16 do
      local okb, tex, apps = pcall(UnitBuff, "target", i)
      if not okb or not tex then break end
      st.targetBuffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
    end
  end
  st.playerDebuffs = {} -- 1.54.0 自身 debuff 纹理集合；1.70.1 起存层数
  st.playerDebuffType = {} -- ★1.74.6 同上：自身 debuff 的「负面类型」平行表（层数表仍是数字）
  if type(UnitDebuff) == "function" then
    for i = 1, 16 do
      local okd, tex, apps, dtype = pcall(UnitDebuff, "player", i)
      if not okd or not tex then break end
      st.playerDebuffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
      if type(dtype) == "string" and dtype ~= "" then st.playerDebuffType[tex] = dtype end
    end
  end

  -- ★1.70.47 队伍/团队：这里**只失效缓存、不做扫描**（用户要求：一键扫描队伍 → 血/蓝/buff/debuff 条件）。
  --   本函数会被战斗信息UI 每 0.15s 调一次；40 人团 × (32 buff + 16 debuff) ≈ 2000 次 API 调用，
  --   每秒上万次——严重违反频率防护总则。真正扫描放在 EVAL_HELP_TEAM_ENSURE()，
  --   由「团队条件求值 / 团队目标选取」在**按宏那一轮**触发一次。
  st.teamEpoch = (st.teamEpoch or 0) + 1 -- 仅供诊断/断言
  st.team, st.teamRaid, st.teamCur = nil, nil, nil

  -- ★1.70.45 自身光环「剩余秒数」表（用户要求：buff 类条件加剩余时间检查）。
  --   数据源**只有** GetPlayerBuff* 家族（wiki globals/Buff 明文）：
  --     GetPlayerBuff(i, "HELPFUL"/"HARMFUL") → 内部槽位（0-31 helpful / 32-47 harmful，-1=无）
  --     GetPlayerBuffTexture(bi)          → 图标（与动作条图标比对法同源，故表键仍是纹理）
  --     GetPlayerBuffTimeLeft(bi)         → 剩余**秒**（越界/空槽/无限/无结束时间 → 0）
  --   ★其他单位（目标）没有时长 API：UnitBuff/UnitDebuff 只返回 图标+层数 ——
  --     所以本表只覆盖自身，目标侧的时间检查在求值阶段如实返回 false（见 Engine condOne）。
  --   频率防护：本段随状态刷新走（事件/节流驱动），不做逐帧扫描；每轮最多 32+16 次 pcall。
  st.playerBuffLeft, st.playerDebuffLeft = {}, {}
  if type(GetPlayerBuff) == "function" and type(GetPlayerBuffTimeLeft) == "function"
     and type(GetPlayerBuffTexture) == "function" then
    local function scanLeft(filter, into)
      for i = 0, 31 do
        local okb, bi = pcall(GetPlayerBuff, i, filter)
        if not okb or type(bi) ~= "number" or bi < 0 then break end
        local okt, tex = pcall(GetPlayerBuffTexture, bi)
        local okl, left = pcall(GetPlayerBuffTimeLeft, bi)
        if okt and tex and okl and type(left) == "number" then into[tex] = left end
      end
    end
    scanLeft("HELPFUL", st.playerBuffLeft)
    scanLeft("HARMFUL", st.playerDebuffLeft)
  end

  -- 修饰键（猛击 Alt 门等）
  st.alt   = (type(IsAltKeyDown) == "function") and IsAltKeyDown() and true or false
  st.shift = (type(IsShiftKeyDown) == "function") and IsShiftKeyDown() and true or false
  st.ctrl  = (type(IsControlKeyDown) == "function") and IsControlKeyDown() and true or false

  -- 目标信息（Cat: 目标是否可攻击 / MPTargetBleed / MPIsBossTarget）
  st.hasTarget = UnitExists("target") and true or false
  if st.hasTarget then
    st.targetName = UnitName("target")
    st.tLevel = UnitLevel("target")
    st.tHp, st.tHpMax = UnitHealth("target"), UnitHealthMax("target")
    st.tHpPct = (st.tHpMax and st.tHpMax > 0) and (st.tHp / st.tHpMax * 100) or 0
    st.tDead = UnitIsDeadOrGhost("target") and true or false
    st.canAttack = (not st.tDead) and UnitCanAttack("player", "target") and true or false
    st.tInCombat = UnitAffectingCombat("target") and true or false
    st.tCreatureType = UnitCreatureType("target")
    -- 可流血（1.63.0 用户定新机制）：白名单 > 黑名单 > 【默认 true】；
    -- 目标在免疫体系内、且免疫的是【流血技能】（撕裂/割裂/绞袭/斜掠/撕扯…）→ false。
    -- 旧版按生物类型硬排除（元素/机械）已删——本客户端 UnitCreatureType 返回值不可靠（用户实测黑暗犬被误判不可流血）。
    local war2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    if EVAL_BLEED_WHITELIST[st.targetName or ""] then
      st.canBleed = true
    elseif EVAL_BLEED_BLACKLIST[st.targetName or ""] then
      st.canBleed = false
    else
      st.canBleed = true
      if st.targetName and war2 and war2.immune then
        for _, bs in ipairs(BLEED_SKILLS) do
          if war2.immune[bs .. "@" .. st.targetName] then st.canBleed = false break end
        end
      end
    end
    -- 精英 / Boss
    st.tClassification = (type(UnitClassification) == "function") and UnitClassification("target") or nil
    st.isBoss = (st.tClassification == "worldboss") and true or false
    st.isElite = (st.tClassification == "elite" or st.tClassification == "rareelite"
      or st.tClassification == "rare") and true or false
    -- 目标职业（1.26.0）：UnitClass 返回 本地化名, 英文token(WARRIOR 等), 职业id；条件比对用英文 token（跨语言稳定）
    local okc2, tclsLoc, tclsEng = pcall(UnitClass, "target")
    st.tClassName = (okc2 and tclsLoc) or nil
    st.tClass = (okc2 and tclsEng) or nil
    -- 目标友善度（1.23.0）：UnitReaction ≤3敌对 / 4中立 / ≥5友善；API 缺失或无目标 = 全 false
    local okr, react = pcall(UnitReaction, "target", "player")
    st.tReaction = (okr and type(react) == "number") and react or nil
    st.tHostile  = (st.tReaction ~= nil and st.tReaction <= 3) and true or false
    st.tNeutral  = (st.tReaction == 4) and true or false
    st.tFriendly = (st.tReaction ~= nil and st.tReaction >= 5) and true or false
  else
    st.targetName, st.tLevel, st.tHp, st.tHpMax, st.tHpPct = nil, 0, 0, 0, 0
    st.tDead, st.canAttack, st.tInCombat = false, false, false
    st.tCreatureType, st.canBleed = nil, false
    st.tClassification, st.isBoss, st.isElite = nil, false, false
    st.tReaction, st.tHostile, st.tNeutral, st.tFriendly = nil, false, false, false
    st.tClassName, st.tClass = nil, nil
    st.tCastName, st.tCastStart = nil, nil -- 1.40.0 无目标即清施法状态
  end
  st.tRange = EVAL_T_RANGE() -- 1.37.0 目标距离分档（在 if/else 之后、return 之前；误插 else 分支内恒 nil 已修）
  -- 1.38.0 施法中跟踪过期清理（事件丢 STOP 时兜底；castUntil nil=无限期读条）
  -- 1.40.0 目标施法状态：超时兜底（事件丢结束时 12s 自清；无目标在 else 分支已清名）
  if st.tCastStart and GetTime() - st.tCastStart > 12 then st.tCastName, st.tCastStart = nil, nil end
  if st.castName and st.castUntil and GetTime() > st.castUntil then st.castName, st.castUntil = nil, nil end
  return st
end

-- 窗口越界检测：GetLeft/Right/Top/Bottom 返回缩放后屏幕坐标，UIParent 尺寸要乘 effectiveScale
-- 再比较（OneJudge 的坐标系换算）。判定：窗口中心在屏幕外，或四边可见部分不足 40px → 视为飞出屏幕。
local function uiOffscreen(f)
  if not f then return true end
  local okl, l = pcall(f.GetLeft, f)
  local okr, r = pcall(f.GetRight, f)
  local okt, t = pcall(f.GetTop, f)
  local okb, b = pcall(f.GetBottom, f)
  if not (okl and okr and okt and okb and l and r and t and b) then return false end
  local okw, sw = pcall(UIParent.GetWidth, UIParent)
  local okh, sh = pcall(UIParent.GetHeight, UIParent)
  if not (okw and okh and sw and sh) then return false end
  local oke, es = pcall(f.GetEffectiveScale, f)
  local k = (oke and type(es) == "number" and es > 0) and es or 1
  sw, sh = sw * k, sh * k
  local cx, cy = (l + r) / 2, (t + b) / 2
  if cx < 0 or cx > sw or cy < 0 or cy > sh then return true end
  if r < 40 or l > sw - 40 or t < 40 or b > sh - 40 then return true end
  if t > sh - 8 then return true end -- 顶边超出屏幕上缘（标题栏被裁，1.12.1 补）
  return false
end

-- ===== 跨模块导出（Engine/EvalHelp 用；toc 加载顺序保证先注册） =====
EVAL_SAY = say
-- ★★★1.75.8：**门控版 + 常开版两个出口**（模块自带的 say 全部委托 EVAL_SAY ⇒ 一处门控、全插件生效）
EVAL_SAY_FORCE = chatOut  -- 不受「调试日志」管：只给开关自身的反馈 + 崩溃兜底用
EVAL_CHAT_ON = logEnabled -- 给「自己直接写聊天框」的模块读总闸门（如 tools/SimpleMap.lua 的 P）
EVAL_LOGLINE = logLine
EVAL_UIOFFSCREEN = uiOffscreen
EVAL_POWERLABEL = powerLabel
EVAL_CURRENTFORM = currentForm
EVAL_AUTOFRAME = autoFrame
EVAL_ON_COMBAT = onCombatEvent
EVAL_FORMAT_STATS = formatStats
EVAL_COLLECT_STATS = collectStats
EVAL_RESOLVE_LANG = ehResolveLang

-- 宏入口兜底（1.44.1）：Engine.lua 若未成功加载（改码中途 /reload 读到半成品、角色插件列表未启用等），
-- /run EVAL_GO() 不再弹「nil value」红框，改聊天框给出可操作的排查指引。
-- 正常加载时 Engine.lua 末尾的正式 EVAL_GO 会覆盖本兜底；EVAL_ENGINE_OK 是加载哨兵。
function EVAL_GO()
  EVAL_SAY_FORCE("|cffff0000EvalHelp 引擎未加载完整|r（宏走了兜底）：请 /reload 一次；反复出现 → 检查角色选择界面的插件列表是否对当前角色启用了 EvalHelp")
end

-- ===== 载入耗时探针 + 存档残渣清理（1.74.31；用户：「审计下载入速度有点慢 → 先取证 + 零风险清理」）=====
-- ★★★1.74.31（阶段 0）载入审计：把「登录/重载慢」拆成可量化的段 ——
--   ① `EVAL_LOAD_T0`（Locales/zhCN.lua **第 1 行**）= 整个插件开始加载；
--   ② `EVAL_LOAD_MARK("files")`（toc **最后一个模块** tools/RareWatch.lua 末尾）= 全部源码编译+执行完；
--   ③ `EVAL_LOAD_MARK("vars")`（VARIABLES_LOADED）= SavedVariables 已恢复；
--   ④ `EVAL_LOAD_MARK("world")`（PLAYER_ENTERING_WORLD）= 进世界；
--   ⑤ `EVAL_LOAD_MARK("init")`（进世界后**时钟可用**的第一帧）+ 打印报告（不新增事件注册，用一次性 OnUpdate）。
-- ★★★真机定案（用户两次 /reload 的报告）：**本客户端在插件加载阶段 GetTime() 恒 0** ——
--   旧报告因此打出「源码加载 0ms ｜ SavedVariables 恢复 0ms ｜ 初始化 390444014ms」，那个 39 万秒
--   = 游戏运行时长（t0/files/vars 三点读数都是 0，init 是进世界后的真实时钟）⇒ **载入期毫秒数根本量不出来**。
--   ⇒ 现在的规矩：**时钟没启动就如实写「测不出」**（绝不拿 0 当「很快」、也绝不把运行时长当「初始化耗时」），
--     并摊开原始读数（GetTime / GetGameTime / time / 墙钟秒）——本客户端只有这几个时间源，
--     下一版要靠这些读数判断 GetGameTime 或 time() 能否顶替（★一次只验一个假设）。
local LOADM = { t0 = nil, files = nil, vars = nil, world = nil, init = nil, reported = false }
local LOAD_RAW = { t0 = {}, files = {}, vars = {}, world = {}, init = {} } -- ★每个打点的原始读数（取证）
local LOAD_PROBE_KEYS = { "iconDump", "shProbe", "shVariantProbe", "probeEvents" } -- ★唯一来源（清理/断言都读它）
-- ★★★1.74.31 收尾：**调试残渣键**（探针的「落盘证人」）：**只有 /eh 存档清理（force）才清**。
--   ★为什么不自动清：它们是某些判据的证人，留着才有「事后读回来」的能力；但它们**全是调试产物**、不进任何功能逻辑。
--   ★★**不许把真状态键写进来**（ds/tb/war/ui/title/share/log/st … 那些删了就是丢用户配置）。
local LOAD_RESIDUE_KEYS = {
  "probeLog", "shColorProbe", "shTitleColorProbe", "shareIconProbe",
  "shareProbe", "shareProbeHover", "shareProbeRaw", "shareProbeVerdicts",
  "shareSealDemo", "shareCreatorOpen", "loadStat", "guideSeen",
  -- ★1.75.2 追踪探针的**专属持久读数**（最近 40 行；存在的理由见 Engine.lua 的 TRK_OUT_MAX 注释：
  --   调试日志环只有 100 条 + `[DS]` 每 ~10 秒一行 ⇒ 探针读数 ~17 分钟就被冲掉，必须另存一份）
  "trkProbe",
}

function EVAL_LOAD_PROBE_KEYS() return LOAD_PROBE_KEYS end
function EVAL_LOAD_RESIDUE_KEYS() return LOAD_RESIDUE_KEYS end

local function loadRawRead()
  local o = {}
  o.gt = (type(GetTime) == "function") and GetTime() or nil
  o.ggt = (type(GetGameTime) == "function") and GetGameTime() or nil
  o.ep = (type(time) == "function") and time() or nil
  o.wall = (type(date) == "function") and date("%H:%M:%S") or nil
  return o
end

function EVAL_LOAD_MARK(what)
  local k = tostring(what or "?")
  local r = loadRawRead()
  LOAD_RAW[k] = r
  local t = (type(r.gt) == "number") and r.gt or 0
  if k == "t0" then LOADM.t0 = rawget(_G, "EVAL_LOAD_T0") -- ★显式重读起点（断言要造确定时间轴）
  elseif not LOADM.t0 then LOADM.t0 = rawget(_G, "EVAL_LOAD_T0") end
  if k == "files" then LOADM.files = t
  elseif k == "vars" then LOADM.vars = t
  elseif k == "world" then LOADM.world = t
  elseif k == "init" then LOADM.init = t end
  return t
end

-- ★t0 的原始读数在**第一个文件**（Locales/zhCN.lua 第 1 行）就采好了（那时 Core.lua 还没载入，调不了函数）
-- ⇒ 这里把它并入 LOAD_RAW.t0；读值口才能把「起点的四个时间源」一并打出来。
if not LOAD_RAW.t0.ep then
  LOAD_RAW.t0 = { gt = rawget(_G, "EVAL_LOAD_T0"), ggt = rawget(_G, "EVAL_LOAD_T0_GGT"),
                  ep = rawget(_G, "EVAL_LOAD_T0_EP"), wall = rawget(_G, "EVAL_LOAD_T0_WALL") }
end

-- 读值口（断言 / 诊断用；**不改状态**）
function EVAL_LOAD_STATE()
  local function p(k)
    local r = LOAD_RAW[k] or {}
    return r.gt, r.ggt, r.ep, r.wall
  end
  local a1, a2, a3, a4 = p("t0")
  local b1, b2, b3, b4 = p("files")
  local c1, c2, c3, c4 = p("vars")
  local d1, d2, d3, d4 = p("world")
  local e1, e2, e3, e4 = p("init")
  return { t0 = LOADM.t0, files = LOADM.files, vars = LOADM.vars, world = LOADM.world, init = LOADM.init,
           t0GT = a1, t0GGT = a2, t0EP = a3, t0WALL = a4,
           filesGT = b1, filesGGT = b2, filesEP = b3, filesWALL = b4,
           varsGT = c1, varsGGT = c2, varsEP = c3, varsWALL = c4,
           worldGT = d1, worldGGT = d2, worldEP = d3, worldWALL = d4,
           initGT = e1, initGGT = e2, initEP = e3, initWALL = e4 }
end

-- 探针写结果时打日期戳（清理按它判过期）
function EVAL_PROBE_STAMP()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  c.probeAt = (type(date) == "function") and date("%Y-%m-%d") or "?" -- 本客户端有 date（os.date 的全局别名）
  return c.probeAt
end

-- 清理探针残渣：force=true 全清（手动命令）；否则「iconDump 一律清 + 其余只清过期（非当天）」
function EVAL_LOAD_CLEANUP(force)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return 0, 0 end
  local today = (type(date) == "function") and date("%Y-%m-%d") or nil
  local stamp = tostring(c.probeAt or "")
  local killed, approxBytes = 0, 0
  -- ① 探针数据键：iconDump 一律清；其余「过期（非当天）」才清
  for i = 1, table.getn(LOAD_PROBE_KEYS) do
    local k = LOAD_PROBE_KEYS[i]
    if c[k] ~= nil then
      local kill = force and true or false
      if not kill then
        if k == "iconDump" then kill = true -- ★一次性采集：AI 读完就不需要
        elseif today ~= nil and (stamp == "" or stamp < today) then kill = true end -- 过期（非当天）
      end
      if kill then
        if type(c[k]) == "table" then
          local m = 0 for _ in pairs(c[k]) do m = m + 1 end
          approxBytes = approxBytes + m * 20
        end
        c[k] = nil
        killed = killed + 1
      end
    end
  end
  -- ② 调试残渣键：**只有 force**（/eh 存档清理）才清 —— 它们是判据的「落盘证人」，
  --    自动清会让「事后读回来」的能力无声消失；真状态键不在这个清单里（见 LOAD_RESIDUE_KEYS 注释）。
  if force then
    for i = 1, table.getn(LOAD_RESIDUE_KEYS) do
      local k = LOAD_RESIDUE_KEYS[i]
      if c[k] ~= nil then
        if type(c[k]) == "table" then
          local m = 0 for _ in pairs(c[k]) do m = m + 1 end
          approxBytes = approxBytes + m * 20
        elseif type(c[k]) == "string" then
          approxBytes = approxBytes + string.len(c[k])
        end
        c[k] = nil
        killed = killed + 1
      end
    end
  end
  if killed > 0 and type(EVAL_LOGLINE) == "function" then
    pcall(EVAL_LOGLINE, string.format("[载入] 已清理存档残渣 %d 个键（估算 %.1f KB）", killed, approxBytes / 1024))
  end
  return killed, approxBytes
end

-- 报告：一般 **3 行**；★载入期时钟不可用时**如实改写第 1 行并追加原始读数行**（取证），
--   绝不打出「0ms」这种假读数、也绝不把游戏运行时长当成「初始化耗时」。
-- 报告：**默认 1 行摘要**（登录不再刷屏）；full=true = 完整取证（/eh 载入报告）。
--   ★完整取证**始终写进调试日志**（聊天只给摘要）⇒ 深挖时 /eh logdump 或 /eh 载入报告 随时拿得到。
--   ★读数规矩不变：毫秒时钟没启动就如实写「测不出」，绝不拿 0 或游戏运行时长冒充。
function EVAL_LOAD_REPORT(sayFn, full)
  local S = EVAL_LOAD_STATE()
  local t0 = S.t0 or rawget(_G, "EVAL_LOAD_T0")
  local function ms(a, b)
    if not (a and b) then return "—" end
    return string.format("%.0fms", (b - a) * 1000)
  end
  -- ★判据：t0 / files / vars 三点的 **GetTime 原始读数** 任一缺失或为 0 ⇒ 载入期时钟没启动 ⇒ 毫秒测不出
  local dead = false
  if type(S.t0GT) ~= "number" or S.t0GT == 0 then dead = true end
  if type(S.filesGT) ~= "number" or S.filesGT == 0 then dead = true end
  if type(S.varsGT) ~= "number" or S.varsGT == 0 then dead = true end
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local n, topK, topB = 0, nil, 0
  if type(c) == "table" then
    for k, v in pairs(c) do
      n = n + 1
      local s = 0
      if type(v) == "table" then local m = 0 for _ in pairs(v) do m = m + 1 end s = m * 20
      elseif type(v) == "string" then s = string.len(v) end
      if s > topB then topB, topK = s, tostring(k) end
    end
  end
  local killed, bytes = EVAL_LOAD_CLEANUP()
  -- ★★抽样累计（写进存档）：源码段 = t0→files，存档段 = files→vars。
  --   平均秒差就是该段真实时长的**无偏估计** ⇒ 把 1 秒分辨率的钟变成可用尺子（参考卷 §13.5）。
  local dA = (type(S.t0EP) == "number" and type(S.filesEP) == "number") and (S.filesEP - S.t0EP) or nil
  local dB = (type(S.filesEP) == "number" and type(S.varsEP) == "number") and (S.varsEP - S.filesEP) or nil
  local stat = nil
  if type(c) == "table" and (dA or dB) then
    stat = c.loadStat
    if type(stat) ~= "table" then stat = { n = 0, a = 0, b = 0, ta = 0, tb = 0 } c.loadStat = stat end
    stat.n = (stat.n or 0) + 1
    if dA then stat.ta = (stat.ta or 0) + dA if dA > 0 then stat.a = (stat.a or 0) + 1 end end
    if dB then stat.tb = (stat.tb or 0) + dB if dB > 0 then stat.b = (stat.b or 0) + 1 end end
  end
  local sA, sB, sn = nil, nil, 0
  if type(stat) == "table" and (stat.n or 0) > 0 then
    sn = stat.n
    sA = (tonumber(stat.ta) or 0) / sn
    sB = (tonumber(stat.tb) or 0) / sn
  end
  -- ① 摘要行（登录只打它）
  local sum
  if sA then
    sum = string.format("[载入] 源码段均 %.2f 秒 ｜ 存档段均 %.2f 秒（样本 %d）", sA, sB, sn)
  else
    sum = "[载入] 秒级样本不足（本客户端载入期只有 1 秒分辨率的 time()）"
  end
  sum = sum .. string.format(" ｜ 存档 %d 键 / 最大 %s（估算 %.1f KB） ｜ 本次清残渣 %d 个", n, tostring(topK or "—"), topB / 1024, killed)
  -- ② 完整取证（始终进日志）
  local detail = { sum }
  if dead then
    table.insert(detail, string.format("[载入] 载入期时钟未启动（GetTime() 原始读数 = 0，实测）⇒ 源码/存档两段毫秒级**测不出**；进世界→首帧 %s",
      ms(S.world, S.init)))
  else
    table.insert(detail, string.format("[载入] 源码加载 %s ｜ SavedVariables 恢复 %s ｜ 初始化 %s ｜ 合计 %s",
      ms(t0, S.files), ms(S.files, S.vars), ms(S.vars, S.init), ms(t0, S.init)))
  end
  table.insert(detail, string.format("[载入] SavedVariables 顶层键 %d 个；最大键 %s（估算 %.1f KB）", n, tostring(topK or "—"), topB / 1024))
  -- ★秒级时钟（time()，1 秒分辨率）的正确用法：同秒 ⇒ 这一段 <1 秒（上界，可用）；
  --   跨秒 ⇒ **不构成下界**（边界前 1ms 采样也会跨秒）⇒ 绝不写「至少 1 秒」；真值靠上面的抽样平均。
  --   ★起点的原始读数可能缺 ⇒ 三种组合逐一尝试，能给多少给多少（不许因为缺一个读数就一行不打）。
  local w0, w1, e0, e1 = S.t0WALL, S.varsWALL, S.t0EP, S.varsEP
  if not (w0 and w1) then w0, w1 = S.filesWALL, S.varsWALL end
  if not (w0 and w1) then w0, w1 = S.t0WALL, S.filesWALL end
  if not (e0 and e1) then e0, e1 = S.filesEP, S.varsEP end
  if not (e0 and e1) then e0, e1 = S.t0EP, S.filesEP end
  if w0 and w1 then
    table.insert(detail, string.format("[载入] 墙钟（秒级旁证）：%s → %s", tostring(w0), tostring(w1)))
  end
  if type(e0) == "number" and type(e1) == "number" then
    local d = e1 - e0
    table.insert(detail, string.format("[载入] 秒级窗口：time() 差 %d 秒（%s）", d,
      (d == 0) and "同秒 ⇒ 这一段 <1 秒" or "跨秒 ⇒ 单次定不了量，看下面的抽样平均"))
  end
  if sA then
    table.insert(detail, string.format("[载入] 秒级抽样 n=%d：源码段均 %.2f 秒（跨秒 %d）｜ 存档段均 %.2f 秒（跨秒 %d）",
      sn, sA, stat.a or 0, sB, stat.b or 0))
  end
  table.insert(detail, string.format("[载入] 本次清理探针残渣 %d 个键（约 %.1f KB）⇒ 下次登录可对比", killed, bytes / 1024))
  if dead then
    local function j(a1, a2, a3, a4, a5)
      return table.concat({ tostring(a1), tostring(a2), tostring(a3), tostring(a4), tostring(a5) }, "/")
    end
    table.insert(detail, "[载入] 原始读数 t0/f/v/w/i ｜ GetTime " .. j(S.t0GT, S.filesGT, S.varsGT, S.worldGT, S.initGT))
    local extra = ""
    if type(S.filesGGT) == "number" and S.filesGGT == S.varsGGT and S.varsGGT == S.initGGT then
      extra = string.format("（GetGameTime 恒 %s，不随时间走 ⇒ 不能当时钟）", tostring(S.filesGGT))
    end
    table.insert(detail, "[载入] 　同序 ｜ GetGameTime " .. j(S.t0GGT, S.filesGGT, S.varsGGT, S.worldGGT, S.initGGT)
      .. " ｜ time(秒) " .. j(S.t0EP, S.filesEP, S.varsEP, S.worldEP, S.initEP) .. extra)
  end
  local lines = full and detail or { sum }
  LOADM.reported = true
  for i = 1, table.getn(detail) do
    if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, detail[i]) end
  end
  for i = 1, table.getn(lines) do
    if type(sayFn) == "function" then pcall(sayFn, lines[i]) end
  end
  return lines, detail
end

