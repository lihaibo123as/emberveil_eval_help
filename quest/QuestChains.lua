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
  local function lvOK(c)
    if not lvLo then return true end
    local lo = tonumber(c and c.lo) or 0
    local hi = tonumber(c and c.hi) or lo
    return (hi >= lvLo) and (lo <= (lvHi or 999))
  end
  -- ★1.75.18 用户要求「任务线->档位过滤使用装备那边的种类过滤」：种类档也落在数据层，
  --   与装备视图**共用同一份多选集合**（空集 = 不过滤）。判据 = 这条线的**奖励里有没有**勾选的种类。
  local kinds = (filter or {}).kinds
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
    if hit and lvOK(c) and qcRecKindsOK(c, kinds) then
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
        if qcRecKindsOK(rec, kinds) then
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
    steps[i] = { n = i, id = s.steps[i].id, q = q }
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
    local nm = (s.q and s.q.n) or ("#" .. tostring(s.id))
    local lv = (s.q and s.q.lv) and ("(" .. tostring(s.q.lv) .. ")") or ""
    table.insert(out, { text = string.format("%d. %s%s", s.n, nm, lv), kind = "step", id = s.id })
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

-- ============================================================================
-- 全量数据层（1.75.9 · QuestBulk.lua）：10-60+ 级**所有**带装备奖励的任务
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
-- filter（可选）= { loMin, loMax, faction="A"/"H"/"ALL", kinds={[种类]=true}, weaponOnly }
--   faction：任务行的标签是 A/H/空（空 = 站点没标阵营 ⇒ **不作为限定**，永远放行 —— 宁可多显示不误杀）
function EVAL_QC_BULK_ITEM_ROWS(filter)
  local b = qcBulk()
  if type(b) ~= "table" or type(b.q) ~= "table" then return {} end
  local f = filter or {}
  local byItem, order = {}, {}
  for id, raw in pairs(b.q) do
    local q = EVAL_QC_BULK_QUEST(id)
    if q then
      local lvOK = true
      if f.loMin and (q.lv < f.loMin or q.lv > (f.loMax or 999)) then lvOK = false end
      local facOK = true
      if f.faction and f.faction ~= "ALL" and q.f ~= "" and q.f ~= f.faction then facOK = false end
      if lvOK and facOK then
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
