-- EvalHelp / tools/DragFrames.lua
--
-- 框拖拽（**独立工具模块**；用户 1.74.29：「图层拖拽是个独立的工具，和地图功能没关系」，
-- 1.74.30：「把这块代码抽成 ./tools 下的独立工具模块」）。
--
-- 本文件 = 从子插件 `addons/EH_DebugBox/EH_DebugBox.lua` 整块搬来的框拖拽实现（那一侧只留瘦转发）。
-- ★自包含：自己的宿主 / 纯色纹理助手 / 下拉弹窗 / 拖拽柄 / 全屏接盘 / **启动期有界复查** / **自己的存档**
--   （落点 `EVAL_HELP_CONFIG.dragFrames[帧名]`，不再用子插件的 `EH_DEBUGBOX_CFG.cust["[全局] 名"]`）。
-- ★对外只暴露：`EVAL_DF_ENABLED / EVAL_DF_SET / EVAL_DF_SUMMARY / EVAL_DF_RESET / EVAL_DF_APPLYALL`
--   （工具箱那一行直接读写它们；**那一行的控件本身也在本文件里**，工具箱只按名字取）+ 若干 `EVAL_DF_*` 诊断/读值口。
-- ★纪律：本文件只用**全局桥**（EVAL_SAY / EVAL_LOGLINE / EVAL_L / rawget(_G,"EVAL_HELP_CONFIG")），
--   绝不引用 EvalHelp.lua 或子插件的文件内 local。装配点在 EvalHelp.lua 的 VARIABLES_LOADED → `EVAL_DF_INSTALL()`。
--
-- ★★★1.74.30 三条真因（本轮审计定案，逐条给出证据）
--  ① 拖拽结束不掉（目标层一直跟着鼠标走）：
--     · `IsMouseButtonDown` **本客户端没有**。证据：官方 API 索引（api_*.html，1328 条唯一函数名）里查无此名；
--       整个游戏 `Interface/AddOns` 目录里除本插件自己的引用外**零出现**（UnrealQuest 14590 行的 ClientAPI.lua 也没有）。
--       ⇒ 旧实现那句 `if type(IsMouseButtonDown) == "function"` 的兜底是**死代码**（从不执行）。
--     · 于是唯一的结束路径 = 拖拽柄的 OnMouseUp，而它只在「松手那一刻指针还在柄上」时才来；
--       旧的 2 秒定时复查会把目标**瞬移回存档位置**（见 ③）→ 柄跟着目标跑掉 → 指针不在柄上 ⇒ OnMouseUp 永不到来。
--  ② 配置窗贴在屏幕左下角：`ClearAllPoints` 之后位置就是 **(0,0)** —— 官方 wiki（Region:ClearAllPoints 明文：
--     "Removes every anchor ... if the position is (0, 0)"；SetPoint 又写明「新建帧有一个默认 BOTTOMLEFT 种子」）。
--     看到左下角 ⇒ **清锚点成功了、SetPoint 没生效**（旧实现把它包在 pcall 里**静默吞掉**结果，也没读回自证）。
--     本模块：位置改成**相对自己的父级**、偏移由**实测几何**算出来，设置后**读回自证**；
--     读回不对 → 退回「改挂 UIParent + CENTER/CENTER」（与配置窗同一个已被日常使用的写法）；两条都失败则如实记 mode=failed。
--  ③ 拖拽期间定时复查抢锚点：旧实现每 2 秒按存档重锚 5 个目标 —— 拖拽中目标位置与存档必然不同 ⇒ 判「漂了」⇒ 回写
--     ⇒ 与手动拖拽抢锚点（位移/闪烁），并把柄从指针下挪走 —— 这正是 ① 的直接触发者。
--     本模块：`DF.dragging` 为真时**整体跳过**定时复查，拖拽结束后补一次。
--
-- ★★★1.74.31【任务 A】复查从「每 2 秒**常驻**」改成「**启动期有界**」（用户原话：「首次出现并且设置成功参数之后，
--   间隔 1s 检查 5 次，之后都符合参数之后就不再定时检查；也就是定时检查**最大检测时间为屏幕载入完成 5s 内**」）：
--   ① 首次出现（`EVAL_DF_INSTALL` 登录/进世界；或本次会话里刚把开关打开）→ 先 `dfApplyAll` 应用一次存档参数；
--   ② 再 `dfKeepArm` 武装窗口：每 `DF_KEEP_PERIOD`(=1s) 复查一次，**净检查 5 次**；
--   ③ 5 次都没有漂移 ⇒ 一次都不重设，第 5 次结束 **`dfKeepStop("allok")` 永久停**（OnUpdate 脚本被摘掉）；
--   ④ 期间漂移 ⇒ 立刻按存档重设并继续复查，5 次用完照样停（结束行带数字如实播报，**不静默**）；
--   ⑤ 战斗中/拖拽中跳过（不重锚、不计净检查次数），但评估次数(12)/墙钟(15s)两条上限兜住 —— 窗口**不会**无限延长。
--   ★★取舍：窗口结束后不再有人修正「用户后来手动改动 / 切地图把层挤动」（**用户明确要的**）——
--     那种场合靠工具箱 [重置] 或重登重走一次启动期复查。这是有意为之，不是漏做。
--
-- ★★★另修一处独立缺陷（① 的帮凶）：旧 `uiDragPopHide()` 只藏了弹窗与下拉，**没藏全屏遮罩**
--   （`EH_DB_DRAGCOVER`，FULLSCREEN_DIALOG/1150 的鼠标吃子）⇒ 第一次弹窗之后，全屏范围内**所有鼠标事件都被它吃掉**，
--   拖拽柄（level 450）再也收不到 mousedown，后续拖拽直接失效。现在：弹窗 root 的 OnHide 统一收遮罩（单一出口）。
--
-- ★★★本客户端的两条已实测/已文档化的锚点事实（决定了本文件的写法，别再退回旧写法）：
--   · `GetPoint` 的第 2 个返回值是**相对帧的名字字符串（不是帧对象）**，父级锚点无名字时返回 "auto"
--     （官方 wiki Region:GetPoint 明文；UnrealQuest 也记为 BEHAVIOR_VERIFIED）。
--     旧实现 `uiRelName(rel)` 只认帧对象 ⇒ 字符串一律变 nil ⇒ 回写时相对帧丢失、退化成「父级」。
--   · `GetPoint` 的 y 与传入 `SetPoint` 的 y **符号口径有歧义**（wiki 说内部存储取反；UnrealQuest 2026-09-17 的定点探针
--     在 UIParent 同名锚点上量到 18/18 同号）⇒ **绝不把 GetPoint 返回的偏移当 SetPoint 的入参**（那是「镜像」的发源地）。
--     本模块改用**测量边**（GetLeft/GetBottom/GetWidth/GetHeight，官方 wiki：UI 像素、原点左下、Y 向上）构造偏移；
--     GetPoint 只用来读**锚点名**（point / relPoint）与相对帧**名字**。
--（文件头说明到此结束）

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

-- ★★★1.75.101 删掉这里原来的 `local say, logLine = EVAL_SAY, EVAL_LOGLINE` + `local L = EVAL_L`：
--   那是把**上面自带的** say/logLine/L（每次调用现读全局桥）**覆盖成载入期快照** —— 与上面那段注释的契约
--   （「模块必须自带 say/logLine」）正好相反，且**桥晚到就是 nil** ⇒ 之后每一句 `say(...)` 都是
--   `attempt to call a nil value`（被 pcall 吞掉 = 播报全静默；没被吞就是整段炸）。判据 harness 当场抓到。

-- ============ 常量 ============
local DF_DRAG_H = 20            -- 拖拽柄高度（贴目标左上角）
-- ★★★1.74.31【任务 A】定时复查改成「启动期有界复查」（用户原话：「首次出现并且设置成功参数之后，
--   间隔 1s 检查 5 次，之后都符合参数之后就不再定时检查；也就是定时检查**最大检测时间为屏幕载入完成 5s 内**」）
--   ⇒ 旧的「每 2 秒**常驻**复查」被整体换掉：周期改 1s、净检查 5 次、做完**永久停止**（OnUpdate 脚本被摘掉）。
-- 语义（逐条都有断言，组 204）：
--   ① 目标首次出现（登录/进世界 = `EVAL_DF_INSTALL`；或用户本次会话里刚把开关打开）→ **先应用一次**存档参数；
--   ② 之后每 `DF_KEEP_PERIOD` 秒复查一次，**净检查 `DF_KEEP_CHECKS` 次**（= 载入完成后 5 秒内结束）；
--   ③ 这 5 次都没有漂移 → **一次都不重设**，并在第 5 次结束时永久停止（不再有常驻 tick）；
--   ④ 中途发现漂移 → 立刻按存档重设一次并**继续**复查，5 次用完照样停（结束行带数字如实播报，不静默）；
--   ⑤ 战斗中 / 拖拽中**跳过**（不重锚、不计净检查次数）——既有口径照旧，不退化。
-- ★★「跳过不会让窗口无限延长」的三条上限（任一到达即永久停，口径唯一）：
--   · 净检查 `DF_KEEP_CHECKS` 次（跳过的不算）· 含跳过在内的评估 `DF_KEEP_TRIES` 次 · 墙钟 `DF_KEEP_WALL` 秒（绝对）。
local DF_KEEP_PERIOD = 1.0      -- 复查周期（秒）——用户定「间隔 1s」
local DF_KEEP_CHECKS = 5        -- 净检查次数上限（5 次 × 1s ⇒ 载入完成后 5 秒内收工）
local DF_KEEP_TRIES = 12        -- 含跳过在内的评估次数上限（一直战斗/拖拽也不会没完没了）
local DF_KEEP_WALL = 15.0       -- 绝对墙钟上限（秒）：从「武装」那一刻起算，任何情况都不许超过它
local DF_DRAG_IDLE_END = 2.0    -- 指针连续 N 秒没动 → 自动结束拖拽（最后一道兜底）
local DF_DRAG_MAX = 120         -- 单次拖拽绝对上限（秒）
local DF_POP_W, DF_POP_H = 250, 224
-- ★★★1.75.1 聊天窗的弹窗多出「宽/高」两行（每行 28px 行距）⇒ 窗高要跟着加，否则两行会压到底部 取消/保存 上。
--   ★底部两个按钮锚在 **BOTTOM** ⇒ 窗高一变自动跟着走，不需要重排任何控件。
local DF_POP_H_SIZE = DF_POP_H + 56
-- ★1.74.31：柄池上限**由目标数派生**（原来写死 8、注释写着「目标表最多也就 5 个」——
--   加了战斗记录与 4 个动作条之后目标到 10 个，写死值会在最坏情况下悄悄少贴几条柄）
local DF_POOL_MAX
local DF_SCALE_PRESETS = { 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3 }
local DF_ALPHA_PRESETS = { 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 }
-- ★★★1.75.1 宽/高预设（**只给聊天窗**用）：与共用下拉同一条约束 —— 项数 ≤ 10（列表只有 10 行、没有滚动）
local DF_W_PRESETS = { 200, 300, 384, 450, 512, 600, 700, 800, 900, 1000 }
local DF_H_PRESETS = { 100, 120, 150, 180, 200, 250, 300, 400, 512, 600 }
-- ★★★1.74.31 用户要求：「图层拖拽 完成弹窗属性设置还要增加当前层宽度/高度设置」
--   预设表按「这 6 个目标的实际尺寸量级」选：头像/小地图偏小、聊天框与动作条偏宽。
--   ★张数必须 ≤ 共用下拉列表的行数（列表行数按 DF_ALPHA_PRESETS 建 = 10 行）。
local DF_WIDTH_PRESETS = { 100, 150, 200, 250, 300, 400, 500, 600, 800, 1000 }
local DF_HEIGHT_PRESETS = { 30, 40, 50, 60, 80, 100, 120, 150, 200, 300 }
-- ★★★1.74.33 属性弹窗的 **X/Y 坐标行**（用户第二次澄清：「属性配置需要支持调整的是窗口的 x,y 坐标值」）：
--   · **语义（用户选定）= 绝对屏幕坐标**：X = 窗口左边缘、Y = 窗口下边缘（本客户端屏幕坐标原点在左下角，
--     实测值域 ≈ X 0~1228 / Y 0~768，见 R15 ⑥d 的探针数据）。**不是**相对位移、也不是相对当前位置的微调。
--   · **控件（用户选定）= 下拉预设 + [−][+] 微调按钮**（本客户端 EditBox 疑似不渲染 ⇒ 不做打字输入）。
--   · ★预设**最多 10 项**：共用下拉列表只有 10 行、没有滚动（见 DF_ALPHA_PRESETS 那条注释）⇒
--     预设给「粗档」，精调交给按钮（每次 ±10px；按住 Shift ±1px）。
--   · ★落锚一律走 `dfPlaceFrom`（量回自证 + 手量折算）——**绝不允许**在这里算出坐标后直接 SetPoint：
--     那样就又回到「把屏幕量当本地偏移用」的老坑（用户上一轮报的『拖完下次打开位置不对』正是它）。
local DF_X_PRESETS = { 0, 100, 200, 300, 400, 500, 700, 900, 1100, 1228 }
local DF_Y_PRESETS = { 0, 50, 100, 200, 300, 400, 500, 600, 700, 768 }
local DF_XY_NUDGE = 10                    -- [−][+] 每次 ±10 像素
local DF_XY_NUDGE_FINE = 1                -- 按住 Shift 时 ±1（对缝用）
local DF_XY_MIN, DF_XY_MAX = -400, 1700    -- 允许把窗口推出屏幕边缘（合法需求），但不许无界

-- ★★固定目标表（与地图扫描源无关）。★口径已两次放宽：动作条1~4（1.74.31）· **宠物动作条**（1.75.x）已补进；
--   姿态条仍不列（用户没点名）。
local DF_TARGETS = {
  -- ★★1.75.36n 推广（用户两句：「拖拽方案调整应用到其他常驻层」+「聊天窗的方块定位锚点,和编辑功能还没同步到新方案」）：
  --   `block = true` 扩到**全部常驻层 12 个**（底部条族 7 + 头像/目标头像/小地图 + 聊天框/战斗记录）。
  --   ★聊天框两条的**特殊处照旧**：守卫依旧豁免（dfSizeOK ⇒ 不进候选 —— 用户早定「聊天框不需要守卫」，
  --     它自带拖动/拖角缩放，守卫会跟手抢）；宽/高编辑照旧开放（dfSizeOK）；变的只是**定位也走方块**。
  --   ★注意边界（如实告知）：客户端 FCF 会自己重锚聊天框（切页/停靠变化时）⇒ 我们的接管锚点可能被顶掉，
  --     而守卫不管它 ⇒ 下一次「关闭编辑模式 / /reload」的应用时才拉回记录位置（与老方案同一口径，没变差）。
  { name = "PlayerFrame", label = "用户头像", block = true },
  { name = "TargetFrame", label = "目标头像", block = true },
  { name = "MinimapCluster", label = "小地图", block = true },
  -- ★★★1.75.36b 用户要求（真机截图：「排查下聊天窗 鼠标移动上去才显示的这个透明层能否往上移动一点.默认固定处理」）：
  --   现象：这族帧的柄**静息时 alpha 只有 0.38**（悬停才升到 0.62）⇒ 看着像「鼠标移上去才有」；
  --     而 `ChatFrame1` 的左上角恰好在**第一条聊天正文**那一行 ⇒ 柄带压住系统消息。
  --   处置 ①（1.75.36b）：先整体上移半个柄高（`hdy = DF_DRAG_H / 2`）⇒ 压到「标签行 ↔ 正文首行」的缝上；
  --   处置 ②（1.75.36c 用户改口）：「**聊天窗的拖拽层.相对聊天窗垂直居中定位**」⇒ 改成 `hcenterY = true`：
  --     柄**锚到目标的 `CENTER`**（由客户端自己居中 ⇒ 天然与缩放无关，不用自己算高度/除缩放）。
  --   ★只挪柄、帧本身与存档一个字节都不动；聊天框与战斗记录两页共用同一几何 ⇒ 一起给。
  { name = "ChatFrame1", label = "聊天框", hcenterY = true, block = true }, -- 综合（★1.75.36n 起归方块；hcenterY 留作柄带时代的记录，方块路径不读它）
  -- ★★1.74.30 用户：「战斗记录的图层知道名称吗？也加入可拖拽配置」
  --   本客户端聊天窗：综合 = ChatFrame1、**战斗记录 = ChatFrame2**（同一窗口分页）
  { name = "ChatFrame2", label = "战斗记录", hcenterY = true, block = true }, -- 战斗记录页（同一窗口的另一页 ⇒ 同几何；同上归方块）
  -- ★★★1.75.36h 用户要求：「需要经验条的拖拽层往上移动,主动作条的拖拽往下移动.错开.现在重叠了」
  --   ⇒ 主条的柄**下移一个柄高**（`hdy = -DF_DRAG_H`）、经验条的柄**上移一个柄高**（见下表那条），
  --     两条柄的纵向间隔因此 ≥ 一个柄高 ⇒ 任何「上边差 ≥ 0」的摆位下都不重叠（推导见经验条那条注释）。
  --   ★hy 的口径 = **上移为正**（柄锚法 `SetPoint(hpt, fr, hpt, hx, hy)`）。
  -- ★★★1.75.36l 用户定稿：「给每个自定义图层在最外层加一个锚点（定位方块）…守护就以方块的绝对坐标更新」+
  --   「1.取代〔旧的 20px 柄带〕2.先验证〔先做底部条族〕」⇒ 这一族改用**方块**：
  --   `t.block = true` ⇒ `dfRefresh` 不再给它贴整条透明柄，改画一个 20×20 的方块（颜色区分 + 标题），
  --   目标被**接管锚点**到方块上 ⇒ 位置 = 方块的绝对坐标。
  --   ★1.75.36n 三连调整（用户）：① 推广到全部常驻层（见本表顶部三条）② 方块透明度 **0.8**
  --     ③ 定位 = 目标层**中心**（`CENTER ← 方块/CENTER, 0, 0`；ax/ay = 中心绝对坐标，与缩放无关）；
  --     ④ 关闭编辑模式方块一起隐藏（dfRefresh 的方块同步**不受 `if DF.on` 门管**）。
  { name = "MainMenuBar", label = "主动作条", hdy = -DF_DRAG_H, block = true },
  -- ★★★1.75.36 用户要求：「将经验条也加入图层拖拽->常驻层可选项」
  --   （真机截图：`MainMenuExpBar` 已被手动拖过 −3,+39 / 透明 0.40 = 用户就是要给它一个**常驻拖拽柄**）
  --   ★真名有**本地证据**：`/edb ui` 的图层树里它是 `MainMenuBar` 的子帧（1024×13，含 4 片 `MainMenuXPBarTexture0..3`）。
  --   ★不带 roster/icon/pet 标记 ⇒ 自然归第 1 组「常驻层（拖拽柄）」（分组由 `EVAL_DF_PICK_MENU` 现算，标签不写死）。
  --   ★与主条（`MainMenuBar`，本表上面那条）**各自一个柄**：拖哪个动哪个；主条动了经验条会跟着（父子关系）。
  --   ★★★柄带定位四改（每次都是真机截图驱动的「一句话调整」，只动这一个常量）：
  --     ① 最初：`hdy = -(DF_DRAG_H + 2)` —— 主条与经验条**左上角完全重合**（真机树：两者上边 Y53、左边 X173）
  --        ⇒ 两条 20px 柄精确叠在一起（后画的盖住先画的）⇒ 把经验条柄下移 22px 错开。
  --     ② 1.75.36e（用户：「经验条的拖拽位置移动到经验条上面」）：用户已经把**经验条本身**挪上去了
  --        （真机存档里那条调试自定义：`MainMenuExpBar dx=-2.9 dy=+39.1`，即比主条顶边高 39px）
  --        ⇒ 两条柄不再可能重合，**去掉下移量**，柄带就贴在经验条自己身上（hdy 归 0 = 左上角对齐）。
  --     ③ 1.75.36h（用户：「需要经验条的拖拽层往上移动,主动作条的拖拽往下移动.错开.现在重叠了」）：
  --        经验条又回到「与主条左上角相距不到一个柄高」的摆位 ⇒ 两条柄再次重叠 ⇒ 改成**各自朝相反
  --        方向让开一个柄高**：经验条 hdy = +DF_DRAG_H（往上）· 主条 hdy = -DF_DRAG_H（往下，见上表那条）。
  --     ★判据（为什么这样就一定不再重叠）：柄锚法 = SetPoint(hpt, fr, hpt, hx, hy)（**hy 上移为正**）、
  --       柄高恒为 DF_DRAG_H ⇒ 屏上区间 = [上边 - hy, 上边 - hy + DF_DRAG_H]。设经验条上边 = Tx、
  --       主条上边 = Tm、g = Tm - Tx（常态 g >= 0），两者不重叠 ⇔ hy_xp - hy_m >= DF_DRAG_H - g；
  --       取 hy_xp = +DF_DRAG_H、hy_m = -DF_DRAG_H ⇒ 左边恒 = 2 x DF_DRAG_H ⇒ 只要 g >= -DF_DRAG_H
  --       就绝不重叠（**含 g = 0 即两者左上角完全重合那种最坏情况**）。
  --     ★以后若又重叠：先看这两个常量是否还在 ±DF_DRAG_H，再按「谁压住谁」调绝对值（一个数的事）。
  { name = "MainMenuExpBar", label = "经验条", cands = { "MainMenuExpBar" }, hdy = DF_DRAG_H, block = true },
  -- ★★★1.74.31 用户要求：「图层拖拽 将 动作条1,2,3,4 也加入可拖拽项」。
  --   ★★本客户端（UE 重写）的动作条帧名**没有本地证据**：客户端 UI 编译在 pak 里，磁盘上既没有 FrameXML、
  --     别的插件也一次都没引用过 MultiBar*（本地取证：Interface 下只有 AddOns；SavedVariables 里只有 MainMenuBar）。
  --     ⇒ 不猜一个名字写死，改成**候选名解析**（`cands`）：按顺序取第一个真实存在的帧；
  --       一个都没命中 → 该目标**如实缺席**（不画拖拽条；[重置] 清单末尾单列一行说明），用 `/edb bars` 把真名探出来。
  --   ★存档键（name = 候选第一名）**与命中哪个候选无关** ⇒ 换客户端/改名都不会让老存档对不上。
  { name = "MultiBarBottomLeft", label = "动作条1", block = true,
    cands = { "MultiBarBottomLeft", "MultiBar1", "ActionBar1", "BottomLeftActionBar", "MultiActionBar1", "ActionBarFrame1" } },
  { name = "MultiBarBottomRight", label = "动作条2", block = true,
    cands = { "MultiBarBottomRight", "MultiBar2", "ActionBar2", "BottomRightActionBar", "MultiActionBar2", "ActionBarFrame2" } },
  { name = "MultiBarRight", label = "动作条3", block = true,
    cands = { "MultiBarRight", "MultiBar3", "ActionBar3", "RightActionBar", "RightActionBar1", "MultiActionBar3", "ActionBarFrame3" } },
  { name = "MultiBarLeft", label = "动作条4", block = true,
    cands = { "MultiBarLeft", "MultiBar4", "ActionBar4", "RightActionBar2", "MultiActionBar4", "ActionBarFrame4" } },
  -- ★★★1.75.x 用户要求：「工具→图层拖拽→设置. 常驻层缺少宠物动作条」⇒ 补进**常驻层**。
  --   ★不带 roster/icon 标记 ⇒ 自然归第 1 组「常驻层（拖拽柄）」（分组由 EVAL_DF_PICK_MENU 现算，标签不写死）。
  --   ★帧名同动作条1~4：本客户端 UI 编译在 pak 里（磁盘无 FrameXML、别的插件零引用 PetActionBar*）
  --     ⇒ 走候选名解析；一个候选都没命中就**如实缺席**（不画柄），用 `/edb bars` 探真名（探针已加 pet 关键词组）。
  --   ★★宠物动作条是**按需出现**的（没宠物时不显示）⇒ 与队伍/团队同族，带 `pet = true` 进**有界跟随**：
  --     事件 `UNIT_PET` 有本地证据（本项目 addons/EH_DebugBox/EH_DebugBox.lua 正在注册它）；
  --     ★`PET_BAR_UPDATE` **不注册**——本地零证据（铁律 5④：探测名单不算注册依据）。
  { name = "PetActionBarFrame", label = "宠物动作条", pet = true, block = true,
    cands = { "PetActionBarFrame", "PetActionBar", "PetBarFrame", "PetActionButtonsFrame", "PetBar" } },
  -- ★★1.75.38 用户两句：「将战士/小德姿态条也加入图层拖拽->常驻可选」+「将主动作条内的动作条 加入常驻可选」
  --   （真机截图证据 = 图层树探针报 `#282 BonusActionBarFrame`，框内有两枚姿态图标）。
  --   ★姿态条帧名**没有本地证据**（UI 编译在 pak 里）⇒ 走候选名解析；一个都没命中就**如实缺席**
  --     （编辑模式下不会出现它的方块），真名用 `/edb bars` 探。BonusActionBarFrame 有截图证据 ⇒ 直接写死。
  --   ★两者都**按职业/状态出现**（法师没有姿态条；不切姿态不出额外动作条）⇒ 方块自带 IsShown 门
  --     （目标没显示就不画孤块）；位置漂移由守卫兜底。
  { name = "ShapeshiftBarFrame", label = "姿态条", block = true,
    cands = { "ShapeshiftBarFrame", "StanceBarFrame", "StanceBar", "ShapeshiftBar", "StanceBarFrame1" } },
  { name = "BonusActionBarFrame", label = "主动作条内单独动作条", block = true,
    cands = { "BonusActionBarFrame", "BonusActionBar", "BonusBarFrame" } },
  -- ★★★1.74.32 用户要求：「拖拽图层再增加队伍层,团队层如果存在的话」。
  --   ★「如果存在的话」是**两层**意思，都要如实处理，不许假装：
  --     ① **帧名**同动作条1~4：本客户端 UI 编译在 pak 里（磁盘无 FrameXML、别的插件零引用）
  --        ⇒ 不猜一个名字写死，走候选名解析（`cands`）；一个候选都没命中 → 如实缺席（不画柄）。
  --     ② **帧体本身是「按需出现」的** —— 单人时客户端不显示队伍框、非团队时不显示团队框
  --        ⇒ 「没命中」与「命中但没显示」都算缺席（`dfRefresh` 只给当前显示的目标贴柄）。
  --        ★所以组上人/进团队那一刻必须**补上**：见下面的 `DF_ROSTER_EVENTS`（有界跟随，不做常驻轮询）。
  --   ★★★1.74.32 真机取证定案（探针 `/eh go 框体探针` 实测）：本客户端**没有整队容器帧** ——
  --     队伍就是 `PartyMemberFrame1~4` 四个**各自独立**的帧（探针里 `PartyFrame/PartyMemberFrameContainer/
  --     PartyFrameContainer/PartyContainer` 全部「不在」，只有 `PartyMemberFrame1` 命中）。
  --     ⇒ 用户决定：**拆成「队伍成员1~4」四个可拖拽项**（拖哪个人就动哪一框），不再假装有个「队伍层」整体。
  { name = "PartyMemberFrame1", label = "队伍成员1", roster = true, cands = { "PartyMemberFrame1" } },
  { name = "PartyMemberFrame2", label = "队伍成员2", roster = true, cands = { "PartyMemberFrame2" } },
  { name = "PartyMemberFrame3", label = "队伍成员3", roster = true, cands = { "PartyMemberFrame3" } },
  { name = "PartyMemberFrame4", label = "队伍成员4", roster = true, cands = { "PartyMemberFrame4" } },
  { name = "RaidFrame", label = "团队层", roster = true,
    cands = { "RaidFrame", "RaidFrameContainer", "CompactRaidFrameContainer", "RaidGroupContainer",
              "RaidGroup1", "RaidGroupFrame1", "RaidGroupHeader1", "RaidFrame1" } },
  -- ★★★1.74.32【第 2 步：图标形态】被动打开层 —— 真名**全部来自探针实测**（不是猜的），
  --   形态：小图标（默认开）· 点图标 = 开该层属性弹窗 · 拖图标 = 拖窗口 · 图标挂在窗口下随窗口显隐。
  --   ★真机取证的两条关键事实：① 这族窗口尺寸统一 **384×512 / lv=1**（`CharacterFrame` 打开时是 lv=8）；
  --     ② 它们都是 `UIParent` 的顶层子帧（探针「顶层大帧兜底」清单里一目了然）。
  -- { name = "GuildFrame",   label = "公会",     icon = true, cands = { "GuildFrame" } },
  { name = "CharacterFrame", label = "属性",   icon = true, cands = { "CharacterFrame" } },
  { name = "MailFrame",    label = "邮箱",     icon = true, cands = { "MailFrame" } },
  { name = "QuestLogFrame", label = "任务",    icon = true, cands = { "QuestLogFrame" } },
  { name = "SpellBookFrame", label = "技能树", icon = true, cands = { "SpellBookFrame" } },
  { name = "TradeFrame",   label = "交易技能", icon = true, cands = { "TradeFrame" } },
  { name = "MerchantFrame", label = "商人",    icon = true, cands = { "MerchantFrame" } },
  { name = "FriendsFrame", label = "好友",     icon = true, cands = { "FriendsFrame" } },
  -- ↓ 「其它标准窗口」一族（用户选了 C：探针扫到的 384×512 那批，规格完全一样、成本几乎为零）
  { name = "BankFrame",        label = "银行",     icon = true, cands = { "BankFrame" } },
  { name = "QuestFrame",       label = "任务对话", icon = true, cands = { "QuestFrame" } },
  { name = "GossipFrame",      label = "NPC对话",  icon = true, cands = { "GossipFrame" } },
  { name = "ItemTextFrame",    label = "物品文字", icon = true, cands = { "ItemTextFrame" } },
  { name = "DressUpFrame",     label = "装备试穿", icon = true, cands = { "DressUpFrame" } },
  { name = "TaxiFrame",        label = "飞行路线", icon = true, cands = { "TaxiFrame" } },
  { name = "TabardFrame",      label = "公会徽章", icon = true, cands = { "TabardFrame" } },
  { name = "PetStableFrame",   label = "宠物栏",   icon = true, cands = { "PetStableFrame" } },
  { name = "PetitionFrame",    label = "签名",     icon = true, cands = { "PetitionFrame" } },
  { name = "BattlefieldFrame", label = "战场",     icon = true, cands = { "BattlefieldFrame" } },
  { name = "GuildRegistrarFrame", label = "公会注册", icon = true, cands = { "GuildRegistrarFrame" } },
  { name = "LFTFrame",         label = "寻找组队", icon = true, cands = { "LFTFrame" } },
  { name = "HelpFrame",        label = "帮助",     icon = true, cands = { "HelpFrame" } },
  { name = "ShopFrame",        label = "商店",     icon = true, cands = { "ShopFrame" } },
  -- ★★★1.74.33 补上「训练师」：真名来自探针实测（`TrainerFrame` **不存在**，真名是 `ClassTrainerFrame`）——
  --   它是被动窗口一族里的标准一档（同 384×512 规格），与上面「商店/帮助」同形，直接走图标形态。
  { name = "ClassTrainerFrame", label = "训练师", icon = true, cands = { "ClassTrainerFrame" } },
  -- ★★【待补】拍卖行：探针里候选逐个「不在」、`auction` 关键词命中 0、顶层大帧兜底清单里也没有 ——
  --   强烈指向它是**匿名窗口**（用户当时没开拍卖行，属惰加载）。等用户**开着拍卖行**再跑一次
  --   `/eh go 框体探针` + `/reload`，读存档 `dragBars.kids`（父子链 + 具名子件指纹）定名后再接入。
  --   ★**不先用 `AuctionFrame` 占位**：探针已经证明这个名字在本客户端**不存在**，
  --     写进去只会是一条永远「如实缺席」的记录，反而让面板难读。
}

-- ★柄池上限 = 目标数 + 2（**派生**，不写死：旧写法 8 的注释是「目标表最多也就 5 个」——
--   加了战斗记录 / 4 个动作条 / 队伍层 / 团队层之后目标到 12 个，写死值会在最坏情况下悄悄少贴几条柄）
-- ★★★1.74.33 用户**第二次澄清**（口径从「被动窗口」收窄到**所有窗口**）：
--   「图层拖拽功能.是所有窗口都不能调整宽高.会把内部原始撕裂.是我之前的需求说错了
--     属性配置需要支持调整的是窗口的 x,y 坐标值」
--   ⇒ 宽/高这两项**整体停用**（不分窗口类型：被动窗口 / 拖拽柄层 / 动作条都一样）：
--     ① 属性弹窗**不再创建**宽/高行（只留一行说明为什么）② `dfAttrsApply` 一律不写
--     ③ 老记录里的宽高在启动时**清理并还原原尺寸**。位置继续由**拖窗口**负责。
--   ★为什么不是「禁止同时设缩放+宽度」而是「干脆不给宽度」：宽度会**撕裂窗口内部布局**（截图里法术书左边技能列表与
--     右边那条各画各的），而缩放在真机上实测安全（属性窗口缩放 0.7 一直好用）⇒ 宁可少一个能力，也不要一个会把界面搞坏的能力。
--   ★★★1.75.1 用户**第三次**改口径（附截图）：「工具箱->图层拖拽->只有针对聊天窗才支持长宽设置.并且持久化」：
--     宽/高从「所有窗口都不给」收窄为「**只给聊天窗**」——
--     聊天窗（`ChatFrame1` 综合 / `ChatFrame2` 战斗记录，同一个聊天窗的两个分页）**可以**改宽高，
--     且**落存档持久化**（重登/应用存档都写回去）；其余窗口（头像/小地图/动作条/队伍・团队层/被动打开层）
--     **照旧一个宽高写调用都不发**（会撕裂窗口内部布局 —— 这条理由一个字都没变）。
--   ★★**唯一真值 = `dfSizeOK(name)`**：`dfAttrsApply` 的门、属性弹窗、启动清理三处都读**目标表项的 `noSize`**，
--     而 `noSize` 由它现算 ⇒ 全项目只有这一处知道「哪些名字算聊天窗」
--     （别处再判一次 = 两处真值迟早打架，这正是本项目反复栽过的坑）。
local DF_SIZE_PAT = "^ChatFrame%d+$"
local function dfSizeOK(name)
  if type(name) ~= "string" or name == "" then return false end
  return string.find(name, DF_SIZE_PAT) ~= nil
end
-- 每个目标挂 `noSize`（读值口与判据直接读它，不必去够模块内的 local）
for i = 1, table.getn(DF_TARGETS) do
  DF_TARGETS[i].noSize = not dfSizeOK(DF_TARGETS[i].name)
end
DF_POOL_MAX = table.getn(DF_TARGETS) + 2

-- ★★★1.74.32【第 1 步：只读取证】用户要求：「其他比如公会,属性,拍卖,邮箱,任务,技能树等被动打开层，
--   在其标题增加配置 UI 属性的图标开关，默认支持拖拽」。
--   ★确认过的四条设计（用户 1.74.32 明确）：① 点图标 = 直接开该层**属性弹窗**（复用现有 5 行）；
--     ② **拖图标本身 = 拖窗口**（图标默认开，面积小、不吃窗口点击 —— 这是它敢默认开的前提）；
--     ③ 目标是**窗口整体**（CharacterFrame / SpellBookFrame / QuestLogFrame 这一级，不拆页签）；
--     ④ 分两步走：**先只读取证拿真名，再实现图标**。
--   ★★所以本表**现在只喂探针**，**不接进 DF_TARGETS** —— 面板/拖拽柄/[重置]清单的行为一点没变
--     （一旦接进去，这些窗口立刻会被贴整条透明柄，那是第 2 步才该发生的事）。
--   ★第 2 步（拿到真名后）：把命中项搬进 DF_TARGETS，并给每个目标加 `icon = true` 走图标形态；
--     届时 `DF BARS WIRING CHECK` 里那条「DF_TARGETS 仍为 12 项」的哨兵要一起改掉（那里有注释提醒）。
local DF_WIN_CANDS = {
  -- ★候选顺序 = 「越像窗口整体越靠前」：先试正主，再试同一窗口的别名/容器
  { group = "guild",   label = "公会",   cands = { "GuildFrame", "GuildFrameContainer", "GuildRosterFrame" } },
  { group = "char",    label = "属性",   cands = { "CharacterFrame", "CharacterPanel", "PaperDollFrame", "PlayerCharacterFrame" } },
  { group = "auction", label = "拍卖",   cands = { "AuctionFrame", "AuctionHouseFrame", "AuctionFrameContainer" } },
  { group = "mail",    label = "邮箱",   cands = { "MailFrame", "InboxFrame", "MailFrameContainer" } },
  { group = "quest",   label = "任务",   cands = { "QuestLogFrame", "QuestFrame", "QuestLog", "QuestLogFrameContainer" } },
  { group = "spell",   label = "技能树", cands = { "SpellBookFrame", "SpellBook", "SkillFrame", "SpellBookFrameContainer" } },
  -- ★以下 4 类用户没点名（原话有「等」字）⇒ 一并取证，拿到真名后**由用户决定要不要进目标表**
  { group = "trainer",  label = "训练师", cands = { "TrainerFrame", "ClassTrainerFrame", "SkillTrainerFrame" } },
  { group = "trade",    label = "交易技能", cands = { "TradeSkillFrame", "CraftFrame", "TradeFrame" } },
  { group = "merchant", label = "商人",   cands = { "MerchantFrame", "MerchantFrameContainer", "MerchantWindow" } },
  { group = "friend",   label = "好友",   cands = { "FriendsFrame", "FriendsFrameContainer", "FriendFrame", "FriendsListFrame" } },
}

-- ============ 状态 ============
-- ★前向声明（Lua local 作用域从声明之后开始；这三处互相引用，必须先声明再用）
local dfDragEnd, dfCommitPop, dfRefresh
-- ★1.74.32 同款前向声明：`dfRosterEnsure` 里 OnEvent 闭包要调 `dfRosterArm`（它定义在后面）——
--   不先声明，闭包里那个名字会**绑成全局 nil**；而那种写法外面通常套 `type(...)=="function"` 守卫 ⇒
--   队伍/团队事件来了**静默什么都不做**（本轮最容易踩、且最难查的一处）。
local dfRosterArm
-- ★★★1.75.36i 同款前向声明（**harness 当场抓到的静默 bug**）：`EVAL_DF_SET`（定义在很前面）里调 `dfGuardArm`/
--   `dfGuardStop`，而它们的 `local function` 定义在后头 ⇒ 那两个名字在 `EVAL_DF_SET` 里绑的是**全局 nil**，
--   `pcall(nil, …)` 只是返回 false、**不报错** ⇒ 「打开开关立即武装 / 关掉立即停」从来没生效过（只有 INSTALL 那条路有效）。
--   ⇒ 必须先在这里声明，定义处改成**赋值**（`dfGuardArm = function(...)`），绝不能再写 `local function`。
--   ★`probe_localorder.js` 对这一类（引用点在**别的函数体内部**、声明在同文件的后面）是**盲区**，别指望它。
local dfGuardArm, dfGuardStop
-- ★★★1.75.36l 同款前向声明：「定位方块」（绝对基准，用户定稿）——`dfApplyAll`/`dfApplyOne` 定义在文件前部
--   而方块那一段在后部 ⇒ 不先声明就会绑成**全局 nil**（`pcall(nil,…)` 静默失败，1.75.36i 刚踩过一模一样的坑）。
local dfBlockApply, dfBlockSync, dfBlockDrift, dfBlockGet
local DF = {
  on = false,          -- 开关（真值 = EVAL_HELP_CONFIG.dragFrames.on）
  installed = false,   -- EVAL_DF_INSTALL 跑过没有
  dragging = false,    -- ★③ 任何拖拽进行中 → 定时复查整体跳过
  dragHandle = nil,    -- 正在被拖的柄
  dragWhy = nil,       -- 最近一次结束原因（诊断用）
  handles = {},        -- 柄池
  poolN = 0,           -- 当前贴了几个柄
  keepFrame = nil,     -- 启动期复查 tick 帧
  keepAcc = 0,         -- 周期累加
  keepSaid = false,
  -- ★★1.74.31 有界复查的状态（读值口 EVAL_DF_TEST_STATE 会逐项吐出来，断言直接读它，不复刻映射逻辑） ★1.75.34：该读值口已随 tests/ 一并删除（孤儿探针清理，见 CHANGELOG）。
  keepDone = true,     -- 是否已永久停止（初始 true = 还没武装过；武装时置 false）
  keepWhy = nil,       -- 结束原因："allok"（5 次全符合）/ "drift"（期间漂移已修正）/ "skipped"（评估上限）/ "wall"（墙钟上限）
  keepArmed = nil,     -- 这次窗口是被谁武装的："install" / "enable" / "testreset"（诊断用）
  keepRuns = 0,        -- 已完成的**净检查**次数（跳过的不算）
  keepTries = 0,       -- 已完成的**评估**次数（含跳过）
  keepSkips = 0,       -- 跳过的评估次数（战斗中 / 拖拽中）
  keepFixed = 0,       -- 有几次净检查**真的重设过**（漂移修正轮数）
  keepChecked = 0,     -- 最近一次净检查覆盖到的目标数（带定位记录且帧在位的）
  keepAge = 0,         -- 本次窗口已过去的墙钟秒数（绝对上限用它判）
  -- ★★★1.75.36f 属性设置守卫（0.3s 常驻；用户：「宠物栏位置…偶然性拾取物品之后会被还原位置.
  --   添加一个属性设置守卫,0.3频率重设.对所有有自定义属性设置的,对聊天框做特殊处理…不需要守卫」）
  guardFrame = nil,    -- 守卫 tick 帧
  guardOn = false,     -- 是否在跑（模块关掉 ⇒ 立刻摘脚本）
  guardAcc = 0,        -- 周期累加（0.3s 一拍）
  guardFixes = 0,      -- 累计「按存档重设」次数（读值口/断言读它）
  guardSkipped = 0,    -- 累计整拍跳过次数（拖拽中/战斗中）
  guardMoved = 0,      -- 累计重设的目标数（与 guardFixes 同源的另一个视角）
  -- ★★★1.75.36g 战斗中「写了但没生效」的处理（用户报障：「进入攻击状态,会把宠物动作栏顶到上面去」）
  guardBlocked = 0,    -- 战斗中对受保护帧写位置被拒的次数（>0 = 客户端在战斗中不放行这一写）
  guardNoWrite = {},   -- 目标名 → true（本场战斗里写过一次却没生效 ⇒ 不再 0.3s 一次地空写；出战斗清空重试）
  catcher = nil,       -- 全屏接盘（只在拖拽期间 Show）
  pop = nil,           -- 配置弹窗控件表
  popMode = nil,       -- 弹窗定位结果："host" / "uiparent" / "failed"
  popInfo = nil,       -- 弹窗定位数字（诊断/断言读它）
  forcePlaceFail = false, -- 测试钩子：强制第一次定位「校验不过」→ 走兜底
  mouseDownOK = nil,   -- IsMouseButtonDown 自校准结果：true=可用 / false=不可用 / nil=还没校准
  mouseDownSeen = nil, -- 校准时它到底返回了什么（诊断用，如实记录）
  focusOK = nil,       -- GetMouseFocus 自校准结果
  focusSeen = nil,
  tgtFocus = nil,      -- 弹窗下拉当前宿主行
  -- ★★1.74.32 队伍/团队帧「按需出现」的跟随（读值口 EVAL_DF_TEST_STATE 会逐项吐出来） ★1.75.34：该读值口已随 tests/ 一并删除（孤儿探针清理，见 CHANGELOG）。
  rosterFrame = nil,   -- 事件帧（EVAL_DF_ROSTER）
  rosterLeft = 0,      -- 本次跟随还剩几次结算（0 = 没在跟）
  rosterAcc = 0,       -- 距离下次结算累积了多少秒
  rosterWhy = nil,     -- 这次是被哪个事件叫起来的（诊断用）
  rosterDone = 0,      -- 累计「帧刚出现就按存档恢复」的次数
  rosterApplied = {},  -- 帧对象 → 已恢复过（★按**帧对象**记，不按目标名：帧被重建 ⇒ 重新恢复一次）
  -- ★★1.74.32 图标形态（被动打开层）的读值口用计数（断言直接读它，不复刻映射逻辑）
  iconN = 0,
}

-- ============ 小助手 ============
local function dfNum(v, d)
  if type(v) == "number" then return v end
  local n = tonumber(v)
  if n then return n end
  return d
end

local function dfLog(msg)
  if type(logLine) == "function" then
    local ok = pcall(logLine, "[DF] " .. tostring(msg))
    if ok then return end
  end
end

-- 宿主帧：**不能挂 UIParent**（开全屏地图会隐藏 UIParent → 柄跟着消失）；WorldFrame 恒在。
local function dfHost()
  local wf = rawget(_G, "WorldFrame")
  if type(wf) == "table" or type(wf) == "userdata" then return wf end
  return rawget(_G, "UIParent")
end

local function dfFrameOf(name)
  local f = rawget(_G, name)
  if type(f) == "table" or type(f) == "userdata" then return f end
  return nil
end

-- ★★★目标 → 帧对象（**唯一解析入口**）：有 `cands` 就按候选顺序找（命中即记下命中名，供 /edb bars 与面板显示）。
--   ★只缓存**命中**：帧可能惰加载，这一次没找到不代表永远没有（未命中每次重找，代价只是几次 _G 查表）。
--   ★必须定义在 dfFrameOf **之后**：Lua local 作用域从声明之后开始 —— 写在前面会绑成全局 nil，
--     而那种写法若外面套一个 `type(...)=="function"` 守卫，就会**静默**把候选解析整个废掉（本轮第一版差点这样）。
--   ★★去重：两个候选槽**可能撞到同一帧**（比如候选表都退到同一个变体名）⇒ 第一个认领者胜，后来者跳过；
--     否则同一个帧会拿到两条拖拽柄、两条存档记录互相打架（那是本项目最恨的静默冲突）。
local DF_CLAIM = {}
local function dfTargetFrame(t)
  if type(t) ~= "table" then return nil end
  if t.__hitFrame then return t.__hitFrame end
  local list = t.cands or { t.name }
  for i = 1, table.getn(list) do
    local f = dfFrameOf(list[i])
    if f and (DF_CLAIM[f] == nil or DF_CLAIM[f] == t) then
      DF_CLAIM[f] = t
      t.__hitFrame, t.__hitName = f, list[i]
      return f
    end
  end
  return nil
end

local function dfInCombat()
  if type(UnitAffectingCombat) ~= "function" then return false end
  local ok, v = pcall(UnitAffectingCombat, "player")
  return (ok and v) and true or false
end

local function dfSolid(t, r, g, b, a)
  if not t then return end
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8") end
  if type(t.SetVertexColor) == "function" then pcall(t.SetVertexColor, t, r, g, b, a) end
end

-- 自绘小按钮（与子插件里的 uiBtn 同形，但只属于本模块）
-- ★1.75.101：`name` 可选 —— 具名帧才进 `_G`（重置面板的按钮要能被判据/命令驱动）
local function dfBtn(parent, w, h, txt, name)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(w) b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  dfSolid(bg, 0.22, 0.17, 0.07, 1)
  b.bg = bg
  local fs = b:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontNormal) end
  if type(fs.SetPoint) == "function" then pcall(fs.SetPoint, fs, "CENTER", b, "CENTER", 0, 0) end
  if type(fs.SetTextColor) == "function" then pcall(fs.SetTextColor, fs, 1, 0.95, 0.7) end
  if type(fs.SetText) == "function" then pcall(fs.SetText, fs, txt or "") end
  b.label = fs
  return b
end

-- ============ 存档（唯一真值）============
-- 结构：EVAL_HELP_CONFIG.dragFrames = {
--   on = true/false,
--   mig = true,                           -- 老存档一次性迁移跑过没有
--   [帧名] = { base = { {锚点名, 相对帧名, 相对锚点名, x, y}, ... },  -- 原始锚点（★只存名字字符串，绝不存帧对象）
--              dx = n, dy = n,                                        -- 相对原始锚点的累计位移
--              scale = n, alpha = n, hidden = bool,
--              w = n, h = n,          -- ★1.74.31 用户设定过的宽/高（拖拽完成弹窗里选的）
--              ow = n, oh = n,        -- ★改动**之前**的原始宽/高（只用于重置还原；宽高没有「系统默认值」可退回）
--              legacy = true },
-- }
-- ★★「未就位就不写」纪律（子插件 1.74.29 那条教训）：EVAL_HELP_CONFIG 在文件执行期是空表、
--   SavedVariables 的恢复晚于文件执行 —— 所以文件期**只读不写**，写一律发生在登录之后。
-- ★★★1.75.109 **聊天窗两页 = 同一个窗口**（用户：「图层拖拽 聊天窗设置属性的时候也要将战斗记录做相同的参数设定.
--   这两个属于同个窗口同个位置」）⇒ 让两页**共用一份记录**（写 `ChatFrame2` == 写 `ChatFrame1`），
--   而**不是在十几处各写一遍「再镜像一次」的逻辑**（那种写法迟早漏一处 ⇒ 静默不同步）：
--     · 位置（`ax/ay`）/ 宽 / 高 / 缩放 / 透明度 / 显隐 **天然同步**；
--     · 守护（`dfGuardCandidates`/`dfApplyOne`）、载入应用（`dfApplyAll`）、[重置] 面板、清单、
--       方块拖动（记录里 `ax/ay` 是同一份 ⇒ 另一页的方块下一拍 `dfBlockSync` 自己跟）**一行都不用改**。
--   ★规范键 = **`ChatFrame1`**（老存档不用迁移 —— 它本来就是聊天框那份）；老存档里「只有战斗记录那份」
--     的情况由 `dfMirrorMerge` 一次性并入（**绝不丢用户数据**）。
--   ★唯一实现 `DF.storeKey(name)` + 存储代理 `DF.storeMT`；**别处不许再写第二份镜像逻辑**（结构钉守着）。
--   ★`rawget/rawset` 绕不过代理 ⇒ 迁移与「体检」那两处必须显式用 `raw*`（那是有意的）。
--   ★★★**全部挂 `DF` 表、绝不新增文件级 local**：本文件主 chunk **已到 200 个局部变量的上限**
--     （本轮加 5 个 local 当场打成 `too many local variables (limit is 200) in main function` —— 本项目在案）。
DF.mirror = { ChatFrame2 = "ChatFrame1" }        -- 镜像名 → 规范键
DF.mirrorOf = { ChatFrame1 = "ChatFrame2" }      -- 规范键 → 另一页（弹窗保存时显式应用那一边）
DF.storeKey = function(name)
  if type(name) ~= "string" then return name end
  local k = DF.mirror[name]
  if k then return k end
  return name
end
DF.storeMT = {
  __index = function(t, k) return rawget(t, DF.storeKey(k)) end,
  __newindex = function(t, k, v) rawset(t, DF.storeKey(k), v) end,
}

local function dfStore(create)
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return nil end
  local s = c.dragFrames
  if type(s) ~= "table" then
    if not create then return nil end
    s = {}
    c.dragFrames = s
  end
  return setmetatable(s, DF.storeMT)   -- ★镜像代理（见上面 DF.mirror 那段；幂等）
end

-- ============ 选中名单（1.74.33 用户要求）============
-- 用户原话：「工具箱->拖拽图层 右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，
--   选中的才开启配置和支持拖拽,等图层拖拽的能力」。
-- ★真值 = `EVAL_HELP_CONFIG.dragFrames.pick[name] = true`（键 = 目标名，与定位记录同一套键）。
-- ★★★**这张表不存在 = 全选**：老存档没有这一项时必须与改动前**行为完全一致**（升级后不是「全没选」——
--   那会让用户所有拖拽/图标突然消失，而且不报错）。
-- ★★`EVAL_DF_PICK_SET` 是**唯一写入口**，且第一次写要先把「全选」快照**物化**进表里再改这一项 ——
--   否则「取消勾选 A」会让 B~Z 因为表里没有键而全部变成未选中（一次点击静默关掉几十个拖拽，
--   正是本项目最恨的「静默失效」）。这条由断言组 214③与源码检查 `DF PICK WIRING CHECK` 双向守。
local function dfPickTbl(create)
  local store = dfStore(create)
  if not store then return nil end
  local p = store.pick
  if type(p) ~= "table" then
    if not create then return nil end
    p = {}
    store.pick = p
  end
  return p
end

-- 现在的选中真值（表不存在 = 全选）
local function dfPicked(name)
  local p = dfPickTbl(false)
  if type(p) ~= "table" then return true end
  return p[name] and true or false
end

-- 是否处于「从没设过 = 全选」状态（写入口靠它决定要不要先物化）
local function dfPickVirgin()
  return type(dfPickTbl(false)) ~= "table"
end

function EVAL_DF_PICK_ENABLED(name) return dfPicked(name) end

-- 对外如实报告「是不是还没设过（全选）」（工具箱 tooltip 与诊断用）
function EVAL_DF_PICK_ALL() return dfPickVirgin() end

function EVAL_DF_PICK_SET(name, on)
  if type(name) ~= "string" or name == "" then return false end
  local virgin = dfPickVirgin() -- ★必须在创建表**之前**问（创建之后就不是 virgin 了）
  local p = dfPickTbl(true)
  if type(p) ~= "table" then return false end
  if virgin then
    -- ★物化「全选」快照（见段首注释：少了这一步 = 一次点击静默关掉其它所有层）
    for i = 1, table.getn(DF_TARGETS) do p[DF_TARGETS[i].name] = true end
  end
  p[name] = on and true or nil
  return true
end

-- 已选 / 总数（按钮悬停、播报、断言都用它；单一实现，不在别处再数一遍）
function EVAL_DF_PICK_COUNT()
  local n, tot = 0, table.getn(DF_TARGETS)
  for i = 1, tot do if dfPicked(DF_TARGETS[i].name) then n = n + 1 end end
  return n, tot
end

-- 下拉内容（**唯一来源就是 DF_TARGETS**）：items 文本 / locked 分组标题行 / sel 初始勾选 / names 行→目标名。
-- ★工具箱只是这张菜单的**宿主**：它绝不自己复刻一份目标表（复刻必漂 —— 以后加一类目标要改两处、
--   漏一处就是「新目标在设置里看不到、也就永远选不上」这种静默缺席）。由 `DF PICK WIRING CHECK` 守。
-- ★分组标题行走 locked（`EVAL_DD_OPEN` 的既有语义：不画方框、点击无反应），names[i] 留空 ⇒ 回调里天然跳过。
function EVAL_DF_PICK_MENU()
  local items, locked, sel, names = {}, {}, {}, {}
  local cur = nil
  local function push(txt, isLocked, name, picked)
    local i = table.getn(items) + 1
    items[i] = txt
    locked[i] = isLocked and true or false
    names[i] = name
    if picked then sel[i] = true end
  end
  for i = 1, table.getn(DF_TARGETS) do
    local t = DF_TARGETS[i]
    local g = 1
    if t.icon then g = 3 elseif t.roster then g = 2 end
    if g ~= cur then
      cur = g
      if g == 1 then push(L("TB_LD_PICK_G1"), true)
      elseif g == 2 then push(L("TB_LD_PICK_G2"), true)
      else push(L("TB_LD_PICK_G3"), true) end
    end
    push(t.label, false, t.name, dfPicked(t.name))
  end
  return items, locked, sel, names
end

-- ============ 几何：实测边 + 锚点名 ============
-- point 名 → 该点在帧矩形里的相对系数（0=左/下、0.5=中、1=右/上）；不是 LEFT/RIGHT/BOTTOM/TOP 的一律当中
local function dfFactor(point, low, high)
  if type(point) ~= "string" then return 0.5 end
  if string.find(point, low, 1, true) then return 0 end
  if string.find(point, high, 1, true) then return 1 end
  return 0.5
end

-- 实测矩形（UI 像素、原点左下、Y 向上）：返回 l, b, w, h；读不到 → nil（**绝不用 GetPoint 的偏移顶替**）
local function dfMeasure(f)
  if not f then return nil end
  local okl, l = pcall(f.GetLeft, f)
  local okw, w = pcall(f.GetWidth, f)
  local okh, h = pcall(f.GetHeight, f)
  if not (okl and okw and okh and tonumber(l) and tonumber(w) and tonumber(h)) then return nil end
  local okb, b = pcall(f.GetBottom, f)
  if not (okb and tonumber(b)) then
    local okt, t = pcall(f.GetTop, f)
    if not (okt and tonumber(t)) then return nil end -- ★实测边拿不齐就**如实放弃**，不糊一个假值
    b = tonumber(t) - tonumber(h)
  end
  return tonumber(l), tonumber(b), tonumber(w), tonumber(h)
end

-- 相对帧**名字**归一：字符串原样（本客户端 GetPoint 就返回名字）；帧对象 → GetName；"auto"/空 → nil（= 父级）
local function dfRelName(rel)
  if type(rel) == "string" then
    if rel == "" or rel == "auto" then return nil end
    return rel
  end
  if rel and type(rel.GetName) == "function" then
    local ok, n = pcall(rel.GetName, rel)
    if ok and type(n) == "string" and n ~= "" then return n end
  end
  return nil
end

-- 相对帧对象：名字 → _G 取帧；名字取不到或没名字 → 目标的**父级**（nil 相对帧的语义就是父级）
local function dfRelFrame(relName, fr)
  if type(relName) == "string" and relName ~= "" then
    local f = dfFrameOf(relName)
    if f then return f end
  end
  if fr and type(fr.GetParent) == "function" then
    local ok, p = pcall(fr.GetParent, fr)
    if ok and (type(p) == "table" or type(p) == "userdata") then return p end
  end
  return rawget(_G, "UIParent")
end

-- 相对帧的「相对锚点」在屏幕坐标里的位置（量不到就按 0/0 兜底 —— 至少不编造一个方向）
local function dfRelAnchorPos(relName, relPoint, fr)
  local R = dfRelFrame(relName, fr)
  local l, b, w, h = dfMeasure(R)
  if not l then return 0, 0 end
  return l + w * dfFactor(relPoint, "LEFT", "RIGHT"), b + h * dfFactor(relPoint, "BOTTOM", "TOP")
end

-- ★★★1.75.36k 相对锚点目标的「基准屏幕位置」**每次现算**（用**当前**的相对帧位置 + 存档里的锚点偏移）：
--   为什么必须现算：`base.l/base.b` 是抓取那一刻的屏幕位置 —— 父帧一动（客户端重排底部条组）它就**过期**，
--   于是「按存档回位」会把这一层拽回**旧世界**（真机报障：动作栏1~4 设好的位置保存后又回去 / 按键整排上浮）。
--   现算出来的基准 = 「客户端**现在**这个版式下、这一层按存档锚点该在的地方」⇒ 我们的位移 `dx/dy`（**屏幕单位**）
--   叠在它上面才是用户真正想要的位置；父帧挪动时基准跟着挪 ⇒ **不算漂、不打架**。
--   ★返回 nil = 量不到相对帧 ⇒ 调用方**退回旧口径**（如实降级，绝不编一个值）。
local function dfBaseLive(fr, cap)
  if type(cap) ~= "table" or type(cap[1]) ~= "table" then return nil end
  local a = cap[1]
  if type(a[1]) ~= "string" or type(a[4]) ~= "number" or type(a[5]) ~= "number" then return nil end
  local _, _, w, h = dfMeasure(fr)
  if type(w) ~= "number" or type(h) ~= "number" then return nil end
  local rm = (type(a[2]) == "string" and a[2] ~= "") and a[2] or nil
  local rp = (type(a[3]) == "string" and a[3] ~= "") and a[3] or a[1]
  local R = dfRelFrame(rm, fr)
  local rl, rb, rw, rh = dfMeasure(R)
  if type(rl) ~= "number" or type(rb) ~= "number" then return nil end
  local qx = rl + rw * dfFactor(rp, "LEFT", "RIGHT")
  local qy = rb + rh * dfFactor(rp, "BOTTOM", "TOP")
  return dfNum(a[4], 0) + qx - w * dfFactor(a[1], "LEFT", "RIGHT"),
    dfNum(a[5], 0) + qy - h * dfFactor(a[1], "BOTTOM", "TOP")
end

-- 抓一份「实测锚点」（可序列化：全是字符串与数字）
-- 返回 { {point, relName, relPoint, x, y}, ... }；量不到几何 → nil（调用方如实放弃，不写半个记录）
local function dfCapture(fr)
  if not fr or type(fr.GetPoint) ~= "function" then return nil end
  local n = 1
  if type(fr.GetNumPoints) == "function" then
    local okn, v = pcall(fr.GetNumPoints, fr)
    if okn and tonumber(v) and tonumber(v) >= 1 then n = math.floor(tonumber(v)) end
  end
  if n > 4 then n = 4 end -- 防御：最多记 4 个锚点
  local l, b, w, h = dfMeasure(fr)
  if not l then return nil end
  local out = {}
  -- ★★★1.74.33 除了锚点四元组，还记**实测屏幕位置**（`out.l`/`out.b`，命名键，不进数组部分）：
  --   `GetLeft/GetBottom` 是**屏幕**坐标，而 `GetWidth/GetHeight` 是**帧本地**尺寸（含缩放）——
  --   把两者混起来算偏移，在「缩放 ≠ 1」的窗口上每次捕获/落锚都会甩掉一个固定量
  --   （用户报的「有些窗口拖拽位移叠加漂移」就是它，详见 dfPlaceFrom 的说明）。
  --   记下实测屏幕位置后，位移一律**按屏幕算、落锚后量回自证**，不再依赖「偏移量到底是什么单位」这个没有可信文档的问题。
  out.l, out.b = l, b
  for i = 1, n do
    local okp, p, rel, relp = pcall(fr.GetPoint, fr, i)
    if not (okp and type(p) == "string") then break end
    local relName = dfRelName(rel)
    local rp = (type(relp) == "string" and relp ~= "") and relp or p
    local qx, qy = dfRelAnchorPos(relName, rp, fr)
    local x = l + w * dfFactor(p, "LEFT", "RIGHT") - qx
    local y = b + h * dfFactor(p, "BOTTOM", "TOP") - qy
    table.insert(out, { p, relName, rp, x, y })
  end
  if table.getn(out) == 0 then return nil end
  return out
end

-- 按「实测锚点 + 位移」重新锚定：**逐锚点平移同一个位移**（多锚点帧也能整体刚性平移）
-- ★ClearAllPoints 之后位置是 (0,0)（= 父级左下角）——所以每一步都必须真的落上 SetPoint，并且把成功与否如实返回。
-- ★★★1.75.36j **相对锚点**判定 + 按锚点判「到位」（真机取证驱动，见 dfGuardTick 的说明）：
--   记录里的 `base[1]` = 抓取那一刻的「锚点名/相对帧/相对锚点/偏移」四元组。
--   · 相对帧是 **UIParent**（或没有相对帧）⇒ 屏幕坐标就是稳定真值 ⇒ 走**绝对**口径（原逻辑，不变）；
--   · 相对帧是**别的帧**（`PetActionBarFrame ← MainMenuBar`、`MultiBarBottomLeft ← ActionButton1` …）
--     ⇒ 屏幕坐标是**旧世界的**：父帧一动（客户端重排底部条组）它就整体漂 ⇒ 必须按**相对**口径判与治，
--       否则「按绝对坐标回位」会把这一层**从父帧上拽下来**，而客户端下一拍又把它锚回去 ⇒ 两边来回拉 = 每 0.3s 抖。
local function dfRelCap(cap)
  if type(cap) ~= "table" or type(cap[1]) ~= "table" then return false end
  local a = cap[1]
  if type(a[1]) ~= "string" or type(a[2]) ~= "string" or a[2] == "" then return false end
  if a[2] == "UIParent" then return false end
  return true
end

-- 当前锚点是否 = 存档锚点 + (dx,dy)（点名声/相对帧/相对锚点**逐项相等**，偏移容差 1px；锚点数不等就保守判「不到」）
local function dfAnchorAt(fr, cap, dx, dy)
  if type(cap) ~= "table" or type(cap[1]) ~= "table" then return false end
  local cur = dfCapture(fr)
  if type(cur) ~= "table" or type(cur[1]) ~= "table" then return false end
  local n = table.getn(cap)
  if table.getn(cur) ~= n then return false end
  for i = 1, n do
    local c, b = cur[i], cap[i]
    if type(c) ~= "table" or type(b) ~= "table" then return false end
    if c[1] ~= b[1] then return false end
    if (c[2] or "") ~= (b[2] or "") then return false end
    if (c[3] or "") ~= (b[3] or "") then return false end
    if math.abs(dfNum(c[4], 0) - (dfNum(b[4], 0) + dfNum(dx, 0))) > 1 then return false end
    if math.abs(dfNum(c[5], 0) - (dfNum(b[5], 0) + dfNum(dy, 0))) > 1 then return false end
  end
  return true
end

local function dfAnchorApply(fr, cap, dx, dy)
  if not fr or type(cap) ~= "table" then return false, 0 end
  if type(fr.ClearAllPoints) ~= "function" or type(fr.SetPoint) ~= "function" then return false, 0 end
  if not pcall(fr.ClearAllPoints, fr) then return false, 0 end
  local oks, n = 0, 0
  for i = 1, table.getn(cap) do
    local a = cap[i]
    if type(a) == "table" and type(a[1]) == "string" then
      n = n + 1
      local relName = (type(a[2]) == "string" and a[2] ~= "") and a[2] or nil
      local relp = (type(a[3]) == "string" and a[3] ~= "") and a[3] or a[1]
      local x = (dfNum(a[4], 0)) + (dfNum(dx, 0))
      local y = (dfNum(a[5], 0)) + (dfNum(dy, 0))
      local rel = nil
      if relName then rel = dfFrameOf(relName) end -- 名字能取到帧就传帧（更稳）；取不到 → nil = 父级
      local ok = pcall(fr.SetPoint, fr, a[1], rel, relp, x, y)
      if ok then oks = oks + 1 end
    end
  end
  return (oks > 0), oks
end

-- 帧的**有效缩放**：本客户端的 SetPoint 偏移量按**帧本地单位**解释，屏幕位移 = 偏移 × 有效缩放
--   ⇒ 这是「偏移增量」的首猜来源（`GetEffectiveScale` 是有文档的 API，位置记忆那套也在用它）。
--   ★它只是**首猜**：dfPlaceFrom 会把落点**量回自证**，猜错就用手量出来的折算覆盖（见下）。
local function dfEffScale(fr)
  if fr and type(fr.GetEffectiveScale) == "function" then
    local ok, v = pcall(fr.GetEffectiveScale, fr)
    if ok and tonumber(v) and tonumber(v) > 0.05 and tonumber(v) <= 20 then return tonumber(v) end
  end
  return 1
end

-- ★★★1.74.33 位移的唯一落点：**「把帧放到『基准的实测屏幕位置 + (dx, dy)』」**（dx/dy = **屏幕**单位）
-- ── 为什么必须这么写（用户报「窗口拖拽有些会有位移叠加漂移，比如角色」）：
--   ① `dfCapture` 算偏移时用的是 `GetLeft + GetWidth × 系数`：`GetLeft` 是**屏幕**坐标、
--      `GetWidth` 是**帧本地**尺寸；两者只在「缩放 = 1」时才同口径 ⇒ 缩放 ≠ 1 的窗口每次
--      捕获→落锚都会甩掉约 `w × 系数 × (1 − s)` ⇒ **每拖一次叠加一次**（越拖越偏）。
--   ② 更根本的一层：`dfCapture` 那个「偏移量」是**从几何反算出来的**（不是 `GetPoint` 原值），
--      它和「SetPoint 要的偏移」差一个**常数**（单位口径 + 锚点系数叠加），与本次拖多远**无关**
--      ⇒ 用「位移 / 实测系数」反解是解不掉的（前一版就栽在这里：单次对、连续三次仍叠加）。
--   ③ 正确解法 = **解一条仿射关系**：屏幕位置 = 常数 + 折算 × 偏移（`SetPoint` 是线性的）。
--      先用有效缩放首猜一次 → 量回 → 差值就是那个**常数**（与位移无关，一次消掉）
--      → 若还没到位，用**两次落点**手量真实折算，再修一次（收敛；量出来的，不依赖任何单位约定）。
--   ④ 老记录（存档里没有实测屏幕位置 `cap.l`）→ **退回旧的纯锚点平移**，行为与以前一致（不假装能修）。
--   返回 ok, kk（kk = 本次**折算**：1 表示偏移即屏幕单位；≈缩放值表示按帧本地单位折算）。
-- ★★★1.74.33 「拖完下次打开位置不对」的根因之一：**老记录没有实测屏幕基准**（用户真机存档里那 4 条记录 base.l/base.b 全是 nil）。
--   老记录只能走「反算偏移 + 位移」的老路 —— 而那个偏移是**屏幕量**、`SetPoint` 要的是**帧本地量**，
--   缩放 ≠ 1 的窗口必然偏（用户那些 384×512 窗口大多设过 0.5~0.8 缩放）。
--   这里把基准**反推**出来，之后走同一套「量回自证」落锚（不是猜，推导见下）：
--     dfCapture 的反算口径 = 反算值 = 屏幕位置 + w × 系数 − 相对锚点位置（w 是**含缩放**的实测尺寸，见 R15 ⑥d）
--     ⇒ 屏幕位置 = 反算值 − w × 系数 + 相对锚点位置。★只用 w/h（尺寸），**不依赖帧当时的位置读数**
--     ⇒ 隐藏时照样算得准（第一轮取证里「隐藏帧读数不可信」说的正是**位置**，不是尺寸）。
local function dfScreenBaseOf(fr, cap)
  if type(cap) ~= "table" or type(cap[1]) ~= "table" then return nil, nil end
  local a = cap[1]
  if type(a[4]) ~= "number" or type(a[5]) ~= "number" or type(a[1]) ~= "string" then return nil, nil end
  local w, h = nil, nil
  if type(fr.GetWidth) == "function" then
    local ok, v = pcall(fr.GetWidth, fr)
    if ok and tonumber(v) then w = tonumber(v) end
  end
  if type(fr.GetHeight) == "function" then
    local ok, v = pcall(fr.GetHeight, fr)
    if ok and tonumber(v) then h = tonumber(v) end
  end
  if w == nil or h == nil then return nil, nil end
  local relName = (type(a[2]) == "string" and a[2] ~= "") and a[2] or nil
  local rp = (type(a[3]) == "string" and a[3] ~= "") and a[3] or a[1]
  local qx, qy = dfRelAnchorPos(relName, rp, fr)
  if type(qx) ~= "number" or type(qy) ~= "number" then return nil, nil end
  local bl = a[4] - w * dfFactor(a[1], "LEFT", "RIGHT") + qx
  local bb = a[5] - h * dfFactor(a[1], "BOTTOM", "TOP") + qy
  return bl, bb
end

local function dfPlaceFrom(fr, cap, dx, dy)
  if type(cap) ~= "table" then return false, nil end
  -- ★★★1.75.36k 相对锚点目标（相对帧不是 UIParent）：基准**现算**（`dfBaseLive`），随后**仍走下面同一套**
  --   「首猜折算 → 量回自证 → 手量折算修正」。
  --   ★★为什么不能把 `dx/dy` 直接塞进 `SetPoint`（1.75.36j 的错误写法，真机当场出事）：
  --     `dx/dy` 是**屏幕单位**的位移，而 `SetPoint` 的偏移是**帧本地单位** —— 两者差一个有效缩放
  --     （0.7 缩放的条：屏幕 50px 需要本地 ~71）⇒ 直接塞进去每一条都只走了 `scale × 位移`，
  --     而动作栏1~4 是**互相锚着的链**（2←1、4←3）⇒ 误差层层叠加 ⇒ 用户 `/reload` 后「位置全错乱」。
  --   ⇒ 屏幕位移一律交给收敛环去解，锚点身份保持相对（这一层依旧贴着父帧，不会被拽到旧世界）。
  local bl, bb = cap.l, cap.b
  if dfRelCap(cap) then
    local lbl, lbb = dfBaseLive(fr, cap)
    if type(lbl) == "number" and type(lbb) == "number" then bl, bb = lbl, lbb end
  end
  if type(bl) ~= "number" or type(bb) ~= "number" then
    -- ★老记录：先试着**反推**出屏幕基准；反推不出来才老实退回老路径（如实降级，不假装能修）
    bl, bb = dfScreenBaseOf(fr, cap)
  end
  if type(bl) ~= "number" or type(bb) ~= "number" then
    return dfAnchorApply(fr, cap, dx, dy), nil -- 实在反推不出：老路径
  end
  local wx, wy = dfNum(dx, 0), dfNum(dy, 0)
  local wantL, wantB = bl + wx, bb + wy
  -- 已经到位就不动（避免每帧 ClearAllPoints+SetPoint 闪烁）
  local l0, b0 = dfMeasure(fr)
  if l0 and b0 and math.abs(l0 - wantL) <= 1 and math.abs(b0 - wantB) <= 1 then
    return true, (DF.lastK or dfEffScale(fr))
  end
  -- 首猜：偏移增量 = 屏幕位移 ÷ 折算（缩放 1 的窗口这一步就到位；缩放 ≠ 1 的窗口下一步量回修正）
  local k = dfEffScale(fr)
  local ox, oy = wx / k, wy / k
  if not dfAnchorApply(fr, cap, ox, oy) then return false, nil end
  local l1, b1 = dfMeasure(fr)
  if not l1 or not b1 then return true, k end
  -- 量回自证 + 修正（最多 3 轮；真机上「首猜错」的情形第 2 轮就到位）
  for _ = 1, 3 do
    local ex, ey = wantL - l1, wantB - b1
    if math.abs(ex) <= 1 and math.abs(ey) <= 1 then return true, k end
    local stepX, stepY = ex / k, ey / k
    ox, oy = ox + stepX, oy + stepY
    if not dfAnchorApply(fr, cap, ox, oy) then return true, k end
    local l2, b2 = dfMeasure(fr)
    if not l2 or not b2 then return true, k end
    -- ★真实折算 = 本次屏幕位移 ÷ 本次偏移增量（手量，覆盖首猜；只在这个轴真的动了 ≥1px 时才量）
    if math.abs(stepX) >= 1 then
      local km = (l2 - l1) / stepX
      if km > 0.05 and km <= 20 then k = km end
    elseif math.abs(stepY) >= 1 then
      local km = (b2 - b1) / stepY
      if km > 0.05 and km <= 20 then k = km end
    end
    l1, b1 = l2, b2
  end
  return true, k
end

-- 当前锚点是否已经在「屏幕位置 = 基准屏幕位置 + 位移」上（容差 1px）
--   ★判据也改**按屏幕量**（同样不受单位约定影响）；老记录没有实测屏幕位置时退回旧的锚点比对。
local function dfIsAt(fr, base, dx, dy)
  if type(base) ~= "table" or type(base[1]) ~= "table" then return false end
  -- ★★★1.75.36k 判据统一走**屏幕**：相对锚点目标先把「基准屏幕位置」**现算**出来（父帧挪了基准跟着挪），
  --   再比「实测屏幕位置 = 基准 + dx/dy」。★位移 `dx/dy` 是**屏幕单位**（拖拽/属性窗都是这么写的），
  --   所以只能比屏幕；量不到相对帧才退回锚点比对（如实降级）。
  local bl, bb = nil, nil
  if dfRelCap(base) then
    bl, bb = dfBaseLive(fr, base)
    if type(bl) ~= "number" or type(bb) ~= "number" then return dfAnchorAt(fr, base, dx, dy) end
  elseif type(base.l) == "number" and type(base.b) == "number" then
    bl, bb = base.l, base.b
  end
  if type(bl) == "number" and type(bb) == "number" then
    local l, b = dfMeasure(fr)
    if not l or not b then return false end
    return (math.abs(l - (bl + dfNum(dx, 0))) <= 1) and (math.abs(b - (bb + dfNum(dy, 0))) <= 1)
  end
  local cur = dfCapture(fr)
  if not cur or type(cur[1]) ~= "table" then return false end
  local c0, b0 = cur[1], base[1]
  if c0[1] ~= b0[1] then return false end
  if (c0[2] or "") ~= (b0[2] or "") then return false end
  if (c0[3] or "") ~= (b0[3] or "") then return false end
  local wantX = dfNum(b0[4], 0) + dfNum(dx, 0)
  local wantY = dfNum(b0[5], 0) + dfNum(dy, 0)
  if math.abs(dfNum(c0[4], 0) - wantX) > 1 then return false end
  if math.abs(dfNum(c0[5], 0) - wantY) > 1 then return false end
  return true
end

-- 属性（缩放/透明/显隐/宽/高）——只在「登录恢复 / 拖拽结束保存 / 显式应用 / 开窗重设」时写，不做周期性写入
--   ★`tgt` = 目标表项（可选）：被动窗口（`noSize = true`）**绝不写宽/高** —— 用户明确「宽度会破坏内部布局」。
local function dfAttrsApply(fr, rec, quiet, tgt)
  if not fr or type(rec) ~= "table" then return 0 end
  -- ★★★1.75.1：宽/高**只对聊天窗**开放（真值 = 目标表项的 `noSize`，由 `dfSizeOK` 现算）。
  --   ★没给 `tgt` 时**按不允许处理**（保守）：判不出来就不写 —— 宁可少一个能力，
  --     也不要「不知道是什么窗口就去改它尺寸」。
  local allowSize = (type(tgt) == "table") and (tgt.noSize ~= true)
  local n = 0
  if type(rec.scale) == "number" and type(fr.SetScale) == "function" then
    pcall(fr.SetScale, fr, rec.scale) n = n + 1
  end
  if type(rec.alpha) == "number" and type(fr.SetAlpha) == "function" then
    pcall(fr.SetAlpha, fr, rec.alpha) n = n + 1
  end
  -- ★1.74.31 宽/高也要跟着「每次启动自动生效」（与缩放/透明度同一口径：有记录就写回去）
  if allowSize and type(rec.w) == "number" and type(fr.SetWidth) == "function" then
    pcall(fr.SetWidth, fr, rec.w) n = n + 1
  end
  if allowSize and type(rec.h) == "number" and type(fr.SetHeight) == "function" then
    pcall(fr.SetHeight, fr, rec.h) n = n + 1
  end
  if rec.hidden == true and type(fr.Hide) == "function" then
    pcall(fr.Hide, fr) n = n + 1
  elseif rec.hidden == false and type(fr.Show) == "function" then
    pcall(fr.Show, fr) n = n + 1
  end
  if not quiet then dfLog("属性已应用 " .. tostring(n) .. " 项") end
  return n
end

-- ============ 属性读值 / 还原（清单与重置共用）============
-- 读目标**当前**的属性：真机可用的 API `GetScale` / `GetAlpha` / `IsShown` / `GetWidth` / `GetHeight`，一律 pcall。
-- ★读的是**目标本身**，不是存档记录：「记录里写了 0.6」≠「它现在就是 0.6」，用户要看的是后者。
-- ★拿不到就返回 nil（调用方如实写「?」）——**绝不编一个 1** 冒充足「默认值」（本项目「查不到 ≠ 没有」纪律）。
-- ★1.75.36m `noSize = true` = **只读前三样**（缩放/透明/显隐）：守护每拍都要读属性，而它**永远不比宽高**
--   （候选必然 `noSize == true`，见 `dfGuardCustom` 头注）⇒ 省掉每拍每目标 2 次 `GetWidth`/`GetHeight`。
--   默认（nil）行为一字不变 —— 属性清单 / 还原那条路照旧读宽高。
local function dfReadAttrs(fr, noSize)
  if not fr then return nil, nil, nil, nil, nil end
  local sc, al, sh, w, h = nil, nil, nil, nil, nil
  if type(fr.GetScale) == "function" then
    local ok, v = pcall(fr.GetScale, fr)
    if ok and tonumber(v) then sc = tonumber(v) end
  end
  if type(fr.GetAlpha) == "function" then
    local ok, v = pcall(fr.GetAlpha, fr)
    if ok and tonumber(v) then al = tonumber(v) end
  end
  if type(fr.IsShown) == "function" then
    local ok, v = pcall(fr.IsShown, fr)
    -- ★本客户端存在「返回 1 而不是 true」的 API（IsEventRegistered 就是那个先例）⇒ 两种都认；
    --   其余取值（含 nil）一律当**读不到**，如实在清单里写「?」，不猜。
    if ok then
      if v == true or v == 1 then sh = true
      elseif v == false or v == 0 then sh = false end
    end
  end
  if noSize then return sc, al, sh, nil, nil end -- ★守护路径：宽高**连读都不读**（省 2 次调用/目标/拍）
  -- ★1.74.31 宽/高（用户要求清单里也要显示）：与缩放/透明度同口径 —— 现读目标、读不到写「?」
  if type(fr.GetWidth) == "function" then
    local ok, v = pcall(fr.GetWidth, fr)
    if ok and tonumber(v) then w = tonumber(v) end
  end
  if type(fr.GetHeight) == "function" then
    local ok, v = pcall(fr.GetHeight, fr)
    if ok and tonumber(v) then h = tonumber(v) end
  end
  return sc, al, sh, w, h
end

-- 还原一个目标的属性（缩放=1 / 透明度=1 / 显示）并**清掉对应记录字段**。
-- 返回：done = 人读的「还原了哪几项」数组（用于播报）+ res = {scale, alpha, show, skipped} 数字。
-- ★战斗保护（沿用本模块既有口径：战斗中不碰受保护帧的属性）：**一律不调** SetScale/SetAlpha/Show/Hide/SetWidth/SetHeight；
--   此时**字段原样保留**——绝不能「没还原却把记录清了」，那会让用户永远回不到默认值。
-- ★★★1.74.31 宽/高：与缩放/透明度不同，**没有「系统默认值」可回退** ⇒ 必须还原到「第一次改之前记下的原始宽高」
--   （rec.ow/rec.oh，由保存那一侧在**改动前**抓）；原始值缺失（老迁移记录）→ **如实计入 whMiss、字段保留**，
--   绝不拿当前值当「原始值」糊过去（那样等于什么都没还原，却报告成功）。
local function dfRestoreAttrs(fr, rec, combat)
  local done = {}
  local res = { scale = 0, alpha = 0, show = 0, w = 0, h = 0, whMiss = 0, skipped = 0 }
  local pend = (rec.scale ~= nil) or (rec.alpha ~= nil) or (rec.hidden ~= nil)
    or (rec.w ~= nil) or (rec.h ~= nil)
  if not pend then return done, res end
  if combat or not fr then
    res.skipped = 1
    return done, res
  end
  if rec.scale ~= nil then
    local ok = (type(fr.SetScale) == "function") and pcall(fr.SetScale, fr, 1)
    if ok then
      rec.scale = nil
      res.scale = 1
      table.insert(done, L("TB_LD_SUM_SCALE"))
    else
      res.skipped = res.skipped + 1
    end
  end
  if rec.alpha ~= nil then
    local ok = (type(fr.SetAlpha) == "function") and pcall(fr.SetAlpha, fr, 1)
    if ok then
      rec.alpha = nil
      res.alpha = 1
      table.insert(done, L("TB_LD_SUM_ALPHA"))
    else
      res.skipped = res.skipped + 1
    end
  end
  -- ★宽 / 高：还原到「改动前的原始值」
  local function restoreWH(key, okey, setter, label)
    if rec[key] == nil then
      rec[okey] = nil -- 没改过宽/高 → 顺手清掉可能残留的原始值（免得记录因此不整条删除）
      return
    end
    local orig = tonumber(rec[okey])
    if not orig then
      res.whMiss = res.whMiss + 1 -- 没有原始值 ⇒ 不还原、不清字段（如实计入，由播报说明）
      return
    end
    local ok = (type(fr[setter]) == "function") and pcall(fr[setter], fr, orig)
    if ok then
      rec[key] = nil
      rec[okey] = nil
      res[key] = 1
      table.insert(done, label)
    else
      res.skipped = res.skipped + 1
    end
  end
  restoreWH("w", "ow", "SetWidth", L("TB_LD_SUM_W"))
  restoreWH("h", "oh", "SetHeight", L("TB_LD_SUM_H"))
  if rec.hidden ~= nil then
    local ok = (type(fr.Show) == "function") and pcall(fr.Show, fr)
    if ok then
      rec.hidden = nil
      res.show = 1
      table.insert(done, L("TB_LD_SUM_SHOWN"))
    else
      res.skipped = res.skipped + 1
    end
  end
  return done, res
end

-- ============ **启动期有界**复查（按存档回位）============
-- ★★★1.74.31 起**不再是「每 2 秒常驻」**（本行标题与函数内措辞曾长期停留在旧口径，2026-09-28 一并改正）：
--   现口径 = 登录/载入后**武装一次**：周期 `DF_KEEP_PERIOD`=1.0s × **净检查 `DF_KEEP_CHECKS`=5 次**，
--   含跳过在内的评估上限 `DF_KEEP_TRIES`=12 次，**绝对墙钟 `DF_KEEP_WALL`=15.0s** ⇒ 到点 `dfKeepStop` **摘掉 OnUpdate**、
--   之后**永久不再复查**（用户定：「最大检测时间为屏幕载入完成 5s 内」；旧常驻 tick 会在拖拽/切图时反复抢锚点）。
--   属性侧同理：**不做周期性写入**（只在 登录恢复 / 拖拽结束保存 / 显式应用 / 开窗重设 四个时刻写）。
-- ★③ 拖拽进行中**整体跳过**（这是本轮用户报的「拖拽中与定时复查抢锚点」的直接修法）
local function dfKeepTick(quiet)
  if DF.dragging then
    if not quiet then say("框拖拽：拖拽进行中，本次启动期复查跳过（不与手动拖拽抢锚点）") end
    return 0, 0
  end
  if dfInCombat() then return 0, 0 end -- ★战斗中不重锚（客户端保护）
  -- ★★★1.74.30：「显示集合签名」变化 → 重贴拖拽条。
  --   综合/战斗记录切页时只有一页在显示，签名不一致就说明“该出现的条”变了（启动期 1s 一拍，最多 5 拍内跟上）。
  local sig = {}
  for i2 = 1, table.getn(DF_TARGETS) do
    local fr2 = dfTargetFrame(DF_TARGETS[i2])
    local sh2 = 0
    if fr2 and type(fr2.IsShown) == "function" then
      local oks2, v2 = pcall(fr2.IsShown, fr2)
      if oks2 and v2 then sh2 = 1 end
    end
    table.insert(sig, tostring(sh2))
  end
  local sigStr = table.concat(sig, "")
  if DF.shownSig ~= nil and DF.shownSig ~= sigStr then
    DF.shownSig = sigStr
    if type(dfRefresh) == "function" then pcall(dfRefresh) end
  else
    DF.shownSig = sigStr
  end
  local store = dfStore(false)
  if not store then return 0, 0 end
  local fixed, checked = 0, 0
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    local rec = store[tgt.name]
    -- ★1.74.33 未勾选的层**不在管理范围**：不重锚（它现在连拖拽柄/图标都没有，重锚等于偷偷改用户没选的层）
    local fr = dfPicked(tgt.name) and dfTargetFrame(tgt) or nil
    -- ★★★1.75.36l 方块目标：判据与落点都走方块（目标被**接管锚点**到方块上 ⇒ 位置 = 方块的绝对坐标）
    if tgt.block == true then
      -- ★★1.75.52：**必须带 `axAuto` 门**（与 `dfApplyAll`/`dfApplyOne` 同口径）——
      --   迁移基准（客户端版式本身）的层**不算漂移**，拉回方块才是破坏版式；
      --   用户报障「重置之后底部动作栏位置自动偏移」就是这里漏了门：重置已把目标从方块上摘下来，
      --   这一支见「没锚在方块上」立刻 `dfBlockApply` 又把它锚回去 ⇒ 位置就飘了。
      if type(rec) == "table" and fr and rec.axAuto ~= true and dfBlockDrift(tgt) then
        checked = checked + 1
        if dfBlockApply(tgt) then fixed = fixed + 1 end
      end
    elseif type(rec) == "table" and type(rec.base) == "table" and fr then
      if rec.dx or rec.dy then
        checked = checked + 1
        local bcap = rec.cur or rec.base -- ★应用用当前基准
        if not dfIsAt(fr, bcap, rec.dx, rec.dy) then
          local ok = dfPlaceFrom(fr, bcap, rec.dx, rec.dy)
          if ok then fixed = fixed + 1 end
        end
      end
    end
  end
  if not quiet and checked > 0 then
    say("框拖拽定时复查：检查 " .. tostring(checked) .. " 个目标，重设 " .. tostring(fixed) .. " 个（漂了就按存档回位）")
  end
  return fixed, checked
end

-- 全量应用（登录恢复 / 显式应用）：位置 + 属性，逐目标如实计数
local function dfApplyAll(quiet)
  local store = dfStore(false)
  local fixed, attrs, checked = 0, 0, 0
  if not store then return 0, 0, 0 end
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    local rec = store[tgt.name]
    -- ★1.74.33 未勾选的层不应用存档参数（「选中的才开启配置」就是这条：不勾 = 存档里那套缩放/位置不动它）
    local fr = dfPicked(tgt.name) and dfTargetFrame(tgt) or nil
    if type(rec) == "table" and fr then
      checked = checked + 1
      if tgt.block == true then
        -- ★1.75.36l 方块目标：一次写全「方块位置 + 目标锚到方块上」（零位移迁移就在这里面）
        -- ★★1.75.47：迁移基准（axAuto）的目标**不进应用** —— 它的位置就是客户端版式本身，
        --   客户端挪了它 ≠ 漂移（拉回了才是破坏版式）；用户真拖过/显式设过（axAuto 已清）的才守。
        --   ★顺序即判据：dfBlockDrift **先跑**（它顺带做零位移迁移并**当场标 axAuto**），
        --     再读 axAuto 决定是否接管 —— 否则迁移那一拍 axAuto 还没标上，纯迁移层会被误接管。
        if dfBlockDrift(tgt) and rec.axAuto ~= true then
          if dfBlockApply(tgt) then fixed = fixed + 1 end
        end
      elseif type(rec.base) == "table" and (rec.dx or rec.dy) then
        local bcap2 = rec.cur or rec.base -- ★同上
        if not dfIsAt(fr, bcap2, rec.dx, rec.dy) then
          local ok = dfPlaceFrom(fr, bcap2, rec.dx, rec.dy)
          if ok then fixed = fixed + 1 end
        end
      end
      attrs = attrs + dfAttrsApply(fr, rec, true, tgt)
    end
  end
  if not quiet then
    say("框拖拽：已应用存档（有记录 " .. tostring(checked) .. " 个目标；回位 " .. tostring(fixed) ..
      " 个；属性 " .. tostring(attrs) .. " 项）")
  end
  return fixed, checked, attrs
end

-- ============ 队伍 / 团队帧「按需出现」的跟随（1.74.32）============
-- ★为什么必须有：队伍/团队框体**不是常驻帧** —— 单人时客户端不建（或建了不显示）队伍框，非团队时没有团队框。
--   把它们加进可拖拽目标后，「组上人那一刻」必须补上两件事：
--     ① 用同一套口径**恢复存档参数**（出现即生效）—— 否则用户在队伍里存过的位置/宽高会**静默不生效**
--        （最典型的路径：登录时 VARIABLES_LOADED 就跑了 dfApplyAll，那时队伍框还不存在）；
--     ② **重贴拖拽柄**（否则目标在手，柄却要等下一次手动刷新才出现）。
-- ★事件名**有本地证据，不是猜的**（铁律 5 的③④）：`Toolbox.lua:4056` 正在注册
--   PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE（名字着色那条链路，真机在跑）；PLAYER_ENTERING_WORLD 全项目在用。
--   ★`GROUP_ROSTER_UPDATE` 只出现在子插件的**事件探测名单**里（那是拿 `IsEventRegistered` 逐个试的清单，
--     不等于客户端认识它）⇒ **不注册**（不许把探测名单当注册依据）。
-- ★有界：事件之后只跟 `DF_ROSTER_TRIES` 次（帧可能在事件之后才建出来），跟完即停 ——
--   **不做常驻轮询**（与「有界复查窗口」同一纪律：不做没人叫停的后台周期任务）。
--   ★1.75.x：同一套「按需出现」跟随也覆盖**宠物动作条**（`pet = true`）——
--     `UNIT_PET` 有本地证据（本项目 `addons/EH_DebugBox/EH_DebugBox.lua` 正在注册它）；
--     ★`PET_BAR_UPDATE` 本地零证据 ⇒ **不注册**（铁律 5④）。
local DF_ROSTER_EVENTS = { "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "UNIT_PET", "PLAYER_ENTERING_WORLD" }
local DF_ROSTER_PERIOD = 0.5
local DF_ROSTER_TRIES = 4

-- 单个目标：把存档参数应用一次（位置 + 属性）——与 dfApplyAll 逐目标那段**同一口径**（不另写一套公式）
-- ★★★`posOnly`（1.75.36g，可选第二参）= **只治位置、绝不碰属性**：战斗中专用。
--   为什么要有它：用户报障「进入攻击状态会把宠物动作栏顶上去」，而位置漂移正是在**战斗中**发生的；
--   但战斗中对受保护帧写属性风险高（被拒/被忽略）⇒ 战斗里**只做位置这一件事**。
--   ★它仍然是「位置 + 属性」两者的**唯一应用入口**（只是多了一个开关），不许在别处再写一套。
-- 返回 `true, atPos`：atPos = 位置**量回自证**的结果（nil = 本来没有位置工作 / true = 已到位 / false = 没修到位）。
--   ★为什么要量回：`dfPlaceFrom` 内部全是 pcall，战斗中被客户端拒绝是**静默**的 ⇒ 不量一次就会把
--     「写了但没生效」报成修复成功（那正是本项目最恨的静默失效）。
local function dfApplyOne(tgt, posOnly)
  local store = dfStore(false)
  if not store or type(tgt) ~= "table" then return false end
  if not dfPicked(tgt.name) then return false end -- ★1.74.33 未勾选 = 不在管理范围（应用公式这一层也守一道）
  local rec = store[tgt.name]
  local fr = dfTargetFrame(tgt)
  if type(rec) ~= "table" or not fr then return false end
  local atPos = nil
  -- ★★★1.75.36l 方块目标（用户定稿）：位置 = 方块的**绝对坐标**（目标被接管锚点、挂在方块上）
  if tgt.block == true then
    -- ★★1.75.47：迁移基准（axAuto）= 没有位置工作（客户端版式它自己说了算）⇒ 不应用、atPos 也记 nil。
    --   ★顺序即判据：dfBlockDrift **先跑**（顺带迁移 + 当场标 axAuto），再读 axAuto ——
    --     否则迁移那一拍 axAuto 还没标上，纯迁移层会被误接管。
    local driftB = dfBlockDrift(tgt)
    if rec.axAuto == true then
      atPos = nil
    else
      if driftB then dfBlockApply(tgt) end
      atPos = (not dfBlockDrift(tgt)) and true or false
    end
  elseif type(rec.base) == "table" and (rec.dx or rec.dy) then
    local bcap = rec.cur or rec.base -- ★应用用当前基准
    if not dfIsAt(fr, bcap, rec.dx, rec.dy) then dfPlaceFrom(fr, bcap, rec.dx, rec.dy) end
    atPos = dfIsAt(fr, bcap, rec.dx, rec.dy) and true or false
  end
  if not posOnly then dfAttrsApply(fr, rec, true, tgt) end
  return true, atPos
end

-- ============ ★★★1.74.33 方案 A + C：被动窗口「打开即重设」============
-- 用户拍板（原话）：「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度.UI 会撕裂」+「A+C 分析实施」。
-- 【A 链式接管 OnShow】第一轮真机取证（参考卷 R15 ⑥d）量出的事实决定了解法：
--   · 23 个被动窗口里 **21 个原生就有 OnShow 脚本** ⇒ **绝不能覆盖式接管**（那会顶掉客户端自己的开窗逻辑）；
--   · 本客户端**没有 `Frame:HookScript`**（23 个目标全 nil）⇒ 只能自己做链：`GetScript` 存原脚本 →
--     `SetScript` 装我们的 → 我们的脚本里**第一件事就是 `pcall` 调原脚本**，然后才做自己的事。
--   重设的**唯一入口**是 `dfApplyOne(tgt)`（它本来就是「位置 + 属性」的应用公式唯一入口）——一行逻辑都不重写。
--   为什么位置也要跟着重设：第一轮真机证据显示**客户端开窗时会把它自己的窗口摆回原位**（属性窗口：拖到 384 后重开又是 0）。
-- 【C 开窗后短复查】**有界**（0.3s × 4 次 / 墙钟 3s 硬上限），到点自停并**摘脚本** ——
--   隐藏帧的 OnUpdate 照样触发，「只 Hide 不摘」= 永远空转（本项目给分享滴出帧记过这条账）。
--   ★只盯「刚打开过」的目标，且**拖拽中 / 战斗中一律跳过**：绝不把用户正在拖的窗口抢回去、不碰受保护帧的属性。
-- ★关掉功能/取消勾选 ⇒ `dfOpenHookRemove` 把 OnShow **还回原生那一个**（完全还原，不留我们的钩子）。
local DF_OPEN_PERIOD = 0.3     -- 复查周期（秒）
local DF_OPEN_CHECKS = 4       -- 每个目标最多复查几轮（≈1.2 秒，够客户端把尺寸摆完）
local DF_OPEN_WALL = 3.0       -- 绝对墙钟上限（秒）：任何情况都不许超过它
local DF_OPEN_MAX_T = 12       -- 一次最多盯几个目标（连点也不留长尾）

-- ★按**名字**回查目标表项：属性弹窗那条路拿到的是**帧**（`dfCommitPop(fr, label, name)`），
--   帧上没有 noSize —— 判不动「被动窗口」这件事（组 220② 当场抓到第一版）。名字 → 表项的唯一查法放这里，
--   别处（弹窗、清理、复查）都复用，免得各写一份迟早不一致。
local function dfTgtOfName(name)
  if type(name) ~= "string" or name == "" then return nil end
  for i = 1, table.getn(DF_TARGETS) do
    if DF_TARGETS[i].name == name then return DF_TARGETS[i] end
  end
  return nil
end

-- 该不该对这个目标做「打开即重设」：主开关 + 勾选 + 帧在位 + 当前是显示的
-- ============ ★★★1.75.47 ghost：开窗/重设的「弹跳遮蔽」 ============
-- 用户原话：「图层拖拽完成后的属性设置会被游戏内置的机制重置回初始位置…能否强制设置隐藏或者透明度 0，
--   等属性设置成功之后再显示正确的透明度？这样…弹跳位置，视觉上不太好」。
-- 机制（与 SimpleMap 的 SMFIT_GHOST 同族，已验证的模式）：
--   ① 客户端开窗/出现时会先把窗口摆回**它的**原位，我们的重设（OnShow 链 / C 复查）再把它拉回自定义位置
--     ⇒ 用户看到「跳一下」。**先 alpha 归零遮蔽 → 应用 → 量回自证就位 → 恢复正确透明度**（rec.alpha 或 1），
--     多数情况同一帧内完成 ⇒ 弹跳根本看不见；
--   ② **alpha 归零，绝不 Hide()** —— IsShown 是「显示中」判据的信号源（藏了会把自己判死，SimpleMap 判据 ①）；
--   ③ 恢复值 = **记录里的自定义透明度**（没有则 1），不是固定 1.0；
--   ④ 结构性兜底：复查窗口到点 / 摘链 / 关功能 ⇒ **无条件恢复**（绝不永久隐形）；
--   ⑤ 只遮「有位置工作」的层：axAuto 迁移基准不算（本来就在原位，没有弹跳可遮）。
DF.ghostOn = function(fr, rec)
  if (type(fr) ~= "table" and type(fr) ~= "userdata") or type(fr.SetAlpha) ~= "function" then return end
  DF.ghost = DF.ghost or {}
  if DF.ghost[fr] == nil then -- 已在遮蔽中不重复记（防把 0 记成恢复值）
    DF.ghost[fr] = (type(rec) == "table" and type(rec.alpha) == "number") and rec.alpha or 1
  end
  pcall(fr.SetAlpha, fr, 0)
end
DF.ghostOff = function(fr)
  local G = DF.ghost
  if type(G) ~= "table" or G[fr] == nil then return end
  local a = G[fr]
  if type(fr.SetAlpha) == "function" then pcall(fr.SetAlpha, fr, a) end
  G[fr] = nil
end
DF.ghostOffAll = function()
  local G = DF.ghost
  if type(G) ~= "table" then return end
  for fr in pairs(G) do
    if type(fr.SetAlpha) == "function" then pcall(fr.SetAlpha, fr, G[fr]) end
    G[fr] = nil
  end
end
-- 「有位置工作要遮」= 有用户自定义的位置记录（迁移基准 axAuto 不算：它本来就贴在原位，没有弹跳）
DF.ghostHasWork = function(tgt, rec)
  if type(rec) ~= "table" then return false end
  if type(tgt) == "table" and tgt.block == true then
    return (rec.ax ~= nil or rec.ay ~= nil) and rec.axAuto ~= true
  end
  return type(rec.base) == "table" and (rec.dx ~= nil or rec.dy ~= nil)
end
-- 量回自证：位置已经就位（与守卫同一套判据；方块目标判 dfBlockDrift 的反面）
DF.ghostSettled = function(tgt, fr, rec)
  if type(rec) ~= "table" then return true end
  if type(tgt) == "table" and tgt.block == true then return not dfBlockDrift(tgt) end
  if type(rec.base) == "table" and (rec.dx ~= nil or rec.dy ~= nil) then
    return dfIsAt(fr, rec.cur or rec.base, rec.dx, rec.dy) and true or false
  end
  return true
end

local function dfOpenDue(tgt)
  if not DF.on then return false end                 -- 主开关关着 → 什么都不做
  if not dfPicked(tgt.name) then return false end    -- 未勾选的层不在管理范围
  local fr = dfTargetFrame(tgt)
  if not fr then return false end
  if type(fr.IsShown) == "function" then
    local ok, v = pcall(fr.IsShown, fr)
    if ok and v == false then return false end       -- 已经关了：不必重设（用户看都看不到）
  end
  return true, fr
end

-- ★C 的**真实步进体**（OnUpdate 只是薄壳：判据可以直接驱动它，绝不复刻一遍逻辑）
local function dfOpenCheckStep()
  local W = DF.openWatch
  if not W or W.on ~= true then return false, 0 end
  W.runs = W.runs + 1
  local fixed, alive = 0, 0
  for name in pairs(W.targets) do
    local tgt = nil
    for i = 1, table.getn(DF_TARGETS) do
      if DF_TARGETS[i].name == name then tgt = DF_TARGETS[i] break end
    end
    local ok = false
    if tgt then ok = dfOpenDue(tgt) end
    if not ok then
      W.targets[name] = nil                          -- 关了/不勾了/帧没了 → 不再盯它
    else
      alive = alive + 1
      if DF.dragging or dfInCombat() then
        W.skips = dfNum(W.skips, 0) + 1              -- ★拖拽中/战斗中跳过（如实记数，不假装做过）
      else
        local fr = dfTargetFrame(tgt)
        local store = dfStore(false)
        local rec = (type(store) == "table") and store[tgt.name] or nil
        if fr and type(rec) == "table" then
          local need = false
          if type(rec.base) == "table" and not dfIsAt(fr, rec.cur or rec.base, rec.dx, rec.dy) then need = true end
          if not need then
            local sc, al = dfReadAttrs(fr)
            -- ★宽/高**不在复查范围**（被动窗口根本不设宽高，见 dfAttrsApply 的 allowSize）——
            --   复查只钉「缩放/透明/位置」这三样，免得把一个会撕裂布局的能力偷偷加回来。
            if type(rec.scale) == "number" and sc and math.abs(sc - rec.scale) > 0.005 then need = true end
            if type(rec.alpha) == "number" and al and math.abs(al - rec.alpha) > 0.005 then need = true end
          end
          if need and dfApplyOne(tgt) then
            fixed = fixed + 1
            W.fixed = dfNum(W.fixed, 0) + 1
          end
          -- ★1.75.47 ghost 量回：位置已就位 ⇒ 恢复透明度（没就位继续遮蔽，交给下一拍；窗口到点有兜底）
          if DF.ghost and DF.ghost[fr] ~= nil and DF.ghostSettled(tgt, fr, rec) then DF.ghostOff(fr) end
        end
      end
    end
  end
  W.checked = dfNum(W.checked, 0) + alive
  W.alive = alive
  return true, fixed
end

local function dfOpenStop(why)
  local W = DF.openWatch
  if not W then return false end
  W.on = false
  W.why = tostring(why or "?")
  DF.ghostOffAll()  -- ★1.75.47 结构性兜底：复查窗口到点/出错/完成 ⇒ 遮蔽一律无条件恢复（绝不永久隐形）
  -- ★★必须**摘脚本**：隐藏帧的 OnUpdate 照样触发 ⇒ 只 Hide 会永远空转
  if W.frame and type(W.frame.SetScript) == "function" then
    pcall(W.frame.SetScript, W.frame, "OnUpdate", nil)
  end
  return true
end

local function dfOpenOnUpdate(dt)
  local W = DF.openWatch
  if not W or W.on ~= true then return end
  local d = tonumber(dt)
  if not d or d <= 0 then d = dfNum(arg1, DF_OPEN_PERIOD) end
  if not d or d <= 0 then d = DF_OPEN_PERIOD end
  W.age = dfNum(W.age, 0) + d
  W.acc = dfNum(W.acc, 0) + d
  if W.age >= DF_OPEN_WALL then dfOpenStop("wall") return end
  if W.acc < DF_OPEN_PERIOD then return end
  W.acc = 0
  -- ★OnUpdate 里抛错会**每帧刷屏**且刷屏会掩盖真正的原因 ⇒ 立刻停并如实记下来
  local ok, err = pcall(dfOpenCheckStep)
  if not ok then
    dfOpenStop("error")
    dfLog("OPEN WATCH 出错已停：" .. tostring(err))
    return
  end
  if W.runs >= DF_OPEN_CHECKS or dfNum(W.alive, 0) == 0 then dfOpenStop("done") end
end

-- 武装 C（同一个目标重复开窗只把计数刷新一下，不重复建帧）
local function dfOpenArm(tgt)
  if type(tgt) ~= "table" then return false end
  local W = DF.openWatch
  if type(W) ~= "table" or W.on ~= true or dfNum(W.runs, 0) >= DF_OPEN_CHECKS then
    W = { on = true, targets = {}, runs = 0, acc = 0, age = 0, fixed = 0, skips = 0, checked = 0 }
    DF.openWatch = W
  end
  local n = 0
  for _ in pairs(W.targets) do n = n + 1 end
  if n >= DF_OPEN_MAX_T and W.targets[tgt.name] == nil then
    W.drop = dfNum(W.drop, 0) + 1                    -- 上限到顶就**如实记「没盯上」**，不假装盯了
  else
    W.targets[tgt.name] = true
  end
  if not W.frame and type(CreateFrame) == "function" then
    W.frame = CreateFrame("Frame", "EVAL_DF_OPENWATCH", dfHost())
  end
  if W.frame and type(W.frame.SetScript) == "function" then
    pcall(W.frame.SetScript, W.frame, "OnUpdate", dfOpenOnUpdate)
  end
  return true
end

-- ============ A：链式 OnShow 接管 ============
-- `DF.onShowOrig[fr]` = 该帧**原生**的 OnShow（nil = 原本没有，也要如实存着）；
-- `DF.onShowTgt[fr]`  = 该帧对应的目标（OnShow 的回调只给 self，得靠它反查目标）。
local function dfOnShowBoss(self)
  DF.onShowCalls = dfNum(DF.onShowCalls, 0) + 1
  -- ★★★第一件事永远是**先调原生脚本**：本客户端 21/23 个被动窗口都有 OnShow（客户端自己的开窗逻辑就在里面），
  --   跳过它 = 直接破坏别人的界面（与「滚轮链式接管」同一条纪律，也是本轮 A 方案的核心前提）。
  local orig = DF.onShowOrig and DF.onShowOrig[self]
  if type(orig) == "function" then pcall(orig, self) end
  local tgt = DF.onShowTgt and DF.onShowTgt[self]
  if type(tgt) ~= "table" then return end
  local ok = dfOpenDue(tgt)
  if not ok then return end
  if DF.dragging or dfInCombat() then
    DF.onShowSkips = dfNum(DF.onShowSkips, 0) + 1    -- 拖拽中/战斗中不抢：如实记「跳过了」
  else
    -- ★1.75.47 ghost：客户端开窗把窗口摆回它的原位 → 我们拉回 ⇒ 视觉上「跳一下」。
    --   有位置工作的先 alpha 归零遮蔽，应用后量回、就位即恢复（多数同一帧内完成，弹跳看不见）；
    --   没就位交给 C 复查窗口（到点无条件恢复 = 兜底）。
    local storeS = dfStore(false)
    local recS = (type(storeS) == "table") and storeS[tgt.name] or nil
    local frS = dfTargetFrame(tgt)
    if frS and DF.ghostHasWork(tgt, recS) then DF.ghostOn(frS, recS) end
    if dfApplyOne(tgt) then
      DF.onShowFixed = dfNum(DF.onShowFixed, 0) + 1
    end
    if frS and DF.ghost and DF.ghost[frS] ~= nil and DF.ghostSettled(tgt, frS, recS) then DF.ghostOff(frS) end
  end
  dfOpenArm(tgt)   -- ★C：开窗后这一两秒再盯几眼（客户端可能过后才把自己的尺寸摆好）
end

-- 装链（幂等）：被别的东西换掉过 → 重新链一次，链的是**最新那个**原生脚本
local function dfOpenHookEnsure(fr, tgt)
  if type(fr) ~= "table" and type(fr) ~= "userdata" then return false end
  if type(tgt) ~= "table" or type(fr.SetScript) ~= "function" then return false end
  local cur = nil
  if type(fr.GetScript) == "function" then
    local ok, v = pcall(fr.GetScript, fr, "OnShow")
    if ok then cur = v end
  end
  DF.onShowTgt[fr] = tgt
  if cur == DF.onShowBoss then return true end       -- 已经是我们的链：幂等
  DF.onShowOrig[fr] = cur                            -- ★先存原脚本（nil 也存：「原本没有」也是事实）
  if not pcall(fr.SetScript, fr, "OnShow", DF.onShowBoss) then return false end
  DF.onShowN = dfNum(DF.onShowN, 0) + 1
  return true
end

-- 卸链：把 OnShow **还回原生那一个**（关掉功能/取消勾选时完全还原，不留我们的钩子）
local function dfOpenHookRemove(fr)
  if type(fr) ~= "table" and type(fr) ~= "userdata" then return false end
  if not DF.onShowTgt or DF.onShowTgt[fr] == nil then return false end
  local orig = DF.onShowOrig and DF.onShowOrig[fr] or nil
  local cur = nil
  if type(fr.GetScript) == "function" then
    local ok, v = pcall(fr.GetScript, fr, "OnShow")
    if ok then cur = v end
  end
  if cur == DF.onShowBoss and type(fr.SetScript) == "function" then
    pcall(fr.SetScript, fr, "OnShow", orig)          -- nil = 摘掉脚本（与「原本没有」一致）
    DF.onShowOff = dfNum(DF.onShowOff, 0) + 1
  end
  -- ★不管现在挂的是谁的脚本，我们自己的记账都要清干净（否则下次会拿它当「原生脚本」链错人）
  DF.onShowTgt[fr] = nil
  if DF.onShowOrig then DF.onShowOrig[fr] = nil end
  DF.ghostOff(fr)   -- ★1.75.47 摘链时若还在遮蔽 ⇒ 恢复该帧透明度（兜底的一支）
  return true
end

-- 每次刷新同步一遍：该挂的挂、不该挂的摘（条件 = 主开关 + 该层被勾选；与图标开关**无关**）
local function dfOpenHooksSync(on)
  DF.onShowOrig = DF.onShowOrig or {}
  DF.onShowTgt = DF.onShowTgt or {}
  local n = 0
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    if tgt.icon == true then
      local fr = dfTargetFrame(tgt)
      if fr and on and dfPicked(tgt.name) then
        if dfOpenHookEnsure(fr, tgt) then n = n + 1 end
      elseif fr then
        dfOpenHookRemove(fr)
      end
    end
  end
  DF.onShowN = n
  return n
end
DF.onShowBoss = dfOnShowBoss   -- ★读值口/判据要比对「现在挂的是不是我们这条链」，得有个稳定的引用

-- 一次结算：**只碰带 `roster` / `pet` 标记的目标**（队伍/团队/宠物动作条），不重锚别的目标
--   （别的目标的位置由「有界复查窗口」负责 —— 两处各管一段，免得这里偷偷变成常驻重锚）
local function dfRosterPass(quiet)
  if not DF.on then return 0 end
  local n = 0
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    -- ★1.74.33 未勾选的队伍/团队帧**连记账都不做**（记了 applied 之后再勾上就不会补恢复 —— 那是个静默漏做）
    if (tgt.roster or tgt.pet) and dfPicked(tgt.name) then
      local fr = dfTargetFrame(tgt)
      -- ★按**帧对象**记账：帧被重建 ⇒ 重新恢复一次（这正是「按需出现」要的效果）
      if fr and not DF.rosterApplied[fr] then
        DF.rosterApplied[fr] = true
        if dfApplyOne(tgt) then DF.rosterDone = DF.rosterDone + 1 end
        n = n + 1
      end
    end
  end
  if n > 0 then
    if type(dfRefresh) == "function" then pcall(dfRefresh) end
    if not quiet then
      say("框拖拽：队伍/团队/宠物帧出现了 " .. tostring(n) .. " 个 → 已按存档恢复，拖拽柄也补上了")
    end
  end
  return n
end

local function dfRosterOnUpdate()
  if DF.rosterLeft <= 0 then return end
  -- ★★★本客户端 OnUpdate **不传任何参数**（1.74.31 真机事故）⇒ dt 的**唯一**来源是全局 `arg1`。
  --   旧写法 `dfNum(a1, nil)` 是「形参优先」时代的残留：签名去掉形参后，`a1` 变成**全局 nil**，
  --   那两行既永远不成立、又会去读一个来路不明的全局（静默族）⇒ 直接删掉。
  local dt = dfNum(arg1, 0.05)
  if (not dt) or dt < 0 then dt = 0.05 end
  DF.rosterAcc = DF.rosterAcc + dt
  if DF.rosterAcc < DF_ROSTER_PERIOD then return end
  DF.rosterAcc = 0
  DF.rosterLeft = DF.rosterLeft - 1
  dfRosterPass(true)
  if DF.rosterLeft <= 0 then
    dfLog("ROSTER 结算结束 why=" .. tostring(DF.rosterWhy or "?"))
  end
end

local function dfRosterEnsure()
  if DF.rosterFrame then
    if type(DF.rosterFrame.SetScript) == "function" then
      pcall(DF.rosterFrame.SetScript, DF.rosterFrame, "OnUpdate", dfRosterOnUpdate)
    end
    return true
  end
  if type(CreateFrame) ~= "function" then return false end
  local rf = CreateFrame("Frame", "EVAL_DF_ROSTER", dfHost())
  DF.rosterFrame = rf
  if type(rf.RegisterEvent) == "function" then
    for i = 1, table.getn(DF_ROSTER_EVENTS) do
      pcall(rf.RegisterEvent, rf, DF_ROSTER_EVENTS[i])
    end
  end
  rf:SetScript("OnEvent", function()
    local ev = arg1
    if type(ev) ~= "string" then ev = event end
    if not DF.on then return end
    if type(dfRosterArm) == "function" then dfRosterArm(ev) end
  end)
  rf:SetScript("OnUpdate", dfRosterOnUpdate)
  return true
end

dfRosterArm = function(why)
  if not dfRosterEnsure() then return false end
  DF.rosterWhy = tostring(why or "?")
  DF.rosterAcc = 0
  DF.rosterLeft = DF_ROSTER_TRIES
  if type(DF.rosterFrame.SetScript) == "function" then
    pcall(DF.rosterFrame.SetScript, DF.rosterFrame, "OnUpdate", dfRosterOnUpdate)
  end
  dfRosterPass(true) -- 立刻先算一次（事件到达时帧通常已经在了，不必等 0.5s）
  dfLog("ROSTER ARM why=" .. tostring(why) .. " tries=" .. tostring(DF_ROSTER_TRIES))
  return true
end

-- ============ 一次性迁移（老存档 → 新存档）============
-- 老落点：子插件 `EH_DEBUGBOX_CFG.cust["[全局] 名字"]`（opt = GetPoint 原样四元组 + set.dx/dy/scale/alpha/hidden）。
-- 新落点按**帧名字**存。搬移时原样沿用偏移量（= 老代码当年的应用公式，视觉位置不变），
-- 并打上 legacy 标记：**首次拖拽后自动转为实测口径**（那时 base 会从实测边重抓）。
-- ★老记录**不删**（那是子插件的 SavedVariables，我们无权改写它的持久化时机）；子插件那侧改为**跳过这 5 个目标**，
--   于是老记录只是历史数据，不会再有人拿它去抢锚点（两处真值 → 一处真值）。
local function dfMigrate(quiet)
  local store = dfStore(true)
  if not store then return 0 end
  if store.mig == true then return 0 end
  local old = rawget(_G, "EH_DEBUGBOX_CFG")
  if type(old) ~= "table" then return 0 end -- 老插件没装 / 存档未就位：不标记，下次再说（便宜）
  local cust = old.cust
  if type(cust) ~= "table" then
    store.mig = true
    return 0
  end
  local n = 0
  for i = 1, table.getn(DF_TARGETS) do
    local nm = DF_TARGETS[i].name
    local path = "[全局] " .. nm
    local src = cust[path]
    if type(src) == "table" and store[nm] == nil then
      local rec = {}
      local opt = src.opt
      if type(opt) == "table" and type(opt[1]) == "string" then
        local rn = opt[2]
        if type(rn) ~= "string" or rn == "" then rn = nil end
        local rp = type(opt[3]) == "string" and opt[3] or opt[1]
        rec.base = { { opt[1], rn, rp, dfNum(opt[4], 0), dfNum(opt[5], 0) } }
        rec.legacy = true
      end
      local set = src.set
      if type(set) == "table" then
        rec.dx = dfNum(set.dx, 0)
        if type(rec.cur) ~= "table" then rec.cur = rec.base end -- ★老记录：当前基准 = 原始锚点（口径一致）
        rec.dy = dfNum(set.dy, 0)
        if type(set.scale) == "number" then rec.scale = set.scale end
        if type(set.alpha) == "number" then rec.alpha = set.alpha end
        if type(set.hidden) == "boolean" then rec.hidden = set.hidden end
        -- ★1.74.31 老记录里若也有宽/高（子插件那套 set.w/set.h）→ 一起搬过来。
        --   ★**没有原始值可搬**（老格式没记过 ow/oh）⇒ 重置时按「无法还原」如实报告，字段保留。
        if type(set.w) == "number" then rec.w = set.w end
        if type(set.h) == "number" then rec.h = set.h end
      end
      if rec.base or rec.dx or rec.dy or rec.scale or rec.alpha or rec.hidden ~= nil
        or rec.w ~= nil or rec.h ~= nil then
        store[nm] = rec
        n = n + 1
      end
    end
  end
  store.mig = true
  if n > 0 then
    say("框拖拽：已把老存档里的 " .. tostring(n) .. " 个目标定位记录搬到新存档（EVAL_HELP_CONFIG.dragFrames）")
  elseif not quiet then
    say("框拖拽：老存档里没有可搬的定位记录（新存档自己的记录不受影响）")
  end
  dfLog("迁移完成 n=" .. tostring(n))
  return n
end

-- ★★★1.75.109 **聊天窗两页并档**（老存档一次性合并；同 `dfMigrate` 一样**只做一次**、**如实出声**）：
--   规范键是 `ChatFrame1` ⇒ 老存档里「只有 `ChatFrame2` 那份」必须**搬过去**（不搬 = 用户的战斗记录设置
--   静默作废 —— 本项目最恨的那种静默）。两份都有 ⇒ 以**聊天框**那份为准，并如实说清删了哪份。
--   ★必须 `rawget/rawset`：`store[...]` 走的是镜像代理，会把 `ChatFrame2` 全路由到 `ChatFrame1`（读不到真身）。
local function dfMirrorMerge(quiet)
  local store = dfStore(true)
  if not store then return 0 end
  if rawget(store, "mir") == true then return 0 end
  local a, b = rawget(store, "ChatFrame1"), rawget(store, "ChatFrame2")
  local n = 0
  if type(b) == "table" then
    if type(a) ~= "table" then
      rawset(store, "ChatFrame1", b)
      n = 1
    else
      n = 2
    end
    rawset(store, "ChatFrame2", nil)
  end
  rawset(store, "mir", true)
  if n == 1 then
    say("框拖拽：聊天框与战斗记录是**同一窗口的两页** ⇒ 已把战斗记录那份设置并入聊天框" ..
      "（以后两页共用一份：位置 / 宽高 / 缩放 / 透明度 / 显隐）")
  elseif n == 2 then
    say("框拖拽：聊天框与战斗记录是同一窗口的两页 ⇒ 两份记录已合并（以**聊天框**那份为准，" ..
      "战斗记录自己那份已删除）")
  elseif not quiet then
    say("框拖拽：聊天框与战斗记录共用一份设置（本次无需合并）")
  end
  dfLog("镜像并档 n=" .. tostring(n))
  return n
end
DF.mirrorMerge = dfMirrorMerge   -- ★对外口（安装/迁移两条路都走它；挂 DF 表 = 不新增文件级 local）

-- ============ 启动期**有界**复查（1s × 最多 5 次，做完永久停）============
-- ★★为什么不是「每 2 秒常驻」：用户明确「最大检测时间为屏幕载入完成 5s 内」——
--   常驻 tick 既费帧又在拖拽/切图时反复抢锚点；有界窗口把「启动期自愈」与「之后再不管」切开。
-- ★★取舍（**用户明确要的行为，如实点出**）：窗口结束后**没有人再修正**「用户后来手动改动 / 切地图把层挤动」——
--   那时要靠工具箱 [重置]（还原属性+位置）或重登（重走一次启动期复查）。这是有意为之，不是漏做。

-- 停止（永久）：摘掉 OnUpdate 脚本 + 落原因 + **带数字如实播报**（不静默）
local function dfKeepStop(why)
  if DF.keepDone then return end
  DF.keepDone = true
  DF.keepWhy = tostring(why or "?")
  local kf = DF.keepFrame
  if kf and type(kf.SetScript) == "function" then
    pcall(kf.SetScript, kf, "OnUpdate", nil) -- ★永久停：脚本被摘掉 ⇒ 不再有常驻 tick
  end
  local sk = ""
  if DF.keepSkips > 0 then
    sk = "（其中跳过 " .. tostring(DF.keepSkips) .. " 次：战斗中/拖拽中不重锚）"
  end
  local tail
  if why == "wall" then
    tail = "到绝对上限 " .. string.format("%.0f", DF_KEEP_WALL) .. " 秒仍未查满 " .. tostring(DF_KEEP_CHECKS) .. " 次，按上限如实停止"
  elseif why == "skipped" then
    tail = "评估次数上限 " .. tostring(DF_KEEP_TRIES) .. " 次用完（一直战斗/拖拽中，按上限如实停止）"
  elseif why == "drift" then
    tail = "期间检测到漂移，已按存档重设 " .. tostring(DF.keepFixed) .. " 轮"
  else
    tail = tostring(DF_KEEP_CHECKS) .. " 次全部符合参数，一次都没重设"
  end
  say(string.format("框拖拽启动期复查结束：净检查 %d 次%s · 覆盖目标 %d 个 · 修正 %d 轮 · %s；之后不再定时复查（仅启动期）",
    DF.keepRuns, sk, DF.keepChecked, DF.keepFixed, tail))
  dfLog("KEEP STOP why=" .. tostring(why) .. " runs=" .. tostring(DF.keepRuns) .. " tries=" .. tostring(DF.keepTries) ..
    " skips=" .. tostring(DF.keepSkips) .. " fixed=" .. tostring(DF.keepFixed) .. " age=" .. string.format("%.2f", DF.keepAge))
end

-- 每帧入口（★断言直接点火**这个真实脚本**：GetScript("OnUpdate") 拿到的就是它）
local function dfKeepOnUpdate()
  if DF.keepDone then return end
  -- ★★★同上：零形参回调，dt 只认全局 `arg1`（测试要注入 dt 也必须走这条真机通道，
  --   读值口/测试件 = `EVAL_TEST_FIRE_UPDATE(frame, dt)`）。
  local dt = dfNum(arg1, 0.05)
  if (not dt) or dt < 0 then dt = 0.05 end
  DF.keepAge = DF.keepAge + dt
  DF.keepAcc = DF.keepAcc + dt
  if DF.keepAcc < DF_KEEP_PERIOD then
    -- 等待期里也要守住绝对上限（帧率极低 / dt 很大时，不能让窗口靠「等」延长）
    if DF.keepAge >= DF_KEEP_WALL then dfKeepStop("wall") end
    return
  end
  DF.keepAcc = 0
  DF.keepTries = DF.keepTries + 1
  -- ⑤ 战斗中 / 拖拽中：**跳过**（不重锚、不计净检查次数），但评估次数与墙钟照样推进 ⇒ 有上限
  if DF.dragging or dfInCombat() then
    DF.keepSkips = DF.keepSkips + 1
    if DF.keepAge >= DF_KEEP_WALL then dfKeepStop("wall")
    elseif DF.keepTries >= DF_KEEP_TRIES then dfKeepStop("skipped") end
    return
  end
  DF.keepRuns = DF.keepRuns + 1
  local fixed, checked = dfKeepTick(true)
  DF.keepChecked = dfNum(checked, 0)
  if dfNum(fixed, 0) > 0 then
    DF.keepFixed = DF.keepFixed + 1
    if not DF.keepSaid then
      DF.keepSaid = true
      say("框拖拽启动期复查：检测到 " .. tostring(fixed) .. " 个目标被挤回原位 → 已按存档重设")
    end
  end
  local why = nil
  if DF.keepRuns >= DF_KEEP_CHECKS then why = (DF.keepFixed > 0) and "drift" or "allok"
  elseif DF.keepAge >= DF_KEEP_WALL then why = "wall"
  elseif DF.keepTries >= DF_KEEP_TRIES then why = "skipped" end
  if why then dfKeepStop(why) end
end

-- 建帧 + 挂脚本（幂等）；真正的「武装窗口」在 dfKeepArm
local function dfTickEnsure()
  if DF.keepFrame then
    if type(DF.keepFrame.SetScript) == "function" then pcall(DF.keepFrame.SetScript, DF.keepFrame, "OnUpdate", dfKeepOnUpdate) end
    return true
  end
  if type(CreateFrame) ~= "function" then return false end
  local kf = CreateFrame("Frame", "EVAL_DF_KEEP", dfHost())
  DF.keepFrame = kf
  kf:SetScript("OnUpdate", dfKeepOnUpdate)
  return true
end

-- 武装一次**有界**窗口（每次武装 = 一次「首次出现」：登录/进世界，或本次会话里刚把开关打开）
local function dfKeepArm(why)
  if not dfTickEnsure() then return false end
  DF.keepDone = false
  DF.keepWhy = nil
  DF.keepArmed = tostring(why or "?")
  DF.keepAcc = 0
  DF.keepAge = 0
  DF.keepRuns = 0
  DF.keepTries = 0
  DF.keepSkips = 0
  DF.keepFixed = 0
  DF.keepChecked = 0
  DF.keepSaid = false
  if type(DF.keepFrame.SetScript) == "function" then pcall(DF.keepFrame.SetScript, DF.keepFrame, "OnUpdate", dfKeepOnUpdate) end
  dfLog("KEEP ARM why=" .. tostring(why) .. " checks=" .. tostring(DF_KEEP_CHECKS) .. " period=" .. string.format("%.1f", DF_KEEP_PERIOD))
  return true
end

-- ============ 全屏接盘（拖拽期间才 Show）============
-- ★① 的主要修法之一：拖拽期间把鼠标接过来，松手时**无论指针在哪**都能收到 OnMouseUp/OnClick。
--   这是本项目已验证的形态（UnrealQuest 的筛选菜单同款「全屏 click-catcher」）。
--   ★只在拖拽期间显示 → 不吃正常点击；结束立刻 Hide（旧实现的遮罩忘了藏，见文件头）。
local function dfCatcherEnsure()
  if DF.catcher then return DF.catcher end
  if type(CreateFrame) ~= "function" then return nil end
  local host = dfHost()
  local c = CreateFrame("Button", "EVAL_DF_CATCHER", host)
  pcall(c.SetFrameStrata, c, "FULLSCREEN_DIALOG")
  pcall(c.SetFrameLevel, c, 800) -- 高于拖拽柄(450)、低于配置弹窗(1200)
  if type(c.SetAllPoints) == "function" and host then pcall(c.SetAllPoints, c, host) end
  if type(c.EnableMouse) == "function" then pcall(c.EnableMouse, c, true) end
  if type(c.RegisterForClicks) == "function" then pcall(c.RegisterForClicks, c, "LeftButtonUp", "RightButtonUp") end
  local function endFromCatcher() dfDragEnd("catcher") end
  c:SetScript("OnMouseUp", endFromCatcher)
  c:SetScript("OnClick", endFromCatcher)
  c:Hide()
  DF.catcher = c
  return c
end

local function dfCatcherShow(on)
  local c = DF.catcher
  if not c then return false end
  if on then pcall(c.Show, c) else pcall(c.Hide, c) end
  return true
end

-- ============ 配置弹窗（拖拽完成后弹出）============
local function dfPopHide()
  local p = DF.pop
  if not p then return end
  -- ★唯一出口：root 的 OnHide 负责收拾下拉与全屏遮罩（旧实现漏藏遮罩，导致后续拖拽全失效）
  if p.root then pcall(p.root.Hide, p.root) end
  if p.list then pcall(p.list.Hide, p.list) end
  if p.cover then pcall(p.cover.Hide, p.cover) end
end

local function dfPopRow(root, y, labelText, opts, fmt)
  local lab = root:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(lab.SetFontObject, lab, GameFontNormal) end
  pcall(lab.SetPoint, lab, "TOPLEFT", root, "TOPLEFT", 8, y)
  pcall(lab.SetText, lab, labelText)
  local btn = dfBtn(root, 84, 18, "")
  pcall(btn.SetPoint, btn, "TOPLEFT", root, "TOPLEFT", 108, y + 2)
  local row = { btn = btn, label = lab, opts = opts, fmt = fmt or "%s", value = nil }
  btn:SetScript("OnClick", function()
    local list = DF.pop and DF.pop.list
    if not list then return end
    if list:IsShown() and list.dfOwner == row then pcall(list.Hide, list) return end
    list.dfOwner = row
    list:SetHeight(24 * table.getn(opts) + 6)
    for k, rb in ipairs(list.rows) do
      if k <= table.getn(opts) then
        pcall(rb.Show, rb)
        if rb.text then pcall(rb.text.SetText, rb.text, string.format(row.fmt, opts[k])) end
      else
        pcall(rb.Hide, rb)
      end
    end
    pcall(list.ClearAllPoints, list)
    pcall(list.SetPoint, list, "TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
    pcall(list.Show, list)
  end)
  return row
end

-- 定位：**相对自己的父级**放屏幕正中（偏移由实测几何算出来），然后**读回自证**；
-- 读回不对 → 退回「改挂 UIParent + CENTER/CENTER」（配置窗用的就是这个已被天天验证的写法）。
-- 返回 mode 字符串 + 数字表。
local function dfPopPlace(root)
  local up = rawget(_G, "UIParent")
  local host = nil
  if root and type(root.GetParent) == "function" then
    local ok, p = pcall(root.GetParent, root)
    if ok and (type(p) == "table" or type(p) == "userdata") then host = p end
  end
  if not host then host = dfHost() end
  local ul, ub, uw, uh = dfMeasure(up)
  local hl, hb, hw, hh = dfMeasure(host)
  local info = { uip = (ul and true or false), host = (hl and true or false) }
  local es = 1
  if root and type(root.GetEffectiveScale) == "function" then
    local oke, v = pcall(root.GetEffectiveScale, root)
    if oke and tonumber(v) and tonumber(v) ~= 0 then es = tonumber(v) end
  end
  info.es = es
  -- 目标屏幕中心（UIParent 量得到就用它；量不到 → 退回 UIParent 自身，两处都量不到则记 failed）
  local cx, cy = nil, nil
  if ul then
    cx, cy = ul + uw / 2, ub + uh / 2
  end
  info.cx, info.cy = cx, cy
  local ok = false
  if cx and hl then
    -- CENTER 锚到父级 TOPLEFT，偏移 = 屏幕中心 − 父级左上角（父级左上角 = 左边缘, 上边缘）
    local hostTop = hb + hh
    local ox = (cx - hl) / es
    local oy = (cy - hostTop) / es
    info.ox, info.oy = ox, oy
    pcall(root.ClearAllPoints, root)
    ok = pcall(root.SetPoint, root, "CENTER", host, "TOPLEFT", ox, oy)
    info.set = ok and true or false
    -- ★读回自证（判据 = 「锚点到底落上了没有」）：SetPoint 成功 + GetNumPoints ≥ 1 + GetPoint(1) 的点名/x 偏移对得上。
    --   ★为什么不用「实测中心 vs 屏幕中心」当**硬**判据：本客户端 GetPoint 的 y 与 SetPoint 传参的 y 符号口径有歧义
    --     （文件头已记），拿它当硬判据会在真机上误判。实测中心照旧记进 info，由 /edb dragrect 打出来供人工判读。
    local np = nil
    if type(root.GetNumPoints) == "function" then
      local okn, v = pcall(root.GetNumPoints, root)
      if okn then np = tonumber(v) end
    end
    info.points = np
    local okg, gp, gx, gy = pcall(root.GetPoint, root, 1)
    info.gotPoint = (okg and type(gp) == "string") and gp or nil
    info.gotX = okg and dfNum(gx, nil) or nil
    info.gotY = okg and dfNum(gy, nil) or nil
    local pl, pb, pw, ph = dfMeasure(root)
    if pl then
      info.px, info.py = pl + pw / 2, pb + ph / 2
      info.cdx, info.cdy = info.px - cx, info.py - cy
    end
    local landed = ok and (np == nil or np >= 1)
    if landed and info.gotPoint and info.gotPoint ~= "CENTER" then landed = false end
    if landed and info.gotX and math.abs(info.gotX - ox) > 1 then landed = false end
    if DF.forcePlaceFail then
      landed = false
      info.forced = true -- 测试钩子：强制校验不过 → 走兜底分支
    end
    if landed then
      info.mode = "host"
      return "host", info
    end
  else
    info.set = false
  end
  -- 兜底：挂到 UIParent 上，用**父级相对**的 CENTER/CENTER（同配置窗）
  if up then
    pcall(root.SetParent, root, up)
    pcall(root.ClearAllPoints, root)
    local ok2 = pcall(root.SetPoint, root, "CENTER", up, "CENTER", 0, 0)
    info.set2 = ok2 and true or false
    local np2 = nil
    if type(root.GetNumPoints) == "function" then
      local okn, v = pcall(root.GetNumPoints, root)
      if okn then np2 = tonumber(v) end
    end
    info.points2 = np2
    if ok2 and (np2 == nil or np2 >= 1) then
      info.mode = "uiparent"
      return "uiparent", info
    end
  end
  info.mode = "failed"
  dfLog("弹窗定位失败：host=" .. tostring(info.host) .. " uip=" .. tostring(info.uip) ..
    " set=" .. tostring(info.set) .. " points=" .. tostring(info.points))
  return "failed", info
end

local function dfPopBuild()
  if DF.pop then return true end
  if type(CreateFrame) ~= "function" then return false end
  local host = dfHost()
  local p = { rows = {}, rowBy = {} }   -- ★rowBy：按 key 找行（1.74.33 起不再用下标读值）
  -- 全屏遮罩：点别处 = 关窗（用户要的「点非当前 UI 自动隐藏」）；**随 root 一起收**
  local cover = CreateFrame("Button", "EVAL_DF_POPCOVER", host)
  pcall(cover.SetFrameStrata, cover, "FULLSCREEN_DIALOG")
  pcall(cover.SetFrameLevel, cover, 1150)
  if type(cover.SetAllPoints) == "function" and host then pcall(cover.SetAllPoints, cover, host) end
  if type(cover.EnableMouse) == "function" then pcall(cover.EnableMouse, cover, true) end
  if type(cover.RegisterForClicks) == "function" then pcall(cover.RegisterForClicks, cover, "LeftButtonUp", "RightButtonUp") end
  cover:SetScript("OnClick", function() dfPopHide() end)
  cover:Hide()
  p.cover = cover

  local root = CreateFrame("Frame", "EVAL_DF_POP", host)
  root:SetWidth(DF_POP_W) root:SetHeight(DF_POP_H)
  pcall(root.SetFrameStrata, root, "FULLSCREEN_DIALOG")
  pcall(root.SetFrameLevel, root, 1200)
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  root:SetScript("OnHide", function()
    -- ★单一出口：root 一藏，下拉与遮罩都跟着藏（旧实现这里漏了遮罩）
    if p.list then pcall(p.list.Hide, p.list) end
    if p.cover then pcall(p.cover.Hide, p.cover) end
  end)
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  dfSolid(bg, 0.02, 0.02, 0.02, 0.88)
  local eTop = root:CreateTexture(nil, "BORDER")
  eTop:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  eTop:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  eTop:SetHeight(1)
  dfSolid(eTop, 0.55, 0.48, 0.20, 1)
  local eBot = root:CreateTexture(nil, "BORDER")
  eBot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  eBot:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  eBot:SetHeight(1)
  dfSolid(eBot, 0.55, 0.48, 0.20, 1)
  local eLeft = root:CreateTexture(nil, "BORDER")
  eLeft:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  eLeft:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  eLeft:SetWidth(1)
  dfSolid(eLeft, 0.55, 0.48, 0.20, 1)
  local eRight = root:CreateTexture(nil, "BORDER")
  eRight:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  eRight:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  eRight:SetWidth(1)
  dfSolid(eRight, 0.55, 0.48, 0.20, 1)
  local title = root:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(title.SetFontObject, title, GameFontNormal) end
  pcall(title.SetPoint, title, "TOPLEFT", root, "TOPLEFT", 8, -8)
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)
  p.title = title
  -- 五行下拉：显示/隐藏 · 缩放 · 透明度 · 宽度 · 高度
  -- ★★★1.74.31 用户要求：「完成弹窗属性设置还要增加当前层宽度/高度设置」
  -- ★★★1.74.33 用户明确（附截图：法术书撕裂）：「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度」
  --   ⇒ 每行都带**稳定的 key**（不再靠下标读值：下标读法在「宽高行被藏起来」时必错位），
  --     被动窗口（`tgt.noSize`）那两行**隐藏**并显示一行说明 —— 不是灰掉，是**不给这个能力**（灰掉仍可能被点到）。
  local function addRow(y, key, label, opts, fmt)
    local row = dfPopRow(root, y, label, opts, fmt)
    row.key = key
    p.rowBy[key] = row
    table.insert(p.rows, row)
    return row
  end
  -- ★X/Y 行：下拉预设（粗档）+ [−][+] 微调按钮（±10 / 按住 Shift ±1）
  --   ★微调按钮**直接写 row.value**：与「下拉选一个」是同一个语义（都要点 [保存] 才生效），
  --     不然会出现「按钮改了显示、保存却没带上」这种静默不一致。
  local function addXYRow(y, key, opts)
    local row = addRow(y, key, L(key == "x" and "TB_LD_X" or "TB_LD_Y"), opts, "%.0f")
    local function setVal(v)
      if v < DF_XY_MIN then v = DF_XY_MIN elseif v > DF_XY_MAX then v = DF_XY_MAX end
      v = math.floor(v + 0.5)
      row.value = v
      if row.btn and row.btn.label then
        pcall(row.btn.label.SetText, row.btn.label, string.format("%.0f", v) .. " ▾")
      end
    end
    local function nudgeBtn(x, txt, delta)
      local b = dfBtn(root, 30, 18, txt)
      pcall(b.SetPoint, b, "TOPLEFT", root, "TOPLEFT", x, y + 2)
      b:SetScript("OnClick", function()
        local step = delta
        if type(IsShiftKeyDown) == "function" then
          local oks, sh = pcall(IsShiftKeyDown)
          if oks and (sh == true or sh == 1) then
            step = (delta > 0) and DF_XY_NUDGE_FINE or -DF_XY_NUDGE_FINE
          end
        end
        local base = row.value
        if type(base) ~= "number" then base = row.cur end
        if type(base) ~= "number" then base = 0 end
        setVal(base + step)
      end)
      return b
    end
    row.nudgeMinus = nudgeBtn(172, "-", -DF_XY_NUDGE)
    row.nudgePlus = nudgeBtn(206, "+", DF_XY_NUDGE)
    row.setVal = setVal
    return row
  end
  addRow(-34, "show", L("TB_LD_SHOWHIDE"), { "show", "hide" }, "%s")
  addRow(-62, "scale", L("TB_LD_UISCALE"), DF_SCALE_PRESETS, "%.2f")
  addRow(-90, "alpha", L("TB_LD_ALPHA"), DF_ALPHA_PRESETS, "%.2f")
  addXYRow(-118, "x", DF_X_PRESETS)
  addXYRow(-146, "y", DF_Y_PRESETS)
  -- ★★★1.75.1 宽/高两行**回来了**，但**只对聊天窗显示**（用户：「只有针对聊天窗才支持长宽设置」）：
  --   ① 放在 X/Y **下面** ⇒ 前五行位置一个都不动（不需要重排已有行，避开「改一处崩三处」）；
  --   ② 非聊天窗由 dfCommitPop `Hide` 掉这两行并把窗高收回 `DF_POP_H`（**不是灰掉**：灰掉仍可能被点到）；
  --   ③ 聊天窗时窗高 = `DF_POP_H_SIZE`（见它的注释：不加高会压到底部按钮上）。
  addRow(-174, "w", L("TB_LD_WIDTH"), DF_W_PRESETS, "%.0f")
  addRow(-202, "h", L("TB_LD_HEIGHT"), DF_H_PRESETS, "%.0f")
  -- ★★★1.74.33 用户（附截图：那行说明与底部 取消/保存 **叠在一起**）：
  --   「属性配置信息重叠,可以将信息在外部触发图标tooltip 内展示」
  --   ⇒ 弹窗里**不再放任何说明文字**（224 高的窗里五行已经排到底，再塞文字必然与按钮抢位置）；
  --     这些信息统一挂到**图标 / 头部拖拽带的 tooltip** 上（见 dfBindDragButton 的 OnEnter）。
  -- 共用下拉列表（本客户端没有原生下拉）
  local list = CreateFrame("Frame", "EVAL_DF_POPLIST", host)
  list:SetWidth(84) list:SetHeight(24 * table.getn(DF_ALPHA_PRESETS) + 6)
  pcall(list.SetFrameStrata, list, "FULLSCREEN_DIALOG")
  pcall(list.SetFrameLevel, list, 1210)
  if type(list.EnableMouse) == "function" then pcall(list.EnableMouse, list, true) end
  local lbg = list:CreateTexture(nil, "BACKGROUND")
  lbg:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  lbg:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
  dfSolid(lbg, 0.03, 0.03, 0.03, 0.97)
  list.rows = {}
  local ly = -3
  for k = 1, table.getn(DF_ALPHA_PRESETS) do
    local rb = CreateFrame("Button", nil, list)
    rb:SetWidth(84) rb:SetHeight(22)
    pcall(rb.SetPoint, rb, "TOPLEFT", list, "TOPLEFT", 0, ly)
    if type(rb.EnableMouse) == "function" then pcall(rb.EnableMouse, rb, true) end
    if type(rb.RegisterForClicks) == "function" then pcall(rb.RegisterForClicks, rb, "LeftButtonUp") end
    local t2 = rb:CreateFontString(nil, "OVERLAY")
    if type(GameFontNormal) ~= "nil" then pcall(t2.SetFontObject, t2, GameFontNormal) end
    pcall(t2.SetPoint, t2, "CENTER", rb, "CENTER", 0, 0)
    rb.text = t2
    local idx = k
    rb:SetScript("OnClick", function()
      local row = list.dfOwner
      if not row then return end
      local v = row.opts[idx]
      if v == nil then return end
      row.value = v
      if row.btn and row.btn.label then
        local shown = v
        if v == "show" then shown = L("TB_LD_SHOW") elseif v == "hide" then shown = L("TB_LD_HIDE") end
        pcall(row.btn.label.SetText, row.btn.label, string.format(row.fmt, shown) .. " ▾")
      end
      pcall(list.Hide, list)
    end)
    table.insert(list.rows, rb)
    ly = ly - 24
  end
  list:Hide()
  p.list = list
  -- 取消 / 保存
  local cancel = dfBtn(root, 70, 18, L("BTN_CANCEL"))
  pcall(cancel.SetPoint, cancel, "BOTTOMLEFT", root, "BOTTOMLEFT", 26, 10)
  cancel:SetScript("OnClick", function() dfPopHide() end)
  p.cancel = cancel
  local save = dfBtn(root, 70, 18, L("TB_LD_SAVE"))
  pcall(save.SetPoint, save, "BOTTOMRIGHT", root, "BOTTOMRIGHT", -26, 10)
  p.save = save -- ★读值口要用真实控件走真实 OnClick（断言不复刻逻辑）
  save:SetScript("OnClick", function()
    local p2 = DF.pop
    if not p2 then return end
    local tgt, name = p2.target, p2.name
    -- ★★★1.74.33 按 **key** 取值（不再按下标）：被动窗口那两行被藏起来时，下标读法必然错位
    --   （藏了「宽」还按下标读第 4 行，读到的是别行——静默改错属性，本项目最恨的那种）。
    local function pick(k)
      local row = p2.rowBy and p2.rowBy[k]
      return row and row.value or nil
    end
    local vShow = pick("show")
    local vScale = pick("scale")
    local vAlpha = pick("alpha")
    -- ★★★1.75.1 宽/高**只对聊天窗**：非聊天窗**连读都不读**（「读了才去写」是这条约束的反面）；
    --   聊天窗读出来交给下面「先抓原始值 → 写新值 → 读回自证」那一段（与缩放/透明度同一口径）。
    local vW = p2.allowSize and pick("w") or nil
    local vH = p2.allowSize and pick("h") or nil
    if type(vW) ~= "number" then vW = nil end
    if type(vH) ~= "number" then vH = nil end
    -- X/Y = **绝对屏幕坐标**（用户选定）；没动过就保持 nil（不写、不固化）
    local vX = pick("x")
    local vY = pick("y")
    if type(vX) ~= "number" then vX = nil end
    if type(vY) ~= "number" then vY = nil end
    -- ★★★1.75.47 用户拍板**废掉「按现状入库」**（原 1.75.36b 聊天窗特殊处理：未选项按当前实测值入库）——
    --   它是「没设过自定义属性的层也进更新操作」的污染源：弹窗保存一次 ⇒ 坐标/宽高全入库 ⇒ 守卫候选全中。
    --   现在聊天窗与其它目标**同一口径：只写用户显式选择的项**；
    --   客户端自带拖拽摆出的位置由守卫按存档坐标拉回（位置唯一来源 = 我们的存档 / 方块拖动 / 弹窗显式 X/Y）。
    dfPopHide()
    if not tgt then return end
    if dfInCombat() then say("框拖拽：战斗中不改属性（客户端保护）") return end
    local done = {}
    if vShow == "show" then pcall(tgt.Show, tgt) table.insert(done, "显示")
    elseif vShow == "hide" then pcall(tgt.Hide, tgt) table.insert(done, "隐藏") end
    if vScale then pcall(tgt.SetScale, tgt, vScale) table.insert(done, string.format("缩放 %.2f", vScale)) end
    if vAlpha then pcall(tgt.SetAlpha, tgt, vAlpha) table.insert(done, string.format("透明 %.2f", vAlpha)) end
    -- ★1.74.33 宽/高已停用 ⇒ 这一段（读原值 + 写宽高 + 读回自证）整体删除；
    --   老记录里的宽高由 EVAL_DF_SIZE_CLEAN 在启动时清掉并还原原尺寸（那才是唯一该动尺寸的地方）。
    -- ★X/Y（绝对屏幕坐标）⇒ 换算成「相对记录基准的屏幕位移」再落锚：
    --   ★落锚**只走 `dfPlaceFrom`**（首猜按有效缩放折算 → 量回自证 → 手量折算修正）；
    --     绝不在算完坐标后直接 SetPoint（那就回到「把屏幕量当本地偏移用」的老坑，缩放≠1 必偏）。
    -- ★★★1.75.36l 方块目标：X/Y 直接就是**方块（绝对）坐标** ⇒ 写 ax/ay 再落方块，不再走 base/dx/dy
    local tgtRowXY = dfTgtOfName(name)
    if (vX or vY) and type(tgtRowXY) == "table" and tgtRowXY.block == true then
      local stXY = dfStore(true)
      local recXYB = (type(stXY) == "table") and stXY[name] or nil
      if type(recXYB) ~= "table" then recXYB = {} if type(stXY) == "table" then stXY[name] = recXYB end end
      local curAX, curAY = dfBlockGet(tgtRowXY)
      if (type(curAX) ~= "number" or type(curAY) ~= "number") and tgt then
        -- ★1.75.36n：没记录的目标（编辑模式那块「不落档」的方块）⇒ 现值 = 目标现状中心
        local flP, fbP, fwP, fhP = dfMeasure(tgt)
        if type(flP) == "number" and type(fbP) == "number" then
          curAX, curAY = flP + dfNum(fwP, 0) / 2, fbP + dfNum(fhP, 0) / 2
        end
      end
      local nbx = vX or curAX
      local nby = vY or curAY
      if type(nbx) == "number" and type(nby) == "number" then
        recXYB.ax, recXYB.ay = nbx, nby
        recXYB.axAuto = nil -- ★1.75.47：用户显式设的 X/Y = 自定义位置（清掉迁移标记）
        local okb = dfBlockApply(tgtRowXY)
        -- ★1.75.36n：ax/ay 的口径 = 目标**中心** ⇒ 读回自证也比中心（不再比左上角）
        local lNowB, bNowB, wNowB, hNowB = dfMeasure(tgt)
        local cxB = (lNowB and wNowB) and (lNowB + wNowB / 2) or nil
        local cyB = (bNowB and hNowB) and (bNowB + hNowB / 2) or nil
        if cxB and cyB and math.abs(cxB - nbx) <= 1.5 and math.abs(cyB - nby) <= 1.5 then
          table.insert(done, string.format("方块坐标 %.0f,%.0f（目标中心）", cxB, cyB))
        elseif okb then
          table.insert(done, "方块坐标已入库（读回没到位，下次应用时再试）")
        else
          table.insert(done, "方块没能落上（坐标已入库）")
        end
      else
        table.insert(done, "方块坐标读不到现值 ⇒ 本次没设（不猜位置）")
      end
    elseif (vX or vY) and type(name) == "string" and name ~= "" then
      local storeXY = dfStore(true)
      local recXY = (type(storeXY) == "table") and storeXY[name] or nil
      if type(recXY) ~= "table" then
        recXY = {}
        if type(storeXY) == "table" then storeXY[name] = recXY end
      end
      if type(recXY.base) ~= "table" then recXY.base = dfCapture(tgt) end -- 全新记录：当前锚点即基准
      local bXY = recXY.base
      if type(bXY) == "table" and (type(bXY.l) ~= "number" or type(bXY.b) ~= "number") then
        local bl2, bb2 = dfScreenBaseOf(tgt, bXY)   -- 老记录：先反推基准的屏幕位置
        if type(bl2) == "number" and type(bb2) == "number" then bXY.l, bXY.b = bl2, bb2 end
      end
      -- ★★★1.75.36k 相对锚点目标：位移要对着**现算基准**（`dfBaseLive`）算 —— 用户填的是**屏幕坐标**，
      --   而存的 `base.l/base.b` 是抓取那一刻的旧屏幕位置；父帧挪过之后拿旧值相减 ⇒ 设进去的坐标必偏。
      local bXYl, bXYb = (type(bXY) == "table") and bXY.l or nil, (type(bXY) == "table") and bXY.b or nil
      if type(bXY) == "table" and dfRelCap(bXY) then
        local lbl, lbb = dfBaseLive(tgt, bXY)
        if type(lbl) == "number" and type(lbb) == "number" then bXYl, bXYb = lbl, lbb end
      end
      if type(bXYl) == "number" and type(bXYb) == "number" then
        local curX = bXYl + dfNum(recXY.dx, 0)
        local curY = bXYb + dfNum(recXY.dy, 0)
        local nx = vX or curX
        local ny = vY or curY
        recXY.dx, recXY.dy = nx - bXYl, ny - bXYb
        recXY.cur = nil
        local okp = dfPlaceFrom(tgt, bXY, recXY.dx, recXY.dy)
        local lNow, bNow = dfMeasure(tgt)
        if lNow and bNow and math.abs(lNow - nx) <= 1.5 and math.abs(bNow - ny) <= 1.5 then
          table.insert(done, string.format("X/Y %.0f,%.0f", lNow, bNow))
        elseif okp then
          table.insert(done, string.format("X/Y 试过 %.0f,%.0f（读回 %s,%s ⇒ 没到位，可能被锚点撑着）",
            nx, ny, lNow and string.format("%.0f", lNow) or "?", bNow and string.format("%.0f", bNow) or "?"))
        else
          table.insert(done, "X/Y 没能落上（坐标已入库存档，下次应用时再试）")
        end
      else
        table.insert(done, "X/Y 读不到基准位置 ⇒ 本次没设（不猜位置）")
      end
    end

    -- ★★★1.75.1 宽/高（只对聊天窗）：**先抓原始值 → 再写新值 → 读回自证**；★顺序不许换 ——
    --   1.74.31 组 206 抓到过「在 SetWidth **之后**才读原值」⇒ 记下的是刚设进去的新值，重置等于没还原。
    if (vW or vH) and type(tgt) == "table" then
      local _, _, _, curW, curH = dfReadAttrs(tgt)
      local st0 = dfStore(true)
      local rec0 = (type(st0) == "table" and type(name) == "string") and st0[name] or nil
      if type(rec0) == "table" then
        if vW and type(rec0.ow) ~= "number" and type(curW) == "number" then rec0.ow = curW end
        if vH and type(rec0.oh) ~= "number" and type(curH) == "number" then rec0.oh = curH end
      end
      local okw = true
      if vW then okw = (type(tgt.SetWidth) == "function") and pcall(tgt.SetWidth, tgt, vW) end
      local okh = true
      if vH then okh = (type(tgt.SetHeight) == "function") and pcall(tgt.SetHeight, tgt, vH) end
      if vW and okw then table.insert(done, string.format("宽 %.0f", vW)) end
      if vH and okh then table.insert(done, string.format("高 %.0f", vH)) end
    end

    -- 写新存档（★只写用户真的选了的项）
    local store = dfStore(true)
    if store and type(name) == "string" and name ~= "" then
      local rec = store[name]
      if type(rec) ~= "table" then rec = {} store[name] = rec end
      if vScale then rec.scale = vScale end
      if vAlpha then rec.alpha = vAlpha end
      if vShow then rec.hidden = (vShow == "hide") end
      -- ★★★1.75.1 宽/高只对聊天窗：允许的目标**入库持久化**（用户要的「并且持久化」就是这个字段）；
      --   不允许的目标若老记录里还留着 w/h（1.74.33 之前存下的）⇒ **顺手清掉（自愈）并如实说明**，
      --   否则会一直挂着「用户以为设了、其实早被停用」的静默状态。
      if p2.allowSize then
        if vW then rec.w = vW end
        if vH then rec.h = vH end
      elseif rec.w ~= nil or rec.h ~= nil or rec.ow ~= nil or rec.oh ~= nil then
        rec.w, rec.h, rec.ow, rec.oh = nil, nil, nil, nil
        table.insert(done, "已清掉老的宽高设置（该窗口不许改宽高）")
      end
      -- ★★★1.75.36k 如实记：`done` 为空 = **什么都没保存**（用户只点了保存、没选任何一项）⇒
      --   旧写法照样打「属性已保存 …：」（后面空着）⇒ 真机取证时看着像「保存过了」，把排查带偏过一次。
      if table.getn(done) > 0 then
        dfLog("属性已保存 " .. name .. "：" .. table.concat(done, "/"))
      else
        dfLog("属性未保存（没选任何一项） " .. name)
      end
      -- ★★★1.75.109 **镜像：同一窗口的另一页也要落到帧上**（用户：「聊天窗设置属性的时候也要将战斗记录
      --   做相同的参数设定.这两个属于同个窗口同个位置」）。
      --   ★为什么记录共用了还要显式应用一次：**聊天框的守护只守坐标**（尺寸/属性一概不守 —— 1.75.36n
      --     用户定案）⇒ 缩放/透明度/宽高/显隐**不会自己追到另一页**，必须在这里补一次。
      --   ★复用**唯一应用公式 `dfApplyOne(tgt)`**（位置 + 属性一起），一行逻辑都不重写。
      --   ★未勾选的另一边**不跟设**（那是用户显式的「不管理」）—— 但**如实说出来**，绝不静默。
      local mirName = DF.mirrorOf[DF.storeKey(name)]
      if type(mirName) == "string" and mirName ~= name and table.getn(done) > 0 then
        local mt = dfTgtOfName(mirName)
        if mt then
          if dfPicked(mirName) then
            local okm = dfApplyOne(mt)
            table.insert(done, (okm and "同窗另一页（" or "同窗另一页（") .. tostring(mt.label or mirName) ..
              (okm and "）已一并设好" or "）这次没设成（见日志）"))
          else
            table.insert(done, "同窗另一页（" .. tostring(mt.label or mirName) .. "）**未勾选** ⇒ 没跟设")
          end
        end
      end
    end
    if table.getn(done) > 0 then
      say(string.format("已保存：%s → %s", tostring(p2.label or "?"), table.concat(done, " · ")))
    else
      say("未保存：没有选任何一项（点下拉选一个，或点取消）")
    end
  end)
  root:Hide()
  p.root = root
  DF.pop = p
  return true
end

dfCommitPop = function(target, label, name)
  if not dfPopBuild() then return false end
  local p = DF.pop
  if not p then return false end
  p.target, p.label, p.name = target, label, name
  if p.list then pcall(p.list.Hide, p.list) end
  -- 用当前值回填各行（回填只改显示；不选就不改）
  local vis = "show"
  if target and type(target.IsShown) == "function" then
    local ok, v = pcall(target.IsShown, target)
    if ok and v == false then vis = "hide" end
  end
  -- ★1.74.31 宽/高与缩放/透明度同一口径：现读目标的**当前**宽高回填（读不到写「?」）
  local sc, al, sh, w, h = dfReadAttrs(target)
  if sh == false then vis = "hide" end
  sc = sc or 1
  al = al or 1
  -- ★★★1.74.33 按 **key** 回填（不再按下标）；被动窗口**藏起「宽/高」两行**，改显示一行说明
  -- ★1.74.33 宽/高已经**整体停用**（行都不再创建）⇒ 弹窗 = 显隐 / 缩放 / 透明度 + **X/Y 坐标** 五行 + 一行说明
  -- ★★★1.75.1 宽/高：**只对聊天窗**给出这两行（真值 = 目标表项 `noSize`，由 `dfSizeOK` 现算）
  local tgtRow = dfTgtOfName(name)
  if type(tgtRow) == "table" then p.label2 = tgtRow.label end
  local allowSize = (type(tgtRow) == "table") and (tgtRow.noSize ~= true)
  p.allowSize = allowSize and true or false
  p.noSize = not allowSize
  for _, k in ipairs({ "w", "h" }) do
    local row = p.rowBy[k]
    if row then
      local cs = { row.btn, row.label }
      for ci = 1, table.getn(cs) do
        local c = cs[ci]
        if c then
          if allowSize then pcall(c.Show, c) else pcall(c.Hide, c) end
        end
      end
    end
  end
  pcall(p.root.SetHeight, p.root, allowSize and DF_POP_H_SIZE or DF_POP_H)
  -- X/Y 回填 = 目标**当前实测的屏幕位置**（X=左边缘、Y=下边缘）；★只回填显示、**不写 row.value**
  --   （写了就等于「用户没动过也会被保存」，那会把「客户端刚把它摆回去的错误位置」静默固化下来）
  local xNow, yNow, wNowD, hNowD = dfMeasure(target)
  -- ★1.75.36n：方块目标的 X/Y 口径 = 目标**中心**（保存写的就是 ax/ay 中心）⇒ 回填显示也用中心，
  --   免得「显示的数」和「存下去的数」不是一个东西
  if type(tgtRow) == "table" and tgtRow.block == true and type(xNow) == "number" and type(yNow) == "number" then
    xNow, yNow = xNow + dfNum(wNowD, 0) / 2, yNow + dfNum(hNowD, 0) / 2
  end
  for _, row in ipairs(p.rows) do
    local val, shown = nil, nil
    local k = row.key
    if k == "show" then val = vis shown = (vis == "show") and L("TB_LD_SHOW") or L("TB_LD_HIDE")
    elseif k == "scale" then val = sc shown = string.format("%.2f", sc)
    elseif k == "alpha" then val = al shown = string.format("%.2f", al)
    elseif k == "w" then shown = w and string.format("%.0f", w) or "?"
    elseif k == "h" then shown = h and string.format("%.0f", h) or "?"
    elseif k == "x" then row.cur = xNow shown = xNow and string.format("%.0f", xNow) or "?"
    else row.cur = yNow shown = yNow and string.format("%.0f", yNow) or "?" end
    row.value = nil
    if row.btn and row.btn.label then pcall(row.btn.label.SetText, row.btn.label, tostring(shown) .. " ▾") end
  end

  if p.title then pcall(p.title.SetText, p.title, "框拖拽 · " .. tostring(label or "")) end
  p.target = target
  local mode, info = dfPopPlace(p.root)
  DF.popMode, DF.popInfo = mode, info
  if p.cover then pcall(p.cover.Show, p.cover) end
  pcall(p.root.Show, p.root)
  if mode == "failed" then
    say("框拖拽：配置窗定位失败（锚点没落上）——请把 /edb dragrect 的数字发给我")
  end
  return true
end

-- ============ 拖拽柄 + 生命周期 ============
-- 自校准两个「不确定存在」的兜底 API（★绝不让一个恒返回假的实现把拖拽瞬间掐断）：
--   · IsMouseButtonDown：本客户端**没有**（见文件头证据）；若某天有了，也必须在「按下那一刻」返回真值才采信。
--   · GetMouseFocus：本客户端**有**；但只有在按下那一刻真的返回本柄时才采信「它变成别人 = 松手了」。
local function dfCalibrate(b)
  if DF.mouseDownOK == nil and type(IsMouseButtonDown) == "function" then
    local okd, down = pcall(IsMouseButtonDown, "LeftButton")
    DF.mouseDownSeen = okd and tostring(down) or ("ERR:" .. tostring(down))
    DF.mouseDownOK = (okd and (down == true or down == 1)) and true or false
    dfLog("IsMouseButtonDown 自校准：" .. tostring(DF.mouseDownOK) .. "（返回 " .. tostring(DF.mouseDownSeen) .. "）")
  end
  if DF.focusOK == nil and type(GetMouseFocus) == "function" then
    local okf, mf = pcall(GetMouseFocus)
    DF.focusSeen = okf and ((mf == b) and "本柄" or tostring(mf)) or ("ERR:" .. tostring(mf))
    DF.focusOK = (okf and mf == b) and true or false
    dfLog("GetMouseFocus 自校准：" .. tostring(DF.focusOK) .. "（返回 " .. tostring(DF.focusSeen) .. "）")
  end
end

local function dfDragBegin(b)
  if DF.dragging then return false end
  local fr = b.dfTarget
  if not fr then return false end
  if dfInCombat() then
    say("框拖拽：战斗中不可拖动（客户端保护），脱战后再试")
    return false
  end
  if type(GetCursorPosition) ~= "function" then return false end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and tonumber(cx) and tonumber(cy)) then return false end
  local cap = dfCapture(fr)
  if not cap then
    say("框拖拽：" .. tostring(b.dfLabel or "?") .. " 的锚点/几何读不出来，本次拖动放弃（不写半个记录）")
    return false
  end
  dfCalibrate(b)
  -- ★★★1.75.36l 方块拖动：基准 = **方块的绝对坐标**（不是目标的锚点四元组 —— 方块只认绝对坐标）
  local isBlock = (b.dfBlock == true)
  local bax0, bay0 = nil, nil
  if isBlock then
    local bt = dfTgtOfName(b.dfName)
    if bt then bax0, bay0 = dfBlockGet(bt) end
    if type(bax0) ~= "number" or type(bay0) ~= "number" then
      -- 兜底：还没方块/没记录就按目标现状**中心**（零位移迁移；★1.75.36n 起 ax/ay 的口径 = 中心）
      local fl0, fb0, fw0, fh0 = dfMeasure(fr)
      if type(fl0) == "number" and type(fb0) == "number" then
        bax0, bay0 = fl0 + dfNum(fw0, 0) / 2, fb0 + dfNum(fh0, 0) / 2
      end
    end
  end
  -- ★拖拽状态放在**模块自己的表**里（`DF.dragSt`），不挂在按钮对象上：
  --   ① 一次只可能有一个拖拽 → 单一真相更简单；
  --   ② 「读一个没设过的字段」在不同实现下语义不同（真机返回 nil，而宽容桩的 __index 会返回一个**真值函数**），
  --      挂在自己表上就永远不受这个歧义影响（本项目「桩太宽松」教训的另一面：别给歧义留位置）。
  DF.dragSt = {
    b = b, cx0 = cx, cy0 = cy, lastCx = cx, lastCy = cy,
    idle = 0, age = 0, cap = cap, moved = false,
    isBlock = isBlock, ax0 = bax0, ay0 = bay0,
  }
  DF.dragging = true
  DF.dragHandle = b
  DF.dragWhy = nil
  dfCatcherEnsure()
  dfCatcherShow(true)
  return true
end

-- ★★★1.75.101 共用件（[重置] 面板 / 全局重置 / 图标左键重置 三条路**都必须走它**，绝不许各写一份）：
--   ① `dfIsCustom(rec)` = 「这条记录算不算有自定义属性」的**唯一判定**（位置偏移 / 缩放 / 透明度 / 显隐 / 宽 / 高 之一）；
--      只剩 base/cur/legacy 这类内部痕迹的**不算**（重置后就只剩它们）。清单与面板两处共用同一份口径。
--   ② `dfCustomKeys(rec)` = 面板行右端那串「设了哪些项」（位置/缩放/透明度/显隐/宽高）。
--   ③ `dfResetBody(rec, fr, combat)` = **逐目标体重置**（全局 EVAL_DF_RESET / 选中 EVAL_DF_RESET_LIST / 图标左键 dfResetOne 共用）：
--      位置回基准 0 偏移（dfPlaceFrom）→ 清定位账（dx/dy/base/cur/ax/ay/axAuto）→ 缩放/透明度/显隐/宽高回原始值
--      （dfRestoreAttrs 自己清字段）→ 记录空了由调用方整条删。**顺序即判据**（见下面两条在案教训）。
--   ★★为什么要挂 `DF` 表而不是文件级 local：**主 chunk 局部量已到 200 上限**（本项目在案）—— 加一个 local 就整份载不进去。
-- ★★★1.75.107 **方块坐标 `ax/ay` 也算自定义位置**（真机上「移动了聊天窗，重置弹窗里却没有它」的真因）：
--   常驻层那 14 个（聊天框 ×2 / 头像 / 目标头像 / 小地图 / 底部条族 7 / 姿态条…）自 1.75.36l/n 起**位置一律走方块**
--   —— `dfDragUpdate` 的方块分支（`st.isBlock == true`）只往记录里写 `ax/ay`，**根本不写 `dx/dy`**（那条路是
--   `elseif` 的另一支，方块目标进不去）⇒ 旧判据只认 `dx/dy/scale/alpha/hidden/w/h` ⇒ **拖过聊天窗之后记录里
--   一个被认的字段都没有** ⇒ `EVAL_DF_CUSTOM_LIST` 不列它 / `EVAL_DF_SUMMARY` 也不把它算成自定义记录。
--   ★口径与**同一个仓库里的另外两处**完全同一把尺子（`dfGuardCandidates` 的聊天框那支、`dfGuardCustom` 尾行）：
--     `axAuto == true`（编辑模式「零位移迁移」自动盖的系统基准）**不算**；`axAuto` 被清掉（用户真拖过 / 显式设过）才算。
DF.blockPos = function(rec)
  if type(rec) ~= "table" then return false end
  return (rec.ax ~= nil or rec.ay ~= nil) and rec.axAuto ~= true
end
DF.isCustom = function(rec)
  if type(rec) ~= "table" then return false end
  if (rec.dx ~= nil) or (rec.dy ~= nil) or (rec.scale ~= nil)
    or (rec.alpha ~= nil) or (rec.hidden ~= nil) or (rec.w ~= nil) or (rec.h ~= nil) then
    return true
  end
  return DF.blockPos(rec)
end
DF.customKeys = function(rec)
  local out = {}
  if (rec.dx ~= nil) or (rec.dy ~= nil) or DF.blockPos(rec) then table.insert(out, L("TB_LD_SUM_POS")) end
  if rec.scale ~= nil then table.insert(out, L("TB_LD_SUM_SCALE")) end
  if rec.alpha ~= nil then table.insert(out, L("TB_LD_SUM_ALPHA")) end
  if rec.hidden ~= nil then table.insert(out, L("TB_LD_RST_SHOWHIDE")) end
  if (rec.w ~= nil) or (rec.h ~= nil) then table.insert(out, L("TB_LD_RST_SIZE")) end
  return out
end
DF.resetBody = function(rec, fr, combat)
  local did = {}
  local c = { pos = 0, scale = 0, alpha = 0, show = 0, w = 0, h = 0, whMiss = 0, skipped = 0, rest = 0 }
  -- ① 定位还原（**沿用既有的定位还原逻辑**：有 base 就按 base 平移回 0 偏移）
  if type(rec.base) == "table" and fr then
    if dfPlaceFrom(fr, rec.base, 0, 0) then
      c.pos = 1
      table.insert(did, L("TB_LD_SUM_POS"))
    end
  end
  -- 定位数据一律清掉
  rec.dx, rec.dy = nil, nil
  -- ★★1.75.52（用户报障「重置之后底部动作栏位置会自动偏移」）：`base`/`cur` 是**定位基准**（重置刚才就是拿 base 平移回 0 偏移）
  --   ⇒ 必须一起清，否则记录**永远不是空的** ⇒ 「记录清空 → 整条删除」轮不到它 ⇒ 重置后 dfBlockSync 每拍零位移迁移又把
  --   ax/ay 写回来、dfKeepTick 的方块分支见「没锚在方块上」就重新锚回方块（位置就飘了）。
  --   ★顺序即判据：这一行**必须在上面 `dfPlaceFrom(fr, rec.base, 0, 0)` 之后**（那是最后一次用 base）。
  rec.base, rec.cur = nil, nil
  -- ★★1.75.47 方块坐标**也要清**（只清 dx/dy ⇒ 方块目标的 ax/ay 留在记录里 = 「重置了没效果」）；
  --   清掉后下次编辑模式由「零位移迁移」以现状为基准重建（标 axAuto，不进守卫）—— 自洽。
  -- ★★★1.75.107：方块目标（聊天窗 / 常驻层）的位置**就存在 `ax/ay` 上**（没有 `base`/`dx/dy`）⇒ 清它就是
  --   「重置位置」，必须计入 `c.pos`/`did` —— 否则面板与图标左键都会读成「没有可还原的项」（又一次静默）。
  --   ★只在上面那条 `dfPlaceFrom` 没记过位置时补记（`c.pos == 0`）⇒ 绝不会把同一个目标数成两次。
  --   ★真正**回到客户端原生布局要 /reload**（接管时 `ClearAllPoints` 冲掉了原生锚点、原值没存 —— 1.75.47b
  --     那个确认窗就是干这个的）；这里如实记「位置」这一项，但不假装当场就能看见变化。
  if c.pos == 0 and (rec.ax ~= nil or rec.ay ~= nil) and rec.axAuto ~= true then
    c.pos = 1
    table.insert(did, L("TB_LD_SUM_POS"))
  end
  rec.ax, rec.ay, rec.axAuto = nil, nil, nil
  -- ② 缩放 / 透明度 / 显隐 / 宽 / 高：一起还原，并清掉记录字段
  local got, res = dfRestoreAttrs(fr, rec, combat)
  c.scale, c.alpha, c.show = res.scale, res.alpha, res.show
  c.w, c.h = (res.w or 0), (res.h or 0)
  c.whMiss, c.skipped = (res.whMiss or 0), (res.skipped or 0)
  for k = 1, table.getn(got) do table.insert(did, got[k]) end
  -- ③ 记录还剩几个字段（0 ⇒ 调用方整条删）
  local rest = 0
  for _ in pairs(rec) do rest = rest + 1 end
  c.rest = rest
  return did, c
end

-- ★★★左键点一下（不拖动）配置图标 = 重置这一个框的属性（用户 2026-10-06：「增加个左键点击重置对应框属性功能」）：
--   与全局 [重置]（EVAL_DF_RESET）的逐目标体**同一套步骤**、只作用于这一个目标：
--   位置回基准 0 偏移（dfPlaceFrom）→ 清定位账（dx/dy/base/cur/ax/ay/axAuto）→
--   缩放/透明度/显隐/宽高回原始值（dfRestoreAttrs 自己清字段）→ 记录空了就整条删。
--   ★分工（现行）：左键**拖动** = 移动窗口（照旧）· 左键**点一下**（不拖动）= **重置该框属性** · 右键 = 属性弹窗（照旧）。
--   ★为什么用 dfStore(false)：商店不存在 ⇒ 从来就没有过记录 ⇒ 如实说「无需重置」，一个字节都不建。
local function dfResetOne(name, label, fr)
  if dfInCombat() then
    say("框拖拽：战斗中不可重置（客户端保护），脱战后再点一次")
    return false
  end
  local store = dfStore(false)
  if not store then
    say("框拖拽：存档不可用，本次重置没做")
    return false
  end
  local rec = store[name]
  if type(rec) ~= "table" then
    say(string.format("框拖拽：%s 没有自定义记录，无需重置", tostring(label or name or "?")))
    return false
  end
  -- ★1.75.101：逐目标体走共用件 dfResetBody（与全局重置/选中重置**同一套步骤**，不再各写一份）
  local did, c = DF.resetBody(rec, fr, false)
  local res = { skipped = c.skipped, whMiss = c.whMiss }
  local rest = c.rest
  if rest == 0 then store[name] = nil end
  pcall(dfRefresh)
  local what = (table.getn(did) > 0) and table.concat(did, "+") or "没有可还原的项"
  local msg = string.format("框拖拽：已重置 %s（%s）", tostring(label or name or "?"), what)
  if res.skipped > 0 then msg = msg .. "；另有 " .. tostring(res.skipped) .. " 项没改成（目标读不到或接口不可用，记录已保留）" end
  if res.whMiss > 0 then msg = msg .. "；宽/高没有「原始值」记录，无法还原，字段保留" end
  if rest > 0 then msg = msg .. "；记录仍有字段（未整条删除）" end
  say(msg)
  dfLog("图标左键点击 = 重置：" .. tostring(name) .. " -> " .. what)
  return true
end

dfDragEnd = function(why)
  local b = DF.dragHandle
  local st = DF.dragSt
  if not (b and st) then
    DF.dragging = false
    DF.dragHandle = nil
    DF.dragSt = nil
    dfCatcherShow(false)
    return false
  end
  DF.dragSt = nil
  DF.dragging = false
  DF.dragHandle = nil
  DF.dragWhy = tostring(why or "?")
  dfCatcherShow(false)
  local fr = b.dfTarget
  local moved = (st.moved == true)
  -- ★★★分工（现行，2026-10-06 用户改口）：左键**点一下（不拖动）= 重置该框属性** · 左键**拖动** = 移动窗口 · **右键** = 属性弹窗。
  --   历史口径：1.74.33「窗口的拖拽使用图标…左键不要触发弹窗效果」⇒ 当时左键一律不弹属性窗、属性窗改挂右键（见 dfIconBuild 的 OnMouseUp）——
  --   「左键不弹窗」这条**仍然有效**（现在点一下 = 重置，不是弹窗），下面那段「点击判据只能走 st.moved」的机制注释照旧有效。
  --   ★原来的实现是在这里判「按下但没移动 = 点击 ⇒ 开弹窗」（理由见下），现在这条路整段撤掉；
  --     下面那段「真的松手就弹配置窗」也必须把图标排除（否则点一下照样弹，只是换了个分支弹）。
  --     整条柄（非图标目标）的行为**一点不变**。
  --   历史理由（保留，免得以后有人又把它加回来）：拖拽一开始 `dfDragBegin` 就 Show **全屏接盘**
  --   （level 800，高于任何窗口的图标）⇒ 松手那一刻的鼠标事件被接盘吃掉 ⇒ 图标自己的 OnClick 根本不会触发；
  --   所以「点击」这件事只能靠 `st.moved`（拖拽机制自己算的阈值，唯一真值）在收尾时判。
  --   ★★注意判据写法：**必须写 `b.dfIcon == true`，不许写真值判断 `if b.dfIcon then`** ——
  --     测试桩的帧 mock 对**未知键返回一个函数**（truthy）⇒ 真值判断会把**每一条普通拖拽柄**都当成图标
  --     （本轮实测：组 202「拖拽完成弹属性窗」当场被这条判据挡掉）。真机上它是 nil 才对，但判据不能靠这个巧合。
  if b.dfIcon == true and fr and not moved then
    b.dfClickHandled = true
    -- ★2026-10-06 用户改口（「增加个左键点击重置对应框属性功能」）：左键点一下（不拖动）= **重置该框属性**；
    --   历史口径「左键什么都不做（1.74.33）」被它取代；右键仍 = 属性弹窗（分工与 tooltip 三语同步）。
    dfResetOne(b.dfName, b.dfLabel, fr)
  end
  -- ★★★1.75.36l 方块拖动：坐标已经在拖动过程中写进 `rec.ax/ay`（目标锚在方块上会自动跟随）
  --   ⇒ 这里**不再**走 base/dx/dy 那套（两者口径不同，混写必乱），只如实落日志 + 播报。
  if fr and moved and b.dfBlock == true then
    local storeB = dfStore(true)
    local recB = (type(storeB) == "table") and storeB[b.dfName] or nil
    local axB = (type(recB) == "table") and dfNum(recB.ax, 0) or 0
    local ayB = (type(recB) == "table") and dfNum(recB.ay, 0) or 0
    dfLog("方块拖动结束 " .. tostring(b.dfName) .. "：ax=" .. string.format("%.1f", axB) .. " ay=" .. string.format("%.1f", ayB))
    -- ★1.75.109 镜像：聊天框两页是同一窗口 ⇒ 位置记录是**同一份**，另一页的方块下一拍自己跟过来
    --   （`dfBlockSync` 读的是同一条 `ax/ay`）—— 这里只如实说一句，不做第二套搬运。
    local mirB = DF.mirrorOf[DF.storeKey(b.dfName)]
    local mirSay = ""
    if type(mirB) == "string" and mirB ~= b.dfName then
      local mtB = dfTgtOfName(mirB)
      mirSay = "；同窗另一页（" .. tostring((mtB and mtB.label) or mirB) .. "）同步跟到同一位置"
    end
    say(string.format("框拖拽：%s 的定位方块已移到 %.0f,%.0f（目标按绝对坐标跟随%s）",
      tostring(b.dfLabel or b.dfName or "?"), axB, ayB, mirSay))
  elseif fr and moved then
    local store = dfStore(true)
    local fin = dfCapture(fr)
    if store and fin then
      local rec = store[b.dfName]
      if type(rec) ~= "table" then rec = {} store[b.dfName] = rec end
      if type(rec.base) ~= "table" or table.getn(rec.base) ~= table.getn(fin) then
        rec.base = st.cap        -- ★首次拖拽（或口径变了）：拖前实测锚点 = 原始锚点
        rec.legacy = nil
        rec.dx, rec.dy = 0, 0
      end
      -- ★★★1.74.31 修（用户：「某些拖拽会叠加额外的偏移量（头像/目标头像/小地图）」）
      --   真因：位移 = 拖后锚点 − 基准锚点，但**只比了锚点数量、没比锚点身份**（point/rel/relPoint）。
      --   这几个帧的首锚点口径会不同（客户端摆放 / 拖拽时首锚点变了）→ 相减把“尺寸差”当成位移。
      --   现在：口径不同 → **不相减**，把拖后实测锚点当作新基准（rec.cur）。
      -- ★★★1.74.33 更进一步：**新式基准（带实测屏幕位置 `base.l/base.b`）一律按屏幕差记位移** ——
      --   屏幕差与「锚点身份、偏移量单位、缩放」全都无关 ⇒ 这才是「拖一次记一次、绝不再叠加」的口径。
      --   老记录（没有实测屏幕位置）继续走上面的锚点相减（行为与以前一致，不假装能修）。
      local f0 = fin[1] or {}
      if type(rec.base.l) == "number" and type(rec.base.b) == "number" and type(fin.l) == "number" then
        rec.dx = fin.l - rec.base.l -- ★屏幕位移（含缩放后的真实位移，单位无关）
        rec.dy = fin.b - rec.base.b
        rec.cur = nil                 -- 屏幕口径下 rec.cur 这套「换基准」的补丁不再需要
        rec.legacy = nil
      else
        local b0 = rec.base[1] or {}
        local sameId = (b0[1] == f0[1])
          and ((b0[2] or "") == (f0[2] or ""))
          and ((b0[3] or "") == (f0[3] or ""))
        if not sameId then
          rec.cur = fin -- ★新基准 = 拖后实测锚点
          rec.dx, rec.dy = 0, 0
          dfLog("锚点口径不同 → 改用拖后实测锚点作为新基准（不相减）")
        else
          if type(rec.cur) ~= "table" or table.getn(rec.cur) ~= table.getn(fin) then rec.cur = rec.base end
          local c0 = rec.cur[1] or rec.base[1] or {}
          rec.dx = dfNum(f0[4], 0) - dfNum(c0[4], 0)
          rec.dy = dfNum(f0[5], 0) - dfNum(c0[5], 0)
        end
        -- ★★★1.74.33 「拖完下次打开位置不对」的根因之二：**老记录的屏幕基准永远补不上** ——
        --   `rec.base` 只在「锚点数变了」时才换新 ⇒ 升级前建的记录**永远**没有 base.l/base.b，
        --   于是新口径（按屏幕位移落锚）一辈子用不到它（用户真机存档里 4 条记录全是这种，KEEP 每次登录都报 drift）。
        --   这里在**拖拽结束时**把它补上：dx/dy 在两种口径下都是**屏幕位移**
        --   （老口径的 dx = Δ反算值 = Δ屏幕左边缘）⇒ 基准屏幕位置 = 拖后实测 − 本次位移（精确反推）。
        if type(fin.l) == "number" and type(fin.b) == "number" then
          rec.base.l, rec.base.b = fin.l - dfNum(rec.dx, 0), fin.b - dfNum(rec.dy, 0)
          rec.cur = nil
          rec.healed = true
          dfLog("老记录补上屏幕基准 " .. tostring(b.dfName) .. "：base.l=" .. string.format("%.1f", rec.base.l) ..
            " base.b=" .. string.format("%.1f", rec.base.b) .. "（dx/dy 即屏幕位移）")
        end
      end
      dfLog("拖拽结束 " .. tostring(b.dfName) .. "：dx=" .. string.format("%.1f", rec.dx) ..
        " dy=" .. string.format("%.1f", rec.dy) .. " why=" .. tostring(why) ..
        " k=" .. tostring(DF.lastK))
      -- ★实测系数 k ≠ 1 ⇒ 该窗口「偏移量 ≠ 屏幕单位」（多半是缩放 ≠ 1）——如实报出来，
      --   这正是「有些窗口会漂移」的根：老代码在 k≠1 时每次拖拽都会叠加一个固定偏移。
      local kMsg = ""
      if DF.lastK and math.abs(DF.lastK - 1) > 0.02 and DF.lastK > 0 then
        kMsg = string.format("（实测位移系数 %.2f，已按它折算 · 不再叠加）", DF.lastK)
      end
      say(string.format("框拖拽：%s 已保存（偏移 %+.0f,%+.0f）%s",
        tostring(b.dfLabel or b.dfName or "?"), rec.dx, rec.dy, kMsg))
    else
      say("框拖拽：位置读不回来，本次没有写存档（不写半个记录）")
    end
  end
  -- 只对「真的松手」弹配置窗（被隐藏/关掉/掉线这类收尾不弹，免得莫名其妙冒出来）
  -- ★★1.74.33：**图标形态整个排除**（用户：「左键不要触发弹窗效果」）—— 左键（点击/拖动）都不弹，
  --   属性窗只有右键一个入口。整条柄（非图标目标）仍是「松手即弹配置窗」的既有行为。
  --   ★判据同样写 `~= true`（见上面那段：桩对未知键返回函数，真值判断会误伤普通柄）。
  if fr and b.dfIcon ~= true and (why == "mouseup" or why == "catcher" or why == "dragstop" or why == "idle") then
    pcall(dfCommitPop, fr, b.dfLabel, b.dfName)
  elseif fr and moved then
    -- 没弹窗的收尾也补一次「按存档回位」，保证存档与屏幕一致
    dfKeepTick(true)
  end
  return true
end

-- 移动 + 结束判据（每帧）：参数 = 模块自己的拖拽状态（含 st.b = 被拖的柄）
local function dfDragUpdate(st, dt)
  if type(st) ~= "table" then return end
  local b = st.b
  if not b then return end
  -- ★兜底 A：IsMouseButtonDown（**只在自校准通过时**才采信；本客户端不存在 ⇒ 这条永远不启用）
  if DF.mouseDownOK == true and type(IsMouseButtonDown) == "function" then
    local okd, down = pcall(IsMouseButtonDown, "LeftButton")
    if okd and not down then
      dfDragEnd("mouseup")
      return
    end
  end
  -- ★兜底 B：GetMouseFocus（自校准通过时采信「焦点已经不是本柄/接盘了」）
  if DF.focusOK == true and type(GetMouseFocus) == "function" then
    local okf, mf = pcall(GetMouseFocus)
    if okf and mf ~= b and mf ~= DF.catcher then
      dfDragEnd("mouseup")
      return
    end
  end
  local fr = b.dfTarget
  if not fr then dfDragEnd("lost") return end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and tonumber(cx) and tonumber(cy)) then return end
  -- ★★★1.74.33：位移一律按**屏幕**算（**不除缩放**）——目标是「窗口在屏幕上 1:1 跟手」；
  --   「偏移量到底按屏幕还是帧本地解释」交给 `dfPlaceFrom` 的**实测系数**去反解，本项目不猜单位。
  --   （旧代码在这里 `(cx - st.cx0) / es`，在缩放 ≠ 1 的窗口上正是漂移的来源之一。）
  local totX = cx - st.cx0
  local totY = cy - st.cy0
  if math.abs(totX) > 0.5 or math.abs(totY) > 0.5 then st.moved = true end
  -- ★位移用「拖前实测屏幕位置 + 光标累计位移」重建，**不再每帧回读 GetPoint 的偏移**
  --   （本客户端 GetPoint 返回相对帧**名字字符串**、且偏移的 y 符号口径有歧义 —— 回读加增量会累积成镜像/漂移）
  --   ★位移没变就不重写锚点（ClearAllPoints+SetPoint 每帧无谓重写会闪）
  -- ★★★1.75.36l 方块拖动：只改方块的**绝对坐标**，目标因为锚在方块上会自己跟着走（不碰目标锚点）
  if st.isBlock == true then
    if (not st.appX) or math.abs(totX - st.appX) > 0.5 or math.abs(totY - st.appY) > 0.5 then
      local bt = dfTgtOfName(b.dfName)
      -- ★1.75.36n：拖动 = **第一次真写**（没记录就当场建 —— 编辑模式「没记录也给方块」不落档，真拖了才入库，
      --   与旧柄带模型「拖完才写」同口径）
      local store0 = dfStore(true)
      local rec0 = (type(store0) == "table") and store0[b.dfName] or nil
      if bt and type(store0) == "table" and type(st.ax0) == "number" and type(st.ay0) == "number" then
        if type(rec0) ~= "table" then rec0 = {} store0[b.dfName] = rec0 end
        rec0.ax, rec0.ay = st.ax0 + totX, st.ay0 + totY
        rec0.axAuto = nil   -- ★1.75.47：用户真拖了 = 自定义位置（清掉迁移标记，进守卫候选）
        if dfBlockApply(bt) then st.appX, st.appY = totX, totY end
      end
    end
    if math.abs(cx - st.lastCx) < 0.5 and math.abs(cy - st.lastCy) < 0.5 then
      st.idle = st.idle + dt
      if st.idle >= DF_DRAG_IDLE_END then dfDragEnd("idle") return end
    else
      st.idle = 0
    end
    st.lastCx, st.lastCy = cx, cy
    st.age = st.age + dt
    if st.age >= DF_DRAG_MAX then dfDragEnd("timeout") end
    return
  end
  if (not st.appX) or math.abs(totX - st.appX) > 0.5 or math.abs(totY - st.appY) > 0.5 then
    local okp, kk = dfPlaceFrom(fr, st.cap, totX, totY)
    if okp then
      st.appX, st.appY = totX, totY
      if kk then st.k, DF.lastK = kk, kk end
    end
  end
  -- ★兜底 C：指针长时间不动 → 当作已经松手（最后一道保险，绝不会让目标层永远跟着鼠标）
  if math.abs(cx - st.lastCx) < 0.5 and math.abs(cy - st.lastCy) < 0.5 then
    st.idle = st.idle + dt
    if st.idle >= DF_DRAG_IDLE_END then
      dfDragEnd("idle")
      return
    end
  else
    st.idle = 0
    st.lastCx, st.lastCy = cx, cy
  end
  st.age = st.age + dt
  if st.age >= DF_DRAG_MAX then dfDragEnd("timeout") end
end

-- ============ 图标形态：被动打开层（1.74.32 第 2 步）============
-- 用户确认的四条（1.74.32）：① 点图标 = 开该层**属性弹窗**（复用 dfCommitPop 那 5 行）；
--   ② **拖图标本身 = 拖窗口**（复用既有拖拽三件套与 dfDragBegin/Update/End，一行逻辑都不重写）；
--   ③ 图标**默认开**（面积小、不吃窗口点击 —— 这正是它敢默认开、而整条透明柄默认关的原因）；
--   ④ 图标**挂在目标窗口下面**（`CreateFrame("Button", nil, fr)`）。
-- ★★为什么父级要给目标窗口：本客户端的**父子可见性传播**可用（UnrealQuest 记录并实测：
--   `CreateFrame("Frame","pfMapTooltip", GameTooltip)` 那种「挂在别人窗口下、随它显隐」的写法在用）
--   ⇒ 图标随窗口开/关，**不必轮询显隐**（也就不会引入常驻周期任务）。
-- ★★层级：`SetFrameLevel(目标 level + 10)`（本项目配方：同 strata 内按 level 排先后；只设 strata 会被盖住）。
--   真机实测：这族窗口关闭时 lv=1、`CharacterFrame` 打开着时 lv=8 ⇒ 必须**现读**目标 level 再抬。
-- ★位置：贴窗口右上角内侧再往左让开原生关闭按钮（vanilla 那族窗口的关闭按钮就在右上角）。
local DF_ICON_SIZE = 20
-- ★★★1.74.33 **真机截图改口径**：图标原来的右边距是 34 —— 用户截图里「法术书」窗口的 **关闭按钮就在右上角**，
--   34 正好让「配」压在关闭按钮上（截图：红圈里两个控件叠在一起）。原注释写的是「要大于关闭按钮宽度」，
--   但 34 显然不够（关闭按钮连同它的点击区更宽）⇒ 抬到 **58**（图标右边缘离窗口右边界 58px：
--   关闭按钮按 40px 带宽算，还能留出 18px 间隙），图标横跨 [W−78, W−58]，标题栏中间的字不会被压到。
--   ★若某些窗口那一段还有别的东西（页签/装饰），下一次实机核对时按同一办法再挪 —— 这是**只能靠真机看**的量。
local DF_ICON_RIGHT = 58
-- ★★★1.74.33 用户第二次真机微调（截图 = 好友名单窗口：「窗口的属性打开图标可以再往下移动12像素」）：
--   原值 6 让 20×20 的图标**骑在窗口的上边框上**（上半截落在标题栏之外），看着像挂在窗口沿上；
--   ⇒ 下移 12 ⇒ **18**（图标纵向跨 [W 顶下 18, 38]，整块落进标题栏里）。
--   ★注意别和「头部拖拽带」搞混：带的右端 = W − DF_ICON_RIGHT − DF_ICON_SIZE ⇒ 带与图标**横向相邻不重叠**
--     （组 215③ 守这条），所以图标往下挪多少都不会被带盖住（两份控件同一套鼠标分工 `dfBindDragButton`）。
--   ★同族判据：组 212⑤c 验**性质**（上边距 ≥12），改这一个数字不会卡断言。
local DF_ICON_TOP = 13
local DF_ICON_LABEL = "配"  -- ★仅在宏图标取不到时退回的兜底文字（见 DF_ICON_MACRO）
-- ★★★1.74.33 用户要求：「窗口的拖拽使用图标 346 号宏图标，左键不要触发弹窗效果」。
--   · **图标 = 宏图标表第 346 号**：本客户端取宏图标纹理的**唯一合法入口**是
--     `GetNumMacroIcons()` / `GetMacroIconInfo(i)`（官方 API 索引里 Macro 分类共 8 个函数，
--     与「图标库」`IconBrowser.lua` 同一口径；磁盘上 `doc/图标路径清单.txt` 就是它导出的清单）。
--     ★**不写死纹理路径**（那是两处真值）：现场按号取，取不到就退回文字「配」——
--       宁可显示一个能看懂的汉字，也**绝不**静默变成一个空白方块（本项目静默失败族的老账）。
--   · **左键不再弹属性窗**（点击不弹、拖动也不弹）⇒ 属性弹窗改挂**右键**
--     （与「战斗信息UI 技能格：左键=动作 / 右键=配置弹窗」同一约定；左键留给拖窗口本身）。
local DF_ICON_MACRO = 346
local DF_ICONS_DEFAULT = true
-- ★★★1.74.33 用户要求（真机截图：任务窗口顶部那条红线）：「窗口拖拽的区域能否定位到 窗体头部红色部分?」
--   ⇒ 图标形态的窗口除了右上角那个小图标，**再挂一条「头部拖拽带」**：沿窗口顶部的一条**透明带**，
--     抓手落在头顶哪一段都能拖这个窗口（不必去瞄那 20×20 的小图标）。
--   ★右端**必须停在关闭按钮留空区之外**（带右端 = W − DF_ICON_RIGHT）：这一带最容易吃掉窗口自带的按钮
--     （本项目刚因为「图标压住关闭按钮」被用户截图抓过一次，别在拖拽带上再犯）。
--   ★左端让开 DF_HEAD_LEFT：左上角通常是头像/装饰，别真从 0 开始铺。
--   ★高度只盖标题条那一带（DF_HEAD_TOP..DF_HEAD_TOP+DF_HEAD_H），**不往下压**（下面往往是列表/页签/勾选框）。
--   ★★1.74.33 用户追加：「窗体拖拽透明层高度可以向下在延伸15px」⇒ 18 → **33**（给 15px 抓取余量：
--     标题条本身只有十几像素、鼠标略低一点就抓不到；**上沿不动**，只向下长）。
--     ★若某个窗口标题条下面紧挨着勾选框/按钮被这条带吃掉点击，就把那一层的带子单独再矮一点（按窗口调）。
local DF_HEAD_H = 33
local DF_HEAD_LEFT = 4
local DF_HEAD_TOP = 3
local DF_ICONS = {}         -- 目标名 → { b = 按钮, fr = 当时的帧对象 }

-- 图标开关（独立于主开关 `on`：主开关管那 12 个目标的**整条透明柄**，本开关管被动窗口的**小图标**）
local function dfIconsOn()
  local store = dfStore(false)
  if store and type(store.iconsOn) == "boolean" then return store.iconsOn and true or false end
  return DF_ICONS_DEFAULT
end

function EVAL_DF_ICONS_ENABLED() return dfIconsOn() end

-- 宏图标号 → 纹理路径（取不到就 nil，由调用方决定退路）。★索引越界**先用 GetNumMacroIcons 挡住**：
--   本客户端越界取是什么行为没有本地证据 ⇒ 不猜，直接当「取不到」处理（如实退回文字）。
local function dfMacroIconTex(idx)
  if type(idx) ~= "number" then return nil end
  if type(GetMacroIconInfo) ~= "function" then return nil end
  if type(GetNumMacroIcons) == "function" then
    local okn, n = pcall(GetNumMacroIcons)
    if okn and tonumber(n) and tonumber(idx) > tonumber(n) then return nil end
  end
  local ok, t = pcall(GetMacroIconInfo, idx)
  if ok and type(t) == "string" and t ~= "" then return t end
  return nil
end

-- 读值口：当前会解析成什么纹理（诊断 `/eh go 框体图标 状态` 与断言共用，**不复刻映射逻辑**）
function EVAL_DF_TEST_MACRO_TEX(idx) return dfMacroIconTex(idx) end

-- 脚本回调里的「鼠标键」解析（★★本项目已实测的写法，与 `tools/ConsumableHelper.lua` 的 `chMouseBtn` 同源）：
--   **本客户端脚本回调的参数形态不固定** —— `handler(self, button)` 时**第一个参数是 self（帧对象）**、
--   键在第 2 个；传统帧 API 还会把参数写进全局 `arg1/arg2`；测试里我们又直接 `pcall(handler, "RightButton")`。
--   ⇒ **四处都认**，取第一个像键名的字符串，兜底 `"LeftButton"`。
--   ★★★教训（1.74.33 真机：「右键点图标打不开配置」）：原来写成 `function(a1) if a1 == "RightButton"`，
--     `a1` 拿到的是 **self** ⇒ 判定永远不成立 ⇒ 右键分支一次都没跑过；而测试是 `pcall(handler,"RightButton")`
--     直接喂字符串，**照样全绿** ——「测试的调用形态 ≠ 客户端的调用形态」正是这类静默失效的根。
local function dfMouseBtn(a, b)
  return (type(a) == "string" and a) or (type(b) == "string" and b)
         or (type(arg1) == "string" and arg1) or "LeftButton"
end

-- ============ 「图标形态」的鼠标分工（**唯一实现**：图标本体与头部拖拽带共用这一份）============
-- 用户 1.74.33 定的分工：**左键只拖窗口（不弹属性窗）· 右键开属性弹窗**。
--   ★★`b.dfIcon = true` 是「这个控件属于**图标形态**」的标记 —— `dfDragEnd` 靠它决定「左键一律不弹属性窗」。
--     判据写法必须 `== true` / `~= true`（测试桩的帧 mock 对未知键返回**函数**，真值判断会把普通柄误判成图标）。
--   ★右键必须 `RegisterForClicks("LeftButtonUp", "RightButtonUp")`：只注册左键 ⇒ 右键事件永远到不了分派代码。
--   ★拖动一律走 dfDragBegin/Update/End 三件套（**绝不 SetMovable/StartMoving** —— 那是记录在案的崩溃路径）。
local function dfBindDragButton(b)
  b.dfIcon = true
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") end
  if type(b.RegisterForDrag) == "function" then pcall(b.RegisterForDrag, b, "LeftButton") end
  -- 右键 = 开属性弹窗（**唯一出口**；OnMouseUp 与 OnClick 两条路都调它 —— dfCommitPop 幂等，重复调无害）
  local function popup()
    if b.dfTarget then dfCommitPop(b.dfTarget, b.dfLabel, b.dfName) end
  end
  b:SetScript("OnMouseDown", function(a1, a2)
    -- ★右键**不启动拖拽**（右键是「开属性窗」，不是「拖窗口」）
    if dfMouseBtn(a1, a2) == "RightButton" then return end
    if DF.dragging then return end
    b.dfClickHandled = nil
    dfDragBegin(b)
  end)
  b:SetScript("OnMouseUp", function(a1, a2)
    if dfMouseBtn(a1, a2) == "RightButton" then popup() return end
    if DF.dragSt and DF.dragSt.b == b then dfDragEnd("mouseup") end
  end)
  b:SetScript("OnDragStart", function() if not DF.dragging then b.dfClickHandled = nil dfDragBegin(b) end end)
  b:SetScript("OnDragStop", function() if DF.dragSt and DF.dragSt.b == b then dfDragEnd("dragstop") end end)
  b:SetScript("OnUpdate", function()
    if not (DF.dragSt and DF.dragSt.b == b) then return end
    local dt = dfNum(arg1, 0.05)
    if dt <= 0 then dt = 0.05 end
    dfDragUpdate(DF.dragSt, dt)
  end)
  b:SetScript("OnHide", function()
    if DF.dragSt and DF.dragSt.b == b then dfDragEnd("hide") end
  end)
  -- 悬停说明：把**分工**直接写在控件上（用户看不到「怎么开属性窗」就会以为功能没了）
  b:SetScript("OnEnter", function()
    if b.dfHover then pcall(b.dfHover, true) end
    local tip = _G["GameTooltip"]
    if tip and type(tip.SetOwner) == "function" and type(tip.AddLine) == "function" then
      local t = b.dfTgt
      pcall(tip.SetOwner, tip, b, "ANCHOR_RIGHT")
      if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
      pcall(tip.AddLine, tip, tostring((t and t.label) or b.dfLabel or b.dfName or "?") .. "：" .. L("TB_LD_ICON_TIP_LINE1"),
        1, 0.85, 0.30)
      pcall(tip.AddLine, tip, L("TB_LD_ICON_TIP_LINE2"), 0.88, 0.88, 0.88)
      -- ★★★1.74.33 用户要求（截图：弹窗里那行说明与 取消/保存 重叠）：「可以将信息在外部触发图标 tooltip 内展示」
      --   ⇒ 宽高为什么停用、位置怎么调（X/Y 语义与微调步长）这些**说明性文字全部搬到 tooltip**，
      --     弹窗只管控件本身（五行 + 两个按钮），不再有任何说明文字 ⇒ 从结构上杜绝重叠。
      pcall(tip.AddLine, tip, L("TB_LD_NOSIZE_TIP"), 0.85, 0.85, 0.55)
      pcall(tip.AddLine, tip, L("TB_LD_XY_TIP_LINE1"), 0.85, 0.85, 0.55)
      pcall(tip.Show, tip)
    end
  end)
  b:SetScript("OnLeave", function()
    if b.dfHover then pcall(b.dfHover, false) end
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  -- ★右键的**第二条分派路**：项目既有约定是「右键在 `OnClick` 里分派」（技能格 / 一键喂食 / 骑乘都这么做，
  --   见 `EvalHelp.lua` 技能格那段与 `ConsumableHelper.chMouseBtn` 的注释）—— 这条**不能省**：
  --   本客户端究竟哪条路会来没有文档，两条都留着才稳（`popup` 幂等 ⇒ 两条都来也只开一次窗）。
  --   ★左键这条路仍然**什么都不做**（用户 1.74.33：「左键不要触发弹窗效果」）。
  b:SetScript("OnClick", function(a1, a2)
    -- ★★这里的判据必须写 `== true`：从帧对象上读**布尔标记**时，测试桩对未知键返回**函数**（truthy）
    --   ⇒ 写真值判断会让「没处理过」被当成「已处理」而**提前 return**，右键这条路在测试里永远走不到
    --   （组 216① 当场抓到；与 `b.dfIcon == true` 是同一条纪律）。
    if b.dfClickHandled == true then b.dfClickHandled = nil return end
    if dfMouseBtn(a1, a2) == "RightButton" then popup() end
  end)
  return b
end

local function dfIconBuild(tgt, fr)
  local b = CreateFrame("Button", nil, fr) -- ★父级 = 目标窗口（父子可见性传播，见上）
  dfBindDragButton(b)
  b.dfTgt = tgt
  pcall(b.SetWidth, b, DF_ICON_SIZE)
  pcall(b.SetHeight, b, DF_ICON_SIZE)
  local tex = b:CreateTexture(nil, "BACKGROUND")
  dfSolid(tex, 0.15, 0.45, 0.9, 0.62)
  pcall(tex.SetPoint, tex, "TOPLEFT", b, "TOPLEFT", 0, 0)
  pcall(tex.SetPoint, tex, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.dfTex = tex
  b.dfHover = function(on)
    if b.dfTex then pcall(b.dfTex.SetVertexColor, b.dfTex, 0.15, 0.45, 0.9, on and 0.9 or 0.62) end
  end
  -- 图标本体：**346 号宏图标**（用户指定）；取不到 → 退回文字「配」（两条路都在这里定，别处不许再判一次）
  local art = dfMacroIconTex(DF_ICON_MACRO)
  b.dfArt = art
  if art then
    local ic = b:CreateTexture(nil, "ARTWORK")
    pcall(ic.SetTexture, ic, art)
    pcall(ic.SetPoint, ic, "TOPLEFT", b, "TOPLEFT", 0, 0)
    pcall(ic.SetPoint, ic, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.dfArtTex = ic
  else
    local lab = b:CreateFontString(nil, "OVERLAY")
    if type(GameFontNormalSmall) ~= "nil" then pcall(lab.SetFontObject, lab, GameFontNormalSmall)
    elseif type(GameFontNormal) ~= "nil" then pcall(lab.SetFontObject, lab, GameFontNormal) end
    pcall(lab.SetPoint, lab, "CENTER", b, "CENTER", 0, 0)
    pcall(lab.SetJustifyH, lab, "CENTER")
    pcall(lab.SetTextColor, lab, 1, 0.95, 0.8)
    pcall(lab.SetText, lab, DF_ICON_LABEL)
    b.dfLabel2 = lab
  end
  return b
end

-- 头部拖拽带：**透明**（窗口自己的标题条就是可见的「抓手」提示）· 只盖标题那一带 · 右端让开关闭按钮。
--   ★悬停给一点点高亮（alpha 0 → 0.10）：不然用户根本不知道这一带有东西可抓。
local function dfHeadBuild(tgt, fr)
  local b = CreateFrame("Button", nil, fr)
  dfBindDragButton(b)
  b.dfTgt = tgt
  pcall(b.SetHeight, b, DF_HEAD_H)
  local tex = b:CreateTexture(nil, "BACKGROUND")
  dfSolid(tex, 0.85, 0.85, 0.95, 0)
  pcall(tex.SetPoint, tex, "TOPLEFT", b, "TOPLEFT", 0, 0)
  pcall(tex.SetPoint, tex, "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.dfTex = tex
  b.dfHover = function(on) pcall(tex.SetAlpha, tex, on and 0.10 or 0) end
  return b
end


local function dfIconEnsure(tgt, fr)
  if type(tgt) ~= "table" or not fr or type(CreateFrame) ~= "function" then return nil end
  local rec = DF_ICONS[tgt.name]
  -- ★帧被重建过（惰加载窗口关掉再开、客户端换了实现）⇒ 旧图标跟着旧帧一起作废，重建一个
  if rec and rec.fr ~= fr then
    if rec.b then pcall(rec.b.Hide, rec.b) end
    if rec.head then pcall(rec.head.Hide, rec.head) end
    DF_ICONS[tgt.name] = nil
    rec = nil
  end
  local b = rec and rec.b
  if not b then
    b = dfIconBuild(tgt, fr)
    DF_ICONS[tgt.name] = { b = b, fr = fr }
    rec = DF_ICONS[tgt.name]
  end
  b.dfTarget, b.dfName, b.dfLabel = fr, tgt.name, tgt.label
  -- 层级：现读目标 level 再 +10（关闭的窗口 lv=1、打开着的可能到 lv=8，写死会盖不住）
  local lvl = 1
  if type(fr.GetFrameLevel) == "function" then
    local ok, v = pcall(fr.GetFrameLevel, fr)
    if ok and tonumber(v) then lvl = tonumber(v) end
  end
  pcall(b.SetFrameLevel, b, lvl + 10)
  pcall(b.ClearAllPoints, b)
  local okp = pcall(b.SetPoint, b, "TOPRIGHT", fr, "TOPRIGHT", -DF_ICON_RIGHT, -DF_ICON_TOP)
  if not okp then pcall(b.SetPoint, b, "CENTER", fr, "CENTER", 0, 0) end
  pcall(b.Show, b)

  -- ===== 头部拖拽带（用户 1.74.33：「窗口拖拽的区域能否定位到 窗体头部红色部分?」）=====
  -- 位置：贴窗口左上角、只盖标题那一带；宽度 = 窗口宽 − 左让开 − **关闭按钮留空区**（右端绝不越过去）。
  -- ★窗口宽每次现读（不同窗口宽度不一样，且用户可能改过宽），所以这里每次都重算并重锚。
  local h = rec and rec.head
  if not h then
    h = dfHeadBuild(tgt, fr)
    if rec then rec.head = h end
  end
  if h then
    h.dfTarget, h.dfName, h.dfLabel = fr, tgt.name, tgt.label
    local w = 0
    if type(fr.GetWidth) == "function" then
      local okw, v = pcall(fr.GetWidth, fr)
      if okw and tonumber(v) then w = tonumber(v) end
    end
    -- ★宽度 = 窗口宽 − 左让开 − **关闭按钮留空区** − **图标自身宽度**。
    --   ★★最后那一项是**断言当场抓出来的**（组 215③）：只减掉留空区时，带的右端正好落在图标右边界上
    --     ⇒ 带把 20×20 的图标整块盖住、**右键点不到图标**（与「[设置]/[重置] 同锚」是同一类遮挡事故）。
    local hw = w - DF_HEAD_LEFT - DF_ICON_RIGHT - DF_ICON_SIZE
    if hw < 40 then hw = 40 end -- 读不到/窗口极窄时的兜底：宁可窄，也不压关闭按钮与图标
    if w > 0 and hw > (w - DF_ICON_RIGHT - DF_ICON_SIZE) then hw = w - DF_ICON_RIGHT - DF_ICON_SIZE end
    if hw < 20 then hw = 20 end
    pcall(h.SetWidth, h, hw)
    pcall(h.SetHeight, h, DF_HEAD_H)
    pcall(h.SetFrameLevel, h, lvl + 10)
    pcall(h.ClearAllPoints, h)
    local okh = pcall(h.SetPoint, h, "TOPLEFT", fr, "TOPLEFT", DF_HEAD_LEFT, -DF_HEAD_TOP)
    if not okh then pcall(h.SetPoint, h, "TOPLEFT", fr, "TOPLEFT", 0, 0) end
    pcall(h.Show, h)
  end
  return b
end

local function dfIconsRefresh()
  local on = dfIconsOn()
  local n = 0
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    -- ★1.74.33：未勾选的窗口**不挂图标**（「选中的才开启配置」——图标就是开属性弹窗的入口）
    if tgt.icon and dfPicked(tgt.name) then
      local fr = dfTargetFrame(tgt)
      if on and fr then
        if dfIconEnsure(tgt, fr) then n = n + 1 end
      end
    end
  end
  -- 收起来的两种情形：① 总开关关掉；② 这一层**被取消勾选**（可能是这次刚取消的 ⇒ 必须立刻收掉）。
  --   ★**不销毁**：再打开开关/再勾上时接着用（父子传播负责随窗口显隐）；`dfIconEnsure` 每次都 Show，
  --     所以「收起来再打开」不会留下一个永远不显示的图标。
  --   ★头部拖拽带**跟着一起收**（它与图标是同一层的能力，只收一个会留下一条「看不见但吃点击」的带子）。
  for k, rc in pairs(DF_ICONS) do
    if (not on) or (not dfPicked(k)) then
      if rc.b then pcall(rc.b.Hide, rc.b) end
      if rc.head then pcall(rc.head.Hide, rc.head) end
    end
  end
  DF.iconN = n
  -- ★1.74.33 A：被动窗口的「打开即重设」链同样每次刷新同步一遍
  --   条件 = 主开关 + 该层被勾选（与图标显隐开关**无关**：关了图标也照样该重设属性）
  pcall(dfOpenHooksSync, DF.on and true or false)
  return n
end

function EVAL_DF_ICONS_SET(on)
  local store = dfStore(true)
  if store then store.iconsOn = on and true or false end
  local n = dfIconsRefresh()
  say("被动窗口图标 = " .. (dfIconsOn() and "开" or "关") .. "（已挂上 " .. tostring(n) .. " 个窗口）")
  return true
end

local function dfIconsToggle()
  return EVAL_DF_ICONS_SET(not dfIconsOn())
end

local function dfHandle(i)
  local b = DF.handles[i]
  if b then return b end
  b = CreateFrame("Button", nil, dfHost())
  pcall(b.SetFrameStrata, b, "FULLSCREEN_DIALOG")
  pcall(b.SetFrameLevel, b, 450) -- ★低于面板(500)：重叠时面板优先
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  -- ★三件套（本项目 UI 配方第 1 条）：Button 柄 + RegisterForClicks + RegisterForDrag
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  if type(b.RegisterForDrag) == "function" then pcall(b.RegisterForDrag, b, "LeftButton") end
  local tex = b:CreateTexture(nil, "BACKGROUND")
  dfSolid(tex, 0.15, 0.45, 0.9, 0.38)
  tex:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  tex:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  b.dfTex = tex
  local lab = b:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(lab.SetFontObject, lab, GameFontNormal) end
  pcall(lab.SetPoint, lab, "CENTER", b, "CENTER", 0, 0)
  pcall(lab.SetJustifyH, lab, "CENTER")
  pcall(lab.SetTextColor, lab, 1, 0.95, 0.8)
  b.dfLabel2 = lab
  -- 拖动 = **纯 SetPoint**（绝不用 SetMovable/StartMoving：用户实测那条路会把客户端弄崩，已明令禁止）
  b:SetScript("OnMouseDown", function()
    if DF.dragging then return end
    dfDragBegin(b)
  end)
  b:SetScript("OnMouseUp", function()
    if DF.dragSt and DF.dragSt.b == b then dfDragEnd("mouseup") end
  end)
  -- ★兜底 D：RegisterForDrag 的 OnDragStop。真机语义未实测（UnrealQuest 记录：拖动要在 SetMovable+StartMoving 的
  --   配方下才收得到 OnDragStart）→ 这里**只当额外的一层**：收得到就多一条结束路径，收不到也不影响其它兜底。
  --   ★绝不因为这一层去调 SetMovable/StartMoving（受保护帧上那是崩溃路径）。
  b:SetScript("OnDragStart", function() if not DF.dragging then dfDragBegin(b) end end)
  b:SetScript("OnDragStop", function() if DF.dragSt and DF.dragSt.b == b then dfDragEnd("dragstop") end end)
  b:SetScript("OnUpdate", function()
    if not (DF.dragSt and DF.dragSt.b == b) then return end
    local dt = dfNum(arg1, 0.05)
    if dt <= 0 then dt = 0.05 end
    dfDragUpdate(DF.dragSt, dt)
  end)
  b:SetScript("OnHide", function()
    if DF.dragSt and DF.dragSt.b == b then dfDragEnd("hide") end
  end)
  b:SetScript("OnEnter", function()
    if b.dfTex then pcall(b.dfTex.SetVertexColor, b.dfTex, 0.15, 0.45, 0.9, 0.62) end
  end)
  b:SetScript("OnLeave", function()
    if b.dfTex then pcall(b.dfTex.SetVertexColor, b.dfTex, 0.15, 0.45, 0.9, 0.38) end
  end)
  DF.handles[i] = b
  return b
end

-- ============ ★★★1.75.36l 「定位方块」= 每层的**绝对基准**（用户定稿）============
-- 用户原话：「能否给每个自定义图层都在最外层加一个锚点.编辑方案定位方块透明图层显示.颜色区分,显示标题,
--   然后所有自定义图层守护就以这个定位方块的绝对坐标进行后期更新守护?」+「1.取代〔旧的 20px 柄带〕2.先验证〔先底部条族〕」。
-- 机制（三层）：
--   UIParent（最外层，客户端**不会**重排它）
--     └── 方块 EVAL_DF_ANCHOR_<目标名>（挂 WorldFrame，但**只认 UIParent 的绝对坐标** ax/ay）
--           └── 目标层 SetPoint("CENTER", 方块, "CENTER", 0, 0)（**接管锚点**：从此只跟方块走；★1.75.36n 起 ax/ay = 目标**中心**）
-- ★为什么这样最稳：方块只认绝对坐标 ⇒ 客户端重排底部条族（`MainMenuBar`/`ActionButton1` 那一族）动不到它 ⇒
--   「旧世界坐标 / 互锚链层层叠加 / 屏幕 vs 本地单位」三个坑**一次消失**；守护只剩一句话：目标屏位 == 方块屏位。
-- ★★零位移迁移：记录里还没有 `ax/ay` 时，第一次就以**目标当前实测位置**为基准（升级不改版式、不跳一下）。
-- ★旧柄带**保留**给其它目标（`t.block ~= true`）；`block = true` 的目标改用方块（用户定的「取代」）。
-- ★只有 `DF.on`（编辑模式）才显示 / 可拖；守护模式只留坐标继续守护（方块隐藏 = 不吃鼠标）。
-- ★用 `do ... end` 圈起来：主 chunk 有 **200 局部变量上限**，这一段的自建局部量一进块就占槽位，
--   出块即释放（本项目已因这条上限红过一次：`too many local variables (limit is 200)`）。
do
local DF_BLOCK_SIZE = 20
-- 每层一个色（同一个色板循环）⇒ 屏幕上一眼分清谁是谁；边框用**分组色**（常驻层蓝/队伍团队绿/窗口图标金）
local DF_BLOCK_PAL = {
  { 0.25, 0.60, 1.00 }, { 0.30, 0.85, 0.45 }, { 1.00, 0.72, 0.22 }, { 0.95, 0.45, 0.30 },
  { 0.70, 0.52, 1.00 }, { 0.30, 0.85, 0.85 }, { 1.00, 0.45, 0.75 }, { 0.85, 0.85, 0.35 },
}
local function dfBlockGroupRGB(t)
  if type(t) ~= "table" then return 0.15, 0.45, 0.90 end
  if t.icon then return 0.88, 0.70, 0.25 end
  if t.roster then return 0.25, 0.72, 0.40 end
  return 0.15, 0.45, 0.90
end
-- 目标在 DF_TARGETS 里的序号（配色用；找不到按 1）
local function dfBlockIdx(name)
  for i = 1, table.getn(DF_TARGETS) do if DF_TARGETS[i].name == name then return i end end
  return 1
end
local function dfBlockOf(name)
  if type(name) ~= "string" or name == "" then return nil end
  DF.blocks = DF.blocks or {}
  return DF.blocks[name]
end
-- 建方块（首用才建）。★必须**具名**：`dfCapture` 要把「锚在谁身上」读回来，判据才能钉住
local function dfBlockEnsure(t)
  if type(t) ~= "table" or type(CreateFrame) ~= "function" then return nil end
  local bl = dfBlockOf(t.name)
  if bl then
    if bl.dfLabel2 then pcall(bl.dfLabel2.SetText, bl.dfLabel2, t.label) end
    return bl
  end
  bl = CreateFrame("Button", "EVAL_DF_ANCHOR_" .. tostring(t.name), dfHost())
  bl.dfAnchName = "EVAL_DF_ANCHOR_" .. tostring(t.name)
  bl.dfBlock = true
  bl.dfName = t.name
  pcall(bl.SetWidth, bl, DF_BLOCK_SIZE)
  pcall(bl.SetHeight, bl, DF_BLOCK_SIZE)
  pcall(bl.SetFrameStrata, bl, "FULLSCREEN_DIALOG")
  pcall(bl.SetFrameLevel, bl, 455) -- 略高于柄带(450)、低于面板(500)
  if type(bl.EnableMouse) == "function" then pcall(bl.EnableMouse, bl, true) end
  if type(bl.RegisterForClicks) == "function" then pcall(bl.RegisterForClicks, bl, "LeftButtonUp", "RightButtonUp") end
  if type(bl.RegisterForDrag) == "function" then pcall(bl.RegisterForDrag, bl, "LeftButton") end
  -- 边框（分组色）+ 填充（本层色、半透明 = 用户要的「透明图层」）
  local gb = bl:CreateTexture(nil, "BACKGROUND")
  pcall(gb.SetPoint, gb, "TOPLEFT", bl, "TOPLEFT", 0, 0)
  pcall(gb.SetPoint, gb, "BOTTOMRIGHT", bl, "BOTTOMRIGHT", 0, 0)
  local gr, gg, gb2 = dfBlockGroupRGB(t)
  dfSolid(gb, gr, gg, gb2, 0.85)
  bl.dfBorder = gb
  local tex = bl:CreateTexture(nil, "ARTWORK")
  pcall(tex.SetPoint, tex, "TOPLEFT", bl, "TOPLEFT", 1, -1)
  pcall(tex.SetPoint, tex, "BOTTOMRIGHT", bl, "BOTTOMRIGHT", -1, 1)
  local pal = DF_BLOCK_PAL[((dfBlockIdx(t.name) - 1) % table.getn(DF_BLOCK_PAL)) + 1]
  bl.dfRGB = pal
  dfSolid(tex, pal[1], pal[2], pal[3], 0.8) -- ★1.75.36n 用户：「方块透明度0.8」（填充 0.8；悬停 1.0 / 离开回 0.8）
  bl.dfTex = tex
  local lab = bl:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(lab.SetFontObject, lab, GameFontNormal) end
  pcall(lab.SetPoint, lab, "LEFT", bl, "RIGHT", 4, 0)
  pcall(lab.SetJustifyH, lab, "LEFT")
  pcall(lab.SetTextColor, lab, 1, 0.96, 0.82)
  pcall(lab.SetText, lab, tostring(t.label or t.name))
  bl.dfLabel2 = lab
  -- 左键拖 = 只挪方块（目标锚在方块上会跟着走）；右键 = 属性弹窗（与柄带同一入口）
  bl:SetScript("OnMouseDown", function() if not DF.dragging then dfDragBegin(bl) end end)
  bl:SetScript("OnMouseUp", function()
    if DF.dragSt and DF.dragSt.b == bl then dfDragEnd("mouseup") return end
    -- 不是拖拽 ⇒ 当点击：右键开属性弹窗（左键留给拖动）
    if type(arg1) == "string" and arg1 == "RightButton" then
      if type(dfCommitPop) == "function" then pcall(dfCommitPop, bl.dfTarget, t.label, t.name) end
    end
  end)
  bl:SetScript("OnDragStart", function() if not DF.dragging then dfDragBegin(bl) end end)
  bl:SetScript("OnDragStop", function() if DF.dragSt and DF.dragSt.b == bl then dfDragEnd("dragstop") end end)
  bl:SetScript("OnUpdate", function()
    if not (DF.dragSt and DF.dragSt.b == bl) then return end
    local dt = dfNum(arg1, 0.05)
    if dt <= 0 then dt = 0.05 end
    dfDragUpdate(DF.dragSt, dt)
  end)
  bl:SetScript("OnHide", function()
    if DF.dragSt and DF.dragSt.b == bl then dfDragEnd("hide") end
  end)
  bl:SetScript("OnEnter", function() if bl.dfTex then pcall(bl.dfTex.SetVertexColor, bl.dfTex, pal[1], pal[2], pal[3], 1.0) end end)
  bl:SetScript("OnLeave", function() if bl.dfTex then pcall(bl.dfTex.SetVertexColor, bl.dfTex, pal[1], pal[2], pal[3], 0.8) end end)
  bl:Hide()
  DF.blocks[t.name] = bl
  return bl
end
-- ★方块坐标 ax/ay = 目标层的**中心**绝对屏位（1.75.36n 用户：「定位在目标层中心位置」）；
--   没有记录就以目标现在的中心为基准（零位移迁移）。★锚法 CENTER ← CENTER ⇒ **与缩放无关**，不用除有效缩放。
local function dfBlockPos(fr, rec)
  if type(rec) ~= "table" or not fr then return nil end
  if type(rec.ax) ~= "number" or type(rec.ay) ~= "number" then
    local l, b, w, h = dfMeasure(fr)
    if type(l) ~= "number" or type(b) ~= "number" then return nil end
    rec.ax, rec.ay = l + dfNum(w, 0) / 2, b + dfNum(h, 0) / 2
    -- ★★1.75.47 axAuto（迁移基准标记）的**判定口径**：只有「记录里本来就没有任何自定义痕迹」的迁移
    --   才标 —— 那种位置是**系统看到它时它就在那**（客户端版式），不是用户摆的 ⇒ 不进守卫/更新。
    --   ★有 dx/dy **字段**（哪怕值是 0）= 拖拽流程写过（dfDragEnd 只在真拖了才写）⇒ 用户自定义，
    --     **不标**（否则把「用户真拖过的层」移出守卫 = 回归）；scale/alpha/hidden/w/h 同理（只能显式设）。
    local hadCustom = rec.dx ~= nil or rec.dy ~= nil
      or rec.scale ~= nil or rec.alpha ~= nil or rec.hidden ~= nil
      or rec.w ~= nil or rec.h ~= nil
    if not hadCustom then rec.axAuto = true end
  end
  return rec.ax, rec.ay
end
-- 读当前方块坐标（没有就以目标现状为基准；返回 ax, ay 或 nil）——给拖动/对话框用
dfBlockGet = function(t)
  if type(t) ~= "table" then return nil end
  local store = dfStore(false)
  local rec = (type(store) == "table") and store[t.name] or nil
  local fr = dfTargetFrame(t)
  if type(rec) ~= "table" or not fr then return nil end
  local ax, ay = dfBlockPos(fr, rec)
  if type(ax) ~= "number" or type(ay) ~= "number" then return nil end
  return ax, ay
end
-- 「已经锚在方块上、且目标**中心**就在方块坐标上」（唯一判据；1px；★1.75.36n 起 ax/ay = 中心口径）
local function dfBlockAt(fr, bl, rec)
  if not fr or not bl or type(rec) ~= "table" then return false end
  local l, b, w, h = dfMeasure(fr)
  if not l or not b then return false end
  local cx, cy = l + dfNum(w, 0) / 2, b + dfNum(h, 0) / 2
  if math.abs(cx - (tonumber(rec.ax) or -1e9)) > 1 or math.abs(cy - (tonumber(rec.ay) or -1e9)) > 1 then dfLog("BLOCKAT pos " .. tostring(cx) .. "," .. tostring(cy) .. " vs " .. tostring(rec.ax) .. "," .. tostring(rec.ay)) return false end
  local cap = dfCapture(fr)
  local a = (type(cap) == "table") and cap[1] or nil
  if type(a) ~= "table" then dfLog("BLOCKAT nocapline") return false end
  if a[1] ~= "CENTER" or a[2] ~= bl.dfAnchName or a[3] ~= "CENTER" then dfLog("BLOCKAT anchor " .. tostring(a[1]) .. "/" .. tostring(a[2]) .. "/" .. tostring(a[3]) .. " want CENTER/" .. tostring(bl.dfAnchName) .. "/CENTER") return false end
  if math.abs(dfNum(a[4], 0)) > 1 or math.abs(dfNum(a[5], 0)) > 1 then
    dfLog("BLOCKAT 没到位：锚点偏移实测 " .. tostring(a[4]) .. "," .. tostring(a[5]) .. "（应为 0,0）")
    return false
  end
  return true
end
-- 摆方块 + 把目标**锚到方块上**（唯一落点；位置与锚点身份一次写全）
dfBlockApply = function(t)
  if type(t) ~= "table" then return false end
  local store = dfStore(false)
  local rec = (type(store) == "table") and store[t.name] or nil
  local fr = dfTargetFrame(t)
  if type(rec) ~= "table" or not fr then return false end
  local ax, ay = dfBlockPos(fr, rec)
  if type(ax) ~= "number" or type(ay) ~= "number" then return false end
  local bl = dfBlockEnsure(t)
  if not bl then return false end
  local host = rawget(_G, "UIParent") or dfHost()
  pcall(bl.ClearAllPoints, bl)
  pcall(bl.SetPoint, bl, "CENTER", host, "BOTTOMLEFT", ax, ay) -- ★方块**中心**落在 (ax, ay)
  if type(fr.ClearAllPoints) ~= "function" or type(fr.SetPoint) ~= "function" then return false end
  if not pcall(fr.ClearAllPoints, fr) then return false end
  -- ★中心对中心：目标缩放怎么变都对齐（不用除有效缩放 —— 这就是选 CENTER 而非「BOTTOMLEFT + 半宽偏移」的原因）
  if not pcall(fr.SetPoint, fr, "CENTER", bl, "CENTER", 0, 0) then return false end
  return true
end
-- 显示/摆方块。★★★1.75.36n 三条收口：
--   ① **没记录也给方块**（只在编辑模式 + 已勾选 + 帧在）—— 否则没拖过的目标（头像/小地图…）第一次根本
--      没得拖（鸡生蛋）；位置 = 目标现状中心且**不落档**（真的拖了才写记录，与旧柄带模型同口径）；
--   ② 关闭编辑模式 ⇒ 一律 Hide（前提是 dfRefresh **别再把方块同步关在 `if DF.on` 里**，见那边）；
--   ③ 方块定位 = 目标**中心**（用户：「定位在目标层中心位置」；锚法 CENTER ← CENTER，与缩放无关）。
dfBlockSync = function(t, fr)
  if type(t) ~= "table" then return nil end
  local show = (DF.on == true) and dfPicked(t.name) and (fr ~= nil)
  -- ★目标当前没显示 ⇒ 方块也不显示（聊天窗切页 / 宠物条没宠物 ⇒ 不该留个孤块在屏上；与柄带的 shown 门同口径）
  if show and type(fr.IsShown) == "function" then
    local oks, vsh = pcall(fr.IsShown, fr)
    if oks and vsh == false then show = false end
  end
  local store = dfStore(false)
  local rec = (type(store) == "table") and store[t.name] or nil
  if type(rec) ~= "table" and not show then
    -- 守护模式 / 未勾选 / 帧不在：没记录就一个帧都不建（已建的要藏起来）
    local bl0 = dfBlockOf(t.name)
    if bl0 then pcall(bl0.Hide, bl0) end
    return nil
  end
  local bl = dfBlockEnsure(t)
  if not bl then return nil end
  bl.dfTarget = fr
  local ax, ay
  -- ★★1.75.52：**只在编辑模式（`show`）里才做「零位移迁移」** —— `dfBlockPos` 会往记录里写 `ax/ay`，
  --   而守护模式 / 未勾选 / 帧不在时**一个字段都不该写**（用户定：「未设置自定义属性的层不要进入更新操作」；
  --   这也是「[重置] 之后记录清不干净」的第二半：以前每拍 dfRefresh 都把坐标又迁回来）。
  if show and type(rec) == "table" then ax, ay = dfBlockPos(fr, rec) end
  if (type(ax) ~= "number" or type(ay) ~= "number") and type(rec) == "table"
    and type(rec.ax) == "number" and type(rec.ay) == "number" then
    ax, ay = rec.ax, rec.ay -- 非编辑模式：只按记录里**已有**的坐标摆块，绝不迁移、绝不落档
  end
  if (type(ax) ~= "number" or type(ay) ~= "number") and fr then
    local fl, fb, fw, fh = dfMeasure(fr) -- ★没记录：方块贴目标现状中心（不落档）
    if type(fl) == "number" and type(fb) == "number" then ax, ay = fl + dfNum(fw, 0) / 2, fb + dfNum(fh, 0) / 2 end
  end
  if type(ax) == "number" and type(ay) == "number" then
    pcall(bl.ClearAllPoints, bl)
    pcall(bl.SetPoint, bl, "CENTER", rawget(_G, "UIParent") or dfHost(), "BOTTOMLEFT", ax, ay)
  end
  if show then pcall(bl.Show, bl) else pcall(bl.Hide, bl) end
  return bl
end
-- 漂移判据（守护用）：true = 目标不在方块上/不在方块位置上（顺带做零位移迁移）
dfBlockDrift = function(t)
  if type(t) ~= "table" or t.block ~= true then return false end
  local store = dfStore(false)
  local rec = (type(store) == "table") and store[t.name] or nil
  local fr = dfTargetFrame(t)
  if type(rec) ~= "table" or not fr then return false end
  local ax, ay = dfBlockPos(fr, rec) -- ★第一次就以「它现在在哪」为基准（零位移迁移）
  if type(ax) ~= "number" or type(ay) ~= "number" then return false end
  local bl = dfBlockEnsure(t)
  if not bl then return false end
  return not dfBlockAt(fr, bl, rec)
end
end -- do（定位方块段结束）

dfRefresh = function()
  local n = 0
  -- ★★★1.75.36n 方块同步**不受编辑模式的门管**（用户报障：「关闭图层拖拽,也就是关闭编辑模式,方块也要一起隐藏」）：
  --   旧写法整段循环关在 `if DF.on` 里 ⇒ 关掉开关那一刻一个 dfBlockSync 都不跑 ⇒ 方块永远留在屏上。
  --   现在：block 目标**任何时候**都过一遍 dfBlockSync（它内部按 DF.on ∧ 勾选 ∧ 帧在不在定 Show/Hide，幂等）。
  for i = 1, table.getn(DF_TARGETS) do
    local tgtB = DF_TARGETS[i]
    if tgtB.block == true then pcall(dfBlockSync, tgtB, dfTargetFrame(tgtB)) end
  end
  if DF.on then
    for i = 1, table.getn(DF_TARGETS) do
      local tgt = DF_TARGETS[i]
      -- ★★★1.74.32：图标形态的目标**不贴整条透明柄**（它们是 384×512 的窗口，一条 384 宽、20 高的透明条
      --   会把整个窗口标题栏的点击全吃掉）⇒ 走下面的 `dfIconsRefresh`（小图标，默认开）。
      -- ★★1.74.33：**未勾选的层不贴柄**（「选中的才支持拖拽」）—— 柄池是按下标顺序分配的，
      --   跳过某个目标只是少贴一条，不会串位（末尾那段 `for i = n + 1, ... do Hide` 负责把多出来的柄收掉）。
      local fr = (dfPicked(tgt.name) and not tgt.icon) and dfTargetFrame(tgt) or nil
      -- ★★★1.75.36l 方块目标（用户定「取代」）：画 20×20 的定位方块（颜色区分 + 标题），**不再贴整条 20px 透明柄**。
      --   方块只在编辑模式显示；它同时是「绝对基准」（守护就按它的坐标算）。
      if tgt.block == true then
        fr = nil -- ★方块已在上面那段（不受 DF.on 门管）同步过；这一族不贴柄带（`n` 不递增 = 不多占池位）
      end
      -- ★★★1.74.30：**只给当前显示的目标贴条**。
      --   综合与战斗记录是**同一窗口的两页**（ChatFrame1/ChatFrame2）：未显示的那页不该在同一位置叠出一条拖拽条。
      local shown = true
      if fr and type(fr.IsShown) == "function" then
        local oks, v = pcall(fr.IsShown, fr)
        if oks and v == false then shown = false end
      end
      if fr and shown and n < DF_POOL_MAX then
        local w = 120
        if type(fr.GetWidth) == "function" then
          local ok, v = pcall(fr.GetWidth, fr)
          if ok and tonumber(v) and tonumber(v) > 0 then w = tonumber(v) end
        end
        n = n + 1
        local b = dfHandle(n)
        b.dfTarget, b.dfName, b.dfLabel = fr, tgt.name, tgt.label
        if b.dfLabel2 then pcall(b.dfLabel2.SetText, b.dfLabel2, tgt.label) end
        pcall(b.SetWidth, b, math.max(20, w))
        pcall(b.SetHeight, b, DF_DRAG_H)
        pcall(b.ClearAllPoints, b)
        -- 贴目标左上角（拖拽柄锚到别人的帧上 —— 与工具箱/下拉同一套跨父级锚点写法）
        -- ★★★1.75.36：目标可带 `hdx`/`hdy` = **只挪这条柄**的偏移（帧本身一动不动）——
        --   用在「目标与另一个目标的左上角重合」的场合（经验条 vs 主条，见 DF_TARGETS 那条注释）。
        local hx = dfNum(tgt.hdx, 0)
        local hy = dfNum(tgt.hdy, 0)
        -- ★1.75.36c：`hcenterY = true` 的目标 ⇒ 柄**锚到目标的 CENTER**（垂直居中由客户端算，
        --   天然免掉「自己量高度 / 除有效缩放」那一串坑；`hdx/hdy` 仍作附加微调）。
        local hpt = tgt.hcenterY and "CENTER" or "TOPLEFT"
        local okp = pcall(b.SetPoint, b, hpt, fr, hpt, hx, hy)
        if not okp then
          local host = dfHost()
          if host then pcall(b.SetPoint, b, "TOPLEFT", host, "TOPLEFT", 200, -200) end
        end
        pcall(b.Show, b)
      end
    end
  end
  for i = n + 1, table.getn(DF.handles) do
    local b = DF.handles[i]
    if b then
      if DF.dragSt and DF.dragSt.b == b then dfDragEnd("disable") end
      pcall(b.Hide, b)
    end
  end
  DF.poolN = n
  -- ★图标形态（被动窗口）与主开关**无关**：默认开（用户 1.74.32 定），这条刷新不怕重复调用（幂等）
  pcall(dfIconsRefresh)
  return n
end

-- ============ 开关（唯一真值）+ 对外接口 ============
function EVAL_DF_ENABLED()
  local store = dfStore(false)
  if store and type(store.on) == "boolean" then
    -- ★自愈：存档与内存不一致时**以存档为准**（避免“UI 显示开、实际关”这种两处真值打架）
    local on = store.on and true or false
    if (DF.on and true or false) ~= on then
      DF.on = on
      pcall(dfRefresh)
      dfLog("ENABLED：以存档为准同步开关 = " .. tostring(on))
    end
    return on
  end
  return DF.on and true or false
end

function EVAL_DF_SET(on)
  local was = DF.on and true or false
  local want = on and true or false
  -- ★★★1.74.31 护栏（修「载入默认都是关闭 / 不记录用户数据」）：
  --   实例证据：存档里 dragFrames.on = false，而 UI 复选框是打勾的（打勾 = 开）
  --   → **有一次 false 写入把已存的 true 覆盖掉了**（典型来源：行控件在构建/刷新时回写当前值）。
  --   现在：**值没变就不写** → 回写变成 no-op，已存的 true 不会被误覆盖。
  if want == was then
    local st0 = dfStore(false)
    if st0 and type(st0.on) == "boolean" and (st0.on and true or false) == want then
      return true -- 存档与内存一致且本次无变化 → 不写
    end
  end
  DF.on = want
  local store = dfStore(true)
  if store then store.on = want end
  -- ★★★1.75.36i 总开关 = **编辑模式 ⇄ 守护模式**（用户定：「在编辑模式别开启守护.在关闭之后才对有自定义设置的层
  --   进行守护设置」）—— 这一条把 1.75.36f 的武装方向**整个反过来**：
  --     · **打开 = 编辑模式**（拖拽柄/图标可见、你正在摆位置）⇒ 属性守卫**停**（正在编辑时别跟你抢）；
  --     · **关闭 = 守护模式** ⇒ ① 先按存档**应用一次**（把编辑/战斗期间被挪走的层拉回来，也顺手关掉拖拽态/弹窗/跟随），
  --        ② 再**武装**守卫（常驻 0.3s，只治**有自定义记录**的层；没有记录的层一个字节都不碰）。
  --   ★★这两件事一律排在 `dfRefresh()` **之前**：界面刷新即使失败，守护状态也不该错
  --      （且真机上刷新与守护互不依赖 —— **顺序即判据**）。
  --   ★注意这是「关掉零动作」铁律的**明示例外**：本模块关着时守卫照跑（因为它只碰有记录的层、且每拍只读）。
  if not DF.on then
    if DF.dragging then dfDragEnd("disable") end
    if DF.pop then dfPopHide() end
    if type(DF.rstHide) == "function" then pcall(DF.rstHide) end   -- ★1.75.101 重置面板也一起收（关断四件事）
    DF.ghostOffAll()  -- ★1.75.47 关功能 ⇒ 遮蔽一律恢复（结构性兜底）
    DF.rosterLeft = 0 -- ★1.74.32 开关关掉 → 停止队伍/团队跟随（不留后台周期任务）
    dfApplyAll(true)  -- ★「关闭之后」＝按**有自定义记录**的层应用一次（编辑期间摆好的位置就是这一刻定稿）
    pcall(dfGuardArm, "lock")
  else
    pcall(dfGuardStop, "edit-on") -- ★编辑模式：守卫**不跑**（用户明确要求）
  end
  local n = dfRefresh()
  -- ★★1.74.31【任务 A】本次会话里**刚把开关打开**（登录时是关的）⇒ 这也是一次「目标首次出现」：
  --   先应用一次存档参数，再武装一次**有界**复查窗口（5 次 / ≤5 秒 / **绝非常驻**）。
  --   ★已经是开的时候再设「开」不重新武装（免得每次点面板都重置窗口）。
  if DF.on and not was then
    dfApplyAll(true)
    dfKeepArm("enable")
    -- ★1.74.32 开关刚打开时队伍/团队框可能**已经在位**（单人时命中不到、组上人后才出现）
    --   ⇒ 走生产同一条 dfRosterArm：立刻先算一次 + 同时武装有界跟随窗口
    --     （覆盖「帧还没建出来」的那种情况）。★不另写一份逻辑，免得两处口径打架。
    if type(dfRosterArm) == "function" then dfRosterArm("enable") end
    -- ★1.75.36i：这里**不再武装守卫** —— 开关打开 = 编辑模式，按用户要求「编辑模式别开启守护」
    --   （武装点搬到了上面的「关闭 = 守护模式」分支里）。
  end
  say("框拖拽 = " .. (DF.on and ("开（共 " .. tostring(n) .. " 个）") or "关"))
  return true
end

function EVAL_DF_REFRESH() return dfRefresh() end

-- 清单（工具箱 [重置] 的悬停 tooltip 直接逐行 AddLine 它）：
-- ★★★本轮用户要求「工具箱 → 图层拖拽 → 重置 信息显示要显示 缩放、透明度、显示/隐藏 等信息」——
--   所以这里列的是**每个目标当前的真实状态**（dfReadAttrs 现读，不是抄存档），而不是「存档里写了什么」：
--   逐目标一行：缩放 / 透明度 / 显示隐藏（读不到如实写「?」）· 有定位偏移时附上位置 · 末尾一行合计。
--   ★无记录又无异常 → 如实写「（默认值）」；**绝不因为「没记录」就整行不显示**（那样用户看不到当前值）。
-- ★记录字段仍要读（判断「有没有自定义」「有没有定位偏移」），但**只作标记用**，读数一律来自目标。
function EVAL_DF_SUMMARY()
  local out = {}
  local store = dfStore(false)
  local total, recs, miss = 0, 0, 0
  for _, tgt in ipairs(DF_TARGETS) do
    local rec = store and store[tgt.name] or nil
    local hasRec = (type(rec) == "table")
    -- ★「自定义记录」= 记录里**还有实质内容**（位置偏移 / 缩放 / 透明度 / 显隐）；
    --   只剩 base（定位基准）或 legacy 这类内部痕迹的**不算** —— 重置后正是只剩它们，
    --   那时合计写「0 条自定义记录」才与逐行的「（默认值）」自洽（同一口径两处一致）。
    local custom = hasRec and DF.isCustom(rec)   -- ★1.75.101：判定收进共用件（面板同源）
    local fr = dfTargetFrame(tgt)
    -- ★★★1.74.31：候选名一个都没命中的目标**不逐行占版面**（否则新加的 4 个动作条会刷 4 行「帧不在·读不到当前值」），
    --   改成**最后统一一行**如实说明（条数 + 提示用 /edb bars 查真名）。
    if not fr then
      miss = miss + 1
    else
    local sc, al, sh, w, h = dfReadAttrs(fr)
    total = total + 1
    if custom then recs = recs + 1 end
    local parts = {}
    -- ★★★1.74.31 用户要求：「工具箱 → 重置属性 → 信息展示也要将层高度/宽度信息显示」
    --   宽/高放在最前面（一眼看到「这层现在多大」）；与缩放/透明度同口径：**现读目标**，读不到写「?」。
    table.insert(parts, L("TB_LD_SUM_W") .. " " .. (w and string.format("%.0f", w) or "?"))
    table.insert(parts, L("TB_LD_SUM_H") .. " " .. (h and string.format("%.0f", h) or "?"))
    table.insert(parts, L("TB_LD_SUM_SCALE") .. " " .. (sc and string.format("%.2f", sc) or "?"))
    table.insert(parts, L("TB_LD_SUM_ALPHA") .. " " .. (al and string.format("%.2f", al) or "?"))
    if sh == true then
      table.insert(parts, L("TB_LD_SUM_SHOWN"))
    elseif sh == false then
      table.insert(parts, L("TB_LD_SUM_HIDDEN"))
    else
      table.insert(parts, L("TB_LD_SUM_SHOWN") .. "/" .. L("TB_LD_SUM_HIDDEN") .. " ?")
    end
    if hasRec and (rec.dx or rec.dy) then
      table.insert(parts, L("TB_LD_SUM_POS") .. " " .. string.format("%+.0f,%+.0f", dfNum(rec.dx, 0), dfNum(rec.dy, 0)))
    end
    local mark
    -- ★1.74.33 未勾选的层先标「未启用」（它现在不贴柄/不挂图标、存档参数也不应用 ⇒ 上面那些读数虽然
    --   是现读目标的真实值，但**不代表插件在管它** —— 不说清楚会让用户以为「设置了却没生效」）。
    if not dfPicked(tgt.name) then mark = L("TB_LD_SUM_PICKOFF")
    elseif custom then mark = L("TB_LD_SUM_CUSTOM")
    elseif not fr then mark = L("TB_LD_SUM_NOFRAME")
    elseif sc == 1 and al == 1 and sh == true then mark = L("TB_LD_SUM_DEF")
    else mark = L("TB_LD_SUM_ODD") end
    table.insert(parts, "（" .. mark .. "）")
    table.insert(out, tgt.label .. "：" .. table.concat(parts, " · "))
    end -- ★帧没解析到 ⇒ 上面只记 miss，不出行
  end
  -- ★顺序：**合计仍是最后一行**（既有判据「末行是合计」继续成立），找不到帧的说明插在它**上面**
  if miss > 0 then table.insert(out, string.format(L("TB_LD_SUM_MISS"), miss)) end
  table.insert(out, string.format(L("TB_LD_SUM_TOTAL"), total, recs))
  return out
end

-- ★★★本轮用户要求「拖拽图层重置也要重置 缩放、透明度、显示隐藏 等信息」：
--   旧实现**只清定位数据**（缩放/透明/显隐原样保留在记录里）；现在改成**逐项还原到默认**：
--   缩放=1 · 透明度=1 · Show() · 位置按既有 base 归零；还原一项就清掉记录里对应的那一项，
--   记录清空 → 整条删除（沿用既有做法）。战斗保护口径照旧：战斗中不碰受保护帧的这三个属性（如实提示、记录保留）。
-- ============ ★★★1.75.47b [重置] 完成后的「需要 /reload」确认窗 ============
-- 用户原话：「工具箱->图层拖拽->重置.->完成之后弹窗提醒用户需要/reload 操作.确定进行重载」。
-- ★为什么必须 /reload：重置清掉了记录（ax/ay/dx/dy/scale/alpha/hidden），但**被接管锚点的层**
--   （14 个常驻层 SetPoint CENTER/方块/CENTER）不会自动还回客户端原生锚点 —— 接管时 ClearAllPoints
--   把原生锚点冲掉了、我们没存 ⇒ 当场还不了 ⇒ 只有 /reload 让客户端自己重摆（空记录不再接管）。
-- ★ReloadUI 在本客户端是 PROTECTED（UnrealQuest ClientAPI 实测："addons cannot call this"）⇒
--   确定按钮走 **RunScript 绕行**（与本项目 SendChatMessage/SpellStopCasting 同款已验证机制），
--   外加一行诚实兜底（RunScript 是队列/若失败也不崩）：「若界面未刷新，请手动输入 /reload」。
-- ★样式仿 Toolbox.lua 的 subConfirmBuild（DIALOG + level 230 + 金边 + 两按钮）。
DF.reloadAskBuild = function()
  if DF.rloadAsk then return true end
  if type(CreateFrame) ~= "function" then return false end
  local W, H = 420, 150
  -- ★帧名绝不与函数同名（组 54 老坑：具名帧顶掉同名全局函数 ⇒ 函数 type 检查与调用全废）——
  --   函数是 EVAL_DF_RELOAD_ASK()，帧叫 EVAL_DF_RLOAD_ASK。
  local root = CreateFrame("Frame", "EVAL_DF_RLOAD_ASK", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 230)
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(root)
  dfSolid(bg, 0.04, 0.04, 0.04, 0.96)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    dfSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    dfSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, root, "TOP" .. s, 0, 0)
    t:SetPoint("BOTTOM" .. s, root, "BOTTOM" .. s, 0, 0)
    t:SetWidth(1)
  end
  local function mkFS(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    pcall(fs.SetFontObject, fs, "GameFontHighlightSmall")
    return fs
  end
  local title = mkFS(root)
  title:SetPoint("TOP", root, "TOP", 0, -12)
  title:SetTextColor(0.95, 0.82, 0.35)
  local body = mkFS(root)
  body:SetPoint("TOP", root, "TOP", 0, -34)
  body:SetWidth(W - 36)
  pcall(body.SetJustifyH, body, "CENTER")
  body:SetTextColor(0.90, 0.90, 0.90)
  local function mkB(txt, x, fn, nm)
    -- ★具名（与 EVAL_DF_ANCHOR_* 同一惯例）：真机取证与离线 harness 都靠名字拿到按钮
    local b = CreateFrame("Button", nm, root)
    b:SetWidth(130) b:SetHeight(22)
    b:SetPoint("BOTTOM", root, "BOTTOM", x, 14)
    if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
    if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
    local bb = b:CreateTexture(nil, "BACKGROUND")
    bb:SetAllPoints(b)
    dfSolid(bb, 0.22, 0.17, 0.07, 1)
    local bl = mkFS(b)
    bl:SetPoint("CENTER", b, "CENTER", 0, 0)
    bl:SetText(txt)
    b:SetScript("OnClick", fn)
    return b
  end
  mkB("确定重载", -72, function()
    pcall(root.Hide, root)
    -- ★Protected 绕行（与本项目 SendChatMessage/SpellStopCasting 同款已验证机制）；
    --   RunScript 是队列，失败也不崩 ⇒ 下一行提示兜底（「若没重载请自己敲」）。
    pcall(RunScript, "ReloadUI()")
    say("图层拖拽：正在重载界面…（若界面未刷新，请手动输入 /reload）")
  end, "EVAL_DF_RELOAD_ASK_OK")
  mkB("稍后自己 /reload", 72, function() pcall(root.Hide, root) end, "EVAL_DF_RELOAD_ASK_CANCEL")
  root:Hide()
  DF.rloadAsk = { root = root, title = title, body = body }
  return true
end

-- 弹窗（重置完成 = n >= 1 才弹；什么都没清就不用重载）
function EVAL_DF_RELOAD_ASK(n)
  if not DF.reloadAskBuild() then
    say("图层拖拽：重置完成 —— 请手动输入 /reload 让各层恢复客户端原生布局")
    return false
  end
  pcall(DF.rloadAsk.title.SetText, DF.rloadAsk.title, "图层拖拽 · 重置完成")
  local nTxt = (type(n) == "number" and n > 0) and ("已清除 " .. tostring(n) .. " 个目标的自定义设置") or "自定义设置已清除"
  pcall(DF.rloadAsk.body.SetText, DF.rloadAsk.body,
    nTxt .. "。\n被接管锚点的层需要 /reload 才能恢复客户端原生布局。\n确定现在重载界面吗？")
  pcall(DF.rloadAsk.root.Show, DF.rloadAsk.root)
  return true
end

function EVAL_DF_RESET()
  local store = dfStore(false)
  local n, kept, skipped = 0, 0, 0
  local unpicked = 0
  local cScale, cAlpha, cShow, cPos, cW, cH, whMiss = 0, 0, 0, 0, 0, 0, 0
  local combat = dfInCombat()
  local detail = {}
  if store then
    for _, tgt in ipairs(DF_TARGETS) do
      local rec = store[tgt.name]
      -- ★1.74.33 未勾选的层**不在管理范围**：[重置] 一个属性都不碰、记录原样保留（**如实计数**、不静默跳过）。
      --   ★为什么不是「顺手也重置了」：未勾选的层现在连柄/图标都没有，用户根本没在管它 ——
      --     这时候偷偷改它的缩放/宽高，正是「动了用户没让我动的东西」。
      if type(rec) == "table" and not dfPicked(tgt.name) then
        unpicked = unpicked + 1
        rec = nil
      end
      if type(rec) == "table" then
        local fr = dfTargetFrame(tgt)
        -- ★1.75.101：逐目标体 = 共用件（与 dfResetOne / EVAL_DF_RESET_LIST 同一套）
        local did, cc = DF.resetBody(rec, fr, combat)
        cPos = cPos + cc.pos
        cScale = cScale + cc.scale
        cAlpha = cAlpha + cc.alpha
        cShow = cShow + cc.show
        cW = cW + cc.w
        cH = cH + cc.h
        whMiss = whMiss + cc.whMiss
        skipped = skipped + cc.skipped
        -- ③ 记录清空 → 整条删除（沿用既有做法）
        if cc.rest == 0 then store[tgt.name] = nil else kept = kept + 1 end
        if table.getn(did) > 0 then
          table.insert(detail, tgt.label .. "=" .. table.concat(did, "+"))
        end
        n = n + 1
      end
    end
  end
  local got = dfRefresh()
  local msg
  if n == 0 then
    msg = "框拖拽重置：处理 0 个目标（没有任何自定义记录，无需重置）"
  else
    msg = string.format("框拖拽重置：处理 %d 个目标%s；合计 宽还原 %d · 高还原 %d · 缩放还原 %d · 透明度还原 %d · 显示还原 %d · 位置还原 %d",
      n, (table.getn(detail) > 0 and ("（" .. table.concat(detail, " · ") .. "）") or ""),
      cW, cH, cScale, cAlpha, cShow, cPos)
  end
  if combat then
    msg = msg .. "｜战斗中不改缩放/透明度/显隐/宽高（客户端保护）：这几项仍保留在记录里，脱战后请再点一次重置"
  elseif skipped > 0 then
    msg = msg .. "｜另有 " .. tostring(skipped) .. " 项没改成（目标读不到或接口不可用，记录已保留）"
  end
  -- ★宽/高没有「系统默认值」可退回 ⇒ 原始值缺失时**如实说明没还原**（不假装成功）
  if whMiss > 0 then
    msg = msg .. "｜另有 " .. tostring(whMiss) .. " 项宽/高没有「原始值」记录（老存档迁移过来的），无法还原，字段保留"
  end
  if kept > 0 then msg = msg .. "｜另 " .. tostring(kept) .. " 个目标仍留有定位基准记录（未整条删除）" end
  if unpicked > 0 then
    msg = msg .. "｜另有 " .. tostring(unpicked) .. " 个目标没勾选（不在管理范围：记录与属性都原样没动；要管请在工具箱 [设置] 里勾上）"
  end
  msg = msg .. "；拖拽柄 " .. tostring(got) .. " 个（已按新位置重贴）"
  say(msg)
  -- ★1.75.47b：被接管锚点的层要 /reload 才能恢复客户端原生布局 ⇒ 弹窗提醒 + 一键重载（用户定）
  if n >= 1 then pcall(EVAL_DF_RELOAD_ASK, n) end
  return n
end

-- ★★★1.75.101 重置面板的数据源（用户：「点击下栏有自定义属性设置的层/窗口列表,支持多选.确定提交重置.」）：
--   **只列「有自定义属性设置」且已勾选的目标** —— 判定走共用件 `DF.isCustom`（与悬停清单同一口径）；
--   未勾选的层不在管理范围 ⇒ 照旧不列（与 EVAL_DF_RESET 的 `unpicked` 口径一致）。
--   返回 `{ { name = …, label = …, keys = { … } }, … }`（keys = 这一层设了哪些项，供面板行右端显示）。
function EVAL_DF_CUSTOM_LIST()
  local out = {}
  local store = dfStore(false)
  if not store then return out end
  for _, tgt in ipairs(DF_TARGETS) do
    local rec = store[tgt.name]
    if DF.isCustom(rec) and dfPicked(tgt.name) then
      table.insert(out, { name = tgt.name, label = tgt.label, keys = DF.customKeys(rec) })
    end
  end
  return out
end

-- ★★★1.75.101 **只重置选中的那些**（面板 [确定] 的唯一写口）：
--   逐个走共用逐目标体 `DF.resetBody` —— 与全局 `EVAL_DF_RESET` / 图标左键 `dfResetOne` **同一套步骤**，
--   绝不是复制一份（复制 = 以后改一处漏两处）。
--   ① 名单里不存在的名字、没有自定义记录的、未勾选的 ⇒ **如实分档计数**（miss / unpicked / n），绝不静默跳过；
--   ② 战斗中照旧由 `dfRestoreAttrs` 的 combat 门保护（缩放/透明/显隐/宽高保留在记录里，脱战再点一次）。
function EVAL_DF_RESET_LIST(names)
  local want = {}
  if type(names) == "table" then
    for i = 1, table.getn(names) do
      local nm = names[i]
      if type(nm) == "string" and nm ~= "" then want[nm] = true end
    end
  end
  local store = dfStore(false)
  local combat = dfInCombat()
  local n, kept, skipped, unpicked, missN = 0, 0, 0, 0, 0
  local cScale, cAlpha, cShow, cPos, cW, cH, whMiss = 0, 0, 0, 0, 0, 0, 0
  local detail = {}
  if store then
    for _, tgt in ipairs(DF_TARGETS) do
      if want[tgt.name] then
        want[tgt.name] = nil
        local rec = store[tgt.name]
        if not DF.isCustom(rec) then
          missN = missN + 1
        elseif not dfPicked(tgt.name) then
          unpicked = unpicked + 1
        else
          local fr = dfTargetFrame(tgt)
          local did, cc = DF.resetBody(rec, fr, combat)
          cPos = cPos + cc.pos
          cScale = cScale + cc.scale
          cAlpha = cAlpha + cc.alpha
          cShow = cShow + cc.show
          cW = cW + cc.w
          cH = cH + cc.h
          whMiss = whMiss + cc.whMiss
          skipped = skipped + cc.skipped
          if cc.rest == 0 then store[tgt.name] = nil else kept = kept + 1 end
          if table.getn(did) > 0 then
            table.insert(detail, tgt.label .. "=" .. table.concat(did, "+"))
          end
          n = n + 1
        end
      end
    end
  end
  -- 名单里有、但 DF_TARGETS 里没有的名字（旧存档/改名）⇒ 也算「没处理」，如实计数
  for _ in pairs(want) do missN = missN + 1 end
  local got = dfRefresh()
  local msg
  if n == 0 then
    msg = string.format("框拖拽重置（选中 %d 个）：处理 0 个目标（选中的项没有自定义记录或不在管理范围）", table.getn(names or {}))
  else
    msg = string.format("框拖拽重置（选中 %d 个）：处理 %d 个目标%s；合计 宽还原 %d · 高还原 %d · 缩放还原 %d · 透明度还原 %d · 显示还原 %d · 位置还原 %d",
      table.getn(names or {}), n, (table.getn(detail) > 0 and ("（" .. table.concat(detail, " · ") .. "）") or ""),
      cW, cH, cScale, cAlpha, cShow, cPos)
  end
  if combat then
    msg = msg .. "｜战斗中不改缩放/透明度/显隐/宽高（客户端保护）：这几项仍保留在记录里，脱战后请再点一次确定"
  elseif skipped > 0 then
    msg = msg .. "｜另有 " .. tostring(skipped) .. " 项没改成（目标读不到或接口不可用，记录已保留）"
  end
  if whMiss > 0 then
    msg = msg .. "｜另有 " .. tostring(whMiss) .. " 项宽/高没有「原始值」记录，无法还原，字段保留"
  end
  if kept > 0 then msg = msg .. "｜另 " .. tostring(kept) .. " 个目标仍留有定位基准记录（未整条删除）" end
  if unpicked > 0 then msg = msg .. "｜另有 " .. tostring(unpicked) .. " 个目标没勾选（不在管理范围：记录与属性都原样没动）" end
  if missN > 0 then msg = msg .. "｜另有 " .. tostring(missN) .. " 项没找到或有改动（已跳过）" end
  msg = msg .. "；拖拽柄 " .. tostring(got) .. " 个（已按新位置重贴）"
  say(msg)
  if n >= 1 then pcall(EVAL_DF_RELOAD_ASK, n) end
  return n
end

-- ★★★1.75.101 重置面板的**只读**状态口（**活口** = `/eh go dfreset` 探针；判据 harness 也读它）：
--   返回：面板建出来没有 / 显示 / 遮罩显示 / 清单条数 / 显示行数 / **可滚行数** / 已选条数 / 行池上限 /
--         **行偏移 / 可见窗口 / 是不是全选着**（后三个 = 1.75.102 滚动与全选加的；**只追加在尾部** ⇒ 老读数不变）。
--   ★一个字节都不写（纯读）—— 探针与判据共用同一份读数，绝不在别处复刻映射逻辑。
function EVAL_DF_RST_STATE()
  local listed = 0
  local ok, list = pcall(EVAL_DF_CUSTOM_LIST)
  if ok and type(list) == "table" then listed = table.getn(list) end
  local p = DF.rst
  if type(p) ~= "table" then return false, false, false, listed, 0, 0, 0, DF.RST_ROWS, 0, 0, false end
  local shownRows, selN = 0, 0
  local i
  for i = 1, table.getn(p.rows or {}) do
    if p.rows[i]:IsShown() == true then shownRows = shownRows + 1 end
  end
  -- ★只数**真选中**：取消选中写的是 `sel[k] = false`（键还在表里）⇒ `pairs` 计数会把「取消」也数成选中
  for _, v in pairs(p.sel or {}) do if v == true then selN = selN + 1 end end
  local shown = false
  if p.root and p.root:IsShown() == true then shown = true end
  local covShown = false
  if p.cover and p.cover:IsShown() == true then covShown = true end
  local cap = p.cap or 0
  local maxOff = listed - cap
  if maxOff < 0 then maxOff = 0 end
  return true, shown, covShown, listed, shownRows, maxOff, selN, DF.RST_ROWS, (p.off or 0), cap, (listed > 0 and selN >= listed)
end

function EVAL_DF_APPLYALL(quiet)
  local fixed, checked, attrs = dfApplyAll(quiet and true or false)
  return fixed, checked, attrs
end

-- ★★★1.74.33 选中名单变了之后的**一次结算**（工具箱那个多选下拉每点一下就调它一次）：
--   ① 清掉「队伍/团队帧已恢复过」的记账 ⇒ **刚勾上**的队伍/团队帧立刻按存档恢复（否则要等下次组队事件）；
--   ② 对**选中的**目标应用一次存档（`dfApplyAll` 内部只碰勾选的，见那里的门）；
--   ③ 重贴拖拽柄 / 重挂图标（`dfRefresh` 内部同样只碰勾选的）。
--   ★幂等：重复点同一项、或一次点很多项都不会重复建控件（柄与图标都有缓存）。
function EVAL_DF_PICK_REFRESH()
  DF.rosterApplied = {}
  if DF.on then pcall(dfApplyAll, true) end
  local got = 0
  local ok, n = pcall(dfRefresh)
  if ok and tonumber(n) then got = tonumber(n) end
  local picked, tot = EVAL_DF_PICK_COUNT()
  say("框拖拽：图层选择已更新（勾选 " .. tostring(picked) .. "/" .. tostring(tot) ..
    " → 拖拽柄 " .. tostring(got) .. " 个）")
  return got
end

function EVAL_DF_KEEP_TICK(quiet)
  local fixed, checked = dfKeepTick(quiet and true or false)
  return fixed, checked
end

function EVAL_DF_TARGETS()
  local out = {}
  for i = 1, table.getn(DF_TARGETS) do
    local t = DF_TARGETS[i]
    local f = dfTargetFrame(t)
    -- ★1.74.31：对外交出**解析结果**（frame = 帧对象、resolved = 命中的真实帧名）——
    --   面板/测试不必再自己 `_G[名字]`（候选名解析后「名字」可能不是 t.name）。
    table.insert(out, { name = t.name, label = t.label, frame = f, resolved = f and t.__hitName or nil,
      -- ★1.75.36：柄偏移（只影响那条蓝色拖拽柄的位置；断言据此验「经验条柄在主条柄下方」）
      hdx = dfNum(t.hdx, 0), hdy = dfNum(t.hdy, 0),
      -- ★1.75.36c：柄带是否**相对目标垂直居中**（聊天窗两页 = true）
      hcenterY = t.hcenterY and true or false,
    block = t.block and true or false, -- ★1.75.36l「定位方块」目标（绝对基准）
      roster = t.roster and true or false,
      -- ★1.75.x：「按需出现」的**宠物动作条**标记（与 roster 同族，但触发事件不同）
      pet = t.pet and true or false,
      -- ★1.74.32：图标形态标记（被动打开层；面板/断言据此区分「整条透明柄」与「小图标」）
      icon = t.icon and true or false })
  end
  return out
end

-- ============ ★★★1.75.36d 图层拖拽「逐目标」探针（只读）============
-- 用户 2026-09-28：「排查图层拖拽…头像位置缩放，除了主动作条之后的其他动作条缩放位置都无法生效。逐项排查下」。
--   每目标一行 = 勾选 · 解析到的**真帧名** · 帧在不在/显示 · 柄（**按目标名**找当前显示中那条 · 池序号 · 实测矩形）
--   · 存档记录摘要（base 条数 / base 屏幕基准 / dx,dy / scale / alpha / hidden / w,h）。**一个帧属性都不写**。
--   ★取证落**专属有界环 `EVAL_HELP_CONFIG.dfProbe`（`DFP_MAX` 行）**：`say` 只进聊天框、**不落日志环** ⇒ 不给专属落盘的话
--     AI 侧读存档一个字节都拿不到（本项目的老教训，同 lcProbe/selProbe/mbProbe/atkProbe）。
--   ★★容量**必须 ≥ 一份完整报告**（目标数 + 头 + 尾）：本表已有 ~38 个目标 ⇒ 取 40 会在**单次调用内**
--     就把头行挤掉（2026-09-28 harness 当场抓到：n=40 但环首行已经是 #02）⇒ 定 **80**（≈ 两份报告）。
--   ★「柄」按池位号复用 ⇒ 必须按**目标名**查当前**显示中**那条（按下标认会误报）。
local DFP_MAX = 80   -- 至少一份完整报告（目标数 + 头 + 尾）；40 会在单次调用内挤掉头行（harness 实测）
local function dfProbePush(ring, line)
  table.insert(ring, line)
  while table.getn(ring) > DFP_MAX do table.remove(ring, 1) end
end
local function dfProbeRec(rec)
  if type(rec) ~= "table" then return "无记录" end
  local p = {}
  table.insert(p, "base=" .. tostring(type(rec.base) == "table" and table.getn(rec.base) or 0))
  if type(rec.base) == "table" and type(rec.base.l) == "number" then
    table.insert(p, string.format("基准屏位=%.0f,%.0f", rec.base.l, rec.base.b or 0))
  else
    table.insert(p, "基准屏位=?")
  end
  table.insert(p, "dx=" .. tostring(rec.dx or "?"))
  table.insert(p, "dy=" .. tostring(rec.dy or "?"))
  table.insert(p, "scale=" .. tostring(rec.scale or "?"))
  table.insert(p, "alpha=" .. tostring(rec.alpha or "?"))
  table.insert(p, "hidden=" .. tostring(rec.hidden))
  if rec.w or rec.h then table.insert(p, "wh=" .. tostring(rec.w or "?") .. "x" .. tostring(rec.h or "?")) end
  return table.concat(p, " ")
end
function EVAL_DF_PROBE_TARGETS(quiet)
  local store = dfStore(false)
  local lines, picked, withRec, resolvedN, handleN = {}, 0, 0, 0, 0
  local virgin = dfPickVirgin()
  for i = 1, table.getn(DF_TARGETS) do
    local t = DF_TARGETS[i]
    local ok = dfPicked(t.name)
    if ok then picked = picked + 1 end
    local fr = dfTargetFrame(t)
    if fr then resolvedN = resolvedN + 1 end
    -- ★柄：按**目标名**找当前**显示中**那条（池位号复用，绝不按下标认）
    local hb, hidx, hshown = nil, nil, false
    for k = 1, table.getn(DF.handles) do
      local b = DF.handles[k]
      if b and b.dfName == t.name then
        local s = false
        if type(b.IsShown) == "function" then local o, v = pcall(b.IsShown, b) s = (o and v) and true or false end
        if s or not hb then hb, hidx, hshown = b, k, s end
        if s then break end
      end
    end
    local hrect = "?"
    if hb then
      if hshown then handleN = handleN + 1 end
      local l, bt, w, h = dfMeasure(hb)
      if l then hrect = string.format("%.0f,%.0f %.0fx%.0f", l, bt or 0, w or 0, h or 0) else hrect = "读不到" end
    end
    local rec = (type(store) == "table") and store[t.name] or nil
    if type(rec) == "table" then withRec = withRec + 1 end
    local shown = "?"
    if fr and type(fr.IsShown) == "function" then
      local o, v = pcall(fr.IsShown, fr)
      if o then shown = v and "显示" or "隐藏" end
    end
    table.insert(lines, string.format("#%02d %s(%s) 勾=%s 解析=%s 帧=%s/%s 柄=%s 记录=%s",
      i, tostring(t.label or "?"), t.name, ok and "是" or "否",
      t.__hitName and tostring(t.__hitName) or "**没命中**",
      fr and "在" or "**不在**", shown,
      hb and (string.format("#%d[%s %s]", hidx, hshown and "显示" or "隐藏", hrect)) or "**无**",
      dfProbeRec(rec)))
  end
  local head = string.format("== 框拖拽逐目标探针 == 总开关=%s · 目标=%d · 勾选=%d%s · 解析到帧=%d · 已贴柄=%d/%s · 有记录=%d",
    DF.on and "开" or "**关**", table.getn(DF_TARGETS), picked, virgin and "(virgin=全选)" or "",
    resolvedN, handleN, tostring(DF_POOL_MAX), withRec)
  local tail = "读法：勾=否 或 柄=无 ⇒ 那一层现在拖不动；记录里 scale/dx/dy 全是 ? ⇒ 从没成功改过它（不是「改了不生效」，是没写进存档）。"
  local ring = {}
  dfProbePush(ring, head)
  for i = 1, table.getn(lines) do dfProbePush(ring, lines[i]) end
  dfProbePush(ring, tail)
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then
    local old = cfg.dfProbe
    if type(old) ~= "table" then old = {} cfg.dfProbe = old end
    for i = 1, table.getn(ring) do dfProbePush(old, ring[i]) end
  end
  if not quiet then
    for i = 1, table.getn(ring) do say(ring[i]) end
  end
  return table.getn(ring)
end

-- ============ ★★★1.75.36f 属性设置守卫（0.3s；用户定）============
-- 用户原话：「宠物栏位置.在设置之后.偶然性拾取物品之后会被还原位置. 添加一个属性设置守卫,0.3频率重设.
--   对所有有自定义属性设置的, 对聊天框做特殊处理.他本身会被移动缩放大小的.不需要守卫」。
-- ★为什么要「先探测再动手」：1.74.31 之前那套「每 2 秒按存档重锚」的教训是**无条件写** ——
--   拖拽/切图/开窗时反复抢锚点，用户看到的就是「闪烁 / 拖不动」。所以本守卫**每拍只读**，
--   **没有漂移就一个写 API 都不发** ⇒ 平时零写入，才谈得上「常驻」。
-- 三条口径：
--   ① 只对**有自定义属性设置**的目标：记录里真有 `scale/alpha/hidden/dx/dy/w/h` 之一（只有 `base` 不算 ——
--      那是首次解析时就物化的锚点快照）；
--      ★★**聊天框 1.75.36n 起只守坐标**（用户改口：「坐标守卫兜底,尺寸不需要守卫」；此前是整体排除）。
--   ② 每拍：`dfMeasure`（位置）+ `dfReadAttrs`（缩放/透明/显隐/宽高）现读，与记录差超阈值**才**调 `dfApplyOne`
--      （位置+属性的**唯一应用入口**，不另写一套）；
--   ③ **拖拽中整拍跳过**（用户正在动它）；**战斗中只治位置**、属性一律不碰（1.75.36g 定，见 dfGuardTick）。
-- 取证：`DF.guardFixes` 计数 + 专属有界环 `EVAL_HELP_CONFIG.dfGuard`（40 行，**只记真动手的拍**，不刷屏）。
-- ★★★1.75.36m 节拍两档（用户问：「守护能否频率快一点. 1s 30帧. 对性能影响大不?」）：
--   本守卫**每拍只读**（没漂移一个写 API 都不发），所以它的成本 = 「候选数 × 每拍调用次数 × 频率」。
--   逐路径数一下（方块目标无漂移那一拍，就是最常见的一拍）：dfMeasure 4 次（GetLeft/GetWidth/GetHeight/GetBottom）
--   + dfCapture（锚点数/锚点/名字）3~4 次 + 属性 3 次（现改成**记录里没有 scale/alpha/hidden 就一次都不读**，
--   读也只读 3 样、不再白读宽高）≈ **每个候选 10 次上下**（都是 pcall 包着的只读调用）。
--   ⇒ 10 个候选 ≈ 100 次/拍：0.3s 一拍 ≈ 0.3k 次/秒（可忽略）；**30 帧/秒 ≈ 3k 次/秒**，量级仍在 1% CPU 上下。
--   ⇒ 结论：**30 帧常驻也不至于卡**，但「屏上什么都没动的那些帧」是**纯白花**（客户端只在几个可预知时机重排底部条族）。
--   所以口径 = 平时 0.3s，**一旦有东西在动就切 30 帧/秒并只盯一小段（有界）**：
--     ① 进战斗（PLAYER_REGEN_DISABLED —— 你报障的那个时机）② UNIT_PET（宠物动作条登场/退场）
--     ③ ★本守卫**真动手修过一次**（说明客户端正在挪东西）④ 手动 /eh go 框拖拽守卫 快 [秒]。
--   ★要「常驻 30 帧」也有开关：/eh go 框拖拽守卫 常快（**本会话**，不落存档）⇒ 你自己 A/B 体感。
--   ★成本不靠估算，**真机实测**：OnUpdate 里用 GetTime() 量每拍耗时（DF.perfN/perfMs），
--     /eh go 框拖拽守卫 压测 [拍数] 立刻连跑 N 拍并报「平均 ms/拍 · 折算每秒 ms」。
local DF_GUARD_PERIOD = 0.3    -- 平时节拍（只读巡检）
-- ★★快档数值与助手一律走 **DF 表 / 全局口**，不新增 local：主 chunk 有 **200 局部变量上限**，本文件已贴着
--   上限 —— 这一轮加 3 个 local 当场把整份文件打成语法错（`too many local variables (limit is 200)`，
--   本项目 1.75.36l 已因同一条红过一次）⇒ 新常量进 DF 表，新函数直接挂全局读值口。
DF.guardFastPeriod = 0.033    -- ★快档 ≈ 30 帧/秒（用户要的「1s 30帧」）
DF.guardFastSec = 1.5         -- ★快窗口**长度上限**（有界；过窗自动回落 0.3s）
local DF_GUARD_RING = 40

-- ★★★候选判据 = 「**真有能被本守卫写回去的属性**」：位置（`dx/dy`/`ax/ay`）· 缩放 · 透明 · 显隐。
--   ★★**宽/高故意不算**（1.75.36f 收口）：宽高对**任何**目标都不进守卫（非聊天窗根本写不回去；
--     聊天窗能写但用户定了「尺寸不需要守卫」——1.75.36n）⇒ 算进来只会得到「每拍都判漂移、却永远修不好」的空转。
--   ★★**聊天框不再整体排除**（1.75.36n 用户改口：「聊天窗也可以设置坐标守卫兜底,尺寸不不需要守卫」）：
--     它**只进坐标守卫**（候选要有方块坐标 `ax/ay`；尺寸/属性一概不守 —— 客户端的淡出、拖角缩放都归客户端）。
--     ⇒ 判据与「真能动手」对齐，`EVAL_DF_GUARD_STATE` 报的候选数才是**真会动手的**那些。
local function dfGuardCustom(rec)
  if type(rec) ~= "table" then return false end
  -- ★1.75.36l 方块记录（`ax/ay`）= 有自定义位置 ⇒ 也算候选（判据与落点由 `dfBlock*` 那条路负责）
  -- ★★1.75.47 用户要求「未设置自定义属性的层不要进入更新操作」：`axAuto == true` 的 `ax/ay`
  --   是「零位移迁移」的自动基准（系统摆的，不是用户摆的）⇒ **不算候选**（每拍连读都不读）。
  if rec.scale ~= nil or rec.alpha ~= nil or rec.hidden ~= nil or rec.dx ~= nil or rec.dy ~= nil then
    return true
  end
  if (rec.ax ~= nil or rec.ay ~= nil) and rec.axAuto ~= true then return true end
  return false
end

local function dfGuardCandidates()
  local out = {}
  local store = dfStore(false)
  if type(store) ~= "table" then return out end
  for i = 1, table.getn(DF_TARGETS) do
    local t = DF_TARGETS[i]
    if dfPicked(t.name) then
      if dfSizeOK(t.name) then
        -- ★1.75.36n 聊天框：**只守坐标**（候选 = 记录里有方块坐标 ax/ay；尺寸/属性不守 ⇒ 不算候选依据）
        local recC = store[t.name]
        if type(recC) == "table" and (recC.ax ~= nil or recC.ay ~= nil) and recC.axAuto ~= true then table.insert(out, t) end -- ★1.75.47 迁移基准同样不算
      elseif dfGuardCustom(store[t.name]) then
        table.insert(out, t)
      end
    end
  end
  return out
end

-- ★★★名单是**按目标名做键**的表 ⇒ 数它**必须走 pairs**：`table.getn`/`#` 只数数组部分，
--   对纯字符串键的表**恒返回 0**（本读值口第一版就是这么写的：名单明明有 1 个，报出来却是 0）。
local function dfGuardNoWriteN()
  local t = DF.guardNoWrite
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function dfGuardRing(line)
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) ~= "table" then return end
  local ring = cfg.dfGuard
  if type(ring) ~= "table" then ring = {} cfg.dfGuard = ring end
  table.insert(ring, line)
  while table.getn(ring) > DF_GUARD_RING do table.remove(ring, 1) end
end

-- ★★★1.75.36m 开一段**快窗口**（0.033s ≈ 30 帧/秒，**有界**）。四类触发都走这一个入口（探针也走它，不在别处复刻映射）。
--   ★★续期纪律：同一段窗口**不因「又一次动手」无限续期** —— 否则客户端每拍挪一次 = 我们 30 帧/秒跟它拉锯，
--     而「拉锯」正是 1.74.31 之前那套「每 2s 无条件重锚」被人看成闪烁的原因。现在 why == "fix" 且窗口还开着
--     ⇒ **不续期**，一段最多 DF.guardFastSec；过窗后若还在漂，下一拍（0.3s）再修并重新开窗 ⇒ 拉锯夹成有界的一段段。
-- ★★★注意：本函数**故意是全局**（`EVAL_DF_GUARD_FAST`）= 内部助手 + 探针操作口**同一个**（200 local 上限，见上）。
function EVAL_DF_GUARD_FAST(sec, why)
  local s = tonumber(sec) or DF.guardFastSec
  if s <= 0 then s = DF.guardFastSec end
  if s > 60 then s = 60 end -- 上限 60s（防止手滑传个天文数字 = 事实上的常驻满速）
  local cur = dfNum(DF.guardFastLeft, 0)
  if tostring(why) == "fix" and cur > 0 then return cur end -- 不无限续期（见上）
  if s > cur then DF.guardFastLeft = s end
  DF.guardFastArms = dfNum(DF.guardFastArms, 0) + 1
  if tostring(why) ~= "quiet" then
    dfLog(string.format("GUARD FAST %.2fs why=%s", s, tostring(why or "?")))
  end
  return dfNum(DF.guardFastLeft, 0)
end

local function dfGuardTick()
  if DF.dragging then return 0, true end
  local combat = dfInCombat()
  -- ★★★1.75.36g 战斗中也要治**位置**（用户报障：「进入攻击状态,会把宠物动作栏顶到上面去」）——
  --   旧的 `if dfInCombat() then return 0, true end` 把整拍跳掉了，正是这条报障在战斗中**永远治不了**的原因。
  --   现在的口径：**战斗中只治位置**（属性一律不碰，见下）；位置写被客户端拒 ⇒ 记名单、本场战斗不再空写。
  -- ★一出战斗就把名单清空 ⇒ 下一场战斗会**重新试一次**（真被保护就再记一次，绝不永久放弃）。
  if (not combat) and type(DF.guardNoWrite) == "table" and next(DF.guardNoWrite) ~= nil then DF.guardNoWrite = {} end
  local cands = dfGuardCandidates()
  local store = dfStore(false)
  local n = 0
  for i = 1, table.getn(cands) do
    local t = cands[i]
    local fr = dfTargetFrame(t)
    local rec = (type(store) == "table") and store[t.name] or nil
    if fr and type(rec) == "table" then
      local posNeed, attrNeed, why = false, false, nil
      -- ★★★1.75.36k 漂移判据 = **唯一助手 `dfIsAt`**（相对锚点由它内部把基准现算成屏幕位置）。
      --   ★为什么不再自写第二套：1.75.36j 在这里自写了一条「按锚点判」的分支，而落锚那侧（`dfPlaceFrom`）
      --     把**屏幕位移**当**本地偏移**塞进 SetPoint ⇒ 判据与落锚的单位口径不一致：判「到了」但屏幕上是错的，
      --     动作栏1~4 这种**互锚链**还会层层叠加 ⇒ 用户 `/reload` 后「位置全错乱」。
      --   现在判与治都只认屏幕口径（`dfBaseLive` + `dx/dy`），两处不可能再各说各话。
      -- ★★★1.75.36l 方块目标：漂移 = 「没锚在方块上 / 不在方块位置上」（绝对基准，与客户端版式无关）
      if t.block == true then
        if dfBlockDrift(t) then posNeed = true why = "位置" end
      elseif type(rec.base) == "table" and (rec.dx or rec.dy) then
        local bcap = rec.cur or rec.base
        if not dfIsAt(fr, bcap, rec.dx, rec.dy) then posNeed = true why = "位置" end
      end
      -- ★★属性（缩放/透明/显隐）**只在非战斗时**检测与写入：这三种写在战斗中被拒绝/忽略的面更大，
      --   而本轮报障只关于**位置** ⇒ 战斗里把风险面收到最小（位置是「量回自证 + 失败即退让」的）。
      -- ★1.75.36m 两条**省调用**（快档下这是主要成本，行为一字不变 —— 只是把「判不出结果」的读取去掉）：
      --   ① 记录里根本没有 scale/alpha/hidden ⇒ 属性那三条判定**不可能成立** ⇒ 一次属性读都不做；
      --   ② 真要读时传 noSize = true ⇒ 不再白读 GetWidth/GetHeight（守护永远不比宽高）。
      -- ★1.75.36n 聊天框（dfSizeOK）：**属性连读都不读**（用户：「聊天窗也可以设置坐标守卫兜底,尺寸不不需要守卫」
      --   —— 它只进**坐标守卫**；客户端的淡出/拖角缩放归客户端，守卫一概不碰）。
      local needAttrs = (not dfSizeOK(t.name)) and ((rec.scale ~= nil) or (rec.alpha ~= nil) or (rec.hidden ~= nil))
      if (not posNeed) and (not combat) and needAttrs then
        -- ★只读**三样**：缩放 / 透明 / 显隐 —— **宽高不读也不比**（见 `dfGuardCustom` 的头注：候选必然 `noSize`，
        --   宽高根本写不回去，检测它只会「每拍都判漂移、却永远修不好」的空转）。
        local sc, al, sh = dfReadAttrs(fr, true)
        if type(rec.scale) == "number" and type(sc) == "number" and math.abs(sc - rec.scale) > 0.005 then attrNeed = true why = "缩放" end
        if (not attrNeed) and type(rec.alpha) == "number" and type(al) == "number" and math.abs(al - rec.alpha) > 0.005 then attrNeed = true why = "透明" end
        if (not attrNeed) and rec.hidden == true and sh == true then attrNeed = true why = "隐藏" end
        if (not attrNeed) and rec.hidden == false and sh == false then attrNeed = true why = "显示" end
      end
      -- 本场战斗里这个目标已经「写了但没生效」过 ⇒ 不再 0.3s 一次地空写（出战斗自动解禁）
      local noWrite = combat and type(DF.guardNoWrite) == "table" and DF.guardNoWrite[t.name] == true
      if (not noWrite) and (posNeed or attrNeed) then
        -- ★战斗中传 posOnly = combat（只治位置）；`atPos == false` = 位置**没修到位**（多半受保护、被客户端拒）
        -- ★战斗中只治位置；★1.75.36n 聊天框**一律 posOnly**（坐标守卫兜底，尺寸/属性不守）
        local ok, atPos = dfApplyOne(t, combat or dfSizeOK(t.name))
        local notAt = ok and atPos == false
        if notAt and combat then
          -- 战斗中被拒：记名单 + 计数，**不算修复**（不进环、guardFixes 不加）—— 绝不谎报成「已重设」
          if type(DF.guardNoWrite) ~= "table" then DF.guardNoWrite = {} end
          DF.guardNoWrite[t.name] = true
          DF.guardBlocked = dfNum(DF.guardBlocked, 0) + 1
          dfLog("GUARD 战斗中被拒 " .. tostring(t.name) .. "（本场战斗不再重试）")
        elseif ok then
          if notAt then DF.guardBlocked = dfNum(DF.guardBlocked, 0) + 1 end -- 非战斗也没量到位：如实计数
          n = n + 1
          DF.guardFixes = dfNum(DF.guardFixes, 0) + 1
          dfGuardRing(string.format("%s：按存档重设（%s%s%s · 累计第 %d 次）", tostring(t.label or t.name),
            tostring(why or "?"), combat and " · 战斗中" or "", notAt and " ·未量到位" or "", DF.guardFixes))
          dfLog("GUARD 重设 " .. tostring(t.name) .. " why=" .. tostring(why) .. (combat and " combat" or ""))
        end
      end
    end
  end
  return n, false
end

dfGuardStop = function(why)
  DF.guardOn = false
  DF.guardNoWrite = {} -- ★关掉/重开都从「没被拒过」重新开始（名单只对**当前这一场战斗**有意义）
  DF.guardFastLeft = 0 -- ★1.75.36m 快窗口一并失效（停下 = **零动作**：不留热档、不留事件）
  local gf = DF.guardFrame
  if gf and type(gf.SetScript) == "function" then
    pcall(gf.SetScript, gf, "OnUpdate", nil)
    pcall(gf.SetScript, gf, "OnEvent", nil)
  end
  if gf and type(gf.UnregisterAllEvents) == "function" then pcall(gf.UnregisterAllEvents, gf) end
  dfLog("GUARD STOP why=" .. tostring(why or "?"))
  return true
end

dfGuardArm = function(why)
  if type(CreateFrame) ~= "function" then return false end
  local gf = DF.guardFrame
  if not gf then
    gf = CreateFrame("Frame", "EVAL_DF_GUARD", dfHost())
    DF.guardFrame = gf
  end
  DF.guardAcc = 0
  DF.guardOn = true
  if type(DF.guardFastLeft) ~= "number" then DF.guardFastLeft = 0 end
  -- ★1.75.36m 「客户端正准备重排底部条族」的两个时机 ⇒ 顺带开一段快窗口（注册得上才认，注册不上不报错）
  if type(gf.RegisterEvent) == "function" then
    if type(gf.SetScript) == "function" then
      pcall(gf.SetScript, gf, "OnEvent", function()
        local ev = event
        if DF.guardOn and (ev == "PLAYER_REGEN_DISABLED" or ev == "UNIT_PET") then
          EVAL_DF_GUARD_FAST(nil, string.lower(tostring(ev)))
        end
      end)
    end
    pcall(gf.RegisterEvent, gf, "PLAYER_REGEN_DISABLED")
    pcall(gf.RegisterEvent, gf, "UNIT_PET")
  end
  if type(gf.SetScript) == "function" then
    pcall(gf.SetScript, gf, "OnUpdate", function()
      local dt = dfNum(arg1, 0.05)
      if dt <= 0 then dt = 0.05 end
      -- ★快窗口倒计时（有界；「常快」档不看它）
      local left = dfNum(DF.guardFastLeft, 0)
      if left > 0 then
        left = left - dt
        DF.guardFastLeft = (left > 0) and left or 0
      end
      DF.guardAcc = dfNum(DF.guardAcc, 0) + dt
      local fast = (DF.guardFastAlways == true) or (dfNum(DF.guardFastLeft, 0) > 0)
      if DF.guardAcc < (fast and DF.guardFastPeriod or DF_GUARD_PERIOD) then return end
      DF.guardAcc = 0
      -- ★1.75.36m 真机实测每拍耗时（GetTime 进世界才有值；读不到就只计拍数，**不伪造 0**）
      local t0 = (type(GetTime) == "function") and GetTime() or nil
      local n, skipped = dfGuardTick()
      local t1 = (type(GetTime) == "function") and GetTime() or nil
      if type(t0) == "number" and type(t1) == "number" and t1 >= t0 then
        DF.perfMs = dfNum(DF.perfMs, 0) + (t1 - t0) * 1000
        DF.perfN = dfNum(DF.perfN, 0) + 1
      end
      if skipped then DF.guardSkipped = dfNum(DF.guardSkipped, 0) + 1 end
      if n and n > 0 then
        DF.guardMoved = dfNum(DF.guardMoved, 0) + n
        EVAL_DF_GUARD_FAST(nil, "fix") -- ★真动手修过 ⇒ 有东西在动 ⇒ 盯紧一小段（不续期，见该函数头注）
      end
    end)
  end
  dfLog("GUARD ARM why=" .. tostring(why or "?"))
  return true
end

-- 读值口 / 操作口（诊断用；与既有的 `EVAL_DF_KEEP_TICK` 同一族：宿主探针与离线 harness 都走它，
--   ★不在别处复刻映射逻辑）。返回：在跑吗 / 累计重设次数 / 候选数 / 整拍跳过次数 / 累计重设目标数
function EVAL_DF_GUARD_STATE()
  return DF.guardOn and true or false, dfNum(DF.guardFixes, 0), table.getn(dfGuardCandidates()),
    dfNum(DF.guardSkipped, 0), dfNum(DF.guardMoved, 0), dfNum(DF.guardBlocked, 0),
    dfGuardNoWriteN()
end

-- ★1.75.47 ghost 遮蔽状态读值口（生产诊断：守卫状态行与离线 harness 共用；★直给真实计数，不复刻逻辑）。
--   正常恒为 0（就位即恢复）；> 0 = 有帧正在「alpha 归零遮蔽」中等量回 —— 复查窗口到点/摘链/关功能会兜底清零。
function EVAL_DF_GHOST_STATE()
  local G = DF.ghost
  if type(G) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(G) do n = n + 1 end
  return n
end

-- 立刻按存档重设一次（**手动补救**用：宠物栏刚被客户端挪走、不想等到下一拍时用）
function EVAL_DF_GUARD_TICK()
  local ok, n = pcall(dfGuardTick)
  if not ok then return 0 end
  return dfNum(n, 0)
end

-- 手动武装 / 停下守卫（诊断与「关掉零动作」自证用）
function EVAL_DF_GUARD_ARM(why) return dfGuardArm(why or "manual") end
function EVAL_DF_GUARD_OFF(why) return dfGuardStop(why or "manual") end
-- ★★★1.75.36m 节拍 / 性能读值口 + 操作口（探针 `/eh go 框拖拽守卫` 调它们，**不在探针里复刻映射逻辑**）
-- ★快窗口 / 常快档的**定义点**在 dfGuardRing 之后（那是内部助手 + 本读值口同一个全局函数，见那里的头注）
-- 常驻快档开关（**本会话**，不落存档；要 A/B 体感时用）
function EVAL_DF_GUARD_FAST_TOGGLE()
  DF.guardFastAlways = not (DF.guardFastAlways == true)
  return DF.guardFastAlways
end
-- 返回：快窗口剩余秒 · 常快档 · 快窗口累计开过几次 · 累计实测拍数 · 累计实测耗时(ms)
function EVAL_DF_GUARD_FAST_STATE()
  return dfNum(DF.guardFastLeft, 0), (DF.guardFastAlways == true), dfNum(DF.guardFastArms, 0),
    dfNum(DF.perfN, 0), dfNum(DF.perfMs, 0)
end
-- ★压测：立刻连跑 n 拍（默认 30 ≈ 快档下 1 秒的量）。返回 拍数 / 累计动手次数 / 总耗时ms（读不到时间 = nil）/ 候选数
function EVAL_DF_GUARD_PERF_RUN(n)
  local k = tonumber(n) or 30
  if k < 1 then k = 1 end
  if k > 300 then k = 300 end
  local t0 = (type(GetTime) == "function") and GetTime() or nil
  local wrote = 0
  for _ = 1, k do
    local m = EVAL_DF_GUARD_TICK()
    if type(m) == "number" and m > 0 then wrote = wrote + m end
  end
  local t1 = (type(GetTime) == "function") and GetTime() or nil
  local ms = nil
  if type(t0) == "number" and type(t1) == "number" and t1 >= t0 then ms = (t1 - t0) * 1000 end
  local cands = select(3, EVAL_DF_GUARD_STATE())
  return k, wrote, ms, cands
end
-- 安装点（EvalHelp.lua 在 VARIABLES_LOADED 调）：读开关 + 迁移老存档 + 恢复存档 + 武装**有界**复查窗口
function EVAL_DF_INSTALL()
  if DF.installed then return true end
  local store = dfStore(false)
  -- ★★★1.74.31 修（用户：「图层拖拽不记录用户数据，载入默认都是关闭」）：
  --   旧写法在存档尚未就位时把开关定成关，并且 `DF.installed = true` **永久锁死** → 之后再也不读存档。
  --   现在：**没就位就不锁死**（留给后续调用重试）；真正读到存档才置 installed。
  if not store then
    dfLog("INSTALL：存档尚未就位 → 本次不锁死，自带有界重试")
    -- ★★有界重试（模块内自包含：本模块的 INSTALL 只有 VARIABLES_LOADED 一个调用点）
    --   每 0.5 秒试一次、最多 20 次（=10 秒）；期间**一律不写存档**（未就位写会抹数据）
    if type(CreateFrame) == "function" and not DF.retryFrame then
      local rf = CreateFrame("Frame", "EVAL_DF_INSTALL_RETRY", dfHost())
      DF.retryFrame = rf
      local acc, tries = 0, 0
      rf:SetScript("OnUpdate", function()
        if DF.installed then pcall(rf.SetScript, rf, "OnUpdate", nil) DF.retryFrame = nil return end
        acc = acc + (tonumber(arg1) or 0.05)
        if acc < 0.5 then return end
        acc = 0
        tries = tries + 1
        local ok = EVAL_DF_INSTALL()
        if ok then
          dfLog("INSTALL：就位后第 " .. tostring(tries) .. " 次重试成功（开关 = " .. tostring(DF.on) .. "）")
          pcall(rf.SetScript, rf, "OnUpdate", nil)
          DF.retryFrame = nil
        elseif tries >= 20 then
          say("框拖拽：存档重试 20 次仍未就位（期间未写入，不会抹数据）；下次 /reload 再试")
          pcall(rf.SetScript, rf, "OnUpdate", nil)
          DF.retryFrame = nil
        end
      end)
    end
    return false
  end
  DF.installed = true
  DF.on = (store.on == true) and true or false
  dfMigrate(true)
  -- ★1.75.109 聊天窗两页并档（必须在 `dfApplyAll` **之前**：合并后的记录才是要应用的那份）
  pcall(dfMirrorMerge, true)
  -- ★1.74.33 被动窗口的宽高清理放在「应用存档之前」：先清掉+还原，再让 dfApplyAll 应用剩下的（缩放/透明/显隐）
  pcall(EVAL_DF_SIZE_CLEAN, true)
  dfTickEnsure()
  dfApplyAll(true) -- ★① 目标首次出现 → **先应用一次**存档参数（位置 + 属性）
  dfRefresh()
  -- ★② 再武装有界复查：每 1 秒一次、净 5 次、全符合就永久停（用户 1.74.31 的要求）
  dfKeepArm("install")
  -- ★★★1.74.32 队伍/团队帧是**按需出现**的：登录这一刻多半还没有（单人/没进团队）⇒
  --   ① 建事件帧（注册 PARTY_MEMBERS_CHANGED / RAID_ROSTER_UPDATE / PLAYER_ENTERING_WORLD）；
  --   ② 开关开着就跟着走一次（有界）—— 组上人那一刻自动恢复存档参数 + 补拖拽柄。
  dfRosterEnsure()
  if DF.on then dfRosterArm("install") end
  -- ★★★1.75.36i 守卫与「编辑模式」互斥（用户定：「在编辑模式别开启守护.在关闭之后才对有自定义设置的层
  --   进行守护设置」）⇒ 安装期这一行的方向与 1.75.36f **正好相反**：
  --     · 总开关**关着 = 守护模式** ⇒ **武装**（只治「有自定义记录、且非聊天框」的层，没漂移不写）；
  --     · 总开关**开着 = 编辑模式** ⇒ **停**（你正在摆位置时别抢）。
  if DF.on then pcall(dfGuardStop, "install-edit") else pcall(dfGuardArm, "install-lock") end
  dfLog("INSTALL on=" .. tostring(DF.on) .. " store=" .. tostring(store ~= nil))
  return true
end

-- ============ 诊断（子插件 /edb drag* 走这里）============
local function dfRectLine(tag, fr)
  if not fr then return tag .. "：（无）" end
  local okn, np = pcall(fr.GetNumPoints, fr)
  local l, b, w, h = dfMeasure(fr)
  local okp, p, rel, relp, x, y = pcall(fr.GetPoint, fr, 1)
  local cur = "?"
  if okp and p then
    cur = string.format("%s→%s/%s, %.0f, %.0f", tostring(p), tostring(dfRelName(rel) or "（父级）"),
      tostring(relp), dfNum(x, 0), dfNum(y, 0))
  end
  local okpar, par = pcall(fr.GetParent, fr)
  local pn = "?"
  if okpar and par and type(par.GetName) == "function" then
    local okn2, nm = pcall(par.GetName, par)
    if okn2 then pn = tostring(nm) end
  end
  return string.format("%s: 锚点数=%s 第1锚点=%s 父级=%s 矩形=%s", tag, tostring(okn and np or "?"), cur, pn,
    l and string.format("L=%.0f B=%.0f W=%.0f H=%.0f", l, b, w, h) or "（量不到）")
end

function EVAL_DF_RECT()
  say("--- 框拖拽 · 弹窗定位诊断 ---")
  local up = rawget(_G, "UIParent")
  say(dfRectLine("屏幕（UIParent）", up))
  say(dfRectLine("宿主（WorldFrame）", dfHost()))
  if DF.pop then say(dfRectLine("配置弹窗", DF.pop.root)) end
  local info = DF.popInfo or {}
  say(string.format("定位结果 mode=%s（host=%s uip=%s set=%s 锚点数=%s） 目标中心=(%s,%s) 实测中心=(%s,%s)",
    tostring(DF.popMode or "（还没弹过）"), tostring(info.host), tostring(info.uip), tostring(info.set),
    tostring(info.points), tostring(info.cx), tostring(info.cy), tostring(info.px), tostring(info.py)))
  if DF.popMode == "failed" then
    say("判读：锚点没落上（位置会停在 (0,0) = 父级左下角）—— 把上面这几行发我，就能定死是哪一步没生效")
  else
    say("判读：锚点已落上（mode=host 表示相对父级居中成功；uiparent 表示走了兜底路径）")
  end
  return DF.popMode
end

function EVAL_DF_DIAG()
  say("--- 框拖拽诊断（tools/DragFrames.lua）---")
  say("开关=" .. (EVAL_DF_ENABLED() and "开" or "关") .. " · 拖拽中=" .. tostring(DF.dragging)
    .. " · 拖拽柄=" .. tostring(DF.poolN) .. " 个 · 最近结束原因=" .. tostring(DF.dragWhy))
  say("结束兜底：IsMouseButtonDown=" .. tostring(DF.mouseDownOK) .. "（返回 " .. tostring(DF.mouseDownSeen) ..
    "） · GetMouseFocus=" .. tostring(DF.focusOK) .. " · 全屏接盘=" .. (DF.catcher and "已建" or "未建"))
  local store = dfStore(false)
  for _, tgt in ipairs(DF_TARGETS) do
    local rec = store and store[tgt.name]
    local fr = dfTargetFrame(tgt)
    local cur = "?"
    if fr then
      local okp, p, rel, relp, x, y = pcall(fr.GetPoint, fr, 1)
      if okp and p then
        cur = string.format("%s→%s/%s,%.0f,%.0f", tostring(p), tostring(dfRelName(rel) or "（父级）"),
          tostring(relp), dfNum(x, 0), dfNum(y, 0))
      end
    end
    say(string.format("%s(%s): 记录=%s 帧=%s 当前第1锚点=%s · dx,dy=%s,%s%s", tgt.label, tgt.name,
      type(rec) == "table" and "有" or "无", fr and "在" or "不在", cur,
      tostring(rec and rec.dx or 0), tostring(rec and rec.dy or 0),
      (type(rec) == "table" and rec.legacy) and "（老存档搬来的记录）" or ""))
  end
  local fixed, checked = dfKeepTick(false)
  say(string.format("启动期复查（有界）：%s · 净检查 %d/%d 次 · 评估 %d/%d 次（跳过 %d）· 修正 %d 轮 · 覆盖面 %d 个目标",
    DF.keepDone and ("已结束（原因=" .. tostring(DF.keepWhy or "?") .. "，永久停）")
      or ("进行中（由 " .. tostring(DF.keepArmed or "?") .. " 武装）"),
    DF.keepRuns, DF_KEEP_CHECKS, DF.keepTries, DF_KEEP_TRIES, DF.keepSkips, DF.keepFixed, DF.keepChecked))
  say("手动单次复查：检查 " .. tostring(checked) .. " 个，重设 " .. tostring(fixed) .. " 个（★手动入口不消耗窗口次数）")
  return true
end

function EVAL_DF_TRIAL()
  local fr = nil
  local label = nil
  local name = nil
  for _, tgt in ipairs(DF_TARGETS) do
    local f = dfTargetFrame(tgt)
    if f then fr, label, name = f, tgt.label, tgt.name break end
  end
  if not fr then
    say("框拖拽：没有可用目标（5 个目标帧一个都没到位）")
    return false
  end
  say("框拖拽弹窗试用目标：" .. tostring(label))
  return dfCommitPop(fr, label, name) and true or false
end

function EVAL_DF_TOGGLE()
  return EVAL_DF_SET(not EVAL_DF_ENABLED())
end

-- ★★★1.74.33 「不许改宽高的窗口」的**清理**（用户截图里法术书撕裂 = 老记录里存着 w/h）：
--   在册的**不许改宽高的**窗口若存档里有 w/h ⇒ ① 有原始值（rec.ow/oh）就**还原** ② 清掉 w/h/ow/oh ③ 如实报数。
--   ★★★1.75.1：口径改成「**只给聊天窗**」之后，本函数**只清 `noSize == true` 的目标** ——
--     聊天窗的 w/h 是**用户要的持久化数据**，一个字段都不许动（这是「并且持久化」的反面保证）。
--   ★不是「静默清掉」：清了几项要打出来（用户得知道插件动了他的存档，以及为什么动）。
--   ★独立于 `store.mig` 那道迁移（老用户那次早就打过标记了，再挂在那下面等于永不执行）。
function EVAL_DF_SIZE_CLEAN(quiet)
  local store = dfStore(false)
  if not store then return 0, 0 end
  local n, restored = 0, 0
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    local rec = store[tgt.name]
    -- ★★★1.75.1 只清「不许改宽高」的目标（`noSize == true`）；**聊天窗的宽高绝不动**（那是要持久化的数据）
    if tgt.noSize == true and type(rec) == "table" and (rec.w ~= nil or rec.h ~= nil) then
      local fr = dfTargetFrame(tgt)
      if fr then
        if rec.ow ~= nil and type(fr.SetWidth) == "function" then
          if pcall(fr.SetWidth, fr, rec.ow) then restored = restored + 1 end
        end
        if rec.oh ~= nil and type(fr.SetHeight) == "function" then
          if pcall(fr.SetHeight, fr, rec.oh) then restored = restored + 1 end
        end
      end
      rec.w, rec.h, rec.ow, rec.oh = nil, nil, nil, nil
      n = n + 1
    end
  end
  if n > 0 then
    say(string.format("框拖拽：已清掉 %d 个窗口的老宽高设置（这些窗口不许改宽高：会撕裂内部布局）· 还原原尺寸 %d 项；" ..
      "聊天窗的宽高**保留不动**（那是你要的持久化）", n, restored))
  elseif not quiet then
    say("框拖拽：存档里没有宽高设置（无需清理）")
  end
  dfLog("SIZE CLEAN 清理 " .. tostring(n) .. " 个目标的宽高，还原 " .. tostring(restored) .. " 项")
  return n, restored
end

-- 老存档迁移（活口：`/eh go` 里那一条；同时**顺带把聊天窗两页并档** —— 两个都是「老存档一次性」的活）
function EVAL_DF_MIGRATE() return dfMigrate(false) + dfMirrorMerge(false) end

-- ★★★1.74.31 取证命令 `/edb bars`：「动作条1~4」在本客户端到底叫什么帧名？
--   本客户端 UI 编译在 pak 里（磁盘上没有 FrameXML），别的插件也一次没引用过 MultiBar* ⇒ 只能现场探。
--   交付三样（本项目取证纪律）：① 候选项逐个报「在不在」；② **全 _G 扫一遍**名字像动作条的帧（不许猜漏）；
--   ③ 结果**落存档** `EVAL_HELP_CONFIG.dragBars`（/reload 后 AI 直接读，不必用户复制粘贴）。
-- ★★★1.74.32【第 1 步：只读取证】再扩两类：
--   ④ **被动打开层候选**（`DF_WIN_CANDS`：公会/属性/拍卖/邮箱/任务/技能树 + 训练师/交易技能/商人/好友）
--      —— 逐个报「在/不在」，落存档 `dragBars.cands`；★这批**只取证**，没进 DF_TARGETS（行为零变化）。
--   ⑤ **顶层大帧兜底扫描** —— 关键词扫不到「名字不按套路来」的窗口（本客户端是 UE 重写），
--      改用被动打开层的共同形态捞：**父级是 UIParent/WorldFrame 且 ≥200×150 的顶层帧**，
--      落存档 `dragBars.top`（含宽高/父级/层级，正好是画图标要用的全部数据）。
-- ★★★1.74.32 扩成「框体探针」：同一条命令也扫**队伍 / 团队**（用户新加了「队伍层/团队层」两个目标），
--   并且**同时报出当前组队状态**（`GetNumPartyMembers` / `GetNumRaidMembers`）——
--   这是区分「你现在没组队，所以帧当然没有」与「有队伍但帧名不对」的唯一办法（`/edb bars` 保留原名，兼容旧用法）。
-- ★★★1.74.32【第 1 步：只读取证】再扩到「被动打开层」：公会 / 属性 / 拍卖 / 邮箱 / 任务 / 技能树
--   （外加用户没点名但有「等」字的 训练师 / 交易技能 / 商人 / 好友）——这批窗口的真名同样零本地证据。
--   ★关键词表是**唯一分组来源**：加新组只改这里 + `dump.groups` 的初始化，别在别处再写一份。
local function dfFrameLikeGroup(n)
  if type(n) ~= "string" then return nil end
  local s = string.lower(n)
  -- ★1.75.x 宠物动作条：**必须在 bar 之前判** —— `PetActionBarFrame` 里含 "actionbar"，
  --   顺序反了会被判成 "bar" 组（探针分组里就看不到宠物条，取证时误判「帧名不对」）。
  if string.find(s, "petaction", 1, true) or string.find(s, "petbar", 1, true) then return "pet" end
  -- ★1.75.38 姿态条：必须在 bar 之前判 —— `ShapeshiftBarFrame` 里含 "bar"（顺序反了会归错组）
  if string.find(s, "shapeshift", 1, true) or string.find(s, "stance", 1, true) then return "stance" end
  if string.find(s, "multibar", 1, true) or string.find(s, "actionbar", 1, true)
    or string.find(s, "actionbutton", 1, true) or string.find(s, "multiaction", 1, true)
    or string.find(s, "mainmenubar", 1, true) then return "bar" end
  if string.find(s, "party", 1, true) then return "party" end
  if string.find(s, "raid", 1, true) then return "raid" end
  -- ↓ 1.74.32：被动打开层（顺序 = 先具体后笼统，避免 "characterframe" 被 "char" 之类抢走）
  if string.find(s, "guild", 1, true) then return "guild" end
  if string.find(s, "paperdoll", 1, true) or string.find(s, "characterframe", 1, true)
    or string.find(s, "characterpanel", 1, true) then return "char" end
  if string.find(s, "auction", 1, true) then return "auction" end
  if string.find(s, "mail", 1, true) or string.find(s, "inbox", 1, true) then return "mail" end
  if string.find(s, "quest", 1, true) then return "quest" end
  if string.find(s, "spellbook", 1, true) or string.find(s, "skillframe", 1, true) then return "spell" end
  if string.find(s, "trainer", 1, true) then return "trainer" end
  if string.find(s, "tradeskill", 1, true) or string.find(s, "craftframe", 1, true)
    or string.find(s, "tradeframe", 1, true) then return "trade" end
  if string.find(s, "merchant", 1, true) then return "merchant" end
  if string.find(s, "friend", 1, true) then return "friend" end
  return nil
end

-- ★探针共用的「父级名」解析（原本内联在扫描循环里；加了顶层大帧扫描后要两处都用 ⇒ 抽成一个）
--   ★拿不到就返回 "?"（本项目纪律：查不到 ≠ 没有，如实写「?」）
local function dfFrameParentName(f)
  if not f or type(f.GetParent) ~= "function" then return "?" end
  local okp, p = pcall(f.GetParent, f)
  if not (okp and p) or type(p.GetName) ~= "function" then return "?" end
  local okn, pn = pcall(p.GetName, p)
  if okn and type(pn) == "string" and pn ~= "" then return pn end
  return "?"
end

-- ★★★1.74.32 真机实测的原样报错（用户截图）：
--   `DragFrames.lua:2003: attempt to index local 'f' (a userdata value)`
--   —— `_G` 里**有些全局是「不可索引的 userdata」**：既不是帧、也没有方法元表，
--   一句 `f.GetParent` / `f.GetLeft` 就抛错，**把整个探针打断**（而且报错点看上去跟"帧名"毫无关系）。
--   ★为什么以前没踩到：全 `_G` 扫描是本模块**第一处会去索引任意全局**的代码 —— 其它路径都只碰已知帧名。
--   ⇒ 扫描任何 `_G` 全局之前，必须先过这道「能不能当帧用」的安全探测；
--     探不到就当它不是帧、**如实跳过**（不猜、也不报错）。
local function dfFrameUsable(f)
  if type(f) == "table" then return true end -- 普通表（含测试桩）：索引安全，取不到方法自然得 nil
  if type(f) ~= "userdata" then return false end
  local ok, v = pcall(function() return f.GetParent end) -- 故意探一个**所有帧都有**的方法
  return (ok and type(v) == "function") and true or false
end

-- ★对象类型（Texture / FontString / Frame …）。★拿不到就返回 **nil**（调用方不许据此丢弃 —— 「查不到 ≠ 没有」）
--   用途：扫 `_G` 时把「贴图/文字/冷却圈」这类**同名子件**滤掉（真机上光 ActionButton* 就有 3000 多个子件，
--   全塞进存档会把 SavedVariables 灌成大文件，而且它们根本不是可拖拽的"层"）。
local function dfObjectType(f)
  if not dfFrameUsable(f) then return nil end
  local ok, v = pcall(function() return f.GetObjectType end)
  if not (ok and type(v) == "function") then return nil end
  local ok2, t = pcall(v, f)
  if ok2 and type(t) == "string" then return t end
  return nil
end

-- ★★★1.74.32 顶层宿主判定：**按对象身份判，绝不按父级名字判**。
--   理由（本轮实测踩到）：桩/真机都可能让顶层帧的 `GetName()` 返回 nil（测试桩里 UIParent 就是无名的），
--   按名字判 ⇒ **一个都匹配不上**，兜底清单直接空掉（组 209⑤ 当场抓到）。
--   对象身份在两处都成立：真机 `_G.UIParent` / `_G.WorldFrame`，测试桩里也是同一批对象。
--   ★开头那句也必须走安全探测：本函数是**被 `_G` 全扫描调用**的，直接 `f.GetParent` 会抛
--     "attempt to index local 'f' (a userdata value)"（真机原样报错即此）。
local function dfTopHost(f)
  if not dfFrameUsable(f) then return nil end
  local okm, m = pcall(function() return f.GetParent end)
  if not (okm and type(m) == "function") then return nil end
  local okp, p = pcall(m, f)
  if not (okp and p) then return nil end
  if p == rawget(_G, "UIParent") then return "UIParent" end
  if p == rawget(_G, "WorldFrame") then return "WorldFrame" end
  return nil
end

-- ★探针共用的「帧摘要」：显隐 / 宽高 / 父级 / 层级（四处口径一致，绝不各写一份）
local function dfFrameBrief(f)
  local l, b, w, h = dfMeasure(f)
  local sh = nil
  if type(f.IsShown) == "function" then
    local ok, v = pcall(f.IsShown, f)
    if ok then sh = (v == true or v == 1) end
  end
  local lv = "?"
  if type(f.GetFrameLevel) == "function" then
    local okl, v = pcall(f.GetFrameLevel, f)
    if okl then lv = tostring(v) end
  end
  return { shown = sh, w = w, h = h, left = l, bottom = b, parent = dfFrameParentName(f), level = lv }
end

-- ★★★1.74.32 追加取证：**匿名窗口**（没有全局名）靠前面的 `_G` 扫描**永远看不到** ——
--   全 `_G` 扫描只认「挂在 `_G` 上的具名帧」；而本客户端有些窗口是 `CreateFrame("Frame", nil, UIParent)`
--   建出来的。真机线索：用户明明**开着拍卖行**，候选逐个探全「不在」、`auction` 关键词命中 **0**、
--   连顶层大帧兜底清单里也没有任何像拍卖行的帧 ⇒ 强烈指向「它是匿名的」。
--   ⇒ 改走**父子链**：从 `UIParent`/`WorldFrame` 用 `GetChildren()` 往下走两层，按尺寸筛窗口，
--     并**把每个窗口前几个具名子件记下来**（**匿名父 + 具名子件 = 身份的指纹**：
--     例如里面出现 `AuctionFrame*` / `BrowseButton` / `BidButton` / `BuyoutButton`，就能认出这是拍卖行）。
--   ★`GetChildren` 在本客户端**已被验证可用**（子插件的图层扫描就是靠它走全树的），返回的是**多值**不是表
--     ⇒ 必须像子插件那样 `local rc = { pcall(...) }` 之后再从 2 开始遍历。
local DF_PROBE_KIDS_MAX = 150
-- ★★「满屏家具帧」过滤：真机那份顶层清单里一大半是 `1228.8x768`（= UIParent 尺寸）的内部件 ——
--   事件帧 / 遮罩 / 过场（`EVAL_*`、`UnrealQuest*`、`CinematicFrame`、`WorldMapBlackout` …）。
--   它们**不是窗口**（窗口都是 384×512 那一族），留着既灌存档又把真正想看的窗口挤出上限。
--   ★判据用**相对量**（≥ UIParent 尺寸的 99%）而不是写死数字：客户端分辨率/缩放一变，写死值就错。
local function dfKidIsFullscreen(w, h)
  local up = rawget(_G, "UIParent")
  if not up then return false end
  local _, _, uw, uh = dfMeasure(up)
  if not (uw and uh and uw > 0 and uh > 0) then return false end
  return (w >= uw * 0.99) and (h >= uh * 0.99)
end

local function dfKidNames(fr, cap)
  local out = {}
  if not fr or type(fr.GetChildren) ~= "function" then return out end
  local rc = { pcall(fr.GetChildren, fr) }
  if not rc[1] then return out end
  for i = 2, table.getn(rc) do
    local c = rc[i]
    if c and table.getn(out) < cap and type(c.GetName) == "function" then
      local ok, v = pcall(c.GetName, c)
      if ok and type(v) == "string" and v ~= "" then table.insert(out, v) end
    end
  end
  return out
end

local function dfKidWalk(fr, depth, out)
  if depth > 2 or not fr or type(fr.GetChildren) ~= "function" then return end
  local rc = { pcall(fr.GetChildren, fr) }
  if not rc[1] then return end
  for i = 2, table.getn(rc) do
    local c = rc[i]
    if c and dfFrameUsable(c) then
      local nm = "（无名）"
      if type(c.GetName) == "function" then
        local okn, v = pcall(c.GetName, c)
        if okn and type(v) == "string" and v ~= "" then nm = v end
      end
      local _, _, w, h = dfMeasure(c)
      -- 「像窗口」= **宽高都 ≥200** 且不是满屏家具帧。
      --   ★为什么要「都」：真机那族窗口都是 384×512 起步（宽高同时够大），
      --     而「宽够高不够」的多半是聊天框/条状件（400×120 之类）—— 上一版用「或」，
      --     结果清单被这类帧占满、真正的窗口反而被上限挤掉（测试环境当场暴露，真机同样会）。
      if w and h and w >= 200 and h >= 200 and not dfKidIsFullscreen(w, h)
        and table.getn(out) < DF_PROBE_KIDS_MAX then
        local br = dfFrameBrief(c)
        table.insert(out, { name = nm, shown = br.shown, w = br.w, h = br.h, level = br.level,
          parent = br.parent, host = dfTopHost(c) or "?", depth = depth, kids = dfKidNames(c, 8) })
      end
      if depth < 2 then dfKidWalk(c, depth + 1, out) end
    end
  end
end

-- ★组队状态（现读，读不到如实写「?」）：探针必须先说清「该不该有帧」，否则结果无法解释
local function dfRosterCounts()
  local p, r = nil, nil
  if type(GetNumPartyMembers) == "function" then
    local ok, v = pcall(GetNumPartyMembers)
    if ok then p = tonumber(v) end
  end
  if type(GetNumRaidMembers) == "function" then
    local ok, v = pcall(GetNumRaidMembers)
    if ok then r = tonumber(v) end
  end
  return p, r
end

-- ★★★1.74.32【取证命令不能静默】真机踩到之后补的安全入口：
--   背景：子插件那条老路是 `pcall(EVAL_DF_PROBE_BARS)` —— 探针一旦中途抛错，错误被**静默吞掉**、
--   聊天框什么都不打、存档里也没有痕迹 ⇒ 用户看到的是「命令没反应」，而 AI 这边**无法判断**
--   是「命令压根没跑」还是「跑了一半死了」（本轮真机就卡在这里：存档里连 dragBars 键都没有）。
--   ⇒ 三层补救，缺一不可：
--     ① `EVAL_DF_PROBE_MARK(phase, err)`：往存档里写当前**阶段**（start / error）+ 错误原文；
--     ② `EVAL_DF_PROBE_BARS` **第一句**就写 start 标记，末尾写 phase="done" 的完整结果；
--     ③ `EVAL_DF_PROBE_SAFE()` = 统一 pcall 入口，失败时把错误原文播报到聊天框并落存档。
--   ★主插件 `/eh go 框体探针` 与子插件 `/edb bars` **都走 SAFE 这一个入口**（两条路一套口径）。
--   ★这个键名（`dragBars`）与探针结果同名：出错时它就是一份「错误快照」，会覆盖上次的成功结果 ——
--     这是有意的（宁可留下最新的失败证据，也不留一份过期的成功结果让人误判）。
function EVAL_DF_PROBE_MARK(phase, err, key)
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) ~= "table" then return false end
  -- ★1.74.33 第三个参数 = 落到哪个键上（默认 dragBars 保持不变 ⇒ 老调用点一行不用改；
  --   开窗探针用自己的 dragAttr，两边**互不覆盖**——同写一个键会把对方的取证结果抹掉）。
  cfg[key or "dragBars"] = { phase = tostring(phase or "?"),
    err = (err ~= nil) and tostring(err) or nil,
    at = (type(GetTime) == "function") and GetTime() or nil }
  return true
end

function EVAL_DF_PROBE_SAFE()
  EVAL_DF_PROBE_MARK("start")
  local ok, err = pcall(EVAL_DF_PROBE_BARS)
  if ok then return true end
  EVAL_DF_PROBE_MARK("error", err)
  say("|cffff6060框体探针出错|r：错误原文已写进存档 `EVAL_HELP_CONFIG.dragBars.err`（/reload 后可直接读）；原文：" .. tostring(err))
  return false, tostring(err)
end

-- ★分组表**必须与 `dfFrameLikeGroup` 的返回值一一对应**（少一个组名 ⇒ 该组结果静默丢掉，本项目最恨的那种）
local DF_PROBE_GROUPS = { "bar", "pet", "stance", "party", "raid", "guild", "char", "auction", "mail", "quest",
  "spell", "trainer", "trade", "merchant", "friend" }
local DF_PROBE_TOP_MAX = 80  -- 顶层大帧清单上限（够用即可，避免存档被灌成大文件）
-- ★★上限（1.74.32 真机实测补）：关键词会命中**几千个同名子件**（ActionButton* 的贴图/文字/冷却圈…），
--   全落档会把 SavedVariables 灌成大文件（登录/重载都要写盘）⇒ 落档量封顶，但**命中总数如实记**。
local DF_PROBE_FOUND_MAX = 400
local DF_PROBE_GROUP_MAX = 200

function EVAL_DF_PROBE_BARS()
  local dump = { targets = {}, cands = {}, top = {}, found = {}, groups = {} }
  -- ★第一句就落「开始了」的标记（半路死掉也有痕迹；理由见 EVAL_DF_PROBE_MARK 的注释）
  EVAL_DF_PROBE_MARK("start")
  for i = 1, table.getn(DF_PROBE_GROUPS) do dump.groups[DF_PROBE_GROUPS[i]] = {} end
  -- ⓪ 先报组队状态 —— 「候选全不在」在单人时是**正常**的，在有队伍时才是帧名不对
  local pN, rN = dfRosterCounts()
  dump.partyMembers, dump.raidMembers = pN, rN
  say(string.format("框体探针：队友 %s 个 · 团员 %s 个（含自己）",
    (pN and tostring(pN) or "?"), (rN and tostring(rN) or "?")))
  if (rN or 0) > 0 then say("  ⇒ 现在在团队里，团队层本该有帧；若下面候选全不在，就是帧名不对（把结果发我）")
  elseif (pN or 0) > 0 then say("  ⇒ 现在在队伍里，队伍层本该有帧；若下面候选全不在，就是帧名不对（把结果发我）")
  else say("  ⇒ 现在没组队 ⇒ 队伍层/团队层**本该缺席**（这是正常的，不是故障）") end
  -- ① 候选逐个探
  for _, t in ipairs(DF_TARGETS) do
    local row = { key = t.name, label = t.label, hit = nil, cands = {} }
    local list = t.cands or { t.name }
    for i = 1, table.getn(list) do
      local f = dfFrameOf(list[i])
      table.insert(row.cands, list[i] .. (f and "=有" or "=无"))
      if f and not row.hit then row.hit = list[i] end
    end
    if row.hit then say("  " .. t.label .. " → |cff00ff00" .. row.hit .. "|r") 
    else say("  " .. t.label .. " → |cffff6060候选全不在|r（" .. table.concat(row.cands, " ") .. "）") end
    table.insert(dump.targets, row)
  end
  -- ①b ★1.74.32【第 1 步】被动打开层的候选逐个探（**只取证**，这批还没进 DF_TARGETS）
  say("--- 被动打开层候选（只取证，本轮不影响任何行为）---")
  for _, w in ipairs(DF_WIN_CANDS) do
    local row = { group = w.group, label = w.label, hit = nil, cands = {} }
    for i = 1, table.getn(w.cands) do
      local f = dfFrameOf(w.cands[i])
      table.insert(row.cands, w.cands[i] .. (f and "=有" or "=无"))
      if f and not row.hit then row.hit = w.cands[i] end
    end
    if row.hit then
      say("  " .. w.label .. " → |cff00ff00" .. row.hit .. "|r")
    else
      say("  " .. w.label .. " → |cffff6060候选全不在|r（" .. table.concat(row.cands, " ") .. "）")
    end
    table.insert(dump.cands, row)
  end
  -- ② 全 _G 扫「名字像动作条/队伍/团队/被动打开层」的帧（带几何/显隐/父级/层级，便于判断哪个是条、哪个是格子）
  local n, nSkip2 = 0, 0
  if type(_G) == "table" then
    local names = {}
    for k in pairs(_G) do
      if dfFrameLikeGroup(k) then table.insert(names, k) end
    end
    table.sort(names)
    for i = 1, table.getn(names) do
      local nm = names[i]
      local f = dfFrameOf(nm)
      -- ★★两道门（真机踩过之后加的）：
      --   ① `dfFrameUsable`：不可索引的 userdata 直接跳过（否则 `f.GetParent` 抛错打断整个探针）；
      --   ② 只收**帧对象**：真机上光 `ActionButton*` 就有 3000 多个同名子件（贴图/文字/冷却圈），
      --      全塞进存档会把 SavedVariables 灌成大文件，而它们根本不是可拖拽的「层」。
      --      ★判不出类型（`dfObjectType` 返回 nil）时**不敢丢** —— 「查不到 ≠ 没有」。
      if f and dfFrameUsable(f) then
        local ot = dfObjectType(f)
        if ot ~= nil and ot ~= "Frame" then
          nSkip2 = nSkip2 + 1
        else
          n = n + 1
          local br = dfFrameBrief(f)
          local grp = dfFrameLikeGroup(nm) or "?"
          local rec = { name = nm, shown = br.shown, w = br.w, h = br.h, left = br.left, bottom = br.bottom,
            parent = br.parent, level = br.level, group = grp }
          if table.getn(dump.found) < DF_PROBE_FOUND_MAX then table.insert(dump.found, rec) end
          if type(dump.groups[grp]) == "table" and table.getn(dump.groups[grp]) < DF_PROBE_GROUP_MAX then
            table.insert(dump.groups[grp], nm)
          end
          -- 聊天只打前 24 条（不刷屏），全量在存档里
          if n <= 24 then
            say(string.format("  [%s] %s · %s · %sx%s · 父=%s · lv=%s", grp, nm,
              (br.shown == true and "显示" or (br.shown == false and "隐藏" or "?")),
              (br.w and string.format("%.0f", br.w) or "?"), (br.h and string.format("%.0f", br.h) or "?"),
              br.parent, br.level))
          end
        end
      end
    end
    if n > 24 then say("  …还有 " .. tostring(n - 24) .. " 条未在聊天里显示（全量见存档 dragBars.found）") end
  end
  -- ②b ★★兜底扫描（为什么必须有）：**「名字不按套路来」的窗口靠关键词一个都扫不到** ——
  --   本客户端是 UE 重写，窗口完全可能叫 `EHGuildFrame` 之类。被动打开层有个共同形态：
  --   **父级是 UIParent / WorldFrame 的顶层大帧（≥200×150）** ⇒ 按这个形态扫一遍，
  --   真名就捞得出来（清单落存档；聊天只打前 12 条，避免刷屏）。
  local tn = 0
  if type(_G) == "table" then
    -- ★先收名字再**排序**处理：`pairs(_G)` 的遍历顺序不保证（实测各版本不同）⇒
    --   不排序的话「上限 DF_PROBE_TOP_MAX 截掉的是哪一条」是随机的，同一台机器两次跑结果可能不一样。
    -- ★★筛选口径 = **父级对象就是 UIParent / WorldFrame 之一**（`dfTopHost`，按身份判；理由见那边的注释）
    local tnames = {}
    for k in pairs(_G) do
      -- ★只收**字符串键**：`_G` 里理论上可能有非字符串键（别的插件写过），
      --   而下面 `table.sort` 遇到「数字 + 字符串」混排会**直接抛错** —— 那种错会把整个探针打断，
      --   而报错点离现场很远、很难看出原因（本轮真机上探针「什么都没留下」就是这类可怀疑对象之一）。
      if type(k) == "string" then
        local f = dfFrameOf(k)
        -- ★两道门同 ②：不可索引的 userdata 直接跳过（真机原样报错就是栽在这里）+ 只要帧对象
        if f and dfFrameUsable(f) then
          local ot = dfObjectType(f)
          if (ot == nil or ot == "Frame") and dfTopHost(f) then
            local _, _, w, h = dfMeasure(f)
            if w and h and w >= 200 and h >= 150 then table.insert(tnames, k) end
          end
        end
      end
    end
    table.sort(tnames)
    for i = 1, table.getn(tnames) do
      tn = tn + 1
      local nm = tnames[i]
      local f = dfFrameOf(nm)
      if f and tn <= DF_PROBE_TOP_MAX then
        local br = dfFrameBrief(f)
        table.insert(dump.top, { name = nm, shown = br.shown, w = br.w, h = br.h,
          left = br.left, bottom = br.bottom, parent = br.parent, host = dfTopHost(f) or "?",
          level = br.level, group = dfFrameLikeGroup(nm) or "other" })
      end
    end
  end
  say("--- 框体探针（动作条 + 队伍 + 团队 + 被动打开层）：候选命中见上；关键词扫到 " .. tostring(n) .. " 个 ---")
  dump.foundTotal = n
  dump.nonFrameSkipped = nSkip2
  -- ②c ★★匿名窗口取证（父子链走两层）：`_G` 扫描看不见没有名字的窗口，这条能看到，
  --   并靠「具名子件」当身份指纹（真机场景：拍卖行──用户开着窗口却一个候选都没命中）。
  dump.kids = {}
  if type(_G) == "table" then
    local up, wf = rawget(_G, "UIParent"), rawget(_G, "WorldFrame")
    if up then dfKidWalk(up, 1, dump.kids) end
    if wf then dfKidWalk(wf, 1, dump.kids) end
  end
  local kShown = 0
  for _, k in ipairs(dump.kids) do if k.shown == true then kShown = kShown + 1 end end
  say("  父子链取证（UIParent/WorldFrame 往下两层，宽或高 ≥200）：共 " .. tostring(table.getn(dump.kids)) ..
    " 个像窗口的帧，其中**当前显示着**的 " .. tostring(kShown) .. " 个（已落存档 dragBars.kids）")
  if kShown > 0 then
    say("  ↓ 当前显示着的那些（开着窗口时跑这条最有用；「子件」= 身份指纹）：")
    local shownMax = 0
    for _, k in ipairs(dump.kids) do
      if k.shown == true and shownMax < 12 then
        shownMax = shownMax + 1
        say(string.format("    %s · %sx%s · lv=%s · 子件: %s", tostring(k.name),
          tostring(k.w and string.format("%.0f", k.w) or "?"), tostring(k.h and string.format("%.0f", k.h) or "?"),
          tostring(k.level), table.concat(k.kids or {}, " ")))
      end
    end
  end
  if nSkip2 > 0 then
    say("  （另有 " .. tostring(nSkip2) .. " 个同名子件是贴图/文字/冷却圈之类的非帧对象，已跳过）")
  end
  local gl = {}
  for i = 1, table.getn(DF_PROBE_GROUPS) do
    local g = DF_PROBE_GROUPS[i]
    table.insert(gl, g .. " " .. tostring(table.getn(dump.groups[g])))
  end
  say("  分组命中：" .. table.concat(gl, " · "))
  say("  顶层大帧兜底（父级是 UIParent/WorldFrame 且 ≥200×150）：共 " .. tostring(tn) ..
    " 个，前 " .. tostring(table.getn(dump.top)) .. " 个已落存档 dragBars.top")
  if tn > 0 then
    say("  兜底清单前 12 个（这些就是「被动打开层」的候选真身）：")
    for i = 1, math.min(12, table.getn(dump.top)) do
      local t = dump.top[i]
      say(string.format("    %s · %s · %sx%s · 宿主=%s · 父名=%s · lv=%s", t.name,
        (t.shown == true and "显示" or (t.shown == false and "隐藏" or "?")),
        (t.w and string.format("%.0f", t.w) or "?"), (t.h and string.format("%.0f", t.h) or "?"),
        tostring(t.host), tostring(t.parent), tostring(t.level)))
    end
  end
  if table.getn(dump.groups.party) == 0 and (pN or 0) > 0 then
    say("有名有姓的队伍帧一个都没扫到 ⇒ 队伍框多半不叫 Party*（把这份结果发我，我按真名接）")
  end
  if table.getn(dump.groups.raid) == 0 and (rN or 0) > 0 then
    say("有名有姓的团队帧一个都没扫到 ⇒ 团队框多半不叫 Raid*（把这份结果发我，我按真名接）")
  end
  -- ③ 落存档（自己的命名空间，不碰子插件的存档）
  dump.phase = "done"  -- ★完整跑完的标记（与 "start"/"error" 三态区分，见 EVAL_DF_PROBE_MARK）
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then
    cfg.dragBars = dump
    say("已写入存档 EVAL_HELP_CONFIG.dragBars → /reload 后 AI 可直接读（含 cands / groups / top / found）")
  else
    -- ★如实说明：这次没落档（否则用户会以为「跑了就一定存下来了」）
    say("|cffff8080但 EVAL_HELP_CONFIG 不是表（" .. tostring(type(cfg)) .. "）⇒ 本次结果**没能落存档**|r")
  end
  dfLog("探针 bars 完成：候选目标 " .. tostring(table.getn(dump.targets)) ..
    " 个 · 被动层候选 " .. tostring(table.getn(dump.cands)) ..
    " 组 · 关键词命中 " .. tostring(n) .. " · 顶层大帧 " .. tostring(tn))
  return n, dump
end

-- ============ ★★★1.74.33 开窗探针：被动窗口「打开时重设属性」的可行性取证（**只读** · 行为零变化）============
-- 用户问题（原话）：「图层拖拽 -> 被动类窗口能否在打开的时候进行自定义属性重设.或者定时重设? 验证可行性 待我确认」
-- ── 它要回答的四个问题（少一个都定不了方案）：
--   ① 我们写进去的自定义属性（缩放/透明/宽/高），**窗口被打开之后**还是不是我们要的值？
--      被客户端覆盖 ⇒ 「打开即重设」不是可选项而是**必需项**；没被覆盖 ⇒ 这个功能可以不做。
--   ② 「这个窗口被打开了」能不能**可靠侦测**？本客户端没有 `hooksecurefunc`（官方索引里查无此名）
--      ⇒ 只剩三条路：**链式接管 `OnShow`** / 包住 `Show` 方法 / 低频轮询 `IsShown`；风险与代价各不相同。
--   ③ 每个目标**原生有没有** `OnShow` 脚本 —— 有就必须**链式**调原脚本再干自己的事
--      （覆盖式接管 = 直接破坏别人的界面，与「滚轮链式接管」同一纪律）。探针把真值如实记下来。
--   ④ 探针必须**只读**：只 `IsShown/GetWidth/GetHeight/GetScale/GetAlpha/GetLeft/GetBottom`，
--      一个写接口都不碰（判据 = 组 218①：把这些写接口包上计数器 ⇒ 全程必须为 **0**）。
-- ── 用户侧用法：`/eh go 开窗探针` 武装 60 秒 → 依次打开/关闭几个被动窗口 → 结束自动落存档
--   `EVAL_HELP_CONFIG.dragAttr`（`/reload` 后可直接读）。`/eh go 开窗探针 停` 提前收工、`看` 复读上次结果。
-- ── ★有界：60 秒到点自停并**摘掉脚本**（Hide 不阻止 OnUpdate，所以必须摘）—— 不做常驻轮询。
local DF_ATTR_PROBE_SECS = 60
local DF_ATTR_PROBE_PERIOD = 0.25
local DF_ATTR_PROBE_MAX_EV = 150     -- 事件上限（够用即可：避免把存档灌成大文件）
local DF_ATTR_ATTR_KEYS = { "w", "h", "scale", "alpha" }   -- 「属性」（客户端覆盖我们的值 = 这条线）
local DF_ATTR_POS_KEYS = { "left", "bottom" }              -- 「位置」（本项目自己的复查也会动它，要分清）

-- 读一个数值接口（读不到 → nil，**绝不编值**：本项目「查不到 ≠ 没有」纪律）
local function dfAttrPNum(fr, fn)
  local f = fr[fn]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, fr)
  if ok and tonumber(v) then return tonumber(v) end
  return nil
end

-- 采样一个目标：先只读显隐（便宜）；窗口**开着**时才读几何（成本与开着的窗口数成正比）
local function dfAttrPRead(fr, withGeom)
  local o = {}
  if type(fr.IsShown) == "function" then
    local ok, v = pcall(fr.IsShown, fr)
    -- ★本客户端有「返回 1 而不是 true」的 API 先例（IsEventRegistered）⇒ 两种都认，其余当读不到
    if ok then
      if v == true or v == 1 then o.shown = true
      elseif v == false or v == 0 then o.shown = false end
    end
  end
  if withGeom then
    o.w = dfAttrPNum(fr, "GetWidth")
    o.h = dfAttrPNum(fr, "GetHeight")
    o.scale = dfAttrPNum(fr, "GetScale")
    o.alpha = dfAttrPNum(fr, "GetAlpha")
    o.left = dfAttrPNum(fr, "GetLeft")
    o.bottom = dfAttrPNum(fr, "GetBottom")
  end
  return o
end

-- 两次采样之间**真的变了**的项（nil ↔ 数字 也算变化，如实报）
local function dfAttrPDiff(a, b, keys)
  local out = {}
  if type(a) ~= "table" or type(b) ~= "table" then return out end
  for i = 1, table.getn(keys) do
    local k = keys[i]
    if a[k] ~= b[k] then
      table.insert(out, k .. ":" .. tostring(a[k]) .. "->" .. tostring(b[k]))
    end
  end
  return out
end

-- 目标原生**有没有**某个脚本：true=有 / false=明确没有 / nil=这个帧不给读（三态，不许猜）
local function dfAttrPScript(fr, ev)
  if not fr or type(fr.GetScript) ~= "function" then return nil end
  local ok, v = pcall(fr.GetScript, fr, ev)
  if not ok then return nil end
  if v == nil then return false end
  return true
end

-- 存档里「我们想要的值」（用户配的自定义属性；没有记录 = 没配过）
local function dfAttrPSaved(name)
  local store = dfStore(false)
  local rec = (type(store) == "table") and store[name] or nil
  if type(rec) ~= "table" then return nil end
  local s = { w = rec.w, h = rec.h, scale = rec.scale, alpha = rec.alpha, dx = rec.dx, dy = rec.dy }
  if type(rec.base) == "table" then s.hasBase = true end
  if rec.w == nil and rec.h == nil and rec.scale == nil and rec.alpha == nil then return s, false end
  return s, true
end

-- 「存档要的」vs「实测」的差异。返回 **bad, folded** 两个表：
--   bad    = **真不符**（客户端把我们的值改掉了 / 我们的值根本没生效）
--   folded = 「按实测缩放折算后一致」的说明（★不是不符，但必须如实写出来）
-- ★★★1.74.33 第一轮真机取证当场量出来的口径（此前不知道）：本客户端的 `GetWidth/GetHeight` 返回的是
--   **含缩放**的尺寸 —— 属性窗口原生 384×512、我们给它设了缩放 0.7 ⇒ 读回来是 **268.8×358.4**。
--   所以「存档记的宽度（未缩放的配置值）」直接跟它比会**假报不符**：把「缩放已生效」误判成「被客户端覆盖」。
--   判据 = 先比原值；不等再比「存值 × 实测缩放」；两者都不等才算真不符。
local function dfAttrPMismatch(saved, now)
  local bad, folded = {}, {}
  if type(saved) ~= "table" or type(now) ~= "table" then return bad, folded end
  local sc = (type(now.scale) == "number" and now.scale > 0.05 and now.scale <= 20) and now.scale or nil
  local function chk(k, tol, scaled)
    local want, got = saved[k], now[k]
    if type(want) ~= "number" or type(got) ~= "number" then return end
    if math.abs(want - got) <= tol then return end
    if scaled and sc and math.abs(want * sc - got) <= tol then
      table.insert(folded, string.format("%s 折算一致（存%.1f ×缩放%.2f = 实测%.1f）", k, want, sc, got))
      return
    end
    table.insert(bad, string.format("%s 存%.2f→实%.2f", k, want, got))
  end
  chk("w", 1, true) chk("h", 1, true) chk("scale", 0.005, false) chk("alpha", 0.005, false)
  return bad, folded
end

local function dfAttrPEvent(P, kind, name, label, before, after, extra)
  if table.getn(P.events) >= DF_ATTR_PROBE_MAX_EV then
    P.evDrop = dfNum(P.evDrop, 0) + 1 -- 如实记「丢了几条」，不假装全都记下了
    return
  end
  local row = { t = P.elapsed, name = name, label = label, kind = kind, before = before, after = after }
  if extra then row.what = extra end
  table.insert(P.events, row)
end

-- ★真实步进体（OnUpdate 只是薄壳：判据可以直接驱动它，**绝不复刻一遍逻辑**）
local function dfAttrPStep(dt)
  local P = DF.attrProbe
  if not P or P.on ~= true then return false end
  local d = tonumber(dt)
  if not d or d <= 0 then d = DF_ATTR_PROBE_PERIOD end
  P.elapsed = P.elapsed + d
  P.periods = P.periods + 1
  for i = 1, table.getn(P.list) do
    local tgt = P.list[i]
    local fr = dfTargetFrame(tgt)
    local rec = P.tgt[tgt.name]
    if not rec then
      rec = { name = tgt.name, label = tgt.label, opens = 0, closes = 0 }
      P.tgt[tgt.name] = rec
    end
    if not fr then
      rec.missing = true
      P.missing = dfNum(P.missing, 0) + 1
    else
      local sh = dfAttrPRead(fr, false)                      -- 便宜：先看显隐
      local g = nil
      -- ★窗口开着就采几何；关着但**还没有过基线**也采一次（关着的帧同样能读宽高/缩放——
      --   没有这次基线，第一个「开窗」事件的前后对照里 before 就是 nil，而它正是本次取证最要紧的一半）
      if sh.shown == true or type(rec.geom) ~= "table" then g = dfAttrPRead(fr, true) end
      if rec.seen == true then
        if sh.shown == true and rec.shown ~= true then
          -- ① **开窗**：唯一可靠证据 = 上一轮还没显示、这一轮显示了（窗口刚被打开）
          rec.opens = rec.opens + 1
          if not rec.firstOpen then rec.firstOpen = g end
          dfAttrPEvent(P, "open", rec.name, rec.label, rec.geom, g)
        elseif sh.shown ~= true and rec.shown == true then
          -- ② **关窗**：顺手补一次几何采样（关着也能读宽高/缩放 ⇒ 这是「关窗后我们的值」的参照）
          rec.closes = rec.closes + 1
          local gh = dfAttrPRead(fr, true)
          rec.hiddenGeom = gh
          dfAttrPEvent(P, "close", rec.name, rec.label, rec.geom, gh)
        elseif sh.shown == true and type(rec.geom) == "table" and type(g) == "table" then
          -- ③ 窗口**还开着**、值却变了 ⇒ 客户端在开窗之后又改了一次（这才是要抓的现行）
          local dA = dfAttrPDiff(rec.geom, g, DF_ATTR_ATTR_KEYS)
          local dP = dfAttrPDiff(rec.geom, g, DF_ATTR_POS_KEYS)
          if table.getn(dA) > 0 then
            dfAttrPEvent(P, "attrChange", rec.name, rec.label, rec.geom, g, table.concat(dA, ","))
            rec.attrChanges = dfNum(rec.attrChanges, 0) + 1
          elseif table.getn(dP) > 0 then
            -- 位置变了多半是**本项目自己的复查**在重锚（不是客户端）⇒ 与「属性」分开记，免得误判
            dfAttrPEvent(P, "posChange", rec.name, rec.label, rec.geom, g, table.concat(dP, ","))
            rec.posChanges = dfNum(rec.posChanges, 0) + 1
          end
        end
      end
      rec.seen, rec.shown = true, sh.shown
      if g ~= nil then rec.geom = g end   -- ★读不到就**保留上一次的观测**，绝不拿 nil 覆盖掉有效证据
      if sh.shown == true and not rec.firstOpen then rec.firstOpen = g end
    end
  end
  return true
end

local dfAttrPStop -- 前置声明（OnUpdate 里要用它；Lua local 的作用域从声明之后开始）
local function dfAttrPOnUpdate(dt)
  local P = DF.attrProbe
  if not P or P.on ~= true then return end
  local d = tonumber(dt)
  if not d or d <= 0 then d = dfNum(arg1, DF_ATTR_PROBE_PERIOD) end
  if not d or d <= 0 then d = DF_ATTR_PROBE_PERIOD end
  P.acc = (P.acc or 0) + d
  if P.acc < DF_ATTR_PROBE_PERIOD then return end
  local step = P.acc
  P.acc = 0
  -- ★OnUpdate 里抛错会**每帧刷屏**，而且刷屏会掩盖真正的原因 ⇒ 立刻停 + 错误原文落档（三态纪律）
  local ok, err = pcall(dfAttrPStep, step)
  if not ok then
    P.err = tostring(err)
    dfAttrPStop("error")
    say("|cffff6060开窗探针出错已停止|r：错误原文已落存档 `EVAL_HELP_CONFIG.dragAttr.err`；原文：" .. tostring(err))
    return
  end
  if P.elapsed >= DF_ATTR_PROBE_SECS then dfAttrPStop("timeout") end
end

-- 能力清单（这次探针的「可行性」证据：侦测手段与原生脚本现状）
local function dfAttrPCaps()
  local caps = { hooksecurefunc = (type(hooksecurefunc) == "function"), targets = {}, n = 0, onShowYes = 0,
    onShowNo = 0, onShowUnknown = 0 }
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    if tgt.icon == true then
      caps.n = caps.n + 1
      local fr = dfTargetFrame(tgt)
      local row = { label = tgt.label, exists = (fr ~= nil) }
      if fr then
        row.onShow = dfAttrPScript(fr, "OnShow")
        row.onLoad = dfAttrPScript(fr, "OnLoad")
        row.hookType = type(fr.HookScript)   -- ★桩对未知键返回函数 ⇒ 这一项在测试里只能当「有报告」看，不作判据
        row.showType = type(fr.Show)
        row.now = dfAttrPRead(fr, true)      -- 武装那一刻的实测（多半是关着时的值）
        local saved, hasSaved = dfAttrPSaved(tgt.name)
        row.saved = saved
        row.hasSaved = hasSaved and true or nil
        row.badNow, row.foldedNow = dfAttrPMismatch(saved, row.now)
      end
      if row.onShow == true then caps.onShowYes = caps.onShowYes + 1
      elseif row.onShow == false then caps.onShowNo = caps.onShowNo + 1
      else caps.onShowUnknown = caps.onShowUnknown + 1 end
      caps.targets[tgt.name] = row
    end
  end
  return caps
end

-- 落档 + 播报（结束/出错/手动停 都走这里：单一出口）
local function dfAttrPWrite(why)
  local P = DF.attrProbe
  if not P then return nil end
  local now = (type(GetTime) == "function") and GetTime() or nil
  local dump = { phase = "done", why = tostring(why or "?"), secs = DF_ATTR_PROBE_SECS,
    period = DF_ATTR_PROBE_PERIOD, armedAt = P.armedAt, at = now, elapsed = P.elapsed,
    periods = P.periods, targetN = table.getn(P.list), evDrop = P.evDrop, missing = P.missing,
    err = P.err, caps = P.caps, rows = {}, events = P.events }
  -- 逐目标汇总：存档要的 vs **关着时** vs **打开后**（这两条对照就是「要不要做」的答案）
  local openYes, openNo, hidYes, hidNo, foldN = 0, 0, 0, 0, 0
  for i = 1, table.getn(P.list) do
    local tgt = P.list[i]
    local rec = P.tgt[tgt.name] or {}
    local cap = (P.caps and P.caps.targets and P.caps.targets[tgt.name]) or {}
    local saved, hasSaved = dfAttrPSaved(tgt.name)
    local row = { label = tgt.label, exists = cap.exists, hasSaved = hasSaved and true or nil,
      saved = saved, atArm = cap.now, whenHidden = rec.hiddenGeom, atOpen = rec.firstOpen, last = rec.geom,
      opens = rec.opens or 0, closes = rec.closes or 0,
      attrChanges = rec.attrChanges, posChanges = rec.posChanges, onShow = cap.onShow }
    row.badArm, row.foldedArm = dfAttrPMismatch(saved, cap.now)
    row.badOpen, row.foldedOpen = dfAttrPMismatch(saved, rec.firstOpen)   -- ★开窗那一刻的值 vs 存档要的
    row.badLast, row.foldedLast = dfAttrPMismatch(saved, rec.geom)
    if (type(row.foldedOpen) == "table" and table.getn(row.foldedOpen) > 0)
      or (type(row.foldedArm) == "table" and table.getn(row.foldedArm) > 0) then
      foldN = foldN + 1   -- ★「读数含缩放、折算后一致」的目标数（与「真不符」严格分开计数）
    end
    if hasSaved then
      if table.getn(row.badArm) > 0 then hidNo = hidNo + 1 else hidYes = hidYes + 1 end
      if (rec.opens or 0) > 0 then
        if table.getn(row.badOpen) > 0 or (row.attrChanges or 0) > 0 then openNo = openNo + 1 else openYes = openYes + 1 end
      end
    end
    dump.rows[tgt.name] = row
  end
  dump.openMismatch, dump.openOK, dump.armMismatch, dump.armOK = openNo, openYes, hidNo, hidYes
  dump.foldedN = foldN   -- ★折算后一致的目标数（**不计入**不符）
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then
    cfg.dragAttr = dump
    say("结果已落存档 `EVAL_HELP_CONFIG.dragAttr`（/reload 后可直接读）")
  else
    say("|cffff8080但 EVAL_HELP_CONFIG 不是表 ⇒ 本次结果**没能落存档**|r")
  end
  -- 播报（人读的部分：只报能定案的那几行）
  local opens, closes = 0, 0
  for i = 1, table.getn(P.list) do
    local rec = P.tgt[P.list[i].name] or {}
    opens = opens + (rec.opens or 0)
    closes = closes + (rec.closes or 0)
  end
  say(string.format("开窗探针：结束（%s）· 采样 %d 轮 / %.1f 秒 · 开窗 %d 次 · 关窗 %d 次 · 被动窗口 %d 个",
    tostring(why), P.periods, P.elapsed, opens, closes, table.getn(P.list)))
  say(string.format("  · 存档要的属性 vs **关着时**实测：%d 个目标一致 / %d 个不一致",
    hidYes, hidNo))
  say(string.format("  · 存档要的属性 vs **打开后**实测：%d 个一致 / %d 个不一致%s",
    openYes, openNo, (openNo > 0) and "   ← 客户端在开窗时**覆盖**了我们的值（= 需要「打开即重设」）" or ""))
  if foldN > 0 then
    say(string.format("  · 另有 %d 个目标的宽高读数**含缩放**（按折算后与存档一致 ⇒ 不算被覆盖；详见落档 foldedArm/foldedOpen）", foldN))
  end
  local caps = P.caps or {}
  say(string.format("  · 原生 OnShow 脚本：有 %d 个 / 明确没有 %d 个 / 读不到 %d 个（决定「链式接管」怎么挂）· %s",
    dfNum(caps.onShowYes, 0), dfNum(caps.onShowNo, 0), dfNum(caps.onShowUnknown, 0),
    caps.hooksecurefunc and "有 hooksecurefunc" or "无 hooksecurefunc（官方索引里也没有）"))
  -- 逐条列出「打开后与存档不符」的目标（最多 8 条：够定案，也不刷屏）
  local n = 0
  for i = 1, table.getn(P.list) do
    local row = dump.rows[P.list[i].name]
    if row and table.getn(row.badOpen) > 0 and n < 8 then
      n = n + 1
      say(string.format("    · [%s] 打开后：%s", tostring(row.label), table.concat(row.badOpen, " · ")))
    end
  end
  if dfNum(dump.evDrop, 0) > 0 then
    say(string.format("  · ★事件上限已到，另有 %d 条未记（存档里的事件不是全部）", dfNum(dump.evDrop, 0)))
  end
  return dump
end

dfAttrPStop = function(why)
  local P = DF.attrProbe
  if not P then return false end
  P.on = false
  P.why = tostring(why or "?")
  P.stoppedAt = (type(GetTime) == "function") and GetTime() or nil
  -- ★★必须**摘脚本**：本客户端（与 WoW 一致）**隐藏帧的 OnUpdate 照样触发** ⇒ 只 Hide 会永远空转
  if P.frame and type(P.frame.SetScript) == "function" then
    pcall(P.frame.SetScript, P.frame, "OnUpdate", nil)
  end
  dfAttrPWrite(P.why)
  return true
end

-- ============ 对外三个入口（用户命令走它们）============
function EVAL_DF_PROBE_ATTR()
  -- ★三态阶段标记：一进来就留痕（半路死掉也能区分「没跑」与「跑挂了」）
  EVAL_DF_PROBE_MARK("start", nil, "dragAttr")
  local P = { on = true, t = 0, elapsed = 0, periods = 0, acc = 0, tgt = {}, events = {}, list = {},
    armedAt = (type(GetTime) == "function") and GetTime() or nil }
  for i = 1, table.getn(DF_TARGETS) do
    local tgt = DF_TARGETS[i]
    if tgt.icon == true then table.insert(P.list, tgt) end
  end
  if table.getn(P.list) == 0 then
    EVAL_DF_PROBE_MARK("error", "no icon targets", "dragAttr")
    say("|cffff6060开窗探针：一个被动窗口目标都没有|r（目标表为空？）")
    return false
  end
  P.caps = dfAttrPCaps()
  -- ★基准：武装那一刻的实测（caps 阶段**已经读过几何**，哪怕窗口当时关着）—— 它就是「我们写进去的值」的参照；
  --   没有它，第一个「开窗」事件的 before 会是 nil，而**前后对照**正是这次取证最要紧的东西。
  for i = 1, table.getn(P.list) do
    local tgt = P.list[i]
    local cap = P.caps.targets[tgt.name]
    if cap and cap.exists then
      P.tgt[tgt.name] = { name = tgt.name, label = tgt.label, opens = 0, closes = 0,
        seen = true, shown = (cap.now or {}).shown, geom = cap.now }
    end
  end
  DF.attrProbe = P
  local host = dfHost()
  -- ★帧**复用**（存模块级而不是存在 P 里）：重复武装时 CreateFrame 同名帧在真机上会造出重名帧
  --   （重名 = 隐患，本项目 `FRAME NAME CLASH CHECK` 就是为这类事立的）⇒ 只建一次，之后复用。
  if not DF.attrProbeFrame and type(CreateFrame) == "function" then
    DF.attrProbeFrame = CreateFrame("Frame", "EVAL_DF_ATTRPROBE", host)
  end
  P.frame = DF.attrProbeFrame
  if P.frame and type(P.frame.SetScript) == "function" then
    pcall(P.frame.SetScript, P.frame, "OnUpdate", dfAttrPOnUpdate)
  end
  local capN, badN = 0, 0
  for name, row in pairs(P.caps.targets) do
    if row.hasSaved then
      capN = capN + 1
      if type(row.badNow) == "table" and table.getn(row.badNow) > 0 then badN = badN + 1 end
    end
  end
  say(string.format("开窗探针：已武装 %d 秒（每 %.2f 秒**只读**采样一次，一个写接口都不碰）· 被动窗口 %d 个（在位 %d 个）",
    DF_ATTR_PROBE_SECS, DF_ATTR_PROBE_PERIOD, table.getn(P.list), dfNum(P.caps.n, 0)))
  say(string.format("  当前基准：配过自定义属性的 %d 个，其中**现在就与存档不符**的 %d 个（这一行先给你答案的一部分）",
    capN, badN))
  say("  请依次操作：打开一个被动窗口 → 停 2 秒 → 关掉 → 换下一个（属性/好友/技能树/任务/公会…）")
  say("  结束自动落存档 `EVAL_HELP_CONFIG.dragAttr`；也可 `/eh go 开窗探针 停` 提前收工、`看` 复读上次结果")
  if badN > 0 then
    local n = 0
    for name, row in pairs(P.caps.targets) do
      if row.hasSaved and type(row.badNow) == "table" and table.getn(row.badNow) > 0 and n < 5 then
        n = n + 1
        say(string.format("    · [%s] **还没打开**就与存档不符：%s", tostring(row.label), table.concat(row.badNow, " · ")))
      end
    end
  end
  return true
end

function EVAL_DF_PROBE_ATTR_STOP(why)
  if type(DF.attrProbe) ~= "table" then
    say("开窗探针：当前没有在跑的探针（先 `/eh go 开窗探针` 武装）")
    return false
  end
  if DF.attrProbe.on ~= true then
    say("开窗探针：这一轮已经结束了（原因 = " .. tostring(DF.attrProbe.why or "?") .. "）；`看` 可复读上次结果")
    return false
  end
  return dfAttrPStop(why or "manual")
end

-- 复读上次落档的结果（不重新武装）—— 用户想看就直接看，不必去翻存档
function EVAL_DF_PROBE_ATTR_SHOW()
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  local d = (type(cfg) == "table") and cfg.dragAttr or nil
  if type(d) ~= "table" then
    say("开窗探针：存档里还没有结果（先跑一轮 `/eh go 开窗探针`，结束后会自动落档）")
    return false
  end
  say(string.format("开窗探针结果（%s · %s · 采样 %s 轮 / %s 秒 · 开窗 %s 次）：",
    tostring(d.phase), tostring(d.why), tostring(d.periods), tostring(d.elapsed), tostring(d.opens or "?")))
  say(string.format("  · 关着时：%s 一致 / %s 不一致 · 打开后：%s 一致 / %s 不一致",
    tostring(d.armOK), tostring(d.armMismatch), tostring(d.openOK), tostring(d.openMismatch)))
  local n = 0
  for name, row in pairs(d.rows or {}) do
    if type(row) == "table" and type(row.badOpen) == "table" and table.getn(row.badOpen) > 0 and n < 8 then
      n = n + 1
      say(string.format("    · [%s] 打开后：%s", tostring(row.label), table.concat(row.badOpen, " · ")))
    end
  end
  return true
end

-- ============ ★★★1.75.36g 「战斗中底部条组被顶上去」取证探针（**只读** · 行为零变化）============
-- 用户报障（原话）：「进入攻击状态,会把宠物动作栏顶到上面去,排查下」。
-- 真机存档已经证实的两条现状（不用猜，直接从 dragFrames 读出来的）：
--   · PetActionBarFrame 有自定义记录（dx/dy 都在）⇒ 它**是**属性守卫的候选，理论上该被治；
--   · 它的锚点写的是 TOPLEFT ← MainMenuBar / BOTTOMLEFT, 36, 97（基准屏位 371.8, 70.7）
--     ⇒ **宠物条的位置挂在主动作条上**：客户端只要在战斗中重排底部条组，它就会跟着走。
-- ── 这个探针要回答三个问题（少一个都定不了修法）：
--   ① 到底是谁动了（宠物条自己 / 主动作条 / 额外动作条 BonusActionBarFrame）；
--   ② 动到哪（屏幕矩形 + 锚点四元组 + 父级 + 帧层）；
--   ③ 什么时候动（进战斗那一拍 / 战斗中若干拍 / 出战斗）—— 每 0.25s 一拍，**只在真变了的那一拍落一行**。
-- ── 只读取证：IsShown/GetWidth/GetHeight/GetScale/GetAlpha/GetLeft/GetBottom/GetPoint/GetNumPoints/
--   GetParent/GetFrameLevel/IsProtected —— 写接口一个都不碰。
--   战斗进出用 PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED：★**注册得上才认**（pcall 结果如实落档），
--   注册不上也不影响结论 —— 变化检测**不依赖事件名**（这是本项目「事件名不许猜」的落地做法）。
-- ── 用户侧用法：「/eh go 战斗探针」武装 180 秒 → 进战斗打两下 → 出战斗 → /reload → 读存档
--   EVAL_HELP_CONFIG.dragCombat（**有界环 160 行**：这是给 AI 取证用的那一份）。
local DF_CBT_SECS = 180
local DF_CBT_PERIOD = 0.25
local DF_CBT_RING = 160     -- 有界环：头 + 基线 + 变更 + 进出战斗 + 尾
local DF_CBT_CHANGES = 60   -- 变更行上限（防刷屏、防把存档灌大；超了如实记「丢了几条」）
local DF_CBT_SHOW_TAIL = 20 -- 结束/复读时上屏的行数（完整那份在存档里）
local DF_CBT_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
-- 看的帧 = 宠物条 + 它的锚点链 + 四个动作条 + 额外动作条
--   （BonusActionBarFrame 这个名字有本地证据：tools/LayerFix.lua 的真机父级清单里就有它）
local DF_CBT_WATCH = {
  { "PetActionBarFrame", "宠物动作条" },
  { "MainMenuBar", "主动作条" },
  { "MainMenuExpBar", "经验条" },
  { "BonusActionBarFrame", "主动作条内单独动作条" },
  { "ActionButton1", "主动作条第1格" },
  { "MultiBarBottomLeft", "动作条1" },
  { "MultiBarBottomRight", "动作条2" },
  { "MultiBarRight", "动作条3" },
  { "MultiBarLeft", "动作条4" },
}

local function dfCbtParent(fr)
  if type(fr.GetParent) ~= "function" then return "?" end
  local ok, p = pcall(fr.GetParent, fr)
  if not ok then return "读不到" end
  if type(p) == "string" then return p end
  if p and type(p.GetName) == "function" then
    local o2, nm = pcall(p.GetName, p)
    if o2 and type(nm) == "string" and nm ~= "" then return nm end
  end
  return "匿名"
end

local function dfCbtProt(fr)
  if type(fr.IsProtected) ~= "function" then return "无此API" end
  local ok, v = pcall(fr.IsProtected, fr)
  if not ok then return "读不到" end
  return v and "受保护" or "可动"
end

local function dfCbtCap(fr)
  local cap = dfCapture(fr)
  if type(cap) ~= "table" then return "读不到" end
  local p = {}
  for i = 1, table.getn(cap) do
    local a = cap[i]
    if type(a) == "table" then
      table.insert(p, string.format("%s<-%s/%s,%.0f,%.0f", tostring(a[1]), tostring(a[2] or "父级"),
        tostring(a[3]), dfNum(a[4], 0), dfNum(a[5], 0)))
    end
  end
  if table.getn(p) == 0 then return "无锚点" end
  return table.concat(p, " + ")
end

local function dfCbtRead(fr)
  if not fr then return nil end
  local g = dfAttrPRead(fr, true)
  if type(g) ~= "table" then g = {} end
  g.parent = dfCbtParent(fr)
  g.prot = dfCbtProt(fr)
  g.cap = dfCbtCap(fr)
  g.level = dfAttrPNum(fr, "GetFrameLevel")
  return g
end

local function dfCbtGeom(g)
  if type(g) ~= "table" then return "读不到" end
  local l, b, w, h = g.left, g.bottom, g.w, g.h
  return string.format("屏位=%s,%s 尺寸=%sx%s 缩放=%s 透明=%s 显示=%s",
    l and string.format("%.0f", l) or "?", b and string.format("%.0f", b) or "?",
    w and string.format("%.0f", w) or "?", h and string.format("%.0f", h) or "?",
    tostring(g.scale or "?"), tostring(g.alpha or "?"), tostring(g.shown))
end

local function dfCbtRectOf(name)
  local fr = dfFrameOf(name)
  if not fr then return name .. "=不在" end
  local l, b = dfMeasure(fr)
  if not l then return name .. "=读不到" end
  return string.format("%s=%.0f,%.0f", name, l, b or 0)
end

local function dfCbtSummary()
  return dfCbtRectOf("PetActionBarFrame") .. " · " .. dfCbtRectOf("MainMenuBar") .. " · "
    .. dfCbtRectOf("BonusActionBarFrame")
end

-- 两次采样之间**真的变了**的项（nil ↔ 数字 也算变化，如实报）
local function dfCbtDiff(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return nil end
  local p = {}
  if a.left ~= b.left or a.bottom ~= b.bottom then
    local dx = (tonumber(b.left) or 0) - (tonumber(a.left) or 0)
    local dy = (tonumber(b.bottom) or 0) - (tonumber(a.bottom) or 0)
    table.insert(p, string.format("位置 %.0f,%.0f -> %.0f,%.0f（Δ%.0f,%.0f）",
      tonumber(a.left) or -1, tonumber(a.bottom) or -1, tonumber(b.left) or -1, tonumber(b.bottom) or -1, dx, dy))
  end
  if a.parent ~= b.parent then table.insert(p, "父级 " .. tostring(a.parent) .. " -> " .. tostring(b.parent)) end
  if a.cap ~= b.cap then table.insert(p, "锚点 " .. tostring(a.cap) .. " -> " .. tostring(b.cap)) end
  if a.shown ~= b.shown then table.insert(p, "显示 " .. tostring(a.shown) .. " -> " .. tostring(b.shown)) end
  if a.scale ~= b.scale then table.insert(p, "缩放 " .. tostring(a.scale) .. " -> " .. tostring(b.scale)) end
  if a.alpha ~= b.alpha then table.insert(p, "透明 " .. tostring(a.alpha) .. " -> " .. tostring(b.alpha)) end
  if a.level ~= b.level then table.insert(p, "帧层 " .. tostring(a.level) .. " -> " .. tostring(b.level)) end
  if table.getn(p) == 0 then return nil end
  return table.concat(p, " · ")
end

local function dfCbtEvStr(P)
  local p = {}
  if type(P) ~= "table" or type(P.ev) ~= "table" then return "无" end
  for i = 1, table.getn(DF_CBT_EVENTS) do
    local ev = DF_CBT_EVENTS[i]
    local v = P.ev[ev]
    local s = "未尝试"
    if v == true then s = "已注册" elseif v == false then s = "注册失败" end
    table.insert(p, ev .. "=" .. s)
  end
  if P.ev.note then table.insert(p, tostring(P.ev.note)) end
  return table.concat(p, " · ")
end

-- 落环（有界）+ 可选上屏。★上屏走**总闸门**（cfg.log.on），落档不受闸门影响（AI 取证永远拿得到）
local function dfCbtLine(P, line, loud)
  if type(P) ~= "table" or type(P.ring) ~= "table" then return end
  table.insert(P.ring, line)
  while table.getn(P.ring) > DF_CBT_RING do table.remove(P.ring, 1) end
  -- ★★★**边跑边落档**（1.75.36g 真机第一次就白跑了一趟的教训）：环原本只在**结束**那一刻才写进存档，
  --   而用户很可能跑到一半就 `/reload`（或 180s 窗口没走完就退出）⇒ 内存一丢，存档里**一条都没有**、
  --   AI 侧取证直接断链。现在每落一行就把同一个表引用同步给 SavedVariables（零拷贝、零额外成本）。
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then cfg.dragCombat = P.ring end
  if loud then say(line) end
end

local function dfCbtStep(dt)
  local P = DF.cbtProbe
  if not P or P.on ~= true then return false end
  local d = tonumber(dt)
  if not d or d <= 0 then d = DF_CBT_PERIOD end
  P.elapsed = P.elapsed + d
  P.periods = P.periods + 1
  local combat = dfInCombat()
  if combat ~= P.combat then
    P.combat = combat
    dfCbtLine(P, string.format("== %s == t=%.1fs · %s", combat and "★进战斗" or "★出战斗", P.elapsed,
      dfCbtSummary()), true)
  end
  for i = 1, table.getn(DF_CBT_WATCH) do
    local w = DF_CBT_WATCH[i]
    local fr = dfFrameOf(w[1])
    if fr then
      local now = dfCbtRead(fr)
      local prev = P.tgt[w[1]]
      P.tgt[w[1]] = now
      if type(prev) == "table" and type(now) == "table" then
        local line = dfCbtDiff(prev, now)
        if line then
          if P.changes >= DF_CBT_CHANGES then
            P.drop = dfNum(P.drop, 0) + 1 -- ★如实记「丢了几条」，不假装全都记下了
          else
            P.changes = P.changes + 1
            dfCbtLine(P, string.format("%s(%s) %s%s", w[2], w[1], line, combat and " · 战斗中" or ""), true)
          end
        end
      end
    end
  end
  return true
end

local dfCbtStop -- 前置声明（OnUpdate 里要用它；Lua local 的作用域从声明之后开始）
local function dfCbtOnUpdate()
  local P = DF.cbtProbe
  if not P or P.on ~= true then return end
  local d = dfNum(arg1, DF_CBT_PERIOD) -- ★零形参回调：dt 只认全局 arg1
  if d <= 0 then d = DF_CBT_PERIOD end
  P.acc = dfNum(P.acc, 0) + d
  if P.acc < DF_CBT_PERIOD then return end
  local step = P.acc
  P.acc = 0
  -- ★OnUpdate 里抛错会每帧刷屏 ⇒ 立刻停 + 错误原文落档（三态纪律，同开窗探针）
  local ok, err = pcall(dfCbtStep, step)
  if not ok then
    P.err = tostring(err)
    dfCbtStop("error")
    say("|cffff6060战斗探针出错已停止|r：" .. tostring(err))
    return
  end
  if P.elapsed >= DF_CBT_SECS then dfCbtStop("timeout") end
end

-- 落档 + 播报（结束/出错/手动停 都走这里：**单一出口**）
local function dfCbtWrite(why)
  local P = DF.cbtProbe
  if not P then return 0 end
  P.on = false
  if P.frame and type(P.frame.SetScript) == "function" then pcall(P.frame.SetScript, P.frame, "OnUpdate", nil) end
  P.why = tostring(why or "?")
  dfCbtLine(P, string.format("== 战斗探针结束（%s）== 采样 %d 拍 / %.1f 秒 · 变更 %d 条 · 超限丢弃 %d 条 · 事件：%s",
    P.why, P.periods, P.elapsed, P.changes, dfNum(P.drop, 0), dfCbtEvStr(P)))
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then cfg.dragCombat = P.ring end -- ★有界环直接落档（/reload 后 AI 可读）
  local n = table.getn(P.ring)
  say(string.format("战斗探针：结束（%s）· 采样 %d 拍 / %.1f 秒 · 变更 %d 条（完整 %d 行已落存档 EVAL_HELP_CONFIG.dragCombat）",
    P.why, P.periods, P.elapsed, P.changes, n))
  local from = n - DF_CBT_SHOW_TAIL + 1
  if from < 1 then from = 1 end
  for i = from, n do say("  " .. tostring(P.ring[i])) end
  return n
end
dfCbtStop = dfCbtWrite

-- ============ 对外入口（用户命令走它们）============
function EVAL_DF_COMBAT_PROBE()
  if type(CreateFrame) ~= "function" then
    say("战斗探针：本环境不能建帧（CreateFrame 不可用）")
    return false
  end
  local old = DF.cbtProbe
  if type(old) == "table" and old.on == true then
    say("战斗探针：已经在跑了（先 「/eh go 战斗探针 停」 收工，或等它自己到点）")
    return false
  end
  local P = {}
  DF.cbtProbe = P
  P.on, P.elapsed, P.periods, P.acc, P.changes = true, 0, 0, 0, 0
  P.armedAt = (type(GetTime) == "function") and GetTime() or nil
  P.ring, P.tgt, P.ev = {}, {}, {}
  P.combat = dfInCombat()
  dfCbtLine(P, string.format("== 战斗中底部条组探针 == 只读取证 · 每 %.2fs 一拍 · %d 秒到点自停 · 起始：%s",
    DF_CBT_PERIOD, DF_CBT_SECS, P.combat and "已在战斗中" or "不在战斗"))
  for i = 1, table.getn(DF_CBT_WATCH) do
    local w = DF_CBT_WATCH[i]
    local fr = dfFrameOf(w[1])
    if fr then
      local g = dfCbtRead(fr)
      P.tgt[w[1]] = g
      -- ★宠物条那一行**上屏**（它就是报障主角：父级/帧层/受保护三态/锚点一眼可看）；其余只进环
      dfCbtLine(P, string.format("基线 %s(%s) %s · 父级=%s · 帧层=%s · %s · 锚点 %s", w[2], w[1],
        dfCbtGeom(g), tostring(g.parent), tostring(g.level), tostring(g.prot), tostring(g.cap)),
        w[1] == "PetActionBarFrame")
    else
      dfCbtLine(P, string.format("基线 %s(%s) **不在**（本客户端没有这个名字 / 属惰加载）", w[2], w[1]))
    end
  end
  local f = P.frame
  if not f then
    f = CreateFrame("Frame", "EVAL_DF_COMBAT", dfHost())
    P.frame = f
  end
  if type(f.SetScript) == "function" then
    pcall(f.SetScript, f, "OnUpdate", dfCbtOnUpdate)
  end
  if type(f.RegisterEvent) == "function" then
    for i = 1, table.getn(DF_CBT_EVENTS) do
      local name = DF_CBT_EVENTS[i]
      local ok = pcall(f.RegisterEvent, f, name)
      P.ev[name] = ok and true or false -- ★注册不上如实记 false（事件名在本客户端成不成立，这就是证据）
    end
    if type(f.SetScript) == "function" then
      pcall(f.SetScript, f, "OnEvent", function()
        local P2 = DF.cbtProbe
        if not P2 or P2.on ~= true then return end
        dfCbtLine(P2, string.format("（事件 %s @ t=%.1fs）%s", tostring(arg1 or "?"), P2.elapsed, dfCbtSummary()), true)
      end)
    end
  else
    P.ev.note = "该帧不支持 RegisterEvent（只靠变化检测，结论不受影响）"
  end
  say(string.format("战斗探针：已武装 %d 秒（每 %.2fs 只读采一拍，**只记真的变了的拍**）· 事件 %s",
    DF_CBT_SECS, DF_CBT_PERIOD, dfCbtEvStr(P)))
  say("  现在去进战斗打两下再出战斗；「/eh go 战斗探针 看」可复读、「停」提前收工（**边跑边落档**，中途 /reload 也留得住）")
  -- ★总开关关着时**必须点明**（真机第一次报障就是它）：探针只读、照样能取证，但「自动回位」那半边不会工作。
  local master = (type(EVAL_DF_ENABLED) == "function") and (EVAL_DF_ENABLED() and true or false) or nil
  if master == true then
    say("  ★提醒：现在是**编辑模式**（总开关开着）⇒ 本探针照常取证（只读），但**位置不会自动回位**"
      .. "（这正是你要的：编辑时不跟你抢）；摆完把开关关掉 ＝ 守护模式，那时才会自动回位。")
  end
  return true
end

-- 立刻采一拍（命令子命令「采样」用；harness 也走它 —— **不在别处复刻采样逻辑**）
function EVAL_DF_COMBAT_PROBE_TICK(dt)
  local P = DF.cbtProbe
  if not P or P.on ~= true then return 0 end
  local ok = pcall(dfCbtStep, tonumber(dt) or DF_CBT_PERIOD)
  return ok and 1 or 0
end

function EVAL_DF_COMBAT_PROBE_STOP(why) return dfCbtStop(why or "manual") end

-- 复读上次结果（不重新武装）
function EVAL_DF_COMBAT_PROBE_SHOW()
  local P = DF.cbtProbe
  local ring = P and P.ring or nil
  if type(ring) ~= "table" or table.getn(ring) == 0 then
    local cfg = rawget(_G, "EVAL_HELP_CONFIG")
    ring = (type(cfg) == "table") and cfg.dragCombat or nil
  end
  if type(ring) ~= "table" or table.getn(ring) == 0 then
    say("战斗探针：还没有结果（先 「/eh go 战斗探针」，结束后会自动落档）")
    return false
  end
  local n = table.getn(ring)
  say(string.format("战斗探针结果（共 %d 行，列最近 %d 行）：", n, DF_CBT_SHOW_TAIL))
  local from = n - DF_CBT_SHOW_TAIL + 1
  if from < 1 then from = 1 end
  for i = from, n do say("  " .. tostring(ring[i])) end
  return true
end

-- ============ ★★★1.74.34 工具箱那一行 = **模块行**（Toolbox 只留一行数据 + 一个通用嵌入点）============
-- 用户要求（两轮）：
--   ① 「工具箱->拖拽图层 右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，选中的才开启配置和支持拖拽」；
--   ② 「审查下 图层拖拽的功能.在Toolbox.lua 内的代码修改.参考以上也进行./tools 的代码文件归类」
--   ⇒ 原来写在 Toolbox.lua 里的那一段（[设置] 多选下拉 / [重置] 清单 / 两个按钮的 tooltip / 主开关读写代理，
--     共约 128 行）**整体搬进本文件**。Toolbox 侧只剩两样东西：
--       · 模型里**一行数据**：`{ t = "mod", mod = "dragFrames", key = "dbgDrag", label = …, tip = … }`
--         （没有 `noChk` ⇒ 保留主开关勾选框；真值 = `EVAL_DF_ENABLED` / `EVAL_DF_SET`，由下面的 `r.get/r.set` 提供）
--       · 渲染段那个 `elseif it.t == "mod" then` **通用分支**（按 `EVAL_TB_MOD_ROWS[mod]` 取本函数）。
-- ★注册名 "dragFrames" 必须与模型里的 `mod` 一致：对不上 = 那一行**点不动且不报错**（静默）。
--   这条由 `DRAG FRAMES WIRING CHECK` 与通用的 `TB MOD ROW CHECK`（每个模块行都要有同名登记）两边守。
-- ★搬走的只是**界面接线**：所有判定/真值/公式仍在模块自己的函数里（`dfPicked` / `EVAL_DF_PICK_SET` /
--   `EVAL_DF_RESET` / `EVAL_DF_SET` …）—— 工具箱那一侧一行判定逻辑都没有。
local DF_TIP_W = 460   -- tooltip 最小宽度（原 Toolbox 的 `TB_LD_TIP_W`；搬过来后工具箱不再需要那个常量）

-- ============ ★★★1.75.101 重置面板（列表多选 + 确定提交）============
-- 用户：「工具箱->图层拖拽->重置->功能调整: 点击下栏有自定义属性设置的层/窗口列表,支持多选.确定提交重置.」
--   ① 数据源 = `EVAL_DF_CUSTOM_LIST()`（**只列「有自定义属性设置」且已勾选的目标**；未勾选的层不在管理范围 ⇒ 不列）；
--   ② 点一行 = 选中 / 取消（**多选**：绿字 + 绿底）；③ [确定] = `EVAL_DF_RESET_LIST(选中名单)` —— **只重置选中的**；
--   ④ 点面板外面 = 取消（全屏遮罩；**随 root 一起收** —— root 的 OnHide 是唯一收尾出口）。
--   ★★三条路（全局 `EVAL_DF_RESET` / 选中 `EVAL_DF_RESET_LIST` / 图标左键 `dfResetOne`）**共用同一个逐目标体**
--     `DF.resetBody` —— 以后改重置步骤只改一处（反向钉守着「不许再各写一份」）。
--   ★空清单 ⇒ **不开面板**，如实播报「没有任何自定义属性设置，无需重置」（少一个空窗 = 与旧口径一致）。
--   ★★★1.75.102（用户：「重置图层属性增加个全选/取消全选,滚动机制,最大高度」）三条一起上：
--     ① **最大高度** `DF.RST_CAP`：可见窗口 = `min(条数, RST_CAP)`，面板高度 = 顶栏 + 窗口 × 行距 + 底栏
--        ⇒ **不再是**旧写法那套「固定 20 行 + 一行『还有 N 条未列出』」（条数少时留一大片空白、
--        条数多时只能靠「先重置上面这些，再打开一次」两步走）；
--     ② **滚动**：行偏移 `p.off` + 双侧夹 `0..max(0, n - cap)`、滚轮**逐行**、**链式接管**（到边界就交给链上的人，
--        绝不吞别人的滚轮事件）；方向唯一来源 `EVAL_WHEEL_DIR`（全项目同一把尺子，禁位移与方向同号）；
--     ③ **[全选]/[取消全选]**：命中范围 = **清单里的全部条目**（含滚出视口的），不是只选看得见的那几行。
--   ★行控件池`DF.RST_ROWS`**有界**（≥ RST_CAP；1.12 没有销毁帧的 API ⇒ 建一次复用，只 Show/Hide）。
--   ★计数器行 `p.count` **常显**（已选 N / 共 M；需要滚动时再补一段「第 a-b 行 / 共 M」）= 滚动列表的标准件。
--   ★★★全部函数挂 `DF.rstXxx`（**主 chunk 局部量已到 200 上限**：新增一个文件级 local 就整份载不进去）。
DF.RST_ROWS = 20      -- 行控件池上限（建一次复用）
DF.RST_CAP = 16       -- 可见窗口上限 = 面板**最大高度**对应的行数
DF.RST_ROW_H = 18     -- 行距（行高 17 + 1px 缝）
DF.RST_TOPY = 62      -- 第一行距顶部的偏移（标题 / 提示 / 计数器各占一段）
DF.RST_BOT = 38       -- 底栏高度（[全选] 与 [确定] 那一排）
DF.RST_W = 320

-- 收面板（唯一出口；root 的 OnHide 负责把遮罩一起收）
DF.rstHide = function()
  local p = DF.rst
  if type(p) ~= "table" or not p.root then return false end
  pcall(p.root.Hide, p.root)
  -- ★显式收遮罩：root 的 OnHide 仍是**单一出口**，这里是双保险（本客户端偶有不触发 OnHide 的状态；
  --   漏收 = 一个常驻全屏空层把后面所有点击都吃掉 —— 项目在案的老雷）
  if p.cover then pcall(p.cover.Hide, p.cover) end
  return true
end

-- 滚轮方向（唯一来源 `EVAL_WHEEL_DIR`，归一 ±1；桥拿不到就按原始 delta 归一 —— fail-open：
--   ★绝不因为桥缺席就「整条滚不动」，「拿不到证据就一个字节都不碰」在这里的正确用法是「判不出方向就不动」）
DF.rstWheelDir = function(a, b)
  if type(EVAL_WHEEL_DIR) == "function" then
    local ok, d = pcall(EVAL_WHEEL_DIR, a, b)
    if ok and type(d) == "number" then return d end
  end
  if type(b) ~= "number" or b == 0 then return 0 end
  if b > 0 then return 1 end
  return -1
end

-- 滚动（**唯一入口**）：越界 ⇒ 一个字节都不动、**一次都不重画** ⇒ 返回 false 让链上的人接手
--   ★夹取口径与全项目一致（`off` 是行偏移、双侧夹 `0..max(0, n - cap)`）；+1 = 上滚（回到前面）
DF.rstScroll = function(dir)
  local p = DF.rst
  if type(p) ~= "table" or type(dir) ~= "number" or dir == 0 then return false end
  local n = table.getn(p.list or {})
  local cap = p.cap or 0
  local maxOff = n - cap
  if maxOff < 0 then maxOff = 0 end
  local off = (p.off or 0) - dir
  if off < 0 then off = 0 end
  if off > maxOff then off = maxOff end
  if off == (p.off or 0) then return false end
  p.off = off
  DF.rstPaint()
  return true
end

DF.rstPaint = function()
  local p = DF.rst
  if type(p) ~= "table" then return 0 end
  local list = p.list or {}
  local n = table.getn(list)
  local cap = p.cap or 0
  local maxOff = n - cap
  if maxOff < 0 then maxOff = 0 end
  local off = p.off or 0
  if off < 0 then off = 0 end
  if off > maxOff then off = maxOff end
  p.off = off
  local i
  for i = 1, table.getn(p.rows) do
    local row = p.rows[i]
    local it = list[off + i]          -- ★行偏移窗口：第 i 个控件画 list[off + i]
    if type(it) == "table" and i <= cap then
      local on = (p.sel[it.name] == true)
      row.dfName = it.name
      pcall(row.label.SetText, row.label, it.label .. "：" .. table.concat(it.keys, "·"))
      if on then
        pcall(row.label.SetTextColor, row.label, 0.62, 0.95, 0.55)
        dfSolid(row.bg, 0.14, 0.26, 0.16, 1)
      else
        pcall(row.label.SetTextColor, row.label, 0.85, 0.85, 0.85)
        dfSolid(row.bg, 0.10, 0.10, 0.12, 1)
      end
      pcall(row.Show, row)
    else
      row.dfName = nil                -- ★窗口外的行必须**清掉名字**（留着 = 点一下会改到别人的选中态）
      pcall(row.Hide, row)
    end
  end
  -- ★已选计数**只数真选中**：取消选中写的是 sel[k] = false（键还在表里）⇒ pairs 计数会把「取消」也数成选中
  local selN = 0
  local k, v
  for k, v in pairs(p.sel or {}) do if v == true then selN = selN + 1 end end
  -- 计数器行**常显**；需要滚动时补一段「第 a-b 行 / 共 M」（让「还有多少没看到」一眼可见）
  if p.count then
    local txt = string.format(L("TB_LD_RST_COUNT_FMT"), selN, n)
    if maxOff > 0 then
      txt = txt .. "  ｜  " .. string.format(L("TB_LD_RST_RANGE_FMT"), off + 1, off + cap, n)
    end
    pcall(p.count.SetText, p.count, txt)
  end
  -- [全选]/[取消全选]：文案按「是不是全选着」现算 ⇒ 按钮上写的永远等于真值
  local allOn = (n > 0 and selN >= n)
  if p.allb then
    if allOn then pcall(p.allb.label.SetText, p.allb.label, L("TB_LD_RST_UNALL"))
    else pcall(p.allb.label.SetText, p.allb.label, L("TB_LD_RST_ALL")) end
  end
  if p.ok then
    if selN > 0 then pcall(p.ok.label.SetText, p.ok.label, string.format(L("TB_LD_RST_OK_FMT"), selN))
    else pcall(p.ok.label.SetText, p.ok.label, L("TB_LD_RST_OK0")) end
  end
  return selN
end

-- 装填（每次打开都现读；**每次打开清空选中集 + 滚动位置归零** —— 绝不带着上一次的选中悄悄重置）
DF.rstFill = function()
  local p = DF.rst
  if type(p) ~= "table" then return 0 end
  local ok, list = pcall(EVAL_DF_CUSTOM_LIST)
  if not ok or type(list) ~= "table" then list = {} end
  p.list = list
  p.sel = {}
  p.off = 0                 -- ★每次打开都回到第一行（不带着上一次的滚动位置）
  local total = table.getn(list)
  local cap = total
  if cap > DF.RST_CAP then cap = DF.RST_CAP end                  -- ★最大高度：窗口封顶
  if cap > table.getn(p.rows) then cap = table.getn(p.rows) end  -- 池子兜底（池 ≥ RST_CAP，正常不会触发）
  p.cap = cap
  -- 面板高度 = 顶栏 + 可见窗口 × 行距 + 底栏（**最大高度**由 RST_CAP 封顶；条目少就矮一点，不留一片空白）
  if p.root and type(p.root.SetHeight) == "function" then
    pcall(p.root.SetHeight, p.root, DF.RST_TOPY + cap * DF.RST_ROW_H + DF.RST_BOT)
  end
  DF.rstPaint()
  return total
end

-- 打开（空清单 ⇒ 一个字节都不开，如实播报）
DF.rstOpen = function()
  if DF.rstBuild() ~= true then
    say("框拖拽：重置面板建不出来（客户端接口不可用）")
    return false
  end
  local p = DF.rst
  if DF.rstFill() <= 0 then
    say(L("TB_LD_RST_EMPTY"))
    return false
  end
  pcall(p.root.Show, p.root)
  pcall(p.cover.Show, p.cover)
  return true
end

-- [全选]/[取消全选]（**唯一入口**）：范围 = **清单里的全部条目**（含滚出视口的），不是只选看得见的那几行
--   ★「全选着」= 已选数 ≥ 总条数（现算，不看按钮自己那份状态）；取消全选**整表清掉**（不留 false 残键）
DF.rstAll = function()
  local p = DF.rst
  if type(p) ~= "table" then return false end
  local list = p.list or {}
  local n = table.getn(list)
  if n <= 0 then return false end
  local selN = 0
  local k, v
  for k, v in pairs(p.sel or {}) do if v == true then selN = selN + 1 end end
  if selN >= n then
    p.sel = {}
  else
    local i
    for i = 1, n do
      local it = list[i]
      if type(it) == "table" and type(it.name) == "string" then p.sel[it.name] = true end
    end
  end
  DF.rstPaint()
  return true
end

-- [确定]：提交选中名单（一条都没选 ⇒ 如实说 + **面板不关**）
DF.rstOk = function()
  local p = DF.rst
  if type(p) ~= "table" then return false end
  local names = {}
  local list = p.list or {}
  local i
  for i = 1, table.getn(list) do
    local it = list[i]
    if type(it) == "table" and p.sel[it.name] == true then table.insert(names, it.name) end
  end
  if table.getn(names) == 0 then
    say(L("TB_LD_RST_NONE"))
    return false
  end
  DF.rstHide()
  local ok = pcall(EVAL_DF_RESET_LIST, names)
  if ok ~= true then say("框拖拽：重置没跑成（模块接口异常）") end
  if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
  return true
end

-- 建一次复用（1.12 没有销毁帧的 API ⇒ 建出来只 Show/Hide）
DF.rstBuild = function()
  if DF.rst then return true end
  if type(CreateFrame) ~= "function" then return false end
  local host = dfHost()
  local anchorTo = host or rawget(_G, "UIParent")
  local p = { rows = {}, sel = {}, list = {}, off = 0, cap = 0 }
  local cover = CreateFrame("Button", "EVAL_DF_RSTCOVER", host or anchorTo)
  pcall(cover.SetFrameStrata, cover, "FULLSCREEN_DIALOG")
  pcall(cover.SetFrameLevel, cover, 1240)
  if type(cover.SetAllPoints) == "function" and (host or anchorTo) then pcall(cover.SetAllPoints, cover, host or anchorTo) end
  if type(cover.EnableMouse) == "function" then pcall(cover.EnableMouse, cover, true) end
  if type(cover.RegisterForClicks) == "function" then pcall(cover.RegisterForClicks, cover, "LeftButtonUp", "RightButtonUp") end
  cover:SetScript("OnClick", function() DF.rstHide() end)
  cover:Hide()
  p.cover = cover

  local root = CreateFrame("Frame", "EVAL_DF_RESETPANEL", host or anchorTo)
  root:SetWidth(DF.RST_W)
  root:SetHeight(DF.RST_TOPY + DF.RST_CAP * DF.RST_ROW_H + DF.RST_BOT)   -- 开面就是**最大高度**；装填时按真实条数收矮
  p.root = root   -- ★1.75.101：**必须在建完就记住**（漏了这一行 = 面板建得出来、永远不显示 —— 判据当场抓到）
  pcall(root.SetFrameStrata, root, "FULLSCREEN_DIALOG")
  pcall(root.SetFrameLevel, root, 1250)
  if type(root.SetPoint) == "function" and anchorTo then pcall(root.SetPoint, root, "CENTER", anchorTo, "CENTER", 0, 0) end
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  root:SetScript("OnHide", function()
    -- ★单一出口：root 一藏，遮罩跟着藏（漏藏 = 后续点击被一个常驻空层全吃掉）
    if p.cover then pcall(p.cover.Hide, p.cover) end
  end)
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  dfSolid(bg, 0.02, 0.02, 0.02, 0.92)
  local eTop = root:CreateTexture(nil, "BORDER")
  eTop:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  eTop:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  eTop:SetHeight(1)
  dfSolid(eTop, 0.55, 0.48, 0.20, 1)
  local eBot = root:CreateTexture(nil, "BORDER")
  eBot:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  eBot:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  eBot:SetHeight(1)
  dfSolid(eBot, 0.55, 0.48, 0.20, 1)
  local eLeft = root:CreateTexture(nil, "BORDER")
  eLeft:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  eLeft:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  eLeft:SetWidth(1)
  dfSolid(eLeft, 0.55, 0.48, 0.20, 1)
  local eRight = root:CreateTexture(nil, "BORDER")
  eRight:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
  eRight:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  eRight:SetWidth(1)
  dfSolid(eRight, 0.55, 0.48, 0.20, 1)
  local title = root:CreateFontString(nil, "OVERLAY")
  if type(GameFontNormal) ~= "nil" then pcall(title.SetFontObject, title, GameFontNormal) end
  pcall(title.SetPoint, title, "TOPLEFT", root, "TOPLEFT", 10, -8)
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)
  pcall(title.SetText, title, L("TB_LD_RST_TITLE"))
  p.title = title
  local hint = root:CreateFontString(nil, "OVERLAY")
  if type(GameFontHighlightSmall) ~= "nil" then pcall(hint.SetFontObject, hint, GameFontHighlightSmall) end
  pcall(hint.SetPoint, hint, "TOPLEFT", root, "TOPLEFT", 10, -26)
  pcall(hint.SetTextColor, hint, 0.75, 0.75, 0.75)
  pcall(hint.SetText, hint, L("TB_LD_RST_HINT"))
  p.hint = hint
  -- 计数器行（常显）：已选 N / 共 M ｜ 需要滚动时补「第 a-b 行 / 共 M」
  local count = root:CreateFontString(nil, "OVERLAY")
  if type(GameFontHighlightSmall) ~= "nil" then pcall(count.SetFontObject, count, GameFontHighlightSmall) end
  pcall(count.SetPoint, count, "TOPLEFT", root, "TOPLEFT", 10, -44)
  pcall(count.SetTextColor, count, 0.80, 0.86, 0.95)
  pcall(count.SetText, count, "")
  p.count = count
  local i
  for i = 1, DF.RST_ROWS do
    local b = CreateFrame("Button", "EVAL_DF_RSTROW" .. i, root)
    b:SetWidth(DF.RST_W - 20)
    b:SetHeight(17)
    if type(b.SetPoint) == "function" then pcall(b.SetPoint, b, "TOPLEFT", root, "TOPLEFT", 10, -(DF.RST_TOPY + (i - 1) * DF.RST_ROW_H)) end
    if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
    if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
    local rbg = b:CreateTexture(nil, "BACKGROUND")
    rbg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    rbg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    dfSolid(rbg, 0.10, 0.10, 0.12, 1)
    b.bg = rbg
    local fs = b:CreateFontString(nil, "OVERLAY")
    if type(GameFontHighlightSmall) ~= "nil" then pcall(fs.SetFontObject, fs, GameFontHighlightSmall) end
    pcall(fs.SetPoint, fs, "LEFT", b, "LEFT", 4, 0)
    if type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, "LEFT") end
    pcall(fs.SetTextColor, fs, 0.85, 0.85, 0.85)
    b.label = fs
    b:SetScript("OnClick", function()
      local pp = DF.rst
      if type(pp) ~= "table" or type(b.dfName) ~= "string" then return end
      pp.sel[b.dfName] = (pp.sel[b.dfName] ~= true)
      DF.rstPaint()
    end)
    pcall(b.EnableMouseWheel, b, true)
    local rPrev = nil
    if type(b.GetScript) == "function" then
      local okg, g = pcall(b.GetScript, b, "OnMouseWheel")
      if okg and type(g) == "function" then rPrev = g end
    end
    b:SetScript("OnMouseWheel", function(a, bb)
      if DF.rstScroll(DF.rstWheelDir(a, bb)) == true then return end
      if rPrev then pcall(rPrev, a, bb) end
    end)
    b:Hide()
    table.insert(p.rows, b)
  end
  -- 滚轮：面板根 + 每一行都挂（本客户端把滚轮事件给**光标下那个帧**；行铺满列表区 ⇒ 行必须自己会滚）
  --   ★链式接管：到边界（滚不动）就把事件原样转给原来那个处理体，绝不吞别人的滚轮
  pcall(root.EnableMouseWheel, root, true)
  local prevWheel = nil
  if type(root.GetScript) == "function" then
    local okg, g = pcall(root.GetScript, root, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  root:SetScript("OnMouseWheel", function(a, b)
    if DF.rstScroll(DF.rstWheelDir(a, b)) == true then return end
    if prevWheel then pcall(prevWheel, a, b) end
  end)
  -- [全选]/[取消全选]（底栏左）；[确定] 在底栏右 —— 两块并排、绝不重叠
  local allb = dfBtn(root, 120, 20, L("TB_LD_RST_ALL"), "EVAL_DF_RSTALL")
  if type(allb.SetPoint) == "function" then pcall(allb.SetPoint, allb, "BOTTOMLEFT", root, "BOTTOMLEFT", 10, 8) end
  allb:SetScript("OnClick", function() DF.rstAll() end)
  p.allb = allb
  local okb = dfBtn(root, 140, 20, L("TB_LD_RST_OK0"), "EVAL_DF_RSTOK")
  if type(okb.SetPoint) == "function" then pcall(okb.SetPoint, okb, "BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 8) end
  okb:SetScript("OnClick", function() DF.rstOk() end)
  p.ok = okb
  -- ★★★1.75.101：**建完立刻 Hide** —— 客户端新建帧默认是**显示**状态，而空清单那条路是「建出来但不显示」
  --   （不显式 Hide ⇒ 用户点 [重置] 会先看到一个空窗；判据当场抓到）
  pcall(root.Hide, root)
  pcall(cover.Hide, cover)
  DF.rst = p
  return true
end

-- 画「图层拖拽」那一行（`t = "mod"` 的行由工具箱把 `r` 与模型项 `it` 交给这里）
--   ★几何（唯一一套，别处不许再摆一次）：[设置] = `r.add`（cRight−96 宽 44）、[重置] = `r.clr`（cRight−48 宽 40）
--     —— 两块并排、中间留 4px 缝。★★**绝不许用 `r.chv`**（88 宽、起点 cRight−96，与 add 槽**完全重叠**：
--     后建的 chv 压在上面 ⇒ [设置] 永远点不到，而「按钮存在 + 脚本挂上了」的行为断言照样全绿 —— 遮挡是断言盲区）。
local function dfRow(r, it)
  if type(r) ~= "table" then return false end
  -- ① [重置]：清理/还原每一层的缩放·透明度·显隐·位置（真值全在模块里）
  r.clr.text:SetText(L("TB_LDDRAG_RESET"))
  r.clr.btn:Show()
  -- ★1.74.29 修（用户：「自定义信息没显示」）：原写的 subTipDraw / subTipHide 根本不存在
  --   （那两个名字的实现叫 subShowTip/subHideTip，且是子插件行专用、要 a.name/id/key）⇒
  --   `type(...)=="function"` 守卫静默跳过 ⇒ tooltip 什么都不出。现在**直接用 GameTooltip**。
  r.clr.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    -- ★1.74.31 用户要求「信息框宽度大一点」：`GameTooltip:SetMinimumWidth` 是本客户端的正规入口
    --   （api 索引里 category = GameTooltip (widget)）；设了之后每行不再被挤成两三段（无 GetMinimumWidth，不回读）。
    pcall(tip.SetMinimumWidth, tip, DF_TIP_W)
    pcall(tip.SetOwner, tip, r.clr.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, L("TB_LDDRAG_RESET_TIP"), 1, 0.85, 0.30)
    -- ★1.75.101：补一行「点一下会开列表，多选后确定才重置」（三语）
    pcall(tip.AddLine, tip, L("TB_LD_RST_HINT"), 0.75, 0.75, 0.75)
    -- 清单**现读**（不在行渲染期缓存：读的是每一层的当前真值，绝不与别处数字打架）
    if type(EVAL_DF_SUMMARY) == "function" then
      local ok, list = pcall(EVAL_DF_SUMMARY)
      if ok and type(list) == "table" then
        for i = 1, table.getn(list) do
          pcall(tip.AddLine, tip, tostring(list[i]), 0.88, 0.88, 0.88)
        end
      else
        pcall(tip.AddLine, tip, "（读取自定义清单失败）", 0.95, 0.6, 0.5)
      end
    end
    pcall(tip.Show, tip)
  end)
  r.clr.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.clr.btn:SetScript("OnClick", function()
    -- ★★★1.75.101（用户：「工具箱->图层拖拽->重置->功能调整: 点击下栏有自定义属性设置的层/窗口列表,支持多选.确定提交重置.」）：
    --   点 [重置] = 打开**有自定义属性设置**的列表（多选 + 确定才提交），**不再直接全量重置**；
    --   空清单 ⇒ 面板一个字节都不开，如实播报「没有任何自定义属性设置」。
    if type(DF.rstOpen) == "function" then
      pcall(DF.rstOpen)
    else
      pcall(EVAL_DF_RESET)   -- fail-open：面板口拿不到就退回旧的全量重置（绝不静默什么都不做）
    end
    if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
  end)
  -- ② [设置]：图层选择（**多选**下拉；点一项切换、面板不关）
  --   ★控件选型：用项目**现成的多选下拉** `EVAL_DD_OPEN(..., { multi = true, selected, locked })`
  --     （频道行/拦截关键字行同一个件）—— 不新造控件、用户不用重新学。
  --   ★★菜单内容与选中真值**全部来自本模块**（`EVAL_DF_PICK_MENU` / `EVAL_DF_PICK_SET` / `EVAL_DF_PICK_REFRESH`）：
  --     界面侧绝不复刻一份目标表（复刻必漂 —— 以后加一类目标要改两处，漏一处就是「新层在设置里看不到 ⇒
  --     永远选不上」这种静默缺席）。
  r.add.text:SetText(L("TB_LDDRAG_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, DF_TIP_W)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, L("TB_LDDRAG_SET_TIP"), 1, 0.85, 0.30)
    local okc, n, tot = pcall(EVAL_DF_PICK_COUNT)
    if okc and tonumber(tot) then
      pcall(tip.AddLine, tip, string.format(L("TB_LD_PICK_SUM_FMT"), tonumber(n) or 0, tonumber(tot)), 0.88, 0.88, 0.88)
      if (tonumber(n) or 0) <= 0 then
        pcall(tip.AddLine, tip, L("TB_LD_PICK_NONE"), 0.95, 0.60, 0.50)
      end
    else
      pcall(tip.AddLine, tip, "（读取勾选数量失败）", 0.95, 0.6, 0.5)
    end
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    local ok, items, locked, sel, names = pcall(EVAL_DF_PICK_MENU)
    if not ok or type(items) ~= "table" or type(names) ~= "table" then
      say("打开图层选择失败：模块没交回菜单内容（这次没弹出来，不是「没有可选的层」）")
      return
    end
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      -- 分组标题行 names[pi] 为空（locked 行也点不到；这里再兜一层，绝不拿它去写配置）
      local nm = names[pi]
      if type(nm) ~= "string" or nm == "" then return end
      pcall(EVAL_DF_PICK_SET, nm, on == true)
      -- 立刻结算：勾上 → 贴柄/挂图标 + 应用存档；取消 → 收柄/收图标
      pcall(EVAL_DF_PICK_REFRESH)
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = sel, locked = locked })
  end)
  -- ③ 主开关（勾选框）：真值 = `EVAL_HELP_CONFIG.dragFrames.on`，模块没载入时如实告知（不编一个假开关状态）
  r.get = function() return EVAL_DF_ENABLED() and true or false end
  r.set = function(v) return EVAL_DF_SET(v) end
  return true
end

-- 登记进**模块行注册表**（工具箱渲染段按 `it.mod` 取它；两边谁先载入都成立：没有就现建同一个全局表）
local DF_TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(DF_TB_ROWS) ~= "table" then
  DF_TB_ROWS = {}
  rawset(_G, "EVAL_TB_MOD_ROWS", DF_TB_ROWS)
end
DF_TB_ROWS["dragFrames"] = dfRow

