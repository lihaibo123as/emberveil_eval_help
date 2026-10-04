-- EvalHelp · tools/EquipCompare.lua —— 装备比较（1.75.45 新增）
--
-- 需求（用户原话）：「参考UnrealQuest 装备比较.增加个独立工具放置到工具箱内设置开启」
--   ⇒ 做成独立工具模块：**悬停装备类物品**时，在它旁边并排显示**已装备**的同部位物品。
--
-- ★★★参考实现 = **同客户端的** UnrealQuest（`UnrealQuest/Compatibility/ClientAPI.lua` 的
--   `ShowItemCompare` / `HideItemCompare` / `ResolveCompareTooltip`，约 3181~3399 行）——
--   同客户端、同一批 API 已经跑通，口径照抄：
--     · **部位判定** = `GetItemInfo(id)` **第 8 返回 = INVTYPE token**（如 `"INVTYPE_HEAD"`）
--       → 部位**名**（`"HeadSlot"`）→ `GetInventorySlotInfo(名)` 得槽号；
--       `GetInventoryItemLink("player", 槽号)` 判「这一格有没有穿东西」。
--     · **对比框 = 自建 GameTooltip 帧**（最多两个：双戒指/双饰品各一个）。
--       ★**不用客户端的 `ShoppingTooltip1/2`** —— UnrealQuest 注释原文：它们是 `UIParent` 子件，
--         而全屏地图会隐藏 `UIParent` ⇒ 在地图上「填好了也永远看不见」。
--     · `SetInventoryItem` **不会**自带「已装备」标题 ⇒ 读回刚填的行、自己插一行
--       `CURRENTLY_EQUIPPED`（客户端本地化串）再重画。
--     · ★本模块**只读**玩家那个 GameTooltip 的**几何与首行文本**（不调它的任何 Set* 方法）
--       ⇒ 不会破坏玩家自己的提示（CLAUDE.md：借别人的 UI 对象去 *写* = 静默破坏界面）。
--     · ★★★**换填对比框之前必须把左右两栏 FontString 全抹一遍**（`ecTipWipe`）：本客户端换填时
--       **只写它自己那几行**的 FontString —— 上一件（比如武器）留在**右栏**的「速度 2.70」既冲不掉、
--       `ClearLines` 也收不走 ⇒ ① 读回时被并进护甲那一行、② 或留在框里继续显示
--       （用户报障：「装备上而不是武器信息,里面的速度是哪来的?」）。
--       取证 = `/eh go 装备比较 行摊开`（把两边气泡的每一行连左右栏一起摊开，鼠标先停在物品上）。
--     · ★★★**汇总「只在一侧出现」的判据 = 对比框那一趟读到的全部键**（含**同值**行 ⇒ `cmpKey`）：
--       只把「有变化的键」标成见过 ⇒ 「护甲 144 对 144」这种同值属性会在第二趟被当成单侧属性、
--       补一条 `悬停 − 0` = 假差值「护甲 +144」（用户报障「护甲计算不对」）。
--
-- ★★★悬停识别为什么不用「替换 GameTooltip 的方法」：1.75.43 物品价三轮真机取证定稿 ——
--   **在本客户端替换 GameTooltip 的方法无效**（行为判据：一次都没跑到包装）。
--   ⇒ 走**客户端自己的按钮约定**（与 tools/ItemPrice.lua 同一套）：
--     ① 容器按钮 `ContainerFrameItemButton_OnEnter`（背包/银行）—— 包装全局处理体，零参数调原生，
--        再从全局 `this` 取按钮：`GetID()` = 格子号、父级 `GetID()` = 容器号；
--     ② **鼠标焦点路**：拾取行 `LootButtonN` / 任务奖励 `QuestRewardItemN`、`QuestProgressItemN`、
--        `QuestLogItemN` / 商人行 `MerchantItemN` —— 按 `GetMouseFocus()` 的帧名分派；
--     ③ ★**悬停态必须校验**：`EC.hb/hs` 是上一次容器悬留下来的状态 ⇒ 用 tooltip 首行名字核对，
--        对不上就交给焦点路（物品价真机教训：不校验会把上一个格子的信息写到别人提示里）。
--
-- ★纪律（照 CLAUDE.md 与 tools/ItemPrice.lua / tools/LootCursor.lua）：
--   · 载入期零副作用：顶层只声明 + 把渲染函数登记进 `EVAL_TB_MOD_ROWS`；不建帧/不挂事件/不读存档/不建计时器。
--   · 只调全局桥（一律**调用时读**）：`EVAL_L` / `EVAL_SAY` / `EVAL_SAY_FORCE` / `EVAL_TB_CFG` / `EVAL_HELP_CONFIG`。
--   · 关掉零动作：总开关 `tbCfg().equipCompare` 闸在一切探测/读写**之前**；关掉 = 摘包装（按身份比对还原）
--     + 摘 OnUpdate + 藏对比框。
--   · 包装纪律：先存旧的 → **零参数**调原生 → **按身份比对**还原（期间被别人套过的不许冲掉）。
--   · OnUpdate **零形参**（dt 只能从全局 `arg1` 取）；单一 0.15s 节拍，只为「换/离开悬停时收框」。
--   · 认不出就**什么都不显示**并如实记原因（查不到 ≠ 没有；绝不猜部位、绝不乱挂）。
--
-- ★★★两道「该不该比」的门（1.75.71 用户报障后加的；顺序即判据，都排在读回/建框**之前**）：
--   ① **类别门**（`ecClassOf`）：悬停那件必须**不是**已知的**非装备类**（消耗品/商品/任务/配方/容器/
--      弹药/钥匙…）才继续 —— 用户原话：「像绷带类型不要启用比较……只有装备,武器这些才开启」。
--      ★只拦「明确判成非装备」的；**判不出（nil）一律放行**（ruRU 等词表覆盖不到的语种不能被误杀）。
--   ② **另一侧有属性门**：当前装备那件读回来**一条可比数值行都没有**（衬衣/战袍这类）⇒ 这一格
--      不摆框（用户原话：「比较另一方无……属性类的时候就不应该开启比较」）；双戒指/双饰品**逐格判**。
--   · 取证口 = `/eh go 装备比较 物品`（**鼠标先停在物品上**）：把这件的 `GetItemInfo` 十个返回
--     逐个摊开 + ①②两道门的判定结论（离线测不到的东西，一条命令问清楚）；纯读、不改屏上状态。

local EC = {
  built = false,        -- 自建对比框是否已建（读值口）
  armed = false,        -- 总开关是否已生效（包装/计时器在跑）
  wrapped = false,      -- 容器按钮处理体是否已包装
  orig = nil, wrap = nil,
  tickF = nil, acc = 0, -- 节拍帧 / 累加器
  tickT0 = nil,         -- ★1.75.74 节拍的**时间基准**（arg1 不可用时用 GetTime 差值推 dt）
  tips = {},            -- 自建对比框（最多两个，首用才建）
  wornIdx = nil,        -- 本拍「已装备」那件的 键→数值（给左侧气泡染色当参照系）
  hostOwn = nil,        -- 客户端气泡**自己**的行数（我们追加汇总之前抓的；染色只染这几行）
  painted = 0,          -- 最近一次给左侧气泡染了几行
  subN = 0,             -- 最近一次给「子类名」汉化了几格（读值口）
  sumAppended = false,  -- 汇总段是否已追加进客户端气泡（★客户端重建后要补回）
  sumKey = nil,         -- 已追加的那一份汇总的内容键（显式标记：同键 + 无重建信号 ⇒ 不重写）
  sumList = nil,        -- 最近一次汇总的差值列表（诊断用）
  shown = {},           -- 本拍显示中的对比框
  hb = nil, hs = nil,   -- 最近一次容器悬停（bag/slot）
  cur = nil,            -- 当前已对比的物品 id（同一件不重画）
  tipName = nil,        -- 上一次气泡首行名字（变了 = 客户端重建/换物品 ⇒ 清汇总标记）
  hits = 0,             -- 成功显示对比的次数
  colored = 0,          -- 最近一次对比里被染色（更好=绿 / 更差=红）的行数
  deltas = 0,           -- 最近一次汇总里列了几条「有变化的同名行」
  why = nil,            -- 最近一次「没显示」的原因（诊断口 / 命令输出）
  last = nil,           -- 最近一次成功对比的描述（状态行）
  -- ★★★1.75.72b 只读取证环（cfg.ecProbe）的会话参数：★常量挂 EC 表上，**不新增文件级 local**
  --   （本项目定的：主 chunk 局部量有上限，而 harness 把「桩 + 模块 + 测试」拼成同一个 chunk）。
  probeMax = 40,        -- 环上限（条）
  noteGap = 2.0,        -- 同一形态的判决行最少间隔秒数（容器气泡每 0.2s 重建 ⇒ 不去抖 40 行 8 秒就满）
  noteKey = nil,        -- 上一条判决行原文（去重用）
  noteAt = 0,           -- 上一条判决行的时刻（GetTime）
  saidOrigErr = false,  -- 「原生处理体抛错」是否已上屏说过一次（防刷屏；其余只进取证环）
}

local EC_TICK = 0.15            -- 收框/换物品的节拍（只为「离开悬停」这类没有事件可挂的时刻）
local EC_GAP = 2                -- 对比框与主提示的间距
local EC_MAX_LINES = 30         -- 读回行数上限（NumLines 读不到时的兜底）
local EC_TIP_NAME = "EVAL_EC_CMP"
local ecSumHide                 -- ★前向声明（定义在 ecPlace 之后；ecHideAll 要用它）
local EC_HEAD_FALLBACK = nil    -- 见 ecHeading（客户端串读不到时用语言包的兜底）

-- ★★对比染色（用户定：「数值行对比染色：更好的绿、更差的红」）：
--   口径 = **同名行比数值**（标签 = 行内去掉所有数字后的文本 ⇒ 天然跨语言，不需要维护属性词表）：
--     · 对比框里的行与**主提示**（悬停那件）同名行比：更大 = 绿、更小 = 红、相同 = 原色、找不到同名 = 原色；
--     · ★物品名那行（第 1 行）**永远保留品质色**，从不参与染色；
--     · ★「越小越好」的标签（需要等级 / 武器速度…）走**反转**表（默认口径是越大越好）；
--     · ★「a / b」形态（耐久度 65 / 65）比的是**两者中较大的那个数**（比上限；客户端的当前值可能因破损偏低）。
local EC_UP_R, EC_UP_G, EC_UP_B = 0.25, 1.00, 0.30   -- 更好 = 绿
local EC_DN_R, EC_DN_G, EC_DN_B = 1.00, 0.35, 0.35   -- 更差 = 红
-- 「越小越好」的标签关键词（多语言；命中 ⇒ 绿/红反转）。左边是 hover 那件、右边是已装备那件，
--   比的是「谁更好」——例如「需要等级 10」（已装备）对「需要等级 16」（悬停）⇒ 10 更小 ⇒ 绿。
local EC_LOWER_BETTER = {
  "需要等级", "Requires Level", "Требуется",
  "速度", "Speed", "Скорость",
}
-- ★★**不参与比较**的标签（用户：「比较属性不需要比较: 等级,耐久」）——既**不染色**也不进汇总：
--   · 等级 = `需要等级`（**只匹配「需要等级」**，别写成裸「等级」：那会把「物品等级」也一起吞掉）；
--   · 耐久 = `耐久度`（只有上限/当前值，不是战斗属性）；
--   · 商人价 = 客户端自己加的钱行（`商人价 10s 22c` 这种，多数字行，比出来没有意义）。
local EC_SKIP_KEYS = {
  "需要等级", "Requires Level", "Требуется",
  "耐久", "Durability", "Прочность",
  "商人价", "Sell Price", "Цена",
}

----------------------------------------------------------------------
-- 全局桥（★一律调用时读，载入期不抓快照 —— 本项目老雷）
----------------------------------------------------------------------

local function ecConf()
  local t = rawget(_G, "EVAL_HELP_CONFIG")
  return (type(t) == "table") and t or nil
end

local function ecTb()
  if type(EVAL_TB_CFG) == "function" then return EVAL_TB_CFG() end
  return ecConf()
end

-- ★模块必须自带 L（走 EVAL_L）：项目里 L 一律是文件局部，裸调会绑全局 nil 并被 pcall 吞掉。
local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end
-- ★★★子类名汉化（1.75.61；用户报障：「分析工具->装备比较->内的装备类型能否翻译成中文.皮甲.布甲之类的.」）：
--   真机形态（用户截图）：本客户端 zhCN 下**物品子类串仍是英文**（「胸部  Mail」），而这一行**是客户端自己画的** ——
--   左边那栏是客户端气泡，右边那栏是我们读回后用 `AddLine` 重画（`ecFill` 里 `txt .. "  " .. ln.right` 那一句）⇒ 两处都要处理。
--   · 只认**整串**或「前缀 + 空格 + 行尾那一段」命中下表已知子类词的：命中才改，**其余文本一个字节都不碰**（绝不猜、绝不整行重写）；
--   · 值走三语 `L()`；★**拿不到就不动**（`L()` 回空串、或回的正是键名 —— 语言包缺键时的兜底 —— 一律返回 nil）
--     ⇒ 英文客户端取到的就是 `Mail`（与原文相同 ⇒ 我们不改），**绝不会把英文客户端改成中文**；
--   · 客户端每 1/5 秒重建气泡会把它复位 ⇒ 与染色同一个时机重贴（`ecUpdate` 每拍 + `ecFill` 每次填框）。
--   · 表里**只放英文原串**（客户端给的就是英文）；单/复数的不同写法作为**别名**指向同一个键。
--   ★★★1.75.61b：真机给的是**单数裸词**（用户第二张截图：「单手  Sword」「双手  Staff」）——
--     左列的部位前缀（单手/双手/胸部）**客户端自己已经本地化了**，右列只剩一个裸子类词 ⇒
--     裸词必须映射到**裸词译名**（`剑` / `法杖` / `锤` / `盾牌`），**不能**映射到 `单手剑` / `双手剑` 那一族词组键
--     （否则画出来是「单手  单手剑」= 我们自己造的重复）。⇒ 裸词一律走 `_B` 结尾的那一族键（B = bare）。
--     ★同理：**英文客户端的 `_B` 值必须是那一个裸词本身**（`Axe` 对 `Axe`）⇒ 命中后 `v == s` ⇒ 不改一个字节（零回归）。
local EC_SUB = {
  ["Cloth"] = "EC_SUB_CLOTH", ["Leather"] = "EC_SUB_LEATHER", ["Mail"] = "EC_SUB_MAIL", ["Plate"] = "EC_SUB_PLATE",
  ["Shield"] = "EC_SUB_SHIELD", ["Miscellaneous"] = "EC_SUB_MISC", ["Held In Off-hand"] = "EC_SUB_OFFHAND",
  ["One-Handed Axes"] = "EC_SUB_AXE1", ["One-Hand Axes"] = "EC_SUB_AXE1", ["One-Handed Axe"] = "EC_SUB_AXE1",
  ["Two-Handed Axes"] = "EC_SUB_AXE2", ["Two-Hand Axes"] = "EC_SUB_AXE2", ["Two-Handed Axe"] = "EC_SUB_AXE2",
  ["One-Handed Maces"] = "EC_SUB_MACE1", ["One-Hand Maces"] = "EC_SUB_MACE1", ["One-Handed Mace"] = "EC_SUB_MACE1",
  ["Two-Handed Maces"] = "EC_SUB_MACE2", ["Two-Hand Maces"] = "EC_SUB_MACE2", ["Two-Handed Mace"] = "EC_SUB_MACE2",
  ["One-Handed Swords"] = "EC_SUB_SWORD1", ["One-Hand Swords"] = "EC_SUB_SWORD1", ["One-Handed Sword"] = "EC_SUB_SWORD1",
  ["Two-Handed Swords"] = "EC_SUB_SWORD2", ["Two-Hand Swords"] = "EC_SUB_SWORD2", ["Two-Handed Sword"] = "EC_SUB_SWORD2",
  ["Daggers"] = "EC_SUB_DAGGER", ["Fist Weapons"] = "EC_SUB_FIST", ["Polearms"] = "EC_SUB_POLEARM",
  ["Staves"] = "EC_SUB_STAFF", ["Bows"] = "EC_SUB_BOW", ["Crossbows"] = "EC_SUB_CROSSBOW",
  ["Guns"] = "EC_SUB_GUN", ["Wands"] = "EC_SUB_WAND", ["Thrown"] = "EC_SUB_THROWN",
  ["Fishing Poles"] = "EC_SUB_FISHING", ["Relic"] = "EC_SUB_RELIC",
  -- ★裸词族（真机形态；覆盖全部装备子类：武器 / 护甲 / 副手 / 圣物 / 饰品）
  ["Sword"] = "EC_SUB_SWORD_B", ["Axe"] = "EC_SUB_AXE_B", ["Mace"] = "EC_SUB_MACE_B",
  ["Dagger"] = "EC_SUB_DAGGER_B", ["Staff"] = "EC_SUB_STAFF_B", ["Polearm"] = "EC_SUB_POLEARM_B",
  ["Fist Weapon"] = "EC_SUB_FIST_B", ["Bow"] = "EC_SUB_BOW_B", ["Crossbow"] = "EC_SUB_CROSSBOW_B",
  ["Gun"] = "EC_SUB_GUN_B", ["Wand"] = "EC_SUB_WAND_B", ["Fishing Pole"] = "EC_SUB_FISHING_B",
  ["Libram"] = "EC_SUB_LIBRAM_B", ["Idol"] = "EC_SUB_IDOL_B", ["Totem"] = "EC_SUB_TOTEM_B",
  ["Trinket"] = "EC_SUB_TRINKET_B",
}
-- 语言包取值；★回空串、或**回的正是键名**（缺键兜底）一律当「拿不到」⇒ nil（宁可不改，也不把键名画到气泡上）
local function ecSubText(key)
  local v = L(key)
  if type(v) ~= "string" or v == "" or v == key then return nil end
  return v
end
-- 命中才返回替换后的整串；否则 nil（调用方原样保留）。
-- ★两趟：① 整串就是子类词（右列单独一格）；② 「前缀 + 空格 + 行尾那一段」是子类词（并进一行之后的形态）。
local function ecSubTranslate(s)
  if type(s) ~= "string" or s == "" then return nil end
  local k = EC_SUB[s]
  if k then
    local v = ecSubText(k)
    if v and v ~= s then return v end
    return nil
  end
  local pos = 0
  while true do
    local sp = string.find(s, " ", pos + 1, true)
    if not sp then return nil end
    local tail = string.sub(s, sp + 1)
    local k2 = EC_SUB[tail]
    if k2 then
      local v = ecSubText(k2)
      if v and v ~= tail then return string.sub(s, 1, sp) .. v end
      return nil
    end
    pos = sp
  end
end

local function say(s)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(s)) end
end

-- 用户主动触发的读数：走常开出口（关掉「调试日志」也要看得见）
local function sayF(s)
  if type(EVAL_SAY_FORCE) == "function" then pcall(EVAL_SAY_FORCE, tostring(s))
  elseif type(EVAL_SAY) == "function" then pcall(EVAL_SAY, tostring(s)) end
end

-- 总开关真值（工具箱那一行的勾选框读写的就是它）
-- ★★★**默认开**（用户 1.75.45 定：「装备比较默认开启.」）⇒ 键为 nil 时**当场物化 true**（★绝不 `or true` —— 那会顶回用户显式关过的 false；1.75.47c 起 TargetBar 已移除，此写法以本文件为准）；
--   用户显式关过（false）永远是关 —— 读的时候绝不用 `or true` 顶回用户的选择。
function EVAL_EC_ENABLED()
  local tb = ecTb()
  if type(tb) ~= "table" then return false end
  if tb.equipCompare == nil then tb.equipCompare = true end
  return tb.equipCompare == true
end

function EVAL_EC_SET(v)
  local tb = ecTb()
  if type(tb) ~= "table" then return false end
  tb.equipCompare = v and true or false
  EVAL_EC_INSTALL()          -- ★全局函数：定义在下面，调用时才解析（不是 local ⇒ 没有前向声明老雷）
  return true
end

----------------------------------------------------------------------
-- 通用小工具
----------------------------------------------------------------------

-- 具名全局（一律调用时读）
local function ecFn(name)
  local v = rawget(_G, name)
  if type(v) == "function" then return v end
  return nil
end

local function ecTipObj()
  local t = rawget(_G, "GameTooltip")
  if not t then return nil end
  -- ★不强求 `type(t)=="table"`：本客户端帧是 table，但把「是不是能用的提示框」判在方法上更稳
  if type(t.IsShown) == "function" or type(t.SetOwner) == "function" then return t end
  return nil
end

local function ecLinkID(link)
  if type(link) ~= "string" then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  return tonumber(id)
end

local function ecLinkName(link)
  if type(link) ~= "string" then return nil end
  local nm = string.match(link, "%[(.-)%]")
  if type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

-- 名字归一（剥色码 + 去首尾空白）：只用来判「是不是同一件东西」
local function ecNameNorm(s)
  if type(s) ~= "string" then return nil end
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  s = string.gsub(s, "\n.*$", "")          -- 只取第一行（我们自己插过标题行的话）
  if s == "" then return nil end
  return s
end

local function ecTipShown()
  local tip = ecTipObj()
  if not tip or type(tip.IsShown) ~= "function" then return nil end
  local ok, s = pcall(tip.IsShown, tip)
  if not ok then return nil end
  return s and tip or nil
end

-- 主提示第一行 = 当前悬停物品的名字（★客户端读回的文本不含色码）
local function ecTipName()
  local fs = rawget(_G, "GameTooltipTextLeft1")
  if not fs or type(fs.GetText) ~= "function" then return nil end
  local ok, t = pcall(fs.GetText, fs)
  if ok and type(t) == "string" and t ~= "" then return t end
  return nil
end

local function ecHeading()
  local h = rawget(_G, "CURRENTLY_EQUIPPED")
  if type(h) == "string" and h ~= "" then return h end
  if EC_HEAD_FALLBACK == nil then EC_HEAD_FALLBACK = L("EC_EQUIPPED") end
  return EC_HEAD_FALLBACK
end

----------------------------------------------------------------------
-- 物品来源解析（悬停的是哪一件）
----------------------------------------------------------------------

local function ecSlots(bag)
  local fn = ecFn("GetContainerNumSlots")
  if not fn then return 0 end
  local ok, n = pcall(fn, bag)
  return (ok and tonumber(n)) or 0
end

local function ecSlotLink(bag, slot)
  local fn = ecFn("GetContainerItemLink")
  if not fn then return nil end
  local ok, link = pcall(fn, bag, slot)
  if ok and type(link) == "string" then return link end
  return nil
end

-- 按钮 → bag/slot：**只用客户端自己的约定**（客户端原生 ContainerFrameItemButton_OnEnter 也这么取）
local function ecBtnSlot(btn)
  if btn == nil then return nil end
  local sid = (btn.GetID) and btn:GetID() or nil
  local par = (btn.GetParent) and btn:GetParent() or nil
  local bid = (par and par.GetID) and par:GetID() or nil
  if type(sid) == "number" and type(bid) == "number" then return bid, sid end
  return nil
end

-- 任务奖励/任务日志里的物品：没有「焦点即第几个」的口 ⇒ 按 tooltip 首行名字在候选里反查
local function ecQuestFocus(name, inLog)
  local kinds = { "choice", "reward" }
  local k = 1
  while kinds[k] do
    local kind = kinds[k]
    local n = 0
    if inLog then
      if kind == "choice" then
        local f = ecFn("GetNumQuestLogChoices")
        if f then n = tonumber(f()) or 0 end
      else
        local f = ecFn("GetNumQuestLogRewards")
        if f then n = tonumber(f()) or 0 end
      end
    else
      if kind == "choice" then
        local f = ecFn("GetNumQuestChoices")
        if f then n = tonumber(f()) or 0 end
      else
        local f = ecFn("GetNumQuestRewards")
        if f then n = tonumber(f()) or 0 end
      end
    end
    local j = 1
    while j <= n do
      local nm2 = nil
      if inLog then
        if kind == "choice" then
          local f = ecFn("GetQuestLogChoiceInfo")
          if f then nm2 = f(j) end
        else
          local f = ecFn("GetQuestLogRewardInfo")
          if f then nm2 = f(j) end
        end
      else
        local f = ecFn("GetQuestItemInfo")
        if f then
          local ok, a = pcall(f, kind, j)   -- ★多返回值分开接（不套 tostring）
          if ok then nm2 = a end
        end
      end
      if nm2 == name then
        if inLog then
          local f = ecFn("GetQuestLogItemLink")
          if f then return f(kind, j) end
        else
          local f = ecFn("GetQuestItemLink")
          if f then return f(kind, j) end
        end
        return nil
      end
      j = j + 1
    end
    k = k + 1
  end
  return nil
end

-- 鼠标焦点路的物品链接（拾取行 / 任务奖励 / 商人行）；对不上就返回 nil（不猜）
local function ecFocusLink(tipName)
  if not tipName then return nil, nil end
  local gmf = ecFn("GetMouseFocus")
  if gmf then
    local okF, w = pcall(gmf)
    if okF and w ~= nil then
      local okN, nm = pcall(function() return w.GetName and w:GetName() end)
      if okN and type(nm) == "string" then
        -- ★★★1.75.74：先接住匹配结果、**非 nil 才转数字** —— 旧写法把 string.match 的结果直接
        --   喂给 tonumber，模式不匹配时就是 tonumber(nil) ⇒ 当场抛错（这条路径没有 pcall 兜着，
        --   悬停任何「具名但不是 LootButton」的帧都会炸掉整个更新 ⇒ 屏上两样都没有）。
        local lootN = string.match(nm, "^LootButton(%d+)$")
        if lootN then
          local i = tonumber(lootN)
          local f = ecFn("GetLootSlotLink")
          if f then
            local ok, link = pcall(f, i)
            if ok and type(link) == "string" then return link, "loot" end
          end
          return nil, nil
        end

        if string.match(nm, "^MerchantItemButton%d+$") or string.match(nm, "^MerchantItem%d+$") then
          local mN = string.match(nm, "(%d+)$")
          local j = mN and tonumber(mN) or nil
          local f = ecFn("GetMerchantItemLink")
          if j and f then
            local ok, link = pcall(f, j)
            if ok and type(link) == "string" then return link, "merchant" end
          end
          return nil, nil
        end

        local inLog = string.match(nm, "^QuestLogItem%d+$") ~= nil
        local inGiver = string.match(nm, "^QuestRewardItem%d+$") ~= nil
          or string.match(nm, "^QuestProgressItem%d+$") ~= nil
        if inLog or inGiver then return ecQuestFocus(tipName, inLog), "quest" end
      end
    end
  end
  -- ★★★1.75.74 **按名字兜底（不依赖 GetMouseFocus，也不依赖帧名）**：任务奖励页那个按钮的帧名
  --   在不同客户端/不同页面可能是 `QuestRewardItemN` / `QuestProgressItemN` / 别的名字，而
  --   `GetMouseFocus` 在本客户端**不可靠**（DragFrames 那边要自校准才敢采信）⇒ 焦点路认不出时，
  --   直接拿**气泡首行名字**去任务奖励（choice/reward）与任务日志（choice/reward）里找同名项，
  --   找到就用它的链接（`ecQuestFocus` 内部按名字匹配、拿不到就 nil，**绝不猜**）。
  --   非任务悬停（背包 / 技能 / NPC）在这里扫到空表即返回，代价可忽略。
  local link = ecQuestFocus(tipName, false)
  if link then return link, "questname" end
  link = ecQuestFocus(tipName, true)
  if link then return link, "questlogname" end
  return nil, nil
end

-- 当前悬停的是哪一件：① 容器按钮（校验首行名）② 焦点路；都拿不到 ⇒ nil（不猜）
local function ecHoverID()
  local tipName = ecNameNorm(ecTipName())

  local b, s = EC.hb, EC.hs
  if b and s then
    local link = ecSlotLink(b, s)
    local id, linkName = ecLinkID(link), ecNameNorm(ecLinkName(link))
    -- ★必须与主提示首行一致：hb/hs 是**上一次**容器悬停留下的状态，玩家随后可能悬停在别的窗口上
    if id and linkName and tipName and linkName == tipName then
      return id, "bag"
    end
  end

  local link, src = ecFocusLink(tipName)
  local id, linkName = ecLinkID(link), ecNameNorm(ecLinkName(link))
  if id and (tipName == nil or linkName == nil or linkName == tipName) then
    return id, src or "focus"
  end
  return nil, nil
end

----------------------------------------------------------------------
-- 部位判定：INVTYPE token → 部位名 → 槽号
----------------------------------------------------------------------

-- ★键是**字面量字符串**（不是客户端的 `INVTYPE_*` 全局常量）—— 那批常量万一缺一个，
--   `t[INVTYPE_X] = ...` 会直接「table index is nil」把整个文件打挂（本项目语法/载入闸门都照不到）。
local EC_SLOTS = {
  INVTYPE_HEAD = { "HeadSlot" },
  INVTYPE_NECK = { "NeckSlot" },
  INVTYPE_SHOULDER = { "ShoulderSlot" },
  INVTYPE_BODY = { "ShirtSlot" },
  INVTYPE_CHEST = { "ChestSlot" },
  INVTYPE_ROBE = { "ChestSlot" },
  INVTYPE_WAIST = { "WaistSlot" },
  INVTYPE_LEGS = { "LegsSlot" },
  INVTYPE_FEET = { "FeetSlot" },
  INVTYPE_WRIST = { "WristSlot" },
  INVTYPE_HAND = { "HandsSlot" },
  INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
  INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
  INVTYPE_CLOAK = { "BackSlot" },
  INVTYPE_WEAPON = { "MainHandSlot" },
  INVTYPE_2HWEAPON = { "MainHandSlot" },
  INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
  INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
  INVTYPE_SHIELD = { "SecondaryHandSlot" },
  INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
  INVTYPE_RANGED = { "RangedSlot" },
  INVTYPE_RANGEDRIGHT = { "RangedSlot" },
  INVTYPE_THROWN = { "RangedSlot" },
  INVTYPE_RELIC = { "RangedSlot" },
  INVTYPE_TABARD = { "TabardSlot" },
}

-- ★槽号兜底表（`GetInventorySlotInfo` 万一不可用）：vanilla 装备栏位号 ——
--   与 TurtleWoW 参考插件 EQCompare 的 `CMP_INV_SLOT` 逐条一致（1 头 / 5 胸 / 11,12 手指 /
--   13,14 饰品 / 15 披风 / 16,17 主副手 / 18 远程 / 19 徽章），出处可查、不是猜的。
local EC_SLOT_ID = {
  HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5,
  WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
  Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
  BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
  TabardSlot = 19,
}

-- 兜底：主提示里找本地化的部位行（EQCompare 的做法 —— tooltip 第 2~5 行的文本就是 INVTYPE 常量的值）
local EC_LOC_TOKENS = {
  "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST",
  "INVTYPE_ROBE", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST",
  "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_CLOAK", "INVTYPE_WEAPON",
  "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD",
  "INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN",
  "INVTYPE_RELIC", "INVTYPE_TABARD",
}

local function ecLocFromTip(host)
  if not host or type(host.GetName) ~= "function" then return nil end
  local okN, nm = pcall(host.GetName, host)
  if not okN or type(nm) ~= "string" or nm == "" then return nil end
  for row = 2, 6 do
    local fs = rawget(_G, nm .. "TextLeft" .. row)
    if fs and type(fs.GetText) == "function" then
      local okT, t = pcall(fs.GetText, fs)
      local line = okT and ecNameNorm(t) or nil
      if line then
        for k = 1, table.getn(EC_LOC_TOKENS) do
          local tok = EC_LOC_TOKENS[k]
          local v = rawget(_G, tok)
          if type(v) == "string" and v ~= "" and ecNameNorm(v) == line then return tok end
        end
      end
    end
  end
  return nil
end

local function ecSlotIDByName(name)
  local f = ecFn("GetInventorySlotInfo")
  if f then
    local ok, id = pcall(f, name)
    if ok and type(id) == "number" then return id end
  end
  return EC_SLOT_ID[name]
end

----------------------------------------------------------------------
-- 「这件东西能不能比较」= 只认装备类（★第一道门）
----------------------------------------------------------------------

-- ★★★用户报障：「像绷带类型不要启用比较……只有装备,武器这些才开启装备比较」。
--   绷带/药水/材料这类**非装备**也弹对比框 = 纯噪声（弹出来只有个名字 + 一件它对应的装备）。
--   口径三条（每条都是踩过的坑换来的）：
--     ① **按词判、不按下标判** —— `GetItemInfo` 的多返回值位置在各客户端/文档里有出入
--        （本仓库两处记录就不一致：IconGrid 用「第 6 返回 = 类型」，doc/物品价 记的是「第 5 = 类型」）
--        ⇒ 一律**扫一遍它的字符串返回**（跳过 ①物品名 ②链接 ⑨贴图），命中哪个词算哪个；
--        ★**名字绝不能扫**（「任务：xxx 之剑」这类装备名里含「任务」⇒ 会把真装备误杀）。
--     ② **认不出 ≠ 非装备** —— 只有**命中非装备类词**才拦；两张词表都命中时**装备优先**；
--        都没命中 ⇒ 返回 nil = 判不出 ⇒ **放行**（继续走下面的装备槽/部位行那条既有路）。
--        ★这条是给别人用的：ruRU 的「Доспехи / Оружие」不在词表里，绝不能因此把装备也拦掉。
--     ③ 词表**只收类名**（不收子类）；英文串大小写不敏感；`trade goods` 这种多词也按子串匹配。
local EC_CLASS_EQUIP = { "护甲", "武器", "盔甲", "Armor", "Weapon" }
local EC_CLASS_OTHER = {
  "消耗品", "商品", "贸易品", "任务", "配方", "图样", "设计图", "结构图", "容器",
  "箭矢", "弹药", "钥匙", "杂物", "其它",
  "Consumable", "Trade Goods", "Trade", "Quest", "Recipe", "Pattern", "Schematic",
  "Container", "Projectile", "Key", "Miscellaneous", "Misc", "Reagent", "Quiver",
}

local function ecWordHit(s, words)
  local low = string.lower(tostring(s or ""))
  if low == "" then return nil end
  local i = 1
  while i <= table.getn(words) do
    local w = words[i]
    if type(w) == "string" and w ~= "" and string.find(low, string.lower(w), 1, true) then return w end
    i = i + 1
  end
  return nil
end

-- 返回 "equip" / "other" / nil（判不出）；第 2 个返回 = 命中的那个词（取证口用）
local function ecClassOf(id)
  local infoFn = ecFn("GetItemInfo")
  if not infoFn or not id then return nil, nil end
  local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9 = pcall(infoFn, id)
  if not ok then return nil, nil end
  local rets = { a3, a4, a5, a6, a7, a8 }
  local text, seen = "", {}
  local i = 1
  while i <= table.getn(rets) do
    local v = rets[i]
    -- ★跳过与 ①名字 ②链接 ⑨贴图 **逐字相同**的串（贴图名如 `INV_Misc_Bandage_08` 里含 `Misc`）
    if type(v) == "string" and v ~= "" and v ~= a1 and v ~= a2 and v ~= a9 and not seen[v] then
      seen[v] = true
      text = text .. " " .. v
    end
    i = i + 1
  end
  if text == "" then return nil, nil end
  local eq = ecWordHit(text, EC_CLASS_EQUIP)
  if eq then return "equip", eq end
  local ot = ecWordHit(text, EC_CLASS_OTHER)
  if ot then return "other", ot end
  return nil, nil
end

----------------------------------------------------------------------
-- 自建对比框（首用才建；关掉只 Hide，不销毁）
----------------------------------------------------------------------

local function ecTipFrame(idx, host)
  if EC.tips[idx] then return EC.tips[idx] end
  local create = ecFn("CreateFrame")
  if not create then return nil end
  local name = EC_TIP_NAME .. tostring(idx)
  local ok, f = pcall(create, "GameTooltip", name, UIParent, "GameTooltipTemplate")
  if not ok or not f then
    ok, f = pcall(create, "GameTooltip", name, UIParent)   -- 模板名万一不认 ⇒ 退回无模板
    if not ok or not f then return nil end
  end
  if host and type(host.GetFrameStrata) == "function" then
    local okS, strata = pcall(host.GetFrameStrata, host)
    if okS and strata then pcall(f.SetFrameStrata, f, strata) end
  end
  EC.tips[idx] = f
  EC.built = true
  return f
end

local function ecHideAll()
  local i = 1
  while i <= table.getn(EC.shown) do
    local f = EC.shown[i]
    if f then pcall(f.Hide, f) end
    i = i + 1
  end
  EC.shown = {}
  -- ★汇总框（锚在**左侧未装备气泡**下方那个）跟着一起收
  --   ★前向声明：ecSumHide 定义在后面（本项目的「先用后声明 = 绑全局 nil」老雷 ⇒ 顶部先 `local ecSumHide`）
  if ecSumHide then ecSumHide() end
end
-- 读回刚填好的行（★限制在 NumLines 之内：行数之外还留着**上一次**的旧文本，本项目已定案）
local function ecReadLines(name)
  local tip = rawget(_G, name)
  local count = EC_MAX_LINES
  if tip and type(tip.NumLines) == "function" then
    local okN, n = pcall(tip.NumLines, tip)
    if okN and type(n) == "number" and n > 0 then count = n end
  end
  local lines = {}
  local row = 1
  while row <= count do
    local left = rawget(_G, name .. "TextLeft" .. row)
    local text, r, g, b = nil, 1, 1, 1
    if left and type(left.GetText) == "function" then
      local okT, t = pcall(left.GetText, left)
      if okT and type(t) == "string" and t ~= "" then
        text = t
        if type(left.GetTextColor) == "function" then
          local okC, cr, cg, cb = pcall(left.GetTextColor, left)
          if okC and cr then r, g, b = cr, cg, cb end
        end
      end
    end
    if text then
      local right = rawget(_G, name .. "TextRight" .. row)
      local rt = nil
      if right and type(right.GetText) == "function" then
        local okR, t2 = pcall(right.GetText, right)
        if okR and type(t2) == "string" and t2 ~= "" then rt = t2 end
      end
      table.insert(lines, { text = text, right = rt, r = r, g = g, b = b })
    end
    row = row + 1
  end
  return lines
end

-- ★★★换填对比框之前 / 读回之后，把**左右两侧**的 FontString 全部抹空（1..EC_MAX_LINES）。
--   真机形态（用户报障「装备上而不是武器信息,里面的速度是哪来的?」）：客户端换填时**只写它自己那几行**
--   的 FontString，上一件（比如武器）写在**右栏**的「速度 2.70」既不会被冲掉、`ClearLines` 也收不走
--   ⇒ ① 读回时会被并进护甲那一行（框里冒出一条别的物品的字段）、② 或者留在框里继续显示。两处都靠这一遍抹平。
--   ★左栏一起抹：行数之外还留着上一次的旧文本（本来就靠 NumLines 限制），抹了更干净。
--   ★只抹**我们自建的对比框**，一个字节都不碰客户端自己的气泡。
local function ecTipWipe(name)
  local row = 1
  while row <= EC_MAX_LINES do
    local l = rawget(_G, name .. "TextLeft" .. row)
    if l and type(l.SetText) == "function" then pcall(l.SetText, l, "") end
    local r = rawget(_G, name .. "TextRight" .. row)
    if r and type(r.SetText) == "function" then pcall(r.SetText, r, "") end
    row = row + 1
  end
end

-- ===== 对比染色：把一行拆成「标签键 + 数值」 =====
-- 标签键 = 行内**所有数字都换成 #** 后的文本（归一空白）⇒ 两侧同名行天然对上，**不需要维护属性词表**
--   （「428点护甲」与「328点护甲」都归一成「#点护甲」；「+2 力量」与「+3 力量」都归一成「+# 力量」）。
-- 数值 = 行内第一个数字；★含「/」的行（耐久度 65 / 65 这种 a / b）取**两者中较大的**（比上限 ——
--   已装备那件可能正带着破损，拿当前值比会假报「更差」）。
local function ecLineKey(text)
  if type(text) ~= "string" or text == "" then return nil, nil end
  local nums, i = {}, 1
  while true do
    local s, e = string.find(text, "%d+%.?%d*", i)
    if not s then break end
    local v = tonumber(string.sub(text, s, e))
    if v then nums[table.getn(nums) + 1] = v end
    i = e + 1
  end
  local n = table.getn(nums)
  if n == 0 then return nil, nil end
  local v = nums[1]
  if n > 1 and string.find(text, "/", 1, true) then
    local k = 1
    while k <= n do
      if nums[k] > v then v = nums[k] end
      k = k + 1
    end
  end
  local key = string.gsub(text, "%d+%.?%d*", "#")
  key = string.gsub(key, "%s+", " ")
  key = string.gsub(key, "^%s+", "")
  key = string.gsub(key, "%s+$", "")
  return key, v
end

-- 主提示（悬停那件）的行索引：返回 ①标签键→数值（同名取第一条）②**按行序**的 {key, v} 列表
--   ★要那份行序列表是为了「**只在一侧出现**的属性」：悬停件有 +3 耐力、当前装备没有 ⇒ 也要能进汇总
--   （用户报「有些属性丢失比较，没显示耐力的差值」）。
local function ecHostIndex(host)
  local idx, order = {}, {}
  if not host or type(host.GetName) ~= "function" then return idx, order end
  local okN, nm = pcall(host.GetName, host)
  if not okN or type(nm) ~= "string" or nm == "" then return idx, order end
  local lines = ecReadLines(nm)
  local i = 1
  while i <= table.getn(lines) do
    local key, v = ecLineKey(lines[i].text)
    if key then
      if idx[key] == nil then
        idx[key] = v
        order[table.getn(order) + 1] = { key = key, v = v }
      end
    end
    i = i + 1
  end
  return idx, order
end

local function ecLowerBetter(key)
  local i = 1
  while i <= table.getn(EC_LOWER_BETTER) do
    local kw = EC_LOWER_BETTER[i]
    if kw and kw ~= "" and string.find(key, kw, 1, true) then return true end
    i = i + 1
  end
  return false
end

-- ★这一条标签是不是「不参与比较」（见 EC_SKIP_KEYS：等级 / 耐久 / 商人价）
local function ecSkipKey(key)
  if type(key) ~= "string" or key == "" then return true end
  local i = 1
  while i <= table.getn(EC_SKIP_KEYS) do
    local kw = EC_SKIP_KEYS[i]
    if kw and kw ~= "" and string.find(key, kw, 1, true) then return true end
    i = i + 1
  end
  return false
end

-- 汇总行用的标签：把归一里的 `#` 去掉、收拾空格与落单的符号（`+# 力量` → `力量` · `耐久度 # / #` → `耐久度`）
--   ★★还要剥掉**量词**：本客户端护甲行是 `144点护甲` ⇒ 去数字后剩 `点护甲`；汇总里要写 **`护甲`**
--   （用户明确：「护甲的描述就是护甲,而不是点护甲」）。只剥**开头**的量词，剥完为空就不剥（保险）。
local function ecLabelOf(key)
  local s = tostring(key or "")
  s = string.gsub(s, "#", "")
  s = string.gsub(s, "[%+%-]%s*$", "")
  s = string.gsub(s, "[/%s]+$", "")
  s = string.gsub(s, "%s+", " ")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "^[%+%-]%s*", "")
  s = string.gsub(s, "%s+$", "")
  local bare = string.gsub(s, "^点%s*", "")     -- 量词「点」（144**点**护甲 / 12**点**格挡…）
  if bare ~= "" then s = bare end
  if s == "" then return "?" end
  return s
end

-- 读回行的品质色：★★本客户端**读回的物品名那行颜色不可信**（用户报「当前装备的稀有度标题没有染色」——
--   实测读回来是白的，客户端是在绘制时才按品质上色）⇒ 名字行一律**用 GetItemQualityColor(quality) 现算**，
--   拿不到才退回读回色。wornID 由调用方（ecShow）从已装备那件的 link 解出来。
local function ecQualityRGB(id)
  local infoFn = ecFn("GetItemInfo")
  local qcFn = ecFn("GetItemQualityColor")
  if not infoFn or not qcFn or not id then return nil end
  local okI, _, _, q = pcall(infoFn, id)          -- ★多返回值分开接：第 3 返回 = quality
  if not okI or type(q) ~= "number" then return nil end
  local okC, cr, cg, cb = pcall(qcFn, q)
  if okC and type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
    return cr, cg, cb
  end
  return nil
end

-- 填一个对比框：SetInventoryItem → 读回 → 插「已装备」标题 → **逐行对比染色** → 重画。
--   hostIdx = 主提示的行索引（ecHostIndex 第 1 返回）· nameR/G/B = 名字行的品质色（nil = 用读回色）
--   **返回：true, deltas**（deltas = 这个框里「有变化的行」的 {key, d} 列表，交给 ecShow 汇总）
local function ecFill(idx, slotId, host, hostIdx, nameR, nameG, nameB)
  local tip = ecTipFrame(idx, host)
  if not tip then EC.why = "no compare frame" return false end
  if type(tip.SetInventoryItem) ~= "function" then EC.why = "no SetInventoryItem" return false end
  local okOwn = pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
  if not okOwn then EC.why = "SetOwner failed" return false end
  local name = EC_TIP_NAME .. tostring(idx)
  -- ★★换填**之前**先抹掉左右两栏（ClearLines 收不走上一件的右栏字段 —— 见 ecTipWipe 的注释）
  ecTipWipe(name)
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  local okSet = pcall(tip.SetInventoryItem, tip, "player", slotId)
  if not okSet then EC.why = "SetInventoryItem failed" return false end
  local lines = ecReadLines(name)
  if table.getn(lines) == 0 then EC.why = "empty compare lines" return false end
  ecTipWipe(name)
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.AddLine, tip, tostring(ecHeading()), 1, 0.82, 0.30)
  local colored, deltas, keys = 0, {}, {}
  local i = 1
  while i <= table.getn(lines) do
    local ln = lines[i]
    local txt, r, g, b = ln.text, ln.r, ln.g, ln.b
    if ln.right then txt = txt .. "  " .. ln.right end
    -- ★子类名汉化（本客户端右列的子类串仍是英文：真机截图「胸部  Mail」）⇒ 命中才换，其余原样
    local subTxt = ecSubTranslate(txt)
    if subTxt then txt = subTxt end
    -- ★第 1 行是物品名 ⇒ 保留**品质色**（不参与对比染色）；品质色现算，读回色只当兜底
    if i == 1 and type(nameR) == "number" then
      r, g, b = nameR, nameG, nameB
    end
    if i > 1 and type(hostIdx) == "table" then
      local key, v = ecLineKey(ln.text)
      -- ★★不参与比较的标签（等级 / 耐久 / 商人价）：**既不染色也不进汇总**（用户明确定）
      if key and ecSkipKey(key) then key, v = nil, nil end
      if key and v then
        -- ★记进「已装备那件」的键→数值：左侧气泡（未装备那件）染色要拿它当参照系
        if EC.wornIdx then EC.wornIdx[key] = v end
        -- ★★★**凡是「两边都读过」的键都要交出去**（不是只交有变化的那些）：
        --   漏了它 ⇒「两侧数值相同」的属性会在第二趟被当成「只在一侧出现」再补一条 `悬停 − 0`
        --   —— 用户报障「护甲计算不对」的真凶：护甲 144 对 144，汇总却写着「护甲 +144」。
        keys[table.getn(keys) + 1] = key
        -- ★只在一侧出现的属性也要能比：悬停件没有这一行 ⇒ 按 0 算（换装后就丢了这一项）
        local vRef = hostIdx[key]
        if vRef == nil then vRef = 0 end
        if v ~= vRef then
          local better = (v > vRef)
          if ecLowerBetter(key) then better = (v < vRef) end
          if better then r, g, b = EC_UP_R, EC_UP_G, EC_UP_B
          else r, g, b = EC_DN_R, EC_DN_G, EC_DN_B end
          colored = colored + 1
          -- ★汇总用：**只收真有变化的**（用户定「只列变化的行」）；方向 = 悬停 − 已装备
          --   （= 换上这件之后这一项会变成多少 ⇒ 屏幕上的「+」= 更好那一侧的方向由 ecLowerBetter 定色）
          deltas[table.getn(deltas) + 1] = { key = key, d = vRef - v }
        end
      end
    end
    pcall(tip.AddLine, tip, txt, r, g, b)
    i = i + 1
  end
  EC.colored = colored
  -- ★汇总**不写在这个框里**（用户要求改到左侧「未装备」那栏下面）⇒ 只把差值交出去
  --   第 3 个返回 = **两边比过的全部键**（给 ecShow 标「见过」，防同值属性被当成单侧属性）
  return true, deltas, keys
end

-- ★★★汇总段 = **直接追加进客户端那个气泡**（用户：「不是独立的框.而是合并到未装备信息栏内」）。
--   手法与「物品价」的价格行**完全同源**、同一客户端已验证：`GameTooltip:AddLine` 是**追加**，不动客户端
--   自己的行（只是往末尾加我们这几行）。
--   ★★必须处理「客户端每 1/5 秒重建自己的气泡」——重建会把我们追加的行冲掉 ⇒ 用**显式标记 + 重建信号**：
--     · `EC.sumKey` = 我们刚追加的是哪一份（悬停 id + 条目拼串）⇒ 相同且**没收到重建信号**就一拍都不重写；
--     · 重建信号① = 我们的容器按钮包装**又被调用**（客户端每 1/5 秒重建时会再调一次那个全局）；
--     · 重建信号② = 气泡**首行名字变了**。两处都清标记 ⇒ 下一拍（0.15s）自动补回。
--   ★绝不用「搜我们那行文本」去重：行数之外还留着上一次的旧文本（本项目已定案的老坑）。
ecSumHide = function()
  -- 标记清零（下一拍如有悬停会重新染色 + 重新追加）；行本身归客户端的气泡管
  EC.sumKey, EC.sumAppended, EC.hostOwn = nil, false, nil
end

-- ★★★1.75.72b 只读取证环（`cfg.ecProbe`，有界 `EC.probeMax` 行）—— 用户报障「某些情况下装备比较
--   会让**客户端气泡 + 我们的对比框两样都不显示**」时，**唯一能事后判读的证据**。要判的就是两条：
--     ① 「原生 OnEnter 抛错」= 机制①：包装被中断（客户端气泡填不出来 + 我们后面的更新一行都不跑）；
--     ② 「两边都写着在（shown=1）但 vis=0」= 机制②：`IsShown` 只报**自己那个标志**，父级被隐藏时它
--        照样是 true ⇒ 必须看 `IsVisible`；本客户端开全屏地图会隐藏 `UIParent`，而客户端自己的
--        `GameTooltip` 与我们的对比框**都是 UIParent 子件** ⇒ 两边一起不渲染（本项目在案）。
--   ★为什么每个字都要自存一份：`say` 只进聊天框、**不落日志环**，存档又只在 /reload 落盘 ⇒
--     不自存我这边一个字节都读不到（同 lcProbe / atkProbe / selProbe 的教训）。
--   ★只在开关开着时写（关掉零动作 —— 不给没在用这个功能的玩家留残渣）。
--   ★★判决行要**去抖**：容器气泡每 0.2s 重建一次，会一遍遍喊我们 ⇒ 同一形态的行 `EC.noteGap` 秒内
--     只记一条（否则 40 行的环 8 秒就满、真正那一拍反被冲掉）。
--   ★唯一写口：本文件里写 `cfg.ecProbe` 的**只有这一个函数**（漏一处就少一条证据，同 wAtkTrace 的纪律）。
local function ecDiag(tag)
  local cfg = ecConf()
  if type(cfg) ~= "table" then return end
  local tip = ecTipObj()
  -- 「真的看得见吗」：只认 `IsVisible`（读不到就如实写 `?`，绝不拿 IsShown 冒充）
  local function vis(o)
    local f = o
    if type(f) ~= "table" and type(f) ~= "userdata" then return "?" end
    if type(f.IsVisible) ~= "function" then return "?" end
    local ok, v = pcall(f.IsVisible, f)
    if not ok then return "?" end
    return v and "1" or "0"
  end
  local line = string.format("%s%s｜id=%s｜why=%s｜框=%d｜气泡 shown=%s vis=%s｜UIParent vis=%s",
    ((type(date) == "function") and (date("%H:%M:%S") .. " ") or ""),
    tostring(tag), tostring(EC.cur), tostring(EC.why), table.getn(EC.shown),
    (ecTipShown() and "1" or "0"), vis(tip), vis(rawget(_G, "UIParent")))
  local now = ((type(GetTime) == "function") and GetTime()) or 0
  -- ★★★1.75.74：去抖键**绝不能含时间戳** —— 旧写法拿整行（含 `%H:%M:%S`）当键 ⇒ 时间戳每秒都变
  --   ⇒ 同一形态的行每秒都算「新」 ⇒ 40 行的环被容器悬停刷爆（真机实测累计 **3354 条**，
  --   真正那一拍（任务奖励页）**被冲掉** = 取证断链，本轮白绕一轮的直接原因）。
  local key = tostring(tag) .. "|" .. tostring(EC.cur) .. "|" .. tostring(EC.why)
    .. "|" .. tostring(table.getn(EC.shown))
  if EC.noteKey == key and (now - (tonumber(EC.noteAt) or 0)) < EC.noteGap then return end
  EC.noteKey, EC.noteAt = key, now
  local box = cfg.ecProbe
  if type(box) ~= "table" then box = {} cfg.ecProbe = box end
  if type(box.out) ~= "table" then box.out = {} end
  table.insert(box.out, line)
  while table.getn(box.out) > EC.probeMax do table.remove(box.out, 1) end
  box.n = (tonumber(box.n) or 0) + 1
  box.t = line
end

-- 客户端气泡**自己**的行数（我们追加汇总之前抓；染色只染这几行，别染到自己追加的汇总行）
local function ecNumLines(host)
  if not host or type(host.NumLines) ~= "function" then return EC_MAX_LINES end
  local ok, n = pcall(host.NumLines, host)
  if ok and type(n) == "number" and n > 0 then return n end
  return EC_MAX_LINES
end

-- ★★★给**左侧（未装备那件）气泡自己的行**按差异染色（用户：「差异的染色也在未装备的信息内处理」）：
--   口径与右侧那栏**对称**：左侧那行显示的是**悬停件**的值 ⇒ 悬停更好 = 绿、更差 = 红；
--   两侧都排除等级/耐久/商人价；★第 1 行（物品名）永不染；★只染到 `own` 行（客户端自己的行），
--   不碰我们自己追加的汇总段。颜色是**改客户端的 FontString**，客户端重建后会复位 ⇒ 靠同一套标记补回。
local function ecHostPaint(host, wornIdx, own)
  if not host or type(wornIdx) ~= "table" or type(host.GetName) ~= "function" then return 0 end
  local okN, nm = pcall(host.GetName, host)
  if not okN or type(nm) ~= "string" or nm == "" then return 0 end
  local painted, row = 0, 2          -- ★从第 2 行起（第 1 行是物品名）
  while row <= own do
    local fs = rawget(_G, nm .. "TextLeft" .. row)
    if fs and type(fs.GetText) == "function" and type(fs.SetTextColor) == "function" then
      local okT, t = pcall(fs.GetText, fs)
      if okT and type(t) == "string" and t ~= "" then
        local key, vRef = ecLineKey(t)
        if key and vRef and not ecSkipKey(key) then
          local v = wornIdx[key]
          if v == nil then v = 0 end          -- 当前装备没有这一项 ⇒ 按 0（换上就多了这一项）
          if vRef ~= v then
            local better = (vRef > v)
            if ecLowerBetter(key) then better = (vRef < v) end
            if better then pcall(fs.SetTextColor, fs, EC_UP_R, EC_UP_G, EC_UP_B)
            else pcall(fs.SetTextColor, fs, EC_DN_R, EC_DN_G, EC_DN_B) end
            painted = painted + 1
          end
        end
      end
    end
    row = row + 1
  end
  return painted
end


-- ★★★把**某个气泡**的左右两列 FontString 就地汉化（只命中已知子类词才 `SetText`，其余一个字节都不碰）。
--   ★为什么每拍都跑：客户端每 1/5 秒重建自己的气泡 ⇒ 汉化会被复位，靠与染色同一个时机重贴；
--     两个重建信号（容器按钮包装又被调 / 首行名字变了）都会走到 `ecUpdate`，挂在那里最稳。
--   ★只扫客户端**自己**的行（`EC.hostOwn`；还没抓到时按当前行数）—— 我们追加的汇总行是我们自己写的，不碰。
local function ecSubPaintHost(host)
  if not host or type(host.GetName) ~= "function" then return 0 end
  local okN, nm = pcall(host.GetName, host)
  if not okN or type(nm) ~= "string" or nm == "" then return 0 end
  local own = EC.hostOwn or ecNumLines(host)
  local painted, row = 0, 1
  while row <= own do
    local side = 0
    while side < 2 do
      local fs = rawget(_G, nm .. (side == 0 and "TextLeft" or "TextRight") .. row)
      if fs and type(fs.GetText) == "function" and type(fs.SetText) == "function" then
        local okT, t = pcall(fs.GetText, fs)
        if okT and type(t) == "string" and t ~= "" then
          local v = ecSubTranslate(t)
          if v then
            pcall(fs.SetText, fs, v)
            painted = painted + 1
          end
        end
      end
      side = side + 1
    end
    row = row + 1
  end
  EC.subN = painted
  return painted
end

-- 往客户端气泡末尾追加汇总。deltas = {{key=, d=}, ...}（d = 悬停 − 已装备）
local function ecSumShow(host, deltas)
  if not host or type(host.AddLine) ~= "function" then ecSumHide() return false end
  local n = table.getn(deltas)
  -- 组装文本（同一份内容 ⇒ 同一个 key ⇒ 不重复追加）
  local out, key = {}, tostring(EC.cur) .. "|" .. tostring(n)
  local k = 1
  while k <= n do
    local d = deltas[k]
    local sign = (d.d > 0) and "+" or "-"
    local txt = ecLabelOf(d.key) .. " " .. sign .. tostring(math.abs(d.d))
    out[table.getn(out) + 1] = { txt = txt, d = d.d, key = d.key }
    key = key .. "|" .. txt
    k = k + 1
  end
  if EC.sumKey == key then return true end      -- 已处理且没收到重建信号 ⇒ 不重写
  -- ★先给客户端气泡**自己的行**按差异染色（追加汇总之前抓它自己的行数）
  if EC.hostOwn == nil then EC.hostOwn = ecNumLines(host) end
  EC.painted = ecHostPaint(host, EC.wornIdx, EC.hostOwn)
  pcall(host.AddLine, host, L("EC_SUM_HEAD"), 0.62, 0.62, 0.62)
  if n == 0 then
    pcall(host.AddLine, host, L("EC_SUM_NONE"), 0.62, 0.62, 0.62)
  else
    k = 1
    while k <= table.getn(out) do
      local it = out[k]
      -- 颜色 = 「换装后这项变好还是变差」：越大越好 ⇒ +为绿；越小越好 ⇒ +为红
      local better = (it.d > 0)
      if ecLowerBetter(it.key) then better = (it.d < 0) end
      if better then
        pcall(host.AddLine, host, it.txt, EC_UP_R, EC_UP_G, EC_UP_B)
      else
        pcall(host.AddLine, host, it.txt, EC_DN_R, EC_DN_G, EC_DN_B)
      end
      k = k + 1
    end
  end
  EC.sumKey, EC.sumAppended = key, true
  pcall(host.Show, host)     -- 追加后让客户端重新排版（高度会变）
  return true
end

-- 摆位：默认贴主提示右侧；右侧越界就整组翻到左侧（几何一律现算 + 读回自证口径）
local function ecPlace(host)
  -- ★★★1.75.74：定位基准用**调用方传来的那个 host**（= `ecTipShown()` 判定为「显示中」的气泡），
  --   不再自己 `ecTipObj()`（写死 GameTooltip）—— 两者不一致时会**锚到一个不可见的气泡上**
  --   （框 Show 了却摆到屏外/不可见处 = 用户眼里的"没框"）。拿不到就**如实记一行**，绝不静默放弃。
  local tip = host or ecTipObj()
  if not tip then ecDiag("⚠定位拿不到气泡（跳过摆位）") return end
  local okR, hostRight = pcall(tip.GetRight, tip)
  local okU = UIParent and type(UIParent.GetRight) == "function"
  local parentRight = nil
  if okU then
    local okP, pr = pcall(UIParent.GetRight, UIParent)
    if okP then parentRight = pr end
  end
  local width = 0
  local i = 1
  while i <= table.getn(EC.shown) do
    local f = EC.shown[i]
    if f and type(f.GetWidth) == "function" then
      local okW, w = pcall(f.GetWidth, f)
      if okW and type(w) == "number" then width = width + w + EC_GAP end
    end
    i = i + 1
  end
  local toLeft = false
  if okR and type(hostRight) == "number" and parentRight and (hostRight + width > parentRight) then
    toLeft = true
  end
  local prev = tip
  i = 1
  while i <= table.getn(EC.shown) do
    local f = EC.shown[i]
    if f then
      pcall(f.ClearAllPoints, f)
      if toLeft then
        pcall(f.SetPoint, f, "TOPRIGHT", prev, "TOPLEFT", -EC_GAP, 0)
      else
        pcall(f.SetPoint, f, "TOPLEFT", prev, "TOPRIGHT", EC_GAP, 0)
      end
      prev = f
    end
    i = i + 1
  end
end

-- 显示某一件的对照（认不出部位 / 没有已装备件 ⇒ 一个框都不显示，并如实记原因）
local function ecShow(host, id)
  ecHideAll()
  -- ★★★1.75.72b：本件的「汇总差值表」在**进门第一件事**就作废 ——
  --   `ecUpdate` 是在调本函数**之前**就写了 `EC.cur = id`，而 `EC.sumList` 只在下面
  --   `EC.sumList = all` 那一行赋值 ⇒ 「类别门 / 装备槽空串 / 部位认不出」这几条**早退路**
  --   会把**上一件的差值表**留在 `EC.sumList` 里；下一拍走 `id == EC.cur` 的快捷路
  --   （`if EC.sumKey == nil and EC.sumList then ecSumShow(host, EC.sumList) end`）⇒
  --   把上一件的「换装后」汇总画到**这一件的客户端气泡**上（用户在别的物品上看到别人的差值）。
  --   ★不动 `EC.cur`：留着它才能避免「被拦的物品每 0.15s 重跑一遍整条判定」。
  EC.sumList = nil
  local infoFn = ecFn("GetItemInfo")
  local wornFn = ecFn("GetInventoryItemLink")
  if not infoFn then EC.why = "no GetItemInfo" ecDiag("⚠拿不到 API") return false end
  if not wornFn then EC.why = "no GetInventoryItemLink" ecDiag("⚠拿不到 API") return false end

  -- ★★★第一道门：**只比较装备类**（用户：「只有装备,武器这些.才开启装备比较」）。
  --   判不出（nil）⇒ 放行 —— 认不出 ≠ 非装备（别人的客户端/别的语种词表里没有时不能拦）。
  local cls, clsWord = ecClassOf(id)
  if cls == "other" then
    EC.why = "not equip class(" .. tostring(clsWord) .. ")"
    ecDiag("①类别门拦下（命中词 " .. tostring(clsWord) .. "）")
    return false
  end

  local equipLoc = nil
  local _, _, _, _, _, _, _, loc = infoFn(id)     -- ★第 8 返回 = INVTYPE token（多返回值分开接）
  if type(loc) == "string" then equipLoc = loc end
  -- ★官方 wiki 明文：非装备类物品这一位是**空串**（不是 nil）⇒ 直接如实说「不是装备」，别再去找部位行
  if equipLoc == "" then
    EC.why = "not equipment"
    ecDiag("②装备槽空串（不是装备）")
    return false
  end

  -- ① 先按 token 查表（★token 认不出时再退「主提示里的本地化部位行」，两步都是实测口径）
  local names = equipLoc and EC_SLOTS[equipLoc] or nil
  if not names then
    local loc2 = ecLocFromTip(host)
    if loc2 then names = EC_SLOTS[loc2] end
    if names and not equipLoc then equipLoc = loc2 end
  end
  if not names then
    EC.why = "unknown slot (" .. tostring(equipLoc) .. ")"
    ecDiag("③部位认不出")
    return false
  end

  -- ★对比染色的参照系 = **主提示那份行索引**（悬停那件）；取不到就整框原色（绝不错染）
  local hostIdx, hostOrder = ecHostIndex(host)
  EC.wornIdx, EC.hostOwn = {}, nil      -- 本拍的「已装备键→数值」与「气泡自己行数」都重新抓

  local shown, firstSlot, all, seenKey, cmpKey = {}, nil, {}, {}, {}
  local wornNoAttr = 0
  local i = 1
  while i <= table.getn(names) do
    local slotId = ecSlotIDByName(names[i])
    if slotId then
      local okL, wornLink = pcall(wornFn, "player", slotId)
      -- ★「这一格穿着东西」判**链接本身**，不判我们解析出来的 id：
      --   链接形态万一解析不出数字（自定义/变体），按 id 判会**静默跳过比较**（本模块的冒烟就抓到过这一条）。
      local wornID = okL and ecLinkID(wornLink) or nil
      local same = (wornID ~= nil and wornID == id)   -- ★悬停的就是这一格穿的那件 ⇒ 比它自己没意义
      if okL and type(wornLink) == "string" and wornLink ~= "" and not same then
        -- ★名字行的品质色**现算**（读回色不可信，用户报「稀有度标题没染色」）
        local qr, qg, qb = ecQualityRGB(wornID)
        local okF, dl, ks = ecFill(table.getn(shown) + 1, slotId, host, hostIdx, qr, qg, qb)
        -- ★★★第二道门（用户：「比较另一方无……属性类的时候就不应该开启比较」）：
        --   这一格穿的那件**一条可比的属性都没有**（读回来的行里除了 需要等级/耐久度/商人价
        --   以外一个数值行都没有 —— 衬衣/战袍这类）⇒ **这一格不摆框**：摆出来只有个名字，
        --   外加一堆「悬停件 − 0」的假差值，比不摆更糟。★双戒指/双饰品是**逐格判**的：
        --   一格没属性只收那一格，另一格照常比。
        if okF and table.getn(ks) == 0 then
          wornNoAttr = wornNoAttr + 1
          okF = false
        end
        if okF then
          table.insert(shown, EC.tips[table.getn(shown) + 1])
          if not firstSlot then firstSlot = names[i] end
          -- 汇总候选：双戒指/双饰品两个框的差值合并（同名键只取第一条）
          local j = 1
          while j <= table.getn(dl) do
            local it = dl[j]
            if it and it.key and not seenKey[it.key] then
              seenKey[it.key] = true
              all[table.getn(all) + 1] = it
            end
            j = j + 1
          end
          -- ★★★再把「**两边都比过**的键」全部标成见过 —— **不只是有变化的那些**
          --   （只标有变化的 ⇒「两侧数值相同」的属性（护甲 144 对 144）会在下面第二趟被当成
          --    「只在一侧出现」再补一条 `悬停 − 0` = 「护甲 +144」；用户报障「护甲计算不对」即此）
          local m = 1
          while m <= table.getn(ks) do
            if ks[m] then cmpKey[ks[m]] = true end
            m = m + 1
          end
        end
      end
    end
    i = i + 1
  end

  -- ★★只出现在**悬停那件**上的属性（当前装备这一栏里根本没有这一行）：差 = 悬停值 − 0
  --   —— 用户报「有些属性丢失比较，没显示耐力的差值」就是这一支（+3 耐力在对面，这边整行都不存在）。
  --   ★★前提 = **对比框里一次都没读到过这个键**（`cmpKey` 由上面那一趟**全量**标记：同值行也算「见过」）。
  local j2 = 1
  while j2 <= table.getn(hostOrder) do
    local it = hostOrder[j2]
    if it and it.key and not cmpKey[it.key] and not ecSkipKey(it.key) and it.v and it.v ~= 0 then
      seenKey[it.key] = true
      all[table.getn(all) + 1] = { key = it.key, d = it.v }
    end
    j2 = j2 + 1
  end
  EC.deltas = table.getn(all)
  EC.sumList = all

  if table.getn(shown) == 0 then
    -- 该部位没穿东西（正常情况，不是错误）；★穿了东西但**一条属性都没有** = 另一回事，分开如实报
    EC.why = (wornNoAttr > 0) and "worn no attrs" or "nothing equipped"
    ecDiag("④一个框都没摆（另一侧没穿 / 没属性）")
    return false
  end
  EC.shown = shown
  local k = 1
  while k <= table.getn(EC.shown) do
    local f = EC.shown[k]
    if f then pcall(f.Show, f) end
    k = k + 1
  end
  ecPlace(host)
  -- ★汇总写到**左侧未装备气泡下面**（用户要求从右侧搬过来）
  if type(hostIdx) == "table" then ecSumShow(host, all) end
  EC.hits = EC.hits + 1
  EC.last = L("EC_HIT", tostring(id), tostring(firstSlot or equipLoc))
  -- ★★★1.75.74：成功 ⇒ **当场清 why**。旧写法只在「没显示」的各分支写 why、成功时不复位 ⇒
  --   状态行与探针的「上次结论 why=」会一直挂着**上一次失败的原因**（本轮真机就把它当成
  --   "当前结论"、白绕一轮；且与「✅摆框成功」自相矛盾）。
  EC.why = nil
  -- ★★★1.75.72b：成功这一拍也记一行 —— 它是取证环里的**对照基线**：
  --   读存档时要能分清「这一拍本来就该有框（却 vis=0 = 机制②）」与「这一拍被门拦了」。
  ecDiag("✅摆框成功")
  return true
end

-- 节拍/事件共用的更新口：force = 容器按钮刚被调（客户端重建提示时补一次）
local function ecUpdate(force)
  if not EC.armed then return false end
  local host = ecTipShown()
  if not host then
    -- ★★1.75.72b「刚才两样都在、这一刻都没了」的**边沿**：上一拍我们还在摆框（`EC.shown` 非空）
    --   ⇒ 记一行判决（机制②的证据就在这一行：`shown=1` 而 `vis=0`，或 `UIParent vis=0`）。
    --   ★先记再收（`ecHideAll` 会把 `EC.shown` 清空 —— 顺序反了这行就永远是「框=0」）。
    if table.getn(EC.shown) > 0 then ecDiag("★气泡消失（上一拍我们还在摆框）") end
    ecHideAll()
    EC.cur, EC.why = nil, "no tooltip"
    return false
  end
  ecSubPaintHost(host)                 -- ★子类名汉化（客户端重建会复位 ⇒ 每拍重贴；命中才写）
  -- ★重建信号②：气泡**首行名字变了**（客户端换物品/重建）⇒ 清汇总标记，允许补写一次
  local nmNow = ecNameNorm(ecTipName())
  if nmNow ~= EC.tipName then
    EC.tipName = nmNow
    EC.sumKey = nil
  end
  local id = ecHoverID()
  if not id then
    ecHideAll()
    EC.cur, EC.why = nil, "unresolved hover"
    return false
  end
  if (not force) and id == EC.cur then
    -- ★客户端重建过（标记被清）⇒ 只把**汇总**补回气泡，不必重算对比框（省一遍读回/重画）
    if EC.sumKey == nil and EC.sumList then ecSumShow(host, EC.sumList) end
    return true
  end
  EC.cur = id
  return ecShow(host, id)
end

----------------------------------------------------------------------
-- 包装 / 节拍（关掉零动作：探测全在这个门之后）
----------------------------------------------------------------------

local function ecHookButtons()
  if EC.wrapped then return true end
  local orig = rawget(_G, "ContainerFrameItemButton_OnEnter")
  if type(orig) ~= "function" then
    EC.why = "no ContainerFrameItemButton_OnEnter"
    return false
  end
  local wrap = function()
    -- ★★★1.75.72b：原生处理体**必须 pcall**（用户报障「客户端气泡 + 我们的对比框两样都不显示」的第一嫌疑）。
    --   它是**客户端气泡唯一的填充口**：不套 pcall ⇒ 它一抛错就把整个包装中断
    --   （客户端气泡填不出来 + 我们后面的更新一行都不跑 ⇒ 屏上两样都没有）。
    --   ★同族：ItemPrice 挂的是同一个全局（谁后挂谁是外层）⇒ 它那一层抛错会顺着**我们这一次调用**
    --     冒上来，所以必须由我们兜住；★兜住之后**如实记一行**（绝不静默），并只上屏说一次（防刷屏）。
    local okOrig, errOrig = true, nil
    if type(orig) == "function" then okOrig, errOrig = pcall(orig) end
    if not EC.armed then return end                 -- 关掉零动作（连取证环也不写 —— 不留残渣）
    if not okOrig then
      ecDiag("★原生 OnEnter 抛错：" .. tostring(errOrig))
      if not EC.saidOrigErr then
        EC.saidOrigErr = true
        sayF("装备比较：客户端原生的容器悬停处理体抛错了（已兜住，不再中断后续更新）："
          .. tostring(errOrig) .. "｜同类只进取证环：/eh go 装备比较 记录")
      end
    end
    local btn = rawget(_G, "this")
    local b, s = ecBtnSlot(btn)
    if b and s then EC.hb, EC.hs = b, s end
    -- ★重建信号①：容器按钮每 1/5 秒重建气泡时会**再调一次这个全局** ⇒ 当场清汇总标记，允许补写一次
    --   （客户端重建会连带把我们追加的汇总行冲掉；标记不清就会以为「已经写过」而不再补）
    EC.sumKey = nil
    ecUpdate(true)
    -- ★★1.75.72b「该出气泡却两样都没有」的判决点：客户端刚喊过我们（= 它正要显示气泡），
    --   若这一刻客户端气泡**根本没显示** ⇒ 记一行（含 UIParent 可见性 —— 机制②的判决证据）。
    if not ecTipShown() then ecDiag("★两样都不在（客户端气泡没显示）") end
  end
  rawset(_G, "ContainerFrameItemButton_OnEnter", wrap)
  if rawget(_G, "ContainerFrameItemButton_OnEnter") == wrap then   -- 读回自证
    EC.orig, EC.wrap, EC.wrapped = orig, wrap, true
    return true
  end
  return false
end

local function ecUnhookButtons()
  if not EC.wrapped then return false end
  local cur = rawget(_G, "ContainerFrameItemButton_OnEnter")
  if cur == EC.wrap then
    rawset(_G, "ContainerFrameItemButton_OnEnter", EC.orig)
  else
    -- 期间被别人套过 ⇒ **不冲掉别人的**，如实说一句
    say(L("EC_UNHOOK_BUSY"))
  end
  EC.orig, EC.wrap, EC.wrapped = nil, nil, false
  return true
end

-- ★★★1.75.72b：挂节拍必须**幂等重挂**（本项目「关断路径四件事 · 节拍停止」那条的正面要求）——
--   `ecTickOff` 是**真摘** `OnUpdate`（`SetScript(..., nil)`），而它**不清 `EC.tickF`**
--   （1.12 没有销毁帧的 API ⇒ 帧留着复用）⇒ 旧写法开头那句「`EC.tickF` 还在就 `return true`」
--   会让**关一次再打开**之后节拍**永远不再跑**：容器路因为包装还在、看着「像好的」，
--   而**焦点路**（拾取行 / 任务奖励 / 商人行）的悬停与离开收框全靠这一拍 ⇒ 全哑。
--   ★handler 只建一份、存在 `EC.tickH` 上（**不新增文件级 local**：主 chunk 局部量有上限）。
local function ecTickOn()
  if not EC.tickF then
    local create = ecFn("CreateFrame")
    if not create then return false end
    local ok, f = pcall(create, "Frame")
    if not ok or not f then return false end
    EC.tickF = f
    -- ★★★1.75.74：逻辑帧也**显式 Show** —— OnUpdate 只对「显示中」的帧回调（本项目在案：
    --   挂在被隐藏的父级下的帧会**停摆**，例：开图隐藏 UIParent）。这个帧没有尺寸/贴图，
    --   Show 不画任何东西；不 Show 的代价是「焦点路整条哑、而画面与"本来就没框"一模一样」。
    pcall(f.Show, f)
    EC.tickH = function()
      -- ★零形参：dt 从全局 arg1 取（本客户端 OnUpdate 回调一个参数都不传）
      if not EC.armed then return end
      -- ★★★1.75.74：**dt 不再只认 arg1**。旧写法 `tonumber(arg1) or 0` ⇒ 本客户端若不给全局
      --   `arg1`，`acc` 永远是 0 ⇒ 这一拍**一次都不调 ecUpdate** ⇒ 焦点路（任务奖励 / 拾取行 /
      --   商人行）全哑，而容器悬停走包装、看着「像好的」（用户报障「任务奖励页不出对比框」即此）。
      --   现在：arg1 合理就直接用；否则拿 GetTime 差值兜底（全项目其它节拍一律 `or 0.05` 兜底）。
      local now = ((type(GetTime) == "function") and GetTime()) or nil
      local dt = tonumber(rawget(_G, "arg1"))
      if (not dt) or dt <= 0 or dt > 0.5 then
        dt = (now and EC.tickT0 and (now - EC.tickT0)) or 0.05
      end
      if now then EC.tickT0 = now end
      if dt <= 0 then dt = 0.05 end
      if dt > 0.5 then dt = 0.5 end
      EC.acc = (EC.acc or 0) + dt
      if EC.acc >= EC_TICK then
        EC.acc = 0
        ecUpdate(false)
      end
    end
  end
  if not EC.tickH then return false end
  -- ★幂等重挂：每次「要挂」都真挂一遍（判据 = 开回来立刻有节拍、不用 /reload）
  pcall(EC.tickF.SetScript, EC.tickF, "OnUpdate", EC.tickH)
  return true
end

local function ecTickOff()
  if EC.tickF then pcall(EC.tickF.SetScript, EC.tickF, "OnUpdate", nil) end
end

-- 总武装/解除
function EVAL_EC_INSTALL()
  local on = EVAL_EC_ENABLED()
  if on then
    if EC.armed then return true end
    EC.armed = true
    ecHookButtons()
    ecTickOn()
    return true
  end
  EC.armed = false
  ecUnhookButtons()
  ecTickOff()
  ecHideAll()
  EC.hb, EC.hs, EC.cur, EC.acc = nil, nil, nil, 0
  return false
end

----------------------------------------------------------------------
-- 命令体（宿主 /eh 链只留一行分派过来）/ 读值口
----------------------------------------------------------------------

local function ecApiLine()
  local names = {
    "GetItemInfo", "GetInventorySlotInfo", "GetInventoryItemLink",
    "GetContainerItemLink", "ContainerFrameItemButton_OnEnter",
    "GetMouseFocus", "GetLootSlotLink", "GetMerchantItemLink", "GetQuestItemLink",
  }
  local out = {}
  local i = 1
  while i <= table.getn(names) do
    local n = names[i]
    local has = (type(rawget(_G, n)) == "function") and "有" or "**无**"
    table.insert(out, n .. "=" .. has)
    i = i + 1
  end
  local head = rawget(_G, "CURRENTLY_EQUIPPED")
  table.insert(out, "CURRENTLY_EQUIPPED=" .. ((type(head) == "string" and head ~= "") and head or "**无**"))
  return table.concat(out, " · ")
end

-- 对比框自身的 API（自建帧上验，不是全局）
local function ecFrameApiLine()
  local f = EC.tips[1] or EC.tips[2]
  if not f then
    local create = ecFn("CreateFrame")
    if create then
      local ok, nf = pcall(create, "GameTooltip", EC_TIP_NAME .. "0", UIParent)
      if ok and nf then
        EC.tips[0] = nf
        f = nf
        EC.built = true
      end
    end
  end
  if not f then return "对比框：**建不出来**（CreateFrame/GameTooltip 不可用）" end
  local fun = { "SetInventoryItem", "SetOwner", "ClearLines", "AddLine", "NumLines", "GetText" }
  local out = {}
  local i = 1
  while i <= table.getn(fun) do
    local n = fun[i]
    table.insert(out, n .. "=" .. ((type(f[n]) == "function") and "有" or "**无**"))
    i = i + 1
  end
  return "对比框：" .. table.concat(out, " · ")
end

-- ★★取证：把一个提示帧的**每一行原样摊开**（左栏 + 右栏 + 是否越界）——
--   专治「框里冒出一条不属于这件物品的字段」这类报障（例如护甲框里出现「速度 2.70」）：
--   一眼能看出那条是**读回来的**（在我们 AddLine 的行里）还是**客户端/别人的帧**画的。
--   ★行数之外（row > NumLines）也照扫：本项目的定案 —— 行数之外还留着上一次的旧文本。
local function ecDumpLines(title, name)
  if type(name) ~= "string" or name == "" then
    sayF(title .. "：拿不到帧名")
    return
  end
  local tip = rawget(_G, name)
  if not tip then
    sayF(title .. "（" .. name .. "）：不存在")
    return
  end
  local n = 0
  local okN, nn = pcall(tip.NumLines, tip)
  if okN and type(nn) == "number" then n = nn end
  local shown = "?"
  if type(tip.IsShown) == "function" then
    local okS, s = pcall(tip.IsShown, tip)
    if okS then shown = tostring(s) end
  end
  sayF(title .. "（" .. name .. "）：NumLines=" .. tostring(n) .. " · IsShown=" .. shown)
  local row, any = 1, false
  while row <= EC_MAX_LINES do
    local l = rawget(_G, name .. "TextLeft" .. row)
    local r = rawget(_G, name .. "TextRight" .. row)
    local lt, rt = "", ""
    if l and type(l.GetText) == "function" then
      local ok, t = pcall(l.GetText, l)
      if ok and type(t) == "string" then lt = t end
    end
    if r and type(r.GetText) == "function" then
      local ok, t = pcall(r.GetText, r)
      if ok and type(t) == "string" then rt = t end
    end
    if lt ~= "" or rt ~= "" then
      any = true
      sayF("  " .. tostring(row) .. (row > n and "★越界" or "") .. " 左[" .. lt .. "] 右[" .. rt .. "]")
    end
    row = row + 1
  end
  if not any then sayF("  （这个帧一行文本都没有）") end
end

-- 顺手列出**屏上还有哪些提示帧**（自建对比框之外的：客户端自带的对照气泡 / 别的插件的提示）——
--   ★索引守卫：只收 `GetObjectType()=="Frame"` 的对象（不可索引的 userdata 会抛错并打断整个探针）。
local function ecDumpOtherTips()
  local n = 0
  local okAll = pcall(function()
    for k, v in pairs(_G) do
      if n < 12 and type(k) == "string" and type(v) == "table" and type(v.GetObjectType) == "function"
        and string.find(k, "Tooltip", 1, true) and not string.find(k, EC_TIP_NAME, 1, true) then
        local okO, ot = pcall(v.GetObjectType, v)
        if okO and ot == "Frame" then
          local okS, sh = pcall(v.IsShown, v)
          if okS and sh then
            local cnt = 0
            local okC, c = pcall(v.NumLines, v)
            if okC and type(c) == "number" then cnt = c end
            local first = ""
            local fs = rawget(_G, k .. "TextLeft1")
            if fs and type(fs.GetText) == "function" then
              local okT, t = pcall(fs.GetText, fs)
              if okT and type(t) == "string" then first = t end
            end
            n = n + 1
            sayF("  屏上提示帧：" .. k .. " · 行=" .. tostring(cnt) .. " · 首行[" .. first .. "]")
          end
        end
      end
    end
  end)
  if not okAll then sayF("  （全局扫描中断：有对象不可索引 ⇒ 已跳过）") end
  if n == 0 then sayF("  （没有别的提示帧在显示）") end
end

-- ★★★取证口（**一条命令、纯读**）：把「鼠标停着的那件」的 `GetItemInfo` **逐个返回**原样摊开 +
--   我们两道门的判定结论。用途 = 真机排查「为什么这东西也弹框 / 为什么不弹框」：
--   非装备类词到底报在哪个位置、装备槽是不是空串、另一侧有没有可比属性 —— 离线全测不到。
--   ★用法：**先把鼠标停在物品上**，气泡还在屏上时敲 `/eh go 装备比较 物品`。
local function ecItemProbe()
  sayF("— 装备比较 · 物品判定 —")
  local host = ecTipShown()
  local id = ecHoverID()
  sayF("悬停解析：id=" .. tostring(id) .. " · 气泡首行=" .. tostring(ecTipName() or "-")
    .. " · 上次结论 why=" .. tostring(EC.why or "-"))
  if not id then
    sayF("（没解析出物品：先把鼠标停在物品上、气泡还在屏上时敲这条命令）")
    return
  end
  local infoFn = ecFn("GetItemInfo")
  if not infoFn then sayF("GetItemInfo：**无**") return end
  local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = pcall(infoFn, id)
  if not ok then sayF("GetItemInfo 调用失败（pcall 抛错）") return end
  local rets = { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 }
  local i = 1
  while i <= 10 do
    local v = rets[i]
    if v ~= nil then
      local t = type(v)
      sayF("  #" .. tostring(i) .. " [" .. t .. "] " .. ((t == "string") and v or tostring(v)))
    end
    i = i + 1
  end
  local cls, cw = ecClassOf(id)
  sayF("① 类别门：" .. ((cls == nil) and "**判不出**（放行 —— 继续走装备槽/部位行那条路）"
    or ((cls == "equip") and ("装备类（命中「" .. tostring(cw) .. "」）⇒ 放行")
      or ("**非装备类**（命中「" .. tostring(cw) .. "」）⇒ **不比较**（why=not equip class）"))))
  local equipLoc = (type(a8) == "string" and a8 ~= "") and a8 or nil
  local names = equipLoc and EC_SLOTS[equipLoc] or nil
  sayF("② 装备槽：#8=" .. (equipLoc or "**空串/非串**")
    .. " · 查表=" .. (names and names[1] or "认不出")
    .. " · 气泡部位行=" .. tostring(ecLocFromTip(host) or "-"))
  if not names then
    local loc2 = ecLocFromTip(host)
    names = loc2 and EC_SLOTS[loc2] or nil
  end
  if not names then
    sayF("⇒ 结论：**不比较**（部位认不出）")
    return
  end
  local wornFn = ecFn("GetInventoryItemLink")
  local slotId = ecSlotIDByName(names[1])
  local wornLink = nil
  if wornFn and slotId then
    local okL, w = pcall(wornFn, "player", slotId)
    if okL then wornLink = w end
  end
  local wornID = ecLinkID(wornLink)
  local wcls, wcw = ecClassOf(wornID)
  sayF("③ 另一侧：" .. names[1] .. "（槽 " .. tostring(slotId) .. "）· 当前装备=" .. tostring(wornLink or "**没穿**")
    .. " · 它的类别=" .. tostring(wcls or "判不出") .. (wcw and ("（命中「" .. tostring(wcw) .. "」）") or ""))
  if type(wornLink) == "string" and wornLink ~= "" then
    -- 另一侧「有没有可比属性」：真填一次**探针框（0 号）**再读回来，读完**当场收掉**
    --   ★填框会顺手写 `EC.wornIdx`/`EC.colored`（那是屏幕那套的状态）⇒ 探针**先存后还**，
    --     绝不因为敲了一次体检命令就把屏上的染色参照系改掉。
    local keepWorn, keepColored = EC.wornIdx, EC.colored
    local idx = ecHostIndex(host)
    local probeName = EC_TIP_NAME .. "0"
    local okF, dl, ks = ecFill(0, slotId, host, idx, nil, nil, nil)
    sayF("④ 另一侧可比属性：读回行=" .. tostring(table.getn(ecReadLines(probeName)))
      .. " · 可比键=" .. tostring(okF and table.getn(ks) or "**填框失败**")
      .. " ⇒ " .. ((okF and table.getn(ks) > 0) and "会摆框" or "**这一格不摆框**（why=worn no attrs）"))
    EC.wornIdx, EC.colored = keepWorn, keepColored
    local f = EC.tips[0]
    if f then
      pcall(f.Hide, f)
      if type(f.ClearLines) == "function" then pcall(f.ClearLines, f) end
    end
  else
    sayF("④ 另一侧没穿东西 ⇒ **不摆框**（why=nothing equipped）")
  end
end

local function ecStatusLine()
  return L("EC_STATE",
    EVAL_EC_ENABLED() and L("EC_ON") or L("EC_OFF"),
    EC.wrapped and "已挂" or "未挂",
    EC.built and "已建" or "未建",
    tostring(EC.hits),
    tostring(EC.last or "-"))
end

-- ★★★1.75.72b 取证环的**唯一读口**（命令与真机取证都走它；`记录` 分支不解析中文文本）
--   ★为什么要有它：用户报障是「某些情况下**两样都不显示**」，而那一拍现场只能靠**存档里的判决行**复原。
--   返回 = { n = 累计条数, out = {…最新在后…}, last = 最后一条 }
function EVAL_EC_PROBE()
  local cfg = ecConf()
  local box = (type(cfg) == "table") and cfg.ecProbe or nil
  local out = (type(box) == "table" and type(box.out) == "table") and box.out or {}
  local n = table.getn(out)
  return { n = (type(box) == "table") and tonumber(box.n) or 0, lines = n, max = EC.probeMax,
    last = (n > 0) and out[n] or nil, out = out }
end

local function ecProbeOut(k)
  local p = EVAL_EC_PROBE()
  local out = p.out
  local n = table.getn(out)
  local take = tonumber(k) or 8
  if take < 1 then take = 1 end
  if take > n then take = n end
  sayF("— 装备比较 · 取证环（共记 " .. tostring(p.n) .. " 条 · 现存 " .. tostring(n)
    .. " / 上限 " .. tostring(p.max) .. " · 最新在后）—")
  if n == 0 then
    sayF("（环是空的：要么开关关着、要么这一版还没悬停过装备 —— 复现之后再来读）")
    return
  end
  local i = n - take + 1
  while i <= n do
    sayF("  " .. tostring(out[i]))
    i = i + 1
  end
  sayF("判读：①`原生 OnEnter 抛错` ⇒ 机制①（包装被中断）；②`框=1` 而 `vis=0` 或 `UIParent vis=0`"
    .. " ⇒ 机制②（父级被隐藏，两边一起不渲染）；③`①类别门拦下（命中词 …）` ⇒ 认成非装备被拦（看那个词对不对）")
end

function EVAL_EC_CMD(msg)
  local m = tostring(msg or "")
  if string.find(m, "开", 1, true) and not string.find(m, "关", 1, true) then
    EVAL_EC_SET(true)
    sayF(L("EC_ON") .. " · " .. ecStatusLine())
    return true
  end
  if string.find(m, "关", 1, true) then
    EVAL_EC_SET(false)
    sayF(L("EC_OFF"))
    return true
  end
  if string.find(m, "记录", 1, true) or string.find(m, "log", 1, true) then
    -- 取证环：把最近 N 条判决行原样打出来（默认 8 条；纯读，不动任何状态）
    -- ★★★1.75.74：先接住匹配结果再转数字 —— 旧写法在**不带条数**时（`装备比较 记录`）是
    --   `tonumber(nil)` ⇒ 命令当场抛错（本该回落到默认 8 条）。同一个潜伏形态见 ecFocusLink。
    local nStr = string.match(m, "(%d+)")
    ecProbeOut(nStr and tonumber(nStr) or nil)
    return true
  end
  if string.find(m, "dump", 1, true) or string.find(m, "行", 1, true) then
    -- 取证：把两边气泡的每一行原样摊开（先**把鼠标停在物品上**，气泡还在屏上时敲命令）
    sayF("— 装备比较 · 行摊开 —")
    local host = ecTipShown()
    if host and type(host.GetName) == "function" then
      local okN, nm = pcall(host.GetName, host)
      ecDumpLines("主气泡（悬停那件）", (okN and type(nm) == "string") and nm or "")
    else
      sayF("主气泡：现在没有显示中的提示（先把鼠标停在物品上，再敲这条命令）")
    end
    ecDumpLines("对比框1（当前装备）", EC_TIP_NAME .. "1")
    ecDumpLines("对比框2（当前装备）", EC_TIP_NAME .. "2")
    ecDumpOtherTips()
    return true
  end
  if string.find(m, "物品", 1, true) then
    -- 取证：把悬停那件的 GetItemInfo 十个返回 + 两道门的判定摊开（鼠标先停在物品上）
    ecItemProbe()
    return true
  end
  if string.find(m, "测", 1, true) then
    -- 手动跑一次（不用等悬停；用于确认「包装/识别/填框」哪一段没通）
    local ok = ecUpdate(true)
    sayF((ok and "手动更新：显示了对照" or ("手动更新：没显示 —— " .. tostring(EC.why or "?"))))
    return true
  end
  -- 默认 = 状态 + API 体检（缺哪个如实报）
  sayF("— 装备比较 —")
  sayF(ecStatusLine())
  sayF("最近一次：cur=" .. tostring(EC.cur) .. " · why=" .. tostring(EC.why or "-")
    .. " · 悬停格=" .. tostring(EC.hb) .. "/" .. tostring(EC.hs)
    .. " · 染色行=" .. tostring(EC.colored) .. "（更好=绿 · 更差=红）")
  sayF("全局 API：" .. ecApiLine())
  sayF(ecFrameApiLine())
  -- ★★★1.75.74：**「节拍挂没挂」必须能读** —— 焦点路（任务奖励 / 拾取行 / 商人行）的悬停与
  --   离开收框**全靠这一拍**，而它没挂上时画面与「本来就不该有框」长得**一模一样**
  --   （本轮真机白绕一轮的原因）。判据 = 直接问帧 `GetScript("OnUpdate")` 有没有 handler。
  do
    local att = "?"
    if EC.tickF and type(EC.tickF.GetScript) == "function" then
      local okG, h = pcall(EC.tickF.GetScript, EC.tickF, "OnUpdate")
      if okG then att = (h and "**挂**" or "**真摘**") end
    end
    sayF("节拍：" .. att .. " ｜ armed=" .. tostring(EC.armed) .. " · 包装=" .. tostring(EC.wrapped)
      .. " · acc=" .. string.format("%.2f", tonumber(EC.acc) or 0)
      .. " · 累积计入=" .. tostring(EC.hits))
  end
  -- ★★★「某些情况下两样都不显示」的常驻判决：状态里**必须**带环的最后一条（不用另敲命令就能看一眼）
  do
    local p = EVAL_EC_PROBE()
    sayF("取证环：共记 " .. tostring(p.n) .. " 条 · 现存 " .. tostring(p.lines)
      .. " / 上限 " .. tostring(p.max) .. "｜最后一条 = " .. tostring(p.last or "（空）"))
    sayF("（要看最近 8/20 条：/eh go 装备比较 记录 [条数]）")
  end
  sayF(L("EC_CMD_HINT"))
  return true
end

-- 读值口（生产诊断：命令与真机取证都走它们）
function EVAL_EC_TEST_STATE()
  return {
    on = EVAL_EC_ENABLED(), armed = EC.armed, wrapped = EC.wrapped, built = EC.built,
    hits = EC.hits, cur = EC.cur, why = EC.why, last = EC.last,
    colored = EC.colored, deltas = EC.deltas, sumAppended = EC.sumAppended and true or false,
    painted = EC.painted, subN = EC.subN,
    hb = EC.hb, hs = EC.hs, shown = table.getn(EC.shown),
    probeN = EVAL_EC_PROBE().n, probeLines = EVAL_EC_PROBE().lines, probeMax = EC.probeMax,
    probeLast = EVAL_EC_PROBE().last,
    saidOrigErr = EC.saidOrigErr and true or false,
    api = ecApiLine(),
  }
end

----------------------------------------------------------------------
-- 工具箱那一行（模块自己渲染；Toolbox 侧只加一行数据）
----------------------------------------------------------------------

local function ecRow(r, it)
  if type(r) ~= "table" then return false end
  r.get = function() return EVAL_EC_ENABLED() end
  r.set = function(v) EVAL_EC_SET(v and true or false) end
  r.extra:Hide()                 -- ★配置项只在按钮悬停里显示，行上不重复（项目纪律）
  return true
end

local EC_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(EC_TB_ROWS) ~= "table" then
  EC_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", EC_TB_ROWS)
end
EC_TB_ROWS["equipCompare"] = ecRow

-- 载入期到此结束：没有 CreateFrame / RegisterEvent / 存档读写 / 计时器。
