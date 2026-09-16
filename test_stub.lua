-- fengari 测试桩：模拟本客户端 WoW API 环境（Lua 5.1 垫片 + UI mock + 战斗 API）
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
getglobal = getglobal or function(n) return _G[n] end

TEST = { used = {}, targetClass = "WARRIOR", hasTarget = true, slotNames = { [1] = "致死打击", [2] = "冲锋" }, debuffs = {}, buffs = {} }

local function newMock()
  local m = {}
  local shown, scripts, texts = false, {}, {}
  local special = {
    -- ★1.70.25：帧必须真的有显隐状态。原桩的 Show/Hide 是空操作、IsShown 恒 nil，
    --   导致「点选后面板是否仍打开」这类行为断言永远是 false —— 断言失效而不自知。
    --   （这正是「断言绿≠假设对」的又一例：桩过于宽松会把真实回归掩盖成假失败/假通过。）
    Show = function() shown = true end,
    Hide = function() shown = false end,
    IsShown = function() return shown end,
    IsVisible = function() return shown end,
    SetScript = function(_, ev, fn) scripts[ev] = fn end,
    GetScript = function(_, ev) return scripts[ev] end,
    SetText = function(_, t) texts.t = t end,
    GetText = function() return texts.t end,
  }
  setmetatable(m, { __index = function(_, k)
    if special[k] then return special[k] end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return newMock() end end
    return function() return nil end
  end })
  return m
end
-- ★1.70.39：桩必须记录父级，并模拟「祖先隐藏 → 不派发 OnUpdate」这条本客户端铁律。
--   不加这条，「tick 挂 UIParent 导致地图打开时整个停摆」这个 bug 在测试里完全不可见
--   （旧桩 CreateFrame 直接丢掉 parent，任何父级都长得一样）。
--   这正是「桩太宽松 → 真实回归不可见」的第 N 次发作，见 CLAUDE.md 1.70.25/1.70.32 条。
-- 注意：__parent 必须走 rawset 存成**真字段**。newMock 的 __index 对任何未知键
-- 都返回一个函数（宽容桩的设计），所以直接 m.__parent = x 会被后世读取，
-- 但若键不存在则会拿到函数而不是 nil —— 遍历祖先链时会炸（本轮首版即如此）。
local function newFrame(parent)
  local m = newMock()
  rawset(m, "__parent", parent or UIParent)
  return m
end
function CreateFrame(_, name, parent)
  local f = newFrame(parent)
  rawset(f, "__name", name)
  return f
end

-- UI 隐藏模拟：真客户端在**打开全屏世界地图**时会隐藏 UIParent（及其后代），
-- 而 WorldFrame 是 3D 视口、永不被 UI 隐藏。tick 是否收到 OnUpdate 取决于此。
TEST.uiHidden = false
-- 用 rawget 读 __parent：rawset 把值设成 nil 时字段其实**不存在**，
-- 普通读取会落到 newMock 的 __index 兜底函数上（返回 function 而不是 nil），
-- 祖先链遍历随即炸。rawget 才能把「没有父级」如实读成 nil。
local function parentOf(f)
  if type(f) ~= "table" then return nil end
  local p = rawget(f, "__parent")
  if p == f then return nil end
  return p
end
local function frameIsTickable(f)
  -- 祖先链里只要有一环被隐藏，该帧就收不到 OnUpdate（真客户端语义）。
  local seen = {}
  local cur = f
  while cur ~= nil and not seen[cur] do
    seen[cur] = true
    if cur == UIParent and TEST.uiHidden then return false end
    if cur == WorldFrame then return true end -- 3D 视口：永不隐藏，直接判定可跑
    cur = parentOf(cur)
  end
  return true
end
TEST.frameIsTickable = frameIsTickable

-- UIParent / WorldFrame 也走 newFrame，好让它们带上真的 __parent 字段（= nil）。
-- 用裸 newMock() 的话 __parent 会命中 __index 的兜底函数，祖先链遍历直接炸。
-- UIParent 是 UI 树的根（无父级）；WorldFrame 直接挂 UIParent 之下。
UIParent = newFrame(nil)
rawset(UIParent, "__parent", nil) -- 根帧：祖先链到此为止
-- 3D 视口，独立于 UI 显隐（真客户端恒存在）。
WorldFrame = newFrame(UIParent)
Minimap = newMock()
GameTooltipTextLeft1 = { GetText = function()
  if TEST.curBuff then return TEST.buffs[TEST.curBuff + 1] and TEST.buffs[TEST.curBuff + 1].name end
  if TEST.curDebuff then return TEST.debuffs[TEST.curDebuff] and TEST.debuffs[TEST.curDebuff].name end
  return TEST.slotNames[TEST.curSlot or 0]
end }
GameTooltip = {
  SetOwner = function() end, Hide = function() end,
  ClearLines = function() TEST.curSlot = nil TEST.curDebuff = nil TEST.curBuff = nil end,
  SetAction = function(_, slot) TEST.curSlot = slot return true end,
  SetUnitDebuff = function(_, _, i) TEST.curDebuff = i return TEST.debuffs[i] ~= nil end,
  SetPlayerBuff = function(_, bi) TEST.curBuff = bi return TEST.buffs[bi + 1] ~= nil end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) TEST.chat = (TEST.chat or "") .. tostring(msg) .. "\n" end }

GetTime = function() return TEST.time or 1000 end
UnitName = function(u) return u == "player" and "测试玩家" or (TEST.curTargetName or "测试怪") end
UnitLevel = function() return 60 end
UnitClass = function(u) if u == "target" then return "战士", TEST.targetClass, 1 end return "战士", "WARRIOR", 1 end
UnitHealth = function() return 80 end
UnitHealthMax = function() return 100 end
UnitMana = function() return 50 end
UnitManaMax = function() return 100 end
UnitPowerType = function() return 1 end
GetComboPoints = function() return TEST.combo or 0 end
-- 宠物指令桩（1.30.0）：记录调用
HasPetUI = function() return TEST.hasPet ~= false, true end
GetPetIcon = function() return "Interface\\Icons\\PetIcon" end
GetPetActionInfo = function(slot) -- 1.32.6 宠物指令图标学习桩：slot1=攻击命令 token
  if slot == 1 then return "PET_ACTION_ATTACK", nil, "texPetAttack" end
  return nil
end
PetAttack = function() TEST.petCmd = "PetAttack" end
PetFollow = function() TEST.petCmd = "PetFollow" end
PetWait = function() TEST.petCmd = "PetWait" end
PetStopAttack = function() TEST.petCmd = "PetStopAttack" end
PetPassiveMode = function() TEST.petCmd = "PetPassiveMode" end
PetDefensiveMode = function() TEST.petCmd = "PetDefensiveMode" end
PetAggressiveMode = function() TEST.petCmd = "PetAggressiveMode" end
PetDismiss = function() TEST.petCmd = "PetDismiss" end
UnitAffectingCombat = function() return TEST.inCombat or false end
GetNumShapeshiftForms = function() return TEST.stances and table.getn(TEST.stances) or 0 end
GetShapeshiftFormInfo = function(i) local f = TEST.stances and TEST.stances[i] if not f then return nil end return f.icon, f.name, f.active, f.castable end
GetShapeshiftFormCooldown = function() return 0, 0, 1 end
CastShapeshiftForm = function(i) TEST.stanceCast = i local f = TEST.stances and TEST.stances[i] if f then f.active = 1 end end
GetPlayerBuff = function(i) return TEST.buffs[i + 1] and i or -1 end
GetPlayerBuffTexture = function(bi) return TEST.buffs[bi + 1] and TEST.buffs[bi + 1].tex or nil end
UnitDebuff = function(_, i) local d = TEST.debuffs[i] if not d then return nil end return d.tex, d.apps or 0 end
UnitBuff = function(u, i) local t = (u == "target") and TEST.tgtBuffs or TEST.unitBuffs local b = t and t[i] if not b then return nil end return b.tex, b.apps or 0 end -- 1.32.10 兜底枚举桩；1.54.0 target 分表；1.70.1 返回层数
IsAltKeyDown = function() return false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
UnitExists = function(u) return u == "target" and TEST.hasTarget or false end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
UnitAttackSpeed = function() return TEST.atkSpd or 0, TEST.atkSpdOff end
UnitCanAttack = function() return true end
-- ★1.70.28：本客户端实测返回带后缀的本地化名（"人型生物" 而非标准名 "人型"），
--   所以桩默认沿用该值；测试可用 TEST.creatureType 覆盖，用于验证「带后缀/不带后缀」两种都能匹配。
UnitCreatureType = function() return TEST.creatureType or "人型生物" end
IsActionInRange = function(slot) return TEST.inRange and TEST.inRange[slot] end -- 1.37.0：true=内 / 0=外 / nil=不测
UnitReaction = function() return 2 end
HasAction = function(slot) return slot <= 3 end -- 1.37.0 放开到 3（断筋近战参照槽）
GetActionText = function() return nil end
GetActionTexture = function(slot) return "tex" .. slot end
GetActionCooldown = function() return 0, 0 end
IsUsableAction = function() if TEST.usableRet then return TEST.usableRet.u, TEST.usableRet.noMana end return true end
IsCurrentAction = function(slot) return TEST.currentAction == slot end
SpellStopCasting = function() TEST.castStopped = true end
RunScript = function(code) TEST.runScript = code TEST.runScripts = TEST.runScripts or {} table.insert(TEST.runScripts, code) if code == "SpellStopCasting()" then TEST.castStopped = true end end -- 1.69.0 收集多条
AttackTarget = function() TEST.attackTried = true end
UseAction = function(slot) table.insert(TEST.used, slot) end
TargetNearestEnemy = function()
  TEST.targetSel = "nearEnemy"
  if TEST.nearby then -- 附近敌人循环模拟：依次选下一个名字
    TEST.nearIdx = (TEST.nearIdx or 0) + 1
    TEST.curTargetName = TEST.nearby[TEST.nearIdx]
  end
end
TargetUnit = function(u) TEST.targetSel = "unit:" .. tostring(u) end
TargetByName = function(n)
  TEST.targetSel = "name:" .. tostring(n)
  TEST.byNameArg = n
  if TEST.nearby then TEST.curTargetName = n end -- 还原目标模拟
end
TargetNearestFriend = function() TEST.targetSel = "nearFriend" end
TargetNearestPartyMember = function() TEST.targetSel = "nearParty" end
TargetNearestRaidMember = function() TEST.targetSel = "nearRaid" end
TargetLastEnemy = function() TEST.targetSel = "lastEnemy" end
TargetLastTarget = function() TEST.targetSel = "lastTarget" end
ClearTarget = function() TEST.targetSel = "clear" end
-- 物品使用桩（1.32.0）：TEST.bags = { [bag*100+slot] = { name=, tex=, count=, cd= } }
GetContainerNumSlots = function(bag) return (bag >= 0 and bag <= 4) and 2 or 0 end
GetContainerItemLink = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] return it and ("|Hitem:1|h[" .. it.name .. "]|h") or nil end
GetContainerItemInfo = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if not it then return nil end return it.tex, it.count or 1, false, it.q or 1, false end
GetContainerItemCooldown = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if it and it.cd then return 900, 60, 1 end return 0, 0, 1 end
UseContainerItem = function(bag, slot)
  TEST.usedItem = bag * 100 + slot
  TEST.sellCalls = (TEST.sellCalls or 0) + 1
  if TEST.consumeOnUse and not TEST.noSell and TEST.bags then TEST.bags[bag * 100 + slot] = nil end -- 1.68.2 仅工具箱段模拟成交消失
end
GetItemInfo = function(x) -- 1.69.1 售卖明细桩：TEST.itemInfo[名称] = { t=种类, st=子类 }（无条目=未缓存）
  local it = TEST.itemInfo and TEST.itemInfo[x]
  if not it then return nil end
  return it.name or x, "|Hitem:1|h[" .. tostring(x) .. "]|h", it.q or 0, 1, it.t, it.st, 1, "", "tex"
end
-- 地图定位桩（DataSearch.lua 地图图标）：本客户端 GetMapZones 忽略参数只答选中大陆（UnrealQuest 实测注释）
GetCurrentMapContinent = function() return 1 end
SetMapZoom = function(c, z) TEST.mapZooms = TEST.mapZooms or {} table.insert(TEST.mapZooms, tostring(c) .. "," .. tostring(z)) end
GetMapZones = function(_) return { "杜隆塔尔", "奥格瑞玛" } end
ShowUIPanel = function(_) TEST.shownUIPanel = (TEST.shownUIPanel or 0) + 1 end
WorldMapFrame = newMock()
-- 地图可见性桩（1.70.14）：DataSearch 的视图签名要读它——实测「关图后 GetViewedZone 仍报旧区域」，
-- 故可见性必须直接问帧。TEST.mapShown 驱动（nil=帧不可探测 → 退回只比区域）
WorldMapFrame.IsShown = function() return TEST.mapShown end
WorldMapButton = newMock()
-- 数据检索桩（DataSearch.lua）：迷你 UnrealQuestData——1 物品/4 单位/1 对象/1 任务/2 区域
UnrealQuestData = {
  items = { [2589] = { U = { [3] = 11.89, [40] = 29.04 }, O = { [-100] = 5.5 }, V = { [44] = 0 } } },
  ["items_zhCN"] = { [2589] = "亚麻布" },
  ["items_enUS"] = { [2589] = "Linen Cloth" },
  units = {
    [3] = { coords = { { 46.2, 9.3, 14, 25 } }, fac = "AH", lvl = "2" },
    [40] = { coords = { { 51.8, 84.7, 1637, 25 } }, fac = "H", lvl = "5", rnk = "3" }, -- rnk=3 世界Boss（图标断言用）
    [44] = { coords = {}, fac = "A", lvl = "10" },
    [99] = { coords = { { 1, 1, 14, 0 } }, fac = "AH", lvl = "9" },
  },
  ["units_zhCN"] = { [3] = "食腐者", [40] = "狗头人矿工", [44] = "商人贝利" },
  ["units_enUS"] = { [3] = "Scavenger", [40] = "Kobold Miner", [44] = "Vendor Belly", [99] = "OnlyEnglishMob" },
  objects = { [-100] = { coords = { { 10, 20, 14, 0 } }, fac = "AH" } },
  ["objects_zhCN"] = { [-100] = "旧木箱" },
  quests = { [1] = { lvl = 4, min = 1, ["start"] = { U = { 3 } }, ["end"] = { U = { 3 } }, obj = { I = { 2589 } } } },
  ["quests_zhCN"] = { [1] = { T = "收集亚麻布", O = "收集 10 块亚麻布。", D = "帮我收集一些亚麻布。" } },
  ["quests_enUS"] = { [1] = { T = "Gather Linen", O = "Gather 10 Linen Cloth.", D = "Help me." } },
  zones = { [14] = { 12, 1, 1, 0, 0 }, [1637] = { 33, 1, 1, 0, 0 } },
  ["zones_zhCN"] = { [14] = "杜隆塔尔", [1637] = "奥格瑞玛" },
  ["zones_enUS"] = { [14] = "Durotar", [1637] = "Orgrimmar" },
}
-- 工具箱桩（1.68.0）
GetMoney = function() return 1000000 end
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return TEST.repairCost or 0 end
RepairAllItems = function() TEST.repaired = true end
GetMerchantNumItems = function() return TEST.merchant and table.getn(TEST.merchant) or 0 end
GetMerchantItemInfo = function(i) local m = TEST.merchant and TEST.merchant[i] if not m then return nil end return m.name, "tex", m.price or 1, 1, m.avail or -1, true end
BuyMerchantItem = function(i, n) local m = TEST.merchant and TEST.merchant[i] TEST.bought = (TEST.bought or "") .. tostring(m and m.name) .. "x" .. tostring(n) .. ";" end
PickupContainerItem = function(b, s) TEST.picked = b * 100 + s end
DeleteCursorItem = function() if TEST.picked then TEST.deleted = TEST.picked TEST.picked = nil end end
ConfirmReadyCheck = function() TEST.readyChecked = true end
-- 1.69.0 任务日志扫描桩（TEST.questLog = { {title=, complete=, objs={{txt=,d=,m=}}} }）
GetNumQuestLogEntries = function() return table.getn(TEST.questLog or {}) end
GetQuestLogTitle = function(i)
  local q = TEST.questLog and TEST.questLog[i]
  if q then return q.title, q.lvl or 1, nil, nil, nil, q.complete and 1 or nil end
end
GetQuestLogLeaderBoard = function(oi, qi)
  local q = TEST.questLog and TEST.questLog[qi]
  local o = q and q.objs and q.objs[oi]
  if o then return o.txt, "monster", o.d, o.m end
end
AcceptQuest = function() TEST.questAccepted = true end
CompleteQuest = function() TEST.questCompleted = true end
IsQuestCompletable = function() return TEST.questCompletable or false end
GetNumQuestChoices = function() return TEST.questChoices or 0 end
GetQuestReward = function(c) TEST.questReward = c or 0 end
SetCVar = function(k, v) TEST.cvars = TEST.cvars or {} TEST.cvars[k] = tostring(v) end
GetCVar = function(k) return (TEST.cvars and TEST.cvars[k]) or "0" end
