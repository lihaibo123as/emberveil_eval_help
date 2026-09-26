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
-- ★★★1.75.5：**抓原值窗口**的剩余秒数。★必须是**提前声明的文件级 local**，不能放进 `SMFIT`（那张表在第 1750 行
--   才声明 ⇒ 在 `featApplyScale` 里引用会绑成**全局 nil**，`featApply` 会中途报错被 pcall 吞掉 —— 本轮就是
--   `LOCAL ORDER CHECK` 当场抓到的：GUI重开的计数直接变成 0）。
local smFitHold = 0
-- ★★★1.75.5（用户指定「本办法」）：**手动适配进行中** —— 置真时自动逻辑（抓原值窗口 / 每帧守缩放 / 折算）
--   整段让位，由 `/ehm fitnow` 那条调试命令按「开图 → 置自然档 → 等 2s → 读原值 → 套缩放 → 折算」一步步走完并**逐条打印**。
--   为什么要有它：自动时序依赖客户端开图时机，出问题时看不出卡在哪一步；手动过程完全确定、每步都有读数。
local smFixActive = false
local function featApplyScale(s)
  local w = featWm()
  if not w then return end
  s = tonumber(s) or 1
  -- ★★★1.75.5（用户设计，采纳）：**抓原值窗口内先不缩放** —— 用户原话「探索层不加缓存是否可以在 /reload 的时候
  --   不进行缩放,以获取原值,获取完成之后再进行缩放操作?」⇒ 可以，而且这样**不用翻转外框**（翻转会惊动客户端 ⇒ 读不到），
  --   也**不用做「读回 ÷ es」的归一**（读回就是原值，不押注口径）。代价：开图后到抓完这段地图是满尺寸，
  --   所以窗口必须**有界**（`SMFIT_HOLD_SEC`；抓不到/超时就照旧先缩放，绝不把地图卡在满尺寸）。
  --   ★只挡「非 1」的写（`s == 1` 是复位/关闭路径，必须照写）⇒ 关掉功能仍能正常还原。
  if (tonumber(smFitHold) or 0) > 0 and math.abs(s - 1) > 0.001 then return end
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

-- 开图时应用（幂等）：藏两层黑幕 + 键盘还给游戏 + 透明度/缩放/位置记忆
local function featApply()
  local wm = featWm()
  if not wm then return end
  featBuild(wm)
  pcall(featRearm) -- ★1.75.9：把关闭时藏起来的拖拽柄/坐标行**重新武装**（否则拖拽移动永久失效）
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

-- ★★★1.75.9 新增（用户要求：「在开启/关闭大地图缩放要做好探索层纹理的事件清理」）：
--   **关闭时把自己装上去的东西收干净** —— 这是「关掉零动作」最容易漏掉的一半：
--     · 坐标行的 OnUpdate：摘掉 + 清空文本 + Hide（它挂在地图帧下，旧版关掉后照样每 0.1s 算一次）；
--     · 拖拽柄：Hide；
--     · `UISpecialFrames`：**只有我们自己插进去的那一项**才拿掉（`FEAT.escAdded` 记账）；
--     · 滚轮处理器：**不摘链**（摘链会连客户端原生滚轮一起弄丢），而是在处理器开头加 enabled 门（见 featWheelOn）。
--   ★**不清 `SMFIT.rec` / 存档原值** —— 那是「真原值」，留着才能在下次开启时把几何还原（见 smFitApply 的注释）。
local function featTeardown()
  FEAT.torn = true
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
-- ★★★1.75.13：`rec` = **本图**（当前地图身份）的原值；`wroteKeys[纹理名] = 地图身份` = 本图我们真写过哪些层
--   （还原只还我们写过的，绝不去动没碰过的层）；`mapKey` = 当前地图身份；`mapAge` = 本图已开多少秒（等版式稳定）
local SMFIT = { open = false, es = nil, burst = 0, rec = {}, captured = false, needFold = nil, wrote = false,
  pendingApply = false, mapKey = nil, mapAge = 0, wroteKeys = {}, capAt = nil, capCalls = 0, capAge = 99,
  capFails = 0,
  recMap = {} }
-- ★★★1.75.5 定案（用户提问：「这个探索层每个地区的定位是从缓存读取的吗? 理论上每次打开地图都要重新计算的.
--   不需要缓存区记录这个定位信息?」）——**用户是对的：这份定位信息不该长期存盘**。三条事实：
--   ① 客户端**每次开图都会自己重摆**这批纹理（`WorldMapFrame_Update` 按当前地图的补丁列表 `SetPoint/SetWidth`）
--      ⇒ 开图那一刻纹理上的活值**就是原值**，不需要从存档里翻一份出来；
--   ② 存盘带来的全是坑：旧 schema 按纹理名记一份（跨图污染 = 「坐标丢失/全挤在左下」）、版本戳迁移、
--      「存档已齐 ⇒ 抓原值空转 ⇒ 每帧抖缩放」（1.75.4 那场事故）；
--   ③ 唯一**真需要记住**的是：**本会话内、按地图**的一份 —— 一旦我们把某张图折过，纹理上就是折后值；
--      同一会话里切回该图时若客户端没重摆，没有内存记录就会把折后值当原值再折一遍（1.75.9 的「缩两遍」）。
--   ⇒ 现在：**内存 `SMFIT.recMap[地图身份]`（会话级、按图）**，存档里那份**一次性清掉**（没人再读它）。
--   ★不写版本戳：判据就一条「老键还在就丢」——丢掉之后自然不再命中，天然幂等（少一个会过期的字段）。
local function smFitMigrate()
  local had = (SM_CFG.mapFitOrig ~= nil) or (SM_CFG.mapFitVer ~= nil)
  if had then
    SM_CFG.mapFitOrig = nil
    SM_CFG.mapFitVer = nil
    SMFIT.rec = {}
    SMFIT.recMap = {}
    SMFIT.captured = false
  end
  return had
end
local SMFIT_BURST_GAP, SMFIT_BURST_SEC, SMFIT_IDLE_GAP = 0.1, 2.0, 0.3
-- ★1.75.13：等客户端把**本图**的版式摆稳再抓原值（开图那一瞬抓到的可能还是上一张图/未布局的几何）
local SMFIT_SETTLE = 0.4
-- ★★★1.75.5：抓原值的**有界重试**间隔（秒）—— 读不出来时最多 1 秒重试一次，
--   绝不每帧重试（1.75.4 的事故：没落闩 + 每帧重试 = 每帧把地图缩放按 1 再放回 ⇒ 缩放抖动 + 刷屏）
local SMFIT_CAP_GAP = 1.0
-- ★★★1.75.5（用户设计）：**抓原值窗口**上限（秒）—— 「本图还没有原值」时先不缩放、在自然档读原值；
--   抓到就立刻收窗口并缩放；到点还没抓到 ⇒ 也收窗口（先缩放、稍后由有界重试继续补抓），
--   **绝不把地图卡在满尺寸**。
local SMFIT_HOLD_SEC = 2.0

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

-- ★★★1.75.13：**本图*真正在用*的叠加层**判定（只读；读不到一律**放行** —— 判不出就不拦，绝不把功能判死）。
--   · `IsShown() == false` ⇒ 客户端本图不用它（它留着上一张图的几何，写它就是制造错位）；
--   · `GetTexture()` 读得到且为空 ⇒ 客户端这一轮根本没往它上面贴图（同上）。
local function smFitInUse(o)
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

-- ★1.75.5：原值总条数 = **会话内存**里的记录合计（当前图 + 本会话访问过的其他图；存档里那条路已废弃）
local function smFitOrigCount()
  local n = 0
  for _, v in pairs(SMFIT.rec or {}) do if type(v) == "table" then n = n + 1 end end
  for mk, bucket in pairs(SMFIT.recMap or {}) do
    if mk ~= SMFIT.mapKey and type(bucket) == "table" then
      for _, v in pairs(bucket) do if type(v) == "table" then n = n + 1 end end
    end
  end
  return n
end
-- ★1.75.5：**本图**（当前绑定）的记录条数 —— 播报抓原值状态用（`smFitOrigCount` 是「跨图合计」，口径不同，别混用）
local function smFitRecCount()
  local n = 0
  for _, v in pairs(SMFIT.rec or {}) do if type(v) == "table" then n = n + 1 end end
  return n
end
local smFitMsgAt = -99
-- ★1.75.5：瞬态「折算暂缓」取证行的节流时刻（独立于 smFitMsgAt，避免两条消息互相挤掉节流）
local smFitTransAt = -99

-- ★（`smFitNewMap` / `smFitBindMap` 定义在 `mfLog` **之后**、`smFitApply` 之前：
--   它们要写取证环 —— 本项目的铁律是「引用的 local 必须在**声明之后**」，写反了就是全局 nil。）

-- 开关真值：`SM_CFG.mapFit`，**nil = 默认开**（只有显式 false 才算关 —— 「默认启动」是用户明确要求）
local function smFitOn()
  return SM_CFG.mapFit ~= false
end

-- ★★★1.75.5（**用户要求**）：「每次地图关闭都把原值数据清理、不要保存这个值；每次打开地图都重新获取原值、重新缩放大地图」
--   —— 采纳为**默认行为**。真值 `SM_CFG.mapFitFresh`（**nil = 开**）；
--   `/ehm mapfit fresh off` 回退成「本会话内按图记住原值」（只有换图 / `/reload` 才重抓）。
--   ★清空动作在**关图那一刻**做，见 `smFitDropOnClose`。
local function smFitFreshOn()
  return SM_CFG.mapFitFresh ~= false
end

-- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：**详细日志开关**，真值 `SM_CFG.mapFitVerbose`，
--   **nil = 关**（安静档）。安静档只保留「读到了几条 / 折算已对齐 / 关图已清空 / 真出问题」这几行；
--   逐条原值、第 N 次尝试、每次重试提示、窗口开关、每次折算细节 = 本档（`/ehm mapfit verbose on`）。
--   ★默认必须是**关**：这些行是**给排查用的**，功能正常时它们只是刷屏（用户实测：开一次图十几行）。
local function smFitVerboseOn()
  return SM_CFG.mapFitVerbose == true
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
          -- ★★★1.75.9：键**以纹理名优先**（`WorldMapOverlay1`/`WorldMapHighlight` 是稳定身份）。
          --   旧写法用枚举序号 `tex1..texN` ⇒ 换区/开图重建让序号漂移，还原就写到**别的纹理**上，
          --   再折一次 = 花屏/两遍（这类「按位置当身份」的坑本项目在柄池那处也踩过）。
          local key = (type(nm) == "string" and nm ~= "" and nm ~= "?") and nm or ("tex" .. tostring(idx))
          table.insert(list, { o = o, key = key, name = nm })
        end
      end
    end
  end
  return list
end

-- ★★★1.75.9 折算取证环（用户：「可以开启日志.在何种情况下会进行双次缩放操作.」）
--   为什么**另存一份**而不只走日志：`EVAL_LOGLINE` 受「调试日志」总闸门管（关掉就一个字都不记），
--   而这一案要能**任意时刻**复现取证 ⇒ 记进本模块自己的子树 `SM_CFG.mapFitTrace`（60 行小环，随 SavedVariables 落盘，
--   `/ehm mapfit trace` 用**常开出口**打出来；与追踪探针的 `trkProbe` 同一套路）。
--   记的全是**分叉处的实数**：探测（缩放 1 vs 0.7 时读到的屏幕宽）、抓原值（读时的外框缩放 ⇒ 自证自然档）、
--   每次折算（es + 原值 → 新值）、每次还原（读回）、每次开关（mode/touched/还原数）。
local MF_TRACE_MAX = 60
local function mfLog(fmt, ...)
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
local function smFitSayV(fmt, ...)
  local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
  mfLog("[详细] %s", msg)
  if not smFitVerboseOn() then return msg end
  local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
  pcall(out, "[简易地图] " .. msg)
  return msg
end

-- ★★★1.75.13/1.75.5：**换图 = 换一套原值**（同一个纹理名在不同地图上是完全不同的矩形 ⇒ 绝不跨图复用）。
--   为什么必须有它：`WorldMapOverlay1..N` 是按序号逐图复用的（客户端每图重摆），把 A 图的矩形盖到 B 图上
--   就是用户报的「坐标丢失 + 全挤在左下」。
--   ★★1.75.5 起改成**会话内存按图存**（`SMFIT.recMap[地图身份]`）、**不再落存档**（用户提问定案：
--     「理论上每次打开地图都要重新计算的，不需要缓存区记录这个定位信息?」—— 客户端每次开图都会自己重摆，
--      存盘只会带来跨会话脏值；只有「本会话内我们把某图折过」这件事必须记住，否则切回该图会把折后值当原值再折一遍）：
--     · 切走时把当前图的记录**存回 recMap**；切回来时**直接取回**那份（有记录 ⇒ 抓原值空转一次即落闩、一个缩放都不碰）。
local function smFitNewMap(mk)
  mk = tostring(mk or "?")
  local old = SMFIT.mapKey
  if old and old ~= mk and type(SMFIT.rec) == "table" and next(SMFIT.rec) ~= nil then
    SMFIT.recMap[old] = SMFIT.rec
  end
  SMFIT.mapKey = mk
  SMFIT.rec = SMFIT.recMap[mk] or {}
  SMFIT.recMap[mk] = SMFIT.rec
  SMFIT.captured = false
  SMFIT.mapAge = 0
  SMFIT.capAge = 99 -- 换图后第一次抓原值只受「版式稳定」门管（不会被有界重试门多等一秒）
  -- ★1.75.5：播报计数跟着换图归零（用户要求「获取原值的地方打印出来」，但换图后**只许再报几次**，绝不刷屏）
  SMFIT.capSayN = 0
  -- ★1.75.5（用户：「清理下这些调试日志」）：**每次开图只报一次**的那几条也要跟着换图归零
  SMFIT.saidLatch, SMFIT.saidFail, SMFIT.saidEmpty, SMFIT.saidFold = false, false, false, false
  smFitHold = 0 -- ★1.75.5：换图 ⇒ 窗口重新判定（下一拍按「本图有没有记录」决定开不开）
  mfLog("换图：%s ⇒ 本图原值改从**会话内存**取（有就复用、没有就在自然档抓一次；跨图沿用就是「坐标丢失/全挤在左下」的根因）",
    tostring(mk))
  return true
end

-- 把「当前图」的记录绑到 recMap 上（三处调用口共用；★身份变了就换绑 —— 只有这里会换 `SMFIT.rec`）
local function smFitBindMap(mk)
  mk = tostring(mk or "?")
  if mk ~= SMFIT.mapKey then pcall(smFitNewMap, mk) end
  SMFIT.recMap[mk] = SMFIT.rec
  return SMFIT.rec
end

-- ★★★1.75.9：**本客户端的 `GetEffectiveScale` 返回的是「自身 scale」，不是级联后的有效缩放** ——
--   真机证据（用户 DebugBox 截图）：`WorldMapDetailFrame … S1.00`，而它的尺寸是 `701×468` = `1002×668 × 0.7`，
--   即：**尺寸读回含父帧缩放、GetScale 报自身** ⇒ 面板上「缩放 0.70」与折算消息里的「按缩放 1.00」是两个量
--   （前者是我们写进 `WorldMapFrame:SetScale` 的**设置值**，后者是 `GetEffectiveScale` 的**读回值**）。
--   ⇒ 另算一个「沿父链把 GetScale 连乘」的**真有效缩放**，只用于**报告 / 取证 / 诊断**；
--     折算系数仍按读回口径（那才是与读回几何同一口径的量，见 tick 与参考卷 R20）。
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

-- ★★★1.75.9 只读探测：**本客户端会不会把父帧缩放级联到这些纹理的渲染上**？
--   为什么必须实测：两种客户端模型要求**相反**的做法 ——
--     · 会级联（叠加层自己跟着地图缩）⇒ 我们**一个几何都不该碰**（再折一次 = 缩两遍，正是用户报的 bug）；
--     · 不会级联 ⇒ 必须按 es 折算（1.74.34-18b 的老结论）。
--   判据（只读）：把外框缩放临时按 1 → 0.7 走一档，读纹理的**屏幕几何**（GetLeft/GetTop/GetWidth，本客户端含缩放）——
--     跟着变 ⇒ 会级联（`needFold = false`）；一点不变 ⇒ 不会级联（`needFold = true`）；读不到 ⇒ nil。
--   ★`nil`（测不出）一律按**不折算**用（见 tick）：用户实测的两次「缩两遍」都发生在会被级联的客户端上，
--     这一侧才是安全默认；真需要折算的客户端由探测结果自行打开。
--   ★改完立刻把缩放放回原档（同一帧内，无可见闪烁）。
local function smFitDetect()
  local list = smFitTargets()
  if table.getn(list) == 0 then return nil end
  local wm = featWm()
  if not wm then return nil end
  local oks, cur = pcall(wm.GetScale, wm)
  cur = (oks and tonumber(cur)) or 1
  if cur <= 0 then return nil end
  local function snap(o)
    local okL, l = pcall(o.GetLeft, o)
    local okT, t = pcall(o.GetTop, o)
    local okW, w = pcall(o.GetWidth, o)
    return { l = (okL and tonumber(l)) or nil, t = (okT and tonumber(t)) or nil, w = (okW and tonumber(w)) or nil }
  end
  local seen, moved = false, false
  for _, it in ipairs(list) do
    local o = it.o
    local a = snap(o)
    pcall(wm.SetScale, wm, 1)
    local b = snap(o)
    pcall(wm.SetScale, wm, 0.7)
    local c2 = snap(o)
    pcall(wm.SetScale, wm, cur)
    if a.w and b.w and c2 and c2.w then
      seen = true
      -- 1 → 0.7 这一档：屏幕宽度跟着缩 ⇒ 客户端会级联
      if b.w > 0 and math.abs(c2.w - b.w * 0.7) <= b.w * 0.06 then moved = true end
    end
    if a.l and b.l and c2 and c2.l and math.abs(c2.l - b.l) > 0.5 then seen, moved = true, true end
    if not seen then
      mfLog("探测：%s 读不到屏幕几何（GetLeft/GetTop/GetWidth 都无效）⇒ 判定未知", tostring(it.key))
    else
      mfLog("探测：%s 缩放1→读宽 %s ｜ 缩放0.7→读宽 %s ⇒ %s（读回口径 es=%s ｜ 父链真有效缩放=%s ｜ 设置值=%s）", tostring(it.key),
        tostring(b and b.w), tostring(c2 and c2.w),
        moved and "**跟着缩**（客户端自己会级联 ⇒ 折算将是第二遍）" or "不动（客户端不会级联 ⇒ 需要折算）",
        tostring(cur), tostring(smEffScale(wm)), tostring(SM_CFG.scale))
    end
    if moved then break end
  end
  if not seen then return nil end
  return (not moved)
end

-- ★★★1.75.9 折算策略（**默认折算** —— 用户实测：改成「探测说什么就听什么」会让「正常开启完全不生效」）：
--   `SM_CFG.mapFitMode`：nil / "fold" = **照旧折算**（探测结论只进提示与取证）；"auto" = 交给只读探测；"nofold" = 一个几何都不碰。
--   ★这条 A/B 是给真机定档用的：`/ehm mapfit mode fold|auto|nofold`（见 EVAL_SM_MAPFIT_MODE_SET）。
local function smFitMode()
  local m = SM_CFG.mapFitMode
  if m == "auto" or m == "nofold" or m == "fold" then return m end
  return "fold"
end

local function smFitModeLabel()
  local m = smFitMode()
  if m == "auto" then return "自动（听探测结论）" end
  if m == "nofold" then return "不折算（一个几何都不碰）" end
  return "折算（默认：按 es 折一次）"
end

local function smFitNeedFold()
  local m = smFitMode()
  if m == "nofold" then return false end
  if m == "auto" then return (SMFIT.needFold == true) end
  return true -- ★默认：折算（否则「正常开启无法生效」= 用户实测到的那种回归）
end

-- 应用适配：返回 改动数, 已适配数, 等原值的目标数
local function smFitApply(es, quiet)
  smFitMigrate()
  if not smFitNeedFold() then return 0, 0, 0 end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then return 0, 0, 0 end
  es = tonumber(es) or 1
  if es <= 0 then es = 1 end
  -- ★★★1.75.5：**缩放还没落地的瞬态** ⇒ 这一拍先不折算。
  --   真机证据（1.75.4 那场事故的日志）：设置值 scale=0.7 而读回 es=1.000 ⇒ 若照折，就会先把
  --   **未折几何**写一遍（下一拍 es 到位再写一遍）＝ 同一次开图两个不同值都落下去（既闪又刷屏）。
  --   等缩放落地再算，语义与结果都更干净；这也是「读回口径不可信时不动手」的同族判据。
  if math.abs(es - 1) <= 0.001 and math.abs((tonumber(SM_CFG.scale) or 1) - 1) > 0.001 then
    -- ★★★1.75.5（真机日志实测：7 分钟内反复出现「读回 es=1.000 而设置值 0.7」）：
    --   这一拍**主动把缩放掰回去**（`featApplyScale` 自带「同档不重写」读回自证 ⇒ 本来就对时一个写都不发），
    --   这样瞬态最多只影响**一拍**；然后再暂缓折算。
    pcall(featApplyScale, tonumber(SM_CFG.scale) or 1)
    -- 取证行**不受 quiet 门控**（这是「为什么这一拍没折算」的唯一证据），但**有界节流**（3s 一条），绝不刷屏。
    -- ★同时把**自身 GetScale / 父帧有没有**摊出来 —— 这是区分「客户端把缩放重置了」与「父链一时读不到」的唯一证据。
    local nowT = (type(GetTime) == "function") and GetTime() or 0
    if nowT - (smFitTransAt or -99) > 3 then
      smFitTransAt = nowT
      local ownS, hasPar = "?", "?"
      if type(fr) == "table" or type(fr) == "userdata" then
        local ok1, v1 = pcall(fr.GetScale, fr)
        if ok1 then ownS = string.format("%.3f", tonumber(v1) or 0) end
        local ok2, v2 = pcall(fr.GetParent, fr)
        hasPar = (ok2 and v2 ~= nil) and "有" or "**无**"
      end
      mfLog("折算暂缓：读回 es=1.000 而设置值 scale=%s ⇒ 已主动掰回缩放、本拍不折算（自身 GetScale=%s ｜ 父帧=%s）",
        tostring(SM_CFG.scale), ownS, hasPar)
    end
    return 0, 0, 0
  end
  -- ★★★1.75.5：记录只来自**会话内存**（`SMFIT.recMap[地图身份]`，见 smFitMigrate 的注释）——
  --   定位信息由客户端每次开图重摆、我们只在会话内记住「折之前是什么」，**不再落存档**。
  local mk = smMapKey() or SMFIT.mapKey or "?"
  smFitBindMap(mk) -- ★1.75.5：身份变了自己换绑（并把本图记录挂回 recMap）
  -- ★本图客户端自己说「零条叠加层」⇒ 一个几何都不该碰（旧写法照样把那批残留几何写一遍）
  if smNumOverlays() == 0 then return 0, 0, 0 end
  local list = smFitTargets()
  local changed, ready, rec, skipped = 0, 0, 0, 0
  for _, it in ipairs(list) do
    local o = it.o
    -- ★★★1.75.13：**本图不用的层一个几何都不碰**（隐藏 / 没贴图 ⇒ 它身上是别的图的残留几何；
    --   旧写法对它们照写 = 真机看到的那批「全部挤在同一处」）
    local use = smFitInUse(o)
    if not use then skipped = skipped + 1 end
    local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
    local okw, w = pcall(o.GetWidth, o)
    local okh, h = pcall(o.GetHeight, o)
    if use and okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
      -- ★本函数**只读、绝不记原值**（唯一写入点是 smFitCapture）：没有记录 ⇒ 只计数，等抓原值那一拍补上
      local r = SMFIT.rec[it.key]
      if not r then rec = rec + 1 end
      if r then
        local wantX, wantY = r.x * es, r.y * es
        local wantW, wantH = r.w * es, r.h * es
        -- ★读回口径（1.75.5 改成**两种都认**，与 smFitRestore 同一套判据）：
        --   · 「读回 = 逻辑值」（不会级联的客户端）⇒ 对齐 = 读回 ≈ 原值×es（旧写法只认这一种）；
        --   · 「读回 = 逻辑值×es」（**本客户端实测**：几何读回含父帧缩放）⇒ 写进去的逻辑值读回来是 ×es
        --     ⇒ 对齐 = 读回 ≈ 原值×es×es。
        --   ★旧写法只按第一种比 ⇒ 在会级联的客户端上**每一拍都判成「要改」**（真机取证：8 个纹理被反复重写、
        --     聊天每 3 秒刷一条「叠加层适配」）；两种都认之后：该写时写一次，之后永远判「已对齐」。
        local near = function(a, b) return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= 0.5 end
        local okA = near(x, wantX) and near(y, wantY) and near(w, wantW) and near(h, wantH)
        local okB = near(x, wantX * es) and near(y, wantY * es) and near(w, wantW * es) and near(h, wantH * es)
        if okA or okB then
          ready = ready + 1
        else
          -- ★★★1.75.5 真机定案（用户截图：**探索层贴图跑到游戏画面里**，右下角拼出一块丹莫罗地图）：
          --   写锚点**必须传「帧对象」**，绝不能把记录里的相对帧**名字（字符串）或 nil** 丢给 `SetPoint` ——
          --   本客户端对「字符串/nil 相对帧」的处理 = **锚到屏幕**（UIParent）⇒ 这些纹理逃出地图窗口、画在游戏世界上
          --   （`smFitRestore` 那条路一直是**解析成对象**的，所以「关功能」能救回来 —— 这也正是两边行为不一致的真因）。
          local relObj = nil
          if type(r.relObj) == "table" or type(r.relObj) == "userdata" then relObj = r.relObj end
          if (not relObj) and type(r.rel) == "string" and r.rel ~= "" then relObj = _G[r.rel] end
          if not relObj then relObj = fr end -- 兜底：原值记的就是「锚父帧 TOPLEFT」
          pcall(o.ClearAllPoints, o)
          pcall(o.SetPoint, o, r.p, relObj, r.rp, wantX, wantY)
          r.relObj = relObj -- ★记住活对象（同会话内换图/还原都用它，不再靠字符串）
          pcall(o.SetWidth, o, wantW)
          pcall(o.SetHeight, o, wantH)
          changed = changed + 1
          SMFIT.wrote = true -- ★1.75.9：记下「本会话**真的写过**几何」⇒ 关闭时才需要还原（没写过就一个写都不发）
          -- ★1.75.13：**逐层记账**（还原只还我们写过的、且只还**本图**写过的）
          SMFIT.wroteKeys[it.key] = mk
          mfLog("折算：es=%.3f %s 原值(%.1f,%.1f %.1f×%.1f,来自%s) → 写入(%.1f,%.1f %.1f×%.1f)",
            es, tostring(it.key), r.x, r.y, r.w, r.h, tostring(r.from or "rec"),
            wantX, wantY, wantW, wantH)
        end
      end
    end
  end
  if changed > 0 then
    SM_CFG.mapFitAt = (type(GetTime) == "function") and string.format("%.1f", GetTime()) or "?"
    SM_CFG.mapFitLast = { es = es, changed = changed, total = table.getn(list), skipped = skipped, map = mk }
    local now = (type(GetTime) == "function") and GetTime() or 0
    -- 同一波重排只播报一次（3s 节流），不然每拍刷屏
    -- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：再叠一道**每次开图只报一次**的门
    --   （真机实测：开一次图那条「叠加层适配：对齐 8 个」会重复出现 6 次以上 —— 每次重排/重抓都会再来一轮）。
    --   ⇒ 安静档只留**本图第一次折算**那一条；其余进 verbose 档与取证环。
    local firstFold = (not SMFIT.saidFold)
    if (not quiet) and (now - (smFitMsgAt or -99) > 3) and (firstFold or smFitVerboseOn()) then
      smFitMsgAt = now
      SMFIT.saidFold = true
      local eff = smEffScale(fr)
      mfLog("折算口径：读回 es=%.3f ｜ 父链真有效缩放=%.3f ｜ 设置值 scale=%s", es, eff, tostring(SM_CFG.scale))
      local same = (math.abs(eff - es) < 0.01)
      P(string.format("叠加层适配：按读回口径 %.2f 对齐 %d 个（非瓦片纹理共 %d 个%s；底瓦片不动）%s",
        es, changed, table.getn(list),
        (skipped > 0) and ("，本图不用的 " .. skipped .. " 个已跳过") or "",
        same and "" or string.format("｜★真有效缩放(父链连乘)=%.2f，读回口径=%.2f（本客户端 `GetEffectiveScale` 报的是**自身** scale，两个量不同）", eff, es)))
    else
      -- 安静档：只进取证环（一行一条，供 `/ehm mapfit trace` 事后翻）
      mfLog("折算（静默）：es=%.3f 改 %d 个（本图第 %s 次折算；要逐次上屏用 /ehm mapfit verbose on）",
        es, changed, tostring(SMFIT.saidFold and ">1" or "1"))
    end
  end
  return changed, ready, rec
end

-- ★★★1.75.9 新增：**先抓原值、再改缩放**（本项目铁律「读原值 → 写新值，顺序不许换」，1.74.31 组 206 的教训）。
--   真机事故：载入后点开启 ⇒ 探索层缩了两遍。旧顺序 = `smApplyDefaults()`（**立刻** SetScale 0.7）
--   → 之后 tick 才去记「原值」⇒ 记下来的可能已经是**缩过的值**，再折一次 = 两遍。
--   ★本客户端几何读回**可能含缩放**（R15 ⑥d 实测：宽 384 + es 0.7 ⇒ 读回 268.8）⇒
--     抓原值时把外框缩放**临时置 1**（自然档）读一次，读完立刻恢复原缩放（同一帧内，不会闪）。
--   ★只补「还没记过」的目标（**绝不覆盖**已有记录）；成功抓到就把版本戳写进存档。
local function smFitCapture()
  SMFIT.capCalls = (tonumber(SMFIT.capCalls) or 0) + 1 -- ★1.75.5：抓原值的**尝试次数**（读值口/事故取证用）
  -- ★★★1.75.5（**用户要求**：「获取原值的地方添加日志信息，打印出来」）：
  --   每次尝试先报一条**看得见**的入口行（前 5 次 / 每图；计数在 smFitNewMap 里归零）——
  --   真机实证：重开后没重开地图那一次，聊天框里一条抓原值都没有 ⇒ 无法判断是「没抓」还是「抓了没成」。
  local nSay = tonumber(SMFIT.capSayN) or 0
  SMFIT.capSayN = nSay + 1
  -- ★详细档（verbose）才逐次播报；安静档一个字都不打（真出问题时 `/ehm mapfit verbose on` 打开即可）
  if nSay < 5 then
    smFitSayV("抓原值 第%d次尝试：地图=%s ｜ 本图已有记录=%d 条 ｜ 落闩=%s ｜ 客户端叠加层=%s 条",
      tonumber(SMFIT.capCalls) or 0, tostring(smMapKey() or SMFIT.mapKey or "?"), smFitRecCount(),
      SMFIT.captured and "是" or "否", tostring(smNumOverlays()))
  end
  -- ★★★1.75.5：只抓**本图真正在用**的层（见 smFitInUse / smMapKey 的注释），记录进**会话内存** `SMFIT.rec`
  local mk = smMapKey() or SMFIT.mapKey or "?"
  smFitBindMap(mk)
  if smNumOverlays() == 0 then
    if nSay == 0 then smFitSayV("抓原值：客户端说本图 **0 条叠加层** ⇒ 不抓、也不碰任何几何") end
    return 0
  end
  local list = smFitTargets()
  if table.getn(list) == 0 then
    if nSay == 0 then
      smFitSay("抓原值：`WorldMapDetailFrame` 下**没有可用纹理**（地图没开，或客户端还没建这批纹理）⇒ 本次什么都不做")
    end
    return 0
  end
  -- ★★★1.75.5 真机事故（用户：「换了一个账号之后…地图缩放不正常了」）：**先筛候选，再动缩放**。
  --   旧写法把「临时 SetScale(1)」放在筛选**之前**，而落闩条件写的是 `n > 0` —— 原值已齐（每次 /reload 必然如此）
  --   时 `n = 0` ⇒ `SMFIT.captured` 永远 false ⇒ tick **每帧**重跑本函数、**每帧**把世界地图缩放按 1 再放回
  --   ⇒ ① 地图缩放每帧抖一次（看着就是「缩放没生效/不正常」）；② 取证环 1 秒被刷满 60 条（把真证据挤掉）；
  --   ③ 折算口径被搅成 1.000 ⇒ 叠加层被反复重写（聊天刷屏）。
  local todo, skipUse = {}, 0
  for _, it in ipairs(list) do
    if not smFitInUse(it.o) then
      skipUse = skipUse + 1 -- 本图不用的层：既不抓也不写（它身上是别的图的残留几何）
    elseif not SMFIT.rec[it.key] then
      table.insert(todo, it)
    end
  end
  if table.getn(todo) == 0 then
    -- ★★★1.75.5 真机报障（用户截图：「/reload 插件载入的时候为什么原值为 0 也定义为原值抓取完成?这个流程本身就不对」）：
    --   `todo` 空有**两种完全不同的来法**，一视同仁地落闩就是那个 bug：
    --     · 目标**都已经有记录**（本图确实读过）⇒ 真没事可做 ⇒ 落闩 ✓（原设计针对的就是这个场景）；
    --     · 目标**一个都不在用**（客户端还没摆版式 / 还没贴图）⇒ **一条都没读到** ⇒ 落闩意味着
    --       「以后再也不会抓」⇒ 地图缩了、探索层没缩 = 错位（真机现象：「原值已齐（0 条）」+「已抓到原值」+
    --       一个几何都不折）。⇒ 这一种**绝不落闩**，交给 tick 的**有界重试**（1 秒一次）等它摆好。
    if smFitRecCount() > 0 then
      -- 本图原值已齐 ⇒ **当场落闩**（并记下尝试时刻，供有界重试用）：一个缩放都不碰、一次读都不做
      SMFIT.captured = true
      SMFIT.capAt = (type(GetTime) == "function") and GetTime() or 0
      -- ★安静档：**每次开图只报这一条**（有记录、落闩）—— 详细档才逐次摊开
      if not SMFIT.saidLatch then
        SMFIT.saidLatch = true
        smFitSay("抓原值：本图原值**已齐**（%d 条；跳过 %d 个本图不用的层）⇒ 落闩", smFitRecCount(), skipUse)
      else
        smFitSayV("抓原值：本图原值**已齐**（%d 条；本轮跳过 %d 个本图不用的层）⇒ 当场落闩，一个缩放都不碰",
          smFitRecCount(), skipUse)
      end
      if skipUse > 0 then
        mfLog("抓原值：原值已齐，本图不用的 %d 个叠加层已跳过（隐藏/没贴图 ⇒ 旧写法抓到的是别的图的残留几何）", skipUse)
      end
      return 0
    end
    -- ★一条都没读到（记录 0 条 + 候选全不在用）⇒ 不算完成，不落闩
    SMFIT.capAt = (type(GetTime) == "function") and GetTime() or 0
    smFitSayV("抓原值：本图 %d 个候选**一个都还没在用**（客户端还没摆好版式/还没贴图）⇒ **不算抓到原值**、"
      .. "**不落闩**，1 秒后自动重试（等它摆出来再读）", skipUse)
    return 0
  end
  local n, fails = 0, 0
  -- ★★★1.75.5 真机定案（用户：「插件载入时地图缩放异常，关/开一次缩放大地图后探索层才正常」）：
  --   **抓原值时绝不翻转外框缩放** —— 旧写法「同一帧里 SetScale(1) → 立刻读 → 放回」在**外框已经是 0.70** 时
  --   是一次**真改动** ⇒ 本客户端立刻重排/清锚点 ⇒ 紧接着的读**全部读不到**（静默）⇒ 原值 0 条 ⇒ 折算无事可做。
  --   （而「关/开」那条路能成，是因为关的时候 `featReset` 已把外框复位成**真的 1.00** ⇒ 那句 SetScale(1) 是**空操作**、不惊动客户端。）
  --   ★两种客户端口径都能**从读回直接算出逻辑值**，所以根本不需要翻转：
  --     · 本客户端实测「几何读回 = 逻辑值 × es」（`needFold == false`）⇒ **÷ es** 归一；
  --     · 老探针口径「读回就是逻辑值」（`needFold == true`）⇒ 原样取；
  --     · 没探过（`nil`）⇒ 按本客户端实测口径（÷ es）。
  --   ★可自证：trace 里同时记「读回原始值 / 归一系数 / 记录值」，`/ehm mapfit dump` 里也同时打「活值」与「记录」。
  local frC = _G["WorldMapDetailFrame"]
  local esC = 1
  if type(frC) == "table" or type(frC) == "userdata" then
    local e = smEffScale(frC)
    if tonumber(e) and tonumber(e) > 0 then esC = tonumber(e) end
  end
  local norm = (SMFIT.needFold == true) and 1 or esC
  if norm <= 0 then norm = 1 end
  for _, it in ipairs(todo) do
    local o = it.o
    local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
    local okw, w = pcall(o.GetWidth, o)
    local okh, h = pcall(o.GetHeight, o)
    if okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
      -- ★记录进**会话内存**（带活对象引用 `o`：还原时要用它确认「记录对应的就是这个对象」）
      local lx, ly, lw, lh = tonumber(x) / norm, tonumber(y) / norm, tonumber(w) / norm, tonumber(h) / norm
      SMFIT.rec[it.key] = { o = o, idx = it.key, name = it.name, p = tostring(p),
        rel = smRelName(rel), relObj = rel, rp = smRelName(rp), from = "live",
        x = lx, y = ly, w = lw, h = lh, map = mk }
      n = n + 1
      mfLog("抓原值：%s %s 读回(%.1f,%.1f %.1f×%.1f) ÷%.2f ⇒ 记录(%.1f,%.1f %.1f×%.1f)（不翻转外框；地图=%s；只存会话内存）",
        tostring(it.key), tostring(p), tonumber(x), tonumber(y), tonumber(w), tonumber(h), norm,
        lx, ly, lw, lh, tostring(mk))
      -- ★用户要求「打印原值」⇒ 每图**第一次**尝试把每条原值也打到聊天框（之后只进取证环，绝不刷屏）
      if nSay <= 1 then
        smFitSayV("抓原值：%s 读回(%.1f,%.1f %.1f×%.1f) ÷%.2f ⇒ 原值(%.1f,%.1f %.1f×%.1f) ｜ 锚 %s",
          tostring(it.key), tonumber(x), tonumber(y), tonumber(w), tonumber(h), norm,
          lx, ly, lw, lh, tostring(p))
      end
    else
      -- ★★★1.75.5：读不到**再也不许静默**（这次就是被「静默失败」拖了三轮）——计数 + 有界日志
      --   ★只详报**第一个**失败目标（8 个全报会把 60 行取证环一秒冲满），其余只计数、由下面的小结摊开
      --   ★★安静档也**必须出声**：这是「原值抓不到」唯一的直接证据（真出了问题，用户看不到就只能干等）
      fails = fails + 1
      if fails == 1 and (not SMFIT.saidFail) then
        SMFIT.saidFail = true
        mfLog("抓原值读不到：%s（GetPoint=%s p=%s ｜ GetWidth=%s ｜ GetHeight=%s）⇒ 本次不记它，1 秒后重试",
          tostring(it.key), tostring(okp), tostring(p), tostring(okw), tostring(okh))
        smFitSay("抓原值**读不到**：%s（GetPoint=%s p=%s ｜ 宽=%s ｜ 高=%s）⇒ 本次不记它，1 秒后重试",
          tostring(it.key), tostring(okp), tostring(p), tostring(okw), tostring(okh))
      elseif fails == 1 then
        mfLog("抓原值读不到：%s（GetPoint=%s p=%s ｜ GetWidth=%s ｜ GetHeight=%s）⇒ 本次不记它，1 秒后重试",
          tostring(it.key), tostring(okp), tostring(p), tostring(okw), tostring(okh))
      end
    end
  end
  SMFIT.capFails = (tonumber(SMFIT.capFails) or 0) + fails
  SMFIT.capAt = (type(GetTime) == "function") and GetTime() or 0
  -- ★落闩判据 = 「本图这一轮的目标**全部**都拿到了」：
  --   · 拿到了 ⇒ 落闩（否则 tick 每帧重跑 = 上面那条事故）；
  --   · 有目标读不出来 ⇒ **不落闩**，由 tick 的**有界**重试门（`SMFIT_CAP_GAP` = 1 秒一次）兜，
  --     既不漏（等它可读时补上）也不刷（绝不每帧）。
  if n >= table.getn(todo) then SMFIT.captured = true end
  -- ★★★1.75.5：**每次尝试都留一行小结**（用户要求「监测地图信息才能知道原值问题」）——
  --   这一行让人（和 AI 读存档）不必再靠猜：第几次尝试 / 记下几条 / 读失败几个 / 归一系数 / 是否落闩。
  --   ★必须排在落闩**之后**，否则小结里的「落闩」永远是「否」（差一行就会让读数骗人）。
  local capLine = string.format("%.2f 第%d次 记%d/待%d 失败%d 归一÷%.2f 落闩=%s 地图=%s",
    (type(GetTime) == "function") and GetTime() or 0, tonumber(SMFIT.capCalls) or 0, n, table.getn(todo),
    fails, norm, SMFIT.captured and "是" or "否", tostring(mk))
  mfLog("抓原值小结：第 %d 次尝试 ｜ 本次记 %d / 待记 %d ｜ 读失败 %d（累计 %d）｜ 归一÷%.2f（%s）｜ 落闩=%s ｜ 地图=%s",
    tonumber(SMFIT.capCalls) or 0, n, table.getn(todo), fails, tonumber(SMFIT.capFails) or 0, norm,
    (SMFIT.needFold == true) and "读回=逻辑值" or "读回=逻辑×es",
    SMFIT.captured and "是" or "否", tostring(mk))
  -- ★★★1.75.5（用户要求「获取原值的地方打印出来」，随后又要求「清理下这些调试日志」）：
  --   ⇒ 安静档**每次开图只留一条**「已读到 N 条」（下面那条）；逐次小结进 verbose 档。
  --   ★取证环（`mfLog`）永远记全 ⇒ 真出问题时 `/ehm mapfit verbose on` 或 `/ehm mapfit dump` 都还看得到。
  if nSay < 5 then
    smFitSayV("抓原值小结：第%d次 ｜ 记 %d / 待记 %d ｜ 读失败 %d（累计 %d）｜ 归一÷%.2f（%s）｜ 落闩=%s ｜ 地图=%s",
      tonumber(SMFIT.capCalls) or 0, n, table.getn(todo), fails, tonumber(SMFIT.capFails) or 0, norm,
      (SMFIT.needFold == true) and "读回=逻辑值" or "读回=逻辑×es",
      SMFIT.captured and "是" or "否", tostring(mk))
  end
  -- ★★安静档的**唯一一条**成功播报（每次开图一次）：读到了几条 + 落闩
  if SMFIT.captured and (not SMFIT.saidLatch) then
    SMFIT.saidLatch = true
    smFitSay("抓原值：已读到 **%d 条**原值（地图=%s，第 %d 次尝试）⇒ 落闩",
      smFitRecCount(), tostring(mk), tonumber(SMFIT.capCalls) or 0)
  end
  -- ★★★1.75.5：**同一份小结再落一条专属存档环**（本项目既有纪律：say 不落日志环 / 环太小 ⇒ 事后读不到的读数
  --   必须自存一份**有界**环，同 `cfg.tselProbe` / `cfg.rareProbe` / `cfg.petProbe`）。
  --   为什么必须：日志环只有 60/100 行，抓原值那几行几分钟后就被刷掉 ⇒ AI 读存档只能靠猜「到底抓没抓成」。
  if type(SM_CFG.mapFitCapLog) ~= "table" then SM_CFG.mapFitCapLog = {} end
  local capRing = SM_CFG.mapFitCapLog
  table.insert(capRing, capLine)
  while table.getn(capRing) > 10 do table.remove(capRing, 1) end
  return n
end

-- 还原到**会话内存**里的原始几何（★1.75.5 起不再有存档那条路：定位信息由客户端每次开图重摆，我们只记会话内那一份）
local function smFitRestore(quiet)
  smFitMigrate()
  local mk = smMapKey() or SMFIT.mapKey or "?"
  smFitBindMap(mk)
  local list = smFitTargets()
  local n, miss, bad, untouched = 0, 0, 0, 0
  for _, it in ipairs(list) do
    -- ★记录必须**对应同一个活对象**（`live.o == it.o`）—— 客户端重建过纹理时旧记录一律不算（宁可如实跳过）
    local live = SMFIT.rec[it.key]
    local r = (type(live) == "table" and live.o == it.o) and live or nil
    -- ★★★1.75.13：**只还「本图我们真写过的」层** —— 没写过的层一个几何都不碰（「关掉零动作」的同族；
    --   旧写法会把「有记录但本次没写过」的层也写一遍，在跨图场景里等于又制造一次错位）
    if SMFIT.wroteKeys[it.key] ~= mk then
      untouched = untouched + 1
    elseif r and tonumber(r.x) and tonumber(r.y) and tonumber(r.w) and tonumber(r.h) then
      local o = it.o
      local rel = nil
      -- ★1.75.5：**优先用捕获时记下的活对象**（`relObj`）—— 字符串在**本客户端**会被当成「锚到屏幕」，
      --   与写入路径同一个坑（用户截图：探索层贴图跑到游戏画面上）；只有对象才是安全的。
      if type(r.relObj) == "table" or type(r.relObj) == "userdata" then rel = r.relObj end
      if (not rel) and type(r.rel) == "string" and r.rel ~= "" then rel = _G[r.rel] end
      if type(r.rel) ~= "string" and type(r.rel) ~= "nil" and r.rel and type(r.rel) ~= "table" and type(r.rel) ~= "userdata" then rel = r.rel end
      if not rel then rel = _G["WorldMapDetailFrame"] end -- 原值记的就是「锚父帧 TOPLEFT」（探针 27 行定案）
      local rp = (type(r.rp) == "string" and r.rp ~= "") and r.rp or "TOPLEFT"
      pcall(o.ClearAllPoints, o)
      local ok = pcall(o.SetPoint, o, tostring(r.p), rel, rp, tonumber(r.x), tonumber(r.y))
      pcall(o.SetWidth, o, tonumber(r.w))
      pcall(o.SetHeight, o, tonumber(r.h))
      -- ★写完**读回自证**（本项目纪律：写成功 ≠ 写进去生效）。★读回含缩放 ⇒ 比之前先除 es。
      local okv, _, _, _, vx, vy = pcall(o.GetPoint, o, 1)
      local okw2, vw = pcall(o.GetWidth, o)
      local es = 1
      local fr2 = _G["WorldMapDetailFrame"]
      if (type(fr2) == "table" or type(fr2) == "userdata") then
        local eff2 = smEffScale(fr2)
        if tonumber(eff2) and tonumber(eff2) > 0 then es = tonumber(eff2) end
        if es == 1 and type(fr2.GetEffectiveScale) == "function" then
          local oke, v = pcall(fr2.GetEffectiveScale, fr2)
          if oke and tonumber(v) and tonumber(v) > 0 then es = tonumber(v) end
        end
      end
      local okRead = okv and tonumber(vx) and okw2 and tonumber(vw)
      local good = ok and okRead
      if good and es > 0 then
        -- ★两种客户端口径都认：读回含缩放（真机）除 es 后对得上 **或** 读回就是逻辑值 ⇒ 都算写成功；
        --   两边都对不上才记「读回对不上」（如实报出，不静默）。
        local okA = math.abs(tonumber(vx) / es - tonumber(r.x)) <= 0.75 and math.abs(tonumber(vw) / es - tonumber(r.w)) <= 0.75
        local okB = math.abs(tonumber(vx) - tonumber(r.x)) <= 0.75 and math.abs(tonumber(vw) - tonumber(r.w)) <= 0.75
        good = okA or okB
      end
      if not ok then
        miss = miss + 1
        mfLog("还原失败：%s 写不进去（SetPoint 抛错）", tostring(it.key))
      elseif not good then
        bad = bad + 1 n = n + 1
        mfLog("还原存疑：%s 写回后读回对不上（读 x=%s w=%s，期望 %.1f×%.1f，es=%.2f）",
          tostring(it.key), tostring(vx), tostring(vw), tonumber(r.x), tonumber(r.w), es)
      else
        n = n + 1
        mfLog("还原：%s x=%.1f y=%.1f w=%.1f h=%.1f（读回自证通过，es=%.2f）",
          tostring(it.key), tonumber(r.x), tonumber(r.y), tonumber(r.w), tonumber(r.h), es)
      end
    else
      miss = miss + 1
    end
  end
  -- ★★★1.75.9：**绝不在这里清 `SMFIT.rec`** —— 那是「本进程的真原值」，清掉就等于允许下次把
  --   已折过的值重新当原值记下来（旧版「关一次再开 ⇒ 折两遍」的根因）。
  if not quiet then
    P("叠加层还原：按原值还原 " .. n .. " 个"
      .. (miss > 0 and ("；" .. miss .. " 个没有原值或锚点解析失败 ⇒ **如实跳过**（没动它们）") or "")
      .. (bad > 0 and ("；" .. bad .. " 个写回后读回对不上 ⇒ **如实报出**（可能被客户端布局盖掉）") or "")
      .. (untouched > 0 and ("；" .. untouched .. " 个本图我们没写过 ⇒ **一个几何都不碰**") or ""))
  end
  return n, miss, bad
end

-- ★★★1.75.13 新增：**换图 = 换一套原值**（同一个纹理名在不同地图上是完全不同的矩形 ⇒ 绝不跨图复用）。
--   ★★1.75.5：已上移到 smFitApply 之前（apply/capture/restore 三处都要按身份换绑）—— 见 `smFitNewMap`。

-- ★★★1.75.5（**用户要求**）：「**每次地图关闭都把原值数据清理，不要保存这个值；每次打开地图都重新获取原值、重新缩放大地图**」
--   +「每次打开地图都当做是第一次打开」「每次 reload 插件载入也都当做第一次」—— **全部采纳**，落在关闭这一侧：
--   · **关图那一刻**：把折过的几何还回自然档，然后**把本图的原值记录整块删掉**（`rec` / 分桶 / 逐层记账 / 落闩 / 计数）；
--   · **下一次开图**：记录天然是空的 ⇒ 走既有的「本图还没有原值 ⇒ 先不缩放、在自然档读一次 → 落闩 → 套缩放」，
--     也就是「重新获取原值 + 重新缩放」（不需要额外开关，这条路本来就是为「没有记录」设计的）；
--   · `/reload`：原值只在**会话内存**（定位信息绝不落存档）⇒ 载入后本来就是空的 ⇒ 第一次开图必然重读（判据 = 组 254⑦⑧）。
--   ★为什么必须在**关闭**这一侧清（而不是开图时清）：
--     ① 关闭时地图不可见，还原几何**不会闪**，也不会惊动客户端正在做的版式计算；
--     ② 开图那一瞬客户端还在摆版式，此时去写几何/清记录最容易和它抢（实测「抓到 0 条却当成已齐」那类怪象都出在这个窗口）；
--     ③ 「记录只活在**一次开图**里」这条口径最干净：不存在「拿着上一次的矩形当原值」的可能（分辨率 / UI 缩放 /
--        客户端布局一变，旧记录就是错的 —— 这一案反复的根源正是它）。
--   ★安全阀（顺序铁律，缺一步就会把**折过的值**当原值 = 折两遍）：
--     还回自然档**必须先做且必须验成功**才敢清记录。若还回没成功（写回后读回对不上 —— 多半是客户端正在重排版式
--     把我们的写盖掉了），就**保留记录**、如实播报，宁可退化成老行为，也不制造一个更难查的错位。
--   ★真值 `SM_CFG.mapFitFresh`（nil = 开；`/ehm mapfit fresh off` 回退成「本会话内按图记住」）。
local function smFitDropOnClose(mk)
  mk = tostring(mk or SMFIT.mapKey or "?")
  -- ★身份已经换了（这一拍同时换了图）⇒ 不动手：换图那条路有自己的作废（smFitNewMap），两边都写会打架
  if mk ~= tostring(SMFIT.mapKey or "?") then return false end
  local had, nBack, backOK = smFitRecCount(), 0, true
  if SMFIT.wrote == true then
    local ok, n, _miss, bad = pcall(smFitRestore, true) -- ① 先还回自然档（quiet：细节不进聊天框，下面一句话总说）
    if ok then
      nBack, backOK = tonumber(n) or 0, (tonumber(bad) or 0) == 0
    else
      backOK = false
    end
  end
  -- ★★还回之后**自己再严格验一遍**（不能只信 `smFitRestore` 的「两种读回口径都认」）：
  --   本函数只在 `needFold == true`（读回 = **逻辑值本身**）那一档才会被调用 ⇒ 这一档里
  --   「读回 ≈ 原值 × es」**只可能**是客户端把我们的还回写盖掉了（几何还是折后的值）。
  --   ★为什么必须自己验：两种口径在数值上会长得一样（读回 70 既可能是「级联客户端还回成功」，
  --     也可能是「不级联客户端还回失败」）—— 只有按本档的口径严格比，才能把后者揪出来。
  local backBad = 0
  if backOK then
    local liveOk = true
    for _, it in ipairs(smFitTargets()) do
      local r = SMFIT.rec[it.key]
      if SMFIT.wroteKeys[it.key] == mk and type(r) == "table" and r.o == it.o then
        local okp, _p, _rel, _rp, vx, vy = pcall(it.o.GetPoint, it.o, 1)
        local okw, vw = pcall(it.o.GetWidth, it.o)
        local okh, vh = pcall(it.o.GetHeight, it.o)
        local good = okp and okw and okh and tonumber(vx) and tonumber(vy) and tonumber(vw) and tonumber(vh)
          and math.abs(tonumber(vx) - tonumber(r.x)) <= 0.75 and math.abs(tonumber(vy) - tonumber(r.y)) <= 0.75
          and math.abs(tonumber(vw) - tonumber(r.w)) <= 0.75 and math.abs(tonumber(vh) - tonumber(r.h)) <= 0.75
        if not good then liveOk = false end
      end
    end
    if not liveOk then backBad = 1 end
  end
  if (not backOK) or backBad > 0 then
    -- ★★安全阀：**还回自然档没成功** ⇒ **绝不清记录**（清了就等于把「折过的值」当原值，下次再折一次 = 缩两遍）
    smFitSay("关图（%s）：本图折过的几何**没能还回自然档**（写回后读回对不上）⇒ **保留原值记录、不清空**"
      .. "（清掉的话下次开图会把折后的值当原值 ⇒ 折两遍）", mk)
    return false
  end
  -- ② 清掉本图的原值（★只动本图：别的图的分桶一个都不碰）
  SMFIT.rec = {}
  SMFIT.recMap[mk] = {}
  SMFIT.wroteKeys, SMFIT.wrote = {}, false
  SMFIT.captured, SMFIT.capFails = false, 0
  SMFIT.capAge, SMFIT.capCalls, SMFIT.capSayN = 99, 0, 0
  -- ★1.75.5：**每次开图只报一次**的那几条标记一起归零（关图 = 本次开图的生命周期结束）
  SMFIT.saidLatch, SMFIT.saidFail, SMFIT.saidEmpty, SMFIT.saidFold = false, false, false, false
  -- ★窗口也要归零：关图时窗口可能还开着（那个块只在 `open` 时递减）⇒ 不归零的话下次开图会**少一段**自然档时间
  smFitHold = 0
  smFitSay("关图（%s）：按「关图即清空原值」删掉本图 %d 条原值、%d 个折过的几何已还回自然档 ⇒ **下次开图重新读一遍再缩放**",
    mk, had, nBack)
  return true
end

-- ★★★1.75.9：**开启时的叠加层准备**（顺序铁律：先探测/抓原值，再改缩放）。
--   ① 迁移掉不可信的老原值；② 只读探测「本客户端要不要我们折算」；
--   ③ 不需要折算（客户端自己会跟随）⇒ 顺手把**以前折过**的几何还回去，然后**一个几何都不碰**；
--   ④ 需要折算 ⇒ 此刻还没套默认缩放，正好在**自然档**抓原值（见 smFitCapture）。
local function smFitPrepare()
  smFitMigrate()
  -- ★1.75.13：先把**地图身份**对齐（换了图 ⇒ 旧记录当场作废；随后抓到的才是**本图**的几何）
  local mk0 = smMapKey()
  if mk0 and SMFIT.mapKey and mk0 ~= SMFIT.mapKey then
    pcall(smFitNewMap, mk0)
  elseif mk0 then
    SMFIT.mapKey = mk0
  end
  SMFIT.needFold = smFitDetect() -- 两种档都探一次（提示 / 取证 / auto 档的判据）
  if not smFitNeedFold() then
    -- ★只有**本会话真写过**才需要还回去（否则还原也是一次无谓的几何写 —— 「关掉零动作」的同族）
    if SMFIT.wrote == true then pcall(smFitRestore, true) end
    return false
  end
  pcall(smFitCapture)
  return true
end

-- 取证：开关 / 地图开没开 / es / 目标数 / 原值条数 / 本次改动 / burst 剩余
local function smFitDiag()
  local fr = _G["WorldMapDetailFrame"]
  local es = nil
  local esApi = nil
  if (type(fr) == "table" or type(fr) == "userdata") then
    local eff = smEffScale(fr)
    if tonumber(eff) and tonumber(eff) > 0 then es = tonumber(eff) end
    if type(fr.GetEffectiveScale) == "function" then
      local ok, v = pcall(fr.GetEffectiveScale, fr)
      if ok and tonumber(v) then esApi = tonumber(v) end
    end
  end
  local nList = table.getn(smFitTargets())
  local nOrig = smFitOrigCount()
  -- ★1.75.13：**地图身份 / 客户端叠加层条数 / 本图在用几个 / 本图我们写过几个**都要摊出来 ——
  --   「坐标丢失 + 全挤在左下」这一案的核心事实就是「原值属于哪张图、这张图到底用哪几个层」。
  local mkDiag = smMapKey() or SMFIT.mapKey or "?"
  local nOvDiag = smNumOverlays()
  local nUseDiag, nWroteDiag, nWaitDiag = 0, 0, 0
  for _, it in ipairs(smFitTargets()) do
    if smFitInUse(it.o) then
      nUseDiag = nUseDiag + 1
      -- 「等抓原值」= 本图在用的层里还没有会话记录的那些（★别复用 `ready`：那是折算后的「已适配数」，
      --   而且它声明在本行**下面** —— 1.75.5 实案就是这么炸的：`local` 之前引用 = 全局 nil ⇒ `%d` 收到 nil）
      if type(SMFIT.rec[it.key]) ~= "table" then nWaitDiag = nWaitDiag + 1 end
    end
  end
  for _, v in pairs(SMFIT.wroteKeys or {}) do if v == mkDiag then nWroteDiag = nWroteDiag + 1 end end
  P(string.format("地图身份=%s ｜ 客户端叠加层=%s ｜ 本图在用 %d / 非瓦片 %d ｜ 等抓原值 %d 个 ｜ 本图已写 %d 个 ｜ 原值共 %d 条（**会话内存**、按地图）",
    tostring(mkDiag), (nOvDiag ~= nil) and tostring(nOvDiag) or "读不到", nUseDiag, nList, nWaitDiag, nWroteDiag, nOrig))
  -- ★★★1.75.5：抓原值的**尝试 / 读失败**必须摊出来 —— 「静默读不到」正是这次拖了三轮的元凶
  P(string.format("抓原值：尝试 %d 次 ｜ 本图记录 %d 条 ｜ 读失败 %d 次 ｜ 落闩=%s ｜ 归一系数按 %s",
    tonumber(SMFIT.capCalls) or 0, (function() local k = 0 for _ in pairs(SMFIT.rec or {}) do k = k + 1 end return k end)(),
    tonumber(SMFIT.capFails) or 0, SMFIT.captured and "是" or "否",
    (SMFIT.needFold == true) and "读回=逻辑值（不归一）" or "读回=逻辑×es（÷es 归一）"))
  if (type(fr) == "table" or type(fr) == "userdata") then
    P(string.format("缩放量对照：**采用值(父链连乘)**=%.3f ｜ 旧 API 读回=%s ｜ 配置里的设置值 scale=%.3f",
      tonumber(es) or 0, (esApi and string.format("%.3f", esApi)) or "?", tonumber(SM_CFG.scale) or 1))
    P("　★`GetEffectiveScale` 在本客户端**会滞后**（第一次开启读 1.00、关开一次后读 0.70）⇒ 折算一律用**父链连乘**；旧 API 的数字只作对照")
  end
  local changed, ready = 0, 0
  if smFitOn() and es and es > 0.01 then changed, ready = smFitApply(es, true) end
  P(string.format("叠加层适配：开关=%s（默认开） · 地图开=%s · es=%s · 非瓦片纹理 %d 个 · 原值 %d 条 · 本次改 %d / 已适配 %d · burst 剩余 %.1fs",
    smFitOn() and "开" or "关", tostring(featOpenNow()),
    es and string.format("%.3f", es) or "?", nList, nOrig, changed, ready, tonumber(SMFIT.burst) or 0))
  -- ★★★1.75.9：**折算判据必须摊开**（「本客户端要不要我们折算」是这一案的核心事实，不许藏在代码里）
  P("折算策略 = " .. smFitModeLabel() .. "（/ehm mapfit mode fold|auto|nofold 可切）")
  if SMFIT.needFold == nil then
    P("探测结论：**还没探过**（开启时/开图后各探一次）")
  else
    P("探测结论：" .. (SMFIT.needFold and "本客户端**不会**自动级联 ⇒ 需要按 es 折算（原值取自自然档）"
      or "本客户端**会**自动级联 ⇒ 折算就是第二遍（策略 auto 时我们不碰）"))
  end
  P("本次实际动作 = " .. (smFitNeedFold() and "折算（按 es 写几何）" or "**不折算**（一个几何都不碰）")
    .. " ｜ 取证行数 = " .. tostring((type(SM_CFG.mapFitTrace) == "table") and table.getn(SM_CFG.mapFitTrace) or 0)
    .. "（/ehm mapfit trace 可打出来）")
  return changed
end

-- ★★★1.75.13 新增（用户：「排查工具箱->缩放大地图->探索层额外处理异常…**先别修改**，分析问题」⇒ 先给只读取证口）：
--   `/ehm mapfit dump` 的**内容生成口**（命令与测试同源；测试直接读它，不必解析聊天框）。
--   每行都是**只读**读数：本模块的判定（显示 / 贴图 / 本图在用）+ 我们记过/写过什么 + **客户端自己的叠加层真值**
--   （`GetMapInfo` / `GetNumMapOverlays` / `GetMapOverlayInfo`）⇒「谁写的、该是多少」一眼可判。
local function smFitDumpLines()
  local out = {}
  local function add(s) table.insert(out, s) end
  local mk = smMapKey() or SMFIT.mapKey or "?"
  local a, b, c = smMapInfo()
  local nOv = smNumOverlays()
  add(string.format("清单：地图身份=%s（GetMapInfo=%s / %s / %s）｜ 客户端叠加层=%s ｜ 策略=%s ｜ es=%s ｜ 本图已开 %.2fs",
    tostring(mk), tostring(a), tostring(b), tostring(c),
    (nOv ~= nil) and tostring(nOv) or "读不到", smFitModeLabel(),
    tostring(SMFIT.es), tonumber(SMFIT.mapAge) or 0))
  -- ★★★1.75.5（用户报障「每次 /reload 之后探索层缩放都不生效，只有关/开一次缩放大地图才生效」）：
  --   「记录」和「纹理上的**活值**」必须**同时**摊出来 —— 缺了活值就分不清是哪条路坏：
  --     · 记录 ≈ 活值 ≈ 客户端真值×0.7 ⇒ 抓原值时那次临时 `SetScale(1)` **没让读回跟着变**（折出来会是 0.49×）；
  --     · 记录 ✓ 但「本图已写=否」 ⇒ 折算那一步压根没跑（时间门/落闩/es 瞬态）；
  --     · 记录与活值都 ✓ ⇒ 我们写对了，问题在客户端随后又重排（那就该走 nofold 那一档）。
  local nRec, nWrote, nWait, nUse = 0, 0, 0, 0
  for _, v in pairs(SMFIT.rec or {}) do if type(v) == "table" then nRec = nRec + 1 end end
  for _, v in pairs(SMFIT.wroteKeys or {}) do if v == mk then nWrote = nWrote + 1 end end
  local frD = _G["WorldMapDetailFrame"]
  for _, it in ipairs(smFitTargets()) do
    if smFitInUse(it.o) then
      nUse = nUse + 1
      if type(SMFIT.rec[it.key]) ~= "table" then nWait = nWait + 1 end
    end
  end
  local chain = nil
  if type(frD) == "table" or type(frD) == "userdata" then chain = smEffScale(frD) end
  add(string.format("口径：外框缩放(父链连乘)=%s ｜ 设置值 scale=%s alpha=%s ｜ 本图在用=%d ｜ 本图会话记录=%d 条 ｜ 等抓原值=%d 个 ｜ 本图已写=%d 个 ｜ 抓原值尝试=%d 读失败=%d",
    (tonumber(chain) and string.format("%.3f", chain)) or "读不到", tostring(SM_CFG.scale), tostring(SM_CFG.alpha),
    nUse, nRec, nWait, nWrote, tonumber(SMFIT.capCalls) or 0, tonumber(SMFIT.capFails) or 0))
  local list = smFitTargets()
  for i, it in ipairs(list) do
    local o = it.o
    local shown, tex = "读不到", "读不到"
    if type(o.IsShown) == "function" then
      local ok, v = pcall(o.IsShown, o)
      if ok then shown = v and "显示" or "隐藏" end
    end
    if type(o.GetTexture) == "function" then
      local ok, v = pcall(o.GetTexture, o)
      if ok then tex = (v == nil or v == "") and "空" or tostring(v) end
    end
    local r = SMFIT.rec[it.key]
    local rtxt = "无"
    if type(r) == "table" then rtxt = string.format("(%.0f,%.0f) %.0fx%.0f", r.x, r.y, r.w, r.h) end
    -- ★1.75.5：**活值**（纹理此刻的读回几何）—— 与「记录」「客户端真值」三者对照才能定案
    local ltxt = "读不到"
    local okp, _p, _rel, _rp, lx, ly = pcall(o.GetPoint, o, 1)
    local okw, lw = pcall(o.GetWidth, o)
    local okh, lh = pcall(o.GetHeight, o)
    if okp and okw and okh and tonumber(lx) and tonumber(ly) and tonumber(lw) and tonumber(lh) then
      ltxt = string.format("(%.0f,%.0f) %.0fx%.0f", tonumber(lx), tonumber(ly), tonumber(lw), tonumber(lh))
    end
    add(string.format("  %d) %s：%s ｜ 贴图=%s ｜ 本图在用=%s ｜ 活值=%s ｜ 记录=%s ｜ 本图已写=%s",
      i, tostring(it.key), shown, tex, smFitInUse(o) and "是" or "否", ltxt, rtxt,
      (SMFIT.wroteKeys[it.key] == mk) and "是" or "否"))
  end
  if table.getn(list) == 0 then
    add("  （WorldMapDetailFrame 下没有非瓦片纹理：地图没开，或客户端还没建这批纹理）")
  end
  if nOv and nOv > 0 and type(GetMapOverlayInfo) == "function" then
    for i = 1, nOv do
      local ok, tn, w, h, ox, oy = pcall(function() return GetMapOverlayInfo(i) end)
      if not ok then
        add(string.format("  客户端第 %d 条叠加层：读不到（GetMapOverlayInfo 失败）", i))
        break
      end
      add(string.format("  客户端叠加层 %d：%s %sx%s @(%s,%s)", i, tostring(tn), tostring(w), tostring(h), tostring(ox), tostring(oy)))
    end
  else
    add("  客户端叠加层清单：读不到（GetNumMapOverlays/GetMapOverlayInfo 不可用，或本图 0 条）")
  end
  add("  口径：显示/贴图/在用 = 本模块的**只读**判定（「本图在用=否」的层我们一个几何都不碰）；"
    .. "记录 = **本会话内存**里本图的原值（★定位信息不落存档：客户端每次开图都会自己重摆）；本图已写 = 本次会话我们真写过的层")
  -- ★1.75.5：抓原值的**专属有界环**（最近 10 次尝试；随存档落盘 ⇒ 日志环被刷掉也能事后定案）
  local capRing = SM_CFG.mapFitCapLog
  if type(capRing) == "table" and table.getn(capRing) > 0 then
    add("  抓原值历史（最近 " .. table.getn(capRing) .. " 次，最旧→最新）：")
    for i = 1, table.getn(capRing) do add("    " .. tostring(capRing[i])) end
  else
    add("  抓原值历史：**空**（本次会话还没尝试过抓原值 —— 地图没开过，或还没走到那一步）")
  end
  return out
end

-- ★★★1.75.5（用户指定「本办法」）：**手动适配 = 一条调试命令、全过程逐条打印**
--   用户原话：「缩放功能开启的情况下, 游戏首次载入, 可以做个调试命令执行. 打开地图, 等待2s, 获取原值.
--   打印原值, 应用缩放. 打印缩放信息. 这样的调整过程.」
--   ★为什么要有它：自动时序依赖客户端的开图时机，出问题时**看不出卡在哪一步**；手动过程完全确定：
--     ① 开图（`ShowUIPanel`；本项目纪律：开图绝不用 Toggle）→ ② 外框**置回自然档 1.00**、等 2 秒让版式稳定
--     → ③ 读原值（**不翻转、不归一**，读到的就是原值）并逐条打印 → ④ 套缩放并打印（设置值/自身 GetScale/父链连乘）
--     → ⑤ 折算并逐条打印（原值 → 写入）。★期间 `smFixActive` 让**整段自动逻辑让位**（否则会被抢写缩放）。
local SM_FIX = { t = 0 }
local function smFixOut(s)
  local out = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
  pcall(out, "[简易地图] " .. tostring(s))
  mfLog("[手动适配] %s", tostring(s)) -- 同时进取证环/日志环 ⇒ 事后读存档就能看到每一步
end

-- ③④⑤ 三步：读原值 → 打印 → 套缩放 → 打印 → 折算 → 打印（★由计时帧在等满 2 秒后调用）
local function smFixDoCapture()
  -- ★重入闸（计时帧与「挂不上 OnUpdate 就当场跑」两条路只许走一条）
  if SM_FIX.done then return 0 end
  SM_FIX.done = true
  local mk = smMapKey() or SMFIT.mapKey or "?"
  smFitBindMap(mk)
  local n, fails = 0, 0
  smFixOut("第3步 读原值（外框已在自然档、且已等满 2s ⇒ 客户端版式稳定；**不翻转、不归一**）")
  for _, it in ipairs(smFitTargets()) do
    if smFitInUse(it.o) then
      local o = it.o
      local okp, p, rel, rp, x, y = pcall(o.GetPoint, o, 1)
      local okw, w = pcall(o.GetWidth, o)
      local okh, h = pcall(o.GetHeight, o)
      if okp and p and okw and okh and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h) then
        SMFIT.rec[it.key] = { o = o, idx = it.key, name = it.name, p = tostring(p),
          rel = smRelName(rel), relObj = rel, rp = smRelName(rp), from = "fixnow",
          x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h), map = mk }
        n = n + 1
        -- ★锚点名字：`smRelName` 只认**帧对象**，相对**点**（"TOPLEFT" 这种字符串）会给 nil ⇒ 打印成 `-`
        --   （★别把 nil 丢给 `%s`：本客户端是 Lua 5.1，`string.format("%s", nil)` 会**直接抛错**打不出这一行）
        local reln, rpn = smRelName(rel), smRelName(rp)
        smFixOut(string.format("第3步  原值 %s = (%.1f,%.1f) %.1f×%.1f ｜ 锚 %s/%s/%s",
          tostring(it.key), tonumber(x), tonumber(y), tonumber(w), tonumber(h),
          tostring(p), reln or "-", rpn or "-"))
      else
        fails = fails + 1
        smFixOut(string.format("第3步  读不到 %s（GetPoint=%s ｜ GetWidth=%s ｜ GetHeight=%s）",
          tostring(it.key), tostring(okp), tostring(okw), tostring(okh)))
      end
    end
  end
  SMFIT.captured = (n > 0)
  smFixOut(string.format("第3步 完成：原值 %d 条（读不到 %d 条）", n, fails))
  -- ④ 套缩放 + 打印
  smFitHold = 0
  pcall(featApplyScale, tonumber(SM_CFG.scale) or 1)
  local own, chain = "?", "?"
  local wm = featWm()
  if wm then
    local ok, v = pcall(wm.GetScale, wm)
    if ok then own = string.format("%.3f", tonumber(v) or 0) end
  end
  -- ★父链连乘可能踩到「父级不是帧」的脏环境（`cur.GetScale` 的取值在 pcall **外面**求值 ⇒ 会真抛错）
  --   ⇒ 这一句必须自己带 pcall，否则第 4 步抛错会把「第 5 步 + 放掉让位标记」整段吃掉。
  local fr = _G["WorldMapDetailFrame"]
  if type(fr) == "table" or type(fr) == "userdata" then
    local oke, e = pcall(smEffScale, fr)
    if oke and tonumber(e) then chain = string.format("%.3f", e) end
  end
  smFixOut(string.format("第4步 已套缩放：设置值=%.2f ｜ 自身 GetScale=%s ｜ 父链连乘=%s", tonumber(SM_CFG.scale) or 1, own, chain))
  -- ⑤ 折算 + 打印
  local es = tonumber(chain)
  if es and es > 0 then
    local changed, ready = smFitApply(es, true)
    smFixOut(string.format("第5步 折算：es=%.3f ⇒ 写入 %d 个 / 已对齐 %d 个", es, changed, ready))
    for _, it in ipairs(smFitTargets()) do
      local r = SMFIT.rec[it.key]
      if type(r) == "table" and smFitInUse(it.o) then
        smFixOut(string.format("第5步   %s 原值(%.1f,%.1f %.1f×%.1f) → 写入(%.1f,%.1f %.1f×%.1f)%s",
          tostring(it.key), r.x, r.y, r.w, r.h, r.x * es, r.y * es, r.w * es, r.h * es,
          (SMFIT.wroteKeys[it.key] == mk) and " ★本次已写" or "（判为已对齐，未写）"))
      end
    end
  else
    smFixOut("第5步 折算**跳过**：读不到父链缩放（上面第 4 步的「父链连乘」是 ?）")
  end
  smFixActive = false
  smFixOut("手动适配**结束**（以上就是完整调整过程；若仍不对，把这一整段发我）")
  return n
end

-- ★★★1.75.5：兜底跑第 3~5 步 —— **无论成败都放掉让位标记** 并如实报错。
--   为什么必须有它：`smFixActive` 是我们自己关掉自动逻辑的开关，一旦哪一步抛错而没人放掉它，
--   整个「探索层适配」就**永久静默失效**（看着像功能坏了，其实是让位没收）。这类「自己关死自己」的坑本项目有先例。
local function smFixRunCapture()
  local okD, errD = pcall(smFixDoCapture)
  smFixActive = false
  if not okD then smFixOut("手动适配**中途出错**（后面几步没跑到）：" .. tostring(errD)) end
  return okD
end

-- ①②步 + 起计时：由 `/ehm fitnow`（别名 适配/修正）调用
local function smFixNow()
  if not EVAL_SM_ENABLED() then
    smFixOut("前置：**「缩放大地图」没开启** ⇒ 先在工具箱里勾上它，再跑本命令")
    return false
  end
  smFixActive = true
  SM_FIX.t = 0
  SM_FIX.done = false
  smFixOut("第1步 前置：模块=开 ｜ 地图=" .. (featOpenNow() and "开" or "关") ..
    " ｜ 当前 设置值 scale=" .. tostring(SM_CFG.scale) .. " alpha=" .. tostring(SM_CFG.alpha))
  if not featOpenNow() then
    local wm = _G["WorldMapFrame"]
    if type(ShowUIPanel) == "function" and wm then
      pcall(ShowUIPanel, wm)
      smFixOut("第1步 地图没开 ⇒ 已调 `ShowUIPanel(WorldMapFrame)` 打开它")
    else
      smFixOut("第1步 地图没开、且取不到 ShowUIPanel/WorldMapFrame ⇒ 请手动打开地图后重跑本命令")
    end
  end
  pcall(featApplyScale, 1)
  local own = "?"
  local wm2 = featWm()
  if wm2 then
    local ok, v = pcall(wm2.GetScale, wm2)
    if ok then own = string.format("%.3f", tonumber(v) or 0) end
  end
  smFixOut("第2步 已把外框缩放置回**自然档 1.00**（读回自身 GetScale=" .. own .. "），等 2.0 秒让客户端版式稳定…")
  -- 计时帧**懒建**（本项目纪律：载入期零副作用；没有帧也照样把三步走完）
  local par = _G["UIParent"] or _G["WorldFrame"]
  local f = _G["EH_SM_FITFIX"]
  if (not f) and type(CreateFrame) == "function" and par then
    f = CreateFrame("Frame", "EH_SM_FITFIX", par)
    _G["EH_SM_FITFIX"] = f
  end
  if not f or type(f.SetScript) ~= "function" then
    smFixOut("第2步 **没有可用的计时帧** ⇒ 立刻执行第 3~5 步（不等待）")
    smFixRunCapture()
    return true
  end
  local okSet = pcall(f.SetScript, f, "OnUpdate", function()
    local dt = tonumber(arg1) or 0.05
    SM_FIX.t = (tonumber(SM_FIX.t) or 0) + dt
    if SM_FIX.t >= 2.0 then
      pcall(f.SetScript, f, "OnUpdate", nil)
      smFixRunCapture()
    end
  end)
  if not okSet then
    -- ★挂不上就当场走完（否则 `smFixActive` 永远为真 = 自动逻辑被永久让位，那就成了新故障）
    smFixOut("第2步 计时帧**挂不上 OnUpdate** ⇒ 立刻执行第 3~5 步（不等待）")
    smFixRunCapture()
  end
  return true
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
      -- ★★★1.75.7（用户排查：「未开启缩放大地图时，会不会还在监听探索层的缩放操作」）——**会**，而且不只是监听：
      --   实测（修前：模块关闭 + 点 10 拍 tick）：叠加层几何被写了 **8 次**，355/-320/215×215 被折成
      --   248.5/-224/150.5×150.5（×0.7），还记下 2 条原值。根因两条：
      --     ① 这段 tick 是**载入期无条件建**的 ⇒ 关掉开关它照样每帧跑；
      --     ② ④ 只受 smFitOn()（**默认开**）管，③「开图保持」那一段**压根没看总开关**。
      --   ⇒ 关闭时**整段免打扰**：连 IsShown / GetEffectiveScale 都不读（那正是「监听探索层缩放」），
      --     一个几何都不碰（项目纪律：关掉零动作）。
      --   ★「关掉时把已经折算过的几何还回去」改由 EVAL_SM_SET(false) 那侧**当场**做（见那里）——
      --     旧注释把这件事寄托在「常驻 tick 兜还原」上，代价就是关掉开关后照跑照折；现在正面解决。
      if not EVAL_SM_ENABLED() then
        FEAT.applied = false
        SMFIT.open, SMFIT.es, SMFIT.burst = false, nil, 0
        return
      end
      -- ★★★1.75.5（用户指定「本办法」）：**手动适配进行中 ⇒ 整段自动逻辑让位** —— 由 `/ehm fitnow`
      --   那条调试命令按「开图 → 置自然档 → 等 2s → 读原值 → 套缩放 → 折算」一步步走完并**逐条打印**。
      --   ★必须挡在**最前面**（连「每帧守缩放」「抓原值窗口」都不参与），否则手动过程会被自动逻辑抢写缩放，
      --     那就又变成「看不出卡在哪一步」。
      if smFixActive then return end
      local dt = tonumber(arg1) or 0.05
      acc = acc + dt
      accFit = accFit + dt
      -- ① 每帧廉价探测：地图开没开 + **真有效缩放**（各一次 pcall，别做几何扫描）
      local open = featOpenNow()
      -- ★★★1.75.5：**地图身份对齐必须排在「抓原值窗口」之前** —— `smFitNewMap` 会把窗口清零（换图要重新判定），
      --   若它排在窗口块之后，就会在**同一拍**把刚开的窗关掉、紧接着的折算分支又会去写缩放
      --   （组 254⑧「取原值期间一个缩放都不写」实测抓到过这一次写入）。
      local mkNow = smMapKey()
      if mkNow and mkNow ~= SMFIT.mapKey then pcall(smFitNewMap, mkNow) end
      -- ★★★1.75.5（**用户要求**）：「每次地图关闭都把原值数据清理、不要保存；每次打开地图都重新获取原值、重新缩放大地图」。
      --   ⇒ 清空放在**关图那一刻**（地图不可见、不闪、也不跟客户端的版式计算抢），开图时记录天然是空的，
      --     直接走既有的「本图还没有原值 ⇒ 先不缩放 → 读原值 → 落闩 → 套缩放」= 重新获取 + 重新缩放。
      --   ★门：总开关开 + 叠加层适配开 + **折算档**（nofold / auto 判定不折算时我们根本不读原值，也就不清）。
      --   ★必须在「抓原值窗口」块**之前**（否则本拍窗口会按还没清的旧记录判定成「已齐」而不开）。
      local closedNow = (not open) and SMFIT.open
      if closedNow and smFitOn() and smFitFreshOn() and smFitNeedFold() then pcall(smFitDropOnClose, SMFIT.mapKey) end
      -- ★★★1.75.5（用户设计，采纳）：「**本图还没有原值 ⇒ 先不缩放**，在自然档读原值，抓完再缩放」。
      --   为什么这样最好：抓原值时**不用翻转外框**（翻转会惊动客户端 ⇒ 读不到）、也**不用做读回÷es 的归一**
      --   （外框还是 1.00 ⇒ 读回就是原值，不押注任何口径）。
      --   ★只在**真正需要**时开窗口（本图会话记录一条都没有）⇒ 有记录时零延迟、行为与原来完全一样；
      --   ★窗口**有界**（SMFIT_HOLD_SEC）：抓到立刻收（同一拍套缩放），到点没抓到也收（先缩放、稍后补抓）。
      --   ★★**必须排在下面那道「每帧守缩放」之前**（顺序即判据）：反了的话开窗那一拍会先被守缩放写一次。
      if open then
        if (tonumber(smFitHold) or 0) > 0 then
          smFitHold = math.max(0, (tonumber(smFitHold) or 0) - dt)
          if SMFIT.captured then smFitHold = 0 end
          if smFitHold == 0 then
            pcall(featApplyScale, tonumber(SM_CFG.scale) or 1)
            -- ★1.75.5（用户要求「获取原值的地方打印出来」）：窗口收口改成**看得见**的一行（每图最多一次）
            --   ★★措辞必须与**实际读到的条数**挂钩：真机出过「0 条也报『已抓到原值』」⇒ 用户完全被误导
            --     （那次是因为客户端还没摆叠加层，而旧代码把空候选当成「已齐」落了闩）。
            local nRecWin = smFitRecCount()
            -- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：**成功**那一句不再出口
            --   （成功由「抓原值：已读到 N 条 ⇒ 落闩」那一条统一报，避免同一件事两行）；
            --   只有**真的没读到**才出声（一次），详细档照旧两行都打。
            if SMFIT.captured and nRecWin > 0 then
              smFitSayV("抓原值窗口结束：**已抓到原值 %d 条** ⇒ 现在套缩放 scale=%s（此前一直是自然档，读到的就是原值）",
                nRecWin, tostring(SM_CFG.scale))
            elseif not SMFIT.saidEmpty then
              SMFIT.saidEmpty = true
              smFitSay("抓原值：窗口结束仍**没读到原值**（本图记录 %d 条 —— 客户端还没把叠加层摆出来）⇒ 先缩放，之后 1 秒一次继续补抓",
                nRecWin)
            else
              smFitSayV("抓原值窗口结束：**还没读到原值**（记录 %d 条）⇒ 继续 1 秒一次补抓", nRecWin)
            end
          end
        elseif smFitNeedFold() and (not SMFIT.captured) and next(SMFIT.rec or {}) == nil then
          smFitHold = SMFIT_HOLD_SEC
          -- ★同上：开窗这一行是「本图还没原值 ⇒ 先不缩放」的唯一可见证据（每图一次）
          -- ★条件里带 `smFitNeedFold()`：**不折算的档**根本不会读原值 ⇒ 不许把地图按在自然档上白等 2 秒
          smFitSayV("抓原值窗口开启：本图（%s）还没有原值 ⇒ **地图先停在自然档、暂不缩放**，最多 %.1fs 内读一次（读到立刻套缩放）",
            tostring(SMFIT.mapKey or "?"), SMFIT_HOLD_SEC)
        end
      end
      -- ★★★1.75.5：**每帧守住地图缩放**（顺序：排在「抓原值窗口」**之后** —— 窗口期本轮不写，`featApplyScale` 自己让位）。
      --   真机日志实证 `折算暂缓：… 自身 GetScale=1.000 ｜ 父帧=有` ⇒ 是**客户端自己**把地图帧缩放重置回 1.0；
      --   旧写法只在 0.2s 节拍里守 ⇒ 开图/换图后有一段「没缩放」窗口（用户报的「载入后缩放异常」）。
      --   读一次 `GetScale` 很便宜、`featApplyScale` 自带「同档不重写」⇒ **只有漂了才写**。
      if open then pcall(featApplyScale, tonumber(SM_CFG.scale) or 1) end
      local fr = _G["WorldMapDetailFrame"]
      local es = nil
      if (type(fr) == "table" or type(fr) == "userdata") then
        -- ★★★1.75.9：**不读 `GetEffectiveScale`** —— 真机实测它在本客户端**滞后**：
        --   第一次开启读到 1.00（于是那一次等于没折算 = 用户看到的「正常开启不生效」），
        --   关一次再开才读到 0.70 ⇒ 用户原话「**在重新打开关闭之后才能正确读取到缩放**」。
        --   ⇒ 改用**沿父链连乘**（`smEffScale`：`WorldMapFrame 0.70 × DetailFrame 1.00 = 0.70`），
        --     它读的是我们自己刚写进去的 `SetScale`，写完立刻就是最新值、不会滞后。
        local eff = smEffScale(fr)
        if tonumber(eff) and tonumber(eff) > 0 then es = tonumber(eff) end
        if not es and type(fr.GetEffectiveScale) == "function" then
          local ok, v = pcall(fr.GetEffectiveScale, fr) -- 兜底：父链读不到时才用（可能滞后）
          if ok and tonumber(v) then es = tonumber(v) end
        end
      end
      -- ② 过渡（开图 / es 变化）⇒ 进爆发期，并把节拍**顶满**（下一帧就动手，不等 0.1s）
      local justOpened = (open and not SMFIT.open)
      -- ★1.75.9：**闩住「刚开图」这个信号** —— ③ 是 0.2s 节拍，若开图那一拍恰好不在节拍点上，
      --   光靠 `justOpened` 会漏掉这次应用（于是又变成「要开关一次才生效」）。
      if justOpened then SMFIT.pendingApply = true end
      if justOpened then SMFIT.burst = SMFIT_BURST_SEC accFit = 1e9 end
      if es and esCache and math.abs(es - esCache) > 0.001 then SMFIT.burst = SMFIT_BURST_SEC accFit = 1e9 end
      if not open then SMFIT.burst = 0 end
      SMFIT.open, SMFIT.es = open, (es or SMFIT.es)
      esCache = es or esCache
      if (tonumber(SMFIT.burst) or 0) > 0 then SMFIT.burst = math.max(0, SMFIT.burst - dt) end
      -- ③ 既有的「开图保持」节拍（0.2s；★保持原行为不动）
      if acc >= 0.2 then
        acc = 0
        if open then
          -- ★★★1.75.9（用户要求：「开启缩放默认设置 0.7 / 透明度 0.7，不管有没打开；**打开就生效**，不打开就不生效」）：
          --   **每次开图那一刻无条件幂等应用一次**。旧写法只在 `not FEAT.applied` 时应用，而开启时若地图是**关的**，
          --   那一位已经是 true ⇒ **开图那一次反而不应用**（用户就得多开/关一次才生效）。`featApply` 本身幂等，重复调无副作用。
          if SMFIT.pendingApply or not FEAT.applied then
            featApply()
            FEAT.applied = true
            SMFIT.pendingApply = false
          end
          featKeep() -- ★开图期间持续保持（黑幕重藏 + 透明度/缩放漂移校准）
        elseif FEAT.applied then
          FEAT.applied = false
        end
      end
      -- ④ 叠加层适配：走到这里说明**总开关是开的**（本函数开头已闸）⇒ 这里只需看子开关 mapFit（nil = 默认开）。
      --   ★关闭时的几何还原由 EVAL_SM_SET(false) 当场做（不再靠本 tick 兜）。
      if not smFitOn() then return end
      if not open or not es or es <= 0 then
        SMFIT.mapAge = 0 -- 地图关着 ⇒ 计时归零（下次开图重新等版式稳定）
        return
      end
      -- ★★★1.75.5：地图身份的对齐已经**上移到本函数开头**（必须早于「抓原值窗口」）—— 这里不再重复做。
      SMFIT.mapAge = (tonumber(SMFIT.mapAge) or 0) + dt
      -- ★★★1.75.9：折算策略（默认折算；`auto` 才先探测）。探测结论只读、只影响 auto 档。
      if smFitMode() == "auto" and SMFIT.needFold == nil then SMFIT.needFold = smFitDetect() end
      if not smFitNeedFold() then return end
      -- ★原值必须在**自然档**抓一次（见 smFitCapture），绝不能拿已折过的值当原值。
      --   ★★★1.75.13：还要**等客户端把本图版式摆稳**（SMFIT_SETTLE）—— 开图那一瞬抓到的往往是
      --   「还没布局 / 本图不用」的残留几何（真机存档里 6 条原值完全相同就是这么来的）。
      --   ★★★1.75.5：再加一道**有界重试**门（`capAge`/`SMFIT_CAP_GAP`）—— 抓原值内部会把缩放临时按 1，
      --   不落闩时**每帧**重跑就是 1.75.4 那场事故（地图缩放每帧抖一次 + 取证环 1 秒刷满 + 折算刷屏）。
      if SMFIT.captured then
        SMFIT.capAge = 99 -- 已落闩 ⇒ 下次换图时又立刻可抓
      else
        SMFIT.capAge = (tonumber(SMFIT.capAge) or 99) + dt
        if SMFIT.mapAge >= SMFIT_SETTLE and SMFIT.capAge >= SMFIT_CAP_GAP then
          SMFIT.capAge = 0
          pcall(smFitCapture)
        end
      end
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
    -- ★★★1.75.9（用户实测：载入后点开启 ⇒ 探索层缩两遍）：**先探测 + 抓原值，再改缩放**。
    --   顺序铁律「读原值 → 写新值」（1.74.31 组 206 的教训）—— 旧顺序是先 SetScale(0.7) 再在 tick 里记原值，
    --   而本客户端几何读回**含缩放** ⇒ 记下的原值已经是缩过的值，再折一次就是第二遍。
    --   ★`smFitPrepare()` 内部只读探测：客户端自己会级联 ⇒ 我们**一个几何都不碰**（并把以前折过的还回去）。
    SMFIT.needFold = nil   -- 每次开启重新探测（客户端行为可能跟着地图状态变）
    pcall(smFitPrepare)
    mfLog("开关 ON：策略=%s 探测=%s 抓原值=%d 条 缓存记录=%d 条", smFitMode(),
      (SMFIT.needFold == nil) and "未判定" or tostring(SMFIT.needFold ~= false),
      smFitOrigCount(),
      (function() local k = 0 for _ in pairs(SMFIT.rec or {}) do k = k + 1 end return k end)())
    -- ★★★1.74.36-3：**开启即套默认档**（缩放 0.7 / 透明度 0.7 / GUI重开 不启用）——用户原话
    --   「开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」；先套默认值，再应用/就位。
    local a, s = smApplyDefaults()
    pcall(featKeep)   -- 事件帧就位（开图时自动应用）
    pcall(featApply)  -- 立刻应用一次
    -- ★★★1.75.7：**应用过就要记下来**（FEAT.applied）——关闭路径拿它判「到底动没动过地图纹理」。
    --   旧版只有 tick 那一条路会置这一位 ⇒ 开启后立刻关闭时，关闭路径会以为「没动过」而跳过复位。
    FEAT.applied = true

    P(string.format("简易地图：已启用（默认档：缩放 %.2f / 透明度 %.2f / GUI重开 %s；面板或 Shift/Ctrl+滚轮可再调）%s",
      s, a, smReopenOn() and "开" or "关",
      featOpenNow() and "；当前地图=开 ⇒ 已立刻生效" or "；当前地图=关 ⇒ **开图即生效**（默认档已写入配置）"))
    -- ★★★1.75.5（**用户要求**「获取原值的地方添加日志信息，打印出来」）：
    --   真机实证（用户截图：**重开后没重新打开地图**那一次）聊天框里一条抓原值都没有 ⇒ 用户无法判断是「没抓」还是「抓了没成」。
    --   所以这里把**抓原值的状态与下一步**当场说清（尤其是地图没开时：抓原值必须等地图打开，这是唯一的原因）。
    P(string.format("　抓原值：本图记录 %d 条 ｜ 落闩=%s ｜ 地图=%s%s", smFitRecCount(),
      SMFIT.captured and "是" or "否", featOpenNow() and "开" or "关",
      featOpenNow() and string.format(" ⇒ 等版式稳定 %.1fs 后读一次原值（读不到 1 秒后重试）", SMFIT_SETTLE)
        or string.format(" ⇒ **要等你把地图打开**才读得到（打开后先等 %.1fs 再读自然档原值；这期间地图保持 %.2f 缩放）",
          SMFIT_SETTLE, s)))
    -- ★★★1.75.5：策略是非默认档时**当场说清**（否则用户会以为「开关坏了」）。
    --   实案：`mapFitMode = "nofold"` 落存档 + 主开关**不复位策略** ⇒ 用户怎么关开都「始终不生效」，却看不到原因。
    if smFitMode() ~= "fold" then
      P("　★★注意：折算策略当前 = " .. smFitModeLabel() ..
        (smFitMode() == "nofold" and " ⇒ 叠加层适配**一个几何都不碰**（这就是「关开都不生效」的原因）"
          or " ⇒ 是否折算听探测结论") ..
        "；恢复默认档：/ehm mapfit mode fold（本档只在本会话有效，/reload 后自动回默认）")
    end
  else
    -- ★★★1.75.7 关闭 = 把**我们改过的**东西还回去（用户要求：「未开启地图缩放功能不需要进行任务纹理的操作」）。
    --   ★★判据 = **确实动过**才写：FEAT.applied（我们应用过）或会话里还留着原值记录。
    --     从未开启过 ⇒ **一个地图纹理都不碰**（连透明/缩放都不写 1 —— 它们本来就没被我们改过）。
    --   顺序：先还原叠加层几何（读首次折算时记下的原值）→ 再复位透明度/缩放/位置 → 最后如实播报。
    local nOrig230 = smFitOrigCount()
    local touched230 = (FEAT.applied == true) or (nOrig230 > 0)
    mfLog("开关 OFF：策略=%s 动过=%s（applied=%s 原值=%d 条）", smFitMode(), tostring(touched230),
      tostring(FEAT.applied == true), nOrig230)
    if not touched230 then
      FEAT.applied = false
      P("简易地图：已停用（**本就没启用过 ⇒ 没动过任何地图纹理**；透明度/缩放保持原样）")
    else
      local nRestore230, nMiss230, nBad230 = 0, 0, 0
      local wrote230 = (SMFIT.wrote == true)
      if wrote230 and type(smFitRestore) == "function" then
        local okR, aR, bR, cR = pcall(smFitRestore, true)
        if okR then nRestore230, nMiss230, nBad230 = tonumber(aR) or 0, tonumber(bR) or 0, tonumber(cR) or 0 end
      end
      FEAT.applied = false
      SMFIT.wrote = false -- ★1.75.9：这一轮写过的痕迹清了（下轮重新记）
      pcall(featReset)  -- 透明/缩放/位置复位
      -- ★★★1.75.9：**把装上去的钩子/帧收干净**（用户要求：「开启/关闭要做好探索层纹理的事件清理」）。
      pcall(featTeardown)
      P("简易地图：已停用（已复位：透明度 1 / 缩放 1 / 位置回屏幕中央；坐标行/拖拽柄已收起"
        .. (wrote230 and ((nRestore230 > 0) and ("；叠加层几何已还原 " .. nRestore230 .. " 项") or "；叠加层几何**没有原值可还原**")
            or "；叠加层几何**我们一次都没写过** ⇒ 没动它")
        .. ((nMiss230 > 0) and ("；" .. nMiss230 .. " 项没有原值 ⇒ 如实跳过") or "")
        .. ((tonumber(nBad230) or 0) > 0 and ("；" .. nBad230 .. " 项读回对不上 ⇒ 如实报出") or "") .. "）")
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
      elseif sub == "dump" or sub == "探针" or sub == "清单" then
        -- ★★★1.75.13：只读清单（地图身份 / 客户端叠加层真值 / 每个层的在用判定与记录）——「谁写的、该是多少」一眼可判
        local out2 = (type(EVAL_SAY_FORCE) == "function") and EVAL_SAY_FORCE or P
        for _, ln in ipairs(smFitDumpLines()) do out2("[简易地图] " .. tostring(ln)) end
      elseif string.find(sub, "^mode") then
        EVAL_SM_MAPFIT_MODE_SET(string.match(sub, "^mode%s+(%S+)") or "")
      elseif string.find(sub, "^fresh") or sub == "重抓" then
        -- ★★★1.75.5（用户要求「每次打开地图都当做是第一次打开」）：默认**开**；关掉 = 老行为（本会话内按图记住）
        local v = string.match(sub, "^%S+%s+(%S+)") or ""
        if v == "on" or v == "开" then
          SM_CFG.mapFitFresh = nil
        elseif v == "off" or v == "关" then
          SM_CFG.mapFitFresh = false
        end
        P("关图即清空原值 当前 = " .. (smFitFreshOn()
          and "**开**（默认：每次关图删掉本图原值、把折过的几何还回自然档 ⇒ 下次开图重新读一遍再缩放）"
          or "关（本会话内按图记住原值，只有换图 / `/reload` 才重抓）"))
        P("　真值 SM_CFG.mapFitFresh=" .. tostring(SM_CFG.mapFitFresh) .. "（nil=开）｜ 代价：开图后约 0.4s 才发现原值（这段时间地图停在自然档）")
        P("用法：/ehm mapfit fresh on | off")
      elseif string.find(sub, "^verbose") or sub == "详细" then
        -- ★★★1.75.5（用户：「好的功能正常了.清理下这些调试日志」）：详细档开关，**默认关**
        local v = string.match(sub, "^%S+%s+(%S+)") or ""
        if v == "on" or v == "开" then
          SM_CFG.mapFitVerbose = true
        elseif v == "off" or v == "关" then
          SM_CFG.mapFitVerbose = nil
        end
        P("详细日志 当前 = " .. (smFitVerboseOn()
          and "开（逐条原值 / 第 N 次尝试 / 每次重试与折算都上屏）"
          or "**关**（默认：安静档 —— 每次开图最多「已读到 N 条」+「折算已对齐」两行，关图一行；真出问题才出声）"))
        P("　真值 SM_CFG.mapFitVerbose=" .. tostring(SM_CFG.mapFitVerbose) .. "（nil=关）｜ 全过程永远进取证环：/ehm mapfit trace")
        P("用法：/ehm mapfit verbose on | off")
      elseif sub == "on" or sub == "开" then
        EVAL_SM_MAPFIT_SET(true)
      elseif sub == "off" or sub == "关" then
        EVAL_SM_MAPFIT_SET(false)
      elseif sub == "restore" or sub == "还原" then
        smFitRestore(false)
      else
        smFitDiag()
      end
      P("用法：/ehm mapfit on | off | restore | diag | dump（只读清单）| trace | traceclear | mode fold|auto|nofold | fresh on|off | verbose on|off（不给子命令 = diag）")
    elseif msg == "reset" or msg == "复位" then
      featReset()
    elseif msg == "default" or msg == "默认" or msg == "默认档" then
      -- ★1.74.36-3 取证/手动口：把默认档（0.7 / 0.7 / GUI不启用）重新套一遍并如实报出来。
      --   与「工具箱开关从关→开」走的是**同一个**函数（smApplyDefaults），所以这里能证明真机行为。
      local a, s = smApplyDefaults()
      P(string.format("默认档已套用：缩放 %.2f / 透明度 %.2f / GUI重开 %s", s, a, smReopenOn() and "开" or "关"))
      P(string.format("当前真值：alpha=%s scale=%s guiReopen=%s（面板/滚轮可再调）",
        tostring(SM_CFG.alpha), tostring(SM_CFG.scale), tostring(SM_CFG.guiReopen)))
    elseif msg == "fitnow" or msg == "适配" or msg == "修正" then
      -- ★★★1.75.5（用户指定「本办法」）：**手动适配全过程，逐步打印**
      --   用户原话：「打开地图, 等待2s, 获取原值. 打印原值, 应用缩放. 打印缩放信息. 这样的调整过程.」
      local okRun = smFixNow()
      P("用法：/ehm fitnow（别名 /ehm 适配 · /ehm 修正）—— 缩放开启时按「开图 → 置 1.00 → 等 2s → 读原值 → 套缩放 → 折算」逐步打印；"
        .. "若仍不对，把这一整段连同 /ehm mapfit dump 一起发我")
      if not okRun then P("本次**没有开跑**：原因见上面那条（模块没开启）。") end
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
      pcall(mg.UnregisterEvent, mg, "VARIABLES_LOADED")
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
  P("叠加层适配 = " .. (smFitOn() and ("开 · 策略=" .. smFitModeLabel()) or "关（不再碰叠加层几何）"))
  if smFitOn() then P("　" .. EVAL_SM_MAPFIT_TIP()) end
  return true
end

-- 行 tooltip 里那句（与真值同源；行渲染处取它，别处不许再拼一遍文案）
function EVAL_SM_MAPFIT_TIP()
  local m = "叠加层适配：" .. (smFitOn() and "开" or "关")
    .. "（WorldMapOverlay/Highlight 的处理，底瓦片不动；/ehm mapfit 可关或取证）"
  -- ★★★1.75.9：**策略 + 实测判据**都要摊在悬停里 —— 用户报的「被缩两遍」与「正常开启不生效」都是这条事实没被看见。
  m = m .. "｜策略：" .. smFitModeLabel()
  if SMFIT.needFold == false then
    m = m .. "｜探测：本客户端**会自动跟随缩放**（折算档下仍按策略折算；想听探测用 mode auto）"
  elseif SMFIT.needFold == true then
    m = m .. "｜探测：本客户端**不会自动跟随** ⇒ 需要按 es 折算（原值取自自然档）"
  else
    m = m .. "｜探测：还没探过（开启时自动探一次）"
  end
  return m
end

-- ★★★1.75.9 折算策略的读写口（默认 fold = 照旧折算，保住「开启即生效」）
function EVAL_SM_MAPFIT_MODE() return smFitMode() end

function EVAL_SM_MAPFIT_MODE_SET(m)
  m = tostring(m or "")
  if m == "auto" or m == "自动" then m = "auto"
  elseif m == "nofold" or m == "不折算" or m == "不折" or m == "off" then m = "nofold"
  else m = "fold" end
  SM_CFG.mapFitMode = m
  SMFIT.captured = false -- 换档后重新在自然档校准一次原值
  SMFIT.needFold = smFitDetect()
  mfLog("策略切换：%s（探测=%s）", smFitModeLabel(), (SMFIT.needFold == nil) and "未判定" or tostring(SMFIT.needFold))
  P("叠加层折算策略 = " .. smFitModeLabel() .. "（★本档只在本会话有效：/reload 后自动回默认「折算」）")
  P("　" .. EVAL_SM_MAPFIT_TIP())
  if m == "nofold" then
    -- ★★★1.75.5 实案：这一档曾把用户坑成「关闭/开启 缩放始终不生效」（它落存档、而开关不复位策略）⇒ 必须**当场说清**
    P("　★★注意：这一档 = **一个几何都不碰** ⇒ 叠加层适配完全不动作（现象就是「怎么关开都不生效」）。" ..
      "要长期关掉请用工具箱的「叠加层适配」开关（/ehm mapfit off）；要恢复折算：/ehm mapfit mode fold")
  end
  return true
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

-- ★1.75.10 位置口径读值口（用户报障：「每次插件重载的初始位置能否居中」）：
--   返回 `posArmed`（本次会话是否还没居中过）/ `recenter`（居中窗口剩余拍数）/ 存档里的 px、py。
--   `REARM` = 把「本次会话还没居中过」这一位按**载入期的原状**恢复 —— 组 237 要验「首次开图必居中」，
--   而前面的组（224/225/230/232）早就把这一位用掉了；不 rearm 就只能验第二次，等于没验到那条判据。
function EVAL_SM_TEST_POS_STATE()
  return FEAT.posArmed == true, tonumber(FEAT.recenter) or 0, SM_CFG.px, SM_CFG.py
end
function EVAL_SM_TEST_POS_REARM()
  FEAT.posArmed = true
  FEAT.recenter = 0
  return FEAT.posArmed
end
-- ★拖拽柄本体（读值口）：用来点火**真实的 OnDragStart**（验「用户一开始拖就让出居中窗口期」）。
--   本文件的自建件都随 CloseAll 注册进 _G，但那是**全局名**；模块内部的 `featDrag` 才是真身
--   （组 232 会把 _G.EH_SM_DRAG 换成假件再清掉，所以只能从这里取）。
function EVAL_SM_TEST_DRAG() return featDrag end

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
-- ★1.75.13：原值条数 = **跨地图分桶**合计（只数真记录；平表老数据不算 —— 见 smFitOrigCount）
function EVAL_SM_TEST_MAPFIT_ORIG() return smFitOrigCount() end
function EVAL_SM_TEST_MAPFIT_REC() local n = 0 for _ in pairs(SMFIT.rec or {}) do n = n + 1 end return n end
function EVAL_SM_TEST_MAPFIT_BURST(sec) SMFIT.burst = tonumber(sec) or 0 return SMFIT.burst end
function EVAL_SM_TEST_MAPFIT_RESTORE() return smFitRestore(true) end
-- 夹具自清（测试换过 `_G.WorldMapDetailFrame` 的假帧之后必须还原：内存记录 + 存档原值 + 开关一起复位）
function EVAL_SM_TEST_MAPFIT_RESET()
  SMFIT.rec = {}
  SMFIT.open, SMFIT.es, SMFIT.burst = false, nil, 0
  SMFIT.captured, SMFIT.needFold = false, nil
  SMFIT.wrote = false
  -- ★1.75.13：地图身份 / 版式计时 / 逐层记账也要复位（否则上一段夹具的图会串到下一段）
  SMFIT.mapKey, SMFIT.mapAge, SMFIT.wroteKeys = nil, 0, {}
  -- ★1.75.5：会话内存按图存的那份也要清（夹具自清 = 回到「刚载入」）
  SMFIT.recMap = {}
  -- ★1.75.5：抓原值的尝试计数与有界重试计时（新判据组 254 挂在这两个口上）
  SMFIT.capCalls, SMFIT.capAge, SMFIT.capAt = 0, 99, nil
  -- ★1.75.5：抓原值的失败计数 + 抓原值窗口（复位成「没开窗」）
  SMFIT.capFails, smFitHold = 0, 0
  -- ★1.75.5：**每次开图只报一次**的那几条标记 + 详细档开关（夹具自清 = 回到「刚载入」）
  SMFIT.saidLatch, SMFIT.saidFail, SMFIT.saidEmpty, SMFIT.saidFold = false, false, false, false
  SM_CFG.mapFitVerbose = nil
  -- ★★★1.75.5：**手动适配也要复位** —— 否则上一段夹具留下的「自动逻辑让位」会**关掉后面所有组的 tick**
  smFixActive, SM_FIX.t, SM_FIX.done = false, 0, false
  SM_CFG.mapFitOrig = nil
  SM_CFG.mapFitVer = nil
  SM_CFG.mapFit = nil
  SM_CFG.mapFitMode = nil -- ★1.75.9：策略也要回到默认（否则上一档会**串到下一段夹具**：实测 ⑨ 因此抓不到原值）
  SM_CFG.mapFitFresh = nil -- ★1.75.5：「每次开图都当第一次打开」也回默认（nil = 开；夹具自清 = 回到「刚载入」）
  return true
end
-- ★★★1.75.13 新读值口（「坐标丢失 / 全挤在左下」那一案的判据挂在这几个口上）
function EVAL_SM_TEST_MAPFIT_MAPKEY() return SMFIT.mapKey, tonumber(SMFIT.mapAge) or 0, table.getn(smFitTargets()) end
function EVAL_SM_TEST_MAPFIT_INUSE(i)
  local it = smFitTargets()[tonumber(i) or 1]
  if not it then return nil end
  return smFitInUse(it.o), it.key
end
function EVAL_SM_TEST_MAPFIT_WROTE(name) return SMFIT.wroteKeys[tostring(name or "")] end
function EVAL_SM_TEST_MAPFIT_DUMP() return smFitDumpLines() end
function EVAL_SM_TEST_MAPFIT_CAPTURE_RAW() return smFitCapture() end
-- ★1.75.5：抓原值的**尝试次数 / 有界重试计时 / 是否落闩**（「每帧重跑」那场事故的判据挂在这里）
function EVAL_SM_TEST_MAPFIT_CAPSTATE() return tonumber(SMFIT.capCalls) or 0, tonumber(SMFIT.capAge) or 0, SMFIT.captured == true, tonumber(SMFIT.capFails) or 0 end
-- ★★★1.75.5：**只清内存、保留存档原值**（= 精确模拟 `/reload`）——
--   事故场景「存档里原值已齐（同一张图第二次打开/重载后再开）」只有这么复现：跨会话时 rec 是空的、桶是满的。
function EVAL_SM_TEST_MAPFIT_SOFT_RESET()
  SMFIT.rec = {}
  SMFIT.recMap = {}
  SMFIT.captured = false
  SMFIT.capCalls, SMFIT.capAge, SMFIT.capAt = 0, 99, nil
  SMFIT.capSayN = 0 -- ★1.75.5：播报计数（= /reload ⇒ 这次开图的「第 1 次尝试」要重新数）
  -- ★1.75.5：抓原值的失败计数 + 抓原值窗口（复位成「没开窗」）
  SMFIT.capFails, smFitHold = 0, 0
  -- ★★★1.75.5：手动适配的让位标记同样要清（见 EVAL_SM_TEST_MAPFIT_RESET 的注释）
  smFixActive, SM_FIX.t, SM_FIX.done = false, 0, false
  -- ★1.75.5：**每次开图只报一次**的那几条标记（= /reload ⇒ 这次开图要重新报一遍）
  SMFIT.saidLatch, SMFIT.saidFail, SMFIT.saidEmpty, SMFIT.saidFold = false, false, false, false
  SMFIT.mapKey, SMFIT.mapAge = nil, 0
  SMFIT.wroteKeys, SMFIT.wrote = {}, false
  return true
end
function EVAL_SM_TEST_MAPFIT_NEWMAP(mk) return smFitNewMap(mk) end
-- ★1.75.5：**种一条记录**进会话内存（= 旧的「存档里种脏记录」的等价物）——
--   组 253⑤b 用它验「**有记录也不写**本图不用的层」：唯一用途是测试，不进任何生产路径。
function EVAL_SM_TEST_MAPFIT_PLANT(name, x, y, w, h)
  local n = tostring(name or "")
  if n == "" then return false end
  SMFIT.rec[n] = { idx = n, name = n, p = "TOPLEFT", rel = "WorldMapDetailFrame", rp = "TOPLEFT",
    x = tonumber(x) or 0, y = tonumber(y) or 0, w = tonumber(w) or 0, h = tonumber(h) or 0, from = "plant" }
  return true
end
-- ★1.75.5：**会话内存**分图的直读口：返回 桶数, 指定桶里的记录数（桶不存在 = 0）——定位信息不再落存档
function EVAL_SM_TEST_MAPFIT_BUCKET(mk)
  local t = SMFIT.recMap
  if type(t) ~= "table" then return 0, 0 end
  local nb = 0
  for _ in pairs(t) do nb = nb + 1 end
  local b = (mk ~= nil) and t[tostring(mk)] or nil
  local n = 0
  if type(b) == "table" then for _, v in pairs(b) do if type(v) == "table" then n = n + 1 end end end
  return nb, n
end
-- ★★★1.75.9 新读值口（「缩两遍」那一案的判据都挂在这几个口上）
function EVAL_SM_TEST_MAPFIT_NEEDFOLD() return SMFIT.needFold, SMFIT.captured == true end
function EVAL_SM_TEST_MAPFIT_DETECT() return smFitDetect() end
function EVAL_SM_TEST_MAPFIT_PREPARE() return smFitPrepare() end
function EVAL_SM_TEST_MAPFIT_CAPTURE() return smFitCapture() end
function EVAL_SM_TEST_MAPFIT_MIGRATE() return smFitMigrate() end
function EVAL_SM_TEST_MAPFIT_FROM(i)
  local n = 0
  for _ in pairs(SMFIT.rec or {}) do n = n + 1 end
  if tonumber(i) then
    local k = 1
    for key, r in pairs(SMFIT.rec or {}) do
      if k == tonumber(i) then return key, r.from, r.x, r.y, r.w, r.h end
      k = k + 1
    end
  end
  return n
end
function EVAL_SM_TEST_FEAT_TORN() return FEAT.torn == true, FEAT.escAdded == true end
function EVAL_SM_TEST_ESC_ADDED_SET(v) FEAT.escAdded = v and true or false return FEAT.escAdded end
-- ★1.75.9 折算取证环的读值口（用户要求「可以开启日志」⇒ 断言也要能读它）
function EVAL_SM_TEST_MAPFIT_TRACE_N()
  return (type(SM_CFG.mapFitTrace) == "table") and table.getn(SM_CFG.mapFitTrace) or 0
end
function EVAL_SM_TEST_MAPFIT_TRACE_LAST()
  local r = SM_CFG.mapFitTrace
  if type(r) ~= "table" or table.getn(r) == 0 then return "" end
  return tostring(r[table.getn(r)])
end
function EVAL_SM_TEST_MAPFIT_TRACE_ALL()
  local r = SM_CFG.mapFitTrace
  if type(r) ~= "table" then return "" end
  return table.concat(r, " || ")
end
function EVAL_SM_TEST_MAPFIT_TRACE_CLEAR() SM_CFG.mapFitTrace = {} return true end
-- ★★★1.75.5（用户指定「本办法」）读值口：**手动适配全过程**（`/ehm fitnow`）
--   · `EVAL_SM_TEST_FIX_STATE()` = 计时帧在不在 / 已累计秒数 / 自动逻辑是否已让位 / 本趟是否已跑完
--   · `EVAL_SM_TEST_FIX_DO()`   = 直接跑第 3~5 步（跳过「等 2 秒」；测试不必真等）
--   · `EVAL_SM_TEST_FIX_RUN()`  = 走完整入口（含第 1~2 步 + 起计时）
function EVAL_SM_TEST_FIX_STATE()
  local f = _G["EH_SM_FITFIX"]
  local has = (type(f) == "table" or type(f) == "userdata")
  return has, tonumber(SM_FIX.t) or 0, smFixActive == true, SM_FIX.done == true
end
function EVAL_SM_TEST_FIX_DO() SM_FIX.done = false return smFixRunCapture() end
function EVAL_SM_TEST_FIX_RUN() return smFixNow() end
-- ★★★1.75.5：「关图即清空原值（每次开图都重新读）」的真值读值口（nil = 开）+ 手动跑一次清空（测试用）
function EVAL_SM_TEST_MAPFIT_FRESH() return smFitFreshOn(), SM_CFG.mapFitFresh end
-- ★1.75.5：详细档读值口（用户：「清理下这些调试日志」⇒ 默认必须是关）
function EVAL_SM_TEST_MAPFIT_VERBOSE() return smFitVerboseOn(), SM_CFG.mapFitVerbose end
function EVAL_SM_TEST_MAPFIT_DROPCLOSE(mk) return smFitDropOnClose(mk) end
function EVAL_SM_TEST_COORDS_STATE()
  local c = _G["EH_SM_COORDS"]
  if not (type(c) == "table" or type(c) == "userdata") then return nil, nil, nil end
  local ok1, shown = pcall(c.IsShown, c)
  local ok2, sc = pcall(c.GetScript, c, "OnUpdate")
  return (ok1 and shown) or nil, (ok2 and (sc == nil)), type(c) == "table" or type(c) == "userdata"
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
