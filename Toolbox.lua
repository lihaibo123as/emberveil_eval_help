-- EvalHelp · Toolbox.lua —— 工具箱（1.68.0 独立载入：配置窗 Tab3；商人/队伍社交/任务 自动化小工具）
-- 独立原则：本文件自绘 UI（复刻 cfgCheck/cfgHeader 风格），不改主程序任何函数；
-- 依赖仅全局件：EVAL_SAY（Core 桥）、EVAL_TN_OPEN（EvalHelp 回声行弹窗）、EVAL_RESOLVE_LANG/EVAL_LOCALES（i18n）。
-- 配置直读 EVAL_HELP_CONFIG.tb（SavedVariables 自动持久化；全部功能默认关，逐项勾选开启）。

local TB = { off = 0, rows = {}, ROWS = 13 }

-- ===== 自绘基础件（与主程序同风格：WHITE8X8 纯色纹理 + 字体链） =====
local function tbSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function tbText(parent, size, r, g, b)
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

local function tbBtn(parent, x, y, w, label, onClick, widgets)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(15)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  tbSolid(bg, 0.22, 0.18, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local bt = tbText(b, 10, 0.95, 0.82, 0.35)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText(label)
  b:SetScript("OnClick", onClick)
  if widgets then table.insert(widgets, b) end
  return { btn = b, bg = bg, text = bt }
end

-- ===== i18n / 输出 / 配置 =====
-- ★1.70.46 修正语言来源：原写法 `... and EVAL_RESOLVE_LANG() or "zhCN"` 恒等于 "zhCN"
--   （Core.lua 的 ehResolveLang 只把语言写进 EH_LANG、不返回任何值）→ 工具箱在英/俄客户端里
--   整页中文且不报错。与主程序一致改用读取器 EVAL_GET_LANG()。
local function L(k)
  local lang = (type(EVAL_GET_LANG) == "function") and EVAL_GET_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function say(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

-- ★1.71.2 配置迁移：旧版只有一个 quest 开关（**同时**管「接取」和「交付」）→ 拆成两个独立开关
--   （用户要求：工具箱·任务自动交接 分「自动接取」「交付任务」两个开关配置）。
--   ★迁移条件写成「两个新键都还没有 且 旧键存在」→ **只搬一次**；搬完把旧键**置 nil**。
--    为什么不保留旧键：一个状态留两份真值就是本项目反复踩的「派生值当缓存」陷阱
--    （1.70.23/1.70.27 两轮都栽在这）——**只留一份真值**。
-- ★1.71.3 自动购买的数据迁移：老格式 {name,n} → 补 per(每次购买数量，默认 1) / on(启用，默认 true)。
--   ★字段缺失 = 用默认值（而不是拒绝读取）：旧配置不能因为多了两个字段就失效。
--   ★这里**不写 got/会话状态**：那些进 TB.buySess（不落盘）——配置里只存“想买什么”。
local function tbMigrateBuy(t)
  if type(t) ~= "table" or type(t.buy) ~= "table" then return end
  for _, w in ipairs(t.buy) do
    if type(w) == "table" then
      if type(w.n) ~= "number" or w.n < 1 then w.n = 1 end
      if type(w.per) ~= "number" or w.per < 1 then w.per = 1 end
      if w.on == nil then w.on = true end
    end
  end
end

local function tbMigrateQuest(t)
  if type(t) ~= "table" then return end
  if t.questAccept == nil and t.questTurnIn == nil and t.quest ~= nil then
    local was = t.quest and true or false
    t.questAccept, t.questTurnIn, t.quest = was, was, nil
  end
end

local function tbCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  if type(c.tb) ~= "table" then c.tb = {} end
  tbMigrateQuest(c.tb)
  -- ★1.71.3 频道进出信息屏蔽：**默认开**（用户要求）。nil 也视为开（见 EVAL_TB_CHAN_ON）。
  if c.tb.chanJoin == nil then c.tb.chanJoin = true end
  tbMigrateBuy(c.tb) -- ★1.71.3 自动购买：老条目补 每次数量/启用 字段
  return c.tb
end
-- ===== 频道进出信息屏蔽（1.71.3 用户要求：工具箱 → 队伍/社交 → 默认开启）=====
-- ★API 核查（本机 api_*.html 全表 1370 条）：**没有任何「聊天过滤器」API**
--   （`ChatFrame_AddMessageEventFilter` 之类不存在；ChatWindow 分类只有 增删消息组 / 颜色 / 日志）。
--   两条候选路，本实现走第 ② 条：
--     ① `RemoveChatWindowMessages(窗口, 消息组)`（文档在册）——但**消息组名单本机查不到**，
--        盲猜组名等于赌（铁律：用前必查）→ 先用 `/eh go 频道` 把真实消息组打出来，
--        确认存在「频道进出」这一类之后再考虑换用它；
--     ② **挂聊天打印入口**：`DEFAULT_CHAT_FRAME:AddMessage` 是有文档的控件方法（ScrollingMessageFrame），
--        客户端聊天框靠它打印 → 包一层，命中「频道进出通知」就吞掉。
--        · 只吞通知、**不动频道聊天本身**；· 开关**在调用时读**（改开关立即生效，不用 /reload）；
--        · 挂不上（或客户端不走 Lua 打印）→ 什么都不做，`/eh go 频道` 里如实说明「已过滤 0 条」。
local TB_CHAN_WORDS = { "频道", "頻道", "channel", "канал" } -- ★1.71.3 加繁中「頻道」（与 moves 里的繁中进出词配套）
-- ★判据 = 「频道词」**且**「进出词」同时出现 —— 只匹配「加入/离开」会把玩家聊天里
--   一句 “has left” 也吞掉（误伤真人的消息比不屏蔽更糟）；多要一个频道词，误伤面降到几乎为零。
local TB_CHAN_MOVES = {
  -- ★★1.71.3 补「进入」：用户实测截图里的真实文案是「[4. 世界防务] **进入**频道。」
  --   而旧表只有「加入」→ **进入那一半根本没匹配上**（「离开」那半是命中的）。
  --   ★教训：判据表要**照着客户端真实文案抄**，差一个字就是半个功能失效。
  "加入", "进入", "离开", "退出",               -- zhCN
  "加入", "進入", "離開", "退出",               -- 繁中
  "joined", "left", "entered", "you have joined", "you have left", -- enUS
  "joined", "left", "you have joined", "you have left", -- enUS
  "присоединил", "покинул",                             -- ruRU（尽力而为，靠 /eh go 频道 的样本再校准）
}

-- 纯函数：这条聊天文本是不是「频道进出通知」（UI、断言、诊断命令共用同一份判据）
function EVAL_TB_CHAN_BLOCK(msg)
  if type(msg) ~= "string" or msg == "" then return false end
  local lo = string.lower(msg)
  local hasChan = false
  for _, w in ipairs(TB_CHAN_WORDS) do
    if string.find(lo, w, 1, true) ~= nil then hasChan = true break end
  end
  if not hasChan then return false end
  for _, w in ipairs(TB_CHAN_MOVES) do
    if string.find(lo, w, 1, true) ~= nil then return true end
  end
  return false
end

-- 开关：**nil 视为开**（用户要求默认打开；老配置里没这个键时同样是开）
function EVAL_TB_CHAN_ON()
  local tb = tbCfg()
  if not tb then return true end
  return tb.chanJoin ~= false
end

-- 挂聊天打印入口（幂等：已挂过直接返回 true，**绝不重复包装**）
function EVAL_TB_CHAN_INSTALL()
  if TB.chanHooked then return true end
  local f = DEFAULT_CHAT_FRAME
  -- ★不再要求是 table（本客户端帧未必是 table，只看有没有 AddMessage）
  if f == nil then return false end
  local okr, cur = pcall(function() return f.AddMessage end)
  if not (okr and type(cur) == "function") then return false end
  -- ★只要当前入口**就是我们挂的那个**，就算已挂（防「状态说挂了、其实被别人顶掉」）
  if TB.chanWrapper and cur == TB.chanWrapper then TB.chanHooked = true return true end
  local orig = cur
  local function wrapper(self, msg, ...)
    TB.chanSeenAll = (TB.chanSeenAll or 0) + 1 -- ★诊断用：经过本入口的聊天消息总数
    if EVAL_TB_CHAN_ON() and EVAL_TB_CHAN_BLOCK(msg) then
      TB.chanFiltered = (TB.chanFiltered or 0) + 1
      TB.chanSamples = TB.chanSamples or {}
      table.insert(TB.chanSamples, tostring(msg))
      while table.getn(TB.chanSamples) > 8 do table.remove(TB.chanSamples, 1) end
      return -- 吞掉：不进聊天框
    end
    return orig(self, msg, ...)
  end
  local okw = pcall(function() f.AddMessage = wrapper end)
  if not okw then return false end -- ★挂不上就如实返回 false（不假称挂上了）
  TB.chanWrapper = wrapper
  TB.chanHooked = true
  return true
end

-- ★★★1.71.3 **静默失效的根治**（用户实测「屏蔽频道进出信息未能正确工作」）：
--   载入那一刻 DEFAULT_CHAT_FRAME 往往**还没建好**（FrameXML 聊天框晚于插件载入）→ 旧版只试一次，
--   失败后**再没人重试**：开关看着是开的、实际一层都没挂上。
--   现在：限频重试（1 秒至多一次 / 最多 60 次）+ 事件驱动（VARIABLES_LOADED、PLAYER_ENTERING_WORLD）
--   + 每帧队列帧兜底 + `/eh go 频道` 可手动立刻重试。
--   ★判据：**「尝试过」≠「挂上了」**——失败必须重试，成功/放弃都要如实写日志。
local function tbChanRetry()
  if TB.chanHooked then return true end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB.chanTryAt or -99) < 1 then return false end
  TB.chanTryAt = now
  TB.chanTries = (TB.chanTries or 0) + 1
  local ok = EVAL_TB_CHAN_INSTALL()
  if ok then
    EVAL_LOGLINE("[频道屏蔽] 挂载成功（第 " .. tostring(TB.chanTries) .. " 次尝试）")
  elseif TB.chanTries >= 60 then
    EVAL_LOGLINE("[频道屏蔽] 挂载失败：" .. tostring(TB.chanTries) .. " 次尝试后放弃（DEFAULT_CHAT_FRAME 始终不可用）")
  end
  return ok
end
EVAL_TB_CHAN_RETRY = tbChanRetry -- 供诊断命令 / 断言直调

TB.chanHooked = EVAL_TB_CHAN_INSTALL() and true or false
EVAL_LOGLINE("[频道屏蔽] 载入时挂载：" .. (TB.chanHooked and "成功" or "聊天框尚未就绪（将由事件/每帧重试）"))

function EVAL_TEST_TB_CHAN_STATE()
  return EVAL_TB_CHAN_ON(), TB.chanHooked and true or false, (TB.chanFiltered or 0), TB.chanSamples,
         (TB.chanWrapper ~= nil and DEFAULT_CHAT_FRAME ~= nil and DEFAULT_CHAT_FRAME.AddMessage == TB.chanWrapper) and true or false,
         (TB.chanSeenAll or 0), (TB.chanTries or 0)
end

function EVAL_TEST_TB_CHAN_RESET() -- 测试用：清计数并允许重新挂载（不还原已包装的入口）
  TB.chanHooked = false
  TB.chanFiltered = 0
  TB.chanSamples = {}
  TB.chanSeenAll = 0
  TB.chanTryAt = nil
  TB.chanTries = 0
end

-- ★1.71.2 用户要求：「工具箱 → 自动交接任务 按键停止功能，比如按住 shift 临时停止」
--   = **按住即暂停、松开即恢复**的临时闸门（不改配置、不落盘）。
--   设计要点：
--   ① 判据抽成**纯函数** tbHoldOn(tb)，UI 与断言共用一份——否则测试只能复刻一遍逻辑，
--      把这里改坏也测不出来（本项目已三次栽在「测试自己复刻实现」上）。
--   ② **只拦「任务交接」三类事件**（QUEST_DETAIL / QUEST_PROGRESS / QUEST_COMPLETE），
--      不拦商人/丢弃/就位检查：用户说的是「自动交接任务」，按 shift 时不想让任务被自动接/交，
--      但并不想连自动修装/卖店一起停掉（那是另一个开关的事）。
--   ③ ★**按下那一刻还要把已经在队列里的交接动作撤掉**：
--      交接是走限频队列（TB_RATE=0.3s）滴出的，事件触发到真正执行之间有延迟——
--      只拦后续事件的话，按 shift 之前刚入队的那一笔仍会打出去（用户会觉得「按了没用」）。
--   ④ 支持 Ctrl / Alt / Shift 三种，配置项 tb.holdKey 存 id（"shift"/"ctrl"/"alt"/""=关）。
local TB_HOLD_DEFAULT = "shift"
-- 可选的「临时停止」按键（顺序 = 下拉顺序）；"off" 表示关闭该功能
local TB_HOLD_KEYS = { "shift", "ctrl", "alt", "off" }
local TB_HOLD_LABEL = { shift = "Shift", ctrl = "Ctrl", alt = "Alt", off = "" }
local function tbModDown(id)
  if id == "shift" then return (type(IsShiftKeyDown) == "function") and IsShiftKeyDown() and true or false end
  if id == "ctrl" then return (type(IsControlKeyDown) == "function") and IsControlKeyDown() and true or false end
  if id == "alt" then return (type(IsAltKeyDown) == "function") and IsAltKeyDown() and true or false end
  return false
end
-- 纯函数：当前是否处于「临时停止自动交接」状态（未配置 = 默认 Shift；配成空串 = 关闭该功能）
function EVAL_TB_HOLD_ACTIVE(tb)
  if type(tb) ~= "table" then return false end
  local id = tb.holdKey
  if id == nil then id = TB_HOLD_DEFAULT end
  if id == "" then return false end
  return tbModDown(id)
end
local function tbHoldNow()
  local tb = tbCfg()
  return tb and EVAL_TB_HOLD_ACTIVE(tb) or false
end
local function fmtMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local cp = c % 100
  if g > 0 then return g .. "g" .. s .. "s" .. cp .. "c" end
  if s > 0 then return s .. "s" .. cp .. "c" end
  return cp .. "c"
end

-- ===== 功能逻辑（全部 pcall 兜底，API 缺失静默跳过） =====
local function tbBagScan(fn)
  if type(GetContainerNumSlots) ~= "function" then return end
  for b = 0, 4 do
    local slots = GetContainerNumSlots(b) or 0
    for s = 1, slots do fn(b, s) end
  end
end

local function tbItemName(b, s)
  if type(GetContainerItemLink) ~= "function" then return nil end
  local link = GetContainerItemLink(b, s)
  return link and string.match(link, "%[(.-)%]") or nil
end

-- 1.69.1 售卖明细：物品种类（GetItemInfo 只读本地缓存，wiki 确认本客户端仅 9 返回值无售价；未缓存 → nil 兜底显示 ?）
local function tbItemType(name)
  if type(GetItemInfo) ~= "function" or not name then return nil end
  local ok, _1, _2, _3, _4, itype, isub = pcall(GetItemInfo, name) -- 注意：pcall 不可用 and/or 包裹（1.64.0 多返回截断教训）
  if not ok or not itype then return nil end
  if isub and isub ~= itype then return itype .. "/" .. isub end
  return itype
end

-- ===== 动作队列（1.68.2：商人/背包 API 限频 + 出售逐笔成功验证，防服务器反滥用踢线） =====
-- 教训背景：一帧内连续 24 次 UseContainerItem 会被服务器判定异常。所有写动作进队列，
-- OnUpdate 按 TB_RATE 间隔滴出；出售逐笔验证（下一拍核对槽位物品已消失，超时 2s 记失败）；
-- 执行前二次校验（槽位物品可能被玩家移动）；MERCHANT_HIDE 清空待售/待购（防「卖」变「用」）。
local TB_RATE = 0.3
local tbQ = {}
local tbQLast = 0
local tbPending = nil -- {bag,slot,name,cnt,t} 待验证的出售
local tbSellStat = nil -- {ok,fail} 本次扫描统计（队列清空时汇报）

local function tbQPush(q) table.insert(tbQ, q) end

local function tbVerifyPending()
  if not tbPending then return end
  local p = tbPending
  local now = (type(GetTime) == "function") and GetTime() or 0
  if tbItemName(p.bag, p.slot) ~= p.name then -- 槽位物品已消失/变更 → 卖出成功
    tbPending = nil
    if tbSellStat then tbSellStat.ok = tbSellStat.ok + 1 end
    say(string.format(L("TB_SOLD_ITEM"), p.name, p.cnt or 1, tbItemType(p.name) or "?")) -- 1.69.1 售卖明细日志（成交验证后输出，不虚报）
    return
  end
  if now - p.t > 2 then -- 超时仍在 → 失败（锁定/不可售/服务器拒绝）
    tbPending = nil
    if tbSellStat then tbSellStat.fail = tbSellStat.fail + 1 end
    say(string.format(L("TB_SELL_FAIL"), p.name))
  end
end

local tbBuyArm -- ★1.71.3 前置声明（pump 里调用，定义在后面；本文件有 DECL ORDER CHECK 守着）
local function tbQPump()
  tbVerifyPending()
  -- ★1.71.2 「按住修饰键临时停止自动交接」：keydown 那一刻把**还没滴出**的交接动作撤掉。
  --   为什么必须在这里做：交接走限频队列（TB_RATE=0.3s）——事件触发到真正执行之间有延迟，
  --   只拦后续事件的话，按 shift 之前刚入队的那一笔仍会打出去（用户会觉得「按了没用」）。
  --   ★只丢 kind=="quest"，别的一律保留：商人/丢弃/通知与「任务交接」无关（同 EVAL_TB_HOLD_ACTIVE 的边界说明）。
  --   ★不是「一次清空就完事」：按住期间仍可能有 quest 项被别处入队（例如延迟扫描的回调），
  --     所以这里每拍都判一次——按住期间队列里的 quest 项一律不留。
  if tbHoldNow() then
    local kept = {}
    local dropped = 0
    for _, q in ipairs(tbQ) do
      if q.kind == "quest" then dropped = dropped + 1 else table.insert(kept, q) end
    end
    if dropped > 0 then
      tbQ = kept
      say(string.format(L("TB_HOLD_STOP"), dropped)) -- 如实告知撤了几笔，否则用户以为按了没反应
    end
  end
  tbBuyArm() -- ★先 arm：队列空时也要能把下一笔排进来（一拍只下一笔）
  local q = tbQ[1]
  if not q then
    if tbSellStat and (tbSellStat.ok > 0 or tbSellStat.fail > 0) then
      local msg = string.format(L("TB_SOLD"), tbSellStat.ok)
      if tbSellStat.fail > 0 then msg = msg .. string.format(L("TB_SOLD_FAILS"), tbSellStat.fail) end
      say(msg)
      tbSellStat = nil
    end
    return
  end
  -- 商人相关动作必须开着商人窗口（关了直接丢弃，防止 UseContainerItem 变成「使用物品」）
  if (q.kind == "sell" or q.kind == "buy") and not TB.merchantOpen then
    table.remove(tbQ, 1)
    return
  end
  if q.kind == "sell" and tbPending then return end -- 上一笔未确认：有序等待，保证逐笔可验证
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - tbQLast < TB_RATE then return end
  table.remove(tbQ, 1)
  tbQLast = now
  if q.kind == "sell" then
    local ok, tex, cnt, locked, qual = pcall(GetContainerItemInfo, q.bag, q.slot)
    if ok and (tex or cnt) and qual == 0 and tbItemName(q.bag, q.slot) == q.name then
      pcall(UseContainerItem, q.bag, q.slot)
      tbPending = { bag = q.bag, slot = q.slot, name = q.name, cnt = cnt or q.cnt or 1, t = now }
    elseif tbSellStat then
      tbSellStat.fail = tbSellStat.fail + 1 -- 执行前校验失败（物品已被移动/品质变化）
    end
  elseif q.kind == "buy" then
    pcall(BuyMerchantItem, q.idx, q.n)
    -- ★一笔在飞：执行完立刻放行，下一拍 arm 会先核对背包再算下一批（逐笔可验证）
    TB.buyInflight = nil
  elseif q.kind == "discard" then
    if tbItemName(q.bag, q.slot) == q.name then
      local ok, tex, cnt, locked, qual = pcall(GetContainerItemInfo, q.bag, q.slot)
      if ok and (tex or cnt) and type(qual) == "number" and qual <= 1 then
        pcall(PickupContainerItem, q.bag, q.slot)
        pcall(DeleteCursorItem)
      end
    end
  elseif q.kind == "quest" then -- 1.69.0 任务交接 API 限频（对话窗口 0.3s 内保持打开，滴出执行安全）
    if type(q.fn) == "function" then pcall(q.fn) end
  elseif q.kind == "chat" then -- 1.69.0 频道通知：SendChatMessage Protected（wiki 原文）→ RunScript 绕行（1.49.3 范式）
    if type(RunScript) == "function" then
      pcall(RunScript, string.format("SendChatMessage(%q, %q)", q.text, q.ctype))
    end
  end
end

function EVAL_TB_PUMP() tbQPump() end -- 测试/调试直调用
-- ===== 自动购买（1.71.3 重做：分批买 + 逐笔核对 + 多重安全闸门）=====
-- 用户要求：「购买频率限制下防止瞬间购买；支持购买数量多个；每次购买数量默认 1；
--   购买行为要做好安全界限、异常终止等检测，比如背包满了；防止进入重复购买操作」。
-- ★设计要点：
--   ① **一拍只下一笔**（TB.buyInflight），全部走既有限频队列（TB_RATE=0.3s）逐笔滴出
--      → 天然限频，绝不会「瞬间买光」；
--   ② **每次购买数量** per（默认 1），受三个上界夹住：per / 商人一次上限 / 库存 / 还差多少；
--   ③ **逐笔核对**：下一批前先数背包，上一笔没涨 = 失败 → 连失败 TB_BUY_MAX_FAILS 次自动停用该项；
--   ④ **安全闸门**（任一命中即停并如实 say 一句）：商人窗口关了 / 背包满 / 连续失败 / 本轮总量上限；
--   ⑤ 会话状态存在 TB.buySess（**不写进配置**，不污染 SavedVariables）。
local TB_BUY_MAX_FAILS = 3
local TB_BUY_MAX_SESSION = 200
local TB_BUY_ARM_GAP = 0.35

-- 背包剩余空位（0 = 满）：判据与背包扫描同源（GetContainerNumSlots + GetContainerItemInfo）
local function tbFreeSlots()
  local free = 0
  tbBagScan(function(b, s)
    local ok, tex, cnt = pcall(GetContainerItemInfo, b, s)
    if ok and not (tex or cnt) then free = free + 1 end
  end)
  return free
end

-- 背包里某物品的总数量（按名称比对，同卖出/丢弃的判据）
local function tbCountItem(name)
  local have = 0
  tbBagScan(function(b, s)
    if tbItemName(b, s) == name then
      local ok, tex, cnt = pcall(GetContainerItemInfo, b, s)
      if ok and type(cnt) == "number" then have = have + cnt end
    end
  end)
  return have
end

-- ★纯函数：本拍该不该下单、下几件（输入全部显式传入 → 脱离游戏也能测）
--   entry = { name=, n=目标总数, per=每次数量, on=启用 }
--   st    = 该物品的**会话状态** { have0=开局数量, expect=上一笔期望达到的数量, fails=连失败数 }
--   info  = { have=背包现有, free=背包空位, avail=商人库存(-1/负=无限), idx=商人序号(nil=不卖), cap=一次上限 }
--   返回：n（本次下单数量；0/nil = 不下单）, 原因（off/done/bagfull/nomatch/avail/fails/ok）
function EVAL_TB_BUY_DECIDE(entry, st, info)
  if type(entry) ~= "table" then return 0, "off" end
  if entry.on == false then return 0, "off" end
  if type(info) ~= "table" or not info.idx then return 0, "nomatch" end
  if type(info.free) == "number" and info.free <= 0 then return 0, "bagfull" end
  local have = info.have or 0
  if st then
    -- 核对上一笔：说好买了 n 件，结果背包没涨 → 记一次失败（本轮最多 TB_BUY_MAX_FAILS 次）
    if type(st.expect) == "number" and have < st.expect then st.fails = (st.fails or 0) + 1 end
    if (st.fails or 0) >= TB_BUY_MAX_FAILS then return 0, "fails" end
  end
  -- ★1.71.3 用户要求：「购买数量」是**对着背包里现有数量**算的（绝对值目标）——
  --   背包已经够 target 件就**一件都不买**（否则每次跟商人对话都会再买一遍）。
  --   ★不要拿「本次会话开始时有多少」当基准：我第一版就是那样，等于把 n 解释成「这次**再**买 n 件」，
  --     于是背包里明明够了、每次对话仍然重复购买（用户实测报回来的正是这个）。
  local remain = (entry.n or 1) - have
  if remain <= 0 then return 0, "done" end
  local cap = (info.cap and info.cap >= 1) and info.cap or 1
  local per = (entry.per and entry.per >= 1) and entry.per or 1
  local n = per
  if n > cap then n = cap end
  if type(info.avail) == "number" and info.avail >= 0 and n > info.avail then n = info.avail end
  if n > remain then n = remain end
  if n <= 0 then return 0, "avail" end
  if st then st.expect = have + n end
  return n, "ok"
end

local tbBuyArmLast = 0
function tbBuyArm()
  local tb = tbCfg()
  if not (tb and tb.buyOn) then return end
  if not TB.merchantOpen then return end
  if TB.buyInflight then return end -- ★一笔在飞：绝不并发下单（防重复购买）
  if type(tb.buy) ~= "table" or table.getn(tb.buy) == 0 then return end
  if type(GetMerchantNumItems) ~= "function" then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - tbBuyArmLast < TB_BUY_ARM_GAP then return end -- 频率防护（本函数每帧被调）
  tbBuyArmLast = now
  local stat = TB.buyStat
  if type(stat) ~= "table" then return end
  local sess = TB.buySess
  if type(sess) ~= "table" then return end
  local free = tbFreeSlots()
  if free <= 0 then
    if not stat.bagfull then stat.bagfull = true say(L("TB_BUY_BAGFULL")) end
    return
  end
  local mn = GetMerchantNumItems() or 0
  for _, w in ipairs(tb.buy) do
    local s = sess[w.name]
    if not s then s = { fails = 0 } sess[w.name] = s end -- 只记失败数/期望值；目标数按背包现有量算（绝对值）
    -- 找商人序号 / 库存 / 一次上限
    local idx, avail, cap = nil, nil, 1
    for i = 1, mn do
      local ok, nm, _tex, _price, _quant, av = pcall(GetMerchantItemInfo, i)
      if ok and nm == w.name then
        idx = i
        if type(av) == "number" then avail = av end
        break
      end
    end
    if idx and type(GetMerchantItemMaxStack) == "function" then
      local okc, ms = pcall(GetMerchantItemMaxStack, idx)
      if okc and type(ms) == "number" and ms >= 1 then cap = ms end
    end
    local have = tbCountItem(w.name)
    local n, why = EVAL_TB_BUY_DECIDE(w, s, { have = have, free = free, avail = avail, idx = idx, cap = cap })
    if type(n) == "number" and n > 0 then
      if stat.bought + n > TB_BUY_MAX_SESSION then
        if not stat.capped then stat.capped = true say(string.format(L("TB_BUY_CAP"), TB_BUY_MAX_SESSION)) end
        return
      end
      TB.buyInflight = { name = w.name, n = n }
      tbQPush({ kind = "buy", idx = idx, n = n, name = w.name })
      return -- ★一拍只下一笔：队列按 0.3s 滴出 → 限频、不瞬间买光
    elseif why == "fails" then
      say(string.format(L("TB_BUY_FAILS"), tostring(w.name)))
      w.on = false -- 连续失败 → 自动停用该项（如实告知，避免反复重试）
    end
  end
end

-- 商人开启：修理 / 卖灰 / 购买
-- 1.68.1 实测修复：本客户端 MERCHANT_SHOW 连发两次（卖出提示打印两遍）——第二次触发时
-- 物品尚未从背包移除，会重复计数/重复提示/重复尝试出售（同槽位二次 UseContainerItem 为无害空操作，但统计失真）。
-- 去重窗口 1.5s：窗口内重复触发直接跳过。
local tbMerchantLast = 0
local function tbMerchant()
  local tb = tbCfg()
  if not tb then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - tbMerchantLast < 1.5 then return end
  tbMerchantLast = now
  if tb.repair and type(CanMerchantRepair) == "function" and CanMerchantRepair() and type(RepairAllItems) == "function" then
    local cost = (type(GetRepairAllCost) == "function") and (GetRepairAllCost() or 0) or 0
    local money = (type(GetMoney) == "function") and (GetMoney() or 0) or cost
    if cost > 0 and money >= cost then
      pcall(RepairAllItems)
      say(string.format(L("TB_REPAIRED"), fmtMoney(cost)))
    end
  end
  if tb.sell and type(UseContainerItem) == "function" and type(GetContainerItemInfo) == "function" then
    -- 1.68.2：不直接卖——灰色槽位快照入队，队列按 TB_RATE 逐笔出售并验证成功
    local n = 0
    tbSellStat = { ok = 0, fail = 0 }
  -- ★1.71.3 自动购买：每次开商人窗口都重置会话状态（上一次的进度/失败数不带过来）
  TB.buySess = {}
  TB.buyStat = { bought = 0, fails = 0 }
  TB.buyInflight = nil
    tbBagScan(function(b, s)
      local ok, tex, cnt, locked, q = pcall(GetContainerItemInfo, b, s)
      if ok and (tex or cnt) and q == 0 then
        local nm = tbItemName(b, s)
        if nm then tbQPush({ kind = "sell", bag = b, slot = s, name = nm, cnt = cnt or 1 }) n = n + 1 end
      end
    end)
    if n == 0 then tbSellStat = nil end
  end
  -- ★1.71.3：旧的「一次买够 need」整块已删除 —— 自动购买改由下方 tbBuyArm() 统一负责：
  --   一拍只下一笔、按「每次购买数量」分批、逐笔核对、并带背包满/连续失败/总量上限等安全闸门。
  --   ★一处真值：购买逻辑只此一份（旧路径留着就会出现「一次买 3 件」与「3 次各买 1 件」两套行为）。
end

-- 背包变动：丢弃列表（仅灰/白品质，防误删）
-- 性能：BAG_UPDATE 高频（拾取/修理/移动物品都触发）→ 0.5s 节流，且开关/列表为空时零开销直接返回
local tbDiscardLast = 0
local function tbDiscardSweep()
  local tb = tbCfg()
  if not (tb and tb.discardOn and type(tb.discard) == "table" and table.getn(tb.discard) > 0) then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - tbDiscardLast < 0.5 then return end
  tbDiscardLast = now
  if type(PickupContainerItem) ~= "function" or type(DeleteCursorItem) ~= "function" then return end
  local set = {}
  for _, nm in ipairs(tb.discard) do set[nm] = true end
  local n = 0
  tbBagScan(function(b, s)
    local nm = tbItemName(b, s)
    if nm and set[nm] then
      local ok, tex, cnt, locked, q = pcall(GetContainerItemInfo, b, s)
      if ok and (tex or cnt) and type(q) == "number" and q <= 1 then
        tbQPush({ kind = "discard", bag = b, slot = s, name = nm }) -- 1.68.2 限频队列+执行前二次校验
        n = n + 1
      end
    end
  end)
  if n > 0 then say(string.format(L("TB_DISCARDED"), n)) end
end

-- ★★★1.71.2 交接去重 + 频率闸门（用户实测：聊天里同一条「已自动领取任务奖励」无限刷屏）
--   根因（自触发死循环）：QUEST_COMPLETE 入队 GetQuestReward → 领奖这个动作**又触发一次 QUEST_COMPLETE**
--   → 再入队 → 再触发…… 原来**没有任何「同一任务只领一次」的判据**，于是永不停止；
--   每轮还会 say + tbNotify 各发一条，队列越积越长 → 用户看到的「队列播放信息很多」。
--   三层防护（缺一不可）：
--   ① **任务名去重**：同一个任务名在冷却窗内只处理一次（治本——循环的每一轮都是同一个任务）；
--   ② **领取窗口闸门**：QUEST_COMPLETE 之后短暂忽略后续同类事件（客户端领奖本身会重发事件）；
--   ③ **全局频率闸门**：无论什么原因，交接类动作在窗口内最多 N 笔（兜底，防「瞬间触发太多」）。
--   ★为什么三层都要：①治本但依赖「任务名拿得到」；②治客户端重发；
--     ③是**不依赖任何前提的兜底**——前两层都失灵时它仍能把刷屏压住（本项目「兜底要能独立成立」的纪律）。
local TB_QUEST_RATE_WIN = 1.0   -- 同一任务的去重窗口（秒）
local TB_QUEST_RATE_MAX = 3     -- 窗口内最多处理几笔交接（超出直接丢弃）
local tbQuestSeen = nil         -- { [任务名] = 上次处理时间 }
local tbQuestBurst = nil        -- { n = 本窗口已处理数, t0 = 窗口起点 }
local tbQuestWinUntil = 0       -- 领取窗口闸门：在此之前忽略 QUEST_COMPLETE/PROGRESS

-- 该不该处理这笔交接？返回 true=处理，false=拦下（并说明原因，便于测试与日志）
function EVAL_TB_QUEST_GATE(name, now, kind)
  if type(now) ~= "number" then now = 0 end
  -- ② 领取窗口闸门（GetQuestReward 自身会重发事件）
  if now < tbQuestWinUntil then return false, "window" end
  -- ③ 全局频率闸门（不依赖任务名，兜底）
  if type(tbQuestBurst) ~= "table" or now - tbQuestBurst.t0 >= TB_QUEST_RATE_WIN then
    tbQuestBurst = { n = 0, t0 = now }
  end
  if tbQuestBurst.n >= TB_QUEST_RATE_MAX then return false, "rate" end
  -- ① 同名去重（治本）
  if type(name) == "string" and name ~= "" and name ~= "…" then
    if type(tbQuestSeen) ~= "table" then tbQuestSeen = {} end
    local last = tbQuestSeen[name]
    if type(last) == "number" and now - last < TB_QUEST_RATE_WIN then return false, "dup" end
    tbQuestSeen[name] = now
  end
  tbQuestBurst.n = tbQuestBurst.n + 1
  -- 领奖后开一个窗口：领奖动作会再次触发 QUEST_COMPLETE
  if kind == "reward" then tbQuestWinUntil = now + TB_QUEST_RATE_WIN end
  return true
end
-- ===== 任务通知（1.69.0）：进度/接取/完成 → 可选频道（关/仅自己/说/队伍） =====
-- 频道发言：SendChatMessage 是 Protected（wiki 原文）→ RunScript 队列绕行；进限频队列防刷屏踢线
-- 1.69.2 滞后修复：QUEST_LOG_UPDATE 事件先于日志数据落地——事件里同步扫描读到的是【上一状态】，通知滞后一个状态
-- （UnrealQuest QuestState.lua 同结论：不信任事件时序，轮询重建+事件仅作唤醒）→ 事件只排期 tbQScanDue，OnUpdate 延迟 0.3s 再扫
local tbQScanLast = 0
local tbQPrev = nil          -- 上次扫描快照；nil=未初始化（登录/reload 首次建档不刷屏）
local tbLastCompleteName = nil -- 最近一个 isComplete==1 的任务名（交接日志/完成通知用）

local function tbQuestScan()
  -- pcall 直调，不套 and/or（1.64.0 教训：逻辑表达式截断多返回）
  local cur = {}
  if type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then return cur end
  local okn, n = pcall(GetNumQuestLogEntries)
  if not (okn and type(n) == "number") then return cur end
  for i = 1, n do
    local okt, title, _lvl, _tag, isHeader, _col, isComplete = pcall(GetQuestLogTitle, i)
    -- ★★★1.71.2（第五轮）修「任务接取： 」空名日志（用户截图：先一条空白，紧跟着才是正确名）。
    --   根因：**Lua 里空字符串是真值**（已用 fengari 实测确认）。
    --   新接的任务刚进日志时，那一行已存在但标题尚未填充 → 取到 **title = ""**（不是 nil）
    --   → 旧写法 `if okt and title` 对 "" 也成立（nil 才会被挡住）→ 入库成 `cur[""]`，
    --   被当成一个名叫空的**新任务** → 立刻播一条「任务接取： 」；
    --   下一轮扫描真名到位 → 又播一条正确的 ⇒ 就是用户看到的「先空白、后正确」两条。
    --   ★判据：**“字段存在”与“字段有内容”是两件事**；只看 truthy 会把空串当有效值。
    --   ★为什么不能只在播报处过滤：那样 `cur[""]` 仍会进快照，轮次一到又会当成“新任务”重复播 → 必须在**入库处**挡。
    if okt and type(title) == "string" and title ~= "" and not isHeader then
      local objs = {}
      if type(GetQuestLogLeaderBoard) == "function" then
        for oi = 1, 4 do
          local oko, txt, _typ = pcall(GetQuestLogLeaderBoard, oi, i)
          if oko and txt then
            local d2, m2 = string.match(txt, "(%d+)%s*/%s*(%d+)")
            objs[oi] = { txt = txt, d = tonumber(d2) or 0, m = tonumber(m2) or 0 }
          end
        end
      end
      cur[title] = { objs = objs, complete = (isComplete == 1) }
      if isComplete == 1 then tbLastCompleteName = title end
    end
  end
  return cur
end

local TB_CHAN_ORDER = { "off", "self", "say", "party" }
local function tbNotify(msg)
  local tb = tbCfg()
  local ch = (tb and tb.qchan) or "off"
  if ch == "off" then return end
  if ch == "self" then say(msg) return end
  tbQPush({ kind = "chat", text = msg, ctype = (ch == "party") and "PARTY" or "SAY" })
end

local function tbQuestDiff()
  local tb = tbCfg()
  if not (tb and tb.qchan and tb.qchan ~= "off") then return end
  local cur = tbQuestScan() -- 0.5s 节流在调度器 tbQuestTick（顺延制不丢最终状态），此处只负责扫+差分
  if not tbQPrev then tbQPrev = cur return end
  for name, q in pairs(cur) do
    local old = tbQPrev[name]
    if not old then
      -- ★1.71.2（第五轮）双重保护：名字为空就**不播**（与扫描处的入库挡形成两道防线）。
      --   为什么还要在这里挡：扫描那道只管 `GetQuestLogTitle` 这一个数据源；
      --   一旦将来换/新增来源（比如从事件参数取名），空名会从另一条路漏进来。
      --   ★播报层挡住 = 用户**看不到**空白日志（这才是需求本身），与入库层挡住（保快照干净）各管一侧。
      -- ★1.71.2（第五轮）双重保护：名字为空就**不播**（与扫描处的入库挡形成两道防线）。
      --   为什么还要在这里挡：扫描那道只管 `GetQuestLogTitle` 这一个数据源；
      --   一旦将来换/新增来源（比如从事件参数取名），空名会从另一条路漏进来。
      --   ★播报层挡住 = 用户**看不到**空白日志（这才是需求本身），与入库层挡住（保快照干净）各管一侧。
      --   ★★两道防线是**刻意**的冗余：变异实验时只拆一道、另一道仍会挡住 → 看起来像“测试抓不到”，
      --     实际是“两道同时拆掉才复现”。★判据：**冗余防护的变异必须整组拆**，否则会把有效断言误判成无效。
      if type(name) == "string" and name ~= "" then
        tbNotify(string.format(L("TB_QN_ACCEPT"), name)) -- 新出现的任务 = 接取
      end
    else
      for oi, o in ipairs(q.objs) do
        local oo = old.objs[oi]
        if oo and o.d > oo.d then
          tbNotify(string.format(L("TB_QN_PROG"), name, o.txt or "")) -- 目标计数增加 = 进度
        end
      end
    end
  end
  tbQPrev = cur
end

-- 1.69.2 延迟扫描调度：事件只排期，到点扫描；节流中顺延（不丢弃，保证最终状态一定被扫到）
local TB_QSCAN_DELAY = 0.3
local tbQScanDue = 0
local function tbQuestTick()
  if tbQScanDue <= 0 then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now < tbQScanDue then return end
  if now - tbQScanLast < 0.5 then tbQScanDue = tbQScanLast + 0.5 return end
  tbQScanDue = 0
  tbQScanLast = now
  tbQuestDiff()
end
function EVAL_TB_TICK() tbQuestTick() tbQPump() end -- 测试直调（= qf OnUpdate 本体）

-- 事件统一入口（测试可直调）
-- ★1.71.2 事件节流：QUEST_* 三类事件加上闸门后，**被拦下的不再入队、也不再播报**——
--   用户看到的刷屏正是「每轮都 say + notify」，闸门必须拦在**播报之前**（否则消息照样刷）。
local function tbNow() return (type(GetTime) == "function") and GetTime() or 0 end
function EVAL_TB_ONEVENT(e)
  if e == "MERCHANT_SHOW" then
    TB.merchantOpen = true
    tbMerchant()
  elseif e == "MERCHANT_HIDE" then
    -- 关窗即清场：待售/待购全部丢弃（防 UseContainerItem 在无商人时变成使用物品），待验证出售作废
    TB.merchantOpen = false
    tbPending = nil
    local kept = {}
    for _, q in ipairs(tbQ) do
      if q.kind ~= "sell" and q.kind ~= "buy" then table.insert(kept, q) end
    end
    tbQ = kept
  elseif e == "BAG_UPDATE" then
    tbDiscardSweep()
  elseif e == "READY_CHECK" then
    local tb = tbCfg()
    if tb and tb.ready and type(ConfirmReadyCheck) == "function" then pcall(ConfirmReadyCheck) end
  elseif e == "QUEST_DETAIL" then
    local tb = tbCfg()
    local gOK = EVAL_TB_QUEST_GATE(nil, tbNow(), "accept")
    if tb and gOK and not tbHoldNow() and tb.questAccept and type(AcceptQuest) == "function" then
      tbQPush({ kind = "quest", fn = function() pcall(AcceptQuest) end }) -- 1.69.0 限频队列
      say(L("TB_Q_ACCEPT"))
    end
  elseif e == "QUEST_PROGRESS" then
    local tb = tbCfg()
    if tb and not tbHoldNow() and tb.questTurnIn and type(IsQuestCompletable) == "function" and IsQuestCompletable() and type(CompleteQuest) == "function" then
      local cur = tbQuestScan() -- 1.69.0 记录待交任务名（交接日志/完成通知用）
      for nm, q in pairs(cur) do if q.complete then tbLastCompleteName = nm end end
      -- ★闸门放在**拿到任务名之后**：同名去重需要一个名字（这是治本那一层）
      if not EVAL_TB_QUEST_GATE(tbLastCompleteName, tbNow(), "complete") then return end
      tbQPush({ kind = "quest", fn = function() pcall(CompleteQuest) end }) -- 限频队列
      say(string.format(L("TB_Q_PROGRESS"), tbLastCompleteName or "…"))
    end
  elseif e == "QUEST_COMPLETE" then
    local tb = tbCfg()
    if tb and not tbHoldNow() and tb.questTurnIn and type(GetNumQuestChoices) == "function" and type(GetQuestReward) == "function" then
      local nc = GetNumQuestChoices() or 0
      local nm = tbLastCompleteName or "…"
      -- ★★领奖是**自触发循环**的源头：GetQuestReward 会再触发 QUEST_COMPLETE。
      --   闸门必须在入队**之前**判（否则奖励照领军令状照刷）。
      if not EVAL_TB_QUEST_GATE(nm, tbNow(), "reward") then return end
      if nc <= 1 then -- 多奖励（>1）留给玩家手选
        tbQPush({ kind = "quest", fn = function() pcall(GetQuestReward, nc == 1 and 1 or nil) end }) -- 1.69.0 限频队列
        say(string.format(L("TB_Q_TURNIN"), nm))
        tbNotify(string.format(L("TB_QN_DONE"), nm)) -- 完成通知
      end
    end
  elseif e == "QUEST_LOG_UPDATE" then -- 1.69.2 只排期不同步扫（事件先于数据落地，同步扫=滞后一个状态）
    tbQScanDue = ((type(GetTime) == "function") and GetTime() or 0) + TB_QSCAN_DELAY
  end
end

-- 事件帧（三态兼容：事件名在 1参/2参/全局 event）
local evf = CreateFrame("Frame", "EVAL_TOOLBOX_EVENTS", UIParent)
evf:RegisterEvent("MERCHANT_SHOW")
evf:RegisterEvent("MERCHANT_HIDE")
evf:RegisterEvent("BAG_UPDATE")
evf:RegisterEvent("READY_CHECK")
evf:RegisterEvent("QUEST_DETAIL")
evf:RegisterEvent("QUEST_PROGRESS")
evf:RegisterEvent("QUEST_COMPLETE")
evf:RegisterEvent("QUEST_LOG_UPDATE") -- 1.69.0 任务进度通知（日志扫描差分）
evf:RegisterEvent("VARIABLES_LOADED")      -- ★1.71.3 频道屏蔽：载入时聊天框常还没建好，这里再试一次
evf:RegisterEvent("PLAYER_ENTERING_WORLD") -- ★进入世界后再试一次（最可靠的时机）
evf:SetScript("OnEvent", function()
  local e = nil
  if type(event) == "string" then e = event end
  if not e and type(arg1) == "string" then e = arg1 end
  if not e and type(arg2) == "string" then e = arg2 end
  tbChanRetry() -- ★1.71.3 每次事件顺手重试一次频道屏蔽挂载（幂等；成功后立即短路）
  if e then EVAL_TB_ONEVENT(e) end
end)

-- 队列滴出帧：每帧检查一次（队空时仅一次表索引+一次 GetTime 比较，开销可忽略）
local qf = CreateFrame("Frame", "EVAL_TOOLBOX_QUEUE", UIParent)
qf:SetScript("OnUpdate", function()
  tbChanRetry() -- ★1.71.3 频道屏蔽挂载的兜底重试（限频 1s；挂上后只做一次布尔判断，开销可忽略）
  tbQuestTick() tbQPump() -- 1.69.2 任务延迟扫描 + 队列滴出
end)

-- ===== Tab 内容模型（分组归类；列表行动态展开） =====
-- 标签里带上当前按键名（如「按住[Shift]临时停止」）——用户一眼看到现在挂的是哪个键。
-- ★用 label 生成而不是在 UI 渲染时现拼：保持「模型出内容、UI 只渲染」的既有分工，
--   也让断言可以直接查 tbModel() 的 label（不必去读 FontString）。
local function tbHoldLabel()
  local tb = tbCfg()
  local cur = (tb and tb.holdKey) or TB_HOLD_DEFAULT
  if cur == "off" or cur == "" then return L("TB_HOLD_OFF") end
  return string.format(L("TB_HOLD_FMT"), TB_HOLD_LABEL[cur] or "Shift")
end

local function tbModel()
  return {
    { t = "h", label = L("TB_H_MERCHANT") },
    { t = "c", key = "repair", label = L("TB_REPAIR"), tip = L("TB_REPAIR_TIP") },
    { t = "c", key = "sell", label = L("TB_SELL"), tip = L("TB_SELL_TIP") },
    { t = "l", key = "buy", flag = "buyOn", label = L("TB_BUY"), tip = L("TB_BUY_TIP"), ask = L("TB_BUY_ASK") },
    { t = "l", key = "discard", flag = "discardOn", label = L("TB_DISCARD"), tip = L("TB_DISCARD_TIP"), ask = L("TB_DISCARD_ASK") },
    { t = "h", label = L("TB_H_SOCIAL") },
    { t = "c", key = "ready", label = L("TB_READY"), tip = L("TB_READY_TIP") },
    -- ★1.71.3 用户要求：屏蔽「XX 加入/离开频道」这类通知（默认开）
    { t = "c", key = "chanJoin", label = L("TB_CHANJOIN"), tip = L("TB_CHANJOIN_TIP") },
    { t = "g", label = L("TB_GUILDNOTIFY"), tip = L("TB_GUILDNOTIFY_TIP") },
    { t = "h", label = L("TB_H_QAUTO") }, -- 1.69.0 任务组拆分：自动交接 / 任务通知
    -- ★1.71.2 用户要求：自动接取 / 交付任务 **分成两个开关**（原来共用一个 quest 键，想只接取不交付做不到）
    { t = "c", key = "questAccept", label = L("TB_QUEST_ACCEPT"), tip = L("TB_QUEST_ACCEPT_TIP") },
    { t = "c", key = "questTurnIn", label = L("TB_QUEST_TURNIN"), tip = L("TB_QUEST_TURNIN_TIP") },
    -- ★1.71.2 用户要求：「自动交接任务 按键停止功能，比如按住 shift 临时停止」
    { t = "key", key = "holdKey", label = tbHoldLabel(), tip = L("TB_HOLD_TIP") },
    { t = "h", label = L("TB_H_QNOTIFY") },
    { t = "ch", key = "qchan", label = L("TB_QCHAN"), tip = L("TB_QCHAN_TIP") }, -- 频道选择行
  }
end

-- ★测试钩子（1.71.2）：把「行模型」与「迁移」暴露给冒烟测试，
--   否则「UI 真的有两行独立复选框」只能靠人眼看界面（本项目 1.70.46 的教训：只测解析不测调用点）
function EVAL_TEST_TB_ROWS() return tbModel() end
-- ★1.71.3 测试钩子：走**真的 tbCfg()**（迁移也在里面跑）——直接读 EVAL_HELP_CONFIG.tb 不会触发迁移。
function EVAL_TEST_TB_CFG() return tbCfg() end
-- ★1.71.3 测试钩子：取某个 key 对应行的 [添加] 按钮（走真实控件，断言才能点真实 OnClick）
function EVAL_TEST_TB_ADD_BTN_FOR(key)
  if not TB.built then return nil end
  local m = tbModel()
  for i = 1, TB.ROWS do
    local it = m[TB.off + i]
    if it and it.key == key and TB.rows[i] and TB.rows[i].add then return TB.rows[i].add.btn end
  end
  return nil
end
function EVAL_TEST_TB_MIGRATE(t) tbMigrateQuest(t) return t end
function EVAL_TEST_TB_HOLD_KEYS() return TB_HOLD_KEYS, TB_HOLD_LABEL end

local function tbAddItem(key, txt)
  local tb = tbCfg()
  if not tb then return end
  txt = string.gsub(txt or "", "^%s*(.-)%s*$", "%1")
  if txt == "" then return end
  if key == "buy" then
    local nm, n = string.match(txt, "^(.-)[,，]%s*(%d+)$")
    tb.buy = tb.buy or {}
    if nm then
      nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
      table.insert(tb.buy, { name = nm, n = tonumber(n) or 1, per = 1, on = true })
    else
      table.insert(tb.buy, { name = txt, n = 1, per = 1, on = true })
    end
  else
    tb.discard = tb.discard or {}
    table.insert(tb.discard, txt)
  end
end

local function tbListSummary(key)
  local tb = tbCfg()
  if not tb then return "" end
  local parts = {}
  if key == "buy" and type(tb.buy) == "table" then
    for _, w in ipairs(tb.buy) do
      local s = tostring(w.name) .. "×" .. tostring(w.n or 1)
      if (w.per or 1) > 1 then s = s .. string.format(L("TB_BUY_SUM_PER"), w.per) end
      if w.on == false then s = s .. L("TB_BUY_SUM_OFF") end
      table.insert(parts, s)
    end
  elseif key == "discard" and type(tb.discard) == "table" then
    for _, nm in ipairs(tb.discard) do table.insert(parts, tostring(nm)) end
  end
  local s = table.concat(parts, "、")
  if string.len(s) > 40 then s = string.sub(s, 1, 40) .. "…" end
  return s
end

-- ===== 刷新（滚动窗口切片：可见性走显式 Show/Hide 契约） =====
function EVAL_TB_REFRESH()
  if not TB.built then return end
  local m = tbModel()
  local n = table.getn(m)
  local maxOff = math.max(0, n - TB.ROWS)
  TB.off = math.min(TB.off, maxOff)
  local LX = 18
  for i = 1, TB.ROWS do
    local r = TB.rows[i]
    local it = m[TB.off + i]
    r.chk:Hide() r.text:Hide() r.hdr:Hide() r.extra:Hide() r.add.btn:Hide() r.clr.btn:Hide() r.chv.btn:Hide()
    r.get, r.set = nil, nil
    if it then
      if it.t == "h" then
        r.hdr:SetText(it.label)
        r.hdr:Show()
      else
        if it.t == "c" then
          local key = it.key
          r.get = function() local tb = tbCfg() return tb and tb[key] and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[key] = v and true or false end end
        elseif it.t == "g" then -- CVar 直读型（公会上下线提示）
          r.get = function() return type(GetCVar) == "function" and GetCVar("guildMemberNotify") == "0" end
          r.set = function(v) if type(SetCVar) == "function" then SetCVar("guildMemberNotify", v and 0 or 1) end end
        elseif it.t == "l" then
          local flag = it.flag
          r.get = function() local tb = tbCfg() return tb and tb[flag] and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[flag] = v and true or false end end
          r.extra:SetText(tbListSummary(it.key))
          r.extra:Show()
          r.add.btn:Show()
          r.clr.btn:Show()
          r.add.btn:SetScript("OnClick", function()
            -- ★1.71.3：自动购买改开**专用设置窗**（启用/名称/总数/每次 四列可编辑）；其他列表行仍走原来的输入弹窗。
            if it.key == "buy" and type(EVAL_BUY_UI_OPEN) == "function" then EVAL_BUY_UI_OPEN() return end
            if type(EVAL_TN_OPEN) == "function" then
              EVAL_TN_OPEN(it.ask, "", function(txt) tbAddItem(it.key, txt) EVAL_TB_REFRESH() end)
            end
          end)
          r.clr.btn:SetScript("OnClick", function()
            local tb = tbCfg()
            if tb then tb[it.key] = {} end
            if type(EVAL_BUY_UI_REFRESH) == "function" then EVAL_BUY_UI_REFRESH() end
            EVAL_TB_REFRESH()
          end)
        end
        if it.t == "key" then -- ★1.71.2 按住即临时停止自动交接（key 行：勾选=启用，值按钮弹按键下拉）
          local key = it.key
          -- ★与 ch 行同样用「勾选框 = 是否启用」的既有交互：不新造控件类型，用户不用重新学。
          --   勾选 = 启用（默认 shift）；取消勾选 = 写 "off"（功能关闭，永远不暂停）。
          r.get = function() local tb = tbCfg() return tb and tb[key] ~= "off" and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[key] = v and (tb[key] == "off" and "shift" or tb[key] or "shift") or "off" end end
          local cur = (function() local tb = tbCfg() return (tb and tb[key]) or TB_HOLD_DEFAULT end)()
          r.chv.text:SetText(TB_HOLD_LABEL[cur] or "Shift")
          r.chv.btn:Show()
          r.chv.btn:SetScript("OnClick", function()
            if type(EVAL_DD_OPEN) ~= "function" then return end
            local items = {}
            for _, k in ipairs(TB_HOLD_KEYS) do
              if k == "off" then table.insert(items, L("TB_CH_OFF")) else table.insert(items, TB_HOLD_LABEL[k]) end
            end
            EVAL_DD_OPEN(r.chv.btn, items, function(pi)
              local tb2 = tbCfg()
              if tb2 then
                local picked = TB_HOLD_KEYS[pi]
                tb2[key] = (picked == "off") and "off" or (picked or TB_HOLD_DEFAULT)
              end
              EVAL_TB_REFRESH()
            end)
          end)
        end
        if it.t == "ch" then -- 1.69.0 频道选择行：勾选=启用（仅自己），值按钮弹频道下拉
          local key = it.key
          r.get = function() local tb = tbCfg() return tb and tb[key] ~= nil and tb[key] ~= "off" and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[key] = v and "self" or "off" end end
          local cur = (function() local tb = tbCfg() return (tb and tb[key]) or "off" end)()
          r.chv.text:SetText(L("TB_CH_" .. string.upper(cur)) or cur)
          r.chv.btn:Show()
          r.chv.btn:SetScript("OnClick", function()
            if type(EVAL_DD_OPEN) == "function" then
              EVAL_DD_OPEN(r.chv.btn, { L("TB_CH_OFF"), L("TB_CH_SELF"), L("TB_CH_SAY"), L("TB_CH_PARTY") }, function(pi)
                local tb = tbCfg()
                if tb then tb[key] = TB_CHAN_ORDER[pi] or "off" end
                EVAL_TB_REFRESH()
              end)
            end
          end)
        end
        if r.get and r.get() then r.mark:Show() else r.mark:Hide() end
        r.chk:Show()
        r.text:SetText(it.label)
        r.text:Show()
        r.tip = it.tip
      end
    end
  end
  if TB.indicator then
    if n > TB.ROWS then
      TB.indicator:SetText(string.format("%d-%d / %d", TB.off + 1, math.min(TB.off + TB.ROWS, n), n))
      TB.indicator:Show()
    else
      TB.indicator:Hide()
    end
  end
  if TB.scrollUp then
    if TB.off > 0 then TB.scrollUp.btn:Show() else TB.scrollUp.btn:Hide() end
    if TB.off < maxOff then TB.scrollDn.btn:Show() else TB.scrollDn.btn:Hide() end
  end
end

-- ===== 构建入口（配置窗调用；page.widgets 走 Tab 显隐契约） =====
function EVAL_TB_BUILD(root, page, refreshes)
  if TB.built then return end
  local widgets = page.widgets
  local LX, ROWH = 18, 24
  local RW = (root.GetWidth and root:GetWidth() or 560) - 18

  for i = 1, TB.ROWS do
    local y = -56 - (i - 1) * ROWH
    local row = {}
    -- 勾选框（复刻 cfgCheck 金边风格）
    local chk = CreateFrame("Button", nil, root)
    chk:SetWidth(16) chk:SetHeight(16)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", LX, y)
    pcall(chk.EnableMouse, chk, true)
    pcall(chk.RegisterForClicks, chk, "LeftButtonUp")
    local outer = chk:CreateTexture(nil, "BACKGROUND")
    tbSolid(outer, 0.85, 0.70, 0.20, 1)
    outer:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0)
    outer:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    local inner = chk:CreateTexture(nil, "ARTWORK")
    tbSolid(inner, 0.10, 0.09, 0.06, 1)
    inner:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
    local mark = chk:CreateTexture(nil, "OVERLAY")
    tbSolid(mark, 0.95, 0.80, 0.25, 1)
    mark:SetPoint("TOPLEFT", chk, "TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -3, 3)
    mark:Hide()
    row.chk, row.mark = chk, mark
    chk:SetScript("OnClick", function()
      if row.get and row.set then row.set(not row.get()) end
      EVAL_TB_REFRESH()
    end)
    chk:SetScript("OnEnter", function()
      if not row.tip then return end
      GameTooltip:SetOwner(chk, "ANCHOR_RIGHT")
      GameTooltip:AddLine(tostring(row.text:GetText() or ""), 1, 0.82, 0.3)
      GameTooltip:AddLine(row.tip, 0.85, 0.85, 0.85, 1)
      GameTooltip:Show()
    end)
    chk:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(widgets, chk)
    -- 标签（与勾选框共中心线锚定，1.45.1 对齐范式）
    local text = tbText(root, 11, 0.92, 0.88, 0.80)
    text:SetPoint("LEFT", chk, "RIGHT", 6, 0)
    row.text = text
    table.insert(widgets, text)
    -- 组标题
    local hdr = tbText(root, 11, 0.95, 0.80, 0.30)
    hdr:SetPoint("TOPLEFT", root, "TOPLEFT", LX, y - 3)
    row.hdr = hdr
    table.insert(widgets, hdr)
    -- 列表摘要 + 添加/清空
    local extra = tbText(root, 10, 0.75, 0.72, 0.60)
    extra:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 190, y - 3)
    row.extra = extra
    table.insert(widgets, extra)
    row.add = tbBtn(root, RW - 96, y, 44, L("TB_ADD"), function() end, widgets)
    row.clr = tbBtn(root, RW - 48, y, 40, L("TB_CLEAR"), function() end, widgets)
    row.chv = tbBtn(root, RW - 96, y, 88, "", function() end, widgets) -- 1.69.0 频道值按钮（ch 行）
    TB.rows[i] = row
  end

  -- ★★★1.73.9 用户（截图圈出右侧的 ▲ 与底部 ▼+计数）：
  --   「工具箱滚动样式参考图标库那边的滚动方式,然后放置在底部和关闭同行.右对齐关闭旁边」
  --   → 撤掉右上角的 ▲ 与列表下方的 ▼，改成**底部一行**（图标库同款）：
  --     [计数文字 ……]              [上翻][下翻]  [关闭]
  --     两个文字按钮右端停在 [关闭] 左边、与 [关闭]**中线对齐**；计数文字挪到同一行左侧。
  --   ★几何从 EvalHelp 的**生产读值口** EVAL_HELP_CFG_BOTTOM() 取（CLOSE_MIDY / CLOSE_LEFT 的单一来源）；
  --     拿不到就按关闭按钮的公式回退（不写死坐标、也不崩）。滚轮那段保持原样（挂 root、仅 Tab3 响应）。
  local TB_TAIL_GAP, TB_BTN_W, TB_BTN_GAP, TB_STATUS_GAP = 10, 52, 4, 8
  local BOT = (type(EVAL_HELP_CFG_BOTTOM) == "function") and EVAL_HELP_CFG_BOTTOM() or nil
  local okh, hWin = pcall(root.GetHeight, root)
  if type(hWin) ~= "number" or hWin <= 0 then hWin = 460 end
  local botMidY = (BOT and tonumber(BOT.midY)) or -(hWin - 10 - 11) -- 10=底边距 11=关闭高/2
  local closeLeft = (BOT and tonumber(BOT.closeLeft)) or ((root.GetWidth and root:GetWidth() or 660) - 12 - 64)
  TB.botMidY, TB.closeLeft = botMidY, closeLeft
  local bx = closeLeft - TB_TAIL_GAP - (TB_BTN_W * 2 + TB_BTN_GAP) -- 按钮组左端（右端 = closeLeft - TB_TAIL_GAP）
  local btnTop = botMidY + 7.5 -- tbBtn 高 15 → 中线对齐关闭的中线
  TB.scrollUp = tbBtn(root, bx, btnTop, TB_BTN_W, L("TB_UP"), function()
    TB.off = math.max(0, TB.off - 1)
    EVAL_TB_REFRESH()
  end, widgets)
  TB.scrollDn = tbBtn(root, bx + TB_BTN_W + TB_BTN_GAP, btnTop, TB_BTN_W, L("TB_DN"), function()
    TB.off = TB.off + 1
    EVAL_TB_REFRESH()
  end, widgets)
  local ind = tbText(root, 10, 0.65, 0.62, 0.50)
  ind:SetPoint("TOPLEFT", root, "TOPLEFT", LX, botMidY + 5)
  local indW = bx - TB_STATUS_GAP - LX
  if indW < 120 then indW = 120 end
  pcall(ind.SetWidth, ind, indW)
  pcall(ind.SetJustifyH, ind, "LEFT")
  TB.indicator = ind
  table.insert(widgets, ind)
  pcall(root.EnableMouseWheel, root, true)
  root:SetScript("OnMouseWheel", function(a, b)
    -- 仅 Tab3 可见时响应（widgets 显隐契约：非本 Tab 全部 Hide，首行组标题必然隐藏）
    if not (TB.rows[1] and TB.rows[1].hdr:IsVisible()) then return end
    -- ★1.73.3 方向单一来源（原来只读全局 arg1；现在 a/b/arg1 三种写法都认）
    local dir = EVAL_WHEEL_DIR(a, b)
    if dir == 0 then return end
    TB.off = math.max(0, TB.off - dir) -- 上滚 = 回到前面
    EVAL_TB_REFRESH()
  end)

  TB.built = true
  EVAL_TB_REFRESH()
end

-- ===== 自动购买设置窗（1.71.3：列表「启用 | 名称 | 总数 | 每次」+ 安全提示）=====
-- ★为什么单独开窗：工具箱那一行只能放「摘要 + 添加/清空」，而 启用/总数/每次 三个字段都要能改，
--   挤在摘要行里根本没法编辑 → 独立列表窗最清楚（列头 + 每行可点格子）。
-- ★交互沿用既有范式：勾选框 = 启用；点格子 → EVAL_TN_OPEN 输入；[删] = 单条删除；[清空] = 全清。
local TB_BUY_UI_ROWS = 8
local buyUI = { off = 0 }

local function buyUIList()
  local tb = tbCfg()
  if not tb then return nil end
  if type(tb.buy) ~= "table" then tb.buy = {} end
  return tb.buy
end

local function buyUIRefresh()
  if not buyUI.root then return end
  local list = buyUIList() or {}
  local n = table.getn(list)
  local maxOff = math.max(0, n - TB_BUY_UI_ROWS)
  if buyUI.off > maxOff then buyUI.off = maxOff end
  if buyUI.empty then if n == 0 then buyUI.empty:Show() else buyUI.empty:Hide() end end
  for i = 1, TB_BUY_UI_ROWS do
    local r = buyUI.rows[i]
    local e = list[buyUI.off + i]
    if e then
      if i % 2 == 0 then r.stripe:Hide() else r.stripe:Show() end
      r.chk:Show() r.name:Show() r.nt:Show() r.pt:Show() r.del:Show()
      r.nameBtn:Show() r.nBtn:Show() r.pBtn:Show()
      if e.on ~= false then r.mark:Show() else r.mark:Hide() end
      r.name:SetText(tostring(e.name or "?"))
      r.nt:SetText(tostring(e.n or 1))
      r.pt:SetText(tostring(e.per or 1))
      r.chk:SetScript("OnClick", function()
        if e.on == false then e.on = true else e.on = false end -- nil/true 都算启用（老配置兼容）
        buyUIRefresh() EVAL_TB_REFRESH()
      end)
      r.nameBtn:SetScript("OnClick", function()
        if type(EVAL_TN_OPEN) ~= "function" then return end
        EVAL_TN_OPEN(L("TB_BUY_ASK_NAME"), tostring(e.name or ""), function(txt)
          txt = string.gsub(txt or "", "^%s*(.-)%s*$", "%1")
          if txt ~= "" then e.name = txt buyUIRefresh() EVAL_TB_REFRESH() end
        end)
      end)
      r.nBtn:SetScript("OnClick", function()
        if type(EVAL_TN_OPEN) ~= "function" then return end
        EVAL_TN_OPEN(L("TB_BUY_ASK_N"), tostring(e.n or 1), function(txt)
          local v = tonumber(txt)
          if v and v >= 1 then e.n = math.floor(v) buyUIRefresh() EVAL_TB_REFRESH() end
        end)
      end)
      r.pBtn:SetScript("OnClick", function()
        if type(EVAL_TN_OPEN) ~= "function" then return end
        EVAL_TN_OPEN(L("TB_BUY_ASK_PER"), tostring(e.per or 1), function(txt)
          local v = tonumber(txt)
          if v and v >= 1 then e.per = math.floor(v) buyUIRefresh() EVAL_TB_REFRESH() end
        end)
      end)
      r.del:SetScript("OnClick", function()
        local l2 = buyUIList() or {}
        for k, w in ipairs(l2) do if w == e then table.remove(l2, k) break end end -- 按身份删（不受刷新位移影响）
        buyUIRefresh() EVAL_TB_REFRESH()
      end)
    else
      r.stripe:Hide() r.chk:Hide() r.name:Hide() r.nt:Hide() r.pt:Hide() r.del:Hide()
      r.nameBtn:Hide() r.nBtn:Hide() r.pBtn:Hide()
    end
  end
  if buyUI.ind then
    local pages = math.max(1, math.ceil(n / TB_BUY_UI_ROWS))
    buyUI.ind:SetText(string.format("%d/%d  (%d)", buyUI.off / TB_BUY_UI_ROWS + 1, pages, n))
  end
end

local function buyUIBuild()
  if buyUI.root then return end
  local W, H = 360, 268
  local root = CreateFrame("Frame", "EVAL_BUY_UI", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 60, 40)
  pcall(root.SetFrameStrata, root, "DIALOG")
  local bg = root:CreateTexture(nil, "BACKGROUND")
  tbSolid(bg, 0.05, 0.05, 0.07, 0.96)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  local bar = root:CreateTexture(nil, "BORDER")
  tbSolid(bar, 0.20, 0.16, 0.08, 1)
  bar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  bar:SetHeight(22)
  local function edge(ax, ay, w2, h2)
    local t = root:CreateTexture(nil, "BORDER")
    tbSolid(t, 0.45, 0.38, 0.18, 0.9)
    t:SetPoint("TOPLEFT", root, "TOPLEFT", ax, ay)
    t:SetWidth(w2) t:SetHeight(h2)
  end
  edge(0, 0, W, 1) edge(0, -(H - 1), W, 1) edge(0, 0, 1, H) edge(W - 1, 0, 1, H)
  local title = tbText(root, 12, 0.95, 0.80, 0.30)
  title:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -6)
  title:SetText(L("TB_BUY_UI_TITLE"))
  local tipLine = tbText(root, 9, 0.62, 0.60, 0.52)
  tipLine:SetPoint("TOPLEFT", root, "TOPLEFT", 120, -9)
  tipLine:SetText(L("TB_BUY_UI_TIP"))
  local closeB = tbBtn(root, W - 26, -3, 18, "X", function() root:Hide() end)
  -- 列头
  local function head(x, txt, right)
    local h = tbText(root, 10, 0.80, 0.72, 0.45)
    if right then h:SetPoint("TOPRIGHT", root, "TOPRIGHT", -x, -30)
    else h:SetPoint("TOPLEFT", root, "TOPLEFT", x, -30) end
    h:SetText(txt)
  end
  head(14, L("TB_BUY_COL_ON")) head(46, L("TB_BUY_COL_NAME"))
  head(244, L("TB_BUY_COL_N"), true) head(302, L("TB_BUY_COL_PER"), true)
  head(W - 12, L("TB_BUY_COL_DEL"), true)
  local rows = {}
  buyUI.rows = rows
  for i = 1, TB_BUY_UI_ROWS do
    local y = -44 - (i - 1) * 18
    local r = {}
    r.stripe = root:CreateTexture(nil, "BACKGROUND")
    tbSolid(r.stripe, 0.14, 0.13, 0.11, 0.55)
    r.stripe:SetPoint("TOPLEFT", root, "TOPLEFT", 8, y + 2)
    r.stripe:SetWidth(W - 16)
    r.stripe:SetHeight(16)
    local chk = CreateFrame("Button", nil, root)
    chk:SetWidth(14) chk:SetHeight(14)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", 14, y)
    pcall(chk.EnableMouse, chk, true)
    pcall(chk.RegisterForClicks, chk, "LeftButtonUp")
    local cb = chk:CreateTexture(nil, "BACKGROUND")
    tbSolid(cb, 0.30, 0.28, 0.22, 1)
    cb:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0)
    cb:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    local cm = chk:CreateTexture(nil, "ARTWORK")
    tbSolid(cm, 0.95, 0.82, 0.35, 1)
    cm:SetPoint("TOPLEFT", chk, "TOPLEFT", 3, -3)
    cm:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -3, 3)
    r.chk = chk r.mark = cm
    local function cell(x, w, right)
      local b = CreateFrame("Button", nil, root)
      b:SetWidth(w) b:SetHeight(14)
      b:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
      pcall(b.EnableMouse, b, true)
      pcall(b.RegisterForClicks, b, "LeftButtonUp")
      local t = tbText(root, 10, 0.90, 0.88, 0.82)
      if right then t:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(W - x - w), y - 2)
      else t:SetPoint("TOPLEFT", root, "TOPLEFT", x + 2, y - 2) end
      return b, t
    end
    local nb, nt = cell(46, 150, false)
    local qb, qt = cell(200, 44, true)
    local pb, pt = cell(256, 44, true)
    r.name, r.nt, r.pt = nt, qt, pt
    r.nameBtn, r.nBtn, r.pBtn = nb, qb, pb
    local db = tbBtn(root, W - 44, y, 32, L("TB_BUY_DEL"), function() end)
    r.del = db.btn r.delText = db.text
    rows[i] = r
  end
  local empty = tbText(root, 10, 0.60, 0.58, 0.50)
  empty:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -46)
  empty:SetText(L("TB_BUY_EMPTY"))
  buyUI.empty = empty
  local hint = tbText(root, 9, 0.55, 0.60, 0.55)
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", 12, -(44 + TB_BUY_UI_ROWS * 18 + 6))
  hint:SetText(L("TB_BUY_HINT"))
  tbBtn(root, 12, -(H - 26), 84, L("TB_BUY_ADD"), function()
    if type(EVAL_TN_OPEN) ~= "function" then return end
    EVAL_TN_OPEN(L("TB_BUY_ASK_NAME"), "", function(txt)
      txt = string.gsub(txt or "", "^%s*(.-)%s*$", "%1")
      if txt == "" then return end
      local list = buyUIList()
      if not list then return end
      for _, w in ipairs(list) do
        if w.name == txt then say(string.format(L("TB_BUY_DUP"), txt)) return end
      end
      table.insert(list, { name = txt, n = 1, per = 1, on = true })
      buyUIRefresh() EVAL_TB_REFRESH()
    end)
  end)
  tbBtn(root, 102, -(H - 26), 62, L("TB_BUY_CLR"), function()
    local tb = tbCfg()
    if tb then tb.buy = {} end
    buyUIRefresh() EVAL_TB_REFRESH()
  end)
  tbBtn(root, W - 74, -(H - 26), 62, L("TB_BUY_CLOSE"), function() root:Hide() end)
  local up = tbBtn(root, W - 20, -44, 14, "^", function() buyUI.off = math.max(0, buyUI.off - 1) buyUIRefresh() end)
  local dn = tbBtn(root, W - 20, -(44 + (TB_BUY_UI_ROWS - 1) * 18), 14, "v", function() buyUI.off = buyUI.off + 1 buyUIRefresh() end)
  buyUI.up, buyUI.dn = up, dn
  local ind = tbText(root, 9, 0.65, 0.62, 0.50)
  ind:SetPoint("TOPRIGHT", root, "TOPRIGHT", -36, -46)
  buyUI.ind = ind
  root:Hide()
  buyUI.root = root
end

function EVAL_BUY_UI_OPEN()
  buyUIBuild()
  buyUI.off = 0
  buyUIRefresh()
  buyUI.root:Show()
end
function EVAL_BUY_UI_REFRESH() buyUIRefresh() end
function EVAL_BUY_UI_CLOSE() if buyUI.root then buyUI.root:Hide() end end

-- ★测试观测口：当前**可见**的列表行（读控件当前文本，而不是读配置）
function EVAL_TEST_BUY_UI_TEXTS()
  local out = {}
  if not buyUI.root then return out end
  local oks, shown = pcall(buyUI.root.IsShown, buyUI.root)
  if not (oks and shown) then return out end
  for i = 1, TB_BUY_UI_ROWS do
    local r = buyUI.rows[i]
    local okv, vis = pcall(r.chk.IsVisible, r.chk)
    if okv and vis then
      local okm, mvis = pcall(r.mark.IsShown, r.mark)
      table.insert(out, { on = (okm and mvis) and true or false, name = r.name:GetText() or "",
                          n = r.nt:GetText() or "", per = r.pt:GetText() or "" })
    end
  end
  return out
end
function EVAL_TEST_BUY_UI_SHOWN()
  if not buyUI.root then return false end
  local ok, shown = pcall(buyUI.root.IsShown, buyUI.root)
  return (ok and shown) and true or false
end
function EVAL_TEST_BUY_UI_CELL(i, which)
  local r = buyUI.rows and buyUI.rows[i]
  if not r then return nil end
  if which == "chk" then return r.chk end
  if which == "name" then return r.nameBtn end
  if which == "n" then return r.nBtn end
  if which == "per" then return r.pBtn end
  if which == "del" then return r.del end
  return nil
end
function EVAL_TEST_BUY_UI_OFF() buyUI.off = buyUI.off end


-- ===== 测试钩子（放在文件末尾） =====
-- ★1.71.2 把队列的**模块级时间戳**还原成干净值。
--   为什么必须有：tbQLast / tbMerchantLast / tbDiscardLast / tbQScanLast 都是跨调用累加的时间戳，
--   测试用例若把 TEST.time 推高后不复位，**后续用例**（从更早的绝对时间重放）会因
--   「now - last < 间隔」被误判成限频窗口内而静默不执行——现象是「断言莫名拿不到值」，排查成本很高
--   （本轮就在这里连着栽了两次）。用完即还，是本项目反复强调的纪律。
--   ★必须物理放在文件**末尾**：这些 local 的声明点分散在全文（tbMerchantLast 在 264、tbQScanDue 在 412…），
--     写在使用点之前会被 DECL ORDER CHECK 当场抓住（本轮实测：4 条 FAIL）。
-- ★★★1.73.9 断言入口：工具箱**滚动控件**（底部行）的真实几何
--   判据 = 与 [关闭] 中线对齐、按钮组停在关闭左边、计数文字与按钮组不重叠、且整行在列表下面。
function EVAL_TB_TEST_SCROLL()
  local function num(f, o) local ok, v = pcall(f, o) return (ok and type(v) == "number") and v or nil end
  local function txt(o)
    if not o or type(o.GetText) ~= "function" then return nil end
    local ok, v = pcall(o.GetText, o)
    return ok and tostring(v or "") or nil
  end
  local function shown(o)
    if not o then return false end
    local ok, v = pcall(o.IsShown, o)
    return (ok and v) and true or false
  end
  local function frame(o)
    if not o then return nil end
    return { x = num(o.GetLeft, o), y = num(o.GetTop, o), w = num(o.GetWidth, o), h = num(o.GetHeight, o), shown = shown(o) }
  end
  local up = TB.scrollUp and frame(TB.scrollUp.btn) or nil
  local dn = TB.scrollDn and frame(TB.scrollDn.btn) or nil
  if up then up.text = txt(TB.scrollUp.text) end
  if dn then dn.text = txt(TB.scrollDn.text) end
  local ind = nil
  if TB.indicator then
    ind = { x = num(TB.indicator.GetLeft, TB.indicator), y = num(TB.indicator.GetTop, TB.indicator),
            w = num(TB.indicator.GetWidth, TB.indicator), text = txt(TB.indicator), shown = shown(TB.indicator) }
  end
  return { midY = TB.botMidY, closeLeft = TB.closeLeft, up = up, dn = dn, indicator = ind,
           firstRowY = (TB.rows[1] and num(TB.rows[1].chk.GetTop, TB.rows[1].chk)) or nil }
end
function EVAL_TB_TEST_OFF() return TB.off end
-- 点滚动按钮走**真实 OnClick**（不在测试里复刻「off ± 1」的逻辑）
function EVAL_TB_TEST_SCROLL_CLICK(which)
  local b = (which == "up") and TB.scrollUp or TB.scrollDn
  if not (b and b.btn and type(b.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(b.btn.GetScript, b.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
function EVAL_TB_TEST_RESET_TIMERS()
  tbQLast, tbMerchantLast, tbDiscardLast = 0, 0, 0
  tbQScanLast, tbQScanDue = 0, 0
  -- ★新增状态必须一并纳入重置：少了这三行，前一个用例用掉的频率窗口会漏到下一个用例，
  --   表现为「第一次交接就被拦下」（本轮实测：断言 got=false）。
  --   判据：**凡是在文件里出现的模块级可变状态，都要在这个函数里有对应的一行**。
  tbQuestSeen, tbQuestBurst, tbQuestWinUntil = nil, nil, 0
  -- ★★1.71.2（第五轮）**上一轮快照也必须清**：
  --   tbQPrev 是「上次扫描结果」，跨用例残留会让新用例的第一次差分
  --   拿到一个**陈旧的对照组**（本轮实测：空名行早就在旧快照里 → "新增"判定永远不成立 → 断言假绿）。
  --   ★同上条判据：**凡模块级可变状态，都要在这个函数里有对应的一行**。
  tbQPrev = nil
  tbLastCompleteName = nil
end

-- ★1.71.2 只读查询：队列里还有几笔「任务交接」。
--   为什么断言需要它：只看最终效果（TEST.questAccepted 是否为 nil）**区分不了**
--   「事件根本没入队」和「入队后被队列闸门撤掉」——两种实现都能让断言通过，
--   于是「事件级闸门被删掉」的变异体照样存活（本轮实测 3 条全存活）。
--   ★判据：要验「按住时不入队」，就必须**直接问队列**。
-- ★1.71.2（第五轮）直接跑「扫描 + 差分 + 播报」真实路径。
--   用途：验「节点标题暂空时不会播出空白日志」——
--   这两个函数是 Toolbox.lua 的文件局部量，测试直调不到，只能靠导出桥。
--   ★一定要走**真实实现**，不能在测试里另写一份差分逻辑（本项目反复踩过）。
-- ★1.71.2 反向哨兵用：手工走**真实的 tbNotify** 发一条空名消息，
--   用于证明「空白日志检测器真的会响」——否则断言可能因为检测器本身失效而假绿。
function EVAL_TB_TEST_NOTIFY_EMPTY()
  local loc = EVAL_LOCALES[EVAL_GET_LANG()] or {}
  tbNotify(string.format(loc.TB_QN_ACCEPT or "%s", ""))
  return true
end
function EVAL_TB_TEST_SCAN_DIFF()
  tbQuestDiff()
  return true
end
function EVAL_TB_TEST_QUEUED_QUESTS()
  local n = 0
  for _, q in ipairs(tbQ) do if q.kind == "quest" then n = n + 1 end end
  return n
end
