-- ★★★0.3.49 三档整理算法（配置可切换 —— 用户：「原来的算法逻辑保留」+「A算法优化也做」+
--   「将不同的算法(A,B)进入配置可切换」）。真值 = `c.sortAlgo`；读口 `B.algoNow()`（EH_Bag.lua）；
--   入口 = 设置菜单「整理算法」那一行（点一下循环）+ `/ebag algo a|b|orig`：
--   · **`orig` = 原算法（基线，逻辑一字未改）**：算期望序 → 从前往后取**第一处不一致**；
--     目标格被占 ⇒ 先 park 到**第一个空格**，下一拍再搬 donor。
--   · **`a` = 原算法骨架 + park 就近放回（默认档）**：走位顺序、判据、donor 选择**全部与 orig 一字不差**，
--     唯一改动 = 目标被占时**优先把占位那件放进它自己的最终位置**（空着的话），找不到才退回第一个空格。
--     ★实测：合计 **1029 → 902 步（−12.3%）**，两段大件（背包+银行）**−25%**，零互换、最终排布逐格一致，
--       **没有一组变差**；仍然是「一拍一对写动作 + 每拍全量重读 + 只进空格/并入同 id」。
--   · **`b` = 环优先（先补空洞）**：在 a/orig 那一趟**之前**，先做一遍「**目标格是空的**」那一类
--     （1 步即成，不必先 park），donor **只许从本身已经错位的堆里取** ——
--     ★★★偷一个**已经摆对**的堆 = 白走两趟（首版漏了这条，实测反而 **+113%** 更慢；补上后 −38%）。
--     ★实测：合计 **1029 → 635 步（−38.3%）**；最终 id 序列**逐格一致**、互换 **0**；
--       「已排好、只错 6 件」那类也吃到参考下界（1.00x）。
--   ★★`b` 是**严格前置的一趟**：这一趟找不到可做的 ⇒ **原样落回** a 那一趟 ⇒ 边界/坏数据只会退化成
--     a/orig，绝不卡住（A/B 两套共享同一套安全口径：每拍最多一对 `PickupContainerItem` · 每步全量重读 · 绝不发互换）。
--   ★A/B 实测记账 = `B.sortStatAdd`（EH_Bag.lua，只记**跑完**的那一轮；读数 = `/ebag algo` 与 `/ebag status`）。
-- ============================================================
-- EH_BagSort —— EH_Bag 的「一键整理」引擎（规则排序 + 限频执行）
--
-- ★★★为什么不能照抄 OneBag/SortBags 的即时整理：
--   它一次 OnUpdate 里对多个目标格发 PickupContainerItem 对（一拍可能十几笔服务器写动作），
--   本项目有硬教训（一帧 24 次 UseContainerItem 被服务器判异常踢线）⇒
--   这里改成**一个节拍只走一步**（一步 = 一对 PickupContainerItem），步进间隔 B.cfg().moveGap
--   （默认 0.45s ≈ 2.2 步/秒）。宁可慢，绝不撞反滥用限流。
--
-- ★★每一步都**重新读客户端真值**（不维护易失真的本地镜像）：
--   上一次移动可能被客户端合并堆叠、也可能被锁定 ⇒ 按「快照 → 期望序 → 取第一处不一致」走路，
--   天然自愈。物品信息按 id 缓存（GetItemInfo 每个 id 只查一次）以免每步 90 次客户端调用。
--
-- ★排序规则（参考 SortBags 的分类意图，规则表自研）：
--   ① 大类：装备 → 消耗品 → 商品/材料 → 任务 → 容器 → 其它
--   ② 同类内：品质降序 → 名称升序 → id 升序
--   ③ 先做一遍**堆叠合并**（同 id 且目标格装得下就并过去），再走排序位次
--
-- ★3 条安全闸门（任一命中即停并如实说明）：
--   战斗中 / 光标上有物品 / 连续 3 步推不动（物品被锁）
--
-- ★★★0.3.41 两条收口（真机报障：「在遇到箭袋,附魔,草药等专属袋子的时候背包整合会卡住死循环」）：
--   ① **工作区只收「被正面证明是普通袋」的容器**（fail-closed；判定口 = `B.bagKind`，实现在 EH_Bag.lua）：
--      特殊袋（箭袋/弹药袋/草药袋/附魔袋/灵魂袋）与**判不出类型**的袋子**整袋不进池子**
--      —— 既不从中搬出、也不往里搬进。理由：特殊袋只收得下自己那一类物品 ⇒ 期望序里
--      「排在前面那件」必须落进特殊袋时**永远落不进去**（= 期望序**不可达**，即使读回 100% 准确
--      也收敛不了）；而本客户端 drop 被拒时**把物品放回原处、光标清空**（unrealUI 在同一客户端
--      实测的形态）⇒ 旧写法只看光标 ⇒ 记成「搬成功」⇒ 下一步算出同一个期望序、搬同一对格子
--      ⇒ **空转到 `SORT_MAX_MOVES`(400) / `SORT_TIMEOUT`(180s) 才收工**（0.2s 一步 ≈ 每秒 10 次
--      服务器写动作，正压在项目铁律的红线上）。口径照参考插件 `unrealUI/core/itemsort.lua` 的
--      分类边界（"Which bags may be sorted"）逐条对齐。
--   ② **无进展闸门**（旧写法只有「物品被锁」那一条，而**静默被拒根本不走它** ⇒ 形同不存在）：
--      每步算一次**工作区状态指纹**，判据 = **这个状态在本轮整理里出现过没有**
--      （只比上一拍抓不到「A→B→A→B…」的来回互搬周期 —— 0.3.40d 银行主格那次正是那个形态）；
--      从「上一次见到新状态」起算满 `SORT_NOPROG_SEC` 秒就记一次无进展，
--      累计 `SORT_NOPROG_MAX` 次即停并如实出声。
--      ★为什么按「秒」而不按「步」：本客户端**容器读回在整理中会滞后**（0.3.9 / 0.3.35 在案，
--      新鲜戳记有效期 1.5s）⇒ 刚落位的那一拍读回可能还是旧的；按步数会**误报**，
--      按秒给足读回时间才能区分「读回还没到」与「这一步真的没发生」。
-- ============================================================

local B = _G.EH_BAG
if type(B) ~= "table" then
  return
end

local L = B.L

-- 大类名 → 位次（唯一来源：等价于 EH_Bag.lua 的 catOf 输出域）
local CAT_RANK = {
  equip = 1, consume = 2, trade = 3, quest = 4, container = 5, other = 6,
}

local SORT_MAX_MOVES = 400
local SORT_TIMEOUT = 180
local SORT_STALL_MAX = 3
-- ★0.3.41 无进展闸门（见文件头 ②）：指纹从上次变化起连续 NOPROG_SEC 秒没动过 ⇒ 记一次无进展；
--   累计 NOPROG_MAX 次即收工（3.0s 是给「容器读回滞后」留的余量 —— 新鲜戳记有效期 1.5s 的两倍）
local SORT_NOPROG_SEC = 3.0
local SORT_NOPROG_MAX = 2
-- ★0.3.35：整理「新鲜戳记」有效期（秒）—— 刚动过的格子在这段时间内不拿滞后的读回盖掉直接画好的内容
B.SORT_FRESH_SEC = 1.5

local idCache = {}

local function itemInfoCached(id)
  if id == nil then return nil end
  local hit = idCache[id]
  if hit ~= nil then return hit end
  local info = { name = "?", quality = 1, itemType = nil, maxStack = 1, equipLoc = nil }
  if type(GetItemInfo) == "function" then
    -- ★0.3.38：第 9 个返回 = 纹理（真机探针实证可读）—— recAt 的记录要带 texture，
    --   否则 paintRec 每一步都是 SetTexture(nil) 清图标 = 用户报的「有数无图标」
    local ok, n, _, q, _, t, sub, maxStack, eqLoc, tex = pcall(GetItemInfo, id)
    if ok then
      if type(n) == "string" and n ~= "" then info.name = n end
      if type(q) == "number" then info.quality = q end
      info.itemType = t
      info.subType = sub
      info.equipLoc = eqLoc
      if type(maxStack) == "number" and maxStack > 0 then info.maxStack = maxStack end
      if type(tex) == "string" and tex ~= "" then info.texture = tex end
    end
  end
  idCache[id] = info
  return info
end

-- 轻量读一格：只要 id/名称/品质/类型/上限（不做图标与 tooltip）
local function recAt(bag, slot)
  -- ★0.3.40 银行主格（用户：「银行背包窗口开的情况下.背包整理顺带也要整理银行背包内的物品」）：
  --   主格 24 格走**装备槽 API**（40..63）；本客户端恒不给链接（0.3.24）⇒ 链接/id 走
  --   唯一反查口 `B.bankMainInfo`（名字 → GetItemInfo，0.3.39/0.3.40 与显示侧共用，带缓存）。
  if bag == B.BANK then
    local inv = 39 + slot
    if type(BankButtonIDToInvSlotID) == "function" then
      local okI, v = pcall(BankButtonIDToInvSlotID, slot)
      if okI and type(v) == "number" and v > 0 then inv = v end
    end
    local link, texture, count
    if type(GetInventoryItemLink) == "function" then
      local okL, l = pcall(GetInventoryItemLink, "player", inv)
      if okL and type(l) == "string" and l ~= "" then link = l end
    end
    if type(GetInventoryItemTexture) == "function" then
      local okT, t2 = pcall(GetInventoryItemTexture, "player", inv)
      if okT and type(t2) == "string" and t2 ~= "" then texture = t2 end
    end
    if type(GetInventoryItemCount) == "function" then
      local okC, c2 = pcall(GetInventoryItemCount, "player", inv)
      if okC and type(c2) == "number" then count = c2 end
    end
    if link == nil and texture == nil then return nil end
    local id = (link ~= nil) and tonumber(string.match(link, "item:(%d+)")) or nil
    local info = (id ~= nil) and itemInfoCached(id) or nil
    if info == nil and type(B.bankMainInfo) == "function" then
      local bi = B.bankMainInfo(inv, texture)
      if type(bi) == "table" then
        if link == nil and type(bi.link) == "string" then
          link = bi.link
          id = tonumber(string.match(link, "item:(%d+)"))
          if id ~= nil then info = itemInfoCached(id) end
        end
        if info == nil then
          info = { name = bi.name or "?", quality = bi.quality or 1,
                   itemType = bi.itemType, subType = bi.subType,
                   maxStack = bi.maxStack or 1, equipLoc = bi.equipLoc, texture = bi.texture }
        end
      end
    end
    if texture == nil and info ~= nil then texture = info.texture end
    return {
      bag = bag, slot = slot, id = id, link = link,
      name = (info and info.name) or "?",
      quality = (info and info.quality) or 1,
      itemType = info and info.itemType or nil,
      equipLoc = info and info.equipLoc or nil,
      maxStack = (info and info.maxStack) or 1,
      count = count or 1,
      locked = false,
      texture = texture,
      bankMain = true,
    }
  end
  if type(GetContainerItemLink) ~= "function" then return nil end
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if not ok or type(link) ~= "string" or link == "" then return nil end
  local id = tonumber(string.match(link, "item:(%d+)"))
  local info = itemInfoCached(id)
  local count, locked, texture
  if type(GetContainerItemInfo) == "function" then
    local ok2, tex2, c, l = pcall(GetContainerItemInfo, bag, slot)
    if ok2 then
      -- ★0.3.38：容器读到的贴图优先；滞后缺了（探针实证会发生）⇒ 用 id 现取的那份补
      if tex2 ~= nil and tex2 ~= "" then texture = tex2 end
      count = c
      locked = l
    end
  end
  if texture == nil and info ~= nil then texture = info.texture end
  return {
    bag = bag, slot = slot, id = id, link = link,
    name = (info and info.name) or "?",
    quality = (info and info.quality) or 1,
    itemType = info and info.itemType or nil,
    equipLoc = info and info.equipLoc or nil,
    maxStack = (info and info.maxStack) or 1,
    count = count or 1,
    locked = locked and true or false,
    texture = texture,
  }
end

local function catRankOf(rec)
  local cat = B.catOf(rec.itemType, rec.equipLoc)
  return CAT_RANK[cat] or CAT_RANK.other
end

-- 排序比较：大类 → 品质降序 → 名称 → id
local function lessRec(a, b)
  local ac = catRankOf(a)
  local bc = catRankOf(b)
  if ac ~= bc then return ac > bc end          -- ★ 大类：位次大的在前

  local aq = a.quality or 0
  local bq = b.quality or 0
  if aq ~= bq then return aq < bq end          -- ★ 品质：低品质在前

  local an = string.lower(a.name or "")
  local bn = string.lower(b.name or "")
  if an ~= bn then return an > bn end          -- ★ 名称：降序

  return (a.id or 0) > (b.id or 0)             -- ★ id：降序
end

-- ★★★0.3.41：袋子分类（fail-closed）—— 只有**被正面证明是普通袋**的容器才进工作区。
--   ★判定口**不在**（载入异常）⇒ 退回旧口径（全收）：那是**载入顺序**问题，不是「判不出袋子」；
--     而 `B.bagKind` 返回 nil（**真的判不出类型**）⇒ **排除**（宁少整理几个包，
--     也绝不在判不出类型的袋子里搬东西 —— 与参考插件同一句话）。
local function generalOnly(bag)
  if type(B.bagKind) ~= "function" then return true end
  return B.bagKind(bag) == "general"
end

local function kindLabelOf(bag)
  if type(B.bagKindLabel) == "function" then return B.bagKindLabel(bag) end
  return L("KIND_UNKNOWN")
end

-- 被排除的容器 → 「背包 1(草药袋) · 银行包 6(判不出)」这种一行播报文本（有界：最多列 6 条，多的写「…」）
local function skipText(skipped)
  local parts = {}
  local i
  for i = 1, table.getn(skipped) do
    if i > 6 then
      parts[table.getn(parts) + 1] = "…"
      break
    end
    local bag = skipped[i].bag
    local nm = (type(B.bagLabel) == "function") and B.bagLabel(bag) or ("#" .. tostring(bag))
    parts[table.getn(parts) + 1] = nm .. "(" .. kindLabelOf(bag) .. ")"
  end
  return table.concat(parts, " · ")
end

-- 位置序：**工作区 = 0~4 号袋的全部物理格子**，显示中的包排前面、收起的排后面。
-- ★★★0.3.7 修（用户：「物品整理在有空格的情况下会提示空位不足」）：旧写法只收「显示中」的包
--   ⇒ 你把某个背包**收起**（里面还有空位）时，容量行按**物理格数**报「空 26」（窗口下方那行），
--   而整理引擎在可见区找不到空格做中转 ⇒ 直接误报「一格空位都没有」。
--   ★口径：**收起只影响看不看得见，不影响这一格能不能用**；只有**物理上一格不空**才是真的没空位。
--   排序仍然优先把东西摆在**看得见的地方**（第 1 趟 = 显示中的包），多出来的才落到收起的包里。
--   ★★★0.3.41：返回**两个**值 —— `slots`（工作区格子）与 `skipped`（被排除的容器 = 特殊袋 +
--     判不出类型的袋子；供上手播报与 `/ebag status` 体检用；**空表 = 一个都没跳过**）。
local function slotOrder(scope)
  -- ★0.3.40 银行工作区（`scope == "bank"`；用户：「顺带也要整理银行背包内的物品」）：
  --   银行包 5~10，全部物理格；★只在银行开着时才有（`B.bankOpen`）。
  --   ★与背包工作区**分两段跑**（sortStep 在背包 done 后换段）—— 绝不跨容器搬（背包 ↔ 银行）。
  if scope == "bank" then
    -- ★★★0.3.40d 死循环收口（真机：「开着银行 整理 卡主死循环了」）——
    --   **银行主格 24 格从工作区拿掉**：本客户端对它们恒不给链接（0.3.24 定案）⇒ 引擎只能
    --   「名字→GetItemInfo」反查，id 时有时无（nil id 互相「相等」⇒ 反复互搬）+ 读回滞后
    --   ⇒ 期望序每步都变 ⇒ **永不收敛 = 死循环**（「未找到指定物品」= 反查失败时客户端喷的错）。
    --   ⇒ 银行段**只整银行包 5~10**（容器 API，与背包同稳定级）；主格 24 格如实跳过、出声说明。
    local slots, skipped = {}, {}
    if B.bankOpen == true then
      local k, s
      for k = 10, 5, -1 do
        if generalOnly(k) then
          local n = B.bagSlotsRaw(k)
          for s = n, 1, -1 do
            table.insert(slots, { bag = k, slot = s })
          end
        else
          -- ★0.3.41：银行包也可能是特殊袋（草药袋/附魔袋是最常见的银行包）⇒ 一起分类
          table.insert(skipped, { bag = k })
        end
      end
    end
    return slots, skipped
  end
  local slots, skipped = {}, {}
  local pass, k, s
  for pass = 1, 2 do
        for k = 5, 1, -1 do    --改动点
      local bag = k - 1
      local shown = B.bagShown(bag)
      -- ★0.3.41：特殊袋/判不出类型的袋子**整袋不进池子**（第 1 趟里记一次被跳过的容器，别重复列）
      if not generalOnly(bag) then
        if pass == 1 then table.insert(skipped, { bag = bag }) end
      elseif (pass == 1 and shown) or (pass == 2 and not shown) then
        local n = B.bagSlotsRaw(bag)
        for s = n, 1, -1 do --改动点
          table.insert(slots, { bag = bag, slot = s })
        end
      end
    end
  end
  return slots, skipped
end

-- ★★★0.3.7 修（同一次报障的第二层）：`list` 是**逐位赋值**的 —— 末尾的空格子写的是 nil
--   ⇒ `table.getn(list)`（5.1 的边界二分）会**短于槽位数**（8 格里末尾 3 格空 ⇒ 只报 5）。
--   旧写法下面那些 `for i = 1, table.getn(list)` 因此**看不到末尾的空格**，找 park 的循环
--   （`park == nil ⇒ return "nofree"`）就在「明明有空格」的情况下误报「一格空位都没有」——
--   用户报的「有空格却提示空位不足」正是这两层叠加出来的。
--   ⇒ 口径统一成**槽位数**（`slots` 由 table.insert 建、连续无洞 ⇒ 它的长度才是真值）。
local function snapshot(slots)
  local list = {}
  local n = table.getn(slots)
  local i
  for i = 1, n do
    list[i] = recAt(slots[i].bag, slots[i].slot)
  end
  return list, n
end

-- ★0.3.41 工作区状态指纹（无进展闸门用）：逐格 `bag:slot=id:count`，空格记 `-`。
--   用途 = 判「这一步到底有没有真的改变背包」——**只看状态，绝不看调用的返回值**
--   （本客户端 drop 被拒时不报错、且光标被清空 ⇒ 返回值那条路不可信）。
--   有界：长度 = 工作区槽位数；每步只算一次。
local function fpOf(slots, list, n)
  local out = {}
  local i
  for i = 1, n do
    local s = slots[i]
    local r = list[i]
    local part = "-"
    if r ~= nil then
      if r.id ~= nil then part = tostring(r.id)
      elseif type(r.link) == "string" then part = r.link end
      part = part .. ":" .. tostring(r.count or 1)
    end
    out[i] = tostring(s.bag) .. ":" .. tostring(s.slot) .. "=" .. part
  end
  return table.concat(out, "|")
end

local function cursorBusy()
  if type(CursorHasItem) ~= "function" then return false end
  local ok, has = pcall(CursorHasItem)
  return (ok and has) and true or false
end

local function inCombat()
  if type(EVAL_HELP_STATE) == "table" and EVAL_HELP_STATE.inCombat ~= nil then
    return EVAL_HELP_STATE.inCombat and true or false
  end
  if type(UnitAffectingCombat) == "function" then
    local ok, v = pcall(UnitAffectingCombat, "player")
    return (ok and v) and true or false
  end
  return false
end

-- 真正动手：唯一的移动出口。
-- ★★★只允许两种移动：① 搬到**空格** ② 整堆并入同 id 且装得下的格子（合并）。
--   **绝不发起「两格互换」**：互换会让一件物品留在光标上，而光标上的东西一旦被我们 ClearCursor
--   就是**丢件**（本模块首版就是这么把两件物品弄没的，harness 的「后 12 格全空」断言当场抓到）。
--   目标被占用时改走「先 park 到空格，下一步再搬」的两步策略（见 oneStep）。
-- ★0.3.40：拿取分派 —— 银行主格走 `PickupInventoryItem(装备槽)`，其余照旧 `PickupContainerItem`
local function pickUp(bag, slot)
  if bag == B.BANK then
    if type(PickupInventoryItem) ~= "function" then return false end
    local inv = 39 + slot
    if type(BankButtonIDToInvSlotID) == "function" then
      local okI, v = pcall(BankButtonIDToInvSlotID, slot)
      if okI and type(v) == "number" and v > 0 then inv = v end
    end
    pcall(PickupInventoryItem, inv)
    return true
  end
  if type(PickupContainerItem) ~= "function" then return false end
  pcall(PickupContainerItem, bag, slot)
  return true
end

local function moveNow(src, dst, allowMerge)
  if type(PickupContainerItem) ~= "function" and type(PickupInventoryItem) ~= "function" then return false, "noapi" end
  local srcRec = recAt(src.bag, src.slot)
  local dstRec = recAt(dst.bag, dst.slot)
  if srcRec == nil then return false, "empty" end
  if srcRec.locked then return false, "locked" end
  if dstRec ~= nil then
    if not allowMerge then return false, "occupied" end
    if dstRec.locked then return false, "locked" end
    if dstRec.id ~= srcRec.id then return false, "occupied" end
    if (srcRec.count or 1) + (dstRec.count or 1) > (srcRec.maxStack or 1) then return false, "toobig" end
  end
  if not pickUp(src.bag, src.slot) then return false, "noapi" end
  pickUp(dst.bag, dst.slot)
  -- ★真机上「搬进空格」与「整堆合并」都不该留下光标物品；留下了 = 我们对客户端语义的假设不成立
  --   ⇒ **绝不清光标**（清 = 丢件），而是如实上报让上层收工，把东西留给玩家自己放。
  if cursorBusy() then return true, "cursor" end
  return true
end

-- 找一个「同 id 且装得下」的合并对（先合并再排位；与 SortBags 的 Stack() 同意图）
-- ★返回 (源, 目标)：源 = 要被并走的那一堆，目标 = 装得下的那一堆 —— 方向反了就会越并越乱
-- ★★★0.3.7：`n` = **槽位数**（不是 `table.getn(list)` —— 末尾空格子是 nil，那个会短算）
local function findMerge(list, n)
  local i, j
  if n == nil then n = table.getn(list) end
  for i = 1, n do
    local a = list[i]
    if a ~= nil and a.id ~= nil and a.locked ~= true then
      for j = 1, n do
        if j ~= i then
          local b = list[j]
          if b ~= nil and b.id == a.id and b.locked ~= true and b.count ~= nil then
            local maxStack = a.maxStack or 1
            if maxStack > 1 and ((a.count or 1) + (b.count or 1)) <= maxStack then
              return a, b
            end
          end
        end
      end
    end
  end
  return nil
end

-- ★★★0.3.41 无进展闸门（文件头 ②；真机「特殊袋导致死循环」就是这里兜住的）：
--   判据 = **这个工作区状态在本轮整理里出现过没有**（不是「与上一拍是否相同」）——
--   只比上一拍的话，**来回互搬的周期**（A→B→A→B…）每拍都与上一拍不同 ⇒ 永远抓不到
--   （0.3.40d 银行主格那次「id 时有时无 ⇒ 反复互搬」正是这个形态）。
--   · 状态**没出现过** ⇒ 这是净进展（重置计时与计数）；
--   · 状态**出现过** ⇒ 静止不动，或来回绕圈；从「上一次见到新状态」起算满 SORT_NOPROG_SEC 秒
--     就记一次无进展，累计 SORT_NOPROG_MAX 次 ⇒ 收工。
--   ★为什么按「秒」而不按「步」：本客户端**容器读回在整理中会滞后**（0.3.9/0.3.35 在案，
--     新鲜戳记有效期 1.5s）⇒ 刚落位那一拍的读回可能还是旧的（= 状态「出现过」）；按步数会**误报**，
--     按秒（3s = 戳记有效期的两倍）才分得清「读回还没到」与「这一步真的没发生」。
--   ★`seen` 有界：超过 64 个状态就整表清空重来（只有在一路顺进、几十步没被卡过时才会发生）。
local function noProgress(fp, now)
  if type(B.sortFpSeen) ~= "table" then B.sortFpSeen = {} end
  local seen = B.sortFpSeen
  local n = 0
  local _
  for _ in pairs(seen) do n = n + 1 end
  if n > 64 then
    seen = {}
    B.sortFpSeen = seen
  end
  if seen[fp] ~= true then
    seen[fp] = true
    B.sortFp = fp
    B.sortFpAt = now
    B.sortNoProg = 0
    return false
  end
  if B.sortFpAt == nil then
    B.sortFpAt = now
    return false
  end
  if (now - B.sortFpAt) < SORT_NOPROG_SEC then return false end
  B.sortNoProg = (B.sortNoProg or 0) + 1
  B.sortFpAt = now                 -- ★重新计时：否则后面每一拍都会累加
  return (B.sortNoProg >= SORT_NOPROG_MAX)
end

-- 一步：返回 "moved" / "done" / "stall" / "noprog" / "nofree" / "cursor" / 其它错误串
local function oneStep()
  local slots = slotOrder(B.sortScope)
  local list, n = snapshot(slots)
  local now = 0
  if type(GetTime) == "function" then
    local okT, t = pcall(GetTime)
    if okT and type(t) == "number" then now = t end
  end
  if noProgress(fpOf(slots, list, n), now) then return "noprog" end
  -- ★★★0.3.49 本轮用哪套算法（**每拍现读** ⇒ 中途切换立刻生效）——
  --   读口拿不到 / 回坏值 ⇒ 回落 `"orig"`（= 原算法，最保守的一套；「拿不到证据就跑原来那条路」）。
  --   ★盖章排在**合并之前**：合并那一步也可能直接 return，而 A/B 记账要读到「这一轮到底跑的是谁」。
  local algo = "orig"
  if type(B.algoNow) == "function" then algo = B.algoNow() end
  if algo ~= "a" and algo ~= "b" then algo = "orig" end
  B.sortAlgoRun = algo
  local i
  -- ① 合并堆叠（整堆并入，装不下不动手）
  local src, dst = findMerge(list, n)
  if src ~= nil then
    local ok, why = moveNow({ bag = src.bag, slot = src.slot }, { bag = dst.bag, slot = dst.slot }, true)
    if ok then
      if why == "cursor" then return "cursor" end
      -- ★0.3.35：落格要画的那条记录 = 源堆 + 目标堆的合并堆（数量合并、其余字段照源堆）
      local mc = {}
      local mk, mv
      for mk, mv in pairs(src) do mc[mk] = mv end
      mc.count = (src.count or 1) + (dst.count or 1)
      return "moved", src.bag, src.slot, dst.bag, dst.slot, mc
    end
  end
  -- ② 位次排序：期望序 = 当前所有物品按规则排序
  local items = {}
  for i = 1, n do
    if list[i] ~= nil then
      table.insert(items, list[i])
    end
  end
  if table.getn(items) == 0 then return "done" end
  table.sort(items, lessRec)
  -- ★★★0.3.49 算法分派（见文件头）：`a` / `orig` 都走下面那一趟（A 的差别只在 park 目标，见下）；
  --   **`b` 先补一遍「目标格是空的」那一类**（1 步成，不必先 park）⇒ 再把剩下的交给同一趟。
  --   ★B 这一趟**严格前置**：没找到可做的 ⇒ 原样落回下面那一趟 ⇒ 边界/坏数据只会退化成 A/orig，绝不卡住。
  --   ★donor 判据 `(cw == nil or cw.id ~= cd.id)` = 「这一格本身是错位的（或它压根不该有东西）」
  --     —— **绝不许偷已经摆对的堆**（首版漏了这条，实测反而 **+113%** 更慢；补上后 −38%）。
  --   ★单调性：这一步把 i 摆正、把 j2 变空（j2 本来就错位 ⇒ 仍错位）⇒ 错位数**严格递减** ⇒ 不可能不收敛。
  if algo == "b" then
    for i = 1, n do
      local wantB = items[i]
      if wantB ~= nil and list[i] == nil then
        local dn = nil
        local j2
        for j2 = 1, n do
          if j2 ~= i then
            local cd = list[j2]
            local cw = items[j2]
            if cd ~= nil and cd.id == wantB.id and cd.locked ~= true
              and (cw == nil or cw.id ~= cd.id) then
              dn = cd
              break
            end
          end
        end
        if dn ~= nil then
          local okE, whyE = moveNow({ bag = dn.bag, slot = dn.slot }, { bag = slots[i].bag, slot = slots[i].slot })
          if okE then
            if whyE == "cursor" then return "cursor" end
            return "moved", dn.bag, dn.slot, slots[i].bag, slots[i].slot, dn
          end
          if whyE == "locked" then return "stall" end
        end
      end
    end
  end
  for i = 1, n do
    local want = items[i]
    if want == nil then
      break
    end
    local cur = list[i]
    if cur == nil or cur.id ~= want.id then
      local donor = nil
      local j
      for j = i + 1, n do
        local cand = list[j]
        if cand ~= nil and cand.id == want.id and cand.locked ~= true then
          donor = cand
          break
        end
      end
      if donor ~= nil then
        if cur == nil then
          -- 目标空 ⇒ 纯移动（光标必空）
          local ok2, why2 = moveNow({ bag = donor.bag, slot = donor.slot }, { bag = slots[i].bag, slot = slots[i].slot })
          if ok2 then
            if why2 == "cursor" then return "cursor" end
            return "moved", donor.bag, donor.slot, slots[i].bag, slots[i].slot, donor
          end
          if why2 == "locked" then return "stall" end
        else
          -- 目标被占 ⇒ 先把占位那件 park 到一个空格（下一步重扫时 i 已空，再搬 donor 过来）
          -- ★★★0.3.7：这里必须按**槽位数 n** 扫 —— 旧写法写 `table.getn(list)`，而末尾空格的 nil
          --   会让它短算 ⇒ 明明有空格却 `park == nil` ⇒ 误报「一格空位都没有」（用户报障的最后一层）。
          -- ★★★0.3.49 A 的优化（**只改 park 目标怎么挑，走位顺序与判据一字未动**）：
          --   A 档 = 优先把占位那件放进**它自己的最终位置**（`items[k] == cur` 且那一格空着），
          --   找不到才退回「第一个空格」（= orig 档的口径）。
          --   ★实测（同 8 组夹具）：合计 **1029 → 902 步（−12.3%）**，两段大件（背包+银行）**−25%**，
          --     零互换、最终 id 序列逐格一致；**没有一组变差**。
          --   ★为什么安全：仍是一拍一对写动作、仍每拍全量重读、仍只搬进空格 / 并入同 id（绝不互换）；
          --     变的只是「先搬到哪个空位」——搬进自己的最终位置 = 那件当场落定，不必再来一次。
          local park = nil
          local k
          if algo ~= "orig" then
            for k = 1, n do
              if items[k] == cur and list[k] == nil then
                park = k
                break
              end
            end
          end
          if park == nil then
            for k = 1, n do
              if list[k] == nil then
                park = k
                break
              end
            end
          end
          if park == nil then return "nofree" end
          local ok3, why3 = moveNow({ bag = cur.bag, slot = cur.slot }, { bag = slots[park].bag, slot = slots[park].slot })
          if ok3 then
            if why3 == "cursor" then return "cursor" end
            return "moved", cur.bag, cur.slot, slots[park].bag, slots[park].slot, cur
          end
          if why3 == "locked" then return "stall" end
          return "stall"
        end
      end
    end
  end
  return "done"
end

function B.sortStopFn(reason)
  if B.sortOn ~= true then return end
  B.sortOn = false
  B.sortAcc = 0
  B.sortScope = nil
  local moves = B.sortMoves or 0
  local f = B.ui and B.ui.frame
  if f ~= nil and B.isObj(f.ehSortBtn) and B.isObj(f.ehSortBtn.label) then
    pcall(f.ehSortBtn.label.SetText, f.ehSortBtn.label, L("SORT"))
  end
  B.sayForce(L("SORT_STOP", tostring(reason or "?"), moves))
  -- ★0.3.38 中止也盖落定重刷（中止前搬过的那几步同样需要一次「读回恢复后」的整刷）
  B.sortSettleAt = GetTime() + B.SORT_FRESH_SEC + 0.05
  B.pumpSync()
end

-- ★实时显示（0.3.34 → 0.3.35；只动画面、整理算法一字未碰 —— 用户两轮原话见 CHANGELOG）：
--   每走一步，**当场**只重画动过的那两格（不等 +0.08s 的全窗 refreshAll）：
--   · 源格直接画**空**（三条 moved 路径里源格都搬空了 —— 不必等读回）；
--   · 落格直接画**我们手里已知的那条记录**（dstRec —— 本客户端容器读回在整理中滞后
--     （服务器没确认就报空，0.3.9 在案），等读回 = 用户报的「黄框格整程空白」；
--     搬的那件本来就在手里，不必等它）；
--   · 两格各盖一个**新鲜戳记**（`B.sortFresh`，有效期 `B.SORT_FRESH_SEC`）：戳记有效期内
--     `refreshAll` / `paintOne` 不拿滞后的「报空」盖掉这份直接画好的内容；
--     过期后照常按读回画 —— 那时服务器早确认了。
function B.sortPaintMove(sb, ss, db, ds, dstRec)
  local bs = B.ui and B.ui.buttons
  if type(bs) ~= "table" then return end
  local bSrc = (type(sb) == "number" and type(ss) == "number") and bs[sb] and bs[sb][ss] or nil
  local bDst = (type(db) == "number" and type(ds) == "number") and bs[db] and bs[db][ds] or nil
  if type(B.paintRec) ~= "function" then return end
  if B.sortFresh == nil then B.sortFresh = {} end
  if bSrc ~= nil then B.sortFresh[sb .. "," .. ss] = GetTime() end
  if bDst ~= nil then B.sortFresh[db .. "," .. ds] = GetTime() end
  if B.isObj(bSrc) then B.paintRec(bSrc, nil) end
  if B.isObj(bDst) then B.paintRec(bDst, dstRec) end
end

function B.sortStep(dt)
  if B.sortOn ~= true then return end
  B.sortElapsed = (B.sortElapsed or 0) + (tonumber(dt) or 0.05)
  if inCombat() then
    B.sortStopFn(L("SORT_STOP_COMBAT"))
    return
  end
  if cursorBusy() then
    B.sortStopFn(L("SORT_STOP_CURSOR"))
    return
  end
  if B.sortElapsed > SORT_TIMEOUT then
    B.sortStopFn(L("SORT_STOP_TIMEOUT"))
    return
  end
  if (B.sortMoves or 0) >= SORT_MAX_MOVES then
    B.sortStopFn(L("SORT_STOP_MOVES"))
    return
  end
  local gap = B.cfg().moveGap or 0.45
  B.sortAcc = (B.sortAcc or 0) + (tonumber(dt) or 0.05)
  if B.sortAcc < gap then return end
  B.sortAcc = 0
  local r, mvSb, mvSs, mvDb, mvDs, mvRec = oneStep()
  if r == "moved" then
    B.sortMoves = (B.sortMoves or 0) + 1
    B.sortStall = 0
    -- ★0.3.35 实时显示：当场用已知记录直接画动过的那两格 + 盖新鲜戳记（算法节奏不变，markDirty 照旧兜底）
    B.sortPaintMove(mvSb, mvSs, mvDb, mvDs, mvRec)
    B.markDirty(0.08)
    if B.sortMoves % 20 == 0 then
      B.say(L("SORTING") .. " " .. tostring(B.sortMoves))
    end
  elseif r == "stall" then
    B.sortStall = (B.sortStall or 0) + 1
    if B.sortStall >= SORT_STALL_MAX then
      B.sortStopFn(L("SORT_STOP_LOCKED"))
    end
  elseif r == "noprog" then
    -- ★0.3.41：工作区状态连续多秒没有任何变化 ⇒ 这一步（或这一串）根本没发生 ——
    --   立刻收工，绝不空转到 SORT_MAX_MOVES(400) / SORT_TIMEOUT(180s)（旧写法就是这样卡住的）
    B.sortStopFn(L("SORT_STOP_NOPROG", B.sortNoProg or SORT_NOPROG_MAX))
  elseif r == "nofree" then
    -- 一格空的都没有：排序需要空格做中转 ⇒ 如实说，绝不动别人的东西
    B.sortStopFn(L("SORT_STOP_NOFREE"))
  elseif r == "cursor" then
    -- 客户端把物品留在光标上了（我们对 Drop 语义的假设不成立）⇒ 立刻收工，让玩家自己放
    B.sortStopFn(L("SORT_STOP_CURSOR"))
  elseif r == "done" then
    -- ★0.3.40：背包段整完、银行开着 ⇒ 换**银行段**接着整（用户：「顺带也要整理银行背包内的物品」）——
    --   两段分跑，绝不跨容器搬；银行里不足 2 件就跳过这段直接收工。
    if B.sortScope ~= "bank" and B.bankOpen == true then
      local bslots, bskip = slotOrder("bank")
      local blist, bn = snapshot(bslots)
      local bc = 0
      local bi2
      for bi2 = 1, bn do
        if blist[bi2] ~= nil then bc = bc + 1 end
      end
      if bc >= 2 then
        B.sortScope = "bank"
        B.sortAcc = 0
        B.sayForce(L("SORT_BANK_SWITCH"))
        -- ★0.3.41：银行包也可能是特殊袋 ⇒ 换段时同样如实报出被跳过的容器
        if table.getn(bskip) > 0 then B.sayForce(L("SORT_SKIP", skipText(bskip))) end
        return
      end
    end
    B.sortScope = nil
    local t0 = B.sortT0 or GetTime()
    local used = GetTime() - t0
    B.sortOn = false
    B.sortAcc = 0
    local f = B.ui and B.ui.frame
    if f ~= nil and B.isObj(f.ehSortBtn) and B.isObj(f.ehSortBtn.label) then
      pcall(f.ehSortBtn.label.SetText, f.ehSortBtn.label, L("SORT"))
    end
    -- ★0.3.49 完成行带上**这一轮用的算法**（用户要在真机上做 A/B/C 对比 ⇒ 每轮都一眼看见是谁跑的），
    --   并把这一轮记进 A/B 实测账（★只记**跑完**的；被停掉/超时的不进账，平均值才不被截断污染）。
    local algoTag = ""
    if type(B.algoText) == "function" then algoTag = " ｜ " .. B.algoText() end
    B.sayForce(L("SORT_DONE", B.sortMoves or 0, used) .. algoTag)
    if type(B.sortStatAdd) == "function" then
      pcall(B.sortStatAdd, B.sortAlgoRun, B.sortMoves or 0, used, B.sortItems or 0)
    end
    B.markDirty(0.05)
    -- ★0.3.38 落定重刷：戳记（1.5s）全部过期之后再整刷一次 —— 探针实证：整理一停容器读回就恢复，
    --   但戳记过期之后没有人再刷新 ⇒ 被守卫跳过的格子永远停在「有数无图标」（0.3.37 真机定案）。
    B.sortSettleAt = GetTime() + B.SORT_FRESH_SEC + 0.05
    B.pumpSync()
  else
    B.sortStopFn(tostring(r))
  end
end

function B.sortStart(loud)
  if B.sortOn == true then
    -- 再敲一次 = 手动停止（防「停不下来」）
    B.sortStopFn(L("SORT_STOP_CMD"))
    return true
  end
  if inCombat() then
    B.sayForce(L("SORT_COMBAT"))
    return false
  end
  if cursorBusy() then
    B.sayForce(L("SORT_CURSOR"))
    return false
  end
  local slots, skipped = slotOrder()
  local list, nSlots = snapshot(slots)
  local n = 0
  local i
  -- ★★★0.3.7：同样按**槽位数**数（`table.getn(list)` 会被末尾空格短算 ⇒ 件数虚低、
  --   「少于 2 件不整理」会误判）
  for i = 1, nSlots do
    if list[i] ~= nil then n = n + 1 end
  end
  -- 银行段：格子与「被跳过的容器」各算一次（银行开着时才有；分类结果有缓存，开销可忽略）
  local bankSlots, bankSkip
  if B.bankOpen == true then
    bankSlots, bankSkip = slotOrder("bank")
  end
  -- ★0.3.40：背包不足 2 件、但银行开着且银行里 ≥2 件 ⇒ 直接从**银行段**开整（换段逻辑与 done 分支同口径）
  local startScope = nil
  if n < 2 and bankSlots ~= nil then
    local blist, bn = snapshot(bankSlots)
    local bc = 0
    for i = 1, bn do
      if blist[i] ~= nil then bc = bc + 1 end
    end
    if bc >= 2 then
      startScope = "bank"
      n = bc
    end
  end
  -- ★★★0.3.41：起手先把「跳过了哪些容器」说清楚（不论这次能不能启动）——
  --   特殊袋与**判不出类型**的袋子都不进工作区（fail-closed），绝不静默少整理；
  --   ★判不出类型的原因另有一句话（客户端不回答子类词表 = 与「这袋真是特殊袋」是两回事）。
  local allSkip = {}
  for i = 1, table.getn(skipped) do table.insert(allSkip, skipped[i]) end
  if bankSkip ~= nil then
    for i = 1, table.getn(bankSkip) do table.insert(allSkip, bankSkip[i]) end
  end
  if table.getn(allSkip) > 0 then
    if B.bagKindNA == true then
      B.sayForce(L("SORT_SKIP_NA", skipText(allSkip)))
    else
      B.sayForce(L("SORT_SKIP", skipText(allSkip)))
    end
  end
  if n < 2 then
    B.sayForce(L("SORT_NONE"))
    return false
  end
  B.sortScope = startScope
  B.sortOn = true
  B.sortAcc = 0
  B.sortMoves = 0
  B.sortStall = 0
  B.sortElapsed = 0
  B.sortT0 = GetTime()
  -- ★0.3.49 这一轮的「件数」（= n，含银行段换段时它已经改成银行件数）—— A/B 记账要用它判「两轮可比吗」
  B.sortItems = n
  -- ★0.3.41：无进展闸门的会话态开新一轮就归零（`seen` 空 ⇒ 第一步必是「新状态」，绝不误判）
  B.sortFp = nil
  B.sortFpAt = nil
  B.sortFpSeen = {}
  B.sortNoProg = 0
  -- ★0.3.35：每次整理开一张新的「新鲜戳记」表（旧戳记按时间自然过期，不在收尾处清 ——
  --   收尾那一刻最后几步的读回多半还没确认，清了就会被 refreshAll 画回空格）
  B.sortFresh = {}
  -- ★0.3.38：上一次的落定重刷作废（新一轮整理期间由每步的周期刷 + 戳记接管）
  B.sortSettleAt = nil
  local f = B.ui and B.ui.frame
  if f ~= nil and B.isObj(f.ehSortBtn) and B.isObj(f.ehSortBtn.label) then
    pcall(f.ehSortBtn.label.SetText, f.ehSortBtn.label, L("SORTING"))
  end
  if loud ~= false then
    local gap = B.cfg().moveGap or 0.45
    local steps = n
    B.sayForce(L("SORT_START", n, steps, gap))
  end
  B.pumpSync()
  return true
end

-- ===== 只读体检口（`/ebag status` 用；★工具模块的读值口留在模块自己文件里）=====
-- 格式：「整理工作区：背包 0,3 ｜ 银行包 5,7 ｜ 整理跳过特殊袋：背包 1(草药袋) ｜ 无进展 0/2」
--   ★零写入、零副作用（只读分类缓存 + 槽位表；分类结果本身有缓存）。
function B.sortAreaLine()
  local slots, skipped = slotOrder()
  local order, seen = {}, {}
  local i
  for i = 1, table.getn(slots) do
    local b = slots[i].bag
    if seen[b] ~= true then
      seen[b] = true
      table.insert(order, b)
    end
  end
  local function names(list)
    local out = {}
    local j
    for j = 1, table.getn(list) do
      out[j] = (type(B.bagLabel) == "function") and B.bagLabel(list[j]) or ("#" .. tostring(list[j]))
    end
    if table.getn(out) == 0 then return L("ST_NONE") end
    return table.concat(out, ",")
  end
  local txt = names(order)
  if B.bankOpen == true then
    local bslots, bskip = slotOrder("bank")
    local bo, bseen = {}, {}
    for i = 1, table.getn(bslots) do
      local b = bslots[i].bag
      if bseen[b] ~= true then
        bseen[b] = true
        table.insert(bo, b)
      end
    end
    txt = txt .. " ｜ " .. names(bo)
    for i = 1, table.getn(bskip) do table.insert(skipped, bskip[i]) end
  end
  if table.getn(skipped) > 0 then
    txt = txt .. " ｜ " .. L("SORT_SKIP", skipText(skipped))
  end
  txt = txt .. " ｜ " .. L("SORT_NOPROG_N", B.sortNoProg or 0, SORT_NOPROG_MAX)
  return L("ST_SORT_AREA", txt)
end
