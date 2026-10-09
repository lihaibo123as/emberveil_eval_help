--[[ EvalHelp / tools/TargetHealth.lua

目标生命值显示（**独立工具模块**，1.75.113）

用户需求（原文）：「能否将数据库复制到当前插件内.并将在工具箱内添加个工具->目标生命值显示开关,
显示方式和当前生命值方式类似.UI类似」（附截图：玩家框有「1108 / 1108」、目标框只有两根光条）。

★★★ 为什么需要它（一句话）：**客户端对非组队单位只给 0~100 百分比**（`UnitHealthMax("target")` 恒 100），
  所以目标框上「1,234 / 5,678」这两个数**客户端拿不出来**；要显示就得按「名字 + 等级」反查本服生物表、
  再用公式复算**上限**（数据 = 本插件自带的 `UnitVitalsData.lua` / `UnitNamesData.lua`，出处见文件头）。

数据（本模块是唯一消费方）：
  · `EVAL_UNIT_VITALS`（10,369 条模板 + classLevel + rankHpRate，**表体逐字节来自本服快照**）
  · `EVAL_UNIT_NAMES_EN`（恒载入的回退表）+ `EVAL_UNIT_NAMES_ZH` / `_RU`（按客户端 locale 载入）
  · 公式：maxHealth = max(1, round(rankHpRate[rank] × classLevel[class][level][1] × healthMultiplier))

★★★ 三条口径（照抄不得走样）：
  ① **上限 = 精确**（表复算；已与本服数据库站抽样 47/47 对齐）；**当前 = 上限 × 客户端百分比**
     （受百分比量化 ⇒ 精度约 ±1% 上限；**不是**独立读数，`/eh go 目标血量` 状态行如实写明）。
  ② **判不出就退回百分比**：表没载入 / 名字查不到 / 等级读不到（`??` 骷髅 = **-1**，官方 wiki 原文）
     / 目标本来给绝对值 ⇒ **绝不用 0 或假数字冒充**：文本退回「22%」（灰色条），并把这一笔记进取证环。
  ③ **客户端本来就给绝对值的单位**（自己 / 宠物 / 队伍 / 队友宠物）⇒ **不查表**，直接用客户端值
     （查了就是二次换算）。判据 = 该单位是不是我 / 我的宠物 / 我的队友（UnitIsUnit ∨ UnitInParty/Raid）。

纪律（与 `tools/` 其他模块同一把尺子）：
  · 只用**全局桥**（`EVAL_SAY` / `EVAL_LOGLINE` / `EVAL_L` / `EVAL_TB_CFG` / `EVAL_HELP_CONFIG` /
    `EVAL_TB_MOD_ROWS` / `EVAL_TB_REFRESH`）—— 绝不引用 EvalHelp.lua 的文件内 local。
  · **载入期零副作用**：文件顶层只登记工具箱模块行 + 定义全局函数，**不建帧 / 不挂事件 / 不读存档**。
  · **关断四件事**（CLAUDE.md §4.1）：关掉 = 真摘 `OnUpdate` 与全部事件 + 收我们自建的层（1.12 无销毁
    API ⇒ 只 Hide + 留句柄复用，代价如实写明）+ 会话态复位（缓存 / 判定 / 计数）+ 无借用对象需还回。
  · 一个模块只许**一个节拍帧**（`EVAL_TH_FRAME`），挂/摘只有 **`thSync` 一个入口**。
  · 纯显示：`EnableMouse(false)`（不抢点击），绝不写客户端任何对象（只**读** `TargetFrame` 的几何当锚点）。
]]

-- ===== 桥（模块里没有全局 say / logLine / L，必须自带） =====
local function thSay(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(msg)) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end
local function thLog(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, tostring(msg)) end
end
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

-- ===== 常量 =====
local TH_RING_MAX = 30       -- ★有界落盘环（cfg.thProbe）
local TH_CACHE_LIMIT = 300   -- ★(名字:等级) → 上限 的缓存上限（超了整表丢弃，绝不无界增长）
local TH_TICK = 0.2          -- 节拍（事件之外的安全网；值没变就不重画）
local TH_EVENT_GAP = 0.05    -- 事件去抖（PLAYER_TARGET_CHANGED 实测可到 ~10 次/秒）
local TH_W = 180             -- ① fallback 板宽（**只有连客户端目标框都没有**时才画自己的条）
local TH_BAR_H = 13
local TH_FONT_SIZE = 12      -- 与单位框那行数值同档
local TH_FONTS = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }
-- 客户端目标框「血条上的那串文字」的候选名（1.12 FrameXML：TextStatusBar 模板会给每条状态条配一个）
local TH_CLIENT_TEXT = { "TargetFrameHealthBarText" }
local TH_CLIENT_BAR = { "TargetFrameHealthBar" }
local TH_READBACK_FAIL_MAX = 3   -- 写客户端文字连续失败这么多次 ⇒ 退回「自建覆盖层」并如实记一行

-- ===== 状态 =====
EVAL_TH = {
  on = false,             -- 事件+节拍挂上了没有（**真值**仍是 tbCfg().targetHealth）
  built = false, shown = false,
  frame = nil, border = nil, bg = nil, fill = nil, text = nil,
  anchorKind = nil,       -- "barCenter"（居中压客户端目标血条）/ "targetBelow" / "screenTop"
  mode = nil,             -- 呈现模式："clientText"（写客户端那行文字）/ "overlay"（自建层压在血条上）/ "plate"（连目标框都没有）
  refApplied = nil,       -- 已经照抄过谁的字体/颜色（状态门，避免每拍发 SetFont/SetTextColor）
  lastPaint = 0, lastKey = nil,
  index = nil, indexN = 0, indexState = nil,   -- nil 未建 / "ok" / "nodata"
  cache = {}, cacheN = 0,
  visits = 0, hits = 0, misses = 0, fallbacks = 0,
  missSeen = {},          -- 本会话已记过的「查不到」键（环里不重复刷）
  verdict = "—",
  -- 客户端目标条文字那条腿的记账（借来的对象 ⇒ 写前抓原值、关掉还回、写后自证）
  nt = { fs = nil, tried = false, orig = nil, wrote = false, fails = 0, back = nil, mode = nil },
}

-- 前向声明：Lua 的 local 可见性从声明点开始 ⇒ 被后面函数引用的，必须先在这里声明
local thSync, thPaint, thTick, thEnsure, thApply

-- ===== 配置：开关真值 = 工具箱表 tbCfg().targetHealth（**唯一写口 EVAL_TH_SET**） =====
local function thTb()
  if type(EVAL_TB_CFG) == "function" then return EVAL_TB_CFG() end
  return rawget(_G, "EVAL_HELP_CONFIG")
end
function EVAL_TH_ENABLED()
  local tb = thTb()
  return (type(tb) == "table" and tb.targetHealth == true) and true or false
end
local function thCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then c = {} rawset(_G, "EVAL_HELP_CONFIG", c) end
  if type(c.thProbe) ~= "table" then c.thProbe = { out = {} } end
  return c
end

-- ===== 显示内容（「数值 / 百分比」两项目可选多选；1.75.114 用户要求） =====
-- ★真值 = 本模块自己的子树 `EVAL_HELP_CONFIG.targetHealthCfg`（`val` / `pct`）
-- ★**默认两样都开**（键为 nil ⇒ true ⇒ 老行为一字不变，**不需要迁移**）
-- ★★★**两项都不勾 = 按「都显示」处理（fail-open）**：一条只剩光条、什么数字都没有的目标条
--   对用户没有意义（与「关掉零动作」无关，是**呈现层的兜底**）⇒ 兜底时必须**如实出声**，
--   绝不静默把用户的选择顶掉。
local function thOptsCfg()
  local c = thCfg()
  if type(c.targetHealthCfg) ~= "table" then c.targetHealthCfg = {} end
  return c.targetHealthCfg
end
-- ★默认档 = **只显示「数值」**（照玩家头像那行 `908 / 908` 的口径；百分比要显式勾上才出现）
--   ★`pct` 用 `== true` 读：nil / 缺键 = 关（默认档只写在**读口**，不改存档里的键）
local function thOpts()
  local o = thOptsCfg()
  local val = (o.val ~= false)          -- nil / true ⇒ 开；只有显式 false 才是关
  local pct = (o.pct == true)           -- 只有显式 true 才是开
  if (not val) and (not pct) then return true, true, true end   -- 第三返回 = 走了兜底
  return val, pct, false
end
-- 唯一写口（工具箱 [设置] 下拉 / `/eh go 目标血量 数值|百分比` 都走它）
function EVAL_TH_SETOPT(which, on)
  if which ~= "val" and which ~= "pct" then return false end
  local o = thOptsCfg()
  o[which] = on and true or false
  local val, pct, forced = thOpts()
  -- ★改完立刻重画（`thPaint(true)` 强制），否则要等下一拍才变 = 用户眼里的「点了没反应」
  if EVAL_TH_ENABLED() and EVAL_TH.frame then pcall(thPaint, true) end
  local parts = {}
  if val then parts[#parts + 1] = L("TH_OPT_VAL") end
  if pct then parts[#parts + 1] = L("TH_OPT_PCT") end
  local line = string.format(L("TH_SET_SAY"), table.concat(parts, " ｜ "))
  if forced then line = line .. "（" .. L("TH_SET_TIP_EMPTY") .. "）" end
  thSay(line)
  if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
  return true
end

-- ===== 取证环（有界；只记「真事件」：数据缺失 / 开关 / 查不到） =====
local function thWhen()
  if type(date) == "function" then local ok, s = pcall(date, "%H:%M:%S") if ok and s then return tostring(s) end end
  local t = (type(GetTime) == "function") and (GetTime() or 0) or 0
  return string.format("%.1f", t)
end
local function thRing(line)
  local c = thCfg()
  local out = c.thProbe.out
  out[table.getn(out) + 1] = thWhen() .. " " .. tostring(line)
  while table.getn(out) > TH_RING_MAX do table.remove(out, 1) end
  thLog("[目标血量] " .. tostring(line))
end

-- ===== 数据 =====
local function thVitals()
  local db = rawget(_G, "EVAL_UNIT_VITALS")
  if type(db) ~= "table" then return nil end
  if type(db.units) ~= "table" or type(db.classLevel) ~= "table" then return nil end
  return db
end

-- 名字索引（**惰性**建一次）：已载入的名字表并起来 → name -> id（同名多 id 存成列表）
-- ★与 unrealUI 的差别：它三份表**互斥**（只载一份）；我们 enUS 恒载入当回退表 —— 本服 zhCN 数据里
--   有 128 个 id 没有中文名（客户端直接显示英文名）⇒ 只带 zhCN 表就查不到。已复算：并集覆盖 10,367/10,369，
--   且 (名字,等级) → 最大生命值 **零冲突**。
local function thIndex()
  if EVAL_TH.index then return EVAL_TH.index end
  if EVAL_TH.indexState == "nodata" then return nil end
  local idx, n = {}, 0
  local tables = {
    rawget(_G, "EVAL_UNIT_NAMES_EN"),
    rawget(_G, "EVAL_UNIT_NAMES_ZH"),
    rawget(_G, "EVAL_UNIT_NAMES_RU"),
  }
  for t = 1, table.getn(tables) do
    local tb = tables[t]
    if type(tb) == "table" then
      for name, id in pairs(tb) do
        local cur = idx[name]
        if cur == nil then idx[name] = id n = n + 1
        elseif type(cur) == "table" then cur[table.getn(cur) + 1] = id
        elseif cur ~= id then idx[name] = { cur, id } end
      end
    end
  end
  if n == 0 then
    EVAL_TH.indexState = "nodata"
    thRing("★数据缺失：UnitNamesData.lua 没载入（名字索引建不出来）⇒ 只显示百分比")
    return nil
  end
  EVAL_TH.index, EVAL_TH.indexN, EVAL_TH.indexState = idx, n, "ok"
  return idx
end

local function thRound(x) return math.floor(x + 0.5) end

-- (名字, 等级) → 上限；判不出返回 nil（**绝不猜**）
local function thCompute(name, level)
  local idx = thIndex()
  if not idx then return nil end
  local db = thVitals()
  if not db then return nil end
  local entry = idx[name]
  if entry == nil then return nil end
  local rec
  if type(entry) == "table" then
    for i = 1, table.getn(entry) do
      local r = db.units[entry[i]]
      if r and level >= r[3] and level <= r[4] then rec = r break end   -- ★等级区间不覆盖 = 不是这只怪
    end
  else
    local r = db.units[entry]
    if r and level >= r[3] and level <= r[4] then rec = r end
  end
  if not rec then return nil end
  local byClass = db.classLevel[rec[1]]
  local stats = byClass and byClass[level]
  if type(stats) ~= "table" then return nil end
  local rate = 1
  if type(db.rankHpRate) == "table" and db.rankHpRate[rec[2]] then rate = db.rankHpRate[rec[2]] end
  local hp = thRound(rate * stats[1] * rec[5])
  if hp < 1 then hp = 1 end
  return hp
end

local function thMaxHealth(name, level)
  if type(name) ~= "string" or name == "" then return nil end
  level = tonumber(level)
  -- ★`UnitLevel` 对「高出玩家 10 级以上的敌对单位与世界首领」返 **-1**（官方 wiki 原文）⇒ 猜等级就会
  --   打印一个错的上限；这里如实放弃（退回百分比）。
  if not level or level < 1 then return nil end
  local key = name .. ":" .. level
  local hit = EVAL_TH.cache[key]
  if hit ~= nil then if hit == false then return nil end return hit end
  if EVAL_TH.cacheN >= TH_CACHE_LIMIT then EVAL_TH.cache, EVAL_TH.cacheN = {}, 0 end
  local hp = thCompute(name, level)
  EVAL_TH.cacheN = EVAL_TH.cacheN + 1
  EVAL_TH.cache[key] = hp or false          -- ★「明确判不出」也缓存（同 name:level 不重复扫索引）
  return hp
end

-- 「这个单位客户端本来就给绝对值吗」（自己 / 宠物 / 队伍 / 队友宠物）
local function thAbsoluteUnit(unit)
  local function truth(fn, a, b)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, a, b)
    return (ok and v) and true or false
  end
  if truth(UnitIsUnit, unit, "player") then return true end
  if truth(UnitIsUnit, unit, "pet") then return true end
  if truth(UnitInParty, unit) then return true end
  if truth(UnitInRaid, unit) then return true end
  return false
end

-- ===== 数字格式化（千分位；「1099230」这种读不出来） =====
local function thNum(n)
  n = math.floor(tonumber(n) or 0)
  local out, guard = tostring(n), 0
  while guard < 8 do
    local a, b = string.gsub(out, "^(%-?%d+)(%d%d%d)", "%1,%2")
    if b == 0 then break end
    out, guard = a, guard + 1
  end
  return out
end

-- ===== 帧（**首用才建**；1.12 没有销毁帧/纹理的 API ⇒ 建一次复用，关掉只 Hide） =====
local function thSolid(tex, r, g, b, a)
  if type(tex) ~= "table" then return end
  if type(tex.SetTexture) == "function" then pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8") end
  if type(tex.SetVertexColor) == "function" then pcall(tex.SetVertexColor, tex, r, g, b, a or 1) end
end

local function thFontOf(fs, size)
  if type(fs) ~= "table" or type(fs.SetFont) ~= "function" then return nil end
  for i = 1, table.getn(TH_FONTS) do
    -- ★判据 = pcall 的**第一个**返回值（`SetFont` 本身没有返回值；写成"第二个返回"就每次都"失败"）
    if pcall(fs.SetFont, fs, TH_FONTS[i], size, "OUTLINE") then return TH_FONTS[i] end
  end
  if type(fs.SetFontObject) == "function" and pcall(fs.SetFontObject, fs, "GameFontNormalSmall") then
    return "GameFontNormalSmall"
  end
  return nil
end

-- 客户端目标框的**血条**（我们只读它的几何，用来把文字居中压上去）
local function thResolve(cands)
  for i = 1, table.getn(cands) do
    local o = rawget(_G, cands[i])
    if type(o) == "table" then return o end
  end
  return nil
end
local function thClientBar()
  local bar = rawget(_G, "EVAL_TH_BAR_CACHE")
  if bar ~= nil then if bar == false then return nil end return bar end
  local b = thResolve(TH_CLIENT_BAR)
  if b and type(b.GetCenter) ~= "function" and type(b.GetWidth) ~= "function" then b = nil end
  rawset(_G, "EVAL_TH_BAR_CACHE", b or false)     -- 缓存（拿不到也记着，别每拍扫全局）
  return b
end

-- ★★★客户端目标框那条「血条上的文字」FontString —— 公开接口里**它已经居中在血条上**、
--   字体与颜色就是玩家框那行数值的同款模板（`TextStatusBarText`）⇒ 优先写它（最忠实的「参考玩家头像」）。
--   ★**只解析一次**（拿不到也记着）；★**写前把它原本的文字读下来**（关掉时要还回原值）。
local function thClientText()
  local n = EVAL_TH.nt
  if n.tried then return n.fs end
  n.tried = true
  local fs = thResolve(TH_CLIENT_TEXT)
  if not fs then
    local bar = thClientBar()
    local c = (type(bar) == "table") and bar.textString or nil
    if type(c) == "table" then fs = c end
  end
  if fs and type(fs.SetText) ~= "function" then fs = nil end
  if fs and type(fs.GetText) == "function" then
    local ok, t = pcall(fs.GetText, fs)
    n.orig = (ok and type(t) == "string") and t or ""
  else
    n.orig = ""
  end
  n.fs = fs
  return fs
end

-- 参考「玩家头像那行数值」的字体与颜色（读不出来就用自己的字体链 + 白色）
local function thRefText()
  local ref = rawget(_G, "EVAL_TH_REF_CACHE")
  if ref == nil then
    ref = thResolve({ "PlayerFrameHealthBarText", "TargetFrameHealthBarText" }) or false
    rawset(_G, "EVAL_TH_REF_CACHE", ref)
  end
  return (ref ~= false) and ref or nil
end

-- ★只在「我们真的写过」时才清（**绝不动客户端自己的文字**）；无目标时调用
local function thClearClientText()
  local n = EVAL_TH.nt
  if not n.wrote then return end
  if n.fs and type(n.fs.SetText) == "function" then pcall(n.fs.SetText, n.fs, "") end
  n.wrote = false
end

-- 锚点：**客户端目标血条**（居中压上去）> 客户端目标框正下方 > 屏幕上方中央
local function thPlace(f)
  if not f then return nil end
  local bar = thClientBar()
  local native = thResolve({ "TargetFrame" })
  pcall(f.ClearAllPoints, f)
  if bar and type(bar.GetCenter) == "function" then
    -- ★居中压在客户端目标血条正中（这就是「居中显示到目标血量居中位置」）
    pcall(f.SetPoint, f, "CENTER", bar, "CENTER", 0, 0)
    EVAL_TH.anchorKind = "barCenter"
  elseif native then
    pcall(f.SetPoint, f, "TOPRIGHT", native, "BOTTOMRIGHT", 0, -6)
    EVAL_TH.anchorKind = "targetBelow"
  else
    local ui = rawget(_G, "UIParent")
    if not ui then return nil end
    pcall(f.SetPoint, f, "TOP", ui, "TOP", 0, -170)
    EVAL_TH.anchorKind = "screenTop"
  end
  -- 越界回归（本项目惯例：任何摆位都要能回屏内）
  local okL, l = pcall(f.GetLeft, f)
  if okL and tonumber(l) and tonumber(l) < 0 and EVAL_TH.anchorKind ~= "screenTop" then
    local ui = rawget(_G, "UIParent")
    if ui then
      pcall(f.ClearAllPoints, f)
      pcall(f.SetPoint, f, "TOP", ui, "TOP", 0, -170)
      EVAL_TH.anchorKind = "screenTop"
    end
  end
  return EVAL_TH.anchorKind
end

thEnsure = function()
  if EVAL_TH.frame then return EVAL_TH.frame end

  local f = CreateFrame("Frame", "EVAL_TH_FRAME", UIParent)
  -- ★帧名 ≠ 任何全局函数名（具名帧会顶掉同名全局函数，本项目组 54 老坑）
  f:SetWidth(TH_W)
  f:SetHeight(TH_BAR_H + 2)
  if type(f.SetFrameStrata) == "function" then pcall(f.SetFrameStrata, f, "MEDIUM") end
  if type(f.SetFrameLevel) == "function" then pcall(f.SetFrameLevel, f, 10) end
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, false) end   -- ★纯显示，不抢点击

  -- 板（金边 + 暗底 + 关系色填充）**只在「连客户端目标框都没有」的 fallback 模式下显示**；
  -- 正常情况（客户端目标框在）我们**只画那串白字**，条本身用客户端自己的（1.75.114 用户截图改判）。
  local border = f:CreateTexture(nil, "BACKGROUND")
  thSolid(border, 0.42, 0.35, 0.16, 0.95)                       -- 金边（同单位框那种描边）
  border:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  local bg = f:CreateTexture(nil, "ARTWORK")
  thSolid(bg, 0.05, 0.05, 0.05, 0.88)                           -- 暗底
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

  local fill = f:CreateTexture(nil, "ARTWORK")
  thSolid(fill, 0.20, 0.85, 0.25, 1)                            -- 血条填充（颜色每拍按关系给）
  fill:SetPoint("TOPLEFT", bg, "TOPLEFT", 1, -1)
  fill:SetHeight(TH_BAR_H - 4)
  fill:SetWidth(1)

  -- ★只有这一串文字（**不再有名字行**：客户端目标框自己已经把名字写在血条上方了 —— 用户截图里
  --   我们自己那条「名字 + 绿条」是重复信息，已按 1.75.114 改判删除）
  local text = f:CreateFontString("EVAL_TH_TEXT", "OVERLAY")
  text:SetPoint("CENTER", f, "CENTER", 0, 0)
  text:SetJustifyH("CENTER")
  thFontOf(text, TH_FONT_SIZE)
  if type(text.SetShadowOffset) == "function" then pcall(text.SetShadowOffset, text, 1, -1) end
  if type(text.SetShadowColor) == "function" then pcall(text.SetShadowColor, text, 0, 0, 0, 0.9) end

  pcall(f.Hide, f)
  EVAL_TH.frame, EVAL_TH.border, EVAL_TH.bg, EVAL_TH.fill, EVAL_TH.text =
    f, border, bg, fill, text
  EVAL_TH.built = true
  thPlace(f)
  return f
end

-- ===== 绘制（**唯一绘制口**；值没变就一个 Set* 都不发） =====
thPaint = function(force)
  local f = EVAL_TH.frame
  if not f then return false end
  if not EVAL_TH_ENABLED() then return false end

  local exists = false
  if type(UnitExists) == "function" then local ok, v = pcall(UnitExists, "target") exists = (ok and v) and true or false end
  if not exists then
    if EVAL_TH.shown then pcall(f.Hide, f) EVAL_TH.shown = false end
    thClearClientText()                      -- 客户端那条文字也别留着上一只怪的读数
    EVAL_TH.lastKey, EVAL_TH.verdict = nil, "无目标"
    EVAL_TH.mode = nil
    return false
  end

  local nm, lvl, hp, hpmax = nil, nil, nil, nil
  if type(UnitName) == "function" then local ok, v = pcall(UnitName, "target") if ok and type(v) == "string" then nm = v end end
  if type(UnitLevel) == "function" then local ok, v = pcall(UnitLevel, "target") if ok then lvl = tonumber(v) end end
  if type(UnitHealth) == "function" then local ok, v = pcall(UnitHealth, "target") if ok then hp = tonumber(v) end end
  if type(UnitHealthMax) == "function" then local ok, v = pcall(UnitHealthMax, "target") if ok then hpmax = tonumber(v) end end
  if not nm then nm = "?" end
  if not hp or not hpmax or hpmax <= 0 then
    if EVAL_TH.shown then pcall(f.Hide, f) EVAL_TH.shown = false end
    thClearClientText()
    EVAL_TH.verdict = "血量读不到（UnitHealth / UnitHealthMax 没给值）"
    return false
  end

  local pct = thRound(hp / hpmax * 100)
  local key = nm .. ":" .. tostring(lvl) .. ":" .. tostring(pct)
  if (not force) and key == EVAL_TH.lastKey and EVAL_TH.shown then return true end

  EVAL_TH.visits = EVAL_TH.visits + 1

  local cur, maxv, src
  -- ★`UnitHealthMax == 100` + 「这个单位客户端本来就给绝对值」= **百分比单位**
  if hpmax == 100 and not thAbsoluteUnit("target") then
    local mH = thMaxHealth(nm, lvl)
    if mH then
      maxv, cur, src = mH, thRound(mH * hp / hpmax), "table"
      EVAL_TH.hits = EVAL_TH.hits + 1
      EVAL_TH.verdict = string.format("%s L%s → 表命中：上限 %s（精确），当前 %s = 上限 × %d%%",
        nm, tostring(lvl), thNum(mH), thNum(cur), pct)
    else
      src = "pct"
      EVAL_TH.fallbacks = EVAL_TH.fallbacks + 1
      local why = (not lvl or lvl < 1) and "等级 -1（骷髅/世界首领，官方口径）" or "名字+等级不在表里"
      EVAL_TH.verdict = string.format("%s L%s → 查不到（%s）⇒ 只显示百分比", nm, tostring(lvl), why)
      local mk = nm .. ":" .. tostring(lvl)
      if not EVAL_TH.missSeen[mk] then
        EVAL_TH.missSeen[mk] = true
        EVAL_TH.misses = EVAL_TH.misses + 1
        thRing("★查不到：" .. tostring(EVAL_TH.verdict))
      end
    end
  else
    cur, maxv, src = hp, hpmax, "absolute"
    EVAL_TH.verdict = string.format("%s → 客户端给绝对值：%s / %s（不查表）", nm, thNum(cur), thNum(maxv))
  end

  -- 颜色：敌对红 / 中立黄 / 友善绿（拿不到关系就白）
  local cr, cg, cb = 0.92, 0.92, 0.92
  if type(UnitReaction) == "function" then
    local ok, v = pcall(UnitReaction, "player", "target")
    local r = ok and tonumber(v) or nil
    if r then
      if r <= 3 then cr, cg, cb = 0.90, 0.22, 0.18          -- 敌对
      elseif r == 4 then cr, cg, cb = 0.92, 0.82, 0.20      -- 中立
      else cr, cg, cb = 0.20, 0.85, 0.25 end                -- 友善
    end
  end

  -- 文本 = 按「数值 / 百分比」两项选择现拼（`/eh go 目标血量 设置` 或工具箱 [设置] 里改）
  local showVal, showPct = thOpts()
  local body
  if src == "pct" then
    -- ★如实降级：没有绝对值就只报百分比 —— **不管用户勾没勾「数值」**（数值本来就不存在，
    --   绝不为了迎合选择去编一个数字；这是本模块的口径②，比显示偏好优先级更高）
    body = string.format("%d%%", pct)
  elseif showVal and showPct then
    body = string.format("%s / %s (%d%%)", thNum(cur), thNum(maxv), pct)
  elseif showVal then
    body = string.format("%s / %s", thNum(cur), thNum(maxv))
  else
    body = string.format("%d%%", pct)
  end

  -- ★★★呈现（1.75.114 按用户截图改判：**只画白字数值、居中压在目标血条上**，不再画自己的名字与绿条）：
  --   ① `clientText`（首选）＝ 直接写客户端目标框那条血条文字（它本来就居中在血条上、字体颜色就是玩家框同款）；
  --   ② `overlay`  ＝ 写不进去（客户端会顶掉 / 没有那个 FontString）⇒ 用自己的 FontString 居中压在客户端血条上；
  --   ③ `plate`    ＝ 连客户端目标框都没有（自定义 UI）⇒ 才画我们自己的板 + 关系色填充 + 居中白字。
  local fs, mode = thClientText(), nil
  if fs and EVAL_TH.nt.mode ~= "overlay" then
    pcall(fs.SetText, fs, body)
    local okB, back = pcall(fs.GetText, fs)
    if okB and back == body then
      EVAL_TH.nt.fails, EVAL_TH.nt.back, EVAL_TH.nt.wrote = 0, body, true
      mode = "clientText"
    else
      -- ★写后自证：客户端把文字顶掉了 / 读不回 ⇒ 连续 N 次就退回自建覆盖层（**有界**，不是每拍重试到底）
      EVAL_TH.nt.fails = (tonumber(EVAL_TH.nt.fails) or 0) + 1
      EVAL_TH.nt.back = okB and tostring(back) or "读不回"
      if EVAL_TH.nt.fails >= TH_READBACK_FAIL_MAX then
        EVAL_TH.nt.mode = "overlay"
        thRing("★客户端目标条文字写不进去（读回=" .. tostring(EVAL_TH.nt.back) .. "）⇒ 退回自建覆盖层（居中压在血条上）")
      end
      mode = "overlay"
    end
  else
    mode = thClientBar() and "overlay" or "plate"
  end
  if mode == "clientText" then
    -- 用客户端那行文字 ⇒ 我们自己的层全部收起（一个像素都不多画）
    if EVAL_TH.shown then pcall(f.Hide, f) EVAL_TH.shown = false end
  else
    local plate = (mode == "plate")
    if type(EVAL_TH.border.Show) == "function" then
      if plate then
        pcall(EVAL_TH.border.Show, EVAL_TH.border) pcall(EVAL_TH.bg.Show, EVAL_TH.bg)
      else
        pcall(EVAL_TH.border.Hide, EVAL_TH.border) pcall(EVAL_TH.bg.Hide, EVAL_TH.bg)
      end
    end
    if type(EVAL_TH.fill.Show) == "function" then
      if plate then pcall(EVAL_TH.fill.Show, EVAL_TH.fill) else pcall(EVAL_TH.fill.Hide, EVAL_TH.fill) end
    end
    -- ★文字一律**白色**（用户：「白色文字参考玩家头像的数值」）：能读到玩家框那行就照抄它的字体串 + 颜色
    local ref = thRefText()
    if ref and EVAL_TH.refApplied ~= ref then
      EVAL_TH.refApplied = ref
      local okF, path, size, flags = pcall(ref.GetFont, ref)
      if okF and type(path) == "string" and tonumber(size) then
        pcall(EVAL_TH.text.SetFont, EVAL_TH.text, path, tonumber(size), flags)
      end
      local okC, r2, g2, b2 = pcall(ref.GetTextColor, ref)
      if okC and tonumber(r2) and tonumber(g2) and tonumber(b2) then
        pcall(EVAL_TH.text.SetTextColor, EVAL_TH.text, r2, g2, b2)
      else
        pcall(EVAL_TH.text.SetTextColor, EVAL_TH.text, 1, 1, 1)
      end
    elseif not ref and EVAL_TH.refApplied ~= "white" then
      EVAL_TH.refApplied = "white"
      pcall(EVAL_TH.text.SetTextColor, EVAL_TH.text, 1, 1, 1)
    end
    if type(EVAL_TH.text.SetText) == "function" then pcall(EVAL_TH.text.SetText, EVAL_TH.text, body) end
    if plate then
      if type(EVAL_TH.fill.SetVertexColor) == "function" then
        if src == "pct" then
          pcall(EVAL_TH.fill.SetVertexColor, EVAL_TH.fill, 0.55, 0.55, 0.55, 1)   -- 降级态：灰条
        else
          pcall(EVAL_TH.fill.SetVertexColor, EVAL_TH.fill, cr, cg, cb, 1)         -- 与单位框同一套关系色
        end
      end
      -- 条长 = 客户端百分比（我们绝不自己算比例：那是客户端的事）
      local frac = hp / hpmax
      if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
      if type(EVAL_TH.fill.SetWidth) == "function" then
        pcall(EVAL_TH.fill.SetWidth, EVAL_TH.fill, math.max(1, math.floor((TH_W - 4) * frac + 0.5)))
      end
    end
    if not EVAL_TH.shown then pcall(f.Show, f) EVAL_TH.shown = true end
  end
  EVAL_TH.mode = mode
  EVAL_TH.lastKey = key
  return true
end

-- ===== 节拍 / 事件（挂摘唯一入口：thSync） =====
local TH_EVENTS = { "PLAYER_TARGET_CHANGED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "PLAYER_ENTERING_WORLD" }

thTick = function()
  local now = (type(GetTime) == "function") and (GetTime() or 0) or 0
  if now - EVAL_TH.lastPaint < TH_TICK then return end
  EVAL_TH.lastPaint = now
  -- ★每拍第一件事：重问「还要不要跑」（自愈 —— 开关被别的路径关掉 ⇒ 当拍自己摘，不靠外部标志）
  if not EVAL_TH_ENABLED() then thSync(false) return end
  pcall(thPaint)
end

thSync = function(on)
  local f = EVAL_TH.frame
  if not f then return false end
  if on then
    for i = 1, table.getn(TH_EVENTS) do pcall(f.RegisterEvent, f, TH_EVENTS[i]) end
    -- 事件去抖：只重画，不重挂（挂/摘永远只有这一处）
    if type(f.SetScript) == "function" then
      f:SetScript("OnEvent", function()
        local now = (type(GetTime) == "function") and (GetTime() or 0) or 0
        if now - EVAL_TH.lastPaint < TH_EVENT_GAP then return end
        EVAL_TH.lastPaint = now
        pcall(thPaint)
      end)
      f:SetScript("OnUpdate", thTick)
    end
    EVAL_TH.on = true
    return true
  end
  for i = 1, table.getn(TH_EVENTS) do pcall(f.UnregisterEvent, f, TH_EVENTS[i]) end
  if type(f.SetScript) == "function" then
    f:SetScript("OnEvent", nil)
    f:SetScript("OnUpdate", nil)     -- ★真摘（不是每帧早退）
  end
  EVAL_TH.on = false
  return false
end

-- ===== 应用（开/关；**唯一应用口**） =====
thApply = function(on)
  if on then
    if not thVitals() then
      thRing("★数据缺失：UnitVitalsData.lua 没载入 ⇒ 目标生命值显示不可用（只显示客户端百分比）")
      return false
    end
    if not thIndex() then return false end
    thEnsure()
    thPlace(EVAL_TH.frame)
    thSync(true)
    pcall(thPaint, true)
    return true
  end
  -- 关：① 真摘事件与节拍 ② 收我们自建的层 ③ 把借来的客户端文字**按原值还回** ④ 会话态复位
  thSync(false)
  -- ★③「改属性前先抓原值」的同一把尺子：我们只借客户端那条 FontString 的**文字**，关掉要还回它
  --   原本的内容（我们没动它的字体/颜色/位置 ⇒ 只还文字这一样）
  local n = EVAL_TH.nt
  if n.fs and n.wrote and type(n.fs.SetText) == "function" then
    pcall(n.fs.SetText, n.fs, n.orig or "")
  end
  n.fs, n.tried, n.mode, n.fails, n.back, n.wrote = nil, false, nil, 0, nil, false
  -- 客户端句柄缓存也清（下次开重新解析：客户端可能在这期间重建过自己的单位框）
  rawset(_G, "EVAL_TH_BAR_CACHE", nil)
  rawset(_G, "EVAL_TH_REF_CACHE", nil)
  EVAL_TH.refApplied = nil
  if EVAL_TH.frame then pcall(EVAL_TH.frame.Hide, EVAL_TH.frame) end
  EVAL_TH.shown = false
  EVAL_TH.mode = nil
  EVAL_TH.cache, EVAL_TH.cacheN = {}, 0
  EVAL_TH.lastKey, EVAL_TH.verdict = nil, "已关闭"
  EVAL_TH.visits, EVAL_TH.hits, EVAL_TH.misses, EVAL_TH.fallbacks = 0, 0, 0, 0
  EVAL_TH.missSeen = {}
  return false
end

-- ===== 唯一写口（工具箱勾选框 / `/eh go 目标血量 开|关` 都走它） =====
function EVAL_TH_SET(on)
  on = on and true or false
  local tb = thTb()
  -- ★★★顺序即判据：**先把真值写进 tbCfg()，再应用** —— `thApply` 里的绘制会读 `EVAL_TH_ENABLED()`，
  --   反过来写就会「开的那一下画不出来」（要等下一拍 OnUpdate 才补上 = 用户眼里的点了没反应）。
  if type(tb) == "table" then tb.targetHealth = on end
  local ok = thApply(on)
  if on and not ok then
    -- ★勾上了却显示不出来 = 本项目最恨的静默态 ⇒ **开关回退成关** + 如实出声
    if type(tb) == "table" then tb.targetHealth = false end
    thSay(L("TH_ON_FAIL"))
    return false
  end
  thSay(on and L("TH_ON_MSG") or L("TH_OFF_MSG"))
  return on
end

-- 载入期之后（存档已可读）按真值应用一次；幂等
function EVAL_TH_INSTALL()
  if EVAL_TH_ENABLED() then thApply(true) end
  return true
end

-- ===== 工具箱模块行（Toolbox 侧只有一行数据 `{ t="mod", mod="targetHealth", ... }`） =====
-- ★1.75.114：右侧两颗 —— **[设置]**（`r.add`，下拉多选：数值 / 百分比）+ **[状态]**（把当前判定摊开）
--   ★为什么把「状态」保留成独立一颗：真机排查时它是最常用的那一下，塞进下拉里就等于多两次点击。
-- ★★★1.75.115 修（真机报障「下拉开不出来」）：[状态] **必须用 `r.clr`（cRight−48 宽 40）**，
--   **绝不许用 `r.chv`** —— chv 是 **88 宽、起点 cRight−96**，与 [设置] 的 add 槽（cRight−96 宽 44）
--   **完全重叠**；chv 在 Toolbox 里**后建** ⇒ 压在 add 上面 ⇒ **点「设置」永远到不了下拉**（点到的其实是
--   这一颗），而「按钮存在 + OnClick 挂上了」的行为断言**照样全绿**（遮挡是断言盲区）。
--   ★同案原话与判据锚点 = `tools/DragFrames.lua:6069`（那里也写着「绝不许用 r.chv」）；
--   常驻闸门 = `tmp/th_smoke.js` 的结构钉（源码里不许出现 chv 的 btn/text 引用）。
local thRow = function(r, it)
  if type(r) ~= "table" then return false end
  local function dataStr() return thVitals() and "有" or "没有" end
  local function tipHead(tip, btn, firstLine)
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return false end
    pcall(tip.SetMinimumWidth, tip, 320)
    pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, firstLine, 1, 0.85, 0.30)
    return true
  end
  local function tipHide()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end
  local function curOpt(which)
    local val, pct = thOpts()
    if which == "val" then return val end
    return pct
  end
  local function applyOpt(which, on)
    -- ★`on` 为 nil（组件没报新状态）时**按当前真值取反**，绝不默认成 false 把用户的选择抹掉
    if on == nil then on = not curOpt(which) end
    EVAL_TH_SETOPT(which, on == true)
  end

  r.get = function() return EVAL_TH_ENABLED() end
  r.set = function(v) EVAL_TH_SET(v and true or false) end
  r.extra:Hide()                                   -- ★配置项只在 [设置] 的悬停里，行上不重复

  -- ① [设置]：多选下拉（数值 / 百分比，勾哪几样显示哪几样）
  r.add.text:SetText(L("TH_BTN_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    local val, pct, forced = thOpts()
    if not tipHead(tip, r.add.btn, (type(it) == "table" and it.tip) or L("TB_TARGETHEALTH_TIP")) then return end
    pcall(tip.AddLine, tip, L("TH_SET_TIP"), 0.88, 0.88, 0.88)
    pcall(tip.AddLine, tip, "　" .. (val and "√ " or "× ") .. L("TH_OPT_VAL"), 0.75, 0.95, 0.75)
    pcall(tip.AddLine, tip, "　" .. (pct and "√ " or "× ") .. L("TH_OPT_PCT"), 0.75, 0.95, 0.75)
    if forced then pcall(tip.AddLine, tip, L("TH_SET_TIP_EMPTY"), 0.95, 0.80, 0.45) end
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", tipHide)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then
      thSay(L("TH_NO_DD"))                         -- ★拿不到下拉就如实出声，绝不静默
      return
    end
    local val, pct = thOpts()
    local sel = {}
    if val then sel[1] = true end
    if pct then sel[2] = true end
    EVAL_DD_OPEN(r.add.btn, { L("TH_OPT_VAL"), L("TH_OPT_PCT") }, function(pi, on)
      if pi == 1 then applyOpt("val", on) end
      if pi == 2 then applyOpt("pct", on) end
    end, { multi = true, selected = sel })
  end)

  -- ② [状态]：把当前判定摊开（与 `/eh go 目标血量 状态` 同源）
  --   ★★★**只能用 `r.clr`**（cRight−48 宽 40）—— 见本函数上方 1.75.115 那条：`r.chv` 88 宽、与 [设置]
  --     的 add 槽完全重叠且后建压在上面 ⇒ 用它就等于**把 [设置] 点掉**（下拉永远开不出来）。
  --   ★`r.clr` 由 Toolbox 提供（每行都有）；**缺了就跳过**（渲染半途报错会让整行控件停在半成品状态）
  if type(r.clr) == "table" and type(r.clr.text) == "table" and type(r.clr.btn) == "table" then
    r.clr.text:SetText(L("TH_BTN_STATE"))
    r.clr.btn:Show()
    r.clr.btn:SetScript("OnEnter", function()
      local tip = _G["GameTooltip"]
      if not tipHead(tip, r.clr.btn, L("TH_BTN_STATE")) then return end
      -- ★这里必须用**带格式**的那一条（`TH_SET_TIP_DATA` 是含 `%s/%s/%d` 的格式串；
      --   把它当普通行直接 AddLine 出来就是「数据表 %s ｜ 名字索引 %s」原样画在屏幕上）
      pcall(tip.AddLine, tip, string.format(L("TH_SET_TIP_DATA"), dataStr(), tostring(EVAL_TH.indexState or "未建"), tonumber(EVAL_TH.indexN) or 0), 0.75, 0.85, 0.95)
      pcall(tip.AddLine, tip, tostring(EVAL_TH.verdict or "—"), 0.75, 0.95, 0.75)
      pcall(tip.Show, tip)
    end)
    r.clr.btn:SetScript("OnLeave", tipHide)
    r.clr.btn:SetScript("OnClick", function() EVAL_TH_CMD("状态") end)
  end
  return true
end

local TH_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(TH_TB_ROWS) ~= "table" then
  TH_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", TH_TB_ROWS)
end
TH_TB_ROWS["targetHealth"] = thRow

-- ===== 读值口 / 命令 =====
function EVAL_TH_TEST_STATE()
  local val, pct, forced = thOpts()
  local n = EVAL_TH.nt
  return {
    on = EVAL_TH.on, enabled = EVAL_TH_ENABLED(), built = EVAL_TH.built, shown = EVAL_TH.shown,
    anchor = EVAL_TH.anchorKind, mode = EVAL_TH.mode, data = (thVitals() ~= nil),
    indexN = EVAL_TH.indexN, indexState = EVAL_TH.indexState, cacheN = EVAL_TH.cacheN,
    visits = EVAL_TH.visits, hits = EVAL_TH.hits, misses = EVAL_TH.misses, fallbacks = EVAL_TH.fallbacks,
    optVal = val, optPct = pct, optForced = forced,
    clientTextFound = (n.fs ~= nil), clientTextWrote = n.wrote and true or false,
    clientTextBack = n.back, clientTextFails = n.fails, clientTextOrig = n.orig,
    verdict = EVAL_TH.verdict,
  }
end

local function thRd(fn, a1, a2)
  if type(fn) ~= "function" then return "?" end
  local ok, v = pcall(fn, a1, a2)
  if not ok or v == nil then return "?" end
  return tostring(v)
end

local function thStateLines()
  local s = EVAL_TH_TEST_STATE()
  local out = {}
  out[#out + 1] = string.format("目标生命值显示：%s ｜ 帧 %s ｜ 呈现 %s ｜ 锚点 %s",
    s.enabled and "开" or "关", s.built and "已建" or "未建",
    tostring(s.mode or "—"), tostring(s.anchor or "—"))
  -- 呈现那条腿的取证：客户端目标条那行文字到底找没找到 / 写没写进去 / 读回是什么（真机一眼定位）
  out[#out + 1] = string.format("客户端血条文字：%s ｜ 写过 %s ｜ 读回 %s ｜ 连续写失败 %d ｜ 原值「%s」",
    s.clientTextFound and "找到" or "★没找到（改用自建覆盖层）",
    s.clientTextWrote and "是" or "否", tostring(s.clientTextBack or "—"),
    tonumber(s.clientTextFails) or 0, tostring(s.clientTextOrig or ""))
  out[#out + 1] = string.format("数据表 %s ｜ 名字索引 %s（%d 条）｜ 缓存 %d 条 ｜ 本会话 判定 %d ｜ 命中 %d ｜ 降级 %d ｜ 查不到 %d",
    s.data and "已载入" or "★没载入", tostring(s.indexState or "未建"), s.indexN, s.cacheN,
    s.visits, s.hits, s.fallbacks, s.misses)
  -- 显示内容（1.75.114）：数值 / 百分比 两项选择 + 是否走了「两个都不勾」的兜底
  local o = {}
  if s.optVal then o[#o + 1] = L("TH_OPT_VAL") end
  if s.optPct then o[#o + 1] = L("TH_OPT_PCT") end
  out[#out + 1] = string.format("显示内容：%s%s ｜ 改法：工具箱 [设置] 下拉（多选）或 /eh go 目标血量 数值 on|off ｜ 百分比 on|off",
    table.concat(o, " ｜ "), s.optForced and ("（" .. L("TH_SET_TIP_EMPTY") .. "）") or "")
  out[#out + 1] = "当前：" .. tostring(s.verdict or "—")
  -- 只读口里带上「客户端对这个目标到底给了什么」——真机取证时一眼分清「表没中」与「客户端本来给绝对值」
  local okE, has = pcall(UnitExists, "target")
  if okE and has then
    out[#out + 1] = string.format("目标读数（只读）：名 %s ｜ 等级 %s ｜ UnitHealth %s ｜ UnitHealthMax %s ｜ 关系 %s ｜ 本来给绝对值 %s",
      thRd(UnitName, "target"), thRd(UnitLevel, "target"), thRd(UnitHealth, "target"),
      thRd(UnitHealthMax, "target"), thRd(UnitReaction, "player", "target"),
      thAbsoluteUnit("target") and "是" or "否")
  end
  out[#out + 1] = "口径：上限 = 本服生物表复算（精确）｜ 当前 = 上限 × 客户端百分比（±1% 上限，非独立读数）"
  return out
end

local function thRingLines(n)
  local out = thCfg().thProbe.out
  local lines, total = {}, table.getn(out)
  local from = total - (tonumber(n) or 8) + 1
  if from < 1 then from = 1 end
  for i = from, total do lines[#lines + 1] = out[i] end
  if table.getn(lines) == 0 then lines[1] = "（取证环还是空的）" end
  return lines
end

function EVAL_TH_CMD(msg)
  local m = tostring(msg or "")
  m = string.gsub(m, "^%s*go%s+", "")
  m = string.gsub(m, "^%s*目标血量%s*", "")
  m = string.gsub(m, "^%s+", "")
  m = string.gsub(m, "%s+$", "")
  if m == "" or m == "状态" or m == "state" then
    local ls = thStateLines()
    for i = 1, table.getn(ls) do thSay(ls[i]) end
    thSay("用法：" .. L("TH_USAGE"))
  elseif m == "开" or m == "on" then
    EVAL_TH_SET(true)
  elseif m == "关" or m == "off" then
    EVAL_TH_SET(false)
  elseif m == "探针" or m == "probe" then
    if EVAL_TH_ENABLED() and EVAL_TH.frame then pcall(thPaint, true) end
    local ls = thStateLines()
    for i = 1, table.getn(ls) do thSay(ls[i]) end
    thSay("落盘环 cfg.thProbe（上限 " .. TH_RING_MAX .. " 行）⇒ /reload 后我直接读存档")
  elseif m == "存档" or m == "log" then
    local ls = thRingLines(10)
    for i = 1, table.getn(ls) do thSay("  " .. ls[i]) end
  elseif m == "清" or m == "clear" then
    EVAL_TH.cache, EVAL_TH.cacheN = {}, 0
    EVAL_TH.missSeen, EVAL_TH.misses = {}, 0
    thCfg().thProbe = { out = {} }
    thSay("目标生命值显示：缓存与取证环已清空")
  elseif m == "位置" or m == "pos" then
    if not EVAL_TH.frame then thSay("还没建帧（先把开关打开）") return true end
    thSay("锚点：" .. tostring(thPlace(EVAL_TH.frame)) .. "（native = 贴客户端目标框下方；fallback = 屏幕上方中央）")
  elseif m == "设置" or m == "opt" or m == "options" then
    -- 只读回显当前选择（真机排查「我到底勾了哪两样」一眼可见）
    local s = EVAL_TH_TEST_STATE()
    local o = {}
    if s.optVal then o[#o + 1] = L("TH_OPT_VAL") .. " √" end
    if s.optPct then o[#o + 1] = L("TH_OPT_PCT") .. " √" end
    if s.optForced then o[#o + 1] = L("TH_SET_TIP_EMPTY") end
    thSay("显示内容：" .. (table.getn(o) > 0 and table.concat(o, " ｜ ") or L("TH_SET_TIP_EMPTY")))
    thSay("用法：" .. L("TH_USAGE"))
  elseif string.sub(m, 1, 6) == "数值" or string.sub(m, 1, 9) == "百分比" then
    -- `/eh go 目标血量 数值 [on|off]` / `百分比 [on|off]`（不给 on|off = 取反，方便真机敲）
    local which = (string.sub(m, 1, 6) == "数值") and "val" or "pct"
    local rest = string.gsub(m, "^数值%s*", "")
    rest = string.gsub(rest, "^百分比%s*", "")
    rest = string.lower(string.gsub(rest, "%s+$", ""))
    local on
    if rest == "on" or rest == "开" or rest == "1" then on = true
    elseif rest == "off" or rest == "关" or rest == "0" then on = false
    elseif rest == "" then
      local v, p = thOpts()
      on = not ((which == "val") and v or ((which == "pct") and p or false))
    else
      thSay("参数看不懂 ⇒ " .. L("TH_USAGE"))
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
      return true
    end
    EVAL_TH_SETOPT(which, on)
    return true
  else
    thSay("未知子命令 ⇒ " .. L("TH_USAGE"))
  end
  if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
  return true
end
