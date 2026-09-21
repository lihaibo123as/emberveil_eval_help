-- EvalHelp · tools/HunterHelper.lua —— 猎人助手 · 一键喂食（1.74.5 新增）
-- 需求（用户原话）：「先在 ./tools 内完成代码和UI，在工具箱内添加个猎人助手分组 -> 一键喂食开关」
-- 交互（用户已确认的目标）：
--   · 图标**左键 = 一键喂食**（内部两步：① 施放「喂食宠物」进入待选目标态 ② 把预设食物当目标点掉）
--   · 图标**右键 = 下拉选食物**（列背包里的物品；选完图标变成该食物的图标）
--   · 工具箱 →「猎人助手」→「一键喂食」开关 = 本模块的**总闸门**（关掉 = 图标收起、不建帧）
--
-- ★★★「懒加载」的真实边界（用户要求分析；结论写在这里，免得以讹传讹）：
--   ① 本客户端**没有任何文件读取 API**（无 io / os / loadfile）⇒ **文件级懒加载做不到**：
--      唯一载入途径 = 列进 EvalHelp.toc（与 examples/*.lua 同一条纪律）。
--   ② LoadAddOn(name) 在本客户端是 **Protected**（工具链扫全表只有 13 个 Protected，它算一个）
--      ⇒「做成独立小插件、用时再 LoadAddOn」这条路**被客户端堵死**（插件调它无效）。
--   ③ 所以本模块的「懒」= **载入期零副作用 + 首次使用才产生成本**：
--      · 载入期：只有一张局部状态表 + 若干函数（不建帧、不注册事件、不扫背包）；
--      · 图标帧：用户**打开开关**那一下才 CreateFrame（HH.built 从 false 变 true）；
--      · OnUpdate 帧：**第一次真要喂食**才建，且队列一空就摘掉 OnUpdate —— 不在后台空转；
--      · 背包扫描：只在**右键开下拉 / 真喂食**时做一次（唯一真值 = 当次实时扫描）。
--
-- ★★★食物设置**存名字不存包格**（本项目「不许两处真值」纪律）：
--   包格会变（拖动整理 / 堆叠合并 / 吃完消失 / 换背包），存死的 bag/slot 必然「今天能喂、明天喂错格」。
--   故：设置只写 tb.hhFood（名字）+ tb.hhFoodTex（图标缓存，纯显示）；每次喂食/刷新图标都**重新扫背包**解析。
--
-- ★★待实测（本客户端文档没写、必须以探针定案；见 /eh go 喂食探针）：
--   ① 「喂食宠物」的本地化名与法术书下标（自动识别用 HH_SPELL_CAND；识别不到可右键手动指定）；
--   ② RunScript('CastSpellByName(...)') 之后是否真的进入待选目标态（SpellIsTargeting()==1）；
--      ★RunScript 是**排队**通道（项目既有结论），故本模块用**跨帧状态机**等它生效，绝不当帧硬点背包；
--   ③「非鼠标来源」的 PickupContainerItem(bag,slot) 是否被接受为「技能目标」（若不接受 → 退化成两步）；
--   ④ 战斗中 / 无宠物 / 冷却中客户端的确切反应（本模块一律「先自查再动手」，不把未知交给服务器）。
--
-- 依赖的全局件（只在**调用时**读，载入期不读 → 与 toc 顺序解耦）：
--   EVAL_SAY / EVAL_L（Core 桥）· EVAL_DD_OPEN（全局下拉）· EVAL_HELP_CONFIG.tb（与工具箱共用一份真值）

local HH = {
  built = false,     -- 图标帧是否已建（懒加载读值口）
  btn = nil,         -- 图标按钮
  tex = nil,         -- 图标纹理控件
  label = nil,       -- 无纹理时的保底文字
  tick = nil,        -- OnUpdate 帧（第一次喂食才建）
  q = {},            -- 待办 FIFO
  phase = "idle",    -- idle | aim | settle
  aimAt = 0,
  settleAt = 0,
  lastRun = -999,    -- 上一次真正执行的时间（限频）
  food = nil,        -- 本次喂的食物名（点包那一刻按名字**重新解析**包格）
  spellCache = nil,  -- 自动识别到的喂食技能名（只缓存命中结果）
  spellIndex = nil,
  spellAt = -999,
  dd = nil,          -- 上一次构建的下拉模型（测试读值口用，避免测试复刻逻辑）
  hits = 0,          -- 成功的喂食次数（诊断用）
  foodBag = nil,
  regClicks = nil,   -- RegisterForClicks 的 pcall 结果（**不许静默吞**：右键不通时先看这里）
  leftClicks = 0,    -- 左键点击计数（诊断）
  rightClicks = 0,   -- 右键点击计数（诊断：为 0 = 右键根本没到分派代码）
  lastBtn = nil,     -- 最近一次 OnClick 判出的 button
  lastArgs = nil,    -- 最近一次 OnClick 的**原始参数形状**（a/b/arg1 的类型）
}

-- ===== 常量（单一来源；改这里就够） =====
-- ★1.74.5 用户（截图）：「两个助手的图标都太大了，需要和配置的图标相同」
--   ⇒ 与小地图/配置入口按钮**同尺寸 26×26**（EvalHelp.lua: `mb:SetWidth(26)`「边长 26（与图标库单格一致；按钮 = 图标，无内缩）」）。
--   ★位置记忆存的是「中心偏移」（与尺寸无关）⇒ 改尺寸不会让老存档的位置跑偏。
local HH_SIZE = 26
local HH_RATE = 1.0        -- ★1.74.10 用户：「喂食频率机制是什么? 设至少1s」—— 喂食间隔放宽到 1s/笔
local HH_AIM_WAIT = 1.0
local HH_SETTLE_WAIT = 0.8
local HH_QMAX = 3
local HH_MAX_CAND = 96
local HH_BAGS = { 0, 1, 2, 3, 4 }
local HH_DEF_W, HH_DEF_H = 1024, 768   -- UIParent 尺寸拿不到时的兜底（与项目其它位置换算同口径）
local HH_SPELL_CAND = { "喂食宠物", "Feed Pet" }
-- ★食物启发式词表：本客户端**没有**「某物品是不是宠物食物」的 API（全表只有 GetPetFoodTypes/GetStablePetFoodTypes），
--   所以下拉只能「全部列出 + 把像食物的排前面」；**吃不吃由客户端判定**（喂不动会如实回报并放回原格）。
--   词表按物品名里真会出现的字取；GetPetFoodTypes 的食谱名（如「肉类/鱼类」）也一并当信号。
local HH_FOOD_WORDS = { "肉", "鱼", "面包", "蘑菇", "水果", "奶酪", "蛋", "肠", "肋排", "禽",
                        "meat", "fish", "bread", "fruit", "fungus", "cheese", "egg" }
local HH_TEXT = "喂"
-- ★1.73.28 教训：Lua 源码里**绝不手写转义**（引号/反斜杠手写必写坏，且 luacheck 查不出来）→ 用 char 构造
local HH_QUOTE = string.char(34)
local HH_BSLASH = string.char(92)

-- ===== 配置与输出（唯一真值 = EVAL_HELP_CONFIG.tb，与工具箱同一张表） =====
local function hhCfg()
  local c = EVAL_HELP_CONFIG
  if type(c) ~= "table" then return nil end
  if type(c.tb) ~= "table" then c.tb = {} end
  return c.tb
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function hhSay(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

-- ★诊断走**不受开关门控**的日志通道（1.70.16 教训：日志写在开关之后 = 整条链路静默，白猜三轮）
local function hhLog(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[猎人助手] " .. tostring(msg)) end
end

local function hhOn()
  local tb = hhCfg()
  return (tb and tb.feedPet) and true or false
end

local function hhNow()
  if type(GetTime) == "function" then
    local ok, v = pcall(GetTime)
    if ok and type(v) == "number" then return v end
  end
  return 0
end

local function hhEsc(s)
  s = tostring(s or "")
  s = string.gsub(s, HH_BSLASH, HH_BSLASH .. HH_BSLASH)
  s = string.gsub(s, HH_QUOTE, HH_BSLASH .. HH_QUOTE)
  return s
end
-- ===== 背包读取（唯一真值 = 当次实时扫描） =====
local function hhSlots(bag)
  if type(GetContainerNumSlots) ~= "function" then return 0 end
  local ok, v = pcall(GetContainerNumSlots, bag)
  local n = ok and tonumber(v) or 0
  if not n or n < 0 then return 0 end
  return n
end

local function hhItemName(bag, slot)
  if type(GetContainerItemLink) ~= "function" then return nil end
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if not ok or type(link) ~= "string" then return nil end
  local nm = string.match(link, "%[(.-)%]")
  if nm and nm ~= "" then return nm end
  return nil
end

-- 返回 texture, count, locked（缺失一律 nil，调用方自己判）
local function hhItemInfo(bag, slot)
  if type(GetContainerItemInfo) ~= "function" then return nil, nil, nil, nil end
  local ok, tex, cnt, locked, q = pcall(GetContainerItemInfo, bag, slot)
  if not ok then return nil, nil, nil, nil end
  if type(tex) == "string" and tex == "" then tex = nil end -- ★文档：空格子返回空串（空串在 Lua 里是**真值**）
  return tex, tonumber(cnt), (locked and true or false), tonumber(q)
end

-- 宠物食谱关键词（GetPetFoodTypes 给的是**逗号分隔的本地化名**；本客户端没有「某物品是什么食物」的 API）
local function hhDietKeys()
  local out = {}
  if type(GetPetFoodTypes) ~= "function" then return out end
  local ok, s = pcall(GetPetFoodTypes)
  if not ok or type(s) ~= "string" or s == "" then return out end
  local i = 1
  while true do
    local p = string.find(s, ",", i, true)
    local part = p and string.sub(s, i, p - 1) or string.sub(s, i)
    part = string.gsub(part, "^%s*(.-)%s*$", "%1")
    if part ~= "" then table.insert(out, part) end
    if not p then break end
    i = p + 1
  end
  return out
end

local function hhIsLikelyFood(name)
  if type(name) ~= "string" or name == "" then return false end
  local low = string.lower(name)
  for i = 1, table.getn(HH_FOOD_WORDS) do
    if string.find(low, string.lower(HH_FOOD_WORDS[i]), 1, true) then return true end
  end
  local keys = hhDietKeys() -- 食谱名（本地化）也是信号
  for i = 1, table.getn(keys) do
    local k = string.lower(tostring(keys[i]))
    if k ~= "" and string.find(low, k, 1, true) then return true end
  end
  return false
end

-- ===== 公开读值口：候选 / 解析（纯读，不改任何状态） =====
-- ★1.74.5 扫描改用**共用数据源** EVAL_IG_SCAN_BAGS（IconGrid.lua）：喂食与消耗品助手共用同一份
--   「扫背包」代码，免得两处各写一份、行为慢慢漂开。本函数只额外做**食物优先排序**（语义与之前一致）。
function EVAL_HH_CANDIDATES()
  local list, total = {}, 0
  if type(EVAL_IG_SCAN_BAGS) == "function" then
    list, total = EVAL_IG_SCAN_BAGS(HH_BAGS)
  end
  local out = {}
  for i = 1, table.getn(list) do
    local it = list[i]
    if table.getn(out) < HH_MAX_CAND then
      table.insert(out, { name = it.name, bag = it.bag, slot = it.slot, tex = it.tex, count = it.count,
                          locked = it.locked, q = it.q, idx = it.idx,
                          score = hhIsLikelyFood(it.name) and 1 or 0 })
    end
  end
  -- ★可能食物排前面；table.sort 在 5.1 **不稳定** → 用 (score, idx) 装饰排序（项目既有结论）
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.idx < b.idx
  end)
  return out, total
end

-- 按**名字**在当前背包里解析出包格（喂食那一刻调用；锁定格跳过；同名多组取数量最大的）
function EVAL_HH_FIND_FOOD(name)
  if type(name) ~= "string" or name == "" then return nil end
  local bBag, bSlot, bTex, bCnt = nil, nil, nil, -1
  for bi = 1, table.getn(HH_BAGS) do
    local bag = HH_BAGS[bi]
    local n = hhSlots(bag)
    for slot = 1, n do
      if hhItemName(bag, slot) == name then
        local tex, cnt, locked = hhItemInfo(bag, slot)
        local c = cnt or 1
        if not locked and c > bCnt then bBag, bSlot, bTex, bCnt = bag, slot, tex, c end
      end
    end
  end
  if bBag then return bBag, bSlot, bTex, bCnt end
  return nil
end

-- ===== 喂食技能识别 =====
local function hhScanBook()
  if type(GetNumSpellTabs) ~= "function" or type(GetSpellName) ~= "function" then return nil end
  local okt, tabs = pcall(GetNumSpellTabs)
  tabs = (okt and tonumber(tabs)) or 0
  for t = 1, tabs do
    local oki, _, _, off, num = pcall(GetSpellTabInfo, t)
    if oki then
      off, num = tonumber(off) or 0, tonumber(num) or 0
      for i = off + 1, off + num do
        local okn, nm = pcall(GetSpellName, i, "spell")
        if okn and type(nm) == "string" then
          for ci = 1, table.getn(HH_SPELL_CAND) do
            if nm == HH_SPELL_CAND[ci] then return nm, i end
          end
        end
      end
    end
  end
  return nil
end

-- 手工指定优先；没指定则自动识别（**只缓存命中结果**，未命中 5 秒内不重复扫）
function EVAL_HH_SPELL()
  local tb = hhCfg()
  local want = tb and tb.hhSpell
  if type(want) == "string" and want ~= "" then return want, nil end
  if HH.spellCache then return HH.spellCache, HH.spellIndex end
  local now = hhNow()
  if (now - HH.spellAt) < 5 then return nil end
  HH.spellAt = now
  local nm, idx = hhScanBook()
  if nm then HH.spellCache, HH.spellIndex = nm, idx end
  return nm, idx
end

function EVAL_HH_SET_SPELL(name)
  local tb = hhCfg()
  if not tb then return false end
  tb.hhSpell = (type(name) == "string" and name ~= "") and name or nil
  HH.spellCache, HH.spellIndex, HH.spellAt = nil, nil, -999
  hhSay(string.format(L("HH_SET_SPELL"), tostring(name or "-")))
  hhLog("设置喂食技能 = " .. tostring(name))
  return true
end

function EVAL_HH_SET_FOOD(name, tex)
  local tb = hhCfg()
  if not tb then return false end
  if type(name) ~= "string" or name == "" then
    tb.hhFood, tb.hhFoodTex = nil, nil
    hhSay(L("HH_CLEARED"))
    EVAL_HH_REFRESH()
    return true
  end
  tb.hhFood, tb.hhFoodTex = name, tex
  hhSay(string.format(L("HH_SET_FOOD"), name))
  hhLog("设置食物 = " .. name)
  EVAL_HH_REFRESH()
  return true
end
-- ===== 目标态 / 光标 / 宠物 三个薄封装（缺 API 时如实返回 nil，绝不假装） =====
local function hhIsTargeting()
  if type(SpellIsTargeting) ~= "function" then return nil end
  local ok, v = pcall(SpellIsTargeting)
  if not ok then return nil end
  if v == 1 or v == true then return true end
  return false
end

local function hhCursorHasItem()
  if type(CursorHasItem) ~= "function" then return nil end
  local ok, v = pcall(CursorHasItem)
  if not ok then return nil end
  return v and true or false
end

local function hhHasPet()
  if type(HasPetUI) == "function" then
    local ok, v = pcall(HasPetUI)
    if ok and type(v) == "boolean" then return v end
  end
  if type(UnitExists) == "function" then
    local ok, v = pcall(UnitExists, "pet")
    if ok then return v and true or false end
  end
  return false
end

-- ===== 喂食状态机（跨帧：RunScript 是排队通道，当帧硬点背包必然踩空） =====
local function hhRelease()
  HH.phase = "idle"
  if table.getn(HH.q) == 0 and HH.tick then
    pcall(HH.tick.SetScript, HH.tick, "OnUpdate", nil) -- 队列空 → 摘掉 OnUpdate（不在后台空转）
  end
end

local function hhFail(msg)
  hhSay("❌ " .. tostring(msg))
  hhLog("失败：" .. tostring(msg))
  hhRelease()
  return false
end

local function hhOk()
  HH.hits = HH.hits + 1
  hhSay(string.format(L("HH_OK"), tostring(HH.food or "?")))
  hhLog("喂食完成：食物=" .. tostring(HH.food))
  HH.food = nil
  hhRelease()
  EVAL_HH_REFRESH()
  return true
end

local function hhFailUnclear()
  hhSay(L("HH_UNCLEAR"))
  hhLog("结果未确认（已点包但待选态未按时结束）")
  HH.food = nil
  hhRelease()
  EVAL_HH_REFRESH()
  return false
end

-- ① 施放：进入待选目标态（受保护函数走 RunScript —— 项目既有通道，Engine.lua 指定等级同款）
local function hhBegin(now, req)
  local tb = hhCfg()
  if not tb or not tb.feedPet then return hhFail(L("HH_OFF")) end
  if not hhHasPet() then return hhFail(L("HH_NO_PET")) end
  local foodName = (req and req.food) or tb.hhFood
  if type(foodName) ~= "string" or foodName == "" then return hhFail(L("HH_NO_FOOD_SET")) end
  local bag, slot = EVAL_HH_FIND_FOOD(foodName)
  if not bag then return hhFail(string.format(L("HH_FOOD_MISSING"), foodName)) end
  local spell = EVAL_HH_SPELL()
  if not spell then return hhFail(L("HH_NO_SPELL")) end
  if type(RunScript) ~= "function" then return hhFail(L("HH_NO_RUNSCRIPT")) end
  local script = "CastSpellByName(" .. HH_QUOTE .. hhEsc(spell) .. HH_QUOTE .. ")"
  local ok = pcall(RunScript, script)
  if not ok then return hhFail(L("HH_CAST_FAIL")) end
  HH.lastRun, HH.phase, HH.aimAt = now, "aim", now
  HH.food = foodName
  hhLog("施放 " .. tostring(spell) .. " → 等待选目标态（食物 " .. tostring(foodName) ..
        " @" .. tostring(bag) .. "," .. tostring(slot) .. "）")
  return true
end

-- ② 点包：把食物当技能目标。★必须**真的在待选态**才点 —— 否则这一下只会把食物捡到光标上
local function hhPick(now)
  if hhIsTargeting() ~= true then return hhFail(L("HH_AIM_FAIL")) end
  local bag, slot = EVAL_HH_FIND_FOOD(HH.food) -- ★按名字**重新解析**（包格会变）
  if not bag then return hhFail(string.format(L("HH_FOOD_MISSING"), tostring(HH.food))) end
  local ok = pcall(PickupContainerItem, bag, slot)
  if not ok then return hhFail(L("HH_PICK_FAIL")) end
  HH.phase, HH.settleAt = "settle", now
  hhLog("已点食物 @" .. tostring(bag) .. "," .. tostring(slot) .. " → 等结果")
  return true
end

-- ③ 收尾：光标上有东西 = 客户端没把它当目标（不是它的食物）→ **放回原格**并如实报
local function hhRestore(msg)
  if type(ClearCursor) == "function" then pcall(ClearCursor) end
  return hhFail(msg)
end

function EVAL_HH_STEP(now)
  now = tonumber(now) or hhNow()
  if HH.phase == "idle" then
    if table.getn(HH.q) > 0 and (now - HH.lastRun) >= HH_RATE then
      local req = table.remove(HH.q, 1)
      hhBegin(now, req)
    end
    if HH.phase == "idle" and table.getn(HH.q) == 0 then
      if HH.tick then pcall(HH.tick.SetScript, HH.tick, "OnUpdate", nil) end
    end
    return
  end
  if HH.phase == "aim" then
    if hhIsTargeting() == true then
      hhPick(now)
    elseif (now - HH.aimAt) > HH_AIM_WAIT then
      hhFail(L("HH_AIM_FAIL"))
    end
    return
  end
  if HH.phase == "settle" then
    local cur = hhCursorHasItem()
    if cur == true then
      hhRestore(L("HH_REJECT"))
    elseif cur == false and hhIsTargeting() ~= true then
      hhOk()
    elseif (now - HH.settleAt) > HH_SETTLE_WAIT then
      hhFailUnclear()
    end
  end
end

local function hhEnsureTick()
  if HH.tick then return HH.tick end
  local f = CreateFrame("Frame", nil, UIParent) -- ★不具名：具名帧会占用同名全局（FRAME NAME CLASH 教训）
  f:SetScript("OnUpdate", function() EVAL_HH_STEP(hhNow()) end)
  HH.tick = f
  return f
end

-- 一次点击的入口（= 入队；真正的执行在状态机里，受 HH_RATE 限频）
function EVAL_HH_FEED(req)
  if not hhOn() then return hhFail(L("HH_OFF")) end
  if table.getn(HH.q) >= HH_QMAX then return hhFail(L("HH_BUSY")) end
  table.insert(HH.q, req or {})
  hhEnsureTick()
  hhLog("喂食请求入队（队列 " .. tostring(table.getn(HH.q)) .. "）")
  return true
end
-- ===== UI（懒建：只有开关打开时才会走到 EVAL_HH_ENSURE） =====
local function hhSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function hhText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(fs.SetFontObject, fs, fo) then ok = true break end
  end
  if not ok then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okf, ok2 = pcall(fs.SetFont, fs, fp, size, "")
      if okf and ok2 then ok = true break end
    end
  end
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

local function hhSavePos()
  local b = HH.btn
  if not b then return end
  local okl, l = pcall(b.GetLeft, b)
  local okt, t = pcall(b.GetTop, b)
  if not (okl and okt and l and t) then return end
  local s = 1
  local oks, es = pcall(b.GetEffectiveScale, b)
  if oks and type(es) == "number" and es > 0 then s = es end
  local tb = hhCfg()
  if not tb then return end
  -- ★存「图标中心相对 UIParent 中心的偏移」（与项目其它记忆位置同一口径；含缩放 → 要除）
  local okw, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  local bw, bh = HH_SIZE, HH_SIZE
  local okbw, v1 = pcall(b.GetWidth, b)
  if okbw and type(v1) == "number" then bw = v1 end
  local okbh, v2 = pcall(b.GetHeight, b)
  if okbh and type(v2) == "number" then bh = v2 end
  if okw and okh and w2 and h2 then
    tb.hhX = (l + bw / 2 - w2 / 2) / s
    tb.hhY = (t - bh / 2 - h2 / 2) / s
  end
end

local function hhTip(b)
  if type(GameTooltip) ~= "table" then return end
  local tb = hhCfg() or {}
  pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
  pcall(GameTooltip.ClearLines, GameTooltip)
  pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_TITLE"), 1, 0.82, 0.3)
  local food = tb.hhFood
  local bag, slot, _, cnt = nil, nil, nil, nil
  if type(food) == "string" and food ~= "" then bag, slot, _, cnt = EVAL_HH_FIND_FOOD(food) end
  if bag then
    pcall(GameTooltip.AddLine, GameTooltip,
          string.format(L("HH_TT_FOOD"), food, tostring(bag), tostring(slot), tostring(cnt or 1)), 0.9, 0.9, 0.9)
  else
    pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_NOFOOD"), 1, 0.5, 0.4)
  end
  local sp = EVAL_HH_SPELL()
  pcall(GameTooltip.AddLine, GameTooltip,
        string.format(L("HH_TT_SPELL"), tostring(sp or L("HH_TT_SPELL_NONE"))), 0.9, 0.9, 0.9)
  if not hhHasPet() then pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_NOPET"), 1, 0.5, 0.4) end
  pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_LEFT"), 0.6, 1, 0.6)
  pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_RIGHT"), 0.6, 0.8, 1)
  pcall(GameTooltip.AddLine, GameTooltip, L("HH_TT_DRAG"), 0.7, 0.7, 0.7)
  pcall(GameTooltip.AddLine, GameTooltip, string.format(L("HH_TT_CNT"), tostring(HH.hits or 0)), 0.7, 0.7, 0.7)
  pcall(GameTooltip.Show, GameTooltip)
end

-- 图标贴图：食物图标（实时解析）；解析不到 → 保底文字（不写纹理字面量 → 不碰 ICON 白名单）
function EVAL_HH_REFRESH()
  if not (HH.built and HH.btn) then return false end
  local tb = hhCfg() or {}
  local food = tb.hhFood
  local tex, bag = nil, nil
  if type(food) == "string" and food ~= "" then
    local _, _, t = EVAL_HH_FIND_FOOD(food)
    local b2 = EVAL_HH_FIND_FOOD(food)
    tex, bag = t, b2
  end
  if not tex then tex = tb.hhFoodTex end
  if tex then
    local ok = pcall(HH.tex.SetTexture, HH.tex, tex)
    if ok then pcall(HH.tex.Show, HH.tex) else pcall(HH.tex.Hide, HH.tex) end
    pcall(HH.label.Hide, HH.label)
  else
    pcall(HH.tex.Hide, HH.tex)
    pcall(HH.label.SetText, HH.label, HH_TEXT)
    pcall(HH.label.Show, HH.label)
  end
  HH.foodBag = bag
  return true
end

-- ★★★1.74.5 位置换算的**单一来源**：项目里其它窗口存的是「中心偏移」（hhX 向右为正、hhY 向上为正），
--   而本图标用 TOPLEFT 锚点落地 → 换算必须成对：x = w/2 + cx - s/2；y = -(h/2 - cy - s/2)（**y 向下为负**）。
--   ★本轮修掉两个写法错误：① 「y = h/2 + cy - s/2」把方向写反（真机上会落到屏幕上方之外）；
--     ② x 少减了 s/2（恒定偏 18px）。
--   ★越界回归：**在偏移量上直接夹取**，保证四边永远在屏幕内 —— 不用 EVAL_UIOFFSCREEN 是因为它读的是
--     GetTop/GetBottom 的「距屏底」语义并要乘缩放，对「中心偏移」这种存法既绕又不好在桩里验；
--     夹取与它的**目的相同**（绝不还原到屏幕外），语义更干净。
-- ★1.74.5 换算本体抽到共用件 EVAL_IG_TOPLEFT（消耗品助手要用同一份 —— 免得两处各写、方向错一个就歪）
local function hhTopLeft(sw, sh, cx, cy)
  if type(EVAL_IG_TOPLEFT) == "function" then return EVAL_IG_TOPLEFT(sw, sh, HH_SIZE, cx, cy) end
  return sw / 2 + (tonumber(cx) or 0) - HH_SIZE / 2, -(sh / 2 - (tonumber(cy) or 0) - HH_SIZE / 2)
end

-- 懒建（幂等）：开关打开 / 首次需要时才建帧
function EVAL_HH_ENSURE()
  if HH.built and HH.btn then return HH.btn end
  local b = CreateFrame("Button", nil, UIParent)
  b:SetWidth(HH_SIZE)
  b:SetHeight(HH_SIZE)
  local tb = hhCfg() or {}
  local okc, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  if not (okc and type(w2) == "number" and w2 > 0) then w2 = HH_DEF_W end
  if not (okh and type(h2) == "number" and h2 > 0) then h2 = HH_DEF_H end
  -- ★1.74.5 用户要求：**默认打开在窗口中间**（没有记忆位置时 hhX/hhY = 0 → 正中）
  local x, y = hhTopLeft(w2, h2, tb.hhX, tb.hhY)
  pcall(b.SetPoint, b, "TOPLEFT", UIParent, "TOPLEFT", x, y)
  pcall(b.SetMovable, b, true)
  pcall(b.EnableMouse, b, true)
  local okrc, errrc = pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  HH.regClicks = tostring(okrc) .. (okrc and "" or (":" .. tostring(errrc)))
  pcall(b.RegisterForDrag, b, "LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  hhSolid(bg, 0.06, 0.05, 0.04, 0.85)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  -- 四边 1px 亮边（项目配方：纯色纹理 WHITE8X8 + 顶点色）
  for i = 1, 4 do
    local e = b:CreateTexture(nil, "BORDER")
    hhSolid(e, 0.85, 0.70, 0.20, 0.9)
    if i == 1 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
      e:SetHeight(1)
    end
    if i == 2 then
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      e:SetHeight(1)
    end
    if i == 3 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      e:SetWidth(1)
    end
    if i == 4 then
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
      e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      e:SetWidth(1)
    end
  end
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  tex:Hide()
  local label = hhText(b, 12, 0.95, 0.80, 0.30) -- 26px 里 12pt 才不挤（原 36px 用 14pt）
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(label.SetWidth, label, HH_SIZE)
  label:SetText(HH_TEXT)
  HH.btn, HH.tex, HH.label, HH.built = b, tex, label, true
  -- ★★★1.74.5 实测修正（用户报「右键选食物无法触发」）：**本客户端 OnClick 的参数形态不固定**——
  --   主程序里两处已实测的右键分派（技能格 1.74.2 · 方案标签）都写成「四候选」：
  --     mbtn = (type(a)=="string" and a) or (type(b)=="string" and b) or (type(arg1)=="string" and arg1) or "LeftButton"
  --   我第一版照教科书写 `function(_, button)`：客户端把 self 放第一位时 `button` 恒 nil
  --   → **右键掉进左键分支**（去喂食了）→ 菜单永远不出现，正是用户看到的现象。
  --   ★同时把「原始形状」记进 HH：探针能一眼看清客户端到底怎么调，下次不用猜。
  b:SetScript("OnClick", function(a, b2)
    local mbtn = (type(a) == "string" and a) or (type(b2) == "string" and b2)
                 or (type(arg1) == "string" and arg1) or "LeftButton"
    HH.lastBtn = mbtn
    HH.lastArgs = tostring(type(a)) .. "/" .. tostring(type(b2)) .. "/" .. tostring(type(arg1))
    local isRight = (mbtn == "RightButton") or (string.find(mbtn, "Right", 1, true) ~= nil)
    if isRight then
      HH.rightClicks = (HH.rightClicks or 0) + 1
      EVAL_HH_MENU()
    else
      HH.leftClicks = (HH.leftClicks or 0) + 1
      EVAL_HH_FEED()
    end
  end)
  b:SetScript("OnDragStart", function()
    pcall(b.StartMoving, b)
    pcall(b.StopMovingOrSizing, b)
    pcall(b.StartMoving, b) -- warm-up 两步（本客户端实测配方：不做这步拖不动）
  end)
  b:SetScript("OnDragStop", function()
    pcall(b.StopMovingOrSizing, b)
    hhSavePos()
  end)
  b:SetScript("OnEnter", function() hhTip(b) end)
  b:SetScript("OnLeave", function() if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end end)
  hhLog("图标已建立（懒建：开关打开才建帧）")
  EVAL_HH_REFRESH()
  return b
end

-- 下拉模型：条目与动作**一一对应**（测试读值口读同一份模型，绝不在测试里复刻逻辑）
function EVAL_HH_MENU_MODEL()
  local items, acts = {}, {}
  local function add(text, act) table.insert(items, text) table.insert(acts, act) end
  add(L("HH_DD_SETSPELL"), { k = "spell" })
  local cand, total = EVAL_HH_CANDIDATES()
  local n = table.getn(cand)
  for i = 1, n do
    local c = cand[i]
    add(string.format(L("HH_DD_ITEM"), tostring(c.name), tostring(c.count or 1), tostring(c.bag), tostring(c.slot)),
        { k = "food", name = c.name, tex = c.tex })
  end
  if total > n then add(string.format(L("HH_DD_MORE"), tostring(total - n)), { k = "none" }) end
  add(L("HH_DD_CLEAR"), { k = "clear" })
  return items, acts
end

function EVAL_HH_DD_APPLY(pi, acts)
  acts = acts or (HH.dd and HH.dd.acts)
  if type(acts) ~= "table" then return false end
  local a = acts[pi]
  if type(a) ~= "table" then return false end
  if a.k == "spell" then return EVAL_HH_SPELL_MENU() end
  if a.k == "food" then return EVAL_HH_SET_FOOD(a.name, a.tex) end
  if a.k == "clear" then return EVAL_HH_SET_FOOD(nil) end
  return false
end

function EVAL_HH_MENU()
  if not (HH.built and HH.btn) then return false end
  -- ★1.74.5 用户要求：「图标搭配 tooltip，类似背包四方格布局 8×N」→ 优先开**图标网格**；
  --   网格建不起来（老客户端/异常）才降级回文本下拉 —— 降级也要说出来，不静默。
  if type(EVAL_HH_GRID_OPEN) == "function" then
    local okg, resg = pcall(EVAL_HH_GRID_OPEN)
    if okg and resg then return true end
    hhLog("图标网格打不开（" .. tostring(resg) .. "）→ 降级用文本下拉")
  end
  if type(EVAL_DD_OPEN) ~= "function" then hhSay(L("HH_NO_DD")) return false end
  local items, acts = EVAL_HH_MENU_MODEL()
  HH.dd = { items = items, acts = acts }
  EVAL_DD_OPEN(HH.btn, items, function(pi) EVAL_HH_DD_APPLY(pi, acts) end)
  return true
end

-- 二级：从法术书里挑喂食技能（ruRU 等语言识别不到时的**唯一可靠**路径）
function EVAL_HH_SPELL_MENU()
  if type(EVAL_DD_OPEN) ~= "function" then return false end
  local names = {}
  if type(GetNumSpellTabs) == "function" and type(GetSpellName) == "function" then
    local okt, tabs = pcall(GetNumSpellTabs)
    tabs = (okt and tonumber(tabs)) or 0
    for t = 1, tabs do
      local oki, _, _, off, num = pcall(GetSpellTabInfo, t)
      if oki then
        off, num = tonumber(off) or 0, tonumber(num) or 0
        for i = off + 1, off + num do
          local okn, nm = pcall(GetSpellName, i, "spell")
          if okn and type(nm) == "string" and nm ~= "" and table.getn(names) < HH_MAX_CAND then
            table.insert(names, nm)
          end
        end
      end
    end
  end
  if table.getn(names) == 0 then hhSay(L("HH_NO_SPELLBOOK")) return false end
  EVAL_DD_OPEN(HH.btn, names, function(pi) EVAL_HH_SET_SPELL(names[pi]) end)
  return true
end

-- ★★★1.74.5 用户实测：开着一键喂食、把图标拖好，**/reload 之后图标不见了**。
--   【根因】开关（tb.feedPet）只存了**状态**；图标帧是**点开关那一下**才懒建的，
--     而登录流程里没有任何人替用户「再点一次」→ 配置是开的、帧却不存在（工具箱里那个勾还亮着，自相矛盾）。
--   【修法】导出 EVAL_HH_RESTORE()，由 EvalHelp.lua 的 VARIABLES_LOADED 钩子调用
--     （与「战斗信息UI：上次开着的话恢复显示」同一条纪律）；**仍然懒**：配置关着的用户一个帧都不会建。
--   ★位置也在这条路上：hhTopLeft 用 tb.hhX/hhY（拖动时由 hhSavePos 存下）⇒「拖到哪就还在哪」。
--   ★再给一次机会：UIParent 尺寸在 VARIABLES_LOADED 时可能还没定下来 → EVAL_HH_REAPPLY_POS 可被
--     后续事件（PLAYER_ENTERING_WORLD）再调一次，按**那时的**真实尺寸重算锚点（幂等）。
function EVAL_HH_REAPPLY_POS()
  if not (HH.built and HH.btn) then return false end
  local tb = hhCfg() or {}
  local okc, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  if not (okc and type(w2) == "number" and w2 > 0) then w2 = HH_DEF_W end
  if not (okh and type(h2) == "number" and h2 > 0) then h2 = HH_DEF_H end
  local x, y = hhTopLeft(w2, h2, tb.hhX, tb.hhY)
  pcall(HH.btn.ClearAllPoints, HH.btn)
  pcall(HH.btn.SetPoint, HH.btn, "TOPLEFT", UIParent, "TOPLEFT", x, y)
  return true
end

function EVAL_HH_RESTORE()
  local tb = hhCfg()
  if not (tb and tb.feedPet) then return false end -- 关着 = 什么都不建（懒加载仍然成立）
  if not (HH.built and HH.btn) then
    EVAL_HH_ENSURE()
  else
    EVAL_HH_REAPPLY_POS() -- 已经建过（登录时尺寸还没定 / 二次事件）→ 按当前尺寸重算位置
  end
  EVAL_HH_REFRESH()
  if HH.btn then pcall(HH.btn.Show, HH.btn) end
  hhLog("登录恢复：开关是开的 → 图标已重建并显示（位置 " .. tostring(tb.hhX) .. "," .. tostring(tb.hhY) .. "）")
  return true
end

-- 工具箱开关的**即时副作用**（开关一勾就建/显示，取消就收起）
function EVAL_HH_TOGGLE()
  if not hhOn() then
    if HH.btn then pcall(HH.btn.Hide, HH.btn) end
    hhSay(L("HH_OFF_MSG"))
    hhLog("总闸门关闭 → 图标收起（帧保留但不可见，开销为零）")
    return false
  end
  EVAL_HH_ENSURE()
  EVAL_HH_REFRESH()
  if HH.btn then pcall(HH.btn.Show, HH.btn) end
  hhSay(L("HH_ON_MSG"))
  hhLog("总闸门打开 → 图标已显示")
  return true
end
-- ===== 模块级状态复位（测试用；★放在文件**末尾**，否则 DECL ORDER 会抓「用在前、声明在后」） =====
function EVAL_HH_TEST_RESET_TIMERS()
  HH.q, HH.phase, HH.lastRun, HH.aimAt, HH.settleAt = {}, "idle", -999, 0, 0
  if HH.tick then pcall(HH.tick.SetScript, HH.tick, "OnUpdate", nil) end
end

-- ===== 诊断命令（/eh go 喂食* ；与项目「能做成命令就别让用户手工复现」一致） =====
local function hhAvail(name)
  local v = _G[name]
  if type(v) == "function" then return "function✓" end
  return tostring(type(v))
end

function EVAL_HH_CMD(msg)
  msg = tostring(msg or "")
  local sub = string.match(msg, "^go 喂食探针%s*(.-)%s*$")
  if sub ~= nil then return EVAL_HH_PROBE(sub) end
  local feedArg = string.match(msg, "^go 喂食%s*(.-)%s*$")
  if feedArg ~= nil then
    if feedArg == "" then
      EVAL_HH_FEED()
      return true
    end
    local setName = string.match(feedArg, "^设%s*(.-)%s*$")
    if setName then
      if setName == "" then hhSay("用法：/eh go 喂食 设 <食物名>") return false end
      return EVAL_HH_SET_FOOD(setName)
    end
    local spName = string.match(feedArg, "^技能%s*(.-)%s*$")
    if spName and spName ~= "" then return EVAL_HH_SET_SPELL(spName) end
    if feedArg == "状态" then return EVAL_HH_PROBE("") end
    return false
  end
  hhSay("用法：/eh go 喂食（一键喂食）｜ 喂食 设 <食物名> ｜ 喂食 技能 <名> ｜ 喂食探针 [扫书|施放 <名>|喂 <包> <格>|拖|收光标]")
  return false
end

function EVAL_HH_PROBE(sub)
  sub = tostring(sub or "")
  if sub == "" then
    hhSay("— 猎人助手 · 喂食探针（可用性矩阵）—")
    hhSay("接口：RunScript=" .. hhAvail("RunScript") .. " CastSpellByName=" .. hhAvail("CastSpellByName") ..
          " UseAction=" .. hhAvail("UseAction"))
    hhSay("　　　PickupContainerItem=" .. hhAvail("PickupContainerItem") ..
          " PickupInventoryItem=" .. hhAvail("PickupInventoryItem") ..
          " UseContainerItem=" .. hhAvail("UseContainerItem"))
    hhSay("　　　SpellIsTargeting=" .. hhAvail("SpellIsTargeting") .. " CursorHasItem=" .. hhAvail("CursorHasItem") ..
          " ClearCursor=" .. hhAvail("ClearCursor") .. " DropItemOnUnit=" .. hhAvail("DropItemOnUnit"))
    hhSay("宠物：HasPetUI=" .. hhAvail("HasPetUI") .. " GetPetFoodTypes=" .. hhAvail("GetPetFoodTypes") ..
          " GetPetHappiness=" .. hhAvail("GetPetHappiness") .. " PetHasActionBar=" .. hhAvail("PetHasActionBar"))
    hhSay("状态：有宠物=" .. tostring(hhHasPet()) .. " ｜ 待选目标态=" .. tostring(hhIsTargeting()) ..
          " ｜ 光标有物=" .. tostring(hhCursorHasItem()))
    local okh, h1, h2, h3 = pcall(GetPetHappiness)
    if okh then
      hhSay(string.format("快乐度：档位=%s 伤害%%=%s 忠诚速率=%s（1.12 喂食 = 提快乐度，不是治疗）",
                          tostring(h1), tostring(h2), tostring(h3)))
    else
      hhSay("GetPetHappiness 调用失败：" .. tostring(h1))
    end
    local okf, ft = pcall(GetPetFoodTypes)
    hhSay("食谱（GetPetFoodTypes）：" .. tostring(okf and ft or "（接口缺失）"))
    local tb = hhCfg() or {}
    hhSay("设置：总闸门=" .. tostring(tb.feedPet) .. " ｜ 食物=" .. tostring(tb.hhFood or "（未设置）") ..
          " ｜ 喂食技能=" .. tostring(tb.hhSpell or "（自动识别）"))
    local auto = EVAL_HH_SPELL()
    hhSay("自动识别的技能：" .. tostring(auto or "（没找到 → 用 喂食 技能 <名> 手工指定，或右键图标从法术书挑）"))
    if type(tb.hhFood) == "string" and tb.hhFood ~= "" then
      local bag, slot, _, cnt = EVAL_HH_FIND_FOOD(tb.hhFood)
      hhSay("食物解析：" .. (bag and string.format("找到 @%d,%d ×%s", bag, slot, tostring(cnt or 1))
                                or "**背包里找不到**（这种情况会拒绝施放，不会乱挑）"))
    end
    local cand, total = EVAL_HH_CANDIDATES()
    hhSay(string.format("背包物品：%d 件（下拉候选上限 %d）→ 右键图标选食物", total, HH_MAX_CAND))
    -- ★1.74.5 用户报「右键选食物无法触发」后加：把**点击分派真相**一次摊开
    --   （右键计数为 0 = 事件没到分派代码；lastBtn 恒 LeftButton = 参数取错，本项目老坑）
    hhSay("点击分派：注册右键=" .. tostring(HH.regClicks) .. " ｜ 左键 " .. tostring(HH.leftClicks or 0) ..
          " 次 / 右键 " .. tostring(HH.rightClicks or 0) .. " 次 ｜ 最近 button=" .. tostring(HH.lastBtn) ..
          "（参数形状 a/b/arg1 = " .. tostring(HH.lastArgs) .. "）")
    hhSay("下拉件：EVAL_DD_OPEN=" .. hhAvail("EVAL_DD_OPEN") ..
          " ｜ 候选 " .. tostring(table.getn(cand)) .. "/" .. tostring(total) .. " 项会进菜单")
    return true
  end
  if sub == "扫书" then
    hhSay("— 法术书扫描（找「喂食宠物」类技能）—")
    local okt, tabs = pcall(GetNumSpellTabs)
    tabs = (okt and tonumber(tabs)) or 0
    local found = 0
    for t = 1, tabs do
      local oki, pageName, _, off, num = pcall(GetSpellTabInfo, t)
      if oki then
        off, num = tonumber(off) or 0, tonumber(num) or 0
        for i = off + 1, off + num do
          local okn, sname, ssub = pcall(GetSpellName, i, "spell")
          if okn and type(sname) == "string" then
            for ci = 1, table.getn(HH_SPELL_CAND) do
              if sname == HH_SPELL_CAND[ci] then
                found = found + 1
                hhSay(string.format("命中：%s（下标 %d，页 %s）sub=%s", sname, i, tostring(pageName), tostring(ssub)))
              end
            end
          end
        end
      end
    end
    if found == 0 then
      hhSay("候选名 " .. table.concat(HH_SPELL_CAND, " / ") ..
            " 都没命中 → 请把法术书里的真名用「/eh go 喂食 技能 <名>」手工指定")
    end
    return true
  end
  local castName = string.match(sub, "^施放%s*(.-)%s*$")
  if castName then
    local nm = (castName ~= "") and castName or EVAL_HH_SPELL()
    if not nm then hhSay("没指定技能名、也自动识别不到 → 用 /eh go 喂食探针 施放 <真名>") return false end
    hhSay("施放前：SpellIsTargeting=" .. tostring(hhIsTargeting()))
    if type(RunScript) ~= "function" then hhSay("本客户端没有 RunScript → 换动作条方案（UseAction）") return false end
    local script = "CastSpellByName(" .. HH_QUOTE .. hhEsc(nm) .. HH_QUOTE .. ")"
    local ok = pcall(RunScript, script)
    hhSay("已投递脚本（pcall=" .. tostring(ok) .. "）：" .. script)
    hhSay("★排队通道不是当帧生效 → 请 0.5 秒后再敲一次「/eh go 喂食探针」看 SpellIsTargeting 是否变 1")
    return true
  end
  local bagS, slotS = string.match(sub, "^喂%s*(%-?%d+)%s+(%d+)")
  if bagS then
    local bag, slot = tonumber(bagS), tonumber(slotS)
    local nm = hhItemName(bag, slot)
    if not nm then hhSay(string.format("格子 %d,%d 是空的", bag, slot)) return false end
    hhSay(string.format("目标：%s @%d,%d ｜ 喂前 SpellIsTargeting=%s CursorHasItem=%s",
                        nm, bag, slot, tostring(hhIsTargeting()), tostring(hhCursorHasItem())))
    if hhIsTargeting() ~= true then
      hhSay("⚠️ 现在不在待选目标态 → 先「喂食探针 施放 <名>」，否则这一下只会把物品捡到光标上（探针照点，看真实反应）")
    end
    local ok = pcall(PickupContainerItem, bag, slot)
    hhSay("PickupContainerItem(" .. tostring(bag) .. "," .. tostring(slot) .. ") pcall=" .. tostring(ok))
    hhSay("点后：SpellIsTargeting=" .. tostring(hhIsTargeting()) .. " CursorHasItem=" .. tostring(hhCursorHasItem()))
    local okh, h1 = pcall(GetPetHappiness)
    hhSay("快乐度档位=" .. tostring(okh and h1) .. "（喂成功应有变化）")
    hhSay("该格：" .. (hhItemName(bag, slot) and "还有物品" or "**已空 → 很可能喂进去了**"))
    if hhCursorHasItem() == true then hhSay("光标上有物品 → 客户端没把它当目标；用「喂食探针 收光标」放回") end
    return true
  end
  if sub == "拖" then
    hhSay("反向哨兵：DropItemOnUnit(\"pet\")（本客户端文档明写「不倒给宠物」→ 预期不动）")
    if type(DropItemOnUnit) ~= "function" then hhSay("接口缺失") return false end
    local ok = pcall(DropItemOnUnit, "pet")
    hhSay("pcall=" .. tostring(ok) .. " ｜ 光标有物=" .. tostring(hhCursorHasItem()))
    return true
  end
  if sub == "收光标" then
    if type(ClearCursor) == "function" then pcall(ClearCursor) end
    hhSay("已 ClearCursor（物品放回原格）")
    return true
  end
  hhSay("未知子命令：" .. sub)
  return false
end

-- ★测试读值口（读**真实状态**，绝不在测试里复刻逻辑）
function EVAL_TEST_HH_STATE()
  local tb = hhCfg() or {}
  local shown = nil
  if HH.btn and type(HH.btn.IsShown) == "function" then shown = HH.btn:IsShown() end
  return { built = HH.built, shown = shown, on = tb.feedPet and true or false,
           leftClicks = HH.leftClicks, rightClicks = HH.rightClicks, lastBtn = HH.lastBtn,
           lastArgs = HH.lastArgs, regClicks = HH.regClicks,
           food = tb.hhFood, foodTex = tb.hhFoodTex, spell = tb.hhSpell,
           phase = HH.phase, qn = table.getn(HH.q), hasTick = HH.tick and true or false, hits = HH.hits,
           rate = HH_RATE, qmax = HH_QMAX, lastRun = HH.lastRun } -- ★1.74.10 限频常量+上次执行时刻也暴露
end

-- ★1.74.5 测试读值口：用**给定参数**驱动真实 OnClick（本客户端参数形态不固定，四种都要能验）
function EVAL_TEST_HH_CLICK(a, b)
  if not (HH.btn and type(HH.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(HH.btn.GetScript, HH.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, a, b)
  return okc, err
end

function EVAL_TEST_HH_GEOM()
  local b = HH.btn
  if not b then return nil end
  local okl, l = pcall(b.GetLeft, b)
  local okt, t = pcall(b.GetTop, b)
  local okw, w = pcall(b.GetWidth, b)
  local okh, h = pcall(b.GetHeight, b)
  return { left = okl and l or nil, top = okt and t or nil, w = okw and w or nil, h = okh and h or nil }
end

function EVAL_TEST_HH_RESET_UI()
  -- 只让下一次 ENSURE 重新走「懒建 + 定位」（测默认居中 / 记忆位置 / 越界夹取用）
  HH.built, HH.btn, HH.tex, HH.label = false, nil, nil, nil
end

function EVAL_TEST_HH_DD()
  local items, acts = EVAL_HH_MENU_MODEL()
  HH.dd = { items = items, acts = acts }
  return items, acts
end

-- ================================================================================
-- ===== 「选食物」图标网格 = **共用件** tools/IconGrid.lua 的薄封装（1.74.5）=========
-- 用户要求「图标搭配 tooltip，类似背包四方格布局 8×N」；抽成共用件的原因：**消耗品助手要用同一份网格**
--   （多选版）—— 本项目铁律「同一内容不许两处各写」，否则两边行为会慢慢漂开。
-- 本文件只负责把「食物候选 / 单选 / 选完写配置」交给 IconGrid；格子不自绘边框、高度自适应、
--   分页/滚轮/夹取/tooltip 全在共用件里。
-- ★对外名字（EVAL_HH_GRID_* 与 EVAL_TEST_HH_GRID*）**保持不变**：既有判据（组 176⑮⑯⑰）与取证命令不受影响。
local function hhGridSpec()
  return {
    key = "food",
    anchor = HH.btn,
    title = L("HH_G_TITLE"),
    hint = L("HH_G_PICK"),
    mode = "single",
    candidates = function() return EVAL_HH_CANDIDATES() end,
    onPick = function(it) EVAL_HH_SET_FOOD(it.name, it.tex) end,
    btnAText = L("HH_G_CLEAR"),
    btnA = function()
      EVAL_HH_SET_FOOD(nil)
      EVAL_IG_REFRESH()
    end,
    btnBText = L("HH_G_SKILL"),
    btnB = function()
      EVAL_IG_HIDE()
      EVAL_HH_SPELL_MENU()
    end,
  }
end

local function hhGridIsFood()
  local st = EVAL_TEST_IG_STATE()
  return (type(st) == "table" and st.key == "food") and st or nil
end

function EVAL_HH_GRID_BUILD() return EVAL_IG_ENSURE() end
function EVAL_HH_GRID_OPEN() return EVAL_IG_OPEN(hhGridSpec()) end

function EVAL_HH_GRID_REFRESH()
  if hhGridIsFood() then return EVAL_IG_REFRESH() end
  return false
end

function EVAL_HH_GRID_HIDE()
  if hhGridIsFood() then return EVAL_IG_HIDE() end
  return false
end

function EVAL_TEST_HH_GRID()
  local st = hhGridIsFood()
  if not st then return nil end
  return st
end

function EVAL_TEST_HH_GRID_TEX(i) return EVAL_TEST_IG_TEX(i) end
function EVAL_TEST_HH_GRID_CLICK(i) return EVAL_TEST_IG_CLICK(i) end
function EVAL_TEST_HH_GRID_HOVER(i) return EVAL_TEST_IG_HOVER(i) end
function EVAL_TEST_HH_GRID_PAGE(which) return EVAL_TEST_IG_PAGE(which) end
function EVAL_TEST_HH_GRID_WHEEL(a, b) return EVAL_TEST_IG_WHEEL(a, b) end
