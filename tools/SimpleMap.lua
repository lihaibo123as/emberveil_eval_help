-- ============================================================
-- EH_SimpleMap 简易世界地图（透明度可调） v0.2.0
-- probe/worldmap-minimap 分支产物：S_WorldMap 移植 EmberVeil（小地图不做，用户拍板）。
-- 全部能力经 probe 系列实测定案（见「正式版功能」段注释）；探针保留为诊断命令。
-- ============================================================

-- ★★★1.74.29 修：本客户端每个 `## SavedVariables:` 行**只认一个变量名**
--   （UnrealQuest/OneBag/OneBank 都是一行一名）。之前写成「A B -- 注释」被整串当成一个名字 →
--   存档被写成 `A B -- 注释 = nil` → 下次载入直接报错 「'=' expected」且**把账号配置覆盖掉了**。
--   现在：本工具的设置挂到主配置表 **EVAL_HELP_CONFIG.simpleMapCfg** 下（单一 SavedVariables = 稳）。
-- ★★★模块必须**自带**本地化取词：项目里 `L` 一律是**文件局部**（没有全局 L），
--   裸调 `L(...)` 在工具箱里会被 `pcall(fn, r, it)` 吞掉 ⇒ 表现是「按钮文案没设上 / 点了没反应」而面板正常。
--   写法与 tools/ConsumableHelper.lua / DismountHelper.lua / HunterHelper.lua 完全一致（走全局 EVAL_L）。
-- ★★★1.74.36-2：模块**必须自带** `say` / `logLine` —— 项目里这两个名字**只在 Core.lua / Toolbox.lua 里是 local**，
--   模块里裸调得到的是全局 nil：轻则「如实播报」全部静默消失，重则整段代码在 pcall 里直接报错退出。
--   走 Core.lua 末尾的全局桥：`EVAL_SAY = say` / `EVAL_LOGLINE = logLine`（与 ConsumableHelper 的 chSay 同一写法）。
local function say(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end
local function logLine(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, tostring(msg)) end
end

-- ★配置真值的读取口（**唯一入口**）：走工具箱导出的全局 `EVAL_TB_CFG()`。
--   读不到就**如实播报一次**（绝不静默地把「开关不落存档」藏起来 —— 那正是本次真机 bug 的形态）。
local SM_CFG_WARNED = false
local function smTbCfg(quiet)
  if type(EVAL_TB_CFG) == "function" then
    local ok, tb = pcall(EVAL_TB_CFG)
    if ok and type(tb) == "table" then return tb end
  end
  if not quiet and not SM_CFG_WARNED then
    SM_CFG_WARNED = true
    say("简易地图：读不到工具箱配置（EVAL_TB_CFG 不可用）⇒ 这个开关不会落存档（本条只报一次）")
  end
  return nil
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

EH_SIMPLEMAP_CFG = (function()
  EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
  EVAL_HELP_CONFIG.simpleMapCfg = EVAL_HELP_CONFIG.simpleMapCfg or {}
  return EVAL_HELP_CONFIG.simpleMapCfg
end)()

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

-- ============================================================
-- ★★★1.74.36-3 用户要求（原话）：「工具箱 →『缩放大地图』 开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」
--   ⇒ **默认档**（唯一来源：下面所有地方都取这三个常量，不许再散写字面量）：
--       缩放 0.7 · 透明度 0.7 · GUI重开 **不启用**（false）
--   ★语义（与 [关闭] 严格对称，两边都不留「上一轮的临时值」）：
--       · [关闭] = 视觉复位到 1/1 + 位置回屏幕中央（featReset，已有行为）；
--       · **[开启] = 回到这套默认档**（`smApplyDefaults`，本版新增）——每次从关到开都写回默认并立刻应用。
--   ★开了之后当然还能随便调（地图设置面板 [−][+] / Shift+滚轮透明度 / Ctrl+滚轮缩放），
--     调出来的值在「保持开启」期间一直有效；只有**重新开启**才会回到默认档。
-- ============================================================
local SM_DEF_ALPHA, SM_DEF_SCALE, SM_DEF_GUIREOPEN = 0.7, 0.7, false

-- ★★1.74.29 用户定：工具箱→地图功能默认 **缩放 0.7 / 透明 0.7**（原透明默认是 0.75）
SM_CFG.alpha = tonumber(SM_CFG.alpha) or SM_DEF_ALPHA -- 透明度（Shift+滚轮；1=不透明）
-- 一次性迁移：老存档里写着的旧默认 0.75 → 0.7（**只改“恰好等于旧默认”的值**，改过的值不动）
if tonumber(SM_CFG.alpha) == 0.75 and SM_CFG.alphaDefMigrated ~= true then
  SM_CFG.alpha = SM_DEF_ALPHA
  SM_CFG.alphaDefMigrated = true
end
SM_CFG.scale = tonumber(SM_CFG.scale) or SM_DEF_SCALE -- 缩放（Ctrl+滚轮；只缩外框）


-- ★1.74.35-3：FEAT 必须声明在 `featShowGUI` **之前**（里面要给它计数）；
--   `guiCalls` = 真正发出「重显最外层 GUI」的次数 —— 用来钉「关掉时一次都不发」（行为断言照得到的那种事实）。
local FEAT = { applied = false, built = false, guiCalls = 0 }

-- ============================================================
-- ★★★1.74.35-3 用户要求（工具箱 → 缩放大地图 右侧 [设置]）：
--   「缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图切换到其他地图后
--     自动刷新到当前地图,,默认关闭.」
--   ⇒ ① 这一行改成**模块行**（`t = "mod"`）：主开关勾选框 + `[设置]` 多选下拉，界面全在本文件里；
--     ② 设置里唯一条目 **「GUI重开」**，★**默认不勾 = 关**；
--     ③ 提示必须**如实写副作用**（见 TB_SM_GUIREOPEN_TIP*）：地图切到大洲/世界层后会被自动刷新回当前地图；
--     ④ 真值 = `SM_CFG.guiReopen`（nil/false = 关 = 默认；true = 开）。
--
--   ★这个副作用的机制（读 UnrealQuest 的实测注释得到，铁律 2）：
--     `Map/MapContext.lua` 的 `InspectPrimed()` 把 `Client.IsGameUIHidden() == false` 当作
--     「地图是**关着的**」信号，然后每 `RECENTER_SECONDS=2s` 调一次 `SetMapToCurrentZone()`，
--     把大洲/世界层视图拉回当前地图（原文：「A player browsing a continent has the map open and
--     is never overruled」）。我们在地图打开时把 UIParent 重新显示 ⇒ 那条信号被打破 ⇒ 它以为地图关着
--     ⇒ 你浏览大洲时每 2 秒被拉回当前地图。**这就是用户说的那个现象**，所以默认关 + 必须提示。
--   ★历史：1.74.29 曾因「与客户端互抢 UIParent 显隐」整块删过同款功能；1.74.35 用户又要回来（改成可选）。
-- ============================================================
-- 真值读取（**唯一判据入口**）：nil/false = 关（默认关）；true = 开。
--   ★老存档一次性迁移：1.74.35-2 的 `SM_CFG.showGUI`（true/非空表 ⇒ 开；false/空表 ⇒ 关），
--     迁移完**清掉老键**（不留没人读的配置 —— 与 1.74.29 清 keepUI 同一纪律）。
-- ★写入点：本模块的写入点是**白名单**的 5 处（源码检查 SM GUIREOPEN WIRING CHECK 逐条钉住写法与写入的值）：
--   迁移 3 处（true / false / 表值折算）+ `EVAL_SM_GUIREOPEN_SET` 1 处 + 地图设置面板那个开关 1 处。
--   ★任何**新增**写口都要同时在检查里登记 —— 不登记就是「真值多了一份分叉」的静默风险。
local function smMigrateReopen()
  if SM_CFG.guiReopen ~= nil then return end
  local old = SM_CFG.showGUI
  if old == true then
    SM_CFG.guiReopen = true
  elseif old == false then
    SM_CFG.guiReopen = false
  elseif type(old) == "table" then
    local any = false
    for _ in pairs(old) do any = true break end
    SM_CFG.guiReopen = any
  end
end
smMigrateReopen()
SM_CFG.showGUI = nil

local function smReopenOn()
  return SM_CFG.guiReopen == true
end

-- 开图期间把**最外层 GUI**重新显示出来（只 Show UIParent，不碰任何子窗口；读回自证如实报告）
--   返回 可见?, 被隐藏?（true = 客户端又把它藏回去了）
local function featShowGUI()
  FEAT.guiCalls = (FEAT.guiCalls or 0) + 1 -- ★真正发出「重显最外层 GUI」的次数（关掉时必须一次都不涨）
  local up = _G["UIParent"]
  if not (type(up) == "table" or type(up) == "userdata") then return false, false end
  if type(up.Show) == "function" then pcall(up.Show, up) end
  local vis = false
  if type(up.IsShown) == "function" then
    local ok, v = pcall(up.IsShown, up)
    vis = (ok and v) and true or false
  end
  return vis, (not vis)
end

local featDrag = nil
local featReset = nil -- ★前向声明（配置面板的[复位]要引用；定义在后面）
-- ★前向声明：地图设置面板的「值标签 + GUI重开按钮文案」刷新口（featBuild 里赋值）。
--   为什么要有它：默认档（smApplyDefaults）在**面板之外**写 SM_CFG，面板若是已经建好的，
--   不刷就会显示上一轮的旧数字（看着像没生效 —— 本项目最恨的静默族）。
local smPanelSync = nil
-- ★面板件引用（只为**读值口**留的；不参与任何判据）：值标签的落地文字要能被测试读到，
--   否则「默认档刷新了面板」这件事只能靠肉眼看真机（本项目纪律：能被断言的就别靠看）。
local SM_PANEL = { valA = nil, valS = nil }

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
  cfgPanel:SetHeight(132) -- ★1.74.35 多一行「显示GUI」（原 112 会与 [复位] 叠）
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
  -- ★★★1.74.35-2 用户更正：「不需要控制到每个子窗口，**只要最外层 GUI 控制就可以**」
  --   ⇒ 这一行 = **一个开关**（开/关），开 = 开图时把最外层 GUI（UIParent）重新显示出来；关 = 一个动作都不做。
  local guiLbl = cfgPanel:CreateFontString(nil, "OVERLAY")
  pcall(guiLbl.SetFontObject, guiLbl, GameFontNormal)
  pcall(guiLbl.SetPoint, guiLbl, "TOPLEFT", cfgPanel, "TOPLEFT", 10, -76)
  pcall(guiLbl.SetText, guiLbl, L("TB_SM_GUIREOPEN"))
  local guiBtn = goldBar(cfgPanel, 60, 16, smReopenOn() and "开" or "关")
  guiBtn:SetPoint("TOPLEFT", cfgPanel, "TOPLEFT", 76, -74)
  local function guiSyncLabel()
    local fsl = nil
    if type(guiBtn.GetFontString) == "function" then
      local ok, v = pcall(guiBtn.GetFontString, guiBtn)
      if ok then fsl = v end
    end
    if fsl then pcall(fsl.SetText, fsl, smReopenOn() and "开" or "关") end
  end
  -- ★默认档 / [复位] 之后的刷新口（前向声明的 smPanelSync 在这里落地）：
  --   值标签取**配置真值现算**（不复刻一份），GUI重开按钮文案走同一个 guiSyncLabel。
  smPanelSync = function()
    pcall(valA.SetText, valA, string.format("%.2f", tonumber(SM_CFG.alpha) or SM_DEF_ALPHA))
    pcall(valS.SetText, valS, string.format("%.2f", tonumber(SM_CFG.scale) or SM_DEF_SCALE))
    guiSyncLabel()
  end
  SM_PANEL.valA = valA -- 读值口用（真实控件引用）
  SM_PANEL.valS = valS
  pcall(guiBtn.SetScript, guiBtn, "OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip then return end
    pcall(tip.SetOwner, tip, guiBtn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    if type(tip.AddLine) == "function" then
      pcall(tip.AddLine, tip, L("TB_SM_GUIREOPEN_TIP1"))
      pcall(tip.AddLine, tip, L("TB_SM_GUIREOPEN_TIP2"), 1, 0.85, 0.4)
    end
    pcall(tip.Show, tip)
  end)
  pcall(guiBtn.SetScript, guiBtn, "OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip then pcall(tip.Hide, tip) end
  end)
  guiBtn:SetScript("OnClick", function()
    SM_CFG.guiReopen = (not smReopenOn()) -- 写**布尔**（老存档的表值在写入时被替换掉）
    guiSyncLabel()
    P("GUI重开 = " .. (smReopenOn() and "开（开图时重显最外层 GUI）" or "关（不做任何额外 GUI 动作）"))
  end)
  local rst = goldBar(cfgPanel, 60, 18, "复位")
  rst:SetPoint("BOTTOM", cfgPanel, "BOTTOM", 0, 8)
  rst:SetScript("OnClick", function()
    if type(featReset) == "function" then featReset() end
    -- ★标签刷新走**同一个** smPanelSync（原先在这里硬写 "1.00" 两份字面量 = 第二份真值）
    if type(smPanelSync) == "function" then pcall(smPanelSync) end
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
  -- ★1.74.35-2：按「显示GUI」开关把**最外层 GUI**重新显示（关 ⇒ 一个动作都不做，不做额外动态重现）
  if smReopenOn() then
    local vis, blocked = featShowGUI()
    SM_CFG.guiLast = "开图 GUI重开：" .. (vis and "最外层 GUI 已重新显示" or "仍被隐藏（客户端又藏回去了）")
    P(SM_CFG.guiLast)
  end
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
  -- ★1.74.35-2：开图期间持续保持**最外层 GUI** 可见（客户端自己的开图流程会再藏回去 ⇒ 每 tick 幂等重显）
  --   ★关掉 ⇒ 直接跳过（用户明确：不做额外 GUI 动态重现的操作）
  if smReopenOn() then pcall(featShowGUI) end
end

-- ===== ★★★1.74.35-4 地图探索叠加层「跟随地图缩放」自动适配（用户定：**属缩放大地图**，默认启动）=====
--   用户原话（1.74.35-4）：「开图 / es 变化后 0.1s 高频爆发期（持续 2 秒，感知上无缝）＋之后就降到 0.3 稳态巡检
--     （兜换区域的重排）」；「以上的功能是工具箱→大地图缩放要默认启动的功能，不是给图层调试工具内使用的」。
--   ⇒ 功能从 EH_DebugBox（调试工具，只留只读/手动探针）**搬到这里**，默认开。
--
--   ★为什么需要（真机定案；1.74.34-18b 探针 27 行 + 用户实测 `/edb maptile fit s` 有效）：
--     · WorldMapDetailFrame 下 12 张底瓦片 `WorldMapDetailTile*`：**互相锚 + 偏移全 0** ⇒ 对缩放免疫，本功能**不碰**；
--     · 9 张 `WorldMapOverlayN` + `WorldMapHighlight`：锚父帧 TOPLEFT 且**偏移非零**（本客户端 Lua 侧几何一律逻辑口径）
--       ⇒ 地图一缩放就错位。对齐口径 = 按父帧**有效缩放 es** 把「锚点偏移 + 宽高」整体 **×es**（÷es 实测无效）。
--
--   ★节奏（用户定稿）：开图 / es 变化 → **0.1s 爆发期（持续 2s）** → 之后 **0.3s 稳态巡检**。
--     过渡检测在每帧做（两次廉价 pcall：IsShown + GetEffectiveScale），命中就把节拍顶满 ⇒ **下一帧就动手**。
--
--   ★幂等判据：当前值 ≈ 原值 ×es 就跳过（客户端重排会把我们写的冲掉，下一拍自动补回；es 回到 1 时自动还原）。
--     **原值在首次应用时记下**（/reload 之后叠加层是客户端原始布局）——★顺序不许换：读原值 → 写新值（1.74.31 组 206 的教训）。
--   ★默认**开**（用户：「要默认启动的功能」）；`/ehm mapfit off` 关、`/ehm mapfit diag` 取证、`restore` 还原原始几何。
local SMFIT = { open = false, es = nil, burst = 0, rec = {} }
local SMFIT_BURST_GAP, SMFIT_BURST_SEC, SMFIT_IDLE_GAP = 0.1, 2.0, 0.3
local smFitMsgAt = -99

-- 开关真值：`SM_CFG.mapFit`，**nil = 默认开**（只有显式 false 才算关 —— 「默认启动」是用户明确要求）
local function smFitOn()
  return SM_CFG.mapFit ~= false
end

-- 相对锚的**名字**（存档里只能存名字；内存里保留对象引用，见 SMFIT.rec）
local function smRelName(rel)
  if not rel then return nil end
  local n = frameName(rel)
  if type(n) == "string" and n ~= "?" then return n end
  return nil
end

-- 目标 = 父帧下的**非瓦片纹理**（底瓦片跟着地图走，动它反而错）
local function smFitTargets()
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then return {} end
  local list = {}
  if type(fr.GetRegions) ~= "function" then return list end
  local ok, regs = pcall(function() return { fr:GetRegions() } end)
  if not ok then return list end
  local idx = 0
  for _, o in ipairs(regs) do
    local usable = o and type(o.GetWidth) == "function" and type(o.SetPoint) == "function"
    if usable then
      local isTex = true
      if type(o.GetObjectType) == "function" then
        local okt, t = pcall(o.GetObjectType, o)
        isTex = (okt and tostring(t) == "Texture")
      end
      if isTex then
        idx = idx + 1
        local nm = frameName(o)
        if not (type(nm) == "string" and string.sub(nm, 1, 18) == "WorldMapDetailTile") then
          table.insert(list, { o = o, key = "tex" .. tostring(idx), name = nm })
        end
      end
    end
  end
  return list
end

-- 应用适配：返回 改动数, 已适配数, 本次记到的原值数
local function smFitApply(es, quiet)
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then return 0, 0, 0 end
  es = tonumber(es) or 1
  if es <= 0 then es = 1 end
  SM_CFG.mapFitOrig = SM_CFG.mapFitOrig or {}
  local saved = SM_CFG.mapFitOrig -- 落存档那份（只给「/reload 之后还原」用：对象引用过不了 reload）
  local list = smFitTargets()
  local changed, ready, rec = 0, 0, 0
  for _, it in ipairs(list) do
    local o = it.o
    local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
    local okw, w = pcall(o.GetWidth, o)
    local okh, h = pcall(o.GetHeight, o)
    if okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
      local r = SMFIT.rec[it.key]
      if not r then
        -- ★首次见到就记**原值**（本进程内我们只在这之后才写 ⇒ 记下的一定是客户端原始布局）
        r = { o = o, rel = rel, rp = rp, p = tostring(p),
              x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
        SMFIT.rec[it.key] = r
        saved[it.key] = { idx = it.key, name = it.name, p = r.p,
          rel = smRelName(rel), rp = smRelName(rp),
          x = r.x, y = r.y, w = r.w, h = r.h }
        rec = rec + 1
      end
      local wantX, wantY = r.x * es, r.y * es
      local wantW, wantH = r.w * es, r.h * es
      if math.abs((tonumber(x) or 0) - wantX) <= 0.5 and math.abs((tonumber(y) or 0) - wantY) <= 0.5
        and math.abs((tonumber(w) or 0) - wantW) <= 0.5 and math.abs((tonumber(h) or 0) - wantH) <= 0.5 then
        ready = ready + 1
      else
        pcall(o.ClearAllPoints, o)
        pcall(o.SetPoint, o, r.p, r.rel, r.rp, wantX, wantY)
        pcall(o.SetWidth, o, wantW)
        pcall(o.SetHeight, o, wantH)
        changed = changed + 1
      end
    end
  end
  if changed > 0 then
    SM_CFG.mapFitAt = (type(GetTime) == "function") and string.format("%.1f", GetTime()) or "?"
    SM_CFG.mapFitLast = { es = es, changed = changed, total = table.getn(list) }
    local now = (type(GetTime) == "function") and GetTime() or 0
    -- 同一波重排只播报一次（3s 节流），不然每拍刷屏
    if (not quiet) and (now - (smFitMsgAt or -99) > 3) then
      smFitMsgAt = now
      P(string.format("叠加层适配：按缩放 %.2f 折算 %d 个（非瓦片纹理共 %d 个；底瓦片不动）", es, changed, table.getn(list)))
    end
  end
  return changed, ready, rec
end

-- 还原到存档里的原始几何（/reload 之后对象引用失效 ⇒ 按**名字**解析锚点、按 key 配对目标）
local function smFitRestore(quiet)
  SM_CFG.mapFitOrig = SM_CFG.mapFitOrig or {}
  local list = smFitTargets()
  local n, miss = 0, 0
  for _, it in ipairs(list) do
    local r = SM_CFG.mapFitOrig[it.key]
    if r and tonumber(r.x) and tonumber(r.y) and tonumber(r.w) and tonumber(r.h) then
      local o = it.o
      local rel = nil
      if type(r.rel) == "string" and r.rel ~= "" then rel = _G[r.rel] end
      if not rel then rel = _G["WorldMapDetailFrame"] end -- 原值记的就是「锚父帧 TOPLEFT」（探针 27 行定案）
      local rp = (type(r.rp) == "string" and r.rp ~= "") and r.rp or "TOPLEFT"
      pcall(o.ClearAllPoints, o)
      local ok = pcall(o.SetPoint, o, tostring(r.p), rel, rp, tonumber(r.x), tonumber(r.y))
      pcall(o.SetWidth, o, tonumber(r.w))
      pcall(o.SetHeight, o, tonumber(r.h))
      if ok then n = n + 1 else miss = miss + 1 end
    else
      miss = miss + 1
    end
  end
  SMFIT.rec = {}
  if not quiet then
    P("叠加层还原：按存档原始值还原 " .. n .. " 个"
      .. (miss > 0 and ("；" .. miss .. " 个没有原值或锚点解析失败 ⇒ **如实跳过**（没动它们）") or ""))
  end
  return n, miss
end

-- 取证：开关 / 地图开没开 / es / 目标数 / 原值条数 / 本次改动 / burst 剩余
local function smFitDiag()
  local fr = _G["WorldMapDetailFrame"]
  local es = nil
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetEffectiveScale) == "function" then
    local ok, v = pcall(fr.GetEffectiveScale, fr)
    if ok and tonumber(v) then es = tonumber(v) end
  end
  local nList = table.getn(smFitTargets())
  local nOrig = 0
  for _ in pairs(SM_CFG.mapFitOrig or {}) do nOrig = nOrig + 1 end
  local changed, ready = 0, 0
  if smFitOn() and es and es > 0.01 then changed, ready = smFitApply(es, true) end
  P(string.format("叠加层适配：开关=%s（默认开） · 地图开=%s · es=%s · 非瓦片纹理 %d 个 · 原值 %d 条 · 本次改 %d / 已适配 %d · burst 剩余 %.1fs",
    smFitOn() and "开" or "关", tostring(featOpenNow()),
    es and string.format("%.3f", es) or "?", nList, nOrig, changed, ready, tonumber(SMFIT.burst) or 0))
  P("节奏：开图/es 变化 → 0.1s 爆发 2 秒 → 0.3s 稳态巡检；口径 = 锚点偏移与宽高 ×es（真机定案：×es 有效、÷es 无效）")
  return changed
end

-- 开图侦测 tick（0.2s 节流；★挂 WorldFrame 不挂 UIParent）
do
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  if type(CreateFrame) == "function" and parent then
    local f = CreateFrame("Frame", "EH_SM_FEAT", parent)
    local acc = 0        -- 「开图保持」节拍（0.2s，行为不变）
    local accFit = 0     -- 叠加层适配节拍（爆发 0.1s / 稳态 0.3s）
    local esCache = nil
    f:SetScript("OnUpdate", function()
      local dt = tonumber(arg1) or 0.05
      acc = acc + dt
      accFit = accFit + dt
      -- ① 每帧廉价探测：地图开没开 + 父帧有效缩放（各一次 pcall，别做几何扫描）
      local open = featOpenNow()
      local fr = _G["WorldMapDetailFrame"]
      local es = nil
      if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetEffectiveScale) == "function" then
        local ok, v = pcall(fr.GetEffectiveScale, fr)
        if ok and tonumber(v) then es = tonumber(v) end
      end
      -- ② 过渡（开图 / es 变化）⇒ 进爆发期，并把节拍**顶满**（下一帧就动手，不等 0.1s）
      if open and not SMFIT.open then SMFIT.burst = SMFIT_BURST_SEC accFit = 1e9 end
      if es and esCache and math.abs(es - esCache) > 0.001 then SMFIT.burst = SMFIT_BURST_SEC accFit = 1e9 end
      if not open then SMFIT.burst = 0 end
      SMFIT.open, SMFIT.es = open, (es or SMFIT.es)
      esCache = es or esCache
      if (tonumber(SMFIT.burst) or 0) > 0 then SMFIT.burst = math.max(0, SMFIT.burst - dt) end
      -- ③ 既有的「开图保持」节拍（0.2s；★保持原行为不动）
      if acc >= 0.2 then
        acc = 0
        if open then
          if not FEAT.applied then
            featApply()
            FEAT.applied = true
          end
          featKeep() -- ★开图期间持续保持（黑幕重藏 + 透明度/缩放漂移校准）
        elseif FEAT.applied then
          FEAT.applied = false
        end
      end
      -- ④ 叠加层适配：**只受 smFitOn() 管**（不看工具箱那个总开关 —— 否则模块一关，我们已经乘过 es 的几何就没人还原了）
      if not smFitOn() then return end
      if not open or not es or es <= 0 then return end
      local gap = ((tonumber(SMFIT.burst) or 0) > 0) and SMFIT_BURST_GAP or SMFIT_IDLE_GAP
      if accFit < gap then return end
      accFit = 0
      smFitApply(es, false) -- 成功了才播报（内部 3s 节流）
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

-- ★★★默认档的执行口（用户 1.74.36-3；三个常量在文件上方 SM_DEF_* 处 = 单一来源）：
--   **开启「缩放大地图」时套用** —— 缩放 0.7 · 透明度 0.7 · GUI重开 **不启用**。
--   ★写的是**配置真值**（SM_CFG，落存档），并立刻应用视觉效果；面板已建好就顺带刷新它的标签
--     （否则面板显示上一轮的旧数字，看着像「默认值没生效」）。
--   ★顺序固定：先写三处真值 → 再应用（应用读的就是刚写进去的值）→ 最后刷面板。
local function smApplyDefaults()
  SM_CFG.alpha = SM_DEF_ALPHA
  SM_CFG.scale = SM_DEF_SCALE
  SM_CFG.guiReopen = SM_DEF_GUIREOPEN and true or false -- ★写布尔（老存档的表值在这里被替换掉）
  featApplyAlpha(SM_DEF_ALPHA)
  featApplyScale(SM_DEF_SCALE)
  if type(smPanelSync) == "function" then pcall(smPanelSync) end
  return SM_DEF_ALPHA, SM_DEF_SCALE
end

-- ===== 斜杠命令 =====
-- ★★★1.74.29 用户决定：**放弃对 UIParent 的显示操作** —— 原「开图保持界面」(keepui) 功能**整块删除**。
-- 原因（已定案）：本客户端开图时会把 UIParent 隐藏；我们反复 UIParent:Show() 顶回会与客户端
--   形成**互抢**，表现就是「地图间隔地自动重新打开」（用户实测确认）。⇒ 从此**不再碰 UIParent 的显隐**。
-- 若将来还想要「开图时看到小地图/动作条」，走**不操作 UIParent** 的路线（改挂子件，见 EH_DebugBox 的 /edb uikids 实验）。
do
  -- 顺手清掉旧存档里的相关键（避免留一份没人读的配置）
  EH_SIMPLEMAP_CFG = EH_SIMPLEMAP_CFG or {}
  EH_SIMPLEMAP_CFG.keepUI = nil
  EH_SIMPLEMAP_CFG.keepUIStat = nil
  EH_SIMPLEMAP_CFG.keepUIMode = nil
end

-- ★★★1.74.29 用户决定：本模块从**独立子插件**改为**主插件的工具模块**（tools/SimpleMap.lua）。
--   工具箱「地图工具 → 简易地图」开关 = 应用 / 复位简易地图效果（藏黑幕 + 透明 + 键盘 + 位置）。
function EVAL_SM_ENABLED()
  local tb = smTbCfg(true) -- 读口静默（写口/面板会如实报一次）
  return (tb and tb.simpleMap) and true or false
end

function EVAL_SM_SET(on)
  -- ★写**配置真值**（与 EVAL_SM_ENABLED() 读的同一处）：1.74.29 之后 simpleMap 不是子插件了，
  --   旧接线走 EVAL_PLUGIN_SET("simpleMap") 在 SUBADDONS 里查不到 ⇒ 一次都没写进去（勾选框点了不生效，静默）。
  -- ★★1.74.36-2：`tbCfg` 是 Toolbox 的**文件局部**（模块里是 nil）⇒ 必须走它的全局出口 EVAL_TB_CFG()；
  --   读不到时 smTbCfg(false) 会**如实播报**，绝不假装写成功。
  local tb = smTbCfg(false)
  if tb then tb.simpleMap = on and true or false end
  if on then
    -- ★★★1.74.36-3：**开启即套默认档**（缩放 0.7 / 透明度 0.7 / GUI重开 不启用）——用户原话
    --   「开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」；先套默认值，再应用/就位。
    local a, s = smApplyDefaults()
    pcall(featKeep)   -- 事件帧就位（开图时自动应用）
    pcall(featApply)  -- 立刻应用一次
    P(string.format("简易地图：已启用（默认档：缩放 %.2f / 透明度 %.2f / GUI重开 %s；面板或 Shift/Ctrl+滚轮可再调）",
      s, a, smReopenOn() and "开" or "关"))
  else
    pcall(featReset)  -- 透明/缩放/位置复位
    P("简易地图：已停用（已复位：透明度 1 / 缩放 1 / 位置回屏幕中央）")
  end
  return true
end

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
    elseif msg == "gui" or msg == "重开" or msg == "显示gui" or string.find(msg, "^gui%s") == 1 or string.find(msg, "^重开%s") == 1 then
      -- ★1.74.35-3 改名：「显示GUI」→「GUI重开」（`gui` 旧别名保留，别名不冲突由 GO ALIAS UNIQUE CHECK 守的是 /eh go，这里是 /ehm）
      --   用法：/ehm gui [on|off|show]（или/或 /ehm 重开 …）
      local sub = string.lower(string.match(msg, "^%S+%s+(.+)$") or "")
      if sub == "on" or sub == "开" then
        EVAL_SM_GUIREOPEN_SET(true)
      elseif sub == "off" or sub == "关" then
        EVAL_SM_GUIREOPEN_SET(false)
      elseif sub == "show" or sub == "试" then
        if not smReopenOn() then
          P("GUI重开 当前为关 ⇒ **按你的要求不执行**任何重显操作")
        else
          local vis, blocked = featShowGUI()
          P("GUI重开：手动重显最外层 → " .. (vis and "已可见" or ("仍被隐藏" .. (blocked and "（客户端又藏回去了）" or ""))))
        end
      end
      P("GUI重开 当前 = " .. (smReopenOn() and "开" or "关") .. "（真值 SM_CFG.guiReopen=" .. tostring(SM_CFG.guiReopen) .. "；nil/false=关【默认】，true=开）")
      for _, ln in ipairs(EVAL_SM_GUIREOPEN_TIPS()) do P(ln) end
      if SM_CFG.guiLast then P("上次开图结果：" .. tostring(SM_CFG.guiLast)) end
      P("用法：/ehm gui on | off | show（也认 重开 开|关|试）")
    elseif msg == "mapfit" or msg == "叠加层" or string.find(msg, "^mapfit%s") == 1 or string.find(msg, "^叠加层%s") == 1 then
      -- ★1.74.35-4：地图探索叠加层随缩放自动适配（默认开）；本命令用于关掉 / 取证 / 还原
      local sub = string.lower(string.match(msg, "^%S+%s+(.+)$") or "")
      if sub == "on" or sub == "开" then
        EVAL_SM_MAPFIT_SET(true)
      elseif sub == "off" or sub == "关" then
        EVAL_SM_MAPFIT_SET(false)
      elseif sub == "restore" or sub == "还原" then
        smFitRestore(false)
      else
        smFitDiag()
      end
      P("用法：/ehm mapfit on | off | restore | diag（不给子命令 = diag）")
    elseif msg == "reset" or msg == "复位" then
      featReset()
    elseif msg == "default" or msg == "默认" or msg == "默认档" then
      -- ★1.74.36-3 取证/手动口：把默认档（0.7 / 0.7 / GUI不启用）重新套一遍并如实报出来。
      --   与「工具箱开关从关→开」走的是**同一个**函数（smApplyDefaults），所以这里能证明真机行为。
      local a, s = smApplyDefaults()
      P(string.format("默认档已套用：缩放 %.2f / 透明度 %.2f / GUI重开 %s", s, a, smReopenOn() and "开" or "关"))
      P(string.format("当前真值：alpha=%s scale=%s guiReopen=%s（面板/滚轮可再调）",
        tostring(SM_CFG.alpha), tostring(SM_CFG.scale), tostring(SM_CFG.guiReopen)))
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
      P("正式版已生效：开图自动生效（藏黑幕/透明/键盘）；Shift+滚轮=透明度 · Ctrl+滚轮=缩放 · 金色条=拖动 · /ehm reset=复位 · /ehm default=套默认档(0.7/0.7/GUI关)")
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

-- ============ 工具箱那一行（**嵌入点的被调方**）============
-- 工具箱只做两件事：模型数据里写一行 `{ t = "mod", mod = "simpleMap", … }`，渲染段按名字取这里的函数调一次。
--   控件、几何、tooltip、下拉、结算**全在本文件里**（与 LayerFix / DragFrames 同一套规矩）。
--   ★这一行**有**勾选框（模型里不写 `noChk`）：勾选框 = 本工具开/关（真值 = `tbCfg().simpleMap`，
--     与 `EVAL_SM_ENABLED()` 同源、与「子插件」Tab 无关 —— 本模块 1.74.29 起就是主插件的工具模块）。
--   ★`[设置]` = **多选下拉**（`EVAL_DD_OPEN` 的 multi 模式），目前唯一条目 = 「GUI重开」，
--     默认**不勾**（关）；勾上 = 开图时重显最外层 GUI（副作用见 TB_SM_GUIREOPEN_TIP*）。
local SM_TIP_W = 460

-- 真值读写（**唯一入口**）：读走 `EVAL_SM_ENABLED()`，写走 `EVAL_SM_SET()`（它同时把 tbCfg() 写进去 + 立刻应用/复位）
function EVAL_SM_GUIREOPEN_ON() return smReopenOn() end

function EVAL_SM_GUIREOPEN_SET(on)
  SM_CFG.guiReopen = on and true or false
  P("GUI重开 = " .. (smReopenOn() and "开（开图时重显最外层 GUI）" or "关（开图时不做任何额外 GUI 动作）"))
  return true
end

-- 行内摘要（**现算**，不缓存：勾选/滚轮改完立刻重画）
--   ★1.74.36-3：末尾带上「默认档」三个值（都从 SM_DEF_* 现取，绝不写第二份字面量）——
--     用户看悬停就知道「关掉再开回来会回到什么档位」，不用猜。
function EVAL_SM_SUMMARY()
  return string.format("缩放 %.2f · 透明 %.2f · GUI重开 %s（默认档 %.2f / %.2f / %s）",
    tonumber(SM_CFG.scale) or SM_DEF_SCALE, tonumber(SM_CFG.alpha) or SM_DEF_ALPHA,
    smReopenOn() and "开" or "关",
    SM_DEF_SCALE, SM_DEF_ALPHA, SM_DEF_GUIREOPEN and "开" or "关")
end

-- 默认档那一句（在悬停里**独立成行**；与真值同源 = SM_DEF_*，不许另拼文案）
function EVAL_SM_DEF_TIP()
  return string.format("开启默认档：缩放 %.2f · 透明度 %.2f · GUI重开 %s（每次开启都套用；开着时可随时再调）",
    SM_DEF_SCALE, SM_DEF_ALPHA, SM_DEF_GUIREOPEN and "开" or "关")
end

-- ===== 叠加层适配（1.74.35-4）：读写口 + 读值口 =====
-- 真值 `SM_CFG.mapFit`：nil = 默认开（用户：「要默认启动的功能」），只有显式 false = 关
function EVAL_SM_MAPFIT_ON() return smFitOn() end

function EVAL_SM_MAPFIT_SET(on)
  SM_CFG.mapFit = on and true or false
  P("叠加层适配 = " .. (smFitOn() and "开（随地图缩放自动对齐探索层）" or "关（不再碰叠加层几何）"))
  return true
end

-- 行 tooltip 里那句（与真值同源；行渲染处取它，别处不许再拼一遍文案）
function EVAL_SM_MAPFIT_TIP()
  return "叠加层适配：" .. (smFitOn() and "开" or "关")
    .. "（WorldMapOverlay/Highlight 按地图缩放 ×es 折算，底瓦片不动；/ehm mapfit 可关或取证）"
end

-- 提示行（★用户原话里的副作用必须**如实写出来**，不许只写「可能有影响」）
function EVAL_SM_GUIREOPEN_TIPS()
  return { L("TB_SM_GUIREOPEN_TIP1"), L("TB_SM_GUIREOPEN_TIP2"), L("TB_SM_GUIREOPEN_TIP3") }
end

-- 菜单内容（与行渲染**同源**：勾选态 = 真值现算，唯一来源 = SM_CFG.guiReopen）
--   返回 items, locked, tips, sel, keys —— 与 EVAL_DD_OPEN(…, {multi=true, selected=sel, …}) 同口径
function EVAL_SM_MENU()
  local items = { L("TB_SM_GUIREOPEN") }
  local locked = {}
  local tips = { EVAL_SM_GUIREOPEN_TIPS() }
  local keys = { "guiReopen" }
  local sel = {}
  if smReopenOn() then sel[1] = true end
  return items, locked, tips, sel, keys
end

-- ★★★`pcall` **只保留被调函数的第一个返回值**（本客户端实测坑，1.74.35-3 当场踩到）：
--   想「既 pcall 兜住、又拿到多返回」必须包一层函数 —— `pcall(EVAL_SM_MENU)` 只会吐出 items，
--   keys/locked/tips/sel 全变 nil ⇒ 下拉弹不出来，还会被那句「模块没交回菜单内容」误报成「没有可选的项」。
local function smMenuAll()
  local items, locked, tips, sel, keys = EVAL_SM_MENU()
  return items, locked, tips, sel, keys
end

local function smRow(r, it)
  if type(r) ~= "table" then return false end
  -- 主开关：读=EVAL_SM_ENABLED（tbCfg().simpleMap），写=EVAL_SM_SET（配置 + 应用/复位一起做）
  r.get = function() return EVAL_SM_ENABLED() end
  r.set = function(v) pcall(EVAL_SM_SET, v and true or false) end
  -- ★1.74.36 用户：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」
  --   ⇒ 行上不显示 `缩放 0.70 · 透明 0.70 · GUI重开 关` 这串摘要；它只在 [设置] 的悬停说明里现读（见下面 EVAL_SM_SUMMARY()）。
  r.extra:Hide()
  r.add.text:SetText(L("TB_LDDRAG_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, SM_TIP_W)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_SIMPLEMAP_TIP"), 1, 0.85, 0.30)
    for _, ln in ipairs(EVAL_SM_GUIREOPEN_TIPS()) do pcall(tip.AddLine, tip, ln, 0.88, 0.88, 0.88) end
    pcall(tip.AddLine, tip, EVAL_SM_MAPFIT_TIP(), 0.72, 0.92, 0.72) -- ★1.74.35-4 叠加层适配状态（默认开）
    pcall(tip.AddLine, tip, EVAL_SM_DEF_TIP(), 0.92, 0.82, 0.55) -- ★1.74.36-3 开启默认档 0.7/0.7/GUI不启用
    pcall(tip.AddLine, tip, EVAL_SM_SUMMARY(), 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then
      say("打开地图设置失败：下拉控件未载入")
      return
    end
    local ok, items, locked, tips, sel, keys = pcall(smMenuAll)
    if not ok or type(items) ~= "table" or type(keys) ~= "table" then
      say("打开地图设置失败：模块没交回菜单内容（这次没弹出来，不是「没有可选的项」）")
      return
    end
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      -- 分组标题行 keys[pi] 为空（locked 行也点不到；这里再兜一层，绝不拿它去写配置）
      local key = keys[pi]
      if type(key) ~= "string" or key == "" then return end
      if key == "guiReopen" then pcall(EVAL_SM_GUIREOPEN_SET, on == true) end
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = sel, locked = locked, tips = tips })
  end)
  return true
end

-- 登记进**模块行注册表**（工具箱渲染段按 `it.mod` 取它）。
--   ★两边谁先载入都成立：表不存在就现建（同一个全局表），绝不依赖 toc 顺序。
local SM_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(SM_TB_ROWS) ~= "table" then
  SM_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", SM_TB_ROWS)
end
SM_TB_ROWS["simpleMap"] = smRow
function EVAL_SM_TB_REGISTER()
  local t = rawget(_G, "EVAL_TB_MOD_ROWS")
  if type(t) ~= "table" then
    t = {}
    rawset(_G, "EVAL_TB_MOD_ROWS", t)
  end
  t["simpleMap"] = smRow
  return true
end

-- ============ 读值口（测试/诊断用；★不复刻逻辑：真值直给字段，动作走真实入口）============
function EVAL_SM_TEST_GUIREOPEN() return SM_CFG.guiReopen, smReopenOn() end
function EVAL_SM_TEST_GUI_CALLS() return FEAT.guiCalls or 0 end
function EVAL_SM_TEST_GUI_CALLS_RESET() FEAT.guiCalls = 0 return true end

-- ★开图路径触发器（读值口）：只跑 `featKeep` + `featApply`（= 真实开图时走的那两条路径），
--   **不改任何配置**。为什么必须有它：1.74.36-3 起 `EVAL_SM_SET(true)` 会先**套默认档**（含
--   「GUI重开 不启用」）⇒ 想验「用户在下拉里勾上 GUI重开 之后开图到底会不会重显」，
--   就不能再用 SET 间接触发（那会把刚勾上的开关又关掉）。真实用户流程也正是这个顺序：
--   先开模块 → 再在 [设置] 里勾 GUI重开 → 然后开图。
function EVAL_SM_TEST_APPLY()
  pcall(featKeep)
  pcall(featApply)
  return true
end

-- ★1.74.36-3 默认档读值口：先 3 个**常量**、再 3 个**当前真值**。
--   ★断言一律从这里取（不许在测试里复刻 0.7/0.7/false 三个字面量 = 同源自比）。
function EVAL_SM_TEST_DEFAULTS()
  return SM_DEF_ALPHA, SM_DEF_SCALE, SM_DEF_GUIREOPEN,
    tonumber(SM_CFG.alpha), tonumber(SM_CFG.scale), SM_CFG.guiReopen
end

-- ★地图设置面板：刷新口是否已落地 + 两个值标签**实际显示的文字**（面板没建过 ⇒ nil）。
--   ★这也是「默认档有没有真的落到界面上」的唯一可断言证据（真机上就是看那两个数字）。
function EVAL_SM_TEST_PANEL()
  local okSync = (type(smPanelSync) == "function")
  local a, s = nil, nil
  local fsA, fsS = SM_PANEL.valA, SM_PANEL.valS
  if fsA and type(fsA.GetText) == "function" then
    local ok, v = pcall(fsA.GetText, fsA)
    if ok then a = v end
  end
  if fsS and type(fsS.GetText) == "function" then
    local ok, v = pcall(fsS.GetText, fsS)
    if ok then s = v end
  end
  return okSync, a, s
end
-- 迁移四态（★走**真实**的 smMigrateReopen，不在测试里复刻一遍判据）：
--   返回 迁移后的真值, 判据结果, 迁移后是否还留着老键（应当恒为 nil）
function EVAL_SM_TEST_MIGRATE(old)
  SM_CFG.guiReopen = nil
  SM_CFG.showGUI = old
  smMigrateReopen()
  local v = SM_CFG.guiReopen
  local on = smReopenOn()
  local legacy = SM_CFG.showGUI
  SM_CFG.showGUI = nil -- 模拟「载入期清老键」那一步，避免污染其它用例
  return v, on, legacy
end
function EVAL_SM_TEST_LEGACY_KEYS() return SM_CFG.showGUI, SM_CFG.keepUI, SM_CFG.keepUIStat, SM_CFG.keepUIMode end
function EVAL_SM_TEST_ROW() return smRow end

-- ===== 叠加层适配（1.74.35-4）的读值口 =====
function EVAL_SM_TEST_MAPFIT() return smFitOn(), SM_CFG.mapFit, SMFIT.burst, SMFIT.es end
function EVAL_SM_TEST_MAPFIT_GAPS() return SMFIT_BURST_GAP, SMFIT_BURST_SEC, SMFIT_IDLE_GAP end
function EVAL_SM_TEST_MAPFIT_TARGETS() return table.getn(smFitTargets()) end
function EVAL_SM_TEST_MAPFIT_APPLY(es) local c, r, rec = smFitApply(tonumber(es) or 1, true) return c, r, rec end
function EVAL_SM_TEST_MAPFIT_ORIG() local n = 0 for _ in pairs(SM_CFG.mapFitOrig or {}) do n = n + 1 end return n end
function EVAL_SM_TEST_MAPFIT_REC() local n = 0 for _ in pairs(SMFIT.rec or {}) do n = n + 1 end return n end
function EVAL_SM_TEST_MAPFIT_BURST(sec) SMFIT.burst = tonumber(sec) or 0 return SMFIT.burst end
function EVAL_SM_TEST_MAPFIT_RESTORE() return smFitRestore(true) end
-- 夹具自清（测试换过 `_G.WorldMapDetailFrame` 的假帧之后必须还原：内存记录 + 存档原值 + 开关一起复位）
function EVAL_SM_TEST_MAPFIT_RESET()
  SMFIT.rec = {}
  SMFIT.open, SMFIT.es, SMFIT.burst = false, nil, 0
  SM_CFG.mapFitOrig = nil
  SM_CFG.mapFit = nil
  return true
end
-- ★「一次过渡」的可测入口：复刻 tick 里那两行过渡判据（burst 期开始 = 顶满节拍），供断言直接验节奏
function EVAL_SM_TEST_MAPFIT_TRANSITION(open, es)
  SMFIT.burst = 0
  if open then SMFIT.burst = SMFIT_BURST_SEC end
  if es and SMFIT.es and math.abs(tonumber(es) - SMFIT.es) > 0.001 then SMFIT.burst = SMFIT_BURST_SEC end
  SMFIT.open, SMFIT.es = (open and true or false), (tonumber(es) or SMFIT.es)
  return SMFIT.burst
end
function EVAL_SM_TEST_MENU_RAW()
  -- ★必须走 smMenuAll（包一层）：`pcall(EVAL_SM_MENU)` 只留第一个返回值 ⇒ keys 恒 nil、这里会恒返回 nil
  local ok, items, locked, tips, sel, keys = pcall(smMenuAll)
  if not ok or type(items) ~= "table" or type(keys) ~= "table" then return nil end
  local nSel = 0
  for _ = 1, table.getn(sel or {}) do nSel = nSel + 1 end
  local nTips = 0
  if type(tips) == "table" and type(tips[1]) == "table" then nTips = table.getn(tips[1]) end
  return { items = items, keys = keys, selN = nSel, tipLines = nTips, summary = EVAL_SM_SUMMARY() }
end
