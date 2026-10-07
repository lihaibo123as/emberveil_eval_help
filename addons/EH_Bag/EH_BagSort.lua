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

-- 位置序：**工作区 = 0~4 号袋的全部物理格子**，显示中的包排前面、收起的排后面。
-- ★★★0.3.7 修（用户：「物品整理在有空格的情况下会提示空位不足」）：旧写法只收「显示中」的包
--   ⇒ 你把某个背包**收起**（里面还有空位）时，容量行按**物理格数**报「空 26」（窗口下方那行），
--   而整理引擎在可见区找不到空格做中转 ⇒ 直接误报「一格空位都没有」。
--   ★口径：**收起只影响看不看得见，不影响这一格能不能用**；只有**物理上一格不空**才是真的没空位。
--   排序仍然优先把东西摆在**看得见的地方**（第 1 趟 = 显示中的包），多出来的才落到收起的包里。
local function slotOrder()
  local slots = {}
  local pass, k, s
  for pass = 1, 2 do
        for k = 5, 1, -1 do    --改动点
      local bag = k - 1
      local shown = B.bagShown(bag)
      if (pass == 1 and shown) or (pass == 2 and not shown) then
        local n = B.bagSlotsRaw(bag)
        for s = n, 1, -1 do --改动点
          table.insert(slots, { bag = bag, slot = s })
        end
      end
    end
  end
  return slots
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
local function moveNow(src, dst, allowMerge)
  if type(PickupContainerItem) ~= "function" then return false, "noapi" end
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
  pcall(PickupContainerItem, src.bag, src.slot)
  pcall(PickupContainerItem, dst.bag, dst.slot)
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

-- 一步：返回 "moved" / "done" / "stall" / "nofree" / "cursor" / 其它错误串
local function oneStep()
  local slots = slotOrder()
  local list, n = snapshot(slots)
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
          local park = nil
          local k
          for k = 1, n do
            if list[k] == nil then
              park = k
              break
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
  elseif r == "nofree" then
    -- 一格空的都没有：排序需要空格做中转 ⇒ 如实说，绝不动别人的东西
    B.sortStopFn(L("SORT_STOP_NOFREE"))
  elseif r == "cursor" then
    -- 客户端把物品留在光标上了（我们对 Drop 语义的假设不成立）⇒ 立刻收工，让玩家自己放
    B.sortStopFn(L("SORT_STOP_CURSOR"))
  elseif r == "done" then
    local t0 = B.sortT0 or GetTime()
    local used = GetTime() - t0
    B.sortOn = false
    B.sortAcc = 0
    local f = B.ui and B.ui.frame
    if f ~= nil and B.isObj(f.ehSortBtn) and B.isObj(f.ehSortBtn.label) then
      pcall(f.ehSortBtn.label.SetText, f.ehSortBtn.label, L("SORT"))
    end
    B.sayForce(L("SORT_DONE", B.sortMoves or 0, used))
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
  local slots = slotOrder()
  local list, nSlots = snapshot(slots)
  local n = 0
  local i
  -- ★★★0.3.7：同样按**槽位数**数（`table.getn(list)` 会被末尾空格短算 ⇒ 件数虚低、
  --   「少于 2 件不整理」会误判）
  for i = 1, nSlots do
    if list[i] ~= nil then n = n + 1 end
  end
  if n < 2 then
    B.sayForce(L("SORT_NONE"))
    return false
  end
  B.sortOn = true
  B.sortAcc = 0
  B.sortMoves = 0
  B.sortStall = 0
  B.sortElapsed = 0
  B.sortT0 = GetTime()
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
