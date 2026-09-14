-- EvalHelp · Engine.lua —— 一键宏引擎：动作条扫描/技能五分类/规则引擎/条件解析/免疫学习/光环学习/距离分档
-- 依赖 Core.lua 导出；状态读 EVAL_HELP_STATE

local st = EVAL_HELP_STATE
local L = EVAL_L
local formatStats, collectStats = EVAL_FORMAT_STATS, EVAL_COLLECT_STATS -- 1.41.2 拆分漏桥补

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
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff9040war:|r " .. tostring(msg)) end
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
    EVAL_SAY(string.format("动作条共识别 |cff00ff00%d|r 个技能（均可用于方案/条件；核心技能核对↓）", total))
    for _, n in ipairs(WAR_SKILLS) do
      local s = wslots[n]
      EVAL_SAY(string.format("%s → %s", n, s and ("格子 " .. s.slot) or "|cffff0000未找到|r（拖上动作条后 /eh war rescan）"))
    end
  end
  return wslots
end

-- 目标距离分档（1.37.0）：本客户端无精确距离 API（CheckInteractDistance 实测不分档、无目标坐标入口）——
-- 用已知射程参照技能 + IsActionInRange 分档：近战(≤5码)/冲锋距(8-25码)/远程外；无参照技能=nil（不显示）
function EVAL_T_RANGE()
  if not (st.hasTarget and not st.tDead) then return nil end
  if type(IsActionInRange) ~= "function" then return nil end
  local function inRange(name)
    local s = wslots[name]
    if not s then return nil end
    local okr, r = pcall(IsActionInRange, s.slot)
    if not okr or r == nil or r == 1 then return nil end -- 1=自动攻击类不测距
    return r == true
  end
  local melee
  for _, n in ipairs({ "断筋", "压制", "撕裂", "英勇打击", "猛击", "斩杀" }) do
    melee = inRange(n)
    if melee ~= nil then break end
  end
  if melee == true then return "近战" end
  local charge = inRange("冲锋")
  if charge == true then return "冲锋距" end
  if melee == false or charge == false then return "远程外" end
  return nil
end

local function wtex(name) local s = wslots[name]; return s and s.tex end

-- 目标距离分档（1.37.0）：本客户端无精确距离 API（CheckInteractDistance 实测不分档、无目标坐标入口）——
-- 用已知射程参照技能 + IsActionInRange 分档：近战(≤5码)/冲锋距(8-25码)/远程外；无参照技能=nil（不显示）
function EVAL_T_RANGE()
  if not (st.hasTarget and not st.tDead) then return nil end
  if type(IsActionInRange) ~= "function" then return nil end
  local function inRange(name)
    local s = wslots[name]
    if not s then return nil end
    local okr, r = pcall(IsActionInRange, s.slot)
    if not okr or r == nil or r == 1 then return nil end -- 1=自动攻击类不测距
    return r == true
  end
  local melee
  for _, n in ipairs({ "断筋", "压制", "撕裂", "英勇打击", "猛击", "斩杀" }) do
    melee = inRange(n)
    if melee ~= nil then break end
  end
  if melee == true then return "近战" end
  local charge = inRange("冲锋")
  if charge == true then return "冲锋距" end
  if melee == false or charge == false then return "远程外" end
  return nil
end

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
-- 名称→纹理即时学习（EVAL_HELP_CONFIG.war.debuffTex 持久化，cfg 未加载时落 EVAL_DEBUFF_TEX_LEARN 运行时兜底）：
-- 学到后，怪给的非动作条 debuff 也能做 有/无debuff 图标比对（texOf 回退查学习表）。
EVAL_DEBUFF_TEX_LEARN = EVAL_DEBUFF_TEX_LEARN or {}

local function learnAuraTex(name, tex)
  if not (name and tex and name ~= "") then return end
  local store = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex) or EVAL_DEBUFF_TEX_LEARN
  store[name] = tex
end

-- 光环名 → 纹理：动作条优先，学习表回退（1.27.0 前只有动作条一条路径）
local function auraTexOf(n)
  local s = wslots[n]
  if s and s.tex then return s.tex end
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex and EVAL_HELP_CONFIG.war.debuffTex[n] then return EVAL_HELP_CONFIG.war.debuffTex[n] end
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
    EVAL_LOGLINE(pline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. pline .. "|r") end
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
    EVAL_LOGLINE(tline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. tline .. "|r") end
    return true
  end
  local iname = itemOf(name)
  if iname then
    -- 物品使用（1.32.0）：UseContainerItem——消耗品直接使用，装备自动穿上；背包未找到静默跳过
    local bag, slot = wFindBagItem(iname)
    if not bag then wlog(name .. "跳过: 背包未找到") return false end
    pcall(UseContainerItem, bag, slot)
    local iline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(iline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. iline .. "|r") end
    return true
  end
  local s = wslots[name]
  if not s then wlog(string.format("%s: %s，但技能不在动作条", name, reason)) return false end
  UseAction(s.slot)
  local line = string.format("→ %s (%s) | 怒气%d", name, reason, UnitMana("player"))
  EVAL_LOGLINE(line)
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. line .. "|r") end
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
  elseif k == "casting" then
    -- 施法中（1.38.0/1.41.0 扩：s 空=任意施法）：SPELLCAST_* 事件驱动 st.castName（1.12 无 UnitCastingInfo，只能走事件）
    local pass = (st.castName ~= nil) and ((cd.s == nil or cd.s == "") or st.castName == cd.s)
    return (pass and true or false) == (cd.v ~= false), "施法中"
  elseif k == "castEl" then
    -- 自身读条已进行秒数（1.41.0）：无读条=0
    local el = (st.castName and st.castStart) and (GetTime() - st.castStart) or 0
    return condCmp({ cd.op, cd.n }, el), "读条进行"
  elseif k == "castLeft" then
    -- 自身读条剩余秒数（1.41.0）：事件自带精确总时长，无需学习；无读条/无时长=不过
    local left = (st.castName and st.castUntil) and (st.castUntil - GetTime()) or nil
    return (left ~= nil and condCmp({ cd.op, cd.n }, math.max(0, left))), "读条剩余"
  elseif k == "tCastEl" then
    -- 目标读条已进行秒数（1.40.0）：无读条=0
    local tel = (st.tCastName and st.tCastStart) and (GetTime() - st.tCastStart) or 0
    return condCmp({ cd.op, cd.n }, tel), "读条进行"
  elseif k == "tCasting" then
    -- 目标施法中（1.40.0；1.41.0 补回：分支在施法扩展编辑中被误吃，缺分支恒 false）
    local pass = (st.tCastName ~= nil) and ((cd.s == nil or cd.s == "") or st.tCastName == cd.s)
    return (pass and true or false) == (cd.v ~= false), "目标施法中"
  elseif k == "tCastLeft" then
    -- 目标读条剩余秒数（1.40.0）：需已学习该技能总时长（castTime 学习表）；未学习=不过
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local total = (w2 and w2.castTime and st.tCastName) and w2.castTime[st.tCastName] or nil
    local tleft = (total and st.tCastStart) and (st.tCastStart + total - GetTime()) or nil
    return (tleft ~= nil and condCmp({ cd.op, cd.n }, math.max(0, tleft))), "读条剩余"
  elseif k == "inRange" then
    -- 施法范围内（1.37.0）：IsActionInRange(该技能槽位)==true 才算；0=超出 / 1=自动攻击不测距 / nil=无目标
    local s2 = wslots[cd.s or ""]
    local pass = false
    if s2 and type(IsActionInRange) == "function" then
      local okr, r = pcall(IsActionInRange, s2.slot)
      pass = (okr and r == true) and true or false
    end
    return (pass == (cd.v ~= false)), "范围内:" .. tostring(cd.s)
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
    EVAL_SAY("|cffff9040已学习免疫: " .. skill .. " @ " .. mob .. "（该目标不再尝试此技能）|r")
  end
  return true
end

-- 当前目标是否已记录免疫该技能
local function wImmuneTo(skill)
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  local im = w2 and w2.immune
  return (im and st.hasTarget and st.targetName) and im[skill .. "@" .. tostring(st.targetName)] and true or false
end

-- ===== 目标施法跟踪（1.40.0）：CHAT_MSG_SPELL_CREATURE_VS_* 文本驱动 =====
-- 开始：「X开始施放Y。」X=当前目标名 → st.tCastName/tCastStart；结束：「Y击中你/对你造成」→ 学习总时长进 war.castTime（任意施法者都学）
function EVAL_TCAST_EVENT(msg)
  if type(msg) ~= "string" then return end
  local caster, spell = string.match(msg, "(.-)开始施放(.+)。")
  if not caster then caster, spell = string.match(msg, "(.-) begins to cast (.+)%.") end
  if not caster then caster, spell = string.match(msg, "(.-) begins casting (.+)%.") end
  if caster and spell and spell ~= "" then
    if st.hasTarget and st.targetName == caster then
      st.tCastName = spell
      st.tCastStart = GetTime()
    end
    return
  end
  local sp2 = string.match(msg, "(.-)击中你造成") or string.match(msg, "(.-)对你造成") or string.match(msg, "(.-) hits you")
  if sp2 and st.tCastName == sp2 and st.tCastStart then
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    if w2 then
      if not w2.castTime then w2.castTime = {} end
      local dur = GetTime() - st.tCastStart
      if dur > 0.2 and dur < 30 then w2.castTime[sp2] = math.floor(dur * 100 + 0.5) / 100 end
    end
    st.tCastName, st.tCastStart = nil, nil
  end
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
  ["读条"] = "tCastEl", ["tCastEl"] = "tCastEl", ["读条剩"] = "tCastLeft", ["tCastLeft"] = "tCastLeft", -- 1.40.0 目标读条秒数
  ["自身读条"] = "castEl", ["castEl"] = "castEl", ["自身读条剩"] = "castLeft", ["castLeft"] = "castLeft", -- 1.41.0 自身读条秒数
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
  -- 1.40.0 目标施法中：空前缀=任意施法，带名=指定技能；未施法=取反
  if string.find(token, "^目标未施法") or string.find(token, "^tnotcasting") then return { k = "tCasting", s = nil, v = false } end
  local tct = string.match(token, "^目标施法中[:：]?(.-)$") or string.match(token, "^tcasting[:=]?(.-)$")
  if tct ~= nil then return { k = "tCasting", s = (tct ~= "" and condTrim(tct)) or nil, v = not neg } end
  local imt = string.match(token, "^免疫[:：](.+)$") or string.match(token, "^immune[:=](.+)$") -- 1.36.1 免疫条件
  if imt then return { k = "immune", s = condTrim(imt), v = not neg } end
  local imn = string.match(token, "^未免疫[:：](.+)$") or string.match(token, "^notimmune[:=](.+)$")
  if imn then return { k = "immune", s = condTrim(imn), v = false } end
  local irg = string.match(token, "^范围内[:：](.+)$") or string.match(token, "^inrange[:=](.+)$") or string.match(token, "^range[:=](.+)$") -- 1.37.0 射程条件
  if irg then return { k = "inRange", s = condTrim(irg), v = not neg } end
  local irn = string.match(token, "^范围外[:：](.+)$") or string.match(token, "^notinrange[:=](.+)$")
  if irn then return { k = "inRange", s = condTrim(irn), v = false } end
  local tg = string.match(token, "^选取目标[:：](.+)$") or string.match(token, "^target[:=](.+)$")
  local cst = string.match(token, "^施法中[:：](.+)$") or string.match(token, "^casting[:=](.+)$") -- 1.38.0 施法中条件
  if cst then return { k = "casting", s = condTrim(cst), v = not neg } end
  local csn = string.match(token, "^未施法[:：](.+)$") or string.match(token, "^notcasting[:=](.+)$")
  if csn then return { k = "casting", s = condTrim(csn), v = false } end
  if token == "施法中" or token == "casting" then return { k = "casting", s = nil, v = not neg } end -- 1.41.0 裸形式=任意施法
  if token == "未施法" or token == "notcasting" then return { k = "casting", s = nil, v = false } end
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
local COND_NUMNAME = { power = "怒气", tHpPct = "目标血", hpPct = "自身血", powerPct = "能量%", combatTime = "进战", tCastEl = "读条", tCastLeft = "读条剩", combo = "连击" }
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
  if k == "tCasting" then return (cd.v == false and "目标未施法" or "目标施法中") .. ((cd.s and cd.s ~= "") and (":" .. cd.s) or "") end -- 1.40.0
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
      if k == "casting" then return (cd.v == false and "未施法:" or "施法中:") .. tostring(cd.s) end -- 1.38.0
if k == "inRange" then return (cd.v == false and "范围外:" or "范围内:") .. tostring(cd.s) end -- 1.37.0
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
  if not w.castTime then w.castTime = {} end -- 1.40.0 目标读条总时长学习表（技能名→秒）
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
  EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
  -- 配置阈值（/eh cfg 或小地图 EH 图标可调；缺省值与原宏一致）
  local w = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war) or {} -- 1.41.1 热修：拆分后 Engine 无 cfg local（EVAL_GO 裸引用崩全局）
  if w.enabled == false then
    if GetTime() - EVAL_WLASTHINT >= 5 then
      EVAL_WLASTHINT = GetTime()
      EVAL_SAY("一键宏已禁用（/eh cfg 或小地图 EH 图标里开启）")
    end
    return
  end
  if not wscanned then EVAL_GO_RESCAN(true) end

  -- Shift+按宏 = 切换下一个方案（不施法）；也可点战斗信息UI的方案按钮或 /eh go next
  if IsShiftKeyDown and IsShiftKeyDown() then
    EVAL_WAR_ENSURE_PROFILES(w)
    if w.profiles and table.getn(w.profiles) > 1 then
      w.activeProfile = (w.activeProfile or 1) % table.getn(w.profiles) + 1
      EVAL_SAY("切换到方案: " .. tostring(w.profiles[w.activeProfile].name))
    else
      EVAL_SAY("只有一个方案，无需切换（配置窗口 一键宏设置页 [+] 新建）")
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
      EVAL_LOGLINE("→ 开启自动普攻")
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
      if GetTime() - EVAL_WLASTHINT >= 2 then
        EVAL_WLASTHINT = GetTime()
        local names = {}
        for _, p in ipairs(w.profiles) do table.insert(names, "[" .. tostring(p.name) .. "]") end
        EVAL_SAY("方案不存在: 「" .. tostring(profSel) .. "」现有方案: " .. table.concat(names, " ") .. "（注意全半角引号/名称一致；/eh go list 查看）")
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

-- 1.42.0 方案上限 12：EVAL_GO5~GO12 批量生成（5.1 循环闭包每轮新 local j 捕获）
for i = 5, 12 do local j = i _G["EVAL_GO" .. j] = function() EVAL_GO(j) end end
-- /eh war 的状态总览
function EVAL_GO_STATUS()
  if not wscanned then EVAL_GO_RESCAN(true) end
  EVAL_SAY("— 一键宏状态 —")
  for _, n in ipairs(WAR_SKILLS) do
    local s = wslots[n]
    if s then
      local ready, why = wready(n)
      EVAL_SAY(string.format("%s: 格子%d %s", n, s.slot, ready and "|cff00ff00就绪|r" or ("|cffff9040" .. tostring(why) .. "|r")))
    else
      EVAL_SAY(n .. ": |cffff0000未上动作条|r")
    end
  end
  EVAL_SAY("当前: " .. formatStats(collectStats()))
end

-- ===== 跨模块导出（EvalHelp.lua 的 UI 层用） =====
EVAL_WSLOTS = wslots
EVAL_WICON = wicon
EVAL_GROUPS_OK = groupsOK
EVAL_AURA_TEX = auraTexOf
EVAL_PET_OF = petCmdOf
EVAL_TGT_OF = targetSelOf
EVAL_ITEM_OF = itemOf
EVAL_TARGET_SEL = TARGET_SEL
EVAL_TSEL_NAME = TARGET_SEL_NAME
EVAL_CLASS_LIST = CLASS_LIST
EVAL_WAR_SKILLS = WAR_SKILLS
EVAL_COND_TRIM = condTrim
EVAL_P_HASBUFF = wPlayerHasBuff
EVAL_T_HASDEBUFF = wTargetHasDebuff
EVAL_IS_SCANNED = function() return wscanned end
