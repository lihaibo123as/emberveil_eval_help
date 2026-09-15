-- EvalHelp · Core.lua —— 输出/i18n/状态采集(EVAL_HELP_STATE)/角色状态模块/UI 越界助手
-- 加载顺序见 EvalHelp.toc：Locales → Core → Engine → EvalHelp

-- EvalHelp 1.49.1 —— 全职业施法工具：通用一键宏（条件规则引擎） + 状态日志 + 战斗信息UI + 配置窗口
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
--   5) 聊天输出用 DEFAULT_CHAT_FRAME:AddMessage；写日志文件用 Azeroth 专有 UELog()
--      （日志在 %LOCALAPPDATA%\Azeroth\Saved\Logs 下，不刷聊天框）。
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
--   日志文件：%LOCALAPPDATA%\Azeroth\Saved\Logs（/eh wdebug 后聊天框同步显示决策原因）

local VERSION = "1.38.1"

-- ============ 输出：聊天 + 日志文件 ============

local function say(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffEVAL_HELP:|r " .. tostring(msg))
  end
end

-- 写日志文件（Azeroth 专有 API；不存在就静默跳过）
local function logLine(msg)
  if type(UELog) == "function" then
    pcall(UELog, "[EVAL_HELP] " .. tostring(msg))
  end
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
EVAL_BLEED_BLACKLIST = EVAL_BLEED_BLACKLIST or {}
EVAL_BLEED_WHITELIST = EVAL_BLEED_WHITELIST or {}
local BLEED_BAD_TYPES = { ["元素生物"] = true, ["机械"] = true, ["Elemental"] = true, ["Mechanical"] = true }

-- 刷新全部角色状态；返回状态表本身
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
      local oku, tex = pcall(UnitBuff, "player", i)
      if not oku or not tex then break end
      st.playerBuffs[tex] = true
    end
  end
  st.targetDebuffs = {} -- 1.31.0 起存层数（数字）：UnitDebuff 第二返回值；非堆叠 debuff 返回 0 → 归一化为 1
  if UnitExists("target") and type(UnitDebuff) == "function" then
    for i = 1, 16 do
      local okd, tex, apps = pcall(UnitDebuff, "target", i)
      if not okd or not tex then break end
      st.targetDebuffs[tex] = (type(apps) == "number" and apps > 0) and apps or 1
    end
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
    -- 可流血：白名单 > 黑名单 > 生物类型排除（元素/机械）
    if EVAL_BLEED_WHITELIST[st.targetName or ""] then
      st.canBleed = true
    elseif EVAL_BLEED_BLACKLIST[st.targetName or ""] then
      st.canBleed = false
    elseif st.tCreatureType and BLEED_BAD_TYPES[st.tCreatureType] then
      st.canBleed = false
    else
      st.canBleed = true
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
  EVAL_SAY("|cffff0000EvalHelp 引擎未加载完整|r（宏走了兜底）：请 /reload 一次；反复出现 → 检查角色选择界面的插件列表是否对当前角色启用了 EvalHelp")
end
