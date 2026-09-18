-- EvalHelp · PetHelper.lua —— 抓宠帮手（1.73.0 独立载入：配置窗第 6 个 Tab）
-- 需求（用户原话）：顶部输入框支持数据检索「宠物技能」（搭配图标），检索下拉列表显示各等级的技能，
--   选中 → 技能详情页；详情页含技能简介 / 需求等级 / 所持有的宠物列表（领域图标 + 该宠物拥有的技能），
--   右侧放大镜点击宠物名 → 跳转「数据检索」Tab 并自动填入该名称检索，后续走数据检索自己的流程。
-- 数据源 = PetData.lua（由 doc/pet_info.png 逐行转录整理）；本文件只做检索与展示，不改主程序任何函数。
-- 依赖全局件：EVAL_PET_DB（PetData.lua）、EVAL_GET_LANG/EVAL_LOCALES（i18n）、EVAL_SAY（Core 桥）、
--   EVAL_HELP_CFG_TAB（判断本 Tab 是否激活）、EVAL_HELP_CFG_SETTAB（跳 Tab）、EVAL_DS_SEARCH_NAME（数据检索入口）

local PH = { built = false, q = "", view = "list", sel = nil, off = 0, detOff = 0,
             rows = {}, detRows = {}, detWidgets = {} }
local PH_TAB = 6          -- 配置窗第 6 个 Tab（与 EvalHelp.lua 的 tabNames 顺序一一对应）
local PH_ROW_H = 20       -- 结果行高
-- ★行数按**可用空间**反推（配置窗高 460，内容下沿取 -420，本项目「布局类需求先算空间」铁律）：
--   列表顶 -104 → floor((420-104)/20) = 15 行（末行下缘 -404，余量 16px）
--   详情宠物行顶 -146 → floor((420-146)/20) = 13 行（末行下缘 -406）
local PH_LIST_ROWS = 15
local PH_DET_ROWS = 13
local PH_X, PH_LIST_Y, PH_DET_Y = 20, -104, -146
-- 放大镜素材：客户端内置图标（望远镜）；写错路径只是不画，按钮文字仍在（不影响可用性）
local PH_ZOOM_ICON = "Interface\\Icons\\INV_Misc_Spyglass_02"

-- ===== 自绘基础件（与 Toolbox/DataSearch/IconBrowser 同风格） =====
local function phSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function phText(parent, size, r, g, b)
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

local function phBtn(parent, x, y, w, h, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  phSolid(bg, 0.22, 0.18, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local t = phText(b, 10, 0.95, 0.82, 0.35)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(label)
  b:SetScript("OnClick", onClick)
  return { btn = b, bg = bg, text = t }
end

-- ===== i18n =====
local function L(k)
  local lang = (type(EVAL_GET_LANG) == "function") and EVAL_GET_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function phSay(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

-- ===== 数据访问 =====
local function phDb() return rawget(_G, "EVAL_PET_DB") end

-- 全量条目：每个技能的每个等级一条（检索列表就列这个——用户要求「显示各等级的技能」）
local phEntryCache = nil
local function phEntries()
  if phEntryCache then return phEntryCache end
  local out = {}
  local db = phDb()
  if db and db.skills then
    for _, sk in ipairs(db.skills) do
      local ranks = (db.ranks and db.ranks[sk.name]) or {}
      for _, r in ipairs(ranks) do
        table.insert(out, { skill = sk, rank = r })
      end
    end
  end
  phEntryCache = out
  return out
end

local function phBeastsOf(skillName, rank)
  local db = phDb()
  local ranks = db and db.ranks and db.ranks[skillName]
  if not ranks then return {} end
  for _, r in ipairs(ranks) do
    if r.rank == rank then return r.beasts or {} end
  end
  return {}
end

local function phFamLabel(famId)
  local db = phDb()
  local f = db and db.families and db.families[famId]
  return (f and f.label) or tostring(famId or "?")
end

local function phFamIcon(famId)
  local db = phDb()
  local f = db and db.families and db.families[famId]
  return f and f.icon or nil
end

-- 关键字过滤：命中技能名 或 该等级任一驯服来源（野兽名/区域）——两种搜法都能用
local function phMatch(e, ql)
  if ql == "" then return true, nil end
  if string.find(string.lower(e.skill.name), ql, 1, true) then return true, nil end
  local beasts = e.rank.beasts or {}
  for _, b in ipairs(beasts) do
    if string.find(string.lower(b.name), ql, 1, true) then return true, b.name
    elseif string.find(string.lower(b.zone), ql, 1, true) then return true, b.zone end
  end
  return false, nil
end

local function phFiltered()
  local out = {}
  local ql = string.lower(PH.q or "")
  for _, e in ipairs(phEntries()) do
    local okHit = phMatch(e, ql)
    if okHit then table.insert(out, e) end
  end
  return out
end

-- 条目显示文本：技能名 · 等级N（需宠物等级X）  —— 有野兽命中时附上来源名
local function phEntryLabel(e, hit)
  local base = string.format(L("PH_ENTRY_FMT"), tostring(e.skill.name), e.rank.rank, e.rank.req)
  if hit then base = base .. string.format(L("PH_ENTRY_HIT"), tostring(hit)) end
  return base
end

-- ===== 跳转：放大镜 → 数据检索 =====
function EVAL_PH_JUMP(name)
  name = tostring(name or "")
  if name == "" then return false end
  local ok1 = false
  if type(EVAL_DS_SEARCH_NAME) == "function" then ok1 = pcall(EVAL_DS_SEARCH_NAME, name) and true or false end
  if type(EVAL_HELP_CFG_SETTAB) == "function" then pcall(EVAL_HELP_CFG_SETTAB, 4) end -- 第 4 个 Tab = 数据检索
  if not ok1 then phSay(L("PH_NO_DS")) end
  PH.lastJump = name
  return ok1
end

-- 打开详情（供列表行点击与测试调用）
function EVAL_PH_OPEN(idx)
  local list = phFiltered()
  local e = list[idx]
  if not e then return false end
  PH.sel = e
  PH.view = "detail"
  PH.detOff = 0
  EVAL_PH_REFRESH()
  return true
end

function EVAL_PH_BACK()
  PH.view = "list"
  PH.sel = nil
  EVAL_PH_REFRESH()
end

function EVAL_PH_SET_QUERY(q)
  PH.q = tostring(q or "")
  PH.off = 0
  if PH.eb then pcall(PH.eb.SetText, PH.eb, PH.q) end
  EVAL_PH_REFRESH()
  return PH.q
end

-- ===== 刷新（可见性契约：本 Tab 的控件全部走显式 Show/Hide） =====
function EVAL_PH_REFRESH()
  if not PH.built then return end
  local list = phFiltered()
  local detail = (PH.view == "detail") and PH.sel or nil

  -- 顶部计数 / 提示
  if PH.count then
    if detail then
      PH.count:SetText("")
    else
      PH.count:SetText(string.format(L("PH_COUNT"), table.getn(list)))
    end
  end
  if PH.ph then PH.ph:SetText((PH.q == "") and L("PH_PH") or "") end

  -- 列表行
  local maxOff = math.max(0, table.getn(list) - PH_LIST_ROWS)
  if PH.off > maxOff then PH.off = maxOff end
  for i = 1, PH_LIST_ROWS do
    local row = PH.rows[i]
    local e = (not detail) and list[PH.off + i] or nil
    row.btn:Hide()
    if e then
      row.btn:Show()
      if row.icon and e.skill.icon then pcall(row.icon.SetTexture, row.icon, e.skill.icon) end
      row.text:SetText(phEntryLabel(e))
      row.idx = PH.off + i
    end
  end

  -- 详情区
  for _, w in ipairs(PH.detWidgets) do pcall(w.Hide, w) end
  if detail then
    local sk, rk = detail.skill, detail.rank
    for _, w in ipairs(PH.detWidgets) do pcall(w.Show, w) end
    if PH.detIcon and sk.icon then pcall(PH.detIcon.SetTexture, PH.detIcon, sk.icon) end
    PH.detTitle:SetText(string.format(L("PH_DET_TITLE"), tostring(sk.name), rk.rank))
    PH.detIntro:SetText(tostring(sk.intro or ""))
    PH.detMeta:SetText(string.format(L("PH_DET_META"), sk.cost, tostring(sk.cast), tostring(sk.range), tostring(sk.cd)))
    PH.detReq:SetText(string.format(L("PH_DET_REQ"), rk.req))
    -- 宠物行
    local beasts = rk.beasts or {}
    if PH.detPetTitle then
      if table.getn(beasts) > 0 then
        PH.detPetTitle:SetText(string.format(L("PH_DET_PETS"), table.getn(beasts)))
      else
        -- 训练师被动技能没有驯服来源——如实说明，不显示空表（本项目「查不到 ≠ 没有」）
        PH.detPetTitle:SetText(L("PH_DET_TRAINER"))
      end
    end
    local dmax = math.max(0, table.getn(beasts) - PH_DET_ROWS)
    if PH.detOff > dmax then PH.detOff = dmax end
    for i = 1, PH_DET_ROWS do
      local row = PH.detRows[i]
      local b = beasts[PH.detOff + i]
      for _, w in ipairs({ row.icon, row.name, row.meta, row.zoom.btn }) do pcall(w.Hide, w) end
      if b then
        if row.icon and phFamIcon(b.fam) then
          pcall(row.icon.SetTexture, row.icon, phFamIcon(b.fam))
          pcall(row.icon.Show, row.icon)
        end
        row.name:SetText(tostring(b.name))
        row.meta:SetText(string.format(L("PH_PET_META"), tostring(b.level), tostring(b.zone), phFamLabel(b.fam)))
        pcall(row.zoom.btn.Show, row.zoom.btn)
        row.zoom.btn:SetScript("OnClick", function() EVAL_PH_JUMP(b.name) end)
        row.nameBtn:SetScript("OnClick", function() EVAL_PH_JUMP(b.name) end)
        row.beast = b
      end
    end
  end
end

-- ===== 构建 =====
function EVAL_PH_BUILD(root, page, refreshes)
  if PH.built then return end
  local widgets = page.widgets
  local W = 660
  if type(root.GetWidth) == "function" then
    local okw, wv = pcall(root.GetWidth, root)
    if okw and type(wv) == "number" and wv > 200 then W = wv end
  end
  local RX = W - 24

  -- 顶部检索行：输入框 + 计数
  local lab = phText(root, 11, 0.92, 0.88, 0.80)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -60)
  lab:SetText(L("PH_LABEL"))
  table.insert(widgets, lab)

  local boxX, boxW = PH_X + 96, 300
  local ebBg = root:CreateTexture(nil, "BACKGROUND")
  phSolid(ebBg, 0.10, 0.09, 0.06, 1)
  ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", boxX - 2, -54)
  ebBg:SetWidth(boxW + 4) ebBg:SetHeight(22)
  table.insert(widgets, ebBg)

  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_PH_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(boxW) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", boxX, -56)
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
    pcall(eb.SetJustifyH, eb, "LEFT")
    pcall(eb.SetJustifyV, eb, "MIDDLE")
    pcall(eb.SetTextInsets, eb, 2, 0, 0, 0)
    PH.eb = eb
    table.insert(widgets, eb)
    eb:SetScript("OnTextChanged", function()
      local okt, t = pcall(eb.GetText, eb)
      if okt and type(t) == "string" then
        PH.q = t
        PH.off = 0
        -- 纯本地数据过滤，无需去抖（数据量小）
        if PH.view == "detail" then PH.view = "list" PH.sel = nil end
        EVAL_PH_REFRESH()
      end
    end)
    eb:SetScript("OnEnterPressed", function() pcall(eb.ClearFocus, eb) end)
    eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
  end

  -- 占位提示（EditBox 不渲染时的保底，同样给提示）
  local ph = phText(root, 11, 0.55, 0.52, 0.45)
  ph:SetPoint("TOPLEFT", root, "TOPLEFT", boxX + 4, -59)
  pcall(ph.SetWidth, ph, boxW - 8)
  pcall(ph.SetJustifyH, ph, "LEFT")
  ph:SetText(L("PH_PH"))
  PH.ph = ph
  table.insert(widgets, ph)

  local cnt = phText(root, 11, 0.75, 0.72, 0.58)
  cnt:SetPoint("TOPLEFT", root, "TOPLEFT", boxX + boxW + 14, -59)
  pcall(cnt.SetWidth, cnt, 200)
  pcall(cnt.SetJustifyH, cnt, "LEFT")
  PH.count = cnt
  table.insert(widgets, cnt)

  local clearBtn = phBtn(root, RX - 60, -54, 60, 20, L("PH_CLEAR"), function() EVAL_PH_SET_QUERY("") end)
  table.insert(widgets, clearBtn.btn)
  PH.clearBtn = clearBtn

  -- 列表行池：图标 + 文本（整行可点 → 打开详情）
  for i = 1, PH_LIST_ROWS do
    local y = PH_LIST_Y - (i - 1) * PH_ROW_H
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(W - 40) b:SetHeight(PH_ROW_H - 2)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    phSolid(bg, 0.10, 0.09, 0.06, 1)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16) icon:SetHeight(16)
    icon:SetPoint("LEFT", b, "LEFT", 3, 0)
    local t = phText(b, 11, 0.92, 0.88, 0.80)
    t:SetPoint("LEFT", b, "LEFT", 24, 0)
    pcall(t.SetWidth, t, W - 80)
    pcall(t.SetJustifyH, t, "LEFT")
    table.insert(widgets, b)
    PH.rows[i] = { btn = b, bg = bg, icon = icon, text = t, idx = i }
  end

  -- 详情区：标题 + 简介 + 需求 + 宠物列表 + 返回
  local detIcon = root:CreateTexture(nil, "ARTWORK")
  detIcon:SetWidth(28) detIcon:SetHeight(28)
  detIcon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -58)
  table.insert(widgets, detIcon)
  PH.detIcon = detIcon

  local detTitle = phText(root, 12, 1, 0.85, 0.35)
  detTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 36, -60)
  pcall(detTitle.SetWidth, detTitle, 300)
  pcall(detTitle.SetJustifyH, detTitle, "LEFT")
  table.insert(widgets, detTitle)
  PH.detTitle = detTitle

  local detIntro = phText(root, 10, 0.85, 0.82, 0.72)
  detIntro:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 36, -78)
  pcall(detIntro.SetWidth, detIntro, W - 120)
  pcall(detIntro.SetJustifyH, detIntro, "LEFT")
  table.insert(widgets, detIntro)
  PH.detIntro = detIntro

  local detMeta = phText(root, 10, 0.70, 0.68, 0.55)
  detMeta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -100)
  pcall(detMeta.SetWidth, detMeta, W - 260)
  pcall(detMeta.SetJustifyH, detMeta, "LEFT")
  table.insert(widgets, detMeta)
  PH.detMeta = detMeta

  local detReq = phText(root, 10, 1, 0.75, 0.35)
  detReq:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 300, -100)
  pcall(detReq.SetWidth, detReq, 260)
  pcall(detReq.SetJustifyH, detReq, "LEFT")
  table.insert(widgets, detReq)
  PH.detReq = detReq

  local detPetTitle = phText(root, 11, 0.95, 0.80, 0.30)
  detPetTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -122)
  table.insert(widgets, detPetTitle)
  PH.detPetTitle = detPetTitle

  local backBtn = phBtn(root, RX - 70, -56, 70, 20, L("PH_BACK"), function() EVAL_PH_BACK() end)
  table.insert(widgets, backBtn.btn)
  PH.backBtn = backBtn

  -- 宠物行池：家族图标 + 名称（可点）+ 元信息 + 放大镜
  for i = 1, PH_DET_ROWS do
    local y = PH_DET_Y - (i - 1) * PH_ROW_H
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16) icon:SetHeight(16)
    icon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 2, y)
    table.insert(widgets, icon)
    local nb = CreateFrame("Button", nil, root)
    nb:SetWidth(150) nb:SetHeight(PH_ROW_H - 4)
    nb:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 22, y + 2)
    pcall(nb.EnableMouse, nb, true)
    pcall(nb.RegisterForClicks, nb, "LeftButtonUp")
    local name = phText(nb, 11, 0.92, 0.88, 0.80)
    name:SetPoint("LEFT", nb, "LEFT", 0, 0)
    pcall(name.SetWidth, name, 150)
    pcall(name.SetJustifyH, name, "LEFT")
    table.insert(widgets, nb)
    local meta = phText(root, 10, 0.70, 0.68, 0.55)
    meta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 180, y + 3)
    pcall(meta.SetWidth, meta, W - 300)
    pcall(meta.SetJustifyH, meta, "LEFT")
    table.insert(widgets, meta)
    local zoom = phBtn(root, RX - 26, y, 24, PH_ROW_H - 4, L("PH_ZOOM"), function() end)
    -- 放大镜素材（客户端内置望远镜图标）：路径若不对**静默不画**，按钮文字「查」仍是保底
    local zi = zoom.btn:CreateTexture(nil, "ARTWORK")
    zi:SetWidth(14) zi:SetHeight(14)
    zi:SetPoint("CENTER", zoom.btn, "CENTER", 0, 0)
    pcall(zi.SetTexture, zi, PH_ZOOM_ICON)
    table.insert(widgets, zi)
    pcall(zoom.btn.SetScript, zoom.btn, "OnEnter", function()
      if type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, zoom.btn, "ANCHOR_RIGHT")
        pcall(GameTooltip.AddLine, GameTooltip, L("PH_ZOOM_TIP"), 0.9, 0.85, 0.6)
        pcall(GameTooltip.Show, GameTooltip)
      end
    end)
    pcall(zoom.btn.SetScript, zoom.btn, "OnLeave", function()
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    table.insert(widgets, zoom.btn)
    PH.detRows[i] = { icon = icon, name = name, nameBtn = nb, meta = meta, zoom = zoom }
  end

  PH.detWidgets = { detIcon, detTitle, detIntro, detMeta, detReq, detPetTitle, backBtn.btn }
  for i = 1, PH_DET_ROWS do
    local r = PH.detRows[i]
    table.insert(PH.detWidgets, r.icon)
    table.insert(PH.detWidgets, r.nameBtn)
    table.insert(PH.detWidgets, r.name)
    table.insert(PH.detWidgets, r.meta)
    table.insert(PH.detWidgets, r.zoom.btn)
  end

  -- 点击列表行 → 详情（★local 作用域陷阱：OnClick 在所有控件建好后再挂）
  for i = 1, PH_LIST_ROWS do
    local row = PH.rows[i]
    row.btn:SetScript("OnClick", function()
      if row.idx then EVAL_PH_OPEN(row.idx) end
    end)
  end

  -- 滚轮：列表翻页 / 详情宠物翻页（链式接管，不吞别人事件）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  if type(root.GetScript) == "function" then
    local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  root:SetScript("OnMouseWheel", function(a, b)
    local active = true
    if type(EVAL_HELP_CFG_TAB) == "function" then active = (EVAL_HELP_CFG_TAB() == PH_TAB) end
    if active then
      local d = b or arg1 or 0
      if d ~= 0 then
        if PH.view == "detail" then
          PH.detOff = math.max(0, PH.detOff - d)
        else
          PH.off = math.max(0, PH.off - d)
        end
        EVAL_PH_REFRESH()
        return
      end
    end
    if prevWheel then pcall(prevWheel, a, b) end
  end)

  PH.built = true
  table.insert(refreshes, EVAL_PH_REFRESH)
  EVAL_PH_REFRESH()
end

-- ===== 测试钩子（读生产真值，不在测试里复刻逻辑） =====
function EVAL_PH_TEST_BUILT() return PH.built and true or false end
function EVAL_PH_TEST_STATE()
  return { view = PH.view, q = PH.q, off = PH.off, entries = table.getn(phEntries()), filtered = table.getn(phFiltered()) }
end
function EVAL_PH_TEST_ENTRY(i)
  local list = phFiltered()
  local e = list[i]
  if not e then return nil end
  return { skill = e.skill.name, rank = e.rank.rank, req = e.rank.req, beasts = table.getn(e.rank.beasts or {}) }
end
function EVAL_PH_TEST_LABEL(i) return phEntryLabel(phFiltered()[i] or {}) end
function EVAL_PH_TEST_DETAIL()
  local e = PH.sel
  if not e then return nil end
  return { skill = e.skill.name, rank = e.rank.rank, req = e.rank.req, intro = e.skill.intro, icon = e.skill.icon, beasts = e.rank.beasts }
end
function EVAL_PH_TEST_ROW(i)
  local r = PH.rows[i]
  if not r then return nil end
  return { shown = (r.btn.IsShown and r.btn:IsShown()) and true or false, text = r.text:GetText(), idx = r.idx }
end
function EVAL_PH_TEST_DETROW(i)
  local r = PH.detRows[i]
  if not r then return nil end
  return { name = r.name:GetText(), meta = r.meta:GetText(), zoomShown = (r.zoom.btn.IsShown and r.zoom.btn:IsShown()) and true or false }
end
function EVAL_PH_TEST_LAST_JUMP() return PH.lastJump end
function EVAL_PH_RESET_JUMP() PH.lastJump = nil end
function EVAL_PH_TEST_FAMILY_LABEL(f) return phFamLabel(f) end
function EVAL_PH_TEST_RESET() PH.q = "" PH.view = "list" PH.sel = nil PH.off = 0 PH.detOff = 0 PH.lastJump = nil if PH.eb then pcall(PH.eb.SetText, PH.eb, "") end end