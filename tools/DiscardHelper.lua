-- ============================================================================
-- 自动丢弃助手（悬浮图标 + 丢弃列表面板）—— tools/DiscardHelper.lua
-- ============================================================================
-- 用户 2026-10-10 定：「**自动丢弃助手: 需要类似消耗品助手 在界面上有个图标右键快速选择,
--   然后列表罗列,点击列表单元切换启用禁用状态**」+「**参考消耗品助手那边的方式.选择列表单元
--   右键是取消这个项目.左键是切换开启关闭项目**」。
-- ★★分工（照项目铁律「工具类功能一律独立文件，Toolbox 只做开启/配置入口」）：
--   · 本文件 = **悬浮图标 + 列表面板**（入口与界面，全部自包含）；
--   · **数据与执行引擎留在宿主 Toolbox.lua**（白名单扫描 + 限频队列丢弃要用宿主的
--     `tbQ`/`tbBagScan`/`tbItemName` —— 那是文件级 local，搬出来得为它们造一堆桥，风险远大于收益）
--     ⇒ 数据只有那一份实现，本文件一律走桥，**绝不调宿主 local**。
-- ★★只走全局桥，且**一律现读 + pcall + fail-open**（拿不到就返回 false / 如实说一句，绝不报错）：
--   `EVAL_TB_CHAR_STORE`（角色级配置：图标位置/大小）· `EVAL_TB_CFG`（账号级路由代理：`discardTex` 贴图缓存）·
--   `EVAL_TB_REFRESH` ·
--   `EVAL_TB_DISCARD_{LIST,HAS,ADD,REMOVE,CLEAR,ON,SET}` ·
--   `EVAL_SAY` · `EVAL_L` · `EVAL_WHEEL_DIR` · `EVAL_IG_TOPLEFT` ·
--   `EVAL_IG_{OPEN,SCAN_BAGS,HIDE,REFRESH,IS_SHOWN}` · `EVAL_TEST_IG_STATE` · `EVAL_TN_OPEN`。
-- ★★载入期零副作用：顶层只声明常量/表/函数 —— **不建帧、不挂事件、不读存档**（开关打开才建）。
-- ★★关断四件事（宿主那一行的勾选框取消时走 `EVAL_DISCARD_SYNC`）：
--   ① 图标 + **图标右侧的物品横排** + 列表面板一起收起（1.12 **没有销毁帧/纹理的 API** ⇒ 帧只 `Hide`
--     留着复用，代价如实写在这里）；② 会话态复位（行偏移 / 我们那把图标网格）；
--   ③ **数据一个字都不动**（那是用户的配置，只有横排/面板的右键与 [清空] 才删）；④ 控件都是常驻池件，收起即可。
-- ★★★交互口径（★★★用户 2026-10-10 **二轮**定稿：「**图标的右键能否直接进入从背包选择的弹窗选取添加物品,
--   物品选取完成之后的物品列表,参考消耗助手将物品右侧展现.左右键点击操作我在之前的需求内已经说明了.**」）：
--   · **右键主图标 = 直接开「从背包选择」弹窗**（`dhPick` —— 不再是「开列表窗」，用户点名的就是这个）；
--     **左键主图标 = 只用于拖动**（点一下不做任何事 —— 它与 `RegisterForDrag("LeftButton")` 争用同一个按键，
--     CH 1.74.30 就是这么定的）；
--   · **已选物品以横排小图标贴在主图标右侧**（照 `tools/ConsumableHelper.lua` 的横排口径；放不下整条翻左侧）；
--     每枚 **左键 = 切换这一条的 开/停**、**右键 = 从列表移除这一条**（横排与列表面板**同一套语义、同一个写口**）；
--   · **Ctrl+滚轮 = 调图标大小**（16~64，方向单一来源 `EVAL_WHEEL_DIR`；裸滚 / Shift+滚不接管）。
--   ★**列表面板仍然保留**（带名字/状态/手动输入/清空），入口 = 工具箱那一行的 `[配置]`（自己行内的按钮）——
--     横排是「一眼看得见 + 快速开关」的主路径，面板是「看全名 + 手动补」的详细路径。
-- ★帧名 `EVAL_DISCARD_PANEL` / `EVAL_DISCARD_CATCH` 与函数名（`EVAL_DISCARD_UI_OPEN` 等）**不同名**
--   —— 具名帧顶掉同名全局函数是本项目在案的老坑（组 54）。

local DH = { built = false, off = 0 }

-- ── 常量（单一来源）────────────────────────────────────────────────────────
local DH_SIZE = 26                        -- 图标默认边长（与消耗品 / 喂食 / 下马助手同一尺寸口径）
local DH_MIN, DH_MAX, DH_STEP = 16, 64, 4 -- Ctrl+滚轮的可调范围与步进（一律夹取）
local DH_TEXT = "丢"                      -- 图标上的字（本助手不代表任何物品，就用一个字）
local DH_ROWS = 8                         -- 面板行池
local DH_ROW_H = 18
local DH_W, DH_H = 380, 250               -- 面板尺寸
local DH_GAP = 6                          -- 面板与图标之间的缝
local DH_DEF_W, DH_DEF_H = 1024, 768      -- 屏幕尺寸兜底
local DH_ON_X, DH_NAME_X = 12, 62         -- 面板行内两列的左缘（列头与单元格同一来源）
-- 图标右侧的物品横排（照消耗品助手；见文件头「交互口径」）
local DH_STRIP_MAX = 12                   -- 最多排几枚（超出在悬停里如实报「还有 N 项」，绝不静默丢）
local DH_STRIP_GAP = 2                    -- 与主图标 / 彼此之间的缝（固定，不随尺寸变）
local DH_GRAY = 0.40                      -- 「停用」的灰度（★只表示用户停用 —— 不在背包里是常态，绝不画灰）
-- ★前向声明（R2 老雷：横排的点击闭包写在下面，直接 `local function` 会让闭包里的 `dhSyncAll` 绑全局 nil）
local dhSyncAll

-- ── 小工具（全部 pcall，模块侧不允许冒泡）──────────────────────────────────
local function L(k, ...)
  if type(EVAL_L) == "function" then
    local ok, s = pcall(EVAL_L, k, ...)
    if ok and type(s) == "string" then return s end
  end
  return k
end
local function dhSay(msg)
  if type(EVAL_SAY) ~= "function" then return end
  pcall(EVAL_SAY, tostring(msg))
end
local function dhSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b)
  pcall(tex.SetAlpha, tex, a or 1)
end
local function dhText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  pcall(fs.SetFont, fs, "Fonts\\FZLBJW.TTF", size, "")
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end
-- 小按钮（交 b, text, bg；`w`/`h` 必给 —— 面板里的按钮高一律 15，与工具箱同口径）
local function dhBtn(parent, x, y, w, h, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  dhSolid(bg, 0.10, 0.09, 0.07, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local t = dhText(b, 10, 0.95, 0.82, 0.35)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(label or "")
  return b, t, bg
end
-- 图标显隐（读回用 pcall；判不出 ⇒ 当成「没显示」= 面板退回屏幕中央，绝不锚到看不见的帧上）
local function dhShown(f)
  if not f then return false end
  local ok, v = pcall(f.IsShown, f)
  return (ok and v) and true or false
end

-- ── 配置（角色级，与消耗品助手同一条路：EVAL_TB_CHAR_STORE）──────────────
local function dhCfg()
  if type(EVAL_TB_CHAR_STORE) ~= "function" then return nil end
  local ok, t = pcall(EVAL_TB_CHAR_STORE)
  if ok and type(t) == "table" then return t end
  return nil
end
-- ★唯一尺子：图标大小（缺键 / 坏值 ⇒ 回落 26 ⇒ 老存档零迁移；越界当场夹取）
local function dhSize()
  local tb = dhCfg()
  local v = tb and tonumber(tb.discardSize) or nil
  if not v then return DH_SIZE end
  if v < DH_MIN then return DH_MIN end
  if v > DH_MAX then return DH_MAX end
  return v
end

-- ── 宿主桥（数据/开关都在宿主，模块绝不存第二份）───────────────────────────
local function dhList()
  if type(EVAL_TB_DISCARD_LIST) ~= "function" then return {} end
  local ok, l = pcall(EVAL_TB_DISCARD_LIST)
  if ok and type(l) == "table" then return l end
  return {}
end
local function dhHas(nm)
  if type(EVAL_TB_DISCARD_HAS) ~= "function" then return false end
  local ok, v = pcall(EVAL_TB_DISCARD_HAS, nm)
  return (ok and v == true) and true or false
end
local function dhAdd(nm)
  if type(EVAL_TB_DISCARD_ADD) ~= "function" then return false end
  local ok, v = pcall(EVAL_TB_DISCARD_ADD, nm)
  return (ok and v == true) and true or false
end
local function dhRemove(nm)
  if type(EVAL_TB_DISCARD_REMOVE) ~= "function" then return false end
  local ok, v = pcall(EVAL_TB_DISCARD_REMOVE, nm)
  return (ok and v == true) and true or false
end
local function dhClear()
  if type(EVAL_TB_DISCARD_CLEAR) ~= "function" then return false end
  local ok, v = pcall(EVAL_TB_DISCARD_CLEAR)
  return (ok and v ~= false) and true or false
end
local function dhOn()
  if type(EVAL_TB_DISCARD_ON) ~= "function" then return false end
  local ok, v = pcall(EVAL_TB_DISCARD_ON)
  return (ok and v == true) and true or false
end
local function dhSetOn(v)
  if type(EVAL_TB_DISCARD_SET) ~= "function" then return false end
  local ok, r = pcall(EVAL_TB_DISCARD_SET, v and true or false)
  return (ok and r ~= false) and true or false
end
local function dhRowRefresh()
  if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
end
-- 我们那把图标网格（只认 spec.key == "discard"；共用件还有喂药/消耗品等消费方，绝不无条件收）
local function dhGridClose()
  if type(EVAL_IG_IS_SHOWN) ~= "function" or not EVAL_IG_IS_SHOWN() then return end
  if type(EVAL_TEST_IG_STATE) ~= "function" then return end
  local ok, st = pcall(EVAL_TEST_IG_STATE)
  if ok and type(st) == "table" and st.key == "discard" then
    if type(EVAL_IG_HIDE) == "function" then pcall(EVAL_IG_HIDE) end
  end
end
local function dhGridSync()
  if type(EVAL_IG_IS_SHOWN) == "function" and EVAL_IG_IS_SHOWN()
     and type(EVAL_IG_REFRESH) == "function" then
    pcall(EVAL_IG_REFRESH)
  end
end

-- ── 鼠标键 / 屏幕 / 落位 / 存位 ────────────────────────────────────────────
local function dhMouseBtn(a, b)
  return (type(a) == "string" and a) or (type(b) == "string" and b)
         or (type(arg1) == "string" and arg1) or "LeftButton"
end
local function dhScreen()
  local okw, sw = pcall(UIParent.GetWidth, UIParent)
  local okh, sh = pcall(UIParent.GetHeight, UIParent)
  if not (okw and type(sw) == "number" and sw > 0) then sw = DH_DEF_W end
  if not (okh and type(sh) == "number" and sh > 0) then sh = DH_DEF_H end
  return sw, sh
end
-- 图标落位（唯一口）：位置口径 = 中心偏移（discardX/discardY），换算走共用件 EVAL_IG_TOPLEFT
local function dhApplyPos(frame, size, cx, cy)
  local sw, sh = dhScreen()
  local x, y
  if type(EVAL_IG_TOPLEFT) == "function" then
    local ok, px, py = pcall(EVAL_IG_TOPLEFT, sw, sh, size, cx, cy)
    if ok and type(px) == "number" and type(py) == "number" then x, y = px, py end
  end
  if not x then x, y = sw / 2 - size / 2, -(sh / 2 - size / 2) end
  pcall(frame.ClearAllPoints, frame)
  pcall(frame.SetPoint, frame, "TOPLEFT", UIParent, "TOPLEFT", x, y)
end
local function dhSavePos()
  local b = DH.btn
  if not b then return end
  local okl, l = pcall(b.GetLeft, b)
  local okt, t = pcall(b.GetTop, b)
  if not (okl and okt and type(l) == "number" and type(t) == "number") then return end
  local s = 1
  local oks, es = pcall(b.GetEffectiveScale, b)
  if oks and type(es) == "number" and es > 0 then s = es end
  local tb = dhCfg()
  if not tb then return end
  local sw, sh = dhScreen()
  tb.discardX = (l + dhSize() / 2 - sw / 2) / s
  tb.discardY = (t - dhSize() / 2 - sh / 2) / s
end

-- ══════════════════════════ 图标右侧的物品横排 ══════════════════════════
-- ★★★作用（用户二轮定稿）：右键主图标 = 直接进「从背包选择」弹窗 ⇒ **选完的东西一眼就在图标旁排出来**，
--   不必先开窗才知道自己选了什么。每枚：左键 = 切换这条的「开/停」、右键 = 从列表移除这一条。
-- ★★「不在背包里」是**常态**（东西已经被丢掉了！）⇒ 绝不像消耗品助手那样把它画灰 ——
--   灰**只**表示「用户把这条停用了」；贴图靠 `discardTex` 缓存记住（落存档，重载后照旧画得出来）。
local function dhStep() return dhSize() + DH_STRIP_GAP end

-- 贴图缓存：真值在**账号级**配置 `tb.discardTex[名字] = 贴图路径`（与丢弃列表同一个存储位置，随列表一起走）
local function dhCacheTex(nm, tex)
  if type(nm) ~= "string" or nm == "" or type(tex) ~= "string" or tex == "" then return end
  if type(EVAL_TB_CFG) ~= "function" then return end
  local ok, tb = pcall(EVAL_TB_CFG)
  if not (ok and type(tb) == "table") then return end
  if type(tb.discardTex) ~= "table" then tb.discardTex = {} end
  if tb.discardTex[nm] ~= tex then tb.discardTex[nm] = tex end   -- 同值不重复写
end
local function dhKnownTex(nm)
  if type(nm) ~= "string" or nm == "" or type(EVAL_TB_CFG) ~= "function" then return nil end
  local ok, tb = pcall(EVAL_TB_CFG)
  if not (ok and type(tb) == "table" and type(tb.discardTex) == "table") then return nil end
  local t = tb.discardTex[nm]
  return (type(t) == "string" and t ~= "") and t or nil
end

-- 建横排（懒建：与主图标同时，只在开关打开时；1.12 没有销毁 API ⇒ 建一次之后只 Show/Hide）
local function dhBuildStrip()
  if DH.strip then return end
  local S = dhSize()
  local cells = {}
  DH.strip, DH.stripRec = cells, {}
  for i = 1, DH_STRIP_MAX do
    local s = CreateFrame("Button", nil, UIParent)
    s:SetWidth(S) s:SetHeight(S)
    s:SetPoint("TOPLEFT", DH.btn, "TOPRIGHT", DH_STRIP_GAP + (i - 1) * dhStep(), 0)
    pcall(s.EnableMouse, s, true)
    pcall(s.RegisterForClicks, s, "LeftButtonUp", "RightButtonUp")
    local bg = s:CreateTexture(nil, "BACKGROUND")
    dhSolid(bg, 0.07, 0.05, 0.04, 0.85)
    bg:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    local edges = {}
    for k = 1, 4 do
      local e = s:CreateTexture(nil, "BORDER")
      dhSolid(e, 0.90, 0.42, 0.30, 0.95)   -- 与主图标同族的红调（停用时整圈压灰，见 refresh）
      if k == 1 then
        e:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0) e:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0) e:SetHeight(1)
      end
      if k == 2 then
        e:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0) e:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0) e:SetHeight(1)
      end
      if k == 3 then
        e:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0) e:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0) e:SetWidth(1)
      end
      if k == 4 then
        e:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0) e:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0) e:SetWidth(1)
      end
      edges[k] = e
    end
    local tex = s:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
    pcall(tex.Hide, tex)
    -- 「停」字 = 灰贴图之外的第二重信号（色弱 / 16px 小尺寸下也看得见）
    -- ★1.75.118c 用户真机截图：「停的字需要居中图标水平垂直居中」⇒ **居中锚 + 居中排列**
    --   （旧写法是「锚右下角 + 右对齐」，字挤在右下角）；★只发一次锚点（dhText 不设锚 ⇒ 这里这一个不会累积）。
    local mark = dhText(s, 8, 1.0, 0.62, 0.55)
    mark:SetPoint("CENTER", s, "CENTER", 0, 0)
    pcall(mark.SetWidth, mark, S - 2)
    pcall(mark.SetJustifyH, mark, "CENTER")
    pcall(mark.SetNonSpaceWrap, mark, false)
    pcall(mark.Hide, mark)
    cells[i] = { btn = s, tex = tex, mark = mark, edges = edges }
    s:SetScript("OnClick", function(a, b2)
      local rec = DH.stripRec[i]              -- ★本拍绑的记录（不受刷新位移影响）
      if type(rec) ~= "table" then return end
      if dhMouseBtn(a, b2) == "RightButton" then
        if dhRemove(rec.name) then            -- 右键 = 从列表移除这一条
          dhSay(string.format(L("TB_DISC_REMOVED"), tostring(rec.name)))
        end
      else
        if rec.on == false then rec.on = true else rec.on = false end   -- 左键 = 切换 开/停
      end
      dhSyncAll()                             -- 数据只有一个写口 ⇒ 四处显示一起刷
    end)
    s:SetScript("OnEnter", function()
      local rec = DH.stripRec[i]
      if type(rec) ~= "table" or type(GameTooltip) ~= "table" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, s, "ANCHOR_RIGHT")
      pcall(GameTooltip.ClearLines, GameTooltip)
      pcall(GameTooltip.AddLine, GameTooltip, tostring(rec.name or "?"), 0.95, 0.85, 0.55)
      local on = (rec.on ~= false)
      pcall(GameTooltip.AddLine, GameTooltip,
        L("TB_DISC_STATE") .. "：" .. (on and L("TB_DISC_ON") or L("TB_DISC_OFF")),
        on and 0.62 or 0.95, on and 0.95 or 0.58, on and 0.55 or 0.52)
      pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISC_ROW_TIP"), 0.60, 0.85, 1)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    s:SetScript("OnLeave", function()
      if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    pcall(s.Hide, s)
  end
end

-- 横排刷新（唯一绘制口）：读列表 → 一次扫包建「名字 → 贴图」映射 → 逐枚贴图/配色/位置/显隐
local function dhStripRefresh()
  if not (DH.built and DH.btn and DH.strip) then return false end
  -- ★★总开关闸排在**任何上屏之前**：模块关着 ⇒ 一个横排格子都不显示。
  --   为什么必须在这儿再判一次：列表面板在「关着」时仍能从工具箱 [配置] 打开（见文件头），
  --   面板里点一下就走 `dhSyncAll` ⇒ 不判开关的话，关掉的用户会被面板点出满屏小图标来。
  local vis = dhOn()
  local list = dhList() or {}
  local n = table.getn(list)
  local shown = n
  if shown > DH_STRIP_MAX then shown = DH_STRIP_MAX end
  local map = {}
  if type(EVAL_IG_SCAN_BAGS) == "function" then
    local ok, arr = pcall(EVAL_IG_SCAN_BAGS, { 0, 1, 2, 3, 4 })   -- 与宿主 tbBagScan 同一批容器
    if ok and type(arr) == "table" then
      for k = 1, table.getn(arr) do
        local it = arr[k]
        if type(it) == "table" and type(it.name) == "string" and it.name ~= ""
           and type(it.tex) == "string" and it.tex ~= "" then
          if not map[it.name] then map[it.name] = it.tex end
          dhCacheTex(it.name, it.tex)        -- 记进存档 ⇒ 丢掉之后图标还在
        end
      end
    end
  end
  -- 方向：右侧排不下就整条翻到主图标左侧（夹取，绝不跑出屏幕）
  local sw = dhScreen()
  local needW = DH_STRIP_GAP + shown * dhStep()
  DH.side = "right"
  local okr, r = pcall(DH.btn.GetRight, DH.btn)
  if okr and type(r) == "number" and (r + needW) > sw then DH.side = "left" end
  for i = 1, DH_STRIP_MAX do
    local c = DH.strip[i]
    local rec = list[i]
    DH.stripRec[i] = (type(rec) == "table") and rec or nil
    if c then
      if type(rec) == "table" and i <= shown and vis then
        local nm = tostring(rec.name or "?")
        local tex = map[nm] or dhKnownTex(nm)
        if tex then
          pcall(c.tex.SetTexture, c.tex, tex)
          pcall(c.tex.Show, c.tex)
        else
          -- 没缓存、也不在包里 ⇒ 只画底 + 边框（**绝不画假图**），名字仍走悬停
          pcall(c.tex.Hide, c.tex)
        end
        local on = (rec.on ~= false)
        local v = on and 1 or DH_GRAY
        pcall(c.tex.SetVertexColor, c.tex, v, v, v)
        local er, eg, eb = 0.90, 0.42, 0.30
        if not on then er, eg, eb = 0.38, 0.38, 0.38 end
        for k = 1, 4 do
          if c.edges[k] then pcall(c.edges[k].SetVertexColor, c.edges[k], er, eg, eb) end
        end
        if on then
          pcall(c.mark.Hide, c.mark)
        else
          pcall(c.mark.SetText, c.mark, L("TB_DISC_OFF"))
          pcall(c.mark.Show, c.mark)
        end
        pcall(c.btn.ClearAllPoints, c.btn)
        if DH.side == "right" then
          pcall(c.btn.SetPoint, c.btn, "TOPLEFT", DH.btn, "TOPRIGHT", DH_STRIP_GAP + (i - 1) * dhStep(), 0)
        else
          pcall(c.btn.SetPoint, c.btn, "TOPRIGHT", DH.btn, "TOPLEFT", -DH_STRIP_GAP - (i - 1) * dhStep(), 0)
        end
        pcall(c.btn.Show, c.btn)
      else
        pcall(c.btn.Hide, c.btn)
      end
    end
  end
  DH.stripN = vis and shown or 0
  return true
end

-- 横排显隐（关开关 / 关模块走这一条；★子帧挂在 UIParent 上 ⇒ 不靠主图标父子传播，必须显式收）
local function dhStripSetShown(v)
  if not DH.strip then return end
  if v then dhStripRefresh() return end
  for i = 1, DH_STRIP_MAX do
    local c = DH.strip[i]
    if c then pcall(c.btn.Hide, c.btn) end
  end
  DH.stripN = 0                 -- ★读数也要跟着归零（否则状态口报的是上一拍的枚数 = 骗人的读数）
end

-- ══════════════════════════ 列表面板 ══════════════════════════
-- 行记录快照：`DH.rowRec[i]` = 本拍这一行绑的记录（左键切换 / 右键移除都拿它，不受刷新位移影响）
local function dhRefresh()
  if not DH.root then return end
  local list = dhList() or {}
  local n = table.getn(list)
  local maxOff = math.max(0, n - DH_ROWS)
  if DH.off > maxOff then DH.off = maxOff end
  if DH.empty then
    if n == 0 then DH.empty:Show() else DH.empty:Hide() end
  end
  for i = 1, DH_ROWS do
    local r = DH.rows[i]
    local e = list[DH.off + i]
    DH.rowRec[i] = (type(e) == "table") and e or nil
    if type(e) == "table" then
      if i % 2 == 0 then r.stripe:Hide() else r.stripe:Show() end
      r.btn:Show() r.state:Show() r.name:Show()
      local on = (e.on ~= false)   -- ★nil / true 都算启用（与宿主 tb.buy 的 on 同一把尺子）
      r.state:SetText(on and L("TB_DISC_ON") or L("TB_DISC_OFF"))
      if on then
        pcall(r.state.SetTextColor, r.state, 0.62, 0.95, 0.55)
        pcall(r.name.SetTextColor, r.name, 0.92, 0.88, 0.76)
      else
        pcall(r.state.SetTextColor, r.state, 0.95, 0.58, 0.52)
        pcall(r.name.SetTextColor, r.name, 0.58, 0.56, 0.50)
      end
      r.name:SetText(tostring(e.name or "?"))
    else
      r.stripe:Hide() r.btn:Hide() r.state:Hide() r.name:Hide()
    end
  end
  if DH.ind then
    local pages = math.max(1, math.ceil(n / DH_ROWS))
    local page
    if n == 0 then page = 1
    elseif DH.off >= math.max(0, n - DH_ROWS) then page = pages
    else page = math.floor(DH.off / DH_ROWS) + 1 end
    if page < 1 then page = 1 end
    if page > pages then page = pages end
    DH.ind:SetText(string.format("%d/%d  (%d)", page, pages, n))
  end
  local upBtn = DH.up and DH.up.btn
  local dnBtn = DH.dn and DH.dn.btn
  if upBtn and dnBtn then
    if n == 0 then upBtn:Hide() dnBtn:Hide()
    else
      if DH.off <= 0 then upBtn:Hide() else upBtn:Show() end
      if DH.off + DH_ROWS >= n then dnBtn:Hide() else dnBtn:Show() end
    end
  end
  -- 总开关按钮：文案/配色每拍按真值重画（按钮上写的永远等于真值）
  if DH.master and DH.master.text then
    local on = dhOn()
    pcall(DH.master.text.SetText, DH.master.text,
      L("TB_DISC_MASTER") .. "：" .. (on and L("TB_DISC_ON") or L("TB_DISC_OFF")))
    if on then pcall(DH.master.text.SetTextColor, DH.master.text, 0.62, 0.95, 0.55)
    else pcall(DH.master.text.SetTextColor, DH.master.text, 0.95, 0.58, 0.52) end
  end
end

-- ★★★一处刷新 = 四处显示（前向声明在文件顶部，定义处改赋值）
--   为什么必须收成一处：横排与面板**改的是同一份数据**（宿主 `tb.discard`）⇒ 任何一边改动都要让
--   另一边与工具箱那一行、以及还开着的图标网格一起跟上；散在各处手写四连 = 以后加一处显示必漏。
dhSyncAll = function()
  dhRefresh()        -- 列表面板（没建就早退）
  dhStripRefresh()   -- 图标右侧横排（没建就早退）
  dhRowRefresh()     -- 工具箱那一行（摘要/按钮文案要跟着变）
  dhGridSync()       -- 我们那把图标网格（还开着才刷 —— 只认 spec.key == "discard"）
end

-- 面板落位：图标在 ⇒ 贴它右侧（装不下翻左侧）；图标不在 ⇒ 屏幕正中；最后越界回归（量回屏矩形）
local function dhPlacePanel()
  local f = DH.root
  if not f then return end
  pcall(f.ClearAllPoints, f)
  if DH.btn and dhShown(DH.btn) then
    pcall(f.SetPoint, f, "BOTTOMLEFT", DH.btn, "BOTTOMRIGHT", DH_GAP, 0)
    local okl, l = pcall(f.GetLeft, f)
    local sw = dhScreen()
    if okl and type(l) == "number" and (l + DH_W) > sw then
      pcall(f.ClearAllPoints, f)
      pcall(f.SetPoint, f, "BOTTOMRIGHT", DH.btn, "BOTTOMLEFT", -DH_GAP, 0)
    end
  else
    pcall(f.SetPoint, f, "CENTER", UIParent, "CENTER", 0, 0)
  end
  local sw, sh = dhScreen()
  local okl, l = pcall(f.GetLeft, f)
  local okr, r = pcall(f.GetRight, f)
  local okt, t = pcall(f.GetTop, f)
  local okb, bo = pcall(f.GetBottom, f)
  if okl and okr and okt and okb and type(l) == "number" and type(r) == "number"
     and type(t) == "number" and type(bo) == "number" then
    local dx, dy = 0, 0
    if r > sw then dx = sw - r end
    if l + dx < 0 then dx = -l end
    if t > sh then dy = sh - t end
    if bo + dy < 0 then dy = -bo end
    if dx ~= 0 or dy ~= 0 then
      local k = 1
      local oks, es = pcall(UIParent.GetEffectiveScale, UIParent)
      if oks and type(es) == "number" and es > 0 then k = es end
      pcall(f.ClearAllPoints, f)
      pcall(f.SetPoint, f, "TOPLEFT", UIParent, "TOPLEFT", (l + dx) / k, (t + dy) / k)
    end
  end
end

-- 全屏捕手（点面板外面即关）；★按项目纪律「捕手必须读回自证」：SetAllPoints 后读回宽度，
--   <10 就用 UIParent 尺寸显式兜底（本客户端 Set* 静默失效族在案）。
local function dhCatchEnsure()
  if DH.catch then return DH.catch end
  local c = CreateFrame("Button", "EVAL_DISCARD_CATCH", UIParent)
  pcall(c.SetFrameStrata, c, "DIALOG")
  pcall(c.SetFrameLevel, c, 195)        -- 面板 200 之下 ⇒ 面板上的点击照旧落到面板
  pcall(c.EnableMouse, c, true)
  pcall(c.RegisterForClicks, c, "LeftButtonUp", "RightButtonUp")
  pcall(c.SetAllPoints, c, UIParent)
  local okw, w = pcall(c.GetWidth, c)
  if not (okw and type(w) == "number" and w >= 10) then
    local sw, sh = dhScreen()
    pcall(c.ClearAllPoints, c)
    pcall(c.SetPoint, c, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    pcall(c.SetWidth, c, sw)
    pcall(c.SetHeight, c, sh)
  end
  c:SetScript("OnClick", function() EVAL_DISCARD_UI_CLOSE() end)
  pcall(c.Hide, c)
  DH.catch = c
  return c
end

-- 「从背包选择」：共用图标网格（multi；勾 = 在列表里，点一下 = 加入 / 移出）
-- ★★★这是**主图标右键**与面板那颗 [从背包选择] 共用的同一个口（用户二轮点名「图标的右键直接进入从背包选择的弹窗」）
--   ⇒ 弹窗锚点由调用方给（图标 / 面板按钮），拿不到就给主图标，都没有才让共用件自己退屏幕中央。
local function dhPick(anchor)
  if type(EVAL_IG_OPEN) ~= "function" then
    dhSay(L("TB_DISC_NO_GRID"))            -- 拿不到共用件 ⇒ 如实说一句（绝不静默）
    return false
  end
  return EVAL_IG_OPEN({
    key = "discard",
    anchor = anchor or DH.pickBtn or DH.btn,
    title = L("TB_DISC_PICK_TITLE"),
    hint = L("TB_DISC_PICK_HINT"),
    mode = "multi",
    candidates = function()
      if type(EVAL_IG_SCAN_BAGS) ~= "function" then return {}, 0 end
      -- ★与宿主 tbBagScan 同一批容器（0~4）⇒「选得到的」与「扫得到的」是同一个范围
      return EVAL_IG_SCAN_BAGS({ 0, 1, 2, 3, 4 })
    end,
    isSelected = function(it) return dhHas(it and it.name) end,
    onToggle = function(it)
      local nm = it and it.name
      if type(nm) ~= "string" or nm == "" then return end
      if dhHas(nm) then dhRemove(nm) else dhAdd(nm) end
      dhSyncAll()
    end,
    btnAText = L("TB_DISC_PICK_CLEAR"),
    btnA = function()
      dhClear()
      dhSyncAll()
    end,
  })
end

local function dhBuild()
  if DH.root then return end
  local W, H = DH_W, DH_H
  local root = CreateFrame("Frame", "EVAL_DISCARD_PANEL", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 200)   -- 与自动购买设置窗同层：高于工具箱各弹窗、低于全局下拉 250
  pcall(root.EnableMouse, root, true)
  local bg = root:CreateTexture(nil, "BACKGROUND")
  dhSolid(bg, 0.05, 0.05, 0.07, 0.96)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  local bar = root:CreateTexture(nil, "BORDER")
  dhSolid(bar, 0.32, 0.12, 0.10, 1)      -- 红调（与消耗品助手的绿框区分开）
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  bar:SetHeight(22)
  local function edge(ax, ay, w2, h2)
    local t = root:CreateTexture(nil, "BORDER")
    dhSolid(t, 0.55, 0.28, 0.22, 0.9)
    t:SetPoint("TOPLEFT", root, "TOPLEFT", ax, ay)
    t:SetWidth(w2) t:SetHeight(h2)
  end
  edge(0, 0, W, 1) edge(0, -(H - 1), W, 1) edge(0, 0, 1, H) edge(W - 1, 0, 1, H)
  local title = dhText(root, 12, 0.95, 0.72, 0.45)
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -6)
  title:SetText(L("TB_DISC_UI_TITLE"))
  local xb = dhBtn(root, W - 26, -3, 18, 18, "X")
  xb:SetScript("OnClick", function() EVAL_DISCARD_UI_CLOSE() end)
  -- 列头（与行内单元格同一来源）
  local h1 = dhText(root, 10, 0.80, 0.72, 0.45)
  h1:SetPoint("TOPLEFT", root, "TOPLEFT", DH_ON_X, -30)
  h1:SetText(L("TB_DISC_COL_ON"))
  local h2 = dhText(root, 10, 0.80, 0.72, 0.45)
  h2:SetPoint("TOPLEFT", root, "TOPLEFT", DH_NAME_X, -30)
  h2:SetText(L("TB_DISC_COL_NAME"))
  local h3 = dhText(root, 9, 0.62, 0.60, 0.52)
  h3:SetPoint("TOPRIGHT", root, "TOPRIGHT", -30, -30)
  pcall(h3.SetJustifyH, h3, "RIGHT")
  h3:SetText(L("TB_DISC_ROW_TIP_SHORT"))
  -- 行池：整行一个大按钮（左键切换 / 右键移除）+ 行内两个 FontString
  local rows = {}
  DH.rows, DH.rowRec = rows, {}
  for i = 1, DH_ROWS do
    local y = -42 - (i - 1) * DH_ROW_H
    local r = {}
    r.stripe = root:CreateTexture(nil, "BACKGROUND")
    dhSolid(r.stripe, 0.14, 0.13, 0.11, 0.55)
    r.stripe:SetPoint("TOPLEFT", root, "TOPLEFT", 6, y + 2)
    r.stripe:SetWidth(W - 40)
    r.stripe:SetHeight(16)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(W - 40) b:SetHeight(14)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", 6, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    local st = dhText(root, 10, 0.62, 0.95, 0.55)
    st:SetPoint("TOPLEFT", root, "TOPLEFT", DH_ON_X + 2, y - 2)
    pcall(st.SetWidth, st, 44)
    local nm = dhText(root, 10, 0.92, 0.88, 0.76)
    nm:SetPoint("TOPLEFT", root, "TOPLEFT", DH_NAME_X + 2, y - 2)
    pcall(nm.SetWidth, nm, W - DH_NAME_X - 44)
    b:SetScript("OnClick", function(a, b2)
      local rec = DH.rowRec[i]                 -- ★本拍绑的记录（不受刷新位移影响）
      if type(rec) ~= "table" then return end
      if dhMouseBtn(a, b2) == "RightButton" then
        -- 右键 = 从列表移除这一条（用户 2026-10-10 定，照消耗品助手的「右键取消」）
        if dhRemove(rec.name) then
          dhSay(string.format(L("TB_DISC_REMOVED"), tostring(rec.name)))
        end
      else
        -- 左键 = 切换这一条的 开 / 停
        if rec.on == false then rec.on = true else rec.on = false end
      end
      dhSyncAll()          -- ★横排 / 工具箱行 / 图标网格一起跟上（数据只有一个写口）
    end)
    b:SetScript("OnEnter", function()
      local rec = DH.rowRec[i]
      if type(rec) ~= "table" or type(GameTooltip) ~= "table" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
      pcall(GameTooltip.ClearLines, GameTooltip)
      pcall(GameTooltip.AddLine, GameTooltip, tostring(rec.name or "?"), 0.95, 0.85, 0.55)
      local on = (rec.on ~= false)
      pcall(GameTooltip.AddLine, GameTooltip,
        L("TB_DISC_STATE") .. "：" .. (on and L("TB_DISC_ON") or L("TB_DISC_OFF")),
        on and 0.62 or 0.95, on and 0.95 or 0.58, on and 0.55 or 0.52)
      pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISC_ROW_TIP"), 0.60, 0.85, 1)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    b:SetScript("OnLeave", function()
      if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    r.btn, r.state, r.name = b, st, nm
    rows[i] = r
  end
  local empty = dhText(root, 10, 0.60, 0.58, 0.50)
  empty:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -46)
  pcall(empty.SetWidth, empty, W - 32)
  empty:SetText(L("TB_DISC_EMPTY"))
  DH.empty = empty
  -- 说明两行
  local hintY = -(42 + DH_ROWS * DH_ROW_H + 4)
  local hint = dhText(root, 9, 0.55, 0.60, 0.55)
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", 12, hintY)
  pcall(hint.SetWidth, hint, W - 24)
  hint:SetText(L("TB_DISC_HINT"))
  local tipLine = dhText(root, 9, 0.62, 0.60, 0.52)
  tipLine:SetPoint("TOPLEFT", root, "TOPLEFT", 12, hintY - 13)
  pcall(tipLine.SetWidth, tipLine, W - 24)
  tipLine:SetText(L("TB_DISC_TIP2"))
  -- 底栏：总开关 / 从背包选择 / 手动输入 / 清空
  local mb, mt = dhBtn(root, 12, -(H - 26), 104, 15, L("TB_DISC_MASTER"))
  DH.master = { btn = mb, text = mt }
  mb:SetScript("OnClick", function()
    local want = not dhOn()
    if dhSetOn(want) then
      dhSay(want and L("TB_DISC_ICON_ON") or L("TB_DISC_ICON_OFF"))
    end
    EVAL_DISCARD_SYNC()                      -- 总开关变化 ⇒ 图标显隐跟着走（唯一联动口）
    dhSyncAll()
  end)
  local pk = dhBtn(root, 122, -(H - 26), 100, 15, L("TB_DISC_PICK"))
  DH.pickBtn = pk
  pk:SetScript("OnClick", function() dhPick(pk) end)
  local mn = dhBtn(root, 228, -(H - 26), 72, 15, L("TB_DISC_MANUAL"))
  mn:SetScript("OnClick", function()
    if type(EVAL_TN_OPEN) ~= "function" then dhSay(L("TB_DISC_NO_TN")) return end
    pcall(EVAL_TN_OPEN, L("TB_DISCARD_ASK"), "", function(txt)
      txt = string.gsub(txt or "", "^%s*(.-)%s*$", "%1")
      if txt == "" then return end
      if not dhAdd(txt) then dhSay(string.format(L("TB_DISC_DUP"), tostring(txt))) end
      dhSyncAll()
    end)
  end)
  local cl = dhBtn(root, 306, -(H - 26), 62, 15, L("TB_DISC_CLEAR"))
  cl:SetScript("OnClick", function()
    dhClear()
    dhSyncAll()
  end)
  -- 右侧滚动槽（按页滚，与页码一致）
  local ub, ut = dhBtn(root, W - 20, -42, 16, 15, "^")
  local db, dt = dhBtn(root, W - 20, -(42 + (DH_ROWS - 1) * DH_ROW_H), 16, 15, "v")
  DH.up, DH.dn = { btn = ub, text = ut }, { btn = db, text = dt }
  ub:SetScript("OnClick", function() DH.off = math.max(0, DH.off - DH_ROWS) dhRefresh() end)
  db:SetScript("OnClick", function() DH.off = DH.off + DH_ROWS dhRefresh() end)
  -- 页码（标题行右侧）
  local ind = dhText(root, 9, 0.65, 0.62, 0.50)
  ind:SetPoint("TOPRIGHT", root, "TOPRIGHT", -30, -6)
  pcall(ind.SetWidth, ind, 120)
  pcall(ind.SetJustifyH, ind, "RIGHT")
  DH.ind = ind
  -- 滚轮（方向单一来源 EVAL_WHEEL_DIR；上滚 = 回到前面；dir=0 ⇒ 链式交还）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
  if okg and type(g) == "function" then prevWheel = g end
  root:SetScript("OnMouseWheel", function(a, b)
    local dir = 0
    if type(EVAL_WHEEL_DIR) == "function" then dir = tonumber(EVAL_WHEEL_DIR(a, b)) or 0 end
    if dir == 0 then
      if prevWheel then return prevWheel(a, b) end
      return
    end
    DH.off = math.max(0, DH.off - dir)
    dhRefresh()
  end)
  pcall(root.Hide, root)
  DH.root = root
  dhCatchEnsure()
end

-- ══════════════════════════ 悬浮图标 ══════════════════════════
local function dhApplySize()
  local S = dhSize()
  if DH.btn then
    pcall(DH.btn.SetWidth, DH.btn, S)
    pcall(DH.btn.SetHeight, DH.btn, S)
    local tb = dhCfg() or {}
    dhApplyPos(DH.btn, S, tb.discardX, tb.discardY)   -- 保持中心不变
    if DH.label then pcall(DH.label.SetWidth, DH.label, S) end
    if DH.strip then
      -- ★横排小图标与主图标**同尺寸**（与消耗品助手同一口径）；尺寸变了必须重排（步距跟着变）
      for i = 1, DH_STRIP_MAX do
        local c = DH.strip[i]
        if c then
          pcall(c.btn.SetWidth, c.btn, S)
          pcall(c.btn.SetHeight, c.btn, S)
          pcall(c.mark.SetWidth, c.mark, S - 2)
        end
      end
      dhStripRefresh()                                -- 含「右侧排不下 ⇒ 整条翻左侧」的重判
    end
    if dhShown(DH.root) then dhPlacePanel() end        -- 面板跟着图标走
  end
end

function EVAL_DISCARD_ENSURE()
  if DH.built and DH.btn then return DH.btn end
  local tb = dhCfg() or {}
  local b = CreateFrame("Button", nil, UIParent)
  local S0 = dhSize()
  b:SetWidth(S0) b:SetHeight(S0)
  dhApplyPos(b, S0, tb.discardX, tb.discardY)
  pcall(b.SetMovable, b, true)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  pcall(b.RegisterForDrag, b, "LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  dhSolid(bg, 0.07, 0.05, 0.04, 0.85)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  for i = 1, 4 do
    local e = b:CreateTexture(nil, "BORDER")
    dhSolid(e, 0.90, 0.42, 0.30, 0.95)   -- 红调：与消耗品（绿）/ 喂食（黄）区分开
    if i == 1 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 2 then
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 3 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) e:SetWidth(1)
    end
    if i == 4 then
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) e:SetWidth(1)
    end
  end
  local label = dhText(b, 12, 1.0, 0.78, 0.62)
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(label.SetWidth, label, S0)
  label:SetText(DH_TEXT)
  b:SetScript("OnClick", function(a, b2)
    if dhMouseBtn(a, b2) == "RightButton" then
      -- ★★★用户二轮定：「图标的右键**直接进入从背包选择的弹窗**选取添加物品」——右键不再开列表窗；
      --   列表面板改由工具箱那一行的 [配置] 打开（详细路径：看全名 / 手动输入 / 清空）。
      dhPick(b)
      return
    end
    -- 左键**不做任何事**：它留给拖动（RegisterForDrag("LeftButton")）—— 与消耗品助手同一口径
    return
  end)
  b:SetScript("OnDragStart", function()
    pcall(b.StartMoving, b)
    pcall(b.StopMovingOrSizing, b)
    pcall(b.StartMoving, b)           -- warm-up 两步（本客户端实测配方）
  end)
  b:SetScript("OnDragStop", function()
    pcall(b.StopMovingOrSizing, b)
    dhSavePos()
    dhStripRefresh()                      -- 位置变了 ⇒ 横排方向可能要从右翻到左
    if dhShown(DH.root) then dhPlacePanel() end
  end)
  -- Ctrl+滚轮 = 调图标大小（裸滚 / Shift+滚不接管；EnableMouseWheel 可能缺 ⇒ 全程 pcall）
  if pcall(b.EnableMouseWheel, b, true) then
    pcall(b.SetScript, b, "OnMouseWheel", function(a, b2)
      if not (type(IsControlKeyDown) == "function" and IsControlKeyDown()) then return end
      local d = 0
      if type(EVAL_WHEEL_DIR) == "function" then d = tonumber(EVAL_WHEEL_DIR(a, b2)) or 0 end
      if d == 0 then return end
      EVAL_DISCARD_SIZE_STEP(d)
    end)
  end
  b:SetScript("OnEnter", function()
    if type(GameTooltip) ~= "table" then return end
    local list = dhList() or {}
    local n, onN = table.getn(list), 0
    for i = 1, n do
      local e = list[i]
      if type(e) == "table" and e.on ~= false then onN = onN + 1 end
    end
    local on = dhOn()
    pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_LEFT")
    pcall(GameTooltip.ClearLines, GameTooltip)
    pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISCARD"),
      on and 0.62 or 0.95, on and 0.95 or 0.58, on and 0.55 or 0.52)
    pcall(GameTooltip.AddLine, GameTooltip,
      string.format(L("TB_DISC_TT_SUM"), n, onN), 0.85, 0.85, 0.85)
    if n == 0 then
      pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISC_EMPTY"), 1, 0.6, 0.4)
    else
      for i = 1, n do
        local e = list[i]
        local nm = (type(e) == "table") and tostring(e.name or "?") or tostring(e)
        local off = (type(e) == "table" and e.on == false)
        pcall(GameTooltip.AddLine, GameTooltip,
          string.format("%d. %s%s", i, nm, off and L("TB_DISC_OFF_MARK") or ""),
          off and 0.55 or 0.90, off and 0.55 or 0.90, off and 0.50 or 0.90)
      end
    end
    pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISC_ICON_HINT"), 0.6, 0.85, 1)
    if n > DH_STRIP_MAX then
      -- 排不下的如实报出来（绝不静默丢）；全名仍在本悬停的上面那份清单里
      pcall(GameTooltip.AddLine, GameTooltip,
        string.format(L("TB_DISC_STRIP_MORE"), n - DH_STRIP_MAX), 0.95, 0.72, 0.45)
    end
    pcall(GameTooltip.AddLine, GameTooltip, L("TB_DISC_STRIP_HINT"), 0.6, 0.85, 1)
    pcall(GameTooltip.AddLine, GameTooltip, string.format(L("TB_DISC_SIZE_HINT"), tostring(dhSize())), 0.55, 0.90, 0.55)
    pcall(GameTooltip.Show, GameTooltip)
  end)
  b:SetScript("OnLeave", function()
    if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  DH.btn, DH.label = b, label
  DH.built = true
  dhBuildStrip()                          -- 横排与主图标同时建（建出来是收着的，显隐由 SYNC/RESTORE 定）
  dhStripRefresh()                        -- 首拍就把已有列表摆对位置
  return b
end

-- ── 对外口（宿主 Toolbox 只用这几个；全部 fail-open）──────────────────────
-- 面板开关（工具箱那一行的 [配置] 与图标右键**共用**这一个口）
function EVAL_DISCARD_UI_OPEN()
  if dhShown(DH.root) then
    EVAL_DISCARD_UI_CLOSE()
    return true
  end
  dhBuild()
  if not DH.root then return false end
  DH.off = 0
  dhRefresh()
  dhPlacePanel()
  pcall(DH.root.Show, DH.root)
  if DH.catch then pcall(DH.catch.Show, DH.catch) end
  return true
end
-- 刷新（工具箱那一行的 [清空] 与外部调用走它；★面板 + 横排 + 行 + 网格一起刷）
function EVAL_DISCARD_UI_REFRESH() dhSyncAll() end
function EVAL_DISCARD_UI_CLOSE()
  dhGridClose()
  if DH.catch then pcall(DH.catch.Hide, DH.catch) end
  if DH.root then pcall(DH.root.Hide, DH.root) end
  if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
  return true
end
function EVAL_DISCARD_UI_SHOWN() return dhShown(DH.root) end
-- 开关联动（宿主勾选框勾上/取消时调；也是「关断四件事」的唯一入口）
function EVAL_DISCARD_SYNC()
  if not dhOn() then
    EVAL_DISCARD_UI_CLOSE()
    dhStripSetShown(false)                 -- ★横排挂在 UIParent 上 ⇒ 必须显式收（不靠主图标父子传播）
    if DH.btn then pcall(DH.btn.Hide, DH.btn) end
    return false
  end
  EVAL_DISCARD_ENSURE()
  if DH.btn then pcall(DH.btn.Show, DH.btn) end
  dhStripSetShown(true)                    -- 开回来立刻按列表排好，不用 /reload
  return true
end
-- 登录 / 进世界恢复（UIParent 尺寸此时才准 ⇒ 位置重算一遍；幂等；开关关着一个帧都不建）
function EVAL_DISCARD_RESTORE()
  if not dhOn() then dhStripSetShown(false) return false end
  local tb = dhCfg() or {}
  if not (DH.built and DH.btn) then EVAL_DISCARD_ENSURE()
  else dhApplyPos(DH.btn, dhSize(), tb.discardX, tb.discardY) end
  if DH.btn then pcall(DH.btn.Show, DH.btn) end
  dhStripSetShown(true)
  return true
end
-- Ctrl+滚轮写口（坏输入 / 到极限 ⇒ 出声且一个字节都不动）
function EVAL_DISCARD_SIZE_STEP(d)
  d = tonumber(d) or 0
  if d == 0 then return false end
  local cur = dhSize()
  local v = cur + (d > 0 and DH_STEP or -DH_STEP)
  if v < DH_MIN then v = DH_MIN end
  if v > DH_MAX then v = DH_MAX end
  if v == cur then
    dhSay(string.format(L("TB_DISC_SIZE_LIMIT"), tostring(v)))
    return false
  end
  local tb = dhCfg()
  if not tb then return false end
  tb.discardSize = v                   -- 唯一真值（角色级存档）
  dhApplySize()
  dhSay(string.format(L("TB_DISC_SIZE_NOW"), tostring(v)))   -- ★行为改变必须出声
  return true
end
-- 读值口（探针 / 离线判据用；★不许只给 harness 用 —— 这几个都挂在真机路径上）
function EVAL_DISCARD_SIZE_GET() return dhSize() end
function EVAL_DISCARD_BUILT() return (DH.built and DH.btn ~= nil) and true or false end
function EVAL_DISCARD_ICON_SHOWN() return dhShown(DH.btn) end
-- 读值口：图标右侧横排的当前状态（枚数 / 方向 / 逐枚的名字与开关）—— harness 与真机排查都用它
function EVAL_DISCARD_STRIP_STATE()
  local out = { n = DH.stripN or 0, side = DH.side or "right", max = DH_STRIP_MAX, items = {} }
  if not DH.strip then return out end
  for i = 1, DH_STRIP_MAX do
    local c = DH.strip[i]
    local rec = DH.stripRec and DH.stripRec[i]
    if c then
      -- ★★不许写 `(type(rec)=="table") and (rec.on ~= false) or nil` —— 「停用」时前半段是 **false**，
      --   `false or nil` 还是 nil ⇒ 读数把「停用」报成 nil（本项目在案的老坑，harness 当场抓到）
      local nm, onV = nil, nil
      if type(rec) == "table" then
        nm = rec.name
        onV = (rec.on ~= false)
      end
      out.items[i] = { shown = dhShown(c.btn), name = nm, on = onV }
    end
  end
  return out
end
