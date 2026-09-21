-- EvalHelp · tools/ConsumableHelper.lua —— 消耗品助手（1.74.5）
-- 需求（用户原话）：「参照以上宠物喂食助手，添加个消耗品助手。功能相同：点击图标选择，但是他可以支持多选、
--   横向排列。点击图标使用物品，下拉多选记住多选状态。重复点击需要选中。工具类保存到 ./tools」
-- 用户对三处语义的选择（问过）：
--   ① 主图标**只负责开/关面板**（不直接使用）；
--   ② 选中的物品在**主图标旁横排成一排小图标**，**各自点用**；
--   ③ 点**已选中**的格子 = **取消选中**（标准多选开关），选择状态**落盘**（重登还在）。
--
-- 与喂食助手的关系：**同一份图标网格**（tools/IconGrid.lua，多选模式）+ **同一份位置换算**
--   （EVAL_IG_TOPLEFT）+ **同一份扫背包**（EVAL_IG_SCAN_BAGS）—— 本项目铁律「同一内容不许两处各写」。
-- 懒加载纪律与喂食助手一致：载入期零副作用（只定义函数与常量），
--   主图标/横条在**开关打开**时才建；面板在**第一次左键**时才由 IconGrid 建；登录时由
--   EVAL_CH_RESTORE 重建（用户报过喂食图标 reload 丢失，这里一开始就这么做）。
--
-- ★待实测：UseContainerItem 在本客户端是否被禁（项目记录：保护清单未文档化，若被禁会**静默失败**）
--   → 诊断命令 /eh go 消耗品 会摊开可用性与每次使用的结果。
-- 依赖全局件（只在调用时读）：EVAL_L / EVAL_SAY / EVAL_LOGLINE / EVAL_IG_* / EVAL_HELP_CONFIG.tb

local CH = {
  built = false,      -- 主图标/横条是否已建（懒加载读值口）
  btn = nil,          -- 主图标
  -- ★★1.74.14 用户：「消耗品助手 的CD 是每个物品自身的CD 而不是全局的CD」
  --   旧实现是**一个全局** cdUntil → 用了 A 就让 B/C/D 一起变灰 + 显示同一个倒计时（错）。
  --   现在每件物品各记各的：cd[物品名] = 该物品自己的 CD 截止时刻（GetTime 口径）。
  cd = {},            -- ★每件物品各自的 CD 截止时刻表
  cdTotal = {},       -- ★每件物品各自的 CD 总时长（诊断/判据用）
  cdText = nil,       -- ★倒计时文字控件（懒建）
  strip = {},         -- 横排小图标池
  stripN = 0,         -- 当前显示几枚
  side = "right",     -- 横排方向（贴屏幕右缘会翻到左侧）
  sel = {},           -- 本次运行内的选中缓存（真值仍在 cfg.tb.chUse）
  lastUse = -999,     -- 限频（服务器写动作 0.3s/笔）
  uses = 0,           -- 成功使用次数（诊断）
  fail = 0,           -- 失败次数（诊断）
  lastMsg = nil,      -- 最近一次结果（诊断）
  probeUci = nil,     -- UseContainerItem 的 pcall 探测结果（首次使用时记）
}

-- ===== 常量（单一来源） =====
-- ★1.74.5 用户（截图）：「两个助手的图标都太大了，需要和配置的图标相同」
--   ⇒ 与小地图/配置入口按钮**同尺寸 26×26**（EvalHelp.lua `mb:SetWidth(26)`）；横排小图标同尺寸保持一致。
local CH_SIZE = 26          -- 主图标边长（= 配置入口按钮）
local CH_STRIP = 26         -- 横排小图标边长（同一口径）
local CH_STRIP_GAP = 2
local CH_STRIP_STEP = CH_STRIP + CH_STRIP_GAP
local CH_STRIP_MAX = 10     -- 横排最多几枚（超出如实提示，不静默丢）
local CH_RATE = 0.3         -- 限频：服务器写动作 ≥0.3s/笔（与工具箱 TB_RATE 同口径）
local CH_BAGS = { 0, 1, 2, 3, 4 }
local CH_DEF_W, CH_DEF_H = 1024, 768
local CH_TEXT = "耗"         -- 没选中任何物品时的保底文字（不写纹理字面量）
-- ★★★1.74.5 用户：「在物品消耗完了之后显示图标灰色」——
--   用完/卖掉后物品从背包消失（EVAL_CH_FIND 找不到），但**图标要留着、灰着显示**，
--   这样一眼就知道「这一格是用完了」，而不是图标凭空消失、也不知道曾经选的是什么。
--   ⇒ 选中那一刻把它的贴图记进 cfg.tb.chTex[名字]（跟着存档走）；找不到时用记住的贴图 + 灰色顶点色。
local CH_GRAY = 0.35        -- 用完/不在背包时的灰度（三通道同值 = 纯灰）

local function chCfg()
  -- ★★★1.74.20 用户：「消耗品助手…整块按角色」——本助手的所有配置（选中列表/贴图缓存/开关/图标位置）
  --   现在存在**角色级存档** EVAL_HELP_CHAR.tb 里（唯一入口 EVAL_TB_CHAR_STORE，由 Toolbox.lua 提供）。
  if type(EVAL_TB_CHAR_STORE) ~= "function" then return nil end
  return EVAL_TB_CHAR_STORE()
end

-- ★贴图缓存（用完/卖掉后靠它把图标灰着留在原地）：必须声明在 chCfg **之后** ——
--   Lua 的 local 从声明语句之后才可见，放前面会调用到全局 nil（本项目踩过，DECL ORDER CHECK 也会抓）。
local function chCacheTex(name, tex)
  local tb = chCfg()
  if not (tb and type(name) == "string" and name ~= "" and type(tex) == "string") then return end
  if type(tb.chTex) ~= "table" then tb.chTex = {} end
  tb.chTex[name] = tex
end

local function chKnownTex(name)
  local tb = chCfg()
  if not (tb and type(tb.chTex) == "table") then return nil end
  return tb.chTex[name]
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local function chSay(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

local function chLog(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[消耗品助手] " .. tostring(msg)) end
end

local function chOn()
  local tb = chCfg()
  return (tb and tb.consumable) and true or false
end

local function chNow()
  if type(GetTime) == "function" then
    local ok, v = pcall(GetTime)
    if ok and type(v) == "number" then return v end
  end
  return 0
end

-- ===== 选中列表（真值 = cfg.tb.chUse，顺序即点击顺序） =====
function EVAL_CH_LIST()
  local tb = chCfg()
  if not tb then return {} end
  if type(tb.chUse) ~= "table" then tb.chUse = {} end
  return tb.chUse
end

local function chIndex(name)
  local list = EVAL_CH_LIST()
  for i = 1, table.getn(list) do
    if list[i] == name then return i end
  end
  return nil
end

function EVAL_CH_IS_SELECTED(name)
  return chIndex(name) ~= nil
end

function EVAL_CH_TOGGLE_SELECT(name)
  if type(name) ~= "string" or name == "" then return false end
  local list = EVAL_CH_LIST()
  local idx = chIndex(name)
  if idx then
    table.remove(list, idx) -- ★重复点击 = 取消选中（用户选择）
    chSay(string.format(L("CH_REMOVED"), name))
    chLog("取消选中：" .. name)
  else
    if table.getn(list) >= CH_STRIP_MAX then
      chSay(string.format(L("CH_STRIP_FULL"), tostring(CH_STRIP_MAX))) -- 如实说，不静默丢
      return false
    end
    table.insert(list, name)
    chLog("选中：" .. name .. "（第 " .. tostring(table.getn(list)) .. " 个）")
  end
  EVAL_CH_STRIP_REFRESH()
  return true
end

function EVAL_CH_CLEAR()
  local tb = chCfg()
  if tb then tb.chUse = {} end
  chSay(L("CH_CLEARED"))
  EVAL_CH_STRIP_REFRESH()
  return true
end

-- ===== 包格解析（按名字**实时**解析，绝不存死包格；跳过锁定格，同名取数量最大） =====
function EVAL_CH_FIND(name)
  if type(name) ~= "string" or name == "" then return nil end
  local list = {}
  if type(EVAL_IG_SCAN_BAGS) == "function" then list = EVAL_IG_SCAN_BAGS(CH_BAGS) end
  local best = nil
  for i = 1, table.getn(list) do
    local it = list[i]
    if it.name == name and not it.locked then
      local c = it.count or 1
      if not best or c > (best.count or 1) then best = { bag = it.bag, slot = it.slot, tex = it.tex,
                                                      count = c, q = it.q } end
    end
  end
  if best then
    chCacheTex(name, best.tex) -- 顺手把当前贴图记下来（用完后就靠它画灰色图标）
    return best.bag, best.slot, best.tex, best.count
  end
  return nil
end

-- ===== 使用物品（服务器写动作 → 限频；包格那一刻实时解析） =====
function EVAL_CH_USE(name)
  local tb = chCfg()
  if not tb or not tb.consumable then return false, L("CH_OFF") end
  if type(name) ~= "string" or name == "" then return false, L("CH_NO_ITEM") end
  -- ★1.74.11 CD 拦截（用户：「在公共cd 存在_的情况下增加透明遮盖.以体现不可点击.并且要正确的拦截点击触发」）：
  --   CD 还没转好（**这件物品自己的** CD > now）→ **如实拒绝**（不是静默丢，也不是让游戏静默失败）。
  --   ★放在 0.3s 限频**之前**：CD 是更优先的「不可用」判据。
  --   ★★1.74.14 按**物品名**判（每件物品各自的 CD，不是全局）—— 用了一瓶药水不该让别的水也变灰。
  local now = chNow()
  if (CH.cd[name] or 0) > now then
    chSay(L("CH_CD_BUSY"))
    return false, L("CH_CD_BUSY")
  end
  -- ★限频（服务器写动作）：0.3 秒内重复点击**如实拒绝**（不是静默丢）
  if (now - CH.lastUse) < CH_RATE then
    chSay(L("CH_BUSY"))
    return false, L("CH_BUSY")
  end
  local bag, slot = EVAL_CH_FIND(name)
  if not bag then
    CH.fail = CH.fail + 1
    CH.lastMsg = "找不到：" .. name
    chSay(string.format(L("CH_USE_FAIL"), name))
    chLog("使用失败（背包里找不到）：" .. name)
    return false, L("CH_USE_FAIL")
  end
  if type(UseContainerItem) ~= "function" then
    chSay(L("CH_NO_UCI"))
    CH.fail = CH.fail + 1
    CH.lastMsg = "无 UseContainerItem"
    return false, L("CH_NO_UCI")
  end
  -- ★★★1.74.12 推翻 1.74.11 的拆分逻辑（用户：「推翻之前的使用物品的逻辑.先分析技能编辑 物品使用的
  --   逻辑.那边工作是正常的」）。现在与**技能编辑的物品使用路径完全同构**（Engine.lua wuse 的 itemOf 分支）：
  --     ① 背包定位（EVAL_CH_FIND，与 wFindBagItem 同一口径）
  --     ② pcall(UseContainerItem, bag, slot) —— **单次调用，不做任何拆分/光标操作**
  --   ★技能编辑那条路（rule.skill = "物品:名称"）用户实测**正常**，所以这里先与它对齐；
  --     若仍出现「一次用一整组」，就说明那不是代码路径差异，而是该物品/该 API 在客户端的固有行为
  --     （届时再用探针取证定案，见 /eh go 消耗品探针）。
  local ok, err = pcall(UseContainerItem, bag, slot)
  CH.probeUci = tostring(ok) .. (ok and "" or (":" .. tostring(err)))
  CH.lastUse = now
  if not ok then
    CH.fail = CH.fail + 1
    CH.lastMsg = "pcall 失败：" .. tostring(err)
    chSay(string.format(L("CH_USE_FAIL"), name))
    return false, tostring(err)
  end
  CH.uses = CH.uses + 1
  -- ★★1.74.12 用后**延迟 0.5s** 再刷新数量（用户：「然后再使用物品之后延迟0.5s 进行更新物品数量的操作
  --   看下能否正确更新图标物品数量」）：客户端的 GetContainerItemInfo 在 UseContainerItem 之后
  --   **不会立刻更新**（本帧读到的还是旧数量）→ 立刻刷新等于没刷，数量就会「对不上」。
  CH.refreshAt = now + 0.5
  EVAL_CH_REFRESH_TICK_ENSURE()
  CH.lastMsg = string.format("用 %s @%d,%d", name, bag, slot)
  chSay(string.format(L("CH_USED"), name))
  chLog(string.format("已使用 %s @%d,%d（UseContainerItem pcall=%s）", name, bag, slot, tostring(ok)))
  -- ★1.74.11 CD 倒计时：有 CD 的物品按**真实 CD**（GetContainerItemCooldown）；
  --   没有 CD 的物品**继承公共 CD 1.5s 默认值**（用户原话）。
  local start, dur = 0, 0
  if type(GetContainerItemCooldown) == "function" then
    local okc, st, du = pcall(GetContainerItemCooldown, bag, slot)
    if okc then start, dur = tonumber(st) or 0, tonumber(du) or 0 end
  end
  local cdSec = (dur and dur > 0) and dur or 1.5
  CH.cd[name] = now + cdSec     -- ★只登记**这件物品**的 CD（每件各自）
  CH.cdTotal[name] = cdSec
  EVAL_CH_CD_REFRESH()
  EVAL_CH_STRIP_REFRESH()
  return true
end
-- ===== 自绘基础件（与其它模块同风格：WHITE8X8 纯色 + 字体链） =====
local function chSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function chText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(fs.SetFontObject, fs, fo) then ok = true break end
  end
  if not ok then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okf, ok2 = pcall(fs.SetFont, fs, fp, size, "")
      if okf and ok2 then ok = true break end
    end
  end
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

-- 按钮上的「左键/右键」分派：★本客户端 OnClick 参数形态不固定 → 四候选（主程序已实测的写法）
local function chMouseBtn(a, b)
  return (type(a) == "string" and a) or (type(b) == "string" and b)
         or (type(arg1) == "string" and arg1) or "LeftButton"
end

local function chScreen()
  local okw, sw = pcall(UIParent.GetWidth, UIParent)
  local okh, sh = pcall(UIParent.GetHeight, UIParent)
  if not (okw and type(sw) == "number" and sw > 0) then sw = CH_DEF_W end
  if not (okh and type(sh) == "number" and sh > 0) then sh = CH_DEF_H end
  return sw, sh
end

local function chApplyPos(frame, size, cx, cy)
  local sw, sh = chScreen()
  local x, y
  if type(EVAL_IG_TOPLEFT) == "function" then
    x, y = EVAL_IG_TOPLEFT(sw, sh, size, cx, cy)
  else
    x, y = sw / 2 - size / 2, -(sh / 2 - size / 2)
  end
  pcall(frame.ClearAllPoints, frame)
  pcall(frame.SetPoint, frame, "TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function chSavePos()
  local b = CH.btn
  if not b then return end
  local okl, l = pcall(b.GetLeft, b)
  local okt, t = pcall(b.GetTop, b)
  if not (okl and okt and l and t) then return end
  local s = 1
  local oks, es = pcall(b.GetEffectiveScale, b)
  if oks and type(es) == "number" and es > 0 then s = es end
  local tb = chCfg()
  if not tb then return end
  local sw, sh = chScreen()
  tb.chX = (l + CH_SIZE / 2 - sw / 2) / s
  tb.chY = (t - CH_SIZE / 2 - sh / 2) / s
end

-- ===== CD 倒计时（1.74.11 用户要求：悬浮图标显示 CD 实时倒计时特效） =====
-- ★共用格式化 EVAL_IG_CD_TEXT（IconGrid.lua；两个助手同一份）。9pt 小字，贴图标中心下方。
-- ★★1.74.14 **每件物品各自的 CD**（用户：「消耗品助手 的CD 是每个物品自身的CD 而不是全局的CD」）：
--   主图标按 list[1]（左键用的就是它）显示；横排**每枚各显示自己那件物品的** CD 与遮盖。
--   每个图标各有自己的遮盖与倒计时文字控件（都懒建）。
local function chCdWidget(holder, btn, width)
  if not holder.cdMask then
    local m = btn:CreateTexture(nil, "OVERLAY")
    chSolid(m, 0, 0, 0, 0.55) -- 半透明黑：一眼看出「这枚现在点了没用」
    m:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    pcall(m.Hide, m)
    holder.cdMask = m
  end
  if not holder.cdText then
    local fs = chText(btn, 9, 1, 0.85, 0.3) -- 金色，9pt 小字
    fs:SetPoint("CENTER", btn, "CENTER", 0, -1)
    pcall(fs.SetWidth, fs, width)
    pcall(fs.SetJustifyH, fs, "CENTER")
    holder.cdText = fs
  end
  return holder.cdMask, holder.cdText
end

-- 把一个图标的 CD 显示刷成「name 这件物品」的状态；返回**是否还在 CD 中**（供 tick 管理用）
local function chApplyCd(holder, btn, width, name, now)
  local mask, txt = chCdWidget(holder, btn, width)
  local left = (name and CH.cd[name] or 0) - now
  local str = nil
  if left > 0 and type(EVAL_IG_CD_TEXT) == "function" then str = EVAL_IG_CD_TEXT(left) end
  if str then
    pcall(mask.Show, mask)
    txt:SetText(str)
    pcall(txt.Show, txt)
    return true
  end
  pcall(mask.Hide, mask)
  txt:SetText("")
  pcall(txt.Hide, txt)
  return false
end

function EVAL_CH_CD_REFRESH()
  if not (CH.built and CH.btn) then return false end
  local now = chNow()
  local list = EVAL_CH_LIST()
  -- ★1.74.16 主图标不再代表任何物品（不「用第 1 个」）→ **它不显示 CD**；
  --   每件物品的 CD 只由它**自己那一枚横排图标**显示。
  local any = false
  if CH.cdMask then pcall(CH.cdMask.Hide, CH.cdMask) end
  if CH.cdText then CH.cdText:SetText("") pcall(CH.cdText.Hide, CH.cdText) end
  -- 横排：每枚各自（strip[i] = list[i]）
  for i = 1, CH_STRIP_MAX do
    local cell = CH.strip[i]
    if cell and cell.btn then
      if cell.btn:IsShown() then
        if chApplyCd(cell, cell.btn, CH_STRIP - 4, list[i], now) then any = true end
      else
        -- 不显示的格子：把旧状态收起来（免得下次显示时残留旧的遮盖/文字）
        if cell.cdMask then pcall(cell.cdMask.Hide, cell.cdMask) end
        if cell.cdText then pcall(cell.cdText.Hide, cell.cdText) end
      end
    end
  end
  -- tick：只要**还有任何一枚**在 CD 就保持；全没了就摘掉（不在后台空转）
  if any then
    if not CH.cdTick then
      local f = CreateFrame("Frame", nil, UIParent)
      f:SetScript("OnUpdate", function() EVAL_CH_CD_REFRESH() end)
      CH.cdTick = f
    end
  else
    if CH.cdTick then pcall(CH.cdTick.SetScript, CH.cdTick, "OnUpdate", nil) CH.cdTick = nil end
  end
  return true
end

-- ★1.74.12 延迟刷新 ticker（用后 0.5s 刷一次数量；刷完自己摘掉，不在后台空转）
-- ★步进体抽成独立函数（项目范式：EVAL_TB_TICK / EVAL_HH_STEP）——
--   判据可以**直接驱动它**（走真实刷新逻辑，不是复刻一遍），OnUpdate 只是薄壳。
function EVAL_CH_REFRESH_TICK_STEP()
  if not CH.refreshAt then return false end
  if chNow() < CH.refreshAt then return false end
  CH.refreshAt = nil
  EVAL_CH_STRIP_REFRESH() -- 重新解析包格 → 数量/灰色状态都跟着更新
  if CH.refreshTick then pcall(CH.refreshTick.SetScript, CH.refreshTick, "OnUpdate", nil) CH.refreshTick = nil end
  return true
end
function EVAL_CH_REFRESH_TICK_ENSURE()
  if CH.refreshTick then return end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetScript("OnUpdate", function() EVAL_CH_REFRESH_TICK_STEP() end)
  CH.refreshTick = f
end

-- ===== 横排小图标（用户选择：选中项在主图标旁横排，各自点用） =====
function EVAL_CH_STRIP_REFRESH()
  if not CH.built then return false end
  local list = EVAL_CH_LIST()
  local n = table.getn(list)
  if n > CH_STRIP_MAX then n = CH_STRIP_MAX end
  -- ★★★1.74.5 用户（截图）：「消耗品 在选中第二个的时候才增加 现在选中一个多了个重复的」
  --   【根因】主图标**本身就显示第 1 个选中项的图标**，而横排又把第 1 个画了一遍 ⇒ 选 1 个看着像 2 个。
  --   【修法】横排只画**第 2 个往后**（strip 第 i 枚 = 选中列表第 i+1 项）：
  --     选 1 个 → 屏幕上只有主图标 1 枚；选 2 个才多出 1 枚（正是用户要的「选中第二个时才增加」）。
  local stripCount = n -- ★1.74.12 = 全部选中项（主图标是特殊图标，不再代表第 1 项）
  if stripCount < 0 then stripCount = 0 end
  -- 横排方向：右侧放不下就整条翻到主图标左侧（夹取，绝不跑出屏幕）
  local sw = chScreen()
  local needW = 4 + stripCount * CH_STRIP_STEP
  CH.side = "right"
  if CH.btn then
    local okr, r = pcall(CH.btn.GetRight, CH.btn)
    if okr and type(r) == "number" and (r + needW) > sw then CH.side = "left" end
  end
  for i = 1, CH_STRIP_MAX do
    local s = CH.strip[i]
    if s then
      -- ★1.74.12 主图标改成**特殊图标**后，横排要画**全部**选中项（不再是 i+1 跳过第 1 项）
      local name = list[i]
      if name then
        local bag, slot, tex, cnt = EVAL_CH_FIND(name)
        s.name = name
        s.found = (bag ~= nil)
        if not tex then tex = chKnownTex(name) end -- ★用完/不在背包 → 用记住的贴图
        if tex then
          local v = s.found and 1 or CH_GRAY -- ★灰色（用完/不在背包），正常时白
          pcall(s.tex.SetTexture, s.tex, tex)
          pcall(s.tex.Show, s.tex)
          pcall(s.tex.SetVertexColor, s.tex, v, v, v)
        else
          pcall(s.tex.Hide, s.tex)
        end
        if (cnt or 1) > 1 then
          pcall(s.num.SetText, s.num, tostring(cnt))
          pcall(s.num.Show, s.num)
        else
          pcall(s.num.Hide, s.num)
        end
        local x
        if CH.side == "right" then
          pcall(s.btn.ClearAllPoints, s.btn)
          pcall(s.btn.SetPoint, s.btn, "TOPLEFT", CH.btn, "TOPRIGHT", 4 + (i - 1) * CH_STRIP_STEP, 0)
        else
          pcall(s.btn.ClearAllPoints, s.btn)
          pcall(s.btn.SetPoint, s.btn, "TOPRIGHT", CH.btn, "TOPLEFT", -4 - (i - 1) * CH_STRIP_STEP, 0)
        end
        s.btn:Show()
      else
        s.name, s.found = nil, false
        pcall(s.btn.Hide, s.btn)
      end
    end
  end
  CH.stripN = stripCount
  -- ★★1.74.12 主图标 = **特殊图标**（用户：「悬浮图标则个图标是特殊图标.在选择物品>1的情况下才往右延伸
  --   排列物品」）：主图标不再是「第 1 个物品的图标」，而是本插件自带的**物品使用**类别图标；
  --   选中项一律横排在它右侧（N=1 时紧贴 1 枚，N>1 才往右延伸成排）。
  --   ★图标是**自包含素材**（media/icons/chests，与「物品使用」类别同一张，已过 UI ICON CHECK 白名单）。
  if not CH.specialTex then
    CH.specialTex = "Interface\\AddOns\\EvalHelp\\media\\icons\\chests"
  end
  pcall(CH.tex.SetTexture, CH.tex, CH.specialTex)
  pcall(CH.tex.Show, CH.tex)
  -- 有选中项时亮起（1），一个都没选时压暗（一眼看出「还没选东西」）
  local v = (n > 0) and 1 or CH_GRAY
  pcall(CH.tex.SetVertexColor, CH.tex, v, v, v)
  pcall(CH.label.Hide, CH.label)
  return true
end
-- ===== 建 UI（懒建：开关打开时才建主图标与横排池） =====
function EVAL_CH_ENSURE()
  if CH.built and CH.btn then return CH.btn end
  local tb = chCfg() or {}
  -- 主图标（可拖动；左键 = 开/关面板）
  local b = CreateFrame("Button", nil, UIParent)
  b:SetWidth(CH_SIZE)
  b:SetHeight(CH_SIZE)
  chApplyPos(b, CH_SIZE, tb.chX, tb.chY)
  pcall(b.SetMovable, b, true)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  pcall(b.RegisterForDrag, b, "LeftButton")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  chSolid(bg, 0.06, 0.05, 0.04, 0.85)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  for i = 1, 4 do -- 四边 1px 亮边（项目配方）
    local e = b:CreateTexture(nil, "BORDER")
    chSolid(e, 0.30, 0.75, 0.45, 0.95) -- 绿色调：与「喂食」的黄框区分开
    if i == 1 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 2 then
      e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) e:SetHeight(1)
    end
    if i == 3 then
      e:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) e:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0) e:SetWidth(1)
    end
    if i == 4 then
      e:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0) e:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0) e:SetWidth(1)
    end
  end
  local tex = b:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  tex:Hide()
  local label = chText(b, 12, 0.55, 1, 0.70) -- 26px 里 12pt 才不挤
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(label.SetWidth, label, CH_SIZE)
  label:SetText(CH_TEXT)
  CH.btn, CH.tex, CH.label = b, tex, label
  b:SetScript("OnClick", function(a, b2)
    if chMouseBtn(a, b2) == "RightButton" then
      EVAL_CH_PANEL() -- 右键 = 开/关选择面板（**唯一**入口）
      return
    end
    -- ★★★1.74.30 用户：「消耗品助手图标左键点击弹窗取消」——左键**不再开选择面板**。
    --   背景：1.74.16 已定「主图标 = 帮手自己的特殊图标、不代表任何物品、不代替使用」⇒ 左键那时只剩开面板这一个作用，
    --   而它与**左键拖动图标**（RegisterForDrag("LeftButton")）争用同一按键 —— 拖动/误点就会弹窗。
    --   ⇒ 现在：**面板入口只有右键**；左键 = 只用于拖动，点击**不做任何事**（如实 no-op，不写日志刷屏）。
    --   物品使用一律走**右侧横排各枚**（各自点用）——这条不变。
    return
  end)
  b:SetScript("OnDragStart", function()
    pcall(b.StartMoving, b)
    pcall(b.StopMovingOrSizing, b)
    pcall(b.StartMoving, b) -- warm-up 两步（本客户端实测配方）
  end)
  b:SetScript("OnDragStop", function()
    pcall(b.StopMovingOrSizing, b)
    chSavePos()
    EVAL_CH_STRIP_REFRESH() -- 位置变了 → 横排方向可能要从右翻到左
  end)
  b:SetScript("OnEnter", function()
    if type(GameTooltip) ~= "table" then return end
    local list = EVAL_CH_LIST()
    local n = table.getn(list)
    pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_LEFT")
    -- ★★★1.74.29 用户：「消耗品助手显示下物品的详细信息.物品效果等」——
    --   只勾了**一件**且它在包里 → 主图标直接出**客户端原生物品 tooltip**（详情 / 效果），帮手提示补在后面；
    --   勾了多件（或有找不到的）→ 保持原来的**清单**（原生 tooltip 只画得下一件物品，硬画会把整份清单顶掉）。
    local nativeDrawn = false
    if n == 1 and type(GameTooltip.SetBagItem) == "function" then
      local nb, ns = EVAL_CH_FIND(list[1])
      if nb then
        local okN = pcall(GameTooltip.SetBagItem, GameTooltip, nb, ns)
        nativeDrawn = okN and true or false
      end
    end
    if not nativeDrawn then
      pcall(GameTooltip.ClearLines, GameTooltip)
      pcall(GameTooltip.AddLine, GameTooltip, L("TB_CONSUMABLE"), 0.55, 1, 0.70)
      if n == 0 then
        pcall(GameTooltip.AddLine, GameTooltip, L("CH_NO_ITEM"), 1, 0.6, 0.4)
      else
        for i = 1, n do
          local nm = list[i]
          local bag = EVAL_CH_FIND(nm)
          local col = bag and 0.90 or 1
          pcall(GameTooltip.AddLine, GameTooltip,
                string.format("%d. %s%s", i, tostring(nm), bag and "" or ("（" .. L("CH_GONE") .. "）")),
                col, bag and 0.90 or 0.45, bag and 0.90 or 0.45)
        end
      end
    end
    pcall(GameTooltip.AddLine, GameTooltip, L("CH_MAIN_HINT"), 0.6, 0.85, 1)
    pcall(GameTooltip.AddLine, GameTooltip, L("CH_STRIP_HINT"), 0.6, 0.85, 1)
    pcall(GameTooltip.AddLine, GameTooltip, string.format("已用 %d 次 / 失败 %d 次", CH.uses, CH.fail), 0.6, 0.6, 0.6)
    pcall(GameTooltip.Show, GameTooltip)
  end)
  b:SetScript("OnLeave", function()
    if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  -- 横排小图标池（各自点用；右键取消选中）
  CH.strip = {}
  for i = 1, CH_STRIP_MAX do
    local s = CreateFrame("Button", nil, UIParent)
    s:SetWidth(CH_STRIP)
    s:SetHeight(CH_STRIP)
    s:SetPoint("TOPLEFT", b, "TOPRIGHT", 4 + (i - 1) * CH_STRIP_STEP, 0)
    pcall(s.EnableMouse, s, true)
    pcall(s.RegisterForClicks, s, "LeftButtonUp", "RightButtonUp")
    local sbg = s:CreateTexture(nil, "BACKGROUND")
    chSolid(sbg, 0.06, 0.05, 0.04, 0.85)
    sbg:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
    sbg:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
    for k = 1, 4 do
      local e = s:CreateTexture(nil, "BORDER")
      chSolid(e, 0.30, 0.75, 0.45, 0.95)
      if k == 1 then
        e:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0) e:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0) e:SetHeight(1)
      end
      if k == 2 then
        e:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0) e:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0) e:SetHeight(1)
      end
      if k == 3 then
        e:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0) e:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0) e:SetWidth(1)
      end
      if k == 4 then
        e:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, 0) e:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0) e:SetWidth(1)
      end
    end
    local stex = s:CreateTexture(nil, "ARTWORK")
    stex:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
    stex:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
    stex:Hide()
    local snum = chText(s, 9, 1, 0.96, 0.80)
    snum:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -1, 1)
    pcall(snum.SetWidth, snum, CH_STRIP - 4)
    pcall(snum.SetJustifyH, snum, "RIGHT")
    pcall(snum.SetNonSpaceWrap, snum, false)
    local cell = { btn = s, tex = stex, num = snum, name = nil, found = false }
    s:SetScript("OnClick", function(a, b2)
      local nm = cell.name
      if not nm then return end
      if chMouseBtn(a, b2) == "RightButton" then
        EVAL_CH_TOGGLE_SELECT(nm) -- 右键 = 取消选中（与左边对称，方便）
      else
        EVAL_CH_USE(nm) -- ★左键 = 使用这个消耗品（用户选择：横排各自点用）
      end
    end)
    s:SetScript("OnEnter", function()
      if type(GameTooltip) ~= "table" or not cell.name then return end
      pcall(stex.SetVertexColor, stex, 1, 0.92, 0.55)
      local bag, slot, _, cnt = EVAL_CH_FIND(cell.name)
      pcall(GameTooltip.SetOwner, GameTooltip, s, "ANCHOR_RIGHT")
      -- ★★★1.74.29 用户：「消耗品助手显示下物品的详细信息.物品效果等」——
      --   找到物品就出**客户端原生物品 tooltip**（`SetBagItem`：名称 / 品质 / 类型 / 「Use:」效果 / 持续时间 / 售价），
      --   帮手自己的信息（数量 · 包格 · 操作提示）**补在它后面**；找不到物品时退回纯文本（如实说「没了」）。
      --   ★顺序不能反：`SetBagItem` 会**顶掉已有行** ⇒ 原生那一笔必须先画、AddLine 只能在后。
      --   ★API 真伪：`SetBagItem` 在官方 API 索引里（tools/IconGrid.lua 的类型过滤同款调用，1.74.28 已实测可用）。
      local nativeDrawn = false
      if bag and type(GameTooltip.SetBagItem) == "function" then
        local okN = pcall(GameTooltip.SetBagItem, GameTooltip, bag, slot)
        nativeDrawn = okN and true or false
      end
      if not nativeDrawn then
        pcall(GameTooltip.ClearLines, GameTooltip)
        pcall(GameTooltip.AddLine, GameTooltip, tostring(cell.name), 0.55, 1, 0.70)
      end
      if bag then
        pcall(GameTooltip.AddLine, GameTooltip,
              string.format("%s ×%s  [%s,%s]", tostring(cell.name), tostring(cnt or 1),
                            tostring(bag), tostring(slot)), 0.85, 0.85, 0.85)
      else
        pcall(GameTooltip.AddLine, GameTooltip,
              string.format("%s（%s）", tostring(cell.name), L("CH_GONE")), 1, 0.45, 0.45)
      end
      pcall(GameTooltip.AddLine, GameTooltip, L("CH_STRIP_HINT"), 0.55, 0.90, 0.55)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    s:SetScript("OnLeave", function()
      local v = cell.found and 1 or CH_GRAY -- ★用完的保持灰，别被悬停复原成白
      pcall(stex.SetVertexColor, stex, v, v, v)
      if type(GameTooltip) == "table" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    s:Hide()
    CH.strip[i] = cell
  end
  CH.built = true
  chLog("消耗品助手 UI 已建立（懒建：开关打开才建主图标 + 横排池）")
  EVAL_CH_STRIP_REFRESH()
  return b
end

-- ===== 面板（多选，共用 IconGrid） =====
function EVAL_CH_PANEL()
  if not (CH.built and CH.btn) then return false end
  return EVAL_IG_OPEN({
    key = "consumable",
    anchor = CH.btn,
    title = L("CH_PANEL_TITLE"),
    hint = L("CH_HINT"),
    mode = "multi",
    candidates = function()
      if type(EVAL_IG_SCAN_BAGS) ~= "function" then return {}, 0 end
      -- ★1.74.28 弹窗候选**开类型过滤**（用户：「弹窗选的物品项目要过滤一下.不要显示武器,装备.
      --   灰色物品,草药,矿物,任务物品,材料等等非可使用的物品」）—— 只有这条用户点击驱动的路径开，
      --   因为它会走 tooltip 兜底（贵调用）；`EVAL_CH_FIND` 那种按名字解析包格的路径不受影响。
      return EVAL_IG_SCAN_BAGS(CH_BAGS, { classify = true })
    end,
    isSelected = function(it) return EVAL_CH_IS_SELECTED(it.name) end,
    onToggle = function(it)
      EVAL_CH_TOGGLE_SELECT(it.name)
      EVAL_CH_STRIP_REFRESH()
    end,
    btnAText = L("CH_CLEAR"),
    btnA = function()
      EVAL_CH_CLEAR()
      EVAL_IG_REFRESH()
    end,
  })
end

-- ===== 总闸门（工具箱开关的即时副作用） =====
function EVAL_CH_TOGGLE()
  if not chOn() then
    if CH.btn then pcall(CH.btn.Hide, CH.btn) end
    for i = 1, CH_STRIP_MAX do
      if CH.strip[i] then pcall(CH.strip[i].btn.Hide, CH.strip[i].btn) end
    end
    if type(EVAL_IG_IS_SHOWN) == "function" and EVAL_IG_IS_SHOWN() then
      local st = EVAL_TEST_IG_STATE()
      if type(st) == "table" and st.key == "consumable" then EVAL_IG_HIDE() end
    end
    chSay(L("CH_OFF_MSG"))
    chLog("总闸门关闭 → 主图标与横排收起（帧保留但不可见）")
    return false
  end
  EVAL_CH_ENSURE()
  EVAL_CH_STRIP_REFRESH()
  if CH.btn then pcall(CH.btn.Show, CH.btn) end
  chSay(L("CH_ON_MSG"))
  chLog("总闸门打开 → 主图标已显示（选中 " .. tostring(table.getn(EVAL_CH_LIST())) .. " 项）")
  return true
end

-- ★登录恢复（与喂食助手同一条纪律：配置开着就重建，关着一个帧都不建）
function EVAL_CH_RESTORE()
  local tb = chCfg()
  if not (tb and tb.consumable) then return false end
  if not (CH.built and CH.btn) then
    EVAL_CH_ENSURE()
  else
    chApplyPos(CH.btn, CH_SIZE, tb.chX, tb.chY)
  end
  EVAL_CH_STRIP_REFRESH()
  if CH.btn then pcall(CH.btn.Show, CH.btn) end
  chLog("登录恢复：消耗品助手开关是开的 → 图标已重建（位置 " .. tostring(tb.chX) .. "," .. tostring(tb.chY) .. "）")
  return true
end
-- ===== 诊断命令（/eh go 消耗品 ；与项目「能做成命令就别让用户手工复现」一致） =====
local function chAvail(name)
  local v = _G[name]
  if type(v) == "function" then return "function✓" end
  return tostring(type(v))
end

function EVAL_CH_CMD(msg)
  msg = tostring(msg or "")
  local sub = string.match(msg, "^go 消耗品%s*(.-)%s*$")
  if sub == nil then
    chSay("用法：/eh go 消耗品（状态）｜ 消耗品 用 <物品名> ｜ 消耗品 清 ｜ 消耗品探针 [物品名]")
    return false
  end
  local useName = string.match(sub, "^用%s*(.-)%s*$")
  if useName and useName ~= "" then
    EVAL_CH_USE(useName)
    return true
  end
  if sub == "清" then
    EVAL_CH_CLEAR()
    return true
  end
  -- ★1.74.11 取证命令（用户：「每次使用物品的时候是使用一个.现在点击会把物品全部使用完.在仔细看下API」）：
  --   /eh go 消耗品探针 [物品名] —— 实测 UseContainerItem 对堆叠物品**一次真的用几个**
  --   （用前/用后数量差）+ SplitContainerItem(bag,slot,1) 能不能拆出 1 个。
  --   ★判据 = 差值：1 = 正常（和游戏原生一致）；> 1 = 本客户端把 API 改成「用整组」（要绕）。
  -- ★1.74.28 「验证可行性」入口：/eh go 消耗品探针 过滤 —— 把背包里每件物品的类型判定依据摊开
  if sub == "探针 过滤" or sub == "过滤" then
    if type(EVAL_IG_FILTER_REPORT) == "function" then return EVAL_IG_FILTER_REPORT(CH_BAGS, chSay) end
    return false
  end
  local probeName = string.match(sub, "^探针%s*(.-)%s*$")
  if probeName ~= nil then
    local target = (probeName ~= "") and probeName or nil
    local found = nil
    if target then
      local bag, slot, _, cnt = EVAL_CH_FIND(target)
      if bag then found = { name = target, bag = bag, slot = slot, cnt = cnt or 1 } end
    else
      for bag = 0, 4 do
        for slot = 1, 32 do
          local okl, link = pcall(GetContainerItemLink, bag, slot)
          if okl and link then
            local nm = string.match(link, "%[(.-)%]")
            if nm then
              local _b, _s, _t, cnt = EVAL_CH_FIND(nm)
              if (cnt or 1) > 1 then found = { name = nm, bag = bag, slot = slot, cnt = cnt or 1 } break end
            end
          end
        end
        if found then break end
      end
    end
    if not found then
      chSay(target and ("探针：背包里找不到「" .. target .. "」") or "探针：背包里没有堆叠 > 1 的物品")
      return true
    end
    local bag, slot, c0 = found.bag, found.slot, found.cnt
    chSay(string.format("=== 消耗品探针：%s @%d,%d 数量 %d（⚠️ 会真的用掉 1 个来取证）===", found.name, bag, slot, c0))
    -- ① UseContainerItem 一次用几个？
    local okUse = pcall(UseContainerItem, bag, slot)
    -- ★★测准（上一版探针有缺陷）：整组用完后那个格子**变空**，GetContainerItemInfo 返回 nil，
    --   旧写法把 c1 保持成 c0 → 把「整组用光」误报成「用了 0 个」（两者都是同一个显示）。
    --   现在**先看格子还在不在**：空 = 整组用光（used = c0）；还在 = 用差值。
    local c1, gone = nil, false
    if type(GetContainerItemInfo) == "function" then
      local okc, _t, c = pcall(GetContainerItemInfo, bag, slot)
      if okc and tonumber(c) then c1 = tonumber(c)
      elseif okc then gone = true end -- 有返回但数量读不出 / 物品没了
    end
    if c1 == nil then
      -- 再看 link：link 也没了 = 这个格子空了
      local okl2, lk2 = pcall(GetContainerItemLink, bag, slot)
      if okl2 and not lk2 then gone = true end
    end
    local used
    if gone then used = c0 -- 格子空了 = **整组用光**
    else used = c0 - (c1 or c0) end
    CH.probeUseN = used -- ★实测结果记进状态（判据能读；也是「一次用几个」的唯一权威来源）
    chSay(string.format("UseContainerItem pcall=%s → 用后：%s → **一次用了 %d 个**%s",
      tostring(okUse), gone and "格子已空" or ("数量 " .. tostring(c1)), used,
      (used == 1) and "（正常：一次用一个，和游戏原生一致）"
        or ((used == 0) and "（**没用**：这次调用什么都没发生）"
        or ("（**一次用了 " .. used .. " 个** → 不是 1 个）"))))
    -- ② SplitContainerItem 能不能拆 1 个？（如果还有剩）
    if c1 > 1 then
      if type(SplitContainerItem) == "function" then
        local okSplit = pcall(SplitContainerItem, bag, slot, 1)
        chSay(string.format("SplitContainerItem(1) pcall=%s（能拆 = 绕「用整组」的路通）", tostring(okSplit)))
      else
        chSay("SplitContainerItem **不存在**（绕「用整组」的路断）")
      end
    end
    -- ★1.74.11 数量核对（用户：「主按钮上的数量没有正确显示」）：
    --   直接读那组物品的真实 count（GetContainerItemInfo 第 2 返回），
    --   对比 EVAL_CH_FIND 的解析结果 —— 不一致就是「count 被读错」。
    if type(GetContainerItemInfo) == "function" then
      local okc, _t, rawCnt, _lk, _q = pcall(GetContainerItemInfo, bag, slot)
      chSay(string.format("数量核对：GetContainerItemInfo 原始 count=%s ｜ EVAL_CH_FIND 解析 count=%s%s",
        tostring(rawCnt), tostring(c0),
        (tonumber(rawCnt) == tonumber(c0)) and "（一致）" or "（**不一致** → count 被读错）"))
    end
    chSay(string.format("接口：UseContainerItem=%s ｜ SplitContainerItem=%s",
      chAvail("UseContainerItem"), chAvail("SplitContainerItem")))
    return true
  end
  -- 状态 / 探针
  local tb = chCfg() or {}
  local list = EVAL_CH_LIST()
  chSay("— 消耗品助手 状态 —")
  chSay("接口：UseContainerItem=" .. chAvail("UseContainerItem") ..
        " ｜ GetContainerItemInfo=" .. chAvail("GetContainerItemInfo") ..
        " ｜ EVAL_IG_OPEN=" .. chAvail("EVAL_IG_OPEN"))
  chSay("总闸门 consumable=" .. tostring(tb.consumable) .. " ｜ 已建 UI=" .. tostring(CH.built) ..
        " ｜ 位置=" .. tostring(tb.chX) .. "," .. tostring(tb.chY))
  chSay(string.format("选中 %d 项（最多 %d）：", table.getn(list), CH_STRIP_MAX))
  for i = 1, table.getn(list) do
    local nm = list[i]
    local bag, slot, _, cnt = EVAL_CH_FIND(nm)
    chSay(string.format("  %d. %s → %s", i, tostring(nm),
          bag and string.format("@%d,%d ×%s", bag, slot, tostring(cnt or 1)) or "**背包里找不到**"))
  end
  chSay(string.format("使用：成功 %d 次 / 失败 %d 次 ｜ 最近：%s ｜ UseContainerItem 上次 pcall=%s",
        CH.uses, CH.fail, tostring(CH.lastMsg), tostring(CH.probeUci)))
  chSay("横排方向=" .. tostring(CH.side) .. " ｜ 显示 " .. tostring(CH.stripN) .. " 枚")
  local st = EVAL_TEST_IG_STATE()
  if type(st) == "table" and st.key == "consumable" then
    chSay("面板：显示=" .. tostring(st.shown) .. " ｜ 页 " .. tostring(st.page + 1) .. "/" .. tostring(st.pages) ..
          " ｜ 本页 " .. tostring(st.filled) .. " 格 ｜ 已选角标 " .. tostring(st.selCount))
  end
  return true
end

-- ===== 测试读值口（读真实控件 / 真实配置，绝不复刻逻辑） =====
function EVAL_TEST_CH_STATE()
  local tb = chCfg() or {}
  local list = EVAL_CH_LIST()
  local shown = nil
  if CH.btn and type(CH.btn.IsShown) == "function" then shown = CH.btn:IsShown() and true or false end
  local stripShown = 0
  for i = 1, CH_STRIP_MAX do
    local s = CH.strip[i]
    if s and s.btn and s.btn:IsShown() then stripShown = stripShown + 1 end
  end
  local mtex = nil
  if CH.tex then mtex = rawget(CH.tex, "__tex") end
  -- ★灰显判据读**真控件的顶点色**（不复刻逻辑）：灰 = 三通道同为 CH_GRAY
  local mg, mgg, mgb, mshown = nil, nil, nil, nil
  if CH.tex then
    if type(CH.tex.GetVertexColor) == "function" then
      local okg, r1, g1, b1 = pcall(CH.tex.GetVertexColor, CH.tex)
      if okg then mg, mgg, mgb = r1, g1, b1 end
    end
    if type(CH.tex.IsShown) == "function" then mshown = CH.tex:IsShown() and true or false end
  end
  return { built = CH.built, shown = shown, on = tb.consumable and true or false, mainTex = mtex,
           mainGray = mg, mainGrayG = mgg, mainGrayB = mgb, mainShown = mshown,
           list = list, count = table.getn(list), stripN = CH.stripN, stripShown = stripShown,
           side = CH.side, uses = CH.uses, fail = CH.fail, lastMsg = CH.lastMsg,
           hasUci = (type(UseContainerItem) == "function"),
           -- ★1.74.11 CD 倒计时读值口（判据要钉「真实 CD / 无 CD 继承 1.5s / CD 结束摘 OnUpdate」）
           -- ★1.74.14 **每件物品各自的 CD**（判据要能按物品名查，不是全局一个值）
           cd = CH.cd, cdTotal = CH.cdTotal,
           cdTextShown = (CH.cdText and CH.cdText.IsShown and CH.cdText:IsShown() == true) or false,
           cdTickOn = (CH.cdTick ~= nil),
           -- ★1.74.11 遮盖读值口（判据要钉「CD 时遮盖显示 / CD 结束遮盖收起」）
           cdMaskShown = (CH.cdMask and CH.cdMask.IsShown and CH.cdMask:IsShown() == true) or false,
           -- ★1.74.11 探针实测结果（「一次用几个」的唯一权威来源）
           probeUseN = CH.probeUseN,
           -- ★1.74.12 延迟刷新读值口（用后 0.5s 刷一次数量）
           refreshAt = CH.refreshAt, refreshTickOn = (CH.refreshTick ~= nil) }
end

-- ★1.74.14 读值口：**按物品名**查该物品自己的 CD 剩余秒数（判据用；不改状态）
function EVAL_TEST_CH_CD_OF(name)
  if type(name) ~= "string" then return nil end
  local until_ = CH.cd[name]
  if not until_ then return 0 end
  local left = until_ - chNow()
  return (left > 0) and left or 0
end

function EVAL_TEST_CH_CLICK_MAIN(button)
  if not (CH.btn and type(CH.btn.GetScript) == "function") then return false end
  local ok, fn = pcall(CH.btn.GetScript, CH.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, CH.btn, button or "LeftButton")
  return okc, err
end

-- ★1.74.29 断言入口：走**真实的** OnEnter（悬停 = 出物品详情那条路径），不另写一套实现。
function EVAL_TEST_CH_STRIP_ENTER(i)
  local c = CH.strip and CH.strip[i]
  if not (c and c.btn and c.btn.GetScript) then return nil end
  local f = c.btn:GetScript("OnEnter")
  if type(f) ~= "function" then return nil end
  f()
  return true
end
-- ★1.74.29 断言入口：主图标悬停（只勾一件且找得到 → 应出原生物品 tooltip）
function EVAL_TEST_CH_MAIN_ENTER()
  if not (CH.btn and CH.btn.GetScript) then return nil end
  local f = CH.btn:GetScript("OnEnter")
  if type(f) ~= "function" then return nil end
  f()
  return true
end
function EVAL_TEST_CH_STRIP_CLICK(i, button)
  local s = CH.strip[i]
  if not (s and s.btn) then return false end
  local ok, fn = pcall(s.btn.GetScript, s.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  local okc, err = pcall(fn, s.btn, button or "LeftButton")
  return okc, err
end

function EVAL_TEST_CH_STRIP_INFO(i)
  local s = CH.strip[i]
  if not s then return nil end
  -- ★别写成 `(cond) and (x and true or false) or nil`：隐藏时会得到 **nil** 而不是 false（Lua and/or 陷阱，项目有记录）
  local shown = nil
  if type(s.btn.IsShown) == "function" then shown = s.btn:IsShown() and true or false end
  local l, t, w, h = nil, nil, nil, nil
  local ok1, v1 = pcall(s.btn.GetLeft, s.btn) if ok1 then l = v1 end
  local ok2, v2 = pcall(s.btn.GetTop, s.btn) if ok2 then t = v2 end
  local ok3, v3 = pcall(s.btn.GetWidth, s.btn) if ok3 then w = v3 end
  local ok4, v4 = pcall(s.btn.GetHeight, s.btn) if ok4 then h = v4 end
  local texPath, gr, gg, gb, texShown = nil, nil, nil, nil, nil
  if s.tex then
    texPath = rawget(s.tex, "__tex")
    if type(s.tex.GetVertexColor) == "function" then
      local okg, r1, g1, b1 = pcall(s.tex.GetVertexColor, s.tex)
      if okg then gr, gg, gb = r1, g1, b1 end
    end
    if type(s.tex.IsShown) == "function" then texShown = s.tex:IsShown() and true or false end
  end
  -- ★1.74.13 补「数量文字」读值口：数量刷新（用后 0.5s）唯一的可断言证据就是它，
  --   测试够不着 local 控件 ⇒ 必须从读值口给（本项目：测试够不着生产 local 就加钩子，别复刻逻辑）。
  local numTxt = nil
  if s.num and type(s.num.GetText) == "function" then
    local okn, nv = pcall(s.num.GetText, s.num)
    if okn then numTxt = nv end
  end
  -- ★1.74.14 补「**这一枚自己的** CD 遮盖/倒计时」读值口（判据要能证明「每件物品各自 CD」：
  --   A 在 CD → A 那枚有遮盖；B 不在 CD → B 那枚没有遮盖）
  local maskShown = (s.cdMask and s.cdMask.IsShown and s.cdMask:IsShown() == true) or false
  local cdTxt = nil
  if s.cdText and type(s.cdText.GetText) == "function" then
    local okt, tv = pcall(s.cdText.GetText, s.cdText)
    if okt then cdTxt = tv end
  end
  return { shown = shown, name = s.name, found = s.found, left = l, top = t, w = w, h = h, tex = texPath,
           gray = gr, grayG = gg, grayB = gb, texShown = texShown, num = numTxt,
           cdMaskShown = maskShown, cdText = cdTxt }
end

function EVAL_TEST_CH_GEOM()
  if not CH.btn then return nil end
  local okl, l = pcall(CH.btn.GetLeft, CH.btn)
  local okt, t = pcall(CH.btn.GetTop, CH.btn)
  local okw, w = pcall(CH.btn.GetWidth, CH.btn)
  local okh, h = pcall(CH.btn.GetHeight, CH.btn)
  return { left = okl and l or nil, top = okt and t or nil, w = okw and w or nil, h = okh and h or nil }
end

function EVAL_TEST_CH_RESET_UI()
  -- 只让下一次 ENSURE 重新走「懒建 + 定位」（测登录恢复用）
  CH.built, CH.btn, CH.tex, CH.label, CH.strip, CH.stripN = false, nil, nil, nil, {}, 0
end

function EVAL_CH_TEST_RESET_TIMERS()
  CH.lastUse = -999
  -- ★1.74.13 连同 **CD 状态**一起复位：cdUntil 与 lastUse 都是**绝对时刻**口径，
  --   而各用例的 TEST.time 各自独立（相邻用例常出现「时间倒流」）→ 上一组留下的 CD
  --   会把下一组的第一次使用当「CD 未转好」挡掉（本轮实测 got=false）。
  --   ★判据同限频：凡模块级可变状态，用例开头就该有办法复位。
  CH.cd, CH.cdTotal = {}, {}
end



