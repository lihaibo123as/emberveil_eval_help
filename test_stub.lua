-- fengari 测试桩：模拟本客户端 WoW API 环境（Lua 5.1 垫片 + UI mock + 战斗 API）
table.getn = table.getn or function(t) return #t end
math.mod = math.mod or math.fmod
getglobal = getglobal or function(n) return _G[n] end

TEST = { used = {}, targetClass = "WARRIOR", hasTarget = true, slotNames = { [1] = "致死打击", [2] = "冲锋" }, debuffs = {}, buffs = {} }

local function newMock()
  local m = {}
  -- ★★★1.72.4 桩保真：真客户端里 CreateFrame 出来的帧**默认就是显示的**（除非显式 Hide）。
  --   原桩初始值写 false → 于是「没调 Hide 也断言 IsShown()==false」这类断言**恒真通过**：
  --   它不仅不检查，还会把「入口被藏起来」的真回归掩盖成绿灯（1.72.4 实测：把默认隐藏写进代码后，
  --   去掉那两行 Hide 的变异竟然 SURVIVED；用户随后当场报「等级配置没显示」= 真回归被桩漏掉）。
  --   ★判据：桩对「默认状态」必须与客户端一致——状态型桩错的不是「没状态」，而是**默认值反了**。
  local shown, scripts, texts = true, {}, {}
  -- ★★★1.73.5 桩保真：真客户端的 **EditBox 里 SetText 会再触发 OnTextChanged**（1.73.1 踩过的坑：
  --   回写输入框不比对 → 递归）。旧桩不触发 → 「无条件回写」的变异**存活**，
  --   而我们那条「回写不会递归刷新」的断言其实**永远验不到东西**（桩太宽松 = 断言失明，本项目老坑）。
  --   ★只对 EditBox 生效（其余控件 SetText 不触发任何脚本），并由下方 CreateFrame 打开开关。
  local isEditBox, txtDepth = false, 0
  local w, h = nil, nil -- ★1.70.46 帧必须记得自己的尺寸（见下方 SetWidth/SetHeight 说明）
  local layer, level = nil, nil -- ★1.71.2 层（见下方 SetDrawLayer 说明）
  local focused = false -- ★1.71.2（第七轮）焦点状态（见下方 SetFocus 说明）
  local point, relTo, relPoint = nil, nil, nil -- ★1.71.2 锚点语义（见下方 SetPoint 说明）
  -- ★★★1.71.2（第二十轮）**x, y 必须是每个 mock 自己的局部变量**。
  --   原桩漏了这一行 → SetPoint 里的 `x, y = a4, a5` 实际上是给**全局** x/y 赋值，
  --   GetPoint/GetLeft/GetTop 读的也是那两个全局 → **所有帧共享最后一次写入的位置**！
  --   后果：任何「比较两个帧的几何」的断言都在读同一个值（=最后一次 SetPoint 的那个），
  --     恒真或恒假，等于没测（本轮实测：五条状态条全读到 -4，那其实是最后画的目标距离文字的偏移）。
  --   ★这与「桩太宽松 → 断言失明」是同一族，只是更隐蔽：**它让断言看起来在读数，其实读的是别人写的数**。
  --   （此前 IO 窗钩子注释里记着「登记 x=14、GetPoint 却回 0」，根因就是这里。）
  local x, y = nil, nil
  local special = {
    -- ★1.70.25：帧必须真的有显隐状态。原桩的 Show/Hide 是空操作、IsShown 恒 nil，
    --   导致「点选后面板是否仍打开」这类行为断言永远是 false —— 断言失效而不自知。
    --   （这正是「断言绿≠假设对」的又一例：桩过于宽松会把真实回归掩盖成假失败/假通过。）
    Show = function() shown = true end,
    Hide = function() shown = false end,
    IsShown = function() return shown end,
    IsVisible = function() return shown end,
    SetScript = function(_, ev, fn) scripts[ev] = fn end,
    GetScript = function(_, ev) return scripts[ev] end,
    SetText = function(_, t)
      texts.t = t
      -- ★计数：让「回写有没有变成一串递归」可被判据直接读到（递归会被 pcall 吞掉，光看报错看不出来）
      if isEditBox then TEST.ebSetTextCalls = (TEST.ebSetTextCalls or 0) + 1 end
      if isEditBox and type(scripts.OnTextChanged) == "function" then
        txtDepth = txtDepth + 1
        -- ★递归闸门：真客户端上「无条件回写」会无限递归；这里到 50 层就**如实报错**，
        --   免得测试卡死（报错本身就是「这条判据被违反了」的最强证据）。
        if txtDepth > 50 then txtDepth = 0 error("EditBox SetText 递归超过 50 层（真客户端会无限递归）") end
        scripts.OnTextChanged()
        txtDepth = txtDepth - 1
      end
    end,
    GetText = function() return texts.t end,
    -- ★1.70.46：桩必须记得尺寸。原桩把 SetWidth/SetHeight 当空操作、GetWidth/GetHeight 恒 nil，
    --   于是「窗口高度根本没被设置」这类事故在测试里**完全不可见**——用户实测：技能编辑窗高得离谱，
    --   根因是 `seUI.W = W -- 注释 root:SetHeight(H)` 里 SetHeight 被行尾注释吞掉。
    --   当时宽度有断言、高度一条都没有 → 只漏了高度。桩越接近真实，这类事故越早暴露。
    SetWidth = function(_, v) w = v end,
    SetHeight = function(_, v) h = v end,
    GetWidth = function() return w end,
    GetHeight = function() return h end,
    -- ★1.71.2：桩必须记录锚点。原桩把 SetPoint/ClearAllPoints 当空操作、GetLeft 返回 nil，
    --   于是「搜索框被挪到屏幕外」这种**位置语义**的修复在测试里完全不可见——
    --   而这次的真 bug 恰恰是一个位置问题（EditBox 用 Hide() 后仍会画底条，
    --   修法改为「挪出可视区」，用户截图：所有弹窗上部一条看不见的黑块）。
    --   x,y 允许为 nil（("CENTER") 这类只有锚点名的调用），GetLeft 保持返回数字或 nil。
    -- ★1.71.2：桩必须记录「层」。本客户端 EditBox 的底条画在高于 BACKGROUND 的层，
    --   用户在**别的弹窗**顶部看到一条黑块就是这个原因；桩若不记录，SetDrawLayer 写错也测不出来。
    SetDrawLayer = function(_, l) layer = l end,
    GetDrawLayer = function() return layer end,
    SetFrameLevel = function(_, l) level = l end,
    GetFrameLevel = function() return level end,
    -- ★1.73.31 桩保真：鼠标开关要能读回来（「弹窗点击不到」的一半原因是它没吃掉落在自己身上的点击）
    EnableMouse = function(self, v) rawset(self, "__mouse", v and true or false) end,
    IsMouseEnabled = function(self) return rawget(self, "__mouse") and true or false end,
    ClearAllPoints = function() x = nil y = nil end,
    -- ★1.71.2 桩必须同时记住**锚点语义**（point/relPoint/relTo），不能只记偏移量：
    --   用户截图事故是「按钮压在小地图左下角」，而判据是**锚到了邻居的哪条边**
    --   （锚 TOPLEFT = 贴左边缘会压进圆里；锚 LEFT = 落在圆外）。只记 x/y 根本表达不了这个差异。
    --   GetPoint 缺失时 newMock 的兜底会返回一个**函数**，pcall 照样成功 →
    --   锚点信息全是假值，几何断言随之失去意义（本轮实测就是这么被误导的）。
    -- ★★★1.71.2 用 **varargs** 按实参个数解析，绝不写死形参个数：
    --   本客户端有两种调用形态 —— SetPoint(point, relTo, relPoint, x, y)（5 参）
    --   与 SetPoint(point) / SetPoint(point, relTo)（2-3 参）。
    --   旧桩写死 6 个形参，遇到 5 参调用时整体**错位一格**：x 收到 relPoint 字符串、
    --   y 收到真正的 x → 所有几何断言读到假值（本轮实测：6 个按钮的 x 全成 0）。
    --   这与「ipairs 遇 nil 即停」是同一类错误：**假定了一种调用形态，而实际有多种**。
    SetPoint = function(_, a1, a2, a3, a4, a5)
      point, relTo, relPoint, x, y = a1, a2, a3, nil, nil
      if a4 ~= nil then x, y = a4, a5 end -- 5 参形态：末两个才是偏移量
      if a3 == nil then relTo, relPoint = nil, nil end
    end,
    GetPoint = function() return point, relTo, relPoint, x, y end,
    GetLeft = function() return x end,
    GetTop = function() return y end,
    -- ★1.71.2 桩必须让几何**自洽**：uiOffscreen 会同时读 Left/Right/Top/Bottom 四个数字，
    --   只提供 Left/Top 时它拿到 nil 去比较 → 直接抛错
    --   （本轮实测：attempt to compare nil with number，且不带行号，极难定位）。
    --   Right/Bottom 由 Left/Top 与宽高推导；桩不模拟真正的锚点解算，但对越界判定足够。
    GetRight = function() if type(x) == "number" and type(w) == "number" then return x + w end return nil end,
    GetBottom = function() if type(y) == "number" and type(h) == "number" then return y - h end return nil end,
    -- ★★★1.71.2（第七轮）**桩必须记录焦点状态**。
    --   事故：条件行的光环格是 EditBox，点击热区（Button）后建、压在它上面，
    --   于是点一下永远拿不到焦点、打不了字——而旧桩**没有任何焦点概念**，
    --   SetFocus 是空操作、HasFocus 恒 nil → 「点击能否聚焦」在测试里**完全不可见**
    --   （本项目第 N 次「桩太宽松 → 真实事故测不出来」，见 CLAUDE.md 该主题的历次发作）。
    --   ★判据：**被测代码读的每一个状态，桩都必须能记住**。
    SetFocus = function() focused = true end,
    ClearFocus = function() focused = false end,
    HasFocus = function() return focused end,
    -- ★1.71.2（第二十轮）纹理/字串必须能反查**所在帧**。
    --   事故：状态条的填充层是否「内缩 1px」只能拿它和**它所在的条**比才看得出，
    --   而旧桩的纹理没有父级 → 断言只能验「偏移是 0」，验不了「高度等于条高 / 满值不留缝」。
    --   ★判据同「桩必须记住被测代码读的每一个状态」：几何断言需要什么，桩就得给什么。
    GetParent = function() return rawget(m, "__parent") end,
    -- ★1.71.3 桩必须记住**纹理路径**：本轮新增「类别图标 / 异常标记」两列，
    --   而旧桩的 SetTexture 走 __index 兜底（返回一个空函数）→ 断言读不到任何路径，
    --   「图标到底画了哪张」在测试里完全不可见（同族教训：桩不记状态 = 断言失明）。
    --   ★只记字符串（uiSolid 走的是 SetTexture(r,g,b) 三数值形态，不记路径）。
    SetTexture = function(_, a1) if type(a1) == "string" then rawset(m, "__tex", a1) end end,
    -- ★1.73.26 桩保真：真客户端纹理有顶点色（SetVertexColor / GetVertexColor）——
    --   原来桩里没有 → 说明「半透明背景」这类判据**根本读不到值**（本项目「桩太宽松 → 断言失明」那一族）。
    SetVertexColor = function(self, r, g, b, a)
      rawset(self, "__vr", r) rawset(self, "__vg", g) rawset(self, "__vb", b) rawset(self, "__va", a)
    end,
    GetVertexColor = function(self)
      return rawget(self, "__vr") or 1, rawget(self, "__vg") or 1, rawget(self, "__vb") or 1, rawget(self, "__va") or 1
    end,
    GetTexture = function() return rawget(m, "__tex") end,
    -- ★1.73.5 CreateFrame 拿到 "EditBox" 类型后调用它，打开「SetText 会再触发 OnTextChanged」的保真开关
    __markEditBox = function() isEditBox = true end,
  }
  setmetatable(m, { __index = function(_, k)
    if special[k] then return special[k] end
    if k == "CreateTexture" or k == "CreateFontString" then
      -- ★1.71.2（第二十轮）子对象要记住**创建它的那个帧**（见上方 GetParent 说明）。
      --   注意用 rawset：__parent 必须是真字段，否则读取时会命中 __index 的「返回函数」兜底。
      return function() local ch = newMock() rawset(ch, "__parent", _) return ch end
    end
    return function() return nil end
  end })
  return m
end
-- ★1.70.39：桩必须记录父级，并模拟「祖先隐藏 → 不派发 OnUpdate」这条本客户端铁律。
--   不加这条，「tick 挂 UIParent 导致地图打开时整个停摆」这个 bug 在测试里完全不可见
--   （旧桩 CreateFrame 直接丢掉 parent，任何父级都长得一样）。
--   这正是「桩太宽松 → 真实回归不可见」的第 N 次发作，见 CLAUDE.md 1.70.25/1.70.32 条。
-- 注意：__parent 必须走 rawset 存成**真字段**。newMock 的 __index 对任何未知键
-- 都返回一个函数（宽容桩的设计），所以直接 m.__parent = x 会被后世读取，
-- 但若键不存在则会拿到函数而不是 nil —— 遍历祖先链时会炸（本轮首版即如此）。
local function newFrame(parent)
  local m = newMock()
  rawset(m, "__parent", parent or UIParent)
  -- ★★★1.73.31 桩保真：真客户端里**子帧的 frame level = 父帧 + 1**，同 strata 内按 level 排先后。
  --   本轮事故（用户：「自动购买的弹窗点击不到」）**正是**这条语义：弹窗只设了 strata、没设 level，
  --   而工具箱行按钮是配置窗的子帧（level 更高）→ 画在弹窗之上、把鼠标吃掉。
  --   桩若不模拟继承，弹窗 level 恒 0、这个 bug 在测试里**根本不存在**（同族：桩太宽松 → 断言失明）。
  local lvl = 1
  if parent and type(parent.GetFrameLevel) == "function" then
    local ok, pl = pcall(parent.GetFrameLevel, parent)
    if ok and type(pl) == "number" then lvl = pl + 1 end
  end
  if type(m.SetFrameLevel) == "function" then pcall(m.SetFrameLevel, m, lvl) end
  return m
end
-- ★1.73.14 造一个「独立 tooltip」：自己的文本 + 自己的 tooltip API（真机里 CreateFrame("GameTooltip", ...) 就是这个）
local function mkTooltipFrame(name)
  -- ★必须是**普通 table**（不能是带元表兜底的 mock）：测试要能靠 `GT.SetUnitBuff = nil` 如实模拟
  --   「这个入口不可用」——带 __index 兜底的 mock 里赋值 nil 会被兜底函数"复活"（真值），
  --   于是「扫描器不可用」这个前提根本建不起来（组 70 / 组 108 都靠它）。
  local f = {}
  rawset(f, "__name", name)
  rawset(f, "GetName", function() return name end)
  rawset(f, "SetOwner", function() end)
  rawset(f, "SetClampedToScreen", function() end)
  rawset(f, "Hide", function() end)
  rawset(f, "Show", function() end)
  rawset(f, "IsShown", function() return false end)
  rawset(f, "ClearLines", function() TEST.curSlot = nil TEST.curDebuff = nil TEST.curBuff = nil end)
  rawset(f, "SetAction", function(_, slot) TEST.curSlot = slot return true end)
  rawset(f, "SetUnitDebuff", function(_, _, i) TEST.curDebuff = i return TEST.debuffs[i] ~= nil end)
  rawset(f, "SetUnitBuff", function(_, _, i) TEST.curBuff = i return TEST.buffs[i] ~= nil end)
  rawset(f, "SetPlayerBuff", function(_, bi) TEST.curBuff = bi return TEST.buffs[bi + 1] ~= nil end)
  rawset(f, "SetSpell", function() return true end)
  rawset(f, "AddLine", function() end)
  rawset(_G, name .. "TextLeft1", { GetText = function()
    TEST.ttReadFrom = name .. "TextLeft1"
    if TEST.curBuff then return TEST.buffs[TEST.curBuff + 1] and TEST.buffs[TEST.curBuff + 1].name end
    if TEST.curDebuff then return TEST.debuffs[TEST.curDebuff] and TEST.debuffs[TEST.curDebuff].name end
    return TEST.slotNames and TEST.slotNames[TEST.curSlot or 0]
  end })
  return f
end

function CreateFrame(ftype, name, parent)
  if ftype == "GameTooltip" and type(name) == "string" and name ~= "" and name ~= "GameTooltip" then
    local t = mkTooltipFrame(name) -- ★真机里这就是「另一个 tooltip」，与单例 GameTooltip **不是同一个对象**
    rawset(_G, name, t)
    return t
  end
  local f = newFrame(parent)
  rawset(f, "__name", name)
  if ftype == "EditBox" then f.__markEditBox() end -- 见 newMock 里 SetText 的说明
  -- ★1.72.2：真客户端里 CreateFrame("Frame","某名字") 会让该名字**成为全局**；
  --   旧桩只存 __name 不挂全局 → 测试拿不到具名帧（如 EVAL_HELPInitFrame），
  --   于是「加载提示 / 新手引导」这条路径**根本无法被断言**（组 105 就是靠它才建起来的）。
  if type(name) == "string" and name ~= "" then rawset(_G, name, f) end
  return f
end

-- UI 隐藏模拟：真客户端在**打开全屏世界地图**时会隐藏 UIParent（及其后代），
-- 而 WorldFrame 是 3D 视口、永不被 UI 隐藏。tick 是否收到 OnUpdate 取决于此。
TEST.uiHidden = false
-- 用 rawget 读 __parent：rawset 把值设成 nil 时字段其实**不存在**，
-- 普通读取会落到 newMock 的 __index 兜底函数上（返回 function 而不是 nil），
-- 祖先链遍历随即炸。rawget 才能把「没有父级」如实读成 nil。
local function parentOf(f)
  if type(f) ~= "table" then return nil end
  local p = rawget(f, "__parent")
  if p == f then return nil end
  return p
end
local function frameIsTickable(f)
  -- 祖先链里只要有一环被隐藏，该帧就收不到 OnUpdate（真客户端语义）。
  local seen = {}
  local cur = f
  while cur ~= nil and not seen[cur] do
    seen[cur] = true
    if cur == UIParent and TEST.uiHidden then return false end
    if cur == WorldFrame then return true end -- 3D 视口：永不隐藏，直接判定可跑
    cur = parentOf(cur)
  end
  return true
end
TEST.frameIsTickable = frameIsTickable

-- UIParent / WorldFrame 也走 newFrame，好让它们带上真的 __parent 字段（= nil）。
-- 用裸 newMock() 的话 __parent 会命中 __index 的兜底函数，祖先链遍历直接炸。
-- UIParent 是 UI 树的根（无父级）；WorldFrame 直接挂 UIParent 之下。
UIParent = newFrame(nil)
rawset(UIParent, "__parent", nil) -- 根帧：祖先链到此为止
-- 3D 视口，独立于 UI 显隐（真客户端恒存在）。
WorldFrame = newFrame(UIParent)
-- ★1.71.2 小地图必须有**真实几何**：用户截图事故是「EH 按钮压在小地图左下角」，
--   而旧桩的 Minimap 是个没有尺寸的空 mock（GetLeft/Right/Top/Bottom 全 nil），
--   于是「按钮是否压在地图上」这类**几何断言**在测试里根本无法成立（本项目第 N 次栽在「桩太宽松」）。
--   给一个贴近实机的小地图矩形（右上角，140×140，圆心=(sw-84, sh-84)、半径=70）。
Minimap = newFrame(UIParent)
do
  local sw, sh = 1024, 768
  local ml, mr = sw - 84 - 70, sw - 84 + 70
  local mb, mt = sh - 84 - 70, sh - 84 + 70
  rawset(Minimap, "GetLeft", function() return ml end)
  rawset(Minimap, "GetRight", function() return mr end)
  rawset(Minimap, "GetBottom", function() return mb end)
  rawset(Minimap, "GetTop", function() return mt end)
  rawset(Minimap, "GetWidth", function() return mr - ml end)
  rawset(Minimap, "GetHeight", function() return mt - mb end)
end
-- ★★★1.73.14 桩保真（用户报「开战斗UI 后物品 tooltip 几秒就消失」）：
--   真机语义 = **GameTooltip 是单例**，而 `CreateFrame("GameTooltip", "X", UIParent)` 给的是**另一个独立 tooltip**；
--   每个 tooltip 有**自己的** TextLeft1。桩不建模这两点 → 「代码借用了真实 GameTooltip」这种最毒的 bug
--   在测试里**根本不存在**（旧桩里 CreateFrame 返回的 GameTooltip 类型帧既没有 tooltip API，也没有自己的文本）。
--   因此这里：① 记 **TEST.gtCalls**（真实 GameTooltip 的 SetOwner/ClearLines/Hide 调用次数）——
--   「读光环数据时有没有碰玩家正在看的 tooltip」从此是**可断言**的性质；② **TEST.ttReadFrom** 记录读的是哪个 TextLeft1。
TEST.gtCalls = { setOwner = 0, clear = 0, hide = 0, show = 0 }
TEST.ttReadFrom = nil
GameTooltipTextLeft1 = { GetText = function()
  TEST.ttReadFrom = "GameTooltipTextLeft1"
  if TEST.curBuff then return TEST.buffs[TEST.curBuff + 1] and TEST.buffs[TEST.curBuff + 1].name end
  if TEST.curDebuff then return TEST.debuffs[TEST.curDebuff] and TEST.debuffs[TEST.curDebuff].name end
  return TEST.slotNames and TEST.slotNames[TEST.curSlot or 0]
end }
GameTooltip = {
  SetOwner = function() TEST.gtCalls.setOwner = TEST.gtCalls.setOwner + 1 end,
  Hide = function() TEST.gtCalls.hide = TEST.gtCalls.hide + 1 end,
  Show = function() TEST.gtCalls.show = TEST.gtCalls.show + 1 end,
  IsShown = function() return TEST.gtShown and true or false end,
  GetName = function() return "GameTooltip" end,
  -- ★1.71.2（第十九轮）记录 AddLine 的文本：断言要验「按钮 tooltip 到底写了什么」，
  --   桩不记录的话，这类**纯提示**需求在测试里完全不可见（本项目「桩太宽松 → 断言失明」的老坑）。
  AddLine = function(_, text, r, g, b)
    TEST.tipLines = TEST.tipLines or {}
    table.insert(TEST.tipLines, { text = tostring(text), r = r, g = g, b = b })
  end,
  ClearLines = function() TEST.gtCalls.clear = TEST.gtCalls.clear + 1 TEST.curSlot = nil TEST.curDebuff = nil TEST.curBuff = nil end,
  SetAction = function(_, slot) TEST.curSlot = slot return true end,
  SetUnitDebuff = function(_, _, i) TEST.curDebuff = i return TEST.debuffs[i] ~= nil end,
  SetPlayerBuff = function(_, bi) TEST.curBuff = bi return TEST.buffs[bi + 1] ~= nil end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) TEST.chat = (TEST.chat or "") .. tostring(msg) .. "\n" end }
-- ★1.72.2：**必须给 SlashCmdList**。此前桩里没有它，而插件把整条 /eh 命令链包在
--   @@if type(SlashCmdList) == "table" then@@ 里 → 测试里那段代码**从未被注册**，
--   于是所有斜杠命令（含新加的 /eh go tex* 诊断命令）都是**零覆盖盲区**。
SlashCmdList = {}

GetTime = function() return TEST.time or 1000 end
-- ★1.72.4 法术书桩（「释放指定等级」用）：TEST.spellbook = { {name="火球术", sub="等级 3"}, ... }
--   真客户端：GetNumSpellTabs / GetSpellTabInfo(返回 name,tex,offset,num) / GetSpellName(i,"spell") 的第二返回就是等级 subtext
GetNumSpellTabs = function() return TEST.spellTabs or 1 end
GetSpellTabInfo = function(tab)
  if tab > (TEST.spellTabs or 1) then return nil end
  return "测试页", "tex", 0, table.getn(TEST.spellbook or {})
end
GetSpellName = function(i, book)
  local e = (TEST.spellbook or {})[i]
  if not e then return nil end
  return e.name, e.sub
end
-- ★1.70.47 队伍/团队成员桩（用户要求：一键扫描队伍 → 血/蓝/buff/debuff 条件）：
--   TEST.team = { { unit="party1", name=, hp=, hpMax=, mana=, manaMax=, powerType=,
--                   buffs={ {tex=,apps=} }, debuffs={ {tex=,apps=,type=} } }, ... }
--   未设置 TEST.team 时（绝大多数既有用例）成员数为 0、teamRec 恒 nil → **老用例行为完全不变**。
--   TEST.raid = 同上结构，但 unit 用 "raid1".."raidN"（团队范围，radN 已含玩家自己）。
--   ★TEST.partyN 用于模拟**团队里**的返回值（文档：团队里它是「团人数 - 1」，不是 0）
GetNumPartyMembers = function()
  if TEST.partyN then return TEST.partyN end
  return TEST.team and table.getn(TEST.team) or 0
end
GetNumRaidMembers = function()
  if TEST.raid then return table.getn(TEST.raid) end
  return TEST.raidN or 0
end
-- ★★★1.70.47「当前目标」必须能映射到**被切过去的那个单位**：
--   TargetUnit("party1") 之后，UnitBuff/UnitDebuff/UnitHealth("target") 要回报 party1 的数据
--   （真客户端就是这样；队伍选取器的候选过滤完全依赖这一点）。
--   ★不设 TEST.targetUnit 时**行为完全不变** → 既有用例不受影响。
--   ★为什么必须补：旧桩里 "target" 恒读 TEST.tgtBuffs/TEST.debuffs（模拟某个固定怪），
--     于是「切过去再按目标条件判定」在测试里永远是错的——断言会得出与真机相反的结论。
local function resolveTarget(u)
  if u == "target" and TEST.targetUnit then return TEST.targetUnit end
  return u
end
local function teamRec(u)
  u = resolveTarget(u)
  for _, r in ipairs(TEST.team or {}) do if r.unit == u then return r end end
  for _, r in ipairs(TEST.raid or {}) do if r.unit == u then return r end end
  return nil
end
TEST.teamRec = function(u) return teamRec(u) end
UnitName = function(u)
  local r = teamRec(u)
  if r then return r.name or u end
  return u == "player" and "测试玩家" or (TEST.curTargetName or "测试怪")
end
UnitLevel = function() return 60 end
UnitClass = function(u)
  -- ★1.71.3 队伍/团队成员记录里带 cls 时按它报（职业过滤要用），否则沿用原来的老行为（既有用例不变）
  local r = teamRec(u)
  if r and r.cls then return (r.clsLoc or "战士"), r.cls, 1 end
  if u == "target" then return "战士", TEST.targetClass, 1 end
  return "战士", "WARRIOR", 1
end
-- ★1.71.3 GetRaidRosterInfo（官方文档现场核对：非团队或下标越界时**只返回一个 nil**；否则 9 个值）：
--   name, rank, subgroup(1-8), level, classLoc, classFile, zone, online, isDead
--   ★小队号与职业来自同一处 —— 正是「小队多选」「职业过滤」两条的数据源。
GetRaidRosterInfo = function(i)
  local r = TEST.raid and TEST.raid[i]
  if not r then return nil end
  return r.name or r.unit, 0, tonumber(r.grp) or 1, 60, "战士", r.cls or "WARRIOR", "测试区", 1, nil
end
UnitHealth = function(u)
  local r = teamRec(u)
  if r then return r.hp or 0 end
  return TEST.hp or 80
end
UnitHealthMax = function(u)
  local r = teamRec(u)
  if r then return r.hpMax or 100 end
  return TEST.hpMax or 100
end
UnitMana = function(u)
  local r = teamRec(u)
  if r then return r.mana or 0 end
  return TEST.mana or 50
end
UnitManaMax = function(u)
  local r = teamRec(u)
  if r then return r.manaMax or 100 end
  return TEST.manaMax or 100
end
UnitPowerType = function(u)
  local r = teamRec(u)
  if r and r.powerType ~= nil then return r.powerType end
  if u and u ~= "player" and u ~= "target" then return 0 end -- 队友默认按法力职业（0=mana）
  return TEST.powerType or 1
end
GetComboPoints = function() return TEST.combo or 0 end
-- 宠物指令桩（1.30.0）：记录调用
HasPetUI = function() return TEST.hasPet ~= false, true end
GetPetIcon = function() return "Interface\\Icons\\PetIcon" end
GetPetActionInfo = function(slot) -- 1.32.6 宠物指令图标学习桩：slot1=攻击命令 token
  if slot == 1 then return "PET_ACTION_ATTACK", nil, "texPetAttack" end
  return nil
end
PetAttack = function() TEST.petCmd = "PetAttack" end
PetFollow = function() TEST.petCmd = "PetFollow" end
PetWait = function() TEST.petCmd = "PetWait" end
PetStopAttack = function() TEST.petCmd = "PetStopAttack" end
PetPassiveMode = function() TEST.petCmd = "PetPassiveMode" end
PetDefensiveMode = function() TEST.petCmd = "PetDefensiveMode" end
PetAggressiveMode = function() TEST.petCmd = "PetAggressiveMode" end
PetDismiss = function() TEST.petCmd = "PetDismiss" end
UnitAffectingCombat = function() return TEST.inCombat or false end
GetNumShapeshiftForms = function() return TEST.stances and table.getn(TEST.stances) or 0 end
GetShapeshiftFormInfo = function(i) local f = TEST.stances and TEST.stances[i] if not f then return nil end return f.icon, f.name, f.active, f.castable end
GetShapeshiftFormCooldown = function() return 0, 0, 1 end
CastShapeshiftForm = function(i) TEST.stanceCast = i local f = TEST.stances and TEST.stances[i] if f then f.active = 1 end end
-- ★1.70.45 桩改为 filter 感知：HELPFUL 走 TEST.buffs、HARMFUL 走 TEST.pDebuffs（默认 nil → -1 立即停）。
--   原因是新功能要分别为「自身buff / 自身debuff」取剩余秒数，两个列表必须是不同的（真 API 亦然）。
GetPlayerBuff = function(i, filter)
  local list = (filter == "HARMFUL") and TEST.pDebuffs or TEST.buffs
  return (list and list[i + 1]) and i or -1
end
local function stubBuffAt(bi)
  return TEST.buffs[bi + 1] or (TEST.pDebuffs and TEST.pDebuffs[bi + 1])
end
GetPlayerBuffTexture = function(bi) local b = stubBuffAt(bi) return b and b.tex or nil end
-- ★剩余秒数：条目可带 left（秒）。实测语义：越界/空槽/无限/无结束时间都返回 0（wiki globals/Buff）
GetPlayerBuffTimeLeft = function(bi) local b = stubBuffAt(bi) return b and (b.left or 0) or 0 end
-- ★1.70.47 UnitDebuff 第三返回值 = dispel 类型 token（Magic/Curse/Disease/Poison/…，可能 nil）——
--   这是「解魔法/解诅咒」的判据来源，桩必须如实返回（wiki globals/Unit 已核对签名）。
UnitDebuff = function(u, i)
  local r = teamRec(u)
  if r then local d = r.debuffs and r.debuffs[i] if not d then return nil end return d.tex, d.apps or 0, d.type end
  local d = TEST.debuffs[i] if not d then return nil end
  return d.tex, d.apps or 0, d.type
end
UnitBuff = function(u, i)
  local r = teamRec(u)
  if r then local b = r.buffs and r.buffs[i] if not b then return nil end return b.tex, b.apps or 0 end
local t = (u == "target") and TEST.tgtBuffs or TEST.unitBuffs local b = t and t[i] if not b then return nil end return b.tex, b.apps or 0 end -- 1.32.10 兜底枚举桩；1.54.0 target 分表；1.70.1 返回层数
-- ★1.70.47 UnitIsUnit（文档：相同返回 true，不同返回 **nil**，绝不 false）——
--   队伍选取器用它反查「当前目标是哪个单位」以便精确还原，所以桩必须按文档语义返回 nil 而不是 false。
UnitIsUnit = function(a, b)
  if a == nil or b == nil then return nil end
  if a == b then return true end
  if resolveTarget(a) == resolveTarget(b) then return true end
  return nil
end
IsAltKeyDown = function() return false end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
UnitExists = function(u)
  -- ★1.70.47 "player" 恒存在（真 API 语义）；队伍成员按 TEST.team 判定。
  --   此前桩对 player 返回 false —— 团队扫描把它自己漏掉了（被组 66 当场抓到）。
  if u == "player" then return true end
  if teamRec(u) then return true end
  return u == "target" and TEST.hasTarget or false
end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
UnitAttackSpeed = function() return TEST.atkSpd or 0, TEST.atkSpdOff end
UnitCanAttack = function() return true end
-- ★1.70.28：本客户端实测返回带后缀的本地化名（"人型生物" 而非标准名 "人型"），
--   所以桩默认沿用该值；测试可用 TEST.creatureType 覆盖，用于验证「带后缀/不带后缀」两种都能匹配。
UnitCreatureType = function() return TEST.creatureType or "人型生物" end
IsActionInRange = function(slot) return TEST.inRange and TEST.inRange[slot] end -- 1.37.0：true=内 / 0=外 / nil=不测
UnitReaction = function() return 2 end
HasAction = function(slot)
  -- ★1.71.22：既保留 1.37.0 的「1~3 号格默认有东西」语义（断筋/参照槽的旧断言靠它），
  --   又让 TEST.slots 里的真实放置**看得见**（宏链路要靠它判空位）。
  if TEST.slots and TEST.slots[slot] then return true end
  return slot <= 3
end
GetActionText = function() return nil end
GetActionTexture = function(slot) return "tex" .. slot end
GetActionCooldown = function() return 0, 0 end
IsUsableAction = function() if TEST.usableRet then return TEST.usableRet.u, TEST.usableRet.noMana end return true end
IsCurrentAction = function(slot) return TEST.currentAction == slot end
IsAutoRepeatAction = function(slot) return TEST.autoRepeat == slot end -- 1.71.3 停止攻击：自动射击/魔杖自动重复判定
SpellStopCasting = function() TEST.castStoppedDirect = true end -- 1.71.3 ★真机行为：SpellStopCasting 是 Protected，插件**直调静默无效** → 桩必须如实模拟，否则「改回直调」这种回归测不出来（1.49.3 老 bug）
RunScript = function(code) TEST.runScript = code TEST.runScripts = TEST.runScripts or {} table.insert(TEST.runScripts, code) if code == "SpellStopCasting()" then TEST.castStopped = true end end -- 1.69.0 收集多条
IsInGuild = function() return TEST.inGuild or false end
-- ★1.73.24 名字右键菜单：SetItemRef（参考 ChatMOD 的包法 —— 普通全局、可写）+ 公会邀请 API 的记录器
TEST.sirCalls, TEST.invites = {}, {}
SetItemRef = function(link, text, button)
  table.insert(TEST.sirCalls, tostring(link) .. "|" .. tostring(button))
end
GuildInviteByName = function(name)
  TEST.inviteCalls = (TEST.inviteCalls or 0) + 1
  table.insert(TEST.invites, tostring(name))
end
-- ★1.73.28 右键菜单新增动作用到的桩：邀请入队（InviteToParty 优先）+ 打开聊天框（悄悄话）
TEST.partyInvites, TEST.openChats = {}, {}
InviteToParty = function(name)
  TEST.partyInviteCalls = (TEST.partyInviteCalls or 0) + 1
  table.insert(TEST.partyInvites, tostring(name))
end
InviteByName = function(name)
  TEST.inviteByNameCalls = (TEST.inviteByNameCalls or 0) + 1
  table.insert(TEST.partyInvites, tostring(name))
end
ChatFrame_OpenChat = function(text)
  TEST.openChatCalls = (TEST.openChatCalls or 0) + 1
  table.insert(TEST.openChats, tostring(text))
end
CanGuildInvite = function() return TEST.canGuildInvite ~= false end
-- ★1.71.3 跟随（Movement 分类）：文档原文 **not protected**、按名字跟（省略/空名 = 跟当前目标）、**无返回值**。
--   桩要**如实记下参数**：真接口没有返回值，所以「跟谁」是这个功能**唯一可断言的输出**；
--   同时记调用次数，好让「本地先挡掉的两条硬规则」能验成「根本没调」。
FollowByName = function(nm)
  TEST.followCalls = (TEST.followCalls or 0) + 1
  TEST.followed = nm
  return nil
end
-- ★不给 FollowUnit 建桩（生产代码不走它）：万一有人改成 FollowUnit，pcall 会失败 → 断言当场变红。
-- ★1.71.3 宏图标枚举（IconBrowser.lua 的数据源）。桩必须给得出**真实形状**的数据：
--   否则「图标库」整页在测试里永远是空的（桩太宽松 → 断言失明，本项目老坑）。
--   TEST.macroIcons = { "Spell_Fire_Fireball", ... }；nil = 一枚都没有（模拟「接口在但表为空」）。
GetNumMacroIcons = function() return type(TEST.macroIcons) == "table" and table.getn(TEST.macroIcons) or 0 end
GetMacroIconInfo = function(i)
  local t = TEST.macroIcons
  if type(t) ~= "table" then return nil end
  local name = t[i]
  if type(name) ~= "string" then return nil end -- ★非字符串 = 取失败（用于测「失败要记账」）
  -- ★1.73.5 表里给的若**已经是完整路径**（含 / 或 \），原样返回 —— 这样才能用
  --   doc/图标路径清单.txt 里的**真实形态**（/Game/Interface/Icons/X_TEX）当测试素材，
  --   否则桩永远只喂 1.12 老形态，生产上「_TEX 后缀没剥」这类问题就永远照不到。
  if string.find(name, "/", 1, true) or string.find(name, "\\", 1, true) then return name end
  return "Interface\\Icons\\" .. name
end
-- ★1.71.16 KeyBinding 桩（方案快捷键绑定弹窗 + /eh go bind 探针）：TEST.bindings = { [键] = 命令 }。
--   ★桩必须记住被测代码读写的每一个状态：绑定表本身 + SaveBindings 调用次数（不存档 = 绑定随重登丢）。
TEST.bindings = nil
SetBinding = function(k, cmd)
  if type(k) ~= "string" or k == "" then return false end
  TEST.bindings = TEST.bindings or {}
  if cmd == nil then TEST.bindings[k] = nil else TEST.bindings[k] = tostring(cmd) end
  return true
end
GetBindingAction = function(k)
  return (TEST.bindings and TEST.bindings[k]) or ""
end
GetBindingKey = function(cmd)
  if not TEST.bindings then return nil end
  local out = nil
  for k, c in pairs(TEST.bindings) do
    if c == cmd then out = (out and (out .. ",") or "") .. k end
  end
  return out
end
SaveBindings = function(_which)
  TEST.saveBindingsCalls = (TEST.saveBindingsCalls or 0) + 1
  return true
end
GetCurrentBindingSet = function() return 1 end
-- ★1.71.21 绑定命令表桩（Bindings.xml 生效自检）：TEST.bindingCmds = { {cmd, k1, k2}, ... }；nil = 空表。
TEST.bindingCmds = nil
GetNumBindings = function() return type(TEST.bindingCmds) == "table" and table.getn(TEST.bindingCmds) or 0 end
GetBinding = function(i)
  local t = TEST.bindingCmds
  if type(t) ~= "table" then return nil end
  local row = t[i]
  if type(row) ~= "table" then return nil end
  return row[1], row[2], row[3]
end
-- ★1.71.22 派发桩：ActionButtonDown/Up 全局（**本客户端实测 type=function**，插件可替换）。
--   ★桩必须**如实模拟真机行为**，否则新链路测不出来：
--     ① 真机上客户端按下 ACTIONBUTTON<n> 的键 → 调这两个全局 → 我们要能**观测到**它被调用
--     ② 我们**没接管**的格子必须原样走到原函数（桩要分别记「原函数被调」与「我们的接管被调」）
--     ③ 真机按**物理键**触发（不认精确组合键）→ 修饰键守卫是**我们自己的代码**，桩只需提供 IsAltKeyDown 等
--     ④ 真机没 ActionButtonDown 时整条路判死 → 用 TEST.noActionButtonGlobals 模拟（验「装不上要如实说」）
TEST.abDownCalls = {}
TEST.abUpCalls = {}
TEST.abOrigDownCalls = {}
TEST.abOrigUpCalls = {}
TEST.noActionButtonGlobals = false
TEST.altDown, TEST.ctrlDown, TEST.shiftDown = false, false, false
IsAltKeyDown = function() return TEST.altDown and true or false end
IsControlKeyDown = function() return TEST.ctrlDown and true or false end
IsShiftKeyDown = function() return TEST.shiftDown and true or false end
-- ★两个「原函数」桩：生产代码会把它们存起来再包一层，所以这里必须是**可辨识的独立函数**。
local function stubOrigDown(index) table.insert(TEST.abOrigDownCalls, index) end
local function stubOrigUp(index) table.insert(TEST.abOrigUpCalls, index) end
TEST.stubOrigDown, TEST.stubOrigUp = stubOrigDown, stubOrigUp
-- ★把桩挂到**真全局**上（生产代码替换的就是这两个名字）；EVAL_TB_TEST_RESET_TIMERS 里可复位。
function EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
  if TEST.noActionButtonGlobals then
    ActionButtonDown, ActionButtonUp = nil, nil
  else
    ActionButtonDown, ActionButtonUp = stubOrigDown, stubOrigUp
  end
end
EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
-- ★★★合并冲突留下的**重复定义**（1.71.1 修）：v1.71.0 的方案分享补了这两行简版桩，
--   而队友/团员扫描在文件上方另有一份**支持 TEST.team/TEST.raid 列表**的桩。
--   Lua 里**后赋值者静默获胜** → 简版把我那份整个盖掉 → 队伍扫描只扫到自己，
--   组 66 第一条断言当场炸（got=1 want=3），而**语法检查、luacheck、单个文件都看不出问题**。
--   ★教训：Lua 合并冲突不会像 C 那样报「重定义」——**同一个全局被赋两次是合法的**，
--     谁在后面谁生效。改完必须跑测试，不能只看语法。（详见 CLAUDE.md 的 F3/教训节）
--   （两份桩已合并：上方那份保留 TEST.partyN/TEST.team 两种数据源）
AttackTarget = function() TEST.attackTried = true end
-- ★1.71.3 反向哨兵：这两条**故意留着**——停读条确认无法真中断（移动脉冲实测无效、已从生产代码删除），
--   断言用它们证明「我们**绝不**去动玩家角色」（调用了就让断言变红）。
MoveForwardStart = function() TEST.moveStart = (TEST.moveStart or 0) + 1 end
MoveForwardStop = function() TEST.moveStop = (TEST.moveStop or 0) + 1 end
UseAction = function(slot) table.insert(TEST.used, slot) end
TargetNearestEnemy = function()
  TEST.targetSel = "nearEnemy"
  if TEST.nearby then -- 附近敌人循环模拟：依次选下一个名字
    TEST.nearIdx = (TEST.nearIdx or 0) + 1
    TEST.curTargetName = TEST.nearby[TEST.nearIdx]
  end
end
TargetUnit = function(u)
  TEST.targetSel = "unit:" .. tostring(u)
  TEST.targetUnit = u -- 之后 UnitXxx("target") 就回报这个单位的数据（见 resolveTarget）
end
TargetByName = function(n)
  TEST.targetSel = "name:" .. tostring(n)
  TEST.byNameArg = n
  TEST.targetUnit = nil
  for _, r in ipairs(TEST.team or {}) do if r.name == n then TEST.targetUnit = r.unit end end
  for _, r in ipairs(TEST.raid or {}) do if r.name == n then TEST.targetUnit = r.unit end end
  if TEST.nearby then TEST.curTargetName = n end -- 还原目标模拟
end
TargetNearestFriend = function() TEST.targetSel = "nearFriend" end
TargetNearestPartyMember = function() TEST.targetSel = "nearParty" end
TargetNearestRaidMember = function() TEST.targetSel = "nearRaid" end
TargetLastEnemy = function() TEST.targetSel = "lastEnemy" end
TargetLastTarget = function() TEST.targetSel = "lastTarget" end
ClearTarget = function() TEST.targetSel = "clear" TEST.targetUnit = nil end
-- 物品使用桩（1.32.0）：TEST.bags = { [bag*100+slot] = { name=, tex=, count=, cd= } }
GetContainerNumSlots = function(bag) return (bag >= 0 and bag <= 4) and 2 or 0 end
GetContainerItemLink = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] return it and ("|Hitem:1|h[" .. it.name .. "]|h") or nil end
GetContainerItemInfo = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if not it then return nil end return it.tex, it.count or 1, false, it.q or 1, false end
GetContainerItemCooldown = function(bag, slot) local it = TEST.bags and TEST.bags[bag * 100 + slot] if it and it.cd then return 900, 60, 1 end return 0, 0, 1 end
UseContainerItem = function(bag, slot)
  TEST.usedItem = bag * 100 + slot
  TEST.sellCalls = (TEST.sellCalls or 0) + 1
  if TEST.consumeOnUse and not TEST.noSell and TEST.bags then TEST.bags[bag * 100 + slot] = nil end -- 1.68.2 仅工具箱段模拟成交消失
end
GetItemInfo = function(x) -- 1.69.1 售卖明细桩：TEST.itemInfo[名称] = { t=种类, st=子类 }（无条目=未缓存）
  local it = TEST.itemInfo and TEST.itemInfo[x]
  if not it then return nil end
  return it.name or x, "|Hitem:1|h[" .. tostring(x) .. "]|h", it.q or 0, 1, it.t, it.st, 1, "", "tex"
end
-- 地图定位桩（DataSearch.lua 地图图标）：本客户端 GetMapZones 忽略参数只答选中大陆（UnrealQuest 实测注释）
GetCurrentMapContinent = function() return 1 end
SetMapZoom = function(c, z) TEST.mapZooms = TEST.mapZooms or {} table.insert(TEST.mapZooms, tostring(c) .. "," .. tostring(z)) end
GetMapZones = function(_) return { "杜隆塔尔", "奥格瑞玛" } end
ShowUIPanel = function(_) TEST.shownUIPanel = (TEST.shownUIPanel or 0) + 1 end
WorldMapFrame = newMock()
-- 地图可见性桩（1.70.14）：DataSearch 的视图签名要读它——实测「关图后 GetViewedZone 仍报旧区域」，
-- 故可见性必须直接问帧。TEST.mapShown 驱动（nil=帧不可探测 → 退回只比区域）
WorldMapFrame.IsShown = function() return TEST.mapShown end
WorldMapButton = newMock()
-- 数据检索桩（DataSearch.lua）：迷你 UnrealQuestData——1 物品/4 单位/1 对象/1 任务/2 区域
UnrealQuestData = {
  items = { [2589] = { U = { [3] = 11.89, [40] = 29.04 }, O = { [-100] = 5.5 }, V = { [44] = 0 } } },
  ["items_zhCN"] = { [2589] = "亚麻布" },
  ["items_enUS"] = { [2589] = "Linen Cloth" },
  units = {
    [3] = { coords = { { 46.2, 9.3, 14, 25 } }, fac = "AH", lvl = "2" },
    [40] = { coords = { { 51.8, 84.7, 1637, 25 } }, fac = "H", lvl = "5", rnk = "3" }, -- rnk=3 世界Boss（图标断言用）
    [44] = { coords = {}, fac = "A", lvl = "10" },
    [99] = { coords = { { 1, 1, 14, 0 } }, fac = "AH", lvl = "9" },
  },
  ["units_zhCN"] = { [3] = "食腐者", [40] = "狗头人矿工", [44] = "商人贝利" },
  ["units_enUS"] = { [3] = "Scavenger", [40] = "Kobold Miner", [44] = "Vendor Belly", [99] = "OnlyEnglishMob" },
  objects = { [-100] = { coords = { { 10, 20, 14, 0 } }, fac = "AH" } },
  ["objects_zhCN"] = { [-100] = "旧木箱" },
  quests = { [1] = { lvl = 4, min = 1, ["start"] = { U = { 3 } }, ["end"] = { U = { 3 } }, obj = { I = { 2589 } } } },
  ["quests_zhCN"] = { [1] = { T = "收集亚麻布", O = "收集 10 块亚麻布。", D = "帮我收集一些亚麻布。" } },
  ["quests_enUS"] = { [1] = { T = "Gather Linen", O = "Gather 10 Linen Cloth.", D = "Help me." } },
  zones = { [14] = { 12, 1, 1, 0, 0 }, [1637] = { 33, 1, 1, 0, 0 } },
  ["zones_zhCN"] = { [14] = "杜隆塔尔", [1637] = "奥格瑞玛" },
  ["zones_enUS"] = { [14] = "Durotar", [1637] = "Orgrimmar" },
}
-- Addon 依赖探测桩（1.70.46：DataSearch 判断 UnrealQuest 是否可用）
-- 文档要点（emberveil.org/wiki/lua/globals/Addon）：
--   · GetAddOnInfo(名) → 文件夹名,标题,备注,URL,可加载(1/nil),原因token,SECURE/INSECURE
--     ★未知插件：除 security 外**全部 nil** —— 探测逻辑正是靠「第一个返回值是否为 nil」判「未安装」
--   · GetAddOnEnableState(char, 名) → 0 未启用 / 1 部分角色 / 2 已启用
--   · IsAddOnLoaded(名) → 布尔
-- TEST.uqAddon 驱动：{ installed = ?, enabled = ? }（默认「未安装」）
TEST.uqAddon = { installed = false }
GetAddOnInfo = function(name)
  local a = TEST.uqAddon
  if not (a and a.installed) then return nil, nil, nil, nil, nil, nil, "INSECURE", nil end
  return "UnrealQuest", "UnrealQuest", "", nil, 1, nil, "INSECURE", nil
end
GetAddOnEnableState = function(chr, name)
  local a = TEST.uqAddon
  if not (a and a.installed) then return 0 end
  return a.enabled and 2 or 0
end
IsAddOnLoaded = function(name)
  local a = TEST.uqAddon
  return (a and a.installed and a.loaded) and true or false
end
-- 工具箱桩（1.68.0）
GetMoney = function() return 1000000 end
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return TEST.repairCost or 0 end
RepairAllItems = function() TEST.repaired = true end
GetMerchantNumItems = function() return TEST.merchant and table.getn(TEST.merchant) or 0 end
GetMerchantItemInfo = function(i) local m = TEST.merchant and TEST.merchant[i] if not m then return nil end return m.name, "tex", m.price or 1, 1, m.avail or -1, true end
BuyMerchantItem = function(i, n) local m = TEST.merchant and TEST.merchant[i] TEST.bought = (TEST.bought or "") .. tostring(m and m.name) .. "x" .. tostring(n) .. ";" end
PickupContainerItem = function(b, s) TEST.picked = b * 100 + s end
DeleteCursorItem = function() if TEST.picked then TEST.deleted = TEST.picked TEST.picked = nil end end
ConfirmReadyCheck = function() TEST.readyChecked = true end
-- 1.69.0 任务日志扫描桩（TEST.questLog = { {title=, complete=, objs={{txt=,d=,m=}}} }）
GetNumQuestLogEntries = function() return table.getn(TEST.questLog or {}) end
GetQuestLogTitle = function(i)
  local q = TEST.questLog and TEST.questLog[i]
  if q then return q.title, q.lvl or 1, nil, nil, nil, q.complete and 1 or nil end
end
GetQuestLogLeaderBoard = function(oi, qi)
  local q = TEST.questLog and TEST.questLog[qi]
  local o = q and q.objs and q.objs[oi]
  if o then return o.txt, "monster", o.d, o.m end
end
AcceptQuest = function() TEST.questAccepted = true end
CompleteQuest = function() TEST.questCompleted = true end
IsQuestCompletable = function() return TEST.questCompletable or false end
GetNumQuestChoices = function() return TEST.questChoices or 0 end
-- ★★★1.71.2 桩必须模拟「领奖会**再触发一次** QUEST_COMPLETE」——
--   这正是用户实测的死循环成因（GetQuestReward → QUEST_COMPLETE → 再领 → …）。
--   旧桩只记一个 TEST.questReward 就完事，于是「无限刷屏」在测试里**完全不可见**
--   （本项目第 N 次栽在「桩太宽松 → 真实事故测不出来」）。
--   ★设 TEST.rewardRefires = true 才模拟，默认 false 保持既有用例行为不变。
--   计数上限防止测试自身跑不完（真实事故里循环可以跑到几千次）。
GetQuestReward = function(c)
  TEST.questReward = c or 0
  TEST.rewardCalls = (TEST.rewardCalls or 0) + 1
  if TEST.rewardRefires and (TEST.rewardCalls or 0) < 500 then
    if type(EVAL_TB_ONEVENT) == "function" then EVAL_TB_ONEVENT("QUEST_COMPLETE") end
  end
end
SetCVar = function(k, v) TEST.cvars = TEST.cvars or {} TEST.cvars[k] = tostring(v) end
GetCVar = function(k) return (TEST.cvars and TEST.cvars[k]) or "0" end
-- ===== 1.73.10 角色名职业着色（工具箱）桩：公会 / 查询 / 好友三个窗口 =====
-- ★桩的纪律（本项目老坑）：必须让被测代码读到的**每一个状态**都真实存在并且**可观测**——
--   · 三个刷新函数桩各自计数（证明「我们先调原函数再叠色」这条链没断）；
--   · 每个 FontString 的 SetTextColor 单独记账（否则只能测「有没有崩」，测不出「颜色对不对」）；
--   · 数据源（GetGuildRosterInfo/GetWhoInfo/GetFriendInfo）由 TEST.paint* 驱动，方便造在线/离线/同地图三种行。
TEST.paintFS = {}
TEST.paintZone = "艾尔文森林"
TEST.paintRanks = 5
TEST.paintOffset = 0
TEST.guildUpd, TEST.whoUpd, TEST.friendsUpd = 0, 0, 0
local function mkPaintFS(name)
  local fs = newMock()
  rawset(fs, "SetTextColor", function(_, r, g, b) TEST.paintFS[name] = { r = r, g = g, b = b } end)
  rawset(_G, name, fs)
  return fs
end
GUILDMEMBERS_TO_DISPLAY, WHOS_TO_DISPLAY, FRIENDS_TO_DISPLAY = 3, 3, 3
GuildListScrollFrame, WhoListScrollFrame, FriendsFrameFriendsScrollFrame = newMock(), newMock(), newMock()
FauxScrollFrame_GetOffset = function() return TEST.paintOffset or 0 end
GetRealZoneText = function() return TEST.paintZone or "艾尔文森林" end
GuildControlGetNumRanks = function() return TEST.paintRanks or 5 end
for i = 1, 3 do
  mkPaintFS("GuildFrameButton" .. i .. "Name")
  mkPaintFS("GuildFrameButton" .. i .. "Class")
  mkPaintFS("GuildFrameButton" .. i .. "Level")
  mkPaintFS("GuildFrameButton" .. i .. "Zone")
  mkPaintFS("GuildFrameGuildStatusButton" .. i .. "Name")
  mkPaintFS("GuildFrameGuildStatusButton" .. i .. "Rank")
  mkPaintFS("GuildFrameGuildStatusButton" .. i .. "Note")
  mkPaintFS("WhoFrameButton" .. i .. "Name")
  mkPaintFS("WhoFrameButton" .. i .. "Class")
  mkPaintFS("WhoFrameButton" .. i .. "Level")
  mkPaintFS("WhoFrameButton" .. i .. "Variable")
  mkPaintFS("FriendsFrameFriendButton" .. i .. "ButtonTextNameLocation")
  mkPaintFS("FriendsFrameFriendButton" .. i .. "ButtonTextInfo")
end
-- ★三个「原函数」桩必须是**可辨识的独立函数**（生产代码会存起来再包一层）
GuildStatus_Update = function() TEST.guildUpd = TEST.guildUpd + 1 end
WhoList_Update = function() TEST.whoUpd = TEST.whoUpd + 1 end
FriendsList_Update = function() TEST.friendsUpd = TEST.friendsUpd + 1 end
-- ★复位：让「窗口不存在」这种用例可以把某个全局摘掉，再由这里还原（生产代码是幂等安装，重装不重复包装）
function EVAL_TEST_RESET_PAINT_GLOBALS()
  GuildStatus_Update = function() TEST.guildUpd = TEST.guildUpd + 1 end
  WhoList_Update = function() TEST.whoUpd = TEST.whoUpd + 1 end
  FriendsList_Update = function() TEST.friendsUpd = TEST.friendsUpd + 1 end
end
EVAL_TEST_RESET_PAINT_GLOBALS()
GetGuildRosterInfo = function(i)
  local r = TEST.guildRows and TEST.guildRows[i]
  if not r then return nil end
  return r.name, r.rank or "成员", r.rankIndex or 3, r.level or 10, r.class or "战士",
         r.zone or "艾尔文森林", r.note or "", "", (r.online ~= false)
end
GetWhoInfo = function(i)
  local r = TEST.whoRows and TEST.whoRows[i]
  if not r then return nil end
  return r.name, r.guild or "", r.level or 10, r.race or "人类", r.class or "法师", r.zone or "艾尔文森林"
end
GetFriendInfo = function(i)
  local r = TEST.friendRows and TEST.friendRows[i]
  if not r then return nil end
  return r.name, r.level or 10, r.class or "法师", r.zone or "艾尔文森林", (r.online ~= false)
end
-- ★1.73.12 聊天名字着色：采集只读「名册条数」。桩必须**真的**存在这三个 API ——
--   否则生产代码里那条「type(X) == "function"」守卫会让整条采集路径在测试里**从未被走到**
--   （本项目老坑：桩太宽松 → 断言失明）。条数由上面三张行表驱动。
GetNumGuildMembers = function() return table.getn(TEST.guildRows or {}) end
GetNumWhoResults = function() return table.getn(TEST.whoRows or {}) end
-- ★1.73.12 名字主动查询：记录发出的 /who（断言「发了什么 / 发了几次 / 间隔对不对」）
TEST.whoSent = {}
SendWho = function(filter)
  TEST.whoSent = TEST.whoSent or {}
  table.insert(TEST.whoSent, tostring(filter))
  return true
end
-- ★1.73.12 第二入口桩：本客户端聊天框走 ChatFrame_OnEvent（真机实测 frame.AddMessage 写了不生效）。
--   ★桩必须**从全局读 arg1**（1.12 的聊天处理器就是这么取值的）——否则「回写全局 arg1」这条修复
--     在测试里根本验不到（本项目「桩太宽松 → 断言失明」的老坑）。
TEST.ceCalls, TEST.ceSeen = 0, {}
local function tbCeStub(e)
  TEST.ceCalls = TEST.ceCalls + 1
  table.insert(TEST.ceSeen, { event = tostring(e), arg1 = tostring(arg1), arg2 = tostring(arg2) })
end
ChatFrame_OnEvent = tbCeStub
-- 模拟「客户端把自己的实现写回全局」（真机上就是这么顶掉我们那层的）
function EVAL_TEST_CE_RECLAIM() ChatFrame_OnEvent = tbCeStub end
-- ★1.73.12 官方「消息组」API 桩（类别 ChatWindow）：TEST.cwMsg[窗口] = "SAY,CHANNEL,CHANNEL_NOTICE"
--   ★桩必须**按组名增删**（真的改变字符串），否则「摘掉/还原」这两条断言根本验不到东西。
TEST.cwMsg = { [1] = "SAY,YELL,CHANNEL,CHANNEL_NOTICE,GUILD" }
NUM_CHAT_WINDOWS = 7
GetChatWindowMessages = function(win) return TEST.cwMsg[win] end
RemoveChatWindowMessages = function(win, grp)
  local s = TEST.cwMsg[win]
  if type(s) ~= "string" then return false end
  local out = {}
  for part in string.gmatch(s, "[^,]+") do if part ~= grp then table.insert(out, part) end end
  TEST.cwMsg[win] = table.concat(out, ",")
  return true
end
AddChatWindowMessages = function(win, grp)
  if type(grp) ~= "string" or grp == "" then return false end
  TEST.cwMsg[win] = (type(TEST.cwMsg[win]) == "string" and TEST.cwMsg[win] ~= "") and (TEST.cwMsg[win] .. "," .. grp) or grp
  return true
end
GetNumFriends = function() return table.getn(TEST.friendRows or {}) end

