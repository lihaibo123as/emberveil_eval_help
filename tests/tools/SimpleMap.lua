-- tests/tools/SimpleMap.lua
-- 【工具模块自带测试】地图工具（tools/SimpleMap.lua）的断言组。
-- 用户 1.74.35-3：「缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图
--   切换到其他地图后自动刷新到当前地图,,默认关闭.」
--   ⇒ 本模块的测试三件套都归模块自己管：**读值口**在 tools/SimpleMap.lua（EVAL_SM_TEST_*）·
--     **断言组**就是本文件（组 224）· **源码检查**在同级 tests/checks/SimpleMap.js。
-- ★纪律（四条，越界即静默失效）：
--   ① 本文件**不进 toc、不随包发布**——只在测试里被 harness 加载；
--   ② 断言一律用 **EVAL_TEST_EQ**（test_assert.lua 暴露的**同一个** eq）⇒ 失败格式与其它组逐字一致；
--   ③ **最后一行必须调 `EVAL_TEST_MOD_DONE("SimpleMap")`** —— 「这个文件真的跑到底了」的握手信号；
--   ④ 夹具**自建自清**（本组会改 SM_CFG.guiReopen 与 tbCfg().simpleMap，收尾都还原）。
local eq = EVAL_TEST_EQ

-- ===== 组 224（1.74.35-3）：缩放大地图那一行的 [设置] 下拉 = 「GUI重开」（★默认关 + 副作用提示）=====
do
  -- 夹具自建：记下要还原的东西
  -- ★★★1.74.36-2：这里原来写的是 `type(tbCfg) == "function"` ⇒ **永远 false**（tbCfg 是 Toolbox 的 local）
  --   ⇒ 下面那条.round-trip 断言走进「（无 tbCfg，跳过）」分支 = **静默逃生口**，真机上勾选框点不动而套件全绿。
  --   现在改成：先断言出口存在（EVAL_TB_CFG），再走真实的读写往返。
  local tb0 = (type(EVAL_TB_CFG) == "function") and EVAL_TB_CFG() or nil
  eq(type(tb0) == "table", true, "⑩前置：EVAL_TB_CFG() 可用（模块拿不到配置 = 勾选框永远勾不上，这条不许跳过）")
  local savedOn = tb0 and tb0.simpleMap or nil
  local function restore224()
    if tb0 then tb0.simpleMap = savedOn end
    if type(EVAL_SM_GUIREOPEN_SET) == "function" then pcall(EVAL_SM_GUIREOPEN_SET, false) end -- nil/false 都是「关」
  end

  -- ① 读值口在位（缺一个 = 后面的断言会静默跳过，先自己建立前置）
  local ports = { "EVAL_SM_TEST_GUIREOPEN", "EVAL_SM_TEST_GUI_CALLS", "EVAL_SM_TEST_GUI_CALLS_RESET",
                  "EVAL_SM_TEST_MENU_RAW", "EVAL_SM_TEST_ROW", "EVAL_SM_TEST_MIGRATE", "EVAL_SM_SUMMARY",
                  "EVAL_SM_GUIREOPEN_ON", "EVAL_SM_GUIREOPEN_SET", "EVAL_SM_MENU", "EVAL_SM_SET", "EVAL_SM_ENABLED",
                  "EVAL_SM_TEST_APPLY", "EVAL_SM_TEST_DEFAULTS", "EVAL_SM_TEST_PANEL", "EVAL_SM_DEF_TIP" }
  local miss = 0
  for i = 1, table.getn(ports) do if type(_G[ports[i]]) ~= "function" then miss = miss + 1 end end
  eq(miss, 0, "①前置：模块读值口/入口全部在位（缺 " .. miss .. " 个）")

  -- ② ★★★默认关：老存档里**没有**这两个键时必须是「关」（用户明确：「默认关闭」）
  local v1, on1 = EVAL_SM_TEST_MIGRATE(nil)
  eq(on1, false, "②★★★默认关：真值没写过（nil）⇒ GUI重开 = 关（实测 " .. tostring(on1) .. "）")
  eq(v1 == nil or v1 == false, true, "②真值不写就不落存档（nil/false 都算关）")

  -- ③ 一次性迁移：显式开过的用户**尊重**其选择，其余一律关
  local _, onT = EVAL_SM_TEST_MIGRATE(true)
  eq(onT, true, "③老存档显式 true（原「显示GUI」勾过）⇒ 迁移为开")
  local _, onF = EVAL_SM_TEST_MIGRATE(false)
  eq(onF, false, "③老存档显式 false ⇒ 迁移为关")
  local _, onE = EVAL_SM_TEST_MIGRATE({})
  eq(onE, false, "③老存档空表（1.74.35 的 9 组多选全不勾）⇒ 迁移为关")
  local _, onN = EVAL_SM_TEST_MIGRATE({ a = true })
  eq(onN, true, "③老存档非空表（至少勾了一组）⇒ 迁移为开")

  -- ④ 老键必须被清干净（不留没人读的配置）
  local k1, k2, k3, k4 = EVAL_SM_TEST_LEGACY_KEYS()
  eq(k1 == nil and k2 == nil and k3 == nil and k4 == nil, true,
    "④老键 showGUI/keepUI/keepUIStat/keepUIMode 全部已清（实测 " .. tostring(k1) .. "/" .. tostring(k2) .. "/" .. tostring(k3) .. "/" .. tostring(k4) .. "）")

  -- ⑤ 菜单内容 = 设置下拉的那一项（与行渲染同源；勾选态现算）
  pcall(EVAL_SM_GUIREOPEN_SET, false)
  local m1 = EVAL_SM_TEST_MENU_RAW()
  eq(type(m1) == "table" and table.getn(m1.items) == 1, true, "⑤菜单恰好 1 项（实测 " .. tostring(type(m1) == "table" and table.getn(m1.items) or "?") .. "）")
  eq(type(m1) == "table" and m1.keys[1], "guiReopen", "⑤菜单第 1 项的键是 guiReopen")
  eq(type(m1) == "table" and m1.tipLines >= 2, true, "⑤菜单项带**多行提示**（副作用说明；实测 " .. tostring(type(m1) == "table" and m1.tipLines or "?") .. " 行）")
  eq(m1.selN, 0, "⑤关着时菜单不勾（默认关）")
  pcall(EVAL_SM_GUIREOPEN_SET, true)
  local m2 = EVAL_SM_TEST_MENU_RAW()
  eq(m2.selN, 1, "⑤开着时菜单勾上（勾选态由真值现算，不留第二份状态）")

  -- ⑥ 提示文本非空且**含用户要的那句副作用**（走真实取词函数，不自造文案）
  local tips = EVAL_SM_GUIREOPEN_TIPS()
  eq(type(tips) == "table" and table.getn(tips) >= 3, true, "⑥提示至少 3 行（实测 " .. tostring(type(tips) == "table" and table.getn(tips) or "?") .. "）")
  local joined = table.concat(tips, " | ")
  eq(string.find(joined, "刷新") ~= nil, true, "⑥提示里写明「会被自动刷新」（原文：" .. string.sub(joined, 1, 60) .. "…）")

  -- ⑦ ★★★核心判据：关掉时**一个 GUI 动作都不发**；开着时才会发（走真实开图路径 featKeep/featApply）
  --   ★1.74.36-3 起触发方式换了：`EVAL_SM_SET(true)` 现在会**套默认档**（含「GUI重开 不启用」）⇒
  --     「勾上 GUI重开 之后开图会不会重显」必须用**不碰配置**的开图触发器 `EVAL_SM_TEST_APPLY()`；
  --     真实用户流程也是这个顺序：先开模块 → 再在下拉里勾 GUI重开 → 然后开图。
  pcall(EVAL_SM_SET, true)  -- 先开模块（此刻已套默认档：GUI重开 = 关）
  pcall(EVAL_SM_GUIREOPEN_SET, false)
  EVAL_SM_TEST_GUI_CALLS_RESET()
  EVAL_SM_TEST_APPLY()
  local offCalls = EVAL_SM_TEST_GUI_CALLS()
  eq(offCalls, 0, "⑦★★★关掉 GUI重开 ⇒ 开图路径上**一次重显都不发**（实测 " .. tostring(offCalls) .. " 次）")
  pcall(EVAL_SM_GUIREOPEN_SET, true)
  EVAL_SM_TEST_GUI_CALLS_RESET()
  EVAL_SM_TEST_APPLY()
  local onCalls = EVAL_SM_TEST_GUI_CALLS()
  eq(onCalls > 0, true, "⑦开着 GUI重开 ⇒ 开图路径真的会重显最外层 GUI（实测 " .. tostring(onCalls) .. " 次）")

  -- ⑧ 行内摘要现算（勾选/滚轮改完立刻重画；不复刻逻辑，直接问模块）
  pcall(EVAL_SM_GUIREOPEN_SET, false)
  local sum1 = EVAL_SM_SUMMARY()
  eq(string.find(sum1, "GUI重开 关") ~= nil, true, "⑧摘要现算 =「… · GUI重开 关」（实测：" .. tostring(sum1) .. "）")
  pcall(EVAL_SM_GUIREOPEN_SET, true)
  eq(string.find(EVAL_SM_SUMMARY(), "GUI重开 开") ~= nil, true, "⑧勾上后摘要立刻变「开」")

  -- ⑨ 行登记（工具箱渲染段按名字取；两边必须是**同一个函数**）
  local rowFn = EVAL_SM_TEST_ROW()
  eq(type(rowFn) == "function", true, "⑨模块交出的是行渲染函数")
  local reg = rawget(_G, "EVAL_TB_MOD_ROWS")
  eq(type(reg) == "table" and reg["simpleMap"] == rowFn, true, "⑨EVAL_TB_MOD_ROWS[\"simpleMap\"] 已登记且就是它（函数口 EVAL_SM_TB_REGISTER 写同一份真值）")
  pcall(EVAL_SM_TB_REGISTER)
  eq(rawget(_G, "EVAL_TB_MOD_ROWS")["simpleMap"] == rowFn, true, "⑨再登记一次仍是同一个函数（幂等）")

  -- ⑩ 单一真值：开关（勾选框）读写都落在 tbCfg().simpleMap，与 EVAL_SM_ENABLED() 同源
  if tb0 then
    pcall(EVAL_SM_SET, true)
    eq(tb0.simpleMap == true, true, "⑩勾上 ⇒ 配置真值 tbCfg().simpleMap = true（勾选框读的同一处）")
    eq(EVAL_SM_ENABLED(), true, "⑩EVAL_SM_ENABLED()（勾选框的读口）= 同一份真值")
    pcall(EVAL_SM_SET, false)
    eq(tb0.simpleMap == false and EVAL_SM_ENABLED() == false, true, "⑩取消勾选 ⇒ 真值 false（不是 nil，避免「读到 nil」歧义）")
  else
    eq(false, true, "⑩★不该走到这里：EVAL_TB_CFG() 不可用（配置真值读不到，勾选框必然是坏的）")
  end

  -- ★1.74.36 用户：「配置项不需要再外部显示，已经在 tooltip 设置内显示了」
  --   ① 行上**不许**再显示「缩放 … · 透明 … · GUI重开 …」这串摘要（读真控件的显示状态）
  local rtxt224 = EVAL_TB_TEST_ROW_TEXT("simpleMap")
  eq(type(rtxt224) == "table" and rtxt224.extraShown == false, true,
    "㉑★★★ 行上**不再**显示配置摘要（配置项只留在 [设置] 悬停里；实测 extraShown=" ..
    tostring(type(rtxt224) == "table" and rtxt224.extraShown or nil) .. "）")
  --   ② 走**真实 OnEnter**，从真 GameTooltip 的记账里读到那串摘要（配置项没有丢）
  local sbtn224 = (type(EVAL_TEST_TB_ADD_BTN_FOR) == "function") and EVAL_TEST_TB_ADD_BTN_FOR("simpleMap") or nil
  eq(sbtn224 ~= nil, true, "㉑前置：读得到「缩放大地图」那一行的 [设置] 按钮")
  if sbtn224 then
    local ent224 = sbtn224:GetScript("OnEnter")
    eq(type(ent224) == "function", true, "㉑★★ [设置] 挂了真实 OnEnter（由模块挂的）")
    TEST.tipLines = nil
    if type(ent224) == "function" then pcall(ent224) end
    local tip224 = ""
    for _, ln in ipairs(TEST.tipLines or {}) do tip224 = tip224 .. tostring(ln.text or "") .. "\n" end
    eq(string.find(tip224, tostring(EVAL_SM_SUMMARY()), 1, true) ~= nil, true,
      "㉑★★★ 悬停说明里带着当前配置（「" .. tostring(EVAL_SM_SUMMARY()) .. "」）")
    local lv224 = 0
    for _, ln in ipairs(EVAL_SM_GUIREOPEN_TIPS()) do
      if string.find(tip224, tostring(ln), 1, true) ~= nil then lv224 = lv224 + 1 end
    end
    eq(lv224 >= 1, true, "㉑★ 悬停里也带着「GUI重开」的副作用提示（提示不许只在菜单里）")
  end

  restore224()
  print(string.format("  GUI重开：默认关（nil⇒关）· 迁移四态 · 关掉时开图零动作 / 开着 %d 次重显 · 菜单 1 项（键 guiReopen）· 摘要现算 · 行登记同源",
    onCalls))
  print("GROUP 224 (缩放大地图 [设置] 下拉=「GUI重开」：★默认关闭（nil⇒关）· 老键 showGUI 迁移并清空 · 关掉时开图**一个 GUI 动作都不发** · 提示写明「切图后会被刷新回当前地图」): PASS")
end

-- ===== 组 225（1.74.35-4）：叠加层「跟随地图缩放」自动适配（★从图层调试工具**搬到这里** · 默认开）=====
--   用户 1.74.35-4：「开图/es 变化后 0.1s 高频爆发期（持续 2 秒，感知上无缝）＋之后就降到 0.3 稳态巡检」
--     是**工具箱→大地图缩放**要默认启动的功能，**不是给图层调试工具内使用的**。
--   ★本组用**假地图画布**（12 张底瓦片 + 2 张叠加层）走**真实** smFitApply：验的就是
--     「方向 = ×es」「底瓦片一个动作都不发」「幂等」「es 回 1 自动还原」这四条最容易悄悄反掉的性质。
do
  local savedFr = rawget(_G, "WorldMapDetailFrame")
  local FR = { regs = {} }
  FR.GetName = function() return "WorldMapDetailFrame" end
  -- ★真机 `GetRegions()` 是**多返回**（本项目 `{ f() }` 收集多返回的写法就是这么用的）；
  --   假帧必须照同款形态回：返回**一个 table** 会让 `{ f() }` 只套一层 ⇒ 目标数恒 0（本组 ⑤ 当场抓到过）。
  FR.GetRegions = function()
    local r = FR.regs
    return r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14]
  end
  FR.GetEffectiveScale = function() return 0.7 end
  -- 记账用的假纹理：几何读写都真记账，别的调用一律不给（杜绝「测试自己实现一遍判据」）
  local function mkTex(name, x, y, w, h)
    local t = { nm = name, x = x, y = y, w = w, h = h, np = 0, nclear = 0, nw = 0, nh = 0 }
    t.GetObjectType = function() return "Texture" end
    t.GetName = function() return t.nm end
    t.GetPoint = function() return "TOPLEFT", FR, "TOPLEFT", t.x, t.y end
    t.GetWidth = function() return t.w end
    t.GetHeight = function() return t.h end
    -- ★1.75.9：屏幕几何（`smFitDetect` 探测用）；给**常量** = 「不会级联」模型 ⇒ 结论「需要我们折算」。
    t.GetLeft = function() return t.x end
    t.GetTop = function() return t.y end
    t.ClearAllPoints = function() t.nclear = t.nclear + 1 end
    t.SetPoint = function(_, p, rel, rp, nx, ny) t.np = t.np + 1 t.x = nx t.y = ny return true end
    t.SetWidth = function(_, v) t.nw = t.nw + 1 t.w = v return true end
    t.SetHeight = function(_, v) t.nh = t.nh + 1 t.h = v return true end
    return t
  end
  local tiles = {}
  for i = 1, 12 do tiles[i] = mkTex("WorldMapDetailTile" .. i, 0, 0, 256, 256) end
  local ovA = mkTex("WorldMapOverlay1", 355, -320, 215, 215) -- 真机探针存档里的实测值
  local ovB = mkTex("WorldMapHighlight", 10, -20, 40, 40)
  FR.regs = {}
  for _, t in ipairs(tiles) do table.insert(FR.regs, t) end
  table.insert(FR.regs, ovA) table.insert(FR.regs, ovB)
  rawset(_G, "WorldMapDetailFrame", FR)
  -- ★1.75.9：探测要读外框的 GetScale/SetScale ⇒ 给一个最小假帧（本组是「不会级联」模型）
  local savedWm226 = rawget(_G, "WorldMapFrame")
  local sc226 = 1
  local WMF226 = {}
  WMF226.GetScale = function() return sc226 end
  WMF226.SetScale = function(_, v) sc226 = tonumber(v) or sc226 return true end
  WMF226.GetAlpha = function() return 1 end
  WMF226.SetAlpha = function() return true end
  rawset(_G, "WorldMapFrame", WMF226)
  pcall(EVAL_SM_TEST_MAPFIT_RESET)

  -- ① 前置：读值口/写口全部在位（缺一个 ⇒ 后面的断言会静默跳过）
  local ports225 = { "EVAL_SM_MAPFIT_ON", "EVAL_SM_MAPFIT_SET", "EVAL_SM_MAPFIT_TIP",
                     "EVAL_SM_TEST_MAPFIT", "EVAL_SM_TEST_MAPFIT_GAPS", "EVAL_SM_TEST_MAPFIT_TARGETS",
                     "EVAL_SM_TEST_MAPFIT_APPLY", "EVAL_SM_TEST_MAPFIT_ORIG", "EVAL_SM_TEST_MAPFIT_REC",
                     "EVAL_SM_TEST_MAPFIT_BURST", "EVAL_SM_TEST_MAPFIT_RESTORE", "EVAL_SM_TEST_MAPFIT_RESET" }
  local miss225 = 0
  for i = 1, table.getn(ports225) do if type(_G[ports225[i]]) ~= "function" then miss225 = miss225 + 1 end end
  eq(miss225, 0, "①前置：叠加层适配的读值口/入口全部在位（缺 " .. miss225 .. " 个）")

  -- ② ★★★默认开：真值没写过（nil）⇒ 开；只有**显式 false** 才是关（用户：「要默认启动的功能」）
  eq(EVAL_SM_MAPFIT_ON(), true, "②★★★默认开（真值 nil ⇒ 开）")
  local on225, raw225 = EVAL_SM_TEST_MAPFIT()
  eq(on225 == true and raw225 == nil, true,
    "②读值口与真值同源（on=" .. tostring(on225) .. " · 真值=" .. tostring(raw225) .. "）")
  pcall(EVAL_SM_MAPFIT_SET, false)
  eq(EVAL_SM_MAPFIT_ON(), false, "②显式关 ⇒ 关")
  pcall(EVAL_SM_MAPFIT_SET, true)
  eq(EVAL_SM_MAPFIT_ON(), true, "②再开 ⇒ 开（写的是布尔，不留 nil 歧义）")
  eq(string.find(tostring(EVAL_SM_MAPFIT_TIP()), "叠加层适配", 1, true) ~= nil, true, "②行悬停文案有这一条（与真值同源）")

  -- ③ 节奏 = 用户定稿：0.1s 爆发 / 持续 2s / 之后 0.3s 稳态（数字本身就是需求）
  local gb, gs, gi = EVAL_SM_TEST_MAPFIT_GAPS()
  eq(gb == 0.1 and gs == 2.0 and gi == 0.3, true,
    string.format("③★★★节奏常量 = 0.1 / 2.0 / 0.3（实测 %s / %s / %s）", tostring(gb), tostring(gs), tostring(gi)))
  --   ④ 过渡（开图 / es 变化）⇒ 立刻进爆发期（并把节拍顶满 = 下一帧就动手）
  eq(EVAL_SM_TEST_MAPFIT_BURST(0), 0, "④前置：把 burst 清零")
  eq(EVAL_SM_TEST_MAPFIT_TRANSITION(true, 0.7), 2.0, "④开图 ⇒ 进 2s 爆发期")
  eq(EVAL_SM_TEST_MAPFIT_BURST(0), 0, "④前置：再清零")
  eq(EVAL_SM_TEST_MAPFIT_TRANSITION(true, 0.5), 2.0, "④es 变化 ⇒ 同样进爆发期")
  eq(EVAL_SM_TEST_MAPFIT_TRANSITION(false, 0.5), 0, "④关图 ⇒ 退出爆发期（burst 归零）")

  -- ⑤ 目标集合：底瓦片**必须**被跳过（12 张瓦片 + 2 张叠加层 ⇒ 目标恰好 2）
  eq(EVAL_SM_TEST_MAPFIT_TARGETS(), 2, "⑤★目标 = 非瓦片纹理 2 个（12 张底瓦片被跳过）")

  -- ⑥ 应用 = 偏移与宽高 **×es**（真机定案的方向，反了就是错的）；底瓦片一个几何调用都不许发
  -- ★1.75.9：折算的**前提** = 探测判定「需要我们折算」，**原值** = 在自然档抓（apply 自己不再记原值）。
  eq(EVAL_SM_TEST_MAPFIT_PREPARE(), true, "⑥前置：探测判定「不会级联」⇒ 需要我们折算")
  eq(EVAL_SM_TEST_MAPFIT_NEEDFOLD(), true, "⑥前置：needFold = true（tick 只在此时才动手）")
  eq(EVAL_SM_TEST_MAPFIT_ORIG(), 2, "⑥原值在**自然档**抓了 2 条，进了存档子树 SM_CFG.mapFitOrig（/reload 后还原靠它）")
  local c1, r1, rec1 = EVAL_SM_TEST_MAPFIT_APPLY(0.7)
  eq(c1 == 2, true, "⑥两张叠加层都被折算（实测 " .. tostring(c1) .. "）")
  eq(rec1 == 0, true, "⑥★apply **不再记原值**（`rec` 现在是「等原值」计数；实测 " .. tostring(rec1) .. "）")
  eq(math.abs(ovA.x - 355 * 0.7) < 0.01 and math.abs(ovA.y - (-320) * 0.7) < 0.01, true,
    string.format("⑥★偏移 ×es（实测 %.1f,%.1f，期望 %.1f,%.1f）", ovA.x, ovA.y, 355 * 0.7, -320 * 0.7))
  eq(math.abs(ovA.w - 215 * 0.7) < 0.01 and math.abs(ovA.h - 215 * 0.7) < 0.01, true, "⑥★宽高也 ×es")
  local tileCalls = 0
  for _, t in ipairs(tiles) do tileCalls = tileCalls + t.np + t.nclear + t.nw + t.nh end
  eq(tileCalls, 0, "⑥★★★底瓦片一个几何调用都不发（实测 " .. tileCalls .. " 次）")

  -- ⑦ 幂等：客户端重排后再跑，值已经 ≈ 原值 ×es ⇒ 一个写都不发（否则每拍都刷屏/抖动）
  local c2 = EVAL_SM_TEST_MAPFIT_APPLY(0.7)
  eq(c2, 0, "⑦幂等：第二次应用 0 改动（实测 " .. tostring(c2) .. "）")

  -- ⑧ es 回到 1（模块被关/复位）⇒ **自动还原**成原始几何（否则叠加层永远错位）
  local c3 = EVAL_SM_TEST_MAPFIT_APPLY(1)
  eq(c3, 2, "⑧es=1 ⇒ 自动把 2 个还原回原值（实测 " .. tostring(c3) .. "）")
  eq(math.abs(ovA.x - 355) < 0.01 and math.abs(ovA.y + 320) < 0.01, true,
    string.format("⑧★几何回到原始值（实测 %.1f,%.1f）", ovA.x, ovA.y))
  eq(math.abs(ovA.w - 215) < 0.01, true, "⑧宽高也回到原值")

  -- ⑨ 还原入口（/ehm mapfit restore）：按**存档原值**还原，且没有原值的条目如实跳过（不猜）
  local c4 = EVAL_SM_TEST_MAPFIT_APPLY(0.7)
  eq(c4 == 2, true, "⑨前置：再折算一次（实测 " .. tostring(c4) .. "）")
  local rn, rmiss = EVAL_SM_TEST_MAPFIT_RESTORE()
  eq(rn == 2, true, "⑨restore 还原 2 个（实测 " .. tostring(rn) .. "）")
  eq(rmiss, 0, "⑨没有跳过任何条目（实测 miss=" .. tostring(rmiss) .. "）")
  eq(math.abs(ovB.x - 10) < 0.01 and math.abs(ovB.w - 40) < 0.01, true, "⑨第二个叠加层也还原到原值")

  -- ⑩ 夹具自清：清掉内存记录 + 存档原值 + 开关真值（回到「没写过」= 默认开），并还原假帧
  pcall(EVAL_SM_MAPFIT_SET, false)
  eq(EVAL_SM_MAPFIT_ON(), false, "⑩关掉后读值口 = 关（闸门是唯一开关）")
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  eq(EVAL_SM_MAPFIT_ON(), true, "⑩清掉真值（nil）⇒ 回到默认开")
  rawset(_G, "WorldMapDetailFrame", savedFr)
  rawset(_G, "WorldMapFrame", savedWm226) -- ★1.75.9：探测用的假外框也还原

  print(string.format("  叠加层适配：默认开（nil⇒开）· 节奏 0.1/2.0/0.3 · 过渡进爆发期 · 目标 2（跳过 12 张底瓦片）· ×es 折算 %d 个 · 幂等 0 改动 · es=1 自动还原 %d 个",
    c1, c3))
  print("GROUP 225 (缩放大地图·叠加层自动适配：★功能从图层调试工具搬到本模块 + **默认开** · 节奏 0.1s 爆发 2s → 0.3s 稳态 · 底瓦片一个动作都不发 · 幂等 · es 回 1 自动还原): PASS")
end

-- ===== 组 226（1.74.36-3）：**开启「缩放大地图」即套默认档** = 缩放 0.7 / 透明度 0.7 / GUI重开 不启用 =====
-- 用户原话：「工具箱 →『缩放大地图』 开启之后默认值设置 0.7缩放 0.7 透明度 不启用GUI」
-- ★这一组要挡住的静默失效：
--   ① 默认档只写了配置、没应用 ⇒ 开关勾上了、地图还是 1/1 全尺寸不透明；
--   ② 默认档被写成「只在键缺失时才补」⇒ 老存档里上一轮调过的值一直留着，用户看到「默认值没生效」；
--   ③ GUI重开 在默认档里没被关掉 ⇒ 用户明确要的「不启用GUI」反了（还带那个切图被拉回的副作用）；
--   ④ 面板值标签不刷 ⇒ 界面显示旧数字（真机观感 = 没生效）；
--   ⑤ 顺手把「叠加层适配」（另一项默认开）一起关掉 = 破坏别的功能。
do
  eq(type(EVAL_SM_TEST_DEFAULTS) == "function", true, "①前置：默认档读值口在位（缺了后面的断言只能跳过 = 逃生口，明确禁止）")
  local dA, dS, dG = EVAL_SM_TEST_DEFAULTS()
  eq(dA, 0.7, "①默认**透明度**常量 = 0.7（实测 " .. tostring(dA) .. "）")
  eq(dS, 0.7, "①默认**缩放**常量 = 0.7（实测 " .. tostring(dS) .. "）")
  eq(dG, false, "①★★★默认档里 GUI重开 = **不启用**（用户明确；实测 " .. tostring(dG) .. "）")

  -- 夹具自建：记下当前三项真值 + 主开关，收尾还原（③的关闭步骤会把值改成 1，必须还原）
  local _, _, _, sA, sS, sG = EVAL_SM_TEST_DEFAULTS()
  local tb = (type(EVAL_TB_CFG) == "function") and EVAL_TB_CFG() or nil
  eq(type(tb) == "table", true, "①前置：EVAL_TB_CFG() 可用（模块读配置的唯一出口）")
  local savedOn = tb and tb.simpleMap or nil

  -- ② 先把三项**故意调乱**（模拟「用户上一轮调过 / 老存档里是别的值」）
  EH_SIMPLEMAP_CFG.alpha = 0.5
  EH_SIMPLEMAP_CFG.scale = 0.9
  pcall(EVAL_SM_GUIREOPEN_SET, true)
  local _, _, _, bA, bS, bG = EVAL_SM_TEST_DEFAULTS()
  eq(bA, 0.5, "②前置：透明度已改成 0.5（实测 " .. tostring(bA) .. "）")
  eq(bS, 0.9, "②前置：缩放已改成 0.9（实测 " .. tostring(bS) .. "）")
  eq(bG, true, "②前置：GUI重开已改成开（实测 " .. tostring(bG) .. "）")

  -- ③ ★★★开启 ⇒ 三项都回到默认档（**不是**保留上一轮的 0.5 / 0.9 / 开）
  pcall(EVAL_SM_SET, true)
  local _, _, _, aA, aS2, aG = EVAL_SM_TEST_DEFAULTS()
  eq(aA, 0.7, "③★★★开启后透明度回到默认 0.7（实测 " .. tostring(aA) .. "）")
  eq(aS2, 0.7, "③★★★开启后缩放回到默认 0.7（实测 " .. tostring(aS2) .. "）")
  eq(aG, false, "③★★★开启后 GUI重开 = 不启用（实测 " .. tostring(aG) .. "）")
  eq(EVAL_SM_ENABLED(), true, "③主开关真值 = 开（写在 tbCfg 里的那一份）")

  -- ④ 默认档必须**落到界面**：地图设置面板的两个值标签显示 0.70 / 0.70（真机上就是这两个数字）
  local okSync, pA, pS = EVAL_SM_TEST_PANEL()
  eq(okSync, true, "④面板刷新口已落地（featBuild 跑过 ⇒ 面板已建；没建 = 后面的界面断言无从谈起）")
  eq(pA, "0.70", "④★面板透明度标签 = 0.70（实测 " .. tostring(pA) .. "）")
  eq(pS, "0.70", "④★面板缩放标签 = 0.70（实测 " .. tostring(pS) .. "）")
  local tipDef = EVAL_SM_DEF_TIP()
  eq(type(tipDef) == "string" and string.find(tipDef, "0.70", 1, true) ~= nil, true,
    "④悬停里的默认档说明写了 0.70（实测：" .. tostring(tipDef) .. "）")
  eq(type(tipDef) == "string" and string.find(tipDef, "关", 1, true) ~= nil, true, "④悬停里的默认档说明写了 GUI重开 关")

  -- ⑤ 反向哨兵：默认档里 GUI 不启用 ⇒「重显最外层 GUI」一次都不许发
  --   ★用**不碰配置**的开图触发器（EVAL_SM_SET 会套默认档，拿它触发就等于把要验的状态自己清掉）
  pcall(EVAL_SM_TEST_GUI_CALLS_RESET)
  EVAL_SM_TEST_APPLY()
  eq(EVAL_SM_TEST_GUI_CALLS(), 0, "⑤★★GUI重开不启用 ⇒ 开图路径上重显 GUI 调用 0 次（实测 " .. tostring(EVAL_SM_TEST_GUI_CALLS()) .. "）")

  -- ⑥ 反向哨兵：默认档不许碰「叠加层适配」（另一项默认开的功能，各管各的）
  eq(EVAL_SM_MAPFIT_ON(), true, "⑥叠加层适配仍是默认开（默认档没顺手把它关掉）")

  -- ⑦ [关闭] 仍是老语义（视觉复位 1/1）——与「开启套默认档」严格对称，两边都不留临时值
  pcall(EVAL_SM_SET, false)
  local _, _, _, zA, zS = EVAL_SM_TEST_DEFAULTS()
  eq(zA, 1, "⑦关闭后透明度复位 1（实测 " .. tostring(zA) .. "）")
  eq(zS, 1, "⑦关闭后缩放复位 1（实测 " .. tostring(zS) .. "）")
  eq(EVAL_SM_ENABLED(), false, "⑦主开关真值 = 关")

  -- ⑧ 夹具自清：三项真值 + 主开关 + 叠加层适配 全部还原（**不删自己的备份**：这里没备份，直接写回原值）
  EH_SIMPLEMAP_CFG.alpha = sA
  EH_SIMPLEMAP_CFG.scale = sS
  if type(EVAL_SM_GUIREOPEN_SET) == "function" then pcall(EVAL_SM_GUIREOPEN_SET, sG == true) end
  if tb then tb.simpleMap = savedOn end
  pcall(EVAL_SM_TEST_MAPFIT_RESET)

  print(string.format("  默认档：透明度 %.2f / 缩放 %.2f / GUI重开 %s · 故意调乱(0.5/0.9/开)后开启 ⇒ 全部回到默认 · 面板标签 %s/%s · GUI 调用 %d 次",
    dA, dS, dG and "开" or "关", tostring(pA), tostring(pS), EVAL_SM_TEST_GUI_CALLS()))
  print("GROUP 226 (缩放大地图·开启即套默认档：★用户定 0.7缩放/0.7透明度/**不启用GUI** · 写配置+应用+刷面板三步齐全 · 关掉仍复位 1/1 · 不碰叠加层适配): PASS")
end

-- ===== 组 230（1.75.7）：「缩放大地图」**未开启**时，模块不许再监听探索层的缩放（用户排查）=====
-- 用户原话：「排查缩放大地图功能.在未开启的情况下会不会监听探索层的缩放操作」
-- ★修前实测（本组就是它的永久化）：模块关闭 + 点 10 拍 tick ⇒ 叠加层被写 **8 次**、355/-320/215×215 被折成
--   248.5/-224/150.5×150.5（×0.7）、还记下 2 条原值。根因：① tick 是**载入期无条件建**的；
--   ② ④ 只看 mapFit（**默认开**）、③「开图保持」压根没看总开关。
-- 本组钉住四条：① 关闭 ⇒ **连读都不读**（IsShown / GetEffectiveScale 各 0 次 = 不再监听）；
--   ② 关闭 ⇒ 几何**零调用**（关掉零动作）；③ 开启 ⇒ 照常监听并折算（反向哨兵：别把功能关死）；
--   ④ 关闭那一刻把之前折过的几何**当场还原**（旧设计把还原寄托在常驻 tick 上，代价就是关掉照跑）。
do
  local savedFr230 = rawget(_G, "WorldMapDetailFrame")
  local savedWm230 = rawget(_G, "WorldMapFrame")
  local cfg230 = rawget(_G, "EVAL_HELP_CONFIG")
  local savedTb230 = cfg230.tb
  -- 假地图画布：**每一次读都记账**（IsShown / 父链 GetScale）——「有没有在监听」就靠这两个计数说话
  -- ★1.75.9：折算系数改走**父链连乘**（自身 1.00 × 外框 0.70 = 0.70），所以计数对象从会滞后的
  --   `GetEffectiveScale` 换成了 `GetScale`；`GetEffectiveScale` 只留一个不计数的兼容桩。
  local FR230 = { regs = {}, nShown = 0, nEs = 0 }
  FR230.GetName = function() return "WorldMapDetailFrame" end
  FR230.IsShown = function() FR230.nShown = FR230.nShown + 1 return true end
  FR230.GetScale = function() FR230.nEs = FR230.nEs + 1 return 1 end
  FR230.GetParent = function() return rawget(_G, "WorldMapFrame") end
  FR230.GetEffectiveScale = function() return 0.7 end
  local function mkTex230(nm, x, y, w, h)
    local t = { nm = nm, x = x, y = y, w = w, h = h, np = 0, nclear = 0, nw = 0, nh = 0 }
    t.GetObjectType = function() return "Texture" end
    t.GetName = function() return t.nm end
    t.GetPoint = function() return "TOPLEFT", FR230, "TOPLEFT", t.x, t.y end
    t.GetWidth = function() return t.w end
    t.GetHeight = function() return t.h end
    -- ★1.75.9：屏幕几何（探测用）。本夹具给**常量**（不随外框缩放走）= 「不会级联」模型。
    t.GetLeft = function() return t.x end
    t.GetTop = function() return t.y end
    t.ClearAllPoints = function() t.nclear = t.nclear + 1 end
    t.SetPoint = function(_, p, rel, rp, nx, ny) t.np = t.np + 1 t.x = nx t.y = ny return true end
    t.SetWidth = function(_, v) t.nw = t.nw + 1 t.w = v return true end
    t.SetHeight = function(_, v) t.nh = t.nh + 1 t.h = v return true end
    return t
  end
  local ovA230 = mkTex230("WorldMapOverlay1", 355, -320, 215, 215)
  local ovB230 = mkTex230("WorldMapHighlight", 10, -20, 40, 40)
  FR230.regs = { ovA230, ovB230 }
  FR230.GetRegions = function() return FR230.regs[1], FR230.regs[2] end
  rawset(_G, "WorldMapDetailFrame", FR230)
  -- ★1.75.9：探测（`smFitDetect`）要读外框的 GetScale/SetScale ⇒ 给一个最小假帧。
  --   ★本夹具的纹理屏幕几何**不随外框缩放变**（= 「不会级联」模型）⇒ 探测结论 = **需要我们折算**，
  --     与 1.74.34-18b 那套老口径一致；「会级联」模型见组 232。
  local sc230 = 0.7
  local WMF230 = {}
  WMF230.GetScale = function() return sc230 end
  WMF230.SetScale = function(_, v) sc230 = tonumber(v) or sc230 return true end
  WMF230.GetAlpha = function() return 1 end
  WMF230.SetAlpha = function() return true end
  rawset(_G, "WorldMapFrame", WMF230)
  local function geomCalls230()
    return ovA230.np + ovA230.nclear + ovA230.nw + ovA230.nh + ovB230.np + ovB230.nclear + ovB230.nw + ovB230.nh
  end
  local tickF230 = rawget(_G, "EH_SM_FEAT")
  eq(type(tickF230) == "table" or type(tickF230) == "userdata", true, "组230①前置：tick 帧存在（具名 EH_SM_FEAT —— 没有它这一组就是空转）")
  eq(type(EVAL_TEST_FIRE_UPDATE) == "function", true, "组230①前置：EVAL_TEST_FIRE_UPDATE 在位（走真机 OnUpdate 通道）")

  -- ① 关闭：连读都不许读（IsShown / GetEffectiveScale = 「监听探索层」的两条实锤）
  cfg230.tb = { simpleMap = false }
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  FR230.nShown, FR230.nEs = 0, 0
  local fired230 = 0
  for _ = 1, 10 do if EVAL_TEST_FIRE_UPDATE(tickF230, 0.05) then fired230 = fired230 + 1 end end
  eq(fired230, 10, "组230①前置：tick 真的跑了 10 次（0.5s；实测 " .. tostring(fired230) .. "）")
  eq(FR230.nShown, 0, "组230①★★★未开启 ⇒ **不读地图开没开**（IsShown 0 次，实测 " .. tostring(FR230.nShown) .. "）")
  eq(FR230.nEs, 0, "组230①★★★未开启 ⇒ **不读探索层的缩放**（父链 GetScale 0 次 = 不再监听，实测 " .. tostring(FR230.nEs) .. "）")
  eq(geomCalls230(), 0, "组230②★★★未开启 ⇒ 几何**零调用**（实测 " .. tostring(geomCalls230()) .. "）")
  eq(EVAL_SM_TEST_MAPFIT_ORIG(), 0, "组230②★★未开启 ⇒ 一条原值都不许记（实测 " .. tostring(EVAL_SM_TEST_MAPFIT_ORIG()) .. "）")
  eq(math.abs(ovA230.x - 355) < 0.01 and math.abs(ovA230.w - 215) < 0.01, true, "组230②★几何保持原状（没被动过）")

  -- ③ 反向哨兵：开启 ⇒ 照常监听并折算（别把功能关死）
  cfg230.tb = { simpleMap = true }
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  pcall(EVAL_SM_SET, true)   -- ★1.75.9：开一次 ⇒ 走 smFitPrepare（探测 + 自然档抓原值）
  eq(EVAL_SM_TEST_MAPFIT_NEEDFOLD(), true, "组230③★探测结论 = 本夹具「不会级联」⇒ **需要我们折算**（这才是折算的前提）")
  FR230.nShown, FR230.nEs = 0, 0
  for _ = 1, 10 do EVAL_TEST_FIRE_UPDATE(tickF230, 0.05) end
  eq(FR230.nEs > 0, true, "组230③★★反向哨兵：开启 ⇒ **在读**探索层缩放（父链 GetScale " .. tostring(FR230.nEs) .. " 次）")
  eq(geomCalls230() > 0, true, "组230③★★反向哨兵：开启 ⇒ 几何被折算（实测 " .. tostring(geomCalls230()) .. " 次调用）")
  eq(math.abs(ovA230.x - 355 * 0.7) < 0.01, true,
    string.format("组230③★方向仍是 ×es（实测 %.1f，期望 %.1f）", ovA230.x, 355 * 0.7))

  -- ④ 关闭那一刻**当场还原**（旧设计靠常驻 tick 兜还原 ⇒ 代价是关掉照折）
  local nR230 = 0
  pcall(function() local a = select(1, EVAL_SM_TEST_MAPFIT_RESTORE()) nR230 = tonumber(a) or 0 end)
  local okSet230 = pcall(EVAL_SM_SET, false)
  eq(okSet230, true, "组230④前置：EVAL_SM_SET(false) 走得通")
  eq(EVAL_SM_ENABLED(), false, "组230④主开关真值 = 关")
  eq(math.abs(ovA230.x - 355) < 0.01 and math.abs(ovA230.y + 320) < 0.01, true,
    string.format("组230④★★★关闭后几何**回到原值**（实测 %.1f,%.1f）", ovA230.x, ovA230.y))
  eq(math.abs(ovA230.w - 215) < 0.01 and math.abs(ovB230.x - 10) < 0.01, true, "组230④★两个叠加层都还原（宽高与第二个一起核）")
  -- 关闭之后再来 10 拍：仍然一个调用都不许发（还原完就彻底安静）
  FR230.nShown, FR230.nEs = 0, 0
  local g0 = geomCalls230()
  for _ = 1, 10 do EVAL_TEST_FIRE_UPDATE(tickF230, 0.05) end
  eq(FR230.nShown + FR230.nEs, 0, "组230④★★关闭后依旧不读（IsShown+es 合计 0，实测 " .. tostring(FR230.nShown + FR230.nEs) .. "）")
  eq(geomCalls230() - g0, 0, "组230④★★关闭后依旧零动作（实测多出 " .. tostring(geomCalls230() - g0) .. " 次）")

  -- 夹具自清
  rawset(_G, "WorldMapDetailFrame", savedFr230)
  rawset(_G, "WorldMapFrame", savedWm230)
  cfg230.tb = savedTb230
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  -- ⑤ ★★★1.75.7 用户要求：「未开启地图缩放功能不需要进行任务纹理的操作」——连**关闭那一刻**也不许碰：
  --   **从未启用过**（FEAT.applied=false 且没有原值记录）⇒ 一个地图纹理/帧操作都不发。
  local WM230 = { nA = 0, nS = 0, nK = 0, nClear = 0, nPt = 0, sc = 1 }
  WM230.SetAlpha = function(_, v) WM230.nA = WM230.nA + 1 return true end
  -- ★★★1.75.9：缩放**必须是有状态的假帧** —— `featApplyScale` 现在会「读回自证、同档不重写」，
  --   常量型 GetScale 会让「关闭时写回 1」这条被当成重复写而跳过（断言随之假红）。
  WM230.SetScale = function(_, v) WM230.nS = WM230.nS + 1 WM230.sc = tonumber(v) or WM230.sc return true end
  WM230.GetAlpha = function() return 1 end
  WM230.GetScale = function() return WM230.sc end
  WM230.EnableKeyboard = function(_, v) WM230.nK = WM230.nK + 1 return true end
  WM230.ClearAllPoints = function() WM230.nClear = WM230.nClear + 1 end
  WM230.SetPoint = function() WM230.nPt = WM230.nPt + 1 return true end
  rawset(_G, "WorldMapFrame", WM230)
  local sA230, sS230, sG230 = EH_SIMPLEMAP_CFG.alpha, EH_SIMPLEMAP_CFG.scale, EH_SIMPLEMAP_CFG.guiReopen
  cfg230.tb = { simpleMap = false }
  pcall(EVAL_SM_TEST_MAPFIT_RESET) -- 清掉原值记录（= 从没动过）
  local g0b = geomCalls230()
  TEST.chat = nil
  EVAL_SM_SET(false)
  local wmCalls = WM230.nA + WM230.nS + WM230.nK + WM230.nClear + WM230.nPt
  eq(wmCalls, 0, "组230⑤★★★从未启用过 ⇒ 关闭路径**一个地图纹理/帧操作都不发**（实测 " .. tostring(wmCalls) .. " 次）")
  eq(geomCalls230() - g0b, 0, "组230⑤★★从未启用过 ⇒ 叠加层同样零调用")
  eq(string.find(tostring(TEST.chat or ""), "没动过任何地图纹理", 1, true) ~= nil, true, "组230⑤★如实播报「本就没启用过 ⇒ 没动过任何地图纹理」")
  -- ⑥ 反向哨兵：**开启过** ⇒ 关闭那一刻必须真的复位（别把 ⑤ 的闸门做成「关了就什么都不做」）
  cfg230.tb = { simpleMap = true }
  EVAL_SM_SET(true)
  local afterA, afterS = WM230.nA, WM230.nS
  eq(afterA > 0 and afterS > 0, true,
    "组230⑥★开启 ⇒ 立刻把默认档**写进地图帧**（SetAlpha " .. tostring(afterA) .. " / SetScale " .. tostring(afterS) .. "）")
  TEST.chat = nil
  EVAL_SM_SET(false)
  -- ★分开数：226 读的是**配置真值**（把 alpha 写回 1 就算过），这里数的是**真的写到帧上**
  --   ⇒ 「只改配置不碰帧」这种回归只有本组抓得住。
  eq(WM230.nA > afterA, true, "组230⑥★★开启过 ⇒ 关闭时**真的把透明度写回地图帧**（SetAlpha +" .. tostring(WM230.nA - afterA) .. "）")
  eq(WM230.nS > afterS, true, "组230⑥★★同样把缩放写回地图帧（SetScale +" .. tostring(WM230.nS - afterS) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "已复位", 1, true) ~= nil, true, "组230⑥★如实播报已复位（与 ⑤ 的另一种话术区分开）")
  EH_SIMPLEMAP_CFG.alpha, EH_SIMPLEMAP_CFG.scale, EH_SIMPLEMAP_CFG.guiReopen = sA230, sS230, sG230
  cfg230.tb = savedTb230
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  print("  关闭态：IsShown/es 读取 0 次 · 几何 0 次 · 原值 0 条（修前 = 8 次几何写入 + 2 条原值）")
  print("GROUP 230 (缩放大地图·未开启时不再监听探索层缩放：读 0 次/几何 0 次/关闭即还原 · 开启仍照常工作): PASS")
end


-- ===== 组 232（1.75.9）：「探索层纹理缩两遍 / 正常开启不生效」全案 =====
-- 用户原话：「我说的纹理缩放是 WordMapDetailFrame 下面 12 之后的纹理缩放逻辑」→「未开启插件载入..的情况下打开大地图缩放,
--   和开着载入之后关闭又打开, 这两种情况都会发生.纹理渲染层被缩放两次」→「在开启/关闭要做好事件清理」
--   →「现在正常开启都无法生效缩放修正」（= 把默认档改成「听探测」引起的回归）。
-- ★两种客户端模型必须分开断言（本组最重要的方法论）：
--   · **会级联**（真机：几何读回 = 逻辑×es）⇒ 正确行为 = **显示 = 原值×es，且一个逻辑写都不发**
--     （我们算出的目标与读回值相等 ⇒ 幂等判据直接跳过；旧版的「连乘」来自把已缩值当原值重记）；
--   · **不会级联**（老探针模型：读回 = 逻辑）⇒ 正确行为 = 按 es **折一次**（逻辑值 355 → 248.5）。
--   ★把「逻辑值」直接与 355×0.7 比是**测错了模型**（级联侧永远 355 而显示已经对了）。
do
  local fails0 = TESTASSERT_FAILS
  local savedFr = rawget(_G, "WorldMapDetailFrame")
  local savedWm = rawget(_G, "WorldMapFrame")
  local savedEsc = rawget(_G, "UISpecialFrames")
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  local savedTb = cfg.tb
  local tick = rawget(_G, "EH_SM_FEAT")
  local function ticks(n) for _ = 1, n do EVAL_TEST_FIRE_UPDATE(tick, 0.05) end end
  local function build(cascade)
    local st = { sc = 1, geom = 0 }
    local W = {}
    W.GetScale = function() return st.sc end
    W.SetScale = function(_, v) st.sc = tonumber(v) or st.sc return true end
    W.GetAlpha = function() return 1 end
    W.SetAlpha = function() return true end
    W.ClearAllPoints = function() return true end
    W.SetPoint = function() return true end
    W.GetEffectiveScale = function() return st.sc end
    local FR = {}
    FR.IsShown = function() return true end
    -- ★1.75.9：折算系数走**父链连乘**（自身 1.00 × 外框 st.sc）⇒ 夹具必须给出这条层级，
    --   否则连乘恒为 1（等于不折算），「照旧折算一次」那类断言会假红。
    FR.GetScale = function() return 1 end
    FR.GetParent = function() return W end
    FR.GetEffectiveScale = function() return st.sc end
    local function mk(nm, x, y, w, h)
      local t = { nm = nm, x = x, y = y, w = w, h = h }
      t.GetObjectType = function() return "Texture" end
      t.GetName = function() return t.nm end
      if cascade then
        t.GetPoint = function() return "TOPLEFT", FR, "TOPLEFT", t.x * st.sc, t.y * st.sc end
        t.GetWidth = function() return t.w * st.sc end
        t.GetHeight = function() return t.h * st.sc end
        t.GetLeft = function() return t.x * st.sc end
        t.GetTop = function() return t.y * st.sc end
      else
        t.GetPoint = function() return "TOPLEFT", FR, "TOPLEFT", t.x, t.y end
        t.GetWidth = function() return t.w end
        t.GetHeight = function() return t.h end
        t.GetLeft = function() return t.x end
        t.GetTop = function() return t.y end
      end
      t.ClearAllPoints = function() st.geom = st.geom + 1 end
      t.SetPoint = function(_, p, rel, rp, nx, ny) st.geom = st.geom + 1 t.x = nx t.y = ny return true end
      t.SetWidth = function(_, v) st.geom = st.geom + 1 t.w = v return true end
      t.SetHeight = function(_, v) st.geom = st.geom + 1 t.h = v return true end
      return t
    end
    local A = mk("WorldMapOverlay1", 355, -320, 215, 215)
    FR.GetRegions = function() return A end
    rawset(_G, "WorldMapDetailFrame", FR)
    rawset(_G, "WorldMapFrame", W)
    return A, st
  end
  local function openWith(cascade, mode)
    local A, st = build(cascade)
    cfg.tb = { simpleMap = false }
    pcall(EVAL_SM_TEST_MAPFIT_RESET)
    if mode then EH_SIMPLEMAP_CFG.mapFitMode = mode end
    cfg.tb = { simpleMap = true }
    pcall(EVAL_SM_SET, true)
    return A, st
  end
  local function closeAndReopen(mode)
    pcall(EVAL_SM_SET, false)
    if mode then EH_SIMPLEMAP_CFG.mapFitMode = mode end
    cfg.tb = { simpleMap = true }
    pcall(EVAL_SM_SET, true)
    ticks(10)
  end
  -- ① 默认档 = fold（用户实测：改成「听探测」⇒ 正常开启完全不生效）
  local A1, st1 = openWith(true)
  local n1 = st1.geom
  ticks(10)
  eq(EVAL_SM_MAPFIT_MODE(), "fold", "①★★默认策略 = fold（保住「开启即生效」）")
  eq(EVAL_SM_TEST_MAPFIT_NEEDFOLD(), false, "①★探测仍如实报「本客户端会自动级联」（结论只进提示/取证）")
  eq(math.abs(A1.x * st1.sc - 355 * 0.7) < 0.01, true,
     "①★★★级联客户端：**显示 = 原值×es**（实测 " .. tostring(A1.x * st1.sc) .. "，期望 " .. tostring(355 * 0.7) .. "）")
  eq(st1.geom - n1, 0, "①★★★级联客户端：**一个逻辑写都不发**（读回已含缩放 ⇒ 与目标相等 ⇒ 幂等跳过；实测 " .. tostring(st1.geom - n1) .. " 次）")
  closeAndReopen()
  eq(math.abs(A1.x * st1.sc - 355 * 0.7) < 0.01, true, "①★★★关一次再开：显示仍是原值×es（旧版把已缩值重记成原值 ⇒ 连乘）")
  eq(st1.geom - n1, 0, "①★★关→开也没有任何逻辑写（实测 " .. tostring(st1.geom - n1) .. " 次）")
  -- ② 不级联客户端（老探针模型）：默认档必须**真的折一次**（= 用户要的「生效」）
  local A2, st2 = openWith(false)
  local n2 = st2.geom
  ticks(10)
  eq(math.abs(A2.x - 355 * 0.7) < 0.01, true,
     "②★★★不级联客户端：照旧折算一次（逻辑值 实测 " .. tostring(A2.x) .. "，期望 " .. tostring(355 * 0.7) .. "）")
  eq(st2.geom - n2 > 0, true, "②★★确实写了几何（实测 " .. tostring(st2.geom - n2) .. " 次）")
  closeAndReopen()
  eq(math.abs(A2.x - 355 * 0.7) < 0.01, true,
     "②★★★关一次再开仍是原值×es（实测 " .. tostring(A2.x) .. "；旧版连乘成 " .. tostring(355 * 0.7 * 0.7) .. "）")
  -- ③ 策略 nofold：一个几何都不碰（不级联客户端上最明显：逻辑值保持 355）
  local A3, st3 = openWith(false, "nofold")
  local n3 = st3.geom
  ticks(10)
  eq(EVAL_SM_MAPFIT_MODE(), "nofold", "③★策略切到 nofold")
  eq(st3.geom - n3, 0, "③★★nofold ⇒ 零几何调用（实测 " .. tostring(st3.geom - n3) .. " 次）")
  eq(math.abs(A3.x - 355) < 0.01, true, "③★几何保持原样（该模式下就是要这个）")
  -- ④ 策略 auto = 听探测：不级联 ⇒ 折；级联 ⇒ 不折（两条腿都验，别把 auto 做成「永远不折」）
  local A4 = openWith(false, "auto")
  ticks(10)
  eq(EVAL_SM_MAPFIT_MODE(), "auto", "④★策略切到 auto")
  eq(EVAL_SM_TEST_MAPFIT_NEEDFOLD(), true, "④★auto + 不级联 ⇒ 探测判定需要折算")
  eq(math.abs(A4.x - 355 * 0.7) < 0.01, true, "④★★auto 在不级联客户端上照旧折算（实测 " .. tostring(A4.x) .. "）")
  local A4b, st4b = openWith(true, "auto")
  local n4b = st4b.geom
  ticks(10)
  eq(st4b.geom - n4b, 0, "④b★★auto + 会级联 ⇒ 零几何调用（实测 " .. tostring(st4b.geom - n4b) .. " 次）")
  eq(math.abs(A4b.x * st4b.sc - 355 * 0.7) < 0.01, true, "④b★显示仍是原值×es")
  -- ⑤ 原值只在**自然档**抓（宽 215 而不是已缩过的 150.5）+ 记录键 = 纹理名
  --   ★用**会折算**的夹具现跑一次再读记录（上一段 ④b 是「不折算」档，那一档**不抓原值**，记录是空的）
  local A5 = openWith(false)
  ticks(3)
  local key5, _f5, rx5, ry5, rw5 = EVAL_SM_TEST_MAPFIT_FROM(1)
  eq(rw5, 215, "⑤★★原值取自自然档（宽 = 215；实测 " .. tostring(rw5) .. "）")
  eq(rx5, 355, "⑤★★锚点偏移也取自然档（355；实测 " .. tostring(rx5) .. "）")
  eq(type(key5) == "string" and string.find(key5, "WorldMapOverlay", 1, true) == 1, true,
     "⑤★记录键 = **纹理名**（不用会漂移的枚举序号；实测 " .. tostring(key5) .. "）")
  -- ⑥ 关闭时的清理（用户要求「做好探索层纹理的事件清理」）
  local fc = { shown = true, script = "OnUpdate_handler" }
  fc.SetScript = function(_, ev, fn) if ev == "OnUpdate" then fc.script = fn end return true end
  fc.GetScript = function(_, ev) return fc.script end
  fc.Hide = function() fc.shown = false return true end
  fc.Show = function() fc.shown = true return true end
  fc.IsShown = function() return fc.shown end
  rawset(_G, "EH_SM_COORDS", fc)
  local fd = { shown = true }
  fd.Hide = function() fd.shown = false return true end
  fd.Show = function() fd.shown = true return true end
  fd.IsShown = function() return fd.shown end
  rawset(_G, "EH_SM_DRAG", fd)
  rawset(_G, "UISpecialFrames", { "ChatFrame1", "WorldMapFrame" })
  EVAL_SM_TEST_ESC_ADDED_SET(true)
  pcall(EVAL_SM_SET, false)
  eq(fc.script ~= nil, true, "⑥★★关闭**不摘**坐标行的 OnUpdate（摘了就再也装不回来；「关掉零动作」由处理器开头的 enabled 门保证）")
  eq(fc.shown, false, "⑥★★关闭：坐标行 Hide")
  eq(fd.shown, false, "⑥★关闭：拖拽柄 Hide")
  local torn1, escAfter = EVAL_SM_TEST_FEAT_TORN()
  eq(torn1, true, "⑥★★关闭时确实走了「收钩子」这条路（FEAT.torn）")
  eq(escAfter, false, "⑥★★`FEAT.escAdded` 已复位")
  local hasEsc, keptEsc = false, false
  for _, v in ipairs(rawget(_G, "UISpecialFrames") or {}) do
    if v == "WorldMapFrame" then hasEsc = true end
    if v == "ChatFrame1" then keptEsc = true end
  end
  eq(hasEsc, false, "⑥★★★我们插进 ESC 列表的那一项**已拿掉**")
  eq(keptEsc, true, "⑥★★别人（客户端自己）的项一个没动")
  -- ★★★1.75.9 真机回归（用户报障：「这个界面在世界地图拖拽移动功能失效」）：**收钩子必须配「再武装」**
  --   旧写法关闭时把坐标行 OnUpdate 摘了 + `featBuild` 一次性守卫 ⇒ 再开启时拖拽柄永久消失。
  cfg.tb = { simpleMap = true }
  pcall(EVAL_SM_SET, true)
  eq(fd.shown, true, "⑥★★★再开启：**拖拽柄重新出现**（拖拽移动必须恢复；实测 " .. tostring(fd.shown) .. "）")
  eq(fc.shown, true, "⑥★★再开启：坐标行也重新出现（实测 " .. tostring(fc.shown) .. "）")
  local hasEsc2 = false
  for _, v in ipairs(rawget(_G, "UISpecialFrames") or {}) do if v == "WorldMapFrame" then hasEsc2 = true end end
  eq(hasEsc2, true, "⑥★再开启：ESC 列表那一项也补回来了")
  pcall(EVAL_SM_SET, false)
  -- ⑦ 旧存档迁移：没有 `mapFitVer` 戳的原值一律丢弃（旧版可能已被污染成「折过的值」）
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  cfg.tb = { simpleMap = false }
  EH_SIMPLEMAP_CFG.mapFitOrig = { tex13 = { x = 105, y = -157, w = 105, h = 105 } }
  EH_SIMPLEMAP_CFG.mapFitVer = nil
  eq(EVAL_SM_TEST_MAPFIT_MIGRATE(), true, "⑦★迁移认出「没有版本戳的旧原值」")
  eq(EVAL_SM_TEST_MAPFIT_ORIG(), 0, "⑦★★旧原值整块丢弃（实测剩 " .. tostring(EVAL_SM_TEST_MAPFIT_ORIG()) .. " 条）")
  -- ⑧ 幂等：同一 es 再折一拍必须 changed = 0
  local A6 = openWith(false)
  ticks(3)
  local c8 = select(1, EVAL_SM_TEST_MAPFIT_APPLY(0.7))
  eq(c8, 0, "⑧★★第二拍 changed = 0（幂等；实测 " .. tostring(c8) .. "）")
  eq(math.abs(A6.w - 215 * 0.7) < 0.01, true, "⑧★宽也按 es 折算（实测 " .. tostring(A6.w) .. "）")
  -- ⑨ 取证环（用户：「可以开启日志.在何种情况下会进行双次缩放操作.」）
  eq(EVAL_SM_TEST_MAPFIT_TRACE_CLEAR(), true, "⑨前置：清空取证环")
  local A7 = openWith(true)
  ticks(10)
  local trN = EVAL_SM_TEST_MAPFIT_TRACE_N()
  local trAll = EVAL_SM_TEST_MAPFIT_TRACE_ALL()
  eq(trN > 0, true, "⑨★折算取证环有记录（实测 " .. tostring(trN) .. " 条）")
  eq(string.find(trAll, "探测：", 1, true) ~= nil, true, "⑨★★记下了「探测」（缩放 1 vs 0.7 各读到多少屏幕宽）")
  eq(string.find(trAll, "抓原值：", 1, true) ~= nil, true, "⑨★★记下了「抓原值」（含读时外框缩放 ⇒ 自证自然档）")
  eq(trN <= 60, true, "⑨★取证环有界（≤60 行；实测 " .. tostring(trN) .. "）")
  pcall(EVAL_SM_SET, false)
  eq(string.find(EVAL_SM_TEST_MAPFIT_TRACE_ALL(), "开关 OFF：", 1, true) ~= nil, true, "⑨★★记下了「开关 OFF」（策略/动过没/原值条数）")
  eq(type(A7) == "table", true, "⑨夹具在位（A7 = 那批纹理里的第一个）")
  -- 收尾
  pcall(EVAL_SM_SET, false)
  rawset(_G, "WorldMapDetailFrame", savedFr)
  rawset(_G, "WorldMapFrame", savedWm)
  rawset(_G, "UISpecialFrames", savedEsc)
  rawset(_G, "EH_SM_COORDS", nil)
  rawset(_G, "EH_SM_DRAG", nil)
  cfg.tb = savedTb
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  if fails0 == TESTASSERT_FAILS then
    print("GROUP 232 (探索层纹理：两种客户端模型各自正确（显示=原值×es / 逻辑折一次）· 关再开不连乘 · 策略三档 · 原值自然档 · 关闭收钩子 · 取证环): PASS")
  end
end
-- ===== 组 237（1.75.10）：世界地图的**初始位置** = 每次载入的第一次开图**一律居中** =====
-- 用户原话：「世界地图缩放开启之后,每次插件重载的初始位置能否居中.现在他有时候会乱跳到左下角位置」
-- ★为什么必须行为级验（不只是源码检查）：这一案的真值在**存档**里 —— `SM_CFG.px/py` 是跨会话继承的
--   屏幕中心偏移，本客户端几何读回含缩放 ⇒ 那个值一旦算歪就会被永久沿用（每次开图都按它摆）。
--   源码检查只能证明「代码里有清」，行为断言才能证明「脏值真的清掉了、而且真的摆到正中了」。
do
  local fails0 = TESTASSERT_FAILS
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  local savedTb = cfg.tb
  local savedPx, savedPy = EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py
  -- 前置：读值口在位（缺了下面的断言会静默跳过 = 组 224 那次的教训）
  local n237 = 0
  for _, f in ipairs({ "EVAL_SM_TEST_POS_STATE", "EVAL_SM_TEST_POS_REARM", "EVAL_SM_TEST_DRAG" }) do
    if type(_G[f]) ~= "function" then n237 = n237 + 1 end
  end
  eq(n237, 0, "组237前置：位置读值口全部在位（缺 " .. n237 .. " 个）")
  local function posOf(w)
    local ok, p, rel, rp, x, y = pcall(w.GetPoint, w)
    if not ok then return "读取失败:" .. tostring(p) end
    return tostring(p) .. "/" .. tostring(rel == UIParent and "UIParent" or rel) .. "/" .. tostring(rp)
      .. " " .. tostring(x) .. "," .. tostring(y)
  end
  -- ★★★夹具必须**自建**一个有状态的 WorldMapFrame：组 230 的假外框（WM230）**没有还原**，
  --   而本组排在它后面 ⇒ 直接读 `_G.WorldMapFrame` 拿到的是那个**没有 GetPoint** 的假件
  --   （第一版就是这么红的：`pcall(w.GetPoint, w)` 报 attempt to call a nil value ⇒ 判据恒失效）。
  local savedWm237 = rawget(_G, "WorldMapFrame")
  local WM237 = { nClear = 0, nPt = 0, sc = 1, p = nil, rel = nil, rp = nil, x = 0, y = 0 }
  WM237.SetAlpha = function() return true end
  WM237.GetAlpha = function() return 1 end
  WM237.GetScale = function() return WM237.sc end
  WM237.SetScale = function(_, v) WM237.sc = tonumber(v) or WM237.sc return true end
  WM237.EnableKeyboard = function() return true end
  WM237.ClearAllPoints = function()
    WM237.nClear = WM237.nClear + 1
    WM237.p, WM237.rel, WM237.rp, WM237.x, WM237.y = nil, nil, nil, 0, 0
  end
  WM237.SetPoint = function(_, p, rel, rp, x, y)
    WM237.nPt = WM237.nPt + 1
    WM237.p, WM237.rel, WM237.rp = p, rel, rp
    WM237.x, WM237.y = tonumber(x) or 0, tonumber(y) or 0
    return true
  end
  WM237.GetPoint = function() return WM237.p, WM237.rel, WM237.rp, WM237.x, WM237.y end
  rawset(_G, "WorldMapFrame", WM237)
  local wm237 = WM237
  eq(type(wm237.GetPoint) == "function", true, "组237前置：夹具外框带 GetPoint（假件没有它 ⇒ 位置判据会静默失效）")
  -- ① ★★★载入期这一位就是 true（= 「本次会话还没居中过」）；rearm 之后必须能回到这个状态
  eq(EVAL_SM_TEST_POS_REARM(), true, "组237①★rearm 后 posArmed = true（= /reload 后的初始状态）")
  local armed1, rc1 = EVAL_SM_TEST_POS_STATE()
  eq(armed1, true, "组237①★本次会话还没居中过（真值 = 载入期那位）")
  eq(rc1, 0, "组237①窗口期起点 = 0（还没开）")

  -- ② ★★★脏存档：塞一个「左下角」的历史偏移（正是用户报的现象）⇒ 第一次开图必须**居中**并把它清掉
  cfg.tb = { simpleMap = true }
  EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py = -700, -300
  pcall(EVAL_SM_TEST_APPLY) -- = 真实开图路径（featKeep + featApply），不碰其它配置
  eq(posOf(wm237), "CENTER/UIParent/CENTER 0,0",
    "组237②★★★第一次开图**居中**（旧偏移 -700/-300 不许生效；实测 " .. posOf(wm237) .. "）")
  local armed2, rc2, px2, py2 = EVAL_SM_TEST_POS_STATE()
  eq(px2 == nil and py2 == nil, true,
    "组237②★★★存档里的历史偏移**已清**（实测 " .. tostring(px2) .. "/" .. tostring(py2) .. "）—— 不清就会被永久继承")
  eq(armed2, false, "组237②本次会话只做一次（这位关掉了）")
  eq(rc2 > 0, true, "组237②居中窗口期已开（实测剩 " .. tostring(rc2) .. " 拍）")

  -- ③ ★★窗口期保护：客户端自己的开图流程在**我们之后**又摆了一次位置（与黑幕那条竞态同族）⇒ 重申居中
  pcall(wm237.SetPoint, wm237, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  eq(posOf(wm237), "BOTTOMLEFT/UIParent/BOTTOMLEFT 0,0", "组237③前置：确实被摆到左下角了")
  pcall(EVAL_SM_TEST_APPLY)
  eq(posOf(wm237), "CENTER/UIParent/CENTER 0,0",
    "组237③★★窗口期内**重申居中**（这才治得了用户说的「有时候」；实测 " .. posOf(wm237) .. "）")

  -- ④ 窗口期**有界**（不是常驻重申）
  local guard = 0
  while select(2, EVAL_SM_TEST_POS_STATE()) > 0 and guard < 200 do EVAL_SM_TEST_APPLY() guard = guard + 1 end
  eq(select(2, EVAL_SM_TEST_POS_STATE()), 0, "组237④★窗口期会走完（用 " .. tostring(guard) .. " 拍；有界）")
  eq(guard < 200, true, "组237④★★窗口期**有界**（不许变成常驻重申 —— 那会跟用户/客户端抢位置）")
  pcall(wm237.SetPoint, wm237, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  pcall(EVAL_SM_TEST_APPLY)
  eq(posOf(wm237), "BOTTOMLEFT/UIParent/BOTTOMLEFT 0,0",
    "组237④★窗口期过后**不再插手**（实测 " .. posOf(wm237) .. "）")

  -- ⑤ 用户一拖拽 ⇒ 立刻让出窗口期（否则刚拖到位就被拉回正中）
  pcall(EVAL_SM_TEST_POS_REARM)
  pcall(EVAL_SM_TEST_APPLY)
  eq(select(2, EVAL_SM_TEST_POS_STATE()) > 0, true, "组237⑤前置：窗口期已开")
  local dg = EVAL_SM_TEST_DRAG()
  eq(type(dg) == "table" or type(dg) == "userdata", true, "组237⑤拖拽柄读值口拿得到真身（实测 " .. tostring(dg) .. "）")
  local okg, h = pcall(dg.GetScript, dg, "OnDragStart")
  eq(okg and type(h) == "function", true, "组237⑤★★拖拽柄上真的挂着 OnDragStart（脚本能点火）")
  if okg and type(h) == "function" then pcall(h) end
  eq(select(2, EVAL_SM_TEST_POS_STATE()), 0, "组237⑤★★★用户一开始拖 ⇒ 窗口期立刻清 0（不跟用户抢位置）")

  -- ⑥ 本会话内的位置记忆照旧生效（口径 = 「会话内有效」，不是「位置功能没了」）
  pcall(EVAL_SM_TEST_POS_REARM)
  pcall(EVAL_SM_TEST_APPLY) -- 用掉「首次」那一次（会清 px/py）
  EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py = 123, -45
  pcall(EVAL_SM_TEST_APPLY)
  eq(posOf(wm237), "CENTER/UIParent/CENTER 123,-45",
    "组237⑥★★本会话内拖过之后：位置记忆照旧（实测 " .. posOf(wm237) .. "）")

  -- 收尾（夹具自清 + 把位置口径还原成「本次会话还没居中过」，别影响后面的组）
  rawset(_G, "WorldMapFrame", savedWm237)
  cfg.tb = savedTb
  EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py = savedPx, savedPy
  pcall(EVAL_SM_TEST_POS_REARM)
  if fails0 == TESTASSERT_FAILS then
    print("GROUP 237 (世界地图初始位置：每次载入首次开图一律居中 · 清跨会话脏偏移 · 有界窗口期重申 · 拖拽即让位 · 会话内记忆照旧): PASS")
  end
end
-- ===== 组 253（1.75.13）：「探索层坐标丢失 / 全部图层挤在左下重叠」全案 =====
-- 用户报障原话：「排查工具箱->缩放大地图->探索层额外处理异常: 某些地图打开之后会将探索层的坐标丢失.
--   全部图层都集中在左下区域重叠,图2,图3就是这个问题,排查一下原因.」
-- 真机存档实证（`LIHAIBOAS2` 的 `simpleMapCfg.mapFitOrig`）：8 条原值里 **6 条完全相同**（155,-403 240×185），
--   而 `WorldMapOverlay1..N` 是客户端**按序号逐图复用**的（一图一套矩形、用不到的 `:Hide()` 且不清几何）
--   ⇒ 任何真实版式都不可能是「6 条同一矩形」。那批值 = 「客户端还没布局 / 本图不用」的残留几何。
-- ★本组钉五条（缺一条，用户那个现象就会回来）：
--   ① 原值**按地图身份分桶**（`mapFitOrig[地图身份][纹理名]`），换图**当场作废**内存记录并重抓；
--   ② 折算用的是**本图**的矩形，绝不是上一张图的（= 用户看到的「坐标丢失」）；
--   ③ 只碰**本图在用**的层（IsShown / GetTexture），隐藏与没贴图的层一个几何都不碰（= 「全部重叠」）；
--   ④ 抓原值要**等版式稳定**（开图那一瞬抓到的是残留几何 = ① 里那批脏值的来源）；
--   ⑤ 还原**只还本图写过的层**（旧写法会把别的图的矩形又写一遍，用户自己救不回来）。
do
  local fails253 = TESTASSERT_FAILS
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  local savedTb = cfg.tb
  local savedFr = rawget(_G, "WorldMapDetailFrame")
  local savedWm = rawget(_G, "WorldMapFrame")
  local savedGMI, savedGNMO, savedGMOI = rawget(_G, "GetMapInfo"), rawget(_G, "GetNumMapOverlays"), rawget(_G, "GetMapOverlayInfo")
  local savedPx, savedPy = EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py
  local tick = rawget(_G, "EH_SM_FEAT")
  local function ticks(n) for _ = 1, n do EVAL_TEST_FIRE_UPDATE(tick, 0.05) end end

  -- ① 客户端假数据：两张地图 + 一张「零叠加层」的图；三张图的矩形**互不相同**（真机就是这样）
  local CUR = "MapA"
  local CLIENT = {
    MapA = { { "OverlayA1", 240, 185, 155, 403 }, { "OverlayA2", 150, 128, 295, 385 }, { "OverlayA3", 128, 165, 502, 221 } },
    MapB = { { "OverlayB1", 300, 200, 10, 20 }, { "OverlayB2", 215, 215, 355, 320 } },
  }
  -- 假画布上 5 个非瓦片纹理：1~3 = 本图在用的（不提供 IsShown/GetTexture = 「判不出」⇒ 放行）；
  --   4 = 客户端**隐藏**的（IsShown=false）；5 = **没贴图**的（GetTexture=nil）—— 这两个正是旧版被写坏的那批。
  local FIX = {
    A = { { 155, -403, 240, 185 }, { 295, -385, 150, 128 }, { 502, -221, 128, 165 }, { 999, -999, 50, 50 }, { 111, -222, 33, 44 } },
    B = { { 10, -20, 300, 200 }, { 355, -320, 215, 215 }, { 7, -9, 40, 30 }, { 999, -999, 50, 50 }, { 111, -222, 33, 44 } },
    Z = { { 5, -5, 20, 20 }, { 6, -6, 21, 21 }, { 7, -7, 22, 22 }, { 999, -999, 50, 50 }, { 111, -222, 33, 44 } },
  }
  local W = {}
  local sc = 1
  W.GetScale = function() return sc end
  W.SetScale = function(_, v) sc = tonumber(v) or sc return true end
  W.GetAlpha = function() return 1 end
  W.SetAlpha = function() return true end
  W.ClearAllPoints = function() return true end
  W.SetPoint = function() return true end
  W.GetEffectiveScale = function() return sc end
  W.GetPoint = function() return nil end
  local FR = { R = {} }
  FR.GetName = function() return "WorldMapDetailFrame" end
  FR.IsShown = function() return true end
  FR.GetScale = function() return 1 end
  FR.GetParent = function() return W end
  FR.GetEffectiveScale = function() return sc end
  FR.GetRegions = function() local r = FR.R return r[1], r[2], r[3], r[4], r[5] end
  local T = {}
  for i = 1, 5 do
    local t = { nm = "MapOverlay" .. i, idx = i, x = 0, y = 0, w = 0, h = 0, ngeom = 0 }
    t.GetObjectType = function() return "Texture" end
    t.GetName = function() return t.nm end
    t.GetPoint = function() return "TOPLEFT", FR, "TOPLEFT", t.x, t.y end
    t.GetWidth = function() return t.w end
    t.GetHeight = function() return t.h end
    t.GetLeft = function() return t.x end
    t.GetTop = function() return t.y end
    if i == 4 then t.IsShown = function() return false end end          -- 客户端隐藏（本图不用）
    if i == 5 then t.GetTexture = function() return nil end end         -- 客户端没贴图（本图不用）
    t.ClearAllPoints = function() t.ngeom = t.ngeom + 1 end
    t.SetPoint = function(_, p, rel, rp, nx, ny) t.ngeom = t.ngeom + 1 t.x = nx t.y = ny return true end
    t.SetWidth = function(_, v) t.ngeom = t.ngeom + 1 t.w = v return true end
    t.SetHeight = function(_, v) t.ngeom = t.ngeom + 1 t.h = v return true end
    T[i] = t
  end
  FR.R = { T[1], T[2], T[3], T[4], T[5] }
  local function applyFix(setName)
    local g = FIX[setName] or {}
    for i = 1, 5 do
      local e = g[i]
      if e then T[i].x, T[i].y, T[i].w, T[i].h = e[1], e[2], e[3], e[4] end
      T[i].ngeom = 0
    end
  end
  local function geomSum() local n = 0 for i = 1, 5 do n = n + T[i].ngeom end return n end
  rawset(_G, "WorldMapDetailFrame", FR)
  rawset(_G, "WorldMapFrame", W)
  rawset(_G, "GetMapInfo", function() return CUR, 668, 1002 end)
  rawset(_G, "GetNumMapOverlays", function() return table.getn(CLIENT[CUR] or {}) end)
  rawset(_G, "GetMapOverlayInfo", function(i)
    local e = (CLIENT[CUR] or {})[tonumber(i) or 0]
    if not e then return nil end
    return e[1], e[2], e[3], e[4], e[5], 0, 0
  end)

  -- 前置：新读值口全部在位（缺一个 ⇒ 后面的断言会静默跳过）
  local ports253 = { "EVAL_SM_TEST_MAPFIT_MAPKEY", "EVAL_SM_TEST_MAPFIT_INUSE", "EVAL_SM_TEST_MAPFIT_WROTE",
                     "EVAL_SM_TEST_MAPFIT_DUMP", "EVAL_SM_TEST_MAPFIT_BUCKET", "EVAL_SM_TEST_MAPFIT_NEWMAP" }
  local miss253 = 0
  for i = 1, table.getn(ports253) do if type(_G[ports253[i]]) ~= "function" then miss253 = miss253 + 1 end end
  eq(miss253, 0, "组253前置：地图身份/在用判定/清单的读值口全部在位（缺 " .. miss253 .. " 个）")
  eq(type(tick) == "table" or type(tick) == "userdata", true, "组253前置：tick 帧在位（走真机 OnUpdate 通道）")

  -- ② 第一张图：开启 ⇒ 抓原值必须落在**本图**的桶里
  cfg.tb = { simpleMap = false }
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  CUR = "MapA"
  applyFix("A")
  cfg.tb = { simpleMap = true }
  pcall(EVAL_SM_SET, true)
  local mkA, ageA = EVAL_SM_TEST_MAPFIT_MAPKEY()
  eq(mkA, "MapA:668x1002", "②★★地图身份按 GetMapInfo 现算（文件名 + 纹理尺寸；实测 " .. tostring(mkA) .. "）")
  eq(ageA, 0, "②★版式计时从 0 起（开图/换图那一刻）")
  local nbA0, naA = EVAL_SM_TEST_MAPFIT_BUCKET("MapA:668x1002")
  eq(naA, 3, "②★★原值落在**本图**的桶里 3 条（实测 " .. tostring(naA) .. "；隐藏/没贴图的 2 个不算）")
  eq(nbA0 >= 1, true, "②★存档按地图分桶（实测 " .. tostring(nbA0) .. " 个桶）")
  -- ②b ★★★让 MapA **真的折算一次**（`SMFIT.rec` 采纳 = 后面「换图必须作废」的前提）：
  --   不先采纳就测不出「跨图复用」—— 变异 M2（smFitNewMap 不清 rec）第一版就是这么漏网的。
  ticks(8)
  eq(EVAL_SM_TEST_MAPFIT_REC(), 3, "②b★本图记录已被采纳（实测 " .. tostring(EVAL_SM_TEST_MAPFIT_REC()) .. " 条）")
  eq(math.abs(T[1].x - 155 * 0.7) < 0.01, true,
    string.format("②b★MapA 这一轮真的折了一次（T1 实测 %.1f，期望 %.1f）", T[1].x, 155 * 0.7))

  -- ③ 换到 MapB：客户端把同一批纹理重摆成 B 的矩形（真机行为）⇒ 旧记录当场作废 + 等版式稳定
  CUR = "MapB"
  applyFix("B")
  ticks(3) -- 0.15s < 0.4s
  eq(select(2, EVAL_SM_TEST_MAPFIT_NEEDFOLD()), false,
    "③★★换图后**先等版式稳定**（0.15s 时还没抓原值 —— 旧写法开图那一瞬就抓，抓到的正是「还没布局」的残留几何）")
  eq(EVAL_SM_TEST_MAPFIT_MAPKEY(), "MapB:668x1002", "③★★换图 ⇒ 地图身份当场更新（旧记录已作废）")
  ticks(8) -- 累计 0.55s ≥ 0.4s
  eq(select(2, EVAL_SM_TEST_MAPFIT_NEEDFOLD()), true, "③★满 0.4s 之后才抓原值（累计 0.55s）")
  local nb2, nbB = EVAL_SM_TEST_MAPFIT_BUCKET("MapB:668x1002")
  eq(nbB, 3, "③★★原值记进**新图的桶**（实测 " .. tostring(nbB) .. " 条）")
  eq(nb2 >= 2, true, "③★两张地图各自一个桶、互不覆盖（实测 " .. tostring(nb2) .. " 个桶）")
  local _k1, fr1, rx1, ry1, rw1 = EVAL_SM_TEST_MAPFIT_FROM(1)
  eq(rw1 == 300 or rw1 == 215 or rw1 == 40, true,
    "③★★★本图的记录 = **本图**的几何（宽 " .. tostring(rw1) .. "；若是 240/150/128 就说明还在用上一张图的）")

  -- ④ 折算用的是**本图**矩形（用户现象的直接回归哨兵）
  ticks(6)
  local sumB = {}
  for i = 1, 3 do sumB[i] = T[i].x end
  eq(math.abs(T[1].x - 10 * 0.7) < 0.01 and math.abs(T[1].w - 300 * 0.7) < 0.01, true,
    string.format("④★★★折算用**本图**矩形（T1 实测 %.1f/%.1f，期望 %.1f/%.1f；旧写法会用上一张图的 155/240×0.7=%.1f/%.1f）",
      T[1].x, T[1].w, 10 * 0.7, 300 * 0.7, 155 * 0.7, 240 * 0.7))
  eq(math.abs(T[2].x - 355 * 0.7) < 0.01, true,
    string.format("④★★T2 也是本图矩形（实测 %.1f，期望 %.1f）", T[2].x, 355 * 0.7))
  eq(sumB[1] ~= sumB[2] and sumB[2] ~= sumB[3], true,
    "④★★三个层**各在各的位置**（不再全都挤到同一格 —— 用户报的「全部图层集中在左下区域重叠」）")

  -- ⑤ 只碰本图在用的层（隐藏 / 没贴图的一个几何都不碰）
  local use4 = EVAL_SM_TEST_MAPFIT_INUSE(4)
  local use5 = EVAL_SM_TEST_MAPFIT_INUSE(5)
  local use1 = EVAL_SM_TEST_MAPFIT_INUSE(1)
  eq(use4, false, "⑤★★★客户端**隐藏**的层判为「本图不用」⇒ 一个几何都不碰")
  eq(use5, false, "⑤★★★**没贴图**的层同样跳过（旧写法对它们照写 = 那批「挤在同一处」的层）")
  eq(use1, true, "⑤★反向哨兵：读不到 IsShown/GetTexture 的层**照旧处理**（判不出就不拦，别把功能判死）")
  eq(T[4].ngeom == 0 and T[5].ngeom == 0, true,
    "⑤★★隐藏/没贴图层**零几何调用**（实测 " .. tostring(T[4].ngeom) .. "/" .. tostring(T[5].ngeom) .. "）")
  eq(T[1].ngeom > 0, true, "⑤★反向哨兵：在用的层确实被折算过（实测 " .. tostring(T[1].ngeom) .. " 次）")
  -- ⑤b ★★★**脏存档复现**（用户那台机器就是这个状态）：给「本图不用」的两个层**种一条旧记录**，再跑几拍 ——
  --   有闸门 ⇒ 一个几何都不发；把「本图在用」这条判据去掉（变异 M1）⇒ 立刻照写 = 用户看到的「全部重叠」现场。
  --   ★为什么必须有这一条：不种记录时它们本来就没记录、也就不会被写 ⇒ 断言只能证明「没记录所以没写」，
  --     证明不了「有记录也不会写」（变异 M1 实测正是这么漏网的）。
  EH_SIMPLEMAP_CFG.mapFitOrig["MapB:668x1002"]["MapOverlay4"] =
    { x = 1, y = -2, w = 30, h = 40, p = "TOPLEFT", rel = "WorldMapDetailFrame", rp = "TOPLEFT" }
  EH_SIMPLEMAP_CFG.mapFitOrig["MapB:668x1002"]["MapOverlay5"] =
    { x = 3, y = -4, w = 50, h = 60, p = "TOPLEFT", rel = "WorldMapDetailFrame", rp = "TOPLEFT" }
  T[4].ngeom, T[5].ngeom = 0, 0
  local x4b, x5b = T[4].x, T[5].x
  ticks(6)
  eq(T[4].ngeom + T[5].ngeom, 0,
    "⑤b★★★存档里**种着**这两个层的旧记录，本图不用 ⇒ 仍然一个几何都不发（实测 " .. tostring(T[4].ngeom + T[5].ngeom) .. " 次）")
  eq(T[4].x == x4b and T[5].x == x5b, true, "⑤b★★几何也没被写走（旧写法就是拿这份脏记录把它们全写成一格）")

  -- ⑥ 客户端说「本图 0 条叠加层」⇒ 一个几何都不该碰
  CUR = "MapZ"
  applyFix("Z")
  ticks(14)
  eq(select(2, EVAL_SM_TEST_MAPFIT_BUCKET("MapZ:668x1002")), 0, "⑥★零叠加层的地图不抓原值")
  eq(geomSum(), 0, "⑥★★零叠加层 ⇒ 几何**零调用**（实测 " .. tostring(geomSum()) .. "）")
  eq((EVAL_SM_TEST_MAPFIT_MAPKEY()), "MapZ:668x1002", "⑥★地图身份已跟到本图")

  -- ⑦ 还原**只还本图我们写过的层**（换图之后调还原 = 一个几何都不该发）
  CUR = "MapB"
  applyFix("B")
  ticks(14) -- 重新抓 MapB + 折算一次（逐层记账）
  eq(EVAL_SM_TEST_MAPFIT_WROTE(T[1].nm), "MapB:668x1002",
    "⑦★折算时逐层记账 = 本图身份（实测 " .. tostring(EVAL_SM_TEST_MAPFIT_WROTE(T[1].nm)) .. "）")
  CUR = "MapA" -- 换一张图（wroteKeys 里还是 MapB）⇒ 还原必须**什么都不做**
  applyFix("A")
  local gA = geomSum()
  local nRA = select(1, EVAL_SM_TEST_MAPFIT_RESTORE())
  eq(nRA, 0, "⑦★★★换图后还原：本图一个都没写过 ⇒ 还原 0 个（旧写法会把 MapB 的矩形写到 MapA 上）")
  eq(geomSum() - gA, 0, "⑦★★而且几何零调用（实测 " .. tostring(geomSum() - gA) .. "）")
  CUR = "MapB" -- 回到写过的那张图 ⇒ 这次才真的还回去
  local nRB = select(1, EVAL_SM_TEST_MAPFIT_RESTORE())
  eq(nRB > 0, true, "⑦★回到写过的那张图 ⇒ 还原真的发生（实测 " .. tostring(nRB) .. " 个）")
  eq(math.abs(T[1].x - 10) < 0.01 and math.abs(T[1].w - 300) < 0.01, true,
    string.format("⑦★★几何回到**本图**原值（实测 %.1f/%.1f，期望 10/300）", T[1].x, T[1].w))

  -- ⑧ 只读取证清单（用户要求「排查原因」⇒ 得能一眼看出谁写的、该是多少）
  local lines253 = EVAL_SM_TEST_MAPFIT_DUMP()
  eq(type(lines253) == "table" and table.getn(lines253) >= 5, true,
    "⑧★清单有多行（实测 " .. tostring(type(lines253) == "table" and table.getn(lines253) or "非表") .. " 行）")
  local dump253 = table.concat(lines253 or {}, "\n")
  for _, needle in ipairs({ "地图身份=MapB:668x1002", "客户端叠加层=2", "本图在用=", "本图已写=",
                            "MapOverlay1", "客户端叠加层 1：OverlayB1 300x200 @(10,20)" }) do
    eq(string.find(dump253, needle, 1, true) ~= nil, true, "⑧★★清单里有「" .. needle .. "」")
  end
  eq(string.find(dump253, "本图在用=否", 1, true) ~= nil, true, "⑧★★清单把「本图不用」的层如实标出来（那批层我们一个几何都不碰）")

  -- ⑨ 旧存档自愈：版本戳 2（跨图污染的那一代）必须整块丢弃
  EH_SIMPLEMAP_CFG.mapFitVer = 2
  EH_SIMPLEMAP_CFG.mapFitOrig = { MapA = { MapOverlay1 = { x = 1, y = 2, w = 3, h = 4 } } }
  eq(EVAL_SM_TEST_MAPFIT_MIGRATE(), true, "⑨★版本戳 2 的旧原值被认成「不可信」")
  eq(EVAL_SM_TEST_MAPFIT_ORIG(), 0, "⑨★★整块丢弃（实测剩 " .. tostring(EVAL_SM_TEST_MAPFIT_ORIG()) .. " 条）")
  eq(EH_SIMPLEMAP_CFG.mapFitVer, 3, "⑨★迁移后版本戳 = 3（下一次载入不再重复丢弃）")

  -- 夹具自清
  pcall(EVAL_SM_SET, false)
  rawset(_G, "WorldMapDetailFrame", savedFr)
  rawset(_G, "WorldMapFrame", savedWm)
  rawset(_G, "GetMapInfo", savedGMI)
  rawset(_G, "GetNumMapOverlays", savedGNMO)
  rawset(_G, "GetMapOverlayInfo", savedGMOI)
  cfg.tb = savedTb
  EH_SIMPLEMAP_CFG.px, EH_SIMPLEMAP_CFG.py = savedPx, savedPy
  pcall(EVAL_SM_TEST_POS_REARM)
  pcall(EVAL_SM_TEST_MAPFIT_RESET)
  if fails253 == TESTASSERT_FAILS then
    print("  原值按地图身份分桶 · 换图当场作废 · 只碰本图在用的层 · 抓原值等版式稳定 · 还原只还写过的层 · 零叠加层零动作")
    print("GROUP 253 (探索层·原值按地图身份分桶：换图作废+重抓 · 折算用本图矩形 · 隐藏/没贴图的层零几何 · 零叠加层零动作 · 还原只还写过的层 · 只读清单): PASS")
  end
end
EVAL_TEST_MOD_DONE("SimpleMap") -- ★跑到底的握手（见文件头 ③）：TOOL TEST FILES CHECK 拿它对账
