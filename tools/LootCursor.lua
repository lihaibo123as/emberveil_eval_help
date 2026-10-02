-- EvalHelp · tools/LootCursor.lua —— 拾取贴手 · 点一次自动换下一件（1.75.26 新增）
--
-- 需求（用户原话，三次确认）：
--   ①「拾取框物品能否重叠在当前鼠标位置方便快速点击？」→ 调研后定**方案 A：搬整个拾取窗**（不重建 UI）；
--   ②「默认吸附一次（开关可切跟随）+ 加品质色描边」；
--   ③「每次点击自动换下一个物品 · **不用等点击之后是否拾取成功**」← 本文件就是实现它。
--
-- ★★★ 1.75.63 改版（用户：「装备右下角小方块标识装备稀有度的**换一种方式.直接对装备外框进行稀有度描边**,
--   参考图片内」+「**只对普通以上的稀有度染色.普通灰色这种白的的不需要高亮**」）：品质标识由「格子右下角一块
--   9×9 方块」改成**沿整格外框描一圈品质色**（四条边各一条，见 `lcMarkNew`），且**只描「优秀及以上」**
--   （`LC_EDGE_MIN_Q` = 2；白装/灰装不描，金币金色例外）—— 与客户端自带的品质边框视觉一致（参考图那圈绿框）。
--   配置键仍是 `marks`（存档兼容），界面/命令文案改叫「品质描边」（旧命令词 `角标` / `marks` 继续认，别删）。
--
-- ★★★ 真机实测事实（1.74.34-39 探针读数）：
--   · 玩家看到的那扇窗**就是** `LootFrame`（探针「光标帧」比过对象身份）；`LootButton1..4` 类型 = `LootButton`、
--     **37×37**、竖向**链式互锚**（`TOP/LootButton(i-1)/BOTTOM/0,-4`）⇒ 搬窗时按钮自动跟随；
--   · 按钮1中心相对窗左下 = **(24,139)**、相邻**间距 41px**（★代码里**现算**，不写死这两个数）；
--   · `OnClick` 被原生处理体占（`LootFrameItem_OnClick(arg1)`）、`OnEnter/OnLeave` 被原生 tooltip 占，
--     **`OnMouseDown`/`OnMouseUp` 是空槽**；
--   · `GroupLootFrame1..4` 挂在 **WorldFrame**（不在 LootFrame 下）⇒ 搬窗不会连带 roll 框；
--   · 自建纹理贴得上（读回 `Interface\Buttons\WHITE8X8`）⇒ 品质描边可行；
--   · `UIParent` = 1371.79×768、有效缩放 1.000（光标物理像素 == UI 坐标；仍按配方除缩放，兼容其它档）。
--
-- ★★★ 为什么挂 `OnClick`、**不是** `OnMouseDown`（本模块最关键的一条判断，别再改回去）：
--   玩家的「点击」= 按下 + 抬起两拍（人手 80~150ms）。若在**按下**那一刻就把窗搬走，**抬起**时鼠标底下已经
--   换成另一个按钮 ⇒ 客户端会把 OnClick 派发给那个新按钮 = **拾到下一件、漏掉这一件**（本客户端按钮是抬起
--   触发）。⇒ 唯一既安全又「立刻」的时机 = 原生 OnClick **跑完之后**：这一拍这次点击已完整派发、拾取请求
--   已照原样发出（我们只**包装**、不改它的行为），而服务器通常还没回话 —— 正合用户「不等拾取成功确认」。
--
-- ★包装纪律：**绝不覆盖**原生处理体 —— 先存旧的、装我们的，包装里**零参数**调旧函数（客户端把 `this`/`arg1`
--   放在全局里，零参数调用就是原生脚本的调用约定）；关功能时按**身份比对**复原（只换回我们装的那个，
--   期间被别的插件套过的包装不许冲掉），并读回自证。
--
-- ★「下一件」怎么定（**不假设客户端会不会把槽位往上压实**）：
--   默认按「不压实」走（本客户端是 FrameXML 那套 `LootFrame.page` / `LOOTFRAME_NUMBUTTONS` 分页实现，
--   空槽只是把按钮 Hide、槽位不搬家）⇒ 点完第 i 格把窗**上移一格**，让 **i+1 格**落到光标下。
--   ★同时**运行期自证**：点完那一下的前后槽位表一比，若「原来 i+1 格的东西出现在 i 格」= 客户端其实会压实
--   ⇒ 记 `LC.compact = true`、当场把窗挪回去，以后同格原地换（**绝不让用户漏拾**）。
--   ★「下一件」的唯一算法 = `lcNextSlot(i)`：先找 i 之后最小编号的有物品槽，没有就绕回最小编号（排除 i 自己）
--   ⇒ 它天然兼容「压实」与「不压实」两种客户端（只是窗要不要搬不同）。
--
-- ★安全契约（关掉 = 一个动作都不做）：总开关闸在**所有探测/读写之前**；关掉那一刻
--   ① 摘掉 4 个 OnClick 包装（按身份复原）② 收起品质描边 ③ 把窗按**开窗那一刻**抓到的原位放回去（读回自证）
--   ④ 注销事件 + 摘掉 OnUpdate（绝不常驻 ticking）。
--
-- 依赖的全局桥（只在调用时读，载入期不读 ⇒ 与 toc 顺序解耦）：
--   EVAL_SAY / EVAL_L / EVAL_TB_CFG / EVAL_HELP_CONFIG / EVAL_DD_OPEN / EVAL_TB_MOD_ROWS

local LC = {
  built = false,      -- 事件帧是否已武装（读值口）
  evF = nil,
  orig = nil,         -- **开窗那一刻**客户端的原位锚点（关功能/切档时还回去的唯一依据）
  wrappers = {},      -- [i] = 我们装的包装（身份比对用）
  wrapped = {},       -- [i] = 被我们包起来的旧处理体（复原用）
  hooked = false,
  slot = nil,         -- 当前「光标底下那一格」
  compact = nil,      -- nil=还不知道 / false=不压实 / true=会压实
  before = nil,       -- 点击瞬间的槽位名表（自证压实用的对照）
  lastClickSlot = nil,
  hold = nil,         -- 有界重申窗口 { until = 时刻, x = 左, y = 下 }
  marks = {},         -- [i] = 品质描边的 4 条边纹理 {上,下,左,右}（懒建、复用；见 lcMarkNew）
  reasserts = 0,      -- 被客户端摆回去、我们重申的次数（判据：>0 ⇒ 这客户端会抢位置）
  repairs = 0,        -- 尺寸被撑坏、我们修回来的次数
  normalized = 0,     -- 开窗时把「我们自己的锚点」清掉、还原成客户端锚点形态的次数
  refW = nil, refH = nil, -- 本会话第一份**尺寸正常**的读数（判「有没有被撑变形」的基准）
  placed = 0,         -- 成功对准次数
  clicked = 0,        -- 我们处理过的点击次数
  failed = 0,
  lastVerdict = "",
  lastFollow = 0,
  out = {},           -- 有界读数环（AI 侧读存档用；say 不落日志环）
}

-- ===== 常量（单一来源） =====
local LC_OUT_MAX = 40
local LC_HOLD_SEC = 0.5      -- 搬完窗后的**有界**重申窗口（客户端可能在我们之后自己又摆一次）
local LC_EMPTY_SEC = 0.6     -- 开窗那一拍读不到槽位时的**有界**重试窗口（读到就贴，过了如实说一次）
local LC_FOLLOW_GAP = 0.15   -- 跟随档节拍（只在窗开着时跑）
local LC_FOLLOW_MIN = 4      -- 跟随档最小响应位移（小抖动不搬，避免鼠标下swap）
local LC_EDGE_PX = 2         -- 品质描边粗细（逻辑像素；**只改这一个数**就能调粗细）
local LC_EDGE_INSET = 0      -- 描边相对格子边缘的内缩（0 = 正贴格子外框，和客户端自带品质边框同一圈）
-- ★★★描边只给**优秀及以上**（用户 1.75.63：「**只对普通以上的稀有度染色.普通灰色这种白的的不需要高亮**」）：
--   品质序号 0=粗糙(灰) / 1=普通(白) / 2=优秀(绿) / 3=精良(蓝) / 4=史诗(紫) / 5=传说(橙)
--   ⇒ `< LC_EDGE_MIN_Q` 一律不描（白装/灰装满地都是，描了等于把「值得捡的」淹没在噪声里）。
--   ★**金币例外**：那不是稀有度档（`quality` 也是 0），照旧金色高亮。
local LC_EDGE_MIN_Q = 2
local LC_PITCH_FALLBACK = 41 -- 只作兜底：按钮间距**优先现算**（真机实测 41）
-- ★帧的**标称尺寸**（真机探针实测 256×256；开窗/空窗都一样 —— 拾取窗是固定尺寸，不随件数变）
--   只在「抓到的尺寸明显被撑坏」时当兜底用（见 lcSizeBad / lcRepair）
local LC_NOMINAL_W, LC_NOMINAL_H = 256, 256
local LC_SIZE_MIN, LC_SIZE_MAX = 64, 512
local LC_QCOLOR = {          -- 品质色（0 粗糙 → 5 传说）；金币另有金色
  { 0.62, 0.62, 0.62 }, { 1.00, 1.00, 1.00 }, { 0.12, 1.00, 0.12 },
  { 0.00, 0.44, 1.00 }, { 0.63, 0.13, 0.94 }, { 1.00, 0.50, 0.00 },
}
local LC_COIN_COLOR = { 1.00, 0.82, 0.16 }

-- ===== 输出 / 本地化 =====
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function lcSay(msg)
  LC.out[table.getn(LC.out) + 1] = tostring(msg)
  while table.getn(LC.out) > LC_OUT_MAX do table.remove(LC.out, 1) end
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(msg)) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

-- ===== 配置（真值只有两处：总开关在工具箱表 tbCfg().lootCursor；两个档在模块自己的子树） =====
local function lcTb()
  if type(EVAL_TB_CFG) == "function" then return EVAL_TB_CFG() end
  return rawget(_G, "EVAL_HELP_CONFIG")
end

local function lcAllCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then c = {} rawset(_G, "EVAL_HELP_CONFIG", c) end
  if type(c.lootCursorCfg) ~= "table" then c.lootCursorCfg = {} end
  return c.lootCursorCfg
end

local function lcFollowOn() return lcAllCfg().follow == true end
local function lcMarksOn() local v = lcAllCfg().marks return (v == nil) and true or (v == true) end
local function lcSetFollow(v) lcAllCfg().follow = v and true or false return true end
local function lcSetMarks(v) lcAllCfg().marks = v and true or false return true end

function EVAL_LC_ENABLED()
  local tb = lcTb()
  return (type(tb) == "table" and tb.lootCursor == true) and true or false
end

-- ===== 帧 / 几何 =====
local function lcNow()
  if type(GetTime) == "function" then local ok, v = pcall(GetTime) if ok and tonumber(v) then return tonumber(v) end end
  return 0
end

local function lcFrame() return rawget(_G, "LootFrame") end
local function lcNumButtons()
  local n = tonumber(rawget(_G, "LOOTFRAME_NUMBUTTONS"))
  if n and n >= 1 and n <= 12 then return n end
  return 4
end
local function lcBtn(i) return rawget(_G, "LootButton" .. tostring(i)) end

-- 已包装的按钮数（消息里报的是**总数**；lcHook 的返回值只数「这次新包的」）
local function lcCountWrapped()
  local n = 0
  for i = 1, lcNumButtons() do if LC.wrappers[i] then n = n + 1 end end
  return n
end

local function lcShown(f)
  f = f or lcFrame()
  if not f or type(f.IsShown) ~= "function" then return false end
  local ok, v = pcall(f.IsShown, f)
  return (ok and v) and true or false
end

-- 实测左下角（★真机教训：客户端会用 `TOPLEFT/UIParent/BOTTOMLEFT/x,y` 这类混搭锚点 ⇒ 判几何只看实测值，别认锚点类型）
local function lcLeftBottom(f)
  if not f then return nil, nil end
  local ok, l, b = pcall(function() return f:GetLeft(), f:GetBottom() end)
  if not (ok and tonumber(l) and tonumber(b)) then return nil, nil end
  return tonumber(l), tonumber(b)
end

local function lcCenter(f)
  if not f then return nil, nil end
  local ok, l, b, w, h = pcall(function() return f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight() end)
  if not (ok and tonumber(l) and tonumber(b)) then return nil, nil end
  return tonumber(l) + (tonumber(w) or 0) / 2, tonumber(b) + (tonumber(h) or 0) / 2
end

-- 光标（UI 坐标）——★照本仓已验证配方：GetCursorPosition 给**物理像素**，必须除 UIParent 有效缩放
local function lcCursor()
  local rx, ry, sc = nil, nil, 1
  if type(GetCursorPosition) == "function" then
    local ok, x, y = pcall(GetCursorPosition)
    if ok and tonumber(x) and tonumber(y) then rx, ry = tonumber(x), tonumber(y) end
  end
  local up = rawget(_G, "UIParent")
  if type(up) == "table" and type(up.GetEffectiveScale) == "function" then
    local ok, s = pcall(up.GetEffectiveScale, up)
    if ok and tonumber(s) and tonumber(s) > 0 then sc = tonumber(s) end
  end
  if not rx then return nil, nil end
  return rx / sc, ry / sc
end

-- ★★★搬窗的**唯一手法 = 就地平移**（绝不 `ClearAllPoints`）—— 这是本模块第二个别改错的判据：
--   真机事故（1.75.26 用户截图「拾取框有点变形」）：老写法 `ClearAllPoints()` 之后自己 `SetPoint("BOTTOMLEFT",…)`，
--   而客户端随后会把它**自己的**锚点（真机是 `TOPLEFT/…`）补回来 ⇒ 同一帧上边一个 TOPLEFT、下边一个 BOTTOMLEFT，
--   **高度被两条边"撑"出来** = 竖直拉长（宽度不变、居中的「物品」标题跑到中间）。
--   ⇒ 正解 = 保留**客户端自己的锚点结构**，只把它的 x/y 各加一个位移（尺寸/版式一个字节都不动）；
--     客户端以后重锚的又是**同一个点名** ⇒ 永远只有一条边一个锚点，撑不起来。
--   位移一律「按实测差值算」（lcLeftBottom 现读），不猜坐标系。
local function lcShift(f, dx, dy)
  if not f or (dx == 0 and dy == 0) then return false end
  local n = 0
  for k = 1, 4 do
    local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, k)
    if not (ok and p) then break end
    local nx, ny = (tonumber(x) or 0) + dx, (tonumber(y) or 0) + dy
    local okS
    if rel then okS = pcall(f.SetPoint, f, p, rel, rp, nx, ny)
    else okS = pcall(f.SetPoint, f, p, nx, ny) end
    if okS then n = n + 1 end
  end
  return n > 0
end

-- 把**实测左下**搬到 (nx,ny)：按实测差值就地平移
local function lcMoveTo(f, nx, ny)
  local l, b = lcLeftBottom(f)
  if not l then return false end
  return lcShift(f, nx - l, ny - b)
end

-- 尺寸自检：读数正常且与本会话基准一致 ⇒ true
local function lcSizeBad(f)
  local ok, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
  if not (ok and tonumber(w) and tonumber(h)) then return false end
  w, h = tonumber(w), tonumber(h)
  local rw, rh = LC.refW or LC_NOMINAL_W, LC.refH or LC_NOMINAL_H
  return (math.abs(w - rw) > 2 or math.abs(h - rh) > 2), w, h
end

-- 记住第一份「尺寸正常」的读数当基准（被撑坏的尺寸**不许**当基准）
local function lcRememberSize(w, h)
  if LC.refW then return end
  if w and h and w >= LC_SIZE_MIN and w <= LC_SIZE_MAX and h >= LC_SIZE_MIN and h <= LC_SIZE_MAX then
    LC.refW, LC.refH = w, h
  end
end

-- 锚点快照 / 还原（抓**开窗那一刻**客户端的原位；还原后读回自证）
--   ★快照里连**尺寸**一起抓：还原时按它复位 ⇒ 就算中途被撑变形也一并修回来
local function lcSnap(f, n)
  local o = { pts = {} }
  if not f then return o end
  for k = 1, (n or 4) do
    local ok, p, rel, rp, x, y = pcall(f.GetPoint, f, k)
    if ok and p then o.pts[k] = { p = p, rel = rel, rp = rp, x = x, y = y } end
  end
  o.left, o.bottom = lcLeftBottom(f)
  local ok, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
  if ok and tonumber(w) and tonumber(h) then o.w, o.h = tonumber(w), tonumber(h) end
  return o
end

-- ★「我们自建的锚点」指纹（老构建 lcPlace 写的就是这一种）：清账/还原时要把它摘掉，
--   否则它 + 客户端自己的 TOPLEFT = 两条竖直边 = 撑变形（原样还回去 = 把变形一起还回去）。
local function lcIsOurs(p)
  return type(p) == "table" and p.p == "BOTTOMLEFT" and tostring(p.rp or "") == "BOTTOMLEFT"
end

local function lcHasLegacy(o)
  if not o or type(o.pts) ~= "table" then return false end
  for k = 1, table.getn(o.pts) do if lcIsOurs(o.pts[k]) then return true end end
  return false
end

-- 还原：清干净后**只放客户端自己的锚点**（单边单点 ⇒ 撑不起来）+ 按快照复位尺寸
local function lcApply(o, f)
  if not f or not o or table.getn(o.pts) == 0 then return false end
  -- 先摘掉我们自建的锚点；摘完一个不剩（极端情况）就退回第一个，绝不留下空锚点集
  local keep = {}
  for k = 1, table.getn(o.pts) do
    if not lcIsOurs(o.pts[k]) then keep[table.getn(keep) + 1] = o.pts[k] end
  end
  if table.getn(keep) == 0 then keep[1] = o.pts[1] end
  -- ★摘掉过我们自建的锚点 ⇒ 抓快照那一刻**就是被撑变形的状态**，那份尺寸是"撑出来的"、不可信
  local dropped = table.getn(keep) < table.getn(o.pts)
  pcall(f.ClearAllPoints, f)
  local okAll = true
  local first = keep[1]
  local ok
  if first.rel then ok = pcall(f.SetPoint, f, first.p, first.rel, first.rp, first.x, first.y)
  else ok = pcall(f.SetPoint, f, first.p, first.x, first.y) end
  if not ok then okAll = false end
  -- 其余锚点只在**点名不同**（同一帧上不冲突）时才补
  for k = 2, table.getn(keep) do
    local p = keep[k]
    if p.p ~= first.p then
      local ok2
      if p.rel then ok2 = pcall(f.SetPoint, f, p.p, p.rel, p.rp, p.x, p.y)
      else ok2 = pcall(f.SetPoint, f, p.p, p.x, p.y) end
      if not ok2 then okAll = false end
    end
  end
  -- 尺寸复位：**优先用快照**；但（a）摘过老锚点（当时已被撑坏）（b）快照尺寸明显越界 ⇒ 一律退回基准
  local w, h = tonumber(o.w), tonumber(o.h)
  if dropped or not (w and h and w >= LC_SIZE_MIN and w <= LC_SIZE_MAX and h >= LC_SIZE_MIN and h <= LC_SIZE_MAX) then
    w, h = LC.refW or LC_NOMINAL_W, LC.refH or LC_NOMINAL_H
  end
  pcall(f.SetWidth, f, w)
  pcall(f.SetHeight, f, h)
  return okAll
end

-- 开窗清账：快照里发现了「我们自建的锚点」⇒ 按快照 + 尺寸复位一次（把变形就地修掉）
local function lcNormalize(f, o)
  if not f or not o or type(o.pts) ~= "table" then return false end
  if not lcHasLegacy(o) then return false end
  lcApply(o, f)
  return true
end

-- 修复（不改开关，只把外观修回来）：清掉一切锚点 → 放客户端自己的那个锚点 → 尺寸按基准复位
local function lcRepair(f)
  f = f or lcFrame()
  if not f then return false, "LootFrame 不存在" end
  local o = LC.orig
  local before
  do
    local l, b = lcLeftBottom(f)
    local _, w, h = lcSizeBad(f)
    before = string.format("%s,%s %.0fx%.0f", tostring(l), tostring(b), tonumber(w) or -1, tonumber(h) or -1)
  end
  if o and o.pts and table.getn(o.pts) > 0 then
    lcApply(o, f)                       -- 原位 + 尺寸（内部会把我们自建的锚点摘掉）
  else
    -- 还没抓过原位（本会话没开过窗）：位置退回客户端默认，尺寸按基准复位
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "TOPLEFT", rawget(_G, "UIParent"), "TOPLEFT", 0, -104)
    pcall(f.SetWidth, f, LC.refW or LC_NOMINAL_W)
    pcall(f.SetHeight, f, LC.refH or LC_NOMINAL_H)
  end
  local l2, b2 = lcLeftBottom(f)
  local w2, h2 = f:GetWidth(), f:GetHeight()
  LC.repairs = LC.repairs + 1
  return true, string.format("修前 %s → 修后 %s,%s %.0fx%.0f", before, tostring(l2), tostring(b2),
    tonumber(w2) or -1, tonumber(h2) or -1)
end

-- ===== 槽位 =====
local function lcSlotInfo(i)
  if type(GetLootSlotInfo) ~= "function" then return nil end
  local ok, tex, nm, cnt, q = pcall(GetLootSlotInfo, i)
  if not ok or nm == nil then return nil end
  local coin = false
  if type(LootSlotIsCoin) == "function" then local ok2, v = pcall(LootSlotIsCoin, i) coin = (ok2 and v) and true or false end
  return { tex = tex, name = tostring(nm), count = cnt, quality = tonumber(q) or 1, coin = coin }
end

local function lcSlotHas(i) return lcSlotInfo(i) ~= nil end

local function lcSlotMap()
  local m = {}
  for i = 1, lcNumButtons() do local s = lcSlotInfo(i) m[i] = s and s.name or nil end
  return m
end

-- 「最小编号的有物品槽」（开窗时的落点；含金币格）
local function lcFirstSlot()
  for i = 1, lcNumButtons() do if lcSlotHas(i) then return i end end
  return nil
end

-- ★「下一件」的唯一算法：先找 i 之后最小编号的有物品槽；没有就绕回最小编号（排除 i 自己）。
--   它天然兼容「压实 / 不压实」两种客户端 —— 差别只在窗要不要搬（见文件头）。
local function lcNextSlot(i)
  local n = lcNumButtons()
  for k = (i or 0) + 1, n do if lcSlotHas(k) then return k end end
  for k = 1, n do if k ~= i and lcSlotHas(k) then return k end end
  return nil
end

-- ===== 摆放（量回自证 + 逐轮修正；★绝不夹取） =====
local function lcPlaceFor(slot)
  local f, b = lcFrame(), lcBtn(slot)
  if not f then return false, "LootFrame 不存在" end
  if not b then return false, "LootButton" .. tostring(slot) .. " 不存在" end
  local cx, cy = lcCursor()
  if not cx then return false, "拿不到光标位置" end
  for round = 1, 3 do
    local px, py = lcCenter(b)
    if not px then return false, "读不到按钮几何" end
    local dx, dy = cx - px, cy - py
    if math.abs(dx) <= 1.5 and math.abs(dy) <= 1.5 then
      local l, bo = lcLeftBottom(f)
      LC.hold = { exp = lcNow() + LC_HOLD_SEC, x = l, y = bo }
      return true, string.format("第 %d 轮收敛", round)
    end
    local nx, ny = lcLeftBottom(f)
    if not nx then return false, "读不到窗几何" end
    if not lcMoveTo(f, nx + dx, ny + dy) then return false, "平移失败（锚点读不到/写不进）" end
  end
  local px, py = lcCenter(b)
  if px and math.abs(cx - px) <= 2 and math.abs(cy - py) <= 2 then
    local l, bo = lcLeftBottom(f)
    LC.hold = { exp = lcNow() + LC_HOLD_SEC, x = l, y = bo }
    return true, "三轮后收敛"
  end
  return false, "三轮没收敛（坐标系/缩放不一致，或客户端在跟我们抢位置）"
end

-- 有界重申：客户端若在我们之后又把窗摆回去，就重申一次（窗口一过就彻底放手）
local function lcReassert()
  local h = LC.hold
  if not h then return end
  if lcNow() > (h.exp or 0) then LC.hold = nil return end
  local f = lcFrame()
  if not lcShown(f) then LC.hold = nil return end
  -- 顺手尺寸自检：被撑变形就修（**有界**：一次开窗最多修一次，不跟客户端来回拉锯）
  if not LC.repairedOpen then
    local bad, w, hh = lcSizeBad(f)
    if bad then
      LC.repairedOpen = true
      local okR, whyR = lcRepair(f)
      if okR then
        lcSay(L("LC_SIZE_FIXED", tostring(w) .. "x" .. tostring(hh), tostring(whyR)))
        lcMoveTo(f, h.x, h.y)   -- 修完再贴回目标位
      else
        lcSay(L("LC_SIZE_BAD", tostring(w) .. "x" .. tostring(hh), tostring(whyR)))
      end
    end
  end
  local l, b = lcLeftBottom(f)
  if not l then return end
  if h.x and (math.abs(l - h.x) > 1 or math.abs(b - (h.y or 0)) > 1) then
    lcMoveTo(f, h.x, h.y)
    LC.reasserts = LC.reasserts + 1
  end
end

-- 跟随档：窗跟着光标走（只在窗开着时，每 LC_FOLLOW_GAP 拍一次；小位移不搬）
local function lcFollowStep()
  if not lcFollowOn() then return end
  local f = lcFrame()
  if not lcShown(f) then return end
  local now = lcNow()
  if now - (LC.lastFollow or 0) < LC_FOLLOW_GAP then return end
  LC.lastFollow = now
  local b = LC.slot and lcBtn(LC.slot)
  if not b then return end
  local cx, cy = lcCursor()
  local px, py = lcCenter(b)
  if not (cx and px) then return end
  local dx, dy = cx - px, cy - py
  if math.abs(dx) < LC_FOLLOW_MIN and math.abs(dy) < LC_FOLLOW_MIN then return end
  local l, bo = lcLeftBottom(f)
  if not l then return end
  if lcMoveTo(f, l + dx, bo + dy) then
    LC.hold = { exp = lcNow() + LC_HOLD_SEC, x = l + dx, y = bo + dy }
  end
end

-- ===== 品质描边（1.75.63：由「右下角一块方块」改成**沿整格外框描一圈品质色**）=====
-- ★四条边各一块纯色纹理（`WHITE8X8` + `SetVertexColor`）：上/下用**两端锚点**拉满宽、左/右拉满高，
--   厚度由 `LC_EDGE_PX` 定 ⇒ 合起来就是「这一格被品质色描了边」。★**白装/灰装不描**（`LC_EDGE_MIN_Q`）。
-- ★贴图口必须**读回自证**（本项目判据：贴图静默失败是常态）⇒ 每轮记「贴上几格 / 读回为空几格」。
-- ★只改粗细/内缩就改那两个常量，**别在别处硬写数值**。
local function lcMarkNew(b, side)
  if type(b.CreateTexture) ~= "function" then return nil end
  local ok, t = pcall(b.CreateTexture, b, nil, "OVERLAY")
  if not (ok and t) then return nil end
  pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8")
  if type(t.SetDrawLayer) == "function" then pcall(t.SetDrawLayer, t, "OVERLAY", 7) end
  local e, i = LC_EDGE_PX, LC_EDGE_INSET
  if side == 1 then            -- 上边
    pcall(t.SetPoint, t, "TOPLEFT", b, "TOPLEFT", i, -i)
    pcall(t.SetPoint, t, "TOPRIGHT", b, "TOPRIGHT", -i, -i)
    pcall(t.SetHeight, t, e)
  elseif side == 2 then        -- 下边
    pcall(t.SetPoint, t, "BOTTOMLEFT", b, "BOTTOMLEFT", i, i)
    pcall(t.SetPoint, t, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -i, i)
    pcall(t.SetHeight, t, e)
  elseif side == 3 then        -- 左边
    pcall(t.SetPoint, t, "TOPLEFT", b, "TOPLEFT", i, -i)
    pcall(t.SetPoint, t, "BOTTOMLEFT", b, "BOTTOMLEFT", i, i)
    pcall(t.SetWidth, t, e)
  else                         -- 右边
    pcall(t.SetPoint, t, "TOPRIGHT", b, "TOPRIGHT", -i, -i)
    pcall(t.SetPoint, t, "BOTTOMRIGHT", b, "BOTTOMRIGHT", -i, i)
    pcall(t.SetWidth, t, e)
  end
  pcall(t.Hide, t)
  return t
end

-- 懒建 + 复用（一条边建不出来就**整格放弃**：宁可不画，也不画半圈）
local function lcMarkEnsure(b, i)
  local g = LC.marks[i]
  if type(g) == "table" then return g end
  local t = {}
  for side = 1, 4 do
    t[side] = lcMarkNew(b, side)
    if not t[side] then return nil end
  end
  LC.marks[i] = t
  return t
end

local function lcMarkHide(g)
  if type(g) ~= "table" then return end
  for k = 1, table.getn(g) do
    local t = g[k]
    if t then pcall(t.Hide, t) end
  end
end

local function lcMarksUpdate()
  local on = lcMarksOn() and EVAL_LC_ENABLED()
  local shown, blank = 0, 0
  for i = 1, lcNumButtons() do
    local b = lcBtn(i)
    if b then
      if not on then
        lcMarkHide(LC.marks[i])
      else
        local g = lcMarkEnsure(b, i)
        local s = nil
        if g then s = lcSlotInfo(i) end
        -- ★★★品质门槛（用户：「只对普通以上的稀有度染色.普通灰色这种白的的不需要高亮」）：
        --   白装/灰装不描；**金币例外**（`s.coin` 永远金色 —— 它不是稀有度档）
        local q = s and (tonumber(s.quality) or 0) or 0
        local want = s and (s.coin or q >= LC_EDGE_MIN_Q) or false
        if not g then
          blank = blank + 1                     -- 建不出纹理：如实计入（下一轮还会再试）
        elseif want then
          local c = s.coin and LC_COIN_COLOR or (LC_QCOLOR[s.quality + 1] or LC_QCOLOR[1])
          for k = 1, table.getn(g) do
            pcall(g[k].SetVertexColor, g[k], c[1], c[2], c[3], 1)
            pcall(g[k].Show, g[k])
          end
          shown = shown + 1
          -- ★读回自证只看**上边那一条**：四条边是同一轮、同一个口建出来的，一条能读回就说明贴图口通
          local t1 = g[1]
          if type(t1.GetTexture) == "function" then
            local ok3, read = pcall(t1.GetTexture, t1)
            if not (ok3 and read and tostring(read) ~= "") then blank = blank + 1 end
          end
        else
          lcMarkHide(g)
        end
      end
    end
  end
  LC.marksShown, LC.marksBlank = shown, blank
end

local function lcMarksClear()
  for i = 1, table.getn(LC.marks) do
    lcMarkHide(LC.marks[i])
  end
end

-- ===== 点击包装（★挂 OnClick 的理由见文件头；先跑原生、再搬窗） =====
local function lcAdvanceAfterClick(i)
  local nextSlot = lcNextSlot(i)
  if LC.compact == true then
    -- 压实档：下一件会**原地**滑进同一格 ⇒ 不搬窗（光标底下就是它）
    LC.slot = i
    LC.lastVerdict = L("LC_ADVANCE_SAME", i)
    lcSay(LC.lastVerdict)
    return
  end
  if not nextSlot then
    LC.lastVerdict = L("LC_ADVANCE_END", i)
    lcSay(LC.lastVerdict)
    return
  end
  local ok, why = lcPlaceFor(nextSlot)
  if ok then
    LC.slot = nextSlot
    LC.placed = LC.placed + 1
    LC.lastVerdict = L("LC_ADVANCE", i, nextSlot)
  else
    LC.failed = LC.failed + 1
    LC.lastVerdict = L("LC_PLACE_FAIL", nextSlot, tostring(why))
  end
  lcSay(LC.lastVerdict)
  lcMarksUpdate()
end

local function lcOnClicked(i)
  if not EVAL_LC_ENABLED() then return end
  if not lcShown() then return end
  local mouse = arg1
  LC.clicked = LC.clicked + 1
  LC.lastClickSlot = i
  LC.before = lcSlotMap()
  if not (mouse == nil or mouse == "LeftButton") then
    LC.lastVerdict = L("LC_CLICK_NOTLEFT", tostring(mouse))
    return
  end
  local okP, errP = pcall(lcAdvanceAfterClick, i)
  if not okP then
    LC.failed = LC.failed + 1
    LC.lastVerdict = "换下一件出错：" .. tostring(errP)
    lcSay(LC.lastVerdict)
  end
end

local function lcUnhook()
  local n = 0
  for i = 1, lcNumButtons() do
    local b = lcBtn(i)
    if b and LC.wrappers[i] then
      -- ★按**身份**复原：只有当前挂的还是我们装的那个才换回去（期间被别人套过就不许冲掉别人的）
      local cur = nil
      if type(b.GetScript) == "function" then local ok, v = pcall(b.GetScript, b, "OnClick") cur = ok and v or nil end
      if cur == LC.wrappers[i] then
        pcall(b.SetScript, b, "OnClick", LC.wrapped[i])
        n = n + 1
      end
      LC.wrappers[i], LC.wrapped[i] = nil, nil
    end
  end
  LC.hooked = false
  return n
end

local function lcHook()
  if not EVAL_LC_ENABLED() then return 0 end
  local n = 0
  for i = 1, lcNumButtons() do
    local b = lcBtn(i)
    if b and type(b.SetScript) == "function" and not LC.wrappers[i] then
      local old = nil
      if type(b.GetScript) == "function" then local ok, v = pcall(b.GetScript, b, "OnClick") old = ok and v or nil end
      local wrap = function()
        -- ① 原生处理体**先跑**（拾取请求照原样发出；零参数 = 原生脚本的调用约定）
        if type(old) == "function" then pcall(old) end
        -- ② 再「立刻」换下一件（不等服务器回话）
        local ok, err = pcall(lcOnClicked, i)
        if not ok then LC.failed = LC.failed + 1 LC.lastVerdict = "点击处理出错：" .. tostring(err) end
      end
      local okSet = pcall(b.SetScript, b, "OnClick", wrap)
      if okSet then
        LC.wrappers[i], LC.wrapped[i], n = wrap, old, n + 1
      end
    end
  end
  LC.hooked = (n > 0) or LC.hooked
  return n
end

-- ===== 事件 =====
local function lcLearnCompact(cleared)
  if LC.compact ~= nil then return end
  local i = tonumber(LC.lastClickSlot)
  local a = LC.before
  if not i or type(a) ~= "table" or not a[i + 1] then return end
  local b = lcSlotMap()
  if b[i] == a[i + 1] then
    LC.compact = true
    lcSay(L("LC_COMPACT_LEARNED"))
    LC.slot = i
    local ok = lcPlaceFor(i)
    if not ok then LC.failed = LC.failed + 1 end
  elseif b[i + 1] == a[i + 1] then
    LC.compact = false
  end
end

-- 贴上目标格（开窗那一拍 + 有界重试共用；成功返回 true）
local function lcAttemptPlace()
  local slot = lcFirstSlot()
  if not slot then return false end
  local ok, why = lcPlaceFor(slot)
  if ok then
    LC.slot, LC.placed = slot, LC.placed + 1
    lcSay(L("LC_OPEN_MOVED", slot, lcCountWrapped()))
  else
    LC.failed = LC.failed + 1
    LC.slot = nil
    lcSay(L("LC_PLACE_FAIL", slot, tostring(why)))
  end
  return true
end

-- 当前锚点个数（正常只该有 1 个；>1 = 老构建留下的「我们自己的 BOTTOMLEFT + 客户端的 TOPLEFT」= 撑变形的来源）
local function lcPointCount(f)
  local n = 0
  for k = 1, 4 do
    local ok, p = pcall(f.GetPoint, f, k)
    if not (ok and p) then break end
    n = n + 1
  end
  return n
end

local function lcOnOpen()
  if not EVAL_LC_ENABLED() then return end
  local f = lcFrame()
  if not f then lcSay(L("LC_NOFRAME")) return end
  -- ★原位只在**开窗这一刻**抓一次（客户端自己刚摆好）；抓第二次就会把我们摆的位置当原值
  LC.orig = lcSnap(f, 4)
  LC.before, LC.lastClickSlot = nil, nil
  LC.repairedOpen = false
  -- ★只有「没有被老锚点污染」的那份读数才配当尺寸基准（撑坏的尺寸当基准 ⇒ 以后再也认不出变形）
  local legacySnap = lcHasLegacy(LC.orig)
  if not legacySnap then lcRememberSize(LC.orig.w, LC.orig.h) end
  -- ★开窗清账（都只做一次、都自带读回）：① 老构建留下的多锚点 ⇒ 收回客户端那一个（撑变形就是这么来的）；
  --   ② 尺寸已经被撑坏 ⇒ 按基准复位。此后我们**只平移**，永不再制造多锚点。
  local nPts = lcPointCount(f)
  if lcNormalize(f, LC.orig) then
    LC.normalized = LC.normalized + 1
    lcSay(L("LC_NORMALIZED", nPts))
  end
  local bad, w, hh = lcSizeBad(f)
  if bad then
    local okR, whyR = lcRepair(f)
    LC.repairedOpen = true
    if okR then lcSay(L("LC_SIZE_FIXED", tostring(w) .. "x" .. tostring(hh), tostring(whyR)))
    else lcSay(L("LC_SIZE_BAD", tostring(w) .. "x" .. tostring(hh), tostring(whyR))) end
  end
  lcHook()                              -- 幂等：包过就不重包（每次开窗再确认一次）
  lcMarksUpdate()
  if lcAttemptPlace() then
    LC.pending = nil
    return
  end
  -- ★有界重试：开窗那一拍若还读不到槽位（客户端可能稍后才填），0.6 秒内每帧再试一次
  --   （不重试 = 读不到就永远不动 = 用户眼里的「静默失效」，本项目最恨这一族）
  LC.slot = nil
  LC.pending = { exp = lcNow() + LC_EMPTY_SEC }
  lcSay(L("LC_EMPTY_RETRY", LC_EMPTY_SEC))
end

local function lcOnClose()
  LC.hold, LC.slot, LC.before, LC.lastClickSlot, LC.pending = nil, nil, nil, nil, nil
  lcMarksClear()
end

local function lcOnEvent()
  local ev = tostring(event or "?")
  if ev == "LOOT_OPENED" then
    local ok, err = pcall(lcOnOpen)
    if not ok then lcSay("开窗处理出错：" .. tostring(err)) end
  elseif ev == "LOOT_SLOT_CLEARED" then
    local ok, err = pcall(function() lcLearnCompact(tonumber(arg1)) lcMarksUpdate() end)
    if not ok then lcSay("清空槽处理出错：" .. tostring(err)) end
  elseif ev == "LOOT_CLOSED" then
    pcall(lcOnClose)
  end
end

local function lcTick()
  if not EVAL_LC_ENABLED() then return end  -- 双保险（关掉时 OnUpdate 已被摘）
  local p = LC.pending
  if p then
    if lcNow() > (p.exp or 0) then
      LC.pending = nil
      if not LC.slot then lcSay(L("LC_NO_ITEM")) end       -- 窗口过了还是没有 ⇒ 如实说一次，不再纠缠
    elseif lcShown() then
      if lcAttemptPlace() then LC.pending = nil end
    else
      LC.pending = nil
    end
  end
  lcReassert()
  lcFollowStep()
end

-- ===== 安装 / 卸载 =====
local function lcEnsureFrame()
  if LC.evF then return LC.evF end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame", "EH_LC_EV", rawget(_G, "UIParent"))
  if not f then return nil end
  LC.evF = f
  return f
end

local function lcInstall()
  local f = lcEnsureFrame()
  if not f then return false end
  for _, ev in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do
    if type(f.RegisterEvent) == "function" then pcall(f.RegisterEvent, f, ev) end
  end
  if type(f.SetScript) == "function" then
    pcall(f.SetScript, f, "OnEvent", lcOnEvent)   -- ★零形参：事件名/参数读全局 event/arg1
    pcall(f.SetScript, f, "OnUpdate", lcTick)     -- ★零形参
  end
  LC.built = true
  lcHook()                           -- ★装的时候就包上：万一开关是在「窗已经开着」时打开的，不等下一次 LOOT_OPENED
  if lcShown() then lcOnOpen() end   -- 开关在开窗之后才打开 ⇒ 当场贴一次
  return true
end

-- 关功能：**先摘包装再还原位置**（顺序即判据：先让我们的手离开，再谈把东西还回去）
local function lcTeardown()
  local f = LC.evF
  if f then
    if type(f.SetScript) == "function" then pcall(f.SetScript, f, "OnUpdate", nil) end
    if type(f.UnregisterEvent) == "function" then
      for _, ev in ipairs({ "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED" }) do pcall(f.UnregisterEvent, f, ev) end
    end
  end
  local n = lcUnhook()
  lcMarksClear()
  LC.hold = nil
  LC.pending = nil
  local restored = false
  if LC.orig then
    local ff = lcFrame()
    restored = lcApply(LC.orig, ff)
    LC.orig = nil
  end
  LC.built, LC.slot, LC.before, LC.lastClickSlot = false, nil, nil, nil
  lcMarksUpdate()   -- 再走一遍：确保角标一个不留
  return n, restored
end

function EVAL_LC_SET(on)
  on = on and true or false
  local tb = lcTb()
  if type(tb) ~= "table" then
    lcSay(L("LC_NO_CFG"))
    return false
  end
  tb.lootCursor = on
  if on then
    local ok = lcInstall()
    if ok then lcSay(L("LC_ON_MSG")) else lcSay(L("LC_ON_FAIL")) end
    return ok
  end
  local n, restored = lcTeardown()
  if restored then
    local l, b = lcLeftBottom(lcFrame())
    lcSay(L("LC_OFF_MSG", n, tostring(l) .. "," .. tostring(b)))
  else
    lcSay(L("LC_OFF_MSG_NOPOS", n))
  end
  return true
end

function EVAL_LC_INSTALL()
  if not EVAL_LC_ENABLED() then return false end
  return lcInstall()
end

-- ===== 命令：/eh go 拾取 [...] =====
local function lcStateLine()
  local comp = (LC.compact == nil) and L("LC_COMPACT_UNKNOWN") or (LC.compact and L("LC_COMPACT_YES") or L("LC_COMPACT_NO"))
  return L("LC_STATE", EVAL_LC_ENABLED() and L("SH_ON") or L("SH_OFF"),
    lcFollowOn() and L("SH_ON") or L("SH_OFF"),
    lcMarksOn() and L("SH_ON") or L("SH_OFF"),
    comp, LC.placed, LC.clicked)
end

-- 探针：把「现在到底什么样」摊开（不改任何状态）
local function lcProbe()
  lcSay(L("LC_PROBE_TITLE", LC_OUT_MAX, table.getn(LC.out)))
  local f = lcFrame()
  if not f then lcSay("LootFrame 不存在（本客户端没有这个帧？）") return end
  local l, b = lcLeftBottom(f)
  local okw, w, h = pcall(function() return f:GetWidth(), f:GetHeight() end)
  local badSize = lcSizeBad(f)
  lcSay(string.format("LootFrame：显=%s 实测左下=%s,%s ｜ 尺寸=%sx%s（基准 %sx%s ⇒ %s）｜ 锚点数=%d ｜ 窗内按钮数=%d ｜ 事件帧=%s",
    lcShown(f) and "1" or "0", tostring(l), tostring(b),
    tostring(okw and w or "?"), tostring(okw and h or "?"),
    tostring(LC.refW or LC_NOMINAL_W), tostring(LC.refH or LC_NOMINAL_H),
    badSize and "**异常（会被撑变形，跑 /eh go 拾取 修复）**" or "正常",
    lcPointCount(f), lcNumButtons(), LC.evF and "在" or "未建"))
  local cx, cy = lcCursor()
  lcSay(string.format("光标(UI)=%s,%s ｜ 当前目标格=%s ｜ 压实结论=%s ｜ 已包装 %d 个 · 重申 %d 次 · 对准 %d / 点 %d / 失败 %d",
    tostring(cx), tostring(cy), tostring(LC.slot),
    (LC.compact == nil) and "?" or tostring(LC.compact), lcCountWrapped(), LC.reasserts,
    LC.placed, LC.clicked, LC.failed))
  lcSay(string.format("品质描边：贴上 %d 格（每格 4 条边）｜ 贴图读回为空 %d 格（>0 ⇒ 这个客户端的贴图口要换写法）",
    tonumber(LC.marksShown) or 0, tonumber(LC.marksBlank) or 0))
  lcSay(string.format("搬窗手法：就地平移（绝不 ClearAllPoints）｜ 开窗清账 %d 次 ｜ 尺寸修复 %d 次 ｜ 重申 %d 次",
    LC.normalized or 0, LC.repairs or 0, LC.reasserts or 0))
  for i = 1, lcNumButtons() do
    local s = lcSlotInfo(i)
    local px, py = lcCenter(lcBtn(i))
    local under = ""
    if cx and px then
      local bb = lcBtn(i)
      local ok2, bl, bo, bw, bh = pcall(function() return bb:GetLeft(), bb:GetBottom(), bb:GetWidth(), bb:GetHeight() end)
      if ok2 and tonumber(bl) then
        under = ((cx >= bl and cx <= bl + (tonumber(bw) or 0)) and (cy >= bo and cy <= bo + (tonumber(bh) or 0)))
          and "  ★光标就在这一格上" or ""
      end
    end
    lcSay(string.format("  slot%d：%s ｜ 按钮中心=%s,%s%s", i,
      s and (s.name .. (s.coin and "（金币）" or "") .. " x" .. tostring(s.count) .. " 品质" .. tostring(s.quality)) or "空",
      tostring(px), tostring(py), under))
  end
  lcSay("最近一条判定：" .. tostring(LC.lastVerdict))
  -- ★「下一件」链（把唯一算法 `lcNextSlot` 挂成活口 —— 见文件末尾 `EVAL_LC_TEST_NEXT` 的注释）：
  --   真机上一个问题「点完这件之后窗为什么贴到那一格」看这一行就够了。
  do
    local n, chain = lcNumButtons(), {}
    for i = 1, n do
      if lcSlotInfo(i) then
        local nx = lcNextSlot(i)
        chain[table.getn(chain) + 1] = "slot" .. i .. "→" .. (nx and ("slot" .. nx) or "无")
      end
    end
    lcSay("下一件链（`lcNextSlot`）：" .. (table.getn(chain) > 0 and table.concat(chain, "  ") or "（当前一格有物品的都没有）"))
  end
end

local function lcSaveProbe()
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) ~= "table" then cfg = {} rawset(_G, "EVAL_HELP_CONFIG", cfg) end
  local box = { out = {} }
  box.at = tostring(lcNow())
  lcProbe()
  for i = 1, table.getn(LC.out) do box.out[i] = LC.out[i] end
  box.state = EVAL_LC_TEST_STATE()
  cfg.lcProbe = box
  lcSay(L("LC_SAVED", LC_OUT_MAX))
end

function EVAL_LC_CMD(msg)
  local rest = string.match(tostring(msg or ""), "^go 拾取%s*(.-)%s*$")
  if rest == nil then rest = string.match(tostring(msg or ""), "^go lootcursor%s*(.-)%s*$") end
  if rest == nil then return false end
  if rest == "开" or rest == "on" then
    EVAL_LC_SET(true)
    lcSay(lcStateLine())
  elseif rest == "关" or rest == "off" then
    EVAL_LC_SET(false)
  elseif rest == "跟随" or rest == "follow" then
    local v = not lcFollowOn()
    lcSetFollow(v)
    lcSay(L("LC_STATE", EVAL_LC_ENABLED() and L("SH_ON") or L("SH_OFF"), v and L("SH_ON") or L("SH_OFF"),
      lcMarksOn() and L("SH_ON") or L("SH_OFF"), "-", LC.placed, LC.clicked))
  elseif rest == "描边" or rest == "edge" or rest == "角标" or rest == "marks" then
    -- ★1.75.63 起叫「品质描边」；旧词（角标 / marks）继续认 —— 用户记着旧名字，删掉就是「命令静默失效」
    local v = not lcMarksOn()
    lcSetMarks(v)
    lcMarksUpdate()
    lcSay(L("LC_STATE", EVAL_LC_ENABLED() and L("SH_ON") or L("SH_OFF"), lcFollowOn() and L("SH_ON") or L("SH_OFF"),
      v and L("SH_ON") or L("SH_OFF"), "-", LC.placed, LC.clicked))
  elseif rest == "探针" or rest == "probe" then
    lcProbe()
  elseif rest == "修复" or rest == "fix" then
    local ok, why = lcRepair(lcFrame())
    if ok then
      lcSay(L("LC_REPAIRED", tostring(why)))
      -- 修完顺手贴回当前目标格（有的话）
      if LC.slot then lcPlaceFor(LC.slot) end
    else
      lcSay(L("LC_REPAIR_FAIL", tostring(why)))
    end
  elseif rest == "存档" or rest == "save" then
    lcSaveProbe()
  elseif rest == "清" or rest == "clear" then
    LC.out = {}
    local cfg = rawget(_G, "EVAL_HELP_CONFIG")
    if type(cfg) == "table" then cfg.lcProbe = nil end
    lcSay("拾取贴手读数环已清空（存档里那份也要 /reload 才消失）")
  elseif rest == "" or rest == "状态" then
    lcSay(lcStateLine())
    -- ★活口自查（用户报「工具箱里点不到这一行」时一眼可判）：注册表里那一项**就是**我们的渲染函数吗？
    do
      local rows = rawget(_G, "EVAL_TB_MOD_ROWS")
      local mine = EVAL_LC_TEST_ROW()
      lcSay("工具箱模块行："
        .. ((type(rows) == "table" and type(mine) == "function" and rows["lootCursor"] == mine)
          and "已登记（`EVAL_TB_MOD_ROWS.lootCursor` = 本模块渲染函数）" or "**未登记**（工具箱里会点不到这一行）"))
    end
    lcSay("用法：" .. L("LC_USAGE"))
  else
    lcSay("未知子命令 ⇒ " .. L("LC_USAGE"))
  end
  return true
end

-- ===== 工具箱模块行（嵌入点被调方；Toolbox 侧只有一行数据） =====
local function lcMenuItems()
  local items = { L("LC_OPT_FOLLOW"), L("LC_OPT_MARKS") }
  local sel = {}
  if lcFollowOn() then sel[1] = true end
  if lcMarksOn() then sel[2] = true end
  return items, sel
end

local lcRow = function(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return EVAL_LC_ENABLED() end
  r.set = function(v) EVAL_LC_SET(v and true or false) end
  r.extra:Hide()                       -- ★配置项只在 [设置] 的悬停里显示，行上不重复
  r.add.text:SetText(L("TB_LDDRAG_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, 320)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_LOOTCURSOR_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, L("LC_SET_TIP"), 0.88, 0.88, 0.88)
    pcall(tip.AddLine, tip, lcStateLine(), 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then
      lcSay("打开拾取贴手设置失败：下拉控件未载入")
      return
    end
    local items, sel = lcMenuItems()
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      if pi == 1 then lcSetFollow(on == true) end
      if pi == 2 then lcSetMarks(on == true) end
      lcMarksUpdate()
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = sel })
  end)
  return true
end

local LC_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(LC_TB_ROWS) ~= "table" then
  LC_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", LC_TB_ROWS)
end
LC_TB_ROWS["lootCursor"] = lcRow

-- ===== 读值口（诊断/取证；★不复刻逻辑：状态直给真实字段，动作走真实入口） =====
function EVAL_LC_TEST_STATE()
  return {
    on = EVAL_LC_ENABLED(), follow = lcFollowOn(), marks = lcMarksOn(),
    compact = LC.compact, slot = LC.slot, built = LC.built, hooked = lcCountWrapped(),
    placed = LC.placed, clicked = LC.clicked, failed = LC.failed, reasserts = LC.reasserts,
    repairs = LC.repairs, normalized = LC.normalized, refW = LC.refW, refH = LC.refH,
    marksShown = LC.marksShown, marksBlank = LC.marksBlank,
    verdict = LC.lastVerdict, hasOrig = LC.orig and true or false,
  }
end
-- ★诊断口：忘掉「压实」结论（下次点击重新自证）。真机上只有一个用途 = 想让客户端重新自证一次；
--   离线 harness 靠它把「压实 / 不压实」两种客户端都验一遍（同一进程里两条路都要跑）。
function EVAL_LC_TEST_FORGET_COMPACT() LC.compact = nil return true end

-- ★★★诊断口：「下一件」唯一算法 `lcNextSlot(i)` 的对外出口（1.75.34 的孤儿清理**误删过一次**：
--   判据①只看 `.lua` 零引用，而它的调用方在 `tmp/lootcursor_harness.js`（.js）里 ⇒ 被当成孤儿删掉，
--   于是那个 harness 自 1.75.34 起一直崩（`attempt to call a nil value (global 'EVAL_LC_TEST_NEXT')`）。
--   ★按项目纪律：读值口**要么挂到命令上是活口，要么别加** —— 所以它现在**被 `lcProbe()` 调用**：
--   `/eh go 拾取 探针` 会打一行「下一件链」= 真机上「点这一件之后窗会贴到哪一格」的直接答案。
function EVAL_LC_TEST_NEXT(i)
  return lcNextSlot(tonumber(i) or 0)
end

-- ★★同族诊断口（同一个孤儿清理误删的第二个）：工具箱**模块行渲染函数**本身。
--   用途 = 真机自查「工具箱那一行登记上没有」（`/eh go 拾取 状态` 里拿它与注册表比对）。
function EVAL_LC_TEST_ROW()
  return lcRow
end
