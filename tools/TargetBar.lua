-- EvalHelp · tools/TargetBar.lua —— 目标血条样式美化（1.75.40 · target-bar 分支）
-- 需求（用户原话）：「增加个分支.单独对目标识别血量进行样式美化操作.参考UnrealUI的机制.」
--
-- 参考对象 = unrealUI（Interface\AddOns\unrealUI · modules/unitframes.lua + nameplates.lua），
-- 从它身上抄来的**机制**（不是外观）：
--   ① 框 = **Button + LOW strata**——「拖动柄必须 Button」（Frame 收不到可靠鼠标输入）与
--     「HUD 元素永远压在原生窗口之下」两条实测，与我们项目的既有结论完全一致；
--   ② 血条 = 外盒 + **显式宽高的填充、单角锚点**——绝不靠两角锚点拉伸定尺寸
--     （本客户端两角锚定尺寸没有契约；填充宽从外框真实宽度现算）；
--   ③ 文字 = **独立 textLayer（level+10）**——填充纹理宽度每次刷新都在变，同层文字会被盖住；
--   ④ 刷新 = **0.15s 共享 tick + 事件加速器**（PLAYER_TARGET_CHANGED 只加速、不是机制；
--     unrealUI 实测「事件可能根本不触发」⇒ 轮询兜底才是本体）；
--   ⑤ 血量 = UnitHealth / UnitHealthMax —— 本客户端对**非队友只返 0~100 百分比**
--     （unrealUI 实测 BEHAVIOR_VERIFIED）⇒ 血条按百分比画、文本显示 %.1f%%；
--   ⑥ 敌我色 / 难度色 / 精英后缀 = UnitReaction / UnitIsPlayer / UnitCanAttack / UnitLevel /
--     UnitClassification；难度色照抄 unrealUI 的 DifficultyColor 边界
--     （本客户端 GetDifficultyColor 缺失 ⇒ 本地自写，绿带取 GetQuestGreenRange、缺省 7）。
--
-- ★与原生 TargetFrame 的关系：**不压制、不修改**——本机同时装着 unrealUI（它已接管原生框），
--   本模块是**额外**的紧凑 HUD 血条，左键可拖到屏幕任意位置，两者共存不冲突。
-- ★懒加载边界（与 HunterHelper/DismountHelper 同一纪律）：本客户端无文件读取 API、LoadAddOn 是
--   Protected ⇒ 文件级懒加载做不到；本模块的「懒」= **载入期零副作用**（只声明表与函数），
--   开关打开那一下才 CreateFrame。
-- 依赖的全局件（只在调用时读，载入期不读 → 与 toc 顺序解耦）：
--   EVAL_SAY / EVAL_L（Core 桥）· EVAL_TB_CFG（工具箱真值）· EVAL_TB_CHAR_STORE（角色级存档）·
--   EVAL_DD_OPEN（全局下拉）· EVAL_TB_MOD_ROWS（模块行注册表）· EVAL_TB_REFRESH（工具箱刷新）

local TB = {
  built = false,     -- 框是否已建（懒加载读值口）
  root = nil,        -- 外框（Button，具名 EvalHelpTargetBar）
  barBg = nil, barFg = nil,
  nameT = nil, lvlT = nil, pctT = nil,
  cache = {},        -- 上次写入的值（变化才写，省 API）
  elapsed = 0,       -- tick 累加
}

-- ===== 常量（单一来源，改这里就够） =====
local TBW_DEF = 200          -- 默认宽度
local TB_H = 38              -- 外框高（文字行 12 + 血条 16 + 边框与间距）
local TB_BAR_H = 16          -- 血条高
local TB_BORDER = 1
local TB_TICK = 0.15         -- 刷新节拍（unrealUI 的单位框是 0.2s；血条是主要观察对象，给 0.15s）
local TB_DEF_Y = 125         -- 默认位置：屏幕底部正中偏右（与 unrealUI 目标框默认位同族）
local TB_DEF_X = 75
local TB_WIDTHS = { 160, 200, 240, 280 }
-- 敌我色（照抄 unrealUI UNIT_COLOR 的取值，压成我们习惯的低饱和）
local TB_KIND_COLOR = {
  enemy   = { 0.75, 0.27, 0.32 },
  neutral = { 0.80, 0.72, 0.26 },
  friend  = { 0.35, 0.66, 0.34 },
  player  = { 0.26, 0.50, 0.82 },
}
-- 名字反应色（血条色更暗、名字亮一档）
local TB_NAME_COLOR = {
  enemy   = { 1.00, 0.35, 0.35 },
  neutral = { 1.00, 0.90, 0.40 },
  friend  = { 0.45, 0.85, 0.45 },
  player  = { 1.00, 1.00, 1.00 },
}

-- ===== 桥（调用时才读） =====
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end
local function tbSay(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

-- ===== 真值：开关 = 工具箱全局（tb.targetBar）；布局 = 角色级存档 =====
local function tbStore()
  -- 角色级存档（位置/宽度），与骑乘助手同一口径（EVAL_TB_CHAR_STORE）
  if type(EVAL_TB_CHAR_STORE) ~= "function" then return nil end
  local st = EVAL_TB_CHAR_STORE()
  if type(st) ~= "table" then return nil end
  st.targetBarCfg = st.targetBarCfg or {}
  local t = st.targetBarCfg
  if t.width == nil then t.width = TBW_DEF end
  return t
end
local function tbOn()
  if type(EVAL_TB_CFG) ~= "function" then return false end
  local tb = EVAL_TB_CFG()
  if type(tb) ~= "table" then return false end
  -- ★默认开（用户点名要的功能）：第一次把 nil 物化为 true，绝不顶回用户手动勾选
  if tb.targetBar == nil then tb.targetBar = true end
  return tb.targetBar == true
end

-- ===== 小件 =====
local function tbSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end
local function tbFont(fs)
  local ok = pcall(fs.SetFontObject, fs, "GameFontHighlightSmall")
  if not ok then pcall(fs.SetFontObject, fs, "ChatFontNormal") end
end
-- ★API 调用一律「按名解析 + pcall + 强转」（unrealUI 实测：本客户端 Unit API 返回契约未验证）
local function tbApiNum(name, a)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, a)
  if not ok then return nil end
  return tonumber(v)
end
local function tbApiStr(name, a)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, a)
  if not ok or type(v) ~= "string" then return nil end
  return v
end
local function tbApiTruth(name, a, b)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then return false end
  local ok, v = pcall(fn, a, b)
  if not ok then return false end
  return (v ~= nil and v ~= false and v ~= 0 and v ~= "")
end

-- ===== 颜色与文本的纯函数（harness 真跑的就是这几个） =====
-- ★难度色：照抄 unrealUI 的 DifficultyColor 边界（nameplates.lua:206，两处保持同步的约定）——
--   本客户端 GetDifficultyColor 缺失 ⇒ 本地自写；绿带 = GetQuestGreenRange（取不到缺省 7）。
local function tbDiffColor(level, playerLevel, greenRange)
  level = tonumber(level) or 0
  local my = tonumber(playerLevel) or 1
  local gr = tonumber(greenRange)
  if not gr or gr <= 0 then gr = 7 end
  if level <= 0 then return 0.69, 0.69, 0.69 end
  local d = level - my
  if d >= 5 then return 1.00, 0.10, 0.10 end
  if d >= 3 then return 1.00, 0.50, 0.25 end
  if d >= -2 then return 1.00, 1.00, 0.00 end
  if -d <= gr then return 0.25, 0.75, 0.25 end
  return 0.50, 0.50, 0.50
end
-- 精英/稀有后缀（unrealUI 用 "+"；我们把稀有与精英区分开）
local function tbClassSuffix(cls)
  if cls == "worldboss" then return "++" end
  if cls == "rareelite" then return "R+" end
  if cls == "rare" then return "R" end
  if cls == "elite" then return "+" end
  return ""
end
-- 敌我判定（照 unrealUI 的判定顺序：友方玩家 → UnitReaction 分档 → 读不到按敌对）
local function tbUnitKind(isPlayer, canAttack, reaction)
  if isPlayer and not canAttack then return "player" end
  local r = tonumber(reaction)
  if r then
    if r <= 3 then return "enemy" end
    if r == 4 then return "neutral" end
    return "friend"
  end
  return "enemy"
end

-- ===== 位置（位置记忆配方：GetCenter 含缩放 ⇒ 存取除 GetEffectiveScale；越界回默认） =====
local function tbSavePos()
  local cfg = tbStore()
  if not (cfg and TB.root) then return end
  local ok, cx, cy = pcall(TB.root.GetCenter, TB.root)
  if not (ok and cx and cy) then return end
  local sc = 1
  local okS, s = pcall(TB.root.GetEffectiveScale, TB.root)
  if okS and tonumber(s) and s > 0 then sc = s end
  cfg.px, cfg.py = cx / sc, cy / sc
end
local function tbApplyPos()
  if not TB.root then return end
  local cfg = tbStore()
  TB.root:ClearAllPoints()
  if cfg and cfg.px and cfg.py then
    -- ★越界回归（与宿主 uiOffscreen 同款思路）：中心在屏幕外 ⇒ 回默认
    local sw, sh = tbApiNum("GetScreenWidth") or 1024, tbApiNum("GetScreenHeight") or 768
    local W = cfg.width or TBW_DEF
    if cfg.px > -20 and cfg.px < sw + 20 and cfg.py > -20 and cfg.py < sh + 20 then
      TB.root:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cfg.px, cfg.py)
      return
    end
    cfg.px, cfg.py = nil, nil
  end
  TB.root:SetPoint("CENTER", UIParent, "BOTTOM", TB_DEF_X, TB_DEF_Y)
end

-- ===== 刷新（唯一绘制口；变化才写） =====
local function tbRefresh()
  if not (TB.built and TB.root) then return end
  if not tbOn() then return end
  local exists = tbApiTruth("UnitExists", "target")
  if not exists then
    if TB.root:IsShown() then TB.root:Hide() end
    TB.cache = {}
    return
  end
  if not TB.root:IsShown() then TB.root:Show() end
  -- 名字
  local nm = tbApiStr("UnitName", "target") or ""
  if nm ~= TB.cache.name then
    TB.cache.name = nm
    TB.nameT:SetText(nm)
  end
  -- 等级 + 精英后缀（难度色）
  local lv = tbApiNum("UnitLevel", "target")
  local lvTxt = ((lv and lv > 0) and tostring(lv) or "??") .. tbClassSuffix(tbApiStr("UnitClassification", "target"))
  if lvTxt ~= TB.cache.lvl then
    TB.cache.lvl = lvTxt
    TB.lvlT:SetText(lvTxt)
    local r, g, b = tbDiffColor(lv, tbApiNum("UnitLevel", "player"), tbApiNum("GetQuestGreenRange"))
    TB.lvlT:SetTextColor(r, g, b, 1)
  end
  -- 血量（本客户端非队友只给百分比 ⇒ 显示百分比）
  local hp = tbApiNum("UnitHealth", "target")
  local hm = tbApiNum("UnitHealthMax", "target")
  local pct = 0
  if hp and hm and hm > 0 then pct = hp / hm * 100 end
  if pct > 100 then pct = 100 end
  if pct ~= TB.cache.pct then
    TB.cache.pct = pct
    TB.pctT:SetText(string.format("%.1f%%", pct))
    local innerW = (TB.root:GetWidth() or TBW_DEF) - 2 * TB_BORDER
    local fw = math.floor(innerW * pct / 100 + 0.5)
    if pct <= 0 then fw = 0 end
    if fw < 1 then fw = 0.0001 end -- ★0 血不画 1px 假血；SetWidth(0) 在本客户端行为未验证 ⇒ 用近似零
    TB.barFg:SetWidth(fw)
  end
  -- 敌我着色（血条 + 名字反应色）
  local isP = tbApiTruth("UnitIsPlayer", "target")
  local canAtk = tbApiTruth("UnitCanAttack", "player", "target")
  local kind = tbUnitKind(isP, canAtk, tbApiNum("UnitReaction", "target", "player"))
  if kind ~= TB.cache.kind then
    TB.cache.kind = kind
    local c = TB_KIND_COLOR[kind] or TB_KIND_COLOR.enemy
    TB.barFg:SetVertexColor(c[1], c[2], c[3], 1)
    local n = TB_NAME_COLOR[kind] or TB_NAME_COLOR.enemy
    TB.nameT:SetTextColor(n[1], n[2], n[3], 1)
  end
end

-- ===== 构建（首用才建） =====
local function tbRelayout()
  if not TB.built then return end
  local cfg = tbStore()
  local W = (cfg and cfg.width) or TBW_DEF
  TB.root:SetWidth(W)
  TB.edgeT:SetWidth(W)
  TB.edgeB:SetWidth(W)
  TB.cache = {}
  tbRefresh()
end

local function tbBuild()
  if TB.built then return true end
  if type(CreateFrame) ~= "function" then return false end
  local cfg = tbStore()
  local W = (cfg and cfg.width) or TBW_DEF
  local root = CreateFrame("Button", "EvalHelpTargetBar", UIParent)
  root:SetFrameStrata("LOW")          -- ★HUD 元素，永远压原生窗下（strata 会传给子件）
  root:SetWidth(W)
  root:SetHeight(TB_H)
  if type(root.SetClampedToScreen) == "function" then pcall(root.SetClampedToScreen, root, true) end
  root:EnableMouse(true)
  root:RegisterForClicks("LeftButtonUp")
  root:RegisterForDrag("LeftButton")
  if type(root.SetMovable) == "function" then pcall(root.SetMovable, root, true) end
  -- 背景
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(root)
  tbSolid(bg, 0.06, 0.06, 0.06, 0.82)
  -- 四条 1px 金边（上/下宽度随外框，左右固定 1px）
  local function mkEdge(w, h, p1, rel, p2, x, y)
    local t = root:CreateTexture(nil, "BORDER")
    t:SetWidth(w) t:SetHeight(h)
    t:SetPoint(p1, rel, p2, x, y)
    tbSolid(t, 0.55, 0.45, 0.20, 1)
    return t
  end
  TB.edgeT = mkEdge(W, 1, "TOPLEFT", root, "TOPLEFT", 0, 1)
  TB.edgeB = mkEdge(W, 1, "BOTTOMLEFT", root, "BOTTOMLEFT", 0, -1)
  mkEdge(1, TB_H, "TOPLEFT", root, "TOPLEFT", -1, 0)
  mkEdge(1, TB_H, "TOPRIGHT", root, "TOPRIGHT", 1, 0)
  -- 血条（背景两角锚定随外框变宽——纯贴图显示、不做尺寸计算 ⇒ 安全；填充显式宽高+单角锚）
  local barBg = root:CreateTexture(nil, "ARTWORK")
  barBg:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", TB_BORDER, TB_BORDER)
  barBg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -TB_BORDER, TB_BORDER)
  barBg:SetHeight(TB_BAR_H)
  tbSolid(barBg, 0.10, 0.09, 0.06, 1)
  local barFg = root:CreateTexture(nil, "OVERLAY")
  barFg:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
  barFg:SetHeight(TB_BAR_H)
  barFg:SetWidth(1)
  tbSolid(barFg, 0.75, 0.27, 0.32, 1)
  -- ★文字层（独立子帧、level+10）：填充宽每次刷新都变，同层文字会被盖住
  local tl = CreateFrame("Frame", nil, root)
  tl:SetAllPoints(root)
  local lv0 = 1
  local okLv, lvx = pcall(root.GetFrameLevel, root)
  if okLv and tonumber(lvx) then lv0 = lvx end
  pcall(tl.SetFrameLevel, tl, lv0 + 10)
  local nameT = tl:CreateFontString(nil, "OVERLAY")
  tbFont(nameT)
  nameT:SetPoint("BOTTOMLEFT", barBg, "TOPLEFT", 2, 2)
  local lvlT = tl:CreateFontString(nil, "OVERLAY")
  tbFont(lvlT)
  lvlT:SetPoint("BOTTOMRIGHT", barBg, "TOPRIGHT", -2, 2)
  local pctT = tl:CreateFontString(nil, "OVERLAY")
  tbFont(pctT)
  pctT:SetPoint("CENTER", barBg, "CENTER", 0, 0)
  TB.root, TB.barBg, TB.barFg = root, barBg, barFg
  TB.nameT, TB.lvlT, TB.pctT = nameT, lvlT, pctT
  -- 拖拽（Button + RegisterForDrag；位置存中心点、除缩放）
  root:SetScript("OnDragStart", function()
    if not tbOn() then return end
    pcall(root.StartMoving, root)
  end)
  root:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    tbSavePos()
  end)
  TB.built = true
  return true
end

-- ===== 开关（关掉零动作：Hide + 摘 OnUpdate/OnEvent + 摘事件——我们自己的帧，UnregisterAllEvents 安全） =====
local function tbArm()
  if not TB.built then return end
  TB.elapsed = 0
  TB.root:SetScript("OnUpdate", function()
    -- ★OnUpdate 零形参铁律：dt 只能从全局 arg1 取
    local dt = tonumber(arg1) or TB_TICK
    TB.elapsed = TB.elapsed + dt
    if TB.elapsed >= TB_TICK then
      TB.elapsed = 0
      pcall(tbRefresh)
    end
  end)
  TB.root:RegisterEvent("PLAYER_TARGET_CHANGED")
  TB.root:SetScript("OnEvent", function() pcall(tbRefresh) end) -- 事件只是加速器
end
local function tbTeardown()
  if not TB.built then return end
  TB.root:Hide()
  TB.root:SetScript("OnUpdate", nil)
  TB.root:SetScript("OnEvent", nil)
  TB.root:UnregisterAllEvents()
  TB.cache = {}
end

-- ★开关唯一入口（工具箱行与初始化都走它）
function EVAL_TARGETBAR_SET(on)
  if type(EVAL_TB_CFG) == "function" then
    local tb = EVAL_TB_CFG()
    if type(tb) == "table" then tb.targetBar = on and true or false end
  end
  if on then
    if tbBuild() then
      tbArm()
      -- ★尺寸永远与存档一致（重开/恢复路径也要重排——否则改宽存档后框宽不更新，冒烟 D2 抓到）
      tbRelayout()
      tbApplyPos()
      tbRefresh()
    else
      tbSay(L("TBAR_BUILD_FAIL"))
    end
  else
    tbTeardown()
  end
end
-- ★宿主 VARIABLES_LOADED 的唯一接线点
function EVAL_TARGETBAR_INIT()
  if tbOn() then EVAL_TARGETBAR_SET(true) end
end

-- ===== 设置菜单（[设置] 悬停按钮 → 下拉：复位位置 + 宽度四档） =====
local function tbMenu()
  local cfg = tbStore()
  local w = (cfg and cfg.width) or TBW_DEF
  local items, sel = { L("TBAR_RESET_POS") }, {}
  for i, v in ipairs(TB_WIDTHS) do
    table.insert(items, string.format(L("TBAR_WFMT"), v))
    if v == w then sel[i + 1] = true end
  end
  return items, sel
end

local tbRow = function(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return tbOn() end
  r.set = function(v) EVAL_TARGETBAR_SET(v and true or false) end
  r.extra:Hide()                       -- ★配置项只在 [设置] 的悬停里显示，行上不重复
  r.add.text:SetText(L("TB_TARGETBAR_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_TARGETBAR_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, L("TBAR_SET_TIP"), 0.88, 0.88, 0.88)
    local st = EVAL_TB_TARGETBAR_STATE()
    pcall(tip.AddLine, tip, L("TBAR_STATE_FMT", st.on and "on" or "off", tostring(st.width), tostring(st.target), tostring(st.pct)), 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then
      tbSay(L("TBAR_NO_DD"))
      return
    end
    local items, sel = tbMenu()
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      if pi == 1 then
        local cfg = tbStore()
        if cfg then cfg.px, cfg.py = nil, nil end
        tbApplyPos()
        return
      end
      local cfg = tbStore()
      if cfg then
        cfg.width = TB_WIDTHS[pi - 1] or TBW_DEF
        tbRelayout()
      end
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = sel })
  end)
  return true
end

local TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(TB_ROWS) ~= "table" then
  TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", TB_ROWS)
end
TB_ROWS["targetBar"] = tbRow

-- ===== 读值口（生产诊断：工具箱悬停状态行与排查共用；★直给真实字段，不复刻逻辑） =====
function EVAL_TB_TARGETBAR_STATE()
  local cfg = tbStore()
  return {
    on = tbOn(), built = TB.built,
    width = (cfg and cfg.width) or TBW_DEF,
    px = cfg and cfg.px, py = cfg and cfg.py,
    target = TB.cache.name or "-", lvl = TB.cache.lvl or "-",
    pct = TB.cache.pct or 0, kind = TB.cache.kind or "-",
    shown = TB.built and TB.root and TB.root.IsShown and TB.root:IsShown() or false,
  }
end

-- ★离线 harness 用的纯函数出口（不依赖任何帧）：颜色/后缀/敌我判定
function EVAL_TB_TARGETBAR_DIFFCOLOR(level, my, gr) return tbDiffColor(level, my, gr) end
function EVAL_TB_TARGETBAR_KIND(isP, canAtk, reac) return tbUnitKind(isP, canAtk, reac) end
function EVAL_TB_TARGETBAR_CLSSUFFIX(cls) return tbClassSuffix(cls) end
-- ★离线 harness 用的整体驱动口：给定 API 桩表跑一遍真实 tbRefresh（帧由 test_stub 提供）
function EVAL_TB_TARGETBAR_REFRESH() return tbRefresh() end
function EVAL_TB_TARGETBAR_BUILD() return tbBuild() end
function EVAL_TB_TARGETBAR_SETPOS(px, py)
  local cfg = tbStore()
  if cfg then cfg.px, cfg.py = px, py end
end