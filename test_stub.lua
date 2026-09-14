-- fengari 测试桩：模拟本客户端 WoW API 环境（Lua 5.1 垫片 + UI mock + 战斗 API）
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
getglobal = getglobal or function(n) return _G[n] end

TEST = { used = {}, targetClass = "WARRIOR", hasTarget = true, slotNames = { [1] = "致死打击", [2] = "冲锋" } }

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
GameTooltipTextLeft1 = { GetText = function() return TEST.slotNames[TEST.curSlot or 0] end }
GameTooltip = {
  SetOwner = function() end, ClearLines = function() end, Hide = function() end,
  SetAction = function(_, slot) TEST.curSlot = slot return true end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) TEST.chat = (TEST.chat or "") .. tostring(msg) .. "\n" end }

GetTime = function() return 1000 end
UnitName = function(u) return u == "player" and "测试玩家" or "测试怪" end
UnitLevel = function() return 60 end
UnitClass = function(u) if u == "target" then return "战士", TEST.targetClass, 1 end return "战士", "WARRIOR", 1 end
UnitHealth = function() return 80 end
UnitHealthMax = function() return 100 end
UnitMana = function() return 50 end
UnitManaMax = function() return 100 end
UnitPowerType = function() return 1 end
UnitAffectingCombat = function() return false end
GetShapeshiftFormInfo = function() return nil end
GetPlayerBuff = function() return -1 end
GetPlayerBuffTexture = function() return nil end
UnitDebuff = function() return nil end
IsAltKeyDown = function() return false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
UnitExists = function(u) return u == "target" and TEST.hasTarget or false end
UnitIsDeadOrGhost = function() return false end
UnitCanAttack = function() return true end
UnitCreatureType = function() return "人型生物" end
UnitClassification = function() return "normal" end
UnitReaction = function() return 2 end
HasAction = function(slot) return slot <= 2 end
GetActionText = function() return nil end
GetActionTexture = function(slot) return "tex" .. slot end
GetActionCooldown = function() return 0, 0 end
IsUsableAction = function() return true end
IsCurrentAction = function() return false end
UseAction = function(slot) table.insert(TEST.used, slot) end
TargetNearestEnemy = function() TEST.targetSel = "nearEnemy" end
TargetNearestFriend = function() TEST.targetSel = "nearFriend" end
TargetNearestPartyMember = function() TEST.targetSel = "nearParty" end
TargetNearestRaidMember = function() TEST.targetSel = "nearRaid" end
TargetLastEnemy = function() TEST.targetSel = "lastEnemy" end
TargetLastTarget = function() TEST.targetSel = "lastTarget" end
ClearTarget = function() TEST.targetSel = "clear" end
