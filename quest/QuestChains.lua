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

-- ===== 列表：按「档位 → 等级 → 原序」排序；可按阵营/档位筛选 =====
-- filter = { faction = "A"/"H"/"B"/nil, tier = "S"/"A"/"B"/nil }
-- 排序用「装饰（权重, 等级, 原序号）」—— table.sort 在 Lua 5.1 不稳定（项目铁律）
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
      table.insert(out, { c = c, w = QC_TIER_W[c.t] or 9, lo = tonumber(c.lo) or 99, i = i })
    end
  end
  table.sort(out, function(a, b)
    if a.w ~= b.w then return a.w < b.w end
    if a.lo ~= b.lo then return a.lo < b.lo end
    return a.i < b.i
  end)
  local res = {}
  for i = 1, table.getn(out) do res[i] = out[i].c end
  return res
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
function EVAL_QC_SEARCH(query, cap, filter)
  if type(qcChainList()) ~= "table" then return nil, "NO_DATA" end
  local q = query
  if type(q) ~= "string" then q = "" end
  q = string.lower(q)
  local max = tonumber(cap) or 30
  local out, extra = {}, 0
  local lc = function(s) return string.lower(tostring(s or "")) end
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
    if hit then
      if table.getn(out) < max then
        table.insert(out, { idx = i, c = c, kind = hit.kind, id = hit.id, name = hit.name, sub = c.z })
      else
        extra = extra + 1
      end
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
      if hit then
        if table.getn(out) < max then
          table.insert(out, {
            idx = i, kind = "series", key = "s:" .. tostring(i), id = hit.id, name = hit.name,
            c = { k = "s:" .. tostring(i), n = s.n, t = s.t, z = s.z, lo = s.lo, hi = s.hi,
                  f = EVAL_QC_SERIES_FACTION(s), note = "" },
            sub = s.z,
          })
        else
          extra = extra + 1
        end
      end
    end
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
    c = { k = key, n = s.n, f = EVAL_QC_SERIES_FACTION(s), t = s.t, lo = s.lo, hi = s.hi,
          z = s.z, note = "", open = s.open, auto = true },
    rewards = rw, steps = steps,
  }
end

-- ===== 详情（位次 / 链键 / "s:<位次>" 自动任务线键都可；查不到如实返回 nil） =====
function EVAL_QC_DETAIL(key)
  if type(key) == "string" and string.sub(key, 1, 2) == "s:" then return EVAL_QC_SERIES_DETAIL(key) end
  return qcDetailOf(qcChainAt(key))
end

-- ===== 武器判定（唯一来源）：物品表里有 dps 的即武器 =====
function EVAL_QC_IS_WEAPON(rec)
  if type(rec) ~= "table" then return false end
  local d = tonumber(rec.dps)
  return (d ~= nil and d > 0) and true or false
end

-- ===== 装备种类 / 子类型（1.75.8 用户要求：种类细分、支持子类型多选）=====
-- 种类唯一来源 = 生成数据里物品的 `k`（类型：剑/斧/锤/匕首/法杖/弓/盾牌/布甲/皮甲/锁甲/其它），
-- 部位在 `s`（不与种类混用）；「是不是武器子类型」由 EVAL_QC_IS_WEAPON 判（dps>0），不另立表。
-- ★判据：数据以 https://database.emberveil.org/quests 为准 —— 所以种类清单**必须现算**，
--   数据里没有的种类绝不出现在筛选里（写死一张种类表 = 与数据脱节，下一批数据就漂移）。
function EVAL_QC_ITEM_KIND(rec)
  if type(rec) ~= "table" then return "" end
  if type(rec.k) ~= "string" then return "" end
  return rec.k
end

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

-- 多选集合判定：非表 / 空集 = 不过滤（「一个都没勾」与「全部」同义，符合用户多选预期）
local function qcKindPass(set, k)
  if type(set) ~= "table" then return true end
  local any = false
  for _ in pairs(set) do any = true break end
  if not any then return true end
  return set[k] and true or false
end

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
        if it and qcKindPass(f.kinds, EVAL_QC_ITEM_KIND(it))
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
      if table.getn(steps) >= 2 then
        out[table.getn(out) + 1] = {
          n = p[1] or "", lo = tonumber(p[2]) or 0, hi = tonumber(p[3]) or 0, z = p[4] or "",
          t = p[5] or "B", open = (p[6] == "1"), steps = steps,
        }
      end
    end
  end
  -- 排序：开门/史诗优先 → 档位 → 等级 → 名字（界面直接照这个顺序列）
  local TW = { S = 1, A = 2, B = 3 }
  local dec = {}
  for i = 1, table.getn(out) do
    dec[i] = { s = out[i], w = out[i].open and 0 or 1, t = TW[out[i].t] or 9, lo = out[i].lo, n = i }
  end
  table.sort(dec, function(a, b)
    if a.w ~= b.w then return a.w < b.w end
    if a.t ~= b.t then return a.t < b.t end
    if a.lo ~= b.lo then return a.lo < b.lo end
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
            if qcKindPass(f.kinds, EVAL_QC_ITEM_KIND(it))
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
