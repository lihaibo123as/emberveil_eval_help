-- ============================================================
-- EH_DebugBox 纯地图缩放试验（probe/map-scale 分支）
-- ★最一开始的极简版本：只测 SetScale 与悬停命中漂移，无其他任何功能。
--
-- 用法（全程 pcall 守卫；改动不持久化，/reload 还原）：
--   /edb 0.7      = 缩外框 WorldMapFrame
--   /edb b 0.7    = 缩画布 WorldMapButton
--   /edb d 0.7    = 缩 WorldMapDetailFrame
--   /edb all 0.7  = 三个一起缩
--   /edb off      = 全部回 1
--   /edb watch    = 开/关 悬停对照浮字（见下）
--
-- 悬停对照浮字（判断漂移的客观依据，不靠肉眼猜）：
--   地图顶部持续显示三行 ——
--     ① 我们算的鼠标 UV（GetCursorPosition vs 画布矩形，含 GetEffectiveScale 折算）
--     ② 原生悬停区域名（WorldMapFrameAreaLabel 实时文本 = 引擎认为你指着哪）
--     ③ 当前各帧缩放值
--   判读：鼠标指着奥格瑞玛时②应显示「奥格瑞玛」；缩放后②变成别的/空白 = 命中漂移实锤，
--   且①的 UV 若仍与视觉位置吻合 = 漂移在引擎侧的命中换算，Lua 救不回来。
-- ============================================================

local function P(msg)
  if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cff66ccff[EH_DebugBox]|r " .. tostring(msg))
  end
end

-- ★构建标记（唯一来源）：每次改本文件顺手 +1 —— 探针第一行就打它，
--   「跑的是不是最新版」一眼可辨（真机出现过「修了还报错」= 客户端还在跑旧构建）。
local DBX_BUILD = "1.74.34-28"

-- ===== 语言包（1.74.31）=====
-- 用户要求：新开关的**文案与 tooltip 走三语语言包**（Locales/zhCN|enUS|ruRU.lua 里 L("键") 三语齐全）。
-- 取法沿用主插件 Core.lua 的 EVAL_L 契约：当前语言 → 回退 zhCN → 再缺显示键名本身（可发现性）。
-- ★本子插件不加载 Locales/*.lua（那是主插件的模块），但两个插件**共享同一全局环境**（本项目已有先例：
--   本文件本来就在调主插件的 EVAL_DF_* / EVAL_LOGLINE）→ 运行期优先走全局 EVAL_L；
--   主插件没载入时退回读 EVAL_LOCALES 表；两者都没有才显示键名。
-- ★L 只在**运行期**调用（建面板/悬停时），绝不在文件作用域调用（载入时主插件可能还没解析语言）。
local function L(key, ...)
  if type(EVAL_L) == "function" then return EVAL_L(key, ...) end
  local all = EVAL_LOCALES
  local s = (type(all) == "table" and all.zhCN and all.zhCN[key]) or key
  if select("#", ...) == 0 then return s end
  local ok, f = pcall(string.format, s, ...)
  return (ok and type(f) == "string") and f or s
end

local function frameOf(key)
  local n = ({ frame = "WorldMapFrame", b = "WorldMapButton", d = "WorldMapDetailFrame" })[key] or key
  local f = _G[n]
  if type(f) == "table" or type(f) == "userdata" then return f, n end
  return nil, n
end

local function setScale(key, s)
  local f, n = frameOf(key)
  if not f then P(n .. " 不存在") return end
  if type(f.SetScale) ~= "function" then P(n .. " 无 SetScale 方法") return end
  local ok = pcall(f.SetScale, f, s)
  local okG, cur = pcall(f.GetScale, f)
  P(n .. " SetScale(" .. s .. ") 调用=" .. tostring(ok) .. " 读回=" .. tostring(okG and cur or "?"))
end

local function setAll(s)
  setScale("frame", s)
  setScale("b", s)
  setScale("d", s)
end

-- ===== 悬停对照浮字 =====
local watch = { on = false, label = nil, frame = nil }

local function watchEnsure()
  if watch.label then return true end
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then return false end
  if type(wm.CreateFontString) ~= "function" then return false end
  local ok, fs = pcall(wm.CreateFontString, wm, nil, "OVERLAY")
  if not ok or not fs then return false end
  pcall(fs.SetPoint, fs, "TOP", wm, "TOP", 0, -60)
  -- 中文字体链（本项目铁律）
  local fontOk = false
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    if not fontOk then
      local okf = pcall(fs.SetFont, fs, fp, 16, "OUTLINE")
      if okf then fontOk = true end
    end
  end
  if not fontOk and type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  pcall(fs.SetTextColor, fs, 1, 0.85, 0.2)
  watch.label = fs
  return true
end

local function watchTick()
  if not (watch.on and watch.label) then return end
  local wm = _G["WorldMapFrame"]
  local cv = _G["WorldMapButton"]
  if not (type(wm) == "table" or type(wm) == "userdata") then return end
  local uv = "UV=?"
  if type(GetCursorPosition) == "function"
    and (type(cv) == "table" or type(cv) == "userdata") then
    local ok, cx, cy = pcall(GetCursorPosition)
    local oks, es = pcall(wm.GetEffectiveScale, wm)
    local okc, ccx, ccy = pcall(cv.GetCenter, cv)
    local okw, cw = pcall(cv.GetWidth, cv)
    local okh, ch = pcall(cv.GetHeight, cv)
    if ok and oks and okc and okw and okh and es and es ~= 0 and ccx and cw and cw > 0 and ch > 0 then
      local mx, my = cx / es, cy / es
      local ax = (mx - (ccx - cw / 2)) / cw
      local ay = (ccy + ch / 2 - my) / ch
      uv = string.format("UV=%.1f,%.1f", ax * 100, ay * 100)
    end
  end
  local zone = "?"
  local al = _G["WorldMapFrameAreaLabel"]
  if (type(al) == "table" or type(al) == "userdata") and type(al.GetText) == "function" then
    local ok, t = pcall(al.GetText, al)
    if ok and type(t) == "string" and t ~= "" then zone = t end
  end
  local function gs(key)
    local f = frameOf(key)
    if f and type(f.GetScale) == "function" then
      local ok, v = pcall(f.GetScale, f)
      if ok and tonumber(v) then return string.format("%.2f", v) end
    end
    return "?"
  end
  pcall(watch.label.SetText, watch.label,
    uv .. "  原生悬停=" .. zone .. "  scale: 框" .. gs("frame") .. " 布" .. gs("b") .. " 详" .. gs("d"))
end

if type(CreateFrame) == "function" then
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  watch.frame = CreateFrame("Frame", "EH_DB_WATCH", parent)
  local acc = 0
  watch.frame:SetScript("OnUpdate", function()
    acc = acc + (tonumber(arg1) or 0.05)
    if acc < 0.15 then return end
    acc = 0
    watchTick()
  end)
end

-- ===== 全层打印 + 逐个缩放排查（用户要求：与黑幕通缉同款打法） =====
-- /edb list           = 递归打印 WorldMapFrame 全部子帧与图层（编号/名字/类型/尺寸/能否缩放）
-- /edb t 编号 0.7     = 只缩那一层
-- /edb t 编号 off     = 那一层回 1
-- /edb off            = 三个主帧 + 所有试过的层 全回 1
local nodes = nil
local scaledNodes = nil

-- ★★★1.74.31「有没有名字」的**唯一判据**（用户要求：只显示有名字的 / 默认隐藏没有名字的层）：
--   GetName() 返回**非空字符串**才算有名字 —— 与既有扫描统计（uiScanMeasure 的 命名/无名）同口径。
--   ★路径里的名字**不能当判据**：无名帧在路径里被写成 "?"（见 nodeName 的占位符），那是占位符不是名字。
-- ★★★1.74.34-26 安全字段读口（真机红字实证）：
--   `EH_DebugBox.lua:2377: attempt to index field 'f' (a userdata value)` —— 那一行正是
--   `if type(e.f.IsShown) == "function" then`：本客户端**个别对象根本不能索引**（frame/region 的 userdata
--   并非都有 `__index` 元表；`type()` 又骗人），直接 `obj.k` 会**抛错并打断整次刷新** ⇒ 用户看到红字弹窗、
--   面板数据停更。⇒ 凡「读来路可能不干净的对象的方法」一律走这里：读不到 = 当它没这个方法（与 uiRowEntry 同思路）。
--   ★不是洁癖：1.74.34-25 起列表会列出大量纹理/子件，**一个坏对象就能打断整条刷新**。
local function uiField(obj, k)
  if obj == nil then return nil end
  local ok, v = pcall(function() return obj[k] end)
  if ok then return v end
  return nil
end

local function uiFrameName(v)
  local fn = uiField(v, "GetName")
  if type(fn) == "function" then
    local ok, n = pcall(fn, v)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return nil
end

-- ★★★1.74.31 真因（/edb named 实证）：**本客户端 `Texture:GetName()` 会给无名纹理编一个名字**：
--   形如 `Interface/WorldMap/UI-WorldMap-Top2_0x000026D5551750`（贴图路径 + **内存地址**）。
--   → 单看“有没有字符串”会把它们全当「有名字」。现在把这类**合成名**一律排除。
local function uiNameLooksFake(n)
  if type(n) ~= "string" or n == "" then return true end
  if string.find(n, "0x%x%x%x%x") then return true end -- 地址式后缀（如 _0x000026D5551750）
  if string.find(n, "/", 1, true) then return true end   -- 资源路径（真帧名不含 / 也不含 ＼）
  if string.find(n, "\\", 1, true) then return true end
  return false
end
local function nodeName(v)
  local n = uiFrameName(v)
  if n then return n end
  return "?"
end

local function nodeType(v)
  local fn = uiField(v, "GetObjectType")
  if type(fn) == "function" then
    local ok, t = pcall(fn, v)
    if ok then return tostring(t) end
  end
  return "?"
end

-- ★1.74.34：节点上限兜底（超限**如实报**，绝不假装扫全）；深挖扫描（选中目标下钻）走 maxD=64，全量维持 4。
local SCAN_NODE_CAP = 20000
local scanHitCap = false

local function scanTree(f, path, depth, maxD)
  if depth > (maxD or 4) then return end
  if table.getn(nodes or {}) >= SCAN_NODE_CAP then scanHitCap = true return end
  -- ★★★1.74.34-11 修「纹理行无法单选（点一个全亮）」（用户截图实锤）：
  --   同一父级下的同名兄弟（`region:Texture` ×16、无名子帧 `?` ×N）会得到**完全相同的路径**，
  --   而选中/自定义/折叠全按路径做键 ⇒ 一个键命中一大片。现在在本父级内给同名兄弟加 **#n 序号**，
  --   让每个条目键唯一（根路径不变；第 1 个不加后缀 ⇒ 老存档键兼容）。
  local dup = {}
  local function uniq(base)
    dup[base] = (dup[base] or 0) + 1
    if dup[base] == 1 then return base end
    return base .. "#" .. dup[base]
  end
  if type(f.GetRegions) == "function" then
    local rr = { pcall(f.GetRegions, f) }
    if rr[1] then
      for i = 2, table.getn(rr) do
        local r = rr[i]
        if r then
          -- ★★★1.74.31 第二步：把**扫描时的层号**一并记下来（d = 这一层在第几层，根 = 1）。
          --   为什么要它：可折叠树的缩进/父子关系不能靠「路径里 '/' 的个数」推 ——
          --   ① 带前缀的源（`[界面] UIParent/（本体）`）会被多算一层（层深:1 在那些源上显示不出东西，本轮的 off-by-one 修复）；
          --   ② 同帧下的多个区域会得到**同名**路径（`.../region:Texture` 重复），路径本身不唯一（已在上方用 #n 补齐唯一性）。
          --   而 scanTree 的 depth 参数本来就是真层号（f 在第 depth 层，它的区域/子件在 depth+1 层）⇒ 直接用。
          -- ★★★1.74.34-24 用户报「加了可见性功能之后一些图层纹理信息就看不见了」的另一半原因：
          --   这一段原来**一律**用对象类型拼 `region:Texture` ⇒ 有真名的纹理（WorldMapDetailTile3 /
          --   WorldMapOverlay1 这类）在列表里也只显示成「纹理:Texture#7」，用户根本认不出是哪个贴图。
          --   现在：**有真名**的用真名（`region:WorldMapDetailTile3` → 列表显示「纹理:WorldMapDetailTile3」），
          --   无名/合成名的照旧退回类型名（`region:Texture` + `#n` 去重，老存档键格式不变）。
          local rn = uiFrameName(r)
          local rseg = (rn ~= nil and (not uiNameLooksFake(rn))) and ("region:" .. rn) or ("region:" .. nodeType(r))
          table.insert(nodes, { f = r, n = uniq(path .. "/" .. rseg), d = depth + 1 })
        end
      end
    end
  end
  if type(f.GetChildren) == "function" then
    local rc = { pcall(f.GetChildren, f) }
    if rc[1] then
      for i = 2, table.getn(rc) do
        local c = rc[i]
        if c then
          local nm = nodeName(c)
          local npath = uniq(path .. "/" .. nm)
          table.insert(nodes, { f = c, n = npath, d = depth + 1 })
          scanTree(c, npath, depth + 1, maxD)
        end
      end
    end
  end
end

-- ★★★1.74.29「一个不落」扫描（用户要求）：三路合并
--   ① 多根树遍历：WorldMapFrame / WorldFrame / UIParent / Minimap / MinimapCluster（+ 各自 regions）
--   ② 全 _G 游离帧：凡「帧样」（GetObjectType+IsShown+GetWidth/Height）且未被前面认领的全局对象
--      —— 本客户端会漏报子帧（实测 GetChildren 漏了 WorldMapDetailFrame），且存在 GeneratedLuaUIObject_* 这类
--      「有全局名但不在任何树里」的对象，只有扫 _G 才捞得到；
--   ③ 点名顶层名单（TOP）：黑幕/画布/标签/定位导引等关键件，保证它们在（含无名/纹理件）。
--   去重按**对象身份**；深度 8、节点上限 20000（超限如实报，绝不假装扫全）。
-- ★顶层相关帧点名采集（不在 WorldMapFrame 树里的：黑幕/容器/标签/定位导引等）
local TOP = {
  "WorldMapFrame", "WorldMapDetailFrame", "WorldMapButton", "WorldMapPositioningGuide",
  "WorldMapTooltip", "BlackoutWorld", "WorldMapBlackout",
  "WorldMapFrameAreaFrame", "WorldMapFrameAreaLabel", "WorldMapFrameAreaDescription",
  "WorldMapPlayer", "WorldMapCorpse", "MinimapCluster", "WorldFrame", "UIParent",
}

-- ★★★1.74.29 修（用户：「选中小地图扫描源时，扫出来的还是大地图的信息」）：
--   TOP 是**固定点名名单**，原来无条件追加到列表 → 只勾小地图时大地图那几件仍然在。
--   现在给每个名字标注它**属于哪个扫描源**，列表只收当前勾选的那些。
local TOP_SRC = {
  WorldMapFrame = "map", WorldMapDetailFrame = "map", WorldMapButton = "map",
  WorldMapPositioningGuide = "map", WorldMapTooltip = "map", BlackoutWorld = "map",
  WorldMapBlackout = "map", WorldMapFrameAreaFrame = "map", WorldMapFrameAreaLabel = "map",
  WorldMapFrameAreaDescription = "map", WorldMapPlayer = "map", WorldMapCorpse = "map",
  MinimapCluster = "mini",
  WorldFrame = "world",
  UIParent = "ui",
}
local function topSrcOf(nm) return TOP_SRC[nm] or "map" end
-- ★★1.74.29 还原（用户要求）：层检索方式回到本次会话之前的做法 ——
--   **单根扫描** WorldMapFrame 树（scanTree 递归，深度 ≤4，含 regions），再在列表里追加点名顶层名单 TOP；
--   不再多根（WorldMapFrame/WorldFrame/UIParent/Minimap…）、不再全 _G 游离帧扫描。
-- ★ui 表的前向声明：扫描源判定（uiScanSrcOn）在本段就要读 ui.scanSrc，
--   而 ui 表本体在下方几百行处才定义 —— 不声明就是「读到全局 nil」（同 §5.1 那条铁律）。
local ui

-- ★★用户要求（1.74.29）：把 **UIParent** 加入扫描类型 ⇒ 做成**扫描源多选**（默认只勾「地图」，
--   保持此前「会话前那套单根检索」的行为不变；勾上界面/世界层/小地图才追加那些根）。
local SCAN_SRC = {
  { k = "map", label = "地图", root = "WorldMapFrame", prefix = nil },          -- 前缀空 = 沿用 WorldMapFrame 路径（旧存档兼容）
  { k = "ui", label = "界面", root = "UIParent", prefix = "[界面] " },
  { k = "world", label = "世界层", root = "WorldFrame", prefix = "[世界] " },
  { k = "mini", label = "小地图", root = "MinimapCluster", prefix = "[小地图] " },
  -- ★★1.74.29 扩容（用户：「还有那些扫描源也可以添加进去」）——都是独立可扫的顶层/聚簇帧；
  --   不存在的源会被自动跳过（buildNodes 里 anyRoot 判定），不会报错。
  { k = "tooltip", label = "提示框", root = "GameTooltip", prefix = "[提示框] " },
  { k = "chat", label = "聊天窗", root = "ChatFrame1", prefix = "[聊天] " },
  { k = "player", label = "玩家框", root = "PlayerFrame", prefix = "[玩家] " },
  { k = "action", label = "动作条", root = "MainMenuBar", prefix = "[动作条] " },
  { k = "bag", label = "背包", root = "ContainerFrame1", prefix = "[背包] " },
  { k = "uqpin", label = "任务图钉", root = "UnrealQuestWorldMapPin1", prefix = "[任务图钉] " },
}
local function uiScanSrcOn(k)
  local src = ui.scanSrc
  -- ★★未交互过 → 默认只扫「地图」（与旧行为一致）
  if type(src) ~= "table" or ui.scanSrcTouched ~= true then return k == "map" end
  -- ★★用户动过后：**完全按勾选**（取消地图就真的不扫地图）
  return src[k] == true
end

-- ★开图取证（/edb mapwatch）的状态：log/saved/count/frame/on
local MAPWATCH = { on = false, log = {}, saved = nil, count = 0, frame = nil }
-- ★「谁在隐藏 UIParent」取证（/edb uihide）的状态
local UIHIDE = { wrapped = false, orig = nil, count = 0, log = {}, frame = nil, on = false }

-- ★「只控制子件」实验（/edb uikids）的状态：原父级 + 原锚点 + 原绝对位置
local UIKIDS = { done = false, saved = {}, list = { "MinimapCluster", "MainMenuBar", "PlayerFrame", "ChatFrame1", "BuffFrame" } }

local function buildNodes()
  nodes = {}
  scanHitCap = false
  local seen = {}
  local anyRoot = false
  for _, src in ipairs(SCAN_SRC) do
    if uiScanSrcOn(src.k) then
      local root = _G[src.root]
      if (type(root) == "table" or type(root) == "userdata") then
        anyRoot = true
        if seen[root] then
          -- 已扫过（例如 UIParent 里含 Minimap）→ 跳过，避免重复条目
        else
          seen[root] = true
          local base = src.prefix and (src.prefix .. src.root) or src.root
          table.insert(nodes, { f = root, n = base .. (src.prefix and "/（本体）" or "(本体)"), src = src.k, d = 1 })
          scanTree(root, base, 1)
        end
      end
    end
  end
  if not anyRoot then
    -- 一个源都取不到（例如地图帧还没建）→ 用客户端正规路径把地图建出来再试一次
    local wm = _G["WorldMapFrame"]
    if (type(wm) == "table" or type(wm) == "userdata") and uiScanSrcOn("map") then
      if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, wm) end
      nodes = {}
      table.insert(nodes, { f = wm, n = "WorldMapFrame(本体)", src = "map", d = 1 })
      scanTree(wm, "WorldMapFrame", 1)
    elseif uiScanSrcOn("map") then
      return nil
    end
  end
  return nodes
end

local function nodeInfo(l, i)
  local f = l.f
  local w, h = "?", "?"
  if type(f.GetWidth) == "function" then local ok, v = pcall(f.GetWidth, f) if ok and tonumber(v) then w = string.format("%.0f", v) end end
  if type(f.GetHeight) == "function" then local ok, v = pcall(f.GetHeight, f) if ok and tonumber(v) then h = string.format("%.0f", v) end end
  local sc = "?"
  if type(f.GetScale) == "function" then local ok, v = pcall(f.GetScale, f) if ok and tonumber(v) then sc = string.format("%.2f", v) end end
  local lv = "?"
  if type(f.GetFrameLevel) == "function" then local ok, v = pcall(f.GetFrameLevel, f) if ok and tonumber(v) then lv = tostring(v) end end
  local st = "?"
  if type(f.GetFrameStrata) == "function" then local ok, v = pcall(f.GetFrameStrata, f) if ok then st = tostring(v) end end
  local par = "?"
  if type(f.GetParent) == "function" then
    local ok, p = pcall(f.GetParent, f)
    if ok and p and type(p.GetName) == "function" then
      local okn, pn = pcall(p.GetName, p)
      if okn and type(pn) == "string" then par = pn end
    end
  end
  -- ★1.74.34-13：/edb list 的「可缩/不可缩」列改成**可见性**（用户要求删掉不可伸缩、改看显隐）
  local sh = nil
  if type(f.IsShown) == "function" then
    local ok, v = pcall(f.IsShown, f)
    if ok then sh = v and true or false end
  end
  return {
    i = i, path = l.n, type = nodeType(f), w = w, h = h, shown = sh,
    scaleable = (type(f.SetScale) == "function") and true or false,
    scale = sc, level = lv, strata = st, parent = par,
  }
end

local function listLayers()
  if not buildNodes() then
    P("WorldMapFrame 不存在")
    return
  end
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  local dump, shown = {}, 0
  for i, nd in ipairs(nodes) do
    local rec = nodeInfo(nd, i)
    table.insert(dump, rec)
    -- 聊天框收敛：跳过 UnrealQuest 图钉（数量大），其余逐行打印
    if not string.find(rec.path, "UnrealQuest", 1, true) then
      shown = shown + 1
      P(string.format("#%d %s [%s] %sx%s %s scale=%s lv=%s %s 父=%s",
        rec.i, rec.path, rec.type, rec.w, rec.h,
        (rec.shown and "显" or "隐"), rec.scale, rec.level, rec.strata, rec.parent)) -- ★1.74.34-13 该列改成可见性
    end
  end
  EH_DEBUGBOX_CFG.layers = dump
  EH_DEBUGBOX_CFG.n = table.getn(dump)

  -- 顶层相关帧（不在树里）
  local top = {}
  for _, nm in ipairs(TOP) do
    -- ★只收「当前扫描源被勾选」的点名帧（否则只勾小地图也会冒出大地图那几件）
    local okSrc = (type(uiScanSrcOn) ~= "function") or uiScanSrcOn(topSrcOf(nm))
    local f = _G[nm]
    if okSrc and (type(f) == "table" or type(f) == "userdata") then -- ★不在当前扫描源里的点名帧就不列
      local rec = nodeInfo({ f = f, n = nm }, 0)
      table.insert(top, rec)
      P(string.format("[顶层] %s [%s] %sx%s %s scale=%s lv=%s %s 父=%s",
        nm, rec.type, rec.w, rec.h, (rec.shown and "显" or "隐"),
        rec.scale, rec.level, rec.strata, rec.parent))
    elseif okSrc then
      P("[顶层] " .. nm .. " = 不存在")
    end
  end
  EH_DEBUGBOX_CFG.top = top
  EH_DEBUGBOX_CFG.at = (type(GetTime) == "function") and tostring(GetTime()) or "?"
  P("—— 树内 " .. table.getn(dump) .. " 层（聊天框只列非图钉的 " .. shown .. " 条）+ 顶层相关帧 " .. table.getn(top) .. " 个 ——")
  P("全部已写入存档 EH_DEBUGBOX_CFG（layers/top）→ 请 /reload 落盘，AI 直接读文件")
  P("逐个试缩：/edb t 编号 0.7 · 全层同缩：/edb deep 0.7 · 还原：/edb off")
end

-- ===== /edb size：改尺寸路线（★未试过的关键一条） =====
-- 依据：鼠标点名实测 —— 只有 WorldMapButton 吃鼠标（1002×668, lv1），
--   之前证明「SetWidth 无效」的只有 WorldMapFrame 本体，**Button 自身的尺寸从没试过**。
--   若引擎按 Button 矩形绘制贴图 → 改尺寸 = 渲染与命中一起变 → 不漂移。
--   命令：/edb size 820 546（宽 高）· /edb sizef 820 546（连 WorldMapFrame 一起改）· /edb sizeoff（原尺寸还原）
local sizeSaved = nil

local SIZE_TARGETS = { "WorldMapButton", "WorldMapDetailFrame", "WorldMapPositioningGuide" }

local function sizeApply(w, h, withFrame)
  sizeSaved = sizeSaved or {}
  local n = 0
  local list = { SIZE_TARGETS[1], SIZE_TARGETS[2], SIZE_TARGETS[3] }
  if withFrame then table.insert(list, "WorldMapFrame") end
  for _, nm in ipairs(list) do
    local f = _G[nm]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetWidth) == "function" then
      if not sizeSaved[nm] then
        local okw, ow = pcall(f.GetWidth, f)
        local okh, oh = pcall(f.GetHeight, f)
        sizeSaved[nm] = { (okw and tonumber(ow)) or nil, (okh and tonumber(oh)) or nil }
      end
      pcall(f.SetWidth, f, w)
      pcall(f.SetHeight, f, h)
      local okw, nw = pcall(f.GetWidth, f)
      local okh, nh = pcall(f.GetHeight, f)
      n = n + 1
      P(string.format("%s: SetWidth/Height(%s,%s) → 读回 %sx%s", nm, tostring(w), tostring(h),
        tostring(okw and nw or "?"), tostring(okh and nh or "?")))
    else
      P(nm .. " 无 SetWidth")
    end
  end
  P("已改 " .. n .. " 个帧的尺寸。★看两件事：①地图贴图**是否跟着变小** ②悬停城镇**是否跟手**")
  P("（贴图不变 = 引擎不按 Button 矩形绘制 → 这条路也不通；贴图变小且悬停跟手 = 缩放正解）")
  local wm = _G["WorldMapFrame"]
  if type(ShowUIPanel) == "function" and wm then pcall(ShowUIPanel, wm) end
end

local function sizeOff()
  if type(sizeSaved) ~= "table" then P("没有记录到原尺寸（先跑 /edb size …）") return end
  for nm, wh in pairs(sizeSaved) do
    local f = _G[nm]
    if (type(f) == "table" or type(f) == "userdata") and wh and wh[1] and wh[2] then
      pcall(f.SetWidth, f, wh[1])
      pcall(f.SetHeight, f, wh[2])
      P(nm .. " 还原 " .. tostring(wh[1]) .. "x" .. tostring(wh[2]))
    end
  end
  sizeSaved = nil
end

-- ===== 三个坐标链帧的缩放 / 混合试验（用户要求：把这三个也一起设置） =====
-- /edb fit 0.7    = 按系数改**尺寸**（Button/Detail 1002×668 → 比例换算；Guide 1024×768 同比）
-- /edb scale 0.7  = 对这三个帧 SetScale（不含 WorldMapFrame 外框）
-- /edb scalef 0.7 = 三个帧 + WorldMapFrame 一起 SetScale
-- /edb mix 0.7    = 尺寸 + SetScale 同时上（看是否叠加后仍不漂）
local FIT_TARGETS = {
  { nm = "WorldMapButton", w = 1002, h = 668 },
  { nm = "WorldMapDetailFrame", w = 1002, h = 668 },
  { nm = "WorldMapPositioningGuide", w = 1024, h = 768 },
}

local function fitApply(factor)
  sizeSaved = sizeSaved or {}
  for _, t in ipairs(FIT_TARGETS) do
    local f = _G[t.nm]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetWidth) == "function" then
      if not sizeSaved[t.nm] then
        local okw, ow = pcall(f.GetWidth, f)
        local okh, oh = pcall(f.GetHeight, f)
        sizeSaved[t.nm] = { (okw and tonumber(ow)) or nil, (okh and tonumber(oh)) or nil }
      end
      local nw = math.floor(t.w * factor + 0.5)
      local nh = math.floor(t.h * factor + 0.5)
      pcall(f.SetWidth, f, nw)
      pcall(f.SetHeight, f, nh)
      local okw, rw = pcall(f.GetWidth, f)
      local okh, rh = pcall(f.GetHeight, f)
      P(string.format("%s 尺寸 → %sx%s（读回 %sx%s）", t.nm, nw, nh,
        tostring(okw and rw or "?"), tostring(okh and rh or "?")))
    end
  end
  P("系数 " .. tostring(factor) .. "：看 ①贴图是否同比变小 ②悬停是否跟手")
end

local function scaleCoords(factor, withFrame)
  local list = { "WorldMapButton", "WorldMapDetailFrame", "WorldMapPositioningGuide" }
  if withFrame then table.insert(list, "WorldMapFrame") end
  for _, nm in ipairs(list) do
    local f = _G[nm]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetScale) == "function" then
      pcall(f.SetScale, f, factor)
      local ok, v = pcall(f.GetScale, f)
      P(nm .. " SetScale(" .. tostring(factor) .. ") 读回=" .. tostring(ok and v or "?"))
    end
  end
  P("缩放已打在这三个坐标链帧上：看悬停是否跟手（这次它们一起变，理论上是同构缩放）")
  local wm = _G["WorldMapFrame"]
  if type(ShowUIPanel) == "function" and wm then pcall(ShowUIPanel, wm) end
end

-- ===== /edb scanui：通用 UI 层扫描可行性测量（只读，不改任何东西）=====
-- 调研目标（用户）：图层调试能否通用化 —— 地图关闭时也能扫外部 UI（动作条、玩家头像等）？
-- 要回答：① UIParent 树多大（节点/深度）② 扫一遍多久（GetTime 差值）③ 多少可写目标
--   （有名字→可持久化解析；有 SetScale/SetAlpha/SetWidth→可调；尺寸分布→默认过滤阈值）
local function uiScanMeasure()
  local roots = {}
  for _, nm in ipairs({ "UIParent", "WorldFrame", "Minimap" }) do
    local r = _G[nm]
    if type(r) == "table" or type(r) == "userdata" then table.insert(roots, { f = r, n = nm }) end
  end
  if table.getn(roots) == 0 then P("scanui：连 UIParent 都不存在，无法测量") return end
  local t0 = (type(GetTime) == "function") and GetTime() or 0
  local st = { nodes = 0, named = 0, unnamed = 0, withScale = 0, withAlpha = 0, withWidth = 0,
    big = 0, mouse = 0, maxDepth = 0, hidden = 0 }
  local bigList, seen = {}, 0
  local function walk(fr, path, depth)
    if seen > 6000 then return end -- 保险丝：极端情况不卡帧
    seen = seen + 1
    st.nodes = st.nodes + 1
    if depth > st.maxDepth then st.maxDepth = depth end
    local nm = uiFrameName(fr) -- ★「有无名字」判据的唯一来源（1.74.31 起不再就地写一份）
    if nm then st.named = st.named + 1 else st.unnamed = st.unnamed + 1 end
    if type(fr.SetScale) == "function" then st.withScale = st.withScale + 1 end
    if type(fr.SetAlpha) == "function" then st.withAlpha = st.withAlpha + 1 end
    if type(fr.SetWidth) == "function" then st.withWidth = st.withWidth + 1 end
    local shown = true
    if type(fr.IsShown) == "function" then local ok, v = pcall(fr.IsShown, fr) shown = (ok and v) and true or false end
    if not shown then st.hidden = st.hidden + 1 end
    local isMouse = false
    if type(fr.IsMouseEnabled) == "function" then local ok, v = pcall(fr.IsMouseEnabled, fr) isMouse = (ok and v) and true or false end
    if isMouse then st.mouse = st.mouse + 1 end
    local w, h = 0, 0
    if type(fr.GetWidth) == "function" then local ok, v = pcall(fr.GetWidth, fr) if ok and tonumber(v) then w = tonumber(v) end end
    if type(fr.GetHeight) == "function" then local ok, v = pcall(fr.GetHeight, fr) if ok and tonumber(v) then h = tonumber(v) end end
    if w >= 500 and h >= 500 then
      st.big = st.big + 1
      table.insert(bigList, { path = path .. "/" .. tostring(nm or "?"), w = w, h = h, mouse = isMouse })
    end
    if depth < 6 and type(fr.GetChildren) == "function" then
      local rc = { pcall(fr.GetChildren, fr) }
      if rc[1] then
        for i = 2, table.getn(rc) do
          local c = rc[i]
          if c then walk(c, path .. "/" .. tostring(nm or "?"), depth + 1) end
        end
      end
    end
  end
  for _, r in ipairs(roots) do walk(r.f, r.n, 1) end
  local dt = ((type(GetTime) == "function") and GetTime() or 0) - t0
  P(string.format("—— 通用 UI 扫描测量 —— 根 %d（UIParent/WorldFrame/Minimap）", table.getn(roots)))
  P(string.format("节点 %d（深度上限 6）· 命名 %d / 无名 %d · 隐藏 %d", st.nodes, st.named, st.unnamed, st.hidden))
  P(string.format("可 SetScale %d · 可 SetAlpha %d · 可 SetWidth %d · 吃鼠标 %d · ≥500×500 %d",
    st.withScale, st.withAlpha, st.withWidth, st.mouse, st.big))
  P(string.format("最大深度 %d · **一次扫描耗时 %.1f ms**", st.maxDepth, dt * 1000))
  table.sort(bigList, function(a, b) return (a.w * a.h) > (b.w * b.h) end)
  for i = 1, math.min(12, table.getn(bigList)) do
    local b = bigList[i]
    P(string.format("  大件 #%d %s %.0fx%.0f%s", i, b.path, b.w, b.h, b.mouse and " [吃鼠标]" or ""))
  end
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  EH_DEBUGBOX_CFG.uitree = { nodes = st.nodes, named = st.named, unnamed = st.unnamed, hidden = st.hidden,
    scal = st.withScale, alpha = st.withAlpha, width = st.withWidth, mouse = st.mouse, big = st.big,
    depth = st.maxDepth, ms = dt * 1000, bigList = bigList,
    at = (type(GetTime) == "function") and tostring(GetTime()) or "?" }
  P("结果已写入存档 EH_DEBUGBOX_CFG.uitree → /reload 落盘后 AI 直接读")
  -- （原写 flushStore()：本文件没有这个助手 —— 存档在上面的 EH_DEBUGBOX_CFG.uitree 里已写）
end

-- ===== /edb ui：图层调试面板（地图右侧入口）=====
-- 用户要求：右侧按钮 → 点击下拉/展开图层信息 → 支持过滤 → 支持多选 → 选中即设缩放等级，方便逐个调试。
-- 设计纪律（照本项目 UI 配方）：
--   · 纯色件一律 WHITE8X8 + SetVertexColor（本客户端 Texture:SetAlpha 是变暗不是透明）
--   · 无原生下拉 → 分类用按钮、无原生滑条 → 用 [-] 值 [+]
--   · EditBox 疑似不渲染 → 过滤框旁边加**回声行** FontString 保底
--   · 层级：面板 DIALOG/220 级（不压过全局件），挂 WorldMapFrame 下随图显隐
ui = { -- ★★不能再写 local：前面已有 local ui（前向声明），再写 local 会形成**第二个绑定**，闭包（uiScanSrcOn 等）绑到前一个 nil → attempt to index upvalue 'ui'
  root = nil, built = false, sel = {}, off = 0, filter = "", cat = 0,
  rows = 12, entries = nil, rowW = {}, value = 0.70, alphaValue = 1.00,
  xVal = 0, yVal = 0, -- ★用户要求：x,y 坐标设置（相对现有锚点的偏移增量）
  wVal = 700, hVal = 600, -- ★用户要求：宽/高设置，默认 700×600、步进 10
  cust = {}, colorOf = {}, -- ★需求 3/5：自定义记账（账号级存档）+ 每层颜色
  origDefaults = {}, -- ★「从未自定义时」观测到的原始尺寸（清理自定义时的兜底依据）
  -- ★应用外观时的**参数勾选**（只应用勾上的项）：用户要求「默认宽高不选中」→ 宽/高默认关闭，
  --   避免一键「应用外观」把尺寸也改掉（尺寸要单独勾选或走「应用尺寸」）
  par = { scale = true, alpha = true, w = false, h = false },
  tipDbg = false, tipLog = {}, -- ★tooltip 取证（/edb tipdbg 开；每步结果落存档）
  onlyShown = true, -- ★默认只看「当前打开（显示中）」的层（★1.74.34-14：改由 ui.vis 多选表达，本键只作老存档迁移）
  -- ★★★1.74.34-14 用户要求：「隐藏层调整可见性 → 下拉多选支持 → 不可见 / 可见；过滤操作要保持树结构；
  --   如果有子元素，父元素不受可见性影响，直到目标顶级」。⇒ 可见性筛选 = **多选**（可见 / 不可见 / 两者都选 = 不过滤）。
  --   nil = 还没交互过（按老键 onlyShown 迁移成 {shown=true}）；空表 {} = 两个都不选 = 不过滤（与 pick 的「空=全选」同款语义）。
  vis = nil,
  -- ★1.74.35-4：`mapFit`（本面板曾有的「地图叠加层自动适配」开关）**已删除** —— 该功能搬到工具箱→缩放大地图
  --   （`tools/SimpleMap.lua`，真值 `simpleMapCfg.mapFit`，nil = 默认开）。老存档里那个键由 uiLoadSettings 一次性清掉。
  bigOnly = false,  -- ★默认**关闭**（1.74.29 修：默认替用户过滤会让人以为「层变少了」；≥500 仍是可选筛选）
  -- ★★★1.75.13 用户定稿：**默认 1 = 只显示第一层**（先要 0，随后改口「默认1」）。
  --   （语义见 uiDepthApply：0 = 不做层深过滤（全部层级），1..4 = 只显示前 N 层；按钮循环 1→2→3→4→全部(0)。）
  depthMax = 1,
  hideUnnamed = true, -- ★★★1.74.31 用户要求：**默认隐藏没有名字的层**（开关文案/tooltip 走语言包；存档键 ui.hideUnnamed）
  scriptFilter = {}, -- ★事件/脚本过滤（多选）：只显示挂了所选脚本之一的层（空 = 不过滤）
  scanSrc = nil,     -- ★扫描源（多选）：nil = 只扫地图（与旧行为一致）；{ui=true} = 追加 UIParent 等
  -- ★★★1.74.31 第二步（用户要求：「图层列表能否有树的方式。现在量太大，有点卡」）：
  --   **折叠状态** —— 键 = 条目路径，值 = true 表示这棵子树收起来了；空表 = 全展开（老存档的默认）。
  --   落存档 `EH_DEBUGBOX_CFG.ui.treeCollapsed` ⇒ /reload 之后保持（用户要求「折叠状态跨 reload 保持」）。
  treeCollapsed = {},
}

-- ===== 顶栏分类（ui.cat）的**唯一来源** =====
-- ★★★1.74.31 用户要求：「删除 原生地图 / 任务图钉 / 顶层帧 这些不知道用途的功能」。
--   ⇒ **只删入口（按钮），判据与分类码全部保留**（下表 tab=false 的三项 = 能力保留、入口删除）：
--       · 这三类的过滤能力**仍然可用**：过滤框里输入 WorldMap / UnrealQuest / [顶层] 即可
--         （条目路径里本来就有这些字样；[顶层] 也是列表里那批点名帧的前缀）。
-- ★★★1.74.34-13 用户要求：「删除不可伸缩这个功能，调整成可见性」
--   ⇒ 分类码 3 的含义从「不可缩层」换成 **`隐藏层`**（只列当前被隐藏的层；用来找回自己藏掉的层）；
--     分类码本身不变（老存档 ui.cat=3 只是换个语义，不会再变成「点了没反应」）。
--   ★顺带保留一处既有修正：code ↔ 判据一对一钉在下面这张表里（旧代码曾把按钮序号当分类码，导致点 A 按 B 过滤）。
local UI_CAT_ALL = { code = 0, label = "全部", tab = true, test = function() return true end }
local UI_CAT_DEFS = {
  UI_CAT_ALL,
  { code = 1, label = "原生地图", tab = false, -- ← 入口已删（能力保留：过滤框输 WorldMap）
    test = function(e)
      return (string.find(e.path, "WorldMap", 1, true) ~= nil) and (string.find(e.path, "UnrealQuest", 1, true) == nil)
    end },
  { code = 2, label = "任务图钉", tab = false, -- ← 入口已删（能力保留：过滤框输 UnrealQuest）
    test = function(e) return (string.find(e.path, "UnrealQuest", 1, true) ~= nil) end },
  -- ★1.74.34-14：可见性改由**下拉多选**承担（可同时看「可见+不可见」，比二值分类强）
  --   ⇒ 「隐藏层」分类**入口撤掉**（tab=false，判据与分类码保留 = 老存档 ui.cat=3 仍能被归一处理）
  { code = 3, label = "隐藏层", tab = false,
    test = function(e) return (e.shown == false) end },
  { code = 4, label = "顶层帧", tab = false, -- ← 入口已删（能力保留：过滤框输 [顶层]）
    test = function(e) return (e.top == true) end },
}

-- 分类码 → 定义；**找不到（坏存档 / 已删分类 / nil）一律退回「全部」** ⇒ 列表构建绝不依赖已删分类
local function uiCatDef(code)
  for _, d in ipairs(UI_CAT_DEFS) do if d.code == code then return d end end
  return UI_CAT_ALL
end

-- 顶栏要建的分类按钮（顺序 = 从左到右；tab=false 的不建 → 已删分类**不能再被选中**）
local function uiCatTabs()
  local out = {}
  for _, d in ipairs(UI_CAT_DEFS) do if d.tab then table.insert(out, d) end end
  return out
end

-- 老存档的 ui.cat 可能停在已删分类上 → 载入时归一到「全部」（否则「已选中」与列表语义对不上）
local function uiCatNormalize(code)
  for _, d in ipairs(UI_CAT_DEFS) do if d.code == code and d.tab then return d.code end end
  return UI_CAT_ALL.code
end

-- ★顶栏（y = -64 那一排）的**排布游标**：按钮按「从左到右」的顺序调 uiTopTake(宽) 取自己的 x。
--   ★1.74.31 删掉三个分类按钮后，后面的按钮自动左移 —— 不再手写魔数（改一处不会漏另一处，也不会重叠）。
--   ★调用顺序**必须**与视觉顺序一致（分类 → 只显示有名 → 扫描源 → 事件过滤 → 框拖拽）。
--   ★必须声明在 ui 表之后（Lua 词法作用域：声明前引用 ui 会绑成**全局 nil** → 运行期 attempt to index）。
local function uiTopTake(w)
  local x = tonumber(ui.topX) or 8
  ui.topX = x + w + 4
  return x
end

-- ★uiRefresh 前向声明（必须早于任何会调用它的函数，例如拖拽结束回调 markDragEnd ——
--   声明在引用之后 = 绑全局 nil，本轮又被 ADDON DECL ORDER CHECK 抓到）
local uiRefresh

-- ===== tooltip 取证助手（用户报「tooltip 未显示」→ 分步留痕，不靠猜）=====
local function tipDbg(stage, ok, extra)
  if not ui.tipDbg then return end
  local line = string.format("%s ok=%s%s", tostring(stage), tostring(ok), extra and (" " .. tostring(extra)) or "")
  table.insert(ui.tipLog, line)
  while table.getn(ui.tipLog) > 12 do table.remove(ui.tipLog, 1) end
  if type(EVAL_LOGLINE) == "function" then EVAL_LOGLINE("[DBX] " .. line) end
end

-- 显示 tooltip（带回退与自证）：返回 true = 真的显示出来了
local function tipShowFor(owner, lines)
  local cands = { _G["GameTooltip"], _G["WorldMapTooltip"] }
  for idx = 1, 2 do
    local tip = cands[idx]
    if tip and type(tip.SetOwner) == "function" then
      local okS = pcall(tip.SetOwner, tip, owner, "ANCHOR_LEFT")
      tipDbg("SetOwner#" .. idx, okS)
      if okS then
        pcall(tip.ClearLines, tip)
        if type(tip.AddLine) == "function" then
          -- ★这里必须用 tip.AddLine（不是 add：add 只是**行 OnEnter 作用域内**的局部收集器；
          --   上一轮批量替换 pcall(tip.AddLine…) → add( 时误伤此处 → 运行期 call global 'add'）
          for _, ln in ipairs(lines) do
            pcall(tip.AddLine, tip, ln.t, ln.r or 0.9, ln.g or 0.9, ln.b or 0.9)
          end
        end
        local okShow = pcall(tip.Show, tip)
        local okQ, shown = pcall(tip.IsShown, tip)
        tipDbg("Show#" .. idx, okShow, "IsShown=" .. tostring(okQ and shown))
        if okShow and (not okQ or shown) then return true end
      end
    else
      tipDbg("cand#" .. idx, false, "不存在")
    end
  end
  return false
end

-- ★宿主帧（面板/高亮/自绘提示框都用它）：**不能挂 UIParent**（开全屏地图会隐藏 UIParent → 面板跟着消失）
--   WorldFrame 开图时仍显示（probe5 实测 IsShown=true），关图后也一直在。
local function uiHost()
  local wf = _G["WorldFrame"]
  if type(wf) == "table" or type(wf) == "userdata" then return wf end
  return _G["UIParent"]
end

local function uiSolid(t, r, g, b, a)
  if not t then return end
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") end
  if type(t.SetVertexColor) == "function" then pcall(t.SetVertexColor, t, r, g, b, a) end
end

local function uiFont(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  if type(fs.SetTextColor) == "function" then pcall(fs.SetTextColor, fs, r, g, b) end
  return fs
end

-- ===== 面板自身配置的存取（用户要求：层配置信息加入用户配置）=====
-- 存的是**面板的设置**：数值（缩放/透明/宽/高/X/Y）、参数勾选、筛选（仅显示中/≥500/分类/文字）、面板位置。
-- 落点：EH_DEBUGBOX_CFG.ui（账号级 SavedVariables，随插件存档持久化）。
function uiSaveSettings()
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  local pos = EH_DEBUGBOX_CFG.ui and EH_DEBUGBOX_CFG.ui or {}
  if ui.root and type(ui.root.GetLeft) == "function" then
    local host = uiHost()
    local okl, l = pcall(ui.root.GetLeft, ui.root)
    local okt, t = pcall(ui.root.GetTop, ui.root)
    local oks, es = pcall(ui.root.GetEffectiveScale, ui.root)
    local okhl, hl = pcall(host.GetLeft, host)
    local okht, ht = pcall(host.GetTop, host)
    if okl and okt and oks and okhl and okht and tonumber(es) and es ~= 0 then
      pos.px = (l / es) - (hl / es)
      pos.py = (t / es) - (ht / es)
    end
  end
  EH_DEBUGBOX_CFG.ui = {
    value = ui.value, alphaValue = ui.alphaValue,
    wVal = ui.wVal, hVal = ui.hVal, xVal = ui.xVal, yVal = ui.yVal,
    par = ui.par,
    onlyShown = ui.onlyShown, bigOnly = ui.bigOnly, hideUnnamed = ui.hideUnnamed, depthMax = ui.depthMax,
    vis = ui.vis, -- ★1.74.34-14 可见性多选（{shown=true}/{hidden=true}/两者/空表）
    cat = ui.cat, filter = ui.filter, scriptFilter = ui.scriptFilter, scanSrc = ui.scanSrc,
    -- ★★★1.74.31 第二步：树的折叠状态（用户要求「折叠状态跨 reload 保持」）
    treeCollapsed = ui.treeCollapsed,
    px = pos.px, py = pos.py,
  }
  return EH_DEBUGBOX_CFG.ui
end

function uiLoadSettings()
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  local c = EH_DEBUGBOX_CFG.ui
  if type(c) ~= "table" then return false end
  local function num(v, d) return (type(v) == "number") and v or d end
  ui.value = num(c.value, ui.value)
  ui.alphaValue = num(c.alphaValue, ui.alphaValue)
  ui.wVal = num(c.wVal, ui.wVal)
  ui.hVal = num(c.hVal, ui.hVal)
  ui.xVal = num(c.xVal, ui.xVal)
  ui.yVal = num(c.yVal, ui.yVal)
  if type(c.par) == "table" then
    for k, v in pairs(c.par) do if ui.par[k] ~= nil then ui.par[k] = v and true or false end end
  end
  if type(c.onlyShown) == "boolean" then ui.onlyShown = c.onlyShown end
  -- ★1.74.34-14 可见性多选：新键优先；老存档只有 onlyShown ⇒ 迁移成 {shown=true} / 空表（不过滤）。
  --   ★只收布尔真值键（坏存档/别的插件写进来的垃圾不许变成筛选条件）
  if type(c.vis) == "table" then
    local v = {}
    for k, val in pairs(c.vis) do if val and (k == "shown" or k == "hidden") then v[k] = true end end
    ui.vis = v
  elseif type(c.onlyShown) == "boolean" then
    ui.vis = c.onlyShown and { shown = true } or {}
  end
  if type(c.bigOnly) == "boolean" then ui.bigOnly = c.bigOnly end
  -- ★★★1.74.31 无名层过滤（默认**开** = 隐藏无名层）：老存档没有这个键 → 保持默认「开」，不写回存档
  if type(c.hideUnnamed) == "boolean" then ui.hideUnnamed = c.hideUnnamed end
  -- ★1.74.35-4：地图叠加层自动适配**已搬走**（→ 工具箱·缩放大地图）⇒ 老存档里那套键**一次性清掉**
  --   （不留没人读的配置；`maptileOrig`/`maptile*` 那几份是**探针存档**，留给 AI 事后读，不清）
  EH_DEBUGBOX_CFG.mapFit = nil
  EH_DEBUGBOX_CFG.mapFitGate = nil
  EH_DEBUGBOX_CFG.mapFitLast = nil
  EH_DEBUGBOX_CFG.mapFitAt = nil
  if tonumber(c.depthMax) then ui.depthMax = math.max(0, math.min(9, tonumber(c.depthMax))) end
  -- ★★★1.75.13 层深默认值 = **1**（用户先要 0、随后改口「默认1」）——老存档里已经存过 0/2/3/4 的
  --   必须**一次性**归 1，否则「改了默认值」在用户机器上根本看不出来（默认值只在**没有**存档键时生效）。
  --   ★标记键用**值版本号**（放 EH_DEBUGBOX_CFG 顶层，不是 .ui 里）：存档函数（uiSaveSettings）是
  --     **整表重建** .ui 的 ⇒ 写在 .ui 里的标记会被下一次存盘丢掉，迁移就会每开一次面板重跑一遍、
  --     把用户自己的选择反复抹掉。版本号便于以后再改默认值时再往前走一格。
  --   ★只做一次：之后用户点「层深」按钮选的档位**不再被覆盖**；改配置**如实播报**（不静默）。
  EH_DEBUGBOX_CFG.depthDefaultZero = nil -- 上一版的标记键：一次性清掉（不留没人读的配置）
  if (tonumber(EH_DEBUGBOX_CFG.depthDefaultVer) or 0) < 2 then
    local was = tonumber(c.depthMax)
    ui.depthMax = 1
    EH_DEBUGBOX_CFG.ui.depthMax = 1
    EH_DEBUGBOX_CFG.depthDefaultVer = 2
    if was ~= nil and was ~= 1 then
      P("层深默认值 = 1（只显示第一层）；原存档值 " .. tostring(was) .. " 已一次性重置（再点「层深」按钮可自行调回）")
    end
  end
  -- ★分类：已删分类（1/2/4）或坏值一律归一到「全部」（0）—— 已删分类不能再被选中
  if type(c.cat) == "number" then ui.cat = uiCatNormalize(c.cat) end
  if type(c.filter) == "string" then ui.filter = c.filter end
  if type(c.scriptFilter) == "table" then ui.scriptFilter = c.scriptFilter end
  if type(c.scanSrc) == "table" then ui.scanSrc = c.scanSrc end
  -- ★★★1.74.31 第二步：树折叠状态（老存档没有这个键 → 保持空表 = 全展开）；
  --   ★只收「值为真 + 键是字符串」的项（坏存档/别的插件写进来的垃圾不许变成折叠标记）
  if type(c.treeCollapsed) == "table" then
    local tc = {}
    for k, v in pairs(c.treeCollapsed) do if v and type(k) == "string" then tc[k] = true end end
    ui.treeCollapsed = tc
  end
  ui.savedPx, ui.savedPy = num(c.px, nil), num(c.py, nil)
  return true
end

local function uiBtn(parent, w, h, txt)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  uiSolid(bg, 0.22, 0.17, 0.07, 1)
  b.bg = bg -- ★暴露底色纹理：事件过滤按钮要靠它显示选中态
  local fs = uiFont(b, 11, 1, 0.95, 0.7)
  pcall(fs.SetPoint, fs, "CENTER", b, "CENTER", 0, 0)
  pcall(fs.SetText, fs, txt)
  b.label = fs
  return b
end

-- ===== 自绘 tooltip 框（1.74.29：GameTooltip/WorldMapTooltip 在本面板宿主下均不出渲染 → 自绘）=====
--   只用已验证能渲染的东西：WHITE8X8 纯色 + FontString（中文字体链）+ 1px 边框。
--   位置：贴**行左侧**（面板靠右停靠，往左展开不会出屏）；鼠标穿透（EnableMouse(false)）。
local uiTip = { box = nil, text = nil }

-- ★★★1.74.34-17 用户要求「美化 tooltip」「信息适当归类，同类的放一起」：
--   折行按**显示宽度**（汉字 2 列 / ASCII 1 列）且**优先在词边界断**（不再把 OnLeave 切成 OnLeav / e,）；
--   排版件三枚：`uiPad` 标签列对齐 · `uiListBrief` 长列表折叠（如实报剩余项数）· 折行器 `uiWrap`。
local function uiTextW(s)
  s = tostring(s or "")
  local w = 0
  for i = 1, string.len(s) do
    local b = string.byte(s, i)
    if not b then break end
    if b < 128 then w = w + 1
    elseif b >= 192 then w = w + 2 end -- 多字节字符首字节算 2 列（续字节不计）
  end
  return w
end

-- 标签列对齐：把 label 右补空格到 cols **显示列**（汉字两列 ⇒ 补出来才是真对齐）
local function uiPad(label, cols)
  local s = tostring(label or "")
  local w = uiTextW(s)
  if w >= cols then return s end
  return s .. string.rep(" ", cols - w)
end

-- 长列表折叠（如实标出还剩多少项，绝不假装列全）
local function uiListBrief(t, maxN)
  local n = table.getn(t or {})
  if n == 0 then return "（无）" end
  if n <= maxN then return table.concat(t, ", ") end
  local head = {}
  for i = 1, maxN do head[i] = t[i] end
  return table.concat(head, ", ") .. "  …另 " .. tostring(n - maxN) .. " 项"
end

-- 按显示宽度折行：ASCII 连续串当一个 token（不切词），只有超宽 token 才硬切
local function uiWrap(text, cols)
  text = tostring(text or "")
  local maxW = tonumber(cols) or 60
  local lines, cur, curW = {}, "", 0
  local function flush()
    if cur ~= "" then table.insert(lines, cur) end
    cur, curW = "", 0
  end
  local function put(tok)
    local w = uiTextW(tok)
    while w > maxW do -- 单个 token 超宽：硬切（极少见）
      local cut = maxW - curW
      if cut <= 0 then flush() cut = maxW end
      local taken, tw, i = "", 0, 1
      while i <= string.len(tok) do
        local b = string.byte(tok, i)
        local len = 1
        if b and b >= 240 then len = 4 elseif b and b >= 224 then len = 3 elseif b and b >= 192 then len = 2 end
        local pw = (len > 1) and 2 or 1
        if tw + pw > cut then break end
        taken = taken .. string.sub(tok, i, i + len - 1)
        tw = tw + pw
        i = i + len
      end
      if taken == "" then break end
      cur, curW = cur .. taken, curW + tw
      tok = string.sub(tok, i)
      w = uiTextW(tok)
      flush()
    end
    if curW + w > maxW and cur ~= "" then flush() end
    cur, curW = cur .. tok, curW + w
  end
  local i, n = 1, string.len(text)
  while i <= n do
    local b = string.byte(text, i)
    if not b then break end
    if b < 128 then
      local j = i
      while j <= n do
        local bj = string.byte(text, j)
        if not bj or bj >= 128 or bj == 32 then break end
        j = j + 1
      end
      if j == i then
        i = i + 1
        if curW + 1 > maxW then flush() else cur, curW = cur .. " ", curW + 1 end
      else
        put(string.sub(text, i, j - 1))
        i = j
      end
    elseif b >= 192 then
      local len = 2
      if b >= 240 then len = 4 elseif b >= 224 then len = 3 end
      put(string.sub(text, i, i + len - 1))
      i = i + len
    else
      i = i + 1
    end
  end
  flush()
  if table.getn(lines) == 0 then table.insert(lines, "") end
  return lines
end

local function uiTipEnsure()
  if uiTip.box then return uiTip.box end
  local host = uiHost()
  local box = CreateFrame("Frame", "EH_DB_TIPBOX", host)
  pcall(box.SetFrameStrata, box, "FULLSCREEN_DIALOG")
  pcall(box.SetFrameLevel, box, 700)
  if type(box.EnableMouse) == "function" then pcall(box.EnableMouse, box, false) end
  local bg = box:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
  uiSolid(bg, 0.02, 0.02, 0.02, 0.94)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = box:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", box, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", box, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, sd in ipairs({ "LEFT", "RIGHT" }) do
    local t = box:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. sd, box, "TOP" .. sd, 0, 0)
    t:SetPoint("BOTTOM" .. sd, box, "BOTTOM" .. sd, 0, 0)
    t:SetWidth(1)
  end
  local fs = box:CreateFontString(nil, "OVERLAY")
  local fontOk = false
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    if not fontOk then
      local okf = pcall(fs.SetFont, fs, fp, 11, "OUTLINE")
      if okf then fontOk = true end
    end
  end
  if not fontOk and type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  pcall(fs.SetPoint, fs, "TOPLEFT", box, "TOPLEFT", 6, -5)
  pcall(fs.SetJustifyH, fs, "LEFT")
  pcall(fs.SetWidth, fs, 470)
  box:Hide()
  uiTip.box, uiTip.text = box, fs
  return box
end

function uiTipShow(anchorFrame, lines)
  local box = uiTipEnsure()
  if not box then return false end
  -- ★1.74.34-17 排版：每行支持 head（分组头：前面自动加一条分隔线）/ sep（细分隔线）/ gap（空行）
  local TIP_COLS = 62      -- 文本显示列宽（汉字按 2 列算）
  local TIP_LINE = 13      -- 行高
  local TIP_PAD = 6        -- 内边距
  local out = {}
  local function push(t, r, g, b)
    table.insert(out, { t = t, r = r or 0.85, g = g or 0.85, b = b or 0.85 })
  end
  for _, ln in ipairs(lines) do
    local r, g, b = ln.r, ln.g, ln.b
    if ln.gap then push(" ", 0.2, 0.2, 0.2) end
    if ln.head then
      -- 分组头：一条细分隔线 + 标题（金），同类信息聚在一起、段间有视觉边界
      push(string.rep("-", 34), 0.45, 0.38, 0.16)
      push("[" .. tostring(ln.t) .. "]", 0.95, 0.82, 0.35)
    elseif ln.sep then
      push(string.rep("-", 34), 0.45, 0.38, 0.16)
    else
      for _, w in ipairs(uiWrap(ln.t, TIP_COLS)) do push(w, r, g, b) end
    end
  end
  -- 高度：按实际行数算；超出屏幕可用高度 ⇒ **如实截断并写明还剩几行**（绝不静默溢出）
  local sw = (type(GetScreenWidth) == "function") and GetScreenWidth() or 1024
  local sh = (type(GetScreenHeight) == "function") and GetScreenHeight() or 768
  local maxLines = math.max(6, math.floor((sh * 0.78) / TIP_LINE))
  local shown = table.getn(out)
  local truncated = 0
  if shown > maxLines then
    truncated = shown - maxLines + 1
    while table.getn(out) > maxLines - 1 do table.remove(out) end
    push("…（还有 " .. tostring(truncated) .. " 行未显示 · 鼠标悬停短一点的行或用 /edb list 看全量）", 0.9, 0.6, 0.3)
  end
  pcall(uiTip.text.SetWidth, uiTip.text, TIP_COLS * 6 + 12)
  local h = TIP_PAD * 2 + table.getn(out) * TIP_LINE
  pcall(box.SetHeight, box, h)
  pcall(box.SetWidth, box, TIP_COLS * 6 + 12 + TIP_PAD * 2)
  -- 颜色：一次 SetText 只能一个色 ⇒ 用**逐行着色**（多条 FontString 太贵；这里用前缀色码）
  --   ★本项目铁律：色码必须 8 位；同一行只允许一段（客户端会吞多段色码）
  local colored = {}
  for _, l in ipairs(out) do
    table.insert(colored, string.format("|cff%02x%02x%02x%s|r",
      math.floor((l.r or 0.85) * 255), math.floor((l.g or 0.85) * 255), math.floor((l.b or 0.85) * 255), l.t))
  end
  pcall(uiTip.text.SetText, uiTip.text, table.concat(colored, "\n"))
  -- 贴行左侧显示（面板靠右停靠 → 往左展开不出屏）；贴边时**夹回屏幕内**
  pcall(box.ClearAllPoints, box)
  local ok = pcall(box.SetPoint, box, "TOPRIGHT", anchorFrame, "TOPLEFT", -6, 2)
  if not ok then pcall(box.SetPoint, box, "CENTER", uiHost(), "CENTER", 0, 0) end
  pcall(box.Show, box)
  local okl, left = pcall(box.GetLeft, box)
  if okl and tonumber(left) and tonumber(left) < 2 then
    pcall(box.ClearAllPoints, box)
    pcall(box.SetPoint, box, "TOPLEFT", uiHost(), "TOPLEFT", 2, -2)
  end
  local okq, shownQ = pcall(box.IsShown, box)
  return (okq and shownQ) and true or false
end

function uiTipHide()
  if uiTip.box then pcall(uiTip.box.Hide, uiTip.box) end
end

-- ===== 行 tooltip 扩展信息（用户要求）：绑定事件 / 鼠标焦点 / 点击等脚本挂载情况 =====
-- ★本客户端注意：IsEventRegistered 返回 **1 而不是 true**（1.74.4 实测过），判据要两者都认。
-- ★没有「枚举已注册事件」的 API → 只能按**已知名单**逐个 IsEventRegistered 探测，并如实标注是探测结果。
local PROBE_EVENTS = {
  "OnShow", -- 占位（真实事件名在下面）
}
local KNOWN_EVENTS = {
  "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN", "VARIABLES_LOADED", "ADDON_LOADED",
  "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "UNIT_HEALTH", "UNIT_MANA", "UNIT_AURA", "UNIT_PET", "UNIT_FACTION",
  "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE",
  "BAG_UPDATE", "MERCHANT_SHOW", "MERCHANT_HIDE", "QUEST_LOG_UPDATE", "QUEST_DETAIL",
  "CHAT_MSG_SAY", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER",
  "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "MINIMAP_PING", "COMBAT_LOG_EVENT_UNFILTERED",
  -- ★1.74.29 扩展：从本机各插件（UnrealQuest/EvalHelp/两个子插件）的真实注册点抽出的补充名单
  "QUEST_REMOVED", "QUEST_ADDED", "QUEST_OBJECTIVES_CHANGED", "QUEST_LOG_CHANGED", "QUEST_COMPLETED", "PLAYER_LOGIN", "MERCHANT_SHOW", "MERCHANT_HIDE", "READY_CHECK", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_LOG_UPDATE", "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "WHO_LIST_UPDATE", "CHAT_MSG_GUILD", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_SAY",
}
-- ★★结构性边界（必须知道）：本客户端**没有「枚举已注册事件」的 API** —— 官方索引 1370 条里一个事件名都没有，
--   IsEventRegistered 也不在索引内（实测可用，且返回 1 而不是 true）→ 只能按**上面这份名单**逐个探测，
--   **名单外的事件看不见**。要提高覆盖率，往这份 KNOWN_EVENTS 里加名字即可（唯一来源）。
local PROBE_SCRIPTS = {
  "OnEvent", "OnUpdate", "OnShow", "OnHide",
  "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnClick", "OnMouseWheel",
  "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnKeyDown", "OnKeyUp", "OnChar",
  "OnSizeChanged", "OnValueChanged", "OnAttributeChanged", "OnEnterPressed", "OnEscapePressed",
}

local function uiScriptReport(fr)
  local has, hasnt = {}, {}
  for _, sc in ipairs(PROBE_SCRIPTS) do
    local fn = nil
    if type(fr.GetScript) == "function" then
      local ok, v = pcall(fr.GetScript, fr, sc)
      if ok then fn = v end
    end
    if type(fn) == "function" then table.insert(has, sc) else table.insert(hasnt, sc) end
  end
  local ev = {}
  for _, en in ipairs(KNOWN_EVENTS) do
    if type(fr.IsEventRegistered) == "function" then
      local ok, r = pcall(fr.IsEventRegistered, fr, en)
      if ok and (r == true or r == 1) then table.insert(ev, en) end
    end
  end
  local me, mw = "?", "?"
  if type(fr.IsMouseEnabled) == "function" then
    local ok, v = pcall(fr.IsMouseEnabled, fr)
    if ok then me = v and "是" or "否" end
  end
  if type(fr.isMouseWheelEnabled) == "function" then
    local ok, v = pcall(fr.isMouseWheelEnabled, fr)
    if ok then mw = v and "是" or "否" end
  elseif type(fr.IsMouseWheelEnabled) == "function" then
    local ok, v = pcall(fr.IsMouseWheelEnabled, fr)
    if ok then mw = v and "是" or "否" end
  end
  -- ★返回**表**而不是多返回值：多返回值位数一错就是 concat(nil) 这种运行期炸（本轮实踩）
  return { has = has, hasnt = hasnt, ev = ev, mouse = me, wheel = mw }
end

-- （已删：重复的「层高亮框」第一段——与后面那份逐字相同，且所有调用点都在后面那份之后，
--   属纯死代码；保留单一定义免得以后改一处只生效一半）

local function uiSolid(t, r, g, b, a)
  if not t then return end
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") end
  if type(t.SetVertexColor) == "function" then pcall(t.SetVertexColor, t, r, g, b, a) end
end

local function uiFont(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  if type(fs.SetTextColor) == "function" then pcall(fs.SetTextColor, fs, r, g, b) end
  return fs
end

local function uiBtn(parent, w, h, txt)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  uiSolid(bg, 0.22, 0.17, 0.07, 1)
  local fs = uiFont(b, 11, 1, 0.95, 0.7)
  pcall(fs.SetPoint, fs, "CENTER", b, "CENTER", 0, 0)
  pcall(fs.SetText, fs, txt)
  b.label = fs
  return b
end

-- ★★★1.74.34 真机红字实证（用户两次截图，第二次在 `type(row)=="table"` 守卫**之后**）：
--   本客户端 `type(帧)` 会报 **"table"**，但 `rawget(帧, ...)` 的 C 侧仍按 userdata 拒绝
--   （「bad argument #1 to 'rawget' (table expected, got userdata)」）⇒ **type() 不能当分路判据**，
--   直接让 rawget 自己说话：pcall 试 rawget，失败再退到字段读取（本客户端允许帧挂自定义字段）。
--   （测试桩的帧是真 table ⇒ rawget 成功、绕开 mock；真机帧 ⇒ rawget 抛错、走字段读。）
--   读「这一行挂的条目」唯一入口（行的 OnClick / 多选框 / 折叠开关三处共用）。
local function uiRowEntry(row)
  local okR, e = pcall(rawget, row, "entry")
  if not okR then
    local okF, v = pcall(function() return row.entry end)
    if okF then e = v end
  end
  if type(e) ~= "table" then return nil end
  return e
end

-- ===== 行 tooltip 扩展信息（用户要求）：绑定事件 / 鼠标焦点 / 点击等脚本挂载情况 =====
-- ★本客户端注意：IsEventRegistered 返回 **1 而不是 true**（1.74.4 实测过），判据要两者都认。
-- ★没有「枚举已注册事件」的 API → 只能按**已知名单**逐个 IsEventRegistered 探测，并如实标注是探测结果。
local PROBE_EVENTS = {
  "OnShow", -- 占位（真实事件名在下面）
}
local KNOWN_EVENTS = {
  "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN", "VARIABLES_LOADED", "ADDON_LOADED",
  "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "UNIT_HEALTH", "UNIT_MANA", "UNIT_AURA", "UNIT_PET", "UNIT_FACTION",
  "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE",
  "BAG_UPDATE", "MERCHANT_SHOW", "MERCHANT_HIDE", "QUEST_LOG_UPDATE", "QUEST_DETAIL",
  "CHAT_MSG_SAY", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_WHISPER",
  "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "MINIMAP_PING", "COMBAT_LOG_EVENT_UNFILTERED",
}
local PROBE_SCRIPTS = {
  "OnEvent", "OnUpdate", "OnShow", "OnHide",
  "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnClick", "OnMouseWheel",
  "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnKeyDown", "OnKeyUp", "OnChar",
  "OnSizeChanged", "OnValueChanged", "OnAttributeChanged", "OnEnterPressed", "OnEscapePressed",
}

local function uiScriptReport(fr)
  local has, hasnt = {}, {}
  for _, sc in ipairs(PROBE_SCRIPTS) do
    local fn = nil
    if type(fr.GetScript) == "function" then
      local ok, v = pcall(fr.GetScript, fr, sc)
      if ok then fn = v end
    end
    if type(fn) == "function" then table.insert(has, sc) else table.insert(hasnt, sc) end
  end
  local ev = {}
  for _, en in ipairs(KNOWN_EVENTS) do
    if type(fr.IsEventRegistered) == "function" then
      local ok, r = pcall(fr.IsEventRegistered, fr, en)
      if ok and (r == true or r == 1) then table.insert(ev, en) end
    end
  end
  local me, mw = "?", "?"
  if type(fr.IsMouseEnabled) == "function" then
    local ok, v = pcall(fr.IsMouseEnabled, fr)
    if ok then me = v and "是" or "否" end
  end
  if type(fr.isMouseWheelEnabled) == "function" then
    local ok, v = pcall(fr.isMouseWheelEnabled, fr)
    if ok then mw = v and "是" or "否" end
  elseif type(fr.IsMouseWheelEnabled) == "function" then
    local ok, v = pcall(fr.IsMouseWheelEnabled, fr)
    if ok then mw = v and "是" or "否" end
  end
  -- ★返回**表**而不是多返回值：多返回值位数一错就是 concat(nil) 这种运行期炸（本轮实踩）
  return { has = has, hasnt = hasnt, ev = ev, mouse = me, wheel = mw }
end

-- ===== 层高亮框（用户要求：列表行获取焦点时，给对应层描外边框高亮）=====
-- 选中 = 金色描边（可同时多个，池 16 个）；悬停 = 红色描边（单例，最后画、层级最高）
-- ★挂 WorldMapFrame + FULLSCREEN_DIALOG（低于面板 500，高于地图 FULLSCREEN），关图时随父一起隐藏
local hlPool, hlHover = {}, nil

local function hlMake(parent, level, r, g, b)
  local f = CreateFrame("Frame", nil, parent)
  -- ★★★1.74.29 用户要求：高亮框移到**最外层** → strata 抬到 TOOLTIP（本客户端最高层）。
  --   ★分工：「常显」靠**宿主 = uiHost()（WorldFrame，开图/关图都在）**；
  --           「最外层」靠 **strata = TOOLTIP + 高层级**。两件事分开做，才不会互相牵制。
  pcall(f.SetFrameStrata, f, "TOOLTIP")
  pcall(f.SetFrameLevel, f, level)
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, false) end
  local edges = {
    { "TOPLEFT", "TOPRIGHT", nil, 2 },   -- 上：跨满宽，高 2
    { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
    { "TOPLEFT", "BOTTOMLEFT", 2, nil }, -- 左：跨满高，宽 2
    { "TOPRIGHT", "BOTTOMRIGHT", 2, nil },
  }
  for _, e in ipairs(edges) do
    local t = f:CreateTexture(nil, "OVERLAY")
    uiSolid(t, r, g, b, 0.95)
    t:SetPoint(e[1], f, e[1], 0, 0)
    t:SetPoint(e[2], f, e[2], 0, 0)
    if e[3] then t:SetWidth(e[3]) end
    if e[4] then t:SetHeight(e[4]) end
  end
  f:Hide()
  return f
end

local function hlFrameGet(i)
  if hlPool[i] then return hlPool[i] end
  local parent = uiHost() or _G["UIParent"]
  hlPool[i] = hlMake(parent, 1000 + i, 1, 0.82, 0.15) -- ★选中金框（池内第 i 个）
  return hlPool[i]
end

-- 把描边框贴到某个层上（-2/+2 外扩，便于看清边界）
local function hlAttach(hf, target)
  if not hf or not target then return false end
  if type(hf.ClearAllPoints) ~= "function" or type(hf.SetPoint) ~= "function" then return false end
  -- ★★先直接锤目标（帧）；失败则退化到“目标的宿主帧”
  --   （图层/纹理类条目本身不能被帧锤定；至少把它所在的帧圈出来，总比什么都不画强）
  pcall(hf.ClearAllPoints, hf)
  local ok1 = pcall(hf.SetPoint, hf, "TOPLEFT", target, "TOPLEFT", -2, 2)
  local ok2 = pcall(hf.SetPoint, hf, "BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
  if not (ok1 and ok2) then
    local owner = nil
    if type(target.GetParent) == "function" then
      local okp, p = pcall(target.GetParent, target)
      if okp then owner = p end
    end
    if not owner then return false end
    pcall(hf.ClearAllPoints, hf)
    local ok3 = pcall(hf.SetPoint, hf, "TOPLEFT", owner, "TOPLEFT", -2, 2)
    local ok4 = pcall(hf.SetPoint, hf, "BOTTOMRIGHT", owner, "BOTTOMRIGHT", 2, -2)
    if not (ok3 and ok4) then return false end
  end
  pcall(hf.Show, hf)
  return true
end

-- 选中项全部描金边（每次刷新重贴；超过 16 个只描前 16 个，如实提示）
local function hlApplySelected()
  local n = 0
  for _, e in ipairs(ui.entries or {}) do
    if ui.sel[e.path] and e.f then
      if n >= 16 then break end
      local hf = hlFrameGet(n + 1)
      if hlAttach(hf, e.f) then n = n + 1 end
    end
  end
  for i = n + 1, table.getn(hlPool) do
    if hlPool[i] then pcall(hlPool[i].Hide, hlPool[i]) end
  end
  return n
end

local function hlShowHover(target)
  -- ★★★1.74.29 修（用户：「非大地图的 UI 层，鼠标焦点时外框画不出来」）：
  --   旧实现把高亮框挂在 WorldMapFrame 下 → **地图没开时父级隐藏、子框一并隐藏**，
  --   所以扫小地图/界面时看不到边框。改挂 uiHost()（WorldFrame：开图与关图都显示）。
  local parent = uiHost()
  if not hlHover then hlHover = hlMake(parent, 1100, 1, 0.25, 0.25) end -- ★悬停红框：比金框更高
  hlAttach(hlHover, target)
end

local function hlHideHover()
  if hlHover then pcall(hlHover.Hide, hlHover) end
end

-- ★面板/高亮/入口的宿主帧：**不能挂 UIParent**（开全屏地图会被隐藏 → 面板跟着消失）。
--   WorldFrame 在开图时仍显示（probe5 实测 IsShown=true），且关图后也一直在。

-- ===== 随机颜色库 + 自定义记账 + 地图标记池（用户要求 2/3/4） =====
-- ① 颜色库：每个「有自定义设置的层」随机抓一个颜色（同层恒定），文字与边框同色；
-- ② 记账 ui.cust[path]：首次自定义时**先存原始值**（scale/alpha/w/h/锚点）→ 可一键「清理自定义」精确还原；
-- ③ 地图标记：自定义层左上角显示「#序号 名称 自定义属性…」+ 该层四边彩色描边。
pcall(math.randomseed, (type(GetTime) == "function") and math.floor(GetTime() * 1000) or 12345)

local HL_COLORS = {
  { 1.00, 0.30, 0.30 }, { 0.30, 1.00, 0.30 }, { 0.40, 0.60, 1.00 }, { 1.00, 0.85, 0.20 },
  { 1.00, 0.45, 0.85 }, { 0.30, 1.00, 0.95 }, { 1.00, 0.60, 0.20 }, { 0.65, 0.45, 1.00 },
  { 0.45, 1.00, 0.55 }, { 1.00, 1.00, 0.55 }, { 0.55, 0.85, 1.00 }, { 1.00, 0.40, 0.55 },
}

-- ★用户（1）：**每个层一种颜色** —— 不再纯随机（会撞色）；
--   改成「占用最少的颜色优先，同占用数里再随机」→ 12 色内尽量互不相同，超过后均匀复用。
local function uiColorCounts()
  local cnt = {}
  for _, idx in pairs(ui.colorOf or {}) do
    cnt[idx] = (cnt[idx] or 0) + 1
  end
  return cnt
end

-- ★★★1.74.29 修（用户：「每个层自定义颜色需要从颜色库内随机抽取，不要所有层颜色都相同」）：
--   旧实现 = 「占用最少的颜色里**再 math.random**」——本客户端 math.random 可能退化成常数，
--   退化时会连续命中同一个（表现为「所有层一个色」）。新实现 = **最少占用 + 轮转指针**：
--   ① 先取占用数最小的那批颜色（保证不撞）；② 批次内按 ui.colorSeq **轮转**取，绝不依赖随机数；
--   ③ 批次只有一个时自然就是它。效果：12 色库内逐层铺开、各不相同，第 13 层起均匀复用。
local function uiColorFor(path)
  local idx = ui.colorOf[path]
  if idx then
    local c0 = HL_COLORS[idx] or HL_COLORS[1]
    return c0[1], c0[2], c0[3]
  end
  local cnt = uiColorCounts()
  local best, bestN = {}, nil
  for i = 1, table.getn(HL_COLORS) do
    local n = cnt[i] or 0
    if bestN == nil or n < bestN then
      bestN = n
      best = { i }
    elseif n == bestN then
      table.insert(best, i)
    end
  end
  ui.colorSeq = (ui.colorSeq or 0) + 1
  idx = best[(ui.colorSeq % table.getn(best)) + 1]
  ui.colorOf[path] = idx
  local c = HL_COLORS[idx] or HL_COLORS[1]
  return c[1], c[2], c[3]
end

-- ★★★1.74.30：框拖拽的目标清单（原 LD_DRAG_TARGETS）已随整块功能搬进 tools/DragFrames.lua；
--   本文件需要时走**读值口** `EVAL_DF_TARGETS()` 现取（唯一来源，绝不在这里再抄一份）。

local function uiCustSave()
  -- ★★★1.74.29（修「reload 后记录消失」）：**还没成功读过存档就不允许写**。
  --   本客户端 SavedVariables 的恢复时机晚于插件文件执行 → 文件期读到的是空表；
  --   若此时允许保存，就会把空表写回文件 → 自己把自己存的记录抹掉。
  if not ui.custLoaded then return end
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  EH_DEBUGBOX_CFG.cust = ui.cust
  EH_DEBUGBOX_CFG.colors = ui.colorOf
end

-- ★★★1.74.29（用户：「没读到为什么要把存档删除？过一段时间再读就行」）：
--   **未就位 → 不建表、不读、不写**。旧写法在文件执行期就建了空表，
--   抢在客户端恢复之前把真实记录覆盖成空。现在就位后才读（返回 n, ok）。
local function uiCustLoad()
  if type(EH_DEBUGBOX_CFG) ~= "table" then return 0, false end -- ★未就位：什么都不做
  ui.cust = (type(EH_DEBUGBOX_CFG.cust) == "table") and EH_DEBUGBOX_CFG.cust or {}
  ui.colorOf = (type(EH_DEBUGBOX_CFG.colors) == "table") and EH_DEBUGBOX_CFG.colors or {}
  ui.custLoaded = true
  local n = 0
  for _ in pairs(ui.cust) do n = n + 1 end
  return n, true
end

-- ★★★1.74.29 修（用户：「日志有记录，实际没有位移」）：
--   `opt` 里的相对帧（relativeTo）是 **userdata**，而 SavedVariables **不能序列化 userdata**
--   → 存盘后变成 `[2] = nil` → 应用时 `SetPoint(p, nil, relp, x, y)` 锚点失效 → 位置永远不生效。
--   现在：**只存名字**（字符串），应用时用 uiOptRel 解析回帧；旧记录的 nil 按 UIParent 兜底。
-- ★★★1.74.29（用户：「拖拽有时候会把游戏弄崩溃」）：
--   对**受保护帧**（头像/动作条等）调 SetMovable+StartMoving 是最危险的路；
--   而且战斗中对保护帧重锚本就被禁。现在：手动拖动（纯 SetPoint）+ 战斗中禁止拖动与重锚。
local function uiInCombat()
  if type(UnitAffectingCombat) ~= "function" then return false end
  local ok, v = pcall(UnitAffectingCombat, "player")
  return (ok and v) and true or false
end
local function uiOptRel(c)
  if type(c) ~= "table" or type(c.opt) ~= "table" then return UIParent end
  local r = c.opt[2]
  if type(r) == "string" then return _G[r] or UIParent end
  if type(r) == "table" or type(r) == "userdata" then return r end
  return UIParent -- 旧记录（存成了 nil）：按 UIParent 兜底，总比失效强
end

-- 取帧的相对帧**名字**（不存帧对象！）
local function uiRelName(rel)
  if not rel then return nil end
  local fn = uiField(rel, "GetName")
  if type(fn) == "function" then
    local ok, n = pcall(fn, rel)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return nil
end

-- 路径 → 帧（存档只存路径；顶层用 [顶层] 名；树内按名字逐段走；region/无名节点无法解析→如实跳过）
local function uiResolvePath(path)
  if type(path) ~= "string" then return nil end
  -- ★★★1.74.29 修（用户：「/reload 后层回到原位」）：
  --   旧写法 `string.sub(path,1,6) == "[全局]"` **永远不成立**：“[全局]”是 8 字节（[ + 3 + 3 + ]），
  --   而 sub(...,1,6) 只取 6 字节 → 于是 `[全局] ChatFrame1` 被当成树路径走 → 解析不到 → 偏移永远不生效。
  --   现在改成“先拿出括号里的名字、再比对”（多字节安全）。
  local pfx = string.match(path, "^%[([^%]]+)%]")
  if pfx == "顶层" or pfx == "全局" then
    local nm = string.match(path, "^%[[^%]]+%]%s*(.+)$")
    local f = nm and _G[nm]
    if type(f) == "table" or type(f) == "userdata" then return f end
    return nil
  end
  -- ★新前缀：[界面]/[世界]/[小地图] → 先按名字取根，再逐段走（与旧路径同一套逐段逻辑）
  local PREFIX_ROOT = { ["界面"] = "UIParent", ["世界"] = "WorldFrame", ["小地图"] = "MinimapCluster", ["提示框"] = "GameTooltip", ["聊天"] = "ChatFrame1", ["玩家"] = "PlayerFrame", ["动作条"] = "MainMenuBar", ["背包"] = "ContainerFrame1", ["任务图钉"] = "UnrealQuestWorldMapPin1" }
  -- （pfx 已在上方取好）
  local root, rest = nil, path
  if pfx and PREFIX_ROOT[pfx] then
    root = _G[PREFIX_ROOT[pfx]]
    rest = string.match(path, "^%[[^%]]+%]%s*(.+)$") or ""
    if not (type(root) == "table" or type(root) == "userdata") then return nil end
    -- 去掉「本体」那一段（根自身就是目标）
    rest = string.gsub(rest, "^" .. string.gsub(PREFIX_ROOT[pfx], "%%", "%%%%") .. "/?（本体）$", "")
    if rest == PREFIX_ROOT[pfx] or rest == "" then return root end
  end
  local f = root or _G["WorldMapFrame"]
  if not (type(f) == "table" or type(f) == "userdata") then return nil end
  local first = (root == nil)
  for seg in string.gmatch(rest, "([^/]+)") do
    if first then
      first = false -- 第一段就是根名（WorldMapFrame / UIParent …）
    elseif string.sub(seg, 1, 7) == "region:" or seg == "?" then
      return nil -- 图层/无名节点：无名字可寻 → 无法解析
    else
      local found = nil
      if type(f.GetChildren) == "function" then
        local rc = { pcall(f.GetChildren, f) }
        if rc[1] then
          for i = 2, table.getn(rc) do
            local c = rc[i]
            if c and type(c.GetName) == "function" then
              local ok, n = pcall(c.GetName, c)
              if ok and n == seg then found = c break end
            end
          end
        end
      end
      if not found then return nil end
      f = found
    end
  end
  return f
end

-- ★★★1.74.30 框拖拽的目标清单 = 主插件工具模块 `tools/DragFrames.lua` 的真值（EVAL_DF_TARGETS()）。
--   本子插件的「自定义重设」循环**必须跳过这 5 个目标**：它们的定位/属性现在存在
--   `EVAL_HELP_CONFIG.dragFrames` 里，由模块自己的 2 秒复查负责；这里若再按老记录写一次 = **两处抢锚点**
--   （用户报的「拖拽时位移/闪烁」正是这么来的）。★清单现取，不在这里抄第二份。
local function uiIsDragTarget(path)
  if type(path) ~= "string" then return false end
  if type(EVAL_DF_TARGETS) ~= "function" then return false end
  local list = EVAL_DF_TARGETS() or {}
  for i = 1, table.getn(list) do
    if path == "[全局] " .. tostring(list[i].name) then return true end
  end
  return false
end

-- ★★★1.74.30 面板里那几个「写层」按钮（应用属性 / 微调坐标 / 清理自定义 / 还原坐标）要用的闸门：
--   只要**当前选中项**里有框拖拽目标，这些按钮就整体不动手 —— 它们的定位/属性真值在主插件工具模块里，
--   面板再写一次就是**两处抢锚点**（模块的 2 秒复查反过来又会把它按回去，用户看到的是「改了不生效」）。
local function uiSelHasDragTarget()
  for _, e in ipairs(ui.entries or {}) do
    if ui.sel and ui.sel[e.path] and uiIsDragTarget(e.path) then return true end
  end
  return false
end

-- ★需求 5 的兜底：定时器把存档里的自定义设置**重设**到对应层（漂移/重载后自动恢复）
-- ★★1.74.29：**已按用户要求删掉「延迟缩放」那套**（就绪闸门 / 新出现延迟 / 启动延迟）。
--   现在回到「定时器一到就把存档参数写到能解析到的层上」：立即、直接。
--   ★如实告知：当初加延迟是因为「有些原始层还没添加就先缩放，导致某些层失效」——
--     若该现象重现，恢复办法是给这个循环再加「就绪 + 新出现延迟」两道闸门（见 git 历史）。
-- ===== ★★★1.74.34-9 贴图载入侦测 + 缩放闸门（用户实测定案：缩放**有效**，但必须**等贴图全部载入完成**）=====
--   用户的实测结论：先缩放、贴图后载入 ⇒ 后载入的贴图不按缩放走（缩放异常）；载完再缩放 = 正常。
--   ⇒ 只对他点名的 **WorldMapDetailFrame** 门控：写缩放前先看贴图载没载完（每张纹理 GetTexture() 非空），
--     没载完就进**有界等待队列**（0.3s × 10，载完自动写入；超时**不写入**并如实报——写入才是事故）。
local TILEWAIT_MAX, TILEWAIT_GAP = 10, 0.3
local uiScaleWait = { items = {}, frame = nil }

-- 贴图载入完成？true=载完可缩放 / false=没载完（含一张都没有）/ nil=不是它或判不出（不门控）
local function uiDetailTilesReady(fr)
  if not (type(fr) == "table" or type(fr) == "userdata") then return nil end
  if uiFrameName(fr) ~= "WorldMapDetailFrame" then return nil end -- ★只对他点名的这一帧门控
  if type(fr.GetRegions) ~= "function" then return nil end
  local ok, regs = pcall(function() return { fr:GetRegions() } end)
  if not ok or table.getn(regs) == 0 then return false end
  for _, r in ipairs(regs) do
    if r and type(r.GetObjectType) == "function" then
      local okT, t = pcall(r.GetObjectType, r)
      if okT and t == "Texture" then
        local okG, tex = pcall(r.GetTexture, r)
        if not (okG and type(tex) == "string" and tex ~= "") then return false end -- 有还没载入的贴图
      end
    end
  end
  return true
end

local function uiScaleWaitTick()
  local left = {}
  for _, it in ipairs(uiScaleWait.items) do
    it.tries = it.tries + 1
    if uiDetailTilesReady(it.f) == true then
      local itSS = uiField(it.f, "SetScale") -- ★1.74.34-26 安全读口
      if type(itSS) == "function" then pcall(itSS, it.f, it.v) end
      P("贴图已载入完成 → 缩放 " .. string.format("%.2f", it.v) .. " 已写入 WorldMapDetailFrame（第 " .. tostring(it.tries) .. " 次检查）")
    elseif it.tries >= TILEWAIT_MAX then
      P("|cffff8800贴图 " .. string.format("%.1f", TILEWAIT_MAX * TILEWAIT_GAP) .. " 秒仍未载完|r：本次缩放**未写入**（避免贴图缩放异常）；贴图出来后请再点一次「应用外观」")
    else
      table.insert(left, it)
    end
  end
  uiScaleWait.items = left
  if table.getn(left) == 0 and uiScaleWait.frame then
    pcall(uiScaleWait.frame.SetScript, uiScaleWait.frame, "OnUpdate", nil)
  end
end

-- 缩放**门控写入**（唯一入口）：载完/不门控 → 立即写；没载完 → 入队有界等待。返回 "now" / "wait"
local function uiScaleApplyGated(f, v)
  local ready = uiDetailTilesReady(f)
  if ready ~= false then
    pcall(f.SetScale, f, v)
    return "now"
  end
  if not uiScaleWait.frame then
    uiScaleWait.frame = CreateFrame("Frame", "EH_DB_TILEWAIT", uiHost())
  end
  table.insert(uiScaleWait.items, { f = f, v = v, tries = 0 })
  local acc = 0
  uiScaleWait.frame:SetScript("OnUpdate", function()
    acc = acc + (tonumber(arg1) or 0.05)
    if acc < TILEWAIT_GAP then return end
    acc = 0
    uiScaleWaitTick()
  end)
  P("WorldMapDetailFrame 贴图尚未载完 → 缩放已**排队**，载完自动写入（最多等 " .. string.format("%.1f", TILEWAIT_MAX * TILEWAIT_GAP) .. " 秒）")
  return "wait"
end

-- ===== ★★★1.74.35-4 地图探索叠加层「跟随地图缩放」自动适配 → **已搬到工具箱→缩放大地图** =====
--   用户 1.74.35-4 明确：「开图/es 变化后 0.1s 高频爆发期（持续 2 秒）＋之后降到 0.3 稳态巡检」是
--   **工具箱 → 大地图缩放**要默认启动的功能，**不是给图层调试工具内使用的**；「图层调试工具只是个调试工具，不需要」。
--   ⇒ 实现落在 `tools/SimpleMap.lua`（开关真值 `simpleMapCfg.mapFit`，**nil = 默认开**）；
--     命令 `/ehm mapfit [on|off|restore|diag]`。本子插件**不再自己跑自动适配**（连 ticker 一起删掉），
--     只保留手动/只读探针：`/edb maptile fit s|d|restore`（手动试）与 `/edb maptile`（只读清单）。
--   ★原自动适配那版代码的结论仍有效（照抄到 SimpleMap 时才没走弯路）：
--     探针 27 行定案「底瓦片互相锚 + 偏移全 0 ⇒ 对缩放免疫；9 张 WorldMapOverlayN + WorldMapHighlight
--     锚父帧 TOPLEFT + 偏移非零 ⇒ 缩放后错位」，用户实测「偏移与尺寸 ×es」有效。
local function uiCustReapply(quiet)
  local n, miss = 0, 0
  for path, c in pairs(ui.cust or {}) do
    -- ★★★1.74.30：框拖拽的 5 个目标**不在这里重设**（真值已搬到 tools/DragFrames.lua 的 EVAL_HELP_CONFIG.dragFrames）
    --   否则两处各写一次锚点 = 抢锚点（用户报的「位移/闪烁」正是这么来的）。
    local f = nil
    if not uiIsDragTarget(path) then f = uiResolvePath(path) end
    if f then
      local s = c.set or {}
      if s.scale and type(f.SetScale) == "function" then
        local ok, v = pcall(f.GetScale, f)
        if not (ok and tonumber(v) and math.abs(v - s.scale) < 0.001) then
          -- ★1.74.34-9：贴图载入闸门（载完才写；排队中的由等待队列写入并自行播报，不计入本次）
          if uiScaleApplyGated(f, s.scale) == "now" then n = n + 1 end
        end
      end
      if s.alpha and type(f.SetAlpha) == "function" then
        local ok, v = pcall(f.GetAlpha, f)
        if not (ok and tonumber(v) and math.abs(v - s.alpha) < 0.001) then pcall(f.SetAlpha, f, s.alpha) n = n + 1 end
      end
      if s.w and type(f.SetWidth) == "function" then
        local ok, v = pcall(f.GetWidth, f)
        if not (ok and tonumber(v) and math.abs(v - s.w) < 1) then pcall(f.SetWidth, f, s.w) n = n + 1 end
      end
      if s.h and type(f.SetHeight) == "function" then
        local ok, v = pcall(f.GetHeight, f)
        if not (ok and tonumber(v) and math.abs(v - s.h) < 1) then pcall(f.SetHeight, f, s.h) n = n + 1 end
      end
      if (s.dx or s.dy) and c.opt and type(f.SetPoint) == "function" then
        local o = c.opt
        local ok = pcall(f.ClearAllPoints, f)
        if ok then pcall(f.SetPoint, f, o[1], o[2], o[3], (tonumber(o[4]) or 0) + (s.dx or 0), (tonumber(o[5]) or 0) + (s.dy or 0)) end
      end
      -- ★1.74.34-12：显隐也按存档回写（hidden=true → Hide；=false → Show；nil = 没动过显隐）
      if s.hidden == true and type(f.Hide) == "function" then pcall(f.Hide, f) n = n + 1 end
      if s.hidden == false and type(f.Show) == "function" then pcall(f.Show, f) n = n + 1 end
    else
      miss = miss + 1
    end
  end
  if not quiet and (n > 0 or miss > 0) then
    P("自定义重设：已重设 " .. n .. " 项" .. (miss > 0 and ("；" .. miss .. " 条路径解析不到（图层/无名节点，如实跳过）") or ""))
  end
  return n, miss
end

-- 首次自定义：存原始值（还原的唯一依据）；顺带分配颜色
local function uiCustEnsure(e)
  local c = ui.cust[e.path]
  if c then return c end
  local f = e.f
  c = { set = {} }
  if type(f.GetScale) == "function" then local ok, v = pcall(f.GetScale, f) if ok then c.oscale = v end end
  if type(f.GetAlpha) == "function" then local ok, v = pcall(f.GetAlpha, f) if ok then c.oalpha = v end end
  if type(f.GetWidth) == "function" then local ok, v = pcall(f.GetWidth, f) if ok then c.ow = v end end
  if type(f.GetHeight) == "function" then local ok, v = pcall(f.GetHeight, f) if ok then c.oh = v end end
  if type(f.GetPoint) == "function" then
    local ok, p, rel, relp, x, y = pcall(f.GetPoint, f, 1)
    if ok and p then c.opt = { p, uiRelName(rel), relp, x, y } end
  end
  -- ★1.74.34-12：显隐的**原始值**（还原的依据，与 ow/oh 同款：第一次改之前读）
  if type(f.IsShown) == "function" then
    local ok, v = pcall(f.IsShown, f)
    if ok then c.oshown = v and true or false end
  end
  ui.cust[e.path] = c
  uiColorFor(e.path)
  return c
end

-- 自定义摘要文本（给地图标记用）
local function uiCustSummary(path)
  local c = ui.cust[path]
  if not c then return nil end
  local t = {}
  local s = c.set
  if s.scale then table.insert(t, string.format("缩放%.2f", s.scale)) end
  if s.alpha then table.insert(t, string.format("透明%.2f", s.alpha)) end
  if s.w or s.h then table.insert(t, string.format("尺寸%.0fx%.0f", s.w or 0, s.h or 0)) end
  if s.dx or s.dy then table.insert(t, string.format("坐标%+.0f,%+.0f", s.dx or 0, s.dy or 0)) end
  if s.hidden ~= nil then table.insert(t, s.hidden and "隐藏" or "显示") end -- ★1.74.34-12 显隐也进摘要
  if table.getn(t) == 0 then return "自定义" end
  return table.concat(t, " ")
end

-- 地图标记池（彩色描边 + 左上角信息文本）——挂 uiHost()，FULLSCREEN_DIALOG
local uiMarks = {}
local uiMarkSavePos -- ★前向声明（拖拽柄脚本要用；定义在下方 → 不前置声明就会绑成全局 nil）

-- ============ 地图标记拖拽：方案 A（屏幕位移+量回自证）+ 方案 B（全屏接盘兜底）============
-- ★★★1.74.34-5 用户拍板「A+B 全做」（漂移根因三条全中主仓 tools/DragFrames.lua 已定案的坑）：
--   ① 旧 OnUpdate **每帧回读 GetPoint 加增量** → 口径误差留在锚点里逐帧叠加（越拖越偏）；
--   ② 位移 `(cx)/es` **除缩放** → 缩放 ≠ 1 的层按比例算错；
--   ③ 结束只有信息条自己的 OnMouseUp 一道 → 松手事件一丢就「跟手不放」。
-- ★★★1.74.34-6 真机红字实证（用户截图：1636 attempt to call upvalue (a nil value)）：
--   本块**必须放在文件作用域**（uiMarkGet 之前）——上一版误插在 uiMarkGet 函数体内，
--   里面的 local 每次调用都是新槽位、且把顶层的赋值挡成了全局 ⇒ 处理器里的 upvalue 恒 nil
--   （正是本项目「跨段共享件一律放在所有使用方之前」那条铁律的又一次实踩）。
-- ★前向声明：赋值在 markDragEnd 之后（与本文件 `local uiRefresh` 同款模式）。
local uiMarkDragStop, uiMarkPlaceFrom
local markDragActive = nil -- 当前正在拖拽的标记对象（全屏接盘靠它找到该结束谁）
local dbxCatcher = nil
local function uiMarkCatcherEnsure()
  if dbxCatcher then return dbxCatcher end
  if type(CreateFrame) ~= "function" then return nil end
  local host = uiHost()
  local c = CreateFrame("Button", "EH_DB_MARKCATCHER", host)
  pcall(c.SetFrameStrata, c, "FULLSCREEN_DIALOG")
  pcall(c.SetFrameLevel, c, 800) -- 高于标记条，低于配置弹窗
  if type(c.SetAllPoints) == "function" and host then pcall(c.SetAllPoints, c, host) end
  if type(c.EnableMouse) == "function" then pcall(c.EnableMouse, c, true) end
  if type(c.RegisterForClicks) == "function" then pcall(c.RegisterForClicks, c, "LeftButtonUp", "RightButtonUp") end
  local function endFromCatcher()
    if markDragActive then uiMarkDragStop(markDragActive, "catcher") end
  end
  c:SetScript("OnMouseUp", endFromCatcher)
  c:SetScript("OnClick", endFromCatcher)
  c:Hide()
  dbxCatcher = c
  return c
end
local function uiMarkCatcherShow(on)
  local c = uiMarkCatcherEnsure()
  if not c then return false end
  if on then pcall(c.Show, c) else pcall(c.Hide, c) end
  return true
end

local function uiMarkGet(i)
  if uiMarks[i] then return uiMarks[i] end
  local host = uiHost()
  local bd = CreateFrame("Frame", nil, host)
  pcall(bd.SetFrameStrata, bd, "FULLSCREEN_DIALOG")
  pcall(bd.SetFrameLevel, bd, 530 + i)
  if type(bd.EnableMouse) == "function" then pcall(bd.EnableMouse, bd, false) end
  local edges = {}
  for k = 1, 4 do
    local t = bd:CreateTexture(nil, "OVERLAY")
    uiSolid(t, 1, 1, 1, 0.95)
    edges[k] = t
  end
  edges[1]:SetPoint("TOPLEFT", bd, "TOPLEFT", 0, 0) edges[1]:SetPoint("TOPRIGHT", bd, "TOPRIGHT", 0, 0) edges[1]:SetHeight(2)
  edges[2]:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", 0, 0) edges[2]:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", 0, 0) edges[2]:SetHeight(2)
  edges[3]:SetPoint("TOPLEFT", bd, "TOPLEFT", 0, 0) edges[3]:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", 0, 0) edges[3]:SetWidth(2)
  edges[4]:SetPoint("TOPRIGHT", bd, "TOPRIGHT", 0, 0) edges[4]:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", 0, 0) edges[4]:SetWidth(2)
  -- ★用户（2）：信息条 = 独立可拖动的小条（拖拽柄在左，文字在右）
  -- ★用户要求：**信息条本身**就能拖（拖它 = 拖整个图层），不再有单独的拖拽按钮。
  --   注意本客户端铁律：Frame 的 OnDragStart **不触发** → 信息条必须是 Button。
  local lbl = CreateFrame("Button", nil, host)
  pcall(lbl.SetFrameStrata, lbl, "FULLSCREEN_DIALOG")
  pcall(lbl.SetFrameLevel, lbl, 560 + i)
  if type(lbl.RegisterForClicks) == "function" then pcall(lbl.RegisterForClicks, lbl, "LeftButtonUp") end
  if type(lbl.RegisterForDrag) == "function" then pcall(lbl.RegisterForDrag, lbl, "LeftButton") end
  -- ★★写错过的坑：pcall(lbl.SetWidth(240)) 是**先调用**再 pcall（self=nil → sol: received nil for 'self'）
  --   正解是把方法与 self 都当参数传：pcall(lbl.SetWidth, lbl, 240)
  pcall(lbl.SetWidth, lbl, 240)
  pcall(lbl.SetHeight, lbl, 16)
  pcall(lbl.SetMovable, lbl, true)
  if type(lbl.EnableMouse) == "function" then pcall(lbl.EnableMouse, lbl, true) end
  local lbg = lbl:CreateTexture(nil, "BACKGROUND")
  lbg:SetPoint("TOPLEFT", lbl, "TOPLEFT", 0, 0)
  lbg:SetPoint("BOTTOMRIGHT", lbl, "BOTTOMRIGHT", 0, 0)
  uiSolid(lbg, 0.02, 0.02, 0.02, 0.7)
  local fs = lbl:CreateFontString(nil, "OVERLAY")
  local fontOk = false
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    if not fontOk then
      local okf = pcall(fs.SetFont, fs, fp, 12, "OUTLINE")
      if okf then fontOk = true end
    end
  end
  if not fontOk and type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  pcall(fs.SetPoint, fs, "LEFT", lbl, "LEFT", 5, 0) -- 没有拖拽柄了，文字贴左边
  pcall(fs.SetJustifyH, fs, "LEFT")
  local self = {} -- ★每条的标记对象（bd/edges/lbl/fs + path/layer），供刷新与拖拽回调引用
  -- ★用户要求：拖动**信息条本身**即拖动整个图层（Button 上 OnDragStart 才会触发；warm-up 两步）
  -- ★★同样改成手动拖动（不用 StartMoving：拖到受保护层时那条路最容易把客户端弄崩）
  -- ★★★1.74.34-5 方案 A+B：位移按屏幕算（不除缩放）+ 量回自证落锚（不再每帧回读 GetPoint 加增量）
  --   + 全屏接盘兜底（松手在游戏窗口任意位置都能结束）+ 指针静止/超时保险。
  lbl:SetScript("OnMouseDown", function()
    local f2 = self.layer
    if not f2 then return end
    if uiInCombat() then P("框拖拽：战斗中不可拖动（客户端保护）") return end
    if type(GetCursorPosition) ~= "function" then return end
    local okc, cx, cy = pcall(GetCursorPosition)
    if not (okc and tonumber(cx) and tonumber(cy)) then return end
    -- markDragBegin 现在**返回**拖前快照（实测屏幕位置 + 缩放 + 拖前锚点），供 placeFrom 每帧重建
    local from = self.path and markDragBegin(self.path, f2) or nil
    -- ★方案 B：换拖/补拖时先把上一个没收尾的结掉，再挂全屏接盘
    if markDragActive and markDragActive ~= self then uiMarkDragStop(markDragActive, "switch") end
    markDragActive = self
    uiMarkCatcherShow(true)
    self.dragging = { cx0 = cx, cy0 = cy, lastCx = cx, lastCy = cy, idle = 0, age = 0, from = from }
  end)
  lbl:SetScript("OnUpdate", function()
    local d = self.dragging
    if not d then return end
    local f2 = self.layer
    if not f2 then uiMarkDragStop(self, "lost") return end
    local okc, cx, cy = pcall(GetCursorPosition)
    if not (okc and tonumber(cx) and tonumber(cy)) then return end
    local dt = tonumber(arg1) or 0.016
    -- ★保险丝（松手事件丢失时的最后一道）：指针静止 ≥1.5s 或拖拽 ≥30s 强制结束
    if math.abs(cx - d.lastCx) < 0.5 and math.abs(cy - d.lastCy) < 0.5 then
      d.idle = d.idle + dt
      if d.idle >= 1.5 then uiMarkDragStop(self, "idle") return end
    else
      d.idle = 0
    end
    d.lastCx, d.lastCy = cx, cy
    d.age = d.age + dt
    if d.age >= 30 then uiMarkDragStop(self, "timeout") return end
    -- ★方案 A：光标**累计**位移（不除缩放）→ 拖前实测屏幕位置 + 位移 → placeFrom 量回自证落锚
    local totX, totY = cx - d.cx0, cy - d.cy0
    if (not d.appX) or math.abs(totX - d.appX) > 0.5 or math.abs(totY - d.appY) > 0.5 then
      if d.from and uiMarkPlaceFrom(f2, d.from, totX, totY) then
        d.appX, d.appY = totX, totY
      end
    end
  end)
  lbl:SetScript("OnMouseUp", function()
    uiMarkDragStop(self, "mouseup")
  end)
  -- 悬停给点视觉反馈（提示「这条能拖」）
  lbl:SetScript("OnEnter", function() pcall(lbg.SetVertexColor, lbg, 0.18, 0.16, 0.06, 0.85) end)
  lbl:SetScript("OnLeave", function() pcall(lbg.SetVertexColor, lbg, 0.02, 0.02, 0.02, 0.7) end)
  bd:Hide()
  lbl:Hide()
  self.bd, self.edges, self.lbl, self.fs = bd, edges, lbl, fs
  uiMarks[i] = self
  return self
end

-- ★用户要求：信息条上的拖拽柄 = **拖动整个图层**（不是拖那条文字）。
--   实现：拖动开始前记下图层 left/top 与有效缩放 → 结束按差值累计到该层自定义记录的 dx/dy
--   → 再用**原始锚点 + 新偏移**重设（与「应用坐标」同一套语义，互不打架、可被清理自定义还原）。
local markDragFrom = {}

function markDragBegin(path, frame)
  if not (frame and path) then return end
  local okl, l = pcall(frame.GetLeft, frame)
  local okt, t = pcall(frame.GetTop, frame)
  local oks, es = pcall(frame.GetEffectiveScale, frame)
  -- ★★★1.74.29 修（用户：「首次拖拽之后目标层会有个坐标偏移问题」）：
  --   必须在**拖之前**就把「原始锚点」记下来。否则首次拖拽时 markDragEnd 会把拖**后**的锚点
  --   当基准、又把位移加上去 → 位置 = 拖后 + 位移（看起来就是“偏移翻倍”）。
  local okp, p, rel, relp, px, py = pcall(frame.GetPoint, frame, 1)
  markDragFrom[path] = {
    l = okl and l or nil, t = okt and t or nil, es = (oks and tonumber(es)) or 1,
    -- ★拖前锚点（首次拖拽的基准）：相对帧**只存名字**
    opt = (okp and p) and { p, uiRelName(rel), relp, px, py } or nil,
  }
  return markDragFrom[path] -- ★1.74.34-5：调用方（OnMouseDown）要拿这份快照喂给 placeFrom 每帧重建
end

function markDragEnd(path, frame)
  local from = markDragFrom[path]
  markDragFrom[path] = nil
  if not (from and frame) then return end
  local okl, l = pcall(frame.GetLeft, frame)
  local okt, t = pcall(frame.GetTop, frame)
  if not (okl and okt and tonumber(l) and tonumber(t) and tonumber(from.l) and tonumber(from.t)) then return end
  local es = tonumber(from.es) or 1
  if es == 0 then es = 1 end
  local ddx = (l - from.l) / es
  local ddy = (t - from.t) / es
  -- 取该层自定义记录（没有就按当前位置建一条）
  local e = nil
  for _, it in ipairs(ui.entries or {}) do
    if it.path == path then e = it break end
  end
  local c = ui.cust[path]
  if not c then
    if e then c = uiCustEnsure(e) else c = { set = {} } ui.cust[path] = c end
  end
  if not c.opt then
    -- ★首次拖拽：用**拖前锚点**（markDragBegin 记下的）作为基准，这样 dx/dy 的累加才对得上。
    if from.opt then
      c.opt = from.opt
    else
      local okp, p, rel, relp, x, y = pcall(frame.GetPoint, frame, 1)
      if okp and p then c.opt = { p, uiRelName(rel), relp, x, y } end
    end
  end
  c.set.dx = (tonumber(c.set.dx) or 0) + ddx
  c.set.dy = (tonumber(c.set.dy) or 0) + ddy
  if c.opt then
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, c.opt[1], uiOptRel(c), c.opt[3],
      (tonumber(c.opt[4]) or 0) + c.set.dx, (tonumber(c.opt[5]) or 0) + c.set.dy)
  end
  uiCustSave()
  P(string.format("图层已拖动：%s（累计偏移 %+.0f,%+.0f；可用『清理自定义』或『还原坐标』复位）",
    tostring(path), c.set.dx, c.set.dy))
  if uiRefresh then uiRefresh() end
end

-- ★★★1.74.34-5 方案 A 核心：**位移一律按屏幕算 + 量回自证**（主仓 dfPlaceFrom 同款口径的子插件小号版）。
--   输入 = 拖前快照（实测屏幕位置 from.l/from.t + 缩放 from.es + 拖前锚点 from.opt）与光标**累计**位移（不除缩放）；
--   首猜「偏移增量 = 屏幕位移 ÷ 缩放」→ SetPoint → **量回**（GetLeft/GetTop 实测）→ 手量折算修正（≤3 轮）。
--   ★绝不每帧回读 GetPoint 加增量（本客户端偏移口径有歧义，回读会累积成漂移——主仓注释定性过的坑）。
uiMarkPlaceFrom = function(f2, from, totX, totY)
  if not (f2 and from and from.opt) then return false end
  local es = tonumber(from.es) or 1
  if es == 0 then es = 1 end
  local wantL = (tonumber(from.l) or 0) + (tonumber(totX) or 0)
  local wantT = (tonumber(from.t) or 0) + (tonumber(totY) or 0)
  local k = es
  local ox, oy = (tonumber(totX) or 0) / k, (tonumber(totY) or 0) / k
  local function apply(ox2, oy2)
    pcall(f2.ClearAllPoints, f2)
    return pcall(f2.SetPoint, f2, from.opt[1], from.opt[2], from.opt[3],
      (tonumber(from.opt[4]) or 0) + ox2, (tonumber(from.opt[5]) or 0) + oy2)
  end
  if not apply(ox, oy) then return false end
  for _ = 1, 3 do
    local okl, l1 = pcall(f2.GetLeft, f2)
    local okt, t1 = pcall(f2.GetTop, f2)
    if not (okl and okt and tonumber(l1) and tonumber(t1)) then return true end
    local ex, ey = wantL - l1, wantT - t1
    if math.abs(ex) <= 1 and math.abs(ey) <= 1 then return true end
    local stepX, stepY = ex / k, ey / k
    ox, oy = ox + stepX, oy + stepY
    if not apply(ox, oy) then return true end
    local okl2, l2 = pcall(f2.GetLeft, f2)
    local okt2, t2 = pcall(f2.GetTop, f2)
    if okl2 and okt2 and tonumber(l2) and tonumber(t2) then
      -- ★真实折算 = 本次屏幕位移 ÷ 本次偏移增量（手量，覆盖首猜；只在这个轴真的动了 ≥1px 时才量）
      if math.abs(stepX) >= 1 then
        local km = (l2 - l1) / stepX
        if km > 0.05 and km <= 20 then k = km end
      elseif math.abs(stepY) >= 1 then
        local km = (t2 - t1) / stepY
        if km > 0.05 and km <= 20 then k = km end
      end
    end
  end
  return true
end

-- ★方案 B 收尾唯一入口：任何一路结束（信息条 OnMouseUp / 全屏接盘 / 静止 / 超时 / 换拖 / 目标丢失）
--   都走这里——清拖拽状态 + 藏接盘 + 按屏幕差落存档（markDragEnd 现口径不动）。
uiMarkDragStop = function(self, why)
  if not self or not self.dragging then return end
  self.dragging = nil
  if markDragActive == self then markDragActive = nil end
  uiMarkCatcherShow(false)
  local f2 = self.layer
  if f2 and self.path then markDragEnd(self.path, f2) end
end

-- 信息条位置：有存档偏移就按存档放（相对宿主左上角），否则默认贴该层左上角
local function uiMarkPlace(m, e)
  local host = uiHost()
  local c = ui.cust[e.path]
  pcall(m.lbl.ClearAllPoints, m.lbl)
  if c and c.lx and c.ly then
    pcall(m.lbl.SetPoint, m.lbl, "TOPLEFT", host, "TOPLEFT", c.lx, c.ly)
  else
    pcall(m.lbl.SetPoint, m.lbl, "BOTTOMLEFT", e.f, "TOPLEFT", 0, 2)
  end
end

-- 拖动结束 → 存偏移（含缩放的坐标必须除 GetEffectiveScale，本项目铁律）
function uiMarkSavePos(path, lbl)
  local host = uiHost()
  local okl, l = pcall(lbl.GetLeft, lbl)
  local okt, t = pcall(lbl.GetTop, lbl)
  local oks, es = pcall(lbl.GetEffectiveScale, lbl)
  local okhl, hl = pcall(host.GetLeft, host)
  local okht, ht = pcall(host.GetTop, host)
  if okl and okt and oks and okhl and okht and tonumber(es) and es ~= 0 then
    local c = ui.cust[path] or { set = {} }
    c.lx = (l / es) - (hl / es)
    c.ly = (t / es) - (ht / es)
    ui.cust[path] = c
    uiCustSave()
    P("（信息条位置记忆已废弃：现在拖拽柄拖动的是整个图层）")
  end
end

-- 为「有自定义设置」的层刷新地图标记
local function uiMarksRefresh(entries)
  local n = 0
  for _, e in ipairs(entries or ui.entries or {}) do
    if ui.cust[e.path] and e.f then
      n = n + 1
      local m = uiMarkGet(n)
      m.path = e.path -- 拖拽柄靠它把位置写回该层的存档
      m.layer = e.f -- ★拖拽柄拖的是这个层帧
      local r, g, b = uiColorFor(e.path)
      for _, t in ipairs(m.edges) do pcall(t.SetVertexColor, t, r, g, b, 0.95) end
      pcall(m.bd.ClearAllPoints, m.bd)
      pcall(m.bd.SetPoint, m.bd, "TOPLEFT", e.f, "TOPLEFT", -2, 2)
      pcall(m.bd.SetPoint, m.bd, "BOTTOMRIGHT", e.f, "BOTTOMRIGHT", 2, -2)
      local nm = e.name or e.path
      pcall(m.fs.SetText, m.fs, string.format("#%s %s  %s", tostring(e.no or "?"), tostring(nm), uiCustSummary(e.path) or ""))
      pcall(m.fs.SetTextColor, m.fs, r, g, b)
      uiMarkPlace(m, e) -- 默认贴该层左上角；有存档偏移则按偏移
      pcall(m.bd.Show, m.bd)
      pcall(m.lbl.Show, m.lbl)
      if n >= 24 then break end
    end
  end
  for i = n + 1, table.getn(uiMarks) do
    if uiMarks[i] then
      pcall(uiMarks[i].bd.Hide, uiMarks[i].bd)
      if uiMarks[i].lbl then pcall(uiMarks[i].lbl.Hide, uiMarks[i].lbl) end
    end
  end
  return n
end


-- ★1.74.34：skipExtra = true 时**只建扫描树条目**（深挖视图：不追加 [顶层] 点名帧与 [全局] 框拖拽目标）。
local function uiBuildEntries(skipExtra)
  if not nodes then buildNodes() end
  ui.entries = {}
  ui.treeDone = false -- ★★★1.74.31 第二步：条目重建 ⇒ 树（父子/子层数）必须重算（否则新条目的 kids 是上一轮的残留）
  local no = 0
  for i, nd in ipairs(nodes or {}) do
    no = no + 1
    -- ★d = 扫描时就写好的**层号**（根 = 1）；带上它，缩进与「层深」过滤才是同一口径（字符串数 '/' 会漏算前缀源）
    -- ★1.74.34-26：`scaleable` 判据也必须走 uiField —— 这里原来 `type(nd.f.SetScale)` 直接索引，
    --   遇到「不能索引的对象」会让 **uiBuildEntries 当场抛错**（真机红字 `attempt to index field 'f'` 的另一个现场）。
    table.insert(ui.entries, { path = nd.n, f = nd.f, scaleable = (type(uiField(nd.f, "SetScale")) == "function"), i = i, no = no, depth = tonumber(nd.d) or nil })
  end
  if not skipExtra then
  for _, nm in ipairs(TOP) do
    -- ★★门控必须在**本函数内**声明 okSrc（上一版写成别处函数的 local → 在这里是全局 nil，
    --   会把 TOP 条目全部过滤掉，属"改一处埋一坑"）：只收当前扫描源被勾选的点名帧。
    local okSrc = (type(uiScanSrcOn) ~= "function") or uiScanSrcOn(topSrcOf(nm))
    local f = _G[nm]
    if type(f) == "table" or type(f) == "userdata" then
      if okSrc then
        no = no + 1
        table.insert(ui.entries, { path = "[顶层] " .. nm, f = f, scaleable = (type(f.SetScale) == "function"), top = true, no = no })
      end
    end
  end
  -- ★★★1.74.29：**框拖拽的目标也进列表**（否则它们的定位记录在界面上完全看不到，用户以为没存）
  -- ★★★1.74.30：目标清单从工具模块现取（EVAL_DF_TARGETS = 唯一来源，本文件不再抄一份）
  local dfTgts = (type(EVAL_DF_TARGETS) == "function") and EVAL_DF_TARGETS() or nil
  for _, tgt in ipairs(dfTgts or {}) do
    -- ★1.74.31：目标可能是**候选名解析**出来的（动作条1~4 的帧名在本客户端未知，见 tools/DragFrames.lua）
    --   ⇒ 一律用模块交给我们的 `frame` 帧对象与 `resolved` 命中名，本文件**不再自己查 _G**。
    local fr = tgt.frame or _G[tgt.name]
    local showName = tgt.resolved or tgt.name
    if (type(fr) == "table" or type(fr) == "userdata") then
      no = no + 1
      table.insert(ui.entries, {
        path = "[全局] " .. showName, f = fr,
        scaleable = (type(fr.SetScale) == "function"), top = true, dragTarget = true, no = no,
      })
    end
  end
  end
  -- 存档里已自定义的层：即使当前过滤/树里没有，也让颜色与编号沿用
  for path in pairs(ui.cust or {}) do
    uiColorFor(path)
  end
  return ui.entries
end

-- ★事件/脚本过滤项（用户要求：顶部操作栏加事件过滤，支持多选）
--   语义 = **任一命中**即显示（多选取并集；都未选 = 不过滤）。
--   "*event" = 有已注册事件（按已知名单逐个 IsEventRegistered 探测，命中任一即算）。
local SCRIPT_FILTERS = {
  { k = "OnClick", label = "点击" },
  { k = "OnEnter", label = "悬停" },
  { k = "OnUpdate", label = "帧更新" },
  { k = "OnEvent", label = "事件" },
  { k = "OnMouseWheel", label = "滚轮" },
  { k = "OnDragStart", label = "拖动" },
  { k = "*event", label = "已注册事件" },
}

-- 缓存：同一帧的脚本判定在本次刷新内只算一次（GetScript 便宜，但 660 层 × 7 项仍值得缓存）
local scriptCache = {}

local function uiScriptHit(fr, key)
  if not fr then return false end
  local cache = scriptCache[fr]
  if not cache then cache = {} scriptCache[fr] = cache end
  local v = cache[key]
  if v ~= nil then return v end
  local ok2 = false
  if key == "*event" then
    local ev = uiField(fr, "IsEventRegistered")
    if type(ev) == "function" then
      for _, en in ipairs(KNOWN_EVENTS or {}) do
        local ok, r = pcall(ev, fr, en)
        if ok and (r == true or r == 1) then ok2 = true break end
      end
    end
  else
    local gs = uiField(fr, "GetScript")
    if type(gs) == "function" then
      local ok, fn = pcall(gs, fr, key)
      ok2 = ok and (type(fn) == "function")
    end
  end
  cache[key] = ok2
  return ok2
end

local function uiScriptFilterCount()
  local n = 0
  for _ in pairs(ui.scriptFilter or {}) do n = n + 1 end
  return n
end

-- ★★1.74.31「这条目有没有名字」按条目缓存：帧名建好就不变，uiScanState 每次刷新会重算；
--   这里的懒算是给**没走过 uiScanState 就直接调 uiFiltered** 的调用点兜底（例如「全选结果」按钮）。
--   判据唯一来源 = uiFrameName（见文件上方）。
-- ★★★1.74.31 修正（用户截图：开关=开 却仍然列出 `纹理:Texture`）：
--   真因 = 旧判据只问「对象有没有 GetName」，而这些条目的对象是**区域（Texture/FontString）**，
--   按“区域也可能有名字”的口径去判 → 它们被当成「有名字」而不被隐藏。
--   现在：**只有「帧」才按 GetName() 判名字；区域层（纹理/字体串/边框等）一律归为「无名」**。
local function uiIsRegionObj(v)
  if not v then return false end
  -- ★1.74.34-26：所有字段读一律走 uiField（个别对象不能索引，直接 `v.X` 会抛错打断刷新）
  local tfn = uiField(v, "GetObjectType")
  if type(tfn) == "function" then
    local ok, t = pcall(tfn, v)
    if ok and type(t) == "string" then
      if t == "Texture" or t == "FontString" or t == "Line" or t == "Model" or t == "PlayerModel" then return true end
      if t == "Frame" or t == "Button" or t == "EditBox" or t == "ScrollFrame" or t == "Slider" or t == "StatusBar" or t == "Cooldown" then return false end
    end
  end
  -- 拿不到类型：能做框的事（有 GetFrameLevel）就当帧，否则当区域
  if type(uiField(v, "GetFrameLevel")) == "function" then return false end
  if type(uiField(v, "GetVertexColor")) == "function" or type(uiField(v, "GetStringWidth")) == "function" then return true end
  return false
end

-- ★★★1.74.31：条目的**层级深度**（用路径的 "/" 分段数；顶层 = 1）；供「层深」过滤与后续可折叠树用。
local function uiEntryDepth(e)
  if e and e.depth then return e.depth end
  local p = (e and e.path) or ""
  local n = 1
  for _ in string.gmatch(p, "/") do n = n + 1 end
  if e then e.depth = n end
  return n
end
local function uiEntryNamed(e)
  if e.named == nil then
    -- ★★★1.74.34-24 修（用户报：「加了可见性功能之后一些图层纹理信息就看不见了，选全部也是」）：
    --   旧判据把**所有区域层（纹理/字体串）一票否决当无名**（`e.isRegion` 直接参与 `named`），
    --   于是「隐藏无名」一开，**有真名的纹理**（WorldMapDetailTile1..12 / WorldMapOverlay1..9 /
    --   WorldMapHighlight）也被一起藏掉 —— 而用户要看的恰恰是这些层的贴图与几何。
    --   ★「是不是区域层」本来就不是「有没有名字」的判据（两者被混在一句里了）。
    --   而真正该藏的那一片「纹理:Texture」，特征是**GetName 为空**或**合成名**
    --   （本客户端会给无名纹纹理编「贴图路径_0x地址」，见 uiNameLooksFake）—— 与区域/帧无关。
    --   ⇒ 判据收敛成一句：**有名字、且不是合成名** 才算有名（区域层同样适用）。
    --   ★tooltip（DBX_NAMED_TIP）一直就是这么向用户承诺的，是**实现比文案更严**，不是需求变了。
    --   ★顺带保住 1.74.31 那次修复的成果：合成名与无名层照旧被藏（用户连报三次的那片 `纹理:Texture`）。
    e.isRegion = uiIsRegionObj(e.f) or (e.scaleable == false)
    local nm = uiFrameName(e.f)
    e.fakeName = (nm ~= nil and uiNameLooksFake(nm)) and true or false
    e.named = (nm ~= nil and (not e.fakeName)) and true or false
  end
  return e.named
end

-- ===== ★★★1.74.31 第二步：真正的可折叠树（用户要求：▸/▾ 折叠开关 + 按层级缩进 + 记住折叠状态 + 配合「层深」）=====
--   用户原话：「图层调试 图层列表能否有树的方式。现在量太大。有点卡」→ 第一步做了「层深」过滤，
--   这一步做**真正的树**：每行左侧一个折叠开关（只对**有子层**的行显示）、缩进按层级、
--   折叠状态落存档（ui.treeCollapsed）、点「层深」= 一次展开到该深度。
--   ★几何常量集中在这里（唯一来源）：行内左侧从 30 起（左侧真选中框 2..16、颜色块 20..27），
--     每深一层右移 10px；文字从「箭头右边」开始（42）并跟着缩进走。
local UI_TREE_X0 = 30   -- 第 1 层的折叠开关左边缘
local UI_TREE_STEP = 10 -- 每深一层的缩进
local UI_TREE_TX = 42   -- 文字左起点（= X0 + 箭头宽 12，保证与箭头不重叠）
local UI_TREE_OPEN = "▼" -- 展开中（子层就在下面）
local UI_TREE_SHUT = ">" -- 已折叠（子树收起来了）
--   ★★1.74.34-4 真机定案（用户截图：展开的 ▼ 能显示、折叠态显示不出来）：
--     本客户端面板字体**只有上下箭头**（滚动条的 ▲▼ 能渲染）⇒ 折叠态的 ▶ 渲染成空白，
--     用户看着像「折叠图标没画」。按本行注释留的后路改字面量：折叠态换成 **ASCII ">"**
--     （任何字体都能渲染；语义不变 = 收起的子树，点开往右展开）。
--   ★字体只能保证渲染「几何图形」这一段（面板里 ▼▲ 已在用、用户可见）⇒ 折叠态用 > 而不是 ▶：
--     若真机上 > 显示不合适，**只改这两行字面量即可**（其余逻辑与它无关）。

-- 由「扫描层号 + DFS 前序相邻性」算父子：维护一个「还没闭合的祖先栈」，遇到层号 ≤ 栈顶的条目就弹栈。
--   ★为什么不按路径字符串切父级：① 根条目叫 `WorldMapFrame(本体)`、子条目叫 `WorldMapFrame/X`（前缀对不上，带前缀的源还多一层）；
--     ② 同一帧下的多个区域路径**完全相同**（`.../region:Texture`），路径做键会把多个节点混成一个；
--     ③ 过滤会藏掉中间层 —— 按「过滤后的列表」算父子会随开关漂移（折叠一半的树会变形）。
--   ⇒ 层级来自扫描（唯一真源），兄弟/父子只靠**顺序**，与过滤状态无关。
local function uiTreePass()
  local list = ui.entries or {}
  local stack = {}
  for i = 1, table.getn(list) do
    local e = list[i]
    local d = uiEntryDepth(e)
    e.kids = 0     -- 每次重算（条目对象是复用的 ⇒ 不清会留下上一轮的计数）
    e.visKid = nil -- 同上：本轮的「这一支里有没有**当前能显示**的子层」由 uiFiltered 现算
    while table.getn(stack) > 0 and uiEntryDepth(stack[table.getn(stack)]) >= d do
      table.remove(stack)
    end
    local par = (table.getn(stack) > 0) and stack[table.getn(stack)] or nil
    e.tpar = par   -- 父条目（nil = 这棵树的根）
    if par then par.kids = (par.kids or 0) + 1 end
    table.insert(stack, e)
  end
  ui.treeDone = true
  return list
end

-- 本条目的**任一祖先**被折叠 ⇒ 不显示（整棵子树一起收）
local function uiTreeHidden(e)
  local p = (e and e.tpar) or nil
  local guard = 0
  while p do
    if ui.treeCollapsed and ui.treeCollapsed[p.path] then return true end
    p = p.tpar
    guard = guard + 1
    if guard > 64 then break end -- 环兜底（tpar 只由本文件的 pass 写，理论无环）
  end
  return false
end

-- 「层深」= **展开到第 N 层**（用户要求「配合层深可快速展开到指定深度」）：
--   把比 N 浅的折叠标记清掉 ⇒ 第 1..N 层必定全部展开（N=0/全部 ⇒ 一个都不清，尊重用户手工折的那些）
local function uiTreeExpandTo(depth)
  local d = tonumber(depth) or 0
  if d <= 0 then return 0 end
  local n = 0
  for _, e in ipairs(ui.entries or {}) do
    if uiEntryDepth(e) < d and ui.treeCollapsed and ui.treeCollapsed[e.path] then
      ui.treeCollapsed[e.path] = nil
      n = n + 1
    end
  end
  return n
end

-- 已折叠的节点数（供状态行显示「树折叠:N」—— 让「列表变短」这件事在界面上**看得见**，而不是让人以为数据没了）
--   ★只数**当前条目里**的标记：存档里可能留下上一轮扫描（换了扫描源）的旧路径标记，那些不显示、也不该算。
local function uiTreeCollapsedCount()
  local n = 0
  for _, e in ipairs(ui.entries or {}) do
    if ui.treeCollapsed and ui.treeCollapsed[e.path] then n = n + 1 end
  end
  return n
end

-- ★「层深」的**唯一入口**（顶栏按钮循环 / 展开时自动抬高都走它）：写值 → 展开到该层 → 存盘 → 刷列表与按钮文案
local function uiDepthApply(depth)
  local d = tonumber(depth) or 0
  ui.depthMax = math.max(0, math.min(9, d))
  local n = uiTreeExpandTo(ui.depthMax)
  if ui.depthSync then pcall(ui.depthSync) end -- 顶栏文案按真值现算（与 namedLabel 同款：不许两处各写一份）
  uiSaveSettings()
  ui.off = 0
  if uiRefresh then uiRefresh() end
  return ui.depthMax, n
end

-- ★点一行的折叠开关 = 折叠/展开这一棵子树（真实控件 OnClick 走这里）
--   ★三种状态要分清（否则会出现「点了没反应」的假开关）：
--     ① 已折叠（有折叠标记）           → 展开：清标记；
--     ② 没折叠，但**「层深」上限把子层挡住**（cap ≤ 本层）→ 展开 = 把上限抬到「本层+1」（默认 层深:1 时点第一层的 ▶ 就是走这里）；
--     ③ 其它                            → 折叠：写折叠标记。
local function uiTreeToggle(e)
  if not e or type(e.path) ~= "string" then return false end
  local d = uiEntryDepth(e)
  local cap = tonumber(ui.depthMax) or 0
  local capBlocks = (cap > 0) and (cap <= d)
  local folded = (ui.treeCollapsed and ui.treeCollapsed[e.path]) and true or false
  if folded then
    ui.treeCollapsed[e.path] = nil
    if capBlocks then
      uiDepthApply(math.min(9, d + 1))
    else
      uiSaveSettings()
      if uiRefresh then uiRefresh() end
    end
  elseif capBlocks then
    uiDepthApply(math.min(9, d + 1))
  else
    ui.treeCollapsed = ui.treeCollapsed or {}
    ui.treeCollapsed[e.path] = true
    uiSaveSettings()
    if uiRefresh then uiRefresh() end
  end
  return true
end

-- ★1.74.34-14：可见性多选的**只筛可见**态（提示文案用；与 uiFiltered 同一份真值 ui.vis）
local function uiVisOnlyShown()
  local v = ui.vis
  return (type(v) == "table") and (v.shown == true) and (v.hidden ~= true)
end

local function uiFiltered()
  if not ui.entries then uiBuildEntries() end
  if not ui.treeDone then uiTreePass() end
  local out = {}
  local f = string.lower(ui.filter or "")
  -- ★★★1.74.34-14 可见性多选（用户要求）：{shown=true} 只要可见 / {hidden=true} 只要不可见 / 两个都要 = 不过滤 / 空表 = 不过滤
  local vsel = ui.vis
  local visOn = (type(vsel) == "table") and ((vsel.shown and true or false) or (vsel.hidden and true or false)) or false
  local onlyVis = (type(vsel) == "table") and ((vsel.shown and not vsel.hidden) and "shown" or ((vsel.hidden and not vsel.shown) and "hidden" or nil)) or nil
  -- ★★「可见性过滤也要保持树结构」（用户要求）：命中可见性的条目 ⇒ 它的**祖先一路保留到顶层**，
  --   祖先**不受可见性过滤影响**（其余过滤照旧生效）。用一个 keep 集合先算、再按 DFS 顺序输出。
  local keep, keepAnc = {}, {}
  for _, e in ipairs(ui.entries) do
    -- 与下面主循环同一套「非可见性」判据（判据保持单一来源：这里只算 okBase，不重复实现可见性）
    local okCat = uiCatDef(ui.cat).test(e)
    local okNamed = (not ui.hideUnnamed) or uiEntryNamed(e)
    local okDepth = ((tonumber(ui.depthMax) or 0) == 0) or (uiEntryDepth(e) <= (tonumber(ui.depthMax) or 1))
    local okBig = (not ui.bigOnly) or (not (e.w and e.h)) or (e.w >= 500 and e.h >= 500)
    local okScript = true
    if uiScriptFilterCount() > 0 then
      okScript = false
      for key in pairs(ui.scriptFilter) do
        if uiScriptHit(e.f, key) then okScript = true break end
      end
    end
    local okTxt = (f == "") or (string.find(string.lower(e.path), f, 1, true) ~= nil)
    local okBase = okCat and okNamed and okDepth and okBig and okScript and okTxt
    if okBase then
      local okVis = (not visOn) or (onlyVis == "shown" and e.shown == true)
        or (onlyVis == "hidden" and e.shown == false)
        or (onlyVis == nil) -- 两个都选 = 不过滤
      if okVis then
        keep[e] = true
        local p = e.tpar
        local guard = 0
        while p do
          keepAnc[p] = true
          p = p.tpar
          guard = guard + 1
          if guard > 64 then break end
        end
      end
    end
    e.baseOK = okBase -- 供主循环复用（同一次刷新内口径一致）
  end
  for _, e in ipairs(ui.entries) do
    if e.baseOK and (keep[e] or keepAnc[e]) then
      -- ★★★1.74.31 第二步：给**祖先记账** —— 只有「这一支里真的有当前能显示的子层」时才给父节点画 ▸/▾；
      --   否则会出现「父节点上挂着 ▾，点下去列表毫无变化」（子层被别的过滤藏起来了）= 假开关。
      local p = e.tpar
      local guard = 0
      while p do
        p.visKid = true
        p = p.tpar
        guard = guard + 1
        if guard > 64 then break end
      end
      -- ★树折叠：祖先被折叠 ⇒ 整棵子树收起（判据唯一来源 uiTreeHidden）
      if not uiTreeHidden(e) then table.insert(out, e) end
    end
  end
  return out
end

-- ★★统计（供播报与 /edb named 诊断）：总数 / 有名 / 无名 / 当前列表实际显示数
local function uiNamedCounts()
  local total, named, unnamed = 0, 0, 0
  for _, e in ipairs(ui.entries or {}) do
    total = total + 1
    if uiEntryNamed(e) then named = named + 1 else unnamed = unnamed + 1 end
  end
  local shown = 0
  if type(uiFiltered) == "function" then
    local ok, list = pcall(uiFiltered)
    if ok and type(list) == "table" then shown = table.getn(list) end
  end
  return { total = total, named = named, unnamed = unnamed, shown = shown, on = ui.hideUnnamed and true or false }
end


-- ★★★1.74.30 框拖拽整块**已搬进主插件工具模块** `tools/DragFrames.lua`（用户两次要求：
--   「图层拖拽是个独立的工具，和地图功能没关系」+「把这块代码抽成 ./tools 下的独立工具模块」）。
--   搬走的内容：LD_DRAG_TARGETS / 拖拽柄(uiDragHandle) / 定时复查(uiDragKeepTick) / 配置弹窗(dragPop 全套) /
--   uiDragRefresh / EVAL_LD_* —— 本文件只剩下面那两处**瘦转发**（/edb drag* 与 EVAL_LD_*）。
--   ★为什么要搬：三条真因（①结束不掉 ②弹窗贴左下角 ③拖拽中定时复查抢锚点）都长在这几段里，
--     而它们与地图功能无关；搬进模块后能**整块重写生命周期**（全屏接盘 + 自校准兜底 + 拖拽期间跳过复查）。

-- ★★★1.74.34-26 条目级扫描（**一次刷新的原子单元**）：原来这段是 uiScanState 里的循环体，
--   现在抽成函数 —— 因为真机里出现了「**一个坏条目打断整次刷新**」：
--   `EH_DebugBox.lua:2377: attempt to index field 'f' (a userdata value)`（那行是 `type(e.f.IsShown)`），
--   一个不能被索引的对象让 uiScanState 抛错 ⇒ 面板列表停更 + 红字弹窗（用户的实机截图）。
--   ⇒ ① 所有字段读走 uiField（读不到 = 当它没这个方法）；② 调用方用 pcall **逐条目**兜底，
--      坏条目**如实记名跳过**（不静默、不假装扫全），其余条目照常刷新。
local function uiScanOne(e)
    -- ★★★1.74.34-26 坏对象闸门：连 `IsShown` 都**索引不了**的对象（真机红字就是它）⇒ 记名跳过，
    --   不去写一堆 nil 字段（那些 nil 会冒充「未知状态」，反而误导）—— 由调用方汇总上报 + 落档。
    e.fBad = false
    if not e.f then e.fBad = true else
      if not pcall(function() return e.f.IsShown end) then e.fBad = true end
    end
    if e.fBad then
      -- 坏条目也要有个**能看懂的显示名**（否则列表那一行是空白/问号，用户以为丢数据）
      local p = e.path or ""
      local lf = string.match(p, "([^/]+)$") or p
      e.name = string.gsub(lf, "^region:", "纹理:")
      e.parent = e.parent or "?"
      return
    end
    local shown = false
    if type(uiField(e.f, "IsShown")) == "function" then
      local ok, v = pcall(uiField(e.f, "IsShown"), e.f)
      shown = (ok and v) and true or false
    end
    e.shown = shown
    -- ★★★1.74.31 修（用户第三次报同一现象：开关显示「开」，列表里仍列着一片 `纹理:Texture`）：
    --   这里原来**直接写** e.named = (uiFrameName(e.f) ~= nil) —— 那是**第二份判据**，
    --   而且比 uiEntryNamed 弱：它不看「这是不是区域层」，也不看「名字是不是合成名」。
    --   更致命的是 uiEntryNamed 只在 e.named == nil 时才计算 ⇒ 这一行一旦先写下去，
    --   uiEntryNamed 里那两条判据（uiIsRegionObj / uiNameLooksFake）**永远不会被走到**：
    --   于是开关看着生效、实际只藏住了「GetName 真返回空」的那些，
    --   区域层（纹理/字体串）与「贴图路径 + 内存地址」的合成名照旧列出来。
    --   现在改成**只失效、不判定**：本条目的 named 判据**唯一来源 = uiEntryNamed**（懒算，本次刷新即算）。
    e.named, e.isRegion, e.fakeName = nil, nil, nil
    local sc, al = nil, nil
    if type(uiField(e.f, "GetScale")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetScale"), e.f)
      if ok and tonumber(v) then sc = v end
    end
    if type(uiField(e.f, "GetAlpha")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetAlpha"), e.f)
      if ok and tonumber(v) then al = v end
    end
    e.scale = sc
    e.alpha = al
    -- ★实时读尺寸（≥500×500 过滤器与列表显示都要）
    local w, h = nil, nil
    if type(uiField(e.f, "GetWidth")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetWidth"), e.f)
      if ok and tonumber(v) then w = tonumber(v) end
    end
    if type(uiField(e.f, "GetHeight")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetHeight"), e.f)
      if ok and tonumber(v) then h = tonumber(v) end
    end
    e.w, e.h = w, h
    -- ★1.74.34-10 用户要求：列表单元展示 **X/Y 坐标**（绝对屏幕坐标：X=左边缘 · Y=下边缘，与主插件 DF 的 X/Y 约定同口径）
    --   ★注意本客户端 GetLeft/GetBottom **含缩放**（R15 ⑥d 实测）——展示的就是「现在在屏幕上的真实位置」，正好。
    local sl, sb = nil, nil
    if type(uiField(e.f, "GetLeft")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetLeft"), e.f)
      if ok and tonumber(v) then sl = tonumber(v) end
    end
    if type(uiField(e.f, "GetBottom")) == "function" then
      local ok, v = pcall(uiField(e.f, "GetBottom"), e.f)
      if ok and tonumber(v) then sb = tonumber(v) end
    end
    e.l, e.b = sl, sb
    -- ★1.74.34-15 用户要求：列表单元显示**相对坐标**（锚点 + 相对帧 + 偏移，即 SetPoint 那一套）
    local apt, arel, arp, ax, ay = nil, nil, nil, nil, nil
    if type(uiField(e.f, "GetPoint")) == "function" then
      local okp, p, rel, relp, x, y = pcall(uiField(e.f, "GetPoint"), e.f, 1)
      if okp and p then
        apt, arel, arp = tostring(p), uiRelName(rel), tostring(relp)
        ax, ay = tonumber(x), tonumber(y)
      end
    end
    e.apt, e.arel, e.arp, e.ax, e.ay = apt, arel, arp, ax, ay
    -- ★清理自定义的兜底依据：**从未自定义过**的层，把当前尺寸记为它的原始默认值
    if not ui.cust[e.path] and w and h then
      local od = ui.origDefaults[e.path]
      if not od then ui.origDefaults[e.path] = { w = w, h = h } end
    end
    -- ★用户要求：列表要显示「层名称 + 当前实际尺寸 + 父类层名称」
    --   名称取叶子名（路径最后一段），父类用 GetParent + GetName
    local path = e.path or ""
    local leaf = string.match(path, "([^/]+)$") or path
    leaf = string.gsub(leaf, "^region:", "纹理:")
    e.name = leaf
    local par = "?"
    if type(uiField(e.f, "GetParent")) == "function" then
      local okp, p = pcall(uiField(e.f, "GetParent"), e.f)
      if okp and p and type(uiField(p, "GetName")) == "function" then
        local okn, pn = pcall(uiField(p, "GetName"), p)
        if okn and type(pn) == "string" and pn ~= "" then par = pn end
      elseif okp and p then
        par = "（无名父级）"
      end
    end
    if e.top then par = e.topParent or par end
    e.parent = par
end

local function uiScanState()
  -- ★★下拉保持打开：刷新/重建时不把已打开的下拉挤掉（状态为开而框被藏 → 重新 Show）
  local function keepDropOpen(dd, flag)
    if not (flag and dd) then return end
    if type(dd.IsShown) ~= "function" then return end
    local ok, sh = pcall(dd.IsShown, dd)
    if ok and not sh then pcall(dd.Show, dd) end
  end
  keepDropOpen(ui.ssDrop, ui.ssOpen)
  keepDropOpen(ui.sfDrop, ui.sfOpen)
  -- ★★1.74.31 修（本轮读代码 + 探针实测发现的既有静默现象）：这里原来是 `if not ui.entries then return end` ——
  --   于是「面板刚打开」或「刚换扫描源」的那一次刷新里 uiScanState **什么都没写**（e.shown 全是 nil），
  --   紧接着 uiFiltered 又按「仅显示中」（默认开）过滤 → **列表全空**，要等下一次刷新（点一下/2 秒 tick）才有数据。
  --   现在改成「没条目就先建条目」——状态（shown/scale/alpha/尺寸/有无名字）当次就有值。
  --   （条目的 named 判据也才有落点：否则 hideUnnamed 会把还没算过 named 的条目当成无名。）
  if not ui.entries then uiBuildEntries() end
  -- ★★★1.74.34-26：逐条目 pcall（坏对象不再能打断整次刷新）；坏条目**如实记名**并落档取证
  ui.badEntries = {}
  for _, e in ipairs(ui.entries) do
    local okE = pcall(uiScanOne, e)
    if (not okE) or e.fBad then
      table.insert(ui.badEntries, tostring(e.path or "?") .. (e.fBad and "（对象不能索引）" or "（读取抛错）"))
    end
  end
  if table.getn(ui.badEntries) > 0 then
    EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
    EH_DEBUGBOX_CFG.badEntries = ui.badEntries
    local now = (type(GetTime) == "function") and GetTime() or 0
    if now - (ui.badReportAt or -99) > 5 then
      ui.badReportAt = now
      P("图层扫描：有 " .. table.getn(ui.badEntries) .. " 个条目**读不了**（对象不能索引）⇒ 已跳过，其余照常："
        .. table.concat(ui.badEntries, " / "))
    end
  end
end

-- 应用到选中：缩放 / 透明度 / 宽 / 高（各参可为 nil = 该项不动）；同时记自定义 + 落存档
local function uiApplyToSelected(scaleV, alphaV, wV, hV)
  -- ★★★1.74.30 框拖拽目标的真值在主插件工具模块（tools/DragFrames.lua）→ 这里一律不动手，并如实说明去处。
  if uiSelHasDragTarget() then
    P("选中的层里有「框拖拽」目标（真值在 tools/DragFrames.lua）：请用工具箱那一行，或 /edb dragapply / /edb dragrect")
    return
  end
  local n, skip = 0, 0
  for _, e in ipairs(uiFiltered()) do
    if ui.sel[e.path] then
      local f = e.f
      local touched = false
      if scaleV and e.scaleable then uiScaleApplyGated(f, scaleV) touched = true end -- ★1.74.34-9：缩放进贴图载入闸门（载完才写）
      -- ★1.74.34-26：方法一律经 uiField 取（坏对象直接 `f.SetAlpha` 会抛错，把整次「应用」打断）
      local fSetAlpha, fSetW, fSetH = uiField(f, "SetAlpha"), uiField(f, "SetWidth"), uiField(f, "SetHeight")
      if alphaV and type(fSetAlpha) == "function" then pcall(fSetAlpha, f, alphaV) touched = true end
      if wV and type(fSetW) == "function" then pcall(fSetW, f, wV) touched = true end
      if hV and type(fSetH) == "function" then pcall(fSetH, f, hV) touched = true end
      if touched then
        local c = uiCustEnsure(e)
        if scaleV then c.set.scale = scaleV end
        if alphaV then c.set.alpha = alphaV end
        if wV then c.set.w = wV end
        if hV then c.set.h = hV end
        n = n + 1
      else
        skip = skip + 1
      end
    end
  end
  uiCustSave() -- ★需求 5：每次改动立即写存档（账号级，下次载入生效）
  P("已应用到选中 " .. n .. " 层"
    .. (scaleV and (" · 缩放=" .. string.format("%.2f", scaleV)) or "")
    .. (alphaV and (" · 透明=" .. string.format("%.2f", alphaV)) or "")
    .. (wV and (" · 宽=" .. string.format("%.0f", wV)) or "")
    .. (hV and (" · 高=" .. string.format("%.0f", hV)) or "")
    .. (skip > 0 and ("；" .. skip .. " 层这些都改不了，已跳过") or ""))
  if uiRefresh then uiRefresh() end
end

-- ★用户要求：主动触发「当前全层扫描信息更新」——重枚举整棵树 + 重读全部状态
-- ★★★1.74.34 用户要求：**有选中目标时，「扫描」= 只深挖选中目标的子树**（下一级往下、不受层深 4 上限
--   与「层深」显示过滤的限制，可一轮轮继续往下挖）——不再全量重枚举所有根，省性能开销；
--   **无选中** = 维持原「全量扫描」。回到全视图：清空选择 → 再点「扫描」。
local function uiScanAll()
  -- ① 选中目标深挖分支（选中按**当前条目**解析；选中的路径已不在条目里 = 落空 → 自动退回全量）
  local targets = {}
  for _, e in ipairs(ui.entries or {}) do
    if (ui.sel or {})[e.path] and (type(e.f) == "table" or type(e.f) == "userdata") then
      table.insert(targets, e)
    end
  end
  if table.getn(targets) > 0 then
    scanHitCap = false
    nodes = {}
    for _, e in ipairs(targets) do
      -- ★根保留**原路径**（不加「(本体)」后缀）⇒ 选中/自定义/折叠等按键记录全部沿用；
      --   层号从 1 重起（深挖视图里它就是树根，缩进/层深过滤同一口径）
      table.insert(nodes, { f = e.f, n = e.path, d = 1 })
      scanTree(e.f, e.path, 1, 64) -- 深挖：上限 64（全量扫描是 4），节点上限 20000 兜底
    end
    ui.entries = nil
    uiBuildEntries(true) -- true = 深挖视图：不追加 [顶层]/[全局] 额外条目
    uiScanState()
    -- 深挖视图直接看到「根 + 下一级」（再往深走点行内 ▶ 或「层深」按钮）
    -- ★层深**唯一写入点 = uiDepthApply**（DBX TREE WIRING CHECK 守的就是这个，绝不直接写字段）
    uiDepthApply(2)
    ui.off = 0
    if uiRefresh then uiRefresh() end
    P("深挖扫描完成：选中 " .. table.getn(targets) .. " 个目标 → 子树共 " .. table.getn(nodes) .. " 层"
      .. (scanHitCap and "（已达节点上限 20000，**未扫全**）" or "")
      .. "（只扫选中子树、不扫全部节点；清空选择后点「扫描」回到全量）")
    return table.getn(ui.entries or {})
  end
  -- ② 全量分支（原行为）
  nodes = nil
  ui.entries = nil
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    -- ★从未开过图 → 借 ShowUIPanel 让客户端把地图帧建出来（否则懒加载子帧根本不存在，树必然不全）
    if type(ShowUIPanel) == "function" then
      pcall(ShowUIPanel, _G["WorldMapFrame"])
    end
    wm = _G["WorldMapFrame"]
  end
  uiBuildEntries()
  ui.entries = ui.entries or {}
  uiScanState()
  if uiRefresh then uiRefresh() end
  local msg = "全层扫描完成：树内 " .. table.getn(nodes or {}) .. " 层 + 顶层帧 " .. table.getn(TOP) .. " 个（状态已刷新）"
  -- ★结果 0 的原因要如实说出来（避免看到空列表就以为“扫描坏了”）
  if table.getn(ui.entries or {}) == 0 then
    local mv = _G["WorldMapButton"]
    local mapOpen = false
    if (type(mv) == "table" or type(mv) == "userdata") and type(mv.IsShown) == "function" then
      local ok, v = pcall(mv.IsShown, mv)
      mapOpen = (ok and v) and true or false
    end
    if (not mapOpen) and uiVisOnlyShown() then
      msg = msg .. "；结果 0：**地图未开** + 可见性只筛「可见」→ 图层全是隐藏态。把可见性改成「不限」或先开图即可看到层**"
    elseif table.getn(ui.entries or {}) == 0 then
      msg = msg .. "；结果 0：当前过滤条件把全部层都排除了（看状态行的「过滤[…]」）"
    end
  end
  P(msg)
  return table.getn(ui.entries)
end

-- ★★用户要求：点击（选中）某个层 → 支持设 x,y 坐标（相对**现有锚点**的偏移增量）
--   做法：取第 1 个锚点 GetPoint(1) → ClearAllPoints → 用**同一组锚点**+新偏移重设。
--   这比「绝对屏幕坐标」安全：不动锚点语义，不会被地图自身的重锚逻辑打架；原值存起来可还原。
local uiPosSaved = nil

local function uiMoveSelected(dx, dy)
  -- ★★★1.74.30 框拖拽目标的真值在主插件工具模块（tools/DragFrames.lua）→ 这里一律不动手，并如实说明去处。
  if uiSelHasDragTarget() then
    P("选中的层里有「框拖拽」目标（真值在 tools/DragFrames.lua）：请用工具箱那一行，或 /edb dragapply / /edb dragrect")
    return
  end
  local n, skip = 0, 0
  uiPosSaved = uiPosSaved or {}
  for _, e in ipairs(uiFiltered()) do
    if ui.sel[e.path] then
      local f = e.f
      if type(f.GetPoint) == "function" and type(f.SetPoint) == "function" and type(f.ClearAllPoints) == "function" then
        local ok, p, rel, relp, x, y = pcall(f.GetPoint, f, 1)
        if ok and p then
          if not uiPosSaved[e.path] then
            uiPosSaved[e.path] = { p, rel, relp, x, y } -- 记原始锚点（首次移动前）
          end
          local o = uiPosSaved[e.path]
          local nx = (tonumber(o[4]) or 0) + dx
          local ny = (tonumber(o[5]) or 0) + dy
          pcall(f.ClearAllPoints, f)
          local ok2 = pcall(f.SetPoint, f, o[1], o[2], o[3], nx, ny)
          if ok2 then
            n = n + 1
            local c = uiCustEnsure(e)
            c.set.dx = dx
            c.set.dy = dy
          else
            skip = skip + 1
          end
        else
          skip = skip + 1
        end
      else
        skip = skip + 1
      end
    end
  end
  P("坐标：已移动选中 " .. n .. " 层（x" .. tostring(dx) .. " y" .. tostring(dy) .. "）"
    .. (skip > 0 and ("；" .. skip .. " 层无 GetPoint/SetPoint，已跳过") or ""))
  uiCustSave() -- ★需求 5：坐标改动也落存档
  if uiRefresh then uiRefresh() end
end

-- ★需求 2：清理自定义设置 —— 把选中层（没选中就全部自定义层）还原到**原始值**
-- ★需求 2 强化（用户：「清理自定义不仅删除自定义属性，还要还原对应层的属性值，比如 0.7 还原到系统默认 1」）
--   三级还原依据：
--     ① ui.cust[path] 里**首次自定义前**记录的原值（oscale/oalpha/ow/oh/opt）；
--     ② 缺值兜底：缩放/透明度 = **系统默认 1**（SetScale/SetAlpha 的原生默认）；
--       宽/高 = ui.origDefaults[path]（**从未自定义时**观测到的原始尺寸）；
--     ③ 原始值恰好等于自定义值（说明当时抓晚了）→ 同样按 ① 的兜底处理，避免"还原成自定义值"。
local function uiClearCustom()
  -- ★★★1.74.30 框拖拽目标的真值在主插件工具模块（tools/DragFrames.lua）→ 这里一律不动手，并如实说明去处。
  if uiSelHasDragTarget() then
    P("选中的层里有「框拖拽」目标（真值在 tools/DragFrames.lua）：请用工具箱那一行，或 /edb dragapply / /edb dragrect")
    return
  end

  local targets = {}
  local anySel = false
  for _, e in ipairs(ui.entries or {}) do
    if ui.sel[e.path] and ui.cust[e.path] then anySel = true break end
  end
  for _, e in ipairs(ui.entries or {}) do
    if ui.cust[e.path] and (not anySel or ui.sel[e.path]) then table.insert(targets, e) end
  end
  local n, miss, detail = 0, 0, 0
  for _, e in ipairs(targets) do
    local c = ui.cust[e.path]
    local f = e.f or uiResolvePath(e.path)
    if (type(f) == "table" or type(f) == "userdata") and c then
      local s = c.set or {}
      -- 缩放：原值可用且不等于自定义值 → 用原值；否则系统默认 1
      local sc = c.oscale
      if not tonumber(sc) or (s.scale and math.abs((tonumber(sc) or 0) - s.scale) < 0.001) then sc = 1 end
      -- 透明度：同上，默认 1
      local al = c.oalpha
      if not tonumber(al) or (s.alpha and math.abs((tonumber(al) or 0) - s.alpha) < 0.001) then al = 1 end
      -- 宽/高：原值缺失时用「从未自定义时观测到的原始尺寸」
      local od = ui.origDefaults[e.path] or {}
      local w = tonumber(c.ow) or tonumber(od.w)
      local h = tonumber(c.oh) or tonumber(od.h)
      if type(f.SetScale) == "function" and type(f.GetScale) == "function" then
        pcall(f.SetScale, f, sc)
        detail = detail + 1
      end
      if type(f.SetAlpha) == "function" then pcall(f.SetAlpha, f, al) detail = detail + 1 end
      if w and type(f.SetWidth) == "function" then pcall(f.SetWidth, f, w) detail = detail + 1 end
      if h and type(f.SetHeight) == "function" then pcall(f.SetHeight, f, h) detail = detail + 1 end
      if c.opt and type(f.SetPoint) == "function" then
        pcall(f.ClearAllPoints, f)
        pcall(f.SetPoint, f, c.opt[1], uiOptRel(c), c.opt[3], c.opt[4], c.opt[5])
        detail = detail + 1
      end
      -- ★1.74.34-12：显隐还原（按第一次改之前记下的 oshown；缺值不去猜，如实跳过）
      if c.oshown == true and type(f.Show) == "function" then
        pcall(f.Show, f) detail = detail + 1
      elseif c.oshown == false and type(f.Hide) == "function" then
        pcall(f.Hide, f) detail = detail + 1
      end
      ui.cust[e.path] = nil
      ui.colorOf[e.path] = nil
      if uiPosSaved then uiPosSaved[e.path] = nil end
      n = n + 1
    else
      miss = miss + 1
    end
  end
  -- 顺手清掉解析不到的残留记录（如实告知）
  if not anySel then
    for path in pairs(ui.cust) do
      if not uiResolvePath(path) then ui.cust[path] = nil ui.colorOf[path] = nil miss = miss + 1 end
    end
  end
  uiCustSave()
  uiMarksRefresh(ui.entries)
  P("清理自定义设置：已还原 " .. n .. " 层（共回写 " .. detail .. " 项属性；缩放/透明度默认回 1）"
    .. (miss > 0 and ("；另有 " .. miss .. " 条解析不到已剔除记录") or ""))
  if uiRefresh then uiRefresh() end
end

local function uiResetPos()
  -- ★★★1.74.30 框拖拽目标的真值在主插件工具模块（tools/DragFrames.lua）→ 这里一律不动手，并如实说明去处。
  if uiSelHasDragTarget() then
    P("选中的层里有「框拖拽」目标（真值在 tools/DragFrames.lua）：请用工具箱那一行，或 /edb dragapply / /edb dragrect")
    return
  end

  local n = 0
  if type(uiPosSaved) == "table" then
    for _, e in ipairs(uiFiltered()) do
      local o = uiPosSaved[e.path]
      if ui.sel[e.path] and o then
        -- ★1.74.34-26：字段读/调一律走 uiField（坏对象直接索引会抛错，见文件上方说明）
        local cap, sp = uiField(e.f, "ClearAllPoints"), uiField(e.f, "SetPoint")
        if type(cap) == "function" then pcall(cap, e.f) end
        if type(sp) == "function" then pcall(sp, e.f, o[1], o[2], o[3], o[4], o[5]) end
        local c = ui.cust[e.path]
        if c and c.set then c.set.dx = nil c.set.dy = nil end
        n = n + 1
      end
    end
  end
  uiCustSave()
  P("坐标：已还原选中层到原始锚点（" .. n .. " 层）")
  if uiRefresh then uiRefresh() end
end

-- ★★★1.74.34-12 用户要求：「图层属性再添加个隐藏/显示功能」。
--   对**选中的层**执行 Show/Hide（唯一写显隐的入口），并把结果记进该层的自定义（`set.hidden`）
--   ⇒ 启动自动生效/重设自定义会按存档回写，`清理自定义` 按第一次改之前记下的 `oshown` 还原。
--   ★如实统计：没有 Show/Hide 的对象（区域/只读包装）跳过并计数，不假装成功。
local function uiApplyVisibilityToSelected(hidden)
  local n, skip = 0, 0
  for _, e in ipairs(uiFiltered()) do
    if ui.sel[e.path] then
      local f = e.f
      local fn = hidden and f.Hide or f.Show
      if type(fn) == "function" then
        pcall(fn, f)
        local c = uiCustEnsure(e)
        if c then
          if c.oshown == nil then c.oshown = e.shown and true or false end
          c.set.hidden = hidden and true or false
        end
        n = n + 1
      else
        skip = skip + 1
      end
    end
  end
  uiCustSave()
  P("显隐：" .. (hidden and "已隐藏 " or "已显示 ") .. n .. " 层"
    .. (skip > 0 and ("；" .. skip .. " 层没有 Show/Hide（区域/只读对象），已跳过") or "")
    .. "（记进自定义 ⇒ 启动/重设会按存档回写；『清理自定义』按原始显隐还原）")
  if uiRefresh then uiRefresh() end
  return n, skip
end

-- ★1.74.34-15 用户要求：列表显示**原始尺寸**。三级来源（与「清理自定义」同一套依据，绝不编造）：
--   ① 该层自定义记录里**第一次改之前**记下的 ow/oh（最准）；② 从未自定义时观测到的 origDefaults；
--   ③ 都没有 ⇒ 返回当前尺寸并标明来源=当前（如实，不假装那就是原始值）
local function uiOrigSizeOf(path, e)
  local c = ui.cust[path]
  if c then
    local w, h = tonumber(c.ow), tonumber(c.oh)
    if w or h then return w, h, "自定义前" end
  end
  local od = ui.origDefaults[path]
  if od and (tonumber(od.w) or tonumber(od.h)) then return tonumber(od.w), tonumber(od.h), "观测" end
  return (e and e.w), (e and e.h), "当前"
end

-- ★合并后的应用族（用户要求：功能重复的合并）
--   外观 = 缩放 + 透明 + 宽 + 高；全部 = 外观 + 坐标
local function uiApplyAppearance()
  -- ★只应用被勾选的参数（用户要求）：未勾选的传 nil = 该项不动
  local p = ui.par or {}
  uiApplyToSelected(p.scale and ui.value or nil, p.alpha and ui.alphaValue or nil,
    p.w and ui.wVal or nil, p.h and ui.hVal or nil)
end

local function uiApplyAll()
  uiApplyAppearance()
  uiMoveSelected(ui.xVal or 0, ui.yVal or 0)
end

local function uiBuild()
  if ui.built then return true end
  if type(CreateFrame) ~= "function" then return false end
  local wm = _G["WorldMapFrame"]
  -- ★用户要求：窗口长一点 = **屏幕高度**（行数按可用高度现算，不再写死 12 行）
  local sw = (type(GetScreenWidth) == "function") and GetScreenWidth() or 1024
  local sh = (type(GetScreenHeight) == "function") and GetScreenHeight() or 768
  local W = 560
  local H = math.max(320, sh - 20)
  ui.rows = math.max(6, math.floor((H - 88 - 120) / 21)) -- 88=头部/过滤区（扫描源/事件过滤已并入分类排），120=底部四排
  local root = CreateFrame("Frame", "EH_DB_UI", uiHost())
  root:SetWidth(W) root:SetHeight(H)
  -- ★★用户要求「面板要在地图上层显示」：根因是本项目著名坑 —— **开全屏地图会隐藏 UIParent**
  --   （1.70.39 记录在案），挂在 UIParent 下的面板会跟着被藏。
  --   → 改挂 WorldFrame（开图时不隐藏、关图后也一直在），strata 抬到 FULLSCREEN_DIALOG。
  root:SetPoint("TOPRIGHT", uiHost(), "TOPRIGHT", -10, -10)
  -- ★用户要求：地图关闭后面板**不消失** → 挂 UIParent（不再随地图显隐），位置用右上角锚点
  --   （见上方 root 创建处）
  pcall(root.SetFrameStrata, root, "FULLSCREEN_DIALOG")
  pcall(root.SetFrameLevel, root, 500)
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  uiSolid(bg, 0.02, 0.02, 0.02, 0.94)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, root, "TOP" .. s, 0, 0)
    t:SetPoint("BOTTOM" .. s, root, "BOTTOM" .. s, 0, 0)
    t:SetWidth(1)
  end
  local title = uiFont(root, 12, 0.95, 0.82, 0.35)
  pcall(title.SetPoint, title, "TOP", root, "TOP", 0, -6)
  pcall(title.SetText, title, "图层调试（可拖拽 · 关图不消失）")

  -- ★用户要求：面板可拖拽（Button 柄 + warm-up 两步，本客户端配方）
  local bar = CreateFrame("Button", "EH_DB_UI_BAR", root)
  bar:SetWidth(W - 4) bar:SetHeight(20)
  bar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(bar.SetFrameLevel, bar, 510)
  if type(bar.EnableMouse) == "function" then pcall(bar.EnableMouse, bar, true) end
  if type(bar.RegisterForDrag) == "function" then pcall(bar.RegisterForDrag, bar, "LeftButton") end
  bar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root) -- warm-up 两步
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  bar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    uiSaveSettings() -- ★面板位置也记进用户配置
  end)

  -- ★用户要求：右上角**关闭按钮**（标题栏右侧）
  local closeB = CreateFrame("Button", nil, root)
  closeB:SetWidth(20) closeB:SetHeight(16)
  closeB:SetPoint("TOPRIGHT", root, "TOPRIGHT", -4, -3)
  pcall(closeB.SetFrameLevel, closeB, 512)
  if type(closeB.EnableMouse) == "function" then pcall(closeB.EnableMouse, closeB, true) end
  if type(closeB.RegisterForClicks) == "function" then pcall(closeB.RegisterForClicks, closeB, "LeftButtonUp") end
  local cbg = closeB:CreateTexture(nil, "BACKGROUND")
  cbg:SetAllPoints(closeB)
  uiSolid(cbg, 0.45, 0.12, 0.12, 0.95)
  local ctxt = closeB:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(ctxt.SetFontObject, ctxt, GameFontNormal) end
  pcall(ctxt.SetPoint, ctxt, "CENTER", closeB, "CENTER", 0, 0)
  pcall(ctxt.SetText, ctxt, "X")
  closeB:SetScript("OnClick", function()
    pcall(root.Hide, root)
    P("图层调试面板已关闭（右侧「层」按钮或 /edb ui 可再打开）")
  end)

  -- 过滤行：EditBox + 回声行 + 分类按钮
  local ebOk, eb = pcall(CreateFrame, "EditBox", "EH_DB_FILTER", root)
  if ebOk and eb then
    eb:SetWidth(180) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -26)
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
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    eb:SetScript("OnTextChanged", function()
      ui.filter = tostring(eb:GetText() or "")
      uiSaveSettings()
      ui.off = 0
      if uiRefresh then uiRefresh() end
    end)
    ui.eb = eb
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -24)
    ebBg:SetWidth(184) ebBg:SetHeight(22)
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
  end
  local echo = uiFont(root, 10, 0.7, 0.9, 0.7)
  pcall(echo.SetPoint, echo, "TOPLEFT", root, "TOPLEFT", 12, -48)
  pcall(echo.SetWidth, echo, 200)
  pcall(echo.SetJustifyH, echo, "LEFT")
  pcall(echo.SetText, echo, "过滤：（不填=全部）")
  ui.echo = echo

  -- ★★★1.74.31 第二步**顺带修掉一处死代码**（本轮读代码 + 组 205 实测发现）：
  --   uiRefresh 一直在算那行状态（`结果 N · 选中 M · 过滤[仅显示中+层深:3+树折叠:2] · 地图已开…`），
  --   却写进 `ui.pageLbl` —— 而 `ui.pageLbl` **从来没有被创建过**（恒 nil ⇒ 那句话永远是空写）。
  --   后果：用户看不到「为什么列表变少了」（层深/树折叠/无名过滤全在这一行里），
  --   正是「以为数据丢了」那类误会的来源。现在把它**真的建出来**：
  --   位置 = 过滤框右侧那条一直空着的带（x 216 起、宽 336，两行；顶栏在 -64、列表在 -88，不会压到任何东西）。
  ui.statLbl = uiFont(root, 10, 0.85, 0.85, 0.85)
  pcall(ui.statLbl.SetPoint, ui.statLbl, "TOPLEFT", root, "TOPLEFT", 216, -30)
  pcall(ui.statLbl.SetWidth, ui.statLbl, 336)
  pcall(ui.statLbl.SetJustifyH, ui.statLbl, "LEFT")
  ui.filterLbl = uiFont(root, 10, 0.80, 0.80, 0.80)
  pcall(ui.filterLbl.SetPoint, ui.filterLbl, "TOPLEFT", root, "TOPLEFT", 216, -46)
  pcall(ui.filterLbl.SetWidth, ui.filterLbl, 336)
  pcall(ui.filterLbl.SetJustifyH, ui.filterLbl, "LEFT")

  -- ★★★1.74.31 顶栏分类按钮：**只建 UI_CAT_DEFS 里 tab=true 的**
  --   （用户要求删掉「原生地图 / 任务图钉 / 顶层帧」三个按钮 ⇒ 它们的 tab=false，判据仍留在表里 = 能力保留）。
  --   坐标走 uiTopTake 游标（从 8 起、每枚 宽+4）⇒ 删了按钮后面的自动左移，不会有空洞也不会重叠。
  ui.topX = 8
  ui.catBtns = {}
  for _, d in ipairs(uiCatTabs()) do
    local code, label = d.code, d.label -- ★先取到本轮局部（闭包不依赖循环变量/循环外变量）
    local w = 46 -- ★1.74.34-13：分类按钮文案现在都是 2~3 个汉字（「全部/隐藏层」），统一宽度
    local b = uiBtn(root, w, 18, label)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", uiTopTake(w), -64)
    b:SetScript("OnClick", function()
      ui.cat = code
      uiSaveSettings()
      ui.off = 0
      if uiRefresh then uiRefresh() end
      P("分类：" .. label .. (code == 0 and "（不过滤 = 全部层）" or ""))
    end)
    table.insert(ui.catBtns, b)
  end

  -- ★★★1.74.31 用户要求：「增加一个过滤开关：只显示有名字的 / 隐藏没有名字的层。默认隐藏」
  --   · 真值 = ui.hideUnnamed（默认 true = 隐藏无名层），落子插件自己的存档 EH_DEBUGBOX_CFG.ui.hideUnnamed；
  --   · 文案与 tooltip 走三语语言包（L("DBX_NAMED_ON") / L("DBX_NAMED_OFF") / L("DBX_NAMED_TIP")）；
  --   · 判据唯一来源 = uiFrameName（GetName 非空），与「全层扫描测量」的 命名/无名 同口径。
  local function namedLabel()
    if ui.hideUnnamed then return L("DBX_NAMED_ON") end
    return L("DBX_NAMED_OFF")
  end
  local namedBtn = uiBtn(root, 96, 18, namedLabel())
  namedBtn:SetPoint("TOPLEFT", root, "TOPLEFT", uiTopTake(96), -64)
  ui.namedBtn = namedBtn
  ui.namedLabel = namedLabel -- ★恢复设置时按存档值重写按钮文案（不能写死「开」）
  namedBtn:SetScript("OnClick", function()
    ui.hideUnnamed = (not ui.hideUnnamed) and true or false
    pcall(namedBtn.label.SetText, namedBtn.label, namedLabel())
    uiSaveSettings()
    ui.off = 0
    if uiRefresh then uiRefresh() end
    -- ★★1.74.31：如实播报 + **带上数字**（用户问「只显示名字是无法屏蔽掉纹理吗？」→ 把效果变成可看的数字，不用猜）
    local cnt = uiNamedCounts()
    P(string.format("无名层过滤：%s · 当前列表 %d 条（共 %d 条：有名 %d · 无名 %d）",
      (ui.hideUnnamed and "开（只显示有名字的层）" or "关（无名层也一并显示）"),
      cnt.shown, cnt.total, cnt.named, cnt.unnamed))
  end)
  -- ★★层深按钮：点一下循环 1→2→3→4→全部(0)（★1.75.13 用户定稿默认 **1 = 只显示第一层**）
  --   ★★★1.74.31 第二步：它同时是**树的「展开到第 N 层」** —— 走唯一入口 uiDepthApply（写值 + 清掉更浅的折叠标记 + 存盘 + 刷新）。
  --   ★★★1.74.34 修（用户截图：「层深:3」压在底部「扫描」按钮上）：旧代码 `pcall(uiTopTake, depthBtn, 78)`
  --     把**按钮本体**当宽度传给游标 ⇒ `x + 帧 + 4` 算术炸在 pcall 里 ⇒ depthBtn **从没 SetPoint**（无锚点帧
  --     落在父级默认位置 = 左下角，正好压住第四排的「扫描」），且游标没前进（后面三枚按钮全左移 82px）。
  --     现在改放**底部第四排**（扫描右侧；顶排因此也不超宽：分类+无名+扫描源+事件+框拖拽右端 496 < 560）。
  local depthBtn = uiBtn(root, 72, 18, "")
  depthBtn:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 76, 8) -- 第四排：扫描(8..68) 右侧
  local function depthLabel()
    local d = tonumber(ui.depthMax) or 1 -- ★兜底 = 默认值（1 = 只显示第一层）
    return "层深:" .. ((d == 0) and "全部" or tostring(d))
  end
  local function depthSync()
    if depthBtn and depthBtn.label then pcall(depthBtn.label.SetText, depthBtn.label, depthLabel()) end
  end
  depthSync()
  ui.depthBtn = depthBtn
  ui.depthSync = depthSync -- ★文案按真值现算、且暴露给「恢复存档」与「折叠自动抬高」两条路径（与 ui.namedLabel 同款）
  depthBtn:SetScript("OnClick", function()
    local d = tonumber(ui.depthMax) or 1 -- ★同上：兜底 = 默认 1（点一下 → 2 → 3 → 4 → 全部 → 1）
    if d == 1 then d = 2 elseif d == 2 then d = 3 elseif d == 3 then d = 4 elseif d == 4 then d = 0 else d = 1 end
    local _, un = uiDepthApply(d)
    P("层深：" .. ((d == 0) and "全部层级都显示" or ("只显示前 " .. d .. " 层"))
      .. (un > 0 and ("；顺带展开了 " .. un .. " 个更浅的折叠节点") or ""))
  end)
  -- tooltip 走**自绘**信息面板（本面板宿主下 GameTooltip 不渲染，见 uiTipShow 的说明）
  namedBtn:SetScript("OnEnter", function()
    uiTipShow(namedBtn, {
      { t = L("DBX_NAMED_TIP"), r = 0.95, g = 0.85, b = 0.35 },
      { t = "判据：GetName() 返回空 = 无名（与「/edb scanui」的 命名/无名 统计同口径）", r = 0.80, g = 0.80, b = 0.80 },
    })
  end)
  namedBtn:SetScript("OnLeave", function() uiTipHide() end)

  -- （≥500 过滤开关已并入第三排，顶部只留分类按钮 + 无名层开关）

  -- ★★用户要求（1.74.29 改版）：**一个按钮 → 点击弹出自绘下拉 → 下拉里多选事件类型**
  --   （不是一排按钮）。下拉挂在 uiHost() + FULLSCREEN_DIALOG/800，点按钮切换、点行只切选不关、
  --   另有「清空」与「关闭」两行；选中数显示在按钮文字上。
  local function sfCount()
    local n = 0
    for _ in pairs(ui.scriptFilter or {}) do n = n + 1 end
    return n
  end
  local function sfUpdateBtn()
    if ui.sfBtn and ui.sfBtn.label then
      pcall(ui.sfBtn.label.SetText, ui.sfBtn.label, "事件过滤(" .. sfCount() .. ") ▾")
    end
  end
  local function sfEnsureDrop()
    if ui.sfDrop then return ui.sfDrop end
    local host = uiHost()
    local dd = CreateFrame("Frame", "EH_DB_SFDROP", host)
    dd:SetWidth(190)
    dd:SetHeight(24 * (table.getn(SCRIPT_FILTERS) + 2) + 10)
    pcall(dd.SetFrameStrata, dd, "FULLSCREEN_DIALOG")
    pcall(dd.SetFrameLevel, dd, 800)
    if type(dd.EnableMouse) == "function" then pcall(dd.EnableMouse, dd, true) end
    local bg = dd:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
    uiSolid(bg, 0.03, 0.03, 0.03, 0.96)
    local edge = dd:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", dd, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 1, -1)
    uiSolid(edge, 0.85, 0.70, 0.20, 1)
    dd.rows = {}
    local y = -5
    for _, sf in ipairs(SCRIPT_FILTERS) do
      local rb = CreateFrame("Button", nil, dd)
      rb:SetWidth(180) rb:SetHeight(22)
      rb:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y)
      if type(rb.EnableMouse) == "function" then pcall(rb.EnableMouse, rb, true) end
      if type(rb.RegisterForClicks) == "function" then pcall(rb.RegisterForClicks, rb, "LeftButtonUp") end
      local mk = rb:CreateTexture(nil, "BACKGROUND")
      mk:SetPoint("LEFT", rb, "LEFT", 2, 0)
      mk:SetWidth(13) mk:SetHeight(13)
      uiSolid(mk, 0.10, 0.09, 0.06, 1)
      local tick = rb:CreateTexture(nil, "OVERLAY")
      tick:SetPoint("LEFT", rb, "LEFT", 4, 0)
      tick:SetWidth(9) tick:SetHeight(9)
      uiSolid(tick, 0.95, 0.80, 0.25, 1)
      tick:Hide()
      local tx = rb:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(tx.SetFontObject, tx, GameFontNormal) end
      pcall(tx.SetPoint, tx, "LEFT", rb, "LEFT", 20, 0)
      pcall(tx.SetJustifyH, tx, "LEFT")
      pcall(tx.SetText, tx, sf.label)
      rb.tick, rb.key = tick, sf.k
      rb:SetScript("OnClick", function()
        ui.scriptFilter[sf.k] = (not ui.scriptFilter[sf.k]) and true or nil
        ui.off = 0
        if type(EVAL_LOGLINE) == "function" then
          EVAL_LOGLINE("[DBX] 事件过滤 " .. sf.label .. " = " .. tostring(ui.scriptFilter[sf.k] ~= nil))
        end
        dd.sync()
        if uiRefresh then uiRefresh() end
        uiSaveSettings()
      end)
      dd.rows[table.getn(dd.rows) + 1] = rb
      y = y - 24
    end
    local function mkAction(txt, y2, fn)
      local ab = CreateFrame("Button", nil, dd)
      ab:SetWidth(180) ab:SetHeight(20)
      ab:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y2)
      if type(ab.EnableMouse) == "function" then pcall(ab.EnableMouse, ab, true) end
      if type(ab.RegisterForClicks) == "function" then pcall(ab.RegisterForClicks, ab, "LeftButtonUp") end
      local fs2 = ab:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(fs2.SetFontObject, fs2, GameFontNormal) end
      pcall(fs2.SetPoint, fs2, "CENTER", ab, "CENTER", 0, 0)
      pcall(fs2.SetText, fs2, txt)
      pcall(fs2.SetTextColor, fs2, 0.95, 0.82, 0.35)
      ab:SetScript("OnClick", fn)
      return ab
    end
    mkAction("清空（不过滤）", y, function()
      ui.scriptFilter = {}
      dd.sync()
      if uiRefresh then uiRefresh() end
      uiSaveSettings()
    end)
    mkAction("关闭", y - 22, function() ui.sfOpen = false dd:Hide() sfUpdateBtn() end)
    dd.sync = function()
      for _, rb in ipairs(dd.rows) do
        if ui.scriptFilter[rb.key] then pcall(rb.tick.Show, rb.tick) else pcall(rb.tick.Hide, rb.tick) end
      end
      sfUpdateBtn()
    end
    dd:Hide()
    ui.sfDrop = dd
    return dd
  end
  -- ★扫描源下拉（多选）：地图 / 界面(UIParent) / 世界层 / 小地图簇
  local function ssCount()
    local n = 0
    for _, src in ipairs(SCAN_SRC) do if uiScanSrcOn(src.k) then n = n + 1 end end
    return n
  end
  local function ssUpdateBtn()
    if ui.ssBtn and ui.ssBtn.label then
      pcall(ui.ssBtn.label.SetText, ui.ssBtn.label, "扫描源(" .. ssCount() .. ") ▾")
    end
  end
  local function ssEnsureDrop()
    if ui.ssDrop then return ui.ssDrop end
    local dd = CreateFrame("Frame", "EH_DB_SSDROP", uiHost())
    dd:SetWidth(190) dd:SetHeight(24 * table.getn(SCAN_SRC) + 20 + 44 + 10) -- ★源 + 提示行 + 两行动作
    pcall(dd.SetFrameStrata, dd, "FULLSCREEN_DIALOG")
    pcall(dd.SetFrameLevel, dd, 800)
    if type(dd.EnableMouse) == "function" then pcall(dd.EnableMouse, dd, true) end
    local bg = dd:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
    uiSolid(bg, 0.03, 0.03, 0.03, 0.96)
    local edge = dd:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", dd, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 1, -1)
    uiSolid(edge, 0.85, 0.70, 0.20, 1)
    dd.rows = {}
    local y = -5
    local hint = dd:CreateFontString(nil, "OVERLAY")
    if type(GameFontNormal) ~= "nil" then pcall(hint.SetFontObject, hint, GameFontNormal) end
    pcall(hint.SetPoint, hint, "TOPLEFT", dd, "TOPLEFT", 6, y)
    pcall(hint.SetTextColor, hint, 0.75, 0.75, 0.75)
    pcall(hint.SetText, hint, "多选：点条目切换（不关闭）")
    y = y - 20
    for _, src in ipairs(SCAN_SRC) do
      local rb = CreateFrame("Button", nil, dd)
      rb:SetWidth(180) rb:SetHeight(22)
      rb:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y)
      if type(rb.EnableMouse) == "function" then pcall(rb.EnableMouse, rb, true) end
      if type(rb.RegisterForClicks) == "function" then pcall(rb.RegisterForClicks, rb, "LeftButtonUp") end
      local mk = rb:CreateTexture(nil, "BACKGROUND")
      mk:SetPoint("LEFT", rb, "LEFT", 2, 0)
      mk:SetWidth(13) mk:SetHeight(13)
      uiSolid(mk, 0.10, 0.09, 0.06, 1)
      local tick = rb:CreateTexture(nil, "OVERLAY")
      tick:SetPoint("LEFT", rb, "LEFT", 4, 0)
      tick:SetWidth(9) tick:SetHeight(9)
      uiSolid(tick, 0.95, 0.80, 0.25, 1)
      tick:Hide()
      local tx = rb:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(tx.SetFontObject, tx, GameFontNormal) end
      pcall(tx.SetPoint, tx, "LEFT", rb, "LEFT", 20, 0)
      pcall(tx.SetText, tx, src.label .. "（" .. src.root .. "）")
      rb.tick, rb.key = tick, src.k
      rb:SetScript("OnClick", function()
        -- ★★真正的多选：点条目 = 切换该源（不关下拉）；首次交互后一律按勾选算
        local cur = uiScanSrcOn(src.k)
        ui.scanSrc = ui.scanSrc or { map = true }
        ui.scanSrcTouched = true -- ★从此不再默认开地图
        ui.scanSrc[src.k] = (not cur) and true or nil
        ui.off = 0
        nodes = nil -- ★换扫描源要重扫（缓存作废）
        ui.entries = nil -- ★★关键：条目表也要作废，否则刷新时 uiBuildEntries 不会重建（之前只清 nodes → 列表不变）
        uiScanState() -- 先把新树的状态读一遍
        if uiRefresh then uiRefresh() end
        uiSaveSettings()
        dd.sync()
      end)
      dd.rows[table.getn(dd.rows) + 1] = rb
      y = y - 24
    end
    -- ★★用户要求：点别处（例如列表里的层）**不自动关闭** → 只能用「关闭」行或再点按钮收起
    local function mkAct(txt, y2, fn)
      local ab = CreateFrame("Button", nil, dd)
      ab:SetWidth(180) ab:SetHeight(20)
      ab:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y2)
      if type(ab.EnableMouse) == "function" then pcall(ab.EnableMouse, ab, true) end
      if type(ab.RegisterForClicks) == "function" then pcall(ab.RegisterForClicks, ab, "LeftButtonUp") end
      local fs2 = dd:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(fs2.SetFontObject, fs2, GameFontNormal) end
      pcall(fs2.SetPoint, fs2, "CENTER", ab, "CENTER", 0, 0)
      pcall(fs2.SetText, fs2, txt)
      pcall(fs2.SetTextColor, fs2, 0.95, 0.82, 0.35)
      ab:SetScript("OnClick", fn)
    end
    mkAct("清空（全不选）", y, function()
      ui.scanSrc = {} ui.scanSrcTouched = true
      nodes = nil ui.entries = nil
      uiSaveSettings() dd.sync()
      if uiRefresh then uiRefresh() end
    end)
    mkAct("关闭", y - 22, function() ui.ssOpen = false dd:Hide() ssUpdateBtn() end)
    dd.sync = function()
      for _, rb in ipairs(dd.rows) do
        if uiScanSrcOn(rb.key) then pcall(rb.tick.Show, rb.tick) else pcall(rb.tick.Hide, rb.tick) end
      end
      ssUpdateBtn()
    end
    dd:Hide()
    ui.ssDrop = dd
    return dd
  end
  -- ★★★1.74.34-23 用户报「图层调试工具 少个菜单」：**「可见性」下拉搬到顶栏这一排**（紧跟「只显示有名」之后）。
  --   原因：它原来在**底部第三排**（和「清理自定义/全选结果/清空选择」这些**动作**按钮混在一起），
  --   而面板高度 `H = 屏高 - 20` ⇒ 顶上的过滤行与左下那排隔着**整屏**，
  --   用户在上面的过滤排里根本看不到它（截图里那一排只有 全部/只显示有名/扫描源/事件过滤/框拖拽）。
  --   ★它明显是**过滤**（可见/不可见），和「扫描源/事件过滤」同族 ⇒ 归到顶栏过滤排。
  --   ★顶栏的 x 由 uiTopTake 游标按**创建顺序**发，而可见性的按钮在下面 3700+ 那段才建 ⇒
  --     必须在这里**先把这段 x 取走**（否则游标已走到「框拖拽」之后，可见性会被排到最右边）。
  local VIS_TOP_X = uiTopTake(88)
  local ssBtn = uiBtn(root, 88, 18, "扫描源(1) ▾")
  -- ★★1.74.31：坐标改由 uiTopTake 游标给（紧跟分类按钮与无名层开关之后，自动左移、不重叠、不压列表）
  ssBtn:SetPoint("TOPLEFT", root, "TOPLEFT", uiTopTake(88), -64)
  ui.ssBtn = ssBtn
  ssBtn:SetScript("OnClick", function()
    local dd = ssEnsureDrop()
    if dd:IsShown() then
      ui.ssOpen = false
      dd:Hide()
    else
      ui.ssOpen = true
      dd.sync()
      pcall(dd.ClearAllPoints, dd)
      pcall(dd.SetPoint, dd, "TOPLEFT", ssBtn, "BOTTOMLEFT", 0, -2)
      dd:Show()
    end
    ssUpdateBtn()
  end)
  ssUpdateBtn()

  local sfBtn = uiBtn(root, 88, 18, "事件过滤(0) ▾")
  -- ★★1.74.31：位置在**创建处**就取（走到这里游标一定在扫描源之后）——
  --   旧代码把 SetPoint 写在后面 dragBtn 之后，会让「框拖拽」先占走 x（顺序错 = 按钮错位）。
  sfBtn:SetPoint("TOPLEFT", root, "TOPLEFT", uiTopTake(88), -64)
  -- ★按钮 tooltip：把「探测范围」与「自动刷新」如实写清（名单外看不见 = 结构性边界，不装懂）
  sfBtn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" then return end
    pcall(tip.SetOwner, tip, sfBtn, "ANCHOR_LEFT")
    pcall(tip.ClearLines, tip)
    if type(tip.AddLine) == "function" then
      pcall(tip.AddLine, tip, "事件/脚本过滤（多选，任一命中即显示）", 1, 0.85, 0.3)
      pcall(tip.AddLine, tip, "脚本类：实时读 GetScript，后期挂上的下次刷新即出现", 0.85, 0.85, 0.85)
      pcall(tip.AddLine, tip, "事件类：按 " .. tostring(table.getn(KNOWN_EVENTS or {})) .. " 个已知名单探测 —— 本客户端无枚举 API，名单外看不见", 0.85, 0.85, 0.85)
      pcall(tip.AddLine, tip, "面板开着且已勾选时，每 2 秒自动刷新一次", 0.75, 0.75, 0.75)
    end
    pcall(tip.Show, tip)
  end)
  sfBtn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)

  -- ★★框拖拽开关（默认关：透明层会吃鼠标）
  -- ★★★1.74.30：真值在**主插件工具模块** tools/DragFrames.lua（EVAL_HELP_CONFIG.dragFrames.on）——
  --   本按钮只是第二个入口，**不另存一份状态**（与工具箱那一行、`/edb drag` 同源）。
  local function ldBtnLabel()
    local on = false
    if type(EVAL_DF_ENABLED) == "function" then on = EVAL_DF_ENABLED() and true or false end
    return "框拖拽:" .. (on and "开" or "关")
  end
  local dragBtn = uiBtn(root, 88, 18, ldBtnLabel())
  dragBtn:SetPoint("TOPLEFT", root, "TOPLEFT", uiTopTake(88), -64) -- ★1.74.31 游标给 x（顶栏最后一枚）
  ui.dragBtn = dragBtn
  dragBtn:SetScript("OnClick", function()
    if type(EVAL_DF_TOGGLE) == "function" then
      pcall(EVAL_DF_TOGGLE)
    else
      P("框拖拽模块（tools\\DragFrames.lua）没载入：开关不可用 —— 检查 EvalHelp.toc")
    end
    if dragBtn.label then pcall(dragBtn.label.SetText, dragBtn.label, ldBtnLabel()) end
  end)
  ui.ldBtnLabel = ldBtnLabel
  ui.sfBtn = sfBtn
  sfBtn:SetScript("OnClick", function()
    local dd = sfEnsureDrop()
    if dd:IsShown() then
      ui.sfOpen = false
      dd:Hide()
    else
      ui.sfOpen = true
      dd.sync()
      -- 位置：贴按钮左下方（面板在屏幕右侧，往下展开不会出屏）
      pcall(dd.ClearAllPoints, dd)
      pcall(dd.SetPoint, dd, "TOPLEFT", sfBtn, "BOTTOMLEFT", 0, -2)
      dd:Show()
    end
    sfUpdateBtn()
  end)
  sfUpdateBtn()

  -- 列表行（事件过滤改成单按钮+下拉，不再占一整排 → 位置还原到 -88）
  for r = 1, ui.rows do
    local row = CreateFrame("Button", nil, root)
    row:SetWidth(W - 20) row:SetHeight(20)
    row:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -88 - (r - 1) * 21)
    if type(row.EnableMouse) == "function" then pcall(row.EnableMouse, row, true) end
    if type(row.RegisterForClicks) == "function" then pcall(row.RegisterForClicks, row, "LeftButtonUp") end
    local rbg = row:CreateTexture(nil, "BACKGROUND")
    rbg:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    rbg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    uiSolid(rbg, 0.10, 0.10, 0.10, 0.6)
    local mark = row:CreateTexture(nil, "OVERLAY")
    mark:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
    uiSolid(mark, 0.95, 0.80, 0.25, 1)
    mark:Hide()
    -- ★用户要求：行**最左加真选中框**（金边 + 暗内 + 金 mark 三件套，与工具箱同款）
    local rchk = CreateFrame("Button", nil, row)
    rchk:SetWidth(14) rchk:SetHeight(14)
    rchk:SetPoint("LEFT", row, "LEFT", 2, 0)
    if type(rchk.EnableMouse) == "function" then pcall(rchk.EnableMouse, rchk, true) end
    if type(rchk.RegisterForClicks) == "function" then pcall(rchk.RegisterForClicks, rchk, "LeftButtonUp") end
    local rcOuter = rchk:CreateTexture(nil, "BACKGROUND")
    rcOuter:SetPoint("TOPLEFT", rchk, "TOPLEFT", 0, 0)
    rcOuter:SetPoint("BOTTOMRIGHT", rchk, "BOTTOMRIGHT", 0, 0)
    uiSolid(rcOuter, 0.85, 0.70, 0.20, 1)
    local rcInner = rchk:CreateTexture(nil, "ARTWORK")
    rcInner:SetPoint("TOPLEFT", rchk, "TOPLEFT", 1, -1)
    rcInner:SetPoint("BOTTOMRIGHT", rchk, "BOTTOMRIGHT", -1, 1)
    uiSolid(rcInner, 0.10, 0.09, 0.06, 1)
    local rcMark = rchk:CreateTexture(nil, "OVERLAY")
    rcMark:SetPoint("TOPLEFT", rchk, "TOPLEFT", 3, -3)
    rcMark:SetPoint("BOTTOMRIGHT", rchk, "BOTTOMRIGHT", -3, 3)
    uiSolid(rcMark, 0.95, 0.80, 0.25, 1)
    rcMark:Hide()
    rchk:SetScript("OnClick", function()
      -- ★左侧多选框 = **唯一的多选入口**（勾选/取消互不影响；行本体点击是单选，见下方 row OnClick）。
      --   读 entry 走唯一入口 uiRowEntry（真机帧 rawget 会抛、type() 不可信，见该函数注释）。
      local e = uiRowEntry(row)
      if not e then return end
      ui.sel[e.path] = (not ui.sel[e.path]) and true or nil
      if uiRefresh then uiRefresh() end
    end)
    -- ★需求 4：行最左的**颜色色块**（有自定义设置才填充该层颜色）+ 同色四边描边
    local cblk = row:CreateTexture(nil, "OVERLAY")
    cblk:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -2)
    cblk:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 20, 2)
    cblk:SetWidth(7)
    uiSolid(cblk, 0.25, 0.25, 0.25, 0.9)
    local redges = {}
    for k = 1, 4 do
      local t = row:CreateTexture(nil, "OVERLAY")
      uiSolid(t, 1, 1, 1, 0.95)
      redges[k] = t
    end
    redges[1]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0) redges[1]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0) redges[1]:SetHeight(1)
    redges[2]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0) redges[2]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0) redges[2]:SetHeight(1)
    redges[3]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0) redges[3]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0) redges[3]:SetWidth(1)
    redges[4]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0) redges[4]:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0) redges[4]:SetWidth(1)
    for _, t in ipairs(redges) do t:Hide() end
    -- ★★★1.74.31 第二步：本行的**折叠开关**（▼ 展开中 / ▶ 已折叠；只有「有子层」的行才显示 —— 用户要求「父节点才显示」）。
    --   它是本行的**子按钮**：自带 EnableMouse ⇒ 点它**不会**触发行的选中（与左侧真选中框同款做法）；
    --   位置与显示/隐藏每次刷新由 uiRefresh 按层号设定（缩进 = (层号-1) * UI_TREE_STEP）。
    local tw = uiBtn(row, 12, 15, UI_TREE_OPEN)
    tw:SetPoint("LEFT", row, "LEFT", UI_TREE_X0, 0)
    tw:Hide()
    tw:SetScript("OnClick", function()
      -- 读 entry 走唯一入口 uiRowEntry（真机帧 rawget 会抛、type() 不可信，见该函数注释）。
      local e = uiRowEntry(row)
      if not e then return end
      uiTreeToggle(e)
    end)
    local txt = uiFont(row, 10, 0.9, 0.9, 0.9)
    pcall(txt.SetPoint, txt, "LEFT", row, "LEFT", UI_TREE_TX, 0) -- 默认（第 1 层）左起点；每次刷新按层号重设
    pcall(txt.SetWidth, txt, W - 92)
    pcall(txt.SetJustifyH, txt, "LEFT")
    row.mark, row.txt, row.cblk, row.redges, row.rchk, row.rcMark, row.tw = mark, txt, cblk, redges, rchk, rcMark, tw
    row:SetScript("OnClick", function()
      -- ★★1.74.34 用户要求：**点击层单元 = 单选这个层**（清掉其它所有选择；再点已单选的同一层 = 取消选择）。
      --   多选只走左侧多选框（rchk），行本体不再做勾选式累积。
      -- ★★1.74.34 真机实证（用户第二次截图）：本客户端点子按钮（折叠开关/多选框）会**连带触发**
      --   行本体的 OnClick（点 ▶ 的堆栈里出现的是行 OnClick）⇒ 焦点在子控件上时行不动作，
      --   交给子控件自己的 OnClick（否则点 ▶ 会顺带把选择清单清成单选）。
      if type(GetMouseFocus) == "function" then
        local okF, foc = pcall(GetMouseFocus)
        if okF and foc and (foc == tw or foc == rchk) then return end
      end
      -- 读 entry 走唯一入口 uiRowEntry（真机帧 rawget 会抛、type() 不可信，见该函数注释）。
      local e = uiRowEntry(row)
      if not e then return end
      local wasOnly = false
      if ui.sel[e.path] then
        local n = 0
        for _ in pairs(ui.sel) do n = n + 1 end
        wasOnly = (n == 1)
      end
      ui.sel = {}
      if not wasOnly then ui.sel[e.path] = true end
      if uiRefresh then uiRefresh() end
    end)
    -- 悬停提示：完整路径/类型/父级/可缩性（行内只放叶子名，全路径放这里）
    -- ★提示框偏好：本客户端地图上 GameTooltip 挂在画布子件下可能不渲染（UnrealQuest 实录）
    --   → 优先用 WorldMapTooltip，退回 GameTooltip。
    row:SetScript("OnEnter", function()
      local e = row.entry
      if not e then return end
      hlShowHover(e.f) -- ★悬停 = 在地图上红框标出这一层
      -- ★1.74.29 起改用**自绘信息面板**（见下方 uiTipShow）：不再依赖 GameTooltip/WorldMapTooltip
      -- ★★1.74.31 改名：本地行收集器原叫 `L`，与文件顶部的语言包函数 `L` **同名**（本项目明令避免这种
      --   同名短名助手：闸门按名字比对时会整名跳过 → 先用后声明这类错就漏网）→ 换成独有名字 rowTip。
      local rowTip = {}
      local function add(t, r, g2, b2) table.insert(rowTip, { t = t, r = r, g = g2, b = b2 }) end
      -- ★★★1.74.34-17 用户要求：「美化 tooltip」「信息适当归类，同类的放一起」
      --   结构 = 标题行 → 定位 → 外观 → 自定义（有才出）→ 脚本/事件 → 鼠标；同类同组、组间有分隔线；
      --   标签列由 uiPad 对齐（8 显示列），长列表由 uiListBrief 折叠并如实报剩余项数。
      local LBL = 9
      do
        -- 标题：叶子名 + 类型（路径放最后一行，太长时不挡视线）
        add("#" .. tostring(e.no or "?") .. "  " .. tostring(e.name or e.path) .. "   [" .. nodeType(e.f) .. "]", 1, 0.85, 0.3)

        add("定位", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
        add(uiPad("屏幕坐标", LBL) .. "X" .. (e.l and string.format("%.0f", e.l) or "?")
          .. "  Y" .. (e.b and string.format("%.0f", e.b) or "?") .. "   （左/下边缘，含缩放）", 0.88, 0.88, 0.88)
        if e.apt then
          add(uiPad("相对坐标", LBL) .. string.format("%s ← %s/%s （%.0f, %.0f）", tostring(e.apt),
            tostring(e.arel or "?"), tostring(e.arp or "?"), tonumber(e.ax) or 0, tonumber(e.ay) or 0), 0.88, 0.88, 0.88)
        else
          add(uiPad("相对坐标", LBL) .. "读不到（无 GetPoint 或未设锚点）", 0.7, 0.7, 0.7)
        end
        add(uiPad("父类", LBL) .. tostring(e.parent or "?"), 0.88, 0.88, 0.88)
        add(uiPad("层级", LBL) .. "第 " .. tostring(uiEntryDepth(e)) .. " 层", 0.80, 0.80, 0.80)

        add("外观", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
        local sz = (e.w and e.h) and string.format("%.0fx%.0f", e.w, e.h) or "?x?"
        add(uiPad("当前尺寸", LBL) .. sz, 0.92, 0.92, 0.92)
        do
          local ow, oh, src = uiOrigSizeOf(e.path, e)
          add(uiPad("原始尺寸", LBL) .. (tonumber(ow) and string.format("%.0f", ow) or "?") .. "x"
            .. (tonumber(oh) and string.format("%.0f", oh) or "?") .. "   （来源：" .. tostring(src) .. "）", 0.88, 0.88, 0.88)
        end
        add(uiPad("缩放/透明", LBL) .. "S" .. (e.scale and string.format("%.2f", e.scale) or "?")
          .. "  A" .. (e.alpha and string.format("%.2f", e.alpha) or "?"), 0.88, 0.88, 0.88)
        add(uiPad("显隐", LBL) .. (e.shown and "显示" or "隐藏"), 0.88, 0.88, 0.88)

        -- ★自定义参数（有记录才出这一组；颜色用该层的色板色）
        local c = ui.cust[e.path]
        if c then
          local r, g, b = uiColorFor(e.path)
          add("自定义", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
          add(uiPad("摘要", LBL) .. (uiCustSummary(e.path) or "自定义"), r, g, b)
          local s = c.set or {}
          local function pair2(label, cur, orig, fmt)
            local curS = cur and string.format(fmt, cur) or "?"
            local origS = orig and string.format(fmt, orig) or "?"
            return uiPad(label, LBL) .. curS .. "   （原始 " .. origS .. "）"
          end
          if s.scale then add(pair2("缩放", s.scale, c.oscale, "%.2f"), 0.85, 0.85, 0.85) end
          if s.alpha then add(pair2("透明", s.alpha, c.oalpha, "%.2f"), 0.85, 0.85, 0.85) end
          if s.w then add(pair2("宽", s.w, c.ow, "%.0f"), 0.85, 0.85, 0.85) end
          if s.h then add(pair2("高", s.h, c.oh, "%.0f"), 0.85, 0.85, 0.85) end
          if s.hidden ~= nil or c.oshown ~= nil then
            add(uiPad("显隐", LBL) .. (s.hidden == nil and "未改" or (s.hidden and "隐藏" or "显示"))
              .. "   （原始 " .. (c.oshown == nil and "?" or (c.oshown and "显示" or "隐藏")) .. "）", 0.85, 0.85, 0.85)
          end
          if s.dx or s.dy then
            add(uiPad("坐标偏移", LBL) .. string.format("%+.0f,%+.0f", s.dx or 0, s.dy or 0), 0.85, 0.85, 0.85)
          end
          add(uiPad("标记色", LBL) .. "色板第 " .. tostring(ui.colorOf[e.path] or "?") .. " 色（全库 "
            .. tostring(table.getn(HL_COLORS)) .. " 色）", r, g, b)
        else
          add("自定义", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
          add("无（应用任一设置后会记录，可用【清理自定义】还原）", 0.7, 0.7, 0.7)
        end

        -- ★脚本 / 事件（同类归一组；长列表折叠并如实报剩余项数）
        local rep = uiScriptReport(e.f)
        local has, hasnt, ev = rep.has or {}, rep.hasnt or {}, rep.ev or {}
        add("脚本与事件", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
        add(uiPad("已挂", LBL) .. uiListBrief(has, 8), 0.85, 0.95, 0.85)
        add(uiPad("未挂", LBL) .. uiListBrief(hasnt, 8), 0.62, 0.62, 0.62)
        add(uiPad("已注册事件", LBL) .. (table.getn(ev) > 0 and uiListBrief(ev, 6) or "（名单内未探测到）"), 0.85, 0.85, 0.95)

        add("鼠标", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
        add(uiPad("焦点/点击", LBL) .. "EnableMouse=" .. tostring(rep.mouse) .. "   滚轮=" .. tostring(rep.wheel)
          .. (type(uiField(e.f, "GetScript")) == "function" and "" or "   无 GetScript"), 0.80, 0.90, 0.80)

        add("路径", nil, nil, nil) rowTip[table.getn(rowTip)].head = true
        add(tostring(e.path), 0.75, 0.75, 0.75)
      end
      -- ★1.74.29：改走**自绘信息面板**（GameTooltip/WorldMapTooltip 在本面板宿主下均不出渲染）
      local shownOk = uiTipShow(row, rowTip)
      tipDbg("final(自绘)", shownOk)
      if not shownOk then P("自绘提示框也没显示出来（请把 /edb tiplog 结果发我）") end
    end)
    row:SetScript("OnLeave", function()
      hlHideHover() -- ★离开 = 撤掉红框
      uiTipHide()   -- ★自绘信息面板也收起
      local tip = _G["GameTooltip"]
      if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    end)
    ui.rowW[r] = row
  end

  -- 底部四行：①外观参数（含参数勾选）②坐标 ③应用族 ④筛选/滚动
  -- ★★排版单一来源（1.74.29 修「复选框压住标签」）：一组 = [勾选框][标签][-][值][+]，
  --   组距 GPITCH、组内偏移全部由下面常量算出 —— 不许在各处手写 x。
  local GX = { 8, 140, 272, 404 } -- 四个外观组的左起点（组距 132）
  local DCHK, DLBL, DMIN, DVAL, DPLUS = 0, 16, 52, 74, 108 -- 组内偏移（同一口径）
  local function groupX(i2) return GX[i2] or GX[1] end

  -- 参数勾选框（12×12；未勾选 = 应用外观时不碰该项）
  local function parChk(label, ox, y, key)
    local cb = CreateFrame("Button", nil, root)
    cb:SetWidth(12) cb:SetHeight(12)
    cb:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", ox + DCHK, y + 7)
    if type(cb.EnableMouse) == "function" then pcall(cb.EnableMouse, cb, true) end
    if type(cb.RegisterForClicks) == "function" then pcall(cb.RegisterForClicks, cb, "LeftButtonUp") end
    local o = cb:CreateTexture(nil, "BACKGROUND")
    o:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
    o:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
    uiSolid(o, 0.85, 0.70, 0.20, 1)
    local inn = cb:CreateTexture(nil, "ARTWORK")
    inn:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
    inn:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
    uiSolid(inn, 0.10, 0.09, 0.06, 1)
    local mk2 = cb:CreateTexture(nil, "OVERLAY")
    mk2:SetPoint("TOPLEFT", cb, "TOPLEFT", 2, -2)
    mk2:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -2, 2)
    uiSolid(mk2, 0.95, 0.80, 0.25, 1)
    local function sync()
      if ui.par[key] then pcall(mk2.Show, mk2) else pcall(mk2.Hide, mk2) end
    end
    cb:SetScript("OnClick", function()
      ui.par[key] = not ui.par[key]
      sync()
      uiSaveSettings() -- ★面板配置随改随存
      P("应用外观参数「" .. label .. "」= " .. (ui.par[key] and "勾选（会应用）" or "未勾选（不碰）"))
    end)
    sync()
    ui.parMarks = ui.parMarks or {}
    ui.parMarks[key] = mk2 -- ★供恢复设置时同步勾选外观
    return cb
  end

  -- 步进器（0.05 档=缩放/透明，10 档=坐标/宽高）；withChk = 是否在这组里画参数勾选框
  local function mkStepper(label, slot, y, key, step, minv, maxv, fmt, withChk)
    local ox = groupX(slot)
    if withChk then parChk(label, ox, y, key == "value" and "scale" or (key == "alphaValue" and "alpha" or (key == "wVal" and "w" or "h"))) end
    local lx = ox + (withChk and DLBL or 0)
    local lb = uiFont(root, 10, 0.85, 0.85, 0.85)
    pcall(lb.SetPoint, lb, "BOTTOMLEFT", root, "BOTTOMLEFT", lx, y + 5)
    pcall(lb.SetText, lb, label)
    local m = uiBtn(root, 20, 18, "-")
    m:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", ox + (withChk and DMIN or 40), y)
    local vl = uiFont(root, 11, 1, 0.95, 0.6)
    pcall(vl.SetPoint, vl, "BOTTOMLEFT", root, "BOTTOMLEFT", ox + (withChk and DVAL or 64), y + 5)
    local p = uiBtn(root, 20, 18, "+")
    p:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", ox + (withChk and DPLUS or 100), y)
    local function cur() return tonumber(ui[key]) or 0 end
    local function setv(v)
      if v < minv then v = minv end
      if v > maxv then v = maxv end
      ui[key] = math.floor(v * 100 + 0.5) / 100
      pcall(vl.SetText, vl, string.format(fmt, ui[key]))
      uiSaveSettings() -- ★数值改动随改随存
    end
    m:SetScript("OnClick", function() setv(cur() - step) end)
    p:SetScript("OnClick", function() setv(cur() + step) end)
    pcall(vl.SetText, vl, string.format(fmt, cur()))
    ui.lbls = ui.lbls or {}
    ui.lbls[key] = vl
    return vl
  end

  mkStepper("缩放", 1, 86, "value", 0.05, 0.05, 1.5, "%.2f", true)
  mkStepper("透明", 2, 86, "alphaValue", 0.05, 0.05, 1.5, "%.2f", true)
  mkStepper("宽度", 3, 86, "wVal", 10, 10, 3000, "%.0f", true)
  mkStepper("高度", 4, 86, "hVal", 10, 10, 3000, "%.0f", true)
  mkStepper("X", 1, 60, "xVal", 10, -800, 800, "%.0f", false)
  mkStepper("Y", 2, 60, "yVal", 10, -800, 800, "%.0f", false)

  local BW = 66
  local applyLook = uiBtn(root, BW, 18, "应用外观")
  applyLook:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 272, 60)
  applyLook:SetScript("OnClick", function() uiApplyAppearance() end)
  local applyPos = uiBtn(root, BW, 18, "应用坐标")
  applyPos:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 342, 60)
  applyPos:SetScript("OnClick", function() uiMoveSelected(ui.xVal or 0, ui.yVal or 0) end)
  local applyAll = uiBtn(root, BW, 18, "应用全部")
  applyAll:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 412, 60)
  applyAll:SetScript("OnClick", function() uiApplyAll() end)
  local resetPos = uiBtn(root, BW, 18, "还原坐标")
  resetPos:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 482, 60)
  resetPos:SetScript("OnClick", function() uiResetPos() end)

  -- 第三排：清理/重设 + 选择 + 筛选（仅显示中 / ≥500 从顶部搬到这排，顶部只留分类）
  local clearCust = uiBtn(root, 88, 18, "清理自定义")
  clearCust:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 8, 34)
  clearCust:SetScript("OnClick", function() uiClearCustom() end)
  local reapplyB = uiBtn(root, 88, 18, "重设自定义")
  reapplyB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 100, 34)
  reapplyB:SetScript("OnClick", function()
    local n = uiCustReapply(false)
    local cnt = 0
    for _ in pairs(ui.cust or {}) do cnt = cnt + 1 end
    P("手动重设：重设 " .. n .. " 项（存档里共 " .. cnt .. " 层有自定义）")
  end)
  local allA = uiBtn(root, 70, 18, "全选结果")
  allA:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 192, 34)
  allA:SetScript("OnClick", function()
    for _, e in ipairs(uiFiltered()) do ui.sel[e.path] = true end
    if uiRefresh then uiRefresh() end
  end)
  local clr = uiBtn(root, 70, 18, "清空选择")
  clr:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 266, 34)
  clr:SetScript("OnClick", function()
    ui.sel = {}
    if uiRefresh then uiRefresh() end
  end)
  -- ★★★1.74.34-14 用户要求：「隐藏层调整可见性 → 下拉多选支持 → 不可见 / 可见」。
  --   原来那颗「仅显示中:开/关」二值开关换成**可见性多选下拉**（两个都选 / 都不选 = 不过滤）。
  --   沿用本面板已验证的下拉范式（扫描源/事件过滤同款：点按钮弹、点行只切选不关、另有清空/关闭）。
  local function visLabelText()
    local v = ui.vis or {}
    local n = 0
    if v.shown then n = n + 1 end
    if v.hidden then n = n + 1 end
    if n == 0 then return "可见性:不限 ▾" end
    if n == 2 then return "可见性:全部 ▾" end
    return (v.shown and "可见性:可见 ▾" or "可见性:不可见 ▾")
  end
  local visBtn = uiBtn(root, 88, 18, visLabelText())
  ui.visBtn = visBtn
  -- ★★★1.74.34-23：位置从「底部第三排」搬到**顶栏过滤那一排**（槽位由上面 VIS_TOP_X 预留）。
  --   同一排从左到右：分类(全部) → 只显示有名 → **可见性** → 扫描源 → 事件过滤 → 框拖拽（右端 514 < 560）。
  visBtn:SetPoint("TOPLEFT", root, "TOPLEFT", VIS_TOP_X, -64)
  -- 悬停说明（与「只显示有名」同款自绘信息面板；本面板宿主下 GameTooltip 不渲染）
  visBtn:SetScript("OnEnter", function()
    uiTipShow(visBtn, {
      { t = "可见性过滤（多选）：可见 / 不可见 / 两个都选 = 不过滤 / 都不选 = 不过滤", r = 0.95, g = 0.85, b = 0.35 },
      { t = "★勾上「不可见」可把被隐藏的层调出来；有子元素时父级按树保留、直到目标顶级", r = 0.80, g = 0.80, b = 0.80 },
    })
  end)
  visBtn:SetScript("OnLeave", function() uiTipHide() end)
  local function visEnsureDrop()
    if ui.visDrop then return ui.visDrop end
    local dd = CreateFrame("Frame", "EH_DB_VISDROP", uiHost())
    dd:SetWidth(150) dd:SetHeight(24 * 2 + 20 + 44)
    pcall(dd.SetFrameStrata, dd, "FULLSCREEN_DIALOG")
    pcall(dd.SetFrameLevel, dd, 800)
    if type(dd.EnableMouse) == "function" then pcall(dd.EnableMouse, dd, true) end
    local bg = dd:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
    uiSolid(bg, 0.03, 0.03, 0.03, 0.96)
    local edge = dd:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", dd, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 1, -1)
    uiSolid(edge, 0.85, 0.70, 0.20, 1)
    dd.rows = {}
    local VOPTS = {
      { k = "shown", label = "可见" },
      { k = "hidden", label = "不可见" },
    }
    local y = -5
    for _, op in ipairs(VOPTS) do
      local rb = CreateFrame("Button", nil, dd)
      rb:SetWidth(140) rb:SetHeight(22)
      rb:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y)
      if type(rb.EnableMouse) == "function" then pcall(rb.EnableMouse, rb, true) end
      if type(rb.RegisterForClicks) == "function" then pcall(rb.RegisterForClicks, rb, "LeftButtonUp") end
      local mk = rb:CreateTexture(nil, "BACKGROUND")
      mk:SetPoint("LEFT", rb, "LEFT", 2, 0)
      mk:SetWidth(13) mk:SetHeight(13)
      uiSolid(mk, 0.10, 0.09, 0.06, 1)
      local tick = rb:CreateTexture(nil, "OVERLAY")
      tick:SetPoint("LEFT", rb, "LEFT", 4, 0)
      tick:SetWidth(9) tick:SetHeight(9)
      uiSolid(tick, 0.95, 0.80, 0.25, 1)
      tick:Hide()
      local tx = rb:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(tx.SetFontObject, tx, GameFontNormal) end
      pcall(tx.SetPoint, tx, "LEFT", rb, "LEFT", 20, 0)
      pcall(tx.SetJustifyH, tx, "LEFT")
      pcall(tx.SetText, tx, op.label)
      rb.tick, rb.key = tick, op.k
      rb:SetScript("OnClick", function()
        ui.vis = ui.vis or {}
        ui.vis[op.k] = (not ui.vis[op.k]) and true or nil
        -- ★两个都选 = 等价于不过滤，但**保留**两个勾（用户看得见自己选了什么）
        pcall(visBtn.label.SetText, visBtn.label, visLabelText())
        dd.sync()
        uiSaveSettings()
        ui.off = 0
        if uiRefresh then uiRefresh() end
      end)
      dd.rows[table.getn(dd.rows) + 1] = rb
      y = y - 24
    end
    local function mkVisAction(txt, y2, fn)
      local ab = CreateFrame("Button", nil, dd)
      ab:SetWidth(140) ab:SetHeight(20)
      ab:SetPoint("TOPLEFT", dd, "TOPLEFT", 5, y2)
      if type(ab.EnableMouse) == "function" then pcall(ab.EnableMouse, ab, true) end
      if type(ab.RegisterForClicks) == "function" then pcall(ab.RegisterForClicks, ab, "LeftButtonUp") end
      local fs2 = ab:CreateFontString(nil, "OVERLAY")
      if type(GameFontNormal) ~= "nil" then pcall(fs2.SetFontObject, fs2, GameFontNormal) end
      pcall(fs2.SetPoint, fs2, "CENTER", ab, "CENTER", 0, 0)
      pcall(fs2.SetText, fs2, txt)
      pcall(fs2.SetTextColor, fs2, 0.95, 0.82, 0.35)
      ab:SetScript("OnClick", fn)
      return ab
    end
    mkVisAction("不筛选（两个都不选）", y, function()
      ui.vis = {}
      pcall(visBtn.label.SetText, visBtn.label, visLabelText())
      dd.sync()
      uiSaveSettings()
      ui.off = 0
      if uiRefresh then uiRefresh() end
    end)
    mkVisAction("关闭", y - 22, function()
      ui.visOpen = false
      dd:Hide()
    end)
    dd.sync = function()
      local v = ui.vis or {}
      for _, rb in ipairs(dd.rows) do
        if v[rb.key] then pcall(rb.tick.Show, rb.tick) else pcall(rb.tick.Hide, rb.tick) end
      end
      pcall(visBtn.label.SetText, visBtn.label, visLabelText())
    end
    dd:Hide()
    ui.visDrop = dd
    return dd
  end
  visBtn:SetScript("OnClick", function()
    local dd = visEnsureDrop()
    if dd:IsShown() then
      ui.visOpen = false
      dd:Hide()
    else
      ui.visOpen = true
      dd.sync()
      pcall(dd.ClearAllPoints, dd)
      pcall(dd.SetPoint, dd, "TOPLEFT", visBtn, "BOTTOMLEFT", 0, -2) -- 贴按钮下方展开
      dd:Show()
    end
  end)
  local bigB2 = uiBtn(root, 88, 18, "≥500:开")
  ui.bigBtn = bigB2
  -- ★1.74.34-23：可见性搬去顶栏后，这排空出的槽（340）由「≥500」补上 ⇒ 不留空洞
  bigB2:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 340, 34)
  bigB2:SetScript("OnClick", function()
    ui.bigOnly = not ui.bigOnly
    pcall(bigB2.label.SetText, bigB2.label, "≥500:" .. (ui.bigOnly and "开" or "关"))
    uiSaveSettings()
    ui.off = 0
    if uiRefresh then uiRefresh() end
  end)

  -- 第四排：工具（扫描=全量重枚举；重扫已并入扫描，去掉重复入口）
  local scanB = uiBtn(root, 60, 18, "扫描")
  scanB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 8, 8)
  scanB:SetScript("OnClick", function() uiScanAll() end)

  -- ★1.74.34-12 用户要求：图层属性加隐藏/显示（对选中层生效；记进自定义、可还原）
  local hideB = uiBtn(root, 54, 18, "隐藏")
  hideB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 156, 8)
  hideB:SetScript("OnClick", function() uiApplyVisibilityToSelected(true) end)
  local showB = uiBtn(root, 54, 18, "显示")
  showB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 214, 8)
  showB:SetScript("OnClick", function() uiApplyVisibilityToSelected(false) end)

  -- ★用户要求：列表滚动（滚轮 + 上下按钮）
  -- ★★1.74.34 修（用户截图：「1-2/…」计数与 ▲▼ 叠在一起）：计数改为**右对齐**且右边缘收在 ▲ 左侧
  --   （414+70=484 < ▲ 的 490），字数再多也只往左长、不再压按钮。
  ui.scrollLbl = uiFont(root, 10, 0.8, 0.8, 0.8)
  pcall(ui.scrollLbl.SetPoint, ui.scrollLbl, "BOTTOMLEFT", root, "BOTTOMLEFT", 414, 12)
  pcall(ui.scrollLbl.SetWidth, ui.scrollLbl, 70)
  pcall(ui.scrollLbl.SetJustifyH, ui.scrollLbl, "RIGHT")
  local upB = uiBtn(root, 26, 18, "▲")
  upB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 490, 8)
  upB:SetScript("OnClick", function()
    ui.off = math.max(0, (ui.off or 0) - 3)
    if uiRefresh then uiRefresh() end
  end)
  local dnB = uiBtn(root, 26, 18, "▼")
  dnB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 520, 8)
  dnB:SetScript("OnClick", function()
    ui.off = (ui.off or 0) + 3
    if uiRefresh then uiRefresh() end
  end)

  -- ★滚轮滚动（方向单一来源：上滚 = 序号减小；幅度固定 3 行；越界在 uiRefresh 里夹取）
  if type(root.EnableMouseWheel) == "function" then pcall(root.EnableMouseWheel, root, true) end
  pcall(root.SetScript, root, "OnMouseWheel", function()
    local d = tonumber(arg1) or 0
    if d == 0 then return end
    local dir = (d > 0) and -1 or 1
    ui.off = math.max(0, (ui.off or 0) + dir * 3)
    if uiRefresh then uiRefresh() end
  end)

  uiRefresh = function()
    scriptCache = {} -- ★脚本判定缓存按刷新失效（帧可能新增/移除脚本）
    uiScanState() -- ★实时扫描：每次刷新都重读「显示中 / 当前 scale / 当前 alpha」
    local list = uiFiltered()
    local per = ui.rows
    local total = table.getn(list)
    local maxOff = math.max(0, total - per)
    if (ui.off or 0) > maxOff then ui.off = maxOff end
    if (ui.off or 0) < 0 then ui.off = 0 end
    local nSel = 0
    for _ in pairs(ui.sel) do nSel = nSel + 1 end
    for r = 1, ui.rows do
      local row = ui.rowW[r]
      local e = list[(ui.off or 0) + r]
      row.entry = e
      if e then
        -- ★★★1.74.31 第二步：**树的缩进 + 折叠开关**（缩进按扫描层号，与「层深」同一个 uiEntryDepth）
        --   · 折叠开关只在「这一支里真有能显示的子层」（e.visKid，由 uiFiltered 记账）、**或**「本节点已折叠」、
        --     **或**「层深上限正好卡住它的子层」时画 —— 后两种必须照旧画 ▶，否则收起来/被上限挡住之后就再也展不开了；
        --   · 叶子层一律不画（用户要求「父节点才显示」）。
        local drow = uiEntryDepth(e)
        local ind = (drow - 1) * UI_TREE_STEP
        if ind < 0 then ind = 0 end
        local cap = tonumber(ui.depthMax) or 0
        -- 「层深」上限正好卡住这一层的子层 ⇒ 视觉上也是**收起**的（点它就是往下钻一层：把上限抬高）
        local capBlocks = (cap > 0) and (cap <= drow)
        local shut = ((ui.treeCollapsed and ui.treeCollapsed[e.path]) and true or false) or capBlocks
        if row.tw then
          if ((e.kids or 0) > 0) and (shut or e.visKid) then
            if row.tw.label then
              pcall(row.tw.label.SetText, row.tw.label, shut and UI_TREE_SHUT or UI_TREE_OPEN)
            end
            pcall(row.tw.ClearAllPoints, row.tw)
            pcall(row.tw.SetPoint, row.tw, "LEFT", row, "LEFT", UI_TREE_X0 + ind, 0)
            pcall(row.tw.Show, row.tw)
          else
            pcall(row.tw.Hide, row.tw)
          end
        end
        pcall(row.txt.ClearAllPoints, row.txt)
        pcall(row.txt.SetPoint, row.txt, "LEFT", row, "LEFT", UI_TREE_TX + ind, 0)
        pcall(row.txt.SetWidth, row.txt, W - 92 - ind) -- 缩进吃掉宽度 ⇒ 右边缘恒定（不论多深都不越出行的右边界）
        local tag = e.shown and "[显示]" or "[隐藏]" -- ★1.74.34-13：这一格改作**可见性**（原「不可缩」标记已按用户要求删除）
        local sz = (e.w and e.h) and string.format("%.0fx%.0f", e.w, e.h) or "?x?"
        -- ★1.74.34-10 用户要求：行内展示 **X/Y 坐标**（X=左边缘 · Y=下边缘，绝对屏幕坐标，含缩放——
        --   与主插件 DF 的 X/Y 约定同口径；读不到如实显 "?"）
        local xy = " X" .. (e.l and string.format("%.0f", e.l) or "?") .. ",Y" .. (e.b and string.format("%.0f", e.b) or "?")
        -- ★1.74.34-15：相对坐标（锚点偏移）+ 原始尺寸（与当前不同时才显示，避免每行都拖长）
        local anc = ""
        if e.ax or e.ay then anc = string.format(" 锚%.0f,%.0f", e.ax or 0, e.ay or 0) end
        local ow, oh = uiOrigSizeOf(e.path, e)
        local orig = ""
        if tonumber(ow) and tonumber(oh) and e.w and e.h
          and (math.abs(ow - e.w) > 1 or math.abs(oh - e.h) > 1) then
          orig = string.format(" 原%.0fx%.0f", ow, oh)
        end
        local vals = ""
        if e.scale then vals = vals .. string.format(" S%.2f", e.scale) end
        if e.alpha then vals = vals .. string.format(" A%.2f", e.alpha) end
        -- ★层名称 + 实际尺寸 + 父类层名称（用户要求）；有自定义的再带彩色摘要
        local custTxt = ""
        if ui.cust[e.path] then
          custTxt = "  {" .. (uiCustSummary(e.path) or "自定义") .. "}"
        end
        pcall(row.txt.SetText, row.txt,
          string.format("#%s %s %s  %s%s%s%s%s%s", tostring(e.no or "?"), tag, tostring(e.name or e.path), sz,
            xy, anc, orig, vals, custTxt)) -- ★1.74.34-16 用户要求：行内**不再显示「父=…」**（树结构已表达父子关系；完整父类信息仍在悬停 tooltip）
        if ui.sel[e.path] then row.mark:Show() else row.mark:Hide() end
        if row.rcMark then
          if ui.sel[e.path] then pcall(row.rcMark.Show, row.rcMark) else pcall(row.rcMark.Hide, row.rcMark) end
        end
        -- ★需求 4：有自定义 → 左色块填充该层颜色 + 整行同色边框
        local isCust = ui.cust[e.path] and true or false
        if isCust then
          local r, g, b = uiColorFor(e.path)
          pcall(row.cblk.SetVertexColor, row.cblk, r, g, b, 1)
          for _, t in ipairs(row.redges) do
            pcall(t.SetVertexColor, t, r, g, b, 0.95)
            t:Show()
          end
        else
          pcall(row.cblk.SetVertexColor, row.cblk, 0.25, 0.25, 0.25, 0.9)
          for _, t in ipairs(row.redges) do t:Hide() end
        end
        row:Show()
      else
        row:Hide()
      end
    end
    -- ★选中项在地图上描金边（列表 ↔ 地图 联动）+ ★需求 3：自定义层的地图标记（彩色边框+左上角信息）
    local nHl = hlApplySelected()
    -- ★★★1.74.30 拖拽柄在工具模块里（EVAL_DF_REFRESH，开关开时才生效）
    local nDrag = 0
    if type(EVAL_DF_REFRESH) == "function" then nDrag = EVAL_DF_REFRESH() or 0 end
    local nMk = uiMarksRefresh(ui.entries)
    -- ★状态行补「扫描维度」：让人一眼看出数据来源与过滤量（之前只显示结果数，用户以为层变少了）
    local nAll = table.getn(ui.entries or {})
    local nShown = 0
    for _, e in ipairs(ui.entries or {}) do if e.shown then nShown = nShown + 1 end end
    local mapOpen = false
    local mv = _G["WorldMapButton"]
    if (type(mv) == "table" or type(mv) == "userdata") and type(mv.IsShown) == "function" then
      local ok, v = pcall(mv.IsShown, mv)
      mapOpen = (ok and v) and true or false
    end
    local flt = {}
    -- ★1.74.34-14：可见性筛选按**多选真值**如实写（可见 / 不可见 / 全部=不过滤 / 未选=不过滤）
    local vv = ui.vis
    if type(vv) == "table" then
      local sv, hv = vv.shown == true, vv.hidden == true
      if sv and hv then table.insert(flt, "可见性:全部")
      elseif sv then table.insert(flt, "可见性:可见")
      elseif hv then table.insert(flt, "可见性:不可见")
      else table.insert(flt, "可见性:不限") end
    else
      table.insert(flt, "可见性:不限")
    end
    -- ★树结构保持（用户要求）：有子元素命中时父级一路保留 ⇒ 状态行写明「父级按树保留」
    if (type(vv) == "table") and ((vv.shown and not vv.hidden) or (vv.hidden and not vv.shown)) then
      table.insert(flt, "父级按树保留")
    end
    if ui.bigOnly then table.insert(flt, "≥500") end
    if ui.hideUnnamed then table.insert(flt, "隐藏无名") end -- ★1.74.31：无名层过滤（默认开）
    -- ★★★1.74.31 第二步：**层深也要显示在状态行**（它是「层变少」最主要的原因，之前不在 flt 里 ⇒ 看着像数据丢了）
    local dcap = tonumber(ui.depthMax) or 0
    if dcap > 0 then table.insert(flt, "层深:" .. dcap) end
    -- ★★★1.74.31 第二步：树上收起来的节点数（让「列表变短」在界面上看得见；顺带说明「有 ▾ 的行才是父节点」）
    local nFold = uiTreeCollapsedCount()
    if nFold > 0 then table.insert(flt, "树折叠:" .. nFold) end
    -- ★分类显示**名字**而不是数字（旧代码显示「分类4」这种内部码，看不出是什么；已删分类也照新表归一到全部）
    local catDef = uiCatDef(ui.cat)
    if catDef.code ~= 0 then table.insert(flt, "分类:" .. catDef.label) end
    if ui.filter ~= "" then table.insert(flt, "文字:" .. ui.filter) end
    -- ★★状态行（现在**真的画出来了**，见 uiBuild 里那两个控件的说明）：
    --   ① 计数 + 地图状态（+ 描边/自定义数）② 当前过滤条件 —— 「列表为什么变少」必须看得见。
    if ui.statLbl then
      pcall(ui.statLbl.SetText, ui.statLbl, string.format("结果 %d · 选中 %d · %s", total, nSel,
        mapOpen and "地图已开" or "地图未开")
        .. (nHl > 0 and (" · 描边 " .. nHl) or "") .. (nMk > 0 and (" · 自定义 " .. nMk) or ""))
    end
    if ui.filterLbl then
      pcall(ui.filterLbl.SetText, ui.filterLbl, (#flt > 0) and ("过滤：" .. table.concat(flt, " · ")) or "过滤：无")
      -- ★「可见性只筛可见 + 地图未开」= 树内几乎全是隐藏层，提示用户（这是「数据变少」的常见错觉来源）
      if uiVisOnlyShown() and not mapOpen then
        pcall(ui.filterLbl.SetTextColor, ui.filterLbl, 0.95, 0.75, 0.30)
      else
        pcall(ui.filterLbl.SetTextColor, ui.filterLbl, 0.80, 0.80, 0.80)
      end
    end
    if ui.scrollLbl then
      pcall(ui.scrollLbl.SetText, ui.scrollLbl,
        string.format("%d-%d/%d", (ui.off or 0) + 1, math.min(total, (ui.off or 0) + per), total))
    end
    if ui.echo then
      pcall(ui.echo.SetText, ui.echo, "过滤：" .. (ui.filter ~= "" and ui.filter or "（不填=全部）") .. " · 滚轮翻动列表")
    end
  end

  -- ★用户要求：恢复上次的层配置信息（数值/勾选/筛选/位置）
  local had = uiLoadSettings()
  if had then
    -- 数值标签
    if ui.lbls then
      for key, vl in pairs(ui.lbls) do
        local v = ui[key]
        if type(v) == "number" then
          local fmt = (key == "value" or key == "alphaValue") and "%.2f" or "%.0f"
          pcall(vl.SetText, vl, string.format(fmt, v))
        end
      end
    end
    -- 参数勾选 mark
    if ui.parMarks then
      for key, mk in pairs(ui.parMarks) do
        if ui.par[key] then pcall(mk.Show, mk) else pcall(mk.Hide, mk) end
      end
    end
    -- 开关按钮文案
    -- ★1.74.34-14：可见性按钮文案按存档真值重写（两个都选/都不选/单选 三态都由 visLabelText 现算）
    if ui.visBtn and type(visLabelText) == "function" then pcall(ui.visBtn.label.SetText, ui.visBtn.label, visLabelText()) end
    if ui.bigBtn then pcall(ui.bigBtn.label.SetText, ui.bigBtn.label, "≥500:" .. (ui.bigOnly and "开" or "关")) end
    -- ★1.74.31 无名层开关的文案也按**存档读回来的值**重写（不能写死「开」）
    if ui.namedBtn and ui.namedLabel then pcall(ui.namedBtn.label.SetText, ui.namedBtn.label, ui.namedLabel()) end
    -- ★★★1.74.31 第二步：**层深文案也要按存档值重写** —— uiLoadSettings 在本函数之后才跑，
    --   建按钮那一刻的文案是按「当时的 ui.depthMax」写的 ⇒ 不重写就会出现「存档里是层深:2、按钮写着层深:1」。
    if ui.depthSync then pcall(ui.depthSync) end
    -- 过滤框文本
    if ui.eb and ui.filter ~= "" then pcall(ui.eb.SetText, ui.eb, ui.filter) end
    -- 面板位置（并做越界回归：读真实矩形，出屏就回默认锚点）
    if ui.savedPx and ui.savedPy then
      pcall(root.ClearAllPoints, root)
      pcall(root.SetPoint, root, "TOPLEFT", uiHost(), "TOPLEFT", ui.savedPx, ui.savedPy)
      local okl, l = pcall(root.GetLeft, root)
      local okt, t = pcall(root.GetTop, root)
      local sw = (type(GetScreenWidth) == "function") and GetScreenWidth() or 1024
      local sh = (type(GetScreenHeight) == "function") and GetScreenHeight() or 768
      if not (okl and okt and tonumber(l) and tonumber(t) and l >= -20 and t <= sh + 20 and l <= sw - 40 and t >= 40) then
        pcall(root.ClearAllPoints, root)
        pcall(root.SetPoint, root, "TOPRIGHT", uiHost(), "TOPRIGHT", -10, -10)
        P("上次的面板位置超出屏幕，已回到默认位置")
      end
    end
    P("已恢复上次的层配置（缩放 " .. string.format("%.2f", ui.value) .. " · 透明 " .. string.format("%.2f", ui.alphaValue)
      .. " · 宽 " .. string.format("%.0f", ui.wVal) .. " · 高 " .. string.format("%.0f", ui.hVal) .. "）")
  end
  ui.root = root
  ui.built = true
  root:Hide()
  return true
end

-- ★补救命令用的：把所有「已自定义」层的颜色重新铺开（修历史存档里撞色的数据）
function uiRecolorAll()
  local paths = {}
  for path in pairs(ui.cust or {}) do table.insert(paths, path) end
  table.sort(paths) -- 稳定顺序，便于复现
  for _, p in ipairs(paths) do ui.colorOf[p] = nil end
  ui.colorSeq = 0
  for _, p in ipairs(paths) do uiColorFor(p) end
  uiCustSave()
  if type(uiMarksRefresh) == "function" then uiMarksRefresh(ui.entries) end
  if uiRefresh then uiRefresh() end
  P("颜色已重排：" .. table.getn(paths) .. " 个自定义层各分到不同颜色（色库 " .. table.getn(HL_COLORS) .. " 色）")
  return table.getn(paths)
end

-- ★需求 5：自定义设置**账号级存档**（SavedVariables）+ 定时器兜底重设
local function uiToggle()
  if not uiBuild() then
    P("面板建不起来（WorldMapFrame 不可用）")
    return
  end
  if ui.root:IsShown() then
    ui.root:Hide()
  else
    ui.off = 0
    uiRefresh()
    ui.root:Show()
    P("图层调试面板已打开（一个不落扫描：多根树 + 全 _G 游离帧 + 顶层点名；可设缩放/透明/宽高/坐标）")
  end
end

-- ★★1.74.29 用户要求：**删除大地图右侧的「层」入口按钮**（连同它的创建 tick）。
--   面板现在只从两处打开：① 命令 `/edb ui`；② EvalHelp 配置窗「子插件」Tab → 图层调试行 → [打开面板]。
--   （原实现见 git 历史：uiEnsureEntry + EH_DB_UIENTRY tick，anchored WorldMapFrame TOPRIGHT）

-- ===== 事件/脚本过滤的自动心跳刷新（1.74.29）=====
-- 用户问「后期注册的会不会扫不到」：脚本与事件都是**实时查询**（每次刷新都清 scriptCache），
--   所以后期注册的**下一次刷新**就能反映 —— 这里让「面板开着 + 事件过滤有选中」时每 2 秒自动刷一次，
--   不必手动点扫描；限频 2s、无过滤时不跑，开销可忽略。
do
  if type(CreateFrame) == "function" then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    local tf = CreateFrame("Frame", "EH_DB_SFTICK", parent)
    local acc = 0
    tf:SetScript("OnUpdate", function()
      acc = acc + (tonumber(arg1) or 0.05)
      if acc < 2.0 then return end
      acc = 0
      local shown = false
      if ui.root and type(ui.root.IsShown) == "function" then
        local ok, v = pcall(ui.root.IsShown, ui.root)
        shown = (ok and v) and true or false
      end
      if shown and (type(uiScriptFilterCount) == "function") and uiScriptFilterCount() > 0 then
        scriptCache = {}
        if uiRefresh then pcall(uiRefresh) end
      end
    end)
  end
end

-- ===== 需求 5：账号级自定义设置的载入 + 定时器兜底重设 =====
-- ★★1.74.29 用户要求：**删除「定时重设」机制** ——
--   原来挂了一个 EH_DB_REAPPLY 定时器（每 2 秒扫一遍存档、把被客户端冲掉的参数写回去）。
--   现在**不再有任何自动重设**：载入时只把存档读进内存，之后仅在用户**主动**点按钮时才写：
--     · 面板里的「应用外观 / 应用坐标 / 应用全部」= 主动应用
--     · 面板里的「重设自定义」= 主动重设（走同一个 uiCustReapply）
--     · 「清理自定义 / 还原坐标」= 主动复位
--   ⇒ 好处：不会有周期性写入，也不会有任何由此引起的"跳一下"；代价：客户端若把你的改动冲掉，
--     需要你自己点一次「重设自定义」（这就是这次取舍的全部影响，如实记录）。
-- ★★★1.74.29 用户要求：「层拖拽后的位置记入用户配置，每次启动自动设置生效」
--   · 记录：拖拽结束时 markDragEnd 已把偏移写进 EH_DEBUGBOX_CFG.cust[路径].set.dx/dy（帐号级）✓
--   · 生效：这里做**有界重试**（最多 6 次、每 2 秒一次，全部解析到就停）——
--     因为地图层是**惰加载**的，刚进世界时路径多半解析不到，跑一次就放弃会「看起来没生效」。
local AUTOAPPLY_MAX, AUTOAPPLY_GAP = 6, 2.0
local autoApply = { on = false, tries = 0, lastN = 0, lastMiss = 0, frame = nil }

function uiCustAutoApplyTick()
  if not autoApply.on then return true end
  autoApply.tries = autoApply.tries + 1
  local n, miss = uiCustReapply(true)
  autoApply.lastN, autoApply.lastMiss = n or 0, miss or 0
  local total = 0
  for _ in pairs(ui.cust or {}) do total = total + 1 end
  if total == 0 then
    autoApply.on = false
    return true -- 没有自定义记录 → 不必重试（也不打扰）
  end
  if (miss or 0) == 0 then
    autoApply.on = false
    P("启动自动生效完成：已重设 " .. tostring(n) .. " 项（第 " .. tostring(autoApply.tries) .. " 次共 " .. tostring(total) .. " 条自定义）")
    return true
  end
  if autoApply.tries >= AUTOAPPLY_MAX then
    autoApply.on = false
    P("启动自动生效结束：已重设 " .. tostring(n) .. " 项；仍有 " .. tostring(miss)
      .. " 条解析不到（图层/无名节点，全部尝试 " .. tostring(AUTOAPPLY_MAX) .. " 次后停手）")
    return true
  end
  return false -- 继续重试
end

function uiCustAutoApplyBegin(why)
  autoApply.on = true
  autoApply.tries = 0
  if not autoApply.frame then
    autoApply.frame = CreateFrame("Frame", "EH_DB_AUTOAPPLY", uiHost())
  end
  local acc = 0
  autoApply.frame:SetScript("OnUpdate", function()
    if not autoApply.on then pcall(autoApply.frame.SetScript, autoApply.frame, "OnUpdate", nil) return end
    acc = acc + (tonumber(arg1) or 0.05)
    if acc < AUTOAPPLY_GAP then return end
    acc = 0
    if uiCustAutoApplyTick() then pcall(autoApply.frame.SetScript, autoApply.frame, "OnUpdate", nil) end
  end)
  -- 立即试一次（当帧就能生效的部分先生效）
  if uiCustAutoApplyTick() then pcall(autoApply.frame.SetScript, autoApply.frame, "OnUpdate", nil) end
  if type(EVAL_LOGLINE) == "function" then EVAL_LOGLINE("[DBX] 启动自动生效开始（" .. tostring(why or "?") .. "）") end
  return true
end

-- 事件帧：进世界后自动生效（本插件原本没有事件帧，这里新增一个**只做这一件事**的）
do
  if type(CreateFrame) == "function" then
    local ef = CreateFrame("Frame", "EH_DB_AUTOAPPLY_EV", uiHost())
    if type(ef.RegisterEvent) == "function" then
      pcall(ef.RegisterEvent, ef, "PLAYER_ENTERING_WORLD")
      pcall(ef.RegisterEvent, ef, "VARIABLES_LOADED")
      ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" or event == "VARIABLES_LOADED" then
          -- ★★此刻 SavedVariables 已就位 → 再读一次（文件期读不到的记录在这里补上）
          if not ui.custLoaded then
            local n2 = uiCustLoad()
            P("自定义设置：事件期补读存档 " .. tostring(n2) .. " 条") 
          end
          -- ★1.74.35-4：地图叠加层自动适配的 ticker **已整块删除**（搬到工具箱→缩放大地图，见 1565 行区段的说明）
          uiCustAutoApplyBegin(tostring(event))
        end
      end)
    end
  end
end
do
  -- ★文件期试读一次（本客户端多半还没就位）——**读不到就什么都不做**；真正的读取靠下面的重试：
  --   每 1 秒试一次（最多 20 次），读到就停并**立即自动生效** —— 正是用户说的「过一段时间再读、然后再设属性」
  local n, ok = uiCustLoad()
  if ok then
    P("自定义设置存档：载入 " .. n .. " 条")
  else
    P("自定义设置：存档尚未就位（本次不读不写）——就位后自动读取")
  end
  if type(CreateFrame) == "function" then
    local rf = CreateFrame("Frame", "EH_DB_SVRETRY", uiHost())
    local acc, tries = 0, 0
    rf:SetScript("OnUpdate", function()
      if ui.custLoaded then pcall(rf.SetScript, rf, "OnUpdate", nil) return end
      acc = acc + (tonumber(arg1) or 0.05)
      if acc < 1.0 then return end
      acc = 0
      tries = tries + 1
      local n2, ok2 = uiCustLoad()
      if ok2 then
        P("自定义设置：就位后读到 " .. n2 .. " 条（第 " .. tostring(tries) .. " 次重试）→ 立即自动生效")
        uiCustAutoApplyBegin("就位重试")
        pcall(rf.SetScript, rf, "OnUpdate", nil)
      elseif tries >= 20 then
        P("自定义设置：重试 20 次仍未就位（期间一律未写入，不会抹数据）")
        pcall(rf.SetScript, rf, "OnUpdate", nil)
      end
    end)
  end
end


-- 高亮框的实现在下方（★必须在 ui 段之前声明：uiRefresh 的闭包要捕获 hlApplySelected，
--   Lua 的 local 从声明之后才生效 —— 之前插在 ui 段之后就炸了 `call global 'hlApplySelected'`）

-- ===== /edb mouse：鼠标开关点名（谁 EnableMouse 着 = 谁可能抢走悬停/点击） =====
-- ★判据来源：本项目已实测「Frame 不吃鼠标事件就收不到」，反过来说
--   「谁 EnableMouse=true 谁就在命中链上」。IsMouseEnabled 是本客户端官方索引里的 widget 方法。
local MOUSE_CAND = {
  "WorldMapFrame", "WorldMapDetailFrame", "WorldMapButton", "WorldMapPositioningGuide",
  "WorldMapFrameAreaFrame", "WorldMapPlayer", "WorldMapCorpse", "WorldMapFlag1", "WorldMapFlag2",
  "WorldMapPing", "WorldMapParty1", "WorldMapRaid1",
  "UnrealQuestPatrolStrokeLayer", "UnrealQuestWorldMapPin2001", "UnrealQuestWorldMapPinObjective1",
  "BlackoutWorld", "WorldMapBlackout", "WorldMapTooltip",
}

local function mouseReport()
  if type(ShowUIPanel) == "function" then
    local wm = _G["WorldMapFrame"]
    if wm then pcall(ShowUIPanel, wm) end -- 开图让子帧就位
  end
  P("—— 鼠标开关点名（开图状态采集）——")
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  local dump = {}
  local function one(nm)
    local f = _G[nm]
    if not (type(f) == "table" or type(f) == "userdata") then
      P(nm .. " = 不存在")
      return
    end
    local me, mw = "?", "?"
    if type(f.IsMouseEnabled) == "function" then
      local ok, v = pcall(f.IsMouseEnabled, f)
      if ok then me = v and "吃鼠标" or "不吃" end
    end
    if type(f.isMouseWheelEnabled) == "function" then
      local ok, v = pcall(f.isMouseWheelEnabled, f)
      if ok then mw = v and "吃滚轮" or "不吃滚轮" end
    elseif type(f.IsMouseWheelEnabled) == "function" then
      local ok, v = pcall(f.IsMouseWheelEnabled, f)
      if ok then mw = v and "吃滚轮" or "不吃滚轮" end
    end
    local lv = "?"
    if type(f.GetFrameLevel) == "function" then local ok, v = pcall(f.GetFrameLevel, f) if ok and tonumber(v) then lv = tostring(v) end end
    local st = "?"
    if type(f.GetFrameStrata) == "function" then local ok, v = pcall(f.GetFrameStrata, f) if ok then st = tostring(v) end end
    local w, h = "?", "?"
    if type(f.GetWidth) == "function" then local ok, v = pcall(f.GetWidth, f) if ok and tonumber(v) then w = string.format("%.0f", v) end end
    if type(f.GetHeight) == "function" then local ok, v = pcall(f.GetHeight, f) if ok and tonumber(v) then h = string.format("%.0f", v) end end
    table.insert(dump, { path = nm, mouse = me, wheel = mw, level = lv, strata = st, w = w, h = h })
    P(string.format("%s [%s %sx%s] lv=%s %s —— %s / %s", nm, nodeType(f), w, h, lv, st, me, mw))
  end
  for _, nm in ipairs(MOUSE_CAND) do one(nm) end
  EH_DEBUGBOX_CFG.mouse = dump
  P("已写入存档 EH_DEBUGBOX_CFG.mouse → /reload 落盘后 AI 直接读")
  P("判读：『吃鼠标』且尺寸大/层级高的 = 最可能抢走悬停；WorldMapButton 一个『不吃』就说明命中不归它")
end

-- ===== /edb grab：一条命令全自动采集 =====
-- ★用户实测：地图打开后敲不了命令 → 采集必须「自开自关」：
--   关着图敲 /edb grab → 自己 ShowUIPanel 开图 → 等 1.5s 让懒加载子帧就位 → 扫描+落盘 → 自动关图。
local grab = { armed = false, t = 0 }

local function grabTick(elapsed)
  if not grab.armed then return end
  grab.t = grab.t + (tonumber(elapsed) or 0.05)
  if grab.t < 1.5 then return end
  grab.armed = false
  listLayers()
  local wm = _G["WorldMapFrame"]
  if (type(wm) == "table" or type(wm) == "userdata") and type(wm.Hide) == "function" then
    pcall(wm.Hide, wm) -- 自动关图，方便回聊天框看摘要
  end
  P("采集完成（地图已自动关闭）→ 请 /reload 落盘 → AI 直接读存档")
end

if type(CreateFrame) == "function" then
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  local gf = CreateFrame("Frame", "EH_DB_GRAB", parent)
  gf:SetScript("OnUpdate", function() grabTick(arg1) end)
end

local function grabArm()
  grab.armed = true
  grab.t = 0
  local wm = _G["WorldMapFrame"]
  if type(ShowUIPanel) == "function" and wm then pcall(ShowUIPanel, wm) end
  P("自动采集已启动：地图自动打开 → 1.5 秒后扫描 → 自动关闭。稍候，别敲命令")
end

-- 外围件（★用户问：黑幕层缩了吗 —— 它们是独立顶层帧，不在 WorldMapFrame 树里，必须点名补上）
local EXTRA = { "BlackoutWorld", "WorldMapBlackout", "WorldMapTooltip", "WorldMapPositioningGuide" }

-- ★用户要求：先把**所有层一起缩**测可行性，再逐个排查
local function scaleDeep(s)
  if not buildNodes() then
    P("WorldMapFrame 不存在")
    return
  end
  scaledNodes = {}
  local n, skipped = 0, 0
  for i, nd in ipairs(nodes) do
    local ndSS = uiField(nd.f, "SetScale") -- ★1.74.34-26 安全读口
    if type(ndSS) == "function" then
      pcall(ndSS, nd.f, s)
      scaledNodes[i] = nd.f
      n = n + 1
    else
      skipped = skipped + 1
    end
  end
  P("全层缩放：已缩 " .. n .. " 层（不可缩/图层 " .. skipped .. " 个跳过）→ /edb " .. tostring(s))
  -- 外围件（黑幕/提示/定位导引）单独点名：不在树里
  local exN = 0
  for _, nm in ipairs(EXTRA) do
    local f = _G[nm]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetScale) == "function" then
      pcall(f.SetScale, f, s)
      exN = exN + 1
      scaledNodes["x:" .. nm] = f -- ★记进还原表（/edb off 一并回 1）
      local par = "?"
      if type(f.GetParent) == "function" then
        local okp, p = pcall(f.GetParent, f)
        if okp and p then
          local okn, pn = pcall(p.GetName, p)
          if okn and type(pn) == "string" then par = pn end
        end
      end
      P("  外围件 " .. nm .. " 已缩（父级=" .. par .. "）")
    end
  end
  P("外围件共缩 " .. exN .. " 个（含黑幕层）")
  P("【开图后指着奥格瑞玛看浮字②：原生悬停正确 = 全层同缩这条路可行；仍漂 = 引擎侧命中不跟 Lua 缩放】")
  local wm = _G["WorldMapFrame"]
  if type(ShowUIPanel) == "function" and wm then pcall(ShowUIPanel, wm) end
end


local function scaleNode(idx, s)
  if type(nodes) ~= "table" or table.getn(nodes) == 0 then
    P("先跑 /edb list 拿清单")
    return
  end
  local nd = nodes[tonumber(idx) or 0]
  if not nd then
    P("编号无效（1.." .. table.getn(nodes) .. "）")
    return
  end
  local ndSS3 = uiField(nd.f, "SetScale") -- ★1.74.34-26 安全读口（坏对象直接索引会抛错）
  if type(ndSS3) ~= "function" then
    P("#" .. tostring(idx) .. " " .. nd.n .. " 无 SetScale（图层/纹理只能改尺寸，不支持缩放）")
    return
  end
  pcall(ndSS3, nd.f, s)
  scaledNodes = scaledNodes or {}
  scaledNodes[idx] = nd.f
  P("#" .. tostring(idx) .. " " .. nd.n .. " SetScale(" .. tostring(s) .. ") 已打"
    .. " 【悬停地图试试：这一层缩了之后触控对不对】")
  local wm2 = _G["WorldMapFrame"]
  if type(ShowUIPanel) == "function" and wm2 then pcall(ShowUIPanel, wm2) end -- 缩完自动开图，方便立刻悬停验证
end

local function resetNodes()
  if type(scaledNodes) == "table" then
    for _, f in pairs(scaledNodes) do pcall(f.SetScale, f, 1) end
  end
  scaledNodes = nil
end

-- ★★★1.74.30 框拖拽**整块搬进主插件工具模块** `tools/DragFrames.lua`（用户要求两次：「图层拖拽是个独立的工具，
--   和地图功能没关系」「把这块代码抽成 ./tools 下的独立工具模块」）。
--   本子插件从此只留**瘦转发**：开关真值 = `EVAL_HELP_CONFIG.dragFrames.on`（模块自己的存档）；
--   拖拽柄 / 全屏接盘 / 配置弹窗 / 定时复查 / 一次性迁移全在模块里。
--   ★模块没载入时**如实提示**（绝不假装开关有效、也不编一个假状态）。
local function ldNoModule(what)
  P("框拖拽模块（tools\\DragFrames.lua）没载入：" .. tostring(what) .. "不可用 —— 检查 EvalHelp.toc 是否载入它")
  return false
end

function EVAL_LD_DRAG_GET()
  if type(EVAL_DF_ENABLED) == "function" then return EVAL_DF_ENABLED() and true or false end
  return false
end

function EVAL_LD_DRAG_SET(on)
  if type(EVAL_DF_SET) == "function" then return EVAL_DF_SET(on) end
  return ldNoModule("开关")
end

function EVAL_LD_CUSTOM_SUMMARY()
  if type(EVAL_DF_SUMMARY) == "function" then
    local ok, list = pcall(EVAL_DF_SUMMARY)
    if ok and type(list) == "table" then return list end
    return { "（框拖拽模块读取自定义清单失败）" }
  end
  return { "框拖拽模块（tools\\DragFrames.lua）没载入：看不到自定义记录" }
end

function EVAL_LD_DRAG_RESET()
  if type(EVAL_DF_RESET) == "function" then return EVAL_DF_RESET() end
  return ldNoModule("重置定位")
end

if type(SlashCmdList) == "table" then
  SLASH_EHDEBUGBOX1 = "/edb"
  SLASH_EHDEBUGBOX2 = "/ems" -- 旧命令保留成别名
  SlashCmdList["EHDEBUGBOX"] = function(msg)
    msg = string.lower(tostring(msg or ""))
    local key, s = string.match(msg, "^(%w*)%s*(%d*%.?%d*)$")
    s = tonumber(s)
    if msg == "off" then
      setAll(1)
      resetNodes()
      P("三个主帧 + 所有试过的层 全回 1")
    elseif msg == "list" or msg == "ls" then
      listLayers()
    elseif msg == "grab" then
      grabArm()
    elseif msg == "mouse" or msg == "m" then
      mouseReport()
    elseif msg == "ui" then
      uiToggle()
    elseif msg == "tipdraw" then
      -- ★三分对照：三种宿主/层级各画一个框（同一段文字），看得到哪个字母就定案
      local function mkTest(tag, parent, strata, level, ox, oy)
        if not parent then P(tag .. "：宿主不存在，跳过") return nil end
        local b = CreateFrame("Frame", "EH_DB_TIPDRAW_" .. tag, parent)
        b:SetWidth(320) b:SetHeight(70)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", ox, oy)
        pcall(b.SetFrameStrata, b, strata)
        pcall(b.SetFrameLevel, b, level)
        if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, false) end
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
        uiSolid(bg, 0.02, 0.02, 0.02, 0.95)
        local fs = b:CreateFontString(nil, "OVERLAY")
        for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
          if pcall(fs.SetFont, fs, fp, 14, "OUTLINE") then break end
        end
        pcall(fs.SetPoint, fs, "TOPLEFT", b, "TOPLEFT", 6, -6)
        pcall(fs.SetText, fs, tag .. " · 宿主=" .. tostring(strata) .. " lv=" .. tostring(level) .. "\n能看到这行 = 这种画法可用")
        pcall(fs.SetTextColor, fs, 1, 0.9, 0.3)
        pcall(b.Show, b)
        local okq, shown = pcall(b.IsShown, b)
        local okl, l = pcall(b.GetLeft, b)
        local okt, t = pcall(b.GetTop, b)
        P(string.format("%s：parent=%s strata=%s lv=%s → IsShown=%s 位置=%.0f,%.0f",
          tag, tostring(parent and parent.GetName and (select(1, pcall(parent.GetName, parent)) or "?") or "?"),
          tostring(strata), tostring(level), tostring(okq and shown), tonumber(okl and l) or -1, tonumber(okt and t) or -1))
        return b
      end
      mkTest("A(WorldFrame/FULLSCREEN_DIALOG/700)", uiHost(), "FULLSCREEN_DIALOG", 700, 300, -140)
      mkTest("B(面板root/510)", ui.root, "FULLSCREEN_DIALOG", 510, 20, -160)
      mkTest("C(UIParent/DIALOG/250)", _G["UIParent"], "DIALOG", 250, 300, -260)
      P("请回我：屏幕上看到哪几个字母（A/B/C）？— 一个都看不到 = 三种画法都不渲染（罕见，另查）")
    elseif msg == "tipboxshow" then
      -- 直接把**自绘 tooltip 框**强制显示在屏幕中央（不走 OnEnter），看它本身能不能画出来
      local okBox = uiTipShow(_G["UIParent"], { { t = "自绘 tooltip 框：能看到这行 = 框本身没问题（那问题就在 OnEnter 没触发）" } })
      P("自绘框强制显示 → " .. tostring(okBox))
      if uiTip.box then
        pcall(uiTip.box.ClearAllPoints, uiTip.box)
        pcall(uiTip.box.SetPoint, uiTip.box, "CENTER", _G["UIParent"], "CENTER", 0, 0)
        pcall(uiTip.box.SetFrameStrata, uiTip.box, "TOOLTIP")
        pcall(uiTip.box.SetFrameLevel, uiTip.box, 900)
        P("已把自绘框移到屏幕中央并抬到 TOOLTIP/900")
      end
    elseif msg == "tipdbg" then
      ui.tipDbg = not ui.tipDbg
      P("tooltip 取证 = " .. (ui.tipDbg and "开（悬停几行后再 /edb tiplog）" or "关"))
      if ui.tipDbg then ui.tipLog = {} end
    elseif msg == "tiplog" then
      EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
      EH_DEBUGBOX_CFG.tipdbg = ui.tipLog
      P("tooltip 取证缓冲（" .. table.getn(ui.tipLog) .. " 条）：")
      for _, ln in ipairs(ui.tipLog) do P("  " .. ln) end
      P("已写入存档 EH_DEBUGBOX_CFG.tipdbg → /reload 后 AI 直接读")
    elseif msg == "tiptest" or msg == "tip" then
      -- ★自检：面板行 tooltip 用的是哪个对象？Show 之后到底显示了没？（用户报「tooltip 未显示」的取证入口）
      local gt = _G["GameTooltip"]
      local wt = _G["WorldMapTooltip"]
      P("GameTooltip=" .. tostring(gt ~= nil) .. " · WorldMapTooltip=" .. tostring(wt ~= nil)
        .. " · 面板=" .. tostring(ui.root ~= nil and ui.root:IsShown() and "已开" or "未开/未建"))
      local tip = gt or wt
      if not tip then P("两个 tooltip 对象都不存在，无法显示") return end
      local owner = (ui.root or UIParent)
      pcall(tip.SetOwner, tip, owner, "ANCHOR_LEFT")
      pcall(tip.ClearLines, tip)
      if type(tip.AddLine) == "function" then add("tooltip 自检：能看到这行 = 显示正常", 1, 0.85, 0.3) end
      pcall(tip.Show, tip)
      local ok, shown = pcall(tip.IsShown, tip)
      P("已对 " .. (tip == gt and "GameTooltip" or "WorldMapTooltip") .. " 调用 Show → IsShown=" .. tostring(ok and shown) .. "（false 即该对象不可用于本面板）")
      local okBox = uiTipShow(ui.root or UIParent, { { t = "自绘信息面板自检：能看到这段 = 自绘框可用" } })
      P("自绘信息面板 Show → " .. tostring(okBox))
    elseif msg == "uiconf" then
      EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
      local c = EH_DEBUGBOX_CFG.ui
      if type(c) ~= "table" then P("用户配置里还没有面板配置（改动任一控件即自动写入）") return end
      local catDef = uiCatDef(c.cat or 0)
      -- ★1.74.31 补：分类显示**名字**（数字码看不出是什么）+ 无名层过滤的存档值
      --   （老存档没有这个键 → 如实标「默认」= 代码里的默认值「开 = 隐藏无名层」）
      P(string.format("面板配置：缩放%.2f 透明%.2f 宽%.0f 高%.0f X%.0f Y%.0f · 参数勾选[缩放%s 透明%s 宽%s 高%s] · 可见性=%s ≥500=%s 隐藏无名=%s · 分类=%s(码%s) · 位置=%.0f,%.0f",
        c.value or -1, c.alphaValue or -1, c.wVal or -1, c.hVal or -1, c.xVal or 0, c.yVal or 0,
        tostring(c.par and c.par.scale), tostring(c.par and c.par.alpha), tostring(c.par and c.par.w), tostring(c.par and c.par.h),
        (function()
          local v = c.vis
          if type(v) ~= "table" then return "不限（老存档按 onlyShown=" .. tostring(c.onlyShown) .. " 迁移）" end
          local sv, hv = v.shown == true, v.hidden == true
          if sv and hv then return "全部" end
          if sv then return "可见" end
          if hv then return "不可见" end
          return "不限"
        end)(), tostring(c.bigOnly),
        (c.hideUnnamed == nil) and "开（老存档默认）" or tostring(c.hideUnnamed),
        catDef.label, tostring(c.cat), c.px or 0, c.py or 0))
    elseif msg == "uiconfclear" then
      EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
      EH_DEBUGBOX_CFG.ui = nil
      P("面板配置已清除（/reload 后回到默认值）")
    elseif msg == "uikids" or msg == "子件试挂" then
      -- ★★用户问：「能否不控制 UIParent 的显示，只控制子元素的显示？」
      --   Lua 帧模型的硬约束：**父隐藏时子帧不渲染**（child:Show() 无效）⇒
      --   唯一不碰 UIParent 的办法 = 把需要的子件**改父级（SetParent）**到可见宿主（WorldFrame），
      --   并按**绝对位置**重锚（否则锚点相对新父级会跳位）。
      --   ★第二条约束：地图是 FULLSCREEN strata，若子件 strata 更低会被地图盖住 ——
      --     本实验同时把它们抬到 FULLSCREEN_DIALOG，才能"压在地图之上"（如实告知：这会改变层级）。
      local sub5 = string.match(msg, "^%S+%s*(.-)%s*$") or ""
      local host = uiHost()
      local function absOf(fr)
        local okl, l = pcall(fr.GetLeft, fr)
        local okt, t = pcall(fr.GetTop, fr)
        local oks, es = pcall(fr.GetEffectiveScale, fr)
        if not (okl and okt and tonumber(l) and tonumber(t)) then return nil end
        es = (oks and tonumber(es)) or 1
        if es == 0 then es = 1 end
        return l / es, t / es
      end
      if sub5 == "restore" or sub5 == "还原" then
        local n = 0
        for name, rec in pairs(UIKIDS.saved) do
          local fr = _G[name]
          if (type(fr) == "table" or type(fr) == "userdata") and rec.parent then
            pcall(fr.SetParent, fr, rec.parent)
            pcall(fr.ClearAllPoints, fr)
            for _, pt in ipairs(rec.points or {}) do
              pcall(fr.SetPoint, fr, pt[1], pt[2], pt[3], pt[4], pt[5])
            end
            if rec.strata then pcall(fr.SetFrameStrata, fr, rec.strata) end
            n = n + 1
          end
        end
        UIKIDS.saved = {}
        UIKIDS.done = false
        P("已还原 " .. n .. " 个子件（父级 + 锚点 + strata 全部回原样）")
      else
        local n, skip = 0, 0
        for _, name in ipairs(UIKIDS.list) do
          local fr = _G[name]
          if not (type(fr) == "table" or type(fr) == "userdata") then
            skip = skip + 1
          else
            local pos = absOf(fr)
            local rec = { points = {}, parent = nil, strata = nil }
            if type(fr.GetParent) == "function" then
              local okp, p = pcall(fr.GetParent, fr)
              if okp then rec.parent = p end
            end
            if type(fr.GetPoint) == "function" then
              for i = 1, 4 do
                local okpt, pt, rel, relp, x, y = pcall(fr.GetPoint, fr, i)
                if okpt and pt then table.insert(rec.points, { pt, rel, relp, x, y }) else break end
              end
            end
            if type(fr.GetFrameStrata) == "function" then
              local okst, st = pcall(fr.GetFrameStrata, fr)
              if okst then rec.strata = st end
            end
            UIKIDS.saved[name] = rec
            -- 改挂 + 按绝对位置重锚（左上角贴宿主左上角，偏移 = 绝对坐标）
            local ok1 = pcall(fr.SetParent, fr, host)
            if ok1 and pos then
              pcall(fr.ClearAllPoints, fr)
              pcall(fr.SetPoint, fr, "TOPLEFT", host, "TOPLEFT", pos, select(2, absOf(fr) or 0))
              -- ★上面 select 写法不可靠 → 重新用绝对坐标正确落位（两值分开取）
              local l2, t2 = absOf(fr)
              if l2 then
                pcall(fr.ClearAllPoints, fr)
                pcall(fr.SetPoint, fr, "TOPLEFT", host, "TOPLEFT", l2, t2)
              end
            end
            pcall(fr.SetFrameStrata, fr, "FULLSCREEN_DIALOG") -- 压过地图的 FULLSCREEN
            if type(fr.SetFrameLevel) == "function" then pcall(fr.SetFrameLevel, fr, 450) end
            pcall(fr.Show, fr)
            n = n + 1
          end
        end
        UIKIDS.done = true
        P("子件试挂完成：已改挂 " .. n .. " 个（跳过 " .. skip .. " 个不存在）→ 宿主 WorldFrame，strata 抬到 FULLSCREEN_DIALOG/450")
        P("★现在开图看：小地图 / 动作条 / 头像 / 聊天 是否还在？(/edb uikids restore 一键还原)")
        EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
        EH_DEBUGBOX_CFG.uikids = { done = n, at = (type(GetTime) == "function") and tostring(GetTime()) or "?" }
      end
    elseif msg == "uihide" or msg == "界面隐藏取证" then
      -- ★★用户确认「地图间隔重开 = 我们 Show(UIParent) 与客户端互抢」后转方向：
      --   不再事后抢，而是查**到底谁在隐藏 UIParent** —— Lua 层可定点拦截，C 层只能另想办法。
      local sub3 = string.match(msg, "^%S+%s*(.-)%s*$") or ""
      local function flushHide()
        EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
        EH_DEBUGBOX_CFG.uihide = UIHIDE.log
      end
      if UIHIDE.wrapped and (sub3 == "stop" or sub3 == "停") then
        local up = _G["UIParent"]
        if up and UIHIDE.orig then pcall(function() up.Hide = UIHIDE.orig end) end
        UIHIDE.wrapped = false
        UIHIDE.on = false
        if UIHIDE.frame then pcall(UIHIDE.frame.SetScript, UIHIDE.frame, "OnUpdate", nil) end
        flushHide()
        P("界面隐藏取证已停止（UIParent.Hide 已还原）。共记 " .. table.getn(UIHIDE.log) .. " 条：")
        for _, ln in ipairs(UIHIDE.log) do P("  " .. ln) end
        P("已写存档 EH_DEBUGBOX_CFG.uihide（/reload 后 AI 直接读）")
      else
        UIHIDE.log = {}
        UIHIDE.count = 0
        local up = _G["UIParent"]
        if not (type(up) == "table" or type(up) == "userdata") then
          P("UIParent 不存在，无法取证")
        else
          if type(up.Hide) == "function" then
            UIHIDE.orig = up.Hide
            local orig = up.Hide
            local function rec(tag, extra)
              local t = (type(GetTime) == "function") and GetTime() or 0
              table.insert(UIHIDE.log, string.format("%.2f %s%s", t, tag, extra and (" " .. extra) or ""))
              while table.getn(UIHIDE.log) > 60 do table.remove(UIHIDE.log, 1) end
              if table.getn(UIHIDE.log) % 5 == 0 then flushHide() end
            end
            UIHIDE.rec = rec
            up.Hide = function(self, ...)
              UIHIDE.count = UIHIDE.count + 1
              local src = "?"
              if type(debug) == "table" and type(debug.getinfo) == "function" then
                local ok, i = pcall(debug.getinfo, 2, "Sl")
                if ok and i then
                  src = tostring(i.short_src or "?") .. ":" .. tostring(i.currentline or "?")
                end
              end
              rec("UIParent.Hide() 被调用", "第 " .. UIHIDE.count .. " 次 · 调用者=" .. src)
              return orig(self, ...)
            end
            UIHIDE.wrapped = true
            rec("包装完成：UIParent.Hide 已被记账（原函数保留并转发）")
          else
            P("UIParent.Hide 不是函数形态 → 无法包装（可能是 C 层字段，如实告知）")
          end
        end
        -- 同时采样：有的实现不是 Hide 而是把 alpha 归零
        if type(CreateFrame) == "function" then
          if not UIHIDE.frame then
            local parent = _G["WorldFrame"]
            if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
            UIHIDE.frame = CreateFrame("Frame", "EH_DB_UIHIDE", parent)
          end
          UIHIDE.on = true
          local acc, last = 0, nil
          UIHIDE.frame:SetScript("OnUpdate", function()
            if not UIHIDE.on then return end
            acc = acc + (tonumber(arg1) or 0.05)
            if acc < 0.25 then return end
            acc = 0
            local u = _G["UIParent"]
            if not (type(u) == "table" or type(u) == "userdata") then return end
            local oks, sh = pcall(u.IsShown, u)
            local oka, al = pcall(u.GetAlpha, u)
            local cur = "shown=" .. tostring(oks and sh) .. " alpha=" .. tostring(oka and al)
            if last == nil then
              last = cur
              if UIHIDE.rec then UIHIDE.rec("初始 " .. cur) end
            elseif cur ~= last then
              local t = (type(GetTime) == "function") and GetTime() or 0
              table.insert(UIHIDE.log, string.format("%.2f UIParent 状态变化 → %s", t, cur))
              last = cur
            end
          end)
        end
        flushHide()
        P("界面隐藏取证已开始：记账 UIParent.Hide + 采样 shown/alpha 变化")
        P("★现在开一次图；然后把 /edb uihide stop 的摘要发我（或 /reload 让我读存档）")
      end
    elseif msg == "mapwatch" or msg == "开图取证" then
      -- ★★取证：谁在"间隔地重新打开地图"（用户报的现象）
      local sub2 = string.match(msg, "^%S+%s*(.-)%s*$") or ""
      if MAPWATCH.on and (sub2 == "stop" or sub2 == "停") then
        MAPWATCH.on = false
        for name, orig in pairs(MAPWATCH.saved or {}) do
          if orig ~= nil then pcall(function() _G[name] = orig end) end
        end
        if MAPWATCH.frame then pcall(MAPWATCH.frame.SetScript, MAPWATCH.frame, "OnUpdate", nil) end
        EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
        EH_DEBUGBOX_CFG.mapwatch = MAPWATCH.log
        P("开图取证已停止（原函数已还原）。共记 " .. table.getn(MAPWATCH.log) .. " 条：")
        for _, ln in ipairs(MAPWATCH.log) do P("  " .. ln) end
        P("已写存档 EH_DEBUGBOX_CFG.mapwatch（/reload 后 AI 直接读）")
      else
        MAPWATCH.log = {}
        MAPWATCH.saved = MAPWATCH.saved or {}
        MAPWATCH.count = 0
        local function rec(tag, extra)
          local t = (type(GetTime) == "function") and GetTime() or 0
          table.insert(MAPWATCH.log, string.format("%.2f %s%s", t, tag, extra and (" " .. extra) or ""))
          while table.getn(MAPWATCH.log) > 60 do table.remove(MAPWATCH.log, 1) end
          if table.getn(MAPWATCH.log) % 10 == 0 then -- ★每 10 条落一次盘：半途 /reload 也不丢证据
            EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
            EH_DEBUGBOX_CFG.mapwatch = MAPWATCH.log
          end
        end
        -- 钩三个「开图」入口（哪个存在钩哪个；保存原函数，stop 时还原）
        for _, gname in ipairs({ "ShowUIPanel", "ToggleWorldMap", "OpenWorldMap" }) do
          local orig = _G[gname]
          local isFn = (type(orig) == "function")   -- 具名帧会顶掉同名函数：只钩函数形态，如实标注
          if isFn and MAPWATCH.saved[gname] == nil then
            MAPWATCH.saved[gname] = orig
            local captured = gname
            _G[gname] = function(a1, a2, a3, a4)
              MAPWATCH.count = MAPWATCH.count + 1
              local name = "?"
              if type(a1) == "table" or type(a1) == "userdata" then
                if type(a1.GetName) == "function" then local ok, v = pcall(a1.GetName, a1) if ok then name = tostring(v) end end
              else
                name = tostring(a1)
              end
              rec("钩到 " .. captured .. "()", "参数1=" .. name .. " 第 " .. MAPWATCH.count .. " 次")
              return orig(a1, a2, a3, a4)
            end
          elseif not isFn then
            rec("（" .. gname .. " 不是函数形态 → 未钩）")
          end
        end
        -- 时间轴采样：只记「状态翻转」，避免刷屏
        local lastOpen = nil
        if type(CreateFrame) == "function" then
          if not MAPWATCH.frame then
            local parent = _G["WorldFrame"]
            if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
            MAPWATCH.frame = CreateFrame("Frame", "EH_DB_MAPWATCH", parent)
          end
          MAPWATCH.on = true
          local acc = 0
          MAPWATCH.frame:SetScript("OnUpdate", function()
            if not MAPWATCH.on then return end
            acc = acc + (tonumber(arg1) or 0.05)
            if acc < 0.25 then return end
            acc = 0
            local wf = _G["WorldMapFrame"]
            local mv = _G["WorldMapButton"]
            local a, b = nil, nil
            if (type(wf) == "table" or type(wf) == "userdata") and type(wf.IsShown) == "function" then
              local ok, v = pcall(wf.IsShown, wf) a = ok and v and true or false
            end
            if (type(mv) == "table" or type(mv) == "userdata") and type(mv.IsShown) == "function" then
              local ok, v = pcall(mv.IsShown, mv) b = ok and v and true or false
            end
            local nowOpen = a or b
            if lastOpen == nil then
              lastOpen = nowOpen
              rec("初始状态 地图=" .. tostring(nowOpen))
            elseif nowOpen ~= lastOpen then
              rec("状态翻转 地图=" .. tostring(nowOpen), (nowOpen and "（开了）" or "（关了）"))
              lastOpen = nowOpen
            end
          end)
        end
        P("开图取证已开始：钩住 Lua 侧开图入口 + 每 0.25s 采样地图开关状态（只记翻转）")
        P("★现在去复现「地图自己又开了」；复现后敲 /edb mapwatch stop 看摘要（或 /reload 让我读存档）")
      end
    elseif msg == "uidump" or msg == "界面快照" then
      -- ★★纯观察快照（1.74.29）：**不 Show、不 Hide、不改任何东西**，只如实读状态并落盘。
      --   判读：若「地图已开 = true」且「UIParent.IsShown = true」⇒ 本客户端开图**并不会隐藏 UI**
      --   （此前「开图隐藏 UIParent」的结论就要作废/限条件）；若 UIParent=false ⇒ 仍会隐藏。
      local RES = {}
      local function rec(k, v) RES[table.getn(RES) + 1] = k .. " = " .. tostring(v) end
      local function st(name)
        local fr = _G[name]
        if not (type(fr) == "table" or type(fr) == "userdata") then rec(name, "（不存在）") return end
        local oks, shown = pcall(fr.IsShown, fr)
        local okp, par = pcall(fr.GetParent, fr)
        local pn = "?"
        if okp and par and type(par.GetName) == "function" then
          local okn, v = pcall(par.GetName, par)
          pn = okn and tostring(v) or "?"
        end
        rec(name, "IsShown=" .. tostring(oks and shown) .. " 父=" .. pn)
      end
      st("WorldMapFrame") st("WorldMapButton") st("WorldMapDetailFrame")
      st("UIParent") st("MinimapCluster") st("PlayerFrame") st("ActionButton1") st("MainMenuBar") st("WorldFrame")
      EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
      EH_DEBUGBOX_CFG.uidump = RES
      P("—— 界面快照（纯观察，未做任何修改）——")
      for _, ln in ipairs(RES) do P(ln) end
      P("已写存档 EH_DEBUGBOX_CFG.uidump（/reload 后 AI 直接读）")
    elseif msg == "uiprobe" or msg == "开图探针" then
      -- ★★1.74.29 用户决定：**放弃对 UIParent 的显示操作** ⇒ 这个"强制 Show 再观察"的探针已整块删除
      --   （它第 ① 步就执行 UIParent:Show()，属"操作"而非"观察"，还会把 UI 顶住不还原）。
      --   纯观察 → /edb uidump；查"谁在隐藏 UIParent" → /edb uihide；改挂子件实验 → /edb uikids。
      P("uiprobe 已删除（它会操作 UIParent 显隐）。纯观察用 /edb uidump；查隐藏来源用 /edb uihide")

    elseif key == "tree" or msg == "树" or string.find(msg, "^tree ") == 1 then
      -- ★★★1.74.31 第二步：图层树的**取证 + 操作**入口（用户要求「折叠状态跨 reload 保持」⇒ 必须有能自查的东西）
      --   /edb tree        → 树的现状：条目/父节点/子层总数/已折叠/当前列表条数（数字全来自读值口同一份数据）
      --   /edb tree all    → 全部展开（清空折叠标记，落存档）
      --   /edb tree none   → 全部折叠（只留第 1 层）
      uiBuildEntries()
      uiTreePass()
      local sub = string.match(msg, "^%S+%s+(%a+)") or ""
      if sub == "all" or sub == "expand" then
        ui.treeCollapsed = {}
        uiSaveSettings()
        if uiRefresh then uiRefresh() end
        P("图层树：已全部展开（折叠标记清空，已落存档）")
      elseif sub == "none" or sub == "collapse" then
        local tc, n = {}, 0
        for _, e in ipairs(ui.entries or {}) do
          if (e.kids or 0) > 0 then tc[e.path] = true n = n + 1 end
        end
        ui.treeCollapsed = tc
        uiSaveSettings()
        ui.off = 0
        if uiRefresh then uiRefresh() end
        P("图层树：已全部折叠（" .. n .. " 个有子层的节点收起来，只留最外层；已落存档）")
      else
        local nodesN, parN, kidN = 0, 0, 0
        local byDepth = {}
        for _, e in ipairs(ui.entries or {}) do
          nodesN = nodesN + 1
          local d = uiEntryDepth(e)
          byDepth[d] = (byDepth[d] or 0) + 1
          if (e.kids or 0) > 0 then parN = parN + 1 kidN = kidN + (e.kids or 0) end
        end
        local shown = table.getn(uiFiltered())
        local fold = uiTreeCollapsedCount()
        P(string.format("--- 图层树：条目 %d · 有子层的节点 %d（合计子层 %d）· 已折叠 %d · 当前列表 %d 条 ---",
          nodesN, parN, kidN, fold, shown))
        local dl = {}
        for d = 1, 9 do if byDepth[d] then table.insert(dl, "第" .. d .. "层 " .. byDepth[d] .. " 条") end end
        P("各层条目数：" .. ((table.getn(dl) > 0) and table.concat(dl, " · ") or "（无）")
          .. " · 层深上限 = " .. ((tonumber(ui.depthMax) or 0) == 0 and "全部" or tostring(ui.depthMax)))
        local shownFold = 0
        for _, e in ipairs(ui.entries or {}) do
          if ui.treeCollapsed and ui.treeCollapsed[e.path] and shownFold < 5 then
            shownFold = shownFold + 1
            P(string.format("  已折叠 #%s %s（子层 %d）", tostring(e.no or "?"), tostring(e.path), e.kids or 0))
          end
        end
        if fold == 0 then P("  当前没有任何折叠（点行左侧的 ▼ 折叠一层；/edb tree none 可一次全折）") end
      end
    elseif msg == "named" or msg == "有名" then
      local c = uiNamedCounts()
      P(string.format("--- 无名层过滤诊断：%s ---", c.on and "开（只显示有名字的层）" or "关（无名层也显示）"))
      P(string.format("条目总数 %d · 有名 %d · 无名 %d · 当前列表显示 %d 条", c.total, c.named, c.unnamed, c.shown))
      P("判据：只有 GetName() 返回非空字符串才算「有名字」；无名纹理/字体串都是无名 → 开关打开时不列出。")
      if c.on and c.shown > 0 and c.unnamed == 0 then P("提示：目前列表里没有无名条目（过滤正常）") end
      P("--- 前 5 条实证（路径 | 对象类型 | GetName | 判为）---")
      local shown5 = 0
      for _, e in ipairs(uiFiltered()) do
        if shown5 >= 5 then break end
        shown5 = shown5 + 1
        local t = "?"
        local got = uiField(e.f, "GetObjectType") -- ★1.74.34-26：走安全读口（坏对象直接索引会抛错）
        if type(got) == "function" then local ok, v = pcall(got, e.f) if ok then t = tostring(v) end end
        local nm = uiFrameName(e.f)
        P(string.format("%s | %s | %s | %s%s", tostring(e.path), t, tostring(nm), uiEntryNamed(e) and "有名" or "无名",
          ((nm ~= nil and uiNameLooksFake(nm)) and "（合成名，已当无名）" or "")))
      end
    elseif msg == "bars" or msg == "动作条探针" or msg == "frames" or msg == "框体探针" then
      -- ★★★1.74.31「动作条1~4 也加入可拖拽项」的取证入口（用户要求，本客户端帧名未知 → 现场探）：
      --   候选逐个报在不在 + 全 _G 扫名字像动作条的帧 + 结果落存档 EVAL_HELP_CONFIG.dragBars（/reload 后 AI 直接读）
      -- ★★★1.74.32 同一条命令扩成**框体探针**（用户新加「队伍层/团队层」）：同时扫队伍/团队帧，
      --   并**先报当前队友/团员数** —— 单人时「候选全不在」是正常的，有队伍时才说明帧名不对。
      --   ★命令名 `/edb bars` 保留（旧用法/旧测试都在用），`/edb frames` 是同一条路的别名。
      -- ★★★1.74.32【第 1 步：只读取证】再扩「被动打开层」（公会/属性/拍卖/邮箱/任务/技能树 等）：
      --   逐个候选报在不在 + 关键词分组扫 + **顶层大帧兜底** → 一次跑完就能拿全真名与几何，供下一步画图标用。
      -- ★★★1.74.32 修「命令静默」：旧写法 `pcall(EVAL_DF_PROBE_BARS)` 会把内部错误**吞掉** ——
      --   真机上出现过「跑了命令、聊天框什么都不打、存档里连 dragBars 键都没有」，无法判断是没跑还是跑挂了。
      --   现在优先走 `EVAL_DF_PROBE_SAFE`（写阶段标记 + 播报并落档错误原文）；退路才自己 pcall 并如实报错。
      if type(EVAL_DF_PROBE_SAFE) == "function" then
        -- ★先打一行**即时回显**：看到它 = 命令到达了；看不到 = 命令压根没到（插件没载入/分派没接上）
        P("框体探针：命令已收到，开始扫描（约 1 秒，别急）…")
        EVAL_DF_PROBE_SAFE()
      elseif type(EVAL_DF_PROBE_BARS) == "function" then
        local ok, err = pcall(EVAL_DF_PROBE_BARS)
        if not ok then
          P("|cffff6060框体探针出错|r：" .. tostring(err))
          if type(EVAL_DF_PROBE_MARK) == "function" then pcall(EVAL_DF_PROBE_MARK, "error", err) end
        end
      else
        ldNoModule("框体探针")
      end
    elseif msg == "dragtest" or msg == "拖拽诊断" then
      if type(EVAL_DF_DIAG) == "function" then pcall(EVAL_DF_DIAG) else ldNoModule("拖拽诊断") end
    elseif msg == "dragsum" or msg == "拖拽清单" then
      -- ★★1.74.31：用户要求「[重置] 信息显示要现在缩放/透明度/显示隐藏」。
      --   工具箱 tooltip 已接 EVAL_DF_SUMMARY；这里再给**不依赖 tooltip 渲染**的同一份数据（打聊天框）。
      if type(EVAL_DF_SUMMARY) ~= "function" then P("框拖拽模块未载入（tools/DragFrames.lua）") return true end
      local ok, list = pcall(EVAL_DF_SUMMARY)
      if not (ok and type(list) == "table") then P("读取清单失败") return true end
      P("--- 框拖拽清单（缩放 / 透明度 / 显示隐藏）---")
      for i2 = 1, table.getn(list) do P(tostring(list[i2])) end
    elseif msg == "dragrect" or msg == "弹窗矩形" then
      -- ★★★1.74.30 弹窗定位诊断搬到模块（同一份数字：锚点数 / 每级矩形 / 定位 mode）
      if type(EVAL_DF_RECT) == "function" then pcall(EVAL_DF_RECT) else ldNoModule("弹窗矩形诊断") end
    elseif msg == "dragpop" then
      if type(EVAL_DF_TRIAL) == "function" then pcall(EVAL_DF_TRIAL) else ldNoModule("弹窗试用") end
    elseif msg == "dragapply" then
      if type(EVAL_DF_APPLYALL) == "function" then pcall(EVAL_DF_APPLYALL, false) else ldNoModule("立即应用") end
    elseif msg == "apply" then
      uiCustAutoApplyBegin("手动 /edb apply")
      P("已手动触发「启动自动生效」链（最多 6 次、每 2 秒）")
    elseif msg == "drag" then
      if type(EVAL_DF_TOGGLE) == "function" then
        pcall(EVAL_DF_TOGGLE)
      else
        ldNoModule("开关")
      end
      -- 面板顶栏那个按钮的文字跟着走（同一真值，不另存状态）
      if ui.dragBtn and ui.dragBtn.label and type(ui.ldBtnLabel) == "function" then
        pcall(ui.dragBtn.label.SetText, ui.dragBtn.label, ui.ldBtnLabel())
      end
    elseif msg == "recolor" or msg == "颜色" then
      uiRecolorAll()
    elseif msg == "scanui" or msg == "uisize" then
      uiScanMeasure()
    elseif msg == "maptile" or msg == "地图瓦片" or string.find(msg, "^maptile%s") == 1 or string.find(msg, "^地图瓦片%s") == 1 then
      -- ★★★1.74.34-18「探索叠加图不跟随地图缩放」取证 + 试修（用户报：WorldMapDetailFrame 内 12 号之后的纹理
      --   缩放/定位不随外框走）。真机数据（1.74.34-18b 存档）给出的定案：
      --   · 父帧 es=0.7 来自**祖先** WorldMapFrame；Lua 侧几何**全是逻辑口径**（22 个 k 全 = 1.000）
      --   · 12 张底瓦片互相锚 + **偏移全 0** ⇒ 对缩放免疫，所以底图正确
      --   · 9 张 WorldMapOverlayN + WorldMapHighlight 锚父帧 TOPLEFT + **非零逻辑偏移** ⇒ 缩放后出错
      --   ⇒ 试修 = 只动**非瓦片**的那些纹理：把「偏移 + 尺寸」按父级 es 折算（保持相对父帧的锚点不变）。
      --   子命令：/edb maptile fit s|d|restore（s = ×es · d = ÷es · restore = 还原到原始值）
      -- ★★★1.74.35-4：**自动适配已搬到工具箱→缩放大地图**（`tools/SimpleMap.lua`，默认开，命令 /ehm mapfit）。
      --   用户明确「图层调试工具只是个调试工具，不需要」⇒ 这里**不再有 auto 开关、也不再自己跑 ticker**，
      --   `diag` 改成**只读**报告（不写任何几何），只保留手动试修 fit/restore 与只读清单。
      local sub = string.lower(string.match(msg, "^%S+%s+(%S+)") or "")
      if sub == "diag" or sub == "诊断" then
        local fr = _G["WorldMapDetailFrame"]
        local mv = _G["WorldMapButton"]
        local open = false
        if (type(mv) == "table" or type(mv) == "userdata") and type(mv.IsShown) == "function" then
          local ok, v = pcall(mv.IsShown, mv)
          open = (ok and v) and true or false
        end
        local es = nil
        if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetEffectiveScale) == "function" then
          local ok, v = pcall(fr.GetEffectiveScale, fr)
          if ok and tonumber(v) then es = tonumber(v) end
        end
        local nOrig, nTex, nTile = 0, 0, 0
        for _ in pairs((EH_DEBUGBOX_CFG or {}).maptileOrig or {}) do nOrig = nOrig + 1 end
        if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
          local okr, regs = pcall(function() return { fr:GetRegions() } end)
          if okr then
            for _, o in ipairs(regs) do
              if o and nodeType(o) == "Texture" then
                local nm = uiFrameName(o)
                if type(nm) == "string" and string.sub(nm, 1, 18) == "WorldMapDetailTile" then nTile = nTile + 1
                else nTex = nTex + 1 end
              end
            end
          end
        end
        local g = { at = (type(GetTime) == "function") and string.format("%.1f", GetTime()) or "?",
          open = open, es = es, tex = nTex, tile = nTile, orig = nOrig,
          owner = "tools/SimpleMap.lua（/ehm mapfit）" }
        EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
        EH_DEBUGBOX_CFG.maptileDiag = g
        P(string.format("地图叠加层诊断（只读）：地图开=%s · 父帧 es=%s · 非瓦片纹理 %d 个 · 底瓦片 %d 个 · 存档原值 %d 条",
          tostring(open), es and string.format("%.3f", es) or "?", nTex, nTile, nOrig))
        P("★自动适配的归属 = **工具箱 → 缩放大地图**（tools/SimpleMap.lua，默认开）：用 /ehm mapfit [on|off|restore|diag]；本工具只做手动探针")
        P("落档 EH_DEBUGBOX_CFG.maptileDiag → /reload 后 AI 可读")
        return
      end
      if sub == "fit" or sub == "s" or sub == "d" or sub == "restore" or sub == "还原" then
        local mode = sub
        if mode == "fit" then
          mode = string.lower(string.match(msg, "^%S+%s+%S+%s+(%S+)") or "")
        end
        if mode == "还原" then mode = "restore" end
        local fr = _G["WorldMapDetailFrame"]
        if not (type(fr) == "table" or type(fr) == "userdata") then
          P("|cffff6060WorldMapDetailFrame 不存在|r")
        else
          local es = 1
          if type(fr.GetEffectiveScale) == "function" then
            local ok, v = pcall(fr.GetEffectiveScale, fr)
            if ok and tonumber(v) and tonumber(v) > 0 then es = tonumber(v) end
          end
          EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
          EH_DEBUGBOX_CFG.maptileOrig = EH_DEBUGBOX_CFG.maptileOrig or {}
          local orig = EH_DEBUGBOX_CFG.maptileOrig
          local regs = {}
          if type(fr.GetRegions) == "function" then
            local ok, t = pcall(function() return { fr:GetRegions() } end)
            if ok then regs = t end
          end
          local k = 1
          if mode == "s" then k = es elseif mode == "d" then k = 1 / es else k = nil end
          -- ★1.74.35-4：不再有本地的「自动适配开关」要关（自动适配已搬到工具箱→缩放大地图）。
          --   注意：`/ehm mapfit` 默认**开** ⇒ 想用这里的 ÷es 反向试修时，先 `/ehm mapfit off`，
          --   否则 SimpleMap 那套幂等判据下一拍就把手动写进去的值改回 ×es（这是设计如此，不是打架）。
          local idx, n, skipTiles, miss = 0, 0, 0, 0
          for _, o in ipairs(regs) do
            if o and nodeType(o) == "Texture" then
              idx = idx + 1
              local nm = uiFrameName(o)
              local isTile = (type(nm) == "string" and string.sub(nm, 1, 18) == "WorldMapDetailTile")
              if isTile then
                skipTiles = skipTiles + 1 -- ★底瓦片一律不动（它们本来就对）
              else
                local key = "tex" .. tostring(idx)
                local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
                local okw, w = pcall(o.GetWidth, o)
                local okh, h = pcall(o.GetHeight, o)
                if okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
                  if not orig[key] then -- 第一次动手前记录原始值（还原的唯一依据）
                    orig[key] = { idx = idx, name = nm, p = tostring(p), rel = tostring(uiRelName(rel)),
                      rp = tostring(rp), x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
                  end
                  local o0 = orig[key]
                  if mode == "restore" then
                    pcall(o.ClearAllPoints, o)
                    pcall(o.SetPoint, o, o0.p, o0.rel, o0.rp, o0.x, o0.y)
                    pcall(o.SetWidth, o, o0.w)
                    pcall(o.SetHeight, o, o0.h)
                    n = n + 1
                  elseif k then
                    pcall(o.ClearAllPoints, o)
                    pcall(o.SetPoint, o, p, uiRelName(rel), rp, (tonumber(x) or 0) * k, (tonumber(y) or 0) * k)
                    pcall(o.SetWidth, o, (tonumber(w) or 0) * k)
                    pcall(o.SetHeight, o, (tonumber(h) or 0) * k)
                    n = n + 1
                  end
                else
                  miss = miss + 1
                end
              end
            end
          end
          local mt = {}
          local function PM2(t) mt[table.getn(mt) + 1] = tostring(t) P(t) end
          PM2("maptile 试修 build=" .. DBX_BUILD .. " 模式=" .. tostring(mode) .. " 父帧 es=" .. string.format("%.3f", es))
          PM2("已处理 " .. tostring(n) .. " 个纹理（跳过底瓦片 " .. tostring(skipTiles) .. " 个；几何读不到 " .. tostring(miss) .. " 个）")
          PM2(mode == "restore" and "已按存档原始值还原（原值在 EH_DEBUGBOX_CFG.maptileOrig）"
            or ("折算系数 k=" .. string.format("%.3f", k or 1) .. " —— **真机眼看是否对齐**；不对就换另一种：/edb maptile fit s 或 /edb maptile fit d；都不行 /edb maptile restore"))
          PM2("注意：换区域/改地图缩放后客户端会重排这些纹理 ⇒ 需要重跑本命令；若要自动化再做（先把方向定下来）")
          EH_DEBUGBOX_CFG.maptileFix = mt
          EH_DEBUGBOX_CFG.maptileFixAt = (type(GetTime) == "function") and tostring(GetTime()) or "?"
        end
        return
      end
      local fr = _G["WorldMapDetailFrame"]
      -- ★★★1.74.34-18b 结果**落存档**（用户跑完探针后 AI 直接读文件，不必抄屏）：
      --   落点 EH_DEBUGBOX_CFG.maptile（数组，逐行文本）+ maptileAt（时间）；/reload 后落盘。
      local MT = {}
      local function PM(t) MT[table.getn(MT) + 1] = tostring(t) P(t) end
      PM("地图瓦片探针 build=" .. DBX_BUILD)
      if not (type(fr) == "table" or type(fr) == "userdata") then
        PM("|cffff6060WorldMapDetailFrame 不存在|r")
      else
        local function fmtN(v) return (tonumber(v) and string.format("%.0f", v)) or "?" end
        local function rectOf(o)
          local okl, l = pcall(o.GetLeft, o)
          local okb, b = pcall(o.GetBottom, o)
          local okr, r = pcall(o.GetRight, o)
          local okt, t = pcall(o.GetTop, o)
          if okl and okb and okr and okt and tonumber(l) and tonumber(b) and tonumber(r) and tonumber(t) then
            return tonumber(l), tonumber(b), tonumber(r), tonumber(t)
          end
        end
        local function esOf(o)
          if type(o.GetEffectiveScale) == "function" then
            local ok, v = pcall(o.GetEffectiveScale, o)
            if ok and tonumber(v) then return tonumber(v) end
          end
        end
        local fl, fb, frr, ft = rectOf(fr)
        local fes = esOf(fr)
        local fsc = nil
        if type(fr.GetScale) == "function" then local ok, v = pcall(fr.GetScale, fr) if ok and tonumber(v) then fsc = tonumber(v) end end
        PM(string.format("父帧 屏[%s,%s ~ %s,%s] es=%s scale=%s", fmtN(fl), fmtN(fb), fmtN(frr), fmtN(ft),
          fes and string.format("%.3f", fes) or "?", fsc and string.format("%.3f", fsc) or "?"))
        -- ★父帧锚点也记一行（判断父帧自己是逻辑口径还是屏幕口径）
        do
          local okp, p, rel, rp, x, y = pcall(fr.GetPoint, fr, 1)
          if okp and p then
            PM(string.format("父帧锚=%s/%s/%s(%s,%s)", tostring(p), tostring(uiRelName(rel)), tostring(rp), fmtN(x), fmtN(y)))
          end
        end
        local regs = {}
        if type(fr.GetRegions) == "function" then
          local ok, t = pcall(function() return { fr:GetRegions() } end)
          if ok then regs = t end
        end
        local idx, nInChain, nAbsolute = 0, 0, 0
        local firstK = nil
        for _, o in ipairs(regs) do
          if o and nodeType(o) == "Texture" then
            idx = idx + 1
            local nm = uiFrameName(o)
            local lw, lh = nil, nil
            if type(o.GetWidth) == "function" then local ok, v = pcall(o.GetWidth, o) if ok and tonumber(v) then lw = tonumber(v) end end
            if type(o.GetHeight) == "function" then local ok, v = pcall(o.GetHeight, o) if ok and tonumber(v) then lh = tonumber(v) end end
            local l, b, r, t = rectOf(o)
            local sw = (l and r) and (r - l) or nil
            local sh = (b and t) and (t - b) or nil
            local k = (lw and lw > 1 and sw) and (sw / lw) or nil
            local oes = esOf(o)
            if k then
              if math.abs(k - 1) <= 0.05 then nAbsolute = nAbsolute + 1 else nInChain = nInChain + 1 end
              if not firstK and idx <= 4 then firstK = k end
            end
            local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
            -- ★落档时**不截断**（全部纹理都记，供 AI 做网格推算）；聊天框仍只打前 22 行
            local line = string.format("#%d %s 逻辑=%sx%s 屏=%sx%s k=%s es=%s 屏[%s,%s~%s,%s] 锚=%s/%s/%s(%s,%s)",
              idx, tostring(nm or "?"), fmtN(lw), fmtN(lh), fmtN(sw), fmtN(sh),
              k and string.format("%.3f", k) or "?", oes and string.format("%.3f", oes) or "?",
              fmtN(l), fmtN(b), fmtN(r), fmtN(t),
              tostring(p or "?"), tostring(uiRelName(rel)), tostring(rp or "?"), fmtN(x), fmtN(y))
            MT[table.getn(MT) + 1] = line
            if idx <= 22 then P(line) end
          end
        end
        local sum = string.format("合计 %d 个 Texture：吃父级缩放（k≈es）%d 个 · 不吃（k≈1）%d 个 · 首个基准 k=%s · 父帧 es=%s",
          idx, nInChain, nAbsolute, firstK and string.format("%.3f", firstK) or "?",
          fes and string.format("%.3f", fes) or "?")
        PM(sum)
        PM("判读：k≈es ⇒ 在缩放链里（只需按屏幕差改锚点偏移）；k≈1 且 es≠1 ⇒ **不吃父级缩放**（要自己写屏幕尺寸与屏幕位置）；" ..
          "锚点若是 WorldMapDetailTileN/角 ⇒ 相对兄弟瓦片；若是 WorldMapDetailFrame/TOPLEFT ⇒ 相对父帧。")
        PM("结果已写入存档 EH_DEBUGBOX_CFG.maptile（共 " .. tostring(table.getn(MT)) .. " 行）→ 请 /reload 落盘，AI 直接读文件")
      end
      EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
      EH_DEBUGBOX_CFG.maptile = MT
      EH_DEBUGBOX_CFG.maptileAt = (type(GetTime) == "function") and tostring(GetTime()) or "?"
    elseif msg == "tiles" or msg == "贴图" then
      -- ★1.74.34-9 贴图载入侦测自查（与缩放闸门同一份判据 uiDetailTilesReady）
      local fr = _G["WorldMapDetailFrame"]
      local r = uiDetailTilesReady(fr)
      local nTex, nEmpty = 0, 0
      if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
        local ok, regs = pcall(function() return { fr:GetRegions() } end)
        if ok then
          for _, o in ipairs(regs) do
            if o and type(o.GetObjectType) == "function" then
              local okT, t = pcall(o.GetObjectType, o)
              if okT and t == "Texture" then
                nTex = nTex + 1
                local okG, tex = pcall(o.GetTexture, o)
                if not (okG and type(tex) == "string" and tex ~= "") then nEmpty = nEmpty + 1 end
              end
            end
          end
        end
      end
      P(string.format("贴图载入侦测 build=%s：WorldMapDetailFrame 纹理 %d 张（未载入 %d）⇒ %s；缩放排队中 %d 条",
        DBX_BUILD, nTex, nEmpty,
        (r == true and "已载入完成（可直接缩放）" or (r == false and "未载完（缩放会排队等待）" or "判不出/不门控")),
        table.getn(uiScaleWait.items)))
    elseif msg == "scan" then
      uiBuild()
      uiScanAll()
    elseif msg == "kids" or string.find(msg, "^kids%s") == 1 or msg == "子层" or string.find(msg, "^子层%s") == 1 then
      -- ★★★1.74.34-7「层下面明明有贴图、扫描却看不到子元素」的裸探针（用户问 WorldMapDetailFrame）：
      --   **绕过全部过滤器**（不看树、不看「只显示有名/仅显示中/层深」）——直接对目标帧裸调
      --   GetRegions / GetChildren，逐个报 类型/名字（含合成名标注）/显隐/尺寸。一次分清三种可能：
      --   ①有 region 但被「隐藏无名」滤掉 ②本客户端引擎内绘、Lua 拿不到 ③子元素全报「隐」被「仅显示中」挡住。
      --   目标选取：当前选中的层 > /edb kids <路径关键字> > 默认 WorldMapDetailFrame。
      local kw = string.match(msg, "^%S+%s+(.+)$")
      local fr, frPath = nil, nil
      for _, e in ipairs(ui.entries or {}) do
        if (ui.sel or {})[e.path] then fr, frPath = e.f, e.path break end
      end
      if not fr and kw then
        local lk = string.lower(kw)
        for _, e in ipairs(ui.entries or {}) do
          if string.find(string.lower(e.path), lk, 1, true) then fr, frPath = e.f, e.path break end
        end
      end
      if not fr then
        fr = _G["WorldMapDetailFrame"]
        frPath = "WorldMapDetailFrame(全局)"
      end
      P("子元素探针 build=" .. DBX_BUILD .. " · 目标=" .. tostring(frPath) .. "（原始清单，不过滤）")
      if not (type(fr) == "table" or type(fr) == "userdata") then
        P("|cffff6060目标帧不存在|r")
      else
        local function dbxDumpObjs(tag, objs, total)
          P(tag .. " 共 " .. total .. " 个：")
          for i = 1, math.min(total, 24) do
            local o = objs[i]
            if o == nil then
              P("  #" .. i .. " nil")
            else
              local t = nodeType(o)
              local nm = uiFrameName(o) or "（无名）"
              local fake = uiNameLooksFake(nm) and "|cffff8800（合成名）|r" or ""
              local sh = "?"
              if type(o.IsShown) == "function" then local okS, v = pcall(o.IsShown, o) if okS then sh = v and "显" or "隐" end end
              local w2, h2 = "?", "?"
              if type(o.GetWidth) == "function" then local okW, v = pcall(o.GetWidth, o) if okW and tonumber(v) then w2 = string.format("%.0f", v) end end
              if type(o.GetHeight) == "function" then local okH, v = pcall(o.GetHeight, o) if okH and tonumber(v) then h2 = string.format("%.0f", v) end end
              -- ★可写性探测：本客户端遍历返回的是**只读包装**（UnrealQuest 实测）⇒ 写方法可能不存在
              local wr = (type(o.SetScale) == "function") and "可写" or "|cffff6060只读包装|r"
              P(string.format("  #%d [%s] %s%s %s %sx%s %s", i, t, tostring(nm), fake, sh, w2, h2, wr))
              -- ★★1.74.34-8 定位行（治「缩放后贴图定位不准」取证）：
              --   锚点（相对谁、偏移多少）+ **实测屏幕矩形** + 有效缩放 —— 与父帧矩形对不上 = 定位口径不同。
              local pos = {}
              if type(o.GetEffectiveScale) == "function" then
                local okE, v = pcall(o.GetEffectiveScale, o)
                if okE and tonumber(v) then pos[table.getn(pos) + 1] = string.format("es=%.2f", v) end
              end
              if type(o.GetLeft) == "function" then
                local okL, l = pcall(o.GetLeft, o)
                local okB, b = pcall(o.GetBottom, o)
                local okR2, r2 = pcall(o.GetRight, o)
                local okT2, t2 = pcall(o.GetTop, o)
                if okL and okB and okR2 and okT2 and tonumber(l) and tonumber(b) and tonumber(r2) and tonumber(t2) then
                  pos[table.getn(pos) + 1] = string.format("屏[%.0f,%.0f~%.0f,%.0f]", l, b, r2, t2)
                end
              end
              if type(o.GetPoint) == "function" then
                local okP, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
                if okP and p then
                  pos[table.getn(pos) + 1] = string.format("锚=%s/%s/%s(%.0f,%.0f)",
                    tostring(p), tostring(uiRelName(rel)), tostring(rp), tonumber(x) or 0, tonumber(y) or 0)
                end
              end
              if table.getn(pos) > 0 then P("      " .. table.concat(pos, " · ")) end
            end
          end
          if total > 24 then P("  …（其余 " .. (total - 24) .. " 个省略）") end
        end
        -- 父帧自己也来一行定位（贴图矩形该落在它里面；落不在 = 定位口径不同）
        if type(fr.GetLeft) == "function" then
          local okL, l = pcall(fr.GetLeft, fr)
          local okB, b = pcall(fr.GetBottom, fr)
          local okR2, r2 = pcall(fr.GetRight, fr)
          local okT2, t2 = pcall(fr.GetTop, fr)
          local okE, es = pcall(fr.GetEffectiveScale, fr)
          if okL and okB and okR2 and okT2 and tonumber(l) and tonumber(b) and tonumber(r2) and tonumber(t2) then
            P(string.format("父帧矩形 屏[%.0f,%.0f~%.0f,%.0f] es=%s", l, b, r2, t2, (okE and tonumber(es)) and string.format("%.2f", es) or "?"))
          end
        end
        if type(fr.GetRegions) == "function" then
          local okR, regs = pcall(function() return { fr:GetRegions() } end)
          if okR then
            local total = 0
            for _ in ipairs(regs) do total = total + 1 end
            dbxDumpObjs("① GetRegions（贴图/字体串）", regs, total)
          else
            P("① GetRegions 调用抛错：" .. tostring(regs))
          end
        else
          P("① 该帧没有 GetRegions")
        end
        if type(fr.GetChildren) == "function" then
          local okC, kids = pcall(function() return { fr:GetChildren() } end)
          if okC then
            local total = 0
            for _ in ipairs(kids) do total = total + 1 end
            dbxDumpObjs("② GetChildren（子帧）", kids, total)
          else
            P("② GetChildren 调用抛错：" .. tostring(kids))
          end
        else
          P("② 该帧没有 GetChildren")
        end
        P("判读：①有贴图条目 ⇒ 是被「只显示有名」滤掉的（关掉它树里就有）；①②都 0 ⇒ 引擎内绘 Lua 拿不到（贴图缩放不跟手同根）；条目全「隐」⇒ 被「仅显示中」挡住；「只读包装」⇒ 对扫描到的对象直接 SetScale 无效，要按名字解析回真对象再写。")
        P("定位判读：贴图「屏[...]」应整齐落在父帧矩形内（179×179 瓦片相邻无缝）；整体平移出界 ⇒ 高亮/定位走的是**逻辑坐标**（没乘父级缩放），渲染走的是缩放后坐标——这不是贴图错了，是定位口径没跟缩放；逐张散乱 ⇒ 引擎按自己的布局摆瓦片，Lua 锚点说了不算。")
      end
    elseif msg == "twprobe" or msg == "箭头探针" then
      -- ★★★1.74.34 折叠开关一键取证（同一现象第 3 轮 → 铁律 4 取证模式：能做成命令就不让用户手工复现）。
      --   一屏定案四件事：①跑的是哪个构建（旧构建 = 请先 /reload）②点击路径上的真实对象是什么
      --   ③ rawget / 字段读在本机的真实表现 ④ 真实 OnClick 模拟点击的成败与折叠状态翻转。
      uiBuild()
      P("折叠开关探针 build=" .. DBX_BUILD)
      P("① uiRowEntry=" .. (type(uiRowEntry) == "function" and "在（修复版）" or "|cffff6060不在 —— 跑的是旧构建，请 /reload！|r"))
      local row, e = nil, nil
      for r = 1, (ui.rows or 0) do
        local rw = ui.rowW and ui.rowW[r]
        if rw and rw.tw then
          local okS, sh = pcall(rw.tw.IsShown, rw.tw)
          if okS and sh then row = rw break end
        end
      end
      if not row then
        P("② 没有显示中的折叠开关（列表里没有父节点：先开地图再 /edb scan，或把「层深」调大后再试）")
      else
        e = uiRowEntry(row)
        P("② 目标行=" .. tostring(e and e.path or "|cffff6060<这一行没有条目>|r"))
        local okR, vR = pcall(rawget, row, "entry")
        local okF, vF = pcall(function() return row.entry end)
        P(string.format("③ rawget: %s · 字段读: %s（值类型 %s）· type(row)=%s",
          okR and ("成功·值=" .. type(vR)) or "抛错(已捕获)",
          okF and "成功" or "抛错(已捕获)", type(vF), type(row)))
        local fn = nil
        if type(row.tw.GetScript) == "function" then
          local okG, g = pcall(row.tw.GetScript, row.tw, "OnClick")
          if okG then fn = g end
        end
        if type(fn) ~= "function" then
          P("④ |cffff6060折叠开关没挂 OnClick！|r")
        else
          local path = e and e.path or nil
          local before = (path and ui.treeCollapsed and ui.treeCollapsed[path]) and true or false
          local okC, errC = pcall(fn)
          local after = (path and ui.treeCollapsed and ui.treeCollapsed[path]) and true or false
          if okC then
            P(string.format("④ 模拟点击: 成功 · 折叠 %s → %s（已再点一次还原）", tostring(before), tostring(after)))
            pcall(fn) -- 还原视图
          else
            P("④ 模拟点击: |cffff6060报错|r: " .. tostring(errC) .. "（把这一行原样发我）")
          end
        end
      end
      P("—— 探针完（把这屏结果发我；存档键 EH_DEBUGBOX_CFG 无需动）——")
    elseif string.match(msg, "^sizef%s+%d+%s+%d+") then
      local w, h = string.match(msg, "^sizef%s+(%d+)%s+(%d+)")
      sizeApply(tonumber(w), tonumber(h), true)
    elseif string.match(msg, "^size%s+%d+%s+%d+") then
      local w, h = string.match(msg, "^size%s+(%d+)%s+(%d+)")
      sizeApply(tonumber(w), tonumber(h), false)
    elseif msg == "sizeoff" then
      sizeOff()
    elseif string.match(msg, "^fit%s*[%d%.]+") then
      fitApply(tonumber(string.match(msg, "^fit%s*([%d%.]+)")))
    elseif string.match(msg, "^scalef%s*[%d%.]+") then
      scaleCoords(tonumber(string.match(msg, "^scalef%s*([%d%.]+)")), true)
    elseif string.match(msg, "^scale%s*[%d%.]+") then
      scaleCoords(tonumber(string.match(msg, "^scale%s*([%d%.]+)")), false)
    elseif string.match(msg, "^mix%s*[%d%.]+") then
      local fa = tonumber(string.match(msg, "^mix%s*([%d%.]+)"))
      fitApply(fa)
      scaleCoords(fa, false)
      P("混合试验：尺寸 + 三帧 SetScale 都已打 —— 看悬停")
    elseif string.match(msg, "^deep%s*[%d%.]+") then
      scaleDeep(tonumber(string.match(msg, "^deep%s*([%d%.]+)")))
    elseif string.match(msg, "^allnodes%s*[%d%.]+") then
      scaleDeep(tonumber(string.match(msg, "^allnodes%s*([%d%.]+)")))
    elseif string.match(msg, "^t%s+%d+%s+off") then
      local i = tonumber(string.match(msg, "^t%s+(%d+)"))
      if type(nodes) == "table" and nodes[i] then
        local nSS = uiField(nodes[i].f, "SetScale") -- ★1.74.34-26 安全读口
  if type(nSS) == "function" then pcall(nSS, nodes[i].f, 1) end
        if scaledNodes then scaledNodes[i] = nil end
        P("#" .. tostring(i) .. " " .. nodes[i].n .. " 回 1")
      else
        P("先跑 /edb list")
      end
    elseif string.match(msg, "^t%s+%d+%s+[%d%.]+") then
      local i, s2 = string.match(msg, "^t%s+(%d+)%s+([%d%.]+)")
      scaleNode(tonumber(i), tonumber(s2))
    elseif msg == "watch" then
      watch.on = not watch.on
      if watch.on then
        if watchEnsure() then
          P("悬停对照浮字：开（开图后看地图顶部三合一信息行）")
        else
          watch.on = false
          P("浮字建不起来（WorldMapFrame 不可用）")
        end
      else
        if watch.label then pcall(watch.label.SetText, watch.label, "") end
        P("悬停对照浮字：关")
      end
    elseif msg == "all" and s then
      setAll(s)
    elseif (key == "" or key == nil) and s then
      setScale("frame", s)
    elseif (key == "b" or key == "d") and s then
      setScale(key, s)
    else
      P("/edb 0.7=缩外框 · /edb b 0.7=缩画布 · /edb d 0.7=缩Detail · /edb all 0.7=全缩 · /edb off=回1 · /edb watch=悬停对照浮字")
      P("/edb list=打印全部层编号 · /edb t 编号 0.7=只缩那一层 · /edb t 编号 off=那一层回1")
      P("/edb grab=★全自动采集（自开图→扫描→自关图→落盘）· /edb deep 0.7=全层同缩 · /edb off=全部回1")
      P("/edb mouse=★鼠标开关点名（谁吃鼠标/谁吃滚轮，判『谁抢了悬停』）")
      P("/edb size 820 546=★改画布尺寸（渲染+命中一起变的可能路线）· /edb sizef 820 546=连外框一起 · /edb sizeoff=原尺寸还原")
      P("/edb fit 0.7=按系数改三个坐标链帧尺寸 · /edb scale 0.7=三个帧 SetScale · /edb scalef 0.7=+外框 · /edb mix 0.7=尺寸+缩放同时")
      P("/edb ui=★图层调试面板（打开面板；列表是可折叠的树：行左侧 ▼/▶ 折叠 · 顶栏「层深」= 展开到第 N 层）")
      P("/edb named=无名层过滤诊断（条目/有名/无名/列表条数 + 前 5 条实证）")
      P("/edb tree=★图层树诊断 · /edb tree all=全部展开 · /edb tree none=全部折叠（折叠状态落存档）")
      P("/edb bars=★框体探针（动作条1~4 + 队伍/团队 + **被动打开层**：公会/属性/拍卖/邮箱/任务/技能树/训练师/交易技能/商人/好友）· 先报队友/团员数，再逐候选报在不在 + 关键词全 _G 扫 + **顶层大帧兜底**（父级 UIParent/WorldFrame 且 ≥200×150）· 结果落存档 dragBars（cands/groups/top/found）· 别名 /edb frames · ★子插件没载入时用主插件那条：/eh go 框体探针")
    end
  end
end

P("EH_DebugBox 纯缩放试验已载入：/edb 查看用法（/reload 还原一切）")

-- ★★★1.74.31 测试读值口（与主插件 EVAL_*_TEST_* 同族，见 CLAUDE.md §5.3「测试够不着生产 local ⇒ 加钩子」）：
--   面板状态 `ui` 与三个判据函数都是**文件内 local**，测试桩取不到 ⇒「列表到底列了什么」这条行为
--   一直没有断言（用户截图的现象就长在这个盲区里）。这里只**交出去**、不改任何行为：
--   测试走真实入口（/edb ui → uiToggle → uiRefresh、真实 OnClick），再用这些读值口读结果。
--   ★交给测试的是**真函数本身**（不是复刻一份映射逻辑），所以「读值口与生产同源」。
function EVAL_DBX_TEST_UI()
  return { ui = ui, namedCounts = uiNamedCounts, filtered = uiFiltered, entryNamed = uiEntryNamed,
    -- ★★★1.74.31 第二步（可折叠树）：交给测试的仍是**真函数本身**（不是复刻一份映射逻辑）
    entryDepth = uiEntryDepth, treePass = uiTreePass, treeHidden = uiTreeHidden, treeToggle = uiTreeToggle,
    treeExpandTo = uiTreeExpandTo, treeFoldCount = uiTreeCollapsedCount, depthApply = uiDepthApply,
    save = uiSaveSettings, load = uiLoadSettings }
end
