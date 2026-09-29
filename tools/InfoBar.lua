-- EvalHelp · tools/InfoBar.lua —— 顶部信息条（1.75.40 新增）
--
-- 来源：移植自开源插件 **SimpleInfoBar**（https://github.com/vivk-17/SimpleInfoBar，MIT，
--   Copyright (c) 2026 vivk-17）。原版是「一个 Frame + 一个 FontString」的六段信息条：
--   区域 · 金钱 · 背包 · 网络 · 专业 · 内存。移植时**保留功能口径、重做实现与外观**：
--   · 界面文案走本项目**国际化规范**（三语语言包的 `IB_*` 键 + 本文件自带的 `local function L(k)`）；
--   · 字体走**客户端字体对象链**（不写死任何 .ttf 路径 —— 用户要求「不需要特殊字体」；
--     真机截图已证 `GameFontNormalSmall` 能正常渲染中文）；
--   · 外观重做（深色玻璃板 + 1px 细金框 + 段间暗竖线 + 悬停提亮 + 锁定变灰 = 看得见的锁定反馈）；
--   · 交互重做（拖动柄 = Button，符合本项目铁律；右键设置 = `EVAL_DD_OPEN` 多选下拉，不再自建菜单）；
--   · 刷新改**事件驱动 + 分块脏标记**（原版每 0.5s 无条件全量扫包，满包约 140 次 API/秒）。
--
-- ★★★模块纪律（CLAUDE.md §4.1 / §5.1）：
--   · **载入期零副作用**：顶层只声明 + 把渲染函数登记进 `EVAL_TB_MOD_ROWS`；不建帧/不挂事件/不读存档/不建计时器。
--   · **只调全局桥**（一律「调用时读」）：`EVAL_L` / `EVAL_SAY` / `EVAL_TB_CFG` / `EVAL_HELP_CONFIG` / `EVAL_DD_OPEN`。
--     绝不引用宿主 local（宿主里 `L`/`say`/`c()` 都是文件局部 ⇒ 在模块里绑成全局 nil 会被 pcall 吞掉）。
--   · **关掉零动作**：总开关 `tbCfg().infoBar` 闸在一切探测/读写**之前**；关掉 = 摘掉全部事件 + 摘掉 OnUpdate + 隐藏面板，
--     之后一个 API 都不再发（帧保留复用，不销毁，避免下次重建）。
--
-- ★真值只有两处（单一来源，不再开第二份）：
--   · 主开关 = 工具箱表 `tbCfg().infoBar`（读写走本文件的 `EVAL_IB_ENABLED()` / `EVAL_IB_SET()`）；
--   · 子配置 = `EVAL_HELP_CONFIG.infoBarCfg`（本模块自己的子树：分块开关/顺序/标签/背景/锁定/位置/字号/透明度）。
--   ★**绝不复用**原插件的 `SimpleInfoBarDB`（键名与语义都不同，导入只会造成两处真值打架）。
--
-- ★已核实（本地 api_*.html 的 1370 条索引 + emberveil wiki 原文）：
--   `GetNetStats()` 返回 3 个值（in KB/s、out KB/s、**latency ms**）；
--   `GetSubZoneText()` 无子区时**不返回值**（不是 ""）；
--   `GetScriptMemory()` = GC 字节数换算成向下取整的整 MB；
--   `GetSkillLineInfo(i)` 返回 **12 个值**，第 7 = `skillMaxRank`、第 8 = `isAbandonable`（`1` 或 `nil`）；
--   `isExpanded` / `isAbandonable` 是 `1`/`nil` 而**不是** true/false（wiki 明写）。
--   ★`GetContainerItemInfo` 空槽的纹理是 `""`（Lua 里是**真值**）⇒ 必须显式比 `nil` 与 `""`。

local IB = {
  built = false,        -- 帧是否已建（读值口）
  evArmed = false,      -- 事件是否在跑（读值口）
  root = nil, text = nil, evF = nil,
  seg = {},             -- [key] = 该分块上一次算好的文本（脏了才算）
  dZone = true, dMoney = true, dBags = true, dProf = true, dNet = true, dMem = true,
  free = 0, total = 0,  -- 背包空格（tooltip 用）
  lastText = nil,       -- 上一帧写进 FontString 的整串（内容没变就一个 API 都不发）
  acc = 0,              -- 0.5s 累加器
  hover = false,
  memShown = "0",       -- 最近一次算出的内存显示串（tooltip / 探针用）
  memMB = nil,          -- 最近一次算出的 Lua 堆 MB（探针 / tooltip 判重都用它）
  uncat = {},           -- ★自诊断：被判为「非专业」而没显示、但 maxRank>1 的技能行（见 ibSegProf）
  out = {},             -- 有界取证环（落盘 cfg.ibProbe）
}

local IB_OUT_MAX = 40
local IB_H = 22          -- 条高（★真机实测后由 20 提到 22：12pt 中文上下更透气）
local IB_PAD = 16        -- ★左内边距（真机实测后由 10 提到 16：用户要求「尺寸可以宽一点」）
local IB_RPAD = 4        -- ★右内边距（用户：「右边位置不要设置边距试下，缩小点」⇒ 由 16+6 收到 4）
local IB_PERIOD = 0.5    -- 刷新节拍（网络/内存靠它；其余分块走事件）

-- 可开关的分块与设置项（多选下拉的行序 = 这里的顺序；唯一来源）
local OPT = {
  { key = "zone", label = "IB_SEG_ZONE" },
  { key = "money", label = "IB_SEG_MONEY" },
  { key = "bags", label = "IB_SEG_BAGS" },
  { key = "net", label = "IB_SEG_NET" },
  { key = "prof", label = "IB_SEG_PROF" },
  { key = "mem", label = "IB_SEG_MEM" },
  { key = "labels", label = "IB_OPT_LABELS" },
  { key = "bg", label = "IB_OPT_BG" },
  { key = "locked", label = "IB_OPT_LOCK" },
}

----------------------------------------------------------------------
-- 全局桥（★一律调用时读，载入期不抓快照 —— 本项目老雷）
----------------------------------------------------------------------

local function ibConf()
  local t = rawget(_G, "EVAL_HELP_CONFIG")
  return (type(t) == "table") and t or nil
end

local function ibTb()
  if type(EVAL_TB_CFG) == "function" then return EVAL_TB_CFG() end
  return ibConf()
end

-- ★模块必须自带 L（走 EVAL_L）：项目里 L 一律是文件局部，裸调会绑全局 nil 并被 pcall 吞掉。
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function ibSay(s)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, s) end
end

----------------------------------------------------------------------
-- 配置
----------------------------------------------------------------------

local DEF = {
  point = "TOP", relPoint = "TOP", x = 0, y = -18,
  zone = true, money = true, bags = true, net = true, prof = true, mem = true,
  labels = true,     -- 段前的暗灰小题（关掉只剩纯值，更紧凑）
  bg = true,         -- 深色玻璃板（关掉 = 只有文字浮在世界之上）
  locked = false,
  order = "zone,money,bags,net,prof,mem",
  font = 12,
  -- ★面板底色不透明度：**与「姓名右键弹窗」同款 0.88**（用户要求背景照那个弹窗来）
  alpha = 0.88,
  -- ★边框颜色 / 浓度（用户：「边框颜色能设置么?」+「边框透明度可以低一点」）——
  --   颜色 = 5 档循环；浓度 = 0.40 起（原 0.75 太抢眼，用户要求「低一点」）。
  borderColor = "white",
  borderAlpha = 0.40,
  skinVer = 2,       -- ★皮肤改版标记（见 ibCfg 的一次性迁移）：老存档那份 0.62 是旧设计
  -- 专业阈值：距技能上限**还剩多少点**转色（bad=红、warn=黄）。三档预设见 THR。
  profBad = 10,
  profWarn = 25,
}

local SEG_ORDER_DEF = { "zone", "money", "bags", "net", "prof", "mem" }

local function ibCfg()
  local root = ibConf()
  if type(root) ~= "table" then root = {} rawset(_G, "EVAL_HELP_CONFIG", root) end
  local c = root.infoBarCfg
  if type(c) ~= "table" then c = {} root.infoBarCfg = c end
  -- ★★★一次性迁移（皮肤改版）**必须排在「补默认值」之前**：
  --   老存档里没有 skinVer 这个键，而 DEF 里**有** ⇒ 先补默认就会把它补成 2，
  --   于是 `c.skinVer ~= 2` 永远为假、迁移永远不触发（本模块 harness 当场抓到这条）。
  --   口径：底色改为「姓名右键弹窗」同款 0.88；老存档那份 0.62 是**旧设计**，
  --   而 alpha **没有任何界面入口**（不是用户自己设的）⇒ 直接顶掉，用 skinVer 保证只顶一次。
  if c.skinVer ~= 2 then c.skinVer = 2 c.alpha = DEF.alpha end
  for k, v in pairs(DEF) do
    if c[k] == nil then c[k] = v end   -- ★只补缺，绝不覆盖用户显式关掉的 false
  end
  return c
end

function EVAL_IB_ENABLED()
  local tb = ibTb()
  return (type(tb) == "table" and tb.infoBar == true) and true or false
end

-- 顺序串 → 数组（★照原版口径：字符串存盘、缺的项补在末尾 ⇒ 以后加块也不会丢）
local function ibOrder()
  local c = ibCfg()
  local raw = tostring(c.order or "")
  local list, n = {}, 0
  local rest = raw .. ","
  while true do
    local _, _, item, tail = string.find(rest, "^([^,]*),(.*)$")
    if not item then break end
    if item ~= "" then n = n + 1 list[n] = item end
    rest = tail
    if rest == "" then break end
  end
  local k = 1
  while SEG_ORDER_DEF[k] do
    local found, j = false, 1
    while j <= n do
      if list[j] == SEG_ORDER_DEF[k] then found = true end
      j = j + 1
    end
    if not found then n = n + 1 list[n] = SEG_ORDER_DEF[k] end
    k = k + 1
  end
  return list, n
end

----------------------------------------------------------------------
-- 取证环（★探针读数必须自带落盘：say 只进聊天框、不落日志环，AI 侧读存档才拿得到）
----------------------------------------------------------------------

local function ibRec(line)
  line = tostring(line or "")
  IB.out[table.getn(IB.out) + 1] = line
  while table.getn(IB.out) > IB_OUT_MAX do table.remove(IB.out, 1) end
  local root = ibConf()
  if type(root) == "table" then root.ibProbe = { out = IB.out } end
end

----------------------------------------------------------------------
-- 小工具
----------------------------------------------------------------------

-- 文本里的 "|" 会当色码分隔符 ⇒ 转义成 "||"（区域名/技能名理论上有这个可能）
local function ibEsc(s)
  s = tostring(s or "")
  if string.find(s, "|", 1, true) then s = string.gsub(s, "|", "||") end
  return s
end

local function ibNum(v, d)
  v = tonumber(v)
  if v == nil then return d end
  return v
end

-- 整屏尺寸（越界回归用）；取不到按 1024×768 兜底
local function ibScreen()
  local w, h = 1024, 768
  if type(GetScreenWidth) == "function" then local ok, v = pcall(GetScreenWidth) if ok and tonumber(v) then w = tonumber(v) end end
  if type(GetScreenHeight) == "function" then local ok, v = pcall(GetScreenHeight) if ok and tonumber(v) then h = tonumber(v) end end
  return w, h
end

----------------------------------------------------------------------
-- 数据分块（每块只在「脏了」时才被调用）
----------------------------------------------------------------------

local C_LABEL = "|cff8b8b8b"
local C_SEP = "|cff3a3a3a"
local C_WHITE = "|cffffffff"
local C_DIM = "|cff6f6f6f"
local C_GOOD = "|cff45ff45"
local C_WARN = "|cffffd200"
local C_BAD = "|cffff4040"
local C_GOLD = "|cffffd700"
local C_SILVER = "|cffc7c7cf"
local C_COPPER = "|cffeda55f"

local function ibLabel(key)
  if not ibCfg().labels then return "" end
  return C_LABEL .. L(key) .. "|r "
end

local function ibSegZone()
  local zone, sub = "", ""
  if type(GetZoneText) == "function" then
    local ok, v = pcall(GetZoneText)
    if ok and type(v) == "string" then zone = v end
  end
  if type(GetSubZoneText) == "function" then
    -- ★无子区时**返回零个值**（不是 ""）⇒ 这里 v 就是 nil，必须判类型
    local ok, v = pcall(GetSubZoneText)
    if ok and type(v) == "string" then sub = v end
  end
  if zone == "" and sub == "" then return nil end
  if zone == "" then zone, sub = sub, "" end
  local out = ibLabel("IB_SEG_ZONE") .. C_WHITE .. ibEsc(zone) .. "|r"
  if sub ~= "" and sub ~= zone then
    out = out .. " " .. C_DIM .. "· " .. ibEsc(sub) .. "|r"
  end
  return out
end

local function ibSegMoney()
  local copper = 0
  if type(GetMoney) == "function" then
    local ok, v = pcall(GetMoney)
    if ok then copper = ibNum(v, 0) end
  end
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local cc = copper - math.floor(copper / 100) * 100
  local parts, n = {}, 0
  if g > 0 then n = n + 1 parts[n] = C_GOLD .. g .. L("IB_GOLD") .. "|r" end
  if g > 0 or s > 0 then n = n + 1 parts[n] = C_SILVER .. s .. L("IB_SILVER") .. "|r" end
  n = n + 1 parts[n] = C_COPPER .. cc .. L("IB_COPPER") .. "|r"
  return ibLabel("IB_SEG_MONEY") .. table.concat(parts, " ")
end

local function ibSegNet()
  local fps, lag = 0, 0
  if type(GetFramerate) == "function" then
    local ok, v = pcall(GetFramerate)
    if ok then fps = math.floor(ibNum(v, 0) + 0.5) end
  end
  if type(GetNetStats) == "function" then
    -- ★本客户端返回三个值：in KB/s、out KB/s、latency ms（wiki 已核实）
    local ok, _, _, ms = pcall(GetNetStats)
    if ok then lag = math.floor(ibNum(ms, 0) + 0.5) end
  end
  local fc = C_BAD
  if fps >= 50 then fc = C_GOOD elseif fps >= 30 then fc = C_WARN end
  local lc = C_BAD
  if lag <= 100 then lc = C_GOOD elseif lag <= 250 then lc = C_WARN end
  return ibLabel("IB_SEG_NET")
    .. fc .. fps .. "|r" .. C_DIM .. " " .. L("IB_UNIT_FPS") .. "|r"
    .. " " .. C_SEP .. "·|r "
    .. lc .. lag .. "|r" .. C_DIM .. " " .. L("IB_UNIT_MS") .. "|r"
end

-- 背包：只在事件置脏时才算（原版每 0.5s 无条件全量扫，满包 ≈140 次 API/秒）
local function ibScanBags()
  local free, total = 0, 0
  if type(GetContainerNumSlots) ~= "function" or type(GetContainerItemInfo) ~= "function" then
    return free, total
  end
  local bag = 0
  while bag <= 4 do
    local ok, slots = pcall(GetContainerNumSlots, bag)
    slots = ok and ibNum(slots, 0) or 0
    if slots > 0 then
      total = total + slots
      local slot = 1
      while slot <= slots do
        local ok2, tex = pcall(GetContainerItemInfo, bag, slot)
        -- ★空槽的纹理是 ""（Lua 里是真值）⇒ 必须显式比 nil 与 ""
        if not ok2 or tex == nil or tex == "" then free = free + 1 end
        slot = slot + 1
      end
    end
    bag = bag + 1
  end
  return free, total
end

local function ibSegBags()
  local col = C_WHITE
  if IB.free <= 3 then col = C_BAD elseif IB.free <= 8 then col = C_WARN end
  return ibLabel("IB_SEG_BAGS") .. col .. IB.free .. "|r" .. C_DIM .. "/" .. IB.total .. "|r"
end

-- 专业：一次 API 遍历 + 一次纯表遍历（原版走两遍 GetSkillLineInfo，白翻一倍）
--   ★分类判据 = 该分类下**任一技能行** isAbandonable == 1（wiki：是 1 或 nil，不是 true/false）。
--     武器技能靠 maxRank == 1 天然排除（wiki：熟练度类不涨级，maxRank 恒 1）；
--     「防御/语言」这类不可遗忘 ⇒ 不会被误判成专业。
--   ★★自诊断：凡是 maxRank>1 却因分类没被判上而**没显示**的技能行，名字记进 IB.uncat，
--     由 `/eh go 信息条 诊断` 摊开 —— 这样「次要技能到底算不算可遗忘」不用猜，真机跑一次就知道。
local function ibSegProf()
  if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then return nil end
  local c = ibCfg()                       -- 阈值从配置读（三档预设见 THR）
  local okN, total = pcall(GetNumSkillLines)
  total = okN and ibNum(total, 0) or 0
  if total <= 0 then return nil end

  local cats, rows, n = {}, {}, 0
  local cur = nil
  local i = 1
  while i <= total do
    local name, header, _, rank, _, _, maxRank, abandonable = GetSkillLineInfo(i)
    if header == 1 then
      cur = name
    elseif cur and name then
      if abandonable == 1 then cats[cur] = true end
      n = n + 1
      rows[n] = { cat = cur, name = name, rank = ibNum(rank, 0), max = ibNum(maxRank, 0) }
    end
    i = i + 1
  end

  local out, shown, uncat = "", 0, {}
  i = 1
  while i <= n do
    local r = rows[i]
    if r.max > 1 then
      if cats[r.cat] then
        if shown > 0 then out = out .. " " .. C_SEP .. "·|r " end
        local col = C_WHITE
        local left = r.max - r.rank
        local cb = ibNum(c.profBad, DEF.profBad)
        local cw = ibNum(c.profWarn, DEF.profWarn)
        if left < cb then col = C_BAD elseif left < cw then col = C_WARN end
        out = out .. C_DIM .. ibEsc(r.name) .. "|r " .. col .. r.rank .. "|r" .. C_DIM .. "/" .. r.max .. "|r"
        shown = shown + 1
      else
        uncat[table.getn(uncat) + 1] = tostring(r.cat) .. "/" .. tostring(r.name) .. "(" .. r.rank .. "/" .. r.max .. ")"
      end
    end
    i = i + 1
  end
  IB.uncat = uncat
  if shown == 0 then return nil end
  return ibLabel("IB_SEG_PROF") .. out
end

-- ★★「内存」块的口径（1.75.40 真机取证实测修正）：
--   原版 SimpleInfoBar 显示的是 `GetScriptMemory()`，而这台客户端它**恒为 999**。
--   wiki（Addon 页 SetScriptMemory 段）原文：
--     「…that stored integer is returned. Otherwise this is the Lua garbage-collector byte count
--      converted to whole megabytes (floored).」
--   ⇒ `GetScriptMemory()` 优先返回**客户端存过的那个整数**（本机 999）= **脚本内存上限**，
--     不是当前占用！原版把它当占用显示（"Memory 999 MB"）是**读错了**。
--   ⇒ 本实现：条上只显示 **Lua 堆实际占用**（`collectgarbage("count")` 是 KB）；
--     上限挪进 tooltip（且只在它确实不是同一个数时才显示，免得重复）；
--     GC 也取不到 ⇒ 如实显示「不可用」，**绝不拿限值冒充用量**。
local function ibMemLimit()
  if type(GetScriptMemory) ~= "function" then return nil end
  local ok, v = pcall(GetScriptMemory)
  v = ok and tonumber(v) or nil
  if not v or v <= 0 then return nil end
  return v
end

local function ibSegMem()
  local mb = nil
  if type(collectgarbage) == "function" then
    local ok, kb = pcall(collectgarbage, "count")
    if ok and tonumber(kb) and tonumber(kb) > 0 then mb = tonumber(kb) / 1024 end
  end
  if mb == nil then
    IB.memMB, IB.memShown = nil, nil
    return ibLabel("IB_SEG_MEM") .. C_DIM .. L("IB_MEM_NA") .. "|r"
  end
  local shown
  if mb < 100 then shown = string.format("%.1f", mb) else shown = string.format("%d", mb) end
  IB.memMB, IB.memShown = mb, shown
  return ibLabel("IB_SEG_MEM") .. C_WHITE .. shown .. "|r" .. C_DIM .. " " .. L("IB_UNIT_MB") .. "|r"
end

----------------------------------------------------------------------
-- 刷新（分块脏标记 + 内容不变不写）
----------------------------------------------------------------------

local function ibShown()
  local f = IB.root
  if not f or type(f.IsShown) ~= "function" then return false end
  local ok, v = pcall(f.IsShown, f)
  return (ok and v) and true or false
end

local ibFit   -- 前向声明（ibRefresh / ibBuild / ibSkinApply 都会用到）

-- ★★★自估宽度（第三道保险，**完全不依赖客户端的度量 API**）：
--   真机报障「右侧的文字溢出了」的根因 = `GetStringWidth()` 对**中文**偏窄（少算约 14%）。
--   若连 `FontString:GetWidth()` 也偏窄，那就只剩这条路 ⇒ 自己按字符算一遍取**较大者**。
--   口径（本项目既有判据「中文宽度按字符数估」）：
--     ① 先**剥掉色码与转义**（`|cxxxxxxxx` / `|r` / `||`→`|`）——它们是零宽的控制串，
--        不剥会让估算虚高十几倍（本条字符串里有十几处色码）；
--     ② 再按 **UTF-8 首字节**判字符算宽（单位 = 字号 em）：
--        3/4 字节（中日韩·全角）= **1.0 em** ｜ 2 字节（拉丁扩展，如 `·` `°`）= **0.5 em**
--        ｜ ASCII 空格 = **0.3 em**（比字母窄）｜ 其余 ASCII = **0.5 em**。
--        ★空格不能按 0.5 em 算：本条有 20+ 个间隔空格，按 0.5 会把整条估宽近两成。
local function ibStripCodes(s)
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "||", "|")      -- 转义的竖线还原成一个（它是**要显示**的字符）
  return s
end

local function ibEstWidth(s, size)
  s = ibStripCodes(tostring(s or ""))
  size = tonumber(size) or 12
  local w, i, len = 0, 1, string.len(s)
  while i <= len do
    local b = string.byte(s, i)
    if b == nil then break end
    if b >= 0xF0 then i = i + 4 w = w + size
    elseif b >= 0xE0 then i = i + 3 w = w + size
    elseif b >= 0xC0 then i = i + 2 w = w + size * 0.5
    else
      i = i + 1
      if b == 32 then w = w + size * 0.3 else w = w + size * 0.5 end
    end
  end
  return w
end

local function ibRefresh()
  if not EVAL_IB_ENABLED() then return end        -- ★总开关闸在一切读写之前
  if not IB.built or not ibShown() then return end
  local c = ibCfg()

  if c.zone and IB.dZone then IB.dZone = false IB.seg.zone = ibSegZone() end
  if c.money and IB.dMoney then IB.dMoney = false IB.seg.money = ibSegMoney() end
  if c.prof and IB.dProf then IB.dProf = false IB.seg.prof = ibSegProf() end
  if c.net and IB.dNet then IB.dNet = false IB.seg.net = ibSegNet() end
  if c.mem and IB.dMem then IB.dMem = false IB.seg.mem = ibSegMem() end
  if c.bags and IB.dBags then
    IB.dBags = false
    IB.free, IB.total = ibScanBags()
    IB.seg.bags = ibSegBags()
  end
  -- 关掉的分块清掉旧文本（否则开关一关，那一格还挂在上面）
  if not c.zone then IB.seg.zone = nil end
  if not c.money then IB.seg.money = nil end
  if not c.bags then IB.seg.bags = nil end
  if not c.net then IB.seg.net = nil end
  if not c.prof then IB.seg.prof = nil end
  if not c.mem then IB.seg.mem = nil end

  local list, n = ibOrder()
  local parts, cnt = {}, 0
  local i = 1
  while i <= n do
    local k = list[i]
    if c[k] then
      local s = IB.seg[k]
      if s then cnt = cnt + 1 parts[cnt] = s end
    end
    i = i + 1
  end

  local out
  if cnt == 0 then
    out = C_DIM .. L("IB_NOSEG") .. "|r"
  else
    out = table.concat(parts, "  " .. C_SEP .. "|||r  ")
  end

  if out == IB.lastText then return end   -- ★内容没变 ⇒ 一个 SetText / SetWidth 都不发
  IB.lastText = out
  pcall(IB.text.SetText, IB.text, out)
  if ibFit then ibFit() end
end

local function ibForceAll()
  IB.dZone, IB.dMoney, IB.dBags, IB.dProf, IB.dNet, IB.dMem = true, true, true, true, true, true
  IB.seg = {}
  IB.lastText = nil
end

----------------------------------------------------------------------
-- 皮肤（★口径 = 照抄「工具箱 → 姓名右键弹窗」的圆角与背景；挂不上退化为方形底 + 四条平边）
----------------------------------------------------------------------

-- ★★★皮肤口径 = **照抄「工具箱 → 姓名右键弹窗」那一套**（用户定稿：「背景框圆角背景参考 工具箱->姓名右键弹窗设计」）：
--   · 底 + 圆角边 = 客户端**原生 backdrop**：`bgFile = UI-Tooltip-Background` + `edgeFile = UI-Tooltip-Border`
--     + `tile/tileSize/edgeSize = 16` + `insets 4` —— vanilla 的右键菜单/提示框本来就是这一套；
--   · 底色/边框色 = 与那个弹窗**同款**（`Toolbox.lua` 的 `TB_MENU_COLORS`）：深色 `0.01,0.01,0.02` + **白色高亮**边框 `1,1,1,0.75`；
--   · ★挂不上（`SetBackdrop` 失败 / `GetBackdrop()` 读到的不是这张边贴图）⇒ **退化路径** = WHITE8X8 方形底
--     + 四条 1px 平边（本项目唯一可靠的纯色纹理），**绝不静默丢掉边框**；
--   · ★圆角档下**必须藏掉自绘的方底与四条平边** —— Toolbox 原注释：再叠一层方形底会发黑，而且方底会盖住圆角；
--   · ★`edgeSize` 一律**整数**（Toolbox 实测：小数 edgeSize 在本客户端栅格化不可靠）。
local IB_EDGE = 16          -- 原生边贴图 16×16 九宫格（整数！）
local IB_INSET = 4
local PANEL_R, PANEL_G, PANEL_B = 0.01, 0.01, 0.02   -- 与姓名右键弹窗同款底色
local IB_CHROME = "flat"    -- "rounded" / "flat"（建帧时探测一次；读值口用）
local SKIN = {}

-- ★★外观预设（右侧 [设置] 里「点一下换下一个」的三行；单一真值 = cfg 里的 key / 数值）
local BORDER_COLORS = {
  { key = "white",  label = "IB_BC_WHITE",  rgb = { 1.00, 1.00, 1.00 } },   -- 默认 = 姓名右键弹窗同款
  { key = "gold",   label = "IB_BC_GOLD",   rgb = { 1.00, 0.82, 0.20 } },
  { key = "cyan",   label = "IB_BC_CYAN",   rgb = { 0.35, 0.85, 1.00 } },
  { key = "purple", label = "IB_BC_PURPLE", rgb = { 0.72, 0.45, 1.00 } },
  { key = "gray",   label = "IB_BC_GRAY",   rgb = { 0.55, 0.55, 0.60 } },
}
local BORDER_ALPHAS = {
  { key = "low",  label = "IB_BA_LOW",  v = 0.25 },
  { key = "mid",  label = "IB_BA_MID",  v = 0.40 },   -- ★默认（用户：「边框透明度可以低一点」）
  { key = "high", label = "IB_BA_HIGH", v = 0.70 },
}
local PANEL_ALPHAS = {
  { key = "thin",  label = "IB_PA_THIN",  v = 0.55 },
  { key = "std",   label = "IB_PA_STD",   v = 0.88 },  -- ★默认 = 姓名右键弹窗同款
  { key = "solid", label = "IB_PA_SOLID", v = 0.96 },
}

-- 按 key 找颜色（找不到退回第 1 项 ⇒ 老存档里写坏的值不会让边框消失）
local function ibColorOf(c)
  local k = c and c.borderColor
  local i = 1
  while BORDER_COLORS[i] do
    if BORDER_COLORS[i].key == k then return BORDER_COLORS[i].rgb end
    i = i + 1
  end
  return BORDER_COLORS[1].rgb
end

local function ibNearestColor(c)
  local k = c and c.borderColor
  local i = 1
  while BORDER_COLORS[i] do
    if BORDER_COLORS[i].key == k then return i end
    i = i + 1
  end
  return 1
end

-- 按**数值**找最近的预设下标（单一真值 = 数值本身，不另存一份 key ⇒ 不会两处打架）
local function ibNearestIdx(list, val)
  local best, bi = nil, 1
  local v = tonumber(val)
  local i = 1
  while list[i] do
    local d = math.abs((list[i].v or 0) - (v or 0))
    if best == nil or d < best then best, bi = d, i end
    i = i + 1
  end
  return bi
end

local function ibSolid(parent, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8")   -- ★本项目唯一可靠的纯色纹理
  return t
end

local function ibSkinBuild(root)
  -- ① 先试原生圆角 backdrop（与姓名右键弹窗同款）
  IB_CHROME = "flat"
  if type(root.SetBackdrop) == "function" then
    local ok = pcall(root.SetBackdrop, root, {
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = IB_EDGE, edgeSize = IB_EDGE,
      insets = { left = IB_INSET, right = IB_INSET, top = IB_INSET, bottom = IB_INSET },
    })
    if ok then
      IB_CHROME = "rounded"
      -- ★读回自证：**读到了但不是这张边贴图**才算没挂上；**读不到**按「能挂」处理（与 Toolbox 同口径）
      if type(root.GetBackdrop) == "function" then
        local oks, str = pcall(root.GetBackdrop, root)
        if oks and type(str) == "string" and string.find(str, "UI-Tooltip-Border", 1, true) == nil then
          IB_CHROME = "flat"
        end
      end
    end
  end

  -- ② 退化路径的件：**永远建出来**（圆角档下由 ibSkinApply 藏掉）—— 两条路都能走，切换零重建
  SKIN.bg = ibSolid(root, "BACKGROUND")
  pcall(SKIN.bg.SetAllPoints, SKIN.bg, root)

  SKIN.top = ibSolid(root, "BORDER")
  pcall(SKIN.top.SetPoint, SKIN.top, "TOPLEFT", root, "TOPLEFT", 0, 0)
  pcall(SKIN.top.SetPoint, SKIN.top, "TOPRIGHT", root, "TOPRIGHT", 0, 0)
  pcall(SKIN.top.SetHeight, SKIN.top, 1)

  SKIN.bot = ibSolid(root, "BORDER")
  pcall(SKIN.bot.SetPoint, SKIN.bot, "BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  pcall(SKIN.bot.SetPoint, SKIN.bot, "BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  pcall(SKIN.bot.SetHeight, SKIN.bot, 1)

  SKIN.left = ibSolid(root, "BORDER")
  pcall(SKIN.left.SetPoint, SKIN.left, "TOPLEFT", root, "TOPLEFT", 0, 0)
  pcall(SKIN.left.SetPoint, SKIN.left, "BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  pcall(SKIN.left.SetWidth, SKIN.left, 1)

  SKIN.right = ibSolid(root, "BORDER")
  pcall(SKIN.right.SetPoint, SKIN.right, "TOPRIGHT", root, "TOPRIGHT", 0, 0)
  pcall(SKIN.right.SetPoint, SKIN.right, "BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  pcall(SKIN.right.SetWidth, SKIN.right, 1)

  SKIN.lines = { SKIN.top, SKIN.bot, SKIN.left, SKIN.right }
end

local function ibSkinApply()
  if not IB.built then return end
  local c = ibCfg()
  local a = ibNum(c.alpha, DEF.alpha)
  if a < 0.05 then a = 0.05 elseif a > 1 then a = 1 end
  local rounded = (IB_CHROME == "rounded")

  -- 底：圆角档交给 backdrop 自己画（insets 让它落在圆角内侧）；退化档用自绘方底
  if rounded then
    pcall(SKIN.bg.Hide, SKIN.bg)
    local al = 0
    if c.bg then
      al = a + (IB.hover and 0.10 or 0)
      if al > 1 then al = 1 end
    end
    if type(IB.root.SetBackdropColor) == "function" then
      pcall(IB.root.SetBackdropColor, IB.root, PANEL_R, PANEL_G, PANEL_B, al)
    end
  else
    pcall(SKIN.bg.Show, SKIN.bg)
    if c.bg then
      local al = a + (IB.hover and 0.18 or 0)
      if al > 1 then al = 1 end
      pcall(SKIN.bg.SetVertexColor, SKIN.bg, PANEL_R, PANEL_G, PANEL_B, al)
    else
      pcall(SKIN.bg.SetVertexColor, SKIN.bg, 0, 0, 0, 0)
    end
  end

  -- 边框：颜色/浓度**可配**（用户：「边框颜色能设置么?」+「边框透明度可以低一点」）；
  --   悬停 = 在基准浓度上加亮 0.30；锁定 = 冷灰（**看得见的锁定反馈**，与所选颜色无关）
  local bc = ibColorOf(c)
  local ba = ibNum(c.borderAlpha, DEF.borderAlpha)
  if ba < 0.05 then ba = 0.05 elseif ba > 1 then ba = 1 end
  local fr, fg, fb, fa
  if c.locked then
    fr, fg, fb, fa = 0.62, 0.62, 0.68, ba * 0.85
  elseif IB.hover then
    fr, fg, fb, fa = bc[1], bc[2], bc[3], math.min(1, ba + 0.30)
  else
    fr, fg, fb, fa = bc[1], bc[2], bc[3], ba
  end
  local i = 1
  while i <= table.getn(SKIN.lines) do
    local t = SKIN.lines[i]
    if rounded then
      pcall(t.Hide, t)
    else
      pcall(t.Show, t)
      pcall(t.SetVertexColor, t, fr, fg, fb, fa)
    end
    i = i + 1
  end
  if rounded and type(IB.root.SetBackdropBorderColor) == "function" then
    pcall(IB.root.SetBackdropBorderColor, IB.root, fr, fg, fb, fa)
  end

  -- 背景关掉时给文字描边（不然字浮在世界贴图上读不清）
  -- ★不写死字体文件：从 GetFont 读回路径/字号再写回，只改 flags
  local okp, path, size = pcall(IB.text.GetFont, IB.text)
  if okp and type(path) == "string" and path ~= "" then
    local flag = c.bg and "" or "OUTLINE"
    pcall(IB.text.SetFont, IB.text, path, ibNum(size, ibNum(c.font, DEF.font)), flag)
  end

  -- ★字体/边框一变，渲染宽就可能变 ⇒ 重新量宽（否则关掉背景后中文会压出边框）
  if ibFit then ibFit() end
end

----------------------------------------------------------------------
-- 位置（记忆 + 越界回归；★先量回自证，再决定要不要回默认）
----------------------------------------------------------------------

local function ibOffscreen(f)
  if not f or type(f.GetLeft) ~= "function" then return false end
  local ok, l, b, r, top = pcall(function() return f:GetLeft(), f:GetBottom(), f:GetRight(), f:GetTop() end)
  if not ok or not tonumber(l) or not tonumber(top) then return false end
  local sw, sh = ibScreen()
  if r < 4 or l > sw - 4 then return true end
  if top < 4 or b > sh - 4 then return true end
  return false
end

local function ibApplyPos()
  if not IB.built then return end
  local c = ibCfg()
  pcall(IB.root.ClearAllPoints, IB.root)
  pcall(IB.root.SetPoint, IB.root, c.point or DEF.point, UIParent, c.relPoint or DEF.relPoint,
    ibNum(c.x, DEF.x), ibNum(c.y, DEF.y))
  if ibOffscreen(IB.root) then
    -- ★越界回归：存档位置在本次分辨率下已在屏幕外 ⇒ 回默认 + 如实播报（绝不静默留一条看不见的条）
    c.point, c.relPoint, c.x, c.y = DEF.point, DEF.relPoint, DEF.x, DEF.y
    pcall(IB.root.ClearAllPoints, IB.root)
    pcall(IB.root.SetPoint, IB.root, DEF.point, UIParent, DEF.relPoint, DEF.x, DEF.y)
    ibRec("位置越界 → 已回默认 " .. DEF.point .. " " .. DEF.x .. "," .. DEF.y)
    ibSay(L("IB_POS_BAD"))
  end
end

local function ibSavePos()
  if not IB.built then return end
  local ok, p, _, rp, x, y = pcall(IB.root.GetPoint, IB.root, 1)
  if not ok or not p then return end
  local c = ibCfg()
  c.point = p
  c.relPoint = rp or p
  c.x = ibNum(x, 0)
  c.y = ibNum(y, 0)
end

----------------------------------------------------------------------
-- 提示 / 设置下拉
----------------------------------------------------------------------

local function ibTip(owner)
  local tip = _G["GameTooltip"]
  if not tip or type(tip.SetOwner) ~= "function" then return end
  local c = ibCfg()
  pcall(tip.SetOwner, tip, owner, "ANCHOR_BOTTOM")
  -- ★★★**显式摆位**（1.75.40 真机报障「这个信息显示的位置不对」）：
  --   只给 `SetOwner` 那串锚点名时，真机提示框跑到了**屏幕中下方**（离条两百多像素）——
  --   本客户端对 Button 宿主 + "ANCHOR_BOTTOM" 的自动摆位不按预期走。
  --   ⇒ 清掉客户端给的锚点、**自己钉**在条下方 4px（`TOP` 对 `BOTTOM`），位置从此可预期。
  if type(tip.ClearAllPoints) == "function" and type(tip.SetPoint) == "function" then
    pcall(tip.ClearAllPoints, tip)
    pcall(tip.SetPoint, tip, "TOP", owner, "BOTTOM", 0, -4)
  end
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.AddLine, tip, L("IB_TIP_TITLE"), 1, 0.82, 0.30)
  -- ★★★悬停**只留操作说明**：信息行（背包空格 / 脚本内存上限）一律不上屏 ——
  --   ① 背包空格在条上的「背包」块里本来就有，重复；
  --   ② 内存上限那句太长，真机上会**溢出提示框右缘**（用户截图报障「右侧的文字溢出了」）；
  --   ③ 用户定稿：「提示信息现在如果没有设置功能，可以直接隐藏」。
  --   ⇒ 这两个数要取证时走 `/eh go 信息条 诊断`（那条通道是给 AI 读的，不占屏幕）。
  --   ★`IB_TIP_FREE` / `IB_TIP_MEMLIM` 两个键**保留在语言包里备用**（别再往悬停里加回去）。
  if c.locked then
    pcall(tip.AddLine, tip, L("IB_TIP_LOCKED"), 1, 0.55, 0.55)
  else
    pcall(tip.AddLine, tip, L("IB_TIP_DRAG"), 0.80, 0.80, 0.80)
  end
  pcall(tip.AddLine, tip, L("IB_TIP_MENU"), 0.80, 0.80, 0.80)
  pcall(tip.Show, tip)
end

local function ibTipHide()
  local tip = _G["GameTooltip"]
  if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
end

-- ★★为什么是**两个**下拉（设计约束，别再合并回去）：
--   `EVAL_DD_OPEN` 的多选模式里**每一行都是勾选框**（`opts.locked` 行更是连 OnClick 都没有），
--   **没有「动作项」概念** ⇒ 「点上移 / 选阈值 / 重设 / 隐藏」这类**动作**放进去会被画成复选框，
--   看着像开关、点了却执行动作 = 语义错乱。
--   ⇒ 拆成两个：`[显示]` = 多选（勾选类）· `[设置]` = **非多选**（动作类）。
--   ★非多选下拉点一下就 `dd:Hide()` ⇒ 为了像原版那样「点完菜单还开着」，动作执行后**立刻重开自己**
--     （`ibOpenMore` 递归调用：那一拍 dd 已经 Hide，`EVAL_DD_OPEN` 的 toggle 分支不会命中）。

local function ibAfterChange()
  ibForceAll()
  ibSkinApply()
  ibRefresh()
  if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
end

local function ibSaveOrder(list, n)
  local out, i = "", 1
  while i <= n do
    if i > 1 then out = out .. "," end
    out = out .. list[i]
    i = i + 1
  end
  ibCfg().order = out
  return out
end

-- 把某一块往前挪一位（原版右键菜单「顺序（点击上移）」同口径）
local function ibMoveUp(key)
  local list, n = ibOrder()
  local i = 2
  while i <= n do
    if list[i] == key then
      list[i], list[i - 1] = list[i - 1], list[i]
      ibSaveOrder(list, n)
      return true
    end
    i = i + 1
  end
  return false      -- 已经在第一位 ⇒ 如实返回 false（不做无意义的写盘）
end

local function ibMenuOpen(anchor)
  if type(EVAL_DD_OPEN) ~= "function" then
    ibSay(L("IB_NO_DD"))
    return
  end
  local c = ibCfg()
  local items, sel, i = {}, {}, 1
  while OPT[i] do
    items[i] = L(OPT[i].label)
    if c[OPT[i].key] ~= false then sel[i] = true end
    i = i + 1
  end
  EVAL_DD_OPEN(anchor or IB.root, items, function(pi, on)
    local opt = OPT[pi]
    if not opt then return end
    ibCfg()[opt.key] = (on == true)
    ibRec("设置：" .. tostring(opt.key) .. " = " .. tostring(on == true))
    ibAfterChange()
  end, { multi = true, selected = sel })
end

-- 专业阈值三档（bad = 距上限多少点转红，warn = 转黄）
local THR = {
  { key = "IB_THR_LOOSE",  bad = 5,  warn = 15 },
  { key = "IB_THR_NORMAL", bad = 10, warn = 25 },
  { key = "IB_THR_STRICT", bad = 20, warn = 40 },
}

local function ibSegName(key)
  return L("IB_SEG_" .. string.upper(tostring(key)))
end

-- 动作菜单的条目 + 逐项动作表（每次打开现算 ⇒ 顺序/阈值当场就是最新的）
local function ibMoreItems()
  local c = ibCfg()
  local list, n = ibOrder()
  local items, act = {}, {}
  local function push(text, kind, arg)
    local i = table.getn(items) + 1
    items[i] = text
    act[i] = { kind = kind, arg = arg }
  end

  push(L("IB_ORDER_HDR"), "noop")
  local i = 1
  while i <= n do
    local key = list[i]
    local txt = i .. ". " .. ibSegName(key)
    if i > 1 then txt = txt .. "   |cffffd700↑|r" end   -- 第 1 行挪不动 ⇒ 不给箭头
    push(txt, "up", key)
    i = i + 1
  end

  push(L("IB_PROF_HDR"), "noop")
  i = 1
  while i <= 3 do
    local p = THR[i]
    local on = (ibNum(c.profBad, DEF.profBad) == p.bad) and (ibNum(c.profWarn, DEF.profWarn) == p.warn)
    push(L("IB_THR_FMT", L(p.key), p.warn, p.bad) .. (on and "   |cffffd100●|r" or ""), "thr", p)
    i = i + 1
  end

  -- ★外观：**循环切换**三行（点一下换下一个）——比「5 色 ×3 浓度 ×3 面板 = 14 行」省得多，
  --   也不会把下拉撑成两列（本项目下拉是 24 行/列的多列网格）。
  push(L("IB_APPEAR_HDR"), "noop")
  push(L("IB_ROW_BORDER", L(BORDER_COLORS[ibNearestColor(c)].label)), "cyc", "color")
  push(L("IB_ROW_BALPHA", L(BORDER_ALPHAS[ibNearestIdx(BORDER_ALPHAS, c.borderAlpha)].label)), "cyc", "balpha")
  push(L("IB_ROW_PALPHA", L(PANEL_ALPHAS[ibNearestIdx(PANEL_ALPHAS, c.alpha)].label)), "cyc", "palpha")

  push(L("IB_MENU_RESET"), "reset")
  push(L("IB_MENU_HIDE"), "hide")
  return items, act
end

local ibOpenMore

ibOpenMore = function(anchor)
  if type(EVAL_DD_OPEN) ~= "function" then
    ibSay(L("IB_NO_DD"))
    return
  end
  local anchorBtn = anchor or IB.root
  local items, act = ibMoreItems()
  EVAL_DD_OPEN(anchorBtn, items, function(pi)
    local a = act[pi]
    if a == nil or a.kind == "noop" then
      ibOpenMore(anchorBtn)                     -- 标题行：原样重开（点了等于没点，但菜单不关）
      return
    end
    if a.kind == "up" then
      if ibMoveUp(a.arg) then ibRec("顺序上移：" .. tostring(a.arg)) end
      ibForceAll()
      if IB.built then ibRefresh() end
      ibOpenMore(anchorBtn)
    elseif a.kind == "thr" then
      local c = ibCfg()
      c.profBad, c.profWarn = a.arg.bad, a.arg.warn
      ibRec("专业阈值 = 距上限 " .. a.arg.warn .. " 转黄 · " .. a.arg.bad .. " 转红")
      IB.dProf = true
      ibAfterChange()
      ibOpenMore(anchorBtn)
    elseif a.kind == "cyc" then
      -- ★外观三项：点一下换下一个（列表末尾绕回第一项）
      local c = ibCfg()
      if a.arg == "color" then
        local i = ibNearestColor(c) % table.getn(BORDER_COLORS) + 1
        c.borderColor = BORDER_COLORS[i].key
        ibRec("边框颜色 = " .. tostring(c.borderColor))
      elseif a.arg == "balpha" then
        local i = ibNearestIdx(BORDER_ALPHAS, c.borderAlpha) % table.getn(BORDER_ALPHAS) + 1
        c.borderAlpha = BORDER_ALPHAS[i].v
        ibRec("边框浓度 = " .. tostring(c.borderAlpha))
      elseif a.arg == "palpha" then
        local i = ibNearestIdx(PANEL_ALPHAS, c.alpha) % table.getn(PANEL_ALPHAS) + 1
        c.alpha = PANEL_ALPHAS[i].v
        ibRec("面板浓度 = " .. tostring(c.alpha))
      end
      ibAfterChange()
      ibOpenMore(anchorBtn)
    elseif a.kind == "reset" then
      EVAL_IB_RESET_POS()
      ibSay(L("IB_RESET_DONE"))
      ibRec("重设位置与顺序")
      ibAfterChange()
      ibOpenMore(anchorBtn)
    elseif a.kind == "hide" then
      -- ★单一真值：隐藏 = 关掉总开关（工具箱那一行的勾选框同步取消）——
      --   绝不另开一个 hidden 状态（两份真值一定会打架），且回头路在工具箱里看得见。
      EVAL_IB_SET(false)
      ibSay(L("IB_HIDE_MSG"))
      return                                    -- 隐藏后不再重开
    end
  end)
end

----------------------------------------------------------------------
-- 建帧（★拖动柄用 Button —— 本项目铁律：Frame 的 OnDragStart 不触发）
----------------------------------------------------------------------

local function ibTickScript()
  -- ★OnUpdate 回调**一个形参都不传**（本项目铁律）：dt 只能从全局 arg1 取
  if not EVAL_IB_ENABLED() then return end      -- ★总开关闸在一切读写之前
  local dt = tonumber(arg1)
  if not dt or dt < 0 or dt > 1 then dt = 0.05 end
  IB.acc = IB.acc + dt
  if IB.acc < IB_PERIOD then return end
  IB.acc = 0
  IB.dNet, IB.dMem = true, true                 -- 网络/内存本来就一直变
  ibRefresh()
end

local function ibBuild()
  if IB.built then return true end
  if type(CreateFrame) ~= "function" then return false end

  local root = CreateFrame("Button", "EVAL_IB_ROOT", UIParent)
  root:SetWidth(220)
  root:SetHeight(IB_H)
  pcall(root.SetFrameStrata, root, "MEDIUM")
  pcall(root.SetClampedToScreen, root, true)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  pcall(root.RegisterForDrag, root, "LeftButton")
  pcall(root.RegisterForClicks, root, "LeftButtonUp", "RightButtonUp")
  IB.root = root
  ibSkinBuild(root)

  local text = root:CreateFontString(nil, "OVERLAY")
  -- ★字体走**客户端字体对象链**（不写死任何 .ttf 路径；真机截图已证本客户端能渲染中文）
  for _, fo in ipairs({ "GameFontNormalSmall", "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    local obj = rawget(_G, fo)
    if obj ~= nil and pcall(text.SetFontObject, text, obj) then break end
  end
  -- ★★★文本**左对齐**（用户定稿：「左侧空白还是很多。**不能左对齐吗?**」）：
  --   锚 `LEFT` + x = 内边距 + `SetJustifyH("LEFT")` ⇒ 左边**恒为内边距**，一个像素都不多。
  --   ★为什么必须左对齐（不再是居中）：定宽是**估**出来的，估宽了多少无法保证 ——
  --     居中时「估多出来的余量」会**左右各摊一半**（真机症状就是用户报的「左侧空白有点多」）；
  --     左对齐后余量**全部落到右边**，左缘永远贴着 16px 内边距，视觉上稳且符合条状 UI 的直觉。
  pcall(text.SetPoint, text, "LEFT", root, "LEFT", IB_PAD, 0)
  pcall(text.SetJustifyH, text, "LEFT")
  pcall(text.SetText, text, "...")
  IB.text = text

  root:SetScript("OnUpdate", ibTickScript)

  root:SetScript("OnDragStart", function()
    if ibCfg().locked then return end
    pcall(root.StartMoving, root)
  end)
  root:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    ibSavePos()
    local c = ibCfg()
    ibRec("拖动结束：落点 " .. tostring(c.point) .. " " .. tostring(c.x) .. "," .. tostring(c.y))
  end)

  root:SetScript("OnClick", function(a, b)
    -- ★★★右键分派必须用**三元探测**（照本项目既有配方 EvalHelp.lua:699 / 789 / 909 / 1753 / 5682 五处）：
    --   本客户端会把按键名放在**全局 `arg1`** 里（回调形参很可能是 nil）⇒ 只判 `button == "RightButton"`
    --   等于什么都没判 ⇒ 表现为「右键打不开设置」。
    --   ★真机事故（1.75.40，用户原话「信息条他有右键配置功能吗？我这边无法打开」）：就是这一条。
    local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b)
      or (type(arg1) == "string" and arg1) or "LeftButton"
    if mbtn == "RightButton" then ibMenuOpen(root) end
  end)

  root:SetScript("OnEnter", function()
    IB.hover = true
    ibSkinApply()
    ibTip(root)
  end)
  root:SetScript("OnLeave", function()
    IB.hover = false
    ibSkinApply()
    ibTipHide()
  end)

  IB.built = true
  return true
end

ibFit = function()
  if not IB.built or not IB.text then return end
  -- ★★★定宽只用**两个互相独立的读数取较大者**（1.75.40 真机两轮定案）：
  --   ① 客户端度量 `GetStringWidth()` —— 真机对**中文偏窄约 14%**（harness 实测同一条文本差 14%）；
  --   ② **自估**（剥色码 + 按 UTF-8 字符算宽）—— 完全不依赖客户端的度量 API。
  --
  -- ★★★**绝不许**把 `FontString:GetWidth()` 放进计算，更不许拿它做「量回自证收敛」：
  --   本客户端它对**居中且无显式宽度**的 FontString 回的是**帧宽回声**（≈ 我们刚设的宽）⇒
  --   一进循环就是正反馈：每轮 `need = tw + 2*PAD + SLACK` 都比上一轮大 ⇒ **越量越宽**
  --   （三轮多出上百像素）。真机症状 = 用户报的「**左侧空白有点多**」（字居中，两侧各多出几十像素）。
  --   ⇒ 它只进探针读数（`fitTW`），**不进任何计算**。
  local sw = 0
  local ok1, v1 = pcall(IB.text.GetStringWidth, IB.text)
  if ok1 and tonumber(v1) then sw = tonumber(v1) end
  local okf, _, fsz = pcall(IB.text.GetFont, IB.text)
  local fsize = (okf and tonumber(fsz)) or ibNum(ibCfg().font, DEF.font)
  local est = ibEstWidth(IB.lastText, fsize)
  local w = sw
  if est > w then w = est end
  -- ★左内边距全给、右内边距只留 4px（用户：「右边位置不要设置边距试下，缩小点」）——
  --   文本左对齐 ⇒ 右边这点余量就是**唯一**的右侧留白，收掉它条就紧凑了。
  local need = w + IB_PAD + IB_RPAD
  pcall(IB.root.SetWidth, IB.root, need)
  pcall(IB.root.SetHeight, IB.root, IB_H)

  -- 读值口（探针用；★只读，**不参与计算**）
  local ok2, tw = pcall(IB.text.GetWidth, IB.text)
  IB.fitW, IB.fitSW, IB.fitEST = need, (ok1 and tonumber(v1)) or nil, est
  IB.fitTW = (ok2 and tonumber(tw)) or nil
end

----------------------------------------------------------------------
-- 事件（★按分块置脏；关掉时一个事件都不注册）
----------------------------------------------------------------------

local IB_EVENTS = {
  "PLAYER_ENTERING_WORLD",
  "PLAYER_MONEY",
  "BAG_UPDATE", "BAG_CLOSED", "ITEM_LOCK_CHANGED", "UNIT_INVENTORY_CHANGED",
  "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "MINIMAP_ZONE_CHANGED",
  "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
}

local IB_KIND = {
  PLAYER_ENTERING_WORLD = "ALL",
  PLAYER_MONEY = "Money",
  BAG_UPDATE = "Bags", BAG_CLOSED = "Bags", ITEM_LOCK_CHANGED = "Bags", UNIT_INVENTORY_CHANGED = "Bags",
  ZONE_CHANGED = "Zone", ZONE_CHANGED_INDOORS = "Zone", ZONE_CHANGED_NEW_AREA = "Zone", MINIMAP_ZONE_CHANGED = "Zone",
  SKILL_LINES_CHANGED = "Prof", CHAT_MSG_SKILL = "Prof",
}

local function ibEventsOn()
  if not IB.evF then
    if type(CreateFrame) ~= "function" then return end
    local f = CreateFrame("Frame", "EVAL_IB_EVENTS")
    f:SetScript("OnEvent", function()
      if not EVAL_IB_ENABLED() then return end   -- ★关掉零动作
      local kind = IB_KIND[event]
      if kind == nil then return end
      if kind == "ALL" then
        ibForceAll()
        ibRefresh()
        return
      end
      IB["d" .. kind] = true
      ibRefresh()
    end)
    IB.evF = f
  end
  for _, ev in ipairs(IB_EVENTS) do pcall(IB.evF.RegisterEvent, IB.evF, ev) end
  IB.evArmed = true
end

local function ibEventsOff()
  local f = IB.evF
  if not f then IB.evArmed = false return end
  for _, ev in ipairs(IB_EVENTS) do pcall(f.UnregisterEvent, f, ev) end
  IB.evArmed = false
end

----------------------------------------------------------------------
-- 开关 / 安装
----------------------------------------------------------------------

local function ibTurnOn(silent)
  if not ibBuild() then return false end
  ibCfg()
  ibApplyPos()
  ibSkinApply()
  ibForceAll()
  pcall(IB.root.Show, IB.root)
  pcall(IB.root.SetScript, IB.root, "OnUpdate", ibTickScript)   -- 重新挂上节拍
  ibEventsOn()
  ibRefresh()
  ibFit()
  ibRec("开：位置=" .. tostring(ibCfg().point) .. " " .. tostring(ibCfg().x) .. "," .. tostring(ibCfg().y))
  if not silent then ibSay(L("IB_ON_MSG", L("SH_ON"))) end
  return true
end

local function ibTurnOff(silent)
  ibEventsOff()
  if IB.built then
    pcall(IB.root.SetScript, IB.root, "OnUpdate", nil)          -- ★摘掉节拍 = 真的零动作
    pcall(IB.root.Hide, IB.root)
  end
  ibRec("关")
  if not silent then ibSay(L("IB_OFF_MSG", L("SH_OFF"))) end
  return true
end

function EVAL_IB_SET(on)
  on = on and true or false
  local tb = ibTb()
  if type(tb) ~= "table" then
    ibSay(L("IB_NO_CFG"))
    return false
  end
  tb.infoBar = on
  if on then return ibTurnOn(false) end
  return ibTurnOff(false)
end

function EVAL_IB_INSTALL()
  if not EVAL_IB_ENABLED() then
    ibCfg()          -- 只补默认值：不建帧、不注册事件、不挂节拍
    return false
  end
  return ibTurnOn(true)
end

function EVAL_IB_RESET_POS()
  local c = ibCfg()
  c.point, c.relPoint, c.x, c.y = DEF.point, DEF.relPoint, DEF.x, DEF.y
  c.order = DEF.order
  if IB.built then ibApplyPos() ibForceAll() ibRefresh() end
  return true
end

-- 供模块行 tooltip 用的状态行（★前向声明必须在 ibRow 之前 —— 否则绑全局 nil 被 pcall 吞掉）
local ibStateLine

----------------------------------------------------------------------
-- 工具箱模块行（嵌入点被调方；Toolbox 侧只有一行数据）
----------------------------------------------------------------------

local function ibRow(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return EVAL_IB_ENABLED() end
  r.set = function(v) EVAL_IB_SET(v and true or false) end
  r.extra:Hide()                       -- ★配置项只在按钮的悬停里显示，行上不重复
  -- ★两个按钮（为什么必须拆：见上面「两个下拉」那段注释）：
  --   左 = [显示] 多选（哪几块 / 标签 / 背景 / 锁定）· 右 = [设置] 非多选（顺序 / 阈值 / 重设 / 隐藏）
  r.add.text:SetText(L("IB_BTN_SHOW"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, 320)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_INFOBAR_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, ibStateLine and ibStateLine() or "", 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function() ibMenuOpen(r.add.btn) end)

  r.clr.text:SetText(L("TB_LDDRAG_SET"))
  r.clr.btn:Show()
  r.clr.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, 320)
    pcall(tip.SetOwner, tip, r.clr.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_INFOBAR_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, ibStateLine and ibStateLine() or "", 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.clr.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.clr.btn:SetScript("OnClick", function() ibOpenMore(r.clr.btn) end)
  return true
end

local IB_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(IB_TB_ROWS) ~= "table" then
  IB_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", IB_TB_ROWS)
end
IB_TB_ROWS["infoBar"] = ibRow

----------------------------------------------------------------------
-- 状态行 / 命令体（宿主 /eh 链只留一行 prRun("IB", msg)）
----------------------------------------------------------------------

ibStateLine = function()
  local c = ibCfg()
  local segs, n = {}, 0
  local i = 1
  while SEG_ORDER_DEF[i] do
    if c[SEG_ORDER_DEF[i]] then n = n + 1 segs[n] = SEG_ORDER_DEF[i] end
    i = i + 1
  end
  return L("TB_INFOBAR") .. "：" .. (EVAL_IB_ENABLED() and L("SH_ON") or L("SH_OFF"))
    .. " · " .. table.concat(segs, "/")
    .. " · " .. L("IB_OPT_LABELS") .. "=" .. (c.labels and L("SH_ON") or L("SH_OFF"))
    .. " · " .. L("IB_OPT_BG") .. "=" .. (c.bg and L("SH_ON") or L("SH_OFF"))
    .. " · " .. L("IB_OPT_LOCK") .. "=" .. (c.locked and L("SH_ON") or L("SH_OFF"))
end

function EVAL_IB_CMD(msg)
  msg = tostring(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")

  if msg == "" or msg == "状态" then
    ibSay(ibStateLine())
    local c = ibCfg()
    local w = "-"
    if IB.built and type(IB.root.GetWidth) == "function" then
      local ok, v = pcall(IB.root.GetWidth, IB.root)
      if ok then w = tostring(v) end
    end
    ibSay(string.format("位置 %s %s,%s ｜ 字号 %s ｜ 面板浓度 %s ｜ 边框 %s/%s ｜ 专业阈值 %s/%s",
      tostring(c.point), tostring(c.x), tostring(c.y), tostring(c.font), tostring(c.alpha),
      tostring(c.borderColor), tostring(c.borderAlpha),
      tostring(c.profWarn), tostring(c.profBad)))
    ibSay(string.format("帧=%s ｜ 事件=%s ｜ 条宽=%s",
      IB.built and "已建" or "未建", IB.evArmed and "在" or "未挂", w))
    -- ★量宽取证（真机报障「右侧的文字溢出了」）：三个读数一起报，谁不靠谱一眼看出
    ibSay(string.format("边框=%s ｜ 量宽四读数：GetStringWidth=%s ｜ FontString:GetWidth=%s ｜ **自估=%s** ｜ 定宽=%s（内边距 左 %d / 右 %d）",
      (IB_CHROME == "rounded") and "原生圆角（UI-Tooltip-Border）" or "退化平边（WHITE8X8×4）",
      tostring(IB.fitSW), tostring(IB.fitTW), tostring(IB.fitEST), tostring(IB.fitW), IB_PAD, IB_RPAD))
    ibSay("顺序：" .. tostring(c.order))
    ibSay("子命令：开 · 关 · 重设 · 顺序 zone,money,bags,net,prof,mem · 诊断 · 存档 · 清")

  elseif msg == "开" then
    EVAL_IB_SET(true)

  elseif msg == "关" then
    EVAL_IB_SET(false)

  elseif msg == "重设" then
    EVAL_IB_RESET_POS()
    ibSay(L("IB_RESET_DONE"))

  elseif string.find(msg, "^顺序%s") == 1 then
    local list = string.gsub(msg, "^顺序%s+", "")
    ibCfg().order = list
    ibForceAll()
    if IB.built then ibRefresh() end
    ibSay("顺序已设为：" .. list)
    ibRec("顺序 = " .. list)

  elseif msg == "诊断" then
    -- ★专业分类的**自诊断**：maxRank>1 却没被判成专业的技能行（真机跑一次就知道次要技能算不算可遗忘）
    ibSay(string.format("专业诊断：被判为「非专业」而隐藏、但 maxRank>1 的技能行 = %d 条", table.getn(IB.uncat)))
    if table.getn(IB.uncat) == 0 then
      ibSay("　（0 条 ⇒ 判据 isAbandonable==1 已把所有该显示的技能行收进来；若界面上看不到专业，请把这一行发我）")
    else
      for i = 1, table.getn(IB.uncat) do ibSay("　[未归类] " .. IB.uncat[i]) end
      ibSay("　⇒ 把这份清单发我：若是「烹饪/急救/钓鱼」，说明本客户端的次要技能 isAbandonable 不是 1，判据要换。")
    end
    local free, total = ibScanBags()
    ibSay(string.format("背包实测：%d/%d 空格 ｜ 网络段=%s", free, total, IB.seg.net and "有" or "无"))
    -- ★内存口径取证（真机踩过：原版把 999 当占用量显示）：两个数分开报，一眼看出各是什么。
    local heap = IB.memMB and string.format("%.2f", IB.memMB) or "取不到"
    local lim = ibMemLimit()
    ibSay(string.format("内存：Lua 堆（collectgarbage count）= %s MB ｜ GetScriptMemory = %s（★客户端存的**限值**，不是占用）",
      heap, lim and tostring(math.floor(lim)) or "取不到"))
    if IB.memMB == nil then
      ibSay("　⇒ collectgarbage 取不到 ⇒ 条上显示的是「不可用」，**不拿限值冒充用量**")
    end

  elseif msg == "存档" then
    local root = ibConf()
    local box = (type(root) == "table") and root.ibProbe or nil
    local out = (type(box) == "table" and type(box.out) == "table") and box.out or IB.out
    local n = table.getn(out)
    ibSay(string.format("===== 顶部信息条探针 · 存档读数（键 cfg.ibProbe ｜ 上限 %d ｜ 现有 %d）=====", IB_OUT_MAX, n))
    for i = 1, n do ibSay("　" .. tostring(out[i])) end
    ibSay("（/reload 后才写盘；AI 侧直读 EvalHelp.lua 存档的 ibProbe 键）")

  elseif msg == "清" then
    IB.out = {}
    local root = ibConf()
    if type(root) == "table" then root.ibProbe = nil end
    ibSay("顶部信息条探针读数环已清空（存档里那份也要 /reload 才消失）")

  else
    ibSay("用法：/eh go 信息条 [状态 | 开 | 关 | 重设 | 顺序 <列表> | 诊断 | 存档 | 清]")
  end
  return true
end

-- 读值口（诊断/取证；一律给真实字段，不复刻逻辑）
function EVAL_IB_TEST_STATE()
  local c = ibCfg()
  local bgShown, linesShown = false, 0
  if SKIN.bg then
    local okb, v = pcall(SKIN.bg.IsShown, SKIN.bg)
    bgShown = (okb and v) and true or false
  end
  local i = 1
  while i <= table.getn(SKIN.lines or {}) do
    local t = (SKIN.lines or {})[i]
    local okv, v = pcall(t.IsShown, t)
    if okv and v then linesShown = linesShown + 1 end
    i = i + 1
  end
  return {
    on = EVAL_IB_ENABLED(), built = IB.built, armed = IB.evArmed, shown = ibShown(),
    labels = c.labels, bg = c.bg, locked = c.locked, order = c.order,
    profBad = c.profBad, profWarn = c.profWarn, alpha = c.alpha, skinVer = c.skinVer,
    borderColor = c.borderColor, borderAlpha = c.borderAlpha,
    x = c.x, y = c.y, free = IB.free, total = IB.total,
    memMB = IB.memMB, memShown = IB.memShown, memLimit = ibMemLimit(),
    chrome = IB_CHROME, skinBg = bgShown, skinLines = linesShown,
    fitSW = IB.fitSW, fitTW = IB.fitTW, fitEST = IB.fitEST, fitW = IB.fitW,
    lastText = IB.lastText, uncat = IB.uncat,
  }
end
