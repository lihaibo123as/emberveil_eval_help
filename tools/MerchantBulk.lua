-- ============================================================================
-- tools/MerchantBulk.lua —— 商人界面「Shift + 右键」批量购买（数量窗）
-- ============================================================================
-- 用户需求原文（2026-10-10）：
--   「调研分析API 物品购买批量购买可能性.或者一键一键购买达成批量购买也可行.
--     在商人界面shift+右键弹出提示批量购买数量.默认20 递步5」
--
-- ★★★调研结论（唯一真值 = 官方 API 文档 https://emberveil.org/wiki/lua/globals/Merchant
--   ，2026-10-10 现读；本地快照 tmp/merchant_page.html）—— 三条硬事实，别再重新调研：
--   ① `BuyMerchantItem(index)` —— 官方原文「The stack count sent to the server is **always 1**.」
--      ⇒ **一次调用只买 1 笔**（1 笔 = 该物品一次购买给的数量，见 ④）。
--   ② `BuyMerchantItem(index, quantity)` —— 原文「When a second argument is present, **the last argument
--      is used as the vendor index** and the first argument is ignored … **Not sent as a buy count**.」
--      ⇒ 第二个参数不是数量、而是**槽位号**（第一个参数被忽略）—— 传两参 = 买错格子。
--   ③ `GetMerchantItemMaxStack(index)` —— 原文「**Currently always 1** … The default merchant UI therefore
--      does not open the stack-split frame.」⇒ 本客户端的商人界面**没有**拆分框
--      （Shift+左键 / Shift+右键在今天**什么都不会多买**）⇒ 我们接管 Shift+右键**零功能损失**。
--   ④ `GetMerchantItemInfo(index)` 的第 4 个返回 = 「count granted per purchase」（每笔给几个）、
--      第 5 个 = 库存（-1 = 无限）、第 3 个 = **每笔**价格（铜）。
--   ⇒ **批量购买只能靠「循环单次调用」**（没有批量 API），并且必须限频。
--     本插件走宿主既有的写动作限频队列 `tbQ`（`TB_RATE = 0.3s/笔`）⇒ 20 个 ≈ 6 秒；
--     一次买光 = 被服务器当反滥用踢线的老路（本项目 1.68.2 的教训）。
--   ⇒ 跨插件分工（照 1.75.118 `tools/DiscardHelper.lua` 的尺子）：
--     **本模块只做「交互 + 数量窗」**（钩子 / 弹窗 / 参数夹取展示）；
--     **真正的写动作与全部安全闸门在宿主**（`Toolbox.lua` 的 `EVAL_TB_MBULK_ENQUEUE` + `tbQ` 队列）。
--
-- 判据 / 锚点：
--   · 只拦「**Shift + 右键**」；其余任何点击**原样转发**原生处理体（绝不改玩家原有手感）。
--   · 默认数量 `MB_DEF = 20` · 步进 `MB_STEP = 5`（**唯一来源**，对话框与命令都读它们）。
--   · 载入期**零副作用**（顶层只登记工具箱模块行 + 声明表）；建帧/挂事件/挂钩子全在 `EVAL_MB_INSTALL`
--     （VARIABLES_LOADED，因为开关真值要等存档）与工具箱勾选（`EVAL_MB_SET`）之后。
--   · 关掉 = **真摘**：注销事件 + 按身份还回按钮处理体 + 收起数量窗 + `SetScript("OnUpdate", nil)`。
--   · 1.12 **没有销毁帧/纹理的 API** ⇒ 数量窗建一次、之后只 Show/Hide（代价如实记在这里）。
--   · 钩子点（`MerchantItemNItemButton` / `MerchantItemN` 的 OnClick）**参考**：
--     客户端 FrameXML 参考实现（TurtleWoW `MerchantFrame.xml`，本仓库 tmp/mpq_out\Interface\FrameXML\）里
--     商人行是 `<Frame name="MerchantItem1..12" inherits="MerchantItemTemplate">`，其子件
--     `$parentItemButton`（= `MerchantItemNItemButton`）的 OnClick 调 `MerchantItemButton_OnClick(arg1)`；
--     本项目 `tools/EquipCompare.lua:415` 早已在生产里按 `^MerchantItemButton%d+$` / `^MerchantItem%d+$`
--     认这两族帧名（真机在跑）⇒ 名字可信；但「EmberVeil 的点击到底走不走那支处理体」**只能真机验**，
--     所以钩子是**防御式**的：认不出按钮 ⇒ `/eh go 商人` 的探针如实报「认不出」，绝不假装成功。
--     ★pak 明文扫描**不可用**：`tmp/mb_pak_scan.js` 连阳性对照（`ContainerFrameItemButton_OnEnter`）
--       都 0 命中（pak 里不是明文）⇒ 那条路已如实作废，别再拿它当证据。
-- ============================================================================

local MB = {
  wrap = {},   -- [i] = 我们装的包装处理体（身份比对用）
  old = {},    -- [i] = 装之前的原生处理体（可能 nil）
  hookN = 0,   -- 当前挂上的行数（探针读数）
  armed = false, -- 收到 MERCHANT_SHOW 且还没收到 MERCHANT_HIDE（见 mbMerchantOpen 的注释）
  ev = nil,    -- 事件帧（MERCHANT_SHOW / MERCHANT_HIDE）
  beat = nil,  -- 唯一节拍帧（只在商人窗开着时才挂）
  beatAt = 0,
  dlg = nil,   -- 数量窗（建一次、之后只 Show/Hide）
  catch = nil, -- 全屏捕手（点窗外面即关；★与窗同生共死，唯一隐藏出口 = mbHideDlg）
  idx = nil,   -- 本窗对应的**商人槽位号**（1 基、跨页绝对序号）
  name = nil,  -- 本窗物品名（下单时作执行前二次校验的基准）
  per = 1,     -- 每笔给几个（GetMerchantItemInfo 第 4 返回）
  price = 0,   -- 每笔价格（铜）
  qty = 20,    -- 当前数量（**个数**，不是笔数）
  cap = 999,   -- 上限（现算：库存 × 每笔个数 ∩ 买得起个数）
  last = "",   -- 最近一次动作（探针读数用）
}

local MB_DEF = 20      -- ★用户点名：默认 20
local MB_STEP = 5      -- ★用户点名：步进 5（点一下）
local MB_STEP_FAST = 20 -- ★1.76.1c 用户：「shift 点击增减按钮支持 20+递进」⇒ 按住 Shift 点 = 步进 20
local MB_ROW_MAX = 12  -- 商人行数上限（MerchantItem1..12）
local MB_BEAT = 0.5    -- 补挂处理体的节拍间隔（只在商人窗开着时跑）
-- ★1.76.1b 用户真机反馈（附截图）：「窗口小一点.黑色透明度85%.黑色边框.」
-- ★★★1.76.1f 用户真机截图（边框**完全错乱**：白角饰 + 竖条纹）+ 原话：「样式完全错乱了.还原到插件自身的
--   边框分割.参考工具箱->姓名板右键的弹窗边框样式是如何设定的.」
--   ⇒ **手工九宫格整条撤掉**（`UI-DialogBox-Border` 的角件/边件在本客户端被栅格化成白块与竖条）；
--     现在 = **与「工具箱 → 姓名右键菜单」逐字同源的那套插件自身配方**（唯一实现 `mbChrome`）：
--     ① 首选 `SetBackdrop`（客户端 tooltip 那圈圆角：bg `UI-Tooltip-Background` + edge `UI-Tooltip-Border`、
--        `tile/tileSize/edgeSize = MB_EDGE_ART`(16)、insets 4）→ **读回 `GetBackdrop` 自证**；
--     ② 读回说「不是那张边贴图」或压根挂不上 ⇒ **四边 1px 纯色描边**（`mbEdge`，插件自建、绝不失手）；
--     ③ ★★★**圆角路径下必须把「铺满整帧的自建方底」藏掉**（1.76.1h 用户真机截图提问：「边框外面还有一层边
--        是什么?」）—— 参考实现原话：「圆角时底由 backdrop 自己画（insets 4 → 落在圆角内侧）；再叠一层自己的
--        方形半透明底会发黑」；圆角边框贴图是**内缩**的，而方底铺满整帧 ⇒ 它的四条边与四个角从圆角边框
--        **外面**露出来，那就是用户看到的那一层。★**兜底路径（flat）必须留着它**（那条路没有 backdrop 底）。
--   ★尺寸/内边距回到「小窗」那一档（边框不再吃 32px 角饰 ⇒ 不必再给角饰让位）：214×156 / PAD 8。
--   ★★★1.76.1j 版式精简（用户：「批量购买内的文本可以删除只保留…总计金额计算值，然后宽度可进一步缩小，
--     数量值往上一行文字水平居中·对齐右侧，按钮标题颜色对齐插件文本色黄色」）：
--     ① 屏上只留「本单约 X」一行字（上限 / 操作提示全挪进悬停）② 删除「数量:」标签、数值搬到「每笔…」
--     那一行 ③ 窗宽 214 → 164、窗高 156 → 124（行数少了 2 行）④ 按钮标题走插件文本色（黄）。
--   ★★★1.76.1k 数量行改形（用户真机截图 + 原话：「**将每笔换成 x 数量(20) 文字紧凑点.对齐左边.**」；
--     版式由用户在两个候选里选定 A）：**「每笔」两个字从屏上撤掉**，那一行 = **`x20 · 1个 1铜`** ——
--     ① 行首一个「x」前缀（`MB_XPRE`），**数量值紧跟它右边**（左对齐）② 尾巴 = 每笔给几个 + 每笔价
--     （`MB_EACH`，锚在数值块右边 ⇒ 数量几位都自动跟随）③ **整行左对齐**（旧版贴右内边距右对齐）。
--     ★旧写法为什么必须改：整句「每笔 N 个 · 每笔 X」限宽到数值块左边只剩 ~102px ⇒ **真机上折行**
--     （用户截图里第二行孤零零一个「铜」字压在下一行上），且「每笔」占掉两处 ~40px 冗余宽度。
local MB_W, MB_H = 164, 124
local MB_PAD = 8                       -- 左右/标题内边距（唯一来源，几何全按它算）
local MB_XPRE = "x"                    -- 数量前缀（屏上写「x20」；★与 ▲/▼/± 这类纯符号同一处理：不走语言键）
local MB_X_W = 10                      -- 「x」前缀占的宽度（数量值紧跟它右边 = 左对齐）
local MB_VAL_W = 38                    -- 数值块宽（EditBox 与回声同一块：**同左缘、左对齐**）
local MB_VAL_GAP = 6                   -- 数值块与尾巴「· N个 单价」之间的缝（尾巴限宽用）
local MB_TXT_RGBA = { 1.00, 0.85, 0.35 } -- ★插件文本色（黄）= 标题与按钮标题**同一份值**（用户点名按钮标题对齐它）
local MB_EDGE = 1                      -- 兜底四边描边粗细（拿不到圆角 backdrop 时才用）
local MB_EDGE_ART = 16                 -- 客户端圆角边的 edgeSize：**必须整数**（参考插件实测：小数栅格化不可靠）
local MB_BD_RGBA = { 1, 1, 1, 1 }      -- 边框色 = **纯白不透明**（★1.76.1h 用户真机点名「边框需要设定白色」；
                                       --   ★参考实现（姓名右键菜单）是 `1,1,1,0.75`：**同一把配方、色值各自可调**，
                                       --   本窗按用户要求提亮到纯白 —— 改这一个常量即可，别处不许再写死色值）
-- 竖向排布（唯一来源；改窗高时只改这几行）
--   ★1.76.1j：原 QTY / CAP / HINT 三行已合并 —— 数值并入 EACH 那一行、上限与操作提示挪进悬停 ⇒ 只剩 4 行。
local MB_Y_TITLE = -8
local MB_Y_EACH  = -30                 -- 数量行（`x20 · 1个 1铜`：前缀 / 数值 / 尾巴都在这一行，左对齐）
local MB_Y_STEP  = -50                 -- −5 / +5
local MB_Y_TOTAL = -76                 -- 屏上唯一保留的文字：本单约 X
local MB_Y_BTN   = -(MB_H - MB_PAD - 20)  -- 底部按钮行（= -96；底距恒 = MB_PAD）
local MB_BG = { 0.00, 0.00, 0.00, 0.85 }  -- 底色：纯黑，透明度 85%

-- ===== 桥（一律「调用时现读」；拿不到就如实降级，绝不硬造全局）=====
local function L(k)
  local f = rawget(_G, "EVAL_L")
  if type(f) == "function" then
    local ok, v = pcall(f, k)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return tostring(k)
end

local function G(name) return rawget(_G, name) end

local function say(txt)
  local f = G("EVAL_SAY")
  if type(f) == "function" then pcall(f, tostring(txt)) end
end

-- ★用户主动敲命令 / 点界面 ⇒ 一律**可见**（「调试日志」总闸门默认关着也不许把回话吞掉；
--   口径 = §5.2 的「你问它答」那一族，与 WorldFog 的 wfEcho / LootCursor 的探针同一把尺子）
local function sayF(txt)
  local f = G("EVAL_SAY_FORCE")
  if type(f) == "function" then pcall(f, tostring(txt)) return end
  say(txt)
end

local function tbCfgGet()
  local f = G("EVAL_TB_CFG")
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f)
  if ok and type(v) == "table" then return v end
  return nil
end

-- 开关真值：`tbCfg().merchantBulk`（**nil = 开** —— 行为改变是用户点名的，默认就生效；
--   显式 false 永远是关）。★读不到配置 ⇒ 返回 false（fail-safe：绝不擅自接管玩家的点击）。
function EVAL_MB_ON()
  local tb = tbCfgGet()
  if type(tb) ~= "table" then return false end
  return tb.merchantBulk ~= false
end

-- ===== 商人窗 / 商人行的现场判读（全部 pcall，认不出就说认不出）=====
-- 商人窗「帧显隐」现读（★只认帧；`GetMerchantNumItems()` 关窗后可能残留，不许当兜底）
local function mbFrameOpen()
  local mf = G("MerchantFrame")
  if mf then
    if type(mf.IsShown) == "function" then
      local ok, v = pcall(mf.IsShown, mf)
      return (ok and v == true)
    end
    if type(mf.IsVisible) == "function" then
      local ok, v = pcall(mf.IsVisible, mf)
      return (ok and v == true)
    end
    return false
  end
  -- 没有 MerchantFrame 的客户端（自绘商人窗）才用 API 兜底
  local nf = G("GetMerchantNumItems")
  if type(nf) == "function" then
    local ok, n = pcall(nf)
    if ok and type(n) == "number" and n > 0 then return true end
  end
  return false
end

-- 「现在算不算商人窗开着」= **收到过 MERCHANT_SHOW 且还没收到 HIDE**（`MB.armed`）∨ 帧可见。
--   ★为什么必须有 armed：MERCHANT_SHOW 可能是客户端**先发事件、后 Show 帧**，若只按帧判，
--     我们会在那一拍判定「没开」⇒ 钩子与节拍**整场都不装**（用户眼里 = 功能没生效）；
--     反过来漏收 MERCHANT_HIDE 时由节拍用帧状态**自愈**（见 mbTick）。
local function mbMerchantOpen()
  return (MB.armed == true) or mbFrameOpen()
end

local function mbRowBtn(i)
  local b = G("MerchantItem" .. i .. "ItemButton")
  if b then return b end
  return G("MerchantItem" .. i)
end

-- 行号 → 商人槽位号。★行号 (1..12) **不是**列表序号（分页时第 1 行可能是第 11 项）：
--   首选按钮自己的 GetID()（客户端 FrameXML 是 `itemButton:SetID(index)` 写进去的）；
--   拿不到就按 MerchantFrame.page 折算（10 行一页）；两个都不行 ⇒ nil（如实失败，绝不猜）。
local function mbRowIndex(i)
  local b = mbRowBtn(i)
  if b and type(b.GetID) == "function" then
    local ok, v = pcall(b.GetID, b)
    local n = ok and tonumber(v) or nil
    if n and n >= 1 then return n end
  end
  local mf = G("MerchantFrame")
  if mf then
    local ok, page = pcall(function() return mf.page end)
    if ok and type(page) == "number" and page >= 1 then return (page - 1) * 10 + i end
  end
  return nil
end

local function mbItem(idx)
  local f = G("GetMerchantItemInfo")
  if type(f) ~= "function" or type(idx) ~= "number" then return nil end
  local ok, nm, tex, price, quant, avail = pcall(f, idx)
  if not ok or type(nm) ~= "string" or nm == "" then return nil end
  local per = (type(quant) == "number" and quant >= 1) and quant or 1
  return nm, tex, (type(price) == "number") and price or 0, per, avail
end

local function mbMoney(c)
  c = tonumber(c) or 0
  local gg = math.floor(c / 10000)
  local ss = math.floor((c % 10000) / 100)
  local cc = c % 100
  if gg > 0 then return string.format("%d金%d银%d铜", gg, ss, cc) end
  if ss > 0 then return string.format("%d银%d铜", ss, cc) end
  return string.format("%d铜", cc)
end

-- 上限 = min(库存 × 每笔个数, 买得起个数)；两者都判不出（无限库存 + 免费）⇒ 给个够大的数，
--   真正的闸门在宿主（它每一笔都重查库存/银两/背包，见 EVAL_TB_MBULK_ENQUEUE 与 tbBuyOne）。
local function mbCap(price, per, avail)
  local cap = nil
  if type(avail) == "number" and avail >= 0 then cap = math.floor(avail) * per end
  if type(price) == "number" and price > 0 then
    local money = 0
    local mf = G("GetMoney")
    if type(mf) == "function" then
      local ok, v = pcall(mf)
      if ok and type(v) == "number" then money = v end
    end
    local byMoney = math.floor(money / price) * per
    if cap == nil or byMoney < cap then cap = byMoney end
  end
  if cap == nil then cap = 999 end
  if cap < 1 then cap = 0 end
  return cap
end

-- ===== 钩子（装/摘都是**身份比对**：期间被别人套过就不许冲掉别人的处理体）=====
local mbOpenDlg -- ★前向声明（包装体里要用；定义在下面 —— 本项目 local 作用域老雷）

local function mbHookRow(i)
  local b = mbRowBtn(i)
  if not b or type(b.SetScript) ~= "function" then return 0 end
  local cur = nil
  if type(b.GetScript) == "function" then
    local ok, v = pcall(b.GetScript, b, "OnClick")
    cur = ok and v or nil
  end
  -- ★★幂等的**核查**而不是「记过就不再管」：客户端可能在每次 MERCHANT_SHOW 重建这些按钮
  --   （换了对象 ⇒ 我们那个包装早就不在那个新按钮上）⇒ 每拍都拿**当前**处理体比一次，
  --   不是我们的就（重新）装 —— 只按 MB.wrap[i] 记账会让功能在第二轮开窗时**静默失灵**。
  if type(MB.wrap[i]) == "function" and cur == MB.wrap[i] then return 0 end
  local old = (cur ~= MB.wrap[i]) and cur or MB.old[i]
  local row = i
  local wrap = function(a, bb)
    -- 按键名三候选取（本项目既有配方：形参 a/b + 全局 arg1）；默认左键
    local mbtn = (type(a) == "string" and a) or (type(bb) == "string" and bb)
      or (type(arg1) == "string" and arg1) or "LeftButton"
    local shift = false
    local sk = G("IsShiftKeyDown")
    if type(sk) == "function" then
      local ok, v = pcall(sk)
      shift = (ok and v == true)
    end
    if mbtn == "RightButton" and shift then
      local ok = false
      if type(mbOpenDlg) == "function" then ok = mbOpenDlg(row) end
      if ok then
        -- ★拦下这一下：本客户端原生 Shift+右键 只会买 1 个（没有拆分框，见文件头 ③）
        MB.last = "Shift+右键：第 " .. row .. " 行 → 数量窗"
        return
      end
    end
    if type(old) == "function" then pcall(old) end
  end
  if pcall(b.SetScript, b, "OnClick", wrap) then
    MB.wrap[i], MB.old[i] = wrap, old
    return 1
  end
  return 0
end

local function mbHook()
  if not EVAL_MB_ON() then return 0 end
  local n = 0
  for i = 1, MB_ROW_MAX do n = n + mbHookRow(i) end
  MB.hookN = 0
  for i = 1, MB_ROW_MAX do if MB.wrap[i] then MB.hookN = MB.hookN + 1 end end
  return n
end

local function mbUnhook()
  local n = 0
  for i = 1, MB_ROW_MAX do
    local b = mbRowBtn(i)
    if b and MB.wrap[i] then
      local cur = nil
      if type(b.GetScript) == "function" then
        local ok, v = pcall(b.GetScript, b, "OnClick")
        cur = ok and v or nil
      end
      if cur == MB.wrap[i] then
        pcall(b.SetScript, b, "OnClick", MB.old[i])
        n = n + 1
      end
      MB.wrap[i], MB.old[i] = nil, nil
    end
  end
  MB.hookN = 0
  return n
end

-- ===== 数量窗（建一次；1.12 没有销毁帧的 API ⇒ 之后只 Show/Hide）=====
local function mbFont(fs, size)
  local chain = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }
  for _, p in ipairs(chain) do
    local ok = pcall(fs.SetFont, fs, p, size)
    if ok then return true end
  end
  pcall(fs.SetFontObject, fs, "GameFontNormal")
  return false
end

local function mbBtn(parent, w, h, txt, x, y)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0.13, 0.13, 0.11, 0.95)
  local fs = b:CreateFontString(nil, "OVERLAY")
  mbFont(fs, 11)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetText(txt)
  -- ★按钮标题 = **插件文本色（黄）**（用户 1.76.1j：「按钮标题颜色对齐插件文本色黄色」）⇒ 与标题同一个常量，
  --   要调色只改 `MB_TXT_RGBA`（绝不在别处再写一个黄色字面量）。
  pcall(fs.SetTextColor, fs, MB_TXT_RGBA[1], MB_TXT_RGBA[2], MB_TXT_RGBA[3])
  return b, fs, bg
end

-- 悬停说明（唯一实现；照 tools/LootCursor.lua 的写法：`_G.GameTooltip` + 全程 pcall ——
--   拿不到那个口就静默不弹，绝不硬造帧、也绝不报错）
--   ★1.76.1j：`lines` 允许传**函数**（悬停那一刻现算）—— 上限/本单金额随数量与库存每拍变，
--     建窗时就把字符串拍死会显示过期值（本项目「值要现读」的同一把尺子）。
local function mbTip(btn, lines)
  if not btn or type(btn.SetScript) ~= "function" then return end
  btn:SetScript("OnEnter", function()
    local tip = _G.GameTooltip
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    local ls = lines
    if type(ls) == "function" then
      local ok, v = pcall(ls)
      ls = ok and v or nil
    end
    pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    for i = 1, table.getn(ls or {}) do
      local ln = ls[i]
      if type(ln) == "string" and ln ~= "" then pcall(tip.AddLine, tip, ln, 0.90, 0.90, 0.90) end
    end
    pcall(tip.Show, tip)
  end)
  btn:SetScript("OnLeave", function()
    local tip = _G.GameTooltip
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
end

local function mbDlgEdit()
  return MB.dlg and MB.dlg.edit or nil
end

-- 帧名/显隐一律 pcall 读（`b:GetName()` 与 `IsShown` 都可能抛；探针不许自己成为故障源）
local function mbName(b)
  if not b or type(b.GetName) ~= "function" then return "?" end
  local ok, v = pcall(b.GetName, b)
  if ok and type(v) == "string" then return v end
  return "?"
end

local function mbShown(f)
  if not f or type(f.IsShown) ~= "function" then return false end
  local ok, v = pcall(f.IsShown, f)
  return (ok and v == true)
end

-- 本单总价 = **唯一算式**（笔数 = ceil(数量 / 每笔个数)）—— 屏上那一行「本单约 X」与 [购买] 的悬停都读它，
--   绝不各算一份（本项目「一处真值」的同一把尺子）。
local function mbCost()
  local per = math.max(1, tonumber(MB.per) or 1)
  local left = math.ceil((tonumber(MB.qty) or 1) / per)      -- 本单笔数（每笔给 per 个）
  return (tonumber(MB.price) or 0) * left
end

local function mbDlgPaint()
  if not MB.dlg then return end
  local d = MB.dlg
  if d.title then pcall(d.title.SetText, d.title, tostring(MB.name or "?")) end
  local per = math.max(1, tonumber(MB.per) or 1)
  -- 尾巴 = 「· N个 单价」（`x20` 里的数量由 EditBox + 回声两处自己写，见下面 d.edit / d.echo）
  if d.tail then
    pcall(d.tail.SetText, d.tail, string.format(L("MB_EACH"), per, mbMoney(MB.price)))
  end
  -- ★屏上**唯一**保留的文字行（1.76.1j 用户：「文本可以删除只保留…总计金额计算值」）
  if d.total then
    pcall(d.total.SetText, d.total, string.format(L("MB_TOTAL"), mbMoney(mbCost())))
  end
  local eb = mbDlgEdit()
  if eb then pcall(eb.SetText, eb, tostring(MB.qty or MB_DEF)) end
  -- 回声行 = 「EditBox 万一不渲染」的兜底（本项目在案的老雷）⇒ 只写数字，不掺散文
  if d.echo then pcall(d.echo.SetText, d.echo, tostring(MB.qty or MB_DEF)) end
end

local mbHideDlg -- ★前向声明：捕手的 close 闭包要用它（定义在下面）⇒ 「定义处改赋值」，绝不裸 local function
-- ★1.76.1b 全屏捕手（用户：「点击任意其他位置支持关闭」）——照本项目 §三.4 配方：
--   UIParent 上的全屏 Button · strata 同 DIALOG · **level = 弹窗 − 5**（195 < 200 ⇒ 窗上的点击照旧落到窗里）；
--   ★**唯一隐藏出口 `mbHideDlg` 必须把它一起藏**（否则留一层吃点击的常驻空层）。
--   ★★本客户端 `Set*` 静默失效族在案 ⇒ 建成后**读回宽度自证**，< 10px 就按 UIParent 尺寸显式兜底
--     （同 1.75.106 名字右键菜单那条：只调 SetAllPoints 可能得到 0×0 的透明点 = 永远点不到）。
local function mbCatchBuild()
  if MB.catch then return MB.catch end
  local c = CreateFrame("Button", "EVAL_MB_DLG_CATCH", UIParent)
  pcall(c.SetFrameStrata, c, "DIALOG")
  pcall(c.SetFrameLevel, c, 195)
  pcall(c.EnableMouse, c, true)
  pcall(c.RegisterForClicks, c, "LeftButtonUp", "RightButtonUp")
  pcall(c.SetAllPoints, c)
  local okW, w = pcall(c.GetWidth, c)
  if not okW or type(w) ~= "number" or w < 10 then
    local uw, uh = 1024, 768
    if UIParent and type(UIParent.GetWidth) == "function" then
      local o1, v1 = pcall(UIParent.GetWidth, UIParent)
      if o1 and type(v1) == "number" and v1 > 100 then uw = v1 end
    end
    if UIParent and type(UIParent.GetHeight) == "function" then
      local o2, v2 = pcall(UIParent.GetHeight, UIParent)
      if o2 and type(v2) == "number" and v2 > 100 then uh = v2 end
    end
    pcall(c.ClearAllPoints, c)
    pcall(c.SetPoint, c, "TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    pcall(c.SetWidth, c, uw)
    pcall(c.SetHeight, c, uh)
  end
  local close = function() mbHideDlg() end
  c:SetScript("OnClick", close)
  -- ★第二条收尾路：`RegisterForClicks` 万一静默失效时，抬起那一下照样能关
  c:SetScript("OnMouseUp", close)
  pcall(c.Hide, c)
  MB.catch = c
  return c
end

mbHideDlg = function()
  if MB.catch then pcall(MB.catch.Hide, MB.catch) end -- ★捕手与窗同生共死（唯一隐藏出口）
  if MB.dlg then pcall(MB.dlg.Hide, MB.dlg) end
  MB.idx, MB.name = nil, nil
  return true
end

-- 锚在**被点的那一行**右边；右边放不下就翻到左边（越界回归：绝不把窗挂在屏幕外）
local function mbAnchor(row)
  local d = MB.dlg
  if not d then return end
  local af = mbRowBtn(row) or G("MerchantFrame")
  pcall(d.ClearAllPoints, d)
  if not af then
    pcall(d.SetPoint, d, "CENTER", UIParent, "CENTER", 0, 60)
    return
  end
  local right, screenW = nil, nil
  if type(af.GetRight) == "function" then local ok, v = pcall(af.GetRight, af) if ok then right = v end end
  if UIParent and type(UIParent.GetWidth) == "function" then
    local ok, v = pcall(UIParent.GetWidth, UIParent)
    if ok then screenW = v end
  end
  if type(right) == "number" and type(screenW) == "number" and (right + 8 + MB_W) > screenW then
    pcall(d.SetPoint, d, "TOPRIGHT", af, "TOPLEFT", -8, 6)
  else
    pcall(d.SetPoint, d, "TOPLEFT", af, "TOPRIGHT", 8, 6)
  end
end

-- 四边 1px 描边（**唯一实现**；窗口是固定尺寸 ⇒ 静态几何即可）——
-- ★上/下用**两端锚点**拉满宽 + `SetHeight`、左/右拉满高 + `SetWidth`（与子插件 EH_Bag 的 mkEdge 同一把尺子）。
local function mbEdge(d, r, g, b, a, px)
  local top = d:CreateTexture(nil, "BORDER")
  local bot = d:CreateTexture(nil, "BORDER")
  local lft = d:CreateTexture(nil, "BORDER")
  local rgt = d:CreateTexture(nil, "BORDER")
  local all = { top, bot, lft, rgt }
  for i = 1, 4 do
    all[i]:SetTexture("Interface\\Buttons\\WHITE8X8")
    all[i]:SetVertexColor(r, g, b, a)
  end
  top:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
  top:SetHeight(px)
  bot:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, 0)
  bot:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
  bot:SetHeight(px)
  lft:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
  lft:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, 0)
  lft:SetWidth(px)
  rgt:SetPoint("TOPRIGHT", d, "TOPRIGHT", 0, 0)
  rgt:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
  rgt:SetWidth(px)
  return all
end

-- **边框的唯一实现**（建窗时一次；与「工具箱 → 姓名右键菜单」的 `tbMenuChrome` 逐字同源）：
--   ① `SetBackdrop` 那圈圆角贴图 + **读回自证**（`GetBackdrop` 报出这张边贴图才算真挂上）；
--   ② 挂不上 / 读回说不是它 ⇒ **四边 1px 纯色描边**（fail-open：观感降级，绝不空着、也绝不画错）；
--   ★拿不到 `SetBackdrop`（自定义 UI / 旧客户端）同样走 ②。
--   ★判据与参考实现**逐字一致**：读不到读回值（本客户端可能没这个读值口）按「已挂上」处理，只有
--     「读到了、却不是那张边贴图」才判 flat —— 这样两处边框的观感永远相同。
local function mbChrome(d)
  local kind, edge = "flat", nil
  if type(d.SetBackdrop) == "function" then
    local ok = pcall(d.SetBackdrop, d, {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = MB_EDGE_ART, edgeSize = MB_EDGE_ART,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    if ok then
      if type(d.SetBackdropColor) == "function" then
        pcall(d.SetBackdropColor, d, MB_BG[1], MB_BG[2], MB_BG[3], MB_BG[4])
      end
      if type(d.SetBackdropBorderColor) == "function" then
        pcall(d.SetBackdropBorderColor, d, MB_BD_RGBA[1], MB_BD_RGBA[2], MB_BD_RGBA[3], MB_BD_RGBA[4])
      end
      if type(d.GetBackdrop) == "function" then
        local oks, str = pcall(d.GetBackdrop, d)
        if oks and type(str) == "string" then edge = str end
      end
      if edge == nil or string.find(edge, "UI-Tooltip-Border", 1, true) ~= nil then
        kind = "rounded"
      end
    end
  end
  if kind == "flat" then
    d.edges = mbEdge(d, MB_BD_RGBA[1], MB_BD_RGBA[2], MB_BD_RGBA[3], MB_BD_RGBA[4], MB_EDGE)
  end
  d.bdKind, d.bdEdge = kind, edge
  return kind
end

local function mbBuild()
  if MB.dlg then return MB.dlg end
  local d = CreateFrame("Frame", "EVAL_MB_DLG", UIParent)
  d:SetWidth(MB_W) d:SetHeight(MB_H)
  d:SetFrameStrata("DIALOG")
  d:SetFrameLevel(200)
  d:EnableMouse(true)
  -- 底色 = 纯黑 85%（唯一来源 MB_BG）
  local bg = d:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(d)
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(MB_BG[1], MB_BG[2], MB_BG[3], MB_BG[4])
  -- 边框 = **唯一实现**（与姓名右键菜单同源：圆角 backdrop → 读回自证 → 四边描边兜底）
  local kind = mbChrome(d)
  -- ★★★圆角路径：把上面这块**铺满整帧的方底藏掉**（与参考实现 `if chrome.kind == "rounded" then pcall(bg.Hide, bg) end`
  --   逐字同源）—— 圆角边框贴图是**内缩**的，方底铺满整帧 ⇒ 四条边 / 四个角会从圆角边框**外面**露出一层方边
  --   （真机症状 = 用户截图问的「边框外面还有一层边」）；圆角路径的黑色 85% 由 backdrop 的 bg 提供
  --   （上一句 `SetBackdropColor(MB_BG…)`，与 MB_BG 同一份值 ⇒ 用户要的「黑色 85%」一个字没少）。
  --   ★**兜底路径（flat）必须留着它** —— 那条路没有 backdrop 底，黑 85% 只此一份，藏了就是透明窗。
  if kind == "rounded" then pcall(bg.Hide, bg) end
  d.bg = bg

  -- 标题 = **物品名**，居中放在顶带上（限宽 = 窗宽 − 2×PAD，长名字自己截断）
  local t = d:CreateFontString(nil, "OVERLAY")
  mbFont(t, 12)
  t:SetPoint("TOP", d, "TOP", 0, MB_Y_TITLE)
  t:SetWidth(MB_W - MB_PAD * 2)
  pcall(t.SetJustifyH, t, "CENTER")
  -- ★标题色 = 插件文本色（黄）；与按钮标题共用 `MB_TXT_RGBA`（要调色只改那一个常量）
  pcall(t.SetTextColor, t, MB_TXT_RGBA[1], MB_TXT_RGBA[2], MB_TXT_RGBA[3])
  t:SetText(L("MB_TITLE"))
  d.title = t

  -- 左：数量前缀「x」—— 数量值**紧跟它右边**（用户 1.76.1k：「将每笔换成 x 数量(20)…对齐左边」）
  local pre = d:CreateFontString(nil, "OVERLAY")
  mbFont(pre, 10)
  pre:SetPoint("TOPLEFT", d, "TOPLEFT", MB_PAD, MB_Y_EACH)
  pre:SetWidth(MB_X_W)
  pcall(pre.SetJustifyH, pre, "LEFT")
  pcall(pre.SetTextColor, pre, 0.85, 0.85, 0.85)
  pre:SetText(MB_XPRE)
  d.pre = pre

  -- ★★数值块（1.76.1k 版式）：**紧跟「x」右边 · 左对齐**（旧版贴右内边距右对齐 —— 用户要求「对齐左边」）
  --   EditBox 在本项目里有过「pcall 全成功却看不见」的旧账 ⇒ 仍配一行**回声**兜底；
  --   ★两句占**同一块位置 + 同一左缘**（都左对齐）⇒ 谁被渲染都只有一个数，绝不会「20 20」并排。
  local eb = CreateFrame("EditBox", "EVAL_MB_DLG_EDIT", d)
  eb:SetWidth(MB_VAL_W) eb:SetHeight(18)
  eb:SetPoint("TOPLEFT", d, "TOPLEFT", MB_PAD + MB_X_W, MB_Y_EACH + 3)
  eb:SetAutoFocus(false)
  pcall(eb.SetMaxLetters, eb, 6)
  mbFont(eb, 11)
  pcall(eb.SetTextInsets, eb, 2, 2, 0, 0)
  pcall(eb.SetJustifyH, eb, "LEFT")   -- 数字紧跟「x」（与回声同一左缘）
  eb:SetText(tostring(MB_DEF))
  eb:SetScript("OnEscapePressed", function() mbHideDlg() end)
  eb:SetScript("OnEnterPressed", function()
    local self = mbDlgEdit()
    if self then
      local s = nil
      local ok, v = pcall(self.GetText, self)
      if ok then s = v end
      s = string.gsub(tostring(s or ""), "%D", "")
      local n = tonumber(s)
      if n and n >= 1 then MB.qty = n end
    end
    local f = G("EVAL_MB_CONFIRM")
    if type(f) == "function" then pcall(f) end
  end)
  eb:SetScript("OnTextChanged", function()
    local self = mbDlgEdit()
    if not self then return end
    local ok, v = pcall(self.GetText, self)
    local s = ok and tostring(v or "") or ""
    local digits = string.gsub(s, "%D", "")
    if digits ~= s then pcall(self.SetText, self, digits) return end
    local n = tonumber(digits)
    if n and n >= 1 then MB.qty = n end
    if d.echo then pcall(d.echo.SetText, d.echo, tostring(MB.qty or MB_DEF)) end
  end)
  d.edit = eb

  local echo = d:CreateFontString(nil, "OVERLAY")
  mbFont(echo, 10)
  echo:SetPoint("TOPLEFT", d, "TOPLEFT", MB_PAD + MB_X_W, MB_Y_EACH)
  echo:SetWidth(MB_VAL_W)
  pcall(echo.SetJustifyH, echo, "LEFT")
  -- ★它现在是**主显示**（数量值就摆在这一行）⇒ 亮白；旧写法是 0.62 灰的「兜底读数」
  pcall(echo.SetTextColor, echo, 0.95, 0.95, 0.95)
  echo:SetText(tostring(MB_DEF))
  d.echo = echo

  -- 尾段 = 「· N个 单价」（`MB_EACH`）：**锚在数值块右边** ⇒ 数量几位都自动跟随（不写死 x 坐标）；
  --   限宽到右内边距（长价格自己截断，绝不折行压到下一行 —— 旧版那句整句限宽就是这么在真机上折行的）。
  local tail = d:CreateFontString(nil, "OVERLAY")
  mbFont(tail, 10)
  tail:SetPoint("LEFT", echo, "RIGHT", MB_VAL_GAP, 0)
  tail:SetWidth(MB_W - MB_PAD * 2 - MB_X_W - MB_VAL_W - MB_VAL_GAP)
  pcall(tail.SetJustifyH, tail, "LEFT")
  pcall(tail.SetTextColor, tail, 0.85, 0.85, 0.85)
  tail:SetText(string.format(L("MB_EACH"), 1, mbMoney(0)))
  d.tail = tail

  local minus = mbBtn(d, 28, 18, "-" .. tostring(MB_STEP), MB_PAD, MB_Y_STEP)
  local plus = mbBtn(d, 28, 18, "+" .. tostring(MB_STEP), MB_W - MB_PAD - 28, MB_Y_STEP)
  minus:SetScript("OnClick", function() pcall(EVAL_MB_STEP, -1) end)
  plus:SetScript("OnClick", function() pcall(EVAL_MB_STEP, 1) end)
  -- ★1.76.1c：Shift 大步要**能被发现** ⇒ 两颗按钮悬停说清「点一下 N / 按住 Shift N」
  local steptip = string.format(L("MB_STEP_TIP"), MB_STEP, MB_STEP_FAST)
  mbTip(minus, { steptip })
  mbTip(plus, { steptip })
  d.minus, d.plus = minus, plus

  -- ★屏上**唯一**保留的文字行（1.76.1j 用户：「批量购买内的文本可以删除只保留…总计金额计算值」）：
  --   「本单约 X」；原来那一行的「上限 N 个」与下面那一整行操作提示都已挪进按钮悬停（屏上一个字都不显示）。
  local tot = d:CreateFontString(nil, "OVERLAY")
  mbFont(tot, 10)
  tot:SetPoint("TOPLEFT", d, "TOPLEFT", MB_PAD, MB_Y_TOTAL)
  pcall(tot.SetTextColor, tot, 0.72, 0.78, 0.95)
  tot:SetText(string.format(L("MB_TOTAL"), mbMoney(0)))
  d.total = tot

  local cancel = mbBtn(d, 66, 20, L("MB_CANCEL"), MB_PAD, MB_Y_BTN)
  local buy = mbBtn(d, 66, 20, L("MB_BUY"), MB_W - MB_PAD - 66, MB_Y_BTN)
  -- ★★被删掉的两行字去哪了（1.76.1j 用户选定「挪进悬停」）：鼠标停在按钮上才出 ——
  --   [取消] = Enter 确认 · Esc 取消；[购买] = 上限 N 个 + 本单约 X + 同一句操作说明。
  --   ★上限与金额**悬停那一刻现算**（传函数，见 mbTip）—— 建窗时把字符串拍死会显示过期值。
  mbTip(cancel, { L("MB_HINT") })
  mbTip(buy, function()
    return {
      string.format(L("MB_CAP"), tonumber(MB.cap) or 0),
      string.format(L("MB_TOTAL"), mbMoney(mbCost())),
      L("MB_HINT"),
    }
  end)
  cancel:SetScript("OnClick", function() mbHideDlg() end)
  buy:SetScript("OnClick", function()
    local f = G("EVAL_MB_CONFIRM")
    if type(f) == "function" then pcall(f) end
  end)
  d.buy, d.cancel = buy, cancel

  pcall(d.Hide, d)
  MB.dlg = d
  return d
end

-- 开窗（**唯一入口**）。返回 true = 已接管这一下点击；false = 交回原生处理体。
mbOpenDlg = function(row)
  if not EVAL_MB_ON() then return false end
  if not mbMerchantOpen() then return false end
  local idx = mbRowIndex(row)
  if not idx then
    MB.last = "第 " .. tostring(row) .. " 行取不到槽位号（GetID 与 page 都不行）"
    return false
  end
  local nm, _tex, price, per, avail = mbItem(idx)
  if not nm then
    MB.last = "槽位 " .. tostring(idx) .. " 取不到物品（GetMerchantItemInfo 返空）"
    return false
  end
  MB.idx, MB.name, MB.per, MB.price = idx, nm, per, price
  MB.cap = mbCap(price, per, avail)
  if MB.cap < 1 then
    MB.last = "槽位 " .. tostring(idx) .. " 已达上限（库存/银两）"
    sayF(string.format(L("MB_REFUSE"), nm))
    return false
  end
  MB.qty = MB_DEF
  if MB.qty > MB.cap then MB.qty = MB.cap end
  local d = mbBuild()
  mbAnchor(row)
  mbDlgPaint()
  local cat = mbCatchBuild()
  if cat then pcall(cat.Show, cat) end -- ★捕手先起（点窗外任意位置即关）
  pcall(d.Show, d)
  MB.last = "开窗：槽位 " .. tostring(idx) .. " " .. tostring(nm) .. "（上限 " .. tostring(MB.cap) .. "）"
  return true
end

-- 步进（唯一入口；★夹取到 [1, cap]，到极限**不出声刷屏**，改由上限行现算）
--   ★1.76.1c 用户：「shift 点击增减按钮支持 20+递进」⇒ **点一下 = ±MB_STEP(5)，按住 Shift 点 = ±MB_STEP_FAST(20)**。
--   ★Shift 状态**在点的那一刻现读**（`IsShiftKeyDown`）—— 我们的按钮是自建闭包、点击参数不一定带修饰键，
--     而本项目 1.75.102 对配置窗 ± 用的就是「点一下 = 基础递步 / 按住 Shift = 大步」这套同一口径。
function EVAL_MB_STEP(dir)
  local d = tonumber(dir) or 0
  if d == 0 then return false end
  local shift = false
  local sk = G("IsShiftKeyDown")
  if type(sk) == "function" then
    local ok, v = pcall(sk)
    shift = (ok and v == true)
  end
  local step = shift and MB_STEP_FAST or MB_STEP
  local n = (tonumber(MB.qty) or MB_DEF) + (d > 0 and step or -step)
  local cap = tonumber(MB.cap) or 999
  if n < 1 then n = 1 end
  if n > cap then n = cap end
  MB.qty = n
  MB.last = "数量 " .. tostring(n) .. "（步进 " .. tostring(step) .. (shift and " · Shift）" or "）")
  mbDlgPaint()
  return n
end

-- 确认（唯一入口）：**把订单交给宿主**（写动作与安全闸门全在那边）
function EVAL_MB_CONFIRM()
  local idx, n, name = MB.idx, tonumber(MB.qty) or 0, MB.name
  if not idx or n < 1 then
    sayF(L("MB_NONE"))
    return false
  end
  local cap = tonumber(MB.cap) or 999
  if n > cap then n = cap end
  mbHideDlg()
  local f = G("EVAL_TB_MBULK_ENQUEUE")
  if type(f) ~= "function" then
    -- ★如实说，绝不假装成功（宿主没载入 = 这一下点了什么都不会发生）
    sayF(L("MB_NO_BRIDGE"))
    return false
  end
  local ok, got, msg = pcall(f, idx, n, name)
  if not ok then
    sayF(string.format(L("MB_ERR"), tostring(got)))
    return false
  end
  if not got then
    sayF(tostring(msg or L("MB_NONE")))
    return false
  end
  MB.last = "下单：槽位 " .. tostring(idx) .. " " .. tostring(name) .. " ×" .. tostring(n)
  return true
end

-- ===== 节拍 / 事件（挂摘只有一个入口 `mbBeatSync`）=====
local function mbOnEvent()
  -- ★事件名走全局 `event`（本客户端脚本处理体的调用约定：零形参 + 全局 event/arg1）
  local e = rawget(_G, "event")
  if e == "MERCHANT_SHOW" then
    MB.armed = true        -- ★事件本身 = 商人窗开了的证据（不押注这一拍帧显隐读到的是不是 true）
  elseif e == "MERCHANT_HIDE" then
    MB.armed = false
  end
  if type(EVAL_MB_SYNC) == "function" then pcall(EVAL_MB_SYNC) end
end

local function mbTick()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (MB.beatAt or 0) < MB_BEAT then return end
  MB.beatAt = now
  -- ★自愈：帧已经不可见 ⇒ 漏收了 MERCHANT_HIDE（或客户端自绘窗）⇒ 当拍收摊（不靠外部标志）
  if not mbFrameOpen() then
    MB.armed = false
    if type(EVAL_MB_SYNC) == "function" then pcall(EVAL_MB_SYNC) end
    return
  end
  mbHook() -- 幂等核查：补挂这一轮新出现/被重建的行
end

local function mbBeatSync()
  local need = EVAL_MB_ON() and mbMerchantOpen()
  if need then
    if not MB.beat then
      MB.beat = CreateFrame("Frame")
      pcall(MB.beat.SetScript, MB.beat, "OnUpdate", mbTick)
    else
      pcall(MB.beat.SetScript, MB.beat, "OnUpdate", mbTick) -- ★重挂：关一次再开也必须活（本项目踩过）
    end
    MB.beatAt = 0
    mbHook()
  else
    if MB.beat then pcall(MB.beat.SetScript, MB.beat, "OnUpdate", nil) end -- ★真摘
    mbUnhook()
    mbHideDlg()
  end
  return need
end

-- **唯一装/摘入口**（VARIABLES_LOADED、工具箱勾选、命令三条路都走它；幂等）
function EVAL_MB_SYNC()
  local on = EVAL_MB_ON()
  if MB.ev == nil then
    MB.ev = CreateFrame("Frame")
    pcall(MB.ev.SetScript, MB.ev, "OnEvent", mbOnEvent)
  end
  if on then
    pcall(MB.ev.RegisterEvent, MB.ev, "MERCHANT_SHOW")
    pcall(MB.ev.RegisterEvent, MB.ev, "MERCHANT_HIDE")
  else
    pcall(MB.ev.UnregisterEvent, MB.ev, "MERCHANT_SHOW")
    pcall(MB.ev.UnregisterEvent, MB.ev, "MERCHANT_HIDE")
  end
  return mbBeatSync()
end

function EVAL_MB_SET(v)
  local tb = tbCfgGet()
  if type(tb) == "table" then tb.merchantBulk = v and true or false end
  EVAL_MB_SYNC()
  return EVAL_MB_ON()
end

-- 载入期入口（VARIABLES_LOADED 调用；**默认开** ⇒ 这里就把钩子/事件装起来）
function EVAL_MB_INSTALL()
  EVAL_MB_SYNC()
  return EVAL_MB_ON()
end

-- ===== 读值口（诊断/探针；直给真实字段，动作走真实入口）=====
function EVAL_MB_TEST_STATE()
  local rowNames = {}
  for i = 1, MB_ROW_MAX do
    local b = mbRowBtn(i)
    if b then
      local idx = mbRowIndex(i)
      local nm = idx and mbItem(idx) or nil
      table.insert(rowNames, string.format("#%d %s idx=%s %s", i, mbName(b), tostring(idx), tostring(nm or "-")))
    end
  end
  local maxStack = nil
  local msf = G("GetMerchantItemMaxStack")
  if type(msf) == "function" and MB.idx then
    local ok, v = pcall(msf, MB.idx)
    if ok then maxStack = v end
  end
  return {
    on = EVAL_MB_ON(), hooks = MB.hookN, merchant = mbMerchantOpen(), armed = (MB.armed == true),
    frameOpen = mbFrameOpen(),
    dlg = mbShown(MB.dlg), catch = mbShown(MB.catch),
    -- ★1.76.1f 边框自证（配方式，**不可切换** —— 手工九宫格已按用户要求整条撤掉）：
    --   `bdKind` = 实际走的那条路（rounded = 客户端圆角贴图已挂上 / flat = 四边 1px 描边）；
    --   `bdEdge` = `GetBackdrop` 读回值（false = 读不到 ⇒ 按「已挂上」处理，与参考实现同一判据）；
    --   `setBackdrop` = 客户端有没有这个 API（只作记录）。
    bdKind = (MB.dlg ~= nil and MB.dlg.bdKind) or false,
    bdEdge = (MB.dlg ~= nil and MB.dlg.bdEdge) or false,
    -- ★1.76.1h 自建方底的显隐（**"边框外面还有一层边" 的唯一判据**）：
    --   rounded 路径**必须**为 false（方底已藏 ⇒ 没有那层露在圆角边框外面的方边）；
    --   flat 路径必须为 true（那条路只有这块方底能当黑色底）。两者相反 = 一定写错了。
    bdBg = (MB.dlg ~= nil and mbShown(MB.dlg.bg)),
    setBackdrop = (MB.dlg ~= nil and type(MB.dlg.SetBackdrop) == "function") or false,
    stepBase = MB_STEP, stepFast = MB_STEP_FAST,
    idx = MB.idx, name = MB.name, per = MB.per, price = MB.price, qty = MB.qty, cap = MB.cap,
    maxStack = maxStack, last = MB.last, rows = rowNames,
  }
end

-- ===== 工具箱模块行（Toolbox 侧只有一行数据；这里是嵌入点被调方）=====
local mbRow = function(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return EVAL_MB_ON() end
  r.set = function(v) EVAL_MB_SET(v and true or false) end
  if r.extra then r.extra:Hide() end          -- 配置项只在 tip 里说，行上不重复
  if r.add and r.add.btn then r.add.btn:Hide() end
  if r.clr and r.clr.btn then r.clr.btn:Hide() end
  return true
end

local MB_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(MB_TB_ROWS) ~= "table" then
  MB_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", MB_TB_ROWS)
end
MB_TB_ROWS["merchantBulk"] = mbRow

-- ===== 命令（/eh go 商人 ……；纯读优先，写命令都要人点名）=====
local function mbStateLines()
  local st = EVAL_MB_TEST_STATE()
  sayF(string.format(L("MB_STATE"), st.on and L("SH_ON") or L("SH_OFF"), st.hooks, MB_ROW_MAX,
    st.merchant and L("SH_ON") or L("SH_OFF")))
  sayF(string.format(L("MB_STATE_API"), tostring(st.maxStack)))
  sayF(string.format(L("MB_STATE_BD"), tostring(st.bdKind))) -- ★边框配方 + 实际走的那条路
  sayF(string.format(L("MB_STATE_BD2"),                     -- ★客户端有没有 SetBackdrop + 读回值（只作记录）
    (st.setBackdrop and L("SH_ON") or L("SH_OFF")),
    (st.bdEdge and tostring(st.bdEdge) or L("SH_OFF"))))
  -- ★1.76.1h 自建方底显隐 —— 这一行就是「边框外面还有一层边」的判据（rounded ⇒ 必须为「关」= 已藏）
  sayF(string.format(L("MB_STATE_BG"), (st.bdBg and L("SH_ON") or L("SH_OFF"))))
  sayF("　" .. string.format(L("MB_STEP_TIP"), st.stepBase, st.stepFast)) -- 探针也把步进口径摊开
  for i = 1, table.getn(st.rows or {}) do sayF("   " .. st.rows[i]) end
  if st.last and st.last ~= "" then sayF(L("MB_LAST") .. "：" .. st.last) end
end

function EVAL_MB_CMD(msg)
  local rest = string.gsub(tostring(msg or ""), "^go%s*", "")
  rest = string.gsub(rest, "^商人%s*", "")
  rest = string.gsub(rest, "%s+$", "")
  if rest == "开" or rest == "on" then
    EVAL_MB_SET(true)
    sayF(string.format(L("MB_SET"), L("SH_ON")))
  elseif rest == "关" or rest == "off" then
    EVAL_MB_SET(false)
    sayF(string.format(L("MB_SET"), L("SH_OFF")))
  elseif string.find(rest, "^边框") or string.find(rest, "^bd") then
    -- /eh go 商人 边框：**只读**播报边框配方与自证（1.76.1f 起**样式不可切换** —— 手工九宫格已按用户要求撤掉，
    --   现档 = 与工具箱·姓名右键菜单同源的那一套；带参数也按只读处理，绝不假装换了样式）。
    local st = EVAL_MB_TEST_STATE()
    sayF(string.format(L("MB_STATE_BD"), tostring(st.bdKind)))
    sayF(string.format(L("MB_STATE_BD2"),
      (st.setBackdrop and L("SH_ON") or L("SH_OFF")),
      (st.bdEdge and tostring(st.bdEdge) or L("SH_OFF"))))
    sayF(string.format(L("MB_STATE_BG"), (st.bdBg and L("SH_ON") or L("SH_OFF"))))
  elseif string.find(rest, "^窗") then
    -- /eh go 商人 窗 [行号]：强制开一次数量窗（真机验证钩子替代品，不用真的按 Shift+右键）
    local n = tonumber(string.match(rest, "(%d+)")) or 1
    if type(mbOpenDlg) == "function" and mbOpenDlg(n) then
      sayF(string.format(L("MB_DLG_OPEN"), n))
    else
      sayF(L("MB_NONE"))
    end
  elseif string.find(rest, "^买") then
    -- /eh go 商人 买 <行号> <个数>：跳过弹窗直接下单（真机排查用；★真花钱，故必须人点名）
    local row = tonumber(string.match(rest, "(%d+)")) or 0
    local n = tonumber(string.match(rest, "%d+%s+(%d+)")) or 0
    local idx = (row >= 1) and mbRowIndex(row) or nil
    local nm = idx and mbItem(idx) or nil
    if not idx or not nm or n < 1 then
      sayF(L("MB_NONE"))
    else
      MB.idx, MB.name, MB.qty = idx, nm, n
      MB.cap = 999
      EVAL_MB_CONFIRM()
    end
  else
    mbStateLines()
    sayF(L("MB_USAGE"))
  end
  return true
end
