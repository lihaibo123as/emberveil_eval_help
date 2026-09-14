-- EvalHelp 1.36.2 —— 全职业施法工具：通用一键宏（条件规则引擎） + 状态日志 + 战斗信息UI + 配置窗口
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

local VERSION = "1.36.2"
local cfg = nil -- VARIABLES_LOADED 后指向 EVAL_HELP_CONFIG

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
  if cfg then cfg.lang = code end
  say(L("LANG_RELOAD", EH_LANG_LABEL[code] or code))
  return true
end

-- 语言解析（VARIABLES_LOADED 后调用）：存配置优先 → GetLocale 四码 → GetClientLocale UE 风格 → zhCN
local function ehResolveLang()
  local saved = cfg and cfg.lang
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
  if cfg and cfg.log then logLine(msg) end
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
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  local line = formatStats(collectStats())
  output(line)
  return line
end

-- ============ 进出战斗自动输出 ============

local autoFrame = CreateFrame("Frame", "EVAL_HELPAutoFrame", UIParent)
local function onCombatEvent(entered)
  if cfg and cfg.auto then
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
  end
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

-- ============ 一键输出引擎（规则引擎驱动；移植自 战士_武器.lua，内置战士技能白名单，其他职业同构扩展） ============
-- 宏入口：/run EVAL_GO() —— 每次按键只做一个动作（同键多行动作会互抢 GCD）。
-- 需要把技能拖上动作条（缺哪个就跳过哪个逻辑）：
--   攻击 / 战斗姿态 / 冲锋 / 压制 / 断筋 / 撕裂 / 战斗怒吼 / 血性狂暴 / 猛击 / 英勇打击
-- 技能识别走 tooltip 技能名（不依赖图标名拼写）；buff/debuff 用「动作条图标 == 光环图标」比对。
-- 原宏两个插件依赖的处理：
--   MPGetMainHandLeft（挥击计时）→ 本客户端无此 API，猛击改为【按住 Alt 才放】；
--   MPTargetBleed（可否流血）→ 用 UnitCreatureType 排除元素/机械。
-- 调试：/eh war 看识别结果和当前状态；/eh war rescan 重扫；/eh wdebug 开关详细日志。
-- 所有出手动作都会写入日志文件（UELog），连按不刷屏也能事后复盘。

local WAR_MAX_SLOT = 119
local WAR_SKILLS = { "攻击", "战斗姿态", "冲锋", "压制", "断筋", "撕裂", "战斗怒吼", "血性狂暴", "猛击", "英勇打击" }
local WTT = GameTooltip -- 识别动作条技能用
local wslots = {}       -- 技能名 -> { slot, tex }
local wscanned = false
local wLastAttackTry = 0

-- 详细日志：/eh wdebug 开启后刷聊天框，同时总是可写日志文件
local function wlog(msg)
  if cfg and cfg.wdebug then say("|cffff9040war:|r " .. tostring(msg)) end
end

local function wactionName(slot)
  if not WTT or not WTT.SetAction then return nil end
  local ok = pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  if not ok then pcall(function() WTT:SetOwner(UIParent, "ANCHOR_TOPLEFT") end) end
  pcall(function() WTT:ClearLines() end)
  local ok2 = pcall(WTT.SetAction, WTT, slot) -- 1.33.2 同探针结论：built 返回值在本客户端不可信，不拿它当门槛
  local name
  if ok2 then
    local fs = getglobal("GameTooltipTextLeft1")
    if fs and fs.GetText then name = fs:GetText() end
  end
  pcall(function() WTT:Hide() end)
  return name
end

-- 扫描动作条，定位技能所在格子并记录图标
-- 1.24.0 泛化：不再限 WAR_SKILLS 白名单——动作条上所有非宏技能全部记录。
-- 收益：① 有/无buff、有/无debuff 条件支持任意已上条技能（图标比对需要纹理）；
--       ② 方案规则可直接写任意已上条技能释放（冷却/可用/排队判定都是通用 API）→ 真·全职业。
function EVAL_GO_RESCAN(quiet)
  wslots = {}
  for slot = 1, WAR_MAX_SLOT do
    if HasAction(slot) and not GetActionText(slot) then -- GetActionText 非空 = 宏格子，跳过
      local name = wactionName(slot)
      if name and not wslots[name] then
        local tex
        local okt, t = pcall(GetActionTexture, slot)
        if okt then tex = t end
        wslots[name] = { slot = slot, tex = tex }
      end
    end
  end
  wscanned = true
  if not quiet then
    local total = 0
    for _ in pairs(wslots) do total = total + 1 end
    say(string.format("动作条共识别 |cff00ff00%d|r 个技能（均可用于方案/条件；核心技能核对↓）", total))
    for _, n in ipairs(WAR_SKILLS) do
      local s = wslots[n]
      say(string.format("%s → %s", n, s and ("格子 " .. s.slot) or "|cffff0000未找到|r（拖上动作条后 /eh war rescan）"))
    end
  end
  return wslots
end

local function wtex(name) local s = wslots[name]; return s and s.tex end

-- ===== 宠物指令（1.30.0 特殊技能：rule.skill="宠物:攻击"，不占动作条，出手直接调 Pet API） =====
-- 收录战斗行为类全量：攻击/跟随/停留/停止攻击 + 三种姿态（被动/防御/主动）+ 解散。
-- 刻意不含：PetAbandon 永久放弃（太危险）、PetRename、兽栏系（非战斗行为）、CastPetAction（格子随宠物变不可靠）。
local PET_CMD = {
  { id = "attack",     name = "攻击",     fn = "PetAttack",        token = "PET_ACTION_ATTACK" },
  { id = "follow",     name = "跟随",     fn = "PetFollow",        token = "PET_ACTION_FOLLOW" },
  { id = "wait",       name = "停留",     fn = "PetWait",          token = "PET_ACTION_WAIT" },
  { id = "stopAttack", name = "停止攻击", fn = "PetStopAttack" },  -- 不上宠物动作条，无 token
  { id = "passive",    name = "被动姿态", fn = "PetPassiveMode",   token = "PET_MODE_PASSIVE" },
  { id = "defensive",  name = "防御姿态", fn = "PetDefensiveMode", token = "PET_MODE_DEFENSIVE" },
  { id = "aggressive", name = "主动姿态", fn = "PetAggressiveMode", token = "PET_MODE_AGGRESSIVE" },
  { id = "dismiss",    name = "解散",     fn = "PetDismiss",       token = "PET_ACTION_DISMISS" },
}
local PET_CMD_FN = {} -- 中文名 → 函数名
for _, p in ipairs(PET_CMD) do PET_CMD_FN[p.name] = p.fn end

-- 宠物指令图标（1.32.6）：有宠物时从宠物动作条 GetPetActionInfo(1..10) 学习 名称/token→图标，
-- 持久化 cfg.war.petIcons（跨会话）；未学到回退宠物家族图标 GetPetIcon → 问号。
-- 直接走 EVAL_HELP_CONFIG 全局（此处 local cfg 尚未声明，同 uiWarCfg 模式）
local function petIconOf(cmdName)
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  if w2 and not w2.petIcons then w2.petIcons = {} end
  local store = w2 and w2.petIcons
  if type(GetPetActionInfo) == "function" and type(HasPetUI) == "function" then
    local okh, hasPet = pcall(HasPetUI)
    if okh and hasPet and store then
      for slot = 1, 10 do
        local oki, aname, asub, atex = pcall(GetPetActionInfo, slot)
        if oki and aname and atex then store[aname] = atex end -- 命令槽返回 token（PET_ACTION_ATTACK 等），法术槽返回中文名
      end
    end
  end
  if store then
    if store[cmdName] then return store[cmdName] end
    for _, p in ipairs(PET_CMD) do
      if p.name == cmdName and p.token and store[p.token] then return store[p.token] end
    end
  end
  if type(GetPetIcon) == "function" then
    local ok, t = pcall(GetPetIcon)
    if ok and t then return t end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- 宠物指令解析："宠物:攻击" → "攻击"（非宠物指令返回 nil）
local function petCmdOf(skill)
  local n = string.match(skill or "", "^宠物[:：](.+)$")
  if n and PET_CMD_FN[n] then return n end
  return nil
end

-- ===== 目标选取（1.25.0 条件级 / 1.32.0 起同时为技能级）：副作用=切换当前目标 =====
-- 表位置上移到 wuse 之前：技能级执行（wuse 分支）需要 TARGET_SEL_FN/ARG
local TARGET_SEL = {
  { id = "nearEnemy",    name = "最近敌人",   fn = "TargetNearestEnemy" },
  { id = "nearFriend",   name = "最近友方",   fn = "TargetNearestFriend" },
  { id = "nearParty",    name = "最近队友",   fn = "TargetNearestPartyMember" },
  { id = "nearRaid",     name = "最近团员",   fn = "TargetNearestRaidMember" },
  { id = "lastEnemy",    name = "上一敌人",   fn = "TargetLastEnemy" },
  { id = "lastTarget",   name = "上一目标",   fn = "TargetLastTarget" },
  { id = "targetTarget", name = "目标的目标", fn = "TargetUnit", arg = "targettarget" },
  { id = "byName",       name = "指定名称",   fn = "TargetByName", needsName = true },
  { id = "clear",        name = "清除目标",   fn = "ClearTarget" },
}
local TARGET_SEL_NAME, TARGET_SEL_ID, TARGET_SEL_FN, TARGET_SEL_ARG = {}, {}, {}, {}
for _, t in ipairs(TARGET_SEL) do
  TARGET_SEL_NAME[t.id] = t.name
  TARGET_SEL_ID[t.name] = t.id
  TARGET_SEL_ID[t.id] = t.id
  TARGET_SEL_FN[t.id] = t.fn
  TARGET_SEL_ARG[t.id] = t.arg
end

-- 选取目标技能级解析（1.32.0）："选取目标:最近敌人" → id；"选取目标:指定名称:嗜血者" → "byName","嗜血者"
local function targetSelOf(skill)
  local tg = string.match(skill or "", "^选取目标[:：](.+)$")
  if not tg then return nil end
  local nm = string.match(tg, "^指定名称[:：](.+)$")
  if nm then return "byName", nm end
  local id = TARGET_SEL_ID[tg]
  if id then return id end
  return nil
end

-- 物品使用（1.32.0）：rule.skill="物品:名称"——背包扫描定位 + UseContainerItem（消耗品直接用/装备自动穿上，官方文档明确不受保护）
local function itemOf(skill)
  return string.match(skill or "", "^物品[:：](.+)$")
end
-- 背包查找：→ bag, slot, tex, count（未找到返回 nil）
local function wFindBagItem(name)
  if type(GetContainerNumSlots) ~= "function" then return nil end
  for bag = 0, 4 do
    local okn, slots = pcall(GetContainerNumSlots, bag)
    if okn and slots and slots > 0 then
      for slot = 1, slots do
        local okl, link = pcall(GetContainerItemLink, bag, slot)
        if okl and link then
          local iname = string.match(link, "%[(.-)%]")
          if iname == name then
            local oki, tex, count = pcall(GetContainerItemInfo, bag, slot)
            return bag, slot, (oki and tex) or nil, (oki and count) or 1
          end
        end
      end
    end
  end
  return nil
end

-- 技能图标统一入口（1.30.0）：动作条纹理 → 宠物指令回退（宠物头像/问号）
local function wicon(name)
  local s = wslots[name]
  if s and s.tex then return s.tex end
  local pc2 = petCmdOf(name)
  if pc2 then return petIconOf(pc2) end -- 1.32.6 宠物指令专属图标（动作条学习）
  if targetSelOf(name) then return "Interface\\Icons\\INV_Misc_QuestionMark" end -- 1.32.0 选取目标无专属图标
  local iname = itemOf(name) -- 1.32.0 物品：背包图标 → GetItemInfo 缓存 → 问号
  if iname then
    local _, _, tex = wFindBagItem(iname)
    if tex then return tex end
    if type(GetItemInfo) == "function" then
      local ok, _1, _2, _3, _4, _5, _6, _7, itex = pcall(GetItemInfo, iname)
      if ok and itex then return itex end -- 1.12 GetItemInfo 第9返回值=纹理
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  return nil
end

-- 玩家自身 buff 检查（图标比对；0 起始索引）
local function wPlayerHasBuff(tex)
  if not tex then return false end
  if st.playerBuffs then return st.playerBuffs[tex] and true or false end -- 优先读状态表
  if type(GetPlayerBuff) ~= "function" then return false end
  for i = 0, 31 do
    local bi = GetPlayerBuff(i, "HELPFUL")
    if not bi or bi == -1 then break end
    local ok, t = pcall(GetPlayerBuffTexture, bi)
    if ok and t and t == tex then return true end
  end
  return false
end

-- 目标 debuff 检查（UnitDebuff 返回图标路径，直接与技能图标比对）
local function wTargetHasDebuff(tex)
  if not tex then return false end
  if st.targetDebuffs then return st.targetDebuffs[tex] and true or false end -- 优先读状态表
  for i = 1, 16 do
    local dtex = UnitDebuff("target", i)
    if not dtex then break end
    if dtex == tex then return true end
  end
  return false
end

-- ===== 实时光环清单（1.27.0）：编辑窗 debuff/buff 条件下拉列出「当前目标 debuff / 当前自身 buff」 =====
-- 名称读取走 GameTooltip:SetUnitDebuff/SetPlayerBuff 填 tooltip 再读 GameTooltipTextLeft1（同 wactionName 法）；
-- 名称→纹理即时学习（cfg.war.debuffTex 持久化，cfg 未加载时落 EVAL_DEBUFF_TEX_LEARN 运行时兜底）：
-- 学到后，怪给的非动作条 debuff 也能做 有/无debuff 图标比对（texOf 回退查学习表）。
EVAL_DEBUFF_TEX_LEARN = EVAL_DEBUFF_TEX_LEARN or {}

local function learnAuraTex(name, tex)
  if not (name and tex and name ~= "") then return end
  local store = (cfg and cfg.war and cfg.war.debuffTex) or EVAL_DEBUFF_TEX_LEARN
  store[name] = tex
end

-- 光环名 → 纹理：动作条优先，学习表回退（1.27.0 前只有动作条一条路径）
local function auraTexOf(n)
  local s = wslots[n]
  if s and s.tex then return s.tex end
  if cfg and cfg.war and cfg.war.debuffTex and cfg.war.debuffTex[n] then return cfg.war.debuffTex[n] end
  return EVAL_DEBUFF_TEX_LEARN[n]
end

-- 当前目标 debuff 实时清单：[{name,tex},...]（每次调用现场扫描 + 学习）
function EVAL_TARGET_DEBUFF_LIST()
  local list = {}
  if not (UnitExists("target") and type(UnitDebuff) == "function") then return list end
  if not (WTT and WTT.SetUnitDebuff) then return list end
  pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  for i = 1, 16 do
    local okd, tex = pcall(UnitDebuff, "target", i)
    if not okd or not tex then break end
    local name
    pcall(function() WTT:ClearLines() end)
    local oks = pcall(WTT.SetUnitDebuff, WTT, "target", i) -- 1.33.2 探针实测：返回值恒 nil 但 tooltip 已填充，built 不能当门槛
    if oks then
      local fs = getglobal("GameTooltipTextLeft1")
      if fs and fs.GetText then name = fs:GetText() end
    end
    if name and name ~= "" then
      table.insert(list, { name = name, tex = tex })
      learnAuraTex(name, tex)
    end
  end
  pcall(function() WTT:Hide() end)
  return list
end

-- 当前自身 buff 实时清单（GetPlayerBuff 0 起始索引 + SetPlayerBuff 读名）
function EVAL_PLAYER_BUFF_LIST()
  local list = {}
  local function tooltipName() -- 读 tooltip 第一行（WTT=GameTooltip）
    local fs = getglobal("GameTooltipTextLeft1")
    if fs and fs.GetText then return fs:GetText() end
    return nil
  end
  if type(GetPlayerBuff) == "function" and WTT and WTT.SetPlayerBuff then
    pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
    for i = 0, 31 do
      local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
      if not okb or type(bi) ~= "number" or bi < 0 then break end
      local okt, tex = pcall(GetPlayerBuffTexture, bi)
      local name
      pcall(function() WTT:ClearLines() end)
      local oks = pcall(WTT.SetPlayerBuff, WTT, bi) -- 1.33.2 同探针实测：built 恒 nil 但 name 可读
      if oks then name = tooltipName() end
      if name and name ~= "" and okt and tex then
        table.insert(list, { name = name, tex = tex })
        learnAuraTex(name, tex)
      end
    end
    pcall(function() WTT:Hide() end)
  end
  -- 1.32.10 兜底：一个名字都没读到时换 UnitBuff+SetUnitBuff 路径（本客户端 SetPlayerBuff
  -- 读名可能失败——药品类 buff 不进下拉的病根；SetUnitBuff 与已验证的 SetUnitDebuff 同族）
  if table.getn(list) == 0 and type(UnitBuff) == "function" and WTT and WTT.SetUnitBuff then
    pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
    for i = 1, 32 do
      local oku, tex = pcall(UnitBuff, "player", i)
      if not oku or not tex then break end
      local name
      pcall(function() WTT:ClearLines() end)
      local oks = pcall(WTT.SetUnitBuff, WTT, "player", i) -- 1.33.2 同探针实测
      if oks then name = tooltipName() end
      if name and name ~= "" then
        table.insert(list, { name = name, tex = tex })
        learnAuraTex(name, tex)
      end
    end
    pcall(function() WTT:Hide() end)
  end
  return list
end

-- 技能冷却是否就绪；不就绪时返回剩余秒数说明
local function wready(name)
  local iname = itemOf(name) -- 1.32.0 物品冷却走背包 API
  if iname then
    local bag, slot = wFindBagItem(iname)
    if not bag then return false, "背包未找到" end
    local okc, start, dur = pcall(GetContainerItemCooldown, bag, slot)
    if not okc then return false, "冷却查询失败" end
    if (start or 0) == 0 and (dur or 0) == 0 then return true end
    local left = (start or 0) + (dur or 0) - GetTime()
    return false, string.format("冷却剩 %.1fs", left > 0 and left or 0)
  end
  local s = wslots[name]
  if not s then return false, "不在动作条" end
  local ok, start, dur = pcall(GetActionCooldown, s.slot)
  if not ok then return false, "冷却查询失败" end
  if (start or 0) == 0 and (dur or 0) == 0 then return true end
  local left = (start or 0) + (dur or 0) - GetTime()
  return false, string.format("冷却剩 %.1fs", left > 0 and left or 0)
end

-- 出手一个技能：写动作日志（文件必写；wdebug 时同步聊天框）
local function wuse(name, reason)
  local pc = petCmdOf(name)
  if pc then
    -- 宠物指令（1.30.0）：不占动作条，直接调 Pet API；无宠物时静默跳过
    if type(HasPetUI) == "function" then
      local okh, hasPet = pcall(HasPetUI)
      if okh and not hasPet then wlog(name .. "跳过: 无宠物") return false end
    end
    local fn = getglobal(PET_CMD_FN[pc])
    if type(fn) ~= "function" then wlog(name .. ": 无宠物指令函数") return false end
    pcall(fn)
    local pline = string.format("→ %s (%s)", name, reason)
    logLine(pline)
    if cfg and cfg.wdebug then say("|cff7fff7f" .. pline .. "|r") end
    return true
  end
  local ts, tsnm = targetSelOf(name)
  if ts then
    -- 选取目标技能级（1.32.0）：执行切换即算出手；日志记切换后的目标名
    local fn = getglobal(TARGET_SEL_FN[ts])
    if type(fn) ~= "function" then wlog(name .. ": 无选取函数") return false end
    if ts == "byName" then pcall(fn, tsnm)
    elseif TARGET_SEL_ARG[ts] then pcall(fn, TARGET_SEL_ARG[ts])
    else pcall(fn) end
    local tline = string.format("→ %s (%s) | 当前目标:%s", name, reason, UnitName("target") or "无")
    logLine(tline)
    if cfg and cfg.wdebug then say("|cff7fff7f" .. tline .. "|r") end
    return true
  end
  local iname = itemOf(name)
  if iname then
    -- 物品使用（1.32.0）：UseContainerItem——消耗品直接使用，装备自动穿上；背包未找到静默跳过
    local bag, slot = wFindBagItem(iname)
    if not bag then wlog(name .. "跳过: 背包未找到") return false end
    pcall(UseContainerItem, bag, slot)
    local iline = string.format("→ %s (%s)", name, reason)
    logLine(iline)
    if cfg and cfg.wdebug then say("|cff7fff7f" .. iline .. "|r") end
    return true
  end
  local s = wslots[name]
  if not s then wlog(string.format("%s: %s，但技能不在动作条", name, reason)) return false end
  UseAction(s.slot)
  local line = string.format("→ %s (%s) | 怒气%d", name, reason, UnitMana("player"))
  logLine(line)
  if cfg and cfg.wdebug then say("|cff7fff7f" .. line .. "|r") end
  return true
end

-- ============ 配置化技能释放规则引擎（条件全部读 EVAL_HELP_STATE） ============
-- 一条规则 = { skill="技能名", when={...条件...}, why="日志原因" }，按顺序评估，第一条全过的出手。
-- 条件字段（→ 状态表字段；缺失的已补进状态模块）：
--   combat=bool            → inCombat        战斗中/非战斗
--   combatTime={">",3}    → combatTime      进战秒数
--   hpPct / power / powerPct / tHpPct = {op,n}  自身血% / 能量值 / 能量% / 目标血%
--   canAttack=true         → canAttack       释放对象：敌对可攻击
--   canBleed=bool          → canBleed        目标可流血
--   isBoss / isElite=bool  → isBoss/isElite  目标分级
--   tInCombat=bool         → tInCombat       目标战斗中
--   form=1 或 "战斗姿态"   → formIndex/form  当前姿态；formNot=1 取反
--   alt / shift / ctrl=bool → 修饰键（猛击 Alt 门等）
--   autoAttack=bool        → autoAttack      普攻开关
--   hasBuff / noBuff="战斗怒吼"    → playerBuffs（按动作条图标比对）
--   hasDebuff / noDebuff="断筋"    → targetDebuffs
-- 技能侧条件（走动作条 API）：ready=true 冷却就绪 / usable=true 可用（压制类）/ notQueued=true 未排队
-- 本客户端做不了：目标施法中打断（无 UnitCastingInfo）、距离、挥击计时。
-- 用法：宏里也可以直接 /run EVAL_RULE_RUN({ {skill="压制", when={usable=true}} })

-- 比较器：{ ">", 30 } { ">=", 30 } { "<", 50 } { "<=", 50 } { "==", 1 } { "~=", 1 }
local function condCmp(spec, actual)
  if type(spec) == "number" then return actual == spec end
  if type(spec) ~= "table" then return false end
  local op, n = spec[1], spec[2]
  if type(actual) ~= "number" or type(n) ~= "number" then return false end
  if op == ">" then return actual > n
  elseif op == ">=" then return actual >= n
  elseif op == "<" then return actual < n
  elseif op == "<=" then return actual <= n
  elseif op == "==" or op == "=" then return actual == n
  elseif op == "~=" or op == "!=" then return actual ~= n end
  return false
end

-- 逐条评估 when；返回 true 或 false+第一个不满足的原因（供 wdebug 日志）
local function condOK(when, skill)
  local function texOf(n) return auraTexOf(n) end -- 动作条 + 学习表回退（1.27.0）
  if when.combat ~= nil and st.inCombat ~= when.combat then return false, "战斗状态不符" end
  if when.combatTime and not condCmp(when.combatTime, st.combatTime) then return false, "进战时间不符" end
  if when.combo and not condCmp(when.combo, st.combo or 0) then return false, "连击点不符" end
  if when.hpPct and not condCmp(when.hpPct, st.hpPct) then return false, "自身血%不符" end
  if when.power and not condCmp(when.power, st.power) then return false, "能量不符" end
  if when.powerPct and not condCmp(when.powerPct, st.powerPct) then return false, "能量%不符" end
  if when.tHpPct and not condCmp(when.tHpPct, st.tHpPct) then return false, "目标血%不符" end
  if when.canAttack ~= nil and st.canAttack ~= when.canAttack then return false, "目标不可攻击" end
  if when.canBleed ~= nil and st.canBleed ~= when.canBleed then return false, "流血条件不符" end
  if when.isBoss ~= nil and st.isBoss ~= when.isBoss then return false, "Boss 条件不符" end
  if when.isElite ~= nil and st.isElite ~= when.isElite then return false, "精英条件不符" end
  if when.tInCombat ~= nil and st.tInCombat ~= when.tInCombat then return false, "目标战斗状态不符" end
  if when.form ~= nil then
    if type(when.form) == "number" and st.formIndex ~= when.form then return false, "姿态不符" end
    if type(when.form) == "string" and st.form ~= when.form then return false, "姿态不符" end
  end
  if when.formNot ~= nil and st.formIndex == when.formNot then return false, "姿态冲突" end
  if when.alt ~= nil and st.alt ~= when.alt then return false, "Alt 未按" end
  if when.shift ~= nil and st.shift ~= when.shift then return false, "Shift 未按" end
  if when.ctrl ~= nil and st.ctrl ~= when.ctrl then return false, "Ctrl 未按" end
  if when.autoAttack ~= nil and (st.autoAttack and true or false) ~= when.autoAttack then return false, "普攻状态不符" end
  if when.hasBuff and not st.playerBuffs[texOf(when.hasBuff) or ""] then return false, "缺少buff:" .. when.hasBuff end
  if when.noBuff and st.playerBuffs[texOf(when.noBuff) or ""] then return false, "已有buff:" .. when.noBuff end
  if when.hasDebuff and not st.targetDebuffs[texOf(when.hasDebuff) or ""] then return false, "目标缺debuff:" .. when.hasDebuff end
  if when.noDebuff and st.targetDebuffs[texOf(when.noDebuff) or ""] then return false, "目标已有debuff:" .. when.noDebuff end
  -- 技能侧条件
  if when.ready then
    local rd, why = wready(skill)
    if not rd then return false, "未就绪:" .. tostring(why) end
  end
  if when.usable then
    local s = wslots[skill]
    local oku, usable = s and pcall(IsUsableAction, s.slot)
    if not (oku and usable) then return false, "不可用(IsUsableAction)" end
  end
  if when.notQueued then
    local s = wslots[skill]
    local okq, q = s and pcall(IsCurrentAction, s.slot)
    if okq and q then return false, "已排队" end
  end
  return true
end

-- ===== 选取目标条件（1.25.0）：规则求值时切换当前目标（副作用条件，求值通过恒 true） =====
-- 官方文档 emberveil.org/wiki/lua/globals/Targetting；下列均为无参函数，重复调用会在邻近单位间循环（死人跳过）。
-- TargetByName/AssistByName/AssistUnit/TargetUnit 需要名称/UnitID 参数，暂不纳入下拉。
-- 1.29.0 扩展：targetTarget=目标的目标（TargetUnit 带 UnitID 参数，不解析时无动作——比 AssistUnit 安全）；
-- byName=指定名称（TargetByName 带名称参数，cd.nm 存名字；编辑窗下拉给最近 5 敌名 + 自定义输入弹窗）。
-- （TARGET_SEL 表 1.32.0 起上移到 wuse 之前，与 PET_CMD 并列——技能级执行需要）

-- 附近敌人名称枚举（1.29.0，编辑窗「指定名称」下拉用）：客户端无附近单位枚举 API，
-- 用 TargetNearestEnemy 循环选取特性边切边收集，完事恢复原目标（无原目标则清除）。
-- 代价：调用瞬间目标快速切换一轮；同名怪多时 TargetByName 还原的可能不是同一只（可接受）。
function EVAL_NEARBY_ENEMY_NAMES(maxN)
  local names, seen = {}, {}
  local orig = UnitName("target")
  for _ = 1, (maxN or 5) do
    pcall(TargetNearestEnemy)
    local n = UnitName("target")
    if not n or seen[n] then break end
    seen[n] = true
    table.insert(names, n)
  end
  if orig then pcall(TargetByName, orig) else pcall(ClearTarget) end
  return names
end

-- ===== 目标职业条件（1.26.0）：UnitClass 第二返回值（英文 token）比对；多选 = 或关系 =====
local CLASS_LIST = {
  { id = "HUNTER",  name = "猎人" },
  { id = "PRIEST",  name = "牧师" },
  { id = "MAGE",    name = "法师" },
  { id = "WARLOCK", name = "术士" },
  { id = "SHAMAN",  name = "萨满" },
  { id = "ROGUE",   name = "盗贼" },
  { id = "WARRIOR", name = "战士" },
  { id = "DRUID",   name = "德鲁伊" },
}
local CLASS_NAME_BY_ID, CLASS_ID = {}, {} -- CLASS_ID 同时收中文名/英文 token（导入文本两种都认）
for _, c in ipairs(CLASS_LIST) do
  CLASS_NAME_BY_ID[c.id] = c.name
  CLASS_ID[c.name] = c.id
  CLASS_ID[c.id] = c.id
end

-- ===== 条件组格式（方案/技能配置 UI 用）：rule.groups = { {cond,...}, ... }，组内条件为 & 关系，组间为 | 关系 =====
-- 单条件 cond = { k=类型, op/n=数值比较, v=布尔, s=技能名, inv=取反 }
--   数值: {k="power",op=">",n=30}  tHpPct/hpPct/powerPct/combatTime/combo(连击点 1.28.0) 同
--   布尔: {k="combat",v=true}  canAttack/canBleed/isBoss/isElite/tInCombat/alt/shift/ctrl/autoAttack
--   姿态: {k="form",n=1} / {k="formNot",n=1}
--   光环: {k="noBuff",s="战斗怒吼"}  hasBuff/noDebuff/hasDebuff
--   技能侧: {k="ready"} {k="usable"} {k="notQueued"}（inv=true 取反）
--   选取目标: {k="target",s="nearEnemy"}（1.25.0 副作用条件，恒过；dry 预览不执行）
--   目标职业: {k="tClass",cs={WARRIOR=true,...}}（1.26.0 多选或关系，比对 UnitClass 英文 token）

-- 单个条件求值；返回 true 或 false+原因。dry=true 为预览求值（UI 亮金），副作用条件（选取目标）只验函数存在不执行
local function condOne(cd, skill, dry)
  local k = cd.k
  local function texOf(n) return auraTexOf(n) end -- 动作条 + 学习表回退（1.27.0）
  if k == "combat" then return (st.inCombat == cd.v), "战斗状态"
  elseif k == "combatTime" then return condCmp({ cd.op, cd.n }, st.combatTime), "进战时间"
  elseif k == "combo" then return condCmp({ cd.op, cd.n }, st.combo or 0), "连击点"
  elseif k == "hpPct" then return condCmp({ cd.op, cd.n }, st.hpPct), "自身血%"
  elseif k == "power" then return condCmp({ cd.op, cd.n }, st.power), "能量"
  elseif k == "powerPct" then return condCmp({ cd.op, cd.n }, st.powerPct), "能量%"
  elseif k == "tHpPct" then return condCmp({ cd.op, cd.n }, st.tHpPct), "目标血%"
  elseif k == "hasTarget" then return ((st.hasTarget and true or false) == cd.v), "目标存在" -- 1.32.1
  elseif k == "canAttack" then return (st.canAttack == cd.v), "可攻击"
  elseif k == "canBleed" then return (st.canBleed == cd.v), "可流血"
  elseif k == "isBoss" then return (st.isBoss == cd.v), "Boss"
  elseif k == "isElite" then return (st.isElite == cd.v), "精英"
  elseif k == "tInCombat" then return (st.tInCombat == cd.v), "目标战斗"
  elseif k == "tFriendly" then return (st.tFriendly == cd.v), "友善"
  elseif k == "tHostile" then return (st.tHostile == cd.v), "敌对"
  elseif k == "tNeutral" then return (st.tNeutral == cd.v), "中立"
  elseif k == "form" then return (st.formIndex == cd.n), "姿态"
  elseif k == "formNot" then return (st.formIndex ~= cd.n), "姿态"
  elseif k == "alt" then return (st.alt == cd.v), "Alt"
  elseif k == "shift" then return (st.shift == cd.v), "Shift"
  elseif k == "ctrl" then return (st.ctrl == cd.v), "Ctrl"
  elseif k == "autoAttack" then return ((st.autoAttack and true or false) == cd.v), "普攻"
  elseif k == "hasBuff" then return (st.playerBuffs[texOf(cd.s) or ""] and true or false), "缺buff:" .. tostring(cd.s)
  elseif k == "noBuff" then return (not st.playerBuffs[texOf(cd.s) or ""]), "已有buff:" .. tostring(cd.s)
  elseif k == "hasDebuff" then
    -- 层数门槛（1.31.0）：cd.n=需要的最小层数（nil/1=只要有）
    local cnt = st.targetDebuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (cnt or 0) -- 兼容旧布尔
    local need = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    if cnt <= 0 then return false, "目标缺debuff:" .. tostring(cd.s) end
    if cnt < need then return false, "debuff层数不足:" .. tostring(cd.s) .. " " .. cnt .. "/" .. need end
    return true, "debuff层数:" .. cnt
  elseif k == "noDebuff" then
    -- 层数门槛（1.31.0）：cd.n=视为"无"的上限（nil/1=完全没有；N=不足N层才算无）
    local cnt = st.targetDebuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (cnt or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    if cnt >= lim then return false, "目标已有debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "层") or "") end
    return true, "debuff层数不足:" .. cnt .. "/" .. lim
  elseif k == "ready" then
    local rd, why = wready(skill)
    if cd.inv then rd = not rd end
    return rd, tostring(why or "就绪")
  elseif k == "usable" then
    local s = wslots[skill]
    local oku, u = s and pcall(IsUsableAction, s.slot)
    local pass = (oku and u) and true or false
    if cd.inv then pass = not pass end
    return pass, "可用性"
  elseif k == "notQueued" then
    local s = wslots[skill]
    local okq, q = s and pcall(IsCurrentAction, s.slot)
    local pass = not (okq and q)
    if cd.inv then pass = not pass end
    return pass, "已排队"
  elseif k == "immune" then
    -- 目标是否已免疫指定技能（1.36.1：读免疫学习表 immune[技能@当前目标]；v=false 即「未免疫」）
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local im = w2 and w2.immune
    local rec = (im and st.targetName) and im[(cd.s or "") .. "@" .. tostring(st.targetName)] and true or false
    return (rec == (cd.v ~= false)), "免疫:" .. tostring(cd.s)
  elseif k == "tClass" then
    -- 目标职业：cd.cs = { WARRIOR=true, ... } 多选或关系；无目标/无职业信息 = 不过
    local pass = (st.tClass and cd.cs and cd.cs[st.tClass]) and true or false
    return pass, "目标职业:" .. tostring(st.tClassName or st.tClass or "?")
  elseif k == "target" then
    -- 副作用条件：切换当前目标（战斗信息UI 亮金预览 dry 时不执行，防止刷新误切目标）
    local gfn = TARGET_SEL_FN[cd.s]
    local fn = gfn and getglobal(gfn)
    if type(fn) ~= "function" then return false, "无选取函数:" .. tostring(cd.s) end
    if cd.s == "byName" and not (cd.nm and cd.nm ~= "") then return false, "未设目标名称" end
    if not dry then
      if cd.s == "byName" then pcall(fn, cd.nm)
      elseif TARGET_SEL_ARG[cd.s] then pcall(fn, TARGET_SEL_ARG[cd.s])
      else pcall(fn) end
    end
    return true, "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
  end
  return false, "未知条件:" .. tostring(k)
end

-- 条件组求值：任一组全过即过（组间 | ），组内全过才算过（组内 & ）
-- 命中时返回第三个值 trace = 该组每个条件的逐项判定明细（释放日志用）
local function groupsOK(rule, dry)
  local lastWhy = "条件不满足"
  for _, g in ipairs(rule.groups or {}) do
    local allOK = true
    local trace = {}
    for _, cd in ipairs(g) do
      local ok, why = condOne(cd, rule.skill, dry)
      table.insert(trace, EVAL_COND_STR(cd) .. (ok and "√" or "×"))
      if not ok then allOK = false lastWhy = why break end
    end
    if allOK then return true, nil, table.concat(trace, " ") end
  end
  return false, lastWhy
end

-- 按顺序执行规则表；第一条条件全过且启用的技能出手。返回 true=本次按键已动作
-- ===== 免疫学习器（1.36.0，探针实测驱动） =====
-- 事件 CHAT_MSG_SPELL_SELF_DAMAGE，文本 "你的{技能}施放失败。{怪名}对此免疫。"（英文端 "Your X fails. Y is immune."）
-- 学习持久化 EVAL_HELP_CONFIG.war.immune["技能@怪名"]=true；RULE_RUN 对同名怪自动跳过该技能（可流血黑名单的自动学习版）
function EVAL_IMMUNE_LEARN(msg)
  if type(msg) ~= "string" then return false end
  local skill, mob = string.match(msg, "你的(.-)施放失败。(.-)对此免疫。")
  if not skill then skill, mob = string.match(msg, "Your (.-) fails%. (.-) is immune%.") end
  if not (skill and mob and skill ~= "" and mob ~= "") then return false end
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  if not w2 then return false end
  if not w2.immune then w2.immune = {} end
  local key = skill .. "@" .. mob
  if not w2.immune[key] then
    w2.immune[key] = true
    say("|cffff9040已学习免疫: " .. skill .. " @ " .. mob .. "（该目标不再尝试此技能）|r")
  end
  return true
end

-- 当前目标是否已记录免疫该技能
local function wImmuneTo(skill)
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  local im = w2 and w2.immune
  return (im and st.hasTarget and st.targetName) and im[skill .. "@" .. tostring(st.targetName)] and true or false
end

function EVAL_RULE_RUN(rules)
  for _, r in ipairs(rules) do
    if r.enabled == false then
      -- 技能配置开关关掉的：静默跳过
    elseif not wslots[r.skill] and not petCmdOf(r.skill) and not targetSelOf(r.skill) and not itemOf(r.skill) then
      wlog(r.skill .. "跳过: 不在动作条")
    elseif wImmuneTo(r.skill) then
      wlog(r.skill .. "跳过: 目标已免疫（学习记录 " .. tostring(st.targetName) .. "）")
    else
      local ok, why, trace
      if r.groups then ok, why, trace = groupsOK(r) else ok, why = condOK(r.when or {}, r.skill) end
      if ok then
        if wuse(r.skill, r.why or r.skill) then
          -- 释放成功：记入释放日志（状态信息UI「最近释放」展示触发条件明细）
          st.castLog = st.castLog or {}
          table.insert(st.castLog, 1, {
            t = GetTime(),
            skill = r.skill,
            why = r.why or r.skill,
            trace = trace or "",
            target = (st.hasTarget and st.targetName) and tostring(st.targetName) or "",
          })
          while table.getn(st.castLog) > 5 do table.remove(st.castLog) end
          if trace then wlog(r.skill .. "触发: " .. trace) end
          return true
        end
      else
        wlog(r.skill .. "跳过: " .. tostring(why))
      end
    end
  end
  return false
end

-- ===== 条件串解析（UI 输入框 / /eh war add 用）："怒气>30 & 战斗中 | 非战斗" =====
local function condTrim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local COND_NUM = {
  ["怒气"] = "power", ["能量"] = "power", ["power"] = "power",
  ["目标血"] = "tHpPct", ["tHpPct"] = "tHpPct",
  ["自身血"] = "hpPct", ["hpPct"] = "hpPct",
  ["能量%"] = "powerPct", ["powerPct"] = "powerPct",
  ["进战"] = "combatTime", ["combatTime"] = "combatTime",
  ["连击"] = "combo", ["连击点"] = "combo", ["combo"] = "combo",
}
local COND_BOOL = {
  ["战斗中"] = { "combat", true }, ["非战斗"] = { "combat", false }, ["combat"] = { "combat", true },
  ["目标存在"] = { "hasTarget", true }, ["有目标"] = { "hasTarget", true }, ["无目标"] = { "hasTarget", false }, ["hasTarget"] = { "hasTarget", true },
  ["可攻击"] = { "canAttack", true }, ["canAttack"] = { "canAttack", true },
  ["可流血"] = { "canBleed", true }, ["canBleed"] = { "canBleed", true },
  ["精英"] = { "isElite", true }, ["isElite"] = { "isElite", true },
  ["Boss"] = { "isBoss", true }, ["首领"] = { "isBoss", true }, ["isBoss"] = { "isBoss", true },
  ["目标战斗中"] = { "tInCombat", true }, ["tInCombat"] = { "tInCombat", true },
  ["目标友善"] = { "tFriendly", true }, ["友善"] = { "tFriendly", true }, ["tFriendly"] = { "tFriendly", true },
  ["目标敌对"] = { "tHostile", true }, ["敌对"] = { "tHostile", true }, ["tHostile"] = { "tHostile", true },
  ["目标中立"] = { "tNeutral", true }, ["中立"] = { "tNeutral", true }, ["tNeutral"] = { "tNeutral", true },
  ["Alt"] = { "alt", true }, ["alt"] = { "alt", true },
  ["Shift"] = { "shift", true }, ["shift"] = { "shift", true },
  ["Ctrl"] = { "ctrl", true }, ["ctrl"] = { "ctrl", true },
  ["普攻"] = { "autoAttack", true }, ["autoAttack"] = { "autoAttack", true },
}
local COND_FLAG = {
  ["就绪"] = "ready", ["ready"] = "ready",
  ["可用"] = "usable", ["usable"] = "usable",
  ["未排队"] = "notQueued", ["notQueued"] = "notQueued",
}

function EVAL_PARSE_ONE(token)
  token = condTrim(token)
  if token == "" then return nil end
  local neg = false
  if string.sub(token, 1, 1) == "!" then neg = true token = condTrim(string.sub(token, 2)) end
  local name, op, num = string.match(token, "^(.-)([><]=?)(%d+)$")
  if name and COND_NUM[condTrim(name)] then
    return { k = COND_NUM[condTrim(name)], op = op, n = tonumber(num) }
  end
  local fn = string.match(token, "^姿态(%d)$")
  if fn then return { k = "form", n = tonumber(fn) } end
  fn = string.match(token, "^非姿态(%d)$")
  if fn then return { k = "formNot", n = tonumber(fn) } end
  local bs = string.match(token, "^无buff[:：](.+)$") or string.match(token, "^noBuff[:=](.+)$")
  if bs then return { k = "noBuff", s = condTrim(bs) } end
  bs = string.match(token, "^有buff[:：](.+)$") or string.match(token, "^hasBuff[:=](.+)$")
  if bs then return { k = "hasBuff", s = condTrim(bs) } end
  -- debuff 层数后缀（1.31.0）：有debuff:破甲>=3（至少3层）/ 无debuff:破甲<3（不足3层）；无后缀=只要有/没有
  -- want: "min"=有debuff(至少N层，只收 >/>=)；"max"=无debuff(不足N层，只收 </<=)。
  -- 1.32.0 审计修复：反向 op（如 有debuff:x<3）语义会反转成 cnt>=3 的静默逻辑坑——降级为无层数限制
  local function auraStack(body, want)
    local nm, op, n = string.match(body, "^(.-)([><]=?=?)(%d+)$")
    if not nm then return condTrim(body), nil end
    if want == "min" and op ~= ">" and op ~= ">=" then return condTrim(nm), nil end
    if want == "max" and op ~= "<" and op ~= "<=" then return condTrim(nm), nil end
    n = tonumber(n)
    if op == ">" then n = n + 1 elseif op == "<=" then n = n + 1 end -- >N 即 >=N+1；<=N 即 <N+1
    return condTrim(nm), n
  end
  bs = string.match(token, "^无debuff[:：](.+)$") or string.match(token, "^noDebuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "max") return { k = "noDebuff", s = nm, n = n } end
  bs = string.match(token, "^有debuff[:：](.+)$") or string.match(token, "^hasDebuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "min") return { k = "hasDebuff", s = nm, n = n } end
  local tc = string.match(token, "^目标职业[:：](.+)$") or string.match(token, "^tClass[:=](.+)$")
  if tc then
    -- 分隔统一成 / 再切：顿号/中文逗号是多字节，直接进字符类会按字节误切汉字（如"猎"含 ，的字节）
    tc = string.gsub(tc, "、", "/")
    tc = string.gsub(tc, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tc, "[^/,]+") do
      local id = CLASS_ID[condTrim(nm)]
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tClass", cs = cs } end
    return nil
  end
  local imt = string.match(token, "^免疫[:：](.+)$") or string.match(token, "^immune[:=](.+)$") -- 1.36.1 免疫条件
  if imt then return { k = "immune", s = condTrim(imt), v = not neg } end
  local imn = string.match(token, "^未免疫[:：](.+)$") or string.match(token, "^notimmune[:=](.+)$")
  if imn then return { k = "immune", s = condTrim(imn), v = false } end
  local tg = string.match(token, "^选取目标[:：](.+)$") or string.match(token, "^target[:=](.+)$")
  if tg then
    -- 指定名称:嗜血者 / byName=嗜血者（1.29.0：名称存 cd.nm）
    local nm = string.match(tg, "^指定名称[:：](.+)$") or string.match(tg, "^byName[:=](.+)$")
    if nm then nm = condTrim(nm) if nm ~= "" then return { k = "target", s = "byName", nm = nm } end return nil end
    local id = TARGET_SEL_ID[condTrim(tg)]
    if id then return { k = "target", s = id } end
    return nil
  end
  local b = COND_BOOL[token]
  if b then return { k = b[1], v = neg and (not b[2]) or b[2] } end
  local fl = COND_FLAG[token]
  if fl then return { k = fl, inv = neg } end
  return nil
end

function EVAL_PARSE_CONDS(str)
  local groups = {}
  for orPart in string.gmatch(str or "", "([^|]+)") do
    local g = {}
    for andPart in string.gmatch(orPart, "([^&]+)") do
      local cd = EVAL_PARSE_ONE(andPart)
      if cd then table.insert(g, cd) end
    end
    if table.getn(g) > 0 then table.insert(groups, g) end
  end
  return groups
end

-- 条件组 → 显示字符串（列表摘要 / 编辑回显）
local COND_NUMNAME = { power = "怒气", tHpPct = "目标血", hpPct = "自身血", powerPct = "能量%", combatTime = "进战", combo = "连击" }
function EVAL_COND_STR(cd)
  local k = cd.k
  if COND_NUMNAME[k] then return COND_NUMNAME[k] .. (cd.op or ">") .. tostring(cd.n) end
  if k == "combat" then return cd.v and "战斗中" or "非战斗" end
  if k == "form" then return "姿态" .. tostring(cd.n) end
  if k == "formNot" then return "非姿态" .. tostring(cd.n) end
  if k == "hasTarget" then return cd.v and "目标存在" or "无目标" end
  if k == "canAttack" then return cd.v and "可攻击" or "不可攻击" end
  if k == "canBleed" then return cd.v and "可流血" or "不可流血" end
  if k == "isElite" then return cd.v and "精英" or "非精英" end
  if k == "isBoss" then return cd.v and "Boss" or "非Boss" end
  if k == "tInCombat" then return cd.v and "目标战斗中" or "目标非战斗" end
  if k == "tFriendly" then return cd.v and "友善" or "非友善" end
  if k == "tHostile" then return cd.v and "敌对" or "非敌对" end
  if k == "tNeutral" then return cd.v and "中立" or "非中立" end
  if k == "alt" then return (cd.v and "" or "!") .. "Alt" end
  if k == "shift" then return (cd.v and "" or "!") .. "Shift" end
  if k == "ctrl" then return (cd.v and "" or "!") .. "Ctrl" end
  if k == "autoAttack" then return cd.v and "普攻" or "未普攻" end
  if k == "hasBuff" then return "有buff:" .. tostring(cd.s) end
  if k == "noBuff" then return "无buff:" .. tostring(cd.s) end
  if k == "hasDebuff" then return "有debuff:" .. tostring(cd.s) .. ((type(cd.n) == "number" and cd.n > 1) and (">=" .. cd.n) or "") end
  if k == "noDebuff" then return "无debuff:" .. tostring(cd.s) .. ((type(cd.n) == "number" and cd.n > 1) and ("<" .. cd.n) or "") end
  if k == "ready" then return cd.inv and "未就绪" or "就绪" end
  if k == "usable" then return cd.inv and "不可用" or "可用" end
  if k == "notQueued" then return cd.inv and "已排队" or "未排队" end
  if k == "target" then
    if cd.s == "byName" then return "选取目标:指定名称:" .. tostring(cd.nm or "?") end
    return "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
  end
  if k == "immune" then return (cd.v == false and "未免疫:" or "免疫:") .. tostring(cd.s) end -- 1.36.1
  if k == "tClass" then
    local ns = {}
    for _, c in ipairs(CLASS_LIST) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.name) end end
    return "目标职业:" .. (table.getn(ns) > 0 and table.concat(ns, "/") or "未选")
  end
  return tostring(k)
end

function EVAL_GROUP_STR(groups)
  local parts = {}
  for _, g in ipairs(groups or {}) do
    local cs = {}
    for _, cd in ipairs(g) do table.insert(cs, EVAL_COND_STR(cd)) end
    table.insert(parts, table.concat(cs, " & "))
  end
  return table.concat(parts, " | ")
end

-- 方案数据：缺省时从 cfg.war 阈值生成默认方案（1.22.0 起含 姿态/冲锋 开怪规则——原硬编码前置已全部规则化）
function EVAL_WAR_ENSURE_PROFILES(w)
  if not w then return end
  if not w.debuffTex then w.debuffTex = {} end -- 1.32.0 审计修复：光环名→纹理学习表从未创建，学习跨会话丢失（1.27.0 遗留）
  if not w.immune then w.immune = {} end -- 1.36.0 免疫学习表（技能@怪名，EVAL_IMMUNE_LEARN 写入）
  if type(w.profiles) ~= "table" or table.getn(w.profiles) == 0 then
    w.profiles = { { name = "默认", skills = {
      { skill = "战斗姿态", enabled = true, why = "非战斗切姿态",
        groups = { { { k = "combat", v = false }, { k = "formNot", n = 1 }, { k = "canAttack", v = true } } } },
      { skill = "冲锋", enabled = true, why = "非战斗冲锋",
        groups = { { { k = "combat", v = false }, { k = "form", n = 1 }, { k = "canAttack", v = true }, { k = "ready" } } } },
      { skill = "压制", enabled = true, why = "压制可用",
        groups = { { { k = "power", op = ">", n = w.ovRage or 5 }, { k = "usable" }, { k = "ready" } } } },
      { skill = "战斗怒吼", enabled = true, why = "怒吼缺失",
        groups = { { { k = "power", op = ">", n = w.bsRage or 9 }, { k = "noBuff", s = "战斗怒吼" } } } },
      { skill = "断筋", enabled = true, why = "挂断筋",
        groups = { { { k = "tHpPct", op = "<", n = w.hamHp or 30 }, { k = "power", op = ">", n = 9 }, { k = "noDebuff", s = "断筋" } } } },
      { skill = "撕裂", enabled = true, why = "挂撕裂",
        groups = { { { k = "canBleed", v = true }, { k = "tHpPct", op = ">", n = w.rendHp or 10 }, { k = "power", op = ">", n = 9 }, { k = "noDebuff", s = "撕裂" } } } },
      { skill = "血性狂暴", enabled = true, why = "补怒气",
        groups = { { { k = "combat", v = true }, { k = "noBuff", s = "血性狂暴" }, { k = "ready" } } } },
      { skill = "猛击", enabled = true, why = "Alt猛击",
        groups = { { { k = "alt", v = true }, { k = "power", op = ">", n = w.slamRage or 20 } } } },
      { skill = "英勇打击", enabled = true, why = "泄怒",
        groups = { { { k = "power", op = ">", n = w.hsRage or 30 }, { k = "notQueued" } } } },
    } } }
  end
  if not w.activeProfile then w.activeProfile = 1 end
end



-- 一键入口：/run EVAL_GO()
-- 可选参数 profSel：0 或不传 = 当前激活方案；1-4 = 直触对应方案；字符串 = 按方案名。
-- 直触不改变激活方案。绑定多按键：宏1 /run EVAL_GO(1)（或 EVAL_GO1()）、宏2 /run EVAL_GO(2)……
function EVAL_GO(profSel)
  if profSel == 0 then profSel = nil end -- 0 = 当前激活方案
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  -- 配置阈值（/eh cfg 或小地图 EH 图标可调；缺省值与原宏一致）
  local w = cfg.war or {}
  if w.enabled == false then
    if GetTime() - wLastHint >= 5 then
      wLastHint = GetTime()
      say("一键宏已禁用（/eh cfg 或小地图 EH 图标里开启）")
    end
    return
  end
  if not wscanned then EVAL_GO_RESCAN(true) end

  -- Shift+按宏 = 切换下一个方案（不施法）；也可点战斗信息UI的方案按钮或 /eh go next
  if IsShiftKeyDown and IsShiftKeyDown() then
    EVAL_WAR_ENSURE_PROFILES(w)
    if w.profiles and table.getn(w.profiles) > 1 then
      w.activeProfile = (w.activeProfile or 1) % table.getn(w.profiles) + 1
      say("切换到方案: " .. tostring(w.profiles[w.activeProfile].name))
    else
      say("只有一个方案，无需切换（配置窗口 一键宏设置页 [+] 新建）")
    end
    return
  end

  -- 刷新角色状态表（Cat 思路：宏只读缓存变量，不重复调 API）
  EVAL_HELP_UPDATE_STATE()
  local rage     = st.power
  local inCombat = st.inCombat
  local battle   = (st.formIndex == 1) -- 战斗姿态

  -- 1) 目标检查：无目标/死亡/不可攻击 → 选最近敌人（st.canAttack）
  -- 1.21.7：选不到敌人【不再硬返回】——自身 buff 类技能（战斗怒吼/血性狂暴等）不需要目标，
  -- 是否该放由方案规则的条件自行判定（攻击类技能用「可攻击/可用」条件兜底）。
  local hostile = st.canAttack
  if not hostile then
    TargetNearestEnemy()
    EVAL_HELP_UPDATE_STATE() -- 换目标后重刷
    hostile = st.canAttack
    wlog("无有效目标 → TargetNearestEnemy；结果=" .. tostring(hostile))
  end

  local thscale  = st.tHpPct / 100
  local ttype    = st.tCreatureType
  local canBleed = st.canBleed -- Cat 的 MPTargetBleed（类型排除+黑白名单，见状态模块）

  -- 2)（1.22.0 移除硬编码「非战斗切姿态/冲锋」前置：它无视方案内容强制出手，是旧战士宏残留。
  --    需要该行为请在方案里加规则：战斗姿态 | 非战斗 & 非姿态1 & 可攻击；冲锋 | 非战斗 & 姿态1 & 可攻击 & 就绪）

  -- 3) 自动普攻（AttackTarget 是切换语义，必须用 IsCurrentAction 守卫，连按安全）
  local atk = wslots["攻击"]
  st.autoAttack = false
  if w.attack ~= false and atk and type(IsCurrentAction) == "function" then
    local okc, cur = pcall(IsCurrentAction, atk.slot)
    if okc and cur then st.autoAttack = true end
    if okc and not cur and GetTime() - wLastAttackTry >= 2 then
      wLastAttackTry = GetTime()
      AttackTarget()
      logLine("→ 开启自动普攻")
      wlog("开启自动普攻")
    end
  end

  -- 4~10) 输出循环 = 指定方案（profSel 参数）或当前激活方案的技能规则表
  EVAL_WAR_ENSURE_PROFILES(w)
  local prof = nil
  if profSel ~= nil then
    if type(profSel) == "number" then
      prof = w.profiles[profSel]
    elseif type(profSel) == "string" then
      for _, p in ipairs(w.profiles) do
        if p.name == profSel then prof = p break end
      end
    end
    if not prof then
      if GetTime() - wLastHint >= 2 then
        wLastHint = GetTime()
        local names = {}
        for _, p in ipairs(w.profiles) do table.insert(names, "[" .. tostring(p.name) .. "]") end
        say("方案不存在: 「" .. tostring(profSel) .. "」现有方案: " .. table.concat(names, " ") .. "（注意全半角引号/名称一致；/eh go list 查看）")
      end
      return
    end
  else
    prof = w.profiles[w.activeProfile or 1]
  end
  if prof and EVAL_RULE_RUN(prof.skills) then return end

  -- 本次按键无动作：打一条状态行，方便对照调阈值
  wlog(string.format("无动作 | 怒气%d 目标血%.0f%% %s%s%s%s",
    rage, thscale * 100,
    inCombat and "战斗中" or "非战斗",
    battle and " 战斗姿态" or "",
    ttype and (" " .. ttype) or "",
    st.isBoss and " Boss" or (st.isElite and " 精英" or "")))
end

-- 技能选择清单（1.24.0）：WAR_SKILLS 白名单在前 + 动作条扫描到的其他技能（去重），编辑窗下拉用
function EVAL_GO_SKILL_CHOICES()
  local list, seen = {}, {}
  for _, n in ipairs(WAR_SKILLS) do
    if not seen[n] then seen[n] = true table.insert(list, n) end
  end
  if wscanned and wslots then
    local extra = {}
    for n in pairs(wslots) do
      if not seen[n] then table.insert(extra, n) end
    end
    table.sort(extra)
    for _, n in ipairs(extra) do table.insert(list, n) end
  end
  for _, p in ipairs(PET_CMD) do table.insert(list, "宠物:" .. p.name) end -- 1.30.0 特殊技能段
  return list
end

-- 技能二级分类（1.32.0）：编辑窗技能名下拉先选类再选项。
-- 五类：角色行为(攻击) / 角色技能(白名单+动作条扫描) / 宠物行为 / 目标选取 / 物品使用(背包实时扫描+自定义名)
-- items 为函数：点开时才取数（背包/动作条是动态的）
function EVAL_GO_SKILL_CATEGORIES()
  local cats = {}
  table.insert(cats, { label = L("SK_CAT_1"), items = function() return { "攻击" } end })
  table.insert(cats, { label = L("SK_CAT_2"), items = function()
    local list, seen = {}, {}
    for _, n in ipairs(WAR_SKILLS) do
      if n ~= "攻击" and not seen[n] then seen[n] = true table.insert(list, n) end
    end
    if wscanned and wslots then
      local extra = {}
      for n in pairs(wslots) do
        if not seen[n] and n ~= "攻击" then table.insert(extra, n) end
      end
      table.sort(extra)
      for _, n in ipairs(extra) do table.insert(list, n) end
    end
    return list
  end })
  table.insert(cats, { label = L("SK_CAT_3"), items = function()
    local l = {}
    for _, p in ipairs(PET_CMD) do table.insert(l, "宠物:" .. p.name) end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_4"), items = function()
    local l = {}
    for _, t in ipairs(TARGET_SEL) do
      if t.needsName then table.insert(l, L("SE_PICK_TGT"))
      else table.insert(l, "选取目标:" .. t.name) end
    end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_5"), items = function()
    local l, seen = {}, {}
    if type(GetContainerNumSlots) == "function" then
      for bag = 0, 4 do
        local okn, slots = pcall(GetContainerNumSlots, bag)
        if okn and slots and slots > 0 then
          for slot = 1, slots do
            local okl, link = pcall(GetContainerItemLink, bag, slot)
            local nm = okl and link and string.match(link, "%[(.-)%]")
            if nm and not seen[nm] then
              seen[nm] = true
              local oki, tex, cnt = pcall(GetContainerItemInfo, bag, slot)
              table.insert(l, "物品:" .. nm .. ((oki and cnt and cnt > 1) and ("×" .. cnt) or ""))
            end
          end
        end
      end
      table.sort(l)
      while table.getn(l) > 46 do table.remove(l) end -- DD 行池上限 48（首行留给自定义）
    end
    table.insert(l, 1, L("SE_PICK_ITEM"))
    return l
  end })
  return cats
end

-- 方案直触便捷函数：宏正文 /run EVAL_GO2() 即可把方案2 绑到独立按键
function EVAL_GO1() EVAL_GO(1) end
function EVAL_GO2() EVAL_GO(2) end
function EVAL_GO3() EVAL_GO(3) end
function EVAL_GO4() EVAL_GO(4) end

-- /eh war 的状态总览
function EVAL_GO_STATUS()
  if not wscanned then EVAL_GO_RESCAN(true) end
  say("— 一键宏状态 —")
  for _, n in ipairs(WAR_SKILLS) do
    local s = wslots[n]
    if s then
      local ready, why = wready(n)
      say(string.format("%s: 格子%d %s", n, s.slot, ready and "|cff00ff00就绪|r" or ("|cffff9040" .. tostring(why) .. "|r")))
    else
      say(n .. ": |cffff0000未上动作条|r")
    end
  end
  say("当前: " .. formatStats(collectStats()))
end

-- ============ 状态 UI（参考 Cat 的 CatUI-Melee 布局，构件法用 OneJudge HUD 的已验证写法） ============
-- /eh ui 开关窗口；按住顶部标题栏拖动换位置（自动记忆）；悬停滚轮缩放（0.5~1.6，自动重建）。
-- 内容：血条 / 能量条（怒气红·法力蓝·能量黄）/ 目标条 / 状态行 / 技能图标行。
-- 刷新：OnUpdate 每 0.15s 一次，窗口隐藏时不刷新（Cat 的 MPCatUIMeleeRun 同款节流）。
-- 注意（OneJudge 实测教训）：不用 SetScale（会引发命中区/位置漂移），缩放 = 几何尺寸 × 系数后重建；
--      不用 StatusBar 控件，用纯色 Texture 按宽度填充；字体按 FZLBJW→FRIZQT→ARIALN 顺序尝试。

local ui = { root = nil }
local UI_TICK = 0.15
local uiLastTick = 0

local function uiCfg()
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  if not cfg.ui then cfg.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
  return cfg.ui
end

-- 纯色纹理：SetTexture(RGB) 本客户端未文档化，先按颜色试，失败退回官方底图+顶点色（OneJudge 同款）
local function uiSolid(t, r, g, b, a)
  local ok = pcall(t.SetTexture, t, r, g, b)
  if not ok then
    pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8")
    pcall(t.SetVertexColor, t, r, g, b, a or 1)
  end
end

-- 字体字符串：中文字体优先（FZLBJW=方正隶变），失败逐级回退
local function uiText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local set = false
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    local okF, ok2 = pcall(fs.SetFont, fs, fp, size, "OUTLINE")
    if not (okF and ok2) then okF, ok2 = pcall(fs.SetFont, fs, fp, size) end
    if okF and ok2 then set = true break end
  end
  if not set then pcall(fs.SetTextHeight, fs, size) end
  fs:SetTextColor(r, g, b)
  return fs
end

-- 一条状态条：深色底框 + 彩色填充层（宽度=比例）+ 居中文字
local function uiMakeBar(parent, w, h)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(w) bar:SetHeight(h)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.08, 0.08, 0.10, 0.9)
  bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  uiSolid(fill, 0.5, 0.5, 0.5, 1)
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
  fill:SetHeight(h - 2)
  pcall(fill.SetWidth, fill, 1)
  local text = uiText(bar, math.max(8, h - 6), 1, 1, 1)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  return bar, fill, text, w - 2
end

-- 技能格：图标 + 冷却数字（亮=就绪/激活，暗=不可用；OneJudge 窗格简化版）
local function uiMakeCell(parent, size)
  local cell = CreateFrame("Frame", nil, parent)
  cell:SetWidth(size) cell:SetHeight(size)
  local bg = cell:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.12, 0.12, 0.12, 1)
  bg:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
  local icon = cell:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
  uiSolid(icon, 0.2, 0.2, 0.2, 1)
  local text = uiText(cell, math.max(8, math.floor(size * 0.45)), 1, 1, 0.4)
  text:SetPoint("CENTER", cell, "CENTER", 0, 0)
  return { frame = cell, bg = bg, icon = icon, text = text }
end

-- 图标行监控的技能（按显示顺序）
local UI_ICONS = { "攻击", "冲锋", "压制", "战斗怒吼", "断筋", "撕裂", "血性狂暴" }

-- 方案配置访问（配置段的 warCfg 在本段之后定义，这里直接走全局 SavedVariables + 迁移函数）
local function uiWarCfg()
  local cc = EVAL_HELP_CONFIG
  if type(cc) ~= "table" then cc = {} EVAL_HELP_CONFIG = cc end
  if type(cc.war) ~= "table" then cc.war = {} end
  EVAL_WAR_ENSURE_PROFILES(cc.war)
  return cc.war
end

-- 当前方案第 i 条规则（技能编辑窗/方案技能行共用）
local function uiWarActiveRule(i)
  local w2 = uiWarCfg()
  local p = w2.profiles and w2.profiles[w2.activeProfile or 1]
  return (p and p.skills) and p.skills[i] or nil
end

-- 重建/新建战斗信息UI（改缩放时整帧重建，见上方 SetScale 说明）
function EVAL_HELP_UI_BUILD()
  local u = uiCfg()
  local z = (type(u.scale) == "number" and u.scale >= 0.4) and u.scale or 1
  if ui.root then
    ui.root:Hide()
    pcall(ui.root.SetScript, ui.root, "OnUpdate", nil)
  end

  local root = CreateFrame("Frame", "EVAL_HELP_UI", UIParent)
  pcall(root.SetFrameStrata, root, "MEDIUM")
  pcall(root.SetFrameLevel, root, 10)
  pcall(root.EnableMouse, root, true)   -- 本体只接收滚轮（缩放），不注册拖动
  pcall(root.SetMovable, root, true)

  local W = math.floor(240 * z)
  local pad = math.floor(8 * z)
  local barH = math.floor(14 * z)
  local gap = math.floor(4 * z)
  local cell = math.floor(26 * z)

  -- 标题栏 = 拖动手柄：只有按住标题条才能拖动窗口（需求 1）。
  -- UnrealQuest 实测五件套：Handle 必须是【Button】（Frame 的拖拽在本客户端不触发）、
  -- SetFrameLevel 抬高 +10（用 strata 抬高是记录在案的失败做法）、EnableMouse、
  -- RegisterForClicks、RegisterForDrag。
  local titleBarH = math.floor(16 * z)
  local titleBar = CreateFrame("Button", nil, root)
  -- 标题条与内容条同宽（内缩 pad；1.20.1 修复标题条两边超出内容区的问题）
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, 0)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -pad, 0)
  titleBar:SetHeight(titleBarH)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10)
  end
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 0.95)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, math.max(9, math.floor(11 * z)), 0.9, 0.8, 0.4)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText("战斗信息")

  -- 三条状态条：血 / 能量 / 目标
  local y = titleBarH + gap
  local barW = W - pad * 2
  local hpBar, hpFill, hpText, hpW = uiMakeBar(root, barW, barH)
  hpBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
  y = y + barH + gap
  local pwBar, pwFill, pwText, pwW = uiMakeBar(root, barW, barH)
  pwBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
  y = y + barH + gap
  local tgBar, tgFill, tgText, tgW = uiMakeBar(root, barW, barH)
  tgBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
  y = y + barH + gap

  -- 状态行：战斗状态 · 姿态 · 普攻
  local status = uiText(root, math.max(8, math.floor(10 * z)), 0.75, 0.75, 0.75)
  status:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
  y = y + math.floor(13 * z) + gap

  -- 技能图标行
  local cells = {}
  local x = pad
  for _, name in ipairs(UI_ICONS) do
    local c = uiMakeCell(root, cell)
    c.frame:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    c.name = name
    table.insert(cells, c)
    x = x + cell + gap
  end
  y = y + cell + gap

  -- 方案切换行：点击按钮换激活方案（一键宏立即换套路；Shift+按宏 / /eh war next 也可切）
  local profBtns = {}
  local plabel = uiText(root, math.max(8, math.floor(9 * z)), 0.95, 0.82, 0.35)
  plabel:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -(y + math.floor(3 * z)))
  plabel:SetText("方案")
  local pbw = math.floor((W - pad * 2 - math.floor(28 * z)) / 4)
  for i = 1, 4 do
    local pb = CreateFrame("Button", nil, root)
    pb:SetWidth(pbw) pb:SetHeight(math.floor(15 * z))
    pb:SetPoint("TOPLEFT", root, "TOPLEFT", pad + math.floor(28 * z) + (i - 1) * pbw, -y)
    pcall(pb.EnableMouse, pb, true)
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp")
    local pbg = pb:CreateTexture(nil, "BACKGROUND")
    uiSolid(pbg, 0.16, 0.13, 0.08, 1)
    pbg:SetPoint("TOPLEFT", pb, "TOPLEFT", 0, 0)
    pbg:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", 0, 0)
    local pt = uiText(pb, math.max(7, math.floor(9 * z)), 0.85, 0.80, 0.70)
    pt:SetPoint("CENTER", pb, "CENTER", 0, 0)
    local pidx = i
    pb:SetScript("OnClick", function()
      local w2 = uiWarCfg()
      if w2.profiles and w2.profiles[pidx] then
        w2.activeProfile = pidx
        say("切换到方案: " .. tostring(w2.profiles[pidx].name))
      end
    end)
    profBtns[i] = { btn = pb, bg = pbg, text = pt }
  end
  y = y + math.floor(16 * z) + gap

  -- 方案技能列表行：当前方案的技能图标（悬停 tooltip 看触发条件；点击开编辑窗；亮=条件当前满足）
  local profCells = {}
  local pcell = math.floor(24 * z)
  local pgap2 = math.floor(3 * z)
  local px = pad
  for i = 1, 8 do
    local cb = CreateFrame("Button", nil, root)
    cb:SetWidth(pcell) cb:SetHeight(pcell)
    cb:SetPoint("TOPLEFT", root, "TOPLEFT", px, -y)
    pcall(cb.EnableMouse, cb, true)
    pcall(cb.RegisterForClicks, cb, "LeftButtonUp")
    local cbg = cb:CreateTexture(nil, "BACKGROUND")
    uiSolid(cbg, 0.45, 0.38, 0.15, 1)
    cbg:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
    cbg:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
    local cicon = cb:CreateTexture(nil, "ARTWORK")
    uiSolid(cicon, 0.2, 0.2, 0.2, 1)
    cicon:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
    cicon:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
    local ctext = uiText(cb, math.max(7, math.floor(9 * z)), 1, 1, 0.4)
    ctext:SetPoint("CENTER", cb, "CENTER", 0, 0)
    local ci = i
    cb:SetScript("OnEnter", function()
      local r = uiWarActiveRule(ci)
      if not r then return end
      GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
      GameTooltip:AddLine(tostring(r.skill), 1, 0.82, 0.3)
      GameTooltip:AddLine((r.enabled ~= false) and ("|cff00ff00" .. L("TIP_ON") .. "|r") or ("|cffff0000" .. L("TIP_OFF") .. "|r"))
      GameTooltip:AddLine(L("TIP_COND_H"), 0.62, 0.55, 0.40)
      local gcount = 0
      for gi, g in ipairs(r.groups or {}) do
        gcount = gi
        local cs = {}
        for _, cd in ipairs(g) do table.insert(cs, EVAL_COND_STR(cd)) end
        GameTooltip:AddLine(string.format("%d. %s", gi, table.concat(cs, " & ")), 0.85, 0.85, 0.85)
      end
      if gcount == 0 then
        GameTooltip:AddLine(L("TIP_NOCOND"), 0.6, 0.6, 0.6)
      end
      GameTooltip:AddLine(L("TIP_CLICK"), 0.5, 0.5, 0.5)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function()
      local w2 = uiWarCfg()
      local p = w2.profiles and w2.profiles[w2.activeProfile or 1]
      if p and p.skills[ci] then EVAL_HELP_SE_OPEN(w2.activeProfile or 1, ci) end
    end)
    profCells[i] = { btn = cb, bg = cbg, icon = cicon, text = ctext }
    px = px + pcell + pgap2
  end
  y = y + pcell + pad

  root:SetWidth(W)
  root:SetHeight(y)
  root:ClearAllPoints()
  root:SetPoint("CENTER", UIParent, "CENTER", u.x or 0, u.y or -180)
  if uiOffscreen(root) then -- 记忆位置飞出屏幕 → 回归视野中心
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    u.x, u.y = 0, -180
  end

  -- 按住标题栏拖动换位置，松手记坐标（GetCenter 已含 effectiveScale，要除回去——OneJudge 1.7.2 的修复）
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, cx, cy = pcall(root.GetCenter, root)
    if ok and cx then
      local okw, w2 = pcall(UIParent.GetWidth, UIParent)
      local okh, h2 = pcall(UIParent.GetHeight, UIParent)
      if okw and okh and w2 and h2 then
        local oke, es = pcall(root.GetEffectiveScale, root)
        local k = (oke and type(es) == "number" and es > 0) and es or 1
        u.x = (cx - w2 / 2) / k
        u.y = (cy - h2 / 2) / k
      end
    end
  end)

  -- 悬停滚轮缩放（EnableMouseWheel 本客户端可能缺，全程 pcall——OneJudge 1.7.2 教训）
  if pcall(root.EnableMouseWheel, root, true) then
    pcall(root.SetScript, root, "OnMouseWheel", function(a, b)
      local d = 0
      if type(b) == "number" then d = b
      elseif type(a) == "number" then d = a
      elseif type(arg1) == "number" then d = arg1 end
      if d == 0 then return end
      local s = (u.scale or 1) + (d > 0 and 0.1 or -0.1)
      s = math.min(1.6, math.max(0.5, s))
      if math.abs(s - (u.scale or 1)) > 1e-9 then
        u.scale = s
        EVAL_HELP_UI_BUILD()
        if ui.root then ui.root:Show() end
      end
    end)
  end

  ui.root, ui.title = root, title
  ui.hpFill, ui.hpText, ui.hpW = hpFill, hpText, hpW
  ui.pwFill, ui.pwText, ui.pwW = pwFill, pwText, pwW
  ui.tgBar, ui.tgFill, ui.tgText, ui.tgW = tgBar, tgFill, tgText, tgW
  ui.status, ui.cells = status, cells
  ui.profBtns, ui.profCells = profBtns, profCells

  root:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - uiLastTick < UI_TICK then return end
    uiLastTick = now
    EVAL_HELP_UI_TICK()
  end)
end

-- 填充条刷新工具
local function uiSetBar(fill, text, maxW, frac, r, g, b, str)
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  pcall(fill.SetWidth, fill, math.max(1, maxW * frac))
  pcall(fill.SetVertexColor, fill, r, g, b, 1)
  text:SetText(str)
end

-- 每个心跳刷新（窗口隐藏时直接返回——Cat 同款）
function EVAL_HELP_UI_TICK()
  if not ui.root or not ui.root:IsVisible() then return end

  -- 统一走角色状态表（每次心跳刷新一次，之后只读变量——Cat 思路）
  EVAL_HELP_UPDATE_STATE()

  -- 血条：绿→红渐变
  local hfrac = (st.hpMax and st.hpMax > 0) and (st.hp / st.hpMax) or 0
  uiSetBar(ui.hpFill, ui.hpText, ui.hpW, hfrac, 1 - hfrac, hfrac, 0.15,
    string.format("%d/%d  %d%%", st.hp, st.hpMax, math.floor(hfrac * 100 + 0.5)))

  -- 能量条：按能量类型配色（0法力蓝 1怒气红 2集中橙 3能量黄）
  local pfrac = (st.powerMax and st.powerMax > 0) and (st.power / st.powerMax) or 0
  local pr, pg, pb = 0.25, 0.45, 0.90
  if st.powerType == 1 then pr, pg, pb = 0.90, 0.20, 0.25
  elseif st.powerType == 2 then pr, pg, pb = 0.90, 0.50, 0.20
  elseif st.powerType == 3 then pr, pg, pb = 1.00, 1.00, 0.40 end
  uiSetBar(ui.pwFill, ui.pwText, ui.pwW, pfrac, pr, pg, pb,
    string.format("%s %d/%d", powerLabel(), st.power, st.powerMax))

  -- 目标条
  if st.hasTarget then
    local tfrac = st.tHpPct / 100
    uiSetBar(ui.tgFill, ui.tgText, ui.tgW, tfrac, 0.80, 0.20, 0.20,
      string.format("%s  %d%%", tostring(st.targetName), math.floor(tfrac * 100 + 0.5)))
  else
    uiSetBar(ui.tgFill, ui.tgText, ui.tgW, 0, 0.3, 0.3, 0.3, "无目标")
  end

  -- 状态行
  local inCombat = st.inCombat
  local form = st.form or "无姿态"
  local atkOn = false
  if wslots["攻击"] and type(IsCurrentAction) == "function" then
    local oka, cur = pcall(IsCurrentAction, wslots["攻击"].slot)
    atkOn = oka and cur and true or false
  end
  st.autoAttack = atkOn -- 同步进状态表（Cat 的 MPAutoAttack）
  ui.status:SetText(string.format("%s · %s · 普攻:%s",
    inCombat and "|cffff5040战斗中|r" or "|cff80ff80非战斗|r",
    form, atkOn and "|cff00ff00开|r" or "|cff909090关|r"))

  -- 技能图标行（依赖一键模块的 wslots；未扫描先静默扫一次）
  if not wscanned then EVAL_GO_RESCAN(true) end
  for _, c in ipairs(ui.cells) do
    local s = wslots[c.name]
    if not s then
      pcall(c.icon.SetVertexColor, c.icon, 0.25, 0.25, 0.25)
      c.text:SetText("?")
    else
      local t0 = wicon(c.name)
      if t0 then pcall(c.icon.SetTexture, c.icon, t0) end
      local lit = false
      if c.name == "攻击" then
        lit = atkOn
      elseif c.name == "战斗怒吼" or c.name == "血性狂暴" then
        lit = wPlayerHasBuff(s.tex)
      elseif c.name == "断筋" or c.name == "撕裂" then
        lit = wTargetHasDebuff(s.tex)
      elseif c.name == "压制" then
        local oku, usable = pcall(IsUsableAction, s.slot)
        lit = oku and usable and true or false
      elseif c.name == "冲锋" then
        lit = not inCombat
      end
      -- 冷却数字
      local left = 0
      local okc, st, dur = pcall(GetActionCooldown, c.name == "攻击" and -1 or s.slot)
      if okc and type(st) == "number" and type(dur) == "number" and st > 0 and dur > 0 then
        left = st + dur - GetTime()
      end
      if left > 0 then
        c.text:SetText(left >= 10 and string.format("%d", math.floor(left + 0.5)) or string.format("%.1f", left))
        pcall(c.icon.SetVertexColor, c.icon, 0.4, 0.4, 0.4)
      else
        c.text:SetText("")
        if lit then
          pcall(c.icon.SetVertexColor, c.icon, 1, 1, 1)
          pcall(c.bg.SetVertexColor, c.bg, 0.9, 0.75, 0.1, 1) -- 激活：金边
        else
          pcall(c.icon.SetVertexColor, c.icon, 0.45, 0.45, 0.45)
          pcall(c.bg.SetVertexColor, c.bg, 0.12, 0.12, 0.12, 1)
        end
      end
    end
  end

  -- 方案切换行：当前激活金色高亮，不存在的方案位隐藏
  if ui.profBtns then
    local w2 = uiWarCfg()
    for i, pb in ipairs(ui.profBtns) do
      local prof = w2.profiles and w2.profiles[i]
      if prof then
        pb.btn:Show()
        pb.text:SetText(tostring(prof.name or i))
        local sel = (w2.activeProfile or 1) == i
        pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
        pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.72, sel and 0.9 or 0.68, sel and 0.4 or 0.55)
      else
        pb.btn:Hide()
      end
    end
  end

  -- 方案技能列表：亮金=条件当前满足（实时反馈），半暗=条件不满足，灰+停=已停用
  if ui.profCells then
    for i, pc in ipairs(ui.profCells) do
      local r = uiWarActiveRule(i)
      if not r then
        pc.btn:Hide()
      else
        pc.btn:Show()
        local s = wslots[r.skill]
        local t0 = wicon(r.skill)
        if t0 then pcall(pc.icon.SetTexture, pc.icon, t0) end
        local enabled = r.enabled ~= false
        local pass = false
        if enabled and (s or petCmdOf(r.skill) or targetSelOf(r.skill) or itemOf(r.skill)) and r.groups then -- 宠物/选取目标/物品不占动作条也参与亮金（1.30.0/1.32.0）
          local okp = groupsOK(r, true) -- dry: 亮金预览不触发选取目标等副作用
          pass = okp and true or false
        end
        if not enabled then
          pcall(pc.icon.SetVertexColor, pc.icon, 0.25, 0.25, 0.25)
          pc.text:SetText("停")
        elseif not s and not petCmdOf(r.skill) and not targetSelOf(r.skill) and not itemOf(r.skill) then -- 宠物/选取目标/物品不占动作条不算缺失（1.30.0/1.32.0）
          pcall(pc.icon.SetVertexColor, pc.icon, 0.35, 0.35, 0.35)
          pc.text:SetText("?")
        elseif pass then
          pcall(pc.icon.SetVertexColor, pc.icon, 1, 1, 1)
          pc.text:SetText("")
        else
          pcall(pc.icon.SetVertexColor, pc.icon, 0.55, 0.55, 0.55)
          pc.text:SetText("")
        end
        if pass and enabled then
          pcall(pc.bg.SetVertexColor, pc.bg, 1, 0.85, 0.3, 1) -- 条件满足：亮金描边
        else
          pcall(pc.bg.SetVertexColor, pc.bg, 0.45, 0.38, 0.15, 1)
        end
      end
    end
  end
end

-- /eh ui 开关
function EVAL_HELP_UI_TOGGLE()
  local u = uiCfg()
  if ui.root and ui.root:IsVisible() then
    ui.root:Hide()
    u.enabled = false
    say("战斗信息UI: |cffff0000关|r")
  else
    EVAL_HELP_UI_BUILD()
    if ui.root then ui.root:Show() end
    u.enabled = true
    say("战斗信息UI: |cff00ff00开|r（按住标题栏拖动换位置，滚轮缩放）")
  end
end

-- ============ 配置窗口 + 小地图图标（参考 UnrealQuest 设置面板：深底金边 + 金框勾选 + 滑条 + 底部关闭） ============
-- 打开方式：小地图左侧金色「EH」图标，或 /eh cfg。改动即时写入 EVAL_HELP_CONFIG（SavedVariables 自动存档）。
-- 窗口按 UnrealQuest 的实测构件法：纯色纹理(WHITE8X8)+金边、自绘勾选框/滑条，不依赖任何客户端贴图/模板/Slider 控件。

local cfgWin = { root = nil, refresh = nil }
local wLastHint = 0

local function c()
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  return cfg
end

local function warCfg()
  local cc = c()
  if not cc.war then
    cc.war = { enabled = true, attack = true, hsRage = 30, slamRage = 20, hamHp = 30, rendHp = 10, ovRage = 5, bsRage = 9 }
  end
  EVAL_WAR_ENSURE_PROFILES(cc.war) -- 方案数据迁移（缺省生成默认方案）
  return cc.war
end

-- 金框勾选框（参考截图的方形金框 checkbox）：Button + 外金框 + 内暗底 + 打勾金色块
local function cfgCheck(parent, x, y, label, get, set, list)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(16) b:SetHeight(16)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local outer = b:CreateTexture(nil, "BACKGROUND")
  uiSolid(outer, 0.85, 0.70, 0.20, 1)
  outer:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  outer:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local inner = b:CreateTexture(nil, "ARTWORK")
  uiSolid(inner, 0.10, 0.09, 0.06, 1)
  inner:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  local mark = b:CreateTexture(nil, "OVERLAY")
  uiSolid(mark, 0.95, 0.80, 0.25, 1)
  mark:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  local text = uiText(parent, 11, 0.92, 0.88, 0.80)
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 22, y - 3)
  text:SetText(label)
  if list then table.insert(list, b) table.insert(list, text) end
  local function refresh()
    if get() then mark:Show() else mark:Hide() end
  end
  b:SetScript("OnClick", function()
    set(not get())
    refresh()
  end)
  refresh()
  return refresh
end

-- 阈值滑条：UnrealQuest 实测配方——本客户端不用 Slider 控件，
-- 用 track Frame + thumb Button + RegisterForDrag 自绘；拖动含 warm-up 两步；OnUpdate 实时回写数值。
local function cfgSlider(parent, x, y, w, label, get, set, list)
  local text = uiText(parent, 10, 0.92, 0.88, 0.80)
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  text:SetText(label)
  local valText = uiText(parent, 11, 1, 0.85, 0.35)
  valText:SetPoint("TOPLEFT", parent, "TOPLEFT", x + w + 6, y - 13)
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(w) track:SetHeight(8)
  track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
  local trackBg = track:CreateTexture(nil, "BACKGROUND")
  uiSolid(trackBg, 0.06, 0.05, 0.04, 1)
  trackBg:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  trackBg:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
  local trackEdge = track:CreateTexture(nil, "BORDER")
  uiSolid(trackEdge, 0.85, 0.70, 0.20, 0.7)
  trackEdge:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 1)
  trackEdge:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, 1)
  trackEdge:SetHeight(1)
  local thumb = CreateFrame("Button", nil, track)
  thumb:SetWidth(12) thumb:SetHeight(14)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
  uiSolid(thumbTex, 0.95, 0.80, 0.25, 1)
  thumbTex:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
  thumbTex:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
  pcall(thumb.EnableMouse, thumb, true)
  pcall(thumb.RegisterForClicks, thumb, "LeftButtonUp")
  pcall(thumb.RegisterForDrag, thumb, "LeftButton")
  local dragging = false
  local function place(v)
    v = math.max(0, math.min(100, v or 0))
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", track, "LEFT", (v / 100) * (w - 12), 0)
  end
  local function read()
    local ok1, tl = pcall(thumb.GetLeft, thumb)
    local ok2, kl = pcall(track.GetLeft, track)
    if not (ok1 and ok2 and tl and kl) then return nil end
    local usable = w - 12
    if usable <= 0 then return nil end
    local off = tl - kl
    if off < 0 then off = 0 elseif off > usable then off = usable end
    return math.floor(off / usable * 100 + 0.5)
  end
  thumb:SetScript("OnDragStart", function()
    pcall(thumb.SetMovable, thumb, true)
    pcall(thumb.StartMoving, thumb)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(thumb.StopMovingOrSizing, thumb)
    if pcall(thumb.StartMoving, thumb) then dragging = true end
  end)
  thumb:SetScript("OnUpdate", function()
    if not dragging then return end
    local v = read()
    if v then set(v) valText:SetText(tostring(v)) end
  end)
  thumb:SetScript("OnDragStop", function()
    local v = read()
    dragging = false
    pcall(thumb.StopMovingOrSizing, thumb)
    if v then set(v) valText:SetText(tostring(v)) end
    place(v or (get() or 0))
  end)
  if list then
    table.insert(list, text) table.insert(list, valText)
    table.insert(list, track) table.insert(list, thumb)
  end
  place(get() or 0)
  valText:SetText(tostring(get() or 0))
  return function() place(get() or 0) valText:SetText(tostring(get() or 0)) end
end

-- 章节标题
local function cfgHeader(parent, x, y, label, list)
  local t = uiText(parent, 11, 0.95, 0.80, 0.30)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetText(label)
  if list then table.insert(list, t) end
end

-- 构建配置窗口（只建一次；开关 = Show/Hide）
local function cfgBuild()
  if cfgWin.root then return cfgWin.root end
  local WIDE = (EH_LANG ~= "zhCN") -- 1.34.1 i18n：西文（英/俄）比中文宽 ~1.5 倍，窗口与右列自适应加宽
local W, H = WIDE and 700 or 560, 420
  local root = CreateFrame("Frame", "EVAL_HELP_CFG", UIParent)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.EnableMouse, root, true)
  pcall(root.SetMovable, root, true)
  root:SetWidth(W) root:SetHeight(H)
  -- 位置：默认左移错开 UnrealQuest 的居中设置窗口；拖动后按记忆位置恢复
  root:ClearAllPoints()
  local pos = c().cfgPos
  if pos and type(pos.point) == "string" then
    pcall(root.SetPoint, root, pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    root:SetPoint("CENTER", UIParent, "CENTER", -320, -30)
  end

  -- 深底 + 1px 金边（四边纯色纹理，不依赖客户端贴图）
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.95)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end

  -- 标题栏（拖动柄，与状态窗口同一套逻辑：Button + frame level +10，见状态窗口注释）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(20)
  local okLvl2, rootLvl2 = pcall(root.GetFrameLevel, root)
  if okLvl2 and type(rootLvl2) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl2 + 10)
  end
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, point, _, relPoint, x, y = pcall(root.GetPoint, root, 1)
    if ok and type(point) == "string" then
      c().cfgPos = {
        point = point,
        relPoint = (type(relPoint) == "string") and relPoint or point,
        x = (type(x) == "number") and x or 0,
        y = (type(y) == "number") and y or 0,
      }
    end
  end)
  local title = uiText(titleBar, 12, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("CFG_TITLE"))

  -- 语言选择（1.34.0 i18n P0）：标题栏右上角国旗行 [CN][EN][RU]——国旗纹理盖住 ASCII 徽标，
  -- 纹理加载失败徽标仍在（任何语言都能找到回家的路）；选中=不透明/未选=30%透/悬停=95%；
  -- 不入 G/Wp 页清单——常驻标题栏两个 Tab 都可见；切换存 cfg.lang + 新语言提示 /reload
  local EH_FLAGS = {
    { code = "zhCN", badge = "CN", flag = "cn" },
    { code = "enUS", badge = "EN", flag = "en" },
    { code = "ruRU", badge = "RU", flag = "ru" },
  }
  cfgWin.langBtns = {}
  EVAL_HELP_CFGWIN = cfgWin -- 全局桥：供 EVAL_HELP_LANG_REFRESH（定义在本 local 声明之前）使用
  for i, lg in ipairs(EH_FLAGS) do
    local fb = CreateFrame("Button", nil, root)
    fb:SetWidth(18) fb:SetHeight(14)
    fb:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8 - (table.getn(EH_FLAGS) - i) * 21, -3)
    pcall(fb.EnableMouse, fb, true)
    pcall(fb.RegisterForClicks, fb, "LeftButtonUp")
    local okLF, tLvl = pcall(titleBar.GetFrameLevel, titleBar)
    if okLF and type(tLvl) == "number" then pcall(fb.SetFrameLevel, fb, tLvl + 5) end -- 高过拖动柄
    local fbg = fb:CreateTexture(nil, "BACKGROUND")
    uiSolid(fbg, 0.10, 0.09, 0.06, 1)
    fbg:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
    fbg:SetPoint("BOTTOMRIGHT", fb, "BOTTOMRIGHT", 0, 0)
    local badge = uiText(fb, 9, 0.92, 0.92, 0.92)
    badge:SetPoint("CENTER", fb, "CENTER", 0, 0)
    badge:SetText(lg.badge)
    local ft = fb:CreateTexture(nil, "ARTWORK")
    ft:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
    ft:SetPoint("BOTTOMRIGHT", fb, "BOTTOMRIGHT", 0, 0)
    pcall(ft.SetTexture, ft, "Interface\\AddOns\\EvalHelp\\media\\Flags\\" .. lg.flag .. ".tga")
    fb.langCode = lg.code
    fb:SetScript("OnClick", function()
      if EVAL_SET_LANG(lg.code) then EVAL_HELP_LANG_REFRESH() end
    end)
    fb:SetScript("OnEnter", function() if EH_LANG ~= lg.code then pcall(fb.SetAlpha, fb, 0.95) end end)
    fb:SetScript("OnLeave", function() EVAL_HELP_LANG_REFRESH() end)
    cfgWin.langBtns[i] = fb
  end
  EVAL_HELP_LANG_REFRESH()

  local refreshes = {}

  -- Tab 按钮行（全局 / 一键宏设置；选中=金底亮字，未选=暗底灰字——参考 UnrealQuest 标签页风格）
  local pages = {}
  cfgWin.pages = pages
  local tabNames = { L("TAB_GLOBAL"), L("TAB_MACRO") }
  for i, name in ipairs(tabNames) do
    local tb = CreateFrame("Button", nil, root)
    tb:SetWidth(90) tb:SetHeight(18)
    tb:SetPoint("TOPLEFT", root, "TOPLEFT", 12 + (i - 1) * 96, -26)
    pcall(tb.EnableMouse, tb, true)
    pcall(tb.RegisterForClicks, tb, "LeftButtonUp")
    local tbg = tb:CreateTexture(nil, "BACKGROUND")
    uiSolid(tbg, 0.16, 0.13, 0.08, 1)
    tbg:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
    tbg:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
    local tt = uiText(tb, 11, 0.95, 0.82, 0.35)
    tt:SetPoint("CENTER", tb, "CENTER", 0, 0)
    tt:SetText(name)
    local idx = i
    tb:SetScript("OnClick", function() EVAL_HELP_CFG_SETTAB(idx) end)
    pages[i] = { btn = tb, bg = tbg, text = tt, widgets = {} }
  end

  local LX, RX, RW = 18, WIDE and 330 or 250, 160 -- RX 右列随语言加宽

  -- ===== Tab 1「全局」：日志 / 界面 / 帮助（非职业相关） =====
  local G = pages[1].widgets
  cfgHeader(root, LX, -56, L("G_LOG_H"), G)
  table.insert(refreshes, cfgCheck(root, LX, -74, L("G_LOG_FILE"),
    function() return c().log end, function(v) c().log = v end, G))
  table.insert(refreshes, cfgCheck(root, LX, -98, L("G_LOG_AUTO"),
    function() return c().auto end, function(v) c().auto = v end, G))

  cfgHeader(root, LX, -138, L("G_UI_H"), G)
  table.insert(refreshes, cfgCheck(root, LX, -156, L("G_UI_COMBAT"),
    function() local u = c(); return u.ui and u.ui.enabled end,
    function(v)
      local u = c()
      if not u.ui then u.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
      if v ~= (u.ui.enabled and true or false) then EVAL_HELP_UI_TOGGLE() end
    end, G))
  table.insert(refreshes, cfgCheck(root, LX, -180, L("G_UI_STATE"),
    function() local u = c(); return u.st and u.st.enabled end,
    function(v)
      local u = c()
      if not u.st then u.st = { enabled = false, x = 330, y = -180 } end
      if v ~= (u.st.enabled and true or false) then EVAL_HELP_ST_TOGGLE() end
    end, G))

  cfgHeader(root, RX, -56, L("G_HELP_H"), G)
  -- 分组排版（1.21.5）：金色小标题 + 缩进条目 + 组间留白；命令行用亮米色区分
  -- 1.32.7 重整：清掉战士残留（猛击 Alt），补五分类/Shift切方案/重扫按钮/导入导出
  local helpLines = { -- 1.34.0 i18n：全部走语言包键
    { L("HELP_QS_H"), h = true },
    { L("HELP_QS_1") },
    { L("HELP_QS_2") },
    { L("HELP_QS_3") },
    { L("HELP_PROF_H"), h = true },
    { L("HELP_PROF_1"), cmd = true },
    { L("HELP_PROF_2"), cmd = true },
    { L("HELP_PROF_3"), cmd = true },
    { L("HELP_PROF_4"), cmd = true },
    { L("HELP_ADV_H"), h = true },
    { L("HELP_ADV_1") },
    { L("HELP_ADV_2") },
    { L("HELP_ADV_3") },
    { L("HELP_MISC_H"), h = true },
    { L("HELP_MISC_1") },
    { L("HELP_MISC_2") },
  }
  local hy = -74
  for _, e in ipairs(helpLines) do
    local ht
    if e.h then
      ht = uiText(root, 10, 0.95, 0.82, 0.35)         -- 组标题：金色，上方留白
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX, hy - 4)
      hy = hy - 21
    elseif e.cmd then
      ht = uiText(root, 9, 0.88, 0.82, 0.58)         -- 命令示例：亮米色
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX + 12, hy)
      hy = hy - 14
    else
      ht = uiText(root, 9, 0.65, 0.65, 0.65)         -- 普通条目：灰色
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX + 12, hy)
      hy = hy - 14
    end
    ht:SetText(e[1])
    table.insert(G, ht)
  end

  -- ===== Tab 2「一键宏设置」：多方案 + 技能规则列表（可视化编辑器，全职业通用） =====
  local Wp = pages[2].widgets
  local warUI = { rows = {}, profBtns = {}, picker = {}, editing = nil, pickSkill = nil }
  cfgWin.warUI = warUI
  local MAXPROF = 4

  -- 左栏：方案列表（多方案 Tab；最后一个 [+] 新建方案）
  cfgHeader(root, LX, -56, L("W_PROF_H"), Wp)
  for i = 1, MAXPROF + 1 do
    local pb = CreateFrame("Button", nil, root)
    pb:SetWidth(90) pb:SetHeight(17)
    pb:SetPoint("TOPLEFT", root, "TOPLEFT", LX, -74 - (i - 1) * 21)
    pcall(pb.EnableMouse, pb, true)
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp")
    local pbg = pb:CreateTexture(nil, "BACKGROUND")
    uiSolid(pbg, 0.16, 0.13, 0.08, 1)
    pbg:SetPoint("TOPLEFT", pb, "TOPLEFT", 0, 0)
    pbg:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", 0, 0)
    local pt = uiText(pb, 10, 0.92, 0.88, 0.80)
    pt:SetPoint("CENTER", pb, "CENTER", 0, 0)
    local pidx = i
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp", "RightButtonUp")
    pb:SetScript("OnClick", function(a, b)
      local w2 = warCfg()
      local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
      -- 右键 = 重命名弹窗（1.17.0：替代底部输入框流程，EditBox 不渲染也有回声行）
      if mbtn == "RightButton" and pidx <= table.getn(w2.profiles) then
        EVAL_HELP_RP_OPEN(pidx)
        return
      end
      if pidx <= table.getn(w2.profiles) then
        w2.activeProfile = pidx
      elseif pidx == table.getn(w2.profiles) + 1 and table.getn(w2.profiles) < MAXPROF then
        table.insert(w2.profiles, { name = "方案" .. tostring(table.getn(w2.profiles) + 1), skills = {} })
        w2.activeProfile = table.getn(w2.profiles)
        say("新建方案: " .. tostring(w2.profiles[w2.activeProfile].name))
      end
      EVAL_WAR_TAB_REFRESH()
    end)
    -- [删] 按钮（二次确认：5 秒内再点一次才删，防误删）
    local delB = CreateFrame("Button", nil, root)
    delB:SetWidth(15) delB:SetHeight(17)
    delB:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 92, -74 - (i - 1) * 21)
    pcall(delB.EnableMouse, delB, true)
    pcall(delB.RegisterForClicks, delB, "LeftButtonUp")
    local delBg = delB:CreateTexture(nil, "BACKGROUND")
    uiSolid(delBg, 0.25, 0.10, 0.10, 1)
    delBg:SetPoint("TOPLEFT", delB, "TOPLEFT", 0, 0)
    delBg:SetPoint("BOTTOMRIGHT", delB, "BOTTOMRIGHT", 0, 0)
    local delT = uiText(delB, 8, 0.95, 0.6, 0.5)
    delT:SetPoint("CENTER", delB, "CENTER", 0, 0)
    delT:SetText("删")
    delB:SetScript("OnClick", function()
      local w2 = warCfg()
      if pidx > table.getn(w2.profiles) then return end
      if warUI.delArm == pidx and GetTime() - (warUI.delArmT or 0) < 5 then
        warUI.delArm = nil
        EVAL_WAR_DEL_PROFILE(pidx)
      else
        warUI.delArm = pidx
        warUI.delArmT = GetTime()
        say("再点一次 [删] 确认删除方案: " .. tostring(w2.profiles[pidx].name))
        EVAL_WAR_TAB_REFRESH()
      end
    end)
    warUI.profBtns[i] = { btn = pb, bg = pbg, text = pt, del = delB, delBg = delBg }
    table.insert(Wp, pb)
    table.insert(Wp, delB)
  end

  -- 左栏下方：全局开关
  local swY = -74 - (MAXPROF + 1) * 21 - 18
  cfgHeader(root, LX, swY, L("W_SWITCH_H"), Wp)
  table.insert(refreshes, cfgCheck(root, LX, swY - 18, L("W_ENABLE"),
    function() return warCfg().enabled ~= false end,
    function(v) warCfg().enabled = v end, Wp))
  table.insert(refreshes, cfgCheck(root, LX, swY - 42, L("W_AUTOATK"),
    function() return warCfg().attack ~= false end,
    function(v) warCfg().attack = v end, Wp))
  table.insert(refreshes, cfgCheck(root, LX, swY - 66, L("W_DEBUG"),
    function() return c().wdebug end, function(v) c().wdebug = v end, Wp))

  -- 右侧：技能规则列表（顺序=优先级；勾选=技能配置开关）
  local RX2 = 128
  cfgHeader(root, RX2, -56, L("W_LIST_H"), Wp)
  local ROWS = 8
  local function mkSmall(x, y, w, label, fn, list, rightAnch) -- 1.32.2 list：传 G 挂全局页；1.34.1 rightAnch：右缘锚定（i18n 宽窗自适应）
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(15)
    if rightAnch then b:SetPoint("TOPRIGHT", root, "TOPRIGHT", -x, y)
    else b:SetPoint("TOPLEFT", root, "TOPLEFT", x, y) end
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.16, 0.13, 0.08, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 9, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    table.insert(list or Wp, b)
    if list then table.insert(list, bt) end -- 文本属按钮子件随动，但 G 列表契约要求显式登记
    return b, bt
  end
  -- 方案导入/导出窗口入口（md 文本互转）
  -- [添加技能]：直接打开技能编辑窗新增（技能下拉 + 条件逐行配置 + 保存即入列表）
  mkSmall(WIDE and 122 or 92, -56, WIDE and 112 or 80, L("W_ADD"), function()
    EVAL_HELP_SE_OPEN(warCfg().activeProfile or 1)
  end, nil, true)
  mkSmall(16, -56, WIDE and 98 or 68, L("W_IO"), function() EVAL_HELP_IO_TOGGLE() end, nil, true)

  -- 全局 Tab「一键宏」组（1.32.2）：重扫动作条按钮，等同 /eh go rescan——拖动过技能后点一下即可
  cfgHeader(root, LX, -212, L("G_MACRO_H"), G)
  local rsB, rsT = mkSmall(LX, -232, 130, L("G_RESCAN"), function() EVAL_GO_RESCAN() end, G)
  local rsTip = uiText(root, 8, 0.6, 0.6, 0.6)
  rsTip:SetPoint("TOPLEFT", root, "TOPLEFT", LX, -252)
  rsTip:SetText(L("G_RESCAN_TIP"))
  table.insert(G, rsTip)

  -- （1.21.6 起移除底部「激活方案」下拉：与左侧方案栏/战斗信息UI方案行/Shift+按宏//eh go prof N 功能重复）

  for ri = 1, ROWS do
    local y = -74 - (ri - 1) * 24
    local row = {}
    local chk = CreateFrame("Button", nil, root)
    chk:SetWidth(14) chk:SetHeight(14)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", RX2, y)
    pcall(chk.EnableMouse, chk, true)
    pcall(chk.RegisterForClicks, chk, "LeftButtonUp")
    local cOut = chk:CreateTexture(nil, "BACKGROUND")
    uiSolid(cOut, 0.85, 0.70, 0.20, 1)
    cOut:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0)
    cOut:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    local cIn = chk:CreateTexture(nil, "ARTWORK")
    uiSolid(cIn, 0.10, 0.09, 0.06, 1)
    cIn:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1)
    cIn:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
    local cMark = chk:CreateTexture(nil, "OVERLAY")
    uiSolid(cMark, 0.95, 0.80, 0.25, 1)
    cMark:SetPoint("TOPLEFT", chk, "TOPLEFT", 3, -3)
    cMark:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -3, 3)
    chk:SetScript("OnClick", function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local r = p and p.skills[ri + (warUI.offset or 0)]
      if r then
        r.enabled = (r.enabled == false) and true or false
        EVAL_WAR_TAB_REFRESH()
      end
    end)
    row.chk, row.mark = chk, cMark
    table.insert(Wp, chk)
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 18, y)
    icon:SetWidth(15) icon:SetHeight(15)
    row.icon = icon
    table.insert(Wp, icon)
    local nm = uiText(root, 10, 0.92, 0.88, 0.80)
    nm:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 38, y - 2)
    row.name = nm
    table.insert(Wp, nm)
    local cds = uiText(root, 9, 0.70, 0.70, 0.70)
    cds:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 102, y - 3)
    pcall(cds.SetWidth, cds, WIDE and 356 or 236) -- 1.33.0 让位滚动条；1.34.1 宽语言再加宽
    pcall(cds.SetJustifyH, cds, "LEFT")
    row.conds = cds
    table.insert(Wp, cds)
    row.up = mkSmall(72, y, 16, "上", function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and idx > 1 and p.skills[idx] and p.skills[idx - 1] then
        p.skills[idx], p.skills[idx - 1] = p.skills[idx - 1], p.skills[idx]
        EVAL_WAR_TAB_REFRESH()
      end
    end, nil, true)
    row.edit = mkSmall(44, y, 24, L("W_EDIT"), function()
      -- 打开技能编辑窗（独立条件属性行 + & / | 关系调整）
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and p.skills[idx] then
        EVAL_HELP_SE_OPEN(w2.activeProfile or 1, idx)
      end
    end, nil, true)
    row.del = mkSmall(16, y, 24, L("W_DEL"), function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and p.skills[idx] then
        table.remove(p.skills, idx)
        EVAL_WAR_TAB_REFRESH()
      end
    end, nil, true)
    warUI.rows[ri] = row
  end

  -- 滚动条（1.33.0：技能数取消上限后的超高滚动）：^ 上翻 / v 下翻 + 滚轮；仅超出可见行数时显示
  warUI.offset = warUI.offset or 0
  warUI.scrollUp = mkSmall(94, -74, 14, "^", function()
    warUI.offset = math.max(0, (warUI.offset or 0) - 1)
    EVAL_WAR_TAB_REFRESH()
  end, nil, true)
  warUI.scrollDn = mkSmall(94, -242, 14, "v", function()
    warUI.offset = (warUI.offset or 0) + 1
    EVAL_WAR_TAB_REFRESH() -- 上限在刷新里收敛
  end, nil, true)
  local okWheel = pcall(root.EnableMouseWheel, root, true)
  if okWheel then
    root:SetScript("OnMouseWheel", function()
      local d = arg1 -- 1.12 风格：滚轮方向在全局 arg1（上=+1）
      if type(d) ~= "number" then return end
      warUI.offset = math.max(0, (warUI.offset or 0) - d)
      EVAL_WAR_TAB_REFRESH()
    end)
  end

  -- 底部关闭按钮（截图同款右下「关闭」）
  local close = CreateFrame("Button", nil, root)
  close:SetWidth(64) close:SetHeight(22)
  close:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -12, 10)
  pcall(close.EnableMouse, close, true)
  pcall(close.RegisterForClicks, close, "LeftButtonUp")
  local cbg = close:CreateTexture(nil, "BACKGROUND")
  uiSolid(cbg, 0.16, 0.13, 0.08, 1)
  cbg:SetPoint("TOPLEFT", close, "TOPLEFT", 0, 0)
  cbg:SetPoint("BOTTOMRIGHT", close, "BOTTOMRIGHT", 0, 0)
  local ct = uiText(close, 11, 0.95, 0.82, 0.35)
  ct:SetPoint("CENTER", close, "CENTER", 0, 0)
  ct:SetText(L("CLOSE"))
  close:SetScript("OnClick", function() root:Hide() end)

  cfgWin.root = root
  root:SetScript("OnHide", function() EVAL_DD_HIDE() end) -- 关窗收起下拉（1.19.0）
  cfgWin.refresh = function() for _, r in ipairs(refreshes) do pcall(r) end end
  EVAL_HELP_CFG_SETTAB(c().cfgTab or 1)
  return root
end

-- ===== 方案重命名弹窗（1.17.0：替代底部输入框改名流程） =====
-- EditBox 在本客户端可能不渲染 → 加回声行（OnTextChanged 实时镜像输入内容，盲打也可见）
local rpUI = {}

function EVAL_HELP_RP_BUILD()
  if rpUI.root then return end
  local W, H = 300, 150
  local root = CreateFrame("Frame", "EVAL_HELP_RP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 120)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 4) titleBar:SetHeight(22)
  titleBar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 121)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("RP_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local lab = uiText(root, 10, 0.85, 0.85, 0.85)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  lab:SetText("新方案名：")

  -- 输入框（单行）
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_RP_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(220) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -54)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 11) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(24)
    local ebEdge = root:CreateTexture(nil, "BORDER")
    uiSolid(ebEdge, 0.85, 0.70, 0.20, 0.8)
    ebEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebEdge:SetWidth(W - 28) ebEdge:SetHeight(1)
    rpUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -54)
    noEb:SetText(L("RP_NOEB"))
  end

  -- 回声行：实时镜像输入内容（EditBox 不渲染时的保底可见性）
  local echo = uiText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -80)
  pcall(echo.SetWidth, echo, W - 40)
  pcall(echo.SetJustifyH, echo, "LEFT")
  rpUI.echo = echo
  if rpUI.eb then
    rpUI.eb:SetScript("OnTextChanged", function()
      local ok, t = pcall(rpUI.eb.GetText, rpUI.eb)
      if ok and type(t) == "string" then echo:SetText(t) end
    end)
  end

  local function apply()
    local nm = ""
    if rpUI.eb then
      local ok, t = pcall(rpUI.eb.GetText, rpUI.eb)
      if ok and type(t) == "string" then nm = t end
    end
    nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
    local w2 = warCfg()
    local p = rpUI.target and w2.profiles[rpUI.target]
    if p and nm ~= "" then
      p.name = nm
      say("方案已改名: " .. nm)
    end
    rpUI.target = nil
    root:Hide()
    EVAL_WAR_TAB_REFRESH()
  end
  if rpUI.eb then
    rpUI.eb:SetScript("OnEnterPressed", function() apply() end)
    rpUI.eb:SetScript("OnEscapePressed", function() root:Hide() end)
  end

  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(80) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(70, L("BTN_OK"), function() apply() end)
  bBtn(160, L("BTN_CANCEL"), function() root:Hide() end)

  root:Hide()
  rpUI.root = root
end

function EVAL_HELP_RP_OPEN(idx)
  EVAL_HELP_RP_BUILD()
  local w2 = warCfg()
  if not w2.profiles[idx] then return end
  rpUI.target = idx
  local nm = tostring(w2.profiles[idx].name or "")
  if rpUI.eb then
    pcall(rpUI.eb.SetText, rpUI.eb, nm)
    pcall(rpUI.eb.SetFocus, rpUI.eb)
  end
  if rpUI.echo then rpUI.echo:SetText(nm) end
  rpUI.root:Show()
end


-- ===== 通用名称输入弹窗（1.29.0：仿 1.17.0 重命名弹窗回声行范式——EditBox 可能不渲染 → 金色回声行保底） =====
-- EVAL_TN_OPEN(标题, 当前值, onOk(名称))；确定/回车回调，取消/Esc 直接关。
local tnUI = {}

function EVAL_TN_BUILD()
  if tnUI.root then return end
  local W, H = 300, 150
  local root = CreateFrame("Frame", "EVAL_HELP_TN", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 130) -- 高于技能编辑窗(100)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 4) titleBar:SetHeight(22)
  titleBar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 131)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  tnUI.titleText = title
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local lab = uiText(root, 10, 0.85, 0.85, 0.85)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  lab:SetText("目标名称：")

  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_TN_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(220) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -54)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 11) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(24)
    tnUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -54)
    noEb:SetText(L("TN_NOEB"))
  end

  -- 回声行：实时镜像输入内容（盲打保底可见）
  local echo = uiText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -80)
  pcall(echo.SetWidth, echo, W - 40)
  pcall(echo.SetJustifyH, echo, "LEFT")
  tnUI.echo = echo
  if tnUI.eb then
    tnUI.eb:SetScript("OnTextChanged", function()
      local ok, t = pcall(tnUI.eb.GetText, tnUI.eb)
      if ok and type(t) == "string" then echo:SetText(t) end
    end)
  end

  local function apply()
    local nm = ""
    if tnUI.eb then
      local ok, t = pcall(tnUI.eb.GetText, tnUI.eb)
      if ok and type(t) == "string" then nm = t end
    end
    nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
    if nm ~= "" and tnUI.onOk then tnUI.onOk(nm) end
    root:Hide()
  end
  if tnUI.eb then
    tnUI.eb:SetScript("OnEnterPressed", function() apply() end)
    tnUI.eb:SetScript("OnEscapePressed", function() root:Hide() end)
  end

  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(80) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(70, L("BTN_OK"), function() apply() end)
  bBtn(160, L("BTN_CANCEL"), function() root:Hide() end)

  root:Hide()
  root:SetScript("OnHide", function() tnUI.onOk = nil end)
  tnUI.root = root
end

function EVAL_TN_OPEN(title, cur, onOk)
  EVAL_TN_BUILD()
  tnUI.onOk = onOk
  if tnUI.titleText then tnUI.titleText:SetText(title or "输入名称") end
  if tnUI.eb then
    pcall(tnUI.eb.SetText, tnUI.eb, cur or "")
    pcall(tnUI.eb.SetFocus, tnUI.eb)
  end
  if tnUI.echo then tnUI.echo:SetText(cur or "") end
  tnUI.root:Show()
end

-- 删除方案（至少保留一个；activeProfile 随删除左移/收敛）
function EVAL_WAR_DEL_PROFILE(idx)
  local w2 = warCfg()
  if table.getn(w2.profiles) <= 1 then say("至少保留一个方案") return false end
  if not w2.profiles[idx] then return false end
  say("已删除方案: " .. tostring(w2.profiles[idx].name))
  table.remove(w2.profiles, idx)
  if (w2.activeProfile or 1) > table.getn(w2.profiles) then
    w2.activeProfile = table.getn(w2.profiles)
  elseif (w2.activeProfile or 1) > idx then
    w2.activeProfile = (w2.activeProfile or 1) - 1
  end
  pcall(EVAL_WAR_TAB_REFRESH)
  return true
end

-- 一键宏 Tab 列表刷新（方案按钮选中态 / 技能行内容 / 图标选择器高亮）
function EVAL_WAR_TAB_REFRESH()
  if not wscanned then EVAL_GO_RESCAN(true) end -- 1.32.9 自愈：初始化重扫若早于动作条就绪，这里补扫（否则技能行图标全灰）
  local warUI = cfgWin.warUI
  if not warUI then return end
  local w2 = warCfg()
  for i, pb in ipairs(warUI.profBtns) do
    local prof = w2.profiles[i]
    if prof then
      pb.text:SetText(tostring(prof.name or ("方案" .. i)))
      local sel = (w2.activeProfile or 1) == i
      pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
      pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.75, sel and 0.9 or 0.72, sel and 0.4 or 0.6)
    elseif i == table.getn(w2.profiles) + 1 then
      pb.text:SetText("+")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.10, 0.10, 0.10, 1)
    else
      pb.text:SetText("")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.06, 0.05, 0.04, 1)
    end
    -- [删] 仅存在的方案显示；待确认状态红色高亮
    if pb.del then
      if prof then
        pb.del:Show()
        local armed = (warUI.delArm == i) and (GetTime() - (warUI.delArmT or 0) < 5)
        pcall(pb.delBg.SetVertexColor, pb.delBg, armed and 0.75 or 0.25, 0.10, 0.10, 1)
      else
        pb.del:Hide()
      end
    end
  end
  local p = w2.profiles[w2.activeProfile or 1]
  -- 1.33.0 滚动：offset 收敛到合法范围；滚动按钮仅在超高时显示
  local cnt = (p and p.skills) and table.getn(p.skills) or 0
  local rowsN = table.getn(warUI.rows) -- 1.33.3 修：ROWS 是 cfgBuild 内 local，本函数拿不到（nil 算术报错）
  local maxOff = math.max(0, cnt - rowsN)
  warUI.offset = math.max(0, math.min(warUI.offset or 0, maxOff))
  if warUI.scrollUp then
    if cnt > rowsN then
      pcall(warUI.scrollUp.Show, warUI.scrollUp) pcall(warUI.scrollDn.Show, warUI.scrollDn)
    else
      pcall(warUI.scrollUp.Hide, warUI.scrollUp) pcall(warUI.scrollDn.Hide, warUI.scrollDn)
    end
  end
  for ri, row in ipairs(warUI.rows) do
    local r = p and p.skills[ri + warUI.offset]
    local widgets = { row.chk, row.icon, row.name, row.conds, row.up, row.edit, row.del }
    for _, wgt in ipairs(widgets) do
      if r then pcall(wgt.Show, wgt) else pcall(wgt.Hide, wgt) end
    end
    if r then
      if r.enabled ~= false then row.mark:Show() else row.mark:Hide() end
      local t0 = wicon(r.skill)
      if t0 then
        pcall(row.icon.SetTexture, row.icon, t0)
        pcall(row.icon.SetVertexColor, row.icon, 1, 1, 1)
      else
        uiSolid(row.icon, 0.25, 0.25, 0.25, 1)
      end
      row.name:SetText(tostring(r.skill))
      row.conds:SetText(EVAL_GROUP_STR(r.groups))
    end
  end
end

-- Tab 切换：按控件列表显式 Show/Hide（本客户端可见性契约：走控件列表，不靠父框架传播）
function EVAL_HELP_CFG_SETTAB(idx)
  if not cfgWin.pages then return end
  cfgWin.tab = idx
  c().cfgTab = idx
  for i, p in ipairs(cfgWin.pages) do
    local on = (i == idx)
    for _, wgt in ipairs(p.widgets) do
      if on then pcall(wgt.Show, wgt) else pcall(wgt.Hide, wgt) end
    end
    if on then
      pcall(p.bg.SetVertexColor, p.bg, 0.45, 0.35, 0.10, 1)
      pcall(p.text.SetTextColor, p.text, 1, 0.90, 0.40)
    else
      pcall(p.bg.SetVertexColor, p.bg, 0.16, 0.13, 0.08, 1)
      pcall(p.text.SetTextColor, p.text, 0.70, 0.65, 0.55)
    end
  end
  if idx == 2 then pcall(EVAL_WAR_TAB_REFRESH) end
end

function EVAL_HELP_CFG_TOGGLE()
  local win = cfgBuild()
  if win:IsVisible() then
    win:Hide()
  else
    -- 每次弹窗计算位置：飞出屏幕（拖太远/改过分辨率）→ 回归视野中心
    if uiOffscreen(win) then
      win:ClearAllPoints()
      win:SetPoint("CENTER", UIParent, "CENTER", -320, 60)
      c().cfgPos = nil
    end
    if cfgWin.refresh then cfgWin.refresh() end
    EVAL_HELP_CFG_SETTAB(cfgWin.tab or c().cfgTab or 1)
    win:Show()
  end
end

-- 小地图图标：挂在小地图左侧的金色 EH 按钮。
-- UnrealQuest 实测要点：parent 用 UIParent（不是 Minimap——它是地图外的 chrome）；
-- 锚链 Minimap → MinimapCluster → UIParent 右上角；RegisterForClicks 注册点击；
-- 悬停用 OnEnter/OnLeave 改边框色 + GameTooltip 提示（不用 SetHighlightTexture）。
-- 按钮本身支持拖拽换位（Button 手柄配方），位置存 cfg.mbPos，重登恢复；
-- 拖动松手会跟着触发一次 OnClick，用 mbDragMoved 标记抑制这次误触。
local minimapBtn = nil
local mbDragMoved = false
do
  local mb = CreateFrame("Button", "EVAL_HELP_MINIMAP", UIParent)
  mb:SetWidth(24) mb:SetHeight(24)
  pcall(mb.SetFrameStrata, mb, "MEDIUM")
  pcall(mb.EnableMouse, mb, true)
  pcall(mb.RegisterForClicks, mb, "LeftButtonUp")
  pcall(mb.RegisterForDrag, mb, "LeftButton")
  local anchored = false
  if type(Minimap) == "table" or type(Minimap) == "userdata" then
    anchored = pcall(mb.SetPoint, mb, "TOPRIGHT", Minimap, "TOPLEFT", -6, 0)
  end
  if not anchored and (type(MinimapCluster) == "table" or type(MinimapCluster) == "userdata") then
    anchored = pcall(mb.SetPoint, mb, "TOPRIGHT", MinimapCluster, "TOPLEFT", -6, -6)
  end
  if not anchored then
    pcall(mb.SetPoint, mb, "TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
  end
  local ring = mb:CreateTexture(nil, "BACKGROUND")
  uiSolid(ring, 0.85, 0.70, 0.20, 1)
  ring:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)
  ring:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", 0, 0)
  local inner = mb:CreateTexture(nil, "ARTWORK")
  uiSolid(inner, 0.12, 0.10, 0.06, 1)
  inner:SetPoint("TOPLEFT", mb, "TOPLEFT", 2, -2)
  inner:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", -2, 2)
  local mt = uiText(mb, 11, 1, 0.85, 0.30)
  mt:SetPoint("CENTER", mb, "CENTER", 0, 0)
  mt:SetText("EH")
  mb:SetScript("OnDragStart", function()
    mbDragMoved = false
    pcall(mb.SetMovable, mb, true)
    pcall(mb.StartMoving, mb)              -- warm-up 两步（实测配方）
    pcall(mb.StopMovingOrSizing, mb)
    pcall(mb.StartMoving, mb)
  end)
  mb:SetScript("OnDragStop", function()
    pcall(mb.StopMovingOrSizing, mb)
    mbDragMoved = true
    local ok, point, _, relPoint, x, y = pcall(mb.GetPoint, mb, 1)
    if ok and type(point) == "string" then
      c().mbPos = {
        point = point,
        relPoint = (type(relPoint) == "string") and relPoint or point,
        x = (type(x) == "number") and x or 0,
        y = (type(y) == "number") and y or 0,
      }
    end
  end)
  mb:SetScript("OnEnter", function()
    pcall(ring.SetVertexColor, ring, 1, 0.88, 0.40, 1)
    if GameTooltip and GameTooltip.SetOwner then
      pcall(GameTooltip.SetOwner, GameTooltip, mb, "ANCHOR_LEFT")
      if GameTooltip.AddLine then
        pcall(GameTooltip.AddLine, GameTooltip, "全职业施法工具 · 设置")
        pcall(GameTooltip.AddLine, GameTooltip, "点击打开配置窗口，按住可拖动", 0.7, 0.7, 0.7)
      end
      pcall(GameTooltip.Show, GameTooltip)
    end
  end)
  mb:SetScript("OnLeave", function()
    pcall(ring.SetVertexColor, ring, 0.85, 0.70, 0.20, 1)
    if GameTooltip and GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  mb:SetScript("OnClick", function()
    if mbDragMoved then mbDragMoved = false return end -- 拖动松手后的那次抬起不算点击
    EVAL_HELP_CFG_TOGGLE()
  end)
  minimapBtn = mb
end

-- ============ 状态信息 UI（展示 Cat 式角色状态表 EVAL_HELP_STATE 的实时值） ============
-- /eh st 开关；标题栏拖动（位置记忆+越界回归）；每 0.15s 刷新一次 EVAL_HELP_UPDATE_STATE()。
-- 内容 = 状态模块全部字段：玩家数值/战斗计时/姿态/修饰键/普攻 + 目标可攻击/可流血/精英Boss 等。

local stui = { root = nil, body = nil }
local stLastTick = 0
local ST_TICK = 0.15

local function stCfg()
  local cc = c()
  if not cc.st then cc.st = { enabled = false, x = 330, y = -180 } end
  return cc.st
end

local function stYesNo(v)
  return v and "|cff00ff00是|r" or "|cffff5040否|r"
end

function EVAL_HELP_ST_BUILD()
  local sc = stCfg()
  if stui.root then
    stui.root:Hide()
    pcall(stui.root.SetScript, stui.root, "OnUpdate", nil)
  end
  local W = 250
  local pad = 8
  local titleBarH = 16
  local root = CreateFrame("Frame", "EVAL_HELP_STUI", UIParent)
  pcall(root.SetFrameStrata, root, "MEDIUM")
  pcall(root.SetMovable, root, true)
  -- 本体不吃鼠标（UnrealQuest：容器 mouse-disabled，不吞世界点击）；拖动走标题栏 Button
  pcall(root.EnableMouse, root, false)

  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.92)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end

  -- 标题栏拖动柄（Button 配方）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(titleBarH)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10)
  end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText("状态信息")
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, cx, cy = pcall(root.GetCenter, root)
    if ok and cx then
      local okw, w2 = pcall(UIParent.GetWidth, UIParent)
      local okh, h2 = pcall(UIParent.GetHeight, UIParent)
      if okw and okh and w2 and h2 then
        local oke, es = pcall(root.GetEffectiveScale, root)
        local k = (oke and type(es) == "number" and es > 0) and es or 1
        sc.x = (cx - w2 / 2) / k
        sc.y = (cy - h2 / 2) / k
      end
    end
  end)

  -- 正文：一个多行 FontString，逐行展示状态变量
  local body = uiText(root, 10, 0.85, 0.85, 0.85)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -(titleBarH + pad))
  pcall(body.SetWidth, body, W - pad * 2)
  pcall(body.SetJustifyH, body, "LEFT")

  root:SetWidth(W)
  root:SetHeight(titleBarH + pad * 2 + 15 * 14)
  root:ClearAllPoints()
  root:SetPoint("CENTER", UIParent, "CENTER", sc.x or 330, sc.y or -180)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 330, -180)
    sc.x, sc.y = 330, -180
  end

  stui.root, stui.body = root, body
  root:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - stLastTick < ST_TICK then return end
    stLastTick = now
    EVAL_HELP_ST_TICK()
  end)
end

-- 每次心跳：刷新状态表，逐行重排正文（Cat 的 CatUI-Melee 状态行同款展示）
function EVAL_HELP_ST_TICK()
  if not stui.root or not stui.root:IsVisible() then return end
  EVAL_HELP_UPDATE_STATE()
  local lines = {}
  table.insert(lines, string.format("%s  Lv%d %s%s",
    st.playerName or "?", st.level or 0, st.classLoc or "",
    st.raceLoc and (" · " .. st.raceLoc) or ""))
  table.insert(lines, string.format("血 %d/%d (%.0f%%)", st.hp, st.hpMax, st.hpPct))
  table.insert(lines, string.format("%s %d/%d (%.0f%%)%s", powerLabel(), st.power, st.powerMax, st.powerPct,
    (st.class == "ROGUE" or st.class == "DRUID") and string.format(" · 连击 %d", st.combo or 0) or ""))
  table.insert(lines, string.format("%s%s · %s",
    st.inCombat and "|cffff5040战斗中|r" or "|cff80ff80非战斗|r",
    st.inCombat and string.format(" %.1fs", st.combatTime) or "",
    st.form or "无姿态"))
  table.insert(lines, string.format("Alt:%s Shift:%s Ctrl:%s 普攻:%s",
    stYesNo(st.alt), stYesNo(st.shift), stYesNo(st.ctrl), stYesNo(st.autoAttack)))
  if st.hasTarget then
    table.insert(lines, string.format("目标: %s  Lv%d%s%s",
      tostring(st.targetName), st.tLevel or 0,
      st.isBoss and " |cffff4040Boss|r" or "",
      (not st.isBoss and st.isElite) and " |cffff9040精英|r" or ""))
    table.insert(lines, string.format("目标血 %.0f%% · 可攻击:%s · 可流血:%s · 关系:%s",
      st.tHpPct, stYesNo(st.canAttack), stYesNo(st.canBleed),
      st.tFriendly and "友善" or (st.tNeutral and "中立" or (st.tHostile and "敌对" or "?"))))
    table.insert(lines, string.format("类型:%s 分级:%s%s · 职业:%s",
      st.tCreatureType or "?", st.tClassification or "?",
      st.tInCombat and " · 目标战斗中" or "",
      tostring(st.tClassName or st.tClass or "?")))
  else
    table.insert(lines, "目标: |cff808080无|r")
  end
  -- 最近释放：技能 + 触发原因 + 条件逐项判定明细（规则引擎 trace）
  if st.castLog and table.getn(st.castLog) > 0 then
    table.insert(lines, "|cffc8a04a— 最近释放 —|r")
    local now = GetTime()
    for i = 1, 3 do
      local e = st.castLog[i]
      if not e then break end
      local ago = now - (e.t or now)
      table.insert(lines, string.format("|cff909090%.0fs前|r |cffffd050%s|r%s%s",
        ago, tostring(e.skill),
        (e.target and e.target ~= "") and ("→" .. e.target) or "",
        (e.why and e.why ~= "") and (" |cff909090← " .. tostring(e.why) .. "|r") or ""))
      if e.trace and e.trace ~= "" then
        table.insert(lines, "  |cff70b070" .. e.trace .. "|r")
      end
    end
  end
  stui.body:SetText(table.concat(lines, "\n"))
end

function EVAL_HELP_ST_TOGGLE()
  local sc = stCfg()
  if stui.root and stui.root:IsVisible() then
    stui.root:Hide()
    sc.enabled = false
    say("状态信息UI: |cffff0000关|r")
  else
    EVAL_HELP_ST_BUILD()
    if stui.root then stui.root:Show() end
    sc.enabled = true
    say("状态信息UI: |cff00ff00开|r（Cat 状态变量实时总览）")
  end
end

-- ============ 技能编辑窗（技能循环选择 + 独立条件属性行 + & / | 连接符） ============
-- 编辑模型：ed.conds = 线性条件列表 { {conn=nil|"&"|"|", cd=条件}, ... }；
-- conn 语义：& 并入当前组、| 新开一组 → 与引擎 groups（组内 & 、组间 | ）一一对应。
-- 本客户端无下拉控件：技能/条件类型/比较符/技能名全部用「点击循环」按钮实现。

local SE_TYPES = {
  { id = "power",      name = "怒气/能量",   kind = "num",   n = 30 },
  { id = "tHpPct",     name = "目标血%",     kind = "num",   n = 10 },
  { id = "hpPct",      name = "自身血%",     kind = "num",   n = 50 },
  { id = "powerPct",   name = "能量%",       kind = "num",   n = 10 },
  { id = "combatTime", name = "进战秒数",    kind = "num",   n = 3 },
  { id = "combo",      name = "连击点数",    kind = "num",   n = 3 },
  { id = "combat",     name = "战斗状态",    kind = "bool" },
  { id = "hasTarget",  name = "目标存在",    kind = "bool" },
  { id = "canAttack",  name = "目标可攻击",  kind = "bool" },
  { id = "canBleed",   name = "目标可流血",  kind = "bool" },
  { id = "tFriendly",  name = "目标友善",    kind = "bool" },
  { id = "tHostile",   name = "目标敌对",    kind = "bool" },
  { id = "tNeutral",   name = "目标中立",    kind = "bool" },
  { id = "isElite",    name = "目标精英",    kind = "bool" },
  { id = "isBoss",     name = "目标Boss",    kind = "bool" },
  { id = "tInCombat",  name = "目标战斗中",  kind = "bool" },
  { id = "autoAttack", name = "普攻已开",    kind = "bool" },
  { id = "alt",        name = "Alt按住",     kind = "bool" },
  { id = "shift",      name = "Shift按住",   kind = "bool" },
  { id = "ctrl",       name = "Ctrl按住",    kind = "bool" },
  { id = "form",       name = "当前姿态",    kind = "form" },
  { id = "hasBuff",    name = "自身有buff",  kind = "skill", s = "战斗怒吼" },
  { id = "noBuff",     name = "自身无buff",  kind = "skill", s = "战斗怒吼" },
  { id = "hasDebuff",  name = "目标有debuff", kind = "skill", s = "断筋" },
  { id = "noDebuff",   name = "目标无debuff", kind = "skill", s = "断筋" },
  { id = "ready",      name = "冷却就绪",    kind = "flag" },
  { id = "usable",     name = "技能可用",    kind = "flag" },
  { id = "notQueued",  name = "未排队",      kind = "flag" },
  { id = "target",     name = "选取目标",    kind = "target", s = "nearEnemy", hidden = true }, -- 1.32.0 提为技能级（技能下拉「目标选取」），新增条件下拉不再提供；存量条件仍渲染/求值
  { id = "tClass",     name = "目标职业",    kind = "class" },
  { id = "immune",    name = "目标免疫技能", kind = "skill", s = "撕裂" }, -- 1.36.1 免疫学习表判定
}
local SE_BY_K = {}
for i, td in ipairs(SE_TYPES) do SE_BY_K[td.id] = i end
SE_BY_K["formNot"] = SE_BY_K["form"]
local SE_OPS = { ">", ">=", "<", "<=", "==", "~=" }

-- 条件类型分组（1.32.5 下拉美化）：金色组标题行不可选；SE_TYPES 本体顺序不动，仅展示层分组
local SE_TYPE_GROUPS = {
  { label = "CTG_1", ids = { "power", "hpPct", "powerPct", "combatTime", "combo", "combat", "autoAttack", "alt", "shift", "ctrl", "form" } },
  { label = "CTG_2", ids = { "tHpPct", "hasTarget", "canAttack", "canBleed", "tFriendly", "tHostile", "tNeutral", "isElite", "isBoss", "tInCombat", "tClass", "immune" } },
  { label = "CTG_3", ids = { "hasBuff", "noBuff", "hasDebuff", "noDebuff" } },
  { label = "CTG_4", ids = { "ready", "usable", "notQueued" } },
}

local seUI = { root = nil, ed = nil, rows = {} }

local function seDefaultCond(ti)
  local td = SE_TYPES[ti]
  if td.kind == "num" then return { k = td.id, op = ">", n = td.n }
  elseif td.kind == "bool" then return { k = td.id, v = true }
  elseif td.kind == "form" then return { k = "form", n = 1 }
  elseif td.kind == "skill" then return { k = td.id, s = td.s }
  elseif td.kind == "target" then return { k = td.id, s = td.s }
  elseif td.kind == "class" then return { k = td.id, cs = { WARRIOR = true } }
  else return { k = td.id } end
end

-- groups → 线性编辑列表（复制条件，避免保存前污染已存数据）
local function seGroupsToLinear(groups)
  local list = {}
  for gi, g in ipairs(groups or {}) do
    for ci, cd in ipairs(g) do
      local conn
      if gi > 1 and ci == 1 then conn = "|"
      elseif ci > 1 then conn = "&" end
      local cp = {}
      for k, v in pairs(cd) do
        if type(v) == "table" then -- cs 等表字段拷一层，避免编辑期污染已存数据
          local c2 = {}
          for k2, v2 in pairs(v) do c2[k2] = v2 end
          cp[k] = c2
        else
          cp[k] = v
        end
      end
      table.insert(list, { conn = conn, cd = cp })
    end
  end
  return list
end

-- 线性列表 → groups：| 新开组，& 并入当前组
local function seLinearToGroups(list)
  local groups, cur = {}, nil
  for _, it in ipairs(list or {}) do
    if it.conn == "|" or not cur then
      cur = {}
      table.insert(groups, cur)
    end
    if it.cd then table.insert(cur, it.cd) end
  end
  return groups
end

local function seBtn(parent, x, y, w, h, label, fn)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bb = b:CreateTexture(nil, "BACKGROUND")
  uiSolid(bb, 0.16, 0.13, 0.08, 1)
  bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local bt = uiText(b, 9, 0.92, 0.88, 0.80)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText(label)
  b:SetScript("OnClick", fn)
  return { btn = b, bg = bb, text = bt }
end

-- ===== 全局模拟下拉列表面板（1.19.0 由 SE 专用泛化：任意窗口可调用） =====
-- EVAL_DD_OPEN(锚点按钮, 选项表, 回调)；多列 12 行/列，贴屏底自动上翻；EVAL_DD_HIDE() 收起。
local DD_COLS = 12
local ddUI = {}

local function DD_BUILD()
  if ddUI.root then return end
  local dd = CreateFrame("Frame", "EVAL_HELP_DD", UIParent)
  pcall(dd.SetFrameStrata, dd, "DIALOG")
  pcall(dd.SetFrameLevel, dd, 250)
  pcall(dd.EnableMouse, dd, true)
  local bg = dd:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = dd:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", dd, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", dd, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = dd:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, dd, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, dd, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  ddUI.rows = {}
  for i = 1, 48 do -- 1.27.0 加倍：技能清单+实时debuff/buff 追加项可能超 24
    local rb = CreateFrame("Button", nil, dd)
    rb:SetWidth(104) rb:SetHeight(14)
    pcall(rb.EnableMouse, rb, true)
    pcall(rb.RegisterForClicks, rb, "LeftButtonUp")
    local rbg = rb:CreateTexture(nil, "BACKGROUND")
    uiSolid(rbg, 0.10, 0.09, 0.06, 1)
    rbg:SetPoint("TOPLEFT", rb, "TOPLEFT", 0, 0)
    rbg:SetPoint("BOTTOMRIGHT", rb, "BOTTOMRIGHT", 0, 0)
    local rt = uiText(rb, 9, 0.85, 0.85, 0.85)
    rt:SetPoint("LEFT", rb, "LEFT", 4, 0)
    local ri = rb:CreateTexture(nil, "ARTWORK") -- 1.32.4 可选图标列（opts.icons）
    ri:SetWidth(12) ri:SetHeight(12)
    ri:SetPoint("LEFT", rb, "LEFT", 2, 0)
    ri:Hide()
    rb:SetScript("OnEnter", function() pcall(rbg.SetVertexColor, rbg, 0.38, 0.30, 0.10, 1) end)
    rb:SetScript("OnLeave", function() pcall(rbg.SetVertexColor, rbg, 0.10, 0.09, 0.06, 1) end)
    ddUI.rows[i] = { btn = rb, bg = rbg, text = rt, icon = ri }
  end
  dd:Hide()
  ddUI.root = dd
end

function EVAL_DD_HIDE() if ddUI.root then ddUI.root:Hide() end ddUI.anchor = nil end

-- anchorBtn 下方展开 items 列表；onPick(序号) 回调
-- opts.multi=true 多选模式（1.26.0）：点按切换选中（√ 金标）不关面板，onPick(序号, 是否选中) 逐项回调；
-- opts.selected = { [序号]=true } 初始选中集（面板重开时重建传入）。收起走 EVAL_DD_HIDE()/宿主窗 OnHide。
function EVAL_DD_OPEN(anchorBtn, items, onPick, opts)
  DD_BUILD()
  local dd = ddUI.root
  if not dd then return end
  -- 1.32.5 重复点击同一触发按钮 = 收起下拉（toggle）
  local okS, shown = pcall(dd.IsShown, dd)
  if okS and shown and ddUI.anchor == anchorBtn then EVAL_DD_HIDE() return end
  ddUI.anchor = anchorBtn
  ddUI.multi = (opts and opts.multi) and true or false
  ddUI.sel = (ddUI.multi and (opts.selected or {})) or nil -- 1.32.0 审计修复：multi 未传 selected 时索引 nil 隐患
  local n = table.getn(items)
  local cols = math.ceil(n / DD_COLS)
  local icons = opts and opts.icons -- 1.32.4 可选图标列：与 items 同序的纹理表
  local colW = icons and 124 or 108
  for i, row in ipairs(ddUI.rows) do
    if i <= n then
      local pi = i
      local ic = icons and icons[i]
      if ic then
        pcall(row.icon.SetTexture, row.icon, ic)
        row.icon:Show()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 18, 0)
      else
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 4, 0)
      end
      if ddUI.multi then
        local function paint()
          local on = ddUI.sel and ddUI.sel[pi] and true or false
          row.text:SetText((on and "|cffffd100√|r " or "") .. tostring(items[pi]))
        end
        paint()
        row.btn:SetScript("OnClick", function()
          local nowOn = not (ddUI.sel[pi] and true or false)
          ddUI.sel[pi] = nowOn or nil
          paint()
          onPick(pi, nowOn)
        end)
      else
        row.text:SetText(tostring(items[i]))
        row.btn:SetScript("OnClick", function() dd:Hide() onPick(pi) end)
      end
      local col = math.floor((i - 1) / DD_COLS)
      local ri = math.mod(i - 1, DD_COLS)
      row.btn:ClearAllPoints()
      row.btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 4 + col * colW, -4 - ri * 15)
      row.btn:Show()
    else
      row.btn:Hide()
    end
  end
  local rows = math.min(n, DD_COLS)
  dd:SetWidth(8 + cols * colW)
  dd:SetHeight(8 + rows * 15)
  dd:ClearAllPoints()
  dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
  -- 贴屏底时改为向上展开
  local okb, ab = pcall(anchorBtn.GetBottom, anchorBtn)
  if okb and type(ab) == "number" then
    local oke, es = pcall(dd.GetEffectiveScale, dd)
    local k = (oke and type(es) == "number" and es > 0) and es or 1
    if ab < (8 + rows * 15) * k + 20 then
      dd:ClearAllPoints()
      dd:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 2)
    end
  end
  dd:Show()
end

function EVAL_HELP_SE_REFRESH()
  local ed = seUI.ed
  if not ed or not seUI.root then return end
  -- 技能选择器
  local t0 = wicon(ed.skill)
  if t0 then
    pcall(seUI.skillIcon.SetTexture, seUI.skillIcon, t0)
    pcall(seUI.skillIcon.SetVertexColor, seUI.skillIcon, 1, 1, 1)
  else
    uiSolid(seUI.skillIcon, 0.25, 0.25, 0.25, 1)
  end
  seUI.skillName:SetText(tostring(ed.skill))
  if seUI.catName then -- 分类按钮文字 = 当前技能所属类（1.32.3）
    local cl = { L("SK_CAT_1"), L("SK_CAT_2"), L("SK_CAT_3"), L("SK_CAT_4"), L("SK_CAT_5") }
    local ci = 2
    if ed.skill == "攻击" then ci = 1
    elseif petCmdOf(ed.skill) then ci = 3
    elseif targetSelOf(ed.skill) then ci = 4
    elseif itemOf(ed.skill) then ci = 5 end
    seUI.catName:SetText(cl[ci])
  end
  if ed.enabled then seUI.enMark:Show() else seUI.enMark:Hide() end
  -- 条件行
  for i, row in ipairs(seUI.rows) do
    local it = ed.conds[i]
    for _, wgt in ipairs(row.all) do pcall(wgt.Hide, wgt) end
    if it then
      local cd = it.cd
      row.conn.text:SetText(i == 1 and "当" or (it.conn or "&"))
      pcall(row.conn.btn.Show, row.conn.btn)
      local ti = SE_BY_K[cd.k] or 1
      local td = SE_TYPES[ti]
      row.typeBtn.text:SetText(L("CT_" .. string.upper(td.id)))
      pcall(row.typeBtn.btn.Show, row.typeBtn.btn)
      if td.kind == "num" then
        row.opBtn.text:SetText(cd.op or ">")
        row.valText:SetText(tostring(cd.n or 0))
        pcall(row.opBtn.btn.Show, row.opBtn.btn)
        pcall(row.minus.btn.Show, row.minus.btn)
        pcall(row.plus.btn.Show, row.plus.btn)
        pcall(row.valText.Show, row.valText)
      elseif td.kind == "bool" then
        row.valBtn.text:SetText(cd.v and "是" or "否")
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
      elseif td.kind == "flag" then
        row.valBtn.text:SetText(cd.inv and "否" or "是")
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
      elseif td.kind == "form" then
        row.valBtn.text:SetText(cd.k == "formNot" and "非" or "是")
        row.formN.text:SetText(tostring(cd.n or 1))
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
        pcall(row.formN.btn.Show, row.formN.btn)
      elseif td.kind == "skill" then
        local disp = tostring(cd.s or "?")
        local isDebuff = (cd.k == "hasDebuff" or cd.k == "noDebuff")
        if isDebuff then
          if type(cd.n) == "number" and cd.n > 1 then
            disp = disp .. (cd.k == "hasDebuff" and (" ≥" .. cd.n) or (" <" .. cd.n))
          end
          row.stk.text:SetText(type(cd.n) == "number" and cd.n > 1 and ("层" .. cd.n) or "层")
          pcall(row.stk.btn.Show, row.stk.btn)
        end
        row.skillText:SetText(disp)
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      elseif td.kind == "target" then
        local disp = (cd.s == "byName") and ("指定:" .. tostring(cd.nm or "未设")) or (TARGET_SEL_NAME[cd.s] or tostring(cd.s or "?"))
        row.skillText:SetText(disp)
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      elseif td.kind == "class" then
        local ns = {}
        for _, c in ipairs(CLASS_LIST) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.name) end end
        row.skillText:SetText(table.getn(ns) > 0 and table.concat(ns, "/") or "未选择（永不满足）")
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      end
      row.preview:SetText(EVAL_COND_STR(cd))
      pcall(row.preview.Show, row.preview)
      pcall(row.del.btn.Show, row.del.btn)
    end
  end
  -- 底部实时预览（整串条件）
  seUI.preview:SetText(EVAL_GROUP_STR(seLinearToGroups(ed.conds)))
end

local function SE_BUILD()
  if seUI.root then return end
  local W, H = 470, 280
  local root = CreateFrame("Frame", "EVAL_HELP_SE", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 60, 80)
  -- 配置窗是 DIALOG strata：本窗必须同级 + 更高 frameLevel，否则被配置窗盖住（1.11.2 修复）
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 100)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then -- 越界回归视野中心
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(16)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10) end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("SE_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- 技能选择行（1.32.3 二级下拉 UI）：[分类▾] [图标] [具体项▾]　启用
  -- 分类按钮在左（替代旧"技能:"标签位），项按钮在右——点哪个弹哪级，所见即两级
  local function seCatOfSkill(skill) -- 技能名 → 分类序号（EVAL_GO_SKILL_CATEGORIES 顺序）
    if skill == "攻击" then return 1 end
    if petCmdOf(skill) then return 3 end
    if targetSelOf(skill) then return 4 end
    if itemOf(skill) then return 5 end
    return 2
  end
  -- 项列表 → 图标表（1.32.4：下拉行左侧显示技能/物品图标；wicon 统一入口含宠物/选取/物品兜底）
  local function seItemIcons(items)
    local icons, any = {}, false
    for i, v in ipairs(items) do
      local nm = string.match(v, "^(物品[:：].-)×%d+$") or v
      local t = wicon(nm)
      if t then icons[i] = t any = true end
    end
    return any and icons or nil
  end
  -- 项选中落值（两个下拉共用）：特殊项弹输入框，物品项剥 ×数量 展示后缀
  local function seApplySkillPick(v)
    if not v then return end
    if v == L("SE_PICK_ITEM") then
      EVAL_TN_OPEN(L("SE_TN_ITEM"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "物品:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    if v == L("SE_PICK_TGT") then
      EVAL_TN_OPEN(L("SE_TN_TARGET"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "选取目标:指定名称:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    seUI.ed.skill = string.match(v, "^(物品[:：].-)×%d+$") or v
    EVAL_HELP_SE_REFRESH()
  end
  -- 分类下拉（一级）
  local catW = seBtn(root, 16, -24, 72, 16, "", function()
    if not seUI.ed then return end
    local cats = EVAL_GO_SKILL_CATEGORIES()
    local labels = {}
    for _, c in ipairs(cats) do table.insert(labels, c.label) end
    EVAL_DD_OPEN(seUI.catBtn, labels, function(ci)
      local cat = cats[ci]
      if not cat then return end
      -- 选完分类立即续弹该类的项列表（沿用 byName 续弹范式）
      local items = cat.items()
      EVAL_DD_OPEN(seUI.skillBtn, items, function(pi)
        seApplySkillPick(items[pi])
      end, { icons = seItemIcons(items) })
    end)
  end)
  seUI.catBtn = catW.btn
  seUI.catName = catW.text
  local icon = root:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", root, "TOPLEFT", 94, -24)
  icon:SetWidth(15) icon:SetHeight(15)
  seUI.skillIcon = icon
  -- 具体项下拉（二级）：直接弹当前分类的项列表
  -- 注意：seBtn 返回包裹表 { btn, bg, text }，不是按钮本体——锚点/加文字一律用 .btn（1.21.4 修复）
  local skW = seBtn(root, 114, -24, 100, 16, "", function()
    if not seUI.ed then return end
    local cats = EVAL_GO_SKILL_CATEGORIES()
    local cat = cats[seCatOfSkill(seUI.ed.skill)]
    if not cat then return end
    local items = cat.items()
    EVAL_DD_OPEN(seUI.skillBtn, items, function(pi)
      seApplySkillPick(items[pi])
    end, { icons = seItemIcons(items) })
  end)
  local skBtn = skW.btn
  seUI.skillBtn = skBtn
  local skName = uiText(skBtn, 10, 1, 0.9, 0.5)
  skName:SetPoint("CENTER", skBtn, "CENTER", 0, 0)
  pcall(skName.SetWidth, skName, 96) -- 长名（物品:xxx）裁剪防溢出到启用框
  pcall(skName.SetNonSpaceWrap, skName, false)
  seUI.skillName = skName
  local enChk = CreateFrame("Button", nil, root)
  enChk:SetWidth(14) enChk:SetHeight(14)
  enChk:SetPoint("TOPLEFT", root, "TOPLEFT", 216, -25)
  pcall(enChk.EnableMouse, enChk, true)
  pcall(enChk.RegisterForClicks, enChk, "LeftButtonUp")
  local enOut = enChk:CreateTexture(nil, "BACKGROUND")
  uiSolid(enOut, 0.85, 0.70, 0.20, 1)
  enOut:SetPoint("TOPLEFT", enChk, "TOPLEFT", 0, 0)
  enOut:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", 0, 0)
  local enIn = enChk:CreateTexture(nil, "ARTWORK")
  uiSolid(enIn, 0.10, 0.09, 0.06, 1)
  enIn:SetPoint("TOPLEFT", enChk, "TOPLEFT", 1, -1)
  enIn:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", -1, 1)
  local enMark = enChk:CreateTexture(nil, "OVERLAY")
  uiSolid(enMark, 0.95, 0.80, 0.25, 1)
  enMark:SetPoint("TOPLEFT", enChk, "TOPLEFT", 3, -3)
  enMark:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", -3, 3)
  enChk:SetScript("OnClick", function()
    if seUI.ed then seUI.ed.enabled = not seUI.ed.enabled EVAL_HELP_SE_REFRESH() end
  end)
  seUI.enMark = enMark
  local enLabel = uiText(root, 9, 0.75, 0.75, 0.75)
  enLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 234, -27)
  enLabel:SetText(L("SE_ENABLE"))

  -- 条件表头
  local hd = uiText(root, 9, 0.60, 0.55, 0.40)
  hd:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -48)
  hd:SetText(L("SE_HEADER"))

  -- 8 行条件池
  for i = 1, 8 do
    local y = -64 - (i - 1) * 20
    local row = { all = {} }
    local function reg(w) table.insert(row.all, w) return w end
    row.conn = seBtn(root, 16, y, 26, 15, L("SE_WHEN"), function()
      local ed = seUI.ed
      if ed and i > 1 and ed.conds[i] then
        ed.conds[i].conn = (ed.conds[i].conn == "|") and "&" or "|"
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.conn.btn)
    row.typeBtn = seBtn(root, 46, y, 92, 15, L("SE_TYPE_PH"), function()
      -- 点开下拉列表：全部 26 种条件类型可见可选（1.14.0：替代盲循环；1.25.0 选取目标；1.26.0 目标职业；1.28.0 连击点数）
      local ed = seUI.ed
      local it = ed and ed.conds[i]
      if not it then return end
      -- 1.32.5 分组美化：金色组标题（idxMap=0 不可选）+ 四类分组；hidden 类型（选取目标）不进下拉
      local items, idxMap = {}, {}
      for _, grp in ipairs(SE_TYPE_GROUPS) do
        table.insert(items, "|cffffd100· " .. L(grp.label) .. " ·|r")
        table.insert(idxMap, 0)
        for _, id in ipairs(grp.ids) do
          local ti2 = SE_BY_K[id]
          if ti2 and not SE_TYPES[ti2].hidden then table.insert(items, L("CT_" .. string.upper(SE_TYPES[ti2].id))) table.insert(idxMap, ti2) end
        end
      end
      EVAL_DD_OPEN(row.typeBtn.btn, items, function(ti0)
        local ti = idxMap[ti0]
        if not ti or ti == 0 then return end
        local old, new = it.cd, seDefaultCond(ti)
        if old.op and new.op then new.op, new.n = old.op, old.n end -- 同族参数保留
        local oldTd = SE_TYPES[SE_BY_K[old.k] or 1]
        if old.s and new.s and oldTd and oldTd.kind == SE_TYPES[ti].kind then new.s = old.s end -- s 仅同族保留
        it.cd = new
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.typeBtn.btn)
    -- 数值参数：[比较符] [-] 值 [+]
    row.opBtn = seBtn(root, 142, y, 34, 15, ">", function()
      -- 比较符下拉（1.19.0：替代点按循环，可选项全可见）
      local it = seUI.ed and seUI.ed.conds[i]
      if not (it and it.cd.op) then return end
      EVAL_DD_OPEN(row.opBtn.btn, SE_OPS, function(oi)
        it.cd.op = SE_OPS[oi]
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.opBtn.btn)
    row.minus = seBtn(root, 180, y, 20, 15, "-", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it and it.cd.n then it.cd.n = math.max(0, it.cd.n - 5) EVAL_HELP_SE_REFRESH() end
    end)
    reg(row.minus.btn)
    local vt = uiText(root, 9, 1, 0.9, 0.5)
    vt:SetPoint("TOPLEFT", root, "TOPLEFT", 204, y - 3)
    row.valText = vt
    reg(vt)
    row.plus = seBtn(root, 230, y, 20, 15, "+", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it and it.cd.n then it.cd.n = math.min(300, it.cd.n + 5) EVAL_HELP_SE_REFRESH() end
    end)
    reg(row.plus.btn)
    -- 布尔/标志/姿态：是/否循环
    row.valBtn = seBtn(root, 142, y, 44, 15, L("SE_YES"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it then
        local cd = it.cd
        local ti = SE_BY_K[cd.k] or 1
        local kind = SE_TYPES[ti].kind
        if kind == "bool" then cd.v = not cd.v
        elseif kind == "flag" then cd.inv = not cd.inv
        elseif kind == "form" then cd.k = (cd.k == "form") and "formNot" or "form" end
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.valBtn.btn)
    -- 姿态号下拉（1.19.0：替代 1/2/3 循环）
    row.formN = seBtn(root, 190, y, 30, 15, "1", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not (it and it.cd.n) then return end
      EVAL_DD_OPEN(row.formN.btn, { "1", "2", "3" }, function(ni)
        it.cd.n = ni
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.formN.btn)
    -- buff/debuff 技能名：显示 + [v] 下拉（1.19.0 移除 [<][>] 循环）
    local st2 = uiText(root, 9, 1, 0.9, 0.5)
    st2:SetPoint("TOPLEFT", root, "TOPLEFT", 142, y - 3)
    row.skillText = st2
    reg(st2)
    -- 1.35.2 布局优化：[v] 箭头按钮取消——文字本身就是触发区（透明热区覆盖，悬停高亮提示可点）
    local sHit = CreateFrame("Button", nil, root)
    sHit:SetWidth(120) sHit:SetHeight(15)
    sHit:SetPoint("TOPLEFT", root, "TOPLEFT", 140, y)
    pcall(sHit.EnableMouse, sHit, true)
    pcall(sHit.RegisterForClicks, sHit, "LeftButtonUp")
    sHit:SetScript("OnEnter", function() pcall(st2.SetTextColor, st2, 1, 1, 0.85) end)
    sHit:SetScript("OnLeave", function() pcall(st2.SetTextColor, st2, 1, 0.9, 0.5) end)
    row.sHit = sHit
    reg(sHit)
    -- [v] 下拉：buff/debuff 技能名全列表（1.35.2 起按钮本体常驻隐藏，仅作处理器宿主）
    row.sDrop = seBtn(root, 246, y, 16, 15, "v", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      local tdi = SE_TYPES[SE_BY_K[it.cd.k] or 1]
      if tdi and tdi.kind == "class" then
        -- 目标职业：多选下拉（或关系），点按切换 √ 不关面板（1.26.0）
        it.cd.cs = it.cd.cs or {}
        local items, sel = {}, {}
        for ci, c in ipairs(CLASS_LIST) do
          table.insert(items, c.name)
          if it.cd.cs[c.id] then sel[ci] = true end
        end
        EVAL_DD_OPEN(row.sHit, items, function(pi, on)
          it.cd.cs[CLASS_LIST[pi].id] = on or nil
          EVAL_HELP_SE_REFRESH()
        end, { multi = true, selected = sel })
        return
      end
      if tdi and tdi.kind == "target" then
        -- 指定名称的名称下拉（1.29.0）：最近 5 敌名（循环枚举法）+ 自定义输入弹窗
        local function openNameDrop()
          local items = {}
          for _, n in ipairs(EVAL_NEARBY_ENEMY_NAMES(5)) do table.insert(items, n) end
          table.insert(items, "✎ 自定义名称…")
          local customIdx = table.getn(items)
          EVAL_DD_OPEN(row.sHit, items, function(pi)
            if pi >= customIdx then
              EVAL_TN_OPEN("指定目标名称（盲打看金色回声行）", it.cd.nm or "", function(nm)
                it.cd.nm = nm
                EVAL_HELP_SE_REFRESH()
              end)
            else
              it.cd.nm = items[pi]
              EVAL_HELP_SE_REFRESH()
            end
          end)
        end
        if it.cd.s == "byName" then
          openNameDrop() -- 已是指定名称：本下拉=选名称（换种类重选条件类型即可）
        else
          -- 选取目标：下拉官方 Targetting 函数种类（1.25.0 七种 + 1.29.0 目标的目标/指定名称）
          local items = {}
          for _, t in ipairs(TARGET_SEL) do table.insert(items, t.name) end
          EVAL_DD_OPEN(row.sHit, items, function(pi)
            it.cd.s = TARGET_SEL[pi].id
            EVAL_HELP_SE_REFRESH()
            if it.cd.s == "byName" then openNameDrop() end -- 选完种类立即选名称
          end)
        end
        return
      end
      -- 1.32.9 重构：并行 names 表（显示前缀不入值，不做字符串解析）；排除伪技能（宠物/选取/物品——没有光环概念，1.32.9 修混入）；
      -- 实时项 ◆目标debuff/○自身buff（1.27.0）+ 已学习名 ◇（跨会话持久，buff 消失也能选——修「药水 buff 不及时显示」）；图标经 auraTexOf
      local items, names = {}, {}
      local function push(disp, nm) table.insert(items, disp) table.insert(names, nm) end
      for _, n in ipairs(EVAL_GO_SKILL_CHOICES()) do
        if not petCmdOf(n) and not targetSelOf(n) and not itemOf(n) then push(n, n) end
      end
      local k0 = it.cd.k
      local isAura = (k0 == "hasDebuff" or k0 == "noDebuff" or k0 == "hasBuff" or k0 == "noBuff")
      if k0 == "hasDebuff" or k0 == "noDebuff" then
        for _, d in ipairs(EVAL_TARGET_DEBUFF_LIST()) do push("◆" .. d.name, d.name) end
      elseif k0 == "hasBuff" or k0 == "noBuff" then
        for _, d in ipairs(EVAL_PLAYER_BUFF_LIST()) do push("○" .. d.name, d.name) end
      end
      if isAura then
        local seen = {}
        for _, n in ipairs(names) do seen[n] = true end
        local w2c = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
        local lt = w2c and w2c.debuffTex
        if lt then
          local ln = {}
          for n in pairs(lt) do table.insert(ln, n) end
          table.sort(ln)
          for _, n in ipairs(ln) do if not seen[n] then push("◇" .. n, n) end end
        end
      end
      local icons = {}
      local anyIcon = false
      for i2, nm in ipairs(names) do
        local t = auraTexOf(nm)
        if t then icons[i2] = t anyIcon = true end
      end
      EVAL_DD_OPEN(row.sHit, items, function(pi)
        it.cd.s = names[pi]
        EVAL_HELP_SE_REFRESH()
      end, { icons = anyIcon and icons or nil })
    end)
    row.sDrop.btn:Hide() -- 1.35.2 v 按钮常驻隐藏
    sHit:SetScript("OnClick", function() local c = row.sDrop.btn:GetScript("OnClick") if c then c() end end)
    reg(row.sDrop.btn)
    row.stk = seBtn(root, 266, y, 20, 15, L("SE_STK"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      local stkItems = { L("SE_STK_UNLIM") } for si = 2, 5 do table.insert(stkItems, L("SE_STK_FMT", si)) end
      EVAL_DD_OPEN(row.stk.btn, stkItems, function(pi)
        it.cd.n = (pi > 1) and pi or nil -- 序号2-5即层数2-5
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.stk.btn)
    -- 结果预览 + 删除
    local pv = uiText(root, 9, 0.55, 0.75, 0.55)
    pv:SetPoint("TOPLEFT", root, "TOPLEFT", 288, y - 3)
    row.preview = pv
    reg(pv)
    row.del = seBtn(root, 420, y, 28, 15, L("W_DEL"), function()
      local ed = seUI.ed
      if ed and ed.conds[i] then table.remove(ed.conds, i) EVAL_HELP_SE_REFRESH() end
    end)
    reg(row.del.btn)
    seUI.rows[i] = row
  end

  -- 添加条件 + 预览 + 保存/取消
  seBtn(root, 16, -64 - 8 * 20 - 6, 96, 16, L("SE_ADD"), function()
    local ed = seUI.ed
    if ed and table.getn(ed.conds) < 8 then
      table.insert(ed.conds, { conn = (table.getn(ed.conds) > 0) and "&" or nil, cd = seDefaultCond(1) })
      EVAL_HELP_SE_REFRESH()
    end
  end)
  -- 1.36.2 预览挪到 [+添加条件] 右侧同行（原在底部与 保存/取消 按钮重叠）
  local pvLabel = uiText(root, 9, 0.60, 0.55, 0.40)
  pvLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 122, -64 - 8 * 20 - 9)
  pvLabel:SetText(L("SE_PREVIEW"))
  local pv = uiText(root, 9, 0.95, 0.82, 0.35)
  pv:SetPoint("TOPLEFT", root, "TOPLEFT", 158, -64 - 8 * 20 - 9)
  pcall(pv.SetWidth, pv, 300)
  pcall(pv.SetJustifyH, pv, "LEFT")
  seUI.preview = pv
  local function bBtn(x, w, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(150, 80, L("SE_SAVE"), function() EVAL_HELP_SE_SAVE() end)
  bBtn(240, 80, L("BTN_CANCEL"), function() root:Hide() end)
  root:Hide()
  root:SetScript("OnHide", function() EVAL_DD_HIDE() end)
  seUI.root = root
end

function EVAL_HELP_SE_SAVE()
  local ed = seUI.ed
  if not ed then return end
  local w2 = warCfg()
  local p = w2.profiles[ed.profIdx]
  if not p then if seUI.root then seUI.root:Hide() end return end
  local groups = seLinearToGroups(ed.conds)
  if ed.skillIdx and p.skills[ed.skillIdx] then
    local r = p.skills[ed.skillIdx]
    r.skill = ed.skill
    r.enabled = ed.enabled
    r.groups = groups
    say("已保存技能: " .. tostring(ed.skill) .. " → " .. EVAL_GROUP_STR(groups))
  else
    -- 1.33.0 取消 8 技能上限（配置窗列表支持滚动）
    table.insert(p.skills, { skill = ed.skill, enabled = ed.enabled, groups = groups, why = ed.skill })
    say("已添加技能: " .. tostring(ed.skill) .. " → " .. EVAL_GROUP_STR(groups))
  end
  pcall(EVAL_WAR_TAB_REFRESH)
  if seUI.root then seUI.root:Hide() end
end

-- 打开编辑窗：skillIdx=nil 表示新增（presetSkill 预选技能）
function EVAL_HELP_SE_OPEN(profIdx, skillIdx, presetSkill)
  SE_BUILD()
  local w2 = warCfg()
  local p = w2.profiles[profIdx]
  if not p then return end
  local ed = { profIdx = profIdx, skillIdx = skillIdx }
  if skillIdx and p.skills[skillIdx] then
    local r = p.skills[skillIdx]
    ed.skill = r.skill
    ed.enabled = r.enabled ~= false
    ed.conds = seGroupsToLinear(r.groups)
  else
    ed.skill = presetSkill or WAR_SKILLS[1]
    ed.enabled = true
    ed.conds = {}
  end
  seUI.ed = ed
  EVAL_HELP_SE_REFRESH()
  seUI.root:Show()
end

-- ============ 方案 导入/导出（md 文本互转，复制粘贴快速分享） ============
-- 存储/交换格式（example/zs_wq.md 同款）：
--   # 方案: 武器战
--   - 压制 | 怒气>5 & 可用 & 就绪
--   - !猛击 | Alt & 怒气>20        （技能名前 ! = 该技能停用）
-- 解析容忍 markdown 杂物：# 开头 = 方案名，> 或 < 开头/超长行忽略，无 | 的行忽略。

local ioUI = { root = nil, eb = nil }

-- 内置武器战示例（与 example/zs_wq.md 同步，游戏里也能直接看到格式）
local ZS_WQ_EXAMPLE = "# 方案: 武器战\n\n" ..
  "- 压制 | 怒气>5 & 可用 & 就绪\n" ..
  "- 战斗怒吼 | 怒气>9 & 无buff:战斗怒吼\n" ..
  "- 断筋 | 目标血<30 & 怒气>9 & 无debuff:断筋\n" ..
  "- 撕裂 | 可流血 & 目标血>10 & 怒气>9 & 无debuff:撕裂\n" ..
  "- 血性狂暴 | 战斗中 & 无buff:血性狂暴 & 就绪\n" ..
  "- 猛击 | Alt & 怒气>20\n" ..
  "- 英勇打击 | 怒气>30 & 未排队"

-- 方案 → md 文本（导出）
function EVAL_PROFILE_TO_TEXT(idx)
  local w2 = warCfg()
  local p = w2.profiles[idx or (w2.activeProfile or 1)]
  if not p then return "" end
  local lines = {}
  table.insert(lines, "# 方案: " .. tostring(p.name))
  table.insert(lines, "")
  for _, r in ipairs(p.skills or {}) do
    local dis = (r.enabled == false) and "!" or ""
    table.insert(lines, "- " .. dis .. tostring(r.skill) .. " | " .. EVAL_GROUP_STR(r.groups))
  end
  return table.concat(lines, "\n")
end

-- md 文本 → 方案表（导入）；失败返回 nil+原因
function EVAL_PROFILE_FROM_TEXT(text)
  if type(text) ~= "string" then return nil, "无文本" end
  text = string.gsub(text, "\r\n", "\n")
  text = string.gsub(text, "\r", "\n")
  local name, skills = nil, {}
  for line in string.gmatch(text .. "\n", "(.-)\n") do
    local l = condTrim(line)
    local nm = string.match(l, "^#%s*方案[:：]%s*(.+)$") or string.match(l, "^#%s*(.+)$")
    if nm then
      name = condTrim(nm)
    elseif string.sub(l, 1, 1) ~= ">" and string.sub(l, 1, 1) ~= "<" and l ~= "" then
      local body = string.match(l, "^[-*]%s*(.+)$") or l
      local sn, conds = string.match(body, "^([^|]+)|(.*)$")
      if sn then
        sn = condTrim(sn)
        local enabled = true
        if string.sub(sn, 1, 1) == "!" then enabled = false sn = condTrim(string.sub(sn, 2)) end
        -- 技能名合理性守卫：超过 8 个汉字的行视为说明文字
        if sn ~= "" and string.len(sn) <= 24 then
          table.insert(skills, { skill = sn, enabled = enabled, groups = EVAL_PARSE_CONDS(conds or ""), why = sn })
        end
      end
    end
  end
  if table.getn(skills) == 0 then return nil, "没解析到技能行（格式: - 技能名 | 条件）" end
  return { name = name or "导入方案", skills = skills } -- 1.33.0 取消 8 技能上限
end

function EVAL_HELP_IO_BUILD()
  if ioUI.root then return end
  local W, H = 470, 350
  local root = CreateFrame("Frame", "EVAL_HELP_IO", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  -- 同 1.11.2：抬到 DIALOG 同级 + 高 frameLevel，避免被配置窗（DIALOG）盖住
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 90)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  -- 标题栏拖动（Button 配方）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(16)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10) end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("IO_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- 操作说明
  local tip = uiText(root, 9, 0.75, 0.75, 0.75)
  tip:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -26)
  tip:SetText(L("IO_TIP"))

  -- 多行输入框（1.15.1：字体对象优先；本客户端 EditBox 可能不渲染，下方有保底预览区）
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_IO_EB", root)
  if okEb and eb then
    pcall(eb.SetMultiLine, eb, true)
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    -- 1.32.8 编辑区尺寸修正：EditBox 装进 ScrollFrame 精确裁剪到可视框（ebBg 内缩），
    -- 不再溢出盖住说明行/预览区；超高文本自动滚到底部。ScrollFrame 不可用时回退旧直挂布局。
    local okSF, sf = pcall(CreateFrame, "ScrollFrame", "EVAL_HELP_IO_SF", root)
    if okSF and sf and pcall(sf.SetScrollChild, sf, eb) then
      sf:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -40)
      sf:SetWidth(W - 32) sf:SetHeight(136)
      eb:SetPoint("TOPLEFT", sf, "TOPLEFT", 4, -2)
      eb:SetWidth(W - 48) eb:SetHeight(132)
      eb:SetScript("OnTextChanged", function()
        pcall(sf.UpdateScrollChildRect, sf)
        local okr, range = pcall(sf.GetVerticalScrollRange, sf)
        if okr and type(range) == "number" then pcall(sf.SetVerticalScroll, sf, range) end
      end)
      ioUI.sf = sf
    else
      eb:SetWidth(W - 40) eb:SetHeight(128)
      eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -44)
    end
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 10, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 10) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -38)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(140)
    local ebEdge = root:CreateTexture(nil, "BORDER")
    uiSolid(ebEdge, 0.85, 0.70, 0.20, 0.8)
    ebEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -38)
    ebEdge:SetWidth(W - 28) ebEdge:SetHeight(1)
    eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
    ioUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -44)
    noEb:SetText("（输入框不可用：导入改用 /eh war add 逐条添加；导出看下方预览区或 example/zs_wq.md）")
  end

  -- 保底预览区：当前方案文本以 FontString 渲染（EditBox 不显示时也始终可见）
  local pvLabel = uiText(root, 9, 0.95, 0.82, 0.35)
  pvLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -184)
  pvLabel:SetText(L("IO_PV"))
  ioUI.pvLines = {}
  for i = 1, 8 do
    local ln = uiText(root, 9, 0.82, 0.82, 0.82)
    ln:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -196 - (i - 1) * 12)
    pcall(ln.SetWidth, ln, W - 40)
    pcall(ln.SetJustifyH, ln, "LEFT")
    ioUI.pvLines[i] = ln
  end

  -- 配置文件位置提示（1.20.2：EditBox 不可复制时的兜底——方案自动存盘，小退后文件即最新）
  local pathTip = uiText(root, 8, 0.55, 0.55, 0.55)
  pathTip:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -288)
  pcall(pathTip.SetWidth, pathTip, W - 28)
  pcall(pathTip.SetJustifyH, pathTip, "LEFT")
  pathTip:SetText(L("IO_PATH1"))
  local pathTip2 = uiText(root, 8, 0.68, 0.62, 0.30)
  pathTip2:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -300)
  pcall(pathTip2.SetWidth, pathTip2, W - 28)
  pcall(pathTip2.SetJustifyH, pathTip2, "LEFT")
  pathTip2:SetText("%LOCALAPPDATA%\\Azeroth\\Saved\\Account\\<你的账号>\\SavedVariables\\EVAL_HELP.lua")

  -- 底部按钮行
  local function ioBtn(x, w, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(24)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 14)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  ioBtn(14, 108, L("IO_IMPORT"), function()
    local text = ""
    if ioUI.eb then
      local ok, t = pcall(ioUI.eb.GetText, ioUI.eb)
      if ok and type(t) == "string" then text = t end
    end
    local prof, err = EVAL_PROFILE_FROM_TEXT(text)
    if not prof then say("导入失败: " .. tostring(err)) return end
    local w2 = warCfg()
    if table.getn(w2.profiles) < 4 then
      table.insert(w2.profiles, prof)
      w2.activeProfile = table.getn(w2.profiles)
      say("已导入为新方案: " .. tostring(prof.name) .. "（" .. table.getn(prof.skills) .. " 个技能）")
    else
      w2.profiles[w2.activeProfile or 1] = prof
      say("方案已满 4 个，已替换当前方案: " .. tostring(prof.name))
    end
    pcall(EVAL_WAR_TAB_REFRESH)
    ioUI.root:Hide()
  end)
  ioBtn(128, 108, L("IO_EXPORT"), function()
    if ioUI.eb then
      pcall(ioUI.eb.SetText, ioUI.eb, EVAL_PROFILE_TO_TEXT())
      pcall(ioUI.eb.SetFocus, ioUI.eb)
      pcall(ioUI.eb.HighlightText, ioUI.eb)
    end
    EVAL_HELP_IO_REFRESH()
    say("已导出到输入框并全选：Ctrl+C 复制，存成 .md 即可分享（输入框不显示就看下方预览区）")
  end)
  ioBtn(242, 108, L("IO_SAMPLE"), function()
    if ioUI.eb then pcall(ioUI.eb.SetText, ioUI.eb, ZS_WQ_EXAMPLE) end
    say("已填入武器战示例（与 example/zs_wq.md 相同），可改后点导入")
  end)
  ioBtn(392, 64, L("CLOSE"), function() ioUI.root:Hide() end)

  root:Hide()
  ioUI.root = root
end

-- 预览区刷新：当前方案文本逐行填进保底 FontString（跳过空行；EditBox 不渲染时靠它看内容）
function EVAL_HELP_IO_REFRESH()
  if not ioUI.pvLines then return end
  local lines = {}
  for line in string.gmatch(EVAL_PROFILE_TO_TEXT() .. "\n", "(.-)\n") do
    if line ~= "" then table.insert(lines, line) end
  end
  for i, ln in ipairs(ioUI.pvLines) do
    ln:SetText(lines[i] or "")
  end
end

function EVAL_HELP_IO_TOGGLE()
  if ioUI.root and ioUI.root:IsVisible() then ioUI.root:Hide() return end
  EVAL_HELP_IO_BUILD()
  -- 每次打开默认填入当前方案的导出文本（看一眼格式 / 直接改）
  if ioUI.eb then pcall(ioUI.eb.SetText, ioUI.eb, EVAL_PROFILE_TO_TEXT()) end
  EVAL_HELP_IO_REFRESH()
  if ioUI.root then ioUI.root:Show() end
end

-- ============ 斜杠命令 /eh ============

if type(SlashCmdList) == "table" then
  SLASH_EVALHELP1 = "/eh"
  SLASH_EVALHELP2 = "/evalhelp"
  SlashCmdList["EVALHELP"] = function(msg)
    msg = string.lower(tostring(msg or ""))
    msg = string.gsub(msg, "^war", "go") -- /eh war 旧命令组兼容 → 通用 /eh go（1.21.1 改名）
    if msg == "log" then
      cfg.log = not cfg.log
      say("写日志文件: " .. (cfg.log and "|cff00ff00开|r" or "|cffff0000关|r"))
    elseif msg == "auto" then
      cfg.auto = not cfg.auto
      say("进出战斗自动输出: " .. (cfg.auto and "|cff00ff00开|r" or "|cffff0000关|r"))
    elseif msg == "ui" then
      EVAL_HELP_UI_TOGGLE()
    elseif msg == "cfg" or msg == "config" or msg == "set" then
      EVAL_HELP_CFG_TOGGLE()
    elseif msg == "st" or msg == "state" or msg == "info" then
      EVAL_HELP_ST_TOGGLE()
    elseif string.find(msg, "^go add ") then
      -- 兜底添加: /eh go add 技能名 条件串（如 /eh go add 压制 可用 & 就绪）
      local sn, conds = string.match(string.sub(msg, 8), "^(%S+)%s*(.*)$")
      if sn then
        local w2 = warCfg()
        local p = w2.profiles[w2.activeProfile or 1]
        if p then -- 1.33.4 取消 8 上限残留（1.33.0 漏改的 /eh go add 路径）
          table.insert(p.skills, { skill = sn, enabled = true, groups = EVAL_PARSE_CONDS(conds), why = sn })
          say("已添加: " .. sn .. " → " .. ((conds ~= "") and conds or "无条件"))
          pcall(EVAL_WAR_TAB_REFRESH)
        end
      end
    elseif string.find(msg, "^go del ") then
      local n = tonumber(string.sub(msg, 8))
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      if p and n and p.skills[n] then
        say("已删除: " .. tostring(p.skills[n].skill))
        table.remove(p.skills, n)
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif string.find(msg, "^go newprof") then
      local nm = string.match(msg, "^go newprof%s*(.*)$")
      local w2 = warCfg()
      if table.getn(w2.profiles) < 4 then
        table.insert(w2.profiles, { name = (nm and nm ~= "") and nm or ("方案" .. tostring(table.getn(w2.profiles) + 1)), skills = {} })
        w2.activeProfile = table.getn(w2.profiles)
        say("新建并切换到: " .. tostring(w2.profiles[w2.activeProfile].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      else
        say("最多 4 个方案")
      end
    elseif string.find(msg, "^go prof ") then
      local n = tonumber(string.sub(msg, 9))
      local w2 = warCfg()
      if n and w2.profiles[n] then
        w2.activeProfile = n
        say("切换到方案: " .. tostring(w2.profiles[n].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif string.find(msg, "^go delprof") then
      local n = tonumber(string.match(msg, "^go delprof%s*(%d*)$"))
      local w2 = warCfg()
      EVAL_WAR_DEL_PROFILE(n or (w2.activeProfile or 1))
    elseif string.find(msg, "^go rename ") or string.find(msg, "^go name ") then
      local nm = string.match(msg, "^go %S+%s+(.+)$")
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      if p and nm and nm ~= "" then
        p.name = nm
        say("方案已改名: " .. nm)
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif msg == "go next" then
      local w2 = warCfg()
      if table.getn(w2.profiles) > 1 then
        w2.activeProfile = (w2.activeProfile or 1) % table.getn(w2.profiles) + 1
        say("切换到方案: " .. tostring(w2.profiles[w2.activeProfile].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      else
        say("只有一个方案（配置窗口 一键宏设置页 [+] 新建）")
      end
    elseif msg == "go io" or msg == "go export" or msg == "go import" then
      EVAL_HELP_IO_TOGGLE()
    elseif msg == "go list" then
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      say("— 方案[" .. tostring(p and p.name) .. "] —")
      if p then
        for i, r in ipairs(p.skills) do
          say(string.format("%d. %s %s | %s", i, tostring(r.skill),
            (r.enabled ~= false) and "|cff00ff00开|r" or "|cffff0000关|r", EVAL_GROUP_STR(r.groups)))
        end
      end
    elseif msg == "go" then
      EVAL_GO_STATUS()
    elseif msg == "go rescan" then
      EVAL_GO_RESCAN(false)
    elseif msg == "go probe immune" then
      -- 免疫事件探针（1.35.1，免疫学习器前置验证）：30 秒全事件抓取——CHAT_MSG_* 或参数含「免疫/immune」
      -- 的写 UELog；对免疫怪放技能后翻日志拿真实事件名+文本格式，再写解析器（事件 wiki 无文档页）
      say("免疫探针启动：30 秒内对免疫怪放技能（如撕裂）→ /eh go probe dump 看结果")
      local pf = CreateFrame("Frame")
      local t0 = GetTime()
      -- 1.35.5：0 条说明全事件抓取可能没收到——加全事件计数（判定 RegisterAllEvents 是否有效）
      -- + 显式注册候选事件名对照（计数键带 [R] 前缀区分通道）
      cfg.probeLog = {}
      cfg.probeEvents = {}
      local CAND = { "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_FAILED_LOCALPLAYER", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_SPELL_SELF_BUFF" }
      pf:SetScript("OnEvent", function()
        local a1, a2 = arg1, arg2
        local ev = (type(event) == "string") and event or nil
        local name = ev or (type(a1) == "string" and a1) or ""
        if name ~= "" then
          local pe = cfg.probeEvents
          pe[name] = (pe[name] or 0) + 1
          local sk = name .. "_s"
          if not pe[sk] then pe[sk] = tostring(a1) .. " | " .. tostring(a2) end
        end
        local hit = (string.find(name, "^CHAT_MSG") ~= nil)
        if not hit then
          for _, v in ipairs({ a1, a2 }) do
            if type(v) == "string" and (string.find(v, "免疫") or string.find(v, "immune")) then hit = true break end
          end
        end
        if hit then
          table.insert(cfg.probeLog, "PROBE " .. tostring(name) .. " | a1=" .. tostring(a1) .. " | a2=" .. tostring(a2))
          while table.getn(cfg.probeLog) > 120 do table.remove(cfg.probeLog, 1) end
        end
      end)
      local okAll = pcall(pf.RegisterAllEvents, pf)
      for _, en in ipairs(CAND) do pcall(pf.RegisterEvent, pf, "[R]" .. en) end -- 显式注册走同一帧（事件名前缀[R]区分）
      say("RegisterAllEvents pcall=" .. tostring(okAll) .. "；显式候选 " .. table.getn(CAND) .. " 个")
      pf:SetScript("OnUpdate", function()
        if GetTime() - t0 > 30 then
          pcall(pf.UnregisterAllEvents, pf)
          pf:SetScript("OnUpdate", nil)
          pf:SetScript("OnEvent", nil)
          say("免疫探针结束（30s），已记录 " .. table.getn(cfg.probeLog or {}) .. " 条 → /eh go probe dump 查看")
        end
      end)
    elseif msg == "go probe dump" then
      -- 打印探针持久记录（1.35.4：UELog 不落盘的替代查看通道；打完免疫技能后用这个看）
      local pl = cfg.probeLog or {}
      say("— 探针记录 " .. table.getn(pl) .. " 条 —")
      for i, line in ipairs(pl) do say(i .. ". " .. line) end
      -- 1.35.5 全事件计数总览（判断事件系统是否工作）：按次数降序打前 25 个 + 首样本
      local pe = cfg.probeEvents or {}
      local names = {}
      for n, c2 in pairs(pe) do if type(c2) == "number" then table.insert(names, n) end end
      table.sort(names, function(a, b) return pe[a] > pe[b] end)
      say("— 事件计数（共 " .. table.getn(names) .. " 种）—")
      for i = 1, math.min(25, table.getn(names)) do
        local n = names[i]
        say(n .. " × " .. pe[n] .. "  样本: " .. tostring(pe[n .. "_s"]))
      end
      if table.getn(pl) == 0 and table.getn(names) == 0 then say("（全空——先 /eh go probe immune 并在 30 秒内对免疫怪放技能；若反复全空说明事件系统不可用）") end
    elseif msg == "go immune" then
      local im = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.immune) or {}
      local n, keys = 0, {}
      for k in pairs(im) do n = n + 1 table.insert(keys, k) end
      table.sort(keys)
      say("免疫学习记录 " .. n .. " 条（/eh go immune clear 清空）:")
      for _, k in ipairs(keys) do say("  " .. k) end
    elseif msg == "go immune clear" then
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war then EVAL_HELP_CONFIG.war.immune = {} end
      say("免疫学习记录已清空")
    elseif msg == "go probe" then
      -- buff 探针（1.33.1）：两条枚举+tooltip 读名路径原始值打印，诊断药品类 buff 不进下拉
      say("— buff 探针（结果同时写日志文件） —")
      local function pr(s) say(s) logLine(s) end
      pr("GetPlayerBuff=" .. tostring(type(GetPlayerBuff)) .. " UnitBuff=" .. tostring(type(UnitBuff)) .. " SetPlayerBuff=" .. tostring(type(GameTooltip.SetPlayerBuff)) .. " SetUnitBuff=" .. tostring(type(GameTooltip.SetUnitBuff)))
      pr("BuffButton0=" .. tostring(getglobal("BuffButton0") ~= nil) .. " BuffFrame=" .. tostring(getglobal("BuffFrame") ~= nil))
      for i = 0, 3 do
        local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
        pr(string.format("GPB(%d) ok=%s bi=%s(%s)", i, tostring(okb), tostring(bi), type(bi)))
        if okb and type(bi) == "number" and bi >= 0 then
          local okt, tex = pcall(GetPlayerBuffTexture, bi)
          pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
          pcall(function() GameTooltip:ClearLines() end)
          local oks, built = pcall(GameTooltip.SetPlayerBuff, GameTooltip, bi)
          local nm = GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText and GameTooltipTextLeft1:GetText()
          pr("  tex=" .. tostring(okt and tex) .. " | SetPlayerBuff ok=" .. tostring(oks) .. " built=" .. tostring(built) .. " name=" .. tostring(nm))
          pcall(function() GameTooltip:Hide() end)
        end
      end
      for i = 1, 4 do
        local oku, tex, apps = pcall(UnitBuff, "player", i)
        pr(string.format("UnitBuff(%d) ok=%s tex=%s apps=%s", i, tostring(oku), tostring(tex), tostring(apps)))
        if oku and tex then
          pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
          pcall(function() GameTooltip:ClearLines() end)
          local oks, built = pcall(GameTooltip.SetUnitBuff, GameTooltip, "player", i)
          local nm = GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText and GameTooltipTextLeft1:GetText()
          pr("  SetUnitBuff ok=" .. tostring(oks) .. " built=" .. tostring(built) .. " name=" .. tostring(nm))
          pcall(function() GameTooltip:Hide() end)
        end
      end
    elseif msg == "wdebug" or msg == "debug" then
      cfg.wdebug = not cfg.wdebug
      say("调试日志: " .. (cfg.wdebug and "|cff00ff00开|r" or "|cffff0000关|r"))
    elseif msg == "help" then
      say("—— EVAL_HELP 全职业施法工具（通用一键宏） ——")
      say("|cffffff00快速上手:|r ① 技能拖上动作条 ② /eh go rescan ③ 新建宏正文 /run EVAL_GO() 拖上按键连按")
      say("|cffffff00命令:|r /eh 输出状态 | /eh log 写日志开关 | /eh auto 进出战斗自动输出")
      say("/eh ui 战斗信息UI | /eh st 状态信息UI | /eh cfg 设置窗口（小地图旁 EH 图标同效）")
      say("/eh go 一键宏状态 | /eh go rescan 重扫动作条 | /eh debug 调试日志（/eh war 旧命令仍兼容）")
      say("方案命令：/eh go list 查看 | go add 技能 条件 | go del N | go newprof 名 | go prof N | go rename 新名 | go delprof N")
      say("方案导入导出（md 文本复制粘贴）：/eh go io，示例文件 example/zs_wq.md")
      say("方案切换：Shift+按一键宏 | /eh go next | 战斗信息UI 方案按钮")
      say("|cffffff00执行指定方案:|r 新建宏正文 /run EVAL_GO(参数) —— 不传或0=当前激活方案；方案号1~4 或 \"方案名\" = 只跑该方案（不切激活）")
      say("　例：/run EVAL_GO(2) 跑2号方案 | /run EVAL_GO(\"测试\") 跑名为测试的方案 | /run EVAL_GO1()~GO4() 同效快捷写法；不同方案各绑一个按键即可多套输出")
      say("|cffffff00提示:|r 猛击需按住 Alt 按宏键；宏入口 /run EVAL_HELP() 输出状态日志")
      say("|cffffff00异常自救:|r 技能不识别/界面异常/刚更新过插件 → 先 /reload 重载（配置已存盘不会丢）；重扫动作条 /eh go rescan")
      say("|cffffff00问题反馈:|r https://gitee.com/xeval/emberveil_eval_help.git —— 插件持续优化中，欢迎测试并留下宝贵意见")
      say("日志文件: %LOCALAPPDATA%\\Azeroth\\Saved\\Logs")
    else
      EVAL_HELP()
    end
  end
end

-- ============ 初始化（SavedVariables 要等 VARIABLES_LOADED 才恢复） ============

local init = CreateFrame("Frame", "EVAL_HELPInitFrame", UIParent)
pcall(init.RegisterEvent, init, "VARIABLES_LOADED")
init:SetScript("OnEvent", function(a, b)
  -- 本客户端 OnEvent 参数传递有兼容差异：event 可能在第 1 参、第 2 参或全局 event
  local eventName
  if type(a) == "string" then eventName = a
  elseif type(b) == "string" then eventName = b
  elseif type(event) == "string" then eventName = event end

  if eventName == "VARIABLES_LOADED" then
    cfg = EVAL_HELP_CONFIG or {}
    EVAL_HELP_CONFIG = cfg
    ehResolveLang() -- 1.34.0 语言解析：cfg.lang 优先 → 客户端语言自动检测
    if cfg.log  == nil then cfg.log  = true  end -- 默认写日志文件
    if cfg.auto == nil then cfg.auto = false end -- 默认不自动输出
    if cfg.wdebug == nil then cfg.wdebug = false end
    if not cfg.war then
      cfg.war = { enabled = true, attack = true, hsRage = 30, slamRage = 20, hamHp = 30, rendHp = 10, ovRage = 5, bsRage = 9 }
    end
    -- 小地图按钮：恢复拖到的位置（越界则清掉记忆，回到默认锚点）
    if cfg.mbPos and minimapBtn then
      pcall(minimapBtn.ClearAllPoints, minimapBtn)
      pcall(minimapBtn.SetPoint, minimapBtn, cfg.mbPos.point, UIParent,
        cfg.mbPos.relPoint or cfg.mbPos.point, cfg.mbPos.x or 0, cfg.mbPos.y or 0)
      if uiOffscreen(minimapBtn) then
        cfg.mbPos = nil
        pcall(minimapBtn.ClearAllPoints, minimapBtn)
        if type(Minimap) == "table" or type(Minimap) == "userdata" then
          pcall(minimapBtn.SetPoint, minimapBtn, "TOPRIGHT", Minimap, "TOPLEFT", -6, 0)
        else
          pcall(minimapBtn.SetPoint, minimapBtn, "TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
        end
      end
    end
    -- 战斗信息UI：上次开着的话恢复显示
    if cfg.ui and cfg.ui.enabled then
      EVAL_HELP_UI_BUILD()
      if ui.root then ui.root:Show() end
    end
    -- 状态信息UI：上次开着的话恢复显示
    if cfg.st and cfg.st.enabled then
      EVAL_HELP_ST_BUILD()
      if stui.root then stui.root:Show() end
    end
    -- 注册进出战斗事件（pcall 防御：事件名若不存在不会崩）
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_REGEN_DISABLED")
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_REGEN_ENABLED")
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_TARGET_CHANGED") -- Cat：目标切换时刷新可流血等状态
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_SPELL_SELF_DAMAGE") -- 1.36.0 免疫学习器（探针实测事件名）
    autoFrame:SetScript("OnEvent", function(ea, eb)
      local en
      if type(ea) == "string" then en = ea
      elseif type(eb) == "string" then en = eb
      elseif type(event) == "string" then en = event end
      if en == "PLAYER_REGEN_DISABLED" then
        EVAL_HELP_STATE.combatStart = GetTime() -- 精确进战时间（Cat 的 MPInCombatTime）
        onCombatEvent(true)
      elseif en == "PLAYER_REGEN_ENABLED" then
        EVAL_HELP_STATE.combatStart = nil
        onCombatEvent(false)
      elseif en == "PLAYER_TARGET_CHANGED" then
        EVAL_HELP_UPDATE_STATE()
      elseif en == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        -- 消息文本取全局 arg1；ea/eb 若承载事件名则不当消息用（三态兼容）
        local msgT = (type(arg1) == "string" and arg1) or ((type(ea) == "string" and ea ~= en) and ea) or (type(eb) == "string" and eb)
        if msgT then EVAL_IMMUNE_LEARN(msgT) end
      end
    end)
    say("全职业施法工具 " .. VERSION .. "（通用一键宏） — 一键宏 /run EVAL_GO() | /eh cfg 配置 | /eh help 帮助")
  end
end)