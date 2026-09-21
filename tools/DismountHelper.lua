-- EvalHelp · tools/DismountHelper.lua —— 骑乘助手 · 一键下马（1.74.7 新增）
-- 需求（用户原话）：「按照推荐的在工具箱内添加个一键下马功能.脚本./tools 内」
--   推荐方案来自对 LazyPig 的调研 + 官方 API 核对：
--     ① 本客户端**没有** Dismount / IsMounted / Mount 任何 API（1370 条索引零命中）；
--     ② 官方 Bucket：CancelPlayerBuff(buffIndex) 存在且**未标 Protected**（插件可直接调）；
--     ③ 更干净的做法 = 用 GetPlayerBuff 的 **CANCELABLE 过滤器**把候选缩到「可取消的有益光环」，
--        再按 tooltip 描述识别坐骑（「速度提高X%」/「增加移动速度」/ Mount / 坐骑 / 骑乘）。
--   ★与 LazyPig 的差别：它在 TurtleWoW 上用「累加槽位 + 全量取消兜底」；我们按本客户端文档走
--     过滤器 + 内部索引（CancelPlayerBuff 要的是 **GetPlayerBuff 返回的内部索引**，不是槽位号！）。
--
-- 交互（与猎人助手/消耗品助手同一套范式）：
--   · 屏幕图标**左键 = 一键下马**（检测坐骑光环 → 取消 → 如实播报）
--   · 图标**右键 = 下拉菜单**（一键下马 / 自动下马开关 / 位置复位），全走全局下拉件 EVAL_DD_OPEN
--   · 工具箱 →「骑乘助手」→「一键下马」开关 = 本模块**总闸门**（关掉 = 图标收起、不建帧）
--   · 可选「自动下马」：被系统以「你正在骑乘/无法在…」拒绝时自动下马（LazyPig 同款触发点，但按需开）
--
-- ★懒加载边界（与 HunterHelper 同一纪律，别再重新论证）：
--   本客户端无文件读取 API、LoadAddOn 是 Protected ⇒ **文件级懒加载做不到**，只能列进 EvalHelp.toc；
--   本模块的「懒」= 载入期零副作用（只有状态表 + 函数），开关打开那一下才 CreateFrame。
--
-- 依赖的全局件（只在调用时读，载入期不读 → 与 toc 顺序解耦）：
--   EVAL_SAY / EVAL_L（Core 桥）· EVAL_DD_OPEN（全局下拉）· EVAL_IG_TOPLEFT（共用位置换算）·
--   EVAL_HELP_CONFIG.tb（与工具箱同一张真值表）· EVAL_WTT_*（1.73.14 的隔离 tooltip，绝不碰玩家正看的那个）

local DH = {
  built = false,   -- 图标帧是否已建（懒加载读值口）
  btn = nil,
  tex = nil,
  label = nil,
  hits = 0,        -- 成功下马次数（诊断）
  scans = 0,       -- 检测次数（诊断）
  lastIndex = nil, -- 最近一次识别到的内部索引（诊断）
  lastScan = -999,
  lastRun = -999,
  lastReason = "",
  regClicks = nil,
  leftClicks = 0,
  rightClicks = 0,
  lastBtn = nil,
  lastArgs = nil,
  autoUntil = 0,   -- 自动下马冷却（避免连续触发）
}

-- ===== 常量（单一来源，改这里就够） =====
local DH_SIZE = 26
local DH_DEF_W, DH_DEF_H = 1024, 768
local DH_TEXT = "马"
local DH_RATE = 0.5          -- 两次真正下马之间的最小间隔
local DH_AUTO_GAP = 2.0      -- 自动下马冷却（同类报错连发时只处理一次）
-- ★坐骑识别词表：照 LazyPig 的多模式兜底（中文描述用**模式**容忍百分比数字；英文/中文关键词并列）
local DH_PATTERNS = {
  "速度提高%d+%%", "速度提高", "增加移动速度", "移动速度提高",
  "Mount", "mount", "坐骑", "骑乘",
}
-- ★自动下马触发词：客户端以这些词拒绝动作时，说明「骑着马想干别的」（LazyPig 同款判据）
local DH_BLOCK_WORDS = { "你正在", "无法在", "骑乘", "骑在", "下马" }

-- ===== 配置与输出（唯一真值 = EVAL_HELP_CONFIG.tb） =====
local function dhCfg()
  -- ★★★1.74.20 用户：「骑乘助手…整块按角色」——两个开关与图标位置都存**角色级存档**。
  if type(EVAL_TB_CHAR_STORE) ~= "function" then return nil end
  return EVAL_TB_CHAR_STORE()
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function dhSay(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

local function dhSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function dhText(parent, size, r, g, b)
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

-- ===== 坐骑识别（本模块的核心） =====
-- 读某个内部索引对应光环的 tooltip 文本（走隔离 tooltip；玩家正看 tooltip 时如实返回不可信）
local function dhBuffText(bi)
  local may = true
  if type(EVAL_WTT_MAY_READ) == "function" then may = EVAL_WTT_MAY_READ() and true or false end
  if not may then return nil, false end
  if type(EVAL_DH_TEST_TEXT) == "function" then return EVAL_DH_TEST_TEXT(bi) end -- 测试钩子（生产环境不存在）
  local names = {}
  local ok = pcall(function()
    -- ★1.73.14：只碰**自建**的隔离 tooltip（EVAL_HELP_WTT），绝不碰 GameTooltip（那会清空玩家正看的物品提示）
    local wtt = rawget(_G, "EVAL_HELP_WTT")
    if not (wtt and wtt.SetPlayerBuff) then return end
    pcall(wtt.ClearLines, wtt)
    pcall(wtt.SetPlayerBuff, wtt, bi)
    for _, suffix in ipairs({ "TextLeft1", "TextLeft2", "TextLeft3", "TextRight1" }) do
      local fs = rawget(_G, "EVAL_HELP_WTT" .. suffix)
      if fs and fs.GetText then
        local t = fs:GetText()
        if type(t) == "string" and t ~= "" then table.insert(names, t) end
      end
    end
  end)
  if not ok then return nil, false end
  -- ★★一条文本都没读到 = **读不出来**（不是「读到空」）⇒ 如实报不可信：
  --   「查不到」≠「没有」，把「读不出」判成 NONE 会让功能在真机上静默失效（本项目铁律 5.2）。
  if table.getn(names) == 0 then return nil, false end
  return table.concat(names, " "), true
end

-- ★纯函数（可单测）：文本是否像坐骑
function EVAL_DH_IS_MOUNT_TEXT(text)
  if type(text) ~= "string" or text == "" then return false end
  for _, pat in ipairs(DH_PATTERNS) do
    if string.find(text, pat) then return true end
  end
  return false
end

-- ★检测：返回「坐骑光环的内部索引」或 nil（+原因）
-- 设计取舍：先按 CANCELABLE 过滤缩候选（少读 tooltip）；逐条读 tooltip 判坐骑；
--   tooltip 不可信（玩家正看提示 / 隔离件不可用）时**不猜**，如实返回「无法判定」。
function EVAL_DH_FIND_MOUNT()
  if type(GetPlayerBuff) ~= "function" then return nil, "NO_API" end
  local seen, unreadable = 0, 0
  for i = 0, 31 do
    local bi = GetPlayerBuff(i, "HELPFUL|CANCELABLE")
    if type(bi) ~= "number" or bi < 0 then break end
    seen = seen + 1
    local text, trusted = dhBuffText(bi)
    if trusted == false then unreadable = unreadable + 1 end
    if text and EVAL_DH_IS_MOUNT_TEXT(text) then return bi, "FOUND", text end
  end
  if unreadable > 0 and seen > 0 and unreadable >= seen then return nil, "UNREADABLE" end
  return nil, "NONE"
end

-- ★执行：一键下马
function EVAL_DH_DISMOUNT(quiet)
  DH.scans = DH.scans + 1
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - DH.lastRun < DH_RATE then
    DH.lastReason = "RATE"
    if not quiet then dhSay(L("DH_RATE")) end
    return false
  end
  local bi, why, text = EVAL_DH_FIND_MOUNT()
  DH.lastIndex = bi
  DH.lastReason = tostring(why)
  if not bi then
    if why == "NO_API" then
      if not quiet then dhSay(L("DH_NO_API")) end
    elseif why == "UNREADABLE" then
      if not quiet then dhSay(L("DH_UNREADABLE")) end
    else
      if not quiet then dhSay(L("DH_NOT_MOUNTED")) end
    end
    DH.lastScan = now
    return false
  end
  if type(CancelPlayerBuff) ~= "function" then
    if not quiet then dhSay(L("DH_NO_API")) end
    return false
  end
  local ok = pcall(CancelPlayerBuff, bi)
  if ok then
    DH.hits = DH.hits + 1
    DH.lastRun = now
    DH.lastScan = now
    if not quiet then dhSay(L("DH_DONE")) end
    if type(EVAL_DH_REFRESH) == "function" then pcall(EVAL_DH_REFRESH) end
    return true
  end
  if not quiet then dhSay(L("DH_FAILED")) end
  return false
end

-- ★是否在坐骑上（给图标染色 / 自动下马判据用；不依赖任何 Mount API）
function EVAL_DH_MOUNTED()
  local bi = EVAL_DH_FIND_MOUNT()
  return bi ~= nil
end

-- ===== 自动下马（可选开关；触发点照 LazyPig：被系统以「骑乘/你正在/无法在」拒绝时） =====
-- ★纯函数（可单测）：这条报错是否属于「该自动下马」的那种
function EVAL_DH_SHOULD_AUTO(msg, enabled, now, lastAt)
  if not enabled then return false end
  if type(msg) ~= "string" or msg == "" then return false end
  local hit = false
  for _, w in ipairs(DH_BLOCK_WORDS) do
    if string.find(msg, w) then hit = true break end
  end
  if not hit then return false end
  if type(now) == "number" and type(lastAt) == "number" and (now - lastAt) < DH_AUTO_GAP then return false end
  return true
end

function EVAL_DH_ON_UIMSG(msg)
  local tb = dhCfg() or {}
  local now = (type(GetTime) == "function") and GetTime() or 0
  if not EVAL_DH_SHOULD_AUTO(msg, tb.dismountAuto and true or false, now, DH.autoUntil) then return false end
  DH.autoUntil = now
  return EVAL_DH_DISMOUNT(true) -- 自动路径静默（不刷屏），失败也不播报
end

-- ===== 位置换算（与猎人助手/消耗品助手共用一份） =====
local function dhTopLeft(sw, sh, cx, cy)
  if type(EVAL_IG_TOPLEFT) == "function" then return EVAL_IG_TOPLEFT(sw, sh, DH_SIZE, cx, cy) end
  return sw / 2 + (tonumber(cx) or 0) - DH_SIZE / 2, -(sh / 2 - (tonumber(cy) or 0) - DH_SIZE / 2)
end

local function dhSavePos()
  local tb = dhCfg()
  if not (tb and DH.btn) then return end
  local okc, _ = pcall(DH.btn.GetCenter, DH.btn)
  if not okc then return end
  local c = { DH.btn:GetCenter() }
  if type(c[1]) ~= "number" then return end
  local okw, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  if not (okw and type(w2) == "number" and w2 > 0) then w2 = DH_DEF_W end
  if not (okh and type(h2) == "number" and h2 > 0) then h2 = DH_DEF_H end
  local oke, es = pcall(DH.btn.GetEffectiveScale, DH.btn)
  local k = (oke and type(es) == "number" and es > 0) and es or 1
  tb.dhX = c[1] / k - w2 / 2
  tb.dhY = c[2] / k - h2 / 2
end

function EVAL_DH_REAPPLY_POS()
  if not (DH.built and DH.btn) then return false end
  local tb = dhCfg() or {}
  local okc, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  if not (okc and type(w2) == "number" and w2 > 0) then w2 = DH_DEF_W end
  if not (okh and type(h2) == "number" and h2 > 0) then h2 = DH_DEF_H end
  local x, y = dhTopLeft(w2, h2, tb.dhX, tb.dhY)
  pcall(DH.btn.ClearAllPoints, DH.btn)
  pcall(DH.btn.SetPoint, DH.btn, "TOPLEFT", UIParent, "TOPLEFT", x, y)
  return true
end

-- ===== 图标刷新（有坐骑 = 亮金，无 = 半暗；纹理用该光环自己的图标） =====
function EVAL_DH_REFRESH()
  if not (DH.built and DH.btn) then return false end
  local bi = EVAL_DH_FIND_MOUNT()
  DH.lastIndex = bi
  local mounted = bi ~= nil
  local tex = nil
  if mounted and type(GetPlayerBuffTexture) == "function" then
    local okt, t = pcall(GetPlayerBuffTexture, bi)
    if okt and type(t) == "string" and t ~= "" then tex = t end
  end
  if tex then
    local ok = pcall(DH.tex.SetTexture, DH.tex, tex)
    if ok then pcall(DH.tex.Show, DH.tex) else pcall(DH.tex.Hide, DH.tex) end
    pcall(DH.label.Hide, DH.label)
  else
    pcall(DH.tex.Hide, DH.tex)
    pcall(DH.label.SetText, DH.label, DH_TEXT)
    pcall(DH.label.Show, DH.label)
  end
  -- 无坐骑时整体压暗（一眼看出「现在点了没用」），有坐骑则亮起
  local a = mounted and 1 or 0.45
  if DH.tex then pcall(DH.tex.SetVertexColor, DH.tex, a, a, a) end
  pcall(DH.btn.SetAlpha, DH.btn, mounted and 1 or 0.75)
  return true
end

-- ===== 懒建（幂等）：开关打开时才建帧 =====
function EVAL_DH_ENSURE()
  if DH.built and DH.btn then return DH.btn end
  local b = CreateFrame("Button", nil, UIParent)
  b:SetWidth(DH_SIZE)
  b:SetHeight(DH_SIZE)
  local tb = dhCfg() or {}
  local okc, w2 = pcall(UIParent.GetWidth, UIParent)
  local okh, h2 = pcall(UIParent.GetHeight, UIParent)
  if not (okc and type(w2) == "number" and w2 > 0) then w2 = DH_DEF_W end
  if not (okh and type(h2) == "number" and h2 > 0) then h2 = DH_DEF_H end
  local x, y = dhTopLeft(w2, h2, tb.dhX, tb.dhY)
  pcall(b.SetPoint, b, "TOPLEFT", UIParent, "TOPLEFT", x, y)
  pcall(b.SetMovable, b, true)
  pcall(b.EnableMouse, b, true)
  local okrc, errrc = pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  DH.regClicks = tostring(okrc) .. (okrc and "" or (":" .. tostring(errrc)))
  pcall(b.RegisterForDrag, b, "LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  dhSolid(bg, 0.06, 0.05, 0.04, 0.85)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  for i = 1, 4 do
    local e = b:CreateTexture(nil, "BORDER")
    dhSolid(e, 0.85, 0.70, 0.20, 0.9)
    if i == 1 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
      e:SetHeight(1)
    elseif i == 2 then
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      e:SetHeight(1)
    elseif i == 3 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
      e:SetWidth(1)
    else
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
      e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      e:SetWidth(1)
    end
  end
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  tex:Hide()
  local label = dhText(b, 12, 0.95, 0.80, 0.30)
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(label.SetWidth, label, DH_SIZE)
  label:SetText(DH_TEXT)
  DH.btn, DH.tex, DH.label, DH.built = b, tex, label, true
  -- ★右键要真的到得了分派代码：客户端 OnClick 参数形态不固定（与猎人助手同一实测结论）
  b:SetScript("OnClick", function(a, bb)
    local mbtn = (type(a) == "string" and a) or (type(bb) == "string" and bb) or
                 (type(arg1) == "string" and arg1) or "LeftButton"
    DH.lastBtn = mbtn
    DH.lastArgs = tostring(type(a)) .. "/" .. tostring(type(bb)) .. "/" .. tostring(type(arg1))
    if mbtn == "RightButton" then
      DH.rightClicks = DH.rightClicks + 1
      EVAL_DH_MENU()
    else
      DH.leftClicks = DH.leftClicks + 1
      EVAL_DH_DISMOUNT()
    end
  end)
  b:SetScript("OnEnter", function()
    if not (GameTooltip and GameTooltip.SetOwner) then return end
    pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
    local tb2 = dhCfg() or {}
    local mounted = EVAL_DH_MOUNTED()
    pcall(GameTooltip.AddLine, GameTooltip, L("DH_TIP_TITLE"), 1, 0.85, 0.35)
    pcall(GameTooltip.AddLine, GameTooltip, L("DH_TIP_L"), 0.92, 0.88, 0.80)
    pcall(GameTooltip.AddLine, GameTooltip, L("DH_TIP_R"), 0.92, 0.88, 0.80)
    pcall(GameTooltip.AddLine, GameTooltip,
      string.format(L("DH_TIP_STATE"), mounted and L("DH_YES") or L("DH_NO"),
        (tb2.dismountAuto and L("DH_YES") or L("DH_NO"))), 0.60, 0.60, 0.60)
    pcall(GameTooltip.Show, GameTooltip)
  end)
  b:SetScript("OnLeave", function() if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end end)
  b:SetScript("OnDragStart", function()
    pcall(b.SetMovable, b, true)
    pcall(b.StartMoving, b)
  end)
  b:SetScript("OnDragStop", function()
    pcall(b.StopMovingOrSizing, b)
    dhSavePos()
  end)
  return b
end

-- ===== 右键菜单（全局下拉件） =====
function EVAL_DH_MENU_MODEL()
  local tb = dhCfg() or {}
  return {
    L("DH_M_DISMOUNT"),
    string.format(L("DH_M_AUTO"), (tb.dismountAuto and L("DH_ON") or L("DH_OFF"))),
    L("DH_M_RESET"),
  }
end

function EVAL_DH_MENU()
  if type(EVAL_DD_OPEN) ~= "function" then return false end
  local items = EVAL_DH_MENU_MODEL()
  EVAL_DD_OPEN(DH.btn or UIParent, items, function(pi)
    local tb = dhCfg()
    if pi == 1 then
      EVAL_DH_DISMOUNT()
    elseif pi == 2 then
      if tb then tb.dismountAuto = not tb.dismountAuto end
      dhSay(string.format(L("DH_AUTO_SWITCH"), (tb and tb.dismountAuto) and L("DH_ON") or L("DH_OFF")))
      EVAL_TB_REFRESH()
    elseif pi == 3 then
      local tb2 = dhCfg()
      if tb2 then tb2.dhX, tb2.dhY = 0, 0 end
      EVAL_DH_REAPPLY_POS()
      dhSay(L("DH_POS_RESET"))
    end
  end)
  return true
end

-- ===== 工具箱开关的即时副作用 / 登录恢复 =====
function EVAL_DH_RESTORE()
  local tb = dhCfg()
  if not (tb and tb.dismount) then return false end -- 关着 = 一个帧都不建
  if not (DH.built and DH.btn) then
    EVAL_DH_ENSURE()
  else
    EVAL_DH_REAPPLY_POS()
  end
  EVAL_DH_REFRESH()
  if DH.btn then pcall(DH.btn.Show, DH.btn) end
  return true
end

function EVAL_DH_TOGGLE()
  local tb = dhCfg() or {}
  if not tb.dismount then
    if DH.btn then pcall(DH.btn.Hide, DH.btn) end
    dhSay(L("DH_OFF_MSG"))
    return false
  end
  EVAL_DH_ENSURE()
  EVAL_DH_REFRESH()
  if DH.btn then pcall(DH.btn.Show, DH.btn) end
  dhSay(string.format(L("DH_ON_MSG"), (tb.dismountAuto and L("DH_YES") or L("DH_NO"))))
  return true
end

-- ===== 事件：自动下马（可选）+ 坐骑状态刷新 =====
-- ★事件帧懒建：只有「一键下马」开关开着时才注册（关着 = 零开销）
local dhf = nil
local function dhEnsureEvents()
  local tb = dhCfg()
  if not (tb and tb.dismount) then return false end
  if dhf then return true end
  dhf = CreateFrame("Frame", "EVAL_DH_EVENTS", UIParent)
  pcall(dhf.RegisterEvent, dhf, "UI_ERROR_MESSAGE")
  pcall(dhf.RegisterEvent, dhf, "PLAYER_ENTERING_WORLD")
  dhf:SetScript("OnEvent", function()
    local en = event
    if type(en) ~= "string" then en = (type(arg1) == "string" and arg1) or arg2 end
    if en == "UI_ERROR_MESSAGE" then
      -- 三态兼容取消息文本（事件名可能占掉 arg1）
      local msg = (type(arg1) == "string" and arg1 ~= en) and arg1 or arg2
      if type(msg) == "string" then EVAL_DH_ON_UIMSG(msg) end
    elseif en == "PLAYER_ENTERING_WORLD" then
      EVAL_DH_REAPPLY_POS()
      EVAL_DH_REFRESH()
    end
  end)
  return true
end

function EVAL_DH_EVENTS_ENSURE() return dhEnsureEvents() end

-- ===== 诊断命令：/eh go 下马 [状态] =====
function EVAL_DH_CMD(msg)
  msg = tostring(msg or "")
  local sub = string.match(msg, "^go 下马%s*(.-)%s*$")
  if sub == nil then return false end
  if sub == "状态" or sub == "探针" then
    local bi, why, text = EVAL_DH_FIND_MOUNT()
    dhSay(string.format(L("DH_PROBE"), tostring(why), tostring(bi), tostring(text or "-"),
      tostring(DH.scans), tostring(DH.hits)))
    return true
  end
  EVAL_DH_DISMOUNT()
  return true
end

-- ===== 模块级状态复位 / 读值口（测试用；★放文件末尾，否则 DECL ORDER 会抓「用在前、声明在后」） =====
-- ★★读值口只**如实回读**状态，绝不复刻判据（否则变异 M577 会存活 —— 本项目老坑）
function EVAL_DH_TEST_STATE()
  return {
    built = DH.built, hits = DH.hits, scans = DH.scans,
    lastIndex = DH.lastIndex, lastReason = DH.lastReason,
    lastRun = DH.lastRun, lastScan = DH.lastScan,
    leftClicks = DH.leftClicks, rightClicks = DH.rightClicks,
    lastBtn = DH.lastBtn, lastArgs = DH.lastArgs,
    regClicks = DH.regClicks, hasEvents = (dhf ~= nil),
    shown = (DH.btn and DH.btn.IsShown and DH.btn:IsShown() == true) or false,
  }
end

function EVAL_DH_TEST_RESET()
  DH.hits, DH.scans, DH.lastIndex, DH.lastScan, DH.lastRun = 0, 0, nil, -999, -999
  DH.lastReason, DH.leftClicks, DH.rightClicks = "", 0, 0
  DH.autoUntil, DH.lastBtn, DH.lastArgs = 0, nil, nil
end

-- ★测试钩子：生产环境不存在 ⇒ dhBuffText 走真实 tooltip；测试里挂上它就能**如实模拟**
--   「光环在、但 tooltip 一条都读不出来」（组 182 ⑤ 的 UNREADABLE 分支靠它建起来）。
--   ★放在最前（早于任何真空 tooltip 读取），所以「读不出来」这个前提绝不可能被兜底函数复活。
-- ★测试读值口：用**给定参数**驱动真实 OnClick（本客户端参数形态不固定，四种都要能验）
function EVAL_TEST_DH_CLICK(a, b)
  if not (DH.btn and type(DH.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(DH.btn.GetScript, DH.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, a, b)
  return okc, err
end

-- ★测试读值口：图标几何（与其他两个助手同一套口径）
function EVAL_TEST_DH_GEOM()
  local b = DH.btn
  if not b then return nil end
  local okl, l = pcall(b.GetLeft, b)
  local okt, t = pcall(b.GetTop, b)
  local okw, w = pcall(b.GetWidth, b)
  local okh, h = pcall(b.GetHeight, b)
  return { left = okl and l or nil, top = okt and t or nil, w = okw and w or nil, h = okh and h or nil }
end

-- 帧与事件帧整体丢弃（组 182 模拟 /reload 用；生产环境不会调它）
function EVAL_DH_TEST_RESET_UI()
  if DH.btn then pcall(DH.btn.Hide, DH.btn) end
  DH.built, DH.btn, DH.tex, DH.label = false, nil, nil, nil
end
