-- EvalHelp · Engine.lua —— 一键宏引擎：动作条扫描/技能五分类/规则引擎/条件解析/免疫学习/光环学习/距离分档
-- 依赖 Core.lua 导出；状态读 EVAL_HELP_STATE

local st = EVAL_HELP_STATE
local L = EVAL_L
local formatStats, collectStats = EVAL_FORMAT_STATS, EVAL_COLLECT_STATS -- 1.41.2 拆分漏桥补

-- ============ 一键输出引擎（规则引擎驱动，全职业通用） ============
-- 宏入口：/run EVAL_GO() —— 每次按键只做一个动作（同键多行动作会互抢 GCD）。
-- 技能清单一切以动作条扫描为准（1.48.0 战士白名单已清零）：把技能拖上动作条 → /eh go rescan 或配置窗[重扫]。
-- 技能识别走 tooltip 技能名（不依赖图标名拼写）；buff/debuff 用「动作条图标 == 光环图标」比对。
-- 调试：/eh go 看识别结果和当前状态；/eh go rescan 重扫；/eh debug 开关详细日志。
-- 所有出手动作都会写入调试日志（SavedVariables 环形缓冲，/eh logdump 查看），连按不刷屏也能事后复盘。

local WAR_MAX_SLOT = 119
-- 1.48.0 清理：WAR_SKILLS 战士白名单已删除——技能清单一切以动作条扫描（wslots）为准，真·全职业
-- ★★★1.73.14 隐形 tooltip（读数用）：**绝不能再借用真实 GameTooltip**
--   【实事故·用户报「开启战斗UI 后物品 tooltip 显示几秒就自动隐藏」】旧代码是 `local WTT = GameTooltip` ——
--   也就是「读光环/技能数据」用的是**玩家正在看的那个 tooltip**：每次读都要
--   SetOwner(UIParent,"ANCHOR_NONE") → ClearLines() → 填内容 → Hide()，
--   于是战斗UI / 状态UI 的**定时刷新**（条件求值要读光环）会把玩家正看的物品 tooltip **清空并关掉**。
--   ★正解 = 照 Heart/C 的范式（`C.xml` 里的 `C_Tooltip`）**自建一个隐形 tooltip**，只读它、永不碰 GameTooltip。
--   ★自建失败（客户端不给该 frame 类型）→ 才退回 GameTooltip，并加一道守卫：
--     只有「它当时没在显示」时才敢读（即便退化，也绝不碰玩家正看着的那一个）。
local WTT, WTTSELF, WTT_TOUCH, WTT_WHY = nil, false, 0, nil
do
  local tries = {
    function() return CreateFrame("GameTooltip", "EVAL_HELP_WTT", UIParent, "GameTooltipTemplate") end,
    function() return CreateFrame("GameTooltip", "EVAL_HELP_WTT", UIParent) end,
  }
  local got = nil
  for i = 1, table.getn(tries) do
    local okc, f = pcall(tries[i])
    if okc and type(f) == "table" and f ~= GameTooltip then got = f break end
  end
  if got ~= nil then
    WTT, WTTSELF = got, true
    WTT_WHY = "自建隐形 tooltip（EVAL_HELP_WTT）"
  else
    WTT, WTTSELF = GameTooltip, false
    WTT_WHY = "自建失败 → 退化用 GameTooltip（只在它没显示时才读）"
  end
  if WTT ~= nil then
    pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end) -- 1.10 hack（与 C.xml 同款）
    pcall(function() WTT:SetClampedToScreen(0) end)            -- 1.11 hack
    pcall(function() WTT:Hide() end)
  end
end
-- 读第一行：**读 WTT 自己的那个 FontString**（真实 GameTooltip 的是 GameTooltipTextLeft1；读错就读到玩家的内容）
local function wtText1()
  if WTT == nil then return nil end
  local base = "GameTooltip"
  if WTTSELF then
    local okn, n = pcall(function() return WTT:GetName() end)
    if okn and type(n) == "string" and n ~= "" then base = n end
  end
  local fs = getglobal(base .. "TextLeft1")
  if fs and fs.GetText then
    local ok2, t = pcall(function() return fs:GetText() end)
    if ok2 then return t end
  end
  return nil
end
-- 纯函数：这次到底敢不敢碰 WTT（自建 → 随便读；退化成真实 tooltip → 只有**没在显示**时才敢读）
function EVAL_WTT_MAY_READ_PURE(isSelf, realShown)
  if isSelf == true then return true end
  return (realShown ~= true)
end
function EVAL_WTT_MAY_READ()
  if WTT == nil then return false end
  if WTTSELF then return true end
  local oks, shown = pcall(function() return WTT:IsShown() end)
  local may = EVAL_WTT_MAY_READ_PURE(false, (oks and shown == true))
  if may then WTT_TOUCH = WTT_TOUCH + 1 end -- 退化模式下真碰了玩家那个 tooltip 的次数（应该尽量 0）
  return may
end
function EVAL_TEST_WTT() return WTT end -- ★测试用：读出**真正在用的**那个隐性 tooltip（断言要改它、别再改 GameTooltip）
-- ★1.75.16 **正式**读值口（不是测试专用）：凡是要拿这个隐形 tooltip「向服务器要数据」的功能
--   （数据检索里给未缓存装备补缓存）都必须走这里 —— `rawget(_G, "EVAL_HELP_WTT")` 在
--   「自建失败 → 退化用 GameTooltip」那条路上**恒为 nil**，于是调用方静默什么也做不了
--   （1.75.16 真机事故：任务线当前页不再检索装备，就是读全局名读出了 nil）。
function EVAL_WTT_HANDLE() return WTT end
function EVAL_WTT_IS_SELF() return WTTSELF end
function EVAL_WTT_STATE()
  return { self = WTTSELF, name = (WTTSELF and "EVAL_HELP_WTT" or "GameTooltip"),
           why = WTT_WHY, touches = WTT_TOUCH, hasWtt = (WTT ~= nil) }
end
local wslots = {}       -- 技能名 -> { slot, tex }
local wscanned = false
local wLastAttackTry = 0

-- 「轻量日志」：只在 /eh wdebug 开启时刷聊天框。★★★它**不写调试日志缓冲**（与旧注释相反——
--   本轮实测踩到：跟随的守卫提示用 wlog 写，`/eh logdump` 里一行都看不到，断言当场变红）。
--   ★判据：**要进 `/eh logdump` 的消息必须用 `EVAL_LOGLINE`**（那才是环形缓冲的写入口，见 Core.logLine）；
--   `wlog` 是「只在开 wdebug 时顺嘴上说一句」的调试口，两者别混用。
local function wlog(msg)
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff9040war:|r " .. tostring(msg)) end
end

local function wactionName(slot)
  if not WTT or not WTT.SetAction then return nil end
  if not EVAL_WTT_MAY_READ() then return nil end -- ★1.73.14 别碰玩家正看着的 tooltip
  local ok = pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  if not ok then pcall(function() WTT:SetOwner(UIParent, "ANCHOR_TOPLEFT") end) end
  pcall(function() WTT:ClearLines() end)
  local ok2 = pcall(WTT.SetAction, WTT, slot) -- 1.33.2 同探针结论：built 返回值在本客户端不可信，不拿它当门槛
  local name
  if ok2 then name = wtText1() end -- ★读**自家** tooltip 那一行（不再读 GameTooltipTextLeft1）
  pcall(function() WTT:Hide() end)
  return name
end

-- 扫描动作条，定位技能所在格子并记录图标
-- 1.24.0 泛化：不再限 WAR_SKILLS 白名单——动作条上所有非宏技能全部记录。
-- 收益：① 有/无buff、有/无debuff 条件支持任意已上条技能（图标比对需要纹理）；
--       ② 方案规则可直接写任意已上条技能释放（冷却/可用/排队判定都是通用 API）→ 真·全职业。
-- ★1.71.2 第 2 参 why：静默日志里标明「这次扫描是谁触发的」（open=打开配置窗 / menu=/eh go rescan / auto=自愈补扫）。
--   ★为什么不拿 quiet 兼职当原因：quiet 的三种调用点（打开配置、自愈补扫、按钮）语义不同，
--   混在一起日志里就分不清「用户开的窗」和「引擎自己补的扫」——而这两者的排查路径完全不同。
function EVAL_GO_RESCAN(quiet, why)
  -- 1.46.0 修复：原地清空而不是重新赋值——EVAL_WSLOTS 导出的是表引用（EvalHelp.lua 顶部别名持有），
  -- 重新赋值会让外部引用指向旧空表（重扫后 UI 读 wslots 全 nil、图标行全 ?）
  if wslots then for k in pairs(wslots) do wslots[k] = nil end else wslots = {} end
  -- ★★★1.71.2 物品识别（用户实测：「buff 条件下拉里出现「清凉的泉水」这类物品」）：
  --   下拉的第三组「全部技能」列的就是**动作条上的全部非宏格子**，而动作条上可以放物品
  --   （饮料/药水）→ 它们会以**裸名字**进入列表（如「清凉的泉水」）。
  --   ★为什么原有的 `not itemOf(n)` 挡不住：itemOf 只认**带前缀**的写法「物品:名称」
  --     （那是用户显式配置「使用物品」的形式），裸名字不匹配 → 漏网。
  --   ★为什么**不能直接从 wslots 里删掉**物品：动作条上的物品通过 UseAction(slot)
  --     是**真能用**的（技能行可以写它），删了会扳掉一个真功能。故只**打标**，不删除。
  --   ★为什么用背包名集合而不是别的判据：GetContainerNumSlots / GetContainerItemLink 是本项目
  --     **已在用且验证可用**的 API（同 wFindBagItem），不引入未验证的接口（本项目铁律：用前必查）。
  --   ★已知局限（如实记录，不夸大）：物品**已用完 / 已装备**（不在背包里）时认不出来 → 那条不加标记。
  local bagNames = nil
  if type(GetContainerNumSlots) == "function" and type(GetContainerItemLink) == "function" then
    bagNames = {}
    for bag = 0, 4 do
      local okn, cnt = pcall(GetContainerNumSlots, bag)
      if okn and type(cnt) == "number" and cnt > 0 then
        for bs = 1, cnt do
          local okl, link = pcall(GetContainerItemLink, bag, bs)
          if okl and type(link) == "string" then
            local inm = string.match(link, "%[(.-)%]")
            if inm then bagNames[inm] = true end
          end
        end
      end
    end
  end
  local unnamed = {} -- ★1.74.9 读不出名字的槽位（如实记录，便于排查是哪个格子）
  for slot = 1, WAR_MAX_SLOT do
    if HasAction(slot) and not GetActionText(slot) then -- GetActionText 非空 = 宏格子，跳过
      local name = wactionName(slot)
      -- ★1.74.9 修「角色技能下拉里出现一个空技能」（用户截图：列表第一项没图标没名字）：
      --   空名/纯空白名也是「读不出来」—— Lua 里 "" 是真值，旧判据 if name 会放过它，
      --   于是 wslots[""] 成立、下拉第一项就是那个空行（1.74.8 起「全部非宏格子」全列出来才暴露）。
      --   这里按本项目的同一纪律处理：查不到 ≠ 没有，宁可不进表（下方探针能如实看见它）。
      if type(name) == "string" then name = string.match(name, "^%s*(.-)%s*$") end
      if not (name and name ~= "") then
        table.insert(unnamed, slot)
      elseif not wslots[name] then
        local tex
        local okt, t = pcall(GetActionTexture, slot)
        if okt then tex = t end
        -- item=true → 该格子是物品（供下拉打标）
        wslots[name] = { slot = slot, tex = tex, item = (bagNames and bagNames[name]) or nil }
      end
    end
  end
  wscanned = true
  -- ★1.71.2 静默日志：即使用户没开调试输出，也把「动作条扫到了什么」写进调试日志缓冲。
  --   起因（用户要求）：「每次打开配置都进行一次技能扫描（静默日志）」——
  --   症状往往是「技能在动作条上却灰色/找不到格子」，而现场唯一的证据就是**这次扫描到底看到了什么**。
  --   ★必须走 EVAL_LOGLINE（环形缓冲，随 SavedVariables 落盘），不能走 EVAL_SAY——
  --     quiet=true 的调用点（打开配置窗）本就不该刷屏。
  --   ★看门狗式调用点（if not wscanned then RESCAN(true) end，1.32.9/1.46 自愈）不写日志：
  --     它可能每帧触发，会把环形缓冲刷满，把用户真正关心的日志挤掉。
  -- ★1.74.9 如实记录「读不出名字的格子」（上面把它们剔出了，用户得看得见这条因果）
  if table.getn(unnamed) > 0 and type(EVAL_LOGLINE) == "function" then
    EVAL_LOGLINE(string.format("[扫:%s] 有 %d 个格子读不出技能名（已剔除）：%s",
      tostring(why or "quiet"), table.getn(unnamed), table.concat(unnamed, ",")))
  end
  if quiet and type(EVAL_LOGLINE) == "function" then
    local total = 0
    for _ in pairs(wslots) do total = total + 1 end
    EVAL_LOGLINE(string.format("[扫:%s] 动作条识别 %d 个技能", tostring(why or "quiet"), total))
    -- 逐个列出 名称→格子：核对「方案里写的技能名」与「动作条上的技能名」是否对得上
    -- （名称对不上是「明明拖上去了却显示未找到」的头号原因，光看总数查不出来）
    local names = {}
    for nm in pairs(wslots) do table.insert(names, nm) end
    table.sort(names)
    for _, nm in ipairs(names) do
      EVAL_LOGLINE(string.format("[扫]   %s → 格子 %d", nm, wslots[nm].slot))
    end
  end
  if not quiet then
    local total = 0
    for _ in pairs(wslots) do total = total + 1 end
    EVAL_SAY(string.format("动作条共识别 |cff00ff00%d|r 个技能（均可用于方案/条件）", total))
    -- 1.45.0 核对清单以激活方案技能为准（旧版固定战士白名单核对已废弃；
    -- petCmdOf 等 local 声明在本函数之后 → 走全局导出，调用期取值）
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local p = w2 and w2.profiles and w2.profiles[w2.activeProfile or 1]
    if p and p.skills and table.getn(p.skills) > 0 then
      EVAL_SAY("激活方案「" .. tostring(p.name) .. "」技能核对↓")
      for _, r in ipairs(p.skills) do
        local n = r.skill
        local special = (EVAL_PET_OF and EVAL_PET_OF(n)) or (EVAL_TGT_OF and EVAL_TGT_OF(n)) or (EVAL_STANCE_OF and EVAL_STANCE_OF(n)) or (EVAL_ITEM_OF and EVAL_ITEM_OF(n)) or n == "取消施法"
        if special then
          EVAL_SAY(n .. " → |cff80ff80特殊技能（不占动作条）|r")
        else
          local s = wslots[n]
          EVAL_SAY(string.format("%s → %s", n, s and ("格子 " .. s.slot) or "|cffff0000未找到|r（拖上动作条后重扫）"))
        end
      end
    else
      EVAL_SAY("（激活方案暂无技能：/eh cfg → 一键宏设置 → 添加技能）")
    end
  end
  return wslots
end

-- 目标距离分档（1.37.0）：本客户端无精确距离 API（CheckInteractDistance 实测不分档、无目标坐标入口）——
-- 用已知射程参照技能 + IsActionInRange 分档：近战(≤5码)/冲锋距(8-25码)/远程外；无参照技能=nil（不显示）
function EVAL_T_RANGE()
  if not (st.hasTarget and not st.tDead) then return nil end
  if type(IsActionInRange) ~= "function" then return nil end
  local function inRange(name)
    local s = wslots[name]
    if not s then return nil end
    local okr, r = pcall(IsActionInRange, s.slot)
    if not okr or r == nil or r == 1 then return nil end -- 1=自动攻击类不测距
    return r == true
  end
  -- 1.49.2 参照技能多职业化（旧版纯战士：断筋/冲锋）：近战技=战/贼/猎/骑/德常见近战；突进技=冲锋/拦截/野性冲锋
  local melee
  for _, n in ipairs({ "断筋", "压制", "撕裂", "英勇打击", "猛击", "斩杀", "背刺", "脚踢", "猛禽一击", "审判", "撕碎" }) do
    melee = inRange(n)
    if melee ~= nil then break end
  end
  if melee == true then return "近战" end
  local charge
  for _, n in ipairs({ "冲锋", "拦截", "野性冲锋" }) do
    charge = inRange(n)
    if charge ~= nil then break end
  end
  if charge == true then return "冲锋距" end
  if melee == false or charge == false then return "远程外" end
  return nil
end

local function wtex(name) local s = wslots[name]; return s and s.tex end
-- ===== 宠物指令（1.30.0 特殊技能：rule.skill="宠物:攻击"，不占动作条，出手直接调 Pet API） =====
-- 收录战斗行为类全量：攻击/跟随/停留/停止攻击 + 三种姿态（被动/防御/主动）+ 解散。
-- 刻意不含：PetAbandon 永久放弃（太危险）、PetRename、兽栏系（非战斗行为）、CastPetAction（格子随宠物变不可靠）。
local PET_CMD = {
  { id = "attack",     name = "攻击",     fn = "PetAttack",        token = "PET_ACTION_ATTACK" },
  { id = "follow",     name = "跟随",     fn = "PetFollow",        token = "PET_ACTION_FOLLOW" },
  { id = "wait",       name = "停留",     fn = "PetWait",          token = "PET_ACTION_WAIT" },
  { id = "stopAttack", name = "停止攻击", fn = "PetStopAttack" },  -- 不上宠物动作条，无 token
  { id = "passive",    name = "被动姿态", fn = "PetPassiveMode",   token = "PET_MODE_PASSIVE" },
  { id = "defensive",  name = "防御姿态", fn = "PetDefensiveMode", token = "PET_MODE_DEFENSIVE" },
  { id = "aggressive", name = "主动姿态", fn = "PetAggressiveMode", token = "PET_MODE_AGGRESSIVE" },
  { id = "dismiss",    name = "解散",     fn = "PetDismiss",       token = "PET_ACTION_DISMISS" },
}
local PET_CMD_FN = {} -- 中文名 → 函数名
for _, p in ipairs(PET_CMD) do PET_CMD_FN[p.name] = p.fn end

-- 宠物指令图标（1.32.6）：有宠物时从宠物动作条 GetPetActionInfo(1..10) 学习 名称/token→图标，
-- 持久化 cfg.war.petIcons（跨会话）；未学到回退宠物家族图标 GetPetIcon → 问号。
-- 直接走 EVAL_HELP_CONFIG 全局（此处 local cfg 尚未声明，同 uiWarCfg 模式）
local function petIconOf(cmdName)
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  if w2 and not w2.petIcons then w2.petIcons = {} end
  local store = w2 and w2.petIcons
  if type(GetPetActionInfo) == "function" and type(HasPetUI) == "function" then
    local okh, hasPet = pcall(HasPetUI)
    if okh and hasPet and store then
      for slot = 1, 10 do
        local oki, aname, asub, atex = pcall(GetPetActionInfo, slot)
        if oki and aname and atex then store[aname] = atex end -- 命令槽返回 token（PET_ACTION_ATTACK 等），法术槽返回中文名
      end
    end
  end
  if store then
    if store[cmdName] then return store[cmdName] end
    for _, p in ipairs(PET_CMD) do
      if p.name == cmdName and p.token and store[p.token] then return store[p.token] end
    end
  end
  if type(GetPetIcon) == "function" then
    local ok, t = pcall(GetPetIcon)
    if ok and t then return t end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ★★★1.71.3 全角冒号归一（本轮实测踩到的**老坑**，一次修一辈子）：中文输入法默认打出**全角**冒号「：」，
--   而 **Lua 的字符集 `[...]` 是按字节匹配的**——`[:：]` 只会吃掉「：」的**第一个字节**（0xEF），
--   于是 `跟随：甲` 捕获到的是「<两个乱码字节>甲」，下游查表全查不到 → **静默不生效**（本项目最恨的那族）。
--   ★判据：**多字节字符绝不能放进 Lua 的 `[...]` 字符集**（那是字节集，不是字符集）。
--   ★为什么在**解析入口**归一，而不是把那 30 处 `[:：]` 逐个改掉：改一处漏一处是这类修复的典型失败，
--     而归一之后下游所有既有写法照旧可用 → **零回归面、零遗漏**。
local function colonNorm(s)
  if type(s) ~= "string" then return s end
  return (string.gsub(s, "：", ":"))
end

-- 宠物指令解析："宠物:攻击" → "攻击"（非宠物指令返回 nil）
local function petCmdOf(skill)
  local n = string.match(colonNorm(skill) or "", "^宠物[:：](.+)$")
  if n and PET_CMD_FN[n] then return n end
  return nil
end

-- ===== 目标选取（1.25.0 条件级 / 1.32.0 起同时为技能级）：副作用=切换当前目标 =====
-- 表位置上移到 wuse 之前：技能级执行（wuse 分支）需要 TARGET_SEL_FN/ARG
local TARGET_SEL = {
  { id = "nearEnemy",    name = "最近敌人",   fn = "TargetNearestEnemy" },
  { id = "nearFriend",   name = "最近友方",   fn = "TargetNearestFriend" },
  { id = "nearParty",    name = "最近队友",   fn = "TargetNearestPartyMember" },
  { id = "nearRaid",     name = "最近团员",   fn = "TargetNearestRaidMember" },
  { id = "lastEnemy",    name = "上一敌人",   fn = "TargetLastEnemy" },
  { id = "lastTarget",   name = "上一目标",   fn = "TargetLastTarget" },
  { id = "targetTarget", name = "目标的目标", fn = "TargetUnit", arg = "targettarget" },
  { id = "byName",       name = "指定名称",   fn = "TargetByName", needsName = true },
  -- ★★★1.75.10 「玩家的目标」（用户：「技能编辑->目标选择->增加选取目标:**玩家的目标**（参考选取目标:指定名称的
  --   编辑方式，但是选择的是**指定玩家的目标**），分析可行性」）：
  --   实现 = **`AssistByName(名字)`** —— 官方 Targetting 页明文：「Assists a nearby player: sets the target to that
  --   player's target.」（协助**附近**的一名玩家：把目标设成他的目标）；该页表格**没有 Protected 行**
  --   ⇒ 与 TargetUnit 同族，插件可直调（核对口径见铁律 5）。
  --   名字存 **cd.nm**（与「指定名称」同一字段）；`needsName = true` ⇒ 编辑方式（名字下拉 + 自定义输入）完全复用。
  --   ★与「指定名称」的差别只在**客户端函数**：byName = TargetByName（按名选**那个人**），
  --     playerTarget = AssistByName（选**那个人的目标**）。
  --   ★★已知边界（如实告知 + 真机探针定案，见 /eh go assist）：官方只承诺**附近**的玩家；名字不存在/不在附近时的
  --     确切表现（是否清掉当前目标）**文档没写** ⇒ 求值侧按「调用后没有目标 = 如实失败」兜底。
  { id = "playerTarget", name = "玩家的目标", fn = "AssistByName", needsName = true, needTgt = true },
  { id = "clear",        name = "清除目标",   fn = "ClearTarget" },
  -- ★★1.70.47 队伍/团队**自动扫描**选取（用户需求定案，原话）：
  --   「新增行为类型 选取目标: - 队伍成员 - 团队成员」，自动实施扫描。
  --   ★它是**成员扫描器 + 过滤器**，两件事都做：
  --     ① 扫描（队伍 = 自己 + party1..N；团队 = raid1..N）
  --     ② 用**这一行自己的条件列表**逐个候选过滤（用户示例：目标血量<N% / 目标buff:名 / 目标debuff:名）
  --     ③ 命中者 TargetUnit 过去，并记入 **st.allyUnit**（后续技能行的 UseAction 就打在他身上）
  --   ★候选顺序 = 血量百分比升序（最危险优先）→ 天然满足「扫描全员取最低」。
  --   ★为什么过滤要**切过去再判定**：条件里的「目标血量/目标buff/目标debuff」读的是 st 里的
  --     当前目标数据；只有真的切过去 + 刷新状态，那些条件才是**真的**在判定这个候选
  --     （不切就只能靠扫描记录猜，职业/类型/精英类条件根本答不出来）。代价 = ≤队伍人数 次切换，
  --     且**按需**发生（没配条件就不切），符合频率防护总则。
  --   ★teamSel = true：执行时**跳过常规条件预判**（那些条件是对「当前目标」说的，对扫描器无意义），
  --     直接进 wuse → EVAL_TEAM_PICK 按候选逐个判定（见 EVAL_RULE_RUN 的 teamSel 分支）。
  { id = "teamParty", name = "队伍成员", fn = "EVAL_TEAM_PICK", arg = "auto", teamSel = "party" },
  { id = "teamRaid",  name = "团队成员", fn = "EVAL_TEAM_PICK", arg = "auto", teamSel = "raid" },
}
local TARGET_SEL_NAME, TARGET_SEL_ID, TARGET_SEL_FN, TARGET_SEL_ARG = {}, {}, {}, {}
-- ★1.75.10 `TARGET_SEL_NM` = 「这一条选取**需要名字参数**」（当前：指定名称 byName / 玩家的目标 playerTarget）——
--   单一来源：求值（两个调用点）、编辑器（名字格与输入弹窗）、导出文本都读它，
--   免得「又在三处各写一遍 `cd.s == "byName"`」（漏一处就是「选了不生效」或「名字不显示」）。
local TARGET_SEL_NM = {}
-- ★1.75.10 `TARGET_SEL_NEEDTGT` = 「调用之后**必须有目标**，否则这次选取**没生效**」。
--   为什么只有「玩家的目标」需要：AssistByName 的失败形态**官方没写**（不像 AssistUnit 明文「清目标」），
--   而它是**副作用条件（求值恒 true）**——不判就会出现「没协助到 → 规则照样放行 → 后面那手打在旧目标上」
--   且日志还写着成功（本项目最恨的静默）。⇒ 用 `UnitExists("target")` 兜底，如实失败（见 /eh go assist 探针）。
local TARGET_SEL_NEEDTGT = {}
local TARGET_SEL_TEAMSEL = {} -- 扫描范围（"party"/"raid"）；非成员选取器为 nil
for _, t in ipairs(TARGET_SEL) do
  TARGET_SEL_NAME[t.id] = t.name
  TARGET_SEL_ID[t.name] = t.id
  TARGET_SEL_ID[t.id] = t.id
  TARGET_SEL_FN[t.id] = t.fn
  TARGET_SEL_ARG[t.id] = t.arg
  if t.needsName then TARGET_SEL_NM[t.id] = true end
  if t.needTgt then TARGET_SEL_NEEDTGT[t.id] = true end
  if t.teamSel then TARGET_SEL_TEAMSEL[t.id] = t.teamSel end
end

-- ===== 选取目标取证（1.75.12）：**每一次真的调客户端选取函数**都记一条 =================
-- 用户报障（1.75.11）：「选取目标:最近敌人 + 冲锋：选中一个**死亡**目标后按键，某些时候会在另一个目标
--   和死亡目标之间**来回切换、无限循环**，过一会儿才停」；而且**没按键时目标也会跳**。
--   ⇒ 静态审计（Engine/EvalHelp/Core 全文）结论：插件里**没有任何定时器**会调选取目标 ——
--     能切目标的只有 5 类调用点（技能行 / 条件 / 队伍扫描·命中 / 队伍扫描·还原 / 名字枚举 + 探针），
--     而它们的唯一入口是 `EVAL_GO`（宏或动作格接管）和你显式敲的命令。
--     **"没按键却在跳" ⇒ 调用在源源不断地来**：`/run` 宏在本客户端走 RunScript pending 队列，
--     松手后陈旧调用仍被客户端按**它自己的节奏**一发发冲刷；而去抖窗只是「两次被接受调用的最小间隔」，
--     当冲刷节奏**大于**窗口时**每一发都被放行**（CHANGELOG 1.54.2 自己写了这条局限）。
--   ⇒ 判据必须落在**调用点**上。每条记：① 第几发被接受的 EVAL_GO（`p` 号；同一发的多次调用同号，
--     `p-` = 不在按键那一轮里，如编辑窗下拉/探针）· ② 谁调的（技能行/条件/队伍扫描/名字枚举）·
--     ③ 调用**前 → 后**的目标快照（名字 + 血量% + 是否尸体）⇒「切了没有 / 切到谁 / 尸体有没有参与」
--     一眼可判；④ 另配「接受发数 / 被去抖丢弃发数」两条腿的计数与间隔 ⇒ 区分
--     **队列余震**（接受多、丢弃少、间隔≈冲刷节奏）与**键连发**（丢弃多）。
-- ★★单一来源：所有调用点一律走 `tselInvoke`，**不许再各自写 `pcall(fn, …)`** ——
--   漏一处就少一条证据，而这正是本项目「静默失效」的高发区（源码检查 `SEL TRACE WIRING CHECK` 守它）。
-- ★落盘 `cfg.selProbe`（有界 40 行）：日志环只有 100 条、会被 [DS]/mapfit 冲掉，而 `say` **不落日志环**
--   ⇒ 必须自带专属落盘（同 tselProbe/mbProbe/meleeProbe 的教训）；已在 Core 的调试残渣键清单里
--   （只有 `/eh 存档清理` 才清）。读它：`/eh go tsel log`（命令走读值口 EVAL_TSEL_PROBE）。
-- ★零足迹：**从没调用过选取目标就一个字节都不写**（连「去抖丢弃」也不记）⇒ 不用选取目标的用户无感。
local TSEL_OUT_MAX = 40
local tselPass, tselSeq = 0, 0              -- 第几发被接受的 EVAL_GO / 累计调用号
local tselAcc, tselSkip = 0, 0              -- 接受发数 / 被去抖丢弃发数
local tselLastAcc, tselLastSkip = nil, nil  -- 距上一发的毫秒（nil = 第一发）
local tselHdrPending = false                -- 本发还没写表头（懒写：只有真发生选取才写）
local tselLastWasSkip = false               -- 上一条写的是「丢弃中」说明（连续丢弃不重复刷屏）
local tselInGo = nil                        -- 当前正在跑的按键轮号（nil = 不在按键那一轮里）

local function tselBox()
  local cfg = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
  if cfg == nil then return nil end
  local box = cfg.selProbe
  if type(box) ~= "table" then box = {} cfg.selProbe = box end
  if type(box.out) ~= "table" then box.out = {} end
  return box
end

local function tselPush(s)
  local box = tselBox()
  if box == nil then return end
  local out = box.out
  table.insert(out, s)
  while table.getn(out) > TSEL_OUT_MAX do table.remove(out, 1) end
  box.nAcc, box.nSkip, box.pass, box.seq = tselAcc, tselSkip, tselPass, tselSeq
  box.lastAcc, box.lastSkip = tselLastAcc, tselLastSkip
  box.t = (type(date) == "function") and date("%H:%M:%S") or nil
end

-- 目标快照：「名(血40%·尸体)」/「无目标」。★客户端读不到 GUID ⇒ 同名怪只能靠**血量%**区分，
--   所以「快照相同」只能说**可能**是同一只（日志里如实写成「没变(快照相同=可能同一只)」，不冒充身份判定）。
local function tselSnap()
  if type(UnitExists) ~= "function" then return "?" end
  local okE, has = pcall(UnitExists, "target")
  if not (okE and has) then return "无目标" end
  local nm = "?"
  if type(UnitName) == "function" then
    local okN, v = pcall(UnitName, "target")
    if okN and type(v) == "string" and v ~= "" then nm = v end
  end
  local pct = "?"
  if type(UnitHealth) == "function" and type(UnitHealthMax) == "function" then
    local ok1, hp = pcall(UnitHealth, "target")
    local ok2, hm = pcall(UnitHealthMax, "target")
    if ok1 and ok2 and tonumber(hm) and tonumber(hm) > 0 then
      pct = tostring(math.floor(tonumber(hp) / tonumber(hm) * 100 + 0.5))
    end
  end
  local dead = false
  if type(UnitIsDeadOrGhost) == "function" then
    local okD, v = pcall(UnitIsDeadOrGhost, "target")
    dead = (okD and v) and true or false
  end
  return string.format("%s(血%s%%%s)", nm, pct, dead and "·尸体" or "")
end

-- ★唯一调用口：调客户端选取函数 + 记一条取证。返回值与 `pcall` **完全一致**（ok, ret）；
--   「参数是不是 nil」决定 `pcall(fn, a1)` 还是 `pcall(fn)` —— 不许给无参函数硬塞个 nil（保行为不变）。
local function tselInvoke(how, fname, fn, arg1)
  if type(fn) ~= "function" then return false, "无该函数" end
  local before = tselSnap()
  local ok, r
  if arg1 ~= nil then ok, r = pcall(fn, arg1) else ok, r = pcall(fn) end
  local after = tselSnap()
  tselSeq = tselSeq + 1
  if tselHdrPending then
    tselHdrPending, tselLastWasSkip = false, false
    tselPush(string.format("[选取] === 第%d发（距上一发接受 +%sms；累计执行%d / 丢弃%d）===",
      tselPass, tostring(tselLastAcc or 0), tselAcc, tselSkip))
  end
  local pLab = (tselInGo ~= nil and tselInGo == tselPass) and ("p" .. tostring(tselPass)) or "p-"
  local call = tostring(fname) .. ((arg1 ~= nil) and ("(" .. tostring(arg1) .. ")") or "()")
  local line = string.format("[选取] #%d %s %s %s %s ⇒ %s%s%s",
    tselSeq, pLab, tostring(how), call, before, after,
    (before == after) and " 没变(快照相同=可能同一只)" or " **变了**",
    ok and "" or " ★调用抛错")
  tselLastWasSkip = false
  tselPush(line)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, line) end
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug and type(EVAL_SAY) == "function" then
    pcall(EVAL_SAY, "|cffb0d0ff" .. line .. "|r")
  end
  return ok, r
end

-- EVAL_GO 入口每次调用都报一次「接受 / 被去抖丢弃」（本轮是「调用在不在来」的直接证据）
local function tselNoteGo(skip, gapMs)
  if skip then
    tselSkip = tselSkip + 1
    tselLastSkip = gapMs
    -- ★没调用过选取目标就什么都不写；连续丢弃只留**一条**说明（否则快速连发会把环刷爆）
    if (tselSeq > 0 or tselPass > 0) and not tselLastWasSkip then
      tselLastWasSkip = true
      tselPush(string.format("[选取] --- 去抖丢弃（距上一发接受 +%sms；累计执行%d / 丢弃%d）---",
        tostring(tselLastAcc or "?"), tselAcc, tselSkip))
    end
  else
    tselAcc = tselAcc + 1
    tselLastAcc = gapMs
    tselPass = tselPass + 1
    tselHdrPending = true
    tselLastWasSkip = false
  end
end

-- ★读值口（命令与断言共用同一份；**不解析中文文本**）：计数 + 环行数 + 最后一条
function EVAL_TSEL_PROBE()
  local box = tselBox()
  local out = (box and type(box.out) == "table") and box.out or {}
  local n = table.getn(out)
  return {
    seq = tselSeq, acc = tselAcc, skip = tselSkip, pass = tselPass,
    lines = n, last = (n > 0) and out[n] or nil,
    lastAcc = tselLastAcc, lastSkip = tselLastSkip, inGo = tselInGo,
    boxT = box and box.t or nil, max = TSEL_OUT_MAX,
  }
end

-- ★1.70.47 dispel（可驱散）类型表：id 是**入库/文本用的稳定英文 token**（来自客户端 UnitDebuff 第三返回的同一套），
--   loc 是中文显示名。★客户端返回值可能是**本地化名**（中文客户端 tooltip 显示「魔法」）也可能是英文 token，
--   故匹配一律走 dispelMatch 双向容忍（与 1.70.28 目标类型「带后缀的本地化名」同一类教训）。
local DISPEL_TYPES = {
  { id = "Magic",   tok = "Magic",   loc = "魔法" },
  { id = "Curse",   tok = "Curse",   loc = "诅咒" },
  { id = "Poison",  tok = "Poison",  loc = "毒" },
  { id = "Disease", tok = "Disease", loc = "疾病" },
}
EVAL_DISPEL_TYPES = DISPEL_TYPES -- 全局桥：编辑窗下拉与断言共用同一份

-- ★1.73.2 多选支持（用户：「debuff 类型检测 包括团队debuff 类型要支持多选」）：
--   cd.dt 允许三种形态，全部在**读侧**归一（不强制迁移存量数据）：
--     nil / "" / "any"  → 任意（不过滤类型）
--     "Magic"（字符串） → 单选（**存量数据的原样**，导出逐字不变）
--     { Magic=true, Poison=true } → 多选（新增；命中任一即算命中）
--   ★判据：集合里一个都没勾 = 任意（与 nil 同义，不能反过来变成「永不命中」）；
--     勾了几个就只认这几个（Poison 命中、Curse 不命中）。
local function dispelList(dt)
  local out = {}
  if type(dt) == "table" then
    for _, t in ipairs(DISPEL_TYPES) do if dt[t.id] then table.insert(out, t.id) end end
  elseif type(dt) == "string" and dt ~= "" and dt ~= "any" then
    table.insert(out, dt)
  end
  return out
end
-- 列表 → 入库形态：0 项 = nil（任意）、1 项 = 字符串（**保持存量导出逐字不变**）、≥2 项 = 集合表
local function dispelFold(list)
  local n = table.getn(list or {})
  if n == 0 then return nil end
  if n == 1 then return list[1] end
  local set = {}
  for _, v in ipairs(list) do set[v] = true end
  return set
end
-- ★★★1.73.12 界面上要显示**本地化名**（用户报「debuff 格式化是否没做好」：预览行吐的是导出用的英文 token
--   `(Magic/Curse/Poison)`，而编辑窗格子里明明是「魔法/诅咒/毒」）。
--   ★做法 = **同一份格式化 + 一个显示开关**（绝不复制第二份格式化逻辑）：
--     · 导出/往返：disp = nil → 英文 token（**存量与既有往返逐字不变**，这是兼容性的根）；
--     · 界面显示：disp = true → 走语言包的 DS_T_<ID>（三语言齐全），拿不到再退回 loc 中文名、最后退回 id。
--   ★为什么敢让显示形态也能被解析回：`dispelNorm` 对 tok 与 loc **双向容忍**，所以「本地化名」照旧能导入。
local function dispelLabel(dt, disp)
  local list = dispelList(dt)
  if table.getn(list) == 0 then return "" end
  if not disp then return table.concat(list, "/") end
  local out = {}
  for i = 1, table.getn(list) do
    local id = list[i]
    local label = id
    for _, t in ipairs(DISPEL_TYPES) do if t.id == id then label = t.loc end end
    local key = "DS_T_" .. string.upper(id)
    local v = (type(EVAL_L) == "function") and EVAL_L(key) or nil
    if type(v) == "string" and v ~= "" and v ~= key then label = v end
    table.insert(out, label)
  end
  return table.concat(out, "/")
end
EVAL_DISPEL_LABEL = dispelLabel -- 全局桥：界面/断言共用同一份
EVAL_DISPEL_LIST = dispelList   -- 全局桥：编辑窗显示/断言共用一份
EVAL_DISPEL_FOLD = dispelFold

local function dispelMatch(actual, want)
  -- ★1.73.2 多选：want 是集合 → 命中任一即真；**集合为空 = 任意**（与 nil/"any" 同义）
  if type(want) == "table" then
    local picked = false
    for id, on in pairs(want) do
      if on then
        picked = true
        if dispelMatch(actual, id) then return true end
      end
    end
    if not picked then return true end
    return false
  end
  if want == nil or want == "" or want == "any" then return true end -- 未指定类型 = 任意
  if type(actual) ~= "string" or actual == "" then return false end
  local a, w = string.lower(actual), string.lower(want)
  if a == w then return true end
  -- 客户端可能返回本地化名/带修饰的长串 → 双向包含兜底
  if string.find(a, w, 1, true) or string.find(w, a, 1, true) then return true end
  -- 英文 token ↔ 本地化标签 互认
  for _, t in ipairs(DISPEL_TYPES) do
    local tl, tt = string.lower(t.loc), string.lower(t.tok)
    if (w == tl or w == tt) and (a == tl or a == tt) then return true end
  end
  return false
end

-- 把用户写的类型（英文 token 或中文标签 / 大小写不一）归一成**入库用的英文 id**；不认识就原样返回
local function dispelNorm(want)
  if type(want) ~= "string" then return nil end
  local w = string.lower(string.gsub(want, "^%s*(.-)%s*$", "%1"))
  if w == "" then return nil end
  if w == "any" then return "any" end
  for _, t in ipairs(DISPEL_TYPES) do
    if w == string.lower(t.tok) or w == string.lower(t.loc) then return t.id end
  end
  return want
end

-- 文本里的一串类型（斜杠分隔、顿号/逗号也认）→ 入库形态
local function dispelFromText(s)
  local list, seen = {}, {}
  for one in string.gmatch(tostring(s or "") .. "/", "([^/%s,、]+)[/%s,、]") do
    local norm = dispelNorm(one)
    if norm and norm ~= "any" and not seen[norm] then
      seen[norm] = true
      table.insert(list, norm)
    end
  end
  return dispelFold(list)
end

-- 解析「名字(类型)」/「名字」/「类型」三种写法（导入侧宽松；类型单独写时归一到英文 id）
local function dispelSplit(s)
  s = string.gsub(s or "", "^%s*(.-)%s*$", "%1")
  local open, close = string.find(s, "%("), string.find(s, "%)%s*$")
  if open and close and close > open then
    local nm = string.gsub(string.sub(s, 1, open - 1), "^%s*(.-)%s*$", "%1")
    local dt = string.gsub(string.sub(s, open + 1, close - 1), "^%s*(.-)%s*$", "%1")
    if nm == "" then nm = nil end
    -- ★1.73.2 括号里可以是一串类型（斜杠分隔），逐项归一后再折叠回 单值/集合
    return nm, dispelFromText(dt)
  end
  -- 没有括号：整串若是一个 dispel 类型，就当作「类型」；否则当作「名称」
  local norm = dispelNorm(s)
  for _, t in ipairs(DISPEL_TYPES) do
    if norm == t.id then return nil, t.id end
  end
  if s == "" then return nil, nil end
  return s, nil
end

-- ★1.70.47 队伍成员扫描选取的**内部判据**（只被 EVAL_TEAM_PICK 用；用户看不到，也不必看到）：
--   hpLow   = 血量%最低者（满血也会被选中，交给后续「队伍血量<X%」条件把关）
--   manaLow = 蓝量%最低者（**只考虑有蓝职业**：UnitPowerType 非 0 的成员跳过）
--   buff:名 / buff:名(层数) = 身上有该 buff 的**层数最少**者（缺这个 buff 的优先，用于补 buff）
--   debuff:类型[:名称] = 身上有该类型（或该名称）负面效果的第一个成员
-- ★判据在 auto 模式下由「同一条规则里已有的队伍条件」反推（见 teamCriteriaFor）。
--   teamPickArg 是 condOne → EVAL_TEAM_PICK 的**传参通道**（Lua 只能按位置传参，而执行路径是 pcall(fn, arg)）；
--   TARGET_SEL_ARG_LAST 记「这次点的是 队伍 还是 团队」，决定扫描范围。
local teamPickArg = { arg = "hpLow" }
local TARGET_SEL_ARG_LAST = nil

-- ★1.70.47 前置声明：groupsOK（条件组求值）在文件后半段才实现，但「选取目标:队伍成员」的
--   **候选过滤**要用它（对每个候选跑一遍这一行自己的条件列表）。Lua 词法作用域 → 必须先声明。
local groupsOK

-- ★1.70.47 前置声明：auraTexOf 的**真正实现**在下面（光环名→纹理，动作条优先/学习表回退）。
--   本段（队伍选人判据）在它之前就要用「buff 名 → 纹理」做比对，而 Lua 只认**词法**作用域：
--   不前置声明的话，这里的 auraTexOf 会解析成**全局 nil** → 一按队伍buff 条件就红字报错。
--   ★这正是本项目累计十几次的同一类坑；DECL ORDER CHECK 这次**没抓到**（它只扫
--     「顶层 local 声明 vs 使用」，而这里的问题是「使用了下面才声明的东西」——
--     检查方向需要覆盖「同一文件内、引用点早于声明点」的相互次序，已记入待办）。
local auraTexOf
-- ★1.74.8 同理前置声明：图标解析（wactionName 一带，行号 <1121）里要用 auraTexKnown，
--   而它声明在后面 —— 不前置就是「按到取消自身buff 就红字 attempt to call a nil value」。
local auraTexKnown
local function teamPickBest(list, crit, bufTex, bufNeed, debTex, debWant)
  local best, bestKey = nil, nil
  for _, r in ipairs(list) do
    if crit == "hpLow" then
      if r.hpMax > 0 and (bestKey == nil or r.hpPct < bestKey) then best, bestKey = r, r.hpPct end
    elseif crit == "manaLow" then
      local isMana = (r.powerType == nil or r.powerType == 0)
      if isMana and r.powerMax > 0 and (bestKey == nil or r.powerPct < bestKey) then best, bestKey = r, r.powerPct end
    elseif crit == "buff" then
      -- 补 buff 语义：优先选**缺这个 buff**（或层数不足）的成员；都齐了就退化为血量最低者
      local cnt = bufTex and r.buffs[bufTex] or nil
      cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
      if cnt < bufNeed then
        local key = cnt -- 层数越少越优先；同层数再比血量
        if bestKey == nil or key < bestKey or (key == bestKey and r.hpPct < (best.hpPct or 999)) then
          best, bestKey = r, key
        end
      end
    else -- debuff
      local hit, hitCnt = false, 0
      if debTex then
        local d = r.debuffs[debTex]
        if d and dispelMatch(d.t, debWant) then hit = true hitCnt = tonumber(d.n) or 1 end
      else
        for _, d in pairs(r.debuffs) do
          if dispelMatch(d.t, debWant) then hit = true hitCnt = tonumber(d.n) or 1 break end
        end
      end
      if hit and (bestKey == nil or hitCnt > bestKey) then best, bestKey = r, hitCnt end
    end
  end
  return best
end

-- ★1.70.47 已删除「按同一规则里的队伍条件反推判据」那套（teamCriteriaFor）。
--   为什么删：用户需求定案后，「挑选谁」改由**选取器那一行自己的条件列表**逐候选过滤
--   （见 EVAL_TEAM_PICK 的 ① 分支）——那比「反推判据」更直接、更可预测，也支持任意条件组合。
--   反推那套就只剩「无规则时默认血量最低」，一行足矣。★前提被取代的机制要删掉，别留着空转。

-- ★1.70.47 队伍成员自动扫描选取（用户要求）。
--   crit="auto"：判据由**同一条规则里的队伍条件**反推（见 teamCriteriaFor）——这就是「选取目标:队伍」的全部行为
--   选中后：设 st.teamCur（队伍/团队条件按它求值）+ TargetUnit(unit)（后续技能行 UseAction 就打在它身上）。
-- ★为什么要切目标：CastSpellByName/SpellTargetUnit 在本客户端**都是 Protected**，插件无法直接指定施法对象；
--   TargetUnit 非 Protected，所以「切目标 → 用技能 → 还原」是唯一可行路径（见 CLAUDE.md F2 节）。
-- ★频率防护：整个扫描只在这里发生一次（按宏那一轮），UPDATE_STATE 绝不扫描。
-- 候选按血量百分比升序（最危险优先）——「扫描全员取最低」的自然顺序
-- ★★★1.71.3 选取规则统一（用户定案）：「在通过条件的人里挑谁」由**行内第一个比较型条件**决定：
--   「<」「<=」→ 取该值**最小**；「>」「>=」→ **最大**；「=」「==」→ **最接近 N**；
--   没有比较型条件 / 「~=」→ 回退（按血量%升序 = 取最小，与旧版行为一致）。
--   ★流程不变：仍按这个顺序逐个切过去判定，**第一个通过的就是结果**（切换次数与旧版相同）。
--   ★near 之所以也能「第一个通过即最接近」，是因为**排序键就是「到 N 的距离」**。
local function teamCandVal(rec, key)
  if type(rec) ~= "table" then return nil end
  local v = (key == "power") and rec.powerPct or rec.hpPct
  return tonumber(v)
end

-- 从规则里推导「比较键 + 方向 + N + 依据条件」；nil = 无方向（回退）
-- ★只认**候选者可比**的数值条件：候选者血%/能量%（新）、自身血%/能量%、目标血%（在选取器行上
--   这几类都按候选者读，见 condOne 的候选上下文）。
local TEAM_ORDER_KEYS = { candHp = "hp", hpPct = "hp", tHpPct = "hp",
                          candPower = "power", powerPct = "power", tPowerPct = "power" }
function EVAL_TEAM_PICK_ORDER(rule)
  for _, g in ipairs((rule and rule.groups) or {}) do
    for _, cd in ipairs(g) do
      local key = TEAM_ORDER_KEYS[cd.k]
      if key and type(cd.n) == "number" then
        local mode = nil
        if cd.op == "<" or cd.op == "<=" then mode = "min"
        elseif cd.op == ">" or cd.op == ">=" then mode = "max"
        elseif cd.op == "==" or cd.op == "=" then mode = "near" end
        if mode then return { key = key, mode = mode, n = cd.n, cd = cd, label = EVAL_COND_STR(cd) } end
      end
    end
  end
  return nil
end

-- 日志里的「依据」文案（用户要求：说清楚为什么是他）
local function teamOrderLabel(order)
  if not order then return "无比较条件 → 默认血量最低" end
  local how = (order.mode == "min") and "取最小" or ((order.mode == "max") and "取最大" or "取最接近")
  return how .. "(" .. tostring(order.label) .. ")"
end

local function teamSortBy(list, order)
  local out = {}
  for i = 1, table.getn(list) do out[i] = list[i] end
  local key = order and order.key or "hp"
  local mode = order and order.mode or "min"
  local n = order and order.n or 0
  table.sort(out, function(a, b)
    local va, vb = teamCandVal(a, key), teamCandVal(b, key)
    -- ★没有该属性（例如无蓝职业）的成员**排到最后**：既不参与「最」的竞争，也不报错
    if va == nil and vb == nil then return (a.hpPct or 0) < (b.hpPct or 0) end
    if va == nil then return false end
    if vb == nil then return true end
    if mode == "max" then return va > vb end
    if mode == "near" then
      local da, db = math.abs(va - n), math.abs(vb - n)
      if da == db then return va < vb end
      return da < db
    end
    if va == vb then return (a.hpPct or 0) < (b.hpPct or 0) end
    return va < vb
  end)
  return out
end

-- 记下「这一次按键选中的队友」：后续技能行的 UseAction 就打在他身上
local function teamSelect(rec)
  st.allyUnit = rec and rec.unit or nil
  st.teamCur = rec
  if rec and type(TargetUnit) == "function" then tselInvoke("队伍选取:命中", "TargetUnit", TargetUnit, rec.unit) end
  return rec and rec.unit or nil
end

-- ★★1.71.3 「选取目标:队伍成员」的**如实日志**（用户实测报回：日志只说「已出手」，看不出选没选到人、
--   按哪条条件选的 →「现在无法正常工作」）。
--   teamPickInfo 由 EVAL_TEAM_PICK 填、由 wuse 写日志：① 命中 → 名字/unit/血量·法力% + 满足的条件明细；
--   ② 没命中 → 候选清单（名字+血量%）+「自身* 筛不出队友」的提示。★每次选取都重置，只反映这一次。
local teamPickInfo = { hit = false, text = nil }

-- 百分比取整显示：★不能用 tostring(10.0)——Lua 5.1 给 "10"，fengari(5.3) 给 "10.0"，
--   两边日志不一致；取整后都是"10"，用户看着也清爽（"血量 10%"）。
local function teamPct(v)
  local n = tonumber(v)
  if not n then return "?" end
  return tostring(math.floor(n + 0.5))
end

-- 候选人简报：名字 + unit + 血量%（用户要求「明确匹配到的目标名称 + 血量 N%」）
local function teamRecBrief(rec)
  if type(rec) ~= "table" then return "?" end
  return string.format("%s %s 血量 %s%% 法力 %s%%", tostring(rec.name or rec.unit), tostring(rec.unit),
    teamPct(rec.hpPct), teamPct(rec.powerPct))
end

-- 候选清单简报（没命中时用；最多列 8 个，避免刷屏）："甲50% / 乙10%"
local function teamCandBrief(list)
  local parts = {}
  for i = 1, table.getn(list or {}) do
    if i > 8 then table.insert(parts, "...") break end
    table.insert(parts, string.format("%s %s%%", tostring(list[i].name or list[i].unit), teamPct(list[i].hpPct)))
  end
  return table.concat(parts, " / ")
end

-- ★★★1.71.3 成员过滤（用户要求：8 项队伍/团员条件加「职业多选」；4 项团员条件另加「队伍多选」）。
--   ★★**空集 = 不过滤**（用户原话「默认空不过滤职业.也就是全部」）——这与「目标职业」那条
--     「空 = 永不满足」**正好相反**，所以两处既不共用判据、也不共用文案（各有专属断言钉住）。
--   ★cd = 单条条件（按它自己的过滤）；rule = 整行（取**并集**：任一条件里选了哪个职业/小队，那个就算候选）。
--     ——「选取目标:队伍成员」那一行走的就是 rule 这条：职业/小队过滤限制的是**候选集合**。
local function teamFilterList(list, cd, rule)
  local cs = (cd and type(cd.cs) == "table") and cd.cs or nil
  local gs = (cd and type(cd.gs) == "table") and cd.gs or nil
  if not cs and not gs and rule then
    cs, gs = {}, {}
    for _, g in ipairs(rule.groups or {}) do
      for _, c in ipairs(g) do
        if type(c.cs) == "table" then for kk in pairs(c.cs) do cs[kk] = true end end
        if type(c.gs) == "table" then for kk in pairs(c.gs) do gs[kk] = true end end
      end
    end
  end
  local hasCs, hasGs = (cs and next(cs) ~= nil) or false, (gs and next(gs) ~= nil) or false
  if not hasCs and not hasGs then return list end
  local out = {}
  for i = 1, table.getn(list or {}) do
    local r = list[i]
    local ok = true
    if hasCs and not (r.cls and cs[r.cls]) then ok = false end
    if ok and hasGs then
      local g2 = tonumber(r.grp)
      if not (g2 and gs[g2]) then ok = false end
    end
    if ok then table.insert(out, r) end
  end
  return out
end

-- ★「自身*」条件描述的是**你自己**，筛不出队友。用户方案里配的正是「自身血%<95」→
--   结果要么全员都过、要么全员都不过，看起来就像「选取不工作」。这里把话说清楚（不猜、不静默）。
-- ★★★1.71.3 挑选候选者的**可比条件**清单（用户定案：自身*/目标*/候选者* 在选取器行上都按候选者读，
--   所以它们**都能**筛队友——这一条纠正了 1.71.3 早前那句「自身* 筛不出队友」的提示）。
local TEAM_PICK_CAND_K = {
  candHp = true, candPower = true, candBuff = true, candDebuff = true,
  hpPct = true, powerPct = true, power = true,            -- 兼容写法（选取器行上按候选者读）
  tHpPct = true, tPowerPct = true, tBuff = true, noBuff = true, hasDebuff = true, noDebuff = true,
  tCasting = true, tCastEl = true, tCastLeft = true,      -- 目标 = 候选者
}
local function teamSelfOnlyHint(rule)
  local all, cand = 0, 0
  for _, g in ipairs((rule and rule.groups) or {}) do
    for _, cd in ipairs(g) do
      all = all + 1
      if TEAM_PICK_CAND_K[cd.k] then cand = cand + 1 end
    end
  end
  if all > 0 and cand == 0 then
    return "（提示：本行**没有能筛候选者的条件**（血量/能量/buff/debuff…）→ 扫描器退化为「血量最低者」，所以谁都不通过时才会全灭）"
  end
  return ""
end

function EVAL_TEAM_PICK(crit)
  teamPickInfo.hit, teamPickInfo.text = false, nil -- ★每次选取都重置：日志只反映**这一次**
  -- 叫「队伍成员」就只扫队伍，叫「团队成员」就扫团队
  local scope = (TARGET_SEL_ARG_LAST == "teamRaid") and "raid" or "party"
  local list = EVAL_HELP_TEAM_ENSURE and EVAL_HELP_TEAM_ENSURE(scope) or nil
  if not list or table.getn(list) == 0 then
    st.teamCur, st.allyUnit = nil, nil
    teamPickInfo.text = "扫描范围内没有成员（范围=" .. tostring(scope) .. "）"
    return nil
  end

  -- ① 有规则（「选取目标:队伍成员」技能行）→ **按这一行自己的条件逐个候选过滤**
  local rule = teamPickArg.rule
  if rule then
    -- ★1.71.3 候选集合先按这一行的「职业/队伍」过滤（**并集**：任一条件选了哪个职业，那个就算候选）
    local filtered = teamFilterList(list, nil, rule)
    if table.getn(filtered) == 0 then
      teamPickInfo.text = "扫描范围内没有人符合「职业/队伍」过滤"
      return nil
    end
    list = filtered
    -- ★原目标要尽量**精确**记住：优先用 UnitIsUnit 反查出它的 unit id（还原最可靠）；查不到才退化为按名字。
    --   ★为什么不能只靠名字：文档（Targetting#targetbyname）明确 TargetByName 只认**附近**单位——
    --     原目标在远处时按名字还原会**静默失败**，目标就丢在最后一个候选身上了。
    --   （UnitIsUnit 文档：相同返回 true，不同返回 **nil**（绝不 false）→ 判定只能看真值，不能 == true）
    local origName = (st.hasTarget and st.targetName) and st.targetName or nil
    local origUnit = nil
    if origName and type(UnitIsUnit) == "function" then
      for _, rec in ipairs(list) do
        if UnitIsUnit("target", rec.unit) then origUnit = rec.unit break end
      end
    end
    local order = EVAL_TEAM_PICK_ORDER(rule)       -- ★选人方向（用户规则）；nil = 回退
    teamPickArg.driverCd = order and order.cd or nil -- 供「=」的「取最接近」放宽（只放宽**驱动那一条**）
    local sorted = teamSortBy(list, order)
    for _, rec in ipairs(sorted) do
      -- ★★候选上下文：这一行的「候选者血%/能量%」以及兼容写法的「自身血%/能量%」都读**这个候选者**
      --   （用户定案：扫描集含自己，一视同仁）
      st.pickCand = rec
      if type(TargetUnit) == "function" then tselInvoke("队伍扫描:候选", "TargetUnit", TargetUnit, rec.unit) end
      if EVAL_HELP_UPDATE_STATE then pcall(EVAL_HELP_UPDATE_STATE) end
      -- ★捕捉第三个返回值 trace = 满足的那组条件的**逐项判定明细**（"目标血%<40√"），写进日志
      --   （旧版把它丢掉了 → 日志里看不出按哪条条件选中的人）
      local ok, _why, trace = groupsOK(rule, false)
      if ok then
        teamPickInfo.hit = true
        teamPickInfo.text = teamRecBrief(rec) .. " · 条件: " .. tostring(trace or "")
          .. " · 依据: " .. teamOrderLabel(order)
        st.pickCand, teamPickArg.driverCd = nil, nil
        return teamSelect(rec)
      end
    end
    st.pickCand, teamPickArg.driverCd = nil, nil -- ★无论命中与否都要清掉：绝不让上下文漏到别的行
    -- 全员都不满足 → **还原原目标**（诚实：不把目标丢在最后一个候选身上就算完）
    if origUnit then
      tselInvoke("队伍扫描:还原", "TargetUnit", TargetUnit, origUnit) -- 精确还原（原目标就是某个队友/自己）
    elseif origName then
      tselInvoke("队伍扫描:还原", "TargetByName", TargetByName, origName) -- 仅对附近单位有效；失败时下面这条日志会如实说明
      wlog("队伍选取: 没选到成员；已尝试按名字还原目标「" .. tostring(origName) .. "」(TargetByName 只认附近单位)")
    else
      tselInvoke("队伍扫描:还原", "ClearTarget", ClearTarget) -- 本来就没有目标 → 还原成「无目标」
    end
    if EVAL_HELP_UPDATE_STATE then pcall(EVAL_HELP_UPDATE_STATE) end
    st.teamCur, st.allyUnit = nil, nil
    teamPickInfo.hit = false
    teamPickInfo.text = teamCandBrief(sorted) .. " 都不满足 " .. teamSelfOnlyHint(rule)
    return nil
  end

  -- ② 无规则：按判据直接挑（测试直调 / 内部复用）
  local bufTex, bufNeed, debTex, debWant = nil, 1, nil, nil
  if crit == "auto" or crit == nil then
    crit = "hpLow" -- 无规则可过滤时的默认：血量最低（治疗场景最保守的选择）
  elseif crit == "buff" then
    bufTex, bufNeed = teamPickArg.tex, (teamPickArg.n or 1)
  elseif crit == "debuff" then
    debTex, debWant = teamPickArg.tex, teamPickArg.dt
  end
  local best = teamPickBest(list, crit, bufTex, bufNeed, debTex, debWant)
  -- 补 buff 场景下若全队都有该 buff → 退化为血量最低者（仍选一个人出来，别空手）
  if not best and crit == "buff" then best = teamPickBest(list, "hpLow") end
  if not best then
    st.teamCur, st.allyUnit = nil, nil
    teamPickInfo.hit = false
    teamPickInfo.text = teamCandBrief(list) .. " 都不满足（判据 " .. tostring(crit) .. "）"
    return nil
  end
  teamPickInfo.hit = true
  teamPickInfo.text = teamRecBrief(best) .. " · 判据: " .. tostring(crit)
  return teamSelect(best)
end

-- 选取目标技能级解析（1.32.0）："选取目标:最近敌人" → id；"选取目标:指定名称:嗜血者" → "byName","嗜血者"
local function targetSelOf(skill)
  local tg = string.match(colonNorm(skill) or "", "^选取目标[:：](.+)$")
  if not tg then return nil end
  local nm = string.match(tg, "^指定名称[:：](.+)$")
  if nm then return "byName", nm end
  -- ★1.75.10 玩家的目标（协助某玩家）："选取目标:玩家的目标:嗜血者" → "playerTarget","嗜血者"
  local nmP = string.match(tg, "^玩家的目标[:：](.+)$")
  if nmP then return "playerTarget", nmP end
  -- ★1.71.3 分类下拉里那一项的文案就是 L("SE_PICK_TGT")=「指定名称…」（**带省略号**）：
  --   原先直接拿它查表查不到 → wicon 一路落空 → 这一行**一个图标都没有**（用户截图红线圈出的正是它）。
  --   → 查表前先剥掉结尾的省略号（… / ...），让**同一份 TARGET_SEL 表**既管文案又管图标（单一真值）。
  local key = string.gsub(tg, "…$", "")
  key = string.gsub(key, "%.%.%.$", "") -- ★注意：Lua 模式里 %% 是「字面百分号」，这里必须单 %（本轮手误踩到）
  local id = TARGET_SEL_ID[key]
  if id then return id end
  return nil
end

-- 物品使用（1.32.0）：rule.skill="物品:名称"——背包扫描定位 + UseContainerItem（消耗品直接用/装备自动穿上，官方文档明确不受保护）
local function itemOf(skill)
  return string.match(colonNorm(skill) or "", "^物品[:：](.+)$")
end
-- 背包查找：→ bag, slot, tex, count（未找到返回 nil）
local function wFindBagItem(name)
  if type(GetContainerNumSlots) ~= "function" then return nil end
  for bag = 0, 4 do
    local okn, slots = pcall(GetContainerNumSlots, bag)
    if okn and slots and slots > 0 then
      for slot = 1, slots do
        local okl, link = pcall(GetContainerItemLink, bag, slot)
        if okl and link then
          local iname = string.match(link, "%[(.-)%]")
          if iname == name then
            local oki, tex, count = pcall(GetContainerItemInfo, bag, slot)
            return bag, slot, (oki and tex) or nil, (oki and count) or 1
          end
        end
      end
    end
  end
  return nil
end

-- 姿态切换（1.43.0）：rule.skill="姿态:战斗姿态"——走姿态栏 CastShapeshiftForm（官方文档明确 Not protected，插件可直调），
-- 不占动作条。战士姿态不可取消（重复按 no-op）；德鲁伊等可切换形态重复按会取消 aura → 执行前 active 守门。
local function stanceOf(skill)
  return string.match(colonNorm(skill) or "", "^姿态[:：](.+)$")
end
-- 姿态名或序号（"姿态:2" 1.47.0 起兼容）→ 姿态栏 1 基索引, 图标, 当前激活(1/nil), 可用(1/nil)；未找到/无姿态栏返回 nil
local function wFindStance(name)
  if type(GetNumShapeshiftForms) ~= "function" then return nil end
  local okn, n = pcall(GetNumShapeshiftForms)
  if not (okn and n and n > 0) then return nil end
  local idx = tonumber(name) -- 序号直取（"姿态:2"=姿态栏第 2 格）
  if idx and idx >= 1 and idx <= n then
    local oki, icon, nm, active, castable = pcall(GetShapeshiftFormInfo, idx)
    if oki and nm then return idx, icon, active, castable end
    return nil
  end
  for i = 1, n do
    local oki, icon, nm, active, castable = pcall(GetShapeshiftFormInfo, i)
    if oki and nm and nm == name then return i, icon, active, castable end
  end
  return nil
end

-- 取消施法（1.47.0 特殊行为）：rule.skill="取消施法"——SpellStopCasting 打断自己当前读条（wiki Spell 分类），
-- 不占动作条；典型用途：读条被打/需要立刻转身逃跑时配条件触发。
local function cancelCastOf(skill)
  if skill == "取消施法" then return true end
  return nil
end

-- 停止攻击（1.71.3 特殊行为，用户要求「类似按 ESC」）：rule.skill="停止攻击" —— 一次做完「停手」四件事：
--   ① 读条 + 自动射击 + 魔杖自动重复：官方文档 api_spell 原文——SpellStopCasting()「Stops the current cast
--      or auto-repeat spell ... Cancels auto-shot / auto-repeat first if one is running. Otherwise interrupts
--      the in-progress cast.」→ 一次调用覆盖三类；但它【Protected: yes】→ 走 RunScript 排队（同 1.49.3）。
--   ② 近战普攻：AttackTarget() 文档原文「Toggles auto-attack on the current target」=【切换】语义，
--      必须先确认「当前真在挥击」（IsCurrentAction 守卫，同 1.50.0 自动攻击）才敢按，
--      否则会把没在打的人**打起来**（与「停止」正相反）；动作条上没有「攻击」= 判不出来 → 不碰并如实记日志。
-- 不占动作条、无冷却；未在攻击/施法时是空操作（文档：Returns nil if neither is active）。
local function stopAllOf(skill)
  if skill == "停止攻击" then return true end
  return nil
end

-- 跟随（1.71.3 特殊行为，用户要求：「角色行为 添加: 跟随:名字输入, 查看API是否跟随.跟随目标.验证可行性」）：
--   rule.skill = "跟随"（跟当前目标）/ "跟随:名字"（按名字跟）。
--   ★★★官方文档核查（本轮现场取证：emberveil 文档 Movement 分类原文，用户要的「验证可行性」）：
--     · `FollowByName(name)` —— **not protected**：「Starts autofollow on a nearby player by name, or on the
--       current target if name is omitted or empty」；名字匹配**不区分大小写**、只搜**它已知的玩家对象**；
--       找不到（或省略名字时没有目标）→ **显示一条错误并返回**（不抛异常）；额外参数被忽略、省略名字不报错。
--     · `FollowUnit(unit)` —— 同样 **not protected**，但它要的是**单位 id**（player/target/…）而不是名字，
--       且参数缺失会**抛 Lua 错误**（Usage: FollowUnit("UnitType")）→ 按名字跟就走 FollowByName 更直接。
--     · ★除这两个之外，Movement 页**每个函数都是 Protected**（MoveForwardStart/Stop、TurnLeftStart…）——
--       这正好**回顾性解释了**上一轮「移动脉冲」为什么实测无效：插件根本调不动它们（那条路已删）。
--   ★结论：**做得到**。直调 FollowByName；★**不走 RunScript**——它不是 Protected
--     （RunScript 是给 Protected 用的排队通道，停读条那条才是）。
--   ★两条文档明列的硬规则先在本地挡掉（都零频率风险）：**不能跟随自己**；没给名字且当前没目标。
local function followOf(skill)
  if skill == "跟随" then return true, "" end
  local nm = string.match(colonNorm(skill) or "", "^跟随:(.*)$")
  if nm then return true, nm end
  return nil
end

-- 取消自身buff（1.74.8 特殊行为，用户要求：「方案->技能->取消自身buff」）：
--   rule.skill = "取消自身buff"（取消**全部**可取消的自身光环）
--              / "取消自身buff:光环名"（只取消那一个）。
--   ★★★官方 API 核查（本项目铁律：返工/新功能先核 API 本身对不对）：
--     · 本客户端**没有** Dismount / IsMounted / CancelAura 任何专用函数（1370 条索引零命中）；
--     · 唯一通道 = `CancelPlayerBuff(buffIndex)`，**not Protected**（可直接调，无需 RunScript）
--       —— 与 1.74.7 骑乘助手同一结论；
--     · ★它收的是 **GetPlayerBuff 返回的内部索引**，不是增益条槽位号 —— 喂错会取消**别的**光环。
--   ★语义取舍（与「取消施法」的「没在读条就静默跳过」同族，别做成静默失败）：
--     · 指定名字时：身上没有 → **跳过并如实记日志**（不是报错，也不是假装成功）；
--     · 不指定名字时：取消全部**可取消**的自身增益（GetPlayerBuff 的 CANCELABLE 过滤天然排除不可取消的）。
--   ★不占动作条（见 skillNoSlotOk）。
local function cancelBuffOf(skill)
  if skill == "取消自身buff" then return true, nil end
  -- ★1.74.9 多选（用户：「下拉选择 buff 需要支持多选」）：逗号分隔 "取消自身buff:名1,名2"
  --   → 返回的 nm 是**名单表**（集合 + 保持顺序的列表），执行侧逐个匹配；
  --   单个名字照旧（集合里就一个）。逗号在光环名里不会出现，用它当分隔符最安全。
  local nm = string.match(colonNorm(skill) or "", "^取消自身buff:(.*)$")
  if nm then
    -- ★集合表（键=名字 → true），有序名单挂在 .list 上（跳过时如实点名用）；
    --   单个名字时集合里就一个 —— 与旧单名行为逐字一致。
    local set, list = {}, {}
    for part in string.gmatch(nm, "([^,]+)") do
      local one = string.match(part, "^%s*(.-)%s*$")
      if one ~= "" and not set[one] then set[one] = true table.insert(list, one) end
    end
    if table.getn(list) == 0 then return nil end
    set.list = list
    return true, set
  end
  return nil
end

-- ★★★1.72.4 「不占动作条也合法」的**单一判据**（引擎闸门 + 战斗信息UI 的亮金/缺失判定共用一份）。
--   为什么必须抽成一份：原来这段 7 个 or 的名单在**三个地方各写了一遍**（引擎跳过判据、
--   战斗信息UI 亮金白名单、战斗信息UI「缺技能?」白名单）→ 新增一类「不需要动作条」的技能时
--   只改一处，另外两处就静默不同步（表现：技能其实能放，图标却是灰的 + 标着「?」= 假告警）。
--   ★rank（指定等级）走 RunScript 直接施法，**本来就不需要动作条** → 必须算进来。
function skillNoSlotOk(skill, rank)
  if rank then return true end
  return (petCmdOf(skill) or targetSelOf(skill) or itemOf(skill) or stanceOf(skill)
          or cancelCastOf(skill) or stopAllOf(skill) or followOf(skill) or cancelBuffOf(skill)) and true or false
end

-- ===== 「停读条」通道（1.71.3：**保留原始 SpellStopCasting 方式**；移动脉冲实测无效、已删）=====
-- ★核查过程（本机 api_*.html 全表 1370 条逐类翻过）：
--   · 停读条接口**只有 `SpellStopCasting` 一个**（`SpellStopTargeting` 只收待选目标的光标），
--     文档原文「Stops the current cast or auto-repeat spell…」并标注
--     【**Protected: yes**｜addons cannot call this; only the default FrameXML UI can】。
--   · 用户实测①：插件调它 → **本地进度条消失、法术照放**（只清本地 UI，服务端读条照旧）。
--   · 用户实测②：「移动脉冲」（1.12「走一步断读条」原理：MoveForwardStart → 0.08s → MoveForwardStop）
--     → **同样无效** → 已删除（没效果还把角色往前挪 = 纯副作用）。
--   · ★用户决定（1.71.3）：「**可能是现在客户端的 bug，功能先留着**」——所以这里**保留原始的
--     SpellStopCasting 方式**（Protected → RunScript 排队，1.49.3 那条已验证通道），
--     「取消施法」这个动作也**照旧保留**；将来客户端把那块行为修好，无需改代码即可直接生效。
--   ★★绝不再做任何移动（不动玩家角色）；将来若客户端行为有变，重做入口就是这一个函数。
local stopCastLast = -99

-- 返回：是否做了动作, 通道明细（当前恒为 "本地条"）
function EVAL_STOP_CAST()
  local now = (type(GetTime) == "function") and GetTime() or 0
  if now - stopCastLast < 1 then return false, "限频" end -- 频率防护：规则每拍触发时别把 pending 脚本队列刷满
  stopCastLast = now
  if type(RunScript) == "function" then
    pcall(RunScript, "SpellStopCasting()")
    return true, "本地条"
  elseif type(SpellStopCasting) == "function" then
    pcall(SpellStopCasting)
    return true, "本地条"
  end
  return false, "无通道"
end
-- ★1.71.3 「选取目标:」族专属图标（用户反馈：子菜单里一排红问号根本分不清）。
--   ★图标**自包含**（这 27 张已拷进本插件的 media\\icons\\）；★**单一来源**：这张表是这族图标的唯一出处，
--     wicon 与断言都从这里取。★id 与 TARGET_SEL 一一对应；表里没有的 id 仍回退问号（不瞎指一张图）。
local TSE_ICON_ROOT = "Interface\\AddOns\\EvalHelp\\media\\icons\\"
local TARGET_SEL_ICON = {
  nearEnemy    = TSE_ICON_ROOT .. "boss-mobs",     -- 最近敌人（打）
  nearFriend   = TSE_ICON_ROOT .. "spirithealer",  -- 最近友方（蓝天使）
  nearParty    = TSE_ICON_ROOT .. "meetingstone",  -- 最近队友（集合石）
  nearRaid     = TSE_ICON_ROOT .. "elite-mobs",    -- 最近团员
  lastEnemy    = TSE_ICON_ROOT .. "rare-mobs",     -- 上一敌人
  lastTarget   = TSE_ICON_ROOT .. "flight",        -- 上一目标（回头）
  targetTarget = TSE_ICON_ROOT .. "quest-marker",  -- 目标的目标（跟随）
  byName       = TSE_ICON_ROOT .. "database",      -- 指定名称（查找）
  playerTarget = TSE_ICON_ROOT .. "trainer",       -- ★1.75.10 玩家的目标（协助某玩家 → 看他的目标；借「训练师」那张人像表示"一名玩家"）
  clear        = TSE_ICON_ROOT .. "repair",        -- 清除目标
  teamParty    = TSE_ICON_ROOT .. "battlemaster",  -- 队伍成员
  teamRaid     = TSE_ICON_ROOT .. "raid-entrance", -- 团队成员
}
function EVAL_TARGET_SEL_ICON(id) return TARGET_SEL_ICON[id] end -- 供断言/图标库读（同一份真值）
-- ★1.71.3 「角色行为」里非动作条动作的图标（目前只有「跟随」一张）。★与 TSE_ICON_ROOT 是同一套自包含文件，
--   但**另立一个根名**：UI ICON CHECK 按「根名 + 文件名」逐组核对，同根会被当成「选取目标那族」去查重。
local ACT_ICON_ROOT = "Interface\\AddOns\\EvalHelp\\media\\icons\\"
local ACT_FOLLOW_ICON = ACT_ICON_ROOT .. "flight" -- ★借「飞行管理员」那双靴子（跟着走）；该文件本来就自包含在 media\icons\

-- ★★★1.71.3 「取消施法」的左图标改从**客户端自带的宏图标表**里取（用户要求「左边你从宏图标内自己选一个」）。
--   ★为什么不写死一个 "Interface\Icons\xxx" 字符串：本客户端**纹理路径写错时什么都不画**
--     （不报错、不崩，只是空白——同 UI ICON CHECK 那条判据）；而内置图标在磁盘上取不到
--     （整套图标打包在 Content\Paks 里，本机散图只有 AddOns 下那 163 个）→ 写死 = 赌一个看不见的字符串。
--   ★改成**问客户端自己的表**（GetNumMacroIcons / GetMacroIconInfo，与「图标库」Tab 同一数据源）：
--     找到才用，找不到**如实退回问号**（不瞎指一张图）。
--   ★只扫一次（成功即缓存）；表在载入期可能还没就绪 → 空结果**不缓存**、最多再试 3 次
--     （★用计数器而不是时钟：本项目测试桩里 GetTime 是定值，时钟限频会让第二次调用永远被挡住）。
local W_CANCEL_ICON, W_CANCEL_ICON_TRIES = nil, 0
local W_CANCEL_ICON_WANT = { "Kick", "Interrupt", "Counterspell", "Silence", "Stop" }
local function wMacroIconScan()
  if W_CANCEL_ICON ~= nil then return W_CANCEL_ICON or nil end -- false = 已定型「没有」
  if W_CANCEL_ICON_TRIES >= 3 then return nil end
  W_CANCEL_ICON_TRIES = W_CANCEL_ICON_TRIES + 1
  if type(GetNumMacroIcons) ~= "function" or type(GetMacroIconInfo) ~= "function" then
    W_CANCEL_ICON = false -- 本客户端没有这个接口 → 定型（别再每次开菜单都探一遍）
    return nil
  end
  local okn, n = pcall(GetNumMacroIcons)
  n = okn and tonumber(n) or nil
  if not n or n < 1 then return nil end -- 接口在但一枚都没有（可能还没就绪）→ 不缓存，下次再试
  local list = {}
  for i = 1, n do
    local oki, pth = pcall(GetMacroIconInfo, i)
    if oki and type(pth) == "string" and pth ~= "" then table.insert(list, pth) end
  end
  if table.getn(list) == 0 then return nil end
  for wi = 1, table.getn(W_CANCEL_ICON_WANT) do
    local kw = W_CANCEL_ICON_WANT[wi]
    for ai = 1, table.getn(list) do
      if string.find(list[ai], kw, 1, true) then W_CANCEL_ICON = list[ai] return list[ai] end
    end
  end
  W_CANCEL_ICON = false -- 扫到了但一个关键字都没命中 → 定型（免得每次开菜单都扫一遍）
  return nil
end
-- 断言入口：清缓存，让「宏图标表 ↔ 取消施法图标」这条链能在测试里被证实（而不是只验缓存）
function EVAL_TEST_MACRO_ICON_RESET() W_CANCEL_ICON, W_CANCEL_ICON_TRIES = nil, 0 return true end

local function wicon(name)
  local s = wslots[name]
  if s and s.tex then return s.tex end
  local pc2 = petCmdOf(name)
  if pc2 then return petIconOf(pc2) end -- 1.32.6 宠物指令专属图标（动作条学习）
  local tsid = targetSelOf(name)
  if tsid then return TARGET_SEL_ICON[tsid] or "Interface\\Icons\\INV_Misc_QuestionMark" end -- ★1.71.3 选取目标专属图标
  if cancelCastOf(name) then -- ★1.71.3 左图标改从客户端宏图标表取（用户要求）；取不到仍**如实**退回问号
    return wMacroIconScan() or "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  if stopAllOf(name) then -- 1.71.3 停止攻击：借「攻击」格的客户端纹理（该格没有就退回问号）
    local ast = wslots["攻击"]
    if ast and ast.tex then return ast.tex end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  if followOf(name) then return ACT_FOLLOW_ICON end -- ★1.71.3 跟随：本插件自带的那张（跟着走）
  local _cbOn, cbNm = cancelBuffOf(name) -- ★1.74.8 取消自身buff：借**那个光环自己的图标**（学习表/动作条）；无名退回问号
  if _cbOn then
    -- ★1.74.9 多选：cbNm 是**集合表**（键=名字）；图标取名单里**第一个**认得出的光环（多个时显示第一个）
    local nm0 = (type(cbNm) == "table" and cbNm.list and cbNm.list[1]) or nil
    if nm0 and nm0 ~= "" then
      local ctx = auraTexKnown(nm0)
      if ctx then return ctx end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  local stname = stanceOf(name) -- 1.43.0 姿态：GetShapeshiftFormInfo 图标（激活态自动亮纹）
  if stname then
    local _si, stex = wFindStance(stname)
    if stex then return stex end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  local iname = itemOf(name) -- 1.32.0 物品：背包图标 → GetItemInfo 缓存 → 问号
  if iname then
    local _, _, tex = wFindBagItem(iname)
    if tex then return tex end
    if type(GetItemInfo) == "function" then
      local ok, _1, _2, _3, _4, _5, _6, _7, itex = pcall(GetItemInfo, iname)
      if ok and itex then return itex end -- 1.12 GetItemInfo 第9返回值=纹理
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  return nil
end

-- 玩家自身 buff 检查（图标比对；0 起始索引）
local function wPlayerHasBuff(tex)
  if not tex then return false end
  if st.playerBuffs then return st.playerBuffs[tex] and true or false end -- 优先读状态表
  if type(GetPlayerBuff) ~= "function" then return false end
  for i = 0, 31 do
    local bi = GetPlayerBuff(i, "HELPFUL")
    if not bi or bi == -1 then break end
    local ok, t = pcall(GetPlayerBuffTexture, bi)
    if ok and t and t == tex then return true end
  end
  return false
end

-- 目标 debuff 检查（UnitDebuff 返回图标路径，直接与技能图标比对）
local function wTargetHasDebuff(tex)
  if not tex then return false end
  if st.targetDebuffs then return st.targetDebuffs[tex] and true or false end -- 优先读状态表
  for i = 1, 16 do
    local dtex = UnitDebuff("target", i)
    if not dtex then break end
    if dtex == tex then return true end
  end
  return false
end

-- ===== 实时光环清单（1.27.0）：编辑窗 debuff/buff 条件下拉列出「当前目标 debuff / 当前自身 buff」 =====
-- 名称读取走 GameTooltip:SetUnitDebuff/SetPlayerBuff 填 tooltip 再读 GameTooltipTextLeft1（同 wactionName 法）；
-- 名称→纹理即时学习（EVAL_HELP_CONFIG.war.debuffTex 持久化，cfg 未加载时落 EVAL_DEBUFF_TEX_LEARN 运行时兜底）：
-- 学到后，怪给的非动作条 debuff 也能做 有/无debuff 图标比对（texOf 回退查学习表）。
EVAL_DEBUFF_TEX_LEARN = EVAL_DEBUFF_TEX_LEARN or {}

local function learnAuraTex(name, tex)
  if not (name and tex and name ~= "") then return end
  local store = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex) or EVAL_DEBUFF_TEX_LEARN
  store[name] = tex
end

-- 光环名 → 纹理。
-- ★注意这里是**给上面已前置声明的 local 赋值**（不是新建 local）——改了会连带断掉
--   队伍选人判据那边的引用（它们在声明点之前，只能看到前置声明的那个 local）。
--
-- ★★★1.71.2（第十一轮）**学习表优先于动作条**（原来反了，这就是骑士光环判定失败的真因）。
--   【用户实测证据】作为**动作条格子 9** 的虔诚光环，
--   `GetActionTexture(9)` 返回 `Spell_Nature_WispSplode_TEX`（**其它法术的图标**），
--   而它在增益条上的**真实图标**是 `Spell_Holy_DevotionAura_TEX` → 拿动作条图标去比对**永远不命中**
--   → 「自身buff检查=否」永远成立 → 无限重复施放。
--   ★判据：**动作条图标只是代理；从增益条亲自观察到的纹理才是权威**。
--     学习表由 EVAL_PLAYER_BUFF_LIST / EVAL_TARGET_*_LIST 在**真实光环**上读出名字+纹理后写入 → 它才是镜子里那个。
--   ★为什么不担心影响施法：施法走的是 wslots 的**格子号**（另一条路），不经过本函数。
function auraTexOf(n)
  local learned = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex and EVAL_HELP_CONFIG.war.debuffTex[n])
    or (EVAL_DEBUFF_TEX_LEARN and EVAL_DEBUFF_TEX_LEARN[n])
  if learned then return learned end
  local s = wslots[n]
  if s and s.tex then return s.tex end
  return nil
end

-- ★★★1.71.2（第十轮）光环名 → 纹理，**解析不出就返回 nil，让调用方如实失败**。
--   为什么必须有它（用户实测事故）：骑士「虔诚光环」在动作条上没有对应格子、也没进过学习表，
--   于是 auraTexOf 回 nil；而旧写法 `st.playerBuffs[texOf(cd.s) or ""]` 会退化成查空串 = nil → cnt=0
--   → 「否/无」方向被当成**成立** → **规则无限重放**（用户日志里同一条反复刷屏）。
--   ★判据：**「查不到」与「没有」是两件事**——查不到必须如实报错，不能默认成「没有」。
--   ★这也是本项目「静默失败族」的又一例：不报错、不崩、行为却错。
-- ★注意：这里是**给上面已前置声明的 local 赋值**（不是新建 local）——同上，改了会断掉引用。
function auraTexKnown(name)
  if type(name) ~= "string" or name == "" then return nil end
  return auraTexOf(name)
end

-- ★★★1.71.2（第十二轮，用户要求：「能否通过名称判断，有些法术图标是不同的」）
--   **名字判定**：图标不可靠（有些法术的**动作条图标 ≠ 光环图标**——实测虔诚光环动作条给
--   `Spell_Nature_WispSplode`、增益条给 `Spell_Holy_DevotionAura`），**名称才是稳定标识**。
--   ★频率防护三层（工具读名很贵：每个 buff 一次 SetPlayerBuff + GetText）：
--     ① 只在**图标比对没命中**时才做 → 正常路径**零开销**；
--     ② 每个列表最多 AURA_NAME_MIN 秒重扫一次，结果缓存；
--     ③ 顺带 learnAuraTex 把正确的「名字→图标」学下来 → 之后自动回**快路径**（自愈）。
--   ★第③层是关键：不做自愈的话，命中一次就要永远付工具读名的代价。
local AURA_NAME_MIN = 0.5
local auraNameCache = {}
-- ★★★1.72.2（分享方案事故）**三态**：true=命中 / false=**扫描干净跑完**且确实不在 / nil=不可信。
--   【事故】分享出去的方案在别人角色上：`debuffTex` 学习表是**每角色**的、目标身上的 debuff（如「十字军审判」）
--     又不是对方动作条上的技能 → `auraTexKnown` 两条路都回 nil → 判定以「纹理未记录」直接失败
--     → 条件恒假、技能永远不放（用户日志：十字军圣印/正义圣印跳过）。
--   【为什么旧版够不到】旧 `auraNameHit` 只回 true/false，分不清「扫描器没跑」与「跑了、确实没有」；
--     而调用点又写成「纹理解析不出就先 return」，于是按名字兜底**只在纹理已知时**才到达 —— 恰是最不需要它的时候。
--   ★判据：① **命中永远可信**（读到名字就是有，哪怕扫描残缺）；
--           ② 「确实没有」只有在**扫描可信**（跑完且每个有光环的槽都读到了名字）时才敢下结论；
--           ③ 其余一律 nil → 调用方必须**如实失败**（1.71.2「查不到 ≠ 没有」的铁律不破）。
local function auraNameHit(name, key, provider)
  if type(name) ~= "string" or name == "" then return nil end
  if type(provider) ~= "function" then return nil end
  local now = (type(GetTime) == "function") and GetTime() or 0
  local c = auraNameCache[key]
  if not (c and (now - c.t) < AURA_NAME_MIN) then
    local set = {}
    local okRun, list, okScan = pcall(provider) -- provider 第二返回 = 本次扫描是否可信
    if okRun and type(list) == "table" then
      for _, d in ipairs(list) do
        if type(d) == "table" and type(d.name) == "string" and d.name ~= "" then set[d.name] = true end
      end
    end
    c = { t = now, set = set, ok = (okRun and okScan) and true or false }
    auraNameCache[key] = c
  end
  if c.set[name] then return true end
  if c.ok then return false end
  return nil
end
-- ★测试用：清空名字缓存（模块级状态，跨用例必须可重置）
function EVAL_AURA_TEST_RESET_NAME_CACHE() auraNameCache = {} end

-- ★★★1.72.2 光环**两级解析**统一入口：① 纹理快路径（学习表/动作条）→ ② 名字慢路径（工具读名，限频 0.5s，命中即自愈学习）。
--   返回 (cnt, unknown)：unknown=true = **两条路都认不出这个光环** → 调用方必须如实失败，
--   **绝不能当成「没有」**（1.71.2 铁律：查不到 ≠ 没有；旧写法就是这里退化成 0 → 规则无限重放）。
--   texStore 传 st.playerBuffs / st.playerDebuffs / st.targetBuffs / st.targetDebuffs。
local function auraCountOf(cd, texStore, key, provider, typeStore)
  -- ★★★1.74.6 名称留空 + 指定了「负面类型」= **有任意该类型负面**（与队伍debuff 同一套语义）：
  --   按类型平行表数命中项，层数取命中项里的**最大值**（lim=1 即「存在」；lim=N 即「有一条叠到 N 层」）。
  if (cd.s == nil or cd.s == "") and cd.dt ~= nil and typeStore ~= nil then
    local mx, hits = 0, 0
    for tex2, t2 in pairs(typeStore) do
      if dispelMatch(t2, cd.dt) then
        hits = hits + 1
        local n2 = tonumber(texStore and texStore[tex2]) or 1
        if n2 > mx then mx = n2 end
      end
    end
    return (hits > 0) and mx or 0, false
  end
  local tex = auraTexKnown(cd.s)
  local cnt = tex and texStore and texStore[tex] or nil
  if cnt then
    -- ★1.74.6 指定了类型：**名字对上了但类型不符 → 视为没有**（正向不误判、反向不误放行）
    if cd.dt ~= nil and typeStore ~= nil then
      if not dispelMatch(typeStore[tex], cd.dt) then cnt = 0 end
    end
  else
    local hit = auraNameHit(cd.s, key, provider)
    if hit == true then cnt = 1
    elseif hit == nil and not tex then return nil, true end -- 既没纹理、名字扫描也不可信 → 如实失败
  end
  return cnt, false
end

-- 当前目标 debuff 实时清单：[{name,tex},...]（每次调用现场扫描 + 学习）
function EVAL_TARGET_DEBUFF_LIST()
  local list = {}
  if not (UnitExists("target") and type(UnitDebuff) == "function") then return list, false end
  if not (WTT and WTT.SetUnitDebuff) then return list, false end
  if not EVAL_WTT_MAY_READ() then return list, false end -- ★1.73.14 玩家正看 tooltip 时不读（如实判「不可信」）
  pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  -- ★1.72.2 第二返回 = **本次扫描是否可信**：只有「每个有光环的槽都读到了名字」才算干净。
  --   读到一半就下结论「没有这个 debuff」是危险的（负向判定会因此放行 → 重放）。
  local slots, named = 0, 0
  for i = 1, 16 do
    local okd, tex = pcall(UnitDebuff, "target", i)
    if not okd or not tex then break end
    slots = slots + 1
    local name
    pcall(function() WTT:ClearLines() end)
    local oks = pcall(WTT.SetUnitDebuff, WTT, "target", i) -- 1.33.2 探针实测：返回值恒 nil 但 tooltip 已填充，built 不能当门槛
    if oks then name = wtText1() end
    if name and name ~= "" then
      named = named + 1
      table.insert(list, { name = name, tex = tex })
      learnAuraTex(name, tex)
    end
  end
  pcall(function() WTT:Hide() end)
  return list, (named == slots)
end

-- 通用光环实时清单（1.54.0）：unit="target"/"player"，harmful=true=debuff / false=buff
local function wScanAuras(unit, harmful)
  local list = {}
  if not UnitExists(unit) then return list, false end
  local api = harmful and UnitDebuff or UnitBuff
  local ttm = WTT and (harmful and WTT.SetUnitDebuff or WTT.SetUnitBuff)
  if type(api) ~= "function" or not ttm then return list, false end
  if not EVAL_WTT_MAY_READ() then return list, false end -- ★1.73.14 同上
  pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
  local slots, named = 0, 0 -- ★1.72.2 同 EVAL_TARGET_DEBUFF_LIST：读全了才算「扫描可信」
  for i = 1, 16 do
    local okd, tex = pcall(api, unit, i)
    if not okd or not tex then break end
    slots = slots + 1
    local name
    pcall(function() WTT:ClearLines() end)
    local oks = pcall(ttm, WTT, unit, i) -- 1.33.2 探针实测：返回值恒 nil 但 tooltip 已填充
    if oks then name = wtText1() end
    if name and name ~= "" then
      named = named + 1
      table.insert(list, { name = name, tex = tex })
      learnAuraTex(name, tex)
    end
  end
  pcall(function() WTT:Hide() end)
  return list, (named == slots)
end
function EVAL_TARGET_BUFF_LIST() local l, ok = wScanAuras("target", false) return l, ok end -- 目标 buff（1.54.0）
function EVAL_PLAYER_DEBUFF_LIST() local l, ok = wScanAuras("player", true) return l, ok end -- 自身 debuff（1.54.0）

-- ★1.74.8 内部索引 → 光环名（供「取消自身buff:名字」按名匹配用）。
--   与 EVAL_PLAYER_BUFF_LIST 同源：同一个隔离 tooltip 读名 —— 「清单里显示叫什么」与
--   「按名字取消时认不认得出」必须是同一面镜子，否则会出现「看得见却取消不掉」。
--   读不出 → nil（调用方据此**如实跳过**，不猜）。
function EVAL_PLAYER_BUFF_NAME(bi)
  if type(bi) ~= "number" or bi < 0 then return nil end
  if not (WTT and WTT.SetPlayerBuff and EVAL_WTT_MAY_READ()) then return nil end
  local nm = nil
  pcall(function()
    WTT:SetOwner(UIParent, "ANCHOR_NONE")
    WTT:ClearLines()
    if WTT.SetPlayerBuff(WTT, bi) then nm = wtText1() end
    WTT:Hide()
  end)
  if type(nm) == "string" and nm ~= "" then return nm end
  return nil
end

-- 当前自身 buff 实时清单（GetPlayerBuff 0 起始索引 + SetPlayerBuff 读名）
function EVAL_PLAYER_BUFF_LIST()
  local list = {}
  -- ★1.72.2 第二返回 = **本次扫描是否可信**（每个「看到的光环」都进了清单且读到了名字）。
  --   ``ran`` = 两条路径是否真的跑过（都没有 → 不可信，调用方必须如实失败）。
  local ran, slots, named = false, 0, 0
  local function tooltipName() return wtText1() end -- ★1.73.14 读**自家** tooltip 那一行
  if type(GetPlayerBuff) == "function" and WTT and WTT.SetPlayerBuff and EVAL_WTT_MAY_READ() then
    ran = true
    pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
    for i = 0, 31 do
      local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
      if not okb or type(bi) ~= "number" or bi < 0 then break end
      slots = slots + 1
      local okt, tex = pcall(GetPlayerBuffTexture, bi)
      local name
      pcall(function() WTT:ClearLines() end)
      local oks = pcall(WTT.SetPlayerBuff, WTT, bi) -- 1.33.2 同探针实测：built 恒 nil 但 name 可读
      if oks then name = tooltipName() end
      if name and name ~= "" and okt and tex then
        named = named + 1
        table.insert(list, { name = name, tex = tex })
        learnAuraTex(name, tex)
      end
    end
    pcall(function() WTT:Hide() end)
  end
  -- 1.32.10 兜底：一个名字都没读到时换 UnitBuff+SetUnitBuff 路径（本客户端 SetPlayerBuff
  -- 读名可能失败——药品类 buff 不进下拉的病根；SetUnitBuff 与已验证的 SetUnitDebuff 同族）
  if table.getn(list) == 0 and type(UnitBuff) == "function" and WTT and WTT.SetUnitBuff and EVAL_WTT_MAY_READ() then
    ran = true
    slots, named = 0, 0 -- 换路径重新计（同一条光环不能算两次）
    pcall(function() WTT:SetOwner(UIParent, "ANCHOR_NONE") end)
    for i = 1, 32 do
      local oku, tex = pcall(UnitBuff, "player", i)
      if not oku or not tex then break end
      slots = slots + 1
      local name
      pcall(function() WTT:ClearLines() end)
      local oks = pcall(WTT.SetUnitBuff, WTT, "player", i) -- 1.33.2 同探针实测
      if oks then name = tooltipName() end
      if name and name ~= "" then
        named = named + 1
        table.insert(list, { name = name, tex = tex })
        learnAuraTex(name, tex)
      end
    end
    pcall(function() WTT:Hide() end)
  end
  return list, (ran and named == slots)
end

-- 技能冷却是否就绪；不就绪时返回剩余秒数说明
local function wready(name)
  local iname = itemOf(name) -- 1.32.0 物品冷却走背包 API
  if iname then
    local bag, slot = wFindBagItem(iname)
    if not bag then return false, "背包未找到" end
    local okc, start, dur = pcall(GetContainerItemCooldown, bag, slot)
    if not okc then return false, "冷却查询失败" end
    if (start or 0) == 0 and (dur or 0) == 0 then return true end
    local left = (start or 0) + (dur or 0) - GetTime()
    return false, string.format("冷却剩 %.1fs", left > 0 and left or 0)
  end
  local stname2 = stanceOf(name) -- 1.43.0 姿态冷却走姿态栏 API；已在该姿态=不就绪（防止德鲁伊形态被再按取消）
  if stname2 then
    local si, _t, active, castable = wFindStance(stname2)
    if not si then return false, "无该姿态栏位" end
    if active then return false, "已在该姿态" end
    if not castable then return false, "不可用" end
    if type(GetShapeshiftFormCooldown) == "function" then
      local okc, start, dur = pcall(GetShapeshiftFormCooldown, si)
      if okc and (start or 0) > 0 and (dur or 0) > 0 then
        local left = start + dur - GetTime()
        if left > 0 then return false, string.format("冷却剩 %.1fs", left) end
      end
    end
    return true
  end
  if cancelCastOf(name) then -- 1.47.0 取消施法：仅在读条/引导中有意义
    if st.castName or (st.castUntil and st.castUntil > GetTime()) then return true end
    return false, "未在施法"
  end
  if stopAllOf(name) then -- 1.71.3 停止攻击：无冷却、不占动作条 → 恒就绪（真在做什么由 wuse 里如实记录）
    return true
  end
  if followOf(name) then -- ★1.71.3 跟随：不占动作条、无冷却 → 恒就绪（能否跟上由客户端判定，wuse 里如实记账）
    return true
  end
  if cancelBuffOf(name) then -- ★1.74.8 取消自身buff：不占动作条、无冷却 → 恒就绪（身上有没有由 wuse 里如实记录）
    return true
  end
  local s = wslots[name]
  if not s then return false, "不在动作条" end
  local ok, start, dur = pcall(GetActionCooldown, s.slot)
  if not ok then return false, "冷却查询失败" end
  if (start or 0) == 0 and (dur or 0) == 0 then return true end
  local left = (start or 0) + (dur or 0) - GetTime()
  return false, string.format("冷却剩 %.1fs", left > 0 and left or 0)
end

-- 出手一个技能：写动作日志（文件必写；wdebug 时同步聊天框）
-- ★★★1.72.4 「释放指定等级」的官方判据（本机 api_spell.html 原文）：
--   · `CastSpell(id, bookType)` → **Protected: yes**（插件不能直调）
--   · `CastSpellByName(name)` → Protected，**但 name 可以带括号等级**：
--       "name may include rank in parentheses, for example Fireball(Rank 3)；
--        text inside the parentheses must match the spell's subtext exactly；
--        With no parentheses, the last known [rank]"  → 这就是指定等级的写法，Protected 走 RunScript 绕行。
--   · `GetSpellName(spellID, bookType)` → **第二返回就是 rank/subtext**（中文客户端形如「等级 3」）
--       → 等级列表直接从**法术书**枚举，不需要 tooltip、也不需要占动作格。
--   ★频率防护：法术书扫描按名字缓存 SB_TTL 秒（一次扫描可能上百次 API 调用，绝不能每次按键都扫）。
-- ★1.72.4 等级排序（用户要求：下拉里**从低到高**排，别按法术书里那副乱序）。
--   ★必须按**数字**比，不能按字符串：字符串序下「等级 10」会排在「等级 3」前面（真坑）。
--   ★取不到数字的（subtext 不含数字，如「变形」）排在**最后**，并保持它们彼此的原有顺序。
--   ★table.sort 在 5.1 里**不稳定** → 用「数字 + 原始下标」做全序装饰排序（同一份输入永远同一结果）。
local function sbRankNum(sub)
  local n = string.match(tostring(sub or ""), "(%d+)")
  return n and tonumber(n) or nil
end
local function sbSortRanks(list)
  local d = {}
  for i, v in ipairs(list) do d[i] = { v = v, n = sbRankNum(v), i = i } end
  table.sort(d, function(a, b)
    if a.n and b.n then
      if a.n ~= b.n then return a.n < b.n end
      return a.i < b.i
    end
    if a.n then return true end
    if b.n then return false end
    return a.i < b.i
  end)
  local out = {}
  for i = 1, table.getn(d) do out[i] = d[i].v end
  return out
end

local sbCache, SB_TTL = {}, 2
function EVAL_SPELLBOOK_RANKS(name)
  if type(name) ~= "string" or name == "" then return {} end
  local now = (type(GetTime) == "function") and GetTime() or 0
  local c = sbCache[name]
  if c and (now - c.t) < SB_TTL then return c.list end
  local out = {}
  if type(GetNumSpellTabs) == "function" and type(GetSpellTabInfo) == "function" and type(GetSpellName) == "function" then
    local okt, nt = pcall(GetNumSpellTabs)
    if okt and type(nt) == "number" then
      for tab = 1, nt do
        local ok1, _tn, _tex, off, num = pcall(GetSpellTabInfo, tab)
        if ok1 and type(off) == "number" and type(num) == "number" then
          for i = off + 1, off + num do
            local ok2, nm, sub = pcall(GetSpellName, i, "spell")
            if ok2 and nm == name and type(sub) == "string" and sub ~= "" then
              local dup = false
              for _, v in ipairs(out) do if v == sub then dup = true break end end
              if not dup then table.insert(out, sub) end
            end
          end
        end
      end
    end
  end
  out = sbSortRanks(out) -- ★1.72.4 顺序在这里定一次（下拉与任何未来调用者共用同一份「从低到高」）
  sbCache[name] = { t = now, list = out }
  return out
end
-- 该「名字+等级」是否**真实存在**（CastSpellByName 要求括号内与 subtext 逐字相符，猜错会静默失败）
function EVAL_SPELLBOOK_HAS(name, rank)
  for _, v in ipairs(EVAL_SPELLBOOK_RANKS(name)) do if v == rank then return true end end
  return false
end
-- 测试用：清空法术书缓存（模块级状态必须可重置）
function EVAL_SPELLBOOK_TEST_RESET() sbCache = {} end

local function wuse(name, reason, rank)
  -- ★1.72.4 指定等级：`CastSpellByName("名(等级 N)")`（Protected → RunScript 绕行），**不占动作格**
  if rank and rank ~= "" then
    if not EVAL_SPELLBOOK_HAS(name, rank) then
      -- ★绝不静默放行：等级拼错/该等级没学过 → 如实报错（CastSpellByName 括号内必须与 subtext 逐字相符）
      wlog(name .. "跳过: 法术书里没有「" .. tostring(name) .. "(" .. tostring(rank) .. ")」这个等级")
      return false
    end
    if type(RunScript) ~= "function" then wlog(name .. "跳过: 本客户端没有 RunScript") return false end
    local esc = function(s) return (string.gsub(string.gsub(tostring(s), "\\", "\\\\"), '"', '\\"')) end
    pcall(RunScript, 'CastSpellByName("' .. esc(name) .. "(" .. esc(rank) .. ')"' .. ')')
    local rline = string.format("→ %s(%s) (%s)", name, rank, reason)
    EVAL_LOGLINE(rline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. rline .. "|r") end
    return true
  end
  local pc = petCmdOf(name)
  if pc then
    -- 宠物指令（1.30.0）：不占动作条，直接调 Pet API；无宠物时静默跳过
    if type(HasPetUI) == "function" then
      local okh, hasPet = pcall(HasPetUI)
      if okh and not hasPet then wlog(name .. "跳过: 无宠物") return false end
    end
    local fn = getglobal(PET_CMD_FN[pc])
    if type(fn) ~= "function" then wlog(name .. ": 无宠物指令函数") return false end
    pcall(fn)
    local pline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(pline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. pline .. "|r") end
    return true
  end
  local ts, tsnm = targetSelOf(name)
  if ts then
    -- 选取目标技能级（1.32.0）：执行切换即算出手；日志记切换后的目标名
    local fn = getglobal(TARGET_SEL_FN[ts])
    if type(fn) ~= "function" then wlog(name .. ": 无选取函数") return false end
    local okc, ret
    -- ★1.75.10 带名字参数的选取器（指定名称 / 玩家的目标）统一走这一支
    -- ★1.75.12 三条一律走**唯一调用口** tselInvoke（取证：谁调的 + 调用前后的目标快照）
    local tHow = "技能行:" .. tostring(name)
    if TARGET_SEL_NM[ts] then
      okc, ret = tselInvoke(tHow, TARGET_SEL_FN[ts], fn, tsnm)
    elseif TARGET_SEL_ARG[ts] then
      -- ★1.70.47 技能行也可以直接是「选取目标:队伍成员/团队成员」：teamPickArg.rule 由**调用方**塞入
      --   （那一行自己的条件列表 = 候选过滤条件）。这里**绝不能清掉它**——清掉 = 过滤器失效且**静默**。
      TARGET_SEL_ARG_LAST = ts
      okc, ret = tselInvoke(tHow, TARGET_SEL_FN[ts], fn, TARGET_SEL_ARG[ts])
      TARGET_SEL_ARG_LAST = nil
    else
      okc, ret = tselInvoke(tHow, TARGET_SEL_FN[ts], fn)
    end
    if not okc then wlog(name .. " 选取目标调用失败（pcall 捕获）") return false end
    -- ★★1.75.10「玩家的目标」如实报账：AssistByName 之后**没有目标** = 这次选取**没生效**
    --   （该玩家不在附近 / 他自己没有目标）。若照旧写「→ … | 当前目标:无」并 return true，
    --   日志看着像成功，后面的技能却打在**旧目标**上（与 1.71.3 成员选取器那次同族）。
    if TARGET_SEL_NEEDTGT[ts] and not UnitExists("target") then
      local fline = string.format("%s 未生效：协助 %s 之后没有目标（该玩家不在附近或他自己没有目标）", name, tostring(tsnm or "?"))
      EVAL_LOGLINE(fline)
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff8080" .. fline .. "|r") end
      return false
    end
    -- ★★1.71.3 成员选取器（队伍/团队成员）**如实报账**：旧版无论选没选到人都写「→ … | 当前目标:X」
    --   并返回 true —— 用户看到日志像成功了，实际目标没换、后面的技能打在旧目标上，
    --   于是「功能不工作」却查不出原因（本轮用户实测报回）。
    --   现在：命中 → 写清**谁被选中 + 血量/法力% + 满足的条件明细**；
    --        没命中 → 明说「未选中成员」+ 候选清单 + 提示，并 **return false**（如实：这次没出手）。
    if TARGET_SEL_TEAMSEL[ts] then
      local detail = tostring(teamPickInfo.text or "")
      if ret ~= nil then
        local tline = string.format("→ %s（命中:%s）| 当前目标:%s", name, detail, UnitName("target") or "无")
        EVAL_LOGLINE(tline)
        if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. tline .. "|r") end
        return true
      end
      local fline = string.format("%s 未选中成员：%s", name, detail)
      EVAL_LOGLINE(fline)
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff8080" .. fline .. "|r") end
      return false
    end
    local tline = string.format("→ %s (%s) | 当前目标:%s", name, reason, UnitName("target") or "无")
    EVAL_LOGLINE(tline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. tline .. "|r") end
    return true
  end
  local iname = itemOf(name)
  if iname then
    -- 物品使用（1.32.0）：UseContainerItem——消耗品直接使用，装备自动穿上；背包未找到静默跳过
    local bag, slot = wFindBagItem(iname)
    if not bag then wlog(name .. "跳过: 背包未找到") return false end
    pcall(UseContainerItem, bag, slot)
    local iline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(iline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. iline .. "|r") end
    return true
  end
  local stname3 = stanceOf(name)
  if stname3 then
    -- 姿态切换（1.43.0）：CastShapeshiftForm 不受保护；已在该姿态时跳过（战士姿态 no-op，德鲁伊形态会被取消——必须守门）
    local si, _t, active = wFindStance(stname3)
    if not si then wlog(name .. "跳过: 无该姿态栏位") return false end
    if active then wlog(name .. "跳过: 已在该姿态") return false end
    if type(CastShapeshiftForm) ~= "function" then wlog(name .. ": 无姿态切换函数") return false end
    pcall(CastShapeshiftForm, si)
    local sline = string.format("→ %s (%s)", name, reason)
    EVAL_LOGLINE(sline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. sline .. "|r") end
    return true
  end
  if cancelCastOf(name) then
    -- 取消施法（1.47.0）：未在读条时静默跳过（条件里建议配 施法中:X）。
    -- ★1.71.3：**保留原始的 SpellStopCasting 方式**（Protected → RunScript 排队，1.49.3 已验证通道）。
    --   用户实测它在本客户端**只清本地进度条**、服务端读条照旧（「进度条没了、法术还在放」）；
    --   用户判断「可能是客户端 bug」→ **功能先留着**，客户端修好即自动生效。移动脉冲那条路实测无效、已删。
    if not (st.castName or (st.castUntil and st.castUntil > GetTime())) then wlog(name .. "跳过: 未在施法") return false end
    local okCast, how = EVAL_STOP_CAST()
    if not okCast then wlog(name .. "跳过: " .. tostring(how)) return false end
    local cline = string.format("→ %s (%s) | 停止: %s", name, reason, tostring(how))
    EVAL_LOGLINE(cline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. cline .. "|r") end
    return true
  end
  if stopAllOf(name) then
    -- 停止攻击（1.71.3 用户要求「类似按 ESC」）：停读条 + 停自动射击/魔杖自动重复 + 停近战普攻。
    -- 三条通道各自独立，缺哪条如实写日志——绝不假装做到（判据与守卫的官方依据见 stopAllOf 上方注释）。
    local stopped = {}
    local casting = (st.castName or (st.castUntil and st.castUntil > GetTime())) and true or false
    local repeating = nil
    for _, rn in ipairs({ "自动射击", "射击" }) do
      local rs = wslots[rn]
      if rs and type(IsAutoRepeatAction) == "function" then
        local okr, rv = pcall(IsAutoRepeatAction, rs.slot)
        if okr and rv then repeating = rn break end -- 自动重复只会有一个（文档：currently repeating）
      end
    end
    if casting or repeating then
      -- ★读条与自动重复**共用同一条通道**（文档：SpellStopCasting 先取消 auto-shot/自动重复，否则打断读条）
      --   ★1.71.3 实测：它在本客户端**只清本地进度条**（真中断做不到，见 EVAL_STOP_CAST 注释）——功能先留着。
      local okCast, how = EVAL_STOP_CAST()
      if okCast then
        if casting then table.insert(stopped, "读条(" .. tostring(how) .. ")") end
        if repeating then table.insert(stopped, repeating .. "停止") end
      end
    end
    local meleeAtk = wslots["攻击"]
    local meleeOn = false
    if meleeAtk and type(IsCurrentAction) == "function" then
      local okc, cur = pcall(IsCurrentAction, meleeAtk.slot)
      meleeOn = (okc and cur) and true or false
    end
    if meleeOn and type(AttackTarget) == "function" then
      pcall(AttackTarget) -- 非 Protected（文档无标注）→ 直调；同 1.50.0 自动攻击那条已验证通道
      table.insert(stopped, "普攻")
    end
    local did = (table.getn(stopped) > 0) and ("停止: " .. table.concat(stopped, "+")) or "无可停止的动作（未观测到读条/自动射击/普攻）"
    if not meleeAtk then did = did .. "（普攻未判定：动作条上没有「攻击」）" end
    local sline = string.format("→ %s (%s) | %s", name, reason, did)
    EVAL_LOGLINE(sline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. sline .. "|r") end
    return true
  end
  local cbOn, cbName = cancelBuffOf(name)
  if cbOn then
    -- 取消自身buff（1.74.8）：见 cancelBuffOf 上方的 API 核查注释。
    -- ★三条硬纪律：① CancelPlayerBuff 收**内部索引**（不是槽位号）；
    --   ② 拿不到索引 → **如实失败**，绝不瞎猜一个索引去取消别的光环；
    --   ③ 「身上没有」是**跳过**（不是成功，也不是报错）——与「取消施法」同族的空操作语义。
    local function cbskip(msg)
      local sl = name .. "跳过: " .. msg
      EVAL_LOGLINE(sl)
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff8080" .. sl .. "|r") end
    end
    if type(GetPlayerBuff) ~= "function" then cbskip("客户端没有 GetPlayerBuff（取消失败）") return false end
    if type(CancelPlayerBuff) ~= "function" then cbskip("客户端没有 CancelPlayerBuff（不可用）") return false end
    -- 收集目标：指定名字 → 只有它；不指定 → **全部可取消的自身增益**（CANCELABLE 过滤天然排除不可取消的）
    local targets = {}
    for i = 0, 31 do
      local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL|CANCELABLE")
      if not okb or type(bi) ~= "number" or bi < 0 then break end
      -- ★1.74.9 多选：cbName 是**名单表**（cancelBuffOf 第二返回）；
      --   匹配 = 「这个光环的名字在名单里」。名单只存**集合**（cancelBuffOf 返回的表）：
      --   单个名字时集合里就一个，与旧单名行为逐字一致。
      local named = (type(cbName) == "table")
      if named then
        local bn = EVAL_PLAYER_BUFF_NAME(bi)
        if bn and cbName[bn] then table.insert(targets, bi) end
      else
        table.insert(targets, bi)
      end
    end
    if table.getn(targets) == 0 then
      local want = (type(cbName) == "table" and cbName.list) and table.concat(cbName.list, "、") or nil
      cbskip(want and ("身上没有「" .. want .. "」") or "身上没有可取消的增益")
      return false
    end
    local done = 0
    for _, bi in ipairs(targets) do
      if pcall(CancelPlayerBuff, bi) then done = done + 1 end
    end
    if done == 0 then cbskip("取消调用全部失败") return false end
    local wantNames = (type(cbName) == "table" and cbName.list) and table.concat(cbName.list, "、") or nil
    local cline = string.format("→ %s (%s) | 取消 %d 个自身增益%s", name, reason, done,
      wantNames and ("：" .. wantNames) or "")
    EVAL_LOGLINE(cline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. cline .. "|r") end
    return true
  end
  local fok2, fname2 = followOf(name)
  if fok2 then
    -- 跟随（1.71.3 用户要求「角色行为 添加: 跟随:名字输入」）：FollowByName **直调**（文档 not protected）。
    --   ★它**没有返回值**：调用后能不能真的跟上由客户端判定（客户端自己会弹错误）→ 我们**只如实记账**，不假装成功。
    --   ★为什么不预扫队伍/团队去核对名字：客户端只认「它已知的玩家对象」，而且一次执行最多要 40 次 UnitName
    --     （频率风险）→ 不值得；名字认不出来时**客户端自己会提示**，我们只把这件事写在注释与文档里。
    -- ★守卫提示必须用 EVAL_LOGLINE（**这才是环形缓冲的写入口**，/eh logdump 看得到）；wlog 只在开 wdebug 时说一句。
    local function fskip(msg)
      local sl = name .. "跳过: " .. msg
      EVAL_LOGLINE(sl)
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff8080" .. sl .. "|r") end
    end
    if type(FollowByName) ~= "function" then fskip("客户端没有 FollowByName（跟随不可用）") return false end
    local who = tostring(fname2 or "")
    if who ~= "" then
      local okme, me = pcall(UnitName, "player")
      if okme and type(me) == "string" and me ~= "" and string.lower(me) == string.lower(who) then
        fskip("不能跟随自己（文档原文 You cannot follow yourself）")
        return false
      end
    else
      local oke, ex = pcall(UnitExists, "target")
      if oke and not ex then fskip("没给名字，且当前没有目标可以跟") return false end
    end
    local okf = pcall(FollowByName, (who ~= "") and who or nil)
    local fline = string.format("→ %s (%s) | 跟随: %s%s（本接口无返回值，能否跟上由客户端判定）",
                                name, reason, (who ~= "") and who or "当前目标", okf and "" or " · 调用失败(pcall)")
    EVAL_LOGLINE(fline)
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. fline .. "|r") end
    return true
  end
  local s = wslots[name]
  if not s then wlog(string.format("%s: %s，但技能不在动作条", name, reason)) return false end
  UseAction(s.slot)
  local line = string.format("→ %s (%s) | %s%d", name, reason, (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), UnitMana("player")) -- 1.49.2 怒气硬编码→动态（法力/怒气/集中值）
  EVAL_LOGLINE(line)
  if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cff7fff7f" .. line .. "|r") end
  return true
end

-- ============ 配置化技能释放规则引擎（条件全部读 EVAL_HELP_STATE） ============
-- 一条规则 = { skill="技能名", when={...条件...}, why="日志原因" }，按顺序评估，第一条全过的出手。
-- 条件字段（→ 状态表字段；缺失的已补进状态模块）：
--   combat=bool            → inCombat        战斗中/非战斗
--   combatTime={">",3}    → combatTime      进战秒数
--   hpPct / power / powerPct / tHpPct = {op,n}  自身血% / 能量值 / 能量% / 目标血%
--   canAttack=true         → canAttack       释放对象：敌对可攻击
--   canBleed=bool          → canBleed        目标可流血
--   isBoss / isElite=bool  → isBoss/isElite  目标分级
--   tInCombat=bool         → tInCombat       目标战斗中
--   form=1 或 "战斗姿态"   → formIndex/form  当前姿态；formNot=1 取反
--   alt / shift / ctrl=bool → 修饰键（猛击 Alt 门等）
--   autoAttack=bool        → autoAttack      普攻开关
--   hasBuff / noBuff="战斗怒吼"    → playerBuffs（按动作条图标比对）
--   hasDebuff / noDebuff="断筋"    → targetDebuffs
-- 技能侧条件（走动作条 API）：ready=true 冷却就绪 / usable=true 可用（压制类）/ notQueued=true 未排队
-- 本客户端做不了：目标施法中打断（无 UnitCastingInfo）、距离、挥击计时。
-- 用法：宏里也可以直接 /run EVAL_RULE_RUN({ {skill="压制", when={usable=true}} })

-- 比较器：{ ">", 30 } { ">=", 30 } { "<", 50 } { "<=", 50 } { "==", 1 } { "~=", 1 }
local function condCmp(spec, actual)
  if type(spec) == "number" then return actual == spec end
  if type(spec) ~= "table" then return false end
  local op, n = spec[1], spec[2]
  if type(actual) ~= "number" or type(n) ~= "number" then return false end
  if op == ">" then return actual > n
  elseif op == ">=" then return actual >= n
  elseif op == "<" then return actual < n
  elseif op == "<=" then return actual <= n
  elseif op == "==" or op == "=" then return actual == n
  elseif op == "~=" or op == "!=" then return actual ~= n end
  return false
end

-- ★★★1.71.3 「取最接近」的配套（用户定案：= 取最接近 N）：
--   驱动排序的那一条条件在**候选上下文**里**不再要求精确相等**——否则百分比上永远没人通过，
--   又会变成「选了没反应」（正是这轮在修的毛病）。★只放宽**驱动那一条**，其它 = 条件照旧精确比较。
--   ★声明点必须在 condOne 之前（DECL ORDER CHECK 当场抓到过一次：用在前、声明在后）。
local function candNumPass(cd, v)
  if (cd.op == "==" or cd.op == "=") and teamPickArg.driverCd == cd and st.pickCand then return true end
  return condCmp({ cd.op, cd.n }, v)
end

-- 逐条评估 when；返回 true 或 false+第一个不满足的原因（供 wdebug 日志）
local function condOK(when, skill)
  local function texOf(n) return auraTexOf(n) end -- 动作条 + 学习表回退（1.27.0）
  if when.combat ~= nil and st.inCombat ~= when.combat then return false, "战斗状态不符" end
  if when.combatTime and not condCmp(when.combatTime, st.combatTime) then return false, "进战时间不符" end
  if when.combo and not condCmp(when.combo, st.combo or 0) then return false, "连击点不符" end
  if when.hpPct and not condCmp(when.hpPct, st.hpPct) then return false, "自身血%不符" end
  if when.power and not condCmp(when.power, st.power) then return false, "能量不符" end
  if when.powerPct and not condCmp(when.powerPct, st.powerPct) then return false, "能量%不符" end
  if when.tHpPct and not condCmp(when.tHpPct, st.tHpPct) then return false, "目标血%不符" end
  if when.canAttack ~= nil and st.canAttack ~= when.canAttack then return false, "目标不可攻击" end
  if when.canBleed ~= nil and st.canBleed ~= when.canBleed then return false, "流血条件不符" end
  if when.isBoss ~= nil and st.isBoss ~= when.isBoss then return false, "Boss 条件不符" end
  if when.isElite ~= nil and st.isElite ~= when.isElite then return false, "精英条件不符" end
  if when.tInCombat ~= nil and st.tInCombat ~= when.tInCombat then return false, "目标战斗状态不符" end
  if when.form ~= nil then
    if type(when.form) == "number" and st.formIndex ~= when.form then return false, "姿态不符" end
    if type(when.form) == "string" and st.form ~= when.form then return false, "姿态不符" end
  end
  if when.formNot ~= nil and st.formIndex == when.formNot then return false, "姿态冲突" end
  if when.alt ~= nil and st.alt ~= when.alt then return false, "Alt 未按" end
  if when.shift ~= nil and st.shift ~= when.shift then return false, "Shift 未按" end
  if when.ctrl ~= nil and st.ctrl ~= when.ctrl then return false, "Ctrl 未按" end
  if when.autoAttack ~= nil and (st.autoAttack and true or false) ~= when.autoAttack then return false, "普攻状态不符" end
  -- ★★★1.71.2（第十轮）同 condOne：纹理解析不出就**如实失败**，不得退化成「0 层」
  if when.hasBuff then
    local bx = texOf(when.hasBuff)
    if not bx then return false, "缺少buff:无法识别光环「" .. tostring(when.hasBuff) .. "」" end
    if not st.playerBuffs[bx] then return false, "缺少buff:" .. when.hasBuff end
  end
  if when.noBuff then
    local bx = texOf(when.noBuff)
    if not bx then return false, "已有buff:无法识别光环「" .. tostring(when.noBuff) .. "」" end
    if st.playerBuffs[bx] then return false, "已有buff:" .. when.noBuff end
  end
  if when.hasDebuff and not st.targetDebuffs[texOf(when.hasDebuff) or ""] then return false, "目标缺debuff:" .. when.hasDebuff end
  if when.noDebuff and st.targetDebuffs[texOf(when.noDebuff) or ""] then return false, "目标已有debuff:" .. when.noDebuff end
  -- 技能侧条件
  if when.ready then
    local rd, why = wready(skill)
    if not rd then return false, "未就绪:" .. tostring(why) end
  end
  if when.usable then
    local s = wslots[skill]
    if not s then return false, "不可用" end
    -- 1.64.0 修多返回截断：s and pcall(...) 是逻辑表达式，只取 pcall 第一返回值——usable/noMana 恒 nil
    local oku, usable, noMana = pcall(IsUsableAction, s.slot)
    if not (oku and (usable or not noMana)) then return false, noMana and "不可用:资源不足" or "不可用" end -- 1.64.0 只信资源信号
  end
  if when.notQueued then
    local s = wslots[skill]
    if s then
      local okq, q = pcall(IsCurrentAction, s.slot) -- 1.64.0 修多返回截断（q 恒 nil）
      if okq and q then return false, "已排队" end
    end
  end
  return true
end

-- ===== 选取目标条件（1.25.0）：规则求值时切换当前目标（副作用条件，求值通过恒 true） =====
-- 官方文档 emberveil.org/wiki/lua/globals/Targetting；下列均为无参函数，重复调用会在邻近单位间循环（死人跳过）。
-- TargetByName/AssistByName/AssistUnit/TargetUnit 需要名称/UnitID 参数，暂不纳入下拉。
-- 1.29.0 扩展：targetTarget=目标的目标（TargetUnit 带 UnitID 参数，不解析时无动作——比 AssistUnit 安全）；
-- byName=指定名称（TargetByName 带名称参数，cd.nm 存名字；编辑窗下拉给最近 5 敌名 + 自定义输入弹窗）。
-- （TARGET_SEL 表 1.32.0 起上移到 wuse 之前，与 PET_CMD 并列——技能级执行需要）

-- 附近敌人名称枚举（1.29.0，编辑窗「指定名称」下拉用）：客户端无附近单位枚举 API，
-- 用 TargetNearestEnemy 循环选取特性边切边收集，完事恢复原目标（无原目标则清除）。
-- 代价：调用瞬间目标快速切换一轮；同名怪多时 TargetByName 还原的可能不是同一只（可接受）。
-- 1.75.11 加了可选第二参 traceFn：每轮原样回调一次读到的目标名（nil 也回调）。
--   用途 = 近战探针的 /eh go melee 周围 要看清循环是不是在两只怪之间来回跳 ——
--   只在去重后回调的话，同名来回跳会被抹平，数出来的只数会假装更多。
--   既有调用方（编辑窗指定名称下拉）只传 1 个参数，行为完全不变。
function EVAL_NEARBY_ENEMY_NAMES(maxN, traceFn)
  local names, seen = {}, {}
  local orig = UnitName("target")
  for _ = 1, (maxN or 5) do
    tselInvoke("名字枚举", "TargetNearestEnemy", TargetNearestEnemy)
    local n = UnitName("target")
    if type(traceFn) == 'function' then pcall(traceFn, n) end
    if not n or seen[n] then break end
    seen[n] = true
    table.insert(names, n)
  end
  if orig then tselInvoke("名字枚举:还原", "TargetByName", TargetByName, orig)
  else tselInvoke("名字枚举:还原", "ClearTarget", ClearTarget) end
  return names
end

-- ★1.75.10 玩家名候选（编辑窗「选取目标:玩家的目标」的名字下拉用）：**纯只读**枚举，零副作用
--   —— 与上面那条「边切边收集」**相反**：绝不能为了列几个名字去动用户当前的目标
--   （那条是给「指定名称 = 找怪」用的，切一轮可以接受；这条是「协助某人」，切目标本身就是我们要避免的副作用）。
--   顺序 = 自己 → party1..4 → raid1..N；去重 + 按 maxN 截断（默认 12）。
function EVAL_PLAYER_NAMES(maxN)
  local out, seen = {}, {}
  local cap = maxN or 12
  local function push(u)
    if table.getn(out) >= cap then return end
    local ok, n = pcall(UnitName, u)
    if not ok or type(n) ~= "string" or n == "" then return end
    if seen[n] then return end
    seen[n] = true
    table.insert(out, n)
  end
  push("player")
  for i = 1, 4 do push("party" .. i) end
  for i = 1, 40 do push("raid" .. i) end
  return out
end

-- ===== 目标职业条件（1.26.0）：UnitClass 第二返回值（英文 token）比对；多选 = 或关系 =====
local CLASS_LIST = {
  { id = "HUNTER",  name = "猎人" },
  { id = "PRIEST",  name = "牧师" },
  { id = "MAGE",    name = "法师" },
  { id = "WARLOCK", name = "术士" },
  { id = "SHAMAN",  name = "萨满" },
  { id = "ROGUE",   name = "盗贼" },
  { id = "WARRIOR", name = "战士" },
  { id = "DRUID",   name = "德鲁伊" },
  -- ★1.72.4 审计补漏：**原本整张表里没有圣骑士** → 任何 [职业:圣骑士] 的职业过滤都被
  --   解析侧静默丢弃（名单少一个人 = 那个人永远不被选中；不报错、只是永远不生效）。
  --   ★必须**追加在末尾**：CLASS_ID 索引/职业下拉的行号都是按本表下标一一对应的，
  --     插在中间会让已有的行号错位。判据 = 断言组 111 ⑥（模版里的职业名必须都在本表里）。
  { id = "PALADIN", name = "圣骑士" },
}
local CLASS_NAME_BY_ID, CLASS_ID = {}, {} -- CLASS_ID 同时收中文名/英文 token（导入文本两种都认）
for _, c in ipairs(CLASS_LIST) do
  CLASS_NAME_BY_ID[c.id] = c.name
  CLASS_ID[c.name] = c.id
  CLASS_ID[c.id] = c.id
end

-- ===== 目标类型条件（1.70.28）：UnitCreatureType 比对 =====
-- 该 API 在**本客户端曾被记为不可靠**（旧版拿它推断「不能流血」导致黑暗犬误判）。
-- 但那条结论针对的是「类型→可否流血」的**推断**，不等于返回值本身是垃圾；
-- 且此前它只用于调试串，从未参与判定，所以一直没有可信的实测数据。
-- 因此这里的设计原则是「**假设可能不准，但绝不静默失败**」：
--   · id 稳定存进条件；loc=中文显示名；tok=英文 token（enUS 客户端返回英文）
--   · 匹配时**同时**比对本地化名与英文 token（大小写不敏感），两种语言都认
--   · 另外接受 "other" 兜底项，用户可显式匹配「未列出的类型」
--   · 编辑器顶部会显示客户端**此刻真实报告**的类型，让不准的地方立刻可见
local CREATURE_TYPES = {
  { id = "beast",       loc = "野兽",   tok = "Beast" },
  { id = "dragonkin",   loc = "龙类",   tok = "Dragonkin" },
  { id = "demon",       loc = "恶魔",   tok = "Demon" },
  { id = "elemental",   loc = "元素",   tok = "Elemental" },
  { id = "giant",       loc = "巨人",   tok = "Giant" },
  { id = "undead",      loc = "亡灵",   tok = "Undead" },
  { id = "humanoid",    loc = "人型",   tok = "Humanoid" },
  { id = "critter",     loc = "小动物", tok = "Critter" },
  { id = "mechanical",  loc = "机械",   tok = "Mechanical" },
  { id = "notpecified", loc = "未指定", tok = "Not specified" },
  { id = "totem",       loc = "图腾",   tok = "Totem" },
  { id = "other",       loc = "其他",   tok = "Other" },
}
-- 归一化：把客户端返回的字符串映射到 id。
-- ★1.70.28 关键：本客户端返回的本地化名**可能带后缀**——测试桩里记录的是「人型生物」，
--   而 1.12 的标准名是「人型」。若只按标准名比对，「人型」永远匹配不上而**静默失效**。
--   故这里同时比对「原串」与「去掉 生物/类/型/系 词尾后的核心」，并保留英文 token 通路。
local function creatureKey(s)
  if type(s) ~= "string" then return nil end
  return string.lower(string.gsub(s, "%s+", ""))
end
-- 去词尾「生物」用于宽松匹配。
-- ★只剥离「生物」这一个词尾，**绝不能把「型/类/系」也当后缀**——
--   它们是名字本身的组成部分（「人型」「龙类」「机械」这类名字被剥掉尾字就变成了「人」「龙」），
--   会导致「人型」→「人」而「人型生物」→「人型」，两边永远对不上（本功能的核心静默失效点）。
local CREATURE_SUFFIX = "生物"
local function creatureCore(s)
  local k = creatureKey(s)
  if not k then return nil end
  local n = string.len(CREATURE_SUFFIX)
  if string.len(k) > n and string.sub(k, -n) == CREATURE_SUFFIX then
    k = string.sub(k, 1, string.len(k) - n)
  end
  return k
end
local function creatureTypeId(raw)
  local key = creatureKey(raw)
  if not key or key == "" then return nil end
  local core = creatureCore(raw)
  for _, c in ipairs(CREATURE_TYPES) do
    -- 精确匹配：本地化全名 / 英文 token
    if creatureKey(c.loc) == key or creatureKey(c.tok) == key then return c.id end
    -- 宽松匹配：去词尾后的核心（「人型生物」↔「人型」；「元素生物」↔「元素」）
    if core and (creatureCore(c.loc) == core or creatureCore(c.tok) == core) then return c.id end
  end
  return nil -- 未列出：由调用方决定是否算 "other"
end

-- ===== 条件组格式（方案/技能配置 UI 用）：rule.groups = { {cond,...}, ... }，组内条件为 & 关系，组间为 | 关系 =====
-- 单条件 cond = { k=类型, op/n=数值比较, v=布尔, s=技能名, inv=取反 }
--   数值: {k="power",op=">",n=30}  tHpPct/hpPct/powerPct/combatTime/combo(连击点 1.28.0) 同
--   布尔: {k="combat",v=true}  canAttack/canBleed/isBoss/isElite/tInCombat/alt/shift/ctrl/autoAttack
--   姿态: {k="form",n=1} / {k="formNot",n=1}
--   光环: {k="noBuff",s="战斗怒吼"}  hasBuff/noDebuff/hasDebuff
--   技能侧: {k="ready"} {k="usable"} {k="notQueued"}（inv=true 取反）
--   选取目标: {k="target",s="nearEnemy"}（1.25.0 副作用条件，恒过；dry 预览不执行）
--   目标职业: {k="tClass",cs={WARRIOR=true,...}}（1.26.0 多选或关系，比对 UnitClass 英文 token）

-- 单个条件求值；返回 true 或 false+原因。dry=true 为预览求值（UI 亮金），副作用条件（选取目标）只验函数存在不执行
local function condOne(cd, skill, dry, rule)
  local k = cd.k
  local function texOf(n) return auraTexOf(n) end -- 动作条 + 学习表回退（1.27.0）
  -- ★1.70.45 自身光环「剩余时间检查」（cd.secOp / cd.secN，单位秒）。
  --   只在**光环确实存在**时才参与判定：于是「无buff:奥术智慧[<30s]」= 没有 或 快到期（正是「该补了」）。
  --   left == 0：wiki（globals/Buff）明确「越界/空槽/无限/无结束时间都返回 0」→ 视作**永不到期**，
  --   只有 > / >= 才算满足。若把 0 当「0 秒」，<N 会恒真 → 每次求值都判「该补」→ 无脑重施。
  local function auraTimeCmp(cd, tbl)
    local tex = texOf(cd.s)
    if not tex then return false, "未知光环" end
    local left = tbl and tbl[tex] or nil
    if type(left) ~= "number" then return false, "无剩余时间数据" end
    if left <= 0 then
      local inf = (cd.secOp == ">" or cd.secOp == ">=")
      return inf, "剩余时间无限"
    end
    -- ★1.71.2（第十八轮）用户要求：「技能日志 小数类数据显示保留1位小数」——
    --   旧写法直接 tostring(left)，聊天框里就是「剩余295.24997172132s」这种浮点尾巴（用户截图原文）。
    --   ★格式与本文件既有的「冷却剩 %.1fs」（第 761/773/788 行）保持一致，不另造一套。
    return condCmp({ cd.secOp, cd.secN }, left), string.format("剩余%.1fs", left)
  end
  -- ★1.70.45 把剩余时间检查并入光环判定的**唯一**入口（自身 buff / 自身 debuff 共用）。
  --   语义（v 决定方向，这正是「刷新」用法的核心）：
  --     · v=true （有buff）：必须「有」**且**剩余满足比较；
  --     · v=false（无buff）：没有 **或** 剩余满足比较 —— 于是
  --       「无buff:奥术智慧[<30s]」= 没有 或 快到期 → 正是「该补了」。
  --     · 光环不存在时不查时间（没有东西可查）：v=false 直接判真（该补），v=true 已判假。
  --   ★我第一版把 v=false 时「有 buff 但时间满足」也判成假（因为「有≠无」先短路了），
  --     被用例 (2) 当场抓到——注释写对了、代码没写对，是测试把它逼出来的。
  local function auraTimeJudge(cd, has, okv, tbl, label)
    if type(cd.secN) ~= "number" or not has then return okv, nil end
    local okT, why = auraTimeCmp(cd, tbl)
    if cd.v == false then
      if okT then return true, nil end
      return false, label .. "剩余时间不符(" .. tostring(why) .. ")"
    end
    if not okT then return false, label .. "剩余时间不符(" .. tostring(why) .. ")" end
    return okv, nil
  end
  if k == "combat" then return (st.inCombat == cd.v), "战斗状态"
  elseif k == "combatTime" then return condCmp({ cd.op, cd.n }, st.combatTime), "进战时间"
  elseif k == "combo" then return condCmp({ cd.op, cd.n }, st.combo or 0), "连击点"
  elseif k == "hpPct" then
    -- ★★★1.71.3 候选上下文（用户定案）：在**选取器行**上，「自身血%」读的是**候选者**（扫描集含自己）。
    --   于是截图里那种「自身血%<80」的旧配置不用改也能继续筛队友。
    if st.pickCand then return candNumPass(cd, st.pickCand.hpPct), "候选血%:" .. tostring(teamPct(st.pickCand.hpPct)) end
    return condCmp({ cd.op, cd.n }, st.hpPct), "自身血%"
  elseif k == "power" then
    if st.pickCand then return candNumPass(cd, st.pickCand.power), "候选能量:" .. tostring(teamPct(st.pickCand.power)) end
    return condCmp({ cd.op, cd.n }, st.power), "能量"
  elseif k == "powerPct" then
    if st.pickCand then return candNumPass(cd, st.pickCand.powerPct), "候选能量%:" .. tostring(teamPct(st.pickCand.powerPct)) end
    return condCmp({ cd.op, cd.n }, st.powerPct), "能量%"
  -- ★★★1.75.11 近战围攻数 / 交战人数（用户：「…自身状态->10s交战人数N数量 比较类型,围攻自身N数量 比较类型」）
  --   ★★值一律读**全局战斗数据 st**（Core 的 UPDATE_STATE 每拍只算一次；用户口径：「围攻数量归入战斗数据
  --     全局可被使用,不多个地方各自计算」）—— 这里**绝不再调 EVAL_MW_ACTIVE_N**（同一份数据两处算，迟早打架，
  --     而且同名怪的合并/估算口径只在 EVAL_MW_ACTIVE_INFO 一处维护）。
  --     两个数**只统计战斗状态**（非战斗恒 0），且都是**纯聊天正文口径、零切目标**：
  --       围攻数 = max(近战窗口内「在打我」的不同怪名数, 6s 挥击累加估算)；交战数 = 10s 内跟我有过来往的怪名数。
  --   ★查不到（Core/Engine 未载入 ⇒ 字段 nil）时如实按 0 算，不许假装满足。
  elseif k == "mwSiege" then
    local nS = tonumber(st.mwSiege) or 0
    return condCmp({ cd.op, cd.n }, nS), "围攻数"
  elseif k == "mwEngaged" then
    local nE = tonumber(st.mwEngaged) or 0
    return condCmp({ cd.op, cd.n }, nE), "交战数"
  elseif k == "tHpPct" then return condCmp({ cd.op, cd.n }, st.tHpPct), "目标血%"
  elseif k == "swingLeft" then -- 1.57.0 距下次攻击秒数（1.74.30 起**状态感知**：自动射击中 = 距下次射击）
    local rem = (type(EVAL_SWING_REMAIN_ACTIVE) == "function") and EVAL_SWING_REMAIN_ACTIVE() or EVAL_SWING_REMAIN()
    if rem == nil then return false, "无攻击计时数据" end
    return condCmp({ cd.op, cd.n }, rem), "距攻击"
  elseif k == "shotLeft" then -- ★1.74.30 距下次**射击**秒数（与「距攻击」并列的显式入口，不走状态感知）
    --   ★数据源与「距攻击」自动射击态**同一份**（EVAL_SHOT_REMAIN：探针实测锚点=法术频道含「自动射击」、射速=UnitRangedDamage[1]）
    local remS = (type(EVAL_SHOT_REMAIN) == "function") and EVAL_SHOT_REMAIN() or nil
    if remS == nil then return false, "无射击计时数据" end
    return condCmp({ cd.op, cd.n }, remS), "距射击"
  elseif k == "hasTarget" then return ((st.hasTarget and true or false) == cd.v), "目标存在" -- 1.32.1
  elseif k == "canAttack" then return (st.canAttack == cd.v), "可攻击"
  elseif k == "canBleed" then return (st.canBleed == cd.v), "可流血"
  -- ★1.75.10 目标死亡（用户：「条件类型 → 目标状态 → 目标死亡 是/否」）：
  --   取值 = `st.tDead`（Core 的 UPDATE_STATE 用 `UnitIsDeadOrGhost("target")` 填）。
  --   ★与「目标存在/可攻击/可流血…」**同一口径**：直接与 cd.v 比较（没有目标时 st.tDead = false ⇒ 「否」成立）。
  elseif k == "tDead" then return ((st.tDead and true or false) == cd.v), "目标死亡"
  elseif k == "isBoss" then return (st.isBoss == cd.v), "Boss"
  elseif k == "isElite" then return (st.isElite == cd.v), "精英"
  elseif k == "tInCombat" then return (st.tInCombat == cd.v), "目标战斗"
  elseif k == "tFriendly" then return (st.tFriendly == cd.v), "友善"
  elseif k == "tHostile" then return (st.tHostile == cd.v), "敌对"
  elseif k == "tNeutral" then return (st.tNeutral == cd.v), "中立"
  elseif k == "form" then return (st.formIndex == cd.n), "姿态"
  elseif k == "formNot" then return (st.formIndex ~= cd.n), "姿态"
  elseif k == "tracking" then
    -- ★1.75.6 追踪类型条件（用户：「条件类型 → 自身状态 → 追踪类型，下拉单选」）：
    --   判据唯一入口 = EVAL_TRACK_MATCH（内部按纹理缓存 ⇒ 贵调用只在追踪真的变了时做一次）；
    --   cd.v ~= false = 正向（正在追踪 X）；cd.v == false = 反向（「未追踪:野兽」= 不是野兽，
    --   含「完全没在追踪」）。★认不出种类时**如实失败**（不当成「不是 X」——那会变成静默误判）。
    local okT229, whyT229 = EVAL_TRACK_MATCH(cd.s)
    return (okT229 == (cd.v ~= false)), whyT229

  elseif k == "alt" then return (st.alt == cd.v), "Alt"
  elseif k == "shift" then return (st.shift == cd.v), "Shift"
  elseif k == "ctrl" then return (st.ctrl == cd.v), "Ctrl"
  elseif k == "autoAttack" then return ((st.autoAttack and true or false) == cd.v), "普攻"
  -- 1.51.0 自动射击/魔杖射击 激活状态（直查 IsCurrentAction，同 usable 惯例；未上条=未激活）
  elseif k == "autoShot" or k == "wandShoot" then
    local sn = (k == "autoShot") and "自动射击" or "射击"
    local s = wslots[sn]
    local cur = false
    if s and type(IsCurrentAction) == "function" then
      local okc, c2 = pcall(IsCurrentAction, s.slot)
      cur = okc and c2 and true or false
    end
    return (cur == (cd.v ~= false)), sn
  elseif k == "hasBuff" then -- 1.54.0 合并：v=false=无buff（旧 k=noBuff 仅兼容存量数据）；1.70.1 层数门槛 cd.n
    -- ★★★1.71.2（第十轮）先解析纹理；**解析不出就如实失败**，绝不退化成「0 层」。
    --   （旧写法会把未知光环当成「确定没有」→「否/无」方向永远成立→规则无限重放）
    local cnt, unknownAura = auraCountOf(cd, st.playerBuffs, "pb", EVAL_PLAYER_BUFF_LIST)
    if unknownAura then return false, "自身buff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0) -- 兼容旧布尔/新层数
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    local okv, whyT = auraTimeJudge(cd, has, (has == (cd.v ~= false)), st.playerBuffLeft, "自身buff")
    if not okv then return false, whyT or "自身buff判定不符" end
    return true, "自身buff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "noBuff" then
    local cnt, unknownAura = auraCountOf(cd, st.playerBuffs, "pb", EVAL_PLAYER_BUFF_LIST)
    if unknownAura then return false, "已有buff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    local have = (cnt == true) or ((tonumber(cnt) or 0) > 0)
    return (not have), "已有buff:" .. tostring(cd.s)
  elseif k == "tBuff" then -- 1.54.0 目标 buff 检查（v=false=无目标buff）；1.70.1 层数门槛
    -- ★1.70.45 目标光环**没有**时长 API（wiki globals/Buff：其他单位只有 UnitBuff/UnitDebuff = 图标+层数）。
    --   带剩余时间检查时如实返回 false —— 不忽略它（忽略 = 写了却不生效，属静默失败）。
    if type(cd.secN) == "number" then return false, "目标buff无剩余时间数据" end
    local cnt, unknownAura = auraCountOf(cd, st.targetBuffs, "tb", EVAL_TARGET_BUFF_LIST)
    if unknownAura then return false, "目标buff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    return (has == (cd.v ~= false)), "目标buff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "pDebuff" then -- 1.54.0 自身 debuff 检查（v=false=无自身debuff）；1.70.1 层数门槛
    local cnt, unknownAura = auraCountOf(cd, st.playerDebuffs, "pd", EVAL_PLAYER_DEBUFF_LIST, st.playerDebuffType)
    if unknownAura then return false, "自身debuff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    local okv, whyT = auraTimeJudge(cd, has, (has == (cd.v ~= false)), st.playerDebuffLeft, "自身debuff")
    if not okv then return false, whyT or "自身debuff判定不符" end
    return true, "自身debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "hasDebuff" then
    -- ★1.70.45 同 tBuff：目标光环无时长数据 → 带剩余时间检查时如实 false
    if type(cd.secN) == "number" then return false, "目标debuff无剩余时间数据" end
    -- 1.54.0 合并：v=false=无debuff（不足 lim 层才算无，与旧 noDebuff 同语义）；层数门槛 cd.n（1.31.0）
    local cnt, unknownAura = auraCountOf(cd, st.targetDebuffs, "td", EVAL_TARGET_DEBUFF_LIST, st.targetDebuffType)
    if unknownAura then return false, "目标debuff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    cnt = (cnt == true) and 1 or (tonumber(cnt) or 0) -- 兼容旧布尔/新层数
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local has = cnt >= lim
    return (has == (cd.v ~= false)), "目标debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "/" .. lim) or "")
  elseif k == "noDebuff" then
    -- 层数门槛（1.31.0）：cd.n=视为"无"的上限（nil/1=完全没有；N=不足N层才算无）
    local cnt, unknownAura = auraCountOf(cd, st.targetDebuffs, "td", EVAL_TARGET_DEBUFF_LIST, st.targetDebuffType)
    if unknownAura then return false, "目标debuff:无法识别光环「" .. tostring(cd.s) .. "」（纹理未记录）" end
    cnt = (cnt == true) and 1 or (cnt or 0)
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    if cnt >= lim then return false, "目标已有debuff:" .. tostring(cd.s) .. (lim > 1 and (" " .. cnt .. "层") or "") end
    return true, "debuff层数不足:" .. cnt .. "/" .. lim
  elseif k == "ready" then
    local rd, why = wready(skill)
    if cd.inv then rd = not rd end
    return rd, tostring(why or "就绪")
  elseif k == "usable" then
    local s = wslots[skill]
    if not s then return false, "可用性" end
    -- 1.64.0 修多返回截断：旧写法 s and pcall(...) 是逻辑表达式，只取 pcall 第一返回值——
    -- u/noMana 恒 nil，可用性条件自引入起恒 false（测试只覆盖显示路径没覆盖执行路径才漏网）。
    -- 另：本客户端 usable 第一返回走缓存态误报率高（冲锋/撕裂实际可放仍 false），
    -- 只信第二返回 noMana=「资源不足」（用户 0 怒气验证）；其余交给客户端自拒（1.59.0 模型）。
    local oku, u, noMana = pcall(IsUsableAction, s.slot)
    local pass = (oku and (u or not noMana)) and true or false
    if cd.inv then pass = not pass end
    return pass, noMana and "可用性:资源不足" or "可用性"
  elseif k == "notQueued" then
    local s = wslots[skill]
    local okq, q
    if s then okq, q = pcall(IsCurrentAction, s.slot) end -- 1.64.0 修多返回截断（q 恒 nil，已排队检测失效）
    local pass = not (okq and q)
    if cd.inv then pass = not pass end
    return pass, "已排队"
  elseif k == "casting" then
    -- 施法中（1.38.0/1.41.0 扩：s 空=任意施法）：SPELLCAST_* 事件驱动 st.castName（1.12 无 UnitCastingInfo，只能走事件）
    local pass = (st.castName ~= nil) and ((cd.s == nil or cd.s == "") or st.castName == cd.s)
    return (pass and true or false) == (cd.v ~= false), "施法中"
  elseif k == "castEl" then
    -- 自身读条已进行秒数（1.41.0）：无读条=0
    local el = (st.castName and st.castStart) and (GetTime() - st.castStart) or 0
    return condCmp({ cd.op, cd.n }, el), "施法时间"
  elseif k == "castLeft" then
    -- 自身读条剩余秒数（1.41.0）：事件自带精确总时长，无需学习；无读条/无时长=不过
    local left = (st.castName and st.castUntil) and (st.castUntil - GetTime()) or nil
    return (left ~= nil and condCmp({ cd.op, cd.n }, math.max(0, left))), "施法剩余时间"
  elseif k == "tCastEl" then
    -- 目标读条已进行秒数（1.40.0）：无读条=0
    local tel = (st.tCastName and st.tCastStart) and (GetTime() - st.tCastStart) or 0
    return condCmp({ cd.op, cd.n }, tel), "目标施法时间"
  elseif k == "tCasting" then
    -- 目标施法中（1.40.0；1.41.0 补回：分支在施法扩展编辑中被误吃，缺分支恒 false）
    local pass = (st.tCastName ~= nil) and ((cd.s == nil or cd.s == "") or st.tCastName == cd.s)
    return (pass and true or false) == (cd.v ~= false), "目标施法中"
  elseif k == "tCastLeft" then
    -- 目标读条剩余秒数（1.40.0）：需已学习该技能总时长（castTime 学习表）；未学习=不过
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local total = (w2 and w2.castTime and st.tCastName) and w2.castTime[st.tCastName] or nil
    local tleft = (total and st.tCastStart) and (st.tCastStart + total - GetTime()) or nil
    return (tleft ~= nil and condCmp({ cd.op, cd.n }, math.max(0, tleft))), "目标施法剩余时间"
  elseif k == "inRange" then
    -- 施法范围内（1.37.0）：IsActionInRange(该技能槽位)==true 才算；0=超出 / 1=自动攻击不测距 / nil=无目标
    local s2 = wslots[cd.s or ""]
    local pass = false
    if s2 and type(IsActionInRange) == "function" then
      local okr, r = pcall(IsActionInRange, s2.slot)
      pass = (okr and r == true) and true or false
    end
    return (pass == (cd.v ~= false)), "范围内:" .. tostring(cd.s)
  elseif k == "immune" then
    -- 目标是否已免疫指定技能（1.36.1：读免疫学习表 immune[技能@当前目标]；v=false 即「未免疫」）
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local im = w2 and w2.immune
    local rec = (im and st.targetName) and im[(cd.s or "") .. "@" .. tostring(st.targetName)] and true or false
    return (rec == (cd.v ~= false)), "免疫:" .. tostring(cd.s)
  elseif k == "tClass" then
    -- 目标职业：cd.cs = { WARRIOR=true, ... } 多选或关系；无目标/无职业信息 = 不过
    local pass = (st.tClass and cd.cs and cd.cs[st.tClass]) and true or false
    return pass, "目标职业:" .. tostring(st.tClassName or st.tClass or "?")
  elseif k == "tCreature" then
    -- 目标类型（1.70.28）：cd.cs = { beast=true, elemental=true } 多选或关系 + 是/否
    -- 读不到类型 → id=nil → 匹配不到任何选中项（「否」方向则相反，见下）
    local raw = st.tCreatureType
    local id = creatureTypeId(raw)
    if id == nil and raw ~= nil and raw ~= "" then id = "other" end -- 未列出的返回值归入「其他」
    local hit = (id ~= nil and cd.cs and cd.cs[id]) and true or false
    local pass = (hit == (cd.v ~= false))
    return pass, "目标类型:" .. tostring(raw or "?") .. (cd.v == false and "(否)" or "")
  elseif k == "tPlayer" then
    -- ★★★1.75.10 目标玩家（用户：「技能编辑->目标状态->添加个判断: 目标玩家:xxx名（名称支持自定义输入） 是/否」）。
    --   语义：当前目标**是 / 不是**名为 X 的**玩家**。三条判据缺一不可，缺哪条都**如实失败**（绝不静默通过）：
    --     ① 名字填了（没填 = 用户还没配好 → 不能当「不是 X」放行）；
    --     ② 有目标（没目标时**两个方向都不算过** —— 本项目「查不到 ≠ 没有」纪律）；
    --     ③ 名字相符（**大小写不敏感**，与 tbUnitOf 的名字比对同一口径）+ 目标**确实是玩家**
    --        （UnitIsPlayer；NPC 恰好重名不算「目标玩家」）。
    --   ★★这里**绝不能**调 `condTrim` —— 它是本文件**后面**（约 3506 行）才声明的 local，
    --     而 condOne 在 2173 行 ⇒ 按 Lua 词法作用域，这里绑到的是**全局 nil**（真机红字、闸门当场抓到：
    --     `DECL ORDER CHECK` + 运行时 `attempt to call a nil value (global 'condTrim')`）。
    --     走全局桥 `EVAL_COND_TRIM`（= 同一个函数，单一来源；调用发生在载入完成后，一定已赋值）。
    local nmP = tostring(cd.nm or "")
    if type(EVAL_COND_TRIM) == "function" then nmP = EVAL_COND_TRIM(nmP) end
    if nmP == "" then return false, "目标玩家:未填名称" end
    if not st.hasTarget then return false, "目标玩家:无目标" end
    if type(UnitIsPlayer) ~= "function" then return false, "目标玩家:本客户端没有 UnitIsPlayer" end
    local okIP, isP = pcall(UnitIsPlayer, "target")
    if not okIP then return false, "目标玩家:UnitIsPlayer 调用失败" end
    isP = isP and true or false
    local same = (type(st.targetName) == "string" and string.lower(st.targetName) == string.lower(nmP)) or false
    local hit = (isP and same)
    return (hit == (cd.v ~= false)), "目标玩家:" .. nmP .. ((hit and isP) and "(是玩家)" or "")
  elseif k == "target" then
    -- 副作用条件：切换当前目标（战斗信息UI 亮金预览 dry 时不执行，防止刷新误切目标）
    local gfn = TARGET_SEL_FN[cd.s]
    local fn = gfn and getglobal(gfn)
    if type(fn) ~= "function" then return false, "无选取函数:" .. tostring(cd.s) end
    if TARGET_SEL_NM[cd.s] and not (cd.nm and cd.nm ~= "") then
      -- ★1.75.10 名字参数缺失 ⇒ 如实失败（两种带名选取器都走这里；文案指明是哪一种）
      return false, "未设名称:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
    end
    if not dry then
      -- ★1.75.12 取证标签：条件形态的选取目标（谁的行 + 是条件）—— 与技能行那一处区分开
      local cHow = "条件:" .. tostring((type(rule) == "table" and rule.skill) or "?")
      if TARGET_SEL_NM[cd.s] then
        tselInvoke(cHow, gfn, fn, cd.nm)
        -- ★★1.75.10「玩家的目标」：调用之后**没有目标** ⇒ 如实失败（该玩家不在附近 / 他自己没有目标）。
        --   这条是**副作用条件（求值恒 true）**——不判就会「没协助到也放行」，后面那手打在旧目标上。
        --   ★dry（战斗信息UI 每 0.15s 的预览）**不切也不判**，与其它选取器一致（绝不能预览时误切/误报）。
        if TARGET_SEL_NEEDTGT[cd.s] and not UnitExists("target") then
          return false, "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s) .. "未生效（没协助到目标）"
        end
      elseif TARGET_SEL_ARG[cd.s] then
        -- ★1.70.47 队伍/团队选取：把「规则」与「队伍 or 团队」传给 EVAL_TEAM_PICK，
        --   让它按同规则里的队伍条件反推选人判据（选血最少 / 蓝最少 / 中魔法的那个）。
        teamPickArg.rule = rule
        TARGET_SEL_ARG_LAST = cd.s
        tselInvoke(cHow, gfn, fn, TARGET_SEL_ARG[cd.s])
        teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
      else tselInvoke(cHow, gfn, fn) end
    end
    return true, "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
  end
  -- ★1.70.47 队友/团员条件（用户需求定案）。四种：血量% / 蓝量% / debuff 检测 / buff 检测。
  --   ★语义（用户原话「扫描全员取最低，记下 unitID → st.allyUnit」）：
  --     teamHp     : 扫描全员取**血量%最低**者，与该值比较；命中时记 st.allyUnit = 他
  --     teamMana   : 同上，只算**有蓝职业**（怒气/能量/集中/幸福职业跳过，绝不当成 0% 蓝）
  --     teamBuff   : 「有」= 任一成员带该 buff ；「无/缺」= 任一成员缺该 buff
  --     teamDebuff : 「有」= 任一成员中该类型负面（★这正是「队友有魔法→解魔法」）；「无」= 没人中
  --   ★谁被扫：由 **cd.name** 决定（"队伍" → player+partyN；"团队" → raidN），两类条件各扫各的。
  --   ★★★命中时**切目标并把 unit 记进 st.allyUnit**（用户要求）——这样单条条件就能自足地完成
  --     「找出该治/该解的人 → 后续技能行 UseAction 打在他身上」，不强制额外配一行选取目标。
  --     ★只在**非 dry** 时切（dry = 战斗信息UI 每 0.15s 的预览求值 → 绝不能切目标）。
  --     ★与「选取目标:队伍成员」的配合：规则按顺序全部执行，**后写的条件/选取者决定最终目标**
  --       （确定性的「后者覆盖前者」，不是随机）。
  --     ★「无/缺」方向（没人中 / 没人缺）不切目标：那是**存在性**判定，没有「该对谁施法」的含义。
  --   ★诚实失败：不在队/团里、成员无蓝、无人符合 → 返回 false **并给出原因**；
  --     绝不退化成对玩家自己求值（那会把「队友有魔法」静默变成「我有魔法」）。
  -- ★★★1.71.3 候选者条件（用户要求：选取器行只提供这 4 类）
  --   候选者 = 循环检索到的那个成员（**含自己**，由选取器行决定队伍/团队范围）。
  --   ★只在选取器行有效：没有候选上下文就**如实失败**（不假装通过）——配在别的行上没有意义。
  if k == "candHp" or k == "candPower" or k == "candBuff" or k == "candDebuff" then
    local rec = st.pickCand
    if type(rec) ~= "table" then
      return false, "候选者条件只能配在「选取目标:队伍成员/团队成员」那一行（当前没有候选者）"
    end
    local rn = tostring(rec.name or rec.unit)
    if k == "candHp" then
      return candNumPass(cd, rec.hpPct), "候选者血%:" .. tostring(teamPct(rec.hpPct)) .. "% " .. rn
    elseif k == "candPower" then
      if not (rec.powerMax and rec.powerMax > 0) then return false, "候选者没有能量条（无蓝职业）：" .. rn end
      return candNumPass(cd, rec.powerPct), "候选者能量%:" .. tostring(teamPct(rec.powerPct)) .. "% " .. rn
    elseif k == "candBuff" then
      local tex = texOf(cd.s)
      if not tex then return false, "未知buff:" .. tostring(cd.s) end
      local need = (type(cd.n) == "number" and cd.n > 0) and cd.n or 1
      local cnt = rec.buffs[tex]
      cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
      local lack = (cnt < need) -- 「缺」= 层数不足（与「队友缺buff」同一套语义：v==false 表示缺）
      local lbl = "候选者缺buff:" .. tostring(cd.s)
      if cd.v == false then return lack, lbl .. (lack and (" 缺:" .. rn) or " 已有") end
      return (not lack), lbl .. ((not lack) and (" 有:" .. rn) or " 缺")
    else -- candDebuff：候选者身上有该（或该类型）负面效果
      local want = cd.dt
      local hasName = (cd.s ~= nil and cd.s ~= "")
      local tex = hasName and texOf(cd.s) or nil
      if hasName and not tex then return false, "未知debuff:" .. tostring(cd.s) end
      local hit, hitCnt = false, 0
      if tex then
        local d = rec.debuffs[tex]
        if d and dispelMatch(d.t, want) then hit = true hitCnt = tonumber(d.n) or 1 end
      else
        for _, d in pairs(rec.debuffs) do
          if dispelMatch(d.t, want) then hit = true hitCnt = tonumber(d.n) or 1 break end
        end
      end
      local lbl = "候选者debuff:" .. (hasName and tostring(cd.s) or "(任意)")
        .. ((want ~= nil and want ~= "" and want ~= "any") and ("(" .. tostring(want) .. ")") or "")
      if cd.v == false then return (not hit), lbl .. (hit and " 有" or " 无") end
      return hit, lbl .. (hit and (" 有:" .. rn) or " 无")
    end
  end
  if k == "teamHp" or k == "teamMana" or k == "teamBuff" or k == "teamDebuff" then
    local scope = (cd.name == "团队") and "raid" or "party"
    local scopeName = (scope == "raid") and "团队" or "队伍"
    local list = EVAL_HELP_TEAM_ENSURE and EVAL_HELP_TEAM_ENSURE(scope) or nil
    if not list or table.getn(list) == 0 then
      return false, "不在" .. scopeName .. "中（无成员可检测）"
    end
    -- ★1.71.3 按**这一条条件自己的**「职业/队伍」过滤收窄成员集合（空集 = 不过滤）
    list = teamFilterList(list, cd)
    if table.getn(list) == 0 then
      return false, scopeName .. "中没有人符合「职业/队伍」过滤（换个职业/小队，或把过滤清空）"
    end
    local lim = (type(cd.n) == "number" and cd.n > 1) and cd.n or 1
    local best, bestKey = nil, nil

    if k == "teamHp" or k == "teamMana" then
      for _, r in ipairs(list) do
        local isMana = (r.powerType == nil or r.powerType == 0)
        if k == "teamMana" and not isMana then
          -- 没蓝的职业没有「蓝量%」可言，跳过（不报错，只不参与比较）
        else
          local maxv = (k == "teamHp") and r.hpMax or r.powerMax
          local pct  = (k == "teamHp") and r.hpPct or r.powerPct
          -- ★★★1.71.3 统一到「按比较符选人」（用户定案）：< 取最小 / > 取最大 / = 取最接近 / 无→最小
          if maxv and maxv > 0 then
            local better = false
            if bestKey == nil then better = true
            elseif cd.op == ">" or cd.op == ">=" then better = pct > bestKey
            elseif cd.op == "==" or cd.op == "=" then
              better = math.abs(pct - (cd.n or 0)) < math.abs(bestKey - (cd.n or 0))
            else better = pct < bestKey end
            if better then best, bestKey = r, pct end
          end
        end
      end
      if not best then return false, scopeName .. "中无人可测蓝量" end
      local pass = condCmp({ cd.op, cd.n }, bestKey)
      local lbl = ((k == "teamHp") and scopeName .. "血%" or scopeName .. "蓝%")
        .. ":" .. tostring(bestKey) .. "% " .. tostring(best.name or best.unit)
      -- ★命中即「记下这个人」并切过去：后续技能行的 UseAction 就落在他身上
      if pass and not dry then teamSelect(best) end
      return pass, lbl
    elseif k == "teamBuff" then
      -- 「有队伍buff:X」= **有任一**成员带 X（层数够）；「无队伍buff:X」= **有任一**成员缺 X。
      --   ★语义与自身/目标的 有buff/无buff 对齐：都是「存在性」判定，不要求全队一致。
      --   报出的成员：有 → 层数最高的那个；无 → 层数最少的那个（= 最该补的人）。
      local tex = texOf(cd.s)
      if not tex then return false, "未知buff:" .. tostring(cd.s) end
      local have, haveCnt, lack, lackCnt = nil, nil, nil, nil
      for _, r in ipairs(list) do
        local cnt = r.buffs[tex]
        cnt = (cnt == true) and 1 or (tonumber(cnt) or 0)
        -- ★并列时的裁决：层数相同就选**血量百分比更低**的那个。
        --   与 EVAL_TEAM_PICK 的 teamPickBest 用同一条规则——否则「条件报出的人」和
        --   「选取目标实际切过去的人」可能不是同一个（日志与行为对不上，用户会以为选错了）。
        if cnt >= lim then
          if not have or cnt > haveCnt or (cnt == haveCnt and r.hpPct < have.hpPct) then have, haveCnt = r, cnt end
        else
          if not lack or cnt < lackCnt or (cnt == lackCnt and r.hpPct < lack.hpPct) then lack, lackCnt = r, cnt end
        end
      end
      local lbl = scopeName .. "buff:" .. tostring(cd.s) .. (lim > 1 and (">=" .. lim) or "")
      if cd.v == false then
        if not lack then return false, lbl .. " 全都有" end -- 「无/缺」不成立：没人缺
        if not dry then teamSelect(lack) end -- 缺 buff 的人 = 该被补的那个人
        return true, lbl .. " 缺:" .. tostring(lack.name or lack.unit)
      end
      if not have then return false, lbl .. " 无人有" end
      -- 「有」= 纯存在性判定（不是「该对谁施法」）→ **不切目标**
      return true, lbl .. " 有:" .. tostring(have.name or have.unit)
    else -- teamDebuff
      -- 「有队伍debuff:X」= **有任一**成员中 X；「无队伍debuff:X」= **没人**中 X。
      --   ★这正是「队伍有魔法 → 解魔法」：正向为真时，报出的那个成员就是该解的人。
      local want = cd.dt
      local hasName = (cd.s ~= nil and cd.s ~= "")
      local tex = hasName and texOf(cd.s) or nil
      if hasName and not tex then return false, "未知debuff:" .. tostring(cd.s) end
      local hit, hitCnt, best = false, 0, nil
      for _, r in ipairs(list) do
        local cur2, curCnt = false, 0
        if tex then
          local d = r.debuffs[tex]
          if d and dispelMatch(d.t, want) then cur2 = true curCnt = tonumber(d.n) or 1 end
        else
          for _, d in pairs(r.debuffs) do
            if dispelMatch(d.t, want) then cur2 = true curCnt = tonumber(d.n) or 1 break end
          end
        end
        if cur2 and (best == nil or curCnt > hitCnt) then hit, hitCnt, best = true, curCnt, r end
      end
      local lbl = scopeName .. "debuff:" .. (hasName and tostring(cd.s) or "(任意)")
        .. ((want ~= nil and want ~= "" and want ~= "any") and ("(" .. tostring(want) .. ")") or "")
      if not hit then
        -- 没人中：正向（有）如实失败；取反（无）如实通过
        return (cd.v == false), lbl .. " 无人有"
      end
      if cd.v == false then return false, lbl .. " 有人有:" .. tostring(best.name or best.unit) end
      local ok = hitCnt >= lim
      -- ★命中即切过去：这正是「队友有魔法 → 解魔法」——不切的话技能会打在别人身上
      if ok and not dry then teamSelect(best) end
      return ok, lbl .. (ok and (" 有:" .. tostring(best.name or best.unit)) or (" 层数不足(" .. tostring(hitCnt) .. ")"))
    end
  end
  return false, "未知条件:" .. tostring(k)
end

-- 条件组求值：任一组全过即过（组间 | ），组内全过才算过（组内 & ）
-- 命中时返回第三个值 trace = 该组每个条件的逐项判定明细（释放日志用）
-- 1.49.1：条件为空 = 无条件直接执行（旧行为：空 groups 表一组都不进 → 恒 false 永远不触发，
-- 编辑窗不配条件保存 / 导入文本 "- 技能 | " 都会产出空表——技能变死条目）
-- ★注意这里是**给上面已前置声明的 local 赋值**（不是新建 local）——
--   改了会连带断掉「队伍成员」扫描器里的候选过滤（那些引用在声明点之前）。
function groupsOK(rule, dry)
  if not rule.groups or table.getn(rule.groups) == 0 then return true, nil, "无条件" end
  local lastWhy = "条件不满足"
  for _, g in ipairs(rule.groups or {}) do
    local allOK = true
    local trace = {}
    for _, cd in ipairs(g) do
      local ok, why = condOne(cd, rule.skill, dry, rule)
      table.insert(trace, EVAL_COND_STR(cd) .. (ok and "√" or "×"))
      if not ok then allOK = false lastWhy = why break end
    end
    if allOK then return true, nil, table.concat(trace, " ") end
  end
  return false, lastWhy
end

-- 按顺序执行规则表；第一条条件全过且启用的技能出手。返回 true=本次按键已动作
-- ===== 免疫学习器（1.36.0，探针实测驱动） =====
-- 事件 CHAT_MSG_SPELL_SELF_DAMAGE，文本 "你的{技能}施放失败。{怪名}对此免疫。"（英文端 "Your X fails. Y is immune."）
-- 学习持久化 EVAL_HELP_CONFIG.war.immune["技能@怪名"]=true；RULE_RUN 对同名怪自动跳过该技能（可流血黑名单的自动学习版）
function EVAL_IMMUNE_LEARN(msg)
  if type(msg) ~= "string" then return false end
  local skill, mob = string.match(msg, "你的(.-)施放失败。(.-)对此免疫。")
  if not skill then skill, mob = string.match(msg, "Your (.-) fails%. (.-) is immune%.") end
  if not (skill and mob and skill ~= "" and mob ~= "") then return false end
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  if not w2 then return false end
  if not w2.immune then w2.immune = {} end
  local key = skill .. "@" .. mob
  if not w2.immune[key] then
    w2.immune[key] = true
    EVAL_SAY("|cffff9040已学习免疫: " .. skill .. " @ " .. mob .. "（该目标不再尝试此技能）|r")
  end
  return true
end

-- 当前目标是否已记录免疫该技能
local function wImmuneTo(skill)
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  local im = w2 and w2.immune
  return (im and st.hasTarget and st.targetName) and im[skill .. "@" .. tostring(st.targetName)] and true or false
end

-- ===== 目标施法跟踪（1.40.0）：CHAT_MSG_SPELL_CREATURE_VS_* 文本驱动 =====
-- 开始：「X开始施放Y。」X=当前目标名 → st.tCastName/tCastStart；结束：「Y击中你/对你造成」→ 学习总时长进 war.castTime（任意施法者都学）
function EVAL_TCAST_EVENT(msg)
  if type(msg) ~= "string" then return end
  local caster, spell = string.match(msg, "(.-)开始施放(.+)。")
  if not caster then caster, spell = string.match(msg, "(.-) begins to cast (.+)%.") end
  if not caster then caster, spell = string.match(msg, "(.-) begins casting (.+)%.") end
  if caster and spell and spell ~= "" then
    if st.hasTarget and st.targetName == caster then
      st.tCastName = spell
      st.tCastStart = GetTime()
    end
    return
  end
  local sp2 = string.match(msg, "(.-)击中你造成") or string.match(msg, "(.-)对你造成") or string.match(msg, "(.-) hits you")
  if sp2 and st.tCastName == sp2 and st.tCastStart then
    local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    if w2 then
      if not w2.castTime then w2.castTime = {} end
      local dur = GetTime() - st.tCastStart
      if dur > 0.2 and dur < 30 then w2.castTime[sp2] = math.floor(dur * 100 + 0.5) / 100 end
    end
    st.tCastName, st.tCastStart = nil, nil
  end
end

-- ===== 挥击计时（1.55.0，与施法学习同机制） =====
-- 事件 CHAT_MSG_COMBAT_SELF_HITS：「你击中X造成Y点伤害。」「你爆击X…」（英文 "You hit/crit X for Y"）
-- ——每次平砍命中锚定 st.lastSwing；攻速 UPDATE_STATE 采集（st.atkSpd）；施法会推迟挥击：锚点取 max(lastSwing, castUntil)
function EVAL_SWING_EVENT(msg)
  if type(msg) ~= "string" then return false end
  local hit = string.find(msg, "^你击中") or string.find(msg, "^你爆击") or string.find(msg, "^You hit") or string.find(msg, "^You crit")
  if not hit then return false end
  st.lastSwing = GetTime()
  return true
end

-- 距下次挥击秒数；无攻速/无锚点数据返回 nil（UI 显示「—」）
function EVAL_SWING_REMAIN()
  local spd = st.atkSpd
  if not (spd and spd > 0) then return nil end
  local anchor = st.lastSwing
  if st.castUntil and st.castUntil > (anchor or 0) then anchor = st.castUntil end -- 施法推迟挥击
  if not anchor then return nil end
  local r = anchor + spd - GetTime()
  return (r > 0) and r or 0
end


-- ===== 射击计时（1.74.30；由 `/eh go 射击探针` 真机实测定案）=====
-- ★实测（8 发干净样本，见探针报告）：
--   · **锚点通道 = CHAT_MSG_SPELL_SELF_DAMAGE**，原文含「自动射击」；★暴击原文是「你的自动射击对X造成30的致命一击伤害。」
--     —— **也含「自动射击」** ⇒ 判据一律**只认「自动射击 / Auto Shot」这个词**，不要去认「击中/爆击」那套词形。
--   · **速度来源 = UnitRangedDamage("player") 第 1 个返回值**（实测 2.09）；[2][3] 是伤害上下限（差 3.0 = 弹药），[4][5][6] 是噪声。
--   · 实测 Δt 均值 2.16 vs API 2.09 → **比值 1.03 ≈ 1** ⇒ API 值就是真实间隔（本轮**未观测到**箭袋急速带来的差异）。
--   · 与近战**互不干扰**：近战走 CHAT_MSG_COMBAT_SELF_HITS + UnitAttackSpeed，两套锚点各自独立（1.55.0 那套一行未改）。
-- ★自校准（只在**明显偏离**时才修）：留最近几次 (Δt ÷ API) 的中位数；样本 ≥4 且中位数落在 [0.9, 1.1] 之外
--   （= API 未含急速）才拿它修正，否则一律用 API 原值 —— **不把客户端计时抖动当急速**。
local SHT = { samples = {}, max = 6 }
local SHT_CAL_MIN = 4
local SHT_CAL_LO, SHT_CAL_HI = 0.9, 1.1

-- 这条消息是不是「自动射击」的伤害/命中（命中与暴击两种词形都含「自动射击」）
function EVAL_SHOT_IS(msg)
  if type(msg) ~= "string" then return false end
  if string.find(msg, "自动射击", 1, true) then return true end
  if string.find(msg, "Auto Shot", 1, true) then return true end
  return false
end

-- 远程速度 API 原值（单一口：UPDATE_STATE 与计时/探针都读它，避免两处各调一次）
function EVAL_SHOT_API_SPEED()
  if type(UnitRangedDamage) ~= "function" then return nil end
  local ok, v = pcall(UnitRangedDamage, "player")
  if ok and type(v) == "number" and v > 0.1 and v < 20 then return v end
  return nil
end

-- 自校准中位数（样本不足 → nil，表示「不修正」）
function EVAL_SHOT_CAL_RATIO()
  local n = table.getn(SHT.samples)
  if n < SHT_CAL_MIN then return nil end
  local sorted = {}
  for i = 1, n do sorted[i] = SHT.samples[i] end
  table.sort(sorted)
  return sorted[math.floor((n + 1) / 2)]
end

function EVAL_SHOT_SPEED()
  local api = EVAL_SHOT_API_SPEED()
  if not api then return nil end
  local r = EVAL_SHOT_CAL_RATIO()
  if r and (r < SHT_CAL_LO or r > SHT_CAL_HI) then return api * r end -- ★只在明显偏离时才修（见上）
  return api
end

-- 锚点：自动射击命中那一刻（顺手攒一个自校准样本；离群样本丢弃）
function EVAL_SHOT_EVENT(msg)
  if not EVAL_SHOT_IS(msg) then return false end
  local t = GetTime()
  local api = EVAL_SHOT_API_SPEED()
  if api and st.lastShot then
    local dt = t - st.lastShot
    if dt > api * 0.5 and dt < api * 1.5 then -- ★离群剔除：早了/晚了一整个周期的不当样本
      table.insert(SHT.samples, dt / api)
      while table.getn(SHT.samples) > SHT.max do table.remove(SHT.samples, 1) end
    end
  end
  st.lastShot = t
  return true
end

-- 现在是不是「自动射击中」（找不到槽位 / 无 API → false，如实回退近战那套）
function EVAL_SHOT_ACTIVE()
  if type(IsAutoRepeatAction) ~= "function" or type(wslots) ~= "table" then return false end
  local names = { "自动射击", "射击", "Auto Shot", "Shoot" }
  for i = 1, 4 do
    local rs = wslots[names[i]]
    if type(rs) == "table" and rs.slot then
      local ok, v = pcall(IsAutoRepeatAction, rs.slot)
      if ok and v then return true end
    end
  end
  return false
end

-- 距下次**射击**秒数（无速度/无锚点 → nil：UI 显「—」、条件不满足，绝不假装有数据）
function EVAL_SHOT_REMAIN()
  local spd = EVAL_SHOT_SPEED()
  if not (spd and spd > 0) then return nil end
  local anchor = st.lastShot
  if st.castUntil and st.castUntil > (anchor or 0) then anchor = st.castUntil end -- 施法同样推迟自动射击
  if not anchor then return nil end
  local r = anchor + spd - GetTime()
  return (r > 0) and r or 0
end

-- ★对外只用这两个**状态感知**入口（UI 与条件都走它）：自动射击中看射击，否则看近战
function EVAL_SWING_KIND()
  if EVAL_SHOT_ACTIVE() then return "ranged" end
  return "melee"
end
function EVAL_SWING_SPEED()
  if EVAL_SWING_KIND() == "ranged" then
    local s = EVAL_SHOT_SPEED()
    if s then return s end
    return nil -- ★自动射击中但拿不到射速 → 如实 nil（不许退回近战速度冒充）
  end
  return st.atkSpd
end
function EVAL_SWING_REMAIN_ACTIVE()
  if EVAL_SWING_KIND() == "ranged" then return EVAL_SHOT_REMAIN() end
  return EVAL_SWING_REMAIN()
end

-- ★测试读值口：自校准样本数 / 当前中位数 / 最终采用的射速（都读生产真值，不在测试里复刻公式）
function EVAL_SHOT_TEST_STATE()
  return { n = table.getn(SHT.samples), ratio = EVAL_SHOT_CAL_RATIO(), speed = EVAL_SHOT_SPEED(), api = EVAL_SHOT_API_SPEED() }
end

-- ★测试用：清掉自校准样本与锚点（模块级状态，测试必须能整组拆）
function EVAL_SHOT_TEST_RESET()
  SHT.samples = {}
  st.lastShot = nil
  return true
end

-- ===== 射击计时探针（1.74.29；用户：「调研猎人自动射击状态下的攻击时间计算 → 按方案实施」）=====
-- ★只取证、不改任何行为：一次问清三件事 —— ① `UnitRangedDamage` 到底返回什么（哪一个才是「秒/击」）
--   ② 自动射击的命中落在**哪个事件**（原文长什么样）③ 实测两次命中的 Δt 与 ①② 对不对得上。
-- ★为什么先探针：本客户端**没有挥击/射击计时 API**（近战那套也是「事件锚点 + UnitAttackSpeed」推出来的），
--   远程的锚点事件名/速度取值一旦猜错 → 计时**静默不动或系统性偏**（本项目最恨的失败型）。
-- 用法：`/eh go 射击探针`（开/关）· `/eh go 射击探针 报告`（打印）· `/eh go 射击探针 清空`
local SHP = { on = false, rows = {}, max = 32, frame = nil }
local SHP_EV = "CHAT_MSG_COMBAT_SELF_MISSES" -- 未命中通道（只在探针开启期间临时挂，关掉即摘）
-- ★播报出口：Engine.lua 段没有 EvalHelp 那个 local say —— 走项目统一出口 EVAL_SAY（静默纪律不变）。
-- ★★1.74.30 **同时落盘**（EVAL_LOGLINE → SavedVariables 环形缓冲，与 Share 探针 1.74.4 同一条纪律）：
--   探针只打聊天框的话，事后谁读不到（截图/复述都会丢细节）⇒ 每条都进 `[射击探针]` 日志，AI 可直接读存档文件。
local function shpSay(s)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[射击探针] " .. tostring(s)) end
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, s) else print(s) end
end

function EVAL_SHOT_PROBE_STATE()
  return { on = SHP.on, n = table.getn(SHP.rows), max = SHP.max }
end

-- 事件喂入（命中两条通道由主程序的 OnEvent 派发处调用；未命中那条由探针自己的帧收）
function EVAL_SHOT_PROBE_FEED(ev, txt)
  if not SHP.on then return false end
  if table.getn(SHP.rows) >= SHP.max then return false end
  table.insert(SHP.rows, { ev = tostring(ev or "?"), txt = tostring(txt or ""), t = GetTime() })
  return true
end

-- ① 远程速度来源：把 `UnitRangedDamage` 的**每个返回值**原样交出来（哪个像「秒/击」由人一眼判）
function EVAL_SHOT_PROBE_SPEEDS()
  local out = { ranged = {}, melee = {} }
  if type(UnitRangedDamage) == "function" then
    local ok, a, b, c, d, e, f = pcall(UnitRangedDamage, "player")
    out.rangedOk = ok and true or false
    local vals = { a, b, c, d, e, f }
    for i = 1, 6 do
      out.ranged[i] = { v = vals[i], t = type(vals[i]),
        plausible = (type(vals[i]) == "number" and vals[i] >= 0.4 and vals[i] <= 5.0) and true or false }
    end
  else
    out.rangedOk = false
  end
  if type(UnitAttackSpeed) == "function" then
    local ok2, mh, oh = pcall(UnitAttackSpeed, "player")
    out.melee.ok = ok2 and true or false
    out.melee.mh, out.melee.oh = mh, oh
  end
  return out
end

-- ③ 远程动作条槽位 + 「现在是不是自动射击中」（IsAutoRepeatAction，项目已在用同一接口）
function EVAL_SHOT_PROBE_SLOTS()
  local out = {}
  local names = { "自动射击", "射击", "Auto Shot", "Shoot" }
  for i = 1, 4 do
    local nm = names[i]
    local rs = (type(wslots) == "table") and wslots[nm] or nil
    if type(rs) == "table" and rs.slot then
      local rep = "no-api"
      if type(IsAutoRepeatAction) == "function" then
        local ok, v = pcall(IsAutoRepeatAction, rs.slot)
        rep = ok and tostring(v) or ("call-fail:" .. tostring(v))
      end
      table.insert(out, { name = nm, slot = rs.slot, isRepeat = rep }) -- ★字段名不能叫 repeat（Lua 保留字）
    end
  end
  return out, (type(IsAutoRepeatAction) == "function")
end

function EVAL_SHOT_PROBE_REPORT()
  local n = table.getn(SHP.rows)
  local sp = EVAL_SHOT_PROBE_SPEEDS()
  shpSay("===== 射击计时探针（记录 " .. n .. "/" .. SHP.max .. " 条）=====")
  shpSay(string.format("① UnitRangedDamage(player)：可用=%s", tostring(sp.rangedOk)))
  for i = 1, 6 do
    local r = sp.ranged[i]
    if r and r.v ~= nil then
      shpSay(string.format("   [%d] type=%s 值=%s%s", i, r.t, tostring(r.v), r.plausible and "   ← 像「秒/击」" or ""))
    end
  end
  shpSay(string.format("② UnitAttackSpeed（近战对照）：主手=%s 副手=%s", tostring(sp.melee.mh), tostring(sp.melee.oh)))
  local slots, hasApi = EVAL_SHOT_PROBE_SLOTS()
  if table.getn(slots) == 0 then
    shpSay("③ 动作条里没找到「自动射击/射击」（IsAutoRepeatAction 可用=" .. tostring(hasApi) .. "）")
  else
    for i = 1, table.getn(slots) do
      local s = slots[i]
      shpSay(string.format("③ 槽位 %s = slot %s ｜ IsAutoRepeatAction=%s（API 可用=%s）",
          s.name, tostring(s.slot), tostring(s.isRepeat), tostring(hasApi)))
    end
  end
  local last = nil
  local cnt, dts = {}, {}
  local patText = nil -- ★1.74.30 锚点文本特征：命中原文里到底出现了「自动射击」还是「Auto Shot」
  shpSay("④ 事件记录（事件名 ｜ Δt ｜ 原文）")
  for i = 1, n do
    local r = SHP.rows[i]
    cnt[r.ev] = (cnt[r.ev] or 0) + 1
    if not patText then
      if string.find(r.txt, "自动射击", 1, true) then patText = "自动射击"
      elseif string.find(r.txt, "Auto Shot", 1, true) then patText = "Auto Shot" end
    end
    local dt = ""
    if last then dt = string.format("%.2f", r.t - last) table.insert(dts, r.t - last) end
    last = r.t
    shpSay(string.format("   %d) %s ｜ Δt=%s ｜ %s", i, r.ev, (dt == "" and "—" or dt), string.sub(r.txt, 1, 70)))
  end
  local sum = 0
  for i = 1, table.getn(dts) do sum = sum + dts[i] end
  local avg = (table.getn(dts) > 0) and (sum / table.getn(dts)) or nil
  local ns = table.getn(dts)
  shpSay(string.format("⑤ Δt 样本=%d 均值=%s", ns, avg and string.format("%.2f", avg) or "—"))
  for ev, c in pairs(cnt) do shpSay("   通道计数：" .. ev .. " ×" .. tostring(c)) end
  -- ★★1.74.30 比值表（这一屏就是结论）：Δt ÷ 各候选 —— 比值≈1 的那个才是**真实间隔来源**；
  --   明显 <1（如 0.85~0.90）= 该候选**未含急速**（箭袋/弹药袋），差值就是急速系数。
  if avg and avg > 0 then
    local parts = {}
    for i = 1, 6 do
      local rr = sp.ranged[i]
      if rr and type(rr.v) == "number" and rr.v >= 0.4 and rr.v <= 5.0 then
        table.insert(parts, string.format("①[%d]%s→%.2f", i, tostring(rr.v), avg / rr.v))
      end
    end
    if type(sp.melee.mh) == "number" and sp.melee.mh > 0 then
      table.insert(parts, string.format("②主手%s→%.2f", tostring(sp.melee.mh), avg / sp.melee.mh))
    end
    if type(sp.melee.oh) == "number" and sp.melee.oh > 0 then
      table.insert(parts, string.format("②副手%s→%.2f", tostring(sp.melee.oh), avg / sp.melee.oh))
    end
    shpSay("⑤b 比值（Δt÷候选）：" .. table.concat(parts, "  "))
  end
  shpSay("⑥ 锚点通道 = ④ 里计数>0 的事件名；命中文本特征：" .. tostring(patText or "未出现「自动射击/Auto Shot」字样"))
  shpSay("⑦ 判定：⑤b 里**比值最接近 1** 的候选 = 真实射击间隔来源；比值明显<1 → 该候选未含急速。")
  return n
end

function EVAL_SHOT_PROBE(sub)
  sub = tostring(sub or "")
  if string.find(sub, "报告") or string.find(sub, "report") then return EVAL_SHOT_PROBE_REPORT() end
  if string.find(sub, "清空") or string.find(sub, "clear") then SHP.rows = {} shpSay("射击探针：记录已清空") return 0 end
  SHP.on = not SHP.on
  if SHP.on then
    SHP.rows = {}
    if not SHP.frame then
      local f = CreateFrame("Frame")
      f:SetScript("OnEvent", function()
        local a1 = (type(arg1) == "string") and arg1 or ""
        EVAL_SHOT_PROBE_FEED((type(event) == "string") and event or "?", a1)
      end)
      SHP.frame = f
    end
    pcall(SHP.frame.RegisterEvent, SHP.frame, SHP_EV)
    shpSay("射击计时探针：|cff00ff00已开启|r —— 现在**开自动射击打几下**（≥5 次），再 /eh go 射击探针 报告")
  else
    if SHP.frame then pcall(SHP.frame.UnregisterEvent, SHP.frame, SHP_EV) end
    shpSay("射击计时探针：已关闭（记录保留，「报告」仍可查看）")
  end
  return SHP.on
end

-- ===== 追踪探针（1.74.31；用户：「调用 API 如何获得角色追踪状态（采矿/采药/野兽追踪）」）=====
-- ★本客户端**没有**经典版那套追踪枚举 API —— 本机 `api_*.html` 索引里 `GetNumTrackingTypes` / `GetTrackingInfo` /
--   `SetTracking` **都不存在**；存在的只有两个：
--   · **`GetTrackingTexture()`**（category **Mapping**）= 当前追踪技能的**图标纹理**（没追踪时为空）→ **主路**；
--   · **`CancelTrackingBuff()`**（category **Buff**）= 取消当前追踪。
-- ★「是哪一种追踪」**没有 API 直接给名字** ⇒ 必须靠**纹理 ↔ 技能名对照**（动作条 `wslots[名].tex` + 法术书扫一遍）。
-- ★官方文档另一条已知空洞：「Hidden or tracking auras are skipped」⇒ 追踪**可能不占增益条槽位**，
--   所以光环（`GetPlayerBuff`）只能当**辅助证据**；本探针把两条路一起打出来对照。
-- ★★1.75.2 补两条路（本次调研结论；官方文档原文见下）：
--   · **`GameTooltip:SetTrackingSpell()`**（widgets/GameTooltip，索引里有）——官方原文
--     「Fills an aura tooltip from the player's current tracking spell (minimap tracking). Clears lines first.
--      Does nothing if no tracking spell is active.」⇒ **「是哪一种追踪」只有这里能拿到本地化名字**
--     （纹理表要按语言+客户端维护，名字不用）→ **名字主路**；读它必须走**自建隐形 tooltip**
--     （`EVAL_HELP_WTT` + `EVAL_WTT_MAY_READ` 守卫），绝不碰玩家正看着的 `GameTooltip`（1.73.14 铁律）。
--   · 官方对**增益条**那条路的硬事实（别再去绕）：「Tracking auras are **not** listed here」
--     （Buff 页）+「Hidden or tracking auras are **skipped**」（`GetPlayerBuff`）⇒ 光环只能当**辅助证据**。
-- ★参考实现（本机 `D:\game\TurtleWoW\Interface\AddOns\S_MiniMap\Modules\pftrackingUI.lua`，pfUI 小地图追踪）：
--   判状态 = `GetTrackingTexture()`；出名字 = `GameTooltip:SetTrackingSpell()`；开追踪 =
--   `CastSpell(spellIndex, BOOKTYPE_SPELL)`（法术书索引；Protected ⇒ 本插件只能走动作条 `UseAction`）；
--   关 = `CancelTrackingBuff()`；刷新事件 = `PLAYER_ENTERING_WORLD` / `PLAYER_AURAS_CHANGED` /
--   `SPELLS_CHANGED` / `UPDATE_SHAPESHIFT_FORMS`。
--   ★它那张「图标名 → 追踪种类」表（`INV_Misc_Flower_02`=采药 · `Spell_Nature_Earthquake`=采矿 ·
--     `Ability_Tracking`=追踪野兽 · `Racial_Dwarf_FindTreasure`=寻找宝藏）**是 TurtleWoW 的实测值**；
--     EmberVeil 的纹理串形态**未实测**（本项目已知形态是 `/Game/Interface/Icons/<名>_TEX`）
--     ⇒ 探针只当**候选**打印，**绝不写死判据**。
-- ★★1.75.3 本轮（用户：「分析API 排查 玩家追踪效果.草药,采矿,野兽之类的」）四条实证结论，先看这四条再动代码：
--   ① **接口面到此为止**：本地 1370 条官方索引里跟追踪有关的**只有三条** ——
--      GetTrackingTexture()（Mapping：当前追踪的**图标纹理**，没追踪 = nil）、
--      GameTooltip:SetTrackingSpell()（widget：**唯一**能拿到「是哪种追踪」本地化名字的入口）、
--      CancelTrackingBuff()（Buff：取消当前追踪）。三条的官方页**都没有 Protected 行** ⇒ 插件可直接调；
--      对照 CastSpell / CastSpellByName 是 Protected ⇒ **开追踪**只能走动作条 UseAction(slot)。
--      **没有**枚举/查询「有哪些追踪种类」的 API（GetNumTrackingTypes / GetTrackingInfo / SetTracking
--      在本客户端**不存在**，别照 1.12 的写法抄）。
--   ② **小地图上的追踪圆点无法枚举**：Minimap 官方页只给 SetBlipTexture（队友点）/ SetIconTexture
--      （**追踪图标**：生物 / 资源 / 任务 / 宠物）两个**纯外观** setter，没有任何 blip 列表读口
--      ⇒ 「玩家追踪效果」只能从**状态**判定，不能从图上读回来。
--   ③ **候选图标表已实证**（见下面 TRK.hint）：13 条追踪法术来自官方数据库逐条核对，且逐条在本机
--      图标清单里存在 ⇒ 表里不再有「TurtleWoW 抄来的未验证值」；判据 = TRACK ICON CHECK（tests/checks/Track.js）。
--   ④ **事件名无处可查**：wiki 的 /wiki/lua/Events 是 **404**，索引里也没有事件表（只有 UIObject 的
--      RegisterEvent 说明）⇒ 「切换追踪时哪条事件会来」**只能靠⑧监听实测**（别照抄 pfUI 的
--      PLAYER_AURAS_CHANGED：那是 TurtleWoW 的值，本客户端**未实测**）。
-- ★★1.75.4 真机首轮读数（用户跑完了取证流程）暴露两件事，本版据此改探针：
--   ① 两次读数**完全一样**、都是「① 本次=（空/无追踪）」+「② 当前没追踪」⇒ 但旧探针**分不清**这三种情况：
--      (a) 真的没追踪；(b) 有追踪、但 GetTrackingTexture 返回的**不是字符串**（旧版 type(v)=="string" 直接丢）；
--      (c) 有追踪、但接口就是不给（返回 nil）。⇒ ① 改成**类型 + 原文一起打**，② 改成**独立于①** + why 三态。
--   ② 那一轮「动作条 2 个追踪技能」「法术书 2 条」都读到了（说明 API/UI 基本可用），
--      却没有一条能说明**当前追踪是什么** ⇒ 补第三条路：**默认 UI 的追踪按钮图标**（⑩）。
--   ③ `监听` 从「猜 4 条候选事件」升级成 **RegisterAllEvents 全事件抓取**（事件名官方没公开：
--      与其猜，不如全收下来**按次数升序**排 —— 切换追踪只会给真正相关的那条 + 几次）。
-- 用法：`/eh go 追踪探针`（打印一次；**开/关追踪各跑一次**，第二次会显示「上次 → 本次」对照）
--       `/eh go 追踪探针 监听`（开关事件监听：切换几次追踪 → 打出「哪条事件真的跟着走」，退出时给计数）
--       `/eh go 追踪探针 表`（打印候选图标表：13 条追踪法术 ↔ 客户端图标基础名；回传时对照用）
--       `/eh go 追踪探针 清空`（清「上次」读数 + 专属读数）
--       `/eh go 追踪探针 存档`（把**专属读数**（最近 40 行，落存档、不被 [DS] 刷掉）打回聊天框）
local TRK = {
  lastTex = nil,
  ev = false,          -- 事件监听开关
  frame = nil,
  evHit = {},          -- 每个事件命中次数（关监听时打印 = 哪条事件真的会跟着追踪走）
  evLastTex = nil,     -- 事件里「纹理变了才打一行」（PLAYER_AURAS_CHANGED 在战斗中很密，不能刷屏）
  -- ★1.75.4 两条新路（真机首轮读数暴露的问题：两次读数都是「（空/无追踪）」，而旧探针**分不清**
  --   「真的没追踪」与「有追踪但 GetTrackingTexture 返回的不是字符串」——正是「查不到≠没有」）
  allEv = false,       -- true = RegisterAllEvents 全事件抓取（handler 里**只计数**，一个 API 都不调）
  evTotal = 0,         -- 本次抓取的总事件次数（关掉时打印）
  now = nil,           -- ★1.75.6 「现在的追踪」缓存（按纹理缓存 ⇒ 贵调用只在追踪真的变了时做一次）

  -- ★★★候选图标表（1.75.3 实证值；1.75.6 起第 1 列由中文标签换成 **稳定 id**）：
  --   ① 官方数据库 database.emberveil.org 的 13 条追踪法术页：法术 ID → 英文名 + 图标 png 名；
  --   ② **本客户端**图标清单 doc 目录的「图标路径清单.txt」（/eh go icons 从真机采的 1018 条）：
  --      这 13 个基础名**逐条都在**（形态 = /Game/Interface/Icons/<基础名>_TEX）⇒ 不是抄来的、是核过的。
  --   ★匹配一律走**基础名全等**（EVAL_TRACK_BASE）⇒ Interface/Icons/X、/Game/Interface/Icons/X_TEX、
  --     ★真机形态 /Game/Interface/Icons/X_TEX.X_TEX（1.75.5 实测）、大小写任意组合都成立；
  --     **绝不做子串匹配**（子串会误报：INV_Misc_Flower_02 也是 INV_Misc_Flower_02_Copy 的前缀）。
  --   ★仍**绝不写死判据**：没命中 = 如实 nil（「没命中候选表」≠「不是追踪」）。
  --   列 = { **id**, 客户端图标基础名, 英文法术名, 中文法术名 }；行尾注释 = 官方数据库的法术 ID。
  --   ★id 是**语言无关的稳定键**：条件值（cd.s）、导出文本（追踪:beast）都用它；
  --     界面标签走 EVAL_TRACK_LABEL(id) = L("TRK_"..ID)（三语齐全由 TRACK ICON CHECK 守）。
  hint = {
    { "herb",         "INV_Misc_Flower_02",               "Find Herbs",       "寻找草药" },     -- 2383
    { "mining",       "Spell_Nature_Earthquake",          "Find Minerals",    "寻找矿物" },     -- 2580
    { "treasure",     "Racial_Dwarf_FindTreasure",        "Find Treasure",    "寻找宝藏" },     -- 2481 矮人种族
    { "beast",        "Ability_Tracking",                 "Track Beasts",     "追踪野兽" },     -- 1494
    { "humanoid",     "Spell_Holy_PrayerOfHealing",       "Track Humanoids",  "追踪人型生物" }, -- 19883
    { "demon",        "Spell_Shadow_SummonFelHunter",     "Track Demons",     "追踪恶魔" },     -- 19878
    { "dragonkin",    "INV_Misc_Head_Dragon_01",          "Track Dragonkin",  "追踪龙类" },     -- 19879
    { "elemental",    "Spell_Frost_SummonWaterElemental", "Track Elementals", "追踪元素生物" }, -- 19880
    { "giant",        "Ability_Racial_Avatar",            "Track Giants",     "追踪巨人" },     -- 19882
    { "undead",       "Spell_Shadow_DarkSummoning",       "Track Undead",     "追踪亡灵" },     -- 19884
    { "hidden",       "Ability_Stealth",                  "Track Hidden",     "追踪隐藏生物" }, -- 19885
    { "sensedemon",   "Spell_Shadow_Metamorphosis",       "Sense Demons",     "感知恶魔" },     -- 5500 ★算不算「追踪」待真机验
    { "senseundead",  "Spell_Holy_SenseUndead",           "Sense Undead",     "感知亡灵" },     -- 5502 ★同上
  },
  -- 追踪变化要跟的事件（pfUI 的清单；注册失败的那几个在报告里如实点名 = 本客户端没这个事件）
  evNames = { "PLAYER_AURAS_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UPDATE_SHAPESHIFT_FORMS" },
  -- ★1.75.4 第三条独立路：**默认 UI 的追踪按钮/图标**（= 游戏自己认为当前追踪是什么）
  --   本客户端 UI 编译在 pak 里 ⇒ 帧名只能现场探：候选表 + 有界 `_G` 扫描；全落空就**如实缺席**。
  btnCands = { "MiniMapTrackingIcon", "MiniMapTrackingButtonIcon", "MiniMapTrackingTexture",
               "MiniMapTracking", "MiniMapTrackingButton", "MiniMapTrackingFrame" },
}

-- （EVAL_TRACK_PROBE_STATE 1.75.4 起移到本段末尾：与测试驱动口放在一起）
-- 纹理 → 技能名（先在动作条里找；找不到返回 nil，**不猜**）
function EVAL_TRACK_WHO(tex)
  if type(tex) ~= "string" or tex == "" or type(wslots) ~= "table" then return nil end
  local hit = nil
  for nm, v in pairs(wslots) do
    if type(v) == "table" and v.tex == tex then hit = tostring(nm) break end
  end
  return hit
end

-- 纯函数（可单测）：纹理串 → **基础名**（剥目录 / 扩展名 / _TEX 后缀；转小写）
--   ★反斜杠一律用 string.char(92) 构造 —— 项目铁律：Lua 源码里不手写转义（写坏过好几次）
--   ★★★1.75.5 真机实测形态（本项目**唯一**实测过的那条，别再按 1.12 的形态想）：
--     /Game/Interface/Icons/Ability_Tracking_TEX.Ability_Tracking_TEX
--     = **资产路径 _TEX + 「.」 + 对象名 _TEX**，两段都带后缀 ⇒ 老实现整段归一得到
--     ability_tracking_tex.ability_tracking，**永远命中不了候选表**（③ 一直报「没命中」，
--     全靠名字备用路兜着 —— 真机首轮读数的 ③ 就是这么错的）。
--   ★修法：取最后一段后**只认第一个「.」之前**（图标基础名里不含点）；扩展名 / _TEX 仍是兜底。
function EVAL_TRACK_BASE(tex)
  if type(tex) ~= "string" or tex == "" then return nil end
  local s = string.lower(tex)
  s = string.gsub(s, string.char(92), "/")   -- 反斜杠 → 斜杠
  s = string.match(s, "([^/]*)$") or s       -- 取最后一段（目录全丢）
  local seg = string.match(s, "^([^%.]*)")    -- ★只取第一个「.」之前（真机形态里的「资产名.对象名」）
  if seg ~= nil and seg ~= "" then s = seg end
  s = string.gsub(s, "%.[%a%d]+$", "")       -- 去扩展名（.png / .tex / .tga …；上面已切点，属兜底）
  s = string.gsub(s, "_tex$", "")            -- 去客户端后缀 _TEX
  if s == "" then return nil end
  return s
end

-- 纹理 → 追踪**种类 id**（候选图标表对照；★「没命中」≠「不是追踪」⇒ 只作对照，不写死判据）
--   ★按**基础名全等**比对（不是子串）：子串匹配会误报（INV_Misc_Flower_02 是 ..._02_Copy 的前缀）
--   ★返回**稳定 id**（herb/beast/…，语言无关）——界面名走 EVAL_TRACK_LABEL(id)
--   ★按**基础名全等**比对（不是子串）：子串匹配会误报（INV_Misc_Flower_02 是 ..._02_Copy 的前缀）
function EVAL_TRACK_KIND(tex)
  local base = EVAL_TRACK_BASE(tex)
  if base == nil then return nil end
  for i = 1, table.getn(TRK.hint) do
    if base == string.lower(TRK.hint[i][2]) then return TRK.hint[i][1] end
  end
  return nil
end

-- 本地化名字 → 追踪**种类 id**（备用路：纹理没命中候选表时，名字还能认出种类）
--   ★只收官方数据库确有译名的两种语言（zhCN / enUS；ruRU 在库里回落到英文 ⇒ 不收，如实 nil）
--   ★同样「认不出就 nil」，**不猜**
--   ★只收官方数据库确有译名的两种语言（zhCN / enUS；ruRU 在库里回落到英文 ⇒ 不收，如实 nil）
--   ★同样「认不出就 nil」，**不猜**
function EVAL_TRACK_KIND_BY_NAME(nm)
  if type(nm) ~= "string" then return nil end
  local n = string.lower(nm)
  n = string.gsub(n, "^%s+", "")
  n = string.gsub(n, "%s+$", "")
  if n == "" then return nil end
  for i = 1, table.getn(TRK.hint) do
    local h = TRK.hint[i]
    if n == string.lower(tostring(h[3] or "")) or n == string.lower(tostring(h[4] or "")) then return h[1] end
  end
  return nil
end

-- 纯函数（可单测）：从 tooltip 的行文本里挑法术名（第一行非空即名字）
function EVAL_TRACK_NAME_FROM_LINES(l1, l2)
  if type(l1) == "string" and l1 ~= "" then return l1 end
  if type(l2) == "string" and l2 ~= "" then return l2 end
  return nil
end

-- ★★★1.75.2 为什么探针要**另存一份专属读数**（实测教训，别删）：调试日志环 `EH_LOG_MAX = 100` 条，
--   而 `cfg.ds.trace` 开着时 `[DS]` 心跳/地图行**每 ~10 秒一行** ⇒ **约 17 分钟就把探针读数冲干净**——
--   1.75.2 实测：用户做完 5 步、过了约 19 分钟才 `/reload`，存档里**一条 `[追踪探针]` 都读不到**（白跑一趟）。
--   ⇒ 探针每行同时落一个小环（最近 40 行）到存档 `EVAL_HELP_CONFIG.trkProbe`：
--     我这边**直接读 SavedVariables 文件**即可，用户侧也能用 `/eh go 追踪探针 存档` 把它打回聊天框。
--   ★它只是调试产物 ⇒ 已登记进 Core 的「调试残渣键」清单（`/eh 存档清理` 可清）。
-- ★1.75.4 40 → 80：报告变长了（多了「原文+类型 / 名字三态 / 光环名字 / 追踪按钮 / 快照」），
--   40 行只装得下 2 份报告 ⇒ 「开 → 关 → 换种类」三份对照会被冲掉 ⇒ 提到 80 行（仍是**有界**环）。
local TRK_OUT_MAX = 80
local function trkOut(s)
  local cfg = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
  if cfg == nil then return end
  local box = cfg.trkProbe
  if type(box) ~= "table" then box = { out = {} } cfg.trkProbe = box end
  if type(box.out) ~= "table" then box.out = {} end
  table.insert(box.out, tostring(s))
  while table.getn(box.out) > TRK_OUT_MAX do table.remove(box.out, 1) end
  box.t = (type(date) == "function") and date("%H:%M:%S") or nil
end

local function trkSay(s)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[追踪探针] " .. tostring(s)) end
  pcall(trkOut, s) -- ★专属持久读数（不被 [DS] 冲掉）
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, s) else print(s) end
end


-- 纯函数（可单测）：把**任意返回值**打成能看懂的一行（nil / 字符串 / 非字符串都如实说）
--   ★tostring 对 userdata 可能抛错 ⇒ 一律 `pcall(tostring, v)`（★不许写 `pcall(tostring(v))`：那是先调用再交给 pcall）
function EVAL_TRACK_STR(v)
  if v == nil then return "nil" end
  local ok, s = pcall(tostring, v)
  if ok and type(s) == "string" then return s end
  return "（tostring 失败：" .. type(v) .. "）"
end

-- 纯函数：数一个表有几个键（打印「本次共 N 个不同事件名」用）
local function trkCountKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- 第三条路（有界探针）：扫 `_G` 里名字含 Track/追踪 的对象，报「类型 + 纹理 + IsShown」
--   ★守卫照铁律：索引前先 `pcall(v.GetObjectType, v)` 探类型；方法一律 `pcall(obj.M, obj)` 形态
--   ★匿名窗口在 `_G` 里**看不到**（参考卷 R15 ⑥k）⇒ 扫不到是**如实缺席**，不等于「没有追踪按钮」
--   返回 out, okAll（okAll=false = 扫描中途抛错 ⇒ 结果不可信，报告里如实说）
function EVAL_TRACK_SCAN_GLOBALS()
  local out, okAll = {}, false
  pcall(function()
    for k, v in pairs(_G) do
      if type(k) == "string" and (string.find(k, "Track") or string.find(k, "追踪")) then
        local tv = type(v)
        if tv == "table" or tv == "userdata" then
          local okg, gt = pcall(v.GetObjectType, v)
          if okg and type(gt) == "string" then
            local tex, shown = nil, nil
            if type(v.GetTexture) == "function" then local okt, t = pcall(v.GetTexture, v) if okt then tex = t end end
            if type(v.IsShown) == "function" then local oks, s = pcall(v.IsShown, v) if oks then shown = s end end
            table.insert(out, string.format("%s（%s）%s%s", k, gt,
              (tex ~= nil) and (" ｜ 纹理=" .. tostring(tex)) or "",
              (shown ~= nil) and (" ｜ IsShown=" .. tostring(shown)) or ""))
          end
        end
      end
    end
    okAll = true
  end)
  table.sort(out)
  return out, okAll
end
-- 名字主路：**自建隐形 tooltip** + `SetTrackingSpell`
--   ★1.75.4 返回值扩成 name, ok, why, l1, l2 —— **why 必须分三态**：
--     旧版一律在报告里写「当前没追踪」，正好踩中项目最恨的「查不到 ≠ 没有」（真机首轮读数就是这么来的）。
--       why="noapi"   = 自建 tooltip 上没有 SetTrackingSpell（接口不存在）
--       why="noguard" = EVAL_WTT_MAY_READ 守卫不让读（玩家正看 tooltip / 退化到真 GameTooltip）
--       why="empty"   = 真调了 SetTrackingSpell，但两行**都是空**（= 客户端认为没有追踪）
--       why="ok"      = 读到名字
local function trkName()
  if type(EVAL_WTT_MAY_READ) ~= "function" or not EVAL_WTT_MAY_READ() then return nil, false, "noguard" end
  local wtt = nil
  if type(EVAL_WTT_HANDLE) == "function" then wtt = EVAL_WTT_HANDLE() end
  if wtt == nil then return nil, false, "noapi" end
  if type(wtt.SetTrackingSpell) ~= "function" then return nil, false, "noapi" end
  local base = "GameTooltip"
  if type(EVAL_WTT_STATE) == "function" then
    local oks, st = pcall(EVAL_WTT_STATE)
    if oks and type(st) == "table" and type(st.name) == "string" and st.name ~= "" then base = st.name end
  end
  pcall(function()
    pcall(wtt.ClearLines, wtt)
    pcall(wtt.SetOwner, wtt, UIParent, "ANCHOR_NONE")
    wtt:SetTrackingSpell()
  end)
  local l1, l2
  local fs1 = rawget(_G, base .. "TextLeft1")
  if fs1 and fs1.GetText then local ok1, t = pcall(fs1.GetText, fs1) if ok1 then l1 = t end end
  local fs2 = rawget(_G, base .. "TextLeft2")
  if fs2 and fs2.GetText then local ok2, t = pcall(fs2.GetText, fs2) if ok2 then l2 = t end end
  pcall(wtt.Hide, wtt)
  local nm = EVAL_TRACK_NAME_FROM_LINES(l1, l2)
  if nm == nil then return nil, false, "empty", l1, l2 end
  return nm, true, "ok", l1, l2
end
-- 纯函数（可单测）：这次事件要不要**打一行**？—— 只在**纹理变了**时打
--   ★为什么不按「事件来了就打」：PLAYER_AURAS_CHANGED 在战斗中**很密**（每次光环变化都来），
--   那样监听一开就刷屏、把真正的切换淹掉；★计数照记（关监听时打印）⇒「哪条事件真的会来」照样有据。
function EVAL_TRACK_EV_SHOULD_LOG(tex, lastTex)
  if (tex or nil) == (lastTex or nil) then return false end
  return true
end

-- 事件路线：切换追踪时**哪条事件**真的会来？
--   ★1.75.4 全事件模式下**只计数**：RegisterAllEvents 收所有事件，handler 里调一次 API 都是浪费/风险，
--     纹理与名字一律等到「关掉监听」那一刻由报告路去读（那时状态已定）。
--   ★退化模式（本客户端没有 RegisterAllEvents）保留旧行为：**纹理变了才打一行**（否则 PLAYER_AURAS_CHANGED 刷屏）。
--   ★真机 OnEvent 回调**零形参**（事件名走全局 `event`；本项目 ONUPDATE ARG 那条铁律同族）
local function trkOnEvent()
  local ev = tostring(event or "?")
  TRK.evHit[ev] = (TRK.evHit[ev] or 0) + 1
  TRK.evTotal = (TRK.evTotal or 0) + 1
  if TRK.allEv then return end
  local tex = nil
  if type(GetTrackingTexture) == "function" then
    local okv, v = pcall(GetTrackingTexture)
    if okv and type(v) == "string" and v ~= "" then tex = v end
  end
  if EVAL_TRACK_EV_SHOULD_LOG(tex, TRK.evLastTex) then
    TRK.evLastTex = tex
    local nm, nmOk = trkName()
    trkSay(string.format("[事件] %s ｜ 纹理=%s ｜ 名字=%s", ev, tostring(tex or "（空/无追踪）"),
      (nmOk and nm) and ("「" .. tostring(nm) .. "」") or "（读不出）"))
  end
end
-- 光环清单（辅助证据：追踪到底占不占增益条）—— ★1.75.4 连**名字**一起读：
--   真机首轮读数里增益条只有 1 个光环（`Spell_Nature_RavenForm_TEX`）——**它到底是什么**必须读名字才知道，
--   否则「追踪是不是就藏在增益条里」永远只能猜。名字走共用件 `EVAL_PLAYER_BUFF_NAME`（自建隔离 tooltip，1.74.8 起就在）。
local function trkBuffs()
  local out = {}
  if type(GetPlayerBuff) ~= "function" or type(GetPlayerBuffTexture) ~= "function" then return out, false end
  for i = 0, 31 do
    local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
    if not okb or type(bi) ~= "number" or bi < 0 then break end
    local okt, tex = pcall(GetPlayerBuffTexture, bi)
    local nm = nil
    if type(EVAL_PLAYER_BUFF_NAME) == "function" then
      local okn, v = pcall(EVAL_PLAYER_BUFF_NAME, bi)
      if okn and type(v) == "string" and v ~= "" then nm = v end
    end
    if okt and type(tex) == "string" and tex ~= "" then
      table.insert(out, { i = i, bi = bi, tex = tex, name = nm })
    end
  end
  return out, true
end

-- 读值口（测试/诊断）：探针状态（★1.75.4 补 allEv / evTotal）
function EVAL_TRACK_PROBE_STATE()
  return { lastTex = TRK.lastTex, listening = TRK.ev, allEv = TRK.allEv,
           evHit = TRK.evHit, evTotal = TRK.evTotal }
end

-- ★★★测试驱动口（1.75.4）：把「事件来了」**按真机通道**打进去（设全局 event → 调 frame 的 OnEvent → 还原）
--   ★绝不直接调 trkOnEvent —— 那会绕过真实注册链路（项目纪律：断言打真实入口）；★真机回调**零形参**
function EVAL_TRACK_TEST_FIRE_EVENT(evName)
  if TRK.frame == nil then return false end
  local okS, sc = pcall(TRK.frame.GetScript, TRK.frame, "OnEvent")
  if not okS or type(sc) ~= "function" then return false end
  local keep = event
  event = tostring(evName or "?")
  local okc = pcall(sc)
  event = keep
  return okc and true or false
end

-- 读值口：每个事件命中次数（关监听时报告打印的就是同一份）
function EVAL_TRACK_TEST_HITS() return TRK.evHit end
-- ===== 1.75.6 追踪条件（用户：「一键宏 → 技能编辑 → 条件类型 → 自身状态 → 添加一个追踪类型，下拉单选」）=====
-- 三条 API 的实测结论见上面 1.75.3~1.75.5 的注释；这里只做「把状态变成可判定的东西」这件事。

-- id → 本地化标签（★**运行时拼键** L("TRK_"..ID)：LANG KEY CHECK 只看字面量、扫不到它
--   ⇒ 三语齐全由 TRACK ICON CHECK 逐条核对；★认不出的 id 退回候选表中文名，绝不编造）
function EVAL_TRACK_LABEL(id)
  local key = "TRK_" .. string.upper(tostring(id or ""))
  local s = (type(EVAL_L) == "function") and EVAL_L(key) or nil
  if type(s) == "string" and s ~= "" and s ~= key then return s end
  for i = 1, table.getn(TRK.hint) do
    if TRK.hint[i][1] == id then return tostring(TRK.hint[i][4]) end
  end
  return tostring(id or "?")
end

-- 下拉/文档的唯一清单：首项 = 任意追踪，其后 = 候选表顺序（★UI 与断言都读它，不另抄一份）
function EVAL_TRACK_LIST()
  -- ★别写成 EVAL_TRACK_LABEL("any")：**函数名以 L 结尾 + 字面量参数**会被 LANG KEY CHECK 的正则
  --   当成语言键 "any"（它按 L("KEY") 子串扫，不看前面是不是标识符）⇒ 假红。走局部变量最省事。
  local anyId = "any"
  local out = { { id = anyId, label = EVAL_TRACK_LABEL(anyId) } }
  for i = 1, table.getn(TRK.hint) do
    table.insert(out, { id = TRK.hint[i][1], label = EVAL_TRACK_LABEL(TRK.hint[i][1]) })
  end
  return out
end

-- id / 基础名 / 英中文法术名 / 本地化标签 → **规范 id**（认不出 = nil，**不猜**）
--   ★文本往返用得上：导出写 id（追踪:beast），用户手打「追踪:追踪野兽」也要认。
function EVAL_TRACK_PARSE_ID(txt)
  if type(txt) ~= "string" then return nil end
  local t = string.lower(txt)
  t = string.gsub(t, "^%s+", "")
  t = string.gsub(t, "%s+$", "")
  if t == "" then return nil end
  if t == "any" or t == "任意" or t == "任意追踪" then return "any" end
  for i = 1, table.getn(TRK.hint) do
    local h = TRK.hint[i]
    if t == string.lower(tostring(h[1])) then return h[1] end
    if t == string.lower(tostring(h[2])) then return h[1] end
    if t == string.lower(tostring(h[3] or "")) then return h[1] end
    if t == string.lower(tostring(h[4] or "")) then return h[1] end
    local lbl = EVAL_TRACK_LABEL(h[1])
    if type(lbl) == "string" and t == string.lower(lbl) then return h[1] end
  end
  return nil
end

-- 「现在的追踪」（★**按纹理缓存**）：纹理没变就直接复用上一次结果 ——
--   贵调用（SetTrackingSpell 走 tooltip）**只在追踪真的变了**时做一次（项目纪律：贵调用只在变化时做）。
--   返回 { on=bool, tex=..., base=..., id=..., name=..., why=... }；id 没命中候选表时 = nil（**不猜**）
function EVAL_TRACK_NOW()
  local tex = nil
  if type(GetTrackingTexture) == "function" then
    local ok, v = pcall(GetTrackingTexture)
    if ok and type(v) == "string" and v ~= "" then tex = v end
  end
  local c = TRK.now
  if c ~= nil and c.tex == tex then return c end
  local now = { tex = tex, on = (tex ~= nil), base = EVAL_TRACK_BASE(tex), id = nil, name = nil, why = nil }
  if tex ~= nil then
    now.id = EVAL_TRACK_KIND(tex)           -- 纹理路（语言无关，首选）
    local nm, _ok, why = trkName()          -- 名字路（贵；只在变化时读一次）
    now.name, now.why = nm, why
    if now.id == nil then now.id = EVAL_TRACK_KIND_BY_NAME(nm) end
  end
  TRK.now = now
  return now
end

-- 条件求值入口（condOne 用的唯一判据）：id = 候选表 id 或 "any"
--   返回 ok, why（why 与别的条件同口径：进调试日志与条件 trace）
function EVAL_TRACK_MATCH(id)
  local now = EVAL_TRACK_NOW()
  if now.on ~= true then return false, "没有追踪" end
  local cur = now.id or now.name or now.base or "?"
  if id == nil or id == "" or id == "any" then return true, "追踪:" .. tostring(cur) end
  local want = EVAL_TRACK_PARSE_ID(id) or tostring(id)
  if now.id == nil then return false, "追踪:" .. tostring(cur) .. "（本客户端没能认出种类）" end
  return (now.id == want), "追踪:" .. tostring(cur) .. "／要 " .. tostring(EVAL_TRACK_LABEL(want))
end

-- 读值口（测试/诊断）：缓存本身与清缓存（断言要能验「第二次不再读 tooltip」）
function EVAL_TEST_TRACK_CACHE() return TRK.now end
function EVAL_TEST_TRACK_CACHE_CLEAR() TRK.now = nil end

function EVAL_TRACK_PROBE(sub)
  sub = tostring(sub or "")
  if string.find(sub, "清空") or string.find(sub, "clear") then
    TRK.lastTex = nil
    local cfgC = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
    if cfgC ~= nil then cfgC.trkProbe = { out = {} } end
    trkSay("追踪探针：上次读数 + 专属读数（存档 trkProbe）已清空")
    return 0
  end
  -- ★专属读数的读回入口（配合 `/eh 存档清理` 的残渣清单；我这边也能直接读 SavedVariables 文件）
  if string.find(sub, "存档") or string.find(sub, "dump") then
    local cfgD = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
    local boxD = cfgD and cfgD.trkProbe
    local lstD = (type(boxD) == "table" and type(boxD.out) == "table") and boxD.out or {}
    local nD = table.getn(lstD)
    trkSay(string.format("===== 追踪探针 · 专属读数（存档 trkProbe；上限 %d 行）｜现有 %d 行 =====", TRK_OUT_MAX, nD))
    if nD == 0 then
      trkSay("（空）—— 还没跑过 `追踪探针`，或刚 `清空` 过。★这一份**不会被 [DS] 心跳刷掉**：跑完探针直接 /reload 即可回传")
    end
    for i = 1, nD do trkSay(string.format("[%d] %s", i, tostring(lstD[i]))) end
    return nD
  end
  -- ★候选图标表（1.75.3）：把「什么基础名算哪种追踪」摊开 —— 用户回传时可直接对照
  if string.find(sub, "表") or string.find(sub, "roster") then
    local nR = table.getn(TRK.hint)
    trkSay(string.format("===== 追踪探针 · 候选图标表（%d 条；来源 database.emberveil.org + 本机图标清单）=====", nR))
    for i = 1, nR do
      local h = TRK.hint[i]
      trkSay(string.format("   %d. %s（id=%s） ｜ %s / %s ｜ /Game/Interface/Icons/%s_TEX",
        i, tostring(EVAL_TRACK_LABEL(h[1])), tostring(h[1]), tostring(h[3] or "?"), tostring(h[4] or "?"), tostring(h[2])))
    end
    trkSay("   用法：开着追踪跑一次 `追踪探针` → ③ 的「基础名」**不在**上表 → 把 ①③ 两行原文回传，我据此补表")
    return nR
  end
  -- ★事件监听（开关）：追踪切换时**哪条事件**真的会来 —— 这是「实时检测」要用的事件判据取证
  --   ★1.75.4 改成**全事件抓取**（`RegisterAllEvents`，wiki widgets/Frame 索引里确有）：事件名官方没公开
  --     （wiki /wiki/lua/Events = 404）⇒ 「猜 4 条候选」不如「全收下来按次数排」：
  --     切换追踪只会给真正相关的那条 + 几次，噪音事件（战斗/聊天/地图）在这段时间里的次数明显不同。
  --   ★抓取期间 handler **只计数**；★RegisterAllEvents 不可用 ⇒ 如实退回 4 条候选并点名谁没注册上。
  if string.find(sub, "监听") or string.find(sub, "listen") then
    if not TRK.frame then
      local f = CreateFrame("Frame")
      f:SetScript("OnEvent", function() trkOnEvent() end) -- ★真机回调**零形参**
      TRK.frame = f
    end
    if TRK.ev then
      for i = 1, table.getn(TRK.evNames) do
        pcall(TRK.frame.UnregisterEvent, TRK.frame, TRK.evNames[i])
      end
      local hadAll = TRK.allEv
      if hadAll then pcall(TRK.frame.UnregisterAllEvents, TRK.frame) end
      TRK.ev, TRK.allEv = false, false
      trkSay(string.format("事件监听：已关闭（%s）。本次共 %d 次事件、%d 个不同事件名；下面按**次数升序**（少的前面 = 候选）：",
        hadAll and "全事件抓取" or "4 条候选事件", tonumber(TRK.evTotal) or 0, trkCountKeys(TRK.evHit)))
      local list = {}
      for k, v in pairs(TRK.evHit) do table.insert(list, { k = tostring(k), n = tonumber(v) or 0 }) end
      table.sort(list, function(a, b) if a.n ~= b.n then return a.n < b.n end return a.k < b.k end)
      local cap = 60
      for i = 1, table.getn(list) do
        if i > cap then
          trkSay(string.format("   …（还有 %d 个事件名没列；按次数升序，越靠前越可疑）", table.getn(list) - cap))
          break
        end
        trkSay(string.format("   %s = %d 次", list[i].k, list[i].n))
      end
      trkSay("   pfUI 那 4 条候选（TurtleWoW 的值，仅供参考）：")
      for i = 1, table.getn(TRK.evNames) do
        local ev = TRK.evNames[i]
        trkSay(string.format("      %s = %d 次", ev, tonumber(TRK.evHit[ev]) or 0))
      end
      return 0
    end
    TRK.ev, TRK.evHit, TRK.evLastTex, TRK.evTotal = true, {}, nil, 0
    TRK.allEv = false
    -- ★判据 = **接口在不在**（存在就调、抛错才算不可用）——绝不用「返回值真假」判：
    --   pcall 的第一个返回是**成功标志**，真客户端 RegisterAllEvents 本来就**不返回值**（同 RegisterEvent）
    --   ⇒ 写成 `pcall(...) and true or false` 会把「调用成功但没返回」也算成 true，判据就废了（1.75.4 当场踩到）。
    local allOk, allWhy = false, "本客户端没有 RegisterAllEvents"
    if type(TRK.frame.RegisterAllEvents) == "function" then
      local okc, err = pcall(TRK.frame.RegisterAllEvents, TRK.frame)
      if okc then allOk, allWhy = true, "" else allWhy = tostring(err) end
    end
    if allOk then
      TRK.allEv = true
      trkSay("事件监听：|cff00ff00全事件抓取已开启|r（RegisterAllEvents）")
      trkSay("   现在**只做一件事**：用小地图追踪按钮切换 3 次（开 → 关 → 换种类），别的什么都别做；")
      trkSay("   做完再跑一次 `/eh go 追踪探针 监听` 关掉 → 会**按次数**列出所有事件名（少的就是候选）。")
      return 1
    end
    local reg, bad = {}, {}
    for i = 1, table.getn(TRK.evNames) do
      local ev = TRK.evNames[i]
      if pcall(TRK.frame.RegisterEvent, TRK.frame, ev) then table.insert(reg, ev) else table.insert(bad, ev) end
    end
    trkSay("事件监听：|cff00ff00已开启|r（★退回 4 条候选事件：" .. tostring(allWhy) .. "）")
    trkSay("   注册成功：" .. ((table.getn(reg) > 0) and table.concat(reg, " ／ ") or "（一个都没有）"))
    if table.getn(bad) > 0 then
      trkSay("   ★注册失败（本客户端**没有**这个事件）：" .. table.concat(bad, " ／ "))
    end
    trkSay("   现在切换几次追踪（开 → 关 → 换种类），每次变化会打一行 [事件]；做完再跑一次 `监听` 关掉")
    return 1
  end
  trkSay("===== 追踪探针 =====")
  -- ① 当前追踪（主路）：★1.75.4 **类型 + 原文一起打**，不再用「字符串才算」把非字符串值静默丢掉
  --   （旧版就是这么把「有追踪但返回值不是字符串」误报成「没追踪」的 —— 查不到≠没有）
  local hasApi = (type(GetTrackingTexture) == "function")
  local raw, rawType = nil, "（接口不存在）"
  if hasApi then
    local ok, v = pcall(GetTrackingTexture)
    if ok then raw, rawType = v, type(v) end
  end
  local cur = (rawType == "string" and raw ~= "") and raw or nil
  trkSay(string.format("① GetTrackingTexture：可用=%s ｜ 类型=%s ｜ 原文=%s ｜ 上次=%s",
    tostring(hasApi), tostring(rawType), EVAL_TRACK_STR(raw), tostring(TRK.lastTex or "（还没读过）")))
  if hasApi and rawType ~= "string" and raw ~= nil then
    trkSay("   ★返回的**不是字符串** ⇒ 本探针按「没追踪」处理，但这**可能是假象**（把上面「原文」回传给我）")
  end
  if cur and TRK.lastTex and cur ~= TRK.lastTex then
    trkSay("   ★两次读数**不同** → 中间那一步改变了追踪（开/关或换种类）；对照两次报告即可定判据")
  end
  -- ② 名字（主路）——「是哪一种追踪」的**唯一本地化名字来源**
  --   ★1.75.4 **独立于①**：只要接口在就调，why 三态 + tooltip 两行原文全打出来
  --   （旧版 cur==nil 就直接写「当前没追踪」，把「名字路读空」与「真没追踪」混成一句 = 静默族）
  local nm, nmOk, nmWhy, nmL1, nmL2
  if hasApi then
    local okn2, n2, okf, w2, l1, l2 = pcall(trkName)
    if okn2 then nm, nmOk, nmWhy, nmL1, nmL2 = n2, okf, w2, l1, l2 end
  end
  local nmTxt
  if not hasApi then nmTxt = "（GetTrackingTexture 不可用 → 本条免谈）"
  elseif nmWhy == "ok" and nm then nmTxt = "「" .. tostring(nm) .. "」（名字路**有值**）"
  elseif nmWhy == "empty" then nmTxt = "★调了 SetTrackingSpell，但 tooltip **两行都是空**（= 客户端认为没有追踪）"
  elseif nmWhy == "noguard" then nmTxt = "★**守卫不让读**（玩家正看 tooltip / 退化到真 GameTooltip）"
  elseif nmWhy == "noapi" then nmTxt = "★自建 tooltip 上**没有 SetTrackingSpell**（接口不存在）"
  else nmTxt = "★**读不出来**（pcall 抛错）—— 别当成「没追踪」" end
  trkSay("② 名字（主路）GameTooltip:SetTrackingSpell：读到=" .. nmTxt)
  trkSay(string.format("   tooltip 原文：TextLeft1=%s ｜ TextLeft2=%s", EVAL_TRACK_STR(nmL1), EVAL_TRACK_STR(nmL2)))
  -- ③ 种类：纹理主路（基础名对候选表）+ 名字备用路（本地化名字对候选表）—— 两条路互相印证
  --   ★两条路**打架**时如实点出「不一致」：静默取某一路 = 候选表写错了用户也看不到
  --   ★1.75.6 起 id 与本地化标签一起打（id 是稳定键、也是条件值；标签是给人看的）
  local kindTex = EVAL_TRACK_KIND(cur)
  local kindNm = ((nmOk == true) and type(nm) == "string") and EVAL_TRACK_KIND_BY_NAME(nm) or nil
  local function trkBoth(id)
    if id == nil then return nil end
    return tostring(id) .. "（" .. tostring(EVAL_TRACK_LABEL(id)) .. "）"
  end
  trkSay(string.format("③ 种类：基础名=%s ｜ 候选图标表=%s ｜ 动作条名字=%s",
    tostring(EVAL_TRACK_BASE(cur) or "（无）"),
    trkBoth(kindTex) or "（没命中候选表 —— 按①的纹理原文回传，我据此补表）",
    tostring(EVAL_TRACK_WHO(cur) or "（动作条里没有这个纹理的技能）")))
  local nmTxt3
  if kindNm == nil then
    nmTxt3 = "（名字认不出种类，或名字路读不出 —— 不猜）"
  elseif kindTex == nil then
    nmTxt3 = "「" .. tostring(trkBoth(kindNm)) .. "」（纹理没命中候选表，名字认出来了 ⇒ 两条路互补）"
  elseif kindTex == kindNm then
    nmTxt3 = "「" .. tostring(trkBoth(kindNm)) .. "」（与纹理路**一致** ⇒ 两条路互证）"
  else
    nmTxt3 = "★「" .. tostring(trkBoth(kindNm)) .. "」与纹理路「" .. tostring(trkBoth(kindTex)) .. "」**不一致** ⇒ 把这两行原文回传，我核表"
  end
  trkSay("   名字备用路：" .. nmTxt3)

  trkSay("④ 取消 CancelTrackingBuff：可用=" .. tostring(type(CancelTrackingBuff) == "function"))
  -- ⑤ 光环（辅助）—— ★1.75.4 连**名字 / 种类**一起打：真机上「追踪到底占不占增益条」靠这一行定案
  local bl, bOk = trkBuffs()
  trkSay(string.format("⑤ 增益条光环（辅路）：接口可用=%s 共 %d 个", tostring(bOk), table.getn(bl)))
  local seen, auraKind = false, nil
  for i = 1, table.getn(bl) do
    local b = bl[i]
    local who = EVAL_TRACK_WHO(b.tex)
    local kAura = EVAL_TRACK_KIND(b.tex)
    local kNm = (type(b.name) == "string") and EVAL_TRACK_KIND_BY_NAME(b.name) or nil
    if cur and b.tex == cur then seen = true end
    if kAura ~= nil or kNm ~= nil then auraKind = kAura or kNm end
    trkSay(string.format("   [槽 %d] %s ｜ 名字=%s%s%s", b.i, tostring(b.tex), EVAL_TRACK_STR(b.name),
      (kAura ~= nil) and (" ｜ 种类=" .. tostring(kAura) .. "（" .. tostring(EVAL_TRACK_LABEL(kAura)) .. "）")
        or ((kNm ~= nil) and (" ｜ 名字像=" .. tostring(kNm) .. "（" .. tostring(EVAL_TRACK_LABEL(kNm)) .. "）") or ""),
      who and (" ← 动作条：" .. who) or ""))
  end
  if auraKind ~= nil then
    trkSay("   ★★增益条里**有一条像追踪**（" .. tostring(auraKind) .. "（" .. tostring(EVAL_TRACK_LABEL(auraKind))
      .. "））⇒ 本客户端的追踪**占增益条槽位**（官方那句「not listed here」对本客户端不成立）")
  end

  if cur then
    trkSay("   ★①的纹理" .. (seen and "**在**增益条里出现 ⇒ 追踪占槽位（光环路线可用）"
      or "**没**出现在增益条 ⇒ 纹理这条路读不到追踪的信息"))
  end
  -- ⑥ 动作条里的追踪类技能（建纹理↔名字对照表）
  local nT = 0
  if type(wslots) == "table" then
    for nm, v in pairs(wslots) do
      if type(v) == "table" and type(v.tex) == "string" then
        local s = tostring(nm)
        local k2 = EVAL_TRACK_KIND(v.tex)
        -- 判据 = 纹理命中候选表 **或** 名字含关键字（前者语言无关；后者兜住候选表还没覆盖的）
        if k2 ~= nil or string.find(s, "追踪") or string.find(s, "寻找") or string.find(s, "Track") or string.find(s, "Find") then
          nT = nT + 1
          trkSay(string.format("   [动作条] %s ｜ slot=%s ｜ 种类=%s ｜ 纹理=%s", s, tostring(v.slot),
            (k2 ~= nil) and (tostring(k2) .. "（" .. tostring(EVAL_TRACK_LABEL(k2)) .. "）") or "（纹理没命中）", tostring(v.tex)))
        end
      end
    end
  end
  trkSay(string.format("⑥ 动作条里的追踪类技能：%d 个（纹理命中候选表 或 名字含「追踪/寻找/Track/Find」）", nT))
  -- ⑦ 法术书扫描（★1.75.3：判据从「名字含追踪/寻找」换成**纹理命中候选表** —— 名字判据会漏掉
  --   「感知恶魔 / 感知亡灵」这类名字里没有「追踪/寻找」的，且跨语言不可靠；纹理命中与③同一口径）
  --   ★两条都打：纹理命中的（= 这个角色已学的追踪）+ 仅名字命中的（= 我该补表的候选）
  local sbOk = (type(GetSpellName) == "function")
  trkSay("⑦ 法术书扫描：接口可用=" .. tostring(sbOk))
  if sbOk and type(GetSpellTexture) == "function" then
    local nSb, nSbName = 0, 0
    for i = 1, 400 do
      local okn, nm2 = pcall(GetSpellName, i, "spell")
      if not okn or type(nm2) ~= "string" or nm2 == "" then break end
      local tex2 = nil
      local okt, tv = pcall(GetSpellTexture, i, "spell")
      if okt and type(tv) == "string" then tex2 = tv end
      local k3 = EVAL_TRACK_KIND(tex2)
      if k3 ~= nil then
        nSb = nSb + 1
        trkSay(string.format("   [法术书 %d] %s ｜ 种类=%s ｜ 纹理=%s", i, tostring(nm2),
          tostring(k3) .. "（" .. tostring(EVAL_TRACK_LABEL(k3)) .. "）", tostring(tex2)))
      elseif string.find(nm2, "追踪") or string.find(nm2, "寻找") or string.find(nm2, "Track") or string.find(nm2, "Find") then
        nSbName = nSbName + 1
        trkSay(string.format("   [法术书 %d] %s ｜ ★纹理没命中候选表 ｜ 纹理=%s", i, tostring(nm2), tostring(tex2 or "?")))
      end
    end
    trkSay(string.format("   ↑ 纹理命中 %d 条 ／ 仅名字命中 %d 条（后者请把纹理原文回传，我据此补表）", nSb, nSbName))
  end
  trkSay("⑧ 事件监听：" .. (TRK.ev and "|cff00ff00开着|r（再跑一次 `监听` 关掉并看计数）"
    or "关（用 `/eh go 追踪探针 监听` 开；开完切换几次追踪再关，就能看出**哪条事件**真的跟着走）"))
  if cur then TRK.lastTex = cur end
  trkSay("⑨ 判定：① = **在不在追踪**（nil 就是没追踪）；② = **是哪一种**（本地化名字，采药/采矿/追踪野兽）；")
  trkSay("   ③ 纹理主路（基础名对候选表）+ 名字备用路（两条路**互证**，打架就报「不一致」）；")
  trkSay("   ⑤ 光环是**旁证**（若增益条里真有一条像追踪，报告会点出来 ⇒ 那就是本客户端追踪占槽位）；")
  trkSay("   ⑥⑦ 是「这个角色都学了哪些追踪」的旁证；⑧ 给「实时刷新」的事件判据（全事件抓取实测）；")
  -- ⑩ 默认 UI 的追踪按钮/图标（★1.75.4 第三条独立路：**游戏自己**认为当前追踪是什么）
  --   候选名 + 有界 `_G` 扫描（名字含 Track/追踪）；一个都没命中就**如实缺席**（UI 编译在 pak 里）
  trkSay("⑩ 默认 UI 追踪按钮（第三条独立路）：")
  local foundBtn, btnTxt = 0, {}
  for i = 1, table.getn(TRK.btnCands) do
    local nm2 = TRK.btnCands[i]
    local obj = rawget(_G, nm2)
    if obj ~= nil then
      foundBtn = foundBtn + 1
      local tex, shown, ot = nil, nil, nil
      if type(obj.GetTexture) == "function" then local okt, t = pcall(obj.GetTexture, obj) if okt then tex = t end end
      if type(obj.IsShown) == "function" then local oks, s = pcall(obj.IsShown, obj) if oks then shown = s end end
      local okg, g = pcall(obj.GetObjectType, obj)
      if okg then ot = g end
      table.insert(btnTxt, string.format("   [候选] %s ｜ 类型=%s ｜ 纹理=%s ｜ IsShown=%s",
        nm2, EVAL_TRACK_STR(ot), EVAL_TRACK_STR(tex), EVAL_TRACK_STR(shown)))
    end
  end
  for i = 1, table.getn(btnTxt) do trkSay(btnTxt[i]) end
  local gHits, gOk = EVAL_TRACK_SCAN_GLOBALS()
  trkSay(string.format("   `_G` 扫名字含 Track/追踪 的对象：扫描可信=%s 共 %d 条", tostring(gOk), table.getn(gHits)))
  local gCap = 20
  for i = 1, table.getn(gHits) do
    if i > gCap then trkSay(string.format("      …（还有 %d 条没列）", table.getn(gHits) - gCap)) break end
    trkSay("      " .. tostring(gHits[i]))
  end
  if foundBtn == 0 and table.getn(gHits) == 0 then
    trkSay("   （候选全不在 + 扫描 0 条 ⇒ 本客户端没有这些全局名，或追踪按钮不叫这个 ⇒ 把线索回传）")
  end
  -- ⑪ 一行快照：开/关各跑一次，**直接比这一行**就够了（不用逐行对照）
  trkSay(string.format("⑪ 一行快照：纹理类型=%s ｜ 纹理=%s ｜ 名字=%s（why=%s） ｜ 光环=%d 个 ｜ 追踪按钮命中=%d ｜ 扫描=%d 条",
    tostring(rawType), EVAL_TRACK_STR(raw), EVAL_TRACK_STR(nm), tostring(nmWhy or "?"),
    table.getn(bl), foundBtn, table.getn(gHits)))
  return 1
end

function EVAL_RULE_RUN(rules)
  local acted = false -- 1.53.0：非 GCD 类型出手也算有动作（但继续评估后续规则）
  for _, r in ipairs(rules) do
    if r.enabled == false then
      -- 技能配置开关关掉的：静默跳过
    elseif not wslots[r.skill] and not skillNoSlotOk(r.skill, r.rank) then -- ★1.72.4 单一判据（rank = 指定等级，走 RunScript 不需要动作条）
      wlog(r.skill .. "跳过: 不在动作条")
    elseif wImmuneTo(r.skill) then
      wlog(r.skill .. "跳过: 目标已免疫（学习记录 " .. tostring(st.targetName) .. "）")
    elseif TARGET_SEL_TEAMSEL[targetSelOf(r.skill)] then
      -- ★★1.70.47「选取目标:队伍成员/团队成员」技能行——**不做常规条件预判**：
      --   那一行的条件列表是给**候选**用的过滤条件（目标血量/目标buff/目标debuff 说的是「被扫描到的那个人」），
      --   拿它对「当前目标」预判毫无意义（一个都过不了 → 扫描器永远不执行）。
      --   所以直接进 wuse，由 EVAL_TEAM_PICK 逐候选判定（见那里的 ① 分支）。
      teamPickArg.rule = r
      local tsel = targetSelOf(r.skill)
      TARGET_SEL_ARG_LAST = tsel
      local okw = wuse(r.skill, r.why or r.skill, r.rank)
      teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
      if okw then
        acted = true
        EVAL_HELP_UPDATE_STATE() -- 目标已切到选中成员，后续条件按新状态判定
      else
        wlog(r.skill .. "跳过: 队伍/团队里没有符合该行条件的成员")
      end
    else
      local ok, why, trace
      if r.groups then ok, why, trace = groupsOK(r) else ok, why = condOK(r.when or {}, r.skill) end
      if ok then
        if wuse(r.skill, r.why or r.skill, r.rank) then
          -- 释放成功：记入释放日志（状态信息UI「最近释放」展示触发条件明细）
          st.castLog = st.castLog or {}
          table.insert(st.castLog, 1, {
            t = GetTime(),
            skill = r.skill,
            rank = r.rank, -- ★1.72.4 释放日志也记等级（否则两条只差等级的规则在「最近释放」里长得一模一样）
            why = r.why or r.skill,
            trace = trace or "",
            target = (st.hasTarget and st.targetName) and tostring(st.targetName) or "",
          })
          while table.getn(st.castLog) > 5 do table.remove(st.castLog) end
          if trace then wlog(r.skill .. "触发: " .. trace) end
          -- 1.59.0 去除公共CD终止机制（用户定义）：按顺序把符合的规则全部执行一遍——
          -- 能不能放交给游戏内置判定（GCD 中 UseAction 静默失败，不产生副作用）；
          -- 1.53.0 的 gcdSkill 终止删除，所有类型统一：出手后刷新状态、继续评估后续规则。
          acted = true
          EVAL_HELP_UPDATE_STATE() -- 目标/状态可能已变，后续条件按新状态判定
        end
      else
        wlog(r.skill .. "跳过: " .. tostring(why))
      end
    end
  end
  return acted
end

-- ===== 条件串解析（UI 输入框 / /eh war add 用）："怒气>30 & 战斗中 | 非战斗" =====
local function condTrim(s) return (string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end
local COND_NUM = {
  ["怒气"] = "power", ["能量"] = "power", ["power"] = "power",
  -- ★★★1.73.27 资源名的**其他叫法**（单位权力 0=法力 / 2=集中值）：法系资源就是「法力/魔法值」，
  --   而导出/回显用的名字来自 EVAL_POWERLABEL()（动态）→ **解析侧必须认这些名字**，
  --   否则法系玩家把方案导出再导入就会丢条件（本项目「导出侧与解析侧成对验」的老纪律）。
  ["法力"] = "power", ["魔法"] = "power", ["魔法值"] = "power", ["蓝"] = "power",
  ["集中值"] = "power", ["集中"] = "power", ["精力"] = "power",
  ["目标血"] = "tHpPct", ["tHpPct"] = "tHpPct",
  ["自身血"] = "hpPct", ["hpPct"] = "hpPct",
  ["能量%"] = "powerPct", ["powerPct"] = "powerPct",
  -- ★1.73.27 各资源名的百分比写法（少一个都会让「导出→导入」丢条件）
  ["法力%"] = "powerPct", ["魔法%"] = "powerPct", ["魔法值%"] = "powerPct", ["蓝%"] = "powerPct",
  ["集中值%"] = "powerPct", ["集中%"] = "powerPct", ["怒气%"] = "powerPct", ["精力%"] = "powerPct",
  ["进战"] = "combatTime", ["combatTime"] = "combatTime",
  ["读条"] = "tCastEl", ["tCastEl"] = "tCastEl", ["读条剩"] = "tCastLeft", ["tCastLeft"] = "tCastLeft", -- 1.40.0 目标读条秒数
  ["自身读条"] = "castEl", ["castEl"] = "castEl", ["自身读条剩"] = "castLeft", ["castLeft"] = "castLeft", -- 1.41.0 自身读条秒数
  -- ★1.71.2 改名后的新写法（用户定名）；旧写法**全部保留**——存量方案里的「读条>2」不能因改名失效
  ["施法时间"] = "castEl", ["施法剩余时间"] = "castLeft",
  ["目标施法时间"] = "tCastEl", ["目标施法剩余时间"] = "tCastLeft",
  ["连击"] = "combo", ["连击点"] = "combo", ["combo"] = "combo",
  ["距攻击"] = "swingLeft", ["swingLeft"] = "swingLeft", -- 1.57.0 距下次攻击秒数
  ["距射击"] = "shotLeft", ["距下次射击"] = "shotLeft", ["shotLeft"] = "shotLeft", -- ★1.74.30 距下次射击秒数（与「距攻击」成对）
  -- ★★★1.75.11 近战围攻 / 交战人数（条件类型 → 自身状态；数值比较：步进 1 / 默认 1 / 上限 10）
  --   用户原话：「技能编辑->添加条件类型->自身状态->10s交战人数N数量 比较类型,围攻自身N数量 比较类型.递步1 默认1 <10」
  --   ★导出走这两个中文名（摘要/回显同一份）；导入两种写法都认（中文名 + 英文 id）
  ["围攻"] = "mwSiege", ["围攻数"] = "mwSiege", ["围攻自身"] = "mwSiege", ["围攻自身数量"] = "mwSiege", ["mwSiege"] = "mwSiege",
  ["交战"] = "mwEngaged", ["交战数"] = "mwEngaged", ["交战人数"] = "mwEngaged", ["mwEngaged"] = "mwEngaged",
  -- ★1.70.47 队伍/团队血量·蓝量百分比（条件自己去队里挑「血最少/蓝最少」的那个人，见 condOne）
  ["队伍血"] = "teamHp", ["队伍血量"] = "teamHp", ["teamHp"] = "teamHp",
  ["队伍蓝"] = "teamMana", ["队伍蓝量"] = "teamMana", ["teamMana"] = "teamMana",
  ["团队血"] = "teamHp", ["团队血量"] = "teamHp",
  ["团队蓝"] = "teamMana", ["团队蓝量"] = "teamMana",
  -- ★1.71.3 候选者条件（选取器行的候选过滤；只在选取器行有意义）
  ["候选者血"] = "candHp", ["候选血"] = "candHp", ["candHp"] = "candHp",
  ["候选者能量"] = "candPower", ["候选能量"] = "candPower", ["candPower"] = "candPower",
}
local COND_BOOL = {
  ["战斗中"] = { "combat", true }, ["非战斗"] = { "combat", false }, ["combat"] = { "combat", true },
  ["目标存在"] = { "hasTarget", true }, ["有目标"] = { "hasTarget", true }, ["无目标"] = { "hasTarget", false }, ["hasTarget"] = { "hasTarget", true },
  ["可攻击"] = { "canAttack", true }, ["canAttack"] = { "canAttack", true },
  -- ★★★1.70.43 往返一致性的核心修复：以下 8 条「取反写法」**导出侧一直在写、解析侧一直没有**
  --   （EVAL_COND_STR 第 1224~1232 行会输出 不可攻击/不可流血/非精英/非Boss/目标非战斗/非友善/非敌对/非中立），
  --   而 EVAL_PARSE_ONE 只认 COND_BOOL 里已有的键 + 感叹号前缀 → 这些写法解析为 nil
  --   → EVAL_PARSE_CONDS 只 push 非 nil → **条件被静默丢弃**（用户看不到任何报错）。
  --   影响：任何用到这些条件的方案，一旦「导出→导入」或经案例模版导入，条件就消失。
  --   ★教训：序列化器的输出域必须用一条「导出→导入」往返断言锁死（见 test 组 59），
  --     否则两侧各自演化，缺口只会在用户数据里静默出现。
  ["不可攻击"] = { "canAttack", false },
  ["可流血"] = { "canBleed", true }, ["canBleed"] = { "canBleed", true },
  ["不可流血"] = { "canBleed", false },
  -- ★1.75.10 目标死亡（导出侧写「目标死亡/目标未死亡」，解析侧必须成对认；缺一半 = 导入即丢条件）
  ["目标死亡"] = { "tDead", true }, ["tDead"] = { "tDead", true },
  ["目标未死亡"] = { "tDead", false }, ["目标没死"] = { "tDead", false },
  ["精英"] = { "isElite", true }, ["isElite"] = { "isElite", true },
  ["非精英"] = { "isElite", false },
  ["Boss"] = { "isBoss", true }, ["首领"] = { "isBoss", true }, ["isBoss"] = { "isBoss", true },
  ["非Boss"] = { "isBoss", false }, ["非首领"] = { "isBoss", false },
  ["目标战斗中"] = { "tInCombat", true }, ["tInCombat"] = { "tInCombat", true },
  ["目标非战斗"] = { "tInCombat", false },
  ["目标友善"] = { "tFriendly", true }, ["友善"] = { "tFriendly", true }, ["tFriendly"] = { "tFriendly", true },
  ["非友善"] = { "tFriendly", false },
  ["目标敌对"] = { "tHostile", true }, ["敌对"] = { "tHostile", true }, ["tHostile"] = { "tHostile", true },
  ["非敌对"] = { "tHostile", false },
  ["目标中立"] = { "tNeutral", true }, ["中立"] = { "tNeutral", true }, ["tNeutral"] = { "tNeutral", true },
  ["非中立"] = { "tNeutral", false },
  ["Alt"] = { "alt", true }, ["alt"] = { "alt", true },
  ["Shift"] = { "shift", true }, ["shift"] = { "shift", true },
  ["Ctrl"] = { "ctrl", true }, ["ctrl"] = { "ctrl", true },
  ["普攻"] = { "autoAttack", true }, ["autoAttack"] = { "autoAttack", true },
  ["自动射击"] = { "autoShot", true }, ["autoShot"] = { "autoShot", true }, -- 1.51.0（取反写 !自动射击 或 未自动射击）
  ["未自动射击"] = { "autoShot", false },
  ["魔杖射击"] = { "wandShoot", true }, ["wandShoot"] = { "wandShoot", true },
  ["未魔杖射击"] = { "wandShoot", false },
  ["未普攻"] = { "autoAttack", false }, -- 1.51.0 补旧缺口：显示层早有 未普攻，解析层一直不会
}
local COND_FLAG = {
  ["就绪"] = "ready", ["ready"] = "ready",
  ["可用"] = "usable", ["usable"] = "usable",
  ["未排队"] = "notQueued", ["notQueued"] = "notQueued",
}
-- ★1.70.43 反向 flag 单独一张表：COND_FLAG 的值只是「键名」，表达不了 inv 语义。
--   导出侧（EVAL_COND_STR 第 1250~1252 行）会写 未就绪 / 不可用 / 已排队，
--   而这三个此前不在任何表里 → 导入同样被静默丢弃。与上面 8 条是同一个缺口的两半。
local COND_FLAG_INV = {
  ["未就绪"] = "ready", ["notready"] = "ready",
  ["不可用"] = "usable", ["notusable"] = "usable",
  ["已排队"] = "notQueued", ["queued"] = "notQueued",
}

-- ★1.70.45 内层：原 EVAL_PARSE_ONE 主体。外层（见下方 EVAL_PARSE_ONE）负责先剥掉
--   「剩余时间」后缀 [<30s]，再统一挂到结果 cd 上——这样 8 个光环分支一处都不用改，
--   也保证任何分支都不会把后缀当成光环名字的一部分（否则名字错=永远静默匹配不上）。
local function parseOneRaw(token)
  token = condTrim(colonNorm(token)) -- ★1.71.3 全角冒号先归一（多字节字符不能进 Lua 的 [...] 字节集）
  if token == "" then return nil end
  local neg = false
  if string.sub(token, 1, 1) == "!" then neg = true token = condTrim(string.sub(token, 2)) end
  local name, op, num = string.match(token, "^(.-)([><]=?)(%d+)$")
  if name and COND_NUM[condTrim(name)] then
    local ck = COND_NUM[condTrim(name)]
    -- ★1.70.47 队伍/团队血蓝：「团队血<50」要带上扫描范围（cd.name），否则导出回来会退化成队伍
    if ck == "teamHp" or ck == "teamMana" then
      local sc = string.match(condTrim(name), "^团队") and "团队" or "队伍"
      return { k = ck, op = op, n = tonumber(num), name = sc }
    end
    return { k = ck, op = op, n = tonumber(num) }
  end
  -- ★1.71.3 候选者血/能量支持「=」（取最接近）：上面那条通用模式只认 < > <= >=，这里补一次
  local cn2, cop2, cnum2 = string.match(token, "^(.-)([><=]=?)(%d+)$")
  if cn2 then
    local ck2 = COND_NUM[condTrim(cn2)]
    if ck2 == "candHp" or ck2 == "candPower" then
      return { k = ck2, op = cop2, n = tonumber(cnum2) }
    end
  end
  local fn = string.match(token, "^姿态(%d)$")
  if fn then return { k = "form", n = tonumber(fn) } end
  fn = string.match(token, "^非姿态(%d)$")
  if fn then return { k = "formNot", n = tonumber(fn) } end
  -- 光环层数后缀（1.31.0 debuff 起；1.70.1 扩到四类光环）：名>=3（至少3层）/ 名<3（不足3层）；无后缀=只要有/没有
  -- want: "min"=有(至少N层，只收 >/>=)；"max"=无(不足N层，只收 </<=)。
  -- 1.32.0 审计修复：反向 op（如 有debuff:x<3）语义会反转成 cnt>=3 的静默逻辑坑——降级为无层数限制
  -- 注：本函数必须定义在下方各光环解析分支【之前】（Lua local 作用域从声明后开始）
  local function auraStack(body, want)
    local nm, op, n = string.match(body, "^(.-)([><]=?=?)(%d+)$")
    if not nm then return condTrim(body), nil end
    if want == "min" and op ~= ">" and op ~= ">=" then return condTrim(nm), nil end
    if want == "max" and op ~= "<" and op ~= "<=" then return condTrim(nm), nil end
    n = tonumber(n)
    if op == ">" then n = n + 1 elseif op == "<=" then n = n + 1 end -- >N 即 >=N+1；<=N 即 <N+1
    return condTrim(nm), n
  end
  -- ★★★1.74.6 「名字(类型) 层数门槛」（用户：「自身/目标debuff 要参考队伍debuff 支持 debuff 负面类型」）：
  --   与 teamDebuff 同一套写法 —— 「断筋(魔法)」/「断筋(魔法) >=2」/「魔法」/「魔法 >=2」都能解析；
  --   ★没写括号时**与旧行为逐字一致**（dt=nil），存量文本一个字节都不变（兼容性的根）。
  local function auraStackSplit(body, want)
    local head, n = auraStack(body, want) -- ① 先剥层数后缀（"X >=2" → X）
    local nm, dt = dispelSplit(head or "") -- ② 再拆名字/类型（"名(类型)" / "类型" / "名"）
    if dt == nil and head ~= body then
      -- 层数后缀没被识别（方向不对）→ 退回原串再拆一次，免得把「(类型) <2」整串当成名字
      local nm2, dt2 = dispelSplit(body)
      if dt2 ~= nil then return nm2, n, dt2 end
    end
    if nm == "" then nm = nil end
    return nm, n, dt
  end
  local bs = string.match(token, "^无buff[:：](.+)$") or string.match(token, "^noBuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "max") return { k = "hasBuff", s = nm, n = n, v = false } end -- 1.54.0 合并为 hasBuff+v（旧 noBuff 词条仍认）；1.70.1 层数
  local tb = string.match(token, "^目标buff[:：](.+)$") or string.match(token, "^tBuff[:=](.+)$") -- 1.54.0；1.70.1 层数
  if tb then local nm, n = auraStack(tb, "min") return { k = "tBuff", s = nm, n = n, v = not neg } end
  local tbn = string.match(token, "^无目标buff[:：](.+)$") or string.match(token, "^目标无buff[:：](.+)$")
  if tbn then local nm, n = auraStack(tbn, "max") return { k = "tBuff", s = nm, n = n, v = false } end
  local pd = string.match(token, "^自身debuff[:：](.+)$") or string.match(token, "^pDebuff[:=](.+)$")
  if pd then local nm, n, dt = auraStackSplit(pd, "min") return { k = "pDebuff", s = nm, n = n, dt = dt, v = not neg } end
  local pdn = string.match(token, "^无自身debuff[:：](.+)$") or string.match(token, "^自身无debuff[:：](.+)$")
  if pdn then local nm, n, dt = auraStackSplit(pdn, "max") return { k = "pDebuff", s = nm, n = n, dt = dt, v = false } end
  bs = string.match(token, "^有buff[:：](.+)$") or string.match(token, "^hasBuff[:=](.+)$")
  if bs then local nm, n = auraStack(bs, "min") return { k = "hasBuff", s = nm, n = n } end
  bs = string.match(token, "^无debuff[:：](.+)$") or string.match(token, "^noDebuff[:=](.+)$")
  if bs then local nm, n, dt = auraStackSplit(bs, "max") return { k = "hasDebuff", s = nm, n = n, dt = dt, v = false } end -- 1.54.0 合并；1.74.6 类型
  bs = string.match(token, "^有debuff[:：](.+)$") or string.match(token, "^hasDebuff[:=](.+)$")
  if bs then local nm, n, dt = auraStackSplit(bs, "min") return { k = "hasDebuff", s = nm, n = n, dt = dt } end
  -- ★1.70.47 队伍/团队 buff/debuff（导入/文本编辑）：前缀「队伍」或「团队」决定扫描范围（cd.name）。
  --   写法：有/无{队伍|团队}buff:名 ；有/无{队伍|团队}debuff:名(类型) 或直接写类型 ；英文 id teamBuff/teamDebuff(默认队伍)
  --   ★★★两条 Lua 模式的硬规矩（都是本项目 H 节记过、我这次又踩的）：
  --     ① **`|` 不是交替**——写成 (队伍|团队) 只在匹配字面串「队伍|团队」时成立，
  --        结果是任何队伍/团队条件都解析不出来（表现：编辑窗存了、再导入条件**静默消失**）。
  --     ② **字符组不能装多字节字**——`[伍团]` 是**按字节**匹配的集合，
  --        匹配 '伍' 的首字节后剩下两个尾字节对不上后面的 buff，照样失败。
  --     所以这里改成「先用 .+ 抓前缀，再**用字符串比较**校验前缀」——不受多字节影响。
  local function teamScope(pfx)
    if pfx == "队伍" or pfx == "团队" then return pfx end
    return nil
  end
  local p1, p2
  p1, p2 = string.match(token, "^有(.+)buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "min")
    return { k = "teamBuff", s = nm, n = n, v = not neg, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^无(.+)buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "max")
    return { k = "teamBuff", s = nm, n = n, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^(.+)无buff[:：](.+)$")
  if p1 and teamScope(p1) then local nm, n = auraStack(p2, "max")
    return { k = "teamBuff", s = nm, n = n, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^有(.+)debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = not neg, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^无(.+)debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = false, name = teamScope(p1) } end
  p1, p2 = string.match(token, "^(.+)无debuff[:：](.*)$")
  if p1 and teamScope(p1) then local nm, dt = dispelSplit(p2)
    return { k = "teamDebuff", s = nm, dt = dt, v = false, name = teamScope(p1) } end
  -- 英文 id（默认队伍范围）
  local tbf = string.match(token, "^teamBuff[:=](.+)$")
  if tbf then local nm, n = auraStack(tbf, "min")
    return { k = "teamBuff", s = nm, n = n, v = not neg, name = "队伍" } end
  local tdb = string.match(token, "^teamDebuff[:=](.*)$")
  if tdb then local nm, dt = dispelSplit(tdb)
    return { k = "teamDebuff", s = nm, dt = dt, v = not neg, name = "队伍" } end
  -- ★1.71.3 候选者 buff/debuff（选取器行的候选过滤；只在选取器行有意义）
  local cbf = string.match(token, "^候选者缺buff[:：](.+)$") or string.match(token, "^候选者无buff[:：](.+)$")
    or string.match(token, "^candBuff[:=](.+)$")
  if cbf then local nm, n = auraStack(cbf, "max") return { k = "candBuff", s = nm, n = n, v = false } end
  local cbs = string.match(token, "^候选者buff[:：](.+)$")
  if cbs then local nm, n = auraStack(cbs, "min") return { k = "candBuff", s = nm, n = n, v = true } end
  local cdbf = string.match(token, "^候选者debuff[:：](.*)$") or string.match(token, "^candDebuff[:=](.*)$")
  if cdbf then local nm, dt = dispelSplit(cdbf) return { k = "candDebuff", s = nm, dt = dt, v = not neg } end
  local cdbn = string.match(token, "^候选者无debuff[:：](.*)$")
  if cdbn then local nm, dt = dispelSplit(cdbn) return { k = "candDebuff", s = nm, dt = dt, v = false } end
  -- 1.70.28 目标类型（导入）：支持 目标类型:野兽/元素、目标类型非:元素、tCreature=beast
  local tcr = string.match(token, "^目标类型非[:：](.+)$") or string.match(token, "^notcreature[:=](.+)$")
  if tcr then
    tcr = string.gsub(tcr, "、", "/") tcr = string.gsub(tcr, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tcr, "[^/,]+") do
      local id = creatureTypeId(condTrim(nm))
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tCreature", cs = cs, v = false } end
    return nil
  end
  local tcp = string.match(token, "^目标类型[:：](.+)$") or string.match(token, "^tCreature[:=](.+)$")
  if tcp then
    tcp = string.gsub(tcp, "、", "/") tcp = string.gsub(tcp, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tcp, "[^/,]+") do
      local id = creatureTypeId(condTrim(nm))
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tCreature", cs = cs } end
    return nil
  end
  -- ★★★1.75.10 目标玩家（导入/文本编辑）：目标玩家:X / tPlayer=X ；目标不是玩家:X / notplayer=X ；前置 ! 也认。
  --   ★空名 = 写法错误 → 返回 nil **如实丢弃**（与其它条件同口径：宁可整条不要，也不静默留半个条件）。
  local tpl = string.match(token, "^目标玩家[:：](.+)$") or string.match(token, "^tPlayer[:=](.+)$")
  if tpl then
    local nmP = condTrim(tpl)
    if nmP == "" then return nil end
    return { k = "tPlayer", nm = nmP, v = not neg }
  end
  local tpln = string.match(token, "^目标不是玩家[:：](.+)$") or string.match(token, "^notplayer[:=](.+)$")
  if tpln then
    local nmP2 = condTrim(tpln)
    if nmP2 == "" then return nil end
    return { k = "tPlayer", nm = nmP2, v = false }
  end
  local tc = string.match(token, "^目标职业[:：](.+)$") or string.match(token, "^tClass[:=](.+)$")
  if tc then
    -- 分隔统一成 / 再切：顿号/中文逗号是多字节，直接进字符类会按字节误切汉字（如"猎"含 ，的字节）
    tc = string.gsub(tc, "、", "/")
    tc = string.gsub(tc, "，", "/")
    local cs, any = {}, false
    for nm in string.gmatch(tc, "[^/,]+") do
      local id = CLASS_ID[condTrim(nm)]
      if id then cs[id] = true any = true end
    end
    if any then return { k = "tClass", cs = cs } end
    return nil
  end
  -- 1.40.0 目标施法中：空前缀=任意施法，带名=指定技能；未施法=取反
  if string.find(token, "^目标未施法") or string.find(token, "^tnotcasting") then return { k = "tCasting", s = nil, v = false } end
  local tct = string.match(token, "^目标施法中[:：]?(.-)$") or string.match(token, "^tcasting[:=]?(.-)$")
  if tct ~= nil then return { k = "tCasting", s = (tct ~= "" and condTrim(tct)) or nil, v = not neg } end
  local imt = string.match(token, "^免疫[:：](.+)$") or string.match(token, "^immune[:=](.+)$") -- 1.36.1 免疫条件
  if imt then return { k = "immune", s = condTrim(imt), v = not neg } end
  local imn = string.match(token, "^未免疫[:：](.+)$") or string.match(token, "^notimmune[:=](.+)$")
  if imn then return { k = "immune", s = condTrim(imn), v = false } end
  local irg = string.match(token, "^范围内[:：](.+)$") or string.match(token, "^inrange[:=](.+)$") or string.match(token, "^range[:=](.+)$") -- 1.37.0 射程条件
  if irg then return { k = "inRange", s = condTrim(irg), v = not neg } end
  local irn = string.match(token, "^范围外[:：](.+)$") or string.match(token, "^notinrange[:=](.+)$")
  if irn then return { k = "inRange", s = condTrim(irn), v = false } end
  -- ★1.75.6 追踪类型条件（用户新增）：追踪[:id] / tracking[=id]；裸形式 = 任意追踪；
  --   未追踪 / nottracking / 前置 ! = 反向。★id 认「稳定 id / 图标基础名 / enUS / zhCN / 本地化标签」，
  --   认不出**返回 nil**（与其它条件的写法错误同口径：如实丢弃，不静默留半个条件）。
  local tk = string.match(token, "^追踪[:：]?(.*)$") or string.match(token, "^tracking[:=]?(.*)$")
  if tk ~= nil then
    local tidTxt = condTrim(tk)
    if tidTxt == "" then return { k = "tracking", s = "any", v = not neg } end
    local pid = EVAL_TRACK_PARSE_ID(tidTxt)
    if pid == nil then return nil end
    return { k = "tracking", s = pid, v = not neg }
  end
  local tnk = string.match(token, "^未追踪[:：]?(.*)$") or string.match(token, "^nottracking[:=]?(.*)$")
  if tnk ~= nil then
    local tidTxt2 = condTrim(tnk)
    if tidTxt2 == "" then return { k = "tracking", s = "any", v = false } end
    local pid2 = EVAL_TRACK_PARSE_ID(tidTxt2)
    if pid2 == nil then return nil end
    return { k = "tracking", s = pid2, v = false }
  end
  local tg = string.match(token, "^选取目标[:：](.+)$") or string.match(token, "^target[:=](.+)$")
  -- ★★1.75.10 英文 id 形态（byName=名 / playerTarget=名 / assistbyname=名）必须在**入口**归一：
  --   下面 `if tg then` 里那两条 `^byName[:=]` 分支，因为入口的 tg 只认「选取目标:/target:」，
  --   实际上是**死代码**（"byName=嗜血者" 连门都进不来）。这里补入口归一，一次救活两种带名选取器；
  --   裸 id（"playerTarget" / "byName"）也一并认（与「目标玩家」的 tPlayer= 同族的英文写法）。
  if not tg then
    local idEn, nmEn = string.match(token, "^(byName)[:=](.+)$")
    if not idEn then idEn, nmEn = string.match(token, "^(playerTarget)[:=](.+)$") end
    if not idEn then idEn, nmEn = string.match(token, "^(assistbyname)[:=](.+)$") end
    if not idEn then idEn, nmEn = string.match(token, "^(byName|playerTarget)$") end
    if idEn then
      if idEn == "assistbyname" then idEn = "playerTarget" end -- 函数名写法 = 同一个选取器
      local dispEn = TARGET_SEL_NAME[idEn] or idEn
      tg = nmEn and (dispEn .. ":" .. nmEn) or dispEn
    end
  end
  -- ★1.71.2 冒号可省：导出侧的**裸形式**「施法中」（不指定技能名）以前解析不回（配合 EVAL_COND_STR 的空名修复）
  local cst = string.match(token, "^施法中[:：]?(.*)$") or string.match(token, "^casting[:=]?(.*)$") -- 1.38.0 施法中条件
  -- ★1.71.2 空前缀（裸「施法中」）归一成 s=nil——与 tCasting 完全一致；「空串」和「nil」在求值里等价，
  --   但归一是为了让「同一个条件」不管从哪种写法读进来，表示形式都一样（否则 EVAL_GROUP_STR 回显会飘）。
  if cst then return { k = "casting", s = (cst ~= "" and condTrim(cst)) or nil, v = not neg } end
  local csn = string.match(token, "^未施法[:：]?(.*)$") or string.match(token, "^notcasting[:=]?(.*)$") -- 1.71.2 冒号可省（裸「未施法」也能读回）
  if csn then return { k = "casting", s = (csn ~= "" and condTrim(csn)) or nil, v = false } end
  if token == "施法中" or token == "casting" then return { k = "casting", s = nil, v = not neg } end -- 1.41.0 裸形式=任意施法
  if token == "未施法" or token == "notcasting" then return { k = "casting", s = nil, v = false } end
  if tg then
    -- 指定名称:嗜血者 / byName=嗜血者（1.29.0：名称存 cd.nm）
    local nm = string.match(tg, "^指定名称[:：](.+)$") or string.match(tg, "^byName[:=](.+)$")
    if nm then nm = condTrim(nm) if nm ~= "" then return { k = "target", s = "byName", nm = nm } end return nil end
    -- ★1.75.10 玩家的目标:嗜血者 / playerTarget=嗜血者 / assistbyname=嗜血者（名称同样存 cd.nm）
    local nmA = string.match(tg, "^玩家的目标[:：](.+)$") or string.match(tg, "^playerTarget[:=](.+)$")
      or string.match(tg, "^assistbyname[:=](.+)$")
    if nmA then nmA = condTrim(nmA) if nmA ~= "" then return { k = "target", s = "playerTarget", nm = nmA } end return nil end
    local id = TARGET_SEL_ID[condTrim(tg)]
    if id then return { k = "target", s = id } end
    return nil
  end
  local b = COND_BOOL[token]
  -- 1.51.0 修复取反优先级：旧式 neg and (not b[2]) or b[2] 在 b[2]=true（全部条目）时 ! 恒失效
  if b then local vv = b[2] if neg then vv = not vv end return { k = b[1], v = vv } end
  local fl = COND_FLAG[token]
  if fl then return { k = fl, inv = neg } end
  -- ★1.70.43 反向 flag（未就绪/不可用/已排队）：inv 恒为 true；「!未就绪」= 双重取反 = 就绪
  local fli = COND_FLAG_INV[token]
  if fli then return { k = fli, inv = not neg } end
  return nil
end

-- ★★1.70.45 剩余时间后缀 [<op><n>s]（用户要求：buff 类条件加「剩余时间检查」，单位秒）。
--   语法示例：无buff:奥术智慧[<30s]  = 没有「奥术智慧」或 剩余不足 30 秒
--           有buff:奥术智慧[>=60s] = 有，且剩余至少 60 秒
--   ★为什么用方括号：层数后缀（名<N / 名>=N）已经占用了「名字后面直接跟比较符」的写法，
--     两者若共用一套语法必然歧义。方括号把时间段整个包住、且以 s 结尾，互不干扰。
--   ★作用范围：本客户端**只有自身光环**有时长 API（wiki globals/Buff：
--     GetPlayerBuffTimeLeft 返回秒；其他单位的 UnitBuff/UnitDebuff 只给图标+层数）。
--     故后缀**只在 自身buff(hasBuff) / 自身debuff(pDebuff) 上生效**；
--     目标两类即使写了也会在求值阶段如实返回 false（见 condOne 的注释），不静默当作没写。
--   ★非光环条件带这个后缀 = 写法错误 → 返回 nil（宁可丢弃，也不静默接受一个无意义的字段）。
-- ★★★1.71.3 队伍/团员条件的「职业多选 / 队伍多选」后缀：[职业:战士/法师][队伍:1/3]
--   ★剥法：从**串尾**反复剥（两种顺序任意、可只写一个）；分隔符先归一成 "/" 再切——
--     绝不用 [^…] 去切**多字节**分隔符（Lua 的字符集按**字节**匹配，见 colonNorm 上面那条注释）。
--   ★空集 = **不过滤**（与「目标职业」的「空 = 永不满足」正好相反，两边各有专属断言）。
local function splitFilterSet(body)
  local norm = string.gsub(tostring(body or ""), "、", "/")
  norm = string.gsub(norm, "，", "/")
  norm = string.gsub(norm, ",", "/")
  local out = {}
  for one in string.gmatch(norm, "[^/]+") do
    local v = condTrim(one)
    if v ~= "" then table.insert(out, v) end
  end
  return out
end
-- 职业显示名（或英文 id）→ 类文件名（"战士" → "WARRIOR"）：与「目标职业」共用 CLASS_LIST（单一来源）
local function classIdOfName(nm)
  local s = condTrim(nm or "")
  if s == "" then return nil end
  for _, c in ipairs(CLASS_LIST) do if c.name == s then return c.id end end
  local up = string.upper(s)
  for _, c in ipairs(CLASS_LIST) do if c.id == up then return c.id end end
  return nil
end
-- ★★★1.71.3 尾巴上的一对方括号：[<label>:内容]（内容**不许含 ]**，否则会把后面那个方括号组一起吞掉——
--   本轮实测踩到：`[职业:术士][队伍:2]` 被当成一个「职业」组，职业解析失败、队伍过滤还整段丢了）。
--   ★半角/全角冒号**分别匹配**，绝不写成 `[:：]` 字节集（多字节字符进 Lua 字符集=只吃一个字节）。
local function matchFilterTail(s, label)
  local head, body = string.match(s, "^(.-)%[" .. label .. ":([^%]]-)%]$")
  if body then return head, body end
  return string.match(s, "^(.-)%[" .. label .. "：([^%]]-)%]$")
end
local function parseTeamFilterSuffix(token)
  local cs, gs, s = nil, nil, tostring(token or "")
  for _ = 1, 4 do
    local head, body = matchFilterTail(s, "职业")
    if body then
      -- ★一个有效项都没有时**不留下空集**：空集与「没写」必须是同一件事（否则导出会写出 `[职业:]`）
      local set = {}
      for _, nm in ipairs(splitFilterSet(body)) do
        local id = classIdOfName(nm)
        if id then set[id] = true end
      end
      if next(set) then
        cs = cs or {}
        for kk in pairs(set) do cs[kk] = true end
      end
      s = condTrim(head)
    else
      local head2, body2 = matchFilterTail(s, "队伍")
      if not body2 then break end
      local set2 = {}
      for _, nm in ipairs(splitFilterSet(body2)) do
        local v = tonumber(nm)
        if v and v >= 1 and v <= 8 then set2[v] = true end
      end
      if next(set2) then
        gs = gs or {}
        for kk in pairs(set2) do gs[kk] = true end
      end
      s = condTrim(head2)
    end
  end
  return cs, gs, s
end

function EVAL_PARSE_ONE(token)
  token = condTrim(token)
  if token == "" then return nil end
  -- ★1.71.3 先剥「职业/队伍」过滤后缀（在「剩余时间」之前：两者都用方括号，先剥长的那个）
  local csF, gsF, rest = parseTeamFilterSuffix(token)
  local stripped, sop, snum = string.match(rest, "^(.-)%[([<>=]+)(%d+)s%]$")
  local cd = parseOneRaw(stripped and condTrim(stripped) or rest)
  if not cd then return nil end
  if csF or gsF then
    -- ★只有队伍/团员条件支持这两个过滤；别的类型写它 = 写法错误 → **如实丢弃**（不静默留一个无意义字段）
    -- ★★★1.71.3 允许的**成员类**条件：8 项队伍/团员 + 4 项候选者（后者就是选取器行的过滤条件，
    --   「只给法师补智力」这类模版全靠它）；别的类型写这个后缀 = 写法错误 → 如实丢弃。
    local kmem = cd.k
    if kmem ~= "teamHp" and kmem ~= "teamMana" and kmem ~= "teamBuff" and kmem ~= "teamDebuff"
       and kmem ~= "candHp" and kmem ~= "candPower" and kmem ~= "candBuff" and kmem ~= "candDebuff" then
      return nil
    end
    cd.cs, cd.gs = csF, gsF
  end
  if not stripped then return cd end
  if cd.k == "hasBuff" or cd.k == "pDebuff" or cd.k == "tBuff" or cd.k == "hasDebuff" then
    cd.secOp, cd.secN = sop, tonumber(snum)
    return cd
  end
  return nil -- 非光环条件不允许带剩余时间后缀
end

-- 测试直调：单条件求值（EVAL_RULE_RUN 会跳过「不在动作条」的技能，无法用于纯粹的条件断言）
function EVAL_COND_EVAL(cd) return condOne(cd, nil, true) end

-- ★1.70.47 断言专用：以**非 dry** 方式求值单个条件（= 按宏时真正走的那条路）。
--   存在理由：dry 模式不执行副作用（不切目标）、也不做队伍扫描；
--   而队伍/团队条件的核心行为**恰恰是扫描+选人+切目标**——只用 dry 断言等于没测。
--   这是本项目第 4 次栽在「只测解析不测调用点」上之后补的钩子。
function EVAL_TEST_COND_EVAL_LIVE(cd, rule) return condOne(cd, nil, false, rule) end

-- ★1.70.47 断言专用：走「选取目标:队伍/团队」的 auto 判据推断（等价于 condOne 的 target 分支）。
--   传 nil 规则 = 无队伍条件 → 退化「血量最低」；传规则 = 按规则里的队伍条件反推。
-- ★1.70.47 断言专用：直调**技能级执行**（选取目标/宠物指令/物品/动作条那条路）。
--   存在理由：技能行也能写成「选取目标:团队」，那条路径**不经过 condOne**，
--   是个独立调用点；只测条件路径会漏掉它（本项目「A 产出 / B 消费 两边都要断言」）。
function EVAL_TEST_WUSE(name) return wuse(name, "test") end

-- ★1.74.8 断言入口：**就绪判定**（不占动作条的特殊技能恒就绪 —— 客户端对它们不报冷却）
function EVAL_TEST_READY(name) local ok, why = wready(name) return ok and true or false, why end
-- ★1.74.8 断言入口：**图标解析**（验「取消自身buff:名」借的是那个光环自己的纹理）
function EVAL_TEST_ACTION_ICON(name) return wicon(name) end

function EVAL_TEST_TEAM_PICK_AUTO(rule, selId)
  teamPickArg.rule = rule
  TARGET_SEL_ARG_LAST = selId or "teamParty"
  local ok, unit = pcall(EVAL_TEAM_PICK, "auto")
  teamPickArg.rule, TARGET_SEL_ARG_LAST = nil, nil
  if not ok then return nil, tostring(unit) end
  return unit
end

function EVAL_PARSE_CONDS(str)
  local groups = {}
  for orPart in string.gmatch(str or "", "([^|]+)") do
    local g = {}
    for andPart in string.gmatch(orPart, "([^&]+)") do
      local cd = EVAL_PARSE_ONE(andPart)
      if cd then table.insert(g, cd) end
    end
    if table.getn(g) > 0 then table.insert(groups, g) end
  end
  return groups
end

-- 条件组 → 显示字符串（列表摘要 / 编辑回显）
-- 1.49.2 power 显示名动态化（UnitPowerType：法力/怒气/集中值/能量——旧版硬编码「怒气」，法师看着别扭）
local COND_NUMNAME = { power = (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), tHpPct = "目标血", hpPct = "自身血", swingLeft = "距攻击", shotLeft = "距射击", powerPct = "能量%", combatTime = "进战", castEl = "施法时间", castLeft = "施法剩余时间", tCastEl = "目标施法时间", tCastLeft = "目标施法剩余时间", combo = "连击", mwSiege = "围攻", mwEngaged = "交战" }
-- ★1.71.3 队伍/团员条件的「职业/队伍」过滤后缀（**导出侧**）：空集不写 → 老配置导出后**逐字不变**
local function teamFilterSuffix(cd)
  local out = ""
  local cs = cd.cs
  if type(cs) == "table" then
    local ns = {}
    for _, c in ipairs(CLASS_LIST) do if cs[c.id] then table.insert(ns, c.name) end end
    if table.getn(ns) > 0 then out = out .. "[职业:" .. table.concat(ns, "/") .. "]" end
  end
  local gs = cd.gs
  if type(gs) == "table" then
    local ns2 = {}
    for i = 1, 8 do if gs[i] then table.insert(ns2, tostring(i)) end end
    if table.getn(ns2) > 0 then out = out .. "[队伍:" .. table.concat(ns2, "/") .. "]" end
  end
  return out
end

function EVAL_COND_STR(cd, disp)
  local k = cd.k
  -- ★1.70.47 队伍/团队血蓝：前缀随扫描范围（cd.name）变化，保证「导出→导入」往返不掉范围
  local tscope = (cd.name == "团队") and "团队" or "队伍"
  if k == "teamHp" then return tscope .. "血" .. (cd.op or ">") .. tostring(cd.n) .. teamFilterSuffix(cd) end
  if k == "teamMana" then return tscope .. "蓝" .. (cd.op or ">") .. tostring(cd.n) .. teamFilterSuffix(cd) end
  -- ★1.71.3 候选者条件（选取器行专用）：独立拼写，与新类型一一对应
  if k == "candHp" then return "候选者血" .. (cd.op or ">") .. tostring(cd.n) .. teamFilterSuffix(cd) end
  if k == "candPower" then return "候选者能量" .. (cd.op or ">") .. tostring(cd.n) .. teamFilterSuffix(cd) end
  -- ★候选者光环型的导出行放在**stkSuffix 定义之后**（见下面 hasBuff 那一段）——Lua 词法作用域，
  --   放上面会绑到全局 nil（本轮实测报 attempt to call a nil value (global 'stkSuffix')）。
  -- ★★★1.73.27 资源类条件（power / powerPct）的显示名**每次现算**：德鲁伊变豹=能量、变熊=怒气、人形态=法力，
  --   建表时定死会在变形后显示错的名字（用户问的「能量对法系是不是魔法值」就是这个问题）。
  if k == "power" or k == "powerPct" then
    local lbl = (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量")
    if k == "powerPct" then lbl = lbl .. "%" end
    return lbl .. (cd.op or ">") .. tostring(cd.n)
  end
  if COND_NUMNAME[k] then return COND_NUMNAME[k] .. (cd.op or ">") .. tostring(cd.n) end
  if k == "combat" then return cd.v and "战斗中" or "非战斗" end
  if k == "form" then return "姿态" .. tostring(cd.n) end
  if k == "formNot" then return "非姿态" .. tostring(cd.n) end
  if k == "tracking" then
    -- ★1.75.6 追踪类型：导出/存档走**稳定 id**（追踪:beast，语言无关）；界面显示走本地化标签（追踪野兽）
    local id = tostring(cd.s or "any")
    return (cd.v == false and "未追踪:" or "追踪:") .. (disp and tostring(EVAL_TRACK_LABEL(id)) or id)
  end

  if k == "hasTarget" then return cd.v and "目标存在" or "无目标" end
  if k == "canAttack" then return cd.v and "可攻击" or "不可攻击" end
  if k == "canBleed" then return cd.v and "可流血" or "不可流血" end
  if k == "tDead" then return cd.v and "目标死亡" or "目标未死亡" end -- ★1.75.10 目标死亡
  if k == "isElite" then return cd.v and "精英" or "非精英" end
  if k == "isBoss" then return cd.v and "Boss" or "非Boss" end
  if k == "tInCombat" then return cd.v and "目标战斗中" or "目标非战斗" end
  if k == "tCasting" then return (cd.v == false and "目标未施法" or "目标施法中") .. ((cd.s and cd.s ~= "") and (":" .. cd.s) or "") end -- 1.40.0
  if k == "tFriendly" then return cd.v and "友善" or "非友善" end
  if k == "tHostile" then return cd.v and "敌对" or "非敌对" end
  if k == "tNeutral" then return cd.v and "中立" or "非中立" end
  if k == "alt" then return (cd.v and "" or "!") .. "Alt" end
  if k == "shift" then return (cd.v and "" or "!") .. "Shift" end
  if k == "ctrl" then return (cd.v and "" or "!") .. "Ctrl" end
  if k == "autoAttack" then return cd.v and "普攻" or "未普攻" end
  if k == "autoShot" then return cd.v and "自动射击" or "未自动射击" end -- 1.51.0
  if k == "wandShoot" then return cd.v and "魔杖射击" or "未魔杖射击" end
  -- 1.70.1：四类光环检查统一附层数门槛（>=N / <N），与 hasDebuff 同语法
  local function stkSuffix()
    if type(cd.n) == "number" and cd.n > 1 then return ((cd.v == false) and "<" or ">=") .. cd.n end
    return ""
  end
  -- ★★★1.74.6 「负面类型」后缀——**同一份格式化**（队伍debuff / 候选者debuff / 自身debuff / 目标debuff 共用）：
  --   · 导出/往返：disp=nil → 英文 token（(Magic) / (Magic/Poison)），单选与存量**逐字相同**；
  --   · 界面显示：disp=true → 本地化名（(魔法)），与 1.73.12「同一份格式化 + 一个显示开关」同一条纪律。
  --   ★必须声明在下面那些 if 之前（本项目 DECL ORDER 的教训：Lua local 从声明语句之后才可见）。
  local function dtSuffix()
    local dl = dispelLabel(cd.dt, disp)
    return (dl ~= "") and ("(" .. dl .. ")") or ""
  end
  -- ★1.70.45 剩余时间后缀（单位秒）：[<30s] / [>=60s] … 与层数后缀（名<N）不冲突，理由见 EVAL_PARSE_ONE
  local function secSuffix()
    if type(cd.secN) == "number" and type(cd.secOp) == "string" then
      return "[" .. cd.secOp .. cd.secN .. "s]"
    end
    return ""
  end
  -- ★1.71.3 候选者光环型（必须放在 stkSuffix/secSuffix 声明之后，否则引用到全局 nil）
  if k == "candBuff" then return ((cd.v == false) and "候选者缺buff:" or "候选者buff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() .. teamFilterSuffix(cd) end
  if k == "candDebuff" then return ((cd.v == false) and "候选者无debuff:" or "候选者debuff:") .. tostring(cd.s) .. dtSuffix() .. stkSuffix() .. secSuffix() .. teamFilterSuffix(cd) end -- ★1.74.6 补类型后缀（原来这里漏了 → 类型存不住）
  if k == "hasBuff" then return ((cd.v == false) and "无buff:" or "有buff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() end -- 1.54.0 合并（旧 k=noBuff 走下一行兼容）
  if k == "noBuff" then return "无buff:" .. tostring(cd.s) end
  if k == "tBuff" then return ((cd.v == false) and "无目标buff:" or "目标buff:") .. tostring(cd.s) .. stkSuffix() .. secSuffix() end -- 1.54.0
  if k == "pDebuff" then -- 1.54.0；★1.74.6 支持类型后缀与「名称留空 = 任意该类型」
    local nm = (cd.s ~= nil and cd.s ~= "") and tostring(cd.s) or ""
    return ((cd.v == false) and "无自身debuff:" or "自身debuff:") .. nm .. dtSuffix() .. stkSuffix() .. secSuffix()
  end
  if k == "hasDebuff" then -- ★1.74.6 同 pDebuff：类型后缀 + 名称留空「任意该类型」
    local nm2 = (cd.s ~= nil and cd.s ~= "") and tostring(cd.s) or ""
    return ((cd.v == false) and "无debuff:" or "有debuff:") .. nm2 .. dtSuffix() .. ((type(cd.n) == "number" and cd.n > 1) and ((cd.v == false and "<" or ">=") .. cd.n) or "") .. secSuffix()
  end
  if k == "noDebuff" then return "无debuff:" .. tostring(cd.s) .. ((type(cd.n) == "number" and cd.n > 1) and ("<" .. cd.n) or "") end
  -- ★1.70.47 队伍/团队 buff/debuff（用户要求）：前缀带扫描范围；类型以 (Magic) 后缀附上，解析侧双向容忍本地化名
  if k == "teamBuff" then return ((cd.v == false) and ("无" .. tscope .. "buff:") or ("有" .. tscope .. "buff:")) .. tostring(cd.s) .. stkSuffix() .. teamFilterSuffix(cd) end
  if k == "teamDebuff" then
    local nm = (cd.s ~= nil and cd.s ~= "") and tostring(cd.s) or ""
    -- ★1.73.2 多选：导出形态 (Magic) / (Magic/Poison)；单选与存量**逐字相同**
    -- ★1.73.12 disp=true 时走本地化名（**只影响界面显示**；导出/往返一律 false）
    return ((cd.v == false) and ("无" .. tscope .. "debuff:") or ("有" .. tscope .. "debuff:")) .. nm .. dtSuffix() .. teamFilterSuffix(cd)
  end
  if k == "ready" then return cd.inv and "未就绪" or "就绪" end
  if k == "usable" then return cd.inv and "不可用" or "可用" end
  if k == "notQueued" then return cd.inv and "已排队" or "未排队" end
  if k == "target" then
    -- ★1.75.10 带名称的选取器（指定名称 / 玩家的目标）统一走「选取目标:<显示名>:<名称>」——
    --   与解析侧（targetSelOf / parseOneRaw）同一口径；漏一种就是「导出能看、导入即丢条件」。
    if TARGET_SEL_NM[cd.s] then return "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s) .. ":" .. tostring(cd.nm or "?") end
    return "选取目标:" .. tostring(TARGET_SEL_NAME[cd.s] or cd.s)
  end
      -- ★★★1.71.2 修：技能名为 nil / 空串时**不再拼冒号**。旧写法输出「施法中:nil」「施法中:」，
      --   而解析侧只认「施法中」或「施法中:名」→ 两个都读不回 → **条件被静默丢弃**。
      --   ★与 tCasting（上方）对齐——它一直是对的，本次只是把自身侧补齐。
      if k == "casting" then return ((cd.v == false) and "未施法" or "施法中") .. ((cd.s and cd.s ~= "") and (":" .. cd.s) or "") end -- 1.38.0
if k == "inRange" then return (cd.v == false and "范围外:" or "范围内:") .. tostring(cd.s) end -- 1.37.0
if k == "immune" then return (cd.v == false and "未免疫:" or "免疫:") .. tostring(cd.s) end -- 1.36.1
  if k == "tClass" then
    local ns = {}
    for _, c in ipairs(CLASS_LIST) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.name) end end
    return "目标职业:" .. (table.getn(ns) > 0 and table.concat(ns, "/") or "未选")
  end
  if k == "tCreature" then -- 1.70.28 目标类型（多选或关系 + 是/否）
    local ns = {}
    for _, c in ipairs(CREATURE_TYPES) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.loc) end end
    local body = (table.getn(ns) > 0 and table.concat(ns, "/") or "未选")
    return ((cd.v == false) and "目标类型非:" or "目标类型:") .. body
  end
  if k == "tPlayer" then
    -- ★★★1.75.10 目标玩家（导出/回显）：是 = 目标玩家:X ；否 = 目标不是玩家:X。
    --   ★与解析侧**成对**（parseOneRaw 的 目标玩家/tPlayer 与 目标不是玩家/notplayer）——导出读不回 = 导入即丢条件。
    local nmP = tostring(cd.nm or "")
    if nmP == "" then nmP = "未填" end -- 空名在界面上/导出里如实写「未填」，不显示成空白
    return ((cd.v == false) and "目标不是玩家:" or "目标玩家:") .. nmP
  end
  return tostring(k)
end

-- ★1.71.2 断言专用：数值条件的「摘要显示名」（COND_NUMNAME）。
--   为什么要这个钩子：断言必须核实「摘要**真的**用了这个名字」，而不是在测试里**再抄一份**——
--   抄一份的话，生产代码改回裸 id 断言照样绿（本项目「测试里复刻逻辑」的老坑）。
function EVAL_TEST_COND_NUMNAME(k) return COND_NUMNAME[k] end

function EVAL_GROUP_STR(groups, disp)
  local parts = {}
  for _, g in ipairs(groups or {}) do
    local cs = {}
    for _, cd in ipairs(g) do table.insert(cs, EVAL_COND_STR(cd, disp)) end
    table.insert(parts, table.concat(cs, " & "))
  end
  return table.concat(parts, " | ")
end

-- 方案数据：缺省时给空「默认」方案（1.48.0 起；旧版生成一整套战士规则已删——起手走案例模版/编辑窗）
function EVAL_WAR_ENSURE_PROFILES(w)
  if not w then return end
  if not w.debuffTex then w.debuffTex = {} end -- 1.32.0 审计修复：光环名→纹理学习表从未创建，学习跨会话丢失（1.27.0 遗留）
  if not w.immune then w.immune = {} end -- 1.36.0 免疫学习表（技能@怪名，EVAL_IMMUNE_LEARN 写入）
  if not w.castTime then w.castTime = {} end -- 1.40.0 目标读条总时长学习表（技能名→秒）
  if type(w.profiles) ~= "table" or table.getn(w.profiles) == 0 then
    -- 1.48.0 去战士化：新装插件默认给空方案（旧版生成 战斗姿态/冲锋/压制… 一整套战士规则，其他职业全是垃圾条目）；
    -- 起手请用 配置窗→导入导出→[案例模版]（武器战模版首发）或编辑窗自行添加。
    w.profiles = { { name = "默认", skills = {} } }
  end
  if not w.activeProfile then w.activeProfile = 1 end
end



-- 一键入口：/run EVAL_GO()
-- 可选参数 profSel：0 或不传 = 当前激活方案；1-4 = 直触对应方案；字符串 = 按方案名。
-- 直触不改变激活方案。绑定多按键：宏1 /run EVAL_GO(1)（或 EVAL_GO1()）、宏2 /run EVAL_GO(2)……
function EVAL_GO(profSel)
  if profSel == 0 then profSel = nil end -- 0 = 当前激活方案
  -- 1.54.1 执行去抖：/run 宏在本客户端走 RunScript pending 队列（wiki 原文： queued, runs when flushed）——
  -- 连按时按键在队列里堆积，松手后陈旧调用还在逐个冲刷（用户实测：停手后目标狂切/技能滞后放）。
  -- 窗口内重复调用直接丢弃：公共CD 1.5s 下节流无感，但堆积的过期调用几乎全部失效 → 松手即停。
  -- 1.54.2 窗口可配：cfg.goDebounce 秒（默认 0.3，配置窗全局 Tab [一键宏] 组 [-][+] 步进 0.05）；
  --          + 执行追踪 EVAL_GO_TRACE（/eh go trace 看最近 12 次调用时间戳，定位偶发重复执行）。
  local goNow = GetTime()
  local goWin = tonumber(EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.goDebounce) or 0.3
  local goSkip = (goWin > 0) and (goNow - (EVAL_GO_LAST or 0) < goWin) or false
  -- ★1.75.12 选取目标取证：每次调用都报一次「接受 / 被去抖丢弃」+ 距上一发的毫秒
  --   —— 这是「调用到底在不在来」的直接证据（见文件上方「选取目标取证」段）：
  --     接受多+间隔≈冲刷节奏 ⇒ 队列余震；丢弃多 ⇒ 键/宏在连发。
  local goGapMs = (EVAL_GO_LAST and EVAL_GO_LAST > 0) and math.floor((goNow - EVAL_GO_LAST) * 1000 + 0.5) or nil
  tselNoteGo(goSkip, goGapMs)
  EVAL_GO_TRACE = EVAL_GO_TRACE or {}
  table.insert(EVAL_GO_TRACE, 1, { t = goNow, skip = goSkip })
  while table.getn(EVAL_GO_TRACE) > 12 do table.remove(EVAL_GO_TRACE) end
  if goSkip then
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug then EVAL_SAY("|cffff9040war:|r 去抖：忽略过快调用（队列冲刷）") end
    return
  end
  EVAL_GO_LAST = goNow
  EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
  -- 配置阈值（/eh cfg 或小地图 EH 图标可调；缺省值与原宏一致）
  local w = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war) or {} -- 1.41.1 热修：拆分后 Engine 无 cfg local（EVAL_GO 裸引用崩全局）
  if w.enabled == false then
    if GetTime() - EVAL_WLASTHINT >= 5 then
      EVAL_WLASTHINT = GetTime()
      EVAL_SAY("一键宏已禁用（/eh cfg 或小地图 EH 图标里开启）")
    end
    return
  end
  if not wscanned then EVAL_GO_RESCAN(true, "auto") end

  -- Shift+按宏 = 切换下一个方案（不施法）；也可点战斗信息UI的方案按钮或 /eh go next
  if IsShiftKeyDown and IsShiftKeyDown() then
    EVAL_WAR_ENSURE_PROFILES(w)
    if w.profiles and table.getn(w.profiles) > 1 then
      w.activeProfile = (w.activeProfile or 1) % table.getn(w.profiles) + 1
      EVAL_SAY("切换到方案: " .. tostring(w.profiles[w.activeProfile].name))
    else
      EVAL_SAY("只有一个方案，无需切换（配置窗口 一键宏设置页 [+] 新建）")
    end
    return
  end

  -- 刷新角色状态表（Cat 思路：宏只读缓存变量，不重复调 API）
  EVAL_HELP_UPDATE_STATE()
  -- ★1.70.47「这一次按键选中的队友」必须在**每次按键开头清空**：
  --   否则上一轮选的人会被这一轮当成「本次命中的人」，技能就打在旧目标身上了。
  --   它由 队友/团员条件 或 选取目标:队伍成员/团队成员 在**本轮**写入。
  st.allyUnit, st.teamCur = nil, nil
  local rage     = st.power
  local inCombat = st.inCombat

  -- 1)（1.49.0 移除硬编码「无有效目标 → TargetNearestEnemy」前置：它在规则评估之前抢跑选敌，
  --    与「选取目标:最近友方」类规则方向相反、互相抢目标（用户实测日志先选敌再选友）。
  --    选目标行为全部交给规则：需要自动选敌写规则 选取目标:最近敌人 | 无目标（或非战斗 & 无目标 等组合）。
  --    1.21.7 起本函数已不再因无目标硬返回——攻击类技能用「可攻击/可用」条件兜底。）

  local thscale  = st.tHpPct / 100
  local ttype    = st.tCreatureType
  local canBleed = st.canBleed -- Cat 的 MPTargetBleed（类型排除+黑白名单，见状态模块）

  -- 2)（1.22.0 移除硬编码「非战斗切姿态/冲锋」前置：它无视方案内容强制出手，是旧战士宏残留。
  --    需要该行为请在方案里加规则：战斗姿态 | 非战斗 & 非姿态1 & 可攻击；冲锋 | 非战斗 & 姿态1 & 可攻击 & 就绪）

  -- 3) 自动普攻（AttackTarget 是切换语义，必须用 IsCurrentAction 守卫，连按安全）
  -- 1.47.0 解耦：st.autoAttack 状态采集【不受接管开关影响】（否则开关关掉时 普攻/未普攻 条件恒读 false，
  -- 规则里放「攻击」不带 未普攻 条件会每按一次开/关翻转）；开关只控制「自动开启」这个动作。
  -- 1.50.0 自动攻击（改名自 自动普攻接管）：优先级 自动射击(猎人) > 射击(魔杖) > 攻击(近战普攻)；
  -- 上条且【可用】才入选（IsUsableAction——无远程武器/无魔杖自动降档）；近战「攻击」为无条件兜底。
  local atkSlot, atkUse, atkName = nil, nil, nil
  local function pickAtk(name, useFn, needUsable)
    local s = wslots[name]
    if not s then return false end
    if needUsable then
      if type(IsUsableAction) == "function" then
        local oku, usable, noMana = pcall(IsUsableAction, s.slot)
        if not (oku and (usable or not noMana)) then return false end -- 1.64.0 只信资源信号（缓存 false 不误降档）
      end
      -- 1.52.0 距离检测：IsUsableAction 不含射程判定（自动射击 8-35 码贴脸也"可用"但放不出）——
      -- IsActionInRange 明确返回 0=超程时降档；nil=无目标/无法判定时放行（交给客户端自己拒）
      if type(IsActionInRange) == "function" then
        local okr, inRg = pcall(IsActionInRange, s.slot)
        if okr and inRg == 0 then return false end
      end
    end
    atkSlot, atkUse, atkName = s.slot, useFn, name
    return true
  end
  if not pickAtk("自动射击", function() UseAction(wslots["自动射击"].slot) end, true)
     and not pickAtk("射击", function() UseAction(wslots["射击"].slot) end, true) then
    pickAtk("攻击", function() AttackTarget() end) -- 近战兜底（不查可用，自动攻击恒可开）
  end
  st.autoAttack = false
  -- ★★1.75.12【修复·第 1 步】「补自动攻击」从规则评估之前**挪到之后**（真正按下去在下面 `tselInGo` 那一段）：
  --   · `st.autoAttack` 仍然在这里采（规则里的「自动攻击」条件读它；采集与接管开关解耦 = 1.47.0 的纪律）；
  --   · 这里只记下「当前没在自动攻击」这个**事实**（atkOff），不再当场按。
  --   ★为什么挪（用户 1.75.12 报障 + 真机取证 `/eh go tsel log`）：旧位置在**规则之前**（"先调用"），
  --     而本客户端的「攻击」= `AttackTarget()` **会顺带切目标**（官方文档只写 Toggles，实测会切）——
  --     于是每一发成了「先被它把目标切走 → 再被 选取目标:最近敌人 切回来」，
  --     用户看到的就是目标在**尸体与活怪之间无限来回跳**。
  --   ★★别再挪回规则之前：1.62.0 曾挪到之后、1.65.0 又撤销，**那次是误诊**（真凶是 1.64.0 修的 pcall 多返回截断）；
  --     1.75.12 是有真机证据的（组 251 + `/eh go tsel log` 里 `[攻击]`/`[选取]` 的先后与目标快照）。
  local atkOff = false -- 「当前没在自动攻击」= 本发需要补
  if atkSlot and type(IsCurrentAction) == "function" then
    local okc, cur = pcall(IsCurrentAction, atkSlot)
    if okc and cur then st.autoAttack = true else atkOff = (okc == true) end
  end

  -- 4~10) 输出循环 = 指定方案（profSel 参数）或当前激活方案的技能规则表
  EVAL_WAR_ENSURE_PROFILES(w)
  local prof = nil
  if profSel ~= nil then
    if type(profSel) == "number" then
      prof = w.profiles[profSel]
    elseif type(profSel) == "string" then
      for _, p in ipairs(w.profiles) do
        if p.name == profSel then prof = p break end
      end
    end
    if not prof then
      if GetTime() - EVAL_WLASTHINT >= 2 then
        EVAL_WLASTHINT = GetTime()
        local names = {}
        for _, p in ipairs(w.profiles) do table.insert(names, "[" .. tostring(p.name) .. "]") end
        EVAL_SAY("方案不存在: 「" .. tostring(profSel) .. "」现有方案: " .. table.concat(names, " ") .. "（注意全半角引号/名称一致；/eh go list 查看）")
      end
      return
    end
  else
    prof = w.profiles[w.activeProfile or 1]
  end
  -- ★1.75.12 取证用「按键轮号」：这一轮里的选取目标调用都会带上同一个 `p<N>`（见 tselInvoke）
  tselInGo = tselPass
  local acted = prof and EVAL_RULE_RUN(prof.skills)
  -- ★★★1.75.12【修复·第 2 步】补自动攻击挪到**规则评估之后**，且**只在目标真的能打时**才按（理由见上一步的长注释）：
  --   ① 目标是尸体 / 无目标 / 不可攻击（友方等）⇒ **一次都不按** —— 这正是用户报障的那个口子：
  --      旧版只看「攻击格没在自动攻击」+ 2 秒节流，目标是尸体也照按，而本客户端的 `AttackTarget()` 会顺带切目标；
  --   ② 判定用**实时 API**（UnitExists / UnitIsDeadOrGhost / UnitCanAttack），**不用 `st.canAttack`**——
  --      规则可能刚切过目标，`st` 是这一轮开头采的、已经过期（本项目「读真值，不读缓存」纪律）；实时 API 缺失才退回它；
  --   ③ 放在 `if acted then return end` **之前** ⇒ 规则出手了也照样补（"保持自动攻击"的意图不变）；
  --   ④ 按之前/之后各拍一张目标快照写进取证环（`[攻击] … 前 ⇒ 后`）——本客户端的 AttackTarget 会不会切目标，
  --      下一轮真机测试一眼可判（不必再靠"关掉开关再试"这种猜法）。
  local function atkTargetAttackable()
    if type(UnitExists) ~= "function" then return (st.canAttack == true) end
    local okE, has = pcall(UnitExists, "target")
    if not (okE and has) then return false end
    if type(UnitIsDeadOrGhost) == "function" then
      local okD, dead = pcall(UnitIsDeadOrGhost, "target")
      if okD and dead then return false end
    end
    if type(UnitCanAttack) == "function" then
      local okC, can = pcall(UnitCanAttack, "player", "target")
      if okC and not can then return false end
    end
    return true
  end
  if atkOff and w.attack ~= false and GetTime() - wLastAttackTry >= 2 then
    if not atkTargetAttackable() then
      -- 如实留证：这是**故意不按**（尸体/无目标/不可攻击），不是"忘了" —— 否则下次排查还得靠猜
      wlog("跳过补自动攻击（" .. tostring(atkName) .. "）：目标是尸体/不存在/不可攻击")
    else
      wLastAttackTry = GetTime()
      local aBefore = tselSnap()
      atkUse()
      local aAfter = tselSnap()
      local aline = string.format("[攻击] %s() p%s %s ⇒ %s%s", tostring(atkName),
        (tselInGo ~= nil) and tostring(tselPass) or "-", aBefore, aAfter,
        (aBefore == aAfter) and " 没变" or " **变了**")
      tselPush(aline)
      if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, aline) end
      if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.wdebug and type(EVAL_SAY) == "function" then
        pcall(EVAL_SAY, "|cffffd080" .. aline .. "|r")
      end
    end
  end
  tselInGo = nil
  if acted then return end

  -- 本次按键无动作：打一条状态行，方便对照调阈值
  -- ★1.71.2（第十八轮）小数值保留 1 位：目标血% 原为 %.0f —— 0.4% 会显示成「0%」，
  --   而「目标残血」恰恰是调阈值时最需要看的那一档（同一天起，剩余秒数也统一到 1 位）。
  wlog(string.format("无动作 | %s%d 目标血%.1f%% %s%s%s%s", -- 1.49.2 怒气/战斗姿态硬编码→动态
    (EVAL_POWERLABEL and EVAL_POWERLABEL() or "能量"), rage, thscale * 100,
    inCombat and "战斗中" or "非战斗",
    (st.form and (" " .. st.form) or ""),
    ttype and (" " .. ttype) or "",
    st.isBoss and " Boss" or (st.isElite and " 精英" or "")))
end

-- 技能选择清单（1.48.0 起纯扫描）：动作条扫到的全部技能（去重排序）+ 宠物指令段，编辑窗下拉用。
-- 旧版 WAR_SKILLS 战士白名单置顶已删——法师不再看到 冲锋/压制 这些战士技能。
function EVAL_GO_SKILL_CHOICES()
  local list, seen = {}, {}
  if wscanned and wslots then
    local extra = {}
    for n in pairs(wslots) do
      if not seen[n] then table.insert(extra, n) end
    end
    table.sort(extra)
    for _, n in ipairs(extra) do table.insert(list, n) end
  end
  for _, p in ipairs(PET_CMD) do table.insert(list, "宠物:" .. p.name) end -- 1.30.0 特殊技能段
  return list
end

-- 技能二级分类（1.32.0）：编辑窗技能名下拉先选类再选项。
--   ★1.71.3 五个类别各配一个图标（用户要求「角色行为下拉添加图标美化」）。
--     ★图标**自包含**：这些 .tga 已从 UnrealQuest 拷进本插件 media\icons\（对方改图/改路径都不影响我们）。
--     ★单一来源：类别元数据（标签 + 取项函数 + 图标）全在这一张表里，UI 只负责画（不在 UI 层另写一份）。
local CAT_ICON_ROOT = "Interface\\AddOns\\EvalHelp\\media\\icons\\"
-- 五类：角色行为(攻击) / 角色技能(白名单+动作条扫描) / 宠物行为 / 目标选取 / 物品使用(背包实时扫描+自定义名)
-- items 为函数：点开时才取数（背包/动作条是动态的）
function EVAL_GO_SKILL_CATEGORIES()
  local cats = {}
  table.insert(cats, { label = L("SK_CAT_1"), icon = CAT_ICON_ROOT .. "trainer", items = function() -- 1.43.0 追加姿态切换（姿态栏实时枚举，不占动作条）
    -- 1.47.0 扩充：自动射击（猎人）/射击（法系魔杖）走动作条通道同「攻击」；取消施法=SpellStopCasting 特殊行为
    -- ★1.71.3 追加「跟随」（不占动作条的特殊行为）：直接「跟随」= 跟当前目标；
    --   `L("SE_PICK_FOLLOW")`（「跟随:指定名字…」）点了会弹名字输入框 → 存成 `跟随:名字`。
    -- ★1.74.8 追加「取消自身buff」（用户要求：「方案->技能->取消自身buff」）：
    --   裸写法 = 取消**全部**可取消的自身增益；带名字写法只取消那一个（点了弹名字输入框）。
    local l = { "攻击", "自动射击", "射击", "取消施法", "停止攻击", "跟随", L("SE_PICK_FOLLOW"),
                "取消自身buff", L("SE_PICK_CANCELBUFF") }
    if type(GetNumShapeshiftForms) == "function" then
      local okn, n = pcall(GetNumShapeshiftForms)
      if okn and n and n > 0 then
        for i = 1, n do
          local oki, _ic, nm = pcall(GetShapeshiftFormInfo, i)
          if oki and nm then table.insert(l, "姿态:" .. nm) end
        end
      end
    end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_2"), icon = CAT_ICON_ROOT .. "trainers-icon", items = function() -- 1.48.0 纯动作条扫描（白名单已删）
    local list, seen = {}, {}
    if wscanned and wslots then
      local extra = {}
      for n in pairs(wslots) do
        if not seen[n] and n ~= "攻击" and n ~= "自动射击" and n ~= "射击" and n ~= "取消施法" and n ~= "停止攻击" then table.insert(extra, n) end
      end
      table.sort(extra)
      for _, n in ipairs(extra) do table.insert(list, n) end
    end
    return list
  end })
  table.insert(cats, { label = L("SK_CAT_3"), icon = CAT_ICON_ROOT .. "stablemaster", items = function()
    local l = {}
    for _, p in ipairs(PET_CMD) do table.insert(l, "宠物:" .. p.name) end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_4"), icon = CAT_ICON_ROOT .. "database", items = function()
    local l = {}
    for _, t in ipairs(TARGET_SEL) do
      -- ★1.75.10 两个「需要名字」的选取器必须给**不同**的菜单文案：选完要按文案串回查 id
      --   （`targetSelOf` 剥掉尾部省略号再查 `TARGET_SEL_ID`）——同串 = 两行分不清，选了也分不出是哪种。
      if t.id == "playerTarget" then table.insert(l, L("SE_PICK_TGT_PLAYER"))
      elseif t.needsName then table.insert(l, L("SE_PICK_TGT"))
      else table.insert(l, "选取目标:" .. t.name) end
    end
    return l
  end })
  table.insert(cats, { label = L("SK_CAT_5"), icon = CAT_ICON_ROOT .. "chests", items = function()
    local l, seen = {}, {}
    if type(GetContainerNumSlots) == "function" then
      for bag = 0, 4 do
        local okn, slots = pcall(GetContainerNumSlots, bag)
        if okn and slots and slots > 0 then
          for slot = 1, slots do
            local okl, link = pcall(GetContainerItemLink, bag, slot)
            local nm = okl and link and string.match(link, "%[(.-)%]")
            if nm and not seen[nm] then
              seen[nm] = true
              local oki, tex, cnt = pcall(GetContainerItemInfo, bag, slot)
              table.insert(l, "物品:" .. nm .. ((oki and cnt and cnt > 1) and ("×" .. cnt) or ""))
            end
          end
        end
      end
      table.sort(l)
      while table.getn(l) > 46 do table.remove(l) end -- DD 行池上限 48（首行留给自定义）
    end
    table.insert(l, 1, L("SE_PICK_ITEM"))
    return l
  end })
  return cats
end

-- 方案直触便捷函数：宏正文 /run EVAL_GO2() 即可把方案2 绑到独立按键
function EVAL_GO1() EVAL_GO(1) end
function EVAL_GO2() EVAL_GO(2) end
function EVAL_GO3() EVAL_GO(3) end
function EVAL_GO4() EVAL_GO(4) end

-- 1.42.0 方案上限 12：EVAL_GO5~GO12 批量生成（5.1 循环闭包每轮新 local j 捕获）
for i = 5, 12 do local j = i _G["EVAL_GO" .. j] = function() EVAL_GO(j) end end
-- /eh war 的状态总览
function EVAL_GO_STATUS()
  if not wscanned then EVAL_GO_RESCAN(true, "auto") end
  EVAL_SAY("— 一键宏状态 —")
  -- 1.45.0 以激活方案技能为准（旧版固定战士白名单已废弃）
  local w2 = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
  local p = w2 and w2.profiles and w2.profiles[w2.activeProfile or 1]
  if p and p.skills and table.getn(p.skills) > 0 then
    EVAL_SAY("激活方案「" .. tostring(p.name) .. "」：")
    for _, r in ipairs(p.skills) do
      local n = r.skill
      if petCmdOf(n) or targetSelOf(n) or stanceOf(n) or cancelCastOf(n) or stopAllOf(n) or followOf(n) then -- ★1.71.3 跟随也算「不占动作条的特殊技能」
        EVAL_SAY(n .. ": |cff80ff80特殊技能（不占动作条）|r")
      elseif itemOf(n) then
        local bag = wFindBagItem(itemOf(n))
        EVAL_SAY(n .. ": " .. (bag and "|cff00ff00背包已找到|r" or "|cffff0000背包未找到|r"))
      else
        local s = wslots[n]
        if s then
          local ready, why = wready(n)
          EVAL_SAY(string.format("%s: 格子%d %s", n, s.slot, ready and "|cff00ff00就绪|r" or ("|cffff9040" .. tostring(why) .. "|r")))
        else
          EVAL_SAY(n .. ": |cffff0000未上动作条|r")
        end
      end
    end
  else
    EVAL_SAY("（激活方案暂无技能）")
  end
  EVAL_SAY("当前: " .. formatStats(collectStats()))
end

-- ===== 跨模块导出（EvalHelp.lua 的 UI 层用） =====
EVAL_WSLOTS = wslots
EVAL_WICON = wicon
EVAL_GROUPS_OK = groupsOK
EVAL_AURA_TEX = auraTexOf
-- ★1.73.2 断言入口：可驱散类型的匹配判定（含**多选集合**）——测试直接问生产实现，不另写一份
function EVAL_TEST_DISPEL_MATCH(actual, want) return dispelMatch(actual, want) end
EVAL_PET_OF = petCmdOf
EVAL_TGT_OF = targetSelOf
EVAL_TSEL_TEAMSEL = TARGET_SEL_TEAMSEL -- ★1.71.3 条件类型下拉要按「这一行是不是成员选取器」过滤
EVAL_ITEM_OF = itemOf
EVAL_STANCE_OF = stanceOf
EVAL_CANCELCAST_OF = cancelCastOf
EVAL_STOPALL_OF = stopAllOf -- 1.71.3 停止攻击特殊行为（UI 层判定「不占动作条」用）
EVAL_FOLLOW_OF = followOf -- ★1.71.3 跟随特殊行为（UI 层同样按「不占动作条」处理）
-- ★★★1.74.9 取消自身buff「多选 buff」三个纯函数（UI 只做展示，判据钉这里的逻辑）：
--   ① 候选列表（实时自身 buff + 已记录，去重排序）；
--   ② 集合 → 技能文本（逗号分隔，供 seUI.ed.skill）；
--   ③ 技能文本 → 集合（回读，供多选面板预选）。
--   ★分隔符用逗号：光环名里不会出现，比空格/顿号安全；多字节名字按字节切不受影响。

-- ① 候选列表：实时自身 buff（EVAL_PLAYER_BUFF_LIST）+ 学习表里已记录的名字（此刻不在也能选）。
function EVAL_CANCELBUFF_CANDIDATES()
  local seen, out = {}, {}
  local list = EVAL_PLAYER_BUFF_LIST() -- 实时（读自家隔离 tooltip；玩家正看提示时如实返回空）
  for _, d in ipairs(list) do
    if type(d.name) == "string" and d.name ~= "" and not seen[d.name] then
      seen[d.name] = true table.insert(out, d.name)
    end
  end
  local lt = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex) or EVAL_DEBUFF_TEX_LEARN
  if type(lt) == "table" then
    for nm in pairs(lt) do
      if type(nm) == "string" and nm ~= "" and not seen[nm] then
        seen[nm] = true table.insert(out, nm)
      end
    end
  end
  table.sort(out)
  return out
end

-- ② 集合（键=名字 → true）→ 技能文本："取消自身buff"（空）/ "取消自身buff:名1,名2"
function EVAL_CANCELBUFF_TO_TEXT(set)
  if type(set) ~= "table" then return "取消自身buff" end
  local names = {}
  for nm in pairs(set) do
    if type(nm) == "string" and nm ~= "" then table.insert(names, nm) end
  end
  if table.getn(names) == 0 then return "取消自身buff" end -- 空集 = 不限 = 取消全部
  table.sort(names)
  return "取消自身buff:" .. table.concat(names, ",")
end

-- ③ 技能文本 → 集合（回读，供多选面板预选）；"取消自身buff"（无后缀）→ 空集（= 取消全部）
function EVAL_CANCELBUFF_FROM_TEXT(skill)
  local set = {}
  local nm = string.match(colonNorm(skill or ""), "^取消自身buff:(.*)$")
  if not nm then return set end -- 无后缀 = 不限 = 空集
  for part in string.gmatch(nm, "([^,]+)") do
    local one = string.match(part, "^%s*(.-)%s*$")
    if one ~= "" then set[one] = true end
  end
  return set
end

EVAL_CANCELBUFF_OF = cancelBuffOf -- ★1.74.8 取消自身buff 特殊行为（UI 层同样按「不占动作条」处理）
EVAL_NO_SLOT_OK = skillNoSlotOk -- ★1.72.4 「不占动作条也合法」的单一判据（引擎与战斗信息UI 共用，不许再各写一份名单）
EVAL_FOLLOW_ICON = ACT_FOLLOW_ICON -- ★1.71.3 跟随的图标（图标库「本插件在用」要列它；单一来源，不另抄路径）
-- 1.71.3 移动脉冲已删（实测无效）→ 对应的两个测试观测口一并删除（不留死状态）
EVAL_TARGET_SEL = TARGET_SEL
EVAL_TSEL_NAME = TARGET_SEL_NAME
-- ★1.75.10 追加两个读值口（用户问「选取目标:目标的目标 可行性」时要能**离线断言**这条选取走的是哪个函数）：
--   `EVAL_TSEL_ID[名字或 id] = id`（内置双向映射）· `EVAL_TSEL_FN[id] = 客户端函数名`。
--   ★判据价值：`targetTarget` 必须走 **TargetUnit**（解析不到=什么都不做），**绝不许**被改成 AssistUnit
--     （后者对解析不到的 UnitID 会**清掉当前目标** —— 官方 Targetting 页明文）。
EVAL_TSEL_ID = TARGET_SEL_ID
EVAL_TSEL_FN = TARGET_SEL_FN
-- ★1.75.10 `EVAL_TSEL_NM[id] = true` = 「这一条选取需要名字参数」（指定名称 / 玩家的目标）——
--   宿主（EvalHelp.lua）编辑器与技能级下拉读它，别再各写一份 `cd.s == "byName"`（漏一处就是静默）。
EVAL_TSEL_NM = TARGET_SEL_NM
EVAL_TSEL_NEEDTGT = TARGET_SEL_NEEDTGT -- 调用后必须有目标（当前只有 playerTarget；如实失败判据）
EVAL_CLASS_LIST = CLASS_LIST
EVAL_COND_TRIM = condTrim
EVAL_COLON_NORM = colonNorm -- ★1.71.3 全角冒号归一（EvalHelp 解析导入文本时同样要用）
EVAL_P_HASBUFF = wPlayerHasBuff
EVAL_T_HASDEBUFF = wTargetHasDebuff
EVAL_IS_SCANNED = function() return wscanned end

-- ===== 近战围攻探针（1.75.11）：战斗中「有几只怪在近战打我」+「周围有几只敌人」的可行性取证 =====
-- ★用户需求（原话）：「排查能否战斗中多少个怪同时近战攻击你.然后统计出周围怪数量的条件机制?先排查出命令我测试」
-- ★官方事实（本机 doc/api_*.html 全表 1370 条 + tmp\wiki\functions.txt 逐条核过，不是印象）：
--   · **没有任何「附近敌人枚举」API**（没有 GetNumEnemyUnits / UnitInRange 之类）⇒ 真值只能靠
--     TargetNearestEnemy 循环选取边切边数（既有实现 = EVAL_NEARBY_ENEMY_NAMES，1.29.0 起就在用）；
--     ★★但用户 1.75.11 定了口径：「**非战斗也不要切目标**」⇒ 自动路径**一个目标都不切**
--       （状态UI 上的「交战数」走纯消息口径，见文件末尾的临时测试挂接）；
--       TargetNearestEnemy 那条降级成手工命令：只有显式敲 `/eh go melee 周围 切目标` 才切一次。
--   · 有 UnitIsEnemy / UnitIsFriend / UnitAffectingCombat / UnitIsVisible / CheckInteractDistance 可用。
--   · **事件名在官方索引里查不到**（functions.txt 只有函数，没有 Events 页）⇒「哪条聊天事件承载『X 击中你』」
--     **不许猜**（CLAUDE.md 铁律 5 第 ④ 条）。本探针走两条正规取证路：
--       ① GetChatWindowMessages(1) —— 本客户端返回**逗号分隔的组名串**（Toolbox.lua 1.73.12 实测形态）
--          ⇒ 把含 COMBAT 的组名全列出来（这是**客户端自己认的**组名，不是我猜的）；
--       ② 挂一组候选事件并**统计每个事件实际触发了几次** ⇒ 谁真的跟着走一目了然（0 次 = 本客户端没有这个事件名）。
--   · 攻击者名字**从消息正文认**（不是 arg2）：1.12 的 CHAT_MSG_COMBAT_* 里 arg2 多半是空串，
--     而本客户端的参数布局只能实测 ⇒ 探针把 arg1/arg2/arg3 **原样**记下来，认不出也留证（绝不静默丢）。
-- ★读数专属落盘 cfg.meleeProbe（有界 40 行，已进 Core 调试残渣键清单）：
--   say 只进聊天框、**不落日志环**（1.75.9 教训），且存档只在 /reload/退出时写盘 ⇒ 不自己存一份我这边读不到。
-- ★「关掉零动作」：不跑「开始」就**一个事件都不挂、一个字节都不读**（默认零动作）。

local MW = {
  on = false, frame = nil, win = 4, t0 = nil, n = 0, -- win = 报告/默认统计窗口（★1.75.11 6 → 4，与 MW_UIWIN 同步）
  counts = {},  -- 事件名 -> 触发次数（★取证核心读数：0 次 = 本客户端没有这个事件名）
  atk = {},     -- 攻击者名 -> { last = 最近一次命中时间, n = 次数, first = 首次 }
  hits = {},    -- ★1.75.11 被围攻估算：最近若干次「怪近战挥击」{ t = 时刻, nm = 怪名 }（有界 MW_HITS_MAX）
  ivl = {},     -- ★1.75.11 自学习的「怪名 -> 攻速档位」（只在**可证单只**的窗口里学；跨战斗保留=知识）
  ivlN = {},    -- ★每个名字**档位更新过几次**（真的变了才 +1；首次学到算 1 次）
  ivlSeen = {}, -- ★每个名字被**确认单只**过几次（监测证据：一直在盯，只是档位没变而已）
  ivlLog = {},  -- ★档位**变更日志**（有界 12 条：旧档→新档 + 实测中位间隔），报告里打出来自证「及时更新」
  raw = {},     -- 最近 8 条原始样本（事件名 + arg1/2/3 原样）
  miss = {},    -- 最近 6 条「认不出攻击者」的原文（★不许静默丢，认不出也要留证）
  seen = {},    -- 交战过的怪名（它打我 / 我打它）-> { last, n, dir }：★「周围怪数」的消息口径，零切目标
  -- ★全事件抓取（RegisterAllEvents 模式）：事件名官方**没有索引** ⇒ 只能把真机来过的事件读出来
  all = false, allCounts = {}, allSample = {}, seq = {},
  reg = {}, bad = {},
}
local MW_OUT_MAX = 120 -- ★1.75.11 40 → 120：真机实测一次完整报告就 ~40 行，把上一轮读数全冲掉了（战斗窗口/全事件读数就是这么丢的）
-- ★★★1.75.11 统计窗口 = **4s**（用户口径：「根据攻速统计怪个数的统计时间调整到4s 内,离开战斗重置」）
local MW_UIWIN = 4   -- 状态UI/战斗UI「围攻」窗口（秒）
local MW_UIENG = 10  -- 状态UI「交战」窗口（秒；消息口径，零切目标）
-- ★★★1.75.11 被围攻估算 —— 全部建立在**用户给的领域约束**上（这轮自学习/灵敏度的根据，别改回去）：
--   ① 怪的攻速只可能是 **1.5 / 2.0 / 2.5** 三档 ⇒ 学到的间隔一律**吸附到档位**（不再存 1.8 这种中间值）；
--   ② 单只怪的真实间隔 ≥1.5，而两只怪错相时的最小间隔 ≤ 2.5/2 = 1.25
--      ⇒ ★**观测到的相邻两条间隔 ≥1.4 ⇒ 必然是同一只怪**（可证，不是估算）；反之出现 ≤1.3 的间隔 ⇒ 至少 2 只。
--   ⇒ 「这是几只」在单只那一档从**估算**升级成**定理**：独苗永远是 1 只，绝不四舍五入成 2 只；
--     多只那一档才用「窗口内条数 ÷ 档位间隔」+ 跨度反推（两条估计取大 ⇒ 更灵敏）。
--   怪的一次挥击（命中/未命中/被闪避招架格挡）**恰好一条消息** ⇒ 到达率 ∝ 攻击者数 ÷ 档位间隔。
--   ★必须**窗口化**（不能用 atk[nm].n 那个「进战以来累计」）：先单挑 A 60s、B/C 最后 4s 才来，
--     累计次数 ÷ 累计时长照样算出 1 只 —— 那是「平均」不是「现在有几只」。
--   ★与名字无关 ⇒ 认不出名字的挥击也照计（「名字认不出」和「这次挥击没发生」是两件事）。
local MW_ESTI = 2.0    -- 默认档（还没学到该怪名字的档位时用它）
local MW_ESTCAP = 8    -- 估算上限（★有界：技能连击/异常不许把数顶飞 —— 这个数会驱逐一键宏，宁保守）
local MW_HITS_MAX = 64 -- 挥击时间环上限（★有界数组：绝不无界增长）
local MW_TIERS = { 1.5, 2.0, 2.5 } -- ★用户给的攻速档位（唯一合法取值；吸附/反推都只在这三档里挑）
local MW_GAP_SINGLE = 1.4 -- 相邻间隔 ≥ 它 ⇒ **可证**这只怪是独苗（单只 ≥1.5；两只 ≤1.25）
local MW_GAP_MULTI = 1.3  -- 相邻间隔 ≤ 它 ⇒ 至少 2 只（同上，两个数不许互换）
local MW_TIER_TOL = 0.25  -- 吸附到档位的容差（离三档都超过它 ⇒ 如实**不学**，不硬套）
local MW_FIT_MIN_N = 4    -- 「没学过档位」时按到达节奏反推档位所需的最小样本数
local MW_FIT_MIN_SPAN = 3.0 -- 反推档位所需的最小跨度（秒）：跨度太短时相位聚集会把档位判歪
local MW_FIT_TOL = 0.25   -- 反推档位的拟合容差
local MW_IVLLOG_MAX = 12  -- 档位变更日志条数上限（★有界）
-- 候选事件（1.12 家族的经典命名；★真伪由「触发次数」+ 组名串定案，这里只是候选，不当作事实）
local MW_EVENTS = {
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
  "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS",
  "CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES",
  "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
  "CHAT_MSG_COMBAT_SELF_HITS",              -- 对照：1.55.0 挥击计时已在用的那条（本插件确定在用）
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", -- 对照：法术/远程打你（用来把「近战」与「法术」分开）
  -- ★★★1.75.11 真机实测追加（LIHAIBOAS2 一轮战斗的读数，见 cfg.meleeProbe）：
  --   ① 我方持续伤害（撕裂/毒等）走**这条**，不是 SELF_HITS：
  --      「你的撕裂使大峭壁野猪受到了5点物理伤害。」⇒ CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE
  "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", -- 实测：我方 DoT 打怪（归 out = 交战数）
  --   ② 击杀：CHAT_MSG_COMBAT_HOSTILE_DEATH（实测两种文案「你杀死了X！」/「X死亡了。」）
  --      ⇒ 用来把死掉的怪**踢出围攻桶**（尸体不该继续算「还在打我」）
  "CHAT_MSG_COMBAT_HOSTILE_DEATH",          -- 实测：击杀（归 kill）
  -- ★★★1.75.11 真机 `全事件` 读数（LIHAIBOAS2，398s）逼出来的**反查项**：那 398s 里只来过
  --   CHAT_MSG_ADDON / CURSOR_UPDATE / CHAT_MSG_CHANNEL_LEAVE / GUILD_ROSTER_UPDATE / UPDATE_MOUSEOVER_UNIT
  --   —— **没有 PLAYER_REGEN_* / PLAYER_TARGET_CHANGED / 任何 UNIT_***。
  --   若属实 ⇒ 主插件的「进出战斗输出」（PLAYER_REGEN_*）与「切目标刷新状态」（PLAYER_TARGET_CHANGED）
  --   在本客户端**静默失效**（状态UI 仍对，是因为 st.inCombat 走的是轮询 UnitAffectingCombat）。
  --   ⇒ 这 4 条挂成候选（kind=meta：**只计数**，不进任何桶）把这件事**钉死**：0 次 = 客户端真的不发。
  "PLAYER_REGEN_DISABLED",                   -- meta：主插件用它记「进战时刻」/ 进出战斗输出
  "PLAYER_REGEN_ENABLED",                    -- meta：同上（脱战）
  "PLAYER_TARGET_CHANGED",                   -- meta：主插件用它切目标刷新状态
  -- ★★★1.75.11 全事件抓取（229.8s / 55 个事件名）抓出来的**结构化战斗信息**候选 ——
  --   这几条**之前完全不知道存在**（事件名官方无索引 ⇒ 只有全收才能发现）：
  "UNIT_COMBAT",              -- 实测 107 次：arg1=target | arg2=WOUND | arg3=空 ⇒ 结构化「受伤」
  "COMBAT_TEXT_UPDATE",       -- 实测  56 次：arg1=DAMAGE | arg2=4 ⇒ 浮动战斗文字（类型+数值）
  "PLAYER_ENTER_COMBAT",      -- 实测  11 次：另有进战事件（比 PLAYER_REGEN_* 更频繁，11/11 成对）
  "PLAYER_LEAVE_COMBAT",      -- 实测  11 次
  "PLAYER_AURAS_CHANGED",     -- 实测  47 次：光环变化（buff/debuff 实时刷新的省事路）
  "CURRENT_SPELL_CAST_CHANGED", -- 实测 38 次：施法变化（本客户端无 UnitCastingInfo 的替代信号）
  "UNIT_HEALTH",                             -- meta：对照 —— 看本客户端到底发不发 UNIT_* 系列
}
local MW_ISEV = {}
for _, e in ipairs(MW_EVENTS) do MW_ISEV[e] = true end
-- 每条候选通道的语义分类（决定它进不进「围攻我的怪数」）：
--   in    = 怪用近战打我（★唯一进围攻统计的通道）
--   party = 怪打队友（旁证：说明这条事件名存在，但不是打我）
--   pvp   = 敌对玩家打我（1.12 有些客户端把 PvP 分出来）
--   other = 怪打怪/别的
--   out   = 对照：我打别人（1.55.0 已在用，确认存在的锚）
--   spell = 对照：法术/远程打我（正文里带技能名，不能当近战名用）
local MW_KIND = {
  ["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"] = "in",
  ["CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"] = "in",
  ["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS"] = "party",
  ["CHAT_MSG_COMBAT_CREATURE_VS_PARTY_MISSES"] = "party",
  ["CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS"] = "other",
  ["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"] = "pvp",
  ["CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"] = "pvp",
  ["CHAT_MSG_COMBAT_SELF_HITS"] = "out",
  ["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"] = "spell",
  ["CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"] = "out", -- 实测：我方 DoT
  ["CHAT_MSG_COMBAT_HOSTILE_DEATH"] = "kill",           -- 实测：击杀 ⇒ 把该怪踢出桶
  ["PLAYER_REGEN_DISABLED"] = "meta",  -- 只计数（反查主插件的进战事件到底有没有来）
  ["PLAYER_REGEN_ENABLED"] = "meta",
  ["PLAYER_TARGET_CHANGED"] = "meta",
  ["UNIT_HEALTH"] = "meta",
  ["UNIT_COMBAT"] = "meta",                 -- ★只计数 + 进 ⑨ 参数序列（语义待下一轮定案）
  ["COMBAT_TEXT_UPDATE"] = "meta",          -- ★同上（可能是「不解析文本就能拿伤害」的那条路）
  ["PLAYER_ENTER_COMBAT"] = "meta",
  ["PLAYER_LEAVE_COMBAT"] = "meta",
  ["PLAYER_AURAS_CHANGED"] = "meta",
  ["CURRENT_SPELL_CAST_CHANGED"] = "meta",
-- ★⑨ 段专用：这几条要看**不止首次**参数（要看清 arg1 会不会出现 player、arg3 是什么）
}

local MW_SEQ_EV = {
  ["UNIT_COMBAT"] = true,
  ["COMBAT_TEXT_UPDATE"] = true,
  ["PLAYER_ENTER_COMBAT"] = true,
  ["PLAYER_LEAVE_COMBAT"] = true,
}

-- 名字清洗：多字节禁入 Lua [...]（CLAUDE.md 5.1）⇒ 标点判断只看**首字节**（UTF-8：。=E3 80 82 ／ ，！？：=EF BC xx）
local function mwClean(nm)
  if type(nm) ~= "string" then return nil end
  nm = string.gsub(nm, "^%s+", "")
  nm = string.gsub(nm, "%s+$", "")
  if nm == "" or nm == "你" then return nil end
  if string.len(nm) > 40 then return nil end
  local b = string.byte(nm, 1)
  -- ★★本客户端聊天文本是 **UTF-8**（不是 GBK！）：CJK 表意字 = E4~E9 打头（雪=E9、黑=E9、幼=E5…）；
  --   CJK 标点 = E3 80 xx（。、）· 全角标点 = EF BC xx（，！？：）· 通用标点/符号 = E2 80/87 xx（… ⇒）。
  --   ⇒ 首字节是 E2/E3/EF 的一律**不是怪名**（是标点/符号）—— 离线实测：旧写法按 GBK 的 A1/A3 判断，
  --     「你闪避了。」会被认成攻击者名叫「。」（UTF-8 的 。= E3 80 82）⇒ 这条是那次离线测试抓出来的真 bug。
  if b == 0xE2 or b == 0xE3 or b == 0xEF then return nil end
  local c1 = string.sub(nm, 1, 1)
  if c1 == "." or c1 == "," or c1 == "!" or c1 == "?" or c1 == ":" or c1 == ";" then return nil end
  return nm
end

-- 「X的Y击中你…」（怪的技能/毒素打你）⇒ 攻击者是**的**之前那段，否则同一只怪会以
--   「雪豹幼崽」和「雪豹幼崽的撕咬」两个名字各记一笔 ⇒ 围攻数**虚高**（这种假数据最难发现）。
--   ★怪名通常不含「的」；归一只改计数键，原文照样留在 ④ 原始样本里可回溯。
local function mwBase(nm)
  if type(nm) ~= "string" then return nm end
  local b = string.match(nm, "^(.-)的")
  if b ~= nil and b ~= "" then return b end
  return nm
end

-- 从战斗消息原文里认出「攻击者名字」（纯函数，可断言）。返回 名字 或 nil + 原因
local MW_NAME_FIRST = { -- 名字在动词**前**：「野猪击中你造成12点伤害。」
  -- ★★★1.75.11 真机存档抓到的**幽灵名**：「峭壁野猪没有击中你。」按「最早出现的动词」切会切在「击中你」上
  --   ⇒ 名字段成了「峭壁野猪没有」⇒ 同一只怪在桶里**多出一个假攻击者**（存档 ③ 段真出现过「峭壁野猪没有」）。
  --   修法 = 把带「没有」的**完整短语也放进动词表**：它起点更早 ⇒ 切点自动落到「没有」之前，名字正好是怪名。
  "没有击中你", "没有命中你", "没有打中你",
  "击中你", "攻击你", "命中你", "对你造成", "打中你", "拍击你", "撕咬你",
  -- ★1.75.11 实测补：「X发起了攻击。你招架住了。」= CREATURE_VS_SELF_MISSES 的真实文案
  --   （旧表认不出 ⇒ 那条未命中被记进 ⑤；这是 ④⑤ 留证设计当场抓到的第一个真缺陷）
  "发起了攻击",
  " hits you", " misses you", " attacks you", " hit you",
}
local MW_NAME_AFTER = { -- 名字在动词**后**：「你闪避了野猪的攻击。」/ "You dodge Wolf's attack."
  "闪避了", "招架了", "格挡了", "躲开了", " dodge ", " parry ", " block ", " resist ",
}
function EVAL_MELEE_ATTACKER(txt)
  if type(txt) ~= "string" or txt == "" then return nil, "empty" end
  -- ① 名字在前：取**最早**出现的那个动词之前的整段
  local cut = nil
  for _, v in ipairs(MW_NAME_FIRST) do
    local s = string.find(txt, v, 1, true)
    if s ~= nil and (cut == nil or s < cut) then cut = s end
  end
  if cut ~= nil and cut > 1 then
    local nm = mwBase(mwClean(string.sub(txt, 1, cut - 1)))
    if nm ~= nil then return nm, "first" end
  end
  -- ② 名字在动词之后
  for _, v in ipairs(MW_NAME_AFTER) do
    local _, e = string.find(txt, v, 1, true)
    if e ~= nil then
      local rest = string.sub(txt, e + 1)
      local p = string.find(rest, "的", 1, true)
      if p == nil then p = string.find(rest, "'", 1, true) end
      local nm2 = mwClean((p ~= nil) and string.sub(rest, 1, p - 1) or rest)
      if nm2 ~= nil then return nm2, "after" end
    end
  end
  return nil, "nomatch"
end

-- 「我打它」方向的名字（**只用于交战数**，绝不进「围攻我的怪数」）：
--   中文「你击中X造成…」/「你爆击X造成…」· 宠物技能「你的撕咬使X受到了…」· 英文 "You hit X for …"。
--   认不出就返回 nil（不猜；原文照样留在 ④ 原始样本里可回溯）。
local function mwVictim(txt)
  if type(txt) ~= "string" or txt == "" then return nil end
  for _, v in ipairs({ "你击中", "你爆击" }) do
    local _, e = string.find(txt, v, 1, true)
    if e ~= nil then
      local rest = string.sub(txt, e + 1)
      local p = string.find(rest, "造成", 1, true)
      local nm = mwClean((p ~= nil) and string.sub(rest, 1, p - 1) or rest)
      if nm ~= nil then return nm end
    end
  end
  do
    local _, e = string.find(txt, "使", 1, true)
    if e ~= nil then
      local rest = string.sub(txt, e + 1)
      local p = string.find(rest, "受到了", 1, true)
      if p ~= nil then
        local nm = mwClean(string.sub(rest, 1, p - 1))
        if nm ~= nil then return nm end
      end
    end
  end
  -- ★1.75.11 实测补：「你没有击中大峭壁野猪。」（我方未命中）也带受害者名 ⇒ 归 out
  do
    local _, eM = string.find(txt, "你没有击中", 1, true)
    if eM ~= nil then
      local restM = string.sub(txt, eM + 1)
      local pM = string.find(restM, "。", 1, true)
      local nmM = mwClean((pM ~= nil) and string.sub(restM, 1, pM - 1) or restM)
      if nmM ~= nil then return nmM end
    end
  end
  for _, v in ipairs({ "You hit ", "You crit " }) do
    local _, e = string.find(txt, v, 1, true)
    if e ~= nil then
      local rest = string.sub(txt, e + 1)
      local p = string.find(rest, " for", 1, true)
      local nm = mwClean((p ~= nil) and string.sub(rest, 1, p - 1) or rest)
      if nm ~= nil then return nm end
    end
  end
  return nil
end

-- 记一笔「这个怪名最近跟我有过来往」（它打我 = dir in ／ 我打它 = dir out）
local function mwSee(nm, t, dir)
  if type(nm) ~= "string" or nm == "" then return end
  local r = MW.seen[nm]
  if r == nil then r = { last = t, n = 0, dir = dir } MW.seen[nm] = r end
  r.last = t
  r.n = r.n + 1
  r.dir = dir
end
-- 战斗状态闸门（★用户 1.75.11 口径：「周围怪统计只计算战斗状态.非战斗状态不需要统计」）：
--   · 闸门放在**桶写入之前**（与「关掉零动作」同族）：非战斗时只计数 + 落原始样本，
--     **不进** MW.atk / MW.seen（不进桶 = 那个数根本不会被算出来）；
--   · **进战清桶**：上一场的怪绝不许带进新一场（否则「刚打完那只」会在下一场开头冒充围攻数）；
--   · **脱战也清桶**（★1.75.11 用户口径「离开战斗重置」）：清之前先留一行「上一场快照」进读数环，
--     取证不丢（用户往往打完才敲 报告），但显示与条件一律按战斗状态给值（见 EVAL_MW_ACTIVE_INFO / EVAL_MW_UI_LINES）。
local function mwInCombat()
  if type(UnitAffectingCombat) ~= "function" then return false end
  local ok, v = pcall(UnitAffectingCombat, "player")
  return (ok and v) and true or false
end
local function mwCombatSync()
  local inC = mwInCombat()
  if inC ~= MW.inC then
    MW.inC = inC
    local t = (type(GetTime) == "function") and GetTime() or 0
    if inC then
      MW.atk, MW.seen = {}, {}   -- ★进战 = 新一场：清空上一场的桶
      MW.hits = {}               -- ★同理：上一场的挥击时刻不许带进新一场（否则开场第一拍就虚高）
      MW.cStart = t
    else
      MW.cEnd = t
      -- ★★★1.75.11 用户口径：「离开战斗重置」⇒ 脱战把**计数用的桶**清空（下一场从零开始；
      --   脱战后读值口/两个 UI 都是 0，不会拿上一场的残留冒充现状）。
      --   ★保留的三样：① 学到的攻速档位 MW.ivl（那是「这类怪多久挥一下」的知识，跨战斗才有用）；
      --     ② 取证计数（MW.counts/kills/peak —— 报告要看得见上一场）；③ 一行「上一场快照」。
      --   ★清 **之前** 先留快照：否则脱战后敲 报告 只剩 0 只，真机取证被这次重置吃掉（1.75.9 的老教训）。
      if next(MW.atk) ~= nil then
        local lst = {}
        for nmL, rL in pairs(MW.atk) do table.insert(lst, string.format("%s×%d", tostring(nmL), rL.n or 0)) end
        table.sort(lst)
        MW.lastSum = string.format("上一场（脱战即重置）：围攻过我的 %d 种 ｜ 本场峰值 %d 只 ｜ %s",
          table.getn(lst), MW.peak or 0, table.concat(lst, " "))
      end
      MW.atk, MW.seen, MW.hits = {}, {}, {}
    end
  end
  return inC
end
-- 击杀文案（★真机实测两种）：「你杀死了大峭壁野猪！」「大峭壁野猪死亡了。」
function EVAL_MELEE_KILLNAME(txt)
  if type(txt) ~= "string" or txt == "" then return nil end
  local _, eK = string.find(txt, "你杀死了", 1, true)
  if eK ~= nil then
    local restK = string.sub(txt, eK + 1)
    local pK = string.find(restK, "！", 1, true)
    if pK == nil then pK = string.find(restK, "!", 1, true) end
    local nmK = mwClean((pK ~= nil) and string.sub(restK, 1, pK - 1) or restK)
    if nmK ~= nil then return nmK end
  end
  local pK2 = string.find(txt, "死亡了", 1, true)
  if pK2 ~= nil and pK2 > 1 then
    local nmK2 = mwClean(string.sub(txt, 1, pK2 - 1))
    if nmK2 ~= nil then return nmK2 end
  end
  return nil
end
-- 喂入一条事件（探针关闭时**什么都不做**，返回 false）
-- 喂入一条事件（探针关闭时**什么都不做**，返回 false）
function EVAL_MW_FEED(ev, a1, a2, a3)
  if not MW.on then return false end
  local inC = mwCombatSync() -- ★先同步战斗状态（进战清桶 / 脱战只标记）
  local t = (type(GetTime) == "function") and GetTime() or 0
  MW.n = MW.n + 1
  if type(ev) == "string" then MW.counts[ev] = (MW.counts[ev] or 0) + 1 end
  local kind = MW_KIND[ev] or "?"
  -- ★⑨ 结构化通道的参数**序列**（有界 16 条）：UNIT_COMBAT / COMBAT_TEXT_UPDATE 这类要看清
  --   「arg1 会不会出现 player / arg2 有哪些类型 / arg3 是什么」——只看首次样本定不了案。
  if MW_SEQ_EV[ev] then
    table.insert(MW.seq, string.format("%s | arg1=%s | arg2=%s | arg3=%s", tostring(ev), tostring(a1), tostring(a2), tostring(a3)))
    while table.getn(MW.seq) > 16 do table.remove(MW.seq, 1) end
  end
  -- ★★meta 事件不进原始样本（真机实测：PLAYER_TARGET_CHANGED = **624 次/60s**、UNIT_HEALTH = 176 次）
  --   实测它们把 ④ 段 8 个名额全占了、战斗原文一条都留不下（样本池的设计缺陷，当场修）。
  if kind ~= "meta" then
    table.insert(MW.raw, string.format("%s | arg1=%s | arg2=%s | arg3=%s", tostring(ev), tostring(a1), tostring(a2), tostring(a3)))
    while table.getn(MW.raw) > 8 do table.remove(MW.raw, 1) end
  end
  if not inC then return true end
  -- ★击杀（实测 CHAT_MSG_COMBAT_HOSTILE_DEATH）：同一只怪会发**两条**死亡文案
  --   （「你杀死了X！」+「X死亡了。」）⇒ 1 秒内同名只计一次（否则击杀数直接翻倍，实测 12 次 = 6 只）
  if kind == "kill" then
    local kn = EVAL_MELEE_KILLNAME(a1)
    if kn ~= nil then
      MW.killLast = MW.killLast or {}
      local lastK = MW.killLast[kn]
      if lastK == nil or (t - lastK) > 1.0 then
        MW.kills = (MW.kills or 0) + 1
        MW.killLast[kn] = t
      end
      MW.atk[kn], MW.seen[kn] = nil, nil -- 死了就踢出两个桶（尸体不许继续算「还在围攻我」）
    end
    return true
  end
  -- ★只有「怪用近战打我」这条通道进「围攻我的怪数」（kind=in）；其它通道只计数 + 已落 ④ 原始样本。
  --   理由：法术通道正文是「X的冰霜箭击中你…」（名字里带技能名）、怪打队友根本不是打我 ⇒
  --   混进来会把「近战围攻我的怪数」读假（假读数最难发现，因为看着很像真数据）。
  if kind == "in" then
    local nm = EVAL_MELEE_ATTACKER(a1) -- ★只认正文；认不出留证
    -- ★★★1.75.11 记进时间环（★每条**只记一次** —— 早先这里先插了个裸时间戳、再插一次表，
    --   于是环里一半是垃圾、实际只装得下一半样本）。放在认名字的判空**之前**是判据：
    --   认不出的挥击也是挥击（名字记 "?"），漏掉它估算就偏低（组 249⑥ 有哨兵）。
    table.insert(MW.hits, { t = t, nm = nm or "?" })
    while table.getn(MW.hits) > MW_HITS_MAX do table.remove(MW.hits, 1) end
    if nm == nil then
      table.insert(MW.miss, tostring(ev) .. " → " .. tostring(a1))
      while table.getn(MW.miss) > 6 do table.remove(MW.miss, 1) end
      return true
    end
    local rec = MW.atk[nm]
    if rec == nil then rec = { last = t, n = 0, first = t } MW.atk[nm] = rec end
    rec.last = t
    rec.n = rec.n + 1
    mwSee(nm, t, "in")
    -- ★本场峰值：脱战后仍能看「这一场最多几只同时打我」（用户口径：只统计战斗状态）
    --   ★1.75.11 改用**估算**（按怪名分组 + 定档规则）—— 名字口径对同名怪只会数成 1，峰值也跟着虚低。
    local okP, nEst = pcall(EVAL_MW_EST_N, MW.win, t)
    if not (okP and type(nEst) == "number") then nEst = table.getn(EVAL_MW_ATTACKERS(MW.win, t)) end
    if nEst > (MW.peak or 0) then MW.peak = nEst end
    return true
  end
  -- ★「我打它」方向**只喂交战数**，绝不进 MW.atk：那会让「我在打它」也算成「它在打我」⇒ 围攻数虚高。
  if kind == "out" then
    local nm2 = mwVictim(a1)
    if nm2 ~= nil then mwSee(nm2, t, "out") end
  end
  return true
end

-- 窗口内「还在打我」的攻击者清单（按距上次命中升序）；win/now 可注入（便于断言）
function EVAL_MW_ATTACKERS(win, now)
  local w = tonumber(win) or MW.win
  local tn = tonumber(now) or ((type(GetTime) == "function") and GetTime() or 0)
  local list = {}
  for nm, r in pairs(MW.atk) do
    local age = tn - (r.last or 0)
    if age <= w then table.insert(list, { nm = nm, age = age, n = r.n, out = false }) end
  end
  table.sort(list, function(a, b) return (a.age or 0) < (b.age or 0) end)
  return list
end

-- ★1.75.11 攻速**定档吸附**（用户给的约束：只可能是 1.5 / 2.0 / 2.5 三档）：
--   把观测到的间隔吸附到最近的档位；离三档都超过容差 MW_TIER_TOL ⇒ 返回 nil（如实**不学**，绝不硬套）。
local function mwTierOf(g)
  if type(g) ~= "number" then return nil end
  local best, bd = nil, nil
  for i = 1, table.getn(MW_TIERS) do
    local d = math.abs(g - MW_TIERS[i])
    if bd == nil or d < bd then best, bd = MW_TIERS[i], d end
  end
  if best == nil or bd == nil or bd > MW_TIER_TOL then return nil end
  return best
end
-- 相邻两条间隔的**中位数**（抗单次异常；n<2 ⇒ nil）
local function mwMedianGap(ts)
  local n = table.getn(ts)
  if n < 2 then return nil end
  local gaps = {}
  for i = 2, n do table.insert(gaps, ts[i] - ts[i - 1]) end
  table.sort(gaps)
  local m = table.getn(gaps)
  if m <= 0 then return nil end
  return (m % 2 == 1) and gaps[(m + 1) / 2] or ((gaps[m / 2] + gaps[m / 2 + 1]) / 2)
end
-- ★「没学过档位」时按到达节奏**反推档位**：N 只怪均匀错相时 平均间隔 = I/N ⇒ I/g 应接近整数。
--   三档各算一次拟合误差，取最小的；误差超过容差 ⇒ nil（宁可用默认档，也不硬套）。
--   ★只在样本够密（n≥4）且跨度够长（≥3s）时用：开战那一下「齐射」相位挤在一起，跨度短会把档位判歪。
local function mwFitTier(meanGap)
  if type(meanGap) ~= "number" or meanGap <= 0 then return nil end
  local best, bs = nil, nil
  for i = 1, table.getn(MW_TIERS) do
    local I = MW_TIERS[i]
    local k = I / meanGap
    local r = math.floor(k + 0.5)
    if r < 2 then r = 2 end
    local d = math.abs(k - r)
    if bs == nil or d < bs then best, bs = I, d end
  end
  if best == nil or bs == nil or bs > MW_FIT_TOL then return nil end
  return best
end

-- ★★★1.75.11 被围攻**估算明细**（纯函数：win/now 可注入 ⇒ 可断言；**唯一实现** —— EVAL_MW_EST_N 只做求和，
--   断言读值口 EVAL_MW_TEST_DETAIL 也读它 ⇒ 不存在「读值口复刻一份逻辑」那种假绿）。
--   返回：明细数组（每项一个名字分组）, 窗口内条数。每项字段 = { nm, n, minGap, N, src, I, tier, span }
--   **按怪名分组**，每组独立判定（这才是「同类怪」场景的正解：名字相同也分得开几只）：
--   ① n == 1（窗口内只看到一条）⇒ 1 只。
--   ② **最小间隔 ≥ MW_GAP_SINGLE(1.4) ⇒ 可证只有 1 只**（单只 ≥1.5；两只错相 ≤1.25）——
--      ★这是定理不是估计 ⇒ 独苗永远算 1，绝不因为「窗口里条数多」被算成 2 只。
--   ③ 否则（出现 ≤1.3 的间隔）⇒ **至少 2 只**（可证），再由两条估计**取大**：
--      · 窗口法：floor(n × I ÷ 窗口)
--      · 跨度法：round(I × (n−1) ÷ 跨度)（跨度 = 末次 − 首次；对窗口边界不敏感，通常更准）
--      I = 学到的档位 → 否则反推档位（够样本时）→ 否则**默认 2.0**。
--   ④ 合计后封顶 MW_ESTCAP。
-- ★★★自学习（用户 1.75.11 追加口径：「自学习成功的怪并不是就一直保持不变…如果同名怪攻速达到 1.4 以上
--   则这个怪攻速必然是单只怪的攻速，要**及时学习更新**这个怪的攻速，未学习的怪攻速默认 2.0」）：
--   · **每次**出现「可证单只」的窗口都把中位间隔吸附到档位并**覆盖**旧值（不是学一次就冻结）；
--   · 覆盖时记一笔变更日志 MW.ivlLog（旧档→新档，有界 12 条，报告里打出来）与学习次数 MW.ivlN（真机可核：
--     「学到过几次、什么时候改的档」一眼可见）；
--   · 多只窗口里**绝不学**（那里学到的是 I/怪数）—— 组 249①d 用哨兵钉死；
--   · 从没学过该名字 ⇒ I 走默认 MW_ESTI(2.0)，明细里 src = "default"（组 249⑨ 有哨兵）。
function EVAL_MW_EST_DETAIL(win, now)
  local w = tonumber(win) or MW_UIWIN
  local tn = tonumber(now) or ((type(GetTime) == "function") and GetTime() or 0)
  local byName, order, nTotal = {}, {}, 0
  for i = 1, table.getn(MW.hits) do
    local h = MW.hits[i]
    if type(h) == "table" and h.t ~= nil and (tn - h.t) <= w then
      local nm = h.nm or "?"
      local arr = byName[nm]
      if arr == nil then arr = {} byName[nm] = arr table.insert(order, nm) end
      table.insert(arr, h.t)
      nTotal = nTotal + 1
    end
  end
  local det = {}
  for k = 1, table.getn(order) do
    local nm = order[k]
    local ts = byName[nm]
    local n = table.getn(ts)
    local minGap = nil
    for i = 2, n do
      local d = ts[i] - ts[i - 1]
      if minGap == nil or d < minGap then minGap = d end
    end
    local row = { nm = nm, n = n, minGap = minGap, N = 1, src = "one", I = nil, tier = nil, span = 0 }
    if n >= 2 then
      if minGap ~= nil and minGap >= MW_GAP_SINGLE then
        -- ★可证单只 ⇒ 恰好 1 只；并且**每次都重新学**（用户口径：不是一直保持不变，要及时更新）
        row.N, row.src = 1, "single"
        local med = mwMedianGap(ts)
        local tier = mwTierOf(med)
        row.tier = tier
        if tier ~= nil then
          local old = MW.ivl[nm]
          MW.ivlSeen[nm] = (MW.ivlSeen[nm] or 0) + 1 -- ★监测计数：又确认了一次「这只怪是单只」（档位没变也记）
          if old ~= tier then
            MW.ivlN[nm] = (MW.ivlN[nm] or 0) + 1      -- ★更新计数：档位**真的变了**才 +1（首次学到也算 1 次）
            if old == nil then
              table.insert(MW.ivlLog, string.format("%s 首次学到 %.1fs（实测中位 %.2fs）", tostring(nm), tier, med))
            else
              table.insert(MW.ivlLog, string.format("%s %.1fs→%.1fs（实测中位 %.2fs）", tostring(nm), old, tier, med))
            end
            while table.getn(MW.ivlLog) > MW_IVLLOG_MAX do table.remove(MW.ivlLog, 1) end
          end
          MW.ivl[nm] = tier
        end
        row.I = MW.ivl[nm] or MW_ESTI
      else
        local span = ts[n] - ts[1]
        row.span = span
        local I = MW.ivl[nm]
        local src = "learned"
        if I == nil and n >= MW_FIT_MIN_N and span >= MW_FIT_MIN_SPAN then
          I = mwFitTier(span / (n - 1)) -- 反推档位（样本够密才敢用）
          if I ~= nil then src = "fit" end
        end
        if I == nil then I = MW_ESTI src = "default" end -- ★未学习 ⇒ 默认 2.0
        row.I, row.src = I, src
        local nWin = math.floor((n * I) / w)
        if nWin < 2 then nWin = 2 end
        local nSpr = 2
        if span >= MW_GAP_SINGLE then
          nSpr = math.floor((I * (n - 1)) / span + 0.5)
          if nSpr < 2 then nSpr = 2 end
        end
        row.N = (nSpr > nWin) and nSpr or nWin
      end
    end
    table.insert(det, row)
  end
  return det, nTotal
end

-- ★★★1.75.11 被围攻**估算**（对外的数）：求和 + 封顶。返回：估算只数, 窗口内条数, 名字分组数
function EVAL_MW_EST_N(win, now)
  local det, nTotal = EVAL_MW_EST_DETAIL(win, now)
  local nGroups = table.getn(det)
  if nTotal <= 0 then return 0, 0, 0 end
  local est = 0
  for i = 1, nGroups do est = est + (det[i].N or 0) end
  if est > MW_ESTCAP then est = MW_ESTCAP end
  return est, nTotal, nGroups
end

-- 「最近跟我交战过的怪」清单（它打我 **或** 我打它；★纯消息口径、**零切目标**）
function EVAL_MW_ENGAGED(win, now)
  local w = tonumber(win) or MW_UIENG
  local tn = tonumber(now) or ((type(GetTime) == "function") and GetTime() or 0)
  local list = {}
  for nm, r in pairs(MW.seen) do
    local age = tn - (r.last or 0)
    if age <= w then table.insert(list, { nm = nm, age = age, n = r.n, dir = r.dir }) end
  end
  table.sort(list, function(a, b) return (a.age or 0) < (b.age or 0) end)
  return list
end
-- 全事件抓取的名字清单（供报告/命令计数）
local function mwAllNames()
  local out = {}
  for k in pairs(MW.allCounts) do table.insert(out, k) end
  return out
end
-- 采集帧（**懒建**：不跑「开始」就一个帧都不建）
-- 事件名形状过滤：WoW 事件名一律「大写字母 + 数字 + 下划线」⇒ 用它把「正文文本被当成事件名」挡掉
--   （本客户端参数布局不确定：可能 ea=事件名，也可能只传参数、事件名走全局 event）
local function mwEvName(s)
  if type(s) ~= "string" then return nil end
  if string.match(s, "^[A-Z][A-Z0-9_]*$") == nil then return nil end
  return s
end

local function mwFrame()
  if MW.frame ~= nil then return MW.frame end
  if type(CreateFrame) ~= "function" then return nil end
  local ok, f = pcall(CreateFrame, "Frame", "EVAL_HELP_MELEE_PROBE", UIParent)
  if not ok or f == nil then return nil end
  pcall(f.SetScript, f, "OnEvent", function(ea, eb)
    local ev = mwEvName(ea) or mwEvName(eb) or ((type(event) == "string") and mwEvName(event) or nil)
    if ev ~= nil and MW_ISEV[ev] then
      -- ★参数布局不猜：三态取正文（谁像消息就用谁），三个原值一起喂进去留证
      local txt = nil
      if type(arg1) == "string" and not MW_ISEV[arg1] then txt = arg1
      elseif type(ea) == "string" and not MW_ISEV[ea] then txt = ea
      elseif type(eb) == "string" and not MW_ISEV[eb] then txt = eb end
      EVAL_MW_FEED(ev, txt, arg2, arg3)
      return
    end
    -- ★全事件抓取（1.75.11）：事件名**官方索引里根本没有**（85 个分类里没有 Events）⇒
    --   只能把「这一战真正来过的事件」读出来（照搬追踪探针 /eh go 追踪探针 监听 的实证做法）。
    if MW.all and ev ~= nil then
      MW.allCounts[ev] = (MW.allCounts[ev] or 0) + 1
      if MW.allSample[ev] == nil then
        MW.allSample[ev] = string.format("arg1=%s | arg2=%s | arg3=%s", tostring(arg1), tostring(arg2), tostring(arg3))
      end
    end
  end)
  MW.frame = f
  return f
end

-- 专属落盘的写入口（有界 40 行；同 trkProbe 的形态 { out = {…} } ⇒ 清残渣/读存档同一套）
local function mwOut(s)
  local cfg = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
  if cfg == nil then return end
  local box = cfg.meleeProbe
  if type(box) ~= "table" then box = { out = {} } cfg.meleeProbe = box end
  if type(box.out) ~= "table" then box.out = {} end
  table.insert(box.out, tostring(s))
  while table.getn(box.out) > MW_OUT_MAX do table.remove(box.out, 1) end
  box.t = (type(date) == "function") and date("%H:%M:%S") or nil
end
local function mwSay(s)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[近战探针] " .. tostring(s)) end
  pcall(mwOut, s) -- ★专属持久读数（不被 [DS] 心跳冲掉）
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, s) else print(s) end
end

-- ① 读客户端自己认的聊天消息组（返回 组名表 或 nil+原因）
function EVAL_MW_CHANNELS()
  if type(GetChatWindowMessages) ~= "function" then return nil, "noapi" end
  local ok, s = pcall(GetChatWindowMessages, 1)
  if not ok then return nil, "error" end
  if type(s) ~= "string" then return nil, "notstr（读到 " .. type(s) .. "）" end
  local out = {}
  for part in string.gmatch(s, "[^,%s]+") do table.insert(out, part) end
  return out, nil
end

-- ③ 周围敌人数量：走既有的 EVAL_NEARBY_ENEMY_NAMES（带轨迹回调，量回自证切了哪些目标）
function EVAL_MW_NEARBY(maxN)
  local trace = {}
  local names = {}
  if type(EVAL_NEARBY_ENEMY_NAMES) == "function" then
    local okn, res = pcall(EVAL_NEARBY_ENEMY_NAMES, maxN or 12, function(nm) table.insert(trace, tostring(nm)) end)
    if okn and type(res) == "table" then names = res end
  end
  return names, trace
end

function EVAL_MW_START(byUI)
  -- ★byUI=true = 由状态信息UI 自动拉起（UI 关掉时它负责停）；命令手动开始 = 不由 UI 管
  MW.uiStarted = byUI and true or false
  local f = mwFrame()
  if f == nil then return false, "CreateFrame 不可用（建不了采集帧）" end
  local reg, bad = {}, {}
  for _, ev in ipairs(MW_EVENTS) do
    local ok = pcall(f.RegisterEvent, f, ev)
    if ok then table.insert(reg, ev) else table.insert(bad, ev) end
  end
  MW.reg, MW.bad = reg, bad
  MW.on = true
  MW.t0 = (type(GetTime) == "function") and GetTime() or 0
  MW.n = 0
MW.counts, MW.atk, MW.raw, MW.miss, MW.seen, MW.allCounts, MW.allSample, MW.kills = {}, {}, {}, {}, {}, {}, {}, 0
  MW.hits, MW.ivl, MW.ivlN, MW.ivlSeen, MW.ivlLog = {}, {}, {}, {}, {} -- ★1.75.11 时间环 + 档位/更新次数/监测次数/变更日志一并归零
                             --   ★进战/脱战都**不**清 ivl：学到的档位是「这类怪多久挥一下」的知识，跨战斗才有用
  MW.peak, MW.killLast, MW.seq = 0, {}, {}
  pcall(EVAL_MW_CHAT_RESET) -- ★截获计数一并归零（全局查表：本函数定义在它之前，写 local 会绑成 nil）
  return true, reg, bad
end

function EVAL_MW_STOP()
  if MW.frame ~= nil then
    -- ★全事件抓取是**重量级**（所有事件都会进来）⇒ 停采集时必须一起摘掉（「关掉零动作」纪律）
    if MW.all and type(MW.frame.UnregisterAllEvents) == "function" then
      pcall(MW.frame.UnregisterAllEvents, MW.frame)
      MW.all = false
    end
    for _, ev in ipairs(MW_EVENTS) do pcall(MW.frame.UnregisterEvent, MW.frame, ev) end
  end
  MW.on = false
  pcall(EVAL_MW_CHAT_OFF) -- ★关掉零动作：截获层也一起摘（它挂在全局 ChatFrame_OnEvent 上）
  return true
end

function EVAL_MW_REPORT(win)
  local w = tonumber(win) or MW.win
  MW.win = w
  local now = (type(GetTime) == "function") and GetTime() or 0
  local dur = (MW.t0 ~= nil) and (now - MW.t0) or 0
  mwSay("===== 近战围攻探针（1.75.11）=====")
  mwSay(string.format("采集状态：%s ｜ 已跑 %.1fs ｜ 收到候选事件 %d 次 ｜ 判定窗口 %ds",
    MW.on and "开启" or "已停", dur, MW.n, w))
  -- ① 客户端自己认的消息组：★1.75.11 改成**扫所有聊天窗**（真机实测：战斗文字不在窗口1，
  --   窗口1 一个 COMBAT 组都没有 ⇒ 只看窗口1 会得出「战斗文字不走消息组」的错误结论）
  if type(GetChatWindowMessages) == "function" then
    local nWin = (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS > 0) and NUM_CHAT_WINDOWS or 7
    mwSay(string.format("① 各聊天窗的战斗消息组（NUM_CHAT_WINDOWS=%d；事件名 = CHAT_MSG_ + 组名）:", nWin))
    local anyWin = 0
    for w = 1, nWin do
      local okw, sw = pcall(GetChatWindowMessages, w)
      if okw and type(sw) == "string" and sw ~= "" then
        local tot, hit = 0, {}
        for part in string.gmatch(sw, "[^,%s]+") do
          tot = tot + 1
          if string.find(string.upper(part), "COMBAT", 1, true) ~= nil then table.insert(hit, part) end
        end
        if table.getn(hit) > 0 then
          anyWin = anyWin + 1
          mwSay(string.format("    窗口%d：共 %d 组 ｜ 含 COMBAT %d 组：%s", w, tot, table.getn(hit), table.concat(hit, " ／ ")))
        end
      end
    end
    if anyWin == 0 then
      mwSay("    ★所有窗口都没有含 COMBAT 的组 ⇒ 战斗文字不走聊天窗口消息组（那就只看 ② 的实际次数）")
    else
      mwSay(string.format("    ★有 %d 个窗口带战斗消息组（战斗记录页通常是窗口2 = ChatFrame2）", anyWin))
    end
  else
    mwSay("① 战斗消息组：本客户端没有 GetChatWindowMessages（只看 ② 的实际次数）")
  end
  -- ② 每个候选事件实际来了几次（★0 次才是关键读数）
  local cnt = {}
  for _, ev in ipairs(MW_EVENTS) do table.insert(cnt, { ev = ev, n = MW.counts[ev] or 0, k = MW_KIND[ev] or "?" }) end
  table.sort(cnt, function(a, b) return (a.n or 0) > (b.n or 0) end)
  mwSay("② 候选事件触发次数（★0 次 = 本客户端没有这个事件名；[in]=怪近战打我·进围攻数，其它=对照旁证）:")
  for i = 1, table.getn(cnt) do
    mwSay(string.format("    [%s] %s = %d 次%s", cnt[i].k, cnt[i].ev, cnt[i].n, (cnt[i].n == 0) and "  ← 没来" or ""))
  end
  if MW.frame ~= nil and type(IsEventRegistered) == "function" then
    local yes = 0
    for _, ev in ipairs(MW_EVENTS) do
      local okr, r = pcall(IsEventRegistered, ev)
      if okr and (r == true or r == 1) then yes = yes + 1 end
    end
    mwSay(string.format("②b IsEventRegistered 报「已注册」%d/%d 条（★本客户端返 1 不是 true，判据写 (r==true or r==1)）",
      yes, table.getn(MW_EVENTS)))
  end
  -- ③ 窗口内「还在近战打我」的怪
  local list = EVAL_MW_ATTACKERS(w, now)
  -- ★③b 交战口径（它打我 或 我打它；纯消息、零切目标）
  local engL = EVAL_MW_ENGAGED(MW_UIENG, now)
  local engS = {}
  for i = 1, table.getn(engL) do table.insert(engS, engL[i].nm) end
  mwSay(string.format("③b 交战过的怪（打我 或 我打它，最近 %ds）：%d 只%s", MW_UIENG, table.getn(engL),
    (table.getn(engS) > 0) and ("：" .. table.concat(engS, "、")) or ""))
  mwSay(string.format("③ 口径=只统计战斗状态（当前 %s）｜窗口 %ds 内「在近战打我」的怪：%d 只",
    (MW.inC and "战斗中" or "非战斗（下面是最近一场的残留读数，仅供取证）"), w, table.getn(list)))
  for i = 1, table.getn(list) do
    mwSay(string.format("    %d. %s ｜ 距上次命中 %.1fs ｜ 累计 %d 次", i, list[i].nm, list[i].age, list[i].n))
  end
  local out, nOut = {}, 0
  for nm, r in pairs(MW.atk) do
    local age = now - (r.last or 0)
    if age > w then nOut = nOut + 1 table.insert(out, { nm = nm, age = age }) end
  end
  if nOut > 0 then
    table.sort(out, function(a, b) return (a.age or 0) < (b.age or 0) end)
    mwSay(string.format("    （窗口外历史攻击者 %d 只，最近一只 %s 在 %.1fs 前停手）", nOut, out[1].nm, out[1].age))
  end
  if (MW.kills or 0) > 0 then
    mwSay(string.format("③c 本场击杀（实测通道 CHAT_MSG_COMBAT_HOSTILE_DEATH）：%d 只 —— 击杀的怪已从围攻桶里踢掉", MW.kills or 0))
  end
  if (MW.peak or 0) > 0 then
    mwSay(string.format("③d 本场峰值：同时有 %d 只怪在近战打我（★脱战后仍看得到）", MW.peak))
  end
  -- ★1.75.11 ③e 估算读数（用户口径：4s 窗口、按怪名分组、攻速定档 1.5/2.0/2.5；与名字数取大）
  --   ★这里**不**走读值口的战斗闸门，脱战后也要看得见（取证口径），终值按「取大」现算。
  do
    local nN = table.getn(list)
    local eE, nE, gE = EVAL_MW_EST_N(w, now)
    mwSay(string.format("③e 围攻估算（%ds 窗口·档位 %.1f/%.1f/%.1f）：窗口内挥击 %d 次 ｜ 名字分组 %d 类 ｜ 估算 %d 只 ｜ 名字数 %d ｜ 终值（取大）%d",
      w, MW_TIERS[1], MW_TIERS[2], MW_TIERS[3], nE, gE, eE, nN, (eE > nN) and eE or nN))
    -- ★学到的攻速档位（键 = 怪名）：真机复核用 —— 看吸附到哪一档对不对（单只怪打一轮就能学下来）
    local ivlT = {}
    for nmI, vI in pairs(MW.ivl) do
      table.insert(ivlT, string.format("%s=%.1fs（更新%d次/确认单只%d次）", tostring(nmI), vI, MW.ivlN[nmI] or 0, MW.ivlSeen[nmI] or 0))
    end
    if table.getn(ivlT) > 0 then
      table.sort(ivlT)
      mwSay("     已学到的攻速档位（自学习·吸附到档位，" .. table.getn(ivlT) .. " 种）：" .. table.concat(ivlT, " ｜ "))
    else
      mwSay(string.format("     还没学到任何档位（★未学习的怪一律按默认 %.1fs 估算）", MW_ESTI))
    end
    -- ★★档位**变更日志**（用户口径：「不是一直保持不变…要及时学习更新」）——真机一眼看有没有在更新
    if table.getn(MW.ivlLog) > 0 then
      mwSay("     档位更新记录（最近 " .. table.getn(MW.ivlLog) .. " 次变更；★学过的怪一直在监测，变了就覆盖）：")
      for i = 1, table.getn(MW.ivlLog) do mwSay("        " .. MW.ivlLog[i]) end
    end
    if type(MW.lastSum) == "string" then mwSay("③f " .. MW.lastSum) end
  end
  -- ④⑤ 原始样本 + 认不出的原文（取证）
  if table.getn(MW.raw) > 0 then
    mwSay("④ 原始样本（最近 " .. table.getn(MW.raw) .. " 条，原样）:")
    for i = 1, table.getn(MW.raw) do mwSay("    " .. MW.raw[i]) end
  end
  if table.getn(MW.miss) > 0 then
    mwSay("⑤ 认不出攻击者的原文（最近 " .. table.getn(MW.miss) .. " 条；★认不出也要留证，不许静默丢）:")
    for i = 1, table.getn(MW.miss) do mwSay("    " .. MW.miss[i]) end
  end
  mwSay("   ★周围怪数：/eh go melee 周围 = 消息口径（零副作用，不切目标）；要看真值才加 切目标")
  -- ⑥ 全事件抓取：事件名官方无索引 ⇒ 这是「战斗信息到底有哪些通道」的实证清单
  if MW.all or next(MW.allCounts) ~= nil then
    local aNames = mwAllNames()
    table.sort(aNames, function(a, b) return (MW.allCounts[a] or 0) < (MW.allCounts[b] or 0) end)
    mwSay(string.format("⑥ 全事件抓取%s：共 %d 个不同事件名（★按次数升序，少的在前 = 可疑候选）",
      MW.all and "（进行中）" or "", table.getn(aNames)))
    local capA = 60 -- ★1.75.11 30 → 60：真机一轮就有 **53 个**不同事件名，30 条装不下（"还有 23 个没列"）
    for i = 1, table.getn(aNames) do
      if i > capA then mwSay(string.format("    …（还有 %d 个没列完；先关掉落盘再报告就能看全）", table.getn(aNames) - capA)) break end
      mwSay(string.format("    %s = %d 次 ｜ 首次 %s", aNames[i], MW.allCounts[aNames[i]] or 0, tostring(MW.allSample[aNames[i]] or "")))
    end
  end
  -- ⑦ 聊天入口截获读数（★不依赖事件名的那条路）
  local okC, cst = pcall(EVAL_MW_CHAT_STATE)
  if okC and type(cst) == "table" and (cst.n or 0) > 0 then
    mwSay(string.format("⑦ 聊天入口截获：经过 %d 条 ｜ 取不到文本 %d 条 ｜ 最近原文：", cst.n, cst.noMsg))
    for i = 1, table.getn(cst.raw) do mwSay("    " .. cst.raw[i]) end
  end
  -- ⑨ 结构化战斗通道的参数序列（★UNIT_COMBAT / COMBAT_TEXT_UPDATE 语义定案用）
  if table.getn(MW.seq) > 0 then
    mwSay(string.format("⑨ 结构化通道参数序列（最近 %d 条；重点看 arg1 有没有 player / arg2 有哪些类型）:", table.getn(MW.seq)))
    for i = 1, table.getn(MW.seq) do mwSay("    " .. MW.seq[i]) end
  end
  mwSay("读数已落存档 cfg.meleeProbe（上限 " .. MW_OUT_MAX .. " 行）⇒ /reload 后即可读存档")
end

function EVAL_MW_CMD(sub)
  local s = tostring(sub or "")
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  local word, restArg = string.match(s, "^(%S+)%s*(.*)$")
  local cmd = word or ""
  -- ★总闸门（调试日志）关着时的**看得见的回头路**：读数照常落盘，但要告诉用户怎么开回来
  if type(EVAL_CHAT_ON) == "function" then
    local okc, on = pcall(EVAL_CHAT_ON)
    if okc and on ~= true and type(EVAL_SAY_FORCE) == "function" then
      pcall(EVAL_SAY_FORCE, "近战探针：聊天输出总闸门（调试日志）关着 —— 读数照常落存档 cfg.meleeProbe，/reload 后可读；想看聊天框请打开「调试日志」")
    end
  end
  if cmd == "" or cmd == "状态" or cmd == "status" then
    mwSay(string.format("近战围攻探针：%s ｜ 窗口 %ds ｜ 收到候选事件 %d 次 ｜ 窗口内攻击者 %d 只",
      MW.on and "正在采集" or "未采集", MW.win, MW.n, table.getn(EVAL_MW_ATTACKERS(MW.win))))
    mwSay("用法：/eh go melee 开始 | 停 | 报告 [窗口秒] | 周围 [切目标] | 通道 | 战斗窗口 | 截获 | 全事件 | 清")
    mwSay("  ★开始 = 去拉 3~5 只近战怪打你，十几秒后 报告；跑完 /reload 我读存档")
  elseif cmd == "开始" or cmd == "start" then
    local ok, reg, bad = EVAL_MW_START()
    if not ok then mwSay("近战探针：开始失败 —— " .. tostring(reg)) return end
    mwSay(string.format("近战探针：采集已开始（挂上 %d 条候选事件；%d 条注册时抛错）",
      table.getn(reg), table.getn(bad)))
    mwSay("   现在去拉 3~5 只**近战**怪打你（让它们真的打到你），十几秒后敲 /eh go melee 报告")
    mwSay("   ★报告前不用停；跑完 /reload，我直接读存档 cfg.meleeProbe")
  elseif cmd == "停" or cmd == "stop" then
    EVAL_MW_STOP()
    mwSay("近战探针：已停（候选事件全部摘掉；再敲 开始 才会重新采集）")
  elseif cmd == "报告" or cmd == "report" then
    EVAL_MW_REPORT(tonumber(restArg))
  elseif cmd == "周围" or cmd == "nearby" then
    -- ★★用户口径「非战斗也不要切目标」⇒ 默认 一个目标都不切，只报消息口径的交战数。
    if restArg == "切目标" or restArg == "force" then
      -- ★双重要求才切：用户显式要「真值」时才动目标，读完立刻按原名还原（没原目标则清除）
      local names, trace = EVAL_MW_NEARBY(12)
      mwSay(string.format("周围可选中敌人（TargetNearestEnemy 循环）：%d 只", table.getn(names)))
      if table.getn(trace) > 0 then mwSay("    循环轨迹：" .. table.concat(trace, " → ")) end
      if table.getn(names) > 0 then mwSay("    名单：" .. table.concat(names, "、")) end
      mwSay("    ★口径：同名怪按名字去重、循环回到见过的名字即停 ⇒ 真怪数可能更多。")
      mwSay("    ★副作用：过程中确实切了目标，结束已按原名还原（这是你自己敲了 切目标 才做的）。")
    else
      local now = (type(GetTime) == "function") and GetTime() or 0
      local eng = EVAL_MW_ENGAGED(MW_UIENG, now)
      local names = {}
      for i = 1, table.getn(eng) do table.insert(names, eng[i].nm) end
      mwSay(string.format("周围怪数（消息口径·最近 %ds 跟我有过来往的）：%d 只 ｜ 口径=只统计战斗状态（当前 %s）",
        MW_UIENG, table.getn(eng), (MW.inC == true) and "战斗中" or "非战斗"))
      if table.getn(names) > 0 then mwSay("    名单：" .. table.concat(names, "、")) end
      mwSay("    ★零副作用：这条 一个目标都不切（它打我 / 我打它 都从聊天正文里认名字）。")
      mwSay("    ★数不到「还没交过手、也没打过我的怪」—— 客户端没有附近敌人枚举 API。")
      mwSay("    ★要看真值（能被 TargetNearestEnemy 选中的敌人数）请显式敲：/eh go melee 周围 切目标")
    end
  elseif cmd == "全事件" or cmd == "all" then
    -- ★★事件名官方**没有索引**（85 个分类里没有 Events）⇒「战斗信息有哪些通道」只能真机读出来：
    --   这条 = RegisterAllEvents 全事件抓取（与 /eh go 追踪探针 监听 同一套实证做法）。
    local fAll = mwFrame()
    if fAll == nil then
      mwSay("全事件抓取：建不了采集帧（CreateFrame 不可用）")
    elseif MW.all then
      MW.all = false
      if type(fAll.UnregisterAllEvents) == "function" then pcall(fAll.UnregisterAllEvents, fAll) end
      for _, ev in ipairs(MW_EVENTS) do pcall(fAll.RegisterEvent, fAll, ev) end -- ★候选事件挂回来（UnregisterAllEvents 把它们也摘了）
      mwSay(string.format("全事件抓取：已关 ｜ 本次共 %d 个不同事件名 ｜ 候选事件已重新挂回", table.getn(mwAllNames())))
    elseif type(fAll.RegisterAllEvents) ~= "function" then
      mwSay("全事件抓取：本客户端没有 RegisterAllEvents（官方索引里列着，实测却缺 ⇒ 如实报告，不假装）")
    else
      if not MW.on then pcall(EVAL_MW_START, true) end
      MW.allCounts, MW.allSample = {}, {}
      local okRA = pcall(fAll.RegisterAllEvents, fAll)
      MW.all = true
      mwSay(okRA and "全事件抓取：已开（RegisterAllEvents）—— 现在去打一场，打完敲 /eh go melee 报告"
        or "全事件抓取：RegisterAllEvents 调用抛错（如实报告，不假装开着）")
      mwSay("   ★报告会按**次数升序**列出这一战真正来过的事件名（少的在前 = 候选通道），并附首次样本 arg1/2/3")
    end
  elseif cmd == "战斗窗口" or cmd == "cf2" or cmd == "chatframe" then
    EVAL_MW_COMBAT_WINDOW(tonumber(restArg))
  elseif cmd == "截获" or cmd == "chat" then
    -- ★读全局读值口，不碰模块 local（本函数定义在 u_chat 段之前：直接索引那个 local 会绑成全局 nil）
    local cst = EVAL_MW_CHAT_STATE()
    if cst.on == true then
      local okc, why = EVAL_MW_CHAT_OFF()
      mwSay(okc and string.format("截获：已关（共经过 %d 条；取不到文本 %d 条）", cst.n, cst.noMsg)
        or ("截获：关时未硬还原（" .. tostring(why) .. "）—— 别人后来又包了一层，硬还原会打掉别人的层（如实报告）"))
    else
      if not MW.on then pcall(EVAL_MW_START, true) end
      local okc, why = EVAL_MW_CHAT_ON()
      mwSay(okc and "截获：已开（包住 ChatFrame_OnEvent，读回确认过）—— 现在去打一场，打完敲 /eh go melee 报告"
        or ("截获：没挂上（" .. tostring(why) .. "）⇒ 如实报告，不假装挂着"))
      if okc then mwSay("   ★这条**不依赖事件名**：凡是进聊天窗的战斗文字都会过这里（战斗记录页 = ChatFrame2）") end
    end
  elseif cmd == "通道" or cmd == "channels" then
    local grp, why = EVAL_MW_CHANNELS()
    if grp == nil then
      mwSay("通道：读不到（原因=" .. tostring(why) .. "）")
    else
      local hit = {}
      for i = 1, table.getn(grp) do
        if string.find(string.upper(grp[i]), "COMBAT", 1, true) ~= nil then table.insert(hit, grp[i]) end
      end
      mwSay(string.format("通道：GetChatWindowMessages(1) 共 %d 组；含 COMBAT 的 %d 组：", table.getn(grp), table.getn(hit)))
      if table.getn(hit) > 0 then mwSay("    " .. table.concat(hit, " ／ ")) end
      mwSay("    全量组名（便于我核对）：" .. table.concat(grp, ","))
    end
  elseif cmd == "清" or cmd == "clear" then
    EVAL_MW_STOP()
    MW.counts, MW.atk, MW.raw, MW.miss, MW.seen, MW.allCounts, MW.allSample, MW.kills, MW.n, MW.t0 = {}, {}, {}, {}, {}, {}, {}, 0, 0, nil
    local cfg = (type(EVAL_HELP_CONFIG) == "table") and EVAL_HELP_CONFIG or nil
    if cfg ~= nil then cfg.meleeProbe = { out = {} } end
    mwSay("近战探针：内存读数与专属存档已清空（存档那份要 /reload 才落盘）")
  else
    mwSay("近战探针：不认识的子命令「" .. tostring(cmd) .. "」")
    mwSay("用法：/eh go melee 开始 | 停 | 报告 [窗口秒] | 周围 [切目标] | 通道 | 战斗窗口 | 截获 | 全事件 | 清")
  end
end

-- ===== 临时测试挂接（1.75.11）：状态信息UI 里显示「围攻我的怪数」+「周围怪数」 =====
-- ★用户原话：「可以进入战斗..离开战斗. 临时添加个战斗状态,周围怪物数量的状态值.在战斗UI状态Ui 内测试」
--   · 战斗状态：状态UI 本来就有那一行（collectStats 的 s.incombat → 战斗中 x.xs / 非战斗），无需新增；
--   · 新增两个状态值 = 「围攻我的怪数」+「周围怪数（交战口径）」。
-- ★★★两条用户口径（1.75.11，别改回去）：
--   ① 「非战斗也不要切目标」⇒ 自动路径一个目标都不切：周围怪数 = 纯消息口径
--      （最近 MW_UIENG 秒跟我有过来往的怪名：它打我 / 我打它），TargetNearestEnemy 循环降级为手工命令
--      `/eh go melee 周围 切目标`；
--   ② 「周围怪统计只计算战斗状态.非战斗状态不需要统计」⇒ 闸门在桶写入之前（见 mwCombatSync），
--      这里的显示也按战斗状态给值：非战斗一律显示「——（非战斗·不统计）」，一个数都不报。
-- ★代价要认：客户端没有附近敌人枚举 API ⇒ 消息口径数不到「还没交过手、也没打过我的怪」。
-- ★另两条纪律：① 采集只在状态UI 打开期间进行（UI 关掉立刻 EVAL_MW_UI_OFF = 零动作）；
--   ② UI 关掉时自动往专属读数环留一条紧凑快照（用户不必记得敲 报告，否则我这边读不到）。
function EVAL_MW_UI_ON()
  if not MW.on then pcall(EVAL_MW_START, true) end
  MW.uiOpen = true -- ★1.75.11 「状态UI 现在开着」标记（UI_OFF 靠它决定要不要留快照；见下）
  mwCombatSync() -- ★每拍同步战斗状态（进战清桶 / 脱战标记）—— 显示与条件都按它给值
  return true
end
function EVAL_MW_UI_OFF()
  -- ★★★1.75.11 快照与「停采集」**拆开**：
  --   · 采集现在由**全局战斗数据**常驻驱动（Core 每拍取一次 st）⇒ UI 打开时 MW.on 早就 true、
  --     MW.uiStarted 永远是 false ⇒ 老写法（整个函数被 MW.on and MW.uiStarted 包住）会让
  --     「关掉状态UI 自动留快照」**静默失效** —— 我这边就再也读不到真机读数了（1.75.9 的教训）。
  --   · 所以：快照看 MW.uiOpen（UI 开过就打一条，打完清掉 ⇒ 本函数每拍都被调用也不会刷屏）；
  --     停采集仍然只看 uiStarted（条件驱动的采集不许被 UI 关掉）。
  --   · 代价如实说：探针现在等价于常开（14 条候选事件、每条几次表操作）—— 这是「随时可用」的代价。
  if MW.on and MW.n > 0 and MW.uiOpen then
    MW.uiOpen = false -- ★一次性标记：UI 关掉只留一条快照（否则每拍一条，把 120 行读数环冲爆）
    local chans, atk, eng = {}, {}, {}
    for _, ev in ipairs(MW_EVENTS) do
      local c = MW.counts[ev] or 0
      if c > 0 then table.insert(chans, string.format("%s=%d", ev, c)) end
    end
    for nm, r in pairs(MW.atk) do table.insert(atk, string.format("%s×%d", nm, r.n)) end
    for nm, r in pairs(MW.seen) do table.insert(eng, string.format("%s[%s]×%d", nm, tostring(r.dir or "?"), r.n)) end
    table.sort(chans)
    table.sort(atk)
    table.sort(eng)
    pcall(mwOut, string.format("[状态UI快照] 口径=只统计战斗状态 ｜ 候选事件 %d 次 ｜ 有信号的通道：%s", MW.n,
      (table.getn(chans) > 0) and table.concat(chans, " ") or "（一条都没来）"))
    pcall(mwOut, string.format("   围攻过我的：%s ｜ 交战过的：%s",
      (table.getn(atk) > 0) and table.concat(atk, " ") or "（无）",
      (table.getn(eng) > 0) and table.concat(eng, " ") or "（无）"))
    pcall(mwOut, "   ★细节看 /eh go melee 报告（每个事件次数 / 原始样本 / 没认出的原文）")
  end
  if MW.on and MW.uiStarted then pcall(EVAL_MW_STOP) end
end
-- ★★★将来「一键宏条件」的唯一读值口：**只统计战斗状态**（非战斗恒 0）——
--   条件加进来时只准读它，别再去碰 MW.atk（否则「非战斗不统计」就有两处口径，迟早打架）。
-- ★★★1.75.11 懒启动：**条件在用这两个读值口 ⇒ 采集必须开着**。
--   为什么非加不可（真机语义问题）：采集默认**只在状态信息UI 打开期间**进行（「关掉零动作」纪律），
--   而这两个条件是要**驱逐一键宏**的 —— 用户不会为了按宏一直开着状态UI ⇒ 不懒启动的话条件恒 0，
--   功能形同废（而且不报错，最难看出来的那种失败）。
--   ★不带 byUI ⇒ `MW.uiStarted = false`：状态UI 关掉时**不会**把条件驱动的采集停掉（两套开关互不误伤）。
--   ★开销很小：只挂 14 条候选事件（不含 all-events 与聊天截获那种重量级）。
-- ★★★1.75.11 围攻数据的**唯一计算入口**（用户口径：「围攻数量归入战斗数据全局可被使用,不多个地方各自计算」）：
--   一次调用把三个值一起算出来 ⇒ Core 的 UPDATE_STATE 每拍取一次写进状态表（st.mwSiege / mwSiegeNm / mwSiegeEst），
--   **条件（condOne）与两个 UI 一律读 st，谁也不许自己再算一遍**（这就是「不多个地方各自计算」的落点）。
--   返回：终值（取大）, 名字口径数, 估算数
function EVAL_MW_ACTIVE_INFO(win)
  if not MW.on then pcall(EVAL_MW_START) end -- 条件在用 ⇒ 懒启动（见上）
  if MW.inC ~= true then return 0, 0, 0 end
  local w = tonumber(win) or MW_UIWIN
  local nmN = table.getn(EVAL_MW_ATTACKERS(w))
  -- ★★★与旧口径（名字数）**取最大值**（用户原话：「然后兼容之前的方案取最大值」）：
  --   同名怪在名字桶里永远只有 1 个键（3 只「峭壁野猪」= 1）⇒ 估算补灵敏度；两边都低时也绝不被拉低。
  --   ★估算失败（pcall 兜底）就当 0：宁可用旧口径，也不许因为估算出错让条件整个失灵。
  local estN = 0
  local okE, e = pcall(EVAL_MW_EST_N, w)
  if okE and type(e) == "number" then estN = e end
  local fin = (estN > nmN) and estN or nmN
  return fin, nmN, estN
end
-- 旧入口（兼容既有调用点与历史断言）：值 = 同一份计算（★新代码请读 st.mwSiege）
function EVAL_MW_ACTIVE_N(win)
  local fin = EVAL_MW_ACTIVE_INFO(win)
  return fin
end
function EVAL_MW_ENGAGED_N()
  if not MW.on then pcall(EVAL_MW_START) end
  if MW.inC ~= true then return 0 end
  return table.getn(EVAL_MW_ENGAGED(MW_UIENG))
end
-- 状态UI 的两行（纯读：不挂事件、不切目标 —— 副作用只剩 开始/停 采集）
function EVAL_MW_UI_LINES()
  local now = (type(GetTime) == "function") and GetTime() or 0
  mwCombatSync()
  if MW.inC ~= true then
    -- ★用户口径：非战斗状态**不需要统计** ⇒ 一个数都不报（显示破折号，不留旧值冒充现状）
    return "围攻 ——（非战斗·不统计）", "交战 ——（非战斗·不统计）"
  end
  local list = EVAL_MW_ATTACKERS(MW_UIWIN, now)
  -- ★★★1.75.11 显示的数走**全局战斗数据 st**（Core 的 UPDATE_STATE 每拍算一次；用户口径：「不多个地方各自计算」）——
  --   本窗只做展示（名单仍来自桶），st 还没算过时（直接调本函数的测试路径）退回桶计数。
  local stG = (type(EVAL_HELP_STATE) == "table") and EVAL_HELP_STATE or nil
  local nA = (stG and tonumber(stG.mwSiege)) or table.getn(list)
  local shown = {}
  for i = 1, table.getn(list) do
    if i > 3 then break end
    table.insert(shown, list[i].nm)
  end
  local estA = (stG and tonumber(stG.mwSiegeEst)) or 0
  local nmA = (stG and tonumber(stG.mwSiegeNm)) or table.getn(list)
  local lineA = string.format("围攻 %d只（近战窗口%ds%s）%s", nA, MW_UIWIN,
    (estA > nmA) and "·含估算" or "",
    (table.getn(shown) > 0) and (": " .. table.concat(shown, "·")) or "")
  local eng = EVAL_MW_ENGAGED(MW_UIENG, now)
  local nE = (stG and tonumber(stG.mwEngaged)) or table.getn(eng)
  local lineB
  if MW.nearN ~= nil and MW.nearT ~= nil then
    lineB = string.format("交战 %d只（%ds·峰值%d）｜可选中 %d只（%.0fs前·手工）",
      nE, MW_UIENG, MW.peak or 0, MW.nearN, now - MW.nearT)
  else
    lineB = string.format("交战 %d只（%ds·峰值%d）", nE, MW_UIENG, MW.peak or 0)
  end
  return lineA, lineB
end
-- 读值口（断言/离线自证用）
function EVAL_MW_TEST_UI()
  local a, b = EVAL_MW_UI_LINES()
  return { nearN = MW.nearN, nearT = MW.nearT, lineA = a, lineB = b, on = MW.on, inC = MW.inC,
           activeN = EVAL_MW_ACTIVE_N(), engagedN = EVAL_MW_ENGAGED_N() }
end
-- ===== ChatFrame2（战斗记录页）取证（1.75.11；用户：「战斗信息层是ChatFrame2 排查下」）=====
-- ★官方索引核过（doc/api_*.html 1370 条 · [ScrollingMessageFrame (widget)] 共 16 条方法）：
--   AddMessage / AtBottom / AtTop / ScrollDown|Up|ToBottom|ToTop / SetFading / SetFont / SetFontObject /
--   SetJustifyH|V / SetMaxLines / SetTimeVisible / UpdateColorByID
--   ⇒ **没有 GetMessageText / GetNumMessages** ⇒ ChatFrame2 的内容**读不回来**（不能轮询它的行）。
-- ★★所以「战斗信息层」只有三条路，本段全给：
--   ① GetChatWindowMessages(2) = 该窗口**订阅的消息组名**（= 战斗信息类型清单）；
--      组名前缀 CHAT_MSG_ 就是事件名（本仓库既有实证：Toolbox 找含 NOTICE 的组 = CHAT_MSG_CHANNEL_NOTICE）。
--   ② IsEventRegistered(ChatFrame2, "CHAT_MSG_"..组名) ⇒ 反过来问客户端「这事件你注册了吗」——
--      **零副作用、零触发**验证事件名真伪（★返 1 不是 true，判据写 (r==true or r==1)；
--      该函数**不在官方索引里**但实测可用，见 EH_DebugBox.lua:1075/1092）。
--   ③ 截入口 ChatFrame_OnEvent（普通全局函数）⇒ **一网打尽**所有真正进战斗记录页的文本，
--      **不依赖事件名**（1.73.12 实测：frame.AddMessage 写进去不生效，只有这个入口能拦到）。
local MW_CHAT = { orig = nil, wrap = nil, n = 0, noMsg = 0, raw = {} }

-- ①+② 战斗窗口读数（纯只读：一个副作用都没有）
function EVAL_MW_COMBAT_WINDOW(win)
  local w = tonumber(win) or 2
  local n = (type(NUM_CHAT_WINDOWS) == "number" and NUM_CHAT_WINDOWS > 0) and NUM_CHAT_WINDOWS or 7
  mwSay(string.format("⑧ 战斗信息层排查：NUM_CHAT_WINDOWS=%d（目标 = ChatFrame%d）", n, w))
  local fr = rawget(_G, "ChatFrame" .. w)
  if fr == nil then
    mwSay(string.format("   ★ChatFrame%d 现在**不存在**（本客户端聊天窗由 FrameXML 懒建）⇒ 先在游戏里点开一次「战斗记录」页再跑这条", w))
  else
    local okv, vis = pcall(fr.IsVisible, fr)
    mwSay(string.format("   ChatFrame%d：存在 ｜ 可见=%s ｜ IsEventRegistered=%s",
      w, tostring(okv and vis or "?"), (type(fr.IsEventRegistered) == "function") and "有" or "**没有**"))
  end
  if type(GetChatWindowMessages) ~= "function" then
    mwSay("   组名清单：本客户端没有 GetChatWindowMessages ⇒ 这条路走不通（只剩 ③ 截获）")
    return
  end
  local okg, s = pcall(GetChatWindowMessages, w)
  if not okg or type(s) ~= "string" then
    mwSay("   组名清单：读不到（返回类型 = " .. type(s) .. "）")
    return
  end
  local grp = {}
  for part in string.gmatch(s, "[^,%s]+") do table.insert(grp, part) end
  mwSay(string.format("   该窗口订阅消息组 %d 个（事件名 = CHAT_MSG_ + 组名）：", table.getn(grp)))
  local probed, reg = 0, {}
  for i = 1, table.getn(grp) do
    local ev = "CHAT_MSG_" .. grp[i]
    local mark = ""
    if fr ~= nil and type(fr.IsEventRegistered) == "function" then
      local okr, r = pcall(fr.IsEventRegistered, fr, ev)
      probed = probed + 1
      if okr and (r == true or r == 1) then mark = "  ★已注册" table.insert(reg, ev) end
    end
    mwSay(string.format("      %s%s", ev, mark))
  end
  if probed > 0 then
    mwSay(string.format("   ★② IsEventRegistered 探测 %d 条，客户端承认已注册 %d 条（这批事件名就是真的）", probed, table.getn(reg)))
    if table.getn(reg) > 0 then mwSay("      " .. table.concat(reg, " ／ ")) end
  end
  if fr ~= nil and type(fr.IsEventRegistered) == "function" then
    local hit = {}
    for _, ev in ipairs(MW_EVENTS) do
      local okr, r = pcall(fr.IsEventRegistered, fr, ev)
      if okr and (r == true or r == 1) then table.insert(hit, ev) end
    end
    mwSay(string.format("   ★候选通道交叉核对：ChatFrame%d 注册了其中 %d/%d 条%s", w, table.getn(hit), table.getn(MW_EVENTS),
      (table.getn(hit) > 0) and ("：" .. table.concat(hit, " ／ ")) or "（0 条 ⇒ 战斗信息可能不走该窗口，看 ③ 截获）"))
  end
end

-- ③ 截入口：包住全局 ChatFrame_OnEvent（保存原函数 → 包一层 → **读回确认** → 停用时按记账还原）
function EVAL_MW_CHAT_ON()
  if MW_CHAT.orig ~= nil then return false, "already" end
  local cur = rawget(_G, "ChatFrame_OnEvent")
  if type(cur) ~= "function" then return false, "noapi" end
  MW_CHAT.orig = cur
  local function wrapper(a1, ...)
    -- ★取参兼容三形态（照 Toolbox tbCeArgs 的教训）：事件名 = 以 CHAT_MSG 开头那个；文本 = 下一个字符串
    local cand = { a1 }
    local nv = select("#", ...)
    for i = 1, nv do cand[i + 1] = select(i, ...) end
    local ev, txt, snd = nil, nil, nil
    for i = 1, table.getn(cand) do
      local v = cand[i]
      if type(v) == "string" then
        if ev == nil and string.find(v, "^CHAT_MSG") ~= nil then ev = v
        elseif txt == nil then txt = v
        elseif snd == nil then snd = v end
      end
    end
    if txt == nil then
      local g1 = arg1
      if type(g1) == "string" and string.find(g1, "^CHAT_MSG") == nil then txt = g1 end
    end
    MW_CHAT.n = MW_CHAT.n + 1
    if type(txt) == "string" and txt ~= "" then
      pcall(EVAL_MW_CHAT_FEED, ev, txt, snd)
    else
      MW_CHAT.noMsg = MW_CHAT.noMsg + 1 -- ★取不到文本也**如实计数**（不许静默跳过）
    end
    return MW_CHAT.orig(a1, ...)
  end
  rawset(_G, "ChatFrame_OnEvent", wrapper)
  local back = rawget(_G, "ChatFrame_OnEvent")
  if back ~= wrapper then
    rawset(_G, "ChatFrame_OnEvent", cur)
    MW_CHAT.orig = nil
    return false, "writefail" -- ★「写成功 ≠ 写进去生效」（1.73.12 的教训）：读回不是我们的层就当场回退
  end
  MW_CHAT.wrap = wrapper
  return true
end
function EVAL_MW_CHAT_OFF()
  if MW_CHAT.orig == nil then return false, "noton" end
  local cur = rawget(_G, "ChatFrame_OnEvent")
  if cur ~= MW_CHAT.wrap then
    -- ★别人后来又包了一层 ⇒ **不许硬还原**（那会把别人的层打掉）：只清我们的记账并如实说
    MW_CHAT.orig, MW_CHAT.wrap = nil, nil
    return false, "changed"
  end
  rawset(_G, "ChatFrame_OnEvent", MW_CHAT.orig)
  MW_CHAT.orig, MW_CHAT.wrap = nil, nil
  return true
end
-- 喂入一条「经聊天入口进来的文本」（★不依赖事件名：候选通道之外的文本照样参与统计）
function EVAL_MW_CHAT_FEED(ev, txt, snd)
  if type(txt) ~= "string" or txt == "" then return false end
  table.insert(MW_CHAT.raw, string.format("%s ｜ %s", tostring(ev), txt))
  while table.getn(MW_CHAT.raw) > 12 do table.remove(MW_CHAT.raw, 1) end
  if ev ~= nil and MW_ISEV[ev] then return true end -- ★候选事件已由探针帧处理，避免同一条算两次
  local inC = mwCombatSync()
  if inC ~= true then return true end -- ★只统计战斗状态（用户口径）
  local t = (type(GetTime) == "function") and GetTime() or 0
  local nm = EVAL_MELEE_ATTACKER(txt)
  if nm ~= nil then
    local rec = MW.atk[nm]
    if rec == nil then rec = { last = t, n = 0, first = t } MW.atk[nm] = rec end
    -- ★同一条消息可能同时喂给多个聊天窗（FrameXML 逐帧派发）⇒ 0.2s 内的重复不算「又一次命中」
    if (t - (rec.last or 0)) > 0.2 then rec.n = rec.n + 1 end
    rec.last = t
    mwSee(nm, t, "in")
    return true
  end
  local nm2 = mwVictim(txt)
  if nm2 ~= nil then mwSee(nm2, t, "out") end
  return true
end
function EVAL_MW_CHAT_STATE()
  return { on = (MW_CHAT.orig ~= nil), n = MW_CHAT.n, noMsg = MW_CHAT.noMsg,
           rawN = table.getn(MW_CHAT.raw), raw = MW_CHAT.raw }
end
function EVAL_MW_CHAT_RESET()
  MW_CHAT.n, MW_CHAT.noMsg, MW_CHAT.raw = 0, 0, {}
  return true
end
-- ===== 读值口（供断言/离线自证；生产路径一个都不调）=====
function EVAL_MW_TEST_STATE()
  local cnt, nAtk = {}, 0
  for k, v in pairs(MW.counts) do cnt[k] = v end
  for _ in pairs(MW.atk) do nAtk = nAtk + 1 end
  return { on = MW.on, n = MW.n, win = MW.win, t0 = MW.t0, counts = cnt, atkN = nAtk, hitsN = table.getn(MW.hits),
           rawN = table.getn(MW.raw), missN = table.getn(MW.miss), allN = table.getn(mwAllNames()),
           regN = table.getn(MW.reg), badN = table.getn(MW.bad) }
end
function EVAL_MW_TEST_EVENTS() return MW_EVENTS end
function EVAL_MW_TEST_FEED(ev, a1, a2, a3)
  local was = MW.on
  MW.on = true
  local r = EVAL_MW_FEED(ev, a1, a2, a3)
  MW.on = was
  return r
end
function EVAL_MW_TEST_COUNT(win, now) return table.getn(EVAL_MW_ATTACKERS(win, now)) end
function EVAL_MW_TEST_SETWIN(w) MW.win = tonumber(w) or MW.win return MW.win end
function EVAL_MW_TEST_RESET()
  EVAL_MW_STOP()
  MW.counts, MW.atk, MW.raw, MW.miss, MW.seen, MW.allCounts, MW.allSample, MW.kills, MW.n, MW.t0 = {}, {}, {}, {}, {}, {}, {}, 0, 0, nil
  MW.hits = {} -- ★1.75.11 估算的时间环也一起清（否则夹具之间互相污染）
  MW.ivl, MW.ivlN, MW.ivlSeen, MW.ivlLog = {}, {}, {}, {} -- ★档位/更新次数/监测次数/变更日志也清（夹具要能复现「没学过」初态）
  MW.lastSum, MW.peak, MW.uiOpen = nil, 0, false
  return true
end
-- ★1.75.11 估算读值口（返回表：估算/窗口内条数/名字分组数/环内总数）——生产路径一个都不调
function EVAL_MW_TEST_EST(win, now)
  local e, n, g = EVAL_MW_EST_N(win, now)
  return { est = e, n = n, groups = g, hitsN = table.getn(MW.hits) }
end
-- ★1.75.11 自学习读数：某怪名学到的**档位**（nil = 还没学过 ⇒ 用默认档 MW_ESTI）
function EVAL_MW_TEST_IVL(nm) return MW.ivl[nm] end
-- 常量/档位读值口（★断言不许写死数字：窗口、档位、阈值都从这里现取）
function EVAL_MW_TEST_ESTI() return MW_ESTI, MW_UIWIN, MW_ESTCAP end
function EVAL_MW_TEST_WIN() return MW_UIWIN end
function EVAL_MW_TEST_TIERS() return MW_TIERS[1], MW_TIERS[2], MW_TIERS[3] end
function EVAL_MW_TEST_GAPS() return MW_GAP_SINGLE, MW_GAP_MULTI end
function EVAL_MW_TEST_TIEROF(g) return mwTierOf(g) end
-- ★估算**明细**（读值口与生产**同一份实现** EVAL_MW_EST_DETAIL ⇒ 不会出现「读值口复刻逻辑」的假绿）
function EVAL_MW_TEST_DETAIL(win, now)
  local det = EVAL_MW_EST_DETAIL(win, now)
  return det
end
function EVAL_MW_TEST_IVLN(nm) return MW.ivlN[nm] end
function EVAL_MW_TEST_IVLSEEN(nm) return MW.ivlSeen[nm] end
function EVAL_MW_TEST_IVLLOG() return MW.ivlLog end
function EVAL_MW_TEST_LASTSUM() return MW.lastSum end
