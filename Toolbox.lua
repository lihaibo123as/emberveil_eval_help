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
  return c.tb
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
    tbBagScan(function(b, s)
      local ok, tex, cnt, locked, q = pcall(GetContainerItemInfo, b, s)
      if ok and (tex or cnt) and q == 0 then
        local nm = tbItemName(b, s)
        if nm then tbQPush({ kind = "sell", bag = b, slot = s, name = nm, cnt = cnt or 1 }) n = n + 1 end
      end
    end)
    if n == 0 then tbSellStat = nil end
  end
  if tb.buyOn and type(tb.buy) == "table" and table.getn(tb.buy) > 0 and type(GetMerchantNumItems) == "function" then
    for _, w in ipairs(tb.buy) do
      local have = 0
      tbBagScan(function(b, s)
        if tbItemName(b, s) == w.name then
          local ok, tex, cnt = pcall(GetContainerItemInfo, b, s)
          if ok and type(cnt) == "number" then have = have + cnt end
        end
      end)
      local need = (w.n or 1) - have
      if need > 0 then
        local mn = GetMerchantNumItems() or 0
        for i = 1, mn do
          local ok, nm, tex, price, quant, avail = pcall(GetMerchantItemInfo, i)
          if ok and nm == w.name then
            if type(avail) == "number" and avail >= 0 and avail < need then need = avail end
            if need > 0 then
              tbQPush({ kind = "buy", idx = i, n = need }) -- 1.68.2 限频队列
              say(string.format(L("TB_BOUGHT"), w.name, need))
            end
            break
          end
        end
      end
    end
  end
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
evf:SetScript("OnEvent", function()
  local e = nil
  if type(event) == "string" then e = event end
  if not e and type(arg1) == "string" then e = arg1 end
  if not e and type(arg2) == "string" then e = arg2 end
  if e then EVAL_TB_ONEVENT(e) end
end)

-- 队列滴出帧：每帧检查一次（队空时仅一次表索引+一次 GetTime 比较，开销可忽略）
local qf = CreateFrame("Frame", "EVAL_TOOLBOX_QUEUE", UIParent)
qf:SetScript("OnUpdate", function() tbQuestTick() tbQPump() end) -- 1.69.2 任务延迟扫描 + 队列滴出

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
      table.insert(tb.buy, { name = nm, n = tonumber(n) or 1 })
    else
      table.insert(tb.buy, { name = txt, n = 1 })
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
    for _, w in ipairs(tb.buy) do table.insert(parts, tostring(w.name) .. "×" .. tostring(w.n or 1)) end
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
            if type(EVAL_TN_OPEN) == "function" then
              EVAL_TN_OPEN(it.ask, "", function(txt) tbAddItem(it.key, txt) EVAL_TB_REFRESH() end)
            end
          end)
          r.clr.btn:SetScript("OnClick", function()
            local tb = tbCfg()
            if tb then tb[it.key] = {} end
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

  -- 滚动：[▲][▼] + 滚轮（滚轮挂配置窗 root，仅 Tab3 响应）
  TB.scrollUp = tbBtn(root, RW - 14, -50, 16, "▲", function()
    TB.off = math.max(0, TB.off - 1)
    EVAL_TB_REFRESH()
  end, widgets)
  TB.scrollDn = tbBtn(root, RW - 14, -56 - (TB.ROWS - 1) * ROWH - 20, 16, "▼", function()
    TB.off = TB.off + 1
    EVAL_TB_REFRESH()
  end, widgets)
  local ind = tbText(root, 9, 0.65, 0.62, 0.50)
  ind:SetPoint("TOPRIGHT", root, "TOPRIGHT", -20, -56 - TB.ROWS * ROWH - 8)
  TB.indicator = ind
  table.insert(widgets, ind)
  pcall(root.EnableMouseWheel, root, true)
  root:SetScript("OnMouseWheel", function()
    -- 仅 Tab3 可见时响应（widgets 显隐契约：非本 Tab 全部 Hide，首行组标题必然隐藏）
    if not (TB.rows[1] and TB.rows[1].hdr:IsVisible()) then return end
    local d = arg1 or 0
    TB.off = math.max(0, TB.off - d)
    EVAL_TB_REFRESH()
  end)

  TB.built = true
  EVAL_TB_REFRESH()
end

-- ===== 测试钩子（放在文件末尾） =====
-- ★1.71.2 把队列的**模块级时间戳**还原成干净值。
--   为什么必须有：tbQLast / tbMerchantLast / tbDiscardLast / tbQScanLast 都是跨调用累加的时间戳，
--   测试用例若把 TEST.time 推高后不复位，**后续用例**（从更早的绝对时间重放）会因
--   「now - last < 间隔」被误判成限频窗口内而静默不执行——现象是「断言莫名拿不到值」，排查成本很高
--   （本轮就在这里连着栽了两次）。用完即还，是本项目反复强调的纪律。
--   ★必须物理放在文件**末尾**：这些 local 的声明点分散在全文（tbMerchantLast 在 264、tbQScanDue 在 412…），
--     写在使用点之前会被 DECL ORDER CHECK 当场抓住（本轮实测：4 条 FAIL）。
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
