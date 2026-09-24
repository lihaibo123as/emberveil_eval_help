-- tests/tools/LayerFix.lua
-- 【工具模块自带测试】图层特殊处理（tools/LayerFix.lua）的断言组。
-- 用户 1.74.34：「test 相关的搬迁到对应工具类子文件内自身管理。」
--   ⇒ 本模块的测试三件套都归模块自己管：**读值口**写在 tools/LayerFix.lua 里（EVAL_LF_TEST_*）·
--     **断言组**就是本文件（组 223）· **源码检查**在同级 tests/checks/LayerFix.js。
-- ★纪律（四条，越界即静默失效）：
--   ① 本文件**不进 toc、不随包发布**（tests/ 不在发布清单里）——只在测试里被 harness 加载；
--   ② 断言一律用 **EVAL_TEST_EQ**（test_assert.lua 暴露的**同一个** eq）⇒ 失败格式与其它组逐字一致，
--      不许在本文件里自造一套判定（自造 = 两套口径，早晚打架）；
--   ③ **最后一行必须调 `EVAL_TEST_MOD_DONE("<模块名>")`** —— 它是「这个文件真的跑到底了」的握手信号，
--      `TOOL TEST FILES CHECK` 拿它和 tests/tools/*.lua 的文件数对账：**少跑一个文件 = 整组断言静默消失**
--      （本项目最恨的那种：套件照旧 ALL TESTS PASS，功能却没人验）；
--   ④ 夹具**自建自清**（不依赖 test_assert.lua 里别的组留下的状态）。
local eq = EVAL_TEST_EQ

-- ===== 组 223（1.74.34）：图层特殊处理（Layer Fixes = 独立模块 tools/LayerFix.lua + 工具箱多选下拉）=====
-- 用户原话：
--   「能否对固定的某个层内的最后2个纹理做特殊处理.比如隐藏这2个纹理」
--   「以上如果可行.可以在工具箱->UI 工具->添加个图层特处理->设置/重置 ,设置功能支持下拉,
--     目前里面添加个动作条狮鹫 ,支持多选.切换显示选中的特殊处理.」
--   「以上特殊处理定义规范配置.以后可能还有其他特殊处理, 弹窗下拉UI参考图层拖拽->设置」
--   「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.只要加入嵌入点进行函数调用?」
-- 本组钉住八件事（每条都是「漏了不报错、只是静默失效或静默乱改界面」的那种）：
--   ① 定义规范：LF_FIXES 每条都有 key/kind/layer/pick/label/tip，key 唯一非空；默认**一条都不选**；
--   ② 菜单形状：内容唯一来源 = LF_FIXES，分组标题行走 locked、初始勾选为空；
--   ③ 勾上 ⇒ **只**藏层里最后 N 个纹理（前面的一个都不许动）+ 如实播报层名与贴图路径；幂等；
--   ④ 取消勾选 ⇒ 当场还原；★客户端自己藏着的**不许**被我们 Show 出来；★读不到原状时按「显示」还原；
--   ⑤ 层不在 ⇒ 一个对象都不动 + 如实播报（绝不猜着改）；
--   ⑥ 存档持久化（**本模块自己的子树 layerFix**）+ 旧位置一次性迁移 + 重开后守护；
--   ⑦ 启动期**有界**复查：层晚出现补一次、被显示回来再藏一次，窗口跑完**摘脚本**；
--   ⑧ 工具箱那一行：模块行注册表里有它 · **没有勾选框** · [设置]/[重置] 几何不重叠 · 多选下拉 ·
--      走真实回调当场生效（= 嵌入点真的接通了，不是「只写了行数据」）。
do
  local savedFixStore223 = rawget(_G, "EVAL_HELP_CONFIG").layerFix
  local savedDfStore223 = rawget(_G, "EVAL_HELP_CONFIG").dragFrames
  local savedChat223 = TEST.chat
  local savedTips223 = TEST.tipLines
  local savedCombat223 = TEST.inCombat
  local wasOn223 = EVAL_DF_ENABLED()
  local savedTab223 = (type(EVAL_HELP_CFG_TAB) == "function") and EVAL_HELP_CFG_TAB() or nil
  local savedLayerG223 = rawget(_G, "MainMenuBarArtFrame")
  local savedBarG223 = rawget(_G, "MainMenuBar")

  -- 干净起点：真值表**不存在** = 一条特殊处理都没选（★与「图层选择」的语义相反，见组首注释）
  rawget(_G, "EVAL_HELP_CONFIG").layerFix = nil
  rawget(_G, "EVAL_HELP_CONFIG").dragFrames = nil
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  EVAL_LF_TEST_STOP()
  TEST.inCombat = false

  -- 夹具：层 = MainMenuBarArtFrame（用户真机截图里它是 MainMenuBar 的子帧，717x37），
  --   里面 6 个纹理（截图里 #17…#22）+ **1 个字体串**（截图里 #23）——
  --   ★字体串在区域顺序里**排在最后**，正好用来验「不数错类型」（写错就会把字体串当纹理、藏错对象）。
  local layer223 = CreateFrame("Frame", "MainMenuBarArtFrame", UIParent)
  layer223:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -700)
  layer223:SetWidth(717) layer223:SetHeight(37)
  local texs223, tstate223, tmode223 = {}, {}, {}
  local function mkTex223(i)
    local t = layer223:CreateTexture(nil, "ARTWORK")
    rawset(t, "GetObjectType", function() return "Texture" end)
    rawset(t, "__tex", "Interface/MainMenuBar/piece" .. tostring(i))
    tstate223[i] = true      -- ★真机上 CreateTexture 出来的纹理**默认就是显示的**（桩默认 nil，这里显式建立）
    tmode223[i] = "read"
    rawset(t, "Show", function() tstate223[i] = true return true end)
    rawset(t, "Hide", function() tstate223[i] = false return true end)
    rawset(t, "IsShown", function()
      if tmode223[i] == "nil" then return nil end   -- 模拟「读不到原状」
      return tstate223[i]
    end)
    texs223[i] = t
    return t
  end
  for i = 1, 6 do mkTex223(i) end
  local fs223 = layer223:CreateFontString(nil, "OVERLAY")
  rawset(fs223, "GetObjectType", function() return "FontString" end)
  rawset(layer223, "GetRegions", function()
    local all = {}
    for i = 1, 6 do table.insert(all, texs223[i]) end
    table.insert(all, fs223)   -- ★区域顺序：6 个纹理在前、字体串在最后（与真机截图一致）
    return unpack(all)
  end)

  -- ① 定义规范 + 默认一条都不选
  local fixRaw223 = EVAL_LF_TEST_FIXES_RAW()
  local nFix223 = table.getn(fixRaw223)
  eq(nFix223 >= 1, true, "组223① 定义表 LF_FIXES 里至少有一条特殊处理（实测 " .. tostring(nFix223) .. " 条）")
  local seenKey223, badSpec223, gry223 = {}, 0, nil
  for i = 1, nFix223 do
    local f = fixRaw223[i]
    if type(f) ~= "table" then badSpec223 = badSpec223 + 1
    else
      if type(f.key) ~= "string" or f.key == "" or seenKey223[f.key] then badSpec223 = badSpec223 + 1 end
      seenKey223[f.key or "?"] = true
      if f.kind ~= "hideTex" then badSpec223 = badSpec223 + 1 end
      if type(f.layer) ~= "table" or type(f.layer.cands) ~= "table" or table.getn(f.layer.cands) == 0 then
        badSpec223 = badSpec223 + 1
      end
      if type(f.pick) ~= "table" or (f.pick.last == nil and f.pick.path == nil) then badSpec223 = badSpec223 + 1 end
      if type(f.label) ~= "function" or type(f.tip) ~= "function" then badSpec223 = badSpec223 + 1 end
      if f.key == "gryphon" then gry223 = f end
    end
  end
  eq(badSpec223, 0, "组223①★★ 每条定义都符合规范（key 唯一非空 · kind · layer.cands · pick · label/tip；坏 " ..
    tostring(badSpec223) .. " 条）")
  eq(gry223 ~= nil, true, "组223① 表里有「动作条狮鹫」这条（key = gryphon）")
  local lblGry223 = (gry223 and type(gry223.label) == "function") and gry223.label() or nil
  eq(type(lblGry223) == "string" and lblGry223 ~= "" and lblGry223 ~= "gryphon", true,
    "组223①★ 取词函数现取到真文案（「" .. tostring(lblGry223) .. "」；取不到会退回 key 本身）")
  local cnt0_223, tot0_223 = EVAL_LF_COUNT()
  eq(cnt0_223 == 0 and tot0_223 == nFix223, true,
    "组223①★★★ 默认**一条都不选**（" .. tostring(cnt0_223) .. "/" .. tostring(tot0_223) ..
    "；与「图层选择」的「表不存在 = 全选」相反：特殊处理绝不擅自改界面）")
  eq(EVAL_LF_ENABLED("gryphon"), false, "组223①★ 读值口也如实报告「没选」")
  local sum0_223 = EVAL_LF_SUMMARY()
  eq(type(sum0_223) == "string" and sum0_223 ~= "" and string.find(sum0_223, lblGry223, 1, true) == nil, true,
    "组223①★ 摘要（一行「当前状态」）：没选时不列任何处理名（「" .. tostring(sum0_223) .. "」）")
  -- ★★独立模块纪律：老位置（框拖拽模块）不许再有任何特殊处理代码/真值
  eq(rawget(_G, "EVAL_LF_TEST_ROW") ~= nil and type(rawget(_G, "EVAL_LF_TEST_ROW")) == "function", true,
    "组223①★★ 模块对外交出工具箱行的渲染函数（Toolbox 只按名字调它）")
  eq(type(rawget(_G, "EVAL_TB_MOD_ROWS")) == "table"
      and type(rawget(_G, "EVAL_TB_MOD_ROWS")["layerFix"]) == "function", true,
    "组223①★★★ 模块行的渲染函数**已登记**进工具箱注册表（EVAL_TB_MOD_ROWS.layerFix）—— 嵌入点接通的前提")

  -- ② 菜单形状（**唯一来源 = LF_FIXES**；分组标题行走 locked、keys 留空 ⇒ 回调天然跳过）
  local items223, locked223, tips223, sel223, keys223 = EVAL_LF_MENU()
  local nItems223 = table.getn(items223)
  eq(table.getn(locked223) == nItems223 and table.getn(keys223) == nItems223, true,
    "组223② 菜单的 items/locked/keys 三表等长（" .. tostring(nItems223) .. " 项）")
  local heads223, rows223, badRow223, selN223, tipN223 = 0, 0, 0, 0, 0
  for i = 1, nItems223 do
    if locked223[i] then
      heads223 = heads223 + 1
      if keys223[i] ~= nil then badRow223 = badRow223 + 1 end  -- 标题行不许指处理（否则点它能改配置）
    else
      rows223 = rows223 + 1
      if not seenKey223[keys223[i] or "?"] then badRow223 = badRow223 + 1 end
      if sel223[i] then selN223 = selN223 + 1 end
      if type(tips223[i]) == "string" and tips223[i] ~= "" then tipN223 = tipN223 + 1 end
    end
  end
  eq(rows223 == nFix223, true, "组223②★★ 可选项数 == 定义表条数（" .. tostring(rows223) .. "/" .. tostring(nFix223) ..
    "：以后加处理不会漏进设置）")
  eq(heads223 >= 1, true, "组223②★ 有分组标题行（" .. tostring(heads223) .. " 行；走 locked ⇒ 点不到）")
  eq(badRow223, 0, "组223②★★ 每行都指到真实处理、标题行不指（坏行 " .. tostring(badRow223) .. "）")
  eq(selN223 == 0, true, "组223②★★ 初始勾选为空（一条都没勾 ⇒ 界面一点没被改；实测 " .. tostring(selN223) .. "）")
  eq(tipN223 == rows223, true, "组223②★ 每条可选项都带悬停说明（" .. tostring(tipN223) .. "/" .. tostring(rows223) .. "）")
  local piGry223 = nil
  for i = 1, nItems223 do if keys223[i] == "gryphon" then piGry223 = i end end
  eq(piGry223 ~= nil, true, "组223② 菜单里能找到「动作条狮鹫」那一行（下标 " .. tostring(piGry223) .. "）")
  eq(items223[piGry223 or 0] == EVAL_L("TB_FIX_GRYPHON"), true,
    "组223②★ 那一行的文本 = 语言包（UI 与语言包同源：「" .. tostring(items223[piGry223 or 0]) .. "」）")

  -- ③ 勾上 ⇒ **只**藏「层内最后 2 个纹理」
  TEST.chat = ""
  eq(EVAL_LF_SET("gryphon", true), true, "组223③ 写入口接受这次勾选")
  local appliedA223, restoredA223 = EVAL_LF_SYNC()
  eq(appliedA223 == 1 and restoredA223 == 0, true,
    "组223③ 结算：新生效 " .. tostring(appliedA223) .. " 条 · 还原 " .. tostring(restoredA223) .. " 个")
  eq(texs223[5]:IsShown() == false and texs223[6]:IsShown() == false, true,
    "组223③★★★ 最后 2 个纹理被隐藏（读**真控件** IsShown）")
  local touched223 = 0
  for i = 1, 4 do if texs223[i]:IsShown() ~= true then touched223 = touched223 + 1 end end
  eq(touched223 == 0, true, "组223③★★★ **前面的纹理一个都没动**（" .. tostring(touched223) ..
    " 个被误伤 —— 判据是「最后 2 个」不是「前 2 个」）")
  local st223 = EVAL_LF_TEST_FIX_STATE().gryphon
  eq(type(st223) == "table" and st223.n == 2, true, "组223③★★ 记账里正好 2 个对象（实测 " ..
    tostring(type(st223) == "table" and st223.n or "nil") .. "）")
  eq(type(st223) == "table" and st223.layer == "MainMenuBarArtFrame", true,
    "组223③★ 记账里记下了**命中的层名**（" .. tostring(type(st223) == "table" and st223.layer or "nil") ..
    "；候选名解析命中哪个就报哪个）")
  eq(type(st223) == "table" and type(st223.paths) == "table" and st223.paths[1] ~= nil
      and string.find(tostring(st223.paths[1]), "piece5", 1, true) ~= nil, true,
    "组223③★ 记账里存下了**真贴图路径**（" .. tostring(type(st223) == "table" and st223.paths and st223.paths[1]) ..
    "；用户据此核对「藏的是不是那两个」）")
  local chatA223 = tostring(TEST.chat or "")
  eq(string.find(chatA223, "已隐藏 2 个纹理", 1, true) ~= nil, true,
    "组223③★ 播报带数字（「已隐藏 2 个纹理」）")
  eq(string.find(chatA223, "MainMenuBarArtFrame", 1, true) ~= nil, true, "组223③★ 播报带**层名**（改的是哪一层）")
  eq(string.find(chatA223, "piece5", 1, true) ~= nil, true, "组223③★ 播报带**贴图路径**（藏的是哪两个）")
  eq(string.find(chatA223, lblGry223, 1, true) ~= nil, true, "组223③★ 播报带处理名（哪一条处理干的）")

  -- ③b 幂等：再结算一次不许重新挑（重新挑会因为在往「更前面」数而藏错对象）
  TEST.chat = ""
  local appliedB223 = EVAL_LF_SYNC()
  eq(appliedB223 == 0, true, "组223③b★★ 已经生效过 ⇒ 再结算不重复生效（实测新生效 " .. tostring(appliedB223) .. " 条）")
  eq(texs223[4]:IsShown() == true, true, "组223③b★★★ 幂等哨兵：第 4 个纹理仍然显示着（没被「再藏一批」误伤）")
  eq(string.find(tostring(TEST.chat or ""), "已隐藏", 1, true) == nil, true, "组223③b★ 幂等时不重复播报")

  -- ④ 取消勾选 ⇒ 当场还原（可逆）
  TEST.chat = ""
  eq(EVAL_LF_SET("gryphon", false), true, "组223④ 写入口接受这次取消勾选")
  local appliedC223, restoredC223 = EVAL_LF_SYNC()
  eq(appliedC223 == 0 and restoredC223 == 2, true,
    "组223④★ 结算：还原 " .. tostring(restoredC223) .. " 个纹理（新生效 " .. tostring(appliedC223) .. " 条）")
  eq(texs223[5]:IsShown() == true and texs223[6]:IsShown() == true, true,
    "组223④★★★ 取消勾选 ⇒ 两个纹理**都回来了**（可逆）")
  eq(string.find(tostring(TEST.chat or ""), "已还原 2 个纹理", 1, true) ~= nil, true, "组223④★ 播报带数字（「已还原 2 个纹理」）")
  eq(EVAL_LF_SET("gryphon", true), true, "组223④ 再勾一次")
  EVAL_LF_SYNC()
  eq(texs223[5]:IsShown() == false and texs223[6]:IsShown() == false, true,
    "组223④★★ 再勾上 ⇒ 又隐藏（勾/取消都当场生效，不需要重载）")

  -- ⑤ 诚实还原：**客户端自己藏着的**不许被我们 Show 出来
  EVAL_LF_SET("gryphon", false)
  EVAL_LF_SYNC()
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  tstate223[5], tstate223[6] = true, false -- 第 6 个：**客户端自己藏着的**
  TEST.chat = ""
  EVAL_LF_SET("gryphon", true)
  EVAL_LF_SYNC()
  eq(string.find(tostring(TEST.chat or ""), "1 个本来就是隐藏的", 1, true) ~= nil, true,
    "组223⑤★★ 播报如实标出「其中 1 个本来就是隐藏的」（不把「没变化」算成「藏好了」）")
  EVAL_LF_SET("gryphon", false)
  EVAL_LF_SYNC()
  eq(texs223[5]:IsShown() == true, true, "组223⑤★★ 还原：我们藏起来的那个回来了")
  eq(texs223[6]:IsShown() == false, true,
    "组223⑤★★★ **客户端自己藏着的那个，还原后仍然隐藏**（绝不用 Show 把它弄出来）")

  -- ⑤b 读不到原状（IsShown 返回 nil）⇒ 还原按「显示」还原（否则用户看到的就是「重置了但没回来」）
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  tmode223[6], tstate223[6] = "nil", true
  EVAL_LF_SET("gryphon", true)
  EVAL_LF_SYNC()
  eq(tstate223[6], false, "组223⑤b前置：读不到原状时照样藏得下去（我们动过它）")
  EVAL_LF_SET("gryphon", false)
  EVAL_LF_SYNC()
  eq(tstate223[6], true, "组223⑤b★★★ 读不到原状 ⇒ 还原按「显示」还原（不能因为读不到就当「本来就隐藏」）")
  tmode223[6] = "read"

  -- ⑥ 层不在 ⇒ 如实缺席，**一个对象都不动**
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  for i = 1, 6 do tstate223[i] = true end
  rawset(_G, "MainMenuBarArtFrame", nil)
  rawset(_G, "MainMenuBar", nil)
  TEST.chat = ""
  EVAL_LF_SET("gryphon", true)
  local appliedD223 = EVAL_LF_SYNC()
  eq(appliedD223 == 0, true, "组223⑥★ 层不在 ⇒ 一条都没生效（实测 " .. tostring(appliedD223) .. "）")
  eq(EVAL_LF_TEST_FIX_STATE().gryphon == nil, true, "组223⑥★ 没有生效记账（不假装成功）")
  local aliveD223 = 0
  for i = 1, 6 do if tstate223[i] then aliveD223 = aliveD223 + 1 end end
  eq(aliveD223 == 6, true, "组223⑥★★★ 层不在时**一个对象都没动**（" .. tostring(6 - aliveD223) .. " 个被误改）")
  local chatD223 = tostring(TEST.chat or "")
  eq(string.find(chatD223, "没做成", 1, true) ~= nil, true, "组223⑥★★ 如实播报「没做成」（绝不静默：点了勾却什么都不发生是最糟的）")
  eq(string.find(chatD223, "没有对界面做任何改动", 1, true) ~= nil, true, "组223⑥★ 同时说清「这次没动界面」")
  rawset(_G, "MainMenuBarArtFrame", layer223) -- 层回来（模拟客户端惰加载）

  -- ⑦ [重置]（模块入口）= 还原全部 + 清空勾选 + 如实报数字
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  for i = 1, 6 do tstate223[i] = true end
  EVAL_LF_SET("gryphon", true)
  EVAL_LF_SYNC()
  eq(tstate223[5] == false and tstate223[6] == false, true, "组223⑦前置：先让它生效（两个纹理已隐藏）")
  TEST.chat = ""
  EVAL_LF_RESET()
  eq(tstate223[5] == true and tstate223[6] == true, true, "组223⑦★★★ [重置] ⇒ 还原所有已生效的处理（两个纹理都回来了）")
  local cAfter223, tAfter223 = EVAL_LF_COUNT()
  eq(cAfter223 == 0, true, "组223⑦★★★ [重置] ⇒ 勾选被清空（" .. tostring(cAfter223) .. "/" .. tostring(tAfter223) .. "）")
  eq(EVAL_LF_ENABLED("gryphon"), false, "组223⑦★ 真值（存档）里也不再有这条勾选")
  local chatE223 = tostring(TEST.chat or "")
  eq(string.find(chatE223, "已清空 1 条处理的勾选", 1, true) ~= nil, true, "组223⑦★ 播报带数字（清空了几条）")
  -- 反向哨兵：再点一次（已经没有生效项了）不许炸、不许乱改、也要有话说
  TEST.chat = ""
  EVAL_LF_RESET()
  eq(tstate223[1] == true and tstate223[5] == true, true, "组223⑦★ 无事可做的 [重置] 不改任何东西")
  eq(string.find(tostring(TEST.chat or ""), "重置完成", 1, true) ~= nil, true, "组223⑦★ 无事可做时照样如实播报（不静默）")

  -- ⑧ 存档持久化（**本模块自己的子树**）+ 旧位置一次性迁移 + 「重开后守护」
  eq(EVAL_LF_SET("gryphon", true), true, "组223⑧ 勾上")
  local lfStore223 = rawget(_G, "EVAL_HELP_CONFIG").layerFix
  eq(type(lfStore223) == "table" and type(lfStore223.fix) == "table" and lfStore223.fix.gryphon == true, true,
    "组223⑧★★★ 真值落**本模块自己的子树** `EVAL_HELP_CONFIG.layerFix.fix.gryphon = true`（键 = 处理键，不是序号）")
  eq(type(lfStore223.fix) == "table" and lfStore223.fix["1"] == nil, true,
    "组223⑧★★ 存档里**没有**按序号写的键（按序号做键 = 以后加条目就错位）")
  eq(type(rawget(_G, "EVAL_HELP_CONFIG").dragFrames) ~= "table"
      or rawget(_G, "EVAL_HELP_CONFIG").dragFrames.fix == nil, true,
    "组223⑧★★★ 老位置（dragFrames.fix）**一份都不留**（两份真值会互相打架）")
  -- 旧位置迁移：模拟 1.74.34 第一版的存档（勾选还在 dragFrames.fix 里）
  rawget(_G, "EVAL_HELP_CONFIG").layerFix = nil
  rawget(_G, "EVAL_HELP_CONFIG").dragFrames = { fix = { gryphon = true } }
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  EVAL_LF_TEST_MIGRATE(true)
  eq(EVAL_LF_ENABLED("gryphon"), true, "组223⑧★★★ 旧位置的勾选被**搬进**新子树（老用户升级后勾选不丢）")
  eq(rawget(_G, "EVAL_HELP_CONFIG").dragFrames.fix == nil, true, "组223⑧★★ 老键搬完即清（不留第二份真值）")
  -- 重开游戏：内存记账清空（对象身份不可落存档）+ 客户端把界面重建回显示态
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  for i = 1, 6 do tstate223[i] = true end
  EVAL_LF_INSTALL()          -- ★真安装入口（已 installed 则直接返回 true；这里只为口径一致）
  EVAL_LF_SYNC(true)         -- 载入期 INSTALL 里调的就是它（同一入口）
  eq(tstate223[5] == false and tstate223[6] == false, true,
    "组223⑧★★★ 重开之后按存档**又把它藏了回去**（守护生效；INSTALL 那一行本身由 `LAYER FIX WIRING CHECK` 源码级守）")

  -- ⑨ 启动期**有界**复查（1s × 5 次）：层晚出现补一次 + 被显示回来再藏一次 + 窗口跑完**摘脚本**
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  for i = 1, 6 do tstate223[i] = true end
  EVAL_LF_SET("gryphon", true)
  rawset(_G, "MainMenuBarArtFrame", nil)
  rawset(_G, "MainMenuBar", nil)
  TEST.chat = ""
  EVAL_LF_SYNC()
  eq(EVAL_LF_TEST_FIX_STATE().gryphon == nil, true, "组223⑨前置：层不在 ⇒ 当时没做成")
  rawset(_G, "MainMenuBarArtFrame", layer223) -- 层随后出现（客户端惰加载）
  local LIM223 = EVAL_LF_TEST_LIMITS()
  eq(type(LIM223) == "table" and LIM223.checks >= 1 and LIM223.period > 0, true,
    "组223⑨ 读值口交出了有界窗口的**真实上限**（" .. tostring(LIM223 and LIM223.checks) .. " × " ..
    tostring(LIM223 and LIM223.period) .. "s）")
  eq(EVAL_LF_TEST_ARM(), true, "组223⑨ 武装一次有界窗口（生产同一条 lfArm）")
  local stK223 = EVAL_LF_TEST_STATE()
  local tickF223 = stK223.frame
  eq(tickF223 ~= nil and type(tickF223.GetScript) == "function", true, "组223⑨前置：tick 帧在位")
  local sc223 = (tickF223 and type(tickF223.GetScript) == "function") and tickF223:GetScript("OnUpdate") or nil
  eq(type(sc223) == "function", true, "组223⑨前置：有界复查的 OnUpdate 挂在真实 tick 帧上（能点火）")
  TEST.chat = ""
  if type(sc223) == "function" then pcall(sc223, LIM223.period) end -- dt = 一个周期 = 正好一轮
  eq(tstate223[5] == false and tstate223[6] == false, true,
    "组223⑨★★★ 有界复查窗口里的那一次**把晚出现的层补上了**（最后 2 个纹理已隐藏）")
  eq(string.find(tostring(TEST.chat or ""), "启动期复查", 1, true) ~= nil, true, "组223⑨★ 补生效时如实播报（不静默）")
  tstate223[5], tstate223[6] = true, true -- 客户端自己又显示回来
  local sc2_223 = tickF223:GetScript("OnUpdate")
  if type(sc2_223) == "function" then pcall(sc2_223, LIM223.period) end
  eq(tstate223[5] == false and tstate223[6] == false, true,
    "组223⑨★★★ 被显示回来后，复查窗口里**再藏一次**（守护）")
  eq(EVAL_LF_TEST_STATE().fixRehide >= 2, true,
    "组223⑨★ 守护有实证计数（fixRehide = " .. tostring(EVAL_LF_TEST_STATE().fixRehide) .. "）")
  -- 跑满窗口 ⇒ **脚本必须被摘掉**（不做常驻轮询）
  local fired223 = 2
  for _i = 1, LIM223.checks + 2 do
    local f = tickF223:GetScript("OnUpdate")
    if type(f) == "function" then pcall(f, LIM223.period) fired223 = fired223 + 1 end
  end
  eq(fired223 <= LIM223.checks + 1, true,
    "组223⑨★★ 窗口用完就不再点火（实测点到 " .. tostring(fired223) .. " 次，净上限 " .. tostring(LIM223.checks) .. "）")
  eq(tickF223:GetScript("OnUpdate") == nil, true,
    "组223⑨★★★ 窗口结束**摘掉 OnUpdate 脚本**（不是靠内部标志空转 —— 不做常驻轮询）")
  eq(EVAL_LF_TEST_STATE().live == false, true, "组223⑨★ 读值口如实报告「tick 不再工作」")

  -- ⑩ 工具箱那一行（端到端）：无勾选框 + [设置]/[重置] 不重叠 + 多选下拉 + 真实回调当场生效
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  for i = 1, 6 do tstate223[i] = true end
  EVAL_LF_RESET()                     -- 回到干净态（勾选清空 + 全部还原）
  EVAL_HELP_CFG_SETTAB(3)
  eq(EVAL_TB_TEST_GOTO("layerFix"), true, "组223⑩ 工具箱能按 key 翻到「图层特殊处理」那一行")
  local lay223 = EVAL_TB_TEST_LAYOUT()
  local rowFix223, rowC223 = nil, nil
  for k = 1, table.getn(lay223.rows) do
    local rr = lay223.rows[k]
    if rr and rr.kind == "mod" then rowFix223 = rr end
    if rr and rr.kind == "c" then rowC223 = rr end
  end
  eq(rowFix223 ~= nil, true, "组223⑩★ 渲染出来的行里找得到 kind = mod（模块行；走真实行模型）")
  eq(rowFix223 ~= nil and rowFix223.shown == false, true,
    "组223⑩★★★ 这一行**没有勾选框**（真值就是多选里勾了哪几条；多挂一个总开关只会多一份真值）")
  eq(rowC223 ~= nil and rowC223.shown == true, true,
    "组223⑩★ 反向哨兵：普通开关行的勾选框**仍然在**（不是所有行都被藏了）")
  local setBtn223 = EVAL_TEST_TB_ADD_BTN_FOR("layerFix")
  local clrBtn223 = EVAL_TEST_TB_CLR_FOR("layerFix")
  eq(setBtn223 ~= nil and setBtn223:IsShown() == true, true,
    "组223⑩★★★ [设置] 按钮真的被**模块**建出来并显示（= 嵌入点调到了模块的渲染函数）")
  eq(clrBtn223 ~= nil and clrBtn223:IsShown() == true, true, "组223⑩★★ [重置] 按钮同样由模块建出并显示")
  local geo223 = EVAL_TB_TEST_ROW_BTNS("layerFix")
  eq(type(geo223) == "table" and geo223.add ~= nil and geo223.clr ~= nil, true,
    "组223⑩★ 读得到两个按钮的几何（add / clr）")
  if geo223 and geo223.add and geo223.clr then
    local aR223 = (geo223.add.left or 0) + (geo223.add.width or 0)
    local cL223 = geo223.clr.left or 0
    eq(cL223 >= aR223, true, "组223⑩★★★ [设置] 与 [重置]**不重叠**（[设置] 右边界 " .. tostring(aR223) ..
      " ≤ [重置] 左边 " .. tostring(cL223) .. "；同锚时后者压住前者、另一个永远点不到）")
  end
  eq(geo223 ~= nil and geo223.chv ~= nil and geo223.chv.shown == false, true,
    "组223⑩★ 这一行没有用 chv 槽（88 宽、会横跨整个右侧带把 [设置] 盖住）")
  local txtRow223 = EVAL_TB_TEST_ROW_TEXT("layerFix")
  eq(type(txtRow223) == "table" and txtRow223.label == EVAL_L("TB_DFFIX"), true,
    "组223⑩★ 行标签 = 语言包（「" .. tostring(type(txtRow223) == "table" and txtRow223.label or nil) .. "」）")
  -- ★1.74.36 用户：「配置项不需要再外部显示，已经在 tooltip 设置内显示了」⇒ 行上**不许**再显示摘要
  eq(type(txtRow223) == "table" and txtRow223.extraShown == false, true,
    "组223⑩★★★ 行上**不再**重复显示配置摘要（只留在 [设置] 悬停里；实测 extraShown=" ..
    tostring(type(txtRow223) == "table" and txtRow223.extraShown or nil) .. "、行内文本「" ..
    tostring(type(txtRow223) == "table" and txtRow223.extra or nil) .. "」）")
  TEST.tipLines = nil
  local enter223 = setBtn223 and setBtn223:GetScript("OnEnter")
  eq(type(enter223) == "function", true, "组223⑩★★ [设置] 挂了真实 OnEnter（由模块挂的）")
  if type(enter223) == "function" then pcall(enter223) end
  local tip223 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tip223 = tip223 .. tostring(ln.text or "") .. "\n" end
  eq(string.find(tip223, EVAL_L("TB_DFFIX_SET_TIP"), 1, true) ~= nil, true,
    "组223⑩★ 悬停说明来自语言包（讲清「勾上的才生效、取消勾选当场还原」）")
  eq(string.find(tip223, tostring(EVAL_LF_SUMMARY()), 1, true) ~= nil, true,
    "组223⑩★ 悬停里带当前状态（现读，不与行内摘要打架）")
  local savedDD223 = rawget(_G, "EVAL_DD_OPEN")
  local capA223, capI223, capCb223, capO223 = nil, nil, nil, nil
  rawset(_G, "EVAL_DD_OPEN", function(anchor, items, cb, opts)
    capA223, capI223, capCb223, capO223 = anchor, items, cb, opts
    return true
  end)
  local click223 = setBtn223 and setBtn223:GetScript("OnClick")
  eq(type(click223) == "function", true, "组223⑩★ [设置] 挂了真实 OnClick")
  if type(click223) == "function" then pcall(click223) end
  rawset(_G, "EVAL_DD_OPEN", savedDD223)
  eq(capA223 == setBtn223 and type(capI223) == "table", true,
    "组223⑩★★★ 点 [设置] ⇒ 用**项目现成的下拉件** EVAL_DD_OPEN 打开、锚在这个按钮上（不新造控件）")
  eq(capO223 ~= nil and capO223.multi == true and type(capO223.locked) == "table"
      and type(capO223.selected) == "table", true,
    "组223⑩★★★ 下拉是**多选**（multi=true；分组标题行走 locked、初始勾选走 selected）")
  eq(capO223 ~= nil and type(capO223.tips) == "table" and capO223.tips[piGry223] ~= nil, true,
    "组223⑩★ 每条处理带悬停说明（tips 与 items 同序，按原始下标索引）")
  local same223 = (type(capI223) == "table" and table.getn(capI223) == nItems223)
  if same223 then
    for i = 1, nItems223 do if capI223[i] ~= items223[i] then same223 = false end end
  end
  eq(same223, true, "组223⑩★★★ 菜单内容**逐项来自模块**（工具箱没有另造一份处理清单 ⇒ 不会两处漂移）")
  TEST.chat = ""
  if type(capCb223) == "function" then pcall(capCb223, piGry223, true) end
  eq(EVAL_LF_ENABLED("gryphon"), true,
    "组223⑩★★★ 通过下拉的**真实回调**勾选 ⇒ 立刻落进真值（走真实接线，不是直调写入口）")
  eq(tstate223[5] == false and tstate223[6] == false, true,
    "组223⑩★★★ 端到端：下拉里勾上 ⇒ 动作条那两张狮鹫贴图**当场被隐藏**（不需要重载）")
  local txtOn223 = EVAL_TB_TEST_ROW_TEXT("layerFix")
  eq(type(txtOn223) == "table" and txtOn223.extraShown == false, true,
    "组223⑩★★ 勾上之后行上**依旧**不显示摘要（配置项不回到行上）")
  -- ★配置项改由**悬停说明**承载：重新走一次真实 OnEnter，从真 GameTooltip 的记账里读
  TEST.tipLines = nil
  if type(enter223) == "function" then pcall(enter223) end
  local tipOn223 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipOn223 = tipOn223 .. tostring(ln.text or "") .. "\n" end
  eq(string.find(tipOn223, lblGry223, 1, true) ~= nil, true,
    "组223⑩★★★ 勾上后**悬停说明里**当场列出处理名（「" .. tostring(EVAL_LF_SUMMARY()) .. "」）")
  local clickR223 = clrBtn223 and clrBtn223:GetScript("OnClick")
  eq(type(clickR223) == "function", true, "组223⑩★ [重置] 挂了真实 OnClick")
  if type(clickR223) == "function" then pcall(clickR223) end
  eq(tstate223[5] == true and tstate223[6] == true, true, "组223⑩★★★ 端到端：[重置] ⇒ 贴图显示回来")
  local cEnd223 = EVAL_LF_COUNT()
  eq(cEnd223 == 0, true, "组223⑩★★ [重置] 之后勾选清空（" .. tostring(cEnd223) .. "）")
  local txtEnd223 = EVAL_TB_TEST_ROW_TEXT("layerFix")
  eq(type(txtEnd223) == "table" and txtEnd223.extraShown == false, true,
    "组223⑩★ [重置] 之后行上仍不显示摘要（不因状态变化又冒出来）")
  TEST.tipLines = nil
  if type(enter223) == "function" then pcall(enter223) end
  local tipEnd223 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipEnd223 = tipEnd223 .. tostring(ln.text or "") .. "\n" end
  eq(string.find(tipEnd223, tostring(EVAL_LF_SUMMARY()), 1, true) ~= nil, true,
    "组223⑩★ 悬停说明跟着回到「没有启用任何特殊处理」（" .. tostring(EVAL_LF_SUMMARY()) .. "）")

  -- 收尾：真值/夹具/全局桥全部还原（★连 tick 脚本一起停掉，免得阴影里还在跑）
  EVAL_LF_TEST_STOP()
  EVAL_LF_TEST_FIX_STATE_CLEAR()
  rawget(_G, "EVAL_HELP_CONFIG").layerFix = savedFixStore223
  rawget(_G, "EVAL_HELP_CONFIG").dragFrames = savedDfStore223
  rawset(_G, "MainMenuBarArtFrame", savedLayerG223)
  rawset(_G, "MainMenuBar", savedBarG223)
  TEST.chat = savedChat223
  TEST.tipLines = savedTips223
  TEST.inCombat = savedCombat223
  if savedTab223 then EVAL_HELP_CFG_SETTAB(savedTab223) end
  EVAL_DF_SET(wasOn223)
  EVAL_DF_TEST_RESET_TIMERS()
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  图层特殊处理：%d 条定义（默认全不选）· 勾上只藏最后 %s 个纹理 · 取消还原 · 层不在一个不动 · [重置] 清勾选",
    nFix223, tostring((gry223 and gry223.pick and gry223.pick.last) or "?")))
  print("GROUP 223 (图层特殊处理 = 独立模块 tools/LayerFix.lua（层内个别元素「动作条狮鹫」）· 工具箱只留模块行嵌入点 · 默认全不选 · 层不在绝不猜着改): PASS")
end

EVAL_TEST_MOD_DONE("LayerFix") -- ★跑到底的握手（见文件头 ③）：TOOL TEST FILES CHECK 拿它对账
