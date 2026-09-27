-- ============================================================================
-- quest/QuestChains.lua —— 任务线**检索逻辑层**（纯函数 · 无 UI · 无副作用）
--
-- 分工（解耦约定，用户要求「只在数据检索才用到检索功能」）：
--   · QuestData.lua  = 纯数据（生成物，来自 quest/build.js）
--   · 本文件          = 纯逻辑（搜索 / 筛选 / 详情模型），可被 node 直测
--   · DataSearch.lua = **唯一调用方**（「数据检索」Tab 里的任务线检索源）
--   本文件不建帧、不注册事件、不碰配置、不依赖 UnrealQuest —— 载入期零副作用。
--
-- 数据访问一律**惰性**（rawget 每次现取）：QuestData 的载入顺序、以及未来换数据源都不影响这里。
-- 「查不到 ≠ 没有」：数据缺失一律如实返回 nil，并留着 EVAL_QC_READY 让调用方区分
--   「没数据」与「没命中」。
--
-- ★身份约定（界面只用 kind+id 定位详情）：链的 id = 它在 EVAL_QC_LIST() 里的**位次（数字）**。
--   搜索与详情都走同一个 EVAL_QC_LIST()，因此界面把搜索结果的 id 原样交给详情即可，
--   不必额外传字符串键（也避免了「数字 id 与字符串 id 混排比较」的运行时报错）。
-- ============================================================================

-- 档位权重：唯一来源（列表排序与详情标题共用）
local QC_TIER_W = { S = 1, A = 2, B = 3 }

local function qcItems() return rawget(_G, "EVAL_QC_ITEMS") end
local function qcQuests() return rawget(_G, "EVAL_QC_QUESTS") end
local function qcChainList() return rawget(_G, "EVAL_QC_CHAINS") end
local function qcMeta() return rawget(_G, "EVAL_QC_META") end

-- 数据是否可用（诚实失败的前提：区分「没数据」与「没命中」）
function EVAL_QC_READY()
  local c = qcChainList()
  if type(c) ~= "table" then return nil end
  if not c[1] then return nil end
  return true
end

function EVAL_QC_COUNT()
  local c = qcChainList()
  return (type(c) == "table") and table.getn(c) or 0
end

function EVAL_QC_SOURCE()
  local m = qcMeta()
  if type(m) ~= "table" then return nil end
  return m.src, m.built
end

function EVAL_QC_QUEST_NAME(id)
  local q = qcQuests()
  local r = (type(q) == "table") and q[id] or nil
  return r and r.n or nil
end

function EVAL_QC_ITEM_NAME(id)
  local it = qcItems()
  local r = (type(it) == "table") and it[id] or nil
  if r and r.n then return r.n end
  -- ★1.75.9：策展表里没有 → 退回**全量**物品表（30-60 的装备都在那边）
  local b = (type(EVAL_QC_BULK_ITEM) == "function") and EVAL_QC_BULK_ITEM(id) or nil
  return b and b.n or nil
end

function EVAL_QC_ITEM(id)
  local it = qcItems()
  local r = (type(it) == "table") and it[id] or nil
  if r then return r end
  local b = (type(EVAL_QC_BULK_ITEM) == "function") and EVAL_QC_BULK_ITEM(id) or nil
  return b
end

-- 任务等级（1.75.12 用户要求：装备→任务线的信息里要展示**任务对应的等级**）
-- 两份数据源依次找：策展任务表 → 全量任务表；查不到如实返回 nil
function EVAL_QC_QUEST_LEVEL(id)
  local q = qcQuests()
  local r = (type(q) == "table") and q[id] or nil
  if r and tonumber(r.lv) then return tonumber(r.lv) end
  local bq = (type(EVAL_QC_BULK_QUEST) == "function") and EVAL_QC_BULK_QUEST(id) or nil
  if bq and tonumber(bq.lv) then return tonumber(bq.lv) end
  return nil
end

-- ===== 稀有度（1.75.10 用户要求：「任务线也按等级排序，并按稀有程度用魔兽特有的染色机制；
--        橙色给史诗风剑之类的任务」）=====
-- 唯一来源：token → 魔兽**品质色**（与物品品质同一套 RGB，别在界面里再写一份）
--   传说 ff8000 · 史诗 a335ee · 稀有 0070dd · 优秀 1eff00 · 普通 ffffff · 粗糙 9d9d9d
local QC_RAR = {
  LEG = { 1.00, 0.50, 0.00 },
  EPIC = { 0.64, 0.21, 0.93 },
  RARE = { 0.00, 0.44, 0.87 },
  UNCOMMON = { 0.12, 1.00, 0.00 },
  COMMON = { 1.00, 1.00, 1.00 },
  POOR = { 0.62, 0.62, 0.62 },
}
-- 排序权重（越小越靠前：同级时传说在前）
local QC_RAR_W = { LEG = 1, EPIC = 2, RARE = 3, UNCOMMON = 4, COMMON = 5, POOR = 6 }
-- ★传说（橙）：**传说级物品/世界事件**相关的线 —— 用户点名「史诗风剑之类」
local QC_LEG_KEYS = { "雷霆之怒", "逐风者", "风剑", "埃提耶什", "萨弗拉斯", "灰烬使者", "流沙", "甲虫之墙", "安其拉" }
-- ★史诗（紫）：团本开门/钥匙链 + 大型史诗线 + 职业史诗
local QC_EPIC_KEYS = { "纳克萨玛斯", "克尔苏加德", "奥妮克希亚", "熔火之心", "黑翼", "之门", "开门", "钥匙",
  "梦魇", "达隆郡", "林克", "爱与家庭", "奎尔塞拉", "节杖", "议会", "史诗", "传说" }

-- 注意：Lua 模式里 `|` **不是交替**（项目铁律）⇒ 一律用 plain 逐词查找，绝不用模式。
local function qcHasAny(hay, keys)
  if type(hay) ~= "string" or hay == "" then return false end
  for i = 1, table.getn(keys) do
    if string.find(hay, keys[i], 1, true) then return true end
  end
  return false
end

-- 链名 + 各步骤任务名拼成的「判据串」（步骤名是主要依据：风剑/奎尔塞拉的线索就在步骤名里）
local function qcRarityHay(rec)
  if type(rec) ~= "table" then return "" end
  local parts = { tostring(rec.n or "") }
  local qs = rec.qs or {}
  for i = 1, table.getn(qs) do
    local nm = EVAL_QC_QUEST_NAME(qs[i])
    if not nm then
      local bq = (type(EVAL_QC_BULK_QUEST) == "function") and EVAL_QC_BULK_QUEST(qs[i]) or nil
      nm = bq and bq.n or nil
    end
    if nm then parts[table.getn(parts) + 1] = tostring(nm) end
  end
  return table.concat(parts, " ")
end

-- 稀有度：返回 token + RGB 三通道（界面只用这一个入口，颜色绝不在界面里写死）
function EVAL_QC_RARITY(rec)
  local n = (type(rec) == "table") and table.getn(rec.qs or {}) or 0
  local hay = qcRarityHay(rec)
  local t
  if qcHasAny(hay, QC_LEG_KEYS) then
    t = "LEG"                                              -- 传说（橙）：风剑 / 橙杖 / 安其拉开门…
  elseif (type(rec) == "table" and rec.open) or qcHasAny(hay, QC_EPIC_KEYS) or n >= 10 then
    t = "EPIC"                                             -- 史诗（紫）：团本开门/钥匙 + 大型线
  elseif (type(rec) == "table" and rec.t == "S") or n >= 6 then
    t = "RARE"                                             -- 稀有（蓝）：职业史诗 / 6 步以上
  elseif (type(rec) == "table" and rec.t == "A") or n >= 4 then
    t = "UNCOMMON"                                         -- 优秀（绿）：4-5 步
  elseif n >= 1 then
    t = "COMMON"                                           -- 普通（白）：2-3 步 / 独立任务
  else
    t = "POOR"                                             -- 粗糙（灰）：查不到步骤（数据缺失）
  end
  local c = QC_RAR[t] or QC_RAR.COMMON
  return t, c[1], c[2], c[3]
end

-- ★1.75.14 **单条任务的染色**（用户定稿口径，已替换掉先前的「名字关键词 + 站点标签」判法）：
--   ① **没有任何任务奖励 ⇒ 一律「普通」（白）**；
--   ② **有奖励 ⇒ 按「最好那件奖励的品质色」**（与物品品质色**完全同源**，同一张 `QC_RAR`）：
--      q0 粗糙(灰) · q1 普通(白) · q2 优秀(绿) · q3 稀有(蓝) · q4 史诗(紫) · q5 传说(橙)。
--   ★为什么不按 eq 过滤奖励：站点**类型/部位字段会缺**（`预言藤杖`/`悲哀衬肩`/`洛瑞卡宝珠` 都被判成
--     非装备）⇒ 按 eq 筛会把真装备藏掉；奖励清单本身就是「这件任务给什么」，直接取最高品质即可。
--   ★不再判名字关键词与 `d/e/r` 标签（那是**任务线**的口径）；任务行要的是「装备等级的颜色」。
function EVAL_QC_QUEST_RARITY(rec)
  local TOK = { "POOR", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEG" }   -- 下标 = 品质 q + 1
  local best = nil
  if type(rec) == "table" then
    local bq = (type(EVAL_QC_BULK_QUEST) == "function") and EVAL_QC_BULK_QUEST(rec.id) or nil
    local rw = (bq and bq.rw) or {}
    for i = 1, table.getn(rw) do
      local it = (type(EVAL_QC_BULK_ITEM) == "function") and EVAL_QC_BULK_ITEM(rw[i]) or nil
      local q = (it and tonumber(it.q)) or nil
      if q and (best == nil or q > best) then best = q end
    end
  end
  local t
  if best == nil then
    t = "COMMON"                                  -- ① 没有任务奖励 ⇒ 一律普通
  else
    local idx = math.floor(best) + 1              -- ② 有奖励 ⇒ 最高品质对应的颜色
    if idx < 1 then idx = 1 end
    if idx > 6 then idx = 6 end
    t = TOK[idx] or "COMMON"
  end
  local c = QC_RAR[t] or QC_RAR.COMMON
  return t, c[1], c[2], c[3]
end

-- 读值口：颜色表 / token 清单（测试与界面共用，避免复刻）
function EVAL_QC_RARITY_RGB(token)
  local c = QC_RAR[token]
  if not c then return nil end
  return c[1], c[2], c[3]
end

function EVAL_QC_RARITY_KEYS()
  return { "LEG", "EPIC", "RARE", "UNCOMMON", "COMMON", "POOR" }
end

-- ===== 列表：按「**等级 → 稀有度 → 原序**」排序（1.75.10 用户要求：任务线也按等级排序）=====
-- filter = { faction = "A"/"H"/"B"/nil, tier = "S"/"A"/"B"/nil }
-- 排序用「装饰（等级, 稀有度权重, 原序号）」—— table.sort 在 Lua 5.1 不稳定（项目铁律）
function EVAL_QC_LIST(filter)
  local list = qcChainList()
  if type(list) ~= "table" then return {} end
  local f = filter or {}
  local out = {}
  for i = 1, table.getn(list) do
    local c = list[i]
    local ok = true
    -- ★阵营是**严格三分类**（用户要求：联盟 / 部落 / 共有）——选联盟就只出联盟，不再把「共有」并进来。
    if f.faction and f.faction ~= "ALL" and c.f ~= f.faction then ok = false end
    if f.tier and f.tier ~= "ALL" and c.t ~= f.tier then ok = false end
    if ok then
      local rar = EVAL_QC_RARITY(c)
      table.insert(out, { c = c, r = QC_RAR_W[rar] or 9, lo = tonumber(c.lo) or 99, i = i })
    end
  end
  table.sort(out, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.r ~= b.r then return a.r < b.r end
    return a.i < b.i
  end)
  local res = {}
  for i = 1, table.getn(out) do res[i] = out[i].c end
  return res
end

-- ===== 装备种类（1.75.8 细分 / 1.75.17 按部位细分 / 1.75.18 任务线也能按种类筛）=====
-- 种类唯一来源 = 生成数据里物品的 `k`（类型：剑/斧/锤/匕首/法杖/弓/盾牌/布甲/皮甲/锁甲/其它），
-- 部位在 `s`；「是不是武器子类型」由 EVAL_QC_IS_WEAPON 判（dps>0），不另立表。
-- ★★1.75.17 用户要求「其它 能否细分为 戒指/项链/饰品」：站点把这三类的**类型**全写成「其它」
--   （其它 251 件里 手指 102 / 颈部 77 / 饰品 72），**只有部位**分得开 ⇒ 类型为「其它」/空时按部位补。
--   ★映射只列站点确实给得出的部位名（数据里没有的绝不凭空造种类）；种类清单仍**由数据现算**。
-- ★★1.75.18 这几个件**必须声明在 EVAL_QC_SEARCH 之前**：任务线的种类筛选要用它们
--   （local 用在使用之后 = 真机读到全局 nil —— 顺序事故项目里已踩过两次，LOCAL ORDER CHECK 守着）。
local QC_SLOT_KIND = { ["手指"] = "戒指", ["颈部"] = "项链", ["饰品"] = "饰品" }
function EVAL_QC_ITEM_KIND(rec)
  if type(rec) ~= "table" then return "" end
  local k = (type(rec.k) == "string") and rec.k or ""
  if k == "" or k == "其它" then
    local s = QC_SLOT_KIND[rec.s or ""]
    if s then return s end
  end
  return k
end

-- 多选集合判定（单一来源）：非表 / 空集 = 不过滤（「一个都没勾」与「全部」同义，符合用户多选预期）
function EVAL_QC_KIND_PASS(set, k)
  if type(set) ~= "table" then return true end
  local any = false
  for _ in pairs(set) do any = true break end
  if not any then return true end
  return set[k] and true or false
end

-- ★1.75.14 用户要求「装备/任务线列表检索增加地域过滤 · 支持多选 · 默认全选」：
--   判定与种类**同一套语义**（非表 / 空集 = 不过滤）——界面与两个列表共用这一个入口。
--   ★空串（""）是一等公民：站点有极少数任务没写地区 ⇒ 用 "" 当键、界面给一行「（无地区）」，
--     这样「筛了地区却混进无地区行」不会发生（用户想排除它，取消勾选那一行即可）。
function EVAL_QC_ZONE_PASS(set, z)
  if type(set) ~= "table" then return true end
  local any = false
  for _ in pairs(set) do any = true break end
  if not any then return true end
  return set[tostring(z or "")] and true or false
end

-- 物品 id → 记录（全量优先、策展兜底 —— 两个来源都可能只有其一）
local function qcItemRec(id)
  local it = EVAL_QC_BULK_ITEM(id)
  if type(it) == "table" then return it end
  return EVAL_QC_ITEM(id)
end

-- 记录（策展链 / 自报系列）的奖励里**有没有**勾选的种类（空集 = 不过滤）
-- ★拿不到奖励清单就**如实不通过**（不假装命中）—— 例外是空集（= 不过滤，直接放行）
local function qcRecKindsOK(c, kset)
  if type(kset) ~= "table" then return true end
  local any = false
  for _ in pairs(kset) do any = true break end
  if not any then return true end
  local rw = (type(c) == "table") and c.rw or nil
  if type(rw) ~= "table" then return false end
  for i = 1, table.getn(rw) do
    local it = qcItemRec(rw[i])
    if it and EVAL_QC_KIND_PASS(kset, EVAL_QC_ITEM_KIND(it)) then return true end
  end
  return false
end

-- 位次 / 字符串键 → 链记录（两个入口都支持，测试与界面各取所需）
local function qcChainAt(key)
  if type(key) == "number" then
    local sorted = EVAL_QC_LIST(nil)
    return sorted[key]
  end
  if type(key) ~= "string" then return nil end
  local list = qcChainList()
  if type(list) ~= "table" then return nil end
  for i = 1, table.getn(list) do
    if list[i].k == key then return list[i] end
  end
  return nil
end

-- 详情模型（链记录 → 结构化；EVAL_QC_DETAIL 与 EVAL_QC_LINES 共用这一份）
local function qcDetailOf(c)
  if type(c) ~= "table" then return nil end
  local rewards = {}
  local rw = c.rw or {}
  for i = 1, table.getn(rw) do
    rewards[i] = { id = rw[i], it = EVAL_QC_ITEM(rw[i]) }
  end
  local steps = {}
  local qs = c.qs or {}
  for i = 1, table.getn(qs) do
    local q = qcQuests()
    steps[i] = { n = i, id = qs[i], q = (type(q) == "table") and q[qs[i]] or nil }
  end
  return { c = c, rewards = rewards, steps = steps }
end

-- ===== 搜索：链名 / 任务名 / 奖励物品名（plain 查找：绝不用模式，避开 % 与多字节坑） =====
-- 返回 { {idx=位次, c=链, kind="chain"|"quest"|"item", id=, name=, sub=}, ... }, extra
-- ★空查询 = 列出全部链（界面「任务线」过滤下的首屏）
-- ★filter（可选）= { faction=, tier= }：筛选与排序仍走 EVAL_QC_LIST（单一来源）。
--   带 filter 时 idx 是「筛选后列表」的位次 ⇒ 调用方要用行里的 `c.k`（链键）去定位详情。
-- ★★1.75.14 自动任务线记录 = **单一来源**：列表行与详情必须给出**一模一样**的字段 ——
--   稀有度就是从这些字段算的（`EVAL_QC_RARITY` 读 qs/open/t/件数）。旧实现详情少给 `qs`
--   ⇒ 同一条任务线「列表行色 ≠ 详情色」（组 192 ⑦「行色 == 数据层稀有度色」当场抓到）。
local function qcSeriesRec(s, idx)
  local sids, rw, seen = {}, {}, {}
  for k = 1, table.getn(s.steps or {}) do
    local qid = s.steps[k].id
    sids[k] = qid
    -- ★1.75.18 顺带把**奖励物品 id** 收进记录：任务线的「类型」筛选要按奖励种类判，
    --   而这一份是从 site 数据现算的（不再为筛选去逐条调详情 ⇒ 688 条系列也能秒筛）
    local q = EVAL_QC_BULK_QUEST(qid)
    local qrw = (q and q.rw) or {}
    for j = 1, table.getn(qrw) do
      local iid = qrw[j]
      local it = EVAL_QC_BULK_ITEM(iid)
      if it and it.eq and not seen[iid] then seen[iid] = true rw[table.getn(rw) + 1] = iid end
    end
  end
  return {
    k = "s:" .. tostring(idx), n = s.n, t = s.t, z = s.z, lo = s.lo, hi = s.hi,
    f = EVAL_QC_SERIES_FACTION(s), note = "", qs = sids, open = s.open, auto = true, rw = rw,
  }
end

function EVAL_QC_SEARCH(query, cap, filter)
  if type(qcChainList()) ~= "table" then return nil, "NO_DATA" end
  local q = query
  if type(q) ~= "string" then q = "" end
  q = string.lower(q)
  -- ★1.75.13 `cap ≤ 0` = **不限条数**（浏览要全量）。旧实现固定 200，而任务线按「等级升序」排列
  --   ⇒ 30 级以上的线全被截掉（用户实测「任务线最高只有 30 级」的真凶；数据本身到 60 级）。
  local max = tonumber(cap) or 30
  if max <= 0 then max = math.huge end
  -- ★1.75.14 **跨块统一排序**（用户问「任务线有按照任务最低等级排序吗?」）：
  --   旧实现是「策展链自己排好」+「自报系列自己排好」然后**直接拼接** ⇒ 第 22/23 条之间
  --   出现 **30 → 4 的回头**（用户截图正中：策展链尾巴 27/29/30 级，紧接着自报系列 4-5 级）。
  --   改成：两个来源**先全收**→ 统一排序 → **最后才截断**（排序键与数据层两处同口径：
  --   任务最低等级 → 稀有度权重 → 原始顺序；table.sort 在 5.1 **不稳定**，必须带原下标）。
  local all, extra = {}, 0
  local seq = 0
  local function put(e)
    seq = seq + 1
    e.at = seq
    all[table.getn(all) + 1] = e
  end
  local lc = function(s) return string.lower(tostring(s or "")) end
  -- ★1.75.15 用户要求「任务线过滤页增加个等级过滤」：等级档落在数据层（界面只给区间）。
  --   判据 = **区间重叠**（线自己的 lo..hi 与所选档相交）—— 若写「lo 落在档内」，
  --   跨档长线（如 30-40）在「40-49」档会整条消失，按等级找线就会找不到。
  local lvLo = tonumber((filter or {}).loMin)
  local lvHi = tonumber((filter or {}).loMax)
  -- ★1.75.14 等级**多选**：filter.lvRanges（档数组 { {lo,hi},… }）优先；没有才退回旧的 loMin/loMax 单档。
  local lvRanges = EVAL_QC_LV_RANGES((filter or {}).lvRanges or lvLo, lvHi)
  local function lvOK(c)
    if not lvRanges then return true end
    local lo = tonumber(c and c.lo) or 0
    local hi = tonumber(c and c.hi) or lo
    return EVAL_QC_LV_OVER(lvRanges, lo, hi)
  end
  -- ★1.75.18 用户要求「任务线->档位过滤使用装备那边的种类过滤」：种类档也落在数据层，
  --   与装备视图**共用同一份多选集合**（空集 = 不过滤）。判据 = 这条线的**奖励里有没有**勾选的种类。
  local kinds = (filter or {}).kinds
  -- ★1.75.14 地域档（用户要求：**两个列表**都能按地域筛；空集 = 全部）：策展链看 `c.z`、自报系列看 `s.z`。
  local zones = (filter or {}).zones
  local sorted = EVAL_QC_LIST(filter) -- ★与详情同一顺序（filter=nil 时位次 i 就是详情 id）
  for i = 1, table.getn(sorted) do
    local c = sorted[i]
    local hit = nil
    if q == "" or string.find(lc(c.n), q, 1, true) then
      hit = { kind = "chain", name = c.n }
    else
      local qs = c.qs or {}
      for k = 1, table.getn(qs) do
        local nm = EVAL_QC_QUEST_NAME(qs[k])
        if nm and string.find(lc(nm), q, 1, true) then
          hit = { kind = "quest", id = qs[k], name = nm }
          break
        end
      end
      if not hit then
        local rw = c.rw or {}
        for k = 1, table.getn(rw) do
          local nm = EVAL_QC_ITEM_NAME(rw[k])
          if nm and string.find(lc(nm), q, 1, true) then
            hit = { kind = "item", id = rw[k], name = nm }
            break
          end
        end
      end
    end
    if hit and lvOK(c) and qcRecKindsOK(c, kinds) and EVAL_QC_ZONE_PASS(zones, c.z) then
      put({ idx = i, c = c, kind = hit.kind, id = hit.id, name = hit.name, sub = c.z })
    end
  end
  -- ★1.75.9：再搜**自动任务线**（站点「本系列第 N/M 部分」拼出来的，含 30-60 与开门/大型任务线）
  --   结果 kind="series"、键 key="s:<位次>"（详情走 EVAL_QC_DETAIL("s:n")）；同一份排序/筛选口径。
  local ser = EVAL_QC_SERIES_LIST()
  for i = 1, table.getn(ser) do
    local s = ser[i]
    local okF = true
    if filter and filter.faction and filter.faction ~= "ALL" then
      local sf = EVAL_QC_SERIES_FACTION(s)
      if sf ~= filter.faction then okF = false end
    end
    if okF and (not filter or not filter.tier or filter.tier == "ALL" or s.t == filter.tier) then
      local hit = nil
      if q == "" or string.find(lc(s.n), q, 1, true) then
        hit = { kind = "series", name = s.n }
      else
        for k = 1, table.getn(s.steps) do
          if string.find(lc(s.steps[k].n), q, 1, true) then
            hit = { kind = "series", id = s.steps[k].id, name = s.steps[k].n }
            break
          end
        end
      end
      if hit and lvOK(s) then
        -- ★1.75.14 记录走 **qcSeriesRec**（与详情同一来源；旧实现这里手拼、详情另拼一份 ⇒ 字段漂移）
        local rec = qcSeriesRec(s, i)
        -- ★1.75.18 种类筛选按记录里的奖励判（qcSeriesRec 已把奖励 id 一起收好）
        if qcRecKindsOK(rec, kinds) and EVAL_QC_ZONE_PASS(zones, s.z) then
          put({
            idx = i, kind = "series", key = "s:" .. tostring(i), id = hit.id, name = hit.name,
            c = rec, sub = s.z,
          })
        end
      end
    end
  end
  -- ★1.75.14 统一排序 + 最后截断（跨两个来源，键：任务最低等级 → 稀有度权重 → 原始顺序）
  local dec = {}
  for i = 1, table.getn(all) do
    local c = all[i].c or {}
    dec[i] = { e = all[i], lo = tonumber(c.lo) or 99, r = QC_RAR_W[EVAL_QC_RARITY(c)] or 9, n = i }
  end
  table.sort(dec, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.r ~= b.r then return a.r < b.r end
    return a.n < b.n
  end)
  local out = {}
  for i = 1, table.getn(dec) do
    if table.getn(out) < max then out[table.getn(out) + 1] = dec[i].e
    else extra = extra + 1 end
  end
  return out, extra
end

-- 自动任务线的阵营：步骤任务里只要有联盟标记就含 A、有部落标记就含 H；两者都有/都没有 = 双方(B)
-- （站点只在部分任务上标 A/H ⇒ 拿不准时按「共有」放行，宁可多显示也不误杀 —— 与装备视图同口径）
function EVAL_QC_SERIES_FACTION(s)
  if type(s) ~= "table" then return "B" end
  local a, h = false, false
  for i = 1, table.getn(s.steps or {}) do
    local q = EVAL_QC_BULK_QUEST(s.steps[i].id)
    if q then
      if q.f == "A" then a = true elseif q.f == "H" then h = true end
    end
  end
  if a and not h then return "A" end
  if h and not a then return "H" end
  return "B"
end

-- 自动任务线 → 详情模型（形状与策展链**完全一致**，界面/文案行不必分叉）
function EVAL_QC_SERIES_DETAIL(key)
  local idx = tonumber(string.sub(tostring(key or ""), 3)) or 0
  local ser = EVAL_QC_SERIES_LIST()
  local s = ser[idx]
  if not s then return nil end
  local rewards, steps = {}, {}
  for i = 1, table.getn(s.steps) do
    local q = EVAL_QC_BULK_QUEST(s.steps[i].id)
    -- ★★★1.75.1：这里**绝不能再把系列步骤名覆盖掉** —— 原写 `n = i` 把站点系列块抄来的**名字**顶掉成**序号**，
    --   于是 `EVAL_QC_LINES` 只能退回去查 q 表 ⇒ 没有装备奖励的步骤全显示成 `#5742`（用户截图里的真凶之一）。
    --   现约定：`n` = 序号（渲染 "1. " 用）· **`nm` = 名字**（站点系列块 → sn 兜底）。
    steps[i] = { n = i, id = s.steps[i].id, nm = s.steps[i].n, q = q }
    for k = 1, table.getn((q and q.rw) or {}) do
      local iid = q.rw[k]
      local it = EVAL_QC_BULK_ITEM(iid)
      if it and it.eq then
        local dup = false
        for j = 1, table.getn(rewards) do if rewards[j].id == iid then dup = true break end end
        if not dup then
          rewards[table.getn(rewards) + 1] = { id = iid, it = it }
        end
      end
    end
  end
  -- 奖励按「武器优先 → 品质 → 物品等级」排（与策展链同一口径）
  local dec = {}
  for i = 1, table.getn(rewards) do
    local it = rewards[i].it
    dec[i] = { r = rewards[i], w = EVAL_QC_IS_WEAPON(it) and 0 or 1, q = -(tonumber(it.q) or 0),
               il = -(tonumber(it.ilvl) or 0), n = i }
  end
  table.sort(dec, function(x, y)
    if x.w ~= y.w then return x.w < y.w end
    if x.q ~= y.q then return x.q < y.q end
    if x.il ~= y.il then return x.il < y.il end
    return x.n < y.n
  end)
  local rw = {}
  for i = 1, table.getn(dec) do rw[i] = dec[i].r end
  return {
    c = qcSeriesRec(s, idx),
    rewards = rw, steps = steps,
  }
end

-- ===== 详情（位次 / 链键 / "s:<位次>" 自动任务线键都可；查不到如实返回 nil） =====
function EVAL_QC_DETAIL(key)
  if type(key) == "string" and string.sub(key, 1, 2) == "s:" then return EVAL_QC_SERIES_DETAIL(key) end
  return qcDetailOf(qcChainAt(key))
end

-- 链的**奖励物品 id**（1.75.10 用户要求：任务线行后面也要摆奖励图标 + 悬停预览链接）
-- 顺序与详情**完全一致**（武器优先 → 品质 → 物品等级），max 只截展示、不影响详情。
-- 返回 ids（最多 max 件）, 总数（用来显示「+N」）。
function EVAL_QC_CHAIN_REWARDS(key, max)
  local d = EVAL_QC_DETAIL(key)
  local ids, total = {}, 0
  local cap = tonumber(max) or 4
  for i = 1, table.getn((d and d.rewards) or {}) do
    local id = d.rewards[i].id
    if id then
      total = total + 1
      if table.getn(ids) < cap then ids[table.getn(ids) + 1] = id end
    end
  end
  return ids, total
end

-- ===== 武器判定（唯一来源）：物品表里有 dps 的即武器 =====
function EVAL_QC_IS_WEAPON(rec)
  if type(rec) ~= "table" then return false end
  local d = tonumber(rec.dps)
  return (d ~= nil and d > 0) and true or false
end

-- ===== 装备种类 / 子类型的**旧位置**已上移到 EVAL_QC_SEARCH 之前（1.75.18：任务线筛选要用）=====

-- 种类清单（数组）：{ {k=种类名, w=true/false(武器子类型), n=件数, i=首见序} }
-- 排序唯一来源：武器子类型在前 → 件数降序 → 名字升序 → 首见序（table.sort 在 5.1 不稳定 ⇒ 末项兜底）
function EVAL_QC_KIND_LIST()
  local rows = EVAL_QC_ITEM_ROWS(nil)
  local byKind, order = {}, {}
  for i = 1, table.getn(rows) do
    local it = rows[i].it
    local k = EVAL_QC_ITEM_KIND(it)
    if k ~= "" then
      local e = byKind[k]
      if not e then
        e = { k = k, w = false, n = 0, i = i }
        byKind[k] = e
        order[table.getn(order) + 1] = k
      end
      e.n = e.n + 1
      if EVAL_QC_IS_WEAPON(it) then e.w = true end
    end
  end
  local out = {}
  for i = 1, table.getn(order) do out[i] = byKind[order[i]] end
  table.sort(out, function(a, b)
    local aw, bw = a.w and 0 or 1, b.w and 0 or 1
    if aw ~= bw then return aw < bw end
    if a.n ~= b.n then return a.n > b.n end
    if a.k ~= b.k then return a.k < b.k end
    return a.i < b.i
  end)
  return out
end

-- 两个分组（供筛选菜单画分组标题；界面不自己分组）：返回 武器子类型名数组, 其它种类名数组
function EVAL_QC_KIND_GROUPS()
  local list = EVAL_QC_KIND_LIST()
  local wp, ot = {}, {}
  for i = 1, table.getn(list) do
    if list[i].w then wp[table.getn(wp) + 1] = list[i].k else ot[table.getn(ot) + 1] = list[i].k end
  end
  return wp, ot
end

-- 多选集合判定已上移为**全局** EVAL_QC_KIND_PASS（1.75.18：任务线筛选与装备筛选共用同一份）

-- ===== 详细文案行（纯数据，界面负责本地化与渲染）=====
-- kind: title / sub / sec_reward / reward / sec_steps / step / note
--   reward 行带 id=物品 id（界面挂悬停 tooltip）；step 行带 id=任务 id（界面挂跳转链接）
function EVAL_QC_LINES(key)
  local d = EVAL_QC_DETAIL(key)
  if not d then return nil end
  local c = d.c
  local out = {}
  table.insert(out, { text = tostring(c.n or ""), kind = "title" })
  table.insert(out, {
    text = string.format("%s · %s~%s", tostring(c.z or ""), tostring(c.lo or "?"), tostring(c.hi or "?")),
    kind = "sub",
  })
  table.insert(out, { text = "", kind = "sec_reward" })
  for i = 1, table.getn(d.rewards) do
    local it = d.rewards[i].it
    local nm = (it and it.n) or ("#" .. tostring(d.rewards[i].id))
    local parts = { nm }
    if it then
      if EVAL_QC_IS_WEAPON(it) then parts[table.getn(parts) + 1] = string.format("DPS%.1f", tonumber(it.dps) or 0) end
      if it.s and it.k then parts[table.getn(parts) + 1] = tostring(it.s) .. tostring(it.k) end
      if it.st and it.st ~= "" then parts[table.getn(parts) + 1] = it.st end
    end
    table.insert(out, { text = table.concat(parts, " · "), kind = "reward", id = d.rewards[i].id })
  end
  table.insert(out, { text = "", kind = "sec_steps" })
  for i = 1, table.getn(d.steps) do
    local s = d.steps[i]
    -- ★★★1.75.1 名字四级来源（**别只认 q 表**）：系列步骤名（站点系列块抄来的 `nm`）→ q 表 → `sn` → 如实 `#id`。
    --   旧写法 `(s.q and s.q.n) or ("#"..id)` 对**没有装备奖励**的步骤必然退化（用户截图：7 行全 `#5742`）。
    local nm = (type(s.nm) == "string" and s.nm ~= "" and s.nm)
      or (s.q and s.q.n) or EVAL_QC_STEP_NAME(s.id) or ("#" .. tostring(s.id))
    local lv = (s.q and s.q.lv) and ("(" .. tostring(s.q.lv) .. ")") or ""
    table.insert(out, { text = string.format("%d. %s%s", s.n, nm, lv), kind = "step", id = s.id, name = nm })
  end
  if c.note and c.note ~= "" then
    table.insert(out, { text = tostring(c.note), kind = "note" })
  end
  return out
end

-- ===== 装备视图（1.75.1）：「练级要装备」的入口 —— 先按等级列装备，再反查要做哪些任务 =====
-- 排序（单一来源）：可获得等级(链的 lo)升序 → 武器优先 → 品质降序 → 物品等级降序 → 原序。
-- 同一件装备可能来自多条链（例：墓碑节杖 = 联盟线 + 部落线）⇒ chains 是数组，全部返回。
-- filter（可选）= { loMin=, loMax=, weaponOnly=true, faction="A"/"H"/"B", kinds={[种类]=true} }
--   kinds = 种类**多选集合**（空集/缺省 = 全部）；weaponOnly 保留给旧调用（= 只看武器子类型）
-- ★1.75.9：本函数 = **策展链派生**（旧实现）—— 现在只作为**全量数据缺席时的兜底**（诚实降级）。
--   有 QuestBulk.lua 时走 EVAL_QC_BULK_ITEM_ROWS（10-60+ 全部带装备奖励的任务），见文件末尾的分派。
local function qcChainItemRows(filter)
  local list = qcChainList()
  if type(list) ~= "table" then return {} end
  local f = filter or {}
  local byItem, order = {}, {}
  for i = 1, table.getn(list) do
    local c = list[i]
    local lo = tonumber(c.lo) or 99
    local lvOK = true
    if f.loMin and (lo < f.loMin or lo > (f.loMax or 999)) then lvOK = false end
    local facOK = true
    if f.faction and f.faction ~= "ALL" and c.f ~= f.faction then facOK = false end
    if lvOK and facOK then
      local rw = c.rw or {}
      for k = 1, table.getn(rw) do
        local id = rw[k]
        local it = EVAL_QC_ITEM(id)
        if it and EVAL_QC_KIND_PASS(f.kinds, EVAL_QC_ITEM_KIND(it))
           and not (f.weaponOnly and not EVAL_QC_IS_WEAPON(it)) then
          if not byItem[id] then
            byItem[id] = { id = id, it = it, chains = {}, lo = lo }
            order[table.getn(order) + 1] = id
          end
          local e = byItem[id]
          e.chains[table.getn(e.chains) + 1] = c
          if lo < e.lo then e.lo = lo end
        end
      end
    end
  end
  local dec = {}
  for n = 1, table.getn(order) do
    local e = byItem[order[n]]
    dec[n] = {
      e = e,
      w = EVAL_QC_IS_WEAPON(e.it) and 0 or 1,
      q = -(tonumber(e.it.q) or 0),
      il = -(tonumber(e.it.ilvl) or 0),
      lo = e.lo,
      n = n,
    }
  end
  table.sort(dec, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.w ~= b.w then return a.w < b.w end
    if a.q ~= b.q then return a.q < b.q end
    if a.il ~= b.il then return a.il < b.il end
    return a.n < b.n
  end)
  local out = {}
  for n = 1, table.getn(dec) do out[n] = dec[n].e end
  return out
end

-- 装备视图统一入口：**全量优先**（用户要求：只要有装备/武器的任务都采集，单任务也算），
-- 全量数据缺席时退回策展链派生（界面与判定都只认这一个入口，不各写一份）。
function EVAL_QC_ITEM_ROWS(filter)
  if EVAL_QC_BULK_READY() then return EVAL_QC_BULK_ITEM_ROWS(filter) end
  return qcChainItemRows(filter)
end

-- 单件装备的来源链（装备详情用）；查不到如实返回 nil
-- ★1.75.9：改成**反向索引**（不再借道 EVAL_QC_ITEM_ROWS —— 后者已改为全量数据驱动，
--   两处形状不同，借道就会静默返回 nil；顺带把「每件装备 × 每条链」的重复扫描收成一次）。
local qcCurIdx = nil
local function qcCurItemIndex()
  if qcCurIdx then return qcCurIdx end
  local idx = {}
  local list = qcChainList()
  if type(list) == "table" then
    for i = 1, table.getn(list) do
      local c = list[i]
      local rw = c.rw or {}
      for k = 1, table.getn(rw) do
        local arr = idx[rw[k]]
        if not arr then arr = {} idx[rw[k]] = arr end
        arr[table.getn(arr) + 1] = c
      end
    end
  end
  qcCurIdx = idx
  return idx
end

function EVAL_QC_ITEM_CHAINS(itemId)
  local arr = qcCurItemIndex()[itemId]
  if not arr or table.getn(arr) == 0 then return nil end
  return arr
end

--   用户要求：「任务奖励只要有装备/武器的都可以进行数据采集，单任务也可以加入采集」+
--            「经典任务线衍生到 30-60 范围，包含大型任务线、各种开门任务线」
--   数据记法是紧凑串（见 QuestBulk.lua 头部注释），分隔符 '|' 由生成器保证不出现在名字里。
--   本层与策展层**并存**：全量在 → 装备视图走全量；全量缺席 → 自动退回策展链派生（诚实降级）。
-- ============================================================================
local function qcBulk() return rawget(_G, "EVAL_QC_BULK") end

local qcBQ, qcBI, qcBS, qcBIdx = nil, nil, nil, nil

local function qcBulkSplit(s)
  local out, p = {}, 1
  while true do
    local i = string.find(s, "|", p, true)
    if not i then out[table.getn(out) + 1] = string.sub(s, p) break end
    out[table.getn(out) + 1] = string.sub(s, p, i - 1)
    p = i + 1
  end
  return out
end

-- 数据是否可用（诚实失败的前提）
function EVAL_QC_BULK_READY()
  local b = qcBulk()
  if type(b) ~= "table" then return nil end
  if type(b.q) ~= "table" or type(b.i) ~= "table" then return nil end
  return true
end

function EVAL_QC_BULK_META()
  local b = qcBulk()
  if type(b) ~= "table" then return nil end
  return b.meta
end

-- ★★★1.75.1（用户实测「爱与家庭」搜到却显示成一串 `#5742`）：系列步骤名的**唯一补充来源** = 生成数据的 `sn` 表。
--   背景：进包 q 表**只装带装备奖励的任务**（751 / 站点 4018 页），而站点自报系列里大量步骤**没有装备奖励**
--   ⇒ 它们的名字既不在 q 表、也不在策展表 —— **只在 `sn`**（生成期从站点系列块抄下来的）。
--   ★任何「按 id 反查任务名」的地方都要过这里，否则退化成 `#5742`：步骤行（`EVAL_QC_LINES`）·
--   放大镜（DataSearch 的 step 分支）· 装备→来源任务线（`EVAL_QC_ITEM_CHAINS` 那一路）。
function EVAL_QC_STEP_NAME(id)
  local b = qcBulk()
  local sn = (type(b) == "table") and b.sn or nil
  if type(sn) ~= "table" then return nil end
  local nm = sn[id]
  if type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

-- 全量任务行 → { id, n, lv, z, f(阵营 A/H/""), rw={物品id} }；查不到如实 nil
function EVAL_QC_BULK_QUEST(id)
  local b = qcBulk()
  if type(b) ~= "table" or type(b.q) ~= "table" then return nil end
  local raw = b.q[id]
  if type(raw) ~= "string" then return nil end
  qcBQ = qcBQ or {}
  local hit = qcBQ[id]
  if hit then return hit end
  local p = qcBulkSplit(raw)
  local rw = {}
  if type(p[5]) == "string" and p[5] ~= "" then
    for w in string.gmatch(p[5] .. ",", "([^,]+)") do
      local n = tonumber(w)
      if n then rw[table.getn(rw) + 1] = n end
    end
  end
  local rec = { id = id, n = p[1] or "", lv = tonumber(p[2]) or 0, z = p[3] or "", f = p[4] or "", rw = rw }
  qcBQ[id] = rec
  return rec
end

-- ============================================================================
-- 全量任务表（1.75.14 · `quest/QuestAll.lua` 生成物）：**含没有装备奖励的任务**
--   用户定案：「**C 执行**」= 全量任务进包（此前只收「带装备奖励」的 751 条 ⇒ 血色修道院那类
--   无装备奖励的任务在插件里根本检索不到 —— 用户实测报障的正是这个）。
--   `q[id] = 名称|任务等级|地区|阵营(A/H/空=不限)|有装备奖励(0/1)|标签码(d地下城 e精英 r团队 pPvP s护送 l传说 w世界事件)`
--            `|需要等级|c:可选奖励id,r|r:直接给予id,r`（后两段没有就整段省略；`iw[id]` = 奖励物品名）
--   ★1.75.21 后三段是**审计补的**（用户：「有些属于任务线的，点任务详情内是空的」）—— 详见本文件下方
--     `EVAL_QC_ALL_REWARDS` 那一段的审计结论。
--   ★只读、按需解析并缓存（与 bulk 同一套做法）；表不在 ⇒ 一路如实返回 nil（诚实降级）。
-- ============================================================================
local qcAllQ = nil
local function qcAllTbl() return rawget(_G, "EVAL_QC_ALL") end

function EVAL_QC_ALL_READY()
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return nil end
  return true
end

-- 条目数（表以 id 为键 ⇒ 不能用 table.getn；优先用生成器写下的 meta.n，退化为现数一次）
function EVAL_QC_ALL_COUNT()
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return 0 end
  if a.meta and tonumber(a.meta.n) then return tonumber(a.meta.n) end
  local n = 0
  for _ in pairs(a.q) do n = n + 1 end
  a.meta = a.meta or {}
  a.meta.n = n
  return n
end

-- 单个任务 → { id, n, lv, z, f, gear(boolean), tags }；查不到如实 nil
function EVAL_QC_ALL_QUEST(id)
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return nil end
  local raw = a.q[id]
  if type(raw) ~= "string" then return nil end
  qcAllQ = qcAllQ or {}
  local hit = qcAllQ[id]
  if hit then return hit end
  local p = qcBulkSplit(raw)
  local rec = {
    id = id, n = p[1] or "", lv = tonumber(p[2]) or 0, z = p[3] or "",
    f = p[4] or "", gear = (p[5] == "1"), tags = p[6] or "",
    -- ★1.75.21 需要等级（站点「需要等级 N」）——任务详情要显示，缺字段的老表按 0 处理（诚实降级）
    req = tonumber(p[7]) or 0,
  }
  qcAllQ[id] = rec
  return rec
end

-- ★1.75.14 某任务的**奖励物品**（任务行的「行尾奖励图标带」用它）—— ★**与任务线行同一口径：不按 eq 筛**。
--   ★★为什么不能按 `eq` 筛（本次审计实测）：站点的**类型/部位字段会缺**，于是 `预言藤杖`（法杖！）、
--     `悲哀衬肩`（肩甲！）、`洛瑞卡宝珠`（副手！）全被判成 `eq=false` ⇒ 按 eq 筛会把**真装备藏掉**
--     （用户要求是「**如果有装备就把装备显示出来**」）。项目铁律：**判不出就不剔**。
--   没有奖励 ⇒ `{}, 0`（界面不画图标，详情里如实写「无装备奖励」）。
--   ★与 `EVAL_QC_CHAIN_REWARDS` 同形（任务线行用的是那个）⇒ 界面那段布局代码两类行共用。
function EVAL_QC_QUEST_REWARDS(id, max)
  local bq = EVAL_QC_BULK_QUEST(id)
  local all = (bq and bq.rw) or {}
  local total = table.getn(all)
  local m = tonumber(max) or total
  if m < 1 then m = 0 end
  local out = {}
  for i = 1, total do
    if i > m then break end
    out[i] = all[i]
  end
  return out, total
end

-- ============================================================================
-- ★★1.75.21 **单体任务详情**的数据口（用户报障：「有些属于任务线的，但是点击任务详情内是空的。自己审计下」）
--   审计结论（对照 database.emberveil.org 实测）：
--   ① 详情此前只读 `QuestBulk.q`（= 站点上「**带装备奖励**」的 751 条）⇒ 其余 3267 条任务的奖励
--      **整段是空的**，正文只剩一行「无装备奖励」= 用户看到的「空的」。
--      站点实测：给奖励的任务 **1685** 个，其中 **934** 个不是装备奖励任务（药水/卷轴/任务物品/食谱）
--      —— 这些数据的唯一来源就是本次补进生成物的 `c:` / `r:` 两个字段。
--   ② 行上标着「属任务线」，点进去却**不提是哪条线**（详情里根本没有任务线那一段）
--      —— 本组新增 `EVAL_QC_SERIES_OF` / `EVAL_QC_QUEST_CHAINS` 反查（数据早就在，只是没人读）。
--   ★用户 #2861「塔贝萨的任务」就是①+②的合体：站点上它确实**没有任何物品奖励**（只有经验值），
--     但它属于「塔贝萨的任务 → 深渊皇冠」这条 2 步系列 ⇒ 现在详情会列出该线、步骤与需要等级。
-- ============================================================================
local qcAllI, qcAllRw = nil, nil

-- 奖励物品名（**只收 QuestBulk.i 里没有的**）→ { id, n, q }；查不到如实 nil
function EVAL_QC_ALL_ITEM(id)
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.iw) ~= "table" then return nil end
  local raw = a.iw[id]
  if type(raw) ~= "string" or raw == "" then return nil end
  qcAllI = qcAllI or {}
  local hit = qcAllI[id]
  if hit then return hit end
  local rec = { id = id, n = raw, q = 1 }
  -- 装备表认识这件物品就优先用那份（有品质/部位，tooltip 色阶才对）
  local it = EVAL_QC_BULK_ITEM(id)
  if it then
    rec.q = tonumber(it.q) or 1
    if tostring(it.n or "") ~= "" then rec.n = it.n end
  end
  qcAllI[id] = rec
  return rec
end

-- 奖励物品的**统一取件口**（列表行/详情行都走它，绝不各写一份）——装备表优先，其次奖励名表
function EVAL_QC_REWARD_ITEM(id)
  return EVAL_QC_BULK_ITEM(id) or EVAL_QC_ALL_ITEM(id)
end

-- 某任务在站点上的奖励 → choose（可选一件 id）· receive（直接给予 id）；各自可为空表
--   ★生成物里的整段是 `c:1,2|r:3`（没有的段整段省略）⇒ 按**前缀**认字段，不认下标（往后加字段不会错位）。
function EVAL_QC_ALL_REWARDS(id)
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return nil, nil end
  local raw = a.q[id]
  if type(raw) ~= "string" then return nil, nil end
  qcAllRw = qcAllRw or {}
  local hit = qcAllRw[id]
  if hit then return hit.c, hit.r end
  local p = qcBulkSplit(raw)
  local function ids(s)
    local out = {}
    s = string.sub(s, 3)          -- 剥掉 `c:` / `r:`
    for w in string.gmatch(s .. ",", "([^,]+)") do
      local n = tonumber(w)
      if n then out[table.getn(out) + 1] = n end
    end
    return out
  end
  local c, r = {}, {}
  for i = 7, table.getn(p) do
    local f = p[i]
    if type(f) == "string" then
      local pre = string.sub(f, 1, 2)
      if pre == "c:" then c = ids(f)
      elseif pre == "r:" then r = ids(f) end
    end
  end
  qcAllRw[id] = { c = c, r = r }
  return c, r
end

-- 任务 → **自动任务线**反查（键 `s:<位次>`，与列表/详情同一份 `EVAL_QC_SERIES_LIST` 数据）
--   返回 { { key="s:12", rec=系列记录, n=第几步 }, … }；不属于任何线 ⇒ nil（诚实）
local qcSerIdx = nil
local function qcSeriesIndex()
  if qcSerIdx then return qcSerIdx end
  local idx = {}
  local ser = EVAL_QC_SERIES_LIST()          -- ★全局函数，运行期才取（定义在文件更后面）
  for i = 1, table.getn(ser) do
    local steps = ser[i].steps or {}
    for k = 1, table.getn(steps) do
      local qid = steps[k].id
      if qid then
        local arr = idx[qid]
        if not arr then arr = {} idx[qid] = arr end
        arr[table.getn(arr) + 1] = { key = "s:" .. tostring(i), rec = ser[i], n = k }
      end
    end
  end
  qcSerIdx = idx
  return idx
end

function EVAL_QC_SERIES_OF(qid)
  local idx = qcSeriesIndex()
  local arr = idx[qid]
  if not arr or table.getn(arr) == 0 then return nil end
  return arr
end

-- 任务 → **策展链**反查（`qs` 里含该任务 id 的链）→ { { rec=链记录, n=第几步 }, … }；查不到如实 nil
local qcCurQIdx = nil
local function qcCurQuestIndex()
  if qcCurQIdx then return qcCurQIdx end
  local idx = {}
  local list = qcChainList()
  if type(list) == "table" then
    for i = 1, table.getn(list) do
      local c = list[i]
      local qs = c.qs or {}
      for k = 1, table.getn(qs) do
        local arr = idx[qs[k]]
        if not arr then arr = {} idx[qs[k]] = arr end
        arr[table.getn(arr) + 1] = { rec = c, n = k }
      end
    end
  end
  qcCurQIdx = idx
  return idx
end

function EVAL_QC_QUEST_CHAINS(qid)
  local arr = qcCurQuestIndex()[qid]
  if not arr or table.getn(arr) == 0 then return nil end
  return arr
end

-- ============================================================================
-- ★★1.75.21 **父子任务（前置/后续）**——用户：「比如一个任务完成出现另外 2 个后续任务，则定义父子任务形式」
--   数据两条腿（**站点为主、系列兜底**，界面只读这一个口）：
--     ① 站点任务页「解锁」面板 → 生成物 `EVAL_QC_ALL.ch[id]="子id,子id"`（一个任务可带 N 个后续）；
--     ② 没有「解锁」信息的任务 → **系列下一步**（站点「本系列第 N/M 部分」的线性顺序，`EVAL_QC_SERIES_OF` 现成）。
--   ★★**父不是唯一的**（一个任务可以同时被多条线解锁）⇒ 运行期给的是**有向图**：`EVAL_QC_QUEST_PARENTS`
--     如实返回全部前置；树视图对同一节点**只展开一次**并在行上标出「N 个前置」（不重复画、也不假装唯一）。
-- ============================================================================
local qcKids, qcPars = nil, nil
local function qcKidIndex()
  if qcKids then return qcKids end
  local idx = {}
  local a = qcAllTbl()
  if type(a) == "table" and type(a.ch) == "table" then
    for id, raw in pairs(a.ch) do
      if type(raw) == "string" then
        local arr = {}
        for w in string.gmatch(raw .. ",", "([^,]+)") do
          local n = tonumber(w)
          if n then arr[table.getn(arr) + 1] = n end
        end
        if table.getn(arr) > 0 then idx[id] = arr end
      end
    end
  end
  qcKids = idx
  return idx
end

-- 站点点「解锁」给出的**后续任务 id 数组**；没有这条 ⇒ nil（不编）
function EVAL_QC_CHILDREN(id)
  local k = qcKidIndex()[id]
  if not k or table.getn(k) == 0 then return nil end
  return k
end

-- **后续任务的唯一入口**：站点「解锁」优先；没有就退回「系列下一步」（线性顺序）
--   返回 { id, ... } 或 nil。★同一份数据也喂给树视图与任务详情的「后续任务」段。
function EVAL_QC_QUEST_NEXT(id)
  local k = qcKidIndex()[id]
  if k and table.getn(k) > 0 then return k end
  local so = (type(EVAL_QC_SERIES_OF) == "function") and EVAL_QC_SERIES_OF(id) or nil
  if so then
    for i = 1, table.getn(so) do
      local steps = so[i].rec and so[i].rec.steps or {}
      local nx = steps[(so[i].n or 0) + 1]
      if nx and nx.id then return { nx.id } end
    end
  end
  return nil
end

-- 反向：**前置任务**（谁解锁了我）→ id 数组；查不到如实 nil
local function qcParIndex()
  if qcPars then return qcPars end
  local idx, kids = {}, qcKidIndex()
  for pid, arr in pairs(kids) do
    for i = 1, table.getn(arr) do
      local c = arr[i]
      local t = idx[c]
      if not t then t = {} idx[c] = t end
      t[table.getn(t) + 1] = pid
    end
  end
  -- ★顺序确定化（pairs 遍历顺序不定 ⇒ 同一屏两次画出来不一样）
  for _, t in pairs(idx) do table.sort(t) end
  qcPars = idx
  return idx
end

function EVAL_QC_QUEST_PARENTS(id)
  local t = qcParIndex()[id]
  if not t or table.getn(t) == 0 then return nil end
  return t
end

-- 树深度上限（防环 + 防病态长链把一屏撑爆；超出 ⇒ 该节点**照常出行**但不再往下展开）
local QC_TREE_MAX_DEPTH = 8

-- **父子任务树**：把过滤后的任务按「前置 → 后续」展开成**扁平行**（界面只负责画，不做图算法）
--   filter 与列表**同一口径**（等级档/来源/阵营/关键词），返回：
--     rows = { { q=任务记录, depth=缩进层级, par=前置个数, kids=后续个数, tree=true }, … }
--     画出来的行数 · **多前置**（已在上方展开过、没再画）的条数 · **撞上限**没走到的条数
--   ★两个计数分开返回是判据：混在一起 ⇒ 提示行会报「3418 条多前置」这种假话（实测过）。
function EVAL_QC_QUEST_TREE(filter, cap)
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return {}, 0, 0, 0 end
  local f = filter or {}
  local maxRows = tonumber(cap) or 600
  if maxRows <= 0 then maxRows = 600 end
  -- ① 过滤（复用唯一入口：等级/来源/阵营/关键词的口径与列表完全一致）
  local flt = {}
  for k, v in pairs(f) do flt[k] = v end
  flt.exclude = nil                       -- 树视图**不做**「步骤并入链行」（树本身就是层级）
  local list = EVAL_QC_QUEST_LIST(f.query, flt, 0)
  local S = {}
  for i = 1, table.getn(list) do S[list[i].id] = list[i] end
  local nS = table.getn(list)
  if nS == 0 then return {}, 0, 0 end
  -- ② 边：两端**都在本次结果里**才成边（否则父被筛掉，子就成了根 —— 与列表那条判据同源）
  local kids, parents = {}, {}
  for id in pairs(S) do
    local ks = EVAL_QC_QUEST_NEXT(id)
    if ks then
      for i = 1, table.getn(ks) do
        local c = ks[i]
        if c and S[c] then
          local arr = kids[id]
          if not arr then arr = {} kids[id] = arr end
          arr[table.getn(arr) + 1] = c
          parents[c] = (parents[c] or 0) + 1
        end
      end
    end
  end
  -- ③ 排序（等级 → 名字 → id，确定化）
  local function byIdx(x, y)
    local ax, ay = S[x], S[y]
    local xl, yl = tonumber(ax and ax.lv) or 0, tonumber(ay and ay.lv) or 0
    if xl ~= yl then return xl < yl end
    local xn, yn = tostring(ax and ax.n or ""), tostring(ay and ay.n or "")
    if xn ~= yn then return xn < yn end
    return x < y
  end
  local roots = {}
  for id in pairs(S) do if not parents[id] then roots[table.getn(roots) + 1] = id end end
  table.sort(roots, byIdx)
  -- ④ 迭代先序 DFS（栈里存 {id, depth}；`seen` 保证一个节点只展开一次）
  --   ★返回的两个计数**必须分开**（旧写法把两者混成一个数 ⇒ 提示行会说「3418 条多前置」这种假话）：
  --     `dup`  = **有多个前置的任务**（只在首个前置下展开；★在**入栈**处 `if not seen` 就拦掉了，
  --              所以不能在出栈处数 —— 那样永远数不到，实测奥达曼一个都是 0，而节点上明明写着「前置2」）
  --     `rest` = 因为**撞到行数上限**而没走到的（要靠筛选收窄，不是多前置）
  local out, seen, nSeen = {}, {}, 0
  local stack = {}
  for i = table.getn(roots), 1, -1 do stack[table.getn(stack) + 1] = { roots[i], 0 } end
  while table.getn(stack) > 0 do
    local top = stack[table.getn(stack)]
    stack[table.getn(stack)] = nil
    local id, depth = top[1], top[2]
    if not seen[id] then
      seen[id] = true
      nSeen = nSeen + 1
      local r = S[id]
      local ks = kids[id]
      out[table.getn(out) + 1] = {
        q = r, depth = depth, par = parents[id] or 0,
        kids = ks and table.getn(ks) or 0, tree = true,
      }
      if table.getn(out) >= maxRows then break end
      if ks and depth < QC_TREE_MAX_DEPTH then
        local sorted = {}
        for i = 1, table.getn(ks) do sorted[i] = ks[i] end
        table.sort(sorted, byIdx)
        for i = table.getn(sorted), 1, -1 do
          if not seen[sorted[i]] then stack[table.getn(stack) + 1] = { sorted[i], depth + 1 } end
        end
      end
    end
  end
  local dup = 0
  for i = 1, table.getn(out) do if (out[i].par or 0) > 1 then dup = dup + 1 end end
  return out, table.getn(out), dup, nS - nSeen
end

-- ============================================================================
-- ★★1.75.22 **任务目标材料（需求）**——用户：「任务需求完成需要的目标材料……显示在列表元素右侧、与装备图标
--   同行，提示『需求: xx,xx』，图标展示；**只筛选显示制造业/普通物品等、而非任务道具**」。
--   数据：生成物 `ob[id]="物品id:需要数量,…"`（**生成期已剔除任务道具** —— 判据 = 物品页有没有
--   `Quest Item` 标记；交易品/消耗品/装备/配方一律保留）+ `ow[物品id]="名|品质"`（材料名/品质单一来源）。
--   ★为什么必须按物品页判：任务页上「任务道具」与「交易品」的目标行**标记完全一样**（同色同结构），
--     唯一区别在物品页 ⇒ 只能逐件物品页取证（`tmp/refetch_objectives.js` Pass B）。
-- ============================================================================
local qcNeedIdx = nil

-- 解析并缓存 ob 表 → { [任务id] = { ids={…}, needs={…} } }
local function qcNeedIndex()
  if qcNeedIdx then return qcNeedIdx end
  local idx = {}
  local a = qcAllTbl()
  if type(a) == "table" and type(a.ob) == "table" then
    for id, raw in pairs(a.ob) do
      if type(raw) == "string" and raw ~= "" then
        local ids, needs = {}, {}
        for w in string.gmatch(raw .. ",", "([^,]+)") do
          local iid, cnt = string.match(w, "^(%d+):(%d+)$")
          if iid then
            ids[table.getn(ids) + 1] = tonumber(iid)
            needs[table.getn(needs) + 1] = tonumber(cnt) or 0
          end
        end
        if table.getn(ids) > 0 then idx[tonumber(id) or id] = { ids = ids, needs = needs } end
      end
    end
  end
  qcNeedIdx = idx
  return idx
end

-- 材料的取件口（名字/品质）：`ow` 优先，其次装备表/奖励名表（老数据也能显示）
function EVAL_QC_NEED_ITEM(id)
  local a = qcAllTbl()
  local raw = (type(a) == "table" and type(a.ow) == "table") and a.ow[id] or nil
  if type(raw) == "string" and raw ~= "" then
    local p = qcBulkSplit(raw)
    return { id = id, n = p[1] or "", q = tonumber(p[2]) or 1 }
  end
  local it = EVAL_QC_BULK_ITEM(id)
  if it then return it end
  return EVAL_QC_ALL_ITEM(id)
end

-- 某个任务的**需求材料**（**全部**）→ { {id=, need=}, … }；没有 ⇒ nil（诚实）
function EVAL_QC_NEED_LIST(qid)
  local e = qcNeedIndex()[qid]
  if not e then return nil end
  local out = {}
  for i = 1, table.getn(e.ids) do
    out[i] = { id = e.ids[i], need = e.needs[i] or 0 }
  end
  return out
end

-- 某个任务的**需求材料 id**（列表行图标带用）：最多 max 件 + 总数
function EVAL_QC_QUEST_NEEDS(id, max)
  local e = qcNeedIndex()[id]
  if not e then return {}, 0 end
  local total = table.getn(e.ids)
  local m = tonumber(max) or total
  if m < 1 then m = 0 end
  local out = {}
  for i = 1, total do
    if i > m then break end
    out[i] = e.ids[i]
  end
  return out, total
end

-- **任务线**的需求材料 = 各步骤的并集（同一材料取**最大**需求数量）；id 去重保序
function EVAL_QC_CHAIN_NEED_LIST(key)
  local d = EVAL_QC_DETAIL(key)
  if type(d) ~= "table" then return nil end
  local idx, out = qcNeedIndex(), {}
  local seen = {}
  for i = 1, table.getn(d.steps or {}) do
    local qid = d.steps[i].id
    local e = qid and idx[qid]
    if e then
      for k = 1, table.getn(e.ids) do
        local iid, cnt = e.ids[k], e.needs[k] or 0
        if seen[iid] then
          if cnt > (seen[iid].need or 0) then seen[iid].need = cnt end
        else
          local rec = { id = iid, need = cnt }
          seen[iid] = rec
          out[table.getn(out) + 1] = rec
        end
      end
    end
  end
  if table.getn(out) == 0 then return nil end
  return out
end

function EVAL_QC_CHAIN_NEEDS(key, max)
  local list = EVAL_QC_CHAIN_NEED_LIST(key)
  local total = table.getn(list or {})
  local m = tonumber(max) or total
  if m < 1 then m = 0 end
  local out = {}
  for i = 1, total do
    if i > m then break end
    out[i] = list[i].id
  end
  return out, total
end

-- ★1.75.14 地域候选清单（筛选菜单的**唯一来源**，一律由数据现算 —— 绝不写死地名表）：
--   来源 = 全量任务行的 `z` + 策展链 `z` + 自报系列 `z`；返回 { {z=地名, n=条目数}, ... }。
--   排序 = 条目数降序 → 名字升序；**空地区永远排最后**。结果缓存（生成物运行期不变）。
--   ★真机数据实测（**三处并集**：全量任务表 88 + 自报系列表 87 + 策展链 56，去重后 = **106 个来源**；
--     下拉实际条目 = 106 + 4 个组标题 + 1 个「全部」清空行 = **111 项**）。
--     ★上次只扫了任务表（88）⇒ 低估了 18 个名字（`职业任务`/`季节性`/`新年`/`暴风城监狱`/复合路线名等），
--     它们当时全落到默认的「世界区域」里 —— 教训：**统计要给三个来源取并集**，少一张表就会误分类。
--   ★★本函数**必须声明在 `local qcBulk` 之后**（bulk 段）：`qcBulk` 是文件局部，写在它之前会绑成
--     全局 nil ⇒ 真机红字 attempt to call a nil value（本项目头号铁律「local 声明顺序 = 词法作用域」）。
local qcZoneCache = nil
-- ★1.75.14 全量清单（无参、缓存一次）—— 只在文件内部用；对外一律走下面的 EVAL_QC_ZONE_LIST(lo,hi)
local function qcZoneAll()
  if qcZoneCache then return qcZoneCache end
  local cnt, order, zlo, zhi = {}, {}, {}, {}
  -- ★1.75.14 用户要求「**标题后添加等级区间，并按等级区间排序**」⇒ 每个来源额外收一份 lo/hi：
  --   来源 = 我们自己数据里所有带该来源的记录的等级（任务表给单个 `lv`；系列/策展链给它自己的 `lo..hi`）
  --   ⇒ 三个来源取并集后求 min/max。★这是「**本库内容在该来源覆盖的等级**」，**不是**官方地区等级区间
  --     （本库以「带装备奖励的任务 + 自报系列」为主，低等级无奖励任务不计入 ⇒ 低端可能偏高，如实告知）。
  local function add(z, lo, hi)
    local k = tostring(z or "")
    if cnt[k] == nil then cnt[k] = 0 order[table.getn(order) + 1] = k end
    cnt[k] = cnt[k] + 1
    local a, bb = tonumber(lo), tonumber(hi)
    if a then if zlo[k] == nil or a < zlo[k] then zlo[k] = a end end
    if bb then if zhi[k] == nil or bb > zhi[k] then zhi[k] = bb end end
    if bb == nil and a then if zhi[k] == nil or a > zhi[k] then zhi[k] = a end end
  end
  local b = qcBulk()
  if type(b) == "table" and type(b.q) == "table" then
    for id in pairs(b.q) do
      local q = EVAL_QC_BULK_QUEST(id)
      if q then add(q.z, q.lv, q.lv) end
    end
  end
  local list = qcChainList()
  if type(list) == "table" then
    for i = 1, table.getn(list) do add(list[i].z, list[i].lo, list[i].hi) end
  end
  local ser = (type(EVAL_QC_SERIES_LIST) == "function") and EVAL_QC_SERIES_LIST() or nil
  if type(ser) == "table" then
    for i = 1, table.getn(ser) do add(ser[i].z, ser[i].lo, ser[i].hi) end
  end
  local out = {}
  for i = 1, table.getn(order) do
    local k = order[i]
    out[i] = { z = k, n = cnt[k], lo = zlo[k], hi = zhi[k] }
  end
  table.sort(out, function(a, c)
    -- ① 空来源（未标注「」）永远排最后
    local ae, ce = (a.z == ""), (c.z == "")
    if ae ~= ce then return ce end
    -- ② ★按**等级区间**排序（1.75.14 用户要求）：先最低等级 → 再最高等级；缺等级的排最后
    local alo = tonumber(a.lo) or 999
    local clo = tonumber(c.lo) or 999
    if alo ~= clo then return alo < clo end
    local ahi = tonumber(a.hi) or 999
    local chi = tonumber(c.hi) or 999
    if ahi ~= chi then return ahi < chi end
    -- ③ 同档再按条目数降序 → 名字升序（保证稳定，table.sort 在 5.1 不稳定）
    if a.n ~= c.n then return a.n > c.n end
    return a.z < c.z
  end)
  qcZoneCache = out
  return out
end

-- ★1.75.14 等级档**多选**的唯一判定口（数据层；界面、装备列表、任务线列表共用这三个）：
--   ① EVAL_QC_LV_RANGES(a, b)：把「档数组 { {lo,hi},… }」或「loMin, loMax 两个数」归一成标准档数组；
--      nil / 空数 / 空表 = **不限等级**（「一个都没勾」= 全部，与种类/来源多选同一套语义）。
--   ② EVAL_QC_LV_IN(ranges, lv)：单个等级是否落在**任一**档内（装备按来源任务等级判）。
--   ③ EVAL_QC_LV_OVER(ranges, lo, hi)：区间是否与**任一**档重叠（任务线按自身 lo..hi 判，与单档同口径）。
function EVAL_QC_LV_RANGES(a, b)
  if type(a) == "table" then
    local out = {}
    for i = 1, table.getn(a) do
      local r = a[i]
      if type(r) == "table" and tonumber(r.lo) then
        out[table.getn(out) + 1] = { lo = tonumber(r.lo), hi = tonumber(r.hi) or 999 }
      end
    end
    if table.getn(out) == 0 then return nil end
    return out
  end
  local lo = tonumber(a)
  if not lo then return nil end
  return { { lo = lo, hi = tonumber(b) or 999 } }
end

function EVAL_QC_LV_IN(ranges, lv)
  if type(ranges) ~= "table" then return true end
  local v = tonumber(lv)
  if not v then return false end          -- 查不到等级：有档在筛就不放行（否则等于「不限」，与用户预期相反）
  for i = 1, table.getn(ranges) do
    local r = ranges[i]
    if v >= (r.lo or 0) and v <= (r.hi or 999) then return true end
  end
  return false
end

function EVAL_QC_LV_OVER(ranges, lo, hi)
  if type(ranges) ~= "table" then return true end
  local a = tonumber(lo) or 0
  local b = tonumber(hi) or a
  for i = 1, table.getn(ranges) do
    local r = ranges[i]
    if b >= (r.lo or 0) and a <= (r.hi or 999) then return true end
  end
  return false
end

-- ★1.75.14 对外入口（可按**等级档**过滤）—— 用户要求：「来源根据等级的多选项，**动态调整过滤项**」。
--   判据 = **区间重叠**（与任务线等级过滤同一口径）：来源自己的 [lo,hi] 与所选档相交才留在菜单里。
--   ★为什么不用「lo 落在档内」：跨档来源（如 30-60）在「40-49」档会整条消失 ⇒ 按等级找来源就找不到。
--   ★缺等级的来源（未标注/其它等）只在「等级: 全部」时出现（它们没有等级可比，不硬塞进任何档）。
--   ★1.75.14 等级改**多选**后，入参可以是「档数组」（EVAL_QC_LV_RANGES 归一），也兼容旧的 (loMin, loMax)。
function EVAL_QC_ZONE_LIST(loMin, loMax)
  local all = qcZoneAll()
  local ranges = EVAL_QC_LV_RANGES(loMin, loMax)
  if not ranges then return all end
  local out = {}
  for i = 1, table.getn(all) do
    local e = all[i]
    local elo = tonumber(e.lo)
    if elo and EVAL_QC_LV_OVER(ranges, elo, tonumber(e.hi) or elo) then
      out[table.getn(out) + 1] = e
    end
  end
  return out
end

-- ★1.75.14 来源下拉的**三分类**（用户要求：「下拉数据整理分类: 职业&制造&节日任务, 世界区域, 副本区域」）：
--   判据 = **点名表**（与 `QC_SLOT_KIND` 同一做法）——只列需要点名的两类，其余一律进**世界区域**。
--   ★这样新采集到的世界区域**自动归位**，不必维护一份 88 条的全量表（那份表一更新就漂移）。
--   ★「其它」= 站点把非地名写进了地区字段的兜底组（真机实测：`传说`×5 · `史诗`×1 是**档位**串；
--     空串 = 3 条任务没写地区）——**不硬塞进那三类**（塞进去就是骗人），菜单里单独一组如实呈现。
--   ★`奥特兰克山谷`（战场）归**副本区域**：同为实例化内容（`奥特兰克山脉`是野外，归世界区域）。
--   ★`暗月马戏团`（世界事件）归第一组：它不是固定区域而是**节日/活动**来源，与职业/制造同类「非地点」。
--   ★带「预留」注释的名字 = 本版数据里还没有（离线校验脚本会标成「点名但数据里没有」，那是**故意的**）：
--     将来采集到就自动归位，不用再改代码。
local QC_ZONE_JOB = {
  -- 职业
  ["战士"] = 1, ["盗贼"] = 1, ["法师"] = 1, ["术士"] = 1, ["圣骑士"] = 1, ["德鲁伊"] = 1,
  ["猎人"] = 1, ["牧师"] = 1, ["萨满祭司"] = 1,
  -- 制造/采集专业（真机数据里现有 3 个；其余为**预留**）
  ["钓鱼"] = 1, ["裁缝"] = 1, ["烹饪"] = 1,
  ["炼金术"] = 1, ["锻造"] = 1, ["附魔"] = 1, ["工程学"] = 1, ["制皮"] = 1, ["急救"] = 1,
  -- 节日/活动（真机数据里现有 `暗月马戏团`；其余为**预留**）
  ["暗月马戏团"] = 1, ["春节"] = 1, ["情人节"] = 1, ["儿童周"] = 1, ["仲夏火焰节"] = 1,
  ["收获节"] = 1, ["万圣节"] = 1, ["冬幕节"] = 1,
  -- ★真实数据并集（106 项来源）里，这几个**内容类** token 也归这一组（不是地名）：
  ["职业任务"] = 1, ["季节性"] = 1, ["新年"] = 1,
}
local QC_ZONE_DUNGEON = {
  ["祖尔格拉布"] = 1, ["安其拉"] = 1, ["安其拉废墟"] = 1, ["纳克萨玛斯"] = 1, ["黑翼之巢"] = 1,
  -- ★`熔火之心`= **预留项**：本版数据里还没有任何任务写它（离线校验脚本会把它标成「点名但数据里没有」，
  --   那是**故意的**）——将来采集到就自动归到副本区域，不用再改代码。
  ["奥妮克希亚的巢穴"] = 1, ["熔火之心"] = 1, ["厄运之槌"] = 1, ["黑石深渊"] = 1, ["黑石塔"] = 1,
  ["斯坦索姆"] = 1, ["通灵学院"] = 1, ["血色修道院"] = 1, ["沉没的神庙"] = 1, ["玛拉顿"] = 1,
  ["奥达曼"] = 1, ["诺莫瑞根"] = 1, ["死亡矿井"] = 1, ["监狱"] = 1, ["黑暗深渊"] = 1,
  ["哀嚎洞穴"] = 1, ["剃刀沼泽"] = 1, ["剃刀高地"] = 1, ["祖尔法拉克"] = 1, ["影牙城堡"] = 1,
  ["怒焰裂谷"] = 1, ["奥特兰克山谷"] = 1,
  -- ★真实数据里还有这几个：`暴风城监狱`（与上面的 `监狱` 是**两个不同 token**，都出现过）·
  --   `阿拉希盆地`（战场，与奥特兰克山谷同族）· 两条**复合路线名**（内容就是副本，归这类看得更准）
  ["暴风城监狱"] = 1, ["阿拉希盆地"] = 1, ["灰谷 · 黑暗深渊"] = 1, ["西部荒野 → 死亡矿井"] = 1,
}
local QC_ZONE_OTHER = { ["传说"] = 1, ["史诗"] = 1 }

-- 单个地区 → 组名：job / world / dungeon / other（未点名的**一律 world**）
function EVAL_QC_ZONE_GROUP(z)
  local k = tostring(z or "")
  if k == "" then return "other" end
  if QC_ZONE_JOB[k] then return "job" end
  if QC_ZONE_DUNGEON[k] then return "dungeon" end
  if QC_ZONE_OTHER[k] then return "other" end
  return "world"
end

-- 分组清单（菜单用）：四个数组，**组内顺序 = EVAL_QC_ZONE_LIST 的既有顺序**（等级区间 → 条目数 → 名字）
-- ★1.75.14 数组元素是**条目表** `{z=来源, n=条目数, lo=最低等级, hi=最高等级}`（不再是裸字符串）——
--   菜单要在标题后显示等级区间，界面上必须拿得到 lo/hi。
-- ★1.75.14 支持**等级档过滤**：loMin/loMax 由界面传入（菜单随等级动态收窄），口径见 EVAL_QC_ZONE_LIST。
function EVAL_QC_ZONE_GROUPS(loMin, loMax)
  local job, world, dun, other = {}, {}, {}, {}
  local list = EVAL_QC_ZONE_LIST(loMin, loMax)
  for i = 1, table.getn(list) do
    local e = list[i]
    local g = EVAL_QC_ZONE_GROUP(e.z)
    if g == "job" then job[table.getn(job) + 1] = e
    elseif g == "dungeon" then dun[table.getn(dun) + 1] = e
    elseif g == "other" then other[table.getn(other) + 1] = e
    else world[table.getn(world) + 1] = e end
  end
  return job, world, dun, other
end

-- 全量物品行 → { id, n, q, ilvl, dps, sp, s, k, st, icon, eq }（字段名与策展物品表一致，便于共用判定）
function EVAL_QC_BULK_ITEM(id)
  local b = qcBulk()
  if type(b) ~= "table" or type(b.i) ~= "table" then return nil end
  local raw = b.i[id]
  if type(raw) ~= "string" then return nil end
  qcBI = qcBI or {}
  local hit = qcBI[id]
  if hit then return hit end
  local p = qcBulkSplit(raw)
  local rec = {
    id = id, n = p[1] or "", q = tonumber(p[2]) or 1, ilvl = tonumber(p[3]) or 0,
    dps = tonumber(p[4]) or 0, sp = tonumber(p[5]) or 0, s = p[6] or "", k = p[7] or "",
    st = p[8] or "", icon = p[9] or "", eq = (p[10] == "1"),
  }
  qcBI[id] = rec
  return rec
end

-- ★1.75.15 **策展链 ↔ 自报系列去重**：同一条任务线在列表里只能出一行。
--   策展条目信息更全（人工档位 / 点评 / 奖励逐条核对）⇒ 系列若已被策展代表就别再出。
--   ★阈值取「步骤重合 ≥60%」而不是「全等」：build.js 抓失败的步骤会让策展 qs 变短，
--     全等判据会把它当成「没覆盖」→ 列表里又冒出同名第二行。
local QC_SERIES_DUP = 0.6
-- 名字归一：剥掉「（联盟）/（部落）」这类后缀再比 —— 用户看到的是「同名两行」，跟步骤号无关
local function qcBaseName(s)
  return (string.gsub(tostring(s or ""), "（[^）]*）$", ""))
end
local qcCurStepSet, qcCurNameSet = nil, nil
local function qcCuratedIndex()
  if qcCurStepSet and qcCurNameSet then return qcCurStepSet, qcCurNameSet end
  local set, names = {}, {}
  local list = qcChainList()
  if type(list) == "table" then
    for i = 1, table.getn(list) do
      local c = list[i]
      local qs = c.qs or {}
      for k = 1, table.getn(qs) do set[qs[k]] = true end
      if tostring(c.n or "") ~= "" then names[qcBaseName(c.n)] = true end
    end
  end
  qcCurStepSet, qcCurNameSet = set, names
  return set, names
end
local function qcSeriesCovered(steps, name)
  local set, names = qcCuratedIndex()
  -- ① **同名即覆盖**：策展那条信息更全（人工档位/点评/奖励核对），同名的系列不再单独出一行
  if tostring(name or "") ~= "" and names[qcBaseName(name)] then return true end
  -- ② 步骤重合 ≥60%（防「改名但同一条线」；阈值不取 100% 是因为抓失败的步骤会让策展 qs 变短）
  local n = table.getn(steps or {})
  if n == 0 then return false end
  local hit = 0
  for i = 1, n do if set[steps[i].id] then hit = hit + 1 end end
  return (hit / n) >= QC_SERIES_DUP
end

-- 自动任务线（站点「本系列第 N/M 部分」拼出）→ 数组 { n, lo, hi, z, t, open, steps={ {id,n} } }
function EVAL_QC_SERIES_LIST()
  local b = qcBulk()
  if type(b) ~= "table" or type(b.s) ~= "table" then return {} end
  if qcBS then return qcBS end
  local out = {}
  for i = 1, table.getn(b.s) do
    local raw = b.s[i]
    if type(raw) == "string" then
      local p = qcBulkSplit(raw)
      local steps = {}
      if type(p[7]) == "string" and p[7] ~= "" then
        for w in string.gmatch(p[7] .. ",", "([^,]+)") do
          local qid = tonumber(w)
          if qid then
            local q = EVAL_QC_BULK_QUEST(qid)
            local nm = (q and q.n) or (type(b.sn) == "table" and b.sn[qid]) or ("#" .. tostring(qid))
            steps[table.getn(steps) + 1] = { id = qid, n = nm, lv = (q and q.lv) or 0 }
          end
        end
      end
      if table.getn(steps) >= 2 and not qcSeriesCovered(steps, p[1]) then
        local sids = {}
        for k = 1, table.getn(steps) do sids[k] = steps[k].id end
        out[table.getn(out) + 1] = {
          n = p[1] or "", lo = tonumber(p[2]) or 0, hi = tonumber(p[3]) or 0, z = p[4] or "",
          t = p[5] or "B", open = (p[6] == "1"), steps = steps, qs = sids,
        }
      end
    end
  end
  -- ★排序（1.75.10 用户要求「任务线也按等级排序」）：**等级 → 稀有度 → 原序**
  --   （旧口径「开门/史诗优先 → 档位 → 等级」是上一轮的要求，已被本轮明确反转）
  local dec = {}
  for i = 1, table.getn(out) do
    local rar = EVAL_QC_RARITY(out[i])
    dec[i] = { s = out[i], r = QC_RAR_W[rar] or 9, lo = out[i].lo, n = i }
  end
  table.sort(dec, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.r ~= b.r then return a.r < b.r end
    return a.n < b.n
  end)
  local sorted = {}
  for i = 1, table.getn(dec) do sorted[i] = dec[i].s end
  qcBS = sorted
  return sorted
end

function EVAL_QC_SERIES_COUNT() return table.getn(EVAL_QC_SERIES_LIST()) end

-- 物品 → 来源任务（全量）；查不到如实 nil（与「策展链」是两件事，详情里分别显示）
function EVAL_QC_BULK_SOURCES(itemId)
  local b = qcBulk()
  if type(b) ~= "table" or type(b.q) ~= "table" then return nil end
  if not qcBIdx then
    qcBIdx = {}
    for id, raw in pairs(b.q) do
      local q = EVAL_QC_BULK_QUEST(id)
      if q then
        for k = 1, table.getn(q.rw) do
          local it = q.rw[k]
          local arr = qcBIdx[it]
          if not arr then arr = {} qcBIdx[it] = arr end
          arr[table.getn(arr) + 1] = q
        end
      end
    end
  end
  local arr = qcBIdx[itemId]
  if not arr or table.getn(arr) == 0 then return nil end
  -- 同等级升序 → 任务 id（稳定，不随 pairs 遍历顺序变）
  local dec = {}
  for i = 1, table.getn(arr) do dec[i] = { q = arr[i], lv = arr[i].lv, id = arr[i].id } end
  table.sort(dec, function(a, b)
    if a.lv ~= b.lv then return a.lv < b.lv end
    return a.id < b.id
  end)
  local out = {}
  for i = 1, table.getn(dec) do out[i] = dec[i].q end
  return out
end

-- 全量装备行（装备视图的**真身**）：每行 = 一件装备 + 它的来源任务（+ 若在策展链里则带链）
-- filter（可选）= { loMin, loMax, lvRanges={ {lo,hi},… }, faction="A"/"H"/"ALL", kinds={[种类]=true}, zones={[地区]=true}, weaponOnly }
--   faction：任务行的标签是 A/H/空（空 = 站点没标阵营 ⇒ **不作为限定**，永远放行 —— 宁可多显示不误杀）
function EVAL_QC_BULK_ITEM_ROWS(filter)
  local b = qcBulk()
  if type(b) ~= "table" or type(b.q) ~= "table" then return {} end
  local f = filter or {}
  local byItem, order = {}, {}
  for id, raw in pairs(b.q) do
    local q = EVAL_QC_BULK_QUEST(id)
    if q then
      -- ★1.75.14 等级**多选**：f.lvRanges（档数组）优先；没有才退回旧的 loMin/loMax 单档。
      local lvOK = true
      if f.lvRanges then
        lvOK = EVAL_QC_LV_IN(f.lvRanges, q.lv)
      elseif f.loMin and (q.lv < f.loMin or q.lv > (f.loMax or 999)) then
        lvOK = false
      end
      local facOK = true
      if f.faction and f.faction ~= "ALL" and q.f ~= "" and q.f ~= f.faction then facOK = false end
      -- ★1.75.14 地域先按**任务级**筛：一件装备可能有多条来源任务 ⇒ 只要有一条任务的地区被勾中，
      --   这件装备就留下（与「来源任务」那几行是同一个口径，不会出现「留下的行看不到任何被选地区」）。
      local zOK = EVAL_QC_ZONE_PASS(f.zones, q.z)
      if lvOK and facOK and zOK then
        for k = 1, table.getn(q.rw) do
          local iid = q.rw[k]
          local it = EVAL_QC_BULK_ITEM(iid)
          if it and it.eq then
            if EVAL_QC_KIND_PASS(f.kinds, EVAL_QC_ITEM_KIND(it))
               and not (f.weaponOnly and not EVAL_QC_IS_WEAPON(it)) then
              local e = byItem[iid]
              if not e then
                e = { id = iid, it = it, chains = EVAL_QC_ITEM_CHAINS(iid) or {}, quests = {}, lo = q.lv }
                byItem[iid] = e
                order[table.getn(order) + 1] = iid
              end
              e.quests[table.getn(e.quests) + 1] = q
              if q.lv < e.lo then e.lo = q.lv end
            end
          end
        end
      end
    end
  end
  local dec = {}
  for n = 1, table.getn(order) do
    local e = byItem[order[n]]
    -- 来源任务按等级升序（同一件装备可能多条任务给）
    local qd = {}
    for i = 1, table.getn(e.quests) do qd[i] = { q = e.quests[i], lv = e.quests[i].lv, id = e.quests[i].id } end
    table.sort(qd, function(a, c)
      if a.lv ~= c.lv then return a.lv < c.lv end
      return a.id < c.id
    end)
    local qs = {}
    for i = 1, table.getn(qd) do qs[i] = qd[i].q end
    e.quests = qs
    -- ★1.75.14 用户要求「装备列表单元添加地域信息」：来源任务的地区**去重**收集（顺序 = 任务等级序，
    --   上面刚排好）⇒ 列表单元格取「首个（必是等级最低那条任务的地区）(+N)」，详情页可列全。
    --   ★空串也进数组（显示成「（无地区）」）—— 如实呈现，不假装它没有来源。
    local zs, zseen = {}, {}
    for i = 1, table.getn(qs) do
      local z = tostring(qs[i].z or "")
      if not zseen[z] then zseen[z] = true zs[table.getn(zs) + 1] = z end
    end
    e.zones = zs
    dec[n] = {
      e = e,
      w = EVAL_QC_IS_WEAPON(e.it) and 0 or 1,
      q = -(tonumber(e.it.q) or 0),
      il = -(tonumber(e.it.ilvl) or 0),
      lo = e.lo,
      n = n,
    }
  end
  table.sort(dec, function(a, c)
    if a.lo ~= c.lo then return a.lo < c.lo end
    if a.w ~= c.w then return a.w < c.w end
    if a.q ~= c.q then return a.q < c.q end
    if a.il ~= c.il then return a.il < c.il end
    return a.n < c.n
  end)
  local out = {}
  for n = 1, table.getn(dec) do out[n] = dec[n].e end
  return out
end


-- ★1.75.14 **任务检索**（用户定案「C 执行」= 全量任务进包）：
--   覆盖**全量表里的每个任务**（不只是「不在任何线里」的那些）—— 因为站点会把某些任务编进
--   与它地区不同的线（真机实例：`狂热之心`（血色修道院）属「蝙蝠的粪便」（剃刀沼泽）；
--   `知识试炼`（血色修道院）属「信仰的试炼」（千针石林））⇒ 只列「单体任务」会漏掉它们。
--   每条记 `inSeries`（是否属于某条任务线），界面据此标注「单体 / 属任务线」。
--   filter = { lvRanges={ {lo,hi},… }, zones={[地区]=true}, faction="A"/"H"/"ALL" }；query 匹配**任务名或地区**。
--   ★口径与装备视图一致：阵营为空的任务**永远放行**（站点没标 ⇒ 不作限定）；等级按档数组；地区按集合。
--   返回 { {id,n,lv,z,f,gear,tags,inSeries}, … }（按 等级 → 名字 排序，截断到 cap，默认 300）。
local qcSeriesSet = nil
local function qcInSeriesSet()
  if qcSeriesSet then return qcSeriesSet end
  local set = {}
  local b = qcBulk()
  if type(b) == "table" and type(b.s) == "table" then
    for i = 1, table.getn(b.s) do
      local raw = b.s[i]
      if type(raw) == "string" then
        local p = qcBulkSplit(raw)
        for w in string.gmatch((p[7] or "") .. ",", "([^,]+)") do
          local id = tonumber(w)
          if id then set[id] = true end
        end
      end
    end
  end
  local list = qcChainList()
  if type(list) == "table" then
    for i = 1, table.getn(list) do
      local qs = list[i].qs or {}
      for k = 1, table.getn(qs) do set[qs[k]] = true end
    end
  end
  qcSeriesSet = set
  return set
end

--   ★1.75.21 `f.exclude`（任务 id 集合）= **已并入本次结果里的任务线行**的步骤 ⇒ 不再单独出行。
--     返回第三个值 = 被并掉的条数（界面拿它如实说明「已并入 N 条线内步骤」）。
function EVAL_QC_QUEST_LIST(query, filter, cap)
  local a = qcAllTbl()
  if type(a) ~= "table" or type(a.q) ~= "table" then return {} end
  local f = filter or {}
  local max = tonumber(cap) or 300
  if max <= 0 then max = math.huge end
  local q = string.lower(tostring(query or ""))
  local inSeries = qcInSeriesSet()
  local exclude, merged = f.exclude, 0
  local out = {}
  for id in pairs(a.q) do
    local r = EVAL_QC_ALL_QUEST(id)
    if r then
      local ok = true
      if f.lvRanges and not EVAL_QC_LV_IN(f.lvRanges, r.lv) then ok = false end
      if ok and f.faction and f.faction ~= "ALL" and r.f ~= "" and r.f ~= f.faction then ok = false end
      if ok and not EVAL_QC_ZONE_PASS(f.zones, r.z) then ok = false end
      if ok and q ~= "" then
        local hit = (string.find(string.lower(r.n), q, 1, true) ~= nil)
          or (string.find(string.lower(r.z), q, 1, true) ~= nil)
        if not hit then ok = false end
      end
      -- ★★并入判据：**只对「本次真的过滤通过」的那条**计数 —— 先判是否已出锅，再决定并还是留
      if ok and exclude and exclude[id] then ok = false merged = merged + 1 end
      if ok then
        r.inSeries = inSeries[id] and true or false   -- 供界面标注（同一份缓存记录，值恒定）
        out[table.getn(out) + 1] = r
      end
    end
  end
  table.sort(out, function(x, y)
    local xl, yl = tonumber(x.lv) or 0, tonumber(y.lv) or 0
    if xl ~= yl then return xl < yl end
    if x.n ~= y.n then return x.n < y.n end
    return x.id < y.id
  end)
  local res = {}
  for i = 1, table.getn(out) do
    if i > max then break end
    res[i] = out[i]
  end
  return res, table.getn(out), merged
end