-- ============================================================
-- EH_SimpleMap 简易世界地图（透明度可调） v0.2.0
-- probe/worldmap-minimap 分支产物：S_WorldMap 移植 EmberVeil（小地图不做，用户拍板）。
-- 全部能力经 probe 系列实测定案（见「正式版功能」段注释）；探针保留为诊断命令。
-- ============================================================

EH_SIMPLEMAP_CFG = EH_SIMPLEMAP_CFG or {}

local SM = { lines = {} }

local function P(msg)
  msg = tostring(msg)
  table.insert(SM.lines, msg)
  if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cff66ccff[简易地图]|r " .. msg)
  end
end

-- 探针结果落存档（SavedVariables；/reload 或小退后落盘，可回读 EH_SimpleMap.lua）
local function flushStore()
  EH_SIMPLEMAP_CFG.probeLog = SM.lines
  EH_SIMPLEMAP_CFG.probeAt = (type(GetTime) == "function") and tostring(GetTime()) or "?"
end

-- ===== 探测助手 =====
local function hasFn(name)
  return (type(_G[name]) == "function") and "有" or "无"
end

local function hasObj(name)
  local v = _G[name]
  if type(v) == "table" or type(v) == "userdata" then return "有" end
  return "无"
end

-- 帧几何：能读出 宽x高 才算「有真身」
local function geom(name)
  local f = _G[name]
  if not (type(f) == "table" or type(f) == "userdata") then return "无" end
  if type(f.GetWidth) ~= "function" or type(f.GetHeight) ~= "function" then return "有(无几何)" end
  local okw, w = pcall(f.GetWidth, f)
  local okh, h = pcall(f.GetHeight, f)
  if okw and okh and type(w) == "number" and type(h) == "number" then
    return string.format("有 %.0fx%.0f", w, h)
  end
  return "有(几何读不出)"
end

-- 子帧枚举（GetChildren 返回不定个数；pcall 收全表）
local function childrenOf(name)
  local f = _G[name]
  if not (type(f) == "table" or type(f) == "userdata") then return "父帧不存在" end
  if type(f.GetChildren) ~= "function" then return "无 GetChildren 方法" end
  local r = { pcall(f.GetChildren, f) }
  if not r[1] then return "GetChildren 调用失败" end
  local out = {}
  for i = 2, table.getn(r) do
    local k = r[i]
    if k then
      local nm, ft = nil, nil
      if type(k.GetName) == "function" then local ok, v = pcall(k.GetName, k) if ok then nm = v end end
      if type(k.GetFrameType) == "function" then local ok, v = pcall(k.GetFrameType, k) if ok then ft = v end end
      table.insert(out, tostring(nm or "?") .. "/" .. tostring(ft or "?"))
    end
  end
  if table.getn(out) == 0 then return "0 个子帧" end
  return table.getn(out) .. " 个: " .. table.concat(out, ", ")
end

-- 方法存在性（widget 方法：SetMaskTexture / SetZoom 等）
local function hasM(name, m)
  local f = _G[name]
  if not (type(f) == "table" or type(f) == "userdata") then return "父帧无" end
  return (type(f[m]) == "function") and "有" or "无"
end

-- 事件注册试验：只证「注册不炸」（本客户端可能静默收下不存在的事件名，故不算支持证据）
local function tryEvents(list)
  local f = CreateFrame("Frame")
  if not f or type(f.RegisterEvent) ~= "function" then return "CreateFrame/RegisterEvent 不可用" end
  local okN, badN = 0, {}
  for _, ev in ipairs(list) do
    local ok = pcall(f.RegisterEvent, f, ev)
    if ok then okN = okN + 1 else table.insert(badN, ev) end
  end
  local s = "注册不报错 " .. okN .. "/" .. table.getn(list)
  if table.getn(badN) > 0 then s = s .. "；报错: " .. table.concat(badN, ", ") end
  return s .. "（★只证不炸，不证事件真会派发）"
end

-- ===== /ehm probe：只读取证 =====
local function probeRead()
  SM.lines = {}
  P("—— 只读取证开始（不动任何状态）——")

  P("① 世界地图函数: ShowUIPanel=" .. hasFn("ShowUIPanel")
    .. " ToggleWorldMap=" .. hasFn("ToggleWorldMap")
    .. " PingPlayerPosition=" .. hasFn("WorldMapFrame_PingPlayerPosition")
    .. " ProcessMapClick=" .. hasFn("ProcessMapClick"))
  P("① 世界地图函数2: GetNumMapOverlays=" .. hasFn("GetNumMapOverlays")
    .. " GetMapOverlayInfo=" .. hasFn("GetMapOverlayInfo")
    .. " MouseIsOver=" .. hasFn("MouseIsOver")
    .. " GetCursorPosition=" .. hasFn("GetCursorPosition")
    .. " SetMapToCurrentZone=" .. hasFn("SetMapToCurrentZone")
    .. " GetMapInfo=" .. hasFn("GetMapInfo")
    .. " GetPlayerMapPosition=" .. hasFn("GetPlayerMapPosition"))
  P("① 面板机制: UIPanelWindows=" .. hasObj("UIPanelWindows")
    .. " UISpecialFrames=" .. hasObj("UISpecialFrames")
    .. " UpdateMicroButtons=" .. hasFn("UpdateMicroButtons")
    .. " CloseDropDownMenus=" .. hasFn("CloseDropDownMenus"))

  P("② 世界地图控件: WorldMapFrame=" .. geom("WorldMapFrame")
    .. " WorldMapButton=" .. geom("WorldMapButton")
    .. " WorldMapDetailFrame=" .. geom("WorldMapDetailFrame"))
  P("② 装饰件: BlackoutWorld=" .. hasObj("BlackoutWorld")
    .. " ZoomOutButton=" .. hasObj("WorldMapZoomOutButton")
    .. " MagnifyingGlass=" .. hasObj("WorldMapMagnifyingGlassButton")
    .. " Tooltip=" .. hasObj("WorldMapTooltip"))
  P("② 区域标签: AreaFrame=" .. hasObj("WorldMapFrameAreaFrame")
    .. " AreaLabel=" .. hasObj("WorldMapFrameAreaLabel")
    .. " AreaDescription=" .. hasObj("WorldMapFrameAreaDescription"))
  P("② WorldMapFrame 子帧: " .. childrenOf("WorldMapFrame"))
  P("② WorldMapButton 子帧: " .. childrenOf("WorldMapButton"))

  -- 队伍/团队地图图标帧（S_WorldMap blips 模块的目标）
  local np, nr = 0, 0
  for i = 1, 4 do if _G["WorldMapParty" .. i] then np = np + 1 end end
  for i = 1, 40 do if _G["WorldMapRaid" .. i] then nr = nr + 1 end end
  P("③ 队伍图标帧: WorldMapParty=" .. np .. "/4 WorldMapRaid=" .. nr .. "/40"
    .. " MapUnit_OnUpdate=" .. hasFn("MapUnit_OnUpdate")
    .. " MapUnit_IsInactive=" .. hasFn("MapUnit_IsInactive"))
  P("③ 钩子目标: WorldMapButton_OnClick=" .. hasFn("WorldMapButton_OnClick")
    .. " WorldMapFrame_Update=" .. hasFn("WorldMapFrame_Update")
    .. " StaticPopup_Show=" .. hasFn("StaticPopup_Show")
    .. " StaticPopupDialogs=" .. hasObj("StaticPopupDialogs"))

  P("④ 小地图: Minimap=" .. geom("Minimap") .. " MinimapCluster=" .. geom("MinimapCluster"))
  P("④ Minimap 方法: SetMaskTexture=" .. hasM("Minimap", "SetMaskTexture")
    .. " SetZoom=" .. hasM("Minimap", "SetZoom")
    .. " GetZoom=" .. hasM("Minimap", "GetZoom")
    .. " SetPlayerModel=" .. hasM("Minimap", "SetPlayerModel")
    .. " SetAlpha=" .. hasM("Minimap", "SetAlpha")
    .. " SetMovable=" .. hasM("Minimap", "SetMovable"))
  P("④ Minimap 子帧: " .. childrenOf("Minimap"))
  P("④ 原生子件: Border=" .. hasObj("MinimapBorder")
    .. " BorderTop=" .. hasObj("MinimapBorderTop")
    .. " ZoneTextButton=" .. hasObj("MinimapZoneTextButton")
    .. " ToggleButton=" .. hasObj("MinimapToggleButton")
    .. " ZoomIn=" .. hasObj("MinimapZoomIn")
    .. " ZoomOut=" .. hasObj("MinimapZoomOut")
    .. " GameTime=" .. hasObj("GameTimeFrame"))
  P("④ 图标帧: Mail=" .. hasObj("MiniMapMailFrame")
    .. " MailBorder=" .. hasObj("MiniMapMailBorder")
    .. " MailIcon=" .. hasObj("MiniMapMailIcon")
    .. " Battlefield=" .. hasObj("MiniMapBattlefieldFrame")
    .. " MeetingStone=" .. hasObj("MiniMapMeetingStoneFrame")
    .. " Tracking=" .. hasObj("MiniMapTrackingFrame"))
  P("④ 缩放函数: Minimap_ZoomIn=" .. hasFn("Minimap_ZoomIn")
    .. " Minimap_ZoomOut=" .. hasFn("Minimap_ZoomOut")
    .. " ToggleMinimap=" .. hasFn("ToggleMinimap")
    .. " GetMinimapZoneText=" .. hasFn("GetMinimapZoneText"))

  P("⑤ 追踪/其他: GetTrackingTexture=" .. hasFn("GetTrackingTexture")
    .. " CancelTrackingBuff=" .. hasFn("CancelTrackingBuff")
    .. " HasNewMail=" .. hasFn("HasNewMail")
    .. " ToggleBattlefieldMinimap=" .. hasFn("ToggleBattlefieldMinimap")
    .. " ToggleWorldStateScoreFrame=" .. hasFn("ToggleWorldStateScoreFrame"))
  P("⑤ 下拉/框架: UIDropDownMenu_Initialize=" .. hasFn("UIDropDownMenu_Initialize")
    .. " ToggleDropDownMenu=" .. hasFn("ToggleDropDownMenu")
    .. " AceLibrary=" .. hasFn("AceLibrary")
    .. " GetAddOnEnableState=" .. hasFn("GetAddOnEnableState"))

  P("⑥ 事件注册: " .. tryEvents({ "MINIMAP_PING", "ZONE_CHANGED_NEW_AREA", "PLAYER_AURAS_CHANGED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS" }))

  P("—— 只读取证完毕；写入试验：先打开世界地图(M)，再 /ehm probe2 ——")
  flushStore()
end

-- ===== /ehm probe2：写入试验（不持久化，/reload 还原） =====
local function probeWrite()
  SM.lines = {}
  P("—— 写入试验开始（全部不持久化，/reload 还原）——")
  ensureMapOpen() -- 探针自己开图（用户实测：开图后敲不了命令）

  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    P("WorldMapFrame 不存在，跳过世界地图写入试验")
  else
    local okA0, a0 = pcall(wm.GetAlpha, wm)
    local okS = pcall(wm.SetAlpha, wm, 0.5)
    local okA1, a1 = pcall(wm.GetAlpha, wm)
    P("世界地图 SetAlpha(0.5)：调用=" .. tostring(okS)
      .. " 读回 " .. tostring(okA0 and a0 or "?") .. " → " .. tostring(okA1 and a1 or "?")
      .. " 【打开地图看：应半透明、箭头仍清晰】")
    local okW0, w0 = pcall(wm.GetWidth, wm)
    local okH0, h0 = pcall(wm.GetHeight, wm)
    local w1 = (okW0 and type(w0) == "number" and w0 > 0) and (w0 * 0.8) or 600
    local okW = pcall(wm.SetWidth, wm, w1)
    local okW2, w2 = pcall(wm.GetWidth, wm)
    P("世界地图 SetWidth(" .. string.format("%.0f", w1) .. ")：调用=" .. tostring(okW)
      .. " 读回 " .. tostring(okW0 and w0 or "?") .. "x" .. tostring(okH0 and h0 or "?")
      .. " → 宽 " .. tostring(okW2 and w2 or "?") .. " 【打开地图看：应变窄成窗口】")
    pcall(wm.SetMovable, wm, true)
    pcall(wm.SetClampedToScreen, wm, true)
    P("世界地图 SetMovable/SetClampedToScreen 已 pcall（拖动试验留给正式实现）")
  end

  local mm = _G["Minimap"]
  if not (type(mm) == "table" or type(mm) == "userdata") then
    P("Minimap 不存在，跳过小地图写入试验")
  else
    local okA0, a0 = pcall(mm.GetAlpha, mm)
    local okS = pcall(mm.SetAlpha, mm, 0.6)
    local okA1, a1 = pcall(mm.GetAlpha, mm)
    P("小地图 SetAlpha(0.6)：调用=" .. tostring(okS)
      .. " 读回 " .. tostring(okA0 and a0 or "?") .. " → " .. tostring(okA1 and a1 or "?")
      .. " 【看小地图：应半透明】")
    local okM, eM = pcall(mm.SetMaskTexture, mm, "Interface\\Buttons\\WHITE8X8")
    P("小地图 SetMaskTexture(方形)：调用=" .. tostring(okM) .. (okM and "" or (" 错=" .. tostring(eM)))
      .. " 【看小地图：应圆变方】")
    local okZ0, z0 = pcall(mm.GetZoom, mm)
    local okZ, eZ = pcall(mm.SetZoom, mm, (okZ0 and type(z0) == "number") and z0 or 0)
    P("小地图 SetZoom(原档 " .. tostring(okZ0 and z0 or "?") .. " 写回)：调用=" .. tostring(okZ)
      .. (okZ and "" or (" 错=" .. tostring(eZ))))
  end

  P("—— 写入试验完毕；确认完请 /reload 全部还原 ——")
  flushStore()
end

-- ===== /ehm probe3：窗口化决定性试验（移动 / 拖拽 / 逐帧写尺寸） =====
-- ★背景：probe2 实测 SetWidth 读回变了（1024→819.2）但画面没变 ——
--   Lua 几何与引擎渲染可能脱钩。本试验一次性定案三件事：
--   A. SetPoint 移动是否驱动渲染；B. 真拖拽是否驱动渲染；C. 引擎是否每帧重读 Lua 尺寸。
local dragBtn = nil
local tickFrame = nil
local blackHid = nil -- probe5 藏掉的黑色层（probe5r 还原用）
local candList = nil -- probe6 的全屏候选清单
local candHid = nil -- probe6 已藏的候选（probe6r 还原用）

-- ===== /ehm probe6：全屏黑幕通缉（遍历 _G，找所有「显示中且接近全屏」的帧） =====
-- ★背景（probe5 实测）：BlackoutWorld 藏了还黑、WorldMapBlackout 本来就是藏的、
--   WorldMapFrame 内部没有黑色大图层、WorldFrame 自称还在渲染 ——
--   黑底另有其人。probe5 只扫了地图帧内部；这次遍历全部全局对象。
--   安全纪律：probe6 只**列清单**；逐个试藏走 /ehm probe6h 编号（一次一个，眼见为实）；
--   永不碰 WorldMapFrame / WorldFrame / UIParent 本体。/ehm probe6r 全部放回。
local function isFrameish(v)  if type(v) ~= "table" and type(v) ~= "userdata" then return false end
  -- ★_G 里混着「不能直接索引的 userdata」（实测报错 attempt to index userdata）→ 整段 pcall
  local ok, r = pcall(function()
    return type(v.GetObjectType) == "function" and type(v.IsShown) == "function"
      and type(v.GetWidth) == "function" and type(v.GetHeight) == "function"
  end)
  return ok and r == true
end

-- 探针自己开图（用户实测：开图后敲不了命令）——ShowUIPanel 开图不 toggle，是本客户端已验证的姿势
-- ★全局函数（跨段共享助手：合并后它落在 probe2 之后，用 local 会踩「声明顺序」陷阱，见 CLAUDE.md §5.1）
function ensureMapOpen()
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then return false end
  if type(ShowUIPanel) == "function" then
    local ok = pcall(ShowUIPanel, wm)
    if ok then return true end
  end
  pcall(wm.Show, wm)
  return true
end

-- ★黑底可见性前提（用户实测）：地图满屏时分不出「黑底」和「地图本身」——
--   SetScale 缩小（probe4 已验证可行）后黑底才露得出来。所有试藏流程先缩到 0.7。
-- ★全局函数（同上：跨段共享，避免 local 声明顺序陷阱）
function shrinkMapForTest()
  local wm = _G["WorldMapFrame"]
  if type(wm) == "table" or type(wm) == "userdata" then
    pcall(wm.SetScale, wm, 0.7)
  end
end

local function frameName(v)
  if type(v.GetName) == "function" then
    local ok, n = pcall(v.GetName, v)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return "?"
end

-- 全屏候选扫描（probe6 手动版与 auto 自动版共用）
local function scanFullscreen()
  local wm, wf, up = _G["WorldMapFrame"], _G["WorldFrame"], _G["UIParent"]
  local out = {}
  for name, v in pairs(_G) do
    if isFrameish(v) and v ~= wm and v ~= wf and v ~= up then
      local oks, shown = pcall(v.IsShown, v)
      local okw, w = pcall(v.GetWidth, v)
      local okh, h = pcall(v.GetHeight, v)
      if oks and shown and okw and okh and type(w) == "number" and type(h) == "number"
        and w > 400 and h > 300 then
        table.insert(out, { f = v, n = frameName(v), g = tostring(name), w = w, h = h })
      end
    end
  end
  return out
end

local function probeBlackHunt()
  SM.lines = {}
  P("—— 全屏黑幕通缉（自动开图；本步只列清单，不藏任何东西）——")
  ensureMapOpen() -- 探针自己开图（用户实测：开图后敲不了命令）
  candList = {}
  candHid = {}
  local list = scanFullscreen()
  for i, c in ipairs(list) do
    local lv, st = "?", "?"
    if type(c.f.GetFrameLevel) == "function" then local ok, x = pcall(c.f.GetFrameLevel, c.f) if ok then lv = tostring(x) end end
    if type(c.f.GetFrameStrata) == "function" then local ok, x = pcall(c.f.GetFrameStrata, c.f) if ok then st = tostring(x) end end
    table.insert(candList, c.f)
    P(string.format("#%d %s(%s) %.0fx%.0f level=%s strata=%s", i, c.n, c.g, c.w, c.h, lv, st))
  end
  if table.getn(candList) == 0 then
    P("一个全屏候选都没找到（黑底不在任何 Lua 帧里 → 引擎级，死心）")
  else
    P("共 " .. table.getn(candList) .. " 个候选。手动逐个试藏：/ehm probe6h 编号")
    P("★或者全自动：/ehm auto 武装后按 M —— 自动逐个试藏（每个 3 秒、地图上打大字编号）")
  end
  flushStore()
end

local function probeBlackHide(idx)
  if type(candList) ~= "table" or table.getn(candList) == 0 then
    P("先跑 /ehm probe6 拿候选清单")
    return
  end
  local v = candList[tonumber(idx) or 0]
  if not v then
    P("编号无效（1.." .. table.getn(candList) .. "）")
    return
  end
  local ok = pcall(v.Hide, v)
  table.insert(candHid, v)
  P("已藏 #" .. tostring(idx) .. " " .. frameName(v) .. "（调用=" .. tostring(ok) .. "）【看画面：黑底消失了吗】")
  ensureMapOpen() -- ★藏完自动重新开图（开图状态敲不了命令，只能这样轮转）
  shrinkMapForTest() -- ★缩小地图，黑底才露得出来（用户实测：满屏时分不出黑底和地图）
end

local function probeBlackHuntRestore()
  if type(candHid) == "table" then
    for _, v in ipairs(candHid) do pcall(v.Show, v) end
  end
  candHid = {}
  local wm = _G["WorldMapFrame"]
  if type(wm) == "table" or type(wm) == "userdata" then pcall(wm.SetScale, wm, 1) end
  P("已把 probe6 藏掉的候选全部放回、缩放复位（/reload 亦可）")
end

-- ===== 自动巡检共享件（★必须在 probe7/probe8/auto 之前声明：Lua local 从声明之后才开始作用域，
--   声明前引用会解析成全局 nil —— probe8 刚踩过这个坑：autoEnsureLabel nil 报错） =====
local autoLabel = nil

local function autoBig(msg) -- 聊天 + 地图上的大字 双写（开图状态看不到聊天框）
  P(msg)
  if autoLabel then pcall(autoLabel.SetText, autoLabel, msg) end
end

local function autoEnsureLabel()
  if autoLabel then return true end
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then return false end
  if type(wm.CreateFontString) ~= "function" then return false end
  local ok, fs = pcall(wm.CreateFontString, wm, nil, "OVERLAY")
  if not ok or not fs then return false end
  pcall(fs.SetPoint, fs, "TOP", wm, "TOP", 0, -150)
  -- ★字体链 FZLBJW→FRIZQT→ARIALN 全程 pcall（本项目铁律；GameFontNormalHuge 不一定渲染中文）
  local fonts = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }
  local fontOk = false
  for _, fp in ipairs(fonts) do
    if not fontOk then
      local okf = pcall(fs.SetFont, fs, fp, 26, "OUTLINE")
      if okf then fontOk = true end
    end
  end
  if not fontOk and type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  pcall(fs.SetTextColor, fs, 1, 0.85, 0.2)
  autoLabel = fs
  return true
end

-- ===== /ehm probe7：一刀切全关试验（用户：「逐个全都关闭，只留游戏世界，先看透明是否可行」）=====
-- probe7  = 藏掉**所有**全屏候选（含地图画布）+ 两层黑幕 → 只剩游戏世界：
--           世界露出来 = 黑底是这些层之一/几个，透明路线有戏；还是黑 = 引擎级，死心。
-- probe7m = 预览「目标形态」：只留地图画布（WorldMapButton/DetailFrame/PositioningGuide），
--           其余全藏 + 地图 alpha 0.6 → 半透明地图浮在游戏世界上 = 做成后的样子。
-- probe7r = 全部放回 + 缩放/透明度复位。
local allHid = nil

local MAP_KEEP = { WorldMapButton = 1, WorldMapDetailFrame = 1, WorldMapPositioningGuide = 1 }

local function probe7hideAll(keepMap)
  SM.lines = {}
  allHid = {}
  ensureMapOpen()
  shrinkMapForTest()
  local wm = _G["WorldMapFrame"]
  local list = scanFullscreen()
  local n = 0
  for _, c in ipairs(list) do
    local keep = keepMap and MAP_KEEP[c.g]
    if not keep then
      if pcall(c.f.Hide, c.f) then
        table.insert(allHid, c.f)
        n = n + 1
      end
    end
  end
  -- 两层黑幕点名再藏一次（名单里若没扫到也兜底）
  for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
    local b = _G[bn]
    if (type(b) == "table" or type(b) == "userdata") and type(b.Hide) == "function" then
      pcall(b.Hide, b)
    end
  end
  if type(wm) == "table" or type(wm) == "userdata" then
    pcall(wm.SetAlpha, wm, 0.6)
  end
  return n
end

local function probe7All()
  local n = probe7hideAll(false)
  P("—— 一刀切：已藏全屏候选 " .. n .. " 个 + 两层黑幕（地图画布也藏了，地图消失=正常）——")
  P("【看画面：露出游戏世界 = 透明路线可行；还是纯黑 = 引擎开图不渲染世界，死心】")
  P("下一步：/ehm probe7m 预览「半透明地图浮在游戏上」；/ehm probe7r 还原")
  flushStore()
end

local function probe7MapOnly()
  -- 先全放回，再「只留地图画布」地藏
  if type(allHid) == "table" then
    for _, v in ipairs(allHid) do pcall(v.Show, v) end
  end
  allHid = nil
  local n = probe7hideAll(true)
  P("—— 目标形态预览：只留地图画布，其余 " .. n .. " 个全藏，地图 alpha=0.6 ——")
  P("【半透明地图浮在游戏世界上 = 这就是「简易世界地图（透明度可调）」做成后的样子】")
  P("还原：/ehm probe7r")
  flushStore()
end

local function probe7Restore()
  if type(allHid) == "table" then
    for _, v in ipairs(allHid) do pcall(v.Show, v) end
  end
  allHid = nil
  local wm = _G["WorldMapFrame"]
  local bw = _G["BlackoutWorld"]
  local bw2 = _G["WorldMapBlackout"]
  if (type(bw) == "table" or type(bw) == "userdata") and type(bw.Show) == "function" then pcall(bw.Show, bw) end
  if (type(bw2) == "table" or type(bw2) == "userdata") and type(bw2.Show) == "function" then pcall(bw2.Show, bw2) end
  if type(wm) == "table" or type(wm) == "userdata" then
    pcall(wm.SetAlpha, wm, 1)
    pcall(wm.SetScale, wm, 1)
  end
  P("已全部放回 + 透明度/缩放复位（/reload 亦可）")
end


-- ===== /ehm probe8：反向排查（逐层放回，查「哪一层把世界盖住了」） =====
-- ★probe7 已证「全藏后世界透出、鼠标正常」；本试验从全藏状态每 3 秒放回一层，
--   两层黑幕排最前（头号嫌疑）。哪层放回后世界被盖住/变黑 = 黑底真凶。
-- ★键盘修复顺带验证：开图后 EnableKeyboard(false)（S_WorldMap 原版姿势——
--   地图帧抢了键盘输入，禁掉它的键盘，游戏按键才恢复）。
local pb8 = { running = false, t = 0, idx = 0, list = {} }
local pb8Frame = nil

local function pb8Finish()
  pb8.running = false
  autoBig("反向排查完毕：全部放回。世界被盖住的编号 = 黑底真凶（关图后把编号+名字发我）")
end

local function pb8Tick(elapsed)
  if not pb8.running then return end
  pb8.t = pb8.t + (tonumber(elapsed) or 0.05)
  if pb8.t < 3 then return end
  pb8.t = 0
  pb8.idx = pb8.idx + 1
  local f = pb8.list[pb8.idx]
  if not f then pb8Finish() return end
  pcall(f.Show, f)
  autoBig(string.format("放回 #%d/%d %s —— 世界被盖住就记我", pb8.idx, table.getn(pb8.list), frameName(f)))
end

local function pb8Start()
  SM.lines = {}
  if type(allHid) ~= "table" or table.getn(allHid) == 0 then
    probe7hideAll(false) -- 不在全藏状态就先进入（含开图+缩小+压alpha）
  end
  -- 键盘修复试验：地图帧禁键盘，游戏按键恢复（S_WorldMap 原版姿势）
  local wm = _G["WorldMapFrame"]
  if (type(wm) == "table" or type(wm) == "userdata") and type(wm.EnableKeyboard) == "function" then
    pcall(wm.EnableKeyboard, wm, false)
    P("已对 WorldMapFrame EnableKeyboard(false)：【试试开图状态按 M 关图 / 方向键走动】")
  end
  -- 嫌疑排序：两层黑幕排最前
  local first, rest = {}, {}
  for _, f in ipairs(allHid or {}) do
    local nm = frameName(f)
    if nm == "BlackoutWorld" or nm == "WorldMapBlackout" then table.insert(first, f) else table.insert(rest, f) end
  end
  pb8.list = {}
  for _, f in ipairs(first) do table.insert(pb8.list, f) end
  for _, f in ipairs(rest) do table.insert(pb8.list, f) end
  pb8.idx = 0
  pb8.t = 0
  pb8.running = true
  if not pb8Frame and type(CreateFrame) == "function" then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    pb8Frame = CreateFrame("Frame", "EH_SM_PB8", parent)
    pb8Frame:SetScript("OnUpdate", function() pb8Tick(arg1) end)
  end
  autoEnsureLabel()
  P("—— 反向排查开始：从全藏状态每 3 秒放回一层（黑幕嫌疑排最前），共 " .. table.getn(pb8.list) .. " 层 ——")
  P("世界被盖住/变黑时记下地图上的黄色编号；/ehm probe8stop 中止并全放回")
  flushStore()
end

local function pb8Stop()
  pb8.running = false
  for _, f in ipairs(pb8.list or {}) do pcall(f.Show, f) end
  P("已中止，所有层放回")
end


-- ===== /ehm probe9：缩放路线×悬停漂移 对照试验 =====
-- ★背景（用户实测）：缩放 0.7 后「鼠标漂浮、地图触控位置失效」——渲染缩了、命中没跟上。
--   probe4 当时只验了「有缩小」没验悬停（同款 SetScale 漂移，本项目铁律记录在案）。
--   细节：拖拽在缩放下跟手（帧级命中正常）→ 漂移在**画布内部**的坐标换算。
--   三种缩放路线逐个试（每个 5 秒、地图大字报名）：A 只缩外框 / B 只缩画布 / C 都缩。
--   用户把鼠标悬到地图上的城镇/区域，看悬停高亮与提示位置对不对。
local pb9 = { running = false, t = 0, idx = 0 }
local pb9Frame = nil

-- ★本段在正式功能段之前，featWm 等 local 还没声明（声明前引用 = 全局 nil，pb9 首跑就踩了）
--   → 一律直接读 _G。
local function pb9Wm()
  local w = _G["WorldMapFrame"]
  if type(w) == "table" or type(w) == "userdata" then return w end
  return nil
end

local function pb9SetAll(s)
  local w = pb9Wm()
  if w then pcall(w.SetScale, w, s) end
  for _, n in ipairs({ "WorldMapButton", "WorldMapDetailFrame" }) do
    local f = _G[n]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetScale) == "function" then
      pcall(f.SetScale, f, s)
    end
  end
end

local pb9Modes = {
  { n = "A 只缩外框(WorldMapFrame)", f = function()
    pb9SetAll(1)
    local w = pb9Wm()
    if w then pcall(w.SetScale, w, 0.7) end
  end },
  { n = "B 只缩画布(WorldMapButton)", f = function()
    pb9SetAll(1)
    local c = _G["WorldMapButton"]
    if (type(c) == "table" or type(c) == "userdata") and type(c.SetScale) == "function" then
      pcall(c.SetScale, c, 0.7)
    end
  end },
  { n = "C 外框+画布都缩", f = function()
    pb9SetAll(0.7)
  end },
}

local function pb9Finish()
  pb9.running = false
  pb9SetAll(1) -- 复位（回 1，由 featKeep 把外框拉回配置值）
  autoBig("对照试验完毕：回我【哪个模式悬停是对的】A/B/C/全漂；已复位")
end

local function pb9Tick(elapsed)
  if not pb9.running then return end
  pb9.t = pb9.t + (tonumber(elapsed) or 0.05)
  if pb9.t < 5 then return end
  pb9.t = 0
  pb9.idx = pb9.idx + 1
  local m = pb9Modes[pb9.idx]
  if not m then pb9Finish() return end
  m.f()
  autoBig(string.format("模式 %s（%d/3）：悬停城镇看提示位置对不对", m.n, pb9.idx))
end

local function pb9Start()
  ensureMapOpen()
  shrinkMapForTest()
  if not pb9Frame and type(CreateFrame) == "function" then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    pb9Frame = CreateFrame("Frame", "EH_SM_PB9", parent)
    pb9Frame:SetScript("OnUpdate", function() pb9Tick(arg1) end)
  end
  pb9.idx = 0
  pb9.t = 0
  pb9.running = true
  autoEnsureLabel()
  P("—— 缩放路线对照：每个模式 5 秒（A 只缩外框 / B 只缩画布 / C 都缩）——")
  P("每个模式下把鼠标悬到地图城镇/区域上：悬停高亮与提示**跟手**的模式回我（A/B/C/全漂）；/ehm probe9stop 中止")
end

local function pb9Stop()
  pb9.running = false
  pb9SetAll(1)
  P("已中止并复位缩放")
end

-- ===== /ehm auto：自动巡检 =====
-- 流程：/ehm auto 一条命令全包 → 自动开图缩到 0.7 → 扫描全屏候选
--   → 每个候选藏 3 秒（地图上有大字编号+名字）→ 自动放回换下一个 → 跑完自动全部还原。
-- 用户全程不用敲命令：黑底消失时记下屏幕上的编号即可。/ehm autostop 中止。
-- ★tick 帧挂 WorldFrame 不挂 UIParent（全屏地图可能隐藏 UIParent 导致 OnUpdate 停摆——EvalHelp 1.70.39 的坑）。
local autoSt = { on = false, running = false, wasOpen = false, phase = nil, t = 0, idx = 0, list = {}, cur = nil }
local autoFrame = nil

local function autoFinish()
  if autoSt.cur then pcall(autoSt.cur.f.Show, autoSt.cur.f) autoSt.cur = nil end
  autoSt.running = false
  autoSt.on = false
  autoBig("自动巡检完毕：已全部还原。黑底消失过的编号 = 真凶（关图后把编号+名字发我）")
  local wm = _G["WorldMapFrame"]
  if type(wm) == "table" or type(wm) == "userdata" then pcall(wm.SetScale, wm, 1) end
end

local function autoTick(elapsed)
  if not (autoSt.on and autoSt.running) then return end
  -- 逐个试藏：3 秒一个
  autoSt.t = autoSt.t + (tonumber(elapsed) or 0.05)
  if autoSt.t < 3 then return end
  autoSt.t = 0
  if autoSt.cur then pcall(autoSt.cur.f.Show, autoSt.cur.f) autoSt.cur = nil end
  autoSt.idx = autoSt.idx + 1
  local c = autoSt.list[autoSt.idx]
  if not c then autoFinish() return end
  pcall(c.f.Hide, c.f)
  autoSt.cur = c
  autoBig(string.format("试藏 #%d/%d %s —— 黑底消失就记我", autoSt.idx, table.getn(autoSt.list), c.n .. "(" .. c.g .. ")"))
end

local function autoArm()
  if not autoFrame and type(CreateFrame) == "function" then
    local parent = _G["WorldFrame"]
    if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
    autoFrame = CreateFrame("Frame", "EH_SM_AUTO", parent)
    autoFrame:SetScript("OnUpdate", function() autoTick(arg1) end)
  end
  -- ★不赌 IsShown 侦测（本客户端明文不可靠，上一轮黄字没出现就是它误判）：
  --   直接自己开图 + 缩小 + 立刻开跑，确定性流程。
  ensureMapOpen()
  shrinkMapForTest()
  autoSt.list = scanFullscreen()
  autoSt.idx = 0
  autoSt.cur = nil
  autoSt.t = 0
  if table.getn(autoSt.list) == 0 then
    P("自动巡检：没找到全屏候选（黑底不在 Lua 层 → 引擎级）")
    autoSt.on = false
    autoSt.running = false
    return
  end
  autoSt.on = true
  autoSt.running = true
  autoEnsureLabel()
  autoBig("自动巡检开始：共 " .. table.getn(autoSt.list) .. " 个候选，每个藏 3 秒（地图已缩到 0.7）")
  P("盯着地图四周黑边 + 地图上的黄色大字编号；黑边消失时记下编号。/ehm autostop 中止")
end

local function autoStop()
  autoSt.on = false
  if autoSt.cur then pcall(autoSt.cur.f.Show, autoSt.cur.f) autoSt.cur = nil end
  autoSt.running = false
  autoSt.phase = nil
  P("自动巡检已中止，试藏过的已放回")
end



-- ===== /ehm probe5：黑幕深挖（底下是不是还有一层黑幕） =====
-- ★背景（probe4 实测）：BlackoutWorld:Hide() 后仍是黑的、压 alpha 也看不到游戏世界。
--   本试验枚举 WorldMapFrame 的全部 regions/子帧 + 常见命名的黑幕件，
--   把「近全屏且纯黑」的层一次全藏掉再压 alpha —— 还黑 = 引擎级黑底（世界根本没渲染），死心。
local function probeBlack()
  SM.lines = {}
  P("—— 黑幕深挖（自动开图）——")
  ensureMapOpen() -- 探针自己开图（用户实测：开图后敲不了命令）
  blackHid = {}
  local sw, sh = nil, nil
  if type(GetScreenWidth) == "function" then sw = GetScreenWidth() end
  if type(GetScreenHeight) == "function" then sh = GetScreenHeight() end

  -- ① 常见命名黑幕件逐个查存在性与显隐
  local named = { "BlackoutWorld", "WorldMapBlackout", "WorldMapFrameBlackout", "BlackoutFrame" }
  for _, n in ipairs(named) do
    local f = _G[n]
    if type(f) == "table" or type(f) == "userdata" then
      local shown = "?"
      if type(f.IsShown) == "function" then local ok, v = pcall(f.IsShown, f) if ok then shown = tostring(v) end end
      P("① " .. n .. "：存在，IsShown=" .. shown)
    else
      P("① " .. n .. "：无")
    end
  end

  -- ② 枚举 WorldMapFrame 的 regions（Texture/FontString 层）与子帧，找「大而黑」的
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    P("② WorldMapFrame 不存在，试验终止")
    flushStore()
    return
  end
  local function regionInfo(r)
    local ot = "?"
    if type(r.GetObjectType) == "function" then local ok, v = pcall(r.GetObjectType, r) if ok then ot = tostring(v) end end
    return ot
  end
  local function tryCollectBlack(f, tag)
    -- 帧本体若是 Frame 也可能有纯黑 backdrop；先 regions 后子帧
    if type(f.GetRegions) == "function" then
      local rr = { pcall(f.GetRegions, f) }
      if rr[1] then
        for i = 2, table.getn(rr) do
          local r = rr[i]
          if r and regionInfo(r) == "Texture" then
            local shown = true
            if type(r.IsShown) == "function" then local ok, v = pcall(r.IsShown, r) shown = (ok and v) and true or false end
            local cr, cg, cb = 1, 1, 1
            if type(r.GetVertexColor) == "function" then
              local ok, a, b, c = pcall(r.GetVertexColor, r)
              if ok then cr, cg, cb = tonumber(a) or 1, tonumber(b) or 1, tonumber(c) or 1 end
            end
            local rw, rh = 0, 0
            if type(r.GetWidth) == "function" then local ok, v = pcall(r.GetWidth, r) if ok then rw = tonumber(v) or 0 end end
            if type(r.GetHeight) == "function" then local ok, v = pcall(r.GetHeight, r) if ok then rh = tonumber(v) or 0 end end
            if shown and cr < 0.1 and cg < 0.1 and cb < 0.1 and rw > 300 and rh > 300 then
              table.insert(blackHid, r)
              P("② 黑色大图层(" .. tag .. ")：" .. string.format("%.0fx%.0f 色 %.2f,%.2f,%.2f", rw, rh, cr, cg, cb))
            end
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
            local nm = "?"
            if type(c.GetName) == "function" then local ok, v = pcall(c.GetName, c) if ok then nm = tostring(v) end end
            tryCollectBlack(c, tag .. ">" .. nm)
          end
        end
      end
    end
  end
  tryCollectBlack(wm, "WorldMapFrame")
  if table.getn(blackHid) == 0 then
    P("② WorldMapFrame 里没找到「大而黑」的自有图层（黑底不归它的图层管）")
  end

  -- ③ UIParent / WorldFrame 状态（1.70.39 记录：开全屏地图会隐藏 UIParent）
  local up = _G["UIParent"]
  if type(up) == "table" or type(up) == "userdata" then
    local s = "?"
    if type(up.IsShown) == "function" then local ok, v = pcall(up.IsShown, up) if ok then s = tostring(v) end end
    P("③ UIParent.IsShown=" .. s .. "（false = 开图时整个普通 UI 被藏，符合既有记录）")
  end
  local wf = _G["WorldFrame"]
  if type(wf) == "table" or type(wf) == "userdata" then
    local s = "?"
    if type(wf.IsShown) == "function" then local ok, v = pcall(wf.IsShown, wf) if ok then s = tostring(v) end end
    P("③ WorldFrame(3D世界) 存在，IsShown=" .. s)
  else
    P("③ WorldFrame(3D世界) 不存在")
  end

  -- ④ 把找到的黑色层全藏掉 + BlackoutWorld 再藏一次 + 压 alpha，让用户看底下
  local bw = _G["BlackoutWorld"]
  if (type(bw) == "table" or type(bw) == "userdata") and type(bw.Hide) == "function" then pcall(bw.Hide, bw) end
  for _, r in ipairs(blackHid) do pcall(r.Hide, r) end
  pcall(wm.SetAlpha, wm, 0.6)
  P("④ 已藏：BlackoutWorld + 黑色图层 " .. table.getn(blackHid) .. " 层；地图 alpha=0.6")
  P("④ 【现在看画面：地图外/底下透出游戏世界 = 有救；还是纯黑 = 引擎开图时不渲染世界，透明度死心】")
  P("还原：/ehm probe5r；/reload 亦可")
  flushStore()
end

local function probeBlackRestore()
  local wm = _G["WorldMapFrame"]
  local bw = _G["BlackoutWorld"]
  if (type(bw) == "table" or type(bw) == "userdata") and type(bw.Show) == "function" then pcall(bw.Show, bw) end
  if type(blackHid) == "table" then
    for _, r in ipairs(blackHid) do pcall(r.Show, r) end
  end
  blackHid = nil
  if type(wm) == "table" or type(wm) == "userdata" then pcall(wm.SetAlpha, wm, 1) end
  P("已还原黑幕与透明度（/reload 亦可全还原）")
end



-- ===== /ehm probe4：半透明+缩放+拖拽 终局试验 =====
-- ★背景（用户实测）：SetAlpha(0.5) 后「地图有点黑」、SetPoint 左移后「右边黑」——
--   两处黑都疑似 1.12 原版全屏地图的黑色遮挡层 BlackoutWorld 透了出来。
--   若藏掉黑幕后半透明依旧 = 真·半透明世界地图成立（S_WorldMap 核心卖点）。
local function probeFinal()
  SM.lines = {}
  P("—— 终局试验（自动开图，盯着画面看）——")
  ensureMapOpen() -- 探针自己开图（用户实测：开图后敲不了命令）
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    P("WorldMapFrame 不存在，试验终止")
    flushStore()
    return
  end

  -- A. 黑幕试验：BlackoutWorld 存在就藏掉
  local bw = _G["BlackoutWorld"]
  if type(bw) == "table" or type(bw) == "userdata" then
    local ok = pcall(bw.Hide, bw)
    P("A. BlackoutWorld:Hide() 调用=" .. tostring(ok)
      .. " 【黑底消失、露出游戏画面 = 黑幕就是它；仍黑 = 黑的是别的东西】")
  else
    P("A. BlackoutWorld 不存在（黑底另有其人：可能引擎底色/地图自身背景）")
  end

  -- B. 真半透明确认：藏黑幕后再压一次透明度
  local okA = pcall(wm.SetAlpha, wm, 0.7)
  local okG, a1 = pcall(wm.GetAlpha, wm)
  P("B. SetAlpha(0.7)：调用=" .. tostring(okA) .. " 读回=" .. tostring(okG and a1 or "?")
    .. " 【能透过地图看到游戏世界 = 半透明成立；只是变暗 = 引擎不支持】")

  -- C. SetScale 缩放试验（S_WorldMap 的缩放路径；与 SetWidth 是两条渲染路径）
  local okS = pcall(wm.SetScale, wm, 0.8)
  local okG2, s1 = pcall(wm.GetScale, wm)
  P("C. SetScale(0.8)：调用=" .. tostring(okS) .. " 读回=" .. tostring(okG2 and s1 or "?")
    .. " 【地图整体缩小 = 缩放可走 SetScale；没变 = 缩放也归引擎】"
    .. " 若缩小了：顺手把鼠标悬到地图城镇上，看提示位置对不对（查点击漂移）")

  -- D. 拖拽柄修正版：锚进地图内部（probe3 锚到屏幕外了）、层级拉满
  if dragBtn then pcall(dragBtn.Hide, dragBtn) dragBtn = nil end
  if type(CreateFrame) == "function" then
    local b = CreateFrame("Button", "EH_SM_DRAGTEST", wm)
    b:SetWidth(180)
    b:SetHeight(24)
    b:SetPoint("TOP", wm, "TOP", 0, -60) -- ★锚进地图内部（probe3 的 +26 画到屏幕外了）
    local lv = 10
    if type(wm.GetFrameLevel) == "function" then
      local okl, v = pcall(wm.GetFrameLevel, wm)
      if okl and type(v) == "number" then lv = v end
    end
    b:SetFrameLevel(lv + 100)
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(b)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.85, 0.65, 0.10, 1)
    local bd = b:CreateTexture(nil, "BORDER")
    bd:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    bd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    bd:SetTexture("Interface\\Buttons\\WHITE8X8")
    bd:SetVertexColor(0, 0, 0, 1)
    local fs = b:CreateFontString(nil, "OVERLAY")
    pcall(fs.SetFontObject, fs, GameFontNormal)
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText("按住左键拖我（试验）")
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
      pcall(wm.SetMovable, wm, true)
      pcall(wm.StartMoving, wm) -- warm-up 两步
      pcall(wm.StopMovingOrSizing, wm)
      pcall(wm.StartMoving, wm)
    end)
    b:SetScript("OnDragStop", function()
      pcall(wm.StopMovingOrSizing, wm)
    end)
    b:Show()
    dragBtn = b
    P("D. 拖拽柄已放进地图内部（金色条，顶部往下 60px）：按住左键拖"
      .. " 【地图跟着走 = 支持拖拽】")
  end

  P("还原：/ehm probe4r（黑幕放回/透明度1/缩放1/位置回中）；/reload 全还原")
  flushStore()
end

local function probeFinalRestore()
  local wm = _G["WorldMapFrame"]
  local bw = _G["BlackoutWorld"]
  if type(bw) == "table" or type(bw) == "userdata" then pcall(bw.Show, bw) end
  if type(wm) == "table" or type(wm) == "userdata" then
    pcall(wm.SetAlpha, wm, 1)
    pcall(wm.SetScale, wm, 1)
    if type(wm.ClearAllPoints) == "function" and type(wm.SetPoint) == "function" then
      pcall(wm.ClearAllPoints, wm)
      pcall(wm.SetPoint, wm, "CENTER", UIParent, "CENTER", 0, 0)
    end
  end
  if dragBtn then pcall(dragBtn.Hide, dragBtn) dragBtn = nil end
  if tickFrame then tickFrame:SetScript("OnUpdate", nil) end
  P("已还原：黑幕放回 / 透明度 1 / 缩放 1 / 位置回中（/reload 亦可全还原）")
end



local function probeWindow()
  SM.lines = {}
  P("—— 窗口化决定性试验（请自动开图，盯着画面看）——")
  ensureMapOpen() -- 探针自己开图（用户实测：开图后敲不了命令）
  local wm = _G["WorldMapFrame"]
  if not (type(wm) == "table" or type(wm) == "userdata") then
    P("WorldMapFrame 不存在，试验终止")
    flushStore()
    return
  end

  -- A. SetPoint 移动试验：贴到屏幕左缘（效果若存在则一眼可见）
  if type(wm.ClearAllPoints) == "function" and type(wm.SetPoint) == "function" then
    pcall(wm.ClearAllPoints, wm)
    local ok = pcall(wm.SetPoint, wm, "LEFT", UIParent, "LEFT", 30, 0)
    P("A. SetPoint 移到屏幕左缘：调用=" .. tostring(ok)
      .. " 【地图整体左移 = 位置归 Lua 管；纹丝不动 = 位置归引擎管】")
  else
    P("A. ClearAllPoints/SetPoint 方法缺失")
  end

  -- B. 真拖拽试验：顶部放黄色「拖我」柄（Button 柄 + warm-up 两步，本客户端拖动配方）
  if not dragBtn and type(CreateFrame) == "function" then
    local b = CreateFrame("Button", "EH_SM_DRAGTEST", wm)
    b:SetWidth(160)
    b:SetHeight(22)
    b:SetPoint("TOP", wm, "TOP", 0, 26)
    local lv = 10
    if type(wm.GetFrameLevel) == "function" then
      local okl, v = pcall(wm.GetFrameLevel, wm)
      if okl and type(v) == "number" then lv = v end
    end
    b:SetFrameLevel(lv + 50)
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(b)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.8, 0.6, 0.1, 0.9)
    local fs = b:CreateFontString(nil, "OVERLAY")
    pcall(fs.SetFontObject, fs, GameFontNormal)
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    fs:SetText("按住左键拖我试验")
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
      pcall(wm.SetMovable, wm, true)
      pcall(wm.StartMoving, wm) -- warm-up 两步
      pcall(wm.StopMovingOrSizing, wm)
      pcall(wm.StartMoving, wm)
    end)
    b:SetScript("OnDragStop", function()
      pcall(wm.StopMovingOrSizing, wm)
    end)
    b:Show()
    dragBtn = b
    P("B. 黄色拖拽柄已放上地图顶部：按住左键拖它"
      .. " 【地图跟着走 = 支持拖拽；柄在动图不动 / 都没动 = 引擎不管】")
  else
    P("B. 拖拽柄已存在（顶部黄条），直接拖")
  end

  -- C. 逐帧写尺寸试验：OnUpdate 里每帧 SetWidth(819)，持续 3 秒自动停
  --   （probe2 已证「写一次没用」；若每帧写会生效 = 引擎每帧重读 Lua 几何 → 窗口化还有救）
  if not tickFrame and type(CreateFrame) == "function" then
    tickFrame = CreateFrame("Frame", "EH_SM_TICKTEST", UIParent)
  end
  if tickFrame then
    tickFrame.elapsed = 0
    tickFrame:SetScript("OnUpdate", function()
      tickFrame.elapsed = (tickFrame.elapsed or 0) + (arg1 or 0)
      if tickFrame.elapsed > 3 then
        tickFrame:SetScript("OnUpdate", nil)
        P("C. 逐帧写尺寸 3 秒结束：【期间地图变窄了 = 引擎每帧重读；一直没变 = 尺寸彻底归引擎】")
        return
      end
      pcall(wm.SetWidth, wm, 819)
    end)
    P("C. 逐帧 SetWidth(819) 已启动（3 秒自动停）：【盯着地图看是否变窄】")
  end

  P("还原：/ehm probe3r 位置放回屏幕中央；/reload 全部还原")
  flushStore()
end

local function probeWindowRestore()
  local wm = _G["WorldMapFrame"]
  if type(wm) == "table" or type(wm) == "userdata" then
    if type(wm.ClearAllPoints) == "function" and type(wm.SetPoint) == "function" then
      pcall(wm.ClearAllPoints, wm)
      pcall(wm.SetPoint, wm, "CENTER", UIParent, "CENTER", 0, 0)
    end
  end
  if tickFrame then tickFrame:SetScript("OnUpdate", nil) end
  P("已把世界地图锚点放回屏幕中央（拖拽柄与改动 /reload 后全消）")
end

-- ============================================================
-- 正式版功能：简易世界地图（透明度可调）  v0.2.0
-- ★全部能力均为 probe 系列实测定案，无一是猜测：
--   · 黑底真凶 = WorldMapBlackout（probe8 反向排查；BlackoutWorld 顺手一起藏）
--   · SetAlpha = 真透明（probe7 透出游戏世界）· SetScale 缩放有效 · SetWidth 无效（别用）
--   · SetPoint/拖拽移动有效（Button 柄 + warm-up 两步，本客户端 Frame 的 OnDragStart 不触发）
--   · EnableKeyboard(false) = 地图帧不抢键盘（用户拍板；S_WorldMap 原版同款姿势）
--   · tick 挂 WorldFrame 不挂 UIParent（全屏地图可能藏 UIParent → OnUpdate 停摆，1.70.39 的坑）
-- ============================================================

local SM_CFG = EH_SIMPLEMAP_CFG
SM_CFG.alpha = tonumber(SM_CFG.alpha) or 0.75 -- 透明度（Shift+滚轮；1=不透明）★用户定：默认 0.75
SM_CFG.scale = tonumber(SM_CFG.scale) or 0.7  -- 缩放（Ctrl+滚轮；只缩外框）★用户定：默认 0.7

local FEAT = { applied = false, built = false }
local featDrag = nil
local featReset = nil -- ★前向声明（配置面板的[复位]要引用；定义在后面）

local function featWm()
  local w = _G["WorldMapFrame"]
  if type(w) == "table" or type(w) == "userdata" then return w end
  return nil
end

-- 开图信号：★不能读 WorldMapBlackout（它会被我们藏掉），读地图画布 WorldMapDetailFrame
local function featOpenNow()
  for _, n in ipairs({ "WorldMapDetailFrame", "WorldMapButton" }) do
    local f = _G[n]
    if (type(f) == "table" or type(f) == "userdata") and type(f.IsShown) == "function" then
      local ok, v = pcall(f.IsShown, f)
      if ok and v then return true end
    end
  end
  return false
end

-- 拖拽结束存位置（S_WorldMap 原版换算公式：GetCenter 含缩放，按 z 系数折回屏幕中心偏移）
local function featSavePos(wm)
  local okc, cx, cy = pcall(wm.GetCenter, wm)
  if not (okc and cx and cy) then return end
  local z = 0.5
  local up = _G["UIParent"]
  if type(up) == "table" or type(up) == "userdata" then
    local oku, ues = pcall(up.GetEffectiveScale, up)
    local oks, ms = pcall(wm.GetScale, wm)
    if oku and oks and tonumber(ues) and tonumber(ms) and ms ~= 0 then z = ues / 2 / ms end
  end
  local sw = (type(GetScreenWidth) == "function") and GetScreenWidth() or 1024
  local sh = (type(GetScreenHeight) == "function") and GetScreenHeight() or 768
  SM_CFG.px = cx - sw * z
  SM_CFG.py = cy - sh * z
end

-- ★施加口径（用户实测：SetAlpha/SetScale 打在 WorldMapFrame 上只有**外框**生效，
--   地图贴图是引擎单独画的、不吃父帧级联）→ 透明度要连画布一起打；缩放两路都打。
local function featApplyAlpha(a)
  local w = featWm()
  if w then pcall(w.SetAlpha, w, a) end
  for _, n in ipairs({ "WorldMapButton", "WorldMapDetailFrame" }) do
    local f = _G[n]
    if (type(f) == "table" or type(f) == "userdata") and type(f.SetAlpha) == "function" then
      pcall(f.SetAlpha, f, a)
    end
  end
end

-- ★缩放口径（用户定）：**只缩外框**，内部地图贴图不缩放（画布另缩会露出底图留白）。
--   透明度口径不变：外框 + 画布一起打（否则贴图不透明）。
--   ★已知悬停漂移问题在 probe/map-scale 分支专项排查（probe9：A/B/C 全漂）。
local function featApplyScale(s)
  local w = featWm()
  if w then pcall(w.SetScale, w, s) end
end

-- 滚轮挂载（★挂世界地图帧 + 地图画布两处：画布盖在帧上，滚轮事件被画布吃掉——
--   正式版首轮「滚轮没反应」就是只挂了帧。Shift=透明度 / Ctrl=缩放 / 裸滚=透传原生）
local function featWheelOn(f)
  if not (type(f) == "table" or type(f) == "userdata") then return end
  if type(f.EnableMouseWheel) == "function" then pcall(f.EnableMouseWheel, f, true) end
  local old = nil
  if type(f.GetScript) == "function" then
    local ok, o = pcall(f.GetScript, f, "OnMouseWheel")
    if ok and type(o) == "function" then old = o end
  end
  pcall(f.SetScript, f, "OnMouseWheel", function()
    local d = tonumber(arg1) or 0
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
      local a = (tonumber(SM_CFG.alpha) or 1) + d / 10
      if a < 0.3 then a = 0.3 end
      if a > 1 then a = 1 end
      SM_CFG.alpha = a
      featApplyAlpha(a)
    elseif type(IsControlKeyDown) == "function" and IsControlKeyDown() then
      local s = (tonumber(SM_CFG.scale) or 1) + d / 10
      if s < 0.5 then s = 0.5 end
      if s > 1 then s = 1 end
      SM_CFG.scale = s
      featApplyScale(s)
    elseif type(old) == "function" then
      pcall(old) -- 裸滚透传原生行为
    end
  end)
end

-- 一次性搭建：滚轮（帧+画布）+ 拖拽柄 + 坐标行 + ESC
local function featBuild(wm)
  if FEAT.built then return end
  FEAT.built = true

  featWheelOn(wm)
  featWheelOn(_G["WorldMapButton"])

  -- 拖拽柄（金色小条；★用户要求：上移到标题行，贴着「世界地图」标题位）
  if type(CreateFrame) == "function" then
    local b = CreateFrame("Button", "EH_SM_DRAG", wm)
    b:SetWidth(90)
    b:SetHeight(16)
    b:SetPoint("TOP", wm, "TOP", 0, -4)
    local lv = 10
    if type(wm.GetFrameLevel) == "function" then
      local okl, v = pcall(wm.GetFrameLevel, wm)
      if okl and type(v) == "number" then lv = v end
    end
    b:SetFrameLevel(lv + 100)
    -- ★用户定：拖动条 = 整图宽、无文字、黑底透明度 0.1（右端留 28px 避开右上角 X）
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", wm, "TOPLEFT", 0, -2)
    b:SetPoint("TOPRIGHT", wm, "TOPRIGHT", -28, -2)
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(b)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0, 0, 0, 0.1)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
      local w = featWm()
      if not w then return end
      pcall(w.SetMovable, w, true)
      pcall(w.StartMoving, w) -- warm-up 两步
      pcall(w.StopMovingOrSizing, w)
      pcall(w.StartMoving, w)
    end)
    b:SetScript("OnDragStop", function()
      local w = featWm()
      if not w then return end
      pcall(w.StopMovingOrSizing, w)
      featSavePos(w)
    end)
    featDrag = b
  end

  -- 配置入口（用户要求：地图右侧加配置图标，点开调透明度/缩放参数）
  -- 金色小件统一做法：WHITE8X8 底 + 顶点色 + 文字
  local function goldBar(parent, w, h, txt)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(w) b:SetHeight(h)
    if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
    if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints(b)
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.55, 0.42, 0.08, 0.9)
    local fs = b:CreateFontString(nil, "OVERLAY")
    pcall(fs.SetFontObject, fs, GameFontNormal)
    pcall(fs.SetPoint, fs, "CENTER", b, "CENTER", 0, 0)
    pcall(fs.SetText, fs, txt)
    return b
  end

  local cfgPanel = CreateFrame("Frame", "EH_SM_CFGP", wm)
  cfgPanel:SetWidth(190)
  cfgPanel:SetHeight(112)
  cfgPanel:SetPoint("TOPRIGHT", wm, "TOPRIGHT", -30, -48)
  local plv = 10
  if type(wm.GetFrameLevel) == "function" then
    local okl, v = pcall(wm.GetFrameLevel, wm)
    if okl and type(v) == "number" then plv = v end
  end
  cfgPanel:SetFrameLevel(plv + 110)
  if type(cfgPanel.EnableMouse) == "function" then pcall(cfgPanel.EnableMouse, cfgPanel, true) end
  local pb = cfgPanel:CreateTexture(nil, "BACKGROUND")
  pb:SetAllPoints(cfgPanel)
  pb:SetTexture("Interface\\Buttons\\WHITE8X8")
  pb:SetVertexColor(0.02, 0.02, 0.02, 0.92) -- ★用户定：背景黑色为主
  -- 边框 = 四条 1px 细线（★上一版整面覆盖金色是 bug：面板看着是金的）
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = cfgPanel:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", cfgPanel, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", cfgPanel, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = cfgPanel:CreateTexture(nil, "BORDER")
    t:SetTexture("Interface\\Buttons\\WHITE8X8")
    t:SetVertexColor(0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, cfgPanel, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, cfgPanel, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local ptitle = cfgPanel:CreateFontString(nil, "OVERLAY")
  pcall(ptitle.SetFontObject, ptitle, GameFontNormal)
  pcall(ptitle.SetPoint, ptitle, "TOP", cfgPanel, "TOP", 0, -6)
  pcall(ptitle.SetTextColor, ptitle, 0.95, 0.82, 0.35)
  pcall(ptitle.SetText, ptitle, "地图设置")

  local valA, valS -- 值标签（[-]/[+] 点击后刷新）
  local function mkRow(label, dy, get, set, lo, hi, step)
    local lab = cfgPanel:CreateFontString(nil, "OVERLAY")
    pcall(lab.SetFontObject, lab, GameFontNormal)
    pcall(lab.SetPoint, lab, "TOPLEFT", cfgPanel, "TOPLEFT", 10, dy)
    pcall(lab.SetText, lab, label)
    local bm = goldBar(cfgPanel, 22, 16, "-")
    bm:SetPoint("TOPLEFT", cfgPanel, "TOPLEFT", 76, dy + 2)
    local val = cfgPanel:CreateFontString(nil, "OVERLAY")
    pcall(val.SetFontObject, val, GameFontNormal)
    pcall(val.SetPoint, val, "TOPLEFT", cfgPanel, "TOPLEFT", 102, dy)
    local bp = goldBar(cfgPanel, 22, 16, "+")
    bp:SetPoint("TOPLEFT", cfgPanel, "TOPLEFT", 150, dy + 2)
    bm:SetScript("OnClick", function() set(-step) end)
    bp:SetScript("OnClick", function() set(step) end)
    return val
  end
  local function clampV(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
  end
  valA = mkRow("透明度", -28,
    function() return tonumber(SM_CFG.alpha) or 1 end,
    function(d)
      SM_CFG.alpha = clampV((tonumber(SM_CFG.alpha) or 1) + d, 0.3, 1)
      featApplyAlpha(SM_CFG.alpha)
      pcall(valA.SetText, valA, string.format("%.2f", SM_CFG.alpha))
    end, 0.3, 1, 0.05)
  valS = mkRow("缩放", -52,
    function() return tonumber(SM_CFG.scale) or 1 end,
    function(d)
      SM_CFG.scale = clampV((tonumber(SM_CFG.scale) or 1) + d, 0.5, 1)
      featApplyScale(SM_CFG.scale)
      pcall(valS.SetText, valS, string.format("%.2f", SM_CFG.scale))
    end, 0.5, 1, 0.05)
  pcall(valA.SetText, valA, string.format("%.2f", tonumber(SM_CFG.alpha) or 1))
  pcall(valS.SetText, valS, string.format("%.2f", tonumber(SM_CFG.scale) or 1))
  local rst = goldBar(cfgPanel, 60, 18, "复位")
  rst:SetPoint("BOTTOM", cfgPanel, "BOTTOM", 0, 8)
  rst:SetScript("OnClick", function()
    if type(featReset) == "function" then featReset() end
    pcall(valA.SetText, valA, "1.00")
    pcall(valS.SetText, valS, "1.00")
  end)
  cfgPanel:Hide()

  -- ★用户定：设置按钮 = 宏图标 454、正常技能图标尺寸 26×26（与图标库单格一致），无边框无底色
  local cfgBtn = CreateFrame("Button", "EH_SM_CFG", wm)
  cfgBtn:SetWidth(26)
  cfgBtn:SetHeight(26)
  cfgBtn:SetPoint("TOPRIGHT", wm, "TOPRIGHT", -30, -24)
  cfgBtn:SetFrameLevel(plv + 100)
  if type(cfgBtn.EnableMouse) == "function" then pcall(cfgBtn.EnableMouse, cfgBtn, true) end
  if type(cfgBtn.RegisterForClicks) == "function" then pcall(cfgBtn.RegisterForClicks, cfgBtn, "LeftButtonUp") end
  local ic = cfgBtn:CreateTexture(nil, "ARTWORK")
  ic:SetAllPoints(cfgBtn)
  local ipath = nil
  if type(GetMacroIconInfo) == "function" then
    local okI, p = pcall(GetMacroIconInfo, 454)
    if okI and type(p) == "string" and p ~= "" then ipath = p end
  end
  if not ipath then ipath = "/Game/Interface/Icons/INV_Gizmo_02_TEX" end
  pcall(ic.SetTexture, ic, ipath)
  cfgBtn:SetScript("OnClick", function()
    if cfgPanel:IsShown() then cfgPanel:Hide() else cfgPanel:Show() end
  end)


  if type(UISpecialFrames) == "table" then
    local found = false
    for _, n in ipairs(UISpecialFrames) do if n == "WorldMapFrame" then found = true end end
    if not found then pcall(table.insert, UISpecialFrames, "WorldMapFrame") end
  end

  -- 底部坐标行（鼠标坐标 + 玩家坐标；0.1s 节流；挂在地图帧下 → 关图自动停）
  local cf = CreateFrame("Frame", "EH_SM_COORDS", wm)
  cf:SetWidth(320)
  cf:SetHeight(16)
  cf:SetPoint("BOTTOM", wm, "BOTTOM", 0, 6)
  local ct = cf:CreateFontString(nil, "OVERLAY")
  pcall(ct.SetFontObject, ct, GameFontNormal)
  pcall(ct.SetPoint, ct, "CENTER", cf, "CENTER", 0, 0)
  local coordT = 0
  cf:SetScript("OnUpdate", function()
    coordT = coordT + (tonumber(arg1) or 0.05)
    if coordT < 0.1 then return end
    coordT = 0
    local w = featWm()
    local cv = _G["WorldMapButton"]
    if not w or not (type(cv) == "table" or type(cv) == "userdata") then pcall(ct.SetText, ct, "") return end
    local px, py = nil, nil
    if type(GetPlayerMapPosition) == "function" then
      local ok, a, b2 = pcall(GetPlayerMapPosition, "player")
      if ok and tonumber(a) and tonumber(b2) then px, py = a * 100, b2 * 100 end
    end
    local txt = ""
    if px then txt = string.format("玩家 %.0f,%.0f", px, py) end
    if type(GetCursorPosition) == "function" then
      local ok, cx0, cy0 = pcall(GetCursorPosition)
      local oks, es = pcall(w.GetEffectiveScale, w)
      local okc, ccx, ccy = pcall(cv.GetCenter, cv)
      local okw, cw = pcall(cv.GetWidth, cv)
      local okh, ch = pcall(cv.GetHeight, cv)
      if ok and oks and okc and okw and okh and es and es ~= 0 and ccx and cw and cw > 0 and ch > 0 then
        local mx, my = cx0 / es, cy0 / es
        local ax = (mx - (ccx - cw / 2)) / cw
        local ay = (ccy + ch / 2 - my) / ch
        if ax >= 0 and ax <= 1 and ay >= 0 and ay <= 1 then
          txt = string.format("鼠标 %.0f,%.0f", ax * 100, ay * 100) .. (px ~= nil and ("　" .. txt) or "")
        end
      end
    end
    pcall(ct.SetText, ct, txt)
  end)
end

-- 开图时应用（幂等）：藏两层黑幕 + 键盘还给游戏 + 透明度/缩放/位置记忆
local function featApply()
  local wm = featWm()
  if not wm then return end
  featBuild(wm)
  for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
    local b = _G[bn]
    if (type(b) == "table" or type(b) == "userdata") and type(b.Hide) == "function" then pcall(b.Hide, b) end
  end
  if type(wm.EnableKeyboard) == "function" then pcall(wm.EnableKeyboard, wm, false) end
  featApplyAlpha(tonumber(SM_CFG.alpha) or 1)
  featApplyScale(tonumber(SM_CFG.scale) or 1)
  if tonumber(SM_CFG.px) and tonumber(SM_CFG.py)
    and type(wm.ClearAllPoints) == "function" and type(wm.SetPoint) == "function" then
    pcall(wm.ClearAllPoints, wm)
    pcall(wm.SetPoint, wm, "CENTER", UIParent, "CENTER", SM_CFG.px, SM_CFG.py)
  end
end

-- 开图期间每 tick 保持（★治竞态：客户端自己的开图流程可能在我们 apply 之后才把黑幕 Show 出来，
--   一次性藏会被盖回去 —— 正式版首轮「黑幕没藏住」就是它。重藏/校准都是幂等廉价操作）
local function featKeep()
  local wm = featWm()
  if not wm then return end
  for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
    local b = _G[bn]
    if (type(b) == "table" or type(b) == "userdata")
      and type(b.IsShown) == "function" and type(b.Hide) == "function" then
      local ok, v = pcall(b.IsShown, b)
      if ok and v then pcall(b.Hide, b) end
    end
  end
  local a = tonumber(SM_CFG.alpha) or 1
  local okA, cur = pcall(wm.GetAlpha, wm)
  if okA and tonumber(cur) and cur ~= a then featApplyAlpha(a) end
  local s = tonumber(SM_CFG.scale) or 1
  local okS, curs = pcall(wm.GetScale, wm)
  if okS and tonumber(curs) and math.abs(curs - s) > 0.001 then featApplyScale(s) end
end

-- 开图侦测 tick（0.2s 节流；★挂 WorldFrame 不挂 UIParent）
do
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  if type(CreateFrame) == "function" and parent then
    local f = CreateFrame("Frame", "EH_SM_FEAT", parent)
    local acc = 0
    f:SetScript("OnUpdate", function()
      acc = acc + (tonumber(arg1) or 0.05)
      if acc < 0.2 then return end
      acc = 0
      local open = featOpenNow()
      if open then
        if not FEAT.applied then
          featApply()
          FEAT.applied = true
        end
        featKeep() -- ★开图期间持续保持（黑幕重藏 + 透明度/缩放漂移校准）
      elseif FEAT.applied then
        FEAT.applied = false
      end
    end)
  end
end

-- 复位：透明度/缩放/位置全回默认
function featReset()
  SM_CFG.alpha = 1
  SM_CFG.scale = 1
  SM_CFG.px = nil
  SM_CFG.py = nil
  featApplyAlpha(1) -- ★连画布一起（只打外框 = 贴图还是半透明的）
  featApplyScale(1)
  local wm = featWm()
  if wm then
    if type(wm.ClearAllPoints) == "function" and type(wm.SetPoint) == "function" then
      pcall(wm.ClearAllPoints, wm)
      pcall(wm.SetPoint, wm, "CENTER", UIParent, "CENTER", 0, 0)
    end
  end
  P("已复位：透明度 1 / 缩放 1 / 位置回屏幕中央")
end

-- ===== 斜杠命令 =====
if type(SlashCmdList) == "table" then
  SLASH_EHSIMPLEMAP1 = "/ehm"
  SLASH_EHSIMPLEMAP2 = "/ehsimplemap"
  SlashCmdList["EHSIMPLEMAP"] = function(msg)
    msg = string.lower(tostring(msg or ""))
    if msg == "probe" or msg == "探针" then
      probeRead()
    elseif msg == "probe2" or msg == "探针2" then
      probeWrite()
    elseif msg == "probe3" or msg == "探针3" then
      probeWindow()
    elseif msg == "probe3r" then
      probeWindowRestore()
    elseif msg == "probe4" or msg == "探针4" then
      probeFinal()
    elseif msg == "probe4r" then
      probeFinalRestore()
    elseif msg == "probe5" or msg == "探针5" then
      probeBlack()
    elseif msg == "probe5r" then
      probeBlackRestore()
    elseif msg == "probe6" or msg == "探针6" then
      probeBlackHunt()
    elseif string.match(msg, "^probe6h%s+%d+") then
      probeBlackHide(tonumber(string.match(msg, "^probe6h%s+(%d+)")))
    elseif msg == "probe6r" then
      probeBlackHuntRestore()
    elseif msg == "auto" then
      autoArm()
    elseif msg == "autostop" then
      autoStop()
    elseif msg == "probe7" or msg == "探针7" then
      probe7All()
    elseif msg == "probe7m" then
      probe7MapOnly()
    elseif msg == "probe7r" then
      probe7Restore()
    elseif msg == "probe8" or msg == "探针8" then
      pb8Start()
    elseif msg == "probe8stop" then
      pb8Stop()
    elseif msg == "probe9" or msg == "探针9" then
      pb9Start()
    elseif msg == "probe9stop" then
      pb9Stop()
    elseif msg == "reset" or msg == "复位" then
      featReset()
    elseif msg == "fix" then
      -- ★手动补救+状态报告：正式版没生效时跑这个（报告侦测信号/黑幕显隐/配置值）
      P("fix：开图信号=" .. tostring(featOpenNow())
        .. " built=" .. tostring(FEAT.built) .. " applied=" .. tostring(FEAT.applied)
        .. " alpha=" .. tostring(SM_CFG.alpha) .. " scale=" .. tostring(SM_CFG.scale))
      for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
        local b = _G[bn]
        local st = "无"
        if type(b) == "table" or type(b) == "userdata" then
          local ok, v = pcall(b.IsShown, b)
          st = "shown=" .. tostring(ok and v or "?")
        end
        P("fix：" .. bn .. " " .. st)
      end
      featApply()
      featKeep()
      P("fix：已手动重应用一遍（开着图跑才有效）")
    else
      P("正式版已生效：开图自动生效（藏黑幕/透明/键盘）；Shift+滚轮=透明度 · Ctrl+滚轮=缩放 · 金色条=拖动 · /ehm reset=复位")
      P("—— 诊断探针 ——")
      P("/ehm probe = 只读取证 · probe2 写入试验 · probe3/4 窗口化 · probe5 黑幕深挖 · probe6 通缉 · auto 自动巡检 · probe7 一刀切 · probe8 反向排查")
    end
  end
end

-- ★载入横幅推迟到 PLAYER_ENTERING_WORLD：本插件按字母序先于聊天框初始化载入，
--   文件末尾直接 P() 时 DEFAULT_CHAT_FRAME 可能还没建好 → 横幅静默丢失（用户实测）。
do
  if type(CreateFrame) == "function" then
    local bf = CreateFrame("Frame", "EH_SM_BANNER", UIParent)
    bf:RegisterEvent("PLAYER_ENTERING_WORLD")
    bf:SetScript("OnEvent", function()
      P("EH_SimpleMap 简易世界地图已载入：开图自动生效（藏黑幕/透明度/键盘）；Shift+滚轮=透明度 · Ctrl+滚轮=缩放 · /ehm 查看命令")
      pcall(bf.UnregisterEvent, bf, "PLAYER_ENTERING_WORLD")
    end)
  end
end
