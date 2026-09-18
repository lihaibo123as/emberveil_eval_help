-- EvalHelp · DataSearch.lua —— 数据检索 Tab（配置窗 Tab4；基于 UnrealQuest 捆绑数据库的 任务/物品/生物/对象 检索）
-- 独立原则同 Toolbox：自绘 UI 不改主程序；依赖全局件 EVAL_SAY/EVAL_RESOLVE_LANG/EVAL_LOCALES/EVAL_DD_OPEN。
-- 数据访问：UnrealQuestData 全局表懒惰读取——加载顺序 EvalHelp(E) 先于 UnrealQuest(U)，载入期拿不到；
-- 且对方可能未安装/未启用，一切入口先判 dsDb() 非空，缺失显示引导提示不报错。
-- 逻辑层（EVAL_DS_SEARCH / EVAL_DS_DETAIL / EVAL_DS_SHOWMAP）与 UI 分离：test_engine 打桩迷你 UnrealQuestData 直测模型。
-- 级联导航：无限层级（用户实测要求：只要还有关联就可继续点），顶部+底部双 [←返回] 逐层回退。
-- 行图标：类型图标（UnrealQuest media/icons）+物品真实图标（GetItemInfo 第9返回）；有坐标的行带地图图标，点击打开世界地图定位。

local DS = { built = false, filter = "all", mode = "search", nav = {}, results = {}, due = 0, lastQuery = nil, titleLoc = nil }

-- ===== 自绘基础件（与 Toolbox 同风格：WHITE8X8 纯色纹理 + 字体链） =====
local function dsSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function dsText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(fs.SetFontObject, fs, fo) then ok = true break end
  end
  if not ok then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okF, ok2 = pcall(fs.SetFont, fs, fp, size, "")
      if okF and ok2 then ok = true break end
    end
  end
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

local function dsBtn(parent, x, y, w, label, onClick, widgets)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(16)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  dsSolid(bg, 0.22, 0.18, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local bt = dsText(b, 10, 0.95, 0.82, 0.35)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText(label)
  b:SetScript("OnClick", onClick)
  if widgets then table.insert(widgets, b) end
  return { btn = b, bg = bg, text = bt }
end

-- ===== i18n =====
-- ★1.70.46 修正语言来源（真 bug，「静默失败」家族）：
--   原写法 `(type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"`
--   **恒等于 "zhCN"**：Core.lua 的 ehResolveLang() 是个「写入器」——它只把语言存进
--   local EH_LANG，每个分支都是**裸 return（没有任何返回值）**，末尾以 EH_LANG = "zhCN" 收尾。
--   于是 EVAL_RESOLVE_LANG() 返回 nil，被 `or "zhCN"` 兜底 → 本 Tab 在英/俄客户端里
--   **整页显示中文**；更隐蔽的是 dsLang() 也这样写 → 永远去取 `items_zhCN`/`units_zhCN` 子表，
--   物品/怪物/任务名一律中文。全程不报错。
--   主程序取语言一直用的是**读取器** EVAL_GET_LANG()（见 EvalHelp.lua 的 cfWinWidth/WIDE）。
--   ★教训：写入器与读取器混用 → 调用点拿到 nil → 被 `or 默认值` 吞掉。
local function dsLangCode()
  if type(EVAL_GET_LANG) == "function" then
    local l = EVAL_GET_LANG()
    if type(l) == "string" and l ~= "" then return l end
  end
  return "zhCN"
end

local function L(k)
  local pack = EVAL_LOCALES and EVAL_LOCALES[dsLangCode()]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

-- ===== UnrealQuest 互操作访问器（懒惰：EvalHelp 加载早于 UnrealQuest，载入期拿不到） =====
-- 统一从这里取对方的 Client 与模块，供坐标/图钉/开图/tooltip 复用（1.70.8 起大量替代自实现）。
local function dsUQClient()
  local uq = rawget(_G, "UnrealQuest")
  local c = type(uq) == "table" and uq.Client or nil
  return (type(c) == "table") and c or nil
end
local function dsUQModule(name)
  local uq = rawget(_G, "UnrealQuest")
  if type(uq) ~= "table" or type(uq.GetModule) ~= "function" then return nil end
  local ok, m = pcall(uq.GetModule, uq, name)
  if ok and type(m) == "table" then return m end
  return nil
end

-- ===== 数据访问层（全部防御式：对方缺席/表缺失/条目缺失逐级兜底） =====
local function dsDb()
  local d = rawget(_G, "UnrealQuestData")
  if type(d) ~= "table" then return nil end
  return d
end

-- ===== 依赖探测：数据来源 UnrealQuest 是否可用（1.70.46）=====
-- 本 Tab 强依赖 UnrealQuest：任务/物品/生物/对象数据库全部来自它的全局表 UnrealQuestData，
-- 地图定位走它的 UnrealQuest.Client。对方缺席时必须给出**可行动**的引导，而不是让用户在
-- 搜索框里打字却只拿到空列表——本项目最忌讳的「静默失败」。
-- 本客户端有完整的 Addon API（emberveil.org/wiki/lua/globals/Addon）：
--   GetAddOnInfo(名)          → 文件夹名,标题,备注,URL,可加载(1/nil),原因token,SECURE/INSECURE
--                              ★未知插件：除 security 外全部 nil → 用第一个返回值判「未安装」
--   GetAddOnEnableState(nil,名) → 0 未启用 / 1 部分角色 / 2 已启用
--   IsAddOnLoaded(名)         → 是否已加载
-- 名称查找大小写不敏感；LoadAddOn 是 Protected（插件不能自行加载对方）→ 不给「一键加载」按钮，只做引导。
-- ★主判据始终是 dsDb()：对方元信息只用来**细化措辞**，绝不因为元信息异常就否掉可用的数据。
local DS_DEP_OK, DS_DEP_MISSING, DS_DEP_OFF, DS_DEP_PENDING, DS_DEP_UNKNOWN = 0, 1, 2, 3, 4
-- 文件夹实际名是 UnrealQuest（磁盘上亲测）；文档说查找大小写不敏感，两种拼写都试一次做双保险。
local DS_DEP_ADDON = { "UnrealQuest", "unrealQuest" }

local function dsCall(name, ...)
  local f = rawget(_G, name)
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
  return nil
end

local function dsDepState()
  if type(dsDb()) == "table" then return DS_DEP_OK end
  if type(rawget(_G, "GetAddOnInfo")) ~= "function" then return DS_DEP_UNKNOWN end -- 客户端无 Addon API：只知数据不可用
  local folder = nil
  for _, nm in ipairs(DS_DEP_ADDON) do
    local f = dsCall("GetAddOnInfo", nm)
    if type(f) == "string" and f ~= "" then folder = f break end
  end
  if folder == nil then return DS_DEP_MISSING end -- 未知插件 = 装都没装（GetAddOnInfo 对未知插件只回 security）
  local en = dsCall("GetAddOnEnableState", nil, folder)
  if en == 0 then return DS_DEP_OFF end          -- 装了但没勾选启用
  return DS_DEP_PENDING                           -- 已启用，但数据表还没就绪（首次进游戏/尚未建立）
end

-- 状态 → 文案键。★纯函数且**唯一**：UI 与断言共用同一份，
-- 避免「测试里复刻一份逻辑」导致变异不可见（本项目已在此栽过 4 次）。
local DS_DEP_KEY = {
  [DS_DEP_MISSING] = "DS_NEED_UQ",
  [DS_DEP_OFF]     = "DS_DEP_OFF",
  [DS_DEP_PENDING] = "DS_DEP_PENDING",
  [DS_DEP_UNKNOWN] = "DS_DEP_UNKNOWN",
}
local function dsDepText(st) return DS_DEP_KEY[st] or "DS_NEED_UQ" end

-- 数据库本地化子表所用的语言码（items_zhCN / units_enUS …）。
-- ★必须与 L() 同源（dsLangCode），否则界面语言与数据语言会不一致。
local function dsLang() return dsLangCode() end

-- 本地化名称表：优先界面语言，条目缺失回退 enUS（UnrealQuest LocaleTable 同款）
local function dsLocEntry(base, id)
  local db = dsDb()
  if not db then return nil end
  local loc = db[base .. "_" .. dsLang()]
  local v = type(loc) == "table" and loc[id] or nil
  if v == nil then
    local en = db[base .. "_enUS"]
    v = type(en) == "table" and en[id] or nil
  end
  if base == "quests" and type(v) == "table" then return v.T end
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function dsQuestLoc(id) -- 任务本地化整条 {T,O,D}（详情用 O/D）
  local db = dsDb()
  if not db then return nil end
  local loc = db["quests_" .. dsLang()]
  local v = type(loc) == "table" and loc[id] or nil
  if type(v) ~= "table" then
    local en = db["quests_enUS"]
    v = type(en) == "table" and en[id] or nil
  end
  if type(v) == "table" then return v end
  return nil
end

local function dsZoneName(zid)
  if type(zid) ~= "number" then return nil end
  return dsLocEntry("zones", zid)
end

-- 单位/对象坐标 → 区域摘要 "区域A(x,y)/区域B"（去重，最多 maxn 个）
local function dsZoneSummary(rec, maxn)
  if type(rec) ~= "table" or type(rec.coords) ~= "table" then return "" end
  local seen, parts = {}, {}
  for _, c in ipairs(rec.coords) do
    local zid = type(c) == "table" and c[3] or nil
    if type(zid) == "number" and not seen[zid] then
      seen[zid] = true
      local zn = dsZoneName(zid) or ("#" .. tostring(zid))
      local xy = ""
      if type(c[1]) == "number" and type(c[2]) == "number" and (c[1] > 0 or c[2] > 0) then
        xy = string.format("(%.1f,%.1f)", c[1], c[2])
      end
      table.insert(parts, zn .. xy)
      if table.getn(parts) >= (maxn or 3) then break end
    end
  end
  return table.concat(parts, "/")
end

-- ===== 反查索引（懒构建+会话缓存；构建为一次性 pairs 遍历，实测卡顿再改分块——UnrealQuest INDEX_CHUNK 方案备用） =====
local DS_IDX = {}

local function dsRelList(rel) -- quests[id].start/end/obj 的 {U={},O={},I={}} 子表统一成 {sub,id} 数组
  local out = {}
  if type(rel) ~= "table" then return out end
  for _, sub in ipairs({ "U", "O", "I", "IR" }) do
    local t = rel[sub]
    if type(t) == "table" then
      for _, id in ipairs(t) do
        if type(id) == "number" then table.insert(out, { sub = sub, id = id }) end
      end
    end
  end
  return out
end

local function dsIdxItemQuest() -- 物品 → 关联任务 { {id=questId, how="obj|start|use"} }
  if DS_IDX.itemQuest then return DS_IDX.itemQuest end
  local idx = {}
  DS_IDX.itemQuest = idx
  local db = dsDb()
  local qs = db and db.quests
  if type(qs) ~= "table" then return idx end
  for qid, q in pairs(qs) do
    if type(qid) == "number" and type(q) == "table" then
      for _, e in ipairs(dsRelList(q["start"])) do
        if e.sub == "I" then
          idx[e.id] = idx[e.id] or {}
          table.insert(idx[e.id], { id = qid, how = "start" })
        end
      end
      if type(q.obj) == "table" then
        for _, e in ipairs(dsRelList(q.obj)) do
          if e.sub == "I" or e.sub == "IR" then
            idx[e.id] = idx[e.id] or {}
            table.insert(idx[e.id], { id = qid, how = (e.sub == "IR") and "use" or "obj" })
          end
        end
      end
    end
  end
  return idx
end

local function dsIdxUnitItem() -- 怪/NPC → 掉落物品 {itemId=rate}（items.U 反转）
  if DS_IDX.unitItem then return DS_IDX.unitItem end
  local idx = {}
  DS_IDX.unitItem = idx
  local db = dsDb()
  local its = db and db.items
  if type(its) ~= "table" then return idx end
  for iid, it in pairs(its) do
    if type(iid) == "number" and type(it) == "table" and type(it.U) == "table" then
      for uid, rate in pairs(it.U) do
        if type(uid) == "number" then
          idx[uid] = idx[uid] or {}
          idx[uid][iid] = tonumber(rate) or 0
        end
      end
    end
  end
  return idx
end

local function dsIdxObjItem() -- 对象/容器 → 内含物品 {itemId=rate}（items.O 反转）
  if DS_IDX.objItem then return DS_IDX.objItem end
  local idx = {}
  DS_IDX.objItem = idx
  local db = dsDb()
  local its = db and db.items
  if type(its) ~= "table" then return idx end
  for iid, it in pairs(its) do
    if type(iid) == "number" and type(it) == "table" and type(it.O) == "table" then
      for oid, rate in pairs(it.O) do
        if type(oid) == "number" then
          idx[oid] = idx[oid] or {}
          idx[oid][iid] = tonumber(rate) or 0
        end
      end
    end
  end
  return idx
end

local function dsIdxUnitQuest() -- 怪/NPC → 发起/结束任务 {start={ids}, fin={ids}}
  if DS_IDX.unitQuest then return DS_IDX.unitQuest end
  local idx = {}
  DS_IDX.unitQuest = idx
  local db = dsDb()
  local qs = db and db.quests
  if type(qs) ~= "table" then return idx end
  for qid, q in pairs(qs) do
    if type(qid) == "number" and type(q) == "table" then
      for _, e in ipairs(dsRelList(q["start"])) do
        if e.sub == "U" then
          idx[e.id] = idx[e.id] or { start = {}, fin = {} }
          table.insert(idx[e.id].start, qid)
        end
      end
      for _, e in ipairs(dsRelList(q["end"])) do
        if e.sub == "U" then
          idx[e.id] = idx[e.id] or { start = {}, fin = {} }
          table.insert(idx[e.id].fin, qid)
        end
      end
    end
  end
  return idx
end

-- ===== 坐标与排序工具 =====
local function dsSortedRates(map) -- {id=rate} → 按掉率降序数组
  local arr = {}
  if type(map) ~= "table" then return arr end
  for id, rate in pairs(map) do
    if type(id) == "number" then table.insert(arr, { id = id, rate = tonumber(rate) or 0 }) end
  end
  table.sort(arr, function(a, b)
    if a.rate ~= b.rate then return a.rate > b.rate end
    return a.id < b.id
  end)
  return arr
end

-- ★1.70.44 一次定位最多取几个刷新点（GetEntityLocations 的 limit）。
--   ★位置教训：它原先声明在 669 行，而 dsRecLoc 在 285 行就用它 → 读到全局 nil
--   → limit=nil → **查询上限静默失效**（可能拉回该实体的全部刷新点）。
--   由 test_engine.js 的 DECL ORDER CHECK 自动发现（不是人眼）。
local DS_MAX_PINS = 12

-- 记录坐标 → 定位数据 {x,y,zid,name,pts}。
-- 1.70.8：坐标筛选/归一改走 UnrealQuest 的 Database:GetEntityLocations(sourceType, id, areaId, limit)
-- （它内部就是「coords[i][3]==areaId 且 x/y 为数字」的同一条判断，且带 limit）；
-- 对方缺席/查不到时才回退到本地直读 coords（保持无 UnrealQuest 可用）。
local function dsRecLoc(rec, label, sourceType, sourceId)
  if type(rec) ~= "table" or type(rec.coords) ~= "table" then return nil end
  local first, pts = nil, {}
  -- 第一条有效坐标决定「去哪张图」，随后由 UnrealQuest 取该区域内的全部刷新点
  for _, c in ipairs(rec.coords) do
    if type(c) == "table" and type(c[1]) == "number" and type(c[3]) == "number" and (c[1] > 0 or (type(c[2]) == "number" and c[2] > 0)) then
      first = { x = c[1], y = c[2], zid = c[3] }
      break
    end
  end
  if not first then return nil end
  local dbMod = dsUQModule("Database")
  if dbMod and type(dbMod.GetEntityLocations) == "function" then
    local ok, locs = pcall(dbMod.GetEntityLocations, dbMod, sourceType, sourceId, first.zid, DS_MAX_PINS)
    if ok and type(locs) == "table" then
      for _, l in ipairs(locs) do table.insert(pts, { x = l.x, y = l.y }) end
    end
  end
  if table.getn(pts) == 0 then table.insert(pts, { x = first.x, y = first.y }) end
  first.name = label
  first.pts = pts
  return first
end

-- 任意实体 → 首个可定位坐标（物品=最高掉率来源；任务=起始/目标的首个单位或对象）
local function dsFirstLoc(kind, id)
  local db = dsDb()
  if not db then return nil end
  -- 定位数据自带「它指向谁」（kind/id）——地图钉 tooltip 靠它显示该点完整内容（1.70.6）。
  -- 注意：物品/任务的坐标其实来自某个子实体（掉落怪 / 起始NPC），所以标注点描述的是【那个实体】，
  -- 不是父级物品/任务本身——与「这个钉指着一只怪」的直觉一致。
  if kind == "unit" then
    local l = dsRecLoc(db.units and db.units[id], dsLocEntry("units", id), "unit", id)
    if l then l.kind = "unit" l.id = id end
    return l
  end
  if kind == "object" then
    local l = dsRecLoc(db.objects and db.objects[id], dsLocEntry("objects", id), "object", id)
    if l then l.kind = "object" l.id = id end
    return l
  end
  if kind == "quest" then
    local q = db.quests and db.quests[id]
    if type(q) ~= "table" then return nil end
    for _, rel in ipairs({ q["start"], q.obj }) do
      for _, e in ipairs(dsRelList(rel)) do
        if e.sub == "U" then
          local l = dsRecLoc(db.units and db.units[e.id], dsLocEntry("units", e.id), "unit", e.id)
          if l then l.kind = "unit" l.id = e.id l.parentKind = "quest" l.parentId = id return l end
        end
        if e.sub == "O" then
          local l = dsRecLoc(db.objects and db.objects[e.id], dsLocEntry("objects", e.id), "object", e.id)
          if l then l.kind = "object" l.id = e.id l.parentKind = "quest" l.parentId = id return l end
        end
      end
    end
    return nil
  end
  if kind == "item" then -- 物品：定位到最高掉率来源（怪优先，其次容器）
    local it = db.items and db.items[id]
    if type(it) ~= "table" then return nil end
    local au = dsSortedRates(it.U)
    if au[1] then
      local l = dsRecLoc(db.units and db.units[au[1].id], dsLocEntry("units", au[1].id), "unit", au[1].id)
      if l then l.kind = "unit" l.id = au[1].id l.parentKind = "item" l.parentId = id return l end
    end
    local ao = dsSortedRates(it.O)
    if ao[1] then
      local l = dsRecLoc(db.objects and db.objects[ao[1].id], dsLocEntry("objects", ao[1].id), "object", ao[1].id)
      if l then l.kind = "object" l.id = ao[1].id l.parentKind = "item" l.parentId = id return l end
    end
    return nil
  end
  return nil
end

-- ===== 搜索（逻辑层，可测）：前缀匹配 > 子串匹配，名称短者优先，取前 10 =====
local DS_TYPES = { "quest", "item", "unit", "object" }
local DS_BASE = { quest = "quests", item = "items", unit = "units", object = "objects" }

local function dsSub(db, kind, id) -- 结果行补充信息
  if kind == "quest" then
    local q = db.quests and db.quests[id]
    return "Lv" .. tostring((type(q) == "table" and q.lvl) or "?")
  elseif kind == "unit" then
    local u = db.units and db.units[id]
    local s = "Lv" .. tostring((type(u) == "table" and u.lvl) or "?")
    local z = dsZoneSummary(u, 1)
    if z ~= "" then s = s .. " " .. z end
    return s
  elseif kind == "object" then
    local o = db.objects and db.objects[id]
    return dsZoneSummary(o, 1)
  end
  return "#" .. tostring(id) -- item
end

local function dsScanTable(out, db, kind, base, tbl, ql, skip)
  if type(tbl) ~= "table" then return end
  for id, v in pairs(tbl) do
    if type(id) == "number" and not (skip and skip[id] ~= nil) then
      local nm = nil
      if base == "quests" and type(v) == "table" then nm = v.T
      elseif type(v) == "string" then nm = v end
      if type(nm) == "string" and nm ~= "" then
        local ln = string.lower(nm)
        local p = string.find(ln, ql, 1, true)
        if p then
          table.insert(out, {
            kind = kind, id = id, name = nm,
            score = (p == 1) and 2 or 1,
            sub = dsSub(db, kind, id),
          })
        end
      end
    end
  end
end

function EVAL_DS_SEARCH(query, ftype)
  local out = {}
  if type(query) ~= "string" then return out end
  query = string.gsub(query, "^%s*(.-)%s*$", "%1")
  if query == "" then return out end
  local db = dsDb()
  if not db then return out end
  local ql = string.lower(query)
  local lang = dsLang()
  local types = (ftype and DS_BASE[ftype]) and { ftype } or DS_TYPES
  for _, kind in ipairs(types) do
    local base = DS_BASE[kind]
    local loc = db[base .. "_" .. lang]
    local en = db[base .. "_enUS"]
    dsScanTable(out, db, kind, base, loc, ql, nil)
    if lang ~= "enUS" and type(en) == "table" then -- enUS 兜底：主语言表没有的条目
      dsScanTable(out, db, kind, base, en, ql, (type(loc) == "table") and loc or nil)
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if string.len(a.name) ~= string.len(b.name) then return string.len(a.name) < string.len(b.name) end
    return a.id < b.id
  end)
  while table.getn(out) > 10 do table.remove(out) end
  for _, r in ipairs(out) do r.loc = dsFirstLoc(r.kind, r.id) end -- 地图图标数据（截断后再解析，省无效计算）
  return out
end

-- ===== 详情模型（逻辑层，可测）：无限级联——只要有关联就挂 link（用户实测要求，原 2 级上限取消）；hoverItem 供悬停 tooltip =====
local function dsLine(lines, text, kind, id, depth, loc)
  local ln = { text = text }
  if kind and id then
    ln.link = { kind = kind, id = id }
    ln.loc = dsFirstLoc(kind, id)
  end
  if loc then ln.loc = loc end
  if kind == "item" and id then ln.hoverItem = id end
  table.insert(lines, ln)
end

local function dsFacText(fac)
  if fac == "A" then return L("DS_FAC_A") end
  if fac == "H" then return L("DS_FAC_H") end
  return L("DS_FAC_AH")
end

local function dsItemKind(id) -- 物品种类 best-effort（GetItemInfo 只读本地缓存；pcall 不套 and/or——1.64.0 教训）
  if type(GetItemInfo) ~= "function" then return nil end
  local ok, _1, _2, _3, _4, itype, isub = pcall(GetItemInfo, id)
  if not ok or not itype then return nil end
  if isub and isub ~= itype then return itype .. "/" .. isub end
  return itype
end

-- 各区块条目上限（1.70.4：视图支持滚动后放开——旧版 掉落8/容器4/商人4/任务4 会把「商人出售」等区块截没，用户实测反馈行数不够）
local DS_CAP = { drop = 30, container = 15, vendor = 15, itemquest = 10, unitdrop = 30, unitquest = 8, questrel = 8, reqitem = 15, objcontain = 15 }

local DS_DETAIL = {}

DS_DETAIL.item = function(db, id, depth, d)
  local it = db.items and db.items[id]
  d.subtitle = L("DS_KIND") .. ": " .. (dsItemKind(id) or L("DS_UNKNOWN")) .. "  #" .. tostring(id)
  if type(it) ~= "table" then return end
  if type(it.U) == "table" then
    dsLine(d.lines, L("DS_DROP_SRC"))
    local n = 0
    for _, e in ipairs(dsSortedRates(it.U)) do
      local nm = dsLocEntry("units", e.id) or ("#" .. tostring(e.id))
      local z = dsZoneSummary(db.units and db.units[e.id], 2)
      dsLine(d.lines, string.format("%s  %s %.1f%%  %s", nm, L("DS_RATE"), e.rate, z), "unit", e.id, depth)
      n = n + 1
      if n >= DS_CAP.drop then break end
    end
  end
  if type(it.O) == "table" then
    dsLine(d.lines, L("DS_CONTAINED"))
    local n = 0
    for _, e in ipairs(dsSortedRates(it.O)) do
      local nm = dsLocEntry("objects", e.id) or ("#" .. tostring(e.id))
      dsLine(d.lines, string.format("%s  %.1f%%", nm, e.rate), "object", e.id, depth)
      n = n + 1
      if n >= DS_CAP.container then break end
    end
  end
  if type(it.V) == "table" then
    dsLine(d.lines, L("DS_SOLD_BY"))
    local n = 0
    for _, e in ipairs(dsSortedRates(it.V)) do
      local nm = dsLocEntry("units", e.id) or ("#" .. tostring(e.id))
      dsLine(d.lines, nm, "unit", e.id, depth)
      n = n + 1
      if n >= DS_CAP.vendor then break end
    end
  end
  local rel = dsIdxItemQuest()[id]
  if type(rel) == "table" and table.getn(rel) > 0 then
    dsLine(d.lines, L("DS_REL_QUEST"))
    local n = 0
    for _, e in ipairs(rel) do
      local nm = dsLocEntry("quests", e.id) or ("#" .. tostring(e.id))
      local q = db.quests and db.quests[e.id]
      local lv = (type(q) == "table" and q.lvl) and ("Lv" .. tostring(q.lvl) .. " ") or ""
      dsLine(d.lines, string.format("%s%s（%s）", lv, nm, L("DS_HOW_" .. string.upper(e.how or "obj"))), "quest", e.id, depth)
      n = n + 1
      if n >= DS_CAP.itemquest then break end
    end
  end
end

DS_DETAIL.unit = function(db, id, depth, d)
  local u = db.units and db.units[id]
  local lvl = (type(u) == "table" and u.lvl) or "?"
  local fac = (type(u) == "table" and u.fac) or "AH"
  d.subtitle = L("DS_LEVEL") .. ": " .. tostring(lvl) .. "  " .. L("DS_FAC") .. ": " .. dsFacText(fac) .. "  #" .. tostring(id)
  local z = dsZoneSummary(u, 3)
  if z ~= "" then dsLine(d.lines, L("DS_ZONE_S") .. ": " .. z, nil, nil, depth, dsFirstLoc("unit", id)) end
  local drops = dsSortedRates(dsIdxUnitItem()[id])
  if table.getn(drops) > 0 then
    dsLine(d.lines, L("DS_DROPS_ITEM"))
    local n = 0
    for _, e in ipairs(drops) do
      local nm = dsLocEntry("items", e.id) or ("#" .. tostring(e.id))
      dsLine(d.lines, string.format("%s  %.1f%%", nm, e.rate), "item", e.id, depth)
      n = n + 1
      if n >= DS_CAP.unitdrop then break end
    end
  end
  local uq = dsIdxUnitQuest()[id]
  if type(uq) == "table" then
    if table.getn(uq.start) > 0 then
      dsLine(d.lines, L("DS_GIVE_QUEST"))
      local n = 0
      for _, qid in ipairs(uq.start) do
        dsLine(d.lines, dsLocEntry("quests", qid) or ("#" .. tostring(qid)), "quest", qid, depth)
        n = n + 1
        if n >= DS_CAP.unitquest then break end
      end
    end
    if table.getn(uq.fin) > 0 then
      dsLine(d.lines, L("DS_END_QUEST"))
      local n = 0
      for _, qid in ipairs(uq.fin) do
        dsLine(d.lines, dsLocEntry("quests", qid) or ("#" .. tostring(qid)), "quest", qid, depth)
        n = n + 1
        if n >= DS_CAP.unitquest then break end
      end
    end
  end
end

DS_DETAIL.quest = function(db, id, depth, d)
  local q = db.quests and db.quests[id]
  local lv = (type(q) == "table" and q.lvl) or "?"
  d.subtitle = L("DS_LEVEL") .. ": " .. tostring(lv) .. "  #" .. tostring(id)
  local loc = dsQuestLoc(id)
  if loc and type(loc.O) == "string" and loc.O ~= "" then dsLine(d.lines, L("DS_OBJTXT") .. loc.O) end
  if loc and type(loc.D) == "string" and loc.D ~= "" then
    local t = loc.D
    if string.len(t) > 90 then t = string.sub(t, 1, 90) .. "…" end
    dsLine(d.lines, L("DS_DESC") .. t)
  end
  if type(q) ~= "table" then return end
  local function relLines(rel, header, maxn)
    local es = dsRelList(rel)
    if table.getn(es) == 0 then return end
    dsLine(d.lines, header)
    local n = 0
    for _, e in ipairs(es) do
      local kind = (e.sub == "U") and "unit" or ((e.sub == "O") and "object" or "item")
      local nm = dsLocEntry(DS_BASE[kind], e.id) or ("#" .. tostring(e.id))
      dsLine(d.lines, nm, kind, e.id, depth)
      n = n + 1
      if n >= (maxn or DS_CAP.questrel) then break end
    end
  end
  relLines(q["start"], L("DS_STARTNPC"), DS_CAP.questrel)
  relLines(q["end"], L("DS_ENDNPC"), DS_CAP.questrel)
  if type(q.obj) == "table" then
    local its = {}
    for _, e in ipairs(dsRelList(q.obj)) do
      if e.sub == "I" or e.sub == "IR" then table.insert(its, e.id) end
    end
    if table.getn(its) > 0 then
      dsLine(d.lines, L("DS_REQ_ITEM"))
      local n = 0
      for _, iid in ipairs(its) do
        dsLine(d.lines, dsLocEntry("items", iid) or ("#" .. tostring(iid)), "item", iid, depth)
        n = n + 1
        if n >= DS_CAP.reqitem then break end
      end
    end
  end
end

DS_DETAIL.object = function(db, id, depth, d)
  local o = db.objects and db.objects[id]
  d.subtitle = "#" .. tostring(id)
  local z = dsZoneSummary(o, 3)
  if z ~= "" then dsLine(d.lines, L("DS_ZONE_S") .. ": " .. z, nil, nil, depth, dsFirstLoc("object", id)) end
  local its = dsSortedRates(dsIdxObjItem()[id])
  if table.getn(its) > 0 then
    dsLine(d.lines, L("DS_CONTAINED"))
    local n = 0
    for _, e in ipairs(its) do
      dsLine(d.lines, string.format("%s  %.1f%%", dsLocEntry("items", e.id) or ("#" .. tostring(e.id)), e.rate), "item", e.id, depth)
      n = n + 1
      if n >= DS_CAP.objcontain then break end
    end
  end
end

function EVAL_DS_DETAIL(kind, id, depth)
  local db = dsDb()
  if not db then return nil end
  if type(DS_BASE[kind]) ~= "string" then return nil end
  depth = depth or 1
  local d = { kind = kind, id = id, title = dsLocEntry(DS_BASE[kind], id) or ("#" .. tostring(id)), subtitle = "", lines = {} }
  local fn = DS_DETAIL[kind]
  if type(fn) == "function" then pcall(fn, db, id, depth, d) end
  return d
end

-- ===== 图标与地图定位 =====
-- 类型图标用 UnrealQuest 自带素材（硬依赖对方已装）；物品优先真实图标（GetItemInfo 第9返回=纹理，1.12 已验证）
-- ★本客户端实测：附加素材 TGA 路径【必须无扩展名】且插件名小写——带 .tga 后缀会静默什么都不画
-- （UnrealQuest ClientAPI 注释实证：textures.addon_tga_paths_require_extensionless；同一坑导致地图图标不可见）
local DS_ICON_ROOT = "Interface\\AddOns\\unrealQuest\\media\\icons\\"
local DS_ICON = {
  quest = DS_ICON_ROOT .. "questIcon",
  unit = DS_ICON_ROOT .. "rares",   -- 普通生物/ NPC（UnrealQuest 的 Rare/Elite/Boss 行本体图标）
  object = DS_ICON_ROOT .. "chests",
  item = DS_ICON_ROOT .. "database",
}
-- 生物按自身 rank 换用更精确的图标（与 UnrealQuest RANK_ICONS 同语义：1=精英 2=稀有精英 3=Boss 4=稀有）
local DS_RANK_ICON = {
  ["1"] = DS_ICON_ROOT .. "elite-mobs",
  ["2"] = DS_ICON_ROOT .. "elite-mobs",
  ["3"] = DS_ICON_ROOT .. "boss-mobs",
  ["4"] = DS_ICON_ROOT .. "rare-mobs",
}
-- 地图图标用「小地图目标圆点」（media\QuestDot）而不是 quest-marker 的黄色感叹号——
-- 后者与左侧「链接指向」类型图标里的任务感叹号视觉撞车（用户实测反馈容易混）。
-- 圆点=「在地图上定位」，类型图标=「这行指向什么」，两者形状/位置都区分开。
local DS_MAP_ICON = "Interface\\AddOns\\unrealQuest\\media\\QuestDot"
-- 采集点标注用的小圆点（= 上面同一素材，独立命名以便语义清晰）与尺寸（照抄对方 NODE_WORLD_PIN_SIZE=15/2）
local DS_NODE_DOT_TEXTURE = DS_MAP_ICON
local DS_NODE_PIN_SIZE = 8
local DS_MAP_PIN_ICON = DS_ICON_ROOT .. "quest-marker" -- 真正打在世界地图上的标记仍用钉形

-- ★类别图标根路径：**必须无扩展名**（本客户端带 .tga 会静默什么都不画，见记忆体「素材路径铁律」）。
--   抄自 UnrealQuest ClientAPI.lua:10226 的 NPC_SERVICE_ICON_ROOT。
local DS_ANN_ICON_ROOT = "Interface\\AddOns\\unrealQuest\\media\\icons\\"
-- 图标钉用对方完整尺寸 WORLD_PIN_SIZE=15；采集/节点类用半尺寸（NODE_WORLD_PIN_SIZE=7.5≈8），
-- 否则一个区域上千个图标会糊成一片。
local DS_ANN_ICON_SIZE = 15
local DS_ANN_ICON_SIZE_SMALL = 8

local function dsKindIcon(kind, id)
  if kind == "item" and type(GetItemInfo) == "function" then
    local ok, _1, _2, _3, _4, _5, _6, _7, tex = pcall(GetItemInfo, id) -- 第9返回=纹理；pcall 不套 and/or
    if ok and type(tex) == "string" and tex ~= "" then return tex end
  end
  if kind == "unit" then -- 有 rank 的生物用精确图标（精英/Boss/稀有），否则通用生物图标
    local db = dsDb()
    local u = db and db.units and db.units[id]
    local rk = type(u) == "table" and tostring(u.rnk or "") or ""
    if DS_RANK_ICON[rk] then return DS_RANK_ICON[rk] end
  end
  return DS_ICON[kind]
end
function EVAL_DS_ICON_PATH(kind, id) return dsKindIcon(kind, id) end -- 测试直调（图标路径按 rank 选择）
function EVAL_DS_MAP_ICON_PATH() return DS_MAP_ICON end -- 测试直调（行尾「在地图上定位」按钮素材）
function EVAL_DS_MAP_PIN_PATH() return DS_MAP_PIN_ICON end -- 测试直调（世界地图上的图钉素材）

-- 统一标注层的钉子池定义在下方「统一地图标注层」段（dsAnnPins）。
-- DS_MAX_PINS 已上移到共享状态块（★1.70.44）：它被上方 dsRecLoc 读作
-- GetEntityLocations 的 limit，原先声明在此处 → dsRecLoc 读到的是全局 nil
-- → limit=nil → **查询上限静默失效**（一次定位可能拉回该实体的全部刷新点）。

-- 标注点 tooltip 内容（数据来源=该点指向的实体，与详情页同一套模型）：
-- 表头（青色名称）→ 属性行（等级/阵营/区域）→ 关联块（掉落物品 / 提供任务 / 来源怪 …），
-- 行格式与 UnrealQuest RenderTooltipLines 一致：{text=,r,g,b} / {left=,right=,rightR..} / {separator=true}。
local function dsPinTooltipLines(info)
  local lines = {}
  if type(info) ~= "table" then return lines end
  local db = dsDb()
  local kind, id = info.kind, info.id
  table.insert(lines, { text = tostring(info.name or "?"), r = 0.3, g = 1, b = 0.8 }) -- 青色标题（同任务插件风格）
  if info.zone then
    table.insert(lines, { left = L("DS_ZONE_S"), right = tostring(info.zone), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 })
  end
  table.insert(lines, { left = L("DS_COORD"), right = string.format("%.1f, %.1f", info.x or 0, info.y or 0), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 })
  if not db or not kind or not id then return lines end
  if kind == "unit" then
    local u = db.units and db.units[id]
    if type(u) == "table" then
      if u.lvl then table.insert(lines, { left = L("DS_LEVEL"), right = tostring(u.lvl), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 }) end
      table.insert(lines, { left = L("DS_FAC"), right = dsFacText(u.fac or "AH"), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 })
    end
    local drops = dsSortedRates(dsIdxUnitItem()[id])
    if table.getn(drops) > 0 then
      table.insert(lines, { separator = true })
      table.insert(lines, { text = L("DS_DROPS_ITEM"), r = 1, g = 0.82, b = 0 })
      local n = 0
      for _, e in ipairs(drops) do
        table.insert(lines, { left = dsLocEntry("items", e.id) or ("#" .. tostring(e.id)), right = string.format("%.1f%%", e.rate), r = 1, g = 1, b = 1, rightR = 0.3, rightG = 1, rightB = 0.3 })
        n = n + 1
        if n >= 5 then break end
      end
    end
    local uq = dsIdxUnitQuest()[id]
    if type(uq) == "table" and table.getn(uq.start) > 0 then
      table.insert(lines, { separator = true })
      table.insert(lines, { text = L("DS_GIVE_QUEST"), r = 1, g = 0.82, b = 0 })
      local n = 0
      for _, qid in ipairs(uq.start) do
        table.insert(lines, { text = "[!] " .. (dsLocEntry("quests", qid) or ("#" .. tostring(qid))), r = 1, g = 0.82, b = 0 })
        n = n + 1
        if n >= 5 then break end
      end
    end
  elseif kind == "object" then
    local its = dsSortedRates(dsIdxObjItem()[id])
    if table.getn(its) > 0 then
      table.insert(lines, { separator = true })
      table.insert(lines, { text = L("DS_CONTAINED"), r = 1, g = 0.82, b = 0 })
      local n = 0
      for _, e in ipairs(its) do
        table.insert(lines, { left = dsLocEntry("items", e.id) or ("#" .. tostring(e.id)), right = string.format("%.1f%%", e.rate), r = 1, g = 1, b = 1, rightR = 0.3, rightG = 1, rightB = 0.3 })
        n = n + 1
        if n >= 5 then break end
      end
    end
  elseif kind == "item" then
    local it = db.items and db.items[id]
    table.insert(lines, { left = L("DS_KIND"), right = dsItemKind(id) or L("DS_UNKNOWN"), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 })
    if type(it) == "table" and type(it.U) == "table" then
      local u = dsSortedRates(it.U)
      if u[1] then
        table.insert(lines, { separator = true })
        table.insert(lines, { text = L("DS_DROP_SRC"), r = 1, g = 0.82, b = 0 })
        local n = 0
        for _, e in ipairs(u) do
          table.insert(lines, { left = dsLocEntry("units", e.id) or ("#" .. tostring(e.id)), right = string.format("%.1f%%", e.rate), r = 1, g = 1, b = 1, rightR = 0.3, rightG = 1, rightB = 0.3 })
          n = n + 1
          if n >= 5 then break end
        end
      end
    end
  elseif kind == "quest" then
    local loc = dsQuestLoc(id)
    if loc and type(loc.O) == "string" and loc.O ~= "" then
      table.insert(lines, { text = loc.O, r = 1, g = 1, b = 1, wrap = true })
    end
    local q = db.quests and db.quests[id]
    if type(q) == "table" and q.lvl then
      table.insert(lines, { left = L("DS_LEVEL"), right = tostring(q.lvl), r = 0.65, g = 0.65, b = 0.65, rightR = 1, rightG = 1, rightB = 1 })
    end
  end
  return lines
end

-- ===== 复用 UnrealQuest 的图钉设施（1.70.8：删除自绘图钉，减少本插件代码量）=====
-- 全部走它的公开 API：
--   Client.CreateWorldMapPin(i, r,g,b)   画布子帧+尺寸+层级+贴图+鼠标，一步到位（原来我们自己 CreateFrame/SetTexture/SetFrameLevel/EnableMouse）
--   Client.SetWorldMapPinTexture/Size    换素材与大小
--   Client.SetWorldMapPinHandlers(f, onEnter,onLeave,onClick)  鼠标回调（含 RegisterForClicks 处理）
--   MapContext:PlaceOnWorldMap(f, x, y)  归一化坐标(0..1)直接放到画布（原来自己算 x/100*width）
--   Client.ShowMapTooltip/HideMapTooltip tooltip（正确解析 WorldMapTooltip，见 1.70.6 记录）
-- 1.70.9 硬依赖：tooltip 直接交给 UnrealQuest（它内部解析正确的帧：地图画布上必须用 WorldMapTooltip，见 1.70.6 记录）
local function dsShowPinTooltip(f)
  local info = f and f.dsInfo
  if type(info) ~= "table" then return end
  local c = dsUQClient()
  if c and type(c.ShowMapTooltip) == "function" then
    pcall(c.ShowMapTooltip, f, dsPinTooltipLines(info), "ANCHOR_RIGHT")
  end
end

local function dsHidePinTooltip(f)
  local c = dsUQClient()
  if c and type(c.HideMapTooltip) == "function" then pcall(c.HideMapTooltip, f) end
end

function EVAL_DS_NAV() return DS.nav end -- 测试直调（级联栈）
function EVAL_DS_TEST_STATE(k)
  if k == "results" then return table.getn(DS.results or {}) end
  if k == "detOff" then return DS.detOff or 0 end
  if k == "lastQuery" then return DS.lastQuery or "" end
  if k == "nav" then return table.getn(DS.nav or {}) end
  return nil
end
function EVAL_DS_PIN_TOOLTIP_LINES(info) return dsPinTooltipLines(info) end -- 测试直调（定义必须在本 local 之后——Lua local 作用域从声明后开始）

-- ★★★标注层的全部共享状态：**必须声明在任何一个使用它的函数之前**。
--   本文件因「Lua local 从声明语句之后才可见」已多次踩坑，每一次都是同一形态——
--   「某个函数读到了全局 nil：不报错、pcall 全成功、但行为是错的」：
--     · dsPersist 读 dsAnnOn（开关持久化静默失效）
--     · dsTick 读它自己（引擎停摆，1.70.39）
--     · DSL_ROW_BTN_Y 被 filterBtn 读（按钮整颗消失，1.70.41）
--     · ★dsAnnOverlay / dsAnnLastFail / dsAnnPlaceLog（1.70.44 实测定案）：
--       dsOverlayStr/dsSetOverlay 定义在声明之前 → 绑定到**全局**（写入成功）；
--       dsAnnDraw/REFRESH 定义在声明之后 → 读的是**局部**（恒 nil）。
--       症状：同一帧日志里「覆盖=草刺野猪(21点)」与「强制重绘：层已关且**无覆盖层**」并存，
--       结果定位圆点永远画不出来 —— **一个变量被两批函数分别绑到了两个位置**。
--   ★因此位置不能再按「只需在 dsPersist 之前」来挑：要在**整个文件里最早的使用点之前**。
--     test_engine.js 的 DECL ORDER CHECK 会系统性地守住这条（不再靠人肉眼）。
local dsAnnPins = {}          -- 唯一钉子池
local dsAnnSig = nil          -- 当前已绘制的地图签名（areaId）
local dsAnnOn = false         -- 分类标注层总开关
local dsAnnShown = {}         -- 本次绘制实际显示的类别（用于计数/诊断）
local dsAnnOverlay = nil      -- 搜索结果定位覆盖（{areaId=, pts={...}}），与分类层共存于同一池
local DS_ANN_MAX = 500        -- 单区域上限（用户实测反馈：200 太少，杜隆塔尔实际 466 个采集点）
local dsAnnTick, dsAnnHb, dsAnnSameT = 0, 0, 0
-- ★ 1.70.40：dsAnnForcedT / dsAnnSlowT / dsAnnCandSig / dsAnnCandT 已随三件套一起删除。
--   重绘时机现在只由「签名是否变化」决定，不再有额外的计时状态。
-- ★1.70.42 自愈机制的两个状态（用户实测「点定位后地图空白」）：
--   dsAnnLastDrawn = 上次绘制**打算**放几个点（含放置失败的）；dsAnnHealT = 上次自愈时刻。
--   语义与已删除的三件套不同：它**先校验再修复**——只有「上次该画出点、此刻却一个都
--   不可见」才重画一次（2s 节流），正常情况（该画 0 点 / 钉子都在）完全不出手。
local dsAnnLastDrawn = 0
local dsAnnHealT = 0
local dsAnnLastFail = 0    -- 上次绘制中放置失败的点数（诚实放置 1.70.35：失败即 Hide）
local dsAnnPlaceLog = nil  -- 上次绘制中首个失败点的信息（诊断用，最多记一条）
-- ★1.70.42 绘制次数计数器：断言「到底有没有重建」时，不能拿「有没有查库」当代理——
--   空结果场景下即使重建也不会查库，于是变异体（去掉 lastDrawn 门控）会静默存活。
--   要保的性质是「重建发生了吗」，就必须直接数重建。
local dsAnnDrawCount = 0
local dsAnnTruncated = false   -- 本次绘制是否触顶（用于诊断/提示，避免静默截断）
local dsTestEmptyResults = nil -- 测试专用：令分类层查询返回空集，用于构造「0 点重绘」

-- 覆盖层的可诊断摘要（日志 / HUD / /eh ds 共用）。
-- ★1.70.42 起因：用户实测「点定位后地图空白」，而这条链路上任何一个环节静默失败
--   （loc 无效 / ShowAreas 切不过去 / 覆盖层 areaId 与当前视图不符 / 放置全失败）都无迹可查。
local function dsOverlayStr()
  local ov = dsAnnOverlay
  if type(ov) ~= "table" then return "覆盖=无" end
  local n = type(ov.pts) == "table" and table.getn(ov.pts) or 0
  return "覆盖=" .. tostring(ov.name) .. "(areaId=" .. tostring(ov.areaId)
    .. " " .. tostring(ov.kind) .. "#" .. tostring(ov.id) .. " " .. n .. "点)"
end

-- 搜索结果定位：不再自建钉子，改为记入「覆盖层」交给统一标注层绘制（1.70.19）。
-- 旧实现有自己的 12 枚池 + 60s 自熄，表现为「切图不隐藏、只能等一分钟」——与用户要求的
-- 「所有标注都和地图绑定」冲突。现在它只是统一层的一份额外数据：
--   dsAnnOverlay = { areaId=, name=, kind=, id=, pts={ {x,y}, ... } }
-- 切图后由统一层按 areaId 决定显示与否，切回同一张图会自动重新出现。
local function dsSetOverlay(loc)
  if type(loc) ~= "table" or type(loc.zid) ~= "number" then
    dsAnnOverlay = nil
    return false
  end
  local pts = loc.pts
  if type(pts) ~= "table" or table.getn(pts) == 0 then pts = { { x = loc.x, y = loc.y } } end
  dsAnnOverlay = {
    areaId = loc.zid, name = loc.name, kind = loc.kind, id = loc.id,
    parentKind = loc.parentKind, parentId = loc.parentId, pts = pts,
  }
  return true
end

-- ===== 日志基础件（1.70.42 上移到这里）=====
-- ★必须定义在 EVAL_DS_SHOWMAP（下方）**之前**：本项目已 11 次踩「Lua local 从声明语句之后
--   才可见」的坑——1.70.42 首版把 dsLog 调用加进 SHOWMAP 而 dsLog 定义在 900 行之后，
--   运行时读到全局 nil 直接 attempt to call a nil value（测试当场抓到）。
-- ★dsLog 与 dsLogAlways 的分工（频率防护总则同样适用于日志）：
--   · dsLog      = trace 门控：tick/心跳这类**高频或常态**路径，只在 /eh ds trace 期间记录。
--   · dsLogAlways = 不门控：**用户点击驱动**（定位）或**异常才触发**（自愈/失败）的路径，
--     天然低频，诊断价值高，不该要求用户「先开 trace 才能取证」。
local dsTrace = false           -- 轨迹日志开关（/eh ds trace）
local DS_TRACE_TTL = 600        -- trace 自动过期（秒）
local dsTraceUntil = 0
local function dsLog(msg)
  if not dsTrace then return end
  if type(EVAL_LOGLINE) == "function" then EVAL_LOGLINE("[DS] " .. tostring(msg)) end
end
local function dsLogAlways(msg)
  if type(EVAL_LOGLINE) == "function" then EVAL_LOGLINE("[DS] " .. tostring(msg)) end
end

-- 打开世界地图并定位到 {x,y,zid} 并在地图上标注。
-- 1.70.9 硬依赖简化：只走 UnrealQuest 的成熟链路（QuestClicks:RevealOnMap 同款），不再维护自实现副本——
-- 本 Tab 的数据本就来自 UnrealQuestData，没有对方时整页只显示引导提示，故无需平行实现。
-- 流程（UnrealQuest/Quest/QuestClicks.lua:381 RevealOnMap）：
--   1) Client.OpenWorldMap()            开图（ShowUIPanel(WorldMapFrame) 封装；绝不 ToggleWorldMap——IsShown 不可靠会把玩家已开的图关掉）
--   2) MapContext:ShowAreas({areaId})   移动视图（内部处理：先 SetMapZoom(continent) 再读 GetMapZones——本客户端该函数忽略参数只答选中大陆；
--                                       按本地化名匹配 zone 索引；读回校验；已有视图命中则不动）
--   3) MapContext:ParkView(areaId)      标记「有意移动」——否则冷启动 primer（登录后 zoneIndex 0 歧义态）会把视图拉回玩家所在地
--   4) dsSetOverlay：把定位点记入标注层覆盖数据（绘制由统一标注层负责，见下方）
function EVAL_DS_SHOWMAP(loc)
  if type(loc) ~= "table" or type(loc.zid) ~= "number" then
    dsLogAlways("定位失败：loc 无效 type=" .. type(loc) .. " zid=" .. tostring(type(loc) == "table" and loc.zid or nil))
    return false
  end
  -- ★1.70.42 全链路日志（用户实测「点定位后地图空白」，逐段留痕）：本条链路是**用户点击驱动**，
  --   频率天然受限（人一秒点不了几次），不适用 tick 类日志的频率防护降频。
  dsLogAlways("定位开始：" .. tostring(loc.name) .. " kind=" .. tostring(loc.kind) .. " id=" .. tostring(loc.id)
    .. " zid=" .. tostring(loc.zid) .. " x=" .. tostring(loc.x) .. " y=" .. tostring(loc.y)
    .. " pts=" .. tostring(type(loc.pts) == "table" and table.getn(loc.pts) or 0))
  local client = dsUQClient()
  local mc = dsUQModule("MapContext")
  if not client or not mc or type(mc.ShowAreas) ~= "function" then
    dsLogAlways("定位失败：UnrealQuest 的 Client/MapContext 不可用")
    return false
  end
  if type(client.OpenWorldMap) == "function" then pcall(client.OpenWorldMap) end
  local ok, shown, how = pcall(mc.ShowAreas, mc, { loc.zid })
  dsLogAlways("ShowAreas(zid=" .. tostring(loc.zid) .. ") → ok=" .. tostring(ok) .. " shown=" .. tostring(shown) .. " how=" .. tostring(how))
  if not ok or shown == nil then
    dsLogAlways("定位失败：该区域在这张图上列不出来（对方也切不过去），未记覆盖层")
    return false
  end
  if how == "switched" and type(mc.ParkView) == "function" then
    pcall(mc.ParkView, mc, shown) -- 顺序同 QuestClicks：必须在重绘前 park
    dsLogAlways("ParkView → " .. tostring(shown))
  end
  dsSetOverlay(loc)   -- 记入覆盖层，由统一标注层负责绘制（含地图绑定）
  dsLogAlways(dsOverlayStr())
  local n = EVAL_DS_ANN_REFRESH()
  dsLogAlways("定位后重绘 共 " .. tostring(n) .. " 点（失败 " .. tostring(dsAnnLastFail) .. "）"
    .. (dsAnnPlaceLog and (" " .. dsAnnPlaceLog) or ""))
  return true
end


-- ===== 标注类别表（1.70.19 统一标注层）=====
-- 数据源 Database:GetAreaServiceLocations(areaId, classId, raceId, wanted)：
--   · 服务类 11 种【默认就返回，不占 wanted 门槛】（Database.lua:1450-1466 的 meta 关系）
--   · 节点类 5 种【数量大，需 wanted 申请】（Database.lua:1478-1484 NODE_META_KEYS）
-- 全部 16 类共用同一套图钉设施；分类配色照抄 UnrealQuest NpcPins。
-- ★icon 字段 = 该类别在世界地图上的专属图标文件（UnrealQuest media\icons\ 下，无需扩展名）。
--   素材名逐个抄自 UnrealQuest Map\NpcPins.lua 的 CATEGORIES 表（1.70.26），不自行拼写——
--   本客户端素材路径写错是【静默不画】（见记忆体「素材路径铁律」），抄错一个字母就只剩空气。
--   small = 采集/节点类，用 UnrealQuest 的 NODE_WORLD_PIN_SIZE(7.5) 半尺寸，避免上千点糊成一片。
local DS_ANN_CATS = {
  -- 节点类（默认关：一个区域可达上千个）
  { k = "herbs",        label = "草药",   group = "node", def = false, icon = "herbs",       small = true,  color = { 0.40, 0.85, 0.35 } },
  { k = "mines",        label = "矿脉",   group = "node", def = false, icon = "mines",       small = true,  color = { 0.80, 0.62, 0.40 } },
  { k = "chests",       label = "宝箱",   group = "node", def = false, icon = "chests",                     color = { 1.00, 0.82, 0.35 } },
  { k = "fish",         label = "鱼群",   group = "node", def = false, icon = "fish",                       color = { 0.35, 0.70, 0.95 } },
  { k = "rares",        label = "稀有怪", group = "node", def = false, icon = "rares",                      color = { 0.95, 0.35, 0.35 } },
  -- 服务类（默认开：数量少、找起来最有用）
  { k = "flight",       label = "飞行点", group = "svc",  def = true,  icon = "flight",                     color = { 0.30, 0.85, 0.85 } },
  { k = "innkeeper",    label = "旅店",   group = "svc",  def = true,  icon = "innkeeper",                  color = { 0.95, 0.75, 0.30 } },
  { k = "mailbox",      label = "邮箱",   group = "svc",  def = true,  icon = "mailbox",                    color = { 0.95, 0.95, 0.95 } },
  { k = "banker",       label = "银行",   group = "svc",  def = false, icon = "banker",                     color = { 0.85, 0.85, 0.55 } },
  { k = "auctioneer",   label = "拍卖",   group = "svc",  def = false, icon = "auctioneer",                 color = { 0.70, 0.55, 0.95 } },
  { k = "vendor",       label = "商人",   group = "svc",  def = false, icon = "vendor",                     color = { 0.55, 0.85, 0.55 } },
  { k = "repair",       label = "修理",   group = "svc",  def = true,  icon = "repair",                     color = { 0.80, 0.80, 0.80 } },
  { k = "stablemaster", label = "兽栏",   group = "svc",  def = true,  icon = "stablemaster",               color = { 0.85, 0.65, 0.45 } },
  { k = "spirithealer", label = "灵魂医者", group = "svc", def = true, icon = "spirithealer",               color = { 0.60, 0.90, 1.00 } },
  { k = "meetingstone", label = "集合石", group = "svc",  def = false, icon = "meetingstone",               color = { 0.75, 0.75, 0.90 } },
  { k = "battlemaster", label = "战场",   group = "svc",  def = false, icon = "battlemaster",               color = { 0.90, 0.60, 0.60 } },
}

-- 稀有怪按 rank 换脸（照抄对方 RANK_ICONS）：精英/稀有精英=elite-mobs、Boss=boss-mobs、稀有=rare-mobs。
local DS_ANN_RANK_ICON = {
  [1] = "elite-mobs", [2] = "elite-mobs", [3] = "boss-mobs", [4] = "rare-mobs",
}
local DS_ANN_DEFCOLOR = { 0.85, 0.85, 0.85 } -- 未知类别兜底色
local DS_ANN_COLOR = {}   -- category -> {r,g,b}
local DS_ANN_BYKEY = {}   -- category -> 定义
for _, c in ipairs(DS_ANN_CATS) do
  DS_ANN_COLOR[c.k] = c.color
  DS_ANN_BYKEY[c.k] = c
end

-- ===== 统一地图标注层（1.70.19 重构）=====
-- 用户需求（原话）：所有在地图上的标注信息都要和地图绑定——切换之后标注要更新隐藏，
-- 切回地图要根据当前地图重新显示；不单是矿石，所有标注信息都可能是跨地图的；再加一个清理标注功能。
--
-- 旧结构的问题：地图上并存两套互不相通的钉子——
--   dsPins（搜索结果定位，12 个，60s 自熄，不绑地图） + dsNodePins（采集点，200 个，绑地图）
-- 表现为「搜索定位的钉切图不隐藏、只能等 60 秒」，且节点层只认花草矿宝 4 类。
--
-- 新结构：**一套池子 + 一个「当前地图」概念**。
--   · 同一池 dsAnnPins 承接全部标注（分类层 + 搜索结果定位），不再有发射后不管的孤儿钉。
--   · 每次重绘都是「清空整层 → 按当前地图重建」，天然满足「切走隐藏、切回重建」。
--   · 跨地图条目：定位时用条目自己的 areaId 打开对应地图（方案 A，与 UnrealQuest 一致）。

-- ===== 共享基础件（日志件已上移到 EVAL_DS_SHOWMAP 之前，1.70.42）=====

-- WorldMapFrame:IsShown() 在本客户端【两个方向都不可靠】，禁止用它做逻辑判断（1.70.17 定案）：
--   ClientAPI.lua:8664「do not reliably reflect this client's fullscreen presentation」
--   MapContext.lua:696「recorded leaving WorldMapFrame's shown state TRUE after it closes」
-- 仅保留给 /eh ds 做参考显示，绝不进分支。
local function dsMapShown()
  local f = WorldMapFrame
  if type(f) ~= "table" or type(f.IsShown) ~= "function" then return nil end
  local ok, s = pcall(f.IsShown, f)
  if not ok then return nil end
  return s and true or false
end


-- 持久化（图层开关 + trace；类别开关由 EVAL_DS_SET_CAT 直接写 cfg.ds.cats）
local function dsPersist()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return end
  if type(c.ds) ~= "table" then c.ds = {} end
  c.ds.nodes = dsAnnOn
  c.ds.trace = dsTrace
end

-- 类别表见上方 DS_ANN_CATS（16 类：节点类 5 + 服务类 11）

-- 类别开关状态：cfg.ds.cats[category] = boolean（缺省用定义里的 def）
local function dsCatOn(k)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local d = DS_ANN_BYKEY[k]
  local dflt = (d and d.def) or false
  if type(c) == "table" and type(c.ds) == "table" and type(c.ds.cats) == "table" then
    local v = c.ds.cats[k]
    if v ~= nil then return v and true or false end
  end
  return dflt
end

-- 组装 wanted 表（只有节点类需要申请；服务类对方默认就给）
local function dsAnnWanted()
  local w, any = {}, false
  for _, d in ipairs(DS_ANN_CATS) do
    if d.group == "node" and dsCatOn(d.k) then w[d.k] = true any = true end
  end
  return any and w or nil
end

-- 该类别是否被用户开启（服务类靠本地过滤，因为对方总会返回它们）
local function dsAnnAccept(cat)
  if not cat then return false end
  return dsCatOn(cat)
end

-- 只把池里的钉子全部隐藏（不动签名）。重绘前用它归零，随后按新地图重新摆位。
-- 池内处于「显示」状态的钉子数（诊断用；池子复用，数组长度 != 可见数）
local function dsAnnShownCount()
  local n = 0
  for _, f in ipairs(dsAnnPins) do
    if type(f.IsShown) == "function" and f:IsShown() then n = n + 1 end
  end
  return n
end

local function dsAnnHidePins()
  for _, f in ipairs(dsAnnPins) do pcall(f.Hide, f) end
end

-- 「地图不在了」：隐藏 + 清签名（下次 tick 会认为需要重建）。
-- ★注意与 dsAnnHidePins 的区别：dsAnnDraw 内部若误用本函数，会把调用方刚设好的 dsAnnSig 清成 nil，
-- 表现为「画了但签名丢失 → 每 tick 都重绘」或「状态查询返回 nil」（1.70.19 实际踩到）。
local function dsAnnHideAll()
  dsAnnHidePins()
  dsAnnSig = nil
  dsAnnLastDrawn = 0 -- 层已收：自愈机制不得再拿旧的「打算画 N 点」去救一个已清空的层
  dsAnnShown = {}
end

-- 取一枚池内钉子（按序号复用；鼠标只在新造时设一次）。
-- ★1.70.26：素材与尺寸**不再在这里固定**——池子复用，同一枚钉子这次是草药（小图标）、
--   下次可能是灵魂医者（大图标），创建时定死会导致换类别后素材残留（与颜色残留同一个坑）。
--   两者都改由 dsAnnPlace 每次设置。
local function dsAnnPin(client, idx)
  local f = dsAnnPins[idx]
  if f then return f end
  if type(client.CreateWorldMapPin) ~= "function" then return nil end
  local ok, nf = pcall(client.CreateWorldMapPin, "EVALDSA" .. idx, 1, 1, 1)
  if not ok or not nf then return nil end
  f = nf
  if type(client.SetWorldMapPinHandlers) == "function" then
    pcall(client.SetWorldMapPinHandlers, f, function() dsShowPinTooltip(f) end,
      function() dsHidePinTooltip(f) end, nil)
  end
  dsAnnPins[idx] = f
  return f
end

-- 解析一条标注该用哪个图标文件（不含根路径、不含扩展名）；返回 nil = 用圆点+颜色。
-- 规则照抄 UnrealQuest Map\NpcPins.lua:209 IconForLocation：
--   · 稀有怪（unit 类）按 rank 换脸：精英/稀有精英→elite-mobs、Boss→boss-mobs、稀有→rare-mobs；
--     读不到 rank 就用类别图标兜底。
--   · 草药/矿脉等「物件类」优先用**该物件自己的美术**（UQ.nodeIcons：Peacebloom 就该长得像
--     Peacebloom，而不是一个通用草药图标）；对方表里没有的物件（如 Incendicite/Indurium）
--     回落到类别图标——与对方行为一致。
local function dsAnnIconFor(l)
  local d = l and l.category and DS_ANN_BYKEY[l.category]
  if not d then return nil end
  -- ① 单位类：稀有怪按 rank 换脸
  if l.sourceType == "unit" and l.category == "rares" then
    local db = dsDb()
    local rank
    if db then
      if type(db.GetUnitRank) == "function" then
        local ok, r = pcall(db.GetUnitRank, db, l.sourceId)
        if ok then rank = r end
      end
      local u = db.units and db.units[l.sourceId]
      if rank == nil and type(u) == "table" then rank = u.rnk end
    end
    return DS_ANN_RANK_ICON[tonumber(rank) or -1] or d.icon
  end
  -- ② 物件类：先查该物件专属美术
  local UQ = rawget(_G, "UnrealQuest")
  local per = UQ and UQ.nodeIcons and UQ.nodeIcons[l.category]
  local file = type(per) == "table" and per[l.sourceId]
  if type(file) == "string" and file ~= "" then
    return l.category .. "\\" .. file
  end
  -- ③ 回落到类别图标
  return d.icon
end

-- ★★★1.70.41 搜索结果定位的「随机彩色」小圆点（用户要求：每只怪一个随机颜色，便于区分）。
--
-- ★关键设计：颜色必须**由实体 id 派生**（确定性哈希），不能每次绘制都现摇一个随机数。
--   否则每 0.25s 一次重绘（甚至只是切图回来）颜色就会全变——用户根本无法「靠颜色记住哪只是哪只」，
--   随机色反而变成纯粹的视觉噪音。要求是「看起来随机」，不是「随时间随机」。
--
-- 用整数哈希（FNV-1a 变体）而不是 math.random：math.random 在本客户端各版本行为不一致，
-- 且无法保证「同一 id 恒定同色」；哈希是纯函数，跨会话也稳定。
-- 色相均匀取样（黄金角 0.618 步进）+ XML 式亮度/饱和度，避免出现灰/黑等看不清的颜色。
local function dsEntityColor(id)
  local n = tonumber(id) or 0
  if n < 0 then n = -n end
  -- 32 位整数混合（乘法取模用 double 精度内可接受的小乘数，避免 Lua 5.1 number 溢出误差累积）
  local h = n
  h = (h * 2654435761) % 4294967296
  h = (h * 2246822519) % 4294967296
  h = (h * 3266489917) % 4294967296
  -- 色相：黄金角步进，均匀铺满色轮且相邻 id 差异明显
  local hue = (h % 1000) / 1000
  -- 饱和度/亮度：各自再取一段哈希位，限制在「鲜艳但不刺眼」的区间
  local sat = 0.55 + ((math.floor(h / 1000) % 100) / 100) * 0.40   -- 0.55 ~ 0.95
  local val = 0.75 + ((math.floor(h / 100000) % 100) / 100) * 0.25 -- 0.75 ~ 1.00
  -- HSV → RGB
  local i = math.floor(hue * 6)
  local f = hue * 6 - i
  local p = val * (1 - sat)
  local q = val * (1 - f * sat)
  local t = val * (1 - (1 - f) * sat)
  local r, g, b
  local m = i % 6
  if m == 0 then r, g, b = val, t, p
  elseif m == 1 then r, g, b = q, val, p
  elseif m == 2 then r, g, b = p, val, t
  elseif m == 3 then r, g, b = p, q, val
  elseif m == 4 then r, g, b = t, p, val
  else r, g, b = val, p, q end
  return r, g, b
end
-- 测试直调：验证「同一 id 恒定同色」与「不同 id 尽量不同色」两条不变量。
function EVAL_DS_ENTITY_COLOR(id) return dsEntityColor(id) end

-- ★1.70.41 测试直调：控制行「所有控件都真实构建且几何同源」的可观测契约。
-- 背景：filterBtn 曾用 DSL_ROW_BTN_Y 定位，而该 local 在 35 行之后才声明 → 读到全局 nil
-- → SetPoint("TOPLEFT", parent, "TOPLEFT", x, nil) → 本客户端对 nil 锚点不做定位、也不报错
-- → 按钮落在未定义位置（用户截图「应该有个按钮没了」）。这是第 10 次 local 作用域坑。
-- ★为什么用「构建期登记 + 运行期读取」而非解析源码行号：Lua 运行期拿不到行号，
--   而桩不校验 SetPoint 的坐标参数——把与 SetPoint **同源**的常量登记下来，
--   断言才能发现「某个控件根本没被构建 / 构建时几何是 nil」。行号级的源码校验
--   另放在 test_engine.js 的 LAYOUT CHECK（那边能读文件、能做真正的顺序检查）。
function EVAL_DS_TEST_CONTROL_ROW_WIDGETS()
  -- 返回 { {name=, built=, center=}, ... }：center 为 nil 即「该控件用了未声明的局部量」
  local out = {}
  local row = DS.controlRow
  if type(row) ~= "table" or type(row.buttons) ~= "table" then return out end
  for _, b in ipairs(row.buttons) do
    table.insert(out, { name = b.name, center = b.center, declared = (b.center ~= nil) })
  end
  return out
end

-- 把一条标注摆上地图。
-- ★素材与颜色**每次都要重设**：池子按序号复用，同一枚钉子这次可能是草药（小图标）、
--   下次是灵魂医者（大图标），不重设就会素材残留（与颜色残留同一个坑，1.70.11 已踩过一次）。
--
-- ★图标策略（1.70.26 用户要求「查看每个类别的标注是否有对应的图标显示；自定义检索的数据
--   （npc/无掉落等）才用小圆点显示」）：
--     · 分类层（用户勾选的 16 类）→ 有 icon 就用**该类别专属图标**，且**不做颜色染色**
--       （照抄 UnrealQuest NpcPins:1108-1113 的分支：有 icon 时只设贴图，没 icon 才设圆点+颜色）。
--     · 搜索结果定位（自定义检索的数据：npc / 无掉落等）→ **一律圆点 + 金色**，
--       由调用方传 icon=nil 表达，正好符合用户「自定义检索的数据才用小圆点」。
local function dsAnnPlace(client, idx, info, r, g, b, icon)
  local f = dsAnnPin(client, idx)
  if not f then return false end
  f.dsInfo = info
  if type(client.SetWorldMapPinSize) == "function" then
    local sz = info.small and DS_ANN_ICON_SIZE_SMALL or DS_ANN_ICON_SIZE
    pcall(client.SetWorldMapPinSize, f, sz, sz)
  end
  if type(client.SetWorldMapPinTexture) == "function" then
    if icon then
      pcall(client.SetWorldMapPinTexture, f, DS_ANN_ICON_ROOT .. icon)
    else
      pcall(client.SetWorldMapPinTexture, f, DS_NODE_DOT_TEXTURE)
    end
  end
  if type(client.SetWorldMapPinColor) == "function" then
    -- 有图标时不染色（图标自带配色，染色会把它染糊）；圆点才用类别色。
    if icon then
      pcall(client.SetWorldMapPinColor, f, 1, 1, 1)
    else
      pcall(client.SetWorldMapPinColor, f, r or 1, g or 1, b or 1)
    end
  end
  -- ★★★1.70.35 修「静默放置失败」：PositionWorldMapPin 在**画布不存在/尺寸异常**时返回 false
  --   （ClientAPI.lua:2087），而旧代码 pcall 后**丢弃返回值、无条件 return true、无条件 Show**。
  --   后果：画布不在时我们仍报告「放了 N 个钉子」，counts 与 dsAnnShownCount 都以为正常，
  --   屏幕上却什么都没有——「两个信号都说健康、画面却是空的」这一类问题的又一个来源。
  --   现在：定位失败就不 Show、不算成功，由调用方如实计数（便于日志暴露真实失败）。
  local okPos, placed = pcall(client.PositionWorldMapPin, f, info.x / 100, info.y / 100)
  if not okPos or placed == false then
    pcall(f.Hide, f) -- 没有有效位置就不要显示（否则会停在错误坐标上）
    return false
  end
  pcall(f.Show, f)
  return true
end


-- 重绘整层：清空 → 取当前地图数据 → 按开启的类别铺点 → 叠加搜索结果定位
local function dsAnnDraw(areaId)
  dsAnnDrawCount = dsAnnDrawCount + 1
  local client = dsUQClient()
  local dbMod = dsUQModule("Database")
  dsAnnHidePins() -- 只清钉子，不动签名（调用方已设好）
  dsAnnLastFail = 0 dsAnnPlaceLog = nil -- 本次绘制的失败计数从零起算
  if not (client and dbMod) then dsAnnLastDrawn = 0 return 0 end
  if type(client.CreateWorldMapPin) ~= "function" or type(client.PositionWorldMapPin) ~= "function" then
    dsAnnLastDrawn = 0 return 0
  end

  local idx = 0
  local counts = {}

  -- ① 分类标注层（用户勾选的类别）
  -- dsTestEmptyResults 仅供测试构造「0 点重绘」场景（1.70.27 签名提交时机的回归防线）
  if dsAnnOn and not dsTestEmptyResults and type(dbMod.GetAreaServiceLocations) == "function" then
    local ok, locs = pcall(dbMod.GetAreaServiceLocations, dbMod, areaId, nil, nil, dsAnnWanted())
    if ok and type(locs) == "table" then
      for _, l in ipairs(locs) do
        if idx >= DS_ANN_MAX then break end
        if l.x and l.y and dsAnnAccept(l.category) then
          idx = idx + 1
          local col = DS_ANN_COLOR[l.category] or DS_ANN_DEFCOLOR
          local d = DS_ANN_BYKEY[l.category]
          local info = {
            name = l.name, zone = dsZoneName(l.areaId), x = l.x, y = l.y,
            kind = l.sourceType, id = l.sourceId, category = l.category,
            small = d and d.small or nil,
          }
          -- 分类层：有专属图标就用图标（含草药/矿脉的单物件美术），没有才退回圆点+类别色
          if dsAnnPlace(client, idx, info, col[1], col[2], col[3], dsAnnIconFor(l)) then
            counts[l.category] = (counts[l.category] or 0) + 1
          else
            dsAnnLastFail = dsAnnLastFail + 1
            if not dsAnnPlaceLog then
              dsAnnPlaceLog = "放置失败 例:" .. tostring(l.name) .. " (" .. tostring(l.x) .. "," .. tostring(l.y) .. ")"
            end
          end
        end
      end
    end
  end

  -- ② 搜索结果定位覆盖（也走同一池、同一地图绑定——不再有 60s 孤儿钉）
  if type(dsAnnOverlay) == "table" and dsAnnOverlay.areaId == areaId then
    local ov = dsAnnOverlay
    for _, p in ipairs(ov.pts or {}) do
      if idx >= DS_ANN_MAX then break end
      if p.x and p.y then
        idx = idx + 1
        local info = {
          name = ov.name, zone = dsZoneName(areaId), x = p.x, y = p.y,
          kind = ov.kind, id = ov.id, parentKind = ov.parentKind, parentId = ov.parentId,
          overlay = true,
        }
        -- ★搜索结果定位 = 用户所说的「自定义检索的数据（npc/无掉落等）」→
        --   显式传 icon=nil，一律**小圆点**（与分类层的图标区分）。
        -- ★1.70.41 用户要求「每只怪一个随机颜色，便于区分」：
        --   颜色由实体 id 派生（dsEntityColor）→ 同一只怪恒定同色、不同怪颜色不同，
        --   重绘/切图回来都不会变色（若每次现摇随机，颜色会不停跳，反而没法靠颜色认怪）。
        local cr, cg, cb = dsEntityColor(ov.id)
        if not dsAnnPlace(client, idx, info, cr, cg, cb, nil) then
          dsAnnLastFail = dsAnnLastFail + 1
          if not dsAnnPlaceLog then
            dsAnnPlaceLog = "覆盖层放置失败 例:" .. tostring(ov.name) .. " (" .. tostring(p.x) .. "," .. tostring(p.y) .. ")"
          end
        end
      end
    end
  end

  -- ③ 藏掉池里没用到的那部分
  for i = idx + 1, table.getn(dsAnnPins) do pcall(dsAnnPins[i].Hide, dsAnnPins[i]) end
  dsAnnShown = counts
  -- 截断必须可见：静默丢弃会让用户以为「显示了整个世界的数据」或数据不对（用户实测反馈）。
  if idx >= DS_ANN_MAX then
    dsAnnTruncated = true
    dsLog("注意：达到上限 " .. DS_ANN_MAX .. "，本图还有更多点未显示（可在类别里关掉密集类别）")
  else
    dsAnnTruncated = false
  end
  dsAnnLastDrawn = idx -- 本次**打算**放的点数（含放置失败）——自愈机制靠它区分「该画没画」与「本来就 0 点」
  return idx
end

-- 用户可读的本次显示摘要（诊断/日志用）
local function dsAnnSummary()
  local parts, n = {}, 0
  for _, d in ipairs(DS_ANN_CATS) do
    local c = dsAnnShown[d.k]
    if c and c > 0 then
      n = n + 1
      parts[n] = d.label .. c
    end
  end
  if n == 0 then return "（无）" end
  return table.concat(parts, " ")
end

-- 检查 GetViewedZone 的语义：返回 areaId 则可标注，nil = 地图没开/大陆视图
-- 视图签名：**区域 + 地图视图**，参照 UnrealQuest WorldMapPins 的 ViewSignature
-- （Map/WorldMapPins.lua:678 —— 它的签名含 areaId|mapFile|continent|zoneIndex）。
-- ★为什么必须带上 mapFile/continent/zoneIndex（1.70.24 修用户实测「勾选了类型但地图上不显示」）：
--   只用 areaId 时，**关图再开同一张图**（areaId 不变）会被判定为「未变 → 跳过重绘」，
--   于是钉子停留在关图时被客户端清掉的状态——地图看起来是空的。
--   实测日志佐证：`重绘 map=14 共 41 点` 之后连续 `地图=14 未变 → 跳过重绘`，用户再开图什么都不显示。
--   （与 1.70.17 是同一类错误的两端：那次错用不可靠的 IsShown 当可见性判据，这次则是一个
--     能反映视图变化的信号都没留。）
-- 诊断用：把 GetViewedZone 的 report 原样打出来。
-- 起因（1.70.31 排查）：日志里 areaId 在 14/17/141/215/405 之间反复漂移，而用户看到的是
-- **卡利姆多大陆视图**——必须确认客户端在大陆视图下到底报什么（zoneIndex 是否为 0）。
-- UnrealQuest 的 GetViewedZone 在 zoneIndex == 0 时返回 nil（"continentView"），
-- 所以拿到非 nil areaId 就意味着客户端自认是「具体区域视图」——这与用户看到的画面矛盾，
-- 只能靠实测数据判定，不能再靠推断。
local function dsViewReportStr(mc)
  if not mc or type(mc.GetViewedZone) ~= "function" then return "" end
  local ok, areaId, report, how = pcall(mc.GetViewedZone, mc)
  if not ok then return " [report取不到]" end
  local function f(v) return (v == nil) and "nil" or tostring(v) end
  -- ★画布尺寸也打出来：PositionWorldMapPin 把 (x,y) 当作**当前画布的比例**，
  --   所以「查询的区域」与「画布显示的地图」必须一致，否则百分比会被投射到错误的地图上
  --   ——这正是用户截图里「钉子在凄凉之地的图上散落到好几个区域」的成因。
  --   mapZoneName = 客户端原生地名（判断「画布到底在哪张图」的第一手依据）。
  local cw, ch = "?", "?"
  if type(dsUQClient) == "function" then
    local cl = dsUQClient()
    if cl and type(cl.GetWorldMapCanvasSize) == "function" then
      local okc, w, h = pcall(cl.GetWorldMapCanvasSize)
      if okc and type(w) == "number" and type(h) == "number" then cw, ch = w, h end
    end
  end
  return " | report: area=" .. f(areaId)
    .. " mapFile=" .. f(report and report.mapFile)
    .. " continent=" .. f(report and report.continent)
    .. " zoneIndex=" .. f(report and report.zoneIndex)
    .. " mapZoneName=" .. f(report and report.mapZoneName)
    .. " how=" .. f(how)
    .. " 画布=" .. tostring(cw) .. "x" .. tostring(ch)
    .. " 可见钉子=" .. tostring(dsAnnShownCount())
end

-- ★★★1.70.36 画布一致性校验：读取「世界地图当前贴图」作为独立证据。
--
-- 为什么需要它（本轮实测取证）：用户切到凄凉之地后，客户端 4.8 秒后把上报区域改回杜隆塔尔
-- （日志 `重绘 map=405` → 4.8 秒 → `重绘 map=14`），而**画布仍显示凄凉之地**。我们照着重绘，
-- 于是杜隆塔尔的 0-100% 坐标被画到凄凉之地的画布上（PositionWorldMapPin 按当前画布比例定位，
-- ClientAPI.lua:2087）→ 钉子糊满整张图 = 用户截图。
--
-- 随机点测试已证明「绘制链路完全正常」（9 轮 成功=8 失败=0，随机位置/颜色都可见），
-- 所以问题不在画布能力，而在「我们相信了一个与画布不符的区域上报」。
--
-- 本函数返回画布贴图路径（小写）供比对；取不到时返回 nil = 无法校验，
-- 此时**退回旧行为**（不能因为读不到证据就停止绘制，否则会在别的客户端上彻底不显示）。
local function dsCanvasTex()
  local cl = dsUQClient()
  if not cl or type(cl.GetWorldMapCanvas) ~= "function" then return nil end
  local okc, cv = pcall(cl.GetWorldMapCanvas)
  if not okc or not cv or type(cv.GetTexture) ~= "function" then return nil end
  local okt, t = pcall(cv.GetTexture, cv)
  if not okt or type(t) ~= "string" or t == "" then return nil end
  return string.lower(t)
end

-- 客户端报告的地图文件名 vs 画布贴图，宽松比对：
--   贴图 ...\interface\worldmap\durotar\durotar1  → 含 "durotar"
--   报告 "Durotar"                                  → 小写后含 "durotar"
-- 任一包含另一方即视为一致（避免路径大小写/层级差异误判）。
--   true=一致 / false=明确不一致 / nil=无法判定（缺任一证据）
local function dsCanvasAgrees(mapFile)
  local tex = dsCanvasTex()
  if not tex then return nil end
  if type(mapFile) ~= "string" or mapFile == "" then return nil end
  local key = string.lower(mapFile)
  if string.find(tex, key, 1, true) then return true end
  if string.find(key, tex, 1, true) then return true end
  return false
end

-- ★1.70.37 大陆/区域判别的独立信号：GetMapInfo 返回 (name, height, width)。
-- 起因（实测）：本客户端在**大陆视图**下 `zoneIndex` 仍报非 0（上一个选中区域），
-- 于是 UnrealQuest 的 `zoneIndex == 0` 守卫永不触发，我们把某区域的钉子按百分比
-- 画到**大陆画布**上 → 钉子糊满整张图（用户截图「迷雾之海」正是大陆视角）。
-- 各区域自己的地图尺寸不同，故把 height/width 记进日志，用于找「大陆 vs 区域」的分界。
local function dsMapSizeStr()
  if type(GetMapInfo) ~= "function" then return "GetMapInfo 不可用" end
  local ok, name, h, w = pcall(GetMapInfo)
  if not ok then return "GetMapInfo 失败" end
  return tostring(name) .. " " .. tostring(h) .. "x" .. tostring(w)
end
local function dsViewSig(mc)
  if not mc or type(mc.GetViewedZone) ~= "function" then return nil end
  local ok, areaId, report = pcall(mc.GetViewedZone, mc)
  if not ok or type(areaId) ~= "number" then return nil end
  local sig = tostring(areaId)
    .. "|" .. tostring(report and report.mapFile)
    .. "|" .. tostring(report and report.continent)
    .. "|" .. tostring(report and report.zoneIndex)
  return sig, areaId
end

-- ★1.70.39 tick 帧的前向声明。必须出现在**任何**读写它的函数之前，
-- 否则那些函数读到的是全局 nil（本项目第 9 次踩同一个 local 作用域坑）。
-- 本次是测试当场抓到的：EVAL_DS_TEST_TICK_FRAME() 返回 false（读到了全局）。
local dsTick = nil

local DS_ANN_INTERVAL = 0.25
local DS_ANN_HEARTBEAT = 30
-- ★★★1.70.40【重大简化】删掉「定时强刷(1.5s)」「慢速兜底(5s)」「稳定期闸门(0.8s)」三件套。
--
-- 为什么删——三个机制各自的成立前提，都在 1.70.39 修好 tick 父级之后失效了：
--
-- ① **1.5s 快速修复**：当初为「视图检测被 nil 骗过 → 层被清空」而加。
--    实测日志里它**一次都没触发过**（全文只有「定时兜底」，没有一条「强刷自愈」）。
--    tick 挂 WorldFrame 后检测已可靠，它已是死代码。
--
-- ② **5s 慢速兜底**：当初的唯一依据是「客户端上报区域滞后 13.7 秒」。
--    **这条证据本身是坏构建产生的**：13.7s ÷ 0.25s = 54.8 ≈ 55 次，而原文正说
--    「期间 tick 跑了 55 次」——即 55 次恰好等于 13.7 秒**满速** tick。可当时地图是开着
--    的，而地图开着时 tick 根本不跑（父级 bug）。**该数字自相矛盾，不能作为「上报滞后」
--    的证据**。基于它加的兜底，等于用每 5 秒一次全量重建（12 次/分）换一个不存在的收益。
--
-- ③ **0.8s 稳定期闸门**：当初为「大陆/缩放过渡时把区域坐标画到大陆画布上」而加。
--    但那个真凶同样是父级 bug（tick 停摆 → 关图瞬间补画上一次的图）。
--    更糟的是它**成了现在「切图不更新」的主因**，日志铁证：
--      t=3922342.934  视图变化 → 17|Barrens（等待稳定）
--      t=3922477.306  视图变化 → 215|Mulgore（等待稳定）   ← 134 秒里一次都没「稳定」过
--    用户连续切图时每一次都判「未稳定」→ **一次都不重绘** → 屏幕停在上一次兜底画的旧图上。
--    **这正是用户报了很久的「滞后一拍」的残余来源：不是检测慢，是闸门把重绘全吞了。**
--
-- ★用户明确选择 A 方案（1.70.40）：「每张图都画，中间态可以闪一下」。
--   实测本客户端没有「按事件驱动」这条路——UnrealQuest 全项目 6 处 RegisterEvent
--   **没有任何地图/区域事件**（唯一区域相关的是 PLAYER_ENTERING_WORLD），它的地图标注层
--   完全靠轮询 REFRESH_INTERVAL=0.25s。所以「任务插件切图能正确显示」靠的是
--   ① tick 帧挂 WorldFrame（我 1.70.39 才修对）② 签名一变就画。我们照做即可。
--
-- ★新语义（回归「任务插件的做法」）：**签名一变就画，不等稳定**。
--   保留的只有「先记签名再画」（避免绘制中途出错时每 tick 反复重建）。
--   频率仍由 DS_ANN_INTERVAL=0.25s 节流，且重绘只在签名**真的变化**时发生。
--
-- ★教训：一个兜底机制在「前提被证伪」之后必须被删掉，不能因为「留着也无害」而保留。
--   这三件套不但无害论不成立（5s 兜底每分钟 12 次全量重建、闸门直接吞掉重绘），
--   还会让后来的人以为「这里有保护」。★先证伪前提，再决定去留。

-- 心跳/诊断日志（沿用 1.70.16 的教训：先记心跳再判开关，否则静默无法与「没跑」区分）
local function dsAnnHeartbeat(now, areaId)
  if not dsTrace then return end
  if dsTraceUntil > 0 and now > dsTraceUntil then
    dsTrace = false dsTraceUntil = 0 dsPersist()
    dsLog("trace 已自动关闭（超过 " .. (DS_TRACE_TTL / 60) .. " 分钟）；需要继续取证请再 /eh ds trace")
  end
  if now - dsAnnHb >= DS_ANN_HEARTBEAT then
    dsAnnHb = now
    dsLog("心跳：tick 运行中 分类层=" .. tostring(dsAnnOn) .. " 当前地图=" .. tostring(areaId)
      .. " 钉子池=" .. table.getn(dsAnnPins) .. " 本层=" .. dsAnnSummary()
      .. "（IsShown=" .. tostring(dsMapShown()) .. " 仅参考）")
  end
end

-- ★前向声明：dsRndStep 定义在文件更后面（随机点测试段），而 tick 在它之前使用它。
--   Lua local 从声明语句之后才可见，不前置声明会读到全局 nil（本项目已多次踩同类坑）。
local dsRndStep
-- ★同样前置声明：dsHudTick 定义在文件更后面（诊断浮层段）
local dsHudTick

local function dsAnnTickFn()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - dsAnnTick < DS_ANN_INTERVAL then return end
  dsAnnTick = now

  -- 地图没开：整层隐藏（切走/关图 → 标注跟着走，这是用户明确要求的「绑定地图」）
  local mc = dsUQModule("MapContext")
  local sig, areaId = dsViewSig(mc)
  dsAnnHeartbeat(now, areaId)
  -- ★1.70.38 诊断浮层：即便 areaId 为 nil 也要刷新（用户要能看到「客户端报 nil」这件事本身）
  if dsHudTick then dsHudTick(areaId, sig) end

  if not areaId then
    if dsAnnSig ~= nil then
      dsLog("地图关闭/大陆视图 → 隐藏整层（原地图=" .. tostring(dsAnnSig) .. "）")
      dsAnnHideAll()
    end
    return
  end

  -- ★1.70.35 随机点测试（用户建议）：独立于图层开关，专门验证「地图打开后还能不能画」。
  --   放在 areaId 判定之后：只有地图可见时才测，关图自然停（与强刷同一原则）。
  if dsRndStep then dsRndStep(now, areaId) end

  -- ★1.70.27：图层实际关闭时，必须**把已有钉子收掉**，而不是「什么都不做」。
  --   旧实现在层关着时直接跳过重绘，于是上一批钉子永远留在屏幕上（用户报的「旧数据」）。
  --   这里只做隐藏+清签名（HideAll 语义），绝不用 REFRESH——见 1.70.20 的教训。
  if not dsAnnOn and table.getn(dsAnnPins) > 0 then
    dsLog("图层已关闭 → 收起全部标注")
    dsAnnHideAll()
    return
  end

  -- 地图切换 / 视图变化：整层重建（切回时自然重新显示；关图再开同图也会因签名变化而重绘）
  -- ★★★1.70.40【A 方案】签名一变**立刻**重绘，不等稳定。原来的三件套（1.5s 强刷 /
  --   5s 慢速兜底 / 0.8s 稳定期闸门）已全部删除，理由见文件上方常量处的长注释。
  --   一句话：它们的成立前提都在 1.70.39 修好 tick 父级之后失效了，而闸门反而成了
  --   「切图不更新」的主因（连续切图时每一次都判「未稳定」→ 一次都不重绘）。
  if sig == dsAnnSig then
    -- ★★★1.70.42 自愈（用户实测「点定位后地图空白」）：上次绘制**打算**画出点
    --   （dsAnnLastDrawn>0），但此刻一个都不可见 → 绘制发生在「画布尚未就绪」的瞬间
    --   （点击定位刚开图时最常见），诚实放置（1.70.35）把钉子全部 Hide，而签名没变
    --   → 永远不会再画 → 空地图。这与 1.70.40 删掉的三件套**本质不同**：
    --     · 它是「先校验再修复」（打算画 >0 且可见 =0 才出手），不校验的机制才会空转；
    --     · 2s 节流 + 每次出手都留日志（触发即证据，不触发则零开销零噪音）。
    --   ★反过来也成立：该区域本来就 0 点（lastDrawn=0）时绝不出手，不会每 2s 白查一次库。
    if dsAnnLastDrawn > 0 and dsAnnShownCount() == 0 and now - dsAnnHealT >= 2 then
      dsAnnHealT = now
      local nh = dsAnnDraw(areaId)
      dsLogAlways("自愈重绘 map=" .. tostring(areaId) .. " 打算 " .. tostring(dsAnnLastDrawn) .. " 点全部不可见 → 重画 "
        .. tostring(nh) .. " 点（失败 " .. tostring(dsAnnLastFail) .. "）"
        .. (dsAnnPlaceLog and (" " .. dsAnnPlaceLog) or ""))
      return
    end
    -- 视图没变：什么都不做（每 tick 一次比较，成本可忽略）。
    -- 「未变」是常态，按频率防护降频记录，避免刷爆 300 条环形缓冲。
    if now - dsAnnSameT >= 10 then
      dsAnnSameT = now
      dsLog("地图=" .. tostring(areaId) .. " 未变 → 跳过重绘")
    end
    return
  end
  -- ★ 1.70.40 A方案：签名变了就立刻画，不等稳定期。
  --   实测本客户端没有地图事件可依赖（UnrealQuest 全项目无地图/区域事件注册，
  --   它的地图层同样是 0.25s 轮询 + 签名比对），所以「签名一变就画」就是最快路径，
  --   而这正是任务插件切图能正确显示的全部原因。
  --   用户明确选择 A：每张图都画，中间态闪一下可接受。
  dsLog("视图变化 map=" .. tostring(dsAnnSig) .. " → " .. tostring(sig))
  dsAnnSig = sig -- 先记签名再画：避免绘制中途出错时每 tick 反复重建
  local n = dsAnnDraw(areaId) -- ★1.70.42 删掉 1.70.40 补丁残留的重复一对（原来每次切图画两遍）
  -- ★1.70.36 先观测、不拦截：把「画布贴图」和「它与上报区域是否一致」记进日志。
  --   等看到真实取值后，再决定是否用它作为「拒绝重绘」的依据。
  --   直接拦截的风险：若该客户端根本不暴露可用的贴图路径，守卫会拒绝一切重绘 → 功能全废。
  local agreeTxt = "?"
  do
    local rep = nil
    if mc and type(mc.GetViewedZone) == "function" then
      local okr, _a, r2 = pcall(mc.GetViewedZone, mc)
      if okr then rep = r2 end
    end
    local ag = dsCanvasAgrees(rep and rep.mapFile)
    agreeTxt = (ag == nil) and "无法判定" or (ag and "一致" or "★不一致")
  end
  dsLog("重绘 map=" .. tostring(areaId) .. " 打算 " .. n .. " 点，可见 " .. tostring(dsAnnShownCount())
    .. "，失败 " .. tostring(dsAnnLastFail) .. "：" .. dsAnnSummary() .. " " .. dsOverlayStr()
    .. dsViewReportStr(mc) .. " 画布贴图=" .. tostring(dsCanvasTex()) .. " 校验=" .. agreeTxt
    .. " GetMapInfo=" .. dsMapSizeStr())
end

-- ===== 对外接口 =====
function EVAL_DS_TOGGLE_NODES(on) -- 分类标注层总开关（保留旧名，UI/测试沿用）
  dsAnnOn = (on == nil) and not dsAnnOn or (on and true or false)
  -- ★关闭时必须「隐藏 + 清签名」，且绝不能走 REFRESH（1.70.20 修用户实测「点了关不掉」）：
  --   REFRESH 会无视开关直接按当前地图重绘，并把 dsAnnSig 设成当前地图——
  --   于是刚关掉的层又被画回来，且 tick 以为「这张图已画过」而永不再清理，表现为关不掉 + 旧数据残留。
  if dsAnnOn then
    EVAL_DS_ANN_REFRESH()
  else
    dsAnnHideAll()
  end
  dsPersist()
  return dsAnnOn
end
function EVAL_DS_NODE_STATE() return dsAnnOn, dsAnnSig, table.getn(dsAnnPins) end -- 测试直调

-- 分类开关（供 UI/测试）：/eh ds cat herbs on
-- ★1.70.23：独立的「总开关」按钮已合并进下拉，故图层开关改为**跟随类别数**派生——
--   任一类别勾上 = 图层开；全部取消 = 图层关。这样下拉里的勾选项本身就承担了开关职责，
--   与用户「开关已经在列表内具备了」的理解一致。
function EVAL_DS_SET_CAT(k, v)
  if not DS_ANN_BYKEY[k] then return false end
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) == "table" then
    if type(c.ds) ~= "table" then c.ds = {} end
    if type(c.ds.cats) ~= "table" then c.ds.cats = {} end
    c.ds.cats[k] = v and true or false
  end
  -- 派生总开关：有类别开启即开层，全关即关层（关层走 HideAll，绝不 REFRESH —— 见 TOGGLE 注释）
  local anyOn = false
  for _, d in ipairs(DS_ANN_CATS) do
    if dsCatOn(d.k) then anyOn = true break end
  end
  if anyOn and not dsAnnOn then
    dsAnnOn = true
    EVAL_DS_ANN_REFRESH()
  elseif (not anyOn) and dsAnnOn then
    dsAnnOn = false
    dsAnnHideAll()
  else
    EVAL_DS_ANN_REFRESH()
  end
  dsPersist()
  return true
end
function EVAL_DS_CAT_ON(k) return dsCatOn(k) end
function EVAL_DS_CAT_COUNT() -- 已开启的类别数（UI 按钮显示用）
  local n = 0
  for _, d in ipairs(DS_ANN_CATS) do if dsCatOn(d.k) then n = n + 1 end end
  return n
end
function EVAL_DS_ANN_STATS() return dsAnnShown, table.getn(dsAnnPins), dsAnnSig end

-- 强制重绘（开关/类别变化后立即生效，不等下一次 tick）
-- ★层关着时绝不能记签名：否则 tick 会以为「这张图已经画过」→ 用户再打开开关时不会重绘，
--   表现为「切换地图之后都是旧数据」（1.70.20 用户实测报障）。
function EVAL_DS_ANN_REFRESH()
  if not dsAnnOn then
    dsAnnHideAll()
    if type(dsAnnOverlay) ~= "table" then
      dsLogAlways("强制重绘：层已关且无覆盖层 → 收起") -- 1.70.42 诊断留痕
      return 0
    end
  end
  local mc = dsUQModule("MapContext")
  local sig, areaId = dsViewSig(mc)
  if not areaId then
    dsAnnHideAll()
    dsLogAlways("强制重绘：当前无视图（GetViewedZone 返回 nil）→ 收起") -- 1.70.42：开图瞬间客户端状态可能还没跟上
    return 0
  end
  dsAnnSig = sig -- 存的是「视图签名」而不是裸 areaId（关图再开同图必须能触发重绘）
  local n = dsAnnDraw(areaId)
  -- ★1.70.42 留痕：含「打算画/实际可见/失败」三元组——「信号都说健康、屏幕却是空的」
  --   的唯一区分办法就是这三个数并排打出来（1.70.35 教训的延续）。
  dsLogAlways("强制重绘 map=" .. tostring(areaId) .. " 打算 " .. tostring(n) .. " 点，可见 "
    .. tostring(dsAnnShownCount()) .. "，失败 " .. tostring(dsAnnLastFail)
    .. "：" .. dsAnnSummary() .. " " .. dsOverlayStr() .. dsViewReportStr(mc))
  return n
end

-- 清除「搜索结果定位」覆盖层（1.70.23：原「清理标注」按钮按用户要求删除，能力收进下拉）。
-- 只清覆盖层，不动类别开关——类别由下拉里的勾选项自己控制。
-- 为什么必须保留这个能力：搜索结果的定位钉是独立于类别开关的（dsAnnDraw 里不受 dsAnnOn 约束），
-- 若无入口清除，它们会一直挂到切图/重载为止。
function EVAL_DS_ANN_CLEAR_OVERLAY()
  dsAnnOverlay = nil
  EVAL_DS_ANN_REFRESH()
  return true
end

-- 兼容旧名：/eh ds clear 仍然可用（等价于「全部类别关掉 + 清覆盖层」）
function EVAL_DS_ANN_CLEAR()
  dsAnnOverlay = nil
  dsAnnOn = false
  dsAnnHideAll()
  dsPersist()
  return true
end

-- ===== 轨迹日志与诊断（沿用 1.70.13~1.70.18 的教训）=====
-- ★坑（1.70.13 实测）：轨迹日志挂在 tick 里，而 tick 开头的开关判断会让它一行都不产生——
--   用户只开 trace 不开图层 → 看着像功能坏了。故开 trace 时自动打开图层。
-- ★坑（1.70.15 实测）：trace/开关都是内存 local，/reload 后归零 → 取证被静默打断。故持久化。
-- ★坑（1.70.16 实测）：恢复逻辑曾写在 EVAL_DS_BUILD 里，而用户从未打开该 Tab → 恢复从未执行。
--   故恢复必须在文件作用域（见下方 EVAL_DS_RESTORE）。
-- ★trace 自动过期：忘了关会永久以高频刷写环形缓冲，把有用记录挤掉。
function EVAL_DS_TRACE(on)
  dsTrace = (on == nil) and not dsTrace or (on and true or false)
  if dsTrace then
    local now = (type(GetTime) == "function") and GetTime() or 0
    dsTraceUntil = now + DS_TRACE_TTL
    if not dsAnnOn then
      dsAnnOn = true
      dsLog("trace 开启（同时自动打开标注层；" .. (DS_TRACE_TTL / 60) .. " 分钟后自动关闭）")
    else
      dsLog("trace 开启（" .. (DS_TRACE_TTL / 60) .. " 分钟后自动关闭）")
    end
    EVAL_DS_ANN_REFRESH()
  else
    dsTraceUntil = 0
  end
  dsPersist()
  return dsTrace
end
function EVAL_DS_TRACE_STATE() return dsTrace end
function EVAL_DS_NODE_TICK_FOR_TEST() dsAnnTick = 0 dsAnnTickFn() end -- 测试直调（清零节流跑一次）

-- 诊断（/eh ds）：一张表看清整条链路
function EVAL_DS_NODE_DIAG()
  local mc = dsUQModule("MapContext")
  local areaId, err = nil, nil
  if mc and type(mc.GetViewedZone) == "function" then
    local ok, a = pcall(mc.GetViewedZone, mc)
    if ok then areaId = a else err = tostring(a) end
  end
  local shown = "?"
  if type(WorldMapFrame) == "table" and type(WorldMapFrame.IsShown) == "function" then
    local ok, s = pcall(WorldMapFrame.IsShown, WorldMapFrame)
    if ok then shown = tostring(s) end
  end
  local on = {}
  for _, d in ipairs(DS_ANN_CATS) do if dsCatOn(d.k) then table.insert(on, d.label) end end
  local tip = ""
  if not dsAnnOn then tip = " | 图层总开关未开（/eh ds trace 或 Tab 里打开）" end
  return string.format("图层=%s trace=%s 已绘地图=%s 钉子池=%d 对方当前区域=%s IsShown=%s(仅参考)",
    tostring(dsAnnOn), tostring(dsTrace), tostring(dsAnnSig), table.getn(dsAnnPins),
    tostring(areaId), tostring(shown))
    .. " | 开启类别=" .. ((table.getn(on) > 0) and table.concat(on, ",") or "无")
    .. " | 本次显示=" .. dsAnnSummary()
    .. (dsAnnTruncated and (" | 已触顶(" .. DS_ANN_MAX .. ")，本图还有更多点未显示") or "")
    .. tip .. (err and (" err=" .. err) or "")
end



-- ★★★1.70.38 地图诊断浮层（用户建议）：把当前诊断状态**直接画在世界地图上**，
-- 与随机点测试同一位置，用户无需读日志就能立刻看到「客户端报的什么 / 我们画的什么」。
--
-- 为什么需要：本轮排查反复卡在「日志状态」与「屏幕画面」对不上，来回改了 5 次方向。
-- 把状态直接贴在画面上，用户一张截图就能给出决定性证据。
--
-- 实现要点：
--   · 用 Client.GetWorldMapCanvas() 作为父级（与钉子同一画布），子帧必定随地图显隐
--   · 固定贴在画布左上角，不随区域坐标变化（所以它自己不会「跑偏」）
--   · 每 tick 更新文本（频率防护：只在文本真的变化时才 SetText）
-- ★状态变量必须声明在**使用它们的函数之前**（Lua local 从声明语句之后才可见）。
--   本轮我先把 EVAL_DS_HUD* 写在前面、状态写在后面 → 函数读到的是全局 nil，
--   EVAL_DS_HUD_STATE() 恒返回 nil（测试当场抓到 got=nil）。这是本项目第 8 次踩同一坑。
-- ★1.70.44 随机点测试的状态：HUD 文本（下方 dsHudTick）读 dsRndOn，故必须先声明。
local dsRndOn, dsRndT, dsRndStats = false, 0, { ok = 0, fail = 0, rounds = 0 }
local dsHudOn, dsHudFrame, dsHudText = false, nil, nil
local dsHudLastText = nil -- HUD 最后组装的诊断文本（供测试直读）

function EVAL_DS_HUD(on)
  dsHudOn = (on == nil) and not dsHudOn or (on and true or false)
  if not dsHudOn and dsHudFrame then pcall(dsHudFrame.Hide, dsHudFrame) end
  return dsHudOn
end
function EVAL_DS_HUD_STATE() return dsHudOn end
-- 构建浮层（惰性：第一次需要时才建，避免给不用它的人增加开销）
local function dsHudEnsure()
  if dsHudFrame then return dsHudFrame end
  local cl = dsUQClient()
  if not cl or type(cl.GetWorldMapCanvas) ~= "function" then return nil end
  local ok, canvas = pcall(cl.GetWorldMapCanvas)
  if not ok or not canvas then return nil end
  -- 用 Frame 承载文本；父级=地图画布 → 随地图一起显隐
  -- ★★★1.72.2 **具名帧会占用同名全局**（真客户端行为）——原名字 "EVAL_DS_HUD" 与本文件上面的
  --  全局函数 `function EVAL_DS_HUD(on)` **同名** → 帧把这个函数顶掉之后，`/eh ds hud` 入口的
  --  `if type(EVAL_DS_HUD) == "function"` 就不成立 → **命令静默失效**（HUD 打开后再也关不掉，且没有任何提示）。
  --  ★暴露途径：测试桩 1.72.2 起按真客户端行为把具名帧挂到全局，组 54 立刻报 attempt to call a table value。
  --  ★判据：**帧名必须与插件内任何全局函数名错开**（新增源码检查 FRAME NAME CLASH 守着这一类）。
  local f = CreateFrame("Frame", "EVAL_DS_HUDFrame", canvas)
  pcall(f.SetWidth, f, 300)
  pcall(f.SetHeight, f, 90)
  pcall(f.SetPoint, f, "TOPLEFT", canvas, "TOPLEFT", 6, -6)
  if type(f.SetFrameLevel) == "function" then pcall(f.SetFrameLevel, f, 200) end
  -- 半透明底衬，保证在任何地图底色上都能读清
  local bg = f:CreateTexture(nil, "BACKGROUND")
  if type(bg.SetTexture) == "function" then pcall(bg.SetTexture, bg, "Interface\\Buttons\\WHITE8X8") end
  if type(bg.SetVertexColor) == "function" then pcall(bg.SetVertexColor, bg, 0, 0, 0) end
  if type(bg.SetAlpha) == "function" then pcall(bg.SetAlpha, bg, 0.65) end
  if type(bg.SetAllPoints) == "function" then pcall(bg.SetAllPoints, bg, f) end
  local txt = dsText(f, 9, 1, 1, 0.6)
  if type(txt.SetPoint) == "function" then pcall(txt.SetPoint, txt, "TOPLEFT", f, "TOPLEFT", 4, -3) end
  if type(txt.SetJustifyH) == "function" then pcall(txt.SetJustifyH, txt, "LEFT") end
  if type(txt.SetWidth) == "function" then pcall(txt.SetWidth, txt, 292) end
  dsHudFrame, dsHudText = f, txt
  return f
end
-- 每 tick 刷新文本（仅当文本变化时 SetText，符合频率防护）
local dsHudLast = nil
dsHudTick = function(areaId, sig)
  if not dsHudOn then return end
  local f = dsHudEnsure()
  if not f then return end
  local mc = dsUQModule("MapContext")
  local rep, how = nil, nil
  if mc and type(mc.GetViewedZone) == "function" then
    local ok, a, r2, h2 = pcall(mc.GetViewedZone, mc)
    if ok then rep, how = r2, h2 end
  end
  local function fv(v) return (v == nil) and "nil" or tostring(v) end
  local lines = {
    "|cffffd100== 标注诊断 ==|r",
    "客户端报: area=" .. fv(areaId) .. " zone=" .. fv(rep and rep.zoneIndex) .. " how=" .. fv(how),
    "mapFile=" .. fv(rep and rep.mapFile) .. "  名字=" .. fv(rep and rep.mapZoneName),
    "GetMapInfo=" .. dsMapSizeStr(),
    "已画签名=" .. fv(dsAnnSig) .. "  池=" .. table.getn(dsAnnPins) .. " 可见=" .. dsAnnShownCount(),
    "本次显示=" .. dsAnnSummary(),
    "打算画=" .. tostring(dsAnnLastDrawn) .. " 失败=" .. tostring(dsAnnLastFail) .. " 已画=" .. tostring(dsAnnSig ~= nil),
    dsOverlayStr(),
    "图层=" .. tostring(dsAnnOn) .. " 随机点=" .. tostring(dsRndOn),
  }
  local text = table.concat(lines, "\n")
  -- ★把「最后组装的文本」存在模块变量里：这既是 HUD 的真实输出，也让测试能独立断言它，
  --   而不必依赖桩的 FontString 是否记录文本（桩的 <frame>:GetText 常常读不到）。
  dsHudLastText = text
  if text ~= dsHudLast then
    dsHudLast = text
    if type(dsHudText.SetText) == "function" then pcall(dsHudText.SetText, dsHudText, text) end
  end
  pcall(f.Show, f)
end

-- ★★★1.70.35 /eh ds rnd：定时随机点位测试（用户建议）。
-- 目的：回答「绘制是否只在打开地图的那一刻有效，之后就不接收绘制了」。
-- 做法：每隔 DS_RND_INTERVAL 秒，往当前地图上放 N 个**随机位置**的醒目钉子，并如实记录
--       每一次的**放置成功率**（PositionWorldMapPin 的真实返回值）。
-- 判读：
--   · 若首次（开图瞬间）成功、之后持续失败 → 绘制确实只在地图刚打开时有效（用户猜测成立）
--   · 若一直成功但屏幕上看不见 → 是画布/层级问题，而非调用时机
--   · 若一直成功且看得见 → 绘制链路正常，问题在别处（回到 areaId 判据）
-- 用 /eh ds rnd 开关。默认 2 秒放 8 个点，颜色随机、位置随机（0..100%），与真实数据无关。
local DS_RND_INTERVAL = 2
local DS_RND_COUNT = 8
-- ★1.70.44 dsRndOn 已上移到 HUD 之前（浮层文本读它，DECL ORDER CHECK 发现
--   「用在 1795 行、声明在 1819 行」→ 浮层里「随机点」恒显示 nil）。
-- 1.70.38 地图诊断浮层状态
function EVAL_DS_RND(on)
  dsRndOn = (on == nil) and not dsRndOn or (on and true or false)
  dsRndStats = { ok = 0, fail = 0, rounds = 0 }
  dsAnnRndSink = dsAnnRndSink or {}
  return dsRndOn
end
function EVAL_DS_RND_STATE() return dsRndOn, dsRndStats end
-- ★1.70.39 测试直调：暴露 tick 帧本身，让断言能检查它的**父级**。
-- 父级是本轮根因（挂 UIParent → 地图打开时 UIParent 被隐藏 → OnUpdate 停发 → tick 停摆）。
-- 只暴露帧、不暴露判断逻辑：断言读的是真对象，不是测试里复刻的一份。
function EVAL_DS_TEST_TICK_FRAME() return dsTick end
-- 1.70.38 测试直调：诊断浮层文本（验证它真的收到了内容，而不是只建了帧）
function EVAL_DS_TEST_HUD_TEXT()
  -- 返回「最后组装的诊断文本」：这是 HUD 的真实输出，与桩无关。
  -- （用 FontString:GetText 读会被桩的能力限制，导致断言测不到东西——本项目多次踩过。）
  return dsHudLastText
end
-- 每轮：清掉上一轮随机钉 → 放新的一批 → 记录成功/失败
dsRndStep = function(now, areaId)
  if not dsRndOn then return end
  if now - dsRndT < DS_RND_INTERVAL then return end
  dsRndT = now
  local client = dsUQClient()
  if not client or type(client.CreateWorldMapPin) ~= "function" then return end
  -- 清上一轮（同一批复用帧，避免无限增长）
  for _, f in ipairs(dsAnnRndSink) do pcall(f.Hide, f) end
  local okN, failN = 0, 0
  for i = 1, DS_RND_COUNT do
    local f = dsAnnRndSink[i]
    if not f then
      local ok, nf = pcall(client.CreateWorldMapPin, "EVALDSRND" .. i, 1, 1, 1)
      if ok and nf then f = nf dsAnnRndSink[i] = nf end
    end
    if f then
      local rx = math.random(5, 95)
      local ry = math.random(5, 95)
      -- 随机醒目色，便于在满屏真实钉子中一眼认出
      if type(client.SetWorldMapPinColor) == "function" then
        pcall(client.SetWorldMapPinColor, f, math.random(), math.random(), math.random())
      end
      if type(client.SetWorldMapPinSize) == "function" then
        pcall(client.SetWorldMapPinSize, f, 12, 12)
      end
      -- ★如实取返回值：这正是「画布是否还在、还能不能放」的直接证据
      local okPos, placed = pcall(client.PositionWorldMapPin, f, rx / 100, ry / 100)
      if okPos and placed ~= false then
        pcall(f.Show, f)
        okN = okN + 1
      else
        pcall(f.Hide, f)
        failN = failN + 1
      end
    else
      failN = failN + 1
    end
  end
  dsRndStats.ok = dsRndStats.ok + okN
  dsRndStats.fail = dsRndStats.fail + failN
  dsRndStats.rounds = dsRndStats.rounds + 1
  dsLog(string.format("随机点测试 第%d轮 area=%s 成功=%d 失败=%d (累计 成功=%d 失败=%d)",
    dsRndStats.rounds, tostring(areaId), okN, failN, dsRndStats.ok, dsRndStats.fail))
end
function EVAL_DS_RND_DIAG()
  return string.format("随机点测试=%s 轮数=%d 累计成功=%d 累计失败=%d（%ds/轮，每轮%d点）",
    tostring(dsRndOn), dsRndStats.rounds, dsRndStats.ok, dsRndStats.fail,
    DS_RND_INTERVAL, DS_RND_COUNT)
end

-- ★★恢复持久化开关必须在这里（文件作用域），不能放在 EVAL_DS_BUILD 里（1.70.16 实测定案）：
-- EVAL_DS_BUILD 只在用户**打开数据检索 Tab**时执行一次。而 tick 是挂在 OnUpdate 上独立跑的，
-- 与 Tab 是否打开无关。我原先把恢复逻辑放进 BUILD → 用户停在 Tab1 从没打开过 Tab4 →
-- 恢复从未执行 → trace 始终 false → 日志永远只有一行「trace 开启」，连心跳都没有。
-- 放在文件作用域：每次 /reload 载入即恢复。

-- ★★★1.70.34 /eh ds snap：一次性快照，供用户在「看到错误标注的那一刻」手动触发。
-- 起因：多轮日志排查都无法把「日志状态」与「屏幕画面」对上——这是本次问题的真正瓶颈，
-- 而不是代码。快照把两边同时记下来：
--   · 客户端报告的区域（GetViewedZone）与 report 全字段
--   · **地图画布当前贴图的路径**——这是「屏幕上到底显示哪张图」的独立证据
--     （GetViewedZone 已被实测证明会在两个区域间来回跳，不能再当唯一依据）
--   · 我们实际画的是哪个区域、放了多少钉子、钉子里记录的 zone 是什么
-- 判读方法：若「画布贴图」与「我们画的区域」不一致 → 是投影基准错位（钉子必然散乱）；
--          若两者一致但画面仍不对 → 问题在别处（届时看钉子样本）。
function EVAL_DS_SNAP()
  local mc = dsUQModule("MapContext")
  local out = {}
  local function add(s) table.insert(out, s) end
  add("=== DS SNAP ===")
  add("图层=" .. tostring(dsAnnOn) .. " trace=" .. tostring(dsTrace)
    .. " 已绘签名=" .. tostring(dsAnnSig))
  add("钉子池=" .. tostring(table.getn(dsAnnPins)) .. " 可见=" .. tostring(dsAnnShownCount())
    .. " 打算画=" .. tostring(dsAnnLastDrawn) .. " 失败=" .. tostring(dsAnnLastFail))
  add(dsOverlayStr()) -- 1.70.42：覆盖层是「点定位后地图空白」排障的第一现场
  if dsAnnPlaceLog then add("放置失败详情: " .. dsAnnPlaceLog) end
  -- 客户端报告的视图
  if mc and type(mc.GetViewedZone) == "function" then
    local ok, a, rep, how = pcall(mc.GetViewedZone, mc)
    if ok then
      local function f(v) return (v == nil) and "nil" or tostring(v) end
      add("GetViewedZone: area=" .. f(a) .. " mapFile=" .. f(rep and rep.mapFile)
        .. " zoneIndex=" .. f(rep and rep.zoneIndex) .. " mapZoneName=" .. f(rep and rep.mapZoneName)
        .. " how=" .. f(how))
    else
      add("GetViewedZone 调用失败: " .. tostring(a))
    end
  else
    add("MapContext 不可用")
  end
  -- ★画布贴图：屏幕上实际显示的地图图像（独立于上面的区域上报）
  local cl = dsUQClient()
  local canvasTex = "?"
  if cl and type(cl.GetWorldMapCanvas) == "function" then
    local okc, cv = pcall(cl.GetWorldMapCanvas)
    if okc and cv and type(cv.GetTexture) == "function" then
      local okt, t = pcall(cv.GetTexture, cv)
      if okt and t then canvasTex = tostring(t) end
    end
  end
  add("画布贴图=" .. canvasTex)
  -- 画布与上报区域是否一致（本包先观测不拦截，见 dsCanvasAgrees 注释）
  local repFile = nil
  if mc and type(mc.GetViewedZone) == "function" then
    local okr, _a, r2 = pcall(mc.GetViewedZone, mc)
    if okr then repFile = r2 and r2.mapFile end
  end
  local ag = dsCanvasAgrees(repFile)
  add("画布校验(mapFile=" .. tostring(repFile) .. ")="
    .. ((ag == nil) and "无法判定" or tostring(ag)))
  -- 我们实际绘制的区域与钉子样本
  add("本次显示=" .. dsAnnSummary())
  local samples = {}
  for i = 1, math.min(3, table.getn(dsAnnPins)) do
    local pin = dsAnnPins[i]
    local inf = pin and pin.dsInfo
    if inf then
      table.insert(samples, string.format("#%d zone=%s cat=%s (%.1f,%.1f)",
        i, tostring(inf.zone), tostring(inf.category), inf.x or -1, inf.y or -1))
    end
  end
  add("钉子样本: " .. ((table.getn(samples) > 0) and table.concat(samples, "  ") or "无"))
  return table.concat(out, " | ")
end

function EVAL_DS_RESTORE()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" or type(c.ds) ~= "table" then return false end
  -- 1.70.27 fix for "map switch shows stale annotations": since 1.70.23 the layer switch
  -- is DERIVED from the category set, so restoring cfg.ds.nodes independently is wrong --
  -- that field is only a cached mirror and can be stale. Observed failure chain:
  --   cfg.ds.nodes=false (saved by an earlier session) but cfg.ds.cats={herbs,mines}
  --   -> restore sets dsAnnOn=false -> dsAnnDraw category block gated on `if dsAnnOn`
  --      draws 0 points -> yet the tick set dsAnnSig BEFORE drawing, so every later tick
  --      concludes "already drawn, skip" -> switching maps re-draws 0 points again
  --   -> the previous batch of pins stays on screen = the stale data the user reported.
  -- Log proof: every heartbeat reads 分类层=false while the save has nodes=true and two
  -- categories on; a truly-off layer could not have pins on screen (the screenshot is full).
  -- Fix: the category set is the single authority; re-derive at restore time.
  local anyOn = false
  for _, d in ipairs(DS_ANN_CATS) do
    if dsCatOn(d.k) then anyOn = true break end
  end
  dsAnnOn = anyOn
  c.ds.nodes = anyOn -- mirror back for backward compatibility
  if c.ds.trace ~= nil then dsTrace = c.ds.trace and true or false end
  if dsTrace then
    dsLog("（恢复取证开关：trace=开 图层=" .. tostring(dsAnnOn) .. "）")
  end
  return true
end
EVAL_DS_RESTORE() -- 文件载入即恢复（此时 SavedVariables 已由客户端还原）

-- ===== UI 层 =====
local DS_RES_ROWS, DS_DET_LINES = 10, 14

local function dsMode() return table.getn(DS.nav) > 0 and "detail" or "search" end

local function dsTabActive() -- 去抖/事件触发时 Tab 可能已切走：显隐契约只在激活 Tab 上 Show（cfgTab 由 SETTAB 先写）
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  return type(c) == "table" and c.cfgTab == 4
end

-- 依赖状态 → 面板文案。面板未构建时只记状态（EVAL_DS_REFRESH 可能先于 UI 构建被调用）。
local function dsDepApply(st)
  local d = DS.dep
  DS.depState = st
  if not d then return end
  d.title:SetText(L("DS_DEP_TITLE"))
  d.why:SetText(L("DS_DEP_WHY"))
  d.msg:SetText(L(dsDepText(st)))
  d.foot:SetText(L("DS_DEP_FOOT"))
  pcall(d.frame.Show, d.frame)
end

function EVAL_DS_REFRESH()
  if not DS.built then return end
  if not dsTabActive() then return end
  local st = dsDepState()
  if st ~= DS_DEP_OK then -- 强依赖缺席（未装/未启用/未就绪/无法判定）：只留引导面板
    dsDepApply(st)
    -- ★这里必须把搜索行**一并收起**。旧实现只显示一行黄字、控件照旧可交互，
    --   用户会打字、会点按钮，却只能得到空列表——那正是「静默失败」。
    --   让界面看上去就「本页当前不可用」，用户才会去看引导。
    for _, w in ipairs(DS.searchWidgets) do pcall(w.Hide, w) end
    for _, r in ipairs(DS.resRows) do r.btn:Hide() r.mapBtn:Hide() r.iconBtn:Hide() end
    DS.back.btn:Hide() DS.backBottom.btn:Hide() DS.title:Hide() DS.subtitle:Hide() DS.titleMap:Hide()
    for _, l in ipairs(DS.detLines) do l.btn:Hide() l.mapBtn:Hide() l.iconBtn:Hide() end
    if DS.scrollUp then DS.scrollUp.btn:Hide() DS.scrollDn.btn:Hide() DS.indicator:Hide() end
    return
  end
  if DS.dep then pcall(DS.dep.frame.Hide, DS.dep.frame) end -- 依赖就绪：收起引导面板
  if dsMode() == "detail" then
    for _, w in ipairs(DS.searchWidgets) do pcall(w.Hide, w) end -- 详情模式隐藏搜索行（修 1.0 实测重叠）
    DS.back.btn:Show() -- 1.70.7 重置钮在详情模式也常显（一键归零）
    for _, r in ipairs(DS.resRows) do r.btn:Hide() r.mapBtn:Hide() r.iconBtn:Hide() end -- ★结果行整行(含两个图标钮)必须全藏：漏一个就会在详情视图里叠出一列图标（用户实测截图）
    local cur = DS.nav[table.getn(DS.nav)]
    local d = EVAL_DS_DETAIL(cur.kind, cur.id, table.getn(DS.nav))
    DS.back.btn:Show() DS.backBottom.btn:Show()
    DS.title:SetText(d and d.title or "?") DS.title:Show()
    DS.subtitle:SetText((d and d.subtitle) or "") DS.subtitle:Show()
    DS.titleLoc = dsFirstLoc(cur.kind, cur.id)
    if DS.titleLoc then DS.titleMap:Show() else DS.titleMap:Hide() end
    local total = d and table.getn(d.lines) or 0
    local maxOff = math.max(0, total - DS_DET_LINES)
    DS.detOff = math.max(0, math.min(DS.detOff or 0, maxOff)) -- 1.70.4 收敛到合法范围
    for i, l in ipairs(DS.detLines) do
      local ln = d and d.lines[DS.detOff + i] or nil
      l.link, l.hoverItem, l.loc = nil, nil, nil
      l.btn:Hide() l.mapBtn:Hide() l.iconBtn:Hide()
      if ln then
        l.text:SetText(((ln.link) and "→ " or "  ") .. tostring(ln.text))
        l.link = ln.link l.hoverItem = ln.hoverItem l.loc = ln.loc
        if ln.link then
          local p = dsKindIcon(ln.link.kind, ln.link.id)
          if p then pcall(l.icon.SetTexture, l.icon, p) l.iconBtn:Show() end
        end
        l.btn:Show()
        if ln.loc then l.mapBtn:Show() end
      end
    end
    -- 1.70.4 滚动条（仅详情）：↑↓ 按钮 + 滚轮（滚轮链式接管见 EVAL_DS_BUILD 尾部）
    if DS.scrollUp then
      if DS.detOff > 0 then DS.scrollUp.btn:Show() else DS.scrollUp.btn:Hide() end
      if DS.detOff < maxOff then DS.scrollDn.btn:Show() else DS.scrollDn.btn:Hide() end
      if total > DS_DET_LINES then
        DS.indicator:SetText(string.format("%d-%d / %d", DS.detOff + 1, math.min(DS.detOff + DS_DET_LINES, total), total))
        DS.indicator:Show()
      else
        DS.indicator:Hide()
      end
    end
  else
    for _, w in ipairs(DS.searchWidgets) do pcall(w.Show, w) end
    if not DS.echoNeeded then pcall(DS.echo.Hide, DS.echo) end -- EditBox 可正常渲染时不同时显示回声行
    DS.back.btn:Hide() DS.backBottom.btn:Hide() DS.title:Hide() DS.subtitle:Hide() DS.titleMap:Hide()
    for _, l in ipairs(DS.detLines) do l.btn:Hide() l.mapBtn:Hide() l.iconBtn:Hide() end
    if DS.scrollUp then DS.scrollUp.btn:Hide() DS.scrollDn.btn:Hide() DS.indicator:Hide() end
    for i, r in ipairs(DS.resRows) do
      local it = DS.results[i]
      r.kind, r.id, r.loc = nil, nil, nil
      r.btn:Hide() r.mapBtn:Hide() r.iconBtn:Hide()
      if it then
        r.text:SetText(string.format("[%s] %s  %s", L("DS_T_" .. string.upper(it.kind)), it.name, it.sub or ""))
        r.kind, r.id, r.loc = it.kind, it.id, it.loc
        local p = dsKindIcon(it.kind, it.id)
        if p then pcall(r.icon.SetTexture, r.icon, p) r.iconBtn:Show() end
        r.btn:Show()
        if it.loc then r.mapBtn:Show() end
      end
    end
    if table.getn(DS.results) == 0 and DS.lastQuery ~= "" and DS.lastQuery ~= nil then
      DS.resRows[1].text:SetText(L("DS_NORESULT"))
      DS.resRows[1].btn:Show() -- 无链接，仅占位展示
    end
  end
end

local function dsNavPush(kind, id)
  table.insert(DS.nav, { kind = kind, id = id })
  DS.detOff = 0 -- 1.70.4 新详情从顶部开始
  if DS.eb then pcall(DS.eb.ClearFocus, DS.eb) end
  EVAL_DS_REFRESH()
end

local function dsNavBack()
  if table.getn(DS.nav) > 0 then table.remove(DS.nav) end
  EVAL_DS_REFRESH()
end

-- 1.70.7 重置搜索状态（用户要求：把「返回」改成重置）——清空 输入/结果/级联栈/滚动/焦点，回到全新搜索页。
-- 与「返回上一级」区分：返回只弹一层，重置是彻底归零（不再需要连点多次回退）。
local function dsResetSearch()
  DS.nav = {}
  DS.results = {}
  DS.detOff = 0
  DS.lastQuery = ""
  DS.mode = "search"
  if DS.eb then
    pcall(DS.eb.SetText, DS.eb, "")
    pcall(DS.eb.ClearFocus, DS.eb)
  end
  if DS.echo then pcall(DS.echo.SetText, DS.echo, "") end
  if DS.ph then pcall(DS.ph.SetText, DS.ph, L("DS_PH")) end
  EVAL_DS_REFRESH()
end

function EVAL_DS_RESET() dsResetSearch() end -- 测试直调（必须定义在 dsResetSearch 之后——Lua local 作用域）

local function dsDoSearch()
  DS.due = 0
  local q = ""
  if DS.eb then
    local ok, t = pcall(DS.eb.GetText, DS.eb)
    if ok and type(t) == "string" then q = t end
  end
  q = string.gsub(q, "^%s*(.-)%s*$", "%1")
  DS.lastQuery = q
  DS.results = (q ~= "") and EVAL_DS_SEARCH(q, DS.filter) or {}
  if DS.ph then DS.ph:SetText((q == "") and L("DS_PH") or "") end -- 有输入则收起占位提示
  if dsMode() == "search" then EVAL_DS_REFRESH() end
end

-- 输入去抖帧（频率防护总则：按键高频必去抖 0.25s；纯本地数据展示，无服务器写动作）
-- 统一标注层的 tick 挂在这里（自带 0.25s 节流 + 地图签名比对）——不新增帧。
-- 旧的「搜索结果钉 60s 自熄」已删除：现在所有标注都由地图绑定管理，不再有发射后不管的钉子。
--
-- ★★★1.70.39【本客户端最关键的坑】tick 的父级必须是 WorldFrame，不能是 UIParent。
--
-- 根因（UnrealQuest Core/Driver.lua:467-482 有明文，我此前没读到）：
--   「A frame receives no OnUpdate while it or any ancestor is hidden. UIParent is part
--     of the game UI and gets hidden -- the fullscreen map presentation being the case
--     that bit us: the whole addon's periodic work stopped for as long as the map was
--     open. WorldFrame is the 3D viewport and is never hidden by the UI.」
-- 即：**打开全屏世界地图时 UIParent 被隐藏 → 挂在它下面的帧完全收不到 OnUpdate → tick 整个停摆**。
-- 对方因此把驱动帧挂在 WorldFrame（并点明 pfQuest 也是这么干的：
--   pfMap = CreateFrame("Frame", "pfQuestMap", WorldFrame)）。
--
-- 这一个父级错误完整解释了用户长期报的「切图不更新 / 滞后一拍」：
--   ① 地图开着时 tick 不跑 → 切图当场不重绘；
--   ② 关图瞬间 UIParent 恢复 → tick 恢复，此时客户端早已把画布重建清空，
--      我们才补画上一次的图 → 看起来恰好「滞后一拍」；
--   ③ 再开图时画布又是新的、已画签名却还记着旧图 → 「数据还是上次那张图的」。
-- 所有「轮询 + 签名比对」「定时强刷」「稳定期闸门」都建立在一个假设上——**tick 一直在跑**；
-- 这个假设在地图打开时是假的，所以那三层加固全都在空转。
--
-- ★教训：「定时刷新」类修复之前，先确认「定时器在地图打开时是否真的在跑」。
--   我连续用日志推断了几轮，却没问过「这些日志本身是不是在地图打开时根本不产生」。
local dsTickParent = UIParent
do
  -- WorldFrame 是 3D 视口，UI 隐藏时不会被隐藏；拿不到就退回 UIParent（聊胜于无）。
  local okFrame, wf = pcall(function() return WorldFrame end)
  if not okFrame or not wf then wf = nil end
  if wf then dsTickParent = wf end
end
dsTick = CreateFrame("Frame", "EVAL_DATASEARCH_TICK", dsTickParent)
dsTick:SetScript("OnUpdate", function()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if DS.due > 0 and now >= DS.due then dsDoSearch() end
  dsAnnTickFn() -- 统一标注层：随地图切换重建/隐藏
end)

-- ===== 地图标注菜单（1.70.25 提到文件作用域，供 UI 与测试共用）=====
-- 多选勾选（用户确认的形式）：每项独立开关，可同时看多类；点一项即切换，面板不关闭。
-- 分组显示（节点类=采集物，服务类=城镇设施）+ 顶部全开/全关快捷项。
--
-- ★为什么不把 ■/□ 拼进标签文本：那会让「面板自绘的方框」与「我拼的字」两套状态并存，
--   一旦不重绘就各说各话（用户实测「我选的是草药，矿脉也被勾选上」正是这种不一致的观感）。
--   现在标记只由 EVAL_DD_OPEN 多选模式按 opts.selected 绘制，数据源唯一 = cfg.ds.cats。
function dsCatMenu()
  local items, keys, locked = {}, {}, {}
  local function add(label, key, lock)
    local i = table.getn(items) + 1
    keys[i] = key
    items[i] = label
    if lock then locked[i] = true end -- 分组标题：多选模式下不画方框、点击不切换
  end
  add("|cffaaaaaa— 节点（采集物）—|r", nil, true)
  for _, d in ipairs(DS_ANN_CATS) do
    if d.group == "node" then add(d.label, d.k) end
  end
  add("|cffaaaaaa— 服务（城镇）—|r", nil, true)
  for _, d in ipairs(DS_ANN_CATS) do
    if d.group == "svc" then add(d.label, d.k) end
  end
  add("|cffaaaaaa— 快捷 —|r", nil, true)
  add("|cffffd200全部开启|r", "__all_on__")
  add("|cffffd200全部关闭|r", "__all_off__")
  return { items = items, keys = keys, locked = locked, sel = dsCatMenuSel(keys, table.getn(items)) }
end

-- 勾选态由「类别真实状态」派生（唯一数据源 = cfg.ds.cats）→ 面板与数据不可能再不一致。
-- 批量动作（全开/全关）后也用它重新派生并 EVAL_DD_SYNC，避免只重绘被点的那一行。
function dsCatMenuSel(keys, n)
  local s, cnt = {}, EVAL_DS_CAT_COUNT()
  for i = 1, n do
    local k = keys[i]
    if k == "__all_on__" then
      s[i] = (cnt > 0) and true or nil
    elseif k == "__all_off__" then
      s[i] = (cnt == 0) and true or nil
    elseif k then
      s[i] = EVAL_DS_CAT_ON(k) and true or nil
    end
  end
  return s
end

-- 下拉项被点：k=类别键 或 "__all_on__"/"__all_off__"；nowOn=面板回传的新状态。
function dsCatMenuPick(k, nowOn)
  if not k then return end -- 分组标题行：不可点（已在 opts.locked 里声明，双保险）
  if k == "__all_on__" or k == "__all_off__" then
    local on = (k == "__all_on__")
    for _, d in ipairs(DS_ANN_CATS) do EVAL_DS_SET_CAT(d.k, on) end
    if not on then
      -- 「全部关闭」= 用户心目中的总开关关：顺带清掉搜索结果定位钉，
      -- 否则那些钉没有任何入口可以移除（原「清理标注」按钮已按用户要求删除）
      EVAL_DS_ANN_CLEAR_OVERLAY()
    end
    -- 批量改动必须整体重绘（只重绘被点那一行会让其余 16 行停在旧方框上）
    local m = dsCatMenu()
    if type(EVAL_DD_SYNC) == "function" then EVAL_DD_SYNC(m.sel) end
  else
    -- 用面板回传的真实新状态 nowOn，而不是再读一次 EVAL_DS_CAT_ON 取反：
    -- 读数据源做「取反」在状态与面板不一致时会连续同向翻转（典型表现=点 A 却像点了 B）。
    EVAL_DS_SET_CAT(k, nowOn and true or false)
  end
end

-- 测试直调（不建真实 UI 也能断言菜单结构与勾选一致性）
function EVAL_DS_ANN_CAT_LIST() return DS_ANN_CATS end
function EVAL_DS_TEST_CATBTN() return DS.catBtn and DS.catBtn.btn end -- 接线级断言用真实按钮
function EVAL_DS_TEST_CONTROL_ROW_GEOMETRY()
  -- 未构建时给一份与构建期同源的默认值（常量推导，不另抄数字）
  return DS.controlRow or {
    boxCenter = -64, phCenter = -64, phAnchorV = "CENTER",
    buttons = { { name = "类型", center = -64 }, { name = "地图标注", center = -64 } },
  }
end
-- 1.70.26 测试直调：类别图标解析与根路径
function EVAL_DS_ANN_ICON_ROOT() return DS_ANN_ICON_ROOT end
function EVAL_DS_CAT_ICON(k)
  local d = DS_ANN_BYKEY[k]
  return d and d.icon or nil
end
function EVAL_DS_ANN_ICON_FOR(l) return dsAnnIconFor(l) end
-- 1.70.27 测试直调：构造「层关但钉子残留」与「0 点重绘」两种真实状态
function EVAL_DS_TEST_PIN_COUNT() return table.getn(dsAnnPins) end
function EVAL_DS_TEST_SHOWN_COUNT() return dsAnnShownCount() end
function EVAL_DS_TEST_WIPE_PINS() -- 制造「层开着但无可见钉子」的异常，验证安全网自愈
  for _, f in ipairs(dsAnnPins) do pcall(f.Hide, f) end
end
-- 清空钉子池。★测试必需：dsAnnPins 是模块级状态，会**跨用例残留**上一用例用旧桩建的帧，
-- 而 dsAnnPlace 按序号复用（存在即不新建）→ 本用例的桩根本没被用到，断言会以误导方式失败。
-- 测试直调：用给定的假 client 放一个钉子，返回 dsAnnPlace 的真实结果
function EVAL_DS_TEST_PLACE_ONE(fakeClient, idx)
  return dsAnnPlace(fakeClient, idx or 1, { x = 50, y = 50, name = "t" }, 1, 1, 1, nil)
end
function EVAL_DS_TEST_RESET_PINS()
  dsAnnPins = {}
  dsAnnSig = nil
  dsAnnShown = {}
  dsAnnLastDrawn = 0 dsAnnHealT = 0 dsAnnLastFail = 0 dsAnnPlaceLog = nil -- 1.70.42 自愈状态同样是模块级残留
  dsAnnDrawCount = 0 -- 绘制计数器同样是模块级残留
  -- ★稳定期闸门的候选状态也必须重置：它同样是模块级状态，会跨用例残留。
  --   若不清，新用例的签名可能恰好等于上个用例留下的候选 → 闸门被误判为「已稳定」，
  --   用例就会以误导的方式失败（与钉子池残留同一个坑，见 1.70.32/1.70.37）。
end
function EVAL_DS_TEST_DRAW_COUNT() return dsAnnDrawCount end -- 直读「重建发生了几次」
-- ★1.70.44 测试直调：走**生产用的** dsSetOverlay（而不是在测试里另写一份赋值）。
--   这正是本轮 bug 逃过测试的原因：原 capture 辅助「直接构造覆盖层」= 自己写了一个
--   与生产无关的赋值，于是「setter 绑到全局 / draw 读到局部」的分歧在测试里完全不可见。
--   ★教训（第 4 次同型）：测试必须调用被测代码的真实入口，自己复刻一份就等于没测。
function EVAL_DS_TEST_CALL_SET_OVERLAY(loc) return dsSetOverlay(loc) end
-- 另一个读者：诊断串也读同一个变量。断言「setter 写完之后，两个读者都看得见」。
function EVAL_DS_TEST_OVERLAY_STR() return dsOverlayStr() end
function EVAL_DS_TEST_ALL_PINS_HIDDEN() -- 池内钉子是否全部处于隐藏态（用户可见契约）
  for _, f in ipairs(dsAnnPins) do
    if type(f.IsShown) == "function" and f:IsShown() then return false end
  end
  return true
end
function EVAL_DS_TEST_FORCE_LAYER_OFF() dsAnnOn = false end -- 只置开关，故意不清钉子
function EVAL_DS_TEST_SET_EMPTY_RESULTS(on) dsTestEmptyResults = on and true or nil end
-- 磁盘存在性校验放在 node 侧（test_engine.js）：fengari 沙箱内 io 不可用，
-- 而「素材路径写错=静默不画」这条只能靠真实文件系统验证。
-- 摆放时的两个行为契约（用假 client 记录调用，不依赖真实地图）
function EVAL_DS_TEST_PLACE_SETS_TEXTURE_EACH_TIME()
  local calls = {}
  local fake = {
    CreateWorldMapPin = function() return {} end,
    SetWorldMapPinHandlers = function() end,
    SetWorldMapPinSize = function(_, w, h) calls[#calls + 1] = "size" end,
    SetWorldMapPinTexture = function(_, t) calls[#calls + 1] = "tex:" .. tostring(t) end,
    SetWorldMapPinColor = function() calls[#calls + 1] = "color" end,
    PositionWorldMapPin = function() calls[#calls + 1] = "pos" end,
  }
  -- 用同一枚池位连续摆两次（模拟池子复用），第二次必须重新设素材与尺寸
  dsAnnPins = {}
  dsAnnPlace(fake, 1, { x = 1, y = 1, small = true }, 1, 0, 0, "herbs")
  local first = table.concat(calls, ",")
  calls = {}
  dsAnnPlace(fake, 1, { x = 2, y = 2 }, 1, 0, 0, "spirithealer")
  local second = table.concat(calls, ",")
  dsAnnPins = {}
  return string.find(first, "tex:") ~= nil and string.find(second, "tex:") ~= nil
end
-- 记录一次真实重绘里「每条标注实际用了什么素材」，用于断言接线（而不是只断言解析函数）。
-- 返回 { {icon=..., small=...}, ... }，按摆放顺序。
function EVAL_DS_TEST_CAPTURE_DRAW(areaId)
  local captured = {}
  local realPlace = dsAnnPlace
  -- 用真实的 client（UnrealQuest 在测试 stub 里是打桩的），只把「记参数」包一层
  local client = dsUQClient()
  if not client then return captured end
  dsAnnPlace = function(c, idx, info, r, g, b, icon)
    -- ★1.70.41 也记颜色：用户要求搜索定位小圆点「每只怪一个随机颜色」。只断言
    --   dsEntityColor()（解析函数）会漏掉「调用点写死一个常量色」的变异——
    --   这正是 1.70.26 记过的「断言解析函数 ≠ 断言调用点」。必须记**调用点实际传的**值。
    captured[table.getn(captured) + 1] = {
      icon = icon, small = info and info.small, cat = info and info.category,
      r = r, g = g, b = b, kind = info and info.kind, id = info and info.id,
    }
    return false -- 不真的建钉子，只记参数
  end
  pcall(dsAnnDraw, areaId)
  dsAnnPlace = realPlace
  return captured
end
-- 专测搜索结果覆盖层的摆放参数：设置一个覆盖层，真实重绘，看看它有没有被塞图标。
function EVAL_DS_TEST_CAPTURE_OVERLAY(areaId)
  -- ★★★1.70.44 改走**生产用的 setter**（dsSetOverlay），不再自己构造一份赋值。
  --   原实现在这里直接写 dsAnnOverlay —— 那恰好绕开了生产路径，于是
  --   「setter 绑到全局 / draw 读到局部」这条分歧在测试里完全不可见（测试全绿、功能全废）。
  --   ★这是「测试里复刻逻辑 ⇒ 被测代码的变异不可见」的第 4 次发作（见 1.70.25/26/28）。
  --   现在：如果 setter 写错了变量，下面 dsAnnDraw 就看不到覆盖层 → hasOverlay=false → 断言变红。
  local okSet = EVAL_DS_TEST_CALL_SET_OVERLAY({
    zid = areaId, name = "测试条目", kind = "unit", id = 1, x = 50, y = 50,
  })
  local strBefore = EVAL_DS_TEST_OVERLAY_STR() -- 另一个读者：诊断串
  local cap = EVAL_DS_TEST_CAPTURE_DRAW(areaId)
  local hasOverlay, allDots = false, true
  for _, c in ipairs(cap) do
    -- 覆盖层的 pts 只有 1 个点、且带 ov 语义；用「无类别」识别它
    if c.cat == nil then
      hasOverlay = true
      if c.icon then allDots = false end
    end
  end
  dsAnnOverlay = nil
  -- ★1.70.41 把覆盖层实际用的颜色也带出来（用于断言「颜色确实来自 dsEntityColor 派生」）
  local ovcol = nil
  for _, c in ipairs(cap) do
    if c.cat == nil then ovcol = { r = c.r, g = c.g, b = c.b } break end
  end
  -- ★把两个读者看到的结果一并返回：断言「setter 之后两个读者都看得见」，
  --   这正是本轮 bug 的直接反例（一个看得见、一个看不见）。
  return { hasOverlay = hasOverlay, allDots = allDots, n = table.getn(cap), color = ovcol,
    setOk = okSet and true or false, str = strBefore }
end
function EVAL_DS_TEST_ICON_NOT_TINTED()
  local tinted = nil
  local fake = {
    CreateWorldMapPin = function() return {} end,
    SetWorldMapPinHandlers = function() end,
    SetWorldMapPinSize = function() end,
    SetWorldMapPinTexture = function() end,
    SetWorldMapPinColor = function(_, r, g, b) tinted = { r, g, b } end,
    PositionWorldMapPin = function() end,
  }
  dsAnnPins = {}
  dsAnnPlace(fake, 1, { x = 1, y = 1 }, 0.4, 0.85, 0.35, "herbs")
  local iconUntinted = tinted and tinted[1] == 1 and tinted[2] == 1 and tinted[3] == 1
  tinted = nil
  dsAnnPlace(fake, 1, { x = 1, y = 1 }, 0.4, 0.85, 0.35, nil)
  local dotTinted = tinted and tinted[1] == 0.4 and tinted[2] == 0.85 and tinted[3] == 0.35
  dsAnnPins = {}
  return (iconUntinted and dotTinted) and true or false
end
function EVAL_DS_TEST_DD_MENU() return dsCatMenu() end
function EVAL_DS_TEST_DD_SEL() -- key -> true（按当前类别状态派生，与面板所见一致）
  local m, out = dsCatMenu(), {}
  for i = 1, table.getn(m.keys) do
    local k = m.keys[i]
    if k and m.sel[i] and k ~= "__all_on__" and k ~= "__all_off__" then out[k] = true end
  end
  return out
end
function EVAL_DS_TEST_DD_PICK(k, nowOn)
  if k == "__all_on__" or k == "__all_off__" then
    dsCatMenuPick(k, true)
    return
  end
  -- Cannot write "(nowOn ~= nil) and nowOn or <default>": the Lua and/or idiom cannot
  -- express false (when nowOn=false the left side yields false and falls through to the
  -- default branch). Must test for nil explicitly.
  if nowOn == nil then nowOn = not EVAL_DS_CAT_ON(k) end
  dsCatMenuPick(k, nowOn and true or false)
end
function EVAL_DS_TEST_DD_LOCKED_COUNT()
  local m, n = dsCatMenu(), 0
  for i = 1, table.getn(m.items) do if m.locked[i] then n = n + 1 end end
  return n
end
function EVAL_DS_TEST_DD_IS_LOCKED(label) -- 按标签片段找行，返回该行是否锁定
  local m = dsCatMenu()
  for i = 1, table.getn(m.items) do
    if string.find(m.items[i], label, 1, true) then return m.locked[i] and true or false end
  end
  return nil
end

-- ===== 构建入口（配置窗调用；page.widgets 走 Tab 显隐契约） =====
function EVAL_DS_BUILD(root, page, refreshes)
  if DS.built then return end
  local widgets = page.widgets
  local LX = 18
  local RW = (root.GetWidth and root:GetWidth() or 560) - 18

  -- ★★★1.70.41 控制行几何常量**必须先于任何使用点声明**（本项目第 10 次踩 local 作用域）。
  --   症状：用户截图「应该有个按钮没了」——「类型: 全部」过滤钮整颗不显示。
  --   根因：filterBtn（下方几行）用 DSL_ROW_BTN_Y 定位，而该 local 在 **35 行之后**才声明，
  --   于是那里读到的是**全局 nil** → SetPoint("TOPLEFT", parent, "TOPLEFT", x, nil)
  --   → 该客户端对 nil 锚点不做任何定位（不报错）→ 按钮落在未定义位置 = 看不见。
  --   ★这是「不报错的空操作」的又一实例：Lua 不报错、pcall 全成功、断言也查不到，
  --   因为测试桩根本不校验 SetPoint 的坐标参数（见下方断言只用构建期同源常量）。
  --   ★教训重申：函数体内所有互相引用的局部量，声明顺序必须按「被依赖者在前」排列；
  --   把一组布局常量集中放在**函数开头**，一次性消除这类顺序陷阱。
  local DSL_ROW_CY = -64      -- 整行中线
  local DSL_BTN_H  = 16       -- 按钮高
  local DSL_BOX_H  = 20       -- 输入框高
  -- ★坐标系提醒：TOPLEFT 锚点的 y 是「顶边」，且 y 越往下越负。
  --   所以 顶边 = 中线 + 高度/2（因为中线在顶边【下方】，即更负），推导见下：
  --     顶边 = 中线 + 高度/2  →  -56 = -64 + 8  ✔（顶边在上，数值更大）
  --   （我第一版写成「中线 = 顶边 + 高度/2 = -48」是错的，测试当场抓到——见断言。
  --     正确：中线 = 顶边 - 高度/2 = -56 - 8 = -64）
  local DSL_ROW_BTN_Y = DSL_ROW_CY + DSL_BTN_H / 2   -- 按钮顶边 = -56
  local DSL_ROW_BOX_Y = DSL_ROW_CY + DSL_BOX_H / 2   -- 输入框顶边 = -54

  -- 类型过滤钮（下拉）
  DS.filterBtn = dsBtn(root, LX, DSL_ROW_BTN_Y, 96, "", function()
    if type(EVAL_DD_OPEN) ~= "function" then return end
    EVAL_DD_OPEN(DS.filterBtn.btn, {
      L("DS_F_ALL"), L("DS_F_QUEST"), L("DS_F_ITEM"), L("DS_F_UNIT"), L("DS_F_OBJECT"),
    }, function(pi)
      DS.filter = ({ "all", "quest", "item", "unit", "object" })[pi] or "all"
      DS.filterBtn.text:SetText(L("DS_FILTER") .. ": " .. ({ L("DS_F_ALL"), L("DS_F_QUEST"), L("DS_F_ITEM"), L("DS_F_UNIT"), L("DS_F_OBJECT") })[pi])
      if DS.lastQuery and DS.lastQuery ~= "" then DS.due = ((type(GetTime) == "function") and GetTime() or 0) + 0.05 end
    end)
  end, widgets)
  DS.filterBtn.text:SetText(L("DS_FILTER") .. ": " .. L("DS_F_ALL"))

  -- 地图标注控制（1.70.23 合并为单按钮）：一个「地图标注(N)」按钮 = 总开关入口 + 类别多选下拉。
  -- 用户要求「合并两个按钮」+「删除清理标注的功能，开关已经在列表内具备」——
  -- 故原独立的总开关按钮与「清理标注」按钮都撤销，能力全部收进这一个下拉：
  --   · 任何类别勾上 = 图层自动开启；全部取消 = 图层自动关闭（等价于原来的总开关）
  --   · 「全部关闭」同时清除搜索结果定位钉（否则那些钉没有任何入口可移除）
  -- 控件靠右（右缘 542 = 560-18），让开左侧搜索输入区。
  local function catLabel() -- 「地图标注(N)」N=已开启类别数，一眼看出图层是否生效
    return L("DS_NODES") .. "(" .. tostring(EVAL_DS_CAT_COUNT()) .. ")"
  end
  -- ★1.70.30 控制行统一垂直基准（用户截图「位置错行」的根治）：
  --   整行共用一个「中线」常量，各控件的 y 一律由它推导，不再各写各的魔法数字。
  --   起因：按钮/输入框按中线定位，占位提示却按文字顶边定位（-62），
  --   两者基准不同 → 提示比输入框文字低约 3.5px（用户截图里的红线段）。
  --   教训：同一行里混用「顶边对齐」与「中线对齐」必然错位；统一到中线最稳，
  --   且字体行高变化（enUS/ruRU 字体链不同）时也不会再漂。
  -- （布局常量已在函数开头声明——见 DSL_ROW_* 处的说明，勿在此重复声明）
  DS.catBtn = dsBtn(root, LX + 310, DSL_ROW_BTN_Y, 214, "", function()
    if type(EVAL_DD_OPEN) ~= "function" then return end
    local m = dsCatMenu() -- 菜单结构提到文件作用域，便于测试直接断言（不再藏在闭包里）
    EVAL_DD_OPEN(DS.catBtn.btn, m.items, function(pi, nowOn)
      dsCatMenuPick(m.keys[pi], nowOn)
      DS.catBtn.text:SetText(catLabel())
    end, { multi = true, selected = m.sel, locked = m.locked })
  end, widgets)
  DS.catBtn.text:SetText(catLabel())

  -- 搜索输入（EditBox + 回声行兜底——1.15.1 EditBox 疑似不渲染教训）
  local ebBg = root:CreateTexture(nil, "BACKGROUND")
  dsSolid(ebBg, 0.10, 0.09, 0.06, 1)
  ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 102, DSL_ROW_BOX_Y)
  ebBg:SetWidth(180) ebBg:SetHeight(20)
  table.insert(widgets, ebBg)
  local eb = CreateFrame("EditBox", nil, root)
  eb:SetWidth(168) eb:SetHeight(18)
  eb:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 106, DSL_ROW_BOX_Y - 1)
  pcall(eb.EnableMouse, eb, true)
  pcall(eb.SetAutoFocus, eb, false)
  -- 1.70.3 文字左对齐：本客户端 EditBox 默认文字/光标居中偏右（用户截图），显式压左 + 清内缩
  pcall(eb.SetJustifyH, eb, "LEFT")
  pcall(eb.SetJustifyV, eb, "MIDDLE")
  pcall(eb.SetTextInsets, eb, 2, 0, 0, 0) -- 左内缩 2px，其余 0
  pcall(eb.SetAltArrowKeyMode, eb, false)
  local setF = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(eb.SetFontObject, eb, fo) then setF = true break end
  end
  if not setF then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
      if okF and ok2 then setF = true break end
    end
  end
  DS.eb = eb
  table.insert(widgets, eb)
  -- 回声行（保底）：本客户端实测 EditBox 可正常渲染（截图确认）→ 仅在字体链全部失败（疑似不渲染，1.15.1 场景）时才显示，
  -- 否则 EditBox 自身文字 + 回声行 = 输入框里同一内容渲染两遍（用户实测反馈「返回后输入框出现重复文字」）
  local echo = dsText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 108, -58) -- 与 EditBox 文本起点对齐（同为左对齐）
  pcall(echo.SetWidth, echo, 164)
  pcall(echo.SetJustifyH, echo, "LEFT")
  DS.echo = echo
  DS.echoNeeded = not setF -- setF=false 才需要回声兜底
  if DS.echoNeeded then echo:Show() else echo:Hide() end
  table.insert(widgets, echo)
  eb:SetScript("OnTextChanged", function()
    local ok, t = pcall(eb.GetText, eb)
    if ok and type(t) == "string" then echo:SetText(t) end
    DS.due = ((type(GetTime) == "function") and GetTime() or 0) + 0.25
  end)
  eb:SetScript("OnEnterPressed", function() pcall(eb.ClearFocus, eb) dsDoSearch() end)
  eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
  local focusBtn = CreateFrame("Button", nil, root) -- 点击输入区聚焦
  focusBtn:SetWidth(180) focusBtn:SetHeight(20) -- 跟随输入框宽度（旧值 304 会盖住右侧按钮）
  focusBtn:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 102, DSL_ROW_BOX_Y)
  pcall(focusBtn.EnableMouse, focusBtn, true)
  pcall(focusBtn.RegisterForClicks, focusBtn, "LeftButtonUp")
  focusBtn:SetScript("OnClick", function() pcall(eb.SetFocus, eb) end)
  table.insert(widgets, focusBtn)
  local ph = dsText(root, 9, 0.62, 0.58, 0.46)
  -- 占位提示对齐输入框文字起点（框 120..300），宽度必须夹在框内——
  -- 不限制会溢出、压到右侧按钮上（用户截图反馈的正是这个）
  --
  -- ★1.70.30 修复「位置错行」（用户截图：占位提示比输入框文字低一截）：
  --   旧写法 SetPoint("TOPLEFT", ..., -62) 是**按文字块顶边**定位，而 EditBox 用
  --   SetJustifyV("MIDDLE") 是**按文字中线**定位——两套基准不同，于是 FontString 的
  --   实际中线约在 -67.5，比输入框文字中线(-64)低 3.5px。
  --   现在改成**按中线对齐**（LEFT 锚 + 纵向 CENTER 到输入框中线 -64）：
  --   这样字体/字号/语言（enUS/ruRU 字体链不同、行高不同）变化时都不会再错位。
  --   教训：同一行里混用「顶边对齐」和「中线对齐」必然错位；要么全用中线，要么全用顶边。
  ph:SetPoint("LEFT", root, "TOPLEFT", LX + 106, DSL_ROW_CY)
  pcall(ph.SetWidth, ph, 172)
  pcall(ph.SetJustifyH, ph, "LEFT")
  ph:SetText(L("DS_PH"))
  DS.ph = ph
  table.insert(widgets, ph)
  -- 详情模式整行隐藏（修重叠）；echo 仅在需要兜底时入列（否则会与 EditBox 文字重复渲染）
  -- ★1.70.30 记录控制行的「预期几何」，供测试断言整行中线一致（该行两次出布局问题）。
  --   与上面的实际 SetPoint 用同一批数字（下方 DSL_ROW_CY 常量），避免测试里再抄一份。
  DS.controlRow = {
    boxCenter = DSL_ROW_CY,
    phCenter = DSL_ROW_CY, -- 占位提示与输入框同中线（LEFT 锚 + 该 y 即中线）
    phAnchorV = "CENTER",
    buttons = {
      -- 中线 = 顶边 - 高度/2（顶边数值更大、中线更负）
      -- ★1.70.41：filterBtn 必须在此登记。它曾因 DSL_ROW_BTN_Y 声明顺序错误而被
      --   以 nil 定位（按钮不显示）；登记后 center 一旦为 nil 断言立刻变红。
      { name = "类型", center = DSL_ROW_BTN_Y - DSL_BTN_H / 2 },
      { name = "地图标注", center = DSL_ROW_BTN_Y - DSL_BTN_H / 2 },
    },
  }
  DS.searchWidgets = { DS.filterBtn.btn, ebBg, eb, ph, focusBtn, DS.catBtn.btn }
  table.insert(DS.searchWidgets, echo)

  -- ===== UnrealQuest 缺失引导面板（1.70.46，用户要求「未安装时给友好的依赖提示」）=====
  -- 旧实现只有一行黄字。改为一块面板，回答用户的四个问题：
  --   ① 缺什么（标题）② 为什么需要它（数据来源）③ 我该做什么（按**探测到的真实状态**分叉）
  --   ④ 会影响别的功能吗（只影响本页）。
  -- ★文案由 dsDepText() 给出（与断言共用同一份），面板只负责摆放。
  -- ★只用「底色 + 左侧金色竖条」，不用四边框贴图：文字换行/字体链差异都不会显得「破框」。
  local DEP_PAD, DEP_W = 14, RW - 36
  local dep = CreateFrame("Frame", nil, root)
  dep:SetPoint("TOPLEFT", root, "TOPLEFT", LX, -104)
  dep:SetWidth(DEP_W) dep:SetHeight(132)
  local depBg = dep:CreateTexture(nil, "BACKGROUND")
  dsSolid(depBg, 0.11, 0.09, 0.05, 0.92)
  depBg:SetPoint("TOPLEFT", dep, "TOPLEFT", 0, 0)
  depBg:SetPoint("BOTTOMRIGHT", dep, "BOTTOMRIGHT", 0, 0)
  local depBar = dep:CreateTexture(nil, "ARTWORK") -- 左侧金色竖条
  dsSolid(depBar, 0.95, 0.78, 0.25, 0.85)
  depBar:SetPoint("TOPLEFT", dep, "TOPLEFT", 0, 0)
  depBar:SetWidth(3) depBar:SetHeight(132)
  local depTitle = dsText(dep, 12, 0.98, 0.84, 0.35)
  depTitle:SetPoint("TOPLEFT", dep, "TOPLEFT", DEP_PAD, -12)
  pcall(depTitle.SetWidth, depTitle, DEP_W - DEP_PAD * 2)
  pcall(depTitle.SetJustifyH, depTitle, "LEFT")
  local depWhy = dsText(dep, 10, 0.80, 0.76, 0.62)
  depWhy:SetPoint("TOPLEFT", dep, "TOPLEFT", DEP_PAD, -38)
  pcall(depWhy.SetWidth, depWhy, DEP_W - DEP_PAD * 2)
  pcall(depWhy.SetJustifyH, depWhy, "LEFT")
  local depMsg = dsText(dep, 10, 0.96, 0.82, 0.32) -- 状态对策（按探测结果变化）
  depMsg:SetPoint("TOPLEFT", dep, "TOPLEFT", DEP_PAD, -72)
  pcall(depMsg.SetWidth, depMsg, DEP_W - DEP_PAD * 2)
  pcall(depMsg.SetJustifyH, depMsg, "LEFT")
  local depFoot = dsText(dep, 9, 0.62, 0.58, 0.46)
  depFoot:SetPoint("TOPLEFT", dep, "TOPLEFT", DEP_PAD, -104)
  pcall(depFoot.SetWidth, depFoot, DEP_W - DEP_PAD * 2)
  pcall(depFoot.SetJustifyH, depFoot, "LEFT")
  DS.dep = { frame = dep, title = depTitle, why = depWhy, msg = depMsg, foot = depFoot, w = DEP_W }
  table.insert(widgets, dep) -- 只登记外框：子 FontString 随外框显隐，不会有「藏了面板还留一行字」

  -- 结果行 ×10（模拟下拉：输入框正下方；左图标=链接指向类型，右地图图标=有坐标可定位）
  DS.resRows = {}
  for i = 1, DS_RES_ROWS do
    local y = -96 - (i - 1) * 22
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(RW - 62) b:SetHeight(20)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", LX, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    dsSolid(bg, 0.14, 0.12, 0.07, 1)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    -- 左类型图标：独立按钮（纹理不接收鼠标；与行点击同效=进入该条目详情）
    local ib = CreateFrame("Button", nil, root)
    ib:SetWidth(16) ib:SetHeight(16)
    ib:SetPoint("LEFT", b, "LEFT", 3, 0)
    pcall(ib.EnableMouse, ib, true)
    pcall(ib.RegisterForClicks, ib, "LeftButtonUp")
    pcall(function() ib:SetFrameLevel((b:GetFrameLevel() or 1) + 2) end)
    local ic = ib:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", ib, "TOPLEFT", 0, 0)
    ic:SetPoint("BOTTOMRIGHT", ib, "BOTTOMRIGHT", 0, 0)
    ib:Hide()
    local bt = dsText(b, 10, 0.92, 0.88, 0.80)
    bt:SetPoint("LEFT", b, "LEFT", 22, 0)
    pcall(bt.SetWidth, bt, RW - 92)
    pcall(bt.SetJustifyH, bt, "LEFT")
    local row = { btn = b, bg = bg, text = bt, icon = ic, iconBtn = ib, kind = nil, id = nil, loc = nil }
    local mb = CreateFrame("Button", nil, root) -- 地图定位钮（仅该行有坐标时显示）
    mb:SetWidth(16) mb:SetHeight(16)
    mb:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    pcall(mb.EnableMouse, mb, true)
    pcall(mb.RegisterForClicks, mb, "LeftButtonUp")
    pcall(function() mb:SetFrameLevel((b:GetFrameLevel() or 1) + 2) end) -- 叠在整行按钮之上（否则点击被行按钮吃掉）
    local mtex = mb:CreateTexture(nil, "ARTWORK")
    pcall(mtex.SetTexture, mtex, DS_MAP_ICON)
    mtex:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)
    mtex:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", 0, 0)
    mb:SetScript("OnClick", function() if row.loc then EVAL_DS_SHOWMAP(row.loc) end end)
    mb:SetScript("OnEnter", function()
      if not row.loc or type(GameTooltip) == "nil" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, mb, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetText, GameTooltip, L("DS_MAP_TIP"))
      pcall(GameTooltip.Show, GameTooltip)
    end)
    mb:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    mb:Hide()
    table.insert(widgets, mb)
    table.insert(widgets, ib)
    row.mapBtn = mb
    ib:SetScript("OnClick", function() -- 左图标=进入该条目（与点行文字同效）
      if row.kind and row.id then dsNavPush(row.kind, row.id) end
    end)
    ib:SetScript("OnEnter", function()
      if row.kind == "item" and row.id and type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, ib, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.id))
      end
    end)
    ib:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    b:SetScript("OnClick", function()
      if row.kind and row.id then dsNavPush(row.kind, row.id) end
    end)
    b:SetScript("OnEnter", function() -- 物品行悬停=游戏内物品 tooltip（GameTooltip:SetHyperlink wiki 已确认）
      if row.kind == "item" and row.id and type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(row.id))
      end
    end)
    b:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    b:Hide()
    table.insert(widgets, b)
    DS.resRows[i] = row
  end

  -- 详情视图：顶部+底部双返回钮（无限级联逐层回退） + 标题/副标题/标题地图钮 + 关联行 ×14
  DS.back = dsBtn(root, LX, -56, 60, L("DS_RESET"), function() dsResetSearch() end, widgets) -- 1.70.7：顶部=重置搜索状态
  DS.backTop = DS.back
  DS.backBottom = dsBtn(root, LX + 8, -96 - DS_DET_LINES * 20 - 6, 60, L("DS_BACK"), function() dsNavBack() end, widgets)
  DS.title = dsText(root, 12, 0.95, 0.82, 0.35)
  DS.title:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 70, -58)
  pcall(DS.title.SetWidth, DS.title, 330)
  pcall(DS.title.SetJustifyH, DS.title, "LEFT")
  table.insert(widgets, DS.title)
  DS.subtitle = dsText(root, 10, 0.75, 0.72, 0.60)
  DS.subtitle:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 70, -74)
  pcall(DS.subtitle.SetWidth, DS.subtitle, 400)
  pcall(DS.subtitle.SetJustifyH, DS.subtitle, "LEFT")
  table.insert(widgets, DS.subtitle)
  local tmb = CreateFrame("Button", nil, root) -- 标题行地图定位钮
  tmb:SetWidth(16) tmb:SetHeight(16)
  tmb:SetPoint("TOPLEFT", root, "TOPLEFT", RW - 60, -56)
  pcall(tmb.EnableMouse, tmb, true)
  pcall(tmb.RegisterForClicks, tmb, "LeftButtonUp")
  pcall(function() tmb:SetFrameLevel((root:GetFrameLevel() or 1) + 2) end)
  local ttex = tmb:CreateTexture(nil, "ARTWORK")
  pcall(ttex.SetTexture, ttex, DS_MAP_ICON)
  ttex:SetPoint("TOPLEFT", tmb, "TOPLEFT", 0, 0)
  ttex:SetPoint("BOTTOMRIGHT", tmb, "BOTTOMRIGHT", 0, 0)
  tmb:SetScript("OnClick", function() if DS.titleLoc then EVAL_DS_SHOWMAP(DS.titleLoc) end end)
  tmb:Hide()
  table.insert(widgets, tmb)
  DS.titleMap = tmb
  DS.detLines = {}
  for i = 1, DS_DET_LINES do
    local y = -96 - (i - 1) * 20
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(RW - 70) b:SetHeight(18) -- 1.70.7 收窄 30px：右侧留出独立滚动列（原来行右缘与 [▲][▼] 重叠）
    b:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 8, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    -- 左「链接指向」图标：独立按钮（原来只是 b 的纹理——纹理不接收鼠标，且与右地图钮行为不一致，
    -- 用户实测「左右两个图标都点不到」→ 两端都改成显式按钮 + 抬高 frameLevel，点击效果与行文字一致）
    local ib = CreateFrame("Button", nil, root)
    ib:SetWidth(16) ib:SetHeight(16)
    ib:SetPoint("LEFT", b, "LEFT", 2, 0)
    pcall(ib.EnableMouse, ib, true)
    pcall(ib.RegisterForClicks, ib, "LeftButtonUp")
    pcall(function() ib:SetFrameLevel((b:GetFrameLevel() or 1) + 2) end)
    local ic = ib:CreateTexture(nil, "ARTWORK")
    ic:SetPoint("TOPLEFT", ib, "TOPLEFT", 0, 0)
    ic:SetPoint("BOTTOMRIGHT", ib, "BOTTOMRIGHT", 0, 0)
    ib:Hide()
    local bt = dsText(b, 10, 0.88, 0.85, 0.75)
    bt:SetPoint("LEFT", b, "LEFT", 22, 0)
    pcall(bt.SetWidth, bt, RW - 92)
    pcall(bt.SetJustifyH, bt, "LEFT")
    local ln = { btn = b, text = bt, icon = ic, iconBtn = ib, link = nil, hoverItem = nil, loc = nil }
    local mb = CreateFrame("Button", nil, root)
    mb:SetWidth(15) mb:SetHeight(15)
    mb:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    pcall(mb.EnableMouse, mb, true)
    pcall(mb.RegisterForClicks, mb, "LeftButtonUp")
    -- ★叠在整行按钮之上：整行 b 宽 502 把地图钮区域整个包在里面，同层时点击会被 b 吃掉（用户实测「点图标没反应」）
    pcall(function() mb:SetFrameLevel((b:GetFrameLevel() or 1) + 2) end)
    local mtex = mb:CreateTexture(nil, "ARTWORK")
    pcall(mtex.SetTexture, mtex, DS_MAP_ICON)
    mtex:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)
    mtex:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", 0, 0)
    mb:SetScript("OnClick", function() if ln.loc then EVAL_DS_SHOWMAP(ln.loc) end end)
    -- 左图标按钮：与整行同效（进入关联条目）+ 物品悬停 tooltip
    ib:SetScript("OnClick", function() if ln.link then dsNavPush(ln.link.kind, ln.link.id) end end)
    ib:SetScript("OnEnter", function()
      if ln.hoverItem and type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, ib, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(ln.hoverItem))
      end
    end)
    ib:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    mb:SetScript("OnEnter", function()
      if not ln.loc or type(GameTooltip) == "nil" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, mb, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetText, GameTooltip, L("DS_MAP_TIP"))
      pcall(GameTooltip.Show, GameTooltip)
    end)
    mb:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    mb:Hide()
    table.insert(widgets, mb)
    table.insert(widgets, ib) -- 左图标按钮也走 Tab 显隐契约
    ln.mapBtn = mb
    b:SetScript("OnClick", function()
      if ln.link then dsNavPush(ln.link.kind, ln.link.id) end -- 无限级联：只要有关联即可继续点
    end)
    b:SetScript("OnEnter", function()
      if ln.hoverItem and type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. tostring(ln.hoverItem))
      end
    end)
    b:SetScript("OnLeave", function() if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end end)
    b:Hide()
    table.insert(widgets, b)
    DS.detLines[i] = ln
  end

  -- 1.70.4 详情滚动：[▲][▼] + 计数指示；滚轮【链式接管】配置窗 root 的既有 OnMouseWheel
  -- ★root:SetScript 是单槽位：Toolbox(Tab3) 已占用该脚本，直接 SetScript 会把它的滚轮顶掉 ——
  --   故这里先取出旧处理器，包一层（仅本 Tab 激活且滚轮未被消费时才转发给旧处理器）。
  DS.scrollUp = dsBtn(root, RW - 18, -96, 16, "▲", function()
    DS.detOff = math.max(0, (DS.detOff or 0) - 1)
    EVAL_DS_REFRESH()
  end, widgets)
  DS.scrollDn = dsBtn(root, RW - 18, -96 - (DS_DET_LINES - 1) * 20, 16, "▼", function()
    DS.detOff = (DS.detOff or 0) + 1
    EVAL_DS_REFRESH()
  end, widgets)
  local ind = dsText(root, 9, 0.65, 0.62, 0.50)
  ind:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -42, 52) -- 左移让开 [▼]（原来压在滚动钮上）
  pcall(ind.SetJustifyH, ind, "RIGHT")
  DS.indicator = ind
  table.insert(widgets, ind)
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  if type(root.GetScript) == "function" then
    local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  root:SetScript("OnMouseWheel", function(a, b)
    -- 数据检索 Tab 可见（搜索框在列即代表本 Tab 激活）且处于详情模式时才消费滚轮
    if dsTabActive() and dsMode() == "detail" then
      local d = b or arg1 or 0
      if d ~= 0 then
        DS.detOff = math.max(0, (DS.detOff or 0) - d)
        EVAL_DS_REFRESH()
        return
      end
    end
    if prevWheel then pcall(prevWheel, a, b) end -- 转发给 Toolbox 等既有处理器（不吞事件）
  end)

  DS.built = true
  EVAL_DS_REFRESH()
end

-- 诊断探针（/eh ds probe）：dump 详情行与两个图标的几何/鼠标/脚本状态——
-- 用于排查「图标看着在却点不动」这类命中区问题（本客户端 Button 热区与父子遮挡需实测，别猜）。
-- 测试直调：用最小 root/page 构建一次 UI，返回行结构（验证「两侧图标都是可点按钮」这类结构契约）
function EVAL_DS_BUILD_FOR_TEST()
  if DS.built then return true end
  local root = CreateFrame("Frame", "EVAL_DS_TEST_ROOT", UIParent)
  local page = { widgets = {} }
  EVAL_DS_BUILD(root, page, {})
  return DS.built == true
end
function EVAL_DS_TEST_LINE(i) return DS.detLines and DS.detLines[i] end
function EVAL_DS_TEST_ROW(i) return DS.resRows and DS.resRows[i] end

-- 依赖探测与引导面板的测试访问器（1.70.46）
-- ★断言必须落在**文案内容**上，不能只断言「面板存在/文本是字符串」——
--   旧文本会一直留在 FontString 里，跳过刷新也能让存在性断言通过（1.70.38 教训）。
function EVAL_DS_DEP_STATE() return dsDepState() end
function EVAL_DS_TEST_DEP_MSG()
  local d = DS.dep
  if not d then return nil end
  local ok, t = pcall(d.msg.GetText, d.msg)
  if ok then return t end
  return nil
end
function EVAL_DS_TEST_DEP_LINE(which)
  local d = DS.dep
  if not d then return nil end
  local fs = (which == "title") and d.title or (which == "why") and d.why
    or (which == "msg") and d.msg or (which == "foot") and d.foot
  if not fs then return nil end
  local ok, t = pcall(fs.GetText, fs)
  if ok then return t end
  return nil
end
function EVAL_DS_TEST_DEP_SHOWN()
  local d = DS.dep
  if not d then return nil end
  local ok, v = pcall(d.frame.IsShown, d.frame)
  if ok then return v end
  return nil
end
-- 状态 → 文案键（断言映射本身：只断言「四条文本两两不同」抓不到状态与文案被互换）
function EVAL_DS_TEST_DEP_KEY(st) return dsDepText(st) end
-- 控制行控件清单（断言「依赖缺席时交互控件全部收起」用）
function EVAL_DS_TEST_SEARCH_WIDGETS() return DS.searchWidgets end
-- 数据本地化子表所用的语言码（items_zhCN / units_enUS …）——与 L() 必须同源
function EVAL_DS_TEST_LANG() return dsLang() end

function EVAL_DS_PROBE()
  if not DS.built then return "未构建（先 /eh cfg 打开配置窗）" end
  local out = {}
  local function geo(name, f)
    if not f then table.insert(out, name .. ": nil") return end
    local okL, l = pcall(f.GetLeft, f)
    local okW, w = pcall(f.GetWidth, f)
    local okT, t = pcall(f.GetTop, f)
    local okH, h = pcall(f.GetHeight, f)
    local okS, s = pcall(f.IsShown, f)
    local okV, v = pcall(f.IsVisible, f)
    local okM = pcall(f.IsMouseEnabled, f)
    local okE, e = pcall(f.IsMouseEnabled, f)
    table.insert(out, string.format("%s: L=%s W=%s T=%s H=%s shown=%s vis=%s mouse=%s",
      name, tostring(l), tostring(w), tostring(t), tostring(h), tostring(s), tostring(v), tostring(okE and e or "?")))
  end
  for i, ln in ipairs(DS.detLines) do
    if ln.btn:IsShown() then
      geo("row" .. i, ln.btn)
      geo("rowIcon" .. i, ln.iconBtn)
      geo("rowMap" .. i, ln.mapBtn)
      table.insert(out, string.format("  row%d link=%s loc=%s script=%s mapScript=%s", i,
        ln.link and (ln.link.kind .. "#" .. tostring(ln.link.id)) or "nil",
        ln.loc and tostring(ln.loc.zid) or "nil",
        tostring(ln.btn:GetScript("OnClick") ~= nil),
        tostring(ln.mapBtn:GetScript("OnClick") ~= nil)))
      break -- 只 dump 第一个可见行，够定位问题
    end
  end
  geo("scrollUp", DS.scrollUp and DS.scrollUp.btn)
  geo("detLine1", DS.detLines[1] and DS.detLines[1].btn)
  for _, l in ipairs(out) do if type(EVAL_SAY) == "function" then EVAL_SAY(l) end end
  return table.concat(out, " | ")
end
