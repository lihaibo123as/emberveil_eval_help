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
  cdUntil = 0,       -- ★1.74.11 CD 截止时刻（喂食施法走 GCD 1.5s）
  cdTotal = 0,       -- ★CD 总时长
  cdText = nil,      -- ★倒计时文字控件（懒建）
  cdTick = nil,      -- ★CD 刷新 OnUpdate 帧（CD 结束即摘）
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
local HH_RATE = 2.0        -- ★1.74.10 用户：「公共CD 是1.5s 喂食间隔设置2s」—— 间隔放宽到 2s/笔（给 1.5s GCD 留余量）
local HH_AIM_WAIT = 1.0
local HH_SETTLE_WAIT = 0.8
local HH_QMAX = 3
-- ★★★1.74.29 新增：**服务器动作闸门 + 审计**（用户：「某些情况下点喂食会被提下线」）
--   根据：本项目已实测「一帧 24 次 UseContainerItem 被服务器反滥用踢线」——所以只靠「每笔 2 秒」不够，
--   还要保证：任意两次服务器动作**不同帧**、且间隔 ≥ HH_ACT_GAP；1 秒内 ≥ HH_BURST_MAX 次则硬停。
local HH_ACT_GAP = 0.2       -- ★★用户明确：「固定 0.2s 的延迟都可以」——两次服务器动作的最小间隔（**延迟，不拒绝**）
local HH_BURST_MAX = 8       -- ★仅作记账用（不再硬停）：一秒窗口内超过就记一笔，供探针查看
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
  -- ★★★1.74.20 用户：「喂食助手…整块按角色」——食物/喂食技能/开关/图标位置都存**角色级存档**。
  --   （猎人的宠物与食物本来就各角色各囤各的；共用一份会在换号时错乱。）
  if type(EVAL_TB_CHAR_STORE) ~= "function" then return nil end
  return EVAL_TB_CHAR_STORE()
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
    -- ★1.74.28 弹窗候选**开类型过滤**（用户：「喂食助手 弹窗选的物品项目要过滤一下.不要显示武器,装备.
    --   灰色物品,草药,矿物,任务物品,材料等等非可食用的物品」）：判定在 IconGrid 的共用件里（三级：
    --   品质 → GetItemInfo(链接) → 自建 tooltip 兜底并顺手把物品写进客户端缓存）。
    -- ★★1.74.29：加 keepNames 例外 —— 「像食物」的物品即使被判为**材料/贸易品**也保留
    --   （肉类正属于这一类；不加这条，大块野猪肉这类真食物会被类型过滤整个剔掉）
    list, total = EVAL_IG_SCAN_BAGS(HH_BAGS, {
      classify = true,
      keepNames = function(nm) return hhIsLikelyFood(nm) end,
    })
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

local function hhOk(now)
  HH.hits = HH.hits + 1
  hhSay(string.format(L("HH_OK"), tostring(HH.food or "?")))
  hhLog("喂食完成：食物=" .. tostring(HH.food))
  HH.food = nil
  -- ★1.74.11 CD 倒计时：喂食施法走**公共 CD 1.5s**（GCD 默认值；
  --   食物本身没单独 CD 可查，公共 CD 是真实约束）。
  --   ★截止时刻用**喂完那一刻的真实时间**（step 的 now 参数），不是 hhNow()（GetTime 可能滞后）。
  local t = tonumber(now) or hhNow()
  HH.cdUntil = t + 1.5
  HH.cdTotal = 1.5
  EVAL_HH_CD_REFRESH()
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

-- ★服务器动作闸门（统一入口）：返回 true = 放行；false = 本帧/本刻不该发
local HH_ACT = { last = -999, lastFrame = -1, log = {}, sec = 0, secCount = 0, secNo = 0, maxBurst = 0, blocked = 0 }

-- ★★★1.74.29 用户实测「第一下就被拦」后重构：**去掉拒绝，只留延迟**。
--   · hhActReady(now) = 现在能不能发动作（距上一次 ≥ HH_ACT_GAP）；不能就**等下一帧再来**（状态机每帧都跑），**不会吃掉玩家的点击**。
--   · hhActMark(kind, now) = 真正发出动作后记时间 + 审计。
local function hhActReady(now)
  now = tonumber(now) or hhNow()
  if (now - HH_ACT.last) < HH_ACT_GAP then
    HH_ACT.deferred = (HH_ACT.deferred or 0) + 1
    return false
  end
  return true
end

local function hhActMark(kind, now)
  now = tonumber(now) or hhNow()
  HH_ACT.last, HH_ACT.lastKind = now, kind
  local sec = math.floor(now)
  if sec ~= HH_ACT.sec then
    if HH_ACT.secCount > HH_ACT.maxBurst then HH_ACT.maxBurst = HH_ACT.secCount end
    HH_ACT.sec, HH_ACT.secCount = sec, 0
  end
  HH_ACT.secCount = HH_ACT.secCount + 1
  HH_ACT.log[table.getn(HH_ACT.log) + 1] = string.format("%.2f %s", now, tostring(kind))
  while table.getn(HH_ACT.log) > 40 do table.remove(HH_ACT.log, 1) end
end
-- 读值口（探针/日志用）
function EVAL_HH_TEST_ACTS()
  return { last = HH_ACT.last, sec = HH_ACT.sec, secCount = HH_ACT.secCount, gap = HH_ACT_GAP,
           maxBurst = HH_ACT.maxBurst, blocked = HH_ACT.blocked, deferred = HH_ACT.deferred or 0, log = HH_ACT.log }
end
-- ① 施放：进入待选目标态（受保护函数走 RunScript —— 项目既有通道，Engine.lua 指定等级同款）
-- ★找「喂食宠物」在动作条的格号（优先用 UseAction；找不到返回 nil）
--   手段：依次读每格的 tooltip 文本（本项目已验证的读法：GameTooltip:SetAction(slot) → TextLeft1）。
--   ★只在首次需要时扫一次（缓存），避免高频 tooltip 调用。
local HH_SLOT_CACHE = nil
local function hhFindSpellSlot(spellName)
  if HH_SLOT_CACHE ~= nil then return HH_SLOT_CACHE or nil end
  if type(spellName) ~= "string" or spellName == "" then return nil end
  if type(GetActionTexture) ~= "function" or type(GameTooltip) ~= "table" then HH_SLOT_CACHE = false return nil end
  local tip = GameTooltip
  local found = false
  for slot = 1, 120 do
    local ok, tex = pcall(GetActionTexture, slot)
    if ok and tex then
      local okS = pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
      if okS then
        pcall(tip.ClearLines, tip)
        local okA = pcall(tip.SetAction, tip, slot)
        if okA then
          local tl = _G["GameTooltipTextLeft1"]
          if tl and type(tl.GetText) == "function" then
            local okT, t = pcall(tl.GetText, tl)
            if okT and type(t) == "string" and t ~= "" and string.find(t, spellName, 1, true) then found = true end
          end
        end
      end
    end
    if found then
      pcall(tip.Hide, tip)
      HH_SLOT_CACHE = slot
      hhLog("找到喂食技能在动作条第 " .. tostring(slot) .. " 格")
      return slot
    end
  end
  pcall(tip.Hide, tip)
  HH_SLOT_CACHE = false -- 没在条上（缓存否，不反复扫）
  return nil
end

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
  -- ★★★1.74.29 （用户：「某些情况下点喂食会被提下线」）：**优先走动作条**。
  --   理由：RunScript + CastSpellByName 是「绕过受保护函数」的非常规通道，而 UseAction(格号) 是客户端
  --   认可的正规动作 → 被反作弊标记的概率大大降低。找不到格号才退回 RunScript。
  local slot = hhFindSpellSlot(spell)
  if slot then
    -- （门控已改为「调用方先判 hhActReady」：不在这里拒绝，避免吃掉玩家点击）
    local okA = pcall(UseAction, slot)
    if okA then
      HH.lastRun, HH.phase, HH.aimAt = now, "aim", now
      HH.food = foodName
      hhActMark("cast", now) -- ★记账（已实际发出）
      hhLog("动作条施放泡点 " .. tostring(slot) .. "（避开 RunScript 绕行）→ 等待选目标态")
      return true
    end
    hhLog("动作条 UseAction(" .. tostring(slot) .. ") 失败 → 退回 RunScript")
  end
  if type(RunScript) ~= "function" then return hhFail(L("HH_NO_RUNSCRIPT")) end
  local script = "CastSpellByName(" .. HH_QUOTE .. hhEsc(spell) .. HH_QUOTE .. ")"
  local ok = pcall(RunScript, script)
  if not ok then return hhFail(L("HH_CAST_FAIL")) end
  hhActMark("cast", now) -- ★记账
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
  hhActMark("pick", now) -- ★记账
  HH.phase, HH.settleAt = "settle", now
  hhLog("已点食物 @" .. tostring(bag) .. "," .. tostring(slot) .. " → 等结果")
  return true
end

-- ③ 收尾：光标上有东西 = 客户端没把它当目标（不是它的食物）→ **放回原格**并如实报
local function hhRestore(msg)
  if type(ClearCursor) == "function" then
    hhActMark("cursor", hhNow()) -- ★只记账：收尾动作必须执行（否则食物留在光标上）
    pcall(ClearCursor)
  end
  return hhFail(msg)
end

function EVAL_HH_STEP(now)
  now = tonumber(now) or hhNow()
  if HH.phase == "idle" then
    -- ★先判「现在能发动作吗」**再**取队列：否则一旦被拒，这一次点击就被吃掉了（审核发现的设计缺陷）
    if table.getn(HH.q) > 0 and (now - HH.lastRun) >= HH_RATE and hhActReady(now) then
      local req = table.remove(HH.q, 1)
      hhBegin(now, req)
    end
    if HH.phase == "idle" and table.getn(HH.q) == 0 then
      if HH.tick then pcall(HH.tick.SetScript, HH.tick, "OnUpdate", nil) end
    end
    return
  end
  if HH.phase == "aim" then
    if hhIsTargeting() == true and hhActReady(now) then -- ★等 0.2s 间隔（延迟，不拒绝）
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
      hhOk(now)
    elseif (now - HH.settleAt) > HH_SETTLE_WAIT then
      hhFailUnclear()
    end
  end
end

local function hhEnsureTick()
  -- ★★★1.74.29 修（用户报「首次喂食成功后按钮点不动」）：
  --   旧实现「已有 tick 就直接 return」——而 hhRelease() 在队列清空时会
  --   HH.tick:SetScript("OnUpdate", nil) **摘掉心跳** ⇒ 之后点击只入队、状态机永不执行。
  --   正解：每次调用都**保证 OnUpdate 已挂**（幂等重挂，成本可忽略）。
  if HH.tick then
    local has = nil
    if type(HH.tick.GetScript) == "function" then
      local ok, fn = pcall(HH.tick.GetScript, HH.tick, "OnUpdate")
      has = ok and type(fn) == "function"
    end
    if not has and type(HH.tick.SetScript) == "function" then
      pcall(HH.tick.SetScript, HH.tick, "OnUpdate", function() EVAL_HH_STEP(hhNow()) end)
      hhLog("心跳已重新挂上（此前被 hhRelease 摘掉 —— 这正是「点不动」的根因）")
    end
    return HH.tick
  end
  local f = CreateFrame("Frame", nil, UIParent) -- ★不具名：具名帧会占用同名全局（FRAME NAME CLASH 教训）
  f:SetScript("OnUpdate", function() EVAL_HH_STEP(hhNow()) end)
  HH.tick = f
  return f
end

-- 一次点击的入口（= 入队；真正的执行在状态机里，受 HH_RATE 限频）
function EVAL_HH_FEED(req)
  if not hhOn() then return hhFail(L("HH_OFF")) end
  -- ★1.74.11 CD 拦截（用户：「在公共cd 存在_的情况下增加透明遮盖.以体现不可点击.并且要正确的拦截点击触发」）：
  --   CD 还没转好（cdUntil > now）→ **如实拒绝**，不入队（入了也会在 1s 限频里干等）。
  local now0 = hhNow()
  -- ★「无法喂食」原因日志（用户要求）：每一次点击都先记一行「为什么能/不能」，
  --   必要时给出可读原因 —— 不再出现「点了没反应且没有任何线索」。
  local function why(ok2, reason)
    hhLog(string.format("喂食判定：%s · %s（phase=%s 队列=%d CD剩余=%.2fs 心跳=%s）",
      ok2 and "允许" or "拒绝", reason, tostring(HH.phase), table.getn(HH.q),
      math.max(0, (HH.cdUntil or 0) - now0),
      tostring(HH.tick and (function()
        if type(HH.tick.GetScript) ~= "function" then return "?" end
        local okk, fn = pcall(HH.tick.GetScript, HH.tick, "OnUpdate")
        return (okk and type(fn) == "function") and "在" or "已摘"
      end)() or "无")))
  end
  if HH.cdUntil > now0 then
    why(false, string.format("公共CD未转好（还剩 %.2fs）", math.max(0, HH.cdUntil - now0)))
    return hhFail(L("HH_CD_BUSY"))
  end
  if table.getn(HH.q) >= HH_QMAX then
    why(false, "队列已满（" .. tostring(HH_QMAX) .. "）")
    return hhFail(L("HH_BUSY"))
  end
  if HH.phase ~= "idle" and table.getn(HH.q) > 0 then
    why(true, "状态机正忙，本次排到队尾")
  else
    why(true, "入队")
  end
  table.insert(HH.q, req or {})
  hhEnsureTick()
  hhLog("喂食请求入队（队列 " .. tostring(table.getn(HH.q)) .. "）")
  -- ★看门狗（1s）：入队后状态机若一直没动（典型=OnUpdate 没挂上/被摘），如实记一条，
  --   否则这种现象在日志里完全不可见（正是本轮「点不动」当初查不出的原因）。
  local wd = CreateFrame("Frame", nil, UIParent)
  local wacc = 0
  local cfgW = hhCfg() or {}
  local markFood = tostring(HH.food or cfgW.hhFood or "?") -- ★读配置要走 hhCfg()（tb 是别处的局部，直接写会绑全局 nil）
  local qAt = table.getn(HH.q)
  wd:SetScript("OnUpdate", function()
    wacc = wacc + (tonumber(arg1) or 0.05)
    if wacc < 1.0 then return end
    wd:SetScript("OnUpdate", nil)
    if HH.phase == "idle" and table.getn(HH.q) >= qAt then
      hhLog("⚠ 看门狗：入队 1 秒后状态机仍未执行（phase=idle / 队列=" .. tostring(table.getn(HH.q))
        .. " / 食物=" .. markFood .. "）—— 多为 OnUpdate 未挂或被摘、或 EVAL_HH_STEP 未派发")
    end
  end)
  return true
end
-- ★★1.74.29 用户要求：工具箱「喂食助手」行加「重设位置」按钮 → 图标回到**屏幕正中**。
--   口径与项目其它记忆位置一致：位置 = 「中心偏移」（hhX 向右为正、hhY 向上为正），
--   正中 = 偏移 (0,0)；写配置后**立刻**按同一套换算重新落位（hhTopLeft 是唯一来源）。
function EVAL_HH_RESET_POS()
  local cfg = hhCfg()
  if not cfg then return false end
  cfg.hhX, cfg.hhY = 0, 0
  if HH.btn then
    local okc, w2 = pcall(UIParent.GetWidth, UIParent)
    local okh, h2 = pcall(UIParent.GetHeight, UIParent)
    if not (okc and type(w2) == "number" and w2 > 0) then w2 = HH_DEF_W end
    if not (okh and type(h2) == "number" and h2 > 0) then h2 = HH_DEF_H end
    -- ★不用 hhTopLeft（那是本函数**之后**才声明的 local → 会绑全局 nil，见 CLAUDE.md §5.1）；
    --   这里用同一套换算（若 EVAL_IG_TOPLEFT 可用则走共用件）
    local x, y
    if type(EVAL_IG_TOPLEFT) == "function" then
      x, y = EVAL_IG_TOPLEFT(w2, h2, HH_SIZE, 0, 0)
    else
      x, y = w2 / 2 - HH_SIZE / 2, -(h2 / 2 - HH_SIZE / 2)
    end
    pcall(HH.btn.ClearAllPoints, HH.btn)
    pcall(HH.btn.SetPoint, HH.btn, "TOPLEFT", UIParent, "TOPLEFT", x, y)
  end
  hhSay("喂食图标位置已重设为屏幕正中（偏移 0,0）")
  hhLog("重设位置：hhX/hhY = 0,0（按钮=" .. tostring(HH.btn ~= nil) .. "）")
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

-- ===== 宠物信息行（1.74.12 用户要求：tooltip 里有宠物时显示「等级 ｜ 快乐度 ｜ 忠诚 ｜ 经验」）=====
-- ★全部走已验证 API：UnitLevel("pet") / GetPetHappiness()（三返回值：档位 1不开心/2一般/3快乐、伤害%、忠诚速率）/
--   GetPetLoyalty() / GetPetExperience()；拿不到就留「?」，**绝不虚构数值**。
--   ★快乐度是**三档**不是百分比：显示「档位（伤害 N%）」——伤害%来自 API 第二返回值（开心时更高）。
-- ★★★1.74.29 用户明确定：伤害% **按快乐度三档固定文字显示** ——
--   1 不开心 → 75% ｜ 2 一般 → 100% ｜ 3 快乐 → 125%（这是宠物伤害修正的固定三档）。
--   ★不再读 GetPetHappiness() 的第 2 返回值：本客户端实测给出**坏值**（-1258291200 = 0x4B000000 位模式），
--     与其做「形态猜测」不如按三档固定 —— 这也是唯一稳定、可断言的口径。
local HH_HAPPY_DMG = { 75, 100, 125 }

-- 读值口（断言/探针共用同一份表；不改任何状态）
function EVAL_HH_TEST_HAPPYDMG(idx)
  if type(idx) ~= "number" then return nil end
  return HH_HAPPY_DMG[idx]
end

function EVAL_HH_PET_INFO()
  if not hhHasPet() then return nil end
  local lvl = "?"
  if type(UnitLevel) == "function" then local ok, v = pcall(UnitLevel, "pet") if ok and type(v) == "number" then lvl = tostring(v) end end
  local hapIdx = 2
  if type(GetPetHappiness) == "function" then
    local okh, h1 = pcall(GetPetHappiness) -- ★只取第 1 返回值（档位）；第 2 返回值是本客户端的坏值，不用
    if okh and type(h1) == "number" and h1 >= 1 and h1 <= 3 then hapIdx = h1 end
  end
  local hapDmg = HH_HAPPY_DMG[hapIdx] -- 固定三档：75 / 100 / 125
  -- ★★1.74.29 修（用户截图：伤害显示 -1258291200%）：GetPetHappiness 的第 2 返回值在本客户端
  --   并非「百分数」，实测给出的是**原始浮点/位模式**（-1258291200 = 0x4B000000 这种天文数字）。
  --   ⇒ 加**合理性闸门**：NaN / inf / 负数 / >300 一律作废（显示「?」，绝不把垃圾值画给用户）；
  --     合法的两种形态都认：分数（0.75/1.0/1.25 → ×100）与百分数（75/100/125）。
  local hapTxt = L("HH_PET_HAPPY2")
  if hapIdx == 1 then hapTxt = L("HH_PET_HAPPY1") elseif hapIdx == 3 then hapTxt = L("HH_PET_HAPPY3") end
  local r, g, b = 1, 0.82, 0.3 -- 一般=金
  if hapIdx == 1 then r, g, b = 1, 0.5, 0.4 elseif hapIdx == 3 then r, g, b = 0.5, 1, 0.5 end -- 不开心=红 / 快乐=绿
  -- ★★1.74.29 修（用户截图：(Loyalty Level 1) Rebellious 原样堆了进去）：本客户端返回的是
  --   **未本地化英文串**（含档位数字）→ 解析出数字后用**本地化档名**显示；解析不出数字就退化显示
  --   去括号后的首段文本（仍如实，但不堆整串英文）。
  local LOYAL_NAME = { L("HH_PET_LOYAL1"), L("HH_PET_LOYAL2"), L("HH_PET_LOYAL3"),
                       L("HH_PET_LOYAL4"), L("HH_PET_LOYAL5"), L("HH_PET_LOYAL6") }
  local loyal = "?"
  if type(GetPetLoyalty) == "function" then
    local okl, v = pcall(GetPetLoyalty)
    if okl and type(v) == "string" and v ~= "" then
      local n = tonumber(string.match(v, "(%d+)"))
      if n and n >= 1 and n <= 6 then
        loyal = tostring(n) .. " " .. tostring(LOYAL_NAME[n])
      else
        local plain = string.gsub(v, "%b()", "")            -- 去掉 "(Loyalty Level N)" 这类括号段
        plain = string.gsub(plain, "^%s+", "")
        plain = string.gsub(plain, "%s+$", "")
        if plain == "" then plain = v end
        loyal = plain
      end
    end
  end
  local xpTxt = "?/?"
  if type(GetPetExperience) == "function" then
    local okx, x1, x2 = pcall(GetPetExperience)
    if okx and type(x1) == "number" and type(x2) == "number" then xpTxt = tostring(x1) .. "/" .. tostring(x2) end
  end
  -- ★有合法伤害% → 用带伤害的整句；没有 → 用不带伤害的整句（不再出现「伤害 ?%」这种半截话）
  if hapDmg then
    return string.format(L("HH_TT_PETINFO"), lvl, hapTxt, tostring(hapDmg), loyal, xpTxt), r, g, b
  end
  return string.format(L("HH_TT_PETINFO_NODMG"), lvl, hapTxt, loyal, xpTxt), r, g, b
end

-- ★★★提示行的**唯一来源**（读值口 + 渲染源）：只在这里拼一次 ——
--   ① 悬浮提示照它渲染；② 断言直接读它（不必跟桩里的 GameTooltip 记账，也不会两处各拼一份而漂移）。
-- ★用户要求（工具→宠物助手）：没选喂养技能时，把那一行换成**明确提示语**（HH_TT_SPELL_NONE）并用警示色
--   —— 与「食物：未设置」同一形态，不再显示含糊的「未识别」。
function EVAL_HH_TIP_LINES()
  local out = {}
  local function put(t, r, g, b) table.insert(out, { t = t, r = r, g = g, b = b }) end
  local tb = hhCfg() or {}
  put(L("HH_TT_TITLE"), 1, 0.82, 0.3)
  local food = tb.hhFood
  local bag, slot, _, cnt = nil, nil, nil, nil
  if type(food) == "string" and food ~= "" then bag, slot, _, cnt = EVAL_HH_FIND_FOOD(food) end
  if bag then
    put(string.format(L("HH_TT_FOOD"), food, tostring(bag), tostring(slot), tostring(cnt or 1)), 0.9, 0.9, 0.9)
  else
    put(L("HH_TT_NOFOOD"), 1, 0.5, 0.4)
  end
  -- ★没选喂养技能 = 明确提示（警示色）；选了 = 技能名（常规色）
  local sp = EVAL_HH_SPELL()
  if sp then
    put(string.format(L("HH_TT_SPELL"), tostring(sp)), 0.9, 0.9, 0.9)
  else
    put(string.format(L("HH_TT_SPELL"), L("HH_TT_SPELL_NONE")), 1, 0.5, 0.4)
  end
  -- ★1.74.12 有宠物 → 显示宠物信息行（等级/快乐度/忠诚/经验）；没宠物 → 显示「现在没有宠物」
  local piTxt, piR, piG, piB = EVAL_HH_PET_INFO()
  if piTxt then put(piTxt, piR, piG, piB) else put(L("HH_TT_NOPET"), 1, 0.5, 0.4) end
  put(L("HH_TT_LEFT"), 0.6, 1, 0.6)
  put(L("HH_TT_RIGHT"), 0.6, 0.8, 1)
  put(L("HH_TT_DRAG"), 0.7, 0.7, 0.7)
  put(string.format(L("HH_TT_CNT"), tostring(HH.hits or 0)), 0.7, 0.7, 0.7)
  return out
end

local function hhTip(b)
  if type(GameTooltip) ~= "table" then return end
  pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
  pcall(GameTooltip.ClearLines, GameTooltip)
  local lines = EVAL_HH_TIP_LINES()
  for i = 1, table.getn(lines) do
    local ln = lines[i]
    pcall(GameTooltip.AddLine, GameTooltip, ln.t, ln.r, ln.g, ln.b)
  end
  pcall(GameTooltip.Show, GameTooltip)
end

-- ===== CD 倒计时（1.74.11 用户要求：悬浮图标显示 CD 实时倒计时特效） =====
-- ★共用格式化 EVAL_IG_CD_TEXT（IconGrid.lua；两个助手同一份）。字体 9pt 小字，贴主图标中心下方。
function EVAL_HH_CD_REFRESH()
  if not (HH.built and HH.btn) then return false end
  -- ★1.74.11 遮盖（用户：「在公共cd 存在_的情况下增加透明遮盖.以体现不可点击」）
  local left = HH.cdUntil - hhNow()
  local onCd = (left > 0)
  if not HH.cdMask then
    local m = HH.btn:CreateTexture(nil, "OVERLAY")
    hhSolid(m, 0, 0, 0, 0.55) -- 半透明黑
    m:SetPoint("TOPLEFT", HH.btn, "TOPLEFT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", HH.btn, "BOTTOMRIGHT", 0, 0)
    pcall(m.Hide, m)
    HH.cdMask = m
  end
  if onCd then pcall(HH.cdMask.Show, HH.cdMask) else pcall(HH.cdMask.Hide, HH.cdMask) end
  if not HH.cdText then
    local fs = hhText(HH.btn, 9, 1, 0.85, 0.3) -- 金色，9pt 小字
    fs:SetPoint("CENTER", HH.btn, "CENTER", 0, -1)
    pcall(fs.SetWidth, fs, HH_SIZE)
    pcall(fs.SetJustifyH, fs, "CENTER")
    HH.cdText = fs
  end
  local txt = (type(EVAL_IG_CD_TEXT) == "function") and EVAL_IG_CD_TEXT(left) or nil
  if txt then
    HH.cdText:SetText(txt)
    pcall(HH.cdText.Show, HH.cdText)
    if not HH.cdTick then
      local f = CreateFrame("Frame", nil, UIParent)
      f:SetScript("OnUpdate", function() EVAL_HH_CD_REFRESH() end)
      HH.cdTick = f
    end
  else
    HH.cdText:SetText("")
    pcall(HH.cdText.Hide, HH.cdText)
    if HH.cdTick then pcall(HH.cdTick.SetScript, HH.cdTick, "OnUpdate", nil) HH.cdTick = nil end -- CD 结束 → 摘掉 OnUpdate
  end
  return true
end

-- 图标贴图：食物图标（实时解析）；解析不到 → 保底文字（不写纹理字面量 → 不碰 ICON 白名单）
-- ★★★1.74.29 （用户要求）：
--   ① 按宠物**快乐度**给按钮换高亮边框：1 不开心=红 / 2 一般=金 / 3 快乐=绿；
--   ② 顶部蓝色进度条 = 宠物**经验百分比**（GetPetExperience 的 当前/上限）。
--   拿不到宠物/拿不到经验（或已满）→ 进度条隐藏；边框回到默认金色。**绝不编数据**。
function EVAL_HH_PETDECOR()
  if not (HH.built and HH.btn) then return false end
  -- 边框：按快乐度档位取色
  -- ★★1.75.1 补门（合并两支时抓到）：**没有宠物 ⇒ 一律默认金**，一个快乐度读数都不读。
  --   理由 = 本函数上方那条承诺（「拿不到宠物/拿不到快乐度 ⇒ 边框回到默认金色，**绝不编数据**」）：
  --   `GetPetHappiness()` **没有「无宠物」这个返回值语义**（桩里它就照读 `TEST.happiness`；真机上取值也不该被当成
  --   「这只有宠物的快乐度」）⇒ 少了这道门，宠物刚消失时会**沿用上一档颜色**（宠物没了却还亮着红/绿边）。
  --   判据 = 组 188 ④ 的**反向哨兵**「没有宠物 → 退回默认金边（不硬编『开心』）」（head 线原有，合并后当场抓到）。
  local idx = nil
  if hhHasPet() and type(GetPetHappiness) == "function" then
    local ok, v = pcall(GetPetHappiness)
    if ok and tonumber(v) then idx = tonumber(v) end
  end
  local r, g, b = 0.85, 0.70, 0.20 -- 默认金（无宠物/拿不到快乐度）
  if idx == 1 then r, g, b = 1.00, 0.35, 0.30
  elseif idx == 2 then r, g, b = 0.95, 0.80, 0.25
  elseif idx == 3 then r, g, b = 0.45, 1.00, 0.45 end
  if type(HH.edges) == "table" then
    for i = 1, 4 do
      local e = HH.edges[i]
      if e then pcall(e.SetVertexColor, e, r, g, b, 0.95) end
    end
  end
  -- 经验条：宽度 = （按钮内宽）× 百分比
  -- ★同上：**没有宠物 ⇒ 不读经验、进度条隐藏**（同一道门、同一份承诺，避免两处条件写法漂移）
  local cur, max = nil, nil
  if hhHasPet() and type(GetPetExperience) == "function" then
    local ok, c, m = pcall(GetPetExperience)
    if ok and tonumber(c) and tonumber(m) then cur, max = tonumber(c), tonumber(m) end
  end
  if HH.xpFill and HH.xpBg then
    if cur and max and max > 0 then
      local pct = cur / max
      if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
      local inner = HH_SIZE - 2
      pcall(HH.xpBg.Show, HH.xpBg)
      pcall(HH.xpFill.Show, HH.xpFill)
      pcall(HH.xpFill.SetWidth, HH.xpFill, inner * pct)
    else
      pcall(HH.xpFill.Hide, HH.xpFill)
      pcall(HH.xpBg.Hide, HH.xpBg)
    end
  end
  return true
end

-- ★低频心跳（2s）：快乐度会随喂食变化、经验会随战斗增长 → 定期刷新（只在按钮存在时）
do
  if type(CreateFrame) == "function" then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    local tf = CreateFrame("Frame", "EH_HH_DECOR", parent)
    local acc = 0
    tf:SetScript("OnUpdate", function()
      acc = acc + (tonumber(arg1) or 0.05)
      if acc < 2.0 then return end
      acc = 0
      if HH.built and HH.btn then pcall(EVAL_HH_PETDECOR) end
    end)
  end
end

function EVAL_HH_REFRESH()
  if not (HH.built and HH.btn) then return false end
  if type(EVAL_HH_PETDECOR) == "function" then pcall(EVAL_HH_PETDECOR) end -- ★快乐度边框 + 经验条一并刷
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
  -- ★★1.74.29 用户要求：边框颜色随**宠物快乐度**变化 → 四条收进 HH.edges，由 EVAL_HH_PETDECOR 统一改色
  HH.edges = {}
  for i = 1, 4 do
    local e = b:CreateTexture(nil, "BORDER")
    HH.edges[i] = e
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
  -- ★★1.74.29 用户要求：按钮**顶部一条小小的蓝色进度条**（宠物经验百分比）
  local xpBg = b:CreateTexture(nil, "OVERLAY")
  hhSolid(xpBg, 0, 0, 0, 0.75)
  xpBg:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  xpBg:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
  xpBg:SetHeight(3)
  local xpFill = b:CreateTexture(nil, "OVERLAY")
  hhSolid(xpFill, 0.25, 0.55, 1.0, 1) -- 蓝色
  xpFill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  xpFill:SetHeight(3)
  xpFill:SetWidth(0)
  HH.xpBg, HH.xpFill = xpBg, xpFill
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
-- ★用户要求（1.74.29）：下拉里加入**食品类别**（肉类/鱼类/面包/水果/蘑菇/奶酪/蛋/其他）。
--   本客户端**没有**「某物品属于哪类食物」的 API（只有 GetPetFoodTypes 给宠物食谱名），
--   所以类别只能按**物品名关键词**判定（与 hhIsLikelyFood 同一份词表，单一来源）。
local HH_CATS = {
  { k = "肉类", words = { "肉", "肋排", "肠", "禽", "腿", "熊", "野猪", "狼" } },
  { k = "鱼类", words = { "鱼", "鲈", "鲑", "鳕", "鳗", "鳟" } },
  { k = "面包", words = { "面包", "饼干", "薄饼", "麦", "面", "糕" } },
  { k = "水果", words = { "水果", "苹果", "香蕉", "芒果", "瓜", "莓", "桃" } },
  { k = "蘑菇", words = { "蘑菇", "菌" } },
  { k = "奶酪", words = { "奶酪", "干酪", "奶" } },
  { k = "蛋", words = { "蛋" } },
}
local function hhFoodCat(name)
  local low = string.lower(tostring(name or ""))
  for _, cat in ipairs(HH_CATS) do
    for _, w in ipairs(cat.words) do
      if string.find(low, string.lower(w), 1, true) then return cat.k end
    end
  end
  return "其他"
end
local function hhCatOrder(k)
  for i, cat in ipairs(HH_CATS) do if cat.k == k then return i end end
  return table.getn(HH_CATS) + 1
end
-- 公开读值口（测试/探针用）
function EVAL_HH_FOOD_CAT(name) return hhFoodCat(name) end

function EVAL_HH_MENU_MODEL()
  local items, acts = {}, {}
  local function add(text, act) table.insert(items, text) table.insert(acts, act) end
  add(L("HH_DD_SETSPELL"), { k = "spell" })
  local cand, total = EVAL_HH_CANDIDATES()
  local n = table.getn(cand)
  -- ★给每个候选打上类别（按名字关键词判定；这是本客户端唯一可行的判据）
  local byCat, catSeen = {}, {}
  for i = 1, n do
    local c = cand[i]
    c.cat = hhFoodCat(c.name)
    byCat[c.cat] = byCat[c.cat] or {}
    table.insert(byCat[c.cat], c)
    catSeen[c.cat] = true
  end
  -- ★类别快捷条目：点它 = 选该类**第一件**（列表已按食物相似度排序 → 通常是包里的主粮）
  local cats = {}
  for ck in pairs(catSeen) do table.insert(cats, ck) end
  table.sort(cats, function(a, b) return hhCatOrder(a) < hhCatOrder(b) end)
  for _, ck in ipairs(cats) do
    local first = byCat[ck][1]
    if first then
      add(string.format("★类别·%s（选：%s）", ck, tostring(first.name)),
          { k = "food", name = first.name, tex = first.tex })
    end
  end
  -- 明细：按类别分组排序，条目带 [类别] 前缀
  local sorted = {}
  for _, ck in ipairs(cats) do
    for _, c in ipairs(byCat[ck]) do table.insert(sorted, c) end
  end
  for i = 1, table.getn(sorted) do
    local c = sorted[i]
    add(string.format("[%s] ", tostring(c.cat))
        .. string.format(L("HH_DD_ITEM"), tostring(c.name), tostring(c.count or 1), tostring(c.bag), tostring(c.slot)),
        { k = "food", name = c.name, tex = c.tex, cat = c.cat })
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
  -- ★★1.74.29：防踢线闸门的状态也要清（否则前一组测试的时间线会把后一组卡住）
  HH_ACT.last, HH_ACT.lastFrame, HH_ACT.lastKind, HH_ACT.lastSay = -999, -1, nil, -999
  HH_ACT.sec, HH_ACT.secCount, HH_ACT.blocked, HH_ACT.log = 0, 0, 0, {}
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
  -- ★1.74.28 「验证可行性」入口：/eh go 喂食探针 过滤 —— 背包每件物品的类型判定依据一屏摊开
  if sub == "过滤" then
    if type(EVAL_IG_FILTER_REPORT) == "function" then return EVAL_IG_FILTER_REPORT(HH_BAGS, hhSay) end
    return false
  end
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
    if feedArg == "频率" or feedArg == "freq" then
      local a = EVAL_HH_TEST_ACTS()
      hhSay("--- 喂食服务器动作审计 ---")
      hhSay(string.format("最大 1 秒窗口动作数=%d · 被闸门拦下=%d 次 · 当前秒已发=%d",
        a.maxBurst or 0, a.blocked or 0, a.secCount or 0))
      hhSay("最近动作（时间 类型）：" .. table.concat(a.log or {}, " · "))
      hhSay("判读：正常喂食应是「每 2 秒 1 次 cast + 1 次 pick」；若最大窗口动作数接近 4 或被拦很多，说明原来确实在短时间内连发。")
      return true
    end
    return false
  end
  hhSay("用法：/eh go 喂食（一键喂食）｜ 喂食 设 <食物名> ｜ 喂食 技能 <名> ｜ 喂食探针 [扫书|施放 <名>|喂 <包> <格>|拖|收光标]")
  return false
end

-- ★★1.74.29 取证分支（用户截图「伤害 -1258291200%」）：
--   把宠物相关 API 的**原始返回值**按顺序摊开 —— 类型 + 值，绝不加工。
--   判读：若第 2 返回值是 0.75/1.0/1.25 → 分数形态（我们乘 100 显示）；
--         若是 75/100/125 → 百分数；若是天文数字/负数 → 本客户端就是坏值，我们如实不显示。
local function hhProbePet()
  hhSay("— 猎人助手 · 宠物信息探针（原始返回值）—")
  local function dump(label, fn, ...)
    if type(fn) ~= "function" then hhSay(label .. "：本客户端没有这个 API") return end
    local args = { ... }
    local r = { pcall(fn, unpack(args)) }
    if not r[1] then hhSay(label .. "：调用失败（" .. tostring(r[2]) .. "）") return end
    local parts = {}
    for i = 2, table.getn(r) do
      local v = r[i]
      parts[i - 1] = "#" .. tostring(i - 1) .. "=" .. tostring(v) .. "(" .. type(v) .. ")"
    end
    if table.getn(parts) == 0 then parts[1] = "（无返回值）" end
    hhSay(label .. "：" .. table.concat(parts, " · "))
  end
  dump("UnitLevel('pet')", UnitLevel, "pet")
  dump("GetPetHappiness()", GetPetHappiness)
  dump("GetPetLoyalty()", GetPetLoyalty)
  dump("GetPetExperience()", GetPetExperience)
  local pi = EVAL_HH_PET_INFO()
  hhSay("当前 tooltip 实际显示：" .. tostring(pi or "（无宠物 → 显示「现在没有宠物」）"))
  hhSay("★把上面几行发我即可定案伤害%的形态（分数/百分数/坏值）")
  return true
end

function EVAL_HH_PROBE(sub)
  if sub == "宠物" or sub == "pet" then return hhProbePet() end
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
      -- ★被剔名单（取证）：有名字像食物却被剔的，直接点名 —— 免得再出现「真食物看不见」而无从下手
      local drops = (type(EVAL_IG_KIND_DROPS) == "function") and EVAL_IG_KIND_DROPS() or nil
      if type(drops) == "table" and table.getn(drops) > 0 then
        local line = {}
        for i = 1, table.getn(drops) do
          local d = drops[i]
          if hhIsLikelyFood(d.name) then
            table.insert(line, tostring(d.name) .. "(" .. tostring(d.kind) .. ")")
          end
        end
        if table.getn(line) > 0 then
          hhSay("⚠ 被类型过滤剔掉、但名字像食物的：" .. table.concat(line, "、") .. "（已修：keepNames 例外会保它们）")
        end
      end
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
-- ★★合并自 master 线（1.74.29）：快乐度边框的读值口 —— 本模块实现改由 EVAL_HH_PETDECOR 上色，
--   本口只**读**四条边的真实顶点色（测试用；不改变任何行为）。
function EVAL_TEST_HH_HAP()
  local out = { n = 0, rgb = nil, tier = nil, pet = (hhHasPet() and true or false) }
  if not (HH.edges and HH.edges[1]) then return out end
  out.n = table.getn(HH.edges)
  local ok, r, g, b = pcall(HH.edges[1].GetVertexColor, HH.edges[1])
  if ok and type(r) == "number" then out.rgb = { r, g, b } end
  if out.pet and type(GetPetHappiness) == "function" then
    local okh, idx = pcall(GetPetHappiness)
    if okh and type(idx) == "number" then out.tier = idx end
  end
  return out
end
function EVAL_TEST_HH_STATE()
  local tb = hhCfg() or {}
  local shown = nil
  if HH.btn and type(HH.btn.IsShown) == "function" then shown = HH.btn:IsShown() end
  return { built = HH.built, shown = shown, on = tb.feedPet and true or false,
           leftClicks = HH.leftClicks, rightClicks = HH.rightClicks, lastBtn = HH.lastBtn,
           lastArgs = HH.lastArgs, regClicks = HH.regClicks,
           food = tb.hhFood, foodTex = tb.hhFoodTex, spell = tb.hhSpell,
           phase = HH.phase, qn = table.getn(HH.q), hasTick = HH.tick and true or false, hits = HH.hits,
           rate = HH_RATE, qmax = HH_QMAX, lastRun = HH.lastRun,
           -- ★1.74.11 CD 倒计时读值口
           cdTotal = HH.cdTotal, cdUntil = HH.cdUntil,
           cdMaskShown = (HH.cdMask and HH.cdMask.IsShown and HH.cdMask:IsShown() == true) or false }
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
