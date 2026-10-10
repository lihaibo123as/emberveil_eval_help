-- ============================================================
-- EH_Mail —— EvalHelp 子插件：邮箱 API 支持度体检（v0.1.0 · 体检版）
--
-- ★★本文件要解决什么问题（用户 2026-10-10 定：「作为 EH_Mail 子插件」测试）：
--   `tmp/TurtleMail/` 那个 TurtleWoW 血统的邮箱增强插件，**C API 层已被离线证明全支持**
--   （49 个函数逐个都在 EmberVeil 官方 API 索引里，邮件类 31 条一条不缺），
--   唯一判不了的是 **FrameXML / 具名帧这一层**（索引不收 FrameXML；pak 内容是压缩的；
--   `tmp/mpq_out` 是另一台客户端的基础 MPQ，只能当同血统旁证）。
--   ⇒ 这一层的结论只能由**真机**给出：本子插件就是那把尺子。
--   结论与全部证据 = `doc/TurtleMail-API支持度调研.md`（风险条目 R1~R10）。
--
-- ★★★命令（唯一入口，游戏内敲）：`/email`（别名 `/eh邮件`）
--   `/email`          只读体检：逐个判定 115 个客户端名字在不在 → 结果写进本子插件自己的
--                     有界落盘环 `EH_MAIL_CFG.probe` → 聊天回 3 行（结论 + 缺失点名 + 倒数）
--                     → **延后 6 秒自动 /reload** 落盘（AI 自己去读存档，不用玩家转述）
--   `/email 明细`     把落盘环摊开到聊天（全量，按写入顺序）
--   `/email 状态`     一行简报（上次体检时间 / 缺几条 / 环里几条）
--   `/email 清`       清空落盘环
--
-- ★★★三条纪律（本项目铁律在本文件里的落点）：
--   1) **体检必须全只读**：不写任何游戏状态、不碰任何客户端全局、不建常驻帧、不挂事件；
--      唯一例外 = 模板探针要 `CreateFrame` 试一次（1.12 **没有销毁帧的 API**）⇒ 建出来当场
--      `Hide` 且不留引用，并在聊天里如实报「探针临时帧：建了 N 个」。
--   2) **一个模块只许一个节拍帧**：全文只有 `EH_MailTick` 一个 `OnUpdate`，
--      挂/摘走**唯一入口** `tickSync()`（有待办才挂，到点执行完当场真摘）。
--   3) **记忆体分离**（宿主契约②）：本文件**只**读写自己的 `EH_MAIL_CFG`，
--      `EVAL_HELP_CONFIG` / `EVAL_HELP_CHAR` 命中 0 处（常驻闸门 `tmp/mem_sep_probe.js` 守着）。
--
-- ★★判读口径（AI 读存档时按这张表走）：
--   · `缺 0 项`                ⇒ 可直接用，风险 R1~R4 全部排除
--   · 缺 `FUNC` 里任一挂钩全局  ⇒ R1：TurtleMail 一开邮箱就会红字（它的包装体无 nil 守卫）
--   · 缺 `SendMailMoney*Right` / `REGIONS < 9` ⇒ R2：它的 `sendmail_load` 会从那一行整段中断
--   · 缺 `FriendsFrameTabTemplate` ⇒ R3：它的 XML 载入失败 / 第 3 个页签不可用
--   · 缺 `PARENT` 组            ⇒ R4：`$parent` 派生名（静态看不见，只能运行期探）
-- ★环里的行格式固定为 `类别 名字 结论 备注`（类别 = FUNC/FRAME/MISC/CONST/FONT/PARENT/TEMPLATE/REGIONS），
--   便于用脚本按列统计（读存档脚本 = `tmp/read_ehmailprobe.js`）。
-- ============================================================

local EH_MAIL_BUILD = "0.3.18"
-- 落盘环上限（有界：超上限丢最老的）
local RING_MAX = 260
-- 体检结束后延后多少秒自动 /reload
-- ★不能立刻重载：本客户端 /reload 会清空聊天框，玩家会看到「重载了、什么都没发生」（1.75.59m 教训）
local RELOAD_SEC = 6

-- ============================================================
-- 本地化（子插件自带三语；**绝不**碰宿主语言包，也不扩宿主 Locales）
-- ============================================================
local T = {
  zhCN = {
    USAGE = "用法：/email（体检）｜/email 明细｜/email 状态｜/email 清",
    HEAD = "体检：共 %d 项 ｜ 缺 %d 项",
    OK = "★全部命中：这 %d 项客户端名字一个不缺（风险 R1~R4 全部排除）",
    MISS = "缺失：%s",
    MISS_MORE = "%s …等共 %d 项",
    OVER = "★区域下标越界：%s（上游插件的源码是裸索引 GetRegions()[N]，越界即运行期报错）",
    RELOAD = "%d 秒后自动 /reload 落盘 ｜ 探针临时帧 %d 个（已全部 Hide）",
    MANUAL = "拿不到 RunScript / GetTime ⇒ 结果已在存档表里，请手动 /reload 一次落盘",
    RING_HEAD = "落盘环（最新在后，上限 %d 条，现 %d 条）：",
    RING_EMPTY = "落盘环是空的：先敲一次 /email 体检",
    CLEARED = "落盘环已清空（%d 条）",
    STATUS = "EH_Mail %s ｜ 上次体检 %s ｜ 缺 %s ｜ 环 %d 条",
    NEVER = "（从未）",
    NOCF = "CreateFrame 不可用 ⇒ 模板组判不出（其余组照常）",
    ERR = "内部错误：",
  },
  enUS = {
    USAGE = "Usage: /email (probe) | /email dump | /email status | /email clear",
    HEAD = "Probe: %d checked ｜ %d missing",
    OK = "★All present: none of the %d client names is missing (risks R1-R4 all clear)",
    MISS = "Missing: %s",
    MISS_MORE = "%s ... %d total",
    OVER = "★Region index out of range: %s (the upstream addon indexes GetRegions()[N] with no guard)",
    RELOAD = "auto /reload in %d s to save ｜ %d temporary probe frames (all hidden)",
    MANUAL = "RunScript / GetTime unavailable ⇒ results are in the saved table; please /reload manually",
    RING_HEAD = "Ring (newest last, cap %d, now %d):",
    RING_EMPTY = "Ring is empty: run /email first",
    CLEARED = "Ring cleared (%d lines)",
    STATUS = "EH_Mail %s ｜ last probe %s ｜ missing %s ｜ ring %d",
    NEVER = "(never)",
    NOCF = "CreateFrame unavailable ⇒ template group undecidable (other groups still run)",
    ERR = "internal error: ",
  },
  ruRU = {
    USAGE = "Использование: /email (проверка) | /email dump | /email status | /email clear",
    HEAD = "Проверка: %d ｜ нет %d",
    OK = "★Всё найдено: ни одного из %d имён не отсутствует (риски R1-R4 сняты)",
    MISS = "Отсутствует: %s",
    MISS_MORE = "%s ... всего %d",
    OVER = "★Индекс региона вне диапазона: %s (в исходном аддоне GetRegions()[N] берётся без проверки)",
    RELOAD = "авто /reload через %d с ｜ временных кадров: %d (все скрыты)",
    MANUAL = "RunScript / GetTime недоступны ⇒ данные в таблице; сделайте /reload вручную",
    RING_HEAD = "Кольцо (новое в конце, лимит %d, сейчас %d):",
    RING_EMPTY = "Кольцо пусто: сначала /email",
    CLEARED = "Кольцо очищено (%d строк)",
    STATUS = "EH_Mail %s ｜ проверка %s ｜ нет %s ｜ кольцо %d",
    NEVER = "(никогда)",
    NOCF = "CreateFrame недоступен ⇒ группа шаблонов не определена (остальные группы работают)",
    ERR = "внутренняя ошибка: ",
  },
}

local LOC = "zhCN"

local function pickLocale()
  if type(GetLocale) == "function" then
    local ok, v = pcall(GetLocale)
    if ok and type(v) == "string" and v ~= "" and T[v] then return v end
  end
  return "zhCN"
end

local function L(key, ...)
  local t = T[LOC] or T.zhCN
  local s = t[key]
  if s == nil then s = T.zhCN[key] end
  if s == nil then return tostring(key) end
  if select("#", ...) == 0 then return s end
  local ok, f = pcall(string.format, s, ...)
  if ok and type(f) == "string" then return f end
  return s
end

-- ============================================================
-- 说话出口（唯一）：命令回显 = 玩家主动问的 ⇒ 走强制可见口
-- ============================================================
local function rawSay(msg)
  local cf = rawget(_G, "DEFAULT_CHAT_FRAME")
  if type(cf) == "table" and type(cf.AddMessage) == "function" then
    pcall(cf.AddMessage, cf, "|cff66ccff[EH_Mail]|r " .. tostring(msg))
  end
end

local function say(msg)
  local text = "[EH_Mail] " .. tostring(msg)
  if type(EVAL_SAY_FORCE) == "function" then
    local ok = pcall(EVAL_SAY_FORCE, text)
    if ok then return end
  end
  rawSay(msg)
end

-- ============================================================
-- 自己的存档（记忆体分离：只碰 EH_MAIL_CFG）
-- ============================================================
local function cfg()
  local c = rawget(_G, "EH_MAIL_CFG")
  if type(c) ~= "table" then
    c = {}
    rawset(_G, "EH_MAIL_CFG", c)
  end
  if type(c.probe) ~= "table" then c.probe = {} end
  if type(c.ver) ~= "string" then c.ver = EH_MAIL_BUILD end
  return c
end

-- 有界环写入（最新在后；超上限丢最老的）
local function ringAdd(line)
  local c = cfg()
  local r = c.probe
  table.insert(r, tostring(line))
  local n = table.getn(r)
  while n > RING_MAX do
    table.remove(r, 1)
    n = n - 1
  end
  c.probeN = n
end

local function ringClear()
  local c = cfg()
  local n = table.getn(c.probe)
  c.probe = {}
  c.probeN = 0
  return n
end

-- ============================================================
-- 被体检的名字表（分类 = 判据；名单来源 = `tmp/tm_probe_names.txt` **人工去噪后**的客户端侧名字）
--   加/减条目请同时改这份名单与 `tmp/tm_probe_names.js` 的抽取口径
-- ============================================================
-- FUNC：FrameXML 全局函数（前 10 个 = TurtleMail **挂钩**的那 10 个 ⇒ R1 要害）
local G_FUNC = {
  "InboxFrame_OnClick", "InboxFrame_Update", "InboxFrameItem_OnEnter",
  "MailFrameTab_OnClick", "OpenMail_Reply", "OpenMailFrame_OnHide",
  "SendMailFrame_CanSend", "SendMailFrame_Update", "SendMailRadioButton_OnClick",
  "UpdateUIPanelPositions",
  "CloseDropDownMenus", "ToggleDropDownMenu",
  "UIDropDownMenu_AddButton", "UIDropDownMenu_Initialize", "UIDropDownMenu_SetText", "UIDropDownMenu_SetWidth",
  "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab",
  "MoneyFrame_Update", "MoneyInputFrame_GetCopper", "MoneyInputFrame_ResetMoney", "MouseIsOver",
}
-- FRAME：客户端提供的具名帧（TurtleMail 按名字直接 SetPoint/Show/Hide/GetRegions）
local G_FRAME = {
  "MailFrame", "InboxFrame", "SendMailFrame", "OpenMailFrame",
  "MailFrameTab1", "MailFrameTab2",
  "MailFrameTopLeft", "MailFrameTopRight", "MailFrameBotLeft", "MailFrameBotRight",
  "InboxTitleText", "InboxCloseButton", "InboxPrevPageButton", "InboxNextPageButton", "InboxCurrentPage",
  "MailItem1", "MailItem2", "MailItem3", "MailItem4", "MailItem5", "MailItem6", "MailItem7",
  "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox",
  "SendMailMoney", "SendMailMoneyGold", "SendMailMoneyText",
  "SendMailCODButton", "SendMailPackageButton", "SendMailMailButton",
  "SendMailScrollFrame", "SendMailScrollChildFrame", "SendMailSendMoneyButton",
  -- ★`SendMailStationeryButton` 已按真机读数移出名单：它在客户端确实不存在，但 **TurtleMail 源码零引用**（只有
  -- `StationeryBackgroundLeft/Right` 那两个背景纹理，实测都在）⇒ 留在名单里只会让每轮体检常驻一条「缺 1 项」的
  -- 噪音、把真正的缺口淹掉。事实记在 `CLAUDE.md` 与调研报告，不占探针名额。
  "SendMailCostMoneyFrame",
  "StationeryBackgroundLeft", "StationeryBackgroundRight",
  "OpenMailDepositMoneyFrame", "OpenMailMoneyButton", "OpenMailPackageButton", "OpenMailReplyButton",
  "OpenMailBodyText", "OpenMailSender", "OpenMailSubject", "OpenMailScrollFrame", "OpenMailInvoiceFrame",
}
-- MISC：辅助全局（表 / 常显帧）
local G_MISC = {
  "DEFAULT_CHAT_FRAME", "GameTooltip", "SlashCmdList", "TradeFrame",
  "UIPanelWindows", "UISpecialFrames", "WorldFrame",
}
-- CONST：全局字符串常量（缺一个通常只影响一行文案；ITEM_OPENABLE / INBOXITEMS_TO_DISPLAY 参与逻辑判定）
local G_CONST = {
  "AMOUNT_TO_SEND", "COD_AMOUNT", "EMPTY", "INBOX", "INBOXITEMS_TO_DISPLAY", "ITEM_OPENABLE", "NO_ATTACHMENTS",
  "ERROR_CAPS", "GRAY_FONT_COLOR", "NORMAL_FONT_COLOR",
  "ERR_INV_FULL", "ERR_ITEM_MAX_COUNT", "ERR_MAIL_REACHED_CAP", "ERR_MAIL_TARGET_NOT_FOUND",
  "ERR_MAIL_TO_SELF", "ERR_PLAYER_WRONG_FACTION",
  "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
  "AUCTION_OUTBID_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT",
}
-- FONT：字体对象（_G 上的 Font 对象）
local G_FONT = {
  "GameFontNormal", "GameFontHighlight", "GameFontDisable", "GameFontDisableSmall", "NumberFontNormal",
}
-- PARENT：`$parent` 派生名（静态 grep 天生看不见；只可能运行期存在）
--   · MailItem1Button ← `MailItemTemplate` 的 `name="$parentButton"`（能命中 = 客户端 XML 真的建了那 7 格）
--   · SendMailMoneySilver / Copper / *Right ← `MoneyInputFrameTemplate` / 金额框模板的 `$parent*`
local G_PARENT = {
  "MailItem1Button",
  "SendMailMoneySilver", "SendMailMoneyCopper",
  "SendMailMoneyGoldRight", "SendMailMoneySilverRight", "SendMailMoneyCopperRight",
  "SendMailNameEditBoxMiddle", "SendMailNameEditBoxRight",
}
-- TEMPLATE：XML 模板（探法 = `pcall(CreateFrame, "Frame", nil, UIParent, 模板名)` 成功即模板在）
local G_TEMPLATE = {
  "UIPanelButtonTemplate", "UIPanelScrollFrameTemplate", "UIDropDownMenuTemplate",
  "OptionsCheckButtonTemplate", "FriendsFrameTabTemplate",
}
-- REGIONS：区域计数 +「TurtleMail 要取的那个下标可及否」
-- ★★这一组**不计数**（不进 total/miss，单独成段），但它才是「移植会不会当场红字」的判据：
--   源码里 `({ f:GetRegions() })[N]` 一律是**裸索引、没有 pcall** ⇒ N 越界就是 nil 索引 = 运行期报错。
--   条目 = { 名字, 源码实际取用的最大下标 }；下标 0 = 源码只调几何/不读 region。
--   实锚（TurtleMail.lua）：SendMailPackageButton[1][3]（:580/:582）· SendMailScrollFrame[3]（:1858）
--                         · SendMailMoneyGold/Silver/Copper[9]（:2097/:2101/:2105）
--   ★「名字在」≠「下标够」—— 两者必须分开看（真机首轮就是靠这一组才抓到 `[9] > N=4`）。
local G_REGIONS = {
  { "SendMailMoney", 0 },
  { "SendMailMoneyGold", 9 },
  { "SendMailMoneySilver", 9 },
  { "SendMailMoneyCopper", 9 },
  { "SendMailPackageButton", 3 },
  { "SendMailScrollFrame", 3 },
}

-- ============================================================
-- 唯一节拍帧（前向声明 + 定义处赋值；有待办才挂，执行完当场真摘）
-- ★所有节拍相关的 local 必须在**任何引用它们的函数之前**声明 —— 否则引用点绑全局 nil（本项目 R2 老雷）
-- ============================================================
local tickFrame
local tickOn = false
local reloadAt
local onTick
local tickSync

local function frameGet()
  if tickFrame then return tickFrame end
  if type(CreateFrame) ~= "function" then return nil end
  local ok, f = pcall(CreateFrame, "Frame", "EH_MailTick")
  if not ok or (type(f) ~= "table" and type(f) ~= "userdata") then return nil end
  tickFrame = f
  return tickFrame
end

onTick = function()
  if reloadAt == nil then
    tickSync()
    return
  end
  if type(GetTime) ~= "function" then return end
  if GetTime() >= reloadAt then
    reloadAt = nil
    tickSync()
    pcall(RunScript, "ReloadUI()")
  end
end

tickSync = function()
  local f = frameGet()
  if f == nil then return end
  local need = (reloadAt ~= nil)
  if need and not tickOn then
    if type(f.SetScript) == "function" then
      pcall(f.SetScript, f, "OnUpdate", onTick)
      tickOn = true
    end
  elseif (not need) and tickOn then
    if type(f.SetScript) == "function" then
      pcall(f.SetScript, f, "OnUpdate", nil)
      tickOn = false
    end
  end
end

-- ============================================================
-- 探针（纯只读）
-- ============================================================
local tmpFrames = 0

local function probeGlobal(name)
  local v = rawget(_G, name)
  if v == nil then return false, "nil" end
  return true, type(v)
end

local function probeFunc(name)
  local v = rawget(_G, name)
  if type(v) == "function" then return true, "function" end
  if v == nil then return false, "nil" end
  return false, type(v)
end

-- 模板探针：建一个帧试 inherits；成功 = 模板在
-- ★这是本命令**唯一**的写动作（只建临时帧），1.12 没有销毁帧的 API ⇒ 当场 Hide + 不留引用
local function probeTemplate(name)
  if type(CreateFrame) ~= "function" then return nil, "noCreateFrame" end
  local parent = rawget(_G, "UIParent")
  local ok, f = pcall(CreateFrame, "Frame", nil, parent, name)
  if not ok then return false, "pcall-fail" end
  if type(f) == "table" or type(f) == "userdata" then
    if type(f.Hide) == "function" then pcall(f.Hide, f) end
    tmpFrames = tmpFrames + 1
    return true, "ok"
  end
  return nil, "undecided"
end

local function probeRegions(name)
  local o = rawget(_G, name)
  if o == nil then return nil end
  if type(o.GetRegions) ~= "function" then return nil end
  local ok, n = pcall(function()
    local t = { o:GetRegions() }
    return table.getn(t)
  end)
  if ok and type(n) == "number" then return n end
  return nil
end

local function stampNow()
  if type(date) ~= "function" then return "?" end
  local ok, d = pcall(date, "%Y-%m-%d %H:%M:%S")
  if ok and type(d) == "string" and d ~= "" then return d end
  return "?"
end

local function runProbe()
  local c = cfg()
  tmpFrames = 0
  local total, missN = 0, 0
  local missList = {}
  local lines = {}

  local function note(kind, name, ok, extra)
    total = total + 1
    if ok == true then
      table.insert(lines, string.format("%-8s %-34s OK   %s", kind, name, tostring(extra or "")))
    elseif ok == false then
      missN = missN + 1
      table.insert(missList, kind .. ":" .. name)
      table.insert(lines, string.format("%-8s %-34s MISS %s", kind, name, tostring(extra or "")))
    else
      table.insert(lines, string.format("%-8s %-34s ?    %s", kind, name, tostring(extra or "")))
    end
  end

  local i, n, name, ok, extra
  n = table.getn(G_FUNC)
  for i = 1, n do
    name = G_FUNC[i]
    ok, extra = probeFunc(name)
    note("FUNC", name, ok, extra)
  end
  n = table.getn(G_FRAME)
  for i = 1, n do
    name = G_FRAME[i]
    ok, extra = probeGlobal(name)
    note("FRAME", name, ok, extra)
  end
  n = table.getn(G_MISC)
  for i = 1, n do
    name = G_MISC[i]
    ok, extra = probeGlobal(name)
    note("MISC", name, ok, extra)
  end
  n = table.getn(G_CONST)
  for i = 1, n do
    name = G_CONST[i]
    ok, extra = probeGlobal(name)
    note("CONST", name, ok, extra)
  end
  n = table.getn(G_FONT)
  for i = 1, n do
    name = G_FONT[i]
    ok, extra = probeGlobal(name)
    note("FONT", name, ok, extra)
  end
  n = table.getn(G_PARENT)
  for i = 1, n do
    name = G_PARENT[i]
    ok, extra = probeGlobal(name)
    note("PARENT", name, ok, extra)
  end
  if type(CreateFrame) ~= "function" then
    table.insert(lines, string.format("%-8s %-34s ?    %s", "TEMPLATE", "-", L("NOCF")))
  else
    n = table.getn(G_TEMPLATE)
    for i = 1, n do
      name = G_TEMPLATE[i]
      ok, extra = probeTemplate(name)
      note("TEMPLATE", name, ok, extra)
    end
  end
  -- 区域组：名字在 ≠ 下标够 —— 源码是裸索引 `[N]`，N > cnt 就是运行期 nil 索引
  local overList = {}
  n = table.getn(G_REGIONS)
  for i = 1, n do
    local ent = G_REGIONS[i]
    name = ent[1]
    local need = ent[2] or 0
    local cnt = probeRegions(name)
    if cnt == nil then
      table.insert(lines, string.format("%-8s %-34s ?    判不出", "REGIONS", name))
    elseif need <= 0 then
      table.insert(lines, string.format("%-8s %-34s N=%d（源码不读 region）", "REGIONS", name, cnt))
    elseif cnt >= need then
      table.insert(lines, string.format("%-8s %-34s N=%d 要取[%d] 可及", "REGIONS", name, cnt, need))
    else
      table.insert(lines, string.format("%-8s %-34s N=%d 要取[%d] ★越界", "REGIONS", name, cnt, need))
      table.insert(overList, string.format("%s[%d]>%d", name, need, cnt))
    end
  end
  local overN = table.getn(overList)

  -- 结论进有界落盘环（AI 读存档用；环里不许有 nil）
  local stamp = stampNow()
  c.lastAt = stamp
  c.lastTotal = total
  c.lastMiss = missN
  c.lastOver = overN
  c.ver = EH_MAIL_BUILD
  c.tmpFrames = tmpFrames
  ringAdd("===== 体检 " .. stamp .. " ｜ 共 " .. total .. " 项 ｜ 缺 " .. missN .. " 项 ｜ build " .. EH_MAIL_BUILD)
  if missN > 0 then
    ringAdd("缺失：" .. table.concat(missList, ", "))
  end
  if overN > 0 then
    ringAdd("区域下标越界：" .. table.concat(overList, ", "))
  end
  for i = 1, table.getn(lines) do
    ringAdd(lines[i])
  end
  ringAdd("")

  -- 聊天只回 3 行（防刷屏；全量走 /email 明细）
  say(L("HEAD", total, missN))
  -- ★「缺名字」与「区域下标越界」是两类问题 ⇒ 各占一段、同一行，聊天行数恒 3
  local parts = {}
  if missN > 0 then
    local head, rest = {}, {}
    local capN = 8
    for i = 1, table.getn(missList) do
      if i <= capN then
        table.insert(head, missList[i])
      else
        table.insert(rest, missList[i])
      end
    end
    if table.getn(rest) > 0 then
      table.insert(parts, L("MISS", table.concat(head, ", ")) .. " ｜ " .. L("MISS_MORE", table.concat(rest, ", "), missN))
    else
      table.insert(parts, L("MISS", table.concat(head, ", ")))
    end
  end
  if overN > 0 then
    table.insert(parts, L("OVER", table.concat(overList, ", ")))
  end
  if table.getn(parts) == 0 then
    say(L("OK", total))
  else
    say(table.concat(parts, " ｜ "))
  end

  -- 延后自动 /reload（不是立刻：/reload 会清空聊天框，把刚打出来的结论当场抹掉）
  if type(RunScript) == "function" and type(GetTime) == "function" then
    reloadAt = GetTime() + RELOAD_SEC
    say(L("RELOAD", RELOAD_SEC, tmpFrames))
    tickSync()
  else
    say(L("MANUAL"))
  end
  return total, missN
end

-- ============================================================
-- 子命令
-- ============================================================
local function dumpRing()
  local c = cfg()
  local r = c.probe
  local n = table.getn(r)
  if n == 0 then
    say(L("RING_EMPTY"))
    return
  end
  say(L("RING_HEAD", RING_MAX, n))
  local i, line
  for i = 1, n do
    line = r[i]
    if line == nil then line = "" end
    rawSay(line)
  end
end

local function statusLine()
  local c = cfg()
  say(L("STATUS", EH_MAIL_BUILD, c.lastAt or L("NEVER"), tostring(c.lastMiss or "?"), table.getn(c.probe)))
end

local function trimStr(s)
  s = tostring(s or "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

local function runCommand(msg)
  local m = trimStr(msg)
  if m == "" or m == "体检" or m == "check" then
    runProbe()
  elseif m == "明细" or m == "dump" then
    dumpRing()
  elseif m == "状态" or m == "status" then
    statusLine()
  elseif m == "清" or m == "clear" then
    say(L("CLEARED", ringClear()))
  else
    say(L("USAGE"))
  end
end

function EH_MAIL_CMD(msg)
  local ok, err = pcall(runCommand, msg)
  if not ok then
    say(L("ERR") .. tostring(err))
  end
end

-- ============================================================
-- 载入期唯一的动作 = 注册斜杠命令
-- （零副作用：不建帧 / 不挂事件 / 不读写存档；帧与节拍都在**首用**时才建）
-- ============================================================
LOC = pickLocale()

if type(SlashCmdList) == "table" then
  SlashCmdList["EHMAIL"] = EH_MAIL_CMD
  SLASH_EHMAIL1 = "/email"
  SLASH_EHMAIL2 = "/eh邮件"
end
