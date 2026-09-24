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
  local c1, r1, rec1 = EVAL_SM_TEST_MAPFIT_APPLY(0.7)
  eq(c1 == 2, true, "⑥两张叠加层都被折算（实测 " .. tostring(c1) .. "）")
  eq(rec1 == 2, true, "⑥首次应用记下 2 条原值（还原的唯一依据）")
  eq(EVAL_SM_TEST_MAPFIT_ORIG(), 2, "⑥原值进了存档子树 SM_CFG.mapFitOrig（/reload 后还原靠它）")
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

EVAL_TEST_MOD_DONE("SimpleMap") -- ★跑到底的握手（见文件头 ③）：TOOL TEST FILES CHECK 拿它对账
