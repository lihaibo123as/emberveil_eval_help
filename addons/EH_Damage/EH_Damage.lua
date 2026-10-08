-- ============================================================================
-- EH_Damage · 增强伤害显示（浮动战斗信息）独立子插件
-- ----------------------------------------------------------------------------
-- 血统与边界（调研定案，别回头再踩）：
--   · 动画引擎参考 DamageEx(Nampower 2026-04-16)：动画槽池 + smoothstep 淡入淡出
--     (t*t*(3-2t)) + 暴击三段缩放 + 彩虹弧线(重力衰减) + 防重叠游标。
--   · DamageEx 的「结构化战斗事件 / GUID / 姓名板附着」全部依赖 Nampower 客户端
--     补丁，本客户端(EmberVeil) 一律没有 ⇒ 事件源只能走 SCT 模式
--     （解析 CHAT_MSG_* 文本事件）。
--     ★★姓名板附着**做不到**（2026-10-08 定案，别再重做）：本客户端姓名板是 UE 引擎 widget
--     （AzerothNameplateWidget/…WidgetComponent + HealthPlateComponent；Lua 侧只有 Show/HideNameplates
--     四个开关函数），且无 GUID / 单位位置 / 世界→屏幕 API ⇒ 自绘文字锚不到怪头顶那条浮动姓名板。
--   · 文本模式 = zhCN 尽力而为：**事件名与文本格式不许猜**（铁律 5）⇒ 内置
--     「捕获环」/edmg 捕获 + /edmg 事件 把真机原文落盘，供逐条校准模式表。
-- 客户端配方（项目既有判据）：
--   · OnUpdate 零形参：dt 只能从全局 arg1 取，取不到用 GetTime() 差值推。
--   · 节拍帧宿主 = WorldFrame（开全屏地图会隐藏 UIParent ⇒ 挂 UIParent 节拍停摆）。
--   · 一个模块只许一个节拍帧，挂/摘唯一入口 beatSync()；关断四件事（资源回收 /
--     节拍停止 / 数据重置 / 图层清理）。
--   · 1.12 无销毁帧/纹理 API ⇒ 槽池建一次、只 Show/Hide。
--   · 纯色纹理只有 Interface\Buttons\WHITE8X8 + SetVertexColor 可靠。
--   · 字体链 FZLBJW→FRIZQT→ARIALN 全程 pcall；FontString 不吃鼠标 ⇒ 热区用透明 Button。
-- ============================================================================

local BUILD = "0.2.27"

local D = {}                      -- 命名空间（跨函数共享件全挂这里，控 local 数）
_G["EH_DMG"] = D                  -- 调试/桥接口（子插件独立，不依赖宿主）

-- ----------------------------------------------------------------------------
-- 配置：显示项（与暴雪「浮动战斗信息」面板逐行对齐，def = 参考截图的默认勾选）
-- ----------------------------------------------------------------------------
local ITEMS = {
  { id = "lowHealth",    def = true,  zh = "生命法力过低显示" },
  { id = "auraGain",     def = true,  zh = "效果显示" },
  { id = "auraFade",     def = false, zh = "效果消失显示" },
  { id = "combatState",  def = true,  zh = "战斗状态显示" },
  { id = "misses",       def = false, zh = "躲闪/招架/未击中显示" },
  { id = "mitigation",   def = false, zh = "伤害减免显示" },
  { id = "reputation",   def = false, zh = "声望显示" },
  { id = "reactSpell",   def = false, zh = "反击法术和技能显示" },
  { id = "healerNames",  def = false, zh = "友方治疗者姓名显示" },
  { id = "comboPoints",  def = false, zh = "连击点显示" },
  { id = "energize",     def = false, zh = "能量获取显示" },
  { id = "honor",        def = true,  zh = "荣誉显示" },
  { id = "targetDamage", def = true,  zh = "目标伤害显示" },
  { id = "dotDamage",    def = true,  zh = "周期性伤害" },
  { id = "petDamage",    def = true,  zh = "宠物伤害" },
  -- 附加项（截图之外、DamageEx 血统里有）：受到的伤害
  { id = "incoming",     def = true,  zh = "受到的伤害（附加）" },
}

local DIRS = { "up", "down", "arc", "angleUp", "angleDown", "horiz", "sprinkler", "sine",
               "burst", "burstL", "burstR" }
local DIR_ZH = { up = "向上滚动", down = "向下滚动", arc = "抛物线滚动",
                 angleUp = "斜上抛物", angleDown = "斜下抛物", horiz = "水平散开",
                 sprinkler = "洒水散开", sine = "正弦上升",
                 burst = "极速蹦出", burstL = "极速蹦出·斜左", burstR = "极速蹦出·斜右" }

-- ★★曲线函数库（0.2.23；用户：「模仿官方的伤害展现方式…有哪些曲线函数支持吗?增加专门曲线函数的配置项?」）
--   全部输入 t∈[0,1]、输出进度（绝对时间驱动）；官方 FCT 手感 = **缓出**（快起慢收）；
--   `back` 会**过冲到终点以上再回落**（~1.10 处），就是「蹦」的那一下。
local CURVES = {
  cubic = function(t) local u = 1 - t return 1 - u * u * u end,          -- 缓出立方（官方手感主力）
  quad  = function(t) local u = 1 - t return 1 - u * u end,              -- 缓出平方（稍柔）
  back  = function(t) local c1, c3 = 1.70158, 2.70158 local u = t - 1
            return 1 + c3 * u * u * u + c1 * u * u end,                  -- 回弹过冲（蹦）
  expo  = function(t) if t >= 1 then return 1 end return 1 - 2 ^ (-10 * t) end, -- 指数缓出（起步最暴）
}
local CURVE_ORD = { "cubic", "quad", "back", "expo" }
local CURVE_ZH = { cubic = "缓出立方", quad = "缓出平方", back = "回弹过冲", expo = "指数缓出" }

local function easeCurve(name, t)
  local fn = CURVES[name or "cubic"] or CURVES.cubic
  local ok, v = pcall(fn, t)
  if ok and type(v) == "number" then return v end
  return t
end

local DEF = {
  master = true,
  direction = "angleUp",   -- ★0.2.13 初始默认（用户截图定）：斜上抛物
  curve = "cubic",         -- ★0.2.23 蹦出系方向的曲线函数（缓出立方/缓出平方/回弹过冲/指数缓出）
  clampPct = 30,           -- ★0.2.25 移动上限（占屏 %；行程夹取 + 屏界保险丝，5~60）
  fontTier = 6,            -- 字号档位 1小/2中/3大/4特大/5巨大/6超大（★0.2.13 初始默认 = 超大）
  speed = 180,             -- ★0.2.13 初始默认：180 像素/秒
  duration = 2.0,          -- 秒
  critAnim = 1,            -- 暴击缩放动画开关
  showIcon = true,         -- 技能图标（法术书名→图标缓存，查不到就不画）
  showSpellText = false,   -- 技能名纯文本（默认关；开了 = 「撕裂 9」「次级治疗术 +154」这样带名字）
  posX = 0, posY = -60,    -- 主锚点（屏幕中心偏移，逻辑单位）
  inOffY = -170,           -- 受到伤害行的额外下移
  capture = false,         -- 诊断：捕获未识别的战斗文本进环
}

local say                                   -- ★前向声明：cfgEnsure 的迁移播报用到它（否则绑全局 nil）

local function cfgEnsure()
  local c = rawget(_G, "EH_DAMAGE_CFG")
  if type(c) ~= "table" then c = {} rawset(_G, "EH_DAMAGE_CFG", c) end
  -- ★0.2.0 一次性迁移（**必须先于 DEF 填缺**）：旧 fontSize 像素值 → 档位
  --   （改字号机制已被探针全否，档位字体对象才有效）；只有老存档（有 fontSize 没 fontTier）才折算
  if c.fontTier == nil and c.fontSize ~= nil then
    local px = tonumber(c.fontSize) or 44
    c.fontTier = (px <= 14 and 1) or (px <= 18 and 2) or (px <= 30 and 3) or 4
  end
  for k, v in pairs(DEF) do if c[k] == nil then c[k] = v end end
  for _, it in ipairs(ITEMS) do
    if c["it_" .. it.id] == nil then c["it_" .. it.id] = it.def and true or false end
  end
  if type(c.ring) ~= "table" then c.ring = {} end
  return c
end
local function C() return cfgEnsure() end
local function itemOn(id) return C()["it_" .. id] == true end

-- ----------------------------------------------------------------------------
-- 小工具
-- ----------------------------------------------------------------------------
say = function(m)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  if f and f.AddMessage then pcall(f.AddMessage, f, "|cffff6666[EH伤害]|r " .. tostring(m)) end
end

local TEX_WHITE = "Interface\\Buttons\\WHITE8X8"
local function solid(t, r, g, b, a)
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, TEX_WHITE) end
  pcall(t.SetVertexColor, t, r, g, b, a)
end

local function mkFont(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = pcall(fs.SetFontObject, fs, GameFontHighlight)
  if not ok then pcall(fs.SetFontObject, fs, GameFontNormal) end
  -- 字体链兜底（FZLBJW→FRIZQT→ARIALN，全程 pcall）
  pcall(function()
    if not fs:GetFont() then
      for _, f in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        if pcall(fs.SetFont, fs, f, 12, "") then break end
      end
    end
  end)
  return fs
end

local function smoothstep(t) return t * t * (3 - 2 * t) end   -- DamageEx 同款淡入淡出曲线
local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

-- ----------------------------------------------------------------------------
-- 技能名 → 图标（法术书扫描；GetSpellName/GetSpellTexture 是本客户端在案可用的两条 API）
--   ★只缓存法术书里有的：别人施的（如队友的「恢复」）只有你也会才查得到，查不到不画（绝不画 ? 图）
-- ----------------------------------------------------------------------------
D.iconCache = {}
function D.iconScan()
  local c = {}
  if type(GetSpellName) == "function" and type(GetSpellTexture) == "function" then
    for i = 1, 900 do
      local okN, name = pcall(GetSpellName, i, "spell")
      if not okN or not name then break end
      local okT, tex = pcall(GetSpellTexture, i, "spell")
      if okT and tex and not c[name] then c[name] = tex end
    end
  end
  -- ★★0.2.27 宠物技能图标（用户：「宠物技能击中能显示对应图标吗?」；真机句式
  --   「Cat的撕咬击中雌性草原狮造成8点伤害。」）：
  --   来源① = **宠物动作条** `GetPetActionInfo(i)`（Pet 类 API，本客户端 exe/索引都在案；
  --     vanilla 形状 = name, subtext, texture, isToken, isActive, …）—— 撕咬/低吼这类宠物技能就在这里；
  --     token 形态的名字（PET_ACTION_*）要经 `_G` 转本地化名，转不出就当没有；
  --   来源② = 宠物法术书 `GetSpellName(i, "pet")`（客户端不认这个 bookType 就静默跳过，绝不当成错）。
  --   ★仍然守既有铁律：**查不到就一个图标都不画**（绝不画 ? 图）。
  if type(GetPetActionInfo) == "function" then
    for i = 1, 10 do
      local ok, n, _sub, tex, isToken = pcall(GetPetActionInfo, i)
      if ok and type(n) == "string" and n ~= "" then
        if isToken and type(rawget(_G, n)) == "string" then n = rawget(_G, n) end
        if type(tex) == "string" and tex ~= "" and not c[n] then c[n] = tex end
      end
    end
  end
  if type(GetSpellName) == "function" and type(GetSpellTexture) == "function" then
    for i = 1, 30 do
      local okN, name = pcall(GetSpellName, i, "pet")
      if not okN or type(name) ~= "string" or name == "" then break end
      local okT, tex = pcall(GetSpellTexture, i, "pet")
      if okT and tex and not c[name] then c[name] = tex end
    end
  end
  D.iconCache = c
end
local function iconOf(spellName)
  if not spellName then return nil end
  return D.iconCache and D.iconCache[spellName] or nil
end

-- ★0.2.27 从战斗文本里取「技能名」（配图用；句式 = 2026-10-08 用户真机日志）：
--   自己远程/技能：「你的自动射击击中雌性草原狮造成25点伤害。」「你的 撕裂 使 X 受到了…」
--   宠物技能　　：「Cat的撕咬击中雌性草原狮造成8点伤害。」（Cat = `UnitName("pet")`）
--   宠物普攻　　：「Cat击中雌性草原狮造成15点伤害。」⇒ **提不出技能名**（普攻不给图标，与玩家平砍同一把尺子）
--   玩家平砍　　：「你击中X造成12点伤害。」⇒ 同上
--   ★只用文本给名字、用 `UnitName("pet")` 锚定宠物，**不做任何「猜技能」**；查不到图标就不画。
local function spellFromMsg(m)
  if type(m) ~= "string" or m == "" then return nil end
  local sp = string.match(m, "^你的%s*(.-)%s*击中")        -- 自己的技能 / 远程自动射击
  if sp and sp ~= "" then return sp end
  local pet
  if type(UnitName) == "function" then
    local ok, v = pcall(UnitName, "pet")
    if ok and type(v) == "string" and v ~= "" then pet = v end
  end
  if pet and string.sub(m, 1, string.len(pet) + 1) == pet .. "的" then
    local rest = string.sub(m, string.len(pet) + 2)
    sp = string.match(rest, "^(.-)%s*击中") or string.match(rest, "^(.-)%s*对")
    if sp and sp ~= "" then return sp end
  end
  local who, sp2 = string.match(m, "^(.-)的(.-)%s*击中")    -- 宠物名兜底（拿不到 UnitName("pet") 时）
  if who and who ~= "你" and sp2 and sp2 ~= "" then return sp2 end
  return nil
end
D.spellFromMsg = spellFromMsg

-- ★★字号机制终案（0.2.0；探针 A~K 真机定案）：「改字号」（SetFont/SetTextHeight/帧缩放）
--   在本客户端全无效，但**分档字体对象**（Fonts.xml 自带大小的字体模板）有效，梯度 I<J<K。
--   ⇒ 字号 = 档位制：特大档数字行走 NumberFontNormalHuge（最大，数字优化；可能缺中文字形），
--   中文行走 GameFontNormalHuge（全字形）；其余档两族同名。
D.TIER = {
  { game = "GameFontNormal",       num = "GameFontNormal",       zh = "小" },
  { game = "GameFontNormalLarge",  num = "GameFontNormalLarge",  zh = "中" },
  { game = "GameFontNormalHuge",   num = "GameFontNormalHuge",   zh = "大" },
  { game = "GameFontNormalHuge",   num = "NumberFontNormalHuge", zh = "特大" },
  { game = "SystemFont_Huge3",     num = "SystemFont_Huge3",     zh = "巨大" },
  { game = "SystemFont_Huge4",     num = "SystemFont_Huge4",     zh = "超大" },
}
D.TIER_H = { 18, 24, 32, 48, 64, 84 }      -- 各档行距（防重叠用）
D.ICON_RATIO = 0.45                        -- 图标边长 = 行距 × 系数（0.2.10 起公式化：随档位动态现算，
                                           --   调档/加档自动跟随；要整体大小就调这一个系数，真机可调）
D.ICON_DY = -3                             -- 图标 y 微调（0.2.9；FontString 行盒比字形高 ⇒ 字面重心偏下，
                                           --   图标按行盒中心锚会偏高 ⇒ 下移对齐字面，真机可再调）
local KIND_NUMERIC = { damage = 1, dot = 1, pet = 1, heal = 1, incoming = 1, energize = 1, mitigation = 1 }
local function sizeApply(fs, tier, kind)
  tier = math.max(1, math.min(table.getn(D.TIER), tonumber(tier) or 3))
  -- ★逐级向下回退：某一档的字体对象不存在（本客户端 Fonts.xml 未必全）就落下一档，绝不比配置的档显小
  for t = tier, 1, -1 do
    local tt = D.TIER[t]
    local fo = rawget(_G, KIND_NUMERIC[kind] and tt.num or tt.game)
    if fo then pcall(fs.SetFontObject, fs, fo) return end
  end
  local fo = rawget(_G, "GameFontNormal")
  if fo then pcall(fs.SetFontObject, fs, fo) end
end
local FONT_BASE = 22                    -- 历史常量（暴击系数语义已并入档位，留着防外部引用）
local FONT_CHAIN = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }  -- mkFont 的字体链兜底

-- ----------------------------------------------------------------------------
-- 显示种类（kind）→ 颜色 / 车道 / 文案
--   车道 lane："out" = 主锚点（按 direction 滚动）；"in" = 受到伤害锚点（恒向下）
-- ----------------------------------------------------------------------------
local KIND = {
  damage    = { lane = "out", r = 1.00, g = 1.00, b = 0.30 },
  dot       = { lane = "out", r = 1.00, g = 0.60, b = 0.20 },
  pet       = { lane = "out", r = 0.50, g = 0.90, b = 1.00 },
  miss      = { lane = "out", r = 1.00, g = 0.40, b = 0.40 },
  mitigation= { lane = "out", r = 0.80, g = 0.60, b = 1.00 },
  auraGain  = { lane = "out", r = 0.50, g = 0.80, b = 1.00 },
  auraFade  = { lane = "out", r = 0.70, g = 0.70, b = 0.70 },
  combat    = { lane = "out", r = 1.00, g = 0.85, b = 0.30 },
  react     = { lane = "out", r = 1.00, g = 0.85, b = 0.30 },
  combo     = { lane = "out", r = 1.00, g = 0.50, b = 0.20 },
  honor     = { lane = "out", r = 1.00, g = 0.60, b = 0.80 },
  rep       = { lane = "out", r = 0.60, g = 1.00, b = 0.60 },
  energize  = { lane = "in",  r = 0.40, g = 0.70, b = 1.00 },
  heal      = { lane = "in",  r = 0.30, g = 1.00, b = 0.40 },
  incoming  = { lane = "in",  r = 1.00, g = 0.30, b = 0.30 },
  lowhp     = { lane = "in",  r = 1.00, g = 0.20, b = 0.20 },
  lowmana   = { lane = "in",  r = 0.30, g = 0.50, b = 1.00 },
}

-- kind → 控制它的显示项 id（nil = 不受开关管，总开关直接管）
local KIND_ITEM = {
  damage = "targetDamage", dot = "dotDamage", pet = "petDamage",
  miss = "misses", mitigation = "mitigation",
  auraGain = "auraGain", auraFade = "auraFade",
  combat = "combatState", react = "reactSpell",
  combo = "comboPoints", honor = "honor", rep = "reputation",
  energize = "energize", heal = "healerNames",
  incoming = "incoming", lowhp = "lowHealth", lowmana = "lowHealth",
}

-- ----------------------------------------------------------------------------
-- 动画槽池（1.12 无销毁 API ⇒ 建一次只 Show/Hide；上限有界）
-- ----------------------------------------------------------------------------
local POOL_MAX = 40
D.pool = {}          -- i → { f, fs, active, ... }
D.poolN = 0
local ui                                  -- ★前向声明：tick 在它之前、面板段在它之后（否则 tick 里绑全局 nil）

local function slotAcquire()
  for i = 1, D.poolN do
    if not D.pool[i].active then return D.pool[i] end
  end
  if D.poolN >= POOL_MAX then return nil end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetWidth(260) f:SetHeight(30)
  -- ★带继承模板建 FontString（宿主 uiText 已验证配方），SetFontObject 再双保险
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pcall(fs.SetFontObject, fs, GameFontNormal)
  pcall(fs.SetPoint, fs, "CENTER", f, "CENTER", 0, 0)
  pcall(fs.SetJustifyH, fs, "CENTER")
  local ic = f:CreateTexture(nil, "ARTWORK")          -- 技能图标（锚在文字左缘，不占槽位几何）
  pcall(ic.Hide, ic)
  D.poolN = D.poolN + 1
  D.pool[D.poolN] = { f = f, fs = fs, ic = ic, active = false }
  return D.pool[D.poolN]
end

local function slotRelease(s)
  s.active = false
  pcall(s.f.Hide, s.f)
end

local function slotReleaseAll()
  for i = 1, D.poolN do slotRelease(D.pool[i]) end
end

-- 唯一入口：往屏幕上放一条字
--   kind = KIND 键；text = 文案；crit = 1/0（暴击抬档动画）；spellName = 技能名（配图用，可省）
local function addText(kind, text, crit, spellName)
  if C().master ~= true then return false end
  local kd = KIND[kind]
  if not kd then return false end
  local gate = KIND_ITEM[kind]
  if gate and not itemOn(gate) then return false end

  local s = slotAcquire()
  if not s then return false end

  local c = C()
  local lane = kd.lane
  local x = c.posX or 0
  local y = (lane == "in") and ((c.posY or 0) + (c.inOffY or -170)) or (c.posY or 0)

  -- ★防重叠（0.1.2 重写；真机报障「技能伤害定位越来越高」的根因）：
  --   新字**永远从锚点出发** —— 先到的字已经漂走了，天然不叠；
  --   只有「同一瞬间连发」（AOE 爆发：最近那条还贴着锚点没漂开一个行距）才往上/下摞一格。
  --   旧写法 = 黏性游标只有车道全空才复位 ⇒ 连续战斗时车道永远不空 ⇒ 每条都 +行距 ⇒ 无限爬高。
  local dir = (lane == "in") and "down" or (c.direction or "up")
  local spacing = D.TIER_H[c.fontTier or 3] or 24
  local edge = nil                                   -- 同车道里**离锚点最近**那条的当前 y
  for i = 1, D.poolN do
    local s = D.pool[i]
    if s.active and s.kind and KIND[s.kind] and KIND[s.kind].lane == lane then
      local cy = s.cy or s.y0
      if dir == "down" then
        if (not edge) or cy > edge then edge = cy end   -- down 车道：最靠上 = 离锚点最近
      else
        if (not edge) or cy < edge then edge = cy end   -- up/arc 车道：最靠下 = 离锚点最近
      end
    end
  end
  if edge and math.abs(edge - y) < spacing then
    if dir == "down" then y = edge - spacing else y = edge + spacing end
  end

  s.active = true
  s.kind = kind
  s.crit = (crit == 1 and C().critAnim == 1) and 1 or 0
  -- ★0.2.26b：暴击**文字身份**与「暴击动画」开关**解耦**（用户：「致命一击 没有标红」——
  --   首版把红色挂在 s.crit 上，而它被 critAnim 挡着 ⇒ 关掉暴击动画的人看不到红）：
  --   红不红只由事件文本的「致命」标记决定；字号抬档仍走 s.crit（开关管动画，不管颜色）。
  s.critTxt = (crit == 1) and 1 or 0
  s.t0 = GetTime and GetTime() or 0
  s.dur = c.duration or 2.0
  s.tier = c.fontTier or 3
  s.x0, s.y0 = x, y
  s.cy = y                  -- 出生即当前 y（槽是复用的：不清掉的话会吃到上一条命的残值）
  s.side = (math.random(0, 1) == 1) and 1 or -1
  s.dir = dir

  if C().showSpellText == true and spellName then
    text = tostring(spellName) .. " " .. tostring(text)        -- 技能名纯文本（默认关）
  end
  pcall(s.fs.SetText, s.fs, tostring(text))
  -- ★0.2.26：暴击伤害值变红（用户：「暴击的时候将伤害值变红色」）—— 判定走 critTxt（与动画开关解耦）；
  --   槽是复用的但颜色每次出生都重写 ⇒ 不会串色。
  if s.critTxt == 1 then pcall(s.fs.SetTextColor, s.fs, 1, 0.15, 0.1)
  else pcall(s.fs.SetTextColor, s.fs, kd.r, kd.g, kd.b) end
  sizeApply(s.fs, s.tier, kind)                                -- ★分档字体对象（探针定案，见上）
  s._tier = s.tier
  -- 技能图标（0.2.4）：锚在文字左缘；查不到/没传/关着就不画（绝不画 ? 图）
  local icon = (C().showIcon ~= false) and iconOf(spellName) or nil
  if icon then
    -- 图标边长随字号档位动态现算（行距 × ICON_RATIO；本客户端量不出真实字高，这是最近似的动态口径）
    local sz = math.max(6, math.floor((D.TIER_H[s.tier] or 24) * (D.ICON_RATIO or 0.45) + 0.5))
    pcall(s.ic.SetTexture, s.ic, icon)
    pcall(s.ic.SetWidth, s.ic, sz) pcall(s.ic.SetHeight, s.ic, sz)
    pcall(s.ic.SetPoint, s.ic, "RIGHT", s.fs, "LEFT", -2, D.ICON_DY or 0)
    pcall(s.ic.Show, s.ic)
  else
    pcall(s.ic.Hide, s.ic)
  end
  pcall(s.f.SetAlpha, s.f, 0)
  pcall(s.f.SetPoint, s.f, "CENTER", UIParent, "CENTER", s.x0, s.y0)
  pcall(s.f.Show, s.f)
  return true
end
D.addText = addText

-- ----------------------------------------------------------------------------
-- 动画推进（节拍帧唯一 handler；OnUpdate 零形参 ⇒ dt 走全局 arg1 / GetTime 差值）
-- ----------------------------------------------------------------------------
local function tick()
  if C().master ~= true then return end          -- 双闸之一：节拍函数第一行
  local now = GetTime and GetTime() or 0

  local c = C()
  for i = 1, D.poolN do
    local s = D.pool[i]
    if s.active then
      local t = now - s.t0
      if t >= s.dur then
        slotRelease(s)
      else
        -- 透明度：前 10% smoothstep 淡入，后 50% smoothstep 淡出
        local a
        if t < s.dur * 0.1 then a = smoothstep(t / (s.dur * 0.1))
        elseif t > s.dur * 0.5 then a = 1 - smoothstep((t - s.dur * 0.5) / (s.dur * 0.5))
        else a = 1 end
        -- 位移（绝对时间驱动：t = now - t0，与帧率无关）
        local x, y = s.x0, s.y0
        if s.dir == "down" then
          y = s.y0 - (c.speed or 90) * t
        elseif s.dir == "arc" then
          -- 彩虹弧线（0.2.1 加高：用户「抛物线能否抛高一点再下落」）：
          --   峰值 = vy0²/(4g) ≈ 72px · 0.6s 到顶 · 之后加速下落到锚点以下
          local vy0, g = 240, 200
          y = s.y0 + vy0 * t - g * t * t
          x = s.x0 + 60 * t * s.side
        elseif s.dir == "angleUp" then
          -- 斜上抛物（0.2.2；DamageEx 斜上族）：斜向冲出后缓落
          x = s.x0 + (c.speed or 90) * 0.8 * t * s.side
          y = s.y0 + (c.speed or 90) * 1.4 * t - 120 * t * t
        elseif s.dir == "angleDown" then
          -- 斜下抛物（0.2.2）
          x = s.x0 + (c.speed or 90) * 0.8 * t * s.side
          y = s.y0 - (c.speed or 90) * 1.2 * t - 60 * t * t
        elseif s.dir == "horiz" then
          -- 水平散开（0.2.2；DamageEx 水平族）：左右交替横移 + 微浮沉
          x = s.x0 + (c.speed or 90) * 1.2 * t * s.side
          y = s.y0 + math.sin(t * 3) * 6
        elseif s.dir == "sprinkler" then
          -- 洒水散开（0.2.2；DamageEx 洒水器族）：前 0.3s 快速斜喷，之后缓升微摆
          if t < 0.3 then
            x = s.x0 + 300 * t * s.side
            y = s.y0 + 220 * t
          else
            x = s.x0 + 90 * s.side + math.sin(t * 8) * 10 * s.side
            y = s.y0 + 66 + 30 * (t - 0.3)
          end
        elseif s.dir == "sine" then
          -- 正弦上升（0.2.2；DamageEx OTHER 族的 sin 手法）：直上 + 左右正弦摆
          x = s.x0 + math.sin(t * 6) * 40
          y = s.y0 + (c.speed or 90) * t
        elseif s.dir == "burst" or s.dir == "burstL" or s.dir == "burstR" then
          -- 极速蹦出（0.2.3；用户：「模仿官方的伤害展现方式：中间极速蹦出来、方向朝上」）：
          --   官方 FCT = **缓出曲线**（快起慢收）；`back` 曲线过冲到终点以上再回落 = 「蹦」
          --   ★曲线吃「进度分数」t/dur（0..1），不是秒
          local f = t / s.dur
          local e = easeCurve(c.curve, f)
          local dist = (c.speed or 90) * s.dur * 0.45          -- 总行程（速度×时长定，比例恒定）
          y = s.y0 + dist * e
          if s.dir == "burstL" then x = s.x0 - 70 * f * f
          elseif s.dir == "burstR" then x = s.x0 + 70 * f * f end
        else
          y = s.y0 + (c.speed or 90) * t
        end
        -- ★★★0.2.25 行程上限 + 屏界保险丝（用户：「有没一个参数这是动画移动的上限或者下限占屏幕
        --   百分百?有时候技能都飘到屏幕外面去了」+「A+B」）：
        --   A = 行程夹取：|x−x0| ≤ 屏宽×上限%、|y−y0| ≤ 屏高×上限%（到顶的字**原地停住继续淡出**，
        --       对方向/曲线/速度/时长全兼容 —— 夹取是轨迹算完之后的最后一步）；
        --   B = 屏界夹取：最终坐标恒在屏内（CENTER 锚口径：±宽/2、±高/2）—— 锚点贴边也出不了屏。
        do
          local cPct = tonumber(c.clampPct) or 30
          if cPct < 5 then cPct = 5 elseif cPct > 60 then cPct = 60 end
          local sw, sh = 1024, 768
          if type(UIParent) == "table" then
            local okw, w1 = pcall(UIParent.GetWidth, UIParent)
            if okw and type(w1) == "number" and w1 > 0 then sw = w1 end
            local okh, h1 = pcall(UIParent.GetHeight, UIParent)
            if okh and type(h1) == "number" and h1 > 0 then sh = h1 end
          end
          local mx, my = sw * cPct / 100, sh * cPct / 100
          if x - s.x0 > mx then x = s.x0 + mx elseif s.x0 - x > mx then x = s.x0 - mx end
          if y - s.y0 > my then y = s.y0 + my elseif s.y0 - y > my then y = s.y0 - my end
          local hx, hy = sw / 2, sh / 2
          if x > hx then x = hx elseif x < -hx then x = -hx end
          if y > hy then y = hy elseif y < -hy then y = -hy end
        end
        -- 暴击：0.35s 窗口内抬一档（特大封顶），窗口外落回配置档 —— 档位制下的「缩放」语义
        if s.crit == 1 then
          local wantTier = (t < 0.35) and math.min(table.getn(D.TIER), (s.tier or 3) + 1) or (s.tier or 3)
          if wantTier ~= s._tier then s._tier = wantTier sizeApply(s.fs, wantTier, s.kind) end
        end
        pcall(s.f.SetPoint, s.f, "CENTER", UIParent, "CENTER", x, y)
        pcall(s.f.SetAlpha, s.f, clamp01(a))
        s.cy = y                                        -- 当前 y（防重叠取「离锚点最近一条」要用）
      end
    end
  end

  -- 编辑模式：拖拽推进 + 模拟战斗
  if D.editOn then
    D.editTick(now)
  end
  -- 配置面板拖拽（同一节拍驱动，不再立第二个节拍帧）
  if ui.drag then
    D.uiDragTick()
  end
end
D.tick = tick

-- ----------------------------------------------------------------------------
-- 节拍帧：唯一挂/摘入口（宿主 WorldFrame；一个模块只许一个节拍帧）
-- ----------------------------------------------------------------------------
D.frame = nil
local function beatSync()
  if type(CreateFrame) ~= "function" then return end
  local want = C().master == true
  if not D.frame then
    local parent = rawget(_G, "WorldFrame") or UIParent
    D.frame = CreateFrame("Frame", "EH_DMG_BEAT", parent)
  end
  if want then
    pcall(D.frame.SetScript, D.frame, "OnUpdate", tick)     -- 重挂同一 handler（幂等）
  else
    pcall(D.frame.SetScript, D.frame, "OnUpdate", nil)      -- 真摘，不靠每帧早退
  end
end
D.beatSync = beatSync

-- ----------------------------------------------------------------------------
-- 事件解析（SCT 模式；zhCN 模式表尽力而为，未识别的进捕获环）
--   ★事件名/文本格式不许猜 ⇒ /edmg 捕获 打开后原文落环，/edmg 事件 查看。
-- ----------------------------------------------------------------------------
local RING_MAX = 80                     -- 0.2.8 加大（深度捕获要装一场战斗的负载）
local function ringPush(line)
  local c = C()
  local r = c.ring
  table.insert(r, tostring(line))
  while table.getn(r) > RING_MAX do table.remove(r, 1) end
end

-- ★★★句形去重落环（真机取证口）：把这句战斗文本的「句形」（数字统一换成 `#`）记一次 ——
--   一串同形的伤害只留一行、会话内有界（SHAPE_MAX）⇒ 打完一场就有一份「本客户端到底有哪几种
--   战斗句式」的清单，供模式表逐条校准（真机踩过：不看清真实句式就改匹配规则 = 整车失效）。
--   ★调用点在运行时（事件/命令），赋值在载入期 ⇒ 用 D. 字段而不是 local（不许先引用后声明）。
D.shapeSeen = {}
local SHAPE_MAX = 40
local function shapeCount()
  local n = 0
  for _ in pairs(D.shapeSeen) do n = n + 1 end
  return n
end
D.shapeCount = shapeCount
function D.noteShape(tag, m)
  if type(m) ~= "string" or m == "" then return end
  local shape = string.gsub(m, "%d+", "#")
  local key = tostring(tag) .. "|" .. shape
  if D.shapeSeen[key] then return end
  if shapeCount() >= SHAPE_MAX then return end        -- 有界：满了就不再记（绝不无界增长）
  D.shapeSeen[key] = true
  ringPush("SHAPE " .. key)
end

local function capture(ev, msg)
  if C().capture then ringPush(tostring(ev) .. " | " .. tostring(msg)) end
end

-- 通用提取：伤害数字 + 致命标记 + 目标名（尽力而为的多模式）
local function numOf(msg) local n = string.match(msg, "(%d+)") return tonumber(n) end
local function isCrit(msg) return string.find(msg, "致命") ~= nil end

-- 事件表：ev → 处理器（全部用全局 arg1 原文）
local EVH = {}

-- 光环/展示类去重（0.2.14）：归一键 + 时间窗内同名只出一条（窗口可配）
D.recent = {}
local function dupOk(key, win)
  local now = GetTime and GetTime() or 0
  if D.recent[key] and (now - D.recent[key]) < (win or 1.0) then return false end
  D.recent[key] = now
  return true
end

EVH["CHAT_MSG_COMBAT_SELF_HITS"] = function(m)
  -- ★0.2.27「提不出数字不硬显示」（与 incoming/DOT 早已定下的尺子统一）：非伤害文本
  --   （真机例：「你施放毒蛇钉刺失败：尚未恢复」「Cat的撕咬没有击中雌性草原狮。」）落到这个事件上时
  --   旧写法 `numOf(m) or m` 会把**整句原文当伤害值画在屏幕上** ⇒ 现在一律不画、只记句形供校准。
  local n = numOf(m)
  if not n then D.noteShape("hit-nonum", m) return end
  addText("damage", n, isCrit(m) and 1 or 0, spellFromMsg(m))
end
EVH["CHAT_MSG_SPELL_SELF_DAMAGE"] = function(m)
  local n = numOf(m)
  if not n then D.noteShape("spell-nonum", m) return end
  -- 技能名（配图用）：真机句式「你的 撕裂 使 噬骨者 受到了 9 点物理伤害。」「你的自动射击击中X造成25点伤害。」
  local sp = string.match(m, "^你的%s*(.-)%s*使") or spellFromMsg(m)
  addText("damage", n, isCrit(m) and 1 or 0, sp)
  -- 减免后缀（……点被抵抗/吸收/格挡）：减免显示开着时补一条
  local abs = string.match(m, "（(%d+)点被(.+)）") or string.match(m, "(%d+)点被抵抗")
  if abs and itemOn("mitigation") then addText("mitigation", "-" .. abs .. " 减免", 0) end
end
EVH["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"] = function(m)
  -- ★★★0.2.24 归属门（真机报障：「某些其他骑士的奉献神圣伤害会在牧师的伤害界面上显示?」）：
  --   这族事件的「目标类别」是敌对玩家/生物，**来源不限**（vanilla 语义：附近任何人的 DoT 跳在
  --   怪身上都会进战斗日志）⇒ 别人的奉献（范围周期神圣伤害）会显示成我们的 dot ⇒ 只认自己的：
  --   真机已校准句式一律「你的 …」开头（「你的 撕裂 使 X 受到了 9 点伤害。」）；不是就跳过+落环。
  if string.sub(m, 1, 3) ~= "你" then capture("DOT-OTHER", m) return end
  local n = numOf(m)
  if not n then capture("DOT-NONUM", m) return end   -- 0.2.4：提不出数字不硬显示（同 incoming 的尺子）
  local sp = string.match(m, "^你的%s*(.-)%s*使") or string.match(m, "^你的%s*(.-)%s*击中")
          or string.match(m, "^你的%s*(.-)%s*对")
  addText("dot", n, 0, sp)
end
EVH["CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"] = EVH["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"]

EVH["CHAT_MSG_COMBAT_SELF_MISSES"] = function(m)
  local w = string.find(m, "躲闪") and "躲闪" or string.find(m, "招架") and "招架"
         or string.find(m, "未击中") and "未击中" or string.find(m, "抵抗") and "抵抗" or "未命中"
  addText("miss", w, 0)
end
EVH["CHAT_MSG_SPELL_SELF_MISSES"] = EVH["CHAT_MSG_COMBAT_SELF_MISSES"]

-- ★★0.2.27 宠物伤害（用户真机反馈：「宠物伤害显示匹配应该还有问题」）：
--   **提不出数字不硬显示**（旧写法 `numOf(m) or m` 会把整句原文当伤害值画在屏幕上 ——
--   与 incoming/DOT 早已定下的尺子不一致，宠物句式恰好是「未校准」那一套 ⇒ 必然踩中）；
--   句形落环走 `SHAPE pet-nonum|…`，一场仗下来就能看到宠物伤害的真实句式。
local function petHit(m)
  local n = numOf(m)
  if not n then D.noteShape("pet-nonum", m) return end
  addText("pet", n, isCrit(m) and 1 or 0, spellFromMsg(m))
end
EVH["CHAT_MSG_COMBAT_PET_HITS"] = petHit
EVH["CHAT_MSG_SPELL_PET_DAMAGE"] = petHit
EVH["CHAT_MSG_COMBAT_PET_MISSES"] = function(m) EVH["CHAT_MSG_COMBAT_SELF_MISSES"](m) end

-- 能量类型 token → 中文（真机句式里是未翻译 token：RAGE_POINTS 等；查不到就原文显示）
local POWER_ZH = { RAGE_POINTS = "怒气", MANA = "法力", ENERGY = "能量", FOCUS = "集中值", HAPPINESS = "快乐" }

-- 治疗（友方治疗者姓名）：这族事件同时会报「施加 buff」类**无数字**文本（如「X 对你施放了 恢复。」）
--   —— 真机实锤：无数字硬显示 ⇒ 屏上一个「+?」⇒ 没有数字一律不当治疗跳（buff 施加由效果显示管）
--   ★本客户端真机句式（0.2.3 战斗日志截图）：「你因 losol 的 恢复 而获得了 40 点生命值。」
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]  = function(m)
  local n = string.match(m, "获得%s*(%d+)%s*点") or string.match(m, "治疗你%s*(%d+)%s*点")
         or string.match(m, "恢复%s*(%d+)%s*点") or string.match(m, "(%d+)%s*点")
  if not n then capture("HEAL-NONUM", m) return end
  -- ★真机文本「的」前后带空格 ⇒ 提取名字必须把空白一起剥掉；技能名配图（你因 X 的 **恢复** 而…）
  local who = string.match(m, "^你因%s*(.-)%s*的") or string.match(m, "^%s*(.-)%s*的")
  local sp = string.match(m, "^你因%s*.-的%s*(.-)%s*而") or string.match(m, "^.-的%s*(.-)%s*治疗你")
          or string.match(m, "^.-的%s*(.-)%s*使")
  addText("heal", "+" .. n .. (who and (" [" .. who .. "]") or ""), 0, sp)
end
EVH["CHAT_MSG_SPELL_PARTY_BUFF"]         = EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]
EVH["CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF"] = EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]

-- 自我治疗（0.2.5；真机句式「你的 次级治疗术 治疗了你 154 点生命值。」
--   「你的 次级治疗术 对你造成极效治疗，恢复了 247 点生命值。」）
EVH["CHAT_MSG_SPELL_SELF_BUFF"] = function(m)
  local sp = string.match(m, "^你的%s*(.-)%s*治疗") or string.match(m, "^你的%s*(.-)%s*对你造成")
  local n = string.match(m, "治疗了你%s*(%d+)%s*点") or string.match(m, "恢复了%s*(%d+)%s*点")
         or string.match(m, "(%d+)%s*点")
  if not n then capture("SELFHEAL-NONUM", m) return end
  addText("heal", "+" .. n, 0, sp)
end

EVH["CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"] = function(m)
  -- ★本客户端真机句式（0.2.3 截图）：「你从 怒不可遏 获得了 1 点 RAGE_POINTS。」（能量获取）
  --   ★Lua 模式的 `?` 按字节作用 ⇒ 「了?」会切掉半个汉字（项目老坑）⇒ 两条模式分别试
  local n, pw = string.match(m, "^你从.-获得%s*(%d+)%s*点(.-)。")
  if not n then n, pw = string.match(m, "^你从.-获得了%s*(%d+)%s*点(.-)。") end
  if not n then n, pw = string.match(m, "^你获得(%d+)点(.+)") end
  if not n then n, pw = string.match(m, "^你获得了(%d+)点(.+)") end
  if n then
    pw = string.gsub(tostring(pw or ""), "^%s*(.-)%s*$", "%1")   -- 真机文本空格多 ⇒ 剥净再映射
    pw = POWER_ZH[pw] or pw
    local src = string.match(m, "^你从%s*(.-)%s*获得")            -- 来源名（天赋/光环名，配图用）
    addText("energize", "+" .. n .. " " .. pw, 0, src)
    return
  end
  -- ★模式次序（0.2.14 修）：先整句（「…获得了 X 。」两种主语），再「效果」形 ——
  --   `(.-)效果` 按首个「效果」截会得到「恢复的」（与整句形「恢复的效果」归一不到一起 = 去重失效）
  local a = string.match(m, "^你获得了(.+)。") or string.match(m, "^你从.-获得了(.+)。")
         or string.match(m, "^你获得(.+)效果") or string.match(m, "^你从.-获得了(.+)效果")
  -- ★0.2.14 去重（真机截图：同一次「恢复」出了两条）—— 本客户端对同一次 buff 施加会发
  --   两种句式（「你从 X 获得了恢复效果。」+「你获得了恢复的效果。」）⇒ 归一名字、1s 窗内同名只出一条
  if a then
    local key = string.gsub(a, "的效果$", "")
    key = string.gsub(key, "效果$", "")
    if not dupOk("ag:" .. key, 1.0) then return end
    addText("auraGain", "+ " .. a, 0, a)
  else capture("PERIODIC_SELF_BUFFS?", m) end
end

EVH["CHAT_MSG_SPELL_AURA_GONE_SELF"] = function(m)
  local a = string.match(m, "^(.+)效果从你身上消失") or string.match(m, "^(.+)消失了")
  if a then
    local key = string.gsub(a, "的效果$", "")
    key = string.gsub(key, "效果$", "")
    if not dupOk("af:" .. key, 1.0) then return end
  end
  addText("auraFade", "- " .. (a or m), 0, a)
end

EVH["CHAT_MSG_COMBAT_HONOR_GAIN"] = function(m)
  local n = numOf(m)
  addText("honor", n and ("+" .. n .. " 荣誉") or m, 0)
end

-- 受到的伤害（附加项 incoming；0.2.3 补上 —— 真机句式「噬骨者击中你造成32点伤害。」）：
--   事件名按 vanilla 候选注册（pcall 逐个试，不存在的被客户端静默忽略；哪个真发火捕获环说话）
--   ★0.2.4 真机实锤：这类事件的 arg1 负载可能是**裸名字**（不是整句文本）⇒ 提不出数字
--     一律不显示（否则屏上出「-losol」这种垃圾），原文落环待校准（与治疗的「+?」同一把尺子）
--   ★★0.2.27 归属门：这条必须**是打在我身上**的 —— 真机例「雌性草原狮击中Cat造成8点伤害。」
--     是**宠物挨打**（2026-10-08 用户日志），旧写法会把它显示成红色「-8」当作我受到的伤害。
--     判据 = 整句里必须出现「你」（vanilla zhCN 的自我受击句式一律含「你」）。
local function inHit(m)
  if type(m) ~= "string" or not string.find(m, "你", 1, true) then
    D.noteShape("in-other", m) return
  end
  local n = numOf(m)
  if not n then capture("INCOMING-NONUM", m) return end
  addText("incoming", "-" .. n, isCrit(m) and 1 or 0)
end
local function inMiss(m)
  if type(m) ~= "string" or not string.find(m, "你", 1, true) then
    D.noteShape("inmiss-other", m) return
  end
  local w = string.find(m, "躲闪") and "躲闪" or string.find(m, "招架") and "招架"
         or string.find(m, "未击中") and "未击中" or string.find(m, "抵抗") and "抵抗" or "未命中"
  addText("incoming", w, 0)
end
EVH["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"]   = inHit
EVH["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"]       = inHit
EVH["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"]   = inHit
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"]      = inHit
EVH["CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"]  = inMiss
EVH["CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"]     = inMiss
EVH["CHAT_MSG_COMBAT_FACTION_CHANGE"] = function(m)
  local fac, n = string.match(m, "你在(.+)中的声望.+(%d+)点")
  addText("rep", "+" .. (n or "?") .. " 声望" .. (fac and ("·" .. fac) or ""), 0)
end

EVH["PLAYER_REGEN_DISABLED"] = function() addText("combat", "进入战斗", 0) end
EVH["PLAYER_REGEN_ENABLED"]  = function() addText("combat", "离开战斗", 0) end
EVH["SPELLS_CHANGED"]        = function() D.iconScan() end
-- ★0.2.27 宠物技能图标：宠物换了/动作条变了就重扫图标缓存（不然新学的技能要 /reload 才有图）
EVH["PET_BAR_UPDATE"]        = function() D.iconScan() end
EVH["UNIT_PET"]              = function(u) if u == "pet" or u == nil then D.iconScan() end end

EVH["UNIT_COMBO_POINTS"] = function(u)
  if u ~= "player" then return end
  local n
  if type(GetComboPoints) == "function" then
    local ok, v = pcall(GetComboPoints, "player", "target")
    if ok and type(v) == "number" then n = v
    else local ok2, v2 = pcall(GetComboPoints, "target") if ok2 then n = tonumber(v2) end end
  end
  if n and n > 0 then addText("combo", "连击点 ×" .. n, 0) end
end

-- 生命/法力过低（跨阈值一次，恢复后重新武装）
D.lowArmed = { hp = true, mana = true }
EVH["UNIT_HEALTH"] = function(u)
  if u ~= "player" or not itemOn("lowHealth") then return end
  local h, hm = UnitHealth("player"), UnitHealthMax("player")
  if hm and hm > 0 then
    local p = h / hm
    if p < 0.20 and D.lowArmed.hp then D.lowArmed.hp = false addText("lowhp", "生命值过低！", 1)
    elseif p >= 0.35 then D.lowArmed.hp = true end
  end
end
EVH["UNIT_MANA"] = function(u)
  if u ~= "player" or not itemOn("lowHealth") then return end
  if type(UnitPowerType) == "function" and UnitPowerType("player") ~= 0 then return end  -- 只报蓝条职业
  local v, vm = UnitMana("player"), UnitManaMax("player")
  if vm and vm > 0 then
    local p = v / vm
    if p < 0.20 and D.lowArmed.mana then D.lowArmed.mana = false addText("lowmana", "法力值过低！", 0)
    elseif p >= 0.35 then D.lowArmed.mana = true end
  end
end

-- 事件注册清单（注册本身 pcall 逐个试；不存在的事件名客户端会静默忽略或报错，都兜住）
local EVENTS = {
  "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
  "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_MISSES",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_COMBAT_PET_MISSES", "CHAT_MSG_SPELL_PET_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_SELF_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_AURA_GONE_SELF",
  "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
  "PET_BAR_UPDATE", "UNIT_PET",                       -- ★0.2.27 宠物技能图标重扫
  "UNIT_COMBO_POINTS", "UNIT_HEALTH", "UNIT_MANA",
}

D.evFrame = nil
local function eventSync()
  if type(CreateFrame) ~= "function" then return end
  local want = C().master == true
  if not D.evFrame then
    D.evFrame = CreateFrame("Frame", "EH_DMG_EVENT")
    D.evFrame:SetScript("OnEvent", function()
      local ev = rawget(_G, "event")
      local m = rawget(_G, "arg1")
      -- ★0.2.4 深度捕获：开着捕获时把**全部事件原始负载**（event + arg1/2/3）落环 ——
      --   本客户端事件负载与聊天文本未必同构（真机实锤：incoming 的 arg1 可能是裸名字），
      --   校准解析必须看负载原文，不看聊天框。★0.2.8：UNIT_* 不记（每帧都发，会刷爆环）。
      if C().capture and ev and string.sub(ev, 1, 5) ~= "UNIT_" then
        ringPush("RAW " .. tostring(ev) .. " |1=" .. tostring(m) ..
          " |2=" .. tostring(rawget(_G, "arg2")) .. " |3=" .. tostring(rawget(_G, "arg3")))
      end
      local h = ev and EVH[ev] or nil
      if h then
        local ok, err = pcall(h, m)
        if not ok then ringPush("ERR " .. tostring(ev) .. " | " .. tostring(err)) end
      elseif ev and string.sub(ev, 1, 9) == "CHAT_MSG_" then
        capture(ev, m)                       -- 未识别的战斗文本：捕获开着就落环
      end
    end)
  end
  for _, ev in ipairs(EVENTS) do
    if want then pcall(D.evFrame.RegisterEvent, D.evFrame, ev)
    else pcall(D.evFrame.UnregisterEvent, D.evFrame, ev) end
  end
end

-- ----------------------------------------------------------------------------
-- 编辑模式：拖拽锚点 + 模拟战斗（实时预览参数效果）
-- ----------------------------------------------------------------------------
D.editOn = false
D.editUI = nil
D.simOn = false
D.simNext = 0
D.simIdx = 0

local SIM_SEQ = {
  { kind = "damage",    fn = function() return tostring(math.random(80, 900)) end, crit = 0 },
  { kind = "damage",    fn = function() return tostring(math.random(400, 1600)) end, crit = 1 },
  { kind = "dot",       fn = function() return tostring(math.random(20, 120)) .. " ·持续" end, crit = 0 },
  { kind = "pet",       fn = function() return tostring(math.random(30, 220)) .. " ·宠物" end, crit = 0 },
  { kind = "heal",      fn = function() return "+" .. math.random(100, 600) .. " [治疗者甲]" end, crit = 0 },
  { kind = "incoming",  fn = function() return "-" .. math.random(50, 400) end, crit = 0 },
  { kind = "auraGain",  fn = function() return "+ 奥术智慧" end, crit = 0 },
  { kind = "auraFade",  fn = function() return "- 奥术智慧" end, crit = 0 },
  { kind = "combat",    fn = function() return (D.simIdx % 2 == 0) and "进入战斗" or "离开战斗" end, crit = 0 },
  { kind = "miss",      fn = function()
      local w = { "躲闪", "招架", "未击中" }
      return w[math.random(1, 3)]
    end, crit =0 },
  { kind = "mitigation",fn = function() return "-" .. math.random(10, 90) .. " 减免" end, crit = 0 },
  { kind = "energize",  fn = function() return "+" .. math.random(5, 40) .. " 法力" end, crit = 0 },
  { kind = "honor",     fn = function() return "+" .. math.random(10, 200) .. " 荣誉" end, crit = 0 },
  { kind = "combo",     fn = function() return "连击点 ×" .. math.random(1, 5) end, crit = 0 },
  { kind = "rep",       fn = function() return "+" .. math.random(5, 25) .. " 声望·暴风城" end, crit = 0 },
  { kind = "lowhp",     fn = function() return "生命值过低！" end, crit = 1 },
}

local function simFire()
  -- 只放「当前勾选」的种类：未勾的跳过（连跳一圈还没勾的就静默一轮）
  for _ = 1, table.getn(SIM_SEQ) do
    D.simIdx = (D.simIdx % table.getn(SIM_SEQ)) + 1
    local e = SIM_SEQ[D.simIdx]
    local gate = KIND_ITEM[e.kind]
    if not gate or itemOn(gate) then
      addText(e.kind, e.fn(), e.crit)
      return
    end
  end
end

local function editEnsureUI()
  if D.editUI then return true end
  if type(CreateFrame) ~= "function" then return false end
  local f = CreateFrame("Button", "EH_DMG_ANCHOR", UIParent)
  f:SetWidth(170) f:SetHeight(30)
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, true) end
  pcall(f.RegisterForDrag, f, "LeftButton")
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0) bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0.10, 0.08, 0.04, 0.85)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = f:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", f, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", f, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = f:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, f, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, f, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end
  local fs = mkFont(f)
  pcall(fs.SetPoint, fs, "CENTER", f, "CENTER", 0, 0)
  pcall(fs.SetText, fs, "伤害锚点（拖动）")
  pcall(fs.SetTextColor, fs, 0.95, 0.82, 0.35)
  -- 拖拽三件套（项目已验证）：OnMouseDown 起 + 节拍里 GetCursorPosition 现算 + 鼠标键状态收尾
  f:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    D.drag = { sx = cx, sy = cy, bx = C().posX or 0, by = C().posY or 0 }
  end)
  f:SetScript("OnMouseUp", function() D.drag = nil end)
  D.editUI = { f = f, fs = fs }
  return true
end

local function editPlace()
  if not D.editUI then return end
  local c = C()
  pcall(D.editUI.f.SetPoint, D.editUI.f, "CENTER", UIParent, "CENTER", c.posX or 0, c.posY or 0)
end

local function editSet(on)
  D.editOn = on and true or false
  if D.editOn then
    if not editEnsureUI() then say("编辑模式不可用（建不出控件）") D.editOn = false return end
    editPlace()
    pcall(D.editUI.f.Show, D.editUI.f)
    say("编辑模式：开 —— 拖动金色锚点定位；「模拟战斗」可实时预览参数效果")
  else
    if D.editUI then pcall(D.editUI.f.Hide, D.editUI.f) end
    D.drag = nil
    say("编辑模式：关")
  end
end
D.editSet = editSet

-- 编辑模式的每拍（由 tick 在 editOn 时调用）
function D.editTick(now)
  -- 拖拽推进：读光标 + 键状态收尾（GetCursorPosition 与 SetPoint 同单位是本客户端既有口径，真机复核）
  if D.drag then
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
      D.drag = nil
    else
      local cx, cy = GetCursorPosition()
      local c = C()
      c.posX = D.drag.bx + (cx - D.drag.sx)
      c.posY = D.drag.by + (cy - D.drag.sy)
      editPlace()
    end
  end
  -- 模拟战斗（0.2.12 加密：0.45s 一拍、每拍两条 —— 用户「频率再快一点、信息密集一点」）
  if D.simOn and now >= D.simNext then
    D.simNext = now + 0.45
    simFire()
    simFire()
  end
end

-- ----------------------------------------------------------------------------
-- 配置面板（/edmg ui）：15+1 显示项勾选 + 参数行 + 编辑模式/模拟战斗入口
-- ----------------------------------------------------------------------------
ui = { built = false, px = 0, py = 0 }    -- px/py = 面板拖出的位置（会话态，不落存档）

local function uiSolidBtn(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  local bb = b:CreateTexture(nil, "BACKGROUND")
  bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  solid(bb, 0.22, 0.17, 0.07, 1)
  local t = mkFont(b)
  pcall(t.SetPoint, t, "CENTER", b, "CENTER", 0, 0)
  pcall(t.SetText, t, label)
  b:SetScript("OnClick", onClick)
  return b, t, bb
end

local function uiRefresh()
  if not ui.built then return end
  local c = C()
  for _, row in ipairs(ui.itemRows) do
    if row.get() then pcall(row.mk.Show, row.mk) else pcall(row.mk.Hide, row.mk) end
  end
  pcall(ui.dirText.SetText, ui.dirText, DIR_ZH[c.direction] or c.direction)
  pcall(ui.sizeText.SetText, ui.sizeText, (D.TIER[c.fontTier or 3].zh) .. "（" .. tostring(c.fontTier or 3) .. "/" .. table.getn(D.TIER) .. "）")
  pcall(ui.speedText.SetText, ui.speedText, tostring(c.speed))
  pcall(ui.durText.SetText, ui.durText, string.format("%.1f", c.duration or 2.0))
  pcall(ui.curveText.SetText, ui.curveText, CURVE_ZH[c.curve or "cubic"] or tostring(c.curve))
  pcall(ui.clampText.SetText, ui.clampText, tostring(tonumber(c.clampPct) or 30) .. "%")
  pcall(ui.editText.SetText, ui.editText, D.editOn and "编辑模式：开" or "编辑模式：关")
  pcall(ui.simText.SetText, ui.simText, D.simOn and "模拟战斗：开" or "模拟战斗：关")
  pcall(ui.masterMk.Show, ui.masterMk)
  if c.master ~= true then pcall(ui.masterMk.Hide, ui.masterMk) end
end

local function uiBuild()
  if ui.built then return true end
  if type(CreateFrame) ~= "function" then return false end
  local W, H = 470, 424                  -- ★0.2.23 高度重算：表头+总开关 62 + 勾选 10 行 220 + 参数 3 行 86 + 按钮/备注 ~56
  local root = CreateFrame("Frame", "EH_DMG_UI", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", ui.px, ui.py)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 90)
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0) bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0.05, 0.04, 0.03, 0.96)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, root, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, root, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end

  local title = mkFont(root)
  pcall(title.SetPoint, title, "TOP", root, "TOP", 0, -10)
  pcall(title.SetText, title, "增强伤害显示（EH_Damage v" .. BUILD .. "）")
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)

  -- ★标题栏 = 面板拖拽柄（已验证三件套：OnMouseDown 起 + 节拍里 GetCursorPosition 现算 + 键状态收尾；
  --   绝不 SetMovable/StartMoving —— 那套只有一条收尾路，柄一丢捕获窗口就黏在光标上）
  local dh = CreateFrame("Button", nil, root)
  dh:SetWidth(W - 24) dh:SetHeight(24)
  dh:SetPoint("TOP", root, "TOP", 0, -2)
  if type(dh.EnableMouse) == "function" then pcall(dh.EnableMouse, dh, true) end
  if type(dh.SetFrameLevel) == "function" then pcall(dh.SetFrameLevel, dh, 95) end
  dh:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    ui.drag = { sx = cx, sy = cy, bx = ui.px, by = ui.py }
  end)
  dh:SetScript("OnMouseUp", function() ui.drag = nil end)
  ui.dragHandle = dh

  -- 总开关
  local mchk = CreateFrame("CheckButton", nil, root)
  mchk:SetWidth(16) mchk:SetHeight(16)
  mchk:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -34)
  if type(mchk.EnableMouse) == "function" then pcall(mchk.EnableMouse, mchk, true) end
  local mo = mchk:CreateTexture(nil, "BACKGROUND")
  mo:SetPoint("TOPLEFT", mchk, "TOPLEFT", 0, 0) mo:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", 0, 0)
  solid(mo, 0.85, 0.70, 0.20, 1)
  local mb = mchk:CreateTexture(nil, "ARTWORK")
  mb:SetPoint("TOPLEFT", mchk, "TOPLEFT", 1, -1) mb:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", -1, 1)
  solid(mb, 0.10, 0.09, 0.06, 1)
  local mmk = mchk:CreateTexture(nil, "OVERLAY")
  mmk:SetPoint("TOPLEFT", mchk, "TOPLEFT", 3, -3) mmk:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", -3, 3)
  solid(mmk, 0.95, 0.80, 0.25, 1)
  mchk:SetScript("OnClick", function()
    C().master = not (C().master == true)
    if C().master then eventSync() else slotReleaseAll() end
    beatSync()
    uiRefresh()
    say("总开关：" .. (C().master and "开" or "关（已收层、停节拍、摘事件）"))
  end)
  local mlabel = mkFont(root)
  pcall(mlabel.SetPoint, mlabel, "LEFT", mchk, "RIGHT", 6, 0)
  pcall(mlabel.SetText, mlabel, "总开关（关掉 = 收层 + 停节拍 + 摘事件）")
  ui.masterMk = mmk

  -- 勾选网格（0.2.6 重排：显示项 + 开关类参数全收进网格，填掉左列空档 —— 用户定）
  ui.itemRows = {}
  local function mkItem(zh, get, set, x, y)
    local chk = CreateFrame("CheckButton", nil, root)
    chk:SetWidth(14) chk:SetHeight(14)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
    if type(chk.EnableMouse) == "function" then pcall(chk.EnableMouse, chk, true) end
    local o = chk:CreateTexture(nil, "BACKGROUND")
    o:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0) o:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    solid(o, 0.85, 0.70, 0.20, 1)
    local b2 = chk:CreateTexture(nil, "ARTWORK")
    b2:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1) b2:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
    solid(b2, 0.10, 0.09, 0.06, 1)
    local mk = chk:CreateTexture(nil, "OVERLAY")
    mk:SetPoint("TOPLEFT", chk, "TOPLEFT", 2, -2) mk:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -2, 2)
    solid(mk, 0.95, 0.80, 0.25, 1)
    chk:SetScript("OnClick", function() set(not get()) uiRefresh() end)
    local lb = mkFont(root)
    pcall(lb.SetPoint, lb, "LEFT", chk, "RIGHT", 5, 0)
    pcall(lb.SetText, lb, zh)
    pcall(lb.SetTextColor, lb, 0.92, 0.88, 0.80)
    table.insert(ui.itemRows, { get = get, mk = mk })
  end
  local TOGGLES = {}
  for _, it in ipairs(ITEMS) do
    local id = it.id
    table.insert(TOGGLES, { zh = it.zh,
      get = function() return itemOn(id) end,
      set = function(v) C()["it_" .. id] = v and true or false end })
  end
  table.insert(TOGGLES, { zh = "暴击缩放动画",
    get = function() return C().critAnim == 1 end, set = function(v) C().critAnim = v and 1 or 0 end })
  table.insert(TOGGLES, { zh = "技能图标",
    get = function() return C().showIcon ~= false end, set = function(v) C().showIcon = v and true or false end })
  table.insert(TOGGLES, { zh = "技能名文本",
    get = function() return C().showSpellText == true end, set = function(v) C().showSpellText = v and true or false end })
  local GRID_ROWS = 10
  local y0 = -62
  for i, tg in ipairs(TOGGLES) do
    local col = (i <= GRID_ROWS) and 0 or 1
    local row = (i <= GRID_ROWS) and i or (i - GRID_ROWS)
    mkItem(tg.zh, tg.get, tg.set, 18 + col * 232, y0 - (row - 1) * 22)
  end

  -- 数值/多选参数（0.2.6 重排：2×2 两列 —— 用户定）
  local py = y0 - GRID_ROWS * 22 - 14
  local function paramCell(label, x, y, getSet)
    local lb = mkFont(root)
    pcall(lb.SetPoint, lb, "TOPLEFT", root, "TOPLEFT", x, y)
    pcall(lb.SetTextColor, lb, 0.95, 0.80, 0.30)
    pcall(lb.SetText, lb, label)
    local bm = uiSolidBtn(root, "-", 22, 18, function() getSet(-1) uiRefresh() end)
    bm:SetPoint("TOPLEFT", root, "TOPLEFT", x + 78, y + 2)
    local val = mkFont(root)
    pcall(val.SetPoint, val, "TOPLEFT", root, "TOPLEFT", x + 106, y)
    pcall(val.SetWidth, val, 66)
    pcall(val.SetJustifyH, val, "LEFT")
    local bp = uiSolidBtn(root, "+", 22, 18, function() getSet(1) uiRefresh() end)
    bp:SetPoint("TOPLEFT", root, "TOPLEFT", x + 176, y + 2)
    return val
  end
  local PX1, PX2 = 18, 250
  -- ★循环类参数（方向/档位）：`+` 正向、`-` 反向（0.2.12；旧写法两颗都正滚 = 用户眼里的「调节异常」）
  ui.dirText = paramCell("滚动方向", PX1, py, function(d)
    local c = C()
    local i = 1
    for k, v in ipairs(DIRS) do if v == c.direction then i = k break end end
    local n = table.getn(DIRS)
    c.direction = DIRS[((i - 1 + (d or 1)) % n) + 1]
  end)
  ui.sizeText = paramCell("字号档位", PX2, py, function(d)
    local c = C()
    local n = table.getn(D.TIER)
    c.fontTier = (((c.fontTier or 3) - 1 + (d or 1)) % n) + 1
  end)
  ui.speedText = paramCell("速度", PX1, py - 24, function(d) local c = C() c.speed = math.max(20, math.min(400, (c.speed or 90) + d * 10)) end)
  ui.durText = paramCell("时长", PX2, py - 24, function(d) local c = C() c.duration = math.max(0.5, math.min(6, (c.duration or 2.0) + d * 0.25)) end)
  -- ★0.2.23 曲线函数（蹦出系方向用；循环类：`-` 反向）
  ui.curveText = paramCell("曲线", PX1, py - 48, function(d)
    local c = C()
    local i = 1
    for k, v in ipairs(CURVE_ORD) do if v == (c.curve or "cubic") then i = k break end end
    local n = table.getn(CURVE_ORD)
    c.curve = CURVE_ORD[((i - 1 + (d or 1)) % n) + 1]
  end)
  -- ★0.2.25 移动上限（占屏 %，行程夹取 + 屏界保险丝，见 tick）：曲线右边的空槽
  ui.clampText = paramCell("移动上限", PX2, py - 48, function(d)
    local c = C() c.clampPct = math.max(5, math.min(60, (tonumber(c.clampPct) or 30) + d * 5))
  end)
  py = py - 72

  -- 底部按钮
  local by = py - 6
  local e1; e1, ui.editText = uiSolidBtn(root, "编辑模式", 96, 20, function() editSet(not D.editOn) uiRefresh() end)
  e1:SetPoint("TOPLEFT", root, "TOPLEFT", 18, by)
  local e2; e2, ui.simText = uiSolidBtn(root, "模拟战斗", 96, 20, function()
    D.simOn = not D.simOn
    if D.simOn and not D.editOn then editSet(true) end
    D.simNext = 0
    uiRefresh()
    say("模拟战斗：" .. (D.simOn and "开（编辑锚点处持续放样例数字）" or "关"))
  end)
  e2:SetPoint("TOPLEFT", root, "TOPLEFT", 122, by)
  local e3 = uiSolidBtn(root, "重置位置", 84, 20, function()
    local c = C() c.posX, c.posY = DEF.posX, DEF.posY
    slotReleaseAll()
    editPlace() uiRefresh() say("锚点已重置")
  end)
  e3:SetPoint("TOPLEFT", root, "TOPLEFT", 226, by)
  local e4 = uiSolidBtn(root, "恢复默认", 84, 20, function()
    local c = C()
    for k, v in pairs(DEF) do c[k] = v end
    for _, it in ipairs(ITEMS) do c["it_" .. it.id] = it.def and true or false end
    editPlace() uiRefresh() say("已恢复默认配置")
  end)
  e4:SetPoint("TOPLEFT", root, "TOPLEFT", 318, by)
  local e5 = uiSolidBtn(root, "关闭", 60, 20, function() pcall(root.Hide, root) end)
  e5:SetPoint("TOPLEFT", root, "TOPLEFT", W - 78, by)

  local note = mkFont(root)
  pcall(note.SetPoint, note, "BOTTOMLEFT", root, "BOTTOMLEFT", 18, 12)
  pcall(note.SetText, note, "/edmg 事件=捕获环 · /edmg 捕获 · /edmg 编辑 · /edmg 状态 · /edmg 开|关")
  pcall(note.SetTextColor, note, 0.65, 0.65, 0.65)

  ui.root = root
  ui.built = true
  uiRefresh()
  return true
end

local function uiToggle()
  if not uiBuild() then say("配置面板不可用（建不出控件）") return end
  if ui.root:IsShown() then pcall(ui.root.Hide, ui.root)
  else uiRefresh() pcall(ui.root.Show, ui.root) end
end
D.uiToggle = uiToggle

-- 面板拖拽推进（由唯一节拍帧 tick 驱动；不再立第二个节拍帧）
function D.uiDragTick()
  local d = ui.drag
  if not d then return end
  if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
    ui.drag = nil
    return
  end
  local cx, cy = GetCursorPosition()
  ui.px = d.bx + (cx - d.sx)
  ui.py = d.by + (cy - d.sy)
  -- 越界回归（读不到屏幕尺寸就不夹，fail-open）
  local okW, sw = pcall(UIParent.GetWidth, UIParent)
  if okW and type(sw) == "number" then
    local m = sw / 2 - 60
    if ui.px > m then ui.px = m elseif ui.px < -m then ui.px = -m end
  end
  local okH, sh = pcall(UIParent.GetHeight, UIParent)
  if okH and type(sh) == "number" then
    local m2 = sh / 2 - 40
    if ui.py > m2 then ui.py = m2 elseif ui.py < -m2 then ui.py = -m2 end
  end
  pcall(ui.root.ClearAllPoints, ui.root)
  pcall(ui.root.SetPoint, ui.root, "CENTER", UIParent, "CENTER", ui.px, ui.py)
end

-- ----------------------------------------------------------------------------
-- 总开关 / 关断四件事
-- ----------------------------------------------------------------------------
local function setMaster(on)
  local c = C()
  c.master = on and true or false
  if c.master then
    eventSync()
    say("EH_Damage 已开启（/edmg ui 配置 · /edmg 编辑 进入编辑模式）")
  else
    -- ① 资源回收：槽全部收回（1.12 无销毁 API ⇒ Hide + 清账）
    slotReleaseAll()
    -- ③ 数据重置：游标/拖拽/低血武装复位
    D.drag = nil
    D.lowArmed.hp = true D.lowArmed.mana = true
    D.shapeSeen = {}                 -- 句形去重表也随关断清（下次打开从零记）
    -- ④ 图层清理：编辑锚点收起
    if D.editUI then pcall(D.editUI.f.Hide, D.editUI.f) end
    D.editOn = false D.simOn = false
    eventSync()      -- 摘全部事件
    say("EH_Damage 已关闭（收层 · 停节拍 · 摘事件）")
  end
  beatSync()         -- ② 节拍停止/重挂（唯一入口）
  uiRefresh()
end
D.setMaster = setMaster


-- ----------------------------------------------------------------------------
-- 命令
-- ----------------------------------------------------------------------------
local function cmd(msg)
  msg = tostring(msg or "")
  msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")
  local sub = string.lower(msg)
  if sub == "" or sub == "ui" then uiToggle() return end
  if sub == "编辑" or sub == "edit" then editSet(not D.editOn) uiRefresh() return end
  if sub == "模拟" or sub == "sim" then
    D.simOn = not D.simOn
    if D.simOn and not D.editOn then editSet(true) end
    D.simNext = 0
    say("模拟战斗：" .. (D.simOn and "开" or "关"))
    return
  end
  if sub == "开" or sub == "on" then setMaster(true) return end
  if sub == "关" or sub == "off" then setMaster(false) return end
  if sub == "捕获" or sub == "capture" then
    local c = C() c.capture = not c.capture
    say("捕获未识别战斗文本：" .. (c.capture and "开（落存档环）" or "关"))
    return
  end
  if sub == "事件" or sub == "events" then
    local r = C().ring
    local n = table.getn(r)
    say("捕获环（" .. n .. " 条，最新在后）：")
    local from = math.max(1, n - 14)
    for i = from, n do say("  " .. r[i]) end
    return
  end
  if sub == "状态" or sub == "status" then
    local c = C()
    say("状态：总开关=" .. (c.master and "开" or "关") ..
      " 方向=" .. (DIR_ZH[c.direction] or "?") ..
      " 字号=" .. (D.TIER[c.fontTier or 3].zh) .. " 速度=" .. tostring(c.speed) ..
      " 时长=" .. string.format("%.1f", c.duration or 0) ..
      " 槽=" .. D.poolN .. "/" .. POOL_MAX ..
      " 编辑=" .. (D.editOn and "开" or "关") .. " 模拟=" .. (D.simOn and "开" or "关") ..
      " v" .. BUILD)
    return
  end
  if sub == "测试" or sub == "test" then
    addText("damage", "888", 1)
    addText("dot", "66 ·持续", 0)
    addText("heal", "+233 [治疗者甲]", 0)
    say("已放 3 条测试字")
    return
  end
  say("命令：/edmg ui · 编辑 · 模拟 · 开|关 · 捕获 · 事件 · 状态 · 测试")
end
D.cmd = cmd

if type(SlashCmdList) == "table" then
  SlashCmdList["EHDAMAGE"] = function(m) cmd(m) end
  rawset(_G, "SLASH_EHDAMAGE1", "/edmg")
  rawset(_G, "SLASH_EHDAMAGE2", "/edamage")
end

-- ----------------------------------------------------------------------------
-- 载入：toc 预载 + 载入期零副作用（不建帧）；VARIABLES_LOADED 后按真值武装
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:SetScript("OnEvent", function()
  local c = cfgEnsure()
  D.iconScan()                       -- 技能名→图标缓存（配图；法术书变了由 SPELLS_CHANGED 重扫）
  if c.master then eventSync() end
  beatSync()
  say("增强伤害显示 v" .. BUILD .. " 已载入（/edmg 打开配置 · /edmg 编辑 编辑模式 · /edmg 测试）")
end)

-- ----------------------------------------------------------------------------
-- 读值口（生产诊断；名字带 TEST 但保留 —— 真机取证与离线 harness 都走它们）
-- ----------------------------------------------------------------------------
function _G.EVAL_EDMG_STATE()
  local c = C()
  local active = 0
  for i = 1, D.poolN do if D.pool[i].active then active = active + 1 end end
  return {
    version = BUILD, master = c.master, direction = c.direction,
    fontTier = c.fontTier, speed = c.speed, duration = c.duration,
    posX = c.posX, posY = c.posY, pool = D.poolN, active = active,
    shapeN = shapeCount(),                        -- 句形环已记多少种（真机取证口）
    editOn = D.editOn, simOn = D.simOn, ring = table.getn(c.ring or {}),
    tickAttached = (D.frame ~= nil), build = BUILD,
  }
end
function _G.EVAL_EDMG_TEST_ADD(kind, text, crit) return addText(kind, text, crit) end
function _G.EVAL_EDMG_TEST_TICK(dt)                       -- 离线点火（动画走 GetTime 绝对时间，dt 仅作兼容入口）
  rawset(_G, "arg1", dt or 0.05)
  tick()
end
function _G.EVAL_EDMG_TEST_PARSE(ev, msg)                 -- 离线直跑某个事件处理器
  local h = EVH[ev]
  if not h then return false, "no handler" end
  return pcall(h, msg)
end
