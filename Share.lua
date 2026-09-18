-- EvalHelp · Share.lua —— 方案分享（1.71.0 独立载入：聊天频道分片传输 + 事件扫描接收 + 弹窗导入）
-- 可行性结论（调研定案）：
--   发送：SendChatMessage 是 Protected → RunScript 聊天脚本队列绕行（1.49.3 已验证范式，视同玩家手输 /script）
--   传输：hex 编码防聊天系统吃掉 |、"、链接符；220 hex 字符/片（原始 110B），头部 ~20B，总 < 255B 消息上限
--   接收：CHAT_MSG_* 事件扫描（免疫学习器 1.36.0 同款通道），按 发送者+id 缓存分片，收齐弹窗
--   点击：弹窗是自家按钮（规避 SetItemRef 是否存在的未知数）——用户点 [导入] 才导入
-- 依赖仅全局件：EVAL_SAY / EVAL_DD_OPEN / EVAL_IMPORT_TEXT（EvalHelp 桥）/ EVAL_PROFILE_TO_TEXT

local SH = { buf = {}, done = {}, doneList = {} }  -- doneList=去重表的插入序（1.71.3 R6 上限淘汰用）
local SH_CHUNK = 220 -- 每片 hex 字符数

-- ===== 基础工具（文件独立：不依赖 Toolbox/EvalHelp 的 local 件） =====
local function shSay(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

local function L(k)
  local lang = (type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function shSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function shText(parent, size, r, g, b)
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

-- ===== 配置（接收开关，默认开） =====
local function shCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return { recv = true } end -- 未加载完成时按默认
  if type(c.share) ~= "table" then c.share = { recv = true } end
  if c.share.recv == nil then c.share.recv = true end
  return c.share
end

function EVAL_SHARE_RECV_ON()
  return shCfg().recv and true or false
end

function EVAL_SHARE_RECV_TOGGLE()
  local c = shCfg()
  c.recv = not c.recv
  shSay(L("SH_RECV_" .. (c.recv and "ON" or "OFF")))
  return c.recv
end

-- ===== hex 编解码（hex 切片不会劈开多字节汉字） =====
local function toHex(s)
  return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function fromHex(h)
  if type(h) ~= "string" or string.len(h) == 0 or math.mod(string.len(h), 2) ~= 0 then return nil end
  if string.find(h, "[^0-9a-fA-F]") then return nil end
  return (string.gsub(h, "..", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- ===== 发送侧 =====
-- 频道有效性预检（不在该频道时 SendChatMessage 静默失败，提前提示）
-- ★1.71.3 用户实测决定：**团队（RAID）频道从分享里下线**——
--   原话「插件分享. 好像团队模式无法检测到.」→「不要团队模式发送了.」
--   ★为什么是删掉而不是去修：1.12 系客户端里**队长**发的队伍/团队聊天走 CHAT_MSG_*_LEADER 独立事件
--     （我们只注册了 CHAT_MSG_PARTY / CHAT_MSG_RAID），队长一分享，接收端就永远收不到——
--     而且失败是**静默**的：发送方还会照样提示「已发送 N 片」。与其留一个「看着能选、实际没人收到」的
--     频道，不如去掉。发送侧只保留 公会 / 队伍 / 说（接收侧事件注册保持原样：老版本往团队发的照样收）。
local SH_CHANS = {
  { id = "GUILD", name = function() return L("SH_CH_GUILD") end, ok = function() return type(IsInGuild) == "function" and IsInGuild() end },
  { id = "PARTY", name = function() return L("SH_CH_PARTY") end, ok = function() return type(GetNumPartyMembers) == "function" and (GetNumPartyMembers() or 0) > 0 end },
  { id = "SAY",   name = function() return L("SH_CH_SAY") end,   ok = function() return true end },
}


-- 1.71.3 频道白名单（单一真值）：下面这张表就是**唯一**来源 → 直接调 EVAL_SHARE_SEND(公会以外的旧频道) 也会被拒，
-- 不允许「界面上没有、代码里还能发」。
local function shChanOf(id)
  for _, c in ipairs(SH_CHANS) do if c.id == id then return c end end
  return nil
end
-- ★★★1.72.3 发送限频队列（修「长方案对方偶尔收不到」）
--   【用户实测】方案长到 4 片时对方有时收不到；短方案（1 片）从不出问题。
--   【根因】原实现把分片在**一个 for 循环里连着 RunScript** 发出去（同一帧 4 条 SendChatMessage）
--     → 撞客户端/服务器的反刷屏限流，被吞掉的那一片让接收端**永远收不齐**。
--   ★这正是本项目记忆体里写明的铁律：「RunScript 本身也是队列，**连发聊天同样会被反滥用踢线**，
--     通知类输出也要入限频队列」——分享发送当时没遵守。
--   【修法】第 1 片立即发（手感不变），其余进 FIFO，由 OnUpdate 每 SH_SEND_RATE 秒滴一片；
--     队列上限 SH_MAX_QUEUE 防失控（超出如实取消）。
local SH_SEND_RATE = 0.35 -- 相邻两片之间的最小间隔（秒）
local SH_MAX_QUEUE = 200  -- 发送队列上限（条）
local shTxQ, shTxLast = {}, 0
local shTxFrame
-- ★前置声明（本项目铁律：引用点在声明之前会解析成全局 nil）——
--   实现在 shNowT 之后，那里才拿得到计时函数。
local shTxEnqueue, shTxStep
function EVAL_SHARE_SEND(chanId)
  if not shChanOf(chanId) then shSay(L("SH_CH_OFF")) return false end -- 1.71.3 团队频道已下线，白名单外一律拒收
  if type(EVAL_PROFILE_TO_TEXT) ~= "function" then shSay(L("SH_NOEXPORT")) return false end
  if type(RunScript) ~= "function" then shSay(L("SH_NORUNSCRIPT")) return false end
  local text = EVAL_PROFILE_TO_TEXT()
  if not text or text == "" then shSay(L("SH_EMPTY")) return false end
  local hex = toHex(text)
  local n = math.ceil(string.len(hex) / SH_CHUNK)
  local idh = string.format("%02x", math.random(0, 255)) -- 本次传输 id（接收端按 发送者+id 归并分片）
  local bodies = {}
  for i = 1, n do
    bodies[i] = "[EHPF#" .. idh .. " " .. i .. "/" .. n .. "]" .. string.sub(hex, (i - 1) * SH_CHUNK + 1, i * SH_CHUNK)
  end
  -- ★1.72.3 分片必须**限频发送**（同帧连发会被反刷屏吞掉 → 对方永远收不齐）
  return shTxEnqueue(bodies, chanId) -- 队列满时如实返回 false（并已 shSay 说明）
end

-- IO 窗 [分享] 按钮：频道下拉
function EVAL_SHARE_SEND_UI(anchor)
  if type(EVAL_DD_OPEN) ~= "function" then EVAL_SHARE_SEND("GUILD") return end
  local items, ids = {}, {}
  for _, c in ipairs(SH_CHANS) do
    table.insert(items, c.name())
    table.insert(ids, c.id)
  end
  EVAL_DD_OPEN(anchor, items, function(pi)
    local c = SH_CHANS[pi]
    if not c then return end
    if not c.ok() then shSay(L("SH_CH_NO")) return end
    EVAL_SHARE_SEND(c.id)
  end)
end

-- ===== 接收侧：事件扫描 + 分片缓存 + 收齐弹窗 =====
-- ★1.71.3 接收规则优化（用户要求：「优化接收端的接收数据规则. 在多个分享同时出现的时候只显示最新的数据，
--   防止有些人滥发，或者多人发送接收异常.」）
--   规则一览（每条都「如实告知 + 限频」）：
--   R1 **只保留最新一份**：收齐的新分享直接**替换**当前待导入的那份（同一个弹窗、单一数据槽，不叠加）
--      ——「最新」按**收齐时刻**算；被替换掉的那份如实说一句（谁取代了谁）。
--   R2 **同一发送者开始新的一笔 → 他旧的未收齐缓冲立刻作废**（连点两次分享时，旧那笔只到一半就丢弃）。
--      ★只按「发送者」作废旧笔，**绝不跨发送者**：不同人同时发时两边的分片会交错到达，
--        若互相作废（我第一版的想法）会**两边都收不齐**，比不做还糟。
--   R3 **在途传输笔数上限** SH_MAX_BUF：超出时丢弃最久未活动的一笔（多人同时发 / 滥发的兜底）。
--   R4 **单笔分片数上限** SH_MAX_CHUNKS：整笔拒收（防伪造「1/9999」这种超大包）。
--   R5 **单笔解码上限** SH_MAX_TEXT：整笔拒收（防超长内容）。
--   R6 **去重表上限** SH_MAX_DONE：按插入序丢最旧（防无限增长）。
--   R7 **接收侧提示统一限频** SH_WARN_GAP：窗口内只报一次，并在下一次真正报出时告知「另有 N 条已省略」。
--      ★为什么连我们自己的提示也要限频：提示同样是聊天消息——**滥发者能让我们的提示刷屏**。
--      ★限频的是「说不说」，**不是「拦不拦」**：数据侧的拒收/替换一律照常执行（绝不因为限频而静默放过）。
local SH_BUF_TIMEOUT = 60   -- 在途传输超时（秒）
local SH_MAX_BUF = 4        -- 同时在途的传输笔数上限
local SH_MAX_CHUNKS = 40    -- 单笔分享的最大分片数（合法方案远小于此）
local SH_MAX_TEXT = 8192    -- 单笔分享解码后的最大字节数
local SH_MAX_DONE = 64      -- 去重表保留条数上限
local SH_WARN_GAP = 5       -- 接收侧提示的最短间隔（秒）

local function shNowT()
  return (type(GetTime) == "function") and GetTime() or 0
end

local shWarnLast, shWarnSkip = 0, 0
-- 限频提示：窗口内静默累计条数，下一次真正报出时把「省略了几条」一并说出（绝不静默丢弃）
local function shWarn(msg)
  shWarnSkip = shWarnSkip + 1
  local now = shNowT()
  if now - shWarnLast < SH_WARN_GAP then return end
  local skip = shWarnSkip - 1
  shWarnLast, shWarnSkip = now, 0
  shSay(msg .. ((skip > 0) and string.format(L("SH_WARN_MORE"), skip) or ""))
end

-- ★1.72.3 发送队列实现（实现在这里，因为要用上面的 shNowT）
function shTxStep()
  if table.getn(shTxQ) == 0 then
    if shTxFrame then pcall(shTxFrame.Hide, shTxFrame) end
    return
  end
  local now = shNowT()
  if now - shTxLast < SH_SEND_RATE then return end -- ★限频：到点才滴下一片
  shTxLast = now
  local job = table.remove(shTxQ, 1)
  if type(RunScript) == "function" then
    RunScript('SendChatMessage("' .. job.body .. '", "' .. job.chan .. '")')
  end
  if table.getn(shTxQ) == 0 and shTxFrame then pcall(shTxFrame.Hide, shTxFrame) end
end
local function shEnsureTxTicker()
  if not shTxFrame then
    shTxFrame = CreateFrame("Frame", "EVAL_SHARE_TX", UIParent)
    shTxFrame:SetScript("OnUpdate", shTxStep)
  end
  pcall(shTxFrame.Show, shTxFrame)
end
function shTxEnqueue(bodies, chanId)
  local n = table.getn(bodies)
  if table.getn(shTxQ) + n > SH_MAX_QUEUE then
    shSay(string.format(L("SH_Q_FULL"), SH_MAX_QUEUE))
    return false
  end
  -- 第 1 片立即发（手感与旧版一致），其余排队
  RunScript('SendChatMessage("' .. bodies[1] .. '", "' .. chanId .. '")')
  for i = 2, n do table.insert(shTxQ, { body = bodies[i], chan = chanId }) end
  if n > 1 then
    shTxLast = shNowT()
    shEnsureTxTicker()
    shSay(string.format(L("SH_QUEUED"), n, (n - 1) * SH_SEND_RATE))
  else
    shSay(string.format(L("SH_SENT"), n))
  end
  return true
end
-- ★测试直调：驱动与 OnUpdate **同一个**函数（判据必须落在真实调用点/真实闭包上）
function EVAL_SHARE_TEST_TICK() shTxStep() end
function EVAL_SHARE_TEST_QUEUE_LEN() return table.getn(shTxQ) end-- ★1.72.3 **收不齐绝不静默**：超时丢弃在途传输时如实报出「谁发的、收了几片」。
--   【为什么必须说】旧实现到点直接 SH.buf[k] = nil —— 接收方只看到「什么都没发生」，
--     发送方也永远不知道（用户报的「对方有时候接收不到」正是这个静默态）。
local function shSweepBuf(now)
  for k, b in pairs(SH.buf) do
    if now - b.t > SH_BUF_TIMEOUT then
      SH.buf[k] = nil
      shWarn(string.format(L("SH_RECV_PARTIAL"), tostring(b.from or "?"), b.got or 0, b.n or 0))
    end
  end
end
-- R3：在途笔数超上限 → 丢最久未活动的一笔（如实提示）
local function shTrimBuf()
  local cnt, oldK, oldT = 0, nil, nil
  for k, b in pairs(SH.buf) do
    cnt = cnt + 1
    if (oldT == nil) or (b.t < oldT) then oldK, oldT = k, b.t end
  end
  if cnt > SH_MAX_BUF and oldK then
    SH.buf[oldK] = nil
    shWarn(string.format(L("SH_DROP_MANY"), SH_MAX_BUF))
  end
end

-- R2：同一发送者开始新的一笔 → 他旧的未收齐缓冲作废（只看前缀，不走模式串，名字里有特殊字符也安全）
local function shDropSenderBufs(sender, keepKey)
  local pre = sender .. "#"
  local pl = string.len(pre)
  for k in pairs(SH.buf) do
    if k ~= keepKey and string.sub(k, 1, pl) == pre then SH.buf[k] = nil end
  end
end

-- R6：去重表按插入序丢最旧（doneList 只记顺序，真值仍在 done 里）
local function shMarkDone(key)
  SH.done[key] = true
  table.insert(SH.doneList, key)
  while table.getn(SH.doneList) > SH_MAX_DONE do
    local old = table.remove(SH.doneList, 1)
    SH.done[old] = nil
  end
end

-- ★1.71.3 收到分享时标出**来源频道**（用户要求：「能否辨别是否是公会来源」）。
--   判据就是**触发的那个事件名**（我们本来就按频道分别注册了事件）——比拿消息文本去猜可靠得多。
--   ★队长/团长的聊天走 *_LEADER 事件，一并归类（接收侧不能把队长当成野人）。
function EVAL_SHARE_CHAN_LABEL(ev)
  if type(ev) ~= "string" then return nil end
  if ev == "CHAT_MSG_GUILD" then return L("SH_CH_GUILD") end
  if ev == "CHAT_MSG_PARTY" or ev == "CHAT_MSG_PARTY_LEADER" then return L("SH_CH_PARTY") end
  if ev == "CHAT_MSG_RAID" or ev == "CHAT_MSG_RAID_LEADER" or ev == "CHAT_MSG_RAID_WARNING" then return L("SH_CH_RAID") end
  if ev == "CHAT_MSG_SAY" then return L("SH_CH_SAY") end
  if ev == "CHAT_MSG_WHISPER" then return L("SH_CH_WHISPER") end
  return nil -- 认不出来就**不标**（不瞎猜一个来源）
end

-- msg/sender 来自事件；ev = 触发的事件名（可缺：测试直调时为 nil）
-- ★1.71.3 这条分享内容是不是**我自己的方案**（用户要求：非「说」来源的自我回声直接忽略）。
--   判据：解析出来同名 → 把我的那份**序列化后逐字比对**（只比名字会误伤「同名不同内容」）。
function EVAL_SHARE_IS_MINE(text)
  if type(text) ~= "string" or text == "" then return false end
  if type(EVAL_PROFILE_FROM_TEXT) ~= "function" or type(EVAL_PROFILE_TO_TEXT) ~= "function" then return false end
  local prof = EVAL_PROFILE_FROM_TEXT(text)
  if type(prof) ~= "table" then return false end
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local list = (type(c) == "table" and type(c.war) == "table") and c.war.profiles or nil
  if type(list) ~= "table" then return false end
  local function norm(s) return (string.gsub(tostring(s or ""), "%s+", "")) end
  local want = norm(text)
  for i, p in ipairs(list) do
    if type(p) == "table" and tostring(p.name) == tostring(prof.name) then
      local ok, mine = pcall(EVAL_PROFILE_TO_TEXT, p)
      if not (ok and type(mine) == "string") then ok, mine = pcall(EVAL_PROFILE_TO_TEXT, i) end
      if ok and type(mine) == "string" and norm(mine) == want then return true end
    end
  end
  return false
end

-- ★1.71.3 公会来源的分享：点按钮时在**公会频道**玩一句（用户指定的两句话）。
--   ★只在「触发事件是 CHAT_MSG_GUILD」且**真的在公会里**时才发（公会聊天 SendChatMessage 是 Protected → 走 RunScript，同分享发送）。
--   ★发不出去就返回 false（不假装发了）。
local function shGuildFun(fmtKey)
  local p = SH.pending
  if not p then return false end
  if p.ev ~= "CHAT_MSG_GUILD" then return false end
  if type(IsInGuild) == "function" then
    local okg, ing = pcall(IsInGuild)
    if okg and not ing then return false end
  end
  local txt = string.format(L(fmtKey), tostring(p.sender), tostring(p.name))
  if type(RunScript) ~= "function" then return false end
  pcall(RunScript, string.format("SendChatMessage(%q, %q)", txt, "GUILD"))
  EVAL_LOGLINE("[分享] 已在公会频道发送：" .. txt)
  return true
end

-- msg/sender 来自事件；ev = 触发的事件名（可缺：测试直调时为 nil）
local function shOnMsg(msg, sender, ev)
  if type(msg) ~= "string" then return end
  local idh, i, n, payload = string.match(msg, "^%[EHPF#(%x+) (%d+)/(%d+)%](%x*)$")
  if not idh then return end
  if not shCfg().recv then return end
  i, n = tonumber(i), tonumber(n)
  if not i or not n or n < 1 or i < 1 or i > n then return end -- 防异常包（非数字 / 索引越界）
  if n > SH_MAX_CHUNKS then shWarn(string.format(L("SH_DROP_BIG"), n, SH_MAX_CHUNKS)) return end -- R4
  sender = tostring(sender or "?")
  local now = shNowT()
  shSweepBuf(now)
  local key = sender .. "#" .. idh
  local b = SH.buf[key]
  if not b then
    shDropSenderBufs(sender, key) -- R2
    b = { n = n, chunks = {}, got = 0, t = now, ev = ev, from = sender } -- ★1.72.3 记住谁发的（收不齐时要如实点名）
    SH.buf[key] = b
    shTrimBuf() -- R3
  end
  b.t = now
  if not b.chunks[i] then
    b.chunks[i] = payload
    b.got = b.got + 1
  end
  if b.got >= b.n then
    SH.buf[key] = nil
    if SH.done[key] then return end -- 同一笔重复收齐不重复弹
    shMarkDone(key)
    local parts = {}
    for j = 1, b.n do parts[j] = b.chunks[j] or "" end
    local text = fromHex(table.concat(parts))
    if not text then return end
    if string.len(text) > SH_MAX_TEXT then -- R5
      shWarn(string.format(L("SH_DROP_BIGTEXT"), string.len(text), SH_MAX_TEXT))
      return
    end
    -- ★1.71.3 用户要求：**不是「说」来源** 且内容就是**我自己的方案** → 直接忽略
    --   （自己往公会/队伍/团队发分享时，客户端会把分片**回声给自己**，不忽略就会自己弹自己的窗）。
    --   ★先确认「知道来源」（b.ev 非空）：认不出来时照旧弹出——宁可多弹一次，也不误吞真分享。
    if b.ev and b.ev ~= "CHAT_MSG_SAY" and EVAL_SHARE_IS_MINE(text) then
      SH.selfSkipped = (SH.selfSkipped or 0) + 1
      EVAL_LOGLINE("[分享] 已忽略（自己的方案回声）：来源=" .. tostring(b.ev or "?") .. " 发送者=" .. tostring(sender))
      return
    end
    -- R1：只保留最新一份 —— 弹窗内容换成最新的，并如实说明替换了谁
    local old = SH.pending
    EVAL_SH_POPUP(sender, text, b.ev)
    if old then shWarn(string.format(L("SH_POP_REPLACED"), tostring(sender), tostring(old.sender))) end
  end
end

function EVAL_SHARE_ONMSG(msg, sender, ev) shOnMsg(msg, sender, ev) end -- 测试直调（ev 可缺）

-- ★1.71.3 事件分派（三态兼容）抽成函数：事件名在 1参 / 2参 / 全局 event，参数随之一档右移。
--   ★抽出来的理由：断言要验的是**真实分派逻辑**（不能在测试里重写一遍）。
function EVAL_SHARE_DISPATCH(ev, a1, a2, a3, a4)
  if type(ev) == "string" then return ev, a1, a2 end
  if type(a1) == "string" and string.find(a1, "^CHAT_MSG_") then return a1, a2, a3 end
  return nil, a3, a4
end

-- 聊天事件帧（三态兼容：事件名在 1参/2参/全局 event；参数随之一档右移）
local shf = CreateFrame("Frame", "EVAL_SHARE_EVENTS", UIParent)
shf:RegisterEvent("CHAT_MSG_GUILD")
shf:RegisterEvent("CHAT_MSG_PARTY")
shf:RegisterEvent("CHAT_MSG_RAID")
shf:RegisterEvent("CHAT_MSG_SAY")
shf:RegisterEvent("CHAT_MSG_WHISPER")
shf:SetScript("OnEvent", function()
  local ev, msg, sender = EVAL_SHARE_DISPATCH(event, arg1, arg2, arg3, arg4)
  shOnMsg(msg, sender, ev)
end)

-- ===== 接收弹窗（自绘；点 [导入] 走 EVAL_IMPORT_TEXT 桥） =====
local shp = {}
-- ★1.71.2 弹窗最多显示几行方案详情（超出折叠为「…还有 N 行」）。
--   为什么要有上限：方案最多 12 技能 × 每行可能很长的条件串，弹窗不能无限增高。
local SH_DETAIL_MAX = 6
-- ★1.71.3 弹窗图标（自包含：这批 .tga 已从 UnrealQuest 拷进本插件 media\icons\）与标题栏高度
local SH_POP_ICON = "Interface\\AddOns\\EvalHelp\\media\\icons\\trainers-icon"
local SH_TITLE_H = 18

local function shPopupBuild()
  if shp.root then return end
  -- ★1.71.2 高度 130 → 200：要容纳「标题 + 6 行方案详情 + 按钮行」。
  --   算一遍：标题在 -10、详情首行 -52、6 行 × 12 = 至 -124、按钮行占底部 34 → 需要约 170，
  --   留余量取 200（长条件串还会占更宽，但不增高）。
  local W, H = 380, 200
  local root = CreateFrame("Frame", "EVAL_SHARE_POPUP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 140) -- 高于名称输入弹窗(130)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if type(EVAL_UIOFFSCREEN) == "function" and EVAL_UIOFFSCREEN(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  -- ★1.71.3 用户要求「根据新加的图标美化一下」：标题栏（底色条 + 左侧图标）+ 详情区下沉底板。
  local tbBg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  tbBg:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  tbBg:SetHeight(SH_TITLE_H)
  local title = shText(root, 11, 0.95, 0.82, 0.35)
  title:SetPoint("TOP", root, "TOP", 0, -10)
  title:SetText(L("SH_POP_T"))
  -- 标题左侧的图标：★标题是居中锚的，图标贴它左边（不参与居中计算，长标题也不会挤歪它）
  local tIcon = root:CreateTexture(nil, "ARTWORK")
  pcall(tIcon.SetTexture, tIcon, SH_POP_ICON)
  tIcon:SetWidth(14) tIcon:SetHeight(14)
  tIcon:SetPoint("RIGHT", title, "LEFT", -5, 0)
  shp.titleIcon = tIcon
  -- 详情区下沉底板 + 按钮上方的分隔线（观感分层，与配置窗同一套配色）
  local dPanel = root:CreateTexture(nil, "BACKGROUND")
  shSolid(dPanel, 0.02, 0.02, 0.02, 0.85)
  dPanel:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -46)
  dPanel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 44)
  local bSep = root:CreateTexture(nil, "BORDER")
  shSolid(bSep, 0.45, 0.38, 0.16, 1)
  bSep:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 10, 42)
  bSep:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 42)
  bSep:SetHeight(1)
  local body = shText(root, 10, 0.92, 0.88, 0.80)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -34)
  pcall(body.SetWidth, body, W - 32)
  pcall(body.SetJustifyH, body, "LEFT")
  pcall(body.SetNonSpaceWrap, body, false) -- 不允许换行：过长的条件串宁可裁掉，也不要把行数搞乱
  shp.body = body
  -- ★1.71.2 用户要求：「在接收到方案分享的弹窗内，将方案的详细信息也显示」。
  --   原来只显示一行「XX 分享了《方案名》(N 个技能)」，用户看不到**具体有哪些技能/条件**，
  --   必须点导入进配置窗才知道内容。
  --   ★实现方式：按行显示（每条技能一个 FontString），而不是塞进一个多行 FontString——
  --     本客户端的多行 FontString 行高/换行行为不稳（本项目既有记录），逐行独立控件最可靠，
  --     也便于「最多显示 N 行」的裁剪与断言。
  shp.detailLines = {}
  for i = 1, SH_DETAIL_MAX do
    local fs = shText(root, 9, 0.80, 0.78, 0.70)
    fs:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -52 - (i - 1) * 12)
    pcall(fs.SetWidth, fs, W - 32)
    pcall(fs.SetJustifyH, fs, "LEFT")
    pcall(fs.SetNonSpaceWrap, fs, false)
    fs:Hide()
    -- ★注意：本弹窗是**独立弹窗**，不参与配置窗的 Tab 显隐契约，故没有 widgets 表可插。
    --   （误抄 EvalHelp.lua 的 page.widgets 写法会直接报 nil —— 本轮已避免。）
    shp.detailLines[i] = fs
  end
  -- ★1.71.3 用户要求「按钮位置居中对齐下」：两个按钮**整组以窗口中线对齐**。
  --   算一遍：90 + 14 + 90 = 194 → 左起点 = floor((W-194)/2)（W=380 → 93，两个按钮 93/197）。
  --   ★宽与间距是**单一来源**（BTN_W/BTN_GAP），按钮本体也用 BTN_W——两处各写一遍迟早漂移。
  local BTN_W, BTN_GAP = 90, 14
  local btnX1 = math.floor((W - (BTN_W * 2 + BTN_GAP)) / 2)
  local btnX2 = btnX1 + BTN_W + BTN_GAP
  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(BTN_W) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    shSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = shText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  local importBtn = bBtn(btnX1, L("SH_IMPORT"), function()
    local p = SH.pending
    if not p then shp.root:Hide() return end
    if type(EVAL_IMPORT_TEXT) == "function" then
      local ok, msg = EVAL_IMPORT_TEXT(p.text)
      shSay(tostring(msg))
      if ok then
        shGuildFun("SH_FUN_IMPORT") -- 公会来源：点「导入/确认」在公会频道玩另一句（用户指定）
        shp.root:Hide()
        SH.pending = nil
      end
    else
      shSay(L("SH_NOIMPORT"))
    end
  end)
  local ignoreBtn = bBtn(btnX2, L("SH_IGNORE"), function()
    shGuildFun("SH_FUN_IGNORE") -- 公会来源：点「忽略」在公会频道玩一句（用户指定）
    shp.root:Hide()
    SH.pending = nil
  end)
  shp.ignoreBtn = ignoreBtn
  shp.importBtn = importBtn -- ★1.71.2 供断言走**真实按钮**（否则只能直调导入函数，绕过了出问题的路径）
  root:Hide()
  shp.root = root
end

function EVAL_SH_POPUP(sender, text, ev)
  shPopupBuild()
  -- 预览解析（只读不导入）：拿方案名与技能数
  local name, count = "?", 0
  if type(EVAL_PROFILE_FROM_TEXT) == "function" then
    local prof = EVAL_PROFILE_FROM_TEXT(text)
    if prof then name = tostring(prof.name) count = table.getn(prof.skills or {}) end
  end
  local chanLab = EVAL_SHARE_CHAN_LABEL(ev)
  SH.pending = { sender = sender, text = text, name = name, count = count, chan = chanLab, ev = ev }
  local showFrom = chanLab and ("[" .. chanLab .. "] " .. tostring(sender)) or tostring(sender)
  shp.body:SetText(string.format(L("SH_POP_GOT"), showFrom, name, count))
  -- ★1.71.2 详情：把导入文本按行显示，让用户在**点导入之前**就能看清内容。
  --   用**逐个 FontString** 而非一个多行 FontString（本客户端多行行为不稳，逐行最可靠）。
  --   最多 SH_DETAIL_MAX 行，超出时最后一行提示还剩多少（不静默截断——诚实告知）。
  if shp.detailLines then
    local lines = {}
    for ln in string.gmatch(text or "", "[^\r\n]+") do table.insert(lines, ln) end
    local shown, total = 0, table.getn(lines)
    for i = 1, SH_DETAIL_MAX do
      local fs = shp.detailLines[i]
      if fs then
        local l = lines[i]
        if l then
          fs:SetText(l)
          fs:Show()
          shown = i
        else
          -- ★1.71.3 先**清空文本**再 Hide：本客户端 Hide 过的控件仍可能被绘出（「黑块」那轮的教训），
          --   只 Hide 不清空 → 上一份分享的残留行还挂在屏幕上（正是「只显示最新数据」要消灭的东西）。
          fs:SetText("")
          fs:Hide()
        end
      end
    end
    -- 超出部分：复用最后一行显示「…还有 N 行」
    if total > SH_DETAIL_MAX and shp.detailLines[SH_DETAIL_MAX] then
      shp.detailLines[SH_DETAIL_MAX]:SetText(string.format(L("SH_POP_MORE"), total - SH_DETAIL_MAX + 1))
      shp.detailLines[SH_DETAIL_MAX]:Show()
    end
  end
  shp.root:Show()
end

-- ★1.71.2（第十六轮）**删除 EVAL_SHARE_RECV_LABEL**（原先在这里）。
--   它唯一的作用是刷新那个「接收:开/关」按钮的文字，而那个按钮本轮已被用户要求删掉
--   （它与开关组的「接收方案」是同一个开关）→ 调用点归零，成为**孤儿函数**。
--   ★为什么必须删而不是留着：本项目刚刚才吃到一次「留着一份描述旧状态的代码」的亏
--     （见 EvalHelp.lua 里那段 `cfgWin.nav = nil` 的残留：按钮真的建了、登记却被清空，
--       而读它的测试钩子无人调用 → 整整几轮没人发现）。孤儿代码会让人以为「这块还有功能」。
--   ★若将来又需要「在某个按钮上显示接收开关状态」，照下面两行重写即可：
--     EVAL_SHARE_RECV_ON() 读当前值；文字用 string.format(L("SH_RECV"), L("SH_ON"/"SH_OFF"))。

-- ★1.71.2 测试钩子：弹窗**当前实际显示**的文本（标题行 + 详情行）。
--   用途：验「详情真的填进去了」。★必须读控件当前文本（走真实渲染），
--   不能只断言 SH.pending.text 里有内容——那是数据侧，与「有没有显示」是两件事。
function EVAL_TEST_SHARE_POPUP_TEXTS()
  local t = {}
  if shp.body then
    local okb, tb = pcall(shp.body.GetText, shp.body)
    if okb and type(tb) == "string" and tb ~= "" then table.insert(t, tb) end
  end
  for _, fs in ipairs(shp.detailLines or {}) do
    local okS, shown = pcall(fs.IsShown, fs)
    if okS and shown then
      local okt, txt = pcall(fs.GetText, fs)
      if okt and type(txt) == "string" and txt ~= "" then table.insert(t, txt) end
    end
  end
  return t
end

-- 测试观察口
-- ★1.71.3 接收规则的测试观测口：在途笔数 / 去重表条数 / **生产代码真用的上限值**
--   ★上限值必须从生产代码读（断言里写死常量 = 测试在测自己，本项目已踩过）。
function EVAL_TEST_SHARE_BUF_COUNT()
  local c = 0
  for _ in pairs(SH.buf) do c = c + 1 end
  return c
end
function EVAL_TEST_SHARE_DONE_COUNT()
  local c = 0
  for _ in pairs(SH.done) do c = c + 1 end
  return c
end
-- 也回调提示限频器的状态（断言需要在用例之间重置它，避免跨用例残留）
function EVAL_TEST_SHARE_RESET_WARN() shWarnLast = 0 shWarnSkip = 0 end
function EVAL_TEST_SHARE_LIMITS()
  return { buf = SH_MAX_BUF, chunks = SH_MAX_CHUNKS, text = SH_MAX_TEXT, done = SH_MAX_DONE, gap = SH_WARN_GAP }
end
-- ★1.71.3 观测口：弹窗详情行的**原始文本**（含被 Hide 的行）——
--   只读 IsShown 的行会漏掉「Hide 了但文本还留着」这种残留（本客户端 Hide 后仍可能被绘出）。
function EVAL_TEST_SHARE_DETAIL_RAW()
  local t = {}
  for _, fs in ipairs(shp.detailLines or {}) do
    local okt, txt = pcall(fs.GetText, fs)
    table.insert(t, (okt and type(txt) == "string") and txt or "")
  end
  return t
end

-- ★1.71.3 弹窗按钮位置/宽度（读**真实控件**，用于验「整组以窗口中线对齐」；窗口宽也读真实控件）
function EVAL_TEST_SHARE_BTN_POS()
  local out = { x1 = nil, x2 = nil, w = 0, W = 0 }
  if not shp.root then return out end
  local okW, ww = pcall(shp.root.GetWidth, shp.root)
  if okW and type(ww) == "number" then out.W = ww end
  local list = { shp.importBtn, shp.ignoreBtn }
  for i = 1, 2 do
    local b = list[i]
    if b then
      local okl, l = pcall(b.GetLeft, b)
      local okw, bw = pcall(b.GetWidth, b)
      if okl and type(l) == "number" then out["x" .. i] = l end
      if i == 1 and okw and type(bw) == "number" then out.w = bw end
    end
  end
  return out
end
-- ★1.71.3 弹窗标题图标的**实际纹理**（读控件，不读常量——否则测的是「写死的字符串」而不是「画出来的东西」）
function EVAL_TEST_SHARE_TITLE_ICON()
  if not shp.titleIcon then return nil end
  local ok, t = pcall(shp.titleIcon.GetTexture, shp.titleIcon)
  return ok and t or nil
end
function EVAL_SHARE_PENDING() return SH.pending end
function EVAL_SHARE_RESET() SH.buf = {} SH.done = {} SH.doneList = {} SH.pending = nil end
-- ★1.71.2 测试钩子：按分享弹窗的 [导入] 按钮（走它自己的 OnClick 闭包）。
--   用户报的 bug 正是这条路径漏了刷新——直调 EVAL_IMPORT_TEXT 会绕过它、测不出来。
function EVAL_TEST_SHARE_SELF_SKIPPED() return SH.selfSkipped or 0 end
function EVAL_TEST_SHARE_CLICK_IGNORE()
  if not (shp.ignoreBtn and shp.ignoreBtn.GetScript) then return false end
  local fn = shp.ignoreBtn:GetScript("OnClick")
  if not fn then return false end
  fn()
  return true
end
function EVAL_TEST_SHARE_CLICK_IMPORT()
  if not (shp.importBtn and shp.importBtn.GetScript) then return false end
  local fn = shp.importBtn:GetScript("OnClick")
  if not fn then return false end
  fn()
  return true
end
