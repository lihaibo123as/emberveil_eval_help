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
local function featApplyScale(s)
  local w = featWm()
  if not w then return end
  s = tonumber(s) or 1
  -- ★1.75.52：原来这里还有一道「抓原值窗口内先不缩放」的闸门（`smFitHold`）—— 随探索层适配整条摘除。
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
local MDQ = {}

-- ★★★「残留图层清理」的节拍与有界上限（★1.75.52 摘除探索层适配时**误删过一次** ⇒ 常量一律留在 MDQ 表上、
--   紧挨着表定义，别再夹在别的族中间）。
MDQ.STALE_GAP = 0.25      -- 换图/开图窗口内的扫描节拍（客户端这时还在重摆/重指贴图，扫密一点）
MDQ.STALE_GAP_IDLE = 1.0  -- 窗口外的节拍（非区域地图上照样把「又冒出来的」叠加层再藏掉）
MDQ.STALE_SEC = 3.0       -- 「换图 / 开图」后的快扫窗口长度（窗口内 0.25s 一拍）
MDQ.STALE_LOG_MAX = 40    -- 「藏了哪些纹理」的**有界落盘环**上限（`SM_CFG.staleLog`，最新在前）
-- ★★★**同一处误删的还有这张表**（真机红字：`bad argument #1 to 'pairs' (table expected, got nil)` @ tick 里那行）：
--   `MDQ.staleHid` = **藏账**（纹理对象 → { name = 层名, path = 当时的贴图 }）；区域图上全部还回时清空。
--   ⇒ 与上面四个常量一起留在表定义旁边；★纪律：**摘除大块代码后必须做一次「状态初始化审计」**
--     （凡是挂在 `MDQ` / 原先那张 `SMFIT` 上的状态表，逐个确认还有没有创建点）—— 光跑语法闸门与 scan_dangling **抓不到这种雷**。
MDQ.staleHid = {}         -- 藏账：纹理对象 → { name = 层名, path = 当时的贴图 }（区域地图上**全部还回**并清账）

MDQ.TILE = 256       -- Mozz 口径的分块边长
MDQ.poolMax = 240    -- 纹理池上限（防病态表把纹理建爆；撞上就如实报「上限已满」）
MDQ.own = {}         -- 我们自己补建的纹理：池位号 → 纹理对象（跨帧复用，绝不每帧新建）
MDQ.made = {}        -- 同上（按名字记；收层时一起清）
MDQ.ownSet = {}      -- 同上但按**对象身份**记（`MDQ.own[n] = 纹理` ⇒ 反查「这张是不是我们自建的」）：
                     --   ★1.75.52 六改「接管守护」要用它区分「客户端原生层」与「我们自己画的层」——
                     --   名字判定不够（本客户端那批原生层也叫 `WorldMapOverlay<n>`，我们补建的还可能与之重名）。
MDQ.poolSeen = 0     -- 见过的最大池位号（收尾 Hide 只扫到它，不空扫 poolMax 次）
MDQ.newN = 0         -- **本轮**新加了几张（渲染行如实报「客户端既有 N ｜ 新加 M」）
MDQ.saidMk = nil     -- 上一张已播报过的地图（每图只报一次，不刷屏）

-- ★★★1.75.54 **性能收口（1.75.53 真机报障「开了十几个地区以后游戏会卡死」换来的）** —— 三处：
--   ① **写前比对**（`MDQ.slot`）：每块记住「上次写进去的 (地图/区域/块号/倍率/对象)」，
--      完全一样就**一个 `Set*` 都不发** ⇒ 稳态（没换图/没缩放）每拍零写；
--      这也是唯一能保证「不因为反复 `SetTexture` 而反复取贴图文件」的做法。
--   ② **护守只在节流那一拍跑**（逐帧重申那条 silent 路径**不跑** `holdTick`）⇒
--      每帧 `GetRegions()` + 逐 region `GetName()` 的字符串风暴消失。
--   ③ **爆发窗不许被我们自己的写入反复重新武装**（原来 `es` 抖 0.001 就重置 2s 窗口，
--      而我们每拍都在写几何 ⇒ 窗口永不结束 = **每帧整张图重写**）；现在只认**引擎真值**变化，
--      且重新武装有**最小间隔** + 窗口内**帧数上限**，超了如实出声并降档。
MDQ.slot = {}            -- 池位号 → { tex=, file=, area=, tile=, k=, shown=true }（写前比对用）
MDQ.wroteN = 0           -- 本拍**真发出去的**写次数（取证用；稳态应为 0）
MDQ.skipN = 0            -- 本拍因「内容没变」跳过的块数（取证用）
MDQ.SLOW_MS = 12         -- ★安全阀：单拍渲染超过这个毫秒数 ⇒ 降档（宁可少重申，绝不卡死）
MDQ.SLOW_WARN_MS = 6     -- 连续 3 拍超过它 ⇒ 也降档（提前刹车）
MDQ.perfGuard = false    -- 已降档标记（本会话）；`/ehm mapfit perf` 可看、`重启/关开关`复位
MDQ.perfRing = {}        -- 有界取证环（最近 12 拍：{ ms, wrote, skip, n, seen, k }）
MDQ.PERF_RING_MAX = 12

-- ===== ★★★1.75.53：贴图**来源**解析 + 存在性探针（发布独立性；用户：「插件要绝对独立，
--   依赖的东西要复制到插件内自己载入，不然发布上去别人又可能找不到贴图」）=====
--   ① **自带贴图优先**：`EvalHelp\media\WorldMap\<地图>\<区域><块号>` —— 只要那份**能加载**就用它
--      ⇒ 把贴图拷进 `media/WorldMap/` 就自动变成完全自包含（不用改一行代码）。
--   ② 否则退回**客户端自带** `Interface\WorldMap\<地图>\<区域><块号>`（1.12 客户端的探索层美术，
--      与上游 `S_WorldMap` 逐字同口径，见 `Modules/MapOverlay.lua:744/835`）。
--   ③ 两份都**加载不出来** ⇒ `"none"` ⇒ **这一张图不接管**（不渲染、不藏原生、如实出声一次）
--      —— 依据本项目铁律「拿不到证据就一个字节都不碰」：宁可保持客户端原样，也绝不画出一片空白图。
--   ★探针口径：新建一张**不设宽高**的纹理 ⇒ `SetTexture(p)` ⇒ 读 `GetWidth/GetHeight`（客户端报的是
--     **贴图文件**的像素尺寸）。文件在 ⇒ >0；文件不在 ⇒ 0；**读不到/判不出 ⇒ nil = 不拦**（fail-open：
--     判据本身没把握时绝不把功能关死；只有明确探到 0 才判定「没有」）。
--   ★探针纹理**每次新建一张**（匿名、不 Show；1.12 没有销毁纹理的 API ⇒ 泄漏无害），
--     结果按路径缓存（`MDQ.tpOK`）⇒ 每张图最多建两张，绝不逐块探。
MDQ.tpOK = {}        -- 路径 → true/false（会话级缓存；nil = 没探过或判不出）
MDQ.texSrc = {}      -- 地图 → "own" | "client" | "none"（每图只判一次，缓存）

MDQ.probeTex = function(path)
  local c = MDQ.tpOK[path]
  if c ~= nil then return c end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") or type(fr.CreateTexture) ~= "function" then return nil end
  -- ★每次**新建**一张探针纹理（不复用）：复用有「上一次的文件尺寸残留 ⇒ 探出假结果」的风险；
  --   结果按路径缓存 ⇒ 每张图最多建两张，代价可忽略（匿名、不 Show、不进我们的池位）。
  local ok, t = pcall(fr.CreateTexture, fr, nil, "ARTWORK")
  if not ok or t == nil then return nil end
  if type(t.SetTexture) ~= "function" or type(t.GetWidth) ~= "function" then return nil end
  if not pcall(t.SetTexture, t, path) then return nil end
  local okw, w = pcall(t.GetWidth, t)
  local okh, h = pcall(t.GetHeight, t)
  if not (okw and okh) then return nil end
  local w2, h2 = tonumber(w), tonumber(h)
  if w2 == nil and h2 == nil then return nil end -- 判不出 ⇒ 不拦（fail-open）
  local ok2 = (w2 or 0) > 0 and (h2 or 0) > 0
  MDQ.tpOK[path] = ok2 and true or false
  return ok2 and true or false
end

-- ★★★探针的**负对照**（1.75.53b 真机报障换来的）：本客户端**对「文件不存在」的报法并不一致** ——
--   `.blp` 这种带扩展名的路径**明明没有文件，也可能报出非 0 尺寸** ⇒ 只按「>0 = 有」判，会**把没有的
--   当成有** ⇒ 整张图都去加载**不存在的自带贴图** ⇒ 用户眼里的「去迷雾贴图没生效了」（我们画的块全空）。
--   ⇒ 每个写法都配一张**同目录、同后缀、不可能存在**的对照路径：
--     ① 对照也说「有」⇒ 这个写法**读不出真假** ⇒ 返回 nil（判不出）；
--     ② 判不出 ⇒ 一律**退回客户端那份**（= 一直可用的行为；依据铁律「拿不到证据就一个字节都不碰」）。
MDQ.probeBogus = "__eh_nosuch__"
MDQ.probeTrust = function(path)
  local r = MDQ.probeTex(path)
  if r == nil then return nil end
  local p = tostring(path)
  local dir = string.gsub(p, "[^\\]*$", "")          -- 去掉文件名 → 留目录（含结尾反斜杠）
  local e = string.find(p, "%.[A-Za-z0-9]+$")
  local ext = (e ~= nil) and string.sub(p, e) or ""  -- 同后缀（负对照也要走同一条解析路）
  if MDQ.probeTex(dir .. MDQ.probeBogus .. ext) == true then return nil end
  return r
end

-- 自带贴图的路径前缀（相对插件目录；`media\WorldMap\...` 是可选的「自己载入」那一份）
MDQ.ownPfx = "Interface\\AddOns\\EvalHelp\\media\\WorldMap\\"
MDQ.cliPfx = "Interface\\WorldMap\\"

-- ★★★自带那份的**写法（后缀）必须逐个试**：本客户端对**插件目录里的散装文件**要求**写扩展名**
--   （已在案：`media\Flags\<名>.tga` 就是这么写进 `SetTexture` 的，见 `EvalHelp.lua:1521`），
--   而客户端自带的美术在**归档**里，一律**不写扩展名**（上游 `S_WorldMap` 同款）。
--   ⇒ 依次试 `.blp` → `.tga` → 不写，**哪个能加载就用哪个**（判据 = 探针读得到文件尺寸）。
MDQ.ownForms = { ".blp", ".tga", "" }
MDQ.srcPick = {}     -- 地图 → 选中的写法："own:blp" / "own:tga" / "own:raw" / "client" / "none"
                     --   （`texPath` 按它拼；`srcOf` 把前三种归一成 "own"）
MDQ.ownExtOf = function(key)
  local s = tostring(key)
  if string.sub(s, 1, 4) ~= "own:" then return "" end
  local e = string.sub(s, 5)
  if e == "raw" then return "" end
  return "." .. e
end

-- 本图的贴图来源（每图判一次，缓存）："own:blp" / "own:tga" / "own:raw" / "client" / "none"
MDQ.srcKey = function(file)
  local s = MDQ.srcPick[file]
  if s ~= nil then return s end
  local m = MDQ.areaOf(file)
  local areas = {}
  if type(m) == "table" then for a in pairs(m) do table.insert(areas, a) end end
  table.sort(areas)
  local a0 = areas[1]
  if a0 == nil then MDQ.srcPick[file], MDQ.texSrc[file] = "none", "none" return "none" end
  local unclear = false
  for _, ext in ipairs(MDQ.ownForms) do
    local own = MDQ.probeTrust(string.format("%s%s\\%s1%s", MDQ.ownPfx, file, a0, ext))
    if own == true then
      local key = (ext == "") and "own:raw" or ("own:" .. string.sub(ext, 2))
      MDQ.srcPick[file], MDQ.texSrc[file] = key, "own"
      return key
    end
    if own == nil then unclear = true end
  end
  local cli = MDQ.probeTrust(string.format("%s%s\\%s1", MDQ.cliPfx, file, a0))
  -- ★只有**明确探到「没有」**（false）才判 none；`nil`（判不出）按「客户端有」处理 —— 不拦、不关功能。
  if cli == false and not unclear then
    MDQ.srcPick[file], MDQ.texSrc[file] = "none", "none"
    return "none"
  end
  MDQ.srcPick[file], MDQ.texSrc[file] = "client", "client"
  return "client"
end

-- 本图的贴图来源（**三态**，给播报与外部读）：own（自带那份可用）/ client（客户端美术）/ none（都不行）
MDQ.srcOf = function(file)
  local k = MDQ.srcKey(file)
  if k == "none" then return "none" end
  if k == "client" then return "client" end
  return "own"
end

-- 实际写进 `SetTexture` 的路径（自带那份能用就用自带的 ⇒ 拷进 media 即自包含）
MDQ.texPath = function(file, a, t)
  local k = MDQ.srcKey(file)
  if k == "none" or k == "client" then return string.format("%s%s\\%s%d", MDQ.cliPfx, file, a, t) end
  return string.format("%s%s\\%s%d%s", MDQ.ownPfx, file, a, t, MDQ.ownExtOf(k))
end

-- ★只读体检：`/ehm mapfit 贴图` —— 把「引擎自报的贴图路径」与「我们按表拼的两条路径」并排列出来，
--   并逐条给**探针结果**（文件加载得出来 / 探不到 / 判不出）。零副作用（只建一张不显示的探针纹理）。
MDQ.texProbe = function()
  local out = {}
  local file, w, h = smMapInfo()
  out[table.getn(out) + 1] = string.format("贴图体检：地图=%s（%sx%s）｜ 表里 %s ｜ 来源判定=%s",
    tostring(file), tostring(w), tostring(h),
    (function() local m = MDQ.areaOf(tostring(file)); if type(m) ~= "table" then return "**没有这张图**" end
      local n = 0 for _ in pairs(m) do n = n + 1 end return n .. " 区" end)(),
    tostring(MDQ.texSrc[tostring(file)] or "（还没判过）"))
  out[table.getn(out) + 1] = "　路径前缀：自带=" .. MDQ.ownPfx .. "　客户端=" .. MDQ.cliPfx
  -- ① 引擎自报（客户端自己那批探索层的贴图路径 —— 「这批贴图到底叫什么」的唯一真值）
  local n = nil
  if type(GetNumMapOverlays) == "function" then local ok, v = pcall(GetNumMapOverlays) if ok then n = tonumber(v) end end
  out[table.getn(out) + 1] = string.format("① 引擎自报 GetNumMapOverlays=%s", tostring(n))
  if type(GetMapOverlayInfo) == "function" and (n or 0) > 0 then
    for i = 1, math.min(n, 6) do
      local ok, nm, tw, th, ox, oy = pcall(function() return GetMapOverlayInfo(i) end)
      if ok and nm ~= nil then
        local r = MDQ.probeTex(tostring(nm))
        out[table.getn(out) + 1] = string.format("　[%d] %s ｜ %sx%s @%s,%s ｜ 探针=%s", i, tostring(nm),
          tostring(tw), tostring(th), tostring(ox), tostring(oy),
          (r == true) and "**加载得出来**" or (r == false and "**探不到**" or "判不出"))
      end
    end
    if (n or 0) > 6 then out[table.getn(out) + 1] = string.format("　…（另有 %d 条）", n - 6) end
  end
  -- ② 我们按表拼的两条路径（本图第一个区域的第一块）
  local m = MDQ.areaOf(tostring(file))
  if type(m) ~= "table" then
    out[table.getn(out) + 1] = "② 表里没有这张图 ⇒ 本来就不渲染（客户端探索层保持原样）"
  else
    local areas = {}
    for a in pairs(m) do table.insert(areas, a) end
    table.sort(areas)
    local a0 = areas[1]
    local cliP = string.format("%s%s\\%s1", MDQ.cliPfx, tostring(file), tostring(a0))
    local rc = MDQ.probeTrust(cliP)
    local fmt = function(p, r)
      return string.format("　%s ｜ 探针=%s", p, (r == true) and "**加载得出来**" or (r == false and "**探不到**" or "判不出"))
    end
    out[table.getn(out) + 1] = string.format("② 本表 %d 区 ｜ 首个区域=%s ⇒ 我们拼的路径（自带那份逐个写法都试）：",
      table.getn(areas), tostring(a0))
    for _, ext in ipairs(MDQ.ownForms) do
      local p = string.format("%s%s\\%s1%s", MDQ.ownPfx, tostring(file), tostring(a0), ext)
      out[table.getn(out) + 1] = fmt(p, MDQ.probeTrust(p))
    end
    out[table.getn(out) + 1] = fmt(cliP, rc)
    out[table.getn(out) + 1] = "　（每个写法都带**负对照**：同目录同后缀的不可能文件名；对照也说「有」⇒ 该写法判不出 ⇒ 退回客户端）"
    local key = tostring(MDQ.srcKey(tostring(file)))
    local src = MDQ.srcOf(tostring(file))
    out[table.getn(out) + 1] = "　⇒ 选中写法：" .. key
    out[table.getn(out) + 1] = (src == "own") and "　⇒ 结论：**用自带的 media 贴图**（插件自包含）"
      or ((src == "client") and "　⇒ 结论：**用客户端自带贴图**（`Interface\\WorldMap`）"
      or "　⇒ 结论：**两份都探不到 ⇒ 本图不接管**（不渲染、不藏原生；客户端探索层保持原样）")
  end
  out[table.getn(out) + 1] = "　★判据：自带那份只要能加载就**优先用它** ⇒ 把贴图拷进 `media\\WorldMap\\<地图>\\<区域><块号>.blp` 即完全自包含（不用改代码）。"
  out[table.getn(out) + 1] = "　★探针可信度（拿一个**不可能存在**的客户端路径当负对照）："
    .. ((MDQ.probeTrust(MDQ.cliPfx .. MDQ.probeBogus) == nil)
      and "**判不出** —— 本客户端对「文件不存在」也报尺寸 ⇒ 一律**退回客户端那份**（绝不改走不存在的自带路径）"
      or "可信（不存在 ⇒ 报 0）⇒ 自带那份的判定可用")
  out[table.getn(out) + 1] = "　★写法：插件目录里的散装文件**要写扩展名**（同 `media\\Flags\\<名>.tga`），所以自带那份按 `.blp` → `.tga` → 不写 依次试。"
  out[table.getn(out) + 1] = "　★探针口径：不设宽高的临时纹理 + `SetTexture` + 读 `GetWidth/GetHeight`（文件在 ⇒ >0；不在 ⇒ 0；**判不出 ⇒ 不放拦**）。"
  return out
end

-- 开关真值（唯一入口）：`SM_CFG.swmOverlay`（nil/false = 关 = 默认；true = 开）。
--   ★**落存档**（这是产品开关，与「只在本会话有效」的诊断档不同）；写入点只有两个：
--     `EVAL_SM_SWM_SET`（设置下拉 / 命令都走它）与老键迁移。
MDQ.swm = function()
  -- ★★★1.75.52（用户：「缩放大地图->设置->**默认开启全图**」）：真值 = `SM_CFG.swmOverlay`，**默认开**——
  --   键为 nil ⇒ **当场物化 true**（本项目「默认开」的定式，同 EC/HH）；**显式关过（false）永远是关**
  --   （读的时候绝不用 `or true` 顶回用户的选择）。
  if type(SM_CFG) == "table" and SM_CFG.swmOverlay == nil then SM_CFG.swmOverlay = true end
  return (type(SM_CFG) == "table") and SM_CFG.swmOverlay == true
end

-- 期望分块数（列×行）
MDQ.tiles = function(w, h)
  local a, b = tonumber(w) or 0, tonumber(h) or 0
  if a <= 0 or b <= 0 then return 0 end
  return math.ceil(a / MDQ.TILE) * math.ceil(b / MDQ.TILE)
end

-- 贴图文件边长（Mozz 口径：从 16 起按 2 的幂倍增到 ≥ 像素）—— SetTexCoord 的分母就是它
MDQ.fileDim = function(px)
  local v = tonumber(px) or 0
  if v <= 16 then return 16 end
  local d = 16
  while d < v do d = d * 2 end
  return d
end

-- 第 t 块（1 基，行优先）的**期望**像素几何：宽, 高, offsetX, offsetY（读不出 ⇒ nil）
MDQ.expectRect = function(rec, t)
  if type(rec) ~= "table" then return nil end
  local w, h, ox, oy = tonumber(rec[1]), tonumber(rec[2]), tonumber(rec[3]), tonumber(rec[4])
  if not (w and h and ox and oy) then return nil end
  local nh = math.max(1, math.ceil(w / MDQ.TILE))
  local nv = math.max(1, math.ceil(h / MDQ.TILE))
  local idx = math.max(1, tonumber(t) or 1)
  if idx > nh * nv then return nil end
  local j = math.floor((idx - 1) / nh) + 1        -- 第几行
  local k = ((idx - 1) % nh) + 1                  -- 第几列
  local pw = (k < nh) and MDQ.TILE or (w % MDQ.TILE)
  local ph = (j < nv) and MDQ.TILE or (h % MDQ.TILE)
  if pw == 0 then pw = MDQ.TILE end
  if ph == 0 then ph = MDQ.TILE end
  return pw, ph, ox + MDQ.TILE * (k - 1), oy + MDQ.TILE * (j - 1)
end

-- ===== ★★★1.75.51 倍率 k = **现读**（当前缩放级别 × 数据库，实时算；不留常数）=====
-- 用户要求（原话）：「缩放要根据当前缩放级别和数据库实时计算。」
--   做法 = **拿引擎在当前缩放级别下给出的叠加层真值 ÷ 表推值**：
--     · `GetNumMapOverlays()` + `GetMapOverlayInfo(i)` 是**引擎**按当前地图/缩放级别列出来的
--       (贴图名, 宽, 高, offsetX, offsetY) —— **与我们写没写过无关** ⇒ 任何时候读都是引擎的真值；
--     · 贴图名按 Mozz 规则解析回 (地图, 区域, 块号)，去表里取**同一块**的表推宽 ⇒ 比值 = 当前倍率；
--     · 多个样本取**中位数**；≥3 个样本且离散度 > 15% ⇒ **判不出**（表与客户端内容不同源，不硬套）；
--     · 现读不出（本图 0 条 / 名字读不懂 / 表里没这一块）⇒ **兜底用外框有效缩放**（沿父链连乘，也是现读）；
--       连它也读不到 ⇒ 按 1 写，并**如实说「判不出」**（绝不假装算出来了）。
--   ★**不漂移**：我们写进去的是「表值 × k」，下一拍再测仍是同一个 k（引擎真值不因我们改写而变）⇒ 稳态下 k 恒定；
--     客户端一换图 / 一缩放，引擎真值跟着变 ⇒ 下一拍自动跟上（这就是「实时计算」）。
--   ★每拍现读（0.2s 节流 + 按地图签名缓存），代价 = 每 0.2s 约 N 次只读 API（N = 本图叠加层条数）。
MDQ.kCache = {}     -- 地图签名 → { k = 倍率, src = 来源说明, n = 样本数 }
MDQ.kAt = 0         -- 上次现读的时间（节流用）

-- 贴图名解析：`Interface\WorldMap\<地图文件名>\<区域名><分块号>` —— 返回表，或 nil（读不懂就 nil，绝不猜）
MDQ.parse = function(name)
  local s = tostring(name or "")
  if s == "" then return nil end
  local dir, leaf = string.match(s, "^(.*)\\([^\\]+)$")
  if not dir or not leaf or leaf == "" then return nil end
  local mf = string.match(dir, "([^\\]+)$")
  if not mf or mf == "" then return nil end
  local base, digits = string.match(leaf, "^(.-)(%d*)$")
  if not base or base == "" then return nil end
  return { file = mf, leaf = leaf, area = base, tile = (digits ~= "" and tonumber(digits)) or 1 }
end

-- 现读倍率：引擎真值 ÷ 表推值（多样本取中位数；离散太大 ⇒ nil,样本数）
MDQ.measureK = function(file, m)
  if type(m) ~= "table" then return nil, 0 end
  local n = tonumber(smNumOverlays()) or 0
  if n <= 0 then return nil, 0 end
  local rs = {}
  for i = 1, n do
    local ok, nm, w = pcall(function() return GetMapOverlayInfo(i) end)
    if ok and nm then
      local px = MDQ.parse(nm)
      if px and tostring(px.file) == tostring(file) then
        local rec = m[px.leaf] or m[px.area]
        local ew = rec and select(1, MDQ.expectRect(rec, px.tile))
        local cw = tonumber(w)
        if ew and cw and ew > 8 then
          local r = cw / ew
          if r > 0.05 and r < 20 then table.insert(rs, r) end
        end
      end
    end
  end
  local cnt = table.getn(rs)
  if cnt == 0 then return nil, 0 end
  table.sort(rs)
  local med = rs[math.floor((cnt + 1) / 2)]
  if cnt >= 3 then
    local spread = (rs[cnt] - rs[1]) / med
    if spread > 0.15 then return nil, cnt end   -- 离散太大 ⇒ 表与客户端不同源 ⇒ 判不出（不硬套）
  end
  return med, cnt
end

-- 现读（0.2s 节流 + 按地图签名缓存）；返回 k, 来源说明, 样本数
MDQ.kLive = function(file, m, es)
  local now = (type(GetTime) == "function") and GetTime() or 0
  local mk = smMapKey() or file
  local c = MDQ.kCache[mk]
  if type(c) == "table" and (now - (tonumber(MDQ.kAt) or 0)) < 0.2 then return c.k, c.src, c.n end
  local k, nS = MDQ.measureK(file, m)
  local src
  if k then
    src = string.format("引擎实测（%d 个样本）", nS)
  else
    k = tonumber(es)
    if k and k > 0 then
      src = (nS > 0) and "外框有效缩放（引擎真值离散太大 ⇒ 兜底现读）" or "外框有效缩放（引擎没给本图叠加层 ⇒ 兜底现读）"
    else
      k, src = 1, "**判不出**（引擎与缩放都读不到 ⇒ 按 1 写）"
    end
  end
  MDQ.kCache[mk] = { k = k, src = src, n = nS }
  MDQ.kAt = now
  return k, src, nS
end

-- 取池位 n 的纹理：① 客户端已有的（`_G` 里查得到）→ 复用；② 我们自己补建的 → 复用；③ 都没有 ⇒ **现场补建**
--   ★两级建法：先按客户端的命名习惯建具名（`WorldMapOverlay<n>`，与 S_WorldMap 同法 ⇒ 能一路接管它的池位）；
--     具名失败（名字被占 / 本客户端不许具名）⇒ **退回匿名纹理**（照样能画，只是 `_G` 里查不到）—— 绝不静默放弃。
--   ★返回值带**来源**（existing / own / created / no_frame / create_failed），渲染行如实报「既有 N ｜ 新加 M」。
MDQ.texAt = function(n)
  local nm = "WorldMapOverlay" .. tostring(n)
  if n > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = n end
  local t = rawget(_G, nm)
  if t ~= nil then
    -- ★★★1.75.52 六改 b：**复用来的池位也算「我们接管了」** —— 我们马上要往它身上写表内容；
    --   不标记的话「接管守护」会把它当客户端原生层**再藏一次** ⇒ 数据库查出来的层等于没加上（用户实报）。
    MDQ.ownSet[t] = true
    return t, "existing"
  end
  t = MDQ.own[n]
  if t ~= nil then
    MDQ.ownSet[t] = true
    return t, "own"
  end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") or type(fr.CreateTexture) ~= "function" then
    return nil, "no_frame"
  end
  local ok, t2 = pcall(fr.CreateTexture, fr, nm, "ARTWORK")
  if not ok or t2 == nil then
    local ok2, t3 = pcall(fr.CreateTexture, fr, nil, "ARTWORK")   -- ★退回匿名（照样能画）
    if ok2 and t3 ~= nil then t2 = t3 else return nil, "create_failed" end
  end
  MDQ.own[n] = t2
  MDQ.made[nm] = true
  MDQ.ownSet[t2] = true     -- ★身份账（接管守护判「这张是不是我们自建的」唯一依据）
  MDQ.newN = (tonumber(MDQ.newN) or 0) + 1
  return t2, "created"
end

-- 从第 from 位起把池位全部 Hide（客户端池 + 我们自己补的）。
--   ★**不空扫**：客户端那批名字是从 1 起的**连续**池位 ⇒ 扫到「既没有具名纹理、又超过我们见过的最大号」
--     就可以收工；扫到的都把 `MDQ.poolSeen` 顶上去（这样下次才知道该扫到哪）。
MDQ.hideFrom = function(from)
  local n = 0
  local lo = tonumber(from) or 1
  if lo < 1 then lo = 1 end
  for i = lo, MDQ.poolMax do
    local t = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
    if t ~= nil then
      pcall(t.Hide, t)
      -- ★1.75.54：藏了就**作废那一格的写前比对**（否则下次要显示它时会被判「没变」而不 Show ⇒ 缺块）
      if MDQ.slot[i] ~= nil then MDQ.slot[i].shown = false end
      n = n + 1
      if i > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = i end
    elseif i > (tonumber(MDQ.poolSeen) or 0) then
      break
    end
  end
  return n
end

-- ★★★1.75.52 六改 b（用户真机报障：「**删完之后数据库查询出来的层有没添加进去，现在全都是空白的**」）：
--   **表查找 = 单一来源 + 大小写不敏感**：`GetMapInfo()` 的图名与表键**可能大小写不一致** ⇒
--   直接 `tbl[file]` 取不到就会「一片都不画」，再叠加「原生全藏」= **整张图空白**。
--   这里一次性收口：精确命中 → 退**逐个键不比大小写**（53 个键，命中后按图名缓存，不每拍扫表）。
--   返回 `m（区域表）, 真键`；读不到 ⇒ nil。
MDQ.areaCache = {}
MDQ.areaOf = function(file)
  if type(file) ~= "string" or file == "" then return nil end
  local tbl = rawget(_G, "EVAL_MAP_OVERLAY_DATA")
  if type(tbl) ~= "table" then return nil end
  local m = tbl[file]
  if m ~= nil then return m, file end
  local c = MDQ.areaCache[file]
  if c ~= nil then
    if c == false then return nil end
    return c, nil
  end
  local low = string.lower(file)
  for k, v in pairs(tbl) do
    if type(k) == "string" and string.lower(k) == low then
      MDQ.areaCache[file] = v
      return v, k
    end
  end
  MDQ.areaCache[file] = false
  return nil
end

-- 只收**我们自己自建**的层（绝不碰客户端的）：表里没有这张图时用它 ——
--   「数据库没有这张图」= **无从替代** ⇒ 客户端自己的探索层**保持原样**（本项目铁律：拿不到证据就一个字节都不碰）。
MDQ.hideOwnFrom = function(from)
  local n = 0
  local lo = tonumber(from) or 1
  if lo < 1 then lo = 1 end
  for i = lo, MDQ.poolMax do
    local t = MDQ.own[i]
    if t ~= nil then
      pcall(t.Hide, t)
      if MDQ.slot[i] ~= nil then MDQ.slot[i].shown = false end
      n = n + 1
      if i > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = i end
    end
  end
  return n
end

-- 全渲染当前图（**纯写**：贴图/UV/尺寸/位置全部由表现算；不读也不记任何原值）。
--   ★`k` = **当前倍率**（`MDQ.kLive` 现读：当前缩放级别 ÷ 表值）—— 表值 × k 才是这一拍该写的逻辑几何。
--     写表值原样（k=1）只在「引擎真值 = 表值」时成立，**不是**一条可以写死的规则。
--   返回 块数, 区域数, 表里有没有这张图, 是否渲完整, 原因, 客户端既有层数, 新加层数
--   ★`force = true` ⇒ **忽略写前比对，整批重写**（★1.75.54b：**节流那一拍必须这样**）：
--     我们复用的是**客户端自己的** `WorldMapOverlay<n>` 池位纹理，客户端会在我们写完之后**自己再摆一次**
--     （首次开图尤其明显）⇒ 只靠比对会判「没变⇒跳过」⇒ 客户端那套（缩放不对的）几何留在屏幕上
--     = 用户报的「**首次地图打开客户端自身的贴图缩放异常**」。⇒ 重申语义不能省，只在**逐帧**那条路用比对省。
MDQ.render = function(file, k, force)
  k = tonumber(k) or 1
  if k <= 0 then k = 1 end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then
    MDQ.lastRenderN = 0
    return 0, 0, false, true, "没有 WorldMapDetailFrame", 0, 0
  end
  local m = MDQ.areaOf(file)   -- ★六改 b：表查找单一来源（大小写不敏感）
  MDQ.newN = 0
  -- ★★★1.75.52 六改 c：**本拍我们真正写过的那批对象**（`wroteObj`）—— 「接管守护」的安全底线：
  --   守护只许藏「本拍**没**写过、名字又属池位族」的东西；**一个都没认出来 ⇒ 判不出 ⇒ 一个字节都不碰**。
  --   真机日志取证（`/ehm mapfit 残留` 落盘）：`渲染 22 块（客户端既有 0 ｜ 新加 22）` 与
  --   `守护：藏原生 22 ｜ 枚举池位 22` **同时出现** ⇒ 枚举里那 22 个不是我们画的（我们画的没被枚举到
  --   或身份每拍都变）⇒ 旧写法会把它们当原生全藏，等于把我们刚画的一起藏掉 = **整张空白图**。
  MDQ.wroteObj = {}
  MDQ.lastW, MDQ.lastH, MDQ.lastArea, MDQ.lastTex = nil, nil, nil, nil
  if type(m) ~= "table" then
    -- ★★★1.75.52 六改 b：**表里没有这张图 ⇒ 只收我们自建的那几层，客户端自己的探索层保持原样**
    --   （用户真机报障：「删完之后数据库查询出来的层有没添加进去，现在全都是空白的」——
    --    数据库没有这张图时**无从替代**，把原生全藏只会得到一片空白；
    --    本项目铁律「拿不到证据就一个字节都不碰」。）
    MDQ.lastRenderN = 0
    local hid = MDQ.hideOwnFrom(1)
    return 0, 0, false, true,
      ("本图不在 S_WorldMap 表里（数据库没有这张图 ⇒ 客户端自己的探索层**保持原样**；只收起我们自建的 " .. tostring(hid) .. " 层）"), 0, 0
  end
  local areas = {}
  for a in pairs(m) do table.insert(areas, a) end
  table.sort(areas)                 -- ★顺序必须确定（同一张图每次渲染的层序一致，便于逐层对照取证）
  local n, nArea, full = 0, 0, true
  local nExist, fail = 0, nil
  MDQ.wroteN, MDQ.skipN = 0, 0   -- ★1.75.54：本拍真发了几次写 / 因没变跳过了几块（取证 + 安全阀判据）
  for _, a in ipairs(areas) do
    local rec = m[a]
    local total = MDQ.tiles(rec and rec[1], rec and rec[2])
    if total > 0 then
      nArea = nArea + 1
      for t = 1, total do
        if n >= MDQ.poolMax then full = false fail = "max" break end
        local pw, ph, ox, oy = MDQ.expectRect(rec, t)
        if pw then
          local tex, how = MDQ.texAt(n + 1)
          if tex == nil then full = false fail = (how or "create_failed") break end
          if how == "existing" then nExist = nExist + 1 end
          n = n + 1
          MDQ.wroteObj[tex] = true   -- ★六改 c：这一拍我们写过它（守护的「不许藏」名单）
          -- ★★★1.75.54 写前比对：**内容一模一样就一个 `Set*` 都不发**。
          --   比对项 = 对象 + 地图 + 区域 + 块号 + 倍率 + 当前是否显示中（`shown` 被 hideFrom/release 清过）。
          --   ★**不建字符串**（不调 `texPath`）—— 逐帧重申这条路上每块一次 `string.format` 就是纯浪费。
          local sg = MDQ.slot[n]
          if (not force) and sg ~= nil and sg.tex == tex and sg.shown == true and sg.k == k
            and sg.file == file and sg.area == a and sg.tile == t then
            MDQ.skipN = MDQ.skipN + 1
          else
            local fdw, fdh = MDQ.fileDim(pw), MDQ.fileDim(ph)
            pcall(tex.SetTexture, tex, MDQ.texPath(file, a, t))
            pcall(tex.SetTexCoord, tex, 0, pw / fdw, 0, ph / fdh)
            pcall(tex.SetWidth, tex, pw * k)
            pcall(tex.SetHeight, tex, ph * k)
            pcall(tex.ClearAllPoints, tex)
            pcall(tex.SetPoint, tex, "TOPLEFT", fr, "TOPLEFT", ox * k, -(oy * k))
            pcall(tex.Show, tex)
            MDQ.slot[n] = { tex = tex, file = file, area = a, tile = t, k = k, shown = true }
            MDQ.wroteN = MDQ.wroteN + 1
          end
          if MDQ.lastW == nil then
            MDQ.lastW, MDQ.lastH = pw * k, ph * k   -- ★**写进去的**（自证与播报都按它说）
            MDQ.lastTw, MDQ.lastTh = pw, ph         -- ★表值（播报里「表 X ⇒ 写 Y」两个都摊开）
            MDQ.lastTox, MDQ.lastToy = ox, oy
            MDQ.lastK = k
            MDQ.lastArea = a
            MDQ.lastTex = tex      -- ★自证读这一张（**我们真正写的那张**；可能是我们自己补建的匿名纹理）
          end
        end
      end
    end
    if not full then break end
  end
  -- 收尾：这一轮没用到的池位全部 Hide（客户端自己的残留层也在里面 —— 「忽略内置探索纹理」）
  MDQ.hideFrom(n + 1)
  MDQ.lastRenderN = n   -- ★六改 b：本拍真的画出了几块（「接管守护」拿它判「有没有东西可替代」）
  local why = nil
  if not full then
    why = (fail == "max")
      and ("纹理池上限 " .. MDQ.poolMax .. " 已满（已渲染 " .. n .. " 块 ⇒ 表里还有区域没画出来）")
      or ("**本客户端建不出新图层**（CreateTexture 失败，已渲染 " .. n .. " 块）")
  end
  return n, nArea, true, full, why, nExist, (tonumber(MDQ.newN) or 0)
end

-- 把**我们自己补建**的层收起来（Hide）—— WoW 1.12 **没有销毁纹理的 API**（创建即常驻），所以只能藏：
--   藏了之后它们 `IsShown()==false` ⇒ 任何「按本图在用挑层」的逻辑都**不会**再把它们当成客户端的层
--   去抓原值（否则我们会把自己画的几何当原值再折一遍，越折越大）。
--   ★幂等；`MDQ.own`/`made` 一起清（下次要用会重新按需补建）。
MDQ.release = function(why)
  -- ★★★1.75.52 六改：先把「接管守护」藏过的**客户端原生层**全部 Show 还回（绝不永久藏）——
  --   调在这里 ⇒ 三条路（关开关 / 还原·关功能 / 任何收层）**天然全覆盖**，不靠人去记全调用点。
  pcall(MDQ.holdShowAll, tostring(why))
  local n = 0
  for k, t in pairs(MDQ.own or {}) do
    if t ~= nil then pcall(t.Hide, t) n = n + 1 end
    MDQ.ownSet[t] = nil
    MDQ.own[k] = nil
  end
  for nm in pairs(MDQ.made or {}) do MDQ.made[nm] = nil end
  MDQ.slot = {}    -- ★1.75.54：收层 = 把那几层藏了 ⇒ 写前比对全部作废（下次要画会老老实实重写一遍）
  MDQ.newN = 0
  MDQ.saidMk = nil
  if n > 0 then
    pcall(mfLog, "收层（%s）：我们补建的 %d 个叠加层已 Hide（纹理不能销毁，只能藏；藏了就不再被当成客户端的层）",
      tostring(why), n)
  end
  return n
end

-- 渲染 + **写后自证**（返回 块数, 区域数, 判定文本）；`silent` = 一个字都不打（逐帧重申那条路）
--   ★`quiet` 只为与渲染节拍的调用约定对齐而保留；本档的播报节流由 `MDQ.saidMk`（每图一次）与
--     「k 变了也报一次」（缩放级别变了 = 真事件）负责。
MDQ.renderCurrent = function(es, quiet, silent, withGuard)
  local file = select(1, smMapInfo())
  if type(file) ~= "string" or file == "" then return 0, 0, "读不到当前地图文件名" end
  local m = MDQ.areaOf(file)   -- ★六改 b：与 `MDQ.holdN` / `MDQ.render` 同一个表查找（大小写不敏感）
  -- ★★★1.75.53（用户：「插件要绝对独立…不然发布上去别人又可能找不到贴图」）：**贴图准入** ——
  --   表里有这张图，但「自带 media 那一份」与「客户端自带的 Interface\WorldMap 那一份」**都加载不出来**
  --   ⇒ **这一张图一帧都不接管**（不渲染、不藏原生、不建层），并且把之前藏过的原生层**当场还回**。
  --   依据 = 本项目铁律「拿不到证据就一个字节都不碰」：宁可保持客户端原样，也绝不画出一片空白图。
  if type(m) == "table" and MDQ.srcOf(file) == "none" then
    pcall(MDQ.release, "本图贴图加载不出来")   -- 把上一张图藏过的原生层与本图自建的层都还回/收起
    MDQ.lastRender = { map = file, n = 0, areas = 0, inTbl = true, full = false, k = 1, src = "none",
      why = "本应用加载不出这批贴图（自带 media\\WorldMap 与客户端 Interface\\WorldMap 都没有）" }
    if type(MDQ.noTexSaid) ~= "table" then MDQ.noTexSaid = {} end
    if not MDQ.noTexSaid[file] then
      MDQ.noTexSaid[file] = true
      pcall(smFitSay, "打开世界迷雾：地图=%s ｜ 本客户端**加载不出**这批探索层贴图"
        .. "（`media\\WorldMap\\%s\\…` 与 `Interface\\WorldMap\\%s\\…` 两份都探不到）"
        .. "⇒ **这一张图不接管**（客户端自己的探索层保持原样；不渲染、不藏原生）。体检：/ehm mapfit 贴图",
        tostring(file), tostring(file), tostring(file))
    end
    return 0, 0, "本图贴图加载不出来（不接管）"
  end
  -- ★★★1.75.51（用户：「缩放要根据当前缩放级别和数据库实时计算」）：倍率**现读**，不留常数。
  local k, kSrc = 1, "表里没有这张图（不渲染）"
  if type(m) == "table" then k, kSrc = MDQ.kLive(file, m, es) end
  -- ★1.75.54b：**节流那一拍强制整批重写**（`force = withGuard ~= false`）—— 客户端会在我们写完之后自己
  --   再摆一次它那批池位纹理（首次开图尤其明显），只靠「写前比对」会跳过重申 ⇒ 客户端那套缩放不对的
  --   几何留在屏上（用户报的「首次地图打开客户端自身的贴图缩放异常」）。逐帧那条 silent 路才用比对省开销。
  local n, nArea, inTbl, full, why, nExist, nNew = MDQ.render(file, k, withGuard ~= false)
  -- ★六改 b：把本拍的渲染账留在 `MDQ` 上（只读体检 `/ehm mapfit 残留` 直接摊出来 ⇒
  --   「数据库查出来的层到底加进去没有」不再靠猜）
  MDQ.lastRender = { map = file, n = n, areas = nArea, inTbl = inTbl, full = full, why = why, k = k }
  -- ★★★1.75.52 六改：**接管守护**与渲染**同拍**（换图/开图爆发窗内逐帧重申，之后 0.3s 一拍）——
  --   藏「客户端原生层」+ 数量守护（序号超出本图应有块数的池位一律藏）+ 存在性守护（我们自建的块被藏就复位）。
  --   ★必须排在 `MDQ.render` **之后**：渲染先写/Show 我们自建的块，守护这一拍才判得出「谁是我们自建的」。
  -- ★★★1.75.54：**逐帧重申那条 silent 路径不跑护守**（原写法每帧都跑 `holdTick` ⇒ 每帧一次
  --   `GetRegions()` + 逐 region `GetName()` 的字符串风暴，地区一多直接把帧率吃掉）。
  --   护守按**节流节拍**跑（爆发窗 0.1s / 稳态 0.3s）足够 —— 客户端把原生层 Show 回来时，
  --   最迟 0.3s 就会被再藏一次，肉眼看不到。
  local _t0 = (type(GetTime) == "function") and GetTime() or 0
  local hHid, hBack, hSeen, hWant, hAgain = 0, 0, 0, 0, 0
  if withGuard ~= false then
    hHid, hBack, hSeen, hWant, hAgain = MDQ.holdTick(file)
  end
  -- ★★★1.75.54 **安全阀**：单拍太慢 ⇒ **降档**（少重申，绝不卡死）+ 如实出声一次。
  --   为什么会有慢拍：地区多 ⇒ 块多（每块一次写）+ 客户端原生层多（护守要逐个判）。
  --   判据 = 单拍 > `MDQ.SLOW_MS`，或连续 3 拍 > `MDQ.SLOW_WARN_MS`。
  local _ms = ((type(GetTime) == "function") and (GetTime() - _t0) or 0) * 1000
  MDQ.perfMs = _ms
  if _ms > (tonumber(MDQ.SLOW_WARN_MS) or 6) then
    MDQ.perfSlowN = (tonumber(MDQ.perfSlowN) or 0) + 1
  else
    MDQ.perfSlowN = 0
  end
  local ring = MDQ.perfRing
  if type(ring) == "table" then
    table.insert(ring, { ms = _ms, wrote = tonumber(MDQ.wroteN) or 0, skip = tonumber(MDQ.skipN) or 0,
      n = n, seen = tonumber(hSeen) or 0, k = k })
    while table.getn(ring) > (tonumber(MDQ.PERF_RING_MAX) or 12) do table.remove(ring, 1) end
  end
  if (not MDQ.perfGuard) and (_ms > (tonumber(MDQ.SLOW_MS) or 12)
      or (tonumber(MDQ.perfSlowN) or 0) >= 3) then
    MDQ.perfGuard = true
    pcall(smFitSay, "打开世界迷雾：本拍耗时 **%.0f ms**（地图=%s ｜ %d 块 ｜ 客户端叠加层 %d 条）"
      .. "⇒ 已**自动降档**：逐帧重申改成 0.5s 一拍（护守照旧每拍查数量/存在性；功能不受影响）。"
      .. "取证：/ehm mapfit perf", _ms, tostring(file), n, tonumber(hSeen) or 0)
    pcall(mfLog, "[perf] 降档：%.1f ms ｜ %s ｜ %d 块 ｜ 写 %d ｜ 跳过 %d",
      _ms, tostring(file), n, tonumber(MDQ.wroteN) or 0, tonumber(MDQ.skipN) or 0)
  end
  -- 写后自证：读回**我们真正写的那张**第一块（可能是客户端原有的池位，也可能是我们自己补建的匿名纹理）
  --   两种已知口径都认（读回 = 写入值 / 读回 = 写入值 × es）—— 都对不上就如实说「判不出」。
  local verdict = "（没渲染出任何块）"
  local t1 = MDQ.lastTex
  if n > 0 and MDQ.lastW and t1 ~= nil and type(t1.GetWidth) == "function" then
    local okw, v = pcall(t1.GetWidth, t1)
    local lw = (okw and tonumber(v)) and tonumber(v) or nil
    local e = tonumber(es) or 1
    if lw == nil then
      verdict = string.format("写入 %.1f ⇒ 读回读不到（判不出）", MDQ.lastW)
    elseif math.abs(lw - MDQ.lastW) <= 0.6 then
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **生效**（读回=写入值）", MDQ.lastW, lw)
    elseif math.abs(lw - MDQ.lastW * e) <= 0.6 then
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **生效**（读回=写入值×es %.2f）", MDQ.lastW, lw, e)
    else
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **判不出/没接受**（既不是写入值，也不是 ×es %.2f）", MDQ.lastW, lw, e)
    end
  end
  if silent then return n, nArea, verdict end  -- 逐帧重申那条路：一个字都不打（连取证环也不进）
  local mk = smMapKey() or file
  -- 播报门 = **每图一次** + **k 变了再报一次**（用户在缩放地图 ⇒ 倍率真的变了，值得一行）
  local kChg = (MDQ.lastKSaid == nil) or (math.abs((tonumber(MDQ.lastKSaid) or 0) - k) > 0.03)
  if MDQ.saidMk ~= mk or kChg then
    MDQ.saidMk, MDQ.lastKSaid = mk, k
    local line = string.format("打开世界迷雾：地图=%s ｜ 表里 %d 区 ⇒ 渲染 %d 块（客户端既有 %d ｜ 新加 %d）"
      .. "｜ 倍率 k=%.3f（%s）｜ 外框 es=%.3f ｜ 首块=%s 表 %.0fx%.0f @%.0f,%.0f ⇒ 写 %.0fx%.0f @%.0f,%.0f%s",
      tostring(file), nArea, n, tonumber(nExist) or 0, tonumber(nNew) or 0,
      k, tostring(kSrc), tonumber(es) or 1,
      tostring(MDQ.lastArea or "?"), tonumber(MDQ.lastTw) or 0, tonumber(MDQ.lastTh) or 0,
      tonumber(MDQ.lastTox) or 0, tonumber(MDQ.lastToy) or 0,
      tonumber(MDQ.lastW) or 0, tonumber(MDQ.lastH) or 0,
      (tonumber(MDQ.lastTox) or 0) * k, -((tonumber(MDQ.lastToy) or 0) * k),
      ((why and (" ｜★" .. why)) or "")
      -- ★1.75.52 六改：守护的三个数字（数量/存在性）摊在**同一行**（用户点名要「数量、存在性都要检查」）
      .. string.format(" ｜ 守护：藏原生 %d（又冒出来再藏 %d）｜ 复位我们自建 %d ｜ 枚举池位 %d（认出我们画的 %d）｜ 本图应有 %d 块",
        tonumber(hHid) or 0, tonumber(hAgain) or 0, tonumber(hBack) or 0, tonumber(hSeen) or 0,
        tonumber(MDQ.holdStat.ours) or 0, tonumber(hWant) or 0))
    pcall(mfLog, "%s ｜ 自证：%s", line, verdict)
    -- ★「真出问题必须出声」（本项目判据）：本图不在表里 / 一块都没渲 / 渲不完整 / 自证判不出 / 倍率判不出 ⇒ 常开出口上屏；
    --   正常的成功行走**详细档**（用户：「清理之前调试的一些日志」）—— 全量永远在 mapFitTrace 取证环里。
    local prob = (not inTbl) or (not full) or (n == 0)
      or (string.find(verdict, "判不出", 1, true) ~= nil)
      or (string.find(kSrc, "判不出", 1, true) ~= nil)
    if prob then
      smFitSay("%s ｜ 自证：%s", line, verdict)
    else
      smFitSayV("%s ｜ 自证：%s", line, verdict)
    end
  end
  return n, nArea, verdict
end
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
MDQ.staleLevel = function(file)
  if type(GetCurrentMapZone) == "function" then
    local okz, z = pcall(GetCurrentMapZone)
    if okz and tonumber(z) ~= nil then
      if tonumber(z) == 0 then return true, "GetCurrentMapZone=0" end
      return false, string.format("GetCurrentMapZone=%d", tonumber(z))
    end
  end
  local tbl = rawget(_G, "EVAL_MAP_OVERLAY_DATA")
  if type(tbl) == "table" then
    if type(file) == "string" and file ~= "" and tbl[file] ~= nil then
      return false, "S_WorldMap 表里有这张图（区域图）"
    end
    return true, "S_WorldMap 表里没有这张图（大陆/世界/城市级）"
  end
  return false, "判不出（GetCurrentMapZone 与 S_WorldMap 表都读不到）"
end

-- ★「藏了哪些纹理」记进**有界落盘环**（`SM_CFG.staleLog`，最新在前、最多 `MDQ.STALE_LOG_MAX` 条）：
--   用户要的就是「把哪些纹理隐藏了记下来」；★只上屏的日志 `/reload` 后就没了、事后也没法取证
--   （本项目纪律：探针/判定的**原话必须落盘**，否则用户跑一趟等于白跑）。
MDQ.staleLogPut = function(line)
  if type(SM_CFG) ~= "table" then return 0 end
  local t = SM_CFG.staleLog
  if type(t) ~= "table" then t = {} SM_CFG.staleLog = t end
  table.insert(t, 1, tostring(line))
  local n = table.getn(t)
  while n > MDQ.STALE_LOG_MAX do t[n] = nil n = n - 1 end
  return table.getn(t)
end

-- 读落盘环（最新在前，最多 max 条）
MDQ.staleLogGet = function(max)
  local t = (type(SM_CFG) == "table") and SM_CFG.staleLog or nil
  if type(t) ~= "table" then return {} end
  local out = {}
  local lim = math.min(tonumber(max) or MDQ.STALE_LOG_MAX, table.getn(t))
  for i = 1, lim do out[i] = tostring(t[i]) end
  return out
end

-- 藏账的层名清单（播报 / 体检用）：`WorldMapOverlay1、WorldMapOverlay3…（共 N 个）`
MDQ.staleNames = function(max)
  local names = {}
  for _, rec in pairs(MDQ.staleHid) do
    table.insert(names, tostring(rec and rec.name or "?"))
  end
  table.sort(names)
  local n = table.getn(names)
  if n == 0 then return "（无）" end
  local lim = math.min(tonumber(max) or 8, n)
  local head = {}
  for i = 1, lim do head[i] = names[i] end
  local s = table.concat(head, "、")
  if n > lim then s = s .. "…" end
  return s .. string.format("（共 %d 个）", n)
end

-- 开关真值（唯一入口）：`SM_CFG.staleClean` —— nil = **默认开**（用户要的就是「别让不属这张图的贴图留在图上」）；
--   显式 false = 关（关掉零动作：不再新藏 + 当场把藏账里的层全部还回）。
MDQ.staleOn = function()
  return SM_CFG.staleClean ~= false
end

-- 名字像不像「客户端叠加层池位」：**按前缀 `WorldMapOverlay` 认**（DebugBox 图层树里那批就是 `WorldMapOverlayN`）。
--   ★★★1.75.52 四改（用户原话就一个词：「**WorldMapOverlayN**」）⇒ 判据从「严格数字后缀」**放宽成前缀 `WorldMapOverlay*`**：
--     只认数字后缀的话，真机上若出现字母/其它后缀（`WorldMapOverlayN` 这种写法）就**一条都认不出**，
--     而且是**静默失效**（一个字节都不碰、图上残留照旧）—— 这正是本项目最怕的那种坑。
--   ★仍然只是**名字证据**：底图瓦片 `WorldMapDetailTile*`、匿名纹理（`GetName()` 读不到）照样**一个字都不碰**。
MDQ.stalePoolName = function(o)
  local nm = string.lower(tostring(frameName(o) or ""))
  return (nm ~= "" and string.find(nm, "worldmapoverlay", 1, true) == 1)
end

-- 世界地图贴图路径里的**图名段**：`…\WorldMap\<图名>\…`（`/` 与 `\` 都认；大小写不敏感；容忍 `/Game/Interface/` 前缀）
--   ★返回 nil = **判不出**（不是世界地图贴图 / 路径读不到）⇒ 调用方**一律不碰**（没证据不动手，本项目铁律）。
MDQ.staleSeg = function(path)
  local s = string.lower(tostring(path or ""))
  if s == "" then return nil end
  s = string.gsub(s, "/", "\\")
  local i = string.find(s, "\\worldmap\\", 1, true)
  if i == nil then
    if string.sub(s, 1, 9) == "worldmap\\" then i = 0 else return nil end
  end
  local seg = string.match(string.sub(s, i + 10), "^([^\\]+)")
  if seg == nil or seg == "" then return nil end
  return seg
end

-- 路径相等（大小写 + 分隔符都不敏感；全长相等 或「末段文件名」相等都算）—— 与引擎自报的叠加层路径比对用
--   ★分隔符必须归一：本客户端 `GetTexture()` 报反斜杠，而 `GetMapOverlayInfo()` 可能报 `/Game/Interface/…` 正斜杠形态
--     （追踪图标那条已实测是这个形态）⇒ 不归一就会「明明是同一张图却判成不在清单里」。
MDQ.samePath = function(a, b)
  local x = string.lower(tostring(a or ""))
  local y = string.lower(tostring(b or ""))
  if x == "" or y == "" then return false end
  x, y = string.gsub(x, "/", "\\"), string.gsub(y, "/", "\\")
  if x == y then return true end
  local lx, ly = string.match(x, "([^\\]+)$"), string.match(y, "([^\\]+)$")
  return (lx ~= nil and lx == ly)
end

-- 引擎自报的叠加层路径清单（本图这一拍的真值）；读不到 ⇒ 空表（★空表 = 引擎说「本图没有叠加层」，
--   这时任何「路径属于别的图」的池位都必是残留 —— 与 1.75.45d「自报 0 条 ⇒ 没有可适配的层」同口径）。
MDQ.staleEngineList = function()
  local want = {}
  local n = tonumber(smNumOverlays()) or 0
  for i = 1, n do
    local okg, nm = pcall(function() return GetMapOverlayInfo(i) end)
    if okg and type(nm) == "string" and nm ~= "" then table.insert(want, nm) end
  end
  return want, n
end

-- 藏账条数
MDQ.staleLedgerN = function()
  local c = 0
  for _ in pairs(MDQ.staleHid) do c = c + 1 end
  return c
end

-- ★★★1.75.52 三改（用户看了 DebugBox 图层树后的定案，原话：「**非区域地图 就将 WorldMapOverlay 隐藏了就可以**」）
--   ⇒ 规则**简化成两条**（不再看贴图路径、不再比引擎清单 —— 那两条只留在只读体检里当诊断）：
--     · **非区域地图**（大陆 / 世界级，`MDQ.staleLevel` = true）⇒ 把 `WorldMapOverlay<n>` 池位**全部 `Hide`**；
--     · **区域地图**（`GetCurrentMapZone() > 0` / 表里有这张图）⇒ 把我们藏过的**全部 `Show` 还回**
--       （这一级客户端要用这批池位画本图的探索层；★**不还回就是永久窟窿** —— 这条是本次改动的第一判据）。
--   ★纪律不变：**只 `Hide`/`Show`**，绝不 `SetTexture`、绝不动 UV、绝不改几何；
--     **名字不合 `WorldMapOverlay*` 的对象（底图瓦片 `WorldMapDetailTile*` / 匿名纹理）一个字节都不碰**。
--   ★**藏了哪几条记名 + 落盘**（`SM_CFG.staleLog` 有界 40）—— 用户 1.75.52 二改点名要的那一条。
--   ★返回 本轮新藏 N, 本轮还回 M, 看过的池位 k, 当前图名, 藏账条数, 级别依据
MDQ.staleTick = function()
  local fileRaw = tostring(select(1, smMapInfo()) or "")
  local want = string.lower(fileRaw)
  local ledger0 = MDQ.staleLedgerN()
  if want == "" then return 0, 0, 0, "?", ledger0, "读不到地图名" end
  local lvl, lvlWhy = MDQ.staleLevel(fileRaw)
  -- ★★★1.75.52 五改（用户真机定案的那条**触发条件**）：「**在切换到某个图、如果检索不到目标地图数据的情况下，
  --   会将刚开（上一张）地图的默认纹理直接显示在这个地图上**，导致地图错乱 —— 世界地图 / 板块地图 /
  --   **某些没有探索层数据的地图**都是相同问题」。
  --   ⇒「**本图没有探索层数据**」= 动手的信号，三条**任一**成立即可（证据从硬到软）：
  --     ① `GetNumMapOverlays() == 0` —— **引擎自报本图一条叠加层都没有**（最硬：本图压根不用这批池位
  --        ⇒ 任何还显示着的 `WorldMapOverlay*` 必是上一张图的残留）★这一条正是用户描述的那个场景；
  --     ② **非区域地图**（世界/板块级，用户前一条定案：「非区域地图就将 WorldMapOverlay 隐藏了就可以」）；
  --     ③ 判不出级别且引擎也读不到 ⇒ 走第 ①/② 的 false 分支（**不动手**，本项目铁律）。
  --   ★反之：**本图有数据**（区域图 且 引擎自报 ≥1 条）⇒ **把我们藏过的还回**（那一级客户端要自己摆）。
  --     ★自愈性：引擎的 0 条若只是**尚未摆版式**的瞬态，下一拍它报 ≥1 ⇒ 规则翻回「还回」⇒ 不会留窟窿。
  local engineN = select(2, MDQ.staleEngineList())
  engineN = tonumber(engineN) or 0
  -- ★★★1.75.52 六改 c：**替代开关开着、且本图在表里 ⇒ 残留清理整段让位**（可见性归「接管守护」：
  --   那一档客户端原生层一律要藏、还要按表自行添加）—— 两套规则同时动手只会互相打架（藏了又被还回）。
  --   ★**只在「本图在表里」时让位**（用户要求「全图默认开」之后这更重要）：表里没有这张图的图
  --   （大陆 / 世界 / 城市）**接管守护本来就不动手**，那时残留清理必须继续干活，否则两档都失效。
  if MDQ.swm() and MDQ.holdN(fileRaw) > 0 then
    return 0, 0, 0, want, ledger0, "替代开关已开（本图在表里 ⇒ 可见性归「接管守护」）"
  end
  local noData = (lvl == true) or (engineN == 0)
  local whyLvl = lvl and ("非区域地图：" .. tostring(lvlWhy))
    or (engineN == 0 and "引擎自报本图 0 条叠加层（= 本图没有探索层数据）")
    or ("本图有探索层数据（引擎自报 " .. tostring(engineN) .. " 条）")
  local fr = _G["WorldMapDetailFrame"]
  local okFr = (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function"
  -- ① 本图**有**数据 ⇒ **还回**（绝不把「藏」的状态带过去；幂等：账空了就什么都不做）
  if not noData then
    local back = 0
    if ledger0 > 0 then back = MDQ.staleShowAll("本图有探索层数据（" .. tostring(whyLvl) .. "）") end
    return 0, back, 0, want, MDQ.staleLedgerN(), whyLvl
  end
  -- ② 本图没有探索层数据 ⇒ 把叠加层池位**全部藏掉**（空闲时也允许新藏：客户端随后又 Show 出来就再藏，残留不许回潮）
  if not okFr then return 0, 0, 0, want, ledger0, whyLvl end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then return 0, 0, 0, want, ledger0, whyLvl end
  local hid, seen, nTex = 0, 0, 0
  local samples = {}
  for _, o in ipairs(regs) do
    -- 唯一的证据 = **名字**是叠加层池位；名字不合（底图瓦片 / 匿名装饰）⇒ 一个字节都不碰
    if o ~= nil then
      nTex = nTex + 1
      if nTex <= 6 then
        local nmS = frameName(o)
        table.insert(samples, (nmS ~= "" and nmS ~= "?") and nmS or "(无名)")
      end
      if MDQ.stalePoolName(o) then
        seen = seen + 1
        local oks, shown = pcall(o.IsShown, o)
        if oks and shown == true then
          local okh = pcall(o.Hide, o)
          if okh then
            hid = hid + 1
            -- ★账上没有 ⇒ 第一次藏：记名 + 落盘；★账上已有、却又是显示着的 ⇒ **客户端又把它 Show 出来了**，
            --   照样再藏一次（残留不许回潮），但**不重复记名**（免得一次开图刷满 40 条环）。
            if MDQ.staleHid[o] == nil then
              local nm = frameName(o)
              local okp, path = pcall(o.GetTexture, o)
              if not okp then path = nil end
              MDQ.staleHid[o] = { name = nm, path = tostring(path) }
              MDQ.staleLogPut(string.format("藏：地图=%s（%s）｜ %s ｜ 贴图=%s",
                tostring(want), tostring(whyLvl), tostring(nm), tostring(path)))
            end
          end
        end
      end
    end
  end
  -- ★★★1.75.52 四改：**一个池位名都没认出**时如实出声（否则「名字判据与真机对不上」会变成**静默失效** ——
  --   一个字节都不碰、图上残留照旧，而用户以为修好了）。样本名一起给出来，便于一眼看出真机叫什么。
  if nTex > 0 and seen == 0 then
    MDQ.staleNoPoolSay = (tonumber(MDQ.staleNoPoolSay) or 0) + 1
    if MDQ.staleNoPoolSay <= 3 then
      pcall(mfLog, "残留图层：本图（%s）**没认出任何 WorldMapOverlay 池位**（枚举 %d 个纹理，名字样本：%s）",
        tostring(want), nTex, table.concat(samples, "、"))
    end
  end
  return hid, 0, seen, want, MDQ.staleLedgerN(), whyLvl
end

-- 把藏账里的层**当场全部还回**（关开关 / 关图 / 关模块 / 关功能时用；幂等）
MDQ.staleShowAll = function(why)
  local n = 0
  local names = {}
  for o in pairs(MDQ.staleHid) do
    pcall(o.Show, o)
    table.insert(names, tostring((MDQ.staleHid[o] or {}).name or "?"))
    MDQ.staleHid[o] = nil
    n = n + 1
  end
  if n > 0 then
    pcall(mfLog, "残留图层：把藏起来的 %d 个叠加层全部还回（%s）", n, tostring(why))
    table.sort(names)
    MDQ.staleLogPut(string.format("还回全部 %d 个（%s）：%s", n, tostring(why), table.concat(names, "、")))
  end
  return n
end

-- ★★★1.75.52 六改：**只清账、不还回**（幂等）—— 用在「替代开关刚被打开」那一拍：从这一刻起可见性由
--   「接管守护」负责（客户端原生层本来就要**全藏**）⇒ 若走 `staleShowAll` 会先闪一下再藏回去。
MDQ.staleForget = function(why)
  local n = 0
  for o in pairs(MDQ.staleHid) do
    MDQ.staleHid[o] = nil
    n = n + 1
  end
  if n > 0 then
    pcall(mfLog, "残留图层：账上 %d 个叠加层交给「接管守护」接管（替代开关已开，%s）", n, tostring(why))
    MDQ.staleLogPut(string.format("转交接管守护 %d 个（%s）", n, tostring(why)))
  end
  return n
end

-- ★★★1.75.52 **只读**取证：本帧每个 Texture 的「名字 / 贴图 / 图名段 / 结论」，一个字节都不写（零副作用）。
--   ★这是「路径口径到底对不对」的唯一真机判据：**在大陆图（有残留）时跑**，就能看清残留那几条的贴图属于哪张图；
--     瓦片即使路径不符也只在这里**列出来**（现行实现不藏它们）。
MDQ.staleProbe = function()
  local out = {}
  local wantRaw = tostring(select(1, smMapInfo()) or "?")
  local want = wantRaw
  local wl = string.lower(want)
  local lvl, lvlWhy = MDQ.staleLevel(wantRaw)
  local elist, en = MDQ.staleEngineList()
  en = tonumber(en) or 0
  -- ★五改：**本图没有探索层数据**（非区域 或 引擎自报 0 条）⇒ 本档动手藏；有数据 ⇒ 不藏（并还回）
  local noData = (lvl == true) or (en == 0)
  local fr = _G["WorldMapDetailFrame"]
  local nAll, nPool, nHide, nTileMis, nUnk, nEng = 0, 0, 0, 0, 0, 0
  local lines = {}
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if okr then
      for _, o in ipairs(regs) do
        if o ~= nil and type(o.GetTexture) == "function" then
          nAll = nAll + 1
          local okp, path = pcall(o.GetTexture, o)
          if not okp then path = nil end
          local seg = MDQ.staleSeg(path)
          local nm = frameName(o)
          local isPool = MDQ.stalePoolName(o)
          local isTile = (string.sub(nm, 1, 18) == "WorldMapDetailTile")
          local inEngine = false
          if type(path) == "string" and path ~= "" then
            for wi = 1, table.getn(elist) do
              if MDQ.samePath(path, elist[wi]) then inEngine = true break end
            end
          end
          if inEngine then nEng = nEng + 1 end
          if isPool then nPool = nPool + 1 end
          local v
          if not noData then
            -- 「本图有探索层数据」：本档**不藏**（这一级客户端要用这批池位画探索层；藏账也会被全部还回）
            if isPool then
              v = "叠加层池位 ⇒ 本图**有数据**（引擎自报 " .. tostring(en) .. " 条）⇒ **不藏**"
            elseif seg == nil then
              nUnk = nUnk + 1
              v = "判不出（路径里没有 WorldMap\\<图名>\\ 段）⇒ 不碰"
            else
              v = "本图/别图（" .. seg .. "）⇒ **不碰**（不是叠加层池位）"
            end
          elseif isPool then
            nHide = nHide + 1
            v = "叠加层池位 ⇒ **藏**（" .. (lvl and "非区域地图" or "引擎自报本图 0 条叠加层 = 没有探索层数据") .. "：全藏）"
              .. ((seg ~= nil and seg ~= wl) and ("，注意它的贴图属于别图（" .. seg .. "）= 残留来源") or "")
          elseif seg == nil then
            nUnk = nUnk + 1
            v = "判不出（路径里没有 WorldMap\\<图名>\\ 段）⇒ 不碰"
          else
            if isTile then nTileMis = nTileMis + 1 end
            v = "**别图**（" .. seg .. "）⇒ **只报不藏**（不是叠加层池位；底图/瓦片绝不打洞）"
          end
          table.insert(lines, string.format("　#%d %s ｜ 贴图=%s ｜ 图名段=%s ｜ %s",
            nAll, nm, tostring(path), tostring(seg), v))
        end
      end
    end
  end
  table.insert(out, string.format(
    "残留体检：地图=%s ｜ 本图数据=%s（级别=%s ｜ 引擎自报叠加层 %d 条）｜ 枚举 Texture %d 个（叠加层池位 %d ｜ 引擎清单命中 %d）｜ "
      .. "本档要藏 %d 个 ｜ 瓦片路径不符 %d 个（只报不藏）｜ 判不出 %d 个 ｜ 藏账 %d 条",
    want, noData and "**没有探索层数据 ⇒ 叠加层全藏**" or "有探索层数据 ⇒ **不藏**（藏账全部还回）",
    tostring(lvlWhy), en, nAll, nPool, nEng, nHide, nTileMis, nUnk, MDQ.staleLedgerN()))
  for _, l in ipairs(lines) do table.insert(out, l) end
  -- ★「把哪些纹理隐藏了」= 用户点名要的那一条：当前藏账逐条 + 落盘历史（`SM_CFG.staleLog`）
  table.insert(out, string.format("残留体检·当前藏账 %d 条：%s", MDQ.staleLedgerN(), MDQ.staleNames(12)))
  local ledger = {}
  for o, rec in pairs(MDQ.staleHid) do
    table.insert(ledger, string.format("　藏账 %s ｜ 藏时的贴图=%s",
      tostring(rec and rec.name or "?"), tostring(rec and rec.path or "?")))
  end
  table.sort(ledger)
  for _, l in ipairs(ledger) do table.insert(out, l) end
  local hist = MDQ.staleLogGet(12)
  table.insert(out, string.format("残留体检·落盘历史（SM_CFG.staleLog，最多 %d 条，最新在前）%d 条：",
    MDQ.STALE_LOG_MAX, table.getn(hist)))
  if table.getn(hist) == 0 then
    table.insert(out, "　（空 —— 本档还没藏过任何纹理；/reload 后这里也会保留）")
  else
    for i = 1, table.getn(hist) do table.insert(out, "　" .. hist[i]) end
  end
  return out
end

-- ★★★1.75.52 六改（用户原话：「每次切换到一个地图、识别到地图签名的时候，对应这个地图的贴图数据库查询下有多少贴图，
--   然后删除原生的贴图数据，再自行添加。并且做好守护程序：**有可能会将超出当前贴图数据层数的数据添加回去**，
--   所以要做好守护程序 —— **数量、存在性都要检查**」）⇒ **只在「打开世界迷雾」开着时接管**（用户选的口径 B）：
--   · **数量基准 = 表**：本图应有几块由 `MDQ.holdN` 现算（与 `MDQ.render` **同一算法、同一上限** `poolMax`
--     ⇒ 全项目「本图该有几块」只有一个来源，绝不写常数）；
--   · **原生全藏**：枚举 `WorldMapDetailFrame` 的 region，凡名字属 `WorldMapOverlay*` 且**不是我们自建的**
--     （身份判定 `MDQ.ownSet`，**不看名字** —— 本客户端那批原生层的名字与我们补建的会重名）⇒ `Hide`。
--     ★1.12 **没有销毁纹理的 API** ⇒「删除原生贴图」只能靠 `Hide`（这也正是本项目「只 Hide/Show」铁律）；
--   · **数量守护**：序号**超出本图应有块数**的池位（上一张图块更多时留下的、或客户端又冒出来的）一律 `Hide`
--     ⇒ 残留不许回潮；**存在性/可见性守护**：我们自建的块（序号在本图应有块数之内）**被藏了就重新 `Show`**；
--   · **绝不永久藏**：`MDQ.holdShowAll` 把藏过的**原生**层全部还回并清账，调在 `MDQ.release` 里
--     ⇒ 关开关 / 关功能 / 关模块**三条路天然全覆盖**（另有「关图」那一拍）。
--   ★节拍 = 挂在 `MDQ.renderCurrent` 里 ⇒ 与渲染**同拍**（换图/开图爆发窗内逐帧重申，之后 0.3s 一拍）；
--   ★这里**一个字节都不写贴图 / UV / 几何**（同残留清理的三条纪律）。
MDQ.holdStat = { map = "?", want = 0, hid = 0, again = 0, reshow = 0, seen = 0, ours = 0, blind = false, at = 0 }
MDQ.holdHid = {}   -- 藏账（**只记客户端原生层**）：对象 → { name =, path =, again = }（关开关/关功能时全部还回）
MDQ.holdOrder = {} -- 藏账的**插入顺序**（超上限时把最老的放回去 ⇒ 账有界且绝不永久藏）
MDQ.HOLD_LEDGER_MAX = 600  -- ★真机日志取证：客户端每拍重建自己的池位 ⇒ 无界账一小时就攒到 3960 条

-- 池位名字里的**尾号**（`WorldMapOverlay7` → 7）；认不出（字母后缀 / 没有后缀）⇒ nil，**绝不猜**
MDQ.poolIdx = function(o)
  local nm = string.lower(frameName(o) or "")
  if string.find(nm, "worldmapoverlay", 1, true) ~= 1 then return nil end
  local d = string.match(nm, "(%d+)$")
  return d and tonumber(d) or nil
end

-- 本图**应有几块**（表推；数量口径唯一来源，与 `MDQ.render` 同一算法与同一上限）
--   ★1.75.54：**按图名缓存** —— 它每拍被 `holdTick` 与 `staleTick` 各调一次，逐拍遍历整张区域表是白费；
--   表是**载入期常量**（生成物），所以缓存安全；`MDQ.holdNCache` 只随访问过的图增长（≤ 图数）。
MDQ.holdNCache = {}
MDQ.holdN = function(file)
  local key = tostring(file or "")
  local c = MDQ.holdNCache[key]
  if c ~= nil then return c end
  local m = MDQ.areaOf(key)   -- ★六改 b：与渲染**同一个**表查找（大小写不敏感）⇒ 数量口径不会与画出来的块数打架
  if type(m) ~= "table" then MDQ.holdNCache[key] = 0 return 0 end
  local n = 0
  for _, rec in pairs(m) do
    n = n + (tonumber(MDQ.tiles(rec and rec[1], rec and rec[2])) or 0)
  end
  if n > MDQ.poolMax then n = MDQ.poolMax end
  MDQ.holdNCache[key] = n
  return n
end

-- 原生藏账条数
MDQ.holdLedgerN = function()
  local c = 0
  for _ in pairs(MDQ.holdHid) do c = c + 1 end
  return c
end

-- ★接管守护（**每拍都跑**）：藏原生 + 数量守护（超出本图块数的池位）+ 存在性守护（我们自建的块被藏就复位）
--   返回：藏了原生 N 个, 复位我们自建的 M 个, 枚举到池位 K 个, 本图应有 W 块, 「又冒出来再藏」A 次
MDQ.holdTick = function(file)
  if not MDQ.swm() then return 0, 0, 0, 0, 0 end
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    return 0, 0, 0, 0, 0
  end
  local want = MDQ.holdN(file)
  local drew = tonumber(MDQ.lastRenderN) or 0
  -- ★★★1.75.52 六改 b（用户真机报障「全都是空白的」）：**数据库里没有这张图 / 一块都没画出来**
  --   ⇒ **一个字节都不碰**（客户端的探索层保持原样）。理由两条：
  --     ① 本项目铁律「拿不到证据就一个字节都不碰」—— 不知道这张图该有什么，就没有替代依据；
  --     ② 旧写法（原生全藏 + 不自行添加）在「表里没有这张图」时 = **整张图空白**，比残留更糟。
  if want <= 0 or drew <= 0 then return 0, 0, 0, want, 0 end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then return 0, 0, 0, want, 0 end
  local hid, reshow, seen, again, oursSeen = 0, 0, 0, 0, 0
  local kills, shows = {}, {}
  -- ===== 第一趟：只**判定**，一个字节都不写 =====
  for _, o in ipairs(regs) do
    -- 唯一的证据 = **名字**属叠加层池位族；名字不合（底图瓦片 / 匿名装饰）⇒ 一个字节都不碰
    if o ~= nil and MDQ.stalePoolName(o) then
      seen = seen + 1
      -- ★六改 c：「我们画的」= 身份账 **或** 本拍真的写过它（后者不依赖对象身份跨拍稳定）
      local ours = (MDQ.ownSet[o] == true) or (MDQ.wroteObj[o] == true)
      if ours then oursSeen = oursSeen + 1 end
      local idx = MDQ.poolIdx(o)
      local oks, shown = pcall(o.IsShown, o)
      -- ★原生层**不看序号**（它就是客户端自己那套 / 上一张图的残留）；我们自建的层按**数量**判（超出即藏）
      local kill = (not ours) or (idx ~= nil and idx > want)
      if oks and shown == true and kill then
        table.insert(kills, { o = o, ours = ours })
      elseif oks and shown == false and ours and idx ~= nil and idx <= want then
        table.insert(shows, o)   -- 存在性守护：我们自建的块被藏了 ⇒ 待会儿还回来
      end
    end
  end
  -- ★★★第二趟之前的安全门（1.75.52 六改 c；真机日志取证换来的）：**枚举里一个「我们画的」都认不出**
  --   而本拍明明画出来了 ⇒ 本客户端要么把我们建的纹理排在下一次枚举里、要么对象身份每拍都换
  --   ⇒ **判不出谁是原生 ⇒ 一个字节都不碰**（旧写法会把它们当原生全藏 = 连自己画的一起藏 = 空白图）。
  --   ★出声一次（常开出口）并指明取证命令，绝不让它变成静默失效。
  if oursSeen == 0 and seen > 0 then
    MDQ.holdStat.map, MDQ.holdStat.want = tostring(file), want
    MDQ.holdStat.hid, MDQ.holdStat.again, MDQ.holdStat.reshow = 0, 0, 0
    MDQ.holdStat.seen, MDQ.holdStat.ours = seen, 0
    MDQ.holdStat.at = (type(GetTime) == "function") and GetTime() or 0
    MDQ.holdStat.blind = true
    local mkB = smMapKey() or tostring(file)
    if MDQ.holdSaidBlind ~= mkB then
      MDQ.holdSaidBlind = mkB
      pcall(smFitSay, "接管守护：地图=%s ｜ 枚举到 **%d** 个叠加层池位，但**一个都不是我们刚画的**"
        .. "（本拍画了 %d 块）⇒ **判不出谁是原生 ⇒ 一个字节都不碰**（宁可保留原生的，也绝不留空白图）。"
        .. "取证：/ehm mapfit 残留（首两行给渲染账与枚举数）",
        tostring(file), seen, drew)
    end
    return 0, 0, seen, want, 0
  end
  MDQ.holdStat.blind = false
  -- ===== 第二趟：动手（藏原生 + 数量守护），并复位被藏的我们自建的块 =====
  for _, o in ipairs(shows) do
    if pcall(o.Show, o) then reshow = reshow + 1 end
  end
  for _, it in ipairs(kills) do
    local o, ours = it.o, it.ours
    if pcall(o.Hide, o) then
      hid = hid + 1
      if not ours then
        local rec = MDQ.holdHid[o]
        if rec == nil then
          local nm = frameName(o)
          local okp, path = pcall(o.GetTexture, o)
          if not okp then path = nil end
          -- ★藏账**有界**（真机日志：一小时不到就攒到 3960 条 —— 客户端每拍重建自己的池位对象
          --   ⇒ 无界账会把内存与「关开关时逐个 Show」都拖垮）。超上限时把最老的**放回去**（绝不永久藏）。
          if MDQ.holdOrder == nil then MDQ.holdOrder = {} end
          MDQ.holdHid[o] = { name = nm, path = tostring(path), again = 0 }
          table.insert(MDQ.holdOrder, o)
          while table.getn(MDQ.holdOrder) > MDQ.HOLD_LEDGER_MAX do
            local old = table.remove(MDQ.holdOrder, 1)
            if old ~= nil and MDQ.holdHid[old] ~= nil then
              pcall(old.Show, old)     -- ★放回（绝不永久藏）
              MDQ.holdHid[old] = nil
            end
          end
          MDQ.staleLogPut(string.format("接管藏：地图=%s ｜ 客户端原生层 %s ｜ 贴图=%s",
            tostring(file), tostring(nm), tostring(path)))
        else
          rec.again = (tonumber(rec.again) or 0) + 1
          again = again + 1
          -- ★「客户端又把它 Show 出来了」= 用户报障的那条现象；每个对象最多记 3 次（环有界、不刷屏）
          if rec.again <= 3 then
            MDQ.staleLogPut(string.format("接管再藏（第 %d 次）：地图=%s ｜ 原生层 %s（客户端自己又 Show 出来了）",
              rec.again, tostring(file), tostring(rec.name)))
          end
        end
      end
    end
  end
  local st = MDQ.holdStat
  st.map, st.want = tostring(file), want
  st.hid, st.again, st.reshow, st.seen = hid, again, reshow, seen
  st.ours = oursSeen
  st.at = (type(GetTime) == "function") and GetTime() or 0
  -- ★「客户端又把它 Show 出来了」正是用户报障的那条现象 ⇒ **必须出声**（常开出口），但**每图只一次**
  --   （逐帧重申那一拍 + 客户端每次重摆都可能命中它，不节流就是刷屏）。
  if again > 0 then
    local mkA = smMapKey() or tostring(file)
    if MDQ.holdSaidAgain ~= mkA then
      MDQ.holdSaidAgain = mkA
      pcall(smFitSay, "接管守护：地图=%s ｜ 客户端又把 **%d** 个原生探索层 Show 出来了 ⇒ **已当场再藏**"
        .. "（守护每拍都查：① 数量 = 表推本图 %d 块；② 存在性 = 超出块数的池位一律藏）",
        tostring(file), again, want)
    end
  end
  return hid, reshow, seen, want, again
end

-- 把我们藏过的**客户端原生层**全部还回（关开关 / 关功能 / 关图 / 关模块；幂等）⇒「绝不永久藏」
MDQ.holdShowAll = function(why)
  local n = 0
  for o in pairs(MDQ.holdHid) do
    pcall(o.Show, o)
    MDQ.holdHid[o] = nil
    n = n + 1
  end
  MDQ.holdOrder = {}
  if n > 0 then
    pcall(mfLog, "接管守护（%s）：把藏过的 %d 个客户端原生探索层全部 Show 还回", tostring(why), n)
  end
  return n
end

-- 只读体检（`/ehm mapfit 残留` 里一并打印）：**数量**（本图应有几块）+ **存在性**（逐条：谁的 / 显示没显示 / 结论）
--   ★零副作用：只 `IsShown` / `GetTexture` / `GetRegions`，一个 `Set*` 都不发。
MDQ.holdProbe = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local okFile = (file ~= "")
  local want = MDQ.holdN(okFile and file or nil)
  local drew = tonumber(MDQ.lastRenderN) or 0
  table.insert(out, string.format(
    "接管守护（打开世界迷雾 %s）：地图=%s ｜ 表推本图应有 %d 块 ｜ "
      .. "上一次守护：藏原生 %d ｜ 又冒出来再藏 %d ｜ 我们自建被藏后复位 %d ｜ 枚举池位 %d（认出我们画的 %d）｜ 原生藏账 %d 条%s",
    MDQ.swm() and "**开**" or "关", okFile and file or "?", want,
    tonumber(MDQ.holdStat.hid) or 0, tonumber(MDQ.holdStat.again) or 0, tonumber(MDQ.holdStat.reshow) or 0,
    tonumber(MDQ.holdStat.seen) or 0, tonumber(MDQ.holdStat.ours) or 0, MDQ.holdLedgerN(),
    MDQ.holdStat.blind and "　★判不出（枚举里一个我们画的都没认出）⇒ **一个字节都不碰**" or ""))
  -- ★六改 b：再摊**本拍的渲染账**（用户报障「数据库查出来的层有没添加进去」的唯一直接答案）：
  --   渲染 N 块 / 表里 M 区 / 在不在表里 / 有没有渲完整 / 失败原因 / 现读倍率
  local rr = MDQ.lastRender
  if type(rr) == "table" then
    table.insert(out, string.format(
      "接管渲染：地图=%s ｜ 表里 %d 区 ⇒ **渲染 %d 块**（在表里=%s ｜ 渲完整=%s ｜ 倍率 k=%.3f）%s",
      tostring(rr.map or "?"), tonumber(rr.areas) or 0, tonumber(rr.n) or 0,
      rr.inTbl and "是" or "**否**", rr.full and "是" or "**否**",
      tonumber(rr.k) or 1, rr.why and (" ｜★" .. tostring(rr.why)) or ""))
  else
    table.insert(out, "接管渲染：**本会话还没渲染过**（地图关着 / 替代开关刚打开还没到一拍）")
  end
  if want <= 0 or drew <= 0 then
    table.insert(out, "　（**数据库里没有这张图 / 一块都没画出来** ⇒ 接管守护按「无从替代」处理："
      .. "客户端自己的探索层**保持原样**，一个字节都不碰 —— 不会出现空白图）")
  end
  if not MDQ.swm() then
    table.insert(out, "　（替代开关关着 ⇒ 接管守护**一个字节都不碰**；这时由「残留图层清理」那两条规则负责）")
  end
  local fr = _G["WorldMapDetailFrame"]
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if okr then
      local rows = {}
      for _, o in ipairs(regs) do
        if o ~= nil and MDQ.stalePoolName(o) then
          local ours = (MDQ.ownSet[o] == true)
          local idx = MDQ.poolIdx(o)
          local oks, shown = pcall(o.IsShown, o)
          local okp, path = pcall(o.GetTexture, o)
          if not okp then path = nil end
          local pos = (idx ~= nil) and ("#" .. tostring(idx)) or "#（认不出尾号）"
          local verdict
          if ours then
            verdict = (idx ~= nil and idx <= want) and "本图该在（被藏就复位）" or "**超出本图块数 ⇒ 藏**"
          elseif want > 0 and drew > 0 then
            verdict = "**客户端原生 ⇒ 藏**（本图有表数据，替代语义）"
          else
            verdict = "客户端原生 ⇒ **保持原样**（数据库里没有这张图 / 一块都没画出来 ⇒ 一个字节都不碰）"
          end
          table.insert(rows, string.format("　%s ｜ %s ｜ %s ｜ %s ｜ 贴图=%s ⇒ %s",
            tostring(frameName(o)), pos, ours and "我们自建" or "客户端原生",
            (oks and shown == true) and "显示中" or "已隐藏", tostring(path), verdict))
        end
      end
      table.sort(rows)
      if table.getn(rows) == 0 then
        table.insert(out, "　（本图枚举到的 region 里**没有** WorldMapOverlay* 池位）")
      else
        for _, r in ipairs(rows) do table.insert(out, r) end
      end
    end
  end
  return out
end

-- ★★★1.75.54 **性能体检**（`/ehm mapfit perf`；用户报障「开了十几个地区以后游戏会卡死」换来的取证口）：
--   ★口令是「体检」不是「只读」—— 它**真跑两拍**（与正常节拍完全相同的那条路：渲染 + 护守），会写地图层。
--   为什么这么设计：卡顿只有在**真跑**时才量得出来（离线 harness 只能数调用次数，量不到引擎真实耗时）。
--   读数同时进**有界落盘环** `SM_CFG.perfProbe`(40) ⇒ AI 读存档即可判「有没有慢拍 / 哪一拍慢 / 写了几次」。
MDQ.perfProbe = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local fr = _G["WorldMapDetailFrame"]
  local es = 1
  if fr ~= nil then
    local eff = smEffScale(fr)
    if tonumber(eff) and tonumber(eff) > 0 then es = tonumber(eff) end
  end
  local m = MDQ.areaOf(file)
  local nArea = 0
  if type(m) == "table" then for _ in pairs(m) do nArea = nArea + 1 end end
  table.insert(out, string.format("性能体检：地图=%s ｜ 表里 %d 区 / 应有 %d 块 ｜ 外框 es=%.3f ｜ 开关=%s ｜ 纹理池上限 %d",
    tostring(file), nArea, MDQ.holdN(file), es, MDQ.swm() and "开" or "关", MDQ.poolMax))
  table.insert(out, string.format("　引擎自报叠加层 %s 条（`GetNumMapOverlays`；**探索过的地区越多它越大**）",
    tostring(smNumOverlays())))
  local T = (type(GetTime) == "function") and GetTime or function() return 0 end
  local rows = {}
  for pass = 1, 2 do
    local t0 = T()
    local n1 = select(1, MDQ.renderCurrent(es, true, true, true))   -- 与正常「带护守那一拍」完全同路
    local ms = (T() - t0) * 1000
    local line = string.format("第 %d 拍：%.1f ms ｜ 渲染 %s 块 ｜ **写 %s 次** ｜ 跳过(内容没变) %s ｜ 护守：枚举 %s ｜ 藏 %s ｜ 复位 %s ｜ 认出我们画的 %s%s",
      pass, ms, tostring(n1), tostring(MDQ.wroteN or 0), tostring(MDQ.skipN or 0),
      tostring(MDQ.holdStat.seen or 0), tostring(MDQ.holdStat.hid or 0), tostring(MDQ.holdStat.reshow or 0),
      tostring(MDQ.holdStat.ours or 0), MDQ.holdStat.blind and " ｜ **盲（判不出谁是原生 ⇒ 一个字节都不碰）**" or "")
    table.insert(out, line)
    rows[#rows + 1] = line
  end
  table.insert(out, string.format("安全阀：perfGuard=%s ｜ 慢拍阈值 %d ms（连续 3 拍 > %d ms 也降档）｜ 最近 %d 拍：%s",
    tostring(MDQ.perfGuard), tonumber(MDQ.SLOW_MS) or 12, tonumber(MDQ.SLOW_WARN_MS) or 6,
    table.getn(MDQ.perfRing), (function()
      local t = {}
      for _, r in ipairs(MDQ.perfRing) do
        t[#t + 1] = string.format("%.0fms/写%d", tonumber(r.ms) or 0, tonumber(r.wrote) or 0)
      end
      return table.concat(t, " ")
    end)()))
  table.insert(out, "　★判读：**第 2 拍「写 0 次」= 写前比对生效**（稳态零写，只有换图/缩放才写）；"
    .. "若第 2 拍还在写几十次 ⇒ 有东西每拍在变（报给作者看这两行）；单拍 > 12ms ⇒ 会自动降档（逐帧重申改 0.5s 一拍）。")
  table.insert(out, "　★地区多导致叠加层多时：护守每拍要枚举全部 region（只读），这是**节流拍**才做的事（0.1s/0.3s）。")
  if type(SM_CFG) == "table" then
    if type(SM_CFG.perfProbe) ~= "table" then SM_CFG.perfProbe = {} end
    local ring = SM_CFG.perfProbe
    table.insert(ring, string.format("[%s] %s ｜ %s", date and tostring(date("%H:%M:%S")) or "?", tostring(file), table.concat(rows, " ｜ ")))
    while table.getn(ring) > 40 do table.remove(ring, 1) end
  end
  for _, l in ipairs(out) do pcall(mfLog, "[perf] %s", l) end
  return out
end

-- ★★★1.75.51（用户：「缩放大地图->设置内->添加个 S_WorldMap 贴图替代开关」）：
--   **数据源 = `MDQ.swm()`**（唯一判据入口；产品开关，落存档）：
--     · 开（**默认**）= **表驱动全渲染**（`MDQ.render`，见那一族）：不抓原值、不读本地缓存、不逐层折算 ——
--       贴图/UV/尺寸/位置全部由 S_WorldMap 表现算，客户端内置的那批探索层被逐条改写/多余的藏起来；
--     · 关 = 不再碰叠加层（1.75.52 用户定：整条「探索层适配」已摘除，关掉就是**客户端原生行为**）。
--   ★判据写法：**一律写 `MDQ.swm()`**（挂在既有 `MDQ` 表上）—— 主 chunk 有 **200 个 local 的上限**，
--     为这种一个布尔判断新增文件级 local 会把离线 harness 直接顶爆
--     （历史实测症状 `LOAD FAIL: … too many local variables (limit is 200) in main function`）。
--
-- ★★★1.75.51（用户：「清理掉本地地图签名缓存」）：**清本地缓存**的**唯一出口**（幂等；内存 + 存档老键一起清）。
--   · 存档老键四个（`mapFitOrig` 老原值 · `mapFitVer` 版本戳 · `mapFitTrace` 取证环 · `mapFitCapLog` 抓原值环）
--     —— 它们正是用户要清的「之前调试的日志」；返回清掉的**存档键个数**（0 = 本来就没有）。
--   ★挂在 `MDQ` 表上而不是新增文件级 local（同上：200 local 上限）。
MDQ.cacheClear = function(why)
  local n = 0
  if type(SM_CFG) == "table" then
    for _, k in ipairs({ "mapFitOrig", "mapFitVer", "mapFitTrace", "mapFitCapLog" }) do
      if SM_CFG[k] ~= nil then SM_CFG[k] = nil n = n + 1 end
    end
  end
  pcall(mfLog, "清缓存（%s）：存档老键 %d 个（原值/写入账那些会话内存已随探索层适配整条摘除）", tostring(why), n)
  return n
end
-- 开图侦测 tick（★挂 WorldFrame 不挂 UIParent —— 开全屏地图时 UIParent 会被隐藏，挂它下面收不到 OnUpdate）
--   ★★1.75.52（用户定：整条「探索层适配」摘除）后只剩三件事：
--     ① 黑幕瞬时窗口（开图逐帧重申藏黑幕）｜ ② 「开图保持」（透明度/缩放/居中/位置记忆）
--     ③ 「打开世界迷雾」渲染节拍 + 「残留图层清理」节拍（规则与实现都在 `MDQ.*` 里，这里只管节拍与播报）。
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
        pcall(MDQ.release, "模块已关")
        pcall(MDQ.staleShowAll, "模块已关")
        pcall(MDQ.holdShowAll, "模块已关")
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
          ST.staleUntil = ((type(GetTime) == "function") and GetTime() or 0) + MDQ.STALE_SEC
          ST.staleAt, ST.staleSaid, ST.staleSaidNoPool = -99, false, false
          ST.staleHidN, ST.staleBackN = 0, 0
        end
      end
      -- ③ 残留图层清理节拍：**只 `Hide`/`Show`**，绝不 SetTexture / 绝不动 UV / 绝不改几何（全在 `MDQ.staleTick`）
      do
        local hasLedger = false
        -- ★防御（1.75.52 真机红字换来的）：即便藏账因为任何原因没建起来，也**只退化成「没账」**，
        --   绝不让 tick 每帧抛错刷红字（`type` 判一次的成本可以忽略）。
        local hid = MDQ.staleHid
        if type(hid) == "table" then
          for _ in pairs(hid) do hasLedger = true break end
        end
        if (not MDQ.staleOn()) and hasLedger then
          pcall(MDQ.staleShowAll, "残留图层清理已关")
          hasLedger = false
        end
        if open and mkNow and MDQ.staleOn() then
          local tS = (type(GetTime) == "function") and GetTime() or 0
          local armed = (tonumber(ST.staleUntil) or 0) > tS
          local gapS = armed and MDQ.STALE_GAP or MDQ.STALE_GAP_IDLE
          if (armed or hasLedger) and ((tS - (tonumber(ST.staleAt) or -99)) >= gapS) then
            ST.staleAt = tS
            local hidS, backS, seenS, fileS, nLed, lvlWhyS = MDQ.staleTick()
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
                tostring(fileS), tostring(lvlWhyS or "?"), tonumber(ST.staleHidN) or 0, MDQ.staleNames(8),
                ((tonumber(ST.staleBackN) or 0) > 0) and ("；期间已还回 " .. tostring(ST.staleBackN) .. " 个") or "")
            end
          end
        end
      end
      -- ④ 关图 ⇒ 把藏过的层**全部还回**（残留清理 + 接管守护；绝不把「藏」的状态带进下一张图）
      local closedNow = (not open) and ST.open
      if closedNow then
        pcall(MDQ.staleShowAll, "地图已关")
        pcall(MDQ.holdShowAll, "地图已关")
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
        ST.staleUntil = ((type(GetTime) == "function") and GetTime() or 0) + MDQ.STALE_SEC
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
      if not (open and es and es > 0) then return end
      local gap = ((tonumber(ST.burst) or 0) > 0) and SM_BURST_GAP or SM_IDLE_GAP
      if accSwm >= gap then
        accSwm = 0
        pcall(MDQ.renderCurrent, es, false, false, true)   -- 带护守的那一拍
      end
      if (tonumber(ST.burst) or 0) > 0 and not MDQ.perfGuard then
        pcall(MDQ.renderCurrent, es, true, true, false)    -- 逐帧重申：silent + 不跑护守
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
    P("　打开世界迷雾 = " .. (MDQ.swm() and "**开**（开图即按 S_WorldMap 表整张渲染；表里没有这张图 ⇒ 一个字节都不碰）"
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
      local okR, nRestore230 = pcall(MDQ.release, "关闭缩放大地图")
      if not okR then nRestore230 = 0 end
      pcall(MDQ.staleShowAll, "关闭缩放大地图")
      pcall(MDQ.holdShowAll, "关闭缩放大地图")
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
        local lines = MDQ.staleProbe()
        for _, l in ipairs(lines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
        -- ★★★1.75.52 六改：把「接管守护」的**数量 + 存在性**体检一并打印（同样**零副作用**）——
        --   用户点名要「数量、存在性都要检查」⇒ 这两项必须有**只读**取证口，否则只能靠猜。
        local hlines = MDQ.holdProbe()
        for _, l in ipairs(hlines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
        P("用法：/ehm mapfit 残留 [on|off]（别名 stale/残留层；不给参数 = 只读体检，含「接管守护」的数量/存在性）"
          .. "｜等价开关：工具箱 → 缩放大地图 → [设置] →「打开世界迷雾」")
      elseif sub == "perf" or sub == "性能" then
        -- ★★★1.75.54：**性能体检**（用户报障「开了十几个地区以后游戏会卡死」换来的取证口）。
        --   ★这一条**会真跑一拍渲染**（与正常节拍完全相同的那条路），会写地图层 —— 如实告知，不假装只读。
        local lines = MDQ.perfProbe()
        for _, l in ipairs(lines) do
          P(l)
          pcall(mfLog, "%s", l)
        end
      elseif sub == "贴图" or sub == "tex" then
        -- ★★★1.75.53 只读体检：引擎自报的贴图路径 vs 我们按表拼的两条路径（自带 media / 客户端）——
        --   「发布后别人会不会找不到贴图」这一问，真机上一条命令就能看清。
        local tl = MDQ.texProbe()
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
          P("打开世界迷雾 = **" .. (MDQ.swm() and "开" or "关") .. "**")
          P("　" .. EVAL_SM_SWM_TIP())
        end
        P("用法：/ehm mapfit swm [on | off]（不给参数 = 只报当前）｜等价开关：工具箱 → 缩放大地图 → [设置]")
      else
        -- ★1.75.52（用户定：整条「探索层适配」摘除）⇒ `mapfit` 只剩三条真在干活的路
        --   （swm / 残留 / trace 族），不给子命令 = **现读现报**一份状态。
        P("缩放大地图：模块=" .. (EVAL_SM_ENABLED() and "**开**" or "关")
          .. " ｜ 打开世界迷雾=" .. (MDQ.swm() and "**开**" or "关")
          .. " ｜ 残留图层清理=" .. (MDQ.staleOn() and "开" or "关"))
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
        local nc = MDQ.cacheClear("载入一次性清账")
        P("本地地图签名缓存 + 旧调试日志已清（存档老键 " .. tostring(nc) .. " 个）⇒ 从零开始：会话内存缓存已空、"
          .. "旧取证环已删，之后只留新一轮的日志")
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
--   ★下面两族的闸门（`MDQ.swm()` / `MDQ.staleOn()`）**一个字都不用改** ⇒ 风险最小、行为可预期。
--   ★两个老写口（`EVAL_SM_SWM_SET` / `EVAL_SM_STALE_SET`）**全部转调这里** ⇒ 命令与界面**不可能各写一半**。
function EVAL_SM_FOG_ON() return MDQ.swm() and MDQ.staleOn() end

function EVAL_SM_FOG_SET(on)
  on = on and true or false
  SM_CFG.swmOverlay, SM_CFG.staleClean = on, on
  if not on then
    -- 关：先收我们补建的层（`MDQ.release` 里同时把守护藏过的原生层全部 Show 还回），再把残留清理的账还回。
    pcall(MDQ.release, "关闭世界迷雾")
    pcall(MDQ.staleShowAll, "关闭世界迷雾")
    P("打开世界迷雾 = 关（回到客户端自己摆的探索层：抓原值 + 按 es 折算；此前藏过的层已全部还回）")
  else
    -- 开：残留清理的账**只清不还**（可见性归「接管守护」，走还回会先闪一下又被藏）。
    pcall(MDQ.staleForget, "世界迷雾已开")
    P("打开世界迷雾 = 开（本图整张由 S_WorldMap 表渲染 + 残留清理；不再自己跑图探索）")
    P("　" .. EVAL_SM_SWM_TIP())
  end
  return true
end

-- ===== 1.75.51「S_WorldMap 贴图替代」（**已并入上面的「打开世界迷雾」**）=====
-- 真值读写：读走 `EVAL_SM_SWM_ON()`（与渲染族同源 = `MDQ.swm()`），写走 `EVAL_SM_SWM_SET()`（**转调合并写口**）。
function EVAL_SM_SWM_ON() return MDQ.swm() end

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
-- 真值读写：读走 `EVAL_SM_STALE_ON()`（与清理族同源 = `MDQ.staleOn()`），写走 `EVAL_SM_STALE_SET()`（**转调合并写口**）。
function EVAL_SM_STALE_ON() return MDQ.staleOn() end

function EVAL_SM_STALE_SET(on)
  return EVAL_SM_FOG_SET(on)
end



-- 菜单内容（与行渲染**同源**：勾选态 = 真值现算）
--   ★★★1.75.52（用户：「以上两个配置合成一个控制：**打开世界迷雾**」）：
--     残留清理那一项**并进全图开关** ⇒ 菜单只剩两项（GUI重开 / 打开世界迷雾）；
--     勾选态 = `MDQ.swm()`（全图那一档的闸门；写的时候**两个老键一起写**，见 `EVAL_SM_FOG_SET`）。
function EVAL_SM_MENU()
  local items = { L("TB_SM_GUIREOPEN"), L("TB_SM_SWM") }
  local locked = {}
  local tips = { EVAL_SM_GUIREOPEN_TIPS(), EVAL_SM_SWM_TIPS() }
  local keys = { "guiReopen", "swmOverlay" }
  local sel = {}
  if smReopenOn() then sel[1] = true end
  if MDQ.swm() then sel[2] = true end
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
