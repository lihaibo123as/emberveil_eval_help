-- EvalHelp · Engine.lua —— 一键宏引擎：动作条扫描/技能五分类/规则引擎/条件解析/免疫学习/光环学习/距离分档
-- 依赖 Core.lua 导出；状态读 EVAL_HELP_STATE

local st = EVAL_HELP_STATE
local L = EVAL_L
local formatStats, collectStats = EVAL_FORMAT_STATS, EVAL_COLLECT_STATS -- 1.41.2 拆分漏桥补

-- ============ 一键输出引擎（规则引擎驱动，全职业通用） ============
-- 宏入口：/run EVAL_GO() —— 每次按键只做一个动作（同键多行动作会互抢 GCD）。
-- 技能清单一切以动作条扫描为准（1.48.0 战士白名单已清零）：把技能拖上动作条 → /eh go rescan 或配置窗[重扫]。
-- 技能识别走 tooltip 技能名（不依赖图标名拼写）；buff/debuff 用「动作条图标 == 光环图标」比对。
-- 调试：/eh go 看识别结果和当前状态；/eh go rescan 重扫；/eh debug 开关详细日志。
-- 所有出手动作都会写入调试日志（SavedVariables 环形缓冲，/eh logdump 查看），连按不刷屏也能事后复盘。

local WAR_MAX_SLOT = 119
-- 1.48.0 清理：WAR_SKILLS 战士白名单已删除——技能清单一切以动作条扫描（wslots）为准，真·全职业
local WTT = GameTooltip -- 识别动作条技能用
local wslots = {}       -- 技能名 -> { slot, tex }
local wscanned = false
local wLastAttackTry = 0

-- 详细日志：/eh wdebug 开启后刷聊天框，同时总是写调试日志缓冲
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
  -- 1.46.0 修复：原地清空而不是重新赋值——EVAL_WSLOTS 导出的是表引用（EvalHelp.lua 顶部别名持有），
  -- 重新赋值会让外部引用指向旧空表（重扫后 UI 读 wslots 全 nil、图标行全 ?）
  if wslots then for k in pairs(wslots) do wslots[k] = nil end else wslots = {} end
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
    EVAL_SAY(string.format("动作条共识别 |cff00ff00%d|r 个技能（均可用于方案/条件）", total))
    -- 1.45.0 核对清单以激活方案技能为准（旧版固定战士白名单核对已废弃；
    -- petCmdOf 等 local 声明在本函数之后 → 走全局导出，调用期取值）
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local p = w2 and w2.profiles and w2.profiles[w2.activeProfile or 1]
    if p and p.skills and table.getn(p.skills) > 0 then
      EVAL_SAY("激活方案「" .. tostring(p.name) .. "」技能核对↓")
      for _, r in ipairs(p.skills) do
        local n = r.skill
        local special = (EVAL_PET_OF and EVAL_PET_OF(n)) or (EVAL_TGT_OF and EVAL_TGT_OF(n)) or (EVAL_STANCE_OF and EVAL_STANCE_OF(n)) or (EVAL_ITEM_OF and EVAL_ITEM_OF(n)) or n == "取消施法"
        if special then
          EVAL_SAY(n .. " → |cff80ff80特殊技能（不占动作条）|r")
        else
          local s = wslots[n]
          EVAL_SAY(string.format("%s → %s", n, s and ("格子 " .. s.slot) or "|cffff0000未找到|r（拖上动作条后重扫）"))
        end
      end
    else
      EVAL_SAY("（激活方案暂无技能：/eh cfg → 一键宏设置 → 添加技能）")
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
  -- 1.49.2 参照技能多职业化（旧版纯战士：断筋/冲锋）：近战技=战/贼/猎/骑/德常见近战；突进技=冲锋/拦截/野性冲锋
  local melee
  for _, n in ipairs({ "断筋", "压制", "撕裂", "英勇打击", "猛击", "斩杀", "背刺", "脚踢", "猛禽一击", "审判", "撕碎" }) do
    melee = inRange(n)
    if melee ~= nil then break end
  end
  if melee == true then return "近战" end
  local charge
  for _, n in ipairs({ "冲锋", "拦截", "野性冲锋" }) do
    charge = inRange(n)
    if charge ~= nil then break end
  end
  if charge == true then return "冲锋距" end
  if melee == false or charge == false then return "远程外" end
  return nil
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
  -- ★★1.70.47 队伍/团队**自动扫描**选取（用户需求定案，原话）：
  --   「新增行为类型 选取目标: - 队伍成员 - 团队成员」，自动实施扫描。
  --   ★它是**成员扫描器 + 过滤器**，两件事都做：
  --     ① 扫描（队伍 = 自己 + party1..N；团队 = raid1..N）
  --     ② 用**这一行自己的条件列表**逐个候选过滤（用户示例：目标血量<N% / 目标buff:名 / 目标debuff:名）
  --     ③ 命中者 TargetUnit 过去，并记入 **st.allyUnit**（后续技能行的 UseAction 就打在他身上）
  --   ★候选顺序 = 血量百分比升序（最危险优先）→ 天然满足「扫描全员取最低」。
  --   ★为什么过滤要**切过去再判定**：条件里的「目标血量/目标buff/目标debuff」读的是 st 里的
  --     当前目标数据；只有真的切过去 + 刷新状态，那些条件才是**真的**在判定这个候选
  --     （不切就只能靠扫描记录猜，职业/类型/精英类条件根本答不出来）。代价 = ≤队伍人数 次切换，
  --     且**按需**发生（没配条件就不切），符合频率防护总则。
  --   ★teamSel = true：执行时**跳过常规条件预判**（那些条件是对「当前目标」说的，对扫描器无意义），
  --     直接进 wuse → EVAL_TEAM_PICK 按候选逐个判定（见 EVAL_RULE_RUN 的 teamSel 分支）。
  { id = "teamParty", name = "队伍成员", fn = "EVAL_TEAM_PICK", arg = "auto", teamSel = "party" },
  { id = "teamRaid",  name = "团队成员", fn = "EVAL_TEAM_PICK", arg = "auto", teamSel = "raid" },
}
local TARGET_SEL_NAME, TARGET_SEL_ID, TARGET_SEL_FN, TARGET_SEL_ARG = {}, {}, {}, {}
local TARGET_SEL_TEAMSEL = {} -- 扫描范围（"party"/"raid"）；非成员选取器为 nil
for _, t in ipairs(TARGET_SEL) do
  TARGET_SEL_NAME[t.id] = t.name
  TARGET_SEL_ID[t.name] = t.id
  TARGET_SEL_ID[t.id] = t.id
  TARGET_SEL_FN[t.id] = t.fn
  TARGET_SEL_ARG[t.id] = t.arg
  if t.teamSel then TARGET_SEL_TEAMSEL[t.id] = t.teamSel end
end

-- ★1.70.47 dispel（可驱散）类型表：id 是**入库/文本用的稳定英文 token**（来自客户端 UnitDebuff 第三返回的同一套），
--   loc 是中文显示名。★客户端返回值可能是**本地化名**（中文客户端 tooltip 显示「魔法」）也可能是英文 token，
--   故匹配一律走 dispelMatch 双向容忍（与 1.70.28 目标类型「带后缀的本地化名」同一类教训）。
local DISPEL_TYPES = {
  { id = "Magic",   tok = "Magic",   loc = "魔法" },
  { id = "Curse",   tok = "Curse",   loc = "诅咒" },
  { id = "Poison",  tok = "Poison",  loc = "毒" },
  { id = "Disease", tok = "Disease", loc = "疾病" },
}
EVAL_DISPEL_TYPES = DISPEL_TYPES -- 全局桥：编辑窗下拉与断言共用同一份

local function dispelMatch(actual, want)
  if want == nil or want == "" or want == "any" then return true end -- 未指定类型 = 任意
  if type(actual) ~= "string" or actual == "" then return false end
  local a, w = string.lower(actual), string.lower(want)
  if a == w then return true end
  -- 客户端可能返回本地化名/带修饰的长串 → 双向包含兜底
  if string.find(a, w, 1, true) or string.find(w, a, 1, true) then return true end
  -- 英文 token ↔ 本地化标签 互认
  for _, t in ipairs(DISPEL_TYPES) do
    local tl, tt = string.lower(t.loc), string.lower(t.tok)
    if (w == tl or w == tt) and (a == tl or a == tt) then return true end
  end
  return false
end

-- 把用户写的类型（英文 token 或中文标签 / 大小写不一）归一成**入库用的英文 id**；不认识就原样返回
local function dispelNorm(want)
  if type(want) ~= "string" then return nil end
  local w = string.lower(string.gsub(want, "^%s*(.-)%s*$", "%1"))
  if w == "" then return nil end
  if w == "any" then return "any" end
  for _, t in ipairs(DISPEL_TYPES) do
    if w == string.lower(t.tok) or w == string.lower(t.loc) then return t.id end
  end
  return want
end

-- 解析「名字(类型)」/「名字」/「类型」三种写法（导入侧宽松；类型单独写时归一到英文 id）
local function dispelSplit(s)
  s = string.gsub(s or "", "^%s*(.-)%s*$", "%1")
  local open, close = string.find(s, "%("), string.find(s, "%)%s*$")
  if open and close and close > open then
    local nm = string.gsub(string.sub(s, 1, open - 1), "^%s*(.-)%s*$", "%1")
    local dt = string.gsub(string.sub(s, open + 1, close - 1), "^%s*(.-)%s*$", "%1")
    if nm == "" then nm = nil end
    return nm, dispelNorm(dt)
  end
  -- 没有括号：整串若是一个 dispel 类型，就当作「类型」；否则当作「名称」
  local norm = dispelNorm(s)
  for _, t in ipairs(DISPEL_TYPES) do
    if norm == t.id then return nil, t.id end
  end
  if s == "" then return nil, nil end
  return s, nil
end

-- ★1.70.47 队伍成员扫描选取的**内部判据**（只被 EVAL_TEAM_PICK 用；用户看不到，也不必看到）：
--   hpLow   = 血量%最低者（满血也会被选中，交给后续「队伍血量<X%」条件把关）
--   manaLow = 蓝量%最低者（**只考虑有蓝职业**：UnitPowerType 非 0 的成员跳过）
--   buff:名 / buff:名(层数) = 身上有该 buff 的**层数最少**者（缺这个 buff 的优先，用于补 buff）
--   debuff:类型[:名称] = 身上有该类型（或该名称）负面效果的第一个成员
-- ★判据在 auto 模式下由「同一条规则里已有的队伍条件」反推（见 teamCriteriaFor）。
--   teamPickArg 是 condOne → EVAL_TEAM_PICK 的**传参通道**（Lua 只能按位置传参，而执行路径是 pcall(fn, arg)）；
--   TARGET_SEL_ARG_LAST 记「这次点的是 队伍 还是 团队」，决定扫描范围。
local teamPickArg = { arg = "hpLow" }
local TARGET_SEL_ARG_LAST = nil

-- ★1.70.47 前置声明：groupsOK（条件组求值）在文件后半段才实现，但「选取目标:队伍成员」的
--   **候选过滤**要用它（对每个候选跑一遍这一行自己的条件列表）。Lua 词法作用域 → 必须先声明。
local groupsOK

-- ★1.70.47 前置声明：auraTexOf 的**真正实现**在下面（光环名→纹理，动作条优先/学习表回退）。
--   本段（队伍选人判据）在它之前就要用「buff 名 → 纹理」做比对，而 Lua 只认**词法**作用域：
--   不前置声明的话，这里的 auraTexOf 会解析成**全局 nil** → 一按队伍buff 条件就红字报错。
--   ★这正是本项目累计十几次的同一类坑；DECL ORDER CHECK 这次**没抓到**（它只扫
--     「顶层 local 声明 vs 使用」，而这里的问题是「使用了下面才声明的东西」——
--     检查方向需要覆盖「同一文件内、引用点早于声明点」的相互次序，已记入待办）。
local auraTexOf
local function teamPickBest(list, crit, bufTex, bufNeed, debTex, debWant)
  local best, bestKey = nil, nil
  for _, r in ipairs(list) do
    if crit == "hpLow" then
      if r.hpMax > 0 and (bestKey == nil or r.hpPct < bestKey) then best, bestKey = r, r.hpPct end
    elseif crit == "manaLow" then
      local isMana = (r.powerType == nil or r.powerType == 0)
      if isMana and r.powerMax > 0 and (bestKey == nil or r.powerPct < bestKey) then best, bestKey = r, r.powerPct end
    elseif crit == "buff" then
      -- 补 buff 语义：优先选**缺这个 buff**（或层数不足）的成员；都齐了就退化为血量最低者
      local cnt = bufTex and r.buffs[bufTex] or nil
      cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
      if cnt < bufNeed then
        local key = cnt -- 层数越少越优先；同层数再比血量
        if bestKey == nil or key < bestKey or (key == bestKey and r.hpPct < (best.hpPct or 999)) then
          best, bestKey = r, key
        end
      end
    else -- debuff
      local hit, hitCnt = false, 0
      if debTex then
        local d = r.debuffs[debTex]
        if d and dispelMatch(d.t, debWant) then hit = true hitCnt = tonumber(d.n) or 1 end
      else
        for _, d in pairs(r.debuffs) do
          if dispelMatch(d.t, debWant) then hit = true hitCnt = tonumber(d.n) or 1 break end
        end
      end
      if hit and (bestKey == nil or hitCnt > bestKey) then best, bestKey = r, hitCnt end
    end
  end
  return best
end

-- ★1.70.47 已删除「按同一规则里的队伍条件反推判据」那套（teamCriteriaFor）。
--   为什么删：用户需求定案后，「挑选谁」改由**选取器那一行自己的条件列表**逐候选过滤
--   （见 EVAL_TEAM_PICK 的 ① 分支）——那比「反推判据」更直接、更可预测，也支持任意条件组合。
--   反推那套就只剩「无规则时默认血量最低」，一行足矣。★前提被取代的机制要删掉，别留着空转。

-- ★1.70.47 队伍成员自动扫描选取（用户要求）。
--   crit="auto"：判据由**同一条规则里的队伍条件**反推（见 teamCriteriaFor）——这就是「选取目标:队伍」的全部行为
--   选中后：设 st.teamCur（队伍/团队条件按它求值）+ TargetUnit(unit)（后续技能行 UseAction 就打在它身上）。
-- ★为什么要切目标：CastSpellByName/SpellTargetUnit 在本客户端**都是 Protected**，插件无法直接指定施法对象；
--   TargetUnit 非 Protected，所以「切目标 → 用技能 → 还原」是唯一可行路径（见 CLAUDE.md F2 节）。
-- ★频率防护：整个扫描只在这里发生一次（按宏那一轮），UPDATE_STATE 绝不扫描。
-- 候选按血量百分比升序（最危险优先）——「扫描全员取最低」的自然顺序
local function teamSortByHp(list)
  local out = {}
  for i = 1, table.getn(list) do out[i] = list[i] end
  table.sort(out, function(a, b) return (a.hpPct or 0) < (b.hpPct or 0) end)
  return out
end

-- 记下「这一次按键选中的队友」：后续技能行的 UseAction 就打在他身上
local function teamSelect(rec)
  st.allyUnit = rec and rec.unit or nil
  st.teamCur = rec
  if rec and type(TargetUnit) == "function" then pcall(TargetUnit, rec.unit) end
  return rec and rec.unit or nil
end

function EVAL_TEAM_PICK(crit)
  -- 叫「队伍成员」就只扫队伍，叫「团队成员」就扫团队
  local scope = (TARGET_SEL_ARG_LAST == "teamRaid") and "raid" or "party"
  local list = EVAL_HELP_TEAM_ENSURE and EVAL_HELP_TEAM_ENSURE(scope) or nil
  if not list or table.getn(list) == 0 then st.teamCur, st.allyUnit = nil, nil return nil end

  -- ① 有规则（「选取目标:队伍成员」技能行）→ **按这一行自己的条件逐个候选过滤**
  local rule = teamPickArg.rule
  if rule then
    -- ★原目标要尽量**精确**记住：优先用 UnitIsUnit 反查出它的 unit id（还原最可靠）；查不到才退化为按名字。
    --   ★为什么不能只靠名字：文档（Targetting#targetbyname）明确 TargetByName 只认**附近**单位——
    --     原目标在远处时按名字还原会**静默失败**，目标就丢在最后一个候选身上了。
    --   （UnitIsUnit 文档：相同返回 true，不同返回 **nil**（绝不 false）→ 判定只能看真值，不能 == true）
    local origName = (st.hasTarget and st.targetName) and st.targetName or nil
    local origUnit = nil
    if origName and type(UnitIsUnit) == "function" then
      for _, rec in ipairs(list) do
        if UnitIsUnit("target", rec.unit) then origUnit = rec.unit break end
      end
    end
    local sorted = teamSortByHp(list)
    for _, rec in ipairs(sorted) do
      if type(TargetUnit) == "function" then pcall(TargetUnit, rec.unit) end
      if EVAL_HELP_UPDATE_STATE then pcall(EVAL_HELP_UPDATE_STATE) end
      local ok = groupsOK(rule, false)
      if ok then return teamSelect(rec) end
    end
    -- 全员都不满足 → **还原原目标**（诚实：不把目标丢在最后一个候选身上就算完）
    if origUnit then
      pcall(TargetUnit, origUnit) -- 精确还原（原目标就是某个队友/自己）
    elseif origName then
      pcall(TargetByName, origName) -- 仅对附近单位有效；失败时下面这条日志会如实说明
      wlog("队伍选取: 没选到成员；已尝试按名字还原目标「" .. tostring(origName) .. "」(TargetByName 只认附近单位)")
    else
      pcall(ClearTarget) -- 本来就没有目标 → 还原成「无目标」
    end
    if EVAL_HELP_UPDATE_STATE then pcall(EVAL_HELP_UPDATE_STATE) end
    st.teamCur, st.allyUnit = nil, nil
    return nil
  end

  -- ② 无规则：按判据直接挑（测试直调 / 内部复用）
  local bufTex, bufNeed, debTex, debWant = nil, 1, nil, nil
  if crit == "auto" or crit == nil then
    crit = "hpLow" -- 无规则可过滤时的默认：血量最低（治疗场景最保守的选择）
  elseif crit == "buff" then
    bufTex, bufNeed = teamPickArg.tex, (teamPickArg.n or 1)
  elseif crit == "debuff" then
    debTex, debWant = teamPickArg.tex, teamPickArg.dt
  end
  local best = teamPickBest(list, crit, bufTex, bufNeed, debTex, debWant)
  -- 补 buff 场景下若全队都有该 buff → 退化为血量最低者（仍选一个人出来，别空手）
  if not best and crit == "buff" then best = teamPickBest(list, "hpLow") end
  if not best then st.teamCur, st.allyUnit = nil, nil return nil end
  return teamSelect(best)
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

-- 姿态切换（1.43.0）：rule.skill="姿态:战斗姿态"——走姿态栏 CastShapeshiftForm（官方文档明确 Not protected，插件可直调），
-- 不占动作条。战士姿态不可取消（重复按 no-op）；德鲁伊等可切换形态重复按会取消 aura → 执行前 active 守门。
local function stanceOf(skill)
  return string.match(skill or "", "^姿态[:：](.+)$")
end
-- 姿态名或序号（"姿态:2" 1.47.0 起兼容）→ 姿态栏 1 基索引, 图标, 当前激活(1/nil), 可用(1/nil)；未找到/无姿态栏返回 nil
local function wFindStance(name)
  if type(GetNumShapeshiftForms) ~= "function" then return nil end
  local okn, n = pcall(GetNumShapeshiftForms)
  if not (okn and n and n > 0) then return nil end
  local idx = tonumber(name) -- 序号直取（"姿态:2"=姿态栏第 2 格）
  if idx and idx >= 1 and idx <= n then
    local oki, icon, nm, active, castable = pcall(GetShapeshiftFormInfo, idx)
    if oki and nm then return idx, icon, active, castable end
    return nil
  end
  for i = 1, n do
    local oki, icon, nm, active, castable = pcall(GetShapeshiftFormInfo, i)
    if oki and nm and nm == name then return i, icon, active, castable end
  end
  return nil
end

-- 取消施法（1.47.0 特殊行为）：rule.skill="取消施法"——SpellStopCasting 打断自己当前读条（wiki Spell 分类），
-- 不占动作条；典型用途：读条被打/需要立刻转身逃跑时配条件触发。
local function cancelCastOf(skill)
  if skill == "取消施法" then return true end
  return nil
end

-- 技能图标统一入口（1.30.0）：动作条纹理 → 宠物指令回退（宠物头像/问号）
local function wicon(name)
  local s = wslots[name]
  if s and s.tex then return s.tex end
  local pc2 = petCmdOf(name)
  if pc2 then return petIconOf(pc2) end -- 1.32.6 宠物指令专属图标（动作条学习）
  if targetSelOf(name) then return "Interface\\Icons\\INV_Misc_QuestionMark" end -- 1.32.0 选取目标无专属图标
  if cancelCastOf(name) then return "Interface\\Icons\\INV_Misc_QuestionMark" end -- 1.47.0 取消施法无专属图标
  local stname = stanceOf(name) -- 1.43.0 姿态：GetShapeshiftFormInfo 图标（激活态自动亮纹）
  if stname then
    local _si, stex = wFindStance(stname)
    if stex then return stex end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
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
-- ★注意这里是**给上面已前置声明的 local 赋值**（不是新建 local）——改了会连带断掉
--   队伍选人判据那边的引用（它们在声明点之前，只能看到前置声明的那个 local）。
function auraTexOf(n)
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

-- 通用光环实时清单（1.54.0）：unit="target"/"player"，harmful=true=debuff / false=buff
local function wScanAuras(unit, harmful)
  local list = {}
  if not UnitExists(unit) then return list end
  local api = harmful and UnitDebuff or UnitBuff
  local ttm = WTT and (harmful and WTT.SetUnitDebuff or WTT.SetUnitBuff)
  if type(api) ~= "function" or not ttm then return list end
  pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  for i = 1, 16 do
    local okd, tex = pcall(api, unit, i)
    if not okd or not tex then break end
    local name
    pcall(function() WTT:ClearLines() end)
    local oks = pcall(ttm, WTT, unit, i) -- 1.33.2 探针实测：返回值恒 nil 但 tooltip 已填充
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
function EVAL_TARGET_BUFF_LIST() return wScanAuras("target", false) end -- 目标 buff（1.54.0）
function EVAL_PLAYER_DEBUFF_LIST() return wScanAuras("player", true) end -- 自身 debuff（1.54.0）

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
  local stname2 = stanceOf(name) -- 1.43.0 姿态冷却走姿态栏 API；已在该姿态=不就绪（防止德鲁伊形态被再按取消）
  if stname2 then
    local si, _t, active, castable = wFindStance(stname2)
    if not si then return false, "无该姿态栏位" end
    if active then return false, "已在该姿态" end
    if not castable then return false, "不可用" end
    if type(GetShapeshiftFormCooldown) == "function" then
      local okc, start, dur = pcall(GetShapeshiftFormCooldown, si)
      if okc and (start or 0) > 0 and (dur or 0) > 0 then
        local left = start + dur - GetTime()
        if left > 0 then return false, string.format("冷却剩 %.1fs", left) end
      end
    end
    return true
  end
  if cancelCastOf(name) then -- 1.47.0 取消施法：仅在读条/引导中有意义
    if st.castName or (st.castUntil and st.castUntil > GetTime()) then return true end
    return false, "未在施法"
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
    elseif TARGET_SEL_ARG[ts] then
      -- ★1.70.47 技能行也可以直接是「选取目标:队伍成员/团队成员」（用户在技能下拉的分类里加）。
      --   这条路径**不经过 condOne**，所以必须同样把范围传下去——否则团队会被当成队伍扫。
      --   ★★teamPickArg.rule 由**调用方**负责：EVAL_RULE_RUN 的成员选取器分支会先把整条规则放进去
      --     （那是候选过滤条件），condOne 的 target 分支也会。这里**绝不能清掉它**——
      --     清掉就等于「过滤器失效」，扫描器会退化成「无脑选血量最低」，而且**静默**（不报错）。
      TARGET_SEL_ARG_LAST = ts
      pcall(fn, TARGET_SEL_ARG[ts])
      TARGET_SEL_ARG_LAST = nil
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
  local stname3 = stanceOf(name)
  if stname3 then
    -- 姿态切换（1.43.0）：CastShapeshiftForm 不受保护；已在该姿态时跳过（战士姿态 no-op，德鲁伊形态会被取消——必须守门）
    local si, _t, active = wFindStance(stname3)
    if not si then wlog(name .. "跳过: 无该姿态栏位") return false end
    if active then wlog(name .. "跳过: 已在该姿态") return false end
    if type(CastShapeshiftForm) ~= "function" then wlog(name .. ": 无姿态切换函数") return false end
    pcall(CastShapeshiftForm, si)
    local sline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(sline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. sline .. "|r") end
    return true
  end
  if cancelCastOf(name) then
    -- 取消施法（1.47.0）：未在读条时静默跳过（条件里建议配 施法中:X）。
    -- 1.49.3 修复：SpellStopCasting 本客户端【Protected】（wiki 原文：addons cannot call this），插件直调静默无效
    -- → 改走 RunScript("SpellStopCasting()")：排队为 pending script，与聊天框 /run 同执行路径（wiki 明确无 Protected 标注）
    if not (st.castName or (st.castUntil and st.castUntil > GetTime())) then wlog(name .. "跳过: 未在施法") return false end
    if type(RunScript) == "function" then
      pcall(RunScript, "SpellStopCasting()")
    elseif type(SpellStopCasting) == "function" then
      pcall(SpellStopCasting) -- 兜底：无 RunScript 的老环境直调
    else
      wlog(name .. ": 无取消施法通道") return false
    end
    local cline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(cline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. cline .. "|r") end
    return true
  end
  local s = wslots[name]
  if not s then wlog(string.format("%s: %s，但技能不在动作条", name, reason)) return false end
  UseAction(s.slot)
  local line = string.format("→ %s (%s) | %s%d", name, reason, (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), UnitMana("player")) -- 1.49.2 怒气硬编码→动态（法力/怒气/集中值）
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
    if not s then return false, "不可用" end
    -- 1.64.0 修多返回截断：s and pcall(...) 是逻辑表达式，只取 pcall 第一返回值——usable/noMana 恒 nil
    local oku, usable, noMana = pcall(IsUsableAction, s.slot)
    if not (oku and (usable or not noMana)) then return false, noMana and "不可用:资源不足" or "不可用" end -- 1.64.0 只信资源信号
  end
  if when.notQueued then
    local s = wslots[skill]
    if s then
      local okq, q = pcall(IsCurrentAction, s.slot) -- 1.64.0 修多返回截断（q 恒 nil）
      if okq and q then return false, "已排队" end
    end
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

-- ===== 目标类型条件（1.70.28）：UnitCreatureType 比对 =====
-- 该 API 在**本客户端曾被记为不可靠**（旧版拿它推断「不能流血」导致黑暗犬误判）。
-- 但那条结论针对的是「类型→可否流血」的**推断**，不等于返回值本身是垃圾；
-- 且此前它只用于调试串，从未参与判定，所以一直没有可信的实测数据。
-- 因此这里的设计原则是「**假设可能不准，但绝不静默失败**」：
--   · id 稳定存进条件；loc=中文显示名；tok=英文 token（enUS 客户端返回英文）
--   · 匹配时**同时**比对本地化名与英文 token（大小写不敏感），两种语言都认
--   · 另外接受 "other" 兜底项，用户可显式匹配「未列出的类型」
--   · 编辑器顶部会显示客户端**此刻真实报告**的类型，让不准的地方立刻可见
local CREATURE_TYPES = {
  { id = "beast",       loc = "野兽",   tok = "Beast" },
  { id = "dragonkin",   loc = "龙类",   tok = "Dragonkin" },
  { id = "demon",       loc = "恶魔",   tok = "Demon" },
  { id = "elemental",   loc = "元素",   tok = "Elemental" },
  { id = "giant",       loc = "巨人",   tok = "Giant" },
  { id = "undead",      loc = "亡灵",   tok = "Undead" },
  { id = "humanoid",    loc = "人型",   tok = "Humanoid" },
  { id = "critter",     loc = "小动物", tok = "Critter" },
  { id = "mechanical",  loc = "机械",   tok = "Mechanical" },
  { id = "notpecified", loc = "未指定", tok = "Not specified" },
  { id = "totem",       loc = "图腾",   tok = "Totem" },
  { id = "other",       loc = "其他",   tok = "Other" },
}
-- 归一化：把客户端返回的字符串映射到 id。
-- ★1.70.28 关键：本客户端返回的本地化名**可能带后缀**——测试桩里记录的是「人型生物」，
--   而 1.12 的标准名是「人型」。若只按标准名比对，「人型」永远匹配不上而**静默失效**。
--   故这里同时比对「原串」与「去掉 生物/类/型/系 词尾后的核心」，并保留英文 token 通路。
local function creatureKey(s)
  if type(s) ~= "string" then return nil end
  return string.lower(string.gsub(s, "%s+", ""))
end
-- 去词尾「生物」用于宽松匹配。
-- ★只剥离「生物」这一个词尾，**绝不能把「型/类/系」也当后缀**——
--   它们是名字本身的组成部分（「人型」「龙类」「机械」这类名字被剥掉尾字就变成了「人」「龙」），
--   会导致「人型」→「人」而「人型生物」→「人型」，两边永远对不上（本功能的核心静默失效点）。
local CREATURE_SUFFIX = "生物"
local function creatureCore(s)
  local k = creatureKey(s)
  if not k then return nil end
  local n = string.len(CREATURE_SUFFIX)
  if string.len(k) > n and string.sub(k, -n) == CREATURE_SUFFIX then
    k = string.sub(k, 1, string.len(k) - n)
  end
  return k
end
local function creatureTypeId(raw)
  local key = creatureKey(raw)
  if not key or key == "" then return nil end
  local core = creatureCore(raw)
  for _, c in ipairs(CREATURE_TYPES) do
    -- 精确匹配：本地化全名 / 英文 token
    if creatureKey(c.loc) == key or creatureKey(c.tok) == key then return c.id end
    -- 宽松匹配：去词尾后的核心（「人型生物」↔「人型」；「元素生物」↔「元素」）
    if core and (creatureCore(c.loc) == core or creatureCore(c.tok) == core) then return c.id end
  end
  return nil -- 未列出：由调用方决定是否算 "other"
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
local function condOne(cd, skill, dry, rule)
  local k = cd.k
  local function texOf(n) return auraTexOf(n) end -- 动作条 + 学习表回退（1.27.0）
  -- ★1.70.45 自身光环「剩余时间检查」（cd.secOp / cd.secN，单位秒）。
  --   只在**光环确实存在**时才参与判定：于是「无buff:奥术智慧[<30s]」= 没有 或 快到期（正是「该补了」）。
  --   left == 0：wiki（globals/Buff）明确「越界/空槽/无限/无结束时间都返回 0」→ 视作**永不到期**，
  --   只有 > / >= 才算满足。若把 0 当「0 秒」，<N 会恒真 → 每次求值都判「该补」→ 无脑重施。
  local function auraTimeCmp(cd, tbl)
    local tex = texOf(cd.s)
    if not tex then return false, "未知光环" end
    local left = tbl and tbl[tex] or nil
    if type(left) ~= "number" then return false, "无剩余时间数据" end
    if left <= 0 then
      local inf = (cd.secOp == ">" or cd.secOp == ">=")
      return inf, "剩余时间无限"
    end
    return condCmp({ cd.secOp, cd.secN }, left), "剩余" .. tostring(left) .. "s"
  end
  -- ★1.70.45 把剩余时间检查并入光环判定的**唯一**入口（自身 buff / 自身 debuff 共用）。
  --   语义（v 决定方向，这正是「刷新」用法的核心）：
  --     · v=true （有buff）：必须「有」**且**剩余满足比较；
  --     · v=false（无buff）：没有 **或** 剩余满足比较 —— 于是
  --       「无buff:奥术智慧[<30s]」= 没有 或 快到期 → 正是「该补了」。
  --     · 光环不存在时不查时间（没有东西可查）：v=false 直接判真（该补），v=true 已判假。
  --   ★我第一版把 v=false 时「有 buff 但时间满足」也判成假（因为「有≠无」先短路了），
  --     被用例 (2) 当场抓到——注释写对了、代码没写对，是测试把它逼出来的。
  local function auraTimeJudge(cd, has, okv, tbl, label)
    if type(cd.secN) ~= "number" or not has then return okv, nil end
    local okT, why = auraTimeCmp(cd, tbl)
    if cd.v == false then
      if okT then return true, nil end
      return false, label .. "剩余时间不符(" .. tostring(why) .. ")"
    end
    if not okT then return false, label .. "剩余时间不符(" .. tostring(why) .. ")" end
    return okv, nil
  end
  if k == "combat" then return (st.inCombat == cd.v), "战斗状态"
  elseif k == "combatTime" then return condCmp({ cd.op, cd.n }, st.combatTime), "进战时间"
  elseif k == "combo" then return condCmp({ cd.op, cd.n }, st.combo or 0), "连击点"
  elseif k == "hpPct" then return condCmp({ cd.op, cd.n }, st.hpPct), "自身血%"
  elseif k == "power" then return condCmp({ cd.op, cd.n }, st.power), "能量"
  elseif k == "powerPct" then return condCmp({ cd.op, cd.n }, st.powerPct), "能量%"
  elseif k == "tHpPct" then return condCmp({ cd.op, cd.n }, st.tHpPct), "目标血%"
  elseif k == "swingLeft" then -- 1.57.0 距下次攻击秒数（挥击计时；无数据=不满足）
    local rem = EVAL_SWING_REMAIN()
    if rem == nil then return false, "无攻击计时数据" end
    return condCmp({ cd.op, cd.n }, rem), "距攻击"
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
  -- 1.51.0 自动射击/魔杖射击 激活状态（直查 IsCurrentAction，同 usable 惯例；未上条=未激活）
  elseif k == "autoShot" or k == "wandShoot" then
    local sn = (k == "autoShot") and "自动射击" or "射击"
    local s = wslots[sn]
    local cur = false
    if s and type(IsCurrentAction) == "function" then
      local okc, c2 = pcall(IsCurrentAction, s.slot)
      cur = okc and c2 and true or false
    end
    return (cur == (cd.v ~= false)), sn
  elseif k == "hasBuff" then -- 1.54.0 合并：v=false=无buff（旧 k=noBuff 仅兼容存量数据）；1.70.1 层数门槛 cd.n
    local cnt = st.playerBuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0) -- 兼容旧布尔/新层数
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    local okv, whyT = auraTimeJudge(cd, has, (has == (cd.v ~= false)), st.playerBuffLeft, "自身buff")
    if not okv then return false, whyT or "自身buff判定不符" end
    return true, "自身buff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "noBuff" then return (not st.playerBuffs[texOf(cd.s) or ""]), "已有buff:" .. tostring(cd.s)
  elseif k == "tBuff" then -- 1.54.0 目标 buff 检查（v=false=无目标buff）；1.70.1 层数门槛
    -- ★1.70.45 目标光环**没有**时长 API（wiki globals/Buff：其他单位只有 UnitBuff/UnitDebuff = 图标+层数）。
    --   带剩余时间检查时如实返回 false —— 不忽略它（忽略 = 写了却不生效，属静默失败）。
    if type(cd.secN) == "number" then return false, "目标buff无剩余时间数据" end
    local cnt = st.targetBuffs and st.targetBuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    return (has == (cd.v ~= false)), "目标buff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "pDebuff" then -- 1.54.0 自身 debuff 检查（v=false=无自身debuff）；1.70.1 层数门槛
    local cnt = st.playerDebuffs and st.playerDebuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    local okv, whyT = auraTimeJudge(cd, has, (has == (cd.v ~= false)), st.playerDebuffLeft, "自身debuff")
    if not okv then return false, whyT or "自身debuff判定不符" end
    return true, "自身debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "hasDebuff" then
    -- ★1.70.45 同 tBuff：目标光环无时长数据 → 带剩余时间检查时如实 false
    if type(cd.secN) == "number" then return false, "目标debuff无剩余时间数据" end
    -- 1.54.0 合并：v=false=无debuff（不足 lim 层才算无，与旧 noDebuff 同语义）；层数门槛 cd.n（1.31.0）
    local cnt = st.targetDebuffs[texOf(cd.s) or ""]
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0) -- 兼容旧布尔/新层数
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    return (has == (cd.v ~= false)), "目标debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
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
    if not s then return false, "可用性" end
    -- 1.64.0 修多返回截断：旧写法 s and pcall(...) 是逻辑表达式，只取 pcall 第一返回值——
    -- u/noMana 恒 nil，可用性条件自引入起恒 false（测试只覆盖显示路径没覆盖执行路径才漏网）。
    -- 另：本客户端 usable 第一返回走缓存态误报率高（冲锋/撕裂实际可放仍 false），
    -- 只信第二返回 noMana=「资源不足」（用户 0 怒气验证）；其余交给客户端自拒（1.59.0 模型）。
    local oku, u, noMana = pcall(IsUsableAction, s.slot)
    local pass = (oku and (u or not noMana)) and true or false
    if cd.inv then pass = not pass end
    return pass, noMana and "可用性:资源不足" or "可用性"
  elseif k == "notQueued" then
    local s = wslots[skill]
    local okq, q
    if s then okq, q = pcall(IsCurrentAction, s.slot) end -- 1.64.0 修多返回截断（q 恒 nil，已排队检测失效）
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
  elseif k == "tCreature" then
    -- 目标类型（1.70.28）：cd.cs = { beast=true, elemental=true } 多选或关系 + 是/否
    -- 读不到类型 → id=nil → 匹配不到任何选中项（「否」方向则相反，见下）
    local raw = st.tCreatureType
    local id = creatureTypeId(raw)
    if id == nil and raw ~= nil and raw ~= "" then id = "other" end -- 未列出的返回值归入「其他」
    local hit = (id ~= nil and cd.cs and cd.cs[id]) and true or false
    local pass = (hit == (cd.v ~= false))
    return pass, "目标类型:" .. tostring(raw or "?") .. (cd.v == false and "(否)" or "")
  elseif k == "target" then
    -- 副作用条件：切换当前目标（战斗信息UI 亮金预览 dry 时不执行，防止刷新误切目标）
    local gfn = TARGET_SEL_FN[cd.s]
    local fn = gfn and getglobal(gfn)
    if type(fn) ~= "function" then return false, "无选取函数:" .. tostring(cd.s) end
    if cd.s == "byName" and not (cd.nm and cd.nm ~= "") then return false, "未设目标名称" end
    if not dry then
      if cd.s == "byName" then pcall(fn, cd.nm)
      elseif TARGET_SEL_ARG[cd.s] then
        -- ★1.70.47 队伍/团队选取：把「规则」与「队伍 or 团队」传给 EVAL_TEAM_PICK，
        --   让它按同规则里的队伍条件反推选人判据（选血最少 / 蓝最少 / 中魔法的那个）。
        teamPickArg.rule = rule
        TARGET_SEL_ARG_LAST = cd.s
        pcall(fn, TARGET_SEL_ARG[cd.s])
        teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
      else pcall(fn) end
    end
    return true, "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
  end
  -- ★1.70.47 队友/团员条件（用户需求定案）。四种：血量% / 蓝量% / debuff 检测 / buff 检测。
  --   ★语义（用户原话「扫描全员取最低，记下 unitID → st.allyUnit」）：
  --     teamHp     : 扫描全员取**血量%最低**者，与该值比较；命中时记 st.allyUnit = 他
  --     teamMana   : 同上，只算**有蓝职业**（怒气/能量/集中/幸福职业跳过，绝不当成 0% 蓝）
  --     teamBuff   : 「有」= 任一成员带该 buff ；「无/缺」= 任一成员缺该 buff
  --     teamDebuff : 「有」= 任一成员中该类型负面（★这正是「队友有魔法→解魔法」）；「无」= 没人中
  --   ★谁被扫：由 **cd.name** 决定（"队伍" → player+partyN；"团队" → raidN），两类条件各扫各的。
  --   ★★★命中时**切目标并把 unit 记进 st.allyUnit**（用户要求）——这样单条条件就能自足地完成
  --     「找出该治/该解的人 → 后续技能行 UseAction 打在他身上」，不强制额外配一行选取目标。
  --     ★只在**非 dry** 时切（dry = 战斗信息UI 每 0.15s 的预览求值 → 绝不能切目标）。
  --     ★与「选取目标:队伍成员」的配合：规则按顺序全部执行，**后写的条件/选取者决定最终目标**
  --       （确定性的「后者覆盖前者」，不是随机）。
  --     ★「无/缺」方向（没人中 / 没人缺）不切目标：那是**存在性**判定，没有「该对谁施法」的含义。
  --   ★诚实失败：不在队/团里、成员无蓝、无人符合 → 返回 false **并给出原因**；
  --     绝不退化成对玩家自己求值（那会把「队友有魔法」静默变成「我有魔法」）。
  if k == "teamHp" or k == "teamMana" or k == "teamBuff" or k == "teamDebuff" then
    local scope = (cd.name == "团队") and "raid" or "party"
    local scopeName = (scope == "raid") and "团队" or "队伍"
    local list = EVAL_HELP_TEAM_ENSURE and EVAL_HELP_TEAM_ENSURE(scope) or nil
    if not list or table.getn(list) == 0 then
      return false, "不在" .. scopeName .. "中（无成员可检测）"
    end
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local best, bestKey = nil, nil

    if k == "teamHp" or k == "teamMana" then
      for _, r in ipairs(list) do
        local isMana = (r.powerType == nil or r.powerType == 0)
        if k == "teamMana" and not isMana then
          -- 没蓝的职业没有「蓝量%」可言，跳过（不报错，只不参与比较）
        else
          local maxv = (k == "teamHp") and r.hpMax or r.powerMax
          local pct  = (k == "teamHp") and r.hpPct or r.powerPct
          if maxv and maxv > 0 and (bestKey == nil or pct < bestKey) then best, bestKey = r, pct end
        end
      end
      if not best then return false, scopeName .. "中无人可测蓝量" end
      local pass = condCmp({ cd.op, cd.n }, bestKey)
      local lbl = ((k == "teamHp") and scopeName .. "血%" or scopeName .. "蓝%")
        .. ":" .. tostring(bestKey) .. "% " .. tostring(best.name or best.unit)
      -- ★命中即「记下这个人」并切过去：后续技能行的 UseAction 就落在他身上
      if pass and not dry then teamSelect(best) end
      return pass, lbl
    elseif k == "teamBuff" then
      -- 「有队伍buff:X」= **有任一**成员带 X（层数够）；「无队伍buff:X」= **有任一**成员缺 X。
      --   ★语义与自身/目标的 有buff/无buff 对齐：都是「存在性」判定，不要求全队一致。
      --   报出的成员：有 → 层数最高的那个；无 → 层数最少的那个（= 最该补的人）。
      local tex = texOf(cd.s)
      if not tex then return false, "未知buff:" .. tostring(cd.s) end
      local have, haveCnt, lack, lackCnt = nil, nil, nil, nil
      for _, r in ipairs(list) do
        local cnt = r.buffs[tex]
        cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
        -- ★并列时的裁决：层数相同就选**血量百分比更低**的那个。
        --   与 EVAL_TEAM_PICK 的 teamPickBest 用同一条规则——否则「条件报出的人」和
        --   「选取目标实际切过去的人」可能不是同一个（日志与行为对不上，用户会以为选错了）。
        if cnt >= lim then
          if not have or cnt > haveCnt or (cnt == haveCnt and r.hpPct < have.hpPct) then have, haveCnt = r, cnt end
        else
          if not lack or cnt < lackCnt or (cnt == lackCnt and r.hpPct < lack.hpPct) then lack, lackCnt = r, cnt end
        end
      end
      local lbl = scopeName .. "buff:" .. tostring(cd.s) .. (lim > 1 and (">=" .. lim) or "")
      if cd.v == false then
        if not lack then return false, lbl .. " 全都有" end -- 「无/缺」不成立：没人缺
        if not dry then teamSelect(lack) end -- 缺 buff 的人 = 该被补的那个人
        return true, lbl .. " 缺:" .. tostring(lack.name or lack.unit)
      end
      if not have then return false, lbl .. " 无人有" end
      -- 「有」= 纯存在性判定（不是「该对谁施法」）→ **不切目标**
      return true, lbl .. " 有:" .. tostring(have.name or have.unit)
    else -- teamDebuff
      -- 「有队伍debuff:X」= **有任一**成员中 X；「无队伍debuff:X」= **没人**中 X。
      --   ★这正是「队伍有魔法 → 解魔法」：正向为真时，报出的那个成员就是该解的人。
      local want = cd.dt
      local hasName = (cd.s ~= nil and cd.s ~= "")
      local tex = hasName and texOf(cd.s) or nil
      if hasName and not tex then return false, "未知debuff:" .. tostring(cd.s) end
      local hit, hitCnt, best = false, 0, nil
      for _, r in ipairs(list) do
        local cur2, curCnt = false, 0
        if tex then
          local d = r.debuffs[tex]
          if d and dispelMatch(d.t, want) then cur2 = true curCnt = tonumber(d.n) or 1 end
        else
          for _, d in pairs(r.debuffs) do
            if dispelMatch(d.t, want) then cur2 = true curCnt = tonumber(d.n) or 1 break end
          end
        end
        if cur2 and (best == nil or curCnt > hitCnt) then hit, hitCnt, best = true, curCnt, r end
      end
      local lbl = scopeName .. "debuff:" .. (hasName and tostring(cd.s) or "(任意)")
        .. ((want ~= nil and want ~= "" and want ~= "any") and ("(" .. tostring(want) .. ")") or "")
      if not hit then
        -- 没人中：正向（有）如实失败；取反（无）如实通过
        return (cd.v == false), lbl .. " 无人有"
      end
      if cd.v == false then return false, lbl .. " 有人有:" .. tostring(best.name or best.unit) end
      local ok = hitCnt >= lim
      -- ★命中即切过去：这正是「队友有魔法 → 解魔法」——不切的话技能会打在别人身上
      if ok and not dry then teamSelect(best) end
      return ok, lbl .. (ok and (" 有:" .. tostring(best.name or best.unit)) or (" 层数不足(" .. tostring(hitCnt) .. ")"))
    end
  end
  return false, "未知条件:" .. tostring(k)
end

-- 条件组求值：任一组全过即过（组间 | ），组内全过才算过（组内 & ）
-- 命中时返回第三个值 trace = 该组每个条件的逐项判定明细（释放日志用）
-- 1.49.1：条件为空 = 无条件直接执行（旧行为：空 groups 表一组都不进 → 恒 false 永远不触发，
-- 编辑窗不配条件保存 / 导入文本 "- 技能 | " 都会产出空表——技能变死条目）
-- ★注意这里是**给上面已前置声明的 local 赋值**（不是新建 local）——
--   改了会连带断掉「队伍成员」扫描器里的候选过滤（那些引用在声明点之前）。
function groupsOK(rule, dry)
  if not rule.groups or table.getn(rule.groups) == 0 then return true, nil, "无条件" end
  local lastWhy = "条件不满足"
  for _, g in ipairs(rule.groups or {}) do
    local allOK = true
    local trace = {}
    for _, cd in ipairs(g) do
      local ok, why = condOne(cd, rule.skill, dry, rule)
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

-- ===== 挥击计时（1.55.0，与施法学习同机制） =====
-- 事件 CHAT_MSG_COMBAT_SELF_HITS：「你击中X造成Y点伤害。」「你爆击X…」（英文 "You hit/crit X for Y"）
-- ——每次平砍命中锚定 st.lastSwing；攻速 UPDATE_STATE 采集（st.atkSpd）；施法会推迟挥击：锚点取 max(lastSwing, castUntil)
function EVAL_SWING_EVENT(msg)
  if type(msg) ~= "string" then return false end
  local hit = string.find(msg, "^你击中") or string.find(msg, "^你爆击") or string.find(msg, "^You hit") or string.find(msg, "^You crit")
  if not hit then return false end
  st.lastSwing = GetTime()
  return true
end

-- 距下次挥击秒数；无攻速/无锚点数据返回 nil（UI 显示「—」）
function EVAL_SWING_REMAIN()
  local spd = st.atkSpd
  if not (spd and spd > 0) then return nil end
  local anchor = st.lastSwing
  if st.castUntil and st.castUntil > (anchor or 0) then anchor = st.castUntil end -- 施法推迟挥击
  if not anchor then return nil end
  local r = anchor + spd - GetTime()
  return (r > 0) and r or 0
end

function EVAL_RULE_RUN(rules)
  local acted = false -- 1.53.0：非 GCD 类型出手也算有动作（但继续评估后续规则）
  for _, r in ipairs(rules) do
    if r.enabled == false then
      -- 技能配置开关关掉的：静默跳过
    elseif not wslots[r.skill] and not petCmdOf(r.skill) and not targetSelOf(r.skill) and not itemOf(r.skill) and not stanceOf(r.skill) and not cancelCastOf(r.skill) then
      wlog(r.skill .. "跳过: 不在动作条")
    elseif wImmuneTo(r.skill) then
      wlog(r.skill .. "跳过: 目标已免疫（学习记录 " .. tostring(st.targetName) .. "）")
    elseif TARGET_SEL_TEAMSEL[targetSelOf(r.skill)] then
      -- ★★1.70.47「选取目标:队伍成员/团队成员」技能行——**不做常规条件预判**：
      --   那一行的条件列表是给**候选**用的过滤条件（目标血量/目标buff/目标debuff 说的是「被扫描到的那个人」），
      --   拿它对「当前目标」预判毫无意义（一个都过不了 → 扫描器永远不执行）。
      --   所以直接进 wuse，由 EVAL_TEAM_PICK 逐候选判定（见那里的 ① 分支）。
      teamPickArg.rule = r
      local tsel = targetSelOf(r.skill)
      TARGET_SEL_ARG_LAST = tsel
      local okw = wuse(r.skill, r.why or r.skill)
      teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
      if okw then
        acted = true
        EVAL_HELP_UPDATE_STATE() -- 目标已切到选中成员，后续条件按新状态判定
      else
        wlog(r.skill .. "跳过: 队伍/团队里没有符合该行条件的成员")
      end
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
          -- 1.59.0 去除公共CD终止机制（用户定义）：按顺序把符合的规则全部执行一遍——
          -- 能不能放交给游戏内置判定（GCD 中 UseAction 静默失败，不产生副作用）；
          -- 1.53.0 的 gcdSkill 终止删除，所有类型统一：出手后刷新状态、继续评估后续规则。
          acted = true
          EVAL_HELP_UPDATE_STATE() -- 目标/状态可能已变，后续条件按新状态判定
        end
      else
        wlog(r.skill .. "跳过: " .. tostring(why))
      end
    end
  end
  return acted
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
  ["距攻击"] = "swingLeft", ["swingLeft"] = "swingLeft", -- 1.57.0 距下次攻击秒数
  -- ★1.70.47 队伍/团队血量·蓝量百分比（条件自己去队里挑「血最少/蓝最少」的那个人，见 condOne）
  ["队伍血"] = "teamHp", ["队伍血量"] = "teamHp", ["teamHp"] = "teamHp",
  ["队伍蓝"] = "teamMana", ["队伍蓝量"] = "teamMana", ["teamMana"] = "teamMana",
  ["团队血"] = "teamHp", ["团队血量"] = "teamHp",
  ["团队蓝"] = "teamMana", ["团队蓝量"] = "teamMana",
}
local COND_BOOL = {
  ["战斗中"] = { "combat", true }, ["非战斗"] = { "combat", false }, ["combat"] = { "combat", true },
  ["目标存在"] = { "hasTarget", true }, ["有目标"] = { "hasTarget", true }, ["无目标"] = { "hasTarget", false }, ["hasTarget"] = { "hasTarget", true },
  ["可攻击"] = { "canAttack", true }, ["canAttack"] = { "canAttack", true },
  -- ★★★1.70.43 往返一致性的核心修复：以下 8 条「取反写法」**导出侧一直在写、解析侧一直没有**
  --   （EVAL_COND_STR 第 1224~1232 行会输出 不可攻击/不可流血/非精英/非Boss/目标非战斗/非友善/非敌对/非中立），
  --   而 EVAL_PARSE_ONE 只认 COND_BOOL 里已有的键 + 感叹号前缀 → 这些写法解析为 nil
  --   → EVAL_PARSE_CONDS 只 push 非 nil → **条件被静默丢弃**（用户看不到任何报错）。
  --   影响：任何用到这些条件的方案，一旦「导出→导入」或经案例模版导入，条件就消失。
  --   ★教训：序列化器的输出域必须用一条「导出→导入」往返断言锁死（见 test 组 59），
  --     否则两侧各自演化，缺口只会在用户数据里静默出现。
  ["不可攻击"] = { "canAttack", false },
  ["可流血"] = { "canBleed", true }, ["canBleed"] = { "canBleed", true },
  ["不可流血"] = { "canBleed", false },
  ["精英"] = { "isElite", true }, ["isElite"] = { "isElite", true },
  ["非精英"] = { "isElite", false },
  ["Boss"] = { "isBoss", true }, ["首领"] = { "isBoss", true }, ["isBoss"] = { "isBoss", true },
  ["非Boss"] = { "isBoss", false }, ["非首领"] = { "isBoss", false },
  ["目标战斗中"] = { "tInCombat", true }, ["tInCombat"] = { "tInCombat", true },
  ["目标非战斗"] = { "tInCombat", false },
  ["目标友善"] = { "tFriendly", true }, ["友善"] = { "tFriendly", true }, ["tFriendly"] = { "tFriendly", true },
  ["非友善"] = { "tFriendly", false },
  ["目标敌对"] = { "tHostile", true }, ["敌对"] = { "tHostile", true }, ["tHostile"] = { "tHostile", true },
  ["非敌对"] = { "tHostile", false },
  ["目标中立"] = { "tNeutral", true }, ["中立"] = { "tNeutral", true }, ["tNeutral"] = { "tNeutral", true },
  ["非中立"] = { "tNeutral", false },
  ["Alt"] = { "alt", true }, ["alt"] = { "alt", true },
  ["Shift"] = { "shift", true }, ["shift"] = { "shift", true },
  ["Ctrl"] = { "ctrl", true }, ["ctrl"] = { "ctrl", true },
  ["普攻"] = { "autoAttack", true }, ["autoAttack"] = { "autoAttack", true },
  ["自动射击"] = { "autoShot", true }, ["autoShot"] = { "autoShot", true }, -- 1.51.0（取反写 !自动射击 或 未自动射击）
  ["未自动射击"] = { "autoShot", false },
  ["魔杖射击"] = { "wandShoot", true }, ["wandShoot"] = { "wandShoot", true },
  ["未魔杖射击"] = { "wandShoot", false },
  ["未普攻"] = { "autoAttack", false }, -- 1.51.0 补旧缺口：显示层早有 未普攻，解析层一直不会
}
local COND_FLAG = {
  ["就绪"] = "ready", ["ready"] = "ready",
  ["可用"] = "usable", ["usable"] = "usable",
  ["未排队"] = "notQueued", ["notQueued"] = "notQueued",
}
-- ★1.70.43 反向 flag 单独一张表：COND_FLAG 的值只是「键名」，表达不了 inv 语义。
--   导出侧（EVAL_COND_STR 第 1250~1252 行）会写 未就绪 / 不可用 / 已排队，
--   而这三个此前不在任何表里 → 导入同样被静默丢弃。与上面 8 条是同一个缺口的两半。
local COND_FLAG_INV = {
  ["未就绪"] = "ready", ["notready"] = "ready",
  ["不可用"] = "usable", ["notusable"] = "usable",
  ["已排队"] = "notQueued", ["queued"] = "notQueued",
}

-- ★1.70.45 内层：原 EVAL_PARSE_ONE 主体。外层（见下方 EVAL_PARSE_ONE）负责先剥掉
--   「剩余时间」后缀 [<30s]，再统一挂到结果 cd 上——这样 8 个光环分支一处都不用改，
--   也保证任何分支都不会把后缀当成光环名字的一部分（否则名字错=永远静默匹配不上）。
local function parseOneRaw(token)
  token = condTrim(token)
  if token == "" then return nil end
  local neg = false
  if string.sub(token, 1, 1) == "!" then neg = true token = condTrim(string.sub(token, 2)) end
  local name, op, num = string.match(token, "^(.-)([><]=?)(%d+)$")
  if name and COND_NUM[condTrim(name)] then
    local ck = COND_NUM[condTrim(name)]
    -- ★1.70.47 队伍/团队血蓝：「团队血<50」要带上扫描范围（cd.name），否则导出回来会退化成队伍
    if ck == "teamHp" or ck == "teamMana" then
      local sc = string.match(condTrim(name), "^团队") and "团队" or "队伍"
      return { k = ck, op = op, n = tonumber(num), name = sc }
    end
    return { k = ck, op = op, n = tonumber(num) }
  end
  local fn = string.match(token, "^姿态(%d)$")
  if fn then return { k = "form", n = tonumber(fn) } end
  fn = string.match(token, "^非姿态(%d)$")
  if fn then return { k = "formNot", n = tonumber(fn) } end
  -- 光环层数后缀（1.31.0 debuff 起；1.70.1 扩到四类光环）：名>=3（至少3层）/ 名<3（不足3层）；无后缀=只要有/没有
  -- want: "min"=有(至少N层，只收 >/>=)；"max"=无(不足N层，只收 </<=)。
  -- 1.32.0 审计修复：反向 op（如 有debuff:x<3）语义会反转成 cnt>=3 的静默逻辑坑——降级为无层数限制
  -- 注：本函数必须定义在下方各光环解析分支【之前】（Lua local 作用域从声明后开始）
  local function auraStack(body, want)
    local nm, op, n = string.match(body, "^(.-)([><]=?=?)(%d+)$")
    if not nm then return condTrim(body), nil end
    if want == "min" and op ~= ">" and op ~= ">=" then return condTrim(nm), nil end
    if want == "max" and op ~= "<" and op ~= "<=" then return condTrim(nm), nil end
    n = tonumber(n)
    if op == ">" then n = n + 1 elseif op == "<=" then n = n + 1 end -- >N 即 >=N+1；<=N 即 <N+1
    return condTrim(nm), n
  end
  local bs = string.match(token, "^无buff[:：](.+)$") or string.match(token, "^noBuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "max") return { k = "hasBuff", s = nm, n = n, v = false } end -- 1.54.0 合并为 hasBuff+v（旧 noBuff 词条仍认）；1.70.1 层数
  local tb = string.match(token, "^目标buff[:：](.+)$") or string.match(token, "^tBuff[:=](.+)$") -- 1.54.0；1.70.1 层数
  if tb then local nm, n = auraStack(tb, "min") return { k = "tBuff", s = nm, n = n, v = not neg } end
  local tbn = string.match(token, "^无目标buff[:：](.+)$") or string.match(token, "^目标无buff[:：](.+)$")
  if tbn then local nm, n = auraStack(tbn, "max") return { k = "tBuff", s = nm, n = n, v = false } end
  local pd = string.match(token, "^自身debuff[:：](.+)$") or string.match(token, "^pDebuff[:=](.+)$")
  if pd then local nm, n = auraStack(pd, "min") return { k = "pDebuff", s = nm, n = n, v = not neg } end
  local pdn = string.match(token, "^无自身debuff[:：](.+)$") or string.match(token, "^自身无debuff[:：](.+)$")
  if pdn then local nm, n = auraStack(pdn, "max") return { k = "pDebuff", s = nm, n = n, v = false } end
  bs = string.match(token, "^有buff[:：](.+)$") or string.match(token, "^hasBuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "min") return { k = "hasBuff", s = nm, n = n } end
  bs = string.match(token, "^无debuff[:：](.+)$") or string.match(token, "^noDebuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "max") return { k = "hasDebuff", s = nm, n = n, v = false } end -- 1.54.0 合并
  bs = string.match(token, "^有debuff[:：](.+)$") or string.match(token, "^hasDebuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "min") return { k = "hasDebuff", s = nm, n = n } end
  -- ★1.70.47 队伍/团队 buff/debuff（导入/文本编辑）：前缀「队伍」或「团队」决定扫描范围（cd.name）。
  --   写法：有/无{队伍|团队}buff:名 ；有/无{队伍|团队}debuff:名(类型) 或直接写类型 ；英文 id teamBuff/teamDebuff(默认队伍)
  --   ★★★两条 Lua 模式的硬规矩（都是本项目 H 节记过、我这次又踩的）：
  --     ① **`|` 不是交替**——写成 (队伍|团队) 只在匹配字面串「队伍|团队」时成立，
  --        结果是任何队伍/团队条件都解析不出来（表现：编辑窗存了、再导入条件**静默消失**）。
  --     ② **字符组不能装多字节字**——`[伍团]` 是**按字节**匹配的集合，
  --        匹配 '伍' 的首字节后剩下两个尾字节对不上后面的 buff，照样失败。
  --     所以这里改成「先用 .+ 抓前缀，再**用字符串比较**校验前缀」——不受多字节影响。
  local function teamScope(pfx)
    if pfx == "队伍" or pfx == "团队" then return pfx end
    return nil
  end
  local p1, p2
  p1, p2 = string.match(token, "^有(.+)buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "min")
    return { k = "teamBuff", s = nm, n = n, v = not neg, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^无(.+)buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "max")
    return { k = "teamBuff", s = nm, n = n, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^(.+)无buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "max")
    return { k = "teamBuff", s = nm, n = n, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^有(.+)debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = not neg, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^无(.+)debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^(.+)无debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = false, name = teamScope(p1) } end
  -- 英文 id（默认队伍范围）
  local tbf = string.match(token, "^teamBuff[:=](.+)$")
  if tbf then local nm, n = auraStack(tbf, "min")
    return { k = "teamBuff", s = nm, n = n, v = not neg, name = "队伍" } end
  local tdb = string.match(token, "^teamDebuff[:=](.*)$")
  if tdb then local nm, dt = dispelSplit(tdb)
    return { k = "teamDebuff", s = nm, dt = dt, v = not neg, name = "队伍" } end
  -- 1.70.28 目标类型（导入）：支持 目标类型:野兽/元素、目标类型非:元素、tCreature=beast
  local tcr = string.match(token, "^目标类型非[:：](.+)$") or string.match(token, "^notcreature[:=](.+)$")
  if tcr then
    tcr = string.gsub(tcr, "、", "/") tcr = string.gsub(tcr, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tcr, "[^/,]+") do
      local id = creatureTypeId(condTrim(nm))
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tCreature", cs = cs, v = false } end
    return nil
  end
  local tcp = string.match(token, "^目标类型[:：](.+)$") or string.match(token, "^tCreature[:=](.+)$")
  if tcp then
    tcp = string.gsub(tcp, "、", "/") tcp = string.gsub(tcp, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tcp, "[^/,]+") do
      local id = creatureTypeId(condTrim(nm))
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tCreature", cs = cs } end
    return nil
  end
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
  -- 1.51.0 修复取反优先级：旧式 neg and (not b[2]) or b[2] 在 b[2]=true（全部条目）时 ! 恒失效
  if b then local vv = b[2] if neg then vv = not vv end return { k = b[1], v = vv } end
  local fl = COND_FLAG[token]
  if fl then return { k = fl, inv = neg } end
  -- ★1.70.43 反向 flag（未就绪/不可用/已排队）：inv 恒为 true；「!未就绪」= 双重取反 = 就绪
  local fli = COND_FLAG_INV[token]
  if fli then return { k = fli, inv = not neg } end
  return nil
end

-- ★★1.70.45 剩余时间后缀 [<op><n>s]（用户要求：buff 类条件加「剩余时间检查」，单位秒）。
--   语法示例：无buff:奥术智慧[<30s]  = 没有「奥术智慧」或 剩余不足 30 秒
--           有buff:奥术智慧[>=60s] = 有，且剩余至少 60 秒
--   ★为什么用方括号：层数后缀（名<N / 名>=N）已经占用了「名字后面直接跟比较符」的写法，
--     两者若共用一套语法必然歧义。方括号把时间段整个包住、且以 s 结尾，互不干扰。
--   ★作用范围：本客户端**只有自身光环**有时长 API（wiki globals/Buff：
--     GetPlayerBuffTimeLeft 返回秒；其他单位的 UnitBuff/UnitDebuff 只给图标+层数）。
--     故后缀**只在 自身buff(hasBuff) / 自身debuff(pDebuff) 上生效**；
--     目标两类即使写了也会在求值阶段如实返回 false（见 condOne 的注释），不静默当作没写。
--   ★非光环条件带这个后缀 = 写法错误 → 返回 nil（宁可丢弃，也不静默接受一个无意义的字段）。
function EVAL_PARSE_ONE(token)
  token = condTrim(token)
  if token == "" then return nil end
  local stripped, sop, snum = string.match(token, "^(.-)%[([<>=]+)(%d+)s%]$")
  local cd = parseOneRaw(stripped and condTrim(stripped) or token)
  if not stripped then return cd end
  if not cd then return nil end
  if cd.k == "hasBuff" or cd.k == "pDebuff" or cd.k == "tBuff" or cd.k == "hasDebuff" then
    cd.secOp, cd.secN = sop, tonumber(snum)
    return cd
  end
  return nil -- 非光环条件不允许带剩余时间后缀
end

-- 测试直调：单条件求值（EVAL_RULE_RUN 会跳过「不在动作条」的技能，无法用于纯粹的条件断言）
function EVAL_COND_EVAL(cd) return condOne(cd, nil, true) end

-- ★1.70.47 断言专用：以**非 dry** 方式求值单个条件（= 按宏时真正走的那条路）。
--   存在理由：dry 模式不执行副作用（不切目标）、也不做队伍扫描；
--   而队伍/团队条件的核心行为**恰恰是扫描+选人+切目标**——只用 dry 断言等于没测。
--   这是本项目第 4 次栽在「只测解析不测调用点」上之后补的钩子。
function EVAL_TEST_COND_EVAL_LIVE(cd, rule) return condOne(cd, nil, false, rule) end

-- ★1.70.47 断言专用：走「选取目标:队伍/团队」的 auto 判据推断（等价于 condOne 的 target 分支）。
--   传 nil 规则 = 无队伍条件 → 退化「血量最低」；传规则 = 按规则里的队伍条件反推。
-- ★1.70.47 断言专用：直调**技能级执行**（选取目标/宠物指令/物品/动作条那条路）。
--   存在理由：技能行也能写成「选取目标:团队」，那条路径**不经过 condOne**，
--   是个独立调用点；只测条件路径会漏掉它（本项目「A 产出 / B 消费 两边都要断言」）。
function EVAL_TEST_WUSE(name) return wuse(name, "test") end

function EVAL_TEST_TEAM_PICK_AUTO(rule, selId)
  teamPickArg.rule = rule
  TARGET_SEL_ARG_LAST = selId or "teamParty"
  local ok, unit = pcall(EVAL_TEAM_PICK, "auto")
  teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
  if not ok then return nil, tostring(unit) end
  return unit
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
-- 1.49.2 power 显示名动态化（UnitPowerType：法力/怒气/集中值/能量——旧版硬编码「怒气」，法师看着别扭）
local COND_NUMNAME = { power = (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), tHpPct = "目标血", hpPct = "自身血", swingLeft = "距攻击", powerPct = "能量%", combatTime = "进战", tCastEl = "读条", tCastLeft = "读条剩", combo = "连击" }
function EVAL_COND_STR(cd)
  local k = cd.k
  -- ★1.70.47 队伍/团队血蓝：前缀随扫描范围（cd.name）变化，保证「导出→导入」往返不掉范围
  local tscope = (cd.name == "团队") and "团队" or "队伍"
  if k == "teamHp" then return tscope .. "血" .. (cd.op or ">") .. tostring(cd.n) end
  if k == "teamMana" then return tscope .. "蓝" .. (cd.op or ">") .. tostring(cd.n) end
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
  if k == "autoShot" then return cd.v and "自动射击" or "未自动射击" end -- 1.51.0
  if k == "wandShoot" then return cd.v and "魔杖射击" or "未魔杖射击" end
  -- 1.70.1：四类光环检查统一附层数门槛（>=N / <N），与 hasDebuff 同语法
  local function stkSuffix()
    if type(cd.n) == "number" and cd.n > 1 then return ((cd.v == false) and "<" or ">=") .. cd.n end
    return ""
  end
  -- ★1.70.45 剩余时间后缀（单位秒）：[<30s] / [>=60s] … 与层数后缀（名<N）不冲突，理由见 EVAL_PARSE_ONE
  local function secSuffix()
    if type(cd.secN) == "number" and type(cd.secOp) == "string" then
      return "[" .. cd.secOp .. cd.secN .. "s]"
    end
    return ""
  end
  if k == "hasBuff" then return ((cd.v == false) and "无buff:" or "有buff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() end -- 1.54.0 合并（旧 k=noBuff 走下一行兼容）
  if k == "noBuff" then return "无buff:" .. tostring(cd.s) end
  if k == "tBuff" then return ((cd.v == false) and "无目标buff:" or "目标buff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() end -- 1.54.0
  if k == "pDebuff" then return ((cd.v == false) and "无自身debuff:" or "自身debuff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() end -- 1.54.0
  if k == "hasDebuff" then return ((cd.v == false) and "无debuff:" or "有debuff:") .. tostring(cd.s) .. ((type(cd.n) == "number" and cd.n > 1) and ((cd.v == false and "<" or ">=") .. cd.n) or "") .. secSuffix() end
  if k == "noDebuff" then return "无debuff:" .. tostring(cd.s) .. ((type(cd.n) == "number" and cd.n > 1) and ("<" .. cd.n) or "") end
  -- ★1.70.47 队伍/团队 buff/debuff（用户要求）：前缀带扫描范围；类型以 (Magic) 后缀附上，解析侧双向容忍本地化名
  if k == "teamBuff" then return ((cd.v == false) and ("无" .. tscope .. "buff:") or ("有" .. tscope .. "buff:")) .. tostring(cd.s) .. stkSuffix() end
  if k == "teamDebuff" then
    local nm = (cd.s ~= nil and cd.s ~= "") and tostring(cd.s) or ""
    local dt = (cd.dt ~= nil and cd.dt ~= "" and cd.dt ~= "any") and ("(" .. tostring(cd.dt) .. ")") or ""
    return ((cd.v == false) and ("无" .. tscope .. "debuff:") or ("有" .. tscope .. "debuff:")) .. nm .. dt
  end
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
  if k == "tCreature" then -- 1.70.28 目标类型（多选或关系 + 是/否）
    local ns = {}
    for _, c in ipairs(CREATURE_TYPES) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.loc) end end
    local body = (table.getn(ns) > 0 and table.concat(ns, "/") or "未选")
    return ((cd.v == false) and "目标类型非:" or "目标类型:") .. body
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

-- 方案数据：缺省时给空「默认」方案（1.48.0 起；旧版生成一整套战士规则已删——起手走案例模版/编辑窗）
function EVAL_WAR_ENSURE_PROFILES(w)
  if not w then return end
  if not w.debuffTex then w.debuffTex = {} end -- 1.32.0 审计修复：光环名→纹理学习表从未创建，学习跨会话丢失（1.27.0 遗留）
  if not w.immune then w.immune = {} end -- 1.36.0 免疫学习表（技能@怪名，EVAL_IMMUNE_LEARN 写入）
  if not w.castTime then w.castTime = {} end -- 1.40.0 目标读条总时长学习表（技能名→秒）
  if type(w.profiles) ~= "table" or table.getn(w.profiles) == 0 then
    -- 1.48.0 去战士化：新装插件默认给空方案（旧版生成 战斗姿态/冲锋/压制… 一整套战士规则，其他职业全是垃圾条目）；
    -- 起手请用 配置窗→导入导出→[案例模版]（武器战模版首发）或编辑窗自行添加。
    w.profiles = { { name = "默认", skills = {} } }
  end
  if not w.activeProfile then w.activeProfile = 1 end
end



-- 一键入口：/run EVAL_GO()
-- 可选参数 profSel：0 或不传 = 当前激活方案；1-4 = 直触对应方案；字符串 = 按方案名。
-- 直触不改变激活方案。绑定多按键：宏1 /run EVAL_GO(1)（或 EVAL_GO1()）、宏2 /run EVAL_GO(2)……
function EVAL_GO(profSel)
  if profSel == 0 then profSel = nil end -- 0 = 当前激活方案
  -- 1.54.1 执行去抖：/run 宏在本客户端走 RunScript pending 队列（wiki 原文： queued, runs when flushed）——
  -- 连按时按键在队列里堆积，松手后陈旧调用还在逐个冲刷（用户实测：停手后目标狂切/技能滞后放）。
  -- 窗口内重复调用直接丢弃：公共CD 1.5s 下节流无感，但堆积的过期调用几乎全部失效 → 松手即停。
  -- 1.54.2 窗口可配：cfg.goDebounce 秒（默认 0.3，配置窗全局 Tab [一键宏] 组 [-][+] 步进 0.05）；
  --          + 执行追踪 EVAL_GO_TRACE（/eh go trace 看最近 12 次调用时间戳，定位偶发重复执行）。
  local goNow = GetTime()
  local goWin = tonumber(EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.goDebounce) or 0.3
  local goSkip = (goWin > 0) and (goNow - (EVAL_GO_LAST or 0) < goWin) or false
  EVAL_GO_TRACE = EVAL_GO_TRACE or {}
  table.insert(EVAL_GO_TRACE, 1, { t = goNow, skip = goSkip })
  while table.getn(EVAL_GO_TRACE) > 12 do table.remove(EVAL_GO_TRACE) end
  if goSkip then
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff9040war:|r 去抖：忽略过快调用（队列冲刷）") end
    return
  end
  EVAL_GO_LAST = goNow
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
  -- ★1.70.47「这一次按键选中的队友」必须在**每次按键开头清空**：
  --   否则上一轮选的人会被这一轮当成「本次命中的人」，技能就打在旧目标身上了。
  --   它由 队友/团员条件 或 选取目标:队伍成员/团队成员 在**本轮**写入。
  st.allyUnit, st.teamCur = nil, nil
  local rage     = st.power
  local inCombat = st.inCombat

  -- 1)（1.49.0 移除硬编码「无有效目标 → TargetNearestEnemy」前置：它在规则评估之前抢跑选敌，
  --    与「选取目标:最近友方」类规则方向相反、互相抢目标（用户实测日志先选敌再选友）。
  --    选目标行为全部交给规则：需要自动选敌写规则 选取目标:最近敌人 | 无目标（或非战斗 & 无目标 等组合）。
  --    1.21.7 起本函数已不再因无目标硬返回——攻击类技能用「可攻击/可用」条件兜底。）

  local thscale  = st.tHpPct / 100
  local ttype    = st.tCreatureType
  local canBleed = st.canBleed -- Cat 的 MPTargetBleed（类型排除+黑白名单，见状态模块）

  -- 2)（1.22.0 移除硬编码「非战斗切姿态/冲锋」前置：它无视方案内容强制出手，是旧战士宏残留。
  --    需要该行为请在方案里加规则：战斗姿态 | 非战斗 & 非姿态1 & 可攻击；冲锋 | 非战斗 & 姿态1 & 可攻击 & 就绪）

  -- 3) 自动普攻（AttackTarget 是切换语义，必须用 IsCurrentAction 守卫，连按安全）
  -- 1.47.0 解耦：st.autoAttack 状态采集【不受接管开关影响】（否则开关关掉时 普攻/未普攻 条件恒读 false，
  -- 规则里放「攻击」不带 未普攻 条件会每按一次开/关翻转）；开关只控制「自动开启」这个动作。
  -- 1.50.0 自动攻击（改名自 自动普攻接管）：优先级 自动射击(猎人) > 射击(魔杖) > 攻击(近战普攻)；
  -- 上条且【可用】才入选（IsUsableAction——无远程武器/无魔杖自动降档）；近战「攻击」为无条件兜底。
  local atkSlot, atkUse, atkName = nil, nil, nil
  local function pickAtk(name, useFn, needUsable)
    local s = wslots[name]
    if not s then return false end
    if needUsable then
      if type(IsUsableAction) == "function" then
        local oku, usable, noMana = pcall(IsUsableAction, s.slot)
        if not (oku and (usable or not noMana)) then return false end -- 1.64.0 只信资源信号（缓存 false 不误降档）
      end
      -- 1.52.0 距离检测：IsUsableAction 不含射程判定（自动射击 8-35 码贴脸也"可用"但放不出）——
      -- IsActionInRange 明确返回 0=超程时降档；nil=无目标/无法判定时放行（交给客户端自己拒）
      if type(IsActionInRange) == "function" then
        local okr, inRg = pcall(IsActionInRange, s.slot)
        if okr and inRg == 0 then return false end
      end
    end
    atkSlot, atkUse, atkName = s.slot, useFn, name
    return true
  end
  if not pickAtk("自动射击", function() UseAction(wslots["自动射击"].slot) end, true)
     and not pickAtk("射击", function() UseAction(wslots["射击"].slot) end, true) then
    pickAtk("攻击", function() AttackTarget() end) -- 近战兜底（不查可用，自动攻击恒可开）
  end
  st.autoAttack = false
  if atkSlot and type(IsCurrentAction) == "function" then
    local okc, cur = pcall(IsCurrentAction, atkSlot)
    if okc and cur then st.autoAttack = true end
    -- 1.65.0 接管动作【还原】到规则评估之前（撤销 1.62.0 后移）：当时的「时序污染」是误诊——
    -- 真凶是 1.64.0 修掉的 s and pcall 多返回截断（u/noMana 恒 nil 致可用性恒 false）。
    -- 可用性现只信 noMana 资源信号，开弓/进战不再误杀冲锋类脱战技能；每次按键先补自动攻击（旧行为回归）。
    if w.attack ~= false and okc and not cur and GetTime() - wLastAttackTry >= 2 then
      wLastAttackTry = GetTime()
      atkUse()
      EVAL_LOGLINE("→ 开启自动攻击（" .. atkName .. "）")
      wlog("开启自动攻击（" .. atkName .. "）")
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
  wlog(string.format("无动作 | %s%d 目标血%.0f%% %s%s%s%s", -- 1.49.2 怒气/战斗姿态硬编码→动态
    (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), rage, thscale * 100,
    inCombat and "战斗中" or "非战斗",
    (st.form and (" " .. st.form) or ""),
    ttype and (" " .. ttype) or "",
    st.isBoss and " Boss" or (st.isElite and " 精英" or "")))
end

-- 技能选择清单（1.48.0 起纯扫描）：动作条扫到的全部技能（去重排序）+ 宠物指令段，编辑窗下拉用。
-- 旧版 WAR_SKILLS 战士白名单置顶已删——法师不再看到 冲锋/压制 这些战士技能。
function EVAL_GO_SKILL_CHOICES()
  local list, seen = {}, {}
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
  table.insert(cats, { label = L("SK_CAT_1"), items = function() -- 1.43.0 追加姿态切换（姿态栏实时枚举，不占动作条）
    -- 1.47.0 扩充：自动射击（猎人）/射击（法系魔杖）走动作条通道同「攻击」；取消施法=SpellStopCasting 特殊行为
    local l = { "攻击", "自动射击", "射击", "取消施法" }
    if type(GetNumShapeshiftForms) == "function" then
      local okn, n = pcall(GetNumShapeshiftForms)
      if okn and n and n > 0 then
        for i = 1, n do
          local oki, _ic, nm = pcall(GetShapeshiftFormInfo, i)
          if oki and nm then table.insert(l, "姿态:" .. nm) end
        end
      end
    end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_2"), items = function() -- 1.48.0 纯动作条扫描（白名单已删）
    local list, seen = {}, {}
    if wscanned and wslots then
      local extra = {}
      for n in pairs(wslots) do
        if not seen[n] and n ~= "攻击" and n ~= "自动射击" and n ~= "射击" and n ~= "取消施法" then table.insert(extra, n) end
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
  -- 1.45.0 以激活方案技能为准（旧版固定战士白名单已废弃）
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  local p = w2 and w2.profiles and w2.profiles[w2.activeProfile or 1]
  if p and p.skills and table.getn(p.skills) > 0 then
    EVAL_SAY("激活方案「" .. tostring(p.name) .. "」：")
    for _, r in ipairs(p.skills) do
      local n = r.skill
      if petCmdOf(n) or targetSelOf(n) or stanceOf(n) or cancelCastOf(n) then
        EVAL_SAY(n .. ": |cff80ff80特殊技能（不占动作条）|r")
      elseif itemOf(n) then
        local bag = wFindBagItem(itemOf(n))
        EVAL_SAY(n .. ": " .. (bag and "|cff00ff00背包已找到|r" or "|cffff0000背包未找到|r"))
      else
        local s = wslots[n]
        if s then
          local ready, why = wready(n)
          EVAL_SAY(string.format("%s: 格子%d %s", n, s.slot, ready and "|cff00ff00就绪|r" or ("|cffff9040" .. tostring(why) .. "|r")))
        else
          EVAL_SAY(n .. ": |cffff0000未上动作条|r")
        end
      end
    end
  else
    EVAL_SAY("（激活方案暂无技能）")
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
EVAL_STANCE_OF = stanceOf
EVAL_CANCELCAST_OF = cancelCastOf
EVAL_TARGET_SEL = TARGET_SEL
EVAL_TSEL_NAME = TARGET_SEL_NAME
EVAL_CLASS_LIST = CLASS_LIST
EVAL_COND_TRIM = condTrim
EVAL_P_HASBUFF = wPlayerHasBuff
EVAL_T_HASDEBUFF = wTargetHasDebuff
EVAL_IS_SCANNED = function() return wscanned end
