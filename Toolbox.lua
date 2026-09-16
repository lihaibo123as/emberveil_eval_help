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
local function L(k)
  local lang = (type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function say(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

local function tbCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  if type(c.tb) ~= "table" then c.tb = {} end
  return c.tb
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

-- ===== 动作队列（1.68.2：商人/背包 API 限频 + 出售逐笔成功验证，防服务器反滥用踢线） =====
-- 教训背景：一帧内连续 24 次 UseContainerItem 会被服务器判定异常。所有写动作进队列，
-- OnUpdate 按 TB_RATE 间隔滴出；出售逐笔验证（下一拍核对槽位物品已消失，超时 2s 记失败）；
-- 执行前二次校验（槽位物品可能被玩家移动）；MERCHANT_HIDE 清空待售/待购（防「卖」变「用」）。
local TB_RATE = 0.3
local tbQ = {}
local tbQLast = 0
local tbPending = nil -- {bag,slot,name,t} 待验证的出售
local tbSellStat = nil -- {ok,fail} 本次扫描统计（队列清空时汇报）

local function tbQPush(q) table.insert(tbQ, q) end

local function tbVerifyPending()
  if not tbPending then return end
  local p = tbPending
  local now = (type(GetTime) == "function") and GetTime() or 0
  if tbItemName(p.bag, p.slot) ~= p.name then -- 槽位物品已消失/变更 → 卖出成功
    tbPending = nil
    if tbSellStat then tbSellStat.ok = tbSellStat.ok + 1 end
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
      tbPending = { bag = q.bag, slot = q.slot, name = q.name, t = now }
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
        if nm then tbQPush({ kind = "sell", bag = b, slot = s, name = nm }) n = n + 1 end
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

-- 事件统一入口（测试可直调）
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
    if tb and tb.quest and type(AcceptQuest) == "function" then pcall(AcceptQuest) end
  elseif e == "QUEST_PROGRESS" then
    local tb = tbCfg()
    if tb and tb.quest and type(IsQuestCompletable) == "function" and IsQuestCompletable() and type(CompleteQuest) == "function" then
      pcall(CompleteQuest)
    end
  elseif e == "QUEST_COMPLETE" then
    local tb = tbCfg()
    if tb and tb.quest and type(GetNumQuestChoices) == "function" and type(GetQuestReward) == "function" then
      local nc = GetNumQuestChoices() or 0
      if nc == 0 then pcall(GetQuestReward)
      elseif nc == 1 then pcall(GetQuestReward, 1) end -- 多奖励（>1）留给玩家手选
    end
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
evf:SetScript("OnEvent", function()
  local e = nil
  if type(event) == "string" then e = event end
  if not e and type(arg1) == "string" then e = arg1 end
  if not e and type(arg2) == "string" then e = arg2 end
  if e then EVAL_TB_ONEVENT(e) end
end)

-- 队列滴出帧：每帧检查一次（队空时仅一次表索引+一次 GetTime 比较，开销可忽略）
local qf = CreateFrame("Frame", "EVAL_TOOLBOX_QUEUE", UIParent)
qf:SetScript("OnUpdate", function() tbQPump() end)

-- ===== Tab 内容模型（分组归类；列表行动态展开） =====
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
    { t = "h", label = L("TB_H_QUEST") },
    { t = "c", key = "quest", label = L("TB_QUEST"), tip = L("TB_QUEST_TIP") },
  }
end

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
    r.chk:Hide() r.text:Hide() r.hdr:Hide() r.extra:Hide() r.add.btn:Hide() r.clr.btn:Hide()
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
