/** quest/probe_chainlist.js —— 只读探针：任务线列表的**条数**与**等级覆盖**
 *  回答「任务线最高只有 30 级 / 是不是没收集齐」：直接跑数据层，看真实条数与最高等级。
 *  载入清单与 test_engine.js 同口径（stub + 三语言 + QuestData + QuestBulk + QuestChains）。
 *  用法：node quest/probe_chainlist.js
 */
'use strict';
const fs = require('fs');
const path = require('path');
const fengari = require('fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const root = path.join(__dirname, '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

const files = ['test_stub.lua', 'Locales/zhCN.lua', 'Locales/enUS.lua', 'Locales/ruRU.lua',
  'quest/QuestData.lua', 'quest/QuestBulk.lua', 'quest/QuestChains.lua'];
for (const f of files) {
  const src = fs.readFileSync(path.join(root, f), 'utf8');
  if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) {
    console.error('LOAD FAIL ' + f + ': ' + to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(1);
  }
}

const chunk = `
  local function topHi(hits)
    local top = 0
    for i = 1, table.getn(hits or {}) do
      local c = hits[i].c
      local hi = tonumber(c and c.hi) or 0
      if hi > top then top = hi end
    end
    return top
  end
  local all, ex = EVAL_QC_SEARCH("", 0, nil)
  PROBE_ALL, PROBE_EXTRA = table.getn(all or {}), ex or 0
  PROBE_TOP = topHi(all)
  local cap200 = EVAL_QC_SEARCH("", 200, nil)
  PROBE_CAP200 = table.getn(cap200 or {})
  PROBE_CAP200_TOP = topHi(cap200)
  local small, sex = EVAL_QC_SEARCH("", 5, nil)
  PROBE_SMALL, PROBE_SMALL_EXTRA = table.getn(small or {}), sex or 0
  PROBE_CUR = table.getn(EVAL_QC_LIST())
  PROBE_SER = EVAL_QC_SERIES_COUNT()
  -- ★1.75.14 排序检查：**跨块**统一按「任务最低等级」升序（用户问「任务线有按照任务最低等级排序吗?」）
  --   逆序计数必须为 0；头尾各打几条便于肉眼核对（旧实现是两块拼接 ⇒ 30 → 4 的回头）
  local inv, prev = 0, -1
  for i = 1, table.getn(all or {}) do
    local lo = tonumber(all[i].c and all[i].c.lo) or 99
    if lo < prev then inv = inv + 1 end
    prev = lo
  end
  PROBE_INV = inv
  local head, tail = {}, {}
  for i = 1, math.min(6, table.getn(all or {})) do
    local e = all[i]
    head[table.getn(head) + 1] = string.format("%s/%s(lo=%s)", tostring(e.kind), tostring(e.name), tostring(e.c and e.c.lo))
  end
  local n = table.getn(all or {})
  for i = math.max(1, n - 2), n do
    local e = all[i]
    tail[table.getn(tail) + 1] = string.format("%s/%s(lo=%s)", tostring(e.kind), tostring(e.name), tostring(e.c and e.c.lo))
  end
  PROBE_HEAD, PROBE_TAIL = table.concat(head, " | "), table.concat(tail, " | ")
  -- ★1.75.15 各等级档实测（60+ 独立成档；判据是**区间重叠**，所以 hi 可能超出该档上界）
  local bands = { { "10-19", 10, 19 }, { "20-29", 20, 29 }, { "30-39", 30, 39 },
                  { "40-49", 40, 49 }, { "50-59", 50, 59 }, { "60+", 60, 999 } }
  local bl = {}
  for bi = 1, table.getn(bands) do
    local h = EVAL_QC_SEARCH("", 0, { loMin = bands[bi][2], loMax = bands[bi][3] }) or {}
    local mn, mx = 999, 0
    for i = 1, table.getn(h) do
      local c = h[i].c or {}
      local lo, hi = tonumber(c.lo) or 0, tonumber(c.hi) or 0
      if lo < mn then mn = lo end
      if hi > mx then mx = hi end
    end
    bl[table.getn(bl) + 1] = string.format("%s=%d条(lo%d~hi%d)", bands[bi][1], table.getn(h), mn, mx)
  end
  PROBE_BANDS = table.concat(bl, " · ")
  -- ★1.75.15 键↔详情一致性：列表行用 "s:<录入顺序>" 作键，而详情按**排序后位次**取记录 ——
  --   两者一旦不等，点一条线会打开**另一条**的详情（静默错内容）。这里逐条比对。
  local kBadKV = 0
  local kSerList = EVAL_QC_SERIES_LIST()
  for i = 1, table.getn(kSerList) do
    local key = "s:" .. tostring(i)          -- 列表行与详情**都**按「排序后位次」作键（两边同一口径）
    local d = EVAL_QC_SERIES_DETAIL(key)
    local dn = d and d.c and d.c.n or "nil"
    if tostring(kSerList[i].n) ~= tostring(dn) then
      kBadKV = kBadKV + 1
      if kBadKV <= 3 then PROBE_KV_SAMPLE = (PROBE_KV_SAMPLE or "") .. string.format("[%s] 列表=%s 详情=%s; ", tostring(key), tostring(kSerList[i].n), tostring(dn)) end
    end
  end
  PROBE_KV = kBadKV
  PROBE_KV_SAMPLE = PROBE_KV_SAMPLE or "-"
  -- 跨集合同名（策展链 vs 自报系列）——去重没覆盖到的名字，必须为 0
  local cCur, cSer, cHit = {}, {}, {}
  for i = 1, table.getn(all or {}) do
    local e = all[i]
    local nm = tostring(e.c and e.c.n or "")
    if nm ~= "" then if e.kind == "series" then cSer[nm] = true else cCur[nm] = true end end
  end
  for nm in pairs(cCur) do if cSer[nm] then cHit[table.getn(cHit) + 1] = nm end end
  PROBE_CROSS = table.concat(cHit, ", ")
  -- ★1.75.19 「一页任务线要抓多少件装备」：任务线是**每行最多 6 个奖励图标**（装备视图每行只有 1 个）——
  --   所以同一页要请求的件数差好几倍，这正是「任务线图标跟不上」的量化原因。
  local kBand = EVAL_QC_SEARCH("", 0, { loMin = 10, loMax = 19 }) or {}
  local nRows, nIcons, nRow1 = 0, 0, 0
  for i = 1, math.min(17, table.getn(kBand)) do
    local ids = EVAL_QC_CHAIN_REWARDS(kBand[i].c.k, 6) or {}
    nRows = nRows + 1
    nIcons = nIcons + table.getn(ids)
    if i == 1 then nRow1 = table.getn(ids) end
  end
  PROBE_PAGE = string.format("10-19 首屏 %d 行 · 奖励图标共 %d 个（第 1 行 %d 个）· 对照装备视图同屏只需 %d 件",
    nRows, nIcons, nRow1, nRows)
  -- 逐行摊开：**没有图标的行到底是「数据里没有奖励」还是「有奖励但没抓回来」**
  local rl = {}
  for i = 1, math.min(17, table.getn(kBand)) do
    local c = kBand[i].c
    local ids = EVAL_QC_CHAIN_REWARDS(c.k, 6) or {}
    local _, tot = EVAL_QC_CHAIN_REWARDS(c.k, 99)
    rl[table.getn(rl) + 1] = string.format("%s(%s-%s)=%d/%d", tostring(c.n), tostring(c.lo), tostring(c.hi),
      table.getn(ids), tot or 0)
  end
  PROBE_ROWS = table.concat(rl, " | ")
  -- 各档「首屏要抓的奖励图标数」——看图标密集档位是否会被 2s/件 的限频拖住
  local bl2 = {}
  local bands2 = { { "10-19", 10, 19 }, { "20-29", 20, 29 }, { "30-39", 30, 39 },
                   { "40-49", 40, 49 }, { "50-59", 50, 59 }, { "60+", 60, 999 } }
  for bi = 1, table.getn(bands2) do
    local h = EVAL_QC_SEARCH("", 0, { loMin = bands2[bi][2], loMax = bands2[bi][3] }) or {}
    local icons, rowsWith = 0, 0
    for i = 1, math.min(17, table.getn(h)) do
      local _, tot = EVAL_QC_CHAIN_REWARDS(h[i].c.k, 99)
      icons = icons + (tot or 0)
      if (tot or 0) > 0 then rowsWith = rowsWith + 1 end
    end
    bl2[table.getn(bl2) + 1] = string.format("%s: 首屏%d行/%d行有奖励/共%d件", bands2[bi][1],
      math.min(17, table.getn(h)), rowsWith, icons)
  end
  PROBE_PAGE2 = table.concat(bl2, " · ")
  -- ★1.75.20 「每行先出第一件」到底要做到第几轮（用户实测「任务线图标跟不上」的**量尺**）：
  --   泵每 2 秒抽队首一件；队列每次重绘**重建**（= 当前未缓存的、按该实现口径取前 24 件）。
  --   逐轮模拟三种实现，算「**全部有奖励的行**都出图标」要几轮：
  --     A0 = 未重排（最老的写法，纯行序）· A = 1.75.19（入队时按行序截断 24，**之后**再按列重排）
  --     B = 1.75.20（先全收 → 按列排序 → 再截到 24）
  --   ★为什么必须**逐轮模拟**：只比「首轮那 24 件里含几行首件」会低估 A —— A 下一轮重绘时
  --     那件会重新进入截断窗口、再被重排排到前面（首版量尺就是这么把 A 当成 50 秒的，实际不是）。
  local bl3, bl4 = {}, {}
  local CAP24 = 24
  for bi = 1, table.getn(bands2) do
    local h = EVAL_QC_SEARCH("", 0, { loMin = bands2[bi][2], loMax = bands2[bi][3] }) or {}
    local nR = math.min(17, table.getn(h))
    local rowIds = {}
    for i = 1, nR do rowIds[i] = EVAL_QC_CHAIN_REWARDS(h[i].c.k, 6) or {} end
    local function seqOf(rowFirst)
      local s = {}
      if rowFirst then
        for i = 1, nR do for j = 1, 6 do s[table.getn(s) + 1] = rowIds[i][j] end end
      else
        for j = 1, 6 do for i = 1, nR do s[table.getn(s) + 1] = rowIds[i][j] end end
      end
      return s
    end
    local function dedup(seq)
      local seen, list = {}, {}
      for k = 1, table.getn(seq) do
        local id = seq[k]
        if type(id) == "number" and not seen[id] then seen[id] = true list[table.getn(list) + 1] = id end
      end
      return list
    end
    local dRow, dCol = dedup(seqOf(true)), dedup(seqOf(false))
    -- 按列 rank（与 DataSearch 的排名同一口径：j 外层、i 内层）
    local crank, cn = {}, 0
    for j = 1, 6 do
      for i = 1, nR do
        local id = rowIds[i][j]
        if type(id) == "number" and not crank[id] then cn = cn + 1 crank[id] = cn end
      end
    end
    -- 队列 = 该口径下未缓存的**前 24 件**（doSort = 截断之后再按列重排，即 1.75.19 的写法）
    local function queueOf(seq, cached, doSort)
      local out = {}
      for k = 1, table.getn(seq) do
        local id = seq[k]
        if not cached[id] then
          out[table.getn(out) + 1] = id
          if table.getn(out) >= CAP24 then break end
        end
      end
      if doSort and table.getn(out) > 1 then
        table.sort(out, function(a, b) return (crank[a] or 9999) < (crank[b] or 9999) end)
      end
      return out
    end
    -- 「有奖励的行」= 该行第一件（rwIds[1]）；目标 = 这些件全部抓回来
    local firsts = {}
    for i = 1, nR do if type(rowIds[i][1]) == "number" then firsts[table.getn(firsts) + 1] = rowIds[i][1] end end
    local function roundsToLit(model, rebuildEvery)
      -- rebuildEvery = 每几轮才重建一次队列（1 = 每轮；现实里重绘依赖「服务器回音」→ 常常 >1）
      local cached, q, qAt, rounds = {}, nil, nil, 0
      while rounds <= 400 do
        local lit = true
        for k = 1, table.getn(firsts) do if not cached[firsts[k]] then lit = false break end end
        if lit then return rounds end
        if q == nil or (rounds - qAt) >= rebuildEvery then
          if model == "A0" then q = queueOf(dRow, cached, false)
          elseif model == "A" then q = queueOf(dRow, cached, true)
          else q = queueOf(dCol, cached, false) end
          qAt = rounds
          if table.getn(q) == 0 then return -1 end
        end
        local head = table.remove(q, 1)
        cached[head] = true
        rounds = rounds + 1
      end
      return -1
    end
    bl3[table.getn(bl3) + 1] = string.format("%s: %d行有奖励 · 全部点亮(轮x2s) A0/未重排=%d A/1.75.19行序截断+重排=%d B/1.75.20列序截断=%d",
      bands2[bi][1], table.getn(firsts), roundsToLit("A0", 1), roundsToLit("A", 1), roundsToLit("B", 1))
    -- ★但「每轮都重绘」是理想情况：现实里 **回音稀疏**（实测批量 4 件只回 1 件）⇒ 队列可能好几轮
    --   才重建一次。这时 A 的队列被前几行的件占满、后面的行**连请求都发不出去**，差距才显出来。
    bl4[table.getn(bl4) + 1] = string.format("%s: 稀疏重绘(每8轮重建) A=%d B=%d",
      bands2[bi][1], roundsToLit("A", 8), roundsToLit("B", 8))
  end
  PROBE_LIT = table.concat(bl3, " · ")
  PROBE_LIT2 = table.concat(bl4, " · ")
`;
if (lauxlib.luaL_dostring(L, to_luastring(chunk)) !== lua.LUA_OK) {
  console.error('RUN FAIL: ' + to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
const g = n => { lua.lua_getglobal(L, to_luastring(n)); const v = lua.lua_tointeger(L, -1); lua.lua_pop(L, 1); return v; };
const gs = n => { lua.lua_getglobal(L, to_luastring(n)); const v = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); return v; };
console.log('策展链 EVAL_QC_LIST        = ' + g('PROBE_CUR'));
console.log('自报系列 EVAL_QC_SERIES_COUNT = ' + g('PROBE_SER'));
console.log('列表全量 EVAL_QC_SEARCH("",0) = ' + g('PROBE_ALL') + ' 条 · extra=' + g('PROBE_EXTRA') +
  ' · 最高 hi=' + g('PROBE_TOP'));
console.log('排序：等级逆序处 = ' + g('PROBE_INV') + '（必须为 0）');
console.log('  头部 ' + gs('PROBE_HEAD'));
console.log('  尾部 ' + gs('PROBE_TAIL'));
console.log('各等级档 ' + gs('PROBE_BANDS'));
console.log('键↔详情不一致 = ' + g('PROBE_KV') + ' 条（必须为 0）· 样例 ' + gs('PROBE_KV_SAMPLE'));
console.log('跨集合同名 = ' + (gs('PROBE_CROSS') || '（空）'));
console.log(gs('PROBE_PAGE'));
console.log('逐行奖励(显示/总数) ' + gs('PROBE_ROWS'));
console.log('各档首屏 ' + gs('PROBE_PAGE2'));
console.log('全部点亮 ' + gs('PROBE_LIT'));
console.log('稀疏重绘 ' + gs('PROBE_LIT2'));
console.log('对照 cap=200                = ' + g('PROBE_CAP200') + ' 条 · 最高 hi=' + g('PROBE_CAP200_TOP') + '  ← 旧实现（用户看到的「最高 30 级」）');
console.log('cap=5                       = ' + g('PROBE_SMALL') + ' 条 · extra=' + g('PROBE_SMALL_EXTRA'));
