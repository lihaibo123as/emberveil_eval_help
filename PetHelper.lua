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
-- ===== 布局常量（1.73.1 重排：**单一来源**，几何断言直接读由这些值画出来的真实控件）=====
local PH_ROW_H = 20       -- 每行高
local PH_X = 20           -- 左内边距
local PH_RPAD = 24        -- 右内边距（右边缘 = W - PH_RPAD）
-- ★行数按**可用空间**反推（配置窗高 460，内容下沿取 -420，本项目「布局类需求先算空间」铁律）：
--   列表顶 -104 → floor((420-104)/20) = 15 行（末行下缘 -404，余量 16px）
--   详情：属性行 -104 / 宠物标题 -126 / 分隔线 -142 / 宠物首行 -150 → 12 行（末行下缘 -390）
local PH_LIST_ROWS = 15
local PH_DET_ROWS = 12
local PH_LIST_Y = -104
local PH_DET_Y = -150
-- 控件宽度/右边缘关系（1.73.1 修重叠：原来是「谁写谁算」，现在集中成常量并由几何断言守着）
local PH_LABEL_W = 90     -- 搜索标签宽（x=PH_X）
local PH_BOX_W = 300      -- 输入框宽（x=PH_X+96）
local PH_CNT_W = 140      -- 计数文字宽（x=PH_X+96+PH_BOX_W+14 → 右端 570）
local PH_BTN_W = 60       -- [清除] 宽
local PH_BACK_W = 70      -- [返回] 宽
local PH_ZOOM_W = 24      -- [查]（放大镜）宽
local PH_NAME_W = 150     -- 宠物名格宽
local PH_META_X = 180     -- 宠物元信息起点（相对 PH_X）
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

-- ★1.73.1 查询词入口**只有这一个**（输入框 OnTextChanged 也走它）：
--   ① 改词 = 重新浏览列表 → 必须从详情页退回列表（否则「改了词还停在旧详情」，
--      而空结果提示又是列表视图的控件 → 用户看到一片空白）；
--   ② 回写输入框要**比对后再写**：本客户端的 SetText 会再触发 OnTextChanged，
--      无条件回写 = 递归（这是本项目「一个入口」与「别写回自己」两条纪律的交点）。
function EVAL_PH_SET_QUERY(q)
  q = tostring(q or "")
  PH.q = q
  PH.off = 0
  PH.view = "list"
  PH.sel = nil
  if PH.eb then
    local okc, cur = pcall(PH.eb.GetText, PH.eb)
    if not (okc and cur == q) then pcall(PH.eb.SetText, PH.eb, q) end
  end
  EVAL_PH_REFRESH()
  return PH.q
end

-- ===== 刷新（可见性契约：本 Tab 的控件全部走**显式** Show/Hide） =====
-- ★★★1.73.1 修的两处真事故（用户截图：「详情页信息错误 / 布局错乱」）：
--   ① 详情视图里**搜索行从没被隐藏** → 标签「宠物技能：」+ 输入框里的检索词 + 详情标题三层叠印在同一行
--      （截图里被读成「宠物技能爪击 · 等级爪击」），[清除] 还压在 [返回] 上；
--   ② 宠物行的名字与元信息先被 Hide、随后**只 Show 了图标和放大镜** → 宠物名/等级/区域/类型永远不显示
--      （截图里每行只剩「?」和「查」）。★测试桩里 SetText 与显隐是两件事，所以上一版断言只读文本，全绿。
function EVAL_PH_REFRESH()
  if not PH.built then return end
  local list = phFiltered()
  local detail = (PH.view == "detail") and PH.sel or nil

  -- ① 搜索行（标签 / 输入框 / 占位 / 计数 / [清除]）**只在列表视图显示**
  if PH.listRow then
    for _, w in ipairs(PH.listRow) do
      if detail then pcall(w.Hide, w) else pcall(w.Show, w) end
    end
  end
  if not detail then
    if PH.count then PH.count:SetText(string.format(L("PH_COUNT"), table.getn(list))) end
    if PH.ph then PH.ph:SetText((PH.q == "") and L("PH_PH") or "") end
  end

  -- ② 列表行（空结果时如实提示，不留一片空白）
  local maxOff = math.max(0, table.getn(list) - PH_LIST_ROWS)
  if PH.off > maxOff then PH.off = maxOff end
  local nList = table.getn(list)
  if PH.emptyList then
    if (not detail) and nList == 0 then
      PH.emptyList:SetText(string.format(L("PH_EMPTY_LIST"), tostring(PH.q)))
      pcall(PH.emptyList.Show, PH.emptyList)
    else
      pcall(PH.emptyList.Hide, PH.emptyList)
    end
  end
  for i = 1, PH_LIST_ROWS do
    local row = PH.rows[i]
    local e = (not detail) and list[PH.off + i] or nil
    row.btn:Hide()
    if e then
      row.btn:Show()
      if row.icon and e.skill.icon then pcall(row.icon.SetTexture, row.icon, e.skill.icon) end
      row.text:SetText(phEntryLabel(e))
      -- 交替底色：偶数行稍亮，长列表不再糊成一片（纯观感，不影响判定）
      if row.bg then
        if (PH.off + i) % 2 == 0 then phSolid(row.bg, 0.14, 0.12, 0.08, 1)
        else phSolid(row.bg, 0.10, 0.09, 0.06, 1) end
      end
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
    local nBeast = table.getn(beasts)
    if PH.detPetTitle then
      if nBeast > 0 then
        PH.detPetTitle:SetText(string.format(L("PH_DET_PETS"), nBeast))
      else
        -- 训练师被动技能没有驯服来源——如实说明，不显示空表（本项目「查不到 ≠ 没有」）
        PH.detPetTitle:SetText(L("PH_DET_TRAINER"))
      end
    end
    if PH.detScroll then
      if nBeast > PH_DET_ROWS then
        PH.detScroll:SetText(string.format(L("PH_SCROLL_HINT"), PH.detOff + 1, PH.detOff + PH_DET_ROWS, nBeast))
        pcall(PH.detScroll.Show, PH.detScroll)
      else
        pcall(PH.detScroll.Hide, PH.detScroll)
      end
    end
    local dmax = math.max(0, nBeast - PH_DET_ROWS)
    if PH.detOff > dmax then PH.detOff = dmax end
    for i = 1, PH_DET_ROWS do
      local row = PH.detRows[i]
      local b = beasts[PH.detOff + i]
      -- ★六个控件**都要显式管**：bg / icon / nameBtn / name / meta / zoom（1.73.1 修：原来漏 Show 名字与元信息）
      for _, w in ipairs({ row.bg, row.icon, row.nameBtn, row.name, row.meta, row.zoom.btn }) do pcall(w.Hide, w) end
      if b then
        if row.bg then
          if (PH.detOff + i) % 2 == 0 then phSolid(row.bg, 0.14, 0.12, 0.08, 1)
          else phSolid(row.bg, 0.10, 0.09, 0.06, 1) end
          pcall(row.bg.Show, row.bg)
        end
        local fi = phFamIcon(b.fam)
        if fi then pcall(row.icon.SetTexture, row.icon, fi) end
        pcall(row.icon.Show, row.icon)
        row.name:SetText(tostring(b.name))
        pcall(row.name.Show, row.name)
        row.meta:SetText(string.format(L("PH_PET_META"), tostring(b.level), tostring(b.zone), phFamLabel(b.fam)))
        pcall(row.meta.Show, row.meta)
        pcall(row.nameBtn.Show, row.nameBtn)
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
      -- 纯本地数据过滤，无需去抖（数据量小）；★走**唯一入口** EVAL_PH_SET_QUERY（含回写比对，不会递归）
      if okt and type(t) == "string" and t ~= PH.q then EVAL_PH_SET_QUERY(t) end
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
  -- ★宽度必须**收窄到不撞 [清除]**（1.73.1 修：原先宽 200 → 右端 630，而 [清除] 从 576 起 → 压字）
  pcall(cnt.SetWidth, cnt, PH_CNT_W)
  pcall(cnt.SetJustifyH, cnt, "LEFT")
  PH.count = cnt
  table.insert(widgets, cnt)

  local clearBtn = phBtn(root, RX - PH_BTN_W, -54, PH_BTN_W, 20, L("PH_CLEAR"), function() EVAL_PH_SET_QUERY("") end)
  table.insert(widgets, clearBtn.btn)
  PH.clearBtn = clearBtn
  -- ★1.73.1 搜索行整行成表：详情视图要**整行隐藏**（否则标签+输入框+详情标题叠印，[清除] 还压在 [返回] 上）
  PH.listRow = { lab, ebBg }
  if eb then table.insert(PH.listRow, eb) end
  table.insert(PH.listRow, ph)
  table.insert(PH.listRow, cnt)
  table.insert(PH.listRow, clearBtn.btn)

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

  -- 空结果如实提示（不留一片空白）
  local emptyList = phText(root, 11, 0.75, 0.72, 0.58)
  emptyList:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 4, PH_LIST_Y - 4)
  pcall(emptyList.SetWidth, emptyList, W - 80)
  pcall(emptyList.SetJustifyH, emptyList, "LEFT")
  table.insert(widgets, emptyList)
  PH.emptyList = emptyList

  -- 详情区：标题 + 简介 + 需求 + 宠物列表 + 返回
  -- ★1.73.1 详情页重排：图标 32、标题右移出图标、属性行与需求行**分列不相交**（原先 meta 宽 W-260、
  --   req 从 PH_X+300 起 → 两者重叠 100px，长文本必然撞在一起）——[返回] 只在详情显示，与 [清除] 不再抢同一格。
  local detIcon = root:CreateTexture(nil, "ARTWORK")
  detIcon:SetWidth(32) detIcon:SetHeight(32)
  detIcon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -58)
  table.insert(widgets, detIcon)
  PH.detIcon = detIcon

  local detTitle = phText(root, 12, 1, 0.85, 0.35)
  detTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 42, -60)
  pcall(detTitle.SetWidth, detTitle, 240)
  pcall(detTitle.SetJustifyH, detTitle, "LEFT")
  table.insert(widgets, detTitle)
  PH.detTitle = detTitle

  local detIntro = phText(root, 10, 0.85, 0.82, 0.72)
  detIntro:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 42, -84)
  pcall(detIntro.SetWidth, detIntro, W - (PH_X + 42) - PH_RPAD)
  pcall(detIntro.SetJustifyH, detIntro, "LEFT")
  table.insert(widgets, detIntro)
  PH.detIntro = detIntro

  local detMeta = phText(root, 10, 0.70, 0.68, 0.55)
  detMeta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -104)
  pcall(detMeta.SetWidth, detMeta, 300)
  pcall(detMeta.SetJustifyH, detMeta, "LEFT")
  table.insert(widgets, detMeta)
  PH.detMeta = detMeta

  local detReq = phText(root, 10, 1, 0.75, 0.35)
  detReq:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 310, -104)
  pcall(detReq.SetWidth, detReq, W - (PH_X + 310) - PH_RPAD)
  pcall(detReq.SetJustifyH, detReq, "LEFT")
  table.insert(widgets, detReq)
  PH.detReq = detReq

  local detPetTitle = phText(root, 11, 0.95, 0.80, 0.30)
  detPetTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -126)
  table.insert(widgets, detPetTitle)
  PH.detPetTitle = detPetTitle

  -- 宠物标题与宠物列表之间的分隔线（观感：区块分明；只在详情显示）
  local sep = root:CreateTexture(nil, "BACKGROUND")
  phSolid(sep, 0.32, 0.27, 0.16, 1)
  sep:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -142)
  sep:SetWidth(W - PH_X - PH_RPAD) sep:SetHeight(1)
  table.insert(widgets, sep)

  -- 宠物条目多于一屏时的**如实**提示（本项目的「绝不静默截断」）
  local detScroll = phText(root, 10, 0.70, 0.68, 0.55)
  detScroll:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 300, -126)
  pcall(detScroll.SetWidth, detScroll, W - (PH_X + 300) - PH_RPAD)
  pcall(detScroll.SetJustifyH, detScroll, "LEFT")
  table.insert(widgets, detScroll)
  PH.detScroll = detScroll

  local backBtn = phBtn(root, RX - PH_BACK_W, -58, PH_BACK_W, 20, L("PH_BACK"), function() EVAL_PH_BACK() end)
  table.insert(widgets, backBtn.btn)
  PH.backBtn = backBtn

  -- 宠物行池：底条 + 家族图标 + 名称（可点） + 元信息 + 放大镜
  --   ★列宽关系固定（互不相交）：名称 x=PH_X+26 宽 PH_NAME_W ｜ 元信息 x=PH_X+PH_META_X 宽 到 [查] 左边 -8 ｜ [查] 右贴 RX
  local metaW = W - (PH_X + PH_META_X) - PH_RPAD - PH_ZOOM_W - 8
  for i = 1, PH_DET_ROWS do
    local y = PH_DET_Y - (i - 1) * PH_ROW_H
    local bg = root:CreateTexture(nil, "BACKGROUND")
    phSolid(bg, 0.10, 0.09, 0.06, 1)
    bg:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, y + 2)
    bg:SetWidth(W - PH_X - PH_RPAD) bg:SetHeight(PH_ROW_H - 2)
    table.insert(widgets, bg)
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16) icon:SetHeight(16)
    icon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 5, y + 3)
    table.insert(widgets, icon)
    local nb = CreateFrame("Button", nil, root)
    nb:SetWidth(PH_NAME_W) nb:SetHeight(PH_ROW_H - 4)
    nb:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 26, y + 2)
    pcall(nb.EnableMouse, nb, true)
    pcall(nb.RegisterForClicks, nb, "LeftButtonUp")
    local name = phText(nb, 11, 0.92, 0.88, 0.80)
    name:SetPoint("LEFT", nb, "LEFT", 0, 0)
    pcall(name.SetWidth, name, PH_NAME_W)
    pcall(name.SetJustifyH, name, "LEFT")
    table.insert(widgets, nb)
    local meta = phText(root, 10, 0.70, 0.68, 0.55)
    meta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + PH_META_X, y + 4)
    pcall(meta.SetWidth, meta, metaW)
    pcall(meta.SetJustifyH, meta, "LEFT")
    table.insert(widgets, meta)
    local zoom = phBtn(root, RX - PH_ZOOM_W, y + 2, PH_ZOOM_W, PH_ROW_H - 4, L("PH_ZOOM"), function() end)
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
    PH.detRows[i] = { bg = bg, icon = icon, name = name, nameBtn = nb, meta = meta, zoom = zoom }
  end

  PH.detWidgets = { detIcon, detTitle, detIntro, detMeta, detReq, detPetTitle, sep, detScroll, backBtn.btn }
  for i = 1, PH_DET_ROWS do
    local r = PH.detRows[i]
    table.insert(PH.detWidgets, r.bg)
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
      -- ★1.73.3 方向单一来源（上滚 = 回到前面）
      local dir = EVAL_WHEEL_DIR(a, b)
      if dir ~= 0 then
        if PH.view == "detail" then
          PH.detOff = math.max(0, PH.detOff - dir)
        else
          PH.off = math.max(0, PH.off - dir)
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
-- ★1.73.1 断言入口：详情页**真实控件上的文字**（标题/简介/属性行/需求/宠物标题）
--   ★为什么需要它：用户报「详情页信息错误」——而此前只有 DETAIL（数据侧）钩子，读不到**渲染出来的那句话**。
function EVAL_PH_TEST_TEXTS()
  local t = {}
  for k, w in pairs({ title = PH.detTitle, intro = PH.detIntro, meta = PH.detMeta, req = PH.detReq, petTitle = PH.detPetTitle }) do
    local ok, v = pcall(w.GetText, w)
    t[k] = (ok and tostring(v or "")) or nil
  end
  return t
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
-- ★1.73.1 断言入口：本 Tab 的**真实几何与可见性**（布局审查用；测试里不许复刻坐标）。
--   为什么必须有它：这两处真事故（搜索行没隐藏 / 宠物行名字元信息没 Show）**文本全对、只是不可见**，
--   只读文本的断言全绿——必须能问到「这个控件此刻到底可不可见、矩形落在哪」。
function EVAL_PH_TEST_GEOM()
  local function rect(w)
    if not (w and w.GetLeft and w.GetTop) then return nil end
    local okl, l = pcall(w.GetLeft, w)
    local okt, t = pcall(w.GetTop, w)
    local okw, ww = pcall(w.GetWidth, w)
    local okh, hh = pcall(w.GetHeight, w)
    local oks, s = pcall(w.IsShown, w)
    if not (okl and okt and okw and okh) then return nil end
    return { x = l, y = t, w = ww, h = hh, shown = (oks and s) and true or false }
  end
  local function shown(w)
    if not (w and w.IsShown) then return false end
    local ok, s = pcall(w.IsShown, w)
    return (ok and s) and true or false
  end
  local out = { listRowShown = false, listRow = {}, list = {}, det = {} }
  if PH.listRow then
    for i, w in ipairs(PH.listRow) do
      out.listRow[i] = rect(w)
      if shown(w) then out.listRowShown = true end
    end
  end
  out.clearBtn = rect(PH.clearBtn and PH.clearBtn.btn)
  out.backBtn = rect(PH.backBtn and PH.backBtn.btn)
  out.emptyList = rect(PH.emptyList)
  out.emptyListShown = shown(PH.emptyList)
  out.detIcon = rect(PH.detIcon)
  out.detTitle = rect(PH.detTitle)
  out.detMeta = rect(PH.detMeta)
  out.detReq = rect(PH.detReq)
  out.detPetTitle = rect(PH.detPetTitle)
  out.detScroll = rect(PH.detScroll)
  for i = 1, PH_LIST_ROWS do
    local r = PH.rows[i]
    out.list[i] = { btn = rect(r.btn), text = r.text:GetText(), textShown = shown(r.text) }
  end
  for i = 1, PH_DET_ROWS do
    local r = PH.detRows[i]
    out.det[i] = { nameBtn = rect(r.nameBtn), name = rect(r.name), meta = rect(r.meta), icon = rect(r.icon),
                   zoom = rect(r.zoom.btn), bg = rect(r.bg),
                   nameShown = shown(r.name), metaShown = shown(r.meta), zoomShown = shown(r.zoom.btn),
                   nameText = r.name:GetText(), metaText = r.meta:GetText() }
  end
  return out
end
-- 家族图标（读生产表，不在测试里另写一份）——用来暴露「占位图」这件事
function EVAL_PH_TEST_FAM_ICON(f) return phFamIcon(f) end
function EVAL_PH_TEST_SKILL_ICON(name)
  local db = phDb()
  for _, sk in ipairs((db and db.skills) or {}) do if sk.name == name then return sk.icon end end
  return nil
end
function EVAL_PH_TEST_RESET() PH.q = "" PH.view = "list" PH.sel = nil PH.off = 0 PH.detOff = 0 PH.lastJump = nil if PH.eb then pcall(PH.eb.SetText, PH.eb, "") end end