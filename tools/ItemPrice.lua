-- EvalHelp · tools/ItemPrice.lua —— 物品售价：商人价学习 + tooltip 价格行 + 背包/银行估值（1.75.43 新增）
--
-- 需求（用户原话）：「在不依赖其他插件的情况下能否实现物品售价预览？然后把物品售价比对的功能完善」
--   本轮 A1 = 价格库 + 学价 + 悬停价格行 + 背包/银行估值；
--    A2（Shift 与已穿对比）/ A3（拾取总价）另做。
--
-- ★★★机制（三轮真机取证定稿；全案见 doc/物品价-可行性与真机取证.md 第十二之三）
--   · 本客户端**没有任何「由物品 id 拿售价」的 API**（`GetItemInfo` 报 10 个值就停在 texture，官方 wiki 原文核过）
--     ⇒ 售价只能**在商人窗开着时**从客户端嘴里撬：`GameTooltip:SetBagItem` 会触发 `OnTooltipAddMoney`。
--   · 金额**只从全局 `arg1` 来**（a1..a4 全 nil；三轮实测一致：`位置=5`）。
--   · **自建** GameTooltip 帧**照样触发**（25 格 → 11 次）⇒ 学价**零副作用**，不碰玩家那个 tooltip。
--   · 金额是**整栈总价** ⇒ **单价 = 金额 ÷ 该格数量**（数量是我们自己迭代出来的 ⇒ 比例精确可自证）。
--   · **替换 GameTooltip 的方法在本客户端无效**（行为判据：一次都没跑到包装；同机另一份插件的真机记录
--     同样只有 `hooks: 0 live` —— 该记录的原文与锚点在机制取证文档里）
--     ⇒ 物品识别走**客户端自己的按钮约定**（`GetID()` + 父级 `GetID()`；不读任何第三方插件的私有字段）
--       + 拾取行/任务奖励的**鼠标焦点**路 + tooltip 首行名字兜底。
--   · **只有「可卖」物品才有钱行**（25 格里只有 11 格）⇒「不可卖」与「还没学到」**必须分开**，
--     **绝不把没有钱行写成 0 铜**（那就变成免费了）。查不到 ≠ 免费。
--
-- ★数据来源（三档优先级，显示时如实区分）：
--   ① `cfg.itemPriceCfg.learned[id]` = **本服真价**（商人处扫到的；学到即永久覆盖）；
--   ② `EVAL_IP_BASE.p[id]` = **vanilla 基准价**（`ItemPriceData.lua` 生成物，13,994 条；
--      ★本服新增物品没有行、本服改过价的会先显示 vanilla 数）—— 显示时必须标「基准」；
--   ③ 都没有 ⇒ **不显示**（不猜、不写 0）。
--
-- ★纪律（照 CLAUDE.md 与 tools/InfoBar.lua / tools/LootCursor.lua）：
--   · 载入期零副作用：顶层只声明 + 把渲染函数登记进 `EVAL_TB_MOD_ROWS`；不建帧/不挂事件/不读存档/不建计时器。
--   · 只调全局桥（一律**调用时读**）：`EVAL_L` / `EVAL_SAY` / `EVAL_SAY_FORCE` / `EVAL_TB_CFG` / `EVAL_HELP_CONFIG`。
--   · 关掉零动作：总开关 `tbCfg().itemPrice` 闸在一切探测/读写**之前**；关掉 = 摘包装 + 注销事件 + 摘 OnUpdate + 藏自建 tooltip。
--   · 包装纪律：先存旧的 → **零参数**调原生 → **按身份比对**还原（期间被别人套过的不许冲掉）。
--   · 定时器有界：单一 0.2s OnUpdate（零形参，dt 取全局 arg1），负责「扫价滴出 + 悬停注释 + 银行节流」。
--   · 扫价限频：开商人窗那一拍**不**连扫上百格，改成每拍 `IP_BATCH` 格滴出（硬上限 `IP_SWEEP_MAX`）。

local IP = {
  built = false,        -- 自建扫价 tooltip 是否已建（读值口）
  armed = false,        -- 总开关是否已生效（事件/计时器在跑）
  evF = nil,            -- 事件帧（首用才建）
  tickF = nil,          -- 节拍帧（首用才建）
  tickT0 = nil,         -- ★1.75.74 节拍的时间基准（arg1 不可用时用 GetTime 差值推 dt）
  dtSrc = nil,          -- ★1.75.74 上一拍 dt 的来源："arg1" / "clock"（命令读数用）
  scan = nil,           -- 自建扫价 tooltip（GameTooltip 模板）
  orig = nil, wrap = nil, wrapped = false,   -- 被包装的全局处理体
  q, qn = nil, 0,       -- 扫价队列（FIFO）
  sweeping = false,     -- 队列是否在滴
  pendID, pendCount, pendName = nil, nil, nil,
  hit = nil,            -- 本格钱行金额（整栈）
  moneyFires = 0,       -- 本格钱行回调次数（0 = 不可卖；>0 但没金额 = 认不出）
  sLearn, sUn, sNoAmount, sSlots = 0, 0, 0, 0,   -- 本轮统计
  hb, hs = nil, nil,    -- 悬停格（按钮路解析出来的 bag/slot）
  acc = 0,              -- 0.2s 累加器
  appended = nil,       -- 我们刚追加的是哪一件（id/数量/来源）⇒ 同一件不重复写（见 ipAnnotate 顶部注释）
  lastName = nil,       -- 上一次悬停的 tooltip 首行名（变了 = 客户端重建/换物品 ⇒ 清 appended）
  bankAcc = 0,
  sweepWait = 0,        -- 开窗后等商人列表载入的倒计时（秒）
  lastSay = nil,        -- 最近一次扫价结果（toolbox 悬停里显示）
  warned = false,       -- 「没有 GetContainerItemLink」这类硬缺失只提醒一次
}

local IP_TICK = 0.2        -- 注释/滴出节拍
local IP_BATCH = 8         -- 每拍扫几格（限频；避免开窗那一拍上百次 tooltip 重建）
local IP_SWEEP_MAX = 400   -- 单次扫价硬上限（格）
local IP_SCAN_NAME = "EVAL_IP_SCAN"
local IP_PREFIX = "|cffffd701"   -- 价格行前缀色（与既有暖金一致）
local IP_DIM = "|cff9d9d9e"      -- 「基准」/「不可卖」的灰
local IP_MAX_NAME = 400          -- byName 索引上限（防止无限膨胀）

----------------------------------------------------------------------
-- 全局桥（★一律调用时读，载入期不抓快照 —— 本项目老雷）
----------------------------------------------------------------------

local function ipConf()
  local t = rawget(_G, "EVAL_HELP_CONFIG")
  return (type(t) == "table") and t or nil
end

local function ipTb()
  if type(EVAL_TB_CFG) == "function" then return EVAL_TB_CFG() end
  return ipConf()
end

-- ★模块必须自带 L（走 EVAL_L）：项目里 L 一律是文件局部，裸调会绑全局 nil 并被 pcall 吞掉。
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

-- 一般播报：受「调试日志」总闸门管（EVAL_SAY 自己带门控）
local function say(s)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(s)) end
end

-- 用户主动触发的读数：走常开出口（同 RareWatch / SimpleMap 的取证口；关掉调试日志也要看得见）
local function sayF(s)
  if type(EVAL_SAY_FORCE) == "function" then pcall(EVAL_SAY_FORCE, tostring(s))
  elseif type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(s)) end
end

-- 总开关真值（工具箱那一行的勾选框读写的就是它）
function EVAL_IP_ENABLED()
  local tb = ipTb()
  return (type(tb) == "table" and tb.itemPrice == true) or false
end

function EVAL_IP_SET(v)
  local tb = ipTb()
  if type(tb) ~= "table" then return false end
  tb.itemPrice = v and true or false
  EVAL_IP_INSTALL()
  return true
end

----------------------------------------------------------------------
-- 本模块自己的存档子树（真状态，**不是**残渣键）
----------------------------------------------------------------------

local function ipCfg()
  local c = ipConf()
  if not c then return nil end
  local t = c.itemPriceCfg
  if type(t) ~= "table" then t = {} c.itemPriceCfg = t end
  if type(t.learned) ~= "table" then t.learned = {} end
  if type(t.learnedAt) ~= "table" then t.learnedAt = {} end
  if type(t.byName) ~= "table" then t.byName = {} end
  if type(t.unsellable) ~= "table" then t.unsellable = {} end
  return t
end

local function ipCfgRO()
  local c = ipConf()
  local t = (type(c) == "table") and c.itemPriceCfg or nil
  return (type(t) == "table") and t or nil
end

----------------------------------------------------------------------
-- 金额与小工具
----------------------------------------------------------------------

-- 金额可能在 a1..a4 的任意位置，最后才试全局 arg1（真机实测本客户端**只在 arg1**）。
-- ★绝不用 `tostring(f())` 接多返回值（本项目老雷：只留第一个）。
local function ipAmount(a1, a2, a3, a4)
  local cand = { a1, a2, a3, a4, rawget(_G, "arg1") }
  for i = 1, 5 do
    local v = tonumber(cand[i])
    if v and v > 0 then return v end
  end
  return nil
end

-- 带色铜钱（本客户端 **inline texture `|T...|t` 不渲染** ⇒ 只能用字母 + 色）
local function ipMoney(c)
  c = math.floor(tonumber(c) or 0)
  local g = math.floor(c / 10000)
  local s = math.floor(c / 100) - g * 100
  local p = c - math.floor(c / 100) * 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  return out .. "|cffeda55f" .. p .. "c|r"
end

local function ipLinkID(link)
  if type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

local function ipLinkName(link)
  if type(link) ~= "string" then return nil end
  local nm = string.match(link, "%[(.-)%]")
  if type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

local function ipSlots(bag)
  if type(GetContainerNumSlots) ~= "function" then return 0 end
  local ok, n = pcall(GetContainerNumSlots, bag)
  return (ok and tonumber(n)) or 0
end

local function ipTexCount(bag, slot)
  if type(GetContainerItemInfo) ~= "function" then return nil, nil end
  local ok, tex, cnt = pcall(GetContainerItemInfo, bag, slot)   -- ★多返回值分开接
  if not ok then return nil, nil end
  if type(tex) ~= "string" or tex == "" then return nil, nil end   -- 空槽纹理是 ""（Lua 里是真值！）
  return tex, tonumber(cnt) or 1
end

local function ipSlotLink(bag, slot)
  if type(GetContainerItemLink) ~= "function" then return nil end
  local ok, link = pcall(GetContainerItemLink, bag, slot)
  if ok and type(link) == "string" then return link end
  return nil
end

----------------------------------------------------------------------
-- 价格查询（三档：学到 → 基准 → 无）
----------------------------------------------------------------------

local function ipBase(id)
  local base = rawget(_G, "EVAL_IP_BASE")
  if type(base) ~= "table" or type(base.p) ~= "table" then return nil end
  local s = base.p[id]
  if type(s) ~= "string" then return nil end
  local sell = tonumber(string.match(s, "^(%d+)"))
  if sell and sell > 0 then return sell end
  return nil   -- sell=0 = 不可卖 ⇒ 无价（不当作免费）
end

-- 返回：单价（铜/件）、来源（"learned" / "base"）、「已知不可卖」
local function ipPer(id)
  if not id then return nil, nil, false end
  local c = ipCfgRO()
  if c and type(c.learned) == "table" then
    local v = tonumber(c.learned[id])
    if v and v > 0 then return v, "learned", false end
  end
  local v = ipBase(id)
  if v then return v, "base", false end
  if c and type(c.unsellable) == "table" and c.unsellable[id] == true then
    return nil, nil, true
  end
  return nil, nil, false
end

local function ipIdByName(name)
  if type(name) ~= "string" or name == "" then return nil end
  local c = ipCfgRO()
  if not (c and type(c.byName) == "table") then return nil end
  return tonumber(c.byName[name])
end

----------------------------------------------------------------------
-- 自建扫价 tooltip（首用才建；关掉时只 Hide，不销毁，避免下次重建）
----------------------------------------------------------------------

local function ipScanFrame()
  if IP.scan then return IP.scan end
  if type(CreateFrame) ~= "function" then return nil end
  local ok, f = pcall(CreateFrame, "GameTooltip", IP_SCAN_NAME, UIParent)
  if not ok or not f then return nil end
  if f.SetOwner then pcall(f.SetOwner, f, UIParent, "ANCHOR_NONE") end
  pcall(f.SetScript, f, "OnTooltipAddMoney", function(a1, a2, a3, a4)
    IP.moneyFires = IP.moneyFires + 1
    local v = ipAmount(a1, a2, a3, a4)
    if v then IP.hit = v end
  end)
  IP.scan = f
  IP.built = true
  return f
end

local function ipScanHide()
  if IP.scan then pcall(IP.scan.Hide, IP.scan) end
end

----------------------------------------------------------------------
-- 商人窗扫价（真机定稿：自建 tooltip + 金额 ÷ 数量）
----------------------------------------------------------------------

-- 队列 = 当前背包里所有非空格（银行窗开着时也算上）
local function ipSweepBuild()
  IP.q, IP.qn = {}, 0
  local bags = { 0, 1, 2, 3, 4 }
  local bankSlots = ipSlots(-1)
  if bankSlots > 0 then
    bags[#bags + 1] = -1
    for b = 5, 10 do bags[#bags + 1] = b end
  end
  local i = 1
  while bags[i] do
    local bag = bags[i]
    local n = ipSlots(bag)
    for slot = 1, n do
      if IP.qn >= IP_SWEEP_MAX then break end
      local tex = ipTexCount(bag, slot)
      if tex then
        IP.qn = IP.qn + 1
        IP.q[IP.qn] = { bag, slot }
      end
    end
    i = i + 1
  end
  IP.sLearn, IP.sUn, IP.sNoAmount, IP.slots = 0, 0, 0, IP.qn
  return IP.qn
end

-- 滴一拍：处理最多 IP_BATCH 格。返回 true = 还有剩余
local function ipSweepStep()
  local scan = ipScanFrame()
  if not scan then return false end
  local c = ipCfg()
  local now = (type(GetTime) == "function") and GetTime() or 0
  local done = 0
  while done < IP_BATCH and IP.qn > 0 do
    local it = table.remove(IP.q, 1)
    IP.qn = IP.qn - 1
    done = done + 1
    if it then
      local bag, slot = it[1], it[2]
      local link = ipSlotLink(bag, slot)
      local id = ipLinkID(link)
      if id then
        local _, cnt = ipTexCount(bag, slot)
        local count = tonumber(cnt) or 1
        if count < 1 then count = 1 end
        IP.pendID, IP.pendCount, IP.pendName = id, count, ipLinkName(link)
        IP.hit, IP.moneyFires = nil, 0
        pcall(scan.SetOwner, scan, UIParent, "ANCHOR_NONE")
        pcall(scan.SetBagItem, scan, bag, slot)
        if IP.hit then
          -- ★金额 = 整栈总价 ⇒ 单价 = 金额 ÷ 数量（真机定稿口径）
          local per = math.floor(IP.hit / count + 0.5)
          if per > 0 and c then
            c.learned[id] = per
            c.learnedAt[id] = now
            if IP.pendName and type(c.byName) == "table" then
              -- byName 只作为**悬停兜底**用；有上限，满了就不再涨（不洗掉旧的）
              if c.byName[IP.pendName] == nil then
                local n = 0
                for _ in pairs(c.byName) do n = n + 1 end
                if n < IP_MAX_NAME then c.byName[IP.pendName] = id end
              else
                c.byName[IP.pendName] = id
              end
            end
            c.unsellable[id] = nil   -- 学到价 ⇒ 清掉旧的「不可卖」标记
            IP.sLearn = IP.sLearn + 1
          end
        elseif IP.moneyFires == 0 then
          -- 一个钱行都没有 = **不可卖**（官方 wiki：不可卖物品不触发 OnTooltipAddMoney）
          if c and type(c.unsellable) == "table" then c.unsellable[id] = true end
          IP.sUn = IP.sUn + 1
        else
          -- 有钱行回调但金额认不出 ⇒ 如实计「认不出」，**绝不写 0 价**
          IP.sNoAmount = IP.sNoAmount + 1
        end
      end
    end
  end
  IP.pendID, IP.pendCount, IP.pendName = nil, nil, nil
  return IP.qn > 0
end

local function ipSweepFinish()
  ipScanHide()
  local msg = L("IP_LEARN_DONE", IP.sLearn, IP.slots, IP.sUn, IP.sNoAmount)
  IP.lastSay = msg
  return msg
end

-- 立刻扫（/eh go 物品价 学价 走它；要有商人窗）
local function ipSweepNow()
  if not EVAL_IP_ENABLED() then sayF(L("IP_OFF_HINT")) return false end
  local n = ipSweepBuild()
  if n == 0 then
    sayF(L("IP_LEARN_NOTHING"))
    return false
  end
  IP.sweeping = true
  local guard = 0
  while ipSweepStep() and guard < 200 do guard = guard + 1 end
  IP.sweeping = false
  sayF(ipSweepFinish())
  return true
end

----------------------------------------------------------------------
-- 悬停：把价格行补进玩家的 GameTooltip
----------------------------------------------------------------------

-- ★★去重口径（真机坑，别再改回「走字串找自己那行」）：
--   本客户端 tooltip 重建后，**旧的字串仍留着上一次的文本**（CLAUDE.md 既有判据：
--   「lines past NumLines still hold the text of the previous tooltip」）⇒ 用「走字串看有没有我们那行」
--   会在**重建后误判成「已经写过」**，于是价格行**再也补不回来**（本模块的 harness 真跑抓到过这个症状；
--   早先版本就是这么写的）。⇒ 改成**显式标记 + 重建信号**：
--     · `IP.appended` 记「我们刚追加的是哪一件（id/数量/来源）」；
--     · 「客户端重建了 tooltip」有**两个**信号：① 我们的容器按钮包装**又被调用**（容器按钮每 1/5 秒重建一次，
--       原生处理体会再调一次全局 OnEnter）；② tooltip 首行名字变了 ⇒ 两个信号都清标记，允许重写一次。

-- 按钮 → bag/slot：**只用客户端自己的约定** —— `GetID()` = 格子号、父级 `GetID()` = 容器号
-- （客户端原生 `ContainerFrameItemButton_OnEnter` 就是这么取的）。
-- ★★刻意**不读任何第三方插件的私有字段**（早先版本读过某背包插件自己的格子字段，已删）：
--   本项目不与其它插件做关联 —— 别人改名/改结构不该影响这里；读不到就交给「首行名字」兜底。
local function ipBtnSlot(btn)
  if btn == nil then return nil end
  local sid = (btn.GetID) and btn:GetID() or nil
  local par = (btn.GetParent) and btn:GetParent() or nil
  local bid = (par and par.GetID) and par:GetID() or nil
  if type(sid) == "number" and type(bid) == "number" then return bid, sid end
  return nil
end

-- 任务奖励页 / 任务日志：**按气泡首行名字**在候选里反查（拿不到就 nil，绝不猜）
--   inLog = true ⇒ 查任务日志（QuestLog*）；false ⇒ 查奖励页（GetQuestItemInfo / GetQuestItemLink）
--   返回 link, 数量, 名字
local function ipQuestByName(name, inLog)
  if type(name) ~= "string" or name == "" then return nil end
  local kinds = { "choice", "reward" }
  local k = 1
  while kinds[k] do
    local kind = kinds[k]
    local n = 0
    if inLog then
      if kind == "choice" and type(GetNumQuestLogChoices) == "function" then n = tonumber(GetNumQuestLogChoices()) or 0 end
      if kind == "reward" and type(GetNumQuestLogRewards) == "function" then n = tonumber(GetNumQuestLogRewards()) or 0 end
    else
      if kind == "choice" and type(GetNumQuestChoices) == "function" then n = tonumber(GetNumQuestChoices()) or 0 end
      if kind == "reward" and type(GetNumQuestRewards) == "function" then n = tonumber(GetNumQuestRewards()) or 0 end
    end
    local j = 1
    while j <= n do
      local nm2, cnt = nil, nil
      if inLog then
        if kind == "choice" then
          if type(GetQuestLogChoiceInfo) == "function" then nm2, _, cnt = GetQuestLogChoiceInfo(j) end
        else
          if type(GetQuestLogRewardInfo) == "function" then nm2, _, cnt = GetQuestLogRewardInfo(j) end
        end
      elseif type(GetQuestItemInfo) == "function" then
        nm2, _, cnt = GetQuestItemInfo(kind, j)
      end
      if nm2 == name then
        local link = nil
        if inLog then
          if type(GetQuestLogItemLink) == "function" then link = GetQuestLogItemLink(kind, j) end
        elseif type(GetQuestItemLink) == "function" then
          link = GetQuestItemLink(kind, j)
        end
        return link, tonumber(cnt) or 1, name
      end
      j = j + 1
    end
    k = k + 1
  end
  return nil
end

-- 拾取行（LootButton1..4）与任务奖励（QuestRewardItem / QuestProgressItem / QuestLogItem）
--   ★走「鼠标焦点」而不是逐个 hook：这几个面的按钮数量不定，焦点判定一条就够。
--   ★★★1.75.74：**帧名认不出时不再整条放弃**（真机奖励页那个按钮的真身就不在这几个模式里；
--     装备比较 1.75.74 真机正是栽在「只认帧名」这一点上）⇒ 还剩气泡首行名字可依据，就把
--     任务日志族与奖励页族都试一遍，都对不上才返回 nil（**绝不猜**）。
--   ★同批修掉的潜伏崩溃：旧写法把 string.match 的结果**直接喂给 tonumber**，模式不匹配时那就是
--     tonumber(nil) ⇒ 当场抛错；而这条路径没有 pcall 兜着（悬停任何**具名**而非 LootButton 的帧
--     都会炸）⇒ 现在先接住匹配结果、非 nil 才转数字（锚点：local lootN = ... then）。
local function ipFocusItem()
  -- 气泡首行名字（**与帧名无关**的那条依据；真机奖励页就是靠它）
  local name = nil
  do
    local fs = rawget(_G, "GameTooltipTextLeft1")
    if fs and fs.GetText then
      local okT, t = pcall(fs.GetText, fs)
      if okT and type(t) == "string" and t ~= "" then name = t end
    end
  end
  -- 光标下那个帧的名字（★本客户端 GetMouseFocus 不可靠 ⇒ 可能读不到；读不到不算错）
  local nm = nil
  if type(GetMouseFocus) == "function" then
    local okF, w = pcall(GetMouseFocus)
    if okF and w ~= nil then
      local okN, n2 = pcall(function() return w.GetName and w:GetName() end)
      if okN and type(n2) == "string" then nm = n2 end
    end
  end

  -- ① 拾取行：帧名能定到第几格 ⇒ 直接问客户端要链接
  local lootN = nm and string.match(nm, "^LootButton(%d+)$") or nil
  if lootN then
    local i = tonumber(lootN)
    local link = nil
    if type(GetLootSlotLink) == "function" then link = GetLootSlotLink(i) end
    local cnt = 1
    if type(GetLootSlotInfo) == "function" then
      local _, _, c2 = GetLootSlotInfo(i)      -- (纹理, 名字, 数量, 品质……)
      cnt = tonumber(c2) or 1
    end
    return link, cnt, ipLinkName(link)
  end

  -- ② 帧名认得出是任务面 ⇒ 按它定族（奖励页 / 任务日志），再按名字反查
  local inLog = (nm and string.match(nm, "^QuestLogItem%d+$")) and true or false
  local inGiver = (nm and (string.match(nm, "^QuestRewardItem%d+$")
    or string.match(nm, "^QuestProgressItem%d+$"))) and true or false
  if inLog or inGiver then return ipQuestByName(name, inLog) end

  -- ③ 帧名认不出 ⇒ 只剩首行名字：任务日志族 + 奖励页族都试一遍
  if name then
    local link, cnt = ipQuestByName(name, true)
    if not link then link, cnt = ipQuestByName(name, false) end
    if link then return link, cnt, name end
  end
  return nil
end

local function ipTipShown()
  local tip = rawget(_G, "GameTooltip")
  if not tip or type(tip.IsShown) ~= "function" then return nil end
  local ok, s = pcall(tip.IsShown, tip)
  if not ok then return nil end
  return s and tip or nil
end

-- tooltip 第一行 = 当前悬停物品的名字（真机实测读得到；★客户端读回的文本**不含色码**）
local function ipTipName()
  local fs = rawget(_G, "GameTooltipTextLeft1")
  if not fs or not fs.GetText then return nil end
  local ok, t = pcall(fs.GetText, fs)
  if ok and type(t) == "string" and t ~= "" then return t end
  return nil
end

-- 名字归一（两端都过）：去色码 + 首尾空白 —— 只用来做**同一件东西**的比对
local function ipNameNorm(s)
  if type(s) ~= "string" then return nil end
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  if s == "" then return nil end
  return s
end

-- 注释：算出「这一拍该不该写、写什么」，写进去。返回写了几行。
local function ipAnnotate()
  local tip = ipTipShown()
  if not tip then IP.appended, IP.lastName = nil, nil return 0 end

  local tipName = ipNameNorm(ipTipName())
  if tipName ~= IP.lastName then IP.appended = nil IP.lastName = tipName end   -- 重建信号②

  -- ① 物品识别：按钮路（精确 bag/slot + 数量）→ 焦点路（拾取/任务奖励）→ 首行名字兜底
  local id, count, name = nil, nil, nil
  local b, s = IP.hb, IP.hs
  if b and s then
    local link = ipSlotLink(b, s)
    local linkID, linkName = ipLinkID(link), ipNameNorm(ipLinkName(link))
    -- ★★★名字必须与 tooltip 首行一致：`IP.hb/hs` 是**上一次容器悬停留下的状态**，
    --   玩家随后可能悬停在不带容器模板的窗口上 ⇒ 不校验就会把**上一个格子的价**写到别人提示里。
    if linkID and linkName and tipName and linkName == tipName then
      id, name = linkID, linkName
      local _, cnt = ipTexCount(b, s)
      count = tonumber(cnt) or 1
    end
  end
  if not id then
    local link, cnt, nm = ipFocusItem()
    local linkID, linkName = ipLinkID(link), ipNameNorm(nm or ipLinkName(link))
    -- 焦点路同样要求对得上（拿不到首行时放行：那边是**当前**鼠标焦点，不是陈旧状态）
    if linkID and (tipName == nil or linkName == nil or linkName == tipName) then
      id, count, name = linkID, tonumber(cnt) or 1, linkName
    end
  end
  if not id and tipName then
    name, id = tipName, ipIdByName(tipName)   -- ★只有「学到过」的物品才有名→id 索引（基准表没有名字）
  end
  if not id then IP.appended = nil return 0 end

  local per, src, unsell = ipPer(id)
  local key = tostring(id) .. "/" .. tostring(count) .. "/" .. tostring(src) .. "/" .. tostring(unsell)
  if IP.appended == key then return 0 end   -- 同一件东西已写过、且没收到重建信号 ⇒ 一拍都不重写

  local line = nil
  if per then
    local total = per * (tonumber(count) or 1)
    local tag = (src == "base") and (" " .. IP_DIM .. "(" .. L("IP_BASE_TAG") .. ")|r") or ""
    if (tonumber(count) or 1) > 1 then
      line = IP_PREFIX .. L("IP_VENDOR") .. "|r " .. ipMoney(total)
        .. " " .. IP_DIM .. L("IP_EACH", ipMoney(per)) .. "|r" .. tag
    else
      line = IP_PREFIX .. L("IP_VENDOR") .. "|r " .. ipMoney(total) .. tag
    end
  elseif unsell then
    line = IP_DIM .. L("IP_VENDOR") .. " " .. L("IP_UNSELLABLE") .. "|r"
  end
  if not line then IP.appended = key return 0 end

  local okA = pcall(tip.AddLine, tip, line, 1, 0.82, 0)
  if okA then
    pcall(tip.Show, tip)
    IP.appended = key
    return 1
  end
  return 0
end

----------------------------------------------------------------------
-- 背包 / 银行估值
----------------------------------------------------------------------

local function ipContainerWorth(bag, total, known, unknown)
  local n = ipSlots(bag)
  if n <= 0 then return total, known, unknown end
  for slot = 1, n do
    local _, cnt = ipTexCount(bag, slot)
    if cnt then
      local link = ipSlotLink(bag, slot)
      local id = ipLinkID(link)
      local per = ipPer(id)
      if per then
        total = total + per * (tonumber(cnt) or 1)
        known = known + 1
      else
        unknown = unknown + 1
      end
    end
  end
  return total, known, unknown
end

function EVAL_IP_BAG_WORTH()
  local total, known, unknown = 0, 0, 0
  for bag = 0, 4 do
    total, known, unknown = ipContainerWorth(bag, total, known, unknown)
  end
  return total, known, unknown
end

-- 银行只在开窗时回答（关着时槽位=0）；开着就顺手记进存档（下次没开窗也能报「按上次记录」）
function EVAL_IP_BANK_WORTH()
  local total, known, unknown, seen = 0, 0, 0, false
  if ipSlots(-1) > 0 then
    seen = true
    total, known, unknown = ipContainerWorth(-1, total, known, unknown)
    for bag = 5, 10 do
      total, known, unknown = ipContainerWorth(bag, total, known, unknown)
    end
    local c = ipCfg()
    if c then c.bank = { total = total, known = known, unknown = unknown, t = (type(GetTime) == "function") and GetTime() or 0 } end
  end
  return total, known, unknown, seen
end

local function ipBankSaved()
  local c = ipCfgRO()
  local b = c and c.bank
  if type(b) == "table" and tonumber(b.total) then return tonumber(b.total), tonumber(b.known) or 0, tonumber(b.unknown) or 0 end
  return nil
end

local function ipWorthReport()
  local total, known, unknown = EVAL_IP_BAG_WORTH()
  sayF(L("IP_WORTH_BAG", ipMoney(total), known, unknown))
  local bt, bk, bu, seen = EVAL_IP_BANK_WORTH()
  if seen then
    sayF(L("IP_WORTH_BANK", ipMoney(bt), bk, bu, ""))
  else
    local st, sk, su = ipBankSaved()
    if st then
      sayF(L("IP_WORTH_BANK", ipMoney(st), sk, su, L("IP_BANK_OLD")))
    else
      sayF(L("IP_BANK_NEVER"))
    end
  end
  return total, known, unknown
end

----------------------------------------------------------------------
-- 包装 / 事件 / 节拍
----------------------------------------------------------------------

local function ipHookButtons()
  if IP.wrapped then return true end
  local orig = rawget(_G, "ContainerFrameItemButton_OnEnter")
  if type(orig) ~= "function" then return false end
  local wrap = function()
    orig()                                  -- ★零参数调原生（客户端把 this/arg1 放全局）
    local btn = rawget(_G, "this")
    local b, s = ipBtnSlot(btn)
    -- ★重建信号①：容器按钮每 1/5 秒重建 tooltip 时会再调一次这个全局 ⇒ 当场清标记，允许补写一次
    if b and s then IP.hb, IP.hs, IP.appended = b, s, nil end
    ipAnnotate()                            -- 客户端每 1/5 秒会重建 tooltip（靠这里每次补回）
  end
  rawset(_G, "ContainerFrameItemButton_OnEnter", wrap)
  if rawget(_G, "ContainerFrameItemButton_OnEnter") == wrap then   -- 读回自证（全局函数可读回）
    IP.orig, IP.wrap, IP.wrapped = orig, wrap, true
    return true
  end
  return false
end

local function ipUnhookButtons()
  if not IP.wrapped then return false end
  local cur = rawget(_G, "ContainerFrameItemButton_OnEnter")
  if cur == IP.wrap then
    rawset(_G, "ContainerFrameItemButton_OnEnter", IP.orig)
  elseif type(EVAL_SAY) == "function" then
    -- 期间被别人套过 ⇒ **不冲掉别人的**，如实说一句
    pcall(EVAL_SAY, L("IP_UNHOOK_BUSY"))
  end
  IP.orig, IP.wrap, IP.wrapped = nil, nil, false
  return true
end

local function ipEventsOn()
  if type(CreateFrame) ~= "function" then return false end
  if not IP.evF then
    local ok, f = pcall(CreateFrame, "Frame")
    if not ok or not f then return false end
    IP.evF = f
  end
  local f = IP.evF
  pcall(f.SetScript, f, "OnEvent", function()
    local ev = rawget(_G, "event")
    if ev == "MERCHANT_SHOW" then
      -- 商人列表可能还没载入 ⇒ 等 IP_SWEEP_WAIT 秒再扫（有界）
      IP.sweepWait = 0.8
    elseif ev == "MERCHANT_CLOSED" then
      IP.sweepWait, IP.q, IP.qn, IP.sweeping = 0, {}, 0, false
      ipScanHide()
    elseif ev == "BANKFRAME_CLOSED" then
      EVAL_IP_BANK_WORTH()      -- 关窗那一刻记一次（银行只有开窗时才读得到）
    end
  end)
  local evs = { "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_CLOSED" }
  for i = 1, #evs do pcall(f.RegisterEvent, f, evs[i]) end
  return true
end

local function ipEventsOff()
  local f = IP.evF
  if not f then return end
  if type(f.UnregisterAllEvents) == "function" then pcall(f.UnregisterAllEvents, f)
  else
    local evs = { "MERCHANT_SHOW", "MERCHANT_CLOSED", "BANKFRAME_CLOSED" }
    for i = 1, #evs do pcall(f.UnregisterEvent, f, evs[i]) end
  end
  pcall(f.SetScript, f, "OnEvent", nil)
end

local function ipTickOn()
  if type(CreateFrame) ~= "function" then return false end
  if not IP.tickF then
    local ok, f = pcall(CreateFrame, "Frame")
    if not ok or not f then return false end
    IP.tickF = f
  end
  -- ★★★1.75.74：逻辑帧也**显式 Show** —— OnUpdate 只对「显示中」的帧回调（本项目在案：挂在被隐藏
  --   的父级下的帧会停摆，例：开图隐藏 UIParent）。该帧没有尺寸/贴图，Show 不画任何东西；
  --   不 Show 的代价是「整条节拍不存在」—— 而容器悬停走包装是**直接调** ipAnnotate 的 ⇒
  --   背包照旧有价、看着像好的，只有焦点路（拾取/任务奖励）与自动扫价全哑（同装备比较 1.75.74）。
  pcall(IP.tickF.Show, IP.tickF)
  pcall(IP.tickF.SetScript, IP.tickF, "OnUpdate", function()
    -- ★零形参：dt 先取全局 arg1（本客户端 OnUpdate 回调一个参数都不传、参数走全局）
    if not IP.armed then return end
    -- ★★★1.75.74：dt **不再只认 arg1**。旧写法 `tonumber(arg1) or 0` ⇒ 拿不到就 acc 恒 0
    --   ⇒ ①注释节拍永不触发（焦点路全哑）②`sweepWait` 永不递减（**开商人窗自动扫价也永不启动**），
    --   而这两条都只表现成「什么都没有」，与「本来就没价」肉眼分不出（同装备比较 1.75.74）。
    --   现在：arg1 合理就直接用，否则拿 GetTime 差值兜底（全项目其它节拍一律 `or 0.05` 兜底）。
    local now = ((type(GetTime) == "function") and GetTime()) or nil
    local dt = tonumber(rawget(_G, "arg1"))
    if (not dt) or dt <= 0 or dt > 0.5 then
      dt = (now and IP.tickT0 and (now - IP.tickT0)) or 0.05
      IP.dtSrc = "clock"
    else
      IP.dtSrc = "arg1"
    end
    if now then IP.tickT0 = now end
    if dt <= 0 then dt = 0.05 end
    if dt > 0.5 then dt = 0.5 end
    IP.acc = IP.acc + dt

    -- ① 开窗后等列表载入 → 建队列
    if IP.sweepWait > 0 then
      IP.sweepWait = IP.sweepWait - dt
      if IP.sweepWait <= 0 then
        IP.sweepWait = 0
        ipSweepBuild()
        IP.sweeping = IP.qn > 0
      end
    end
    -- ② 队列滴出（限频：每拍 IP_BATCH 格）
    if IP.sweeping then
      local more = ipSweepStep()
      if not more then
        IP.sweeping = false
        local msg = ipSweepFinish()
        say(msg)                       -- 一般播报（受调试日志闸门管；用户主动跑命令时另走 sayF）
      end
    end
    -- ③ 注释节拍（0.2s 一拍；同一件东西同一口径一拍都不重写）
    if IP.acc >= IP_TICK then
      IP.acc = 0
      ipAnnotate()
      if IP.hb and not ipTipShown() then IP.hb, IP.hs, IP.appended, IP.lastName = nil, nil, nil, nil end
    end
  end)
  return true
end

local function ipTickOff()
  if IP.tickF then pcall(IP.tickF.SetScript, IP.tickF, "OnUpdate", nil) end
end

-- 总武装/解除（关掉零动作：一切探测都在这个门之后）
function EVAL_IP_INSTALL()
  local on = EVAL_IP_ENABLED()
  if on then
    if IP.armed then return true end
    IP.armed = true
    ipHookButtons()
    ipEventsOn()
    ipTickOn()
    return true
  end
  -- 关掉：摘包装 + 注销事件 + 摘 OnUpdate + 藏自建 tooltip + 清悬停态
  IP.armed = false
  ipUnhookButtons()
  ipEventsOff()
  ipTickOff()
  ipScanHide()
  IP.q, IP.qn, IP.sweeping = {}, 0, false
  IP.hb, IP.hs, IP.appended, IP.lastName = nil, nil, nil, nil
  IP.tickT0, IP.dtSrc = nil, nil
  return false
end

----------------------------------------------------------------------
-- 命令体（宿主 /eh 链只留一行 prRun("ITEMPRICE", msg) 转发过来）
----------------------------------------------------------------------

local function ipStatusLine()
  local c = ipCfgRO()
  local n = 0
  if c and type(c.learned) == "table" then for _ in pairs(c.learned) do n = n + 1 end end
  local base = rawget(_G, "EVAL_IP_BASE")
  local bn = (type(base) == "table" and type(base.meta) == "table") and tonumber(base.meta.n) or 0
  local total = EVAL_IP_BAG_WORTH()
  return L("IP_STATUS", EVAL_IP_ENABLED() and L("IP_ON") or L("IP_OFF"), n, bn, ipMoney(total))
end

-- ★★★1.75.74：「节拍挂没挂 / dt 从哪来」必须能读 —— 焦点路（拾取行 / 任务奖励页）的悬停补价、
--   以及「开商人窗后自动扫价」**全靠这一拍**，而它没在跑时画面与「本来就没价」一模一样
--   （装备比较 1.75.74 就是白绕一轮栽在这种静默上）。判据 = 直接问帧有没有 OnUpdate handler。
local function ipTickLine()
  local att = "?"
  if IP.tickF and type(IP.tickF.GetScript) == "function" then
    local okG, h = pcall(IP.tickF.GetScript, IP.tickF, "OnUpdate")
    if okG then att = (h and "**挂**" or "**真摘**") end
  end
  return "节拍：" .. att .. " ｜ armed=" .. tostring(IP.armed) .. " · 包装=" .. tostring(IP.wrapped)
    .. " · acc=" .. string.format("%.2f", tonumber(IP.acc) or 0)
    .. " · dt 来源=" .. tostring(IP.dtSrc or "?")
    .. " · 扫价等=" .. string.format("%.1f", tonumber(IP.sweepWait) or 0) .. "s"
    .. " · 队列=" .. tostring(IP.qn or 0)
end

function EVAL_IP_STATUS() return ipStatusLine() end

function EVAL_IP_CMD(msg)
  local m = tostring(msg or "")
  if string.find(m, "学价", 1, true) or string.find(m, "扫", 1, true) then
    ipSweepNow()
    return true
  end
  if string.find(m, "清价", 1, true) or string.find(m, "忘掉", 1, true) then
    local c = ipCfg()
    local n = 0
    if c then
      if type(c.learned) == "table" then for _ in pairs(c.learned) do n = n + 1 end end
      c.learned, c.learnedAt, c.byName, c.unsellable = {}, {}, {}, {}
    end
    sayF(L("IP_CLEARED", n))
    return true
  end
  if string.find(m, "值", 1, true) or string.find(m, "估值", 1, true) then
    ipWorthReport()
    return true
  end
  -- 默认 = 状态
  sayF(ipStatusLine())
  sayF(ipTickLine())
  local c = ipCfgRO()
  if c and c.bank then
    local st, sk, su = ipBankSaved()
    if st then sayF(L("IP_WORTH_BANK", ipMoney(st), sk, su, L("IP_BANK_OLD"))) end
  end
  if IP.lastSay then sayF(L("IP_LAST_SWEEP") .. IP.lastSay) end
  sayF(L("IP_CMD_HINT"))
  return true
end

-- 读值口（生产诊断：探针与真机取证都走它们）
function EVAL_IP_TEST_STATE()
  local c = ipCfgRO()
  local n = 0
  if c and type(c.learned) == "table" then for _ in pairs(c.learned) do n = n + 1 end end
  local att = false
  if IP.tickF and type(IP.tickF.GetScript) == "function" then
    local okG, h = pcall(IP.tickF.GetScript, IP.tickF, "OnUpdate")
    att = (okG and h ~= nil) and true or false
  end
  return {
    on = EVAL_IP_ENABLED(), armed = IP.armed, built = IP.built, wrapped = IP.wrapped,
    learned = n, sweeping = IP.sweeping, queue = IP.qn,
    lastSay = IP.lastSay, hb = IP.hb, hs = IP.hs,
    tickAttached = att, dtSrc = IP.dtSrc, sweepWait = IP.sweepWait,
  }
end

function EVAL_IP_TEST_PRICE(id) return ipPer(id) end
function EVAL_IP_TEST_CFG() return ipCfgRO() end

----------------------------------------------------------------------
-- 工具箱那一行（模块自己渲染；Toolbox 侧只加一行数据）
----------------------------------------------------------------------

local function ipRowTip(btn, it)
  local tip = rawget(_G, "GameTooltip")
  if not tip or type(tip.SetOwner) ~= "function" then return end
  pcall(tip.SetOwner, tip, btn, "ANCHOR_RIGHT")
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_ITEMPRICE_TIP"), 1, 0.85, 0.30)
  pcall(tip.AddLine, tip, ipStatusLine(), 0.75, 0.95, 0.75)
  pcall(tip.AddLine, tip, L("IP_TIP_DISPLAY"), 0.9, 0.88, 0.78)
  pcall(tip.AddLine, tip, L("IP_TIP_PRICE_SRC"), 0.9, 0.88, 0.78)
  if IP.lastSay then pcall(tip.AddLine, tip, L("IP_LAST_SWEEP") .. IP.lastSay, 0.7, 0.7, 0.7) end
  pcall(tip.Show, tip)
end

local function ipRowLeave()
  local tip = rawget(_G, "GameTooltip")
  if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
end

local function ipRow(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return EVAL_IP_ENABLED() end
  r.set = function(v) EVAL_IP_SET(v and true or false) end
  r.extra:Hide()                 -- ★配置项只在按钮悬停里显示，行上不重复（项目纪律）

  r.add.text:SetText(L("IP_BTN_LEARN"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function() ipRowTip(r.add.btn, it) end)
  r.add.btn:SetScript("OnLeave", ipRowLeave)
  r.add.btn:SetScript("OnClick", function() ipSweepNow() end)

  r.clr.text:SetText(L("IP_BTN_WORTH"))
  r.clr.btn:Show()
  r.clr.btn:SetScript("OnEnter", function() ipRowTip(r.clr.btn, it) end)
  r.clr.btn:SetScript("OnLeave", ipRowLeave)
  r.clr.btn:SetScript("OnClick", function() ipWorthReport() end)
  return true
end

local IP_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(IP_TB_ROWS) ~= "table" then
  IP_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", IP_TB_ROWS)
end
IP_TB_ROWS["itemPrice"] = ipRow

-- 载入期到此结束：没有 CreateFrame / RegisterEvent / 存档读写 / 计时器。
