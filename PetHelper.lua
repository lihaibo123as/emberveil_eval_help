-- EvalHelp · PetHelper.lua —— 抓宠帮手（1.73.0 独立载入：配置窗第 6 个 Tab）
-- 需求（用户原话）：顶部输入框支持数据检索「宠物技能」（搭配图标），检索下拉列表显示各等级的技能，
--   选中 → 技能详情页；详情页含技能简介 / 需求等级 / 所持有的宠物列表（领域图标 + 该宠物拥有的技能），
--   右侧放大镜点击宠物名 → 跳转「数据检索」Tab 并自动填入该名称检索，后续走数据检索自己的流程。
-- 数据源 = PetData.lua（生成物：技能表来自 doc/pet_info.png、家族属性表来自 doc/猎人宠物属性和技能图.jpg；
--   生成器 = 仓库根目录 gen_petdata.js，**绝不手改 PetData.lua**）；本文件只做检索/展示/探针，不改主程序任何函数。
-- 1.75.3 起另含**家族属性 + 真机探针**：/eh go 宠物家族（= /eh pet fam）读 UnitCreatureFamily/GetPetFoodTypes
--   与 PetData 的家族表对账，用来权威定案 280 条驯服来源里那 64 条 fam 标注冲突（详见 doc/猎人宠物家族属性.md）。
-- 依赖全局件：EVAL_PET_DB（PetData.lua）、EVAL_GET_LANG/EVAL_LOCALES（i18n）、EVAL_SAY（Core 桥）、
--   EVAL_HELP_CFG_TAB（判断本 Tab 是否激活）、EVAL_HELP_CFG_SETTAB（跳 Tab）、EVAL_DS_SEARCH_NAME（数据检索入口）

local PH = { built = false, q = "", view = "list", sel = nil, off = 0, detOff = 0,
             rows = {}, detRows = {}, detWidgets = {} }
local PH_TAB = 6          -- 配置窗第 6 个 Tab（与 EvalHelp.lua 的 tabNames 顺序一一对应）
-- ===== 布局常量（1.73.1 重排：**单一来源**，几何断言直接读由这些值画出来的真实控件）=====
local PH_ROW_H = 20       -- 每行高
local PH_X = 20           -- 左内边距
local PH_RPAD = 24        -- 右内边距（右边缘 = W - PH_RPAD）
-- ★行数按**可用空间**反推（配置窗高 460，内容下沿取 -420，本项目「布局类需求先算空间」铁律）：
--   列表顶 -104 → floor((420-104)/20) = 15 行（末行下缘 -404，余量 16px）
--   详情：属性行 -104 / 宠物标题 -126 / 分隔线 -142 / 宠物首行 -150 → 12 行（末行下缘 -390）
local PH_LIST_ROWS = 15
local PH_DET_ROWS = 12
local PH_LIST_Y = -104
local PH_DET_Y = -150
-- 控件宽度/右边缘关系（1.73.1 修重叠：原来是「谁写谁算」，现在集中成常量并由几何断言守着）
local PH_LABEL_W = 90     -- 搜索标签宽（x=PH_X）
local PH_BOX_W = 300      -- 输入框宽（x=PH_X+96）
local PH_CNT_W = 140      -- 计数文字宽（x=PH_X+96+PH_BOX_W+14 → 右端 570）
local PH_BTN_W = 60       -- [清除] 宽
local PH_BACK_W = 70      -- [返回] 宽
local PH_ZOOM_W = 24      -- [查]（放大镜）宽
-- ★1.75.3 家族图标按钮宽（覆盖 16×16 的家族图标、右端留到名字格 x=+26 之前 ⇒ 不抢名字格的点击/不叠印）
local PH_ICON_BTN_W = 20
local PH_NAME_W = 150     -- 宠物名格宽
local PH_META_X = 180     -- 宠物元信息起点（相对 PH_X）
-- ★★★1.73.6 放大镜素材：**客户端真实纹理路径**（doc/图标路径清单.txt 第 489 条）。
--   【实事故】原值是 `Interface\Icons\INV_Misc_Spyglass_02` —— **两处都错**：
--     ① 前缀是 1.12 老形态（本客户端是 Unreal 资产路径 /Game/Interface/Icons/<名>_TEX）；
--     ② 名字 `_02` **在客户端里根本不存在**（清单里只有 INV_Misc_Spyglass_01）。
--   → 于是它一直画成引擎的「?」缺图占位，用户看到的就只剩保底文字「查」（截图圈出处）。
--   ★为什么 1.73.4 换图标时漏了它：`PET ICON CHECK` 当时**只扫 PetData.lua 的 icon = "…"**，
--     这行是 PetHelper.lua 里的 `local ... = "…"`，等于完全没被检查过（「检查存在 ≠ 覆盖到位」）。
--     本轮已把该检查扩到 PetHelper.lua（任何客户端纹理字面量都必须精确在白名单里）。
local PH_ZOOM_ICON = "/Game/Interface/Icons/INV_Misc_Spyglass_01_TEX"

-- ===== 自绘基础件（与 Toolbox/DataSearch/IconBrowser 同风格） =====
local function phSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function phText(parent, size, r, g, b)
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

local function phBtn(parent, x, y, w, h, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  phSolid(bg, 0.22, 0.18, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local t = phText(b, 10, 0.95, 0.82, 0.35)
  t:SetPoint("CENTER", b, "CENTER", 0, 0)
  t:SetText(label)
  b:SetScript("OnClick", onClick)
  return { btn = b, bg = bg, text = t }
end

-- ===== i18n =====
local function L(k)
  local lang = (type(EVAL_GET_LANG) == "function") and EVAL_GET_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function phSay(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

-- ===== 数据访问 =====
local function phDb() return rawget(_G, "EVAL_PET_DB") end

-- 全量条目：每个技能的每个等级一条（检索列表就列这个——用户要求「显示各等级的技能」）
local phEntryCache = nil
local function phEntries()
  if phEntryCache then return phEntryCache end
  local out = {}
  local db = phDb()
  if db and db.skills then
    for _, sk in ipairs(db.skills) do
      local ranks = (db.ranks and db.ranks[sk.name]) or {}
      for _, r in ipairs(ranks) do
        table.insert(out, { skill = sk, rank = r })
      end
    end
  end
  phEntryCache = out
  return out
end

local function phBeastsOf(skillName, rank)
  local db = phDb()
  local ranks = db and db.ranks and db.ranks[skillName]
  if not ranks then return {} end
  for _, r in ipairs(ranks) do
    if r.rank == rank then return r.beasts or {} end
  end
  return {}
end

local function phFamLabel(famId)
  local db = phDb()
  local f = db and db.families and db.families[famId]
  return (f and f.label) or tostring(famId or "?")
end

local function phFamIcon(famId)
  local db = phDb()
  local f = db and db.families and db.families[famId]
  return f and f.icon or nil
end

-- ★★★1.75.3（用户指定）技能图标 = **宏图标号**（用户原话：「宠物技能图标调整: 撕咬->宏图标139 · 爪击->255 ·
--   嚎叫->695 · 冲锋->700 · 甲壳护盾->710 · 暗影抗性->133」；号来自**图标库 Tab5 悬停的「宏图标序号：N」**）。
--   · 号存在 PetData 的 `skills[].iconIdx`，**纹理运行期解析**：宏图标号的唯一合法入口 = `GetMacroIconInfo(号)`。
--   · ★★★为什么不能离线把号翻成路径：`doc/图标路径清单.txt` 是**按字母排序**的白名单（行号 ≠ 号；先例：DF 的
--     346 号在客户端是 `INV_Misc_Fish_20`，清单第 342 条才是它、第 346 条是 `INV_Misc_Flower_02`）。
--   · 取不到（接口不在 / 号越界 / 返回空）⇒ **退回 `skills[].icon` 那条语义路径**，绝不编一个路径出来。
--   · **按号缓存**（一次解析、全程复用）：一行一渲染一个宏图标、列表 15 行 × 每次刷新都问一遍太浪费；
--     缓存命中即返回，未命中记 `false`（避免反复去问一个取不到的号）。
local PH_ICON_CACHE = {}
function EVAL_PH_SKILL_ICON(sk)
  if type(sk) ~= "table" then return nil end
  local idx = sk.iconIdx
  if type(idx) == "number" and idx > 0 then
    local hit = PH_ICON_CACHE[idx]
    if hit == nil then
      hit = false
      if type(GetMacroIconInfo) == "function" then
        local ok, tex = pcall(GetMacroIconInfo, idx)
        if ok and type(tex) == "string" and tex ~= "" then hit = tex end
      end
      PH_ICON_CACHE[idx] = hit
    end
    if hit then return hit end
  end
  return sk.icon
end
-- 测试用：清缓存（改完桩里的宏图标表要重新解析时才用；**不在生产路径里调**）
function EVAL_PH_TEST_ICON_CACHE_CLEAR() PH_ICON_CACHE = {} end

-- 关键字过滤：命中技能名 或 该等级任一驯服来源（野兽名/区域）——两种搜法都能用
local function phMatch(e, ql)
  if ql == "" then return true, nil end
  if string.find(string.lower(e.skill.name), ql, 1, true) then return true, nil end
  local beasts = e.rank.beasts or {}
  for _, b in ipairs(beasts) do
    if string.find(string.lower(b.name), ql, 1, true) then return true, b.name
    elseif string.find(string.lower(b.zone), ql, 1, true) then return true, b.zone end
  end
  return false, nil
end

local function phFiltered()
  local out = {}
  local ql = string.lower(PH.q or "")
  for _, e in ipairs(phEntries()) do
    local okHit = phMatch(e, ql)
    if okHit then table.insert(out, e) end
  end
  return out
end

-- 条目显示文本：技能名 · 等级N（需宠物等级X）  —— 有野兽命中时附上来源名
local function phEntryLabel(e, hit)
  local base = string.format(L("PH_ENTRY_FMT"), tostring(e.skill.name), e.rank.rank, e.rank.req)
  if hit then base = base .. string.format(L("PH_ENTRY_HIT"), tostring(hit)) end
  return base
end

-- ===== 家族属性 + 真机探针（1.75.3）=====
-- 数据：doc/猎人宠物属性和技能图.jpg（用户提供）→ doc/猎人宠物家族属性.md（逐行转录 + 与现有 fam 标注的 64/280 对账）
--   → 由仓库根目录 gen_petdata.js 生成进 PetData.lua 的 families[id]（label/icon/cname/dmg/armor/hp/foods/sk）
--     以及 famOrder（= 图片行序，生成器与属性表**同一份**，不手写第二份顺序）。
-- ★★★为什么非要有真机探针：家族卡按**家族 id** 呈现，而 280 条驯服来源的 fam 标注是生成期用**名字关键字猜**的
--   （gen_petdata.js 的 familyOf），与图片的「家族→技能」约束对账出 **64 条冲突**；只有客户端自己知道家族 ——
--   `UnitCreatureFamily(unit)` 给出本地化家族名，对回本表 cname 即可权威定案（读数同时落存档供事后读回）。
-- ★API 事实：官方索引（api_unit.html 全表）里有 `UnitCreatureFamily`、`GetPetFoodTypes`；
--   **但本客户端能不能用、返回什么形态必须实测**（本项目铁律：每个 API 都先现场确认，不凭印象）。
-- ★三态纪律（本项目「查不到 ≠ 没有」）：读不到一律分四态如实报 —— 接口不存在 / 客户端返回空 /
--   调用抛错 / 返回的不是字符串；名字认不出就打**原文**（精确匹配、不猜、**不做子串匹配**：
--   子串会让「猫头鹰」被判成「猫」那一族，正是把数据判错的那类静默 bug）。
local PH_FAM_MAX = 40 -- 专属读数环上限（调试日志环只有 100 条且 [DS] 每 ~10 秒一行 ⇒ 会被冲掉）

-- 家族卡：按 famOrder（图片行序）列出；`other` 不在序表里 ⇒ 天然不会混进来
function EVAL_PH_FAM_CARDS()
  local out = {}
  local db = phDb()
  if type(db) ~= "table" or type(db.families) ~= "table" then return out end
  local order = (type(db.famOrder) == "table") and db.famOrder or {}
  for i = 1, table.getn(order) do
    local id = order[i]
    local f = db.families[id]
    if type(f) == "table" then
      table.insert(out, { id = id, label = f.label, icon = f.icon, cname = f.cname,
                          dmg = f.dmg, armor = f.armor, hp = f.hp, foods = f.foods, sk = f.sk,
                          hasStats = (type(f.dmg) == "number") })
    end
  end
  return out
end

local function phFamById(id)
  local db = phDb()
  local f = (type(db) == "table" and type(db.families) == "table") and db.families[id] or nil
  if type(f) ~= "table" then return nil end
  return f
end

-- 家族名 → id：label 与 cname（客户端候选名）都接受；**精确匹配**（去首尾空白、大小写不敏感）；认不出 → nil
function EVAL_PH_FAM_BY_NAME(nm)
  if type(nm) ~= "string" then return nil end
  local n = string.gsub(string.lower(nm), "^%s+", "")
  n = string.gsub(n, "%s+$", "")
  if n == "" then return nil end
  local cards = EVAL_PH_FAM_CARDS()
  for i = 1, table.getn(cards) do
    local f = cards[i]
    local cand = { f.label }
    if type(f.cname) == "table" then
      for k = 1, table.getn(f.cname) do table.insert(cand, f.cname[k]) end
    end
    for k = 1, table.getn(cand) do
      if type(cand[k]) == "string" and string.lower(cand[k]) == n then return f.id end
    end
  end
  return nil
end

-- 任意返回值 → 能看懂的一段（nil / 非字符串都如实说；tostring 自己也可能抛错 ⇒ 一律 pcall(tostring, v)）
local function phStr(v)
  if v == nil then return "nil" end
  local ok, s = pcall(tostring, v)
  if ok and type(s) == "string" then return s end
  return "<" .. type(v) .. ">"
end

-- 读一个单位的家族四态：exists / name / ctype / raw / why（ok / empty / noapi / error / notstr）
local function phUnitFam(unit)
  local r = { unit = unit, exists = false, name = nil, ctype = nil, raw = nil, why = "noapi" }
  if type(UnitExists) == "function" then
    local ok, v = pcall(UnitExists, unit)
    if ok then r.exists = v and true or false end
  end
  if type(UnitName) == "function" then
    local ok, v = pcall(UnitName, unit)
    if ok and type(v) == "string" and v ~= "" then r.name = v end
  end
  if type(UnitCreatureType) == "function" then
    local ok, v = pcall(UnitCreatureType, unit)
    if ok then r.ctype = v end
  end
  if type(UnitCreatureFamily) == "function" then
    local ok, v = pcall(UnitCreatureFamily, unit)
    if not ok then r.why = "error"
    elseif v == nil then r.why = "empty"
    elseif type(v) == "string" then
      if v == "" then r.why = "empty" else r.raw = v r.why = "ok" end
    else
      r.raw = v r.why = "notstr"
    end
  end
  return r
end

-- 宠物食谱（GetPetFoodTypes）同款四态
local function phPetFood()
  if type(GetPetFoodTypes) ~= "function" then return nil, "noapi" end
  local ok, v = pcall(GetPetFoodTypes)
  if not ok then return nil, "error" end
  if v == nil then return nil, "empty" end
  if type(v) ~= "string" then return v, "notstr" end
  if v == "" then return nil, "empty" end
  return v, "ok"
end

-- 专属持久读数环：落 EVAL_HELP_CONFIG.petProbe（登录/重载后仍读得回；核心「调试残渣键」清单里可清）
local function phFamStore()
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) ~= "table" then return nil end
  local box = cfg.petProbe
  if type(box) ~= "table" then box = { out = {} } cfg.petProbe = box end
  if type(box.out) ~= "table" then box.out = {} end
  return box
end

local function phFamOut(s)
  local box = phFamStore()
  if box == nil then return nil end
  table.insert(box.out, tostring(s))
  while table.getn(box.out) > PH_FAM_MAX do table.remove(box.out, 1) end
  box.t = (type(date) == "function") and date("%H:%M:%S") or nil
  return box
end

local function phFamSay(s)
  s = tostring(s)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[宠物家族] " .. s) end
  pcall(phFamOut, s) -- ★专属读数（不被 [DS] 心跳冲掉）
  phSay(s)
end

-- 三加成显示：0 = 图片里的「-」= 无加成；不是数字 = 未收录（**绝不显示成 0**）
local function phPct(v)
  if type(v) ~= "number" then return L("PH_FAM_NONE") end
  if v == 0 then return L("PH_FAM_NONE") end
  if v > 0 then return "+" .. tostring(v) .. "%" end
  return tostring(v) .. "%"
end

local function phJoinList(t)
  if type(t) ~= "table" then return L("PH_FAM_NONE") end
  local out = {}
  for i = 1, table.getn(t) do
    if type(t[i]) == "string" and t[i] ~= "" then table.insert(out, t[i]) end
  end
  if table.getn(out) == 0 then return L("PH_FAM_NONE") end
  return table.concat(out, "、")
end

-- 家族卡 → 七段「键 值」；报告与「表」命令共用同一份（不写两处格式）
local function phFamSegs(f)
  local sk = (type(f.sk) == "table") and f.sk or {}
  return { { L("PH_FAM_K_DMG"), phPct(f.dmg) }, { L("PH_FAM_K_ARM"), phPct(f.armor) },
           { L("PH_FAM_K_HP"), phPct(f.hp) }, { L("PH_FAM_K_FOOD"), phJoinList(f.foods) },
           { L("PH_FAM_K_SK1"), phJoinList(sk.dmg) }, { L("PH_FAM_K_SK2"), phJoinList(sk.spd) },
           { L("PH_FAM_K_SK3"), phJoinList(sk.sp) } }
end

-- 「键 值」段拼成一行：家族卡整行、图标 tooltip 的分段**共用这一份格式**（不在别处再写一遍拼接）
local function phSegJoin(segs)
  local out = {}
  for i = 1, table.getn(segs) do
    table.insert(out, string.format(L("PH_FAM_SEG_FMT"), segs[i][1], segs[i][2]))
  end
  return table.concat(out, L("PH_FAM_SEP"))
end

local function phFamLine(f)
  return phSegJoin(phFamSegs(f))
end

-- ★★★家族图标 tooltip 的**内容唯一来源**（1.75.3 用户要求：「技能详情页的宠物列表.宠物图标 tooltip 显示这个宠物的详情.
--   信息来源以上统计信息」）：真实悬停渲染与断言都读它 —— 测试里绝不复刻文案，别处也不许再拼一份。
--   返回 = 行表（`{ t = 文本, r/g/b = 颜色 }`，与 GameTooltip:AddLine 的入参一一对应）。
--   ★`beast` 可省（只报家族）；给了就带上「宠物名（等级 · 区域）」那一行。
--   ★家族没有属性（`other`，或将来新增的家族卡缺字段）⇒ **如实说「未收录」**，绝不显示成 0 加成。
function EVAL_PH_FAM_TIP_LINES(famId, beast)
  local out = {}
  local nm = (type(beast) == "table") and beast.name or nil
  if type(nm) == "string" and nm ~= "" then
    local lv = (type(beast) == "table") and beast.level or nil
    local zn = (type(beast) == "table") and beast.zone or nil
    table.insert(out, { t = string.format(L("PH_FAM_TIP_HEAD"), nm, tostring(lv or "?"), tostring(zn or "?")),
                        r = 1, g = 0.85, b = 0.35 })
  end
  local f = phFamById(famId)
  if type(f) ~= "table" then
    table.insert(out, { t = L("PH_FAM_NOSTATS"), r = 1, g = 0.5, b = 0.4 })
    return out
  end
  table.insert(out, { t = string.format(L("PH_FAM_TIP_FAM"), tostring(f.label), tostring(famId)), r = 0.6, g = 0.9, b = 1 })
  if type(f.dmg) ~= "number" then
    table.insert(out, { t = L("PH_FAM_NOSTATS"), r = 1, g = 0.5, b = 0.4 })
    return out
  end
  local sk = (type(f.sk) == "table") and f.sk or {}
  table.insert(out, { t = phSegJoin({ { L("PH_FAM_K_DMG"), phPct(f.dmg) }, { L("PH_FAM_K_ARM"), phPct(f.armor) },
                                      { L("PH_FAM_K_HP"), phPct(f.hp) } }), r = 0.9, g = 0.9, b = 0.9 })
  table.insert(out, { t = phSegJoin({ { L("PH_FAM_K_FOOD"), phJoinList(f.foods) } }), r = 0.82, g = 0.86, b = 0.72 })
  table.insert(out, { t = phSegJoin({ { L("PH_FAM_K_SK1"), phJoinList(sk.dmg) }, { L("PH_FAM_K_SK2"), phJoinList(sk.spd) },
                                      { L("PH_FAM_K_SK3"), phJoinList(sk.sp) } }), r = 0.82, g = 0.86, b = 0.72 })
  table.insert(out, { t = L("PH_FAM_TIP_SRC"), r = 0.6, g = 0.6, b = 0.6 })
  return out
end

-- 读一次并报告（**唯一入口**：命令与测试都走它，测试里绝不复刻读数逻辑）；返回报告表供断言读
--   ★报告表同时**带着原文行**（rep.lines）—— 断言直接读「真正打出来的那几句」，与 HH_TIP_LINES 同一条纪律
function EVAL_PH_FAM_PROBE()
  local rep = { units = {}, food = nil, foodWhy = nil, matched = {}, unknown = {}, lines = {} }
  local function pushR(s) table.insert(rep.lines, s) phFamSay(s) end
  local UNITS = { { "pet", L("PH_FAM_UNIT_PET") }, { "target", L("PH_FAM_UNIT_TGT") } }
  pushR(L("PH_FAM_TITLE"))
  for i = 1, table.getn(UNITS) do
    local head = UNITS[i][2]
    local u = phUnitFam(UNITS[i][1])
    table.insert(rep.units, u)
    pushR(string.format(L("PH_FAM_U_FMT"), head, tostring(u.exists), phStr(u.name), phStr(u.raw), phStr(u.ctype)))
    if not u.exists then
      -- ★不存在 ≠ 没有家族：如实说明这次读不到，别让用户以为「客户端没有家族信息」
      pushR(L("PH_FAM_U_ABSENT"))
    elseif u.why == "ok" then
      local id = EVAL_PH_FAM_BY_NAME(u.raw)
      if id then
        local f = phFamById(id)
        table.insert(rep.matched, id)
        pushR(string.format(L("PH_FAM_U_MATCH_FMT"), tostring(id), tostring(f and f.label or id)))
        if f and type(f.dmg) == "number" then pushR("　　" .. phFamLine(f)) else pushR(L("PH_FAM_NOSTATS")) end
      else
        table.insert(rep.unknown, u.raw)
        pushR(L("PH_FAM_U_UNKNOWN"))
      end
    else
      pushR(string.format(L("PH_FAM_U_WHY_FMT"), L("PH_FAM_W_" .. string.upper(u.why))))
    end
  end
  local fv, fwhy = phPetFood()
  rep.food, rep.foodWhy = fv, fwhy
  if fwhy == "ok" then pushR(string.format(L("PH_FAM_FOOD_FMT"), tostring(fv)))
  else pushR(string.format(L("PH_FAM_FOOD_FMT"), L("PH_FAM_W_" .. string.upper(fwhy)))) end
  local box = phFamStore()
  local n = (box and type(box.out) == "table") and table.getn(box.out) or 0
  pushR(string.format(L("PH_FAM_SAVED_FMT"), PH_FAM_MAX, n))
  return rep
end

-- 命令入口：/eh go 宠物家族（= 别名 /eh pet fam）｜ 宠物家族 表 ｜ 存档 ｜ 清
function EVAL_PH_FAM_CMD(sub)
  sub = tostring(sub or "")
  sub = string.gsub(sub, "^%s+", "")
  sub = string.gsub(sub, "%s+$", "")
  if sub == "" then
    EVAL_PH_FAM_PROBE()
  elseif sub == "表" or sub == "table" then
    local cards = EVAL_PH_FAM_CARDS()
    phFamSay(string.format(L("PH_FAM_TBL_TITLE_FMT"), table.getn(cards)))
    for i = 1, table.getn(cards) do
      local f = cards[i]
      if f.hasStats then phFamSay(string.format(L("PH_FAM_HEAD_FMT"), tostring(f.label)) .. phFamLine(f))
      else phFamSay(string.format(L("PH_FAM_HEAD_FMT"), tostring(f.label)) .. L("PH_FAM_NOSTATS")) end
    end
  elseif sub == "存档" or sub == "save" then
    local box = phFamStore()
    local out = (box and box.out) or {}
    phFamSay(string.format(L("PH_FAM_SAVE_TITLE_FMT"), PH_FAM_MAX, table.getn(out)))
    for i = 1, table.getn(out) do phSay(tostring(out[i])) end
  elseif sub == "清" or sub == "clear" then
    local cfg = rawget(_G, "EVAL_HELP_CONFIG")
    if type(cfg) == "table" then cfg.petProbe = { out = {} } end
    phFamSay(L("PH_FAM_CLEARED"))
  else
    phFamSay(L("PH_FAM_USAGE"))
    return false
  end
  -- ★总闸门关着 ⇒ 报告一个字都到不了聊天框（只落了存档）—— 必须**如实告知**怎么开回来（静默族防线）
  if type(EVAL_CHAT_ON) == "function" then
    local okOn, on = pcall(EVAL_CHAT_ON)
    if okOn and not on and type(EVAL_SAY_FORCE) == "function" then
      pcall(EVAL_SAY_FORCE, L("PH_FAM_CHATOFF"))
    end
  end
  return true
end

-- ===== 跳转：放大镜 → 数据检索 =====
function EVAL_PH_JUMP(name)
  name = tostring(name or "")
  if name == "" then return false end
  local ok1 = false
  if type(EVAL_DS_SEARCH_NAME) == "function" then ok1 = pcall(EVAL_DS_SEARCH_NAME, name) and true or false end
  if type(EVAL_HELP_CFG_SETTAB) == "function" then pcall(EVAL_HELP_CFG_SETTAB, 4) end -- 第 4 个 Tab = 数据检索
  if not ok1 then phSay(L("PH_NO_DS")) end
  PH.lastJump = name
  return ok1
end

-- 打开详情（供列表行点击与测试调用）
function EVAL_PH_OPEN(idx)
  local list = phFiltered()
  local e = list[idx]
  if not e then return false end
  PH.sel = e
  PH.view = "detail"
  PH.detOff = 0
  EVAL_PH_REFRESH()
  return true
end

function EVAL_PH_BACK()
  PH.view = "list"
  PH.sel = nil
  EVAL_PH_REFRESH()
end

-- ★1.73.1 查询词入口**只有这一个**（输入框 OnTextChanged 也走它）：
--   ① 改词 = 重新浏览列表 → 必须从详情页退回列表（否则「改了词还停在旧详情」，
--      而空结果提示又是列表视图的控件 → 用户看到一片空白）；
--   ② 回写输入框要**比对后再写**：本客户端的 SetText 会再触发 OnTextChanged，
--      无条件回写 = 递归（这是本项目「一个入口」与「别写回自己」两条纪律的交点）。
function EVAL_PH_SET_QUERY(q)
  q = tostring(q or "")
  PH.q = q
  PH.off = 0
  PH.view = "list"
  PH.sel = nil
  if PH.eb then
    local okc, cur = pcall(PH.eb.GetText, PH.eb)
    if not (okc and cur == q) then pcall(PH.eb.SetText, PH.eb, q) end
  end
  EVAL_PH_REFRESH()
  return PH.q
end

-- ===== 刷新（可见性契约：本 Tab 的控件全部走**显式** Show/Hide） =====
-- ★★★1.73.1 修的两处真事故（用户截图：「详情页信息错误 / 布局错乱」）：
--   ① 详情视图里**搜索行从没被隐藏** → 标签「宠物技能：」+ 输入框里的检索词 + 详情标题三层叠印在同一行
--      （截图里被读成「宠物技能爪击 · 等级爪击」），[清除] 还压在 [返回] 上；
--   ② 宠物行的名字与元信息先被 Hide、随后**只 Show 了图标和放大镜** → 宠物名/等级/区域/类型永远不显示
--      （截图里每行只剩「?」和「查」）。★测试桩里 SetText 与显隐是两件事，所以上一版断言只读文本，全绿。
function EVAL_PH_REFRESH()
  if not PH.built then return end
  local list = phFiltered()
  local detail = (PH.view == "detail") and PH.sel or nil

  -- ① 搜索行（标签 / 输入框 / 占位 / 计数 / [清除]）**只在列表视图显示**
  if PH.listRow then
    for _, w in ipairs(PH.listRow) do
      if detail then pcall(w.Hide, w) else pcall(w.Show, w) end
    end
  end
  if not detail then
    if PH.count then PH.count:SetText(string.format(L("PH_COUNT"), table.getn(list))) end
    if PH.ph then PH.ph:SetText((PH.q == "") and L("PH_PH") or "") end
  end

  -- ② 列表行（空结果时如实提示，不留一片空白）
  local maxOff = math.max(0, table.getn(list) - PH_LIST_ROWS)
  if PH.off > maxOff then PH.off = maxOff end
  local nList = table.getn(list)
  if PH.emptyList then
    if (not detail) and nList == 0 then
      PH.emptyList:SetText(string.format(L("PH_EMPTY_LIST"), tostring(PH.q)))
      pcall(PH.emptyList.Show, PH.emptyList)
    else
      pcall(PH.emptyList.Hide, PH.emptyList)
    end
  end
  for i = 1, PH_LIST_ROWS do
    local row = PH.rows[i]
    local e = (not detail) and list[PH.off + i] or nil
    row.btn:Hide()
    if e then
      row.btn:Show()
      if row.icon then
        -- ★图标走**唯一解析口**（有 iconIdx 的技能 = 宏图标号 → 运行期解析；取不到退回语义路径）
        local itex = EVAL_PH_SKILL_ICON(e.skill)
        if itex then pcall(row.icon.SetTexture, row.icon, itex) end
      end
      row.text:SetText(phEntryLabel(e))
      -- 交替底色：偶数行稍亮，长列表不再糊成一片（纯观感，不影响判定）
      if row.bg then
        if (PH.off + i) % 2 == 0 then phSolid(row.bg, 0.14, 0.12, 0.08, 1)
        else phSolid(row.bg, 0.10, 0.09, 0.06, 1) end
      end
      row.idx = PH.off + i
    end
  end

  -- 详情区
  for _, w in ipairs(PH.detWidgets) do pcall(w.Hide, w) end
  if detail then
    local sk, rk = detail.skill, detail.rank
    for _, w in ipairs(PH.detWidgets) do pcall(w.Show, w) end
    if PH.detIcon then
      local dtex = EVAL_PH_SKILL_ICON(sk)
      if dtex then pcall(PH.detIcon.SetTexture, PH.detIcon, dtex) end
    end
    PH.detTitle:SetText(string.format(L("PH_DET_TITLE"), tostring(sk.name), rk.rank))
    PH.detIntro:SetText(tostring(sk.intro or ""))
    PH.detMeta:SetText(string.format(L("PH_DET_META"), sk.cost, tostring(sk.cast), tostring(sk.range), tostring(sk.cd)))
    PH.detReq:SetText(string.format(L("PH_DET_REQ"), rk.req))
    -- 宠物行
    local beasts = rk.beasts or {}
    local nBeast = table.getn(beasts)
    if PH.detPetTitle then
      if nBeast > 0 then
        PH.detPetTitle:SetText(string.format(L("PH_DET_PETS"), nBeast))
      else
        -- 训练师被动技能没有驯服来源——如实说明，不显示空表（本项目「查不到 ≠ 没有」）
        PH.detPetTitle:SetText(L("PH_DET_TRAINER"))
      end
    end
    if PH.detScroll then
      if nBeast > PH_DET_ROWS then
        PH.detScroll:SetText(string.format(L("PH_SCROLL_HINT"), PH.detOff + 1, PH.detOff + PH_DET_ROWS, nBeast))
        pcall(PH.detScroll.Show, PH.detScroll)
      else
        pcall(PH.detScroll.Hide, PH.detScroll)
      end
    end
    local dmax = math.max(0, nBeast - PH_DET_ROWS)
    if PH.detOff > dmax then PH.detOff = dmax end
    for i = 1, PH_DET_ROWS do
      local row = PH.detRows[i]
      local b = beasts[PH.detOff + i]
      -- ★七个控件**都要显式管**：bg / icon / iconBtn（1.75.3 图标悬停用）/ nameBtn / name / meta / zoom
      --   （1.73.1 修过「漏 Show 名字与元信息」：这里少管一个，用户看到的就是那一格永远不显示）
      for _, w in ipairs({ row.bg, row.icon, row.iconBtn, row.nameBtn, row.name, row.meta, row.zoom.btn }) do pcall(w.Hide, w) end
      -- ★★悬停读的就是这一格 ⇒ 空行必须清掉，绝不残留上一屏/上一级的宠物（否则 tooltip 显示的家族是别人的）
      row.beast = nil
      if b then
        if row.bg then
          if (PH.detOff + i) % 2 == 0 then phSolid(row.bg, 0.14, 0.12, 0.08, 1)
          else phSolid(row.bg, 0.10, 0.09, 0.06, 1) end
          pcall(row.bg.Show, row.bg)
        end
        local fi = phFamIcon(b.fam)
        if fi then pcall(row.icon.SetTexture, row.icon, fi) end
        pcall(row.icon.Show, row.icon)
        -- ★★★1.75.3：图标按钮也要 Show（★本组断言当场抓到我第一版**只加进了隐藏清单** —— 正是 1.73.1
        --   「只 Hide 不 Show ⇒ 那一格永远不显示」那一族事故；两处必须成对）
        pcall(row.iconBtn.Show, row.iconBtn)
        row.name:SetText(tostring(b.name))
        pcall(row.name.Show, row.name)
        row.meta:SetText(string.format(L("PH_PET_META"), tostring(b.level), tostring(b.zone), phFamLabel(b.fam)))
        pcall(row.meta.Show, row.meta)
        pcall(row.nameBtn.Show, row.nameBtn)
        pcall(row.zoom.btn.Show, row.zoom.btn)
        row.zoom.btn:SetScript("OnClick", function() EVAL_PH_JUMP(b.name) end)
        row.nameBtn:SetScript("OnClick", function() EVAL_PH_JUMP(b.name) end)
        row.beast = b
      end
    end
  end
end

-- ===== 构建 =====
function EVAL_PH_BUILD(root, page, refreshes)
  if PH.built then return end
  local widgets = page.widgets
  local W = 660
  if type(root.GetWidth) == "function" then
    local okw, wv = pcall(root.GetWidth, root)
    if okw and type(wv) == "number" and wv > 200 then W = wv end
  end
  local RX = W - 24

  -- 顶部检索行：输入框 + 计数
  local lab = phText(root, 11, 0.92, 0.88, 0.80)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -60)
  lab:SetText(L("PH_LABEL"))
  table.insert(widgets, lab)

  local boxX, boxW = PH_X + 96, 300
  local ebBg = root:CreateTexture(nil, "BACKGROUND")
  phSolid(ebBg, 0.10, 0.09, 0.06, 1)
  ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", boxX - 2, -54)
  ebBg:SetWidth(boxW + 4) ebBg:SetHeight(22)
  table.insert(widgets, ebBg)

  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_PH_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(boxW) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", boxX, -56)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
        if okF and ok2 then setF = true break end
      end
    end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    pcall(eb.SetJustifyH, eb, "LEFT")
    pcall(eb.SetJustifyV, eb, "MIDDLE")
    pcall(eb.SetTextInsets, eb, 2, 0, 0, 0)
    PH.eb = eb
    table.insert(widgets, eb)
    eb:SetScript("OnTextChanged", function()
      local okt, t = pcall(eb.GetText, eb)
      -- 纯本地数据过滤，无需去抖（数据量小）；★走**唯一入口** EVAL_PH_SET_QUERY（含回写比对，不会递归）
      if okt and type(t) == "string" and t ~= PH.q then EVAL_PH_SET_QUERY(t) end
    end)
    eb:SetScript("OnEnterPressed", function() pcall(eb.ClearFocus, eb) end)
    eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
  end

  -- 占位提示（EditBox 不渲染时的保底，同样给提示）
  local ph = phText(root, 11, 0.55, 0.52, 0.45)
  ph:SetPoint("TOPLEFT", root, "TOPLEFT", boxX + 4, -59)
  pcall(ph.SetWidth, ph, boxW - 8)
  pcall(ph.SetJustifyH, ph, "LEFT")
  ph:SetText(L("PH_PH"))
  PH.ph = ph
  table.insert(widgets, ph)

  local cnt = phText(root, 11, 0.75, 0.72, 0.58)
  cnt:SetPoint("TOPLEFT", root, "TOPLEFT", boxX + boxW + 14, -59)
  -- ★宽度必须**收窄到不撞 [清除]**（1.73.1 修：原先宽 200 → 右端 630，而 [清除] 从 576 起 → 压字）
  pcall(cnt.SetWidth, cnt, PH_CNT_W)
  pcall(cnt.SetJustifyH, cnt, "LEFT")
  PH.count = cnt
  table.insert(widgets, cnt)

  local clearBtn = phBtn(root, RX - PH_BTN_W, -54, PH_BTN_W, 20, L("PH_CLEAR"), function() EVAL_PH_SET_QUERY("") end)
  table.insert(widgets, clearBtn.btn)
  PH.clearBtn = clearBtn
  -- ★1.73.1 搜索行整行成表：详情视图要**整行隐藏**（否则标签+输入框+详情标题叠印，[清除] 还压在 [返回] 上）
  PH.listRow = { lab, ebBg }
  if eb then table.insert(PH.listRow, eb) end
  table.insert(PH.listRow, ph)
  table.insert(PH.listRow, cnt)
  table.insert(PH.listRow, clearBtn.btn)

  -- 列表行池：图标 + 文本（整行可点 → 打开详情）
  for i = 1, PH_LIST_ROWS do
    local y = PH_LIST_Y - (i - 1) * PH_ROW_H
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(W - 40) b:SetHeight(PH_ROW_H - 2)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    phSolid(bg, 0.10, 0.09, 0.06, 1)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16) icon:SetHeight(16)
    icon:SetPoint("LEFT", b, "LEFT", 3, 0)
    local t = phText(b, 11, 0.92, 0.88, 0.80)
    t:SetPoint("LEFT", b, "LEFT", 24, 0)
    pcall(t.SetWidth, t, W - 80)
    pcall(t.SetJustifyH, t, "LEFT")
    table.insert(widgets, b)
    PH.rows[i] = { btn = b, bg = bg, icon = icon, text = t, idx = i }
  end

  -- 空结果如实提示（不留一片空白）
  local emptyList = phText(root, 11, 0.75, 0.72, 0.58)
  emptyList:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 4, PH_LIST_Y - 4)
  pcall(emptyList.SetWidth, emptyList, W - 80)
  pcall(emptyList.SetJustifyH, emptyList, "LEFT")
  table.insert(widgets, emptyList)
  PH.emptyList = emptyList

  -- 详情区：标题 + 简介 + 需求 + 宠物列表 + 返回
  -- ★1.73.1 详情页重排：图标 32、标题右移出图标、属性行与需求行**分列不相交**（原先 meta 宽 W-260、
  --   req 从 PH_X+300 起 → 两者重叠 100px，长文本必然撞在一起）——[返回] 只在详情显示，与 [清除] 不再抢同一格。
  local detIcon = root:CreateTexture(nil, "ARTWORK")
  detIcon:SetWidth(32) detIcon:SetHeight(32)
  detIcon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -58)
  table.insert(widgets, detIcon)
  PH.detIcon = detIcon

  local detTitle = phText(root, 12, 1, 0.85, 0.35)
  detTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 42, -60)
  pcall(detTitle.SetWidth, detTitle, 240)
  pcall(detTitle.SetJustifyH, detTitle, "LEFT")
  table.insert(widgets, detTitle)
  PH.detTitle = detTitle

  local detIntro = phText(root, 10, 0.85, 0.82, 0.72)
  detIntro:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 42, -84)
  pcall(detIntro.SetWidth, detIntro, W - (PH_X + 42) - PH_RPAD)
  pcall(detIntro.SetJustifyH, detIntro, "LEFT")
  table.insert(widgets, detIntro)
  PH.detIntro = detIntro

  local detMeta = phText(root, 10, 0.70, 0.68, 0.55)
  detMeta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -104)
  pcall(detMeta.SetWidth, detMeta, 300)
  pcall(detMeta.SetJustifyH, detMeta, "LEFT")
  table.insert(widgets, detMeta)
  PH.detMeta = detMeta

  local detReq = phText(root, 10, 1, 0.75, 0.35)
  detReq:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 310, -104)
  pcall(detReq.SetWidth, detReq, W - (PH_X + 310) - PH_RPAD)
  pcall(detReq.SetJustifyH, detReq, "LEFT")
  table.insert(widgets, detReq)
  PH.detReq = detReq

  local detPetTitle = phText(root, 11, 0.95, 0.80, 0.30)
  detPetTitle:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -126)
  table.insert(widgets, detPetTitle)
  PH.detPetTitle = detPetTitle

  -- 宠物标题与宠物列表之间的分隔线（观感：区块分明；只在详情显示）
  local sep = root:CreateTexture(nil, "BACKGROUND")
  phSolid(sep, 0.32, 0.27, 0.16, 1)
  sep:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, -142)
  sep:SetWidth(W - PH_X - PH_RPAD) sep:SetHeight(1)
  table.insert(widgets, sep)

  -- 宠物条目多于一屏时的**如实**提示（本项目的「绝不静默截断」）
  local detScroll = phText(root, 10, 0.70, 0.68, 0.55)
  detScroll:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 300, -126)
  pcall(detScroll.SetWidth, detScroll, W - (PH_X + 300) - PH_RPAD)
  pcall(detScroll.SetJustifyH, detScroll, "LEFT")
  table.insert(widgets, detScroll)
  PH.detScroll = detScroll

  local backBtn = phBtn(root, RX - PH_BACK_W, -58, PH_BACK_W, 20, L("PH_BACK"), function() EVAL_PH_BACK() end)
  table.insert(widgets, backBtn.btn)
  PH.backBtn = backBtn

  -- 宠物行池：底条 + 家族图标 + 名称（可点） + 元信息 + 放大镜
  --   ★列宽关系固定（互不相交）：名称 x=PH_X+26 宽 PH_NAME_W ｜ 元信息 x=PH_X+PH_META_X 宽 到 [查] 左边 -8 ｜ [查] 右贴 RX
  local metaW = W - (PH_X + PH_META_X) - PH_RPAD - PH_ZOOM_W - 8
  for i = 1, PH_DET_ROWS do
    local y = PH_DET_Y - (i - 1) * PH_ROW_H
    local bg = root:CreateTexture(nil, "BACKGROUND")
    phSolid(bg, 0.10, 0.09, 0.06, 1)
    bg:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X, y + 2)
    bg:SetWidth(W - PH_X - PH_RPAD) bg:SetHeight(PH_ROW_H - 2)
    table.insert(widgets, bg)
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(16) icon:SetHeight(16)
    icon:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 5, y + 3)
    table.insert(widgets, icon)
    -- ★1.75.3（用户要求）：「技能详情页的宠物列表 → **宠物图标 tooltip** 显示这个宠物的详情，信息来源以上统计信息」
    --   ⇒ 家族图标上盖一个**透明 Button**：★纹理不吃鼠标事件、挂不了 tooltip（本项目实测结论，见工具箱「待测试」标记那一条），
    --     必须用 Button 兜住才行。内容**只**来自家族属性表（`EVAL_PH_FAM_TIP_LINES` = 唯一来源），此处不再拼第二份文案。
    --   ★只做「悬停提示」，不接管点击（点击仍归名字格与放大镜 —— 免得两处真值抢事件）。
    --   ★读的是 `PH.detRows[i].beast`（刷新时写入；空行显式清 nil）⇒ 悬停时永远拿当前这一行的宠物。
    local ib = CreateFrame("Button", nil, root)
    ib:SetWidth(PH_ICON_BTN_W) ib:SetHeight(PH_ROW_H - 2)
    ib:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 3, y + 1)
    pcall(ib.EnableMouse, ib, true)
    pcall(ib.SetScript, ib, "OnEnter", function()
      if type(GameTooltip) == "nil" then return end
      local r = PH.detRows[i]
      local b = r and r.beast
      local lines = EVAL_PH_FAM_TIP_LINES(b and b.fam or nil, b)
      pcall(GameTooltip.SetOwner, GameTooltip, ib, "ANCHOR_RIGHT")
      for k = 1, table.getn(lines) do
        pcall(GameTooltip.AddLine, GameTooltip, lines[k].t, lines[k].r, lines[k].g, lines[k].b)
      end
      pcall(GameTooltip.Show, GameTooltip)
    end)
    pcall(ib.SetScript, ib, "OnLeave", function()
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    table.insert(widgets, ib)
    local nb = CreateFrame("Button", nil, root)
    nb:SetWidth(PH_NAME_W) nb:SetHeight(PH_ROW_H - 4)
    nb:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + 26, y + 2)
    pcall(nb.EnableMouse, nb, true)
    pcall(nb.RegisterForClicks, nb, "LeftButtonUp")
    local name = phText(nb, 11, 0.92, 0.88, 0.80)
    name:SetPoint("LEFT", nb, "LEFT", 0, 0)
    pcall(name.SetWidth, name, PH_NAME_W)
    pcall(name.SetJustifyH, name, "LEFT")
    table.insert(widgets, nb)
    local meta = phText(root, 10, 0.70, 0.68, 0.55)
    meta:SetPoint("TOPLEFT", root, "TOPLEFT", PH_X + PH_META_X, y + 4)
    pcall(meta.SetWidth, meta, metaW)
    pcall(meta.SetJustifyH, meta, "LEFT")
    table.insert(widgets, meta)
    local zoom = phBtn(root, RX - PH_ZOOM_W, y + 2, PH_ZOOM_W, PH_ROW_H - 4, L("PH_ZOOM"), function() end)
    -- ★1.73.6 用户：「换成 放大镜图标」—— 图标**顶替**保底文字「查」：贴真素材 + 把文字显式藏掉。
    --   ★文字仍保留在建好的控件上（phBtn 的 label 参数），只是**显式 Hide**：这样 L("PH_ZOOM") 这个
    --     语言键仍是「在用」的，而「图标没画出来」的回归由 PET ICON CHECK + 断言一起挡（不靠那行文字兜底）。
    local zi = zoom.btn:CreateTexture(nil, "ARTWORK")
    zi:SetWidth(16) zi:SetHeight(16)
    zi:SetPoint("CENTER", zoom.btn, "CENTER", 0, 0)
    pcall(zi.SetTexture, zi, PH_ZOOM_ICON)
    pcall(zoom.text.Hide, zoom.text)
    table.insert(widgets, zi)
    pcall(zoom.btn.SetScript, zoom.btn, "OnEnter", function()
      if type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, zoom.btn, "ANCHOR_RIGHT")
        pcall(GameTooltip.AddLine, GameTooltip, L("PH_ZOOM_TIP"), 0.9, 0.85, 0.6)
        pcall(GameTooltip.Show, GameTooltip)
      end
    end)
    pcall(zoom.btn.SetScript, zoom.btn, "OnLeave", function()
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    table.insert(widgets, zoom.btn)
    PH.detRows[i] = { bg = bg, icon = icon, iconBtn = ib, name = name, nameBtn = nb, meta = meta, zoom = zoom, zoomIcon = zi }
  end

  PH.detWidgets = { detIcon, detTitle, detIntro, detMeta, detReq, detPetTitle, sep, detScroll, backBtn.btn }
  for i = 1, PH_DET_ROWS do
    local r = PH.detRows[i]
    table.insert(PH.detWidgets, r.bg)
    table.insert(PH.detWidgets, r.icon)
    table.insert(PH.detWidgets, r.iconBtn)
    table.insert(PH.detWidgets, r.nameBtn)
    table.insert(PH.detWidgets, r.name)
    table.insert(PH.detWidgets, r.meta)
    table.insert(PH.detWidgets, r.zoom.btn)
  end

  -- 点击列表行 → 详情（★local 作用域陷阱：OnClick 在所有控件建好后再挂）
  for i = 1, PH_LIST_ROWS do
    local row = PH.rows[i]
    row.btn:SetScript("OnClick", function()
      if row.idx then EVAL_PH_OPEN(row.idx) end
    end)
  end

  -- 滚轮：列表翻页 / 详情宠物翻页（链式接管，不吞别人事件）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  if type(root.GetScript) == "function" then
    local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  root:SetScript("OnMouseWheel", function(a, b)
    local active = true
    if type(EVAL_HELP_CFG_TAB) == "function" then active = (EVAL_HELP_CFG_TAB() == PH_TAB) end
    if active then
      -- ★1.73.3 方向单一来源（上滚 = 回到前面）
      local dir = EVAL_WHEEL_DIR(a, b)
      if dir ~= 0 then
        if PH.view == "detail" then
          PH.detOff = math.max(0, PH.detOff - dir)
        else
          PH.off = math.max(0, PH.off - dir)
        end
        EVAL_PH_REFRESH()
        return
      end
    end
    if prevWheel then pcall(prevWheel, a, b) end
  end)

  PH.built = true
  -- ★★★1.75.11 用户真机 bug 修复（点 HUD 标题栏快捷开关 → 配置窗「抓宠帮手」Tab 内容重叠）：
  --   注册进配置窗刷新表的**必须是带 Tab 门的包装**，不能是裸的 EVAL_PH_REFRESH ——
  --   `cfgWin.refresh()` 跑的是**所有页**的刷新（开配置窗 + HUD 那两个快捷开关都会调它一次），
  --   而本函数里有 Show 控件：不在本 Tab 时就会把本页内容盖到当前那一页上
  --   （实测：停在「工具箱」页点开关 ⇒ 本页 21 个控件全亮）。
  --   ★直接调用（SETTAB / 本页交互 / 断言）**行为一字不变** ⇒ 门只加在「总闸」这条路上。
  table.insert(refreshes, function()
if type(EVAL_HELP_CFG_TAB) == "function" and EVAL_HELP_CFG_TAB() ~= 6 then return end
    EVAL_PH_REFRESH()
  end)
  EVAL_PH_REFRESH()
end

-- ===== 测试钩子（读生产真值，不在测试里复刻逻辑） =====
function EVAL_PH_TEST_BUILT() return PH.built and true or false end
function EVAL_PH_TEST_STATE()
  return { view = PH.view, q = PH.q, off = PH.off, entries = table.getn(phEntries()), filtered = table.getn(phFiltered()) }
end
function EVAL_PH_TEST_ENTRY(i)
  local list = phFiltered()
  local e = list[i]
  if not e then return nil end
  return { skill = e.skill.name, rank = e.rank.rank, req = e.rank.req, beasts = table.getn(e.rank.beasts or {}) }
end
function EVAL_PH_TEST_LABEL(i) return phEntryLabel(phFiltered()[i] or {}) end
function EVAL_PH_TEST_DETAIL()
  local e = PH.sel
  if not e then return nil end
  return { skill = e.skill.name, rank = e.rank.rank, req = e.rank.req, intro = e.skill.intro, icon = e.skill.icon, beasts = e.rank.beasts }
end
-- ★1.73.1 断言入口：详情页**真实控件上的文字**（标题/简介/属性行/需求/宠物标题）
--   ★为什么需要它：用户报「详情页信息错误」——而此前只有 DETAIL（数据侧）钩子，读不到**渲染出来的那句话**。
function EVAL_PH_TEST_TEXTS()
  local t = {}
  for k, w in pairs({ title = PH.detTitle, intro = PH.detIntro, meta = PH.detMeta, req = PH.detReq, petTitle = PH.detPetTitle }) do
    local ok, v = pcall(w.GetText, w)
    t[k] = (ok and tostring(v or "")) or nil
  end
  return t
end
function EVAL_PH_TEST_ROW(i)
  local r = PH.rows[i]
  if not r then return nil end
  return { shown = (r.btn.IsShown and r.btn:IsShown()) and true or false, text = r.text:GetText(), idx = r.idx }
end
function EVAL_PH_TEST_DETROW(i)
  local r = PH.detRows[i]
  if not r then return nil end
  return { name = r.name:GetText(), meta = r.meta:GetText(), zoomShown = (r.zoom.btn.IsShown and r.zoom.btn:IsShown()) and true or false }
end
-- ★1.73.6 放大镜按钮的**真实状态**：① 真控件上贴的纹理是哪个；② 保底文字「查」是否被藏掉。
--   ★判据要盯「画出来的图标 == 客户端清单里那枚放大镜」，而不是「代码里写了某个字符串」——
--     上一版的错就错在**字符串写错而没有任何断言看得见**（它画成了「?」，只有保底文字露在外面）。
function EVAL_PH_TEST_ZOOM(i)
  local r = PH.detRows[i or 1]
  if not r then return nil end
  local path = nil
  if r.zoomIcon and type(r.zoomIcon.GetTexture) == "function" then
    local ok, v = pcall(r.zoomIcon.GetTexture, r.zoomIcon)
    if ok then path = v end
  end
  local textShown = false
  if r.zoom and r.zoom.text and type(r.zoom.text.IsShown) == "function" then
    local ok2, v2 = pcall(r.zoom.text.IsShown, r.zoom.text)
    textShown = (ok2 and v2) and true or false
  end
  return { path = path, textShown = textShown, iconW = (r.zoomIcon and r.zoomIcon:GetWidth()) or nil }
end
function EVAL_PH_TEST_LAST_JUMP() return PH.lastJump end
function EVAL_PH_RESET_JUMP() PH.lastJump = nil end
function EVAL_PH_TEST_FAMILY_LABEL(f) return phFamLabel(f) end
-- ★1.73.1 断言入口：本 Tab 的**真实几何与可见性**（布局审查用；测试里不许复刻坐标）。
--   为什么必须有它：这两处真事故（搜索行没隐藏 / 宠物行名字元信息没 Show）**文本全对、只是不可见**，
--   只读文本的断言全绿——必须能问到「这个控件此刻到底可不可见、矩形落在哪」。
function EVAL_PH_TEST_GEOM()
  local function rect(w)
    if not (w and w.GetLeft and w.GetTop) then return nil end
    local okl, l = pcall(w.GetLeft, w)
    local okt, t = pcall(w.GetTop, w)
    local okw, ww = pcall(w.GetWidth, w)
    local okh, hh = pcall(w.GetHeight, w)
    local oks, s = pcall(w.IsShown, w)
    if not (okl and okt and okw and okh) then return nil end
    return { x = l, y = t, w = ww, h = hh, shown = (oks and s) and true or false }
  end
  local function shown(w)
    if not (w and w.IsShown) then return false end
    local ok, s = pcall(w.IsShown, w)
    return (ok and s) and true or false
  end
  local out = { listRowShown = false, listRow = {}, list = {}, det = {} }
  if PH.listRow then
    for i, w in ipairs(PH.listRow) do
      out.listRow[i] = rect(w)
      if shown(w) then out.listRowShown = true end
    end
  end
  out.clearBtn = rect(PH.clearBtn and PH.clearBtn.btn)
  out.backBtn = rect(PH.backBtn and PH.backBtn.btn)
  out.emptyList = rect(PH.emptyList)
  out.emptyListShown = shown(PH.emptyList)
  out.detIcon = rect(PH.detIcon)
  out.detTitle = rect(PH.detTitle)
  out.detMeta = rect(PH.detMeta)
  out.detReq = rect(PH.detReq)
  out.detPetTitle = rect(PH.detPetTitle)
  out.detScroll = rect(PH.detScroll)
  for i = 1, PH_LIST_ROWS do
    local r = PH.rows[i]
    out.list[i] = { btn = rect(r.btn), text = r.text:GetText(), textShown = shown(r.text) }
  end
  for i = 1, PH_DET_ROWS do
    local r = PH.detRows[i]
    out.det[i] = { nameBtn = rect(r.nameBtn), name = rect(r.name), meta = rect(r.meta), icon = rect(r.icon),
                   iconBtn = rect(r.iconBtn), zoom = rect(r.zoom.btn), bg = rect(r.bg),
                   nameShown = shown(r.name), metaShown = shown(r.meta), zoomShown = shown(r.zoom.btn),
                   iconBtnShown = shown(r.iconBtn), hasBeast = (r.beast ~= nil),
                   nameText = r.name:GetText(), metaText = r.meta:GetText() }
  end
  return out
end
-- ★1.75.3 家族图标 tooltip 的**真实悬停**读值口：**走真控件的 OnEnter 脚本**（不在测试里直接调渲染逻辑，
--   也不在生产代码里读桩的记账表）—— 调用方（断言）自己去看桩记下的 tooltip 文本。
--   返回 wired（有没有挂上脚本）/ called（这次点火有没有抛错）/ hasBeast（这一行当时有没有宠物数据）。
function EVAL_PH_TEST_FAM_HOVER(i)
  local r = PH.detRows[i or 1]
  if not r then return nil end
  local okg, g = pcall(r.iconBtn.GetScript, r.iconBtn, "OnEnter")
  if not okg or type(g) ~= "function" then return { wired = false, called = false, hasBeast = (r.beast ~= nil) } end
  local okc = pcall(g)
  return { wired = true, called = okc and true or false, hasBeast = (r.beast ~= nil) }
end
-- 家族图标（读生产表，不在测试里另写一份）——用来暴露「占位图」这件事
function EVAL_PH_TEST_FAM_ICON(f) return phFamIcon(f) end
-- ★1.75.3（第二轮）fam 重标的读值口：按「技能 + 等级 + 野兽名」取**生产真值**里的 fam
--   （不在测试里复刻生成器的定案逻辑 —— 那是两处真值）
function EVAL_PH_TEST_BEAST_FAM(skill, rank, name)
  local beasts = phBeastsOf(skill, rank)
  for i = 1, table.getn(beasts) do
    if beasts[i].name == name then return beasts[i].fam end
  end
  return nil
end
-- ★1.75.3 技能图标读值口：`EVAL_PH_TEST_SKILL_ICON` = **渲染真正用的那个纹理**（走唯一解析口 = 宏图标号优先）；
--   `..._STATIC` = PetData 里那条**兜底**语义路径（两者不同 ⇒ 说明号解析生效了；接口缺失时两者应相等）。
function EVAL_PH_TEST_SKILL_ICON(name)
  local db = phDb()
  for _, sk in ipairs((db and db.skills) or {}) do if sk.name == name then return EVAL_PH_SKILL_ICON(sk) end end
  return nil
end
function EVAL_PH_TEST_SKILL_ICON_STATIC(name)
  local db = phDb()
  for _, sk in ipairs((db and db.skills) or {}) do if sk.name == name then return sk.icon end end
  return nil
end
function EVAL_PH_TEST_SKILL_ICON_IDX(name)
  local db = phDb()
  for _, sk in ipairs((db and db.skills) or {}) do if sk.name == name then return sk.iconIdx end end
  return nil
end
-- ★1.75.3 **真实渲染**读值口：列表首行图标 / 详情大图标上**真正贴着的纹理**
--   （用来验「解析口接上渲染了」，而不是只验「函数算得对」—— 本项目「接线漏接不报错」的老坑）
function EVAL_PH_TEST_ICON_TEX(which)
  local w = nil
  if which == "detail" then w = PH.detIcon
  elseif which == "row" then local r = PH.rows[1] w = r and r.icon end
  if not w then return nil end
  local ok, v = pcall(w.GetTexture, w)
  if ok and type(v) == "string" then return v end
  return nil
end
function EVAL_PH_TEST_RESET() PH.q = "" PH.view = "list" PH.sel = nil PH.off = 0 PH.detOff = 0 PH.lastJump = nil if PH.eb then pcall(PH.eb.SetText, PH.eb, "") end end