-- EvalHelp · tools/IconGrid.lua —— 通用「背包式图标网格」选择器（1.74.5）
-- 为什么单独一个文件：喂食助手的「选食物」与消耗品助手的「选消耗品」共用**同一份**网格实现
--   （本项目铁律：同一内容不许两处各写 —— 否则改一处漏一处，且两边的行为会慢慢漂开）。
--
-- 能力（都是从喂食助手那份**已实测**的网格里抽出来的，行为不变）：
--   · 8 列 × 5 行 = 40 格/页的**池子复用**（翻页只换纹理与数据，不重建控件）；
--   · **高度按实际行数自适应**（用户截图要求：2 件时不能留一大片空白）；
--   · 计数「1-40 / N」+ [上翻][下翻]（到顶/到底藏箭头，**绝不静默截断**）；
--   · 滚轮翻页（方向单一来源 EVAL_WHEEL_DIR；上滚 = 回到前面）；
--   · 贴屏幕边**夹取**（锚点 = 调用方给的按钮，必要时左翻/上移）；
--   · 每格 tooltip：名字（品质色）+「名字 ×数量 [包 格]」+ spec.hint；
--   · 两种模式：single（点一下就回调并收起）/ multi（点一下切换选中，选中打角标，**不收起**）；
--   · 底栏右侧按钮由 spec 给（最多 2 个 + 永远有的 [关闭]），左侧固定 [上翻][下翻]。
--
-- 调用约定（spec）：
--   key        字符串，分页状态按它各存一份（"food" / "consumable"）
--   anchor     锚点按钮（面板贴在它右侧）
--   title      标题（已本地化）
--   hint       每格 tooltip 末行（已本地化）
--   mode       "single" | "multi"
--   candidates function() return list, total end   —— **每次刷新现算**（唯一真值）
--                 list[i] = { name=, bag=, slot=, tex=, count=, q= }
--   isSelected function(item) -> bool             —— multi 模式用（决定角标）
--   onPick     function(item)                     —— single：点即调用，随后收起
--   onToggle   function(item)                     —— multi：点即切换（不收起）
--   buttons    { {text=, fn=}, ... }（最多 2 个，右对齐排在 [关闭] 左边）
-- 依赖：EVAL_WHEEL_DIR（Core 桥）、EVAL_L（i18n）、GameTooltip、UIParent

-- ★注意两个概念**不许同名**：pageOf = 按 spec.key 记住的页号（表）；pages = 当前总页数（数）。
--   1.74.5 实踩：两者都叫 pages → REFRESH 把表覆盖成数字 → 收起网格时 IG.pages[key] 直接报
--   「attempt to index a number value」→ 选完食物点格子会**报错且不收起**（被共用件自检当场抓住）。
local IG = { built = false, spec = nil, cells = {}, pageOf = {}, page = 0, total = 0, cand = {},
             rowsUsed = 0, shown = false }

-- ===== 布局常量（单一来源） =====
local IG_COLS, IG_ROWS = 8, 5
-- ★1.74.5 用户（截图）：「打开选择框内的图标也太大了，和外层图标尺寸对齐」
--   ⇒ 格子 = 图标 = **26×26**（与两个助手的主图标 / 配置入口按钮同口径），步进 28（留 2px 缝）。
--   面板宽 = 20 + 7×28 + 26 = 242；高度按行数算（1 行 86 / 5 行 198）。
local IG_STEP, IG_BOX, IG_ICON = 28, 26, 26
local IG_PAD, IG_ROW = 10, 4
local IG_TITLE_H, IG_FOOT_H = 16, 16
local IG_PER = IG_COLS * IG_ROWS
local IG_BTN_W, IG_BTN_GAP, IG_BTN_W2 = 48, 6, 56
-- ★★★1.74.5 用户：「两个助手的选择框能否在点击框体外部自动关闭?」
--   项目里没有现成的「外部点击件」（EVAL_DD_OPEN 只靠再点锚点 / 宿主 OnHide / ESC），所以这里自己垫一张
--   **全屏透明捕手**：strata DIALOG、层 **239**（面板 240）⇒ 点在面板上永远走到面板的格子/按钮，捕手收不到；
--   点在任何别处 → 收起面板。★它必须**跟着面板显隐**：常驻可见 = 整屏点击被吞（这类件的经典事故）。
local IG_LEVEL, IG_CATCH_LEVEL = 240, 239
-- ★★面板宽 = max(网格宽, **底栏最小宽**)：格子缩到 26 后面板只有 242 宽，而底栏
--   [上翻][下翻] + [选技能][清除][关闭] 需要 278 —— 不取 max 就会**左组压住「选技能」**（本次实发现）。
--   网格仍从左边 PAD 起排，多出来的余量落在右侧（不会挤压格子）。
local IG_GRID_W = IG_PAD * 2 + (IG_COLS - 1) * IG_STEP + IG_BOX
local IG_FOOT_MIN = IG_PAD * 2 + (IG_BTN_W - 8) + IG_BTN_GAP + (IG_BTN_W - 8) + 8
                    + IG_BTN_W2 + IG_BTN_GAP + IG_BTN_W + IG_BTN_GAP + IG_BTN_W
local IG_W = math.max(IG_GRID_W, IG_FOOT_MIN)
local IG_DEF_W, IG_DEF_H = 1024, 768
local IG_MARK = 10 -- 选中角标边长（multi 模式）

local function igHeight(rows)
  rows = tonumber(rows) or 1
  if rows < 1 then rows = 1 end
  if rows > IG_ROWS then rows = IG_ROWS end
  return IG_PAD + IG_TITLE_H + IG_ROW + (rows - 1) * IG_STEP + IG_BOX + IG_ROW + IG_FOOT_H + IG_PAD
end
local IG_HMAX = igHeight(IG_ROWS)

local function igL(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function igSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function igText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(fs.SetFontObject, fs, fo) then ok = true break end
  end
  if not ok then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okf, ok2 = pcall(fs.SetFont, fs, fp, size, "")
      if okf and ok2 then ok = true break end
    end
  end
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

-- 小文字按钮（自绘；宽度由调用方给 —— 换语言不许溢出）
local function igBtn(parent, w, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(15)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  igSolid(bg, 0.17, 0.15, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local fs = igText(b, 10, 0.95, 0.88, 0.72)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(fs.SetWidth, fs, w)
  pcall(fs.SetNonSpaceWrap, fs, false)
  pcall(fs.SetJustifyH, fs, "CENTER")
  fs:SetText(label)
  b:SetScript("OnEnter", function() pcall(bg.SetVertexColor, bg, 0.32, 0.27, 0.14, 1) end)
  b:SetScript("OnLeave", function() pcall(bg.SetVertexColor, bg, 0.17, 0.15, 0.10, 1) end)
  return { btn = b, bg = bg, text = fs, label = label }
end

local function igQualityRGB(q)
  if type(GetItemQualityColor) == "function" then
    local ok, r, g, b = pcall(GetItemQualityColor, tonumber(q) or 1)
    if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
  end
  return 0.72, 0.72, 0.72
end

-- ===== 通用纯函数：位置换算（两个助手共用 —— 免得各写一份、方向/尺寸错一个就歪）=====
-- 存的是「中心偏移」(cx 向右为正、cy 向上为正)，落点用 TOPLEFT 锚点：
--   x = w/2 + cx - size/2；y = -(h/2 - cy - size/2)（**y 向下为负**）
-- ★夹取：偏移量先夹到 [-(w/2-size/2), w/2-size/2]、y 同理 ⇒ 图标四边永远在屏幕内。
function EVAL_IG_TOPLEFT(sw, sh, size, cx, cy)
  sw, sh, size = tonumber(sw) or 1024, tonumber(sh) or 768, tonumber(size) or 36
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local maxX, maxY = sw / 2 - size / 2, sh / 2 - size / 2
  if maxX < 0 then maxX = 0 end
  if maxY < 0 then maxY = 0 end
  if cx > maxX then cx = maxX elseif cx < -maxX then cx = -maxX end
  if cy > maxY then cy = maxY elseif cy < -maxY then cy = -maxY end
  return sw / 2 + cx - size / 2, -(sh / 2 - cy - size / 2)
end

-- ===== 通用数据源：扫背包（喂食/消耗品两个助手共用 —— 免得两处各写一份扫描，行为慢慢漂开）=====
-- 返回 list, total；list[i] = { name=, bag=, slot=, tex=, count=, locked=, q=, idx= }
-- ★不做任何「像不像食物/消耗品」的判断：那由调用方排序（本客户端也没有「某物品是不是消耗品」的 API）。
function EVAL_IG_SCAN_BAGS(bags)
  bags = bags or { 0, 1, 2, 3, 4 }
  local out, total = {}, 0
  for bi = 1, table.getn(bags) do
    local bag = bags[bi]
    local slots = 0
    if type(GetContainerNumSlots) == "function" then
      local ok, v = pcall(GetContainerNumSlots, bag)
      slots = (ok and tonumber(v)) or 0
    end
    for slot = 1, slots do
      local nm = nil
      if type(GetContainerItemLink) == "function" then
        local okl, link = pcall(GetContainerItemLink, bag, slot)
        if okl and type(link) == "string" then nm = string.match(link, "%[(.-)%]") end
      end
      if nm and nm ~= "" then
        local tex, cnt, locked, q = nil, nil, nil, nil
        if type(GetContainerItemInfo) == "function" then
          local oki, t, c, lk, qq = pcall(GetContainerItemInfo, bag, slot)
          if oki then
            if type(t) == "string" and t == "" then t = nil end -- 空格子返回空串（空串在 Lua 里是真值）
            tex, cnt, locked, q = t, tonumber(c), (lk and true or false), tonumber(qq)
          end
        end
        total = total + 1
        table.insert(out, { name = nm, bag = bag, slot = slot, tex = tex, count = cnt,
                            locked = locked, q = q, idx = total })
      end
    end
  end
  return out, total
end

-- ===== 面板（懒建；只建一次，spec 每次打开时换） =====
function EVAL_IG_ENSURE()
  if IG.built and IG.frame then return IG end
  -- 捕手先建（面板的 OnHide 要引用它）：全屏透明 Button，比面板低一级
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  pcall(catcher.SetFrameStrata, catcher, "DIALOG")
  pcall(catcher.SetFrameLevel, catcher, IG_CATCH_LEVEL) -- ★必须**低于**面板（否则面板上的点击也被它吃掉）
  pcall(catcher.EnableMouse, catcher, true)
  pcall(catcher.RegisterForClicks, catcher, "LeftButtonUp", "RightButtonUp")
  catcher:SetScript("OnClick", function() EVAL_IG_HIDE() end) -- 点框体外部 = 关闭
  catcher:Hide()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetWidth(IG_W)
  f:SetHeight(IG_HMAX)
  pcall(f.SetFrameStrata, f, "DIALOG")
  pcall(f.SetFrameLevel, f, IG_LEVEL) -- 高于配置窗各弹窗(100~230)、低于全局下拉(250)
  -- ★捕手的显隐**只由这里统一负责**：面板一藏（不管是点格子收起、点关闭、还是被别的代码 Hide）捕手立刻跟着藏，
  --   绝不会出现「面板没了、捕手还在吞点击」这种最难查的状态。
  f:SetScript("OnHide", function() pcall(catcher.Hide, catcher) end)
  pcall(f.EnableMouse, f, true)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  igSolid(bg, 0.05, 0.05, 0.06, 0.95)
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  for i = 1, 4 do -- 面板自身的 1px 亮边（格子不画边框 —— 用户要求）
    local e = f:CreateTexture(nil, "BORDER")
    igSolid(e, 0.85, 0.70, 0.20, 0.9)
    if i == 1 then
      e:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) e:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 2 then
      e:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0) e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 3 then
      e:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) e:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0) e:SetWidth(1)
    end
    if i == 4 then
      e:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0) e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0) e:SetWidth(1)
    end
  end
  local title = igText(f, 11, 1, 0.85, 0.35)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", IG_PAD, -(IG_PAD - 2))
  pcall(title.SetWidth, title, IG_W - IG_PAD * 2 - 96)
  pcall(title.SetNonSpaceWrap, title, false)
  local cnt = igText(f, 10, 0.72, 0.70, 0.60)
  cnt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -IG_PAD, -(IG_PAD - 1))
  pcall(cnt.SetWidth, cnt, 96)
  pcall(cnt.SetJustifyH, cnt, "RIGHT")
  pcall(cnt.SetNonSpaceWrap, cnt, false)
  local gridTop = -(IG_PAD + IG_TITLE_H + IG_ROW)
  IG.cells = {}
  for i = 1, IG_PER do
    local col = math.mod(i - 1, IG_COLS)
    local row = math.floor((i - 1) / IG_COLS)
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(IG_BOX)
    b:SetHeight(IG_BOX)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", IG_PAD + col * IG_STEP, gridTop - row * IG_STEP)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local tex = b:CreateTexture(nil, "OVERLAY")
    tex:SetWidth(IG_ICON)
    tex:SetHeight(IG_ICON)
    tex:SetPoint("CENTER", b, "CENTER", 0, 0)
    local mark = b:CreateTexture(nil, "OVERLAY") -- 选中角标（multi 模式）
    igSolid(mark, 0.35, 1, 0.35, 1)
    mark:SetWidth(IG_MARK)
    mark:SetHeight(IG_MARK)
    mark:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    mark:Hide()
    local num = igText(b, 9, 1, 0.96, 0.80)
    num:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    pcall(num.SetWidth, num, IG_BOX - 4)
    pcall(num.SetJustifyH, num, "RIGHT")
    pcall(num.SetNonSpaceWrap, num, false)
    local cell = { btn = b, tex = tex, num = num, mark = mark, item = nil, sel = false }
    b:SetScript("OnClick", function()
      local it = cell.item
      if not it or not IG.spec then return end
      if IG.spec.mode == "multi" then
        if type(IG.spec.onToggle) == "function" then pcall(IG.spec.onToggle, it) end
        EVAL_IG_REFRESH() -- 角标立刻反映新状态（不收起 —— 多选要能连点）
      else
        if type(IG.spec.onPick) == "function" then pcall(IG.spec.onPick, it) end
        EVAL_IG_HIDE()
      end
    end)
    b:SetScript("OnEnter", function()
      local it = cell.item
      if it then pcall(tex.SetVertexColor, tex, 1, 0.92, 0.55) end -- 悬停：提亮图标（不画高亮框）
      if not it or type(GameTooltip) ~= "table" or not IG.spec then return end
      local qr, qg, qb = igQualityRGB(it.q)
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
      pcall(GameTooltip.ClearLines, GameTooltip)
      pcall(GameTooltip.AddLine, GameTooltip, tostring(it.name), qr, qg, qb)
      pcall(GameTooltip.AddLine, GameTooltip,
            string.format("%s ×%s  [%s,%s]", tostring(it.name), tostring(it.count or 1),
                          tostring(it.bag), tostring(it.slot)), 0.85, 0.85, 0.85)
      if IG.spec.hint then pcall(GameTooltip.AddLine, GameTooltip, IG.spec.hint, 0.55, 0.90, 0.55) end
      if IG.spec.mode == "multi" and cell.sel then
        pcall(GameTooltip.AddLine, GameTooltip, igL("IG_SELECTED"), 0.45, 1, 0.45)
      end
      pcall(GameTooltip.Show, GameTooltip)
    end)
    b:SetScript("OnLeave", function()
      pcall(tex.SetVertexColor, tex, 1, 1, 1)
      if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    b:Hide()
    IG.cells[i] = cell
  end
  -- 底栏：左 [上翻][下翻]；右 关闭 + 最多两个 spec 按钮（从右往左摆）
  local footY = -(IG_HMAX - IG_PAD - IG_FOOT_H)
  IG.footY0 = footY
  local up = igBtn(f, IG_BTN_W - 8, igL("TB_UP"))
  local dn = igBtn(f, IG_BTN_W - 8, igL("TB_DN"))
  local close = igBtn(f, IG_BTN_W, igL("LOADPOP_CLOSE"))
  local bA = igBtn(f, IG_BTN_W, "")
  local bB = igBtn(f, IG_BTN_W2, "")
  IG.footX = { up = IG_PAD, dn = IG_PAD + (IG_BTN_W - 8) + IG_BTN_GAP,
               close = IG_W - IG_PAD - IG_BTN_W,
               a = IG_W - IG_PAD - IG_BTN_W - IG_BTN_GAP - IG_BTN_W,
               b = IG_W - IG_PAD - IG_BTN_W - IG_BTN_GAP - IG_BTN_W - IG_BTN_GAP - IG_BTN_W2 }
  local function place(t, x, y)
    if not t then return end
    pcall(t.btn.ClearAllPoints, t.btn)
    pcall(t.btn.SetPoint, t.btn, "TOPLEFT", f, "TOPLEFT", x, y)
  end
  for _, pair in ipairs({ { up, "up" }, { dn, "dn" }, { close, "close" }, { bA, "a" }, { bB, "b" } }) do
    place(pair[1], IG.footX[pair[2]], footY)
  end
  up.btn:SetScript("OnClick", function() EVAL_IG_PAGE(-1) end)
  dn.btn:SetScript("OnClick", function() EVAL_IG_PAGE(1) end)
  close.btn:SetScript("OnClick", function() EVAL_IG_HIDE() end)
  bA.btn:SetScript("OnClick", function()
    if IG.spec and type(IG.spec.btnA) == "function" then pcall(IG.spec.btnA) end
  end)
  bB.btn:SetScript("OnClick", function()
    if IG.spec and type(IG.spec.btnB) == "function" then pcall(IG.spec.btnB) end
  end)
  pcall(f.EnableMouseWheel, f, true)
  pcall(f.SetScript, f, "OnMouseWheel", function(a, b)
    local dir = EVAL_WHEEL_DIR(a, b) -- ★方向单一来源（上滚 = 回到前面）
    if dir == 0 then return end
    EVAL_IG_PAGE(-dir)
  end)
  f:Hide()
  IG.frame, IG.title, IG.cnt, IG.catcher = f, title, cnt, catcher
  IG.up, IG.dn, IG.closeBtn, IG.btnA, IG.btnB = up, dn, close, bA, bB
  IG.placeFoot = place
  IG.built = true
  return IG
end
-- ===== 刷新（高度自适应 + 分页 + 计数 + 选中角标） =====
function EVAL_IG_REFRESH()
  if not (IG.built and IG.spec) then return false end
  local spec = IG.spec
  local cand, total = nil, 0
  if type(spec.candidates) == "function" then
    local okc, l, t = pcall(spec.candidates)
    if okc then cand, total = l, t end
  end
  cand = cand or {}
  IG.cand, IG.total = cand, tonumber(total) or table.getn(cand)
  local n = table.getn(cand)
  local pages = math.max(1, math.ceil(n / IG_PER))
  if IG.page > pages - 1 then IG.page = pages - 1 end
  if IG.page < 0 then IG.page = 0 end
  local first = IG.page * IG_PER + 1
  local last = first + IG_PER - 1
  if last > n then last = n end
  local filledPage, selCount = 0, 0
  for i = 1, IG_PER do
    local c = IG.cells[i]
    local it = cand[IG.page * IG_PER + i]
    if it then
      filledPage = filledPage + 1
      if it.tex then
        pcall(c.tex.SetTexture, c.tex, it.tex)
        pcall(c.tex.Show, c.tex)
      else
        pcall(c.tex.Hide, c.tex)
      end
      if (it.count or 1) > 1 then
        pcall(c.num.SetText, c.num, tostring(it.count))
        pcall(c.num.Show, c.num)
      else
        pcall(c.num.Hide, c.num)
      end
      local sel = false
      if spec.mode == "multi" and type(spec.isSelected) == "function" then
        local oks, v = pcall(spec.isSelected, it)
        sel = (oks and v) and true or false
      end
      c.sel = sel
      if sel then
        pcall(c.mark.Show, c.mark)
        selCount = selCount + 1
      else
        pcall(c.mark.Hide, c.mark)
      end
      c.item = it
      c.btn:Show()
    else
      c.item, c.sel = nil, false
      pcall(c.mark.Hide, c.mark)
      pcall(c.tex.Hide, c.tex)
      pcall(c.num.Hide, c.num)
      c.btn:Hide()
    end
  end
  IG.selCount = selCount
  -- 高度按本页实际行数收（用户截图：2 件不能留一大片空白）
  local rowsUsed = 1
  if filledPage > 0 then rowsUsed = math.ceil(filledPage / IG_COLS) end
  if rowsUsed < 1 then rowsUsed = 1 end
  if rowsUsed > IG_ROWS then rowsUsed = IG_ROWS end
  if IG.rowsUsed ~= rowsUsed then
    IG.rowsUsed = rowsUsed
    local H = igHeight(rowsUsed)
    pcall(IG.frame.SetHeight, IG.frame, H)
    local fy = -(H - IG_PAD - IG_FOOT_H)
    if IG.placeFoot and IG.footX then
      for _, pair in ipairs({ { IG.up, "up" }, { IG.dn, "dn" }, { IG.closeBtn, "close" },
                              { IG.btnA, "a" }, { IG.btnB, "b" } }) do
        IG.placeFoot(pair[1], IG.footX[pair[2]], fy)
      end
    end
  end
  if n == 0 then
    pcall(IG.cnt.SetText, IG.cnt, igL("IG_EMPTY"))
  elseif n > IG_PER then
    pcall(IG.cnt.SetText, IG.cnt, string.format("%d-%d / %d", first, last, n))
  else
    pcall(IG.cnt.SetText, IG.cnt, string.format("%d", n))
  end
  if IG.up then if IG.page > 0 then IG.up.btn:Show() else IG.up.btn:Hide() end end
  if IG.dn then if IG.page < pages - 1 then IG.dn.btn:Show() else IG.dn.btn:Hide() end end
  IG.pages = pages
  return true
end

function EVAL_IG_PAGE(delta)
  if not (IG.built and IG.spec) then return false end
  local pages = IG.pages or 1
  local p = (IG.page or 0) + (tonumber(delta) or 0)
  if p < 0 then p = 0 end
  if p > pages - 1 then p = pages - 1 end
  IG.page = p
  return EVAL_IG_REFRESH()
end

function EVAL_IG_HIDE()
  if IG.catcher then pcall(IG.catcher.Hide, IG.catcher) end
  if IG.built and IG.frame then pcall(IG.frame.Hide, IG.frame) end
  if IG.spec and IG.spec.key then IG.pageOf[IG.spec.key] = IG.page or 0 end
  IG.shown = false
  if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
  return true
end

function EVAL_IG_IS_SHOWN()
  if not (IG.built and IG.frame) then return false end
  local oks, v = pcall(IG.frame.IsShown, IG.frame)
  return (oks and v) and true or false
end

-- 打开（spec 每次换；同一个 spec 再开 = 收起，开关语义）
function EVAL_IG_OPEN(spec)
  if type(spec) ~= "table" then return false end
  EVAL_IG_ENSURE()
  if EVAL_IG_IS_SHOWN() and IG.spec and IG.spec.key == spec.key then
    EVAL_IG_HIDE()
    return true
  end
  IG.spec = spec
  IG.page = tonumber(IG.pageOf[spec.key]) or 0
  if spec.title then pcall(IG.title.SetText, IG.title, spec.title) end
  -- 底部两个可选按钮（标签/回调/显隐都由 spec 定）
  local slots = { { IG.btnA, spec.btnA, spec.btnAText }, { IG.btnB, spec.btnB, spec.btnBText } }
  for i = 1, 2 do
    local t, fn, label = slots[i][1], slots[i][2], slots[i][3]
    if t then
      if type(fn) == "function" then
        pcall(t.text.SetText, t.text, tostring(label or ""))
        pcall(t.btn.Show, t.btn)
      else
        pcall(t.btn.Hide, t.btn)
      end
    end
  end
  EVAL_IG_REFRESH()
  -- 贴锚点右侧；贴屏幕边就左翻/上移（夹取，绝不跑出屏幕）
  local f = IG.frame
  pcall(f.ClearAllPoints, f)
  if spec.anchor then pcall(f.SetPoint, f, "BOTTOMRIGHT", spec.anchor, "TOPRIGHT", 6, 6) end
  pcall(f.Show, f)
  if IG.catcher then pcall(IG.catcher.Show, IG.catcher) end -- ★开面板的同一刻才把捕手放出来
  IG.shown = true
  local okw, sw = pcall(UIParent.GetWidth, UIParent)
  local okh, sh = pcall(UIParent.GetHeight, UIParent)
  if not (okw and type(sw) == "number" and sw > 0) then sw = IG_DEF_W end
  if not (okh and type(sh) == "number" and sh > 0) then sh = IG_DEF_H end
  local okl, l = pcall(f.GetLeft, f)
  local okr, r = pcall(f.GetRight, f)
  local okt, tp = pcall(f.GetTop, f)
  local okb, bo = pcall(f.GetBottom, f)
  if okl and okr and okt and okb and l and r and tp and bo and spec.anchor then
    local k = 1
    if type(UIParent.GetEffectiveScale) == "function" then
      local oks, s = pcall(UIParent.GetEffectiveScale, UIParent)
      if oks and type(s) == "number" and s > 0 then k = s end
    end
    local dx, dy = 0, 0
    if r > sw then dx = sw - r end
    if l + dx < 0 then dx = -l end
    if tp > sh then dy = sh - tp end
    if bo + dy < 0 then dy = -bo end
    if dx ~= 0 or dy ~= 0 then
      pcall(f.ClearAllPoints, f)
      pcall(f.SetPoint, f, "BOTTOMRIGHT", spec.anchor, "TOPRIGHT", 6 + dx / k, 6 + dy / k)
    end
  end
  return true
end

-- ★测试读值口（全部读真实控件/真实分页状态；测试不复刻映射逻辑）
function EVAL_TEST_IG_STATE()
  if not (IG.built and IG.spec) then return nil end
  local fh = nil
  if IG.frame and type(IG.frame.GetHeight) == "function" then
    local okf, vf = pcall(IG.frame.GetHeight, IG.frame)
    if okf then fh = vf end
  end
  local filled, firstItem, firstSel = 0, nil, false
  for i = 1, IG_PER do
    local c = IG.cells[i]
    if c.item then
      filled = filled + 1
      if not firstItem then firstItem, firstSel = c.item, c.sel and true or false end
    end
  end
  local cntTxt = nil
  if IG.cnt and type(IG.cnt.GetText) == "function" then cntTxt = IG.cnt:GetText() end
  -- ★别写「cond and (x and true or false) or nil」：隐藏时会得到 **nil** 而不是 false
  --   （Lua and/or 陷阱 —— 本项目已在两处踩过，读值口一定要显式 if）
  local cathShown = nil
  if IG.catcher and type(IG.catcher.IsShown) == "function" then
    cathShown = IG.catcher:IsShown() and true or false
  end
  -- ★底栏真实几何：任何一格都靠真控件的 GetLeft/GetWidth 量出来（宽度下限就是靠这些断言守住的）
  local function igFoot(t)
    if not (t and t.btn) then return nil, nil end
    local okl, l = pcall(t.btn.GetLeft, t.btn)
    local okw, w = pcall(t.btn.GetWidth, t.btn)
    if okl and okw and type(l) == "number" and type(w) == "number" then return l, l + w end
    return nil, nil
  end
  local dnL, dnR = igFoot(IG.dn)
  local bL, bR = igFoot(IG.btnB)
  local aL, aR = igFoot(IG.btnA)
  local cL, cR = igFoot(IG.closeBtn)
  local fw = nil
  if IG.frame and type(IG.frame.GetWidth) == "function" then
    local okw2, w2 = pcall(IG.frame.GetWidth, IG.frame)
    if okw2 then fw = w2 end
  end
  return { key = IG.spec.key, mode = IG.spec.mode, shown = EVAL_IG_IS_SHOWN(),
           cols = IG_COLS, rows = IG_ROWS, per = IG_PER, rowsUsed = IG.rowsUsed,
           frameH = fh, hMax = IG_HMAX, page = IG.page, pages = IG.pages,
           total = IG.total or 0, filled = filled, selCount = IG.selCount or 0,
           first = firstItem and firstItem.name or nil, firstTex = firstItem and firstItem.tex or nil,
           firstCount = firstItem and firstItem.count or nil, firstSel = firstSel,
           cellBox = IG.cells[1] and IG.cells[1].btn:GetWidth() or nil,
           cellBoxH = IG.cells[1] and IG.cells[1].btn:GetHeight() or nil,
           iconW = IG.cells[1] and IG.cells[1].tex:GetWidth() or nil,
           iconH = IG.cells[1] and IG.cells[1].tex:GetHeight() or nil,
           hasEdge = false, -- 格子不自绘边框（用户要求：图标自带边框）
           countText = cntTxt,
           catcherShown = cathShown,
           frameLevel = IG.frame and IG.frame.GetFrameLevel and IG.frame:GetFrameLevel() or nil,
           catcherLevel = IG.catcher and IG.catcher.GetFrameLevel and IG.catcher:GetFrameLevel() or nil,
           footDnLeft = dnL, footDnRight = dnR,
           footBLeft = bL, footBRight = bR, footALeft = aL, footARight = aR,
           footCloseLeft = cL, footCloseRight = cR, footW = fw,
           upShown = IG.up and IG.up.btn:IsShown() and true or false,
           dnShown = IG.dn and IG.dn.btn:IsShown() and true or false }
end

-- ★「点框体外部自动关闭」的测试入口：走**真实 OnClick**（不是直调隐藏函数）
function EVAL_TEST_IG_OUTSIDE()
  if not IG.catcher then return false end
  local ok, fn = pcall(IG.catcher.GetScript, IG.catcher, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, IG.catcher, "LeftButton")
  return okc, err
end

function EVAL_TEST_IG_TEX(i)
  if not IG.cells[i] then return nil end
  return IG.cells[i].tex
end

function EVAL_TEST_IG_MARK(i)
  if not IG.cells[i] then return nil end
  return IG.cells[i].mark, (IG.cells[i].mark:IsShown() and true or false)
end

function EVAL_TEST_IG_CLICK(i)
  local c = IG.cells[i]
  if not c then return false end
  local ok, fn = pcall(c.btn.GetScript, c.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, c.btn, "LeftButton")
  return okc, err
end

function EVAL_TEST_IG_HOVER(i)
  local c = IG.cells[i]
  if not c then return false end
  local ok, fn = pcall(c.btn.GetScript, c.btn, "OnEnter")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn)
  return okc, err
end

function EVAL_TEST_IG_PAGE(which)
  local t = (which == "up") and IG.up or IG.dn
  if not (t and t.btn) then return false end
  local ok, fn = pcall(t.btn.GetScript, t.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn)
  return okc, err
end

function EVAL_TEST_IG_WHEEL(a, b)
  if not IG.frame then return false end
  local ok, fn = pcall(IG.frame.GetScript, IG.frame, "OnMouseWheel")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, a, b)
  return okc, err
end

-- spec 按钮（底栏右）驱动（测试走真实 OnClick）
function EVAL_TEST_IG_FOOT(which)
  local t = (which == "close") and IG.closeBtn or ((which == "a") and IG.btnA or IG.btnB)
  if not (t and t.btn) then return false end
  local ok, fn = pcall(t.btn.GetScript, t.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn)
  return okc, err
end


