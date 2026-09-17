-- EvalHelp · Share.lua —— 方案分享（1.71.0 独立载入：聊天频道分片传输 + 事件扫描接收 + 弹窗导入）
-- 可行性结论（调研定案）：
--   发送：SendChatMessage 是 Protected → RunScript 聊天脚本队列绕行（1.49.3 已验证范式，视同玩家手输 /script）
--   传输：hex 编码防聊天系统吃掉 |、"、链接符；220 hex 字符/片（原始 110B），头部 ~20B，总 < 255B 消息上限
--   接收：CHAT_MSG_* 事件扫描（免疫学习器 1.36.0 同款通道），按 发送者+id 缓存分片，收齐弹窗
--   点击：弹窗是自家按钮（规避 SetItemRef 是否存在的未知数）——用户点 [导入] 才导入
-- 依赖仅全局件：EVAL_SAY / EVAL_DD_OPEN / EVAL_IMPORT_TEXT（EvalHelp 桥）/ EVAL_PROFILE_TO_TEXT

local SH = { buf = {}, done = {} }
local SH_CHUNK = 220 -- 每片 hex 字符数

-- ===== 基础工具（文件独立：不依赖 Toolbox/EvalHelp 的 local 件） =====
local function shSay(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

local function L(k)
  local lang = (type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function shSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function shText(parent, size, r, g, b)
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

-- ===== 配置（接收开关，默认开） =====
local function shCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return { recv = true } end -- 未加载完成时按默认
  if type(c.share) ~= "table" then c.share = { recv = true } end
  if c.share.recv == nil then c.share.recv = true end
  return c.share
end

function EVAL_SHARE_RECV_ON()
  return shCfg().recv and true or false
end

function EVAL_SHARE_RECV_TOGGLE()
  local c = shCfg()
  c.recv = not c.recv
  shSay(L("SH_RECV_" .. (c.recv and "ON" or "OFF")))
  return c.recv
end

-- ===== hex 编解码（hex 切片不会劈开多字节汉字） =====
local function toHex(s)
  return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function fromHex(h)
  if type(h) ~= "string" or string.len(h) == 0 or math.mod(string.len(h), 2) ~= 0 then return nil end
  if string.find(h, "[^0-9a-fA-F]") then return nil end
  return (string.gsub(h, "..", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- ===== 发送侧 =====
-- 频道有效性预检（不在该频道时 SendChatMessage 静默失败，提前提示）
local SH_CHANS = {
  { id = "GUILD", name = function() return L("SH_CH_GUILD") end, ok = function() return type(IsInGuild) == "function" and IsInGuild() end },
  { id = "PARTY", name = function() return L("SH_CH_PARTY") end, ok = function() return type(GetNumPartyMembers) == "function" and (GetNumPartyMembers() or 0) > 0 end },
  { id = "RAID",  name = function() return L("SH_CH_RAID") end,  ok = function() return type(GetNumRaidMembers) == "function" and (GetNumRaidMembers() or 0) > 0 end },
  { id = "SAY",   name = function() return L("SH_CH_SAY") end,   ok = function() return true end },
}

function EVAL_SHARE_SEND(chanId)
  if type(EVAL_PROFILE_TO_TEXT) ~= "function" then shSay(L("SH_NOEXPORT")) return false end
  if type(RunScript) ~= "function" then shSay(L("SH_NORUNSCRIPT")) return false end
  local text = EVAL_PROFILE_TO_TEXT()
  if not text or text == "" then shSay(L("SH_EMPTY")) return false end
  local hex = toHex(text)
  local n = math.ceil(string.len(hex) / SH_CHUNK)
  local idh = string.format("%02x", math.random(0, 255))
  for i = 1, n do
    local body = "[EHPF#" .. idh .. " " .. i .. "/" .. n .. "]" .. string.sub(hex, (i - 1) * SH_CHUNK + 1, i * SH_CHUNK)
    RunScript('SendChatMessage("' .. body .. '", "' .. chanId .. '")') -- 纯 ASCII 负载，无引号/反斜杠需转义
  end
  shSay(string.format(L("SH_SENT"), n))
  return true
end

-- IO 窗 [分享] 按钮：频道下拉
function EVAL_SHARE_SEND_UI(anchor)
  if type(EVAL_DD_OPEN) ~= "function" then EVAL_SHARE_SEND("GUILD") return end
  local items, ids = {}, {}
  for _, c in ipairs(SH_CHANS) do
    table.insert(items, c.name())
    table.insert(ids, c.id)
  end
  EVAL_DD_OPEN(anchor, items, function(pi)
    local c = SH_CHANS[pi]
    if not c then return end
    if not c.ok() then shSay(L("SH_CH_NO")) return end
    EVAL_SHARE_SEND(c.id)
  end)
end

-- ===== 接收侧：事件扫描 + 分片缓存 + 收齐弹窗 =====
local SH_BUF_TIMEOUT = 60

local function shSweepBuf(now)
  for k, b in pairs(SH.buf) do
    if now - b.t > SH_BUF_TIMEOUT then SH.buf[k] = nil end
  end
end

local function shOnMsg(msg, sender)
  if type(msg) ~= "string" then return end
  local idh, i, n, payload = string.match(msg, "^%[EHPF#(%x+) (%d+)/(%d+)%](%x*)$")
  if not idh then return end
  if not shCfg().recv then return end
  i, n = tonumber(i), tonumber(n)
  if not i or not n or n < 1 or n > 99 then return end -- 防异常包
  sender = tostring(sender or "?")
  local now = (type(GetTime) == "function") and GetTime() or 0
  shSweepBuf(now)
  local key = sender .. "#" .. idh
  local b = SH.buf[key]
  if not b then b = { n = n, chunks = {}, got = 0, t = now } SH.buf[key] = b end
  b.t = now
  if not b.chunks[i] then
    b.chunks[i] = payload
    b.got = b.got + 1
  end
  if b.got >= b.n then
    SH.buf[key] = nil
    if SH.done[key] then return end -- 同一方案重复收齐不重复弹
    SH.done[key] = true
    local parts = {}
    for j = 1, b.n do parts[j] = b.chunks[j] or "" end
    local text = fromHex(table.concat(parts))
    if text then EVAL_SH_POPUP(sender, text) end
  end
end

function EVAL_SHARE_ONMSG(msg, sender) shOnMsg(msg, sender) end -- 测试直调

-- 聊天事件帧（三态兼容：事件名在 1参/2参/全局 event；参数随之一档右移）
local shf = CreateFrame("Frame", "EVAL_SHARE_EVENTS", UIParent)
shf:RegisterEvent("CHAT_MSG_GUILD")
shf:RegisterEvent("CHAT_MSG_PARTY")
shf:RegisterEvent("CHAT_MSG_RAID")
shf:RegisterEvent("CHAT_MSG_SAY")
shf:RegisterEvent("CHAT_MSG_WHISPER")
shf:SetScript("OnEvent", function()
  local msg, sender
  if type(event) == "string" then msg, sender = arg1, arg2
  elseif type(arg1) == "string" and string.find(arg1, "^CHAT_MSG_") then msg, sender = arg2, arg3
  else msg, sender = arg3, arg4 end
  shOnMsg(msg, sender)
end)

-- ===== 接收弹窗（自绘；点 [导入] 走 EVAL_IMPORT_TEXT 桥） =====
local shp = {}
-- ★1.71.2 弹窗最多显示几行方案详情（超出折叠为「…还有 N 行」）。
--   为什么要有上限：方案最多 12 技能 × 每行可能很长的条件串，弹窗不能无限增高。
local SH_DETAIL_MAX = 6

local function shPopupBuild()
  if shp.root then return end
  -- ★1.71.2 高度 130 → 200：要容纳「标题 + 6 行方案详情 + 按钮行」。
  --   算一遍：标题在 -10、详情首行 -52、6 行 × 12 = 至 -124、按钮行占底部 34 → 需要约 170，
  --   留余量取 200（长条件串还会占更宽，但不增高）。
  local W, H = 380, 200
  local root = CreateFrame("Frame", "EVAL_SHARE_POPUP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 140) -- 高于名称输入弹窗(130)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if type(EVAL_UIOFFSCREEN) == "function" and EVAL_UIOFFSCREEN(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local title = shText(root, 11, 0.95, 0.82, 0.35)
  title:SetPoint("TOP", root, "TOP", 0, -10)
  title:SetText(L("SH_POP_T"))
  local body = shText(root, 10, 0.92, 0.88, 0.80)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -34)
  pcall(body.SetWidth, body, W - 32)
  pcall(body.SetJustifyH, body, "LEFT")
  pcall(body.SetNonSpaceWrap, body, false) -- 不允许换行：过长的条件串宁可裁掉，也不要把行数搞乱
  shp.body = body
  -- ★1.71.2 用户要求：「在接收到方案分享的弹窗内，将方案的详细信息也显示」。
  --   原来只显示一行「XX 分享了《方案名》(N 个技能)」，用户看不到**具体有哪些技能/条件**，
  --   必须点导入进配置窗才知道内容。
  --   ★实现方式：按行显示（每条技能一个 FontString），而不是塞进一个多行 FontString——
  --     本客户端的多行 FontString 行高/换行行为不稳（本项目既有记录），逐行独立控件最可靠，
  --     也便于「最多显示 N 行」的裁剪与断言。
  shp.detailLines = {}
  for i = 1, SH_DETAIL_MAX do
    local fs = shText(root, 9, 0.80, 0.78, 0.70)
    fs:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -52 - (i - 1) * 12)
    pcall(fs.SetWidth, fs, W - 32)
    pcall(fs.SetJustifyH, fs, "LEFT")
    pcall(fs.SetNonSpaceWrap, fs, false)
    fs:Hide()
    -- ★注意：本弹窗是**独立弹窗**，不参与配置窗的 Tab 显隐契约，故没有 widgets 表可插。
    --   （误抄 EvalHelp.lua 的 page.widgets 写法会直接报 nil —— 本轮已避免。）
    shp.detailLines[i] = fs
  end
  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(90) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    shSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = shText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  local importBtn = bBtn(56, L("SH_IMPORT"), function()
    local p = SH.pending
    if not p then shp.root:Hide() return end
    if type(EVAL_IMPORT_TEXT) == "function" then
      local ok, msg = EVAL_IMPORT_TEXT(p.text)
      shSay(tostring(msg))
      if ok then shp.root:Hide() SH.pending = nil end
    else
      shSay(L("SH_NOIMPORT"))
    end
  end)
  bBtn(160, L("SH_IGNORE"), function() shp.root:Hide() SH.pending = nil end)
  shp.importBtn = importBtn -- ★1.71.2 供断言走**真实按钮**（否则只能直调导入函数，绕过了出问题的路径）
  root:Hide()
  shp.root = root
end

function EVAL_SH_POPUP(sender, text)
  shPopupBuild()
  -- 预览解析（只读不导入）：拿方案名与技能数
  local name, count = "?", 0
  if type(EVAL_PROFILE_FROM_TEXT) == "function" then
    local prof = EVAL_PROFILE_FROM_TEXT(text)
    if prof then name = tostring(prof.name) count = table.getn(prof.skills or {}) end
  end
  SH.pending = { sender = sender, text = text, name = name, count = count }
  shp.body:SetText(string.format(L("SH_POP_GOT"), tostring(sender), name, count))
  -- ★1.71.2 详情：把导入文本按行显示，让用户在**点导入之前**就能看清内容。
  --   用**逐个 FontString** 而非一个多行 FontString（本客户端多行行为不稳，逐行最可靠）。
  --   最多 SH_DETAIL_MAX 行，超出时最后一行提示还剩多少（不静默截断——诚实告知）。
  if shp.detailLines then
    local lines = {}
    for ln in string.gmatch(text or "", "[^\r\n]+") do table.insert(lines, ln) end
    local shown, total = 0, table.getn(lines)
    for i = 1, SH_DETAIL_MAX do
      local fs = shp.detailLines[i]
      if fs then
        local l = lines[i]
        if l then
          fs:SetText(l)
          fs:Show()
          shown = i
        else
          fs:Hide()
        end
      end
    end
    -- 超出部分：复用最后一行显示「…还有 N 行」
    if total > SH_DETAIL_MAX and shp.detailLines[SH_DETAIL_MAX] then
      shp.detailLines[SH_DETAIL_MAX]:SetText(string.format(L("SH_POP_MORE"), total - SH_DETAIL_MAX + 1))
      shp.detailLines[SH_DETAIL_MAX]:Show()
    end
  end
  shp.root:Show()
end

-- ★1.71.2（第十六轮）**删除 EVAL_SHARE_RECV_LABEL**（原先在这里）。
--   它唯一的作用是刷新那个「接收:开/关」按钮的文字，而那个按钮本轮已被用户要求删掉
--   （它与开关组的「接收方案」是同一个开关）→ 调用点归零，成为**孤儿函数**。
--   ★为什么必须删而不是留着：本项目刚刚才吃到一次「留着一份描述旧状态的代码」的亏
--     （见 EvalHelp.lua 里那段 `cfgWin.nav = nil` 的残留：按钮真的建了、登记却被清空，
--       而读它的测试钩子无人调用 → 整整几轮没人发现）。孤儿代码会让人以为「这块还有功能」。
--   ★若将来又需要「在某个按钮上显示接收开关状态」，照下面两行重写即可：
--     EVAL_SHARE_RECV_ON() 读当前值；文字用 string.format(L("SH_RECV"), L("SH_ON"/"SH_OFF"))。

-- ★1.71.2 测试钩子：弹窗**当前实际显示**的文本（标题行 + 详情行）。
--   用途：验「详情真的填进去了」。★必须读控件当前文本（走真实渲染），
--   不能只断言 SH.pending.text 里有内容——那是数据侧，与「有没有显示」是两件事。
function EVAL_TEST_SHARE_POPUP_TEXTS()
  local t = {}
  if shp.body then
    local okb, tb = pcall(shp.body.GetText, shp.body)
    if okb and type(tb) == "string" and tb ~= "" then table.insert(t, tb) end
  end
  for _, fs in ipairs(shp.detailLines or {}) do
    local okS, shown = pcall(fs.IsShown, fs)
    if okS and shown then
      local okt, txt = pcall(fs.GetText, fs)
      if okt and type(txt) == "string" and txt ~= "" then table.insert(t, txt) end
    end
  end
  return t
end

-- 测试观察口
function EVAL_SHARE_PENDING() return SH.pending end
function EVAL_SHARE_RESET() SH.buf = {} SH.done = {} SH.pending = nil end
-- ★1.71.2 测试钩子：按分享弹窗的 [导入] 按钮（走它自己的 OnClick 闭包）。
--   用户报的 bug 正是这条路径漏了刷新——直调 EVAL_IMPORT_TEXT 会绕过它、测不出来。
function EVAL_TEST_SHARE_CLICK_IMPORT()
  if not (shp.importBtn and shp.importBtn.GetScript) then return false end
  local fn = shp.importBtn:GetScript("OnClick")
  if not fn then return false end
  fn()
  return true
end
