-- EvalHelp · Toolbox.lua —— 工具箱（1.68.0 独立载入：配置窗 Tab3；商人/队伍社交/任务 自动化小工具）
-- 独立原则：本文件自绘 UI（复刻 cfgCheck/cfgHeader 风格），不改主程序任何函数；
-- 依赖仅全局件：EVAL_SAY（Core 桥）、EVAL_TN_OPEN（EvalHelp 回声行弹窗）、EVAL_RESOLVE_LANG/EVAL_LOCALES（i18n）。
-- 配置直读 EVAL_HELP_CONFIG.tb（SavedVariables 自动持久化；全部功能默认关，逐项勾选开启）。

local TB = { off = 0, rows = {}, ROWS = 13 }
-- ★1.73.11 两列版式的列数/列缝：**模块级常量放文件顶部**（DECL ORDER CHECK 会抓「用在前、声明在后」；
--   本轮实测：一开始放在刷新段旁边 → 被 CHECK 当场挡下，这就是那条检查的价值）
local TB_COLS = 2        -- 列数（用户要求两列；将来加第三列只需改这里，列宽/切点算法都是通用的）
local TB_COL_GAP = 24    -- 两列之间的缝
-- ★1.73.16 「玩家聊天」事件白名单（取证缓冲只留这些：战斗/法术刷屏会把真实聊天挤出去）
local TB_CHAT_EV_KEYS = {
  "SAY", "YELL", "PARTY", "RAID", "GUILD", "OFFICER", "CHANNEL", "WHISPER", "EMOTE", "TEXT_EMOTE",
}
-- ★★★1.73.20
-- **名字槽（arg2）不吃富文本 —— 8 位色码也被原样画出来**（用户截图逐字放大定案：
--   「[1. 综合] [|cfff58cbaIonol|r]: 1」；而同一屏里经 AddMessage 打印的 8 位码是**有色**的）。
--   ⇒ 现在**绝不回写 arg2**：宁可不染色，也**不许在玩家聊天里显示颜色码原文**（那是可见的破坏，
--      比不染色糟得多）。认得出来的名字照旧计数（诊断里能看到），只是「暂不回写」。
--   ★等方案定了（吞掉客户端那行自己拼 / 试出可用的写法）再把这里打开。
local TB_NAMECOLOR_WRITE = false
-- ★**字符数**而不是字节数：UTF-8 里一个中文字是 3 字节 —— 用 string.len 判「单字名」
--   会把「甲」当成 2 个字符放过去（本项目反复踩过的「string.len 是字节数」）。判据 = 数首字节。
--   ★1.73.17 从「名字缓存」段**上移到文件顶部**：聊天取参（更早的代码）也要用它 ——
--     局部队变量必须声明在**使用之前**（本轮实测：调用到全局 nil → attempt to call a nil value）。
local function tbNameCharLen(s)
  local n = 0
  local len = (type(s) == "string") and string.len(s) or 0
  for i = 1, len do
    local b = string.byte(s, i)
    -- ASCII（<0x80）与 UTF-8 首字节（>=0xC0）各算一个字符；续字节 0x80..0xBF 不数
    if b and (b < 128 or b >= 192) then n = n + 1 end
  end
  return n
end

-- ★★★1.73.18 名字 → 职业 token 缓存**上移到文件顶部**：聊天入口（更早的代码）要读它；
--   局部队变量必须声明在**使用之前**（本轮两次实测：直接引用后段的 local → 拿到全局 nil →
--   attempt to call a nil value）。单一真值：写入点只有 tbNameClassPut。
local tbNameClass = {}
local function tbNameClassKey(name)
  if type(name) ~= "string" then return nil end
  local s = string.gsub(name, "^%s*(.-)%s*$", "%1")
  if s == "" then return nil end
  s = string.lower(s)
  local dash = string.find(s, "-", 1, true)
  if dash and dash > 1 then s = string.sub(s, 1, dash - 1) end
  if tbNameCharLen(s) < 2 then return nil end
  return s
end
local function tbNameClassPut(name, klass)
  local k = tbNameClassKey(name)
  if not k then return false end
  local tok = EVAL_TB_PAINT_CLASS_TOKEN_OF(klass)
  if not tok then return false end
  tbNameClass[k] = tok
  return true
end
local function tbNameClassGet(name)
  local k = tbNameClassKey(name)
  if not k then return nil end
  return tbNameClass[k]
end
function EVAL_TB_NAMECLASS_PUT(n, k) return tbNameClassPut(n, k) end
function EVAL_TB_NAMECLASS_GET(n) return tbNameClassGet(n) end
function EVAL_TB_NAMECLASS_SIZE()
  local n = 0
  for _ in pairs(tbNameClass) do n = n + 1 end
  return n
end

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

-- ★★★1.73.30 组标题栏：**宽度自适应本列**（用户：「工具箱 内项目标题栏宽度自适应」）
--   语言包里的标题自带装饰（「—— 任务·通知 ——」）→ 这里把装饰**剥掉**再**按本列宽补足**，
--   拼成「———— 任务·通知 ————」的分隔条：列宽变了（两列/单列）标题栏跟着变，不再是一串死字数。
--   ★两个坑：① 「—」是 U+2014（UTF-8 三字节）→ **绝不能塞进 Lua 字符集**（本项目铁律），
--     用 string.char(226,128,148) 构造后再 string.sub 比较；② 本机拿不到 GetStringWidth →
--     用既有近似「字符数 × 11px」。
local TB_HDR_DASH = string.char(226, 128, 148)
local function tbHdrStrip(s)
  s = string.gsub(tostring(s or ""), "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  while string.sub(s, 1, 1) == "-" or string.sub(s, 1, 3) == TB_HDR_DASH do
    if string.sub(s, 1, 3) == TB_HDR_DASH then s = string.sub(s, 4) else s = string.sub(s, 2) end
    s = string.gsub(s, "^%s+", "")
  end
  while true do
    local n = string.len(s)
    if n >= 3 and string.sub(s, n - 2, n) == TB_HDR_DASH then
      s = string.sub(s, 1, n - 3)
    elseif n >= 1 and string.sub(s, n, n) == "-" then
      s = string.sub(s, 1, n - 1)
    else
      break
    end
    s = string.gsub(s, "%s+$", "")
  end
  return s
end
-- 纯函数：标题 + 列宽 → 分隔条文本（渲染与断言**共用这一份**）
local TB_HDR_PER = 11 -- 一个汉字/破折号约 11px（本机拿不到 GetStringWidth 的既有近似）
local function tbHdrEst(s) return tbNameCharLen(tostring(s or "")) * TB_HDR_PER end
-- 读值口：估算宽度（**与生产同一个口径**；断言不许自己另写一套估算）
function EVAL_TEST_TB_HDR_EST(s) return tbHdrEst(s) end
function EVAL_TB_HDR_TEXT(label, colW)
  local title = tbHdrStrip(label)
  local w = tonumber(colW) or 300
  local per = TB_HDR_PER
  local need = tbHdrEst(title) + 2 * per -- 标题 + 两侧各一个空格
  local room = math.floor((w - 8 - need) / 2)
  local n = math.floor(room / per)
  if n < 2 then n = 2 end
  local d = string.rep(TB_HDR_DASH, n)
  return d .. " " .. title .. " " .. d
end
-- 读值口：某个组标题**渲染出来的真文本**（断言与 UI 同源；标题行按 label 找）
function EVAL_TEST_TB_HDR_TEXT(label)
  local want = tostring(label or "")
  for k = 1, TB.ROWS * (TB.cols or TB_COLS) do
    local r = TB.rows[k]
    if r and r.hdr and r.item and r.item.t == "h" and tostring(r.item.label) == want then
      local ok, t = pcall(r.hdr.GetText, r.hdr)
      return (ok and tostring(t or "")) or ""
    end
  end
  return nil
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

-- ★★★1.74.20 「哪些键**按角色存**」——**唯一来源**（用户：「消耗品助手 + 喂食助手 + 骑乘助手整块按角色）。
--   背景（本轮审计定案）：三个助手的配置原先都躺在**账号级**的 `EVAL_HELP_CONFIG.tb` 里 ——
--   同一账号下所有角色共用一份「带什么食物 / 选哪些消耗品 / 图标摆哪」，换个号就得重设一遍。
--   本机客户端实测支持 `## SavedVariablesPerCharacter`（UnrealQuest 已在用，磁盘上三个角色三个文件），
--   故新增角色级存档 `EVAL_HELP_CHAR`，把这三个助手**整块**（含各自的悬浮件位置与贴图缓存）搬过去。
--   ★为什么整块搬（连开关 `consumable`/`feedPet`/`dismount` 一起）：用户要的是「这些配置区分角色」，
--     只搬一半会出现「角色 A 关掉喂食、角色 B 也被关掉」这种自相矛盾的状态。
--   ★**方案库 `cfg.war.profiles` 不搬**（它是资产、要跨角色复用与分享）；语言/日志/分享开关也不搬。
--   ★怎么生效：`tbCfg()` 返回一个**路由代理**（见下），读/写角色键自动落到 `EVAL_HELP_CHAR.tb`，
--     账号键照旧落 `EVAL_HELP_CONFIG.tb` —— 于是**所有既有调用点一个字都不用改**。
--     （验过全项目没有 `pairs(配置表)` 遍历：代理表唯一的已知短板用不上。）
local TB_CHAR_KEYS = {
  -- 消耗品助手（选中列表 / 贴图缓存 / 总开关 / 悬浮件位置）
  chUse = true, chTex = true, consumable = true, chX = true, chY = true,
  -- 猎人助手 · 一键喂食
  feedPet = true, hhFood = true, hhFoodTex = true, hhSpell = true, hhX = true, hhY = true,
  -- 骑乘助手 · 一键下马
  dismount = true, dismountAuto = true, dhX = true, dhY = true,
}
-- 读值口：这个键是不是角色级（断言与源码检查读它，不另抄一份名单）
function EVAL_TB_IS_CHAR_KEY(k) return TB_CHAR_KEYS[k] == true end
-- 读值口：整张角色键清单（按名字排序，便于断言逐个核对）
function EVAL_TB_CHAR_KEY_LIST()
  local out = {}
  for k in pairs(TB_CHAR_KEYS) do out[#out + 1] = k end
  table.sort(out)
  return out
end
-- ★角色级存档的访问口（三个助手与路由代理都走它）——**它只管建表，不管迁移**（迁移见 EVAL_TB_CHAR_MIGRATE）
function EVAL_TB_CHAR_STORE()
  local cc = rawget(_G, "EVAL_HELP_CHAR")
  if type(cc) ~= "table" then cc = {} EVAL_HELP_CHAR = cc end
  if type(cc.tb) ~= "table" then cc.tb = {} end
  return cc.tb
end
-- ★★★迁移（**每个角色只做一次**）：老存档里这些键在账号表 `cfg.tb` 里，第一次登录时**继承一次**当起点。
--   ★账号里那份副本**不删**：它是「升级前那份共享配置」的种子 —— 删了，还没登录过的角色就什么都没有了
--     （UnrealQuest 的 per-character 迁移也是这么做的，并写明了同样的理由）。
--   ★迁移**只在 VARIABLES_LOADED 之后调**（EvalHelp.lua 的事件里）：那时账号表才真的读进来；
--     提前调用会从一张还没加载的空表「继承」出空配置、却把 migrated 标志立上，seed 就永久丢了。
function EVAL_TB_CHAR_MIGRATE()
  local cc = rawget(_G, "EVAL_HELP_CHAR")
  local acct = rawget(_G, "EVAL_HELP_CONFIG")
  if type(acct) ~= "table" then return false end -- 账号配置还没到位 → **不标记**，等下次（VARIABLES_LOADED）再来
  if type(cc) ~= "table" then cc = {} EVAL_HELP_CHAR = cc end
  if type(cc.tb) ~= "table" then cc.tb = {} end
  if cc.tbMigrated then return false end
  cc.tbMigrated = true
  local at = acct.tb
  if type(at) == "table" then
    for k in pairs(TB_CHAR_KEYS) do
      if cc.tb[k] == nil and at[k] ~= nil then cc.tb[k] = at[k] end
    end
  end
  return true
end
-- 清空角色级配置（诊断/测试用；**不给玩家入口**）
function EVAL_TB_CHAR_RESET()
  local cc = rawget(_G, "EVAL_HELP_CHAR")
  if type(cc) ~= "table" then return false end
  cc.tb = {}
  return true
end
-- ★★★路由代理：`tbCfg()` 的返回值。读/写**角色键**落到 EVAL_HELP_CHAR.tb，其余落账号表。
--   ★为什么要代理而不是「把每个调用点都改一遍」：生产里 tb.* 的读写有上百处（UI 渲染、行模型、
--     拖拽记忆…），逐处改既容易漏又必然引入回归；代理让**调用点一个字不动**，路由只有一份实现。
--   ★代理表**绝不进存档**（它只是读写入口，真正落盘的是那两个普通表）。
local tbRouter
local function tbCfgAccount()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  if type(c.tb) ~= "table" then c.tb = {} end
  return c.tb
end
local function tbMakeRouter()
  if tbRouter then return tbRouter end
  tbRouter = setmetatable({}, {
    __index = function(_, k)
      if TB_CHAR_KEYS[k] then return EVAL_TB_CHAR_STORE()[k] end
      local at = tbCfgAccount()
      if not at then return nil end
      -- ★★绝不能写 `return at and at[k] or nil`：Lua 里 `false or nil` **还是 nil** ——
      --   于是所有「值本身就是 false」的账号开关（chanJoin / colorClass / wdebug…）经代理读出来全变成 nil，
      --   调用方一律按默认值处理 → **用户关掉的开关自己又开了**。
      --   本轮实测：组 79 的「开关关掉后判据读到的就是关」当场 got=true（这正是本项目
      --   「`cond and f() or fallback` 在 f() 返 false 时恒取 fallback」那条老坑的同一个形状）。
      return at[k]
    end,
    __newindex = function(_, k, v)
      if TB_CHAR_KEYS[k] then EVAL_TB_CHAR_STORE()[k] = v return end
      local at = tbCfgAccount()
      if at then at[k] = v end
    end,
  })
  return tbRouter
end
-- 读值口：路由代理本体（断言用它验证「同一个键写到哪张表」）
function EVAL_TB_ROUTER() return tbMakeRouter() end

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
  -- ★1.74.13 任务通知频道**多选**（用户要求：「下拉需要支持多选，优先级 队伍>说>自己」）：
  --   旧格式 qchan = "off"/"self"/"say"/"party" 单值字符串 → 集合表 { self=, say=, party= }（只搬一次）。
  --   ★只留一份真值（1.71.2 同一纪律）：搬完字符串形态不复存在；nil/空表 = 关闭。
  if type(c.tb.qchan) == "string" then
    if c.tb.qchan == "off" then c.tb.qchan = nil
    else c.tb.qchan = { [c.tb.qchan] = true } end
  end
  -- ★1.71.3 频道进出信息屏蔽：**默认开**（用户要求）。nil 也视为开（见 EVAL_TB_CHAN_ON）。
  if c.tb.chanJoin == nil then c.tb.chanJoin = true end
  -- ★1.74.0 拦截关键字：chanKeyOff = 被用户**停用**的预设词（默认全开，新预设自动生效）；
  --   chanKeyCustom = 用户自己输入的关键字（有序数组，可带 `!` 前缀 = 单独生效）
  if type(c.tb.chanKeyOff) ~= "table" then c.tb.chanKeyOff = {} end
  if type(c.tb.chanKeyCustom) ~= "table" then c.tb.chanKeyCustom = {} end
  -- ★1.73.10 角色名职业着色：nil 也视为开（用户要求加的功能，装上就生效；取消勾选 = 不叠色）
  if c.tb.colorClass == nil then c.tb.colorClass = true end
  -- ★1.73.12 聊天窗名字着色：同上默认开（引擎侧与窗口着色共用同一份名字缓存）
  if c.tb.chatColor == nil then c.tb.chatColor = true end
  -- ★1.73.12 未缓存角色的主动查询：用户要求**默认开启**（工具箱里可关）
  if c.tb.whoQuery == nil then c.tb.whoQuery = true end
-- ★1.73.24 用户要求：右键聊天名字 → 公会邀请 / 复制名字 / /s 说出名字（默认开）
if c.tb.nameMenu == nil then c.tb.nameMenu = true end
  tbMigrateBuy(c.tb) -- ★1.71.3 自动购买：老条目补 每次数量/启用 字段
  -- ★★★1.74.20 返回**路由代理**（不是 c.tb 本身）：角色键（三个助手）自动落到 EVAL_HELP_CHAR.tb，
  --   账号键落上面这张 c.tb —— 于是上百处 `tb.xxx` 的既有调用点**一个字都不用改**。
  --   ★注意：上面这一串迁移只动**账号**键，与角色键无关（别把 c.tb 当成了全部配置）。
  return tbMakeRouter()
end
-- ★1.73.12 聊天窗挂载点清单（「频道进出屏蔽」与「聊天名字着色」**共用**同一个包装体）：
--   · 真客户端里 DEFAULT_CHAT_FRAME 与 ChatFrame1 常常是**同一个对象** → 不能按名字去重，
--     只能按「当前入口是不是我们挂的那一层」判幂等（见 EVAL_TB_CHAN_INSTALL_ONE）；
--   · ChatFrame2..N 由 FrameXML 懒建 → 除了载入时挂一次，还由限频重试**补挂**（见 tbChanRetry）；
--   · 为什么不止挂主窗口：用户要的「聊天窗内的名字着色」与既有「频道进出屏蔽」都该覆盖**所有**聊天窗
--     （旧版只挂了 DEFAULT_CHAT_FRAME → 2 号窗以后照旧冒通知、名字也不上色）。
local function tbChatFrameKeys()
  local keys = { "DEFAULT_CHAT_FRAME", "ChatFrame1" }
  local n = (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS > 0) and NUM_CHAT_WINDOWS or 7
  for i = 2, n do table.insert(keys, "ChatFrame" .. i) end
  return keys
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
--   ★★★状态更新（用户实测「我们那套没法实际工作」→ 两次审计定案）：
--     判据**改为事件名优先**（EVAL_TB_CHAN_EVENT：CHAT_MSG_CHANNEL_NOTICE = 你自己进出的回执，
--     + CHAT_MSG_CHANNEL_JOIN/LEAVE =「[玩家名] 加入/离开频道」；用户定稿**两种都拦**），
--     在第二入口 ChatFrame_OnEvent 里**先按事件名拦**；
--     下面的文本判据（WORDS×MOVES）**降级为兜底**（通知若走自定义事件名，文本还能兜一层）；
--     官方消息组（1.73.12 的 ① 号路）保留为客户端级另一道。
-- ★★★1.74.0 起：关键字**用户可配置**（工具箱 → 队伍/社交 → 该行右侧「关键字(N)」按钮 → 多选下拉 + 输入框）。
--   分组固定为两组（下拉里用**不可点的组标题行**分隔，与地图标注/条件菜单同一范式）：
--     · 频道词：消息里必须出现其中之一（这是「不误吞玩家聊天」的那道保险）
--     · 动作词：出现其中之一才算「进出通知」
--     · 自定义词（用户输入框加进来的）：与动作词同类 —— **同时**要满足频道词；
--       ★想让某个词**单独生效**（不必带频道词），在它前面加 `!`（例：`!刷屏`）——
--         这是给用户的"强词"出口，默认不给，免得一句普通聊天被一个宽泛的词吞掉。
local TB_CHAN_KEY_GROUPS = {
  { gkey = "TB_CHANKEY_G_CHAN", words = { "频道", "頻道", "channel", "канал" } }, -- ★1.71.3 加繁中「頻道」
  { gkey = "TB_CHANKEY_G_MOVE", words = {
    -- ★★1.71.3 补「进入」：真实文案是「[4. 世界防务] **进入**频道。」，旧表只有「加入」→ 那一半根本没匹配上。
    --   ★教训：判据表要**照着客户端真实文案抄**，差一个字就是半个功能失效（现已可由用户自行增删）。
    "加入", "进入", "离开", "退出",               -- zhCN
    "進入", "離開",                                -- 繁中（「加入/退出」繁简同形，不重复列）
    "joined", "left", "entered", "you have joined", "you have left", -- enUS
    "присоединил", "покинул",                     -- ruRU（尽力而为，靠 /eh go 频道 的样本再校准）
  } },
}

-- 被停用的关键字（cfg.tb.chanKeyOff[词] = true）；**默认全启用**（新加的预设词自动是开的）
local function tbChanKeyOff()
  local tb = tbCfg()
  local off = tb and tb.chanKeyOff
  if type(off) ~= "table" then return {} end
  return off
end
-- 生效的关键字（分组返回）：UI 摘要、判据、断言共用这一份
function EVAL_TB_CHAN_KEYS()
  local off = tbChanKeyOff()
  local out = { chan = {}, move = {}, custom = {} }
  for i = 1, table.getn(TB_CHAN_KEY_GROUPS) do
    local g = TB_CHAN_KEY_GROUPS[i]
    local dst = (i == 1) and out.chan or out.move
    for j = 1, table.getn(g.words) do
      local w = g.words[j]
      if not off[w] then table.insert(dst, w) end
    end
  end
  local tb = tbCfg()
  local cu = tb and tb.chanKeyCustom
  if type(cu) == "table" then
    for i = 1, table.getn(cu) do
      local raw = tostring(cu[i] or "")
      if raw ~= "" and not off[raw] then
        local alone = (string.sub(raw, 1, 1) == "!")
        local w = alone and string.sub(raw, 2) or raw
        if w ~= "" then table.insert(out.custom, { word = w, alone = alone, raw = raw }) end
      end
    end
  end
  return out
end

-- 纯函数：这条聊天文本是不是「频道进出通知」（UI、断言、诊断命令共用同一份判据）
function EVAL_TB_CHAN_BLOCK(msg)
  if type(msg) ~= "string" or msg == "" then return false end
  local lo = string.lower(msg)
  local k = EVAL_TB_CHAN_KEYS()
  local function hit(list)
    for i = 1, table.getn(list) do
      if string.find(lo, string.lower(list[i]), 1, true) ~= nil then return true end
    end
    return false
  end
  -- ① 自定义「强词」（`!` 前缀）：命中即拦（用户显式要求这类词单独生效）
  for i = 1, table.getn(k.custom) do
    local c = k.custom[i]
    if c.alone and string.find(lo, string.lower(c.word), 1, true) ~= nil then return true end
  end
  -- ② 频道词（保险）：没有频道词 → 不拦（避免把玩家一句普通聊天吞掉）
  if not hit(k.chan) then return false end
  -- ③ 动作词 或 自定义词
  if hit(k.move) then return true end
  for i = 1, table.getn(k.custom) do
    local c = k.custom[i]
    if not c.alone and string.find(lo, string.lower(c.word), 1, true) ~= nil then return true end
  end
  return false
end

-- ===== 拦截关键字：下拉多选 + 输入框（1.74.0 用户要求）=====
-- ★控件选型（都用项目已有的全局件，不新造）：
--   · **多选下拉** = EVAL_DD_OPEN(..., { multi = true, selected = sel, locked = locked })
--     —— 点一项切换、**面板不关**（地图标注/图标类别就是这么做的）。
--   · **输入框** = 同一个下拉的 search=true：面板顶部就是输入框（输入即过滤），
--     列表里出现「✎ 使用输入的文本」那一行 → 点击即把该词加进自定义关键字（onFreeText）。
--   · 组标题（频道词/动作词/自定义）= locked 行（不画方框、点击无反应）。
-- 生效词数（行右侧按钮的文字）：三组之和
function EVAL_TB_CHANKEY_SUMMARY()
  local k = EVAL_TB_CHAN_KEYS()
  local n = table.getn(k.chan) + table.getn(k.move) + table.getn(k.custom)
  return string.format(L("TB_CHANJOIN_KEYS_FMT"), n), n
end
-- 下拉内容：items / locked / selected / map（map[序号] 描述该项是什么动作）
function EVAL_TB_CHANKEYS_MENU()
  local off = tbChanKeyOff()
  local items, locked, sel, map = {}, {}, {}, {}
  for i = 1, table.getn(TB_CHAN_KEY_GROUPS) do
    local g = TB_CHAN_KEY_GROUPS[i]
    table.insert(items, L(g.gkey))
    locked[table.getn(items)] = true
    for j = 1, table.getn(g.words) do
      local w = g.words[j]
      table.insert(items, w)
      local pi = table.getn(items)
      map[pi] = { kind = "preset", word = w }
      if not off[w] then sel[pi] = true end
    end
  end
  local tb = tbCfg()
  local cu = (tb and tb.chanKeyCustom) or {}
  if type(cu) == "table" and table.getn(cu) > 0 then
    table.insert(items, L("TB_CHANKEY_G_CUSTOM"))
    locked[table.getn(items)] = true
    for i = 1, table.getn(cu) do
      local raw = tostring(cu[i] or "")
      if raw ~= "" then
        table.insert(items, raw)
        local pi = table.getn(items)
        map[pi] = { kind = "custom", word = raw }
        if not off[raw] then sel[pi] = true end
      end
    end
    table.insert(items, L("TB_CHANKEY_CLEAR"))
    map[table.getn(items)] = { kind = "clear" }
  end
  return items, locked, sel, map
end
-- 加一个自定义关键字（输入框那条路；去重、去空白；返回 true = 已加入或已存在）
function EVAL_TB_CHANKEY_ADD(txt)
  local word = tostring(txt or "")
  word = string.gsub(word, "^%s+", "")
  word = string.gsub(word, "%s+$", "")
  if word == "" then return false end
  local tb = tbCfg()
  if not tb then return false end
  if type(tb.chanKeyCustom) ~= "table" then tb.chanKeyCustom = {} end
  if type(tb.chanKeyOff) ~= "table" then tb.chanKeyOff = {} end
  local low = string.lower(word)
  for i = 1, table.getn(tb.chanKeyCustom) do
    if string.lower(tostring(tb.chanKeyCustom[i])) == low then
      tb.chanKeyOff[word] = nil -- 已存在 → 视为「重新启用」
      if type(EVAL_TB_REFRESH) == "function" then EVAL_TB_REFRESH() end
      return true
    end
  end
  table.insert(tb.chanKeyCustom, word)
  if type(EVAL_TB_REFRESH) == "function" then EVAL_TB_REFRESH() end
  return true
end
-- 清空自定义关键字
function EVAL_TB_CHANKEY_CLEAR()
  local tb = tbCfg()
  if not tb then return false end
  tb.chanKeyCustom = {}
  if type(EVAL_TB_REFRESH) == "function" then EVAL_TB_REFRESH() end
  return true
end
-- 打开下拉（多选 + 输入框）
function EVAL_TB_CHANKEYS_OPEN(anchorBtn)
  if anchorBtn == nil or type(EVAL_DD_OPEN) ~= "function" then return false end
  local items, locked, sel, map = EVAL_TB_CHANKEYS_MENU()
  EVAL_DD_OPEN(anchorBtn, items, function(pi, on)
    local m = map[pi]
    if not m then return end
    local tb = tbCfg()
    if not tb then return end
    if m.kind == "clear" then EVAL_TB_CHANKEY_CLEAR() return end
    if type(tb.chanKeyOff) ~= "table" then tb.chanKeyOff = {} end
    -- ★★别写 `(on == true) and nil or true` —— Lua 的 and/or 没有布尔语义：on 为 true 时
    --   `true and nil` = nil，再 `nil or true` = **true**（正好反了）。分两步写（记忆体里记过这个坑）。
    if on == true then tb.chanKeyOff[m.word] = nil else tb.chanKeyOff[m.word] = true end
    if type(EVAL_TB_REFRESH) == "function" then EVAL_TB_REFRESH() end
  end, { multi = true, selected = sel, locked = locked, search = true,
        onFreeText = function(txt) EVAL_TB_CHANKEY_ADD(txt) end })
  return true
end

-- ★★★事件名判据（用户实测后**升级为主判据**；范围 = 用户定的，见下）：
--   【拦什么】用户截图实证：目标是「[8. Trade] 进入频道。/ 离开频道。」= **你自己**进出频道的回执
--     = CHAT_MSG_CHANNEL_NOTICE（1.12 的 YOU_JOINED/YOU_LEFT 家族；arg1 多半是英文 token 不是中文文案
--     —— 这正是旧文本判据「拦不住」的根因之一：token 里既没有「频道」也没有「进入」）。
--   【也拦】CHAT_MSG_CHANNEL_JOIN/LEAVE =「[玩家名] 加入/离开频道」（参考插件 NoJoinLeaveSpam 拦的就是这一类）
--     —— ★★用户定稿：「这两个情况都要拦截」。
--   【不拦】CHAT_MSG_CHANNEL_NOTICE_USER（踢人/换房主）、CHAT_MSG_CHANNEL（频道聊天本身）、
--     CHAT_MSG_CHANNEL_LIST（/chatlist 点名输出）—— 都不在范围内。
function EVAL_TB_CHAN_EVENT(ev)
  return ev == "CHAT_MSG_CHANNEL_NOTICE"
      or ev == "CHAT_MSG_CHANNEL_JOIN" or ev == "CHAT_MSG_CHANNEL_LEAVE"
end

-- 开关：**nil 视为开**（用户要求默认打开；老配置里没这个键时同样是开）
function EVAL_TB_CHAN_ON()
  local tb = tbCfg()
  if not tb then return true end
  return tb.chanJoin ~= false
end

-- 挂**一个**聊天窗入口（幂等：当前入口就是我们挂的那层 → 直接算已挂，**绝不重复包装**）
--   ★不要求入口是 table（本客户端帧未必是 table，只看有没有 AddMessage）——读写都走 pcall。
--   返回 true = 在位或刚挂上 / false = 这个窗口现在不可用（由调用方记账，不假称成功）
function EVAL_TB_CHAN_INSTALL_ONE(key)
  local f = _G[key]
  if f == nil then return false end
  local okr, cur = pcall(function() return f.AddMessage end)
  if not (okr and type(cur) == "function") then return false end
  TB.chanWrappers = TB.chanWrappers or {}
  -- ★只要当前入口**就是我们挂的那层**，就算已挂（防「状态说挂了、其实被别人顶掉」→ 这里会重挂）
  if cur == TB.chanWrappers[key] then return true end
  -- ★同一个对象可能以两个名字出现（DEFAULT_CHAT_FRAME == ChatFrame1）：入口等于**我们挂的任何一层**
  --   都算已挂 —— 否则会在自己头上再包一层（同一条消息被数两次、频道通知会被判两次）
  for _, w in pairs(TB.chanWrappers) do
    if cur == w then TB.chanWrappers[key] = cur return true end
  end
  local orig = cur
  local function wrapper(self, msg, ...)
    TB.chanSeenAll = (TB.chanSeenAll or 0) + 1 -- ★诊断用：经过本入口的聊天消息总数
    TB.chatSeen = (TB.chatSeen or 0) + 1
    -- ★我们自己打印的行（EVAL_SAY 都带「|cff66ccffEVAL_HELP:|r」前缀）:
    --   · 不进样本缓冲（否则 /eh go 聊天 每打印一次就把真实样本挤掉一批，而且会自己染自己）；
    --   · 也不参与名字着色（诊断输出要保持原样可读）。
    local selfPrint = (type(msg) == "string" and string.find(msg, "EVAL_HELP:", 1, true) ~= nil)
    -- 原始样本环形缓冲（只留 12 条）：/eh go 聊天 靠它把**客户端真实文案**摊开给人看
    --   ★这是「不猜格式」的取证入口：判据认不出名字时，靠这些原文校准（铁律 4）
    if not selfPrint then
      TB.chatRaw = TB.chatRaw or {}
      table.insert(TB.chatRaw, tostring(msg))
      while table.getn(TB.chatRaw) > 12 do table.remove(TB.chatRaw, 1) end
    end
    if EVAL_TB_CHAN_ON() and EVAL_TB_CHAN_BLOCK(msg) then
      TB.chanFiltered = (TB.chanFiltered or 0) + 1
      TB.chanSamples = TB.chanSamples or {}
      table.insert(TB.chanSamples, tostring(msg))
      while table.getn(TB.chanSamples) > 8 do table.remove(TB.chanSamples, 1) end
      return -- 吞掉：不进聊天框
    end
    -- ★1.73.12 聊天名字着色：与频道屏蔽**共用同一个包装体**（一次包装两个功能，绝不叠两层包装）
    local out = msg
    if not selfPrint and EVAL_TB_CHATCOLOR_ON() and type(EVAL_TB_CHAT_COLOR_LINE) == "function" then
      local okc, colored, who = pcall(EVAL_TB_CHAT_COLOR_LINE, msg)
      if okc and type(colored) == "string" and colored ~= msg then
        out = colored
        TB.chatPainted = (TB.chatPainted or 0) + 1
        TB.chatLast = who
      elseif type(EVAL_TB_NAMECLASS_HEAL) == "function" then
        -- ★★★1.73.51 未命中 → 先补一次**本地只读**缓存（公会名册/好友/查询结果；零服务器请求），
        --   真采到新名字就**当场重判这一行**（不等下一行）—— 用户报的「刚载入不染色」正是这一段能救的。
        local okh, added = pcall(EVAL_TB_NAMECLASS_HEAL)
        if okh and type(added) == "number" and added > 0 then
          local ok2, col2, who2 = pcall(EVAL_TB_CHAT_COLOR_LINE, msg)
          if ok2 and type(col2) == "string" and col2 ~= msg then
            out = col2
            TB.chatPainted = (TB.chatPainted or 0) + 1
            TB.chatLast = who2
            TB.chatHealed = (TB.chatHealed or 0) + 1
          end
        end
      end
    end
    -- ★1.73.12（用户追加要求）：未缓存的名字 → 排进**主动查询**队列；
    --   ★这里只负责「入队」，真正**发不发**由 tbWhoTick 的四道闸门决定（频率下限/单飞/负缓存/队列上限）。
    if not selfPrint and type(EVAL_TB_WHO_CANDIDATE) == "function" then
      local cand = EVAL_TB_WHO_CANDIDATE(msg)
      if cand and type(EVAL_TB_WHO_ENQUEUE) == "function" then pcall(EVAL_TB_WHO_ENQUEUE, cand) end
    end
    return orig(self, out, ...)
  end
  local okw = pcall(function() f.AddMessage = wrapper end)
  if not okw then return false end -- ★挂不上就如实返回 false（不假称挂上了）
  TB.chanWrappers[key] = wrapper
  if key == "DEFAULT_CHAT_FRAME" then TB.chanWrapper = wrapper end
  return true
end

-- 挂**所有**聊天窗入口（旧版只挂 DEFAULT_CHAT_FRAME）。返回「至少挂上一个」= true，
--   与旧版语义一致：一个聊天框都拿不到时**如实返回 false**（不假称挂上了）。
function EVAL_TB_CHAN_INSTALL()
  local keys = tbChatFrameKeys()
  local ok, miss = 0, 0
  for i = 1, table.getn(keys) do
    if EVAL_TB_CHAN_INSTALL_ONE(keys[i]) then ok = ok + 1 else miss = miss + 1 end
  end
  TB.chanFrames, TB.chanMiss = ok, miss
  if TB.chanWrappers then
    TB.chanWrapper = TB.chanWrappers["DEFAULT_CHAT_FRAME"] or TB.chanWrappers["ChatFrame1"] or TB.chanWrapper
  end
  TB.chanHooked = (ok > 0)
  return TB.chanHooked
end

-- ★★★1.71.3 **静默失效的根治**（用户实测「屏蔽频道进出信息未能正确工作」）：
--   载入那一刻 DEFAULT_CHAT_FRAME 往往**还没建好**（FrameXML 聊天框晚于插件载入）→ 旧版只试一次，
--   失败后**再没人重试**：开关看着是开的、实际一层都没挂上。
--   现在：限频重试（1 秒至多一次 / 最多 60 次）+ 事件驱动（VARIABLES_LOADED、PLAYER_ENTERING_WORLD）
--   + 每帧队列帧兜底 + `/eh go 频道` 可手动立刻重试。
--   ★判据：**「尝试过」≠「挂上了」**——失败必须重试，成功/放弃都要如实写日志。
local function tbChanRetry()
  if TB.chanHooked then
    -- ★1.73.12 补挂**后续才建出来**的聊天窗（FrameXML 懒建）：限频 5s 扫一次；
    --   已挂的窗口在 INSTALL_ONE 里直接短路，代价只是几次 _G 取值。
    local now2 = (type(GetTime) == "function") and GetTime() or 0
    if now2 - (TB.chanSweepAt or -99) >= 5 then
      TB.chanSweepAt = now2
      EVAL_TB_CHAN_INSTALL()
    end
    return true
  end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB.chanTryAt or -99) < 1 then return false end
  TB.chanTryAt = now
  TB.chanTries = (TB.chanTries or 0) + 1
  local ok = EVAL_TB_CHAN_INSTALL()
  if ok then
    EVAL_LOGLINE("[频道屏蔽] 挂载成功（第 " .. tostring(TB.chanTries) .. " 次尝试；聊天窗 " ..
      tostring(TB.chanFrames or 0) .. " 个）")
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
         (TB.chanSeenAll or 0), (TB.chanTries or 0),
         (TB.chanFrames or 0), (TB.chatSeen or 0), (TB.chanMiss or 0), -- ★1.73.12 挂上的聊天窗数 / 经过入口的消息数 / 不可用窗口数
         (TB.chanEvtFiltered or 0), (TB.chanEvtLast) -- ★事件名判据的计数与最后一条（第 11/12 个返回值；探针与断言靠它）
end

function EVAL_TEST_TB_CHAN_RESET() -- 测试用：清计数并允许重新挂载（不还原已包装的入口、不清名字缓存）
  TB.chanHooked = false
  TB.chanFiltered = 0
  TB.chanEvtFiltered, TB.chanEvtLast = 0, nil
  TB.chanSamples = {}
  TB.chanSeenAll = 0
  TB.chanTryAt = nil
  TB.chanTries = 0
  TB.chanSweepAt = nil
  TB.chatSeen, TB.chatPainted, TB.chatRaw, TB.chatLast = 0, 0, {}, nil
end

-- ===== 频道进出通知：走**官方消息组**接口（1.73.12 深入 API 后的发现）=====
-- ★API 事实（本机 api 全表 1369 条逐条核过，类别 = ChatWindow）：
--   GetChatWindowMessages(窗口)（读该窗口**开了哪些消息组**）、RemoveChatWindowMessages(窗口, 组)（摘掉一组）、
--   AddChatWindowMessages(窗口, 组)（加回来）。**这是客户端官方给的「某类消息不显示」的开关**——
--   把含 NOTICE 的那一组从聊天窗口摘掉，通知就根本不显示，**与「客户端走不走 Lua」完全无关**。
--   ★为什么必须有这条：真机实测 frame.AddMessage 那层「写成功但不生效」→ Lua 入口可能整层是死的；
--     官方消息组这条路**不依赖任何 Lua 打印路径**，是需求「屏蔽频道进出信息」最稳的实现。
--   ★组名清单 api 索引里**没有**（只有函数名）→ 现场探测：从 GetChatWindowMessages(win) 里找含 NOTICE 的那组；
--     找不到就**如实记账、不猜组名**（猜错组名 = 把别的消息也屏蔽了）。
--   ★可回滚：记住每个窗口的**原始组串**，开关关掉时按原样加回去（绝不留下「少了一组」的残状态）。
local TB_CHAN_GROUP_HINT = "NOTICE" -- 组名里含它（大小写不敏感）就算「频道进出通知」那一组
local tbChanSaved = nil             -- { [窗口] = { grp = "CHANNEL_NOTICE", orig = "SAY,CHANNEL,..." } }

-- 读某窗口的组名清单（返回表 + 失败原因）
function EVAL_TB_CHAN_GROUPS(win)
  if type(GetChatWindowMessages) ~= "function" then return nil, "noapi" end
  local ok, s = pcall(GetChatWindowMessages, win or 1)
  if not ok or type(s) ~= "string" then return nil, "unreadable" end
  local out = {}
  for part in string.gmatch(s, "[^,%s]+") do table.insert(out, part) end
  return out, nil
end
-- 找「通知」那一组（找不到返回 nil）
local function tbChanNoticeGroup(win)
  local list = EVAL_TB_CHAN_GROUPS(win)
  if type(list) ~= "table" then return nil end
  for i = 1, table.getn(list) do
    if string.find(string.upper(list[i]), TB_CHAN_GROUP_HINT, 1, true) ~= nil then return list[i] end
  end
  return nil
end
-- 应用/撤销官方屏蔽；返回 找到组的窗口数, 实际动作数, 说明
function EVAL_TB_CHAN_OFFICIAL_APPLY(on)
  if type(RemoveChatWindowMessages) ~= "function" or type(AddChatWindowMessages) ~= "function" then
    return 0, 0, "noapi"
  end
  local n = (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS > 0) and NUM_CHAT_WINDOWS or 7
  tbChanSaved = tbChanSaved or {}
  local found, act = 0, 0
  for w = 1, n do
    if on then
      local grp = tbChanNoticeGroup(w) -- ★注意：摘掉之后就再也探测不到 → 所以下面要记下组名
      if grp then
        found = found + 1
        if tbChanSaved[w] == nil then
          local okr, orig = pcall(GetChatWindowMessages, w)
          tbChanSaved[w] = { grp = grp, orig = (okr and type(orig) == "string") and orig or grp }
        end
        local ok = pcall(RemoveChatWindowMessages, w, grp)
        if ok then act = act + 1 end
      end
    else
      local rec = tbChanSaved[w]
      if rec ~= nil then
        -- ★按 API 语义「按**单个组名**加回」（AddChatWindowMessages 收的就是组名；塞整串不是它的用法）
        local ok = pcall(AddChatWindowMessages, w, rec.grp)
        if ok then act = act + 1 end
        tbChanSaved[w] = nil
      end
    end
  end
  return found, act, "ok"
end
-- 开关驱动：按当前开关状态应用（幂等；找不到组就什么都不做）
function EVAL_TB_CHAN_OFFICIAL_SYNC()
  local on = EVAL_TB_CHAN_ON()
  local ok, found, act = pcall(EVAL_TB_CHAN_OFFICIAL_APPLY, on)
  if not ok then return false, 0 end
  TB.chanOffFound, TB.chanOffAct = found, act
  if on and found and found > 0 and not TB.chanOffLogged then
    TB.chanOffLogged = true
    EVAL_LOGLINE("[频道屏蔽] 官方消息组：在 " .. tostring(found) .. " 个聊天窗口摘掉含 " .. TB_CHAN_GROUP_HINT ..
      " 的消息组（这是与「走不走 Lua」无关的官方路子）")
  end
  return true, found or 0
end
function EVAL_TEST_TB_CHAN_OFFICIAL_RESET() -- 测试用：清「已摘掉哪些窗口」的记账（模块级状态必须可重置）
  tbChanSaved = nil
  TB.chanOffFound, TB.chanOffAct, TB.chanOffLogged = 0, 0, false
end
function EVAL_TB_CHAN_OFFICIAL_STATE()
  local groups, err = EVAL_TB_CHAN_GROUPS(1)
  local saved = 0
  for _ in pairs(tbChanSaved or {}) do saved = saved + 1 end
  return { apiRemove = (type(RemoveChatWindowMessages) == "function"),
           apiAdd = (type(AddChatWindowMessages) == "function"),
           groups = groups, err = err, hint = TB_CHAN_GROUP_HINT,
           saved = saved, found = TB.chanOffFound or 0, act = TB.chanOffAct or 0 }
end

-- ===== 第二入口：ChatFrame_OnEvent（1.73.12 实测「frame.AddMessage 写了不生效」后的换入口）=====
-- ★★★实事故（用户真机截图）：`聊天窗入口：挂上 8 个；不可用 0 个` 与 `其中**是我们的包装** 0 个`
--   **同时出现** —— 说明 `ChatFrame1..7 / DEFAULT_CHAT_FRAME.AddMessage = wrapper` 这层写入
--   在**这个客户端不生效**（pcall 不报错、读回来却不是我们那层）→ 于是「频道屏蔽」与「名字着色」
--   **从来没有真正拦到过一条消息**（截图里「经过入口 0 条」「通知照旧显示」都是这一个根因）。
--   ★这是本项目「尝试过 ≠ 挂上了」那条铁律的**再深一层**：现在还要区分
--     「**写成功了**」与「**写进去生效了**」——凡挂入口，写完后必须**读回来确认**（下面就是）。
--   本客户端聊天框的入口里，`ChatFrame_OnEvent` 是**普通全局函数**（写进去一定生效）→ 改挂它：
--     ① 频道进出通知：命中就 **不调原函数**（这才是真的吞掉，不是「试过了」）；
--     ② 名字着色：把着色后的文本**回写到全局 arg1**（1.12 的聊天处理器逐条从全局 arg1..arg9 取值），
--        并把着色后的文本**作为第二参数转发**（兼容「按形参取值」的写法）。
--   ★两条路都留着：AddMessage 那层在别的客户端有效，本客户端由这一层干活；两层都无害
--     （着色幂等、吞掉只会吞一次），而且诊断里**分开计数**，谁在干活一眼看得出。
-- ★★参考插件实证（tmp/ChatMOD.lua:514-517，同代 1.12 插件）：它在 **ChatFrame_OnEvent 处理体里**做懒挂载——
--     `if not this.ORG_AddMessage then this.ORG_AddMessage = this.AddMessage; this.AddMessage = S_AddMessage end`
--   即：挂的是**事件里的 this 那个对象**，不是 `_G["ChatFrame1"]`。我们先前对 _G 挂、真机写不进去；
--   这里照它的做法再试一次，并且**每个帧只试一次 + 读回确认 + 成败都记账**（诊断里能看出哪种对象挂得上）。
function EVAL_TB_THIS_HOOK(f)
  if type(f) ~= "table" then return false end
  TB.thisTried = TB.thisTried or {}
  if TB.thisTried[f] then return (TB.thisHooked and TB.thisHooked[f]) and true or false end
  TB.thisTried[f] = true
  local okr, cur = pcall(function() return f.AddMessage end)
  if not (okr and type(cur) == "function") then return false end
  local orig = cur
  local function wrapper(self, text, ...)
    TB.thisSeen = (TB.thisSeen or 0) + 1
    local out = text
    if type(text) == "string" then
      if EVAL_TB_CHAN_ON() and EVAL_TB_CHAN_BLOCK(text) then
        TB.thisFiltered = (TB.thisFiltered or 0) + 1
        return -- 这里也能吞：真的不调底层打印
      end
      if type(EVAL_TB_CHATCOLOR_ON) == "function" and EVAL_TB_CHATCOLOR_ON() and
         type(EVAL_TB_CHAT_COLOR_LINE) == "function" then
        local okc, colored = pcall(EVAL_TB_CHAT_COLOR_LINE, text)
        if okc and type(colored) == "string" and colored ~= text then
          out = colored
          TB.thisPainted = (TB.thisPainted or 0) + 1
        end
      end
    end
    return orig(self, out, ...)
  end
  local okw = pcall(function() f.AddMessage = wrapper end)
  if not okw then return false end
  local ok2, back = pcall(function() return f.AddMessage end)
  if not (ok2 and back == wrapper) then
    -- ★真机实测：对某些帧对象这么写**不生效**（写成功、读回来不是我们的）→ 如实记一笔，别假称挂上了
    TB.thisStuck = (TB.thisStuck or 0) + 1
    return false
  end
  TB.thisHooked = TB.thisHooked or {}
  TB.thisHooked[f] = true
  TB.thisOk = (TB.thisOk or 0) + 1
  EVAL_LOGLINE("[聊天入口] 在事件里对 this 帧懒挂载 AddMessage **成功**（ChatMOD 的做法，读回确认过）")
  return true
end

-- ★★★1.73.17 **取参必须兼容全部调用形态**（用户实测：ChatFrame_OnEvent 被调用 1513 次，我们却一条文本都没取到、
--   连事件计数都是空的 → 说明**姿势不对**）。可能的形态（本项目其它地方也踩过「事件名在哪一个参数」这类坑）：
--     (a) ChatFrame_OnEvent(event)                        + 全局 arg1..arg9（1.12 老写法）
--     (b) ChatFrame_OnEvent(event, 文本, 发送者, ...)      （按形参）
--     (c) ChatFrame_OnEvent(self, event, 文本, 发送者, ...)（按处理器调用）
--   ★判据：**把 varargs 全部收进表，按顺序挑「不像事件名的那一个字符串」当文本**（事件名 = 以 CHAT_MSG 开头），
--     再退回全局 arg1 —— 三种形态都能取到；取不到就**如实记 noMsg 计数**（不许静默跳过，见下面 wrapper 里的计数位置）。
local function tbCeArgs(a1, ...)
  local n = select("#", ...)
  local cand = { a1 }
  for i = 1, n do cand[i + 1] = select(i, ...) end
  return cand
end
local function tbCeIsEvStr(v)
  return (type(v) == "string" and v ~= "" and string.find(v, "^CHAT_MSG") ~= nil)
end
local function tbCeEventOf(e, a1, ...)
  local cand = tbCeArgs(a1, ...)
  if tbCeIsEvStr(e) then return e end
  for i = 1, table.getn(cand) do
    if tbCeIsEvStr(cand[i]) then return cand[i] end
  end
  if type(e) == "string" and e ~= "" then return e end
  if type(event) == "string" and event ~= "" then return event end
  return ""
end
-- 文本：按顺序挑第一个「不是事件名」的非空字符串（★同时覆盖 (b)/(c) 两种形态），再退回全局 arg1
local function tbCeMsgOf(a1, ...)
  local cand = tbCeArgs(a1, ...)
  for i = 1, table.getn(cand) do
    local v = cand[i]
    if type(v) == "string" and v ~= "" and not tbCeIsEvStr(v) then return v end
    if type(v) == "number" then return tostring(v) end
  end
  if type(arg1) == "string" and arg1 ~= "" and not tbCeIsEvStr(arg1) then return arg1 end
  return nil
end
-- 发送者名：**候选里挑**（(event,msg,发送者) 与 (self,event,msg,发送者) 下它分别是第 1/第 2 个 vararg → 位置不定），
--   形状像角色名（无空白/冒号/方括号/竖线、2..16 字符）且不等于文本；取不到再退回全局 arg2。
local function tbCeSenderOf(msg, a1, ...)
  local cand = tbCeArgs(a1, ...)
  for i = 1, table.getn(cand) do
    local v = cand[i]
    if type(v) == "string" and v ~= "" and v ~= msg and not tbCeIsEvStr(v) then
      local len = tbNameCharLen(v)
      if string.find(v, "[%s:：|%[%]]") == nil and len >= 2 and len <= 16 then return v end
    end
  end
  if type(arg2) == "string" and arg2 ~= "" and arg2 ~= msg then return arg2 end
  return nil
end
function EVAL_TB_CHATEVENT_INSTALL()
  local cur = _G.ChatFrame_OnEvent
  if type(cur) ~= "function" then return false end
  if cur == TB.ceWrapper then return true end -- 幂等：当前入口就是我们的那层
  local orig = cur
  local function wrapper(e, a1, ...)
    TB.ceSeen = (TB.ceSeen or 0) + 1
    -- ★★★1.73.17 取参：兼容 (event) + 全局 / (event, 文本…) / (self, event, 文本…) 三种形态
    local ev = tbCeEventOf(e, a1, ...)
    local msg = tbCeMsgOf(a1, ...)
    -- ★★★调用形态取证（用户实测：1513 次调用一条文本都没取到 → 必须先把**客户端怎么调的**看清楚）：
    --   记前 6 次的原始形状：e / 第 1 个 vararg / 全局 arg1 / 全局 arg2 的类型与值（截断 28 字）
    if (TB.ceShapeN or 0) < 6 then
      TB.ceShapeN = (TB.ceShapeN or 0) + 1
      TB.ceShape = TB.ceShape or {}
      local function sh(v)
        local t = type(v)
        local s = tostring(v)
        if string.len(s) > 28 then s = string.sub(s, 1, 28) .. "…" end
        return t .. "=" .. s
      end
      table.insert(TB.ceShape, "e:" .. sh(e) .. " ｜ a1:" .. sh(a1) .. " ｜ arg1:" .. sh(arg1) ..
        " ｜ arg2:" .. sh(arg2))
    end
    -- ★★★计数与「取不到文本」都要在**守卫之前**记：上一版把它们写在「取到文本」之后 →
    --   1513 次调用、计数却是空的 = 诊断自己把证据藏了（这就是用户那张截图的由来）。
    TB.ceByEv = TB.ceByEv or {}
    TB.ceByEv[ev] = (TB.ceByEv[ev] or 0) + 1
    if type(msg) ~= "string" or msg == "" then TB.ceNoMsg = (TB.ceNoMsg or 0) + 1 end
    -- ★★★1.74.1 取证：频道类事件的 **arg8 / arg9 原文**。
    --   为什么专门记这两个：参考插件 NoJoinLeaveSpam 的 `/njls mute <频道>` 判据输入**就是 arg9**（频道名），
    --   它只在 CHAT_MSG_CHANNEL_JOIN / _LEAVE 两个事件上生效 ⇒ 「那条命令在**本客户端**到底能不能拦到
    --   你自己进出的回执」完全取决于：这些回执是不是走 JOIN/LEAVE、且 arg9 里是不是频道名。
    --   （我们三种事件名都拦，所以不受影响；这一条只为**如实回答**参考插件的机制是否成立。）
    if type(ev) == "string" and string.find(ev, "CHANNEL", 1, true) ~= nil then
      TB.chanEvArgs = TB.chanEvArgs or {}
      table.insert(TB.chanEvArgs, ev .. " ｜ arg8=" .. tostring(arg8) .. " ｜ arg9=" .. tostring(arg9) ..
        " ｜ arg1=" .. string.sub(tostring(msg or arg1 or ""), 1, 24))
      while table.getn(TB.chanEvArgs) > 8 do table.remove(TB.chanEvArgs, 1) end
    end
    -- ★★★① 频道进出通知：**事件名判据优先**（用户两次审计定案：只吞自己进出的 NOTICE 回执）；
    --   放在 isChat/文本 两道闸**之前**（arg1 是英文 token 也拦得住），并与文本路**分开计数**（谁拦到一眼看到）。
    if EVAL_TB_CHAN_ON() and EVAL_TB_CHAN_EVENT(ev) then
      TB.chanEvtFiltered = (TB.chanEvtFiltered or 0) + 1
      TB.chanEvtLast = ev .. " ｜ " .. tostring(msg or "")
      return -- 不调原函数 = 真的不显示（与参考插件同款吞法）
    end
    -- ★★★①b 文本兜底（**不要求事件名以 CHAT_MSG 开头**：本客户端通知事件名未必叫 CHAT_MSG_*，
    --   旧写法把这一闸放在 isChat 之后 → 自定义事件名的通知**永远走不到判据**，白屏）；
    --   判据本身要求「频道词 + 动作词（或自定义词）」，误伤面很小（见 EVAL_TB_CHAN_BLOCK）。
    --   ★关键字**用户可配置**（多选下拉 + 输入框），改完立即生效（判据在调用时读配置）。
    if EVAL_TB_CHAN_ON() and EVAL_TB_CHAN_BLOCK(msg) then
      TB.ceFiltered = (TB.ceFiltered or 0) + 1
      return
    end
    local isChat = (ev == "" or string.find(ev, "CHAT_MSG") ~= nil)
    if isChat and type(msg) == "string" and msg ~= "" then
      -- ★★★1.73.16 取证实录（用户报「角色名还是没染色」）：**样本必须只留玩家聊天**。
      --   上一版把**所有** CHAT_MSG_* 都塞进 12 格环形缓冲 → 战斗/法术刷屏（实测那 12 条全是
      --   CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS）把真实聊天行**挤出去**了 → 关键证据永远看不到。
      --   ★判据：取证缓冲要按**问题相关的事件白名单**过滤，不能"来者不拒"。
      -- 原始样本：只记**玩家聊天**（说/喊/队伍/团队/公会/官员/频道/密语/表情）
      local evUp = string.upper(ev)
      local isPlayerChat = false
      for _, k in ipairs(TB_CHAT_EV_KEYS) do
        if string.find(evUp, k, 1, true) ~= nil then isPlayerChat = true break end
      end
      if isPlayerChat then
        -- ★arg2 = 发送者名（1.12 语义）：一并记下来 —— 「名字到底在 arg1 里还是只在 arg2 里」是本轮要定的案
        local a2 = tbCeSenderOf(msg, a1, ...) -- ★三种形态下发送者位置不同 → 按候选挑（不再假设是第 2 个 vararg）
        TB.ceChat = TB.ceChat or {}
        table.insert(TB.ceChat, evUp .. " ｜ arg1=" .. msg .. " ｜ arg2=" .. tostring(a2))
        while table.getn(TB.ceChat) > 12 do table.remove(TB.ceChat, 1) end
      end
      -- 兼容：老读值口 ceRaw 继续记（但只记前 4 条，避免刷屏把它撑满）
      TB.ceRaw = TB.ceRaw or {}
      if table.getn(TB.ceRaw) < 4 then table.insert(TB.ceRaw, ev .. " ｜ " .. msg) end
      -- ★ChatMOD 的做法：趁事件在手，对 this 帧试一次懒挂载（成败都记账）
      if this ~= nil then pcall(EVAL_TB_THIS_HOOK, this) end
      -- ★★★1.73.18 真机定案（用户样本）：**arg1 只有正文**（"1" / "你有队"），**arg2 才是发送者名**（"Ionol" / "猎狂"）。
      --   调用形态 = 经典「(event) + 全局 arg1..arg9」（取证里 e=PLAYER_ENTERING_WORLD ｜ a1=nil ｜ arg1=player）。
      --   ⇒ 名字**不在 arg1 里**（客户端自己把它拼成 "[名字]: 正文"）→ 要让名字带上职业色，
      --     唯一能改的就是 **arg2 本身**（处理器从全局取值）。
      local sender = nil
      if type(arg2) == "string" and arg2 ~= "" then sender = arg2 end
      if sender == nil then sender = tbCeSenderOf(msg, a1, ...) end
      -- ①c 主动查询：**发送者名**才是最好的触发点（原来从正文找方括号名字，而正文只有 "1"/"你有队" → 永远找不到）
      if type(EVAL_TB_WHO_ENQUEUE) == "function" and sender then pcall(EVAL_TB_WHO_ENQUEUE, sender) end
      if type(EVAL_TB_WHO_CANDIDATE) == "function" and type(EVAL_TB_WHO_ENQUEUE) == "function" then
        local cand = EVAL_TB_WHO_CANDIDATE(msg) -- 兼容：正文里若真带 [名字]（别的客户端形态）也试一次
        if cand then pcall(EVAL_TB_WHO_ENQUEUE, cand) end
      end
      -- ②a ★名字着色（**本轮真正的修复**）：把 arg2 包成 |c职业色名字|r。
      --   ★做法 =「**剥码 → 查缓存 → 用纯名字重建**」：
      --     先剥掉已有的颜色码拿到**纯名字**再查职业色，然后用**纯名字**重建整段。于是：
      --     ① 客户端自己先上过色（不知道职业时的**默认灰**）→ 照样能被改成职业色
      --        —— 用户抱怨的「角色名还是没染色」正是这种（旧代码拿带码的串查缓存、永远查不到人）；
      --     ② 已经是我们那层色 → 重建出来**逐字节相同** → **天然幂等**、不重复包裹，也不记任何计数。
      --   ★上一版「看到 |c 就整段跳过」的写法里，查缓存用的却是**带码的串** → 那条守卫是**死代码**
      --     （变异 M176 实测存活）；改成重建之后，「剥码」这一步是**承重的**（删掉它 = 灰名字改不掉，变异 M176 捕获）。
      --   ★保守：只在「缓存里有这个职业色」时重建；**不自己加 |Hplayer: 链接**
      --     （真机还没确认客户端是否自己拼链接；先把颜色上上去，链接形态等实测反馈再定）。
      local senderPlain = sender
      if type(senderPlain) == "string" then
        senderPlain = string.gsub(senderPlain, "|c%x+", "")
        senderPlain = string.gsub(senderPlain, "|r", "")
      end
      if sender and type(EVAL_TB_CHATCOLOR_ON) == "function" and EVAL_TB_CHATCOLOR_ON() then
        local hex = nil
        if type(EVAL_TB_PAINT_COLOR_OF) == "function" then hex = EVAL_TB_PAINT_COLOR_OF(senderPlain) end
        if hex then
          TB.ceNamed = (TB.ceNamed or 0) + 1 -- 认得出来（诊断看这个）
          -- ★★★1.73.22 方案 A：**自己拼整行 + 吞掉客户端那行**（名字槽不吃富文本，只有这条路能染色）。
          --   拼得出来 → 打印我们那一行并 **return（不调原函数）**；拼不出来 → 一个字都不改、原样放行。
          local cline = nil
          if type(EVAL_TB_CHATCOMPOSE) == "function" then
            cline = EVAL_TB_CHATCOMPOSE(evUp, msg, senderPlain, hex)
          end
          local fr = _G.DEFAULT_CHAT_FRAME
          if cline and fr and type(fr.AddMessage) == "function" then
            pcall(fr.AddMessage, fr, cline)
            TB.ceReplaced = (TB.ceReplaced or 0) + 1
            return -- ★吞掉：客户端不再自己打这一行（这是「真吞掉」）
          end
          -- 兜底（拼不出来）：**不动任何东西**，交给客户端原样显示（宁可没色，绝不丢消息/串格式）
          TB.ceNameHold = (TB.ceNameHold or 0) + 1
          -- ★后手：名字槽何时能被客户端解析还是未知 —— 只有显式打开才回写 arg2（默认关，见 1.73.20/1.73.21）
          if TB_NAMECOLOR_WRITE and type(arg2) == "string" and arg2 == sender then
            arg2 = "|c" .. hex .. senderPlain .. "|r"
          end
        else
          TB.ceNameMiss = (TB.ceNameMiss or 0) + 1 -- 名字不在缓存里（如实记账，诊断里能看到）
        end
      end
      -- ② 正文着色（其它客户端形态下正文里可能带 [名字]；无副作用：认不出就不动）
      local out = msg
      if type(EVAL_TB_CHATCOLOR_ON) == "function" and EVAL_TB_CHATCOLOR_ON() and
         type(EVAL_TB_CHAT_COLOR_LINE) == "function" then
        local okc, colored = pcall(EVAL_TB_CHAT_COLOR_LINE, msg)
        if okc and type(colored) == "string" and colored ~= msg then
          out = colored
          TB.cePainted = (TB.cePainted or 0) + 1
        end
      end
      if out ~= msg then
        if type(arg1) == "string" and arg1 == msg then arg1 = out end -- 回写全局（处理器从全局取值）
        return orig(e, out, ...)
      end
    end
    return orig(e, a1, ...)
  end
  local okw = pcall(function() _G.ChatFrame_OnEvent = wrapper end)
  if not okw then return false end
  -- ★★★写进去必须**读回来确认**（本客户端刚刚吃过这个亏：AddMessage 写成功但不生效）
  if _G.ChatFrame_OnEvent ~= wrapper then return false end
  TB.ceWrapper = wrapper
  TB.ceOrig = orig -- ★1.73.20 取证口：留一份**原函数**（渲染试验要绕过我们自己这层，直接让客户端拼行）
  return true
end
function EVAL_TB_CHATEVENT_RETRY()
  if TB.ceWrapper and _G.ChatFrame_OnEvent == TB.ceWrapper then return true end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB.ceTryAt or -99) < 1 then return false end
  TB.ceTryAt = now
  TB.ceTries = (TB.ceTries or 0) + 1
  local ok = EVAL_TB_CHATEVENT_INSTALL()
  -- ★1.73.24 顺手重试「名字右键菜单」的 SetItemRef 挂载（同一批事件；它自己还有 1 秒限频）
  if type(EVAL_TB_NAMEMENU_RETRY) == "function" then pcall(EVAL_TB_NAMEMENU_RETRY) end
  -- ★顺便把「官方消息组」屏蔽同步一次（幂等；与走不走 Lua 无关的那条路）
  if type(EVAL_TB_CHAN_OFFICIAL_SYNC) == "function" then pcall(EVAL_TB_CHAN_OFFICIAL_SYNC) end
  if ok and not TB.ceLogged then
    TB.ceLogged = true
    EVAL_LOGLINE("[聊天入口] ChatFrame_OnEvent 挂载成功并**读回确认**（AddMessage 那层在本客户端不生效）")
  end
  return ok
end
-- ★★★1.73.22 方案 A（**用户拍板**）：**吞掉客户端那行 + 自己拼整行** —— 只有这条路能让名字带上职业色。
--   【为什么只能这样】名字槽（arg2）实测**不做富文本解析**（8 位色码也原样显示，见 1.73.20），
--     而 AddMessage 通道**认代码**（我们自己的诊断行一直是有色的）→ 自己拼才染得上。
--   【格式忠实抄客户端】用**客户端自己的全局格式串**拼（取证屏已看到它们都在）：
--     CHAT_SAY_GET="%s说: " ｜ CHAT_YELL_GET="%s喊道: " ｜ CHAT_GUILD_GET="[公会] %s: " …
--     拿同一份模板拼，文案/三语言/客户端改动都不用我们跟。
--   【拿不准就不吞】下面任一条不成立 → **一个字都不改，原样交给客户端**（宁可没色，绝不丢消息或串格式）：
--     ① 事件在支持表里；② 客户端真有那个格式串；③ 模板里**恰好一个 %s**；④ 名字在缓存里（有职业色）。
--   【名字怎么给】`|c职业色|Hplayer:名字|h[名字]|h|r` —— 自己补 `|Hplayer:` 链接 → **点名字照样能密语**。
--   【代价（取证屏已写明，用户接受）】聊天窗**分流**、说/喊**气泡**、部分音效不再由客户端出。
local TB_CE_FMT = {
  CHAT_MSG_SAY = "CHAT_SAY_GET", CHAT_MSG_YELL = "CHAT_YELL_GET",
  CHAT_MSG_GUILD = "CHAT_GUILD_GET", CHAT_MSG_OFFICER = "CHAT_OFFICER_GET",
  CHAT_MSG_PARTY = "CHAT_PARTY_GET", CHAT_MSG_RAID = "CHAT_RAID_GET",
}
local TB_CE_TYPE = {
  CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL", CHAT_MSG_GUILD = "GUILD",
  CHAT_MSG_OFFICER = "OFFICER", CHAT_MSG_PARTY = "PARTY", CHAT_MSG_RAID = "RAID",
}
-- ★★★1.73.23 消息类型色**三个来源**（真机实测：这个客户端取不到 ChatTypeInfo → 公会前缀变白；
--   而用户截图里**客户端自己画的** [公会] 我逐像素取色 = **40FF40** → 内置一份**有证据的**兜底色）
--   ① 客户端 `ChatTypeInfo[类型].colorStr` —— **永远优先**（尊重客户端/玩家的配色设置）；
--   ② 客户端只给 r/g/b → 自己合成 8 位色码（四舍五入到 0..255）；
--   ③ 都没有 → **内置兜底表**：只放**从用户截图取过色**的项；没证据的**宁可不加色**（绝不瞎猜配色）。
local TB_CE_COLOR_FALLBACK = {
  GUILD = "ff40ff40", -- ★证据：用户截图里客户端自己画的「[公会]」= 40FF40（逐像素取色，29 次命中）
}
function EVAL_TB_CHATTYPECOLOR(ev)
  local t = TB_CE_TYPE[ev]
  if not t then return nil, "none" end
  local cti = _G.ChatTypeInfo
  if type(cti) == "table" then
    local e = cti[t]
    if type(e) == "table" then
      local s = e.colorStr
      if type(s) == "string" and string.len(s) >= 10 then return s, "client" end -- "|c" + 8 位
      local r, g, b = tonumber(e.r), tonumber(e.g), tonumber(e.b)
      if r and g and b then
        local function h(x)
          local v = math.floor(x * 255 + 0.5)
          if v < 0 then v = 0 elseif v > 255 then v = 255 end
          return string.format("%02x", v)
        end
        return "|cff" .. h(r) .. h(g) .. h(b), "client-rgb"
      end
    end
  end
  local fb = TB_CE_COLOR_FALLBACK[t]
  if fb then return "|c" .. fb, "builtin" end
  return nil, "none"
end
-- 诊断读值口：逐类型把「用到的色 + 来源」摊开（取证用；★不许在诊断里另写一套判据）
function EVAL_TB_CHATCOLOR_TYPECOLOR_INFO()
  local keys = { "SAY", "YELL", "GUILD", "OFFICER", "PARTY", "RAID" }
  local parts = {}
  for i = 1, table.getn(keys) do
    local c, src = EVAL_TB_CHATTYPECOLOR("CHAT_MSG_" .. keys[i])
    table.insert(parts, keys[i] .. "=" .. tostring(c) .. "（" .. tostring(src) .. "）")
  end
  local cti = _G.ChatTypeInfo
  return "ChatTypeInfo=" .. ((type(cti) == "table") and "有" or "**没有**") .. "；" .. table.concat(parts, " ")
end
-- 纯函数：拼一行（**能拼 → 字符串**；任一条判据不满足 → **nil = 不许吞**）。
-- ★类型色只在**前缀**上（与客户端一样：公会前缀是绿的、正文是白的）：前缀后立刻 `|r` 复位。
function EVAL_TB_CHATCOMPOSE(ev, body, sender, hex)
  if type(ev) ~= "string" or type(sender) ~= "string" or sender == "" then return nil end
  local key = TB_CE_FMT[ev]
  if not key then return nil end
  local tpl = _G[key]
  if type(tpl) ~= "string" then return nil end -- ② 客户端没这个格式串 → 不猜
  local pre, post = string.match(tpl, "^(.-)%%s(.*)$")
  if pre == nil then return nil end            -- ③ 模板里没有 %s
  --  ★plain=true 时找的是**字面两个字符** "%s"（不是模式里的 %%s！）—— 本轮实测：写成 "%%s" 永远找不到，
  --   于是「模板里不止一个 %s → 不许拼」这条判据**整个是死的**（组 129d③ 当场抓到）。
  if string.find(post, "%s", 1, true) then return nil end -- ③ 不止一个 %s → 不猜
  local name = "[" .. sender .. "]"
  if type(hex) == "string" and string.len(hex) == 8 then
    name = "|c" .. hex .. "|Hplayer:" .. sender .. "|h[" .. sender .. "]|h|r"
  end
  local tc = EVAL_TB_CHATTYPECOLOR(ev)
  if tc then
    return tc .. pre .. "|r" .. name .. tc .. post .. tostring(body or "") .. "|r"
  end
  return pre .. name .. post .. tostring(body or "")
end

-- ★★★1.73.20 名字槽**渲染试验**（取证口；铁律 4：能做成命令就别让用户手工复现）
--   【为什么需要它】用户真机截图逐字放大后定案：名字槽里**8 位色码也原样显示**
--   （「[1. 综合] [|cfff58cbaIonol|r]: 1」—— 代码当普通文字画出来），
--   而同一屏里我们自己经 AddMessage 打印的 8 位色码**是有色的** ⇒ 「名字槽不吃富文本」。
--   于是最后一条路只剩「吞掉客户端那行、自己拼整行」，但那有代价（窗口分流 / 气泡 / 音效），
--   **不能靠猜** ⇒ 先做这一屏试验：让客户端自己渲染四种名字写法，用户看一眼就知道哪条路通。
function EVAL_TB_CHATCOLOR_NAMEPROBE()
  local o = TB.ceOrig
  if type(o) ~= "function" and type(EVAL_TB_CHATEVENT_INSTALL) == "function" then
    pcall(EVAL_TB_CHATEVENT_INSTALL)
    o = TB.ceOrig
  end
  local hex = "fff58cba"
  if type(EVAL_TB_PAINT_CLASS_COLOR_OF) == "function" then hex = EVAL_TB_PAINT_CLASS_COLOR_OF("圣骑士") end
  local col = "|c" .. hex
  say("— 名字槽渲染试验（★每行下面那行是**客户端自己拼**的；看哪一行名字**有色 / 可点**）—")
  local tests = {
    { "① 8 位色码（对照）", col .. "Ionol|r" },
    { "② 链接形态 |Hplayer:", "|Hplayer:Ionol|h[Ionol]|h" },
    { "③ 链接 + 内层色码", "|Hplayer:Ionol|h[" .. col .. "Ionol|r]|h" },
    { "④ 纯名字（对照）", "Ionol" },
    { "⑤ 转义测试 A||B", "A||B" },
  }
  local okn = (type(o) == "function")
  if okn then
    for i = 1, table.getn(tests) do
      say("  试验 " .. tests[i][1] .. "：")
      arg1, arg2 = "色测正文", tests[i][2]
      pcall(o, "CHAT_MSG_SAY")
      arg1, arg2 = nil, nil
    end
  else
    say("  （原函数拿不到 → 先 /eh go 聊天 装，再重跑 色测）")
  end
  local function g(k)
    local v = _G[k]
    if v == nil then return "nil" end
    return tostring(v)
  end
  say("客户端聊天格式串：CHAT_SAY_GET=" .. g("CHAT_SAY_GET") .. " ｜ CHAT_YELL_GET=" .. g("CHAT_YELL_GET") ..
      " ｜ CHAT_GUILD_GET=" .. g("CHAT_GUILD_GET") .. " ｜ CHAT_CHANNEL_GET=" .. g("CHAT_CHANNEL_GET"))
  -- ③ 「吞掉客户端那行、自己拼整行」的样子（名字才能带色；链接也由我们给 → 照样可点）
  local link = col .. "|Hplayer:Ionol|h[Ionol]|h|r"
  say("— 若走「吞行 + 自己拼」方案，聊天里会长这样 —")
  say("[公会] [" .. link .. "]: 色测正文")
  say("[" .. link .. "] 说: 色测正文")
  say("[1. 综合] [" .. link .. "]: 色测正文")
  say("★代价：**分流**（哪类消息进哪个聊天窗）、说/喊**气泡**、部分音效由客户端管 → 自己拼就没有了")
  return okn
end
function EVAL_TB_CHATEVENT_STATE()
  return { seen = TB.ceSeen or 0, filtered = TB.ceFiltered or 0, painted = TB.cePainted or 0,
           live = (TB.ceWrapper ~= nil and _G.ChatFrame_OnEvent == TB.ceWrapper) and true or false,
           exists = (type(_G.ChatFrame_OnEvent) == "function"), raw = TB.ceRaw or {},
           tries = TB.ceTries or 0,
           -- ★this 帧懒挂载（ChatMOD 的做法）的战果：挂上几个 / 写不进去几个 / 经它收到与吞掉多少
           thisOk = TB.thisOk or 0, thisStuck = TB.thisStuck or 0,
           thisSeen = TB.thisSeen or 0, thisFiltered = TB.thisFiltered or 0, thisPainted = TB.thisPainted or 0,
           chat = TB.ceChat or {}, byEv = TB.ceByEv or {},
           shape = TB.ceShape or {}, noMsg = TB.ceNoMsg or 0,
           named = TB.ceNamed or 0, nameMiss = TB.ceNameMiss or 0,
           -- ★1.73.20 「认得出职业、但按当前结论**暂不回写**」的次数（名字槽不吃富文本）
           held = TB.ceNameHold or 0,
           -- ★1.73.22 方案 A：真的「吞行 + 自己拼」了几行
           replaced = TB.ceReplaced or 0,
           -- ★事件名判据（频道进出）的战果：拦了几条 / 最后一条是什么事件
           evtFiltered = TB.chanEvtFiltered or 0, evtLast = TB.chanEvtLast,
           chanArgs = TB.chanEvArgs or {} }
end
function EVAL_TEST_TB_CHATEVENT_RESET()
  TB.chanEvtFiltered, TB.chanEvtLast = 0, nil -- 事件名判据的计数（模块级状态必须可重置）
  TB.chanEvArgs = {} -- 频道事件的 arg8/arg9 取证缓冲
  TB.ceSeen, TB.ceFiltered, TB.cePainted, TB.ceRaw = 0, 0, 0, {}
  TB.ceChat, TB.ceByEv, TB.ceShape, TB.ceNoMsg, TB.ceShapeN = {}, {}, {}, 0, 0
  TB.ceNamed, TB.ceNameMiss, TB.ceNameHold, TB.ceReplaced = 0, 0, 0, 0
  TB.ceTryAt, TB.ceTries, TB.ceLogged = nil, 0, false
end
-- ★1.73.20 试验口：临时打开/关闭「回写 arg2」（**默认关** —— 名字槽不吃富文本，回写只会显示成原文）。
--   有了它，「闸门关着 → arg2 一个字不改」与「闸门开着 → 真的会包成职业色」**两条都能被断言钉住**，
--   否则那段回写逻辑就成了「没被任何断言覆盖」的死代码（本项目最忌讳的盲区）。
function EVAL_TEST_TB_NAMECOLOR_WRITE(on)
  local old = TB_NAMECOLOR_WRITE
  TB_NAMECOLOR_WRITE = (on == true)
  return old
end
TB.ceHooked = EVAL_TB_CHATEVENT_INSTALL() and true or false
EVAL_LOGLINE("[聊天入口] ChatFrame_OnEvent 载入时挂载：" ..
  (TB.ceHooked and "成功" or "函数还不存在（将由事件/每帧重试）"))

-- ===== 聊天名字右键菜单（1.73.24 用户要求：「右键聊天名字 → 公会邀请 / 复制名字 / /s 输出名字」）=====
-- 【排查（用户明确要求：先查 API lua 与参考插件）】
--   ① 本机 API 全表：**有** `GuildInviteByName`（类别 Guild）与 `CanGuildInvite`；
--      **没有** `SetClipboardText` / `GetClipboardText` → 「复制名字」**写不进系统剪贴板**（只能给「已全选」的框手动 Ctrl+C）；
--      **没有** `UIDropDownMenu` / `ToggleDropDownMenu` → 菜单得自己画（用本文件既有的 tbText/tbBtn 原语）。
--   ② 参考插件 ChatMOD（`tmp/ChatMOD.lua:1284-1298` 与 `1429-1430`）：它**包 `SetItemRef`**（普通全局，直接可写）
--      并往文本里塞自定义链接 `|Hinv:名字|h` → 点它自己调 `InviteByName`；它的 EasyCopy 弹窗正是
--      「没有剪贴板 API」的替代做法（本实现照抄这个思路：给一个**已全选**的输入框）。
--   ③ 我们**不塞自定义链接**：自己拼的聊天行已经带 `|Hplayer:名字|h`（方案A 加的）→ 直接认 **player: 链接的右键**；
--      ★左键、以及 item:/quest:/spell: 等其它链接**一律原样交给客户端**（不动既有行为）；挂载后**读回确认**（1.73.12 的教训）。
local TB_NAME_MENU = { shown = false, name = nil } -- ★1.73.28 计数都挂在这张表上（party/target/whisper/said/throttled）
-- ★1.73.28 名字要塞进 RunScript 的字符串里 → 先去掉引号与反斜杠。
--   ★用 string.char 构造这两个字符：**不要在 Lua 源码里手写转义** —— 本轮实测，手写转义把文件写坏，
--     而且 luacheck 居然还报 SYNTAX OK，直到运行时 load 才炸（LOAD ERROR 报 near backslash）→ 已补源码检查。
local TB_Q, TB_BS = string.char(34), string.char(92)
local function tbSafeName(s)
  if type(s) ~= "string" then return "" end
  s = string.gsub(s, TB_Q, "")
  s = string.gsub(s, TB_BS, "")
  return s
end
function EVAL_TB_NAMEMENU_ON()
  return tbCfg().nameMenu ~= false
end
function EVAL_TB_MENU_HIDE()
  if TB.menu then pcall(TB.menu.Hide, TB.menu) end
  TB_NAME_MENU.shown = false
end
-- ★★★1.73.35 用户（第 2 条）：右键菜单**扩展 + 两列 + 宽高自适应 + 锚点右上**
--   条目（按用户列表）：悄悄话 / 邀请 / 目标 / 复制名字 / **分享方案（默认当前激活方案）** / **交易** / **查询** /
--   **踢出队伍（在队伍里才显示）** / **踢出公会（有权限才显示）** / **邀请公会（有权限才显示）** / 关闭。
--   ★权限/条件门：CanGuildInvite() / CanGuildRemove() / GetNumPartyMembers()>0 决定条目**出不出现**（不是点了才说没权限）。
--   ★版式：**两列**（每条仍 ≤4 个汉字宽），宽高**由条目数算出来**（单一来源 EVAL_TB_MENU_LAYOUT）。
--   ★锚点：窗口**右上角**（用户要求「弹窗锚点右上」）。
local TB_MENU_COL_W = 62 -- 单列宽（≤4 个汉字）
local TB_MENU_GAP = 4
local TB_MENU_ITEM_H = 15
local TB_MENU_TITLE_H = 13
-- ★★★1.73.40 用户「框增加 padding」：左右/上/下**都有内边距**（标题与条目都不贴边）——
--   ★宽度、高度、标题位置、条目位置**全部由这几个常量算**（单一来源，改一处全都动）。
local TB_MENU_PAD = { x = 8, t = 6, b = 8 }
local TB_MENU_TOP = -(TB_MENU_PAD.t + TB_MENU_TITLE_H) -- 第一行条目的顶边
-- ★★★1.73.40 用户「外框背景加深 / 背景透明 / 只要文字变色，不用背景变色」：
--   面板底**加深**（0.88），条目按钮底**完全透明**（alpha 0）→ 悬停就只剩「文字变白」这一处变化。
local TB_MENU_COLORS = {
  panelRGBA  = { 0.01, 0.01, 0.02, 0.88 }, -- 外框背景（加深）
  itemRGBA   = { 0, 0, 0, 0 },             -- 条目背景（完全透明）
  txtRGBA    = { 0.95, 0.82, 0.35 },       -- 常态文字（金）
  txtHotRGBA = { 1.00, 1.00, 1.00 },       -- 悬停文字（只给文字加点白）
  borderRGBA = { 1, 1, 1, 0.75 },          -- 圆角边框色（白色高亮）
  flatRGBA   = { 1, 1, 1, 0.75 },          -- 退化路径四条平边
}
-- ★原生圆角边的 edgeSize：必须整数（参考插件实测：小数在本客户端栅格化不可靠）
local TB_MENU_EDGE = 16
-- 纯函数：条目数 → 宽 / 高 / 行数 / 列数（渲染与断言**共用这一份**）
function EVAL_TB_MENU_LAYOUT(n)
  n = tonumber(n) or 0
  if n < 1 then n = 1 end
  local rows = math.ceil(n / 2)
  local w = TB_MENU_PAD.x * 2 + TB_MENU_COL_W * 2 + TB_MENU_GAP
  -- ★★★1.73.40 用户截图「右键框未包含关闭按键」——根因就在这一行：
  --   原式只算了 (rows-1) 个**行距**，**最后一行的自身高度没算**，
  --   于是末行按钮吊在窗口底 9px 之外（关闭正好在末行 → 看起来菜单里根本没关闭）。
  --   ★判据 = 组 130③d 的**包含性**（每条按钮的矩形必须落在窗口矩形内，独立于本函数）。
  local h = -TB_MENU_TOP + rows * TB_MENU_ITEM_H + TB_MENU_PAD.b
  return w, h, rows, 2
end
function EVAL_TB_MENU_HEIGHT(n) local _, h = EVAL_TB_MENU_LAYOUT(n) return h end
function EVAL_TB_MENU_WIDTH(n) local w = EVAL_TB_MENU_LAYOUT(n) return w end
local function tbFriendIndex(name)
  if type(name) ~= "string" or name == "" then return nil end
  if type(GetNumFriends) ~= "function" or type(GetFriendInfo) ~= "function" then return nil end
  local okn, n = pcall(GetNumFriends)
  if not okn then return nil end
  n = tonumber(n) or 0
  local want = string.lower(name)
  for i = 1, n do
    local okf, fname = pcall(GetFriendInfo, i)
    if okf and type(fname) == "string" and fname ~= "" and string.lower(fname) == want then return i end
  end
  return nil
end
function EVAL_TB_NAME_ISFRIEND(name) return tbFriendIndex(name) ~= nil end
local function tbFriendCount()
  if type(GetNumFriends) ~= "function" then return nil end
  local ok, n = pcall(GetNumFriends)
  if not ok then return nil end
  return tonumber(n) or 0
end

-- ★1.73.42u 菜单**条目集签名**（前置声明：EVAL_TEST_TB_MENU_DROP 也要清它）——
--   条目集合变了就重建菜单（好友/队伍/权限是会变的状态，不能只建一次）
-- ===== 名字 → 单位 / 队伍成员判定（1.74.1 修「踢出队伍」误显示）=====
-- ★★★用户实测（截图）：「现在是目标不在队伍，但是却显示踢出队伍」。
--   【根因】条目可见性写的是 `GetNumPartyMembers() > 0` —— 那是「**我**在不在队伍里」，
--   与「**被右键的那个人**在不在我队伍里」是两件事 ⇒ 只要自己在队伍里，右键**任何人**都会冒出「踢出队伍」。
--   【正解】照 Heart/C（C_GetUnitID.lua）的机制反查：名字 → unit id 只能**逐个比对**
--   （先 `UnitExists` 判存在、再 `UnitName` 复核），最后拿**本客户端的权威接口**下结论。
--   ★本客户端 api 表实测**有** `UnitInParty` / `UnitInRaid`（api_lua.html 类别 Unit）→ 定位到 unit 后再问它们；
--     两条都读不到时才退回「名字确实出现在 raid/party 名单里」这一步的结论（判不准就**不给条目**的另一半：
--     这里给的是「在名单里」这个**已核实**的事实，不是猜）。
--   ★上界纪律（记忆体 F3）：**party 只有 party1..party4**；`GetNumPartyMembers()` 在团队里返回
--     「raid 人数 - 1」，**绝不能**拿它当 party 循环上界（40 人团会去试 party1..party39）。
--     raid 直接 raid1..`GetNumRaidMembers()`（**含自己** → 必须显式排除自己）。
local function tbUnitNameLower(unit)
  if type(UnitName) ~= "function" then return nil end
  local ok, n = pcall(UnitName, unit)
  if not ok or type(n) ~= "string" or n == "" then return nil end
  return string.lower(n)
end
local function tbNameEqUnit(wantLower, unit)
  if type(UnitExists) ~= "function" then return false end
  local oke, ex = pcall(UnitExists, unit)
  if not (oke and ex) then return false end -- ★先判存在：不存在的单位 UnitName 回 nil（别拿 nil 去比）
  local un = tbUnitNameLower(unit)
  if un == nil then return false end
  if un == wantLower then return true end
  local dash = string.find(un, "-", 1, true)
  if dash and string.sub(un, 1, dash - 1) == wantLower then return true end -- 「名字-服务器」形态也认
  return false
end
-- 名字 → unit id（找不到返回 nil）。查询顺序：团队（含自己）→ 小队 party1..4
function EVAL_TB_NAME_UNITOF(name)
  local want = string.lower(tostring(name or ""))
  if want == "" then return nil end
  local rn = 0
  if type(GetNumRaidMembers) == "function" then
    local ok, v = pcall(GetNumRaidMembers)
    if ok and type(v) == "number" and v > 0 then rn = v end
  end
  for i = 1, rn do
    local u = "raid" .. i
    if tbNameEqUnit(want, u) then return u end
  end
  for i = 1, 4 do -- ★party 只有 1..4（见上：不能拿 GetNumPartyMembers 当上界）
    local u = "party" .. i
    if tbNameEqUnit(want, u) then return u end
  end
  return nil
end
-- 被右键的人**是不是我的队伍/团队成员**（★「踢出队伍」条目的唯一可见性判据）
--   自己不算（踢自己 = 退队，菜单不给这条）
function EVAL_TB_NAME_INMYGROUP(name)
  local s = tostring(name or "")
  if s == "" then return false end
  local me = tbUnitNameLower("player")
  if me ~= nil and me == string.lower(s) then return false end
  local u = EVAL_TB_NAME_UNITOF(s)
  if u == nil then return false end
  local known, inGroup = false, false
  if type(UnitInParty) == "function" then
    local ok, v = pcall(UnitInParty, u)
    if ok then known = true if v then inGroup = true end end
  end
  if type(UnitInRaid) == "function" then
    local ok, v = pcall(UnitInRaid, u)
    if ok then known = true if v then inGroup = true end end
  end
  if inGroup then return true end
  if known then return false end
  return true -- ★两条 API 都读不到 → 退回「名字确实在 raid/party 名单里」这个已核实的事实
end
local TB_MENU_SIG = nil
-- 条目清单 = 数据（顺序即显示顺序：先读一行、再读一列）；加/删条目只改这里
-- ★1.73.42u 条目清单现在**按名字**判断（删除好友只在「已是好友」时出现）→ 入参 name；
--   ★并且改成**每次显示都重算**（见 tbMenuEnsure）：好友/队伍/权限都是会变的状态，
--     原来「首次右键时建一次、之后一直用那份冻结清单」= 加完好友再右键也看不到「删除好友」。
local function tbMenuItems(name)
  local out = {}
  local function add(label, fn)
    if type(label) == "string" and label ~= "" and type(fn) == "function" then
      table.insert(out, { label, fn })
    end
  end
  -- 第一列：原始功能三条 + 我们的「复制名字」
  if type(ChatFrame_OpenChat) == "function" or type(ChatEdit_ActivateChat) == "function" then
    add(L("TB_NAMEMENU_WHISPER"), EVAL_TB_NAME_WHISPER)
  end
  -- ★★★1.73.39 用户要求：「分享方案 ↔ 邀请 对调位置」——分享方案挪到第 2 位（第一行右列），邀请挪到第 5 位
  add(L("TB_NAMEMENU_SHARE"), EVAL_TB_NAME_SHARE)
  add(L("TB_NAMEMENU_TARGET"), EVAL_TB_NAME_TARGET)
  add(L("TB_NAMEMENU_SAY"), EVAL_TB_NAME_SAY)
  add(L("TB_NAMEMENU_TRADE"), EVAL_TB_NAME_TRADE)
  -- ★★★1.73.42w 用户要求（三条）：
  --   ① 「邀请」改名 **邀请队伍**；② **只在未在队伍内**时显示（在队伍里藏掉）；
  --   ③ 「踢出队伍」挪到**查询上面**（同一格由队伍状态决定显示哪条：没队伍=邀请队伍，有队伍=取消邀请+踢出队伍）。
  -- ★★「我在不在队伍里」——决定「邀请队伍 / 离开队伍」出不出现（1.73.42w ②：在队伍里就藏掉邀请）
  local tbInParty = false
  if type(GetNumPartyMembers) == "function" then
    local ok, n = pcall(GetNumPartyMembers)
    tbInParty = ok and type(n) == "number" and n > 0
  end
  -- ★★★1.74.2「我是不是队长」（用户：「邀请队伍 / 提出队伍 只有队长才显示」）：
  --   ★「邀请队伍」改判**不在队伍 或 我是队长**（官方「Invite」的可用域：单人可邀、队长可再邀、非队长不可邀）——
  --     旧写法只在「不在队伍」时显示 ⇒ **队长在队伍里反而邀不了人**（本轮审计出的 bug）。
  --   ★助理也踢得动人、但本客户端**没有** IsRaidAssistant 接口 ⇒ 队长判定 = `IsPartyLeader()` 或 `IsRaidLeader()`，
  --     助理看不到这条（如实接受的边界；动作里仍有一道「不是队长」兜底）。
  local tbIsLeader = false
  if type(IsPartyLeader) == "function" then
    local okL, lead = pcall(IsPartyLeader)
    if okL and lead == true then tbIsLeader = true end
  end
  if not tbIsLeader and type(IsRaidLeader) == "function" then
    local okR, rlead = pcall(IsRaidLeader)
    if okR and rlead == true then tbIsLeader = true end
  end
  -- ★★★1.74.4 用户（截图：对方已入队却仍显示「邀请队伍」）：条件还**漏看「对方是否已在我队伍里」** ——
  --   已在我队伍/团队里的人**不该再出现**「邀请队伍」（邀了也是无操作）；它只看「我」的状态是 bug。
  if (not EVAL_TB_NAME_INMYGROUP(name)) and ((not tbInParty) or tbIsLeader) then add(L("TB_NAMEMENU_PARTY"), EVAL_TB_NAME_PARTY) end -- 对方不在我队伍里，且（没队伍或我是队长）才给「邀请队伍」
  -- ★★★1.74.1 修（用户实测：「目标不在队伍，却显示踢出队伍」）：
  --   可见性判据必须是「**被右键的这个人**是不是我的队伍/团队成员」，而不是「我自己在不在队伍里」。
  --   （旧写法用 tbInParty ⇒ 只要自己在队伍里，右键任何人都会冒出「踢出队伍」。）
  --   ★条目只按「是不是成员」给；**队长身份由动作如实报**（不是队长点了会说「你不是队长」）——
  --     因为团队里的**助理**同样能踢人，而本客户端**没有** IsRaidAssistant 这类接口可以判助理。
  -- ★★★1.74.2 用户：「提出队伍 只有队长才显示」⇒ 条目可见性**也要**求「我是队长」（原来是「是成员就显示、
  --   点了动作才说『你不是队长』」——用户要的是**非队长根本不出现这条**）。
  if EVAL_TB_NAME_INMYGROUP(name) and tbIsLeader then
    add(L("TB_NAMEMENU_KICKP"), EVAL_TB_NAME_KICKP)
  end
  -- ★★★1.74.2 用户：「添加离开队伍，只有在队伍内才显示」⇒ 新增这条（我离开队伍；与右键的人无关）。
  if tbInParty then add(L("TB_NAMEMENU_LEAVEP"), EVAL_TB_NAME_LEAVEP) end
  add(L("TB_NAMEMENU_QUERY"), EVAL_TB_NAME_QUERY)
  -- ★有权限才显示「踢出公会 / 邀请公会」
  if type(CanGuildRemove) == "function" then
    local ok, v = pcall(CanGuildRemove)
    if ok and v then add(L("TB_NAMEMENU_KICKG"), EVAL_TB_NAME_KICKG) end
  end
  if type(CanGuildInvite) == "function" then
    local ok, v = pcall(CanGuildInvite)
    if ok and v then add(L("TB_NAMEMENU_INVITE"), EVAL_TB_NAME_INVITE) end
  end
  -- ★★★1.73.42x 好友（用户：「删除好友.和添加好友应该每次是只能显示一个. 要根据实际状态判断显示」）：
  --   **已经是好友 → 只给「删除好友」；不是好友 → 只给「添加好友」**（两条永不同时出现）。
  --   ★判断不出来时（GetNumFriends/GetFriendInfo 缺、或名字缓存还没到）→ 按「不是好友」处理、只给「添加好友」：
  --     宁可让玩家点一下「添加好友」（服务器会忽略重复），也**绝不**把「删除好友」摆在不确定的人身上（误删更糟）。
  local isFriendNow = (type(EVAL_TB_NAME_ISFRIEND) == "function") and (EVAL_TB_NAME_ISFRIEND(name) == true)
  if isFriendNow then
    if type(RemoveFriend) == "function" then add(L("TB_NAMEMENU_DELFRIEND"), EVAL_TB_NAME_DELFRIEND) end
  elseif type(AddFriend) == "function" then
    add(L("TB_NAMEMENU_ADDFRIEND"), EVAL_TB_NAME_ADDFRIEND)
  end
  return out
end
-- ★★★1.73.40 「圆角」：用客户端**原生**的圆角边框贴图（vanilla 右键菜单/提示框就是这一套：
--   bgFile = UI-Tooltip-Background + edgeFile = UI-Tooltip-Border + edgeSize 16 + insets）。
--   参考插件 Compatibility/ClientAPI.lua:2406-2414 有两条**实测**记录，照抄：
--     ① backdrop 表里**不给 edgeFile**时，边框贴图会留在表里继续画（想要边框就得显式给 edgeFile）；
--     ② **小数 edgeSize 在本客户端栅格化不可靠** → 一律用整数。
--   ★读回来确认：GetBackdrop() 的边框段报出这张边贴图才算真挂上；读不到（本客户端可能没这个读值口）按「无法验证」处理，
--   但**挂不上就退回四条平边**，绝不静默丢掉白色高亮边框。
local function tbMenuChrome(f, W, H)
  local kind, edge, border = "flat", nil, {}
  if type(f.SetBackdrop) == "function" then
    local ok = pcall(f.SetBackdrop, f, {
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = TB_MENU_EDGE, edgeSize = TB_MENU_EDGE,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    if ok then
      if type(f.SetBackdropColor) == "function" then
        pcall(f.SetBackdropColor, f, TB_MENU_COLORS.panelRGBA[1], TB_MENU_COLORS.panelRGBA[2], TB_MENU_COLORS.panelRGBA[3], TB_MENU_COLORS.panelRGBA[4])
      end
      if type(f.SetBackdropBorderColor) == "function" then
        pcall(f.SetBackdropBorderColor, f, TB_MENU_COLORS.borderRGBA[1], TB_MENU_COLORS.borderRGBA[2], TB_MENU_COLORS.borderRGBA[3], TB_MENU_COLORS.borderRGBA[4]) -- 白色高亮（1.73.39 的要求）
      end
      if type(f.GetBackdrop) == "function" then
        local oks, str = pcall(f.GetBackdrop, f)
        if oks and type(str) == "string" then edge = str end
      end
      if edge == nil or string.find(edge, "UI-Tooltip-Border", 1, true) ~= nil then
        kind = "rounded"
      end
    end
  end
  if kind == "flat" then
    -- 退化路径 = 1.73.39 的四条 1px 平白边（半透明白，别抢文字）
    local function edgeTex(name, ax, ay, w2, h2)
      local t = f:CreateTexture(nil, "BORDER")
      tbSolid(t, TB_MENU_COLORS.flatRGBA[1], TB_MENU_COLORS.flatRGBA[2], TB_MENU_COLORS.flatRGBA[3], TB_MENU_COLORS.flatRGBA[4])
      t:SetPoint("TOPLEFT", f, "TOPLEFT", ax, ay)
      t:SetWidth(w2) t:SetHeight(h2)
      border[name] = t
    end
    edgeTex("top", 0, 0, W, 1)
    edgeTex("bottom", 0, -(H - 1), W, 1)
    edgeTex("left", 0, 0, 1, H)
    edgeTex("right", W - 1, 0, 1, H)
  end
  return { kind = kind, edge = edge, border = border }
end
local function tbMenuBuild(items)
  items = items or tbMenuItems(TB_NAME_MENU.name)
  local n = table.getn(items) + 1 -- +1 = [关闭]
  local W, H = EVAL_TB_MENU_LAYOUT(n)
  local f = CreateFrame("Frame", "EVAL_TB_NAMEMENU", UIParent)
  f:SetWidth(W) f:SetHeight(H)
  -- ★锚点：默认放屏幕右下角；真正显示时 EVAL_TB_MENU_SHOW 会改成「相对鼠标点击位置的右上角」
  f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
  pcall(f.SetFrameStrata, f, "DIALOG")
  pcall(f.SetFrameLevel, f, 250)
  pcall(f.EnableMouse, f, true)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  tbSolid(bg, TB_MENU_COLORS.panelRGBA[1], TB_MENU_COLORS.panelRGBA[2], TB_MENU_COLORS.panelRGBA[3], TB_MENU_COLORS.panelRGBA[4]) -- 外框背景（加深）
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.bg = bg
  -- ★★★1.73.40 用户「圆角」（1.73.39「边框 白色高亮」继续保留）：能挂上客户端**原生圆角边贴图**就用它，
  --   挂不上就退回四条 1px 白边（退化路径在 tbMenuChrome 里，两条路都有断言）。
  local chrome = tbMenuChrome(f, W, H)
  f.border = chrome.border
  f.chrome = chrome.kind
  f.chromeEdge = chrome.edge
  -- ★圆角时底由 backdrop 自己画（insets 4 → 落在圆角内侧）；再叠一层自己的方形半透明底会发黑
  if chrome.kind == "rounded" then pcall(bg.Hide, bg) end
  local title = tbText(f, 10, 0.95, 0.82, 0.35)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", TB_MENU_PAD.x, -TB_MENU_PAD.t)
  pcall(title.SetWidth, title, W - TB_MENU_PAD.x * 2)
  pcall(title.SetJustifyH, title, "LEFT")
  f.title = title
  f.rows = {}
  -- ★两列：第 i 条 → 列 = (i-1) % 2、行 = floor((i-1)/2)（坐标全由 TB_MENU_* 常量算出）
  local function put(i, label, fn)
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x = TB_MENU_PAD.x + col * (TB_MENU_COL_W + TB_MENU_GAP)
    local y = TB_MENU_TOP - row * TB_MENU_ITEM_H
    local b = tbBtn(f, x, y, TB_MENU_COL_W, label, fn, nil)
    -- ★条目底**透明**（用户「背景透明」）：底色只在这里写一次，悬停**不再动它**
    if b.bg then
      pcall(b.bg.SetVertexColor, b.bg, TB_MENU_COLORS.itemRGBA[1], TB_MENU_COLORS.itemRGBA[2],
            TB_MENU_COLORS.itemRGBA[3], TB_MENU_COLORS.itemRGBA[4])
    end
    if b.text then
      pcall(b.text.SetWidth, b.text, TB_MENU_COL_W - 6)
      pcall(b.text.SetJustifyH, b.text, "LEFT")
    end
    -- ★★★1.73.40 用户「右键框内操作按键 鼠标获取焦点 增加变色美化」：
    --   悬停高亮 —— 本项目配方禁用 SetHighlightTexture，一律 OnEnter/OnLeave **改颜色**
    --   （底色变亮金 + 文字变亮），并挂在**真实 OnEnter/OnLeave 脚本**上（判据走真实脚本触发）。
    local function paint(hot)
      -- ★★★1.73.40 用户：「操作获取加点白色，只要文字变色，**不用背景变色**」→
      --   这里**只**动 FontString 的颜色（不加白底、不改底色）。
      local tc = hot and TB_MENU_COLORS.txtHotRGBA or TB_MENU_COLORS.txtRGBA
      if b.text and type(b.text.SetTextColor) == "function" then
        pcall(b.text.SetTextColor, b.text, tc[1], tc[2], tc[3])
      end
      b.hot = hot and true or false
    end
    b.paint = paint
    pcall(b.btn.SetScript, b.btn, "OnEnter", function() paint(true) end)
    pcall(b.btn.SetScript, b.btn, "OnLeave", function() paint(false) end)
    paint(false)
    table.insert(f.rows, b)
    return b
  end
  for i = 1, table.getn(items) do
    local it = items[i]
    -- ★点击那一刻再读名字（不捕获构建期快照 —— 快照在「首次右键」时必定是 nil）
    put(i, it[1], function() it[2](TB_NAME_MENU.name) EVAL_TB_MENU_HIDE() end)
  end
  -- ★★★「关闭」原来是空函数（点了什么都不做）→ 真的关
  put(table.getn(items) + 1, L("TB_NAMEMENU_CLOSE"), function() EVAL_TB_MENU_HIDE() end)
  pcall(f.Hide, f)
  TB.menu = f
  return f
end

function EVAL_TEST_TB_MENU_DROP()
  if TB.menu then pcall(TB.menu.Hide, TB.menu) end
  TB.menu = nil
  TB_MENU_SIG = nil
  TB_NAME_MENU.shown = false
  return true
end
-- ★★★1.73.37 测试：按**标签**点菜单条目 —— 走按钮的**真实 OnClick**（不是直接调动作函数）
--   （1.73.35 的教训：测试直接调动作函数 → 按钮接线断了也照样绿）
function EVAL_TEST_TB_MENU_CLICK(label)
  if not TB.menu then return false end
  local want = tostring(label or "")
  for i = 1, table.getn(TB.menu.rows or {}) do
    -- ★注意：tbBtn 返回的是**包裹表** {btn,bg,text} —— 文字在包裹表上、脚本在 .btn 上
    --   （第一版我写成 b.btn.text → 永远读不到标签，「点到了吗」恒 false；这正是本项目那个老坑）
    local b = TB.menu.rows[i]
    if b and b.text and b.btn then
      local ok, t = pcall(b.text.GetText, b.text)
      if ok and tostring(t or "") == want then
        local okf, fn = pcall(b.btn.GetScript, b.btn, "OnClick")
        if okf and type(fn) == "function" then
          pcall(fn)
          return true
        end
        return false
      end
    end
  end
  return false
end
-- ★★★1.73.40 测试：按**标签**触发菜单条目的鼠标悬停 —— 走的是按钮**真实的 OnEnter/OnLeave 脚本**
--   （不是直接调 paint：接线断了这样才会响）。on == false → 触发 OnLeave。
function EVAL_TEST_TB_MENU_HOVER(label, on)
  if not TB.menu then return false end
  local want = tostring(label or "")
  local ev = (on == false) and "OnLeave" or "OnEnter"
  for i = 1, table.getn(TB.menu.rows or {}) do
    local b = TB.menu.rows[i]
    if b and b.text and b.btn then
      local ok, t = pcall(b.text.GetText, b.text)
      if ok and tostring(t or "") == want then
        local okf, fn = pcall(b.btn.GetScript, b.btn, ev)
        if okf and type(fn) == "function" then pcall(fn) return true end
        return false
      end
    end
  end
  return false
end
function EVAL_TB_MENU_GEOM()
  if not TB.menu then return nil end
  local f = TB.menu
  local function num(m, o) local ok, v = pcall(m, o) return (ok and type(v) == "number") and v or nil end
  local out = { w = num(f.GetWidth, f), h = num(f.GetHeight, f), items = {}, bg = {} }
  -- ★1.73.35 锚点读值（用户要求「弹窗锚点右上」→ 判据必须读得到真实的锚点语义）
  local okp, point, _relTo, relPoint, ox, oy = pcall(f.GetPoint, f)
  if okp then out.point, out.relPoint, out.ox, out.oy = point, relPoint, ox, oy end
  -- ★1.73.39 边框读值口（用户要求「白色高亮」→ 判据要读得到颜色与尺寸）
  out.border = {}
  if f.border then
    local names = { "top", "bottom", "left", "right" }
    for i = 1, table.getn(names) do
      local t = f.border[names[i]]
      if t then
        local b = { w = num(t.GetWidth, t), h = num(t.GetHeight, t) }
        if type(t.GetVertexColor) == "function" then
          local okc, cr, cg, cb2, ca = pcall(t.GetVertexColor, t)
          if okc then b.r, b.g, b.b, b.a = cr, cg, cb2, ca end
        end
        out.border[names[i]] = b
      end
    end
  end
  -- ★1.73.40 圆角读值口：菜单用的是**原生圆角边**（rounded）还是**四条平边**（flat）退化路径
  -- ★1.73.40 padding 读值口（用户「框增加 padding」）
  out.padX, out.padT, out.padB = TB_MENU_PAD.x, TB_MENU_PAD.t, TB_MENU_PAD.b
  out.titleH = TB_MENU_TITLE_H
  if f.title then out.titleLeft = num(f.title.GetLeft, f.title) out.titleTop = num(f.title.GetTop, f.title) end
  out.chrome = f.chrome
  out.edge = f.chromeEdge
  if f.bg and type(f.bg.IsShown) == "function" then
    local oksh, sh = pcall(f.bg.IsShown, f.bg)
    if oksh then out.bgShown = sh and true or false end
  end
  if f.bg and type(f.bg.GetVertexColor) == "function" then
    local ok, r, g, b, a = pcall(f.bg.GetVertexColor, f.bg)
    if ok then out.bg = { r = r, g = g, b = b, a = a } end
  end
  for i = 1, table.getn(f.rows or {}) do
    local b = f.rows[i]
    local ok, t = pcall(b.text.GetText, b.text)
    local it = { label = (ok and tostring(t or "")) or "",
                 x = num(b.btn.GetLeft, b.btn), y = num(b.btn.GetTop, b.btn),
                 w = num(b.btn.GetWidth, b.btn), h = num(b.btn.GetHeight, b.btn) }
    -- ★1.73.40 悬停读值口：底色从**真控件读回**（不是回显常量）+ 当前是否高亮
    if b.bg and type(b.bg.GetVertexColor) == "function" then
      local okc, cr, cg, cb2b, ca = pcall(b.bg.GetVertexColor, b.bg)
      if okc then it.r, it.g, it.b, it.a = cr, cg, cb2b, ca end
    end
    -- ★1.73.40 文字色读值口（「只要**文字**变色」→ 必须能分别读到文字色与底色）
    if b.text and type(b.text.GetTextColor) == "function" then
      local okt, tr, tg, tb2b = pcall(b.text.GetTextColor, b.text)
      if okt then it.tr, it.tg, it.tb = tr, tg, tb2b end
    end
    it.hot = b.hot and true or false
    out.items[i] = it
  end
  return out
end
-- ★探针（1.73.28 改）：报「这个菜单真正要用的接口」在不在 ——
--   悄悄话要能打开聊天框、邀请要有邀请 API、目标要有 TargetByName；缺哪个就如实降级并说清楚。
function EVAL_TB_MENU_API_PROBE()
  local names = { "InviteToParty", "InviteByName", "TargetByName", "GuildInviteByName", "CanGuildInvite",
                  "ChatFrame_OpenChat", "ChatEdit_ActivateChat", "ChatFrameEditBox", "ChatFrame1EditBox", "SetItemRef" }
  local parts = {}
  for i = 1, table.getn(names) do
    local v = _G[names[i]]
    local t = type(v)
    if t == "table" then
      local n = 0
      for _ in pairs(v) do n = n + 1 end
      t = "table(" .. tostring(n) .. ")"
    end
    table.insert(parts, names[i] .. "=" .. t)
  end
  say("右键菜单接口探针（function = 可用）：")
  say("  " .. table.concat(parts, " ｜ "))
  if type(ChatFrame_OpenChat) ~= "function" and type(ChatEdit_ActivateChat) ~= "function" then
    say("|cffff8080  ⇒ 没有「打开聊天框」的接口：菜单里的「悄悄话」会如实提示请手动 /w（不静默）|r")
  end
  -- ★★★1.73.40 「圆角」落地状态（取证用：这一条一屏就能区分「客户端挂上了原生圆角边」还是「退回了平边」）——
  --   用户报「还是没有圆角」时，先看这一行，不要凭猜（本项目取证协议）。
  local chrome, edgeTxt = "未建（右键点一次名字再看）", "-"
  if TB.menu then
    chrome = tostring(TB.menu.chrome or "?")
    edgeTxt = tostring(TB.menu.chromeEdge or "-")
  end
  say("  边框做法 = " .. chrome .. " ｜ GetBackdrop 读回 = " .. edgeTxt)
  return true
end
-- ★1.73.42u 条目集签名（声明在文件上方，见 TB_MENU_SIG 注释）：集合一变就重建，没变就复用
local function tbMenuEnsure()
  local items = tbMenuItems(TB_NAME_MENU.name)
  local sig = ""
  for i = 1, table.getn(items) do sig = sig .. "|" .. tostring(items[i][1]) end
  if TB.menu and TB_MENU_SIG == sig then return TB.menu end
  if TB.menu then pcall(TB.menu.Hide, TB.menu) TB.menu = nil end
  local f = tbMenuBuild(items)
  TB_MENU_SIG = sig
  TB.menuSig = sig
  return f
end
-- ★★★1.73.42y 上次好友动作的**延迟核对**：好友列表是服务器回话后才变的 → 开菜单时若有一笔 pending 且已过 1 秒，
--   就当场核对并给出**真结果**（删成功/仍在列表 / 加成功/还没出现）——这才是「不假成功也不假失败」。
local function tbFriendVerifyPending()
  local p = TB_NAME_MENU.pendingFriend
  if type(p) ~= "table" or type(p.name) ~= "string" then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (tonumber(p.at) or 0) < 1 then return end -- 至少给服务器 1 秒
  TB_NAME_MENU.pendingFriend = nil
  local still = (tbFriendIndex(p.name) ~= nil)
  if p.kind == "remove" then
    if still then say(string.format(L("TB_NAMEMENU_FRIENDPENDON"), p.name))
    else say(string.format(L("TB_NAMEMENU_FRIENDREMOVEOK"), p.name)) end
  else
    if still then say(string.format(L("TB_NAMEMENU_FRIENDADDOK"), p.name))
    else say(string.format(L("TB_NAMEMENU_FRIENDPENDOFF"), p.name)) end
  end
end
function EVAL_TB_MENU_SHOW(name)
  if not EVAL_TB_NAMEMENU_ON() then return false end
  if type(name) ~= "string" or name == "" then return false end
  -- ★★★1.73.37 用户报「某些按键点了没反应」——【根因】名字必须在 **build 之前**写好：
  --   原顺序是 build → 赋值，而条目闭包在建菜单时就把 TB_NAME_MENU.name（当时是 nil）**捕获**了
  --   → 所有动作都拿到 nil → 静默返回 false（点了像没反应）。
  TB_NAME_MENU.name = name
  tbFriendVerifyPending() -- ★1.73.42y 先把上次好友动作的**真实结果**核对出来（服务器回话后才准）
  local f = tbMenuEnsure() -- ★每次显示按当前状态重算条目（好友/队伍/权限会变）
  if f.title then pcall(f.title.SetText, f.title, string.format(L("TB_NAMEMENU_TITLE"), name)) end
  -- ★★★1.73.36 用户澄清：**相对鼠标点击位置的右上角** —— 弹窗的**左下角贴光标**，向上、向右展开
  --   （拿不到光标 → 退回屏幕右下角；贴到屏幕边时**夹取**，保证菜单不会跑出屏幕）。
  --   ★坐标要按 UIParent 缩放折算（GetCursorPosition 给的是物理像素），否则高缩放下会飘。
  local px, py = nil, nil
  if type(GetCursorPosition) == "function" then
    local okc, cx, cy = pcall(GetCursorPosition)
    if okc and type(cx) == "number" and type(cy) == "number" then px, py = cx, cy end
  end
  local sc = 1
  if type(UIParent) == "table" and type(UIParent.GetEffectiveScale) == "function" then
    local oks, s = pcall(UIParent.GetEffectiveScale, UIParent)
    if oks and type(s) == "number" and s > 0 then sc = s end
  end
  pcall(f.ClearAllPoints, f)
  if px and py then
    px, py = px / sc, py / sc
    local W, H = 128, 100
    local okw, w1 = pcall(f.GetWidth, f)
    if okw and type(w1) == "number" then W = w1 end
    local okh, h1 = pcall(f.GetHeight, f)
    if okh and type(h1) == "number" then H = h1 end
    local sw, sh = 1024, 768
    if type(UIParent) == "table" then
      local ok1, s1 = pcall(UIParent.GetWidth, UIParent)
      if ok1 and type(s1) == "number" then sw = s1 end
      local ok2, s2 = pcall(UIParent.GetHeight, UIParent)
      if ok2 and type(s2) == "number" then sh = s2 end
    end
    if px + W > sw then px = math.max(0, sw - W) end
    if py + H > sh then py = math.max(0, sh - H) end
    pcall(f.SetPoint, f, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", px, py) -- 左下角 = 光标
  else
    pcall(f.SetPoint, f, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 10)
  end
  pcall(f.Show, f)
  TB_NAME_MENU.shown = true
  return true
end
-- ★★★1.73.29 预填聊天输入框（不发送）：悄悄话与「复制名字」共用这一条实现。
--   优先客户端自带的打开聊天框接口；没有就退回 ChatEdit_ActivateChat + 编辑框；两条都不行 → 返回 nil（调用方如实提示）。
--   ★「不要打印出去」= 我们**只把文本放进输入框**，绝不替用户按回车（不走 SendChatMessage / RunScript）。
local function tbMenuPrefill(text)
  if type(text) ~= "string" or text == "" then return nil end
  if type(ChatFrame_OpenChat) == "function" then
    if pcall(ChatFrame_OpenChat, text) then return "openchat" end
  end
  local eb = _G.ChatFrameEditBox or _G.ChatFrame1EditBox
  if type(ChatEdit_ActivateChat) == "function" and eb and type(eb.SetText) == "function" then
    local ok = pcall(function()
      ChatEdit_ActivateChat(eb)
      eb:SetText(text)
      if type(eb.HighlightText) == "function" then eb:HighlightText() end
    end)
    if ok then return "editbox" end
  end
  return nil
end
-- ★1.73.28 服务器写动作一律限频：邀请 / 密语（发消息）在 0.5 秒内只做一次
local TB_MENU_AT = {}
local function tbMenuThrottle(key, gap)
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB_MENU_AT[key] or -99) < (tonumber(gap) or 0.5) then
    TB_NAME_MENU.throttled = (TB_NAME_MENU.throttled or 0) + 1
    say(L("TB_NAMEMENU_TOOFAST"))
    return false
  end
  TB_MENU_AT[key] = now
  return true
end
-- 公会邀请（★先问 CanGuildInvite，再直接调；直接调不可用就走 RunScript）
function EVAL_TB_NAME_INVITE(name)
  if type(name) ~= "string" or name == "" then return false end
  if type(CanGuildInvite) == "function" then
    local okc, v = pcall(CanGuildInvite)
    if okc and v == false then
      say(string.format(L("TB_NAMEMENU_INVFAIL"), "CanGuildInvite=false"))
      return false
    end
  end
  local safe = tbSafeName(name)
  local okd = false
  if type(GuildInviteByName) == "function" then
    okd = pcall(GuildInviteByName, safe)
    if okd then TB_NAME_MENU.inviteDirect = (TB_NAME_MENU.inviteDirect or 0) + 1 end
  end
  if not okd then
    okd = pcall(RunScript, "GuildInviteByName(\"" .. safe .. "\")")
    if okd then TB_NAME_MENU.inviteScript = (TB_NAME_MENU.inviteScript or 0) + 1 end
  end
  if okd then say(string.format(L("TB_NAMEMENU_INVOK"), safe))
  else say(string.format(L("TB_NAMEMENU_INVFAIL"), "GuildInviteByName")) end
  return okd
end
-- 邀请入队（原始功能「邀请」）：**按名字** InviteByName 优先 → 目标/鼠标指向正是他时用 InviteToParty(UnitID) → 最后 RunScript
-- ★★★1.73.42s 用户真机反馈：「右键邀请触发」——点了邀请、聊天说「已邀请入队」，但实际什么都没发生。
--   两条**假成功**的来源（本客户端 API 表实测：InviteToParty / InviteByName / IsPartyLeader / GetNumPartyMembers 都有）：
--     ① **不是队长**时服务器会静默忽略邀请 —— 客户端不报错，我们就当成成功了；
--     ② `RunScript` 只是把脚本**排队**，入队本身**永远不失败**（真机上脚本还可能因为接口不可调而静默报错）
--        → 拿它当「已邀请成功」播报就是**假承诺**。
--   ⇒ 现在：先查队长（不该发就**不发**并说清）→ 直调哪个 API 就记哪个 → 只剩 RunScript 这条路时**只播报「已排队，无法确认」**。
function EVAL_TB_NAME_PARTY(name)
  if type(name) ~= "string" or name == "" then return false end
  if not tbMenuThrottle("party", 0.5) then return false end
  local safe = tbSafeName(name)
  -- ① 队长门：不在队伍里 = 队长（邀请有效）；在队伍里而我不是队长 → 服务器忽略，**干脆不发**
  local notLeader = false
  if type(GetNumPartyMembers) == "function" and type(IsPartyLeader) == "function" then
    local okn, n = pcall(GetNumPartyMembers)
    if okn and (tonumber(n) or 0) > 0 then
      local okl, lead = pcall(IsPartyLeader)
      if okl and lead == false then notLeader = true end
    end
  end
  if notLeader then
    TB_NAME_MENU.partyNotLeader = (TB_NAME_MENU.partyNotLeader or 0) + 1
    say(L("TB_NAMEMENU_PARTYNOTLEAD"))
    return false
  end
  -- ② ★★★1.73.42t **接口语义按客户端官方 wiki 实测**（emberveil.org/wiki/lua/globals/Group）：
  --     · `InviteByName(Name)` —— **按角色名**邀请（名字 trim；名字为空退回当前目标；邀自己报 invite-self 且不发）；
  --     · `InviteToParty(unit)` —— 收的是 **UnitID**（target / party1 …），**不是角色名**；「unit 为空或不存在时**什么都不做**」。
  --   ★老实现先调 `InviteToParty(角色名)` → 等于「unit 不存在」→ **静默 no-op 却返回成功** ⇒
  --     用户看到「已发出邀请请求」而对方毫无反应（真机截图定案）。
  --   ⇒ 现在：**先按名字 InviteByName**；`InviteToParty` 只在「目标/鼠标指向正好是这个人」时才用（那才是它的正确用法）。
  if type(UnitName) == "function" then
    local okme, me = pcall(UnitName, "player")
    if okme and type(me) == "string" and me ~= "" and string.lower(me) == string.lower(safe) then
      TB_NAME_MENU.partySelf = (TB_NAME_MENU.partySelf or 0) + 1
      say(L("TB_NAMEMENU_PARTYSELF"))
      return false
    end
  end
  local unitTok = nil
  if type(UnitName) == "function" then
    for _, u in ipairs({ "target", "mouseover" }) do
      local oku, un = pcall(UnitName, u)
      if oku and type(un) == "string" and un ~= "" and string.lower(un) == string.lower(safe) then unitTok = u break end
    end
  end
  local ok, via = false, nil
  if type(InviteByName) == "function" then
    ok = pcall(InviteByName, safe)
    if ok then via = "InviteByName" end
  end
  if not ok and unitTok and type(InviteToParty) == "function" then
    ok = pcall(InviteToParty, unitTok) -- ★只喂 UnitID（喂角色名只会静默无效）
    if ok then via = "InviteToParty(" .. unitTok .. ")" end
  end
  if not ok then
    -- ③ 后路：RunScript 只代表「已排队」——**不当成功**，措辞与计数都分开；★排的脚本也用**按名字**那个接口
    local okq = pcall(RunScript, "InviteByName(\"" .. safe .. "\")")
    if okq then
      TB_NAME_MENU.partyScript = (TB_NAME_MENU.partyScript or 0) + 1
      say(string.format(L("TB_NAMEMENU_PARTYSCRIPT"), safe))
      return true
    end
  end
  if ok then
    TB_NAME_MENU.party = (TB_NAME_MENU.party or 0) + 1
    TB_NAME_MENU.partyVia = via
    say(string.format(L("TB_NAMEMENU_PARTYOK"), safe))
  else
    TB_NAME_MENU.partyFail = (TB_NAME_MENU.partyFail or 0) + 1
    say(string.format(L("TB_NAMEMENU_PARTYFAIL"), "InviteToParty / InviteByName"))
  end
  return ok
end
-- ===== 1.73.42u 好友：判定 + 增删（用户要求：右键菜单加「添加好友 / 删除好友（是好友才显示）」）=====
--   ★语义按客户端官方 wiki（emberveil.org/wiki/lua/globals/Friend）：
--     · `AddFriend(name)` —— 「Sends a friends-list add for name」，**无返回值**；
--     · `RemoveFriend(index)` / `RemoveFriend(name)` —— **按 1-based 序号或角色名**都行（不是数字时按名字）；
--     · `GetFriendInfo(i)` —— 六返回值；★**name 来自本地缓存，可能暂时为空**（名字查询还没回来）⇒
--       读不到名字时**不能确认**（既不把空行当好友，也不假称已加/已删）。
--   ⇒ 一律用「操作前后 `GetNumFriends()` 对比」如实播报：变了 = 成功；没变 = 请求已发但**确认不了**（绝不假成功）。
-- 添加好友：先查是不是已经在列表里（不重复加）→ AddFriend → **按条数变化**如实播报
function EVAL_TB_NAME_ADDFRIEND(name)
  if type(name) ~= "string" or name == "" then return false end
  if type(AddFriend) ~= "function" then
    say(string.format(L("TB_NAMEMENU_FRIENDNOAPI"), "AddFriend"))
    return false
  end
  local safe = tbSafeName(name)
  if tbFriendIndex(safe) then
    TB_NAME_MENU.friendAlready = (TB_NAME_MENU.friendAlready or 0) + 1
    say(string.format(L("TB_NAMEMENU_FRIENDALREADY"), safe))
    return false
  end
  if not tbMenuThrottle("friend", 0.5) then return false end -- 服务器写动作：0.5 秒只做一次
  local before = tbFriendCount()
  local ok = pcall(AddFriend, safe)
  local after = tbFriendCount()
  if ok and before ~= nil and after ~= nil and after > before then
    TB_NAME_MENU.friendAdd = (TB_NAME_MENU.friendAdd or 0) + 1
    say(string.format(L("TB_NAMEMENU_FRIENDADDOK"), safe))
    return true
  end
  if ok then
    -- ★请求已发出但列表没同步变：`AddFriend` 是**服务器动作**（wiki：把名字交给服务器）→ 本地列表要等回话。
    --   **不假称成功、也绝不假称失败**：记一笔 pending，下次开菜单（≥1 秒后）再核对并如实报结果。
    TB_NAME_MENU.friendAddUnk = (TB_NAME_MENU.friendAddUnk or 0) + 1
    TB_NAME_MENU.pendingFriend = { kind = "add", name = safe, at = (type(GetTime) == "function") and GetTime() or 0 }
    say(string.format(L("TB_NAMEMENU_FRIENDADDUNK"), safe))
    return true
  end
  TB_NAME_MENU.friendFail = (TB_NAME_MENU.friendFail or 0) + 1
  say(string.format(L("TB_NAMEMENU_FRIENDFAIL"), "AddFriend"))
  return false
end
-- 删除好友：只对**确实是好友**的人动手；★优先按**序号**删（wiki 明确支持，比按名字稳）→ 没成功再按名字删
function EVAL_TB_NAME_DELFRIEND(name)
  if type(name) ~= "string" or name == "" then return false end
  if type(RemoveFriend) ~= "function" then
    say(string.format(L("TB_NAMEMENU_FRIENDNOAPI"), "RemoveFriend"))
    return false
  end
  local safe = tbSafeName(name)
  local idx = tbFriendIndex(safe)
  if not idx then
    say(string.format(L("TB_NAMEMENU_FRIENDNOTON"), safe))
    return false
  end
  if not tbMenuThrottle("friend", 0.5) then return false end
  local before = tbFriendCount()
  local ok = pcall(RemoveFriend, idx)
  local after = tbFriendCount()
  if not (ok and before ~= nil and after ~= nil and after < before) then
    local ok2 = pcall(RemoveFriend, safe) -- 后路：按名字删
    local after2 = tbFriendCount()
    if ok2 and before ~= nil and after2 ~= nil and after2 < before then
      TB_NAME_MENU.friendRemove = (TB_NAME_MENU.friendRemove or 0) + 1
      say(string.format(L("TB_NAMEMENU_FRIENDREMOVEOK"), safe))
      return true
    end
    -- ★★★1.73.42y **不再拿「条数没立刻变小」当失败**（用户真机：好友实际删掉了，界面却报「没生效」）——
    --   `RemoveFriend` 是服务器动作（wiki：把名字交给服务器），本地列表要等服务器回话才变。
    --   ⇒ 只如实说「已请求删除」，并记 pending，**下次开菜单（≥1 秒后）核对**再给出真结果。
    if ok or ok2 then
      TB_NAME_MENU.friendRemoveUnk = (TB_NAME_MENU.friendRemoveUnk or 0) + 1
      TB_NAME_MENU.pendingFriend = { kind = "remove", name = safe, at = (type(GetTime) == "function") and GetTime() or 0 }
      say(string.format(L("TB_NAMEMENU_FRIENDREMOVEUNK"), safe))
      return true
    end
    TB_NAME_MENU.friendFail = (TB_NAME_MENU.friendFail or 0) + 1
    say(string.format(L("TB_NAMEMENU_FRIENDFAIL"), "RemoveFriend"))
    return false
  end
  TB_NAME_MENU.friendRemove = (TB_NAME_MENU.friendRemove or 0) + 1
  say(string.format(L("TB_NAMEMENU_FRIENDREMOVEOK"), safe))
  return true
end
-- 选中目标：TargetByName 只认**附近**单位，够不着就如实说
function EVAL_TB_NAME_TARGET(name)
  if type(name) ~= "string" or name == "" then return false end
  if type(TargetByName) ~= "function" then
    say(string.format(L("TB_NAMEMENU_TARGETFAIL"), "TargetByName"))
    return false
  end
  local safe = tbSafeName(name)
  local ok = pcall(TargetByName, safe)
  if ok then
    TB_NAME_MENU.target = (TB_NAME_MENU.target or 0) + 1
    say(string.format(L("TB_NAMEMENU_TARGETOK"), safe))
  else
    say(string.format(L("TB_NAMEMENU_TARGETFAIL"), "TargetByName"))
  end
  return ok
end
-- 悄悄话：预填 /w 名字 + 空格，**不发送**
function EVAL_TB_NAME_WHISPER(name)
  if type(name) ~= "string" or name == "" then return false end
  local safe = tbSafeName(name)
  local how = tbMenuPrefill("/w " .. safe .. " ")
  if how then
    TB_NAME_MENU.whisper = (TB_NAME_MENU.whisper or 0) + 1
    say(string.format(L("TB_NAMEMENU_WHISPEROK"), safe))
    return true
  end
  say(string.format(L("TB_NAMEMENU_WHISPERFAIL"), safe))
  return false
end
-- 「复制名字」= 只**预填**「/s 名字」到输入框，**不发送**（用户明确：不要打印出去）
function EVAL_TB_NAME_SAY(name)
  if type(name) ~= "string" or name == "" then return false end
  local safe = tbSafeName(name)
  local how = tbMenuPrefill("/s " .. safe)
  if how then
    TB_NAME_MENU.said = (TB_NAME_MENU.said or 0) + 1
    say(string.format(L("TB_NAMEMENU_SAYOK"), safe))
    return true
  end
  say(string.format(L("TB_NAMEMENU_SAYFAIL"), safe))
  return false
end
-- ★★★1.73.35 新增动作：分享方案 / 交易 / 查询 / 踢出队伍 / 踢出公会
--   【先查 API 全表（本机 api_lua.html）】：InitiateTrade ✓ · UninviteByName ✓ · GuildUninviteByName ✓ ·
--   CanGuildRemove ✓ · CanGuildInvite ✓ · SendWho ✓ · NotifyInspect ✓ · IsPartyLeader ✓ · GetNumPartyMembers ✓
--   （**没有** PromoteToLeader / SetGuildLeader / InspectUnit —— 别写进菜单）。
-- ★名字 → unit 的解析（交易/查询都要 unit）：只扫**本机能看到**的单位；查不到就如实退回（不猜）。
local function tbUnitOf(name)
  if type(name) ~= "string" or name == "" then return nil end
  local function same(u)
    if type(UnitName) ~= "function" then return false end
    local ok, un = pcall(UnitName, u)
    if not ok or type(un) ~= "string" or un == "" then return false end
    return string.lower(un) == string.lower(name)
  end
  local fixed = { "target", "mouseover", "targettarget", "player", "pet", "partypet1", "partypet2", "partypet3", "partypet4" }
  for i = 1, table.getn(fixed) do if same(fixed[i]) then return fixed[i] end end
  for i = 1, 4 do
    local u = "party" .. i
    if same(u) then return u end
  end
  local nRaid = 0
  if type(GetNumRaidMembers) == "function" then
    local ok, n = pcall(GetNumRaidMembers)
    if ok and type(n) == "number" then nRaid = n end
  end
  for i = 1, nRaid do
    local u = "raid" .. i
    if same(u) then return u end
  end
  return nil
end
-- 分享方案：把**当前激活方案**密语给这个玩家（Share 模块同一份分片 + 同一限频队列）
function EVAL_TB_NAME_SHARE(name)
  if type(EVAL_SHARE_SEND_TO) ~= "function" then
    say(L("TB_NAMEMENU_SHAREFAIL"))
    return false
  end
  local prof = nil
  -- 激活方案名（读配置真值；拿不到就如实显示 ?）
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) == "table" and type(c.war) == "table" and type(c.war.profiles) == "table" then
    local pi = c.war.activeProfile or 1
    local p = c.war.profiles[pi]
    if type(p) == "table" then prof = p.name end
  end
  local ok = EVAL_SHARE_SEND_TO(name)
  if ok then
    TB_NAME_MENU.share = (TB_NAME_MENU.share or 0) + 1
    say(string.format(L("TB_NAMEMENU_SHAREOK"), tostring(prof or "?"), tostring(name)))
  else
    say(L("TB_NAMEMENU_SHAREFAIL"))
  end
  return ok
end
-- 交易：需要 unit（本机只能解析「看得到」的单位）——解析不到就如实说明，不硬来
function EVAL_TB_NAME_TRADE(name)
  if type(InitiateTrade) ~= "function" then
    say(string.format(L("TB_NAMEMENU_TRADEFAIL"), "InitiateTrade"))
    return false
  end
  local u = tbUnitOf(name)
  if not u then
    say(string.format(L("TB_NAMEMENU_TRADEFAIL"), L("TB_NAMEMENU_NOUNIT")))
    return false
  end
  local ok = pcall(InitiateTrade, u)
  if ok then
    TB_NAME_MENU.trade = (TB_NAME_MENU.trade or 0) + 1
    say(string.format(L("TB_NAMEMENU_TRADEOK"), tostring(name)))
  else
    say(string.format(L("TB_NAMEMENU_TRADEFAIL"), "InitiateTrade"))
  end
  return ok
end
-- 查询（玩家信息）：能解析到 unit → 观察（NotifyInspect）；否则退回 /who 查询（本客户端没有 InspectUnit）
function EVAL_TB_NAME_QUERY(name)
  local u = tbUnitOf(name)
  if u and type(NotifyInspect) == "function" then
    local ok = pcall(NotifyInspect, u)
    if ok then
      TB_NAME_MENU.query = (TB_NAME_MENU.query or 0) + 1
      say(string.format(L("TB_NAMEMENU_QUERYOK"), tostring(name)))
      return true
    end
  end
  -- ★★★1.73.35 查询必须走**限频 who 队列**（源码检查 CHAT COLOR WIRING CHECK 当场抓到：直调 SendWho 是热路径，
  --   会被服务器反滥用）——工具箱里本来就有 EVAL_TB_WHO_ENQUEUE（带队列 + 负缓存 + 在途去重），直接用它。
  if type(EVAL_TB_WHO_ENQUEUE) == "function" then
    local ok = pcall(EVAL_TB_WHO_ENQUEUE, tostring(name))
    if ok then
      TB_NAME_MENU.query = (TB_NAME_MENU.query or 0) + 1
      say(string.format(L("TB_NAMEMENU_QUERYWHO"), tostring(name)))
      return true
    end
  end
  say(string.format(L("TB_NAMEMENU_QUERYFAIL"), tostring(name)))
  return false
end
-- 踢出队伍：只有队长能踢（条目本身只在「在队伍里」时出现）
-- ★1.73.42v 队伍人数读值口（取消邀请/踢人两条都要「操作前后对比」如实播报）
local function tbPartyCount()
  if type(GetNumPartyMembers) ~= "function" then return nil end
  local ok, n = pcall(GetNumPartyMembers)
  if not ok then return nil end
  return tonumber(n) or 0
end
-- ★★★1.73.42v 取消邀请（用户：「添加取消邀请,在队伍内的情况下」）：
--   wiki：`UninviteByName(Name)`「Removes a party or raid member by character name. **Sends the given name to the server**.
--   **Does not look the name up locally first**.」⇒ 名字直接交给服务器：对方**还没接受** → 服务器**取消邀请**；
--   已在队伍 → **移出队伍**。同一个接口两种结果 ⇒ 用「操作前后队伍人数」如实区分两种措辞（不假称）。
function EVAL_TB_NAME_CANCELINVITE(name)
  if type(name) ~= "string" or name == "" then return false end
  if type(UninviteByName) ~= "function" then
    say(string.format(L("TB_NAMEMENU_CANCELFAIL"), "UninviteByName"))
    return false
  end
  if type(IsPartyLeader) == "function" then -- 只有队长能取消/移出（单人也返回 false → 但那正是「不在队伍」的情况）
    local okL, lead = pcall(IsPartyLeader)
    if okL and lead == false then
      say(string.format(L("TB_NAMEMENU_CANCELFAIL"), L("TB_NAMEMENU_NOLEAD")))
      return false
    end
  end
  if not tbMenuThrottle("cancel", 0.5) then return false end -- 服务器写动作：0.5 秒一次
  local safe = tbSafeName(name)
  local before = tbPartyCount()
  local ok = pcall(UninviteByName, safe)
  local after = tbPartyCount()
  if ok and before ~= nil and after ~= nil and after < before then
    TB_NAME_MENU.cancelKicked = (TB_NAME_MENU.cancelKicked or 0) + 1
    say(string.format(L("TB_NAMEMENU_CANCELKICKED"), safe))
    return true
  end
  if ok then
    TB_NAME_MENU.cancelSent = (TB_NAME_MENU.cancelSent or 0) + 1
    say(string.format(L("TB_NAMEMENU_CANCELSENT"), safe))
    return true
  end
  TB_NAME_MENU.cancelFail = (TB_NAME_MENU.cancelFail or 0) + 1
  say(string.format(L("TB_NAMEMENU_CANCELFAIL"), "UninviteByName"))
  return false
end
-- ★★★1.74.2 用户：「添加离开队伍」—— 我离开当前队伍（与右键的人无关；`LeaveParty` 官方 Group 接口已核存在）。
--   ★不是队长也能自己退（退队不需要权限）⇒ 只闸「我在队伍里」；`LeaveParty` 与 UninviteByName 同属组管理、可直接调（同 UninviteByName 的写法）。
function EVAL_TB_NAME_LEAVEP(name)
  if type(LeaveParty) ~= "function" then
    say(string.format(L("TB_NAMEMENU_LEAVEPFAIL"), "LeaveParty"))
    return false
  end
  if type(GetNumPartyMembers) == "function" then
    local ok, n = pcall(GetNumPartyMembers)
    if ok and (tonumber(n) or 0) <= 0 then say(L("TB_NAMEMENU_LEAVEPNOTIN")) return false end
  end
  if not tbMenuThrottle("leave", 0.5) then return false end -- 服务器写动作：0.5 秒一次
  pcall(LeaveParty)
  say(L("TB_NAMEMENU_LEAVEPOK"))
  return true
end
function EVAL_TB_NAME_KICKP(name)
  if type(UninviteByName) ~= "function" then
    say(string.format(L("TB_NAMEMENU_KICKPFAIL"), "UninviteByName"))
    return false
  end
  if type(IsPartyLeader) == "function" then
    local okL, lead = pcall(IsPartyLeader)
    if okL and lead == false then
      say(string.format(L("TB_NAMEMENU_KICKPFAIL"), L("TB_NAMEMENU_NOLEAD")))
      return false
    end
  end
  -- ★1.73.42v 同样**按前后人数对比**如实播报（pcall 成功 ≠ 服务器真的把人移走了）
  local safeK = tbSafeName(name)
  local beforeK = tbPartyCount()
  local ok = pcall(UninviteByName, safeK)
  local afterK = tbPartyCount()
  if ok and beforeK ~= nil and afterK ~= nil and afterK >= beforeK then
    TB_NAME_MENU.kickpUnk = (TB_NAME_MENU.kickpUnk or 0) + 1
    say(string.format(L("TB_NAMEMENU_KICKPUNK"), safeK))
    return true
  end
  if ok then
    TB_NAME_MENU.kickp = (TB_NAME_MENU.kickp or 0) + 1
    say(string.format(L("TB_NAMEMENU_KICKPOK"), tostring(name)))
  else
    say(string.format(L("TB_NAMEMENU_KICKPFAIL"), "UninviteByName"))
  end
  return ok
end
-- 踢出公会：需要会长/官员权限（条目本身只在 CanGuildRemove() 为真时出现）
function EVAL_TB_NAME_KICKG(name)
  if type(GuildUninviteByName) ~= "function" then
    say(string.format(L("TB_NAMEMENU_KICKGFAIL"), "GuildUninviteByName"))
    return false
  end
  local ok = pcall(GuildUninviteByName, tostring(name))
  if ok then
    TB_NAME_MENU.kickg = (TB_NAME_MENU.kickg or 0) + 1
    say(string.format(L("TB_NAMEMENU_KICKGOK"), tostring(name)))
  else
    say(string.format(L("TB_NAMEMENU_KICKGFAIL"), "GuildUninviteByName"))
  end
  return ok
end

function EVAL_TB_SIR_HANDLE(link, button)
  if type(link) ~= "string" then return false end
  -- ★1.74.24 稀有提醒转播的名字链接（EHRW:<名字>）：点它 = **选中那只稀有**（分派在 EVAL_RW_LINK_CLICK，
  --   里面就是一次 TargetByName；选不中由它自己如实报错）。★1.74.26 起链接只带名字、不带坐标。
  --   ★无论哪个键都**吃掉**（return true）：绝不把自家 token 丢给客户端的物品处理函数。
  if string.find(link, "^EHRW:") then
    if type(EVAL_RW_LINK_CLICK) == "function" then pcall(EVAL_RW_LINK_CLICK, link, button) end
    return true
  end
  -- ★★★1.73.46 分享封皮链接：点它 = **弹出「方案分享」窗让玩家自己确认**（用户：「不要自动导入」）；
  --   只认 EHPF: 前缀，其余原样放行。★旧行为是直接导入 —— 一个没有确认的写操作，已按用户要求改掉。
  if string.find(tostring(link or ""), "^EHPF:") then
    if type(EVAL_SHARE_CLICK_OPEN) == "function" then pcall(EVAL_SHARE_CLICK_OPEN, link) end
    return true
  end
  local name = string.match(link, "^player:(.+)$")
  if not name or name == "" then return false end
  if button ~= "RightButton" then return false end
  return EVAL_TB_MENU_SHOW(name)
end
-- ★1.73.42g 测试钩子：走**真实**已安装的 SetItemRef 点一个链接（不直调分支函数）
function EVAL_TEST_SIR_CLICK(link)
  local f = _G.SetItemRef
  if type(f) ~= "function" then return false end
  local ok = pcall(f, tostring(link or ""), "[链接]", "LeftButton")
  return ok and true or false
end

function EVAL_TB_SETITEMREF_INSTALL()
  local cur = _G.SetItemRef
  if type(cur) ~= "function" then return false end
  if TB.sirWrapper and cur == TB.sirWrapper then return true end -- 幂等
  local orig = cur
  local function wrapper(link, text, button)
    TB.sirSeen = (TB.sirSeen or 0) + 1
    local ok, handled = pcall(EVAL_TB_SIR_HANDLE, link, button)
    if ok and handled then
      TB.sirHandled = (TB.sirHandled or 0) + 1
      return
    end
    return orig(link, text, button)
  end
  local okw = pcall(function() _G.SetItemRef = wrapper end)
  if not okw then return false end
  -- ★★写完**读回来确认**（1.73.12 的教训：本客户端吞过 AddMessage 的写；SetItemRef 是普通全局，写进去一定生效）
  if _G.SetItemRef ~= wrapper then return false end
  TB.sirWrapper, TB.sirOrig = wrapper, orig
  return true
end
function EVAL_TB_NAMEMENU_RETRY()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB.sirTryAt or -99) < 1 then return false end
  TB.sirTryAt = now
  local ok = EVAL_TB_SETITEMREF_INSTALL()
  if ok and not TB.sirLogged then
    TB.sirLogged = true
    EVAL_LOGLINE("[名字菜单] SetItemRef 挂载成功并**读回确认**（右键 player: 链接弹菜单）")
  end
  return ok
end
function EVAL_TB_NAMEMENU_STATE()
  return {
    exists = (type(_G.SetItemRef) == "function"),
    live = (TB.sirWrapper ~= nil and _G.SetItemRef == TB.sirWrapper) and true or false,
    seen = TB.sirSeen or 0, handled = TB.sirHandled or 0,
    shown = TB_NAME_MENU.shown and true or false, name = TB_NAME_MENU.name,
    inviteDirect = TB_NAME_MENU.inviteDirect or 0, inviteScript = TB_NAME_MENU.inviteScript or 0,
    -- ★1.73.28 五个动作各自的战果（诊断与断言都读这里，不在别处复刻）
    party = TB_NAME_MENU.party or 0, target = TB_NAME_MENU.target or 0,
    whisper = TB_NAME_MENU.whisper or 0, said = TB_NAME_MENU.said or 0,
    throttled = TB_NAME_MENU.throttled or 0,
    -- ★1.73.42s 邀请的三条路分开记（不是队长拒发 / 只排队未确认 / 直调失败）+ 最近走的接口
    partyVia = TB_NAME_MENU.partyVia, partyNotLeader = TB_NAME_MENU.partyNotLeader or 0,
    partyScript = TB_NAME_MENU.partyScript or 0, partyFail = TB_NAME_MENU.partyFail or 0,
    partySelf = TB_NAME_MENU.partySelf or 0,
    -- ★1.73.42u 好友四态（加成功 / 加请求已发但确认不了 / 已是好友 / 删成功）+ 失败
    friendAdd = TB_NAME_MENU.friendAdd or 0, friendAddUnk = TB_NAME_MENU.friendAddUnk or 0,
    friendAlready = TB_NAME_MENU.friendAlready or 0, friendRemove = TB_NAME_MENU.friendRemove or 0,
    friendFail = TB_NAME_MENU.friendFail or 0, friendRemoveUnk = TB_NAME_MENU.friendRemoveUnk or 0,
    pendingFriend = TB_NAME_MENU.pendingFriend,
    -- ★1.73.42v 取消邀请三态（真的移出 / 请求已发 / 失败）+ 踢出未确认
    cancelKicked = TB_NAME_MENU.cancelKicked or 0, cancelSent = TB_NAME_MENU.cancelSent or 0,
    kickp = TB_NAME_MENU.kickp or 0,
    cancelFail = TB_NAME_MENU.cancelFail or 0, kickpUnk = TB_NAME_MENU.kickpUnk or 0,
  }
end
-- ★★★1.73.42s 取证命令（用户：「右键邀请触发」= 点了没反应）：**能力 + 记账**一次打出来，一条命令定位
--   为什么需要它：本客户端的 API 表里 InviteToParty / InviteByName / IsPartyLeader / GetNumPartyMembers **都有** ⇒
--   「点了没反应」不可能是「接口不存在」，只可能是 ①不是队长被服务器静默忽略 ②名字不对/对方离线 ③只排了队没真发。
--   这三条**在客户端里都看不到结果**，只能靠「我们到底调了什么 + 走的是哪条路」的记账来判。
function EVAL_TB_NAME_PROBE()
  local cap = {
    InviteToParty = (type(InviteToParty) == "function"),
    InviteByName = (type(InviteByName) == "function"),
    IsPartyLeader = (type(IsPartyLeader) == "function"),
    GetNumPartyMembers = (type(GetNumPartyMembers) == "function"),
    GuildInviteByName = (type(GuildInviteByName) == "function"),
    CanGuildInvite = (type(CanGuildInvite) == "function"),
    TargetByName = (type(TargetByName) == "function"),
    AddFriend = (type(AddFriend) == "function"),
    RemoveFriend = (type(RemoveFriend) == "function"),
    GetNumFriends = (type(GetNumFriends) == "function"),
    GetFriendInfo = (type(GetFriendInfo) == "function"),
  }
  local lead, pnum, canGi, fnum = nil, nil, nil, nil
  if cap.GetNumFriends then local okf, v = pcall(GetNumFriends) if okf then fnum = tonumber(v) or 0 end end
  if cap.IsPartyLeader then local okl, v = pcall(IsPartyLeader) if okl then lead = v and true or false end end
  if cap.GetNumPartyMembers then local okn, v = pcall(GetNumPartyMembers) if okn then pnum = tonumber(v) or 0 end end
  if cap.CanGuildInvite then local okc, v = pcall(CanGuildInvite) if okc then canGi = v and true or false end end
  local m = TB_NAME_MENU
  say("===== 右键名字菜单 · 取证 =====")
  say("  邀请接口：InviteToParty=" .. (cap.InviteToParty and "有" or "无") ..
      " · InviteByName=" .. (cap.InviteByName and "有" or "无") ..
      " · 目标=" .. (cap.TargetByName and "有" or "无"))
  say("  队长身份：IsPartyLeader=" .. (cap.IsPartyLeader and "有" or "无") ..
      " · 队伍人数=" .. tostring(pnum) .. " · 我是队长=" .. tostring(lead))
  say("  公会：GuildInviteByName=" .. (cap.GuildInviteByName and "有" or "无") ..
      " · CanGuildInvite=" .. (cap.CanGuildInvite and "有" or "无") .. "（值=" .. tostring(canGi) .. "）")
  say("  邀请记账：直调成功 " .. tostring(m.party or 0) .. "（最近走 " .. tostring(m.partyVia or "—") .. "）" ..
      " · 不是队长拒发 " .. tostring(m.partyNotLeader or 0) ..
      " · 只排队未确认 " .. tostring(m.partyScript or 0) ..
      " · 直调失败 " .. tostring(m.partyFail or 0) ..
      " · 限频拦下 " .. tostring(m.throttled or 0))
  say("  好友接口：AddFriend=" .. (cap.AddFriend and "有" or "无") .. " · RemoveFriend=" .. (cap.RemoveFriend and "有" or "无") ..
      " · 好友数=" .. tostring(fnum))
  say("  好友记账：加成功 " .. tostring(m.friendAdd or 0) .. " · 加请求已发未确认 " .. tostring(m.friendAddUnk or 0) ..
      " · 已是好友 " .. tostring(m.friendAlready or 0) .. " · 删成功 " .. tostring(m.friendRemove or 0) ..
      " · 失败 " .. tostring(m.friendFail or 0))
  say("  取消邀请/踢人：真移出 " .. tostring(m.cancelKicked or 0) .. " · 请求已发 " .. tostring(m.cancelSent or 0) ..
      " · 取消失败 " .. tostring(m.cancelFail or 0) .. " · 踢出未确认 " .. tostring(m.kickpUnk or 0) ..
      " · 踢出成功 " .. tostring(m.kickp or 0))
  say("  公会邀请记账：直调 " .. tostring(m.inviteDirect or 0) .. " · 排队 " .. tostring(m.inviteScript or 0) ..
      " · 目标 " .. tostring(m.target or 0) .. " · 密语 " .. tostring(m.whisper or 0))
  local snap = { at = (type(GetTime) == "function") and GetTime() or 0, cap = cap, lead = lead, partyN = pnum, canGuildInvite = canGi,
                 party = m.party or 0, partyVia = m.partyVia, partyNotLeader = m.partyNotLeader or 0,
                 partyScript = m.partyScript or 0, partyFail = m.partyFail or 0, throttled = m.throttled or 0,
                 inviteDirect = m.inviteDirect or 0, inviteScript = m.inviteScript or 0,
                 -- ★1.73.42u/v 好友与取消邀请的记账也一起落盘（命令接线的证人表里要有它们）
                 friendAdd = m.friendAdd or 0, friendAddUnk = m.friendAddUnk or 0,
                 friendAlready = m.friendAlready or 0, friendRemove = m.friendRemove or 0,
                 friendFail = m.friendFail or 0,
                 cancelKicked = m.cancelKicked or 0, cancelSent = m.cancelSent or 0,
                 cancelFail = m.cancelFail or 0, kickp = m.kickp or 0, kickpUnk = m.kickpUnk or 0 }
  local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgP) == "table" then cfgP.tbNameProbe = snap end -- ★命令接线的**落盘证人**（M336：不玩聊天含子串）
  return snap
end
function EVAL_TEST_TB_NAMEMENU_RESET()
  TB.sirSeen, TB.sirHandled = 0, 0
  TB_NAME_MENU.shown, TB_NAME_MENU.name = false, nil
  TB_NAME_MENU.inviteDirect, TB_NAME_MENU.inviteScript = 0, 0
  TB_NAME_MENU.party, TB_NAME_MENU.target, TB_NAME_MENU.whisper = 0, 0, 0
  TB_NAME_MENU.said, TB_NAME_MENU.throttled = 0, 0
  -- ★1.73.42s 本轮新增的记账也要清（不是队长拒发 / 只排队未确认 / 直调失败 / 最近走的接口）
  TB_NAME_MENU.partyNotLeader, TB_NAME_MENU.partyScript, TB_NAME_MENU.partyFail = 0, 0, 0
  TB_NAME_MENU.partySelf = 0
  TB_NAME_MENU.friendAdd, TB_NAME_MENU.friendAddUnk, TB_NAME_MENU.friendAlready = 0, 0, 0
  TB_NAME_MENU.friendRemove, TB_NAME_MENU.friendFail = 0, 0
  TB_NAME_MENU.friendRemoveUnk, TB_NAME_MENU.pendingFriend = 0, nil
  TB_NAME_MENU.cancelKicked, TB_NAME_MENU.cancelSent, TB_NAME_MENU.cancelFail = 0, 0, 0
  TB_NAME_MENU.kickp, TB_NAME_MENU.kickpUnk = 0, 0
  TB_NAME_MENU.partyVia = nil
  TB_MENU_AT = {}
  EVAL_TB_MENU_HIDE()
end
TB.sirHooked = EVAL_TB_SETITEMREF_INSTALL() and true or false
EVAL_LOGLINE("[名字菜单] SetItemRef 载入时挂载：" ..
  (TB.sirHooked and "成功" or "还没就绪（将由事件/限频重试挂上）"))

-- ===== 角色名职业着色（1.73.10 用户要求：工具箱 → 队伍/社交）=====
-- 需求出处 = tmp/XGuild（1.2，275 行）——按本项目规范**轻量化重写**。XGuild 的三个毛病都已在下面规避：
--   1. 公会/查询/好友三段几乎逐字重复（同一套 getglobal+SetTextColor 抄三遍）；
--   2. 原函数备份存**全局**（oldGuildStatus_Update 之类）→ 污染命名空间；
--   3. 依赖本客户端**不存在**的 GetDifficultyColor（本机 api_*.html 全表 **0 命中**；只有 Core.lua 的垫片提供它）。
-- 本实现 = **一张描述表 + 一个通用上色流程 + 三个纯函数**：
--   · 三窗口差异（按钮前缀 / 行数常量 / 翻页框 / 列后缀）全进 TB_PAINT_LISTS —— 加窗口只加一行；
--   · 颜色决策（职业色 / 等级难度色 / 同地图绿 / 离线减半 / 阶级插值）是**纯函数**，能脱离游戏断言；
--   · 包装全局刷新函数时**先调原函数**（客户端自己的配色先落地）再叠色，带**幂等守卫**（绝不重复包装）；
--   · 每一处 _G 取值与 SetTextColor 都走 pcall：客户端没那个窗口/控件 → **整窗口跳过并如实记账**；
--   · 开关关掉 = **不再叠色**（原函数会把颜色刷回客户端原本的配色），不是「停止刷新」。
local TB_PAINT_DEFAULT_COLOR = "ffa0a0a0"
-- 职业色**自建**（不读 RAID_CLASS_COLORS）：ChatMOD 原作者在注释里写明「本客户端它有时不按预期工作」；
--   自建表还能让判据落在「颜色对不对」上，而不是「有没有调用某个 API」。
local TB_PAINT_CLASS_COLOR = {
  WARRIOR = "ffc79c6e", PALADIN = "fff58cba", HUNTER = "ffabd473", ROGUE = "fffff569",
  PRIEST = "ffffffff", SHAMAN = "ff0070de", MAGE = "ff69ccf0", WARLOCK = "ff9482c9", DRUID = "ffff7d0a",
}
local function tbHexToRGB(h)
  local s = (type(h) == "string") and h or ""
  if string.len(s) == 8 then s = string.sub(s, 3) end -- aarrggbb → 取后 6 位
  if string.len(s) < 6 then return 1, 1, 1 end
  local r = tonumber(string.sub(s, 1, 2), 16) or 255
  local g = tonumber(string.sub(s, 3, 4), 16) or 255
  local b = tonumber(string.sub(s, 5, 6), 16) or 255
  return r / 255, g / 255, b / 255
end
-- 纯函数①：职业显示名（"战士" / "WARRIOR"）→ token（认不出来返回 nil，**不瞎猜**）
--   本地化名 → token 走 Engine 的 CLASS_LIST（EVAL_CLASS_LIST，单一来源；不在这里再抄一份职业名表）
function EVAL_TB_PAINT_CLASS_TOKEN_OF(name)
  if type(name) ~= "string" or name == "" then return nil end
  local up = string.upper(name)
  if TB_PAINT_CLASS_COLOR[up] then return up end
  local list = (type(EVAL_CLASS_LIST) == "table") and EVAL_CLASS_LIST or nil
  if list then
    for i = 1, table.getn(list) do
      local c = list[i]
      if type(c) == "table" and (c.id == up or c.name == name) then return c.id end
    end
  end
  return nil
end
-- 纯函数②：职业名 → 颜色串（认不出来如实退回默认灰）
function EVAL_TB_PAINT_CLASS_COLOR_OF(name)
  local tok = EVAL_TB_PAINT_CLASS_TOKEN_OF(name)
  return (tok and TB_PAINT_CLASS_COLOR[tok]) or TB_PAINT_DEFAULT_COLOR
end
-- ★★★1.73.18 名字**已缓存**时的职业色（聊天名字着色用；不在缓存里返回 **nil** —— 绝不返回默认灰：
--   「不知道职业」和「职业色是灰」是两件事，返回灰会把没见过的名字也涂灰）。
function EVAL_TB_PAINT_COLOR_OF(name)
  local tok = tbNameClassGet(name)
  if not tok then return nil end
  return TB_PAINT_CLASS_COLOR[tok]
end
-- 纯函数③：公会阶级色 = 红(最低)→黄(中)→绿(最高) 线性插值，返回 r,g,b
--   ★XGuild 原作此处有个 bug：它用「rankIndex 是否等于 nRanks/2」判中点，而 nRanks 为**奇数**时
--     那个分支永远不命中（Lua 的 / 是浮点）→ 这里改成**按比例**插值，任何档数都连续。
function EVAL_TB_PAINT_RANK_RGB(idx, n)
  local n2, i2 = tonumber(n) or 0, tonumber(idx) or 0
  if n2 < 2 then return 1, 1, 1 end
  local t = i2 / (n2 - 1)          -- 0（最低档）→ 1（最高档）
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  local RED = { 1.00, 0.10, 0.10 }
  local YEL = { 1.00, 0.82, 0.00 }
  local GRN = { 0.10, 1.00, 0.10 }
  local a, b, k
  if t <= 0.5 then a, b, k = RED, YEL, t / 0.5 else a, b, k = YEL, GRN, (t - 0.5) / 0.5 end
  return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- 三窗口描述表（**唯一的差异集中处**；新增窗口 = 加一行）
local TB_PAINT_LISTS = {
  { key = "guild", upd = "GuildStatus_Update", rows = "GUILDMEMBERS_TO_DISPLAY", scroll = "GuildListScrollFrame",
    btn = "GuildFrameButton", sbtn = "GuildFrameGuildStatusButton",
    cols = { name = "Name", klass = "Class", level = "Level", zone = "Zone" },
    scols = { name = "Name", rank = "Rank", note = "Note" } },
  { key = "who", upd = "WhoList_Update", rows = "WHOS_TO_DISPLAY", scroll = "WhoListScrollFrame",
    btn = "WhoFrameButton",
    cols = { name = "Name", klass = "Class", level = "Level", variable = "Variable" } },
  { key = "friends", upd = "FriendsList_Update", rows = "FRIENDS_TO_DISPLAY", scroll = "FriendsFrameFriendsScrollFrame",
    btn = "FriendsFrameFriendButton",
    cols = { name = "ButtonTextNameLocation", info = "ButtonTextInfo" } },
}

-- ★1.73.12 名字 → 职业 token 缓存（「聊天窗名字着色」的**唯一**数据来源）：
--   · 写入只有一个 helper（tbNameClassPut），读取只有一个（tbNameClassGet）—— 单一真值，不在别处再存一份；
--   · 键规范化：去首尾空白 + 小写；宠物名「主人-宠物」取主人（1.12 的角色名里不会有连字符）；
--   · 长度 < 2 的键**不写也不查**（单字名的误伤面太大）；
--   · 认不出职业的名字**不写**（不猜）—— 「拿不到就不猜」纪律。
-- （名字缓存已上移到文件顶部：聊天入口要用它，局部队变量必须先声明）

-- 开关：nil 视为**开**（用户要求加的，默认就生效；关掉 = 不叠色）
function EVAL_TB_COLOR_ON()
  local tb = tbCfg()
  if not tb then return true end
  return tb.colorClass ~= false
end

local function tbPaintFS(name, r, g, b)
  local fs = _G[name]
  if fs == nil then return false end
  local ok = pcall(function() fs:SetTextColor(r, g, b) end)
  return ok and true or false
end

-- 取一行数据（pcall；拿不到返回 nil → 该行不画）
local function tbPaintRowData(list, idx)
  if list.key == "guild" then
    local ok, name, rank, rankIndex, level, class, zone, note, officernote, online = pcall(GetGuildRosterInfo, idx)
    if not (ok and name ~= nil) then return nil end
    return { name = name, rank = rank, rankIndex = rankIndex, level = level, klass = class, zone = zone, online = online }
  elseif list.key == "who" then
    local ok, name, guild, level, race, class, zone = pcall(GetWhoInfo, idx)
    if not (ok and name ~= nil) then return nil end
    return { name = name, level = level, klass = class, zone = zone, online = true }
  else
    local ok, name, level, class, zone, online = pcall(GetFriendInfo, idx)
    if not (ok and name ~= nil) then return nil end
    return { name = name, level = level, klass = class, zone = zone, online = online }
  end
end

-- who 窗口第三列（Variable）当前是不是「区域」——本客户端 api 表里查不到 UIDropDownMenu_GetSelectedID，
--   ★查不到就**不猜**：拿不到排序维度时这一列不画（其余列照画）。
local function tbPaintWhoSortIsZone()
  if type(UIDropDownMenu_GetSelectedID) ~= "function" then return nil end
  local d = _G["WhoFrameDropDown"]
  if d == nil then return nil end
  local ok, id = pcall(UIDropDownMenu_GetSelectedID, d)
  if not ok or type(id) ~= "number" then return nil end
  return id == 1
end

-- 画一行；返回「真的画了几处」（0 = 这一行没画/控件不存在）
function EVAL_TB_PAINT_ROW(list, i, off, myZone)
  local idx = (tonumber(off) or 0) + i
  local d = tbPaintRowData(list, idx)
  if not d then return 0 end
  -- ★1.73.12 「白拿」的一笔：上色时手上已经有 名字 + 职业 → 顺手写进名字缓存（零额外 API 调用）。
  --   聊天窗名字着色的一半数据就从这里来（另一半是队伍/团队/自己/目标，见 EVAL_TB_NAMECLASS_HARVEST）。
  tbNameClassPut(d.name, d.klass)
  local mul = d.online and 1 or 0.5 -- ★离线整行减半（XGuild 的做法保留）
  local pfx = list.btn .. tostring(i)
  local cr, cg, cb = tbHexToRGB(EVAL_TB_PAINT_CLASS_COLOR_OF(d.klass))
  local n = 0
  local cols = list.cols or {}
  if cols.name and tbPaintFS(pfx .. cols.name, cr * mul, cg * mul, cb * mul) then n = n + 1 end
  if cols.klass and tbPaintFS(pfx .. cols.klass, cr * mul, cg * mul, cb * mul) then n = n + 1 end
  if cols.level then
    local lv = tonumber(d.level)
    if lv and type(GetDifficultyColor) == "function" then
      local okc, c = pcall(GetDifficultyColor, lv)
      if okc and type(c) == "table" then
        if tbPaintFS(pfx .. cols.level, (c.r or 1) * mul, (c.g or 1) * mul, (c.b or 1) * mul) then n = n + 1 end
      end
    end
  end
  -- 同地图：公会/好友直接看 Zone 列；who 要看当前排序维度（拿不到就跳过）
  if cols.zone and myZone and d.zone == myZone then
    if tbPaintFS(pfx .. cols.zone, 0, d.online and 1 or 0.5, 0) then n = n + 1 end
  elseif cols.variable and myZone and d.zone == myZone then
    -- ★只有**确知**当前排序维度是「区域」时才涂这一列（nil = 拿不到排序维度 → 不猜、不涂）
    if tbPaintWhoSortIsZone() == true then
      if tbPaintFS(pfx .. cols.variable, 0, 1, 0) then n = n + 1 end
    end
  end
  -- 好友行：在线名字用职业色（上面已画 ButtonTextNameLocation）、离线整体灰、同地图绿
  if cols.info then
    local ir, ig, ib = 1, 1, 1
    if not d.online then ir, ig, ib = 0.5, 0.5, 0.5
    elseif myZone and d.zone == myZone then ir, ig, ib = 0, 1, 0 end
    if tbPaintFS(pfx .. cols.info, ir, ig, ib) then n = n + 1 end
  end
  -- 公会：状态行的名字/阶级/备注
  local scols = list.scols
  if scols then
    local spfx = (list.sbtn or list.btn) .. tostring(i)
    if scols.name and tbPaintFS(spfx .. scols.name, cr * mul, cg * mul, cb * mul) then n = n + 1 end
    if scols.rank and d.rankIndex ~= nil then
      local nRanks = 0
      if type(GuildControlGetNumRanks) == "function" then
        local okn, v = pcall(GuildControlGetNumRanks)
        if okn and type(v) == "number" then nRanks = v end
      end
      local rr, gg, bb = EVAL_TB_PAINT_RANK_RGB(d.rankIndex, nRanks)
      if tbPaintFS(spfx .. scols.rank, rr * mul, gg * mul, bb * mul) then n = n + 1 end
    end
    if scols.note and tbPaintFS(spfx .. scols.note, 0.54 * mul, 0.54 * mul, 0.54 * mul) then n = n + 1 end
  end
  return n
end

-- 画一整张列表；返回 画了几处, 扫了几行（0,0 = 窗口/控件不存在或没数据）
function EVAL_TB_PAINT_LIST(list)
  local rowsN = _G[list.rows]
  if type(rowsN) ~= "number" or rowsN < 1 then return 0, 0 end
  local scroll = _G[list.scroll]
  if scroll == nil then return 0, 0 end
  local off = 0
  if type(FauxScrollFrame_GetOffset) == "function" then
    local ok, v = pcall(FauxScrollFrame_GetOffset, scroll)
    if ok and type(v) == "number" then off = v end
  end
  local myZone = nil
  if type(GetRealZoneText) == "function" then
    local okz, z = pcall(GetRealZoneText)
    if okz and type(z) == "string" and z ~= "" then myZone = z end
  end
  local painted, rows = 0, 0
  for i = 1, rowsN do
    rows = rows + 1
    local ok, c = pcall(EVAL_TB_PAINT_ROW, list, i, off, myZone)
    if ok and type(c) == "number" then painted = painted + c end
  end
  return painted, rows
end

-- 原函数备份存 **local**（XGuild 存全局 → 污染命名空间，与本项目 FRAME NAME CLASH 同一族隐患）
local tbPaintBackup, tbPaintWrapperMap = {}, {}

-- 包装一个窗口的刷新函数（幂等：已包装或当前入口就是我们的 wrapper → 直接返回 true）
function EVAL_TB_PAINT_INSTALL(list)
  local key = list.upd
  local cur = _G[key]
  if type(cur) ~= "function" then
    TB.paintMissing = TB.paintMissing or {}
    TB.paintMissing[key] = true
    return false
  end
  if tbPaintWrapperMap[key] and cur == tbPaintWrapperMap[key] then
    TB.paintInstalled = TB.paintInstalled or {}
    TB.paintInstalled[key] = true
    return true
  end
  local orig = tbPaintBackup[key] or cur
  tbPaintBackup[key] = orig
  local wrapper = function(...)
    TB.paintCalls = (TB.paintCalls or 0) + 1
    local okc = pcall(orig, ...) -- ★先调原函数：客户端自己的配色/文本先落地
    if EVAL_TB_COLOR_ON() then
      local okp, painted, rows = pcall(EVAL_TB_PAINT_LIST, list)
      if okp and type(painted) == "number" then
        TB.paintPainted = (TB.paintPainted or 0) + painted
        TB.paintRows = rows
      end
    end
    return okc
  end
  local okw = pcall(function() _G[key] = wrapper end)
  if not okw then return false end
  tbPaintWrapperMap[key] = wrapper
  TB.paintInstalled = TB.paintInstalled or {}
  TB.paintInstalled[key] = true
  return true
end

function EVAL_TB_PAINT_INSTALL_ALL()
  local ok = 0
  for i = 1, table.getn(TB_PAINT_LISTS) do
    if EVAL_TB_PAINT_INSTALL(TB_PAINT_LISTS[i]) then ok = ok + 1 end
  end
  return ok, table.getn(TB_PAINT_LISTS)
end

-- 立刻用当前开关状态重刷三个窗口（勾/取消勾时调一次：颜色立刻跟着变，不用等下次刷新）
function EVAL_TB_PAINT_REFRESH()
  local n = 0
  for i = 1, table.getn(TB_PAINT_LISTS) do
    local fn = tbPaintWrapperMap[TB_PAINT_LISTS[i].upd]
    if type(fn) == "function" then
      local ok = pcall(fn)
      if ok then n = n + 1 end
    end
  end
  return n
end

-- 限频重试（窗口是 FrameXML 懒加载的；载入那一刻可能还没建好）——与频道屏蔽同一套纪律
local function tbPaintRetry()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - (TB.paintTryAt or -99) < 1 then return false end
  TB.paintTryAt = now
  TB.paintTries = (TB.paintTries or 0) + 1
  local ok, total = EVAL_TB_PAINT_INSTALL_ALL()
  if ok >= total then
    if not TB.paintLogged then
      TB.paintLogged = true
      EVAL_LOGLINE("[职业着色] 挂载成功（" .. tostring(ok) .. "/" .. tostring(total) .. " 个窗口）")
    end
    return true
  end
  if TB.paintTries >= 60 then
    EVAL_LOGLINE("[职业着色] 挂载不完整：" .. tostring(ok) .. "/" .. tostring(total) ..
      "（窗口还没建好或本客户端没有该窗口；可用 /eh go 着色 看清单）")
  end
  return false
end
EVAL_TB_PAINT_RETRY = tbPaintRetry

-- 诊断/断言读值口：开关 / 已挂窗口 / 缺失窗口 / 累计调用与上色数
function EVAL_TB_PAINT_STATE()
  local ins, mis = {}, {}
  for k, v in pairs(TB.paintInstalled or {}) do if v then ins[k] = true end end
  for k, v in pairs(TB.paintMissing or {}) do if v then mis[k] = true end end
  local wired = false
  for _ in pairs(tbPaintWrapperMap) do wired = true end
  return { on = EVAL_TB_COLOR_ON(), installed = ins, missing = mis,
           calls = TB.paintCalls or 0, painted = TB.paintPainted or 0, rows = TB.paintRows or 0,
           tries = TB.paintTries or 0, wired = wired }
end
function EVAL_TB_PAINT_LISTS() return TB_PAINT_LISTS end
-- 勾/取消勾（走真实逻辑：写配置 + 立刻重刷，颜色立即跟着变）
function EVAL_TB_PAINT_CLICK()
  local tb = tbCfg()
  if not tb then return false end
  tb.colorClass = (tb.colorClass == false)
  EVAL_TB_PAINT_REFRESH()
  return tb.colorClass
end
function EVAL_TB_PAINT_RESET() -- 测试用：清计数（不还原已包装的入口）
  TB.paintCalls, TB.paintPainted, TB.paintRows = 0, 0, 0
  TB.paintTryAt, TB.paintTries = nil, 0
  TB.paintLogged = false
end

-- ===== 聊天窗名字职业着色（1.73.12 用户要求：「聊天窗 内的名字能着色吗?需要走缓存?」）=====
-- 参考 tmp/ChatMOD 的**机制**（同为 1.12 客户端）：它维护 name→class 缓存（来源 = 好友/公会/团队/队伍/目标/who 列表），
--   再在聊天打印入口里把名字染成职业色。我们**轻量化重写**（它的 1600 行只取这一小块），并遵守本项目纪律：
--   ① 缓存只有**一份真值**（tbNameClass；写入点唯一 = tbNameClassPut）：
--      · 来源①「白拿」：公会/查询/好友三个窗口上色时顺手记下（零额外 API 调用，见 EVAL_TB_PAINT_ROW）；
--      · 来源② 自己/队伍/团队/目标：UnitName + UnitClass（**事件驱动 + 限频**，见 tbNcHarvest）；
--      · 来源③ 客户端**本地已缓存**的公会名册 / 好友 / 查询结果（只读，**不发服务器查询**）。
--   ② ★**不做**自动 /who：SendWho 是**服务器写动作**，ChatMOD 靠手动开关 + 3 秒窗兜着；
--      我们这一版干脆不做 —— 查不到的名字就**不上色**（不猜、不打扰服务器）= 频率防护总则。
--   ③ 判据是**纯函数** EVAL_TB_CHAT_COLOR_LINE（只做字符串处理 + 查缓存，能脱游戏直接断言）；
--   ④ 只在**聊天打印入口**加一层（与频道屏蔽**共用同一个包装体**，见 EVAL_TB_CHAN_INSTALL_ONE）；
--   ⑤ 缓存**不落盘**（会话级）：避免 SavedVariables 膨胀与过期清理策略（ChatMOD 要 7 周清理正是因为落了盘）。

-- 开关：nil 视为**开**（与「角色名职业着色」同一套默认：装上就生效；取消勾选 = 不再染）
function EVAL_TB_CHATCOLOR_ON()
  local tb = tbCfg()
  if not tb then return true end
  return tb.chatColor ~= false
end

-- 采集一个单位（自己/队友/团员/目标）：UnitName + UnitClass 都是**只读**调用，不向服务器发请求
local function tbNameClassScanUnit(unit)
  if type(UnitName) ~= "function" or type(UnitClass) ~= "function" then return false end
  local okn, name = pcall(UnitName, unit)
  if not (okn and type(name) == "string" and name ~= "") then return false end
  local okc, a, b = pcall(UnitClass, unit)
  if not okc then return false end
  -- ★UnitClass 两个返回值哪个是「职业」在各客户端/各语言下不一致 → **两个都试**，都认不出就不写（不猜）
  if tbNameClassPut(name, a) then return true end
  return tbNameClassPut(name, b)
end

-- 采集（kind = unit / guild / friends / who；nil = 全部）；返回**本次新写入**条数
function EVAL_TB_NAMECLASS_HARVEST(kind)
  local before = EVAL_TB_NAMECLASS_SIZE()
  local all = (kind == nil)
  if all or kind == "unit" then
    tbNameClassScanUnit("player")
    for i = 1, 4 do tbNameClassScanUnit("party" .. i) end
    local rn = 0
    if type(GetNumRaidMembers) == "function" then
      local okr, n = pcall(GetNumRaidMembers)
      if okr and type(n) == "number" and n > 0 then rn = n end
    end
    for i = 1, rn do tbNameClassScanUnit("raid" .. i) end
    tbNameClassScanUnit("target")
  end
  if (all or kind == "guild") and type(GetNumGuildMembers) == "function" and type(GetGuildRosterInfo) == "function" then
    -- ★只读客户端**本地已缓存**的名册：**不调 GuildRoster()**（那是向服务器发查询 → 违反频率防护）
    local okg, n = pcall(GetNumGuildMembers)
    if okg and type(n) == "number" and n > 0 then
      for i = 1, n do
        local okp, nm, _rank, _ri, _lv, klass = pcall(GetGuildRosterInfo, i)
        if okp and type(nm) == "string" then tbNameClassPut(nm, klass) end
      end
    end
  end
  if (all or kind == "friends") and type(GetNumFriends) == "function" and type(GetFriendInfo) == "function" then
    local okf, n = pcall(GetNumFriends)
    if okf and type(n) == "number" then
      for i = 1, n do
        local okp, nm, _lv, klass = pcall(GetFriendInfo, i)
        if okp and type(nm) == "string" then tbNameClassPut(nm, klass) end
      end
    end
  end
  if (all or kind == "who") and type(GetNumWhoResults) == "function" and type(GetWhoInfo) == "function" then
    local okw, n = pcall(GetNumWhoResults)
    if okw and type(n) == "number" then
      for i = 1, n do
        local okp, nm, _g, _lv, _race, klass = pcall(GetWhoInfo, i)
        if okp and type(nm) == "string" then tbNameClassPut(nm, klass) end
      end
    end
  end
  return EVAL_TB_NAMECLASS_SIZE() - before
end

-- 限频采集（**事件驱动**，绝不进聊天热路径）：每类各自一个窗口，避免「一换目标就扫整张名册」
local TB_NC_THROTTLE = { unit = 5, guild = 30, friends = 10, who = 10 }
local tbNcAt = {}
local function tbNcHarvest(kind)
  local now = (type(GetTime) == "function") and GetTime() or 0
  -- ★1.73.51 兜底：kind 为 nil（= 采全部）时用 "all" 当限频键 —— 绝不拿 nil 做表键（那会当场 `table index is nil`）
  local kkey = kind or "all"
  if now - (tbNcAt[kkey] or -999) < (TB_NC_THROTTLE[kkey] or 10) then return 0 end
  tbNcAt[kkey] = now
  local ok, added = pcall(EVAL_TB_NAMECLASS_HARVEST, kind)
  if ok and type(added) == "number" and added > 0 then TB.ncAdded = (TB.ncAdded or 0) + added end
  return (ok and type(added) == "number") and added or 0
end
EVAL_TB_NAMECLASS_HARVEST_THROTTLED = tbNcHarvest -- 供事件 / 诊断 / 断言直调

-- ★★★1.73.51 未命中自愈：把三类**本地只读**来源按各自限频窗再采一遍（零服务器请求）。
--   为什么需要它：用户实测「打开一次公会信息才开始染色」= 公会名册是**懒加载**的；我们不能替他开公会窗，
--   但名册/好友/查询结果一旦到位，这里就能在下一次聊天命中失败时自己补上（配合聊天入口的「当场重判」）。
--   ★频率：单次最多 3 次 GetTime + 表查找（真正贵的遍历只在窗口到点时发生一次，见 TB_NC_THROTTLE），
--     所以从聊天热路径调用是安全的。返回本次**新写入**的条数。
-- ★★★1.73.52 用户真机取证（`/eh go 名字缓存`）：「公会名册 本地条数=0 · 查询=0 · 好友=0 · 缓存只有 2 条」——
--   所以刚载入时公会聊天里的人名**一条都染不上**：客户端要等**公会窗打开**才把名册拉到本地（懒加载）。
--   ⇒ 补一发**只发一次**的 `GuildRoster()`（向服务器要名册，与「主动查询」同一个开关、同一套纪律）：
--     · 只在「主动查询开着 + 在公会里 + 名册还没到位 + 本会话没问过」时才发；
--     · 结果由已有的 `GUILD_ROSTER_UPDATE` → `tbNcHarvest("guild")` 路径接（不另写一套采集）；
--     · 关掉「主动查询」开关 → 一个查询都不发（退回老行为：等玩家自己开公会窗）。
local function tbNameClassEnsureRoster()
  if TB.rosterAsked then return false end
  if not EVAL_TB_WHO_ON() then return false end
  if type(GuildRoster) ~= "function" then return false end
  if type(IsInGuild) == "function" then
    local okg, ing = pcall(IsInGuild)
    if okg and not ing then return false end
  end
  local n = 0
  if type(GetNumGuildMembers) == "function" then
    local okn, v = pcall(GetNumGuildMembers)
    if okn and type(v) == "number" then n = v end
  end
  if n > 0 then TB.rosterAsked = true return false end -- 本地已有名册：不用问
  TB.rosterAsked = true
  local ok2 = pcall(GuildRoster)
  if ok2 then TB.rosterSent = (TB.rosterSent or 0) + 1 end
  EVAL_LOGLINE("[名字缓存] 本地名册为空 → 已发一次名册查询（本会话仅此一次；由「主动查询」开关把关）")
  return ok2
end
function EVAL_TB_NAMECLASS_ENSURE_ROSTER() return tbNameClassEnsureRoster() end

function EVAL_TB_NAMECLASS_HEAL()
  if not EVAL_TB_CHATCOLOR_ON() then return 0 end
  local n = 0
  -- ★1.73.52 顺手补一次「名册查询」（内部自带：只发一次 / 开关把关 / 已有名册就不发）
  pcall(tbNameClassEnsureRoster)
  n = n + (tbNcHarvest("guild") or 0)
  n = n + (tbNcHarvest("friends") or 0)
  n = n + (tbNcHarvest("who") or 0)
  return n
end

-- 纯函数：把一行聊天文本里的**第一处**已知玩家名染成职业色；返回 (新文本, 命中的名字)。
--   ★判据（保守：宁可不上色，也不要把人家的聊天弄坏）：
--     ① 只认两种形态 —— 方括号名「[名字]」（1.12 组合行里的名字是带方括号的，ChatMOD 也按这个上色）
--        与行首「名字:」/「名字：」（说话人一定在最前面）；★形态**未经验证**的地方一律不猜，
--        靠 /eh go 聊天 打出来的原文样本校准（铁律 4：拿不准就取证，不靠推断）；
--     ② 方括号里含 | 号（物品链接/颜色码）→ 不碰；段前 11 字节内有 |c / |H（客户端已上过色）→ 不碰；
--     ③ 名字不足 2 个字符 → 不碰；缓存里查不到 → 不碰（**不猜**）；
--     ④ 只染第一处（后面重复提到的同一个名字不动，避免整行花掉）。
function EVAL_TB_CHAT_COLOR_LINE(msg)
  if type(msg) ~= "string" or msg == "" then return msg, nil end
  -- ★「已经在富文本里」= 前缀里**最后一个 |c / |H 还没被 |r / |h 闭合**（闭合了的不算）。
  --   ★为什么不看「往前 11 字节窗口」：物品链接 |cff..|Hitem:..|h[名字]|h|r 里，名字左边 11 字节内
  --     根本没有 |c/|H → 只看窗口会把**链接的显示名**也染色（本轮实测到的坑）。
  local function lastIndex(s, pat)
    local last, from = nil, 1
    while true do
      local i = string.find(s, pat, from, true)
      if not i then break end
      last, from = i, i + 1
    end
    return last
  end
  local function alreadyColored(pos)
    if pos <= 1 then return false end
    local pre = string.sub(msg, 1, pos - 1)
    local lc, lr = lastIndex(pre, "|c"), lastIndex(pre, "|r")
    if lc and (lr == nil or lc > lr) then return true end
    local lH, lh = lastIndex(pre, "|H"), lastIndex(pre, "|h")
    if lH and (lh == nil or lH > lh) then return true end
    return false
  end
  -- ★诊断用：本次**考虑过**的候选名（由判据自己记录 —— 绝不在别处再实现一遍判据；
  --   这就是本项目「读值口不许复刻逻辑」那条纪律的正解：让生产把自己的实际过程说出来）。
  --   ★只影响诊断输出、**不影响判据**：去掉方括号这层包装、去重、丢掉带括号的碎片（如「[4.」）。
  local cands, candSeen = {}, {}
  local function noteCandidate(name)
    if string.find(name, "[%[%]]") then return end
    local plain = string.gsub(name, "^%s*(.-)%s*$", "%1")
    if plain == "" or candSeen[plain] then return end
    candSeen[plain] = true
    table.insert(cands, plain)
  end
  local function paint(name, s, e)
    local tok = tbNameClassGet(name)
    if not tok then return nil end
    local hex = TB_PAINT_CLASS_COLOR[tok]
    if type(hex) ~= "string" or string.len(hex) ~= 8 then return nil end
    return string.sub(msg, 1, s - 1) .. "|c" .. hex .. string.sub(msg, s, e) .. "|r" ..
           string.sub(msg, e + 1)
  end
  -- ⓪ ★★★1.73.12（用户实测「全都没染色」后的定案方向）：客户端给的聊天行里，名字往往是
  --   **可点玩家链接**、并自带客户端自己的颜色码：
  --     |cRRGGBB|Hplayer:名字|h[名字]|h|r 悄悄地说: 1        （实测形态）
  --     |Hplayer:名字|h[名字]|h 说: 1                       （链接前面没有颜色码的情形）
  --   ★旧判据「已经在富文本里 → 整行放行」在这里会让**每一行都不上色**（这正是用户看到的现象）。
  --   正解 = **改那段颜色码**（同长度替换 → 位置不变、链接照样可点、其余原样）；
  --   没有颜色码时就把整个链接段**包进**职业色。
  local function paintLink(s, e, colS, colE)
    local cap = string.sub(msg, s, e)
    local nm = string.match(cap, "^|Hplayer:([^|]-)|h")
    local disp = string.match(cap, "%[([^%]]*)%]")
    local tok = nm and tbNameClassGet(nm) or nil
    if not tok and disp then tok = tbNameClassGet(disp) end
    if not tok then return nil end
    local hex = TB_PAINT_CLASS_COLOR[tok]
    if type(hex) ~= "string" or string.len(hex) ~= 8 then return nil end
    noteCandidate(nm or disp)
    local col = "|c" .. hex -- ★8 位（aarrggbb）：6 位客户端不解析，屏幕上会直接显示 |c 原文
    if colS then
      -- 把客户端那段颜色码整段换成职业色（其余原样；链接与 |r 都保留 → 照样可点、不会串色）
      return string.sub(msg, 1, colS - 1) .. col .. string.sub(msg, colE + 1, e) ..
             string.sub(msg, e + 1), (nm or disp)
    end
    return string.sub(msg, 1, s - 1) .. col .. cap .. "|r" .. string.sub(msg, e + 1), (nm or disp)
  end
  -- 带颜色的玩家链接（★颜色码长度不写死：本客户端给的是 |c + **8** 位 hex（aarrggbb），
  --   而 6 位 hex（rrggbb）也可能出现 → 用 |c%x+ 抓下来按实际长度替换）
  local cs, ce, colcap = string.find(msg, "(|c%x+)(|Hplayer:[^|]-|h.-|h)", 1)
  if cs then
    local out, who = paintLink(cs + string.len(colcap), ce, cs, cs + string.len(colcap) - 1)
    if out then return out, who, cands end
  end
  -- 不带颜色的玩家链接
  local ls, le = string.find(msg, "(|Hplayer:[^|]-|h.-|h)", 1)
  if ls then
    local out, who = paintLink(ls, le, nil)
    if out then return out, who, cands end
  end
  -- ① 候选起点 = 行首 + 每个「方括号段 / 颜色段之后」（覆盖「[频道] 名字:」与「|c..[频道]|r 名字:」两种前缀）
  local starts = { 1 }
  local from = 1
  while true do
    local s, e = string.find(msg, "[%]r]%s", from) -- ] 或 r 后面跟空白
    if not s then break end
    table.insert(starts, e + 1)
    from = e + 1
  end
  for i = 1, table.getn(starts) do
    local sp = starts[i]
    -- 名字 = 起点处**不含空白/冒号/竖线**的第一段（角色名里不会有这几种字符）
    local nm = string.match(string.sub(msg, sp), "^([^%s:：|]+)")
    if nm and tbNameCharLen(nm) >= 2 then
      noteCandidate(nm)
      if not alreadyColored(sp) then
        local out = paint(nm, sp, sp + string.len(nm) - 1)
        if out then return out, nm, cands end
      end
    end
  end
  -- ② 逐个方括号段（最多看 4 个：在前面的可能是频道名/公会名/队伍标记）
  local from2 = 1
  for _ = 1, 4 do
    local s, e = string.find(msg, "%[[^%[%]]*%]", from2)
    if not s then break end
    local inner = string.sub(msg, s + 1, e - 1)
    if string.find(inner, "|", 1, true) == nil then
      noteCandidate(inner)
      if not alreadyColored(s) then
        local out = paint(inner, s, e)
        if out then return out, inner, cands end
      end
    end
    from2 = e + 1
  end
  return msg, nil, cands
end

-- ★1.73.12 取证读值口：**每个聊天窗入口现在到底是不是我们挂的那一层** + 其它候选入口是否存在。
--   ★为什么必须有：用户报「全都没染色」，而「我们的包装被客户端顶掉」与「客户端不走 Lua 打印」
--     是两种**现象相同、修法完全不同**的原因（1.71.3 频道屏蔽就吃过这个亏）→ 必须能分开看。
function EVAL_TB_CHATCOLOR_ROUTES()
  local keys = tbChatFrameKeys()
  local rows, ours, live, sameAsDefault = {}, 0, 0, 0
  for i = 1, table.getn(keys) do
    local k = keys[i]
    local f = _G[k]
    local cur = nil
    if f ~= nil then
      local okr, v = pcall(function() return f.AddMessage end)
      if okr then cur = v end
    end
    local isOurs = (cur ~= nil and TB.chanWrappers ~= nil and cur == TB.chanWrappers[k]) and true or false
    if f ~= nil then live = live + 1 end
    if isOurs then ours = ours + 1 end
    if f ~= nil and f == DEFAULT_CHAT_FRAME then sameAsDefault = sameAsDefault + 1 end
    rows[k] = { exists = (f ~= nil), hasAddMessage = (type(cur) == "function"), ours = isOurs }
  end
  -- 其它可能的入口（有就说明还能换个地方挂；没有就说明客户端不走这条路）
  local others = {
    "ChatFrame_OnEvent", "ChatFrame_MessageEventHandler", "ChatFrame_AddMessage",
    "AddMessage", "SetItemRef", "ChatFrame_OnUpdate",
  }
  local found = {}
  for i = 1, table.getn(others) do
    if type(_G[others[i]]) == "function" then table.insert(found, others[i]) end
  end
  return rows, ours, live, sameAsDefault, found
end

-- 诊断读值口（/eh go 聊天 与断言共用）
function EVAL_TB_CHATCOLOR_STATE()
  return { on = EVAL_TB_CHATCOLOR_ON(), cache = EVAL_TB_NAMECLASS_SIZE(), seen = TB.chatSeen or 0,
           painted = TB.chatPainted or 0, last = TB.chatLast, samples = TB.chatRaw or {},
           frames = TB.chanFrames or 0, miss = TB.chanMiss or 0, added = TB.ncAdded or 0,
           healed = TB.chatHealed or 0 }
end
-- ★★★1.73.51 取证命令 `/eh go 名字缓存`：把「名字→职业」缓存的**每个来源**一次摊开。
--   为什么要有它：用户真机现象「刚载入不染色 · 查询完成还是不染色 · **打开一次公会信息**才开始」——
--   这三种表现对应三个完全不同的原因（来源没数据 / 职业名认不出来 / 聊天入口没挂上），
--   而它们只能靠**当场读各来源的条数与职业原文**分辨（本项目「写成功 ≠ 写进去生效」那一族）。
function EVAL_TB_NAMECLASS_PROBE()
  local function apiOk(n) return (type(_G[n]) == "function") and "有" or "**无**" end
  local function countOf(n)
    if type(_G[n]) ~= "function" then return "API无" end
    local ok, v = pcall(_G[n])
    return (ok and type(v) == "number") and tostring(v) or "报错/nil"
  end
  local function tokOf(k) return tostring(EVAL_TB_PAINT_CLASS_TOKEN_OF(k)) end
  say("===== 名字染色缓存探针 =====")
  say("  开关(chatColor)=" .. tostring(EVAL_TB_CHATCOLOR_ON()) .. " · 缓存条数=" .. tostring(EVAL_TB_NAMECLASS_SIZE()) ..
      " · 本会话采集新增=" .. tostring(TB.ncAdded or 0) .. " · 未命中自愈上色=" .. tostring(TB.chatHealed or 0))
  say("  公会名册: GetNumGuildMembers=" .. apiOk("GetNumGuildMembers") .. " · GetGuildRosterInfo=" .. apiOk("GetGuildRosterInfo") ..
      " · 本地条数=" .. countOf("GetNumGuildMembers") .. "（★懒加载：没开过公会窗前通常是 0）")
  if type(GetGuildRosterInfo) == "function" and type(GetNumGuildMembers) == "function" then
    local okn, n = pcall(GetNumGuildMembers)
    if okn and type(n) == "number" and n > 0 then
      local okp, nm, _r, _ri, _lv, klass = pcall(GetGuildRosterInfo, 1)
      say("    首条: " .. tostring(nm) .. " · 职业原文=" .. tostring(klass) .. " → token=" .. tokOf(klass))
    end
  end
  say("  查询结果: GetNumWhoResults=" .. apiOk("GetNumWhoResults") .. " · GetWhoInfo=" .. apiOk("GetWhoInfo") ..
      " · 条数=" .. countOf("GetNumWhoResults"))
  if type(GetWhoInfo) == "function" and type(GetNumWhoResults) == "function" then
    local okn, n = pcall(GetNumWhoResults)
    if okn and type(n) == "number" and n > 0 then
      local okp, nm, _g, _lv, _race, klass = pcall(GetWhoInfo, 1)
      say("    首条: " .. tostring(nm) .. " · 职业原文=" .. tostring(klass) .. " → token=" .. tokOf(klass))
    end
  end
  say("  好友: GetNumFriends=" .. apiOk("GetNumFriends") .. " · GetFriendInfo=" .. apiOk("GetFriendInfo") .. " · 条数=" .. countOf("GetNumFriends"))
  if type(GetFriendInfo) == "function" and type(GetNumFriends) == "function" then
    local okn, n = pcall(GetNumFriends)
    if okn and type(n) == "number" and n > 0 then
      local okp, nm, _lv, klass = pcall(GetFriendInfo, 1)
      say("    首条: " .. tostring(nm) .. " · 职业原文=" .. tostring(klass) .. " → token=" .. tokOf(klass))
    end
  end
  local added = EVAL_TB_NAMECLASS_HARVEST(nil)
  say("  立刻做一次**全量只读采集** → 新增 " .. tostring(added) .. " 条；缓存现在 " .. tostring(EVAL_TB_NAMECLASS_SIZE()) .. " 条")
  local st = EVAL_TB_CHATCOLOR_STATE() or {}
  say("  入口①AddMessage 层（本客户端**写入会被吞**，1.73.12 实测）: 已包装帧=" .. tostring(st.frames) ..
      " · 经过 " .. tostring(st.seen) .. " 条 · 上色 " .. tostring(st.painted) .. " · 最近上色=" .. tostring(st.last))
  -- ★★★诊断纪律：**逐个入口分开计数**（上面那层是死的、下面这层才是真身 —— 只看上面会误判成「入口全断」）
  local ce = (type(EVAL_TB_CHATEVENT_STATE) == "function") and EVAL_TB_CHATEVENT_STATE() or {}
  say("  入口②ChatFrame_OnEvent 层（**真身**）: 存在=" .. tostring(ce.exists) .. " · 是我们的=" .. tostring(ce.live) ..
      " · 经过=" .. tostring(ce.seen) .. " · 吞掉(频道通知)=" .. tostring(ce.filtered))
  say("    认出名字=" .. tostring(ce.named) .. " · 认不出=" .. tostring(ce.nameMiss) ..
      " · 认出但暂不回写(名字槽不吃富文本)=" .. tostring(ce.held) .. " · 自己拼整行=" .. tostring(ce.replaced))
  say("  名册查询: 本会话已发 GuildRoster 调用=" .. tostring(TB.rosterSent or 0) .. " 次（主动查询开关=" .. tostring(EVAL_TB_WHO_ON()) ..
      "；关掉它 = 一个查询都不发，退回「等你自己开公会窗」）")
  local ps = EVAL_TB_PAINT_STATE() or {}
  say("  三个窗口(公会/查询/好友): calls=" .. tostring(ps.calls) .. " · painted=" .. tostring(ps.painted) ..
      "（窗口没打开过就是 0 —— 那也是「缓存为空」的一个来源）")
  say("  ★判读：某来源「本地条数=0」= 客户端还没拉到数据（懒加载）；「职业原文=xx → token=nil」= 职业名认不出（要补映射）；")
  say("     缓存条数 >0 却仍不染色 → 看「聊天入口」那行（已包装帧=0 = 入口没挂上）")
  return true
end
-- 诊断用：对一条原文给出判决（不打印，只回值）—— 与生产**同一个**纯函数，绝不复刻判据
function EVAL_TB_CHATCOLOR_VOTE(msg)
  if type(EVAL_TB_CHAT_COLOR_LINE) ~= "function" then return false, nil end
  local ok, out, who, cands = pcall(EVAL_TB_CHAT_COLOR_LINE, msg)
  if not ok then return false, nil end
  -- 第三个返回值 = 判据**自己**记下的候选名（诊断靠它说明「为什么没认出来」，而不是另写一套判据）
  return (type(out) == "string" and out ~= msg) and true or false, who, cands
end
function EVAL_TB_CHATCOLOR_RESET() -- 测试用：清计数与样本（不还原入口、**不清**名字缓存）
  TB.chatSeen, TB.chatPainted, TB.chatRaw, TB.chatLast = 0, 0, {}, nil
  tbNcAt = {}
  TB.ncAdded = 0
  TB.chatHealed = 0
  TB.rosterAsked, TB.rosterSent = nil, 0 -- ★1.73.52 名册查询的「本会话只发一次」标记也一起清（测试用例要能各自独立）
end
-- 勾/取消勾后的即时动作：立刻补一次缓存（勾上就能用）+ 如实回一句，并把**自己的名字**染出来当示例
-- ===== 未缓存角色的**主动查询**（/who）—— 1.73.12 用户追加要求 =====
-- 用户原话：「未缓存角色默认开启主动查询进缓存,设定个查询频率限制,做好查询不到结果的做好防止重复查询的机制.
--   将关闭查询的开关在工具箱内设置,输出查询日志.归入调试日志」
-- ★这是对先前「不做自动 /who」的**用户明确推翻**（原决定是「查不到就不上色，不打扰服务器」）→ 现在做，
--   但按本项目《频率防护总则》**四道闸门一起上**（缺一道就是被踢线/刷屏/白刷服务器）：
--   ① **频率下限**：每 TB_WHO_GAP 秒**最多一发**（/who 是服务器写动作，绝不许连发）；
--   ② **单飞**：上一发的结果没回来（或超时 TB_WHO_PEND 秒）之前，绝不发下一发（防结果串台）；
--   ③ **负缓存**：查过没查到的名字记档 TB_WHO_MISS_TTL 秒，期内**不再查** —— 这就是用户要的「防止重复查询」；
--   ④ **队列上限**：待查队列满了就**如实丢弃并记日志**（不静默、不无限堆积）。
-- ★查询日志一律进**调试日志**（EVAL_LOGLINE → /eh logdump 或存档文件），**不刷聊天框**（用户明确「归入调试日志」）。
local TB_WHO_GAP = 5         -- 两次查询的最小间隔（秒）
local TB_WHO_PEND = 8        -- 单飞超时（秒）：这么久还没 WHO_LIST_UPDATE 就当没查到
local TB_WHO_MISS_TTL = 1800 -- 负缓存时长（秒）：查不到的名字半小时内不再查
local TB_WHO_QMAX = 20       -- 待查队列上限
local tbWhoQ = {}            -- 待查队列（存规范化后的键）

-- 开关：nil 视为**开**（用户要求「未缓存角色默认开启主动查询」）
function EVAL_TB_WHO_ON()
  local tb = tbCfg()
  if not tb then return true end
  return tb.whoQuery ~= false
end

-- 纯函数：这一行聊天里**该去查的人名**（没有就返回 nil）。
--   ★与「上色候选」是**两套不同严格度**的判据（并且各自只有一份实现）：
--     上色认得多（方括号 / 行首 / 玩家链接），**查询只认「发送者位置」**——
--     去查方括号频道名、地名、物品名这种是白打扰服务器（次数还是有限的）。
--   判据（照用户截图的真实形态定的）：
--     · 方括号里是**名字形状**：无空白/点/冒号/竖线/括号，≥2 字符、≤16 字符、不是纯数字；
--     · 且处在**发送者位置**：紧跟其后就是冒号，**或者**它是本行**第一个**方括号段、且这段之后
--       到下一个左方括号之前还出现过冒号（覆盖「名字 + 动词 + 冒号」= 说话 这种形态）。
--   例：[Ionol]: 1 ✓ · [Ionol] 说: 1 ✓ · [公会] [Ionol]: 1 → 只取 [Ionol] ✓（公会那段后面是方括号不是冒号）
--       [4. 世界防务] 加入频道。 ✗（名字形状不过）· 玩家链接形态不进查询（那是上色判据的事）
function EVAL_TB_WHO_CANDIDATE(msg)
  if type(msg) ~= "string" or msg == "" then return nil end
  local first = true
  local from = 1
  for _ = 1, 4 do
    local s, e = string.find(msg, "%[[^%[%]]*%]", from)
    if not s then return nil end
    local inner = string.sub(msg, s + 1, e - 1)
    local rest = string.sub(msg, e + 1)
    local len = tbNameCharLen(inner)
    local okShape = (string.find(inner, "[%s%.%:|%[%]]") == nil) and len >= 2 and len <= 16 and
                    (string.find(inner, "^%d+$") == nil)
    if okShape then
      local colon = string.find(rest, "[:：]")
      local nxt = string.find(rest, "%[")
      if (colon and colon == 1) or (first and colon and (nxt == nil or colon < nxt)) then
        return inner
      end
    end
    first = false
    from = e + 1
  end
  return nil
end

-- 负缓存：查不到的名字记档（期内不再查）；表本身也有上限与过期清理，避免无限长
local function tbWhoMissPut(key)
  TB.whoMiss = TB.whoMiss or {}
  TB.whoMiss[key] = (type(GetTime) == "function") and GetTime() or 0
  TB.whoMissN = (TB.whoMissN or 0) + 1
  local n = 0
  for _ in pairs(TB.whoMiss) do n = n + 1 end
  if n > 200 then
    local now = (type(GetTime) == "function") and GetTime() or 0
    for k, t in pairs(TB.whoMiss) do if now - t > TB_WHO_MISS_TTL then TB.whoMiss[k] = nil end end
  end
end
function EVAL_TB_WHO_ISMISS(name)
  local k = tbNameClassKey(name)
  if not k or type(TB.whoMiss) ~= "table" then return false end
  local t = TB.whoMiss[k]
  if not t then return false end
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - t > TB_WHO_MISS_TTL then TB.whoMiss[k] = nil return false end
  return true
end

local function tbWhoQueued(key)
  for i = 1, table.getn(tbWhoQ) do if tbWhoQ[i] == key then return true end end
  return false
end
-- 入队（**唯一的入队口**；返回 true=入队 / false + 原因）—— 所有「不查」的理由都在这一处判
function EVAL_TB_WHO_ENQUEUE(name)
  if not EVAL_TB_WHO_ON() then return false, "off" end
  if TB.whoNoApi then return false, "noapi" end
  local k = tbNameClassKey(name)
  if not k then return false, "badname" end
  if tbNameClass[k] then return false, "cached" end
  if EVAL_TB_WHO_ISMISS(k) then return false, "miss" end -- ★用户要的「查不到就别反复查」
  if tbWhoQueued(k) or (TB.whoPending and TB.whoPending.key == k) then return false, "dup" end
  if table.getn(tbWhoQ) >= TB_WHO_QMAX then
    TB.whoDropped = (TB.whoDropped or 0) + 1
    EVAL_LOGLINE("[名字查询] 队列已满（" .. tostring(TB_WHO_QMAX) .. " 条），丢弃：" .. tostring(name))
    return false, "full"
  end
  table.insert(tbWhoQ, k)
  TB.whoQueued = (TB.whoQueued or 0) + 1
  EVAL_LOGLINE("[名字查询] 入队：" .. tostring(name) .. "（未缓存 → 待查；队列 " .. tostring(table.getn(tbWhoQ)) .. "）")
  return true
end

-- 滴出（每帧由 OnUpdate 调；频率下限 + 单飞都在这里）
local function tbWhoTick()
  if not EVAL_TB_WHO_ON() then return end
  local now = (type(GetTime) == "function") and GetTime() or 0
  local p = TB.whoPending
  if p then
    if now - p.at < TB_WHO_PEND then return end -- 单飞：结果没回来就等着
    tbWhoMissPut(p.key)                          -- 超时 = 当作没查到（记负缓存，别反复查）
    TB.whoPending = nil
    TB.whoTimeout = (TB.whoTimeout or 0) + 1
    EVAL_LOGLINE("[名字查询] 超时无结果（" .. tostring(TB_WHO_PEND) .. " 秒）：" .. tostring(p.name) .. " → 记入负缓存")
    return
  end
  if table.getn(tbWhoQ) < 1 then return end
  if now - (TB.whoLast or -999) < TB_WHO_GAP then return end -- ★频率下限
  local key = table.remove(tbWhoQ, 1)
  if tbNameClass[key] then return end -- 排队期间已被别的来源补上 → 不查
  TB.whoLast = now
  TB.whoPending = { key = key, name = key, at = now }
  TB.whoSent = (TB.whoSent or 0) + 1
  if type(SendWho) ~= "function" then
    TB.whoPending = nil
    TB.whoNoApi = true
    EVAL_LOGLINE("[名字查询] 本客户端没有 SendWho → 主动查询不可用（自动退化为只用本地缓存）")
    return
  end
  local ok = pcall(SendWho, key)
  if ok then
    EVAL_LOGLINE("[名字查询] 已发出：/who " .. tostring(key) .. "（第 " .. tostring(TB.whoSent) ..
      " 次；结果回来前不再发，下次最早 " .. tostring(TB_WHO_GAP) .. " 秒后）")
  else
    TB.whoPending = nil
    EVAL_LOGLINE("[名字查询] SendWho 调用失败：" .. tostring(key))
  end
end
EVAL_TB_WHO_TICK = tbWhoTick -- 供每帧 / 测试直调

-- WHO_LIST_UPDATE 到了：先结清在途那一发（查到 → 进缓存；没有 → 记负缓存），再顺带采集整张结果表
function EVAL_TB_WHO_ONRESULTS()
  local p = TB.whoPending
  if not p then return false, nil end
  local n = 0
  if type(GetNumWhoResults) == "function" then
    local ok, v = pcall(GetNumWhoResults)
    if ok and type(v) == "number" then n = v end
  end
  local found = false
  if type(GetWhoInfo) == "function" then
    for i = 1, n do
      local okp, nm, _g, _lv, _race, klass = pcall(GetWhoInfo, i)
      if okp and type(nm) == "string" and tbNameClassKey(nm) == p.key then
        found = true
        tbNameClassPut(nm, klass)
      end
    end
  end
  TB.whoPending = nil
  TB.whoLast = (type(GetTime) == "function") and GetTime() or TB.whoLast
  if found then
    TB.whoHit = (TB.whoHit or 0) + 1
    EVAL_LOGLINE("[名字查询] 查到：" .. tostring(p.name) .. " → 已进名字缓存（可上色了）")
  else
    tbWhoMissPut(p.key)
    EVAL_LOGLINE("[名字查询] 没查到：" .. tostring(p.name) .. "（" .. tostring(n) .. " 条结果里没有）→ 记入负缓存，期内不再查")
  end
  return found, p.name
end

function EVAL_TB_WHO_STATE()
  local miss = 0
  for _ in pairs(TB.whoMiss or {}) do miss = miss + 1 end
  return { on = EVAL_TB_WHO_ON(), noApi = TB.whoNoApi and true or false, queued = table.getn(tbWhoQ),
           pending = TB.whoPending and TB.whoPending.name or nil, gap = TB_WHO_GAP, pend = TB_WHO_PEND,
           ttl = TB_WHO_MISS_TTL, qmax = TB_WHO_QMAX,
           sent = TB.whoSent or 0, hit = TB.whoHit or 0, missN = TB.whoMissN or 0, missed = miss,
           dropped = TB.whoDropped or 0, timeout = TB.whoTimeout or 0, enq = TB.whoQueued or 0 }
end
function EVAL_TB_WHO_RESET() -- 测试用：清队列/在途/负缓存/计数（**不清**名字缓存）
  tbWhoQ = {}
  TB.whoPending, TB.whoLast, TB.whoNoApi = nil, nil, nil
  TB.whoMiss = {}
  TB.whoSent, TB.whoHit, TB.whoMissN, TB.whoDropped, TB.whoTimeout, TB.whoQueued = 0, 0, 0, 0, 0, 0
end
-- 勾/取消勾：关掉 = 立刻停止并**清空队列**（如实记日志）；打开 = 记一行
function EVAL_TB_WHO_AFTER_TOGGLE()
  local on = EVAL_TB_WHO_ON()
  if not on then
    local n = table.getn(tbWhoQ)
    tbWhoQ, TB.whoPending = {}, nil
    EVAL_LOGLINE("[名字查询] 已关闭主动查询（清空待查队列 " .. tostring(n) .. " 条）")
  else
    EVAL_LOGLINE("[名字查询] 已开启主动查询（未缓存的名字会按 " .. tostring(TB_WHO_GAP) .. " 秒/次限频查询）")
  end
  return on
end

function EVAL_TB_CHATCOLOR_AFTER_TOGGLE()
  pcall(tbNcHarvest, "unit")
  pcall(tbNcHarvest, "guild")
  local on = EVAL_TB_CHATCOLOR_ON()
  local demo = ""
  local okn, nm = pcall(UnitName, "player")
  if okn and type(nm) == "string" and nm ~= "" then
    local tok = tbNameClassGet(nm)
    local hex = tok and TB_PAINT_CLASS_COLOR[tok]
    if hex then demo = "（示例：" .. "|c" .. hex .. nm .. "|r）" end
  end
  say(on and L("TB_CHATCOLOR_ON_MSG") or L("TB_CHATCOLOR_OFF_MSG"))
  if demo ~= "" and on then say(demo) end
  return on
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
-- ★1.74.13 频道多选：qchan 集合表的读取/摘要/择路三个唯一来源（UI 与播报共用，别处不许复刻）
function EVAL_TB_QCHAN_SET()
  local tb = tbCfg()
  if type(tb) ~= "table" or type(tb.qchan) ~= "table" then return {} end
  return tb.qchan
end
function EVAL_TB_QCHAN_ANY()
  local s = EVAL_TB_QCHAN_SET()
  return (s.self or s.say or s.party) and true or false
end
function EVAL_TB_QCHAN_SUMMARY()
  local s = EVAL_TB_QCHAN_SET()
  local parts = {}
  if s.self then table.insert(parts, L("TB_CH_SELF")) end
  if s.say then table.insert(parts, L("TB_CH_SAY")) end
  if s.party then table.insert(parts, L("TB_CH_PARTY")) end
  if table.getn(parts) == 0 then return L("TB_CH_OFF") end
  return table.concat(parts, "、")
end
-- 择路（用户定）：多选时按**优先级 队伍 > 说 > 仅自己** 取**一个**频道，每条进度只播报一次。
-- ★队伍频道只在「真的在队伍里」才可用（不在队伍发 PARTY 只会吃到客户端报错）；
--   队伍不可用就**在已勾选的集合内**顺延（说→仅自己），绝不降级到用户没勾的频道。
--   只勾了队伍却不在队伍 → 返回 nil 如实跳过（本轮不播）。
function EVAL_TB_QCHAN_PICK()
  local s = EVAL_TB_QCHAN_SET()
  local inParty = false
  if type(GetNumPartyMembers) == "function" then
    local okn, n = pcall(GetNumPartyMembers)
    inParty = okn and (tonumber(n) or 0) > 0
  end
  if s.party and inParty then return "party" end
  if s.say then return "say" end
  if s.self then return "self" end
  return nil
end
local function tbNotify(msg)
  local ch = EVAL_TB_QCHAN_PICK() -- 1.74.13 多选 → 优先级择一，每次进度仅播报一次
  if not ch then return end
  if ch == "self" then say(msg) return end
  tbQPush({ kind = "chat", text = msg, ctype = (ch == "party") and "PARTY" or "SAY" })
end

local function tbQuestDiff()
  if not EVAL_TB_QCHAN_ANY() then return end -- 1.74.13 多选集合为空 = 关闭
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
function EVAL_TB_TICK() tbQuestTick() tbQPump() tbWhoTick() end -- 测试直调（= qf OnUpdate 本体）

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
  -- ★1.73.12 聊天名字着色：缓存采集（**只读**来源；每类各自限频，见 TB_NC_THROTTLE）
  elseif e == "GUILD_ROSTER_UPDATE" then
    tbNcHarvest("guild")
  elseif e == "FRIENDLIST_UPDATE" then
    tbNcHarvest("friends")
  elseif e == "WHO_LIST_UPDATE" then
    -- ★1.73.12 先结清在途那一发（查到 → 进缓存；没有 → 写负缓存），再顺带采集整张结果表
    EVAL_TB_WHO_ONRESULTS()
    tbNcHarvest("who")
  elseif e == "PARTY_MEMBERS_CHANGED" or e == "RAID_ROSTER_UPDATE" or e == "PLAYER_TARGET_CHANGED" then
    tbNcHarvest("unit")
  elseif e == "PLAYER_ENTERING_WORLD" or e == "VARIABLES_LOADED" then
    -- ★★★1.73.51 用户真机实测：「插件刚载入 → 染色失败；即使玩家查询完成还是失败；**只有打开公会信息**才开始染」。
    --   【根因】原来这两条事件只采 `unit`（自己/队伍/团队/目标），而聊天里的人名绝大多数来自**公会/好友/查询**；
    --     公会名册又是**懒加载**的（客户端要等公会窗打开才把名册拉到本地）⇒ 那段时间缓存里根本没有那些名字。
    --   ⇒ 载入时把**所有只读来源**都采一遍（公会名册 / 好友 / 查询结果 / 队伍）——依旧是零服务器请求，
    --     名册真到位了就立刻能染色；没到位也只是读了个 0（无害）。
    --   ★★四类**逐个**调用、不传 nil：限频表是按 kind 做键的，`tbNcAt[nil]` 会直接 `table index is nil`
    --     （本轮的实测事故 —— 判据当场把它抓出来了）。
    tbNcHarvest("unit")
    tbNcHarvest("guild")
    tbNcHarvest("friends")
    tbNcHarvest("who")
    -- ★1.73.52 名册还没到位（本地条数 0）→ 只发一次 GuildRoster()，回来由 GUILD_ROSTER_UPDATE 接
    if type(EVAL_TB_NAMECLASS_ENSURE_ROSTER) == "function" then pcall(EVAL_TB_NAMECLASS_ENSURE_ROSTER) end
    -- ★1.74.5 猎人助手「一键喂食」：再恢复一次 —— 进世界时 UIParent 尺寸才准，
    --   用它把图标锚点按真实尺寸重算（EVAL_HH_RESTORE 幂等；开关关着时什么都不建）
    if type(EVAL_HH_RESTORE) == "function" then pcall(EVAL_HH_RESTORE) end
    -- ★1.74.5 消耗品助手同样再恢复一次（进世界时 UIParent 尺寸才准）
    if type(EVAL_CH_RESTORE) == "function" then pcall(EVAL_CH_RESTORE) end
    -- ★probe/worldmap-minimap 分支：EH_SimpleMap「不启用不载入」对账（没开过就压回禁用）
    if type(EVAL_SMAP_RECONCILE) == "function" then pcall(EVAL_SMAP_RECONCILE) end
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
-- ★1.73.12 聊天名字着色的**缓存采集**事件（全是只读来源；绝不发服务器查询）：
--   公会名册到位 / 好友列表刷新 / 队伍与团队变动 / 查询结果回来 / 换目标 → 各补一次缓存（各有限频窗）
evf:RegisterEvent("GUILD_ROSTER_UPDATE")
evf:RegisterEvent("FRIENDLIST_UPDATE")
evf:RegisterEvent("PARTY_MEMBERS_CHANGED")
evf:RegisterEvent("RAID_ROSTER_UPDATE")
evf:RegisterEvent("WHO_LIST_UPDATE")
evf:RegisterEvent("PLAYER_TARGET_CHANGED")
evf:SetScript("OnEvent", function()
  local e = nil
  if type(event) == "string" then e = event end
  if not e and type(arg1) == "string" then e = arg1 end
  if not e and type(arg2) == "string" then e = arg2 end
  tbChanRetry() -- ★1.71.3 每次事件顺手重试一次频道屏蔽挂载（幂等；成功后立即短路）
  if type(EVAL_TB_CHATEVENT_RETRY) == "function" then EVAL_TB_CHATEVENT_RETRY() end -- ★1.73.12 第二入口
  tbPaintRetry() -- ★1.73.10 职业着色：公会/查询/好友三个窗口同样是懒加载的，一并重试
  if e then EVAL_TB_ONEVENT(e) end
end)

-- 队列滴出帧：每帧检查一次（队空时仅一次表索引+一次 GetTime 比较，开销可忽略）
local qf = CreateFrame("Frame", "EVAL_TOOLBOX_QUEUE", UIParent)
qf:SetScript("OnUpdate", function()
  tbChanRetry() -- ★1.71.3 频道屏蔽挂载的兜底重试（限频 1s；挂上后只做一次布尔判断，开销可忽略）
  if type(EVAL_TB_CHATEVENT_RETRY) == "function" then EVAL_TB_CHATEVENT_RETRY() end -- ★1.73.12 第二入口兜底重试
  tbPaintRetry() -- ★1.73.10 职业着色挂载的兜底重试（限频 1s；三个窗口都挂上后只做一次布尔判断）
  tbQuestTick() tbQPump() -- 1.69.2 任务延迟扫描 + 队列滴出
  tbWhoTick() -- ★1.73.12 名字主动查询的滴出（频率下限/单飞都在它里面；队列空时只有几次判断）
end)

-- ===== 简易地图插件（addons/EH_SimpleMap，独立插件）总开关 =====
-- ★probe/worldmap-minimap 分支：真值 = tbCfg().simpleMap（账号级配置，一处真值）。
--   「不启用不载入」= 走客户端原生插件管理：勾选 → EnableAddOn + SaveAddOns + 提示 /reload；
--   载入期 EVAL_SMAP_RECONCILE 把「没开过的」压回禁用（WoW 对新插件默认启用，不压就会先跑起来）。
--   EnableAddOn/DisableAddOn/SaveAddOns/GetAddOnEnableState/IsAddOnLoaded 均在本客户端官方索引内。
local SMAP_ADDON = "EH_SimpleMap"
function EVAL_SMAP_ENABLED()
  local tb = tbCfg()
  return (tb and tb.simpleMap == true) and true or false
end
function EVAL_SMAP_SET(v)
  local tb = tbCfg()
  if not tb then return false end
  tb.simpleMap = v and true or false
  if v then
    if type(EnableAddOn) == "function" then pcall(EnableAddOn, SMAP_ADDON) end
    if type(SaveAddOns) == "function" then pcall(SaveAddOns) end
    -- ★用户要求：启用时**一律**弹窗确认「现在重载吗」（确定 = 自动 ReloadUI）。
    --   首版只在「未载入」时弹 → 用户实测「没弹」：插件已在 AddOns.json 启用态时
    --   走了「已载入」分支，期望的弹窗链路根本没触发 → 改为无条件弹。
    EVAL_SMAP_RELOAD_ASK()
  else
    if type(DisableAddOn) == "function" then pcall(DisableAddOn, SMAP_ADDON) end
    if type(SaveAddOns) == "function" then pcall(SaveAddOns) end
    say(L("TB_SMAP_OFF"))
  end
  return true
end
function EVAL_SMAP_RECONCILE()
  local tb = tbCfg()
  if tb and tb.simpleMap == true then return end -- 用户开过：不动
  if type(DisableAddOn) == "function" then pcall(DisableAddOn, SMAP_ADDON) end
end

-- ★用户要求（probe/worldmap-minimap 分支）：插件类开关启用时**弹窗确认是否 reload，确认即自动执行**。
--   弹窗极简自绘（DIALOG/220 层级范式）；不依赖 tbSolid/tbBtn（它们在本文本序之后声明，闭包捕获不到）。
local smapCf = nil
local function smapCfSolid(t, r, g, b, a)
  if not t then return end
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") end
  if type(t.SetVertexColor) == "function" then pcall(t.SetVertexColor, t, r, g, b, a) end
end
local function smapCfText(parent, dy, txt, r, g, b, w)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  if type(fs.SetFontObject) == "function" and type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  pcall(fs.SetPoint, fs, "TOP", parent, "TOP", 0, dy)
  if w and type(fs.SetWidth) == "function" then pcall(fs.SetWidth, fs, w) end
  if type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, "CENTER") end
  if type(fs.SetTextColor) == "function" then pcall(fs.SetTextColor, fs, r, g, b) end
  if type(fs.SetText) == "function" then pcall(fs.SetText, fs, txt) end
  return fs
end
local function smapCfBuild()
  if smapCf then return true end
  if type(CreateFrame) ~= "function" then return false end
  local W, H = 380, 130
  local root = CreateFrame("Frame", "EVAL_TB_SMAP_CONFIRM", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 220) -- 高于工具箱弹窗(200)、低于全局下拉(250)
  pcall(root.EnableMouse, root, true)
  local bg = root:CreateTexture(nil, "BACKGROUND")
  smapCfSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    smapCfSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    smapCfSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  smapCfText(root, -10, L("TB_SIMPLEMAP"), 0.95, 0.82, 0.35)
  smapCfText(root, -36, L("TB_SMAP_ASK"), 0.90, 0.90, 0.90, W - 40)
  local function mkBtn(txt, x, onClick)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(90) b:SetHeight(22)
    b:SetPoint("BOTTOM", root, "BOTTOM", x, 14)
    if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
    if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
    local bb = b:CreateTexture(nil, "BACKGROUND")
    smapCfSolid(bb, 0.20, 0.16, 0.08, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bl = b:CreateFontString(nil, "OVERLAY")
    if type(bl.SetFontObject) == "function" and type(GameFontNormal) ~= "nil" then pcall(bl.SetFontObject, bl, GameFontNormal) end
    pcall(bl.SetPoint, bl, "CENTER", b, "CENTER", 0, 0)
    if type(bl.SetText) == "function" then pcall(bl.SetText, bl, txt) end
    b:SetScript("OnClick", onClick)
    return b
  end
  mkBtn(L("BTN_OK"), -55, function()
    pcall(root.Hide, root)
    if type(ReloadUI) == "function" then pcall(ReloadUI) end -- ★确认 = 自动执行 /reload
  end)
  mkBtn(L("BTN_CANCEL"), 55, function() pcall(root.Hide, root) end)
  root:Hide()
  smapCf = root
  return true
end
function EVAL_SMAP_RELOAD_ASK()
  if smapCfBuild() then
    pcall(smapCf.Show, smapCf)
  else
    say(L("TB_SMAP_RELOAD")) -- 弹窗建不起来就退回纯文字提示
  end
end

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
    -- ★1.74.0 升级为**复合行**：勾选 = 启用/关闭；右侧按钮 = 拦截关键字（多选下拉 + 输入框）
    { t = "kw", key = "chanJoin", label = L("TB_CHANJOIN"), tip = L("TB_CHANJOIN_TIP") },
    -- ★1.73.10 用户要求：角色名按职业着色（参考 tmp/XGuild 的**需求**，实现见本文件「职业着色」段；默认开）
    { t = "c", key = "colorClass", label = L("TB_COLORCLASS"), tip = L("TB_COLORCLASS_TIP") },
    -- ★1.73.12 用户要求：「聊天窗 内的名字能着色吗?需要走缓存?」→ 聊天文字里的角色名按职业色（默认开）
    { t = "c", key = "chatColor", label = L("TB_CHATCOLOR"), tip = L("TB_CHATCOLOR_TIP") },
    -- ★1.73.12 用户追加要求：未缓存的名字**主动查一次**（默认开；可在这里关掉）
    { t = "c", key = "whoQuery", label = L("TB_WHOQ"), tip = L("TB_WHOQ_TIP") },
    -- ★1.73.24 用户要求：右键聊天名字弹菜单（公会邀请 / 复制名字 / /s 说出名字；默认开）
    { t = "c", key = "nameMenu", label = L("TB_NAMEMENU"), tip = L("TB_NAMEMENU_TIP") },
    { t = "g", label = L("TB_GUILDNOTIFY"), tip = L("TB_GUILDNOTIFY_TIP") },
    { t = "h", label = L("TB_H_QAUTO") }, -- 1.69.0 任务组拆分：自动交接 / 任务通知
    -- ★1.71.2 用户要求：自动接取 / 交付任务 **分成两个开关**（原来共用一个 quest 键，想只接取不交付做不到）
    { t = "c", key = "questAccept", label = L("TB_QUEST_ACCEPT"), tip = L("TB_QUEST_ACCEPT_TIP") },
    { t = "c", key = "questTurnIn", label = L("TB_QUEST_TURNIN"), tip = L("TB_QUEST_TURNIN_TIP") },
    -- ★1.71.2 用户要求：「自动交接任务 按键停止功能，比如按住 shift 临时停止」
    { t = "key", key = "holdKey", label = tbHoldLabel(), tip = L("TB_HOLD_TIP") },
    { t = "h", label = L("TB_H_QNOTIFY") },
    { t = "ch", key = "qchan", label = L("TB_QCHAN"), tip = L("TB_QCHAN_TIP") }, -- 频道选择行
    -- ★1.74.5 用户要求：新增「猎人助手」分组 →「一键喂食」开关（默认关）
    --   总闸门 = tools/HunterHelper.lua 的 feedPet：勾上才**懒建**屏幕上的喂食图标（未勾 = 一个帧都不建）
    { t = "h", label = L("TB_H_HUNTER") },
    --   ★wip = 右侧那枚**黄感叹号（待测试）**的 tooltip 文案（用户要求：还没经过游戏内实测的功能要标出来）
    { t = "c", key = "feedPet", label = L("TB_FEEDPET"), tip = L("TB_FEEDPET_TIP"), wip = L("TB_WIP_TIP") },
    -- ★1.74.5 用户要求：「参照喂食助手，添加个消耗品助手」→ 多选 + 主图标旁横排各自点用
    { t = "h", label = L("TB_CH_GROUP") },
    { t = "c", key = "consumable", label = L("TB_CONSUMABLE"), tip = L("TB_CONSUMABLE_TIP"), wip = L("TB_WIP_TIP") },
    -- ★1.74.7 用户要求：「按照推荐的在工具箱内添加个一键下马功能」→ 骑乘助手分组
    --   总闸门 = tools/DismountHelper.lua 的 dismount：勾上才懒建屏幕上的下马图标（未勾 = 一个帧都不建）
    --   ★实现依据：本客户端无 Dismount/IsMounted API；坐骑=可取消的有益光环（tooltip 描述含「速度提高X%」）
    --     → CancelPlayerBuff（非 Protected）取消它。自动下马 = 被系统以「你正在/无法在/骑乘」拒绝时顺手下马。
    { t = "h", label = L("TB_H_RIDE") },
    { t = "c", key = "dismount", label = L("TB_DISMOUNT"), tip = L("TB_DISMOUNT_TIP"), wip = L("TB_WIP_TIP") },
    { t = "c", key = "dismountAuto", label = L("TB_DISMOUNT_AUTO"), tip = L("TB_DISMOUNT_AUTO_TIP"), wip = L("TB_WIP_TIP") },
    -- ★1.74.27 用户要求：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」
    --   稀有提醒转播（tools/RareWatch.lua）的**总开关**放这里；★读写走实现自己的单一来源
    --   （EVAL_RW_ENABLED / EVAL_RW_SET），**不另开一个配置键** —— 免得开关与实现两处真值打架。
    { t = "h", label = L("TB_H_RAREWATCH") },
    { t = "rw", key = "rareWatch", label = L("TB_RAREWATCH"), tip = L("TB_RAREWATCH_TIP") },
    -- ★probe/worldmap-minimap 分支：独立插件 EH_SimpleMap（addons/ 目录，探针版）的总开关。
    --   不启用不载入 + 勾选后提示 /reload（get/set 走上方 EVAL_SMAP_*，单一真值 tb.simpleMap）。
    { t = "h", label = L("TB_H_SIMPLEMAP") },
    { t = "smap", key = "simpleMap", label = L("TB_SIMPLEMAP"), tip = L("TB_SIMPLEMAP_TIP"), wip = L("TB_SMAP_WIP") },
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
  local cols = TB.cols or TB_COLS
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    -- ★读 r.item（刷新时记下的**实际映射**），不在这里重算（否则变异测不出来）
    if r and r.item and r.item.key == key and r.add then return r.add.btn end
  end
  return nil
end
-- ★1.74.13 读值口：取某 key 那行的「值按钮」（chv；走真实控件 + 刷新时记下的实际映射）
function EVAL_TEST_TB_CHV_FOR(key)
  if not TB.built then return nil end
  local cols = TB.cols or TB_COLS
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    if r and r.item and r.item.key == key and r.chv then return r.chv.btn end
  end
  return nil
end
-- ★1.74.27 读值口：取某 key 那行的**勾选框 + 勾号**（走真实控件 + 刷新时记下的实际映射）——
--   稀有提醒开关的判据要能走**真实 OnClick**（不是直调 EVAL_RW_SET，那等于测自己）。
function EVAL_TEST_TB_CHK_FOR(key)
  if not TB.built then return nil end
  local cols = TB.cols or TB_COLS
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    if r and r.item and r.item.key == key and r.chk then return r.chk, r.mark end
  end
  return nil
end
-- ★1.74.5 读值口：取某 key 那行的「待测试」标记按钮（走真实控件 + 刷新时记下的实际映射；测试不复刻逻辑）
function EVAL_TEST_TB_WIP_FOR(key)
  if not TB.built then return nil end
  local cols = TB.cols or TB_COLS
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    if r and r.item and r.item.key == key and r.wip then return r.wip.btn, r.wip.tex end
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

-- ===== 1.73.11 两列版式（用户：「工具箱分两列」）=====
-- 判据与分类模版窗同一套纪律（见 tplTwoColPlan）：**组是不拆的最小单位**（组的标题与它的行必须同列，
--   否则右列开头孤零零几行看着像「少了一组 / 多了一组」），切点取**两列行数差最小**。
-- ★与分类模版窗的差别：这里每行都是**可交互控件行**（勾选框 / 文案 / 摘要 / 按钮），行高列宽固定 →
--   不需要量宽；但「列不相交」必须能断言（右列控件的左边缘 > 左列控件的右边缘）。
-- 纯函数：在**本页**的条目里找一个「组边界」切点，使两列行数差最小
--   items = 全模型（含组标题行 t="h"）；off = 本页起始下标（0 基）；rows = 每列行数上限；cols = 列数
--   返回：cut（本页左列占几条）、rowsL、rowsR、pageN（本页实际显示几条）
function EVAL_TB_COL_CUT(items, off, rows, cols)
  local n = table.getn(items or {})
  local c = tonumber(cols) or TB_COLS
  local per = (tonumber(rows) or TB.ROWS) * c
  local pageN = n - (tonumber(off) or 0)
  if pageN > per then pageN = per end
  if pageN < 0 then pageN = 0 end
  if pageN == 0 then return 0, 0, 0, 0 end
  if c < 2 then return pageN, pageN, 0, pageN end
  -- 允许的切点 = 本页内「下一个条目是组标题」的位置，以及末尾
  --   ★组边界切点保证右列**从组标题开头**（不会把某组的后半截甩到右列）
  local cands = { pageN }
  for i = 1, pageN - 1 do
    local nxt = items[(tonumber(off) or 0) + i + 1]
    if type(nxt) == "table" and nxt.t == "h" then table.insert(cands, i) end
  end
  local bestCut, bestDiff = nil, nil
  for i = 1, table.getn(cands) do
    local cc = cands[i]
    local l, r = cc, pageN - cc
    if l <= (tonumber(rows) or TB.ROWS) and r <= (tonumber(rows) or TB.ROWS) then
      local d = math.abs(l - r)
      if bestDiff == nil or d < bestDiff then bestDiff, bestCut = d, cc end
    end
  end
  if bestCut == nil then bestCut = math.min(tonumber(rows) or TB.ROWS, pageN) end -- 兜底：单个组太长时硬切（不至于溢出）
  return bestCut, bestCut, pageN - bestCut, pageN
end

-- ===== 刷新（滚动窗口切片：可见性走显式 Show/Hide 契约） =====
function EVAL_TB_REFRESH()
  if not TB.built then return end
  local m = tbModel()
  local n = table.getn(m)
  -- ★1.73.11 两列：每页 = 每列行数 × 列数；页码按**整页**推进（与图标库的「上页/下页」同语义）
  local cols = TB.cols or TB_COLS
  local per = TB.ROWS * cols
  local pages = math.max(1, math.ceil(n / per))
  local maxOff = (pages - 1) * per
  if TB.off > maxOff then TB.off = maxOff end
  if TB.off < 0 then TB.off = 0 end
  -- 本页按「组边界」切成左右两段（切点是纯函数，见 EVAL_TB_COL_CUT）
  local cut, rowsL, rowsR, pageN = EVAL_TB_COL_CUT(m, TB.off, TB.ROWS, cols)
  TB.cut, TB.rowsL, TB.rowsR, TB.pageN = cut, rowsL, rowsR, pageN
  local LX = 18
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    -- 第 1 列取本页第 slot 条；第 2 列取本页第 (cut + slot) 条（超出本页 → 这一格空着）
    -- ★★左列只放本页前 cut 条、右列只放第 cut+1..pageN 条 —— 两边都越界就会**同一条出现两次**
    --   （本轮实测：漏了「左列也要受 cut 约束」→ 组 120 的「条目不重不漏」当场抓到）
    local it = nil
    if r then
      local pi = (r.col == 2) and (cut + r.slot) or r.slot
      local okc = (r.col == 2) and (pi > cut and pi <= pageN) or (pi >= 1 and pi <= cut)
      if okc then it = m[TB.off + pi] end
      -- ★★把**实际映射**记在行上（r.pi / r.item）：读值口与 [添加] 查找都从这里读 ——
      --   绝不在别处再实现一遍。本轮实测：读值口自己复刻了一遍映射 → M106（左列不受 cut 约束）的变异
      --   **照样存活**，因为测试读到的是读值口那份"正确版本"，不是刷新真正用的那份。
      r.pi, r.item = okc and pi or nil, it
    end
    r.chk:Hide() r.text:Hide() r.hdr:Hide() r.extra:Hide() r.add.btn:Hide() r.clr.btn:Hide() r.chv.btn:Hide()
    if r.wip then r.wip.btn:Hide() end -- ★1.74.5 「待测试」标记也在显式清单里（少一处 = 上一页的标记残留）
    r.get, r.set = nil, nil
    r.modelKey = it and it.key or nil -- ★1.73.10 记住这一格当前是哪个 key（勾选后要按 key 做即时副作用）
    if it then
      if it.t == "h" then
        -- ★1.73.30 组标题栏宽度自适应本列（纯函数拼分隔条；渲染与断言同源）
        r.hdr:SetText(EVAL_TB_HDR_TEXT(it.label, TB.colW))
        r.hdr:Show()
      else
        if it.t == "c" then
          local key = it.key
          r.get = function() local tb = tbCfg() return tb and tb[key] and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[key] = v and true or false end end
        elseif it.t == "rw" then
          -- ★1.74.27 稀有提醒转播：开关真值在 tools/RareWatch.lua（EVAL_RW_ENABLED/EVAL_RW_SET），
          --   这里只是**它的一个面板**，不存第二份配置（改一处即改全局；`/eh go 稀有 开|关` 与它同源）
          r.get = function() return (type(EVAL_RW_ENABLED) == "function") and EVAL_RW_ENABLED() or false end
          r.set = function(v) if type(EVAL_RW_SET) == "function" then EVAL_RW_SET(v) end end
        elseif it.t == "smap" then
          -- ★probe/worldmap-minimap 分支：EH_SimpleMap 独立插件开关（EnableAddOn + 提示 /reload）
          r.get = function() return (type(EVAL_SMAP_ENABLED) == "function") and EVAL_SMAP_ENABLED() or false end
          r.set = function(v) if type(EVAL_SMAP_SET) == "function" then EVAL_SMAP_SET(v) end end
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
        if it.t == "kw" then -- ★1.74.0 频道通知屏蔽 + 拦截关键字：勾选=启用，值按钮 = 关键字多选下拉（含输入框）
          local key = it.key
          r.get = function() local tb = tbCfg() return tb and tb[key] and true or false end
          r.set = function(v) local tb = tbCfg() if tb then tb[key] = v and true or false end end
          r.chv.text:SetText((EVAL_TB_CHANKEY_SUMMARY()))
          r.chv.btn:Show()
          r.chv.btn:SetScript("OnClick", function() EVAL_TB_CHANKEYS_OPEN(r.chv.btn) end)
        end
        if it.t == "ch" then -- 1.69.0 频道选择行；★1.74.13 改**多选下拉**（用户：「下拉需要支持多选，优先级 队伍>说>自己，每次任务进度仅播报一次」）
          local key = it.key
          -- 勾选框 = 是否启用：勾上（空集合时）默认「仅自己」；取消勾选 = 清空集合（关闭）
          r.get = function() return EVAL_TB_QCHAN_ANY() end
          r.set = function(v)
            local tb = tbCfg()
            if not tb then return end
            if v then
              if not EVAL_TB_QCHAN_ANY() then tb[key] = { self = true } end
            else
              tb[key] = nil
            end
          end
          r.chv.text:SetText(EVAL_TB_QCHAN_SUMMARY())
          r.chv.btn:Show()
          r.chv.btn:SetScript("OnClick", function()
            if type(EVAL_DD_OPEN) ~= "function" then return end
            -- 关闭 = 互斥项：集合为空时它带勾；点任一频道即隐式离开「关闭」
            local function curSel()
              local s, sel = EVAL_TB_QCHAN_SET(), {}
              if not (s.self or s.say or s.party) then sel[1] = true
              else
                if s.self then sel[2] = true end
                if s.say then sel[3] = true end
                if s.party then sel[4] = true end
              end
              return sel
            end
            EVAL_DD_OPEN(r.chv.btn, { L("TB_CH_OFF"), L("TB_CH_SELF"), L("TB_CH_SAY"), L("TB_CH_PARTY") }, function(pi, on)
              local tb = tbCfg()
              if not tb then return end
              if pi == 1 then
                if on == true then tb[key] = nil end -- 勾「关闭」= 清空集合（互斥）
              else
                local ch = TB_CHAN_ORDER[pi]
                if ch then
                  if type(tb[key]) ~= "table" then tb[key] = {} end
                  if on == true then tb[key][ch] = true else tb[key][ch] = nil end
                end
              end
              if type(EVAL_DD_SYNC) == "function" then EVAL_DD_SYNC(curSel()) end -- 面板不关 → 互斥后的标记当场重画
              EVAL_TB_REFRESH()
            end, { multi = true, selected = curSel() })
          end)
        end
        if r.get and r.get() then r.mark:Show() else r.mark:Hide() end
        r.chk:Show()
        r.text:SetText(it.label)
        r.text:Show()
        r.tip = it.tip
        -- ★1.74.5 用户要求：模型标了 wip 的行 → 右侧显示**插件本地黄感叹号**（待测试）
        if it.wip and r.wip then
          r.wip.tip = it.wip
          r.wip.btn:Show()
        end
      end
    end
  end
  if TB.indicator then
    -- ★1.73.11 计数按**本页实际显示**的区间报（两列时每页 = 每列行数 × 列数）
    if n > per then
      TB.indicator:SetText(string.format("%d-%d / %d", TB.off + 1, TB.off + pageN, n))
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
  -- ★1.73.11 两列：列宽 = (可用宽 − 列缝 × (列数−1)) / 列数；窗口太窄（列宽 < 200）退化成单列
  --   （硬分两列会把「标签 + 摘要 + 两个按钮」压成一团 —— 与分类模版窗同一条「先算可用空间」纪律）
  local colW = math.floor(((RW - LX) - TB_COL_GAP * (TB_COLS - 1)) / TB_COLS)
  local cols = TB_COLS
  if colW < 200 then cols = 1 colW = RW - LX end
  local colX = { LX }
  for ci = 2, cols do colX[ci] = LX + (ci - 1) * (colW + TB_COL_GAP) end
  TB.cols, TB.colW, TB.colX, TB.colGap = cols, colW, colX, TB_COL_GAP

  for i = 1, TB.ROWS * cols do
    local col = math.floor((i - 1) / TB.ROWS) + 1
    if col > cols then col = cols end
    local slot = ((i - 1) % TB.ROWS) + 1
    local cX, cRight = colX[col], colX[col] + colW
    local y = -56 - (slot - 1) * ROWH
    local row = { col = col, slot = slot, x = cX, right = cRight }
    -- 勾选框（复刻 cfgCheck 金边风格）
    local chk = CreateFrame("Button", nil, root)
    chk:SetWidth(16) chk:SetHeight(16)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", cX, y)
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
      -- ★1.73.10 职业着色是**即时生效**的全局行为：勾/取消勾后立刻重刷三个窗口，
      --   否则颜色要等窗口自己下次刷新才变，用户会以为开关没反应（本项目「改开关立即生效」惯例）
      if row.modelKey == "colorClass" then pcall(EVAL_TB_PAINT_REFRESH) end
      -- ★1.73.12 聊天名字着色同样是**即时生效**的全局行为：勾上就补缓存 + 回一句示例；
      --   已打印的历史行**改不了**（聊天框不复渲）→ 提示语里写清「对之后的消息生效」。
      if row.modelKey == "chatColor" then pcall(EVAL_TB_CHATCOLOR_AFTER_TOGGLE) end
      -- ★1.73.12 关掉主动查询 = 立刻停止并清空待查队列（如实记日志，不静默）
      if row.modelKey == "whoQuery" then pcall(EVAL_TB_WHO_AFTER_TOGGLE) end
                  if row.modelKey == "nameMenu" then
                    -- ★关掉 = 菜单收起来（包装仍留着但一律放行 → 不改客户端既有行为）
                    if EVAL_TB_NAMEMENU_ON() then pcall(EVAL_TB_NAMEMENU_RETRY) else pcall(EVAL_TB_MENU_HIDE) end
                  end
      -- ★1.73.12 频道屏蔽开关：勾/取消勾时立刻应用/撤销**官方消息组**（与 Lua 层那条路并存）
      if row.modelKey == "chanJoin" then
        TB.chanOffLogged = false
        pcall(EVAL_TB_CHAN_OFFICIAL_SYNC)
      end
      -- ★1.74.5 猎人助手「一键喂食」：勾上 = 立刻懒建并显示喂食图标；取消 = 图标收起（都不需要重载）
      if row.modelKey == "feedPet" then pcall(EVAL_HH_TOGGLE) end
      -- ★1.74.5 消耗品助手：同一条纪律 —— 勾上即时建并显示，取消即时收起
      if row.modelKey == "consumable" then pcall(EVAL_CH_TOGGLE) end
      -- ★1.74.7 骑乘助手「一键下马」：勾上 = 懒建并显示下马图标（并挂上自动下马事件帧）
      if row.modelKey == "dismount" then
        if type(EVAL_DH_TOGGLE) == "function" then pcall(EVAL_DH_TOGGLE) end
        if type(EVAL_DH_EVENTS_ENSURE) == "function" then pcall(EVAL_DH_EVENTS_ENSURE) end
      end
      -- 「自动下马」是**行为开关**（不需要图标），改完立刻生效：确保事件帧在、并如实播报
      if row.modelKey == "dismountAuto" then
        if type(EVAL_DH_EVENTS_ENSURE) == "function" then pcall(EVAL_DH_EVENTS_ENSURE) end
        if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
      end
      -- ★1.74.27 稀有提醒转播：开关**即时生效**（转播/点击时各自查开关）→ 顺手把状态报一遍，
      --   玩家立刻看到「开了/关了 + 挂上了没 + 已转播几次」（不必再去敲命令确认）
      if row.modelKey == "rareWatch" then
        if type(EVAL_RW_CMD) == "function" then pcall(EVAL_RW_CMD, "go 稀有") end
      end
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
    -- 标签：★改成**绝对锚点 + 显式限宽**（原来锚在勾选框右侧、宽度自动）——
    --   两列下「自动宽度」会压过列缝，而列不相交必须是**可断言**的（见 EVAL_TB_TEST_LAYOUT）
    local TB_LABEL_W = math.floor(colW * 0.30)
    local TB_EXTRA_X = math.floor(colW * 0.32)
    -- ★1.73.25 标签相对行顶的下偏量：**单一来源**（以前只写在标签锚点里，按钮另算 y → 两者差 3px）
    if not TB_ROW_TXT_DY then TB_ROW_TXT_DY = 3 end
    local TB_ROW_TXT_DY = TB_ROW_TXT_DY
    local text = tbText(root, 11, 0.92, 0.88, 0.80)
    text:SetPoint("TOPLEFT", root, "TOPLEFT", cX + 22, y - TB_ROW_TXT_DY)
    pcall(text.SetWidth, text, TB_LABEL_W)
    pcall(text.SetNonSpaceWrap, text, false)
    row.text = text
    table.insert(widgets, text)
    -- 组标题
    local hdr = tbText(root, 11, 0.95, 0.80, 0.30)
    hdr:SetPoint("TOPLEFT", root, "TOPLEFT", cX, y - 3)
    -- ★组标题也要**显式限宽**：不限宽时它按文字自动撑开，长标题会压过列缝（列不相交就断了）
    pcall(hdr.SetWidth, hdr, colW - 8)
    pcall(hdr.SetNonSpaceWrap, hdr, false)
    row.hdr = hdr
    table.insert(widgets, hdr)
    -- 列表摘要 + 添加/清空（全部**按本列**定位；右对齐的那几个贴本列右边缘）
    local extra = tbText(root, 10, 0.75, 0.72, 0.60)
    extra:SetPoint("TOPLEFT", root, "TOPLEFT", cX + TB_EXTRA_X, y - 3)
    local extraW = (colW - 96) - TB_EXTRA_X - 6
    if extraW < 20 then extraW = 20 end
    pcall(extra.SetWidth, extra, extraW)
    pcall(extra.SetNonSpaceWrap, extra, false)
    row.extra = extra
    table.insert(widgets, extra)
    row.add = tbBtn(root, cRight - 96, y, 44, L("TB_ADD"), function() end, widgets)
    row.clr = tbBtn(root, cRight - 48, y, 40, L("TB_CLEAR"), function() end, widgets)
    row.chv = tbBtn(root, cRight - 96, y, 88, "", function() end, widgets) -- 1.69.0 频道值按钮（ch 行）
    -- ★1.74.5 「待测试」标记（用户要求：一键喂食 右侧 加一个**插件本地图标黄色感叹号**，tooltip=待测试）：
    --   · 贴**本列右边缘**，且沿用「全用距左边表示」的列几何口径（不用 TOPRIGHT 再算一遍）；
    --   · 用**独立小 Button** 而不是 Texture —— 纹理不吃鼠标事件，挂不了 OnEnter/tooltip；
    --   · 路径走单一来源 EVAL_UI_MARK_TEST（EvalHelp.lua 导出；UI ICON CHECK 核它在磁盘上）。
    local wipBtn = CreateFrame("Button", nil, root)
    wipBtn:SetWidth(12)
    wipBtn:SetHeight(12)
    wipBtn:SetPoint("TOPLEFT", root, "TOPLEFT", cRight - 12, y - 2)
    pcall(wipBtn.EnableMouse, wipBtn, true)
    local wipTex = wipBtn:CreateTexture(nil, "OVERLAY")
    wipTex:SetPoint("TOPLEFT", wipBtn, "TOPLEFT", 0, 0)
    wipTex:SetPoint("BOTTOMRIGHT", wipBtn, "BOTTOMRIGHT", 0, 0)
    local wipPath = rawget(_G, "EVAL_UI_MARK_TEST")
    if type(wipPath) == "string" and wipPath ~= "" then pcall(wipTex.SetTexture, wipTex, wipPath) end
    wipBtn:Hide()
    wipBtn:SetScript("OnEnter", function()
      if type(row.wip) ~= "table" or not row.wip.tip then return end
      if type(GameTooltip) ~= "table" then return end
      GameTooltip:SetOwner(wipBtn, "ANCHOR_RIGHT")
      GameTooltip:ClearLines()
      GameTooltip:AddLine(L("TB_WIP"), 1, 0.85, 0.25)
      GameTooltip:AddLine(row.wip.tip, 0.85, 0.85, 0.85, 1)
      GameTooltip:Show()
    end)
    wipBtn:SetScript("OnLeave", function()
      if type(GameTooltip) == "table" then GameTooltip:Hide() end
    end)
    row.wip = { btn = wipBtn, tex = wipTex, tip = nil }
    table.insert(widgets, wipBtn)
    -- ★★★1.73.25 用户（截图圈出「自动购买指定物 / 自动丢弃指定物」两行）：
    --   「右侧的对应的按键 [要与] 左侧名称**对齐**」。
    --   根因（读代码可证）：标签 FontString 锚在 `y - TB_ROW_TXT_DY`（往下 3px），而按钮锚在同行的 `y`
    --   → 按钮比名称**高 3px**（右上那两对 [添加][清空] 最显眼）。
    --   正解：按钮也按**同一个标签偏移**定位 —— 同一行的控制件共用一条基线，别再各算各的 y。
    --   ★这里刻意用**绝对坐标 + 同一个常量**（不锚到标签控件上）：一是行池里的控件显隐不定，
    --     锚到可能被 Hide 的控件会让读值口拿到不可靠几何；二是布局断言读的是绝对矩形。
    local function tbRowBtnAlign(btn, absX)
      if not btn then return end
      pcall(btn.ClearAllPoints, btn)
      pcall(btn.SetPoint, btn, "TOPLEFT", root, "TOPLEFT", absX, y - TB_ROW_TXT_DY)
    end
    tbRowBtnAlign(row.add.btn, cRight - 96)
    tbRowBtnAlign(row.clr.btn, cRight - 48)
    tbRowBtnAlign(row.chv.btn, cRight - 96)
    row.labelW, row.extraW = TB_LABEL_W, extraW
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
  -- ★1.73.11 两列后翻页按**整页**推进（与图标库「上页/下页」同语义；原来每次 ±1 行）
  local function tbPageStep() return TB.ROWS * (TB.cols or TB_COLS) end
  TB.scrollUp = tbBtn(root, bx, btnTop, TB_BTN_W, L("TB_UP"), function()
    TB.off = math.max(0, TB.off - tbPageStep())
    EVAL_TB_REFRESH()
  end, widgets)
  TB.scrollDn = tbBtn(root, bx + TB_BTN_W + TB_BTN_GAP, btnTop, TB_BTN_W, L("TB_DN"), function()
    TB.off = TB.off + tbPageStep()
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
    TB.off = math.max(0, TB.off - dir * TB.ROWS * (TB.cols or TB_COLS)) -- 上滚 = 回到前面（两列后按整页）
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
-- ★★★1.73.33 自动购买弹窗的**列几何单一来源**（全部「距左边」；右对齐的列写**右边缘**）——
--   列头与单元格必须都从这里取，否则就会出现「列头挤成一团、与数据列对不上」（用户红线指出的事故）。
local TB_BUY_COLS = { chkX = 14, chkW = 28, nameX = 46, nameW = 140, nR = 244, nW = 44, perR = 300, perW = 44, delW = 32 }
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
        end, L("TN_LABEL_NAME"))
      end)
      r.nBtn:SetScript("OnClick", function()
        if type(EVAL_TN_OPEN) ~= "function" then return end
        EVAL_TN_OPEN(L("TB_BUY_ASK_N"), tostring(e.n or 1), function(txt)
          local v = tonumber(txt)
          if v and v >= 1 then e.n = math.floor(v) buyUIRefresh() EVAL_TB_REFRESH() end
        end, L("TN_LABEL_N"))
      end)
      r.pBtn:SetScript("OnClick", function()
        if type(EVAL_TN_OPEN) ~= "function" then return end
        EVAL_TN_OPEN(L("TB_BUY_ASK_PER"), tostring(e.per or 1), function(txt)
          local v = tonumber(txt)
          if v and v >= 1 then e.per = math.floor(v) buyUIRefresh() EVAL_TB_REFRESH() end
        end, L("TN_LABEL_PER"))
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
    -- ★★★1.73.34 滚动条审计：页码三处修正 ——
    --   ① 原来是 off / ROWS + 1（**浮点除法**）：真客户端显示「1.25/2」，fengari 直接报错（bad argument #2 to format）；
    --   ② 而且到底时 off 被夹到 maxOff（不是 ROWS 的整数倍）→ 算出来还是第 1 页 ⇒ 到底就取**最后一页**；
    --   ③ 箭头原来按「行」滚、指示按「页」算 → 两者对不上 ⇒ 箭头改成**按页**滚（一次一页，与指示一致）。
    local page
    if n == 0 then
      page = 1
    elseif buyUI.off >= math.max(0, n - TB_BUY_UI_ROWS) then
      page = pages -- 到底（含夹取后的位置）= 最后一页
    else
      page = math.floor(buyUI.off / TB_BUY_UI_ROWS) + 1
    end
    if page < 1 then page = 1 end
    if page > pages then page = pages end
    buyUI.ind:SetText(string.format("%d/%d  (%d)", page, pages, n))
  end
  -- ★1.73.34 边界状态：到顶隐藏 ▲、到底隐藏 ▼（空列表两个都藏）——滚动条机制该有的反馈
  -- ★注意：tbBtn 返回的是**包裹表** {btn,bg,text}，显隐必须走 .btn（本项目的老坑）
  local upBtn = buyUI.up and buyUI.up.btn
  local dnBtn = buyUI.dn and buyUI.dn.btn
  if upBtn and dnBtn then
    if n == 0 then
      upBtn:Hide() dnBtn:Hide()
    else
      if buyUI.off <= 0 then upBtn:Hide() else upBtn:Show() end
      if buyUI.off + TB_BUY_UI_ROWS >= n then dnBtn:Hide() else dnBtn:Show() end
    end
  end
end

local function buyUIBuild()
  if buyUI.root then return end
  -- ★★★1.73.34 审计滚动条（用户：「审计自动购买内的滚动条机制是否符合项目规范」）——
  --   发现 3 处不符：① **完全没有滚轮**（配置窗内其余 5 个列表都有，且都走 EVAL_WHEEL_DIR 单一来源）；
  --   ② ▲▼ 箭头画在 x=W-20，**压在「删除」按钮上**（删除列 316..348 vs 箭头 340..354）→ 点删除会点到箭头；
  --   ③ 页码指示 ind 锚在 y=-46，正压在第一行数据上。
  --   ⇒ 窗口加宽到 384，右侧留 **30px 专用滚动槽**（删除列右边缘 = W-30），箭头进槽、指示挪到底栏。
  local W, H = 384, 268
  local root = CreateFrame("Frame", "EVAL_BUY_UI", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 60, 40)
  pcall(root.SetFrameStrata, root, "DIALOG")
  -- ★★★1.73.31 用户报「自动购买的弹窗点击不到」——【根因】只设了 strata、**没设 frame level**：
  --   同一个 DIALOG 层里按 frame level 排先后，工具箱的行按钮是配置窗的子帧（level 更高）
  --   → 它们**画在弹窗之上**，鼠标也被它们吃掉（截图里能看到行文字/按钮压在弹窗上）。
  --   【修法】① 明确抬到 200（高于配置窗各弹窗 100~140，**低于**全局下拉 250）；
  --           ② EnableMouse(true)：落在弹窗体内的点击由弹窗吃掉，**不再穿透**到底下的工具箱行
  --              （否则在弹窗空白处点一下会勾到后面的复选框）。
  pcall(root.SetFrameLevel, root, 200)
  pcall(root.EnableMouse, root, true)
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
  -- ★★★1.73.33 用户：「这个弹窗还是不能被拖拽」——【根因】它**根本没有拖动柄**（1.73.31 只修了层级/鼠标，
  --   拖动柄是 1.73.32 给「通用输入弹窗」加的，这个弹窗漏了）→ 照项目规程补：柄必须是 **Button**，
  --   同 DIALOG、level = 窗口+1，SetMovable + RegisterForClicks(LeftButtonUp) + RegisterForDrag(LeftButton)，
  --   StartMoving 用 warm-up 两步（本客户端 Frame 的 OnDragStart 不触发）。
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 32) titleBar:SetHeight(20)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 201)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  tbSolid(tbBg, 0.14, 0.11, 0.06, 0.55)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)
  pcall(root.SetMovable, root, true)
  buyUI.titleBar = titleBar
  local closeB = tbBtn(root, W - 26, -3, 18, "X", function() root:Hide() end)
  -- ★★★1.73.33 用户红线指出「列头布局异常」——【根因】列头把「距左边」的数值当「距右边」的偏移用：
  --   总数/每次两个列头锚成 TOPRIGHT -244/-302 → 跑到 x≈116 / x≈58，**互相压在一起**（截图上那串
  --   「启用每次称 总数」就是两个列头叠着画出来的），而且与下面的数据列对不上。
  --   【修法】列几何**单一来源** TB_BUY_COLS（全部用「距左边」表示；右对齐的列写右边缘），列头与单元格都从它取。
  local cols = TB_BUY_COLS
  buyUI.heads = {}
  -- ★列头宽度 = **本列宽度**（单一来源）→ 文字不会串到隔壁列，盒子也不会互相重叠
  local function headL(x, w, txt)
    local h = tbText(root, 10, 0.80, 0.72, 0.45)
    h:SetPoint("TOPLEFT", root, "TOPLEFT", x, -30)
    pcall(h.SetWidth, h, w)
    h:SetText(txt)
    table.insert(buyUI.heads, h)
  end
  local function headR(rightEdge, w, txt)
    local h = tbText(root, 10, 0.80, 0.72, 0.45)
    h:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(W - rightEdge), -30)
    pcall(h.SetWidth, h, w)
    pcall(h.SetJustifyH, h, "RIGHT")
    h:SetText(txt)
    table.insert(buyUI.heads, h)
  end
  headL(cols.chkX, cols.chkW, L("TB_BUY_COL_ON"))
  headL(cols.nameX, cols.nameW, L("TB_BUY_COL_NAME"))
  headR(cols.nR, cols.nW, L("TB_BUY_COL_N"))      -- ★总数（与 r.nt 那一列同右边缘）
  headR(cols.perR, cols.perW, L("TB_BUY_COL_PER"))-- ★每次（与 r.pt 那一列同右边缘）
  headR(W - 30, cols.delW, L("TB_BUY_COL_DEL"))   -- ★操作（删除列；右边缘 = W-30，右侧留滚动槽）
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
    local nb, nt = cell(cols.nameX, cols.nameW, false)      -- 名称
    local qb, qt = cell(cols.nR - 44, 44, true)             -- 总数（右边缘 = cols.nR）
    local pb, pt = cell(cols.perR - 44, 44, true)           -- 每次（右边缘 = cols.perR）
    r.name, r.nt, r.pt = nt, qt, pt
    r.nameBtn, r.nBtn, r.pBtn = nb, qb, pb
    local db = tbBtn(root, W - 62, y, 32, L("TB_BUY_DEL"), function() end) -- 右边缘 = W-30（不占滚动槽）
    r.del = db.btn r.delText = db.text
    rows[i] = r
  end
  local empty = tbText(root, 10, 0.60, 0.58, 0.50)
  empty:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -46)
  empty:SetText(L("TB_BUY_EMPTY"))
  buyUI.empty = empty
  -- ★1.73.33 用户：「标题右侧的说明统一移动到安全说明下面对齐」——
  --   原来 tipLine 挤在标题右边（与标题/X 抢位置），现在放到安全说明**正下方**、同一条左对齐（都贴 12）。
  local hintY = -(44 + TB_BUY_UI_ROWS * 18 + 6)
  local hint = tbText(root, 9, 0.55, 0.60, 0.55)
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", 12, hintY)
  pcall(hint.SetWidth, hint, W - 24)
  hint:SetText(L("TB_BUY_HINT"))
  local tipLine = tbText(root, 9, 0.62, 0.60, 0.52)
  tipLine:SetPoint("TOPLEFT", root, "TOPLEFT", 12, hintY - 13)
  pcall(tipLine.SetWidth, tipLine, W - 24)
  tipLine:SetText(L("TB_BUY_UI_TIP"))
  buyUI.hint, buyUI.tip = hint, tipLine
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
  -- ▲▼ 放进右侧**专用滚动槽**（x = W-22，宽 16）：不再压住「删除」按钮
  -- ★1.73.34 箭头按**页**滚动（原来按行滚、而指示按页算 → 对不上）：一次一页，与页码指示一致
  local up = tbBtn(root, W - 22, -44, 16, "^", function() buyUI.off = math.max(0, buyUI.off - TB_BUY_UI_ROWS) buyUIRefresh() end)
  local dn = tbBtn(root, W - 22, -(44 + (TB_BUY_UI_ROWS - 1) * 18), 16, "v", function() buyUI.off = buyUI.off + TB_BUY_UI_ROWS buyUIRefresh() end)
  buyUI.up, buyUI.dn = up, dn
  -- 页码指示挪到**底栏**（原来锚在 y=-46 压着第一行数据）
  local ind = tbText(root, 9, 0.65, 0.62, 0.50)
  ind:SetPoint("TOPLEFT", root, "TOPLEFT", 176, -(H - 24))
  pcall(ind.SetWidth, ind, 120)
  pcall(ind.SetJustifyH, ind, "LEFT")
  buyUI.ind = ind
  -- ★★★1.73.34 补滚轮（项目规范：方向单一来源 EVAL_WHEEL_DIR；上滚 = 回到前面；dir=0 不是滚轮事件 → 交还原脚本）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
  if okg and type(g) == "function" then prevWheel = g end
  root:SetScript("OnMouseWheel", function(a, b)
    local dir = EVAL_WHEEL_DIR(a, b)
    if dir == 0 then
      if prevWheel then return prevWheel(a, b) end -- ★链式接管（项目规范）
      return
    end
    buyUI.off = math.max(0, buyUI.off - dir) -- 上滚(+1) = 回到前面
    buyUIRefresh()
  end)
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
-- ★★★1.73.31 读值口：弹窗的**层级/鼠标开关** + 工具箱交互控件的层级（「点击不到」= 层级被压 / 不吃点击）
function EVAL_TEST_BUY_UI_Z()
  local out = { buy = nil, toolbox = nil, mouse = nil }
  if buyUI.root then
    local ok, l = pcall(buyUI.root.GetFrameLevel, buyUI.root)
    if ok then out.buy = l end
    local okm, m = pcall(buyUI.root.IsMouseEnabled, buyUI.root)
    if okm then out.mouse = m and true or false end
  end
  for k = 1, (TB.ROWS or 0) do
    local r = TB.rows and TB.rows[k]
    local o = r and (r.chk or (r.add and r.add.btn) or r.clr)
    if o and type(o.GetFrameLevel) == "function" then
      local ok, l = pcall(o.GetFrameLevel, o)
      if ok and type(l) == "number" then out.toolbox = l break end
    end
  end
  return out
end
-- ★★★1.73.33 读值口：自动购买弹窗的**列几何 / 拖动柄 / 说明行**（用户红线指出的两处布局问题都在这可断言）
function EVAL_TEST_BUY_UI_GEO()
  if not buyUI.root then return nil end
  local W = 360
  local okW, w0 = pcall(buyUI.root.GetWidth, buyUI.root)
  if okW and type(w0) == "number" then W = w0 end
  local function num(o, m)
    if not o or type(o[m]) ~= "function" then return nil end
    local ok, v = pcall(o[m], o)
    return (ok and type(v) == "number") and v or nil
  end
  -- ★坐标统一换算成「距窗口左边」（本机桩记录的是**锚点语义**：TOPRIGHT 的 x 是负偏移）——
  --   这样「列头右边缘」与「数据右边缘」才可比（左对齐/右对齐两种锚法都能算到同一条基准线上）。
  local function rect(o)
    if not o then return nil end
    local out = {}
    local okp, point, _relTo, relPoint, ox, oy = pcall(o.GetPoint, o)
    if okp and type(ox) == "number" then
      out.point, out.relPoint, out.ox, out.oy = point, relPoint, ox, oy
      local w = num(o, "GetWidth") or 0
      if relPoint == "TOPRIGHT" then
        out.r = W + ox
        out.x = out.r - w
      else
        out.x = ox
        out.r = ox + w
      end
      out.y = oy
    end
    return out
  end
  local out = { W = W, cols = TB_BUY_COLS, heads = {}, cells = {} }
  for i = 1, table.getn(buyUI.heads or {}) do out.heads[i] = rect(buyUI.heads[i]) end
  local r1 = buyUI.rows and buyUI.rows[1]
  if r1 then
    out.cells.name = rect(r1.name) out.cells.n = rect(r1.nt)
    out.cells.per = rect(r1.pt) out.cells.del = rect(r1.del)
  end
  local tb = buyUI.titleBar
  if tb then
    local function val(m)
      if type(tb[m]) ~= "function" then return nil end
      local ok, v = pcall(tb[m], tb)
      if ok and v ~= nil then return v end
      return nil
    end
    out.drag = val("GetDragRegistered")
    out.clicks = val("GetClicksRegistered")
    out.titleLevel = num(tb, "GetFrameLevel")
  end
  out.level = num(buyUI.root, "GetFrameLevel")
  local okM, mv = pcall(buyUI.root.IsMovable, buyUI.root)
  if okM then out.movable = mv and true or false end
  out.hint = rect(buyUI.hint) out.tip = rect(buyUI.tip)
  return out
end
-- ★★★1.73.34 读值口：滚动条机制（滚轮安装/方向/夹取 · 箭头与删除列不重叠 · 指示在底栏 · 边界状态）
function EVAL_TEST_BUY_UI_SCROLL()
  if not buyUI.root then return nil end
  local W = 384
  local okW, w0 = pcall(buyUI.root.GetWidth, buyUI.root)
  if okW and type(w0) == "number" then W = w0 end
  local function num(o, m)
    if not o or type(o[m]) ~= "function" then return nil end
    local ok, v = pcall(o[m], o)
    return (ok and type(v) == "number") and v or nil
  end
  local function rect(o)
    if not o then return nil end
    local out = {}
    local okp, point, _relTo, relPoint, ox, oy = pcall(o.GetPoint, o)
    if okp and type(ox) == "number" then
      local w = num(o, "GetWidth") or 0
      if relPoint == "TOPRIGHT" then
        out.r = W + ox
        out.x = out.r - w
      else
        out.x = ox
        out.r = ox + w
      end
      out.y = oy
      out.w = w
    end
    return out
  end
  local out = { off = buyUI.off or 0, W = W }
  local okf, f = pcall(buyUI.root.GetScript, buyUI.root, "OnMouseWheel")
  out.wheel = (okf and type(f) == "function") and true or false
  local okm, mw = pcall(buyUI.root.IsMouseWheelEnabled, buyUI.root)
  out.mouseWheel = (okm and mw) and true or false
  out.up = rect(buyUI.up and buyUI.up.btn) out.dn = rect(buyUI.dn and buyUI.dn.btn)
  out.ind = rect(buyUI.ind)
  local r1 = buyUI.rows and buyUI.rows[1]
  out.del = rect(r1 and r1.del)
  local rl = buyUI.rows and buyUI.rows[TB_BUY_UI_ROWS]
  out.delLast = rect(rl and rl.del) -- ★最后一行的控件 y（指示必须在它下面 = 不压任何数据行）
  local function shown(o)
    if not o then return nil end
    local ok, v = pcall(o.IsShown, o)
    return (ok and v) and true or false
  end
  out.upShown = shown(buyUI.up and buyUI.up.btn)
  out.dnShown = shown(buyUI.dn and buyUI.dn.btn)
  local okI, txt = pcall(buyUI.ind.GetText, buyUI.ind)
  out.indText = (okI and tostring(txt or "")) or ""
  out.pages = math.max(1, math.ceil((table.getn(buyUIList() or {})) / TB_BUY_UI_ROWS))
  out.n = table.getn(buyUIList() or {})
  return out
end
-- ★模拟一次滚轮事件（走**真实**的 OnMouseWheel 脚本）
function EVAL_TEST_BUY_UI_WHEEL(a, b)
  if not buyUI.root then return false end
  local ok, f = pcall(buyUI.root.GetScript, buyUI.root, "OnMouseWheel")
  if not ok or type(f) ~= "function" then return false end
  pcall(f, a, b)
  return true
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
-- ★★★1.73.11 断言入口：两列版式的**真实几何**（每行控件的 x/宽 + 列几何 + 切点/两列行数）
--   判据要能验「列不相交」（右列控件左边缘 > 左列控件右边缘）——所以读的是**控件自身**的坐标，
--   不是我们算出来的常量（本项目「不写死布局常量」的纪律）。
function EVAL_TB_TEST_LAYOUT()
  local function rect(o)
    if not o then return nil end
    local okx, x = pcall(o.GetLeft, o)
    local okw, w = pcall(o.GetWidth, o)
    local oky, y = pcall(o.GetTop, o)
    local okh, h = pcall(o.GetHeight, o)
    local oks, sh = pcall(o.IsShown, o)
    -- ★1.73.25 补上高度：断言要能比「垂直中心」（用户要求「按键与左侧名称对齐」）
    return { x = okx and x or nil, w = okw and w or nil, y = oky and y or nil, h = okh and h or nil,
             shown = (oks and sh) and true or false }
  end
  local out = { cols = TB.cols, colW = TB.colW, colGap = TB.colGap, colX = TB.colX,
                rowsPerCol = TB.ROWS, off = TB.off, cut = TB.cut, rowsL = TB.rowsL, rowsR = TB.rowsR,
                pageN = TB.pageN, pool = table.getn(TB.rows or {}), rows = {} }
  local m = tbModel()
  local cols = TB.cols or TB_COLS
  for k = 1, TB.ROWS * cols do
    local r = TB.rows[k]
    if r then
      -- ★读刷新时记下的**实际映射**（r.item / r.pi）——本读值口**不重算**（重算 = 测试验的是读值口自己）
      local it = r.item
      out.rows[k] = { col = r.col, slot = r.slot, pi = r.pi, key = it and it.key or nil,
                      kind = it and it.t or nil, shown = r.chk:IsShown() and true or false,
                      chk = rect(r.chk), text = rect(r.text), extra = rect(r.extra),
                      add = rect(r.add and r.add.btn), clr = rect(r.clr and r.clr.btn),
                      chv = rect(r.chv and r.chv.btn), hdr = rect(r.hdr),
                      wip = rect(r.wip and r.wip.btn), wipTip = (r.wip and r.wip.tip) or nil }
    end
  end
  return out
end
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
