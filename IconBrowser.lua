-- EvalHelp · IconBrowser.lua —— 图标库（1.71.3 独立载入：配置窗第 5 个 Tab「图标库」）
-- 独立原则：本文件自绘 UI（复刻 Toolbox/DataSearch 的风格），不改主程序任何函数；
--   依赖仅全局件：EVAL_GET_LANG/EVAL_LOCALES（i18n）、EVAL_SAY（Core 桥）、
--   EVAL_DD_OPEN（主程序下拉组件）、EVAL_HELP_CFG_TAB / EVAL_HELP_SE_WARN_ICON（主程序读值口）。
--
-- 数据源 = **客户端内置的宏图标表**（就是宏编辑器里「选图标」那一屏）：
--   GetNumMacroIcons() / GetMacroIconInfo(i)  —— 本机 api_*.html 的函数索引里 Macro 分类共 8 个，
--   这两个都在其中（CreateMacro/DeleteMacro/EditMacro/GetMacroIndexByName/GetMacroInfo/GetNumMacros 另六个）。
--   ★它给的是**路径**（Interface\Icons\xxx），不是文件：整套图标打包在客户端资源里（Content\Paks），
--     磁盘上取不到文件；但 UI 只需要路径就能画，而且它是**客户端内置、无版权问题、零依赖**的资源。
--   ★取不到就**如实说**（绝不假装有图标）：状态分三类 —— ok / noapi（没有这个接口）/ empty（接口在但一枚都没拿到）。
--
-- 另有一组「本插件在用」的图标：**从生产代码里读**（EVAL_GO_SKILL_CATEGORIES 的 icon 字段 + 警示图标读值口），
--   不在这里另写一份名单 —— 那种「两份名单」迟早漂移（本项目反复踩过）。

local IB = { built = false, page = 1, group = "all", q = "", cells = {}, items = {}, status = nil }
local IB_TAB = 5 -- 配置窗第 5 个 Tab（与 EvalHelp.lua 的 tabNames 顺序一一对应）
-- ★★★1.71.9 用户要求「图标容器高度可以再增加」→ 一页行数 6 → **9**（先把可用空间算清楚再定行数）：
--   · 网格顶边 IB_Y_GRID = -100；配置窗高 H=460，底部两条（开关横排 / [案例模版][分享][关闭]）的中线
--     = CLOSE_MIDY = -(H - 10 - 11) = **-439** → 内容可用下沿取 **-420**（留 19px 不贴脸）；
--   · 每行 IB_CELL = 34 → 最多 floor((420 - 100) / 34) = **9 行**（9×34=306 → 末行下缘 -402，余量 18px）；
--   · ★照字面「再加 250px」会直接把最后几行画到窗口外——而本客户端的越界是**静默的**（不报错、只是看不见），
--     所以这一条必须先算后放（本项目「布局类需求先算可用空间」的铁律）。
--   · 每页枚数 = 列数 × 行数（中文窗 660 → floor((660-40)/34)=18 列 → **162 枚/页**，原 108 枚）。
local IB_CELL, IB_ICON, IB_ROWS, IB_PADX = 34, 26, 9, 20
local IB_Y_STATUS, IB_Y_GROUP, IB_Y_GRID = -56, -76, -100

-- ===== 自绘基础件（与 Toolbox/DataSearch 同风格：WHITE8X8 纯色 + 字体链兜底） =====
local function ibSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function ibText(parent, size, r, g, b)
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

local function ibBtn(parent, x, y, w, label, onClick, widgets)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(16)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  ibSolid(bg, 0.22, 0.18, 0.10, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local bt = ibText(b, 10, 0.95, 0.82, 0.35)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText(label)
  b:SetScript("OnClick", onClick)
  if widgets then table.insert(widgets, b) end
  return { btn = b, bg = bg, text = bt }
end

-- ===== i18n / 输出 =====
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

-- ===== 语义表（IconSem.lua：名称 + 多标签）=====
-- ★★★1.73.5 用户要求：「对存储下来的图标路径进行语义识别,对应一个名称,语义tag 一个图标可以设置多个,
--   比如爪子」——IconSem.lua 里每条 = "名称|标签1/标签2/…"（爪子那枚就是「爪|物品/杂物/爪/爪子/爪击/尖爪」）。
--   ★为什么放在独立数据文件：① 它是**生成物**（gen_iconsem.js 从客户端采集的清单生成，单一真值）；
--     ② 过滤/显示都要读它，写在 UI 里就成了第二份真值（本项目「两份名单迟早漂移」的老坑）。
--   ★解析结果**缓存**：过滤是每帧路径（输入即过滤），不能每次重新 split。
local ibSemCache = {}
function EVAL_IB_SEM_OF(base)
  if type(base) ~= "string" or base == "" then return nil end
  if ibSemCache[base] ~= nil then return ibSemCache[base] end
  local out = nil
  local db = rawget(_G, "EVAL_ICON_SEM")
  local v = db and db[base]
  if type(v) == "string" and v ~= "" then
    local nm, tagstr = string.match(v, "^([^|]*)|(.*)$")
    local tags = {}
    if tagstr then
      -- ★用 gmatch 的**显式分隔符**收集（本客户端老坑：不要用 # 与复杂模式）
      for t in string.gmatch(tagstr .. "/", "([^/]+)/") do
        if t ~= "" then table.insert(tags, t) end
      end
    end
    out = { name = (nm ~= "" and nm) or base, tags = tags, raw = base }
  end
  ibSemCache[base] = out or false -- false = 查过了、没有（避免每次重查）
  return out
end

-- ===== 名称 / 分组（纯函数，脱离游戏可测） =====
-- 名称 = 路径最后一段（并去掉扩展名：.blp/.tga 都见过）
--   ★不用 string.gmatch / # （本客户端的老坑），只用 string.match 的字符类。
-- 原始基础名（路径最后一段，去扩展名）——语义表的 key 就是它
function EVAL_IB_RAWN_OF(path)
  if type(path) ~= "string" or path == "" then return nil end
  local seg = string.match(path, "[^\\/]+$") or path
  seg = string.match(seg, "^(.-)%.[%a]+$") or seg   -- 去扩展名（本插件自带素材是 .tga/.blp）
  -- ★★★1.73.5 **必须去掉 Unreal 资产的 _TEX 后缀**：本客户端宏图标表给的是
  --   `/Game/Interface/Icons/<名字>_TEX`（见 doc/图标路径清单.txt）——不去掉的话
  --   EVAL_ICON_SEM 的 key（基础名）一个都对不上 → **全部退回英文名**、中文过滤全废，
  --   而且**一声不响**（这正是 1.73.4 那条「路径形态是 Unreal 资产路径」的同一个坑的翻版）。
  seg = string.match(seg, "^(.-)_TEX$") or seg
  if seg == "" then return nil end
  return seg
end

-- 显示名 = **语义名**（IconSem.lua），没有语义记录时退回原始基础名（如实）
function EVAL_IB_NAME_OF(path)
  local raw = EVAL_IB_RAWN_OF(path)
  if not raw then return nil end
  local sem = EVAL_IB_SEM_OF(raw)
  return (sem and sem.name) or raw
end

-- 分组定义：**顺序稳定**（先匹配到的胜出），最后一条 pat = nil 作兜底。
--   ★判据 = 文件名前缀：宏图标表的命名本身就分族（Spell_Fire_* / Spell_Frost_* / INV_* / Ability_* …）。
local IB_GROUPS = {
  { id = "local",   pat = nil,              key = "IB_G_LOCAL" },   -- 由调用方显式指定（见 ibLocalItems）
  { id = "fire",    pat = "^Spell_Fire",    key = "IB_G_FIRE" },
  { id = "frost",   pat = "^Spell_Frost",   key = "IB_G_FROST" },
  { id = "shadow",  pat = "^Spell_Shadow",  key = "IB_G_SHADOW" },
  { id = "holy",    pat = "^Spell_Holy",    key = "IB_G_HOLY" },
  { id = "nature",  pat = "^Spell_Nature",  key = "IB_G_NATURE" },
  { id = "arcane",  pat = "^Spell_Arcane",  key = "IB_G_ARCANE" },
  { id = "spell",   pat = "^Spell_",        key = "IB_G_SPELL" },
  { id = "ability", pat = "^Ability_",      key = "IB_G_ABILITY" },
  { id = "inv",     pat = "^INV_",          key = "IB_G_INV" },
  { id = "trade",   pat = "^Trade_",        key = "IB_G_TRADE" },
  { id = "racial",  pat = "^Racial_",       key = "IB_G_RACIAL" },
  { id = "temp",    pat = "^Temp",          key = "IB_G_TEMP" },
  { id = "other",   pat = nil,              key = "IB_G_OTHER" },   -- 兜底
}
local function ibGroupByPattern(name)
  for i = 1, table.getn(IB_GROUPS) do
    local g = IB_GROUPS[i]
    if g.pat ~= nil and string.find(name, g.pat) then return g.id end
  end
  return "other"
end

function EVAL_IB_GROUP_OF(path)
  -- ★分组看**原始名**的前缀（Spell_Fire_* 这种），不能拿语义名去匹配前缀
  local n = EVAL_IB_RAWN_OF(path)
  if not n then return nil end
  return ibGroupByPattern(n)
end

function EVAL_IB_GROUPS() return IB_GROUPS end

function EVAL_IB_GROUP_LABEL(id)
  if id == nil or id == "all" then return L("IB_G_ALL") end
  for i = 1, table.getn(IB_GROUPS) do
    if IB_GROUPS[i].id == id then return L(IB_GROUPS[i].key) end
  end
  return tostring(id)
end

-- ===== 本插件在用的图标（**从生产代码读**，不另写名单） =====
-- ★1.73.5 条目工厂：名称/标签/原始名**一处构造**（扫描与「本插件在用」两条路共用，避免两边漂移）
function EVAL_IB_MAKE_ITEM(path, group, idx)
  local raw = EVAL_IB_RAWN_OF(path) or path
  local sem = EVAL_IB_SEM_OF(raw)
  return { path = path, raw = raw, name = (sem and sem.name) or raw,
           tags = (sem and sem.tags) or nil,
           group = group or EVAL_IB_GROUP_OF(path) or "other", idx = idx or 0 }
end

local function ibPushItem(out, seen, path, group)
  if type(path) ~= "string" or path == "" or seen[path] then return end
  seen[path] = true
  table.insert(out, EVAL_IB_MAKE_ITEM(path, group, 0))
end

local function ibLocalItems()
  local out, seen = {}, {}
  if type(EVAL_GO_SKILL_CATEGORIES) == "function" then
    local okc, cats = pcall(EVAL_GO_SKILL_CATEGORIES)
    if okc and type(cats) == "table" then
      for i = 1, table.getn(cats) do
        local c = cats[i]
        if type(c) == "table" then ibPushItem(out, seen, c.icon, "local") end
      end
    end
  end
  if type(EVAL_HELP_SE_WARN_ICON) == "function" then
    local okw, wp = pcall(EVAL_HELP_SE_WARN_ICON)
    if okw then ibPushItem(out, seen, wp, "local") end
  end
  -- ★1.71.3 非动作条动作的图标（目前是「跟随」）：同样**从生产代码读**（单一真值，不另抄路径）
  if type(EVAL_FOLLOW_ICON) == "string" then ibPushItem(out, seen, EVAL_FOLLOW_ICON, "local") end
  -- ★1.71.3 状态标记整套（白=不可用 / 黄=待测试）：**从生产代码读**（同一份真值，不在这里另抄路径）。
  --   ★白的与上面 SE_WARN_ICON 是同一条路径 → ibPushItem 里按路径去重，只算一枚（不会多出来）。
  if type(EVAL_HELP_SE_MARK_ICONS) == "function" then
    local okm, mm = pcall(EVAL_HELP_SE_MARK_ICONS)
    if okm and type(mm) == "table" then
      ibPushItem(out, seen, mm.unavail, "local")
      ibPushItem(out, seen, mm.test, "local")
    end
  end
  return out
end

-- ===== 枚举（pcall 守卫 + 如实记账） =====
-- 返回状态表：{ state = "ok"/"noapi"/"empty", macro = 取到几枚, failed = 几枚取失败 }
function EVAL_IB_SCAN(force)
  if IB.status and not force then return IB.status end
  local st = { state = "ok", macro = 0, failed = 0 }
  local items = ibLocalItems() -- ★本插件在用的图标**永远在**（接口缺失时这一组就是全部内容）
  if type(GetNumMacroIcons) ~= "function" or type(GetMacroIconInfo) ~= "function" then
    st.state = "noapi" -- ★如实：本客户端没有这个接口（不假装列出了一堆图标）
  else
    local okn, n = pcall(GetNumMacroIcons)
    n = okn and tonumber(n) or nil
    if not n or n < 1 then
      st.state = "empty" -- ★接口在，但一枚都没有
    else
      local seen = {}
      for i = 1, table.getn(items) do seen[items[i].path] = true end
      for i = 1, n do
        local oki, tex = pcall(GetMacroIconInfo, i)
        if oki and type(tex) == "string" and tex ~= "" then
          if not seen[tex] then
            seen[tex] = true
            table.insert(items, EVAL_IB_MAKE_ITEM(tex, nil, i))
          end
          st.macro = st.macro + 1
        else
          st.failed = st.failed + 1 -- ★取失败要**数出来**（本项目「绝不静默」）
        end
      end
      if st.macro == 0 then st.state = "empty" end
    end
  end
  IB.items = items
  IB.status = st
  return st
end

function EVAL_IB_STATUS() return IB.status end
function EVAL_IB_ITEMS() return IB.items end
function EVAL_IB_TOTAL() return table.getn(IB.items) end

-- ===== 过滤 / 分页（纯函数：先过滤再切页） =====
-- ★顺序很重要：**先按分组过滤、再切页**。先切页后过滤会让翻页漏项（每页只显示寥寥几枚）。
-- ★★1.73.5 新增**关键字过滤**（用户要求：「在图标库内加个输入过滤根据名称/路径进行筛选功能」）：
--   搜**语义名**（中文）/ **标签**（同义词 + 类别/学派/职业）/ **原始基础名** / **完整路径** —— 四种都命中，
--   大小写不敏感（英文部分）；中文按字节包含即可（不需要分词）。
function EVAL_IB_HIT(it, q)
  if q == nil or q == "" then return true end
  if type(it) ~= "table" then return false end
  local needle = string.lower(q)
  local function has(s)
    return type(s) == "string" and s ~= "" and string.find(string.lower(s), needle, 1, true) ~= nil
  end
  if has(it.name) or has(it.raw) or has(it.path) then return true end
  local tags = it.tags
  for i = 1, table.getn(tags or {}) do
    if has(tags[i]) then return true end
  end
  return false
end

function EVAL_IB_MATCH(it, groupId, q)
  if groupId ~= nil and groupId ~= "all" then
    if not (type(it) == "table" and it.group == groupId) then return false end
  end
  return EVAL_IB_HIT(it, q)
end

function EVAL_IB_FILTER(items, groupId, q)
  local out = {}
  for i = 1, table.getn(items or {}) do
    if EVAL_IB_MATCH(items[i], groupId, q) then table.insert(out, items[i]) end
  end
  return out
end

function EVAL_IB_PAGE_COUNT(n, per)
  per = tonumber(per) or 0
  if per < 1 then return 1 end
  local pc = math.ceil((tonumber(n) or 0) / per)
  if pc < 1 then pc = 1 end
  return pc
end

-- 返回：本页条目表, 夹取后的页码, 总页数, 过滤后总数
function EVAL_IB_PAGE_ITEMS(items, groupId, page, per, q)
  local list = EVAL_IB_FILTER(items, groupId, q)
  local total = table.getn(list)
  local pages = EVAL_IB_PAGE_COUNT(total, per)
  page = tonumber(page) or 1
  if page < 1 then page = 1 end
  if page > pages then page = pages end
  local from = (page - 1) * per + 1
  local out = {}
  for i = from, math.min(from + per - 1, total) do table.insert(out, list[i]) end
  return out, page, pages, total
end

-- 分组下拉的选项：只列**真的有图**的分组（空分组不占行）+ 表头的「全部」
function EVAL_IB_GROUP_OPTIONS(items)
  local counts, order = {}, {}
  table.insert(order, "all")
  counts.all = table.getn(items or {})
  for i = 1, table.getn(IB_GROUPS) do
    local id = IB_GROUPS[i].id
    if id ~= "other" then counts[id] = 0 order[table.getn(order) + 1] = id end
  end
  counts.other = 0
  table.insert(order, "other")
  for i = 1, table.getn(items or {}) do
    local g = items[i].group or "other"
    if counts[g] == nil then counts[g] = 0 end
    counts[g] = counts[g] + 1
  end
  local out = {}
  for i = 1, table.getn(order) do
    local id = order[i]
    if (counts[id] or 0) > 0 then
      table.insert(out, { id = id, label = EVAL_IB_GROUP_LABEL(id) .. " (" .. tostring(counts[id] or 0) .. ")" })
    end
  end
  return out
end

-- 网格排版：列数由**真实窗口宽度**算（列数 × 行数 = 每页枚数）
function EVAL_IB_LAYOUT(W)
  local w = tonumber(W) or 660
  local cols = math.floor((w - IB_PADX * 2) / IB_CELL)
  if cols < 1 then cols = 1 end
  return cols, IB_ROWS, cols * IB_ROWS
end

function EVAL_IB_PER_PAGE(W)
  local _, _, per = EVAL_IB_LAYOUT(W)
  return per
end

-- 翻页（生产与测试共用；越界夹取在 PAGE_ITEMS 里做，这里只管推进页码）
function EVAL_IB_STEP(delta)
  local d = tonumber(delta) or 0
  if d == 0 then return false end
  IB.page = (IB.page or 1) + d
  EVAL_IB_REFRESH()
  return true
end

function EVAL_IB_SET_GROUP(id)
  IB.group = id or "all"
  IB.page = 1
  EVAL_IB_REFRESH()
end

-- ★1.73.5 关键字过滤的**唯一入口**（输入框 OnTextChanged 也走它）：
--   ① 改词 = 回到第 1 页（否则停在第 5 页看着空列表，以为没匹配）；
--   ② 回写输入框要**比对后再写**——本客户端 SetText 会再触发 OnTextChanged，无条件回写 = 递归。
function EVAL_IB_SET_QUERY(q)
  q = tostring(q or "")
  IB.q = q
  IB.page = 1
  if IB.eb then
    local okc, cur = pcall(IB.eb.GetText, IB.eb)
    if not (okc and cur == q) then pcall(IB.eb.SetText, IB.eb, q) end
  end
  EVAL_IB_REFRESH()
  return IB.q
end

-- ===== UI =====
local function ibSetStatusText(st, total, page, pages, q)
  local txt
  if st.state == "ok" then
    if total == 0 and q ~= nil and q ~= "" then
      -- ★1.73.5 空匹配**如实说明**（并提示可搜什么）——不然用户只看到一片空白
      return string.format(L("IB_EMPTY_MATCH"), tostring(q))
    end
    txt = string.format(L("IB_STATUS"), total, page, pages)
    if (st.failed or 0) > 0 then txt = txt .. string.format(L("IB_STATUS_FAIL"), st.failed) end
    if q ~= nil and q ~= "" then txt = txt .. string.format(L("IB_FILTERING"), tostring(q)) end
  elseif st.state == "noapi" then
    txt = L("IB_NOAPI")
  else
    txt = L("IB_EMPTY")
  end
  return txt
end

function EVAL_IB_REFRESH()
  if not IB.built then return end
  IB.refreshes = (IB.refreshes or 0) + 1 -- ★切 Tab 真的刷新了吗？用计数器钉住（不是「数据对不对」）
  local st = EVAL_IB_SCAN()
  local items = IB.items
  local cols, rows, per = EVAL_IB_LAYOUT(IB.W)
  local pageItems, page, pages, total = EVAL_IB_PAGE_ITEMS(items, IB.group, IB.page, per, IB.q)
  IB.page, IB.pages, IB.total, IB.per = page, pages, total, per
  IB.pageItems = pageItems
  if IB.statusFS then pcall(IB.statusFS.SetText, IB.statusFS, ibSetStatusText(st, total, page, pages, IB.q)) end
  if IB.ebPh then
    if IB.q == "" then pcall(IB.ebPh.Show, IB.ebPh) else pcall(IB.ebPh.Hide, IB.ebPh) end
  end
  if IB.groupText then
    pcall(IB.groupText.SetText, IB.groupText,
      string.format(L("IB_GROUP_BTN"), EVAL_IB_GROUP_LABEL(IB.group) .. " (" .. tostring(total) .. ")"))
  end
  for i = 1, table.getn(IB.cells) do
    local c = IB.cells[i]
    local it = pageItems[i]
    c.item = it
    if it then
      pcall(c.tex.SetTexture, c.tex, it.path)
      pcall(c.tex.Show, c.tex)
      pcall(c.btn.Show, c.btn)
    else
      pcall(c.btn.Hide, c.btn)
    end
  end
end

function EVAL_IB_BUILD(root, page, refreshes)
  if IB.built then return end
  local widgets = page.widgets
  local W = 660
  local okw, ww = pcall(root.GetWidth, root)
  if okw and type(ww) == "number" and ww > 0 then W = ww end
  IB.W = W
  IB.root = root

  -- 状态行（左）：共 N 枚 / 第 x/y 页；接口缺失时在这里如实说明
  local stFS = ibText(root, 10, 0.85, 0.82, 0.70)
  stFS:SetPoint("TOPLEFT", root, "TOPLEFT", IB_PADX, IB_Y_STATUS)
  pcall(stFS.SetWidth, stFS, W - 300)
  pcall(stFS.SetJustifyH, stFS, "LEFT")
  pcall(stFS.SetNonSpaceWrap, stFS, false)
  IB.statusFS = stFS
  table.insert(widgets, stFS)

  -- 右上：翻页 + 重扫
  local bw = 52
  local bx = W - IB_PADX - bw * 3 - 8
  IB.btns = {}
  IB.btns.prev = ibBtn(root, bx, IB_Y_STATUS, bw, L("IB_PREV"), function() EVAL_IB_STEP(-1) end, widgets).btn
  IB.btns.next = ibBtn(root, bx + bw + 4, IB_Y_STATUS, bw, L("IB_NEXT"), function() EVAL_IB_STEP(1) end, widgets).btn
  IB.btns.rescan = ibBtn(root, bx + (bw + 4) * 2, IB_Y_STATUS, bw, L("IB_RESCAN"),
    function() EVAL_IB_SCAN(true) EVAL_IB_REFRESH() end, widgets).btn

  -- 分组过滤（复用主程序下拉组件；回调按**下标**映射回 id，不解析标签文字）
  -- ★★回调里要用 gb 自己（点它开下拉）→ 必须**先声明后赋值**：
  --   写成 local gb = ibBtn(..., function() ... gb ... end) 时，闭包里的 gb 会绑到**全局 nil**
  --   （局部变量在语句执行完才进入作用域）——本项目「声明顺序」老坑的第 N 次。
  local gb
  gb = ibBtn(root, IB_PADX, IB_Y_GROUP, 200, "", function()
    local opts = EVAL_IB_GROUP_OPTIONS(IB.items)
    local labels = {}
    for i = 1, table.getn(opts) do labels[i] = opts[i].label end
    if type(EVAL_DD_OPEN) ~= "function" then return end
    EVAL_DD_OPEN(gb.btn, labels, function(pi)
      local o = opts[pi]
      if o then EVAL_IB_SET_GROUP(o.id) end
    end)
  end, widgets)
  IB.groupBtn = gb
  local gt = ibText(gb.btn, 10, 0.95, 0.82, 0.35)
  gt:SetPoint("CENTER", gb.btn, "CENTER", 0, 0)
  pcall(gt.SetWidth, gt, 194)
  pcall(gt.SetNonSpaceWrap, gt, false)
  IB.groupText = gt

  -- ★1.73.5 关键字过滤输入框（用户要求：按名称/路径筛选）——与分组**叠加**（先分组、再关键字）
  --   位置：分组按钮右边（228..428），再右边是 [清除]；都在同一行，不与右上翻页按钮打架。
  local boxX, boxW = IB_PADX + 208, 200
  local ebBg = root:CreateTexture(nil, "BACKGROUND")
  ibSolid(ebBg, 0.10, 0.09, 0.06, 1)
  ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", boxX - 2, IB_Y_GROUP - 2)
  ebBg:SetWidth(boxW + 4) ebBg:SetHeight(20)
  table.insert(widgets, ebBg)
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_IB_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(boxW) eb:SetHeight(16)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", boxX, IB_Y_GROUP)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 10, "")
        if okF and ok2 then setF = true break end
      end
    end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    pcall(eb.SetJustifyH, eb, "LEFT")
    pcall(eb.SetJustifyV, eb, "MIDDLE")
    pcall(eb.SetTextInsets, eb, 2, 0, 0, 0)
    IB.eb = eb
    table.insert(widgets, eb)
    eb:SetScript("OnTextChanged", function()
      local okt, t = pcall(eb.GetText, eb)
      -- 纯本地过滤，无需去抖；走**唯一入口**（含回写比对，不会递归）
      if okt and type(t) == "string" and t ~= IB.q then EVAL_IB_SET_QUERY(t) end
    end)
    eb:SetScript("OnEnterPressed", function() pcall(eb.ClearFocus, eb) end)
    eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
  end
  -- 占位提示（EditBox 不渲染时的保底，同样给提示）
  local ebPh = ibText(root, 10, 0.55, 0.52, 0.45)
  ebPh:SetPoint("TOPLEFT", root, "TOPLEFT", boxX + 4, IB_Y_GROUP - 3)
  pcall(ebPh.SetWidth, ebPh, boxW - 8)
  pcall(ebPh.SetJustifyH, ebPh, "LEFT")
  pcall(ebPh.SetNonSpaceWrap, ebPh, false)
  ebPh:SetText(L("IB_FILTER_PH"))
  IB.ebPh = ebPh
  table.insert(widgets, ebPh)
  local clr = ibBtn(root, boxX + boxW + 8, IB_Y_GROUP, 52, L("IB_FILTER_CLR"),
    function() EVAL_IB_SET_QUERY("") end, widgets)
  IB.filterClear = clr.btn

  -- 图标网格（池子：建 pageSize 个格子，翻页时只换纹理与数据，不重建控件）
  local cols, rows, per = EVAL_IB_LAYOUT(W)
  for i = 1, per do
    local col = math.mod(i - 1, cols)
    local row = math.floor((i - 1) / cols)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(IB_CELL - 4) b:SetHeight(IB_CELL - 4)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", IB_PADX + col * IB_CELL, IB_Y_GRID - row * IB_CELL)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") -- 1.71.15 右键 = 设为小地图按钮图标
    local bg = b:CreateTexture(nil, "BACKGROUND")
    ibSolid(bg, 0.10, 0.09, 0.06, 1)
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(IB_ICON) tex:SetHeight(IB_ICON)
    tex:SetPoint("CENTER", b, "CENTER", 0, 0)
    local cell = { btn = b, bg = bg, tex = tex, item = nil }
    -- ★脚本只在建池时设一次；数据靠 cell.item 现读 —— 避免每页重设脚本
    --   （本客户端 SetScript 是单槽位，反复重设容易把别的处理漏掉）
    b:SetScript("OnClick", function(a, b2)
      local mbtn = (type(a) == "string" and a) or (type(b2) == "string" and b2) or (type(arg1) == "string" and arg1) or "LeftButton"
      if not cell.item then return end
      -- ★1.71.15 用户：「图标调整的不对」——小地图按钮的图标不该由插件代挑，该由她自己挑：
      --   图标库里**右键**任意一枚 = 设为小地图按钮图标（存配置，重登不丢）；左键仍是原来的打印路径。
      if mbtn == "RightButton" then
        if type(EVAL_HELP_MB_SETCUSTOM) == "function" and EVAL_HELP_MB_SETCUSTOM(cell.item.path) then
          say(string.format(L("IB_SET_MB"), cell.item.path))
        end
        return
      end
      say(string.format(L("IB_PICK"), cell.item.path))
    end)
    b:SetScript("OnEnter", function()
      pcall(bg.SetVertexColor, bg, 0.38, 0.30, 0.10, 1)
      local it = cell.item
      if not it or type(GameTooltip) == "nil" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
      pcall(GameTooltip.AddLine, GameTooltip, it.name)
      pcall(GameTooltip.AddLine, GameTooltip, string.format(L("IB_TIP_GROUP"), EVAL_IB_GROUP_LABEL(it.group)))
      -- ★1.73.5 语义标签（同义词 + 类别/学派/职业）——用户要求「一个图标可以设置多个 tag」的落地处之一
      if it.tags and table.getn(it.tags) > 0 then
        pcall(GameTooltip.AddLine, GameTooltip, string.format(L("IB_TIP_TAGS"), table.concat(it.tags, " / ")), 0.75, 0.85, 0.95)
      end
      if (it.idx or 0) > 0 then
        pcall(GameTooltip.AddLine, GameTooltip, string.format(L("IB_TIP_IDX"), it.idx))
      else
        pcall(GameTooltip.AddLine, GameTooltip, L("IB_TIP_LOCAL"))
      end
      pcall(GameTooltip.AddLine, GameTooltip, it.path)
      pcall(GameTooltip.AddLine, GameTooltip, L("IB_TIP_SETMB"), 0.55, 0.85, 0.45) -- 1.71.15 右键换小地图按钮图标
      pcall(GameTooltip.Show, GameTooltip)
    end)
    b:SetScript("OnLeave", function()
      pcall(bg.SetVertexColor, bg, 0.10, 0.09, 0.06, 1)
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    table.insert(widgets, b)
    IB.cells[i] = cell
  end

  -- 滚轮翻页：**链式接管**（先问既有处理器，不吞别人事件——DataSearch/Toolbox 用的是同一套路）
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  if type(root.GetScript) == "function" then
    local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  root:SetScript("OnMouseWheel", function(a, b)
    local active = true
    if type(EVAL_HELP_CFG_TAB) == "function" then active = (EVAL_HELP_CFG_TAB() == IB_TAB) end
    if active then
      -- ★1.73.3 修方向（用户报「滚动方向与效果相反」）：本客户端**上滚 = +1**，
      --   而上滚应当回到**前面**（上一页）——原来写成 `d > 0 → +1（下一页）`，正好反了。
      --   方向一律从 EVAL_WHEEL_DIR 取（单一来源；其余 4 处滚轮也都是「上滚 = 回到前面」）。
      local dir = EVAL_WHEEL_DIR(a, b)
      if dir ~= 0 then
        EVAL_IB_STEP(-dir)
        return
      end
    end
    if prevWheel then pcall(prevWheel, a, b) end
  end)

  IB.built = true
  EVAL_IB_SCAN(true)
  EVAL_IB_REFRESH()
end

-- ===== 测试钩子（读**生产代码的实际状态**，不在测试里复刻逻辑） =====
function EVAL_IB_TEST_BUILT() return IB.built and true or false end
function EVAL_IB_TEST_STATE() local s = IB.status return s and s.state or nil end
function EVAL_IB_TEST_COUNTS()
  local s = IB.status or {}
  return { macro = s.macro or 0, failed = s.failed or 0, items = table.getn(IB.items), local_ = table.getn(ibLocalItems()) }
end
function EVAL_IB_TEST_PAGE() return IB.page, IB.pages, IB.total end
function EVAL_IB_TEST_GROUP() return IB.group end
-- ★1.73.5 语义表/过滤器 的断言入口（读生产真值，不在测试里复刻规则）
function EVAL_IB_TEST_Q() return IB.q end
function EVAL_IB_TEST_SET_Q(q) return EVAL_IB_SET_QUERY(q) end
function EVAL_IB_TEST_SEM(base)
  local s = EVAL_IB_SEM_OF(base)
  if not s then return nil end
  return { name = s.name, tags = s.tags, raw = s.raw }
end
function EVAL_IB_TEST_SEM_SIZE()
  local db = rawget(_G, "EVAL_ICON_SEM")
  local n = 0
  if type(db) == "table" then for _ in pairs(db) do n = n + 1 end end
  return n
end
function EVAL_IB_TEST_MATCH_NAMES(q)
  local out = {}
  local list = EVAL_IB_FILTER(IB.items, IB.group, q)
  for i = 1, table.getn(list) do out[table.getn(out) + 1] = list[i].name end
  return out
end
function EVAL_IB_TEST_MATCH_COUNT(q) return table.getn(EVAL_IB_FILTER(IB.items, IB.group, q)) end
-- ★1.73.5 「分组 + 关键字」叠加是否真生效：返回命中项**各自的 group** ——
--   光比数量大小是弱判据（只写 <= 时，把分组判定整段删掉的变异照样绿）。
function EVAL_IB_TEST_MATCH_GROUPS(q)
  local out = {}
  local list = EVAL_IB_FILTER(IB.items, IB.group, q)
  for i = 1, table.getn(list) do out[table.getn(out) + 1] = list[i].group end
  return out
end
function EVAL_IB_TEST_EB() return IB.eb end
function EVAL_IB_TEST_EB_TEXT()
  if not IB.eb then return nil end
  local ok, t = pcall(IB.eb.GetText, IB.eb)
  return (ok and tostring(t)) or nil
end
function EVAL_IB_TEST_PH_SHOWN()
  if not IB.ebPh then return false end
  local ok, v = pcall(IB.ebPh.IsShown, IB.ebPh)
  return (ok and v) and true or false
end
function EVAL_IB_TEST_CELL(i) return IB.cells[i] end
-- ★1.71.9 断言入口：网格的**真实几何**（首/末格的 Top/Left/Bottom/Right + 池子枚数）——
--   判据是「末格下缘仍在底部按钮行之上、右缘不越窗」，不是读常量（本项目「读常量 = 测自己」的老坑）。
function EVAL_IB_TEST_GRID_BOX()
  local n = table.getn(IB.cells)
  if n < 1 then return nil end
  local first, last = IB.cells[1].btn, IB.cells[n].btn
  local function num(f, o)
    local ok, v = pcall(f, o)
    return (ok and type(v) == "number") and v or nil
  end
  return {
    count = n,
    firstTop = num(first.GetTop, first), firstLeft = num(first.GetLeft, first),
    lastTop = num(last.GetTop, last), lastBottom = num(last.GetBottom, last),
    lastRight = num(last.GetRight, last),
  }
end
function EVAL_IB_TEST_CELL_COUNT() return table.getn(IB.cells) end
function EVAL_IB_TEST_STATUS_TEXT()
  if not IB.statusFS then return nil end
  local ok, t = pcall(IB.statusFS.GetText, IB.statusFS)
  return ok and t or nil
end
function EVAL_IB_TEST_GROUP_TEXT()
  if not IB.groupText then return nil end
  local ok, t = pcall(IB.groupText.GetText, IB.groupText)
  return ok and t or nil
end
function EVAL_IB_TEST_GROUP_BTN() return IB.groupBtn and IB.groupBtn.btn end
function EVAL_IB_TEST_BTN(which) return IB.btns and IB.btns[which] or nil end
function EVAL_IB_TEST_W() return IB.W end
function EVAL_IB_TEST_REFRESH_COUNT() return IB.refreshes or 0 end
function EVAL_IB_TEST_CLICK_CELL(i, mbtn) -- 1.71.15 可传 "RightButton"（默认左键，老用例不变）
  local c = IB.cells[i]
  if not (c and c.btn and type(c.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(c.btn.GetScript, c.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn(mbtn)
  return true
end
function EVAL_IB_TEST_HOVER_CELL(i)
  local c = IB.cells[i]
  if not (c and c.btn and type(c.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(c.btn.GetScript, c.btn, "OnEnter")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
function EVAL_IB_TEST_RESET()
  IB.status = nil
  IB.page = 1
  IB.group = "all"
  IB.q = "" -- ★1.73.5 过滤词也是模块级状态，重置要一起清（否则下一个用例带着上一个的词）
  if IB.eb then
    local okc, cur = pcall(IB.eb.GetText, IB.eb)
    if not (okc and cur == "") then pcall(IB.eb.SetText, IB.eb, "") end
  end
end
