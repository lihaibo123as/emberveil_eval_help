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
EVAL_TEST_MOD_DONE("SimpleMap") -- ★跑到底的握手（见文件头 ③）：TOOL TEST FILES CHECK 拿它对账
