-- ============================================================================
-- EH_DPS · 个人伤害统计表（自娱自乐版）独立子插件
-- ----------------------------------------------------------------------------
-- 定位：只统计「自己 + 宠物」的输出/承伤/治疗/能量/击杀，按技能分解。
--   ★准确度不保证：事件源 = CHAT_MSG_* 文本解析（SCT 模式），本客户端没有
--     结构化战斗事件、没有 GUID API（1329 条 API 索引在案，三轮调研定案）。
--   ★句式 = zhCN 尽力而为：模式表照 EH_Damage 真机校准成果起手，
--     未识别的战斗文本走捕获环（/edps 捕获 → /edps 事件）供逐条校准。
--   ★绝不引入 GetUnitGUID / Nampower 依赖（反向钉）。
-- 客户端配方（项目既有判据）：
--   · OnUpdate 零形参：dt 从全局 arg1 取，取不到用 GetTime() 差值推。
--   · 节拍帧宿主 = WorldFrame（开全屏地图会隐藏 UIParent）。
--   · 一个模块只许一个节拍帧，挂/摘唯一入口 beatSync()。
--   · 拖动柄必须用 Button（Frame 的 OnDragStart 不触发）。
--   · 纯色纹理只有 Interface\Buttons\WHITE8X8 + SetVertexColor 可靠。
--   · 字体链 GameFontNormal 系列全程 pcall；SendChatMessage 是 Protected
--     ⇒ 报告走 pcall(RunScript, ...)，且 0.6s 滴出限频（RunScript 也是队列）。
-- ============================================================================

local BUILD = "0.2.5"

local D = {}                      -- 命名空间（跨函数共享件全挂这里，控 local 数）
_G["EH_DPS"] = D                  -- 调试/桥接口（子插件独立，不依赖宿主）

-- ----------------------------------------------------------------------------
-- 配置与默认值（存档 = EH_DPS_CFG；记忆体分离：绝不碰 EVAL_HELP_* ）
-- ----------------------------------------------------------------------------
local DEF = {
  master = true,        -- 总开关（默认开：新插件即装即用）
  view = 1,             -- 当前视图序号（见 VIEWS）
  seg = 1,              -- 当前段：1=当前战斗 0=全程
  capture = false,      -- 诊断：未识别战斗文本落环
  reportCh = "SAY",     -- 报告频道 SAY/PARTY/RAID
  px = nil, py = nil,   -- 窗口位置记忆（左上角，屏幕坐标 ÷ 有效缩放）
  pw = 232, pr = 10,    -- 窗口逻辑宽度 / 可见行数（右下角拖拽柄调整，落存档）
  scale = 1.0,          -- 整窗缩放（Ctrl+滚轮；几何重建，不走 SetScale —— 点击框漂移在案）
  rowH = 22,            -- 条目高度基准（配置面板可调 22~30，缩放前逻辑值；0.1.3 起默认 22）
  bgAlpha = 0.50,       -- 背景黑色透明度（配置面板可调 0.30~1.00；0.2.2 起默认 0.50）
}

-- 视图定义（0.2.0 起**全部队伍级**：每行 = 一个玩家；点行下钻他的技能分解）：
--   key = PKEY 键（数据源）；perSec = 按该玩家活跃时间折算每秒；count = 计数类（不算占比）；
--   col = 标题配色（0.1.2 用户定：不同统计类型不同颜色、鲜艳一点；0.1.3 队伍伤害不用红）
local VIEWS = {
  { id = "dmg",     zh = "伤害量",   key = "dmg",   perSec = false, col = { 1.00, 0.80, 0.30 } },  -- 0.2.1：红 → 亮金黄（黑底上看不清，用户定）
  { id = "dps",     zh = "DPS",      key = "dmg",   perSec = true,  col = { 1.00, 0.55, 0.10 } },
  { id = "heal",    zh = "治疗量",   key = "heal",  perSec = false, col = { 0.30, 1.00, 0.40 } },
  { id = "hps",     zh = "HPS",      key = "heal",  perSec = true,  col = { 0.50, 1.00, 0.60 } },
  { id = "taken",   zh = "承受伤害", key = "taken", perSec = false, col = { 0.80, 0.40, 1.00 } },
  { id = "healT",   zh = "受到治疗", key = "healT", perSec = false, col = { 0.40, 0.90, 0.80 } },
  { id = "ener",    zh = "能量回复", key = "ener",  perSec = false, col = { 0.35, 0.65, 1.00 } },
  { id = "kills",   zh = "击杀",     key = "kills", perSec = false, count = true, col = { 1.00, 0.85, 0.20 } },
  { id = "casts",   zh = "施放次数", key = "casts", perSec = false, count = true, col = { 0.40, 0.90, 1.00 } },
}

-- 职业色表（vanilla 经典色；键 = UnitClass 第二返回的英文 token）
local CLASS_RGB = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
  ROGUE   = { 1.00, 0.96, 0.41 }, PRIEST  = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
  MAGE    = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, DRUID  = { 1.00, 0.49, 0.04 },
}

-- 能量类型 token → 中文（真机句式里是未翻译 token：RAGE_POINTS 等）
local POWER_ZH = { RAGE_POINTS = "怒气", MANA = "法力", ENERGY = "能量", FOCUS = "集中值", HAPPINESS = "快乐" }

local say                                   -- 前向声明（cfgEnsure 之前的调用点要用）

local function cfgEnsure()
  local c = rawget(_G, "EH_DPS_CFG")
  if type(c) ~= "table" then c = {} rawset(_G, "EH_DPS_CFG", c) end
  for k, v in pairs(DEF) do if c[k] == nil then c[k] = v end end
  -- ★0.2.2 默认档迁移：旧默认 0.85 → 0.50（只升确切旧默认值一次 + 出声；用户自己调过的档不动）
  if c.bgAlpha == 0.85 and c.bgAlphaMig ~= true then
    c.bgAlpha = 0.50
    c.bgAlphaMig = true
    if type(say) == "function" then say("背景透明度默认档改为 50%（要调回：标题 [设] → 背景透明度）") end
  end
  if type(c.ring) ~= "table" then c.ring = {} end
  return c
end
local function C() return cfgEnsure() end

-- ----------------------------------------------------------------------------
-- 小工具
-- ----------------------------------------------------------------------------
say = function(m)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f and f.AddMessage then pcall(f.AddMessage, f, "|cffffaa00[EH_DPS]|r " .. tostring(m)) end
end

local RING_MAX = 40
local function ringPush(line)
  local c = C()
  table.insert(c.ring, tostring(line))
  while table.getn(c.ring) > RING_MAX do table.remove(c.ring, 1) end
end

local function capture(ev, msg)
  if C().capture then ringPush(tostring(ev) .. " | " .. tostring(msg)) end
end

local function numOf(msg) return tonumber(string.match(msg, "(%d+)")) end
local function isCrit(msg) return string.find(msg, "致命") ~= nil end

-- ----------------------------------------------------------------------------
-- 数据模型（0.2.0 起全队伍级）：双段（[0]=全程 / [1]=当前战斗）
--   每段 seg.p[玩家名] = { dmg/heal/taken/healT/ener/kills/casts = 总量,
--     dmgD/healD/takenD/healTD/enerD/castD = 按技能(来源)分解（下钻明细）,
--     actT/actTick = 该玩家的活跃时间（EDPS 5 秒规则）}
--   seg.fightT = 战斗总时长
-- ----------------------------------------------------------------------------
local function newSeg()
  return { p = {}, fightT = 0 }
end

-- 玩家记录字段 ↔ 视图键（唯一映射口）
local PKEY = {
  dmg = { sum = "dmg", det = "dmgD" },
  heal = { sum = "heal", det = "healD" },
  taken = { sum = "taken", det = "takenD" },
  healT = { sum = "healT", det = "healTD" },
  ener = { sum = "ener", det = "enerD" },
  kills = { sum = "kills", det = "killD" },
  casts = { sum = "casts", det = "castD" },
}

D.data = nil            -- VARIABLES_LOADED 时才建/恢复
D.combatStart = 0       -- 进战时刻（0 = 不在战斗）

local function dataEnsure()
  if not D.data then
    D.data = { [0] = newSeg(), [1] = newSeg() }
  end
  return D.data
end

-- 活跃时间（抄 ShaguDPS 的 5 秒规则）：距上次活跃 >5s 按 +5s 计，否则按实际差
local function touchActiveP(p)
  local now = GetTime and GetTime() or 0
  if p.actTick == 0 then
    p.actT = 1
  elseif p.actTick + 5 < now then
    p.actT = p.actT + 5
  else
    p.actT = p.actT + (now - p.actTick)
  end
  p.actTick = now
end

-- 持久化：脱战/手动重置时把全程段存进存档（跨 /reload 恢复）
function D.SaveData()
  local c = C()
  local dd = dataEnsure()
  c.data0 = dd[0]
  c.fightT0 = dd[0].fightT
end

function D.LoadData()
  local c = C()
  local dd = dataEnsure()
  -- ★0.2.0 数据模型换代：旧档（带 dmg 键的扁平表）识别出来就丢弃（结构读不回，不硬迁）
  if type(c.data0) == "table" and type(c.data0.p) == "table" then
    dd[0] = c.data0
    dd[0].fightT = c.fightT0 or dd[0].fightT or 0
  elseif type(c.data0) == "table" then
    c.data0 = nil
    say("旧版统计数据结构不兼容，全程段已清空（当前战斗不受影响）")
  end
end

-- 统一写入口（唯一记账口）：kind = PKEY 键；name = 玩家名；spell = 明细键（技能/来源）
--   ★名册闸：不在队伍名册（含自己）的一律不记
local function bumpP(kind, name, n, spell, active)
  if type(name) ~= "string" or name == "" or not tonumber(n) then return end
  if not D.partyNames[name] then return end
  local pk = PKEY[kind]
  if not pk then return end
  local dd = dataEnsure()
  for s = 0, 1 do
    local seg = dd[s]
    local p = seg.p[name]
    if not p then
      p = { dmg = 0, heal = 0, taken = 0, healT = 0, ener = 0, kills = 0, casts = 0,
            dmgD = {}, healD = {}, takenD = {}, healTD = {}, enerD = {}, castD = {}, killD = {},
            actT = 0, actTick = 0 }
      seg.p[name] = p
    end
    p[pk.sum] = p[pk.sum] + n
    if spell and pk.det then p[pk.det][spell] = (p[pk.det][spell] or 0) + n end
    if active then touchActiveP(p) end
  end
  D.dirty = true
end

-- ----------------------------------------------------------------------------
-- 队伍名册（队伍级统计的过滤闸：不在名册里的名字一律不记，防路人/主城污染）
--   顺带记职业（UnitClass 第二返回 token）⇒ 条目职业染色（0.1.2）
-- ----------------------------------------------------------------------------
D.partyNames = {}
D.partyClass = {}
local function partyRefresh()
  local t, tcls = {}, {}
  if type(UnitName) == "function" then
    local pn = UnitName("player")
    if pn then t[pn] = true end
    local units = {}
    if type(GetNumRaidMembers) == "function" and GetNumRaidMembers() > 0 then
      for i = 1, 40 do units[i] = "raid" .. i end
    elseif type(GetNumPartyMembers) == "function" then
      for i = 1, 4 do units[i] = "party" .. i end
    end
    for _, u in ipairs(units) do
      local n = UnitName(u)
      if n then t[n] = true end
    end
    -- 职业：player + 队伍/团队成员逐个取（拿不到就缺着，染色退回灰）
    if type(UnitClass) == "function" then
      local function putCls(u)
        local n = UnitName(u)
        if not n then return end
        local ok, _, tok = pcall(UnitClass, u)
        if ok and tok then tcls[n] = tok end
      end
      putCls("player")
      for _, u in ipairs(units) do putCls(u) end
    end
  end
  D.partyNames = t
  D.partyClass = tcls
end
D.partyRefresh = partyRefresh

-- 职业染色助手：名字 → {r,g,b}（认不出职业 = 灰）
--   ★0.2.5 用户定：用**标准职业色**（不再提亮），条目条**不透明**（alpha 1.0，Refresh 里）
local function classRGB(name)
  local tok = D.partyClass[name]
  local c = tok and CLASS_RGB[tok] or nil
  if not c then return { 0.82, 0.82, 0.82 } end
  return { c[1], c[2], c[3] }
end

-- ★记账唯一口 = bumpP（见数据模型段；名册闸在里面，不在名册的名字一律不记）

-- ----------------------------------------------------------------------------
-- 事件解析（SCT 模式）
-- ----------------------------------------------------------------------------
local EVH = {}

-- 击杀去重：本客户端同一只怪发两条（「你杀死了X！」+「X死亡了。」）
--   ★表有界（断线审计收口）：按怪名累积会无界增长 ⇒ 超 100 条整表清（2s 去重窗短，清了无害）
D.killRecent = {}
local function killOnce(name)
  if not name or name == "" then return false end
  local n = 0
  for _ in pairs(D.killRecent) do n = n + 1 end
  if n > 100 then D.killRecent = {} end
  local now = GetTime and GetTime() or 0
  if D.killRecent[name] and (now - D.killRecent[name]) < 2 then return false end
  D.killRecent[name] = now
  return true
end

-- 自己名字（名册里有自己；取不到退回「我」）
local function selfName()
  if type(UnitName) == "function" then
    local n = UnitName("player")
    if n then return n end
  end
  return "我"
end

-- 自己平砍：「你击中大峭壁野猪造成12点伤害。」
EVH["CHAT_MSG_COMBAT_SELF_HITS"] = function(m)
  local n = numOf(m)
  if not n then capture("SELF_HIT-NONUM", m) return end
  bumpP("dmg", selfName(), n, "自动攻击", true)
end

-- 自己技能：「你的 撕裂 使 噬骨者 受到了 9 点物理伤害。」；无数字的「你开始进行撕裂。」计施放
EVH["CHAT_MSG_SPELL_SELF_DAMAGE"] = function(m)
  local sp = string.match(m, "^你的%s*(.-)%s*使") or string.match(m, "^你的%s*(.-)%s*击中")
          or string.match(m, "^你的%s*(.-)%s*对")
  local n = numOf(m)
  if not n then
    local cast = string.match(m, "^你开始进行%s*(.-)。") or string.match(m, "^你开始施放%s*(.-)。")
    if cast then bumpP("casts", selfName(), 1, cast) else capture("SELF_SPELL?", m) end
    return
  end
  bumpP("dmg", selfName(), n, sp or "技能", true)
end

-- 自己 DoT：「你的撕裂使大峭壁野猪受到了5点物理伤害。」
--   ★归属门（EH_Damage 0.2.24 真机定案）：这族事件来源不限，附近任何人的 DoT 都会进来
--     ⇒ 不是「你」开头的一律不记 + 落环（反向钉：这条门不许删）
local function dotDamage(m)
  if not string.find(m, "^你") then capture("DOT-OTHER", m) return end
  local n = numOf(m)
  if not n then capture("DOT-NONUM", m) return end
  local sp = string.match(m, "^你的%s*(.-)%s*使") or string.match(m, "^你的%s*(.-)%s*击中")
          or string.match(m, "^你的%s*(.-)%s*对")
  bumpP("dmg", selfName(), n, (sp or "持续伤害") .. "(DoT)", true)
end
EVH["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"] = dotDamage
EVH["CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"] = dotDamage

-- 宠物伤害：并入主人，技能名加「宠物·」前缀（句式未校准，先取数字；原文落环校准）
EVH["CHAT_MSG_COMBAT_PET_HITS"] = function(m)
  local n = numOf(m)
  if not n then capture("PET_HIT-NONUM", m) return end
  bumpP("dmg", selfName(), n, "宠物·攻击", true)
end
EVH["CHAT_MSG_SPELL_PET_DAMAGE"] = function(m)
  local n = numOf(m)
  if not n then capture("PET_SPELL-NONUM", m) return end
  bumpP("dmg", selfName(), n, "宠物·技能", true)
end

-- 自我治疗：「你的 次级治疗术 治疗了你 154 点生命值。」「…对你造成极效治疗，恢复了 247 点生命值。」
--   ★技能名必须吃到「治疗了」为止：「次级治疗术」自己含「治疗」，lazy 匹配会在词中截断
--   ★自我治疗 = 治疗者与自己同一人：heal 与 healT 一起记
EVH["CHAT_MSG_SPELL_SELF_BUFF"] = function(m)
  local sp = string.match(m, "^你的%s*(.-)%s*治疗了") or string.match(m, "^你的%s*(.-)%s*对你造成")
          or string.match(m, "^你的%s*(.-)%s*治疗")
  local n = string.match(m, "治疗了你%s*(%d+)%s*点") or string.match(m, "治疗你%s*(%d+)%s*点")
         or string.match(m, "恢复了%s*(%d+)%s*点") or string.match(m, "(%d+)%s*点")
  if not n then return end    -- 无数字 = 施加 buff 类文本，不是治疗跳
  bumpP("heal", selfName(), tonumber(n), sp or "治疗", true)
  bumpP("healT", selfName(), tonumber(n), sp or "治疗")
end

-- ★治疗统一解析（0.2.0；三族 BUFF 事件共用）：
--   「你因 losol 的 恢复 而获得了 40 点生命值。」= X 治疗我（HOSTILEPLAYER 实测句式）
--   「队友乙的次级治疗术治疗了我80点生命值。」= X 治疗我
--   「X的Y治疗了Z…/为Z恢复…」= X 治疗 Z
--   两侧都过名册闸：治疗者进 heal，被治疗者进 healT
local function healMsg(m)
  local n = string.match(m, "获得了%s*(%d+)%s*点") or string.match(m, "获得%s*(%d+)%s*点")
         or string.match(m, "治疗了.-(%d+)%s*点") or string.match(m, "治疗你%s*(%d+)%s*点")
         or string.match(m, "恢复了%s*(%d+)%s*点") or string.match(m, "恢复%s*(%d+)%s*点")
         or string.match(m, "(%d+)%s*点")
  if not n then return end    -- 无数字 = buff 施加类文本
  n = tonumber(n)
  local healer, sp = string.match(m, "^你因%s*(.-)%s*的%s*(.-)%s*而")
  if healer then
    bumpP("heal", healer, n, sp or "治疗")
    bumpP("healT", selfName(), n, healer)
    return
  end
  local src, spell = string.match(m, "^(.-)的(.-)治疗了")
  if not src then src, spell = string.match(m, "^(.-)的(.-)为.-恢复") end
  if not src then return end
  bumpP("heal", src, n, spell or "治疗")
  -- 被治疗者：治疗了我 → 自己；治疗了Z / 为Z恢复 → Z
  local tgt = string.match(m, "治疗了%s*(.-)%s*" .. n .. "%s*点") or string.match(m, "为%s*(.-)%s*恢复")
  if tgt == "我" or tgt == "你" then tgt = selfName() end
  if tgt then bumpP("healT", tgt, n, src) end
end
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]  = healMsg
EVH["CHAT_MSG_SPELL_PARTY_BUFF"]          = healMsg
EVH["CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF"] = healMsg

-- ★队伍成员伤害（句式尽力而为；名册过滤，不在队伍里的名字不记）：
--   「队友甲击中大峭壁野猪造成15点伤害。」「队友甲的寒冰箭击中X造成N点伤害。」DoT 走「使…受到」
local function partyHit(m)
  local n = numOf(m)
  if not n then capture("PARTY_HIT-NONUM", m) return end
  local src, sp = string.match(m, "^(.-)的(.-)击中")
  if not src then src, sp = string.match(m, "^(.-)的(.-)使") if sp then sp = sp .. "(DoT)" end end
  if not src then src = string.match(m, "^(.-)击中") sp = "自动攻击" end
  if src then bumpP("dmg", src, n, sp or "技能", true) else capture("PARTY_HIT-SRC", m) end
end
EVH["CHAT_MSG_COMBAT_PARTY_HITS"]                    = partyHit
EVH["CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS"]           = partyHit
EVH["CHAT_MSG_SPELL_PARTY_DAMAGE"]                   = partyHit
EVH["CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE"]          = partyHit
EVH["CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE"]          = partyHit
EVH["CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE"] = partyHit

-- 名册变动 → 重建名册
EVH["PARTY_MEMBERS_CHANGED"]  = function() partyRefresh() end
EVH["RAID_ROSTER_UPDATE"]     = function() partyRefresh() end
EVH["PLAYER_ENTERING_WORLD"]  = function() partyRefresh() end

-- 能量获取：「你从 怒不可遏 获得了 1 点 RAGE_POINTS。」（? 按字节作用 ⇒ 两条模式分别试）
EVH["CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"] = function(m)
  local n, pw = string.match(m, "^你从.-获得%s*(%d+)%s*点(.-)。")
  if not n then n, pw = string.match(m, "^你从.-获得了%s*(%d+)%s*点(.-)。") end
  if not n then n, pw = string.match(m, "^你获得(%d+)点(.+)") end
  if not n then n, pw = string.match(m, "^你获得了(%d+)点(.+)") end
  if not n then return end    -- buff 获得类文本，不归我们管
  pw = string.gsub(tostring(pw or ""), "^%s*(.-)%s*$", "%1")
  pw = POWER_ZH[pw] or pw
  local src = string.match(m, "^你从%s*(.-)%s*获得") or "被动"
  bumpP("ener", selfName(), tonumber(n), src .. "(" .. pw .. ")", true)
end

-- 承受伤害（自己被打）：「噬骨者击中你造成32点伤害。」（裸名字负载守卫：提不出数字就不记）
local function inHit(m)
  local n = numOf(m)
  if not n then capture("INCOMING-NONUM", m) return end
  local src = string.match(m, "^(.-)的.-击中你") or string.match(m, "^(.-)的.-对你造成")
           or string.match(m, "^(.-)击中你") or string.match(m, "^(.-)对你造成") or "未知"
  bumpP("taken", selfName(), n, src)
end
EVH["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"]  = inHit
EVH["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"]      = inHit
EVH["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"]  = inHit
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"]     = inHit

-- ★承受伤害（队友被打，0.2.0；「怪打队友」事件真机已实证派发）：
--   「峭壁野猪击中队友甲造成9点伤害。」「X的Y击中队友甲造成N点」⇒ 按受害者记 taken
local function inHitParty(m)
  local n = numOf(m)
  if not n then capture("PARTY_IN-NONUM", m) return end
  local victim = string.match(m, "击中%s*(.-)%s*造成")
  local src = string.match(m, "^(.-)的.-击中") or string.match(m, "^(.-)击中") or "未知"
  if victim then bumpP("taken", victim, n, src) else capture("PARTY_IN-VICTIM", m) end
end
EVH["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS"]  = inHitParty
EVH["CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE"] = inHitParty

-- 击杀：「你杀死了大峭壁野猪！」与「大峭壁野猪死亡了。」同怪两条 ⇒ 2s 同名去重
--   ★只能认出「我杀的」（文本不署别人的名）⇒ 击杀视图 = 自己一行
--   ★多字节坑：`[！!]` 是按字节的字符集，会把「！」拆半个进名字 ⇒ 用整字后缀剥除
EVH["CHAT_MSG_COMBAT_HOSTILE_DEATH"] = function(m)
  local name = string.match(m, "^你杀死了(.+)$")
  if name then
    name = string.gsub(name, "！$", "")
    name = string.gsub(name, "!$", "")
  end
  if not name then name = string.match(m, "^(.+)死亡了。") end
  if name and killOnce(name) then
    bumpP("kills", selfName(), 1, name)
  end
end

-- 进/脱战：分段与战斗时长
EVH["PLAYER_REGEN_DISABLED"] = function()
  local dd = dataEnsure()
  dd[1] = newSeg()
  D.combatStart = GetTime and GetTime() or 0
  D.dirty = true
end
EVH["PLAYER_REGEN_ENABLED"] = function()
  local now = GetTime and GetTime() or 0
  if D.combatStart > 0 then
    local dd = dataEnsure()
    local dur = now - D.combatStart
    dd[1].fightT = dur
    dd[0].fightT = (dd[0].fightT or 0) + dur
    D.combatStart = 0
  end
  D.SaveData()
  D.dirty = true
end

-- 事件注册清单（逐个 pcall 试；不存在的事件名客户端静默忽略）
local EVENTS = {
  "CHAT_MSG_COMBAT_SELF_HITS",
  "CHAT_MSG_SPELL_SELF_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_SPELL_PET_DAMAGE",
  "CHAT_MSG_SPELL_SELF_BUFF",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS", "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
  "CHAT_MSG_COMBAT_HOSTILE_DEATH",
  "CHAT_MSG_COMBAT_PARTY_HITS", "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS",
  "CHAT_MSG_SPELL_PARTY_DAMAGE", "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
  "CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
}

D.evFrame = nil
local function eventSync()
  if type(CreateFrame) ~= "function" then return end
  local want = C().master == true
  if not D.evFrame then
    D.evFrame = CreateFrame("Frame", "EH_DPS_EVENT")
    D.evFrame:SetScript("OnEvent", function()
      local ev = rawget(_G, "event")
      local m = rawget(_G, "arg1")
      -- 深度捕获：开着捕获时全部 CHAT_MSG_ 负载原文落环（校准用）
      if C().capture and ev and string.sub(ev, 1, 9) == "CHAT_MSG_" then
        ringPush("RAW " .. tostring(ev) .. " |1=" .. tostring(m) ..
          " |2=" .. tostring(rawget(_G, "arg2")) .. " |3=" .. tostring(rawget(_G, "arg3")))
      end
      local h = ev and EVH[ev] or nil
      if h then
        local ok, err = pcall(h, m)
        if not ok then ringPush("ERR " .. tostring(ev) .. " | " .. tostring(err)) end
      end
    end)
  end
  for _, ev in ipairs(EVENTS) do
    if want then pcall(D.evFrame.RegisterEvent, D.evFrame, ev)
    else pcall(D.evFrame.UnregisterEvent, D.evFrame, ev) end
  end
end
D.eventSync = eventSync

-- ----------------------------------------------------------------------------
-- 窗口 UI（进度条表；视图循环 + 当前/全程切换 + 报告 + 重置 + 右下角拖拽改尺寸）
-- ----------------------------------------------------------------------------
local ROW_MAX = 20        -- 行池上限（1.12 无销毁 API ⇒ 建一次、只 Show/Hide）
local ROW_MIN = 4
local WIN_W = 232         -- 默认宽（真值 = 配置 pw）
local W_MIN, W_MAX = 180, 400

local function solid(t, r, g, b, a)
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") end
  pcall(t.SetVertexColor, t, r, g, b, a)
end

local function mkFont(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormalSmall) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormalSmall)
  elseif type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  -- ★去阴影（0.1.3 用户定：黑底上字体对象自带的阴影看不清）⇒ 所有文字统一关阴影
  pcall(fs.SetShadowColor, fs, 0, 0, 0, 0)
  pcall(fs.SetShadowOffset, fs, 0, 0)
  return fs
end

-- 收集当前视图的行数据：{ {name, value, raw}, ... } 按数值降序，返回 rows, total, best
--   ★0.2.0 全部视图队伍级：每行 = 一个玩家（seg.p[名]）；perSec 用该玩家自己的活跃时间
--   ★下钻模式（D.detail = 玩家名）：改出该玩家的技能/来源分解（PKEY[key].det）
local function viewRows()
  local c = C()
  local v = VIEWS[c.view] or VIEWS[1]
  local pk = PKEY[v.key]
  local dd = dataEnsure()
  local seg = dd[c.seg == 0 and 0 or 1]
  local rows, total, best = {}, 0, 0
  if D.detail and pk and pk.det then
    local p = seg.p[D.detail]
    local det = (p and p[pk.det]) or {}
    for name, raw in pairs(det) do
      if type(raw) == "number" and raw > 0 then
        table.insert(rows, { name = name, raw = raw, value = raw })
        total = total + raw
        if raw > best then best = raw end
      end
    end
    table.sort(rows, function(a, b) return a.value > b.value end)
    while table.getn(rows) > ROW_MAX do table.remove(rows) end
    return rows, total, best, v, seg
  end
  for name, p in pairs(seg.p) do
    local raw = pk and p[pk.sum] or 0
    if type(raw) == "number" and raw > 0 then
      local secs = p.actT or 1
      if secs < 1 then secs = 1 end
      local val = v.perSec and (raw / secs) or raw
      table.insert(rows, { name = name, raw = raw, value = val })
      total = total + (v.count and 0 or raw)      -- 计数类不算总量占比
      if val > best then best = val end
    end
  end
  table.sort(rows, function(a, b) return a.value > b.value end)
  while table.getn(rows) > ROW_MAX do table.remove(rows) end
  return rows, total, best, v, seg
end

local function fmtNum(n)
  if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
  if n >= 10000 then return string.format("%.1fK", n / 1000) end
  if n >= 100 then return string.format("%.0f", n) end
  return string.format("%.1f", n)
end

-- 布局：按配置 pw/pr/scale 现算全部几何（唯一几何口；行池 ROW_MAX 建一次只 Show/Hide）
--   ★缩放 = 几何重建（本项目禁用 SetScale：点击框漂移在案）；z 只放大框体/条/按钮 ——
--     本客户端文字不吃缩放（EH_Damage 字号 saga 定案），字号不变是客户端限制，如实告知。
local function clampN(n, lo, hi) if n < lo then return lo end if n > hi then return hi end return n end
local Z_MIN, Z_MAX = 0.6, 1.6
function D.Layout()
  local ui = D.ui
  if not ui then return end
  local c = C()
  c.pw = clampN(tonumber(c.pw) or WIN_W, W_MIN, W_MAX)
  c.pr = clampN(tonumber(c.pr) or 10, ROW_MIN, ROW_MAX)
  c.scale = clampN(tonumber(c.scale) or 1, Z_MIN, Z_MAX)
  c.rowH = clampN(tonumber(c.rowH) or 22, 22, 30)   -- 0.1.3 起默认/下限 22（旧档 16 被下界自动顶到 22）
  c.bgAlpha = clampN(tonumber(c.bgAlpha) or 0.85, 0.30, 1.00)
  local z = c.scale
  local w = math.floor(c.pw * z + 0.5)
  local rowH = math.floor(c.rowH * z + 0.5)
  local padX = math.floor(8 * z + 0.5)
  local headH = math.floor(30 * z + 0.5)   -- 0.2.3 用户定：标题栏高一点（原 23）
  ui.padX = padX
  ui.f:SetWidth(w)
  ui.f:SetHeight(headH + 1 + c.pr * rowH + math.floor(20 * z + 0.5))
  -- 背景透明度（黑底，真值 = 配置 bgAlpha）
  if ui.bg then pcall(ui.bg.SetVertexColor, ui.bg, 0, 0, 0, c.bgAlpha) end
  -- 数据行几何
  for i = 1, ROW_MAX do
    local row = ui.rows[i]
    row.f:SetPoint("TOPLEFT", ui.f, "TOPLEFT", padX, -(headH + 1) - (i - 1) * rowH)
    row.f:SetWidth(w - padX * 2) row.f:SetHeight(rowH - 2)
    row.bar:SetHeight(rowH - 2)
    if i > c.pr then pcall(row.f.Hide, row.f) end
  end
  -- 标题栏与按钮几何（按钮在加高后的标题栏里垂直居中）
  ui.hd:SetHeight(headH - 1)
  local bs = math.floor(16 * z + 0.5)
  local btnY = -math.max(1, math.floor(((headH - 1) - bs) / 2))
  for i, b in ipairs(ui.btns) do
    b:SetWidth(bs) b:SetHeight(bs)
    b:SetPoint("RIGHT", ui.hd, "RIGHT", -(math.floor(4 * z + 0.5) + (i - 1) * math.floor(18 * z + 0.5)), btnY)
  end
  if ui.backBtn then
    ui.backBtn:SetWidth(math.floor(18 * z + 0.5)) ui.backBtn:SetHeight(bs)
    ui.backBtn:SetPoint("LEFT", ui.hd, "LEFT", 2, btnY)
  end
  -- 底部状态行与尺寸柄
  ui.foot:SetPoint("BOTTOMLEFT", ui.f, "BOTTOMLEFT", padX, math.floor(5 * z + 0.5))
  local rs = math.floor(14 * z + 0.5)
  ui.resize:SetWidth(rs) ui.resize:SetHeight(rs)
  D.dirty = true
end

-- 悬停明细（GameTooltip）：名字 + 总量/占比 + 技能前几名 + 下钻提示（0.2.0：全部按玩家）
local function rowTipSpellSource(name)
  local c = C()
  local v = VIEWS[c.view] or VIEWS[1]
  local pk = PKEY[v.key]
  if not pk or not pk.det then return nil end
  local dd = dataEnsure()
  local seg = dd[c.seg == 0 and 0 or 1]
  local p = seg.p[name]
  if not p then return nil end
  return p[pk.det]
end

local function rowTipShow(anchor, name, raw, total)
  if type(GameTooltip) == "nil" or not GameTooltip.SetOwner then return end
  pcall(GameTooltip.SetOwner, GameTooltip, anchor, "ANCHOR_RIGHT")
  pcall(GameTooltip.SetText, GameTooltip, name)
  if total and total > 0 then
    pcall(GameTooltip.AddLine, GameTooltip,
      string.format("%s（%.1f%%）", fmtNum(raw), raw / total * 100), 1, 1, 1)
  end
  local det = rowTipSpellSource(name)
  if det then
    local tops = {}
    for sp, val in pairs(det) do
      if type(val) == "number" and val > 0 then table.insert(tops, { sp = sp, val = val }) end
    end
    table.sort(tops, function(a, b) return a.val > b.val end)
    for i = 1, math.min(5, table.getn(tops)) do
      pcall(GameTooltip.AddLine, GameTooltip,
        string.format("  %s  %s", tops[i].sp, fmtNum(tops[i].val)), 0.8, 0.8, 0.8)
    end
    pcall(GameTooltip.AddLine, GameTooltip, "左键 = 进入该玩家明细", 1, 0.82, 0.25)
  end
  pcall(GameTooltip.Show, GameTooltip)
end

-- 刷新窗口（唯一绘制口）
function D.Refresh()
  local ui = D.ui
  if not ui or not ui.f then return end
  local rows, total, best, v, seg = viewRows()
  local c = C()
  local pr = clampN(tonumber(c.pr) or 10, ROW_MIN, ROW_MAX)
  local curW = (ui.f.GetWidth and ui.f:GetWidth() or WIN_W) - (ui.padX or 8) * 2
  -- 标题：视图配色（用户 0.1.2 定：不同统计类型不同颜色、鲜艳一点）+ 下钻态
  local tname = v.zh .. (D.detail and (" · " .. D.detail) or "") .. (c.seg == 0 and "（全程）" or "（当前）")
  pcall(ui.title.SetText, ui.title, "EH_DPS · " .. tname)
  pcall(ui.title.SetTextColor, ui.title, (v.col or { 1, 1, 1 })[1], (v.col or { 1, 1, 1 })[2], (v.col or { 1, 1, 1 })[3])
  if ui.backBtn then
    if D.detail then pcall(ui.backBtn.Show, ui.backBtn) else pcall(ui.backBtn.Hide, ui.backBtn) end
  end
  -- 条目配色（0.2.0 全部按玩家出条目）：总览/下钻都按职业染（下钻 = 该玩家职业整列）
  local detailCol = D.detail and classRGB(D.detail) or nil
  for i = 1, ROW_MAX do
    local row = ui.rows[i]
    local r = (i <= pr) and rows[i] or nil
    if r then
      local pct = (not v.count and total > 0) and (r.raw / total * 100) or 0
      local w = (best > 0) and math.max(1, (r.value / best) * curW) or 1
      pcall(row.bar.SetWidth, row.bar, w)
      local bc = detailCol or classRGB(r.name)
      pcall(row.bar.SetVertexColor, row.bar, bc[1], bc[2], bc[3], 1)   -- 0.2.5：不透明
      row._baseAlpha = 1
      row.name = r.name
      -- 条目文字白色（0.2.4 用户定：黑字在条尾之外的黑底上看不清；0.2.2 的黑字方案退回）
      pcall(row.fs.SetTextColor, row.fs, 1, 1, 1)
      if v.perSec then
        pcall(row.fs.SetText, row.fs, string.format("%s  %.1f", r.name, r.value))
      elseif v.count then
        pcall(row.fs.SetText, row.fs, string.format("%s  %d", r.name, r.raw))
      else
        pcall(row.fs.SetText, row.fs, string.format("%s  %s (%.1f%%)", r.name, fmtNum(r.raw), pct))
      end
      pcall(row.f.Show, row.f)
    else
      row.name = nil
      pcall(row.f.Hide, row.f)
    end
  end
  -- 底部状态行：战斗时长 / 自己的活跃时间
  local me = seg.p[selfName()]
  local ftr = string.format("战斗 %ds · 活跃 %ds", seg.fightT or 0, (me and me.actT) or 0)
  pcall(ui.foot.SetText, ui.foot, ftr)
  D.dirty = false
end

local function buildUI()
  if D.ui then return true end
  if type(CreateFrame) ~= "function" then return false end
  local f = CreateFrame("Frame", "EH_DPS_WIN", UIParent)
  -- ★锚左上角：改尺寸只往右下长（锚 CENTER 会四边对称长 = 拖拽时整窗抖动，真机报障）
  f:SetWidth(WIN_W) f:SetHeight(24 + 10 * 16 + 20)   -- 初始几何（buildUI 末尾 Layout 按存档重算）
  f:SetPoint("TOPLEFT", UIParent, "CENTER", 200, 100) -- 默认位（左上角锚，位置记忆恢复会覆盖）
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, true) end
  if type(f.SetMovable) == "function" then pcall(f.SetMovable, f, true) end
  pcall(f.SetFrameStrata, f, "MEDIUM")
  -- ★0.1.2 窗体样式（用户定）：边框 = 黑色 0.85 透明；背景 = 黑色透明（透明度可配，Layout 写）
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0, 0, 0, 0.85)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = f:CreateTexture(nil, "BORDER") solid(t, 0, 0, 0, 0.85)
    t:SetPoint(e .. "LEFT", f, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", f, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = f:CreateTexture(nil, "BORDER") solid(t, 0, 0, 0, 0.85)
    t:SetPoint("TOP" .. s, f, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, f, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end

  -- 标题栏（Button 拖动柄：Frame 的 OnDragStart 不触发）
  local hd = CreateFrame("Button", "EH_DPS_HDR", f)
  hd:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1) hd:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, 1)
  hd:SetHeight(22)
  if type(hd.EnableMouse) == "function" then pcall(hd.EnableMouse, hd, true) end
  if type(hd.RegisterForDrag) == "function" then pcall(hd.RegisterForDrag, hd, "LeftButton") end
  -- ★右键 = 视图下拉菜单（鼠标键按项目 idiom 从全局 arg1 取）
  if type(hd.RegisterForClicks) == "function" then pcall(hd.RegisterForClicks, hd, "LeftButtonUp", "RightButtonUp") end
  hd:SetScript("OnClick", function()
    if rawget(_G, "arg1") == "RightButton" then D.ViewMenuToggle() end
  end)
  hd:SetScript("OnDragStart", function() pcall(f.StartMoving, f) end)
  hd:SetScript("OnDragStop", function()
    pcall(f.StopMovingOrSizing, f)
    -- 位置记忆 = 左上角（GetLeft/GetTop 含缩放，存取要除 GetEffectiveScale）；
    -- 锚 TOPLEFT ⇒ 右下拖拽改尺寸时本角不动，不抖
    local l, t = f:GetLeft(), f:GetTop()
    local es = f:GetEffectiveScale()
    if l and t and es and es > 0 then
      local c = C()
      c.px = l / es
      c.py = t / es
    end
  end)
  local hdbg = hd:CreateTexture(nil, "BACKGROUND")
  hdbg:SetPoint("TOPLEFT", hd, "TOPLEFT", 0, 0) hdbg:SetPoint("BOTTOMRIGHT", hd, "BOTTOMRIGHT", 0, 0)
  solid(hdbg, 0, 0, 0, 0.85)   -- 0.2.2 用户定：标题栏也黑色背景（与边框同族）

  local ui = { f = f, rows = {}, btns = {}, hd = hd, bg = bg }
  -- 下钻回退钮（标题左侧，只在明细态显示；「返」字比箭头字形稳）
  local backBtn = CreateFrame("Button", nil, hd)
  backBtn:SetWidth(18) backBtn:SetHeight(16)
  backBtn:SetPoint("LEFT", hd, "LEFT", 2, 0)
  local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
  backBg:SetPoint("TOPLEFT", backBtn, "TOPLEFT", 0, 0) backBg:SetPoint("BOTTOMRIGHT", backBtn, "BOTTOMRIGHT", 0, 0)
  solid(backBg, 0.22, 0.18, 0.10, 1)
  local backT = mkFont(backBtn)
  backT:SetPoint("CENTER", backBtn, "CENTER", 0, 0)
  pcall(backT.SetText, backT, "返")
  pcall(backT.SetTextColor, backT, 0.95, 0.82, 0.35)
  backBtn:SetScript("OnClick", function()
    D.detail = nil
    D.dirty = true
    D.Refresh()
  end)
  pcall(backBtn.Hide, backBtn)
  ui.backBtn = backBtn
  local title = mkFont(hd)
  title:SetPoint("LEFT", hd, "LEFT", 24, 0)
  ui.title = title

  -- 标题右侧按钮：[×][清][报][段][>][<]（尺寸由 Layout 按缩放现算，从右往左排）
  local function mkBtn(label, tip, onclick)
    local b = CreateFrame("Button", nil, hd)
    local bb = b:CreateTexture(nil, "BACKGROUND")
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    solid(bb, 0.22, 0.18, 0.10, 1)
    local bt = mkFont(b)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    pcall(bt.SetText, bt, label)
    pcall(bt.SetTextColor, bt, 0.95, 0.82, 0.35)
    b:SetScript("OnClick", onclick)
    b:SetScript("OnEnter", function()
      if type(GameTooltip) ~= "nil" and GameTooltip.SetOwner then
        pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetText, GameTooltip, tip)
        pcall(GameTooltip.Show, GameTooltip)
      end
    end)
    b:SetScript("OnLeave", function() pcall(GameTooltip.Hide, GameTooltip) end)
    table.insert(ui.btns, b)
    return b
  end

  mkBtn("×", "关闭窗口（数据采集继续；/edps 重新打开）", function()
    pcall(f.Hide, f)
    C().winShown = false          -- 记住关过：下次载入不再自动弹（/edps 打开即恢复）
    D.beatSync()
  end)
  mkBtn("清", "清空全部统计数据", function() D.Reset() end)
  mkBtn("报", "把当前视图前 5 行发到聊天（说/队伍/团队，/edps 报告 频道 可指定）", function() D.Report() end)
  mkBtn("段", "切换 当前战斗/全程", function()
    local c = C()
    c.seg = (c.seg == 0) and 1 or 0
    D.detail = nil              -- 换段退出下钻
    D.dirty = true
    D.Refresh()
  end)
  -- ★字形坑：本客户端字体链没有 ◀ ▶ 图形字形（画了空白，真机截图定案）⇒ 用 ASCII < >
  mkBtn(">", "下一个视图", function() D.CycleView(1) end)
  mkBtn("<", "上一个视图", function() D.CycleView(-1) end)
  mkBtn("设", "配置（条目高度 / 背景透明度，持续扩充）", function() D.CfgToggle() end)

  -- ★Ctrl+滚轮 = 整窗缩放（几何重建，不走 SetScale —— 点击框漂移在案；
  --   字号不变是客户端限制：本客户端文字不吃任何缩放/改字号，EH_Damage 探针定案）
  pcall(f.EnableMouseWheel, f, true)
  f:SetScript("OnMouseWheel", function()
    local d = rawget(_G, "arg1") or 0
    if type(IsControlKeyDown) ~= "function" or not IsControlKeyDown() then return end
    if d == 0 then return end
    local c = C()
    c.scale = clampN((c.scale or 1) * (d > 0 and 1.1 or (1 / 1.1)), Z_MIN, Z_MAX)
    D.Layout()
    D.Refresh()
  end)

  -- 数据行（行池 ROW_MAX 建一次，超出配置行数的由 Layout/Refresh 收起）
  --   ★0.1.2 起行 = 可交互 Button：悬停出明细 tooltip，队伍视图点行 = 下钻该玩家
  for i = 1, ROW_MAX do
    local rf = CreateFrame("Button", nil, f)
    rf:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24 - (i - 1) * 16)
    rf:SetWidth(WIN_W - 16) rf:SetHeight(14)
    if type(rf.EnableMouse) == "function" then pcall(rf.EnableMouse, rf, true) end
    local bar = rf:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("LEFT", rf, "LEFT", 0, 0)
    bar:SetHeight(14)
    solid(bar, 0.55, 0.35, 0.10, 0.75)
    local fs = mkFont(rf)
    fs:SetPoint("LEFT", rf, "LEFT", 3, 0)
    pcall(fs.SetTextColor, fs, 1, 1, 1)
    ui.rows[i] = { f = rf, bar = bar, fs = fs }
    rf:SetScript("OnEnter", function()
      local nm = ui.rows[i].name
      if not nm then return end
      local c = C()
      local v = VIEWS[c.view] or VIEWS[1]
      local rows, total = viewRows()
      local raw = 0
      for _, rr in ipairs(rows) do if rr.name == nm then raw = rr.raw break end end
      rowTipShow(rf, nm, raw, total)
      pcall(bar.SetAlpha, bar, 1)
    end)
    rf:SetScript("OnLeave", function()
      pcall(GameTooltip.Hide, GameTooltip)
      pcall(bar.SetAlpha, bar, ui.rows[i]._baseAlpha or 0.75)
    end)
    rf:SetScript("OnClick", function()
      local nm = ui.rows[i].name
      if not nm then return end
      local c = C()
      local v = VIEWS[c.view] or VIEWS[1]
      local pk = PKEY[v.key]
      if pk and pk.det and not D.detail then
        D.detail = nm
        D.dirty = true
        D.Refresh()
      end
    end)
    pcall(rf.Hide, rf)
  end

  -- 底部状态行
  local foot = mkFont(f)
  foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
  pcall(foot.SetTextColor, foot, 0.7, 0.7, 0.7)
  ui.foot = foot

  -- ★右下角尺寸拖拽柄（拖拽三件套：OnMouseDown 起 + 节拍里 GetCursorPosition 现算
  --   + 鼠标键状态收尾；本客户端不赌 StartSizing，EH_Damage 同款手法）
  local rz = CreateFrame("Button", "EH_DPS_RESIZE", f)
  rz:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  rz:SetWidth(14) rz:SetHeight(14)
  if type(rz.EnableMouse) == "function" then pcall(rz.EnableMouse, rz, true) end
  local rzb = rz:CreateTexture(nil, "BORDER")
  rzb:SetPoint("BOTTOMRIGHT", rz, "BOTTOMRIGHT", -1, 1)
  rzb:SetWidth(10) rzb:SetHeight(10)
  solid(rzb, 0.85, 0.70, 0.20, 0.8)
  rz:SetScript("OnEnter", function()
    pcall(rzb.SetVertexColor, rzb, 1, 0.9, 0.4, 1)
    if type(GameTooltip) ~= "nil" and GameTooltip.SetOwner then
      pcall(GameTooltip.SetOwner, GameTooltip, rz, "ANCHOR_LEFT")
      pcall(GameTooltip.SetText, GameTooltip, "拖动调整窗口大小（宽 180~400 · 行数 4~20）")
      pcall(GameTooltip.Show, GameTooltip)
    end
  end)
  rz:SetScript("OnLeave", function()
    pcall(rzb.SetVertexColor, rzb, 0.85, 0.70, 0.20, 0.8)
    pcall(GameTooltip.Hide, GameTooltip)
  end)
  rz:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    local c0 = C()
    local es = (f:GetEffectiveScale() or 1) * (c0.scale or 1)   -- 与 ResizeTick 同一口径（含缩放）
    D.rs = { sx = cx / es, sy = cy / es, w0 = c0.pw or WIN_W, r0 = c0.pr or 10 }
    if D.catchF then pcall(D.catchF.Show, D.catchF) end   -- 全屏接盘：任意位置松开都能收尾
    D.beatSync()
  end)
  rz:SetScript("OnMouseUp", function() D.ResizeEnd() end)
  ui.resize = rz

  -- ★全屏接盘（真机报障「释放触发不稳」）：本客户端鼠标在柄外松开时柄的 OnMouseUp 收不到 ⇒
  --   起拖时盖一个全屏透明 Button（项目弹出层同款手法），三条收尾路：柄 OnMouseUp / 接盘 / 节拍键状态
  local cf = CreateFrame("Button", "EH_DPS_RSCATCH", UIParent)
  pcall(cf.SetAllPoints, cf, UIParent)
  pcall(cf.SetFrameStrata, cf, "DIALOG")
  pcall(cf.SetFrameLevel, cf, 900)
  if type(cf.EnableMouse) == "function" then pcall(cf.EnableMouse, cf, true) end
  cf:SetScript("OnMouseUp", function() D.ResizeEnd() end)
  cf:SetScript("OnClick", function() D.ResizeEnd() end)   -- 唯一隐藏出口外的第二条路
  pcall(cf.Hide, cf)
  D.catchF = cf

  -- ★标题右键 = 视图下拉菜单（自建小菜单：菜单 DIALOG/300 + 点外面即关的全屏捕手 290）
  local mc = CreateFrame("Button", "EH_DPS_MENUCATCH", UIParent)
  pcall(mc.SetAllPoints, mc, UIParent)
  pcall(mc.SetFrameStrata, mc, "DIALOG")
  pcall(mc.SetFrameLevel, mc, 290)
  if type(mc.EnableMouse) == "function" then pcall(mc.EnableMouse, mc, true) end
  mc:SetScript("OnClick", function() D.ViewMenuHide() end)
  pcall(mc.Hide, mc)
  local mn = CreateFrame("Frame", "EH_DPS_VIEWMENU", UIParent)
  mn:SetWidth(130) mn:SetHeight(table.getn(VIEWS) * 16 + 8)
  pcall(mn.SetFrameStrata, mn, "DIALOG")
  pcall(mn.SetFrameLevel, mn, 300)
  if type(mn.EnableMouse) == "function" then pcall(mn.EnableMouse, mn, true) end
  local mnbg = mn:CreateTexture(nil, "BACKGROUND")
  mnbg:SetPoint("TOPLEFT", mn, "TOPLEFT", 0, 0) mnbg:SetPoint("BOTTOMRIGHT", mn, "BOTTOMRIGHT", 0, 0)
  solid(mnbg, 0.04, 0.04, 0.04, 0.96)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = mn:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", mn, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", mn, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = mn:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, mn, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, mn, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end
  mn.rows = {}
  for i, v in ipairs(VIEWS) do
    local rb = CreateFrame("Button", nil, mn)
    rb:SetPoint("TOPLEFT", mn, "TOPLEFT", 4, -4 - (i - 1) * 16)
    rb:SetWidth(122) rb:SetHeight(16)
    if type(rb.EnableMouse) == "function" then pcall(rb.EnableMouse, rb, true) end
    local rfs = mkFont(rb)
    rfs:SetPoint("LEFT", rb, "LEFT", 4, 0)
    pcall(rfs.SetText, rfs, i .. ". " .. v.zh)
    rb:SetScript("OnClick", function()
      C().view = i
      D.detail = nil            -- 换视图退出下钻
      D.ViewMenuHide()
      D.dirty = true
      D.Refresh()
    end)
    rb:SetScript("OnEnter", function() pcall(rfs.SetTextColor, rfs, 1, 0.9, 0.4) end)
    rb:SetScript("OnLeave", function() D.ViewMenuPaint() end)
    mn.rows[i] = { b = rb, fs = rfs }
  end
  pcall(mn.Hide, mn)
  ui.vmenu = mn
  D.menuCatch = mc

  -- ★配置面板（标题 [设] 按钮；0.1.2）：条目高度 / 背景透明度，两行 [-] 值 [+] 选择器
  local cp = CreateFrame("Frame", "EH_DPS_CFGPANEL", UIParent)
  cp:SetWidth(170) cp:SetHeight(2 * 22 + 30)
  pcall(cp.SetFrameStrata, cp, "DIALOG")
  pcall(cp.SetFrameLevel, cp, 310)
  if type(cp.EnableMouse) == "function" then pcall(cp.EnableMouse, cp, true) end
  local cpbg = cp:CreateTexture(nil, "BACKGROUND")
  cpbg:SetPoint("TOPLEFT", cp, "TOPLEFT", 0, 0) cpbg:SetPoint("BOTTOMRIGHT", cp, "BOTTOMRIGHT", 0, 0)
  solid(cpbg, 0, 0, 0, 0.92)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = cp:CreateTexture(nil, "BORDER") solid(t, 0, 0, 0, 0.85)
    t:SetPoint(e .. "LEFT", cp, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", cp, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = cp:CreateTexture(nil, "BORDER") solid(t, 0, 0, 0, 0.85)
    t:SetPoint("TOP" .. s, cp, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, cp, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end
  local cpt = mkFont(cp)
  cpt:SetPoint("TOPLEFT", cp, "TOPLEFT", 8, -6)
  pcall(cpt.SetText, cpt, "配置")
  pcall(cpt.SetTextColor, cpt, 1, 0.82, 0.25)
  -- 配置行：label + [-] + 值 + [+]（行几何固定，面板高度按行数现算）
  local function cfgRow(idx, label, get, set)
    local y = -24 - (idx - 1) * 22
    local lb = mkFont(cp)
    lb:SetPoint("TOPLEFT", cp, "TOPLEFT", 8, y - 3)
    pcall(lb.SetText, lb, label)
    pcall(lb.SetTextColor, lb, 0.9, 0.9, 0.9)
    local function sml(txt, dx, fn)
      local b = CreateFrame("Button", nil, cp)
      b:SetWidth(18) b:SetHeight(16)
      b:SetPoint("TOPRIGHT", cp, "TOPRIGHT", dx, y)
      local bb = b:CreateTexture(nil, "BACKGROUND")
      bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      solid(bb, 0.22, 0.18, 0.10, 1)
      local bt = mkFont(b)
      bt:SetPoint("CENTER", b, "CENTER", 0, 0)
      pcall(bt.SetText, bt, txt)
      pcall(bt.SetTextColor, bt, 0.95, 0.82, 0.35)
      b:SetScript("OnClick", fn)
      return b
    end
    local val = mkFont(cp)
    val:SetPoint("TOPRIGHT", cp, "TOPRIGHT", -34, y - 3)
    pcall(val.SetTextColor, val, 1, 1, 1)
    sml("-", -64, function() set(-1) end)
    sml("+", -6, function() set(1) end)
    return val
  end
  ui.cfgRowH = cfgRow(1, "条目高度",
    function() return tostring(C().rowH or 22) end,
    function(d) local c = C() c.rowH = clampN((c.rowH or 22) + d * 2, 22, 30) D.Layout() D.Refresh() D.CfgPaint() end)
  ui.cfgBgA = cfgRow(2, "背景透明度",
    function() return tostring(C().bgAlpha or 0.85) end,
    function(d)
      local c = C()
      c.bgAlpha = clampN(math.floor(((c.bgAlpha or 0.85) + d * 0.05) * 100 + 0.5) / 100, 0.30, 1.00)
      D.Layout() D.Refresh() D.CfgPaint()
    end)
  pcall(cp.Hide, cp)
  ui.cfgPanel = cp

  -- 位置记忆恢复（左上角锚；旧档语义是中心偏移 ⇒ 一次性作废重来）
  local c = C()
  if c.posV2 ~= true then c.px, c.py, c.posV2 = nil, nil, true end
  if c.px and c.py then
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "TOPLEFT", UIParent, "BOTTOMLEFT", c.px, c.py)
  end

  D.ui = ui
  D.Layout()           -- 按存档 pw/pr 重算几何
  return true
end

-- 尺寸拖拽推进（挂在唯一节拍帧上；松手收尾三条路：柄 OnMouseUp / 全屏接盘 / 键状态）
function D.ResizeEnd()
  if D.catchF then pcall(D.catchF.Hide, D.catchF) end
  if not D.rs then return end                            -- 幂等：三条路谁来都只做一次
  D.rs = nil
  D.SaveData()                                           -- 尺寸落存档（pw/pr 在 cfg 里自动持久）
  D.beatSync()
end

function D.ResizeTick()
  local rs = D.rs
  if not rs then return end
  if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
    D.ResizeEnd()
    return
  end
  -- 节流：每帧重建 Layout 是几十次 widget 调用 ⇒ 0.05s 一拍足够跟手（本地 CPU，不涉服务器）
  local now0 = GetTime and GetTime() or 0
  if rs.t and now0 - rs.t < 0.05 then return end
  rs.t = now0
  local cx, cy = GetCursorPosition()
  local c = C()
  local es = ((D.ui and D.ui.f:GetEffectiveScale()) or 1) * (c.scale or 1)  -- 缩放系数一起除（逻辑单位）
  c.pw = clampN(math.floor(rs.w0 + (cx / es - rs.sx) + 0.5), W_MIN, W_MAX)
  c.pr = clampN(math.floor(rs.r0 + (rs.sy - cy / es) / 16 + 0.5), ROW_MIN, ROW_MAX)
  D.Layout()
end

-- 视图菜单：当前行金色高亮（唯一绘制口；OnLeave 也回这里重画）
function D.ViewMenuPaint()
  local ui = D.ui
  if not ui or not ui.vmenu then return end
  local cur = C().view
  for i, row in ipairs(ui.vmenu.rows) do
    if i == cur then pcall(row.fs.SetTextColor, row.fs, 1, 0.82, 0.25)
    else pcall(row.fs.SetTextColor, row.fs, 0.9, 0.9, 0.9) end
  end
end

function D.ViewMenuToggle()
  local ui = D.ui
  if not ui or not ui.vmenu then return end
  local mn = ui.vmenu
  if mn:IsShown() then D.ViewMenuHide() return end
  mn:SetPoint("TOPLEFT", ui.hd, "BOTTOMLEFT", 0, -2)
  D.ViewMenuPaint()
  pcall(mn.Show, mn)
  if D.menuCatch then pcall(D.menuCatch.Show, D.menuCatch) end
end

function D.ViewMenuHide()
  local ui = D.ui
  if ui and ui.vmenu then pcall(ui.vmenu.Hide, ui.vmenu) end
  if ui and ui.cfgPanel then pcall(ui.cfgPanel.Hide, ui.cfgPanel) end   -- 配置面板同一把收
  if D.menuCatch then pcall(D.menuCatch.Hide, D.menuCatch) end
end

-- 配置面板（标题 [设]）：显示值重画唯一口
function D.CfgPaint()
  local ui = D.ui
  if not ui or not ui.cfgPanel then return end
  pcall(ui.cfgRowH.SetText, ui.cfgRowH, tostring(C().rowH or 22))
  pcall(ui.cfgBgA.SetText, ui.cfgBgA, string.format("%.2f", C().bgAlpha or 0.85))
end

function D.CfgToggle()
  local ui = D.ui
  if not ui or not ui.cfgPanel then return end
  local cp = ui.cfgPanel
  if cp:IsShown() then D.ViewMenuHide() return end
  D.ViewMenuHide()                                  -- 与视图菜单互斥（共用捕手）
  cp:SetPoint("TOPLEFT", ui.hd, "BOTTOMLEFT", 0, -2)
  D.CfgPaint()
  pcall(cp.Show, cp)
  if D.menuCatch then pcall(D.menuCatch.Show, D.menuCatch) end
end

function D.CycleView(dir)
  local c = C()
  D.detail = nil            -- 换视图退出下钻
  c.view = c.view + dir
  if c.view > table.getn(VIEWS) then c.view = 1 end
  if c.view < 1 then c.view = table.getn(VIEWS) end
  D.dirty = true
  D.Refresh()
end

function D.Toggle()
  if not buildUI() then say("界面组件不可用") return end
  local f = D.ui.f
  local c = C()
  if f:IsShown() then pcall(f.Hide, f) c.winShown = false
  else pcall(f.Show, f) c.winShown = true D.dirty = true D.Refresh() end
  D.beatSync()
end

-- 清空全部数据（两段都清 + 持久化）
function D.Reset()
  D.data = { [0] = newSeg(), [1] = newSeg() }
  D.killRecent = {}
  D.SaveData()
  D.dirty = true
  D.Refresh()
  say("数据已清空")
end

-- ----------------------------------------------------------------------------
-- 聊天报告（SendChatMessage 是 Protected ⇒ RunScript 绕行 + 0.6s 滴出限频）
--   ★频率防护（断线审计定案）：① 队列非空 = 上一份还没发完 ⇒ 拒绝新报告（如实播报），
--     绝不叠加 —— 队列无上限叠加 = 持续数分钟的服务器写动作链；② RunScript 是客户端
--     **共享队列**（宿主一键宏 /run EVAL_GO() 也在用）⇒ 滴出间隔 0.6s 不许再调快；
--     ③ 发送内容剥引号（名字含 " 会截断脚本串）。
-- ----------------------------------------------------------------------------
D.reportQ = {}
D.reportNext = 0

local function rsSafe(s) return (string.gsub(tostring(s), '"', "'")) end

function D.Report(ch)
  local c = C()
  if c.master ~= true then say("总开关关着，无法报告（/edps 开 先启用）") return end
  if table.getn(D.reportQ) > 0 then say("上一份报告还在发送中，发完再报") return end   -- ① 防叠加
  ch = ch or c.reportCh or "SAY"
  if ch ~= "SAY" and ch ~= "PARTY" and ch ~= "RAID" then
    say("报告频道只支持 说(SAY)/队伍(PARTY)/团队(RAID)")
    return
  end
  local rows, total, best, v = viewRows()
  if table.getn(rows) == 0 then say("没有可报告的数据") return end
  table.insert(D.reportQ, "EH_DPS " .. v.zh .. (c.seg == 0 and "（全程）" or "（当前战斗）") .. "：")
  local n = math.min(5, table.getn(rows))
  for i = 1, n do
    local r = rows[i]
    local line
    if v.perSec then line = string.format("%d. %s %.1f/s", i, r.name, r.value)
    elseif v.count then line = string.format("%d. %s ×%d", i, r.name, r.raw)
    else
      local pct = total > 0 and (r.raw / total * 100) or 0
      line = string.format("%d. %s %s (%.1f%%)", i, r.name, fmtNum(r.raw), pct)
    end
    table.insert(D.reportQ, rsSafe(line))
  end
  D.beatSync()   -- 有报告待办时必须挂节拍
end

local function reportTick()
  local now = GetTime and GetTime() or 0
  if now < D.reportNext then return end
  local line = table.remove(D.reportQ, 1)
  if not line then return end
  D.reportNext = now + 0.6
  local ch = C().reportCh or "SAY"
  local ok = pcall(RunScript, 'SendChatMessage("' .. line .. '","' .. ch .. '")')
  if not ok then
    say("发送失败（SendChatMessage 受限）：" .. line)   -- 如实兜底，绝不静默
    D.reportQ = {}
  end
end

-- ----------------------------------------------------------------------------
-- 节拍帧：唯一挂/摘入口（宿主 WorldFrame；一个模块只许一个节拍帧）
--   职责：① 数据变更后节流刷新窗口（0.3s）② 报告队列滴出
-- ----------------------------------------------------------------------------
local function tick()
  D.ResizeTick()
  reportTick()
  local ui = D.ui
  if ui and ui.f and ui.f:IsShown() then
    local now = GetTime and GetTime() or 0
    if D.dirty and now >= (D.refreshAt or 0) then
      D.refreshAt = now + 0.3
      D.Refresh()
    end
  end
end
D.tick = tick

D.frame = nil
function D.beatSync()
  if type(CreateFrame) ~= "function" then return end
  local c = C()
  local want = (c.master == true) and ((D.ui and D.ui.f and D.ui.f:IsShown()) or table.getn(D.reportQ) > 0 or D.rs ~= nil)
  if not D.frame then
    local parent = rawget(_G, "WorldFrame") or UIParent
    D.frame = CreateFrame("Frame", "EH_DPS_BEAT", parent)
  end
  if want then
    pcall(D.frame.SetScript, D.frame, "OnUpdate", tick)    -- 重挂同一 handler（幂等）
  else
    pcall(D.frame.SetScript, D.frame, "OnUpdate", nil)     -- 真摘，不靠每帧早退
  end
end

-- ----------------------------------------------------------------------------
-- 总开关（关断四件事：收窗 / 真摘节拍 / 会话态重置 / 摘事件；数据保留在存档）
-- ----------------------------------------------------------------------------
function D.setMaster(on)
  local c = C()
  c.master = on and true or false
  if c.master then
    eventSync()
    -- 开 = 摆出来（与载入期默认显示同语义）
    if buildUI() then
      pcall(D.ui.f.Show, D.ui.f)
      c.winShown = true
      D.dirty = true
      D.Refresh()
    end
    D.beatSync()
    say("已开启（/edps 打开统计窗）")
  else
    if D.ui and D.ui.f then pcall(D.ui.f.Hide, D.ui.f) end          -- ① 收窗
    if D.frame then pcall(D.frame.SetScript, D.frame, "OnUpdate", nil) end  -- ② 真摘节拍
    D.reportQ = {} D.killRecent = {} D.dirty = false D.rs = nil      -- ③ 会话态重置
    if D.catchF then pcall(D.catchF.Hide, D.catchF) end              -- 接盘一起收
    D.ViewMenuHide()                                                 -- 视图菜单一起收
    eventSync()                                                     -- ④ 摘全部事件
    say("已关闭（数据保留，/edps 开 重新启用）")
  end
end

-- ----------------------------------------------------------------------------
-- 命令分发：/edps
-- ----------------------------------------------------------------------------
local function cmd(msg)
  msg = string.gsub(tostring(msg or ""), "^%s*(.-)%s*$", "%1")
  local sub, arg = string.match(msg, "^(%S+)%s*(.-)$")
  sub = sub or ""
  if sub == "" or sub == "ui" then
    D.Toggle()
  elseif sub == "开" or sub == "on" then
    D.setMaster(true)
  elseif sub == "关" or sub == "off" then
    D.setMaster(false)
  elseif sub == "视图" or sub == "view" then
    if arg == "" then
      D.CycleView(1)
    else
      local n = tonumber(arg)
      if not n then
        for i, v in ipairs(VIEWS) do
          if v.zh == arg or v.id == arg then n = i break end
        end
      end
      if n and VIEWS[n] then C().view = n D.dirty = true D.Refresh()
      else say("视图列表：1伤害量 2DPS 3治疗量 4HPS 5承受伤害 6受到治疗 7能量回复 8击杀 9施放次数（全部按玩家出条目，右键标题可直接选）") end
    end
  elseif sub == "当前" then C().seg = 1 D.dirty = true D.Refresh()
  elseif sub == "全程" then C().seg = 0 D.dirty = true D.Refresh()
  elseif sub == "重置" or sub == "清" or sub == "reset" then
    D.Reset()
  elseif sub == "报告" or sub == "report" then
    local ch = nil
    if arg == "队伍" or arg == "party" then ch = "PARTY"
    elseif arg == "团队" or arg == "raid" then ch = "RAID"
    elseif arg == "说" or arg == "say" then ch = "SAY" end
    if ch then C().reportCh = ch end
    D.Report(ch)
  elseif sub == "捕获" then
    local c = C()
    c.capture = not c.capture
    say("战斗文本捕获：" .. (c.capture and "开（原文落环）" or "关"))
  elseif sub == "事件" then
    local r = C().ring
    say("捕获环（最近 " .. table.getn(r) .. " 条，新的在后）：")
    local s = math.max(1, table.getn(r) - 14)
    for i = s, table.getn(r) do say("  " .. r[i]) end
  elseif sub == "状态" then
    local c = C()
    local dd = dataEnsure()
    local v = VIEWS[c.view] or VIEWS[1]
    say("版本 " .. BUILD .. " ｜ 总开关=" .. (c.master and "开" or "关")
      .. " ｜ 视图=" .. v.zh .. " ｜ 段=" .. (c.seg == 0 and "全程" or "当前")
      .. " ｜ 战斗中=" .. (D.combatStart > 0 and "是" or "否"))
    local n = 0
    for _ in pairs(dd[1].p) do n = n + 1 end
    say("当前段人数 " .. n .. " ｜ 名册 " .. (function() local k = 0 for _ in pairs(D.partyNames) do k = k + 1 end return k end)()
      .. " ｜ 捕获环 " .. table.getn(c.ring) .. "/" .. RING_MAX)
  else
    say("用法：/edps [ui|开|关|视图 [序号或名]|当前|全程|重置|报告 [说|队伍|团队]|捕获|事件|状态]（视图：1伤害量 2DPS 3治疗量 4HPS 5承受伤害 6受到治疗 7能量回复 8击杀 9施放次数，或右键标题选）")
  end
end

-- ----------------------------------------------------------------------------
-- 载入：注册命令 + VARIABLES_LOADED 武装（载入期零副作用：不建帧不挂事件）
-- ----------------------------------------------------------------------------
if type(SlashCmdList) == "table" then
  rawset(_G, "SLASH_EHDPS1", "/edps")
  rawset(SlashCmdList, "EHDPS", cmd)
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:SetScript("OnEvent", function()
  cfgEnsure()
  D.LoadData()
  partyRefresh()          -- 队伍名册（队伍级统计的过滤闸）
  if C().master == true then
    eventSync()
    -- ★默认显示窗口（0.1.2b 用户定：启用就摆出来）；用户 × 关过（winShown=false）则不打扰
    if C().winShown ~= false then
      if buildUI() then
        pcall(D.ui.f.Show, D.ui.f)
        D.dirty = true
        D.Refresh()
      end
    end
  end
  D.beatSync()
  say("v" .. BUILD .. " 已加载（/edps 打开统计窗；自娱自乐版，只统计自己，准确度不保证）")
end)
