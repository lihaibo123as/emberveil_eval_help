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
--   kind   处理类型（决定用哪个执行器）：
--            `"hideTex"` = **隐藏**层内挑出来的纹理（可还原，用户 1.74.34 的「动作条狮鹫」）；
--            `"hideObj"` = 直接隐藏**具名对象**（1.75.36 新增，「主动作条背景」用它）。
--   layer  目标层 `{ cands = { "帧名", … } }`：本客户端 UI 编译在 pak 里，帧名只能现场探
--          ⇒ 与图层拖拽同口径（按候选顺序取第一个存在的帧；一个都不在 = **如实缺席**：
--            这一次一个对象都不动，也绝不换一个「看起来像」的层动手）。
--   pick   从层里挑哪些对象（二选一）：
--            `{ last = N }`      = 按 `GetRegions()` 顺序取**最后 N 个纹理**（用户 1.74.34 的口径）
--            `{ path = "子串" }` = 按贴图路径（小写包含）匹配（**更稳**；拿到真机路径后再启用）
--   objs   （仅 `hideObj`）具名对象清单 `{ { cands = { "主名", "备选名" }, parent = { "真实父级", … } }, … }`；
--          ★字段名是 `parent`（`in` 是 Lua 关键字，不能当键）；
--          解析**三级**：① `rawget(_G, 名字)`；② `parent`（真机图层树里看到的**真实父级**，浅扫深度 1）；
--          ③ `containers`（通用兜底，深扫深度 2）—— 一律按 `GetName()` 比对（区域 + 子件都算）。
--          ★一个都找不到 ⇒ **如实缺席**（这一次一个对象都不动）；**部分命中**要把没找到的名字一并报出来。
--   containers （仅 `hideObj`）兜底容器名表（按名字找时的搜索起点）。
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
-- ★★★1.75.60x 修（真 bug，且是「静默」那一类）：原来这两行
--   `local say, logLine = EVAL_SAY, EVAL_LOGLINE` / `local L = EVAL_L` 把上面那三个**兜底函数整个作废**
--   （同名 local 被新 local 覆盖）——桥若还没就位，say / logLine / L 就是 nil：面板一切正常，
--   但「如实播报」与日志**一个字都出不来**。⇒ 删掉这两行，桥一律**调用时现读**。

-- ============ 常量 ============
local LF_TIP_W = 460          -- tooltip 最小宽度（与工具箱其它行的口径一致：TB_LD_TIP_W = 460）
local LF_KEEP_PERIOD = 1.0    -- 启动期复查周期（秒）
local LF_KEEP_CHECKS = 5      -- 净检查次数上限（5 × 1s ⇒ 载入完成后 5 秒内收工）
local LF_KEEP_WALL = 15.0     -- 绝对墙钟上限（秒）：从「武装」那一刻起算，任何情况都不许超过它

-- ★★★1.75.109 **扫描闸门**（真机报障「图层隐藏 → 主动作条背景，初次打开会把游戏卡死」换来的）：
--   旧 `lfFindByName` **只有深度上限** —— 既没有**访问集 `seen`**、也没有**节点预算**，而兜底容器
--   （`containers`）里还带着 **`UIParent`** ⇒ 正是本项目 §5.1 铁律明令「两道闸缺一不可」的那一族
--   （同族在案：`tools/SimpleMap.lua` 的 `tryCollectBlack` 按子帧无界递归；子插件 `EH_DebugBox` 1.75.48
--    「几万次 `GetRegions/GetChildren/GetName` 全挤在同一帧 ⇒ 真机卡死」）。
--   ★**真机数据（不是估算）**：`EH_DebugBox` 存档里落着一条树路径 `[界面] UIParent/GeneratedLuaUIObject_914`
--   ⇒ **UIParent 至少 914 个直接子件**、且名字是**合成名**（DebugBox 在案）。从 UIParent 往下扫 2 层
--   = 每个节点 2~3 次客户端调用（`GetRegions`/`GetChildren`/`GetName` 各一次）⇒ 一趟就是**上万次调用挤在同一帧**；
--   而 `lfPickObjs` 是**逐名字**扫的 —— 7 个具名对象各走一趟（没命中就一路扫到 UIParent）⇒ 真机直接卡死。
--   ⇒ 四道收口：① **预算**（**整趟共享**、写死常量，绝不拿数据规模当上限）② **`seen` 去环**
--     （本客户端是 UE 封装，`GetChildren` 未必是树）③ **`UIParent` 不进兜底深扫**（它只是「整个 UI 的根」，
--     而本模块 7 个目标全在动作条族里 ⇒ 扫它既无用又致命）④ **撞预算不许静默**（如实点名 + 本会话不再重试）。
local LF_SCAN_MAX = 1500   -- 一趟（一次 lfPickObjs）里**所有名字共享**的节点预算
local LF_SCAN_DEEP = 2     -- 兜底容器允许的深度（动作条族那几个帧很浅；真正的闸门是**预算**）
local LF_SCAN_KEEP = 60    -- 落盘取证环上限（`EVAL_HELP_CONFIG.layerFixProbe`）
local LF_PATH_MAX = 12     -- ★★★1.75.109 **路径缓存**的名字链长度上限（写死的常量；链是真实走出来的，不是猜的）
local lfScanN = 0          -- 本趟已访问节点数（唯一写口 = lfScanTake）
local lfScanCap = false    -- 本趟撞没撞预算（撞了 = 判不出 ⇒ 如实点名「有几项没敢扫」，绝不当成「没有」）

-- ★★★1.75.109 **路径缓存**（用户原话：「**不要每次遍历.直接进行一次成功的隐藏之后记录路径就可以**」）：
--   一次解析成功后，把**真实走出来的名字链**（从 `_G` 里那个根，逐级到叶子）落进
--   `EVAL_HELP_CONFIG.layerFixPath[处理键][目标名] = { 根名, …, 叶子名 }` ⇒ 下次直接照链走：
--   **每一级只枚举该帧的直接区域+子件**（几~几十个），代价比整树扫描小两个数量级，
--   而且**根本不再进「深扫」那条路**（卡死的成因从源头消失；预算只留给「路径失效后的那一次重找」）。
--   ★四条纪律：① 链必须**真实走出来**（`lfFindByName` 边下钻边记），绝不许按名字拼；
--   ② 链上出现**匿名节点**（`GetName()` 读不到）⇒ **这条不许缓存**（缓存了下次也走不通，还会假装成功）；
--   ③ 走不通 ⇒ **立刻删掉这条缓存**，并照旧回落一次有界扫描（坏缓存自愈，绝不因此放弃功能）；
--   ④ 写口唯一 `lfPathPut`（校验：键/名是字符串、链长 1..`LF_PATH_MAX`、**末项必须等于这个名字**）。

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
  {
    -- ★★★1.75.36（用户 2026-09-28 截图：「将主动作条以上这几个层加入 工具箱->图层隐藏->主动作条背景 设置」）：
    --   名字**逐字取自真机图层树**（用户第一张截图那几行）—— 具名件按名字找，不靠父子链、也不靠序号。
    --   ★范围口径（如实写进 tip，绝不多藏）= **美术背景**这一类：条身 4 片 + 翻页动画片 + 额外动作条背景 2 片；
    --     经验条（MainMenuExpBar / MainMenuXPBarTexture0~5 / ExhaustionLevelFillBar）· 满级条
    --     （MainMenuMaxLevelBar0~3）· 页码（MainMenuBarPageNumber）**故意不含**：那是「信息」不是「背景」，
    --     藏了会让人以为插件坏了（要并进来只加几行 objs，其余代码一行不用改）。
    --   ★两头端盖（MainMenuBarLeftEndCap / RightEndCap = 狮鹫）归上面那条 `gryphon`，**不在这里重复**。
    key = "barBg", group = 1, kind = "hideObj",
    -- ★★★1.75.109 **内置路径**（`名字 = { 根名, …, 叶子名 }`）：**真机日志烘进来的**「照路径直接拿」表。
    --   来历（用户定的工作流）：「可以做个日志记录.我开启关闭.你读取日志直接就可以将正确的元素都记录好路径」
    --   ⇒ 他开关一次 → 插件把「谁在第几级命中 + 完整路径链」写进 `layerFixProbe` 环 → 我读存档 →
    --   把链**逐字填到这里** ⇒ 以后**任何玩家第一次勾选**都直接照链走（不再整树遍历，也不可能卡死）。
    --   ★★**真机实测（1.75.109 · 账号 lihaiboas3 / 角色 Iosol 的日志，逐字照抄）**：
    --     `MainMenuBarTexture0..3` 与 `BonusActionBarTexture0/1` **六片都是「①全局名」命中**
    --     ⇒ 链 = `{ 名字 }`（ⓠ 走它 = 一次 `rawget`，**零枚举**）；
    --     `MainMenuBarAnimFrame` **三级全没命中**（本趟 363 个节点、没撞预算，没找到 1）——
    --     它**故意留在这里**：将来哪一版客户端把它放进 `_G` 或动作条族里就自动生效；
    --     要现在就拿准它，跑 `/eh go 图层隐藏 深挖`（分帧有界深挖，找到就把链写进取证环）。
    paths = {
      ["MainMenuBarTexture0"] = { "MainMenuBarTexture0" },
      ["MainMenuBarTexture1"] = { "MainMenuBarTexture1" },
      ["MainMenuBarTexture2"] = { "MainMenuBarTexture2" },
      ["MainMenuBarTexture3"] = { "MainMenuBarTexture3" },
      ["BonusActionBarTexture0"] = { "BonusActionBarTexture0" },
      ["BonusActionBarTexture1"] = { "BonusActionBarTexture1" },
    },
    -- ★父级**逐字取自用户第二张真机图层树截图**（MainMenuBar 那棵树）：
    --   MainMenuBar → MainMenuBarArtFrame → [MainMenuBarTexture0..3]
    --   MainMenuBar → MainMenuBarOverlayFrame → [MainMenuBarAnimFrame]（该帧在树里是 ▶ 折叠的）
    --   额外动作条：BonusActionBarFrame → [BonusActionBarTexture0/1]
    objs = {
      --   ★字段名用 `parent`（**不能写 `in`**：`in` 是 Lua 关键字，`{ in = … }` 是语法错 —— 1.75.36 首次踩到）
      { cands = { "MainMenuBarTexture0" }, parent = { "MainMenuBarArtFrame", "MainMenuBar" } },
      { cands = { "MainMenuBarTexture1" }, parent = { "MainMenuBarArtFrame", "MainMenuBar" } },
      { cands = { "MainMenuBarTexture2" }, parent = { "MainMenuBarArtFrame", "MainMenuBar" } },
      { cands = { "MainMenuBarTexture3" }, parent = { "MainMenuBarArtFrame", "MainMenuBar" } },
      { cands = { "MainMenuBarAnimFrame" }, parent = { "MainMenuBarOverlayFrame", "MainMenuBar" } },
      { cands = { "BonusActionBarTexture0" }, parent = { "BonusActionBarFrame" } },
      { cands = { "BonusActionBarTexture1" }, parent = { "BonusActionBarFrame" } },
    },
    -- 通用兜底容器（`parent` 没命中才用）；顺序 = 从最可能到最不可能
    -- ★★★1.75.109：**`UIParent` 已从这里摘掉**（旧写法把「整个 UI 的根」当兜底容器 ⇒ 真机卡死的根源）：
    --   它是 914+ 直接子件的总根，从它往下扫 2 层 = 上万次客户端调用挤在同一帧；而本模块这 7 个目标
    --   **全在动作条族里**（下面的 6 个容器），扫 UIParent 既无用又致命。找不到就如实缺席、一个字节都不碰。
    containers = { "MainMenuBarArtFrame", "MainMenuBar", "MainMenuBarOverlayFrame",
      "MainMenuBarExpBar", "MainMenuBarMaxLevelBar", "BonusActionBarFrame" },
    layerLabel = "具名背景层",
    label = function() return L("TB_FIX_BARBG") end,
    tip = function() return L("TB_FIX_BARBG_TIP") end,
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
  retry = nil,         -- ★1.75.109：存档未就位时的有界重试会话态（并进唯一节拍；原 retryFrame 已删）
  -- ★1.75.109：**本会话已经撞过扫描预算**的处理键 ⇒ 后续（启动期复查 1s×5 / 再点一次）不再重扫
  --   （不记这一笔 ⇒ 每拍重扫一次 = 卡死会重复 5 次；★用户显式取消勾选时清掉，让他有机会重问一次）
  capKeys = {},
  scanN = 0,           -- 最近一趟实际访问的节点数（读值口 / 播报用）
  -- ★1.75.109 分帧深挖的会话态（`dig` = 正在跑；`digLast` = 上一次的结果一句话，体检口要报）
  dig = nil,
  digLast = nil,
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

-- ============ 路径缓存（1.75.109；用户：「不要每次遍历.直接进行一次成功的隐藏之后记录路径就可以」）============
--   `EVAL_HELP_CONFIG.layerFixPath[处理键][目标名] = { 根名, …, 叶子名 }`（★末项 = 目标名，写口校验）
--   读口 `lfPathGet` / 写口**唯一** `lfPathPut` / 删口 `lfPathDel`（走不通就删 = 坏缓存自愈）
local function lfPathStore(create)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  local t = c.layerFixPath
  if type(t) ~= "table" then
    if not create then return nil end
    t = {}
    c.layerFixPath = t
  end
  return t
end
local function lfPathGet(key, nm)
  local t = lfPathStore(false)
  local per = (type(t) == "table") and t[key] or nil
  local chain = (type(per) == "table") and per[nm] or nil
  return (type(chain) == "table") and chain or nil
end
local function lfPathDel(key, nm)
  local t = lfPathStore(false)
  local per = (type(t) == "table") and t[key] or nil
  if type(per) ~= "table" then return false end
  per[nm] = nil
  return true
end
-- 唯一写口：校验全部做完才落盘（★末项必须等于这个名字 —— 写错 = 下次照着走必然走不通）
local function lfPathPut(key, nm, chain)
  if type(key) ~= "string" or key == "" then return false end
  if type(nm) ~= "string" or nm == "" then return false end
  if type(chain) ~= "table" then return false end
  local n = table.getn(chain)
  if n < 1 or n > LF_PATH_MAX then return false end
  for i = 1, n do
    if type(chain[i]) ~= "string" or chain[i] == "" then return false end
  end
  if chain[n] ~= nm then return false end
  local t = lfPathStore(true)
  if type(t) ~= "table" then return false end
  local per = t[key]
  if type(per) ~= "table" then per = {} t[key] = per end
  local old, changed = per[nm], false
  if type(old) ~= "table" or table.getn(old) ~= n then
    changed = true
  else
    for i = 1, n do if old[i] ~= chain[i] then changed = true break end end
  end
  if not changed then return false end   -- ★没变就不写（存档不因为每次登录都重写一遍）
  per[nm] = chain
  return true
end
-- 只读：这个处理键已经缓存了几条路径（体检口用）
local function lfPathCount(key)
  local t = lfPathStore(false)
  local per = (type(t) == "table") and t[key] or nil
  if type(per) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(per) do n = n + 1 end
  return n
end

-- ★★★1.75.109 **有界落盘取证环**（`EVAL_HELP_CONFIG.layerFixProbe`，上限 `LF_SCAN_KEEP` 行）：
--   用户的工作流 = 「我开关一下，你去读日志」⇒ **每次解析（勾选/取消/载入期）自动写**，
--   不需要他敲任何命令；全文含「每个名字在第几级命中 + 完整路径链」⇒ 我读存档就能把正确的路径
--   **烘进插件**（`LF_FIXES[].paths`），以后所有玩家第一次勾选就零遍历。
--   ★上限到了从**头部**砍（最新在后，读的时候取尾部）；★`EVAL_HELP_CONFIG` 没就位就一个字节都不写。
local function lfRingPush(line)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return false end
  local r = c.layerFixProbe
  if type(r) ~= "table" then
    r = {}
    c.layerFixProbe = r
  end
  table.insert(r, tostring(line))
  while table.getn(r) > LF_SCAN_KEEP do table.remove(r, 1) end
  return true
end

local function lfFixOn(key)  local t = lfFixTbl(false)
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

-- ===== 具名对象解析（kind = "hideObj" 用）=====
-- 本趟还能不能继续扫 —— **唯一的预算闸**（★铁律：闸门必须排在**任何客户端调用之前**）：
--   撞预算（`lfScanN >= LF_SCAN_MAX`）⇒ 置 `lfScanCap` 并**立刻停**（后面一律返回 false）；
--   `seen[obj]` 已访问过 ⇒ 也停（去环：本客户端 `GetChildren` 未必是树，同族在案 = SimpleMap 的爆栈）。
local function lfScanTake(seen, obj)
  if lfScanCap then return false end
  if lfScanN >= LF_SCAN_MAX then lfScanCap = true return false end
  if seen[obj] then return false end
  seen[obj] = true
  lfScanN = lfScanN + 1
  return true
end

-- 一个对象的**直接**区域 + 子件（唯一实现：深扫与「照路径逐级走」共用同一把尺子）
local function lfKids(obj)
  local kids = {}
  local function collect(m)
    if type(m) ~= "function" then return end
    local rr = { pcall(m, obj) }
    if not rr[1] then return end
    for i = 2, table.getn(rr) do if rr[i] then table.insert(kids, rr[i]) end end
  end
  collect(obj.GetRegions)
  collect(obj.GetChildren)
  return kids
end

-- ★★★1.75.109 **照路径走**（用户：「不要每次遍历.直接进行一次成功的隐藏之后记录路径就可以」）：
--   `chain = { 根名, 中间名…, 叶子名 }`（根名必须能 `rawget(_G, …)` 到）
--   ⇒ 从根开始，**每一级只枚举该帧的直接区域+子件**（几~几十个）逐级按名找下一级。
--   ★代价 = 链长 × 每级直接子件数（比整树扫描小两个数量级）；★每级都过 `lfScanTake`（同一个预算池，
--     防「病态长链」把这一趟吃光）；★任一级找不到 ⇒ 返回 nil（调用方立刻删掉这条缓存并回落一次有界扫描）。
local function lfPathWalk(chain)
  if type(chain) ~= "table" then return nil end
  local n = table.getn(chain)
  if n < 1 or n > LF_PATH_MAX then return nil end
  local cur = lfFrameOf(chain[1])
  if not (cur and lfFrameUsable(cur)) then return nil end
  for i = 2, n do
    local nm = chain[i]
    if type(nm) ~= "string" or nm == "" then return nil end
    if not lfScanTake({}, cur) then return nil end
    local kids = lfKids(cur)
    local nxt = nil
    for k = 1, table.getn(kids) do
      local o = kids[k]
      if lfFrameUsable(o) and type(o.GetName) == "function" then
        local ok, kn = pcall(o.GetName, o)
        if ok and kn == nm then nxt = o break end
      end
    end
    if not nxt then return nil end
    cur = nxt
  end
  return cur
end

-- 在 obj 的 [区域 + 子件] 里按 **GetName()** 找 nm
--   ★★★1.75.109 两道闸一起上：① 预算（`lfScanTake`，整趟共享）② `seen` 访问集（**每次遍历一份** ——
--   跨名字共用会让第二个名字一步都走不动）。旧写法只有深度上限 ⇒ 真机卡死（见文件头那段）。
--   ★`rec`（可选；传了才记路径）：`rec.path` = 祖先名字链、`rec.anon` = 链上有匿名节点（⇒ 不缓存）、
--   `rec.leaf` = 叶子名。路径是**边下钻边记**出来的，绝不是按名字拼的。
local function lfFindByName(obj, nm, depth, seen, rec)
  seen = seen or {}
  if not lfScanTake(seen, obj) then return nil end
  if not lfFrameUsable(obj) then return nil end
  local pushed = false
  if rec then
    local okn, v = pcall(obj.GetName, obj)
    if okn and type(v) == "string" and v ~= "" then
      table.insert(rec.path, v)
      pushed = true
    else
      rec.anon = true
    end
  end
  local kids = lfKids(obj)
  for i = 1, table.getn(kids) do
    local k = kids[i]
    if lfFrameUsable(k) and type(k.GetName) == "function" then
      local ok, kn = pcall(k.GetName, k)
      if ok and kn == nm then
        if rec then rec.leaf = nm end
        return k
      end
    end
  end
  local d = lfNum(depth, 0)
  if d > 0 then
    for i = 1, table.getn(kids) do
      local f2 = lfFindByName(kids[i], nm, d - 1, seen, rec)
      if f2 then return f2 end
    end
  end
  if rec and pushed then table.remove(rec.path) end
  return nil
end

-- 具名对象解析（**三级**，从最确定到最兜底）：
--   ① 全局名 `rawget(_G, 名字)`（零客户端调用）；
--   ② `parent` = 真机图层树里看到的**真实父级**（浅扫，深度 1 —— 名字就在它自己的区域/子件里）；
--   ③ `containers` = 通用兜底容器（深扫 `LF_SCAN_DEEP` 层，**共享预算**）。
--   ★一个都不命中 ⇒ 交给调用方如实缺席（这里不猜、也不换一个名字相近的对象）。
--   ★★`seen` 的**作用域 = 每个根一次遍历**（`lfFindByName` 自己建），**绝不跨名字共用** ——
--     共用会让第二个名字「一步都走不动」（它要走的节点已被上一个名字标成「走过」了）⇒ 静默少找。
--     真正跨名字共享的是**预算**（`lfScanN`，整趟一个池子）。
--   ★★1.75.109：**三级由 `lfPickObjs` 分段调用**（全局名先给所有名字跑完，再父级、再兜底）——
--     原来那个「一口气走完三级」的 `lfNamedHit` 已删除：它会让排在前面的名字把预算吃光（静默少藏）。
--   ★`rec`（可选）= 边下钻边记路径（命中时交出 `rec.chain`，供**烘进插件**与运行时缓存用）。
local function lfNamedScan(list, nm, depth, rec)
  if type(list) ~= "table" then return nil end
  for i = 1, table.getn(list) do
    local rootKey = list[i]
    local root = lfFrameOf(rootKey)
    if root and lfFrameUsable(root) then
      if rec then rec.path, rec.anon, rec.leaf, rec.chain = {}, false, nil, nil end
      local hit = lfFindByName(root, nm, depth, {}, rec)
      if hit then
        if rec and not rec.anon then
          local chain = {}
          for k = 1, table.getn(rec.path) do chain[k] = rec.path[k] end
          chain[1] = rootKey          -- ★首项必须是**能 rawget 到的全局名**（`GetName()` 读回的可能不一样）
          table.insert(chain, nm)     -- 叶子
          rec.chain = chain
        end
        return hit
      end
    end
  end
  return nil
end

-- 播报用名词（两种 kind 口径不同：不该把「背景层」叫成「纹理」）
local function lfNoun(fix)
  return ((type(fix) == "table") and fix.kind == "hideObj") and "背景层" or "纹理"
end

-- 从层里挑出要处理的对象（kind 分派）——返回 对象表, 失败原因, 没找到的名字表
local function lfPickObjs(fix, layer)
  local kind = tostring((type(fix) == "table") and fix.kind or "")
  -- ★1.75.36：hideObj = 直接按**名字**隐藏（不需要层；名字来自真机图层树）
  if kind == "hideObj" then
    local list = (type(fix.objs) == "table") and fix.objs or nil
    if not list then return nil, "这条处理没写 objs（具名对象清单）" end
    local out, miss, capped = {}, {}, {}
    -- ★★★1.75.109 解析次序（**顺序即判据**：越便宜、越确定的路越先走，贵的最后才动）：
    --   ⓠ **照路径走**：① 内置路径（`fix.paths`，真机日志烘进来的）② 运行时缓存（`layerFixPath`，上次成功记下的）
    --      —— 每级只枚举直接区域+子件 ⇒ **稳态根本不做整树遍历**（用户要的就是这个）；
    --   ⒜ **全局名**（`rawget`，零客户端调用）—— 给全部名字一次机会；
    --   ⒝ **真实父级浅扫**（深度 1；**共享预算**）；
    --   ⒞ **兜底容器深扫**（`LF_SCAN_DEEP` 层；同一个预算）。
    --   ★分段（而不是按名字一口气走完）的理由：那会让**排在前面的名字**把预算吃光、后面的名字**静默找不到**。
    --   ★撞预算 ⇒ 后面的名字**一个都不扫**、进 `capped` 如实点名（判不出就如实说，绝不当「没有」）。
    lfScanN, lfScanCap = 0, false
    local pend, pend2, byPath = {}, {}, 0
    local trace = {}   -- ★真机取证：逐名字一行（级别 + 完整路径）⇒ 烘进插件/我读存档定案
    -- ⓠ 路径（内置 → 运行时缓存）
    for i = 1, table.getn(list) do
      local spec = list[i]
      local cands = (type(spec) == "table") and spec.cands or { spec }
      local inList = (type(spec) == "table") and spec.parent or nil -- ★真实父级（可选；键名是 parent，不是 in）
      -- ⓠ 路径（内置优先 → **内置失效就继续试运行时缓存** → 都失效才去扫描）
      --   ★★★这条「继续试下一个」是必须的（harness 当场抓到）：不同机器/版本上，内置路径的根或中间级
      --   可能不存在，而**这台机器上次成功学到的链**（`layerFixPath`）照样有效 ⇒ 绝不能因为内置失效就去扫。
      local hit = nil
      for j = 1, table.getn(cands) do
        local nm = tostring(cands[j])
        local tries = {
          { from = "内置路径", builtin = true, chain = (type(fix.paths) == "table") and fix.paths[nm] or nil },
          { from = "路径缓存", builtin = false, chain = lfPathGet(fix.key, nm) },
        }
        for t = 1, 2 do
          local chain = tries[t].chain
          if type(chain) == "table" then
            hit = lfPathWalk(chain)
            if hit then
              byPath = byPath + 1
              table.insert(trace, string.format("%s ← %s（%s）", nm, tries[t].from, table.concat(chain, "/")))
              break
            end
            -- 失效：内置路径**留着**（别的客户端版本可能正是这条路，也留给体检口如实报）；
            --   运行时缓存**立刻删**（它是这台机器学到的，坏了就是坏了 ⇒ 下次重新学）
            if not tries[t].builtin then lfPathDel(fix.key, nm) end
            lfLog("PATH MISS key=" .. tostring(fix.key) .. " nm=" .. nm .. " via=" .. tries[t].from ..
              " chain=" .. table.concat(chain, "/"))
            -- ★同一个事实也写进取证环（用户「我开关、你读日志」的工作流就靠这一环：能分清
            --   「路径坏了（客户端改了层级）」与「名字变了」——两者都要重新烘路径）
            lfRingPush(string.format("[解析] %s %s ← %s**失效**（%s）—— %s",
              tostring(fix.key), nm, tries[t].from, table.concat(chain, "/"),
              tries[t].builtin and "改试运行时缓存/扫描" or "已删掉这条缓存，改走扫描"))
          end
        end
        if hit then break end
      end
      if hit then table.insert(out, hit) else table.insert(pend, { cands = cands, inList = inList }) end
    end
    -- ★`LF.capKeys[key]` = **本会话已经撞过预算**的处理 ⇒ 扫描路（⒝/⒞）整段让位
    --   （启动期复查 1s×5 每拍重扫一次 = 卡死会重复 5 次；撞过一次就记名，用户取消勾选时清掉、可重问一次）
    local skip2 = (type(LF.capKeys) == "table") and (LF.capKeys[fix.key] == true)
    -- ⒜ 全局名
    for i = 1, table.getn(pend) do
      local cands, inList = pend[i].cands, pend[i].inList
      local hit, nm = nil, nil
      for j = 1, table.getn(cands) do
        local g = lfFrameOf(cands[j])
        if g and lfFrameUsable(g) then hit, nm = g, tostring(cands[j]) break end
      end
      if hit then
        table.insert(out, hit)
        table.insert(trace, tostring(nm) .. " ← ①全局名")
        lfPathPut(fix.key, tostring(nm), { tostring(nm) })
      else
        table.insert(pend2, { cands = cands, inList = inList })
      end
    end
    -- ⒝ 真实父级浅扫
    local pend3 = {}
    for i = 1, table.getn(pend2) do
      local cands, inList = pend2[i].cands, pend2[i].inList
      local hit, nm = nil, nil
      if not skip2 then
        for j = 1, table.getn(cands) do
          local rec = {}
          hit = lfNamedScan(inList, cands[j], 1, rec)
          if hit then
            nm = tostring(cands[j])
            if type(rec.chain) == "table" then
              lfPathPut(fix.key, nm, rec.chain)
              table.insert(trace, nm .. " ← ②真实父级（" .. table.concat(rec.chain, "/") .. "）")
            else
              table.insert(trace, nm .. " ← ②真实父级（路径不可缓存）")
            end
            break
          end
        end
      end
      if hit then table.insert(out, hit) else table.insert(pend3, cands) end
    end
    -- ⒞ 兜底容器深扫
    for i = 1, table.getn(pend3) do
      local cands = pend3[i]
      local hit, nm = nil, nil
      if not skip2 then
        for j = 1, table.getn(cands) do
          local rec = {}
          hit = lfNamedScan(fix.containers, cands[j], LF_SCAN_DEEP, rec)
          if hit then
            nm = tostring(cands[j])
            if type(rec.chain) == "table" then
              lfPathPut(fix.key, nm, rec.chain)
              table.insert(trace, nm .. " ← ③兜底容器（" .. table.concat(rec.chain, "/") .. "）")
            else
              table.insert(trace, nm .. " ← ③兜底容器（路径不可缓存）")
            end
            break
          end
        end
      end
      if hit then table.insert(out, hit)
      elseif lfScanCap or skip2 then table.insert(capped, tostring(cands[1]))
      else table.insert(miss, tostring(cands[1])) end
    end
    -- ★真机取证 + 自查：把这一趟「谁在第几级命中、完整路径是什么」逐行记下来
    --   （用户的工作流：他开关一下，我读存档就能把正确的路径链烘进 `LF_FIXES[].paths`）
    for i = 1, table.getn(trace) do lfRingPush("[解析] " .. tostring(fix.key) .. " " .. trace[i]) end
    if table.getn(trace) > 0 or table.getn(miss) > 0 or table.getn(capped) > 0 then
      lfRingPush(string.format("[解析] %s：命中 %d（其中照路径 %d）· 没找到 %d · 没敢扫 %d · 本趟节点 %d%s",
        tostring(fix.key), table.getn(out), byPath, table.getn(miss), table.getn(capped), lfScanN,
        lfScanCap and "（★撞预算）" or ""))
    end
    fix.lastByPath = byPath
    fix.lastScanN = lfScanN
    if table.getn(out) == 0 then
      local why = "具名对象一个都没找到"
      if table.getn(miss) > 0 then why = why .. "（" .. table.concat(miss, " · ") .. "）" end
      if table.getn(capped) > 0 then
        why = why .. "；★另有 " .. tostring(table.getn(capped)) .. " 项**没敢扫**（" .. table.concat(capped, " · ") ..
          "）—— 为不卡死提前收工（见 /eh go 图层隐藏）"
      end
      return nil, why
    end
    return out, nil, miss, capped -- ★部分命中：miss / capped 跟着播报一起报出去，绝不静默少藏
  end
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
--   ★1.75.109 补两条**如实说明**（都属「判不出就说判不出」）：① `capped` = 因扫描预算没敢扫的项；
--   ② `scanCap` = 本趟撞了预算（把「为不卡死提前收工」这句话连同节点数一起说出来）。
local function lfMsg(fix, st)
  local n = table.getn(st.objs)
  local p = {}
  for i = 1, n do p[i] = tostring(st.paths[i] or "（读不到贴图路径）") end
  local miss = ""
  if type(st.miss) == "table" and table.getn(st.miss) > 0 then
    miss = "；**没找到**：" .. table.concat(st.miss, " · ")
  end
  if type(st.capped) == "table" and table.getn(st.capped) > 0 then
    miss = miss .. "；★**没敢扫**（为不卡死提前收工）：" .. table.concat(st.capped, " · ")
  end
  if st.scanCap == true then
    miss = miss .. "｜★本趟扫描撞到预算上限 " .. tostring(LF_SCAN_MAX) .. " 个节点（已提前停，界面没有被弄坏）"
  end
  return string.format("图层隐藏[%s]：已隐藏 %d 个%s（层=%s%s）｜贴图：%s%s",
    lfFixWord(fix, "label"), n, lfNoun(fix), tostring(st.layer),
    (lfNum(st.already, 0) > 0) and ("，其中 " .. tostring(st.already) .. " 个本来就是隐藏的") or "",
    table.concat(p, " · "), miss)
end

-- 应用一条（幂等：已经生效过就直接返回，**不重复读原状** —— 那会把「我们自己藏的」记成原始值）
--   返回：ok, 结果码（"applied" / "already" / "layer-missing" / "pick-failed"）, 原因
local function lfApplyOne(fix, quiet)
  if type(fix) ~= "table" then return false, "no-fix", nil end
  if type(LF.fixState[fix.key]) == "table" then return true, "already", nil end
  local kind = tostring(fix.kind or "")
  local layer, hit = nil, nil
  if kind ~= "hideObj" then -- ★hideObj 按名字直接找（没有「层」这一步）；别的 kind 仍要求层先命中
    layer, hit = lfFixLayer(fix)
    if not layer then return false, "layer-missing", "层不在（候选帧名逐个都没命中）" end
  end
  local objs, why, miss, capped = lfPickObjs(fix, layer)
  -- ★1.75.109 **扫描账**（在 `lfPickObjs` 之后立刻取，别让后面的调用把它冲掉）：
  --   `scanCap` = 这一趟撞没撞预算 ⇒ 记进 `LF.capKeys`（启动期复查/再点一次都不再重扫 = 卡死不重复）
  local scanCap, scanNodes = lfScanCap, lfScanN
  LF.scanN = scanNodes
  if scanCap then
    if type(LF.capKeys) ~= "table" then LF.capKeys = {} end
    LF.capKeys[fix.key] = true
    lfLog("SCAN CAP key=" .. tostring(fix.key) .. " nodes=" .. tostring(scanNodes) .. "（本会话不再深扫这一条）")
  end
  if not objs then return false, "pick-failed", why end
  local st = { key = fix.key, layer = hit or fix.layerLabel or "具名对象", objs = objs, orig = {}, paths = {},
    already = 0, miss = miss, capped = capped, scanCap = scanCap, scanN = scanNodes }
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
  lfLog("apply key=" .. tostring(fix.key) .. " layer=" .. tostring(st.layer) .. " n=" .. tostring(table.getn(objs)))
  if not quiet then say(lfMsg(fix, st)) end
  return true, "applied", nil
end

-- 还原一条（**只还原确定是「我们藏起来的」那些**：读到「本来就隐藏」的绝不用 Show 把它弄出来）
local function lfResetOne(fix, quiet)
  local st = LF.fixState[fix.key]
  -- ★1.75.109：取消勾选 = 用户主动收回这一次请求 ⇒ 连同「本会话已撞过预算」的记名一起清掉
  --   （下次勾上还有机会重扫一次；不清 = 用户永远看不到那几片，且没有任何解释）。
  if type(LF.capKeys) == "table" then LF.capKeys[fix.key] = nil end
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
    say(string.format("图层隐藏[%s]：已还原 %d 个%s（层=%s）",
      lfFixWord(fix, "label"), n, lfNoun(fix), tostring(st.layer)))
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
-- ★★★1.75.109 **前向声明（本项目 R2 老雷，必须照这条写）**：节拍那两个函数（handler `lfBeat` 与
--   挂/摘唯一入口 `lfBeatSync`）在下面才定义，而 `lfStop` / `lfDigStop` / `lfDigStep` **都还没有它们**；
--   写成 `local function` ⇒ 引用点绑**全局 nil** ⇒ 运行时 `attempt to call a global 'lfBeatSync'`
--   （被 pcall 包住时**完全哑**：节拍永远挂不上、深挖永远推不动）。⇒ 声明放这里、定义处改赋值。
local lfBeatSync, lfBeat

local function lfStop(why)
  if LF.keepDone then return end
  LF.keepDone = true
  LF.keepWhy = tostring(why or "?")
  -- ★1.75.109：**不再直接 SetScript(nil)** —— 挂/摘收进唯一入口 `lfBeatSync`
  --   （本模块现在有两种活要跑：keep 复查窗口 与 分帧深挖 ⇒ 谁还在跑就不能摘，否则另一个永远推不动）
  lfBeatSync()
  if LF.keepLate > 0 or LF.keepRe > 0 then
    say(string.format("图层隐藏：启动期复查结束（%s）—— 补生效 %d 条（层晚出现）· 又把 %d 个被显示回来的对象藏了回去（守护）",
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
    say(string.format("图层隐藏：启动期复查 —— 补生效 %d 条（层晚出现）· 又把 %d 个被显示回来的对象藏了回去（守护）",
      lateN, reN))
  end
  return lateN + reN
end

-- 启动期复查的**一拍**（原 `lfOnUpdate` 的体重命名；逻辑一字未改）
local function lfKeepBeat(a1)
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

-- ============ ★★★1.75.109 分帧有界深挖（找「三级都没命中」的那几片；**绝不卡死**）============
--   为什么要它：真机日志（1.75.109 · lihaiboas3/Iosol）证明 **`MainMenuBarAnimFrame` 三级都没命中**
--   （本趟 363 个节点、没撞预算），而用户图层树截图里它确实在界面上。
--   ⇒ 直接在节拍里扫整个 UI 就是**当年卡死的那条路**；这里拆成**每帧固定节点预算、跨帧接着走**：
--   `LF_DIG_PER` 节点/帧 · 总量 `LF_DIG_MAX` · 深度上限 `LF_DIG_DEPTH`（都用写死的常量）。
--   ★命中 ⇒ 把**完整链**写进取证环（我读存档就能烘 `LF_FIXES[].paths`）；扫完/撞上限 ⇒ 如实说没找到。
--   ★链上出现**匿名节点**（`GetName()` 读不到）就记 `?` —— 烘焙时一眼看出那一级没法照名字走。
local LF_DIG_PER = 400
local LF_DIG_MAX = 20000
local LF_DIG_DEPTH = 8

-- 帧的**唯一创建口**（keep 复查 / 分帧深挖 / 存档未就位的重试 —— 三种活共用**同一个**节拍帧）
local function lfFrameEnsure()
  if LF.keepFrame then return LF.keepFrame end
  if type(CreateFrame) ~= "function" then return nil end
  local kf = CreateFrame("Frame", "EVAL_LF_KEEP", lfHost())
  LF.keepFrame = kf
  return kf
end

-- 存档未就位时的**有界重试**（原来自带第二帧；1.75.109 并进唯一节拍：0.5s 一拍、上限 20 次）
--   ★`EVAL_LF_INSTALL` 是全局函数（定义在下面）⇒ 调用时按全局名字解析，不是编译期绑定（不违 R2）。
local function lfRetryBeat(a1)
  local r = LF.retry
  if type(r) ~= "table" then return end
  if LF.installed then LF.retry = nil return end
  local dt = lfNum(a1, nil)
  if not dt then dt = lfNum(arg1, 0.05) end
  if (not dt) or dt < 0 then dt = 0.05 end
  r.acc = lfNum(r.acc, 0) + dt
  if r.acc < 0.5 then return end
  r.acc = 0
  r.tries = lfNum(r.tries, 0) + 1
  if EVAL_LF_INSTALL() then
    lfLog("INSTALL：就位后第 " .. tostring(r.tries) .. " 次重试成功")
    LF.retry = nil
  elseif r.tries >= 20 then
    say("图层隐藏：存档重试 20 次仍未就位（期间未写入，不会抹数据）；下次 /reload 再试")
    LF.retry = nil
  end
end

local function lfDigStop(why, hitChain)
  local d = LF.dig
  LF.dig = nil
  if type(d) ~= "table" then return end
  if type(hitChain) == "table" then
    local line = string.format("[深挖] 找到 %s ← %s（%d 个节点 / %d 帧）",
      tostring(d.target), table.concat(hitChain, "/"), lfNum(d.n, 0), lfNum(d.ticks, 0))
    LF.digLast = line
    lfRingPush(line)
    lfLog("DIG HIT " .. tostring(d.target) .. " chain=" .. table.concat(hitChain, "/"))
    say("图层隐藏深挖：找到 " .. tostring(d.target) .. " —— " .. table.concat(hitChain, "/") ..
      "（已写进取证环，可让 AI 烘成内置路径）")
  else
    local line = string.format("[深挖] %s **没找到**（%d 个节点 / %d 帧，%s）—— 名字可能不对，或被合成名替代",
      tostring(d.target), lfNum(d.n, 0), lfNum(d.ticks, 0), tostring(why or "扫完"))
    LF.digLast = line
    lfRingPush(line)
    lfLog("DIG MISS " .. tostring(d.target) .. " why=" .. tostring(why) .. " n=" .. tostring(d.n))
    say("图层隐藏深挖：" .. tostring(d.target) .. " 深挖也没找到（" .. tostring(why or "扫完") .. "）—— 详见取证环")
  end
  lfBeatSync()
end

-- 深挖的**一拍**：处理至多 `LF_DIG_PER` 个节点（迭代式 DFS，绝不递归 ⇒ 不可能爆栈）
local function lfDigStep()
  local d = LF.dig
  if type(d) ~= "table" then return end
  d.ticks = lfNum(d.ticks, 0) + 1
  local budget = LF_DIG_PER
  while budget > 0 do
    local ns = table.getn(d.stack)
    if ns <= 0 then lfDigStop("扫完") return end
    local top = d.stack[ns]
    table.remove(d.stack, ns)
    if not d.seen[top.o] then
      d.seen[top.o] = true
      d.n = lfNum(d.n, 0) + 1
      budget = budget - 1
      if d.n > LF_DIG_MAX then lfDigStop("撞总量上限 " .. tostring(LF_DIG_MAX)) return end
      if lfFrameUsable(top.o) then
        local kids = lfKids(top.o)
        for i = 1, table.getn(kids) do
          local k = kids[i]
          if (not d.seen[k]) and lfFrameUsable(k) and type(k.GetName) == "function" then
            local ok, kn = pcall(k.GetName, k)
            if ok and kn == d.target then
              local chain = {}
              for x = 1, table.getn(top.chain) do chain[x] = top.chain[x] end
              table.insert(chain, kn)
              lfDigStop(nil, chain)
              return
            end
            if top.d < LF_DIG_DEPTH then
              local c2 = {}
              for x = 1, table.getn(top.chain) do c2[x] = top.chain[x] end
              table.insert(c2, (ok and type(kn) == "string" and kn ~= "") and kn or "?")
              table.insert(d.stack, { o = k, chain = c2, d = top.d + 1 })
            end
          end
        end
      end
    end
  end
  lfBeatSync()
end

-- ============ 节拍**唯一入口**（挂/摘只此一处；一个模块只许一个节拍帧）============
--   ★要挂的条件 = 「keep 复查窗口还在跑」**或**「深挖还在跑」；两者都停 ⇒ **真摘**（`SetScript(…, nil)`）。
--   ★幂等：重复「要挂」不重复挂；`lfArm` / `lfStop` / `lfDigStep` / `lfDigStart` 全走它。
--   ★★定义处用**赋值**（顶部已前向声明 `local lfBeatSync, lfBeat`）—— 见那边那段 R2 说明。
--   ★★★1.75.109：**本模块只有这一帧**（`EVAL_LF_KEEP`）—— 原来「存档未就位的重试」自带第二帧
--   （`EVAL_LF_INSTALL_RETRY` + 4 处 `SetScript`）已并进来（`LF.retry` 腿）⇒ 全文件 `SetScript` 只剩
--   「这一次挂」与「这一次摘」两处，harness 的 A18 结构钉直接数这个数（一个模块只许一个节拍帧）。
lfBeatSync = function()
  local need = (LF.keepDone ~= true) or (type(LF.dig) == "table") or (type(LF.retry) == "table")
  local kf = LF.keepFrame
  if not kf then
    if not need then return false end
    kf = lfFrameEnsure()
  end
  if not kf or type(kf.SetScript) ~= "function" then return false end
  pcall(kf.SetScript, kf, "OnUpdate", need and lfBeat or nil)
  return need
end

-- 唯一的 handler（零形参：dt 只能从全局 `arg1` 取 —— 本项目在案）
lfBeat = function(a1)
  if type(LF.retry) == "table" then lfRetryBeat(a1) end
  if LF.keepDone ~= true then lfKeepBeat(a1) end
  if type(LF.dig) == "table" then lfDigStep() end
  lfBeatSync()
end

-- 起一次深挖（`/eh go 图层隐藏 深挖 [名字]` 的唯一实现）——**只读**：不改界面、不写配置
local function lfDigStart(nm)
  if type(nm) ~= "string" or nm == "" then return false, "没给要深挖的名字" end
  local rootKey = "UIParent"
  local root = lfFrameOf(rootKey)
  if not (root and lfFrameUsable(root)) then return false, "找不到 UIParent（深挖的起点）" end
  if type(CreateFrame) ~= "function" then return false, "建不出节拍帧（客户端接口不可用）" end
  local kf = LF.keepFrame
  if not kf then
    kf = CreateFrame("Frame", "EVAL_LF_KEEP", lfHost())
    LF.keepFrame = kf
  end
  LF.dig = { target = nm, stack = { { o = root, chain = { rootKey }, d = 0 } }, seen = {}, n = 0, ticks = 0 }
  lfRingPush(string.format("[深挖] 开始找 %s（每帧 %d 节点 / 总量上限 %d / 深度上限 %d）—— 分帧跑，不会卡",
    nm, LF_DIG_PER, LF_DIG_MAX, LF_DIG_DEPTH))
  lfLog("DIG START " .. nm)
  lfBeatSync()
  return true
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
  lfBeatSync()   -- ★唯一入口（要挂就挂）
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
    -- ★1.75.109：重试并进**唯一节拍**（原来自带第二帧 `EVAL_LF_INSTALL_RETRY` —— 一个模块只许一个节拍帧）
    LF.retry = { acc = 0, tries = 0 }
    lfBeatSync()
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

-- ★★★1.75.109 深挖入口（`/eh go 图层隐藏 深挖 [名字]`）：**只读**（不改界面、不写配置）
--   ★不给名字就自动挑「第一条**还没有内置路径**的具名对象」—— 真机实测那就是三级都没命中的那一片
--     （1.75.109 日志：`MainMenuBarAnimFrame`）。结果写进 `layerFixProbe` 环 ⇒ 我读存档就能烘 `paths`。
function EVAL_LF_DIG(nm)
  if type(nm) ~= "string" or nm == "" then
    nm = nil
    for i = 1, table.getn(LF_FIXES) do
      local f = LF_FIXES[i]
      if tostring(f.kind or "") == "hideObj" and type(f.objs) == "table" then
        for k = 1, table.getn(f.objs) do
          local spec = f.objs[k]
          local cands = (type(spec) == "table") and spec.cands or { spec }
          local cand = tostring(cands[1])
          if not ((type(f.paths) == "table") and (f.paths[cand] ~= nil)) then
            nm = cand
            break
          end
        end
      end
      if nm then break end
    end
  end
  if type(nm) ~= "string" or nm == "" then return false, "所有具名对象都已有内置路径（没有要深挖的）" end
  if type(LF.dig) == "table" then return false, "上一次深挖还在跑（目标 " .. tostring(LF.dig.target) .. "）" end
  local ok, err = lfDigStart(nm)
  return ok, nm, err
end

-- 深挖的只读状态（体检口用）
function EVAL_LF_DIG_STATE()
  local d = LF.dig
  if type(d) ~= "table" then return false, LF.digLast or "无" end
  return true, string.format("%s：已走 %d 个节点 / %d 帧", tostring(d.target), lfNum(d.n, 0), lfNum(d.ticks, 0))
end

-- [重置]：还原全部已生效的处理 + 清空勾选（**如实报数字**；没勾任何条目也照样报「无事可做」）
function EVAL_LF_RESET()
  local restored, n = 0, table.getn(LF_FIXES)
  for i = 1, n do
    local f = LF_FIXES[i]
    restored = restored + lfResetOne(f, false)
    if lfFixOn(f.key) then lfSet(f.key, false) end
  end
  say(string.format("图层隐藏：重置完成 —— 还原 %d 个对象 · 已清空 %d 条处理的勾选（要再启用请点 [设置]）",
    restored, n))
  return restored
end

-- ============ 只读取证（1.75.109；「动作条背景初次勾选卡死」的定案口）============
-- 一条命令拿全部数字：`/eh go 图层隐藏`（别名 `/eh go lf`）⇒ 本函数 + 有界落盘环 `layerFixProbe`
--   （★那个环平时**每次解析都自动写** —— 用户「开关一下、我读日志」的工作流不依赖这条命令）。
--   ★为什么必须有它：卡死的真机读数（**UIParent 到底多大 / 7 个名字各在第几级命中 / 一趟扫了多少节点 /
--   路径缓存有没有建起来**）只能真机回答；而按本项目纪律「AI 自己读存档、不让用户转述」⇒ 全文进有界环。
--   ★本函数**一个字节都不写界面**（不 Hide / 不记 fixState / 不写配置）—— 只追加取证环。
-- 一个帧的**规模**（★只问答数、**绝不枚举** —— 这正是 EH_DebugBox 1.75.48 的级联手法：
--   `GetNumChildren/GetNumRegions` 拿不到才如实写「判不出」，绝不退回「枚举一遍数个数」）
local function lfSizeOf(f)
  if not f then return nil, nil end
  local k, r = nil, nil
  if type(f.GetNumChildren) == "function" then
    local ok, v = pcall(f.GetNumChildren, f)
    if ok and tonumber(v) then k = tonumber(v) end
  end
  if type(f.GetNumRegions) == "function" then
    local ok, v = pcall(f.GetNumRegions, f)
    if ok and tonumber(v) then r = tonumber(v) end
  end
  return k, r
end

function EVAL_LF_PROBE()
  local out = {}
  local function P(s) table.insert(out, tostring(s)) end
  P(string.format("图层隐藏体检：预算 %d 节点/趟 · 兜底深度 %d · 落盘环上限 %d 行",
    LF_SCAN_MAX, LF_SCAN_DEEP, LF_SCAN_KEEP))
  -- ① 两条处理各自的勾选 / 生效状态
  for i = 1, table.getn(LF_FIXES) do
    local f = LF_FIXES[i]
    local st = LF.fixState[f.key]
    local on = lfFixOn(f.key)
    P(string.format("· [%s] 勾选=%s 生效=%s%s", tostring(f.key), on and "是" or "否",
      (type(st) == "table") and ("是（已藏 " .. tostring(table.getn(st.objs)) .. " 个）") or "否",
      (type(LF.capKeys) == "table" and LF.capKeys[f.key]) and "｜★本会话已撞过预算（不再深扫）" or ""))
    -- ★路径缓存的状态（用户的工作流就靠这两个数：内置烘了几条 / 运行时学到了几条）
    local builtN = 0
    if type(f.paths) == "table" then for _ in pairs(f.paths) do builtN = builtN + 1 end end
    P(string.format("· [%s] 路径：内置 %d 条 ｜ 运行时缓存 %d 条 ｜ 最近一照路径命中 %s 项",
      tostring(f.key), builtN, lfPathCount(f.key), tostring(lfNum(f.lastByPath, 0))))
  end
  -- ② UIParent 的规模（**只问答数**；这是「旧写法为什么会卡死」的直接读数）
  local ui = rawget(_G, "UIParent")
  local uc, ur = lfSizeOf(ui)
  P(string.format("· UIParent：%s ｜ 直接子件=%s 区域=%s（旧兜底容器从这个根深扫 2 层 = 上万次调用/趟）",
    ui and "在" or "不在", (uc ~= nil) and tostring(uc) or "判不出", (ur ~= nil) and tostring(ur) or "判不出"))
  -- ★分帧深挖的状态（`/eh go 图层隐藏 深挖` 的进度 / 上次结果）
  local digOn, digTxt = EVAL_LF_DIG_STATE()
  P(string.format("· 深挖：%s（%s）", digOn and "正在跑" or "没在跑", tostring(digTxt)))
  -- ③ 逐条 hideObj：**三级体检**（哪一级命中 / 一趟扫多少节点 / 有没有撞预算）—— 全只读
  for i = 1, table.getn(LF_FIXES) do
    local f = LF_FIXES[i]
    if tostring(f.kind or "") == "hideObj" and type(f.objs) == "table" then
      lfScanN, lfScanCap = 0, false
      P(string.format("· [%s] 具名对象 %d 个（只读体检，顺序=ⓠ路径 ①全局名 ②真实父级 ③兜底容器）",
        tostring(f.key), table.getn(f.objs)))
      for k = 1, table.getn(f.objs) do
        local spec = f.objs[k]
        local cands = (type(spec) == "table") and spec.cands or { spec }
        local inList = (type(spec) == "table") and spec.parent or nil
        local nm = tostring(cands[1])
        local lvl, hit = "-", nil
        -- ⓠ 路径（内置优先，其次运行时缓存）—— 这也是**真机日志要烘的那份链**
        local chain = (type(f.paths) == "table") and f.paths[nm] or nil
        local from = "内置"
        if type(chain) ~= "table" then chain = lfPathGet(f.key, nm) from = "缓存" end
        if type(chain) == "table" then
          hit = lfPathWalk(chain)
          if hit then
            lvl = "ⓠ" .. from .. "路径（" .. table.concat(chain, "/") .. "）"
          else
            lvl = "ⓠ" .. from .. "路径**失效**（" .. table.concat(chain, "/") .. "）"
          end
        end
        if not hit then
          local g = lfFrameOf(nm)
          if g and lfFrameUsable(g) then lvl, hit = "①全局名", g end
        end
        if not hit then
          hit = lfNamedScan(inList, nm, 1)
          if hit then lvl = "②真实父级" end
        end
        if not hit then
          hit = lfNamedScan(f.containers, nm, LF_SCAN_DEEP)
          if hit then lvl = "③兜底容器" end
        end
        P(string.format("    %s → %s%s", nm, lvl,
          hit and "" or (lfScanCap and "（★预算用尽：没敢继续扫 ⇒ 判不出）" or "（都没命中）")))
      end
      P(string.format("    本趟访问节点数 = %d%s", lfScanN,
        lfScanCap and ("（★撞预算上限 " .. tostring(LF_SCAN_MAX) .. "，已提前停）") or "（未撞预算）"))
    end
  end
  P("用法：勾上/取消在 工具箱 → 图层隐藏 → [设置]（多选）；本体检只读，不改界面、不写配置")
  -- ★全文进有界落盘环（AI 自己读存档；聊天里只回显这几行）
  for i = 1, table.getn(out) do lfRingPush(out[i]) end
  lfRingPush("—— 体检结束（" .. tostring(table.getn(out)) .. " 行）——")
  return out
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

