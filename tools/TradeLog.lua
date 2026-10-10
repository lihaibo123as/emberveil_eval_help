-- ============================================================================
-- 交易记录（交易窗口右侧挂靠的历史列表）—— tools/TradeLog.lua
-- ============================================================================
-- 用户 2026-10-10 定：「工具箱->增加个交易记录信息列表.支持滚动.显示信息为目标信息,金币,
--   物品时间等信息,列表挂靠在每次开启交易的窗口右侧.,交易数据支持清空,某一条邮件删除.
--   点击条目可以直接开启和他对话」
--   ★★「某一条邮件删除」按「**某一条右键删除**」实现 —— 左键已经被用户点名的「开启和他对话」占用，
--     与自动丢弃助手 / 消耗品助手的「行左键做主线动作、右键删这一条」是同一套交互；
--     若原意是别的（例如「删整条要二次确认」），改这一处即可。
--   ★★「清空」= **两次点击确认**（第一下只武装、按钮文案改成「再点确认」，3 秒内再点才真清）——
--     照项目对破坏性动作的既定口径；单条删除**一次点击就动手**（明确瞄准的一行 + 右键）。
--
-- ── 客户端事实（全部来自本客户端自带的 FrameXML，逐条可复算）──────────────────
--   · 文件 = `Interface\FrameXML\TradeFrame.lua`（本机导出件 `tmp/mpq_out/Interface/FrameXML/TradeFrame.lua`）
--   · 事件 = `TRADE_SHOW` / `TRADE_CLOSED` / `TRADE_UPDATE` / `TRADE_PLAYER_ITEM_CHANGED`(arg1=格号) /
--     `TRADE_TARGET_ITEM_CHANGED`(arg1=格号) / `TRADE_ACCEPT_UPDATE`(arg1=我方状态, arg2=对方状态)
--   · 对方名字 = **`UnitName("NPC")`**（客户端自己那一行就是 `TradeFrameRecipientNameText:SetText(UnitName("NPC"))`）
--   · 读取口 = `GetTradePlayerItemLink(i)` / `GetTradeTargetItemLink(i)`（`TradeFrame.xml:95/129` 在用）、
--     `GetTradePlayerItemInfo(i)` / `GetTradeTargetItemInfo(i)`（第 3 返回 = 数量）、
--     `GetPlayerTradeMoney()` / `GetTargetTradeMoney()`（`MoneyFrame.lua:50/66` 在用）
--   · 格数 = `MAX_TRADE_ITEMS`=7（第 7 格是附魔格）/ **`MAX_TRADABLE_ITEMS`=6**（可交易格）——
--     我们**只扫 1..6**（附魔格里的"东西"不是物品）
--   · 密语口 = **`ChatFrame_SendTell(name, chatFrame)`**（`ChatFrame.lua:1675`，`/w` 走的就是它）；
--     拿不到才退 `ChatFrame_OpenChat("/w " .. name .. " ", DEFAULT_CHAT_FRAME)`（同处 `:1684` 的原文写法）
--   · 「完成」信号 = `ERR_TRADE_COMPLETE`（**本地化字符串**，本客户端 zhCN = 「交易完成。」）——
--     它属 `UI_INFO_MESSAGE` 那一族（该项目已实测该事件 arg1 就是消息正文，见 `doc/通道信息记录.md`）。
--     ★★本客户端「交易完成到底走不走 UI_INFO_MESSAGE」**离线判不出** ⇒ 结果判定设计成**三条腿**，
--       且 `/eh go 交易记录 探针` 会把「最近一次收尾怎么判的」原样摊开 —— 真机一跑就知道走哪条。
--
-- ── 结果判定（三条腿；**绝不假装成功也绝不假装失败**）──────────────────────
--   ① **完成信号**：收到正文 == `ERR_TRADE_COMPLETE` ⇒ `ok = true`（最权威）；
--   ② **钱对账**：`GetMoney()` 的变化 == 我得到的钱 − 我给出的钱（且期望值非 0）⇒ `ok = true`；
--   ③ 都判不出：双方都点过确认 ⇒ `ok = nil`（如实写「双方已确认」）；否则 ⇒ `ok = false`（取消/失败）。
--   ★★为什么要**收尾核对窗**：`UI_INFO_MESSAGE` 与 `TRADE_CLOSED` 的先后次序未知 ⇒ 关窗后开一个
--     有界核对窗（`TL_VERIFY` = 0.8s，`TL_BEAT` = 0.25s 一拍）：窗口里收到完成信号或钱对得上 ⇒ 立刻按①/②
--     落账；过窗仍判不出 ⇒ 按③如实落账。
--
-- ── 记录内容（一条 = 一次交易）──────────────────────────────────────────────
--   `{ t = 时刻字符串, who = 对方名字, gm = 我给出的铜, gt = 我得到的铜,
--      give = { {n=名字, c=数量, l=链接}, … }, get = { … }, ok = true/false/nil, why = 判定依据键 }`
--   ★**空交易不记**（既没有物品也没有钱 ⇒ 什么都不写，免得历史里全是噪声）；
--   ★**有界** `TL_MAX` = 40 条（最新在前，超了丢最老的）；每条最多 6+6 件（`MAX_TRADABLE_ITEMS`）。
--
-- ── 存档（分两份，与其它助手同一把尺子）────────────────────────────────────
--   · **开关** = `tbCfg().tradeLog`（工具箱那一行的勾选框；**默认开** —— 用户点名要的功能，
--     `nil` 视为开、**显式关过（false）永远是关**；关着 = 不注册事件、不挂节拍、不建帧）；
--   · **数据** = **角色级** `EVAL_TB_CHAR_STORE().tradeLogList`（交易历史是「这个角色做过什么」，
--     与各位助手的位置/大小同一个存储口径；不写账号表）。
--
-- ── 关断四件事（工具箱勾选框取消时走 `EVAL_TL_SYNC`）──────────────────────
--   ① 资源回收：面板与行池收起（1.12 **没有销毁帧/纹理的 API** ⇒ 帧只 `Hide` 留着复用 —— 代价如实写在这里）；
--   ② 节拍停止：`SetScript(beat, "OnUpdate", nil)` **真摘**（不是每帧早退）；
--   ③ 数据重置：会话态（本次交易快照 / 核对窗 / 页码 / 武装态 / 宽事件注册）当场复位；
--   ④ 图层清理：我们**没有改过任何客户端对象**（只**读** `TradeFrame` 的几何来挂靠，一个字节都没写）
--      ⇒ 退回时只需收起自己建的帧。
--   ★★★**本面板有意不做全屏捕手**：它是**陪伴窗**（要能一边看一边点交易窗的确定/取消），
--     捕手会盖住交易窗 ⇒ 那就是「点不动了」。关闭出口只有两个：标题栏 `[×]` 与工具箱那一行。
--   ★★**宽事件（`UI_INFO_MESSAGE`）只在交易期间注册**（开窗时挂、收尾落账后摘）—— 「用的时候才启用」。
--
-- ── 载入期零副作用 ────────────────────────────────────────────────────────
--   顶层只声明常量/表/函数；**不建帧、不注册事件、不读存档**（`EVAL_TL_INSTALL` 由 VARIABLES_LOADED 调）。
--   ★帧名 `EVAL_TL_PANEL` 与函数名（`EVAL_TL_*`）**不同名** —— 具名帧顶掉同名全局函数是项目在案的老坑（组 54）。
-- ============================================================================

local TL = {
  built = false,   -- 面板建过没有
  off = 0,         -- 行偏移（滚动唯一真值，双侧夹）
  cur = nil,       -- 本次交易快照（窗口开着时）
  pend = nil,      -- 收尾核对窗 `{ c = <快照>, at = <时刻> }`
  mode = "free",   -- "attach" = 贴交易窗 / "free" = 工具箱按钮开出来的
  armAt = 0,       -- [清空] 第一次点击的武装时刻（两次点击确认）
  last = "",       -- 最近一次动作/判定（探针读数用）
  ev = nil,        -- 事件帧（唯一）
  beat = nil,      -- 唯一节拍帧（只在核对窗里挂）
  beatAt = 0,
  probe = {},      -- 有界取证环（最近 TL_PROBE_MAX 条；不落盘 —— 交易是低频动作）
}

-- ── 常量（单一来源）────────────────────────────────────────────────────────
local TL_MAX = 40          -- 历史条数上限（有界，最新在前）
local TL_ROWS = 9          -- 面板行池（单行条目 ⇒ 比两行那版多一行）
local TL_ROW_H = 20        -- ★单行条目（时间/对方/金币/物品图标同一行 —— 图标已直观，名字不画 ⇒ 紧凑）
local TL_W, TL_H = 316, 280
local TL_GAP = 0           -- ★0 = **紧贴**交易窗（用户 2026-10-10：面板紧贴交易窗）
local TL_ITEM_MAX = 6      -- 可交易格数上限（= MAX_TRADABLE_ITEMS，读不到用这个）
local TL_VERIFY = 0.8      -- 收尾核对窗（秒）：等完成信号 / 等钱到账
local TL_BEAT = 0.25       -- 核对窗里的节拍间隔
local TL_ARM_SEC = 3.0     -- [清空] 两次点击确认的窗口
local TL_PROBE_MAX = 20    -- 取证环上限
-- ★物品图标（用户：「显示实际的目标物图标…支持悬浮显示物品图标悬浮物品显示信息，物品名称可不显示」）
local TL_ICON_N = 5        -- 每条最多画几个图标（超出的如实写 +N；悬停里有全量）
local TL_ICON = 16         -- 图标边长
local TL_ICON_GAP = 2      -- 图标之间的缝
local TL_ICON_CAP = 4      -- 超过 TL_ICON_N 件时只画 4 个、留一格给「+N」
local TL_ICON_X = 198      -- 图标带在**行按钮内**的起点（= 面板 x 202 − 行按钮 x 4；与列头同源）
-- 方向色（哪里给出 / 哪里得到一眼分得清，不靠文字）：红 = 我给出 · 绿 = 我得到
local TL_GIVE_RGB = { 0.95, 0.45, 0.40 }
local TL_GET_RGB = { 0.50, 0.95, 0.55 }
-- ★系统经典边框圆角（用户：「边框采用系统经典边框圆角」）—— 照客户端自带 GameTooltipTemplate 的配方：
--   bgFile/edgeFile/edgeSize 16/tileSize 16/背景内缩 5（`tmp/mpq_out/Interface/FrameXML/GameTooltipTemplate.xml:4-13`）
local TL_BG_FILE = "Interface\\Tooltips\\UI-Tooltip-Background"
local TL_EDGE_FILE = "Interface\\Tooltips\\UI-Tooltip-Border"
local TL_BG_ALPHA = 0.85   -- ★背景黑色 85%（用户点名）


-- ★前向声明（R2 老雷：事件处理体与面板闭包写在被调函数之前，直接 `local function` 会让它们绑全局 nil）
local tlRefresh, tlShow, tlHide, tlBuild, tlPlace, tlSnap, tlOpenSession, tlCloseSession
local tlTell, tlTick, tlBeatTick, tlBeatSync, tlOnEvent, tlMsgArm

-- ── 桥（一律「调用时现读」+ pcall；拿不到就如实降级，绝不硬造全局）───────────
local function G(name) return rawget(_G, name) end

local function L(k, ...)
  local f = G("EVAL_L")
  if type(f) == "function" then
    local ok, v = pcall(f, k, ...)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return tostring(k)
end

local function say(txt)
  local f = G("EVAL_SAY")
  if type(f) == "function" then pcall(f, tostring(txt)) end
end

-- ★用户主动敲命令 / 点界面 ⇒ 一律可见（「调试日志」总闸门默认关着也不许把回话吞掉）
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

-- 角色级存档访问口（宿主桥；模块绝不自己碰 SavedVariables 根）
local function charStore()
  local f = G("EVAL_TB_CHAR_STORE")
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f)
  if ok and type(v) == "table" then return v end
  return nil
end

-- 开关真值：`tbCfg().tradeLog`（nil = 开；显式 false 永远是关）
function EVAL_TL_ON()
  local tb = tbCfgGet()
  if type(tb) ~= "table" then return false end
  return tb.tradeLog ~= false
end

-- ── 小工具 ────────────────────────────────────────────────────────────────
local function tlNow()
  return (type(GetTime) == "function") and (GetTime() or 0) or 0
end

local function tlClock()
  if type(date) == "function" then
    local ok, s = pcall(date, "%m-%d %H:%M")
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  return ""
end

local function tlShown(f)
  if not f then return false end
  local ok, v = pcall(f.IsShown, f)
  return (ok and v) and true or false
end

local function tlSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b)
  pcall(tex.SetAlpha, tex, a or 1)
end

local function tlText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  pcall(fs.SetFont, fs, "Fonts\\FZLBJW.TTF", size, "")
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

-- 带色铜钱（照 `tools/ItemPrice.lua` 的口径：本客户端 inline texture `|T…|t` 不渲染 ⇒ 只能字母 + 色）
local function tlMoney(c)
  c = math.floor(tonumber(c) or 0)
  if c < 0 then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor(c / 100) - g * 100
  local p = c - math.floor(c / 100) * 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  return out .. "|cffeda55f" .. p .. "c|r"
end

local function tlLinkName(link)
  if type(link) ~= "string" then return nil end
  local nm = string.match(link, "%[(.-)%]")
  if type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

-- 按**字符**数宽（绝不按字节 —— 汉字 3 字节，按字节会切出半个字）
local function tlCharLen(s)
  local n, i = 0, 1
  local len = string.len(s)
  while i <= len do
    local b = string.byte(s, i)
    if b >= 240 then i = i + 4
    elseif b >= 224 then i = i + 3
    elseif b >= 192 then i = i + 2
    else i = i + 1 end
    n = n + 1
  end
  return n
end

local function tlClip(s, maxChars)
  s = tostring(s or "")
  maxChars = tonumber(maxChars) or 8
  if tlCharLen(s) <= maxChars then return s end
  local out, n, i = "", 0, 1
  local len = string.len(s)
  while i <= len and n < maxChars - 1 do
    local b = string.byte(s, i)
    local step = 1
    if b >= 240 then step = 4
    elseif b >= 224 then step = 3
    elseif b >= 192 then step = 2 end
    out = out .. string.sub(s, i, i + step - 1)
    i = i + step
    n = n + 1
  end
  return out .. "…"
end

-- 鼠标键：本项目既有 idiom —— 处理体参数可能在 a / b / 全局 arg1 三处（1.75.59b 真机定案）
local function tlMouseBtn(a, b)
  if a == "RightButton" or b == "RightButton" or rawget(_G, "arg1") == "RightButton" then return "RightButton" end
  return "LeftButton"
end

-- ── 数据（角色级存档；模块只经桥写）──────────────────────────────────────
local function tlList()
  local st = charStore()
  if type(st) ~= "table" then return nil end
  if type(st.tradeLogList) ~= "table" then st.tradeLogList = {} end
  local l = st.tradeLogList
  -- ★自愈：条数超上限（老存档 / 手改）⇒ 当场截断（有界是硬要求）
  local n = table.getn(l)
  if n > TL_MAX then
    for i = n, TL_MAX + 1, -1 do l[i] = nil end
  end
  return l
end

local function tlCount()
  local l = tlList()
  return l and table.getn(l) or 0
end

-- 入账（最新在前）；返回写入后的条数
local function tlPush(rec)
  local l = tlList()
  if not l or type(rec) ~= "table" then return 0 end
  table.insert(l, 1, rec)
  local n = table.getn(l)
  if n > TL_MAX then
    for i = n, TL_MAX + 1, -1 do l[i] = nil end
  end
  return table.getn(l)
end

-- 删第 idx 条（坏下标 ⇒ nil，一个字节都不动）
local function tlDel(idx)
  local l = tlList()
  if not l then return nil end
  idx = tonumber(idx)
  local n = table.getn(l)
  if not idx or idx < 1 or idx > n then return nil end
  return table.remove(l, idx)
end

local function tlClearAll()
  local l = tlList()
  if not l then return 0 end
  local n = table.getn(l)
  for i = 1, n do l[i] = nil end
  return n
end

-- ── 取证环（有界、不落盘：交易是低频动作，环只服务探针 / 真机排查）────────────
local function tlNote(line)
  table.insert(TL.probe, 1, tlClock() .. " " .. tostring(line))
  local n = table.getn(TL.probe)
  if n > TL_PROBE_MAX then
    for i = n, TL_PROBE_MAX + 1, -1 do TL.probe[i] = nil end
  end
  TL.last = tostring(line)
end

-- ── 交易快照 ──────────────────────────────────────────────────────────────
local function tlPartner()
  local f = G("UnitName")
  if type(f) ~= "function" then return nil end
  local ok, nm = pcall(f, "NPC")
  if ok and type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

local function tlReadMoney(fname)
  local f = G(fname)
  if type(f) ~= "function" then return 0 end
  local ok, v = pcall(f)
  local n = ok and tonumber(v) or nil
  return n or 0
end

-- 读一侧的物品（mine = true ⇒ 我给出的那一半；false ⇒ 对方给出的那一半）
local function tlItems(mine)
  local out = {}
  local n = TL_ITEM_MAX
  local mx = rawget(_G, "MAX_TRADABLE_ITEMS")
  if type(mx) == "number" and mx >= 1 and mx <= 14 then n = mx end
  local flink = G(mine and "GetTradePlayerItemLink" or "GetTradeTargetItemLink")
  local finfo = G(mine and "GetTradePlayerItemInfo" or "GetTradeTargetItemInfo")
  for i = 1, n do
    local link = nil
    if type(flink) == "function" then
      local ok, v = pcall(flink, i)
      if ok and type(v) == "string" and v ~= "" then link = v end
    end
    if link then
      local cnt, tex = nil, nil
      if type(finfo) == "function" then
        -- ★多返回值绝不套 pcall/tostring 再当参数用（那只留第一个返回）⇒ 分别接住
        --   ★第 2 返回 = 物品贴图（客户端现给）⇒ **当场记下来**（画图标时不必再查 GetItemInfo）
        local ok, _nm, tx, num = pcall(finfo, i)
        if ok then cnt = tonumber(num) tex = tx end
      end
      out[table.getn(out) + 1] = {
        l = link, n = tlLinkName(link) or "?", c = cnt or 1,
        tx = (type(tex) == "string" and tex ~= "") and tex or nil,
      }
    end
  end
  return out
end

tlSnap = function()
  local c = TL.cur
  if type(c) ~= "table" then return false end
  c.who = tlPartner() or c.who
  c.gm = tlReadMoney("GetPlayerTradeMoney")   -- 我给出的钱
  c.gt = tlReadMoney("GetTargetTradeMoney")   -- 我得到的钱
  c.give = tlItems(true)
  c.get = tlItems(false)
  return true
end

local function tlHasContent(c)
  if type(c) ~= "table" then return false end
  if (tonumber(c.gm) or 0) > 0 or (tonumber(c.gt) or 0) > 0 then return true end
  if table.getn(c.give or {}) > 0 or table.getn(c.get or {}) > 0 then return true end
  return false
end

-- ── 结果判定 + 落账 ───────────────────────────────────────────────────────
-- 返回 ok(true / false / nil) + 判定依据**语言键**
local function tlVerdict(c)
  if type(c) ~= "table" then return nil, "TL_WHY_UNK" end
  if c.complete == true then return true, "TL_WHY_COMPLETE" end
  local moneyNow = nil
  local f = G("GetMoney")
  if type(f) == "function" then
    local ok, v = pcall(f)
    if ok then moneyNow = tonumber(v) end
  end
  local gm, gt = tonumber(c.gm) or 0, tonumber(c.gt) or 0
  local exp = gt - gm                 -- 期望变化 = 收到 − 付出
  if type(moneyNow) == "number" and type(c.money0) == "number" then
    local got = moneyNow - c.money0   -- 实际变化
    if exp ~= 0 and got == exp then return true, "TL_WHY_MONEY" end
  end
  if c.both == true then return nil, "TL_WHY_BOTH" end
  return false, "TL_WHY_CANCEL"
end

-- 落账（唯一写口）：空交易不记；返回 true = 真写了一条
local function tlRecord(c)
  if type(c) ~= "table" then return false end
  if not tlHasContent(c) then
    tlNote("空交易 ⇒ 不记（关窗时没有任何物品与金钱）")
    return false
  end
  local ok, why = tlVerdict(c)
  local rec = {
    t = (type(c.clock) == "string" and c.clock ~= "") and c.clock or tlClock(),
    who = (type(c.who) == "string" and c.who ~= "") and c.who or "?",
    gm = tonumber(c.gm) or 0,
    gt = tonumber(c.gt) or 0,
    give = c.give or {},
    get = c.get or {},
    ok = ok,
    why = why,
  }
  local n = tlPush(rec)
  tlNote(string.format("落账：判定=%s ｜ 对方=%s ｜ 给=%d 铜 / 收=%d 铜 ｜ 给件=%d / 收件=%d ｜ 依据=%s ｜ 共 %d 条",
    tostring(ok), tostring(rec.who), rec.gm, rec.gt,
    table.getn(rec.give), table.getn(rec.get), L(why), n))
  return true
end

tlOpenSession = function()
  -- ★★★上一笔还在核对窗里 ⇒ **先如实落账、再开新的** —— 不先落账就把它静默丢了
  --   （`TL.pend` 一被覆盖，那笔交易就永远不会进历史；本模块的 harness 当场抓到过这一条）
  if type(TL.pend) == "table" then
    local prev = TL.pend
    TL.pend = nil
    tlRecord(prev.c)
  end
  local c = {
    t0 = tlNow(),
    clock = tlClock(),
    who = tlPartner(),
    money0 = nil,
    gm = 0, gt = 0,
    give = {}, get = {},
    both = false,
    complete = false,
  }
  local f = G("GetMoney")
  if type(f) == "function" then
    local ok, v = pcall(f)
    if ok then c.money0 = tonumber(v) end
  end
  TL.cur = c
  TL.pend = nil
  tlSnap()
  tlNote("开窗：对方=" .. tostring(c.who) .. " ｜ 我的钱基准=" .. tostring(c.money0))
  return c
end

-- 窗口关闭：能当场判定就落账，判不出就开**有界核对窗**（等完成信号 / 等钱到账）
tlCloseSession = function()
  local c = TL.cur
  TL.cur = nil
  if type(c) ~= "table" then return false end
  tlSnap()                                  -- ★关窗前再读一次（兜最后一次变化）
  local ok = tlVerdict(c)
  if ok == true then
    tlRecord(c)
    return true
  end
  c.money0 = c.money0 or 0
  TL.pend = { c = c, at = tlNow() }
  tlNote("收尾还判不出 ⇒ 开核对窗（上限 " .. tostring(TL_VERIFY) .. " 秒：等完成信号 / 等钱到账；过窗按实际判定落账）")
  return false
end

local function tlPendTick(now)
  local p = TL.pend
  if type(p) ~= "table" then return false end
  local c = p.c
  if type(c) ~= "table" then TL.pend = nil return true end
  local ok = tlVerdict(c)
  if ok == true then
    TL.pend = nil
    tlRecord(c)
    return true
  end
  if (now - (p.at or 0)) >= TL_VERIFY then
    TL.pend = nil
    tlRecord(c)                              -- 过窗 ⇒ 按如实判定落账（可能是 nil「判不出」）
    return true
  end
  return false
end

-- ══════════════════════════ 面板 ══════════════════════════
-- ★★★面板外观（用户 2026-10-10 定）：「面板紧贴交易窗.背景黑色85%边框采用系统经典边框圆角.
--   交易记录条目样式对齐美化下.显示实际的目标物图标.支持悬浮显示物品图标悬浮物品显示信息,
--   物品名称可不显示.已经有图标直观体现了.所以列项可紧凑点」
--   · **紧贴** = `TL_GAP = 0`（挂靠点与交易窗边缘同一像素）；
--   · **背景黑色 85% + 系统经典边框圆角** = 照客户端自带 `GameTooltipTemplate` 的 Backdrop 配方
--     （`UI-Tooltip-Background` + `UI-Tooltip-Border`，edgeSize/tileSize 16、背景内缩 5）——
--     ★**这就是「系统经典边框圆角」的唯一真值**（`tmp/mpq_out/Interface/FrameXML/GameTooltipTemplate.xml:4-13`）；
--     ★`SetBackdrop` 拿不到（自定义 UI / 旧客户端）⇒ **退回四边纯色描边**（fail-open，绝不没边框）；
--   · **条目单行 + 真图标**：结果标记 ｜ 时间 ｜ 对方 ｜ 金币 ｜ 物品图标（**红框 = 我给出 / 绿框 = 我得到**），
--     **名字一律不画**（图标已直观）⇒ 行高 30 → **20**、可见行 8 → **9**；
--   · **图标可悬停**：每格图标是一颗**透明 Button**（纹理不吃鼠标 —— 项目配方 §三.9），
--     悬停 ⇒ `GameTooltip:SetHyperlink(链接)` = **客户端自己的物品信息**（读不回才退自建两行）。
local function tlResultMark(ok)
  if ok == true then return "√", 0.62, 0.95, 0.55 end
  if ok == false then return "×", 0.95, 0.58, 0.52 end
  return "?", 0.95, 0.82, 0.45
end

-- 「金币」列：按**我的净变化**显示（+收 / −付 / ±0 / —）
local function tlNetStr(rec)
  local gm, gt = tonumber(rec.gm) or 0, tonumber(rec.gt) or 0
  if gm == 0 and gt == 0 then return "|cff9a9a9a—|r" end
  local net = gt - gm
  if net > 0 then return "|cff8fe08f+" .. tlMoney(net) end
  if net < 0 then return "|cfff0a0a0−" .. tlMoney(net) end
  return "|cffd8d8d8±0|r"
end

-- 一条记录摊成**图标序列**：先「我给出」后「我得到」（框色不同 ⇒ 不用文字也分得清）
local function tlIconList(rec)
  local out = {}
  local function push(arr, dir)
    local n = table.getn(arr or {})
    for i = 1, n do out[table.getn(out) + 1] = { it = arr[i], dir = dir } end
  end
  if type(rec) == "table" then
    push(rec.give, "g")
    push(rec.get, "r")
  end
  return out
end

local function tlBtn(parent, x, y, w, h, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  tlSolid(bg, 0.10, 0.09, 0.07, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local t = tlText(b, 10, 0.95, 0.82, 0.35)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(label or "")
  return b, t
end

local function tlTipHide()
  local tip = G("GameTooltip")
  if type(tip) == "table" then pcall(tip.Hide, tip) end
end

-- 悬停整行：把这一条的**全部内容**摊开（行里放不下的都在这里；物品用**链接**画 ⇒ 自带品质色）
local function tlRowTip(btn, rec)
  local tip = G("GameTooltip")
  if type(tip) ~= "table" or type(rec) ~= "table" then return end
  pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.AddLine, tip, string.format(L("TL_TIP_HEAD"), tostring(rec.t or "?"), tostring(rec.who or "?")), 1, 0.85, 0.40)
  local mk, r, g, b = tlResultMark(rec.ok)
  local resKey = (rec.ok == true and "TL_RES_OK") or (rec.ok == false and "TL_RES_FAIL") or "TL_RES_UNK"
  pcall(tip.AddLine, tip, string.format(L("TL_TIP_RESULT"), mk, L(resKey), L(rec.why or "TL_WHY_UNK")), r, g, b)
  local function side(title, arr, moneyC)
    local head = title
    if (tonumber(moneyC) or 0) > 0 then head = head .. "　" .. tlMoney(moneyC) end
    pcall(tip.AddLine, tip, head, 0.85, 0.82, 0.62)
    local n = table.getn(arr or {})
    if n == 0 then
      pcall(tip.AddLine, tip, "　" .. L("TL_NO_ITEM"), 0.62, 0.62, 0.62)
      return
    end
    for i = 1, n do
      local it = arr[i]
      local c = tonumber((type(it) == "table" and it.c) or 1) or 1
      local txt
      if type(it) == "table" and type(it.l) == "string" and it.l ~= "" then
        txt = it.l                                   -- 链接自带品质色
      else
        txt = "|cffffffff" .. tostring((type(it) == "table" and it.n) or "?") .. "|r"
      end
      if c > 1 then txt = txt .. " ×" .. c end
      pcall(tip.AddLine, tip, "　" .. txt, 0.90, 0.90, 0.90)
    end
  end
  side(L("TL_TIP_GIVE"), rec.give, tonumber(rec.gm) or 0)
  side(L("TL_TIP_GET"), rec.get, tonumber(rec.gt) or 0)
  pcall(tip.AddLine, tip, L("TL_TIP_ROW"), 0.60, 0.85, 1)
  pcall(tip.Show, tip)
end

-- ★单格物品图标的悬停 = **客户端自己的物品信息**（`SetHyperlink`）；读不回 / 判不出 ⇒ 退自建两行
--   ★★判据用「行数」：`NumLines()` 报 0 = 客户端没填上 ⇒ 补自建；**报不出（nil）= 判不出 ⇒ 不补**
--     （本项目铁律：判不出 ≠ 没有 —— 拿 nil 当「没填」会把客户端的内容盖掉）
local function tlIconTip(btn, it, dir)
  local tip = G("GameTooltip")
  if type(tip) ~= "table" or type(it) ~= "table" then return end
  local c = tonumber(it.c) or 1
  local dirKey = (dir == "g") and "TL_TIP_GIVE" or "TL_TIP_GET"
  local col = (dir == "g") and TL_GIVE_RGB or TL_GET_RGB
  pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  local filled = false
  if type(it.l) == "string" and it.l ~= "" and type(tip.SetHyperlink) == "function" then
    local ok = pcall(tip.SetHyperlink, tip, it.l)
    if ok then
      filled = true
      if type(tip.NumLines) == "function" then
        local ok2, v = pcall(tip.NumLines, tip)
        if ok2 and tonumber(v) == 0 then filled = false end     -- 明确 0 行 ⇒ 没填上
      end
    end
  end
  if not filled then
    pcall(tip.AddLine, tip, tostring(it.n or "?"), 0.95, 0.95, 0.95)
  end
  pcall(tip.AddLine, tip, L(dirKey) .. " ×" .. tostring(c), col[1], col[2], col[3])
  pcall(tip.Show, tip)
end

-- 一行里一格图标的**唯一绘制口**（方向色框 + 贴图 + 数量）
local function tlSlotPaint(r, k, item)
  local s = r.slots[k]
  if type(item) ~= "table" or type(item.it) ~= "table" then
    pcall(s.btn.Hide, s.btn)
    return false
  end
  local it, dir = item.it, item.dir
  local col = (dir == "g") and TL_GIVE_RGB or TL_GET_RGB
  local tex = it.tx
  if type(tex) ~= "string" or tex == "" then
    -- 快照没带贴图（老记录）⇒ 现查一次（查不到就**不画假图**，只留方向色框）
    local f = G("GetItemInfo")
    if type(f) == "function" and type(it.l) == "string" and it.l ~= "" then
      local ok, _n, _l, _q, _il, _rl, _cl, _sc, _ms, tx = pcall(f, it.l)
      if ok and type(tx) == "string" and tx ~= "" then tex = tx end
    end
  end
  pcall(s.ring.Show, s.ring)
  pcall(s.ring.SetVertexColor, s.ring, col[1], col[2], col[3])
  if tex then
    pcall(s.icon.SetTexture, s.icon, tex)
    pcall(s.icon.Show, s.icon)
  else
    pcall(s.icon.Hide, s.icon)
  end
  local c = tonumber(it.c) or 1
  if c > 1 then
    pcall(s.cnt.SetText, s.cnt, tostring(c))
    pcall(s.cnt.Show, s.cnt)
  else
    pcall(s.cnt.Hide, s.cnt)
  end
  s.rec, s.dir = it, dir
  pcall(s.btn.Show, s.btn)
  return true
end

-- 面板刷新：行池 + 页码 + 本次交易行 + 按钮状态（**唯一绘制口**；几何一律在 tlBuild 定死，这里只画）
tlRefresh = function()
  if not TL.built or not TL.root then return false end
  local l = tlList() or {}
  local n = table.getn(l)
  local maxOff = math.max(0, n - TL_ROWS)
  if TL.off > maxOff then TL.off = maxOff end
  if TL.off < 0 then TL.off = 0 end
  if TL.empty then
    if n == 0 then pcall(TL.empty.Show, TL.empty) else pcall(TL.empty.Hide, TL.empty) end
  end
  for i = 1, TL_ROWS do
    local r = TL.rows[i]
    local rec = l[TL.off + i]
    TL.rowRec[i] = (type(rec) == "table") and rec or nil
    if type(rec) == "table" then
      -- 条纹：隔行一条；悬停行由 tlRowEnter 换成高亮色（r.hot 时这里不覆盖）
      if r.hot then
        pcall(r.stripe.SetVertexColor, r.stripe, 0.24, 0.22, 0.15)
        pcall(r.stripe.Show, r.stripe)
      else
        pcall(r.stripe.SetVertexColor, r.stripe, 0.14, 0.13, 0.11)
        if i % 2 == 0 then pcall(r.stripe.Hide, r.stripe) else pcall(r.stripe.Show, r.stripe) end
      end
      pcall(r.btn.Show, r.btn)
      pcall(r.mark.Show, r.mark)
      pcall(r.time.Show, r.time)
      pcall(r.who.Show, r.who)
      pcall(r.money.Show, r.money)
      local mk, mr, mg, mb = tlResultMark(rec.ok)
      pcall(r.mark.SetText, r.mark, mk)
      pcall(r.mark.SetTextColor, r.mark, mr, mg, mb)
      pcall(r.time.SetText, r.time, tostring(rec.t or "?"))
      pcall(r.who.SetText, r.who, tlClip(tostring(rec.who or "?"), 6))
      pcall(r.money.SetText, r.money, tlNetStr(rec))
      -- 物品图标：先给出后得到；超过上限 ⇒ 前 4 个 +「+N」（**绝不静默丢**，悬停里有全量）
      local icons = tlIconList(rec)
      local total = table.getn(icons)
      local cap = (total > TL_ICON_N) and TL_ICON_CAP or TL_ICON_N
      local shown = 0
      for k = 1, TL_ICON_N do
        if k <= cap and icons[k] then
          tlSlotPaint(r, k, icons[k])
          shown = shown + 1
        else
          pcall(r.slots[k].btn.Hide, r.slots[k].btn)
        end
      end
      if total > shown and shown > 0 then
        pcall(r.more.SetPoint, r.more, "LEFT", r.slots[shown].btn, "RIGHT", 3, 0)
        pcall(r.more.SetText, r.more, string.format(L("TL_ICON_MORE"), total - shown))
        pcall(r.more.Show, r.more)
      else
        pcall(r.more.Hide, r.more)
      end
    else
      pcall(r.stripe.Hide, r.stripe)
      pcall(r.btn.Hide, r.btn)
      pcall(r.mark.Hide, r.mark)
      pcall(r.time.Hide, r.time)
      pcall(r.who.Hide, r.who)
      pcall(r.money.Hide, r.money)
      pcall(r.more.Hide, r.more)
      for k = 1, TL_ICON_N do pcall(r.slots[k].btn.Hide, r.slots[k].btn) end
    end
  end
  -- 页码（常显，照项目唯一的滚动标准）
  if TL.ind then
    local pages = math.max(1, math.ceil(n / TL_ROWS))
    local page
    if n == 0 then page = 1
    elseif TL.off >= maxOff then page = pages
    else page = math.floor(TL.off / TL_ROWS) + 1 end
    if page < 1 then page = 1 end
    if page > pages then page = pages end
    pcall(TL.ind.SetText, TL.ind, string.format("%d/%d (%d)", page, pages, n))
  end
  if TL.up and TL.dn then
    if n == 0 or TL.off <= 0 then pcall(TL.up.btn.Hide, TL.up.btn) else pcall(TL.up.btn.Show, TL.up.btn) end
    if n == 0 or TL.off + TL_ROWS >= n then pcall(TL.dn.btn.Hide, TL.dn.btn) else pcall(TL.dn.btn.Show, TL.dn.btn) end
  end
  -- [清空] 的两次点击确认（过窗自动弹回 —— 不需要额外计时器，每次刷新现算）
  if TL.clearText then
    local armed = (TL.armAt or 0) > 0 and (tlNow() - TL.armAt) <= TL_ARM_SEC
    if (TL.armAt or 0) > 0 and not armed then TL.armAt = 0 end
    pcall(TL.clearText.SetText, TL.clearText, armed and L("TL_CLEAR_ARM") or L("TL_CLEAR"))
    if armed then pcall(TL.clearText.SetTextColor, TL.clearText, 1.00, 0.55, 0.50)
    else pcall(TL.clearText.SetTextColor, TL.clearText, 0.95, 0.72, 0.42) end
  end
  -- 本次交易（进行中 / 收尾核对中）那一行
  if TL.live then
    local c = TL.cur
    if type(c) == "table" then
      pcall(TL.live.SetText, TL.live, string.format(L("TL_LIVE"), tostring(c.who or "?"),
        tlMoney(tonumber(c.gm) or 0), tostring(table.getn(c.give or {})),
        tlMoney(tonumber(c.gt) or 0), tostring(table.getn(c.get or {}))))
      pcall(TL.live.SetTextColor, TL.live, 0.72, 0.90, 1.00)
      pcall(TL.live.Show, TL.live)
    elseif type(TL.pend) == "table" then
      pcall(TL.live.SetText, TL.live, L("TL_VERIFYING"))
      pcall(TL.live.SetTextColor, TL.live, 0.95, 0.82, 0.45)
      pcall(TL.live.Show, TL.live)
    else
      pcall(TL.live.Hide, TL.live)
    end
  end
  return true
end

-- 行的动作（**唯一实现**）：左键 = 密语对方 · 右键 = 删除这一条
--   ★★行按钮与**每格物品图标**共用它（图标是子帧、会先吃到鼠标 ⇒ 必须自己转发，否则点图标没反应）
local function tlRowAction(i, a, b)
  local rec = TL.rowRec[i]
  if type(rec) ~= "table" then return false end
  if tlMouseBtn(a, b) == "RightButton" then
    local idx = TL.off + i
    local gone = tlDel(idx)
    if type(gone) == "table" then
      say(string.format(L("TL_DELETED"), tostring(gone.who or "?")))
      tlNote("删单条：第 " .. tostring(idx) .. " 条（对方=" .. tostring(gone.who or "?") .. "）")
      tlRefresh()
      local rf = G("EVAL_TB_REFRESH")
      if type(rf) == "function" then pcall(rf) end
    end
  else
    tlTell(rec.who)
  end
  return true
end

-- 行的悬停：整行摘要（鼠标移到物品图标上时，图标自己的悬停会把它顶掉）
local function tlRowEnter(i)
  local r = TL.rows[i]
  local rec = TL.rowRec[i]
  if not r or type(rec) ~= "table" then return end
  r.hot = true
  pcall(r.stripe.SetVertexColor, r.stripe, 0.24, 0.22, 0.15)
  pcall(r.stripe.Show, r.stripe)
  tlRowTip(r.btn, rec)
end

local function tlRowLeave(i)
  local r = TL.rows[i]
  if not r then return end
  -- ★鼠标还在本行的物品图标上 ⇒ **不熄**（图标自己的 OnEnter 已经换成了物品信息）
  local mf = G("GetMouseFocus")
  if type(mf) == "function" then
    local ok, f = pcall(mf)
    if ok and f ~= nil then
      for k = 1, TL_ICON_N do
        if r.slots[k] and f == r.slots[k].btn then return end
      end
    end
  end
  r.hot = false
  pcall(r.stripe.SetVertexColor, r.stripe, 0.14, 0.13, 0.11)
  tlTipHide()
end

-- 挂靠：优先贴交易窗右侧 → 放不下翻左侧 → 再不行放下/上方 → 都不行就居中（**绝不把窗留在屏幕外**）
--   ★`TL_GAP = 0` ⇒ **紧贴**（用户点名：面板紧贴交易窗）；上下也对齐交易窗顶（偏移 0）
tlPlace = function()
  local f = TL.root
  if not f then return false end
  pcall(f.ClearAllPoints, f)
  local tf = G("TradeFrame")
  local order = {}
  if tlShown(tf) then
    order = {
      { "TOPLEFT", tf, "TOPRIGHT", TL_GAP, 0 },          -- 右侧（用户点名的默认位，紧贴）
      { "TOPRIGHT", tf, "TOPLEFT", -TL_GAP, 0 },         -- 左侧
      { "TOPLEFT", tf, "BOTTOMLEFT", 0, -TL_GAP },       -- 下方
      { "BOTTOMLEFT", tf, "TOPLEFT", 0, TL_GAP },        -- 上方
    }
  end
  local sw, sh = 1024, 768
  if UIParent then
    if type(UIParent.GetWidth) == "function" then local ok, v = pcall(UIParent.GetWidth, UIParent) if ok and tonumber(v) then sw = v end end
    if type(UIParent.GetHeight) == "function" then local ok, v = pcall(UIParent.GetHeight, UIParent) if ok and tonumber(v) then sh = v end end
  end
  -- ★判不出（几何读不回）⇒ 当成「放得下」= fail-open：宁可沿用首选锚点，也不把窗丢到屏幕中央
  local function fits()
    local okl, lv = pcall(f.GetLeft, f)
    local okr, rv = pcall(f.GetRight, f)
    local okt, tv = pcall(f.GetTop, f)
    local okb, bv = pcall(f.GetBottom, f)
    if not (okl and okr and okt and okb) then return nil end
    if type(lv) ~= "number" or type(rv) ~= "number" or type(tv) ~= "number" or type(bv) ~= "number" then return nil end
    return (lv >= 0 and rv <= sw and tv <= sh and bv >= 0)
  end
  local chosen = false
  for i = 1, table.getn(order) do
    local o = order[i]
    pcall(f.SetPoint, f, o[1], o[2], o[3], o[4], o[5])
    if fits() ~= false then chosen = true break end
  end
  if not chosen then
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "CENTER", UIParent, "CENTER", 0, 0)
  end
  return chosen
end

tlBuild = function()
  if TL.root then return TL.root end
  local W, H = TL_W, TL_H
  local root = CreateFrame("Frame", "EVAL_TL_PANEL", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 190)     -- 与交易窗同一层区（低于工具箱弹窗 200）；★不做捕手（见文件头）
  pcall(root.EnableMouse, root, true)
  -- ★★★系统经典边框圆角 + 黑色 85% 背景 = **全项目弹窗边框配方**（CLAUDE.md §三.10 唯一标准）：
  --   ① `SetBackdrop`（`UI-Tooltip-Background` + `UI-Tooltip-Border`、整数 `tileSize/edgeSize`、insets）
  --      → ② **读回 `GetBackdrop` 自证**（**读不到 ⇒ 按「已挂上」处理**；读到却不是那张边贴图 ⇒ 判 flat）
  --      → ③ 判 flat / 挂不上 ⇒ **四边纯色描边**（fail-open，绝不没边框）。
  --   ★★★**自建方底 / 描边只在 flat 那一支建** —— 圆角路径**绝不**再叠一块铺满整帧的方底：
  --      客户端圆角边框贴图是**内缩**的，方底铺满整帧 ⇒ 它的边与角会从圆角边框**外面**露出来
  --      （真机症状 = 「纹理边框外面还有层边框」；参考实现 `Toolbox.tbMenuBuild` 原话「再叠一层自己的
  --      方形半透明底会发黑」⇒ 它圆角时 `pcall(bg.Hide, bg)`；本窗是**建都不建**，同一把尺子）。
  local backdropOK, bdKind, bdEdge = false, "flat", nil
  if type(root.SetBackdrop) == "function" then
    local ok = pcall(root.SetBackdrop, root, {
      bgFile = TL_BG_FILE, edgeFile = TL_EDGE_FILE,
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    if ok then
      pcall(root.SetBackdropColor, root, 0, 0, 0, TL_BG_ALPHA)
      -- 边框色 = 客户端自己那份（TOOLTIP_DEFAULT_COLOR）；读不到用中性灰（**不猜一个鲜艳色**）
      local tc = rawget(_G, "TOOLTIP_DEFAULT_COLOR")
      if type(tc) == "table" and tonumber(tc.r) and tonumber(tc.g) and tonumber(tc.b) then
        pcall(root.SetBackdropBorderColor, root, tc.r, tc.g, tc.b)
      else
        pcall(root.SetBackdropBorderColor, root, 0.62, 0.62, 0.62)
      end
      -- ★读回自证（与姓名右键菜单 / 批量购买数量窗**逐字同源**的判据）：
      --   本客户端 GetBackdrop 的返回形态 = `"WHITE8X8|<边贴图尾段>"`（没有边框时尾段是 `-`）。
      if type(root.GetBackdrop) == "function" then
        local oks, str = pcall(root.GetBackdrop, root)
        if oks and type(str) == "string" then bdEdge = str end
      end
      if bdEdge == nil or string.find(bdEdge, "UI-Tooltip-Border", 1, true) ~= nil then
        backdropOK, bdKind = true, "rounded"
      end
    end
  end
  TL.backdrop, TL.bdKind, TL.bdEdge = backdropOK, bdKind, bdEdge
  if not backdropOK then
    local bg = root:CreateTexture(nil, "BACKGROUND")
    tlSolid(bg, 0, 0, 0, TL_BG_ALPHA)
    bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    local function edge(ax, ay, w2, h2)
      local t = root:CreateTexture(nil, "BORDER")
      tlSolid(t, 0.55, 0.45, 0.22, 0.9)
      t:SetPoint("TOPLEFT", root, "TOPLEFT", ax, ay)
      t:SetWidth(w2) t:SetHeight(h2)
    end
    edge(0, 0, W, 1) edge(0, -(H - 1), W, 1) edge(0, 0, 1, H) edge(W - 1, 0, 1, H)
  end
  -- 标题行（边框画框内缩 5 ⇒ 内容从 8 起，不压到圆角上）
  local title = tlText(root, 12, 0.95, 0.82, 0.45)
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -6)
  pcall(title.SetHeight, title, 14)
  pcall(title.SetJustifyV, title, "MIDDLE")
  title:SetText(L("TL_TITLE"))
  local xb = tlBtn(root, W - 26, -4, 18, 16, "X")
  xb:SetScript("OnClick", function() tlHide() end)
  -- 列头（与行内单元格同一来源常量；★滚动箭头已挪到底栏 ⇒ 不再压住「物品」列头）
  local heads = {
    { L("TL_COL_TIME"), 24, 54 },
    { L("TL_COL_WHO"), 80, 56 },
    { L("TL_COL_MONEY"), 136, 64 },
    { L("TL_COL_ITEMS"), 202, W - 210 },
  }
  for i = 1, table.getn(heads) do
    local h = tlText(root, 9, 0.78, 0.72, 0.50)
    h:SetPoint("TOPLEFT", root, "TOPLEFT", heads[i][2], -24)
    pcall(h.SetWidth, h, heads[i][3])
    pcall(h.SetHeight, h, 12)
    pcall(h.SetJustifyV, h, "MIDDLE")
    h:SetText(heads[i][1])
  end
  -- 行池：整行一个按钮（左键密语 / 右键删一条）+ 结果/时间/对方/金币 + 每格物品图标
  local rows = {}
  TL.rows, TL.rowRec = rows, {}
  local y0 = -38
  for i = 1, TL_ROWS do
    local y = y0 - (i - 1) * TL_ROW_H
    local r = { slots = {}, hot = false }
    r.stripe = root:CreateTexture(nil, "BACKGROUND")
    tlSolid(r.stripe, 0.14, 0.13, 0.11, 0.55)
    r.stripe:SetPoint("TOPLEFT", root, "TOPLEFT", 4, y + 1)
    pcall(r.stripe.SetWidth, r.stripe, W - 8)
    pcall(r.stripe.SetHeight, r.stripe, TL_ROW_H - 2)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(W - 8) b:SetHeight(TL_ROW_H - 2)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", 4, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    -- 单行四列：全部「行高 + SetJustifyV(MIDDLE)」⇒ 四列同一中线（用户：条目样式对齐）
    local function cell(x, w2, size, cr, cg, cb)
      local fs = tlText(root, size, cr, cg, cb)
      fs:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
      pcall(fs.SetWidth, fs, w2)
      pcall(fs.SetHeight, fs, TL_ROW_H - 2)
      pcall(fs.SetJustifyH, fs, "LEFT")
      pcall(fs.SetJustifyV, fs, "MIDDLE")
      return fs
    end
    r.mark = cell(8, 14, 11, 0.95, 0.82, 0.45)
    r.time = cell(24, 54, 9, 0.78, 0.78, 0.72)
    r.who = cell(80, 56, 10, 0.92, 0.88, 0.76)
    r.money = cell(136, 64, 9, 0.90, 0.90, 0.90)
    -- 物品图标：TL_ICON_N 格（每格 = 透明按钮 + 方向色框 + 图标纹理 + 数量）
    --   ★几何**只在这里定一次**（刷新时只画不重锚 —— 项目纪律：每拍重锚 = 白开销）
    for k = 1, TL_ICON_N do
      local sb = CreateFrame("Button", nil, b)
      sb:SetWidth(TL_ICON) sb:SetHeight(TL_ICON)
      sb:SetPoint("TOPLEFT", b, "TOPLEFT", TL_ICON_X + (k - 1) * (TL_ICON + TL_ICON_GAP), -1)
      pcall(sb.EnableMouse, sb, true)
      pcall(sb.RegisterForClicks, sb, "LeftButtonUp", "RightButtonUp")
      local ring = sb:CreateTexture(nil, "BACKGROUND")
      tlSolid(ring, 1, 1, 1, 1)
      ring:SetAllPoints(sb)
      local icon = sb:CreateTexture(nil, "ARTWORK")
      icon:SetPoint("TOPLEFT", sb, "TOPLEFT", 1, -1)
      icon:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -1, 1)
      pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)   -- 收掉图标自带留白（与格子同一把尺子）
      local cnt = tlText(sb, 9, 1, 1, 1)
      cnt:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 1, 1)
      pcall(cnt.SetJustifyH, cnt, "RIGHT")
      -- ★★图标与整行**同一个动作口**（不转发 = 「点图标没反应」）
      sb:SetScript("OnClick", function(a, b2) tlRowAction(i, a, b2) end)
      sb:SetScript("OnEnter", function()
        local s = r.slots[k]
        if not s.rec then return end
        tlIconTip(s.btn, s.rec, s.dir)
      end)
      sb:SetScript("OnLeave", function() tlTipHide() end)
      r.slots[k] = { btn = sb, ring = ring, icon = icon, cnt = cnt }
    end
    -- 「+N」（超出 TL_ICON_N 件时如实报还有几件；绝不静默丢）
    r.more = tlText(root, 9, 0.95, 0.82, 0.45)
    pcall(r.more.SetHeight, r.more, TL_ROW_H - 2)
    pcall(r.more.SetJustifyV, r.more, "MIDDLE")
    b:SetScript("OnClick", function(a, b2) tlRowAction(i, a, b2) end)
    b:SetScript("OnEnter", function() tlRowEnter(i) end)
    b:SetScript("OnLeave", function() tlRowLeave(i) end)
    r.btn = b
    rows[i] = r
  end
  TL.empty = tlText(root, 10, 0.60, 0.58, 0.50)
  TL.empty:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -46)
  pcall(TL.empty.SetWidth, TL.empty, W - 32)
  TL.empty:SetText(L("TL_EMPTY"))
  local liveY = -(y0 + TL_ROWS * TL_ROW_H + 2)
  TL.live = tlText(root, 9, 0.72, 0.90, 1.00)
  TL.live:SetPoint("TOPLEFT", root, "TOPLEFT", 10, liveY)
  pcall(TL.live.SetWidth, TL.live, W - 20)
  pcall(TL.live.SetJustifyH, TL.live, "LEFT")
  local hint = tlText(root, 9, 0.58, 0.60, 0.58)
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", 10, liveY - 13)
  pcall(hint.SetWidth, hint, W - 20)
  pcall(hint.SetJustifyH, hint, "LEFT")
  hint:SetText(L("TL_HINT"))
  -- 底栏：[清空]（两次点击确认）+ 滚动箭头 + 页码（**箭头搬到这里** ⇒ 不再压住列头）
  local cb, ct = tlBtn(root, 10, -(H - 26), 62, 16, L("TL_CLEAR"))
  TL.clearBtn, TL.clearText = cb, ct
  cb:SetScript("OnClick", function()
    local armed = (TL.armAt or 0) > 0 and (tlNow() - TL.armAt) <= TL_ARM_SEC
    if not armed then
      TL.armAt = tlNow()
      say(L("TL_CLEAR_ASK"))
      tlRefresh()
      return
    end
    TL.armAt = 0
    local n = tlClearAll()
    if n > 0 then
      say(string.format(L("TL_CLEARED"), n))
      tlNote("清空：" .. tostring(n) .. " 条")
    else
      say(L("TL_CLEAR_NONE"))
    end
    tlRefresh()
    local rf = G("EVAL_TB_REFRESH")
    if type(rf) == "function" then pcall(rf) end
  end)
  local ub, ut = tlBtn(root, W - 46, -(H - 26), 16, 16, "^")
  local db, dt = tlBtn(root, W - 26, -(H - 26), 16, 16, "v")
  TL.up, TL.dn = { btn = ub, text = ut }, { btn = db, text = dt }
  ub:SetScript("OnClick", function() TL.off = math.max(0, TL.off - TL_ROWS) tlRefresh() end)
  db:SetScript("OnClick", function() TL.off = TL.off + TL_ROWS tlRefresh() end)
  TL.ind = tlText(root, 9, 0.65, 0.62, 0.50)
  TL.ind:SetPoint("TOPRIGHT", root, "TOPRIGHT", -68, -(H - 26))
  pcall(TL.ind.SetWidth, TL.ind, 60)
  pcall(TL.ind.SetHeight, TL.ind, 16)
  pcall(TL.ind.SetJustifyH, TL.ind, "RIGHT")
  pcall(TL.ind.SetJustifyV, TL.ind, "MIDDLE")
  -- 滚轮（方向单一来源 EVAL_WHEEL_DIR；dir == 0 ⇒ 链式交还，绝不霸占）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
  if okg and type(g) == "function" then prevWheel = g end
  root:SetScript("OnMouseWheel", function(a, b)
    local dir = 0
    local wf = G("EVAL_WHEEL_DIR")
    if type(wf) == "function" then dir = tonumber(wf(a, b)) or 0 end
    if dir == 0 then
      if prevWheel then return prevWheel(a, b) end
      return
    end
    TL.off = math.max(0, TL.off - dir)
    tlRefresh()
  end)
  pcall(root.Hide, root)
  TL.root = root
  TL.built = true
  return root
end

tlShow = function(mode)
  if not EVAL_TL_ON() then return false end
  tlBuild()
  if not TL.root then return false end
  TL.mode = mode or "free"
  tlRefresh()
  tlPlace()
  pcall(TL.root.Show, TL.root)
  return true
end

tlHide = function()
  if TL.root then pcall(TL.root.Hide, TL.root) end
  tlTipHide()
  return true
end

-- ── 密语（左键点条目 = 开启和他的对话）───────────────────────────────────
tlTell = function(who)
  if type(who) ~= "string" or who == "" or who == "?" then
    say(L("TL_NO_WHO"))
    return false
  end
  -- ① 客户端自己的 `/w` 入口（`ChatFrame_SendTell` 就是 `/w` 走的那一条）
  local send = G("ChatFrame_SendTell")
  if type(send) == "function" then
    local ok = pcall(send, who, G("DEFAULT_CHAT_FRAME"))
    if ok then
      tlNote("密语：" .. who .. "（ChatFrame_SendTell）")
      return true
    end
  end
  -- ② 退路：客户端自己的原文写法（`ChatFrame_OpenChat("/w "..name.." ", frame)`）
  local open = G("ChatFrame_OpenChat")
  if type(open) == "function" then
    local ok = pcall(open, "/w " .. who .. " ", G("DEFAULT_CHAT_FRAME"))
    if ok then
      tlNote("密语：" .. who .. "（ChatFrame_OpenChat）")
      return true
    end
  end
  say(L("TL_NO_TELL"))                      -- 两条路都不通 ⇒ 如实说，绝不假装开了
  return false
end

-- ══════════════════════════ 事件 / 节拍 ══════════════════════════
-- ★★宽事件（UI_INFO_MESSAGE）**只在交易期间注册**（「用的时候才启用、不用就关」）
tlMsgArm = function(on)
  if TL.ev == nil then return false end
  if on then
    pcall(TL.ev.RegisterEvent, TL.ev, "UI_INFO_MESSAGE")
  else
    pcall(TL.ev.UnregisterEvent, TL.ev, "UI_INFO_MESSAGE")
  end
  return on
end

tlBeatTick = function(now)
  return tlPendTick(now)
end

tlTick = function()
  local now = tlNow()
  if now - (TL.beatAt or 0) < TL_BEAT then return end
  TL.beatAt = now
  tlBeatTick(now)          -- 核对窗推进（判得出 / 过窗 ⇒ 落账）
  tlRefresh()              -- 面板跟着刷（含 [清空] 武装态的过期）
  tlBeatSync()             -- ★自愈：不需要了就当场真摘（不靠外部标志）
end

tlBeatSync = function()
  local need = (type(TL.pend) == "table")
  if need then
    if not TL.beat then TL.beat = CreateFrame("Frame") end
    pcall(TL.beat.SetScript, TL.beat, "OnUpdate", tlTick)   -- ★每次都真挂（关一次再开也必须活）
    TL.beatAt = 0
  else
    if TL.beat then pcall(TL.beat.SetScript, TL.beat, "OnUpdate", nil) end  -- ★真摘
    -- ★★核对窗结束了、手上也没有进行中的交易 ⇒ 宽事件一起摘掉（「用的时候才启用」——
    --   旧写法只在 TRADE_CLOSED 那一支摘，走核对窗落账的路径会把它留到下一次开窗 = 白挂着）
    if type(TL.cur) ~= "table" then tlMsgArm(false) end
  end
  return need
end

tlOnEvent = function()
  -- ★事件名走全局 `event`（本客户端处理体的调用约定：零形参 + 全局 event/arg1/arg2）
  local e = rawget(_G, "event")
  if e == "TRADE_SHOW" then
    tlOpenSession()
    tlMsgArm(true)
    if EVAL_TL_ON() then tlShow("attach") end
  elseif e == "TRADE_CLOSED" then
    tlCloseSession()
    if TL.mode == "attach" then tlHide() end   -- 贴靠模式：交易窗关了陪着一起收（历史仍在）
    if type(TL.pend) == "table" then
      tlBeatSync()                             -- 核对窗还开着 ⇒ 挂节拍
    else
      tlMsgArm(false)                          -- 已落账 ⇒ 宽事件当场摘掉
      tlBeatSync()
    end
  elseif e == "TRADE_UPDATE" or e == "TRADE_PLAYER_ITEM_CHANGED" or e == "TRADE_TARGET_ITEM_CHANGED" then
    if type(TL.cur) == "table" then
      tlSnap()
      tlRefresh()
    end
  elseif e == "TRADE_ACCEPT_UPDATE" then
    local a1 = tonumber(rawget(_G, "arg1"))
    local a2 = tonumber(rawget(_G, "arg2"))
    if type(TL.cur) == "table" and a1 == 1 and a2 == 1 then
      TL.cur.both = true
      tlRefresh()
    end
  elseif e == "UI_INFO_MESSAGE" then
    local a1 = rawget(_G, "arg1")
    local done = G("ERR_TRADE_COMPLETE")
    if type(a1) == "string" and type(done) == "string" and done ~= "" and a1 == done then
      if type(TL.cur) == "table" then TL.cur.complete = true end
      if type(TL.pend) == "table" then
        TL.pend.c.complete = true
        tlNote("完成信号：ERR_TRADE_COMPLETE（正文逐字相同）")
        tlBeatTick(tlNow())
        if type(TL.pend) ~= "table" then
          tlMsgArm(false)
          tlBeatSync()          -- ★落账了 ⇒ 节拍当场真摘（不等下一拍自愈）
        end
      end
      tlRefresh()
    end
  end
end

-- **唯一装/摘入口**（VARIABLES_LOADED / 工具箱勾选 / 命令三条路都走它；幂等）
function EVAL_TL_SYNC()
  local on = EVAL_TL_ON()
  if TL.ev == nil then
    TL.ev = CreateFrame("Frame")
    pcall(TL.ev.SetScript, TL.ev, "OnEvent", tlOnEvent)
  end
  local EVENTS = { "TRADE_SHOW", "TRADE_CLOSED", "TRADE_UPDATE",
                   "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
                   "TRADE_ACCEPT_UPDATE" }
  for i = 1, table.getn(EVENTS) do
    if on then
      pcall(TL.ev.RegisterEvent, TL.ev, EVENTS[i])
    else
      pcall(TL.ev.UnregisterEvent, TL.ev, EVENTS[i])
    end
  end
  if not on then
    -- ★关断四件事：收面板 + 真摘节拍 + 会话态复位 + 宽事件摘掉（**数据一个字都不动**）
    tlHide()
    if TL.beat then pcall(TL.beat.SetScript, TL.beat, "OnUpdate", nil) end
    tlMsgArm(false)
    TL.cur, TL.pend, TL.armAt = nil, nil, 0
    TL.mode = "free"
  end
  return on
end

function EVAL_TL_SET(v)
  local tb = tbCfgGet()
  if type(tb) == "table" then tb.tradeLog = v and true or false end
  EVAL_TL_SYNC()
  return EVAL_TL_ON()
end

-- 载入期入口（VARIABLES_LOADED 调用；默认开 ⇒ 这里就把事件装起来；关着 = 零副作用）
function EVAL_TL_INSTALL()
  EVAL_TL_SYNC()
  return EVAL_TL_ON()
end

-- ══════════════════════════ 对外口 ══════════════════════════
-- 工具箱那一行的 [列表] 与命令共用这一个口（开关关着 ⇒ 如实说一句，绝不开一个「没在记」的窗）
function EVAL_TL_PANEL_TOGGLE()
  if not EVAL_TL_ON() then
    say(L("TL_OFF_SAY"))
    return false
  end
  if tlShown(TL.root) then
    tlHide()
    return false
  end
  tlShow("free")
  return true
end

function EVAL_TL_PANEL_SHOWN() return tlShown(TL.root) end

function EVAL_TL_CLEAR()
  local n = tlClearAll()
  tlRefresh()
  return n
end

-- 读值口（探针 / 诊断用；★挂在真机命令路径上，不是只为 harness 存在的口）
function EVAL_TL_TEST_STATE()
  local l = tlList()
  local n = l and table.getn(l) or 0
  local apis = {}
  local names = { "GetTradePlayerItemLink", "GetTradeTargetItemLink", "GetTradePlayerItemInfo",
                  "GetTradeTargetItemInfo", "GetPlayerTradeMoney", "GetTargetTradeMoney",
                  "GetMoney", "ChatFrame_SendTell", "ChatFrame_OpenChat" }
  for i = 1, table.getn(names) do
    apis[names[i]] = (type(G(names[i])) == "function")
  end
  local done = G("ERR_TRADE_COMPLETE")
  return {
    on = EVAL_TL_ON(),
    count = n,
    max = TL_MAX,
    built = (TL.built == true),
    shown = tlShown(TL.root),
    mode = TL.mode,
    off = TL.off,
    partner = tlPartner(),
    live = (type(TL.cur) == "table"),
    pend = (type(TL.pend) == "table"),
    last = TL.last,
    -- ★★★弹窗边框自证（CLAUDE.md §三.10 配方；与姓名右键菜单 / 批量购买数量窗同一把尺子）：
    --   `bdKind` = 实际走的那条路（rounded = 客户端圆角贴图已挂上 / flat = 四边 1px 描边兜底）；
    --   `bdEdge` = `GetBackdrop` 读回值（false = 读不到 ⇒ 按「已挂上」处理）。
    --   ★`flat` 那条路才会自建方底与描边 —— 圆角路径**建都不建**（否则方底会露在圆角边框外面）。
    bdKind = TL.bdKind or "flat",
    bdEdge = (TL.bdEdge and tostring(TL.bdEdge)) or false,
    apis = apis,
    completeMsg = (type(done) == "string") and done or nil,
    probe = TL.probe,
    first = (n > 0) and l[1] or nil,
  }
end

local function tlStateLines()
  local st = EVAL_TL_TEST_STATE()
  sayF(string.format(L("TL_STATE"), st.on and L("SH_ON") or L("SH_OFF"), st.count, TL_MAX,
    st.shown and L("SH_ON") or L("SH_OFF"), st.live and L("SH_ON") or L("SH_OFF")))
  sayF(string.format(L("TL_STATE_API"),
    st.apis.GetTradeTargetItemLink and "√" or "×",
    st.apis.GetTargetTradeMoney and "√" or "×",
    st.apis.ChatFrame_SendTell and "√" or "×",
    tostring(st.completeMsg or "—")))
  -- ★边框自证行（弹窗边框配方，见 CLAUDE.md §三.10；只读播报，不换档）
  sayF(string.format(L("TL_STATE_BD"), tostring(st.bdKind or "flat"),
    (st.bdEdge and tostring(st.bdEdge) or L("SH_OFF"))))
  if type(st.first) == "table" then
    sayF(string.format(L("TL_STATE_LAST"), tostring(st.first.t or "?"), tostring(st.first.who or "?"),
      L(st.first.why or "TL_WHY_UNK")))
  end
  if st.last and st.last ~= "" then sayF(L("TL_LAST") .. "：" .. st.last) end
end

-- 命令：/eh go 交易记录 [状态|开|关|列表|清空|探针]
function EVAL_TL_CMD(msg)
  local rest = string.gsub(tostring(msg or ""), "^go%s*", "")
  rest = string.gsub(rest, "^交易记录%s*", "")
  rest = string.gsub(rest, "%s+$", "")
  if rest == "" or rest == "状态" or rest == "state" then
    tlStateLines()
  elseif rest == "开" or rest == "on" then
    EVAL_TL_SET(true)
    sayF(string.format(L("TL_SET"), L("SH_ON")))
  elseif rest == "关" or rest == "off" then
    EVAL_TL_SET(false)
    sayF(string.format(L("TL_SET"), L("SH_OFF")))
  elseif rest == "列表" or rest == "list" then
    local on = EVAL_TL_PANEL_TOGGLE()
    sayF(on and L("TL_LIST_ON") or L("TL_LIST_OFF"))
  elseif rest == "清空" or rest == "clear" then
    local n = EVAL_TL_CLEAR()
    sayF(n > 0 and string.format(L("TL_CLEARED"), n) or L("TL_CLEAR_NONE"))
  elseif rest == "探针" or rest == "probe" then
    local st = EVAL_TL_TEST_STATE()
    local pn = table.getn(st.probe or {})
    sayF(string.format(L("TL_PROBE_HEAD"), st.count, pn))
    if pn == 0 then sayF("   " .. L("TL_PROBE_EMPTY")) end
    for i = 1, pn do sayF("   " .. tostring(st.probe[i])) end
  else
    sayF(L("TL_USAGE"))
  end
end

-- ══════════════════════════ 工具箱模块行 ══════════════════════════
-- Toolbox 侧只有一行数据；控件 / tooltip / 两颗按钮全在这里。
-- ★★★右侧两颗**绝不许用 `r.chv`**（88 宽、与 add 槽完全重叠且后建压在上面 ⇒ 点了永远到不了我们自己那颗；
--   `tools/DragFrames.lua:6069` 与 1.75.115 都为这条付过代价）：
--   [列表] 用 `r.add`（cRight−96 宽 44）· [状态] 用 `r.clr`（cRight−48 宽 40）。
local tlRow = function(r, it)
  if type(r) ~= "table" then return false end
  local function tipHead(btn, firstLine)
    local tip = G("GameTooltip")
    if type(tip) ~= "table" or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return false end
    pcall(tip.SetMinimumWidth, tip, 300)
    pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, firstLine, 1, 0.85, 0.30)
    return true
  end
  r.get = function() return EVAL_TL_ON() end
  r.set = function(v) EVAL_TL_SET(v and true or false) end
  if r.extra then pcall(r.extra.Hide, r.extra) end        -- 配置项只在悬停里说，行上不重复
  if type(r.add) == "table" and type(r.add.text) == "table" and type(r.add.btn) == "table" then
    pcall(r.add.text.SetText, r.add.text, L("TL_BTN_LIST"))
    pcall(r.add.btn.Show, r.add.btn)
    pcall(r.add.btn.SetScript, r.add.btn, "OnEnter", function()
      local tip = G("GameTooltip")
      if not tipHead(r.add.btn, (type(it) == "table" and it.tip) or L("TB_TRADELOG_TIP")) then return end
      pcall(tip.AddLine, tip, string.format(L("TL_TIP_COUNT"), tlCount(), TL_MAX), 0.80, 0.90, 0.80)
      pcall(tip.AddLine, tip, L("TL_BTN_LIST_TIP"), 0.60, 0.85, 1)
      pcall(tip.Show, tip)
    end)
    pcall(r.add.btn.SetScript, r.add.btn, "OnLeave", tlTipHide)
    pcall(r.add.btn.SetScript, r.add.btn, "OnClick", function()
      local on = EVAL_TL_PANEL_TOGGLE()
      say(on and L("TL_LIST_ON") or L("TL_LIST_OFF"))
      local rf = G("EVAL_TB_REFRESH")
      if type(rf) == "function" then pcall(rf) end
    end)
  end
  if type(r.clr) == "table" and type(r.clr.text) == "table" and type(r.clr.btn) == "table" then
    pcall(r.clr.text.SetText, r.clr.text, L("TL_BTN_STATE"))
    pcall(r.clr.btn.Show, r.clr.btn)
    pcall(r.clr.btn.SetScript, r.clr.btn, "OnEnter", function()
      local tip = G("GameTooltip")
      if not tipHead(r.clr.btn, L("TL_BTN_STATE")) then return end
      local st = EVAL_TL_TEST_STATE()
      pcall(tip.AddLine, tip, string.format(L("TL_STATE"), st.on and L("SH_ON") or L("SH_OFF"), st.count, TL_MAX,
        st.shown and L("SH_ON") or L("SH_OFF"), st.live and L("SH_ON") or L("SH_OFF")), 0.80, 0.90, 0.80)
      if st.last and st.last ~= "" then pcall(tip.AddLine, tip, tostring(st.last), 0.75, 0.85, 0.95) end
      pcall(tip.Show, tip)
    end)
    pcall(r.clr.btn.SetScript, r.clr.btn, "OnLeave", tlTipHide)
    pcall(r.clr.btn.SetScript, r.clr.btn, "OnClick", function() EVAL_TL_CMD("状态") end)
  end
  return true
end

local TL_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(TL_TB_ROWS) ~= "table" then
  TL_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", TL_TB_ROWS)
end
TL_TB_ROWS["tradeLog"] = tlRow
