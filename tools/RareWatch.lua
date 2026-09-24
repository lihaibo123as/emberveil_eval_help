--[[ EvalHelp / tools/RareWatch.lua

-- ★★★模块必须**自带**本地化取词（同 ConsumableHelper/DismountHelper/HunterHelper 写法）；
--   项目里没有全局 `L`，裸调 `L(...)` 会被调用方的 pcall 吞掉（静默失效）。★1.74.35-3 MODULE L SCOPE CHECK 抓到的第 4 个文件。
-- ★★★1.74.36-2：模块**必须自带** `say` / `logLine` —— 项目里这两个名字**只在 Core.lua / Toolbox.lua 里是 local**，
--   模块里裸调得到的是全局 nil：轻则「如实播报」全部静默消失，重则整段代码在 pcall 里直接报错退出。
--   走 Core.lua 末尾的全局桥：`EVAL_SAY = say` / `EVAL_LOGLINE = logLine`（与 ConsumableHelper 的 chSay 同一写法）。
local function say(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end
local function logLine(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, tostring(msg)) end
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

稀有提醒转播（**独立模块**，1.74.27 从 EvalHelp.lua 提取）：任务插件 UnrealQuest 发现稀有那一刻，
在聊天框报一行（名字按品阶染色 + 可点）；点名字 = 一次 TargetByName 选中它，选不中**就报错**。

★★★用户要求（1.74.27）：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」
  ⇒ 整块搬到这里（与 tools/ 下其他助手同一形态）；**开关在工具箱 Tab**（Toolbox.lua 的 tbModel 里那行
     rareWatch，读写走本文件的 EVAL_RW_ENABLED()/EVAL_RW_SET() —— 开关只有一份真值）。
★纪律：本文件只用**全局桥**（EVAL_SAY / EVAL_LOGLINE / EVAL_L / rawget(_G,"EVAL_HELP_CONFIG") / UnrealQuest），
  绝不引用 EvalHelp.lua 的文件内 local（那些在这里看不见）。装配仍在 VARIABLES_LOADED → EvalHelp.lua 调 EVAL_RW_INSTALL。
]]

local say, logLine = EVAL_SAY, EVAL_LOGLINE
local L = EVAL_L

-- ============ 稀有提醒转播（1.74.23）============
-- ★用户需求：「只要知道他发现稀有的那一时刻，在对话框内输出一段文字」。
--
-- 机制（读 UnrealQuest 源码定案；判据见 CLAUDE.md §5.5「UnrealQuest 稀有提醒可捕获」）：
--   · 弹窗唯一出口 = World/RareAlert.lua 的 `RareAlert:Show(entry, distance, dx, dy, others)`；
--     它内部顺序是 SetAlertWindowText → UpdateArrow → Client.ShowObject → 设 shownUntil → 提示音
--     → 聊天行 → 计数 ⇒ **包住它、在原函数返回后回调** = 卡片已经出现在屏幕上那一刻。
--   · 模块注册表是公开的：全局 `UnrealQuest`（Core/Namespace.lua:17）+ `UnrealQuest:GetModule("RareAlert")`
--     （就是 UQ.modules[name] 那张**普通表**，NewModule 只塞 name/enabled、无元表保护）。
--   · ★安装时机必须是 VARIABLES_LOADED：AddOns 按目录名排序，**EvalHelp(E) 先于 UnrealQuest(U)**，
--     我们文件载入时全局 UnrealQuest 还不存在（与 DataSearch 的懒惰访问器同因）。
--   · 兜底：对方改了实现（Show 不再是函数）→ 退化为**轮询** `RareAlert:GetStatus().alerts`
--     （单调累计计数，涨了就是弹过；拿不到品阶，但不会漏）。
--   · 频率：对方自带「同怪 180 秒冷却 + inRange 抖动带」⇒ 每只怪最多 3 分钟一次，不会刷屏。
--   · ★我们**不写对方任何数据**：只在回调里读参数 + 读公开读值口；对方原函数抛错时**照原样抛出**（绝不吞）。
EVAL_RW = {
  installed = false,   -- 安装动作跑过没有（一次性）
  mode = nil,          -- "hook" 钩住弹窗 / "poll" 轮询兜底 / "none" 没挂上 / "absent" 任务插件没装
  module = nil,        -- RareAlert 模块表
  seen = 0,            -- 已转播次数
  fails = 0,           -- 异常次数（如实计数，不静默）
  lastName = nil, lastRankText = nil, lastDistance = nil, lastRank = nil,
  tgtTries = 0,        -- 选目标尝试次数（命令里如实显示）
  alerts = nil,        -- 兜底轮询的基准计数
  next = nil,          -- 轮询节流
  tick = nil,          -- 兜底轮询帧（主路不建）
}

-- 开关（默认开；存档里显式关过就尊重）。rawget 读，避免被测试桩的元表干扰（同 Core.logEnabled 做法）
function EVAL_RW_ENABLED()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return true end
  return c.rareWatch ~= false
end

-- 写开关（**与 EVAL_RW_ENABLED 同一张表**：读一处写一处，绝不让命令去改另一个 cfg 局部）
function EVAL_RW_SET(on)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) == "table" then c.rareWatch = on and true or false end
  return true
end

-- 名字要不要做成**可点链接**（默认要）。
-- ★为什么留这个闸门：链接的失败模式是「**整条不画**」（1.73.43 系列实测：色码/链接形态不对，客户端会把整条消息吞掉）
--   —— 万一这个链接形态在本客户端不被接受，玩家一条 `/eh go 稀有 链接` 就能退回「只有颜色、没有链接」的**已验证形态**。
function EVAL_RW_LINK_ON()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return true end
  return c.rareWatchLink ~= false
end
function EVAL_RW_LINK_SET(on)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) == "table" then c.rareWatchLink = on and true or false end
  return true
end

-- UnrealQuest 模块访问器（对方缺席/模块缺失一律回 nil，绝不抛错）。
-- ★DataSearch.lua 的 dsUQModule 是同款 5 行，但它是**文件内 local**；这里要跨文件用 → 提成全局。
function EVAL_UQ_MODULE(name)
  local uq = rawget(_G, "UnrealQuest")
  if type(uq) ~= "table" or type(uq.GetModule) ~= "function" then return nil end
  local ok, m = pcall(uq.GetModule, uq, name)
  if ok and type(m) == "table" then return m end
  return nil
end

-- ===== 染色（用户：「对稀有精英染色」）=====
-- 按怪物品阶取色，用**物品品质**这套玩家一眼就懂的梯度：精英 银 → 稀有 蓝 → 稀有精英 紫 → 首领 橙。
--   ★为什么不复用「方案品阶」那五色（白/绿/紫/橙/亮蓝）：那是**另一个维度**（玩家方案的稀有度），
--     本项目已有明文纪律「两个维度色码必须错开，否则同屏糊在一起」。这里用银色做最低档，与品阶的白/绿也不撞。
--   ★每个都是 **8 位**（`|c` + AARRGGBB）：6 位本客户端不解析、7 位会**吞掉整条消息**（1.73.43e 真机实测）。
--   ★拿不到品阶也必须给一个色码（兜底金）——「有色码无链接」「有链接无色码」都是被判过死刑的形态。
EVAL_RW_RANK_COLOR_MAP = {
  [1] = "|cffc0c0c0", -- 精英：银
  [2] = "|cffa335ee", -- 稀有精英：紫
  [3] = "|cffff8000", -- 首领：橙
  [4] = "|cff0070dd", -- 稀有：蓝
}
EVAL_RW_RANK_COLOR_FALLBACK = "|cffffd100" -- 品阶未知（兜底路径/新档位）→ 沿用原来的金
function EVAL_RW_RANK_COLOR(rank)
  local c = EVAL_RW_RANK_COLOR_MAP[tonumber(rank) or -1]
  if type(c) ~= "string" then return EVAL_RW_RANK_COLOR_FALLBACK end
  return c
end

-- 品阶**文本 → 档位号**反查（兜底轮询路径只有对方给的本地化文本，没有数字；染色要按数字查表）
function EVAL_RW_RANK_FROM_TEXT(txt)
  if type(txt) ~= "string" or txt == "" then return nil end
  local i = 1
  while i <= 4 do
    if EVAL_RW_RANKTEXT(i) == txt then return i end
    i = i + 1
  end
  return nil
end

-- 链接文本清洗：名字里的 `|` `]` 会把链接结构打断（怪物名正常不会有，防御性剥掉）
function EVAL_RW_LINKTEXT(s)
  local t = string.gsub(tostring(s or ""), "|", "")
  return string.gsub(t, "%]", "")
end

-- 链接 token = **只有名字**：`EHRW:<名字>`。
-- ★★★1.74.26 用户定案（原话：「点击名字逻辑很简单.不要和那边插件的机制管理.需求只要是调用类似目标函数
--   选中目标就可以了.如果目标不存在就报错.」）⇒ 链接里**不再带** areaId / 坐标 / unitId，
--   也就不再需要坐标换算、地图投影、最近刷新点那一整套 —— 点一下就是一次 `TargetByName(名字)`。
function EVAL_RW_TOKEN(name)
  local nm = EVAL_RW_LINKTEXT(name)
  if nm == "" then return nil end
  return "EHRW:" .. nm
end

-- 品阶（对方的 rnk：1 精英 / 2 稀有精英 / 3 首领 / 4 稀有，RareAlert.lua:114-117）
function EVAL_RW_RANKTEXT(rank)
  local key = nil
  if rank == 1 then key = "RW_RANK_ELITE"
  elseif rank == 2 then key = "RW_RANK_RARE_ELITE"
  elseif rank == 3 then key = "RW_RANK_BOSS"
  elseif rank == 4 then key = "RW_RANK_RARE" end
  if not key then return nil end
  return L(key)
end

-- 输出一行（两条路径共用）。rankText / rank / distance 允许缺（兜底路径只有对方给的本地化品阶文本）。
--   名字**带链接**（开关见 EVAL_RW_LINK_ON）：点它 = 一次 TargetByName（见 EVAL_RW_DO_TARGET）。
function EVAL_RW_SAY(name, rankText, rank, distance, others)
  if not EVAL_RW_ENABLED() then return nil end
  local nm = (type(name) == "string" and name ~= "") and name or L("RW_UNKNOWN")
  local rk = rankText or L("RW_RANK_MOB")
  local color = EVAL_RW_RANK_COLOR(rank)
  local shown = color .. nm .. "|r"
  if EVAL_RW_LINK_ON() then
    local token = EVAL_RW_TOKEN(nm)
    if token then
      -- ★形态照抄分享封皮那条**真机实测过**的配方（1.73.43 系列）：**一段 8 位色码 + 一个链接**，
      --   色码在外、链接在里（`|c..|H..|h[名]|h|r`）。这一条整个消息里**只有一段色码**。
      shown = color .. "|H" .. token .. "|h[" .. EVAL_RW_LINKTEXT(nm) .. "]|h|r"
    end
  end
  local line
  if type(distance) == "number" then
    line = L("RW_LINE", shown, rk, math.floor(distance + 0.5))
  else
    line = L("RW_LINE_ND", shown, rk)
  end
  if type(others) == "number" and others > 0 then line = line .. L("RW_MORE", others) end
  say(line)
  -- 日志里留一份**去色码的纯文本**，便于 /eh logdump 事后对齐时间轴
  logLine(string.format("[稀有转播] %s / %s / %s", nm, rk, tostring(distance)))
  EVAL_RW.seen = EVAL_RW.seen + 1
  EVAL_RW.lastName, EVAL_RW.lastRankText, EVAL_RW.lastDistance = nm, rk, distance
  EVAL_RW.lastRank = rank
  return line
end

-- 主路回调：entry 里只有 unitId + rank（坐标一概不看 —— 用户定案：不碰那边的地图机制）。
--   名字仍然要问对方要一次（提醒的载荷只有 unitId，名字只有它的数据库里有），这是**唯一**一处读对方数据。
function EVAL_RW_ON_SHOW(entry, distance, others)
  local name = nil
  local uid = (type(entry) == "table") and entry.unitId or nil
  local db = EVAL_UQ_MODULE("Database")
  if db and type(db.GetUnitName) == "function" and uid ~= nil then
    local ok, nm = pcall(db.GetUnitName, db, uid)
    if ok and type(nm) == "string" and nm ~= "" then name = nm end
  end
  local rank = (type(entry) == "table") and entry.rank or nil
  return EVAL_RW_SAY(name, EVAL_RW_RANKTEXT(rank), rank, distance, others)
end

-- 兜底轮询：读对方**公开读值口** RareAlert:GetStatus().alerts（单调累计计数）
function EVAL_RW_POLL()
  local RA = EVAL_RW.module
  if type(RA) ~= "table" or type(RA.GetStatus) ~= "function" then return false end
  local ok, st = pcall(RA.GetStatus, RA)
  if not ok or type(st) ~= "table" or type(st.alerts) ~= "number" then
    EVAL_RW.fails = EVAL_RW.fails + 1
    return false
  end
  if EVAL_RW.alerts == nil then
    EVAL_RW.alerts = st.alerts -- ★首读只立基准：不把「本次登录之前的历史计数」当成刚弹过
    return false
  end
  if st.alerts > EVAL_RW.alerts then
    EVAL_RW.alerts = st.alerts
    -- 兜底路径只有对方给的**本地化品阶文本**（没有档位号）→ 反查它染色；坐标也拿不到 → 不带链接
    return EVAL_RW_SAY(st.lastName, st.lastRank, EVAL_RW_RANK_FROM_TEXT(st.lastRank),
      st.lastDistance, nil, nil) ~= nil
  end
  return false
end

-- 轮询节流（0.5s；**只有兜底路径**才跑 tick，主路一次都不跑）
function EVAL_RW_TICK_STEP()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if EVAL_RW.next and now < EVAL_RW.next then return false end
  EVAL_RW.next = now + 0.5
  return EVAL_RW_POLL()
end

function EVAL_RW_ENSURE_TICK()
  if EVAL_RW.tick then return true end
  -- ★★★父级必须是 WorldFrame：本客户端「任一祖先被隐藏即不派发 OnUpdate」，而开全屏世界地图时
  --   UIParent 被隐藏 → 挂它下面的 tick 整个停摆（1.70.39 踩过；DataSearch.lua:2234-2261 有全文）。
  local parent = rawget(_G, "WorldFrame") or UIParent
  if not parent then return false end
  local ok, f = pcall(CreateFrame, "Frame", "EVAL_RARE_WATCH_TICK", parent)
  if not ok or not f then return false end
  EVAL_RW.tick = f
  pcall(f.SetScript, f, "OnUpdate", function() EVAL_RW_TICK_STEP() end)
  return true
end

-- 安装（VARIABLES_LOADED 调一次；幂等）。返回 mode 字符串，调用方可以如实转述。
function EVAL_RW_INSTALL()
  if EVAL_RW.installed then return EVAL_RW.mode end
  EVAL_RW.installed = true
  local RA = EVAL_UQ_MODULE("RareAlert")
  if type(RA) ~= "table" then
    -- 对方缺席（没装/没启用）→ 如实记状态，**不报错、不静默**（/eh go 稀有 会说明）
    EVAL_RW.mode = (rawget(_G, "UnrealQuest") == nil) and "absent" or "none"
    return EVAL_RW.mode
  end
  EVAL_RW.module = RA

  local orig = RA.Show
  if type(orig) == "function" then
    -- ★透明包装：原函数返回值逐个透传；**原函数抛错就按原语义抛出去**（不吞别人的错），
    --   只在抛错时如实计数 + 记一行日志，然后照原样 error。
    RA.Show = function(self, entry, distance, dx, dy, others)
      local ok, a, b, c, d = pcall(orig, self, entry, distance, dx, dy, others)
      if ok then
        pcall(EVAL_RW_ON_SHOW, entry, distance, others)
      else
        EVAL_RW.fails = EVAL_RW.fails + 1
        logLine("[稀有转播] 原 RareAlert:Show 抛错（已按其原语义抛出）：" .. tostring(a))
        error(a, 0)
      end
      return a, b, c, d
    end
    EVAL_RW.mode = "hook"
    return EVAL_RW.mode
  end

  -- ② 兜底：Show 不可包 → 轮询公开计数
  if type(RA.GetStatus) == "function" and EVAL_RW_ENSURE_TICK() then
    EVAL_RW.mode = "poll"
  else
    EVAL_RW.mode = "none"
  end
  return EVAL_RW.mode
end

function EVAL_RW_MODETEXT()
  local m = EVAL_RW.mode
  if m == "hook" then return L("RW_MODE_HOOK") end
  if m == "poll" then return L("RW_MODE_POLL") end
  if m == "absent" then return L("RW_MODE_ABSENT") end
  return L("RW_MODE_NONE")
end

-- /eh go 稀有 [状态|开|关|试]
-- ★"go 稀有" = 3 + 6 = **9 字节**（string.sub 是字节下标；1.74.5 在「go 喂食」上正是栽在这里）。
function EVAL_RW_CMD(msg)
  local rest = string.gsub(string.sub(tostring(msg or ""), 10), "^%s+", "")
  if rest == "开" or rest == "on" then
    EVAL_RW_SET(true)
    say(L("RW_STATE", L("SH_ON"), EVAL_RW_MODETEXT(), EVAL_RW.seen))
  elseif rest == "关" or rest == "off" then
    EVAL_RW_SET(false)
    say(L("RW_STATE", L("SH_OFF"), EVAL_RW_MODETEXT(), EVAL_RW.seen))
  elseif rest == "试" then
    -- 走对方的测试弹窗（/uq rare test 同一条路）→ 完整链路自证：它会调 Show → 我们的回调必须转播一行
    local RA = EVAL_RW.module
    if type(RA) ~= "table" or type(RA.TestNearest) ~= "function" then
      say(L("RW_TEST_FAIL", EVAL_RW_MODETEXT()))
    else
      local ok, nm, why = pcall(RA.TestNearest, RA)
      if ok and type(nm) == "string" and nm ~= "" then
        say(L("RW_TEST_OK", nm))
      else
        say(L("RW_TEST_FAIL", tostring(why or nm)))
      end
    end
  elseif rest == "目标" then
    -- 等价「左键点聊天行里的名字」
    EVAL_RW_DO_TARGET(nil)
  elseif rest == "目标探针" then
    -- ★取证命令：用**当前目标自己的名字**（必然存在、必然在附近）验 TargetByName 到底能不能用
    EVAL_RW_TARGET_PROBE()
  elseif rest == "链接" then
    local on = not EVAL_RW_LINK_ON()
    EVAL_RW_LINK_SET(on)
    say(L("RW_LINK_SET", on and L("SH_ON") or L("SH_OFF")))
  elseif rest == "" or rest == "状态" then
    say(L("RW_STATE", EVAL_RW_ENABLED() and L("SH_ON") or L("SH_OFF"), EVAL_RW_MODETEXT(), EVAL_RW.seen))
    say(L("RW_LINK_STATE", EVAL_RW_LINK_ON() and L("SH_ON") or L("SH_OFF"),
      tostring(EVAL_RW.tgtTries or 0)))
    if EVAL_RW.lastName then
      local d = (type(EVAL_RW.lastDistance) == "number")
        and tostring(math.floor(EVAL_RW.lastDistance + 0.5)) or "?"
      say(L("RW_LAST", EVAL_RW.lastName, tostring(EVAL_RW.lastRankText or "?"), d))
    else
      say(L("RW_NOLAST"))
    end
    say(L("RW_USAGE"))
  else
    say(L("RW_USAGE"))
  end
end

-- ===== 点了名字之后能做什么（用户两条要求都落在这里）=====
--   ① 「点击他……定位目标」＋「点击头像相当于目标切换到稀有精英目标」→ **左键点名字 = 把目标切到那只稀有**；
--   ② 上一轮的「在地图上定位」→ **右键点名字 = 打开世界地图并标出它的最近刷新点**。

-- ★客户端事实（铁律 5：先核 API 本身）：`TargetByName` 在**官方 API 索引**里
--   （`api_unit.html` 的索引项：name=TargetByName · category=Targetting ·
--     url=emberveil.org/wiki/lua/globals/Targetting#targetbyname），语义 = 「按名字选中附近的一个单位」。
--   ★但「附近没有这只」时它的确切行为**在本机没有文档可查**（该 wiki 正文是 JS 渲染，抓不到文本）——
--     所以这里**不猜**：调用前后各读一次 `UnitName("target")`，**用前后比对如实判定**结果再报给玩家。
--   ★这也是对方 RareAlert 明确**不做**的事（RareAlert.lua:23-27：会抢走玩家目标、战斗中也不例外）——
--     区别在于：他们是**自动**扫描时不敢做，我们这里是**玩家主动点一下**，所以可以做。
function EVAL_RW_TARGET(name)
  if type(name) ~= "string" or name == "" then return "noname" end
  if type(TargetByName) ~= "function" then return "noapi" end
  local before = (type(UnitName) == "function") and UnitName("target") or nil
  local ok = pcall(TargetByName, name)
  if not ok then return "error" end
  local after = (type(UnitName) == "function") and UnitName("target") or nil
  if after == name then return "ok" end
  if after == before then return "notfound" end
  if after == nil then return "cleared" end
  return "other"
end

-- ★★★1.74.26 用户定案（原话：「调用类似目标函数选中目标就可以了.如果目标不存在就报错」）⇒
--   结果只有两种：**选中了** / **选不中（报错）**。不再解释机制、不再报距离、不再区分四五种原因 ——
--   唯一保留的诚实点是：**必须核对结果**（读一次 UnitName("target")），否则「点了没反应」会被报成成功。
function EVAL_RW_TARGET_TEXT(ok, name)
  if ok then return L("RW_TGT_OK", name) end
  return L("RW_TGT_FAIL", name)
end

-- 目标探针（一次定案的取证命令）：用**当前目标自己的名字**（必然存在、必然在附近）去验接口到底能不能用。
--   ★为什么要它：用户报「目标存在却提示不在」。两种可能①**客户端只认附近单位**（文档明文，远处静默失败）
--     ②本客户端的 TargetByName 对插件是**空操作**。这两者从结果上长得一模一样 —— 只有拿一个「必然在附近」
--     的名字做实验才能分开。★同时打印数据库给的那份名字与字节数，便于和屏幕上看到的名字逐字对照
--     （排掉「数据库名字 ≠ 客户端名字」这第三种可能）。
function EVAL_RW_TARGET_PROBE()
  local has = type(TargetByName) == "function"
  say(L("RW_TP_HEAD", has and L("SH_ON") or L("SH_OFF")))
  local cur = (type(UnitName) == "function") and UnitName("target") or nil
  say(L("RW_TP_CUR", (type(cur) == "string" and cur ~= "") and cur or L("RW_TP_NONE")))
  if not has then return false end
  if type(cur) ~= "string" or cur == "" then
    say(L("RW_TP_NEED"))
    return false
  end
  if type(ClearTarget) == "function" then pcall(ClearTarget) end
  local mid = (type(UnitName) == "function") and UnitName("target") or nil
  say(L("RW_TP_CLEARED", (type(mid) == "string" and mid ~= "") and mid or L("RW_TP_NONE")))
  -- 用 DO_TARGET（同一入口）取判定码：它内部会打印「已选中/选不中」那一行
  local code = EVAL_RW_DO_TARGET(cur) and "ok" or "fail"
  local after = (type(UnitName) == "function") and UnitName("target") or nil
  say(L("RW_TP_BACK", cur, (type(after) == "string" and after ~= "") and after or L("RW_TP_NONE"), code))
  if type(EVAL_RW.lastName) == "string" and EVAL_RW.lastName ~= "" then
    say(L("RW_TP_NAME", EVAL_RW.lastName))
  end
  if code == "ok" then say(L("RW_TP_OK")) else say(L("RW_TP_FAIL")) end
  logLine("[稀有转播] 目标探针：has=" .. tostring(has) .. " cur=" .. tostring(cur)
    .. " after=" .. tostring(after) .. " code=" .. code)
  return code == "ok"
end

-- ★点名字（或命令 /eh go 稀有 目标）的全部逻辑：给名字 → 调目标函数 → 核对 → 报告。
--   不碰那边的坐标/地图/数据库机制，不做任何退路动作 —— 用户定案。
function EVAL_RW_DO_TARGET(name)
  local nm = (type(name) == "string" and name ~= "") and name or EVAL_RW.lastName
  if type(nm) ~= "string" or nm == "" then say(L("RW_NO_LAST")) return false end
  EVAL_RW.tgtTries = (EVAL_RW.tgtTries or 0) + 1
  if type(TargetByName) ~= "function" then
    say(L("RW_TGT_NOAPI"))
    return false
  end
  local ok = pcall(TargetByName, nm)
  local after = (type(UnitName) == "function") and UnitName("target") or nil
  local hit = (ok and after == nm)
  say(EVAL_RW_TARGET_TEXT(hit, nm))
  logLine("[稀有转播] 选目标 " .. nm .. " → " .. (hit and "成功" or "失败") .. "（现目标 " .. tostring(after) .. "）")
  return hit
end

-- SetItemRef 分派入口（Toolbox 的 EVAL_TB_SIR_HANDLE 收到 `EHRW:` 前缀后调这里）。
--   ★就一件事：**把名字取出来 → 调目标函数**。没有第二动作、没有退路、不看按键
--     （按键参数留着只是为了兼容调用点；任意键都做同一件事，行为可预测）。
function EVAL_RW_LINK_CLICK(link, button)
  local nm = string.match(tostring(link or ""), "^EHRW:(.+)$")
  return EVAL_RW_DO_TARGET(nm)
end

-- 测试钩子：把安装状态清回「未安装」（安装是一次性的，判据要能反复驱动**真实安装路径**）。
-- ★摘不掉已包上的 Show（就同「SetScript(type,nil) 不能卸载脚本」一样），测试每次换一张新的假模块表即可。
function EVAL_TEST_RW_RESET()
  if EVAL_RW.tick then pcall(EVAL_RW.tick.SetScript, EVAL_RW.tick, "OnUpdate", nil) end
  EVAL_RW.installed, EVAL_RW.mode, EVAL_RW.module, EVAL_RW.alerts = false, nil, nil, nil
  EVAL_RW.tgtTries = 0
  return true
end

-- 读值口：给判据读**真实状态**（不是复刻一遍映射逻辑）
function EVAL_TEST_RW_STATE()
  return {
    mode = EVAL_RW.mode, installed = EVAL_RW.installed, seen = EVAL_RW.seen, fails = EVAL_RW.fails,
    hasTick = EVAL_RW.tick ~= nil, lastName = EVAL_RW.lastName,
    lastRankText = EVAL_RW.lastRankText, lastDistance = EVAL_RW.lastDistance,
    lastRank = EVAL_RW.lastRank, linkOn = EVAL_RW_LINK_ON(),
    tgtTries = EVAL_RW.tgtTries or 0,
  }
end


if type(EVAL_LOAD_MARK) == "function" then EVAL_LOAD_MARK("files") end -- ★1.74.31 全部源码加载完毕
