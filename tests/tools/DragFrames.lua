-- tests/tools/DragFrames.lua
-- 【工具模块自带测试 · 断言组】拖拽图层模块（tools/DragFrames.lua）。
-- 用户 1.74.34：「拖拽图层模块（DragFrames）代码也排查下归类到自身文件内。」
--   ⇒ 本模块的测试三件套各归其位：**读值口**在 tools/DragFrames.lua（EVAL_DF_TEST_*）·
--     **断言组**就是本文件（组 202/204/206~218/220~222）· **源码检查**在同级 tests/checks/DragFrames.js。
-- ★纪律（四条，越界即静默失效）：
--   ① 本文件**不进 toc、不随包发布**（tests/ 不在发布清单里）——只在测试里被 harness 加载；
--   ② 断言一律用 **EVAL_TEST_EQ**（test_assert.lua 暴露的**同一个** eq）⇒ 失败格式与其它组逐字一致；
--   ③ **最后一行必须调 `EVAL_TEST_MOD_DONE("DragFrames")`** —— 它是「这个文件真的跑到底了」的握手信号，
--      harness 拿它和 tests/tools/*.lua 的文件数对账：**少跑一个文件 = 整组断言静默消失**；
--   ④ 每组夹具**自建自清**（与搬来之前一样：自己 patch 屏幕模型、自己还原存档/桩状态）。
-- ★加载时机：test_engine.js 在 test_assert.lua **之后**按文件名序加载 tests/tools/*.lua
--   （DragFrames 在 LayerFix 之前）⇒ 这些组现在运行在**所有常驻组之后**。
local eq = EVAL_TEST_EQ
-- ===== 组 202（1.74.30）：框拖拽 = **独立工具模块** tools/DragFrames.lua =====
-- 用户报的 4 件事（① 拖拽结束不掉→目标层一直跟着鼠标走 ② 配置窗贴屏幕左下角 ③ 拖拽中定时复查抢锚点
--   ④ 抽成 ./tools 独立模块）+ 审计定案的三条真因（证据写在模块文件头）。
-- 本组覆盖：开关三处同源 · **重置口径（本轮已改：连缩放/透明度/显隐一起还原，见组 204）** · 清单读得出 ·
--   **拖拽期间定时复查被跳过** · **结束拖拽的多重兜底接线在位** ·
--   弹窗「不再停在 (0,0)」+ 定位兜底 · 老存档一次性迁移。
-- ★纪律：全部走**真实脚本/读值口**点火与读数（GetScript("OnMouseDown"/"OnUpdate"/"OnMouseUp")、
--   EVAL_DF_TEST_*），**不复刻映射逻辑**；期望值用夹具几何独立算出来（不是抄生产常量）。
-- ★本组是最后一组：为了让弹窗居中可判，给 UIParent / WorldFrame 装了真几何；故不再还原（后面没有别的组）。
do
  local savedTab202 = EVAL_HELP_CFG_TAB()
  -- 夹具：5 个目标帧（真机形状 = 左上角锚 UIParent + 明确宽高）
  local function mkT202(nm, l, t, w, h)
    local f = CreateFrame("Frame", nm, UIParent)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", l, t)
    f:SetWidth(w) f:SetHeight(h)
    return f
  end
  local pf202 = mkT202("PlayerFrame", 100, -50, 120, 40)
  mkT202("TargetFrame", 300, -50, 120, 40)
  mkT202("MinimapCluster", 800, -20, 140, 140)
  mkT202("MainMenuBar", 200, -80, 500, 44)
  mkT202("ChatFrame1", 20, -600, 400, 120)
  -- 屏幕 1024×768 与宿主同尺寸：屏幕中心 = (512, -384)、宿主左上角 = (0, 0)
  UIParent:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  UIParent:SetWidth(1024) UIParent:SetHeight(768)
  WorldFrame:SetPoint("BOTTOMLEFT", WorldFrame, "BOTTOMLEFT", 0, 0)
  WorldFrame:SetWidth(1024) WorldFrame:SetHeight(768)

  local function cursor202(x, y) TEST.cursorX, TEST.cursorY = x, y end
  local function scriptOf202(obj, ev)
    if not obj then return nil end
    local okg, fn = pcall(obj.GetScript, obj, ev)
    if okg and type(fn) == "function" then return fn end
    return nil
  end
  local function fire202(obj, ev, a)
    local fn = scriptOf202(obj, ev)
    if not fn then return false end
    pcall(fn, a)
    return true
  end

  -- ① 干净起点 + 打开开关 → 拖拽柄贴出来（5 个目标都在位）
  EVAL_HELP_CONFIG.dragFrames = nil
  EVAL_DF_TEST_RESET_PROBE()
  EVAL_DF_SET(true)
  local n202 = EVAL_DF_TEST_STATE().poolN
  eq(n202 >= 4, true, "①前置：开关打开后贴出拖拽柄（" .. tostring(n202) .. " 个目标在位）")
  eq(EVAL_DF_TEST_STATE().hasTick, true, "①前置：2 秒定时复查 tick 建好了")
  local hPF = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(hPF ~= nil, true, "①前置：拿得到 PlayerFrame 的拖拽柄（真实控件）")

  -- ② 开关三处同源：工具箱那一行的**真实勾选框** → 真实 OnClick → 模块真值翻转（面板不存第二份）
  EVAL_HELP_CFG_SETTAB(3) -- 工具箱 Tab
  eq(EVAL_TB_TEST_GOTO("dbgDrag"), true, "②前置：把工具箱窗口挪到「图层拖拽」那一行")
  local chk202 = EVAL_TEST_TB_CHK_FOR("dbgDrag")
  eq(chk202 ~= nil, true, "②前置：拿到该行勾选框（读值口走真实控件，不复刻映射）")
  local onBefore202 = EVAL_DF_ENABLED()
  local okClick202 = fire202(chk202, "OnClick")
  eq(okClick202, true, "②★勾选框真的挂了 OnClick")
  eq(EVAL_DF_ENABLED(), not onBefore202, "②★★★工具箱勾选框 → 模块真值跟着翻转（唯一真值 = dragFrames.on）")
  -- 反向也验（模块 → 面板）：改真值 + 重刷那一行 → 勾号跟着变
  EVAL_DF_SET(true)
  EVAL_TB_TEST_GOTO("dbgDrag")
  local _, mkOn202 = EVAL_TEST_TB_CHK_FOR("dbgDrag")
  eq(mkOn202 ~= nil and mkOn202:IsShown() == true, true, "②★★模块真值=开 ⇒ 面板勾号显示")
  EVAL_DF_SET(false)
  EVAL_TB_TEST_GOTO("dbgDrag")
  local _, mkOff202 = EVAL_TEST_TB_CHK_FOR("dbgDrag")
  eq(mkOff202 ~= nil and mkOff202:IsShown() == false, true, "②★★模块真值=关 ⇒ 面板勾号隐藏（两向都同源）")
  EVAL_DF_SET(true)
  hPF = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(hPF ~= nil, true, "②前置：重新打开后柄还在")

  -- ③ 第一次拖拽：走**真实脚本**点火，读真实几何
  cursor202(400, 300)
  eq(fire202(hPF, "OnMouseDown"), true, "③★点火 OnMouseDown（真实脚本）")
  local stD202 = EVAL_DF_TEST_STATE()
  eq(stD202.dragging, true, "③★★拖拽状态置真")
  eq(stD202.catcherShown, true, "③★★★拖拽期间**全屏接盘**已显示（松手时无论指针在哪都收得到 —— 修 ① 的主要一层）")
  eq(stD202.handleName, "PlayerFrame", "③★记下了正在拖的目标名")
  cursor202(450, 330)
  fire202(hPF, "OnUpdate", 0.05)
  eq(pf202:GetLeft(), 150, "③★★拖拽真的把目标移了：左边缘 100 → 150（光标 50px）")
  eq(pf202:GetTop(), -20, "③★★上边缘 -50 → -20（方向没镜像、没反向）")
  fire202(hPF, "OnMouseUp")
  local stE202 = EVAL_DF_TEST_STATE()
  eq(stE202.dragging, false, "③★★★松手后拖拽**结束**（用户报的第 1 件事：不再一直跟着鼠标走）")
  eq(stE202.catcherShown, false, "③★★接盘立刻收起（只在拖拽期间吃鼠标，不吃正常点击）")
  eq(stE202.why, "mouseup", "③★结束原因如实记为 mouseup")
  local store202 = EVAL_DF_TEST_STORE()
  eq(type(store202) == "table" and type(store202.PlayerFrame) == "table", true,
     "③★存档写在**模块自己的表** EVAL_HELP_CONFIG.dragFrames 里（按帧名字）")
  eq(store202.PlayerFrame.dx, 50, "③★★位移存成 dx=50（基准 = 拖前的实测锚点）")
  eq(store202.PlayerFrame.dy, 30, "③★★位移存成 dy=30")
  local b202 = store202.PlayerFrame.base and store202.PlayerFrame.base[1]
  eq(type(b202) == "table" and (type(b202[2]) == "string" or b202[2] == nil), true,
     "③★base 里的相对帧**只存名字字符串**（存帧对象无法序列化，这是踩过的坑）")
  eq(stE202.popShown, true, "③★拖拽完成弹出了属性配置窗")
  eq(stE202.coverShown, true, "③★全屏遮罩也显示了（点窗外 = 取消）")

  -- ③b 弹窗定位：不能再停在 (0,0)（= 父级左下角，正是用户截图那个现象）
  eq(stE202.popMode, "host", "③b★★★弹窗走了「相对父级居中」且**读回自证通过**（mode=host）")
  local pop202 = EVAL_DF_TEST_POP()
  eq(pop202 ~= nil and pop202.root ~= nil, true, "③b前置：拿到弹窗控件")
  local okpp202, ppoint202, _, _, px202, py202 = pcall(pop202.root.GetPoint, pop202.root, 1)
  eq(okpp202 and ppoint202, "CENTER", "③b★★弹窗第 1 锚点 = CENTER（不是空锚点）")
  eq(math.abs((tonumber(px202) or 0) - 512) <= 1, true,
     "③b★★★偏移 x = 屏幕中心 512 − 宿主左边缘 0（实测 " .. tostring(px202) .. "）")
  eq(math.abs((tonumber(py202) or 0) + 384) <= 1, true,
     "③b★★★偏移 y = 屏幕中心 -384 − 宿主上边缘 0（实测 " .. tostring(py202) .. "）")
  eq((tonumber(px202) or 0) ~= 0 or (tonumber(py202) or 0) ~= 0, true,
     "③b★★反向哨兵：锚点不是 (0,0) —— 「贴在左下角」这个现象在结构上不可能再出现")
  -- 定位兜底：主路径校验不过 → 退回「改挂 UIParent + CENTER/CENTER」，并如实记 mode
  EVAL_DF_TEST_FORCE_PLACE_FAIL(true)
  eq(EVAL_DF_TRIAL(), true, "③b★强制主路径校验失败后弹窗仍然弹得出来（有兜底，不是一条路走死）")
  eq(EVAL_DF_TEST_STATE().popMode, "uiparent", "③b★★★兜底路径真的执行了并如实记 mode=uiparent")
  EVAL_DF_TEST_FORCE_PLACE_FAIL(false)

  -- ④ 点「取消」：弹窗与**遮罩一起**收（旧实现漏藏遮罩 → 第一次弹窗之后鼠标事件全被它吃掉）
  fire202(pop202.cancel, "OnClick")
  local stC202 = EVAL_DF_TEST_STATE()
  eq(stC202.popShown, false, "④★点取消后弹窗收起")
  eq(stC202.coverShown, false, "④★★★遮罩**同时**收起（旧实现把 1150 的全屏吃鼠标控件永久留在屏幕上）")

  -- ⑤ 拖拽期间定时复查必须**整体跳过**（用户报的「抢锚点 → 位移/闪烁」）
  cursor202(400, 300)
  fire202(hPF, "OnMouseDown")
  cursor202(600, 400)
  fire202(hPF, "OnUpdate", 0.05)
  eq(pf202:GetLeft(), 350, "⑤前置：第二次拖拽把它拖到 350（存档里期望位置还是 150 ⇒ 已「漂」）")
  local fixedK202 = EVAL_DF_KEEP_TICK(true)
  eq(fixedK202, 0, "⑤★★★拖拽进行中：定时复查返回「重设 0 个」（不与手动拖拽抢锚点）")
  eq(pf202:GetLeft(), 350, "⑤★★★复查**没有**把目标拽回存档位置（左边缘仍是 " .. tostring(pf202:GetLeft()) .. "）")
  eq(pf202:GetTop(), 80, "⑤★★垂直方向同样没被拽回（上边缘仍是 " .. tostring(pf202:GetTop()) .. "）")
  -- 结束走**全屏接盘**的 OnMouseUp（新加的一层：指针不在柄上也能结束）
  local cat202 = EVAL_DF_TEST_CATCHER()
  eq(cat202 ~= nil, true, "⑤前置：全屏接盘控件存在")
  fire202(cat202, "OnMouseUp")
  local stE2_202 = EVAL_DF_TEST_STATE()
  eq(stE2_202.dragging, false, "⑤★★★接盘的 OnMouseUp 也能结束拖拽（修 ① 的关键一层）")
  eq(stE2_202.why, "catcher", "⑤★结束原因如实记为 catcher")
  local rec2_202 = EVAL_DF_TEST_STORE().PlayerFrame
  eq(rec2_202.dx, 250, "⑤★★第二次拖拽后 dx=250（基准仍是**原始锚点** 100，不是上一次的位置）")
  eq(rec2_202.dy, 130, "⑤★★dy=130")
  eq(EVAL_DF_KEEP_TICK(true), 0, "⑤★拖拽结束后复查照常工作（目标已在存档位置 ⇒ 重设 0 个，不是被永久关掉）")

  -- ⑥ 结束拖拽的「多重兜底」逐层接线在位
  eq(hPF:GetDragRegistered(), "LeftButton", "⑥★RegisterForDrag(\"LeftButton\") 在位（本项目 UI 配方第 1 条）")
  eq(scriptOf202(hPF, "OnDragStop") ~= nil, true, "⑥★OnDragStop 接了（客户端若回调，松手必结束）")
  eq(scriptOf202(hPF, "OnDragStart") ~= nil, true, "⑥★OnDragStart 接了（幂等：只在没开始时才置状态）")
  eq(scriptOf202(hPF, "OnMouseUp") ~= nil, true, "⑥★OnMouseUp 在位")
  eq(scriptOf202(hPF, "OnUpdate") ~= nil, true, "⑥★OnUpdate 在位（每帧兜底判据的载体）")
  -- ⑥a 本客户端**没有** IsMouseButtonDown ⇒ 自校准如实记「不可用」，且不误伤拖拽
  local savedIMBD202 = IsMouseButtonDown
  IsMouseButtonDown = nil
  EVAL_DF_TEST_RESET_PROBE()
  cursor202(400, 300) fire202(hPF, "OnMouseDown")
  fire202(hPF, "OnUpdate", 0.05)
  eq(EVAL_DF_TEST_STATE().dragging, true, "⑥a★★没有 IsMouseButtonDown 时那条兜底是死代码、且不误伤拖拽（实测 " .. tostring(EVAL_DF_TEST_STATE().mouseDownOK) .. "）")
  cursor202(410, 300) fire202(hPF, "OnUpdate", 0.05)
  fire202(hPF, "OnMouseUp")
  -- ⑥b「存在但恒返回 false」的实现：绝不能在按下那一刻就掐断拖拽（自校准要拦住它）
  IsMouseButtonDown = function() return false end
  EVAL_DF_TEST_RESET_PROBE()
  cursor202(500, 300) fire202(hPF, "OnMouseDown")
  eq(EVAL_DF_TEST_STATE().mouseDownOK, false, "⑥b★★按下那一刻它返回 false ⇒ 自校准判「不可用」（不采信一个说假话的 API）")
  fire202(hPF, "OnUpdate", 0.05)
  eq(EVAL_DF_TEST_STATE().dragging, true, "⑥b★★★不可信的实现不会把拖拽瞬间掐断")
  fire202(hPF, "OnMouseUp")
  -- ⑥c 真实现（按下时返回真）：松手 → 这条兜底真的结束
  TEST.imbdDown202 = true
  IsMouseButtonDown = function() return TEST.imbdDown202 and true or false end
  EVAL_DF_TEST_RESET_PROBE()
  cursor202(500, 320) fire202(hPF, "OnMouseDown")
  eq(EVAL_DF_TEST_STATE().mouseDownOK, true, "⑥c★按下时返回真 ⇒ 采信这条兜底")
  TEST.imbdDown202 = false
  fire202(hPF, "OnUpdate", 0.05)
  eq(EVAL_DF_TEST_STATE().dragging, false, "⑥c★★★IsMouseButtonDown 兜底真的结束拖拽（指针不动、也没收到 OnMouseUp 的场合）")
  IsMouseButtonDown = savedIMBD202
  TEST.imbdDown202 = nil
  -- ⑥d GetMouseFocus 兜底：自校准只在「按下那一刻它确实返回本柄」时才采信
  local savedGMF202 = GetMouseFocus
  local focus202 = nil
  GetMouseFocus = function() return focus202 end
  EVAL_DF_TEST_RESET_PROBE()
  focus202 = hPF
  cursor202(700, 400) fire202(hPF, "OnMouseDown")
  eq(EVAL_DF_TEST_STATE().focusOK, true, "⑥d★按下时返回本柄 ⇒ 采信这条兜底")
  focus202 = nil -- 焦点没了 = 松手了
  fire202(hPF, "OnUpdate", 0.05)
  eq(EVAL_DF_TEST_STATE().dragging, false, "⑥d★★★GetMouseFocus 兜底也能结束拖拽")
  GetMouseFocus = savedGMF202
  EVAL_DF_TEST_RESET_PROBE()
  -- ⑥e 超时无位移 → 自动结束（最后一道保险：绝不会让目标层永远跟着鼠标）
  cursor202(300, 300)
  fire202(hPF, "OnMouseDown")
  eq(EVAL_DF_TEST_STATE().dragging, true, "⑥e前置：拖拽已开始")
  local guard202 = 0
  while EVAL_DF_TEST_STATE().dragging and guard202 < 80 do
    fire202(hPF, "OnUpdate", 0.2) -- 指针不动，只推进时间
    guard202 = guard202 + 1
  end
  eq(EVAL_DF_TEST_STATE().dragging, false, "⑥e★★★指针 2 秒不动 ⇒ 自动结束（" .. tostring(guard202) .. " 帧）")
  eq(EVAL_DF_TEST_STATE().why, "idle", "⑥e★结束原因如实记为 idle")

  -- ⑦ 重置**只清定位**：先用真实下拉 + [保存] 把「缩放」存进去，再点重置
  eq(EVAL_DF_TRIAL(), true, "⑦前置：弹窗弹出来了（目标 = 第一个在位的目标帧）")
  local pop7 = EVAL_DF_TEST_POP()
  eq(pop7 ~= nil and pop7.rows ~= nil, true, "⑦前置：拿到弹窗的三行下拉")
  local rowScale7 = pop7.rows[2]
  eq(rowScale7 ~= nil and rowScale7.btn ~= nil, true, "⑦前置：拿到「UI 缩放」那一行的下拉按钮")
  fire202(rowScale7.btn, "OnClick")
  eq(pop7.list:IsShown(), true, "⑦★点下拉真的展开了列表（真实控件）")
  fire202(pop7.list.rows[2], "OnClick") -- 选中第 2 项 = 0.60
  eq(rowScale7.value, 0.6, "⑦★选中值落进了行数据（" .. tostring(rowScale7.value) .. "）")
  fire202(pop7.save, "OnClick")
  local rec7 = EVAL_DF_TEST_STORE().PlayerFrame
  eq(rec7 ~= nil and rec7.scale == 0.6, true, "⑦★★[保存] 把缩放写进了模块自己的存档（scale=" .. tostring(rec7 and rec7.scale) .. "）")
  eq(EVAL_DF_TEST_STATE().coverShown, false, "⑦★★保存后弹窗与**遮罩一起**收起")
  local n7 = EVAL_DF_RESET()
  local rec7b = EVAL_DF_TEST_STORE().PlayerFrame
  eq(n7, 1, "⑦★★重置处理了 1 个目标（实测 " .. tostring(n7) .. "）")
  eq(rec7b ~= nil and rec7b.dx == nil and rec7b.dy == nil, true, "⑦★★★重置清掉了定位数据")
  -- ★★本轮需求改向：旧方向是「重置**只**清定位、缩放保留」；用户明确要求「重置也要重置 缩放、透明度、显示隐藏」
  --   ⇒ 判据翻到新方向（不是删断言）：缩放记录被清掉 **且** 目标的缩放真的回到 1。
  eq(rec7b ~= nil and rec7b.scale == nil, true,
     "⑦★★★重置把缩放记录也清掉了（新口径：重置=缩放/透明度/显隐一起还原，实测 scale=" ..
     tostring(rec7b and rec7b.scale) .. "）")
  eq(pf202:GetScale(), 1, "⑦★★★重置把目标的缩放真的还原成 1（实测 " .. tostring(pf202:GetScale()) .. "）")
  eq(pf202:GetLeft(), 100, "⑦★★重置把目标放回原始锚点（左边缘 " .. tostring(pf202:GetLeft()) .. "）")
  eq(pf202:GetTop(), -50, "⑦★★上边缘也回原位（" .. tostring(pf202:GetTop()) .. "）")

  -- ⑧ 清单读得出（工具箱 [重置] 的悬停 tooltip 就用它）
  -- ★★本轮需求改向：旧清单念的是**存档里记了什么**（所以重置后还能读到被保留的 0.60）；
  --   新清单读的是**目标当前真值** ⇒ 那一句必须反过来：0.60 已被重置掉，不该再出现。
  local sum8 = EVAL_DF_SUMMARY()
  eq(type(sum8) == "table" and table.getn(sum8) >= 2, true, "⑧★清单有内容（" .. tostring(table.getn(sum8)) .. " 行）")
  local j8 = table.concat(sum8, "|")
  eq(string.find(j8, "用户头像", 1, true) ~= nil, true, "⑧★★清单里按帧名字给得出目标名")
  eq(string.find(j8, "缩放", 1, true) ~= nil, true, "⑧★★清单里读得出缩放（逐目标当前真值）")
  eq(string.find(j8, "0.60", 1, true) == nil, true,
     "⑧★★★反向哨兵：被重置掉的 0.60 不该再出现在清单里（清单读的是当前真值，不是存档）")
  eq(string.find(j8, "1.00", 1, true) ~= nil, true, "⑧★★重置后清单显示的是还原后的当前值 1.00")

  -- ⑨ 老存档**一次性迁移**（子插件 EH_DEBUGBOX_CFG.cust["[全局] 名"] → 新存档，位置不丢）
  local oldCfg202 = EH_DEBUGBOX_CFG
  EH_DEBUGBOX_CFG = { cust = { ["[全局] TargetFrame"] = {
    opt = { "TOPLEFT", "UIParent", "TOPLEFT", 300, -50 },
    set = { dx = 12, dy = -7, scale = 0.8, alpha = 0.5, hidden = false } } } }
  local store9 = EVAL_DF_TEST_STORE()
  store9.mig = nil -- 允许再迁一次（本组自己造的夹具）
  store9.TargetFrame = nil
  local n9 = EVAL_DF_MIGRATE()
  eq(n9, 1, "⑨★★老存档里 1 条记录被搬进新存档（实测 " .. tostring(n9) .. "）")
  local rec9 = EVAL_DF_TEST_STORE().TargetFrame
  eq(rec9 ~= nil and rec9.dx == 12 and rec9.dy == -7, true, "⑨★★位移原样搬过来（用户拖好的位置不丢）")
  eq(rec9 ~= nil and rec9.scale == 0.8 and rec9.alpha == 0.5, true, "⑨★★缩放/透明也搬")
  eq(rec9 ~= nil and rec9.hidden == false, true, "⑨★显隐状态也搬（false 不许被吞成 nil）")
  eq(rec9 ~= nil and type(rec9.base) == "table" and type(rec9.base[1][2]) == "string", true,
     "⑨★★★base 的相对帧只存**名字字符串**（存帧对象不可序列化）")
  eq(EVAL_DF_TEST_STORE().mig, true, "⑨★迁移标记立上（只搬一次，不会反复覆盖用户后来的调整）")
  EH_DEBUGBOX_CFG = oldCfg202

  -- ⑩ 收尾：关掉开关（不留拖拽柄/接盘吃鼠标）+ Tab 还原（跨用例状态残留是本项目老坑）
  EVAL_DF_SET(false)
  eq(EVAL_DF_TEST_STATE().poolN, 0, "⑩收尾：关掉开关后拖拽柄全部收起")
  EVAL_DF_TEST_FORCE_PLACE_FAIL(false)
  EVAL_DF_TEST_RESET_PROBE()
  EVAL_HELP_CFG_SETTAB(savedTab202)
  print(string.format("  框拖拽模块：目标 %d 个 · 结束兜底 6 层（OnMouseUp/全屏接盘/OnDragStop/IsMouseButtonDown(自校准)/" ..
    "GetMouseFocus(自校准)/超时无位移）· 拖拽期间跳过定时复查 · 弹窗读回自证 mode · 老存档迁移 %d 条", n202, n9))
  print("GROUP 202 (框拖拽 = 独立工具模块 tools/DragFrames.lua：目标清单/拖拽柄/属性弹窗/重置还原/老存档迁移): PASS")
end

-- ===== 组 204（1.74.31）：框拖拽「启动期有界复查」+ 重置还原属性 + 清单读真值 =====
-- 用户本轮三条要求（A 优先级最高）：
--   A「首次出现并且设置成功参数之后，间隔 1s 检查 5 次，之后都符合参数之后就不再定时检查；
--      也就是定时检查**最大检测时间为屏幕载入完成 5s 内**」
--   B「重置也要重置 缩放、透明度、显示隐藏 等信息」
--   C「工具箱 → 图层拖拽 → 重置 信息显示要显示 缩放、透明度、显示/隐藏 等信息」
-- ★纪律：全部走**真实入口** —— 真实 `EVAL_DF_RESET` / 工具箱真实按钮的 OnEnter（真 GameTooltip 出行）/
--   **真实 tick 帧 `EVAL_DF_KEEP` 的 OnUpdate 脚本**（每轮都重新 `GetScript` 读一次 ⇒ 「脚本被摘掉」当场看得见）。
-- ★期望值独立：次数/周期上限走读值口（EVAL_DF_TEST_KEEP_LIMITS，不与生产常量同源自比），
--   位置用夹具坐标（100/-50），清单文案用**字面量**（不用语言包，避免同源比对）。
do
  local fails204 = TESTASSERT_FAILS
  local LIM = EVAL_DF_TEST_KEEP_LIMITS()
  eq(LIM.checks, 5, "组204① 净检查次数上限 = 用户要求的 5 次（实测 " .. tostring(LIM.checks) .. "）")
  eq(LIM.period, 1.0, "组204① 复查周期 = 用户要求的 1 秒（实测 " .. tostring(LIM.period) .. "）")

  local pf = rawget(_G, "PlayerFrame")
  local tf = rawget(_G, "TargetFrame")
  local cf1 = rawget(_G, "ChatFrame1")
  eq(type(pf) == "table" or type(pf) == "userdata", true, "组204前置：PlayerFrame 在位（沿用组 202 造的夹具帧）")
  eq((type(tf) == "table" or type(tf) == "userdata") and (type(cf1) == "table" or type(cf1) == "userdata"), true,
     "组204前置：TargetFrame / ChatFrame1 都在位")
  -- 战斗记录页（真机里它一定在；桩里没有就补一个，免得清单那一行永远是「帧不在」）
  local cf2 = rawget(_G, "ChatFrame2")
  if type(cf2) ~= "table" and type(cf2) ~= "userdata" then
    cf2 = CreateFrame("Frame", "ChatFrame2", UIParent)
    cf2:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -700)
    cf2:SetWidth(400) cf2:SetHeight(120)
  end
  local function at204(f, x, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
  end
  at204(pf, 100, -50)
  pf:SetWidth(120) pf:SetHeight(40)
  pf:SetScale(1) pf:SetAlpha(1) pf:Show()

  -- 干净起点：唯一真值 = EVAL_HELP_CONFIG.dragFrames；先用**真实的「关」**把开关落下来，
  -- 这样下面那次 EVAL_DF_SET(true) 就是**真实的「关→开」过渡**（= 本会话里的「首次出现」）
  EVAL_HELP_CONFIG.dragFrames = nil
  EVAL_DF_TEST_RESET_PROBE()
  EVAL_DF_SET(false)
  local store204 = EVAL_DF_TEST_STORE()
  eq(type(store204) == "table", true, "组204前置：存档表建立（EVAL_HELP_CONFIG.dragFrames）")
  -- 夹具记录：基准 = 实测锚点、位移 0 ⇒ 「参数已符合」（不漂）
  store204.PlayerFrame = { base = EVAL_DF_TEST_CAPTURE("PlayerFrame"), dx = 0, dy = 0 }
  EVAL_DF_SET(true) -- ★真实入口：应用一次存档参数 + 武装有界复查窗口
  local tick204 = EVAL_DF_TEST_TICK()
  eq(tick204 ~= nil and type(tick204.GetScript) == "function", true,
     "组204①前置：真实 tick 帧 EVAL_DF_KEEP 存在（读值口取的就是它）")
  local s0 = EVAL_DF_TEST_STATE()
  eq(s0.keepArmed, "enable", "组204①★窗口由**真实的「关→开」过渡**武装（keepArmed=" .. tostring(s0.keepArmed) .. "）")
  eq(s0.keepLive, true, "组204①★窗口进行中：tick 帧上真的挂着 OnUpdate 脚本（keepLive=true）")
  eq(s0.keepRuns, 0, "组204①前置：净检查次数起点 0")

  -- 「一次都没重设」的硬证据：给目标的 ClearAllPoints 记账（重锚必经 ClearAllPoints + SetPoint）
  local clr204 = 0
  local oldClr204 = pf.ClearAllPoints
  rawset(pf, "ClearAllPoints", function(...) clr204 = clr204 + 1 return oldClr204(...) end)

  TEST.chat = ""
  local fired204 = 0
  -- ★★点火**真实脚本**：每轮重新 GetScript —— 第 5 次复查结束后脚本被摘掉 ⇒ 后面几轮什么也点不到
  for _i = 1, LIM.checks + 2 do
    local f = tick204:GetScript("OnUpdate")
    if type(f) == "function" then pcall(f, LIM.period) fired204 = fired204 + 1 end
  end
  eq(fired204, LIM.checks, "组204①★★★7 次点火只点到 5 次真实脚本（实测 " .. tostring(fired204) ..
     "）⇒ 第 5 次复查结束**脚本就被摘掉**了（不是靠内部标志空转）")
  eq(tick204:GetScript("OnUpdate") == nil, true, "组204①★★★tick 的 OnUpdate 脚本已被摘掉（不再有常驻 tick）")
  local s1 = EVAL_DF_TEST_STATE()
  eq(s1.keepRuns, 5, "组204①★★净检查正好 5 次（实测 " .. tostring(s1.keepRuns) .. "，不多不少）")
  eq(s1.keepDone, true, "组204①★★5 次过后**永久停止**（keepDone=true）")
  eq(s1.keepWhy, "allok", "组204①★结束原因如实记为 allok（" .. tostring(s1.keepWhy) .. "）")
  eq(s1.keepLive, false, "组204①★★keepLive=false（tick 不再工作）")
  eq(s1.keepFixed, 0, "组204①★★★5 次全部符合参数 ⇒ **一次都没重设**（修正轮数 " .. tostring(s1.keepFixed) .. "）")
  eq(clr204, 0, "组204①★★★反向哨兵：这 5 次里**没有**对目标调用过 ClearAllPoints（= 真的没重锚，实测 " ..
     tostring(clr204) .. " 次）")
  eq(pf:GetLeft(), 100, "组204①★★目标位置没被动过（左边缘 " .. tostring(pf:GetLeft()) .. "）")
  eq(pf:GetTop(), -50, "组204①★★上边缘也没动（" .. tostring(pf:GetTop()) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "启动期复查结束", 1, true) ~= nil, true,
     "组204①★结束时有播报（不静默）")
  eq(string.find(tostring(TEST.chat or ""), "净检查 5 次", 1, true) ~= nil, true,
     "组204①★播报里带数字：净检查 5 次")
  eq(string.find(tostring(TEST.chat or ""), "一次都没重设", 1, true) ~= nil, true,
     "组204①★播报如实写「一次都没重设」")
  rawset(pf, "ClearAllPoints", nil) -- 还原桩（回到 __index 提供的原实现）

  -- ② 中途漂移 → 重设一次并**继续**复查，5 次用完照样停（如实播报）
  EVAL_DF_SET(false)
  EVAL_DF_SET(true)
  local s2a = EVAL_DF_TEST_STATE()
  eq(s2a.keepLive, true and s2a.keepArmed == "enable", "组204②前置：窗口被真实入口重新武装")
  at204(pf, 400, -400) -- 「层被挤动」（不是用户拖的：存档那边完全不知情）
  eq(pf:GetLeft(), 400, "组204②前置：目标已被挤到 400（存档要的是 100 ⇒ 这就是漂移）")
  TEST.chat = ""
  local f2 = tick204:GetScript("OnUpdate")
  eq(type(f2) == "function", true, "组204②前置：拿到真实 OnUpdate 脚本")
  if type(f2) == "function" then pcall(f2, LIM.period) end
  eq(pf:GetLeft(), 100, "组204②★★★漂移当场被按存档重设（左边缘回到 " .. tostring(pf:GetLeft()) .. "）")
  local s2b = EVAL_DF_TEST_STATE()
  eq(s2b.keepRuns, 1, "组204②★只花了 1 次净检查")
  eq(s2b.keepFixed, 1, "组204②★★如实记下「修正 1 轮」（" .. tostring(s2b.keepFixed) .. "）")
  eq(s2b.keepLive, true, "组204②★★★发现漂移后**继续**复查（不是发现一次就收工）")
  for _i = 1, 4 do
    local f = tick204:GetScript("OnUpdate")
    if type(f) == "function" then pcall(f, LIM.period) end
  end
  local s2c = EVAL_DF_TEST_STATE()
  eq(s2c.keepRuns, 5, "组204②★★净检查仍是 5 次封顶（实测 " .. tostring(s2c.keepRuns) .. "）")
  eq(s2c.keepFixed, 1, "组204②★★后 4 次都符合 ⇒ 修正轮数没有涨（" .. tostring(s2c.keepFixed) .. "）")
  eq(s2c.keepDone, true, "组204②★5 次用完就停")
  eq(s2c.keepWhy, "drift", "组204②★结束原因如实记为 drift（实测 " .. tostring(s2c.keepWhy) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "已按存档重设", 1, true) ~= nil, true,
     "组204②★漂移时有播报（用户要的「如实播报、不要静默」）")
  eq(string.find(tostring(TEST.chat or ""), "修正 1 轮", 1, true) ~= nil, true,
     "组204②★结束行带数字：修正 1 轮")

  -- ③ 战斗中跳过：不重锚、不计净检查次数；**评估次数上限**兜住 ⇒ 窗口不会无限延长
  EVAL_DF_SET(false)
  EVAL_DF_SET(true)
  at204(pf, 300, -300) -- 又一次漂移（战斗结束前不该被修）
  local s3a = EVAL_DF_TEST_STATE()
  eq(s3a.keepLive, true, "组204③前置：窗口已武装（此时还没进战斗）")
  TEST.inCombat = true
  TEST.chat = ""
  for _i = 1, LIM.tries do
    local f = tick204:GetScript("OnUpdate")
    if type(f) == "function" then pcall(f, LIM.period) end
  end
  local s3 = EVAL_DF_TEST_STATE()
  eq(s3.keepRuns, 0, "组204③★★★战斗中**一次净检查都不做**（不重锚）")
  eq(s3.keepSkips, LIM.tries, "组204③★跳过次数如实计数（实测 " .. tostring(s3.keepSkips) .. "）")
  eq(pf:GetLeft(), 300, "组204③★★★战斗中**没有**把目标拽回存档位置（左边缘仍是 " ..
     tostring(pf:GetLeft()) .. "）")
  eq(s3.keepDone, true, "组204③★★★评估次数上限一到就停 ⇒ 跳过**不会**让窗口无限延长")
  eq(s3.keepWhy, "skipped", "组204③★结束原因如实记为 skipped（实测 " .. tostring(s3.keepWhy) .. "）")
  eq(tick204:GetScript("OnUpdate") == nil, true, "组204③★tick 脚本被摘掉（无常驻）")
  eq(string.find(tostring(TEST.chat or ""), "跳过", 1, true) ~= nil, true, "组204③★播报点明了跳过（不静默）")
  TEST.inCombat = nil

  -- ③b 绝对墙钟上限：帧率极低 / dt 很大时也不能靠「等」把窗口拖长
  EVAL_DF_SET(false)
  EVAL_DF_SET(true)
  eq(EVAL_DF_TEST_STATE().keepLive, true, "组204③b前置：窗口已武装")
  TEST.chat = ""
  local f3b = tick204:GetScript("OnUpdate")
  if type(f3b) == "function" then pcall(f3b, LIM.wall + 1) end
  local s3b = EVAL_DF_TEST_STATE()
  eq(s3b.keepDone, true, "组204③b★★★单帧 dt 就超过墙钟上限 ⇒ 当场停止（窗口不会靠「等」延长）")
  eq(s3b.keepWhy, "wall", "组204③b★结束原因如实记为 wall（实测 " .. tostring(s3b.keepWhy) .. "）")
  eq(s3b.keepRuns < LIM.checks, true, "组204③b★★净检查没查满就被上限叫停（实测 " .. tostring(s3b.keepRuns) ..
     " 次 < " .. tostring(LIM.checks) .. "）—— 如实说明，不硬凑")
  eq(string.find(tostring(TEST.chat or ""), "上限", 1, true) ~= nil, true, "组204③b★播报点明「按上限停止」")

  -- ④ 拖拽中跳过（既有行为不许退化）：复查不与手动拖拽抢锚点
  EVAL_DF_SET(false)
  EVAL_DF_SET(true)
  local h204 = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(h204 ~= nil, true, "组204④前置：拿得到 PlayerFrame 的拖拽柄（真实控件）")
  at204(pf, 500, -500)
  TEST.cursorX, TEST.cursorY = 400, 300
  local s4a = EVAL_DF_TEST_STATE()
  if h204 then
    local md = h204:GetScript("OnMouseDown")
    if type(md) == "function" then pcall(md) end
  end
  eq(EVAL_DF_TEST_STATE().dragging, true, "组204④前置：拖拽真的开始了（真实 OnMouseDown）")
  local f4 = tick204:GetScript("OnUpdate")
  if type(f4) == "function" then pcall(f4, LIM.period) end
  local s4 = EVAL_DF_TEST_STATE()
  eq(s4.keepRuns, 0, "组204④★★★拖拽进行中：不做净检查（不重锚）——既有行为没退化")
  eq(s4.keepSkips, s4a.keepSkips + 1, "组204④★这次评估被如实记为「跳过」（" .. tostring(s4.keepSkips) .. "）")
  eq(s4.keepDone, false, "组204④★跳过不等于结束：窗口仍在")
  eq(pf:GetLeft(), 500, "组204④★★★复查没有把正在被拖的目标拽走（左边缘仍是 " .. tostring(pf:GetLeft()) .. "）")
  EVAL_DF_SET(false) -- 收尾：以 disable 结束拖拽（这条路径不弹属性窗，why=disable）
  eq(EVAL_DF_TEST_STATE().dragging, false, "组204④收尾：拖拽结束（disable 路径，不弹窗）")

  -- ⑤【任务 B】重置 = 还原 缩放/透明度/显示(+位置) + 清掉记录字段；清空即整条删除；带数字播报
  EVAL_DF_SET(false)
  EVAL_HELP_CONFIG.dragFrames = nil
  EVAL_DF_SET(true)
  local store5 = EVAL_DF_TEST_STORE()
  at204(pf, 100, -50)
  store5.PlayerFrame = { base = EVAL_DF_TEST_CAPTURE("PlayerFrame"), dx = 0, dy = 0,
                         scale = 0.6, alpha = 0.4, hidden = true }
  store5.TargetFrame = { scale = 0.8 }        -- 只有属性、没有定位 ⇒ 清完应**整条删除**
  store5.ChatFrame1 = { hidden = true }       -- 同上（显隐一项）
  pf:SetScale(0.6) pf:SetAlpha(0.4) pf:Hide()
  tf:SetScale(0.8)
  cf1:Hide()
  at204(pf, 400, -400) -- 位置也漂一下，好验「位置一起还原」
  TEST.chat = ""
  local n5 = EVAL_DF_RESET()
  eq(n5, 3, "组204⑤★重置处理了 3 个有记录的目标（实测 " .. tostring(n5) .. "）")
  eq(pf:GetScale(), 1, "组204⑤★★★缩放还原成 1（实测 " .. tostring(pf:GetScale()) .. "）")
  eq(pf:GetAlpha(), 1, "组204⑤★★★透明度还原成 1（实测 " .. tostring(pf:GetAlpha()) .. "）")
  eq(pf:IsShown(), true, "组204⑤★★★被隐藏的目标重新 Show()")
  eq(pf:GetLeft(), 100, "组204⑤★★位置也回原始锚点（左边缘 " .. tostring(pf:GetLeft()) .. "）")
  -- ★先验「目标当前的真值」（最直接的判据），再验「记录字段被清 / 整条删除」
  eq(tf:GetScale(), 1, "组204⑤★★★只带属性（没有定位基准）的目标，缩放也要还原成 1（实测 " ..
     tostring(tf:GetScale()) .. "）")
  eq(cf1:IsShown(), true, "组204⑤★★只带显隐记录的目标也要重新 Show()")
  local rec5 = EVAL_DF_TEST_STORE().PlayerFrame
  eq(rec5 ~= nil and rec5.scale == nil and rec5.alpha == nil and rec5.hidden == nil, true,
     "组204⑤★★★记录里的 缩放/透明度/显隐 三项字段被清掉（scale=" .. tostring(rec5 and rec5.scale) ..
     " alpha=" .. tostring(rec5 and rec5.alpha) .. " hidden=" .. tostring(rec5 and rec5.hidden) .. "）")
  eq(rec5 ~= nil and rec5.dx == nil and rec5.dy == nil, true, "组204⑤★★定位字段也被清掉（dx/dy=nil）")
  eq(rec5 ~= nil and type(rec5.base) == "table", true, "组204⑤★只剩定位基准 ⇒ 这条记录保留（不是无脑整条删）")
  eq(EVAL_DF_TEST_STORE().TargetFrame == nil, true, "组204⑤★★★清完没有别的字段 ⇒ **整条记录删除**（只带缩放的）")
  eq(EVAL_DF_TEST_STORE().ChatFrame1 == nil, true, "组204⑤★★★同上（只带显隐的）")
  local chat5 = tostring(TEST.chat or "")
  eq(string.find(chat5, "缩放还原 2", 1, true) ~= nil, true, "组204⑤★播报带数字：缩放还原 2（头像+目标）")
  eq(string.find(chat5, "透明度还原 1", 1, true) ~= nil, true, "组204⑤★播报带数字：透明度还原 1")
  eq(string.find(chat5, "显示还原 2", 1, true) ~= nil, true, "组204⑤★播报带数字：显示还原 2（头像+聊天框）")
  eq(string.find(chat5, "位置还原 1", 1, true) ~= nil, true, "组204⑤★播报带数字：位置还原 1")

  -- ⑤b 战斗保护：战斗中**不碰**这三项，且**字段原样保留**（绝不能「没还原却把记录清了」）
  EVAL_DF_TEST_STORE().PlayerFrame = { scale = 0.5 }
  pf:SetScale(0.5)
  TEST.inCombat = true
  TEST.chat = ""
  EVAL_DF_RESET()
  TEST.inCombat = nil
  eq(pf:GetScale(), 0.5, "组204⑤b★★★战斗中不改缩放（客户端保护，实测 " .. tostring(pf:GetScale()) .. "）")
  local rec5b = EVAL_DF_TEST_STORE().PlayerFrame
  eq(rec5b ~= nil and rec5b.scale == 0.5, true,
     "组204⑤b★★★没还原 ⇒ 记录**原样保留**（不许「没还原却把记录清了」）")
  eq(string.find(tostring(TEST.chat or ""), "战斗", 1, true) ~= nil, true, "组204⑤b★如实提示战斗中不改属性")

  -- ⑤c 端到端：用户点的是**工具箱那一行的 [重置]** —— 走真实 OnClick，属性一样被还原
  EVAL_HELP_CFG_SETTAB(3)
  EVAL_TB_TEST_GOTO("dbgDrag")
  local btn5 = EVAL_TEST_TB_CLR_FOR("dbgDrag")
  eq(btn5 ~= nil, true, "组204⑤c前置：拿到工具箱「图层拖拽柄」行的 [重置] 按钮")
  EVAL_DF_TEST_STORE().PlayerFrame = { scale = 0.25 }
  pf:SetScale(0.25)
  local click5 = btn5 and btn5:GetScript("OnClick")
  eq(type(click5) == "function", true, "组204⑤c★[重置] 真的挂了 OnClick（不是只画了个按钮）")
  if type(click5) == "function" then pcall(click5) end
  eq(pf:GetScale(), 1, "组204⑤c★★★点工具箱 [重置] ⇒ 缩放还原成 1（实测 " .. tostring(pf:GetScale()) .. "）")
  eq(EVAL_DF_TEST_STORE().PlayerFrame == nil, true, "组204⑤c★★清完没别的字段 ⇒ 整条记录删除（只带缩放）")

  -- ⑥【任务 C】[重置] 悬停清单：走**工具箱真实按钮的 OnEnter**，读真 GameTooltip 的行
  EVAL_HELP_CFG_SETTAB(3)
  EVAL_TB_TEST_GOTO("dbgDrag")
  local btn204 = EVAL_TEST_TB_CLR_FOR("dbgDrag")
  eq(btn204 ~= nil, true, "组204⑥前置：拿到「图层拖拽柄」行的右侧 [重置] 按钮")
  local function tip204()
    TEST.tipLines = nil
    local fn = btn204 and btn204:GetScript("OnEnter")
    if type(fn) ~= "function" then return "", {} end
    pcall(fn)
    local lines = {}
    for _, ln in ipairs(TEST.tipLines or {}) do table.insert(lines, tostring(ln.text or "")) end
    return table.concat(lines, "\n"), lines
  end
  local function rowOf204(lines, label)
    for _, ln in ipairs(lines) do
      if string.sub(ln, 1, string.len(label)) == label then return ln end
    end
    return nil
  end
  -- 夹具：**记录里写 0.90，目标当前是 0.35** ⇒ 清单若读存档，这一条当场露馅
  pf:SetScale(0.35) pf:SetAlpha(0.62) pf:Show()
  EVAL_DF_TEST_STORE().PlayerFrame = { base = EVAL_DF_TEST_CAPTURE("PlayerFrame"), dx = 0, dy = 0, scale = 0.9 }
  cf1:Hide() -- 再造一个「隐藏」的目标
  local txt6, lines6 = tip204()
  eq(string.len(txt6) > 0, true, "组204⑥前置：悬停后 tooltip 真的有行（" .. tostring(table.getn(lines6)) .. " 行）")
  local rowPF = rowOf204(lines6, "用户头像")
  eq(rowPF ~= nil, true, "组204⑥★★清单里按目标名给出逐行（用户头像）")
  eq(rowPF ~= nil and string.find(rowPF, "缩放 0.35", 1, true) ~= nil, true,
     "组204⑥★★★逐行读的是**目标当前**的缩放（0.35）：" .. tostring(rowPF))
  eq(rowPF ~= nil and string.find(rowPF, "透明度 0.62", 1, true) ~= nil, true,
     "组204⑥★★★逐行读的是**目标当前**的透明度（0.62）")
  eq(rowPF ~= nil and string.find(rowPF, "显示", 1, true) ~= nil, true, "组204⑥★★★逐行给出显示/隐藏（显示）")
  eq(string.find(txt6, "0.90", 1, true) == nil, true,
     "组204⑥★★★反向哨兵：记录里那个 0.90 **不许**出现在清单里（清单不是抄存档）")
  local rowCF1 = rowOf204(lines6, "聊天框")
  eq(rowCF1 ~= nil and string.find(rowCF1, "隐藏", 1, true) ~= nil, true,
     "组204⑥★★★被隐藏的目标逐行写「隐藏」：" .. tostring(rowCF1))
  local rowTF = rowOf204(lines6, "目标头像")
  eq(rowTF ~= nil and string.find(rowTF, "默认值", 1, true) ~= nil, true,
     "组204⑥★★★默认值的目标如实写「默认值」（不是不显示）：" .. tostring(rowTF))
  eq(rowTF ~= nil and string.find(rowTF, "缩放 1.00", 1, true) ~= nil
     and string.find(rowTF, "透明度 1.00", 1, true) ~= nil, true,
     "组204⑥★★默认值也逐项显示（缩放 1.00 / 透明度 1.00）")
  local last6 = tostring(lines6[table.getn(lines6)] or "")
  eq(string.find(last6, "合计", 1, true) ~= nil, true, "组204⑥★★末行是合计：" .. last6)
  eq(string.find(last6, "6 个目标", 1, true) ~= nil, true, "组204⑥★合计里的目标数 = 6 个（目标表口径）")

  -- ⑦ 反向哨兵：改**目标（桩）**的值 ⇒ 清单文本必须跟着变（证明读的是目标本身）
  pf:SetScale(0.42)
  local txt7 = tip204()
  eq(string.find(txt7, "缩放 0.42", 1, true) ~= nil, true,
     "组204⑦★★★改目标的缩放 0.35→0.42 ⇒ 清单当场跟着变（读的是目标，不是任何副本）")
  eq(string.find(txt7, "缩放 0.35", 1, true) == nil, true, "组204⑦★★旧值 0.35 不再出现")
  pf:Hide()
  local _, lines7 = tip204()
  local rowPF7 = rowOf204(lines7, "用户头像")
  eq(rowPF7 ~= nil and string.find(rowPF7, "隐藏", 1, true) ~= nil, true,
     "组204⑦★★★把目标藏起来 ⇒ 该行变成「隐藏」：" .. tostring(rowPF7))
  pf:SetAlpha(0.11)
  local txt7c = tip204()
  eq(string.find(txt7c, "透明度 0.11", 1, true) ~= nil, true, "组204⑦★★透明度同样逐次现读（0.11）")

  -- 收尾：目标/存档恢复到不碍事的状态（本组是最后一组，仍不留残留）
  pf:Show() pf:SetScale(1) pf:SetAlpha(1)
  at204(pf, 100, -50)
  cf1:Show()
  EVAL_DF_TEST_STORE().PlayerFrame = nil
  EVAL_DF_SET(false)
  EVAL_HELP_CFG_SETTAB(3)

  print(string.format("  框拖拽启动期有界复查：周期 %.1fs × 净检查 %d 次（评估上限 %d · 墙钟 %.0fs）· " ..
    "5 次全符合 → 摘脚本永久停（未重设，ClearAllPoints 0 次）· 漂移 → 重设 1 轮后继续 · " ..
    "战斗/拖拽中跳过且按上限停 · 重置还原 缩放2/透明1/显示2/位置1 并清字段（清空即整条删）· " ..
    "清单逐行读真值（6 行 + 合计）", LIM.period, LIM.checks, LIM.tries, LIM.wall))
  if fails204 == TESTASSERT_FAILS then print("GROUP 204 (框拖拽有界复查/重置还原/清单真值): PASS") end
end

-- ===== 组 206（1.74.33 **改口径**）：宽/高对**所有窗口停用**（原「新增宽度/高度」需求被用户第二次澄清推翻）=====
-- 用户原话（1.74.31）：「图层拖拽 完成弹窗属性设置还要增加当前层宽度/高度设置」
-- 用户第二次澄清（1.74.33）：「图层拖拽功能.是所有窗口都不能调整宽高.会把内部原始撕裂.是我之前的需求说错了
--   属性配置需要支持调整的是窗口的 x,y 坐标值」
-- ⇒ 本组从「验宽高能改」**翻转为验宽高改不了**（旧的 5 行 / 选 500×200 / 还原 那套断言全部作废 ——
--   留着它们就会在改口径之后一直红，而「判据照需求改」是本项目纪律）：
--   ① 弹窗**不创建**宽/高行（普通目标与图标目标都一样），说明行常显，另外三行照旧在
--   ② 真实下拉 → 真实 [保存] 走一遍：缩放照写，但**一个宽高写调用都没发**、存档里不留 w/h/ow/oh、播报不出现「宽 N」
--   ③ 老记录（w/h + 原始值 ow/oh）⇒ 清理时**还原原尺寸**并如实播报
--   ④ 只有 w/h、没有原始值 ⇒ 清记录但**不动目标**（不猜一个「默认尺寸」）
--   ⑤ 存档里塞着宽高时，应用存档也**一个宽高写调用都不发**
do
  local pf = _G["PlayerFrame"]
  eq(pf ~= nil, true, "组206前置：PlayerFrame 在位")
  TEST.inCombat = nil
  local store206 = EVAL_DF_TEST_STORE()
  eq(type(store206) == "table", true, "组206前置：拖拽存档表在位（EVAL_HELP_CONFIG.dragFrames）")
  -- 存档隔离：本组只留自己造的记录，收尾原样放回
  local saved206 = {}
  for _, t in ipairs(EVAL_DF_TARGETS()) do
    saved206[t.name] = store206[t.name]
    store206[t.name] = nil
  end
  local function readNum206(fr, fn)
    if type(fr[fn]) ~= "function" then return nil end
    local ok, v = pcall(fr[fn], fr)
    if ok and tonumber(v) then return tonumber(v) end
    return nil
  end
  -- 写接口计数器：把「有没有偷偷写宽高」变成可数的东西（本项目「行为零变化」要用哨兵钉住的纪律）
  local WR206 = { w = 0, h = 0, scale = 0 }
  local OG206 = {}
  local function wrap206(k, tag)
    OG206[tag] = pf[k]
    rawset(pf, k, function(self, ...)
      WR206[tag] = WR206[tag] + 1
      local f = OG206[tag]
      if type(f) == "function" then return f(self, ...) end
      return nil
    end)
  end
  wrap206("SetWidth", "w") wrap206("SetHeight", "h") wrap206("SetScale", "scale")
  local wasOn206 = EVAL_DF_ENABLED()
  EVAL_DF_SET(true)

  -- ① 弹窗**不再创建**宽/高行（走真实入口 dfCommitPop）
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组206① 真实入口打开弹窗（dfCommitPop）")
  local pop206 = EVAL_DF_TEST_POP()
  eq(pop206 ~= nil and pop206.rowBy ~= nil, true, "组206①前置：弹窗读值口在位（按 key 找行）")
  eq(pop206 and pop206.rowBy and pop206.rowBy.w == nil and pop206.rowBy.h == nil, true,
    "组206①★★★ 弹窗里**没有**宽/高两行（用户第二次澄清：所有窗口都不能改宽高）")
  eq(pop206 ~= nil and table.getn(pop206.rows) == 5, true,
    "组206①★★ 弹窗 5 行 = 显隐/缩放/透明度 + **X/Y 坐标**（宽/高两行已删），实测 " ..
    tostring(pop206 and table.getn(pop206.rows)))
  eq(pop206 and pop206.rowBy and pop206.rowBy.x ~= nil and pop206.rowBy.y ~= nil, true,
    "组206①★★★ X/Y 两行在位（用户第二次澄清：属性配置要支持调整的是窗口的 x,y 坐标值）")
  -- ★★★1.74.33 用户（截图：那行说明与底部 取消/保存 **叠在一起**）：
  --   「属性配置信息重叠,可以将信息在外部触发图标tooltip 内展示」⇒ 弹窗里**不再有说明控件**，
  --   信息改挂**图标 tooltip**（从结构上杜绝重叠：弹窗只管控件本身）。
  eq(pop206 == nil or pop206.note == nil, true,
    "组206①★★★ 弹窗里**没有**说明文字控件（说明已搬去图标 tooltip —— 结构上不可能再重叠）")
  if type(store206) == "table" then store206.GuildFrame = { scale = 0.8 } end
  local gf206 = CreateFrame("Frame", "GuildFrame", UIParent)
  EVAL_DF_TEST_TARGETS_RESET()
  eq(EVAL_DF_TEST_POP_FOR("GuildFrame"), true, "组206① 图标目标的弹窗也能打开")
  local popG206 = EVAL_DF_TEST_POP()
  eq(popG206 and popG206.rowBy and popG206.rowBy.w == nil and popG206.rowBy.h == nil, true,
    "组206①★★★ 图标目标同样没有宽/高行（口径 = **所有窗口**）")
  -- ★说明信息确实挂在**图标 tooltip** 上（走真实 OnEnter 点火，读桩记下来的 AddLine 文本）
  EVAL_DF_REFRESH()   -- 刷新一次 ⇒ 给 GuildFrame 挂上图标（tooltip 在它身上）
  local icon206 = (type(EVAL_DF_TEST_ICON) == "function") and EVAL_DF_TEST_ICON("GuildFrame") or nil
  eq(icon206 ~= nil, true, "组206①前置：拿到 GuildFrame 的图标（说明文字挂在它身上）")
  TEST.tipLines = nil
  if icon206 then
    local okE, fnE = pcall(icon206.GetScript, icon206, "OnEnter")
    if okE and type(fnE) == "function" then pcall(fnE, icon206) end
  end
  local tipTxt206 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipTxt206 = tipTxt206 .. tostring(ln.text) .. "\n" end
  eq(string.find(tipTxt206, "宽/高已停用", 1, true) ~= nil, true,
    "组206①★★★ 图标 tooltip 里说明了「宽/高已停用」（实测：\n" .. tipTxt206 .. "）")
  eq(string.find(tipTxt206, "X/Y", 1, true) ~= nil, true,
    "组206①★★★ 图标 tooltip 里也说明了位置怎么调（X/Y 语义 + 微调步长）")

  -- ② 真实下拉 → 真实 [保存]：缩放照写，宽高一个写调用都没发
  if type(store206) == "table" then
    store206.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0 }
  end
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组206② 重新打开普通目标的弹窗")
  pop206 = EVAL_DF_TEST_POP()
  local rowScale206 = pop206 and pop206.rowBy and pop206.rowBy.scale
  eq(type(rowScale206) == "table" and rowScale206.btn ~= nil, true, "组206②前置：缩放行在位（按 key 找得到）")
  local chosen206 = nil
  if rowScale206 then
    local okb, fn = pcall(rowScale206.btn.GetScript, rowScale206.btn, "OnClick")
    if okb and type(fn) == "function" then
      fn()   -- 打开下拉（顺带按 opts 填好条目文字）
      for _, rb in ipairs(pop206.list and pop206.list.rows or {}) do
        local shown = false
        if type(rb.IsShown) == "function" then
          local oks, v = pcall(rb.IsShown, rb) shown = (oks and v) and true or false
        end
        if shown then
          local okr, fn2 = pcall(rb.GetScript, rb, "OnClick")
          if okr and type(fn2) == "function" then fn2() chosen206 = rowScale206.value break end
        end
      end
    end
  end
  eq(chosen206 ~= nil, true, "组206②★ 通过**真实下拉**选了一个缩放值（实测 " .. tostring(chosen206) .. "）")
  WR206.w, WR206.h, WR206.scale = 0, 0, 0     -- 清零：下面 [保存] 那一下的写调用才算数
  local saved206ok = false
  if pop206 and pop206.save then
    local oks, fn = pcall(pop206.save.GetScript, pop206.save, "OnClick")
    if oks and type(fn) == "function" then pcall(fn) saved206ok = true end
  end
  eq(saved206ok, true, "组206②前置：走了真实 [保存] OnClick")
  eq(WR206.w == 0 and WR206.h == 0, true,
    "组206②★★★ [保存] **一个宽高写调用都没发**（实测 SetWidth " .. tostring(WR206.w) .. " / SetHeight " .. tostring(WR206.h) .. "）")
  eq(WR206.scale >= 1, true,
    "组206②★★ 缩放照写（实测 " .. tostring(WR206.scale) .. " 次）—— 证明不是「整段没干活」的假绿")
  local recP206 = (type(store206) == "table") and store206.PlayerFrame or nil
  eq(type(recP206) == "table" and recP206.w == nil and recP206.h == nil and recP206.ow == nil and recP206.oh == nil, true,
    "组206②★★★ 存档里**不留** w/h/ow/oh（宽高已停用）")
  eq(type(recP206) == "table" and recP206.scale ~= nil, true, "组206②★★ 缩放照旧入库")
  local chat206 = tostring(TEST.chat or "")
  eq(string.find(chat206, "宽 ", 1, true) == nil, true, "组206②★★ 播报里**不出现**「宽 N」（宽高已停用）")

  -- ③ 老记录（有原始值）⇒ 清理 + 还原 + 如实播报
  if type(store206) == "table" then
    store206.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0,
      w = 500, h = 200, ow = 300, oh = 60 }
  end
  pcall(pf.SetWidth, pf, 500) pcall(pf.SetHeight, pf, 200)
  TEST.chat = nil
  local nClean206, restored206 = EVAL_DF_SIZE_CLEAN(true)
  eq(nClean206 >= 1 and restored206 >= 2, true,
    "组206③★★★ 清理老记录并还原原尺寸（目标 " .. tostring(nClean206) .. " 个 / 还原 " .. tostring(restored206) .. " 项）")
  eq(readNum206(pf, "GetWidth") == 300 and readNum206(pf, "GetHeight") == 60, true,
    "组206③★★★ 宽高真的回到原始值 300×60（实测 " .. tostring(readNum206(pf, "GetWidth")) .. "×" ..
    tostring(readNum206(pf, "GetHeight")) .. "）")
  local rec3_206 = (type(store206) == "table") and store206.PlayerFrame or nil
  eq(type(rec3_206) == "table" and rec3_206.w == nil and rec3_206.h == nil and rec3_206.ow == nil and rec3_206.oh == nil, true,
    "组206③★★ 记录里的宽高与原始值都被清掉（不留「早已停用」的字段）")
  eq(string.find(tostring(TEST.chat or ""), "宽高", 1, true) ~= nil, true,
    "组206③★★ 播报如实说明清了宽高（" .. tostring(TEST.chat) .. "）")
  -- ★X/Y 行的两个微调按钮也要在（用户选定「下拉预设 + [−][+] 微调」）
  eq(type(pop206) == "table" and pop206.rowBy and type(pop206.rowBy.x) == "table"
    and pop206.rowBy.x.nudgeMinus ~= nil and pop206.rowBy.x.nudgePlus ~= nil, true,
    "组206③★★ X 行带 [−][+] 两个微调按钮（真实控件，不是画上去的字）")

  -- ④ 只有 w/h、没有原始值 ⇒ 清记录但**不动目标**
  if type(store206) == "table" then
    store206.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0, w = 400 }
  end
  pcall(pf.SetWidth, pf, 250)
  TEST.chat = nil
  EVAL_DF_SIZE_CLEAN(true)
  eq(readNum206(pf, "GetWidth") == 250, true,
    "组206④★★★ 没有原始值 ⇒ **不去猜、不改目标**（宽仍是 250，实测 " .. tostring(readNum206(pf, "GetWidth")) .. "）")
  local rec4_206 = (type(store206) == "table") and store206.PlayerFrame or nil
  eq(type(rec4_206) == "table" and rec4_206.w == nil, true, "组206④★★ 记录里的 w 被清掉")

  -- ⑤ 应用存档：存档里塞着宽高也一个写调用都不发
  if type(store206) == "table" then
    store206.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0,
      w = 600, h = 180, scale = 1 }
  end
  WR206.w, WR206.h = 0, 0
  EVAL_DF_APPLYALL(true)
  eq(WR206.w == 0 and WR206.h == 0, true,
    "组206⑤★★★ 应用存档**不写宽高**（实测 SetWidth " .. tostring(WR206.w) .. " / SetHeight " .. tostring(WR206.h) .. "）")

  -- 收尾
  rawset(pf, "SetWidth", OG206.w) rawset(pf, "SetHeight", OG206.h) rawset(pf, "SetScale", OG206.scale)
  for name, rec in pairs(saved206) do store206[name] = rec end
  EVAL_DF_SET(wasOn206)
  EVAL_DF_TEST_RESET_TIMERS()
  _G["GuildFrame"] = nil
  EVAL_DF_TEST_TARGETS_RESET()
  print(string.format("  宽高整体停用：弹窗 %s 行（宽/高行=%s）· 保存写宽高 %d 次 · 清理 %s 个/还原 %s 项 · 应用存档写宽高 %d 次",
    tostring(pop206 and table.getn(pop206.rows)), tostring(pop206 and pop206.rowBy and pop206.rowBy.w == nil),
    WR206.w + WR206.h, tostring(nClean206), tostring(restored206), WR206.w + WR206.h))
  print("GROUP 206 (宽/高对所有窗口停用：弹窗不建行 + 保存/应用都不写 + 老记录清理还原 + 不猜默认尺寸): PASS")
end

-- ===== 组 207（1.74.31）：框拖拽新增「动作条1~4」= 候选名解析 + 去重 + 探针 =====
-- 用户要求：「图层拖拽 将 动作条1,2,3,4 也加入可拖拽项」。
-- ★为什么本组这么写：本客户端的动作条**真实帧名未知**（客户端 UI 编译在 pak 里，磁盘没有 FrameXML，
--   别的插件也一次没引用过 MultiBar*）⇒ 实现走**候选名解析**，本组就用夹具把「解析、去重、探针、清单」
--   四条行为全部钉住（不依赖真名到底叫什么）。
do
  local raw = EVAL_DF_TEST_TARGETS_RAW()
  eq(type(raw) == "table" and table.getn(raw) >= 10, true,
     "组207① 目标表里已有 ≥10 项（6 个原目标 + 4 个动作条），实测 " .. tostring(type(raw) == "table" and table.getn(raw) or -1))
  -- ① 四个动作条目标都在，且都带候选名
  local bars = {}
  for _, t in ipairs(raw) do
    if t.label == "动作条1" or t.label == "动作条2" or t.label == "动作条3" or t.label == "动作条4" then
      table.insert(bars, t)
    end
  end
  eq(table.getn(bars), 4, "组207① 四个动作条目标都在（实测 " .. tostring(table.getn(bars)) .. " 个）")
  local allCands = true
  for _, t in ipairs(bars) do
    if type(t.cands) ~= "table" or table.getn(t.cands) < 3 then allCands = false end
  end
  eq(allCands, true, "组207① ★每个动作条都给了候选名表（≥3 个候选；本客户端真名未知，不许写死一个）")

  -- ② 干净状态：桩里没有动作条 ⇒ 四个都解析不到、清单里如实计数、**合计仍是最后一行**
  EVAL_DF_TEST_TARGETS_RESET()
  local list0 = EVAL_DF_TARGETS()
  local unresolved = 0
  for _, t in ipairs(list0) do
    if t.label == "动作条1" or t.label == "动作条2" or t.label == "动作条3" or t.label == "动作条4" then
      if t.frame == nil then unresolved = unresolved + 1 end
    end
  end
  eq(unresolved, 4, "组207② 桩里没有动作条帧 ⇒ 四个动作条目标如实「未解析」（实测 " .. tostring(unresolved) .. "）")
  local sum0 = EVAL_DF_SUMMARY()
  local last0 = tostring(sum0[table.getn(sum0)] or "")
  eq(string.find(last0, "合计", 1, true) ~= nil, true, "组207②★★末行仍是「合计」（既有判据不许被新加的一行挤掉）：" .. last0)
  local missLine = nil
  for _, ln in ipairs(sum0) do
    if string.find(ln, "找不到帧", 1, true) ~= nil then missLine = ln end
  end
  -- ★1.74.32：又加了「队伍层/团队层」两个目标（桩里同样没有它们的帧）⇒ 总缺帧计数**现算**，不写死
  local missAll = 0
  for _, t in ipairs(list0) do if t.frame == nil then missAll = missAll + 1 end end
  eq(missAll >= 6, true, "组207② 干净状态未解析目标 ≥6（4 个动作条 + 队伍层 + 团队层），实测 " .. tostring(missAll))
  eq(missLine ~= nil and string.find(missLine, tostring(missAll), 1, true) ~= nil, true,
     "组207②★清单里有一行如实说明「另有 " .. tostring(missAll) .. " 个目标找不到帧」：" .. tostring(missLine))

  -- ③ 候选名解析：桩里造一个 MultiBar1 → 「动作条1」应当命中它，而**存档键仍是候选第一名**
  local fake = {}
  fake.GetWidth = function() return 300 end
  fake.GetHeight = function() return 40 end
  fake.IsShown = function() return true end
  fake.GetScale = function() return 1 end
  fake.SetScale = function() end
  fake.GetAlpha = function() return 1 end
  fake.SetAlpha = function() end
  _G["MultiBar1"] = fake
  EVAL_DF_TEST_TARGETS_RESET()
  local hit = nil
  for _, t in ipairs(EVAL_DF_TARGETS()) do
    if t.label == "动作条1" then hit = t end
  end
  eq(hit ~= nil and hit.frame == fake, true, "组207③★★候选名解析：动作条1 命中了桩里的 MultiBar1")
  eq(hit ~= nil and hit.resolved == "MultiBar1", true,
     "组207③★★★对外如实交出**命中的真实帧名**（resolved = " .. tostring(hit and hit.resolved) .. "）")
  eq(hit ~= nil and hit.name == "MultiBarBottomLeft", true,
     "组207③★★存档键仍是候选第一名（与命中哪个候选无关 ⇒ 换客户端/改名也不丢老存档）")
  -- 命中之后：清单里该行真的按**标签**出现，缺帧计数降到 3
  local sum1 = EVAL_DF_SUMMARY()
  local rowBar = nil
  local miss1 = nil
  for _, ln in ipairs(sum1) do
    if string.sub(ln, 1, string.byte("动")) == "动作条1" or string.find(ln, "动作条1：", 1, true) ~= nil then rowBar = ln end
    if string.find(ln, "找不到帧", 1, true) ~= nil then miss1 = ln end
  end
  eq(rowBar ~= nil, true, "组207③★★清单里出现「动作条1」那一行（读的是解析到的帧）")
  eq(rowBar ~= nil and string.find(rowBar, "宽 300", 1, true) ~= nil, true,
     "组207③★★★该行读的是**桩帧当前**的宽 300（不是抄存档）：" .. tostring(rowBar))
  eq(miss1 ~= nil and string.find(miss1, tostring(missAll - 1), 1, true) ~= nil, true,
     "组207③缺帧计数降到 " .. tostring(missAll - 1) .. "：" .. tostring(miss1))

  -- ④ 面板列表用**解析到的帧名**（不是 tgt.name）：条目里应出现 [全局] MultiBar1
  local hook207 = EVAL_DBX_TEST_UI()
  if hook207 and hook207.ui then
    local u7 = hook207.ui
    local okShow7, shown7 = pcall(u7.root.IsShown, u7.root)
    if not (okShow7 and shown7) then CMD7 = (type(SlashCmdList) == "table") and SlashCmdList["EHDEBUGBOX"] or nil
      if type(CMD7) == "function" then CMD7("ui") end end
    local CMD207 = (type(SlashCmdList) == "table") and SlashCmdList["EHDEBUGBOX"] or nil
    if type(CMD207) == "function" then CMD207("scan") end
    local foundRow = false
    for _, e in ipairs(u7.entries or {}) do
      if e.f == fake then foundRow = true end
      if e.path == "[全局] MultiBar1" then foundRow = true end
    end
    eq(foundRow, true, "组207④★★面板列表按**命中的真实帧名**列出该目标（[全局] MultiBar1），不是候选第一名")
    u7.scanSrcTouched = nil
  end

  -- ⑤ 去重：两个候选槽撞到同一帧 → 第一个认领者胜（否则同帧两条柄 + 两条记录互相打架）
  local dupTargets = { raw[9], raw[10] } -- 动作条1 / 动作条2（表尾四项的前两项）
  local saved9, saved10 = dupTargets[1].cands, dupTargets[2].cands
  dupTargets[1].cands = { "EHDupBar" }
  dupTargets[2].cands = { "EHDupBar" }
  _G["EHDupBar"] = fake
  EVAL_DF_TEST_TARGETS_RESET()
  local l1, l2 = nil, nil
  for _, t in ipairs(EVAL_DF_TARGETS()) do
    if t.label == "动作条1" then l1 = t end
    if t.label == "动作条2" then l2 = t end
  end
  eq(l1 ~= nil and l1.frame == fake, true, "组207⑤前置：第一个候选槽认领了 EHDupBar")
  eq(l2 ~= nil and l2.frame == nil, true, "组207⑤★★★第二个候选槽**跳过**同一帧（不给同一个帧挂两条拖拽柄/两条记录）")
  -- 收尾：候选表、夹具、解析缓存全部还原
  dupTargets[1].cands, dupTargets[2].cands = saved9, saved10
  _G["EHDupBar"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  -- ⑥ 探针命令：候选逐个报在不在 + 全 _G 扫名字像动作条的帧 + 结果落存档（AI 可直接读）
  _G["MultiBar1"] = fake
  _G["MultiBarRight"] = fake
  EVAL_DF_TEST_TARGETS_RESET()
  TEST.chat = ""
  local n7, dump7 = EVAL_DF_PROBE_BARS()
  local chat7 = tostring(TEST.chat or "")
  eq(type(dump7) == "table" and type(dump7.targets) == "table", true, "组207⑥ 探针返回结构化结果（targets/found）")
  eq(n7 >= 2, true, "组207⑥★全 _G 扫到了名字像动作条的帧（实测 " .. tostring(n7) .. " 个）")
  eq(string.find(chat7, "MultiBar1", 1, true) ~= nil, true, "组207⑥★聊天里逐个报出候选/命中（含 MultiBar1）")
  local cfg7 = rawget(_G, "EVAL_HELP_CONFIG")
  eq(type(cfg7) == "table" and type(cfg7.dragBars) == "table", true,
     "组207⑥★★结果落存档 EVAL_HELP_CONFIG.dragBars（/reload 后 AI 直接读，不必用户复制粘贴）")
  eq(type(cfg7.dragBars.found) == "table" and table.getn(cfg7.dragBars.found) >= 2, true,
     "组207⑥★落档的 found 里有真帧记录（条数 " .. tostring(type(cfg7.dragBars.found) == "table" and table.getn(cfg7.dragBars.found) or -1) .. "）")
  -- ⑦ /edb bars 真实命令入口转发到探针（走真实 SlashCmdList）
  local CMD7b = (type(SlashCmdList) == "table") and SlashCmdList["EHDEBUGBOX"] or nil
  TEST.chat = ""
  if type(CMD7b) == "function" then CMD7b("bars") end
  local chat7b = tostring(TEST.chat or "")
  -- ★1.74.32：探针从「动作条探针」扩成「框体探针」（同一条命令也扫队伍/团队）⇒ 标题跟着改
  eq(string.find(chat7b, "框体探针", 1, true) ~= nil, true,
     "组207⑦★ /edb bars 真入口接通（输出含「框体探针」标题）")
  -- ★同一条入口的别名 /edb frames 也必须通（新旧命令名两条路都能到探针）
  TEST.chat = ""
  if type(CMD7b) == "function" then CMD7b("frames") end
  eq(string.find(tostring(TEST.chat or ""), "框体探针", 1, true) ~= nil, true,
     "组207⑦★ 别名 /edb frames 同样接通（命令名换成通用的之后仍留旧名，两种都走同一条路）")
  _G["MultiBar1"] = nil
  _G["MultiBarRight"] = nil
  EVAL_DF_TEST_TARGETS_RESET()
  if type(cfg7) == "table" then cfg7.dragBars = nil end

  print(string.format("  框拖拽动作条目标：目标表 %d 项（其中动作条 4）· 干净状态缺帧 %d 且末行仍为合计 · " ..
    "造 MultiBar1 ⇒ 动作条1 命中（resolved=%s，存档键 %s）· 清单读桩宽 300 · 面板按真名列出 · " ..
    "撞同一帧时第二槽跳过 %s · 探针扫到 %d 个（落档 found %d 条）· /edb bars 已接 %s",
    table.getn(raw), unresolved, tostring(hit and hit.resolved), tostring(hit and hit.name),
    tostring(l2 ~= nil and l2.frame == nil), n7,
    type(cfg7) == "table" and type(dump7) == "table" and table.getn(dump7.found) or -1,
    tostring(string.find(tostring(TEST.chat or ""), "框体探针", 1, true) ~= nil)))
  print("GROUP 207 (框拖拽动作条1~4：候选名解析/去重/探针/面板列出): PASS")
end

-- ===== 组 208（1.74.32）：框拖拽新增「队伍层 / 团队层」= 候选名解析 + **按需出现的事件跟随** =====
-- 用户要求：「拖拽图层再增加队伍层,团队层如果存在的话」。
-- ★「如果存在的话」有两层，本组两层都钉住：
--   ① **帧名未知**（同动作条1~4）⇒ 候选名解析，一个都没命中就**如实缺席**，存档键仍是候选第一名；
--   ② **帧体是按需出现的**（单人时客户端不显示队伍框、非团队时没有团队框）⇒ 必须有一条**事件驱动**的跟随：
--      事件到达时 ⓪ 先恢复存档参数（否则「在队伍里设过宽/高，下次组上人不生效」= 静默失败）
--      ① 再重贴拖拽柄；且必须是**有界**的（跟固定次数就停，不做常驻轮询），开关关掉立刻停。
-- ★纪律：全部走**真实脚本**（模块真实的 OnEvent / OnUpdate，不用自造计时器）与读值口，**不复刻映射逻辑**。
do
  local store8 = EVAL_DF_TEST_STORE()
  local wasOn8 = EVAL_DF_ENABLED()
  local savedPf8 = store8 and store8.PartyFrame
  local savedRf8 = store8 and store8.RaidFrame
  local savedPN8, savedRN8 = TEST.partyN, TEST.raidN
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_TEST_ROSTER_RESET()

  -- ① 目标表：两项都在，都带 roster 标记与候选名表；读值口也如实交出 roster 标记
  local raw8 = EVAL_DF_TEST_TARGETS_RAW()
  -- ★1.74.32 真机取证后改（探针实测）：本客户端**没有整队容器帧** ⇒ 队伍拆成「队伍成员1~4」四个独立目标
  local tMembers, tRaid = {}, nil
  for _, t in ipairs(raw8) do
    if string.sub(t.label, 1, 12) == "队伍成员" then table.insert(tMembers, t) end
    if t.label == "团队层" then tRaid = t end
  end
  eq(table.getn(tMembers) == 4 and tRaid ~= nil, true,
     "组208① 目标表里有「队伍成员1~4」四个 + 「团队层」（实测 " .. tostring(table.getn(tMembers)) .. " 个成员目标）")
  local rosterAll8 = true
  for _, t in ipairs(tMembers) do if t.roster ~= true then rosterAll8 = false end end
  eq(rosterAll8 and tRaid.roster == true, true,
     "组208①★ 四个成员 + 团队层都带 `roster = true`（跟随只碰这几项的唯一依据）")
  local memberCands8 = true
  for _, t in ipairs(tMembers) do
    if type(t.cands) ~= "table" or table.getn(t.cands) < 1 then memberCands8 = false end
  end
  eq(memberCands8, true, "组208①★ 四个成员各带候选名表（真名已实测，≥1 个即可）")
  eq(tRaid ~= nil and type(tRaid.cands) == "table" and table.getn(tRaid.cands) >= 3, true,
     "组208①★ 团队层给了候选名表（≥3 个候选）")
  local rMark8 = 0
  for _, t in ipairs(EVAL_DF_TARGETS()) do if t.roster then rMark8 = rMark8 + 1 end end
  eq(rMark8, 5, "组208① 读值口 EVAL_DF_TARGETS() 如实交出 roster 标记（实测 " .. tostring(rMark8) .. " 项，应为 5）")

  -- ② 干净状态（桩里没有队伍/团队帧）⇒ 这几项**如实缺席**（不报错、也不假装在）
  local clean8 = true
  for _, t in ipairs(EVAL_DF_TARGETS()) do
    if t.roster and t.frame ~= nil then clean8 = false end
  end
  eq(clean8, true, "组208②★★★ 没组队时队伍成员/团队层**如实缺席**（「如果存在的话」的那一半）")
  local missClean8 = nil
  for _, ln in ipairs(EVAL_DF_SUMMARY()) do
    if string.find(ln, "找不到帧", 1, true) ~= nil then missClean8 = ln end
  end
  eq(missClean8 ~= nil, true, "组208② 清单里如实说明缺帧：" .. tostring(missClean8))
  eq(string.find(tostring(missClean8), "队伍", 1, true) ~= nil, true,
     "组208②★ 文案点明了「队伍/团队没组队时本就缺席」（否则用户会把正常缺席当故障）")

  -- ③ 候选名解析：造一个 PartyMemberFrame1 → 「队伍成员1」命中它
  local pf8 = CreateFrame("Frame", "PartyMemberFrame1", UIParent)
  pf8:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -200)
  pf8:SetWidth(120) pf8:SetHeight(48)
  pf8:Show()
  EVAL_DF_TEST_TARGETS_RESET()
  local hitParty8 = nil
  for _, t in ipairs(EVAL_DF_TARGETS()) do if t.label == "队伍成员1" then hitParty8 = t end end
  eq(hitParty8 ~= nil and hitParty8.frame == pf8, true, "组208③★★ 队伍成员1 命中了桩里的 PartyMemberFrame1")
  eq(hitParty8 ~= nil and hitParty8.resolved == "PartyMemberFrame1", true,
     "组208③★★★ 对外如实交出错候选里**命中的真实帧名**（resolved = " .. tostring(hitParty8 and hitParty8.resolved) .. "）")
  eq(hitParty8 ~= nil and hitParty8.name == "PartyMemberFrame1", true,
     "组208③★★ 存档键 = 真名（探针已实测 ⇒ 不再靠候选第一名兜底）")

  -- ④ 事件跟随（本组核心）：帧已经出现了，但参数还没恢复过 ⇒ 真实 OnEvent 到达后必须 ① 恢复参数 ② 补柄
  EVAL_DF_SET(true) -- 跟随只在开关打开时工作（生产 OnEvent 里就过这道门）
  EVAL_DF_TEST_ROSTER_RESET() -- 清「已恢复过」的记账 = 模拟「帧刚出现」
  store8 = EVAL_DF_TEST_STORE()
  -- ★1.74.33 改口径：宽/高**对所有窗口停用**（会撕裂内部布局）⇒ 这条判据改用**缩放**来验
  --   「存档参数立刻生效」这个**性质**（性质不变、载体换成还支持的那一项）；顺带把「宽高没被写」一起钉住。
  store8.PartyMemberFrame1 = { scale = 0.6, base = { { "TOPLEFT", "UIParent", "TOPLEFT", 40, -200 } }, dx = 0, dy = 0 }
  eq(pf8:GetWidth(), 120, "组208④前置：桩帧初始宽 120（存档还没应用过）")
  eq(pf8:GetScale(), 1, "组208④前置：初始缩放 1（存档还没应用过）")
  local okEv8 = EVAL_DF_TEST_ROSTER_EVENT("PARTY_MEMBERS_CHANGED")
  eq(okEv8, true, "组208④★ 事件帧真的挂了 OnEvent（走真实脚本点火，不另造计时器）")
  eq(pf8:GetScale(), 0.6, "组208④★★★ 事件到达 ⇒ 存档参数**立刻生效**（缩放 1 → " .. tostring(pf8:GetScale()) .. "，不再静默不生效）")
  eq(pf8:GetWidth() == 120 and pf8:GetHeight() == 48, true,
    "组208④★★★ 同一轮里**宽高一个都没动**（" .. tostring(pf8:GetWidth()) .. "×" .. tostring(pf8:GetHeight()) ..
    "）—— 宽高已整体停用（用户第二次澄清）")
  local h8 = EVAL_DF_TEST_HANDLE("PartyMemberFrame1")
  eq(h8 ~= nil and h8:IsShown() == true, true, "组208④★★ 拖拽柄也补上了（目标在手、柄不出现 = 旧症状）")
  -- ★读数要**当场收下来**：后面 ⑥ 会把宽度改回 120 并关掉开关（柄随之隐藏），
  --   在最后那行 print 里现读会读到「已经变了的值」——那是打印口径的坑，不是断言失败。
  local wOn8, hOn8 = pf8:GetWidth(), pf8:GetHeight()
  local shown8 = (h8 ~= nil and h8:IsShown() == true)
  eq(EVAL_DF_TEST_STATE().rosterDone >= 1, true,
     "组208④★ 读值口如实记下「刚出现就恢复」的次数（" .. tostring(EVAL_DF_TEST_STATE().rosterDone) .. "）")

  -- ⑤ 跟随**有界**：事件之后只跟固定次数，跟完即停（不许变成常驻后台任务）
  local lim8 = EVAL_DF_TEST_ROSTER_LIMITS()
  eq(lim8.tries >= 2 and lim8.tries <= 10, true, "组208⑤ 跟随次数是**有限**值（实测 " .. tostring(lim8.tries) .. " 次）")
  local rf8 = EVAL_DF_TEST_ROSTER_FRAME()
  eq(rf8 ~= nil, true, "组208⑤★ 事件帧建出来了")
  local upd8 = nil
  if rf8 and type(rf8.GetScript) == "function" then upd8 = rf8:GetScript("OnUpdate") end
  eq(type(upd8) == "function", true, "组208⑤★ 真实 OnUpdate 挂着（跟随靠它推进）")
  eq(EVAL_DF_TEST_STATE().rosterLeft, lim8.tries, "组208⑤ 事件刚到达 = 跟满一轮次数（" .. tostring(EVAL_DF_TEST_STATE().rosterLeft) .. "）")
  if type(upd8) == "function" then
    for _ = 1, lim8.tries + 2 do pcall(upd8, lim8.period + 0.01) end
  end
  eq(EVAL_DF_TEST_STATE().rosterLeft, 0, "组208⑤★★★ 跟满次数后自动归零（有界，不是常驻轮询）")
  local doneBefore8 = EVAL_DF_TEST_STATE().rosterDone
  if type(upd8) == "function" then
    for _ = 1, 3 do pcall(upd8, lim8.period + 0.01) end
  end
  eq(EVAL_DF_TEST_STATE().rosterDone, doneBefore8, "组208⑤★★ 归零后再点火也不结算（不会偷偷变回周期任务）")

  -- ⑥ 开关关掉 ⇒ 跟随立即清零，且事件再来也不动目标
  --   ★载体同样换成**缩放**：用宽高来验「不动目标」在停用宽高之后会变成**恒真的空断言**（弱判据）
  EVAL_DF_SET(false)
  eq(EVAL_DF_TEST_STATE().rosterLeft, 0, "组208⑥★★★ 开关关掉 ⇒ 跟随清零（关了还在跑 = 没人叫停的后台任务）")
  EVAL_DF_TEST_ROSTER_RESET()
  store8.PartyMemberFrame1 = { scale = 0.35 }
  pcall(pf8.SetScale, pf8, 1)
  EVAL_DF_TEST_ROSTER_EVENT("PARTY_MEMBERS_CHANGED")
  local scOff8 = pf8:GetScale()
  eq(scOff8, 1, "组208⑥★★★ 关着的时候事件到达也不动目标（生产 OnEvent 里过 DF.on 门，实测缩放 " .. tostring(scOff8) .. "）")

  -- ⑦ 探针：**先报组队状态**（单人时「候选全不在」是正常的，有队伍时才是帧名不对），并扫 party/raid 关键词
  TEST.partyN = 1
  TEST.chat = ""
  local n8, dump8 = EVAL_DF_PROBE_BARS()
  local chat8 = tostring(TEST.chat or "")
  eq(type(dump8) == "table" and dump8.partyMembers == 1, true,
     "组208⑦★★★ 探针把**当前队友数**落存档（" .. tostring(type(dump8) == "table" and dump8.partyMembers or "nil") .. "）")
  eq(string.find(chat8, "队友", 1, true) ~= nil, true, "组208⑦★★ 聊天里先报组队状态（否则缺帧结论无法解释）")
  eq(type(dump8) == "table" and type(dump8.groups) == "table" and type(dump8.groups.party) == "table", true,
     "组208⑦ 扫描结果按 bar/party/raid 分组")
  local gotPartyName8 = false
  for _, nm in ipairs((type(dump8) == "table" and dump8.groups and dump8.groups.party) or {}) do
    if nm == "PartyMemberFrame1" then gotPartyName8 = true end
  end
  eq(gotPartyName8, true, "组208⑦★ 全 _G 扫到了**队伍帧的真实名字**（PartyMemberFrame1）")
  eq(n8 >= 1, true, "组208⑦ 探针返回扫描条数（实测 " .. tostring(n8) .. "）")

  -- ⑧ 事件名单的反向哨兵：只许有本地证据的（Toolbox.lua 真机在跑的），不许拿「探测名单」当注册依据
  local evs8 = lim8.evs
  local function hasEv8(k)
    for _, e in ipairs(evs8 or {}) do if e == k then return true end end
    return false
  end
  eq(hasEv8("PARTY_MEMBERS_CHANGED") and hasEv8("RAID_ROSTER_UPDATE"), true,
     "组208⑧★★ 注册了有本地证据的两个名单事件（Toolbox.lua 同款，真机在跑）")
  eq(hasEv8("GROUP_ROSTER_UPDATE"), false,
     "组208⑧★★★ 反向哨兵：不注册 GROUP_ROSTER_UPDATE —— 它只出现在子插件的**事件探测名单**里，没有生产证据（铁律 5④）")

  -- 收尾：存档、夹具、解析缓存、组队状态全部还原（不给后面的组留脏状态）
  store8 = EVAL_DF_TEST_STORE()
  if store8 then
    store8.PartyFrame = savedPf8
    store8.RaidFrame = savedRf8
  end
  TEST.chat = ""
  EVAL_DF_SET(wasOn8)
  TEST.partyN, TEST.raidN = savedPN8, savedRN8
  EVAL_DF_TEST_ROSTER_RESET()
  _G["PartyMemberFrame1"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  框拖拽队伍/团队层：目标表 %d 项（其中 roster 2）· 没组队时如实缺席 %s · 候选命中 %s（存档键 %s）· " ..
    "事件到达 ⇒ 宽 %s · 高 %s + 柄补上 %s · 有界 %d 次后归零 %s · 关掉后事件不动目标（宽 %s）· 探针报队友数 %s 并扫到真名 %s",
    table.getn(raw8), tostring(clean8), tostring(hitParty8 and hitParty8.resolved), tostring(hitParty8 and hitParty8.name),
    tostring(wOn8), tostring(hOn8), tostring(shown8),
    lim8.tries, tostring(EVAL_DF_TEST_STATE().rosterLeft == 0), tostring(wOff8),
    tostring(type(dump8) == "table" and dump8.partyMembers), tostring(gotPartyName8)))
  print("GROUP 208 (框拖拽队伍层/团队层：候选名解析 + 按需出现的事件跟随): PASS")
end

-- ===== 组 209（1.74.32）：框体探针扩「被动打开层」= **只读取证**（第 1 步，行为零变化）=====
-- 用户要求：「其他比如公会,属性,拍卖,邮箱,任务,技能树等被动打开层，在其标题增加配置 UI 属性的图标开关，
--   默认支持拖拽」。用户确认的四条：① 点图标 = 开属性弹窗 ② 拖图标 = 拖窗口（默认开）
--   ③ 目标是**窗口整体** ④ **分两步：先只读取证拿真名，再实现图标**。
-- ★为什么本组这么写：第 1 步只许「取证能力」增加，**不许改任何现有行为** —— 所以本组同时钉两件事：
--   ① 探针真的能取证（候选逐个报在不在 + 关键词分组扫 + **顶层大帧兜底** + 落存档）；
--   ② 行为真的没变（`DF_TARGETS` 仍是 12 项、被动层候选**一个都没接进去**）—— 后者是**临时哨兵**，
--      第 2 步实现图标时应当一起改掉（`DF BARS WIRING CHECK` 里有注释提醒）。
do
  local store9 = EVAL_DF_TEST_STORE()
  local wasOn9 = EVAL_DF_ENABLED()
  local savedBars9 = store9 and store9.dragBars
  local savedPN9, savedRN9 = TEST.partyN, TEST.raidN
  local savedChat9 = TEST.chat
  EVAL_DF_TEST_TARGETS_RESET()

  -- ① ★第 1 步的临时哨兵**已按计划撤除**（第 2 步正是要把探到的真名接进目标表）⇒ 改成**反向**断言：
  --   探针实测到的真名必须**确实接进去了**，而且都走图标形态（`icon = true`，不是整条透明柄）。
  local raw9 = EVAL_DF_TEST_TARGETS_RAW()
  eq(table.getn(raw9) >= 30, true,
     "组209①★★★ 目标表已扩到 ≥30 项（第 2 步接入被动窗口；实测 " .. tostring(table.getn(raw9)) .. "）")
  local wins9 = (EVAL_DF_TEST_WIN_CANDS and EVAL_DF_TEST_WIN_CANDS()) or {}
  -- ★只断言**探针已确认存在**的那些真名（拍卖/训练师真名未知，尚未接入 —— 它们不加进这条断言）
  local needIcon9 = { "GuildFrame", "CharacterFrame", "MailFrame", "QuestLogFrame", "SpellBookFrame",
    "TradeFrame", "MerchantFrame", "FriendsFrame", "BankFrame" }
  local missing9 = {}
  for _, nm in ipairs(needIcon9) do
    local hit = false
    for _, t in ipairs(raw9) do if t.name == nm and t.icon == true then hit = true end end
    if not hit then table.insert(missing9, nm) end
  end
  eq(table.getn(missing9), 0, "组209①★★★ 探针实测的真名都接进目标表且带 `icon = true`（缺：" ..
    table.concat(missing9, ",") .. "）")
  local iconN9 = 0
  for _, t in ipairs(EVAL_DF_TARGETS()) do if t.icon then iconN9 = iconN9 + 1 end end
  eq(iconN9 >= 20, true, "组209①★ 读值口如实交出 icon 标记（实测 " .. tostring(iconN9) .. " 项）")

  -- ② 候选清单本身：10 组、每组有 label 与非空候选表
  eq(table.getn(wins9), 10, "组209② 被动层候选清单 10 组（公会/属性/拍卖/邮箱/任务/技能树 + 训练师/交易技能/商人/好友），实测 " .. tostring(table.getn(wins9)))
  local wantLabels9 = { "公会", "属性", "拍卖", "邮箱", "任务", "技能树" }
  local gotLabel9 = {}
  for _, w in ipairs(wins9) do gotLabel9[w.label] = true end
  local missLabel9 = {}
  for _, lb in ipairs(wantLabels9) do if not gotLabel9[lb] then table.insert(missLabel9, lb) end end
  eq(table.getn(missLabel9), 0, "组209②★ 用户点名的 6 类都在（缺：" .. table.concat(missLabel9, ",") .. "）")
  local badC9 = 0
  for _, w in ipairs(wins9) do
    if type(w.group) ~= "string" or type(w.label) ~= "string" or type(w.cands) ~= "table" or table.getn(w.cands) < 3 then
      badC9 = badC9 + 1
    end
  end
  eq(badC9, 0, "组209②★ 每组都有 group/label 且候选 ≥3（本客户端真名未知，不许只写一个）：异常 " .. tostring(badC9) .. " 组")

  -- ③ 候选逐个探：造一个 GuildFrame 桩 ⇒ 「公会」命中它；并且**不许**把桩变成拖拽目标
  local gf9 = CreateFrame("Frame", "GuildFrame", UIParent)
  gf9:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -120)
  gf9:SetWidth(512) gf9:SetHeight(400)
  gf9:Hide()
  local cf9 = CreateFrame("Frame", "CharacterFrame", UIParent)
  cf9:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 80, -160)
  cf9:SetWidth(400) cf9:SetHeight(520)
  cf9:Hide()
  EVAL_DF_TEST_TARGETS_RESET()
  TEST.partyN, TEST.raidN = 0, 0
  TEST.chat = ""
  local n9, dump9 = EVAL_DF_PROBE_BARS()
  local chat9 = tostring(TEST.chat or "")
  local hitG9, hitC9 = nil, nil
  for _, r in ipairs((type(dump9) == "table" and dump9.cands) or {}) do
    if r.label == "公会" then hitG9 = r end
    if r.label == "属性" then hitC9 = r end
  end
  eq(hitG9 ~= nil and hitG9.hit == "GuildFrame", true,
     "组209③★★ 候选逐探：公会命中了桩里的 GuildFrame（实测 " .. tostring(hitG9 and hitG9.hit) .. "）")
  eq(hitC9 ~= nil and hitC9.hit == "CharacterFrame", true,
     "组209③★★ 属性命中了桩里的 CharacterFrame（实测 " .. tostring(hitC9 and hitC9.hit) .. "）")
  eq(string.find(chat9, "被动打开层候选", 1, true) ~= nil, true, "组209③★ 聊天里打出了被动层候选那一节")
  -- ★1.74.32 第 2 步后反向：命中之后它们**就是**拖拽目标了（第 1 步的哨兵已撤除），且走**图标形态**
  local asIcon9 = 0
  for _, t in ipairs(EVAL_DF_TARGETS()) do
    if t.frame == gf9 or t.frame == cf9 then
      if t.icon then asIcon9 = asIcon9 + 1 end
    end
  end
  eq(asIcon9 == 2, true, "组209③★★★ 探到的窗口已是目标、且走图标形态（不是整条透明柄）：命中 " ..
    tostring(asIcon9) .. " / 2")

  -- ④ 关键词分组扫描：新组名要在 groups 里有位置，且能扫到对应名字的帧
  local g9 = (type(dump9) == "table" and dump9.groups) or {}
  local missGroup9 = 0
  for _, gn in ipairs({ "guild", "char", "auction", "mail", "quest", "spell", "trainer", "trade", "merchant", "friend" }) do
    if type(g9[gn]) ~= "table" then missGroup9 = missGroup9 + 1 end
  end
  eq(missGroup9, 0, "组209④ groups 里 10 个新分组都有位置（缺一个 ⇒ 该组结果静默丢掉）")
  local function inGroup9(gn, nm)
    for _, x in ipairs(g9[gn] or {}) do if x == nm then return true end end
    return false
  end
  eq(inGroup9("guild", "GuildFrame"), true, "组209④★ GuildFrame 被归到 guild 组（不是靠候选表，是靠关键词扫描）")
  eq(inGroup9("char", "CharacterFrame"), true, "组209④★ CharacterFrame 被归到 char 组")
  eq(string.find(chat9, "分组命中：", 1, true) ~= nil, true, "组209④★ 聊天里打出分组命中统计行")

  -- ⑤ 顶层大帧兜底：父级 UIParent/WorldFrame 且 ≥200×150 → 必须进 top（含宽高/父级/层级）
  local top9, topHit9 = (type(dump9) == "table" and dump9.top) or {}, nil
  for _, t in ipairs(top9) do if t.name == "CharacterFrame" then topHit9 = t end end
  eq(topHit9 ~= nil, true, "组209⑤★★★ 顶层大帧兜底扫到了 CharacterFrame（关键词扫不到时靠它捞真名）")
  eq(topHit9 ~= nil and topHit9.w == 400 and topHit9.h == 520, true,
     "组209⑤★ 兜底条目带真实宽高（画图标要用的几何）：" ..
     tostring(topHit9 and (tostring(topHit9.w) .. "x" .. tostring(topHit9.h))))
  -- ★★★判据锚在 `host`（父级**对象身份**）而不是 `parent`（父级**名字**）：
  --   桩里 UIParent 是匿名帧（GetName 返回 nil）⇒ 按名字判会一条都匹配不上（本轮实测踩到）；
  --   真机两者都成立，但按身份判更稳 —— 这条断言就是那次踩坑的哨兵。
  eq(topHit9 ~= nil and topHit9.host == "UIParent", true,
     "组209⑤★★★ 宿主按**对象身份**判（host = " .. tostring(topHit9 and topHit9.host) .. "，不是按父级名字）")
  eq(topHit9 ~= nil and type(topHit9.parent) == "string", true,
     "组209⑤★ 父级名字字段仍然存在且是字符串（真机上读得出，读不到如实写 「?」）：" .. tostring(topHit9 and topHit9.parent))
  eq(topHit9 ~= nil and type(topHit9.level) == "string", true,
     "组209⑤★ 带 frame level（判断图标会不会被盖住）：" .. tostring(topHit9 and topHit9.level))
  eq(topHit9 ~= nil and topHit9.shown == false, true, "组209⑤★ 隐藏状态如实记录（窗口没开时不该假装在显示）")
  -- ★反向哨兵：小帧不该混进兜底清单（阈值真的在生效）
  local small9 = CreateFrame("Frame", "EHSmallWin9", UIParent)
  small9:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0) small9:SetWidth(120) small9:SetHeight(90)
  TEST.chat = ""
  local _, dump9b = EVAL_DF_PROBE_BARS()
  local smallInTop9 = false
  for _, t in ipairs((type(dump9b) == "table" and dump9b.top) or {}) do if t.name == "EHSmallWin9" then smallInTop9 = true end end
  eq(smallInTop9, false, "组209⑤★★ 反向哨兵：120×90 的小帧**不许**混进兜底清单（阈值 ≥200×150 真的在生效）")

  -- ⑥ 落存档：cands / groups / top / found 四件齐全，且 found 里带几何（AI 只读存档就能定名）
  local cfg9 = rawget(_G, "EVAL_HELP_CONFIG")
  eq(type(cfg9) == "table" and type(cfg9.dragBars) == "table", true, "组209⑥ 探针结果仍落存档 dragBars")
  local d9 = (type(cfg9) == "table" and cfg9.dragBars) or {}
  eq(type(d9.cands) == "table" and table.getn(d9.cands) == 10, true,
     "组209⑥★ 落档 cands（被动层候选逐条结果）条数 " .. tostring(type(d9.cands) == "table" and table.getn(d9.cands) or -1))
  eq(type(d9.groups) == "table" and type(d9.groups.guild) == "table", true, "组209⑥★ 落档 groups 含新分组")
  eq(type(d9.top) == "table" and table.getn(d9.top) >= 1, true,
     "组209⑥★★ 落档 top（顶层大帧兜底）条数 " .. tostring(type(d9.top) == "table" and table.getn(d9.top) or -1))
  local foundHasGeom9 = false
  for _, r in ipairs(d9.found or {}) do
    if r.name == "GuildFrame" and r.w == 512 and r.h == 400 and type(r.level) == "string" then foundHasGeom9 = true end
  end
  eq(foundHasGeom9, true, "组209⑥★ found 里的条目带宽高与层级（GuildFrame 512x400）")

  -- 收尾：夹具、存档、组队状态、开关全部还原
  _G["GuildFrame"] = nil
  _G["CharacterFrame"] = nil
  _G["EHSmallWin9"] = nil
  cfg9 = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg9) == "table" then cfg9.dragBars = savedBars9 end
  TEST.partyN, TEST.raidN = savedPN9, savedRN9
  TEST.chat = savedChat9
  EVAL_DF_SET(wasOn9)
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  框体探针被动打开层（第 1 步只读取证）：目标表 %d 项（探到的真名已接入且带 icon 的 %d 个）· 候选 %d 组（点名 6 类齐 %s）· " ..
    "GuildFrame/CharacterFrame 命中 %s/%s · 分组命中 guild/char %s/%s · 顶层大帧兜底 %d 条（CharacterFrame %sx%s 宿主=%s lv=%s）· " ..
    "小帧混入 %s · 落档 cands %d / top %d · found 带几何 %s · 关键词总命中 %d",
    table.getn(raw9), iconN9, table.getn(wins9), tostring(table.getn(missLabel9) == 0),
    tostring(hitG9 and hitG9.hit), tostring(hitC9 and hitC9.hit),
    tostring(inGroup9("guild", "GuildFrame")), tostring(inGroup9("char", "CharacterFrame")),
    table.getn(top9), tostring(topHit9 and topHit9.w), tostring(topHit9 and topHit9.h),
    tostring(topHit9 and topHit9.host), tostring(topHit9 and topHit9.level),
    tostring(smallInTop9), table.getn(d9.cands or {}), table.getn(d9.top or {}),
    tostring(foundHasGeom9), n9))
  print("GROUP 209 (框体探针：被动层候选逐探/分组扫描/顶层大帧兜底/落档 + 真名已接入图标形态): PASS")
end

-- ===== 组 210（1.74.32）：框体探针的**安全入口** = 取证命令绝不许静默 =====
-- 真机踩到的事实（本轮）：用户跑了 `/edb bars`，结果存档里**连 dragBars 键都没有** —— 因为子插件那句
--   `pcall(EVAL_DF_PROBE_BARS)` 把内部错误**吞掉**了 ⇒ 既看不到报错、也没有任何痕迹，
--   无法区分「命令压根没跑」与「跑了一半死了」（本项目最恨的静默失败族）。
-- ★本组钉住三条契约（缺一条，下次真机又会卡在同一个地方）：
--   ① 探针**一进来就写阶段标记**（start）⇒ 半路死掉也留痕；
--   ② 跑完写 phase="done" 的完整结果；
--   ③ 安全入口 `EVAL_DF_PROBE_SAFE()`：失败时把**错误原文**播报出来**并**写进存档（phase="error"）。
do
  local store10 = EVAL_DF_TEST_STORE()
  local wasOn10 = EVAL_DF_ENABLED()
  local savedBars10 = store10 and store10.dragBars
  local savedPN10, savedRN10 = TEST.partyN, TEST.raidN
  local savedChat10 = TEST.chat
  local cfg10 = rawget(_G, "EVAL_HELP_CONFIG")

  -- ① 阶段标记：单独调用也得落档（这是「半路死掉」的唯一证据）
  if type(cfg10) == "table" then cfg10.dragBars = nil end
  local okMark10 = (type(EVAL_DF_PROBE_MARK) == "function") and EVAL_DF_PROBE_MARK("start")
  eq(okMark10 == true, true, "组210① 有阶段标记口 EVAL_DF_PROBE_MARK 且写成功")
  eq(type(cfg10.dragBars) == "table" and cfg10.dragBars.phase == "start", true,
     "组210①★★★ 标记写进存档（phase=" .. tostring(type(cfg10.dragBars) == "table" and cfg10.dragBars.phase) .. "）")

  -- ② 真跑一次：完整结果 + phase="done"（start 标记会被最终结果覆盖）
  TEST.partyN, TEST.raidN = 0, 0
  TEST.chat = ""
  local ok10 = EVAL_DF_PROBE_SAFE()
  local d10 = (type(cfg10) == "table" and cfg10.dragBars) or {}
  eq(ok10 == true, true, "组210② 安全入口在正常路径下返回 true")
  eq(d10.phase == "done", true, "组210②★★★ 跑完写 phase=\"done\"（实测 " .. tostring(d10.phase) .. "）")
  eq(d10.err == nil, true, "组210②★ 成功路径**不留**错误痕迹（err 必须 nil，实测 " .. tostring(d10.err) .. "）")
  eq(type(d10.cands) == "table" and table.getn(d10.cands) == 10, true,
     "组210②★ 完整结果还在（cands " .. tostring(type(d10.cands) == "table" and table.getn(d10.cands) or -1) .. " 组）")

  -- ③ ★核心契约：探针内部抛错时，错误必须**既上屏又落档**（绝不许静默）
  local realProbe10 = EVAL_DF_PROBE_BARS
  EVAL_DF_PROBE_BARS = function() error("干探针模拟错误 EH_PROBE_BOOM") end
  TEST.chat = ""
  local okBad10, errBad10 = EVAL_DF_PROBE_SAFE()
  local dBad10 = (type(cfg10) == "table" and cfg10.dragBars) or {}
  local chatBad10 = tostring(TEST.chat or "")
  eq(okBad10 == false, true, "组210③★★★ 探针抛错时安全入口返回 false（而不是把错误吞掉）")
  eq(type(errBad10) == "string" and string.find(errBad10, "EH_PROBE_BOOM", 1, true) ~= nil, true,
     "组210③★★★ 错误原文被交回调用方：" .. tostring(errBad10))
  eq(dBad10.phase == "error", true, "组210③★★★ 错误阶段也落档（phase=" .. tostring(dBad10.phase) .. "）")
  eq(type(dBad10.err) == "string" and string.find(dBad10.err, "EH_PROBE_BOOM", 1, true) ~= nil, true,
     "组210③★★★ 存档里带错误原文（AI 只读存档就能定位，不必让用户抄聊天框）：" .. tostring(dBad10.err))
  eq(string.find(chatBad10, "框体探针出错", 1, true) ~= nil, true,
     "组210③★★ 出错时聊天框**有话说**（不再是「点了没反应」）")
  EVAL_DF_PROBE_BARS = realProbe10

  -- ④ 收尾 + 还原
  if type(cfg10) == "table" then cfg10.dragBars = savedBars10 end
  TEST.partyN, TEST.raidN = savedPN10, savedRN10
  TEST.chat = savedChat10
  EVAL_DF_SET(wasOn10)
  eq(type(realProbe10) == "function", true, "组210④ 探针本体已还原（测试不许留脏全局）")

  print(string.format("  框体探针安全入口：阶段标记 %s（phase=start）· 正常路径 ok=%s / phase=%s / err=%s / cands %d 组 · " ..
    "失败路径 ok=%s（phase=%s，存档含错误原文 %s，聊天框有话说 %s）",
    tostring(okMark10), tostring(ok10), tostring(d10.phase), tostring(d10.err),
    type(d10.cands) == "table" and table.getn(d10.cands) or -1,
    tostring(okBad10), tostring(dBad10.phase), tostring(dBad10.err ~= nil),
    tostring(string.find(chatBad10, "框体探针出错", 1, true) ~= nil)))
  print("GROUP 210 (框体探针安全入口：阶段标记/错误上屏并落档 —— 取证命令绝不静默): PASS")
end

-- ===== 组 211（1.74.32）：全 _G 扫描的**安全守卫**（真机 bug：索引到不可索引的 userdata）=====
-- 真机原样报错（用户截图）：`DragFrames.lua:2003: attempt to index local 'f' (a userdata value)`
--   ⇒ `_G` 里有些全局是「不可索引的 userdata」，一句 `f.GetParent` 就把整个探针打断。
-- ★★诚实边界：这个 bug 在**测试环境里造不出来** —— fengari 没有 `newproxy`，而 `io.stdout` 那种 userdata
--   是**可索引**的（实测：number/boolean/function 索引才报错，但它们过不了 `dfFrameOf` 的类型门，
--   所以走不到那一步）。⇒ 能测的（守卫判定语义）在这里测，**测不到的部分交给源码检查**
--   `DF GLOBAL SCAN GUARD CHECK` 兜底（这正是本项目「行为断言照不到 → 源码检查补位」那条纪律）。
do
  local fu11 = EVAL_DF_TEST_FRAME_USABLE
  eq(type(fu11) == "function", true, "组211① 有守卫读值口 EVAL_DF_TEST_FRAME_USABLE")
  -- ① 表（含测试桩 / 真机里 type(frame)=="table" 的那种）→ 可用
  eq(fu11({}) == true, true, "组211①★★ 普通表 = 可用（stub 帧与部分真机帧都是表）")
  -- ② 非表非 userdata → **一律不可用**（number/boolean/function/string 这些全局不是帧）
  eq(fu11(5) == false, true, "组211②★ number 不可用")
  eq(fu11(true) == false, true, "组211②★ boolean 不可用")
  eq(fu11("字符串") == false, true, "组211②★ string 不可用（字符串索引不报错，但它不是帧）")
  eq(fu11(function() end) == false, true, "组211②★ function 不可用（真机命令会被同名全局函数顶掉，那也不是帧）")
  eq(fu11(nil) == false, true, "组211② nil 不可用")
  -- ③ userdata：**必须靠 pcall 探测**才敢下结论（真机就是在这里栽的）
  local ud11 = io and io.stdout or nil
  if ud11 ~= nil and type(ud11) == "userdata" then
    eq(fu11(ud11) == false, true,
       "组211③★★ userdata 且 `GetParent` 不是函数（io.stdout）⇒ 判为不可用（真机正是这类对象把探针打断的）")
  else
    eq(true, true, "组211③（本环境拿不到 userdata 样本，跳过该条 —— 由源码检查兜底）")
  end
  -- ④ 对象类型口：拿不到就返回 nil（调用方不许据此丢弃 —— 「查不到 ≠ 没有」）
  eq(EVAL_DF_TEST_OBJECT_TYPE(nil) == nil, true, "组211④ 对象类型口对 nil 返回 nil（而不是编一个类型）")
  eq(EVAL_DF_TEST_OBJECT_TYPE(ud11) == nil or type(EVAL_DF_TEST_OBJECT_TYPE(ud11)) == "string", true,
     "组211④ 对象类型口只会给字符串或 nil（实测 " .. tostring(EVAL_DF_TEST_OBJECT_TYPE(ud11)) .. "）")

  print(string.format("  全 _G 扫描守卫：表=%s · number=%s · boolean=%s · string=%s · function=%s · " ..
    "userdata(io.stdout)=%s ⇒ 判不出类型时**不丢弃**（源码检查 DF GLOBAL SCAN GUARD CHECK 兜底）",
    tostring(fu11({})), tostring(fu11(5)), tostring(fu11(true)), tostring(fu11("s")),
    tostring(fu11(function() end)), tostring(ud11 ~= nil and fu11(ud11) or "n/a")))
  print("GROUP 211 (全 _G 扫描安全守卫：不可索引对象必须被挡在索引之前): PASS")
end

-- ===== 组 212（1.74.32 第 2 步）：被动窗口的**图标形态** =====
-- 用户确认的四条：① 点图标 = 开该层属性弹窗 ② 拖图标 = 拖窗口 ③ 图标**默认开** ④ 目标是窗口整体。
-- ★本组钉住「图标形态」与「整条透明柄」的**行为分界**（这是本步最容易做错的地方）：
--   · 图标**挂在目标窗口下**（父子可见性传播 ⇒ 随窗口开关，不需要轮询）；
--   · 图标目标的**层级 = 目标 level + 10**（真机实测：窗口关闭 lv=1、打开着的 CharacterFrame lv=8）；
--   · 图标目标**不贴整条透明柄**（384 宽的透明条会把整个窗口标题栏的点击吃掉）；
--   · 「点」与「拖」的分界：`st.moved`（拖拽机制自己算的阈值，唯一真值）。
do
  local store212 = EVAL_DF_TEST_STORE()
  local savedIcons212 = store212 and store212.iconsOn
  local savedBars212 = store212 and store212.dragBars
  local wasOn212 = EVAL_DF_ENABLED()
  local savedCursor212 = { TEST.cursorX, TEST.cursorY }
  local savedChat212 = TEST.chat
  -- ★★★1.74.33 用户要求「窗口的拖拽使用图标 346 号宏图标」⇒ 桩里的宏图标表**必须先备好 346 号**，
  --   否则图标会走「取不到 ⇒ 退回文字」那条路，本组前半段的「画法」断言就测不到真路径。
  --   （实测素材用 doc/图标路径清单.txt 的**真实形态**：346 号 = /Game/Interface/Icons/INV_Misc_Fish_20_TEX）
  local savedMacro212 = TEST.macroIcons
  local macroArr212 = {}
  for i = 1, 400 do macroArr212[i] = "INV_Misc_Fish_20" end
  TEST.macroIcons = macroArr212

  -- ① 目标表：被动窗口都带 icon，且读值口如实交出
  local raw212 = EVAL_DF_TEST_TARGETS_RAW()
  local iconRaw212 = 0
  for _, t in ipairs(raw212) do if t.icon then iconRaw212 = iconRaw212 + 1 end end
  eq(iconRaw212 >= 20, true, "组212①★★ DF_TARGETS 里 ≥20 个图标形态目标（实测 " .. tostring(iconRaw212) .. "）")
  local gTgt212 = nil
  for _, t in ipairs(raw212) do if t.name == "GuildFrame" then gTgt212 = t end end
  eq(gTgt212 ~= nil and gTgt212.icon == true, true, "组212①★★ 「公会」是图标形态目标")
  local readIcon212 = 0
  for _, t in ipairs(EVAL_DF_TARGETS()) do if t.icon then readIcon212 = readIcon212 + 1 end end
  eq(readIcon212 == iconRaw212, true, "组212①★ 读值口 EVAL_DF_TARGETS() 的 icon 数与原表一致（" ..
    tostring(readIcon212) .. "/" .. tostring(iconRaw212) .. "）")

  -- ② 默认开：存档里没有 iconsOn 时也当「开」
  if type(store212) == "table" then store212.iconsOn = nil end
  eq(EVAL_DF_ICONS_ENABLED() == true, true, "组212②★★★ 图标**默认开**（存档里没这一项也算开 —— 用户明确要的默认值）")

  -- ③ 在位窗口挂上图标，且**父级就是目标窗口**（父子可见性传播的契约）
  local gf212 = CreateFrame("Frame", "GuildFrame", UIParent)
  gf212:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -60)
  gf212:SetWidth(384) gf212:SetHeight(512)
  gf212:Show()
  EVAL_DF_SET(true) -- 主开关开着，用来验「图标目标不贴整条柄」
  TEST.chat = ""
  local iconBtn212 = EVAL_DF_TEST_ICON("GuildFrame")
  eq(iconBtn212 ~= nil, true, "组212③★★★ 公会窗口在位 ⇒ 图标建出来了（读值口给的是真实控件）")
  eq(iconBtn212 ~= nil and iconBtn212:GetParent() == gf212, true,
     "组212③★★★ 图标**父级 = 目标窗口**（父子可见性传播 ⇒ 随窗口开/关，不用轮询）")
  -- ④ 层级 = 目标 level + 10（现读现抬：窗口打开着的 level 会变）
  local gLvl212, iLvl212 = gf212:GetFrameLevel(), iconBtn212 and iconBtn212:GetFrameLevel()
  eq(iconBtn212 ~= nil and iLvl212 == gLvl212 + 10, true,
     "组212④★★★ 图标层级 = 目标 level + 10（实测 " .. tostring(gLvl212) .. " → " .. tostring(iLvl212) .. "）")
  -- ⑤ 位置：锚在目标右上角内侧（避开原生关闭按钮）
  --   ★★两个坑都在这里踩过：
  --     ① 锚点的「相对目标」在本客户端**可能是名字字符串而不是帧对象**（项目里 `dfRelName` 就是为这事抽的）⇒ 两者都认；
  --     ② **绝不能写 `btn and btn:GetPoint(1)`** —— `and` 表达式**只保留第一个返回值**，
  --        后面几个全变 nil ⇒ 断言读到 nil 还以为锚点没设上（本轮实测就是这么误报的）。
  local p212, relTo212 = nil, nil
  if iconBtn212 then p212, relTo212 = iconBtn212:GetPoint(1) end
  local relOk212 = (relTo212 == gf212) or (relTo212 == "GuildFrame") or (relTo212 == "UIParent")
  eq(p212 == "TOPRIGHT" and relOk212, true,
     "组212⑤★★ 图标锚在窗口右上角（" .. tostring(p212) .. " → " .. tostring(relTo212) .. "）")
  -- ⑤b ★★★真机截图事故（1.74.33）：图标右边距太小 ⇒ 压住了窗口**自带的关闭按钮**（用户截图：法术书）。
  --   这里钉的是**性质**而不是那个数字：图标右边缘离窗口右边界至少 40px（关闭按钮连同点击区的带宽），
  --   否则「配」和关闭按钮叠在一起 —— 关闭按钮被压住就点不了，`pcall` 全程不报错、断言也全绿。
  -- ★★别写 `local _,_,_,x = btn and btn:GetPoint(1)`：`and` 表达式**只保留第一个返回值** ⇒ 读到 nil
  --   （与上面 ⑤ 那条注释里记的是同一个坑，本行第一版又踩了一次）。
  local xOff212 = nil
  if iconBtn212 then
    local _p, _r, _rp, xv = iconBtn212:GetPoint(1)
    xOff212 = xv
  end
  eq(type(xOff212) == "number" and xOff212 <= -40, true,
     "组212⑤b★★★ 图标右边距 ≥40px（实测 " .. tostring(xOff212) ..
     "：真机截图里 34 正好压住关闭按钮 ⇒ 必须给关闭按钮留出整条带宽）")
  -- ⑤c ★★★真机截图事故 2（1.74.33 用户：「窗口的属性打开图标可以再往下移动12像素」，截图 = 好友名单窗口）：
  --   图标**纵向**贴得太后 ⇒ 骑在窗口的上边框上（一半在标题栏外），看着像「挂」在窗口沿上。
  --   这里同样钉**性质**（上边距 ≥12：图标整个落在标题栏里面），不钉死 18 那个数字 ——
  --   每个窗口标题栏的实际带宽不同，要按截图微调时只改 `DF_ICON_TOP` 一处即可。
  local yOff212 = nil
  if iconBtn212 then
    local _p2, _r2, _rp2, _x2, yv = iconBtn212:GetPoint(1)
    yOff212 = yv
  end
  eq(type(yOff212) == "number" and yOff212 <= -12, true,
     "组212⑤c★★★ 图标上边距 ≥12px（实测 " .. tostring(yOff212) ..
     "：截图里图标骑在窗口上边框上 ⇒ 必须整块落进标题栏，不能压着边框）")
  -- ⑥ 图标目标**不贴整条透明柄**（否则整个标题栏点击被吃）
  eq(EVAL_DF_TEST_HANDLE("GuildFrame") == nil, true,
     "组212⑥★★★ 图标目标没有整条透明柄（主开关开着也不给它们贴柄）")

  -- ⑦ 「左键 = 只拖窗口，**不弹**属性窗」+「右键 = 开属性窗」（用户 1.74.33 改口径：
  --   「窗口的拖拽使用图标346 号宏图标,左键不要触发弹窗效果」）
  --   ★★顺序有讲究：**先验右键那条路**（弹窗真能打开），再验左键不弹 ——
  --     否则「没弹窗」可能只是因为弹窗**从来没被建出来过**，那是个空洞的真（本项目「桩默认值也属桩」同族坑）。
  local down212 = iconBtn212 and iconBtn212:GetScript("OnMouseDown")
  local up212 = iconBtn212 and iconBtn212:GetScript("OnMouseUp")
  eq(type(down212) == "function" and type(up212) == "function", true, "组212⑦前置：图标挂了真实 OnMouseDown/OnMouseUp")
  TEST.cursorX, TEST.cursorY = 200, -200
  if down212 then pcall(down212) end
  if up212 then pcall(up212, "RightButton") end
  local popR212 = EVAL_DF_TEST_STATE().popShown
  eq(popR212 == true, true, "组212⑦★★★ 右键图标 ⇒ 打开属性弹窗（左键不弹之后，属性配置的**唯一入口**）")
  local popCtl212 = EVAL_DF_TEST_POP()
  if popCtl212 and popCtl212.root then pcall(popCtl212.root.Hide, popCtl212.root) end
  eq(EVAL_DF_TEST_STATE().popShown == false, true, "组212⑦前置：把弹窗关掉，下面才验得出「左键不会弹」")
  -- 左键点一下（按下 → 没移动 → 松手 ⇒ 走真实脚本，不复制映射逻辑）
  TEST.cursorX, TEST.cursorY = 200, -200
  if down212 then pcall(down212) end
  if up212 then pcall(up212, "LeftButton") end
  local popL212 = EVAL_DF_TEST_STATE().popShown
  eq(popL212 == false, true, "组212⑦★★★ 左键单击图标（没移动）⇒ **不弹属性窗**（用户要求）")

  -- ⑧ 左键拖动：只拖窗口、落存档、**松手也不弹窗**
  --   ★顺序很重要：拖拽基准点是**按下那一刻**的光标位置（`dfDragBegin` 里读）
  --     ⇒ 必须先按下、再挪光标，否则位移恒 0、永远判不成「拖动」（本轮实测就是这么写错的）。
  local mv212 = iconBtn212 and iconBtn212:GetScript("OnUpdate")
  TEST.cursorX, TEST.cursorY = 200, -200   -- 按下时的位置
  if down212 then pcall(down212) end
  TEST.cursorX, TEST.cursorY = 260, -260   -- 然后移动 = 真拖动
  for _ = 1, 6 do if mv212 then pcall(mv212, 0.05) end end
  if up212 then pcall(up212, "LeftButton") end
  eq(EVAL_DF_TEST_STATE().dragging == false, true, "组212⑧ 拖拽已结束（松手即收）")
  local rec212 = (EVAL_DF_TEST_STORE() or {})["GuildFrame"]
  eq(type(rec212) == "table" and rec212.dx ~= nil, true,
     "组212⑧★★★ 拖图标真的**拖了窗口**并落存档（dx=" .. tostring(type(rec212) == "table" and rec212.dx) .. "）")
  eq(EVAL_DF_TEST_STATE().popShown == false, true,
     "组212⑧★★★ 左键拖动松手**也不弹**属性窗（左键整条路都不弹；整条柄的老行为不受影响）")

  -- ⑩ 图标画法 = **346 号宏图标**（取不到才如实退回文字「配」）
  local art212 = EVAL_DF_TEST_ICON_ART("GuildFrame")
  eq(type(art212) == "table" and art212.macro == 346, true,
     "组212⑩★★★ 图标画法用的是 **346 号宏图标**（macro=" .. tostring(type(art212) == "table" and art212.macro) .. "）")
  eq(type(art212) == "table" and type(art212.tex) == "string" and art212.hasTexObj == true, true,
     "组212⑩★★★ 图标真的挂上了宏图标纹理（" .. tostring(type(art212) == "table" and art212.tex) .. "）")
  eq(type(art212) == "table" and art212.label == nil, true,
     "组212⑩★★ 有纹理时**不画**「配」文字（两条画法只走一条，不许叠在一起）")
  -- 反向哨兵：宏图标接口不可用 ⇒ 退回文字（绝不静默变空白方块）；恢复后再切回纹理
  TEST.macroIcons = nil
  eq(EVAL_DF_TEST_MACRO_TEX(346) == nil, true, "组212⑩★★ 接口取不到时解析口如实回 nil（不编一个路径出来）")
  EVAL_DF_TEST_ICON_DROP("GuildFrame")
  EVAL_DF_ICONS_SET(true)
  local artOff212 = EVAL_DF_TEST_ICON_ART("GuildFrame")
  eq(type(artOff212) == "table" and artOff212.tex == nil and artOff212.label == "配", true,
     "组212⑩★★★ 取不到宏图标 ⇒ **如实退回文字「配」**（" .. tostring(type(artOff212) == "table" and artOff212.label) .. "）")
  -- ★接口「回来」= 把同一份桩数据装回（**不是**还原开场那份：开场那份可能是 nil ⇒ 会误判成「没纹理」）
  TEST.macroIcons = macroArr212
  EVAL_DF_TEST_ICON_DROP("GuildFrame")
  EVAL_DF_ICONS_SET(true)
  local artBack212 = EVAL_DF_TEST_ICON_ART("GuildFrame")
  eq(type(artBack212) == "table" and type(artBack212.tex) == "string", true,
     "组212⑩★★ 接口回来后重新建的图标又用纹理（两条路都可逆，实测 " ..
     tostring(type(artBack212) == "table" and artBack212.tex) .. "）")

  -- ⑨ 开关：关掉 → 图标隐藏；再打开 → 回来（幂等，不重复建）
  local cnt212 = EVAL_DF_TEST_ICON_COUNT()
  EVAL_DF_ICONS_SET(false)
  eq(EVAL_DF_TEST_ICONS_SHOWN and EVAL_DF_TEST_ICONS_SHOWN() == 0 or true, true, "组212⑨ 关掉开关不报错")
  local btnAfter212 = EVAL_DF_TEST_ICON("GuildFrame")
  eq(btnAfter212 ~= nil and btnAfter212:IsShown() == false, true, "组212⑨★★ 关掉开关 ⇒ 图标隐藏（不是销毁）")
  EVAL_DF_ICONS_SET(true)
  eq(EVAL_DF_TEST_ICON("GuildFrame") ~= nil and EVAL_DF_TEST_ICON("GuildFrame"):IsShown() == true, true,
     "组212⑨★★ 再打开 ⇒ 图标回来")
  eq(EVAL_DF_TEST_ICON_COUNT() == cnt212, true,
     "组212⑨★ 开关来回不重复建图标（缓存按目标名，实测 " .. tostring(EVAL_DF_TEST_ICON_COUNT()) .. " vs " .. tostring(cnt212) .. "）")

  -- 收尾
  _G["GuildFrame"] = nil
  if type(store212) == "table" then
    store212.iconsOn = savedIcons212
    store212.dragBars = savedBars212
    store212["GuildFrame"] = nil
  end
  TEST.macroIcons = savedMacro212
  TEST.cursorX, TEST.cursorY = savedCursor212[1], savedCursor212[2]
  TEST.chat = savedChat212
  EVAL_DF_SET(wasOn212)
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  被动窗口图标形态：图标目标 %d 个（读值口一致 %d）· 默认开 %s · 父级=窗口 %s · 层级 +10（%s→%s）· " ..
    "锚 %s · 无整条柄 %s · 画法=346 号宏图标 %s（叠文字 %s，取不到退回文字 %s）· " ..
    "左键单击不弹 %s / 左键拖动只拖窗口 %s（dx=%s）· 右键开属性窗 %s",
    iconRaw212, readIcon212, tostring(EVAL_DF_ICONS_ENABLED()),
    tostring(iconBtn212 ~= nil and iconBtn212:GetParent() == gf212), tostring(gLvl212), tostring(iLvl212),
    tostring(p212), tostring(EVAL_DF_TEST_HANDLE("GuildFrame") == nil),
    tostring(type(art212) == "table" and type(art212.tex) == "string"),
    tostring(type(art212) == "table" and art212.label ~= nil),
    tostring(type(artOff212) == "table" and artOff212.label),
    tostring(popL212 == false), tostring(EVAL_DF_TEST_STATE().popShown == false),
    tostring(type(rec212) == "table" and rec212.dx), tostring(popR212 == true)))
  print("GROUP 212 (被动窗口图标形态：346 号宏图标/左键只拖不弹/右键开属性窗/默认开/层级+10): PASS")
end

-- ===== 组 213（1.74.32）：**匿名窗口**取证（父子链走两层 + 具名子件当身份指纹）=====
-- 真机场景：用户**开着拍卖行**，可候选逐个探全「不在」、`auction` 关键词命中 0、
--   顶层大帧兜底清单里也没有像拍卖行的帧 ⇒ 强烈指向「它是**匿名**窗口」。
--   而全 `_G` 扫描只认「挂在 `_G` 上的具名帧」⇒ 必须另开一条路：从 UIParent/WorldFrame
--   用 `GetChildren()` 往下走，并把每个窗口的**具名子件**记下来（匿名父 + 具名子件 = 身份指纹）。
do
  local savedBars213 = (EVAL_DF_TEST_STORE() or {}).dragBars
  local savedChat213 = TEST.chat

  -- ① 造一个**匿名**窗口（没有全局名）+ 两个具名子件（指纹），尺寸够大
  local anon213 = CreateFrame("Frame", nil, UIParent)
  anon213:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -120)
  anon213:SetWidth(430) anon213:SetHeight(340)
  anon213:Show()
  local kidA213 = CreateFrame("Frame", "EHKidFingerprintA", anon213)
  local kidB213 = CreateFrame("Frame", "EHKidFingerprintB", anon213)
  eq(true, true, "组213① 造了一个匿名大窗口 + 两个具名子件（指纹）")
  local _ = kidA213 and kidB213

  TEST.chat = ""
  local _, dump213 = EVAL_DF_PROBE_BARS()
  local kids213 = (type(dump213) == "table" and dump213.kids) or {}
  local hit213 = nil
  for _, k in ipairs(kids213) do
    if k.w == 430 and k.h == 340 then hit213 = k end
  end
  eq(hit213 ~= nil, true, "组213②★★★ 父子链取证抓到了这个**匿名**窗口（`_G` 扫描永远看不到它）")
  eq(hit213 ~= nil and hit213.name == "（无名）", true,
     "组213②★★ 匿名窗口如实标成「（无名）」（不编名字、也不因为它没名字就丢掉）")
  -- ★锚在 `host`（父级**对象身份**）而不是 `parent`（父级**名字**）：桩里 UIParent 是匿名帧
  --   ⇒ 按名字读只会得到「?」（与组 209⑤ 同一个坑，那里也是这么改的）。
  eq(hit213 ~= nil and hit213.host == "UIParent", true,
     "组213②★ 带宿主身份（host=" .. tostring(hit213 and hit213.host) .. "）")
  local fp213 = table.concat((hit213 and hit213.kids) or {}, " ")
  eq(string.find(fp213, "EHKidFingerprintA", 1, true) ~= nil and string.find(fp213, "EHKidFingerprintB", 1, true) ~= nil, true,
     "组213③★★★ **具名子件当身份指纹**（这正是用来认出「这个匿名窗口到底是哪个窗口」的）：" .. fp213)
  eq(hit213 ~= nil and hit213.shown == true, true, "组213②★ 记录显示状态（开着窗口时跑这条才认得出）")
  -- ④ 反向哨兵：**小**帧不该混进来（阈值 ≥200 真的在生效）
  local small213 = CreateFrame("Frame", nil, UIParent)
  small213:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0) small213:SetWidth(80) small213:SetHeight(60)
  small213:Show()
  local _, dump213b = EVAL_DF_PROBE_BARS()
  local smallHit213 = false
  for _, k in ipairs((type(dump213b) == "table" and dump213b.kids) or {}) do
    if k.w == 80 and k.h == 60 then smallHit213 = true end
  end
  eq(smallHit213, false, "组213④★★ 反向哨兵：80×60 的小帧不许混进父子链清单")
  -- ⑤ 落存档（AI 只读存档就能认出匿名窗口）
  local cfg213 = rawget(_G, "EVAL_HELP_CONFIG")
  eq(type(cfg213) == "table" and type(cfg213.dragBars.kids) == "table" and table.getn(cfg213.dragBars.kids) >= 1, true,
     "组213⑤★★ 父子链结果落存档 dragBars.kids（条数 " ..
     tostring(type(cfg213) == "table" and type(cfg213.dragBars.kids) == "table" and table.getn(cfg213.dragBars.kids) or -1) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "父子链取证", 1, true) ~= nil, true, "组213⑤★ 聊天里打出父子链取证一节")

  -- 收尾
  _G["EHKidFingerprintA"], _G["EHKidFingerprintB"] = nil, nil
  _G["GuildFrame"] = nil
  if type(cfg213) == "table" then cfg213.dragBars = savedBars213 end
  TEST.chat = savedChat213

  print(string.format("  匿名窗口取证：父子链清单 %d 条（显 %d）· 匿名窗口识别 %s（名=%s，指纹=%s）· 小帧混入 %s · 落档 kids %d",
    table.getn(kids213), (function() local c = 0 for _, k in ipairs(kids213) do if k.shown then c = c + 1 end end return c end)(),
    tostring(hit213 ~= nil), tostring(hit213 and hit213.name), tostring(fp213 ~= ""),
    tostring(smallHit213), table.getn((type(dump213b) == "table" and dump213b.kids) or {})))
  print("GROUP 213 (匿名窗口取证：父子链走两层 + 具名子件当身份指纹): PASS")
end

-- ===== 组 214（1.74.33）：图层**选中名单**（工具箱 [设置] 多选下拉）=====
-- 用户原话：「工具箱->拖拽图层 右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，
--   选中的才开启配置和支持拖拽,等图层拖拽的能力」。
-- ★本组钉住四件事（全是「接线漏一处不报错、只是静默失效」的地方）：
--   ① 真值语义：**这张表没写过 = 全选**（老存档升级后行为不许变 —— 变了的后果是「所有拖拽突然消失」）；
--   ② ★★★写入口的**物化**：第一次取消勾选时若不把「全选」快照写进表，其余层会因为表里没有键而**全变未选中**
--      （一次点击静默关掉几十个拖拽）。这条是本组最关键、也是变异要打的那个点；
--   ③ 四条生效路径都按勾选过滤：贴柄（dfRefresh）· 挂图标（dfIconsRefresh）· 应用存档（dfApplyAll）·
--      [重置]（EVAL_DF_RESET）；且一律验**行为**（真实帧几何 / 真实控件显隐），不是读回一个开关值；
--   ④ 端到端：点工具箱那一行的 **[设置]** ⇒ 走**项目现成的多选下拉**（multi=true）⇒ 通过它的**真实回调**
--      改勾选 ⇒ 当场生效（不直调 EVAL_DF_PICK_SET，那等于测自己）。
do
  local savedStore214 = rawget(_G, "EVAL_HELP_CONFIG").dragFrames
  local savedChat214 = TEST.chat
  local savedCursor214 = { TEST.cursorX, TEST.cursorY }
  local wasOn214 = EVAL_DF_ENABLED()

  local pf214 = rawget(_G, "PlayerFrame")
  eq(type(pf214) == "table" or type(pf214) == "userdata", true, "组214前置：PlayerFrame 在位（沿用前面的夹具帧）")
  local function at214(f, x, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
  end
  -- 干净起点：存档整表重建（沿用组 204 的做法）⇒ 选中名单处于「没写过 = 全选」
  rawget(_G, "EVAL_HELP_CONFIG").dragFrames = nil
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_SET(false)
  local store214 = EVAL_DF_TEST_STORE()
  eq(type(store214) == "table", true, "组214前置：存档表重建（EVAL_HELP_CONFIG.dragFrames）")
  at214(pf214, 100, -50)
  pf214:SetWidth(120) pf214:SetHeight(40)
  pf214:SetScale(1) pf214:SetAlpha(1) pf214:Show()
  -- 被动窗口夹具（图标形态）：真机里这族窗口统一 384×512 / 顶层子帧
  local gf214 = CreateFrame("Frame", "GuildFrame", UIParent)
  gf214:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -60)
  gf214:SetWidth(384) gf214:SetHeight(512)
  gf214:SetScale(1) gf214:SetAlpha(1)
  gf214:Show()
  EVAL_DF_SET(true)
  EVAL_DF_REFRESH()

  local raw214 = EVAL_DF_TEST_TARGETS_RAW()
  local nTgt214 = table.getn(raw214)

  -- ① 菜单形状（内容**唯一来源 = DF_TARGETS**，分组标题行走 locked）
  local items214, locked214, sel214, names214 = EVAL_DF_PICK_MENU()
  local nItems214 = table.getn(items214)
  eq(table.getn(locked214) == nItems214 and table.getn(names214) == nItems214, true,
     "组214① 菜单的 items/locked/names 三表等长（" .. tostring(nItems214) .. " 项）")
  local known214 = {}
  for _, t in ipairs(raw214) do known214[t.name] = true end
  local heads214, rows214, bad214 = 0, 0, 0
  for i = 1, nItems214 do
    if locked214[i] then
      heads214 = heads214 + 1
      if names214[i] ~= nil then bad214 = bad214 + 1 end -- 标题行不许指目标（否则点它能改配置）
    else
      rows214 = rows214 + 1
      if not known214[names214[i]] then bad214 = bad214 + 1 end
    end
  end
  eq(heads214 == 3, true, "组214①★★ 三条分组标题行（常驻层 / 队伍团队 / 被动窗口，实测 " .. tostring(heads214) .. "）")
  eq(rows214 == nTgt214, true, "组214①★★★ 可选项数 == 目标表条数（" .. tostring(rows214) .. "/" .. tostring(nTgt214) .. "：以后加目标不会漏进设置）")
  eq(bad214, 0, "组214①★★ 每一行都指到真实目标、标题行不指目标（坏行 " .. tostring(bad214) .. "）")
  -- ★★一一对应（不是「数了数够 37 条」就算过）：漏一个目标 = 它在设置里选不上；重复一个 = 两行改同一个目标。
  --   只数条数的话，「37 行全是同一个目标」这种硬编码写法照样能过（本轮变异 M9 正是打这个点）。
  local seen214, dupN214, missing214 = {}, 0, 0
  for i = 1, nItems214 do
    local nm = names214[i]
    if nm ~= nil then
      if seen214[nm] then dupN214 = dupN214 + 1 else seen214[nm] = true end
    end
  end
  for _, t in ipairs(raw214) do if not seen214[t.name] then missing214 = missing214 + 1 end end
  eq(dupN214 == 0 and missing214 == 0, true,
     "组214①★★★ 菜单与目标表**一一对应**（重复 " .. tostring(dupN214) .. " · 漏 " .. tostring(missing214) .. "）")
  local selN214 = 0
  for i = 1, nItems214 do if sel214[i] then selN214 = selN214 + 1 end end
  eq(selN214 == rows214, true, "组214①★★★ 初始**全选**（勾选 " .. tostring(selN214) .. "/" .. tostring(rows214) .. "）")
  eq(EVAL_DF_PICK_ALL(), true, "组214①★★ 读值口如实报告「没设过 = 全选」")
  local cI214, tI214 = EVAL_DF_PICK_COUNT()
  eq(cI214 == rows214 and tI214 == nTgt214, true, "组214①★ 计数口一致（" .. tostring(cI214) .. "/" .. tostring(tI214) .. "）")

  -- ② 单点取消 + ★★★物化哨兵（一次点击不许关掉别的层）
  eq(EVAL_DF_PICK_SET("GuildFrame", false), true, "组214② 写入口接受这次取消勾选")
  eq(EVAL_DF_PICK_ENABLED("GuildFrame"), false, "组214②★★ 取消勾选的那一层读出来是 false")
  eq(EVAL_DF_PICK_ENABLED("PlayerFrame"), true,
     "组214②★★★ 其它层**不受影响**（写入口先把「全选」快照物化 —— 少了这一步会一次点击静默关掉所有层）")
  eq(EVAL_DF_PICK_COUNT() == rows214 - 1, true, "组214②★★ 计数只少 1（实测 " .. tostring(EVAL_DF_PICK_COUNT()) .. "）")
  eq(type(store214.pick) == "table" and store214.pick.PlayerFrame == true and store214.pick.GuildFrame == nil, true,
     "组214②★★ 真值落存档 EVAL_HELP_CONFIG.dragFrames.pick（键 = 目标名，与定位记录同一套键）")
  eq(EVAL_DF_PICK_ALL(), false, "组214② 写过一次之后就不再是「全选态」")

  -- ③ 贴柄过滤（未勾选 = 拖不动）
  EVAL_DF_PICK_SET("GuildFrame", true)
  EVAL_DF_REFRESH()
  -- ★判据必须是「**这个目标名**当前有没有一条**显示中的**柄」，不能拿「之前读到的那条柄对象」去读 IsShown：
  --   柄是**按池位号复用**的（取消勾选后后面的目标整体前移一格）⇒ 原来那条柄对象会被改写成别的目标
  --   （dfName 变了、但仍然是显示的）——用旧对象判会**误报**（本轮第一版就是这么写错的）。
  local function shownHandle214(name)
    local b = EVAL_DF_TEST_HANDLE(name)
    if b == nil then return false end
    return b:IsShown() and true or false
  end
  local hBefore214 = shownHandle214("PlayerFrame")
  eq(hBefore214, true, "组214③前置：勾着时 PlayerFrame 贴着拖拽柄（显示中）")
  local poolN214 = EVAL_DF_TEST_STATE().poolN
  EVAL_DF_PICK_SET("PlayerFrame", false)
  EVAL_DF_PICK_REFRESH()
  local hOff214 = shownHandle214("PlayerFrame")
  eq(hOff214, false, "组214③★★★ 取消勾选 ⇒ 该层拖拽柄收起（= 拖不动、也点不开属性弹窗）")
  eq(EVAL_DF_TEST_STATE().poolN == poolN214 - 1, true,
     "组214③★★ 柄池占用如实少 1（" .. tostring(poolN214) .. " → " .. tostring(EVAL_DF_TEST_STATE().poolN) .. "）")
  EVAL_DF_PICK_SET("PlayerFrame", true)
  EVAL_DF_PICK_REFRESH()
  local hBack214 = shownHandle214("PlayerFrame")
  eq(hBack214, true, "组214③★★ 重新勾上 ⇒ 柄回来")

  -- ④ 图标过滤（未勾选 = 挂不上配置图标）
  EVAL_DF_PICK_SET("GuildFrame", true)
  EVAL_DF_PICK_REFRESH()
  local ib214 = EVAL_DF_TEST_ICON("GuildFrame")
  eq(ib214 ~= nil and ib214:IsShown() == true, true, "组214④前置：勾着时该窗口挂着配置图标")
  -- ★★「挂上几个」的计数也要跟着掉：这是「未勾选的层**连图标都不给它建**」的可读数证据 ——
  --   只看「它是隐藏的」不够：隐藏可能只是后面那道收尾循环顺手收掉的（那样它其实已经被建过、
  --   已经占了资源、计数也虚高）。变异 M4 就是这么漏过第一版的（源码检查里那句 dfPicked 在收尾循环里也有）。
  local iconN214 = EVAL_DF_TEST_STATE().iconN
  EVAL_DF_PICK_SET("GuildFrame", false)
  EVAL_DF_PICK_REFRESH()
  eq(ib214 ~= nil and ib214:IsShown() == false, true, "组214④★★★ 取消勾选 ⇒ 配置图标收起（= 点不到属性弹窗）")
  local iconN2_214 = EVAL_DF_TEST_STATE().iconN
  eq(iconN2_214 == (iconN214 or 0) - 1, true,
     "组214④★★★ 取消勾选 ⇒ 「已挂图标」计数少 1（" .. tostring(iconN214) .. " → " .. tostring(iconN2_214) ..
     "：未勾选的层连图标都不给它建，不是「建了再藏起来」）")
  EVAL_DF_PICK_SET("GuildFrame", true)
  EVAL_DF_PICK_REFRESH()
  local ibBack214 = EVAL_DF_TEST_ICON("GuildFrame")
  eq(ibBack214 ~= nil and ibBack214:IsShown() == true, true, "组214④★★ 重新勾上 ⇒ 图标回来（不重建：缓存按目标名）")
  eq(EVAL_DF_TEST_STATE().iconN == iconN214, true,
     "组214④★★ 重新勾上 ⇒ 计数回到原值（" .. tostring(EVAL_DF_TEST_STATE().iconN) .. "）")

  -- ⑤ 应用存档也按勾选过滤（未勾选 = 插件不碰它的位置/属性）
  store214.PlayerFrame = { base = EVAL_DF_TEST_CAPTURE("PlayerFrame"), dx = 60, dy = 0 }
  EVAL_DF_PICK_SET("PlayerFrame", true)
  EVAL_DF_PICK_REFRESH()
  local appliedL214 = pf214:GetLeft()
  eq(appliedL214 ~= nil and appliedL214 ~= 100, true,
     "组214⑤前置：勾着 ⇒ 存档里的位移被应用（left = " .. tostring(appliedL214) .. "）")
  at214(pf214, 300, -50) -- 手动挪走（模拟「漂了」）
  EVAL_DF_PICK_SET("PlayerFrame", false)
  EVAL_DF_PICK_REFRESH()
  eq(pf214:GetLeft(), 300, "组214⑤★★★ 取消勾选 ⇒ **不应用存档**（挪到 300 就留在 300 —— 插件不再碰它）")
  EVAL_DF_PICK_SET("PlayerFrame", true)
  EVAL_DF_PICK_REFRESH()
  eq(math.abs((pf214:GetLeft() or 0) - appliedL214) < 1, true,
     "组214⑤★★ 重新勾上 ⇒ 存档参数再次生效（回到 " .. tostring(appliedL214) .. "，实测 " .. tostring(pf214:GetLeft()) .. "）")

  -- ⑥ [重置] 的清单如实标出未勾选的层（读数照给，但要说清「插件不管它」）
  EVAL_DF_PICK_SET("GuildFrame", false)
  local line214 = nil
  for _, ln in ipairs(EVAL_DF_SUMMARY()) do
    local s = tostring(ln)
    if string.sub(s, 1, string.len("公会：")) == "公会：" then line214 = s end
  end
  eq(line214 ~= nil and string.find(line214, "未勾选", 1, true) ~= nil, true,
     "组214⑥★★ 面板如实标出未勾选的层（" .. tostring(line214) .. "）")

  -- ⑦ [重置] 不许动未勾选的层（记录保留 + 如实播报）
  store214.GuildFrame = { scale = 0.25 }
  gf214:SetScale(0.25)
  EVAL_DF_PICK_SET("GuildFrame", false)
  TEST.chat = ""
  EVAL_DF_RESET()
  eq(gf214:GetScale() == 0.25 and type(store214.GuildFrame) == "table", true,
     "组214⑦★★★ 没勾选的层 [重置] 一个属性都不碰、记录原样保留（scale = " .. tostring(gf214:GetScale()) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "没勾选", 1, true) ~= nil, true,
     "组214⑦★★ [重置] 如实播报「有几个目标没勾选」（不静默跳过）")
  EVAL_DF_PICK_SET("GuildFrame", true)
  EVAL_DF_RESET()
  eq(gf214:GetScale() == 1, true, "组214⑦★ 勾上之后再 [重置] ⇒ 正常还原（实测 " .. tostring(gf214:GetScale()) .. "）")

  -- ⑧ 端到端：点工具箱那一行的 [设置] → 现成的多选下拉 → 真实回调改勾选 → 当场生效
  EVAL_HELP_CFG_SETTAB(3)
  EVAL_TB_TEST_GOTO("dbgDrag")
  local setBtn214 = EVAL_TEST_TB_ADD_BTN_FOR("dbgDrag")
  eq(setBtn214 ~= nil and setBtn214:IsShown() == true, true,
     "组214⑧★★ 工具箱「图层拖拽柄」行右侧真的有一个 [设置] 按钮（走真实控件，不是只写了行数据）")
  -- ★★★几何哨兵：这一行现在有**两个**右侧按钮（[设置]=add 槽 / [重置]=clr 槽），**不许重叠**。
  --   为什么必须验几何：两个按钮叠在一起时「按钮存在 + OnClick 挂上了」全绿，真机却是上面那个把点击
  --   全吃掉、另一个永远点不到（本轮第一版 [设置] 就在 chv 的 88 宽带上，正好被 [重置] 完全盖住）。
  local geo214 = EVAL_TB_TEST_ROW_BTNS("dbgDrag")
  eq(type(geo214) == "table" and geo214.add ~= nil and geo214.clr ~= nil, true,
     "组214⑧★★ 读得到这一行两个右侧按钮的几何（add/clr）")
  local resetBtn214 = EVAL_TEST_TB_CLR_FOR("dbgDrag")
  eq(resetBtn214 ~= nil and resetBtn214:IsShown() == true, true,
     "组214⑧★★ [重置] 仍在（换了槽位：clr，因为 chv 与 add 完全重叠）")
  if geo214 and geo214.add and geo214.clr then
    local aR214 = (geo214.add.left or 0) + (geo214.add.width or 0)
    local cL214 = geo214.clr.left or 0
    eq(cL214 >= aR214, true,
       "组214⑧★★★ [设置] 与 [重置] **不重叠**（[设置] 右边界 " .. tostring(aR214) .. " ≤ [重置] 左边 " .. tostring(cL214) .. "）")
  end
  eq(geo214 ~= nil and geo214.chv ~= nil and geo214.chv.shown == false, true,
     "组214⑧★ 这一行**没有**用 chv 槽（否则它会横跨整个右侧带、把 add 盖住）")
  TEST.tipLines = nil
  local enter214 = setBtn214 and setBtn214:GetScript("OnEnter")
  eq(type(enter214) == "function", true, "组214⑧★ [设置] 挂了真实 OnEnter")
  if type(enter214) == "function" then pcall(enter214) end
  local tip214 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tip214 = tip214 .. tostring(ln.text or "") .. "\n" end
  eq(string.find(tip214, "已勾选", 1, true) ~= nil, true,
     "组214⑧★★ 悬停显示已勾选数量（用户看得到「哪些层开着」）")
  local savedDD214 = EVAL_DD_OPEN
  local capA214, capI214, capCb214, capO214 = nil, nil, nil, nil
  rawset(_G, "EVAL_DD_OPEN", function(anchor, items, cb, opts)
    capA214, capI214, capCb214, capO214 = anchor, items, cb, opts
    return true
  end)
  local click214 = setBtn214 and setBtn214:GetScript("OnClick")
  eq(type(click214) == "function", true, "组214⑧★ [设置] 挂了真实 OnClick")
  if type(click214) == "function" then pcall(click214) end
  rawset(_G, "EVAL_DD_OPEN", savedDD214)
  eq(capA214 == setBtn214 and type(capI214) == "table", true,
     "组214⑧★★★ 点 [设置] ⇒ 用**项目现成的下拉件** EVAL_DD_OPEN 打开，且锚在这个按钮上（不新造控件）")
  eq(capO214 ~= nil and capO214.multi == true and type(capO214.locked) == "table" and type(capO214.selected) == "table", true,
     "组214⑧★★★ 下拉是**多选**（multi=true，点一项不关面板；分组标题行走 locked、初始勾选走 selected）")
  local same214 = (type(capI214) == "table" and table.getn(capI214) == nItems214)
  if same214 then
    for i = 1, nItems214 do if capI214[i] ~= items214[i] then same214 = false end end
  end
  eq(same214, true, "组214⑧★★★ 菜单内容**逐项来自模块**（工具箱没有自己另造一份目标表 ⇒ 不会两处漂移）")
  local pi214 = nil
  for i = 1, table.getn(names214) do if names214[i] == "PlayerFrame" then pi214 = i end end
  eq(pi214 ~= nil, true, "组214⑧前置：菜单里能找到「用户头像」那一行（下标 " .. tostring(pi214) .. "）")
  TEST.chat = ""
  if type(capCb214) == "function" and pi214 then pcall(capCb214, pi214, false) end
  eq(EVAL_DF_PICK_ENABLED("PlayerFrame"), false,
     "组214⑧★★★ 通过下拉的**真实回调**取消勾选 ⇒ 立刻落进真值（走的是真实接线，不是直调写入口）")
  eq(string.find(tostring(TEST.chat or ""), "图层选择已更新", 1, true) ~= nil, true,
     "组214⑧★★ 回调里立刻结算并如实播报")
  local hEnd214 = shownHandle214("PlayerFrame")
  eq(hEnd214 == false, true,
     "组214⑧★★★ 端到端：下拉里取消勾选 ⇒ 那层的拖拽柄当场收起")

  -- ⑨ 全不选：如实播报 + 一条柄都不贴（不是「点了没反应」）
  for _, t in ipairs(EVAL_DF_TEST_TARGETS_RAW()) do EVAL_DF_PICK_SET(t.name, false) end
  eq(EVAL_DF_PICK_COUNT() == 0, true, "组214⑨★★ 全部取消勾选后计数为 0")
  TEST.chat = ""
  EVAL_DF_PICK_REFRESH()
  eq(string.find(tostring(TEST.chat or ""), "0/", 1, true) ~= nil, true, "组214⑨★ 如实播报 0/总数（不静默）")
  eq(EVAL_DF_REFRESH() == 0, true, "组214⑨★★★ 一层都没勾 ⇒ 一个拖拽柄都不贴（dfRefresh 返回 0）")
  local iconShown214 = 0
  for _, t in ipairs(raw214) do
    if t.icon then
      local b = EVAL_DF_TEST_ICON(t.name)
      if b and b:IsShown() then iconShown214 = iconShown214 + 1 end
    end
  end
  eq(iconShown214, 0, "组214⑨★★ 一层都没勾 ⇒ 一个配置图标都不显示（实测 " .. tostring(iconShown214) .. "）")

  -- 收尾：存档表 / 开关 / 光标 / 聊天缓冲一律**原值还回**（跨用例状态残留是本项目老坑）
  _G["GuildFrame"] = nil
  EVAL_DF_SET(false)
  rawget(_G, "EVAL_HELP_CONFIG").dragFrames = savedStore214
  if wasOn214 then EVAL_DF_SET(true) end
  TEST.cursorX, TEST.cursorY = savedCursor214[1], savedCursor214[2]
  TEST.chat = savedChat214
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  图层选中名单：菜单 %d 项（标题 %d + 可选项 %d，目标表 %d）· 默认全选 %s · " ..
    "柄 勾/去/回 = %s/%s/%s（柄池 %s→%s）· 图标 去/回 = %s/%s · 存档应用按勾选过滤 %s · 重置跳过未勾选 %s · " ..
    "面板标注 %s · 工具箱 [设置]+多选下拉端到端 %s · 全不选贴柄数 %s",
    nItems214, heads214, rows214, nTgt214, tostring(selN214 == rows214),
    tostring(hBefore214), tostring(hOff214), tostring(hBack214), tostring(poolN214),
    tostring(poolN214 - 1),
    tostring(ib214 ~= nil and ib214:IsShown() == false), tostring(ibBack214 ~= nil and ibBack214:IsShown() == true),
    tostring(appliedL214 ~= nil), tostring(line214 ~= nil),
    tostring(hEnd214 == false), tostring(same214), tostring(EVAL_DF_REFRESH() == 0)))
  print("GROUP 214 (图层选中名单：默认全选/物化快照/贴柄与图标与存档与重置四条路径都按勾选过滤/工具箱多选下拉端到端): PASS")
end

-- ===== 组 215（1.74.33）：窗口的**头部拖拽带**（用户：「窗口拖拽的区域能否定位到 窗体头部红色部分?」）=====
-- 用户截图：任务窗口顶部那条红线 —— 希望**整条标题栏**都能抓来拖窗口，而不是只有右上角那个 20×20 的小图标。
-- ★本组钉住四件事（全是「不报错、只是真机点不动或被挡」的接线）：
--   ① 带**存在且贴住头部**（层级 = 目标 level + 10；高度只盖标题条那一带）；
--   ② ★★★**右端绝不越进关闭按钮留空区**（= 窗口宽 − DF_ICON_RIGHT）：这条带是**透明**的，
--      越过去就会「悄悄吃掉关闭按钮的点击」——本轮刚因为图标压住关闭按钮被用户截图抓过一次；
--   ③ **左键拖头部 = 拖窗口**（走真实脚本，落存档；且左键**不弹**属性窗），**右键 = 开属性窗**；
--   ④ 与图标**不重叠**、且未勾选/关掉开关时**跟着一起收**（只收一个 ⇒ 留下一条看不见却吃点击的带子）。
do
  local store215 = EVAL_DF_TEST_STORE()
  local savedBars215 = store215 and store215.dragBars
  local wasOn215 = EVAL_DF_ENABLED()
  local savedCursor215 = { TEST.cursorX, TEST.cursorY }
  local savedChat215 = TEST.chat

  local gf215 = CreateFrame("Frame", "GuildFrame", UIParent)
  gf215:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -80)
  gf215:SetWidth(384) gf215:SetHeight(512)
  gf215:SetScale(1) gf215:SetAlpha(1)
  gf215:Show()
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_SET(true)
  EVAL_DF_REFRESH()

  -- ① 带在位、贴头部、层级跟着目标
  local h215 = EVAL_DF_TEST_HEAD("GuildFrame")
  eq(type(h215) == "table" and h215.btn ~= nil, true, "组215①★★★ 窗口头部挂了拖拽带（真实控件）")
  eq(h215 ~= nil and h215.shown == true, true, "组215①★★ 带是显示的（主开关开着、这一层默认勾选）")
  eq(h215 ~= nil and h215.level == gf215:GetFrameLevel() + 10, true,
     "组215①★★ 带层级 = 目标 level + 10（实测 " .. tostring(h215 and h215.level) .. "）")
  -- ★★判据验**控件真实高度**（realH，现读），不验常量 DF_HEAD_H —— 验常量就是「测自己」：
  --   变异 M28（把 SetHeight 改成 200 ⇒ 带盖住整个窗口）第一版就是这么漏过去的。
  --   验的是**性质**：高度落在「标题条 + 一点点余量」这一档（10~48），不许盖住整个窗口；
  --   ★用户 1.74.33 追加「向下再延伸 15px」后是 33（原 18）—— 这条性质**不钉死数字**，改高度不会被卡。
  eq(h215 ~= nil and type(h215.realH) == "number" and h215.realH >= 10 and h215.realH <= 48, true,
     "组215①★★★ 头部带**真实高度**落在「标题条 + 余量」这一档（实测 " .. tostring(h215 and h215.realH) ..
     "；常量是 " .. tostring(h215 and h215.h) .. "，判据只认控件自己的高度、不钉死数字）")

  -- ② ★★★几何哨兵：右端绝不许越进「关闭按钮留空区」
  local wT215 = gf215:GetWidth()
  local hRight215 = (h215 and h215.left or 0) + (h215 and h215.width or 0)
  eq(hRight215 <= (wT215 - 58) + 0.01, true,
     "组215②★★★ 带右端 " .. tostring(hRight215) .. " ≤ 窗口宽 − 关闭按钮留空区（" .. tostring(wT215 - 58) ..
     "）⇒ 不会盖住窗口自带的关闭按钮")
  eq((h215 and h215.width or 0) > 0.6 * wT215, true,
     "组215②★★ 带够宽（" .. tostring(h215 and h215.width) .. " / " .. tostring(wT215) .. "：整条标题栏都能抓，不是一小段）")
  -- ③ 与右上角图标**不重叠**（两块都能点）
  local ib215 = EVAL_DF_TEST_ICON("GuildFrame")
  local ibLeft215 = nil
  if ib215 then
    local _p, _r, _rp, xv = ib215:GetPoint(1)
    -- 图标锚 TOPRIGHT、偏移 −58 ⇒ 它的左边界 = 窗口宽 − 58 − 图标宽
    if type(xv) == "number" then ibLeft215 = wT215 + xv - 20 end
  end
  eq(ibLeft215 == nil or hRight215 <= ibLeft215 + 0.01, true,
     "组215③★★ 头部带与图标**不重叠**（带右端 " .. tostring(hRight215) .. " ≤ 图标左边界 " .. tostring(ibLeft215) .. "）")

  -- ④ 左键拖头部 = 拖窗口（真实脚本；先按下、再挪光标、再点 OnUpdate —— 顺序写反位移恒 0）
  local down215 = h215 and h215.btn:GetScript("OnMouseDown")
  local up215 = h215 and h215.btn:GetScript("OnMouseUp")
  local mv215 = h215 and h215.btn:GetScript("OnUpdate")
  eq(type(down215) == "function" and type(up215) == "function" and type(mv215) == "function", true,
     "组215④前置：带挂了真实 OnMouseDown/OnMouseUp/OnUpdate")
  if store215 then store215.GuildFrame = nil end
  local before215 = gf215:GetLeft()
  TEST.cursorX, TEST.cursorY = 100, -100
  if down215 then pcall(down215) end
  TEST.cursorX, TEST.cursorY = 140, -130   -- 挪 40px / 上移 30px = 真拖动
  for _ = 1, 6 do if mv215 then pcall(mv215, 0.05) end end
  if up215 then pcall(up215, "LeftButton") end
  local rec215 = (EVAL_DF_TEST_STORE() or {})["GuildFrame"]
  eq(type(rec215) == "table" and rec215.dx ~= nil, true,
     "组215④★★★ 左键拖**头部**真的拖了窗口并落存档（dx=" .. tostring(type(rec215) == "table" and rec215.dx) .. "）")
  eq(gf215:GetLeft() ~= before215, true,
     "组215④★★ 窗口真的动了（" .. tostring(before215) .. " → " .. tostring(gf215:GetLeft()) .. "）")
  eq(EVAL_DF_TEST_STATE().popShown == false, true, "组215④★★★ 左键拖/点头部**不弹**属性窗（与图标同一口径）")

  -- ⑤ 右键头部 = 开属性窗（顺序：先验右键能开，再关掉——否则「不弹」是空洞的真）
  TEST.cursorX, TEST.cursorY = 100, -100
  if down215 then pcall(down215) end
  if up215 then pcall(up215, "RightButton") end
  local popR215 = EVAL_DF_TEST_STATE().popShown
  eq(popR215 == true, true, "组215⑤★★★ 右键点头部 ⇒ 打开属性弹窗")
  local pc215 = EVAL_DF_TEST_POP()
  if pc215 and pc215.root then pcall(pc215.root.Hide, pc215.root) end

  -- ⑥ 未勾选 ⇒ 带跟着一起收；重新勾上 ⇒ 回来（只收图标不收带 = 留一条看不见却吃点击的带子）
  EVAL_DF_PICK_SET("GuildFrame", false)
  EVAL_DF_PICK_REFRESH()
  local hOff215 = EVAL_DF_TEST_HEAD("GuildFrame")
  eq(hOff215 ~= nil and hOff215.shown == false, true,
     "组215⑥★★★ 取消勾选 ⇒ 头部拖拽带**一起收起**（不留看不见却吃点击的带子）")
  EVAL_DF_PICK_SET("GuildFrame", true)
  EVAL_DF_PICK_REFRESH()
  local hBack215 = EVAL_DF_TEST_HEAD("GuildFrame")
  eq(hBack215 ~= nil and hBack215.shown == true, true, "组215⑥★★ 重新勾上 ⇒ 带回来（不重建）")

  -- 收尾
  _G["GuildFrame"] = nil
  eq(true, true, "组215 收尾")
  if type(store215) == "table" then
    store215.dragBars = savedBars215
    store215["GuildFrame"] = nil
  end
  TEST.cursorX, TEST.cursorY = savedCursor215[1], savedCursor215[2]
  TEST.chat = savedChat215
  EVAL_DF_SET(wasOn215)
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  窗口头部拖拽带：在位 %s · 层级+10 %s · 高度 %s/上边距 %s · 右端 %s ≤ %s（关闭按钮留空区） · " ..
    "宽 %s/%s · 与图标不重叠 %s · 左键拖头部落存档 %s（窗口动了 %s）· 左键不弹 %s · 右键开窗 %s · 取消勾选一并收起 %s",
    tostring(type(h215) == "table"), tostring(h215 ~= nil and h215.level == gf215:GetFrameLevel() + 10),
    tostring(h215 and h215.h), tostring(h215 and h215.top), tostring(hRight215), tostring(wT215 - 58),
    tostring(h215 and h215.width), tostring(wT215), tostring(ibLeft215 == nil or hRight215 <= ibLeft215 + 0.01),
    tostring(type(rec215) == "table" and rec215.dx ~= nil), tostring(gf215:GetLeft() ~= before215),
    tostring(EVAL_DF_TEST_STATE().popShown == false), tostring(popR215 == true),
    tostring(hOff215 ~= nil and hOff215.shown == false)))
  print("GROUP 215 (窗口头部拖拽带：贴标题条/右端让开关闭按钮/左键拖窗口不弹窗/右键开属性窗/随勾选收起与图标不重叠): PASS")
end

-- ===== 组 216（1.74.33）：鼠标键分派的**真机参数形态**（用户报「右键点图标打不开配置」的复现与钉子）=====
-- 真机 bug：图标/头部带的回调原来写成 `function(a1) if a1 == "RightButton"`，而本客户端脚本回调是
--   **`handler(self, button)`** —— 第一个参数是 **self（帧对象）**，键在第 2 个 ⇒ 右键判定**永远不成立**
--   ⇒ 右键一次都没开过窗。★而当时的测试是 `pcall(handler, "RightButton")`（直接喂字符串）⇒ **全绿**。
-- ★本组存在的唯一目的：**按客户端的形态调**（`handler(frame, "RightButton")`、以及传统帧 API 的全局 `arg1`），
--   把「测试的调用形态 ≠ 客户端的调用形态」这条盲区钉死。
do
  local store216 = EVAL_DF_TEST_STORE()
  local savedBars216 = store216 and store216.dragBars
  local wasOn216 = EVAL_DF_ENABLED()
  local savedArg216 = { arg1, arg2 }
  local savedChat216 = TEST.chat

  local gf216 = CreateFrame("Frame", "GuildFrame", UIParent)
  gf216:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 44, -88)
  gf216:SetWidth(384) gf216:SetHeight(512)
  gf216:Show()
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_SET(true)
  EVAL_DF_REFRESH()

  local ib216 = EVAL_DF_TEST_ICON("GuildFrame")
  local hd216 = EVAL_DF_TEST_HEAD("GuildFrame")
  eq(ib216 ~= nil and hd216 ~= nil and hd216.btn ~= nil, true, "组216前置：图标与头部拖拽带都在位")
  local icon216, head216 = ib216, (hd216 and hd216.btn)
  local function script216(b, ev) return b and b.GetScript and b:GetScript(ev) end
  local function popShown216() return EVAL_DF_TEST_STATE().popShown == true end
  local function closePop216()
    local p = EVAL_DF_TEST_POP()
    if p and p.root then pcall(p.root.Hide, p.root) end
  end

  -- ① ★★★真机形态：`handler(self, "RightButton")` —— 这条就是当年漏掉的
  local click216 = script216(icon216, "OnClick")
  eq(type(click216) == "function", true, "组216①前置：图标挂了 OnClick")
  closePop216()
  if type(click216) == "function" then pcall(click216, icon216, "RightButton") end
  eq(popShown216(), true, "组216①★★★ **OnClick 按真机形态**（self + \"RightButton\"）⇒ 打开属性弹窗")
  closePop216()
  local up216 = script216(icon216, "OnMouseUp")
  if type(up216) == "function" then pcall(up216, icon216, "RightButton") end
  eq(popShown216(), true, "组216①★★★ **OnMouseUp 按真机形态**同样能打开（两条分派路都留着）")
  closePop216()

  -- ② 传统帧 API 的**全局 arg1** 形态（只传 self 时靠全局）
  arg1, arg2 = "RightButton", nil
  if type(click216) == "function" then pcall(click216, icon216) end
  eq(popShown216(), true, "组216②★★ 只传 self、键在**全局 arg1** 时也能打开（项目既有写法：参数形态不固定，四处都认）")
  closePop216()
  arg1, arg2 = savedArg216[1], savedArg216[2]

  -- ③ 反向哨兵：**左键**（真机形态）不许弹窗
  if type(click216) == "function" then pcall(click216, icon216, "LeftButton") end
  eq(popShown216(), false, "组216③★★★ 左键 OnClick（真机形态）⇒ **不弹**属性窗（用户 1.74.33 的要求）")
  local upL216 = script216(icon216, "OnMouseUp")
  if type(upL216) == "function" then pcall(upL216, icon216, "LeftButton") end
  eq(popShown216(), false, "组216③★★ 左键 OnMouseUp（真机形态）⇒ 也不弹（该路只负责收拖拽）")

  -- ④ 右键**按下**不启动拖拽（右键是「开属性窗」，不是「拖窗口」）
  local down216 = script216(icon216, "OnMouseDown")
  if type(down216) == "function" then pcall(down216, icon216, "RightButton") end
  eq(EVAL_DF_TEST_STATE().dragging == false, true, "组216④★★ 右键按下**不启动拖拽**（否则右键一按窗口就跟着跑）")
  local store216b = EVAL_DF_TEST_STORE() or {}
  store216b.GuildFrame = nil
  local beforeL216 = gf216:GetLeft()
  TEST.cursorX, TEST.cursorY = 300, -300
  if type(down216) == "function" then pcall(down216, icon216, "LeftButton") end
  eq(EVAL_DF_TEST_STATE().dragging == true, true, "组216④★ 左键按下**才**启动拖拽（真机形态）")
  TEST.cursorX, TEST.cursorY = 340, -330
  local mv216 = script216(icon216, "OnUpdate")
  for _ = 1, 6 do if type(mv216) == "function" then pcall(mv216, icon216, 0.05) end end
  if type(upL216) == "function" then pcall(upL216, icon216, "LeftButton") end
  eq(gf216:GetLeft() ~= beforeL216, true, "组216④★ 左键真机形态拖得动窗口（" .. tostring(beforeL216) .. " → " .. tostring(gf216:GetLeft()) .. "）")

  -- ⑤ 头部拖拽带：同样是「右键 OnClick 开窗」（它与图标共用同一份实现，但这里按**它自己的控件**再验一遍）
  if head216 then
    local hClick216 = script216(head216, "OnClick")
    closePop216()
    if type(hClick216) == "function" then pcall(hClick216, head216, "RightButton") end
    eq(popShown216(), true, "组216⑤★★★ 头部拖拽带：OnClick 真机形态右键 ⇒ 打开属性弹窗")
    closePop216()
    if type(hClick216) == "function" then pcall(hClick216, head216, "LeftButton") end
    eq(popShown216(), false, "组216⑤★★ 头部拖拽带：左键不弹（与图标同一口径）")
  end

  -- 收尾
  _G["GuildFrame"] = nil
  arg1, arg2 = savedArg216[1], savedArg216[2]
  if type(store216) == "table" then
    store216.dragBars = savedBars216
    store216["GuildFrame"] = nil
  end
  TEST.chat = savedChat216
  EVAL_DF_SET(wasOn216)
  EVAL_DF_TEST_TARGETS_RESET()

  print("  鼠标键真机形态：OnClick+右键开窗 true · OnMouseUp+右键开窗 true · 全局 arg1 形态开窗 true · " ..
    "左键(OnClick/OnMouseUp)不弹 true · 右键按下不拖拽 true · 头部带同样 true")
  print("GROUP 216 (鼠标键真机形态：handler(self,button)/全局 arg1 两形态 × OnClick/OnMouseUp 两条分派路): PASS")
end

-- ===== 组 217（1.74.33）：拖拽**位移叠加漂移**（用户：「窗口拖拽有些会有位移叠加漂移，比如角色」）=====
-- 真因（本轮定案，已按真机语义推导）：`dfCapture` 把**屏幕坐标**（`GetLeft/GetBottom`）与
--   **帧本地尺寸**（`GetWidth/GetHeight`、含缩放）混在一个式子里：
--       x = GetLeft + GetWidth × 系数 − 相对帧锚点
--   ① 尺寸项少了 ×缩放：`w·系数·(1 − s)` 被当成偏移的一部分；
--   ② 算出来的差是**屏幕**量，却被当成 `SetPoint` 的偏移（本地单位）再落一次 ⇒ 又被折算一次；
--   ③ 而且「反解系数」也救不了：那个偏移是**几何反算**出来的（≠ `GetPoint` 原值），与真偏移差一个
--      **常数**（单位口径 + 锚点系数叠加），与拖多远无关 ⇒ 必须解 **仿射关系**（常数 + 折算 × 偏移），
--      不能只除一个系数（本组第 1 版就栽在这里：单次对、连续三次仍叠加）。
--   ④ 尺寸在拖拽**中途**变化时（队伍框来人 ⇒ 行数变了），旧口径还会把 `Δh` 当位移记进存档（⑦ 专钉这条）。
--   ⇒ 缩放 ≠ 1 的窗口每拖一次就叠加一个固定位移（越拖越偏），第一次拖拽还会「跑得比光标远」。
-- ★本组在桩里**按真机语义造一台 1024×768 的屏 + 一个缩放 0.8 的窗口**（UIParent 的左下角故意放在
--   非零点，这样「把屏幕量当偏移用」这类单位错才会真的露出来），把漂移复现出来，再钉住新口径：
--   位移**按屏幕算**（`cap.l + 光标位移`）、落锚**量回自证 + 手量折算**（首猜走 `GetEffectiveScale`）⇒
--   单次、连续三次、纵向都必须与光标 1:1（老口径在这里会叠加）。
-- ★变异验证（tmp/mut_drift.js，6/6 捕获）：M35 去掉量回自证 → ④；M36 结算退回锚点相减 → ⑦；
--   M37 不记屏幕基准 → ②；M38 去掉修正循环 → ④；M39 播报不报系数 → ③；M40 `dfIsAt` 永远 true → 组204。
do
  local store217 = EVAL_DF_TEST_STORE()
  local savedBars217 = store217 and store217.dragBars
  local wasOn217 = EVAL_DF_ENABLED()
  local savedCursor217 = { TEST.cursorX, TEST.cursorY }
  local savedChat217 = TEST.chat

  local pf217 = rawget(_G, "PlayerFrame")
  eq(type(pf217) == "table" or type(pf217) == "userdata", true, "组217前置：PlayerFrame 夹具在位")

  -- ===== ① 桩里造「屏幕 + 缩放 0.8 的窗口」（按真机语义，而不是让桩替我们把单位抹平）=====
  local UI_L, UI_B, UI_W, UI_H = 200, -300, 1024, 768   -- 屏幕左下角故意不在 0
  local ES217 = 0.8                                     -- 窗口缩放
  local FW217, FH217 = 384, 512                           -- 帧**本地**尺寸（⑦ 会在拖拽中途改它）
  local offX217, offY217 = 0, 0                         -- SetPoint 的偏移（帧本地单位）
  local savedUI217 = {}
  local function patchUI217(name, fn)
    savedUI217[name] = rawget(UIParent, name)
    rawset(UIParent, name, fn)
  end
  patchUI217("GetLeft", function() return UI_L end)
  patchUI217("GetBottom", function() return UI_B end)
  patchUI217("GetWidth", function() return UI_W end)
  patchUI217("GetHeight", function() return UI_H end)
  patchUI217("GetTop", function() return UI_B + UI_H end)
  patchUI217("GetRight", function() return UI_L + UI_W end)
  local function screenTop217() return (UI_B + UI_H) + offY217 * ES217 end
  local function screenLeft217() return UI_L + offX217 * ES217 end
  local function screenBottom217() return screenTop217() - FH217 * ES217 end
  rawset(pf217, "SetPoint", function(_, a1, a2, a3, a4, a5)
    local x, y = nil, nil
    if a4 ~= nil then x, y = a4, a5 end
    offX217, offY217 = tonumber(x) or 0, tonumber(y) or 0
    return true
  end)
  rawset(pf217, "GetLeft", screenLeft217)
  rawset(pf217, "GetBottom", screenBottom217)
  rawset(pf217, "GetTop", screenTop217)
  rawset(pf217, "GetRight", function() return screenLeft217() + FW217 * ES217 end)
  rawset(pf217, "GetWidth", function() return FW217 end)   -- ★本地宽度（**不**乘 0.8）
  rawset(pf217, "GetHeight", function() return FH217 end)  -- ★本地高度
  rawset(pf217, "GetPoint", function() return "TOPLEFT", "UIParent", "TOPLEFT", offX217, offY217 end)
  rawset(pf217, "GetNumPoints", function() return 1 end)
  rawset(pf217, "ClearAllPoints", function() return true end)
  rawset(pf217, "GetEffectiveScale", function() return ES217 end)

  if type(store217) == "table" then store217.PlayerFrame = nil end
  EVAL_DF_SET(true)
  EVAL_DF_REFRESH()
  local h217 = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(h217 ~= nil, true, "组217前置：拿到 PlayerFrame 的拖拽柄")
  local down217 = h217 and h217:GetScript("OnMouseDown")
  local up217 = h217 and h217:GetScript("OnMouseUp")
  local mv217 = h217 and h217:GetScript("OnUpdate")

  -- 拖一次：按下 → 挪光标 → 点若干帧 OnUpdate → 松手（顺序不能反：位移基准在按下那一刻取）
  local function dragBy217(dx, dy)
    TEST.cursorX, TEST.cursorY = 600, -500
    if type(down217) == "function" then pcall(down217, h217, "LeftButton") end
    TEST.cursorX, TEST.cursorY = 600 + dx, -500 + dy
    for _ = 1, 8 do if type(mv217) == "function" then pcall(mv217, h217, 0.05) end end
    if type(up217) == "function" then pcall(up217, h217, "LeftButton") end
  end

  -- ② 单次拖拽：窗口的**屏幕位移必须 = 光标位移**（老口径会「跑得比光标远」）
  local l0 = screenLeft217()
  dragBy217(40, 0)
  local d1 = screenLeft217() - l0
  eq(math.abs(d1 - 40) <= 1.5, true,
     "组217②★★★ 单次拖拽 40px ⇒ 屏幕位移 40（实测 " .. string.format("%.1f", d1) .. "）")

  -- ③ 实测系数：本窗口「偏移 → 屏幕」折算 0.8 ⇒ 读值口必须报出 ≈0.8（老代码就是没有这一段才漂）
  local k217 = EVAL_DF_TEST_STATE().lastK
  eq(type(k217) == "number" and math.abs(k217 - ES217) <= 0.06, true,
     "组217③★★★ 实测位移系数 k ≈ 0.8（实测 " .. tostring(k217) .. "）：落锚时按它反解，不猜单位")
  eq(string.find(tostring(TEST.chat or ""), "实测位移系数", 1, true) ~= nil, true,
     "组217③★★ 拖拽播报如实报出该系数（用户能看到「这个窗口为什么要折算」）")

  -- ④ ★★★核心：**连续三次拖拽不许叠加**（总位移 = 光标总位移）
  local before4 = screenLeft217()
  dragBy217(30, 0)
  dragBy217(30, 0)
  dragBy217(30, 0)
  local moved4 = screenLeft217() - before4
  eq(math.abs(moved4 - 90) <= 3, true,
     "组217④★★★ 连续三次各 30px ⇒ 屏幕总位移 90（实测 " .. string.format("%.1f", moved4) ..
     "；老口径会叠成 ~180 ⇒ 这正是用户看到的「越拖越偏」）")

  -- ⑤ 纵向同样（防止「只修了 x」这种半截修法）
  local b0 = screenBottom217()
  dragBy217(0, 25)
  local dy5 = screenBottom217() - b0
  eq(math.abs(dy5 - 25) <= 1.5, true,
     "组217⑤★★ 纵向位移同样 1:1（实测 " .. string.format("%.1f", dy5) .. " / 期望 25）")

  -- ⑦ ★★★拖到**一半**时这一层自己变了尺寸（真实场景：队伍框/团队框在拖拽中来人或走人 ⇒ 行数变了）：
  --   存档里记的位移必须是**实测屏幕差**，绝不能被「尺寸变化」掺进来 ——
  --   旧口径记的是 `Δ(屏幕底边 + 本地高度 − 相对锚点)`，尺寸一变就把 `Δh` 当成位移记进去
  --   （夹具里 Δh = 48 本地单位 ≈ 38 屏幕像素 ⇒ 再「应用存档」就整整错 38px；这一步专门把这条分开）。
  local recB7 = ((EVAL_DF_TEST_STORE() or {}).PlayerFrame or {})
  local dyBefore7 = tonumber(recB7.dy) or 0
  local bBefore7 = screenBottom217()
  TEST.cursorX, TEST.cursorY = 600, -500
  if type(down217) == "function" then pcall(down217, h217, "LeftButton") end
  FH217 = FH217 + 48                                   -- 拖到一半，层自己长高 48（本地单位）
  TEST.cursorX, TEST.cursorY = 600, -500 + 20
  for _ = 1, 8 do if type(mv217) == "function" then pcall(mv217, h217, 0.05) end end
  if type(up217) == "function" then pcall(up217, h217, "LeftButton") end
  local dyReal7 = screenBottom217() - bBefore7          -- 本次拖拽的**实测屏幕位移**
  local rec7 = (EVAL_DF_TEST_STORE() or {}).PlayerFrame
  eq(type(rec7) == "table" and type(rec7.dy) == "number", true, "组217⑦前置：拖拽结算写下了 dy")
  local dyRec7 = (tonumber(rec7 and rec7.dy) or 0) - dyBefore7   -- 存档里的**增量**
  eq(math.abs(dyRec7 - dyReal7) <= 1.5, true,
     "组217⑦★★★ 存档位移增量 = **实测屏幕差**（存档 " .. string.format("%.1f", dyRec7) ..
     " / 屏幕实测 " .. string.format("%.1f", dyReal7) .. "）：尺寸中途变了也不许掺进来")
  eq(math.abs(dyRec7 - 20) <= 2, true,
     "组217⑦★★ 记的就是光标那 20px（旧口径 = Δ屏幕底边 + Δ本地高度 = 20 + 48 = 68，把 Δh 当成位移）")
  local posBefore7 = screenLeft217()
  offX217, offY217 = offX217 + 77, offY217 + 77        -- 再故意挪歪（模拟漂了）
  EVAL_DF_APPLYALL(true)
  eq(math.abs(screenLeft217() - posBefore7) <= 1.5, true,
     "组217⑦★★ 「应用存档」仍能回到同一屏幕位置（尺寸变过也照样闭环）")

  -- ⑥ 存档里记的是**屏幕**基准与屏幕位移，且「应用存档」能把窗口放回同一屏幕位置
  local rec217 = (EVAL_DF_TEST_STORE() or {}).PlayerFrame
  eq(type(rec217) == "table" and type(rec217.base) == "table" and type(rec217.base.l) == "number", true,
     "组217⑥★★ 存档记下基准的**实测屏幕位置**（base.l：屏幕口径的位移才可复现）")
  local posBefore6 = screenLeft217()
  -- 故意把窗口挪歪 99px（模拟「漂了」：直接改夹具的位置状态，等价于被别的插件拽走/手工拖歪）
  offX217, offY217 = offX217 + 99, offY217 + 99
  eq(math.abs(screenLeft217() - posBefore6) > 10, true,
     "组217⑥前置：把窗口挪歪了 99px（实测 " .. string.format("%.1f", screenLeft217() - posBefore6) .. "）")
  EVAL_DF_APPLYALL(true)   -- 真实的「应用存档」入口
  eq(math.abs(screenLeft217() - posBefore6) <= 1.5, true,
     "组217⑥★★★ 「应用存档」把窗口放回**同一个屏幕位置**（实测 " .. string.format("%.1f", screenLeft217()) ..
     " / 期望 " .. string.format("%.1f", posBefore6) .. "）—— 单位无关的闭环")

  -- 收尾（UIParent 的几何**原值还回**：跨用例状态残留是本项目老坑）
  for k, v in pairs(savedUI217) do rawset(UIParent, k, v) end
  TEST.cursorX, TEST.cursorY = savedCursor217[1], savedCursor217[2]
  TEST.chat = savedChat217
  if type(store217) == "table" then
    store217.dragBars = savedBars217
    store217.PlayerFrame = nil
  end
  EVAL_DF_SET(wasOn217)
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  位移叠加漂移（缩放 0.8 窗口）：单次 40→%.1f · 折算 k=%s · 三次 30 共 90→%.1f · 纵向 25→%.1f · " ..
    "拖到一半改尺寸仍记 20→%.1f（存档增量）· 应用存档回原位",
    d1, tostring(k217), moved4, dy5, dyRec7))
  print("GROUP 217 (拖拽位移按屏幕算 + 量回自证手量折算 + 尺寸中途变化不掺进位移 ⇒ 缩放≠1 的窗口不再叠加漂移): PASS")
end

-- ===== 组 218（1.74.33）：开窗探针 —— 被动窗口「打开时重设属性」的可行性取证工具 =====
-- 用户问题（原话）：「图层拖拽 -> 被动类窗口能否在打开的时候进行自定义属性重设.或者定时重设? 验证可行性 待我确认」
-- ★这一组钉的不是「功能」，而是**取证工具的契约** —— 工具本身错了，真机取证就会得出错结论（比没做更糟）：
--   ① **只读**：探针全程一个写接口都不许碰。做法 = 把夹具的 SetWidth/SetHeight/SetScale/SetAlpha/Show/Hide
--      全包上计数器；「客户端改宽 / 窗口被打开」这些动作由**测试自己**用**原函数**做（做完先清零计数），
--      之后剩下的任何一次写调用都只能是探针干的 ⇒ 必须为 0（这是「只取证、行为零变化」的**哨兵**）。
--   ② **跳变如实记录**：窗口「隐藏→显示」= 开窗事件的唯一可靠证据，且**前后属性都要记**
--      （前 = 我们写进去的值、后 = 客户端改成的值 —— 这一对就是「要不要做开窗重设」的答案）。
--   ③ **开着时被改也记**（attrChange）；**位置**变化单独记 posChange（本项目自己的复查也会动位置，别混算）。
--   ④ **有界自停**：到点必须 on=false **且脚本真被摘掉** —— 本客户端隐藏帧的 OnUpdate 照样触发，
--      只 Hide 不摘 = 永远空转（本项目刚给分享滴出帧记过这条账）。
--   ⑤ 落档三态齐全（phase/rows/caps/events 都在 cfg.dragAttr）+ 命令入口「停 / 看」都真的接上了。
do
  local function n218(v) return tonumber(v) or 0 end
  local cfg218 = rawget(_G, "EVAL_HELP_CONFIG")
  local savedAttr218 = (type(cfg218) == "table") and cfg218.dragAttr or nil
  local store218 = EVAL_DF_TEST_STORE()
  local savedRec218 = (type(store218) == "table") and store218.GuildFrame or nil
  local savedChat218 = TEST.chat
  -- ★夹具必须**自己建**：前面的组收尾时把 `_G["GuildFrame"]` 置回了 nil（本项目「跨用例状态残留」纪律），
  --   这里现建两个被动窗口目标：GuildFrame（设 OnShow ⇒ 验「有」）+ CharacterFrame（不设 ⇒ 验「明确没有」）。
  local gf218 = CreateFrame("Frame", "GuildFrame", UIParent)
  local cf218 = CreateFrame("Frame", "CharacterFrame", UIParent)
  -- ★清解析缓存 ⇒ 探针一定解析到**这两个**夹具（不清的话 `__hitFrame` 还指着别的组留下的旧对象，
  --   于是夹具上做的一切都测不到 —— 「读值口要按稳定键找、别缓存条目对象」同族）
  EVAL_DF_TEST_TARGETS_RESET()
  eq(type(gf218) == "table" and type(cf218) == "table", true,
    "组218前置：两个被动窗口夹具建好（GuildFrame 设 OnShow / CharacterFrame 不设）")

  -- 夹具：① 存档里给这个目标配一份**自定义属性**（探针要拿它和实测对照）
  --       ② 位置接口按真机语义补上（桩的 GetLeft/GetBottom 返回 nil ⇒ 位置类事件就永远测不出来）
  if type(store218) == "table" then
    store218.GuildFrame = { w = 384, h = 512, scale = 0.8, alpha = 1, dx = 0, dy = 0,
      base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 }, l = 120, b = 200 } }
  end
  local posX218, posY218 = 0, 0
  rawset(gf218, "SetPoint", function(_, a1, a2, a3, a4, a5)
    posX218, posY218 = tonumber(a4) or 0, tonumber(a5) or 0
    return true
  end)
  rawset(gf218, "GetLeft", function() return 120 + posX218 end)
  rawset(gf218, "GetBottom", function() return 200 + posY218 end)
  pcall(gf218.SetWidth, gf218, 384)
  pcall(gf218.SetHeight, gf218, 512)
  pcall(gf218.SetScale, gf218, 0.8)
  pcall(gf218.SetAlpha, gf218, 1)
  pcall(gf218.Hide, gf218)
  pcall(gf218.SetScript, gf218, "OnShow", function() end)  -- 模拟「原生**有** OnShow 脚本」的那一半目标

  -- ★写接口计数器：先取到原函数再 rawset 遮蔽（桩的实现在 __index 里，rawset 能盖住它）
  local WR218 = { n = 0 }
  local ORIG218 = {}
  local function wrap218(k)
    ORIG218[k] = gf218[k]
    rawset(gf218, k, function(self, ...)
      WR218.n = WR218.n + 1
      local f = ORIG218[k]
      if type(f) == "function" then return f(self, ...) end
      return nil
    end)
  end
  wrap218("SetWidth") wrap218("SetHeight") wrap218("SetScale") wrap218("SetAlpha")
  wrap218("Show") wrap218("Hide")

  -- ② 真实命令入口武装（判据必须走 SlashCmdList —— 只调生产函数等于没测接线）
  SlashCmdList["EVALHELP"]("go 开窗探针")
  local st218 = EVAL_DF_TEST_ATTR_STATE()
  eq(type(st218) == "table" and st218.on == true, true, "组218②★★★ 真实命令入口（/eh go 开窗探针）能武装探针")
  eq(type(st218) == "table" and st218.tickLive == true, true, "组218②★★ 心跳真的挂上了（OnUpdate 在位）")
  eq(string.find(tostring(TEST.chat or ""), "已武装", 1, true) ~= nil, true,
    "组218②★ 即时回显里给了武装时长与「只读」承诺（用户一眼能判「命令跑到没有」）")
  local cap218 = (type(st218) == "table" and type(st218.caps) == "table") and st218.caps or {}
  eq(type(cap218.targets) == "table" and n218(cap218.n) > 15, true,
    "组218②★ 能力清单覆盖全部被动窗口目标（实测 " .. tostring(cap218.n) .. " 个）")
  local gcap218 = (type(cap218.targets) == "table") and cap218.targets.GuildFrame or nil
  eq(type(gcap218) == "table" and gcap218.onShow == true, true,
    "组218⑥★★ 夹具上设了 OnShow 脚本 ⇒ 清单如实报「有」（有就必须**链式**接管，不许覆盖）")
  eq(n218(cap218.onShowYes) + n218(cap218.onShowNo) + n218(cap218.onShowUnknown) == n218(cap218.n), true,
    "组218⑥★★ OnShow 三态之和 = 目标数（有/明确没有/读不到 三类都要如实分，不许含糊）")
  local noShow218, noShowName218 = nil, nil
  for nm, row in pairs(cap218.targets or {}) do
    if nm ~= "GuildFrame" and row.exists == true and row.onShow == false then
      noShow218, noShowName218 = row, nm break
    end
  end
  eq(noShow218 ~= nil, true,
    "组218⑥★ 反向哨兵：**没设** OnShow 的那个夹具被如实判成「明确没有」（" .. tostring(noShowName218) .. "），不是全判成有")

  -- ③ 基准采样（此刻窗口关着）→ 然后**我们自己**模拟「客户端开窗并把宽改成 500」
  EVAL_DF_TEST_ATTR_STEP(0.25)
  WR218.n = 0
  ORIG218.SetWidth(gf218, 500)
  ORIG218.Show(gf218)
  EVAL_DF_TEST_ATTR_STEP(0.25)
  EVAL_DF_TEST_ATTR_STEP(0.25)
  eq(WR218.n, 0, "组218①★★★ 探针**只读**：全程没碰任何写接口（实测写调用 " .. tostring(WR218.n) .. " 次）")

  local row218 = EVAL_DF_TEST_ATTR_ROW("GuildFrame")
  eq(type(row218) == "table" and n218(row218.opens) == 1, true,
    "组218③★★★ 「隐藏→显示」被记成一次开窗事件（opens=" .. tostring(type(row218) == "table" and row218.opens) .. "）")
  local openEv218 = nil
  for _, e in ipairs((EVAL_DF_TEST_ATTR_STATE() or {}).events or {}) do
    if e.name == "GuildFrame" and e.kind == "open" then openEv218 = e break end
  end
  eq(openEv218 ~= nil, true, "组218③★★★ 开窗事件进了事件表（kind=open）")
  eq(type(openEv218) == "table" and type(openEv218.before) == "table" and openEv218.before.w == 384, true,
    "组218③★★ 事件里记下**开窗前的宽**（= 我们写进去的 384；实测 before=" ..
    tostring(type(openEv218) == "table" and openEv218.before and openEv218.before.w) .. "）")
  eq(type(openEv218) == "table" and type(openEv218.after) == "table" and openEv218.after.w == 500, true,
    "组218③★★★ 事件里记下**打开后的宽**（= 客户端改成的 500）—— 这一对值就是「要不要做开窗重设」的答案")

  -- ④ 窗口**还开着**时又被改（客户端随后自己摆尺寸，或者本项目自己的复查动手）
  WR218.n = 0
  ORIG218.SetWidth(gf218, 600)
  EVAL_DF_TEST_ATTR_STEP(0.25)
  local chg218 = nil
  for _, e in ipairs((EVAL_DF_TEST_ATTR_STATE() or {}).events or {}) do
    if e.name == "GuildFrame" and e.kind == "attrChange" then chg218 = e end
  end
  eq(chg218 ~= nil, true, "组218④★★ 窗口**开着**时属性被改也记成 attrChange（不是只记开窗那一刻）")
  eq(string.find(tostring(chg218 and chg218.what or ""), "w:", 1, true) ~= nil, true,
    "组218④★ attrChange 写清了是哪一项变了（" .. tostring(chg218 and chg218.what) .. "）")
  eq(WR218.n, 0, "组218④★ 这一段探针依旧没写（实测 " .. tostring(WR218.n) .. " 次）")

  -- ⑤ 位置变化单独记（本项目自己的有界复查也会动位置 ⇒ 不能与「客户端改属性」混为一谈）
  gf218.SetPoint(gf218, "TOPLEFT", UIParent, "TOPLEFT", 40, -60)
  EVAL_DF_TEST_ATTR_STEP(0.25)
  local posEv218 = nil
  for _, e in ipairs((EVAL_DF_TEST_ATTR_STATE() or {}).events or {}) do
    if e.name == "GuildFrame" and e.kind == "posChange" then posEv218 = e end
  end
  eq(posEv218 ~= nil, true, "组218⑤★★ 位置变化记成 posChange（与 attrChange 分开，免得把「自己在重锚」误当成「客户端覆盖」）")

  -- ⑦ 有界自停（60 秒上限）：到点必须停 **且摘脚本**
  for _ = 1, 10 do EVAL_DF_TEST_ATTR_TICK(10) end
  local stEnd218 = EVAL_DF_TEST_ATTR_STATE()
  eq(type(stEnd218) == "table" and stEnd218.on == false, true, "组218⑦★★★ 到点自停（上限 " .. tostring(60) .. " 秒）")
  eq(type(stEnd218) == "table" and stEnd218.tickLive == false, true,
    "组218⑦★★★ 自停时**脚本被摘掉**（隐藏帧的 OnUpdate 照样触发 ⇒ 只 Hide = 永远空转）")
  eq(type(stEnd218) == "table" and stEnd218.why == "timeout", true,
    "组218⑦★ 停止原因如实报 timeout（实测 " .. tostring(type(stEnd218) == "table" and stEnd218.why) .. "）")

  -- ⑧ 落档：三态 + 逐目标行 + 计数汇总
  local d218 = (type(cfg218) == "table") and cfg218.dragAttr or nil
  eq(type(d218) == "table" and d218.phase == "done", true, "组218⑧★★★ 跑完写 phase=\"done\"（三态：start/error/done）")
  local r218 = (type(d218) == "table" and type(d218.rows) == "table") and d218.rows.GuildFrame or nil
  eq(type(r218) == "table", true, "组218⑧★★ 落档里有逐目标行（存档要的 vs 关着时 vs 打开后）")
  eq(type(r218) == "table" and type(r218.saved) == "table" and r218.saved.scale == 0.8, true,
    "组218⑧★★ 行里记下「存档要的」属性（缩放 0.8 那条）")
  eq(type(r218) == "table" and type(r218.badOpen) == "table" and table.getn(r218.badOpen) > 0, true,
    "组218⑧★★★ 行里如实标出「打开后与存档不符」的项（" ..
    tostring(type(r218) == "table" and table.concat(r218.badOpen, " · ") or "?") .. "）")
  eq(type(d218) == "table" and d218.openMismatch ~= nil and d218.armOK ~= nil and d218.openOK ~= nil, true,
    "组218⑧★ 落档里有计数汇总（关着时 / 打开后 各几个一致、几个不一致）")
  eq(type(d218) == "table" and type(d218.caps) == "table" and type(d218.events) == "table", true,
    "组218⑧★ 落档里同时带走了能力清单与事件表（/reload 后一次读全）")
  eq(string.find(tostring(TEST.chat or ""), "打开后", 1, true) ~= nil, true,
    "组218⑧★ 播报里有一行「打开后 vs 存档」的结论（用户不必翻存档就能看到答案）")

  -- ⑨ 命令「停 / 看」两条路
  TEST.chat = nil
  SlashCmdList["EVALHELP"]("go 开窗探针 停")
  eq(string.find(tostring(TEST.chat or ""), "已经结束", 1, true) ~= nil, true,
    "组218⑨★★ 已经停了之后再按「停」⇒ 如实说「这一轮已经结束了」（不假装重跑一遍）")
  SlashCmdList["EVALHELP"]("go 开窗探针")
  local stRe218 = EVAL_DF_TEST_ATTR_STATE()
  eq(type(stRe218) == "table" and stRe218.on == true, true, "组218⑨★★ 停掉之后可以重新武装（工具可重复使用）")
  eq(type(stRe218) == "table" and stRe218.tickLive == true, true, "组218⑨★ 重新武装后心跳又挂上了")
  SlashCmdList["EVALHELP"]("go 开窗探针 停")
  local stStop218 = EVAL_DF_TEST_ATTR_STATE()
  eq(type(stStop218) == "table" and stStop218.on == false and stStop218.why == "manual", true,
    "组218⑨★★ 「停」= 提前收工，原因如实记 manual（实测 " .. tostring(type(stStop218) == "table" and stStop218.why) .. "）")
  TEST.chat = nil
  SlashCmdList["EVALHELP"]("go 开窗探针 看")
  eq(string.find(tostring(TEST.chat or ""), "开窗探针结果", 1, true) ~= nil, true,
    "组218⑨★★ 「看」复读上次落档的结果（用户不必去翻 SavedVariables）")

  -- ⑩ ★★★口径（第一轮真机取证当场量出来的，此前不知道）：本客户端 `GetWidth/GetHeight` 返回**含缩放**的尺寸
  --   ⇒ 「存档要 384×512 / 缩放 0.8」而实测读回 307.2×409.6 **必须判「折算后一致」**，不许假报「被客户端覆盖」。
  --   （第一轮真机就靠这条避免误判：属性窗口原生 384×512 + 我们设的缩放 0.7 ⇒ 读回 268.8×358.4，一旦配了宽高
  --     而没有这条折算，就会把「缩放已生效」误读成「客户端把尺寸改回去了」。）
  TEST.chat = nil
  local ogW218, ogH218 = gf218.GetWidth, gf218.GetHeight
  rawset(gf218, "GetWidth", function() return 384 * 0.8 end)    -- 模拟真机：读数含缩放
  rawset(gf218, "GetHeight", function() return 512 * 0.8 end)
  SlashCmdList["EVALHELP"]("go 开窗探针")                        -- 重新武装（caps 取的就是当前读数）
  EVAL_DF_TEST_ATTR_STEP(0.25)
  SlashCmdList["EVALHELP"]("go 开窗探针 停")                     -- 停 ⇒ 落档（行里才有 badArm/foldedArm）
  local d10 = (type(cfg218) == "table") and cfg218.dragAttr or nil
  local r10 = (type(d10) == "table" and type(d10.rows) == "table") and d10.rows.GuildFrame or nil
  eq(type(r10) == "table" and type(r10.badArm) == "table" and table.getn(r10.badArm) == 0, true,
    "组218⑩★★★ 宽高读数含缩放 ⇒ **不判**「与存档不符」（实测 " ..
    tostring(type(r10) == "table" and table.concat(r10.badArm, " · ")) .. "）")
  eq(type(r10) == "table" and type(r10.foldedArm) == "table" and table.getn(r10.foldedArm) > 0, true,
    "组218⑩★★★ 但要**如实写出来**「折算后一致」（" ..
    tostring(type(r10) == "table" and table.concat(r10.foldedArm, " · ")) .. "）")
  eq(type(d10) == "table" and tonumber(d10.foldedN) ~= nil and d10.foldedN > 0, true,
    "组218⑩★★ 落档里有折算一致的计数 foldedN（与「真不符」严格分开，不混进 openMismatch/armMismatch）")
  eq(string.find(tostring(TEST.chat or ""), "含缩放", 1, true) ~= nil, true,
    "组218⑩★ 播报里单独一行说明「读数含缩放」（用户不会把它误读成被客户端覆盖）")
  rawset(gf218, "GetWidth", ogW218)
  rawset(gf218, "GetHeight", ogH218)

  -- 收尾：写接口原样还回、夹具与存档还原、探针状态清空（跨用例残留是本项目老坑）
  rawset(gf218, "SetWidth", ORIG218.SetWidth) rawset(gf218, "SetHeight", ORIG218.SetHeight)
  rawset(gf218, "SetScale", ORIG218.SetScale) rawset(gf218, "SetAlpha", ORIG218.SetAlpha)
  rawset(gf218, "Show", ORIG218.Show) rawset(gf218, "Hide", ORIG218.Hide)
  if type(store218) == "table" then store218.GuildFrame = savedRec218 end
  if type(cfg218) == "table" then cfg218.dragAttr = savedAttr218 end
  TEST.chat = savedChat218
  EVAL_DF_TEST_RESET_TIMERS()
  -- ★夹具按前面各组的收尾口径还回去（下一个人/下一次运行不该看到我们留下的帧）
  _G["GuildFrame"] = nil
  _G["CharacterFrame"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  开窗探针：目标 %s 个 · OnShow 有 %s / 无 %s / 读不到 %s · 开窗事件 %s 次（写调用 %d 次）· 到点自停 %s · 落档 phase=%s",
    tostring(cap218.n), tostring(cap218.onShowYes), tostring(cap218.onShowNo), tostring(cap218.onShowUnknown),
    tostring(row218 and row218.opens), WR218.n, tostring(type(stEnd218) == "table" and not stEnd218.on),
    tostring(type(d218) == "table" and d218.phase)))
  print("GROUP 218 (开窗探针：只读哨兵 + 显隐跳变/属性变化如实记录 + 有界自停摘脚本 + 三态落档 + 命令停/看): PASS")
end

-- ===== 组 220（1.74.33）：被动窗口「不许改宽高」+ 方案 A（链式 OnShow）+ 方案 C（开窗后短复查）=====
-- 用户两条明确要求：
--   ① 「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度.UI 会撕裂」（附截图：法术书撕裂）
--   ② 「A+C 分析实施」
-- ★这一组钉的是「被动窗口不许被改坏」这条**硬约束**与 A/C 两条新机制的真实行为：
--   ① noSize 唯一真值（icon 目标全有、非 icon 目标没有）
--   ② 属性弹窗对被动窗口**藏起宽/高两行**并显示说明（对非被动目标是 5 行）
--   ③ `dfAttrsApply` 对被动窗口**一个宽高写调用都不发**（写接口计数器；同时证明它没「整段不干活」）
--   ④ 老记录里的宽高被**清理并还原原尺寸**（用户撕裂的根因就是存档里还留着 w/h）
--   ⑤ A：链式 OnShow —— **原生脚本必须被先调用**（用「原生把 scale 设成 1.0 / 我们再设回 0.8」验顺序）
--   ⑥ A：幂等 + 被换掉后重新链（链的是**最新那个**原生脚本）
--   ⑦ 关掉功能 ⇒ OnShow **完全还回原生**（不留我们的钩子）
--   ⑧ C：开窗后盯着的那一两秒里能**修回**被改的值，且到点**自停并摘脚本**
--   ⑨ C：战斗中**跳过**（不碰受保护帧属性；拖拽中同样跳过）
do
  local function n219(v) return tonumber(v) or 0 end
  -- 现读一个数值接口（读不到就 nil，不编值）
  local function numOf219(fr, fn)
    if type(fr[fn]) ~= "function" then return nil end
    local ok, v = pcall(fr[fn], fr)
    if ok and tonumber(v) then return tonumber(v) end
    return nil
  end
  -- 关掉属性弹窗：走**它自己的取消按钮**（真实单一出口，不自己 Hide）
  local function popHide219()
    local p = EVAL_DF_TEST_POP()
    local c = p and p.cancel
    if c then
      local f = c:GetScript("OnClick")
      if type(f) == "function" then pcall(f, c) return true end
    end
    return false
  end
  local cfg219 = rawget(_G, "EVAL_HELP_CONFIG")
  local store219 = EVAL_DF_TEST_STORE()
  local savedRec219 = (type(store219) == "table") and store219.GuildFrame or nil
  local savedRecP219 = (type(store219) == "table") and store219.PlayerFrame or nil
  local savedChat219 = TEST.chat
  local savedCombat219 = TEST.inCombat
  local wasOn219 = EVAL_DF_ENABLED()

  -- 夹具：被动窗口（GuildFrame）+ 普通目标（PlayerFrame）各一个；★自己建（前面各组收尾会把 _G 里的帧清掉）
  local gf219 = CreateFrame("Frame", "GuildFrame", UIParent)
  local pf219 = CreateFrame("Frame", "PlayerFrame", UIParent)
  EVAL_DF_TEST_TARGETS_RESET()   -- 清解析缓存 ⇒ 一定解析到这两个夹具
  pcall(gf219.Show, gf219)
  pcall(gf219.SetScale, gf219, 1)
  pcall(gf219.SetAlpha, gf219, 1)
  EVAL_DF_SET(true)

  -- ① noSize 唯一真值（★1.74.33 用户第二次澄清：**所有窗口**都不能改宽高 ⇒ 现在每个目标都带）
  local raw219 = EVAL_DF_TEST_TARGETS_RAW()
  local allN219, allNoSize219, iconN219, iconNoSize219 = 0, 0, 0, 0
  for _, t in ipairs(raw219) do
    allN219 = allN219 + 1
    if t.noSize == true then allNoSize219 = allNoSize219 + 1 end
    if t.icon == true then
      iconN219 = iconN219 + 1
      if t.noSize == true then iconNoSize219 = iconNoSize219 + 1 end
    end
  end
  eq(allN219 > 20 and allNoSize219 == allN219, true,
    "组220①★★★ **每个**目标都带 noSize（" .. tostring(allNoSize219) .. "/" .. tostring(allN219) ..
    "）—— 用户第二次澄清：所有窗口都不能改宽高")
  eq(iconN219 > 15 and iconNoSize219 == iconN219, true,
    "组220①★★ 被动窗口那批也在其中（" .. tostring(iconNoSize219) .. "/" .. tostring(iconN219) .. "）")

  -- ② 属性弹窗：被动窗口藏宽/高行、显示说明；普通目标 5 行全在
  local storeN219 = EVAL_DF_TEST_STORE()
  if type(storeN219) == "table" then
    storeN219.GuildFrame = { scale = 0.8, base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 }, l = 100, b = 200 } }
    storeN219.PlayerFrame = { scale = 0.8, base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 }, l = 100, b = 200 } }
  end
  EVAL_DF_TEST_POP_FOR("GuildFrame")
  local pop219 = EVAL_DF_TEST_POP()
  local rowW219 = pop219 and pop219.rowBy and pop219.rowBy.w
  local rowH219 = pop219 and pop219.rowBy and pop219.rowBy.h
  -- ★★★1.74.33 用户第二次澄清后：宽/高两行**根本不创建**（不是藏起来）——「所有窗口都不能调整宽高」
  eq(pop219 ~= nil and pop219.rowBy ~= nil, true, "组220②前置：弹窗有按 key 的行表（读值口在）")
  local hid220 = (rowW219 == nil and rowH219 == nil) and true or false
  eq(hid220, true, "组220②★★★ 属性弹窗**不再创建**宽/高两行（实测 rowBy.w=" .. tostring(rowW219) ..
    " rowBy.h=" .. tostring(rowH219) .. "）")
  eq(pop219 and pop219.rowBy and pop219.rowBy.scale ~= nil and pop219.rowBy.alpha ~= nil
    and pop219.rowBy.show ~= nil, true,
    "组220②★★ 只砍宽/高：显隐/缩放/透明度三行照旧在（别把别的也砍了）")
  -- ★1.74.33 用户（截图：说明文字与 取消/保存 重叠）：「可以将信息在外部触发图标tooltip 内展示」
  --   ⇒ 弹窗里不再有说明控件；信息改挂图标 tooltip（结构与判据同时在组 206① 里钉住）
  eq(pop219 == nil or pop219.note == nil, true,
    "组220②★★★ 弹窗里**没有**说明文字控件（说明已搬到图标 tooltip ⇒ 不会与底部按钮重叠）")
  EVAL_DF_TEST_POP_FOR("PlayerFrame")
  local pop2_219 = EVAL_DF_TEST_POP()
  eq(pop2_219 and pop2_219.rowBy and pop2_219.rowBy.w == nil and pop2_219.rowBy.h == nil, true,
    "组220②★★★ 普通目标（非被动窗口）**也没有**宽/高行（口径已收窄到所有窗口）")
  popHide219()

  -- ③ dfAttrsApply **对任何目标**都不写宽/高（不是只对被动窗口）；但缩放照写（不是「整段不干活」）
  local W219 = { w = 0, h = 0, scale = 0 }
  local ORIG219 = {}
  local function wrap219(fr, k, tag)
    ORIG219[tag] = fr[k]
    rawset(fr, k, function(self, ...)
      W219[tag] = W219[tag] + 1
      local f = ORIG219[tag]
      if type(f) == "function" then return f(self, ...) end
      return nil
    end)
  end
  wrap219(gf219, "SetWidth", "w") wrap219(gf219, "SetHeight", "h") wrap219(gf219, "SetScale", "scale")
  wrap219(pf219, "SetWidth", "w2") wrap219(pf219, "SetHeight", "h2") wrap219(pf219, "SetScale", "scale2")
  W219.w2, W219.h2, W219.scale2 = 0, 0, 0
  if type(storeN219) == "table" then
    -- ★构造「老记录里确实存着宽高」的最坏情形（用户撕裂的根因），**两个目标都给**
    storeN219.GuildFrame.w, storeN219.GuildFrame.h = 500, 600
    storeN219.GuildFrame.ow, storeN219.GuildFrame.oh = 384, 512
    storeN219.PlayerFrame.w, storeN219.PlayerFrame.h = 500, 600
    storeN219.PlayerFrame.ow, storeN219.PlayerFrame.oh = 384, 512
  end
  EVAL_DF_APPLYALL(true)
  local sizeW = W219.w + W219.w2
  local sizeH = W219.h + W219.h2
  eq(sizeW == 0 and sizeH == 0, true,
    "组220③★★★ 应用存档**一个宽高写调用都不发**（图标目标 " .. tostring(W219.w) .. "+" .. tostring(W219.h) ..
    " · 普通目标 " .. tostring(W219.w2) .. "+" .. tostring(W219.h2) .. "）—— 所有窗口都不许改宽高")
  eq(W219.scale >= 1 and W219.scale2 >= 1, true,
    "组220③★★ 同一轮里缩放照写（" .. tostring(W219.scale) .. "/" .. tostring(W219.scale2) ..
    "）—— 证明不是「整段没干活」的假绿")
  local sizeWrites220 = sizeW + sizeH   -- ★也在这一刻取（后面的清理会调 SetWidth/SetHeight 还原原尺寸）

  -- ④ 老记录的宽高被清理 + 原尺寸还原（**所有目标**，不只是被动窗口）
  local nClean219, restored219 = EVAL_DF_SIZE_CLEAN(true)
  local recG219 = (type(storeN219) == "table") and storeN219.GuildFrame or nil
  local recP219 = (type(storeN219) == "table") and storeN219.PlayerFrame or nil
  eq(nClean219 >= 2, true, "组220④★★★ 清理覆盖**所有**留着宽高的窗口（实测 " .. tostring(nClean219) .. " 个）")
  eq(restored219 >= 4, true, "组220④★★★ 有原始值 ⇒ 每个目标宽高都还原（实测 " .. tostring(restored219) .. " 项）")
  eq(type(recG219) == "table" and recG219.w == nil and recG219.h == nil and recG219.ow == nil and recG219.oh == nil, true,
    "组220④★★★ 图标目标的宽/高/原始值都清干净（留着只会有「以为设了其实被停用」的静默状态）")
  eq(type(recP219) == "table" and recP219.w == nil and recP219.h == nil and recP219.ow == nil and recP219.oh == nil, true,
    "组220④★★★ 普通目标同样被清干净（口径是「所有窗口」）")
  eq(numOf219(gf219, "GetWidth") == 384, true,
    "组220④★★ 帧宽真的回到原始值 384（实测 " .. tostring(numOf219(gf219, "GetWidth")) .. "）")
  rawset(gf219, "SetWidth", ORIG219.w) rawset(gf219, "SetHeight", ORIG219.h) rawset(gf219, "SetScale", ORIG219.scale)
  rawset(pf219, "SetWidth", ORIG219.w2) rawset(pf219, "SetHeight", ORIG219.h2) rawset(pf219, "SetScale", ORIG219.scale2)

  -- ⑤ A：链式 OnShow —— 原生先跑，我们再重设（顺序用「原生把 scale 设成 1.0 ⇒ 我们设回 0.8」来验）
  local origCalls219 = 0
  local ORIG_ONSHOW219 = function(self)
    origCalls219 = origCalls219 + 1
    pcall(self.SetScale, self, 1.0)     -- ★原生开窗逻辑会把缩放摆回 1.0（模拟客户端自己的行为）
  end
  pcall(gf219.SetScript, gf219, "OnShow", ORIG_ONSHOW219)
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_REFRESH()
  local hook219 = EVAL_DF_TEST_OPEN_HOOK("GuildFrame")
  eq(type(hook219) == "table" and hook219.hooked == true, true, "组220⑤★★★ 刷新后 OnShow 被换成我们的链（方案 A 装上了）")
  eq(type(hook219) == "table" and hook219.hasOrig == true, true, "组220⑤★★★ 原生脚本被**存下来**了（链式接管的前提）")
  local onShow219 = gf219:GetScript("OnShow")
  eq(type(onShow219) == "function", true, "组220⑤前置：OnShow 上确实挂着函数")
  pcall(onShow219, gf219)              -- ★点火真实脚本（不自己造一个等价调用）
  eq(origCalls219 == 1, true, "组220⑤★★★ **原生脚本被先调用了**（实测 " .. tostring(origCalls219) .. " 次）—— 绝不能覆盖式接管")
  local origCalls220 = origCalls219   -- ★取这一刻的值（后面 ⑥⑦⑧ 还会再触发几次，取晚了播报就是误导数字）
  local sc219 = numOf219(gf219, "GetScale")
  eq(sc219 ~= nil and math.abs(sc219 - 0.8) <= 0.01, true,
    "组220⑤★★★ 我们的重设**在原生之后**跑（原生设 1.0、我们设回 0.8 ⇒ 实测 " .. tostring(sc219) .. "）—— 顺序可判")

  -- ⑥ 幂等 + 被别人换掉后重新链
  local hookN219 = n219(EVAL_DF_TEST_OPEN_STATE().hookedN)
  EVAL_DF_REFRESH()
  eq(n219(EVAL_DF_TEST_OPEN_STATE().hookedN) == hookN219, true,
    "组220⑥★★ 重复刷新**不重复装**（幂等：实测装上数 " .. tostring(EVAL_DF_TEST_OPEN_STATE().hookedN) .. "）")
  local otherCalls219 = 0
  local OTHER_ONSHOW219 = function() otherCalls219 = otherCalls219 + 1 end
  pcall(gf219.SetScript, gf219, "OnShow", OTHER_ONSHOW219)   -- 模拟「别人又把 OnShow 占了」
  EVAL_DF_REFRESH()
  local hook2_219 = EVAL_DF_TEST_OPEN_HOOK("GuildFrame")
  eq(hook2_219 and hook2_219.hooked == true, true, "组220⑥★★★ 被别人换掉后 ⇒ 重新链上（不许静默失效）")
  pcall(gf219:GetScript("OnShow"), gf219)
  eq(otherCalls219 == 1, true,
    "组220⑥★★★ 重新链的是**最新那个**原生脚本（实测被调 " .. tostring(otherCalls219) .. " 次）")

  -- ⑦ 关掉功能 ⇒ OnShow 完全还回原生
  EVAL_DF_SET(false)
  local hook3_219 = EVAL_DF_TEST_OPEN_HOOK("GuildFrame")
  eq(hook3_219 and hook3_219.hooked == false, true, "组220⑦★★★ 主开关关掉 ⇒ 卸链（现在挂的不是我们的）")
  eq(gf219:GetScript("OnShow") == OTHER_ONSHOW219, true,
    "组220⑦★★★ OnShow **还回原生那一个**（完全还原，不留我们的钩子）")
  EVAL_DF_SET(true)

  -- ⑧ C：开窗后把被改的值修回来 + 到点自停摘脚本
  pcall(gf219.SetScript, gf219, "OnShow", ORIG_ONSHOW219)
  EVAL_DF_REFRESH()
  pcall(gf219:GetScript("OnShow"), gf219)      -- 触发一次开窗 ⇒ 装 C
  local stC219 = EVAL_DF_TEST_OPEN_STATE()
  eq(stC219.on == true and stC219.live == true, true, "组220⑧★★★ 开窗后自动武装短复查（心跳在位）")
  pcall(gf219.SetScale, gf219, 1.0)            -- 模拟「客户端开窗后一两帧才把自己的尺寸/缩放摆好」
  local okStep, fixedStep = EVAL_DF_TEST_OPEN_STEP()
  eq(okStep == true and n219(fixedStep) >= 1, true,
    "组220⑧★★★ 复查能**修回**被改的值（实测修 " .. tostring(fixedStep) .. " 个）")
  local sc8 = numOf219(gf219, "GetScale")
  eq(sc8 ~= nil and math.abs(sc8 - 0.8) <= 0.01, true, "组220⑧★★ 缩放回到存档值 0.8（实测 " .. tostring(sc8) .. "）")
  for _ = 1, 8 do EVAL_DF_TEST_OPEN_TICK(0.5) end
  local stC2_219 = EVAL_DF_TEST_OPEN_STATE()
  eq(stC2_219.on == false, true, "组220⑧★★★ 复查窗口**有界自停**（原因 = " .. tostring(stC2_219.why) .. "）")
  eq(stC2_219.live == false, true, "组220⑧★★★ 自停时**脚本被摘掉**（隐藏帧的 OnUpdate 照样触发 ⇒ 只 Hide = 永远空转）")

  -- ⑨ C：战斗中跳过（不碰受保护帧属性）
  TEST.inCombat = true
  EVAL_DF_TEST_OPEN_ARM("GuildFrame")
  pcall(gf219.SetScale, gf219, 1.0)
  EVAL_DF_TEST_OPEN_STEP()
  local sc9 = numOf219(gf219, "GetScale")
  eq(sc9 ~= nil and math.abs(sc9 - 1.0) <= 0.01, true,
    "组220⑨★★★ 战斗中**不碰属性**（实测仍是 " .. tostring(sc9) .. "，没有被抢改）")
  eq(n219(EVAL_DF_TEST_OPEN_STATE().skips) >= 1, true,
    "组220⑨★★ 跳过要**如实记数**（skips=" .. tostring(EVAL_DF_TEST_OPEN_STATE().skips) .. "），不假装做过")
  local skips9 = n219(EVAL_DF_TEST_OPEN_STATE().skips)
  TEST.inCombat = savedCombat219

  -- 收尾
  TEST.chat = savedChat219
  if type(store219) == "table" then
    store219.GuildFrame = savedRec219
    store219.PlayerFrame = savedRecP219
  end
  EVAL_DF_SET(wasOn219)
  EVAL_DF_TEST_RESET_TIMERS()
  _G["GuildFrame"] = nil
  _G["PlayerFrame"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  宽高整体停用 + A+C：noSize %s/%s · 弹窗不再建宽高行 %s · 应用存档写宽高 %d 次 · 清理 %s 个目标 · " ..
    "链式 OnShow 原生先调 %s 次 · 复查修回 %s 个 · 自停 %s · 战斗中跳过 %s 次",
    tostring(allNoSize219), tostring(allN219), tostring(hid220),
    tostring(sizeWrites220), tostring(nClean219), tostring(origCalls220), tostring(fixedStep),
    tostring(not stC2_219.on), tostring(skips9)))
  print("GROUP 220 (宽高对所有窗口整体停用 + A 链式 OnShow（原生先调·幂等·可重链·可还原）+ C 开窗后短复查（能修回·有界自停·战斗跳过）): PASS")
end

-- ===== 组 221（1.74.33）：老记录缺屏幕基准（用户报「拖住移动窗口之后下次打开位置没有正确生效」）=====
-- 真机证据（存档 + 调试日志）：CharacterFrame/FriendsFrame/QuestLogFrame/SpellBookFrame 四条记录的
--   `base.l`/`base.b` **全是 nil** ⇒ 应用侧只能走老口径（把**屏幕量**当 `SetPoint` 的**本地偏移**用），
--   缩放 ≠ 1 的窗口必然偏；而 `dfDragEnd` 只在「锚点数变了」时才换 `rec.base` ⇒ 老记录**永远**补不上基准
--   （日志里每次登录都 `KEEP STOP why=drift fixed=2` 正是这个偏在反复被纠）。
-- ★两条修复各配一条判据：①（应用侧）缺基准时**现场反推**；②（写入侧）拖完把基准**补上**。
-- ★夹具造两个目标：**GuildFrame**（图标目标，页面 ①② 走应用侧）· **PlayerFrame**（有拖拽柄，页面 ③④ 走拖拽）。
do
  local store221 = EVAL_DF_TEST_STORE()
  local savedRecG221 = (type(store221) == "table") and store221.GuildFrame or nil
  local savedRecP221 = (type(store221) == "table") and store221.PlayerFrame or nil
  local wasOn221 = EVAL_DF_ENABLED()
  local savedCursor221 = { TEST.cursorX, TEST.cursorY }

  -- 屏幕与缩放模型（与组 217 同一套：UIParent 左下角故意不在 0，这样「把屏幕量当偏移用」才会真的露出来）
  local UI_L, UI_B, UI_W, UI_H = 200, -300, 1024, 768
  local ES221 = 0.5
  local savedUI221 = {}
  local function patchUI221(name, fn)
    savedUI221[name] = rawget(UIParent, name)
    rawset(UIParent, name, fn)
  end
  patchUI221("GetLeft", function() return UI_L end)
  patchUI221("GetBottom", function() return UI_B end)
  patchUI221("GetWidth", function() return UI_W end)
  patchUI221("GetHeight", function() return UI_H end)
  patchUI221("GetTop", function() return UI_B + UI_H end)
  patchUI221("GetRight", function() return UI_L + UI_W end)

  -- 夹具工厂：造一个「缩放 0.5 的 384×512 窗口」，屏幕位置 = UI + 偏移 × 0.5
  local function fix221(name)
    local FW, FH = 384, 512
    local o = { x = 0, y = 0 }
    local f = {}
    f.fr = CreateFrame("Frame", name, UIParent)
    f.setOff = function(x, y) o.x, o.y = tonumber(x) or 0, tonumber(y) or 0 end
    f.offX = function() return o.x end
    f.top = function() return (UI_B + UI_H) + o.y * ES221 end
    f.left = function() return UI_L + o.x * ES221 end
    f.bot = function() return f.top() - FH * ES221 end
    f.setGeomReadable = function(on)
      rawset(f.fr, "GetWidth", on and function() return FW end or function() return nil end)
      rawset(f.fr, "GetHeight", on and function() return FH end or function() return nil end)
    end
    rawset(f.fr, "SetPoint", function(_, a1, a2, a3, a4, a5)
      if a4 ~= nil then f.setOff(a4, a5) end
      return true
    end)
    rawset(f.fr, "GetPoint", function() return "TOPLEFT", "UIParent", "TOPLEFT", o.x, o.y end)
    rawset(f.fr, "GetNumPoints", function() return 1 end)
    rawset(f.fr, "ClearAllPoints", function() return true end)
    rawset(f.fr, "GetLeft", f.left)
    rawset(f.fr, "GetTop", f.top)
    rawset(f.fr, "GetBottom", f.bot)
    rawset(f.fr, "GetRight", function() return f.left() + FW * ES221 end)
    f.setGeomReadable(true)
    local shown = true
    f.setShown = function(on) shown = on and true or false end
    rawset(f.fr, "Show", function() shown = true return true end)
    rawset(f.fr, "Hide", function() shown = false return true end)
    rawset(f.fr, "IsShown", function() return shown end)
    rawset(f.fr, "GetScale", function() return ES221 end)
    rawset(f.fr, "GetEffectiveScale", function() return ES221 end)
    return f
  end
  local g221 = fix221("GuildFrame")
  local p221 = fix221("PlayerFrame")
  EVAL_DF_TEST_TARGETS_RESET()   -- 清解析缓存 ⇒ 探针/柄一定解析到这两个夹具
  EVAL_DF_SET(true)

  -- ① 老式记录：只有「反算出来的锚点值」、没有实测屏幕基准（真机存档里那四条就是这样）
  --   反算值 200 ⇒ 屏幕 left = UI_L + 200 = 400；再给 dx=100 ⇒ **要的屏幕 left = 500**
  --   （老口径会把 200+100 当**本地偏移** ⇒ 落在 UI_L + 300×0.5 = 350 ⇒ 差 150px，正好分辨新老口径）
  if type(store221) == "table" then
    store221.GuildFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 200, -50 } },
      dx = 100, dy = 20, scale = ES221, cur = { { "TOPLEFT", "UIParent", "TOPLEFT", 200, -50 } } }
  end
  g221.setOff(0, 0)
  EVAL_DF_APPLYALL(true)
  local l221 = g221.left()
  eq(math.abs(l221 - (UI_L + 200 + 100)) <= 1.5, true,
    "组221①★★★ 老记录缺屏幕基准 ⇒ **现场反推**后落准（实测 left=" .. string.format("%.1f", l221) ..
    " / 期望 " .. tostring(UI_L + 200 + 100) .. " = 相对锚点位置+反算基准+位移；老口径会落在 " .. tostring(UI_L + 150) .. "）")

  -- ② 反推不出来（尺寸读不到）⇒ **如实降级**走老路径（不假装能修）
  g221.setGeomReadable(false)
  if type(store221) == "table" then
    store221.GuildFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 200, -50 } },
      dx = 100, dy = 20, scale = ES221 }
  end
  g221.setOff(0, 0)
  EVAL_DF_APPLYALL(true)
  local l221b = g221.left()
  eq(math.abs(l221b - (UI_L + 150)) <= 2, true,
    "组221②★★ 反推不出来（尺寸读不到）⇒ 老实退回老路径（实测 left=" .. string.format("%.1f", l221b) ..
    " / 期望 " .. tostring(UI_L + 150) .. " —— 如实降级，不假装能修）")
  g221.setGeomReadable(true)

  -- ③ 拖一次（走真实拖拽三件套）⇒ 老记录的屏幕基准被**补上**
  if type(store221) == "table" then
    store221.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 200, -50 } },
      dx = 100, dy = 20, scale = ES221 }
  end
  p221.setOff(400, -100)          -- 拖之前窗口在（屏幕 left = UI_L + 200 = 400）
  EVAL_DF_REFRESH()
  local h221 = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(h221 ~= nil, true, "组221③前置：拿到 PlayerFrame 的拖拽柄（非图标目标才有柄）")
  local down221 = h221 and h221:GetScript("OnMouseDown")
  local up221 = h221 and h221:GetScript("OnMouseUp")
  local mv221 = h221 and h221:GetScript("OnUpdate")
  TEST.cursorX, TEST.cursorY = 600, -500
  if type(down221) == "function" then pcall(down221, h221, "LeftButton") end
  TEST.cursorX, TEST.cursorY = 640, -520
  for _ = 1, 8 do if type(mv221) == "function" then pcall(mv221, h221, 0.05) end end
  if type(up221) == "function" then pcall(up221, h221, "LeftButton") end
  local rec221 = (type(store221) == "table") and store221.PlayerFrame or nil
  eq(type(rec221) == "table" and type(rec221.base) == "table" and type(rec221.base.l) == "number"
    and type(rec221.base.b) == "number", true,
    "组221③★★★ 拖完**补上屏幕基准**（base.l=" .. tostring(type(rec221) == "table" and rec221.base and rec221.base.l) .. "）")
  eq(type(rec221) == "table" and rec221.cur == nil, true,
    "组221③★★ 补齐后清掉 rec.cur（屏幕口径不再需要那套「换基准」的补丁）")
  eq(type(rec221) == "table" and rec221.healed == true, true,
    "组221③★★ 如实留下 healed 标记（能查是哪次拖拽补的）")
  eq(type(rec221) == "table" and math.abs((rec221.base.l + (rec221.dx or 0)) - p221.left()) <= 1.5, true,
    "组221③★★★ 补齐后的记录能**精确复现**拖后的位置（base.l+dx=" ..
    tostring(type(rec221) == "table" and (rec221.base.l + (rec221.dx or 0))) .. " vs 实测 " ..
    string.format("%.1f", p221.left()) .. "）")

  -- ④ 补齐之后，**隐藏状态**（= 登录时的真实情形）也能落准 —— 有屏幕基准就不再依赖反推
  --   ★注意：这里**不能**把 GetWidth/GetHeight 也弄成读不到 —— 那会让 dfMeasure 失效，
  --     「量回自证」这一步就没法纠正首猜（第一版就是这么写错的：实测落在首猜值 340，而不是目标 440）。
  p221.setShown(false)
  local want221 = type(rec221) == "table" and ((rec221.base.l or 0) + (rec221.dx or 0)) or 0
  p221.setOff(0, 0)
  EVAL_DF_APPLYALL(true)
  eq(math.abs(p221.left() - want221) <= 1.5, true,
    "组221④★★★ 有屏幕基准的记录在**隐藏时**也落准（实测 left=" .. string.format("%.1f", p221.left()) ..
    " / 期望 " .. string.format("%.1f", want221) .. "；老路径会把屏幕量当本地偏移 ⇒ 落在 320 附近）")
  p221.setShown(true)

  -- 收尾
  for k, v in pairs(savedUI221) do rawset(UIParent, k, v) end
  if type(store221) == "table" then
    store221.GuildFrame = savedRecG221
    store221.PlayerFrame = savedRecP221
  end
  TEST.cursorX, TEST.cursorY = savedCursor221[1], savedCursor221[2]
  EVAL_DF_SET(wasOn221)
  EVAL_DF_TEST_RESET_TIMERS()
  _G["GuildFrame"] = nil
  _G["PlayerFrame"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  老记录基准修复：反推落点 %.1f（期望 %d）· 反推不可用时降级 %.1f · 拖后补齐 base.l=%s · 有基准时落点 %.1f",
    l221, UI_L + 300, l221b, tostring(type(rec221) == "table" and rec221.base and rec221.base.l), p221.left()))
  print("GROUP 221 (老记录缺屏幕基准：应用侧现场反推 + 拖拽结束补齐基准 ⇒ 拖完下次打开位置精确生效): PASS")
end

-- ===== 组 222（1.74.33）：属性配置的 **X/Y 坐标**（用户第二次澄清要的就是这一项）=====
-- 用户原话：「属性配置需要支持调整的是窗口的 x,y 坐标值」+ 选定语义=**绝对屏幕坐标**（X=左边缘、Y=下边缘）、
--   控件=**下拉预设 + [−][+] 微调按钮**（本客户端 EditBox 疑似不渲染 ⇒ 不做打字输入）。
-- ★这一组钉三件事：① 两行真的在、两个微调按钮真的在；② 走**真实下拉/真实微调/真实 [保存]** 之后，
--   目标**屏幕位置**精确等于设定值（±1.5px）；③ 落锚走的是 `dfPlaceFrom`（量回自证 + 手量折算）——
--   ★用「缩放 0.5 的窗口」来区分：若有人图省事把绝对坐标当**本地偏移**直接 SetPoint，落点会是 150 而不是 300。
do
  local store222 = EVAL_DF_TEST_STORE()
  local savedRec222 = (type(store222) == "table") and store222.PlayerFrame or nil
  local wasOn222 = EVAL_DF_ENABLED()
  local savedShift222 = TEST.shiftDown

  -- 屏幕/缩放模型（与组 221 同一套：UIParent 左下角故意不在 0）
  local UI_L, UI_B, UI_W, UI_H = 200, -300, 1024, 768
  local ES222 = 0.5
  local savedUI222 = {}
  local function patchUI222(name, fn)
    savedUI222[name] = rawget(UIParent, name)
    rawset(UIParent, name, fn)
  end
  patchUI222("GetLeft", function() return UI_L end)
  patchUI222("GetBottom", function() return UI_B end)
  patchUI222("GetWidth", function() return UI_W end)
  patchUI222("GetHeight", function() return UI_H end)
  patchUI222("GetTop", function() return UI_B + UI_H end)
  patchUI222("GetRight", function() return UI_L + UI_W end)
  local FW222, FH222 = 384, 512
  local off222 = { x = 0, y = 0 }
  local pf222 = CreateFrame("Frame", "PlayerFrame", UIParent)
  local function left222() return UI_L + off222.x * ES222 end
  local function top222() return (UI_B + UI_H) + off222.y * ES222 end
  local function bot222() return top222() - FH222 * ES222 end
  rawset(pf222, "SetPoint", function(_, a1, a2, a3, a4, a5)
    if a4 ~= nil then off222.x, off222.y = tonumber(a4) or 0, tonumber(a5) or 0 end
    return true
  end)
  rawset(pf222, "GetPoint", function() return "TOPLEFT", "UIParent", "TOPLEFT", off222.x, off222.y end)
  rawset(pf222, "GetNumPoints", function() return 1 end)
  rawset(pf222, "ClearAllPoints", function() return true end)
  rawset(pf222, "GetLeft", left222)
  rawset(pf222, "GetTop", top222)
  rawset(pf222, "GetBottom", bot222)
  rawset(pf222, "GetRight", function() return left222() + FW222 * ES222 end)
  rawset(pf222, "GetWidth", function() return FW222 end)
  rawset(pf222, "GetHeight", function() return FH222 end)
  rawset(pf222, "Show", function() return true end)
  rawset(pf222, "Hide", function() return true end)
  rawset(pf222, "IsShown", function() return true end)
  rawset(pf222, "GetScale", function() return ES222 end)
  rawset(pf222, "GetEffectiveScale", function() return ES222 end)
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_SET(true)
  -- 记录：**老式**（只有反算锚点、没有屏幕基准）⇒ 顺便验「X/Y 在老记录上也能用」（会自动反推基准）
  if type(store222) == "table" then
    store222.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0, scale = ES222 }
  end

  -- ① 两行 + 两个微调按钮都在（真实控件）
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222① 真实入口打开属性弹窗")
  local pop222 = EVAL_DF_TEST_POP()
  local rowX222 = pop222 and pop222.rowBy and pop222.rowBy.x
  local rowY222 = pop222 and pop222.rowBy and pop222.rowBy.y
  eq(type(rowX222) == "table" and type(rowY222) == "table", true, "组222①★★★ 弹窗有 X/Y 两行（按 key 找得到）")
  eq(rowX222 and rowX222.nudgeMinus ~= nil and rowX222.nudgePlus ~= nil
    and rowY222 and rowY222.nudgeMinus ~= nil and rowY222.nudgePlus ~= nil, true,
    "组222①★★★ 每行都带 [−][+] 两个**真实按钮**（用户选定的控件形式）")
  -- 回填 = 目标当前实测屏幕位置（现读，不是存档）；只回填显示、不写 value
  eq(rowX222 and rowX222.value == nil, true, "组222①★★ 回填只改显示、**不写 value**（没动过的项不该被保存固化）")

  -- ② 真实下拉选 X=300 + 真实 [保存] ⇒ 屏幕 X 精确 300
  local function pickText222(row, txt)
    if not (row and row.btn) then return false end
    local okb, fn = pcall(row.btn.GetScript, row.btn, "OnClick")
    if not (okb and type(fn) == "function") then return false end
    fn()
    for _, rb in ipairs(pop222.list and pop222.list.rows or {}) do
      local shown = false
      if type(rb.IsShown) == "function" then
        local oks, v = pcall(rb.IsShown, rb) shown = (oks and v) and true or false
      end
      if shown then
        local okt, t = pcall(rb.text.GetText, rb.text)
        if okt and tostring(t) == txt then
          local okr, fn2 = pcall(rb.GetScript, rb, "OnClick")
          if okr and type(fn2) == "function" then fn2() return row.value ~= nil, row.value end
        end
      end
    end
    return false
  end
  local okX222, valX222 = pickText222(rowX222, "300")
  eq(okX222 == true and tonumber(valX222) == 300, true,
    "组222②★ 真实下拉里选到 X=300（实测 " .. tostring(valX222) .. "）")
  local okSave222 = false
  if pop222 and pop222.save then
    local oks, fn = pcall(pop222.save.GetScript, pop222.save, "OnClick")
    if oks and type(fn) == "function" then pcall(fn) okSave222 = true end
  end
  eq(okSave222, true, "组222②前置：走了真实 [保存]")
  eq(math.abs(left222() - 300) <= 1.5, true,
    "组222②★★★ [保存] 后目标**屏幕 X = 300**（实测 " .. string.format("%.1f", left222()) ..
    "；★若有人把绝对坐标当本地偏移直接 SetPoint，这里会是 150）")
  local rec222 = (type(store222) == "table") and store222.PlayerFrame or nil
  eq(type(rec222) == "table" and type(rec222.base) == "table" and type(rec222.base.l) == "number", true,
    "组222②★★ 老记录的屏幕基准被**反推出来**并存下（base.l=" ..
    tostring(type(rec222) == "table" and rec222.base and rec222.base.l) .. "）")
  eq(type(rec222) == "table" and math.abs((rec222.base.l + (rec222.dx or 0)) - 300) <= 1.5, true,
    "组222②★★★ 存档里记的是「基准 + 屏幕位移」（" ..
    tostring(type(rec222) == "table" and (rec222.base.l + (rec222.dx or 0))) .. " = 目标 X）")

  -- ③ 真实微调按钮：点 [+] 两次 ⇒ 从当前值 +20，保存后屏幕 X = 320
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222③ 重新打开弹窗（拿全新的行对象）")
  pop222 = EVAL_DF_TEST_POP()
  rowX222 = pop222 and pop222.rowBy and pop222.rowBy.x
  local baseNudge222 = rowX222 and rowX222.cur
  eq(type(baseNudge222) == "number", true, "组222③前置：X 行记住了当前值（" .. tostring(baseNudge222) .. "）")
  local oksP, fnP = pcall(rowX222.nudgePlus.GetScript, rowX222.nudgePlus, "OnClick")
  if oksP and type(fnP) == "function" then pcall(fnP) pcall(fnP) end
  eq(tonumber(rowX222.value) == math.floor(baseNudge222 + 20 + 0.5), true,
    "组222③★★★ 微调 [+] 两次 = +20（实测 " .. tostring(rowX222.value) .. "，起点 " .. tostring(baseNudge222) .. "）")
  local oksS, fnS = pcall(pop222.save.GetScript, pop222.save, "OnClick")
  if oksS and type(fnS) == "function" then pcall(fnS) end
  eq(math.abs(left222() - (baseNudge222 + 20)) <= 1.5, true,
    "组222③★★★ 微调后的值也精确生效（实测 X=" .. string.format("%.1f", left222()) ..
    " / 期望 " .. tostring(baseNudge222 + 20) .. "）")

  -- ④ 按住 Shift ⇒ 步长变成 ±1（对缝用）
  TEST.shiftDown = true
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222④ 打开弹窗（Shift 态）")
  pop222 = EVAL_DF_TEST_POP()
  rowY222 = pop222 and pop222.rowBy and pop222.rowBy.y
  local baseY222 = rowY222 and rowY222.cur
  local oksM, fnM = pcall(rowY222.nudgeMinus.GetScript, rowY222.nudgeMinus, "OnClick")
  if oksM and type(fnM) == "function" then pcall(fnM) end
  eq(tonumber(rowY222.value) == math.floor((baseY222 or 0) - 1 + 0.5), true,
    "组222④★★★ 按住 Shift ⇒ [−] 只走 1px（实测 " .. tostring(rowY222.value) .. "，起点 " .. tostring(baseY222) .. "）")
  TEST.shiftDown = savedShift222

  -- ⑤ Y 同样能精确落（绝对坐标，不是相对微调）
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222⑤ 打开弹窗")
  pop222 = EVAL_DF_TEST_POP()
  rowY222 = pop222 and pop222.rowBy and pop222.rowBy.y
  local okY222, valY222 = pickText222(rowY222, "400")
  eq(okY222 == true and tonumber(valY222) == 400, true, "组222⑤★ 下拉里选到 Y=400（实测 " .. tostring(valY222) .. "）")
  -- ★X 的期望值要在**保存前当场捕获**：③ 已经把 X 微调成 320 了，写死 300 会得到一个假失败（第一版就这么写的）
  local xBefore5 = left222()
  local oksS2, fnS2 = pcall(pop222.save.GetScript, pop222.save, "OnClick")
  if oksS2 and type(fnS2) == "function" then pcall(fnS2) end
  eq(math.abs(bot222() - 400) <= 1.5, true,
    "组222⑤★★★ [保存] 后目标**屏幕 Y（下边缘）= 400**（实测 " .. string.format("%.1f", bot222()) .. "）")
  eq(math.abs(left222() - xBefore5) <= 1.5, true,
    "组222⑤★★ 只动 Y 的那次没有把 X 带跑（实测 X=" .. string.format("%.1f", left222()) ..
    " / 保存前 " .. string.format("%.1f", xBefore5) .. "）")

  -- ⑥ 反推不出基准（尺寸读不到）⇒ 如实说「没设」，**不改目标**
  rawset(pf222, "GetWidth", function() return nil end)
  rawset(pf222, "GetHeight", function() return nil end)
  if type(store222) == "table" then
    store222.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0 }
  end
  local xBefore222 = left222()
  TEST.chat = nil
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222⑥ 打开弹窗（几何读不到）")
  pop222 = EVAL_DF_TEST_POP()
  local okX6 = pickText222(pop222 and pop222.rowBy and pop222.rowBy.x, "700")
  local oksS3, fnS3 = pcall(pop222.save.GetScript, pop222.save, "OnClick")
  if oksS3 and type(fnS3) == "function" then pcall(fnS3) end
  eq(math.abs(left222() - xBefore222) <= 1.5, true,
    "组222⑥★★★ 读不到基准 ⇒ **不改目标**（X 仍是 " .. string.format("%.1f", left222()) .. "）")
  eq(string.find(tostring(TEST.chat or ""), "不猜", 1, true) ~= nil, true,
    "组222⑥★★★ 并且如实说明「读不到基准位置 ⇒ 本次没设（不猜位置）」（" .. tostring(TEST.chat) .. "）")
  rawset(pf222, "GetWidth", function() return FW222 end)
  rawset(pf222, "GetHeight", function() return FH222 end)
  local _ = okX6

  -- ⑦ 「属性里的 X/Y 与**自己拖拽**的 X/Y 是同一个值」（用户要求）：真实拖一次 ⇒ 弹窗回填的 X/Y
  --   == 拖后的实测屏幕位置 == 存档 `base.l + dx`（三者同一个绝对屏幕坐标，不是两套口径）
  rawset(pf222, "GetPoint", function() return "TOPLEFT", "UIParent", "TOPLEFT", off222.x, off222.y end)
  rawset(pf222, "GetNumPoints", function() return 1 end)
  rawset(pf222, "ClearAllPoints", function() return true end)
  if type(store222) == "table" then
    store222.PlayerFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0, scale = ES222 }
  end
  off222.x, off222.y = 300, -200
  EVAL_DF_REFRESH()
  local h222 = EVAL_DF_TEST_HANDLE("PlayerFrame")
  eq(h222 ~= nil, true, "组222⑦前置：拿到 PlayerFrame 的拖拽柄（真实拖动那条路）")
  local dn222, up222 = h222 and h222:GetScript("OnMouseDown"), h222 and h222:GetScript("OnMouseUp")
  local mv222 = h222 and h222:GetScript("OnUpdate")
  TEST.cursorX, TEST.cursorY = 600, -500
  if type(dn222) == "function" then pcall(dn222, h222, "LeftButton") end
  TEST.cursorX, TEST.cursorY = 660, -530
  for _ = 1, 8 do if type(mv222) == "function" then pcall(mv222, h222, 0.05) end end
  if type(up222) == "function" then pcall(up222, h222, "LeftButton") end
  local recDrag222 = (type(store222) == "table") and store222.PlayerFrame or nil
  local draggedX222 = left222()
  local draggedY222 = bot222()
  eq(type(recDrag222) == "table" and type(recDrag222.base.l) == "number", true,
    "组222⑦前置：拖完记录里有了屏幕基准（base.l=" ..
    tostring(type(recDrag222) == "table" and recDrag222.base and recDrag222.base.l) .. "）")
  eq(math.abs((recDrag222.base.l + (recDrag222.dx or 0)) - draggedX222) <= 1.5, true,
    "组222⑦★★★ 拖拽记下的就是**绝对屏幕坐标**（base.l+dx=" ..
    tostring(type(recDrag222) == "table" and (recDrag222.base.l + (recDrag222.dx or 0))) ..
    " vs 实测 " .. string.format("%.1f", draggedX222) .. "）")
  eq(EVAL_DF_TEST_POP_FOR("PlayerFrame"), true, "组222⑦ 拖完打开属性弹窗")
  pop222 = EVAL_DF_TEST_POP()
  local xFill222 = pop222 and pop222.rowBy and pop222.rowBy.x and pop222.rowBy.x.cur
  local yFill222 = pop222 and pop222.rowBy and pop222.rowBy.y and pop222.rowBy.y.cur
  eq(type(xFill222) == "number" and math.abs(xFill222 - draggedX222) <= 1.5, true,
    "组222⑦★★★ 属性里的 X 与**拖拽后的位置**是同一个值（X 回填 " .. tostring(xFill222) ..
    " vs 拖后实测 " .. string.format("%.1f", draggedX222) .. "）")
  eq(type(yFill222) == "number" and math.abs(yFill222 - draggedY222) <= 1.5, true,
    "组222⑦★★★ Y 同理（Y 回填 " .. tostring(yFill222) .. " vs 拖后实测 " .. string.format("%.1f", draggedY222) .. "）")
  -- 关窗走**它自己的取消按钮**（真实单一出口；`popHide219` 是组 220 的局部助手，这里够不着）
  local pCancel222 = EVAL_DF_TEST_POP()
  if pCancel222 and pCancel222.cancel then
    local okc, fnc = pcall(pCancel222.cancel.GetScript, pCancel222.cancel, "OnClick")
    if okc and type(fnc) == "function" then pcall(fnc, pCancel222.cancel) end
  end

  -- ⑧ 「关窗再打开之后守护它生效」（用户要求）：用**图标目标**（GuildFrame —— A/C 只挂在被动窗口上）
  --   ① 用属性弹窗把 X/Y 设成 500 / 300 ② 模拟客户端关窗后把它摆到别处（偏移归零）③ 触发真实 OnShow
  --   ⇒ 位置必须被拉回 500 / 300（方案 A 链式接管在干活；随后 C 还会再盯 1.2 秒兜底）
  local gx222 = CreateFrame("Frame", "GuildFrame", UIParent)
  off222.x, off222.y = 0, 0
  rawset(gx222, "SetPoint", function(_, a1, a2, a3, a4, a5)
    if a4 ~= nil then off222.x, off222.y = tonumber(a4) or 0, tonumber(a5) or 0 end
    return true
  end)
  rawset(gx222, "GetPoint", function() return "TOPLEFT", "UIParent", "TOPLEFT", off222.x, off222.y end)
  rawset(gx222, "GetNumPoints", function() return 1 end)
  rawset(gx222, "ClearAllPoints", function() return true end)
  rawset(gx222, "GetLeft", left222)
  rawset(gx222, "GetTop", top222)
  rawset(gx222, "GetBottom", bot222)
  rawset(gx222, "GetRight", function() return left222() + FW222 * ES222 end)
  rawset(gx222, "GetWidth", function() return FW222 end)
  rawset(gx222, "GetHeight", function() return FH222 end)
  rawset(gx222, "Show", function() gx222.dfShownMark = true return true end)
  rawset(gx222, "Hide", function() gx222.dfShownMark = false return true end)
  rawset(gx222, "IsShown", function() return gx222.dfShownMark ~= false end)
  rawset(gx222, "GetScale", function() return ES222 end)
  rawset(gx222, "GetEffectiveScale", function() return ES222 end)
  rawset(gx222, "SetScale", function() return true end)
  rawset(gx222, "SetAlpha", function() return true end)
  if type(store222) == "table" then
    store222.GuildFrame = { base = { { "TOPLEFT", "UIParent", "TOPLEFT", 0, 0 } }, dx = 0, dy = 0, scale = ES222 }
  end
  EVAL_DF_TEST_TARGETS_RESET()
  EVAL_DF_REFRESH()
  eq(EVAL_DF_TEST_OPEN_HOOK("GuildFrame").hooked == true, true,
    "组222⑧前置：图标目标被链式接管（方案 A 在岗）")
  eq(EVAL_DF_TEST_POP_FOR("GuildFrame"), true, "组222⑧ 打开图标目标的属性弹窗")
  pop222 = EVAL_DF_TEST_POP()
  local okX8 = pickText222(pop222 and pop222.rowBy and pop222.rowBy.x, "500")
  local okY8 = pickText222(pop222 and pop222.rowBy and pop222.rowBy.y, "300")
  eq(okX8 == true and okY8 == true, true, "组222⑧ 通过真实下拉把 X/Y 设成 500 / 300")
  local oksS8, fnS8 = pcall(pop222.save.GetScript, pop222.save, "OnClick")
  if oksS8 and type(fnS8) == "function" then pcall(fnS8) end
  eq(math.abs(left222() - 500) <= 1.5, true, "组222⑧★★ 保存后 X=500（实测 " .. string.format("%.1f", left222()) .. "）")
  -- 模拟「客户端关窗后把它摆回自己的位置」（真实证据：第一轮探针看到重开时 left 归零）
  off222.x, off222.y = 0, 0
  eq(math.abs(left222() - 500) > 100, true, "组222⑧前置：模拟关窗后被客户端摆到了别处（X=" ..
    string.format("%.1f", left222()) .. "）")
  local onShow8 = gx222.GetScript and gx222:GetScript("OnShow") or nil
  eq(type(onShow8) == "function", true, "组222⑧前置：OnShow 上挂着我们的链（能点火）")
  if type(onShow8) == "function" then pcall(onShow8, gx222) end
  eq(math.abs(left222() - 500) <= 1.5, true,
    "组222⑧★★★ **重新打开** ⇒ 位置被守护回 X=500（实测 " .. string.format("%.1f", left222()) .. "）")
  eq(math.abs(bot222() - 300) <= 1.5, true,
    "组222⑧★★★ Y 同样被守护回 300（实测 " .. string.format("%.1f", bot222()) .. "）")
  -- 再验一次「C 的兜底」：重开之后又被改动 ⇒ 短复查能拉回来
  local st8 = EVAL_DF_TEST_OPEN_STATE()
  eq(st8.on == true, true, "组222⑧★★ 重开还武装了短复查（C 在岗：实测 runs=" .. tostring(st8.runs) .. "）")
  off222.x = 0
  local _, fixed8 = EVAL_DF_TEST_OPEN_STEP()
  eq(math.abs(left222() - 500) <= 1.5, true,
    "组222⑧★★★ 重开**之后**再被改动，短复查也拉得回来（修 " .. tostring(fixed8) .. " 个，实测 X=" ..
    string.format("%.1f", left222()) .. "）")

  -- 收尾
  for k, v in pairs(savedUI222) do rawset(UIParent, k, v) end
  if type(store222) == "table" then store222.PlayerFrame = savedRec222 end
  TEST.shiftDown = savedShift222
  EVAL_DF_SET(wasOn222)
  EVAL_DF_TEST_RESET_TIMERS()
  _G["PlayerFrame"] = nil
  _G["GuildFrame"] = nil
  EVAL_DF_TEST_TARGETS_RESET()

  print(string.format("  X/Y 绝对坐标：与拖拽同源（回填 %s）· 重开守护回 X=%.1f Y=%.1f · 读不到基准时不改目标",
    tostring(xFill222), left222(), bot222()))
  print("GROUP 222 (属性配置 X/Y：绝对屏幕坐标 + 下拉预设 + [−][+] 微调（Shift ±1）· 落锚走 dfPlaceFrom 量回自证 · 读不到基准不猜): PASS")
end

EVAL_TEST_MOD_DONE("DragFrames") -- ★跑到底的握手（见文件头 ③）：TOOL TEST FILES CHECK 拿它对账
