-- fengari 测试桩：模拟本客户端 WoW API 环境（Lua 5.1 垫片 + UI mock + 战斗 API）
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
getglobal = getglobal or function(n) return _G[n] end

TEST = { used = {}, targetClass = "WARRIOR", hasTarget = true, slotNames = { [1] = "致死打击", [2] = "冲锋" }, debuffs = {}, buffs = {} }

local function newMock()
  local m = {}
  setmetatable(m, { __index = function(_, k)
    if k == "CreateTexture" or k == "CreateFontString" then return function() return newMock() end end
    return function() return nil end
  end })
  return m
end
function CreateFrame() return newMock() end
UIParent = newMock()
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

GetTime = function() return 1000 end
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
UnitBuff = function(u, i) local t = (u == "target") and TEST.tgtBuffs or TEST.unitBuffs local b = t and t[i] return b and b.tex or nil end -- 1.32.10 兜底枚举桩；1.54.0 target 分表
IsAltKeyDown = function() return false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
UnitExists = function(u) return u == "target" and TEST.hasTarget or false end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
UnitCanAttack = function() return true end
UnitCreatureType = function() return "人型生物" end
IsActionInRange = function(slot) return TEST.inRange and TEST.inRange[slot] end -- 1.37.0：true=内 / 0=外 / nil=不测
UnitReaction = function() return 2 end
HasAction = function(slot) return slot <= 3 end -- 1.37.0 放开到 3（断筋近战参照槽）
GetActionText = function() return nil end
GetActionTexture = function(slot) return "tex" .. slot end
GetActionCooldown = function() return 0, 0 end
IsUsableAction = function() return true end
IsCurrentAction = function(slot) return TEST.currentAction == slot end
SpellStopCasting = function() TEST.castStopped = true end
RunScript = function(code) TEST.runScript = code if code == "SpellStopCasting()" then TEST.castStopped = true end end
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
GetContainerItemInfo = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if not it then return nil end return it.tex, it.count or 1, false, 1, false end
GetContainerItemCooldown = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if it and it.cd then return 900, 60, 1 end return 0, 0, 1 end
UseContainerItem = function(bag, slot) TEST.usedItem = bag * 100 + slot end
GetItemInfo = function() return nil end
