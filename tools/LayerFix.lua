-- EvalHelp / tools/LayerFix.lua
--
-- 图层隐藏（Layer Hiding，1.75.x 由「图层特殊处理」改名；内部名仍叫 LayerFix）—— **独立工具模块**。
-- 用户要求（1.74.34 原话）：
--   ① 「能否对固定的某个层内的最后2个纹理做特殊处理.比如隐藏这2个纹理」；
--   ② 「可以在工具箱->UI 工具->添加个图层特处理->设置/重置 ,设置功能支持下拉,
--      目前里面添加个动作条狮鹫 ,支持多选.切换显示选中的特殊处理.」；
--   ③ 「以上特殊处理定义规范配置.以后可能还有其他特殊处理, 弹窗下拉UI参考图层拖拽->设置」；
--   ④ 「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.
--      只要加入嵌入点进行函数调用?」
--
-- ★★自包含：自己的**存档子树**（`EVAL_HELP_CONFIG.layerFix`）· 自己的小助手 · 自己的**有界**计时器 ·
--   自己的工具箱行（连界面控件都在这里建）。
-- ★★与「图层拖拽」**零耦合**：本文件不引用 tools/DragFrames.lua 的任何东西，那一侧也一行都不再提特殊处理。
--   （历史：1.74.34 第一版临时寄生在 DragFrames 里 —— 那时借了它现成的帧名解析/复查窗口；功能经真机验证可用后，
--     按用户要求整体搬出来，只留**两处嵌入点**：
--       ① `EvalHelp.lua` 的 VARIABLES_LOADED 里一句 `pcall(EVAL_LF_INSTALL)`；
--       ② 工具箱那一行（模型数据里 `t = "mod"`, `mod = "layerFix"`）+ 渲染段那个通用分支 ——
--          它只按名字取**本文件登记进 `EVAL_TB_MOD_ROWS` 的渲染函数**，Toolbox 内部一行都不知道。）
-- ★纪律：本文件只用**全局桥**（`EVAL_SAY` / `EVAL_LOGLINE` / `EVAL_L` / `EVAL_DD_OPEN` / `EVAL_TB_REFRESH` /
--   `rawget(_G,"EVAL_HELP_CONFIG")` / `rawget(_G,"EVAL_TB_MOD_ROWS")`），绝不引用别人文件里的 local。
--   ★`lfFrameUsable` / `lfObjectType` 这类 5 行守卫与 DragFrames 的同名件是**同族工具**、不是第二份真值
--     （真值 = 各模块自己的定义表与存档；工具函数各写一份不会造成两处口径打架，但**绝不能**各写一份定义表）。
--
-- ── 定义规范（**加一条特殊处理只往 LF_FIXES 里加一项，其余代码一行都不用改**）──────────────
--   key    唯一英文键 = **存档键**（真值 = `EVAL_HELP_CONFIG.layerFix.fix[key] = true`）。
--          ★绝不用序号或显示名当键：加条目 / 换语言都会让老存档错位（本项目「按序号做键」的老坑）。
--   group  下拉分组号（同 EVAL_DF_PICK_MENU：分组标题行走 locked ⇒ 点不到，keys 留空 ⇒ 回调天然跳过）。
--   kind   处理类型（决定用哪个执行器）：现在只有 `"hideTex"` = **隐藏**层内挑出来的纹理（可还原）。
--   layer  目标层 `{ cands = { "帧名", … } }`：本客户端 UI 编译在 pak 里，帧名只能现场探
--          ⇒ 与图层拖拽同口径（按候选顺序取第一个存在的帧；一个都不在 = **如实缺席**：
--            这一次一个对象都不动，也绝不换一个「看起来像」的层动手）。
--   pick   从层里挑哪些对象（二选一）：
--            `{ last = N }`      = 按 `GetRegions()` 顺序取**最后 N 个纹理**（用户 1.74.34 的口径）
--            `{ path = "子串" }` = 按贴图路径（小写包含）匹配（**更稳**；拿到真机路径后再启用）
--   label / tip  取词函数，**必须写成 `function() return L("键") end`**：
--          ① 键的字面量出现在源码里 ⇒ `LANG KEY CHECK` 看得见（否则这条键缺语言包也没人管）；
--          ② 每次现取 ⇒ 换语言后菜单立刻是新语言（写成加载期字符串就会绑死当时那一种语言）。
--
-- ── 三条诚实性硬规矩（真机上都会直接看到后果，所以写死在实现里）──
--   ① 层不在 / 层里纹理数少于要处理的个数 ⇒ **一个对象都不动**，并如实播报「没做成 + 这次没动界面」；
--   ② 原始状态是**三态**：true=读到了显示 / false=读到了隐藏 / **nil=读不到 ⇒ 还原时按「显示」还原**
--      （把「读不到」当 false 的后果，正是用户看到的「重置了但贴图没回来」）；
--   ③ **客户端自己藏着的**元素，还原时绝不用 `Show` 把它弄出来。
--
-- ── 执行时刻（三处，全都有界）──
--   ① 勾上 / 取消**当场**生效或还原（工具箱那个多选下拉每点一下就调一次 `EVAL_LF_SYNC`）；
--   ② 载入期 `EVAL_LF_INSTALL`（= 重进游戏照样生效 = 守护）；
--   ③ 启动期**有界**复查窗口（本模块自己的 tick：`LF_KEEP_PERIOD`×`LF_KEEP_CHECKS`，墙钟上限 `LF_KEEP_WALL`）
--      里补一次 —— 覆盖「层还没建出来」与「客户端自己又把它显示回来」，窗口结束**摘掉脚本**即停
--      （**不做常驻轮询**，与框拖拽的位置复查同一纪律）。
-- ★★★模块必须**自带**本地化取词：项目里 `L` 一律是**文件局部**（没有全局 L），
--   裸调 `L(...)` 在工具箱里会被 `pcall(fn, r, it)` 吞掉 ⇒ 表现是「按钮文案没设上 / 点了没反应」而面板正常。
--   写法与 tools/ConsumableHelper.lua / DismountHelper.lua / HunterHelper.lua 完全一致（走全局 EVAL_L）。
-- ★★★1.74.36-2：模块**必须自带** `say` / `logLine` —— 项目里这两个名字**只在 Core.lua / Toolbox.lua 里是 local**，
--   模块里裸调得到的是全局 nil：轻则「如实播报」全部静默消失，重则整段代码在 pcall 里直接报错退出。
--   走 Core.lua 末尾的全局桥：`EVAL_SAY = say` / `EVAL_LOGLINE = logLine`（与 ConsumableHelper 的 chSay 同一写法）。
local function say(msg)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end
local function logLine(msg)
  if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, tostring(msg)) end
end

local function L(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end

local say, logLine = EVAL_SAY, EVAL_LOGLINE
local L = EVAL_L

-- ============ 常量 ============
local LF_TIP_W = 460          -- tooltip 最小宽度（与工具箱其它行的口径一致：TB_LD_TIP_W = 460）
local LF_KEEP_PERIOD = 1.0    -- 启动期复查周期（秒）
local LF_KEEP_CHECKS = 5      -- 净检查次数上限（5 × 1s ⇒ 载入完成后 5 秒内收工）
local LF_KEEP_WALL = 15.0     -- 绝对墙钟上限（秒）：从「武装」那一刻起算，任何情况都不许超过它

-- ============ 处理定义表（**唯一来源**）============
local LF_FIXES = {
  {
    key = "gryphon", group = 1, kind = "hideTex",
    -- ★层真名有**本地证据**（用户真机截图）：容器是 `MainMenuBar` 的子帧 `MainMenuBarArtFrame`（717x37），
    --   它 `GetRegions()` 前 6 条是 `纹理:Texture`、第 7 条是 `字体串` ⇒ 候选第一项就是它。
    --   `MainMenuBar` 只作兜底（万一某版客户端把美术件直接挂在父帧上）；**命中哪个名字会如实播报**。
    --   ★现状：`last = 2`（用户口径）已真机验证「两端的狮鹫贴图被隐藏」；若将来客户端改了区域顺序，
    --     把这里换成 `pick = { path = "……" }`（按贴图路径匹配）即可 —— 引擎已支持，**不需要改代码**。
    layer = { cands = { "MainMenuBarArtFrame", "MainMenuBar" } },
    pick = { last = 2 },
    label = function() return L("TB_FIX_GRYPHON") end,
    tip = function() return L("TB_FIX_GRYPHON_TIP") end,
  },
}
-- 分组标题（下拉里那几行「—— xxx ——」；没有的分组号 → 显示 "?"，不静默）
local LF_FIX_GROUPS = {
  [1] = function() return L("TB_FIX_G1") end,
}

-- ============ 状态 ============
local LF = {
  installed = false,   -- EVAL_LF_INSTALL 跑过没有
  fixState = {},       -- 已生效的记账（**只在内存里**：存的是对象身份，不能落存档）
  fixApplied = 0,      -- 累计「新生效」过几次（诊断用）
  fixRehide = 0,       -- 累计「客户端又显示回来 → 再藏一次」的对象数（守护的实证）
  keepFrame = nil,     -- 启动期复查 tick 帧
  keepAcc = 0,         -- 周期累加
  keepAge = 0,         -- 已过去墙钟秒数
  keepRuns = 0,        -- 已完成的净检查次数
  keepLate = 0,        -- 本次窗口累计「补生效」条数（层晚出现）
  keepRe = 0,          -- 本次窗口累计「再藏回去」的对象数（守护）
  keepDone = true,     -- 是否已停（初始 true = 还没武装过）
  keepWhy = nil,       -- 结束原因
  keepArmed = nil,     -- 这次窗口被谁武装的（诊断用）
  retryFrame = nil,    -- 存档未就位时的有界重试帧
}

-- ============ 小助手（同族工具；见文件头「纪律」那段）============
local function lfNum(v, d)
  if type(v) == "number" then return v end
  local n = tonumber(v)
  if n then return n end
  return d
end

local function lfLog(msg)
  if type(logLine) == "function" then pcall(logLine, "[LF] " .. tostring(msg)) end
end

-- 宿主帧：**不能挂 UIParent**（开全屏地图会隐藏 UIParent → tick 跟着停）；WorldFrame 恒在。
local function lfHost()
  local wf = rawget(_G, "WorldFrame")
  if type(wf) == "table" or type(wf) == "userdata" then return wf end
  return rawget(_G, "UIParent")
end

local function lfFrameOf(name)
  local f = rawget(_G, name)
  if type(f) == "table" or type(f) == "userdata" then return f end
  return nil
end

-- 「能不能当帧/区域用」的安全探测：`_G` 里有些全局是**不可索引的 userdata**，
--   一句 `f.GetRegions` 就抛错、会把整段逻辑打断（真机原样报错：`attempt to index local 'f' (a userdata value)`）。
--   ★帧与区域都认：探测两个**所有帧/区域都有**的方法，任一能取到就算可用。
local function lfFrameUsable(f)
  if type(f) == "table" then return true end -- 普通表（含测试桩）：索引安全
  if type(f) ~= "userdata" then return false end
  local ok, v = pcall(function() return f.GetObjectType end)
  if ok and type(v) == "function" then return true end
  local ok2, v2 = pcall(function() return f.GetParent end)
  return (ok2 and type(v2) == "function") and true or false
end

-- 对象类型（Texture / FontString / Frame …）；拿不到返回 **nil**（调用方不许据此丢弃 —— 见「查不到 ≠ 没有」）
local function lfObjectType(f)
  if not lfFrameUsable(f) then return nil end
  local ok, v = pcall(function() return f.GetObjectType end)
  if not (ok and type(v) == "function") then return nil end
  local ok2, t = pcall(v, f)
  if ok2 and type(t) == "string" then return t end
  return nil
end

-- ============ 存档（本模块自己的子树）============
-- 真值：`EVAL_HELP_CONFIG.layerFix.fix[key] = true`；★表不存在 = **一条都不选**
--   （与「图层选择」的「表不存在 = 全选」**相反**：特殊处理会改客户端界面，绝不能因为升级/加条目就自动生效）
local function lfStore(create)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  local s = c.layerFix
  if type(s) ~= "table" then
    if not create then return nil end
    s = {}
    c.layerFix = s
  end
  return s
end

local function lfFixTbl(create)
  local store = lfStore(create)
  if not store then return nil end
  local t = store.fix
  if type(t) ~= "table" then
    if not create then return nil end
    t = {}
    store.fix = t
  end
  return t
end

local function lfFixOn(key)
  local t = lfFixTbl(false)
  if type(t) ~= "table" then return false end
  return (t[key] == true)
end

-- 按 key 找一条处理（**唯一入口**：菜单 / 执行 / 写入口 / 读值口都走它，别处不许再遍历一遍 LF_FIXES）
local function lfFixOf(key)
  if type(key) ~= "string" or key == "" then return nil end
  for i = 1, table.getn(LF_FIXES) do
    if LF_FIXES[i].key == key then return LF_FIXES[i] end
  end
  return nil
end

-- 取词（**现取**；取不到退回 key —— 绝不显示空白，也绝不显示 nil）
local function lfFixWord(f, which)
  local fn = (type(f) == "table") and f[which] or nil
  if type(fn) == "function" then
    local ok, v = pcall(fn)
    if ok and type(v) == "string" and v ~= "" then return v end
  end
  return tostring((type(f) == "table") and f.key or "?")
end

-- 目标层：按候选顺序取**第一个存在的帧**；命中名一并交出（播报 / 诊断要用）
local function lfFixLayer(fix)
  local cands = (type(fix) == "table" and type(fix.layer) == "table") and fix.layer.cands or nil
  if type(cands) ~= "table" then return nil, nil end
  for i = 1, table.getn(cands) do
    local nm = cands[i]
    local fr = lfFrameOf(nm)
    if fr then return fr, nm end
  end
  return nil, nil
end

-- 贴图路径（真机可读；读不到如实给 nil，**不猜**）——播报里带上它，用户才能一眼核对「藏的是不是那两个」
local function lfTexPath(o)
  if not o or type(o.GetTexture) ~= "function" then return nil end
  local ok, v = pcall(o.GetTexture, o)
  if ok and type(v) == "string" and v ~= "" then return v end
  return nil
end

-- 层内**纹理**清单（顺序 = `GetRegions()` 顺序 —— 真机截图里那份 #17…#22 编号就是它）
--   ★只认 `GetObjectType() == "Texture"`：同层的 `字体串` 与子件都不算（用户数是「纹理」）
--   ★读不到类型 / 没有 GetRegions ⇒ **如实失败**（宁可什么都不做，也不按猜的分类乱藏）
local function lfTextures(layer)
  if not lfFrameUsable(layer) then return nil, "层不是可用的帧对象" end
  local m = layer.GetRegions
  if type(m) ~= "function" then return nil, "层没有 GetRegions（读不到它的区域）" end
  local rr = { pcall(m, layer) }
  if not rr[1] then return nil, "GetRegions 调用抛错：" .. tostring(rr[2]) end
  local out = {}
  for i = 2, table.getn(rr) do
    local r = rr[i]
    if r and lfObjectType(r) == "Texture" then table.insert(out, r) end
  end
  return out, nil
end

-- 从层里挑出要处理的对象（kind 分派）——返回 对象表, 失败原因
local function lfPickObjs(fix, layer)
  local kind = tostring((type(fix) == "table") and fix.kind or "")
  if kind ~= "hideTex" then return nil, "未知的处理类型：" .. kind end
  local tex, why = lfTextures(layer)
  if not tex then return nil, why end
  local n = table.getn(tex)
  local pick = (type(fix.pick) == "table") and fix.pick or {}
  local out = {}
  -- ① 按贴图路径匹配（写了 path 就用它，**不再看 last**：两套判据同时生效 = 谁也不知道藏了几个）
  if type(pick.path) == "string" and pick.path ~= "" then
    local pat = string.lower(pick.path)
    for i = 1, n do
      local p = lfTexPath(tex[i])
      if p and string.find(string.lower(p), pat, 1, true) then table.insert(out, tex[i]) end
    end
    if table.getn(out) == 0 then
      return nil, "按贴图路径「" .. pick.path .. "」一个都没匹配到（层里共 " .. tostring(n) .. " 个纹理）"
    end
    return out, nil
  end
  -- ② 按顺序取**最后 N 个**（用户的口径）
  local want = math.floor(lfNum(pick.last, 0))
  if want <= 0 then return nil, "pick 没写要挑几个（last = N 或 path = \"子串\" 二选一）" end
  if n < want then
    return nil, "层里只有 " .. tostring(n) .. " 个纹理（少于要处理的 " .. tostring(want) ..
      " 个）⇒ 这一次一个都不动（宁可不做，也不猜着藏）"
  end
  for i = n - want + 1, n do table.insert(out, tex[i]) end
  return out, nil
end

-- 播报文本（如实带数字 / 层名 / 贴图路径；本来就隐藏的个数也报出来，不把「没变化」说成「藏好了」）
local function lfMsg(fix, st)
  local n = table.getn(st.objs)
  local p = {}
  for i = 1, n do p[i] = tostring(st.paths[i] or "（读不到贴图路径）") end
  return string.format("图层隐藏[%s]：已隐藏 %d 个纹理（层=%s%s）｜贴图：%s",
    lfFixWord(fix, "label"), n, tostring(st.layer),
    (lfNum(st.already, 0) > 0) and ("，其中 " .. tostring(st.already) .. " 个本来就是隐藏的") or "",
    table.concat(p, " · "))
end

-- 应用一条（幂等：已经生效过就直接返回，**不重复读原状** —— 那会把「我们自己藏的」记成原始值）
--   返回：ok, 结果码（"applied" / "already" / "layer-missing" / "pick-failed"）, 原因
local function lfApplyOne(fix, quiet)
  if type(fix) ~= "table" then return false, "no-fix", nil end
  if type(LF.fixState[fix.key]) == "table" then return true, "already", nil end
  local layer, hit = lfFixLayer(fix)
  if not layer then return false, "layer-missing", "层不在（候选帧名逐个都没命中）" end
  local objs, why = lfPickObjs(fix, layer)
  if not objs then return false, "pick-failed", why end
  local st = { key = fix.key, layer = hit, objs = objs, orig = {}, paths = {}, already = 0 }
  for i = 1, table.getn(objs) do
    local o = objs[i]
    local sh = nil -- 三态：true / false / nil(读不到)
    if type(o.IsShown) == "function" then
      local ok, v = pcall(o.IsShown, o)
      if ok and v ~= nil then sh = v and true or false end
    end
    st.orig[o] = sh                       -- ★先读原状再动手（顺序不许换：动手之后读到的是我们自己设的）
    if sh == false then st.already = st.already + 1 end
    st.paths[i] = lfTexPath(o)
    if type(o.Hide) == "function" then pcall(o.Hide, o) end
  end
  LF.fixState[fix.key] = st
  LF.fixApplied = lfNum(LF.fixApplied, 0) + 1
  lfLog("apply key=" .. tostring(fix.key) .. " layer=" .. tostring(hit) .. " n=" .. tostring(table.getn(objs)))
  if not quiet then say(lfMsg(fix, st)) end
  return true, "applied", nil
end

-- 还原一条（**只还原确定是「我们藏起来的」那些**：读到「本来就隐藏」的绝不用 Show 把它弄出来）
local function lfResetOne(fix, quiet)
  local st = LF.fixState[fix.key]
  if type(st) ~= "table" then return 0 end
  local n = 0
  for i = 1, table.getn(st.objs) do
    local o = st.objs[i]
    if st.orig[o] ~= false and type(o.Show) == "function" then
      local ok = pcall(o.Show, o)
      if ok then n = n + 1 end
    end
  end
  LF.fixState[fix.key] = nil
  if not quiet then
    say(string.format("图层隐藏[%s]：已还原 %d 个纹理（层=%s）",
      lfFixWord(fix, "label"), n, tostring(st.layer)))
  end
  return n
end

-- 结算（**唯一入口**：勾上 / 取消 / 载入期都走它）：勾着的应用、没勾的还原
--   ★失败（层不在 / 对象数不够）**绝对不静默**：如实说清哪一条没做成、为什么、以及「这次没动界面」——
--   用户点了勾却什么都没发生，正是本项目最恨的那种「点了没反应」。
local function lfSync(quiet)
  local applied, restored, failed = 0, 0, nil
  for i = 1, table.getn(LF_FIXES) do
    local f = LF_FIXES[i]
    if lfFixOn(f.key) then
      local ok, how, why = lfApplyOne(f, quiet)
      if ok and how == "applied" then
        applied = applied + 1
      elseif not ok and how ~= "already" then
        if failed == nil then failed = {} end
        table.insert(failed, lfFixWord(f, "label") .. "（" .. tostring(why or how) .. "）")
      end
    else
      restored = restored + lfResetOne(f, quiet)
    end
  end
  if type(failed) == "table" and not quiet then
    say("图层隐藏：勾选了 " .. tostring(table.getn(failed)) .. " 条这次没做成 —— " .. table.concat(failed, " · ") ..
      "｜**没有对界面做任何改动**（层不在或对象数不够时绝不猜着改）；启动后 5 秒内还会自动补一次")
  end
  return applied, restored
end

-- ============ 启动期**有界**复查窗口（1s × 5 次，做完摘脚本即停）============
-- ① 勾了但还没生效（层当时还没建出来）→ 在这里补上；
-- ② 已生效、但客户端自己又把它显示回来了 → **再藏一次**（守护；如实计数，不静默）。
local function lfStop(why)
  if LF.keepDone then return end
  LF.keepDone = true
  LF.keepWhy = tostring(why or "?")
  local kf = LF.keepFrame
  if kf and type(kf.SetScript) == "function" then
    pcall(kf.SetScript, kf, "OnUpdate", nil) -- ★永久停：脚本被摘掉 ⇒ 不再有常驻 tick
  end
  if LF.keepLate > 0 or LF.keepRe > 0 then
    say(string.format("图层隐藏：启动期复查结束（%s）—— 补生效 %d 条（层晚出现）· 又把 %d 个被显示回来的纹理藏了回去（守护）",
      tostring(LF.keepWhy), LF.keepLate, LF.keepRe))
  end
  lfLog("KEEP STOP why=" .. tostring(LF.keepWhy) .. " runs=" .. tostring(LF.keepRuns) ..
    " late=" .. tostring(LF.keepLate) .. " re=" .. tostring(LF.keepRe))
end

local function lfTick()
  local n = table.getn(LF_FIXES)
  if n == 0 then return 0 end
  local lateN, reN = 0, 0
  for i = 1, n do
    local f = LF_FIXES[i]
    if lfFixOn(f.key) then
      local st = LF.fixState[f.key]
      if type(st) ~= "table" then
        -- 层晚出现 ⇒ 在这里补上（细节在勾选那一刻已经报过，这里只累计，由 lfStop 报一句总量）
        local ok, how = lfApplyOne(f, true)
        if ok and how == "applied" then lateN = lateN + 1 end
      else
        local re = 0
        for k = 1, table.getn(st.objs) do
          local o = st.objs[k]
          if st.orig[o] ~= false then       -- ★只复查「确定不是本来就隐藏」的那些
            local sh = false
            if type(o.IsShown) == "function" then
              local ok2, v = pcall(o.IsShown, o)
              if ok2 then sh = v and true or false end
            end
            if sh then
              if type(o.Hide) == "function" then pcall(o.Hide, o) end
              re = re + 1
            end
          end
        end
        if re > 0 then
          reN = reN + re
          LF.fixRehide = lfNum(LF.fixRehide, 0) + re
          lfLog("rehide key=" .. tostring(f.key) .. " n=" .. tostring(re))
        end
      end
    end
  end
  LF.keepLate = lfNum(LF.keepLate, 0) + lateN
  LF.keepRe = lfNum(LF.keepRe, 0) + reN
  -- ★只在**真的做了事**的时候当场播报一句（这个窗口 5 秒结束即停，不会刷屏；「没做事」也绝不虚报）
  if lateN > 0 or reN > 0 then
    say(string.format("图层隐藏：启动期复查 —— 补生效 %d 条（层晚出现）· 又把 %d 个被显示回来的纹理藏了回去（守护）",
      lateN, reN))
  end
  return lateN + reN
end

local function lfOnUpdate(a1)
  if LF.keepDone then return end
  local dt = lfNum(a1, nil)
  if not dt then dt = lfNum(arg1, 0.05) end
  if (not dt) or dt < 0 then dt = 0.05 end
  LF.keepAge = LF.keepAge + dt
  LF.keepAcc = LF.keepAcc + dt
  if LF.keepAcc < LF_KEEP_PERIOD then
    -- 等待期里也要守住绝对上限（帧率极低 / dt 很大时，不能让窗口靠「等」延长）
    if LF.keepAge >= LF_KEEP_WALL then lfStop("wall") end
    return
  end
  LF.keepAcc = 0
  LF.keepRuns = LF.keepRuns + 1
  pcall(lfTick)
  local why = nil
  if LF.keepRuns >= LF_KEEP_CHECKS then why = "allok"
  elseif LF.keepAge >= LF_KEEP_WALL then why = "wall" end
  if why then lfStop(why) end
end

local function lfArm(why)
  if type(CreateFrame) ~= "function" then return false end
  local kf = LF.keepFrame
  if not kf then
    kf = CreateFrame("Frame", "EVAL_LF_KEEP", lfHost())
    LF.keepFrame = kf
  end
  LF.keepAcc, LF.keepAge, LF.keepRuns = 0, 0, 0
  LF.keepDone = false
  LF.keepWhy = nil
  LF.keepArmed = tostring(why or "?")
  LF.keepLate, LF.keepRe = 0, 0
  if type(kf.SetScript) == "function" then pcall(kf.SetScript, kf, "OnUpdate", lfOnUpdate) end
  lfLog("ARM why=" .. tostring(why))
  return true
end

-- ============ 一次性迁移 ============
-- 1.74.34 第一个版本把勾选**临时**存在 `dragFrames.fix` 里（那时整个功能寄生在框拖拽模块内）；
--   本模块独立后真值搬到自己的子树 `EVAL_HELP_CONFIG.layerFix`。老键**搬完即清**（绝不留两份真值）。
--   ★存档没就位时**直接不动**（不写、也不标记），留给 INSTALL 的有界重试再来一次。
local function lfMigrate(quiet)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return 0 end
  local df = c.dragFrames
  local old = (type(df) == "table") and df.fix or nil
  if type(old) ~= "table" then return 0 end
  local s = lfStore(true)
  if type(s) ~= "table" then return 0 end
  local n = 0
  for i = 1, table.getn(LF_FIXES) do
    local k = LF_FIXES[i].key
    if old[k] == true then
      if type(s.fix) ~= "table" then s.fix = {} end
      s.fix[k] = true
      n = n + 1
    end
  end
  df.fix = nil -- ★搬完即清（唯一真值 = layerFix.fix）
  if not quiet then
    say(string.format("图层隐藏：已把 %d 条勾选从旧位置（dragFrames.fix）搬到本模块自己的存档（layerFix.fix）", n))
  end
  lfLog("MIGRATE n=" .. tostring(n))
  return n
end

-- ============ 安装点（EvalHelp.lua 的 VARIABLES_LOADED 调）============
function EVAL_LF_INSTALL()
  if LF.installed then return true end
  -- ★存档没就位 ⇒ **不锁死**（留给后续调用/重试重来）；写存档必须在就位之后（否则会抹数据）
  if type(rawget(_G, "EVAL_HELP_CONFIG")) ~= "table" then
    lfLog("INSTALL：存档尚未就位 → 本次不锁死，自带有界重试")
    if type(CreateFrame) == "function" and not LF.retryFrame then
      local rf = CreateFrame("Frame", "EVAL_LF_INSTALL_RETRY", lfHost())
      LF.retryFrame = rf
      local acc, tries = 0, 0
      rf:SetScript("OnUpdate", function()
        if LF.installed then pcall(rf.SetScript, rf, "OnUpdate", nil) LF.retryFrame = nil return end
        acc = acc + (lfNum(arg1, 0.05))
        if acc < 0.5 then return end
        acc = 0
        tries = tries + 1
        if EVAL_LF_INSTALL() then
          lfLog("INSTALL：就位后第 " .. tostring(tries) .. " 次重试成功")
          pcall(rf.SetScript, rf, "OnUpdate", nil)
          LF.retryFrame = nil
        elseif tries >= 20 then
          say("图层隐藏：存档重试 20 次仍未就位（期间未写入，不会抹数据）；下次 /reload 再试")
          pcall(rf.SetScript, rf, "OnUpdate", nil)
          LF.retryFrame = nil
        end
      end)
    end
    return false
  end
  LF.installed = true
  pcall(lfMigrate, true)
  pcall(lfSync, true)   -- ① 载入期应用一次（存档里勾过的，重进游戏照样生效 = 守护）
  pcall(lfArm, "install") -- ② 再武装**有界**复查窗口（层晚出现 / 客户端又显示回来）
  lfLog("INSTALL done")
  return true
end

-- ============ 对外 API（工具箱那一行读写的就是这几个）============
-- 写入口（**唯一**）：未知键一律拒写（绝不往存档里塞一个没人认得的键 —— 那种键只会在存档里烂掉）
local function lfSet(key, on)
  if not lfFixOf(key) then return false end
  local t = lfFixTbl(true)
  if type(t) ~= "table" then return false end
  t[key] = on and true or nil
  return true
end

function EVAL_LF_ENABLED(key) return lfFixOn(key) end
function EVAL_LF_SET(key, on) return lfSet(key, on) end

-- 已生效 / 总数（按钮悬停、行内摘要、断言都用它；单一实现，不在别处再数一遍）
function EVAL_LF_COUNT()
  local n, tot = 0, table.getn(LF_FIXES)
  for i = 1, tot do if lfFixOn(LF_FIXES[i].key) then n = n + 1 end end
  return n, tot
end

-- 下拉内容（**唯一来源 = LF_FIXES**）：items 文本 / locked 分组标题行 / tips 悬停说明 / sel 初始勾选 / keys 行→处理键
function EVAL_LF_MENU()
  local items, locked, tips, sel, keys = {}, {}, {}, {}, {}
  local cur = nil
  local function push(txt, isLocked, key, on, tip)
    local i = table.getn(items) + 1
    items[i] = txt
    locked[i] = isLocked and true or false
    keys[i] = key
    if on then sel[i] = true end
    if type(tip) == "string" and tip ~= "" then tips[i] = tip end
  end
  for i = 1, table.getn(LF_FIXES) do
    local f = LF_FIXES[i]
    local gp = lfNum(f.group, 1)
    if gp ~= cur then
      cur = gp
      local gf = LF_FIX_GROUPS[gp]
      local gt = "?"
      if type(gf) == "function" then
        local ok, v = pcall(gf)
        if ok and type(v) == "string" and v ~= "" then gt = v end
      end
      push(gt, true)
    end
    push(lfFixWord(f, "label"), false, f.key, lfFixOn(f.key), lfFixWord(f, "tip"))
  end
  return items, locked, tips, sel, keys
end

-- 行内摘要 / 悬停用的一句状态（现读，不在行渲染期缓存）
function EVAL_LF_SUMMARY()
  local n, tot = EVAL_LF_COUNT()
  if n <= 0 then return L("TB_DFFIX_NONE") end
  local names = {}
  for i = 1, table.getn(LF_FIXES) do
    local f = LF_FIXES[i]
    if lfFixOn(f.key) then table.insert(names, lfFixWord(f, "label")) end
  end
  return string.format(L("TB_DFFIX_SUM_FMT"), n, tot) .. "：" .. table.concat(names, " · ")
end

-- 结算入口（工具箱那个多选下拉每点一下就调一次；非静默 = 当场播报「藏了哪几个 / 还原了几个」）
function EVAL_LF_SYNC(quiet) return lfSync(quiet and true or false) end

-- [重置]：还原全部已生效的处理 + 清空勾选（**如实报数字**；没勾任何条目也照样报「无事可做」）
function EVAL_LF_RESET()
  local restored, n = 0, table.getn(LF_FIXES)
  for i = 1, n do
    local f = LF_FIXES[i]
    restored = restored + lfResetOne(f, false)
    if lfFixOn(f.key) then lfSet(f.key, false) end
  end
  say(string.format("图层隐藏：重置完成 —— 还原 %d 个纹理 · 已清空 %d 条处理的勾选（要再启用请点 [设置]）",
    restored, n))
  return restored
end

-- ============ 工具箱那一行（**嵌入点的被调方**）============
-- 工具箱只做两件事：模型数据里写一行 `{ t = "mod", mod = "layerFix", … }`，渲染段按名字取这里的函数调一次。
--   下面的控件、几何、tooltip、下拉、结算**全在本文件里**（用户要求：尽量少的在 Toolbox 里改）。
--   ★几何与「图层拖拽」行同一套：`[设置]` = `r.add`（cRight−96 宽 44）、`[重置]` = `r.clr`（cRight−48 宽 40）
--     —— **两个控件绝不许同锚**：同锚时后者压住前者、被压的那个永远点不到，而「按钮存在 + 脚本挂上了」
--     这类断言照样全绿（本项目记录在案的遮挡盲区）。
--   ★这一行**没有勾选框**（模型里 `noChk = true`）：真值就是多选里勾了哪几条，多挂一个总开关只会多一份真值。
local function lfRow(r, it)
  if type(r) ~= "table" then return false end
  -- ★1.74.36 用户：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」
  --   ⇒ 行上**不再**重复显示摘要（配置项只在 [设置] / [重置] 的悬停说明里现读：见下方两处 EVAL_LF_SUMMARY()）。
  --   显式 Hide 一次：工具箱每次刷新虽会统一 Hide，但这里写清「本行不用这一格」才不会被后人顺手加回来。
  r.extra:Hide()
  r.add.text:SetText(L("TB_LDDRAG_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, LF_TIP_W)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, (type(it) == "table" and it.tip) or L("TB_DFFIX_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, L("TB_DFFIX_SET_TIP"), 0.88, 0.88, 0.88)
    pcall(tip.AddLine, tip, EVAL_LF_SUMMARY(), 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then
      say("打开特殊处理选择失败：下拉控件未载入")
      return
    end
    local ok, items, locked, tips, sel, keys = pcall(EVAL_LF_MENU)
    if not ok or type(items) ~= "table" or type(keys) ~= "table" then
      say("打开特殊处理选择失败：模块没交回菜单内容（这次没弹出来，不是「没有可选的项」）")
      return
    end
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      -- 分组标题行 keys[pi] 为空（locked 行也点不到；这里再兜一层，绝不拿它去写配置）
      local key = keys[pi]
      if type(key) ~= "string" or key == "" then return end
      pcall(EVAL_LF_SET, key, on == true)
      -- 立刻结算：勾上 → 当场隐藏；取消 → 当场还原（非静默：聊天框如实报「藏了哪几个 / 还原了几个」）
      pcall(EVAL_LF_SYNC)
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = sel, locked = locked, tips = tips })
  end)
  r.clr.text:SetText(L("TB_LDDRAG_RESET"))
  r.clr.btn:Show()
  r.clr.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, LF_TIP_W)
    pcall(tip.SetOwner, tip, r.clr.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, L("TB_DFFIX_RESET_TIP"), 1, 0.85, 0.30)
    pcall(tip.AddLine, tip, EVAL_LF_SUMMARY(), 0.75, 0.95, 0.75)
    pcall(tip.Show, tip)
  end)
  r.clr.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.clr.btn:SetScript("OnClick", function()
    pcall(EVAL_LF_RESET)
    if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
  end)
  return true
end

-- 登记进**模块行注册表**（工具箱渲染段按 `it.mod` 取它）。
--   ★两边谁先载入都成立：表不存在就现建（同一个全局表），绝不依赖 toc 顺序 ——
--     只认「对方已经建好表」的写法会出现「模块先载入 ⇒ 登记无处可去 ⇒ 面板上那一行点不动」的静默失效。
local LF_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(LF_TB_ROWS) ~= "table" then
  LF_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", LF_TB_ROWS)
end
LF_TB_ROWS["layerFix"] = lfRow
-- 与工具箱的注册函数**同一份真值**（两条路都写同一个表；供想走函数口的调用方使用）
function EVAL_LF_TB_REGISTER()
  local t = rawget(_G, "EVAL_TB_MOD_ROWS")
  if type(t) ~= "table" then
    t = {}
    rawset(_G, "EVAL_TB_MOD_ROWS", t)
  end
  t["layerFix"] = lfRow
  return true
end

-- ============ 读值口（测试用；★不复刻逻辑：状态直给真实字段，动作走真实入口）============
function EVAL_LF_TEST_FIXES_RAW() return LF_FIXES end
function EVAL_LF_TEST_FIX_STATE()
  local out = {}
  for k, st in pairs(LF.fixState) do
    if type(st) == "table" then
      local shown = {}
      for i = 1, table.getn(st.objs) do
        local o = st.objs[i]
        local s = false
        if type(o.IsShown) == "function" then
          local ok, v = pcall(o.IsShown, o)
          if ok then s = v and true or false end
        end
        shown[i] = s
      end
      out[k] = { layer = st.layer, n = table.getn(st.objs), objs = st.objs, orig = st.orig,
        shown = shown, paths = st.paths, already = st.already }
    end
  end
  return out
end
-- 只清「已生效」的内部记账（**不动存档、不动对象**）—— 测试隔离用；生产用 EVAL_LF_RESET（会还原 + 清勾选）
function EVAL_LF_TEST_FIX_STATE_CLEAR()
  for k in pairs(LF.fixState) do LF.fixState[k] = nil end
  LF.fixApplied, LF.fixRehide = 0, 0
  LF.keepLate, LF.keepRe = 0, 0
  return true
end
-- tick 状态 / 次数上限 / 武装 / 点火（断言读**生产同一份字段**，不另算一份）
function EVAL_LF_TEST_STATE()
  return {
    installed = LF.installed and true or false,
    fixApplied = LF.fixApplied, fixRehide = LF.fixRehide,
    keepDone = LF.keepDone and true or false, keepWhy = LF.keepWhy, keepArmed = LF.keepArmed,
    keepRuns = LF.keepRuns, keepAge = LF.keepAge, keepLate = LF.keepLate, keepRe = LF.keepRe,
    frame = LF.keepFrame,
    live = (LF.keepFrame and not LF.keepDone and type(LF.keepFrame.GetScript) == "function"
      and LF.keepFrame:GetScript("OnUpdate") ~= nil) and true or false,
  }
end
function EVAL_LF_TEST_LIMITS()
  return { period = LF_KEEP_PERIOD, checks = LF_KEEP_CHECKS, wall = LF_KEEP_WALL }
end
function EVAL_LF_TEST_ARM() return lfArm("testreset") end
function EVAL_LF_TEST_STOP() return lfStop("test") end
function EVAL_LF_TEST_TICK(dt) return lfOnUpdate(dt) end
function EVAL_LF_TEST_MIGRATE(quiet) return lfMigrate(quiet and true or false) end
function EVAL_LF_TEST_ROW() return lfRow end
