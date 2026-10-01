-- ============================================================
-- EH_SimpleMap 简易世界地图（透明度可调） v0.2.0
-- probe/worldmap-minimap 分支产物：S_WorldMap 移植 EmberVeil（小地图不做，用户拍板）。
-- 全部能力经 probe 系列实测定案（见「正式版功能」段注释）；探针保留为诊断命令。
-- ============================================================

-- ★★★1.74.29 修：本客户端每个 `## SavedVariables:` 行**只认一个变量名**
--   （客户端自带的几个插件在清单里都是一行一名）。之前写成「A B -- 注释」被整串当成一个名字 →
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

-- ★★★1.75.9 修（真机事故：载入后开启「缩放大地图」⇒ 探索层纹理折了两遍，且设置一个都没落存档）
--   根因之一 = **在文件执行期缓存了存档子树**。本项目已定案：`EVAL_HELP_CONFIG` 在**文件执行期还是空表**
--   （真值要等 VARIABLES_LOADED；见 DragFrames 的「未就位就不写」纪律、EvalHelp 首部注释），
--   于是旧写法 `return EVAL_HELP_CONFIG.simpleMapCfg` 拿到的是**一张临时表** —— 客户端稍后把
--   `EVAL_HELP_CONFIG` 整个换成存档里那份 ⇒ 本模块此后所有写入都进了**没人保存的孤儿表**。
--   真机证据（本题就是靠它定案的）：SavedVariables 里 `tb.simpleMap = true` 在，而 `simpleMapCfg` **整块不存在**。
--   ⇒ 改成**懒代理**：每次读写都现取 `rawget(_G,"EVAL_HELP_CONFIG").simpleMapCfg`（单一真值，永不缓存）。
local function smCfgLive()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then
    c = {}
    rawset(_G, "EVAL_HELP_CONFIG", c)
  end
  if type(c.simpleMapCfg) ~= "table" then c.simpleMapCfg = {} end
  return c.simpleMapCfg
end

EH_SIMPLEMAP_CFG = setmetatable({}, {
  __index = function(_, k) return smCfgLive()[k] end,
  __newindex = function(_, k, v) smCfgLive()[k] = v end,
})

local SM = { lines = {} }

local function P(msg)
  msg = tostring(msg)
  table.insert(SM.lines, msg)
  -- ★★★1.75.8（用户要求）：本模块自己的播报也跟「全局 → 调试日志」总闸门
  --   （`EVAL_CHAT_ON` = Core 里那个**同一个**判据，不另立一份）。
  --   ★`SM.lines`（模块探针自己的读数环）照记 —— 那是数据层，与「说不说话」分开。
  if type(EVAL_CHAT_ON) == "function" and not EVAL_CHAT_ON() then return end
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

-- ★★★1.75.10（用户报障）：「世界地图缩放开启之后，每次插件重载的初始位置能否居中。现在他有时候会乱跳到左下角位置」
--   ⇒ **跨会话的位置记忆作废**：每次载入后的**第一次开图一律居中**，并把存档里那份历史偏移清掉；
--     本会话内用户真拖过之后才记位置（`featSavePos` 照旧写 `SM_CFG.px/py`，但下次载入又会被清）。
--   ★为什么要清而不是「修好折算公式」：`px/py` 是本客户端**几何读回含缩放**（见 `smEffScale` 的注释）下按
--     折算公式写出的屏幕中心偏移，一旦口径对不上，这个值会被**永久继承**——每次开图都按它摆位置，
--     表现就是用户说的「有时候乱跳到左下角」（还会随开关/拖拽**累积**）。位置宁可不可跨会话记忆，也不要一个会漂的数。
--   ★为什么还要一个**窗口期**：客户端自己的开图流程可能在我们 `featApply` **之后**才摆位置
--     （与「黑幕被重新 Show 出来」是同一条竞态）⇒ 光居中一次会「有时候没居上」。
--     窗口期内 `featKeep` 逐拍重申居中；用户一拖拽（`OnDragStart` 把窗口清 0）立刻让位，绝不跟用户抢。
--     ★有界（25 拍 ≈ 开图后 5 秒，`featKeep` 的节拍是 0.2s），不是常驻轮询。
local SM_RECENTER_TICKS = 25

-- ★★★1.75.5（用户报障：「地图每次打开.会闪烁一次背景黑幕?这个如何避免?」）：
--   **开图瞬时遮蔽窗口**。成因：藏黑幕原来只挂在两个地方 —— `featApply`（在 tick 的 **0.2s 节拍块**里）
--   与 `featKeep`（同 0.2s 节拍）；而客户端**每次开图都会自己把黑幕 `Show` 出来**（而且是**在我们之后**，见
--   featKeep 的竞态注释）⇒ 从「开图」到「我们藏住」最多空 0.2 秒 ⇒ 用户看到的就是**黑闪一下**。
--   修法：开图那一拍起，在下面这个**有界**窗口内**逐帧**重申藏黑幕（`Hide` 对已隐藏的帧是空操作，`IsShown` 极廉价），
--   窗口一过就回到 0.2s 节拍（不给常驻每帧加负担）。★与「开图后逐拍重申居中」（SM_RECENTER_TICKS）是同一套手法。
--   取证：`featHideBlackout` 会记一条「开图后 N ms 藏住」（进 mapFitTrace；详细档还会上屏）。
local SM_BLACKOUT_SEC = 0.6

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
-- ★1.75.10 新增两位（位置口径，见 SM_RECENTER_TICKS 的注释）：
--   · `posArmed` = **本次会话还没「居中过一次」**（载入期就是 true ⇒ /reload 后第一次开图必居中）；
--   · `recenter` = 居中窗口剩余拍数（`featKeep` 每拍减 1；拖拽开始清 0）。
local FEAT = { applied = false, built = false, guiCalls = 0, escAdded = false, torn = false,
               posArmed = true, recenter = 0 }

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
-- ★★★1.75.9：**再武装也要前向声明** —— `featApply`（定义在前面）里会调它；定义写在后面而这里不声明，
--   那里 `pcall(featRearm)` 调的就是**全局 nil**（pcall 不报错、只是什么都没做）⇒ 关闭时藏起来的拖拽柄
--   永远回不来 = 用户报的「拖拽移动失效」。组 232⑥ 当场抓到这个（实测 fd.shown=false）。
local featRearm = nil
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

-- ★★★1.75.10 新增（用户报障见 SM_RECENTER_TICKS 的注释）：位置口径的三件套。
-- ① `featCenterNow` = **纯动作**：把地图摆回屏幕正中（不动配置、不记状态、可反复调）。
--    ★已居中就**不写** —— 窗口期内逐拍重申，盲写就是白写 25 次（本客户端 ClearAllPoints+SetPoint 会触发锚点重算）。
--    ★读不到 `GetPoint`（老客户端没有这个 API）时**如实退回盲写**，绝不假装「已经居中了」。
local function featCenterNow(wm)
  wm = wm or featWm()
  if not wm then return false end
  if type(wm.ClearAllPoints) ~= "function" or type(wm.SetPoint) ~= "function" then return false end
  if type(wm.GetPoint) == "function" then
    local okp, p, rel, rp, gx, gy = pcall(wm.GetPoint, wm)
    -- ★比较相对帧用**对象身份**（本项目既有判据：`GetName()` 可能为 nil，按名字筛会一条都匹配不上）
    if okp and p == "CENTER" and rel == UIParent and rp == "CENTER"
      and (tonumber(gx) or 0) == 0 and (tonumber(gy) or 0) == 0 then
      return true
    end
  end
  pcall(wm.ClearAllPoints, wm)
  pcall(wm.SetPoint, wm, "CENTER", UIParent, "CENTER", 0, 0)
  return true
end

-- ② `featCenterOnce` = **本次会话的第一次开图**：丢掉跨会话的历史偏移 + 真摆正中 + 开居中窗口期。
--    ★只有「第一次」才做（`FEAT.posArmed`）——本会话内用户拖过之后，位置记忆照旧生效。
local function featCenterOnce(wm)
  wm = wm or featWm()
  local had = (SM_CFG.px ~= nil) or (SM_CFG.py ~= nil)
  SM_CFG.px, SM_CFG.py = nil, nil -- ① 清掉会被永久继承的那份历史偏移（清的是存档真值，不是临时缓存）
  featCenterNow(wm)               -- ② 真摆正中（客户端自己的 layout 缓存可能把图摆到别处 ⇒ 必须主动写）
  FEAT.posArmed = false           -- ③ 本会话只做一次
  FEAT.recenter = SM_RECENTER_TICKS
  if had then
    P("简易地图：已清掉历史位置偏移 —— 每次载入的**第一次开图一律居中**（本会话内拖动后才会记位置）")
  end
  return true
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
-- ★★★1.75.52（用户定：整条「探索层适配」摘除）：这一段原来的 `smFitHold`（抓原值窗口剩余秒数）与
--   `smFitGhostShow`（「未适配先隐形」的还回口）**随整条适配一起删掉了** —— 「打开世界迷雾」（表驱动全渲染）
--   是替代方案，可见性由它自己按表决定，不再有「先隐形、折算完再显示」这一套。
-- ★★★1.75.45：`mfLog` 也必须提前声明 —— 它的**首次使用在 1727 行**（`featHideBlackout`），
--   而定义在 2000 行之后 ⇒ 不声明的话那几处绑全局 nil、被 `pcall` 静默吞掉（见其定义处的注释）。
--   ★`smFitSayV` 同族（`probe_localorder.js` 在 1.75.45 把它扫出来）：首次使用 1744 行（黑幕耗时取证行）、
--   定义 2123 行 ⇒ 「黑幕遮蔽：开图后 N ms 藏住 M 层」那条**上屏**取证行同样是死的（`mfLog` 那条进环、这条上屏）。
local mfLog
local smFitSayV
-- ★★★1.75.55：`MDQ` 也必须**提前声明**（同族老雷）：`featApplyScale`（**本行下面就是**）要读
--   `MDQ.fit.hold`（探索层折算的「自然档抓原值」窗口）—— 而 `MDQ` 的定义在 2005 行。不声明的话
--   那两处绑的是**全局 nil** ⇒ `attempt to index a nil value (global 'MDQ')` 被外层 `pcall` 静默吞掉
--   ⇒ 表现是「地图**根本不再缩放**」而日志一个字都没有（本项目已多次记录这种前向声明坑）。
local MDQ
local function featApplyScale(s)
  local w = featWm()
  if not w then return end
  s = tonumber(s) or 1
  -- ★1.75.52：原来这里还有一道「抓原值窗口内先不缩放」的闸门（`smFitHold`）—— 随探索层适配整条摘除。
  -- ★★★1.75.55：**又加回来了**（探索层折算需要「自然档抓原值」）—— 只在「打开世界迷雾」**关着**且
  --   折算的抓原值窗口还开着时挡一下；窗口一收（原值抓齐 / `MDQ.FIT_HOLD_SEC` 到点）就照常套缩放。
  if (not EVAL_WF_ON()) and (tonumber(MDQ.fit and MDQ.fit.hold) or 0) > 0 and math.abs(s - 1) > 0.001 then return end
  -- ★★★1.75.9：**同一档只写一次**。开启路径里 `smApplyDefaults` / `featApply` / `featKeep` 三处都会调它，
  --   若本客户端 SetScale 是累乘语义（或客户端自己也记一份），一次开启就会被缩两遍 —— 用户报的正是「一开就缩两遍」。
  --   做法：先读回 `GetScale()`，已经是这档就**不写**（写出去的值与读回一致才算「已经是」）。
  if type(w.GetScale) == "function" then
    local ok, cur = pcall(w.GetScale, w)
    if ok and tonumber(cur) and math.abs(tonumber(cur) - s) <= 0.001 then return end
  end
  pcall(w.SetScale, w, s)
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
    -- ★★★1.75.9（关掉零动作的同族）：总开关关着 ⇒ 一个写都不许发；
    --   **裸滚仍然透传原生**（别把客户端自己的缩放吃掉）。
    if not EVAL_SM_ENABLED() then
      if type(old) == "function" then pcall(old) end
      return
    end
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then
      local a = (tonumber(SM_CFG.alpha) or 1) + d / 10
      if a < 0.3 then a = 0.3 end
      if a > 1 then a = 1 end
      SM_CFG.alpha = a
      featApplyAlpha(a)
      -- ★★★1.75.5（用户：「在使用快捷键设置地图缩放和透明度之后，地图设置内的值要能同步更新.双向同步更新.根源数据保持统一」）：
      --   滚轮与面板的 [-] / [+] 写的是**同一份真值**（`SM_CFG.alpha`/`SM_CFG.scale`）——缺的只是**把面板标签刷一遍**。
      --   ⇒ 改完真值立刻走**同一个**刷新口 `smPanelSync`（它是前向声明的 local，面板没建过时是 nil ⇒ 守卫后静默跳过，
      --     等面板建出来时构造函数会按真值初始化那两个标签，见 `SM_PANEL` 段）。
      if type(smPanelSync) == "function" then pcall(smPanelSync) end
    elseif type(IsControlKeyDown) == "function" and IsControlKeyDown() then
      local s = (tonumber(SM_CFG.scale) or 1) + d / 10
      if s < 0.5 then s = 0.5 end
      if s > 1 then s = 1 end
      SM_CFG.scale = s
      featApplyScale(s)
      if type(smPanelSync) == "function" then pcall(smPanelSync) end
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
      -- ★1.75.10：用户开始拖了 ⇒ **立刻让出居中窗口期**（否则窗口期内每拍把他刚拖到的位置拉回正中 = 跟用户抢）
      FEAT.recenter = 0
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
      -- ★1.75.5：标签刷新**只走这一个口**（滚轮那侧也调它）⇒ 真值与界面永远同源，不再有第二份写法
      if type(smPanelSync) == "function" then pcall(smPanelSync) end
    end, 0.3, 1, 0.05)
  valS = mkRow("缩放", -52,
    function() return tonumber(SM_CFG.scale) or 1 end,
    function(d)
      SM_CFG.scale = clampV((tonumber(SM_CFG.scale) or 1) + d, 0.5, 1)
      featApplyScale(SM_CFG.scale)
      if type(smPanelSync) == "function" then pcall(smPanelSync) end
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

  -- ★★★1.75.6（用户两轮要求：「点击[面板]外任意位置自动关闭」→「**需要点击地图以外也能触发关闭**」）：
  --   **全屏 click-catcher**（本项目既有范式，见 DragFrames）：
  --     · 父级挂地图帧（strata 与面板**同一档** ⇒ 不会因为 strata 更高反而盖住面板自己；关图时自动消失）；
  --     · **锚点是 UIParent 的两个角** ⇒ 铺满**整个屏幕**（不只是地图帧）⇒ 点地图以外也能关；
  --       ★锚点用 UIParent 的坐标空间（偏移 0,0），所以外框被缩放到 0.7 时它照样铺满屏幕。
  --     · 层级 = 面板 − 5（`SetFrameLevel`，本项目铁律：用 strata 抬高的做法在案是失败法）；
  --     · 与面板**同生共死**：`smCfgShow` 是唯一出口 + 面板 `OnHide` 兜底 ⇒ 绝不常驻吃点击。
  local cfgCatch = CreateFrame("Button", "EH_SM_CFGCATCH", wm)
  pcall(cfgCatch.SetPoint, cfgCatch, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  pcall(cfgCatch.SetPoint, cfgCatch, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
  pcall(cfgCatch.SetFrameLevel, cfgCatch, plv + 105) -- 面板 = plv+110 ⇒ catcher 低 5 级
  pcall(cfgCatch.EnableMouse, cfgCatch, true)
  if type(cfgCatch.RegisterForClicks) == "function" then
    pcall(cfgCatch.RegisterForClicks, cfgCatch, "LeftButtonUp", "RightButtonUp")
  end
  pcall(cfgCatch.Hide, cfgCatch)
  -- 面板显示/隐藏的**唯一出口**（点按钮、点外面、关功能三条路都走它）
  local function smCfgShow(show)
    if show then
      pcall(cfgPanel.Show, cfgPanel)
      pcall(cfgCatch.Show, cfgCatch)
    else
      pcall(cfgPanel.Hide, cfgPanel)
      pcall(cfgCatch.Hide, cfgCatch)
    end
  end
  pcall(cfgCatch.SetScript, cfgCatch, "OnClick", function()
    smCfgShow(false) -- ★点面板外任意位置 = 关面板（含右键）
  end)
  -- ★兜底：面板因**任何**原因隐藏（关图 / ESC 关图 / 收尾 / 客户端重排）时，catcher 必须跟着收 ——
  --   它是铺满屏幕的 Button，留着会吃掉所有点击（本项目在案的事故类型）。
  pcall(cfgPanel.SetScript, cfgPanel, "OnHide", function()
    pcall(cfgCatch.Hide, cfgCatch)
  end)
  FEAT.cfgShow = smCfgShow -- 读值口/收尾用（关功能时把面板与 catcher 一起收）

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
    -- ★走唯一出口（面板与 catcher 同生共死）；点按钮本身也由 catcher 兜一层，行为一致
    if cfgPanel:IsShown() then smCfgShow(false) else smCfgShow(true) end
  end)


  if type(UISpecialFrames) == "table" then
    local found = false
    for _, n in ipairs(UISpecialFrames) do if n == "WorldMapFrame" then found = true end end
    if not found then
      pcall(table.insert, UISpecialFrames, "WorldMapFrame")
      FEAT.escAdded = true -- ★1.75.9：记下「是我们插的」⇒ 关闭时才知道该不该拿掉
    end
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
    -- ★★★1.75.9：关闭后本行不许再算（清理的另一半在 featTeardown，这里再加一道门，双保险）
    if not EVAL_SM_ENABLED() then pcall(ct.SetText, ct, "") return end
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

-- ★★★1.75.5（用户报障：「地图每次打开.会闪烁一次背景黑幕?这个如何避免?」+ 用户提议：「能否直接设置黑幕透明度是0」）：
--   **唯一出口** —— 遮蔽那两层黑幕（真凶 `WorldMapBlackout`，`BlackoutWorld` 顺手一起处理；probe8 反向排查定案）。
--   ★**两手一起做，缺一不可**：
--     ① `SetAlpha(0)` = **硬抗闪**：即使客户端把黑幕 `Show` 出来，它画出来的也是**完全透明**（不闪）；
--     ② `Hide()` = **保鼠标**：一个「显示着但透明」的全屏帧**照样会吃掉点击与悬停**（地图点不动 = 比黑闪更糟的 bug）
--        ⇒ 绝不能用「只归零 alpha 不 Hide」换那点性能（源码检查里有反向哨兵钉这条）。
--   ★改属性前**先抓原值**（本项目铁律）：原 alpha 记在 `FEAT.boA[帧名]`，关功能时由 `featBlackoutRestore` 还回去；
--     **读不到原值就不写 alpha**（宁可只 Hide —— 我们已经在用的那条路），绝不拿 0 冒充原值害用户还原不回。
--   ★为什么要抽成一个函数：原来这段在 `featApply` 与 `featKeep` 各写一份，现在再加上「开图瞬时窗口」就是**第三处** ——
--     三份循环迟早漂移（本项目铁律：判据/动作单一来源）。
--   返回：本次真遮住的层数（>=1 才算「遮住过」；0 = 本来就既透明又隐藏）
local function featHideBlackout()
  local hid = 0
  if type(FEAT.boA) ~= "table" then FEAT.boA = {} end -- 原 alpha 记账（每帧名一份）
  for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
    local b = _G[bn]
    if (type(b) == "table" or type(b) == "userdata") and type(b.Hide) == "function" then
      local touched = false
      -- ① alpha 归零（**先抓原值**；读不到就跳过这一步，只做 Hide）
      if type(b.SetAlpha) == "function" and type(b.GetAlpha) == "function" then
        if FEAT.boA[bn] == nil then
          local oka, av = pcall(b.GetAlpha, b)
          -- 读到了就记下原值；读不到记 `false`（= 已知「无法还原」，关功能时如实说明并保留字段）
          FEAT.boA[bn] = (oka and tonumber(av)) and tonumber(av) or false
        end
        if type(FEAT.boA[bn]) == "number" then
          local okc, cur = pcall(b.GetAlpha, b)
          if not okc or tonumber(cur) ~= 0 then
            pcall(b.SetAlpha, b, 0)
            touched = true
          end
        end
      end
      -- ② Hide（保鼠标；★只对「现在显示着」的动手 —— `IsShown` 读不到就照藏，「判不出就不拦」）
      local shown = true
      if type(b.IsShown) == "function" then
        local ok, v = pcall(b.IsShown, b)
        if ok then shown = (v == true or v == 1) end
      end
      if shown then
        pcall(b.Hide, b)
        touched = true
      end
      -- ③ **读回自证**（本项目纪律：写成功 ≠ 写进去生效）：alpha 没归零就如实记一笔（不静默）
      if type(FEAT.boA[bn]) == "number" and type(b.GetAlpha) == "function" then
        local okv, v = pcall(b.GetAlpha, b)
        if not okv or tonumber(v) ~= 0 then
          mfLog("黑幕：%s 的 alpha 归零**没生效**（读回 %s）⇒ 只靠 Hide 顶（客户端可能自己改回不透明）",
            tostring(bn), tostring(v))
        end
      end
      if touched then hid = hid + 1 end
    end
  end
  -- ★★开图瞬时遮蔽的**耗时取证**（治「开图闪一下黑幕」这条必须能量化：
      --   开图那一刻起，到我们第一次成功藏住它，中间隔了多少毫秒 —— 这就是用户看到的那一闪）
  if hid > 0 and (tonumber(FEAT.blackoutAt) or 0) > 0 and not FEAT.blackoutLogged then
    FEAT.blackoutLogged = true
    local dtms = ((type(GetTime) == "function") and GetTime() or 0) - tonumber(FEAT.blackoutAt)
    mfLog("黑幕遮蔽：开图后 %.0f ms 藏住 %d 层（瞬时窗口 %.1fs 内逐帧重申；0.2s 节拍那条路以前最坏要等 200ms）",
      dtms * 1000, hid, tonumber(SM_BLACKOUT_SEC) or 0)
    smFitSayV("黑幕遮蔽：开图后 %.0f ms 藏住 %d 层（这一闪就是这么来的；瞬时窗口 = %.1fs）",
      dtms * 1000, hid, tonumber(SM_BLACKOUT_SEC) or 0)
  end
  return hid
end

-- 开图时应用（幂等）：藏两层黑幕 + 键盘还给游戏 + 透明度/缩放/位置记忆
local function featApply()
  local wm = featWm()
  if not wm then return end
  featBuild(wm)
  pcall(featRearm) -- ★1.75.9：把关闭时藏起来的拖拽柄/坐标行**重新武装**（否则拖拽移动永久失效）
  pcall(featHideBlackout)
  if type(wm.EnableKeyboard) == "function" then pcall(wm.EnableKeyboard, wm, false) end
  featApplyAlpha(tonumber(SM_CFG.alpha) or 1)
  featApplyScale(tonumber(SM_CFG.scale) or 1)
  -- ★1.74.35-2：按「显示GUI」开关把**最外层 GUI**重新显示（关 ⇒ 一个动作都不做，不做额外动态重现）
  if smReopenOn() then
    local vis, blocked = featShowGUI()
    SM_CFG.guiLast = "开图 GUI重开：" .. (vis and "最外层 GUI 已重新显示" or "仍被隐藏（客户端又藏回去了）")
    P(SM_CFG.guiLast)
  end
  -- ★★★1.75.10（用户报障：「世界地图缩放开启之后，每次插件重载的初始位置能否居中。现在他有时候会乱跳到左下角位置」）：
  --   **本次载入的第一次开图 ⇒ 一律居中**（并清掉存档里那份会被永久继承的历史偏移）。
  --   之后（本会话内用户拖过）才走下面的 px/py 位置记忆 —— 即「位置记忆 = 会话内有效」。
  if FEAT.posArmed then
    pcall(featCenterOnce, wm)
  elseif tonumber(SM_CFG.px) and tonumber(SM_CFG.py)
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
  -- ★1.75.5：与 featApply 共用一个出口（藏黑幕 = 单一来源；开图瞬时窗口见 tick 里的 SM_BLACKOUT_SEC）
  pcall(featHideBlackout)
  local a = tonumber(SM_CFG.alpha) or 1
  local okA, cur = pcall(wm.GetAlpha, wm)
  if okA and tonumber(cur) and cur ~= a then featApplyAlpha(a) end
  local s = tonumber(SM_CFG.scale) or 1
  local okS, curs = pcall(wm.GetScale, wm)
  if okS and tonumber(curs) and math.abs(curs - s) > 0.001 then featApplyScale(s) end
  -- ★1.75.10：居中**窗口期**（见 SM_RECENTER_TICKS 与 featCenterOnce 的注释）—— 客户端自己的开图流程
  --   可能在我们 apply **之后**才摆位置（与「黑幕被重新 Show」同一条竞态）⇒ 窗口期内逐拍重申居中。
  --   `featCenterNow` 内部判「已经居中就不写」⇒ 正常情况这里只是读一次锚点，不会每拍重写。
  --   ★用户一拖拽（OnDragStart 清 0）立刻让位；本函数只在**地图开着**时被调用。
  if (tonumber(FEAT.recenter) or 0) > 0 then
    FEAT.recenter = FEAT.recenter - 1
    pcall(featCenterNow, wm)
  end
  -- ★1.74.35-2：开图期间持续保持**最外层 GUI** 可见（客户端自己的开图流程会再藏回去 ⇒ 每 tick 幂等重显）
  --   ★关掉 ⇒ 直接跳过（用户明确：不做额外 GUI 动态重现的操作）
  if smReopenOn() then pcall(featShowGUI) end
end

-- ★★★1.75.5（用户提议「能否直接设置黑幕透明度是0」的收尾）：**把黑幕的原 alpha 还回去**。
--   ★为什么必须有：我们为了抗闪把 `WorldMapBlackout`/`BlackoutWorld` 的 alpha 写成 0（见 featHideBlackout），
--     那是**改了别人的属性** ⇒ 关功能时必须还原（本项目铁律：改属性前先抓原值，用完还回去）。
--   ★**读不到原值**（`FEAT.boA[名] == false`）时**不猜**：如实播报「无法还原、保留现状」，绝不拿当前值冒充原值。
local function featBlackoutRestore()
  if type(FEAT.boA) ~= "table" then return 0 end
  local back = 0
  for _, bn in ipairs({ "BlackoutWorld", "WorldMapBlackout" }) do
    local b = _G[bn]
    local orig = FEAT.boA[bn]
    if (type(b) == "table" or type(b) == "userdata") and type(b.SetAlpha) == "function" then
      if type(orig) == "number" then
        pcall(b.SetAlpha, b, orig)
        back = back + 1
      elseif orig == false then
        P("黑幕 " .. tostring(bn) .. "：当初**读不到原始透明度** ⇒ 不猜、保留现状（可能仍是我设的 0）")
      end
    end
  end
  FEAT.boA = {} -- 释放记账（下次开启重新抓原值）
  return back
end

-- ★★★1.75.9 新增（用户要求：「在开启/关闭大地图缩放要做好探索层纹理的事件清理」）：
--   **关闭时把自己装上去的东西收干净** —— 这是「关掉零动作」最容易漏掉的一半：
--     · 坐标行的 OnUpdate：摘掉 + 清空文本 + Hide（它挂在地图帧下，旧版关掉后照样每 0.1s 算一次）；
--     · 拖拽柄：Hide；
--     · `UISpecialFrames`：**只有我们自己插进去的那一项**才拿掉（`FEAT.escAdded` 记账）；
--     · 滚轮处理器：**不摘链**（摘链会连客户端原生滚轮一起弄丢），而是在处理器开头加 enabled 门（见 featWheelOn）。
--   ★关功能 = 只还回**我们改过的那几样**（黑幕 alpha / 外框缩放 / 透明度 / 装上的钩子）——
  --     整条「探索层适配」已摘除 ⇒ 探索层几何我们一个字节都没碰过，也就没有任何原值要还原。
--   ★1.75.5 追加：**黑幕的原 alpha 也要还回去**（featBlackoutRestore）—— 跟几何原值同一个道理。
local function featTeardown()
  FEAT.torn = true
  -- ★1.75.5：先还黑幕透明度（它是「我们改过的别人的属性」）
  local nAlpha = 0
  local okA, na = pcall(featBlackoutRestore)
  if okA then nAlpha = tonumber(na) or 0 end
  -- ★★★1.75.9 修（用户报障：「这个界面在世界地图拖拽移动功能失效」）：**只 Hide，不摘 OnUpdate**。
  --   旧写法在这里把坐标行的 OnUpdate 摘了，而 `featBuild` 有一次性守卫（`FEAT.built`）⇒ 再开启时既不再建、
  --   也不会 Show ⇒ **拖拽柄/坐标行永久消失**（拖拽移动直接失效）。
  --   ★「关掉零动作」由**处理器开头的 enabled 门**保证（坐标行与滚轮各一道），不需要摘链。
  local c = _G["EH_SM_COORDS"]
  if type(c) == "table" or type(c) == "userdata" then pcall(c.Hide, c) end
  local b = _G["EH_SM_DRAG"]
  if type(b) == "table" or type(b) == "userdata" then pcall(b.Hide, b) end
  if FEAT.escAdded and type(UISpecialFrames) == "table" then
    for i = table.getn(UISpecialFrames), 1, -1 do
      if UISpecialFrames[i] == "WorldMapFrame" then table.remove(UISpecialFrames, i) end
    end
    FEAT.escAdded = false
  end
  FEAT.blackoutUntil, FEAT.blackoutAt, FEAT.blackoutLogged = 0, 0, false -- 瞬时窗口也收掉
  -- ★1.75.52：原来这里还要把「未适配先隐形」的探索层还回可见度 —— 那条（`smFitGhostShow`）随探索层适配整条摘除。
  -- ★★★1.75.6：地图设置面板 + 它的 click-catcher 一起收 —— 关功能 = 零动作，
  --   ★catcher 绝不能留着（它是全屏 Button，留着会吃地图上的所有点击）。
  if type(FEAT.cfgShow) == "function" then pcall(FEAT.cfgShow, false) end
  mfLog("关闭收尾：黑幕透明度还原 %d 层（原 alpha 由 featBlackoutRestore 写回）", nAlpha)
end

-- ★★★1.75.9 新增：**再武装**（关闭时藏起来的件，开启时必须回来）—— 与 featTeardown 成对，缺一半就是上面那个真机 bug。
--   做三件事：拖拽柄 Show、坐标行 Show、ESC 列表那一项按 `FEAT.escAdded` 的记账补回。幂等，随便调。
featRearm = function() -- ★赋值给上面前向声明的 local（不是 local function！）
  FEAT.torn = false
  local b = _G["EH_SM_DRAG"]
  if type(b) == "table" or type(b) == "userdata" then pcall(b.Show, b) end
  local c = _G["EH_SM_COORDS"]
  if type(c) == "table" or type(c) == "userdata" then pcall(c.Show, c) end
  if (not FEAT.escAdded) and type(UISpecialFrames) == "table" then
    local found = false
    for _, n in ipairs(UISpecialFrames) do if n == "WorldMapFrame" then found = true end end
    if not found then
      pcall(table.insert, UISpecialFrames, "WorldMapFrame")
      FEAT.escAdded = true
    end
  end
  return true
end

-- 「打开世界迷雾」渲染节拍（爆发 0.1s / 稳态 0.3s）—— ★1.75.52 起**整条「探索层适配」已按用户要求摘除**
--   （用户：「1.75.45b 换图后探索层缩放失效那块可以不用保留，替代方案已做好」）⇒
--   这三个常量只服务**表驱动全渲染**的「开图 / 换图 / 缩放变化后逐帧重申」，不再有任何抓原值/折算。
local SM_BURST_GAP, SM_BURST_SEC, SM_IDLE_GAP = 0.1, 2.0, 0.3
-- ★★★1.75.54（1.75.53 真机报障「开了十几个地区以后游戏会卡死」）：爆发窗的**重新武装**必须只认
--   **引擎真值**（我们写不进去的东西），并且有**最小间隔**与**帧数上限** ——
--   旧写法看 `es` 抖 0.001 就重置 2s 窗口，而我们每拍都在写几何 ⇒ 窗口永不结束 = 每帧整张图重写。
local SM_BURST_REARM_MIN, SM_BURST_FRAMES = 0.5, 90
-- ★★★1.75.13 新增：**地图身份**（这是本轮修法的地基）。
--   为什么必须：`WorldMapOverlay1..N` 这批纹理是**按序号逐图复用**的 —— 客户端每次 `WorldMapFrame_Update`
--   按当前地图的叠加层列表重新分配它们（本机 S_WorldMap 同源代码：`CreateTexture("WorldMapOverlay"..j)` → 每图重摆），
--   **本图用不到的会被 `:Hide()` 且不清几何**。⇒ 同一个名字在不同地图上代表**完全不同的矩形**，
--   把「原值」按名字记一次就永久沿用（旧 schema）必然把那套矩形盖到别的图上。
local function smMapInfo()
  if type(GetMapInfo) ~= "function" then return nil end
  -- ★本项目铁律：`pcall` 只保留被调函数的**第一个**返回值 ⇒ 想拿多返回必须**包一层函数**
  local ok, a, b, c = pcall(function() return GetMapInfo() end)
  if not ok then return nil end
  return a, b, c
end

-- 地图身份 = 文件名 + 纹理尺寸（尺寸变了版式也会变 ⇒ 同样要重新抓原值）；读不到返回 nil（如实三态，绝不猜）
local function smMapKey()
  local a, b, c = smMapInfo()
  if a == nil and b == nil and c == nil then return nil end
  return string.format("%s:%sx%s", tostring(a), tostring(b), tostring(c))
end

-- 当前地图的叠加层条数（客户端自己的数据）；读不到 = nil（不猜）
local function smNumOverlays()
  if type(GetNumMapOverlays) ~= "function" then return nil end
  local ok, n = pcall(GetNumMapOverlays)
  if not ok or not tonumber(n) then return nil end
  return tonumber(n)
end

-- ★★★1.75.54：**引擎真值签名** —— 只用来判「要不要重新武装爆发窗」。
--   为什么不用 `es`：我们每拍都在写几何（尺寸/锚点），`es` 会跟着抖 0.001 ⇒ 旧写法每次都重置 2s 窗口
--   ⇒ 逐帧重申永不结束 = **每帧整张图重写 + 每帧枚举 region**（地区一多就卡死，真机实报）。
--   这里读的是**客户端自己那批叠加层的条数与首块宽度** —— `GetMapOverlayInfo` 是引擎按当前地图/缩放
--   级别给出的真值，**我们写不进去**（`MDQ.measureK` 的注释里有同一条事实），所以它变 = 真的换图/真缩放。
local function smMeasEngineSig()
  local n = tonumber(smNumOverlays())
  if n == nil then return nil end
  local w = ""
  if n > 0 and type(GetMapOverlayInfo) == "function" then
    local ok, _, cw = pcall(function() return GetMapOverlayInfo(1) end)
    if ok and tonumber(cw) then w = tostring(math.floor(tonumber(cw) + 0.5)) end
  end
  return tostring(n) .. ":" .. w
end
-- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：**详细日志开关**，真值 `SM_CFG.mapFitVerbose`，
--   **nil = 关**（安静档）。安静档只保留「读到了几条 / 折算已对齐 / 关图已清空 / 真出问题」这几行；
--   逐条原值、第 N 次尝试、每次重试提示、窗口开关、每次折算细节 = 本档（`/ehm mapfit verbose on`）。
--   ★默认必须是**关**：这些行是**给排查用的**，功能正常时它们只是刷屏（用户实测：开一次图十几行）。
local function smFitVerboseOn()
  return SM_CFG.mapFitVerbose == true
end
local MF_TRACE_MAX = 60
-- ★★★1.75.45 修（前向声明老雷，同类坑本项目已多次记录）：`mfLog` 的**首次使用在 1727/1739/1863 行**
--   （`featHideBlackout` 与 `featTeardown` 里），而定义原本是这里的 `local function` ⇒ 在那些函数体里
--   `mfLog` 绑的是**全局 nil**，调用即 `attempt to call a nil value`，被外面的 `pcall` 一吞就**静默**：
--   「黑幕遮蔽：开图后 N ms 藏住 M 层」与「关闭收尾：…」这两条**唯一的取证行从来没打出来过**。
--   ⇒ 修法照项目定案：**顶部前向声明 + 定义处改赋值**（不是 `local function`）。
mfLog = function(fmt, ...)
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  local t = (type(GetTime) == "function") and GetTime() or 0
  local line = string.format("%.2f %s", t, msg)
  local ring = SM_CFG.mapFitTrace
  if type(ring) ~= "table" then ring = {} SM_CFG.mapFitTrace = ring end
  table.insert(ring, line)
  while table.getn(ring) > MF_TRACE_MAX do table.remove(ring, 1) end
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[mapfit] " .. msg) end
  return line
end

-- ★★★1.75.5（**用户明确要求**：「获取原值的地方添加日志信息，打印出来」）：
--   抓原值的关键分叉走**常开出口**播报 —— `mfLog` 那条路要过「调试日志」总闸门（`EVAL_LOGLINE` 受它管），
--   关着就一个字都不出声；而真机实测（用户截图：重开后**没重新打开地图**那一次）聊天框里**一条抓原值都没有**，
--   于是「到底抓没抓、卡在哪一步」根本无从判断 —— 这正是这一案反复的地方。
--   ★代价必须认：抓原值这条路径可能 1 秒重试一次 ⇒ **只在「有界」的分叉点调用本函数**（调用点各自带计数门）。
local function smFitSay(fmt, ...)
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  mfLog("[播报] %s", msg)
  local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
  pcall(out, "[简易地图] " .. msg)
  return msg
end

-- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：**详细档**单独门控。
--   安静档（默认）每次开图只留 2 行（「已读到 N 条」+「折算已对齐」）、关图 1 行；
--   逐条原值 / 第 N 次尝试 / 每次重试提示 / 窗口开关 / 每次折算细节 = **verbose 档**（`/ehm mapfit verbose on`）。
--   ★无论如何都进 `mapFitTrace` 取证环（`mfLog` 那一句不省）⇒ 真出问题时仍然读得到全过程。
--   ★★★1.75.45 修：这里原本是 `local function`，而它**首次使用在 1744 行**（黑幕耗时取证行）⇒
--     那处绑全局 nil、被 `pcall(featHideBlackout)` 静默吞掉 ⇒ 那条**上屏**取证行从来没打出来过。
--     修法照项目定案：**顶部前向声明 + 定义处改赋值**（同 `mfLog` / `featRearm`）。
smFitSayV = function(fmt, ...)
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  mfLog("[详细] %s", msg)
  if not smFitVerboseOn() then return msg end
  local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
  pcall(out, "[简易地图] " .. msg)
  return msg
end
-- ===== ★★★「打开世界迷雾」（1.75.51 起叫「S_WorldMap 贴图替代」，1.75.52 改名并合并残留清理）= 表驱动全渲染 =====
-- 用户要求（原话）：「缩放大地图->设置内->添加个 S_WorldMap 贴图替代开关。开启则直接使用 S_WorldMap
--   数据源自动开全图。忽略内置探索纹理。」
--   · **数据源** = 随插件带一份的 `MapOverlayData.lua`（生成物，`node gen_mapoverlay.js`；源 = Turtle 的
--     `!Libs\!MyLib\libs\LibMapOverlayData.lua`，S_WorldMap / MozzFullWorldMap 血统）：
--     `EVAL_MAP_OVERLAY_DATA[地图文件名][区域名] = { 宽, 高, offsetX, offsetY }`，单位 = **地图像素**，
--     原点 = `WorldMapDetailFrame` 左上、y **向下**为正（与 `GetMapOverlayInfo` 同口径）。
--   · **贴图与分块（Mozz 口径，与 `S_WorldMap\Modules\MapOverlay.lua:794-835` 逐行同源）**：
--     贴图 = `Interface\WorldMap\<GetMapInfo() 第1个返回>\<区域名><块号>`；每 256×256 一块
--     （列数 nh = ceil(w/256)、行数 nv = ceil(h/256)，**行优先** t = (j-1)*nh + k），末列/末行取余数（余 0 按 256）；
--     `SetTexCoord(0, 像素/文件边长, 0, 像素/文件边长)`，文件边长 = 16 起按 2 的幂倍增到 ≥ 像素；
--     挂点 = TOPLEFT / WorldMapDetailFrame / TOPLEFT + (ox, -oy)。
--   · **倍率 k = 现读**（用户 1.75.51：「缩放要根据当前缩放级别和数据库实时计算」）——
--     引擎在当前缩放级别下给出的叠加层真值 ÷ 表推值（多样本取中位数；读不出就兜底外框有效缩放、再兜底 1 并如实说判不出）。
--     ★**不留常数**：早期按 DebugBox 的一行读数（`尺寸=68x85 ｜ 原=113x142 ｜ es=0.6`）推断「表值原样写」，
--     那只在「引擎真值 = 表值」时成立；地图一换缩放级别就不成立 —— 现在每拍现读、绝不会停在某个写死的值上。
--     ★写后**读回自证**（本项目纪律：写成功 ≠ 写进去生效）；判不出就如实说，绝不假装成功。
--   · **忽略内置探索纹理**：`WorldMapOverlay1..N` 这批池位本来就是客户端按自己那张旧表摆的 ⇒
--     我们把**每一条都改写成**本表推出来的贴图/UV/尺寸/位置；本图不在表里（大陆图 / 城市图）⇒
--     **把客户端自己的探索层全部 Hide**（替代语义：宁可空着，也不留旧图）。
--   · **层不够就自己补**（用户同一条要求：「渲染的时候如果本身层不够要自行添加完成渲染」）：真机现状是
--     贫瘠之地客户端只摆了 5 个池位、而表里这张图有几十块 ⇒ 缺口由我们现场 `CreateTexture` 补齐
--     （具名失败退回**匿名**纹理，照样能画），并**跨帧复用**（`MDQ.own`）—— 渲染在开图后是**逐帧重申**的，
--     每帧新建会瞬间泄漏几百张纹理。
--   · **全自动**：不新增命令、不新增计时器 —— 挂在开图 tick 的既有节拍上（爆发窗 0.1s / 稳态 0.3s）：
--     开图爆发窗（2s）内逐帧重申，之后 0.3s 一拍；关掉开关即整段让位（`MDQ.release` 把我们补建的层收起来）。
local function smEffScale(f)
  local z, cur, guard = 1, f, 0
  while cur and guard < 8 do
    local oks, s = pcall(cur.GetScale, cur)
    if oks and tonumber(s) and tonumber(s) > 0 then z = z * tonumber(s) end
    local okp, p = pcall(cur.GetParent, cur)
    if not (okp and p) then break end
    cur = p
    guard = guard + 1
  end
  return z
end
-- ============ ★★★1.75.55 探索层折算（客户端自己的探索层跟随地图缩放）============
-- 用户 2026-10-01 报障：「在关闭世界迷雾地图功能之后我们最开始完成的地图探索层缩放功能不生效了。」
--   ⇒ 让探索层跟着地图缩放走的那段（1.75.45c 的 `SMFIT` 折算）在 1.75.52 被整条摘除（当时定的替代方案 = 打开世界迷雾）。
--     现在开关能真停了，关掉之后就只剩客户端自己摆的那批探索层 —— 而它**不跟我们的地图缩放**
--     （这正是 1.75.45b 报过的「缩放大地图 → 换图后探索层缩放失效」）。
--   ⇒ 以**精简形态**把它加回来（口径与 1.75.45c 逐条对齐，删掉了那套诊断档/策略档/隐形/命令），范围收窄到四条：
--     ① **只在「打开世界迷雾」关闭时**跑（开着时那批池位由表驱动全渲染负责，别两套抢同一批几何）；
--     ② **只写几何**（锚点 x/y + 宽/高）—— 绝不 Hide/Show、绝不 SetTexture、绝不动 UV；
--     ③ **只碰** `WorldMapDetailFrame` 下**名字属 `WorldMapOverlay*` 且本图真在用**的非瓦片纹理
--        （底瓦片 `WorldMapDetailTile*` 互相锚 + 偏移 0 ⇒ 对缩放**免疫**，动它反而错）；
--     ④ **写之前先读原值**（顺序铁律）· 原值只在**会话内存**、按地图身份分桶（绝不落存档）·
--        关图 / 关功能 / 切回世界迷雾 ⇒ **当场按原值还回**。
--   ★★★**自然档抓原值**（1.75.45b 的根因就出在这）：地图刚打开时先**不套我们的缩放**（`MDQ.fit.hold` 窗口），
--     等本图在用的层原值抓齐（或窗口 `MDQ.FIT_HOLD_SEC` 到点）再套缩放 + 折算 ⇒ 读到的原值才是**自然档**的。
--     （旧写法在 0.7 档上读原值 ⇒ 记录偏小 ⇒ 判成「已对齐」⇒ 一个几何都不写 = 用户看到的「缩放失效」。）
--   ★**幂等**：当前值 ≈ 原值 × es 就跳过（客户端重排会把我们写的冲掉，下一拍自动补回；es 回 1 时自动还原）。
--   ★**不靠 es 抖动作重新武装**（1.75.54 的教训）：爆发窗只在**开图/换图**这两个真事件上武装。
--   ★全部挂在 `MDQ` 表上（**不新增文件级 local** —— 主 chunk 有 200 local 上限）。
--   ★★1.75.56：迷雾那一族（原来也挂在这张表上）已整体搬去 `tools\WorldFog.lua` ⇒ 这里必须**重新建表**
--     （文件上方那句 `local MDQ` 只是前向声明 = nil；少了这一行，下面第一句 `MDQ.fit = {` 就是
--      `attempt to index a nil value (local 'MDQ')` = **整个插件载不进去**）。
MDQ = {}
MDQ.fit = { rec = {}, recMap = {}, mapKey = nil, wroteKeys = {}, wrote = false, captured = false,
  open = false, needCap = false, hold = 0, holdAge = 0, age = 0, acc = 0, burst = 0, capRan = false,
  esCache = nil, saidFold = false, saidCap = false, wroteN = 0, restoreN = 0, natLeft = 0, capAt = -99 }
MDQ.FIT_HOLD_SEC = 2.0    -- 自然档抓原值窗口上限（秒；到点必收，绝不把地图卡在满尺寸）
MDQ.FIT_SETTLE = 0.4      -- 等客户端把本图版式摆稳再抓（开图那一瞬抓到的可能还是上一张图的几何）
MDQ.FIT_CAP_GAP = 0.5     -- 窗口内抓原值的重试间隔（秒；有界，不每帧重试）
MDQ.FIT_BURST_SEC = 2.0   -- 折算爆发窗（开图/换图后逐帧重申）
MDQ.FIT_BURST_GAP = 0.1
MDQ.FIT_IDLE_GAP = 0.3    -- 稳态巡检节拍

-- 折算的**开关口径**（唯一入口）：模块开着（tick 已保证）+ 地图开着（调用方保证）+ **世界迷雾关着**。
MDQ.fitArmed = function()
  return not EVAL_WF_ON()
end

-- ★★★本图**真在用**的层（只读；**读不到一律放行** —— 判不出就不拦，绝不把功能判死）：
--   · `IsShown() == false` ⇒ 客户端本图不用它（上面留着别的图的几何，写它就是制造错位）；
--   · `GetTexture()` 读得到且为空 ⇒ 这一轮根本没往它上面贴图（同上）。
MDQ.fitInUse = function(o)
  if type(o.IsShown) == "function" then
    local ok, v = pcall(o.IsShown, o)
    if ok and v == false then return false end
  end
  if type(o.GetTexture) == "function" then
    local ok, v = pcall(o.GetTexture, o)
    if ok and (v == nil or v == "") then return false end
  end
  return true
end

-- 目标 = `WorldMapDetailFrame` 下**名字属 `WorldMapOverlay*` 的非瓦片纹理**，键 = **纹理名**（稳定身份）
--   ★为什么要枚举 region：本客户端那批原生探索层**不在 `_G` 里**（按名字查不到 —— 1.75.51 实测），
--     只有枚举拿得到；这里**只写几何**，绝不 Hide/Show、绝不改贴图/UV（弄乱地图的那两版是「全当叠加层改写 + 收尾 Hide」）。
MDQ.fitTargets = function()
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then return {} end
  local ok, regs = pcall(function() return { fr:GetRegions() } end)
  if not ok then return {} end
  local list, idx = {}, 0
  for _, o in ipairs(regs) do
    if o ~= nil and type(o.GetWidth) == "function" and type(o.SetPoint) == "function" then
      local isTex = true
      if type(o.GetObjectType) == "function" then
        local okt, tp = pcall(o.GetObjectType, o)
        isTex = (okt and tostring(tp) == "Texture")
      end
      if isTex then
        idx = idx + 1
        local nm = frameName(o)
        if type(nm) == "string" and string.find(string.lower(nm), "worldmapoverlay", 1, true) == 1 then
          table.insert(list, { o = o, key = nm })
        end
      end
    end
  end
  return list
end

-- 本图记录条数（播报/取证用）
MDQ.fitRecCount = function()
  local n = 0
  for _, v in pairs(MDQ.fit.rec or {}) do if type(v) == "table" then n = n + 1 end end
  return n
end

-- ★★★1.75.13 的地基：**同一个纹理名在不同地图上是完全不同的矩形**（客户端按当前图的叠加层列表逐图复用这批名字）
--   ⇒ 原值必须**按地图身份分桶**（`recMap[mk]`），换图即换绑；绝不跨图复用一份记录。
MDQ.fitBindMap = function(mk)
  if type(mk) ~= "string" or mk == "" then return end
  local f = MDQ.fit
  if f.mapKey == mk then return end
  if type(f.mapKey) == "string" then
    f.recMap[f.mapKey] = f.rec
  else
    -- ★还没有身份（第一拍）⇒ **把手里已有的记录归到这个身份下**，绝不新建空表把刚抓的原值丢掉
    f.recMap[mk] = f.rec
  end
  f.mapKey = mk
  f.rec = f.recMap[mk] or {}
  f.recMap[mk] = f.rec
  -- 换图 ⇒ 写入账与「已抓齐」标记作废（新图要用自己的原值重抓）
  f.wroteKeys, f.wrote, f.captured, f.capRan = {}, false, false, false
  f.saidFold, f.saidCap = false, false
  f.burst, f.acc = MDQ.FIT_BURST_SEC, 0
end

-- 记录里的相对帧**解析成活对象**（★1.75.5 真机定案：写锚点必须传对象，传字符串/nil 会被锚到屏幕
--   ⇒ 纹理跑到游戏画面上；兜底 = 父帧本身，因为原值记的就是「锚父帧 TOPLEFT」）。
MDQ.fitRelObj = function(r)
  local rel = r and r.relObj
  if type(rel) == "table" or type(rel) == "userdata" then return rel end
  if r ~= nil and type(r.rel) == "string" and r.rel ~= "" then
    local o = rawget(_G, r.rel)
    if type(o) == "table" or type(o) == "userdata" then return o end
  end
  return _G["WorldMapDetailFrame"]
end

-- 「这一层与 原值×es 是否已经对齐」的**唯一判据**（返回 true = 要写 / false = 已对齐 / **nil = 几何读不到 ⇒ 判不出就不动**）
--   ★两种读回口径都认（与 1.75.45c 逐字同口径）：okA = 读回≈逻辑值；okB = 读回≈逻辑值×es
--     —— 只认第一种的话，在会级联的客户端上每一拍都判「要改」⇒ 反复重写 + 刷屏。
MDQ.fitNeedWrite = function(o, r, es)
  local okp, p, _rel, _rp, x, y = pcall(o.GetPoint, o, 1)
  local okw, w = pcall(o.GetWidth, o)
  local okh, h = pcall(o.GetHeight, o)
  if not (okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h)) then
    return nil
  end
  local wx, wy, ww, wh = r.x * es, r.y * es, r.w * es, r.h * es
  local near = function(a, b) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= 0.5 end
  local okA = near(x, wx) and near(y, wy) and near(w, ww) and near(h, wh)
  local okB = near(x, wx * es) and near(y, wy * es) and near(w, ww * es) and near(h, wh * es)
  if okA or okB then return false, wx, wy, ww, wh end
  return true, wx, wy, ww, wh
end

-- 抓原值（**只读**；顺序铁律：读原值 → 写新值）。返回 本次抓到 N 条, 还缺 M 条（在用的层里没原值的个数）。
--   ★★★**只在自然档窗口里抓**（`f.needCap == true`，此时外框已被主动按回 1.00）：不在窗口里读 = 读到的是
--     **折后值**（记录偏小 ⇒ 那一层永远折不动）—— 这正是 1.75.45b 报的「换图后探索层缩放失效」的真凶，
--     1.75.24 的原话也是「后来出现的层同样必须在自然档读」。
MDQ.fitCapture = function(quiet)
  local f = MDQ.fit
  if not f.needCap then return 0, 0 end
  -- ★先按当前地图身份换绑（原值**按图分桶**）—— 抓原值与折算必须落在同一张图的账上
  MDQ.fitBindMap(smMapKey())
  local list = MDQ.fitTargets()
  if table.getn(list) == 0 then return 0, 0 end
  -- 客户端本图自报 **0 条叠加层** ⇒ 一个几何都不该碰（旧写法照样把那批残留几何写一遍）
  local nOv = smNumOverlays()
  if nOv ~= nil and tonumber(nOv) == 0 then return 0, 0 end
  local got, missing = 0, 0
  for _, it in ipairs(list) do
    local o, key = it.o, it.key
    if f.rec[key] == nil and MDQ.fitInUse(o) then
      local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
      local okw, w = pcall(o.GetWidth, o)
      local okh, h = pcall(o.GetHeight, o)
      if okp and okw and okh and p ~= nil and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
        f.rec[key] = { o = o, p = p, relObj = rel, rel = frameName(rel), rp = rp,
          x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
        got = got + 1
      end
    end
  end
  for _, it in ipairs(list) do
    if MDQ.fitInUse(it.o) and f.rec[it.key] == nil then missing = missing + 1 end
  end
  if missing == 0 and MDQ.fitRecCount() > 0 then f.captured = true end
  return got, missing
end

-- 只读：**还缺几条原值**（本图在用的层里没有记录的数量）—— 供「有界补抓」决定要不要再回自然档。
--   ★绝不在这里记原值（那会读到折后值）：记录只能由 `MDQ.fitCapture` 在**自然档窗口里**做。
MDQ.fitMissing = function()
  local f = MDQ.fit
  local n = 0
  for _, it in ipairs(MDQ.fitTargets()) do
    if MDQ.fitInUse(it.o) and f.rec[it.key] == nil then n = n + 1 end
  end
  return n
end

-- 折算（把在用的层写成 原值 × es）。返回 本拍真写了几层, 已对齐几层。
MDQ.fitApply = function(es)
  local f = MDQ.fit
  if not MDQ.fitArmed() then return 0, 0 end
  if f.needCap then return 0, 0 end          -- 原值窗口还没收口 ⇒ 这一拍先不折（保持自然档）
  es = tonumber(es) or 1
  if es <= 0 then es = 1 end
  local nOv = smNumOverlays()
  if nOv ~= nil and tonumber(nOv) == 0 then return 0, 0 end
  local mk = smMapKey()
  MDQ.fitBindMap(mk)
  local changed, ready = 0, 0
  for _, it in ipairs(MDQ.fitTargets()) do
    local o, key = it.o, it.key
    local r = f.rec[key]
    if type(r) == "table" and r.o == o and MDQ.fitInUse(o) then
      local need, wx, wy, ww, wh = MDQ.fitNeedWrite(o, r, es)
      if need == true then
        local relObj = MDQ.fitRelObj(r)
        if relObj ~= nil then
          pcall(o.ClearAllPoints, o)
          pcall(o.SetPoint, o, r.p, relObj, r.rp, wx, wy)
          pcall(o.SetWidth, o, ww)
          pcall(o.SetHeight, o, wh)
          r.relObj = relObj
          f.wrote, f.wroteKeys[key] = true, mk
          changed = changed + 1
        end
      elseif need == false then
        ready = ready + 1
      end
    end
  end
  f.wroteN = changed
  if changed > 0 and not f.saidFold then
    f.saidFold = true
    pcall(smFitSay, "探索层折算：地图=%s ｜ 按外框缩放 es=%.3f 折算 **%d** 个探索层（只写锚点/宽高；"
      .. "关图 / 关功能 / 切回「打开世界迷雾」都按原值还回）", tostring(mk or "?"), es, changed)
  end
  return changed, ready
end

-- 按原值还回（**只还我们写过的**；幂等）。返回 还回 N 个, 没还回去的 M 个。
MDQ.fitRestore = function(why)
  local f = MDQ.fit
  local n, miss = 0, 0
  local live = {}
  for _, it in ipairs(MDQ.fitTargets()) do live[it.key] = it.o end
  local function back(key, o)
    local r = f.rec[key]
    if type(r) ~= "table" then miss = miss + 1 return end
    local relObj = MDQ.fitRelObj(r)
    if relObj == nil or o == nil then miss = miss + 1 return end
    pcall(o.ClearAllPoints, o)
    pcall(o.SetPoint, o, r.p, relObj, r.rp, r.x, r.y)
    pcall(o.SetWidth, o, r.w)
    pcall(o.SetHeight, o, r.h)
    n = n + 1
  end
  for key in pairs(f.wroteKeys) do
    local o = live[key]
    if o ~= nil and f.rec[key] ~= nil and f.rec[key].o == o then back(key, o)
    elseif f.rec[key] ~= nil and f.rec[key].o ~= nil then back(key, f.rec[key].o)   -- 关图那一刻枚举不到 ⇒ 用记录里的对象
    else miss = miss + 1 end
  end
  f.wroteKeys, f.wrote, f.restoreN = {}, false, n
  if n > 0 or miss > 0 then
    pcall(mfLog, "探索层折算还回（%s）：地图=%s ｜ 按原值还回 %d 个%s", tostring(why), tostring(f.mapKey or "?"), n,
      (miss > 0) and ("；" .. tostring(miss) .. " 个没有原值/锚点解析失败 ⇒ 如实跳过（没动它们）") or "")
  end
  return n, miss
end

-- 开图/换图那一拍：重开自然档抓原值窗口 + 武装折算爆发窗
--   ★★★窗口期**必须主动把外框按回自然档**（`featApplyScale(1)`）—— 只「挡住缩放」是不够的：
--     外框的 0.7 是**跟着上一张图留下来的**（客户端不会替我们复位）⇒ 不归位就会在 0.7 上读原值
--     ⇒ 记录偏小 ⇒ 折算变空操作（正是 1.75.45b 报的「换图后探索层缩放失效」）。
--   ★**没缓存才走初次流程**（1.75.45c）：本图已经有原值记录（本会话访问过、没关过图）⇒ **不开窗口**，
--     直接用缓存折算（不再有「每次开图先满尺寸 1~2 秒」）。关图会把记录丢掉 ⇒ 下次开图必然重抓（用户 1.75.5 定的口径）。
MDQ.fitOpen = function()
  local f = MDQ.fit
  f.open, f.age, f.holdAge = true, 0, 0
  f.needCap = (next(f.rec or {}) == nil)
  f.hold = f.needCap and MDQ.FIT_HOLD_SEC or 0
  f.natLeft = 3          -- ★补抓窗口预算（每图最多 3 段，绝不把地图长期按在自然档）
  f.capAt = -99
  f.capRan, f.captured, f.esCache = false, false, nil
  f.burst, f.acc = MDQ.FIT_BURST_SEC, 0
  f.saidFold, f.saidCap = false, false
end

-- 关图 / 关功能 / 切回世界迷雾：**当场按原值还回**，并把本图记录丢掉（「每次开图重新抓」的口径）
--   ★安全阀（1.75.45c 的原话）：**还回没验成功就绝不丢记录** —— 丢了就等于允许下次把「折后值」当原值记下来（折两遍）。
MDQ.fitClose = function(why)
  local f = MDQ.fit
  if not f.open and not f.wrote then return 0 end
  f.open, f.needCap, f.hold, f.holdAge, f.age, f.capRan = false, false, 0, 0, 0, false
  local n, miss = 0, 0
  if f.wrote then n, miss = MDQ.fitRestore(why or "已收手") end
  if miss == 0 then
    local mk = f.mapKey
    f.rec = {}
    if type(mk) == "string" then f.recMap[mk] = f.rec end
    f.captured, f.saidFold, f.saidCap = false, false, false
  else
    pcall(smFitSay, "探索层折算：%s ｜ **%d** 个层的原值没还回去（几何读回对不上）⇒ **保留原值记录、不清空**"
      .. "（清掉的话下次开图会把折后值当原值 ⇒ 折两遍）", tostring(why or "已收手"), miss)
  end
  return n
end

-- 折算节拍（挂在既有开图 tick 上；`es` = 外框有效缩放，`dt` = 本帧步长，`mk` = 当前地图签名）
MDQ.fitTick = function(es, dt, mk)
  local f = MDQ.fit
  -- ① 关着（切回世界迷雾）⇒ 还回并收手（**零动作**：之后每拍只判一个布尔）
  if not MDQ.fitArmed() then
    if f.open or f.wrote then pcall(MDQ.fitClose, "切回打开世界迷雾") end
    return 0
  end
  dt = tonumber(dt) or 0.05
  if type(mk) == "string" and mk ~= "" and mk ~= f.mapKey then
    -- ★换图：**不写任何几何** —— 换图那一刻客户端自己会把这批纹理按新图重摆（几何归它），
    --   我们若把上一张图的原值写回去 = 拿旧矩形盖新图（1.75.45c 的老坑）；这里只换绑 + 按新图重抓原值。
    MDQ.fitBindMap(mk)
    MDQ.fitOpen()
  elseif not f.open then
    MDQ.fitOpen()
  end
  -- ② 自然档抓原值窗口：等版式稳定再抓；抓齐 / 到点都收窗口（★绝不把地图卡在满尺寸）
  if f.needCap then
    f.age = (tonumber(f.age) or 0) + dt
    f.hold = math.max(0, (tonumber(f.hold) or 0) - dt)
    f.holdAge = (tonumber(f.holdAge) or 0) + dt
    -- ★窗口期**逐帧重申自然档**（本该是空操作：`featApplyScale` 自带「同档不重写」读回自证 ⇒ 不加写动作）
    pcall(featApplyScale, 1)
    if f.age >= MDQ.FIT_SETTLE and (not f.capRan or f.holdAge >= MDQ.FIT_CAP_GAP) then
      f.capRan, f.holdAge = true, 0
      local got, missing = MDQ.fitCapture()
      if missing == 0 and MDQ.fitRecCount() > 0 then
        f.needCap, f.hold = false, 0
        if not f.saidCap then
          f.saidCap = true
          pcall(smFitSay, "探索层折算：地图=%s ｜ 原值已抓齐 **%d** 层（自然档读的；抓了 %d 条）⇒ 套缩放并折算",
            tostring(mk or "?"), MDQ.fitRecCount(), tonumber(got) or 0)
        end
      end
    end
    if f.hold <= 0 then
      f.needCap = false
      -- ★窗口收口**同一拍**就把缩放套上、并**当拍折算**（不顶满 acc 的话要等下一个节拍，
      --   那 0.1~0.3s 里地图已缩小、探索层还是原尺寸 = 一眼可见的错位 —— 1.75.45b 的原话）
      pcall(featApplyScale, tonumber(SM_CFG.scale) or 1)
      f.acc = 1e9
      f.capAt = (type(GetTime) == "function") and GetTime() or 0
      if not f.saidCap then
        f.saidCap = true
        pcall(smFitSay, "探索层折算：地图=%s ｜ 抓原值窗口到点收口（原值 %d 层）⇒ 套缩放 + 折算"
          .. "（没抓到的层**一个几何都不碰**）", tostring(mk or "?"), MDQ.fitRecCount())
      end
    end
  end
  -- ②-b 窗口关了之后：**后来才冒出来的层**走有界补抓 —— ★1.75.24 的教训：后来出现的层同样必须在**自然档**读，
  --   否则记录偏小 ⇒ 那一层永远折不动；预算 `f.natLeft` 用完就收手（绝不把地图长期按在自然档）。
  --   ★这里**只判定「还缺几条」，绝不记原值**（不在窗口里读到的都是折后值）—— 记录一律留给窗口里的 `fitCapture`。
  if (not f.needCap) and (tonumber(f.natLeft) or 0) > 0 then
    local tNow = (type(GetTime) == "function") and GetTime() or 0
    if (tNow - (tonumber(f.capAt) or -99)) >= MDQ.FIT_CAP_GAP then
      f.capAt = tNow
      local missing = MDQ.fitMissing()
      if (tonumber(missing) or 0) > 0 then
        f.natLeft = f.natLeft - 1
        f.needCap, f.hold, f.holdAge, f.age = true, MDQ.FIT_HOLD_SEC, 0, MDQ.FIT_SETTLE
        pcall(featApplyScale, 1)
        pcall(mfLog, "[fit] 补抓窗口：地图=%s ｜ 还有 %d 个在用的探索层没原值 ⇒ 回到自然档再等 %.1fs"
          .. "（本图预算还剩 %d 段）", tostring(mk or "?"), tonumber(missing) or 0, MDQ.FIT_HOLD_SEC, f.natLeft)
      end
    end
  end
  -- ③ 折算节拍：爆发窗内（开图/换图后 2s）逐帧重申，之后 0.3s 一拍；内容已对齐就一个写都不发
  if (not f.needCap) and es and tonumber(es) and tonumber(es) > 0 then
    f.burst = math.max(0, (tonumber(f.burst) or 0) - dt)
    local gap = ((tonumber(f.burst) or 0) > 0) and MDQ.FIT_BURST_GAP or MDQ.FIT_IDLE_GAP
    f.acc = (tonumber(f.acc) or 0) + dt
    if f.acc >= gap then
      f.acc = 0
      pcall(MDQ.fitApply, tonumber(es))
    end
  end
  return 0
end

-- 开图侦测 tick（★挂 WorldFrame 不挂 UIParent —— 开全屏地图时 UIParent 会被隐藏，挂它下面收不到 OnUpdate）
--   ★★1.75.52（用户定：整条「探索层适配」摘除）后只剩三件事：
--     ① 黑幕瞬时窗口（开图逐帧重申藏黑幕）｜ ② 「开图保持」（透明度/缩放/居中/位置记忆）
--     ③ 「打开世界迷雾」渲染节拍 + 「残留图层清理」节拍（规则与实现都在 `MDQ.*` 里，这里只管节拍与播报）。
--   ★1.75.55 起再加一件：**探索层折算节拍**（`MDQ.fitTick`；只在「打开世界迷雾」关着时干活）。
do
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  if type(CreateFrame) == "function" and parent then
    local f = CreateFrame("Frame", "EH_SM_FEAT", parent)
    local acc = 0        -- 「开图保持」节拍（0.2s，行为不变）
    local accSwm = 0     -- 「打开世界迷雾」渲染节拍（爆发 0.1s / 稳态 0.3s）
    local esCache = nil
    -- 会话级状态（原来寄在 `SMFIT` 表里；探索层适配整条摘掉后收进这一张小表，主 chunk 的 local 预算反而更宽）
    local ST = { open = false, burst = 0, mapKey = nil, pendingApply = false,
      staleUntil = 0, staleAt = -99, staleHidN = 0, staleBackN = 0, staleSaid = false, staleSaidNoPool = false }
    f:SetScript("OnUpdate", function()
      -- ★1.75.7（用户：「未开启缩放大地图时，会不会还在监听探索层的缩放操作」）⇒ **关掉零动作**：
      --   连 IsShown / GetEffectiveScale 都不读，并把「世界迷雾」自建的层收掉、把藏过的层（残留 + 接管守护）全部还回。
      if not EVAL_SM_ENABLED() then
        FEAT.applied = false
        ST.open, ST.burst = false, 0
        -- ★★★1.75.54e：关掉整个模块 = 与关「世界迷雾」**同一套还原**（收自建层 + 复用池位还原原值 +
        --   藏过的原生层全部还回）。走 `MDQ.shutdown`（幂等、只做一次）⇒ 不再每帧重复还回（原来三连 pcall）。
        pcall(EVAL_WF_SHUTDOWN, "模块已关")
        -- ★1.75.55：探索层折算也一起收手（按原值还回几何）
        pcall(MDQ.fitClose, "模块已关")
        return
      end
      local dt = tonumber(arg1) or 0.05
      acc = acc + dt
      accSwm = accSwm + dt
      local open = featOpenNow()
      -- ① 黑幕瞬时窗口：开图那一拍起 `SM_BLACKOUT_SEC` 内**逐帧**重申（客户端每次开图都自己 Show 它、且在我们之后）
      do
        local nowT = (type(GetTime) == "function") and GetTime() or 0
        if open and not ST.open then
          FEAT.blackoutUntil, FEAT.blackoutAt, FEAT.blackoutLogged = nowT + SM_BLACKOUT_SEC, nowT, false
          pcall(featHideBlackout)
        elseif open and (tonumber(FEAT.blackoutUntil) or 0) > nowT then
          pcall(featHideBlackout)
        elseif not open then
          -- ★用户明确要求：关图**只失效窗口**，绝不还原黑幕 alpha（它保持 0 ⇒ 下次开图也不闪）
          FEAT.blackoutUntil, FEAT.blackoutAt, FEAT.blackoutLogged = 0, 0, false
        end
      end
      -- ② 地图身份（换图 = 客户端把这批纹理重摆/重指 ⇒ 世界迷雾**当拍重画**、残留清理重开窗口）
      local mkNow = smMapKey()
      if mkNow and mkNow ~= ST.mapKey then
        ST.mapKey = mkNow
        if open then
          ST.burst = SM_BURST_SEC
          accSwm = 1e9
          ST.staleUntil = ((type(GetTime) == "function") and GetTime() or 0) + EVAL_WF_STALE_SEC()
          ST.staleAt, ST.staleSaid, ST.staleSaidNoPool = -99, false, false
          ST.staleHidN, ST.staleBackN = 0, 0
        end
      end
      -- ③ 残留图层清理节拍：**只 `Hide`/`Show`**，绝不 SetTexture / 绝不动 UV / 绝不改几何（全在 `MDQ.staleTick`）
      do
        -- ★1.75.56：藏账在迷雾模块里（`tools\WorldFog.lua`）⇒ 这里只问一句「账里有没有东西」
        local hasLedger = EVAL_WF_HAS_LEDGER()
        if (not EVAL_WF_STALE_ON()) and hasLedger then
          pcall(EVAL_WF_STALE_SHOWALL, "残留图层清理已关")
          hasLedger = false
        end
        if open and mkNow and EVAL_WF_STALE_ON() then
          local tS = (type(GetTime) == "function") and GetTime() or 0
          local armed = (tonumber(ST.staleUntil) or 0) > tS
          local gapS = armed and EVAL_WF_STALE_GAP() or EVAL_WF_STALE_GAP_IDLE()
          if (armed or hasLedger) and ((tS - (tonumber(ST.staleAt) or -99)) >= gapS) then
            ST.staleAt = tS
            local hidS, backS, seenS, fileS, nLed, lvlWhyS = EVAL_WF_STALE_TICK()
            hidS, backS = tonumber(hidS) or 0, tonumber(backS) or 0
            ST.staleHidN = (tonumber(ST.staleHidN) or 0) + hidS
            ST.staleBackN = (tonumber(ST.staleBackN) or 0) + backS
            if hidS > 0 or backS > 0 then
              pcall(mfLog, "残留图层：地图=%s（%s）｜ 本拍藏 %d 个叠加层 ｜ 还回 %d 个 ｜ 看过池位 %d 个 ｜ 藏账还留 %d 条",
                tostring(fileS), tostring(lvlWhyS or "?"), hidS, backS, tonumber(seenS) or 0, tonumber(nLed) or 0)
            end
            -- ★一个池位都没认出 ⇒ 每图出声一次（「判据与真机对不上」若静默，用户会以为修好了而残留照旧）；
            --   ★「让位」那一拍不许出声（那时 `staleTick` 根本没干活，`seenS == 0` 是让位不是「名字对不上」）。
            local stood = string.find(tostring(lvlWhyS or ""), "接管守护", 1, true) ~= nil
            if (not ST.staleSaidNoPool) and (not stood) and (tonumber(seenS) or 0) == 0 and hidS == 0 then
              ST.staleSaidNoPool = true
              smFitSay("残留图层清理：地图=%s（%s）**没认出任何 WorldMapOverlay 池位** ⇒ 这一档什么都没藏"
                .. "（图上若仍有残留，请敲 `/ehm mapfit 残留` 把首行发我 —— 那行有真机上的纹理名）",
                tostring(fileS), tostring(lvlWhyS or "?"))
            end
            if (not ST.staleSaid) and (tonumber(ST.staleHidN) or 0) > 0 then
              ST.staleSaid = true
              smFitSay("残留图层清理：地图=%s（%s）｜ 已藏 **%d** 个叠加层：%s"
                .. "（**本图没有探索层数据** ⇒ 全藏、只 Hide 不改几何；**切到有数据的区域图会全部还回**；全量见 /ehm mapfit 残留）%s",
                tostring(fileS), tostring(lvlWhyS or "?"), tonumber(ST.staleHidN) or 0, EVAL_WF_STALE_NAMES(8),
                ((tonumber(ST.staleBackN) or 0) > 0) and ("；期间已还回 " .. tostring(ST.staleBackN) .. " 个") or "")
            end
          end
        end
      end
      -- ④ 关图 ⇒ 把藏过的层**全部还回**（残留清理 + 接管守护；绝不把「藏」的状态带进下一张图）
      --   ★1.75.55：探索层折算也在这里收手（按原值还回几何 + 丢掉本图原值 ⇒ 下次开图重新抓）
      local closedNow = (not open) and ST.open
      if closedNow then
        pcall(EVAL_WF_STALE_SHOWALL, "地图已关")
        pcall(EVAL_WF_HOLD_SHOWALL, "地图已关")
        pcall(MDQ.fitClose, "地图已关")
      end
      -- ⑤ 每帧守住地图缩放（读一次 GetScale 很便宜、`featApplyScale` 自带「同档不重写」⇒ 只有漂了才写）
      if open then pcall(featApplyScale, tonumber(SM_CFG.scale) or 1) end
      local fr = _G["WorldMapDetailFrame"]
      local es = nil
      if (type(fr) == "table" or type(fr) == "userdata") then
        -- ★1.75.9：**不读 `GetEffectiveScale`**（本客户端它滞后）⇒ 沿父链连乘，读的是我们自己刚写进去的值
        local eff = smEffScale(fr)
        if tonumber(eff) and tonumber(eff) > 0 then es = tonumber(eff) end
        if not es and type(fr.GetEffectiveScale) == "function" then
          local ok, v = pcall(fr.GetEffectiveScale, fr)
          if ok and tonumber(v) then es = tonumber(v) end
        end
      end
      local justOpened = (open and not ST.open)
      if justOpened then ST.pendingApply = true end
      if justOpened then
        ST.burst = SM_BURST_SEC
        ST.burstN, ST.rearmAt = 0, (type(GetTime) == "function") and GetTime() or 0
        accSwm = 1e9
        ST.staleUntil = ((type(GetTime) == "function") and GetTime() or 0) + EVAL_WF_STALE_SEC()
        ST.staleAt, ST.staleSaid, ST.staleSaidNoPool = -99, false, false
        ST.staleHidN, ST.staleBackN = 0, 0
      end
      -- ★★★1.75.54：**爆发窗的重新武装只认「引擎真值」**（`smMeasEngineSig`：客户端自己那批叠加层的
      --   条数 + 首块宽度 —— 我们写不进去），并且 ① 有**最小间隔** `SM_BURST_REARM_MIN` ② 有**帧数上限**
      --   `SM_BURST_FRAMES` ③ 慢拍被安全阀降档后**不再逐帧重申**。
      --   旧写法（`es` 抖 0.001 就重置 2s）在「我们每拍都写几何」的前提下 = 窗口永不结束 = 每帧整张图重写，
      --   地区越多越致命（1.75.53 真机报障「开了十几个地区以后游戏会卡死」的根因）。
      local ev = smMeasEngineSig()
      if ev ~= nil and ST.engSig ~= nil and ev ~= ST.engSig then
        local nowT = (type(GetTime) == "function") and GetTime() or 0
        if (nowT - (tonumber(ST.rearmAt) or -99)) >= SM_BURST_REARM_MIN then
          ST.rearmAt, ST.burstN = nowT, 0
          ST.burst, accSwm = SM_BURST_SEC, 1e9
        end
      end
      if ev ~= nil then ST.engSig = ev end
      if (tonumber(ST.burst) or 0) > 0 then
        ST.burstN = (tonumber(ST.burstN) or 0) + 1
        if ST.burstN > SM_BURST_FRAMES then ST.burst = 0 end   -- ★帧数上限：绝不无限逐帧重申
      end
      if not open then ST.burst, ST.burstN = 0, 0 end
      ST.open, ST.es = open, (es or ST.es)
      esCache = es or esCache
      if (tonumber(ST.burst) or 0) > 0 then ST.burst = math.max(0, ST.burst - dt) end
      -- ⑥ 「开图保持」节拍（0.2s）：开图那一刻**无条件幂等应用一次**（否则开了功能但地图是关的时候，那一位已是 true ⇒ 开图反而不应用）
      if acc >= 0.2 then
        acc = 0
        if open then
          if ST.pendingApply or not FEAT.applied then
            featApply()
            FEAT.applied = true
            ST.pendingApply = false
          end
          featKeep() -- 开图期间持续保持（黑幕重藏 + 透明度/缩放漂移校准 + 居中窗口 + 位置记忆）
        elseif FEAT.applied then
          FEAT.applied = false
        end
      end
      -- ⑦ 「打开世界迷雾」渲染节拍：爆发窗（开图/换图/**引擎真值变化**后 2s，且 ≤ `SM_BURST_FRAMES` 帧）
      --   内逐帧重申，之后 0.3s 一拍。★1.75.54 分两档：
      --     · **节流那一拍** = 渲染 + 护守（数量/存在性）+ 写后自证 + 播报（`withGuard = true`）
      --     · **逐帧重申那一拍** = **只渲染**（`withGuard = false`）—— 每帧 `GetRegions()` + 逐 region
      --       `GetName()` 是卡顿主因之一；护守按 0.1s/0.3s 拍子查足够（客户端把原生层 Show 回来，
      --       最迟 0.3s 就会被再藏一次）。
      -- ⑦-b ★★★1.75.55 探索层折算节拍（**只在「打开世界迷雾」关着时干活**；规则与状态全在 `MDQ.fit*` 里）：
      --   自然档抓原值窗口 → 折算（原值 × es）→ 关图/关功能/切回世界迷雾时按原值还回。
      if open then pcall(MDQ.fitTick, es, dt, mkNow) end
      if not (open and es and es > 0) then return end
      local gap = ((tonumber(ST.burst) or 0) > 0) and SM_BURST_GAP or SM_IDLE_GAP
      if accSwm >= gap then
        accSwm = 0
        pcall(EVAL_WF_RENDER, es, false, false, true)   -- 带护守的那一拍
      end
      if (tonumber(ST.burst) or 0) > 0 and not EVAL_WF_PERF_GUARD() then
        pcall(EVAL_WF_RENDER, es, true, true, false)    -- 逐帧重申：silent + 不跑护守
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
  -- ★1.75.10：复位 = 居中 ⇒ 同样开窗口期（客户端可能在我们之后又摆一次位置，那这次复位就白做了）
  FEAT.posArmed = false
  FEAT.recenter = SM_RECENTER_TICKS
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
    -- ★1.75.52：原来这里先做「只读探测 + 抓原值准备」（`smFitPrepare`），顺序铁律是「先读原值、再写新值」——
    --   整条探索层适配摘除后**不再需要**：我们只改外框缩放/透明度，客户端的探索层一个字节都不碰。
    -- ★★★1.74.36-3：**开启即套默认档**（缩放 0.7 / 透明度 0.7 / GUI重开 不启用）——用户原话
    --   「开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」；先套默认值，再应用/就位。
    local a, s = smApplyDefaults()
    pcall(featKeep)   -- 事件帧就位（开图时自动应用）
    pcall(featApply)  -- 立刻应用一次
    -- ★★★1.75.7：**应用过就要记下来**（FEAT.applied）——关闭路径拿它判「到底动没动过地图纹理」。
    FEAT.applied = true

    P(string.format("简易地图：已启用（默认档：缩放 %.2f / 透明度 %.2f / GUI重开 %s；面板或 Shift/Ctrl+滚轮可再调）%s",
      s, a, smReopenOn() and "开" or "关",
      featOpenNow() and "；当前地图=开 ⇒ 已立刻生效" or "；当前地图=关 ⇒ **开图即生效**（默认档已写入配置）"))
    -- ★1.75.52：这条原来是「抓原值状态」（记录几条 / 落闩没有 / 地图开没开）—— 那一族已摘除，
    --   现在开图要做的事只有一件：**按 S_WorldMap 表把本图整张画出来**（「打开世界迷雾」）。
    P("　打开世界迷雾 = " .. (EVAL_WF_ON() and "**开**（开图即按 S_WorldMap 表整张渲染；表里没有这张图 ⇒ 一个字节都不碰）"
      or "关（不碰叠加层，客户端原生行为）"))
  else
    -- ★★★1.75.7 关闭 = 把**我们改过的**东西还回去（用户要求：「未开启地图缩放功能不需要进行任务纹理的操作」）。
    --   ★★判据 = **确实动过**才写：FEAT.applied（我们应用过）。
    --     从未开启过 ⇒ **一个地图纹理都不碰**（连透明/缩放都不写 1 —— 它们本来就没被我们改过）。
    --   顺序：收掉「世界迷雾」自建的层 + 把藏过的原生层全部还回 → 再复位透明度/缩放/位置 → 最后如实播报。
    local touched230 = (FEAT.applied == true)
    mfLog("开关 OFF：动过=%s（applied=%s）", tostring(touched230), tostring(FEAT.applied == true))
    if not touched230 then
      FEAT.applied = false
      P("简易地图：已停用（**本就没启用过 ⇒ 没动过任何地图纹理**；透明度/缩放保持原样）")
    else
      -- ★1.75.52：世界迷雾那两族的还原（我们自建的层收掉 + 藏过的原生层 Show 还回）
      local okR, nRestore230 = pcall(EVAL_WF_RELEASE, "关闭缩放大地图")
      if not okR then nRestore230 = 0 end
      pcall(EVAL_WF_STALE_SHOWALL, "关闭缩放大地图")
      pcall(EVAL_WF_HOLD_SHOWALL, "关闭缩放大地图")
      pcall(MDQ.fitClose, "关闭缩放大地图")   -- ★1.75.55：探索层折算也按原值还回
      FEAT.applied = false
      pcall(featReset)  -- 透明/缩放/位置复位
      -- ★★★1.75.9：**把装上去的钩子/帧收干净**（用户要求：「开启/关闭要做好探索层纹理的事件清理」）。
      pcall(featTeardown)
      P("简易地图：已停用（已复位：透明度 1 / 缩放 1 / 位置回屏幕中央；坐标行/拖拽柄已收起"
        .. "；世界迷雾自建的层已收起 " .. tostring(tonumber(nRestore230) or 0) .. " 层、藏过的原生探索层已全部还回）")
    end
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
      if sub == "trace" or sub == "取证" then
        local ring = SM_CFG.mapFitTrace
        local n = (type(ring) == "table") and table.getn(ring) or 0
        local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
        out("[简易地图] 折算取证 " .. n .. " 条（旧 → 新）：")
        for i = 1, n do out("  " .. tostring(ring[i])) end
        if n == 0 then out("  （还是空的：开关一次「缩放大地图」或开一次地图就会记）") end
      elseif sub == "traceclear" or sub == "清取证" then
        SM_CFG.mapFitTrace = {}
        local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
        out("[简易地图] 折算取证已清空")
      elseif sub == "残留" or sub == "stale" or sub == "残留层" or sub == "残留贴图" then
        -- ★★★1.75.52（用户：「**在检测到地图签名变更的时候将这些不属于这块地图的贴图删除**」）：
        --   两个用途都在这一条命令里：① `on|off` = 与 [设置] 里那个开关**同一个写口**的等价入口；
        --   ② 不给参数 = **只读体检**（一个字节都不写）：把本帧每个 Texture 的「名字 / 贴图 / 图名段 / 结论」摊开。
        --   ★**地图开着（有残留）时跑最有意义** —— 那是「路径口径对不对」的唯一真机判据。
        local v = string.lower(string.match(sub, "^%S+%s+(%S+)") or "")
        if v == "on" or v == "开" then
          pcall(EVAL_SM_STALE_SET, true)
        elseif v == "off" or v == "关" then
          pcall(EVAL_SM_STALE_SET, false)
        end
        local lines = EVAL_WF_STALE_PROBE()
        for _, l in ipairs(lines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
        -- ★★★1.75.52 六改：把「接管守护」的**数量 + 存在性**体检一并打印（同样**零副作用**）——
        --   用户点名要「数量、存在性都要检查」⇒ 这两项必须有**只读**取证口，否则只能靠猜。
        local hlines = EVAL_WF_HOLD_PROBE()
        for _, l in ipairs(hlines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
        P("用法：/ehm mapfit 残留 [on|off]（别名 stale/残留层；不给参数 = 只读体检，含「接管守护」的数量/存在性）"
          .. "｜等价开关：工具箱 → 缩放大地图 → [设置] →「打开世界迷雾」")
      elseif sub == "perf" or sub == "性能" then
        -- ★★★1.75.54：**性能体检**（用户报障「开了十几个地区以后游戏会卡死」换来的取证口）。
        --   ★这一条**会真跑一拍渲染**（与正常节拍完全相同的那条路），会写地图层 —— 如实告知，不假装只读。
        local lines = EVAL_WF_PERF_PROBE()
        for _, l in ipairs(lines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
      elseif sub == "贴图" or sub == "tex" then
        -- ★★★1.75.53 只读体检：引擎自报的贴图路径 vs 我们按表拼的两条路径（自带 media / 客户端）——
        --   「发布后别人会不会找不到贴图」这一问，真机上一条命令就能看清。
        local tl = EVAL_WF_TEX_PROBE()
        for _, l in ipairs(tl) do
          P(l)
          pcall(mfLog, "%s", l)
        end
      elseif sub == "swm" or sub == "贴图替代" then
        -- ★★★「打开世界迷雾」（1.75.51 时叫「S_WorldMap 贴图替代」）：与工具箱 → 缩放大地图 → [设置] 里那个开关**同一个真值入口**
        --   （唯一写口 EVAL_SM_SWM_SET）—— 地图开着时敲不了命令（本项目定案），所以主入口是设置里的开关；
        --   这条命令只是给它一个**等价入口**（取证 / 脚本化用）。
        local v = string.lower(string.match(sub, "^%S+%s+(%S+)") or "")
        if v == "on" or v == "开" then
          pcall(EVAL_SM_SWM_SET, true)
        elseif v == "off" or v == "关" then
          pcall(EVAL_SM_SWM_SET, false)
        else
          P("打开世界迷雾 = **" .. (EVAL_WF_ON() and "开" or "关") .. "**")
          P("　" .. EVAL_SM_SWM_TIP())
        end
        P("用法：/ehm mapfit swm [on | off]（不给参数 = 只报当前）｜等价开关：工具箱 → 缩放大地图 → [设置]")
      else
        -- ★1.75.52（用户定：整条「探索层适配」摘除）⇒ `mapfit` 只剩三条真在干活的路
        --   （swm / 残留 / trace 族），不给子命令 = **现读现报**一份状态。
        P("缩放大地图：模块=" .. (EVAL_SM_ENABLED() and "**开**" or "关")
          .. " ｜ 打开世界迷雾=" .. (EVAL_WF_ON() and "**开**" or "关")
          .. " ｜ 残留图层清理=" .. (EVAL_WF_STALE_ON() and "开" or "关"))
        P("用法：/ehm mapfit swm [on|off] ｜ 残留 [on|off]（只读体检，含接管守护的数量/存在性）｜ 贴图（只读体检：贴图路径与来源）｜ perf（性能体检：真跑两拍，量耗时/写次数/护守）｜ trace [N] ｜ traceclear ｜ 清缓存")
        P("　★「叠加层适配（抓原值/折算/隐形）」已按 1.75.52 要求整条摘除 —— 「打开世界迷雾」的表驱动全渲染是它的替代方案。")
      end
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

-- ★★★1.75.5 修（用户报障，全案见参考卷 R20d）：**折算策略（诊断档）不跨会话** —— 载入期把上一会话遗留的那份清掉。
--   实案：`/ehm mapfit mode nofold` 是我给 A/B 用的诊断档，可它**落存档**；而主开关「关→开」只写 `mapFit`
--   （`tbCfg().simpleMap`）**从不复位策略** ⇒ 用户一旦切过 nofold，就变成「关闭/开启 缩放始终不生效」，
--   而且**跨会话一直在**（重启也没用）—— 因为 nofold = 一个几何都不碰，抓原值与折算都在函数第一行 return。
--   ⇒ 诊断档只在**本会话**有效：要在某个会话里长期不折算，用配置里的「叠加层适配」开关（`/ehm mapfit off`）。
--   ★必须挂 VARIABLES_LOADED：文件执行期存档表还是空的（本项目既有教训：迁移早调 = 从空表继承出空配置）。
do
  if type(CreateFrame) == "function" then
    local mg = CreateFrame("Frame", "EH_SM_MODEGUARD", UIParent)
    mg:RegisterEvent("VARIABLES_LOADED")
    mg:SetScript("OnEvent", function()
      if SM_CFG.mapFitMode ~= nil then
        local was = tostring(SM_CFG.mapFitMode)
        SM_CFG.mapFitMode = nil
        if was ~= "fold" then
          P("叠加层折算策略已回默认档（折算）：上一会话遗留的诊断档 " .. was .. " 已清（诊断档只在本会话有效）")
        end
      end
      -- ★1.75.5：**详细日志也只在」本会话有效**（同族理由：它是给排查用的，忘了关就会一直刷屏；
      --   要再开只需 `/ehm mapfit verbose on` 一句）。
      if SM_CFG.mapFitVerbose ~= nil then
        SM_CFG.mapFitVerbose = nil
        P("详细日志已回默认（关）：上一会话遗留的详细档已清（只在本会话有效；要开：/ehm mapfit verbose on）")
      end
      -- ★★★1.75.51（用户：「清理掉本地地图签名缓存」+「清理之前调试的一些日志」）：**一次性**清账。
      --   ★用标记键保证只清一次（之后再积累的取证环是**新一轮测试**的日志，不能再被清）。
      -- ★★★1.75.51：上一轮的**测试/探针**存档键一次性清掉（用户：「清理以上测试代码」）——
      --   /ehm mapdata 逐图核验（mapData / mapDataLog / mapDataArm）已整条删除，那几张表**没人再读**。
      --   ★必须用**新的**标记键：cacheCleared51 在用户的老存档里已经是 true ⇒ 复用它这一段根本不会跑。
      if not SM_CFG.probeCleared52 then
        SM_CFG.probeCleared52 = true
        local np, nk = 0, {}
        for _, k in ipairs({ "mapData", "mapDataLog", "mapDataArm" }) do
          if SM_CFG[k] ~= nil then SM_CFG[k] = nil np = np + 1 table.insert(nk, k) end
        end
        if np > 0 then
          P("已清理上一轮全图核验探针的存档（" .. table.concat(nk, " / ") .. "）")
        end
      end
      if not SM_CFG.cacheCleared51 then
        SM_CFG.cacheCleared51 = true
        local nc = EVAL_WF_CACHE_CLEAR("载入一次性清账")
        P("本地地图签名缓存 + 旧调试日志已清（存档老键 " .. tostring(nc) .. " 个）⇒ 从零开始：会话内存缓存已空、"
          .. "旧取证环已删，之后只留新一轮的日志")
      end
      -- ★★★1.75.54e 一次性**开关状态归一**（用户：「打开世界迷雾开关状态要做好正确的功能开关状态维护」）：
      --   合并开关（1.75.52）之前，「残留图层清理」有自己的开关且**落过存档**；老存档里它可能是**显式 false**
      --   而合并键 `swmOverlay` 从没写过（nil ⇒ 读时物化成 true 默认开）⇒ 那会出现
      --   「勾选框显示**开**、但清理那一半其实关着」的状态不一致。口径 = **尊重用户显式关过的那一次**：
      --   把合并键一起写成 false（一个控制管两件事，之后两族闸门天然一致）。
      --   ★只在这一种组合下迁移（合并键已写过就完全按用户的当前选择，绝不二次顶改）。
      if SM_CFG.swmOverlay == nil and SM_CFG.staleClean == false then
        SM_CFG.swmOverlay, SM_CFG.staleClean = false, false
        P("打开世界迷雾 = 关（老存档里「残留图层清理」是你**显式关过**的 ⇒ 合并成一个控制后按关处理；"
          .. "要开就在 工具箱 → 缩放大地图 → [设置] 里勾上）")
      end
      pcall(mg.UnregisterEvent, mg, "VARIABLES_LOADED")
    end)
  end
end

-- ============ 工具箱那一行（**嵌入点的被调方**）============
-- 工具箱只做两件事：模型数据里写一行 `{ t = "mod", mod = "simpleMap", … }`，渲染段按名字取这里的函数调一次。
--   控件、几何、tooltip、下拉、结算**全在本文件里**（与 LayerFix / DragFrames 同一套规矩）。
--   ★这一行**有**勾选框（模型里不写 `noChk`）：勾选框 = 本工具开/关（真值 = `tbCfg().simpleMap`，
--     与 `EVAL_SM_ENABLED()` 同源、与「子插件」Tab 无关 —— 本模块 1.74.29 起就是主插件的工具模块）。
--   ★`[设置]` = **多选下拉**（`EVAL_DD_OPEN` 的 multi 模式），三个条目：
--     ① 「GUI重开」= 开图时重显最外层 GUI（副作用见 TB_SM_GUIREOPEN_TIP*）；
--     ② 「打开世界迷雾」= 1.75.51「S_WorldMap 贴图替代」改名而来：按 S_WorldMap 区域表把本图整张画出来、忽略客户端内置探索纹理
--        （见 TB_SM_SWM_TIP* 与 MDQ 那一族；真值 = `SM_CFG.swmOverlay`，唯一写口 = `EVAL_SM_SWM_SET`）；
--     ③ 「残留图层清理」= 1.75.52 新增（**默认开**）：换图/开图时把**不属于本图**的叠加层贴图藏掉
--        （缩放到大陆/世界地图时上一张图的探索层会留在图上；见 TB_SM_STALE_TIP* 与 `MDQ.stale*`；
--         真值 = `SM_CFG.staleClean`，唯一写口 = `EVAL_SM_STALE_SET`）。
local SM_TIP_W = 460


-- 行内摘要（**现算**，不缓存：勾选/滚轮改完立刻重画）
--   ★1.74.36-3：末尾带上「默认档」三个值（都从 SM_DEF_* 现取，绝不写第二份字面量）——
--     用户看悬停就知道「关掉再开回来会回到什么档位」，不用猜。
function EVAL_SM_SUMMARY()
  return string.format("缩放 %.2f · 透明 %.2f · GUI重开 %s · 打开世界迷雾 %s（默认档 %.2f / %.2f / %s）",
    tonumber(SM_CFG.scale) or SM_DEF_SCALE, tonumber(SM_CFG.alpha) or SM_DEF_ALPHA,
    smReopenOn() and "开" or "关", EVAL_SM_FOG_ON() and "开" or "关",
    SM_DEF_SCALE, SM_DEF_ALPHA, SM_DEF_GUIREOPEN and "开" or "关")
end



-- 提示行（★用户原话里的副作用必须**如实写出来**，不许只写「可能有影响」）
function EVAL_SM_GUIREOPEN_TIPS()
  return { L("TB_SM_GUIREOPEN_TIP1"), L("TB_SM_GUIREOPEN_TIP2"), L("TB_SM_GUIREOPEN_TIP3") }
end

-- GUI重开真值**唯一写口**（命令行 `/ehm gui on|off` 与设置下拉两条路都走它）。
--   ★1.75.52 摘除探索层适配时，一次性脚本按「function NAME(」搜结尾 `end` 时把**紧邻的这一个**误删过一次
--     （症状 = `scan_dangling.js` 报 `EVAL_SM_GUIREOPEN_SET` 无守卫调用）⇒ 这里补回，并留一条判据：
--     **删函数块不许用「找下一个 col-0 end」这种启发式**（单行函数 `function X() ... end` 不是 col-0 `end`）。
function EVAL_SM_GUIREOPEN_SET(on)
  SM_CFG.guiReopen = on and true or false
  P("GUI重开 = " .. (smReopenOn() and "开（开图时重显最外层 GUI）" or "关（开图时不做任何额外 GUI 动作）"))
  return true
end

-- ===== ★★★1.75.52「打开世界迷雾」= **一个控制管两件事**（用户：「以上两个配置合成一个控制：打开世界迷雾」）
--   合并口径 = **一个写口把两个老键一起写**（`SM_CFG.swmOverlay` + `SM_CFG.staleClean`）：
--     开 = 表驱动全图渲染（忽略内置探索纹理）+ 残留清理；
--     关 = 两族都停（当场收回我们补建的层、把藏过的原生层全部 Show 还回，且此后一个字节都不碰）。
--   ★下面两族的闸门（`EVAL_WF_ON()` / `EVAL_WF_STALE_ON()`）**一个字都不用改** ⇒ 风险最小、行为可预期。
--   ★两个老写口（`EVAL_SM_SWM_SET` / `EVAL_SM_STALE_SET`）**全部转调这里** ⇒ 命令与界面**不可能各写一半**。
function EVAL_SM_FOG_ON() return EVAL_WF_ON() and EVAL_WF_STALE_ON() end

function EVAL_SM_FOG_SET(on)
  on = on and true or false
  SM_CFG.swmOverlay, SM_CFG.staleClean = on, on
  if not on then
    -- 关：**当场一次性收干净**（`MDQ.shutdown` = 收我们补建的层 + 还原复用池位的原值 + 把藏过的原生层全部还回），
    --   并把 `offDone` 置上 ⇒ 本拍之后 tick 每拍只判一个布尔就早退（零动作，绝不半关半开）。
    pcall(EVAL_WF_SHUTDOWN, "关闭世界迷雾")
    P("打开世界迷雾 = 关（回到客户端自己摆的探索层：我们补建的层已收起、复用过的池位已还原原贴图/几何、"
      .. "此前藏过的原生层已全部还回）")
  else
    -- 开：残留清理的账**只清不还**（可见性归「接管守护」，走还回会先闪一下又被藏）。
    EVAL_WF_OFF_RESET()   -- ★1.75.54d：重新打开 ⇒ 下一次闸门判定不再走「已关」那条早退路
    -- ★1.75.55：探索层折算**先按原值还回**（开着世界迷雾时那批层归表驱动全渲染负责，别两套抢同一批几何）
    pcall(MDQ.fitClose, "打开世界迷雾")
    pcall(EVAL_WF_STALE_FORGET, "世界迷雾已开")
    P("打开世界迷雾 = 开（本图整张由 S_WorldMap 表渲染 + 残留清理；不再自己跑图探索）")
    P("　" .. EVAL_SM_SWM_TIP())
  end
  return true
end

-- ===== 1.75.51「S_WorldMap 贴图替代」（**已并入上面的「打开世界迷雾」**）=====
-- 真值读写：读走 `EVAL_SM_SWM_ON()`（与渲染族同源 = `EVAL_WF_ON()`），写走 `EVAL_SM_SWM_SET()`（**转调合并写口**）。
function EVAL_SM_SWM_ON() return EVAL_WF_ON() end

function EVAL_SM_SWM_SET(on)
  return EVAL_SM_FOG_SET(on)
end

-- 行 tooltip / 菜单里那一句（与真值同源；别处不许再拼一遍文案）
--   ★★★1.75.52（用户：「以上信息直接替换成: 初看是这个世界的,其实不是这个世界的.有没似陈相识? **不要加额外信息**」）
--   ⇒ 说明**就这一句**（`TB_SM_SWM_TIP1`，三语同文），这里**不再拼任何前缀/后缀**
--     （旧写法还拼「打开世界迷雾：开（默认）」+ 两三句技术解释 ⇒ 悬停一屏全是字，正是用户要清掉的东西）。
function EVAL_SM_SWM_TIP()
  return L("TB_SM_SWM_TIP1")
end

-- 下拉那一行自己的悬停（与 [设置] 悬停**同一句**，避免两处文案各写一遍）
function EVAL_SM_SWM_TIPS()
  return { EVAL_SM_SWM_TIP() }
end

-- ===== 1.75.52「残留图层清理」（**已并入「打开世界迷雾」**；命令入口保留，写口转调合并写口）=====
-- 真值读写：读走 `EVAL_SM_STALE_ON()`（与清理族同源 = `EVAL_WF_STALE_ON()`），写走 `EVAL_SM_STALE_SET()`（**转调合并写口**）。
function EVAL_SM_STALE_ON() return EVAL_WF_STALE_ON() end

function EVAL_SM_STALE_SET(on)
  return EVAL_SM_FOG_SET(on)
end



-- 菜单内容（与行渲染**同源**：勾选态 = 真值现算）
--   ★★★1.75.52（用户：「以上两个配置合成一个控制：**打开世界迷雾**」）：
--     残留清理那一项**并进全图开关** ⇒ 菜单只剩两项（GUI重开 / 打开世界迷雾）；
--     勾选态 = `EVAL_WF_ON()`（全图那一档的闸门；写的时候**两个老键一起写**，见 `EVAL_SM_FOG_SET`）。
function EVAL_SM_MENU()
  local items = { L("TB_SM_GUIREOPEN"), L("TB_SM_SWM") }
  local locked = {}
  local tips = { EVAL_SM_GUIREOPEN_TIPS(), EVAL_SM_SWM_TIPS() }
  local keys = { "guiReopen", "swmOverlay" }
  local sel = {}
  if smReopenOn() then sel[1] = true end
  if EVAL_WF_ON() then sel[2] = true end
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
    -- ★★★1.75.52（用户：「设置说明清理下，**只保留红色选中部分**」）：
    --   [设置] 按钮的悬停**只留「打开世界迷雾」这一句**（唯一真正属于这个按钮的说明）。
    --   ★其余各行**没有丢**，只是不在这里堆：GUI重开 / 打开世界迷雾 的逐条说明在下拉**各自那一行**的悬停里
    --     （`EVAL_SM_MENU` 的 `tips`），残留清理 / 叠加层适配 / 默认档的说明在各自的行与 `/ehm mapfit` 命令里。
    pcall(tip.AddLine, tip, EVAL_SM_SWM_TIP(), 0.62, 0.82, 1.00)
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
      -- ★★★合并开关：一个控制管「表驱动全图 + 残留清理」两件事（`EVAL_SM_FOG_SET` 两个老键一起写）
      if key == "swmOverlay" then pcall(EVAL_SM_FOG_SET, on == true) end
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


-- ★★★1.75.52（用户定：整条「探索层适配」摘除）——**原来这里的读值口整族已删**：
--   `EVAL_SM_TEST_MAPFIT_REC`（本图记录条数）· `EVAL_SM_TEST_FIX_ACTIVE/ARM/ARM_LEFT`（`/ehm fitnow 待命` 状态）·
--   `EVAL_SM_TEST_NAT_LEFT/NAT_SCALE`（自然档窗口预算/外框缩放）· `EVAL_SM_TEST_MAPFIT_PLANT`（种记录）。
--   理由：它们的**唯一真值来源**（`SMFIT` 那张表）已随适配整条删除 ⇒ 留着就是「读永远 0 / 恒 false」的死口。
--   ★留一句纪律：读值口**要么挂到 `/ehm` 命令上（活），要么别加** —— 只给离线 harness 用的口，删功能时必须一起删。

-- ★★★1.75.49 → 1.75.52 **这一族口已删，不再留空壳**：图层调试子插件（EH_DebugBox）曾问这里要
--   「某探索层的系统原值」（旧 `EVAL_SM_ORIG_OF`，从抓原值那一拍的记账表取）。
--   抓原值整条随「探索层适配」摘除 ⇒ **来源永久缺席** ⇒ 空壳口（恒返回 nil）也一并删掉：
--   子插件的 `type(rawget(_G,"EVAL_SM_ORIG_OF"))=="function"` 守卫会如实报「不在」，四级来源自动降一级。
--   ★★结论性事实（写进 CLAUDE.md / DebugBox 注释）：现在「原始尺寸」的**唯一可信来源**
--     = 子插件自己**第一次改之前**读到的值（`uiCustEnsure`）；其余（首次观测 / 无记录）都只是观测值。

-- ============ 迷雾模块（`tools\WorldFog.lua`）要的桥（1.75.56 拆分时加的）============
--   ★★★为什么要有这一段：迷雾整族搬出去之后，它需要**宿主（本文件）的几个文件局部**（配置表 / 地图身份 /
--     有效缩放 / 播报出口）—— 跨文件拿不到 local，只能走 `_G`。这里统一暴露成 `EVAL_SM_*`。
--   ★一律「调用时读」：桥自己就是函数，WorldFog 侧**拿到才调** ⇒ `.toc` 顺序不敏感、载入期零依赖。
--   ★**只暴露这几个**（别的都不给）：耦合面越小，将来两边各自改就越不容易互相带坏。
EVAL_SM_CFG = function() return EH_SIMPLEMAP_CFG end
EVAL_SM_MAPINFO = function() return smMapInfo() end
EVAL_SM_MAPKEY = function() return smMapKey() end
EVAL_SM_NUMOVERLAYS = function() return smNumOverlays() end
EVAL_SM_EFFSCALE = function(fr) return smEffScale(fr) end
EVAL_SM_FITSAY = function(...) return smFitSay(...) end
EVAL_SM_FITSAYV = function(...) return smFitSayV(...) end
EVAL_SM_MFLOG = function(...) return mfLog(...) end
EVAL_SM_FRAMENAME = function(v) return frameName(v) end
