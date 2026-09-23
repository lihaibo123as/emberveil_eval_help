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
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cff66ccff[缩放试验]|r " .. tostring(msg))
  end
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

local function nodeName(v)
  if type(v.GetName) == "function" then
    local ok, n = pcall(v.GetName, v)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return "?"
end

local function nodeType(v)
  if type(v.GetObjectType) == "function" then
    local ok, t = pcall(v.GetObjectType, v)
    if ok then return tostring(t) end
  end
  return "?"
end

local function scanTree(f, path, depth)
  if depth > 4 then return end
  if type(f.GetRegions) == "function" then
    local rr = { pcall(f.GetRegions, f) }
    if rr[1] then
      for i = 2, table.getn(rr) do
        local r = rr[i]
        if r then
          table.insert(nodes, { f = r, n = path .. "/region:" .. nodeType(r) })
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
          table.insert(nodes, { f = c, n = path .. "/" .. nm })
          scanTree(c, path .. "/" .. nm, depth + 1)
        end
      end
    end
  end
end

local function buildNodes()
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then return nil end
  if type(ShowUIPanel) == "function" then pcall(ShowUIPanel, wm) end -- 开图让懒加载子帧就位
  nodes = {}
  table.insert(nodes, { f = wm, n = "WorldMapFrame(本体)" })
  scanTree(wm, "WorldMapFrame", 1)
  return nodes
end

-- ★顶层相关帧点名采集（不在 WorldMapFrame 树里的：黑幕/容器/标签/定位导引等）
local TOP = {
  "WorldMapFrame", "WorldMapDetailFrame", "WorldMapButton", "WorldMapPositioningGuide",
  "WorldMapTooltip", "BlackoutWorld", "WorldMapBlackout",
  "WorldMapFrameAreaFrame", "WorldMapFrameAreaLabel", "WorldMapFrameAreaDescription",
  "WorldMapPlayer", "WorldMapCorpse", "MinimapCluster", "WorldFrame", "UIParent",
}

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
  return {
    i = i, path = l.n, type = nodeType(f), w = w, h = h,
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
        rec.scaleable and "可缩" or "不可缩", rec.scale, rec.level, rec.strata, rec.parent))
    end
  end
  EH_DEBUGBOX_CFG.layers = dump
  EH_DEBUGBOX_CFG.n = table.getn(dump)

  -- 顶层相关帧（不在树里）
  local top = {}
  for _, nm in ipairs(TOP) do
    local f = _G[nm]
    if type(f) == "table" or type(f) == "userdata" then
      local rec = nodeInfo({ f = f, n = nm }, 0)
      table.insert(top, rec)
      P(string.format("[顶层] %s [%s] %sx%s %s scale=%s lv=%s %s 父=%s",
        nm, rec.type, rec.w, rec.h, rec.scaleable and "可缩" or "不可缩",
        rec.scale, rec.level, rec.strata, rec.parent))
    else
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
  SM.lines = {}
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
    local nm = nil
    if type(fr.GetName) == "function" then local ok, v = pcall(fr.GetName, fr) if ok then nm = v end end
    if type(nm) == "string" and nm ~= "" then st.named = st.named + 1 else st.unnamed = st.unnamed + 1 end
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
  flushStore()
end

-- ===== /edb ui：图层调试面板（地图右侧入口）=====
-- 用户要求：右侧按钮 → 点击下拉/展开图层信息 → 支持过滤 → 支持多选 → 选中即设缩放等级，方便逐个调试。
-- 设计纪律（照本项目 UI 配方）：
--   · 纯色件一律 WHITE8X8 + SetVertexColor（本客户端 Texture:SetAlpha 是变暗不是透明）
--   · 无原生下拉 → 分类用按钮、无原生滑条 → 用 [-] 值 [+]
--   · EditBox 疑似不渲染 → 过滤框旁边加**回声行** FontString 保底
--   · 层级：面板 DIALOG/220 级（不压过全局件），挂 WorldMapFrame 下随图显隐
local ui = {
  root = nil, built = false, sel = {}, off = 0, filter = "", cat = 0,
  rows = 12, entries = nil, rowW = {}, value = 0.70, alphaValue = 1.00,
  xVal = 0, yVal = 0, -- ★用户要求：x,y 坐标设置（相对现有锚点的偏移增量）
  wVal = 700, hVal = 600, -- ★用户要求：宽/高设置，默认 700×600、步进 10
  cust = {}, colorOf = {}, -- ★需求 3/5：自定义记账（账号级存档）+ 每层颜色
  origDefaults = {}, -- ★「从未自定义时」观测到的原始尺寸（清理自定义时的兜底依据）
  onlyShown = true, -- ★默认只看「当前打开（显示中）」的层
  bigOnly = true,   -- ★★默认只显示尺寸 ≥500×500 的层（把图钉/小标记全滤掉，用户要求）
}

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

-- ===== 层高亮框（用户要求：列表行获取焦点时，给对应层描外边框高亮）=====
-- 选中 = 金色描边（可同时多个，池 16 个）；悬停 = 红色描边（单例，最后画、层级最高）
-- ★挂 WorldMapFrame + FULLSCREEN_DIALOG（低于面板 500，高于地图 FULLSCREEN），关图时随父一起隐藏
local hlPool, hlHover = {}, nil

local function hlMake(parent, level, r, g, b)
  local f = CreateFrame("Frame", nil, parent)
  pcall(f.SetFrameStrata, f, "FULLSCREEN_DIALOG")
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
  local parent = _G["WorldMapFrame"] or _G["UIParent"]
  hlPool[i] = hlMake(parent, 520 + i, 1, 0.82, 0.15)
  return hlPool[i]
end

-- 把描边框贴到某个层上（-2/+2 外扩，便于看清边界）
local function hlAttach(hf, target)
  if not hf or not target then return false end
  if type(hf.ClearAllPoints) ~= "function" or type(hf.SetPoint) ~= "function" then return false end
  pcall(hf.ClearAllPoints, hf)
  local ok1 = pcall(hf.SetPoint, hf, "TOPLEFT", target, "TOPLEFT", -2, 2)
  local ok2 = pcall(hf.SetPoint, hf, "BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
  if not (ok1 and ok2) then return false end
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
  local parent = _G["WorldMapFrame"] or _G["UIParent"]
  if not hlHover then hlHover = hlMake(parent, 560, 1, 0.25, 0.25) end
  hlAttach(hlHover, target)
end

local function hlHideHover()
  if hlHover then pcall(hlHover.Hide, hlHover) end
end

-- ★面板/高亮/入口的宿主帧：**不能挂 UIParent**（开全屏地图会被隐藏 → 面板跟着消失）。
--   WorldFrame 在开图时仍显示（probe5 实测 IsShown=true），且关图后也一直在。
local function uiHost()
  local wf = _G["WorldFrame"]
  if type(wf) == "table" or type(wf) == "userdata" then return wf end
  return _G["UIParent"]
end

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
  idx = best[math.random(table.getn(best))]
  ui.colorOf[path] = idx
  local c = HL_COLORS[idx] or HL_COLORS[1]
  return c[1], c[2], c[3]
end

-- ★需求 5：自定义设置**账号级存档**（SavedVariables）+ 定时器兜底重设
local function uiCustSave()
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  EH_DEBUGBOX_CFG.cust = ui.cust
  EH_DEBUGBOX_CFG.colors = ui.colorOf
end

local function uiCustLoad()
  EH_DEBUGBOX_CFG = EH_DEBUGBOX_CFG or {}
  ui.cust = (type(EH_DEBUGBOX_CFG.cust) == "table") and EH_DEBUGBOX_CFG.cust or {}
  ui.colorOf = (type(EH_DEBUGBOX_CFG.colors) == "table") and EH_DEBUGBOX_CFG.colors or {}
  local n = 0
  for _ in pairs(ui.cust) do n = n + 1 end
  return n
end

-- 路径 → 帧（存档只存路径；顶层用 [顶层] 名；树内按名字逐段走；region/无名节点无法解析→如实跳过）
local function uiResolvePath(path)
  if type(path) ~= "string" then return nil end
  if string.sub(path, 1, 6) == "[顶层]" then
    local nm = string.match(path, "^%[顶层%]%s*(.+)$")
    local f = nm and _G[nm]
    if type(f) == "table" or type(f) == "userdata" then return f end
    return nil
  end
  local f = _G["WorldMapFrame"]
  if not (type(f) == "table" or type(f) == "userdata") then return nil end
  local first = true
  for seg in string.gmatch(path, "([^/]+)") do
    if first then
      first = false -- 第一段就是 WorldMapFrame 根
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

-- ★需求 5 的兜底：定时器把存档里的自定义设置**重设**到对应层（漂移/重载后自动恢复）
local function uiCustReapply(quiet)
  local n, miss = 0, 0
  for path, c in pairs(ui.cust or {}) do
    local f = uiResolvePath(path)
    if f then
      local s = c.set or {}
      if s.scale and type(f.SetScale) == "function" then
        local ok, v = pcall(f.GetScale, f)
        if not (ok and tonumber(v) and math.abs(v - s.scale) < 0.001) then pcall(f.SetScale, f, s.scale) n = n + 1 end
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
    if ok and p then c.opt = { p, rel, relp, x, y } end
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
  if table.getn(t) == 0 then return "自定义" end
  return table.concat(t, " ")
end

-- 地图标记池（彩色描边 + 左上角信息文本）——挂 uiHost()，FULLSCREEN_DIALOG
local uiMarks = {}
local uiMarkSavePos -- ★前向声明（拖拽柄脚本要用；定义在下方 → 不前置声明就会绑成全局 nil）

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
  local lbl = CreateFrame("Frame", nil, host)
  pcall(lbl.SetFrameStrata, lbl, "FULLSCREEN_DIALOG")
  pcall(lbl.SetFrameLevel, lbl, 560 + i)
  pcall(lbl.SetWidth(240))
  pcall(lbl.SetHeight(16))
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
  pcall(fs.SetPoint, fs, "LEFT", lbl, "LEFT", 16, 0) -- 文字在拖拽柄右边
  pcall(fs.SetJustifyH, fs, "LEFT")
  -- ★用户（2）：信息条左侧**拖拽柄**（Button + warm-up 两步配方；Frame 的 OnDragStart 本客户端不触发）
  local self = {}
  local hb = CreateFrame("Button", nil, lbl)
  hb:SetWidth(13) hb:SetHeight(13)
  hb:SetPoint("LEFT", lbl, "LEFT", 1, 0)
  if type(hb.EnableMouse) == "function" then pcall(hb.EnableMouse, hb, true) end
  if type(hb.RegisterForDrag) == "function" then pcall(hb.RegisterForDrag, hb, "LeftButton") end
  local hbTex = hb:CreateTexture(nil, "BACKGROUND")
  hbTex:SetAllPoints(hb)
  uiSolid(hbTex, 0.85, 0.80, 0.30, 0.95)
  local hbTxt = hb:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(hbTxt.SetFontObject, hbTxt, GameFontNormal) end
  pcall(hbTxt.SetPoint, hbTxt, "CENTER", hb, "CENTER", 0, 0)
  pcall(hbTxt.SetText, hbTxt, "拖")
  hb:SetScript("OnDragStart", function()
    pcall(lbl.SetMovable, lbl, true)
    pcall(lbl.StartMoving, lbl) -- warm-up 两步
    pcall(lbl.StopMovingOrSizing, lbl)
    pcall(lbl.StartMoving, lbl)
  end)
  hb:SetScript("OnDragStop", function()
    pcall(lbl.StopMovingOrSizing, lbl)
    if self.path then uiMarkSavePos(self.path, lbl) end
  end)
  bd:Hide()
  lbl:Hide()
  self.bd, self.edges, self.lbl, self.fs, self.hb = bd, edges, lbl, fs, hb
  uiMarks[i] = self
  return self
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
    P("自定义信息位置已记忆：" .. tostring(path) .. string.format("（偏移 %.0f,%.0f）", c.lx, c.ly))
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


local function uiBuildEntries()
  if not nodes then buildNodes() end
  ui.entries = {}
  local no = 0
  for i, nd in ipairs(nodes or {}) do
    no = no + 1
    table.insert(ui.entries, { path = nd.n, f = nd.f, scaleable = (type(nd.f.SetScale) == "function"), i = i, no = no })
  end
  for _, nm in ipairs(TOP) do
    local f = _G[nm]
    if type(f) == "table" or type(f) == "userdata" then
      no = no + 1
      table.insert(ui.entries, { path = "[顶层] " .. nm, f = f, scaleable = (type(f.SetScale) == "function"), top = true, no = no })
    end
  end
  -- 存档里已自定义的层：即使当前过滤/树里没有，也让颜色与编号沿用
  for path in pairs(ui.cust or {}) do
    uiColorFor(path)
  end
  return ui.entries
end

local function uiFiltered()
  if not ui.entries then uiBuildEntries() end
  local out = {}
  local f = string.lower(ui.filter or "")
  for _, e in ipairs(ui.entries) do
    local okCat = true
    if ui.cat == 1 then
      okCat = (string.find(e.path, "WorldMap", 1, true) ~= nil) and (string.find(e.path, "UnrealQuest", 1, true) == nil)
    elseif ui.cat == 2 then
      okCat = (string.find(e.path, "UnrealQuest", 1, true) ~= nil)
    elseif ui.cat == 3 then
      okCat = (not e.scaleable)
    elseif ui.cat == 4 then
      okCat = (e.top == true)
    end
    -- ★用户要求：尺寸 <500×500 的（图钉/小标记）过滤掉；尺寸读不到的保留（不误杀）
    local okBig = (not ui.bigOnly) or (not (e.w and e.h)) or (e.w >= 500 and e.h >= 500)
    local okShown = (not ui.onlyShown) or (e.shown == true)
    local okTxt = (f == "") or (string.find(string.lower(e.path), f, 1, true) ~= nil)
    if okCat and okShown and okBig and okTxt then table.insert(out, e) end
  end
  return out
end

local uiRefresh -- 前向声明

-- 每次刷新重读「显示中 / 当前 scale / 当前 alpha」（实时扫描）
local function uiScanState()
  if not ui.entries then return end
  for _, e in ipairs(ui.entries) do
    local shown = false
    if type(e.f.IsShown) == "function" then
      local ok, v = pcall(e.f.IsShown, e.f)
      shown = (ok and v) and true or false
    end
    e.shown = shown
    local sc, al = nil, nil
    if type(e.f.GetScale) == "function" then
      local ok, v = pcall(e.f.GetScale, e.f)
      if ok and tonumber(v) then sc = v end
    end
    if type(e.f.GetAlpha) == "function" then
      local ok, v = pcall(e.f.GetAlpha, e.f)
      if ok and tonumber(v) then al = v end
    end
    e.scale = sc
    e.alpha = al
    -- ★实时读尺寸（≥500×500 过滤器与列表显示都要）
    local w, h = nil, nil
    if type(e.f.GetWidth) == "function" then
      local ok, v = pcall(e.f.GetWidth, e.f)
      if ok and tonumber(v) then w = tonumber(v) end
    end
    if type(e.f.GetHeight) == "function" then
      local ok, v = pcall(e.f.GetHeight, e.f)
      if ok and tonumber(v) then h = tonumber(v) end
    end
    e.w, e.h = w, h
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
    if type(e.f.GetParent) == "function" then
      local okp, p = pcall(e.f.GetParent, e.f)
      if okp and p and type(p.GetName) == "function" then
        local okn, pn = pcall(p.GetName, p)
        if okn and type(pn) == "string" and pn ~= "" then par = pn end
      elseif okp and p then
        par = "（无名父级）"
      end
    end
    if e.top then par = e.topParent or par end
    e.parent = par
  end
end

-- 应用到选中：缩放 / 透明度 / 宽 / 高（各参可为 nil = 该项不动）；同时记自定义 + 落存档
local function uiApplyToSelected(scaleV, alphaV, wV, hV)
  local n, skip = 0, 0
  for _, e in ipairs(uiFiltered()) do
    if ui.sel[e.path] then
      local f = e.f
      local touched = false
      if scaleV and e.scaleable then pcall(f.SetScale, f, scaleV) touched = true end
      if alphaV and type(f.SetAlpha) == "function" then pcall(f.SetAlpha, f, alphaV) touched = true end
      if wV and type(f.SetWidth) == "function" then pcall(f.SetWidth, f, wV) touched = true end
      if hV and type(f.SetHeight) == "function" then pcall(f.SetHeight, f, hV) touched = true end
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
local function uiScanAll()
  nodes = nil
  ui.entries = nil
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    -- 从未开过图 → 借 ShowUIPanel 让客户端把地图帧建出来（不改变可见性要求）
    if type(ShowUIPanel) == "function" and wm then pcall(ShowUIPanel, wm) end
  end
  uiBuildEntries()
  ui.entries = ui.entries or {}
  uiScanState()
  if uiRefresh then uiRefresh() end
  P("全层扫描完成：树内 " .. table.getn(nodes or {}) .. " 层 + 顶层帧 " .. table.getn(TOP) .. " 个（状态已刷新）")
  return table.getn(ui.entries)
end

-- ★★用户要求：点击（选中）某个层 → 支持设 x,y 坐标（相对**现有锚点**的偏移增量）
--   做法：取第 1 个锚点 GetPoint(1) → ClearAllPoints → 用**同一组锚点**+新偏移重设。
--   这比「绝对屏幕坐标」安全：不动锚点语义，不会被地图自身的重锚逻辑打架；原值存起来可还原。
local uiPosSaved = nil

local function uiMoveSelected(dx, dy)
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
        pcall(f.SetPoint, f, c.opt[1], c.opt[2], c.opt[3], c.opt[4], c.opt[5])
        detail = detail + 1
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
  local n = 0
  if type(uiPosSaved) == "table" then
    for _, e in ipairs(uiFiltered()) do
      local o = uiPosSaved[e.path]
      if ui.sel[e.path] and o then
        pcall(e.f.ClearAllPoints, e.f)
        pcall(e.f.SetPoint, e.f, o[1], o[2], o[3], o[4], o[5])
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

-- ★合并后的应用族（用户要求：功能重复的合并）
--   外观 = 缩放 + 透明 + 宽 + 高；全部 = 外观 + 坐标
local function uiApplyAppearance()
  uiApplyToSelected(ui.value, ui.alphaValue, ui.wVal, ui.hVal)
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
  ui.rows = math.max(6, math.floor((H - 88 - 120) / 21)) -- 88=头部/过滤区，120=底部四排控件
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

  local catNames = { "全部", "原生地图", "任务图钉", "不可缩层", "顶层帧" }
  ui.catBtns = {}
  for i = 1, 5 do
    local b = uiBtn(root, 62, 18, catNames[i])
    b:SetPoint("TOPLEFT", root, "TOPLEFT", 8 + (i - 1) * 64, -64)
    b:SetScript("OnClick", function()
      ui.cat = (i == 1) and 0 or i
      ui.off = 0
      if uiRefresh then uiRefresh() end
    end)
    table.insert(ui.catBtns, b)
  end
  -- （≥500 过滤开关已并入第三排，顶部只留分类按钮）

  -- 列表行（12 行）
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
    -- ★需求 4：行最左的**颜色色块**（有自定义设置才填充该层颜色）+ 同色四边描边
    local cblk = row:CreateTexture(nil, "OVERLAY")
    cblk:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    cblk:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
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
    local txt = uiFont(row, 10, 0.9, 0.9, 0.9)
    pcall(txt.SetPoint, txt, "LEFT", row, "LEFT", 16, 0)
    pcall(txt.SetWidth, txt, W - 74)
    pcall(txt.SetJustifyH, txt, "LEFT")
    row.mark, row.txt, row.cblk, row.redges = mark, txt, cblk, redges
    row:SetScript("OnClick", function()
      local e = row.entry
      if not e then return end
      ui.sel[e.path] = (not ui.sel[e.path]) and true or nil
      if uiRefresh then uiRefresh() end
    end)
    -- 悬停提示：完整路径/类型/父级/可缩性（行内只放叶子名，全路径放这里）
    -- ★提示框偏好：本客户端地图上 GameTooltip 挂在画布子件下可能不渲染（UnrealQuest 实录）
    --   → 优先用 WorldMapTooltip，退回 GameTooltip。
    row:SetScript("OnEnter", function()
      local e = row.entry
      if not e then return end
      hlShowHover(e.f) -- ★悬停 = 在地图上红框标出这一层
      local tip = _G["WorldMapTooltip"] or _G["GameTooltip"]
      if not tip or type(tip.SetOwner) ~= "function" then return end
      pcall(tip.SetOwner, tip, row, "ANCHOR_RIGHT")
      pcall(tip.ClearLines, tip)
      if type(tip.AddLine) == "function" then
        pcall(tip.AddLine, tip, tostring(e.path), 1, 0.85, 0.3)
        local sz = (e.w and e.h) and string.format("%.0fx%.0f", e.w, e.h) or "?x?"
        pcall(tip.AddLine, tip, "实际尺寸 " .. sz, 0.9, 0.9, 0.9)
        pcall(tip.AddLine, tip, "父类 " .. tostring(e.parent or "?"), 0.9, 0.9, 0.9)
        pcall(tip.AddLine, tip, "可缩 " .. (e.scaleable and "是" or "否")
          .. " · S" .. (e.scale and string.format("%.2f", e.scale) or "?")
          .. " · A" .. (e.alpha and string.format("%.2f", e.alpha) or "?"), 0.8, 0.8, 0.8)
        -- ★用户要求：tooltip 增加**自定义参数信息**
        local c = ui.cust[e.path]
        if c then
          local r, g, b = uiColorFor(e.path)
          local no = 0
          for _ in pairs(ui.colorOf or {}) do no = no + 1 end
          pcall(tip.AddLine, tip, "—— 自定义参数 ——", r, g, b)
          pcall(tip.AddLine, tip, "自定义摘要：" .. (uiCustSummary(e.path) or "自定义"), 0.95, 0.95, 0.95)
          local s = c.set or {}
          local function pair2(label, cur, orig, fmt)
            local curS = cur and string.format(fmt, cur) or "?"
            local origS = orig and string.format(fmt, orig) or "?"
            return label .. " 当前 " .. curS .. " ← 原始 " .. origS
          end
          pcall(tip.AddLine, tip, pair2("缩放", s.scale, c.oscale, "%.2f"), 0.85, 0.85, 0.85)
          pcall(tip.AddLine, tip, pair2("透明", s.alpha, c.oalpha, "%.2f"), 0.85, 0.85, 0.85)
          pcall(tip.AddLine, tip, pair2("宽", s.w, c.ow, "%.0f"), 0.85, 0.85, 0.85)
          pcall(tip.AddLine, tip, pair2("高", s.h, c.oh, "%.0f"), 0.85, 0.85, 0.85)
          if s.dx or s.dy then
            pcall(tip.AddLine, tip, string.format("坐标偏移 %+.0f,%+.0f（原始锚点 %s）", s.dx or 0, s.dy or 0,
              tostring(c.opt and c.opt[1] or "?")), 0.85, 0.85, 0.85)
          end
          if c.lx and c.ly then
            pcall(tip.AddLine, tip, string.format("信息条位置偏移 %.0f,%.0f（可拖拽柄调整）", c.lx, c.ly), 0.85, 0.85, 0.85)
          else
            pcall(tip.AddLine, tip, "信息条位置：默认（贴该层左上角，可用左侧拖拽柄移动）", 0.75, 0.75, 0.75)
          end
          pcall(tip.AddLine, tip, "颜色：色板第 " .. tostring(ui.colorOf[e.path] or "?") .. " 色（全库 " .. tostring(table.getn(HL_COLORS)) .. " 色）", r, g, b)
        else
          pcall(tip.AddLine, tip, "自定义参数：无（应用任一设置后会记录并可【清理自定义】还原）", 0.7, 0.7, 0.7)
        end
      end
      pcall(tip.Show, tip)
    end)
    row:SetScript("OnLeave", function()
      hlHideHover() -- ★离开 = 撤掉红框
      local tip = _G["WorldMapTooltip"] or _G["GameTooltip"]
      if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    end)
    ui.rowW[r] = row
  end

  -- 底部四行：①缩放/透明 ②宽/高 ③动作（应用族） ④坐标/筛选/滚动
  -- ★步进器唯一实现（0.05 档=缩放/透明，10px 档=坐标/宽高）
  local function mkStepper(label, x, y, key, step, minv, maxv, fmt)
    local lb = uiFont(root, 10, 0.85, 0.85, 0.85)
    pcall(lb.SetPoint, lb, "BOTTOMLEFT", root, "BOTTOMLEFT", x, y + 4)
    pcall(lb.SetText, lb, label)
    local m = uiBtn(root, 20, 18, "-")
    m:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x + 34, y)
    local vl = uiFont(root, 11, 1, 0.95, 0.6)
    pcall(vl.SetPoint, vl, "BOTTOMLEFT", root, "BOTTOMLEFT", x + 58, y + 4)
    local p = uiBtn(root, 20, 18, "+")
    p:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x + 96, y)
    local function cur() return tonumber(ui[key]) or 0 end
    local function setv(v)
      if v < minv then v = minv end
      if v > maxv then v = maxv end
      ui[key] = math.floor(v * 100 + 0.5) / 100
      pcall(vl.SetText, vl, string.format(fmt, ui[key]))
    end
    m:SetScript("OnClick", function() setv(cur() - step) end)
    p:SetScript("OnClick", function() setv(cur() + step) end)
    pcall(vl.SetText, vl, string.format(fmt, cur()))
    ui.lbls = ui.lbls or {}
    ui.lbls[key] = vl
    return vl
  end
  mkStepper("缩放", 8, 86, "value", 0.05, 0.05, 1.5, "%.2f")
  mkStepper("透明", 130, 86, "alphaValue", 0.05, 0.05, 1.5, "%.2f")
  mkStepper("宽度", 252, 86, "wVal", 10, 10, 3000, "%.0f") -- ★需求 1：默认 700、步进 10
  mkStepper("高度", 374, 86, "hVal", 10, 10, 3000, "%.0f") -- ★需求 1：默认 600、步进 10
  mkStepper("X 坐标", 8, 60, "xVal", 10, -800, 800, "%.0f")
  mkStepper("Y 坐标", 130, 60, "yVal", 10, -800, 800, "%.0f")

  -- ★合并族：应用外观（缩放+透明+尺寸）/ 应用坐标 / 应用全部 / 还原坐标
  local applyLook = uiBtn(root, 70, 18, "应用外观")
  applyLook:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 252, 60)
  applyLook:SetScript("OnClick", function() uiApplyAppearance() end)
  local applyPos = uiBtn(root, 70, 18, "应用坐标")
  applyPos:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 326, 60)
  applyPos:SetScript("OnClick", function() uiMoveSelected(ui.xVal or 0, ui.yVal or 0) end)
  local applyAll = uiBtn(root, 70, 18, "应用全部")
  applyAll:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 400, 60)
  applyAll:SetScript("OnClick", function() uiApplyAll() end)
  local resetPos = uiBtn(root, 70, 18, "还原坐标")
  resetPos:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 474, 60)
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
  local onlyB = uiBtn(root, 88, 18, "仅显示中:开")
  onlyB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 340, 34)
  onlyB:SetScript("OnClick", function()
    ui.onlyShown = not ui.onlyShown
    pcall(onlyB.label.SetText, onlyB.label, "仅显示中:" .. (ui.onlyShown and "开" or "关"))
    ui.off = 0
    if uiRefresh then uiRefresh() end
  end)
  local bigB2 = uiBtn(root, 88, 18, "≥500:开")
  bigB2:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 432, 34)
  bigB2:SetScript("OnClick", function()
    ui.bigOnly = not ui.bigOnly
    pcall(bigB2.label.SetText, bigB2.label, "≥500:" .. (ui.bigOnly and "开" or "关"))
    ui.off = 0
    if uiRefresh then uiRefresh() end
  end)

  -- 第四排：工具（扫描=全量重枚举；重扫已并入扫描，去掉重复入口）
  local scanB = uiBtn(root, 60, 18, "扫描")
  scanB:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 8, 8)
  scanB:SetScript("OnClick", function() uiScanAll() end)

  -- ★用户要求：列表滚动（滚轮 + 上下按钮）
  ui.scrollLbl = uiFont(root, 10, 0.8, 0.8, 0.8)
  pcall(ui.scrollLbl.SetPoint, ui.scrollLbl, "BOTTOMLEFT", root, "BOTTOMLEFT", 470, 12)
  pcall(ui.scrollLbl.SetJustifyH, ui.scrollLbl, "LEFT")
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
        local tag = e.shown and "[显]" or "[隐]"
        if not e.scaleable then tag = tag .. "[不可缩]" end
        local sz = (e.w and e.h) and string.format("%.0fx%.0f", e.w, e.h) or "?x?"
        local vals = ""
        if e.scale then vals = vals .. string.format(" S%.2f", e.scale) end
        if e.alpha then vals = vals .. string.format(" A%.2f", e.alpha) end
        -- ★层名称 + 实际尺寸 + 父类层名称（用户要求）；有自定义的再带彩色摘要
        local custTxt = ""
        if ui.cust[e.path] then
          custTxt = "  {" .. (uiCustSummary(e.path) or "自定义") .. "}"
        end
        pcall(row.txt.SetText, row.txt,
          string.format("#%s %s %s  %s  父=%s%s%s", tostring(e.no or "?"), tag, tostring(e.name or e.path), sz,
            tostring(e.parent or "?"), vals, custTxt))
        if ui.sel[e.path] then row.mark:Show() else row.mark:Hide() end
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
    local nMk = uiMarksRefresh(ui.entries)
    local info = string.format("结果 %d · 选中 %d%s%s", total, nSel,
      nHl > 0 and (" · 描边 " .. nHl) or "", nMk > 0 and (" · 自定义 " .. nMk) or "")
    if ui.scrollLbl then
      pcall(ui.scrollLbl.SetText, ui.scrollLbl,
        string.format("%d-%d/%d", (ui.off or 0) + 1, math.min(total, (ui.off or 0) + per), total))
    end
    if ui.pageLbl then
      pcall(ui.pageLbl.SetText, ui.pageLbl, info)
    end
    if ui.echo then
      pcall(ui.echo.SetText, ui.echo, "过滤：" .. (ui.filter ~= "" and ui.filter or "（不填=全部）") .. " · 滚轮翻动列表")
    end
  end

  ui.root = root
  ui.built = true
  root:Hide()
  return true
end

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
    P("图层调试面板：右侧已打开（过滤框 + 分类按钮 + 列表多选 + [-]值[+] 设缩放 + [应用到选中]）")
  end
end

-- 地图右侧入口按钮
local uiEntry = nil
local function uiEnsureEntry()
  if uiEntry then return end
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") or type(CreateFrame) ~= "function" then return end
  local b = uiBtn(wm, 30, 18, "层")
  -- ★用户要求：入口按钮放**右上角**（避开原生 X/缩小按钮那一行，故下移 34px）
  b:SetPoint("TOPRIGHT", wm, "TOPRIGHT", -8, -34)
  -- ★入口按钮同样必须压过地图的 FULLSCREEN strata
  pcall(b.SetFrameStrata, b, "FULLSCREEN_DIALOG")
  b:SetFrameLevel(400)
  b:SetScript("OnClick", function() uiToggle() end)
  uiEntry = b
end

-- 地图右侧入口按钮：开图后自动出现（tick 兜底，无需命令）
if type(CreateFrame) == "function" then
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  local pf = CreateFrame("Frame", "EH_DB_UIENTRY", parent)
  local acc = 0
  pf:SetScript("OnUpdate", function()
    acc = acc + (tonumber(arg1) or 0.05)
    if acc < 0.3 then return end
    acc = 0
    uiEnsureEntry()
  end)
end

-- ===== 需求 5：账号级自定义设置的载入 + 定时器兜底重设 =====
-- ① 载入：把 EH_DEBUGBOX_CFG.cust/colors 读回内存；
-- ② 立即尝试重设一次（帧多半还没建 → 这一次可能全部解析不到，属正常）；
-- ③ **定时器循环监视**（每 2 秒）：只要某层当前值与存档期望不符就重设 ——
--    这样「重载后、开图后、别的插件改过之后」都会自动回到用户设定的状态。
local REAPPLY_PERIOD = 2.0
do
  local n = uiCustLoad()
  P("自定义设置存档：载入 " .. n .. " 条（账号级 EH_DEBUGBOX_CFG.cust）")
  if CreateFrame then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    local rf = CreateFrame("Frame", "EH_DB_REAPPLY", parent)
    local acc = 0
    rf:SetScript("OnUpdate", function()
      acc = acc + (tonumber(arg1) or 0.05)
      if acc < REAPPLY_PERIOD then return end
      acc = 0
      if next(ui.cust or {}) ~= nil then uiCustReapply(true) end
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
    if type(nd.f.SetScale) == "function" then
      pcall(nd.f.SetScale, nd.f, s)
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
  if type(nd.f.SetScale) ~= "function" then
    P("#" .. tostring(idx) .. " " .. nd.n .. " 无 SetScale（图层/纹理只能改尺寸，不支持缩放）")
    return
  end
  pcall(nd.f.SetScale, nd.f, s)
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
    elseif msg == "scanui" or msg == "uisize" then
      uiScanMeasure()
    elseif msg == "scan" then
      uiBuild()
      uiScanAll()
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
        pcall(nodes[i].f.SetScale, nodes[i].f, 1)
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
      P("/edb ui=★图层调试面板（地图右侧『层』按钮同效：过滤+多选+设缩放）")
    end
  end
end

P("EH_DebugBox 纯缩放试验已载入：/edb 查看用法（/reload 还原一切）")
