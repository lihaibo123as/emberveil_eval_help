-- ============================================================
-- EH_WorldFog 世界迷雾（S_WorldMap 表驱动全渲染 + 残留清理 + 接管守护）
-- ★★★1.75.56 从 tools/SimpleMap.lua 整族搬出来（用户：「将开启迷雾功能独立个脚本文件代码管理」）——
--   为什么要独立：这一族与「缩放大地图」（黑幕/透明/缩放/位置记忆/探索层折算）是两件独立的事，
--   混在一个文件里时，任何一边的改动都可能把另一边带坏（1.75.52 摘「探索层适配」就是这么连带摘掉的）。
--   · 本文件**只放迷雾**：`MDQ` 全族（渲染/池位/护守/残留清理/贴图来源/开关收尾/体检探针）。
--   · 与 SimpleMap 的往来**一律走桥**（载入期零依赖、调用时才读）：
--       - 本文件要用 SimpleMap 的 **9 个内部件**（见下「桥白名单」）⇒ 由 SimpleMap 暴露 `EVAL_SM_*`，
--         这里用**懒代理**接（见下 `br()` 与代理段）。
--       - SimpleMap 要用本文件的 ⇒ **只有 2 个**（`EVAL_WF_ON` 折算让位 / `EVAL_WF_CMD` 命令分流）。
--   · ★★★1.75.57c「桥白名单」（用户：「世界迷雾功能独立于大地图缩放.**不要做强关联**」）——
--     本模块引用的 `EVAL_SM_*` **只准是这 9 个**：5 个**只读**（地图身份 `MAPINFO`/`MAPKEY`、
--     引擎条数 `NUMOVERLAYS`、有效缩放 `EFFSCALE`、开图信号 `OPEN`）+ 4 个**出口**（播报 `FITSAY`/`FITSAYV`、
--     取证环 `MFLOG`、层名 `FRAMENAME`）。
--     ★为什么**保留**这些只读桥、而不是在两边各抄一份实现（本版评估过、结论是保留）：① 跨文件只走全局桥
--       是项目既定纪律（§4.1「模块只准调全局桥」），这 9 个是**单向、只读、懒读、拿不到就退回「判不出」**
--       的纯读口，不含任何状态；② 抄一份 = 地图身份/有效缩放两套口径各自演化（本项目吃过「同一处真值变两处」
--       的亏），而桥是**一处实现**；③ 两侧同在一个插件里（语法错一起载不进去）⇒ 拆桥换不来任何可用性。
--     ⇒ 真正的「不做强关联」靠**判据**守（`tmp/swm_harness.js` 的白名单钉：本文件出现白名单以外的
--       `EVAL_SM_*`、或引用缩放大地图的开关/命令口 ⇒ 当场转红）。
--   · 载入期**零副作用**（不建帧 / 不挂事件 / 不读写存档 / 不建计时器）：只有表与函数声明。
--   · 载入顺序：`.toc` 里排在 `tools\SimpleMap.lua` **之后**（桥是调用时读，晚载入也不会踩空）。
-- ============================================================

-- 桥读取器：拿到就调，拿不到返回 nil（**绝不缓存** —— 载入期 SimpleMap 可能还没跑完）
local function br(name)
  local f = rawget(_G, name)
  if type(f) == "function" then return f end
  return nil
end

-- ★★★1.75.59o：**`say` / `L` 必须前向声明**（本项目「前向声明老雷」的又一例，`probe_localorder.js` 当场抓到）。
--   症状（真机上是**静默**的）：文件里 1.75.59o/p 的编辑模式整族（以及当年的贴图版本档）
--   整族都写在 `local function say/L` 的**上面** ⇒ 那些 `say(...)` / `L(...)` 全编译成**全局查找** ⇒
--   真机 `attempt to call a global 'say' (a nil value)`；其中一部分还被 `pcall` 包着 ⇒ **一个字都不报、
--   播报整条哑掉**（与 1.75.57c 的 `mfLog`/`smFitSayV` 完全同族）。
--   ⇒ 修法 = **顶部前向声明 + 定义处改赋值**（`say = function(...)` / `L = function(...)`），逻辑一字未改。
--   ★1.75.59p 又补两个：`WF_ECHO_SEC` / `WF_ECHO_AT`（命令回显窗口）—— 编辑模式的**按钮**也要盖章
--     （用户点我们的界面 = 他主动问的，结果必须看得见；不盖章则「调试日志」关着时点了像没反应），
--     而按钮的闭包在它们声明**之前** ⇒ 同样必须前向声明（否则写的是全局、`wfEchoing()` 读的是另一个）。
local say, L, WF_ECHO_SEC, WF_ECHO_AT

-- 配置子树：懒代理（读写都现取 `EVAL_HELP_CONFIG.worldFogCfg`）
--   ★1.75.57c：以前这里写的是「与 SimpleMap 的 EH_SIMPLEMAP_CFG 是同一张表」—— 那从 1.75.56c
--   （迷雾自带配置子树）起就**不成立了**；两边现在是两张互不相干的表。
--   ★拿不到桥时退化成一张**本地孤儿表**（功能等于关着）—— 绝不抛错、也绝不静默改别人的表。
local function wfLive()
  -- ★★★1.75.56c（用户：「世界迷雾功能独立于大地图缩放.不要做强关联.」）：本模块**自己的配置子树**
  --   `EVAL_HELP_CONFIG.worldFogCfg` —— 开关 / 藏账 / 探针环 / 一次性标记全在这里，
  --   **不再**寄在 `simpleMapCfg`（那是「缩放大地图」的子树）里 ⇒ 那个模块怎么改都动不到迷雾的设置。
  --   ★与项目纪律一致：跨文件只走全局（`EVAL_HELP_CONFIG`），且**调用时读**（载入期那是空表 = 老雷）。
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then c = {} rawset(_G, "EVAL_HELP_CONFIG", c) end
  if type(c.worldFogCfg) ~= "table" then c.worldFogCfg = {} end
  return c.worldFogCfg
end
local SM_CFG = setmetatable({}, {
  __index = function(_, k) return wfLive()[k] end,
  __newindex = function(_, k, v) wfLive()[k] = v end,
})

-- 一次性迁移：老存档里迷雾的键在 `simpleMapCfg`（与「缩放大地图」共用），搬到自己的子树后**从老表删掉**。
--   ★搬不到也不影响行为：`swmOverlay`/`staleClean` 1.75.59c 起**缺省就是「关」**（载入期会落成显式 false），
  --     其余（藏账/探针环/一次性标记）只是历史记录。
local WF_MIGRATE_KEYS = { "cacheCleared51", "mapFitMode", "mapFitVerbose", "perfProbe", "probeCleared52", "staleClean", "staleLog", "swmOverlay" }
local function wfMigrate()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return 0 end
  local dst, src = c.worldFogCfg, c.simpleMapCfg
  if type(dst) ~= "table" or type(src) ~= "table" then return 0 end
  local n = 0
  for _, k in ipairs(WF_MIGRATE_KEYS) do
    if dst[k] == nil and src[k] ~= nil then dst[k] = src[k] src[k] = nil n = n + 1 end
  end
  return n
end

-- 以下 8 个别名与 SimpleMap 里的同名内部件**逐字同签名**（惰性转发全部返回值）
local function smMapInfo()
  local f = br("EVAL_SM_MAPINFO")
  if f then return f() end
end
local function smMapKey()
  local f = br("EVAL_SM_MAPKEY")
  if f then return f() end
end
local function smNumOverlays()
  local f = br("EVAL_SM_NUMOVERLAYS")
  if f then return f() end
end
local function smEffScale(fr)
  local f = br("EVAL_SM_EFFSCALE")
  if f then return f(fr) end
end
local function smFitSay(...)
  local f = br("EVAL_SM_FITSAY")
  if f then return f(...) end
end
local function smFitSayV(...)
  local f = br("EVAL_SM_FITSAYV")
  if f then return f(...) end
end
local function mfLog(...)
  local f = br("EVAL_SM_MFLOG")
  if f then return f(...) end
end
local function frameName(v)
  local f = br("EVAL_SM_FRAMENAME")
  if f then return f(v) end
  return "?"
end

local MDQ = {}

-- ★★★1.75.59l：**改动记号**（手动维护，改本文件顺手改一次）。
--   用途唯一 = 回答「**客户端现在跑的是哪一份代码**」：
--     · 磁盘上源码的时间戳我能查，但**客户端内存里载入的是哪一份**查不到；
--     · 真机现场一旦出现「用户说跑过了、存档里却没有读数」，第一件事就是分辨
--       「命令没跑成」与「跑的是旧版（那条命令在旧版里根本不存在）」—— 那时只看这个键就能立刻定性。
--   它落在两个地方：① 载入期写进存档 `worldFogCfg.buildTag`（**只要 /reload 过就一定有**）；
--   ② `/ehm mapfit 自检` 的落盘环表头与 `[1] 环境` 行（跟着那一次的读数一起存）。
MDQ.BUILD = "1.76.6"

-- ★★★1.75.60b：**编辑模式里的两个视图开关**（用户：「编辑模式右侧增加原始贴图层的显示和隐藏,迷雾贴图层的显示和隐藏」）
--   用途 = 逐块对位时的「对照看」：把**客户端自己的探索层**放出来、把我们画的迷雾层收起来 ——
--          四种组合一眼看清「我们画的块和客户端原来那张图差在哪」。
--   ★三条口径（缺一条就会留下脏状态或「点了没反应」）：
--     ① **不落存档**：这是「看」的开关、不是配置 ⇒ 只存会话；`editSet(false)` 当场复位成
--        「原始隐藏 / 迷雾显示」（= 没开编辑模式时的常态）⇒ 永远不会留下「关掉编辑模式后地图上多一层」。
--     ② ★★★**不是让按钮自己去 `Show`/`Hide` 就完事**：接管守护（`holdTick`）每拍都在藏客户端原生层、
--        每拍都在复位我们自己的画布 ⇒ 按钮刚改完、下一拍就被守护改回去（用户看到的就是「点了没反应」）。
--        ⇒ 唯一开关 = **守护自己让位**（`holdTick` 开头按这两个标志决定这一拍动不动手）。
--     ③ **迷雾贴图层只收「我们画的块」**：金色拖拽柄是编辑 UI，照旧留着 —— 否则关了迷雾就没得拖了。
MDQ.showNative = false   -- 「原始贴图层」：false（默认）= 藏掉客户端的原生探索层（= 现行行为，零变化）
MDQ.showFog = true       -- 「迷雾贴图层」：true（默认）= 显示我们画的块
MDQ.viewNative = function() return MDQ.showNative == true end
MDQ.viewFog = function() return MDQ.showFog ~= false end
-- 「这一拍真的要**让客户端原生层露出来**吗」= 编辑模式开着 ∧ 视图开关开着
--   ★为什么还要挂 `editOn()`：标志只在编辑模式里有意义 ⇒ 万一有哪条路没走到复位，
--     也不至于在编辑模式之外把客户端的层放出来（宁可多藏，绝不把地图弄成两套）。
MDQ.liveNative = function() return (MDQ.showNative == true) and (MDQ.editOn ~= nil) and (MDQ.editOn() == true) end
-- 「这一拍真的要**把我们画的块收起来**吗」—— 同理（拿不到 `editOn` ⇒ false ⇒ 照常显示）
MDQ.liveFogOff = function() return (MDQ.showFog == false) and (MDQ.editOn ~= nil) and (MDQ.editOn() == true) end

-- ★★★「残留图层清理」的节拍与有界上限（★1.75.52 摘除探索层适配时**误删过一次** ⇒ 常量一律留在 MDQ 表上、
--   紧挨着表定义，别再夹在别的族中间）。
MDQ.STALE_GAP = 0.25      -- 换图/开图窗口内的扫描节拍（客户端这时还在重摆/重指贴图，扫密一点）
MDQ.STALE_GAP_IDLE = 1.0  -- 窗口外的节拍（非区域地图上照样把「又冒出来的」叠加层再藏掉）
MDQ.STALE_SEC = 3.0       -- 「换图 / 开图」后的快扫窗口长度（窗口内 0.25s 一拍）
MDQ.STALE_LOG_MAX = 40    -- 「藏了哪些纹理」的**有界落盘环**上限（`SM_CFG.staleLog`，最新在前）
-- ★★★**同一处误删的还有这张表**（真机红字：`bad argument #1 to 'pairs' (table expected, got nil)` @ tick 里那行）：
--   `MDQ.staleHid` = **藏账**（纹理对象 → { name = 层名, path = 当时的贴图 }）；区域图上全部还回时清空。
--   ⇒ 与上面四个常量一起留在表定义旁边；★纪律：**摘除大块代码后必须做一次「状态初始化审计」**
--     （凡是挂在 `MDQ` / 原先那张 `SMFIT` 上的状态表，逐个确认还有没有创建点）—— 光跑语法闸门与 scan_dangling **抓不到这种雷**。
MDQ.staleHid = {}         -- 藏账：纹理对象 → { name = 层名, path = 当时的贴图 }（区域地图上**全部还回**并清账）

MDQ.TILE = 256       -- Mozz 口径的分块边长
MDQ.poolMax = 240    -- 纹理池上限（防病态表把纹理建爆；撞上就如实报「上限已满」）
MDQ.own = {}         -- 我们自己补建的纹理：池位号 → 纹理对象（跨帧复用，绝不每帧新建）
MDQ.made = {}        -- 同上（按名字记；收层时一起清）
MDQ.ownSet = {}      -- 同上但按**对象身份**记（`MDQ.own[n] = 纹理` ⇒ 反查「这张是不是我们自建的」）：
                     --   ★1.75.52 六改「接管守护」要用它区分「客户端原生层」与「我们自己画的层」——
                     --   名字判定不够（本客户端那批原生层也叫 `WorldMapOverlay<n>`，我们补建的还可能与之重名）。
MDQ.poolSeen = 0     -- 见过的最大池位号（收尾 Hide 只扫到它，不空扫 poolMax 次）
MDQ.newN = 0         -- **本轮**新加了几张（渲染行如实报「客户端既有 N ｜ 新加 M」）
MDQ.saidMk = nil     -- 上一张已播报过的地图（每图只报一次，不刷屏）

-- ★★★1.75.54 **性能收口（1.75.53 真机报障「开了十几个地区以后游戏会卡死」换来的）** —— 三处：
--   ① **写前比对**（`MDQ.slot`）：每块记住「上次写进去的 (地图/区域/块号/倍率/对象)」，
--      完全一样就**一个 `Set*` 都不发** ⇒ 稳态（没换图/没缩放）每拍零写；
--      这也是唯一能保证「不因为反复 `SetTexture` 而反复取贴图文件」的做法。
--   ② **护守只在节流那一拍跑**（逐帧重申那条 silent 路径**不跑** `holdTick`）⇒
--      每帧 `GetRegions()` + 逐 region `GetName()` 的字符串风暴消失。
--   ③ **爆发窗不许被我们自己的写入反复重新武装**（原来 `es` 抖 0.001 就重置 2s 窗口，
--      而我们每拍都在写几何 ⇒ 窗口永不结束 = **每帧整张图重写**）；现在只认**引擎真值**变化，
--      且重新武装有**最小间隔** + 窗口内**帧数上限**，超了如实出声并降档。
MDQ.slot = {}            -- 池位号 → { tex=, file=, area=, tile=, k=, shown=true }（写前比对用）
MDQ.wroteN = 0           -- 本拍**真发出去的**写次数（取证用；稳态应为 0）
MDQ.skipN = 0            -- 本拍因「内容没变」跳过的块数（取证用）
MDQ.SLOW_MS = 12         -- ★安全阀：单拍渲染超过这个毫秒数 ⇒ 降档（宁可少重申，绝不卡死）
MDQ.SLOW_WARN_MS = 6     -- 连续 3 拍超过它 ⇒ 也降档（提前刹车）
MDQ.perfGuard = false    -- 已降档标记（本会话）；`/ehm mapfit perf` 可看、`重启/关开关`复位
MDQ.perfRing = {}        -- 有界取证环（最近 12 拍：{ ms, wrote, skip, n, seen, k }）
MDQ.PERF_RING_MAX = 12

-- ===== ★★★1.75.53：贴图**来源**解析 + 存在性探针（发布独立性；用户：「插件要绝对独立，
--   依赖的东西要复制到插件内自己载入，不然发布上去别人又可能找不到贴图」）=====
--   ① **自带贴图优先**：`EvalHelp\media\WorldMap\<地图>\<区域><块号>` —— 只要那份**能加载**就用它
--      ⇒ 把贴图拷进 `media/WorldMap/` 就自动变成完全自包含（不用改一行代码）。
--   ② 否则退回**客户端自带** `Interface\WorldMap\<地图>\<区域><块号>`（1.12 客户端的探索层美术，
--      与上游 `S_WorldMap` 逐字同口径，见 `Modules/MapOverlay.lua:744/835`）。
--   ③ 两份都**加载不出来** ⇒ `"none"` ⇒ **这一张图不接管**（不渲染、不藏原生、如实出声一次）
--      —— 依据本项目铁律「拿不到证据就一个字节都不碰」：宁可保持客户端原样，也绝不画出一片空白图。
--   ★探针口径：新建一张**不设宽高**的纹理 ⇒ `SetTexture(p)` ⇒ 读 `GetWidth/GetHeight`（客户端报的是
--     **贴图文件**的像素尺寸）。文件在 ⇒ >0；文件不在 ⇒ 0；**读不到/判不出 ⇒ nil = 不拦**（fail-open：
--     判据本身没把握时绝不把功能关死；只有明确探到 0 才判定「没有」）。
--   ★探针纹理**每次新建一张**（匿名、不 Show；1.12 没有销毁纹理的 API ⇒ 泄漏无害），
--     结果按路径缓存（`MDQ.tpOK`）⇒ 每张图最多建两张，绝不逐块探。
MDQ.tpOK = {}        -- 路径 → true/false（会话级缓存；nil = 没探过或判不出）
MDQ.texSrc = {}      -- 地图 → "own" | "client" | "none"（每图只判一次，缓存）

MDQ.probeTex = function(path)
  local c = MDQ.tpOK[path]
  if c ~= nil then return c end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") or type(fr.CreateTexture) ~= "function" then return nil end
  -- ★每次**新建**一张探针纹理（不复用）：复用有「上一次的文件尺寸残留 ⇒ 探出假结果」的风险；
  --   结果按路径缓存 ⇒ 每张图最多建两张，代价可忽略（匿名、不 Show、不进我们的池位）。
  local ok, t = pcall(fr.CreateTexture, fr, nil, "ARTWORK")
  if not ok or t == nil then return nil end
  if type(t.SetTexture) ~= "function" or type(t.GetWidth) ~= "function" then return nil end
  if not pcall(t.SetTexture, t, path) then return nil end
  local okw, w = pcall(t.GetWidth, t)
  local okh, h = pcall(t.GetHeight, t)
  if not (okw and okh) then return nil end
  local w2, h2 = tonumber(w), tonumber(h)
  if w2 == nil and h2 == nil then return nil end -- 判不出 ⇒ 不拦（fail-open）
  local ok2 = (w2 or 0) > 0 and (h2 or 0) > 0
  MDQ.tpOK[path] = ok2 and true or false
  return ok2 and true or false
end

-- ★★★探针的**负对照**（1.75.53b 真机报障换来的）：本客户端**对「文件不存在」的报法并不一致** ——
--   `.blp` 这种带扩展名的路径**明明没有文件，也可能报出非 0 尺寸** ⇒ 只按「>0 = 有」判，会**把没有的
--   当成有** ⇒ 整张图都去加载**不存在的自带贴图** ⇒ 用户眼里的「去迷雾贴图没生效了」（我们画的块全空）。
--   ⇒ 每个写法都配一张**同目录、同后缀、不可能存在**的对照路径：
--     ① 对照也说「有」⇒ 这个写法**读不出真假** ⇒ 返回 nil（判不出）；
--     ② 判不出 ⇒ 一律**退回客户端那份**（= 一直可用的行为；依据铁律「拿不到证据就一个字节都不碰」）。
MDQ.probeBogus = "__eh_nosuch__"
MDQ.probeTrust = function(path)
  local r = MDQ.probeTex(path)
  if r == nil then return nil end
  local p = tostring(path)
  local dir = string.gsub(p, "[^\\]*$", "")          -- 去掉文件名 → 留目录（含结尾反斜杠）
  local e = string.find(p, "%.[A-Za-z0-9]+$")
  local ext = (e ~= nil) and string.sub(p, e) or ""  -- 同后缀（负对照也要走同一条解析路）
  if MDQ.probeTex(dir .. MDQ.probeBogus .. ext) == true then return nil end
  return r
end

-- 自带贴图的路径前缀（相对插件目录；`media\WorldMap\...` 是可选的「自己载入」那一份）
MDQ.ownPfx = "Interface\\AddOns\\EvalHelp\\media\\WorldMap\\"
MDQ.cliPfx = "Interface\\WorldMap\\"

-- ★★★自带那份的**写法（后缀）必须逐个试**：本客户端对**插件目录里的散装文件**要求**写扩展名**
--   （已在案：`media\Flags\<名>.tga` 就是这么写进 `SetTexture` 的，见 `EvalHelp.lua:1521`），
--   而客户端自带的美术在**归档**里，一律**不写扩展名**（上游 `S_WorldMap` 同款）。
--   ⇒ 依次试 `.blp` → `.tga` → 不写，**哪个能加载就用哪个**（判据 = 探针读得到文件尺寸）。
MDQ.ownForms = { ".blp", ".tga", "" }
MDQ.srcPick = {}     -- 地图 → 选中的来源键："own:blp" / "own:tga" / "own:raw" / "client" / "none"
                     --   （`texPath` 按它拼；`srcOf` 把前三种归一成 "own"）
-- ★★★1.75.60z：**「贴图版本（分版本贴图）」整套已按用户指令清理掉** —— 原话：「清理功能: MDQ.packs 虽然还列着
--   live/p9 清理掉图层渲染机制」。原机制 = `MDQ.packs`（base/live/p9）+ `worldFogCfg.texPack` +
--   `media\WorldMap\_v\<版本>\…` 目录 + `/ehm mapfit 贴图版本` 命令 + `MDQ.packSet/packLines/packCount/
--   packOf/ownPfxOf/hintOf/packForgetCounts/srcForget/packHint/packKey` + 三语 `TB_SM_PACK_*`。
--   ★删除理由（用户实测）：`_v` 目录已删、三档贴图**看不出差异** ⇒ 多版本只会让来源判定多走几条探测、
--     并在「本版本没装这张图」时多绕一圈；来源判定回到**一条路**。
--   ★清理后**行为 = 原默认档（base）**（`texPack` 原默认就是 base ⇒ 零回归）：自带 `media\WorldMap\` → 客户端。
--   ★存档里的 `texPack` 键在载入期一次性清掉（见文件末尾的清账块），不留死键混淆以后的排查。

MDQ.ownExtOf = function(key)
  local s = tostring(key)
  local e = string.match(s, ":(%w+)$")       -- "<版本>:blp" / "<版本>:raw" / "own:blp"（老键也认）
  if e == nil then return "" end
  if e == "raw" then return "" end
  return "." .. e
end

-- 本图的贴图来源（每图判一次，缓存）："own:blp" / "own:tga" / "own:raw" / "client" / "none"
--   ★1.75.60z：**只剩一条路**（自带 `MDQ.ownPfx` → 客户端）；分版本那套已清理（见上）。
MDQ.srcKey = function(file)
  local s = MDQ.srcPick[file]
  if s ~= nil then return s end
  local m = MDQ.artTbl(file)     -- ★1.75.64：**永远看彩图那份表**（结果按图名缓存 ⇒ 绝不被实景模式污染）
  local areas = {}
  if type(m) == "table" then for a in pairs(m) do table.insert(areas, a) end end
  table.sort(areas)
  local a0 = areas[1]
  if a0 == nil then MDQ.srcPick[file], MDQ.texSrc[file] = "none", "none" return "none" end
  local unclear = false
  for _, ext in ipairs(MDQ.ownForms) do
    local own = MDQ.probeTrust(string.format("%s%s\\%s1%s", MDQ.ownPfx, file, a0, ext))
    if own == true then
      local key = "own:" .. ((ext == "") and "raw" or string.sub(ext, 2))
      MDQ.srcPick[file], MDQ.texSrc[file] = key, "own"
      return key
    end
    if own == nil then unclear = true end
  end
  local cli = MDQ.probeTrust(string.format("%s%s\\%s1", MDQ.cliPfx, file, a0))
  -- ★只有**明确探到「没有」**（false）才判 none；`nil`（判不出）按「客户端有」处理 —— 不拦、不关功能。
  if cli == false and not unclear then
    MDQ.srcPick[file], MDQ.texSrc[file] = "none", "none"
    return "none"
  end
  MDQ.srcPick[file], MDQ.texSrc[file] = "client", "client"
  return "client"
end

-- 本图的贴图来源（**三态**，给播报与外部读）：own（自带那份可用）/ client（客户端美术）/ none（都不行）
MDQ.srcOf = function(file)
  local k = MDQ.srcKey(file)
  if k == "none" then return "none" end
  if k == "client" then return "client" end
  return "own"
end

-- ============================================================
-- ★★★1.75.64：**图层类型（区域彩图 / 区域实景）** —— 用户原话：
--   「工具箱->关闭世界迷雾->设置: 区域彩图,区域实景,单选,实景数据源载入由之前验证成功的 jpg 方式载入.\media\WorldMapJpg」
--   · **区域彩图**（`MDQ.LAYER_ART`）= 现行那套：按 `MapOverlayData.lua` 逐区域/逐块贴
--     `media\WorldMap\<图>\<区域><块>.blp`（游戏世界地图那张手绘图）。
--   · **区域实景**（`MDQ.LAYER_JPG`，★1.75.65 起的**默认档**）= **整区一张** `media\WorldMapJpg\<图>.jpg`（地形实拍拼接）——
--     载入写法 = **不带扩展名**（1.75.62 真机验证（当时的「贴图格式测试」工具已在 1.75.69 清理，结论见 CHANGELOG 1.75.62）：插件目录里的散装 JPG 能画）。
--   ★真值 = `SM_CFG.layerMode`（"art" / "jpg"）；**只有显式 "art" 才是彩图** ⇒ 缺键/垃圾值一律实景
--     （★1.75.64 时是反过来的：那时只有显式 "jpg" 才是实景 —— 用户 1.75.65 点名把默认档改成实景）。
--   ★四条纪律（缺一条就会出「切换没生效 / 残留层压住新层 / 性能异常 / 数据串味」）：
--     ① **切换走唯一写口 `MDQ.layerSet`**：先 `MDQ.release`（把这一路动过的三样全部交还）**再**换真值
--        —— 顺序反了，上一套的几何会留在客户端池位上（用户看到的就是「切换了没反应」）。
--     ② **切换要按「关断四件事」做**：资源回收（收自建层 + 还回复用池位原值 + 藏过的原生层全部 Show）·
--        节拍停止（切完这一拍由 `beatSync` 按需重挂，**不新增常驻**）· 数据重置（编辑模式的会话态全部清零：
--        选中集 `sel` / 逐块隐藏 `blkHide` / 悬停 `hoverIdx` / 闪光 `flashAt` / 图层池账 `slot`）·
--        图层清理（两套的层不共存 —— 渲染收尾 `hideFrom` 天然收干净，切换那一刻先 `release` 一次）。
--     ③ **实景层渲染优先级最高**：写进 **`OVERLAY`** 绘制层（彩图那批在 `ARTWORK`）⇒ **同组内遮盖其它层**；
--        客户端池位的原绘制层随**原值账**还回（原值第 7 样，见 `origGrab` / `origRestore`）。
--     ④ **两套的补偿数据分家**：彩图 → `worldFogCfg.edit` / `MapOverlayOffset.lua`；
--        实景 → `worldFogCfg.editJpg` / `MapOverlayOffsetJPG.lua`。`editTbl`/`editFileTbl` 按模式**换根**
--        ⇒ 编辑模式那一整族（拖拽/箭头/尺寸/列表/重置/体检）**一行不改**就跟着走
--        —— 键形态仍是 `区域#块号`，实景的伪区域 = `MDQ.JPG_AREA`（`_JPG#1`）。
MDQ.LAYER_ART, MDQ.LAYER_JPG = "art", "jpg"
MDQ.JPG_AREA, MDQ.JPG_TILE = "_JPG", 1
-- ★★★1.75.65（用户：「默认设置 开启世界迷雾->选中实景地图,关闭彩图」）：
--   **默认档 = 区域实景** —— `worldFogCfg.layerMode` 为 nil（老存档 / 从没写过）⇒ **实景**；
--   ★**用户显式选过彩图（`"art"`）⇒ 保持彩图**（白名单式判定：只有 `"art"` 算彩图，其余一律实景 ——
--     绝不留「nil/垃圾值」这种半状态，也绝不用 `or` 顶改用户的选择）。
--   ★载入期会把它**落成显式值**并**如实播报一次**（行为改变必须出声，见文件末尾清账块）。
MDQ.layerMode = function()
  local v = (type(SM_CFG) == "table") and SM_CFG.layerMode or nil
  return (v == MDQ.LAYER_ART) and MDQ.LAYER_ART or MDQ.LAYER_JPG
end
MDQ.jpgMode = function() return MDQ.layerMode() == MDQ.LAYER_JPG end

-- 实景基线表（生成物 `MapOverlayJPGData.lua`；懒读 + **大小写不敏感**，与 `MDQ.areaOf` 同口径）
MDQ.jpgTbl = function()
  local t = rawget(_G, "EVAL_MAP_OVERLAY_JPG_DATA")
  if type(t) ~= "table" then return nil end
  return t
end
-- 本图的实景基线记录（`{ 宽, 高, 偏移x, 偏移y }`，帧空间）；表里没有 ⇒ nil ⇒ **本图不接管**
MDQ.jpgBase = function(file)
  if type(file) ~= "string" or file == "" then return nil end
  local t = MDQ.jpgTbl()
  if t == nil then return nil end
  local r = t[file]
  if type(r) == "table" then return r, file end
  local low = string.lower(file)
  for k, v in pairs(t) do
    if type(k) == "string" and type(v) == "table" and string.lower(k) == low then return v, k end
  end
  return nil
end

-- 实景贴图路径：**不带扩展名**（真机验证过的写法；插件目录里的散装 JPG）
MDQ.jpgPfx = "Interface\\AddOns\\EvalHelp\\media\\WorldMapJpg\\"
MDQ.jpgPath = function(file) return MDQ.jpgPfx .. tostring(file) end
-- 实景贴图准入：**只有自带这一份**（没有第二来源可退）⇒ 探不到就**不接管**（本项目铁律：拿不到证据就一个字节都不碰）。
--   ★`MDQ.probeTrust` 自带**负对照**（同目录同后缀的不可能文件）⇒ 判不出（nil）一律**放拦**（fail-open）。
--   ★每图判一次并缓存（切换图层/换图都不重探）。
MDQ.jpgSrc = {}
MDQ.jpgSrcOf = function(file)
  local c = MDQ.jpgSrc[file]
  if c == true then return "own" end
  if c == false then return "none" end
  local p = MDQ.jpgPath(file)
  local ok = MDQ.probeTrust(p)
  if ok == true then MDQ.jpgSrc[file] = true return "own" end
  if ok == false then MDQ.jpgSrc[file] = false return "none" end
  return "own"    -- 判不出 ⇒ 放拦（绝不因为「判不出」把功能关死）
end

-- 实际写进 `SetTexture` 的路径（自带那份能用就用自带的 ⇒ 拷进 media 即自包含）
--   ★1.75.60z：**没有版本前缀了**（分版本已清理）⇒ 自带那份一律 `MDQ.ownPfx`。
MDQ.texPath = function(file, a, t)
  local k = MDQ.srcKey(file)
  if k == "none" or k == "client" then return string.format("%s%s\\%s%d", MDQ.cliPfx, file, a, t) end
  return string.format("%s%s\\%s%d%s", MDQ.ownPfx, file, a, t, MDQ.ownExtOf(k))
end

-- ★只读体检：`/ehm mapfit 贴图` —— 把「引擎自报的贴图路径」与「我们按表拼的两条路径」并排列出来，
--   并逐条给**探针结果**（文件加载得出来 / 探不到 / 判不出）。零副作用（只建一张不显示的探针纹理）。
MDQ.texProbe = function()
  local out = {}
  local file, w, h = smMapInfo()
  out[table.getn(out) + 1] = string.format("贴图体检：地图=%s（%sx%s）｜ 图层类型=%s ｜ 彩图表里 %s ｜ 来源判定=%s",
    tostring(file), tostring(w), tostring(h),
    (MDQ.jpgMode() and "**区域实景**（本命令体检的是**彩图**那份贴图；实景看 `/ehm mapfit 图层`）" or "区域彩图"),
    (function() local m = MDQ.artTbl(tostring(file)); if type(m) ~= "table" then return "**没有这张图**" end
      local n = 0 for _ in pairs(m) do n = n + 1 end return n .. " 区" end)(),
    tostring(MDQ.texSrc[tostring(file)] or "（还没判过）"))
  out[table.getn(out) + 1] = "　路径前缀：自带=" .. MDQ.ownPfx .. "　客户端=" .. MDQ.cliPfx
  -- ① 引擎自报（客户端自己那批探索层的贴图路径 —— 「这批贴图到底叫什么」的唯一真值）
  local n = nil
  if type(GetNumMapOverlays) == "function" then local ok, v = pcall(GetNumMapOverlays) if ok then n = tonumber(v) end end
  out[table.getn(out) + 1] = string.format("① 引擎自报 GetNumMapOverlays=%s", tostring(n))
  if type(GetMapOverlayInfo) == "function" and (n or 0) > 0 then
    for i = 1, math.min(n, 6) do
      local ok, nm, tw, th, ox, oy = pcall(function() return GetMapOverlayInfo(i) end)
      if ok and nm ~= nil then
        local r = MDQ.probeTex(tostring(nm))
        out[table.getn(out) + 1] = string.format("　[%d] %s ｜ %sx%s @%s,%s ｜ 探针=%s", i, tostring(nm),
          tostring(tw), tostring(th), tostring(ox), tostring(oy),
          (r == true) and "**加载得出来**" or (r == false and "**探不到**" or "判不出"))
      end
    end
    if (n or 0) > 6 then out[table.getn(out) + 1] = string.format("　…（另有 %d 条）", n - 6) end
  end
  -- ② 我们按表拼的两条路径（本图第一个区域的第一块）
  local m = MDQ.artTbl(tostring(file))   -- ★1.75.64：体检的是**彩图**那份表（实景走 `/ehm mapfit 图层`）
  if type(m) ~= "table" then
    out[table.getn(out) + 1] = "② 表里没有这张图 ⇒ 本来就不渲染（客户端探索层保持原样）"
  else
    local areas = {}
    for a in pairs(m) do table.insert(areas, a) end
    table.sort(areas)
    local a0 = areas[1]
    local cliP = string.format("%s%s\\%s1", MDQ.cliPfx, tostring(file), tostring(a0))
    local rc = MDQ.probeTrust(cliP)
    local fmt = function(p, r)
      return string.format("　%s ｜ 探针=%s", p, (r == true) and "**加载得出来**" or (r == false and "**探不到**" or "判不出"))
    end
    out[table.getn(out) + 1] = string.format("② 本表 %d 区 ｜ 首个区域=%s ⇒ 我们拼的路径（自带那份每种写法都试）：",
      table.getn(areas), tostring(a0))
    for _, ext in ipairs(MDQ.ownForms) do
      local p = string.format("%s%s\\%s1%s", MDQ.ownPfx, tostring(file), tostring(a0), ext)
      out[table.getn(out) + 1] = fmt(p, MDQ.probeTrust(p))
    end
    out[table.getn(out) + 1] = fmt(cliP, rc)
    out[table.getn(out) + 1] = "　（每个写法都带**负对照**：同目录同后缀的不可能文件名；对照也说「有」⇒ 该写法判不出 ⇒ 退回客户端）"
    local key = tostring(MDQ.srcKey(tostring(file)))
    local src = MDQ.srcOf(tostring(file))
    out[table.getn(out) + 1] = "　⇒ 选中来源键：" .. key
    out[table.getn(out) + 1] = (src == "own") and "　⇒ 结论：**用自带的 media 贴图**（插件自包含）"
      or ((src == "client") and "　⇒ 结论：**用客户端自带贴图**（`Interface\\WorldMap`）"
      or "　⇒ 结论：**两份都探不到 ⇒ 本图不接管**（不渲染、不藏原生；客户端探索层保持原样）")
  end
  out[table.getn(out) + 1] = "　★判据：自带那份只要能加载就**优先用它** ⇒ 把贴图拷进 `media\\WorldMap\\<地图>\\<区域><块号>.blp` 即完全自包含（不用改代码）。"
  out[table.getn(out) + 1] = "　★探针可信度（拿一个**不可能存在**的客户端路径当负对照）："
    .. ((MDQ.probeTrust(MDQ.cliPfx .. MDQ.probeBogus) == nil)
      and "**判不出** —— 本客户端对「文件不存在」也报尺寸 ⇒ 一律**退回客户端那份**（绝不改走不存在的自带路径）"
      or "可信（不存在 ⇒ 报 0）⇒ 自带那份的判定可用")
  out[table.getn(out) + 1] = "　★写法：插件目录里的散装文件**要写扩展名**（同 `media\\Flags\\<名>.tga`），所以自带那份按 `.blp` → `.tga` → 不写 依次试。"
  out[table.getn(out) + 1] = "　★探针口径：不设宽高的临时纹理 + `SetTexture` + 读 `GetWidth/GetHeight`（文件在 ⇒ >0；不在 ⇒ 0；**判不出 ⇒ 不放拦**）。"
  return out
end

-- 开关真值（唯一入口）：`SM_CFG.swmOverlay`（**默认 = 开**；显式 false = 用户主动关过 = 关）。
--   ★**落存档**（这是产品开关，与「只在本会话有效」的诊断档不同）；写入点只有两个：
--     `MDQ.fogSet`（工具箱这一行的勾选框 / 命令都走它。★1.75.65 起 **`[设置]` 下拉里不再登记它**）与载入期归一。
MDQ.swm = function()
  -- ★★★1.75.65（用户：「默认设置 开启世界迷雾->选中实景地图,关闭彩图」）：**默认开**。
  --   读法仍是**只认显式 true**（`== true`）—— 载入期清账块会把 nil 落成**显式 true**（行为改变如实播报一次），
  --   之后键永远存在 ⇒ **绝不在这里写 `or true`**（那会顶改用户显式关掉的选择，本项目在案的老雷）。
  return (type(SM_CFG) == "table") and SM_CFG.swmOverlay == true
end

-- 期望分块数（列×行）
--   ★★★1.75.64：**实景模式恒为 1**（整区一张 JPG，没有按 256 的拆分）——
--   这一条 + `expectRect` 的实景分支，就是「编辑模式那一整族在实景下自动只有一行」的全部代价：
--   面板列表 / 拖拽柄 / 箭头微调 / 尺寸 / 配对体检 读的都是 `areaOf → tiles → expectRect` 这条链。
MDQ.tiles = function(w, h)
  if MDQ.jpgMode() then return 1 end
  local a, b = tonumber(w) or 0, tonumber(h) or 0
  if a <= 0 or b <= 0 then return 0 end
  return math.ceil(a / MDQ.TILE) * math.ceil(b / MDQ.TILE)
end

-- 贴图文件边长（Mozz 口径：从 16 起按 2 的幂倍增到 ≥ 像素）—— SetTexCoord 的分母就是它
MDQ.fileDim = function(px)
  local v = tonumber(px) or 0
  if v <= 16 then return 16 end
  local d = 16
  while d < v do d = d * 2 end
  return d
end

-- 第 t 块（1 基，行优先）的**期望**像素几何：宽, 高, offsetX, offsetY（读不出 ⇒ nil）
--   ★★★1.75.64：**实景分支 = 整区一张**（块 1 = 整张图的基线矩形，`{1002,668,0,0}` 那种）——
--   ★`t = 1` 以外一律 nil（实景只有一块；调用方按 `MDQ.tiles` 的返回遍历，本来也只会问第 1 块）。
MDQ.expectRect = function(rec, t)
  if type(rec) ~= "table" then return nil end
  if MDQ.jpgMode() then
    if (tonumber(t) or 1) ~= 1 then return nil end
    local jw, jh, jx, jy = tonumber(rec[1]), tonumber(rec[2]), tonumber(rec[3]), tonumber(rec[4])
    if not (jw and jh and jx and jy) then return nil end
    return jw, jh, jx, jy
  end
  local w, h, ox, oy = tonumber(rec[1]), tonumber(rec[2]), tonumber(rec[3]), tonumber(rec[4])
  if not (w and h and ox and oy) then return nil end
  local nh = math.max(1, math.ceil(w / MDQ.TILE))
  local nv = math.max(1, math.ceil(h / MDQ.TILE))
  local idx = math.max(1, tonumber(t) or 1)
  if idx > nh * nv then return nil end
  local j = math.floor((idx - 1) / nh) + 1        -- 第几行
  local k = ((idx - 1) % nh) + 1                  -- 第几列
  local pw = (k < nh) and MDQ.TILE or (w % MDQ.TILE)
  local ph = (j < nv) and MDQ.TILE or (h % MDQ.TILE)
  if pw == 0 then pw = MDQ.TILE end
  if ph == 0 then ph = MDQ.TILE end
  return pw, ph, ox + MDQ.TILE * (k - 1), oy + MDQ.TILE * (j - 1)
end

-- ===== ★★★1.75.51 倍率 k = **现读**（当前缩放级别 × 数据库，实时算；不留常数）=====
-- 用户要求（原话）：「缩放要根据当前缩放级别和数据库实时计算。」
--   做法 = **拿引擎在当前缩放级别下给出的叠加层真值 ÷ 表推值**：
--     · `GetNumMapOverlays()` + `GetMapOverlayInfo(i)` 是**引擎**按当前地图/缩放级别列出来的
--       (贴图名, 宽, 高, offsetX, offsetY) —— **与我们写没写过无关** ⇒ 任何时候读都是引擎的真值；
--     · 贴图名按 Mozz 规则解析回 (地图, 区域, 块号)，去表里取**同一块**的表推宽 ⇒ 比值 = 当前倍率；
--     · 多个样本取**中位数**；≥3 个样本且离散度 > 15% ⇒ **判不出**（表与客户端内容不同源，不硬套）；
--     · 现读不出（本图 0 条 / 名字读不懂 / 表里没这一块）⇒ **兜底用外框有效缩放**（沿父链连乘，也是现读）；
--       连它也读不到 ⇒ 按 1 写，并**如实说「判不出」**（绝不假装算出来了）。
--   ★**不漂移**：我们写进去的是「表值 × k」，下一拍再测仍是同一个 k（引擎真值不因我们改写而变）⇒ 稳态下 k 恒定；
--     客户端一换图 / 一缩放，引擎真值跟着变 ⇒ 下一拍自动跟上（这就是「实时计算」）。
--   ★每拍现读（0.2s 节流 + 按地图签名缓存），代价 = 每 0.2s 约 N 次只读 API（N = 本图叠加层条数）。
MDQ.kCache = {}     -- 地图签名 → { k = 倍率, src = 来源说明, n = 样本数 }
MDQ.kAt = 0         -- 上次现读的时间（节流用）

-- 贴图名解析：`Interface\WorldMap\<地图文件名>\<区域名><分块号>` —— 返回表，或 nil（读不懂就 nil，绝不猜）
MDQ.parse = function(name)
  local s = tostring(name or "")
  if s == "" then return nil end
  local dir, leaf = string.match(s, "^(.*)\\([^\\]+)$")
  if not dir or not leaf or leaf == "" then return nil end
  local mf = string.match(dir, "([^\\]+)$")
  if not mf or mf == "" then return nil end
  local base, digits = string.match(leaf, "^(.-)(%d*)$")
  if not base or base == "" then return nil end
  return { file = mf, leaf = leaf, area = base, tile = (digits ~= "" and tonumber(digits)) or 1 }
end

-- 现读倍率：引擎真值 ÷ 表推值（多样本取中位数；离散太大 ⇒ nil,样本数）
MDQ.measureK = function(file, m)
  if type(m) ~= "table" then return nil, 0 end
  local n = tonumber(smNumOverlays()) or 0
  if n <= 0 then return nil, 0 end
  local rs = {}
  for i = 1, n do
    local ok, nm, w = pcall(function() return GetMapOverlayInfo(i) end)
    if ok and nm then
      local px = MDQ.parse(nm)
      if px and tostring(px.file) == tostring(file) then
        local rec = m[px.leaf] or m[px.area]
        local ew = rec and select(1, MDQ.expectRect(rec, px.tile))
        local cw = tonumber(w)
        if ew and cw and ew > 8 then
          local r = cw / ew
          if r > 0.05 and r < 20 then table.insert(rs, r) end
        end
      end
    end
  end
  local cnt = table.getn(rs)
  if cnt == 0 then return nil, 0 end
  table.sort(rs)
  local med = rs[math.floor((cnt + 1) / 2)]
  if cnt >= 3 then
    local spread = (rs[cnt] - rs[1]) / med
    if spread > 0.15 then return nil, cnt end   -- 离散太大 ⇒ 表与客户端不同源 ⇒ 判不出（不硬套）
  end
  return med, cnt
end

-- 现读（0.2s 节流 + 按地图签名缓存）；返回 k, 来源说明, 样本数
MDQ.kLive = function(file, m, es)
  local now = (type(GetTime) == "function") and GetTime() or 0
  local mk = smMapKey() or file
  local c = MDQ.kCache[mk]
  if type(c) == "table" and (now - (tonumber(MDQ.kAt) or 0)) < 0.2 then return c.k, c.src, c.n end
  local k, nS = MDQ.measureK(file, m)
  local src
  if k then
    src = string.format("引擎实测（%d 个样本）", nS)
  else
    k = tonumber(es)
    if k and k > 0 then
      src = (nS > 0) and "外框有效缩放（引擎真值离散太大 ⇒ 兜底现读）" or "外框有效缩放（引擎没给本图叠加层 ⇒ 兜底现读）"
    else
      k, src = 1, "**判不出**（引擎与缩放都读不到 ⇒ 按 1 写）"
    end
  end
  MDQ.kCache[mk] = { k = k, src = src, n = nS }
  MDQ.kAt = now
  return k, src, nS
end

-- 取池位 n 的纹理：① 客户端已有的（`_G` 里查得到）→ 复用；② 我们自己补建的 → 复用；③ 都没有 ⇒ **现场补建**
--   ★两级建法：先按客户端的命名习惯建具名（`WorldMapOverlay<n>`，与 S_WorldMap 同法 ⇒ 能一路接管它的池位）；
--     具名失败（名字被占 / 本客户端不许具名）⇒ **退回匿名纹理**（照样能画，只是 `_G` 里查不到）—— 绝不静默放弃。
--   ★返回值带**来源**（existing / own / created / no_frame / create_failed），渲染行如实报「既有 N ｜ 新加 M」。
MDQ.texAt = function(n)
  local nm = "WorldMapOverlay" .. tostring(n)
  if n > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = n end
  local t = rawget(_G, nm)
  if t ~= nil then
    -- ★★★1.75.52 六改 b：**复用来的池位也算「我们接管了」** —— 我们马上要往它身上写表内容；
    --   不标记的话「接管守护」会把它当客户端原生层**再藏一次** ⇒ 数据库查出来的层等于没加上（用户实报）。
    MDQ.ownSet[t] = true
    return t, "existing"
  end
  t = MDQ.own[n]
  if t ~= nil then
    MDQ.ownSet[t] = true
    return t, "own"
  end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") or type(fr.CreateTexture) ~= "function" then
    return nil, "no_frame"
  end
  local ok, t2 = pcall(fr.CreateTexture, fr, nm, "ARTWORK")
  if not ok or t2 == nil then
    local ok2, t3 = pcall(fr.CreateTexture, fr, nil, "ARTWORK")   -- ★退回匿名（照样能画）
    if ok2 and t3 ~= nil then t2 = t3 else return nil, "create_failed" end
  end
  MDQ.own[n] = t2
  MDQ.made[nm] = true
  MDQ.ownSet[t2] = true     -- ★身份账（接管守护判「这张是不是我们自建的」唯一依据）
  MDQ.newN = (tonumber(MDQ.newN) or 0) + 1
  return t2, "created"
end

-- 从第 from 位起把池位全部 Hide（客户端池 + 我们自己补的）。
--   ★**不空扫**：客户端那批名字是从 1 起的**连续**池位 ⇒ 扫到「既没有具名纹理、又超过我们见过的最大号」
--     就可以收工；扫到的都把 `MDQ.poolSeen` 顶上去（这样下次才知道该扫到哪）。
--   ★★★1.75.54e（用户：「开关状态要做好正确的功能开关状态维护.不要影响到原始地图的功能」）：
--     这里藏掉的**客户端池位**（= 序号超出本图块数的那些 / 客户端多摆的）必须**进藏账**（`MDQ.holdNote`）
--     —— 旧写法只 Hide 不记账 ⇒ 关掉开关时「还回」找不到它们 ⇒ 客户端的探索层**永久缺块**。
--     口径两条：① 只记**我们没自建**的（`ownSet` 之外的才是客户端的，自建的由 `release` 负责收）；
--             ② 只记**当下真的显示着**的（本来就隐藏的不记，免得还回时把客户端自己藏起来的层顶出来）。
MDQ.hideFrom = function(from, file, keepNative)
  local n = 0
  local lo = tonumber(from) or 1
  if lo < 1 then lo = 1 end
  for i = lo, MDQ.poolMax do
    local t = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
    if t ~= nil then
      local ours = (MDQ.ownSet[t] == true)
      -- ★★★1.75.60b：编辑模式「**显示原始贴图层**」时这一趟**一个字节都不碰客户端的层**（`keepNative`）——
      --   这一趟要藏的对象恰恰就是「客户端留下来的 / 上一张图残留的」池位，而那**正是用户要看的那一层**；
      --   藏了就等于把它又盖回去（用户看到的就是「按钮点了、图还是没出来」）。
      --   ★★我们自己写过的（`ownSet`：复用来的池位 + 自建的）**照旧收** —— 不收的话上一张图
      --      **我们画的**残留会叠在这一张上（那不是「原始贴图层」，是我们的旧画）。
      if not (keepNative == true and not ours) then
        -- ★只有「还没记过账的客户端池位」才需要读一次 IsShown（记过的不再读 ⇒ 稳态零额外开销）
        local wasShown = false
        if (not ours) and MDQ.holdHid[t] == nil then
          local okS, sh = pcall(t.IsShown, t)
          wasShown = (okS and sh == true)
        end
        -- ★★★1.75.59k：**记账必须排在 Hide 之前**（`holdNote` 现在同时抓原值 —— 先 Hide 再抓，
        --   抓到的 `shown` 就是 false ⇒ 关掉时还回**不会 Show** ⇒ 客户端探索层永久缺块）。
        if wasShown then pcall(MDQ.holdNote, t, file, "接管藏（多余池位）") end
        pcall(t.Hide, t)
        -- ★1.75.54：藏了就**作废那一格的写前比对**（否则下次要显示它时会被判「没变」而不 Show ⇒ 缺块）
        if MDQ.slot[i] ~= nil then MDQ.slot[i].shown = false end
        n = n + 1
        if i > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = i end
      end
    elseif i > (tonumber(MDQ.poolSeen) or 0) then
      break
    end
  end
  return n
end

-- ★★★1.75.52 六改 b（用户真机报障：「**删完之后数据库查询出来的层有没添加进去，现在全都是空白的**」）：
--   **表查找 = 单一来源 + 大小写不敏感**：`GetMapInfo()` 的图名与表键**可能大小写不一致** ⇒
--   直接 `tbl[file]` 取不到就会「一片都不画」，再叠加「原生全藏」= **整张图空白**。
--   这里一次性收口：精确命中 → 退**逐个键不比大小写**（53 个键，命中后按图名缓存，不每拍扫表）。
--   返回 `m（区域表）, 真键`；读不到 ⇒ nil。
MDQ.areaCache = {}
-- 彩图基表（**永远读艺术表**，与当前图层类型无关）—— 「问的是彩图那份贴图」的口必须走它：
--   `MDQ.srcKey`（自带 .blp 的来源判定，结果按图名缓存 ⇒ 绝不能被实景模式污染）· `MDQ.texProbe`（贴图体检）。
MDQ.artTbl = function(file)
  if type(file) ~= "string" or file == "" then return nil end
  local tbl = rawget(_G, "EVAL_MAP_OVERLAY_DATA")
  if type(tbl) ~= "table" then return nil end
  local m = tbl[file]
  if m ~= nil then return m, file end
  local c = MDQ.areaCache[file]
  if c ~= nil then
    if c == false then return nil end
    return c, nil
  end
  local low = string.lower(file)
  for k, v in pairs(tbl) do
    if type(k) == "string" and string.lower(k) == low then
      MDQ.areaCache[file] = v
      return v, k
    end
  end
  MDQ.areaCache[file] = false
  return nil
end

-- ★★★1.75.64：**本图的基表（按图层类型分派）** —— 全项目「本图有哪些层 / 每层多大在哪」的唯一入口。
--   彩图 = `MDQ.artTbl`（`[区域][块]` 两层，按 256 拆块）；
--   实景 = **现场合成的伪表** `{ [_JPG] = { 宽, 高, 偏移x, 偏移y } }`（一份数据、一个伪区域、一块）。
--   ★为什么用「合成一张形态相同的表」而不是让每个调用点自己分支：编辑模式那一整族
--     （面板列表 `editLines`/`panelSync` · 拖拽柄 `grabSyncAll`/`editBegin` · 箭头 `nudge`/`dragMembers` ·
--      尺寸 `selSizeNow`/`sizeStep` · 配对体检 `editJoin` · 数量守护 `holdN`）读的都是
--     `areaOf → tiles → expectRect` 这条链 ⇒ **换基表即换套**，一行调用点都不用改
--     （本项目在案的教训：「按存储/数据格式分派的地方必须一次全改」，最容易漏的就是散在各处的读取点）。
--   ★大小写不敏感与彩图同口径（`MDQ.jpgBase` 内部逐键比小写）。
MDQ.areaOf = function(file)
  if MDQ.jpgMode() then
    if type(file) ~= "string" or file == "" then return nil end
    local c = MDQ.jpgAreaCache
    if c == nil then c = {} MDQ.jpgAreaCache = c end
    local hit = c[file]
    if hit ~= nil then
      if hit == false then return nil end
      return hit
    end
    local rec = MDQ.jpgBase(file)
    if type(rec) ~= "table" then c[file] = false return nil end
    local t = {}
    t[MDQ.JPG_AREA] = rec
    c[file] = t
    return t, file
  end
  return MDQ.artTbl(file)
end

-- 只收**我们自己自建**的层（绝不碰客户端的）：表里没有这张图时用它 ——
--   「数据库没有这张图」= **无从替代** ⇒ 客户端自己的探索层**保持原样**（本项目铁律：拿不到证据就一个字节都不碰）。
MDQ.hideOwnFrom = function(from)
  local n = 0
  local lo = tonumber(from) or 1
  if lo < 1 then lo = 1 end
  for i = lo, MDQ.poolMax do
    local t = MDQ.own[i]
    if t ~= nil then
      pcall(t.Hide, t)
      if MDQ.slot[i] ~= nil then MDQ.slot[i].shown = false end
      n = n + 1
      if i > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = i end
    end
  end
  return n
end

-- 全渲染当前图（**纯写**：贴图/UV/尺寸/位置全部由表现算；不读也不记任何原值）。
--   ★`k` = **当前倍率**（`MDQ.kLive` 现读：当前缩放级别 ÷ 表值）—— 表值 × k 才是这一拍该写的逻辑几何。
--     写表值原样（k=1）只在「引擎真值 = 表值」时成立，**不是**一条可以写死的规则。
--   返回 块数, 区域数, 表里有没有这张图, 是否渲完整, 原因, 客户端既有层数, 新加层数
--   ★`force = true` ⇒ **忽略写前比对，整批重写**（★1.75.54b：**节流那一拍必须这样**）：
--     我们复用的是**客户端自己的** `WorldMapOverlay<n>` 池位纹理，客户端会在我们写完之后**自己再摆一次**
--     （首次开图尤其明显）⇒ 只靠比对会判「没变⇒跳过」⇒ 客户端那套（缩放不对的）几何留在屏幕上
--     = 用户报的「**首次地图打开客户端自身的贴图缩放异常**」。⇒ 重申语义不能省，只在**逐帧**那条路用比对省。
MDQ.render = function(file, k, force)
  k = tonumber(k) or 1
  if k <= 0 then k = 1 end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then
    MDQ.lastRenderN = 0
    return 0, 0, false, true, "没有 WorldMapDetailFrame", 0, 0
  end
  local m = MDQ.areaOf(file)   -- ★六改 b：表查找单一来源（大小写不敏感）
  -- ★★★1.75.59o：**本图的本游戏专属补偿**（与 `MapOverlayData.lua` 配对使用；无补偿 ⇒ nil ⇒ 渲染路径零开销）
  local edx = MDQ.editIndex(file)
  MDQ.newN = 0
  -- ★★★1.75.52 六改 c：**本拍我们真正写过的那批对象**（`wroteObj`）—— 「接管守护」的安全底线：
  --   守护只许藏「本拍**没**写过、名字又属池位族」的东西；**一个都没认出来 ⇒ 判不出 ⇒ 一个字节都不碰**。
  --   真机日志取证（`/ehm mapfit 残留` 落盘）：`渲染 22 块（客户端既有 0 ｜ 新加 22）` 与
  --   `守护：藏原生 22 ｜ 枚举池位 22` **同时出现** ⇒ 枚举里那 22 个不是我们画的（我们画的没被枚举到
  --   或身份每拍都变）⇒ 旧写法会把它们当原生全藏，等于把我们刚画的一起藏掉 = **整张空白图**。
  MDQ.wroteObj = {}
  MDQ.lastW, MDQ.lastH, MDQ.lastArea, MDQ.lastTex = nil, nil, nil, nil
  -- ★1.75.60o：最终表口径尺寸（含尺寸补偿）也一起清 —— 「这一拍一块都没写」时不许留着上一拍的旧值
  MDQ.lastFw, MDQ.lastFh = nil, nil
  if type(m) ~= "table" then
    -- ★★★1.75.52 六改 b：**表里没有这张图 ⇒ 只收我们自建的那几层，客户端自己的探索层保持原样**
    --   （用户真机报障：「删完之后数据库查询出来的层有没添加进去，现在全都是空白的」——
    --    数据库没有这张图时**无从替代**，把原生全藏只会得到一片空白；
    --    本项目铁律「拿不到证据就一个字节都不碰」。）
    MDQ.lastRenderN = 0
    local hid = MDQ.hideOwnFrom(1)
    -- ★1.75.59o：本图无从替代 ⇒ 拖拽柄也一起收起（否则上一张图留下的柄会留在屏上吃鼠标）
    if MDQ.grabHideAll then pcall(MDQ.grabHideAll, "本图不在表里") end
    if MDQ.panelHide then pcall(MDQ.panelHide, "本图不在表里") end
    return 0, 0, false, true,
      ("本图不在 S_WorldMap 表里（数据库没有这张图 ⇒ 客户端自己的探索层**保持原样**；只收起我们自建的 " .. tostring(hid) .. " 层）"), 0, 0
  end
  local areas = {}
  for a in pairs(m) do table.insert(areas, a) end
  table.sort(areas)                 -- ★顺序必须确定（同一张图每次渲染的层序一致，便于逐层对照取证）
  local n, nArea, full = 0, 0, true
  local nExist, fail = 0, nil
  MDQ.wroteN, MDQ.skipN, MDQ.offN = 0, 0, 0   -- ★1.75.54 本拍真发了几次写 / 没变跳过了几块（取证+安全阀）；★1.75.59o 加了「本拍套了几条补偿」
  for _, a in ipairs(areas) do
    local rec = m[a]
    local total = MDQ.tiles(rec and rec[1], rec and rec[2])
    if total > 0 then
      nArea = nArea + 1
      for t = 1, total do
        if n >= MDQ.poolMax then full = false fail = "max" break end
        local pw, ph, ox, oy = MDQ.expectRect(rec, t)
        if pw then
          -- ★★★1.75.59o：**最终坐标 = `MapOverlayData.lua` 的表值 + 本游戏专属补偿**（配对唯一出口）
          --   ★基础表里查不到这一块 ⇒ `editFinal` 原样返回表值（补偿不生效）—— 孤儿补偿绝不硬加到别的块上。
          local off = (edx ~= nil and edx[a] ~= nil) and edx[a][t] or nil
          local fox, foy, used = MDQ.editFinal(ox, oy, off)
          -- ★★★1.75.60o：**尺寸补偿**（用户：「迷雾贴图列表在单选的情况下支持选中图层的高度和宽度调整.」）——
          --   与位置**同一个记录、同一个配对口径**：最终尺寸（表口径）= 表值 + `dw/dh`（唯一出口 `MDQ.editSize`）。
          --   ★UV **不动**（贴图文件里那一块仍按 `pw×ph` 采样）⇒ 拉伸/压缩的是这一块本身，不是换一块内容。
          local fw, fh = MDQ.editSize(pw, ph, off)
          if used then MDQ.offN = (tonumber(MDQ.offN) or 0) + 1 end
          local tex, how = MDQ.texAt(n + 1)
          if tex == nil then full = false fail = (how or "create_failed") break end
          if how == "existing" then nExist = nExist + 1 end
          n = n + 1
          MDQ.wroteObj[tex] = true   -- ★六改 c：这一拍我们写过它（守护的「不许藏」名单）
          -- ★★★1.75.54 写前比对：**内容一模一样就一个 `Set*` 都不发**。
          --   比对项 = 对象 + 地图 + 区域 + 块号 + 倍率 + 当前是否显示中（`shown` 被 hideFrom/release 清过）。
          --   ★**不建字符串**（不调 `texPath`）—— 逐帧重申这条路上每块一次 `string.format` 就是纯浪费。
          local sg = MDQ.slot[n]
          if (not force) and sg ~= nil and sg.tex == tex and sg.shown == true and sg.k == k
            and sg.file == file and sg.area == a and sg.tile == t
            and sg.ox == fox and sg.oy == foy and sg.ow == fw and sg.oh == fh then
            MDQ.skipN = MDQ.skipN + 1
          else
            -- ★★★1.75.54e：**写之前先把原值读下来**（只对「复用客户端自己的池位」这条来源）——
            --   关掉开关时靠它把这一格还原成客户端原来那份（否则我们的几何永远留在客户端对象上）。
            if how == "existing" then pcall(MDQ.origGrab, n, tex) end
            local fdw, fdh = MDQ.fileDim(pw), MDQ.fileDim(ph)
            pcall(tex.SetTexture, tex, MDQ.texPath(file, a, t))
            pcall(tex.SetTexCoord, tex, 0, pw / fdw, 0, ph / fdh)
            pcall(tex.SetWidth, tex, fw * k)
            pcall(tex.SetHeight, tex, fh * k)
            pcall(tex.ClearAllPoints, tex)
            pcall(tex.SetPoint, tex, "TOPLEFT", fr, "TOPLEFT", fox * k, -(foy * k))
            pcall(tex.Show, tex)
            -- ★1.75.59o：`wx/wy/ww/wh` = **真写进去的逻辑几何**（补偿已算入）⇒ 编辑模式的拖拽柄与图层
            --   **同源**（柄直接抄这一份，绝不另算一套坐标 —— 两套算法迟早会不一致）。
            --   `ox/oy` 存**最终表口径**（表值+补偿）：写前比对必须带上它，否则拖完会被判「没变」而跳过。
            MDQ.slot[n] = { tex = tex, file = file, area = a, tile = t, k = k, shown = true,
              ox = fox, oy = foy, off = used or nil, wx = fox * k, wy = -(foy * k), ww = fw * k, wh = fh * k,
              -- ★1.75.60o：最终**表口径**尺寸（写前比对要用它 —— 只比 k 倍后的像素值会漏掉「表值变了但像素没变」）
              ow = fw, oh = fh,
              -- ★1.75.60l：这一格现在挂的**迷雾透明度**（写前比对用）。
              --   ★只有**同一个对象**（`sg.tex == tex`）才继承旧值；换了对象 ⇒ 记 nil（新对象上未必是那个值，
              --     必须由下面那趟透明度应用重新写一遍）。
              fa = ((sg ~= nil) and (sg.tex == tex)) and sg.fa or nil }
            MDQ.wroteN = MDQ.wroteN + 1
          end
          if MDQ.lastW == nil then
            MDQ.lastW, MDQ.lastH = fw * k, fh * k   -- ★**写进去的**（自证与播报都按它说）
            MDQ.lastTw, MDQ.lastTh = pw, ph         -- ★表值（播报里「表 X ⇒ 写 Y」两个都摊开）
            MDQ.lastFw, MDQ.lastFh = fw, fh          -- ★1.75.60o：**最终表口径尺寸**（含尺寸补偿；取证/判据读它）
            MDQ.lastTox, MDQ.lastToy = ox, oy
            MDQ.lastK = k
            MDQ.lastArea = a
            MDQ.lastTex = tex      -- ★自证读这一张（**我们真正写的那张**；可能是我们自己补建的匿名纹理）
          end
        end
      end
    end
    if not full then break end
  end
  -- 收尾：这一轮没用到的池位全部 Hide（客户端自己的残留层也在里面 —— 「忽略内置探索纹理」）
  --   ★1.75.54e：这次 Hide 掉的**客户端**池位要**进藏账**（关开关时按账全部 Show 还回）——见 `MDQ.hideFrom`
  --   ★1.75.60b：编辑模式「显示原始贴图层」⇒ `keepNative` 让这一趟**不碰客户端的层**（见 `hideFrom` 注释）
  MDQ.hideFrom(n + 1, file, (MDQ.liveNative ~= nil) and MDQ.liveNative() or false)
  MDQ.lastRenderN = n   -- ★六改 b：本拍真的画出了几块（「接管守护」拿它判「有没有东西可替代」）
  -- ★★★1.75.60b：编辑模式「**隐藏迷雾贴图层**」⇒ 本拍画完之后**当场把我们画的块收起来**
  --   （几何照旧写、账照旧记 —— 只是不显示；金色拖拽柄不动，那是编辑 UI，关了迷雾还要有得拖）。
  --   ★`shown = false` 不能省：写前比对靠它 ⇒ 不置的话「开回来」那一拍会被判「没变」而不 `Show`（缺块）。
  if (MDQ.liveFogOff ~= nil) and MDQ.liveFogOff() then
    for i = 1, n do
      local sgOff = MDQ.slot[i]
      if sgOff ~= nil and sgOff.tex ~= nil then
        pcall(sgOff.tex.Hide, sgOff.tex)
        sgOff.shown = false
      end
    end
  end
  -- ★★★1.75.60e：**逐块隐藏**（列表右键；排查用 —— 几何照写、账照记，只是不显示；柄与序号角标照旧）。
  --   ★`shown = false` 不能省：写前比对靠它 ⇒ 不置的话「放回来」那一拍会被判「没变」而不 `Show`（缺块）。
  if MDQ.blkHideCount() > 0 then
    for i = 1, n do
      local sgH = MDQ.slot[i]
      if sgH ~= nil and sgH.tex ~= nil and MDQ.blkHidden(sgH.area, sgH.tile) then
        pcall(sgH.tex.Hide, sgH.tex)
        sgH.shown = false
      end
    end
  end
  -- ★★★1.75.60l（用户：「编辑模式可以在迷雾贴图列表内设置迷雾贴图的透明度,统一设置全部贴图的透明度,
  --   方便和地图原始层对照」）：**迷雾贴图统一透明度** —— 把我们这一拍写出来的每一块 `SetAlpha(透明值)`。
  --   ★五条口径（改这里之前先读完）：
  --     ① **只动我们这一拍写过的那些块**（`MDQ.slot[i].tex` = 我们补建的 / 我们借来用的）——
  --        客户端的原生层（守护与残留清理管的那一批）**一个字节都不碰**（对象边界，同 §⑩）；
  --     ② **写前比对**（`sg.fa` = 这一格现在是几）⇒ 稳态**零写**（只有真变了才发 `SetAlpha`）；
  --     ③ **复用来的客户端池位（how == "existing"）的原 alpha 早在写入之前就进了原值账** ——
  --        `MDQ.origGrab` 抓六样（贴图 / UV / 宽高 / 锚点 / 显隐 / **alpha**）⇒ 关开关 / 收层时由
  --        `MDQ.origRestore` **连 alpha 一起还回**，绝不把客户端的层留在半透明上（铁律「改属性前先把原值读下来」）；
  --     ④ **这一趟不许拿 editOn 当闸**：关编辑模式那一拍**必须**能把它写回不透明
  --        （「只在编辑模式内生效」靠**值**保证：唯一写口在非编辑模式里直接拒绝 + `editSet(false)` 当场复位成 1）；
  --     ⑤ 「迷雾隐藏」那一趟跳过（块已经藏了，写 alpha 是白写；再显示时这一格自然会重算）。
  if not ((MDQ.liveFogOff ~= nil) and MDQ.liveFogOff()) then
    local faNow = tonumber(MDQ.fogAlpha) or 1
    if faNow < 0 then faNow = 0 end
    if faNow > 1 then faNow = 1 end
    for i = 1, n do
      local sgA = MDQ.slot[i]
      if sgA ~= nil and sgA.tex ~= nil and (tonumber(sgA.fa) or 1) ~= faNow then
        if pcall(sgA.tex.SetAlpha, sgA.tex, faNow) then
          sgA.fa = faNow
          MDQ.fogAlphaN = (tonumber(MDQ.fogAlphaN) or 0) + 1
        end
      end
    end
  end
  -- ★★★1.75.59o/p：**编辑模式的拖拽柄 + 贴图列表与图层几何同一拍同步**（不同源就会指错块）——
  --   只在编辑模式开着时才建/铺（关着时 `grabHideAll` 早退；`panelSync` 同理），**默认零开销**。
  if MDQ.grabSyncAll then pcall(MDQ.grabSyncAll, file, n, k) end
  if MDQ.panelSync then pcall(MDQ.panelSync, file, n, k) end
  local why = nil
  if not full then
    why = (fail == "max")
      and ("纹理池上限 " .. MDQ.poolMax .. " 已满（已渲染 " .. n .. " 块 ⇒ 表里还有区域没画出来）")
      or ("**本客户端建不出新图层**（CreateTexture 失败，已渲染 " .. n .. " 块）")
  end
  return n, nArea, true, full, why, nExist, (tonumber(MDQ.newN) or 0)
end

-- ============ ★★★1.75.64：**实景图层**（整区一张 JPG）的渲染 ============
--   与彩图那套（`MDQ.render`）**共用同一份几何账**（`MDQ.slot[1]`）与**同一批收尾语义**
--   （`hideFrom` 收多余池位 / 迷雾隐藏 / 逐块隐藏 / 统一透明度 / 柄与列表同步）
--   —— 编辑模式那一整族读的就是这份账，两套算法各写一份坐标迟早会不一致（本项目在案的教训）。
--   返回口径与 `MDQ.render` **逐字相同**：块数, 区域数, 表里有没有这张图, 是否渲完整, 原因, 客户端既有层数, 新加层数
-- ★★★1.75.68：**屏幕矩形**（真屏幕像素，含全部缩放 —— `GetRight-GetLeft` / `GetTop-GetBottom`）。
--   用途：判「实景贴图到底铺没铺满帧」。★为什么必须用它、不能用 `GetWidth` 比：
--   本项目在案两条实测**互相冲突**（帧 `GetWidth` **含**父链缩放，如真机 `701.4 = 1002 × 0.7`；
--   而纹理 `GetWidth` 报的是**写进去的逻辑值**）⇒ 两个读回值不许直接比，只有屏幕矩形是同一把尺子。
--   读不到（老客户端 / 对象没建 / 地图关着报 0）⇒ 返回 nil，调用方**不许动手**。
MDQ.scrBox = function(o)
  if o == nil then return nil, nil end
  local o1, l = pcall(o.GetLeft, o)
  local o2, r = pcall(o.GetRight, o)
  local o3, b = pcall(o.GetBottom, o)
  local o4, t = pcall(o.GetTop, o)
  if not (o1 and o2 and o3 and o4) then return nil, nil end
  if type(l) ~= "number" or type(r) ~= "number" or type(b) ~= "number" or type(t) ~= "number" then return nil, nil end
  return (r - l), (t - b)
end
-- 实景的**客户端倍率口径**（会话级，一次量准就固定用）：本项目对「`SetWidth` 是逻辑值还是屏幕值」
--   在案两条实测互相冲突 ⇒ **不猜，写完当场量**（见 `MDQ.jpgRender` 里的自证块）：
--   `MDQ.unitFit` = 让「贴图屏幕矩形 = 帧屏幕矩形」所需的额外倍数（1 = 基线原样即铺满）。
MDQ.unitFit = nil
-- ★实景几何 = **唯一写入口**（UV / 宽高 / 绘制层 / 锚点 / 显示 只此一处）：
--   两个调用点 = 首次写入 + 「屏测自证后按测量值重写」⇒ 收成一处，避免同口径散成两份
--   （本项目在案教训：同一段写几何的代码复制两份 ⇒ 变异锚点「不唯一」、改口径必漏一处）。
MDQ.jpgPlace = function(tex, fr, fw, fh, fox, foy, k)
  pcall(tex.SetTexCoord, tex, 0, 1, 0, 1)          -- ★**整张图**（不是 256 块，UV 铺满）
  pcall(tex.SetWidth, tex, fw * k)
  pcall(tex.SetHeight, tex, fh * k)
  -- ★★★用户点名：「实景图层在渲染层显示优先级最高.遮盖其他同组层」——
  --   彩图那批池位在 `ARTWORK`，实景写 **`OVERLAY`**（内容层之上）⇒ 同组内一定压住其它层。
  --   原绘制层进原值账（第 7 样）⇒ 关开关/收层时 `origRestore` 连它一起还回。
  pcall(tex.SetDrawLayer, tex, "OVERLAY")
  pcall(tex.ClearAllPoints, tex)
  pcall(tex.SetPoint, tex, "TOPLEFT", fr, "TOPLEFT", fox * k, -(foy * k))
  pcall(tex.Show, tex)
end
MDQ.jpgRender = function(file, k, force)
  k = tonumber(k) or 1
  if k <= 0 then k = 1 end
  -- ★已量过这个客户端的口径 ⇒ 从一开始就按它算，后续每拍都不会再写错一次
  if MDQ.unitFit ~= nil then k = k * MDQ.unitFit end
  local fr = _G["WorldMapDetailFrame"]
  if not (type(fr) == "table" or type(fr) == "userdata") then
    MDQ.lastRenderN = 0
    return 0, 0, false, true, "没有 WorldMapDetailFrame", 0, 0
  end
  MDQ.newN = 0
  MDQ.wroteObj = {}
  MDQ.wroteN, MDQ.skipN, MDQ.offN = 0, 0, 0
  MDQ.lastW, MDQ.lastH, MDQ.lastArea, MDQ.lastTex = nil, nil, nil, nil
  MDQ.lastFw, MDQ.lastFh = nil, nil
  local rec = MDQ.jpgBase(file)
  if type(rec) ~= "table" then
    -- ★与彩图那套同一条铁律：**表里没有这张图 ⇒ 只收我们自建的层**，客户端自己的探索层保持原样
    MDQ.lastRenderN = 0
    local hid = MDQ.hideOwnFrom(1)
    if MDQ.grabHideAll then pcall(MDQ.grabHideAll, "本图没有实景数据") end
    if MDQ.panelHide then pcall(MDQ.panelHide, "本图没有实景数据") end
    return 0, 0, false, true,
      ("实景表（MapOverlayJPGData.lua）里没有这张图 ⇒ 客户端自己的探索层**保持原样**（只收起我们自建的 "
        .. tostring(hid) .. " 层）"), 0, 0
  end
  local ox, oy = tonumber(rec[3]) or 0, tonumber(rec[4]) or 0
  local off = MDQ.editRec(file, MDQ.JPG_AREA, MDQ.JPG_TILE)     -- 存档 > 文件（`editTbl` 已按模式换根）
  local fox, foy, used = MDQ.editFinal(ox, oy, off)
  local fw, fh = MDQ.editSize(tonumber(rec[1]) or 0, tonumber(rec[2]) or 0, off)
  if used then MDQ.offN = 1 end
  local tex, how = MDQ.texAt(1)
  if tex == nil then
    MDQ.lastRenderN = 0
    return 0, 0, true, false, ("建不出实景图层（" .. tostring(how or "create_failed") .. "）"), 0, 0
  end
  MDQ.wroteObj[tex] = true        -- ★「接管守护」的「不许藏」名单（本拍我们写的）
  local sg = MDQ.slot[1]
  -- ★写前比对（与彩图那套同口径：对象 + 图 + 伪区域/块号 + 倍率 + 显隐 + 最终几何）⇒ 稳态零写
  local same = (not force) and sg ~= nil and sg.tex == tex and sg.shown == true and sg.k == k
    and sg.file == file and sg.area == MDQ.JPG_AREA and sg.tile == MDQ.JPG_TILE
    and sg.ox == fox and sg.oy == foy and sg.ow == fw and sg.oh == fh
  if same then
    MDQ.skipN = 1
  else
    -- ★复用客户端池位 ⇒ **写之前先把原值读下来**（贴图/UV/宽高/锚点/显隐/alpha/绘制层 七样）
    if how == "existing" then pcall(MDQ.origGrab, 1, tex, "pool") end
    pcall(tex.SetTexture, tex, MDQ.jpgPath(file))
    MDQ.jpgPlace(tex, fr, fw, fh, fox, foy, k)      -- ★唯一写入口（UV/宽高/绘制层/锚点/显示）
    -- ★★★1.75.68：**写完当场用屏幕矩形自证并校正倍率**（只量一次、只记一次；量不出/不合常理 ⇒ 一个字节都不动）
    --   症状 = 用户报「实景与地图**缩放和位置**对不上」：若客户端把 `SetWidth` 当逻辑值，
    --   写 `基线 × 外框缩放(0.7)` 就只铺了帧的 70% ⇒ 实景缩在左上角。
    --   判据 = 贴图屏幕宽 ÷ 帧屏幕宽：≈1 铺满；≈0.7 说明多乘了一次 ⇒ 把 k 乘上这个比值重写一次。
    if MDQ.unitFit == nil then
      local fsw = MDQ.scrBox(fr)
      local tsw = MDQ.scrBox(tex)
      if (fsw ~= nil) and (tsw ~= nil) and fsw > 1 and tsw > 1 then
        local fit = fsw / tsw
        if fit > 0.25 and fit < 4 then
          if (fit > 1.03) or (fit < 0.97) then
            MDQ.unitFit = fit
            k = k * fit
            MDQ.jpgPlace(tex, fr, fw, fh, fox, foy, k)   -- 按测量值重写一次（同一写入口）
            MDQ.fitSay = string.format("世界迷雾·实景倍率：屏幕实测「贴图/帧 = %.3f」⇒ 已校正 ×%.4f（k 现在 = %.4f）"
              .. "，本图铺满帧", fit, fit, k)
          else
            MDQ.unitFit = 1
            MDQ.fitSay = string.format("世界迷雾·实景倍率：屏幕实测「贴图/帧 = %.3f」⇒ 基线原样即铺满，无需校正", fit)
          end
        end
      end
    end
    MDQ.slot[1] = { tex = tex, file = file, area = MDQ.JPG_AREA, tile = MDQ.JPG_TILE, k = k, shown = true,
      ox = fox, oy = foy, off = used or nil, wx = fox * k, wy = -(foy * k), ww = fw * k, wh = fh * k,
      ow = fw, oh = fh, jpg = true,
      fa = ((sg ~= nil) and (sg.tex == tex)) and sg.fa or nil }
    MDQ.wroteN = 1
    if MDQ.fitSay ~= nil then say(MDQ.fitSay) MDQ.fitSay = nil end
  end
  MDQ.lastW, MDQ.lastH = fw * k, fh * k
  MDQ.lastTw, MDQ.lastTh = tonumber(rec[1]) or 0, tonumber(rec[2]) or 0
  MDQ.lastFw, MDQ.lastFh = fw, fh
  MDQ.lastTox, MDQ.lastToy = ox, oy
  MDQ.lastK = k
  MDQ.lastArea = MDQ.JPG_AREA
  MDQ.lastTex = tex
  -- 收尾：实景只有一层 ⇒ 序号 2 起（我们的 + 客户端多摆的）全部收起（藏账由 `hideFrom` 负责，关开关时全部 Show 还回）
  MDQ.hideFrom(2, file, (MDQ.liveNative ~= nil) and MDQ.liveNative() or false)
  MDQ.lastRenderN = 1
  local sl = MDQ.slot[1]
  if (MDQ.liveFogOff ~= nil) and MDQ.liveFogOff() then
    pcall(tex.Hide, tex) sl.shown = false
  elseif MDQ.blkHidden(MDQ.JPG_AREA, MDQ.JPG_TILE) then
    pcall(tex.Hide, tex) sl.shown = false
  else
    local faNow = tonumber(MDQ.fogAlpha) or 1
    if faNow < 0 then faNow = 0 end
    if faNow > 1 then faNow = 1 end
    if (tonumber(sl.fa) or 1) ~= faNow then
      if pcall(tex.SetAlpha, tex, faNow) then sl.fa = faNow MDQ.fogAlphaN = (tonumber(MDQ.fogAlphaN) or 0) + 1 end
    end
  end
  if MDQ.grabSyncAll then pcall(MDQ.grabSyncAll, file, 1, k) end
  if MDQ.panelSync then pcall(MDQ.panelSync, file, 1, k) end
  return 1, 1, true, true, nil, ((how == "existing") and 1 or 0), (tonumber(MDQ.newN) or 0)
end

-- ★★★1.75.54e（用户：「开关状态要做好正确的功能开关状态维护.不要影响到原始地图的功能」）：
--   **复用客户端池位之前，先把原值读下来**（本项目铁律「改属性前先把原始值读下来」）。
--   为什么必须做：`MDQ.texAt` 的第 ① 条路是**复用客户端自己的** `_G["WorldMapOverlay<n>"]`，而 `MDQ.render`
--   往它身上写的是**贴图 / UV / 宽高 / 锚点**四样 —— 全是客户端那份几何。旧写法关掉开关时对这些对象
--   **一个字节都不还**（它们不在 `MDQ.own` 里）⇒ 用户看到的就是「**关掉了，地图上还是我们画的那几张
--   （缩放不对的）**」= 「关闭之后依然在生效」的另一半（闸门那半见 `MDQ.renderCurrent` 头部的 1.75.54d）。
--   口径：原值 = **我们第一次写它之前**读到的那份（唯一可信的原值，同 DebugBox 的「自定义前」）；
--   ★按**池位号**存（不是按对象）⇒ 天然有界（≤ `poolMax`）；同号换了新对象就整条换新（旧对象已不是
--     客户端当前那格，可见性由藏账负责）。
MDQ.origIdx = {}
-- ★1.75.59k：`key` 既可以是**池位号**（复用路径），也可以是**对象本身**（接管守护藏原生层的路径）——
--   两种来源都进同一张原值账、由 `origRestore` 一次还清（★不许各写一套「抓/还」）。
--   为什么接管那一路必须按**对象**存：枚举出来的原生层**可能不在 `_G` 里**（同号会有两条），按序号存会互相覆盖。
MDQ.origGrab = function(n, t, ctx)
  if t == nil then return nil end
  local objKey = (type(n) == "number") and n or t
  local rec = MDQ.origIdx[objKey]
  if rec ~= nil and rec.obj == t then return rec end
  -- ★1.75.59k：**两种契约**（写的东西不同 ⇒ 还的东西也必须不同，绝不用一套逻辑套两种场景）：
  --   `"pool"`（默认）= 我们复用的客户端池位，写的是**贴图/UV/宽高/锚点** ⇒ 还原要**五样齐全**，
  --             抓不齐就**先藏**（宁缺一块，绝不把我们那份留在屏幕上）；
  --   `"hide"` = 接管守护藏的原生层，我们只写 **显隐 + alpha** ⇒ 还原就是 `Show` + 还 alpha，
  --             **绝不 Hide**（我们没动它的几何，把它藏起来才是错的）。
  local rec2 = nil
  rec = { obj = t, pts = {}, ok = true, ctx = (ctx == "hide") and "hide" or "pool" }
  local okt, tex = pcall(t.GetTexture, t)
  if okt then rec.tex = tex else rec.ok = false end
  local okw, w = pcall(t.GetWidth, t)
  if okw then rec.w = tonumber(w) end
  local okh, h = pcall(t.GetHeight, t)
  if okh then rec.h = tonumber(h) end
  local oks, sh = pcall(t.IsShown, t)
  if oks then rec.shown = (sh == true) else rec.ok = false end
  -- ★★★1.75.64：**绘制层也进原值账**（第 7 样）—— 实景图层要写 `OVERLAY`（用户点名「优先级最高.遮盖同组其它层」）,
  --   而那是往**客户端自己的池位纹理**上写的属性 ⇒ 抓不到原值就还不了（本项目铁律「改属性前先把原值读下来」）。
  --   ★读不到 ⇒ `rec.layer` 留 nil（**不判整条失败**）：还原时看到 nil 就**不写 layer**（有原值才写）。
  local okl, ly = pcall(t.GetDrawLayer, t)
  if okl and type(ly) == "string" and ly ~= "" then rec.layer = ly end
  local okn, np = pcall(t.GetNumPoints, t)
  if okn and tonumber(np) then
    for i = 1, tonumber(np) do
      -- ★5 个返回一个都不能少（锚点 / 相对对象 / 相对锚点 / x / y）—— 少存一个，还原出来的锚点就是错的
      local okp, p, relTo, relP, x, y = pcall(t.GetPoint, t, i)
      if okp and p ~= nil then
        table.insert(rec.pts, { p, relTo, relP, tonumber(x) or 0, tonumber(y) or 0 })
      end
    end
  end
  local oktc, ta, tb, tc2, td = pcall(t.GetTexCoord, t)
  if oktc and tonumber(ta) then
    rec.tc = { tonumber(ta), tonumber(tb) or 0, tonumber(tc2) or 0, tonumber(td) or 1 }
  end
  -- ★★★1.75.59k（用户：「取消『只 Hide/Show』这条禁令，我要完成功能」）：**alpha 进原值集合**。
  --   ★读不到 ⇒ `rec.a` 留 nil（**不判整条失败**）：调用方看到 nil 就**不写 alpha**（有原值才写 —— 否则还不了）。
  local oka, a = pcall(t.GetAlpha, t)
  if oka and tonumber(a) then rec.a = tonumber(a) end
  MDQ.origIdx[objKey] = rec
  return rec
end

-- ★1.75.59k：**单条还回**（接管藏账放回最老那一条时用；与整批还回**同一套代码**，不复制第二份）。
--   ★参数 = **原值账的键**（池位号**或**对象本身）—— 池位那一路是按序号存的，按对象查会查空（曾因此漏还原）。
--   返回 true = 还原成功, false = 抓不到原值（池位那一路会先把这一格 Hide）
MDQ.origRestoreOne = function(key)
  if key == nil then return false end
  local rec = MDQ.origIdx[key]
  if rec == nil then return false end
  local t = rec.obj
  if t == nil then MDQ.origIdx[key] = nil return false end
  local ok = false
  if rec.ctx == "hide" then
    -- ★守护账：我们只写过**显隐 + alpha** ⇒ 只还这两样，**绝不 Hide、绝不动几何**
    if rec.shown == true then pcall(t.Show, t) end
    if rec.a ~= nil then pcall(t.SetAlpha, t, rec.a) end
    ok = true
  elseif rec.ok and rec.tex ~= nil and rec.w ~= nil and rec.h ~= nil and table.getn(rec.pts) > 0 then
    pcall(t.SetTexture, t, rec.tex)
    if rec.tc ~= nil then pcall(t.SetTexCoord, t, rec.tc[1], rec.tc[2], rec.tc[3], rec.tc[4]) end
    pcall(t.SetWidth, t, rec.w)
    pcall(t.SetHeight, t, rec.h)
    if rec.a ~= nil then pcall(t.SetAlpha, t, rec.a) end
    -- ★1.75.64：绘制层（第 7 样）—— 只在抓到过原值时才写回（抓不到就保持现状，绝不留一个还不了的层）
    if rec.layer ~= nil then pcall(t.SetDrawLayer, t, rec.layer) end
    pcall(t.ClearAllPoints, t)
    for _, p in ipairs(rec.pts) do pcall(t.SetPoint, t, p[1], p[2], p[3], p[4], p[5]) end
    if rec.shown == true then pcall(t.Show, t) else pcall(t.Hide, t) end
    ok = true
  else
    pcall(t.Hide, t)
  end
  MDQ.ownSet[t] = nil
  MDQ.wroteObj[t] = nil
  MDQ.origIdx[key] = nil
  return ok
end

-- 把复用的客户端池位**还回原样**（贴图 / UV / 宽高 / 锚点 / 显隐 / **alpha**；幂等）。返回 还回 N 个, 抓不到原值 M 个。
--   ★抓不到原值（本客户端某个读口缺席 / 探针失败）⇒ **绝不把我们写的那份留在屏幕上**：先把这一格藏起来
--     （客户端下一次摆版式会自己恢复），并如实记一行 —— 宁可暂时少一块，也不留一张缩放不对的图。
MDQ.origRestore = function(why)
  local n, bad = 0, 0
  for idx, rec in pairs(MDQ.origIdx or {}) do
    local t = rec and rec.obj
    if t ~= nil then
      if MDQ.origRestoreOne(idx) then n = n + 1 else bad = bad + 1 end
    end
    MDQ.origIdx[idx] = nil
  end
  if n > 0 or bad > 0 then
    pcall(mfLog, "还原复用的客户端池位（%s）：原贴图/几何还回 %d 个%s", tostring(why), n,
      (bad > 0) and ("；**抓不到原值** " .. tostring(bad) .. " 个已先隐藏（客户端重摆版式时自己恢复）") or "")
  end
  return n, bad
end

-- 把**我们自己补建**的层收起来（Hide）—— WoW 1.12 **没有销毁纹理的 API**（创建即常驻），所以只能藏：
--   藏了之后它们 `IsShown()==false` ⇒ 任何「按本图在用挑层」的逻辑都**不会**再把它们当成客户端的层
--   去抓原值（否则我们会把自己画的几何当原值再折一遍，越折越大）。
--   ★幂等；`MDQ.own`/`made` 一起清（下次要用会重新按需补建）。
MDQ.release = function(why)
  -- ★1.75.59q：同序号去重的**会话结论**一起作废（换图 / 收层之后对象与构成都会变 ⇒ 必须重新探）
  if type(MDQ.dupStat) == "table" then
    MDQ.dupStat.cache, MDQ.dupStat.mk = {}, nil
    MDQ.dupStat.groups, MDQ.dupStat.hid, MDQ.dupStat.same, MDQ.dupStat.blind = 0, 0, 0, 0
  end
  MDQ.dupSaid = nil
  -- ★★★1.75.59j：**实验也必须收**（绝不留「永久隐形/永久换过的贴图」）——
  --   关开关 / 关功能 / 任何收层三条路都会走到 `release` ⇒ 实验的还原天然全覆盖。
  if MDQ.trialActive and MDQ.trialActive() then pcall(MDQ.trialStop, "收层（" .. tostring(why) .. "）") end
  -- ★★★1.75.52 六改：先把「接管守护」藏过的**客户端原生层**全部 Show 还回（绝不永久藏）——
  --   调在这里 ⇒ 三条路（关开关 / 还原·关功能 / 任何收层）**天然全覆盖**，不靠人去记全调用点。
  pcall(MDQ.holdShowAll, tostring(why))
  -- ★★★1.75.54e：再**把复用的客户端池位还原成原样**（贴图/UV/尺寸/锚点/显隐四样）——
  --   不还 = 关掉开关后地图上仍是我们的（缩放不对的）那几张 ⇒ 用户眼里「关掉了还在生效」。
  pcall(MDQ.origRestore, tostring(why))
  local n = 0
  for k, t in pairs(MDQ.own or {}) do
    if t ~= nil then pcall(t.Hide, t) n = n + 1 end
    MDQ.ownSet[t] = nil
    MDQ.own[k] = nil
  end
  for nm in pairs(MDQ.made or {}) do MDQ.made[nm] = nil end
  MDQ.slot = {}    -- ★1.75.54：收层 = 把那几层藏了 ⇒ 写前比对全部作废（下次要画会老老实实重写一遍）
  MDQ.alphaZeroByIdx = {}   -- ★1.75.60g：我们自己的 alpha-0 账跟着作废（换图/收层后同一序号不是同一块）
  MDQ.newN = 0
  MDQ.saidMk = nil
  if n > 0 then
    pcall(mfLog, "收层（%s）：我们补建的 %d 个叠加层已 Hide（纹理不能销毁，只能藏；藏了就不再被当成客户端的层）",
      tostring(why), n)
  end
  return n
end

-- ★★★1.75.54d/54e：**「关闭世界迷雾」关掉 = 把这一路上动过的东西全部交还给客户端**（幂等，一拍一次）。
--   顺序（即判据）：① `MDQ.release` = 藏起我们自建的层 + 还回守护/收尾藏过的原生层 + 还原复用池位的原值；
--                    ② 残留清理的账再还一次（它跟这个开关一起写，两族都不会漏）；
--                    ③ 会话状态复位（安全阀/渲染账/性能计数）⇒ 下次打开从零开始，不带着上一轮的降档跑。
--   ★**只做一次**（`MDQ.offDone` 门）：关着时 tick 每拍都会走到这里，逐拍还回是白烧（且会让播报刷屏）。
MDQ.shutdown = function(why)
  if MDQ.offDone then return 0 end
  MDQ.offDone = true
  MDQ.lastRenderN = 0
  -- ★1.75.59o：关掉迷雾 ⇒ **拖拽当场结束 + 拖拽柄与贴图列表全部收起**（补偿数据**保留**，那是用户的数据）
  if MDQ.editStop then pcall(MDQ.editStop, "关闭世界迷雾") end
  if MDQ.grabHideAll then pcall(MDQ.grabHideAll, "关闭世界迷雾") end
  MDQ.perfGuard, MDQ.perfSlowN = false, 0
  local a = 0
  local ok1, r1 = pcall(MDQ.release, tostring(why))
  if ok1 then a = tonumber(r1) or 0 end
  pcall(MDQ.staleShowAll, tostring(why))
  pcall(mfLog, "[mapfit] %s：收层 %d 个 + 复用池位还原原值 + 藏过的原生层全部还回"
    .. "（此后不再渲染、不再接管；再打开时从零开始）", tostring(why), a)
  return a
end

-- 渲染 + **写后自证**（返回 块数, 区域数, 判定文本）；`silent` = 一个字都不打（逐帧重申那条路）
--   ★`quiet` 只为与渲染节拍的调用约定对齐而保留；本档的播报节流由 `MDQ.saidMk`（每图一次）与
--     「k 变了也报一次」（缩放级别变了 = 真事件）负责。
MDQ.renderCurrent = function(es, quiet, silent, withGuard)
  -- ★★★1.75.54d + 1.75.54e（用户报障「关闭功能之后依然在生效」，以及「开关状态要做好正确的功能开关状态维护.
  --   不要影响到原始地图的功能」）：**总开关闸排在所有探测/读写之前**（本项目铁律「关掉零动作」）——
  --   关着**连 `smMapInfo()` 都不读**，只判一个布尔就早退。
  --   为什么原来会「关掉还在生效」：闸门只在「护守」（`MDQ.holdTick` 首行）与「残留清理」（`staleTick` 的
  --   让位条件）里 ⇒ **渲染本身没有闸门** ⇒ 取消勾选后地图照旧被我们每拍整张重写；
  --   而且写进客户端池位的那份几何**从来没还过**（见 `MDQ.origRestore`）⇒ 屏幕上看还是我们的。
  --   ⇒ 关的那一拍走 `MDQ.shutdown` **一次性收干净**（收自建层 + 还回藏过的原生层 + 还原复用池位的原值），
  --     之后每拍只早退一次；再打开时（`offDone` 复位）照旧从零渲染。
  if not MDQ.swm() then
    MDQ.shutdown("世界迷雾已关")
    return 0, 0, "世界迷雾已关（不接管）"
  end
  MDQ.offDone = false
  local file = select(1, smMapInfo())
  if type(file) ~= "string" or file == "" then return 0, 0, "读不到当前地图文件名" end
  -- ★★★1.75.64：**图层类型在这里分派**（区域彩图 = 逐区域/逐块的老口径；区域实景 = 整区一张 JPG）——
  --   两条路**共用**后面的倍率 / 守护 / 安全阀 / 写后自证，只有「本图的基表」与「画法」不同。
  local jpg = MDQ.jpgMode()
  local m = jpg and MDQ.jpgBase(file) or MDQ.areaOf(file)
  -- ★六改 b：与 `MDQ.holdN` / `MDQ.render` 同一个表查找（大小写不敏感）
  -- ★★★1.75.53（用户：「插件要绝对独立…不然发布上去别人又可能找不到贴图」）：**贴图准入** ——
  --   表里有这张图，但「自带 media 那一份」与「客户端自带的 Interface\WorldMap 那一份」**都加载不出来**
  --   ⇒ **这一张图一帧都不接管**（不渲染、不藏原生、不建层），并且把之前藏过的原生层**当场还回**。
  --   依据 = 本项目铁律「拿不到证据就一个字节都不碰」：宁可保持客户端原样，也绝不画出一片空白图。
  if type(m) == "table" and (jpg and MDQ.jpgSrcOf(file) or MDQ.srcOf(file)) == "none" then
    pcall(MDQ.release, "本图贴图加载不出来")   -- 把上一张图藏过的原生层与本图自建的层都还回/收起
    MDQ.lastRender = { map = file, n = 0, areas = 0, inTbl = true, full = false, k = 1, src = "none",
      why = jpg and "本图实景 JPG（media\\WorldMapJpg）加载不出来" or "本应用加载不出这批贴图（自带 media\\WorldMap 与客户端 Interface\\WorldMap 都没有）" }
    if type(MDQ.noTexSaid) ~= "table" then MDQ.noTexSaid = {} end
    if not MDQ.noTexSaid[file] then
      MDQ.noTexSaid[file] = true
      if jpg then
        pcall(smFitSay, "世界迷雾·实景：地图=%s ｜ **加载不出**这张实景 JPG（`media\\WorldMapJpg\\%s`）"
          .. "⇒ **这一张图不接管**（客户端自己的探索层保持原样；不渲染、不藏原生）。体检：/ehm mapfit 贴图",
          tostring(file), tostring(file))
      else
        pcall(smFitSay, "世界迷雾：地图=%s ｜ 本客户端**加载不出**这批探索层贴图"
          .. "（`media\\WorldMap\\%s\\…` 与 `Interface\\WorldMap\\%s\\…` 两份都探不到）"
          .. "⇒ **这一张图不接管**（客户端自己的探索层保持原样；不渲染、不藏原生）。体检：/ehm mapfit 贴图",
          tostring(file), tostring(file), tostring(file))
      end
    end
    return 0, 0, "本图贴图加载不出来（不接管）"
  end
  -- ★★★1.75.51（用户：「缩放要根据当前缩放级别和数据库实时计算」）：倍率**现读**，不留常数。
  local k, kSrc = 1, "表里没有这张图（不渲染）"
  if type(m) == "table" then k, kSrc = MDQ.kLive(file, m, es) end
  -- ★1.75.54b：**节流那一拍强制整批重写**（`force = withGuard ~= false`）—— 客户端会在我们写完之后自己
  --   再摆一次它那批池位纹理（首次开图尤其明显），只靠「写前比对」会跳过重申 ⇒ 客户端那套缩放不对的
  --   几何留在屏上（用户报的「首次地图打开客户端自身的贴图缩放异常」）。逐帧那条 silent 路才用比对省开销。
  local n, nArea, inTbl, full, why, nExist, nNew
  if jpg then
    n, nArea, inTbl, full, why, nExist, nNew = MDQ.jpgRender(file, k, withGuard ~= false)
  else
    n, nArea, inTbl, full, why, nExist, nNew = MDQ.render(file, k, withGuard ~= false)
  end
  -- ★六改 b：把本拍的渲染账留在 `MDQ` 上（只读体检 `/ehm mapfit 残留` 直接摊出来 ⇒
  --   「数据库查出来的层到底加进去没有」不再靠猜）
  MDQ.lastRender = { map = file, n = n, areas = nArea, inTbl = inTbl, full = full, why = why, k = k }
  -- ★★★1.75.52 六改：**接管守护**与渲染**同拍**（换图/开图爆发窗内逐帧重申，之后 0.3s 一拍）——
  --   藏「客户端原生层」+ 数量守护（序号超出本图应有块数的池位一律藏）+ 存在性守护（我们自建的块被藏就复位）。
  --   ★必须排在 `MDQ.render` **之后**：渲染先写/Show 我们自建的块，守护这一拍才判得出「谁是我们自建的」。
  -- ★★★1.75.54：**逐帧重申那条 silent 路径不跑护守**（原写法每帧都跑 `holdTick` ⇒ 每帧一次
  --   `GetRegions()` + 逐 region `GetName()` 的字符串风暴，地区一多直接把帧率吃掉）。
  --   护守按**节流节拍**跑（爆发窗 0.1s / 稳态 0.3s）足够 —— 客户端把原生层 Show 回来时，
  --   最迟 0.3s 就会被再藏一次，肉眼看不到。
  local _t0 = (type(GetTime) == "function") and GetTime() or 0
  local hHid, hBack, hSeen, hWant, hAgain = 0, 0, 0, 0, 0
  if withGuard ~= false then
    hHid, hBack, hSeen, hWant, hAgain = MDQ.holdTick(file)
  end
  -- ★★★1.75.54 **安全阀**：单拍太慢 ⇒ **降档**（少重申，绝不卡死）+ 如实出声一次。
  --   为什么会有慢拍：地区多 ⇒ 块多（每块一次写）+ 客户端原生层多（护守要逐个判）。
  --   判据 = 单拍 > `MDQ.SLOW_MS`，或连续 3 拍 > `MDQ.SLOW_WARN_MS`。
  local _ms = ((type(GetTime) == "function") and (GetTime() - _t0) or 0) * 1000
  MDQ.perfMs = _ms
  if _ms > (tonumber(MDQ.SLOW_WARN_MS) or 6) then
    MDQ.perfSlowN = (tonumber(MDQ.perfSlowN) or 0) + 1
  else
    MDQ.perfSlowN = 0
  end
  local ring = MDQ.perfRing
  if type(ring) == "table" then
    table.insert(ring, { ms = _ms, wrote = tonumber(MDQ.wroteN) or 0, skip = tonumber(MDQ.skipN) or 0,
      n = n, seen = tonumber(hSeen) or 0, k = k })
    while table.getn(ring) > (tonumber(MDQ.PERF_RING_MAX) or 12) do table.remove(ring, 1) end
  end
  if (not MDQ.perfGuard) and (_ms > (tonumber(MDQ.SLOW_MS) or 12)
      or (tonumber(MDQ.perfSlowN) or 0) >= 3) then
    MDQ.perfGuard = true
    pcall(smFitSay, "世界迷雾：本拍耗时 **%.0f ms**（地图=%s ｜ %d 块 ｜ 客户端叠加层 %d 条）"
      .. "⇒ 已**自动降档**：逐帧重申改成 0.5s 一拍（护守照旧每拍查数量/存在性；功能不受影响）。"
      .. "取证：/ehm mapfit perf", _ms, tostring(file), n, tonumber(hSeen) or 0)
    pcall(mfLog, "[perf] 降档：%.1f ms ｜ %s ｜ %d 块 ｜ 写 %d ｜ 跳过 %d",
      _ms, tostring(file), n, tonumber(MDQ.wroteN) or 0, tonumber(MDQ.skipN) or 0)
  end
  -- 写后自证：读回**我们真正写的那张**第一块（可能是客户端原有的池位，也可能是我们自己补建的匿名纹理）
  --   两种已知口径都认（读回 = 写入值 / 读回 = 写入值 × es）—— 都对不上就如实说「判不出」。
  local verdict = "（没渲染出任何块）"
  local t1 = MDQ.lastTex
  if n > 0 and MDQ.lastW and t1 ~= nil and type(t1.GetWidth) == "function" then
    local okw, v = pcall(t1.GetWidth, t1)
    local lw = (okw and tonumber(v)) and tonumber(v) or nil
    local e = tonumber(es) or 1
    if lw == nil then
      verdict = string.format("写入 %.1f ⇒ 读回读不到（判不出）", MDQ.lastW)
    elseif math.abs(lw - MDQ.lastW) <= 0.6 then
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **生效**（读回=写入值）", MDQ.lastW, lw)
    elseif math.abs(lw - MDQ.lastW * e) <= 0.6 then
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **生效**（读回=写入值×es %.2f）", MDQ.lastW, lw, e)
    else
      verdict = string.format("写入 %.1f ⇒ 读回 %.1f ⇒ **判不出/没接受**（既不是写入值，也不是 ×es %.2f）", MDQ.lastW, lw, e)
    end
  end
  if silent then return n, nArea, verdict end  -- 逐帧重申那条路：一个字都不打（连取证环也不进）
  local mk = smMapKey() or file
  -- 播报门 = **每图一次** + **k 变了再报一次**（用户在缩放地图 ⇒ 倍率真的变了，值得一行）
  local kChg = (MDQ.lastKSaid == nil) or (math.abs((tonumber(MDQ.lastKSaid) or 0) - k) > 0.03)
  if MDQ.saidMk ~= mk or kChg then
    MDQ.saidMk, MDQ.lastKSaid = mk, k
    local line = string.format("世界迷雾：地图=%s ｜ 表里 %d 区 ⇒ 渲染 %d 块（客户端既有 %d ｜ 新加 %d）"
      .. "｜ 倍率 k=%.3f（%s）｜ 外框 es=%.3f ｜ 首块=%s 表 %.0fx%.0f @%.0f,%.0f ⇒ 写 %.0fx%.0f @%.0f,%.0f%s",
      tostring(file), nArea, n, tonumber(nExist) or 0, tonumber(nNew) or 0,
      k, tostring(kSrc), tonumber(es) or 1,
      tostring(MDQ.lastArea or "?"), tonumber(MDQ.lastTw) or 0, tonumber(MDQ.lastTh) or 0,
      tonumber(MDQ.lastTox) or 0, tonumber(MDQ.lastToy) or 0,
      tonumber(MDQ.lastW) or 0, tonumber(MDQ.lastH) or 0,
      (tonumber(MDQ.lastTox) or 0) * k, -((tonumber(MDQ.lastToy) or 0) * k),
      ((why and (" ｜★" .. why)) or "")
      -- ★1.75.52 六改：守护的三个数字（数量/存在性）摊在**同一行**（用户点名要「数量、存在性都要检查」）
      .. string.format(" ｜ 守护：藏原生 %d（又冒出来再藏 %d）｜ 复位我们自建 %d ｜ 枚举池位 %d（认出我们画的 %d）｜ 本图应有 %d 块",
        tonumber(hHid) or 0, tonumber(hAgain) or 0, tonumber(hBack) or 0, tonumber(hSeen) or 0,
        tonumber(MDQ.holdStat.ours) or 0, tonumber(hWant) or 0))
    pcall(mfLog, "%s ｜ 自证：%s", line, verdict)
    -- ★「真出问题必须出声」（本项目判据）：本图不在表里 / 一块都没渲 / 渲不完整 / 自证判不出 / 倍率判不出 ⇒ 常开出口上屏；
    --   正常的成功行走**详细档**（用户：「清理之前调试的一些日志」）—— 全量永远在 mapFitTrace 取证环里。
    local prob = (not inTbl) or (not full) or (n == 0)
      or (string.find(verdict, "判不出", 1, true) ~= nil)
      or (string.find(kSrc, "判不出", 1, true) ~= nil)
    if prob then
      smFitSay("%s ｜ 自证：%s", line, verdict)
    else
      smFitSayV("%s ｜ 自证：%s", line, verdict)
    end
  end
  return n, nArea, verdict
end
MDQ.staleLevel = function(file)
  if type(GetCurrentMapZone) == "function" then
    local okz, z = pcall(GetCurrentMapZone)
    if okz and tonumber(z) ~= nil then
      if tonumber(z) == 0 then return true, "GetCurrentMapZone=0" end
      return false, string.format("GetCurrentMapZone=%d", tonumber(z))
    end
  end
  local tbl = rawget(_G, "EVAL_MAP_OVERLAY_DATA")
  if type(tbl) == "table" then
    if type(file) == "string" and file ~= "" and tbl[file] ~= nil then
      return false, "S_WorldMap 表里有这张图（区域图）"
    end
    return true, "S_WorldMap 表里没有这张图（大陆/世界/城市级）"
  end
  return false, "判不出（GetCurrentMapZone 与 S_WorldMap 表都读不到）"
end

-- ★「藏了哪些纹理」记进**有界落盘环**（`SM_CFG.staleLog`，最新在前、最多 `MDQ.STALE_LOG_MAX` 条）：
--   用户要的就是「把哪些纹理隐藏了记下来」；★只上屏的日志 `/reload` 后就没了、事后也没法取证
--   （本项目纪律：探针/判定的**原话必须落盘**，否则用户跑一趟等于白跑）。
MDQ.staleLogPut = function(line)
  if type(SM_CFG) ~= "table" then return 0 end
  local t = SM_CFG.staleLog
  if type(t) ~= "table" then t = {} SM_CFG.staleLog = t end
  table.insert(t, 1, tostring(line))
  local n = table.getn(t)
  while n > MDQ.STALE_LOG_MAX do t[n] = nil n = n - 1 end
  return table.getn(t)
end

-- 读落盘环（最新在前，最多 max 条）
MDQ.staleLogGet = function(max)
  local t = (type(SM_CFG) == "table") and SM_CFG.staleLog or nil
  if type(t) ~= "table" then return {} end
  local out = {}
  local lim = math.min(tonumber(max) or MDQ.STALE_LOG_MAX, table.getn(t))
  for i = 1, lim do out[i] = tostring(t[i]) end
  return out
end

-- 藏账的层名清单（播报 / 体检用）：`WorldMapOverlay1、WorldMapOverlay3…（共 N 个）`
MDQ.staleNames = function(max)
  local names = {}
  for _, rec in pairs(MDQ.staleHid) do
    table.insert(names, tostring(rec and rec.name or "?"))
  end
  table.sort(names)
  local n = table.getn(names)
  if n == 0 then return "（无）" end
  local lim = math.min(tonumber(max) or 8, n)
  local head = {}
  for i = 1, lim do head[i] = names[i] end
  local s = table.concat(head, "、")
  if n > lim then s = s .. "…" end
  return s .. string.format("（共 %d 个）", n)
end

-- 开关真值（唯一入口）：`SM_CFG.staleClean` —— **默认开**（★1.75.65 起：它与「关闭世界迷雾」是**同一个
--   控制**（1.75.52 合并），而那个勾选框现在**默认勾选** ⇒ 清理也默认开；显式 false = 用户主动关过 = 关）；
--   开着时：换到「没有探索层数据」的图才把上一张图残留的池位藏起来，
--   有数据的图**必须还回**（关掉零动作：不再新藏 + 当场把藏账里的层全部还回）。
MDQ.staleOn = function()
  return (type(SM_CFG) == "table") and SM_CFG.staleClean == true
end

-- 名字像不像「客户端叠加层池位」：**按前缀 `WorldMapOverlay` 认**（DebugBox 图层树里那批就是 `WorldMapOverlayN`）。
--   ★★★1.75.52 四改（用户原话就一个词：「**WorldMapOverlayN**」）⇒ 判据从「严格数字后缀」**放宽成前缀 `WorldMapOverlay*`**：
--     只认数字后缀的话，真机上若出现字母/其它后缀（`WorldMapOverlayN` 这种写法）就**一条都认不出**，
--     而且是**静默失效**（一个字节都不碰、图上残留照旧）—— 这正是本项目最怕的那种坑。
--   ★仍然只是**名字证据**：底图瓦片 `WorldMapDetailTile*`、匿名纹理（`GetName()` 读不到）照样**一个字都不碰**。
MDQ.stalePoolName = function(o)
  local nm = string.lower(tostring(frameName(o) or ""))
  return (nm ~= "" and string.find(nm, "worldmapoverlay", 1, true) == 1)
end

-- 世界地图贴图路径里的**图名段**：`…\WorldMap\<图名>\…`（`/` 与 `\` 都认；大小写不敏感；容忍 `/Game/Interface/` 前缀）
--   ★返回 nil = **判不出**（不是世界地图贴图 / 路径读不到）⇒ 调用方**一律不碰**（没证据不动手，本项目铁律）。
MDQ.staleSeg = function(path)
  local s = string.lower(tostring(path or ""))
  if s == "" then return nil end
  s = string.gsub(s, "/", "\\")
  local i = string.find(s, "\\worldmap\\", 1, true)
  if i == nil then
    if string.sub(s, 1, 9) == "worldmap\\" then i = 0 else return nil end
  end
  local seg = string.match(string.sub(s, i + 10), "^([^\\]+)")
  if seg == nil or seg == "" then return nil end
  return seg
end

-- 路径相等（大小写 + 分隔符都不敏感；全长相等 或「末段文件名」相等都算）—— 与引擎自报的叠加层路径比对用
--   ★分隔符必须归一：本客户端 `GetTexture()` 报反斜杠，而 `GetMapOverlayInfo()` 可能报 `/Game/Interface/…` 正斜杠形态
--     （追踪图标那条已实测是这个形态）⇒ 不归一就会「明明是同一张图却判成不在清单里」。
MDQ.samePath = function(a, b)
  local x = string.lower(tostring(a or ""))
  local y = string.lower(tostring(b or ""))
  if x == "" or y == "" then return false end
  x, y = string.gsub(x, "/", "\\"), string.gsub(y, "/", "\\")
  if x == y then return true end
  local lx, ly = string.match(x, "([^\\]+)$"), string.match(y, "([^\\]+)$")
  return (lx ~= nil and lx == ly)
end

-- 引擎自报的叠加层路径清单（本图这一拍的真值）；读不到 ⇒ 空表（★空表 = 引擎说「本图没有叠加层」，
--   这时任何「路径属于别的图」的池位都必是残留 —— 与 1.75.45d「自报 0 条 ⇒ 没有可适配的层」同口径）。
MDQ.staleEngineList = function()
  local want = {}
  local n = tonumber(smNumOverlays()) or 0
  for i = 1, n do
    local okg, nm = pcall(function() return GetMapOverlayInfo(i) end)
    if okg and type(nm) == "string" and nm ~= "" then table.insert(want, nm) end
  end
  return want, n
end

-- 藏账条数
MDQ.staleLedgerN = function()
  local c = 0
  for _ in pairs(MDQ.staleHid) do c = c + 1 end
  return c
end

-- ★★★1.75.52 三改（用户看了 DebugBox 图层树后的定案，原话：「**非区域地图 就将 WorldMapOverlay 隐藏了就可以**」）
--   ⇒ 规则**简化成两条**（不再看贴图路径、不再比引擎清单 —— 那两条只留在只读体检里当诊断）：
--     · **非区域地图**（大陆 / 世界级，`MDQ.staleLevel` = true）⇒ 把 `WorldMapOverlay<n>` 池位**全部 `Hide`**；
--     · **区域地图**（`GetCurrentMapZone() > 0` / 表里有这张图）⇒ 把我们藏过的**全部 `Show` 还回**
--       （这一级客户端要用这批池位画本图的探索层；★**不还回就是永久窟窿** —— 这条是本次改动的第一判据）。
--   ★纪律不变：**只 `Hide`/`Show`**，绝不 `SetTexture`、绝不动 UV、绝不改几何；
--     **名字不合 `WorldMapOverlay*` 的对象（底图瓦片 `WorldMapDetailTile*` / 匿名纹理）一个字节都不碰**。
--   ★**藏了哪几条记名 + 落盘**（`SM_CFG.staleLog` 有界 40）—— 用户 1.75.52 二改点名要的那一条。
--   ★返回 本轮新藏 N, 本轮还回 M, 看过的池位 k, 当前图名, 藏账条数, 级别依据
MDQ.staleTick = function()
  local fileRaw = tostring(select(1, smMapInfo()) or "")
  local want = string.lower(fileRaw)
  local ledger0 = MDQ.staleLedgerN()
  if want == "" then return 0, 0, 0, "?", ledger0, "读不到地图名" end
  local lvl, lvlWhy = MDQ.staleLevel(fileRaw)
  -- ★★★1.75.52 五改（用户真机定案的那条**触发条件**）：「**在切换到某个图、如果检索不到目标地图数据的情况下，
  --   会将刚开（上一张）地图的默认纹理直接显示在这个地图上**，导致地图错乱 —— 世界地图 / 板块地图 /
  --   **某些没有探索层数据的地图**都是相同问题」。
  --   ⇒「**本图没有探索层数据**」= 动手的信号，三条**任一**成立即可（证据从硬到软）：
  --     ① `GetNumMapOverlays() == 0` —— **引擎自报本图一条叠加层都没有**（最硬：本图压根不用这批池位
  --        ⇒ 任何还显示着的 `WorldMapOverlay*` 必是上一张图的残留）★这一条正是用户描述的那个场景；
  --     ② **非区域地图**（世界/板块级，用户前一条定案：「非区域地图就将 WorldMapOverlay 隐藏了就可以」）；
  --     ③ 判不出级别且引擎也读不到 ⇒ 走第 ①/② 的 false 分支（**不动手**，本项目铁律）。
  --   ★反之：**本图有数据**（区域图 且 引擎自报 ≥1 条）⇒ **把我们藏过的还回**（那一级客户端要自己摆）。
  --     ★自愈性：引擎的 0 条若只是**尚未摆版式**的瞬态，下一拍它报 ≥1 ⇒ 规则翻回「还回」⇒ 不会留窟窿。
  local engineN = select(2, MDQ.staleEngineList())
  engineN = tonumber(engineN) or 0
  -- ★★★1.75.52 六改 c：**替代开关开着、且本图在表里 ⇒ 残留清理整段让位**（可见性归「接管守护」：
  --   那一档客户端原生层一律要藏、还要按表自行添加）—— 两套规则同时动手只会互相打架（藏了又被还回）。
  --   ★**只在「本图在表里」时让位**（1.75.52 要求「全图默认开」、1.75.59c 起**默认不勾选** ⇒ 这条更重要）：表里没有这张图的图
  --   （大陆 / 世界 / 城市）**接管守护本来就不动手**，那时残留清理必须继续干活，否则两档都失效。
  if MDQ.swm() and MDQ.holdN(fileRaw) > 0 then
    return 0, 0, 0, want, ledger0, "替代开关已开（本图在表里 ⇒ 可见性归「接管守护」）"
  end
  local noData = (lvl == true) or (engineN == 0)
  local whyLvl = lvl and ("非区域地图：" .. tostring(lvlWhy))
    or (engineN == 0 and "引擎自报本图 0 条叠加层（= 本图没有探索层数据）")
    or ("本图有探索层数据（引擎自报 " .. tostring(engineN) .. " 条）")
  local fr = _G["WorldMapDetailFrame"]
  local okFr = (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function"
  -- ① 本图**有**数据 ⇒ **还回**（绝不把「藏」的状态带过去；幂等：账空了就什么都不做）
  if not noData then
    local back = 0
    if ledger0 > 0 then back = MDQ.staleShowAll("本图有探索层数据（" .. tostring(whyLvl) .. "）") end
    return 0, back, 0, want, MDQ.staleLedgerN(), whyLvl
  end
  -- ② 本图没有探索层数据 ⇒ 把叠加层池位**全部藏掉**（空闲时也允许新藏：客户端随后又 Show 出来就再藏，残留不许回潮）
  if not okFr then return 0, 0, 0, want, ledger0, whyLvl end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then return 0, 0, 0, want, ledger0, whyLvl end
  local hid, seen, nTex = 0, 0, 0
  local samples = {}
  for _, o in ipairs(regs) do
    -- 唯一的证据 = **名字**是叠加层池位；名字不合（底图瓦片 / 匿名装饰）⇒ 一个字节都不碰
    if o ~= nil then
      nTex = nTex + 1
      if nTex <= 6 then
        local nmS = frameName(o)
        table.insert(samples, (nmS ~= "" and nmS ~= "?") and nmS or "(无名)")
      end
      if MDQ.stalePoolName(o) then
        seen = seen + 1
        local oks, shown = pcall(o.IsShown, o)
        if oks and shown == true then
          local okh = pcall(o.Hide, o)
          if okh then
            hid = hid + 1
            -- ★账上没有 ⇒ 第一次藏：记名 + 落盘；★账上已有、却又是显示着的 ⇒ **客户端又把它 Show 出来了**，
            --   照样再藏一次（残留不许回潮），但**不重复记名**（免得一次开图刷满 40 条环）。
            if MDQ.staleHid[o] == nil then
              local nm = frameName(o)
              local okp, path = pcall(o.GetTexture, o)
              if not okp then path = nil end
              MDQ.staleHid[o] = { name = nm, path = tostring(path) }
              MDQ.staleLogPut(string.format("藏：地图=%s（%s）｜ %s ｜ 贴图=%s",
                tostring(want), tostring(whyLvl), tostring(nm), tostring(path)))
            end
          end
        end
      end
    end
  end
  -- ★★★1.75.52 四改：**一个池位名都没认出**时如实出声（否则「名字判据与真机对不上」会变成**静默失效** ——
  --   一个字节都不碰、图上残留照旧，而用户以为修好了）。样本名一起给出来，便于一眼看出真机叫什么。
  if nTex > 0 and seen == 0 then
    MDQ.staleNoPoolSay = (tonumber(MDQ.staleNoPoolSay) or 0) + 1
    if MDQ.staleNoPoolSay <= 3 then
      pcall(mfLog, "残留图层：本图（%s）**没认出任何 WorldMapOverlay 池位**（枚举 %d 个纹理，名字样本：%s）",
        tostring(want), nTex, table.concat(samples, "、"))
    end
  end
  return hid, 0, seen, want, MDQ.staleLedgerN(), whyLvl
end

-- 把藏账里的层**当场全部还回**（关开关 / 关图 / 关模块 / 关功能时用；幂等）
MDQ.staleShowAll = function(why)
  local n = 0
  local names = {}
  for o in pairs(MDQ.staleHid) do
    pcall(o.Show, o)
    table.insert(names, tostring((MDQ.staleHid[o] or {}).name or "?"))
    MDQ.staleHid[o] = nil
    n = n + 1
  end
  if n > 0 then
    pcall(mfLog, "残留图层：把藏起来的 %d 个叠加层全部还回（%s）", n, tostring(why))
    table.sort(names)
    MDQ.staleLogPut(string.format("还回全部 %d 个（%s）：%s", n, tostring(why), table.concat(names, "、")))
  end
  return n
end

-- ★★★1.75.52 六改：**只清账、不还回**（幂等）—— 用在「替代开关刚被打开」那一拍：从这一刻起可见性由
--   「接管守护」负责（客户端原生层本来就要**全藏**）⇒ 若走 `staleShowAll` 会先闪一下再藏回去。
MDQ.staleForget = function(why)
  local n = 0
  for o in pairs(MDQ.staleHid) do
    MDQ.staleHid[o] = nil
    n = n + 1
  end
  if n > 0 then
    pcall(mfLog, "残留图层：账上 %d 个叠加层交给「接管守护」接管（替代开关已开，%s）", n, tostring(why))
    MDQ.staleLogPut(string.format("转交接管守护 %d 个（%s）", n, tostring(why)))
  end
  return n
end

-- ★★★1.75.52 **只读**取证：本帧每个 Texture 的「名字 / 贴图 / 图名段 / 结论」，一个字节都不写（零副作用）。
--   ★这是「路径口径到底对不对」的唯一真机判据：**在大陆图（有残留）时跑**，就能看清残留那几条的贴图属于哪张图；
--     瓦片即使路径不符也只在这里**列出来**（现行实现不藏它们）。
MDQ.staleProbe = function()
  local out = {}
  local wantRaw = tostring(select(1, smMapInfo()) or "?")
  local want = wantRaw
  local wl = string.lower(want)
  local lvl, lvlWhy = MDQ.staleLevel(wantRaw)
  local elist, en = MDQ.staleEngineList()
  en = tonumber(en) or 0
  -- ★五改：**本图没有探索层数据**（非区域 或 引擎自报 0 条）⇒ 本档动手藏；有数据 ⇒ 不藏（并还回）
  local noData = (lvl == true) or (en == 0)
  local fr = _G["WorldMapDetailFrame"]
  local nAll, nPool, nHide, nTileMis, nUnk, nEng = 0, 0, 0, 0, 0, 0
  local lines = {}
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if okr then
      for _, o in ipairs(regs) do
        if o ~= nil and type(o.GetTexture) == "function" then
          nAll = nAll + 1
          local okp, path = pcall(o.GetTexture, o)
          if not okp then path = nil end
          local seg = MDQ.staleSeg(path)
          local nm = frameName(o)
          local isPool = MDQ.stalePoolName(o)
          local isTile = (string.sub(nm, 1, 18) == "WorldMapDetailTile")
          local inEngine = false
          if type(path) == "string" and path ~= "" then
            for wi = 1, table.getn(elist) do
              if MDQ.samePath(path, elist[wi]) then inEngine = true break end
            end
          end
          if inEngine then nEng = nEng + 1 end
          if isPool then nPool = nPool + 1 end
          local v
          if not noData then
            -- 「本图有探索层数据」：本档**不藏**（这一级客户端要用这批池位画探索层；藏账也会被全部还回）
            if isPool then
              v = "叠加层池位 ⇒ 本图**有数据**（引擎自报 " .. tostring(en) .. " 条）⇒ **不藏**"
            elseif seg == nil then
              nUnk = nUnk + 1
              v = "判不出（路径里没有 WorldMap\\<图名>\\ 段）⇒ 不碰"
            else
              v = "本图/别图（" .. seg .. "）⇒ **不碰**（不是叠加层池位）"
            end
          elseif isPool then
            nHide = nHide + 1
            v = "叠加层池位 ⇒ **藏**（" .. (lvl and "非区域地图" or "引擎自报本图 0 条叠加层 = 没有探索层数据") .. "：全藏）"
              .. ((seg ~= nil and seg ~= wl) and ("，注意它的贴图属于别图（" .. seg .. "）= 残留来源") or "")
          elseif seg == nil then
            nUnk = nUnk + 1
            v = "判不出（路径里没有 WorldMap\\<图名>\\ 段）⇒ 不碰"
          else
            if isTile then nTileMis = nTileMis + 1 end
            v = "**别图**（" .. seg .. "）⇒ **只报不藏**（不是叠加层池位；底图/瓦片绝不打洞）"
          end
          table.insert(lines, string.format("　#%d %s ｜ 贴图=%s ｜ 图名段=%s ｜ %s",
            nAll, nm, tostring(path), tostring(seg), v))
        end
      end
    end
  end
  table.insert(out, string.format(
    "残留体检：地图=%s ｜ 本图数据=%s（级别=%s ｜ 引擎自报叠加层 %d 条）｜ 枚举 Texture %d 个（叠加层池位 %d ｜ 引擎清单命中 %d）｜ "
      .. "本档要藏 %d 个 ｜ 瓦片路径不符 %d 个（只报不藏）｜ 判不出 %d 个 ｜ 藏账 %d 条",
    want, noData and "**没有探索层数据 ⇒ 叠加层全藏**" or "有探索层数据 ⇒ **不藏**（藏账全部还回）",
    tostring(lvlWhy), en, nAll, nPool, nEng, nHide, nTileMis, nUnk, MDQ.staleLedgerN()))
  for _, l in ipairs(lines) do table.insert(out, l) end
  -- ★「把哪些纹理隐藏了」= 用户点名要的那一条：当前藏账逐条 + 落盘历史（`SM_CFG.staleLog`）
  table.insert(out, string.format("残留体检·当前藏账 %d 条：%s", MDQ.staleLedgerN(), MDQ.staleNames(12)))
  local ledger = {}
  for o, rec in pairs(MDQ.staleHid) do
    table.insert(ledger, string.format("　藏账 %s ｜ 藏时的贴图=%s",
      tostring(rec and rec.name or "?"), tostring(rec and rec.path or "?")))
  end
  table.sort(ledger)
  for _, l in ipairs(ledger) do table.insert(out, l) end
  local hist = MDQ.staleLogGet(12)
  table.insert(out, string.format("残留体检·落盘历史（SM_CFG.staleLog，最多 %d 条，最新在前）%d 条：",
    MDQ.STALE_LOG_MAX, table.getn(hist)))
  if table.getn(hist) == 0 then
    table.insert(out, "　（空 —— 本档还没藏过任何纹理；/reload 后这里也会保留）")
  else
    for i = 1, table.getn(hist) do table.insert(out, "　" .. hist[i]) end
  end
  return out
end

-- ★★★1.75.52 六改（用户原话：「每次切换到一个地图、识别到地图签名的时候，对应这个地图的贴图数据库查询下有多少贴图，
--   然后删除原生的贴图数据，再自行添加。并且做好守护程序：**有可能会将超出当前贴图数据层数的数据添加回去**，
--   所以要做好守护程序 —— **数量、存在性都要检查**」）⇒ **只在「关闭世界迷雾」开着时接管**（用户选的口径 B）：
--   · **数量基准 = 表**：本图应有几块由 `MDQ.holdN` 现算（与 `MDQ.render` **同一算法、同一上限** `poolMax`
--     ⇒ 全项目「本图该有几块」只有一个来源，绝不写常数）；
--   · **原生全藏**：枚举 `WorldMapDetailFrame` 的 region，凡名字属 `WorldMapOverlay*` 且**不是我们自建的**
--     （身份判定 `MDQ.ownSet`，**不看名字** —— 本客户端那批原生层的名字与我们补建的会重名）⇒ `Hide`。
--     ★1.12 **没有销毁纹理的 API** ⇒「删除原生贴图」只能靠 `Hide`（这也正是本项目「只 Hide/Show」铁律）；
--   · **数量守护**：序号**超出本图应有块数**的池位（上一张图块更多时留下的、或客户端又冒出来的）一律 `Hide`
--     ⇒ 残留不许回潮；**存在性/可见性守护**：我们自建的块（序号在本图应有块数之内）**被藏了就重新 `Show`**；
--   · **绝不永久藏**：`MDQ.holdShowAll` 把藏过的**原生**层全部还回并清账，调在 `MDQ.release` 里
--     ⇒ 关开关 / 关功能 / 关模块**三条路天然全覆盖**（另有「关图」那一拍）。
--   ★节拍 = 挂在 `MDQ.renderCurrent` 里 ⇒ 与渲染**同拍**（换图/开图爆发窗内逐帧重申，之后 0.3s 一拍）；
--   ★这里**一个字节都不写贴图 / UV / 几何**（同残留清理的三条纪律）。
MDQ.holdStat = { map = "?", want = 0, hid = 0, again = 0, reshow = 0, seen = 0, ours = 0, blind = false, at = 0 }
MDQ.holdHid = {}   -- 藏账（**只记客户端原生层**）：对象 → { name =, path =, again = }（关开关/关功能时全部还回）
MDQ.holdOrder = {} -- 藏账的**插入顺序**（超上限时把最老的放回去 ⇒ 账有界且绝不永久藏）
-- ★1.75.59m：**原 alpha 按序号再存一份**（`序号 → 原值`）—— 藏账是按**对象**存的，而本客户端枚举出来的句柄
--   与我们手里的句柄**不可比较**（见 `MDQ.oursOf` 的 1.75.59m 段）⇒ 「按对象查原值」在还回时可能查空；
--   序号这一份专门给「存在性守护 / 自愈」用（我们自己的画布必须不透明）。
MDQ.holdAlphaByIdx = {}
-- ★1.75.60g：**「这一格的 alpha 0 是我们自己写的」的账**（序号 → 图名）—— 存在性守护的自愈**只认这一份**：
--   没有账 ⇒ 一个字节都不写（「缩放大地图 → 透明度」< 1 时画布 alpha 本来就读回 < 1，那是用户的设置不是伤；
--   旧版每拍写回 1 = 真机「贴图一闪一闪」的根因之一，A/B 实证见 `MDQ.mapAlpha` 的注释）。
MDQ.alphaZeroByIdx = {}
MDQ.saidAlphaNotOurs = nil
MDQ.HOLD_LEDGER_MAX = 600  -- ★真机日志取证：客户端每拍重建自己的池位 ⇒ 无界账一小时就攒到 3960 条

-- 池位名字里的**尾号**（`WorldMapOverlay7` → 7）；认不出（字母后缀 / 没有后缀）⇒ nil，**绝不猜**
MDQ.poolIdx = function(o)
  local nm = string.lower(frameName(o) or "")
  if string.find(nm, "worldmapoverlay", 1, true) ~= 1 then return nil end
  local d = string.match(nm, "(%d+)$")
  return d and tonumber(d) or nil
end

-- ★★★1.75.59i：**「这条是不是我们画的」= 唯一实现**（守护与所有只读体检/结论命令共用）。
--   为什么必须抽出来：1.75.54c 起守护认「活句柄 ∨ 旧身份账 ∨ 本拍写过」**三源并集**，而只读体检原来只认 `ownSet`
--   ⇒ 我们正往里写的**活句柄**会被体检标成「客户端原生 ⇒ 藏」，与守护的实际行为**自相矛盾**
--   （用户据此会误判「守护失效」—— 这正是拿读数判断「有没有全量隐藏」时最危险的坑）。
--   ⇒ 抽成这一个函数，**谁问都走它** ⇒ 结论与行为不可能再打架。语义与 1.75.54c 那一版**逐字一致**。
--   ★★★1.75.59m：**再加第四条来源 —— 「序号这一格我们本图写过」= `MDQ.slot[idx] ~= nil`**。
--     为什么必须加（1.75.59l 真机自检的**决定性证据**，全案见 CHANGELOG 1.75.59m 与参考卷）：
--       `WorldMapDetailFrame:GetRegions()` 交出来的那批 `WorldMapOverlay*`，**和我们 `_G` / `MDQ.own` /
--       `ownSet` / `wroteObj` 里那批永远比不相等**，而那批里**包含我们自己 `CreateTexture` 出来的**同名纹理
--       （自检 [3] 里 `self-made=是` 的 19..25 同时出现在 [2] 枚举里，却 `在_G=否`）⇒ 结论 = 同一个底层纹理
--       在枚举里被包成了**另一个不可比较的句柄**（且它上面 `GetTexture` 读不到 —— 见 [2] 全列 `贴图=读不到`）。
--     ⇒ 对象身份（`==`）在这一族上**整条作废**；但**"第 N 格是我们本图的画布"**这件事我们有账
--       （`MDQ.slot[N]` = 本拍渲染真正写过的那一格，含地图/区域/块号）⇒ **按序号认，不按对象认**。
--     ★语义：`ours` 从此表示「这一格是我们本图的画布」——守护不许藏，只许保证它显示着且不透明。
MDQ.oursOf = function(o, idx)
  if o == nil then return false end
  if idx == nil then idx = MDQ.poolIdx(o) end
  local live = (idx ~= nil) and (o == rawget(_G, "WorldMapOverlay" .. tostring(idx)) or o == MDQ.own[idx])
  local ours = live or (MDQ.ownSet[o] == true) or (MDQ.wroteObj[o] == true)
    or (idx ~= nil and MDQ.slot[idx] ~= nil and MDQ.slot[idx].tex ~= nil)
  return ours
end

-- 本图**应有几块**（表推；数量口径唯一来源，与 `MDQ.render` 同一算法与同一上限）
--   ★1.75.54：**按图名缓存** —— 它每拍被 `holdTick` 与 `staleTick` 各调一次，逐拍遍历整张区域表是白费；
--   表是**载入期常量**（生成物），所以缓存安全；`MDQ.holdNCache` 只随访问过的图增长（≤ 图数）。
MDQ.holdNCache = {}
MDQ.holdN = function(file)
  local key = tostring(file or "")
  -- ★★★1.75.64：**实景模式本图只有一层**（整区一张，没有按区域/块的拆分）⇒ 数量基准恒为 1。
  --   ★「数量守护」就是拿它当上限藏「序号超出的池位」⇒ 实景下 2..poolMax 全藏（我们那套残留与客户端的都被收掉）。
  if MDQ.jpgMode() then
    local cj = MDQ.holdNCache["\1jpg\1" .. key]
    if cj ~= nil then return cj end
    local r = MDQ.jpgBase(key)
    local nj = (type(r) == "table") and 1 or 0
    MDQ.holdNCache["\1jpg\1" .. key] = nj
    return nj
  end
  local c = MDQ.holdNCache[key]
  if c ~= nil then return c end
  local m = MDQ.areaOf(key)   -- ★六改 b：与渲染**同一个**表查找（大小写不敏感）⇒ 数量口径不会与画出来的块数打架
  if type(m) ~= "table" then MDQ.holdNCache[key] = 0 return 0 end
  local n = 0
  for _, rec in pairs(m) do
    n = n + (tonumber(MDQ.tiles(rec and rec[1], rec and rec[2])) or 0)
  end
  if n > MDQ.poolMax then n = MDQ.poolMax end
  MDQ.holdNCache[key] = n
  return n
end

-- ★★★1.75.57d：**「迷雾这一拍真的接管了本图吗」**（只读；折算让位的**唯一**判据）。
--   为什么必须有：让位条件原来是「**迷雾开关开着**」⇒ 迷雾开着但**本图它没接管**（表里没有这张图 /
--   贴图探不到 / 池位建不出来 / 倍率判不出而早退）时 —— 迷雾不画、折算又被那道闸门挡着
--   ⇒ **两边都不缩放探索层** = 用户报障「地图首次打开缩放探索层功能异常」。
--   四条全过才算接管：① 开关开着 ② 地图身份读得到 ③ 表里**有**这张图（`holdN > 0`）
--   ④ **本图这一拍真画出了块**（`lastRender.map` = 本图 ∧ `lastRenderN > 0`）。
--   ★判不出（任一项读不到）⇒ 返回 **false**（不让位 ⇒ 折算照跑）—— 「判不出就不动手」的同一条纪律：
--     宁可折算跑一遍（9/29 那份的既有行为），也不许两边都不管。
MDQ.takesMap = function()
  if not MDQ.swm() then return false end
  local file = select(1, smMapInfo())
  if file == nil or tostring(file) == "" then return false end
  local lr = MDQ.lastRender
  if type(lr) ~= "table" or tostring(lr.map or "") ~= tostring(file) then return false end
  if (tonumber(MDQ.holdN(file)) or 0) <= 0 then return false end
  return (tonumber(MDQ.lastRenderN) or 0) > 0
end

-- 原生藏账条数
MDQ.holdLedgerN = function()
  local c = 0
  for _ in pairs(MDQ.holdHid) do c = c + 1 end
  return c
end

-- ★★★1.75.54e：「我们把某个**客户端层**藏起来了」→ **记名进同一个有界藏账**（关开关时按它全部 Show 还回）。
--   ★**唯一写账口**（`holdTick` 与 `hideFrom` 共用）⇒ 不会出现「藏了却没账」的层（那正是关掉开关后
--     地图缺块的原因：`hideFrom` 收尾藏掉的那些**从来没进过账**，还回时自然找不到它们）。
--   ★只记**当下真的显示着**的层（本来就隐藏的不进账 —— 否则还回会把客户端自己藏起来的层顶出来）；
--     已记过的不重复记（有界 + 不刷屏）。返回 true = 新记一条。
--   ★★★1.75.59k（用户：「取消『只 Hide/Show』这条禁令，我要完成功能。不能限制自己用什么技术」）：
--     **这条账现在同时是「原值账」** —— 记名前先 `origGrab(o, o)` 把**这一条对象的原值**抓下来
--     （贴图 / UV / 宽高 / 锚点 / 显隐 / **alpha**），还回时按它逐样还原 ⇒ 放开技术手段之后，
--     「关掉必须回到原样」这条**代价**仍然兜得住（★对象边界不变：只动名字族 `WorldMapOverlay*`）。
MDQ.holdNote = function(o, file, tag)
  if o == nil or MDQ.holdHid[o] ~= nil then return false end
  local nm = frameName(o)
  local okp, path = pcall(o.GetTexture, o)
  if not okp then path = nil end
  -- ★写任何东西**之前**先抓原值（本项目铁律；`holdTick` 里本函数排在 Hide/SetAlpha 之前）
  --   ★ctx = "hide"：守护账只写显隐 + alpha ⇒ 还原只还这两样、**绝不 Hide**（见 `origRestoreOne`）
  local rec = MDQ.origGrab(o, o, "hide")
  if MDQ.holdOrder == nil then MDQ.holdOrder = {} end
  MDQ.holdHid[o] = { name = nm, path = tostring(path), again = 0, a = (rec ~= nil) and rec.a or nil }
  table.insert(MDQ.holdOrder, o)
  -- ★藏账**有界**（真机日志：一小时不到就攒到 3960 条 —— 客户端每拍重建自己的池位对象
  --   ⇒ 无界账会把内存与「关开关时逐个 Show」都拖垮）。超上限时把最老的**放回去**（绝不永久藏）。
  while table.getn(MDQ.holdOrder) > MDQ.HOLD_LEDGER_MAX do
    local old = table.remove(MDQ.holdOrder, 1)
    if old ~= nil and MDQ.holdHid[old] ~= nil then
      pcall(old.Show, old)     -- ★放回（绝不永久藏）
      -- ★1.75.59k：放回时**原值也要还**，并把那一格的账清掉（否则 `origIdx` 会跟着无界长）
      if MDQ.origIdx[old] ~= nil then
        pcall(MDQ.origRestoreOne, old)
      end
      MDQ.holdHid[old] = nil
    end
  end
  MDQ.staleLogPut(string.format("%s：地图=%s ｜ 客户端原生层 %s ｜ 贴图=%s",
    tostring(tag or "接管藏"), tostring(file), tostring(nm), tostring(path)))
  return true
end

-- ★接管守护（**每拍都跑**）：藏原生 + 数量守护（超出本图块数的池位）+ 存在性守护（我们自建的块被藏就复位）
--   返回：藏了原生 N 个, 复位我们自建的 M 个, 枚举到池位 K 个, 本图应有 W 块, 「又冒出来再藏」A 次
-- ★★★1.75.59q：**同序号去重**（用户真机截图：「图片内出现 2 张完全相同的图片，一张在编辑模式下正常可拖拽，
--   另外一张无法编辑拖拽」= 同一张图**两份**：一份我们画的（有柄可拖）、另一份是**客户端自己那套**没被藏掉）。
--   为什么之前的守护抓不到它：枚举里**同序号出现 ≥2 条**（真机 `43 = 25 + 18`），而按序号认画布
--   （`MDQ.oursOf` 第四条来源 `MDQ.slot[idx] ~= nil`）会把**同号的那几条全判成「我们的」**⇒ 一条都不藏 ⇒ 图上留两份。
--
--   ★★★判据**不是对象身份**（1.75.59m 定案：`GetRegions()` 交出来的句柄与 `_G`/`MDQ.own` 里那批**永远 `~=`**，
--     连我们自己 `CreateTexture` 出来的也一样）⇒ 改用**属性往返探针**（改的是「同一个底层纹理」而不是「同一个句柄」）：
--       ① 往**我们的活句柄**（`_G["WorldMapOverlay<idx>"]` 或 `MDQ.own[idx]`）写一个只可能由我们写出的**哨兵 alpha**；
--       ② 逐条读枚举里同号那几条的 `GetAlpha()`：
--            · 读到哨兵 ⇒ **同一张底层纹理**（别名）⇒ **一个字节都不碰**（藏它 = 把我们的画也藏掉，1.75.59l 的教训）
--            · 读不到   ⇒ **另一张纹理** ⇒ 它才是那张「拖不动的重复图」⇒ `Hide` + 进藏账（可还原）
--            · 哨兵谁都没读到 / 读不了 / 拿不到活句柄 ⇒ **判不出 ⇒ 一个字节都不碰**（保守门不变）
--       ③ 哨兵**立刻还原**（绝不留在屏幕上）；结论按（地图 + 序号 + 条目数）**缓存** ⇒ 稳态零探测。
--   返回 藏了几条, 判为别名几条, 判不出几组, 组数, **本拍被藏掉的那些对象**（第 5 个返回 = 集合）
--   ★★★1.75.60b：第 5 个返回（`hidSet`）是**必须的**，不是附赠 —— 守护的第二趟里有一份
--     「存在性守护：我们自己的画布被藏了就 `Show` 回来」的名单，而**同一拍里**被去重藏掉的异体
--     也会落进那份名单（按序号认画布 ⇒ 它们也算「我们的」）⇒ 第二趟会把刚藏掉的**又 Show 回来**
--     = 两趟自相矛盾（同族：1.75.59m 那次「渲染 Show / 守护 Hide 自相残杀」）。
--     ⇒ 判据 = **本拍判成异体的，本拍不许再 Show 回来**（第二趟据此跳过）。
MDQ.dupStat = { groups = 0, hid = 0, same = 0, blind = 0, mk = nil, cache = {} }
MDQ.DUP_SENT = 0.3751        -- 哨兵 alpha（真机几乎不可能正好是这个值）
-- ★★★1.75.60g：**外框（画布）链的 alpha = 「缩放大地图 → 透明度」设置**（`SimpleMap` 的 `featApplyAlpha`
--   同时打在 `WorldMapFrame` / `WorldMapButton` / `WorldMapDetailFrame` 三个帧上，真值 = `SM_CFG.alpha`）。
--   为什么要读它：**透明度 < 1 时，本客户端的 `GetAlpha` 读回会被比例缩放** ⇒ 一切「按 alpha 数值判定」的
--   逻辑（同序号去重的哨兵探针、存在性守护的 alpha 自愈）全部不可信 —— 真机 A/B 实证：用户把透明度从
--   0.70 调回 1.00，洛克莫丹的闪烁**立刻消失**（lihaiboas3 闪 / LIHAIBOAS2 不闪，两账号唯一的实质差别
--   就是 `simpleMapCfg.alpha` = 0.7 vs 1）。⇒ 读不到 = nil（不猜）；取三个帧里**最小的那个**（任一 < 1 即算）。
MDQ.mapAlpha = function()
  local lo = nil
  for _, nm in ipairs({ "WorldMapFrame", "WorldMapDetailFrame", "WorldMapButton" }) do
    local fr = rawget(_G, nm)
    if fr ~= nil and type(fr.GetAlpha) == "function" then
      local ok, a = pcall(fr.GetAlpha, fr)
      if ok and tonumber(a) ~= nil then
        a = tonumber(a)
        if lo == nil or a < lo then lo = a end
      end
    end
  end
  return lo
end
MDQ.dupKill = function(byIdx, want, file)
  local hid, same, blind, groups = 0, 0, 0, 0
  local hidSet = {}
  if type(byIdx) ~= "table" then return 0, 0, 0, 0, hidSet end
  local SENT = tonumber(MDQ.DUP_SENT) or 0.3751
  local mk = tostring(smMapKey() or file or "?")
  -- 换图 ⇒ 结论全作废（同一序号在不同图上是不同的块）
  if MDQ.dupStat.mk ~= mk then MDQ.dupStat.mk = mk MDQ.dupStat.cache = {} end
  -- ★★★1.75.60g：**透明度 < 1 ⇒ 整组不动手**（真机 A/B 定案的根治点）。
  --   理由：哨兵探针与 alpha 自愈都建立在「GetAlpha 读回 == 写进去的值」这个前提上，而「缩放大地图 → 透明度」
  --   < 1 时读回会被比例缩放 ⇒ 前提不成立 ⇒ 继续动手只会**把我们自己画布的同号孪生当重复图藏掉**，
  --   下一拍存在性守护再 `Show` 回来 = 每拍一闪一闪。⇒ 判不出就不动手（本项目铁律），并把原因**如实说一次**。
  --   ★代价：透明度 < 1 的用户暂时拿不到「同序号去重」这份清理（要它就把透明度调回 1.00）。
  local fa = (MDQ.mapAlpha ~= nil) and MDQ.mapAlpha() or nil
  if fa ~= nil and fa < 0.999 then
    local ng = 0
    for _, lst in pairs(byIdx) do if table.getn(lst) > 1 then ng = ng + 1 end end
    MDQ.dupStat.groups, MDQ.dupStat.hid, MDQ.dupStat.same, MDQ.dupStat.blind = ng, 0, 0, ng
    if MDQ.saidDupAlpha ~= mk then
      MDQ.saidDupAlpha = mk
      pcall(MDQ.staleLogPut, string.format(
        "同序号去重**整组不动手**：地图=%s ｜ 外框 alpha=%.3f（= 「缩放大地图 → 透明度」< 1）⇒ 本客户端 alpha 读回会被"
          .. "比例缩放 ⇒ 哨兵探针判不准（真机会把我们自己的画布当重复图藏掉 = 一闪一闪）⇒ 判不出就不动手；"
          .. "要这份去重请把透明度调回 1.00", tostring(file), fa))
    end
    return 0, 0, ng, ng, hidSet
  end
  -- ★★★1.75.60g：**「藏 + 写后验证 + 立刻回滚」= 唯一实现**（fresh 探针与缓存两条路共用）。
  --   真机报障（用户：「lihaiboas3 打开洛克莫丹贴图一闪一闪，lihaiboas2 同样开关却正常」；A/B 实证：
  --   把「缩放大地图 → 透明度」调回 1.00 立刻不闪）⇒ 根因链：
  --     ① 两账号在存档里的**唯一实质差别** = `simpleMapCfg.alpha`（透明度）0.7 vs 1；
  --     ② 透明度 < 1 时，枚举句柄的 `GetAlpha` 读回**被比例缩放**（写 0.3751 ⇒ 读回 ≈ 0.2626）
  --        ⇒ 旧判据「读回值 == 哨兵」**必然失配** ⇒ 把**同一张底层纹理**判成「另一张纹理」；
  --     ③ 于是把我们**自己画布的同号孪生**当重复图 `Hide` ⇒ 下一拍存在性守护又 `Show` 回来 = **每拍一闪**
  --        （同族：1.75.59m「渲染 Show / 守护 Hide 自相残杀」、1.75.60b ⑨「隔一拍闪一次」）。
  --   ★判据（**不押注任何 alpha 口径**）：藏**之前**先读「组内别名那几条 + 我们本图这一格」的显隐/alpha，
  --     藏**之后**读回 —— **任意一条跟着变了**（显示→隐藏 / alpha 变小）⇒ 刚才藏的就是同一张纹理
  --     ⇒ 当场 `Show` + 还原原 alpha，并把这一组改判 `blind`（**本会话不再碰这个号**）。
  --   ★代价如实告知：这一组那份重复图会**留着**（宁可留残留，绝不留「一闪一闪」/空白图）。
  local function dupHideVerified(aliens, keep, idx)
    local probe = {}
    if keep ~= nil then table.insert(probe, keep) end
    local before = {}
    for i, o in ipairs(probe) do
      local oks2, sh2 = pcall(o.IsShown, o)
      local oka2, al2 = pcall(o.GetAlpha, o)
      before[i] = { sh = (oks2 and sh2 == true), al = (oka2 and tonumber(al2)) or nil }
    end
    local done, nHid = {}, 0
    for _, it in ipairs(aliens) do
      -- ★1.75.60b：**判成异体就进集合**（不管这一拍是「刚藏掉」还是「本来就藏着」）——
      --   第二趟的存在性守护靠它跳过；只在**真 Hide** 的那一下才计数。
      hidSet[it.o] = true
      if it.shown == true then
        -- ★★★顺序即判据（1.75.54e 老账）：**先记账（顺带抓原值）再 Hide**（反过来原值里 shown=false ⇒ 关掉不还回）
        pcall(MDQ.holdNote, it.o, file, "同序号重复")
        if pcall(it.o.Hide, it.o) then nHid = nHid + 1 table.insert(done, it.o) end
      end
    end
    if nHid == 0 then return 0, false end
    local hit = false
    for i, o in ipairs(probe) do
      local oks2, sh2 = pcall(o.IsShown, o)
      local oka2, al2 = pcall(o.GetAlpha, o)
      local b = before[i]
      if b ~= nil then
        if b.sh == true and not (oks2 and sh2 == true) then hit = true end
        if b.al ~= nil and oka2 and tonumber(al2) ~= nil and tonumber(al2) < b.al - 0.001 then hit = true end
      end
    end
    if not hit then return nHid, false end
    -- 回滚：把我们刚藏掉的原样放回来（含原 alpha）—— **绝不永久藏 / 绝不永久改**
    for _, it in ipairs(aliens) do hidSet[it.o] = nil end
    for _, o in ipairs(done) do
      pcall(o.Show, o)
      local rec9 = MDQ.origIdx[o]
      if rec9 ~= nil and rec9.a ~= nil then pcall(o.SetAlpha, o, rec9.a) end
    end
    -- ★★★1.75.60g：**我们自己的画布也要按「藏之前读到的样子」还原** —— 只 `Show` 藏掉的那条孪生句柄是不够的：
    --   真机上 Hide 可能打在**共享的底层纹理**上，而那条句柄的 `Show` 带不动我们手里这一格 ⇒ 画布仍然是黑的
    --   （harness ⑯ 当场造出过这个形态）。⇒ 对每一格「藏之前是显示中/不透明」的对象：**读回自证**，
    --   没回来就 `Show` + 按原 alpha 还原（原 alpha 取藏之前读到的那份，绝不拿当前值冒充）。
    for i, o in ipairs(probe) do
      local b = before[i]
      if b ~= nil then
        local oks2, sh2 = pcall(o.IsShown, o)
        if b.sh == true and not (oks2 and sh2 == true) then pcall(o.Show, o) end
        local oka2, al2 = pcall(o.GetAlpha, o)
        if b.al ~= nil and oka2 and tonumber(al2) ~= nil and tonumber(al2) < b.al - 0.001 then
          pcall(o.SetAlpha, o, b.al)
        end
      end
    end
    pcall(MDQ.staleLogPut, string.format(
      "同序号重复**判错已回滚**：地图=%s ｜ 号=%s ｜ 藏掉之后我们自己的画布跟着变了（= 同一张纹理，"
        .. "多半是「缩放大地图 → 透明度」< 1 让哨兵读回被缩放）⇒ 已 `Show` + 还原 alpha；该组本会话不再动手",
      tostring(file), tostring(idx)))
    if MDQ.saidDupRoll ~= mk then
      MDQ.saidDupRoll = mk
      pcall(smFitSay, "接管守护：地图=%s ｜ 同序号去重**判错已回滚**（藏了之后我们自己的画布跟着变了 ⇒ 那是同一张"
        .. "纹理）⇒ 已当场 `Show` + 还原 alpha，这一组本会话不再动手；那份重复图会暂时留着（体检：/ehm mapfit 重复）",
        tostring(file))
    end
    return 0, true
  end
  for idx, list in pairs(byIdx) do
    local n = table.getn(list)
    if n > 1 then
      groups = groups + 1
      -- ★★缓存键 = **构成指纹**（我们的活句柄 + 组里第一条 + 条数）—— 只按「序号」缓存是不够的：
      --   本图的对象随时可能被重建（我们 `release` 清账 / 客户端重摆池位）⇒ 旧结论（尤其 `blind`）
      --   会被套到**新对象**上 ⇒ 该藏的不藏（harness 的 ⑱ 组当场抓到过：同一张图上前后两次建的批次不同）。
      local mine = rawget(_G, "WorldMapOverlay" .. tostring(idx)) or MDQ.own[idx]
      local ck = tostring(idx) .. "@" .. tostring(mine) .. "#" .. tostring(list[1] and list[1].o) .. "/" .. tostring(n)
      local cached = MDQ.dupStat.cache[ck]
      if cached ~= nil then
        -- 已判过这一组（**同一批对象**）⇒ 直接按结论动手，**不再写哨兵**
        if cached.verdict == "mixed" then
          -- ★1.75.60g：缓存结论**也要过写后验证**（缓存 ≠ 判对；真机那一刻的误判必须在这一拍就回滚掉）
          local al2 = {}
          for _, it in ipairs(list) do
            if it.o ~= cached.keep then table.insert(al2, it) end
          end
          local nH, rolled = dupHideVerified(al2, cached.keep, idx)
          if rolled then
            blind = blind + 1
            MDQ.dupStat.cache[ck] = { n = n, verdict = "blind" }
          else
            hid = hid + (tonumber(nH) or 0)
          end
        elseif cached.verdict == "alias" then
          same = same + n - 1
        else
          blind = blind + 1
        end
      else
        local a0 = nil
        if mine ~= nil and type(mine.GetAlpha) == "function" then
          local okv, v = pcall(mine.GetAlpha, mine)
          if okv and tonumber(v) ~= nil then a0 = tonumber(v) end
        end
        -- ★1.75.60g：哨兵值**要真能改变读数**（万一原值恰好就是哨兵 ⇒ 换一个），
        --   否则「跟着我变」这条判据恒不成立、会把别名判成异体。
        local sW = (a0 ~= nil and math.abs(a0 - SENT) < 0.001) and (1 - SENT) or SENT
        -- ★★★1.75.60g：**基线必须先读**（写哨兵**之前**）—— 判据从「读回值 == 哨兵」改成「**跟着我变**」：
        --   真机（透明度 < 1）下读回会被比例缩放（写 0.3751 ⇒ 读回 ≈ 0.2626）⇒ 精确比对必然失配
        --   ⇒ 把**同一张底层纹理**判成「另一张纹理」并藏掉（= 闪烁的真凶之一，全案见 `dupHideVerified` 上面那段）。
        local base = {}
        for i, it in ipairs(list) do
          local okv, v = pcall(it.o.GetAlpha, it.o)
          base[i] = (okv and tonumber(v)) or nil
        end
        local okS = (a0 ~= nil) and pcall(mine.SetAlpha, mine, sW) or false
        if not okS then
          blind = blind + 1
          MDQ.dupStat.cache[ck] = { n = n, verdict = "blind" }
        else
          local alias, alien = {}, {}
          for i, it in ipairs(list) do
            local okv, v = pcall(it.o.GetAlpha, it.o)
            local v1 = (okv and tonumber(v)) or nil
            local v0 = base[i]
            -- ① **跟着我们变**（哪怕比例不同 —— 同一张底层纹理的判据）② 或正好读到哨兵
            local tracked = (v0 ~= nil and v1 ~= nil) and (math.abs(v1 - v0) > 0.001)
            local exact = (v1 ~= nil) and (math.abs(v1 - sW) < 0.001)
            if tracked or exact then
              table.insert(alias, it)
            else
              table.insert(alien, it)
            end
          end
          pcall(mine.SetAlpha, mine, a0)          -- ★哨兵**立刻还原**（绝不留在屏幕上）
          if table.getn(alias) == 0 then
            blind = blind + 1                     -- 连一个别名都认不出 ⇒ 判不出 ⇒ 不动手
            MDQ.dupStat.cache[ck] = { n = n, verdict = "blind" }
          elseif table.getn(alien) == 0 then
            same = same + table.getn(alias) - 1   -- 全是同一张纹理的别名 ⇒ 屏幕上只有一份，不必动
            MDQ.dupStat.cache[ck] = { n = n, verdict = "alias" }
          else
            local keep = (alias[1] ~= nil) and alias[1].o or nil
            local nH, rolled = dupHideVerified(alien, keep, idx)
            if rolled then
              blind = blind + 1
              MDQ.dupStat.cache[ck] = { n = n, verdict = "blind" }
            else
              hid = hid + (tonumber(nH) or 0)
              MDQ.dupStat.cache[ck] = { n = n, verdict = "mixed", keep = keep }
            end
          end
        end
      end
    end
  end
  MDQ.dupStat.groups, MDQ.dupStat.hid, MDQ.dupStat.same, MDQ.dupStat.blind = groups, hid, same, blind
  return hid, same, blind, groups, hidSet
end

-- ★1.75.59q：**只读体检** `/ehm mapfit 重复`（别名 `dup`）—— 逐组列同序号那几条：
--   名字 / 显示 / alpha / 尺寸 / 锚点偏移 + **上一拍的判定**（mixed=藏了异体 / alias=同一张纹理 / blind=判不出）。
--   ★零副作用：只读枚举 + 读属性，一个字节都不写、也不调 `holdTick`。
MDQ.dupProbe = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local fr = _G["WorldMapDetailFrame"]
  local want = MDQ.holdN(file)
  out[table.getn(out) + 1] = string.format(
    "同序号重复体检（只读）：地图=%s ｜ 本图应有 %d 块 ｜ 上拍：组 %d ｜ 藏掉异体 %d ｜ 别名 %d ｜ 判不出 %d",
    (file ~= "" and file or "?"), want, tonumber(MDQ.dupStat.groups) or 0, tonumber(MDQ.dupStat.hid) or 0,
    tonumber(MDQ.dupStat.same) or 0, tonumber(MDQ.dupStat.blind) or 0)
  local byIdx, seen = {}, 0
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if okr then
      for _, o in ipairs(regs) do
        if o ~= nil and MDQ.stalePoolName(o) then
          seen = seen + 1
          local idx = MDQ.poolIdx(o)
          if idx ~= nil then
            local g = byIdx[idx]
            if g == nil then g = {} byIdx[idx] = g end
            table.insert(g, o)
          end
        end
      end
    end
  end
  local groups = 0
  local keys = {}
  for idx in pairs(byIdx) do table.insert(keys, idx) end
  table.sort(keys)
  for _, idx in ipairs(keys) do
    local g = byIdx[idx]
    if table.getn(g) > 1 then
      groups = groups + 1
      local cached = MDQ.dupStat.cache[tostring(idx)]
      out[table.getn(out) + 1] = string.format("　#%d：**%d 条** ｜ 判定=%s", idx, table.getn(g),
        (cached ~= nil) and tostring(cached.verdict) or "还没探过（等下一拍守护）")
      for k, o in ipairs(g) do
        local oks, sh = pcall(o.IsShown, o)
        local oka, al = pcall(o.GetAlpha, o)
        local okw, w = pcall(o.GetWidth, o)
        local okh, h = pcall(o.GetHeight, o)
        local okp, _, _, _, px, py = pcall(o.GetPoint, o, 1)
        out[table.getn(out) + 1] = string.format("　　#%d-%d 显示=%s alpha=%s 尺寸=%sx%s 锚点偏移=%s,%s 名=%s",
          idx, k, (oks and sh == true) and "是" or "否", oka and tostring(al) or "?",
          okw and tostring(w) or "?", okh and tostring(h) or "?",
          okp and tostring(px) or "?", okp and tostring(py) or "?", tostring(frameName(o)))
      end
    end
  end
  out[table.getn(out) + 1] = string.format("　枚举池位 %d 条 ⇒ 同序号重复 **%d 组**（组内 >1 条才做去重）", seen, groups)
  if groups == 0 then out[table.getn(out) + 1] = "　（本图没有同序号重复：每个序号只有一条）" end
  return out
end

MDQ.holdTick = function(file)  if not MDQ.swm() then return 0, 0, 0, 0, 0 end
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    return 0, 0, 0, 0, 0
  end
  local want = MDQ.holdN(file)
  local drew = tonumber(MDQ.lastRenderN) or 0
  -- ★★★1.75.60b（编辑模式的视图开关「**显示原始贴图层**」）：**这一拍只还回、一个 `Hide` 都不发**。
  --   为什么不能只让按钮自己去 `Show`：守护每拍都在藏 ⇒ 刚放出来、下一拍又被藏回去 = 用户看到的
  --   「按钮点了没反应」。⇒ 单一开关 = **守护自己让位**（把账上藏过的全部还回 + 本拍不动手）。
  --   ★排在这里（`holdN` 之后、两个「不动手」闸门之前）也顺手把 `holdStat` 写字了 ⇒ 体检/播报口径一致。
  if (MDQ.liveNative ~= nil) and MDQ.liveNative() then
    local backN = MDQ.holdShowAll("编辑模式：显示原始贴图层")
    local st0 = MDQ.holdStat
    st0.map, st0.want = tostring(file), want
    st0.hid, st0.again, st0.reshow, st0.seen, st0.ours = 0, 0, backN, 0, 0
    st0.fixa, st0.blind = 0, false
    st0.at = (type(GetTime) == "function") and GetTime() or 0
    return 0, backN, 0, want, 0
  end
  -- ★★★1.75.52 六改 b（用户真机报障「全都是空白的」）：**数据库里没有这张图 / 一块都没画出来**
  --   ⇒ **一个字节都不碰**（客户端的探索层保持原样）。理由两条：
  --     ① 本项目铁律「拿不到证据就一个字节都不碰」—— 不知道这张图该有什么，就没有替代依据；
  --     ② 旧写法（原生全藏 + 不自行添加）在「表里没有这张图」时 = **整张图空白**，比残留更糟。
  if want <= 0 or drew <= 0 then return 0, 0, 0, want, 0 end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then return 0, 0, 0, want, 0 end
  local hid, reshow, seen, again, oursSeen, fixA = 0, 0, 0, 0, 0, 0
  -- ★1.75.60b：编辑模式「隐藏迷雾贴图层」⇒ 我们自己的画布是**故意藏着**的 ⇒ 存在性守护这一拍不许把它 `Show` 回来
  local fogOff = (MDQ.liveFogOff ~= nil) and MDQ.liveFogOff()

  local kills, shows = {}, {}
  -- ★★★1.75.59q：**按序号分组**（真机 `枚举 43 = 25 + 18` 同序号重复）—— 第二趟用它做「同序号去重」。
  local byIdx = {}
  -- ===== 第一趟：只**判定**，一个字节都不写 =====
  for _, o in ipairs(regs) do
    -- 唯一的证据 = **名字**属叠加层池位族；名字不合（底图瓦片 / 匿名装饰）⇒ 一个字节都不碰
    if o ~= nil and MDQ.stalePoolName(o) then
      seen = seen + 1
      local idx = MDQ.poolIdx(o)
      -- ★★★1.75.59m（**1.75.59l 的「按对象认」在本客户端整条作废，真机自检为证**）：
      --   1.75.54c 记的「枚举出来的池位与我们写进去的不是同一批对象」被**误读**成了「枚举的是客户端的另一批」，
      --   于是 1.75.59l 把盲门拆成两半、放出「有活句柄但一条都不在枚举里 ⇒ 照常动手」这条路 ⇒ 真机后果：
      --   **守护把我们自己画的 25 块全 `Hide` + `SetAlpha(0)`**（自检 [6] `藏原生 25`、[2] 全列 `显示=否 alpha=0`）
      --   ⇒ 地图探索层**整片空白**，而且每拍「渲染先 `Show` / 守护随后 `Hide`」**自相残杀** =
      --   用户看到的「纹理层都没了 … 过一会儿又出现又消失」那个循环（**不是**客户端重载地图，是我们自己两趟打架）。
      --   身份已由 `MDQ.oursOf` 的第四条来源（**按序号认画布**）修正 ⇒ 这里的 `ours` 才是可信的。
      local ours = MDQ.oursOf(o, idx)
      if ours then oursSeen = oursSeen + 1 end
      local oks, shown = pcall(o.IsShown, o)
      local oka, al = pcall(o.GetAlpha, o)
      if not oka or not tonumber(al) then al = nil end
      -- ★原生层**不看序号**（它就是客户端自己那套 / 上一张图的残留）；我们自己的画布按**数量**判（超出即藏）
      local kill = (not ours) or (idx ~= nil and idx > want)
      if oks and shown == true and kill then
        table.insert(kills, { o = o, ours = ours })
      elseif (not fogOff) and ours and idx ~= nil and idx <= want
        -- ★1.75.60e：**用户故意藏着的块**（列表右键逐块隐藏）⇒ 存在性守护不许把它 `Show` 回来
        and not ((MDQ.blkHiddenIdx ~= nil) and MDQ.blkHiddenIdx(idx))
        and ((oks and shown == false) or (al ~= nil and al < 0.999)) then
        -- ★★★1.75.59m **存在性守护 + 自愈**：我们自己的画布被藏了 / 被写成透明 ⇒ 待会儿还回来。
        --   `alpha` 一并看：`IsShown()` 在 alpha=0 时**仍报 true**（自检 [5] 实证）⇒ 只看显隐会把「隐形但报显示中」
        --   当成健康状态（1.75.59l 那版就是这么把 25 块 alpha 归零后仍然报「✅ 全量隐藏」的）。
        table.insert(shows, { o = o, idx = idx, hidden = (oks and shown == false), alpha = al })
      end
      -- ★1.75.59q：同序号分组（只收「本图应有的序号」，去重只在 want 之内做）
      if idx ~= nil and idx <= want then
        local g = byIdx[idx]
        if g == nil then g = {} byIdx[idx] = g end
        table.insert(g, { o = o, ours = ours, shown = (oks and shown == true) })
      end
    end
  end
  -- ★★★第二趟之前的安全门（1.75.52 六改 c；**1.75.59m 恢复原样、并写明为什么**）：
  --   「枚举里一个『我们画的』都认不出 ⇒ 判不出 ⇒ 一个字节都不碰」。
  --   ★1.75.59l 曾把这条门放宽（当时以为「有活句柄却不在枚举里」= 枚举的是另一批 ⇒ 可以动手）——
  --     真机自检证明那个前提**是错的**（枚举的就是我们那批，只是句柄不可比较）⇒ 放宽的后果是**把自己画的藏光**。
  --   ⇒ 恢复保守门：**认不出就不动手**（代价 = 这种情形下客户端的层也一起留着显示；宁可留残留，绝不留空白图）。
  if (oursSeen == 0 and seen > 0) then
    MDQ.holdStat.map, MDQ.holdStat.want = tostring(file), want
    MDQ.holdStat.hid, MDQ.holdStat.again, MDQ.holdStat.reshow = 0, 0, 0
    MDQ.holdStat.seen, MDQ.holdStat.ours = seen, 0
    MDQ.holdStat.at = (type(GetTime) == "function") and GetTime() or 0
    MDQ.holdStat.blind = true
    local mkB = smMapKey() or tostring(file)
    if MDQ.holdSaidBlind ~= mkB then
      MDQ.holdSaidBlind = mkB
      pcall(smFitSay, "接管守护：地图=%s ｜ 枚举到 **%d** 个叠加层池位，但**一个都认不出是我们画的**"
        .. "（本拍画了 %d 块）⇒ **判不出 ⇒ 一个字节都不碰**（宁可保留原生的，也绝不留空白图）。"
        .. "取证：/ehm mapfit 自检（[2]/[3] 两段给枚举逐条与我们的活句柄）",
        tostring(file), seen, drew)
    end
    return 0, 0, seen, want, 0
  end
  MDQ.holdStat.blind = false
  -- ★★★1.75.59q：**同序号去重**（用户截图里的第二张「拖不动的重复图」）—— 排在盲门之后（盲门一触发就整拍不动手）。
  --   ★1.75.60b：第 5 个返回 = **本拍被去重藏掉的那些对象** —— 下面第二趟的「存在性守护」必须跳过它们，
  --     否则刚藏掉的异体又被 `Show` 回来（同一拍里两趟自相矛盾）。
  local dupHid, dupSame, dupBlind, dupGroups, dupSet = MDQ.dupKill(byIdx, want, file)
  dupHid = tonumber(dupHid) or 0
  hid = hid + dupHid
  MDQ.holdStat.dupHid, MDQ.holdStat.dupSame, MDQ.holdStat.dupBlind = dupHid, tonumber(dupSame) or 0, tonumber(dupBlind) or 0
  MDQ.holdStat.dupGroups = tonumber(dupGroups) or 0
  if dupHid > 0 then
    local mkD = smMapKey() or tostring(file)
    if MDQ.dupSaid ~= mkD then
      MDQ.dupSaid = mkD
      pcall(smFitSay, "接管守护：地图=%s ｜ 发现**同序号重复**（枚举里同号的 `WorldMapOverlay*` 不止一条）⇒ "
        .. "按「属性往返探针」判出**另一张纹理**并**藏了 %d 条**（那就是图上那份**拖不动的重复图**）；"
        .. "判为同一张纹理的别名 %d 条、判不出 %d 组（判不出就一个字节都不碰）。取证：/ehm mapfit 检查",
        tostring(file), dupHid, tonumber(dupSame) or 0, tonumber(dupBlind) or 0)
    end
  end
  -- ===== 第二趟：动手（藏原生 + 数量守护），并复位/自愈我们自己的画布 =====
  for _, it in ipairs(shows) do
    local o = it.o
    -- ★★★1.75.60b：**本拍刚被判成异体、已经藏掉的那几条，这一趟不许再 `Show` 回来**
    --   （同一拍里两趟打架 = 图上那份重复图一闪一闪；判据 = 本拍的去重结论优先）
    if (type(dupSet) ~= "table") or (dupSet[o] ~= true) then
      if it.hidden and pcall(o.Show, o) then reshow = reshow + 1 end
      -- ★★★1.75.60g（真机 A/B 定案：透明度 0.70 时洛克莫丹贴图一闪一闪、调回 1.00 立刻不闪）：
      --   **只自愈「我们自己写过 0」的那些**（`MDQ.alphaZeroByIdx` = 按序号 + 按图记的账）。
      --   旧写法把「alpha < 0.999」一律当成上一版的误伤，而「缩放大地图 → 透明度」< 1 时**我们画布的 alpha
      --   本来就读回 < 1**（那是用户的设置，不是伤）⇒ 旧写法每一拍都把 25 层强行写回 1 ⇒ 与设置互相覆盖
      --   = **每拍一闪**（存档里那几行「自愈：把我们自己的 25 个画布层的 alpha 从 0 还原成不透明」就是它）。
      --   ⇒ 没有我们自己的账 ⇒ **一个字节都不写**（用户的透明度归用户），只如实记一行取证。
      local aRec = (it.idx ~= nil) and MDQ.alphaZeroByIdx[it.idx] or nil
      if aRec ~= nil and tostring(aRec) == tostring(file) and type(o.SetAlpha) == "function" then
        local rec0 = MDQ.holdAlphaByIdx[it.idx]
        local use = (rec0 ~= nil and rec0 > 0.999) and rec0 or 1
        if pcall(o.SetAlpha, o, use) then
          fixA = fixA + 1
          MDQ.alphaZeroByIdx[it.idx] = nil
        end
      elseif it.alpha ~= nil and it.alpha < 0.999 and MDQ.saidAlphaNotOurs ~= tostring(file)
        -- ★1.75.60l：**我们自己设的「迷雾贴图统一透明度」不是「别人的透明度」** ⇒ 不许拿那句
        --   「多半是『缩放大地图 → 透明度』设置」去误报（否则用户一调透明度就吃到一条假诊断；取证行只许真话）。
        and not ((type(MDQ.alphaIsOurs) == "function") and MDQ.alphaIsOurs(it.alpha)) then
        MDQ.saidAlphaNotOurs = tostring(file)
        pcall(MDQ.staleLogPut, string.format(
          "画布 alpha < 1 但**不是我们写的**（地图=%s ｜ %.3f）⇒ 一个字节都不动（多半是「缩放大地图 → 透明度」"
            .. "设置；旧版把它当误伤、每拍写回 1 ⇒ 一闪一闪）", tostring(file), it.alpha))
      end
    end
  end
  for _, it in ipairs(kills) do
    local o, ours = it.o, it.ours
    -- ★★★1.75.59k（用户：「取消『只 Hide/Show』这条禁令，我要完成功能。不能限制自己用什么技术」）：
    --   **动手前先把原值抓下来**（贴图/UV/宽高/锚点/显隐/alpha；按**对象**存进原值账）。
    --   ★顺序即判据：抓原值必须**排在 Hide / SetAlpha 之前**（写过的值当原值 = 关掉也回不去）。
    --   ★`hadRec` 必须在记名前取：只有**已经在账上**的层才是「客户端又 Show 出来 ⇒ 再藏」（保住 `again` 语义）。
    local hadRec = (MDQ.holdHid[o] ~= nil)
    if not ours then pcall(MDQ.holdNote, o, file, "接管藏") end
    if pcall(o.Hide, o) then
      hid = hid + 1
      if not ours then
        local rec = MDQ.holdHid[o]
        if rec == nil then
          -- （正常走不到：上面已经记过账；留着兜底，仍是**唯一写账口**）
          rec = nil
        end
        -- ★双保险第二步：**alpha 归零**（黑幕 1.75.5 同款手法 —— 客户端把我们 Hide 掉的层又 Show 回来时，
        --   `IsShown` 会变 true 而**画面依然看不见** ⇒ 把「每拍重新追上」的窗口从 0.3s 收窄到「不闪」）。
        --   ★只在**抓到过原 alpha** 时才写：抓不到就没法还回去 —— **有原值才写**。
        local a0 = rec and rec.a or nil
        local wrote0 = false
        if a0 ~= nil and type(o.SetAlpha) == "function" then wrote0 = pcall(o.SetAlpha, o, 0) end
        -- ★1.75.59m：原 alpha 再按**序号**存一份（枚举句柄与我们手里的句柄不可比较 ⇒ 还回时要靠序号查）
        local idxK = MDQ.poolIdx(o)
        if idxK ~= nil and a0 ~= nil then MDQ.holdAlphaByIdx[idxK] = a0 end
        -- ★1.75.60g：**记下「这一格是我们自己写成 0 的」**（存在性守护的自愈只认这一份账 ⇒ 透明度设置不会被误当误伤）；
        --   按**图名**记 ⇒ 换图/收层即作废（同一序号在不同图上是不同的块）。
        if wrote0 and idxK ~= nil then MDQ.alphaZeroByIdx[idxK] = tostring(file) end
        if hadRec then
          local recO = MDQ.holdHid[o]
          if recO ~= nil then
            recO.again = (tonumber(recO.again) or 0) + 1
            again = again + 1
            -- ★「客户端又把它 Show 出来了」= 用户报障的那条现象；每个对象最多记 3 次（环有界、不刷屏）
            if recO.again <= 3 then
              MDQ.staleLogPut(string.format("接管再藏（第 %d 次）：地图=%s ｜ 原生层 %s（客户端自己又 Show 出来了；已 Hide + alpha 0）",
                recO.again, tostring(file), tostring(recO.name)))
            end
          end
        end
      end
    end
  end
  local st = MDQ.holdStat
  st.map, st.want = tostring(file), want
  st.hid, st.again, st.reshow, st.seen = hid, again, reshow, seen
  st.ours = oursSeen
  st.fixa = fixA
  st.at = (type(GetTime) == "function") and GetTime() or 0
  -- ★1.75.59m **自愈出声**（本会话只一次）：我们自己的画布被上一版（1.75.59l）误判成原生层藏过 + alpha 归零
  --   ⇒ 这一拍已经把它们 `Show` 回来、alpha 也还原成不透明；**如实说清是「按不透明还原」而不是「按原值」**。
  if fixA > 0 and not MDQ.saidAlphaHeal then
    MDQ.saidAlphaHeal = true
    pcall(MDQ.staleLogPut, string.format("自愈：地图=%s ｜ 把我们自己的 **%d** 个画布层的 alpha 从 0 还原成不透明", tostring(file), fixA))
    pcall(smFitSay, "接管守护自愈：把我们自己的 **%d** 个画布层还原成不透明（上一版把「枚举里认不出我们画的」误判成"
      .. "「客户端原生」⇒ 连我们画的也被 Hide + alpha 0 了；现在按序号认画布，不再误伤）", fixA)
  end
  -- ★「客户端又把它 Show 出来了」正是用户报障的那条现象 ⇒ **必须出声**（常开出口），但**每图只一次**
  --   （逐帧重申那一拍 + 客户端每次重摆都可能命中它，不节流就是刷屏）。
  if again > 0 then
    local mkA = smMapKey() or tostring(file)
    if MDQ.holdSaidAgain ~= mkA then
      MDQ.holdSaidAgain = mkA
      pcall(smFitSay, "接管守护：地图=%s ｜ 客户端又把 **%d** 个原生探索层 Show 出来了 ⇒ **已当场再藏**"
        .. "（守护每拍都查：① 数量 = 表推本图 %d 块；② 存在性 = 超出块数的池位一律藏）",
        tostring(file), again, want)
    end
  end
  return hid, reshow, seen, want, again
end

-- 把我们藏过的**客户端原生层**全部还回（关开关 / 关功能 / 关图 / 关模块；幂等）⇒「绝不永久藏」+「绝不永久改」
MDQ.holdShowAll = function(why)
  local n = 0
  for o in pairs(MDQ.holdHid) do
    -- ★★★1.75.59k：还回 = `Show` **+ 把原值逐样还回**（放开技术手段后我们可能在它身上写过 alpha/贴图/几何）
    --   ⇒ 走**同一个单条还原口**（有原值就整条还，抓不到原值就只 Show），绝不各写一套。
    if MDQ.origIdx[o] ~= nil then
      pcall(MDQ.origRestoreOne, o)    else
      pcall(o.Show, o)
    end
    MDQ.holdHid[o] = nil
    n = n + 1
  end
  MDQ.holdOrder = {}
  if n > 0 then
    pcall(mfLog, "接管守护（%s）：把藏过的 %d 个客户端原生探索层全部 Show 还回（有原值的按原值还原）", tostring(why), n)
  end
  return n
end

-- 只读体检（`/ehm mapfit 残留` 里一并打印）：**数量**（本图应有几块）+ **存在性**（逐条：谁的 / 显示没显示 / 结论）
--   ★零副作用：只 `IsShown` / `GetTexture` / `GetRegions`，一个 `Set*` 都不发。
MDQ.holdProbe = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local okFile = (file ~= "")
  local want = MDQ.holdN(okFile and file or nil)
  local drew = tonumber(MDQ.lastRenderN) or 0
  table.insert(out, string.format(
    "接管守护（世界迷雾 %s）：地图=%s ｜ 表推本图应有 %d 块 ｜ "
      .. "上一次守护：藏原生 %d ｜ 又冒出来再藏 %d ｜ 我们自建被藏后复位 %d ｜ 枚举池位 %d（认出我们画的 %d）｜ 原生藏账 %d 条%s",
    MDQ.swm() and "**开**" or "关", okFile and file or "?", want,
    tonumber(MDQ.holdStat.hid) or 0, tonumber(MDQ.holdStat.again) or 0, tonumber(MDQ.holdStat.reshow) or 0,
    tonumber(MDQ.holdStat.seen) or 0, tonumber(MDQ.holdStat.ours) or 0, MDQ.holdLedgerN(),
    MDQ.holdStat.blind and "　★判不出（枚举里一个我们画的都没认出）⇒ **一个字节都不碰**" or ""))
  -- ★六改 b：再摊**本拍的渲染账**（用户报障「数据库查出来的层有没添加进去」的唯一直接答案）：
  --   渲染 N 块 / 表里 M 区 / 在不在表里 / 有没有渲完整 / 失败原因 / 现读倍率
  local rr = MDQ.lastRender
  if type(rr) == "table" then
    table.insert(out, string.format(
      "接管渲染：地图=%s ｜ 表里 %d 区 ⇒ **渲染 %d 块**（在表里=%s ｜ 渲完整=%s ｜ 倍率 k=%.3f）%s",
      tostring(rr.map or "?"), tonumber(rr.areas) or 0, tonumber(rr.n) or 0,
      rr.inTbl and "是" or "**否**", rr.full and "是" or "**否**",
      tonumber(rr.k) or 1, rr.why and (" ｜★" .. tostring(rr.why)) or ""))
  else
    table.insert(out, "接管渲染：**本会话还没渲染过**（地图关着 / 替代开关刚打开还没到一拍）")
  end
  if want <= 0 or drew <= 0 then
    table.insert(out, "　（**数据库里没有这张图 / 一块都没画出来** ⇒ 接管守护按「无从替代」处理："
      .. "客户端自己的探索层**保持原样**，一个字节都不碰 —— 不会出现空白图）")
  end
  if not MDQ.swm() then
    table.insert(out, "　（替代开关关着 ⇒ 接管守护**一个字节都不碰**；这时由「残留图层清理」那两条规则负责）")
  end
  local fr = _G["WorldMapDetailFrame"]
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if okr then
      local rows = {}
      for _, o in ipairs(regs) do
        if o ~= nil and MDQ.stalePoolName(o) then
          local idx = MDQ.poolIdx(o)
          -- ★1.75.59i：身份判定与守护**同一口径**（旧写法只认 `ownSet` ⇒ 活句柄被误标「客户端原生」）
          local ours = MDQ.oursOf(o, idx)
          local oks, shown = pcall(o.IsShown, o)
          local okp, path = pcall(o.GetTexture, o)
          if not okp then path = nil end
          local pos = (idx ~= nil) and ("#" .. tostring(idx)) or "#（认不出尾号）"
          local verdict
          if ours then
            verdict = (idx ~= nil and idx <= want) and "本图该在（被藏就复位）" or "**超出本图块数 ⇒ 藏**"
          elseif want > 0 and drew > 0 then
            verdict = "**客户端原生 ⇒ 藏**（本图有表数据，替代语义）"
          else
            verdict = "客户端原生 ⇒ **保持原样**（数据库里没有这张图 / 一块都没画出来 ⇒ 一个字节都不碰）"
          end
          table.insert(rows, string.format("　%s ｜ %s ｜ %s ｜ %s ｜ 贴图=%s ⇒ %s",
            tostring(frameName(o)), pos, ours and "我们自建" or "客户端原生",
            (oks and shown == true) and "显示中" or "已隐藏", tostring(path), verdict))
        end
      end
      table.sort(rows)
      -- ★★★1.75.54c **决定性诊断**：我们手里的活句柄有没有出现在这份枚举里。
      --   0 个 ⇒ 枚举的是**另一批对象**（多半是客户端上几代同名纹理：1.12 没有销毁纹理的 API，
      --     客户端每次重摆版式都新建一批、旧的既不销毁也不隐藏）⇒ 身份只能靠「活句柄」这一条；
      --   >0 ⇒ 枚举里确实混着我们的层 ⇒ 同号的重复条可以安全藏（叠影消失）。
      local liveHit, liveN = 0, 0
      for i = 1, (tonumber(MDQ.poolSeen) or 0) do
        local lt = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
        if lt ~= nil then
          liveN = liveN + 1
          for _, o in ipairs(regs) do if o == lt then liveHit = liveHit + 1 break end end
        end
      end
      table.insert(out, string.format("　★活句柄核对：我们手里 %d 个池位，**%d 个出现在上面的枚举里**"
        .. "（0 ⇒ 枚举的是上几代同名纹理；>0 ⇒ 同号重复条可安全藏）", liveN, liveHit))
      if table.getn(rows) == 0 then
        table.insert(out, "　（本图枚举到的 region 里**没有** WorldMapOverlay* 池位）")
      else
        for _, r in ipairs(rows) do table.insert(out, r) end
      end
    end
  end
  return out
end

-- ★★★1.75.59i：**一句话结论**（用户：「为啥搞这么多次测试工具这么麻烦，不能直接在节拍内把所有 `WorldMapOverlay*`
--   隐藏吗?」）—— 先澄清两点，本命令就是为这两点服务的：
--     ① **「在节拍内自动全藏」本来就是现行实现**（`holdTick` 挂在渲染节拍上、判定 `kill = not ours` 无豁免）；
--     ② 但「做了」与「**能证明做到了**」是两件事，而这类失效**完全安静**（盲门一触发就是一个字节都不碰，
--        屏幕上与「已全藏好」长得一模一样 —— 1.75.54c 真机事故就是这么漏了一版）。
--   ⇒ 本命令 = **只读的结论口**：一条命令直接回答「这一类在本图是否全量隐藏」。
--   ★零副作用（只 `GetRegions`/`IsShown`/`GetTexture`/`GetName`，一个 `Set*` 都不发）。
--   ★判据全部走 `MDQ.oursOf`（与守护同一口径）⇒ 结论不可能与守护行为打架。
--   ★如实分档（不许把「判不出」「本图没数据」都报成 ❌ —— 那会让用户白折腾）：
--     ✅ 全量隐藏 · ❌ 还有客户端的层显示中 / 判不出（盲） · ⚠️ 开关关着 / 本图无从替代 / 枚举不到这一类。
MDQ.holdVerdict = function()
  local out = {}
  local function add(s) table.insert(out, s) end
  local file = tostring(select(1, smMapInfo()) or "")
  local on = MDQ.swm()
  local want = MDQ.holdN(file ~= "" and file or nil)
  local drew = tonumber(MDQ.lastRenderN) or 0
  add(string.format("接管守护体检（只读）：地图=%s ｜ 开关=%s ｜ 表推本图应有 %d 块 ｜ 本拍渲染 %d 块 ｜ 原生藏账 %d 条",
    (file ~= "" and file or "?"), on and "**开**" or "关", want, drew, MDQ.holdLedgerN()))
  -- ===== 枚举（只读；口径与守护逐字一致：名字族 + oursOf 身份）=====
  local nA, nK, nM, nL, nH, liveN, liveHit, nVis, nDup = 0, 0, 0, 0, 0, 0, 0, 0, 0
  local seenIdx = {}
  local bad, why = {}, nil
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    why = "地图帧不在 / 没有 `GetRegions`（地图没开?）"
  else
    local okr, regs = pcall(function() return { fr:GetRegions() } end)
    if not okr then
      why = "`WorldMapDetailFrame:GetRegions()` 抛错"
    else
      for _, o in ipairs(regs) do
        if o ~= nil and MDQ.stalePoolName(o) then
          nA = nA + 1
          local idx = MDQ.poolIdx(o)
          -- ★1.75.59m：同序号重复条计数（真机实测：枚举 43 = 25 + 18 条重名重复）——
          --   「按序号认画布」之后它们**全被算成我们的** ⇒ 结论行必须如实说明这一情形（见下面 ✅ 那一档）
          if idx ~= nil then
            if seenIdx[idx] then nDup = nDup + 1 else seenIdx[idx] = true end
          end
          local ours = MDQ.oursOf(o, idx)
          local oks, shown = pcall(o.IsShown, o)
          if oks and shown == true then
            nK = nK + 1
            -- ★1.75.59m：**「显示中」不等于「看得见」** —— alpha=0 时 `IsShown()` 仍报 true（自检 [5] 实证）。
            --   我们自己的层必须「显示中 ∧ 不透明」才算这份体检的成功态，否则会像 1.75.59l 那样报一个假的 ✅。
            local oka2, al2 = pcall(o.GetAlpha, o)
            local opaque = (not oka2) or (not tonumber(al2)) or tonumber(al2) > 0.999
            if ours then
              nM = nM + 1
              if opaque then nVis = nVis + 1 end
            else
              nL = nL + 1
              -- 只列前 8 条（够定位；不刷屏）
              if table.getn(bad) < 8 then
                local okp, path = pcall(o.GetTexture, o)
                table.insert(bad, string.format("　%s ｜ %s ｜ 显示中 ｜ 贴图=%s",
                  tostring(frameName(o)), (idx ~= nil) and ("#" .. tostring(idx)) or "#（认不出尾号）",
                  tostring(okp and path or nil)))
              end
            end
          else
            nH = nH + 1
          end
        end
      end
      -- 活句柄核对（同 `残留` 体检：0 ⇒ 枚举的是上几代同名纹理）
      for i = 1, (tonumber(MDQ.poolSeen) or 0) do
        local lt = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
        if lt ~= nil then
          liveN = liveN + 1
          for _, o in ipairs(regs) do if o == lt then liveHit = liveHit + 1 break end end
        end
      end
    end
  end
  local tail = string.format("（枚举 %d ｜ 同序号重复 %d ｜ 显示中 %d：我们的 **%d**（其中不透明的 **%d**）/ 其它 **%d** ｜ 已隐藏 %d ｜ 活句柄 %d 个、在枚举里 %d 个 ｜ 盲=%s）",
    nA, nDup, nK, nM, nVis, nL, nH, liveN, liveHit, MDQ.holdStat.blind and "**是**" or "否")
  if why ~= nil then
    add("结论：⚠️ **判不出** —— " .. why .. "（换个已开的区域图再跑一次）")
  elseif not on then
    add("结论：⚠️ **开关关着** ⇒ 接管守护不接管（这时这一类由「残留图层清理」按另一套规则处理）" .. tail)
  elseif MDQ.holdStat.blind then
    add("结论：❌ **判不出谁是原生 ⇒ 一个字节都不碰**（枚举里一个「我们画的」都没认出）"
      .. "　⇒ 这不是「藏不动」，是安全门生效；把 `/ehm mapfit 残留` 发我定位。" .. tail)
  elseif want <= 0 or drew <= 0 then
    add("结论：⚠️ **本图无从替代**（表里没有这张图 / 一块都没画出来）⇒ 守护按「一个字节都不碰」保持客户端原样"
      .. "（**这不是失效** —— 宁可留残留，也绝不画空白图）" .. tail)
  elseif nA == 0 then
    add("结论：⚠️ **本图枚举不到 WorldMapOverlay* 这一类**（`GetRegions()` 里一个都没有）⇒ 无对象可藏；"
      .. "若屏幕上仍看得到这一类，说明它们**不在 `WorldMapDetailFrame` 下**（要靠 `/edb` 看挂在谁下面）" .. tail)
  elseif nL == 0 and nVis > 0 then
    if nH == 0 then
      -- ★1.75.59m（真机第二、三次自检的诚实版）：这一情形下 **守护一条都没藏**（`已隐藏 0`）——
      --   「客户端的原生层已全藏」这句话**不是成绩**，只能读成「**枚举里没有一条被判成客户端的**」；
      --   按序号认画布之后，**同序号重复条**（真机实测 18 条）也全归我们 ⇒ **必须如实说清**，不许冒充「藏过」。
      add(string.format("结论：✅ **我们自己的层都在显示（且不透明）**；★ 本拍**一条都没藏**（已隐藏 0）——"
        .. "枚举 %d 条**全部**被判成我们的画布（含 **%d** 条同序号重复）⇒ 这一行**不是**「藏掉了客户端层」的成绩，"
        .. "只是「枚举里没有一条被判成客户端的」。若屏上仍见到原生探索层的叠影，把这一行发我（要收紧身份判定）。",
        nA, nDup) .. tail)
    else
      add("结论：✅ **客户端的原生层已全藏，我们自己的层正常显示**（枚举里显示中的只有我们画的，且不透明）" .. tail)
    end
  elseif nL == 0 and nVis == 0 then
    -- ★★★1.75.59m 新增档（1.75.59l 在这里报的是一句**假的 ✅**）：枚举里一条都不是「客户端原生」，可我们自己的
    --   画布也一条都没显示（或被写成透明）⇒ 这是**功能坏了**，不是「藏得好」（曾经就是守护把我们自己藏光了）。
    add(string.format("结论：❌ **我们自己的层一条都没显示**（枚举 %d 条里，显示中的我们的 = %d、其中不透明的 = %d）"
      .. "　⇒ 这不是「藏得好」而是**把我们自己的画布也藏了/写成透明了**；守护下一拍应自愈（`Show` + 还原不透明），"
      .. "若连续几次都这样，把这一行发我。", nA, nM, nVis) .. tail)
  else
    add(string.format("结论：❌ **还有 %d 条客户端的 WorldMapOverlay* 处于显示中**"
      .. "（下一拍守护会再藏；若每次跑都 >0，把下面明细发我）%s", nL, tail))
  end
  if table.getn(bad) > 0 then
    add("　显示中、但不是我们画的（最多列 8 条）：")
    for _, l in ipairs(bad) do add(l) end
  end
  add(string.format("　上一次守护：藏原生 %d ｜ 又冒出来再藏 %d ｜ 复位我们的画布 %d ｜ 自愈 alpha %d ｜ 认出我们画的 %d",
    tonumber(MDQ.holdStat.hid) or 0, tonumber(MDQ.holdStat.again) or 0,
    tonumber(MDQ.holdStat.reshow) or 0, tonumber(MDQ.holdStat.fixa) or 0, tonumber(MDQ.holdStat.ours) or 0))
  return out
end

-- ★★★1.75.59j：**alpha / 透明纹理这两条「不走 Hide」的路，实测定案口**（用户问：「WorldMapOverlay 隐藏的方式
--   不单是 hide/show，还有设置透明度、给他一张透明的纹理.之类的试过吗?」）
--   ★在案的事实（本次逐条查过 git 历史与全仓）：
--     ① **alpha 试过**：1.75.45b 的 `smFitGhostHide/Keep/Show`（`git show 05f6b2d:tools/SimpleMap.lua`）就是
--        对**同一批** `WorldMapOverlay*` 纹理 `GetAlpha` 抓原值 → `SetAlpha(0)` 隐形 → 还原；它随 1.75.52
--        「探索层适配」整块摘除，替代者选了**直接 Hide**（在案理由：Hide 更彻底）。
--     ② **「给一张透明纹理」没试过**，且在案是**禁止项**（接管守护三条纪律第一条：绝不 `SetTexture`）——
--        来源是 1.75.51 两次真机事故（改写枚举到的 region ⇒ 地图错乱），定案「宁可留残留，也绝不许动 region」。
--     ③ **两条记录互相矛盾**（都没在这批纹理上实测过）：`EH_DebugBox.lua:708`「本客户端 Texture:SetAlpha
--        是**变暗**不是透明」vs 旧 SimpleMap 探针「SetAlpha = **真透明**（透出游戏世界，但那是打在**帧**上）」。
--   ⇒ 本口分两层，**都必须由用户显式敲命令**才动：
--     · **只读探针** `检查 alpha`：这批纹理有没有 `SetAlpha`/`GetAlpha`、当前 alpha 分布、有没有「显示中却已 alpha≈0」的
--       （**客户端自己也在用 alpha 隐形**就是这一条）—— 一个字节都不写；
--     · **一次性自证实验** `检查 alpha 试 [alpha|贴图]`：挑 **1 条「不是我们的」**层，记原 alpha/原贴图 → 写 →
--       **每拍读回**看客户端哪一拍把值改回去 → **窗口一到立刻还原并读回自证**。窗口与行数都有界。
--   ★为什么必须「每拍读回」：这正是 alpha 唯一可能胜过 Hide 的地方（客户端重摆时通常只动 Show/Hide 与几何、
--     **不动 alpha** ⇒ alpha 0 可能扛过 re-Show；黑幕 1.75.5 就是靠 `SetAlpha(0)` 硬抗 + `Hide` 保鼠标赢的）；
--     而「能不能扛过」只能实测，**不许猜**（本项目铁律：客户端 API 行为必须先探针取证）。
MDQ.TRIAL_SEC = 3.0      -- 观察窗口（秒；有界，到点必还原）
MDQ.TRIAL_ROWS = 12      -- 最多记几拍读数（防刷屏；首拍一定记）
MDQ.TRIAL_GAP = 0.25     -- 读数采样间隔（秒）
MDQ.TRIAL_TEX = "Interface\\Buttons\\WHITE8X8"   -- 「一张透明纹理」的实际做法：1×1 纯白 + alpha 0 = 全透明
MDQ.trial = nil

MDQ.trialActive = function() return MDQ.trial ~= nil end

-- ① **只读探针**：这批纹理上 alpha 这套 API 到底在不在、客户端自己有没有用过
MDQ.alphaProbe = function()
  local out = {}
  local function add(s) table.insert(out, s) end
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    add("alpha 探针：⚠️ 地图帧不在 / 没有 `GetRegions`（地图没开?）⇒ 判不出")
    return out
  end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then add("alpha 探针：⚠️ `GetRegions()` 抛错 ⇒ 判不出") return out end
  local nA, nSet, nGet, nOne, nOther, nZero = 0, 0, 0, 0, 0, 0
  local amin, amax, samples = nil, nil, {}
  for _, o in ipairs(regs) do
    if o ~= nil and MDQ.stalePoolName(o) then
      nA = nA + 1
      local hasS = (type(o.SetAlpha) == "function")
      local hasG = (type(o.GetAlpha) == "function")
      if hasS then nSet = nSet + 1 end
      if hasG then nGet = nGet + 1 end
      if hasG then
        local okv, v = pcall(o.GetAlpha, o)
        local a = okv and tonumber(v) or nil
        if a ~= nil then
          if a == 1 then nOne = nOne + 1 else
            nOther = nOther + 1
            if amin == nil or a < amin then amin = a end
            if amax == nil or a > amax then amax = a end
            local oks, shown = pcall(o.IsShown, o)
            if a <= 0.01 and (oks and shown == true) then nZero = nZero + 1 end
            if table.getn(samples) < 4 then
              table.insert(samples, string.format("　%s ｜ alpha=%.2f ｜ 显示=%s",
                tostring(frameName(o)), a, (oks and shown == true) and "是" or "否"))
            end
          end
        end
      end
    end
  end
  add(string.format("alpha 只读探针（**一个字节都不写**）：枚举 WorldMapOverlay* %d 条 ｜ 有 `SetAlpha` %d ｜ 有 `GetAlpha` %d",
    nA, nSet, nGet))
  add(string.format("　alpha 分布：=1 的 %d ｜ ≠1 的 %d%s ｜ **显示中但 alpha≈0** 的 %d",
    nOne, nOther, (amin ~= nil) and string.format("（最小 %.2f / 最大 %.2f）", amin, amax) or "", nZero))
  if nZero > 0 then
    add("　★ 客户端**自己也在用 alpha 隐形**（有层显示着却 alpha≈0）⇒ 这条路在本客户端是活的")
  elseif nOther > 0 then
    add("　★ 客户端自己确实动过 alpha（有层 ≠1，但不是 0）")
  elseif nSet > 0 and nGet > 0 then
    add("　★ 本图所有池位 alpha 都 = 1 ⇒ 客户端没用 alpha 做隐形；能不能用要跑实验（`/ehm mapfit 检查 alpha 试`）")
  elseif nSet == 0 then
    add("　❌ 这批纹理上**没有 `SetAlpha`** ⇒ 这条路在本客户端不成立（只能 Hide/Show）")
  end
  for _, l in ipairs(samples) do add(l) end
  add("　说明：alpha 0 时 `IsShown()` **仍报 true** ⇒ 若改用 alpha，`检查`/`残留` 的「显示中」判据必须同时看 alpha（本口已按此读）")
  return out
end

-- ② **一次性自证实验**：`kind = "alpha" | "tex"`；只动 **1 条「不是我们的」**层；窗口一到**必还原**
--   ★只挑「不是我们的」：动了我们自己的层 = 把我们画的块弄没了（正是守护要防的事）⇒ 绝不碰。
MDQ.trialStart = function(kind)
  kind = tostring(kind or "alpha")
  local out = {}
  local function add(s) table.insert(out, s) end
  if MDQ.trial ~= nil then
    add("实验：⚠️ 上一次实验还没结束（先 `/ehm mapfit 检查 alpha 停` 或等窗口走完）")
    return out
  end
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    add("实验：⚠️ 地图没开（没有 `WorldMapDetailFrame`）⇒ 先在**区域图**上跑")
    return out
  end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then add("实验：⚠️ `GetRegions()` 抛错 ⇒ 判不出") return out end
  -- 挑一条：名字族 ∧ 不是我们的 ∧ 当前显示着
  local pick, pickIdx = nil, nil
  for _, o in ipairs(regs) do
    if o ~= nil and MDQ.stalePoolName(o) and (not MDQ.oursOf(o)) then
      local oks, shown = pcall(o.IsShown, o)
      if oks and shown == true then pick, pickIdx = o, MDQ.poolIdx(o) break end
    end
  end
  if pick == nil then
    add("实验：⚠️ 本图枚举里**没有「不是我们的」且显示中的 WorldMapOverlay\\* 层** ⇒ 无可试对象"
      .. "（若这一类全被守护藏好了，先 `/ehm mapfit swm off` 再试，或换张图）")
    return out
  end
  local T = { o = pick, kind = kind, n = 0, rows = {}, reset = 0, t0 = (type(GetTime) == "function") and GetTime() or 0 }
  -- ★字段名**不能叫 `until`**（Lua 关键字；本项目在案老坑：`{ until = … }` 直接语法错，luacheck 当场抓到）
  T.stopAt = (tonumber(T.t0) or 0) + (tonumber(MDQ.TRIAL_SEC) or 3)
  T.lastRow = -99
  -- 抓原值（**写之前先读**——本项目铁律）
  if type(pick.GetAlpha) == "function" then
    local okv, v = pcall(pick.GetAlpha, pick)
    if okv and tonumber(v) then T.a = tonumber(v) end
  end
  if type(pick.GetTexture) == "function" then
    local okp, p = pcall(pick.GetTexture, pick)
    if okp then T.tex = tostring(p) end
  end
  add(string.format("alpha 实验（自证）：层=%s ｜ %s ｜ 原 alpha=%s ｜ 原贴图=%s",
    tostring(frameName(pick)), (pickIdx ~= nil) and ("#" .. tostring(pickIdx)) or "#（认不出尾号）",
    T.a and string.format("%.2f", T.a) or "读不到", tostring(T.tex)))
  add(string.format("　窗口 %.1fs ｜ 每 %.2fs 记一拍（最多 %d 拍）｜ 到期**必还原** ｜ kind=%s",
    tonumber(MDQ.TRIAL_SEC) or 3, tonumber(MDQ.TRIAL_GAP) or 0.25, tonumber(MDQ.TRIAL_ROWS) or 12, tostring(kind)))
  -- 写（唯一写点）
  local w1, w2 = false, nil
  if kind == "tex" then
    if type(pick.SetTexture) == "function" then w1 = pcall(pick.SetTexture, pick, MDQ.TRIAL_TEX) end
    if type(pick.SetAlpha) == "function" then w2 = pcall(pick.SetAlpha, pick, 0) end
    T.texWrote = MDQ.TRIAL_TEX
    add(string.format("　已写：`SetTexture(%s)` + `SetAlpha(0)`（1×1 纯白 + alpha 0 = **全透明**）⇒ 调用成功=%s / %s",
      tostring(MDQ.TRIAL_TEX), tostring(w1), tostring(w2)))
  else
    if type(pick.SetAlpha) ~= "function" then
      add("　❌ 这条纹理上**没有 `SetAlpha`** ⇒ alpha 这条路在本客户端不成立")
      return out
    end
    w1 = pcall(pick.SetAlpha, pick, 0)
    add("　已写：`SetAlpha(0)` ⇒ 调用成功=" .. tostring(w1))
  end
  -- 立即读回（写后自证）
  local okv2, v2 = false, nil
  if type(pick.GetAlpha) == "function" then okv2, v2 = pcall(pick.GetAlpha, pick) end
  add(string.format("　写后立即读回：alpha=%s", (okv2 and tonumber(v2)) and string.format("%.2f", tonumber(v2)) or "读不到"))
  MDQ.trial = T
  -- 挂节拍（开关关着也要挂：实验是用户敲的、自己有时限、必还原）
  if type(MDQ.beatSync) == "function" then pcall(MDQ.beatSync) end
  add("　★已挂节拍开始逐拍读回（开关关着也只跑实验这一条腿，绝不碰地图）")
  return out
end

-- 每拍读回（**只读**；到点或客户端改回够多次就收）
MDQ.trialTick = function()
  local T = MDQ.trial
  if T == nil then return false end
  local o = T.o
  if o == nil then return MDQ.trialStop("对象没了") end
  local now = (type(GetTime) == "function") and GetTime() or 0
  local okv, v = false, nil
  if type(o.GetAlpha) == "function" then okv, v = pcall(o.GetAlpha, o) end
  local aTxt = (okv and tonumber(v)) and string.format("%.2f", tonumber(v)) or "读不到"
  local okp, p = false, nil
  if type(o.GetTexture) == "function" then okp, p = pcall(o.GetTexture, o) end
  local pTxt = okp and tostring(p) or "读不到"
  local oks, shown = pcall(o.IsShown, o)
  T.n = (tonumber(T.n) or 0) + 1
  -- 采样有界（防刷屏；首拍一定记）
  if T.n == 1 or ((now - (tonumber(T.lastRow) or -99)) >= (tonumber(MDQ.TRIAL_GAP) or 0.25)
    and table.getn(T.rows) < (tonumber(MDQ.TRIAL_ROWS) or 12)) then
    T.lastRow = now
    table.insert(T.rows, string.format("　第 %d 拍（%.2fs）：alpha=%s ｜ 贴图=%s ｜ 显示=%s%s",
      T.n, now - (tonumber(T.t0) or now), aTxt, pTxt, (oks and shown == true) and "是" or "否",
      (T.kind == "tex" and pTxt ~= tostring(T.texWrote)) and "　★客户端**改回了贴图**" or ""))
  end
  -- 判定「客户端有没有把它改回去」（这才是 alpha 唯一可能胜过 Hide 的地方）
  local resetNow = false
  if T.kind == "tex" then
    resetNow = (pTxt ~= tostring(T.texWrote))
  else
    local a = tonumber(v)
    resetNow = (a ~= nil and a > 0.01)
  end
  if resetNow then T.reset = (tonumber(T.reset) or 0) + 1 end
  if now >= (tonumber(T.stopAt) or 0) then return MDQ.trialStop("观察窗口结束") end
  return true
end

-- 还原口（**唯一**；窗口到点 / 手动 `停` / 关功能 / 关图 都走它）—— 幂等
MDQ.trialStop = function(why)
  local T = MDQ.trial
  if T == nil then return nil end
  MDQ.trial = nil
  local o = T.o
  local back = { alpha = "读不到", tex = "读不到" }
  if o ~= nil then
    if type(o.SetAlpha) == "function" and T.a ~= nil then pcall(o.SetAlpha, o, T.a) end
    if type(o.SetTexture) == "function" and T.tex ~= nil then pcall(o.SetTexture, o, T.tex) end
    -- 读回自证
    if type(o.GetAlpha) == "function" then
      local okv, v = pcall(o.GetAlpha, o)
      if okv and tonumber(v) then back.alpha = string.format("%.2f", tonumber(v)) end
    end
    if type(o.GetTexture) == "function" then
      local okp, p = pcall(o.GetTexture, o)
      if okp then back.tex = tostring(p) end
    end
  end
  if type(MDQ.beatSync) == "function" then pcall(MDQ.beatSync) end
  local out = {}
  local function add(s) table.insert(out, s) end
  add(string.format("alpha 实验结束（%s）：层=%s ｜ 共读 %d 拍 ｜ 客户端改回 %d 次",
    tostring(why), tostring(frameName(o)), tonumber(T.n) or 0, tonumber(T.reset) or 0))
  for _, r in ipairs(T.rows or {}) do add(r) end
  add(string.format("　★已还原（唯一还原口）：alpha=%s（原 %s）｜ 贴图=%s（原 %s）",
    tostring(back.alpha), T.a and string.format("%.2f", T.a) or "读不到",
    tostring(back.tex), tostring(T.tex)))
  if T.kind == "tex" then
    if (tonumber(T.reset) or 0) == 0 then
      add("结论：✅ **「给一张透明纹理」扛得住**（客户端在观察窗内没把贴图改回去）"
        .. " ⇒ 可作为「Hide + 透明纹理」的备选（★但别忘了：这仍要抓原贴图 + 有界还原，漏还原 = 原生层永久空白）")
    else
      add("结论：❌ **客户端会把贴图改回去**（改回 " .. tostring(T.reset) .. " 次）⇒ 不比 Hide 强，不值得换")
    end
  else
    if (tonumber(T.reset) or 0) == 0 then
      add("结论：✅ **alpha 0 扛得住**（观察窗内客户端一次都没改回）"
        .. " ⇒ 「Hide + `SetAlpha(0)`」双保险可行（黑幕 1.75.5 就是同一手法赢的）"
        .. "；★要上就必须一起改两处：抓原值/有界账/三路还原 + **读数判据升级成「IsShown ∧ alpha>0」**")
    else
      add("结论：❌ **客户端会把 alpha 改回**（改回 " .. tostring(T.reset) .. " 次）⇒ alpha 只能「下一拍重申」用，"
        .. "不比 Hide 省；这条路不值得换（在案矛盾记录以本次实测为准）")
    end
  end
  return out
end


-- ★★★1.75.59l：**一条命令自检**（用户：「你能不能准备一条命令.我打开地图配合你运行.直接自己跑完.
--   存储到日志.然后自己已排查」）⇒ `/ehm mapfit 自检`（别名 `selfcheck` / `全诊`）：
--   · **一次跑完全部只读取数**（★不写地图、不改几何、**绝不调 `holdTick`** —— 守护本来就在节拍里跑，
--     这里只**观察它跑过的结果**）：渲染账 / 枚举逐条（对象类型·父级·显隐·贴图·尺寸·alpha·谁的·是否在 `_G`）/
--     我方活句柄逐条（在哪·显隐·贴图·**在不在枚举里**）/ 客户端帧结构样本 / alpha API 探针 / 守护上一拍账 / 一句话结论；
--   · 全文写进**有界落盘环** `worldFogCfg.fitDiag`（上限 500 行）⇒ `/reload` 落盘后 AI **直接读存档**排查；
--   · 聊天框只回显**少量关键行**（防刷屏）+ 提示 `/reload`。
MDQ.FIT_DIAG_MAX = 500
-- ★1.75.59m：自检跑完**等几秒再自动重载**（`/reload` 会清空聊天框 ⇒ 立刻重载 = 回显当场被抹掉）
MDQ.SELF_RELOAD_SEC = 6
MDQ.selfReloadAt = nil
MDQ.fitDiagPut = function(lines)
  local ring = SM_CFG.fitDiag
  if type(ring) ~= "table" then ring = {} SM_CFG.fitDiag = ring end
  local stamp = (type(date) == "function") and tostring(date("%m-%d %H:%M:%S")) or "?"
  table.insert(ring, string.format("===== 自检 %s ｜ 改动记号 %s ｜ 共 %d 行（读法：从后往前看最后一组）=====",
    stamp, tostring(MDQ.BUILD), table.getn(lines)))
  for _, l in ipairs(lines) do table.insert(ring, tostring(l)) end
  while table.getn(ring) > (tonumber(MDQ.FIT_DIAG_MAX) or 500) do table.remove(ring, 1) end
  return table.getn(ring)
end

-- 单对象一行读数（**全部 pcall**：本客户端某个读口缺席时如实写「读不到」，绝不抛错打断整份自检）
local function objLine(tag, i, o, regs)
  local function g(m)
    if o == nil or type(o[m]) ~= "function" then return "读不到" end
    local ok, v = pcall(o[m], o)
    if not ok then return "读不到" end
    return v
  end
  local nm = frameName(o)
  local ot = g("GetObjectType")
  local pa = g("GetParent")
  local paN = "?"
  if pa ~= nil and pa ~= "读不到" then paN = tostring(frameName(pa) or "无名") end
  local sh = g("IsShown")
  local tx = g("GetTexture")
  local w, h = g("GetWidth"), g("GetHeight")
  local al = g("GetAlpha")
  local idx = MDQ.poolIdx(o)
  local inG = "否"
  if idx ~= nil and rawget(_G, "WorldMapOverlay" .. tostring(idx)) == o then inG = "是" end
  local inEnum = "否"
  if regs ~= nil then
    for _, r in ipairs(regs) do if r == o then inEnum = "是" break end end
  end
  return string.format("%s#%d 名=%s 序号=%s 类型=%s 父=%s 显示=%s 贴图=%s 尺寸=%sx%s alpha=%s 谁的=%s 在_G=%s 在枚举=%s",
    tag, i, tostring(nm), (idx ~= nil) and tostring(idx) or "-", tostring(ot), paN,
    (sh == true) and "是" or ((sh == false) and "否" or tostring(sh)), tostring(tx),
    tostring(w), tostring(h), tostring(al),
    MDQ.oursOf(o, idx) and "我们" or "客户端", inG, inEnum)
end

MDQ.fitBattery = function()
  local out = {}
  local function add(s) table.insert(out, s) end
  local file = tostring(select(1, smMapInfo()) or "")
  local fr = _G["WorldMapDetailFrame"]
  local want = MDQ.holdN(file ~= "" and file or nil)
  local es = nil
  if fr ~= nil then
    local okE, v = pcall(smEffScale, fr)
    if okE and tonumber(v) then es = tonumber(v) end
  end
  -- ===== ① 环境与渲染账 =====
  add(string.format("[1] 环境：改动记号=%s ｜ 地图=%s ｜ 开关=%s ｜ 表推本图应有 %d 块 ｜ 本拍渲染 %d 块 ｜ es=%s ｜ 引擎自报叠加层=%s",
    tostring(MDQ.BUILD), (file ~= "" and file or "?"), MDQ.swm() and "开" or "关", want, tonumber(MDQ.lastRenderN) or 0,
    es and string.format("%.3f", es) or "读不到", tostring(smNumOverlays())))
  local rr = MDQ.lastRender
  if type(rr) == "table" then
    add(string.format("[1] 渲染账：地图=%s 表里 %d 区 ⇒ %d 块（在表里=%s 渲完整=%s 倍率 k=%.3f）%s",
      tostring(rr.map or "?"), tonumber(rr.areas) or 0, tonumber(rr.n) or 0, rr.inTbl and "是" or "否",
      rr.full and "是" or "否", tonumber(rr.k) or 1, rr.why and (" ｜ " .. tostring(rr.why)) or ""))
  end
  -- ===== ② 枚举逐条（上限 60；这是判「客户端那批到底是什么」的主证据）=====
  local regs = {}
  local okr = false
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function" then
    okr, regs = pcall(function() return { fr:GetRegions() } end)
    if not okr then regs = {} end
  end
  local nTex, nFrame, nOther, nAnon = 0, 0, 0, 0
  for _, o in ipairs(regs) do
    local ot = "?"
    if o ~= nil and type(o.GetObjectType) == "function" then
      local ok, v = pcall(o.GetObjectType, o)
      if ok then ot = tostring(v) end
    end
    if ot == "Texture" then nTex = nTex + 1 elseif ot == "Frame" then nFrame = nFrame + 1 else nOther = nOther + 1 end
    local nm = frameName(o)
    if nm == nil or tostring(nm) == "" or tostring(nm) == "?" then nAnon = nAnon + 1 end
  end
  add(string.format("[2] region 总数=%d（Texture %d ／ Frame %d ／ 其它 %d ／ **无名 %d**）",
    table.getn(regs), nTex, nFrame, nOther, nAnon))
  local nPool, shown = 0, 0
  for k, o in ipairs(regs) do
    if o ~= nil and MDQ.stalePoolName(o) then
      nPool = nPool + 1
      local oks, sh = pcall(o.IsShown, o)
      if oks and sh == true then shown = shown + 1 end
      if nPool <= 60 then add("[2] " .. objLine("枚举", nPool, o, regs)) end
    end
  end
  add(string.format("[2] 名字族 WorldMapOverlay*：**%d** 条（显示中 %d）", nPool, shown))
  -- ===== ③ 我方活句柄逐条（上限 40）——「我们在哪、在不在枚举里」=====
  local holdN, liveHit = 0, 0
  for i = 1, (tonumber(MDQ.poolSeen) or 0) do
    local t = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
    if t ~= nil then
      holdN = holdN + 1
      local inEnum = false
      for _, r in ipairs(regs) do if r == t then inEnum = true break end end
      if inEnum then liveHit = liveHit + 1 end
      if holdN <= 40 then
        add("[3] " .. objLine("我方", i, t, regs) .. string.format(" self-made=%s ownSet=%s wroteObj=%s",
          (MDQ.own[i] == t) and "是" or "否", (MDQ.ownSet[t] == true) and "是" or "否", (MDQ.wroteObj[t] == true) and "是" or "否"))
      end
    end
  end
  add(string.format("[3] 我方活句柄 **%d** 条 ｜ **出现在枚举里的 %d 条**（0 ⇒ 枚举的是另一批对象）", holdN, liveHit))
  -- ===== ④ 客户端帧结构样本（客户端真正的叠加层挂在哪）=====
  if (type(fr) == "table" or type(fr) == "userdata") and type(fr.GetChildren) == "function" then
    local okc, kids = pcall(function() return { fr:GetChildren() } end)
    if okc then
      add(string.format("[4] WorldMapDetailFrame 子件 %d 个（前 20 个）：", table.getn(kids)))
      for k = 1, math.min(20, table.getn(kids)) do
        local c = kids[k]
        local cn, ct = frameName(c), "?"
        if c ~= nil and type(c.GetObjectType) == "function" then
          local ok, v = pcall(c.GetObjectType, c)
          if ok then ct = tostring(v) end
        end
        add(string.format("[4]   子#%d 名=%s 类型=%s", k, tostring(cn or "无名"), tostring(ct)))
      end
    end
  end
  -- ===== ⑤ alpha API 探针（只读）=====
  for _, l in ipairs(MDQ.alphaProbe()) do add("[5] " .. tostring(l)) end
  -- ===== ⑥ 守护上一拍账 + 一句话结论（都只读）=====
  local st = MDQ.holdStat or {}
  add(string.format("[6] 守护上一拍：藏原生 %d ｜ 又冒出来再藏 %d ｜ 复位我们的画布 %d ｜ 自愈 alpha %d ｜ 枚举池位 %d ｜ 认出我们画的 %d ｜ 盲=%s ｜ 原生藏账 %d 条",
    tonumber(st.hid) or 0, tonumber(st.again) or 0, tonumber(st.reshow) or 0, tonumber(st.fixa) or 0,
    tonumber(st.seen) or 0, tonumber(st.ours) or 0, st.blind and "是" or "否", MDQ.holdLedgerN()))
  for _, l in ipairs(MDQ.holdVerdict()) do add("[7] " .. tostring(l)) end
  -- ===== ⑨ 本游戏专属坐标补偿（与 `MapOverlayData.lua` 配对）=====
  --   ★1.75.59o：编辑模式拖出来的补偿逐条进自检落盘环 ⇒ **AI 读存档就能拿到全部数字**（不让玩家转述）。
  do
    local mine, tot = MDQ.editCount(file)
    add(string.format("[9] 迷雾补偿（编辑模式）：开关=%s ｜ 本图 **%d** 条 / 全部 %d 条 ｜ 落盘历史 %d 条"
      .. "（存 worldFogCfg.edit / editLog；`x,y` = 表口径补偿，最终坐标 = 表值 + 补偿）",
      (MDQ.editOn and MDQ.editOn()) and "开" or "关", mine, tot, MDQ.editLogN()))
    if mine > 0 then
      local jn = MDQ.editJoin(file)
      add(string.format("[9] 配对 MapOverlayData.lua：命中 %d ｜ 孤儿（查不到 ⇒ 不生效）%d ｜ 基础表已变 %d",
        tonumber(jn.hit) or 0, tonumber(jn.orphan) or 0, tonumber(jn.drifted) or 0))
      local per = MDQ.editMap(file, false)
      local k2 = 0
      local keys = {}
      for key in pairs(per or {}) do table.insert(keys, tostring(key)) end
      table.sort(keys)
      for _, key in ipairs(keys) do
        if k2 >= 12 then break end
        local r = per[key]
        if type(r) == "table" then
          k2 = k2 + 1
          local base = nil
          local a, tn = string.match(key, "^(.-)#(%d+)$")
          local mm = MDQ.areaOf(file)
          if type(mm) == "table" and a ~= nil then base = mm[a] end
          local bx, by = nil, nil
          if base ~= nil then bx, by = select(3, MDQ.expectRect(base, tonumber(tn) or 1)) end
          add(string.format("[9] 　%s ｜ 表值 %s,%s ＋ 补偿 x=%+.1f y=%+.1f ⇒ 最终 %s,%s ｜ k=%s es=%s ｜ %s",
            key, tostring(r.bx or bx), tostring(r.by or by), tonumber(r.x) or 0, tonumber(r.y) or 0,
            tostring((tonumber(bx) or 0) + (tonumber(r.x) or 0)), tostring((tonumber(by) or 0) + (tonumber(r.y) or 0)),
            tostring(r.k), tostring(r.es), tostring(r.t or "?")))
        end
      end
      if mine > 12 then add(string.format("[9] 　… 还有 %d 条（全量在存档 worldFogCfg.edit）", mine - 12)) end
    end
  end
  -- ===== ⑩ 同序号重复（★1.75.59q：真机截图「同一张图两份，一份可拖、一份拖不动」）=====
  add(string.format("[10] 同序号重复：本拍 %d 组 ｜ 藏掉「另一张纹理」%d 条 ｜ 判为同一张纹理的别名 %d 条 ｜ 判不出 %d 组"
    .. "（判据 = **属性往返探针**，不是对象 `==`；判不出就一个字节都不碰）",
    tonumber(MDQ.dupStat.groups) or 0, tonumber(MDQ.dupStat.hid) or 0,
    tonumber(MDQ.dupStat.same) or 0, tonumber(MDQ.dupStat.blind) or 0))
  add(string.format("[8] 读法：先看 [2]（客户端那批是什么）+ [3]（我们在不在枚举里）+ [7]（结论）；[2]/[3] 的类型/父级决定「该藏谁」。"))
  return out
end

-- ★★★1.75.54 **性能体检**（`/ehm mapfit perf`；用户报障「开了十几个地区以后游戏会卡死」换来的取证口）：
--   ★口令是「体检」不是「只读」—— 它**真跑两拍**（与正常节拍完全相同的那条路：渲染 + 护守），会写地图层。
--   为什么这么设计：卡顿只有在**真跑**时才量得出来（离线 harness 只能数调用次数，量不到引擎真实耗时）。
--   读数同时进**有界落盘环** `SM_CFG.perfProbe`(40) ⇒ AI 读存档即可判「有没有慢拍 / 哪一拍慢 / 写了几次」。
MDQ.perfProbe = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local fr = _G["WorldMapDetailFrame"]
  local es = 1
  if fr ~= nil then
    local eff = smEffScale(fr)
    if tonumber(eff) and tonumber(eff) > 0 then es = tonumber(eff) end
  end
  local m = MDQ.areaOf(file)
  local nArea = 0
  if type(m) == "table" then for _ in pairs(m) do nArea = nArea + 1 end end
  table.insert(out, string.format("性能体检：地图=%s ｜ 表里 %d 区 / 应有 %d 块 ｜ 外框 es=%.3f ｜ 开关=%s ｜ 纹理池上限 %d",
    tostring(file), nArea, MDQ.holdN(file), es, MDQ.swm() and "开" or "关", MDQ.poolMax))
  table.insert(out, string.format("　引擎自报叠加层 %s 条（`GetNumMapOverlays`；**探索过的地区越多它越大**）",
    tostring(smNumOverlays())))
  local T = (type(GetTime) == "function") and GetTime or function() return 0 end
  local rows = {}
  -- ★两拍**故意走两条不同的路**（1.75.54b 起）：第 1 拍 = **节流拍**（withGuard = true ⇒ force ⇒
  --   **必须整批重申**，写 N 次是正常的）；第 2 拍 = **逐帧拍**（withGuard = false ⇒ 写前比对 ⇒ **应写 0 次**）。
  --   ⇒ 一条命令同时量出「重申的代价」与「比对的收益」；第 2 拍还在写 ⇒ 有东西每拍在变（报给作者看这两行）。
  for pass = 1, 2 do
    local t0 = T()
    local n1 = select(1, MDQ.renderCurrent(es, true, true, pass == 1))
    local ms = (T() - t0) * 1000
    local line = string.format("第 %d 拍（%s）：%.1f ms ｜ 渲染 %s 块 ｜ **写 %s 次** ｜ 跳过(内容没变) %s ｜ 护守：枚举 %s ｜ 藏 %s ｜ 复位 %s ｜ 认出我们画的 %s%s",
      pass, (pass == 1) and "节流拍·强制重申" or "逐帧拍·写前比对",
      ms, tostring(n1), tostring(MDQ.wroteN or 0), tostring(MDQ.skipN or 0),
      tostring(MDQ.holdStat.seen or 0), tostring(MDQ.holdStat.hid or 0), tostring(MDQ.holdStat.reshow or 0),
      tostring(MDQ.holdStat.ours or 0), MDQ.holdStat.blind and " ｜ **盲（判不出谁是原生 ⇒ 一个字节都不碰）**" or "")
    table.insert(out, line)
    rows[#rows + 1] = line
  end
  table.insert(out, string.format("安全阀：perfGuard=%s ｜ 慢拍阈值 %d ms（连续 3 拍 > %d ms 也降档）｜ 最近 %d 拍：%s",
    tostring(MDQ.perfGuard), tonumber(MDQ.SLOW_MS) or 12, tonumber(MDQ.SLOW_WARN_MS) or 6,
    table.getn(MDQ.perfRing), (function()
      local t = {}
      for _, r in ipairs(MDQ.perfRing) do
        t[#t + 1] = string.format("%.0fms/写%d", tonumber(r.ms) or 0, tonumber(r.wrote) or 0)
      end
      return table.concat(t, " ")
    end)()))
  table.insert(out, "　★判读：**第 1 拍（节流拍）该写满 N 次** —— 那是「强制重申」，客户端自己重摆过也能被我们纠正回来（1.75.54b）；"
    .. "**第 2 拍（逐帧拍）该「写 0 次」** = 写前比对生效（逐帧那条路才省开销）；"
    .. "若第 2 拍还在写 ⇒ 有东西每拍在变（报给作者看这两行）；单拍 > 12ms ⇒ 会自动降档（逐帧重申停掉）。")
  table.insert(out, "　★地区多导致叠加层多时：护守每拍要枚举全部 region（只读），这是**节流拍**才做的事（0.1s/0.3s）。")
  if type(SM_CFG) == "table" then
    if type(SM_CFG.perfProbe) ~= "table" then SM_CFG.perfProbe = {} end
    local ring = SM_CFG.perfProbe
    table.insert(ring, string.format("[%s] %s ｜ %s", date and tostring(date("%H:%M:%S")) or "?", tostring(file), table.concat(rows, " ｜ ")))
    while table.getn(ring) > 40 do table.remove(ring, 1) end
  end
  for _, l in ipairs(out) do pcall(mfLog, "[perf] %s", l) end
  return out
end

-- ★★★1.75.51（用户：「缩放大地图->设置内->添加个 S_WorldMap 贴图替代开关」）：
--   **数据源 = `MDQ.swm()`**（唯一判据入口；产品开关，落存档）：
--     · 开（**默认**）= **表驱动全渲染**（`MDQ.render`，见那一族）：不抓原值、不读本地缓存、不逐层折算 ——
--       贴图/UV/尺寸/位置全部由 S_WorldMap 表现算，客户端内置的那批探索层被逐条改写/多余的藏起来；
--     · 关 = 不再碰叠加层（1.75.52 用户定：整条「探索层适配」已摘除，关掉就是**客户端原生行为**）。
--   ★判据写法：**一律写 `MDQ.swm()`**（挂在既有 `MDQ` 表上）—— 主 chunk 有 **200 个 local 的上限**，
--     为这种一个布尔判断新增文件级 local 会把离线 harness 直接顶爆
--     （历史实测症状 `LOAD FAIL: … too many local variables (limit is 200) in main function`）。
--
-- ★★★1.75.51（用户：「清理掉本地地图签名缓存」）：**清本地缓存**的**唯一出口**（幂等；内存 + 存档老键一起清）。
--   · 存档老键四个（`mapFitOrig` 老原值 · `mapFitVer` 版本戳 · `mapFitTrace` 取证环 · `mapFitCapLog` 抓原值环）
--     —— 它们正是用户要清的「之前调试的日志」；返回清掉的**存档键个数**（0 = 本来就没有）。
--   ★挂在 `MDQ` 表上而不是新增文件级 local（同上：200 local 上限）。
MDQ.cacheClear = function(why)
  local n = 0
  if type(SM_CFG) == "table" then
    for _, k in ipairs({ "mapFitOrig", "mapFitVer", "mapFitTrace", "mapFitCapLog" }) do
      if SM_CFG[k] ~= nil then SM_CFG[k] = nil n = n + 1 end
    end
  end
  pcall(mfLog, "清缓存（%s）：存档老键 %d 个（原值/写入账那些会话内存已随探索层适配整条摘除）", tostring(why), n)
  return n
end

-- ============ 开图节拍（**自包含**：宿主只喊一句 `EVAL_WF_TICK`）============
--   ★★★1.75.56：这一套原来长在 `SimpleMap.lua` 的开图 tick 里 —— 搬家的意义 = **本模块自带自己的有界节拍**
--     （项目纪律「工具模块自带自己的有界计时器」），宿主换文件/改节拍都不会把迷雾带坏。
--   契约：`EVAL_WF_TICK(es, dt, open, mk)` —— `es` 外框有效缩放 / `dt` 本帧步长 / `open` 地图是否开着 /
--     `mk` 当前地图签名（= `EVAL_SM_MAPKEY()`）；模块关掉那一拍由宿主先喊 `EVAL_WF_SHUTDOWN`。
local BURST_GAP, BURST_SEC, IDLE_GAP = 0.1, 2.0, 0.3
local REARM_MIN, BURST_FRAMES = 0.5, 90

-- 引擎真值签名（客户端自己那批叠加层**条数 + 首块宽度**）—— 我们写不进去 ⇒ 它变 = 真的换图/真缩放
local function engineSig()
  local n = tonumber(smNumOverlays())
  if n == nil then return nil end
  local w = ""
  if n > 0 and type(GetMapOverlayInfo) == "function" then
    local ok, _, cw = pcall(function() return GetMapOverlayInfo(1) end)
    if ok and tonumber(cw) then w = tostring(math.floor(tonumber(cw) + 0.5)) end
  end
  return tostring(n) .. ":" .. w
end

local TS = { open = false, mapKey = nil, burst = 0, burstN = 0, rearmAt = 0, engSig = nil, acc = 0,
  staleUntil = 0, staleAt = -99, staleHidN = 0, staleBackN = 0, staleSaid = false, staleSaidNoPool = false }

MDQ.tick = function(es, dt, open, mk)
  -- ★★★1.75.57b（用户：「开关状态是否能正确关闭,节拍停止」）：**双保险** —— 除了节拍帧那边
  --   「关掉就真摘 OnUpdate」，这里也先判一次开关：任何调用者（将来谁再接一根线）在关着时都推不动一拍，
  --   而且这一句**早于任何探测/读写**（连 `GetNumMapOverlays` 都不读）= 铁律「关掉零动作」的落地。
  if not MDQ.swm() then return 0 end
  dt = tonumber(dt) or 0.05
  local nowT = (type(GetTime) == "function") and GetTime() or 0
  local function armStale()
    TS.staleUntil = nowT + MDQ.STALE_SEC
    TS.staleAt, TS.staleSaid, TS.staleSaidNoPool = -99, false, false
    TS.staleHidN, TS.staleBackN = 0, 0
  end
  -- ① 换图（签名变）⇒ 武装爆发窗 + 残留清理窗口（客户端这时才重摆/重指贴图）
  if mk ~= nil and mk ~= TS.mapKey then
    TS.mapKey = mk
    if open then TS.burst, TS.acc, TS.burstN, TS.rearmAt = BURST_SEC, 1e9, 0, nowT armStale() end
  end
  -- ② 开图那一拍：同样武装（并让本拍立刻渲染一次）
  if open and not TS.open then
    TS.burst, TS.acc, TS.burstN, TS.rearmAt = BURST_SEC, 1e9, 0, nowT
    armStale()
  end
  -- ③ 残留图层清理节拍：**只 Hide/Show**，规则全在 `MDQ.staleTick` 里
  do
    local hasLedger = (type(MDQ.staleHid) == "table") and (next(MDQ.staleHid) ~= nil)
    if (not MDQ.staleOn()) and hasLedger then
      pcall(MDQ.staleShowAll, "残留图层清理已关")
      hasLedger = false
    end
    if open and mk ~= nil and MDQ.staleOn() then
      local armed = (tonumber(TS.staleUntil) or 0) > nowT
      local gapS = armed and MDQ.STALE_GAP or MDQ.STALE_GAP_IDLE
      if (armed or hasLedger) and ((nowT - (tonumber(TS.staleAt) or -99)) >= gapS) then
        TS.staleAt = nowT
        local hidS, backS, seenS, fileS, nLed, lvlWhyS = MDQ.staleTick()
        hidS, backS = tonumber(hidS) or 0, tonumber(backS) or 0
        TS.staleHidN = (tonumber(TS.staleHidN) or 0) + hidS
        TS.staleBackN = (tonumber(TS.staleBackN) or 0) + backS
        if hidS > 0 or backS > 0 then
          pcall(mfLog, "残留图层：地图=%s（%s）｜ 本拍藏 %d 个叠加层 ｜ 还回 %d 个 ｜ 看过池位 %d 个 ｜ 藏账还留 %d 条",
            tostring(fileS), tostring(lvlWhyS or "?"), hidS, backS, tonumber(seenS) or 0, tonumber(nLed) or 0)
        end
        -- ★一个池位都没认出 ⇒ 每图出声一次（判据与真机对不上若静默，用户会以为修好了而残留照旧）
        --   ★「让位」那一拍不许出声（那时 staleTick 根本没干活，seenS==0 是让位不是「名字对不上」）。
        local stood = string.find(tostring(lvlWhyS or ""), "接管守护", 1, true) ~= nil
        if (not TS.staleSaidNoPool) and (not stood) and (tonumber(seenS) or 0) == 0 and hidS == 0 then
          TS.staleSaidNoPool = true
          pcall(smFitSay, "残留图层清理：地图=%s（%s）**没认出任何 WorldMapOverlay 池位** ⇒ 这一档什么都没藏"
            .. "（图上若仍有残留，请敲 `/ehm mapfit 残留` 把首行发我 —— 那行有真机上的纹理名）",
            tostring(fileS), tostring(lvlWhyS or "?"))
        end
        if (not TS.staleSaid) and (tonumber(TS.staleHidN) or 0) > 0 then
          TS.staleSaid = true
          pcall(smFitSay, "残留图层清理：地图=%s（%s）｜ 已藏 **%d** 个叠加层：%s"
            .. "（**本图没有探索层数据** ⇒ 全藏、只 Hide 不改几何；**切到有数据的区域图会全部还回**；全量见 /ehm mapfit 残留）%s",
            tostring(fileS), tostring(lvlWhyS or "?"), tonumber(TS.staleHidN) or 0, MDQ.staleNames(8),
            ((tonumber(TS.staleBackN) or 0) > 0) and ("；期间已还回 " .. tostring(TS.staleBackN) .. " 个") or "")
        end
      end
    end
  end
  -- ④ 关图 ⇒ 把藏过的层**全部还回**（残留清理 + 接管守护；绝不把「藏」的状态带进下一张图）
  if (not open) and TS.open then
    pcall(MDQ.staleShowAll, "地图已关")
    pcall(MDQ.holdShowAll, "地图已关")
    -- ★1.75.59o/p：关图那一拍**结束拖拽 + 收起拖拽柄与贴图列表**（只在状态翻转那一下做，不是每帧）
    if MDQ.editStop then pcall(MDQ.editStop, "地图已关") end
    if MDQ.grabHideAll then pcall(MDQ.grabHideAll, "地图已关") end
  end
  -- ⑤ 爆发窗的重新武装**只认「引擎真值」**（绝不认 `es` 抖动 —— 那正是 1.75.53 卡死根因）
  local ev = engineSig()
  if ev ~= nil and TS.engSig ~= nil and ev ~= TS.engSig then
    if (nowT - (tonumber(TS.rearmAt) or -99)) >= REARM_MIN then
      TS.rearmAt, TS.burstN, TS.burst, TS.acc = nowT, 0, BURST_SEC, 1e9
    end
  end
  if ev ~= nil then TS.engSig = ev end
  if (tonumber(TS.burst) or 0) > 0 then
    TS.burstN = (tonumber(TS.burstN) or 0) + 1
    if TS.burstN > BURST_FRAMES then TS.burst = 0 end      -- ★帧数上限：绝不无限逐帧重申
  end
  if not open then TS.burst, TS.burstN = 0, 0 end
  TS.open = open
  if (tonumber(TS.burst) or 0) > 0 then TS.burst = math.max(0, TS.burst - dt) end
  -- ⑥ 渲染节拍：爆发窗内逐帧重申、之后 0.3s 一拍；节流那一拍带护守、逐帧那条不带
  if not (open and es and tonumber(es) and tonumber(es) > 0) then return 0 end
  local gap = ((tonumber(TS.burst) or 0) > 0) and BURST_GAP or IDLE_GAP
  TS.acc = (tonumber(TS.acc) or 0) + dt
  if TS.acc >= gap then
    TS.acc = 0
    pcall(MDQ.renderCurrent, tonumber(es), false, false, true)   -- 带护守的那一拍
  end
  if (tonumber(TS.burst) or 0) > 0 and not MDQ.perfGuard then
    pcall(MDQ.renderCurrent, tonumber(es), true, true, false)    -- 逐帧重申：silent + 不跑护守
  end
  return 1
end

-- ============ 本模块**自己的开图节拍帧**（★绝不依赖「缩放大地图」那个开关）============
--   ★★★1.75.56 真机报障（用户截图：「缩放大地图」未勾 + 迷雾那个勾选框已勾 ⇒ 迷雾不生效；该勾选框当时叫「打开世界迷雾」，1.75.59c 起按用户要求改名**「关闭世界迷雾」**）：
--     第一版把本模块的节拍挂在 `SimpleMap` 的开图 tick 里，而那个 tick 在「缩放大地图**关掉**」时
--     **整段早退**（`if not EVAL_SM_ENABLED() then … return end`）⇒ 迷雾跟着一起停摆 ——
--     界面上勾选框显示「开」、实际一个字节都不做（最坏的那种**静默失效**）。
--   ⇒ 本模块**自带帧**（项目纪律「工具模块自带自己的有界计时器」）：只看**自己那个开关**，
--     与「缩放大地图」开关完全无关；宿主那边**不再**喊 `EVAL_WF_TICK`（两处喊 = 每帧白跑两遍）。
do
  local parent = _G["WorldFrame"]
  if not (type(parent) == "table" or type(parent) == "userdata") then parent = _G["UIParent"] end
  if type(CreateFrame) == "function" and parent then
    local wf = CreateFrame("Frame", "EH_WF_FEAT", parent)
    -- ★★★1.75.57b（用户：「开关状态是否能正确关闭,节拍停止.图层清理操作」）——**关掉零动作**：
    --   ① 节拍函数**第一行**先判自己那个开关：关着一拍都不往下走（**连 `GetNumMapOverlays` / 地图签名
    --      都不读**，更不做换图/引擎签名/残留清理的任何探测）—— 这是项目铁律「关掉零动作」的字面落地；
    --   ② 关掉那一刻由 `MDQ.fogSet(false)` **真摘 OnUpdate**（不是靠每帧早退），开回来再挂上；
    --   ③ 图层清理（收我们自建的层 + 还原复用池位 + 把藏过的原生层全部还回）在 `fogSet(false)` 里
    --      **同步做完**（走 `MDQ.shutdown`）—— 绝不寄托在常驻节拍上（否则关掉后还得靠帧跑才干净）。
    local function beat()
      -- ★★★1.75.59j：**实验拍优先** —— 用户敲的 alpha 自证实验要逐拍读回（才能看客户端哪一拍改回去）。
      --   ★纪律不变：下面 `swm()` 那道闸门**照旧在任何地图探测之前** ⇒ 开关关着时本拍**只跑实验这一条腿**，
      --     连地图签名都不读、不渲染、不调 `MDQ.tick`（实验自己有时限、到期必还原、`beatSync` 会摘掉节拍）。
      if MDQ.trialActive and MDQ.trialActive() then pcall(MDQ.trialTick) end
      -- ★★★1.75.59o：**编辑模式的拖拽推进也挂在这一帧上**（一个模块只许一个节拍帧 ⇒ 绝不另建 OnUpdate）。
      --   ★排在 `swm()` 那道闸门**之前**：万一拖到一半开关被关掉，最后那一下也要能正常收尾
      --     （绝不把「拖拽中」的状态留在内存里）。没在拖时 `editTick` 只做一次 nil 判断。
      if (type(MDQ.dragSt) == "table") or (MDQ.editOn and MDQ.editOn()) then pcall(MDQ.editTick) end
      -- ★★★1.75.59m：**自检的「延后落盘」**（用户真机反馈：「执行直接重载了.然后啥事没干」——
      --   聊天框会被 `/reload` 清空 ⇒ 立刻重载等于把回显当场抹掉）⇒ 改成**约定时刻**在这里执行：
      --   命令只盖一个时间戳（`MDQ.selfReloadAt`），到点由本行 `ReloadUI`；`beatSync` 在有待办时也会挂节拍。
      local srAt = tonumber(MDQ.selfReloadAt)
      if srAt ~= nil then
        local nowT = (type(GetTime) == "function") and GetTime() or 0
        if nowT >= srAt then
          MDQ.selfReloadAt = nil
          local okr = false
          if type(RunScript) == "function" then okr = pcall(RunScript, "ReloadUI()") end
          if not okr then
            -- ★不许直接写 `pcall(say, …)`：`say` 是本文件**后文**的 local ⇒ 这里会绑成全局 nil 被 pcall 静默吞掉
            --   （本项目「前向声明老雷」；这条路上必须用 `_G` 现取出口）。
            local sf = rawget(_G, "EVAL_SAY_FORCE") or rawget(_G, "EVAL_SAY")
            if type(sf) == "function" then
              pcall(sf, "[mapfit] [自检] ⚠️ 自动重载没成功 ⇒ 请你**手动 `/reload`** 一次（之后 AI 就能读到全文）")
            end
          end
          return
        end
      end
      if not MDQ.swm() then return end          -- ★关着：本拍零动作（早于任何探测/读写）
      local dt = tonumber(arg1) or 0.05
      local openFn = br("EVAL_SM_OPEN")
      local open = false
      if openFn then open = (openFn() == true) end
      if not open then
        -- 关图那一拍也要跑：把藏过的原生层/账**全部还回**（绝不把「藏」的状态带过关图）
        pcall(MDQ.tick, nil, dt, false, nil)
        return
      end
      local fr = _G["WorldMapDetailFrame"]
      local effFn = br("EVAL_SM_EFFSCALE")
      local es = nil
      if fr ~= nil and effFn then es = effFn(fr) end
      local mkFn = br("EVAL_SM_MAPKEY")
      local mk = mkFn and mkFn() or nil
      pcall(MDQ.tick, es, dt, true, mk)
    end
    -- ★★★1.75.59c：**载入期不挂节拍**（默认不勾选 ⇒ 连一次空节拍都不跑）。挂/摘的唯一入口 = 下面的
    --   `MDQ.beatSync`（`VARIABLES_LOADED` 清账块调一次，`MDQ.fogSet` 每次切换也调）。
    -- 挂在模块表上（**不新增文件级 local**；`fogSet` / `beatSync` 后面用它真摘/重挂）
    MDQ.wfFrame, MDQ.wfBeat = wf, beat
  end
end

-- ★★★1.75.59c（用户：「默认以上两个都不勾选」）——**节拍与开关同步的唯一入口** `MDQ.beatSync()`：
--   ① 打开 ⇒ 挂上 beat；关掉/默认关 ⇒ **真摘 `SetScript(…, "OnUpdate", nil)`**（项目铁律：关掉零动作
--      = 真摘，**不是**靠每帧早退 —— 每帧早退也还在跑、还在读）；
--   ② 载入期就要调一次（`VARIABLES_LOADED` 清账块里）⇒ 默认不勾选的用户**一帧空节拍都不跑**；
--   ③ 全文件 `OnUpdate` 注册/摘除**只有这一处**（harness 结构钉守着计数），将来谁再接一根线也推不动。
MDQ.beatSync = function()
  if MDQ.wfFrame == nil or MDQ.wfBeat == nil then return false end
  -- ★1.75.59j：**实验在跑时也要挂**（用户敲的实验自带时限、到期必还原）——
  --   载入期这条判据仍然是「开关 ∨ 实验」都为假 ⇒ 默认不勾选的用户照旧**一帧空节拍都不跑**。
  -- ★1.75.59m：**自检的延后落盘待办也要挂**（开关关着时也得有人执行那次 `ReloadUI`）。
  -- ★1.75.59o：**编辑模式开着也要挂**（那是用户显式选中的模式，不是「默认开」的空转）——
  --   拖拽的推进（`MDQ.editTick`）走的就是这一帧（一个模块只许一个节拍帧）。
  if MDQ.swm() or (MDQ.editOn and MDQ.editOn()) or (MDQ.trialActive and MDQ.trialActive()) or (tonumber(MDQ.selfReloadAt) ~= nil) then
    pcall(MDQ.wfFrame.SetScript, MDQ.wfFrame, "OnUpdate", MDQ.wfBeat)
  else
    pcall(MDQ.wfFrame.SetScript, MDQ.wfFrame, "OnUpdate", nil)
  end
  return true
end

-- ============ 迷雾**自己的工具箱行** + 开关 + 命令（1.75.56 从 SimpleMap 搬出来，独立管理）============
--   用户定：「将开启迷雾功能独立个脚本文件代码管理」+「单独占工具箱一行（自己一个勾选框 + 自己的 [设置]）」。
-- ★前向声明在文件顶部（`local say, L`）⇒ 这里改**赋值**（`L = function(...)`），别写回 `local function`
L = function(k, ...)
  if type(EVAL_L) == "function" then return EVAL_L(k, ...) end
  return k
end
-- ★★★1.75.59f（用户定 **A 方案**：「调试日志关掉就不许自动说话；但**我敲的命令必须看得见**」）：
--   **命令回显窗口** —— `MDQ.cmd` 入口盖章（截止 = 现在 + `WF_ECHO_SEC`）。窗口内本模块的 `say`
--   走**不门控**的 `EVAL_SAY_FORCE`（你问它答必须可见）；窗口外照旧走受门控的 `EVAL_SAY`。
--   ★用时间戳而不是布尔标志：命令分支有多个 `return`，标志漏清就会「此后自动播报都漏出来」。
--   ★自动播报（残留清理 / 守护 / 渲染自证走的是桥 `EVAL_SM_FITSAY` = SimpleMap 的 `smFitSay`）
--     由 SimpleMap 那边统一门控 ⇒ 本文件**不需要**第二份门控（一处真值）。
-- ★前向声明在文件顶部（`local say, L, WF_ECHO_SEC, WF_ECHO_AT`）⇒ 这两行改**赋值**，别写回 `local`
--   （写回 = 编辑模式那些按钮闭包写的是另一份、`wfEchoing()` 读的还是这份 ⇒ 盖章永远不生效 = 点了像没反应）
WF_ECHO_SEC = 0.75
WF_ECHO_AT = 0
local function wfEchoing()
  if type(GetTime) ~= "function" then return false end
  return GetTime() <= (tonumber(WF_ECHO_AT) or 0)
end
-- ★前向声明在文件顶部（`local say, L`）⇒ 这里改**赋值**（`say = function(...)`），别写回 `local function`
--   （★这条不是洁癖：编辑模式整族都在这句**上面**，写回 `local` = 它们的播报全绑全局 nil）
say = function(msg)
  msg = tostring(msg)
  if wfEchoing() then
    local f = rawget(_G, "EVAL_SAY_FORCE") -- 命令回显：强制可见（不受「调试日志」管）
    if type(f) == "function" then pcall(f, msg) return end
  end
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, msg) return end
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, tostring(msg))
  end
end

-- 合并开关真值（唯一读写口）：`SM_CFG.swmOverlay`；★**1.75.65 起默认开**（nil ⇒ 载入期落成显式 true），
--   **显式 false 才是关**（用户主动关过 ⇒ 永远尊重）；两个老键（swmOverlay / staleClean）一起写 ⇒ 两族闸门天然一致。
--   ★写入点 = 工具箱这一行的勾选框 / `/ehm mapfit swm on|off`（★1.75.65 起 `[设置]` 下拉里**不再**登记它）。
MDQ.fogSet = function(on, quiet)
  on = on and true or false
  SM_CFG.swmOverlay, SM_CFG.staleClean = on, on
  if not on then
    pcall(MDQ.shutdown, "关闭世界迷雾")     -- 一次性收层 + 还原复用池位 + 藏过的原生层全部还回
    pcall(MDQ.staleShowAll, "关闭世界迷雾")
  else
    MDQ.offDone = false                     -- 下次闸门判定不再走「已关」那条早退路
    pcall(MDQ.staleForget, "世界迷雾已开")  -- 残留清理的账**只清不还**（可见性归接管守护）
  end
  -- ★★★1.75.57b（用户：「开关状态是否能正确关闭,节拍停止.图层清理操作」）：
  --   **关 ⇒ 真摘节拍**（不是靠每帧早退；图层清理已在上面同步做完）
  --   **开 ⇒ 重新挂上**（开回来立刻就有节拍，不用等 /reload）
  -- ★1.75.59c：这一段的唯一实现搬到 `MDQ.beatSync()`（载入期也要用同一份 ⇒ 一处真值）
  if type(MDQ.beatSync) == "function" then pcall(MDQ.beatSync) end
  if not quiet then
    if on then
      say("世界迷雾 = 开（本图整张由 S_WorldMap 表渲染 + 残留图层清理；节拍已启动）")
      say("　" .. L("TB_SM_SWM_TIP1"))
    else
      say("世界迷雾 = 关（**节拍已停**；我们补建的层已收起、复用过的池位已还原原贴图/几何、藏过的原生层已全部还回）")
    end
    -- ★★★1.75.59c（用户：「缩放大地图/关闭世界迷雾.开关状态切换都要提示用户reload操作.」）：
    --   **切换完弹通用「需要 /reload」确认窗**（Core.lua 的 `EVAL_RELOAD_ASK` = 全项目唯一实现）；
    --   老核心没有这个口 ⇒ 退回一行如实播报（绝不静默、也绝不假装已经生效）。
    local ask = rawget(_G, "EVAL_RELOAD_ASK")
    local stateTxt = L(on and "DH_ON" or "DH_OFF")
    if type(ask) == "function" then
      pcall(ask, L("REL_ASK_TITLE_FOG"), L("REL_ASK_BODY_FOG", stateTxt))
    else
      say("　" .. L("REL_ASK_BODY_FOG", stateTxt))
    end
  end
  return true
end

-- ============ ★★★1.75.59o：**世界迷雾贴图 · 本游戏专属坐标补偿**（编辑模式 · 每块单独拖）============
-- 用户要求（原话四段）：
--   ①「能否在隐藏世界迷雾->设置->开启编辑模式.这个状态下.添加的图层可以拖拽移动,现在高亮边框,
--      然后拖拽完成之后记录用户数据.这个数据到时候你这边读取.可以只更新到基础世界迷雾数据坐标数据?」
--   ②「拖拽完成的数据记录微调偏移量要和当前地图的缩放.配对存储.解析的方便坐标转化」
--   ③「作为一个当前这个游戏特定的某些区域图层的特定偏移量补偿」
--   ④「最终坐标解析要和 MapOverlayData.lua 配对使用.给这个游戏的世界迷雾贴图纹理专属坐标偏移补偿」
-- ⇒ 本功能 = **一张与 `MapOverlayData.lua` 配对使用的「本游戏专属补偿表」**。为什么需要（在案事实，1.75.51 起）：
--   本客户端的地图内容与上游 S_WorldMap 表**不同源**（`Barrens` 的 `WorldMapOverlay1` = 125x115 @492,63
--   与表里该图 26 区 / 84 块**一块都不吻合**）⇒ 逐块手拖微调，把「表值 + 补偿」当作这张图真正的坐标数据。
--
-- ★★★四条判据（**改这里之前先读完**）：
--   ① **最终坐标 = 基础表 + 补偿**，配对只有**一个出口** `MDQ.editFinal`：
--        基础 = `MapOverlayData.lua` 的 `{宽,高,offsetX,offsetY}`（`MDQ.areaOf` 取、`MDQ.expectRect` 切块）
--        补偿 = `worldFogCfg.edit[地图][区域#块号]`（编辑模式拖出来的**表口径**偏移）
--        最终写进客户端 = `((offsetX + x) * k, -((offsetY + y) * k))`
--      ★**对不上就不套**：基础表里没有这个 (区域, 块号)（表被重生 / 区名改了 / 手改了存档）⇒
--        这条补偿**不生效**，并把「孤儿条数」如实报出来（本项目铁律「拿不到证据就不动手」——
--        绝不把一条孤儿补偿硬加到别的块上）。
--   ② **每块单独拖**（用户选定）：拖的是**我们自己画的那一块**，只改它自己的补偿量，别的块一个字节不动。
--   ③ **补偿量与「当时的缩放」配对存**（用户指定）—— 屏幕位移 → 表口径要**两个系数**，缺一个就换不回来：
--        · 我们写进客户端的是**逻辑值** = 表值 × k（k = `MDQ.kLive` 现读倍率；`MDQ.lastK` = 这一拍真正用的那个）；
--        · 屏幕上真正走的距离 = 逻辑位移 × **外框链有效缩放** es。
--      ⇒ **Δ表 = Δ屏幕 / (k × es)**（反过来 **Δ屏幕 = Δ表 × k × es**）。
--      ⇒ 每条记录都带 `k` / `es` / `coef` / **原始屏幕位移** `sx,sy` / 来源 `src` ⇒ 我读到存档就能**双向换算**
--        （用户要的「解析的方便坐标转化」）；★**渲染只用表口径 `x,y`** ⇒ 缩放无关（换缩放级别依然对）。
--      ★es 一律**当场实测**（`屏测宽 ÷ 逻辑宽`），读不出才退回桥 `EVAL_SM_EFFSCALE`，并**在记录里标明来源**
--        （本项目「位移一律按屏幕算 + 实测系数反解，不猜单位」，范式 = `DragFrames` 的 `dfPlaceFrom`/`dfDragUpdate`）。
--      ★★同时存**拖拽当时的基础表值** `bx/by/bw/bh` ⇒ 将来基础表被重新生成时，能一眼判出「这条补偿是按旧表拖的」
--        （配对基准，不是一个孤零零的数字）。
--   ④ **只改坐标**：贴图 / UV / 宽高一律不碰（用户：「只更新到基础世界迷雾数据坐标数据」）；
--      `MapOverlayData.lua` 是**生成物**（手改会被下次生成冲掉）⇒ 用户数据只进存档，**绝不写回那张表**。
--   ★1.75.60d：**第二层 = 独立偏移量数据库 `MapOverlayOffset.lua`**（用户：「偏移量文件需要独立存储,
--      配合以上数据库使用…整合到作为插件的基础数据,插件是给其他人使用的他们就能看到正确的矫正过的贴图了」）——
--      同为**生成物**（`node gen_mapoffset.js` 从存档导出）；生效次序 **存档 > 文件 > 无**；
--      详见下面 `MDQ.editFileTbl` 那段的三条口径。
--
-- 存哪儿：`worldFogCfg.edit[地图][区域#块号] = { x, y, bx, by, bw, bh, k, es, coef, src, sx, sy, t }`
--   · `x,y`        = **表口径补偿**（像素；**正 x 向右 / 正 y 向下**，与表的 offsetX/offsetY **同口径同符号**）
--   · `bx,by,bw,bh`= 拖拽当时该块在 `MapOverlayData.lua` 里的**表值**（配对基准）
--   · `sx,sy`      = 拖拽当时的**屏幕位移原始值**（`GetCursorPosition` 口径：正 x 向右 / 正 y 向上）
--   · `k,es,coef`  = 当时的三个系数（`coef = k × es`）；`src` = es 的来源；`t` = 时间戳
-- 入口：工具箱「关闭世界迷雾」那一行的 `[设置]` 下拉第二项「编辑模式」；
--   命令 `/ehm mapfit 编辑 [on|off|配对|清|清全部]`（等价入口，同一个写口 `MDQ.editSet`）。
-- 关断（项目「关断四件事」）：关编辑模式 ⇒ **柄全部收起 + 拖拽当场结束 + 节拍按需真摘**；
--   补偿数据**保留**（那是用户的数据，不是会话状态）；另有 `编辑 清` / `编辑 清全部` 两条显式清理路。
MDQ.EDIT_LOG_MAX = 40    -- 「补偿记了什么」的**有界落盘环**上限（`worldFogCfg.editLog`，最新在前）
MDQ.EDIT_MAX = 1200      -- 补偿表条数上限（表本身最多 1019 块，这道门只防病态存档）

-- 补偿表读写（**唯一入口**；别在别处直接碰 `SM_CFG.edit`）
-- ★★★1.75.64：**图层类型（区域彩图 / 区域实景）的唯一写口** —— 工具箱 `[设置]` 单选 / 命令都走它。
--   ★★★切换 = 一次「关断四件事」（本项目 §4.1 那把尺子），缺一件就是「看着切了、实际还在跑/还占资源」：
--     ① **资源回收 + ④ 图层清理**：**先 `MDQ.release`** —— 收我们自建的层 + 按原值账还回复用的客户端池位
--        （贴图/UV/宽高/锚点/显隐/alpha/**绘制层**七样）+ 把守护藏过的客户端原生层全部 `Show` 还回。
--        ★★**顺序铁律：先还、再换真值** —— 反过来的话还回那一步已经按新模式的账在走，会漏还（残留压住新层）。
--     ② **数据重置**：编辑模式的**会话态**全部清零（选中集 / 逐块隐藏 / 悬停 / 关联闪光 / 图层池账 /
--        每图一次播报闸 / 收尾门）⇒ 下次打开从零开始，不带着上一套的半状态跑。
--        ★**补偿数据不在此列**（那是用户的数据，模式各有各的根：`edit` / `editJpg`，切换一个字都不动）。
--     ③ **不新增常驻**：节拍由既有 `beatSync` 按需管（切完这一拍该挂就挂、该摘就摘），本函数**不建帧、不挂脚本**。
--     ④ **立刻刷一拍**（`editViewApply` = 与正常节流同一路：quiet + silent + withGuard）⇒ **切换当场生效、不用 /reload**。
--   返回：是否真的切了, 现模式
MDQ.layerSet = function(mode, quiet)
  local want = (mode == MDQ.LAYER_JPG) and MDQ.LAYER_JPG or MDQ.LAYER_ART
  local cur = MDQ.layerMode()
  if want == cur then
    if not quiet then
      say("世界迷雾·图层类型已经是「" .. ((want == MDQ.LAYER_JPG) and "区域实景" or "区域彩图") .. "」（没有变化）")
    end
    return false, cur
  end
  pcall(MDQ.release, "切换图层类型（" .. tostring(cur) .. " → " .. tostring(want) .. "）")
  MDQ.sel, MDQ.blkHide = {}, {}
  MDQ.hoverIdx, MDQ.flashIdx, MDQ.flashAt = nil, nil, 0
  MDQ.slot, MDQ.lastRender, MDQ.lastRenderN = {}, nil, 0
  MDQ.saidMk, MDQ.offDone = nil, false
  SM_CFG.layerMode = want
  pcall(MDQ.editViewApply)
  if type(MDQ.beatSync) == "function" then pcall(MDQ.beatSync) end
  if not quiet then
    if want == MDQ.LAYER_JPG then
      say("世界迷雾·图层类型 = **区域实景**：整区一张 `media\\WorldMapJpg\\<图>.jpg`（地形实拍），"
        .. "在本组内**优先级最高**（写 `OVERLAY` 绘制层 ⇒ 遮盖其它层）。")
      say("　★补偿数据换到 `worldFogCfg.editJpg`（彩图那份在 `worldFogCfg.edit`，两套互不影响）；"
        .. "编辑模式照旧可拖拽/箭头/改尺寸，列表里只有「整区一张」这一行。")
    else
      say("世界迷雾·图层类型 = **区域彩图**：按 `MapOverlayData.lua` 逐区域/逐块贴 `media\\WorldMap\\…`（游戏世界地图那张手绘图）。")
      say("　★补偿数据在 `worldFogCfg.edit`；实景那份（`worldFogCfg.editJpg`）原样留着，切回去接着用。")
    end
  end
  return true, want
end

-- ★★★1.75.64：**存档根的按模式分派（唯一分派点）** —— 彩图 = `worldFogCfg.edit`、实景 = `worldFogCfg.editJpg`。
--   为什么只改这两个口就够：编辑模式那一整族（拖拽 `editTick` / 箭头 `nudge` / 尺寸 `sizeStep` /
--   列表 `editLines` / 归零 `zeroOne` / 重置 `editClear`/`editResetPlugin` / 体检 `editJoin` / 渲染配对 `editRec`）
--   **全部**只经由 `editTbl` + `editFileTbl` 两个口拿存储 ⇒ 换根即换套，**两套数据永不串味**
--   （键形态也一字未改：仍是 `区域#块号`，实景那套的伪区域 = `MDQ.JPG_AREA`）。
MDQ.EDIT_ROOT_ART, MDQ.EDIT_ROOT_JPG = "edit", "editJpg"
MDQ.editTbl = function(make)
  if type(SM_CFG) ~= "table" then return nil end
  local key = MDQ.jpgMode() and MDQ.EDIT_ROOT_JPG or MDQ.EDIT_ROOT_ART
  local t = SM_CFG[key]
  if type(t) ~= "table" then
    if not make then return nil end
    t = {}
    SM_CFG[key] = t
  end
  return t
end

-- 记录键 = `区域#块号`（★解析一律按**最后一个** `#` 切，区域名里万一有 `#` 也不会错位）
MDQ.editRowKey = function(a, t) return tostring(a) .. "#" .. tostring(t) end

-- 本图那一层子表（`make` = 没有就建）—— ★图名大小写不敏感（客户端拼写可能与基础表不同，见 `MDQ.keyOfMap`）
MDQ.editMap = function(file, make)
  local all = MDQ.editTbl(make)
  if all == nil then return nil end
  local key = tostring(file or "")
  if key == "" then return nil end
  local per = all[key]
  if type(per) == "table" then return per end
  return MDQ.keyOfMap(all, key, make)
end

-- ============ ★★★1.75.60d：**独立偏移量数据库** `MapOverlayOffset.lua`（与 `MapOverlayData.lua` 配对使用）============
-- 用户定案：「我微调的数据储存为独立偏移量数据库.然后整合到作为插件的基础数据.
--   插件是给其他人使用的他们就能看到正确的矫正过的贴图了」+「MapOverlayData.lua 偏移量文件需要独立存储,
--   配合以上数据库使用」⇒ 微调的数据流 = ① 编辑模式拖拽 → 存档 `worldFogCfg.edit`（本机的、活的增量）；
--   ② `node gen_mapoffset.js` 把存档烘成 **`MapOverlayOffset.lua`**（**生成物**，进 toc、随插件发货 ⇒
--   别的玩家开箱就是矫正好的贴图）；③ 运行时**两层一起生效**。
-- ★★★三条口径（改这里之前先读完）：
--   ① **逐键生效次序：存档 > 文件 > 无** —— 存档 = 烘完之后又拖的增量，永远压过文件基线；
--      客户端**没有文件写 API** ⇒ 文件在游戏内是只读的，活数据永远只进存档。
--   ② **所有「清」（归零 / 重置本图 / 重置全部）都只清存档 ⇒ 回落到文件基线** —— 清文件只能重生生成器
--      （`node gen_mapoffset.js`）；★**「拖回原点」是唯一例外**：文件基线上有值时**显式写 `{x=0,y=0}` 压住文件**
--      （直接删存档会回落到文件值，不是回原点 —— 见 `MDQ.editEnd`）。
--   ③ **文件也是生成物**（手改会被下次导出冲掉）⇒ 与 `MapOverlayData.lua` 同纪律：运行时只读、`rawget` 懒读。
-- ★1.75.64：**按图层类型选文件基线**（彩图 = `MapOverlayOffset.lua`、实景 = `MapOverlayOffsetJPG.lua`）
--   —— 与 `MDQ.editTbl` 同一个分派口径（两处必须一致，否则「存档读 A、文件读 B」= 补偿串味）。
MDQ.editFileTbl = function()
  local nm = MDQ.jpgMode() and "EVAL_MAP_OVERLAY_OFFSET_JPG" or "EVAL_MAP_OVERLAY_OFFSET"
  local t = rawget(_G, nm)
  if type(t) ~= "table" then return nil end
  return t
end

-- ★★★1.75.60x：**地图名大小写不敏感的唯一助手**（偏移库两层共用；与 `MDQ.areaOf` 查基础表的口径一致）
--   为什么必须有：**客户端报的图名拼写与上游基础表不一定相同** —— 真机实测编辑记录里是
--   `BadLands` / `Blastedlands` / `HinterLands`，而 `MapOverlayData.lua` 里是
--   `Badlands` / `BlastedLands` / `Hinterlands` ⇒ 只按精确键查会**静默取不到补偿**（46 条）。
--   口径：① 精确命中优先（绝大多数情况，零开销）；② 否则逐键比**小写**，命中后把这次配对记进缓存
--   （下次直接命中，不每拍扫表）；③ 缓存命中也要复核值还在（表被换掉/键被删 ⇒ 自愈清缓存）；
--   ④ `make` = 都没有就用**原键**新建（保持调用方的拼写，与存档既有键永不重名打架）。
MDQ.keyOfMap = function(t, want, make)
  if type(t) ~= "table" or type(want) ~= "string" or want == "" then return nil end
  local hit = t[want]
  if type(hit) == "table" then return hit end
  local low = want:lower()
  local cache = MDQ.mapKeyHit
  if cache == nil then cache = {} MDQ.mapKeyHit = cache end
  local ck = cache[low]
  if ck ~= nil then
    local v = t[ck]
    if type(v) == "table" then return v end
    cache[low] = nil              -- 键没了/表换了 ⇒ 自愈，重新扫一次
  end
  for k, v in pairs(t) do
    if type(k) == "string" and type(v) == "table" and k:lower() == low then
      cache[low] = k
      return v
    end
  end
  if not make then return nil end
  local nt = {}
  t[want] = nt
  cache[low] = want
  return nt
end

-- 文件里本图那一层（`EVAL_MAP_OVERLAY_OFFSET[地图]`；读不到 ⇒ nil）—— ★图名大小写不敏感（见 `MDQ.keyOfMap`）
MDQ.editFileMap = function(file)
  local t = MDQ.editFileTbl()
  if t == nil or type(file) ~= "string" or file == "" then return nil end
  local m = t[file]
  if type(m) == "table" then return m end
  return MDQ.keyOfMap(t, file, false)
end

-- 文件里的某一条（`[区域][块号]`，形态 = `{ x, y, bx, by, bw, bh }`；没有 ⇒ nil）
MDQ.editFileRec = function(file, a, t)
  local m = MDQ.editFileMap(file)
  if m == nil then return nil end
  local ar = m[a]
  if type(ar) ~= "table" then return nil end
  local r = ar[tonumber(t)]
  if type(r) ~= "table" then return nil end
  return r
end

-- 文件层条数：本图, 全部（跳过 {0,0} —— 那不是偏移，生成器本来就不写，这里只兜底）
MDQ.editFileCount = function(file)
  local function oneMap(f)
    local m = MDQ.editFileMap(f)
    local n = 0
    if m ~= nil then
      for _, sub in pairs(m) do
        if type(sub) == "table" then
          for _, r in pairs(sub) do
            local x = (type(r) == "table") and tonumber(r.x) or nil
            local y = (type(r) == "table") and tonumber(r.y) or nil
            if x ~= nil and y ~= nil and (x ~= 0 or y ~= 0) then n = n + 1 end
          end
        end
      end
    end
    return n
  end
  local mine = oneMap(file)
  local tot = 0
  local t = MDQ.editFileTbl()
  if t ~= nil then for f in pairs(t) do tot = tot + oneMap(f) end end
  return mine, tot
end

MDQ.editRec = function(file, a, t)
  -- ★1.75.60d：**存档优先**：存档里有这条 ⇒ 用存档的（用户后来又拖的增量永远压过文件基线）；
  --   存档没有 ⇒ 回落到**独立偏移量数据库**（文件基线）。
  local per = MDQ.editMap(file, false)
  if per ~= nil then
    local r = per[MDQ.editRowKey(a, t)]
    if type(r) == "table" then return r end
  end
  return MDQ.editFileRec(file, a, t)
end

MDQ.editTotal = function()
  local all = MDQ.editTbl(false)
  local n = 0
  if type(all) == "table" then
    for _, sub in pairs(all) do
      if type(sub) == "table" then for _ in pairs(sub) do n = n + 1 end end
    end
  end
  return n
end

-- 写一条（**唯一写口**）。返回 true = 落表成功
MDQ.editPut = function(file, a, t, rec)
  if type(rec) ~= "table" then return false end
  local per = MDQ.editMap(file, true)
  if per == nil then return false end
  local key = MDQ.editRowKey(a, t)
  if per[key] == nil and MDQ.editTotal() >= (tonumber(MDQ.EDIT_MAX) or 1200) then
    pcall(say, "世界迷雾·编辑：补偿表已达上限 " .. tostring(MDQ.EDIT_MAX)
      .. " 条 ⇒ 这一块**没有记下**（先用「编辑 清」清掉一些再拖）")
    return false
  end
  per[key] = rec
  return true
end

-- ★★★1.75.60q（真机报障：「迷雾贴图列表.在修改,宽,高之后.再点击位移微调箭头.会将宽高设置还原丢失」）：
--   **两个写口必须互相带上对方那一家族的字段** —— 位置微调（箭头 `nudge` / 拖拽 `editTick`）写记录时
--   若不把尺寸补偿 `dw/dh` 带上，`editPut` 就是**整条覆盖** ⇒ 尺寸被无声冲掉（反过来 `sizeStep` 早在带 `x/y` 了，
--   这一条是那条规则**对称的另一半** —— 1.75.60o 只做了半边）。
--   ★**只在非 0 时才写**这两个字段：0 = 没有尺寸补偿 ⇒ 不写（免得给生成物灌 `dw=0` 噪声、
--     让每次 `gen_mapoffset.js` 都报全员「更新」）。
MDQ.editCarrySize = function(put, rec)
  if type(put) ~= "table" then return put end
  local dw = tonumber(rec and rec.dw) or 0
  local dh = tonumber(rec and rec.dh) or 0
  if dw ~= 0 or dh ~= 0 then
    put.dw, put.dh = dw, dh
    put.sw = tonumber(rec and rec.sw) or 0
    put.sh = tonumber(rec and rec.sh) or 0
  end
  return put
end

MDQ.editDel = function(file, a, t)
  local per = MDQ.editMap(file, false)
  if per == nil then return false end
  local key = MDQ.editRowKey(a, t)
  if per[key] == nil then return false end
  per[key] = nil
  return true
end

-- ★★★1.75.60m（用户：「迷雾贴图重置也能重置**插件的偏移量**，不单是用户自定义的偏移量；（单）项重置也要支持」）：
--   「重置到**原始表值**」= 连**插件偏移量数据库**（`MapOverlayOffset.lua`）那一条一起压掉。
--   ★为什么只能这么写：客户端**没有文件写 API** ⇒ 文件在游戏内是**只读**的 ⇒ 唯一手段 = **存档里写显式 `{x=0,y=0}` 影**
--     （已有机制，1.75.60d：`editRec` 存档优先、`editIndex` 会把文件那条一起摘掉 ⇒ 这一块回 `MapOverlayData.lua` **原始表值**）。
--   ★**可逆**：普通「重置」（只清存档）会把这条影删掉 ⇒ 又**回落插件基线**。
--   ★**一个顺带的好事（如实告知）**：`gen_mapoffset.js` 的合并语义里 **0 影 = 从库里删除** ⇒ 在游戏里这么重置过之后，
--     跑一次导出就**真的把这几条从 `MapOverlayOffset.lua` 里删掉**（发布给别人的那份也干净）。
MDQ.editShadowPut = function(file, a, t, tag)
  if file == nil or tostring(file) == "" then return false end
  local fr = MDQ.editFileRec(file, a, t)
  local bx, by, bw, bh = nil, nil, nil, nil
  if fr ~= nil then
    bx, by = tonumber(fr.bx), tonumber(fr.by)
    bw, bh = tonumber(fr.bw), tonumber(fr.bh)
  end
  return MDQ.editPut(file, a, t, {
    x = 0, y = 0, bx = bx, by = by, bw = bw, bh = bh,
    k = 1, es = 1, coef = 1, src = tostring(tag or "重置（含插件基线）"),
    sx = 0, sy = 0, t = (date and tostring(date("%m-%d %H:%M:%S")) or "?"),
  })
end

-- ★1.75.60m：**批量把「插件偏移量基线」也重置**（本图 / 全部地图）—— 逐条写 0 影（唯一写口 = `editShadowPut`）。
--   ★只遍历**文件基线**那张表（与「本拍画了几块」无关 ⇒ 连当前没画出来的条目也一起清干净，口径一致）。
--   返回：压掉几条, 涉及几张图
MDQ.editResetPlugin = function(file)
  local maps = {}
  if type(file) == "string" and file ~= "" then
    maps[file] = true
  else
    local ft = MDQ.editFileTbl()
    if type(ft) == "table" then for f in pairs(ft) do maps[f] = true end end
  end
  local n, nm = 0, 0
  for f in pairs(maps) do
    local fm = MDQ.editFileMap(f)
    if type(fm) == "table" then
      local hit = 0
      for area, sub in pairs(fm) do
        if type(sub) == "table" then
          for ti in pairs(sub) do
            if MDQ.editShadowPut(f, area, ti, "重置插件基线") then n = n + 1 hit = hit + 1 end
          end
        end
      end
      if hit > 0 then nm = nm + 1 end
    end
  end
  return n, nm
end
-- 返回：本图条数, 全部条数
-- ★1.75.60d：口径 = **现存的补偿记录** = 存档 ∪ 文件（逐键去重）；★显式 `{0,0}` 影（拖回原点压文件）
--   不算（它就是「回原始表值」的意思，连文件那条一起压掉）；★**孤儿照算**（它**存在**但**不生效** ——
--   孤儿由 `MDQ.editJoin` 配对体检单独报，别拿这个数当「生效条数」用）。
MDQ.editCount = function(file)
  local function oneMap(f)
    local n, seen, zero = 0, {}, {}
    local per = MDQ.editMap(f, false)
    if per ~= nil then
      for key, r in pairs(per) do
        local x = (type(r) == "table") and tonumber(r.x) or nil
        local y = (type(r) == "table") and tonumber(r.y) or nil
        if x ~= nil and y ~= nil then
          if x == 0 and y == 0 then zero[key] = true
          elseif seen[key] == nil then seen[key] = true n = n + 1 end
        end
      end
    end
    local fm = MDQ.editFileMap(f)
    if fm ~= nil then
      for a, sub in pairs(fm) do
        if type(sub) == "table" then
          for ti, r in pairs(sub) do
            local key = tostring(a) .. "#" .. tostring(ti)
            local x = (type(r) == "table") and tonumber(r.x) or nil
            local y = (type(r) == "table") and tonumber(r.y) or nil
            if x ~= nil and y ~= nil and (x ~= 0 or y ~= 0)
              and zero[key] ~= true and seen[key] == nil then
              seen[key] = true n = n + 1
            end
          end
        end
      end
    end
    return n
  end
  local mine = oneMap(file)
  local tot = 0
  local maps = {}
  local ft = MDQ.editFileTbl()
  if ft ~= nil then for f in pairs(ft) do maps[f] = true end end
  local all = MDQ.editTbl(false)
  if type(all) == "table" then for f in pairs(all) do maps[f] = true end end
  for f in pairs(maps) do tot = tot + oneMap(f) end
  return mine, tot
end

-- ★1.75.60d：只数**存档**里的（**重置预览**用：「会清掉本图 N 条」—— 会被清掉的是存档，
--   文件基线（`MapOverlayOffset.lua`）在游戏内是只读的，重置动不到它 ⇒ 预告不许把它数进去）。
MDQ.editSaveCount = function(file)
  local all = MDQ.editTbl(false)
  local tot, mine = 0, 0
  if type(all) == "table" then
    local want = tostring(file or "")
    for mk, sub in pairs(all) do
      if type(sub) == "table" then
        for _ in pairs(sub) do
          tot = tot + 1
          if tostring(mk) == want then mine = mine + 1 end
        end
      end
    end
  end
  return mine, tot
end

-- 清：`file` 有值 ⇒ 只清本图；nil / 空串 ⇒ 清**全部**。返回 清了 N 条
MDQ.editClear = function(file)
  local all = MDQ.editTbl(false)
  if type(all) ~= "table" then return 0 end
  if file == nil or tostring(file) == "" then
    local n = MDQ.editTotal()
    SM_CFG.edit = {}
    return n
  end
  local per = all[tostring(file)]
  if type(per) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(per) do n = n + 1 end
  all[tostring(file)] = nil
  return n
end

-- ★★★配对唯一出口：**最终坐标 = 基础表 + 补偿**。
--   `ox, oy` = 基础表值（`MDQ.expectRect` 出来的表口径 offset）；`off` = 补偿记录（可 nil）
--   返回 最终 offsetX, 最终 offsetY, 是否套上了补偿
MDQ.editFinal = function(ox, oy, off)
  local bx, by = tonumber(ox), tonumber(oy)
  if bx == nil or by == nil then return ox, oy, false end
  if type(off) ~= "table" then return bx, by, false end
  local x, y = tonumber(off.x), tonumber(off.y)
  if x == nil or y == nil then return bx, by, false end
  return bx + x, by + y, true
end

-- ★★★1.75.60o：**最终尺寸 = 基础表块尺寸 + 尺寸补偿**（与 `editFinal` 完全对称的第二个出口）。
--   `w0, h0` = `MDQ.expectRect` 出来的**块**表口径尺寸；`off` = 补偿记录（可 nil）
--   返回 最终宽, 最终高（**永远**给得出值：没有补偿 / 字段缺失 ⇒ 原样返回表值）
--   ★上下限收在 `editSize` 一处（两端都走它 ⇒ 写进去的和渲染出来的不可能不一致）：
--     `MDQ.SIZE_MIN`(2) / `MDQ.SIZE_MAX`(4096) 表像素 —— 超出就夹，绝不把一块调成 0 或负数。
MDQ.editSize = function(w0, h0, off)
  local bw, bh = tonumber(w0), tonumber(h0)
  if bw == nil or bh == nil then return w0, h0 end
  local dw, dh = 0, 0
  if type(off) == "table" then
    dw = tonumber(off.dw) or 0
    dh = tonumber(off.dh) or 0
  end
  local fw, fh = bw + dw, bh + dh
  local lo, hi = tonumber(MDQ.SIZE_MIN) or 2, tonumber(MDQ.SIZE_MAX) or 4096
  if fw < lo then fw = lo end
  if fh < lo then fh = lo end
  if fw > hi then fw = hi end
  if fh > hi then fh = hi end
  return fw, fh
end

-- 渲染侧索引：`{ [区域] = { [块号] = {x,y} } }` —— **没有补偿就返回 nil**（稳态渲染路径零开销）
-- ★1.75.60d：**两层合并** = ① 文件基线（`MapOverlayOffset.lua`）铺底；② 存档覆盖 ——
--   存档有这条 ⇒ 压过文件（含 **`{0,0}` = 显式「回原始表值」**：把文件基线那条也一起摘掉）。
MDQ.editIndex = function(file)
  local out, any = nil, false
  local fm = MDQ.editFileMap(file)
  if fm ~= nil then
    for a, sub in pairs(fm) do
      if type(sub) == "table" then
        for ti, r in pairs(sub) do
          local tn = tonumber(ti)
          local x = (type(r) == "table") and tonumber(r.x) or nil
          local y = (type(r) == "table") and tonumber(r.y) or nil
          local dw = (type(r) == "table") and (tonumber(r.dw) or 0) or 0
          local dh = (type(r) == "table") and (tonumber(r.dh) or 0) or 0
          -- ★1.75.60o：**尺寸补偿也算「这一条有东西」**（只有尺寸、位置为 0 的记录必须进索引，
          --   否则「只调宽高」的补偿会被静默丢掉 —— 那是这一族最容易漏的一处）
          if tn ~= nil and x ~= nil and y ~= nil
            and (x ~= 0 or y ~= 0 or dw ~= 0 or dh ~= 0) then
            if out == nil then out = {} end
            local s2 = out[a]
            if s2 == nil then s2 = {} out[a] = s2 end
            s2[tn] = { x = x, y = y, dw = dw, dh = dh }
            any = true
          end
        end
      end
    end
  end
  local per = MDQ.editMap(file, false)
  if per ~= nil then
    for key, r in pairs(per) do
      if type(r) == "table" then
        local a, tn = string.match(tostring(key), "^(.-)#(%d+)$")
        local ti = tonumber(tn)
        local x, y = tonumber(r.x), tonumber(r.y)
        local dw, dh = tonumber(r.dw) or 0, tonumber(r.dh) or 0
        if a ~= nil and ti ~= nil and x ~= nil and y ~= nil then
          -- ★1.75.60o：位置与尺寸**都**为 0 才叫「0 影」（回原始表值）；只有尺寸非 0 的记录是**有效补偿**
          if x ~= 0 or y ~= 0 or dw ~= 0 or dh ~= 0 then
            if out == nil then out = {} end
            local s2 = out[a]
            if s2 == nil then s2 = {} out[a] = s2 end
            s2[ti] = { x = x, y = y, dw = dw, dh = dh }
            any = true
          elseif out ~= nil and out[a] ~= nil then
            out[a][ti] = nil    -- ★显式 0 影：压掉文件基线（这一块 = 原始表值，不是文件值）
          end
        end
      end
    end
  end
  if not any then return nil end
  return out
end

-- ★★配对体检：逐条拿补偿去 `MapOverlayData.lua` 里查 (区域, 块号) ——
--   命中 / 孤儿（基础表里没有 ⇒ **不生效**）/ 基础表已变（`bx/by` 与现值不符 ⇒ 这条是按旧表拖的）
--   ★1.75.60d：体检范围 = **两层并集**（存档优先；显式 `{0,0}` 影 = 「回原始表值」⇒ 不算补偿、不参与配对），
--     每条带来源标签（**存档** / **文件** = 独立偏移量数据库 `MapOverlayOffset.lua`）。
--   返回 表 { hit=, orphan=, drifted=, n=, items={ "…" } }
MDQ.editJoin = function(file)
  local res = { hit = 0, orphan = 0, drifted = 0, n = 0, items = {} }
  local m = MDQ.areaOf(file)
  local keys = {}
  local per = MDQ.editMap(file, false)
  if per ~= nil then
    for key, r in pairs(per) do
      local x = (type(r) == "table") and tonumber(r.x) or nil
      local y = (type(r) == "table") and tonumber(r.y) or nil
      if x ~= nil and y ~= nil and (x ~= 0 or y ~= 0) then
        keys[key] = { r = r, src = "存档" }
      end
    end
  end
  local fm = MDQ.editFileMap(file)
  if fm ~= nil then
    for a, sub in pairs(fm) do
      if type(sub) == "table" then
        for ti, r in pairs(sub) do
          local key = tostring(a) .. "#" .. tostring(ti)
          if keys[key] == nil and type(r) == "table" then
            local x, y = tonumber(r.x), tonumber(r.y)
            if x ~= nil and y ~= nil and (x ~= 0 or y ~= 0) then
              keys[key] = { r = r, src = "文件" }
            end
          end
        end
      end
    end
  end
  for key, it in pairs(keys) do
    local r = it.r
    res.n = res.n + 1
    local a, tn = string.match(tostring(key), "^(.-)#(%d+)$")
    local ti = tonumber(tn)
    local base = (type(m) == "table" and a ~= nil) and m[a] or nil
    local bw, bh, bx, by = nil, nil, nil, nil
    if base ~= nil and ti ~= nil then bw, bh, bx, by = MDQ.expectRect(base, ti) end
    if bx == nil then
      res.orphan = res.orphan + 1
      if table.getn(res.items) < 12 then
        table.insert(res.items, string.format("　**孤儿**[%s] %s（基础表里查不到这一块 ⇒ 本条**不生效**）", it.src, tostring(key)))
      end
    else
      res.hit = res.hit + 1
      local obx, oby = tonumber(r.bx), tonumber(r.by)
      local drift = (obx ~= nil and math.abs(obx - bx) > 0.5) or (oby ~= nil and math.abs(oby - by) > 0.5)
      if drift then
        res.drifted = res.drifted + 1
        if table.getn(res.items) < 12 then
          table.insert(res.items, string.format("　**基础表已变**[%s] %s：调时表值 %s,%s ⇒ 现在 %s,%s（补偿仍按上面那条叠加）",
            it.src, tostring(key), tostring(obx), tostring(oby), tostring(bx), tostring(by)))
        end
      end
      if table.getn(res.items) < 12 then
        -- ★1.75.60o：这条带尺寸补偿时一并摊开（「尺寸也是补偿」必须看得见）
        local jdw, jdh = tonumber(r.dw) or 0, tonumber(r.dh) or 0
        table.insert(res.items, string.format("　命中[%s] %s ｜ 表值 %s,%s + 补偿 x=%+.1f y=%+.1f ⇒ **最终 %+.1f,%+.1f**%s",
          it.src, tostring(key), tostring(bx), tostring(by), tonumber(r.x) or 0, tonumber(r.y) or 0,
          bx + (tonumber(r.x) or 0), by + (tonumber(r.y) or 0),
          ((math.abs(jdw) >= 0.05) or (math.abs(jdh) >= 0.05))
            and string.format(" ｜ **尺寸补偿 %+.1f×%+.1f**（表口径）", jdw, jdh) or ""))
      end
    end
  end
  return res
end

-- 取证环（**有界**，最新在前；与 `staleLog` 分开，互不挤占）
MDQ.editLogPut = function(line)
  if type(SM_CFG) ~= "table" then return 0 end
  local t = SM_CFG.editLog
  if type(t) ~= "table" then t = {} SM_CFG.editLog = t end
  table.insert(t, 1, string.format("[%s] %s", (date and tostring(date("%m-%d %H:%M:%S")) or "?"), tostring(line)))
  local max = tonumber(MDQ.EDIT_LOG_MAX) or 40
  while table.getn(t) > max do table.remove(t) end
  return table.getn(t)
end

MDQ.editLogN = function()
  local t = (type(SM_CFG) == "table") and SM_CFG.editLog or nil
  if type(t) ~= "table" then return 0 end
  return table.getn(t)
end

-- ===== 系数实测（★不猜单位）=====
--   拿**我们真正写过的那张**纹理读回「逻辑宽」与「屏幕矩形宽」⇒ 链系数 = 屏测 ÷ 逻辑；
--   读不出 ⇒ 退桥给的外框有效缩放（**并在记录里标明是估计**）；连它也读不到 ⇒ 按 1 并如实标注「判不出」。
--   ★为什么不用 `GetEffectiveScale`：本客户端那个口报的是**自身** scale 且滞后（1.75.9 已定案）。
MDQ.editMeasure = function()
  local chain, src = nil, nil
  local t = MDQ.lastTex
  if t ~= nil and type(t.GetWidth) == "function" and type(t.GetLeft) == "function" and type(t.GetRight) == "function" then
    local okw, w = pcall(t.GetWidth, t)
    local okl, l = pcall(t.GetLeft, t)
    local okr, r = pcall(t.GetRight, t)
    local lw = (okw and tonumber(w)) or nil
    local sw = nil
    if okl and okr and tonumber(l) and tonumber(r) then sw = tonumber(r) - tonumber(l) end
    if lw ~= nil and lw > 0.5 and sw ~= nil and sw > 0.5 then
      chain, src = sw / lw, "实测（屏测宽 ÷ 逻辑宽）"
    end
  end
  if chain == nil then
    local fr = _G["WorldMapDetailFrame"]
    if fr ~= nil then
      local ok, v = pcall(smEffScale, fr)
      if ok and tonumber(v) ~= nil and tonumber(v) > 0 then
        chain, src = tonumber(v), "桥给的外框有效缩放（实测读不到 ⇒ 估计）"
      end
    end
  end
  if chain == nil or chain <= 0 then chain, src = 1, "**判不出**（按 1 算，补偿量可能偏）" end
  return chain, src
end

-- 鼠标键从「处理体参数 a / b / 全局 arg1」三处取（★1.75.59b 真机教训：本客户端把参数放**全局 arg1**，
--   只读 a/b 会把右键当左键 ⇒ 同一个坑不许踩第二次）。前向声明：柄的闭包在后面才用到它。
local wfMouseBtn
wfMouseBtn = function(a, b)
  local v = a
  if type(v) ~= "string" or v == "" then v = b end
  if type(v) ~= "string" or v == "" then v = arg1 end
  if type(v) ~= "string" or v == "" then return nil end
  return v
end

-- ★1.75.59p：**用户点我们的界面 = 他主动问的** ⇒ 与敲命令同等待遇：盖章打开回显窗口（1.75.59f 的口径）。
--   不盖章的后果：配置里「调试日志」关着时，点了 [全选]/[重置本图] **聊天框一个字都没有** ——
--   用户分不清「点了没反应」与「点了生效但没提示」（最坏的一类静默）。
local function wfEcho()
  if type(GetTime) == "function" then
    WF_ECHO_AT = GetTime() + (tonumber(WF_ECHO_SEC) or 0.75)
  end
end

-- ===== 拖拽柄（**每一块一个**；按需建、跨图复用）=====
--   ★纹理与字体串都不吃鼠标事件（本项目 UI 配方第 9 条）⇒ 必须**盖一个透明 Button**。
--   ★柄绝不叫 `WorldMapOverlay*`（那是客户端池位族，会被接管守护当原生层藏掉）；
--     也不许与任何函数同名（组 54 老坑）⇒ 统一 `EVAL_WF_GRAB<n>`。
MDQ.grab = {}
MDQ.grabN = 0

-- ★★★1.75.60j（用户：「编辑模式 图层边框默认不要一直显示,**序号显示**.在获取焦点等情况下**等特定其他关联操作**
--   的时候边框才高亮显示」）：「**关联操作**」= 除了悬停之外，凡**点名到某一块**的操作都要把它亮一下（那一下就是反馈
--   「动的是这一块」）—— ① 点列表行前的红 × **归零这一条**；② 拖拽**松手**（光标已移开也还看得见刚才调的是哪块）。
--   ★用**时间戳**不用布尔标志（同 1.75.59f 的命令回显窗口）：到点自己过期，节拍下一拍就收起来 ⇒ 不会忘记清。
--   ★序号角标**不参与收起**（用户点名「序号显示」）：它常显，只有颜色跟着三态/隐藏态走。
MDQ.flashIdx, MDQ.flashAt = nil, 0
MDQ.focusFlash = function(i, sec)
  local n = tonumber(i) or 0
  if n <= 0 then return false end
  MDQ.flashIdx = n
  MDQ.flashAt = ((type(GetTime) == "function") and GetTime() or 0) + (tonumber(sec) or 1.4)
  pcall(MDQ.hoverPaint)          -- 立刻亮起来（不等下一拍）
  return true
end
MDQ.flashOn = function(i)
  local n = tonumber(i) or 0
  if n <= 0 or n ~= (tonumber(MDQ.flashIdx) or -1) then return false end
  local now = (type(GetTime) == "function") and GetTime() or 0
  return now < (tonumber(MDQ.flashAt) or 0)
end

-- ★1.75.60j：这个口原来「**只调整体透明度**」（常态 0.55 / 悬停 1.0）—— 与 1.75.60f 起的「颜色 + 显隐」口径重复，
--   而且会在边框已经收起来之后又把它写成半透明（＝默认一直显示一版的老视觉）。现在它 = **让这一块按当前状态重画一遍**
--   （显隐与颜色都交给唯一实现 `MDQ.grabColor`）⇒ 拖拽起/止那两个调用点靠它立刻点亮 / 复位，不再各写一套。
MDQ.grabHi = function(b, on)
  if b == nil then return false end
  local i = tonumber(b.gi) or 0
  local sg = MDQ.slot[i]
  if i > 0 and sg ~= nil then
    MDQ.grabColor(b, MDQ.selHas and MDQ.selHas(sg.area, sg.tile),
      (tonumber(MDQ.hoverIdx) or -1) == i, MDQ.blkHidden(sg.area, sg.tile))
  elseif type(b.eAll) == "table" then
    -- 没有画布账（极端情形）⇒ 至少按 `on` 决定显隐，绝不留下一个画错的框
    for _, e in ipairs(b.eAll) do
      if on then pcall(e.Show, e) else pcall(e.Hide, e) end
    end
  end
  -- ★拖拽时那个「实时偏移」小标签（`b.fs`，`editTick` 往里写 Δx/Δy）照旧：拖拽中 / 显式点亮才显示
  if b.fs ~= nil then
    if on or ((type(MDQ.dragSt) == "table") and (MDQ.dragSt.b == b)) then pcall(b.fs.Show, b.fs)
    else pcall(b.fs.Hide, b.fs) end
  end
  return true
end

-- ★1.75.59p：选中态的颜色 —— 金 = 未选（可拖），青 = **已选**（多选整组拖）
-- ★1.75.59q（用户：「列表单元鼠标悬浮.高亮对应纹理框颜色」）：加**悬停态** ——
--   鼠标停在某一行上 ⇒ 图上那一块的框换成**亮白黄 + 加粗**（一眼对上是哪一块）。
--   ★优先级：**拖拽中 > 悬停 > 已选 > 常态**（悬停是最新的意图，压过选中态；拖拽压过一切）。
-- ★1.75.60e：再加**隐藏态**（列表右键逐块藏）—— 柄照旧留着（藏了还要能点回来）。
-- ★★★1.75.60j（用户：「编辑模式 **图层边框默认不要一直显示**.在获取焦点等情况下高亮显示」）：
--   **边框默认一个都不画**（编辑模式下地图要干净）；拿到「焦点」才画出来 —— 焦点 = 悬停
--   （图上柄 / 序号角标 / 右侧列表行三处任一，共用 `MDQ.hoverIdx`）∨ 已选（列表多选）∨ 正在拖这一块。
--   ★显隐与颜色都只在这**一个口**里决定（`grabSyncAll` 每拍与 `hoverPaint` 悬停时都走它）⇒ 不会一处画一处不画；
--   ★柄（Button）**照旧一直 `EnableMouse`** —— 它是悬停与拖拽的抓手，收起的只是那 4 条**边框纹理**；
--   ★序号角标照旧常显（它是「列表 ↔ 图上」的对照物），颜色跟着同一套三态走；被逐块隐藏时角标画**灰**。
MDQ.grabColor = function(b, sel, hov, hid)
  if b == nil or type(b.eAll) ~= "table" then return false end
  local drag = (type(MDQ.dragSt) == "table") and (MDQ.dragSt.b == b)
  -- ★1.75.60j：「关联操作」的短暂高亮（红 × 归零 / 拖拽松手）也算焦点（到点自己过期）
  local flash = (MDQ.flashOn ~= nil) and (MDQ.flashOn(tonumber(b.gi) or 0) == true)
  local lit = (hov == true) or drag or flash              -- 「亮起来」的两种来源之一：焦点
  local vis = lit or (sel == true)                        -- 画不画框 = 亮起来 ∨ 已选
  -- ★颜色按**状态**给（不按画不画给）：常态金 / 已选青 / 焦点亮白黄 —— 序号角标常显，用的就是这一份色
  local r, g, bl = 1.00, 0.82, 0.25                       -- 常态：金
  if sel and not lit then r, g, bl = 0.35, 0.88, 1.00 end -- 已选（没在焦点）：青
  if lit then r, g, bl = 1.00, 1.00, 0.45 end             -- 焦点（悬停 / 拖拽中 / 关联操作）：亮白黄
  for _, e in ipairs(b.eAll) do
    pcall(e.SetVertexColor, e, r, g, bl)
    pcall(e.SetAlpha, e, 1.00)
    if vis then pcall(e.Show, e) else pcall(e.Hide, e) end
  end
  -- ★1.75.60c/60j：序号角标**常显**（颜色同一套三态；逐块隐藏的块画灰 ⇒ 排查时一眼看出「这块被藏了」）
  if b.idx ~= nil then
    if hid and not hov then pcall(b.idx.SetTextColor, b.idx, 0.50, 0.50, 0.50)
    else pcall(b.idx.SetTextColor, b.idx, r, g, bl) end
  end
  return true
end

-- ★1.75.59q：**悬停态只重画颜色/加粗**（不重排几何、不重画地图 —— 柄是现成的）⇒ 列表行
--   `OnEnter`/`OnLeave` 走它，悬停零额外开销。★1.75.60u 起**粗细恒定 1px**（状态只靠颜色：金 / 青 / 亮白黄）。
MDQ.hoverPaint = function()
  local cnt = tonumber(MDQ.lastRenderN) or 0
  local hov = tonumber(MDQ.hoverIdx) or -1
  for i = 1, cnt do
    local sg = MDQ.slot[i]
    local b = MDQ.grab[i]
    if sg ~= nil and b ~= nil then
      local on = (hov == i)
      MDQ.grabColor(b, MDQ.selHas and MDQ.selHas(sg.area, sg.tile), on, MDQ.blkHidden(sg.area, sg.tile))
      pcall(MDQ.grabBorderSync, b, sg.ww, sg.wh, MDQ.EDGE_PX)   -- ★1.75.60u：粗细恒定 1px（状态只靠颜色）
    end
  end
  return true
end

-- ★★★1.75.60f（用户：「鼠标悬浮层序号的时候可以高亮这个对应的层边框.并且支持点击拖拽」）：
--   **图上悬停（柄的边框 / 序号角标）= 与列表行悬停同一套**（唯一实现）—— 把这一块画成
--   **亮白黄 + 加粗**（就是悬停列表行时看到的那一下），离开则按选中/隐藏态恢复。
--   ★为什么另立一个口：老 `MDQ.grabHi` **只调整体透明度**（不换色、不加粗）⇒ 悬浮图上的序号
--     只有一点点明暗差别，看着像「没反应」；而列表行悬停走的是 `hoverIdx` + `hoverPaint` 那套。
--     现在两边共用 `MDQ.hoverIdx` ⇒ 一份状态、一处实现（`hoverPaint` / 渲染收尾的 `grabSyncAll` 都读它）。
--   ★离开时**只在自己仍是当前悬停那一块**时才熄（列表行与图上悬停互相踩不到）；
--     **拖拽中不许熄**（那是「正在动的是这一块」的视觉，结束归接盘 / 节拍管）。
MDQ.hoverMap = function(i, on)
  local n = tonumber(i) or -1
  if n <= 0 then return false end
  local b = MDQ.grab[n]
  if on then
    MDQ.hoverIdx = n
    pcall(MDQ.hoverPaint)
    if b ~= nil then pcall(MDQ.grabHi, b, true) end
    return true
  end
  if (tonumber(MDQ.hoverIdx) or -1) ~= n then
    if b ~= nil then pcall(MDQ.grabHi, b, false) end
    return false
  end
  if type(MDQ.dragSt) == "table" and (tonumber(MDQ.dragSt.i) or -1) == n then
    if b ~= nil then pcall(MDQ.grabHi, b, true) end
    return false
  end
  MDQ.hoverIdx = nil
  pcall(MDQ.hoverPaint)
  if b ~= nil then pcall(MDQ.grabHi, b, false) end
  return true
end

-- 边框 + 柄几何同步（`thick` = 边框粗细；★1.75.60u 起调用点一律传 `MDQ.EDGE_PX`(1) ⇒ 不再按状态加粗）
MDQ.grabBorderSync = function(b, w, h, thick)
  if b == nil then return false end
  local tw = tonumber(w) or 1
  local th = tonumber(h) or 1
  local t = tonumber(thick) or (tonumber(MDQ.EDGE_PX) or 1)   -- ★1.75.60u：粗细默认 = EDGE_PX（1px）
  if tw < 1 then tw = 1 end
  if th < 1 then th = 1 end
  pcall(b.SetWidth, b, tw)
  pcall(b.SetHeight, b, th)
  if b.eTop ~= nil then pcall(b.eTop.SetWidth, b.eTop, tw) pcall(b.eTop.SetHeight, b.eTop, t) end
  if b.eBot ~= nil then pcall(b.eBot.SetWidth, b.eBot, tw) pcall(b.eBot.SetHeight, b.eBot, t) end
  if b.eLeft ~= nil then pcall(b.eLeft.SetWidth, b.eLeft, t) pcall(b.eLeft.SetHeight, b.eLeft, th) end
  if b.eRight ~= nil then pcall(b.eRight.SetWidth, b.eRight, t) pcall(b.eRight.SetHeight, b.eRight, th) end
  return true
end

-- ★★★1.75.60i（用户第二轮定案：「**拖拽图层的右键不要进行数据重置操作.只作为拖拽释放操作**」）：
--   **单块归零的唯一实现**从「右键 + 两次确认」改成「**列表行前的红 ×**，一次点击」—— 右键**彻底退出数据面**。
--   ★为什么这样才对（真机报障换来的）：右键在拖拽柄上同时是「释放拖拽」的手势，一个手势两个含义就是误删的根源
--     ——用户刚把贴图对齐、顺手右键收手 ⇒ 存档增量被删 ⇒ 显示回落到 `MapOverlayOffset.lua` 的文件基线，
--     他看到的是「右键把 x 轴数据改了」（实证：`MOGROSHSTRONGHOLD#1` 存档 -0.1,-7.4 ⇒ 变成文件基线 -12.5,-12.5）。
--     现在右键只有一个含义（释放），数据入口是一个**明确瞄准的红钮** ⇒ 不需要「两次确认」也不会误触。
--   ★三态文案如实（1.75.60d 定）：删掉存档之后若**文件基线**上还有值 ⇒ 显示的是文件值，不是 0。
MDQ.zeroOne = function(i, deep)
  local file = tostring(select(1, smMapInfo()) or "")
  local sg = MDQ.slot[i]
  if file == "" or sg == nil then return false end
  -- ★1.75.60m：先清**存档增量**（深清那一路随后用 0 影盖住同一格 —— 先删更干净，「删了几条」的口径也不打架）
  local had = MDQ.editDel(file, sg.area, sg.tile)
  local fHas = MDQ.editFileRec(file, sg.area, sg.tile) ~= nil
  local shadowed = false
  if deep == true and fHas then
    shadowed = MDQ.editShadowPut(file, sg.area, sg.tile, "重置单块（含插件基线）")
  end
  MDQ.editRefresh()
  if shadowed then
    -- ★1.75.60m（用户：「重置也能重置**插件的偏移量**，不单是用户自定义的偏移量」）：**连插件基线一起压掉**
    say(string.format("世界迷雾·编辑：「%s#%d」**连插件偏移量一起重置** —— `MapOverlayOffset.lua` 那一条也用**存档 0 影**压住了"
      .. " ⇒ 这一块回到 `MapOverlayData.lua` 的**原始表值**（0 影可逆：再点左键把影删掉就回落插件基线）",
      tostring(sg.area), tonumber(sg.tile) or 0))
  elseif had then
    -- ★1.75.60d：删掉存档之后若**文件基线**上还有值 ⇒ 显示的是文件值，不是 0 ⇒ 如实说
    if fHas then
      say(string.format("世界迷雾·编辑：「%s#%d」存档补偿**已归零**（记录删除）⇒ **回落到插件基线**（`MapOverlayOffset.lua` 那条还在生效；"
        .. "要连它一起清：**右键这颗红 ×**）", tostring(sg.area), tonumber(sg.tile) or 0))
    else
      say(string.format("世界迷雾·编辑：「%s#%d」补偿**已归零**（记录删除）", tostring(sg.area), tonumber(sg.tile) or 0))
    end
  elseif fHas then
    say(string.format("世界迷雾·编辑：「%s#%d」用的是**插件偏移量基线**（`MapOverlayOffset.lua`，存档里没有可归零的记录）"
      .. "⇒ 要回原始表值：**右键这颗红 ×**（连插件基线一起压住）· 或把它**拖回原点**（一样写 0 影）· 或重生 `gen_mapoffset.js`",
      tostring(sg.area), tonumber(sg.tile) or 0))
  else
    say(string.format("世界迷雾·编辑：「%s#%d」补偿%s", tostring(sg.area), tonumber(sg.tile) or 0,
      "本来就是 0（存档与插件基线里都没有这一条）"))
  end
  -- ★1.75.60j（「关联操作」也要亮）：点红 × 清的是**哪一块**要在图上看一眼 ⇒ 那一块亮 1.4 秒（到点自己过期）
  if had or shadowed then pcall(MDQ.focusFlash, i, 1.4) end
  return true
end

-- ★★★1.75.60t（用户：「地图内右键类似在列表页内的右键效果.隐藏这个图层」）：地图内右键 = **隐藏/显示这一层**。
--   ★难度在于右键**同时**是「释放拖拽」的手势（1.75.60e：拖拽节拍直接读 `IsMouseButtonDown("RightButton")`）⇒
--     用户拖到一半用右键收手时，**抬起那一拍**会在柄/角标上触发 `OnClick` ⇒ 不能让它顺手把这一层藏掉。
--   ⇒ 两道闸（缺一不可）：① `dragSt` 还在 ⇒ 这一下**是释放**（节拍/接盘会结束它），直接返回；
--     ② 节拍那一拍已经释放了 ⇒ 用 `MDQ.rightRel` 的**时间戳窗口**兜住（`editEnd` 前盖章，见 `editTick`）。
--   ★这是**纯显示**动作（补偿数据一个字不动，与列表行右键完全同效），所以窗口过后按多少下都只切显示。
-- ★★★1.75.60u（用户：「地图图层选中/悬浮高亮灯这些框编辑设置1px 不然太粗看不到边界」）：
--   **高亮边框的粗细 = 1 像素**（状态区分**只靠颜色**：常态金 / 已选青 / 焦点亮白黄）。
--   ★钉在**一个常量**上：以前是「常态 2 / 悬停-拖拽 3」两档（用加粗当状态反馈）—— 太粗会把块自己的边界盖掉，
--     用户要的是「能看清边界」，所以粗细不再随状态变；要再调（比如觉得 1 在缩放下太细）**只改这一个数**。
MDQ.EDGE_PX = 1
MDQ.RIGHT_REL_SEC = 0.45
MDQ.rightRel = 0
MDQ.grabBuild = function(i)
  if type(CreateFrame) ~= "function" then return nil end
  local fr = _G["WorldMapDetailFrame"]
  if fr == nil then return nil end
  local b = CreateFrame("Button", "EVAL_WF_GRAB" .. tostring(i), fr)
  if b == nil then return nil end
  b.gi = i        -- ★1.75.60j：柄记住自己的**块序号** —— `grabHi` 要靠它按当前态（悬停/已选/关联操作）重画
  if type(b.SetFrameStrata) == "function" then pcall(b.SetFrameStrata, b, "FULLSCREEN") end
  if type(b.SetFrameLevel) == "function" then
    local lv = 1
    if type(fr.GetFrameLevel) == "function" then
      local okv, v = pcall(fr.GetFrameLevel, fr)
      if okv and tonumber(v) then lv = tonumber(v) end
    end
    pcall(b.SetFrameLevel, b, lv + 20)
  end
  pcall(b.EnableMouse, b, true)
  -- ★★★1.75.60t（用户：「地图内右键类似在列表页内的右键效果.隐藏这个图层」）：**注册双键** ——
  --   左键 = 拖拽/选中（`OnMouseDown`，见下）；**右键 = 隐藏/显示这一层**（`OnClick`，与列表行右键同一个写口）。
  --   ★光注册左键 ⇒ 右键永远到不了分派代码（本项目既定雷，1.75.59b/60m 各踩一次）。
  if type(b.RegisterForClicks) == "function" then
    pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
  end
  b:SetScript("OnClick", function(a, bb)
    if wfMouseBtn(a, bb) ~= "RightButton" then return end        -- 左键那半边走 OnMouseDown/OnMouseUp
    if type(MDQ.dragSt) == "table" then return end               -- 还在拖 ⇒ 这一下是**释放**（不许藏层）
    local nowT = (type(GetTime) == "function") and (tonumber(GetTime()) or 0) or 0
    if (nowT - (tonumber(MDQ.rightRel) or 0)) < (tonumber(MDQ.RIGHT_REL_SEC) or 0.45) then return end
    pcall(MDQ.blkHideBySlot, i, "地图内右键")
  end)
  -- 高亮边框 = 四条细纹理（`WHITE8X8` + `SetVertexColor` 是本项目唯一可靠的纯色配方）
  --   ★1.75.60j：**建出来就是收起的**（`Hide`）—— 默认一个框都不画，拿到焦点才由 `MDQ.grabColor` 亮起来。
  local edges = {}
  local function newEdge(pt, rpt)
    local e = b:CreateTexture(nil, "OVERLAY")
    if e == nil then return nil end
    pcall(e.SetTexture, e, "Interface\\Buttons\\WHITE8X8")
    pcall(e.SetVertexColor, e, 1.00, 0.82, 0.25)
    pcall(e.SetAlpha, e, 1.00)
    pcall(e.SetPoint, e, pt, b, rpt, 0, 0)
    pcall(e.Hide, e)
    table.insert(edges, e)
    return e
  end
  b.eTop = newEdge("TOPLEFT", "TOPLEFT")
  b.eBot = newEdge("BOTTOMLEFT", "BOTTOMLEFT")
  b.eLeft = newEdge("TOPLEFT", "TOPLEFT")
  b.eRight = newEdge("TOPRIGHT", "TOPRIGHT")
  b.eAll = edges
  local fs = b:CreateFontString(nil, "OVERLAY")
  if fs ~= nil then
    if type(fs.SetFontObject) == "function" then pcall(fs.SetFontObject, fs, _G["GameFontHighlightSmall"]) end
    pcall(fs.SetPoint, fs, "BOTTOM", b, "TOP", 0, 2)
    pcall(fs.SetJustifyH, fs, "CENTER")
    pcall(fs.Hide, fs)
  end
  b.fs = fs
  -- ★★★1.75.60c（用户：「编辑模式贴图左上角显示个对应在迷雾贴图列表的序号」）：
  --   柄**左上角**画一个**序号角标** = 右侧贴图列表里那一行的 `序号.`（`bi = 池位号`，与列表逐行同源）
  --   —— 列表第 N 行 ↔ 图上第 N 块一眼对上，不用数格子。
  --   ★角标配一个**暗底小方块**（地图底是亮色地形，裸字会看花）；颜色跟着 `grabColor` 的三态走
  --     （金常态 / 青已选 / 亮白黄悬停）⇒ 悬停哪一行，哪一块的框**和**序号一起亮。
  --   ★纹理/字体串都不吃鼠标 ⇒ 角标不挡拖拽（柄还是那个 Button 在收事件）。
  --   ★1.75.60j：**显式 Show** —— 用户点名「序号显示」⇒ 角标不参与「默认收起」，可见性契约走显式控件清单
  --     （不靠客户端「新建即显示」的默认值；收起边框那件事与它无关）。
  local ibg = b:CreateTexture(nil, "OVERLAY")
  if ibg ~= nil then
    pcall(ibg.SetTexture, ibg, "Interface\\Buttons\\WHITE8X8")
    pcall(ibg.SetVertexColor, ibg, 0.05, 0.05, 0.07)
    pcall(ibg.SetAlpha, ibg, 0.75)
    pcall(ibg.SetWidth, ibg, 18)
    pcall(ibg.SetHeight, ibg, 12)
    pcall(ibg.SetPoint, ibg, "TOPLEFT", b, "TOPLEFT", 2, -2)
    pcall(ibg.Show, ibg)
  end
  b.idxBg = ibg
  local ifs = b:CreateFontString(nil, "OVERLAY")
  if ifs ~= nil then
    if type(ifs.SetFontObject) == "function" then pcall(ifs.SetFontObject, ifs, _G["GameFontHighlightSmall"]) end
    pcall(ifs.SetPoint, ifs, "TOPLEFT", b, "TOPLEFT", 4, -3)
    pcall(ifs.SetJustifyH, ifs, "LEFT")
    pcall(ifs.SetTextColor, ifs, 1.00, 0.82, 0.25)
    pcall(ifs.SetText, ifs, tostring(i))
    pcall(ifs.Show, ifs)      -- ★1.75.60j：序号**常显**（显式 Show，不靠客户端默认值）
  end
  b.idx = ifs
  -- ★★★1.75.60f（用户：「鼠标悬浮层序号的时候可以高亮这个对应的层边框.并且支持点击拖拽」）：
  --   序号角标本身是**纹理 + 字体串 ⇒ 都不吃鼠标**（项目配方 §三.9）⇒ 要在角标上「悬浮 / 按住拖」，
  --   必须**盖一个透明 Button 热区**。它还补上一个真实缺口：**细长块（如 6px 宽）的角标会伸出边框之外**
  --   —— 那一段原本既不高亮也点不动；现在角标整块（20×14）都是抓手。
  --   ★事件语义与柄**完全一致**（三处共用同一实现）：悬浮 = `MDQ.hoverMap`（亮白黄 + 加粗，含序号）、
  --     左键按下 = `MDQ.editBegin(i)`（拖拽）、左键松开 = `editEnd`（鼠标捕获那条路）。
  --   ★★★1.75.60i（用户：「**拖拽图层的右键不要进行数据重置操作.只作为拖拽释放操作**」）：角标与柄上的右键
  --     **不再是任何数据入口**（旧版这里是 `wfZeroBlock(i)`）—— 右键的唯一含义 = 「释放拖拽」（由节拍读键状态实现，
  --     与按在哪个帧上无关）；重置单条数据的入口只剩**列表行前的红 ×**，批量入口仍是那两颗重置按钮。
  --   ★热区是柄的**子帧** ⇒ 柄 Show/Hide 它跟着走（不用另进控件清单），也不吃父帧之外的任何东西。
  local ih = CreateFrame("Button", nil, b)
  if ih ~= nil then
    pcall(ih.SetWidth, ih, 20)
    pcall(ih.SetHeight, ih, 14)
    pcall(ih.SetPoint, ih, "TOPLEFT", b, "TOPLEFT", 1, -1)
    pcall(ih.EnableMouse, ih, true)
    -- ★★★1.75.60t：与柄**完全一致** —— 左键 = 悬停/起拖，**右键 = 隐藏/显示这一层**（同一个写口、同一道窗口闸）。
    if type(ih.RegisterForClicks) == "function" then
      pcall(ih.RegisterForClicks, ih, "LeftButtonUp", "RightButtonUp")
    end
    ih:SetScript("OnClick", function(a, bb)
      if wfMouseBtn(a, bb) ~= "RightButton" then return end
      if type(MDQ.dragSt) == "table" then return end
      local nowT = (type(GetTime) == "function") and (tonumber(GetTime()) or 0) or 0
      if (nowT - (tonumber(MDQ.rightRel) or 0)) < (tonumber(MDQ.RIGHT_REL_SEC) or 0.45) then return end
      pcall(MDQ.blkHideBySlot, i, "地图内右键")
    end)
    ih:SetScript("OnEnter", function()
      if not MDQ.editOn() then return end
      MDQ.hoverMap(i, true)
    end)
    ih:SetScript("OnLeave", function()
      MDQ.hoverMap(i, false)
    end)
    ih:SetScript("OnMouseDown", function(a, bb)
      local btn = wfMouseBtn(a, bb)
      if btn == "RightButton" then return end     -- ★右键 = 只释放拖拽（1.75.60i：不重置数据、也不起拖）
      MDQ.editBegin(i)
    end)
    ih:SetScript("OnMouseUp", function()
      if type(MDQ.dragSt) == "table" and MDQ.dragSt.b == b then pcall(MDQ.editEnd, "松手") end
    end)
  end
  b.idxHit = ih
  b:SetScript("OnEnter", function()
    if not MDQ.editOn() then return end
    -- ★1.75.60f：接进**统一悬停态**（亮白黄 + 加粗，与列表行悬停同一套）
    MDQ.hoverMap(i, true)
  end)
  b:SetScript("OnLeave", function()
    -- ★拖拽中不许被 OnLeave 熄掉（结束归接盘 / 节拍管）—— 这一点收在 `MDQ.hoverMap` 里
    MDQ.hoverMap(i, false)
  end)
  b:SetScript("OnMouseDown", function(a, bb)
    local btn = wfMouseBtn(a, bb)
    if btn == "RightButton" then return end      -- ★右键 = 只释放拖拽（1.75.60i：不重置数据、也不起拖）
    MDQ.editBegin(i)
  end)
  -- ★1.75.60f（用户：「有些时候很难释放拖拽」的**左键那半边**）：柄自己接 **OnMouseUp** ——
  --   在柄上按下时客户端会**鼠标捕获**这个按钮 ⇒ 松开那一下会回到柄上（接盘在地图上方收不到，这条收得到）。
  --   ★与接盘 / 右键释放**三条路走同一个 `editEnd`**（幂等：`dragSt` 已清就早退，不会重复记账）；
  --     只有「本拍正在拖的就是这个柄」才收（按 A 松到 B 上不该结束）。
  b:SetScript("OnMouseUp", function()
    if type(MDQ.dragSt) == "table" and MDQ.dragSt.b == b then pcall(MDQ.editEnd, "松手") end
  end)
  -- ★1.75.60i：柄的 `OnClick` **整个撤掉**（旧版右键在这里归零）—— 右键不再是数据入口，
  --   归零只走「列表行前的红 ×」与那两颗批量重置按钮。
  pcall(b.Hide, b)
  return b
end

MDQ.grabAt = function(i)
  local b = MDQ.grab[i]
  if b ~= nil then return b end
  b = MDQ.grabBuild(i)
  if b == nil then return nil end
  MDQ.grab[i] = b
  if i > (tonumber(MDQ.grabN) or 0) then MDQ.grabN = i end
  return b
end

-- 把柄铺到本拍渲染出的每一块上（**由 `MDQ.render` 收尾时调**）⇒ 与图层几何同源，不另算一套
MDQ.grabSyncAll = function(file, n, k)
  if not (MDQ.editOn and MDQ.editOn()) then return MDQ.grabHideAll("编辑模式关着") end
  local fr = _G["WorldMapDetailFrame"]
  local cnt = tonumber(n) or 0
  local shown = 0
  for i = 1, cnt do
    local sg = MDQ.slot[i]
    local b = (sg ~= nil and sg.wx ~= nil) and MDQ.grabAt(i) or nil
    if b ~= nil then
      local hov = ((tonumber(MDQ.hoverIdx) or -1) == i)
      local thick = MDQ.EDGE_PX   -- ★1.75.60u：渲染收尾也走同一个常量（不再按状态加粗）
      pcall(b.ClearAllPoints, b)
      pcall(b.SetPoint, b, "TOPLEFT", fr, "TOPLEFT", sg.wx, sg.wy)
      MDQ.grabBorderSync(b, sg.ww, sg.wh, thick)
      -- ★1.75.59p：选中集里的块换**青色**（列表多选要在图上看得见）
      -- ★1.75.59q：悬停那一行对应的块换**亮白黄**（列表 ↔ 图上一眼对上）
      MDQ.grabColor(b, MDQ.selHas and MDQ.selHas(sg.area, sg.tile), (tonumber(MDQ.hoverIdx) or -1) == i,
        MDQ.blkHidden(sg.area, sg.tile))
      pcall(b.Show, b)
      shown = shown + 1
    end
  end
  -- 超出本拍块数的柄全部收起（否则上一张图留下的柄会留在屏上吃鼠标）
  for i = cnt + 1, tonumber(MDQ.grabN) or 0 do
    local b2 = MDQ.grab[i]
    if b2 ~= nil then pcall(b2.Hide, b2) end
  end
  return shown
end

MDQ.grabHideAll = function(why)
  local n = 0
  for i = 1, tonumber(MDQ.grabN) or 0 do
    local b = MDQ.grab[i]
    if b ~= nil then pcall(b.Hide, b) n = n + 1 end
  end
  if type(MDQ.dragSt) == "table" then pcall(MDQ.editStop, tostring(why)) end
  -- ★1.75.59p：贴图列表**只在编辑模式用** ⇒ 收柄时一起收起（唯一收口，绝不留孤窗）
  if MDQ.panel ~= nil then pcall(MDQ.panel.Hide, MDQ.panel) end
  return n
end

-- ===== 拖拽接盘（全屏 Button）=====
--   ★为什么必须有它：拖动的是**一小块**，指针几乎立刻离开柄 ⇒ 只靠柄自己的 `OnMouseUp` 会**永远收不到松手**
--     （`DragFrames` 的同一课：接盘过鼠标，松手时无论指针在哪都能收到）。它**没有自己的 OnUpdate**
--     （一个模块只许一个节拍帧，拖拽的推进走 `MDQ.editTick` —— 挂在模块节拍上），只在拖拽期间显示。
MDQ.catch = nil
local function wfCatcherBuild()
  if MDQ.catch ~= nil then return MDQ.catch end
  if type(CreateFrame) ~= "function" then return nil end
  local c = CreateFrame("Button", "EVAL_WF_EDITCATCH", _G["UIParent"])
  if c == nil then return nil end
  pcall(c.SetAllPoints, c)
  if type(c.SetFrameStrata) == "function" then pcall(c.SetFrameStrata, c, "FULLSCREEN") end
  if type(c.SetFrameLevel) == "function" then pcall(c.SetFrameLevel, c, 900) end
  pcall(c.EnableMouse, c, true)
  if type(c.RegisterForClicks) == "function" then pcall(c.RegisterForClicks, c, "LeftButtonUp", "RightButtonUp") end
  c:SetScript("OnMouseUp", function() if type(MDQ.dragSt) == "table" then pcall(MDQ.editEnd, "松手") end end)
  c:SetScript("OnClick", function() if type(MDQ.dragSt) == "table" then pcall(MDQ.editEnd, "松手") end end)
  pcall(c.Hide, c)
  MDQ.catch = c
  return c
end
local function wfCatcherShow(on)
  local c = MDQ.catch
  if on then
    c = wfCatcherBuild()
    if c ~= nil then pcall(c.Show, c) end
  elseif c ~= nil then
    pcall(c.Hide, c)
  end
  return c
end

-- ===== 拖拽主流程 =====
MDQ.editBegin = function(i)
  if not MDQ.editOn() then return false end
  if not MDQ.swm() then return false end
  if type(GetCursorPosition) ~= "function" then return false end
  local sg = MDQ.slot[tonumber(i) or 0]
  if sg == nil or sg.tex == nil then return false end
  -- ★★★1.75.60t（用户点名）：**地图内的左键语义** ——
  --   ① **Shift + 左键 = 只切选中（多选）**：**连拖拽都不起**（不建 `dragSt`、不显示接盘 ⇒ 绝不产生位移）；
  --   ② ★★★1.75.60v（用户：「迷雾贴图->左键单击现在不支持单独选中和拖拽启动,现在只支持 shift+左键支持图层选中,
  --      **只有选中的图片才支持左键拖拽移动,防止误点击拖拽图层**」）：**左键按在「未选中」的块上 = 只选中、绝不起拖**
  --      —— 顺序 = 先单选、再 `return false` ⇒ **这一下建不出 `dragSt`（一个位移都不产生）**，要拖得**再按住左键**
  --      （那时它已在选中集里 ⇒ 走 ③）。⇒ 「误按 + 顺手一拖」不会再把图层挪走（用户点名的防误拖）；
  --   ③ **已选中的块，左键按住 = 起拖**（多选则**整组一起动** —— 否则「Shift 多选之后拖整组」这条唯一的路就没了）。
  --   ★顺序要在 `dragMembers` **之前**：成员表是按「当下选中集」算的 ⇒ 先定选中、再算成员（拖哪几块才正确）。
  if MDQ.shiftDown() then
    local on = MDQ.selToggle(sg.area, sg.tile)
    local n = MDQ.selCount()
    wfEcho()        -- ★用户点我们的界面 = 他主动问的 ⇒ 盖章回显（「调试日志」关着也看得见）
    say(string.format("世界迷雾·编辑：Shift+左键 = **只切选中**（不起拖）⇒「%s#%d」现在 = **%s** ｜ 已选 %d 块%s",
      tostring(sg.area), tonumber(sg.tile) or 0, on and "选中" or "取消", n,
      (n > 1) and "（拖任意一块 = 整组一起动）" or ""))
    MDQ.selAfterChange()
    return false, "shift"
  end
  if not MDQ.selHas(sg.area, sg.tile) then
    -- ★1.75.60v：**只选中、不起拖**（选中与拖动**分成两次按下**）—— 这一下绝不产生位移，杜绝误拖。
    --   ★为什么不再「按下即单选 + 立刻起拖」（1.75.60t 那版）：那时手一抖就会把未选中的图层拖走。
    MDQ.selOnly(sg.area, sg.tile)
    MDQ.selAfterChange()
    wfEcho()        -- 点了界面 = 他主动问的 ⇒ 盖章 + 如实说清「下一步怎么拖」（限频，连点不刷屏）
    local nowP = (type(GetTime) == "function") and (tonumber(GetTime()) or 0) or 0
    if (nowP - (tonumber(MDQ.pickSayAt) or 0)) >= (tonumber(MDQ.PICK_SAY_SEC) or 0.6) then
      MDQ.pickSayAt = nowP
      say(string.format("世界迷雾·编辑：左键单击 = **只选中**（防误拖，不起位移）⇒「%s#%d」已选中；**再按住左键即可拖动**（Shift+左键 = 多选 / 取消）",
        tostring(sg.area), tonumber(sg.tile) or 0))
    end
    return false, "pick"
  end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and tonumber(cx) and tonumber(cy)) then return false end
  local file = tostring(select(1, smMapInfo()) or "")
  if file == "" then return false end
  -- ★★★1.75.59p：**拖拽成员** = 多选取自选中集、单选就是它自己（`MDQ.dragMembers` 是唯一构造口）。
  --   每个成员都先与 `MapOverlayData.lua` 配对（配不上就不进成员表 ⇒ 孤儿补偿绝不被硬算）。
  local m = MDQ.areaOf(file)
  local members = MDQ.dragMembers(file, sg, m, tonumber(MDQ.lastRenderN) or 0)
  if table.getn(members) == 0 then
    -- ★拿不到配对基准 ⇒ **不动手**（本项目铁律）；正常情况下走不到这里（这块就是按表画出来的）
    say(string.format("世界迷雾·编辑：「%s#%d」在 `MapOverlayData.lua` 里查不到 ⇒ 这次**不建补偿**（配对不上就不动手）",
      tostring(sg.area), tonumber(sg.tile) or 0))
    return false
  end
  local k = tonumber(MDQ.lastK) or 1
  if k <= 0 then k = 1 end
  local chain, csrc = MDQ.editMeasure()
  local coef = k * chain
  if coef == nil or coef <= 0 then coef = 1 end
  local b = MDQ.grabAt(i)
  local mem0 = members[1]
  -- ★1.75.60e：右键初始态（按下起拖时右键**已经按着** ⇒ 当「已按下」记 ⇒ 等松开再按才算「释放一下」，
  --   否则拖着右键起拖会**当场**结束掉这次拖拽）
  local rb0 = false
  if type(IsMouseButtonDown) == "function" then
    local okD0, d0 = pcall(IsMouseButtonDown, "RightButton")
    rb0 = (okD0 and (d0 == true or d0 == 1)) or false
  end
  MDQ.dragSt = {
    b = b, i = i, file = file, area = sg.area, tile = sg.tile,
    cx0 = tonumber(cx), cy0 = tonumber(cy), lcx = tonumber(cx), lcy = tonumber(cy),
    members = members,
    k = k, es = chain, coef = coef, src = csrc, idle = 0, age = 0, moved = false, rDown = rb0,
  }
  wfCatcherShow(true)
  if b ~= nil then MDQ.grabHi(b, true) end
  if table.getn(members) > 1 then
    say(string.format("世界迷雾·编辑：**整组拖动 %d 块**（含「%s#%d」；按列表里选中的那些一起走）｜ 当时 k=%.3f es=%.3f ⇒ 1 表像素 = %.3f 屏像素 ｜ 系数=%s",
      table.getn(members), tostring(sg.area), tonumber(sg.tile) or 0, k, chain, coef, tostring(csrc)))
  else
    say(string.format("世界迷雾·编辑：拖动「%s#%d」（基础表 %s,%s ＋ 现有补偿 %+.1f,%+.1f ｜ 当时 k=%.3f es=%.3f ⇒ 1 表像素 = %.3f 屏像素 ｜ 系数=%s）"
      .. "；松手即记入补偿表（拖拽中**任意位置右键 = 释放**；要归零这一条：列表行前的**红 ×**）", tostring(sg.area), tonumber(sg.tile) or 0,
      tostring(mem0.bx), tostring(mem0.by), mem0.x0, mem0.y0, k, chain, coef, tostring(csrc)))
  end
  return true
end

-- 拖拽推进（**挂在模块唯一的那一个节拍帧上**，由 `beat` 调用；零形参，dt 从全局 arg1 取）
MDQ.editTick = function()
  local st = MDQ.dragSt
  if type(st) ~= "table" then return 0 end
  local dt = tonumber(arg1) or 0.05
  -- ★★★1.75.60e（用户：「图层拖拽开始之后.有些时候很难释放拖拽,调整右键释放拖拽.监听是uiparent
  --   也就是位置右键都可以释放拖拽效果」）：**右键（任意位置）= 释放拖拽**。
  --   ★为什么不做成帧监听：接盘在地图上方收不到松开的那一下（层级/遮挡）时，帧方案就是「很难释放」的根源；
  --     这里在节拍里直接读**鼠标键状态**（`IsMouseButtonDown`）—— 与光标位置无关，等价于 UIParent 级监听。
  --   ★排在**光标读取之前**：光标读不到（指针出窗等病态）也照样能放。边沿触发（按下那一下才放），
  --     起拖时已经按着的右键要等松开再按才算数（`editBegin` 记的 `rDown`）。
  if st.rDown == true then
    if type(IsMouseButtonDown) == "function" then
      local okD1, d1 = pcall(IsMouseButtonDown, "RightButton")
      if not (okD1 and (d1 == true or d1 == 1)) then st.rDown = false end
    else
      st.rDown = false   -- API 拿不到 ⇒ 边沿记位复位，别卡死在「已按下」
    end
  elseif type(IsMouseButtonDown) == "function" then
    local okD2, d2 = pcall(IsMouseButtonDown, "RightButton")
    if okD2 and (d2 == true or d2 == 1) then
      st.rDown = true
      -- ★★★1.75.60t：这一拍**不自己盖章** —— 章只盖在 `editEnd` **一处**（那三条释放路：节拍 / 接盘 `OnClick` /
      --   柄 `OnMouseUp` 都汇到它 ⇒ 一处盖章三条路全覆盖，见 `editEnd` 里的注释）。
      --   ★这里多盖一次不仅是冗余，还会把「章到底盖在哪」变成**两处口径**（变异验证实测：摘掉这一行行为
      --     **完全等价** ⇒ 它就是死重，留着只会让判据钉错地方）。
      MDQ.editEnd("右键释放")
      return 1
    end
  end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and tonumber(cx) and tonumber(cy)) then return 0 end
  cx, cy = tonumber(cx), tonumber(cy)
  local totX, totY = cx - st.cx0, cy - st.cy0
  if math.abs(totX) > 0.5 or math.abs(totY) > 0.5 then st.moved = true end
  -- ★换算：Δ表 = Δ屏幕 ÷ (k × es)；★y 号：屏幕 y **向上**为正，表口径 y **向下**为正 ⇒ 取负
  local ddx, ddy = totX / st.coef, -totY / st.coef
  local x, y = ddx, ddy
  if st.moved then
    local t0 = (date and tostring(date("%m-%d %H:%M:%S")) or "?")
    local members = st.members or {}
    if table.getn(members) == 0 and st.area ~= nil then
      members = { { area = st.area, tile = st.tile, x0 = 0, y0 = 0 } }
    end
    for _, mbr in ipairs(members) do
      -- ★每个成员各记**自己那条**补偿（数据始终逐块一条 ⇒ 配对与读取口径不变）；
      --   同一个 Δ 加到各自的原值上 = 整组平移（不选任何块时成员只有它自己）
      local mx = (tonumber(mbr.x0) or 0) + ddx
      local my = (tonumber(mbr.y0) or 0) + ddy
      -- ★1.75.60q：尺寸补偿（`dw/dh`）**原样带过去** —— 不带 = 一拖就把宽高冲掉（真机报障那次）
      local put = {
        x = mx, y = my,
        bx = mbr.bx, by = mbr.by, bw = mbr.bw, bh = mbr.bh,
        k = st.k, es = st.es, coef = st.coef, src = st.src,
        sx = totX, sy = totY, t = t0,
      }
      MDQ.editCarrySize(put, MDQ.editRec(st.file, mbr.area, mbr.tile))
      MDQ.editPut(st.file, mbr.area, mbr.tile, put)
      if mbr.area == st.area and mbr.tile == st.tile then x, y = mx, my end
    end
  end
  -- 立刻重申一遍（silent：不刷屏、不跑护守；写前比对 ⇒ 只有动了的那几块真写）⇒ 拖拽跟手
  local fr = _G["WorldMapDetailFrame"]
  local es = nil
  if fr ~= nil then
    local ok, v = pcall(smEffScale, fr)
    if ok and tonumber(v) then es = tonumber(v) end
  end
  if es ~= nil then pcall(MDQ.renderCurrent, es, true, true, false) end
  if st.b ~= nil and st.b.fs ~= nil then
    local nMem = table.getn(st.members or {})
    if nMem > 1 then
      pcall(st.b.fs.SetText, st.b.fs, string.format("整组 %d 块：Δx%+.1f Δy%+.1f（表口径）", nMem, ddx, ddy))
    else
      pcall(st.b.fs.SetText, st.b.fs, string.format("x%+.1f y%+.1f（表口径）", x, y))
    end
  end
  -- 结束时机：**接盘收到松手是主路**，下面两条只防「接盘也没收到」的病态（指针不动 / 拖太久）
  if math.abs(cx - st.lcx) < 0.5 and math.abs(cy - st.lcy) < 0.5 then
    st.idle = (tonumber(st.idle) or 0) + dt
    if st.idle >= 2.0 then MDQ.editEnd("停手 2 秒") return 1 end
  else
    st.idle = 0
  end
  st.lcx, st.lcy = cx, cy
  st.age = (tonumber(st.age) or 0) + dt
  if st.age >= 30 then MDQ.editEnd("超时 30 秒") return 1 end
  return 1
end

MDQ.editEnd = function(why)
  local st = MDQ.dragSt
  if type(st) ~= "table" then
    wfCatcherShow(false)
    return false
  end
  MDQ.dragSt = nil
  -- ★★★1.75.60t（用户：「地图内右键类似在列表页内的右键效果.隐藏这个图层」）：拖拽收尾这一拍**盖右键窗口章**。
  --   ★为什么必须在**这个**位置：右键在拖拽里是「释放」手势，而释放有**三条路**（节拍读键状态 / 接盘 `OnClick` /
  --     柄自己的 `OnMouseUp`）；紧接着「抬起」那一下还会落到柄或序号角标上触发它们的 `OnClick` ⇒ 不盖章的话，
  --     用户用右键收手会**顺手把那一层藏掉**（= 误伤）。⇒ ★★**章只盖在这一处**（唯一盖章点）：三条路都汇到
  --     `editEnd` ⇒ 天然全覆盖；节拍那条路**不许再自己盖一次**（两处口径 = 判据钉错地方，1.75.60t 收口）。
  if type(GetTime) == "function" then MDQ.rightRel = tonumber(GetTime()) or 0 end
  -- ★1.75.60i：不再盖「刚结束拖拽」的章（旧版 `MDQ.dragEndAt` 是给右键归零兜底的；右键已退出数据面）。
  --   ★松手之后紧接着的那一下右键现在只当「收手」—— 因为它**本来就不做任何数据操作**。
  wfCatcherShow(false)
  local b = st.b or MDQ.grab[st.i]
  if b ~= nil then MDQ.grabHi(b, false) end
  local members = st.members or {}
  if table.getn(members) == 0 then members = { { area = st.area, tile = st.tile } } end
  local nMem = table.getn(members)
  if st.moved ~= true then
    -- ★★★1.75.60t（用户：「默认点击是单选」）：**点一下（没拖着走）不再切换选中** ——
    --   选中的语义已经**前移到 `editBegin`**（按下那一刻）：默认 = 单选、Shift = 切换多选。
    --   ★旧写法在这里 `selToggle` ⇒ 与新语义**打架**：按下刚单选上、抬起又把它取消了 = 用户点一下等于没点。
    --   这里只做「刷新一次」（列表 + 图上高亮跟上），**绝不写任何补偿、也不改选中集**。
    if MDQ.panelSync ~= nil then pcall(MDQ.panelFill, tostring(st.file), tonumber(MDQ.lastRenderN) or 0) end
    pcall(MDQ.editRefresh)
    return true
  end
  -- ★「拖回原点」= 归零 ⇒ **把那一条删掉**（不留 `x=0 y=0` 的噪声条目）
  -- ★1.75.60d：**独立偏移量数据库（文件基线）上有值的块是唯一的例外** —— 删存档会**回落到文件值**
  --   （不是回原点！）⇒ 这种块必须**显式写 `{x=0,y=0}` 压住文件**（渲染索引会把文件那条一起摘掉）。
  local delN, keepN, shadowN = 0, 0, 0
  for _, mbr in ipairs(members) do
    local rec = MDQ.editRec(st.file, mbr.area, mbr.tile)
    local x = (rec ~= nil) and (tonumber(rec.x) or 0) or 0
    local y = (rec ~= nil) and (tonumber(rec.y) or 0) or 0
    -- ★1.75.60o：**尺寸补偿也算「这一条有东西」** —— 位置拖回原点时**不许把尺寸一起丢掉**
    --   （旧写法只看位置就整条删 ⇒ 用户辛苦调好的宽高会无声消失）。所以两条零分支分开：
    --     ① 位置归零但**尺寸还在** ⇒ 写 `x=0,y=0`（带上 dw/dh）保住尺寸，绝不删；
    --     ② 位置与尺寸**都**归零 ⇒ 照旧整条收掉（文件基线有值时写 0 影压住它）。
    local kdw = (rec ~= nil) and (tonumber(rec.dw) or 0) or 0
    local kdh = (rec ~= nil) and (tonumber(rec.dh) or 0) or 0
    local sizeKept = (math.abs(kdw) >= 0.05) or (math.abs(kdh) >= 0.05)
    if math.abs(x) < 0.5 and math.abs(y) < 0.5 then
      if sizeKept then
        if MDQ.editPut(st.file, mbr.area, mbr.tile, {
          x = 0, y = 0, dw = kdw, dh = kdh, bx = mbr.bx, by = mbr.by, bw = mbr.bw, bh = mbr.bh,
          k = st.k, es = st.es, coef = st.coef, src = st.src,
          sx = 0, sy = 0, sw = (tonumber(rec and rec.sw) or 0), sh = (tonumber(rec and rec.sh) or 0),
          t = (date and tostring(date("%m-%d %H:%M:%S")) or "?"),
        }) then delN = delN + 1 shadowN = shadowN + 1 keepN = keepN + 1 end
      elseif MDQ.editFileRec(st.file, mbr.area, mbr.tile) ~= nil then
        if MDQ.editPut(st.file, mbr.area, mbr.tile, {
          x = 0, y = 0, bx = mbr.bx, by = mbr.by, bw = mbr.bw, bh = mbr.bh,
          k = st.k, es = st.es, coef = st.coef, src = st.src, sx = 0, sy = 0,
          t = (date and tostring(date("%m-%d %H:%M:%S")) or "?"),
        }) then delN = delN + 1 shadowN = shadowN + 1 end
      else
        if MDQ.editDel(st.file, mbr.area, mbr.tile) then delN = delN + 1 end
      end
    else
      keepN = keepN + 1
    end
  end
  local rec0 = MDQ.editRec(st.file, st.area, st.tile)
  local x0 = (rec0 ~= nil) and (tonumber(rec0.x) or 0) or 0
  local y0 = (rec0 ~= nil) and (tonumber(rec0.y) or 0) or 0
  local mem0 = members[1]
  local fx = (tonumber(mem0 and mem0.bx) or 0) + x0
  local fy = (tonumber(mem0 and mem0.by) or 0) + y0
  local mine, tot = MDQ.editCount(st.file)
  if nMem > 1 then
    pcall(MDQ.editLogPut, string.format("补偿：地图=%s ｜ **整组 %d 块** ｜ 以 %s#%s 为例 表值 %s,%s ＋ 补偿 x=%+.1f y=%+.1f ⇒ **最终 %+.1f,%+.1f** ｜ 屏幕 %+.1f,%+.1f ｜ k=%.3f es=%.3f（%s）｜ 结束=%s",
      tostring(st.file), nMem, tostring(st.area), tostring(st.tile), tostring(mem0 and mem0.bx), tostring(mem0 and mem0.by),
      x0, y0, fx, fy, tonumber(rec0 and rec0.sx) or 0, tonumber(rec0 and rec0.sy) or 0,
      tonumber(st.k) or 1, tonumber(st.es) or 1, tostring(st.src), tostring(why)))
    say(string.format("世界迷雾·编辑：**整组 %d 块**补偿已记（以「%s#%d」为例 ⇒ 表值 %s,%s ＋ x=%+.1f y=%+.1f = **最终 %+.1f,%+.1f**）"
      .. " ｜ 归零 %d 块 ｜ 本图 %d 条 / 全部 %d 条（当时 k=%.3f es=%.3f，存 `worldFogCfg.edit`）",
      nMem, tostring(st.area), tonumber(st.tile) or 0, tostring(mem0 and mem0.bx), tostring(mem0 and mem0.by),
      x0, y0, fx, fy, delN, mine, tot, tonumber(st.k) or 1, tonumber(st.es) or 1))
  elseif keepN == 0 then
    say(string.format("世界迷雾·编辑：「%s#%d」已拖回原位 ⇒ 补偿归零%s",
      tostring(st.area), tonumber(st.tile) or 0,
      (shadowN > 0) and string.format("（%d 块在文件基线上 ⇒ **显式写 0 影**压住 `MapOverlayOffset.lua`，这一块回到原始表值）", shadowN) or "（记录删除）"))
  else
    pcall(MDQ.editLogPut, string.format("补偿：地图=%s ｜ %s#%s ｜ 表值 %s,%s ＋ 补偿 x=%+.1f y=%+.1f ⇒ **最终 %+.1f,%+.1f** ｜ 屏幕 %+.1f,%+.1f ｜ k=%.3f es=%.3f（%s）｜ 结束=%s",
      tostring(st.file), tostring(st.area), tostring(st.tile), tostring(mem0 and mem0.bx), tostring(mem0 and mem0.by),
      x0, y0, fx, fy, tonumber(rec0 and rec0.sx) or 0, tonumber(rec0 and rec0.sy) or 0,
      tonumber(st.k) or 1, tonumber(st.es) or 1, tostring(st.src), tostring(why)))
    say(string.format("世界迷雾·编辑：「%s#%d」补偿已记 ⇒ 表值 %s,%s ＋ **x=%+.1f y=%+.1f** = **最终 %+.1f,%+.1f**（表口径）"
      .. " ｜ 屏幕 %+.1f,%+.1f（当时 k=%.3f es=%.3f）｜ 本图 %d 条 / 全部 %d 条（存 `worldFogCfg.edit`，AI 直接读）",
      tostring(st.area), tonumber(st.tile) or 0, tostring(mem0 and mem0.bx), tostring(mem0 and mem0.by), x0, y0, fx, fy,
      tonumber(rec0 and rec0.sx) or 0, tonumber(rec0 and rec0.sy) or 0,
      tonumber(st.k) or 1, tonumber(st.es) or 1, mine, tot))
  end
  -- 松手刷一次列表（拖拽中故意不重建行文本 ⇒ 这里补上）
  if MDQ.panelFill ~= nil then pcall(MDQ.panelFill, tostring(st.file), tonumber(MDQ.lastRenderN) or 0) end
  -- ★1.75.60j（「关联操作」也要亮）：**松手之后**这一块继续亮一会儿 —— 光标可能已经移开，
  --   但那一下要能回答「我刚才调的是哪一块」（到点自己过期，节拍下一拍就收起来）。
  if st.moved == true then pcall(MDQ.focusFlash, tonumber(st.i) or 0, 1.4) end
  return true
end

MDQ.editStop = function(why)
  if type(MDQ.dragSt) == "table" then pcall(MDQ.editEnd, tostring(why or "停")) end
  wfCatcherShow(false)
  return true
end

-- 编辑模式开关（真值 = `worldFogCfg.editMode`，**写存档**；唯一写口）
MDQ.editOn = function()
  return (type(SM_CFG) == "table") and SM_CFG.editMode == true
end

-- ★★★1.75.60b：**视图开关改完当场刷一拍**（quiet + silent + withGuard = 与正常节流那一拍**同一条路**，一个字不打）。
--   ★为什么必须带 `withGuard = true`：「原始贴图层」那一格要藏 / 要还，**只有守护那一趟才做**——
--     不带护守地重画一遍，用户看到的就是「按钮点了、图没变」（守护没跑 = 没人去 Show/Hide）。
MDQ.editViewApply = function()
  if not MDQ.swm() then return false end
  local fv = _G["WorldMapDetailFrame"]
  if fv == nil then return false end
  local okv, esv = pcall(smEffScale, fv)
  if not (okv and tonumber(esv) and tonumber(esv) > 0) then return false end
  pcall(MDQ.renderCurrent, tonumber(esv), true, true, true)
  return true
end

-- ★1.75.60b：从命令串尾取「on / off / 开 / 关 / 显示 / 隐藏」三态（**取不到 = nil = 反转当前值**）。
--   ★照本项目既有写法：**两条字面量比较**，不写多字节字符集 `[...]`（那会把「：」这类首字节吃掉）。
MDQ.editArgOnOff = function(sub)
  local s = tostring(sub or "")
  local a = string.match(s, "%s(%S+)$")
  if a == nil then return nil end
  local w = string.lower(a)
  if w == "on" or a == "开" or a == "显示" then return true end
  if w == "off" or a == "关" or a == "隐藏" then return false end
  return nil
end

-- ★1.75.60b：视图开关的**唯一写口**（面板那两颗按钮 / 命令 / 将来任何入口都走它，绝不各写一半）。
--   `which` = "native" | "fog"；`v` = true / false / **nil = 反转当前值**。
MDQ.editViewSet = function(which, v)
  if which == "native" then
    local cur = (MDQ.showNative == true)
    local nv = cur
    if v == nil then nv = not cur else nv = (v == true) end
    MDQ.showNative = nv
  elseif which == "fog" then
    local cur = (MDQ.showFog ~= false)
    local nv = cur
    if v == nil then nv = not cur else nv = (v == true) end
    MDQ.showFog = nv
  else
    return false
  end
  pcall(MDQ.editViewApply)
  pcall(MDQ.panelViewPaint)
  return true
end

-- 视图开关的**一行状态**（体检 / 命令回显共用一份口径，不各写一套）
MDQ.editViewLine = function()
  return string.format("视图开关（只在编辑模式内生效 · **不落存档** · 关编辑模式即复位）："
    .. "原始贴图层 = **%s** ｜ 迷雾贴图层 = **%s** ｜ 迷雾透明度 = **%d%%**",
    (MDQ.showNative == true) and "显示" or "隐藏",
    (MDQ.showFog ~= false) and "显示" or "隐藏",
    (MDQ.fogAlphaPct ~= nil) and MDQ.fogAlphaPct() or 100)
end

-- ★★★1.75.60l（用户：「编辑模式可以在迷雾贴图列表内设置迷雾贴图的透明度,统一设置全部贴图的透明度,
--   方便和地图原始层对照」）：**迷雾贴图统一透明度**（会话态，与两个视图开关同一把尺子）。
--   ★为什么是「循环档 + 命令给精确值」而不是滑条：1.12 **没有原生 Slider**（项目配方），自制轨道+拇指
--     在这个窄面板里既挤又难拖；这两条路加起来才是「一键就能对照」的最短路径。
MDQ.fogAlpha = 1                                              -- 唯一真值：1 = 不透明（默认）
MDQ.fogAlphaN = 0                                             -- 上一趟真写了几个 SetAlpha（体检/判据用）
MDQ.FOG_ALPHA_STEPS = { 1.00, 0.75, 0.50, 0.25, 0.10, 0.00 }  -- 面板那颗按钮的循环档
MDQ.fogAlphaPct = function()
  local v = tonumber(MDQ.fogAlpha) or 1
  if v < 0 then v = 0 end
  if v > 1 then v = 1 end
  return math.floor(v * 100 + 0.5)
end
-- 「这个 alpha 是不是**我们自己设的**迷雾透明度」（守护的取证行靠它避免误报；读不到 ⇒ false = 照旧说实话）
MDQ.alphaIsOurs = function(a)
  if not (MDQ.editOn and MDQ.editOn()) then return false end
  local fa = tonumber(MDQ.fogAlpha) or 1
  if fa >= 0.999 then return false end
  local v = tonumber(a)
  if v == nil then return false end
  return math.abs(v - fa) < 0.02
end
-- 唯一写口（面板那颗按钮 / 命令 `/ehm mapfit 编辑 透明度 <0-100>` 都走它 ⇒ 不会各写一半）
MDQ.fogAlphaSet = function(v)
  -- ★口径（用户 1.75.60l 补充原话：「**这个设置只在编辑模式生效**」）：这是**编辑模式内的视图开关**
  --   （同两个视图开关 / 逐块隐藏同一把尺子）⇒ 非编辑模式里**直接拒绝**，并**如实说**
  --   （绝不静默改一个「下次开编辑模式才生效」的值 —— 那样用户会以为「命令没反应」）。
  if not (MDQ.editOn and MDQ.editOn()) then return false, "editoff" end
  local n = tonumber(v)
  if n == nil then return false, "bad" end
  if n > 1 then n = n / 100 end      -- 认「50」= 50%
  if n < 0 then n = 0 end
  if n > 1 then n = 1 end
  MDQ.fogAlpha = n
  MDQ.fogAlphaN = 0
  pcall(MDQ.editRefresh)             -- 立刻重申（走编辑模式那条 silent 渲染路；写前比对 ⇒ 稳态零写）
  pcall(MDQ.panelAlphaPaint)
  return true
end
-- 面板按钮：**左键循环预设档**（100 → 75 → 50 → 25 → 10 → 0 → 100）；`dir` < 0 = 反向
MDQ.fogAlphaStep = function(dir)
  local cur = tonumber(MDQ.fogAlpha) or 1
  local steps = MDQ.FOG_ALPHA_STEPS
  local ns = table.getn(steps)
  local idx = 1
  for i = 1, ns do if math.abs(steps[i] - cur) < 0.005 then idx = i break end end
  local d = ((tonumber(dir) or 1) >= 0) and 1 or -1
  idx = idx + d
  if idx > ns then idx = 1 end
  if idx < 1 then idx = ns end
  pcall(MDQ.fogAlphaSet, steps[idx])
  return steps[idx]
end
-- 面板那一行文案/颜色（由 `panelFill` **每拍**调一次 ⇒ 幂等、永远等于真值；同 `panelViewPaint` 的口径）。
--   ★< 100% 用亮黄点出来（「现在不是不透明」这件事必须一眼看见，否则用户会以为贴图坏了）。
MDQ.panelAlphaPaint = function()
  local p = MDQ.panel
  if p == nil or p.bAlpha == nil or p.bAlpha.fs == nil then return false end
  local pct = MDQ.fogAlphaPct()
  pcall(p.bAlpha.fs.SetText, p.bAlpha.fs, L("WF_EDIT_ALPHA") .. "：" .. tostring(pct) .. "%")
  if pct < 100 then pcall(p.bAlpha.fs.SetTextColor, p.bAlpha.fs, 1.00, 0.86, 0.35)
  else pcall(p.bAlpha.fs.SetTextColor, p.bAlpha.fs, 0.78, 0.88, 1.00) end
  return true
end

MDQ.editSet = function(on, quiet)
  on = on and true or false
  SM_CFG.editMode = on
  if not on then
    pcall(MDQ.editStop, "编辑模式已关")
    pcall(MDQ.grabHideAll, "编辑模式已关")
    -- ★★★1.75.60b：两个视图开关**当场复位**（原始隐藏 / 迷雾显示 = 常态）并**立刻刷一拍** ——
    --   不复位就会留下脏状态：「关掉编辑模式后地图上还多着客户端原生层」或「我们的块全没了」。
    --   ★复位 + 刷一拍都必须排在这里（`grabHideAll` 之后、`editRefresh` 之前），
    --     否则这一拍按旧标志渲染 ⇒ 恢不回来。
    -- ★1.75.60e：**逐块隐藏集也当场清空**（排查动作，跟编辑模式走；刷一拍会把藏着的块放回来）
    MDQ.showNative, MDQ.showFog = false, true
    -- ★1.75.60l：**迷雾贴图统一透明度也是会话态** ⇒ 关编辑模式当场复位成不透明
    --   （不复位 = 关掉编辑模式后迷雾贴图还是半透明，用户会以为「贴图坏了」；下面那次 editViewApply 会把它写回 1）
    MDQ.fogAlpha, MDQ.fogAlphaN = 1, 0
    MDQ.blkHide = {}
    MDQ.flashIdx, MDQ.flashAt = nil, 0    -- ★1.75.60j：关联操作的高亮态也清（会话状态，关掉不带走）
    pcall(MDQ.editViewApply)
  end
  pcall(MDQ.editRefresh)
  if type(MDQ.beatSync) == "function" then pcall(MDQ.beatSync) end
  if not quiet then
    if on then
      say("世界迷雾·编辑模式 = **开**：地图上**默认不画框**（干净），只有那一块的**序号**标着；鼠标移到**哪一块 / 列表哪一行**（或列表点击选中、拖拽中）⇒ 那一块的**边框亮起来**。按住拖动微调位置（拖拽中**任意位置右键 = 释放**；列表行右键 = 这一块显示/隐藏；列表行前的**红 ×** = 重置这一条）。")
      say("　★编辑模式下地图的点击会被拖拽柄吃掉（拖完请把编辑模式关掉）；补偿量存 `worldFogCfg.edit`，随时再开都能继续调。")
      say("　★**选中图层**（右侧列表点一行 / 图上点一下）后 ⇒ 列表**底部那一排四个箭头**（↑ ↓ ← →）**点一下 = 1 像素微调**（按住 Shift 点 = 10 像素）；整组选中就一起动（箭头是**灰**的 = 一块都没选中）。")
    else
      say("世界迷雾·编辑模式 = **关**：拖拽柄已全部收起、拖拽当场结束。**补偿量保留**（存 `worldFogCfg.edit`）。")
    end
  end
  return true
end

-- 立刻把柄铺一遍（不重画地图时就靠它；走的是与节拍同一条 silent 路，写前比对 ⇒ 稳态零写）
MDQ.editRefresh = function()
  if not MDQ.editOn() then return MDQ.grabHideAll("编辑模式关") end
  if not MDQ.swm() then return MDQ.grabHideAll("世界迷雾关") end
  local fr = _G["WorldMapDetailFrame"]
  if fr == nil then return MDQ.grabHideAll("地图框不在") end
  local ok, es = pcall(smEffScale, fr)
  if not (ok and tonumber(es) and tonumber(es) > 0) then return MDQ.grabHideAll("读不到外框缩放") end
  pcall(MDQ.renderCurrent, tonumber(es), true, true, false)
  return true
end

-- 取证口（`/ehm mapfit 编辑` + 自检 `[9]` 段共用）
MDQ.editLines = function()
  local out = {}
  local file = tostring(select(1, smMapInfo()) or "")
  local mine, tot = MDQ.editCount(file)
  table.insert(out, string.format("迷雾补偿（编辑模式）：开关=%s ｜ 地图=%s ｜ **本图 %d 条 / 全部 %d 条** ｜ 存 `worldFogCfg.edit`",
    MDQ.editOn() and "开" or "关", (file ~= "" and file or "?"), mine, tot))
  table.insert(out, "　口径：**最终坐标 = `MapOverlayData.lua` 的表值 + 补偿**（`x,y` = 表口径，正 x 右 / 正 y 下，"
    .. "与表的 offsetX/offsetY 同符号）⇒ 写进客户端 = ((表值+补偿) × k)；屏幕位移 = 补偿 × k × es"
    .. "（每条都带当时的 k / es / coef / 原始屏幕位移 / **拖时的表值** ⇒ 换缩放级别与表重生都能核对）")
  -- ★1.75.60b：两个视图开关的当前状态（编辑模式里最常问的一句「现在屏上是哪一层」）
  table.insert(out, "　" .. MDQ.editViewLine())
  -- ★1.75.60n：箭头微调的状态（体检里第二常问的一句：「为什么点了没反应」）
  table.insert(out, "　" .. MDQ.nudgeLine())
  -- ★1.75.60o：尺寸那一排的状态（同族第二问：「为什么宽高调不动」）
  table.insert(out, "　" .. MDQ.sizeLine())
  -- ★★★1.75.60r：**面板 / 保存确认窗 / 鼠标焦点的层级体检**（真机「按钮点不动」这类问题一句话定位是谁盖住了它）
  table.insert(out, "　" .. MDQ.panelDiagLine())
  -- ★1.75.60d：**独立偏移量数据库** `MapOverlayOffset.lua`（文件基线；与存档增量一起生效，存档优先）
  local fMine, fTot = MDQ.editFileCount(file)
  table.insert(out, string.format("　★**独立偏移量数据库** `MapOverlayOffset.lua`：本图 **%d 条** / 全部 %d 条"
    .. "（生成物，`node gen_mapoffset.js` 从存档导出 ⇒ 别的玩家开箱就是矫正好的贴图；"
    .. "存档里同键的后续微调**优先**；清存档 ⇒ 回落文件基线）", fMine, fTot))
  -- ★1.75.60m（用户：「重置也能重置插件的偏移量，不单是用户自定义的偏移量；（单）项重置也要支持」）
  table.insert(out, "　★**两级重置**：`重置本图/重置全部` = 只清**存档增量**（⇒ 回落**插件基线**）；"
    .. "`重置本图（含插件）/重置全部（含插件）` = 把插件基线那几条也写成**存档 0 影**（⇒ 回 `MapOverlayData.lua` **原始表值**，可逆）；"
    .. "**单块**同一件事 = 列表行红 × 的**右键**（左键只清你自己的增量）。★想让别人也拿到这份重置：跑一次 `gen_mapoffset.js`（0 影 = 从库里删除）")
  -- 配对体检（与 MapOverlayData.lua 对不上的一律不生效）
  local jn = MDQ.editJoin(file)
  table.insert(out, string.format("　★配对 `MapOverlayData.lua`：本图 %d 条 ⇒ **命中 %d** ｜ 孤儿（查不到 ⇒ 不生效）%d ｜ 基础表已变 %d",
    tonumber(jn.n) or 0, tonumber(jn.hit) or 0, tonumber(jn.orphan) or 0, tonumber(jn.drifted) or 0))
  for _, l in ipairs(jn.items or {}) do table.insert(out, l) end
  local t = (type(SM_CFG) == "table") and SM_CFG.editLog or nil
  if type(t) == "table" and table.getn(t) > 0 then
    table.insert(out, string.format("　落盘历史（`worldFogCfg.editLog`，最多 %d 条，最新在前）：", tonumber(MDQ.EDIT_LOG_MAX) or 40))
    for i = 1, math.min(8, table.getn(t)) do table.insert(out, "　　" .. tostring(t[i])) end
  end
  return out
end

-- ============ ★★★1.75.59p：**编辑模式的贴图列表**（地图右侧 · 多选 · 只在编辑模式用）============
-- 用户要求：「编辑模式需要再地图右侧添加个简单的迷雾纹理贴图列表.方便选取拖拽,支持多选.这个列表只在编辑模式使用」
-- 口径四条：
--   ① **列表内容 = 本拍我们自己画出来的那几块**（顺序 = 池位号 = 区域名排序后的行优先块序，与渲染逐块对齐）；
--      一行 = `序号. 区域#块号`，已有补偿的补一个 `（x+1.0 y-2.0）`，选中的行前面 `▶` + 金色。
--   ② **多选接到拖拽上**（这是本列表存在的理由）：选中的那几块在图上**换成青色高亮**，
--      拖其中任意一块 ⇒ **整组一起动**（每块各记自己那条补偿）；**没选任何一块 ⇒ 只拖点中的那一块**
--      ⇒ 用户要的「每块单独拖」与「多选整组」两条路都在，且**数据始终是逐块一条**（配对与读取都不变）。
--   ③ **滚动 = 本项目唯一标准（连续窗口）**：`off` = 行偏移 · 滚轮**逐行** · 双侧夹 `0..max(0, n-cap)` ·
--      容量恒定 · 计数器常显 · 滚轮**链式接管**（不是我们吃的就交回上一个处理体）。
--   ④ **只在编辑模式显示**：帧建一次、之后只 `Show`/`Hide`（1.12 **没有销毁帧/纹理的 API** —— 如实记在这里）；
--      ★列表**不写地图**：它只改「选中集」与「补偿表」，写地图永远只有渲染那一条路（一处真值）。
--   ★位置：优先贴在地图框**右侧**；右侧放不下（屏幕边）⇒ 翻到**左侧**（越界回归纪律）。
--     判据用的是 `UIParent` 的宽度与地图框的 `GetRight`（两者都在各自的 UI 坐标空间里，
--     本客户端这两者口径一致；万一不一致 ⇒ 最坏结果是列表落在左边，**不影响任何数据**）。
MDQ.sel = {}          -- 选中集：`区域#块号` → true（**按身份**存，不按池位号 ⇒ 重渲染/换图都指不错块）
MDQ.PANEL_W = 196
MDQ.PANEL_ROW_H = 14
MDQ.PANEL_CAP = 16
-- ★1.75.60o：按钮排的间距与排数（原先是写死的 22 / 硬编码总高 184）——
--   多了一排「尺寸」之后用**行距**把总高拉回来（22 → 20）⇒ 面板只比原来高 4 像素。
MDQ.PANEL_BTN_H = 20
MDQ.PANEL_BTN_ROWS = 10   -- ★1.75.60p：末尾又加了一排「保存」（见 panelBuild）
MDQ.panelOff = 0

MDQ.selKey = function(a, t) return MDQ.editRowKey(a, t) end
MDQ.selHas = function(a, t) return MDQ.sel[MDQ.selKey(a, t)] == true end
MDQ.selToggle = function(a, t)
  local k = MDQ.selKey(a, t)
  if MDQ.sel[k] == true then MDQ.sel[k] = nil return false end
  MDQ.sel[k] = true
  return true
end
-- ★★★1.75.60t（用户：「迷雾贴图->图层在地图内按住 shift + 左键点击才是多选,不产生拖拽位移效果,只是多选;
--   默认点击是单选」）：**地图内的选中语义只在这三个小口里定义**，别处不许再自己写一份。
--   · `shiftDown` = Shift **现读**（API 不在 / 读不到 ⇒ false ⇒ 当成「没按」，绝不当成按着）；
--   · `selOnly`  = **单选**（清空后只留这一块）；
--   · `selAfterChange` = 选中集变了的**统一收尾**（列表刷新 + 图上高亮刷新；列表点选 / 地图单选 / Shift 多选共用）。
--   ★1.75.60v：地图内两条左键路 = **未选中 ⇒ 只选中（绝不起拖）** / **已选中 ⇒ 起拖**（见 `editBegin`）。
MDQ.shiftDown = function()
  if type(IsShiftKeyDown) ~= "function" then return false end
  local ok, v = pcall(IsShiftKeyDown)
  return (ok and (v == true or v == 1)) and true or false
end
-- ★1.75.60v（用户：「只有选中的图片才支持左键拖拽移动,防止误点击拖拽图层」）：**左键按在未选中的块上 = 只选中**，
--   那一下**不起拖**（见 `editBegin`）⇒ 必须如实说清「下一步怎么拖」，否则用户会以为「左键坏了」。
--   ★连点不同块会连发 ⇒ 聊天回显**限频**（`PICK_SAY_SEC` = 0.6s 一行，同 `NUDGE_SAY_SEC` 的手法）：
--     实时反馈本来就是**图上那一下青色高亮**，聊天行只是「为什么没动」的解释。
MDQ.PICK_SAY_SEC = 0.6
MDQ.pickSayAt = 0
MDQ.selOnly = function(a, t)
  MDQ.sel = {}
  MDQ.sel[MDQ.selKey(a, t)] = true
  return true
end
MDQ.selAfterChange = function()
  local file = tostring(select(1, smMapInfo()) or "")
  if type(MDQ.panelFill) == "function" then MDQ.panelFill(file, tonumber(MDQ.lastRenderN) or 0) end
  pcall(MDQ.editRefresh)      -- 图上的青色高亮跟着变（silent 渲染那条路，写前比对 ⇒ 稳态零写）
  return true
end
MDQ.selCount = function()
  local n = 0
  for _ in pairs(MDQ.sel) do n = n + 1 end
  return n
end
MDQ.selInit = function() MDQ.sel = {} return true end
-- 把本图**本拍渲染出来的**块全部选中（返回选了几个）
MDQ.selAll = function()
  local n = 0
  for i = 1, tonumber(MDQ.lastRenderN) or 0 do
    local sg = MDQ.slot[i]
    if sg ~= nil then
      if MDQ.sel[sg.area .. "#" .. tostring(sg.tile)] ~= true then
        MDQ.sel[sg.area .. "#" .. tostring(sg.tile)] = true
        n = n + 1
      end
    end
  end
  return n
end

-- 归零**选中**的那些块（删除补偿记录；只动补偿表，不动图层几何 —— 几何由下一拍渲染自己跟上）
-- ★1.75.60d：返回 (删了几条, 其中有几块**回落到文件基线**) —— 独立偏移量数据库（文件）上有值的块，
--   删存档后显示的是**文件值**（不是 0），这句必须如实说出来（不然用户看到「归零了却还在动」）。
MDQ.selZero = function(file)
  local n, fb = 0, 0
  for i = 1, tonumber(MDQ.lastRenderN) or 0 do
    local sg = MDQ.slot[i]
    if sg ~= nil and MDQ.selHas(sg.area, sg.tile) then
      if MDQ.editDel(file, sg.area, sg.tile) then
        n = n + 1
        if MDQ.editFileRec(file, sg.area, sg.tile) ~= nil then fb = fb + 1 end
      end
    end
  end
  return n, fb
end

-- ============ ★★★1.75.60e：**逐块显示/隐藏**（列表行**右键** = 快速藏/放这一块，排查用）============
-- 用户：「世界迷雾编辑模式->迷雾贴图右键列表项可以快速设置这个层的显示和隐藏.方便排查」
-- ★三条口径（与两个视图开关同一把尺子）：
--   ① **只改显示，不改任何数据**（补偿表 / 渲染几何一个字都不动）—— 藏的是「这一块贴图」，
--      金色拖拽柄与序号角标**照旧留着**（藏了还要能点回来、能认出来是哪块）；
--   ② **不落存档**：这是排查用的视图开关 ⇒ 只存会话；**换图清空 + 关编辑模式清空**（绝不留「上张图藏过」的残留）；
--   ③ ★★★**守护与渲染都要让它**：渲染收尾把集合里的块 `Hide`（几何照写、账照记）；
--      守护的存在性复位**不许**把用户故意藏着的块 `Show` 回来（故意藏着的 ≠ 被误藏，同 1.75.60b 那条）。
MDQ.blkHide = {}          -- 逐块隐藏集：`区域#块号` → true（与选中集同键 ⇒ 重渲染/换图都指不错块）
MDQ.blkHidden = function(a, t) return MDQ.blkHide[MDQ.selKey(a, t)] == true end
MDQ.blkToggle = function(a, t)
  local k = MDQ.selKey(a, t)
  if MDQ.blkHide[k] == true then MDQ.blkHide[k] = nil return false end
  MDQ.blkHide[k] = true
  return true
end
MDQ.blkHideInit = function() MDQ.blkHide = {} return true end
-- 按**池位号**查这一块是不是被用户藏了（守护 / 渲染共用；读不到槽位 ⇒ false ⇒ 不藏）
MDQ.blkHiddenIdx = function(i)
  local sg = MDQ.slot[tonumber(i) or 0]
  if sg == nil then return false end
  return MDQ.blkHidden(sg.area, sg.tile)
end
MDQ.blkHideCount = function()
  local n = 0
  for _ in pairs(MDQ.blkHide) do n = n + 1 end
  return n
end

MDQ.panelHide = function(why)
  local p = MDQ.panel
  if p ~= nil then pcall(p.Hide, p) end
  if type(MDQ.grabHideAll) == "function" and type(MDQ.dragSt) == "table" then
    pcall(MDQ.editStop, tostring(why))
  end
  return true
end

-- ★★★1.75.60r（真机报障「保存（写盘 + 重载）无法点击」）：**层级 / 鼠标焦点体检的三个小助手**。
--   为什么要有它们：按钮「看不见问题、点了没反应」只有两类原因 —— ① 点击被**别的帧**吃掉（鼠标底下另有其人）、
--   ② 点击到了、但**我们要显示的东西在下面**（层级别别的帧盖住）。这两种用同一句话就能分开：
--   `鼠标焦点 = 谁` + `各帧 strata/level 各是几`。★全部 pcall 包住（老客户端可能没有 GetMouseFocus /
--   GetFrameStrata）⇒ 读不到一律如实回 "?"，**绝不因为体检而报错**（体检口自己不能成为新的故障源）。
MDQ.frameDiagField = function(obj, meth)
  if obj == nil or meth == nil then return "?" end
  local ok1, fn = pcall(function() return obj[meth] end)
  if not (ok1 and type(fn) == "function") then return "?" end
  local ok2, v = pcall(fn, obj)
  if not (ok2 and v ~= nil) then return "?" end
  return tostring(v)
end
MDQ.frameDiagShown = function(obj)
  local v = MDQ.frameDiagField(obj, "IsShown")
  if v == "true" or v == "1" then return "显示中" end
  if v == "false" or v == "0" then return "收起" end
  return "?"
end
-- 「鼠标底下的最上层帧」= `GetMouseFocus()`（1.12 就有）—— 它若不是我们的面板/按钮，就是它吃掉了点击。
MDQ.frameDiagFocus = function()
  if type(GetMouseFocus) ~= "function" then return "?" end
  local ok, mo = pcall(GetMouseFocus)
  if not (ok and mo ~= nil) then return "?" end
  local nm = MDQ.frameDiagField(mo, "GetName")
  if nm == "?" or nm == "" then nm = "匿名帧" end
  return string.format("%s（strata=%s level=%s）", nm,
    MDQ.frameDiagField(mo, "GetFrameStrata"), MDQ.frameDiagField(mo, "GetFrameLevel"))
end
-- 体检的一行：面板 / 保存确认窗 / 地图框三者的显隐与层级 + **鼠标焦点**（`/ehm mapfit 编辑` 里打印）
MDQ.panelDiagLine = function()
  local p = MDQ.panel
  local ask = rawget(_G, "EVAL_RELOAD_ASK_FRAME")
  local mfr = _G["WorldMapDetailFrame"]
  return string.format("编辑面板：%s（strata=%s level=%s）｜ 保存确认窗：%s（strata=%s level=%s）｜ 地图框：strata=%s level=%s ｜ **鼠标焦点** = %s（★它若是个全屏接盘 / 别的窗，就是它吃掉了点击）",
    MDQ.frameDiagShown(p), MDQ.frameDiagField(p, "GetFrameStrata"), MDQ.frameDiagField(p, "GetFrameLevel"),
    MDQ.frameDiagShown(ask), MDQ.frameDiagField(ask, "GetFrameStrata"), MDQ.frameDiagField(ask, "GetFrameLevel"),
    MDQ.frameDiagField(mfr, "GetFrameStrata"), MDQ.frameDiagField(mfr, "GetFrameLevel"),
    MDQ.frameDiagFocus())
end

MDQ.panelBuild = function()
  if MDQ.panel ~= nil then return MDQ.panel end
  if type(CreateFrame) ~= "function" then return nil end
  local fr = _G["WorldMapDetailFrame"]
  if fr == nil then return nil end
  local p = CreateFrame("Frame", "EVAL_WF_EDITLIST", fr)
  if p == nil then return nil end
  pcall(p.SetWidth, p, MDQ.PANEL_W)
  -- ★高度要装下：标题 26 + 行 cap*ROW_H + 按钮**九排**（9*20）+ 余量
  --   （★1.75.60n 第一排 = **位置箭头**（紧贴列表下沿 ⇒ 点它时眼睛还停在列表上）·
  --    ★1.75.60o 第二排 = **尺寸**（宽−/宽+/高−/高+，只对单选生效）· 第三排 = 选中集操作 ·
  --    第四排 = 重置清理 · ★1.75.60b 第五/六排 = 两个**视图开关** ·
  --    ★1.75.60l 第七排 = **迷雾贴图统一透明度** · ★1.75.60m 第八/九排 = **含插件基线的重置** ·
  --    ★1.75.60p 第十排 = **保存（写盘 + /reload）**）
  pcall(p.SetHeight, p, 26 + MDQ.PANEL_ROW_H * MDQ.PANEL_CAP + MDQ.PANEL_BTN_ROWS * MDQ.PANEL_BTN_H + 8)
  pcall(p.SetPoint, p, "TOPLEFT", fr, "TOPRIGHT", 8, 0)
  if type(p.SetFrameStrata) == "function" then pcall(p.SetFrameStrata, p, "FULLSCREEN") end
  local lv = 1
  if type(fr.GetFrameLevel) == "function" then
    local okv, v = pcall(fr.GetFrameLevel, fr)
    if okv and tonumber(v) then lv = tonumber(v) end
  end
  if type(p.SetFrameLevel) == "function" then pcall(p.SetFrameLevel, p, lv + 6) end
  if type(p.EnableMouse) == "function" then pcall(p.EnableMouse, p, true) end
  p.lv = lv + 6
  -- 暗底（不透明 ⇒ 地图不会透上来把字看花）
  local bg = p:CreateTexture(nil, "BACKGROUND")
  if bg ~= nil then
    pcall(bg.SetTexture, bg, "Interface\\Buttons\\WHITE8X8")
    pcall(bg.SetVertexColor, bg, 0.05, 0.05, 0.07)
    pcall(bg.SetAlpha, bg, 0.92)
    pcall(bg.SetAllPoints, bg)
  end
  p.bg = bg
  -- 标题 + 计数器
  local function mkFS(parent, pt, rpt, x, y, just)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if fs == nil then return nil end
    if type(fs.SetFontObject) == "function" then pcall(fs.SetFontObject, fs, _G["GameFontHighlightSmall"]) end
    pcall(fs.SetPoint, fs, pt, parent, rpt, x, y)
    if just ~= nil and type(fs.SetJustifyH) == "function" then pcall(fs.SetJustifyH, fs, just) end
    return fs
  end
  p.title = mkFS(p, "TOPLEFT", "TOPLEFT", 6, -6, "LEFT")
  if p.title ~= nil then pcall(p.title.SetTextColor, p.title, 1.00, 0.82, 0.25) end
  p.cnt = mkFS(p, "TOPLEFT", "TOPLEFT", 6, -20, "LEFT")
  if p.cnt ~= nil then pcall(p.cnt.SetTextColor, p.cnt, 0.75, 0.75, 0.75) end
  -- 行（按钮；★纹理/字体串不吃鼠标 ⇒ 必须用 Button）
  p.rows = {}
  for i = 1, MDQ.PANEL_CAP do
    local rb = CreateFrame("Button", nil, p)
    if rb == nil then break end
    pcall(rb.SetWidth, rb, MDQ.PANEL_W - 12)
    pcall(rb.SetHeight, rb, MDQ.PANEL_ROW_H)
    pcall(rb.SetPoint, rb, "TOPLEFT", p, "TOPLEFT", 6, -(24 + (i - 1) * MDQ.PANEL_ROW_H))
    -- ★抬高父帧不带动子件（本项目弹层两条硬事实）⇒ 行必须逐个 `SetFrameLevel`
    if type(rb.SetFrameLevel) == "function" then pcall(rb.SetFrameLevel, rb, (p.lv or 1) + 4) end
    -- ★1.75.60i：行文字缩进到 16 —— 左边距留给「单独重置」的红 ×（见下）；缩进对所有行一致 ⇒ 选中时不会跳
    local fs = mkFS(rb, "LEFT", "LEFT", 16, 0, "LEFT")
    if fs ~= nil then pcall(fs.SetTextColor, fs, 0.83, 0.83, 0.83) end
    rb.fs = fs
    rb.idx = i
    -- ★1.75.60e：行注册**双键** —— 左键 = 选中/取消（多选整组拖）；**右键 = 这一块贴图的显示/隐藏**（排查用）
    if type(rb.RegisterForClicks) == "function" then
      pcall(rb.RegisterForClicks, rb, "LeftButtonUp", "RightButtonUp")
    end
    rb:SetScript("OnClick", function(a2, b2)
      local btn = wfMouseBtn(a2, b2)          -- ★本客户端把键放全局 arg1（1.75.59b 真机教训 ⇒ 三处取）
      if btn == "RightButton" then MDQ.panelHideOne(i) else MDQ.panelPick(i) end
    end)
    rb:SetScript("OnEnter", function()
      if rb.fs ~= nil then pcall(rb.fs.SetTextColor, rb.fs, 1, 1, 1) end
      -- ★1.75.59q：悬停行 ⇒ **图上对应那一块的框换亮白黄**（用户点名要的「列表单元鼠标悬浮.高亮对应纹理框颜色」）。
      --   ★1.75.60f：改走**唯一实现** `MDQ.hoverMap`（图上悬浮序号 / 边框也是这一份）⇒ 一份悬停状态、一处实现。
      MDQ.hoverMap((tonumber(MDQ.panelOff) or 0) + rb.idx, true)
    end)
    rb:SetScript("OnLeave", function()
      MDQ.hoverMap((tonumber(MDQ.panelOff) or 0) + rb.idx, false)
      MDQ.panelFill(tostring(select(1, smMapInfo()) or ""), tonumber(MDQ.lastRenderN) or 0)
    end)
    -- ★★★1.75.60i：行内「**单独重置**」红 ×（用户：「单[独]数据重置.在列表点选择某个一条之后.在它前面添加个 x
    --   红色按钮.点击则重置这条数据」）。★它现在是**单块归零的唯一入口**（右键已退出数据面，见 `MDQ.zeroOne`）。
    --   ★显示条件 = **已选中 ∧ 这一行有你自己的存档增量**（由 `panelFill` 每拍现算）：值来自文件基线时
    --     点它无事可做 ⇒ 宁可不摆一个「点了没反应」的红钮（那种行由行尾 `｜文件` 标记说明来历）。
    --   ★几何 = 左边距的**独立小按钮**（13×14）+ 行文字缩进到 16 ⇒ 「点行选中」的点击落在文字区，
    --     不会顺手命中红 ×（这正是它敢用**一次点击**的前提；批量清理那两颗按钮照旧两次确认）。
    --   ★必须**高于行**的 frame level（抬高父帧不带动子件 —— 本项目弹层两条硬事实）。
    local rst = CreateFrame("Button", nil, rb)
    if rst ~= nil then
      pcall(rst.SetWidth, rst, 13)
      pcall(rst.SetHeight, rst, MDQ.PANEL_ROW_H)
      pcall(rst.SetPoint, rst, "LEFT", rb, "LEFT", 1, 0)
      if type(rst.SetFrameLevel) == "function" then pcall(rst.SetFrameLevel, rst, (p.lv or 1) + 6) end
      if type(rst.EnableMouse) == "function" then pcall(rst.EnableMouse, rst, true) end
      -- ★1.75.60m：**左右键两个含义**（本项目铁律：光注册左键 ⇒ 右键永远到不了分派代码）
      if type(rst.RegisterForClicks) == "function" then
        pcall(rst.RegisterForClicks, rst, "LeftButtonUp", "RightButtonUp")
      end
      local rbg = rst:CreateTexture(nil, "BACKGROUND")
      if rbg ~= nil then
        pcall(rbg.SetTexture, rbg, "Interface\\Buttons\\WHITE8X8")
        pcall(rbg.SetVertexColor, rbg, 0.34, 0.04, 0.04)
        pcall(rbg.SetAllPoints, rbg)
      end
      local rfs = mkFS(rst, "CENTER", "CENTER", 0, 0, "CENTER")
      if rfs ~= nil then
        pcall(rfs.SetText, rfs, "×")
        pcall(rfs.SetTextColor, rfs, 1.00, 0.32, 0.32)
      end
      rst:SetScript("OnClick", function(a, b)
        wfEcho()                               -- ★用户点我们的界面 = 他主动问的 ⇒ 盖章（不受「调试日志」挡）
        -- ★1.75.60m（用户：「（单）项重置也要支持」）：**左键 = 只清你自己的增量**（⇒ 回落插件基线）；
        --   **右键 = 连插件偏移量一起清**（写 0 影 ⇒ 回 `MapOverlayData.lua` 原始表值）。
        --   ★鼠标键按本项目 idiom 从 a / b / 全局 arg1 三处取（只读 a/b = 本客户端会把右键当左键）
        local btn = wfMouseBtn(a, b)
        pcall(MDQ.panelZeroOne, i, btn == "RightButton")
      end)
      -- ★悬停红 × 时行与图上的高亮照旧（走同一个 `hoverMap`）⇒ 鼠标移到 × 上不会把悬停态闪掉
      rst:SetScript("OnEnter", function()
        if rbg ~= nil then pcall(rbg.SetVertexColor, rbg, 0.62, 0.08, 0.08) end
        MDQ.hoverMap((tonumber(MDQ.panelOff) or 0) + rb.idx, true)
        -- ★1.75.60m：**左右键两个含义必须写在悬停提示里**（右键是更深一层 —— 破坏性动作不许只靠猜）
        local tip = _G["GameTooltip"]
        if tip ~= nil and type(tip.SetOwner) == "function" and type(tip.AddLine) == "function" then
          if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
          pcall(tip.SetOwner, tip, rst, "ANCHOR_RIGHT")
          pcall(tip.AddLine, tip, L("WF_EDIT_RST_L"), 1.00, 0.62, 0.62)
          pcall(tip.AddLine, tip, L("WF_EDIT_RST_R"), 1.00, 0.82, 0.35)
          pcall(tip.Show, tip)
        end
      end)
      rst:SetScript("OnLeave", function()
        if rbg ~= nil then pcall(rbg.SetVertexColor, rbg, 0.34, 0.04, 0.04) end
        MDQ.hoverMap((tonumber(MDQ.panelOff) or 0) + rb.idx, false)
        local tip = _G["GameTooltip"]
        if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
      end)
      pcall(rst.Hide, rst)
      rb.rst = rst
    end
    pcall(rb.Hide, rb)
    p.rows[i] = rb
  end
  -- 动作按钮**两排**（★1.75.59p 二改：用户「图层列表增加重置清理.全选等操作」）：
  --   ★1.75.60n/o 起整块下移两排（最上面两排让给**位置箭头**与**尺寸**，见上）
  --   第三排 = 选中集操作：全选 / 全清 / 归零选中
  --   第四排 = **重置清理**（清补偿表）：重置本图 / 重置全部
  --   ★破坏性动作走**两次点击确认**（不另建弹窗：按钮自己变成「再点确认」+ 聊天里说明清几条，
  --     3 秒内不再点就自动解除）—— 1.12 没有销毁帧的 API，弹窗要长期常驻，这个更省也更不容易误触。
  local function mkBtn(label, xoff, w, row, fn)
    local btn = CreateFrame("Button", nil, p)
    if btn == nil then return nil end
    pcall(btn.SetWidth, btn, tonumber(w) or 58)
    pcall(btn.SetHeight, btn, 18)
    local y = -(24 + MDQ.PANEL_ROW_H * MDQ.PANEL_CAP + 6 + (tonumber(row) or 0) * (tonumber(MDQ.PANEL_BTN_H) or 20))
    pcall(btn.SetPoint, btn, "TOPLEFT", p, "TOPLEFT", xoff, y)
    if type(btn.SetFrameLevel) == "function" then pcall(btn.SetFrameLevel, btn, (p.lv or 1) + 4) end
    if type(btn.EnableMouse) == "function" then pcall(btn.EnableMouse, btn, true) end
    local b = btn:CreateTexture(nil, "BACKGROUND")
    if b ~= nil then
      pcall(b.SetTexture, b, "Interface\\Buttons\\WHITE8X8")
      pcall(b.SetVertexColor, b, 0.16, 0.16, 0.20)
      pcall(b.SetAllPoints, b)
    end
    local fs = mkFS(btn, "CENTER", "CENTER", 0, 0, "CENTER")
    if fs ~= nil then
      pcall(fs.SetText, fs, label)
      pcall(fs.SetTextColor, fs, 0.90, 0.90, 0.90)
    end
    btn.fs, btn.base = fs, label     -- ★`base` = 未武装时的文案（`panelArmPaint` 靠它弹回）
    btn:SetScript("OnClick", function()
      wfEcho()                       -- ★用户点我们的界面 = 「他主动问的」⇒ 盖章，结果不受「调试日志」挡
      pcall(fn)
      MDQ.panelArmPaint()
    end)
    return btn
  end
  local function refill()
    MDQ.panelFill(tostring(select(1, smMapInfo()) or ""), tonumber(MDQ.lastRenderN) or 0)
    pcall(MDQ.editRefresh)
  end
  -- ★★★1.75.60n（用户：「...调整为在迷雾图层列表底部增加个上下左右箭头点击进行微调」）：
  --   **第一排 = 四个箭头**（紧贴列表下沿 ⇒ 点它时眼睛还停在列表上）。口径见文件末尾那一大段。
  --   ★为什么改成点按钮（撤掉 1.75.60k 的键盘监听）：本客户端 EnableKeyboard(true) 的帧会吃按键
  --     ⇒ 键盘那一路必须先判「焦点在图上」，而那一层反复带来「按了没反应」/「WASD 失灵」两种误判。
  --   ★文案只有箭头字形（面板宽度有限）；按不按得动看**颜色**（有选中 = 金 / 没选中 = 灰，
  --     由 `panelNudgePaint` 每拍重画）；详细说明走悬停那行（WF_EDIT_ARROW_TIP）。
  --   ★按住 Shift 点 = ×MDQ.NUDGE_FAST（10 屏像素）—— 与上一版键盘同一档，用户不必重新学。
  p.arrows = {}
  for k = 1, table.getn(MDQ.NUDGE_DIRS) do
    local kk = k                        -- ★Lua 5.1：闭包必须另存一份，否则四个按钮都读到最后那个 k
    local ab = mkBtn(tostring(MDQ.NUDGE_DIRS[k][1]), 6 + (k - 1) * 46, 44, 0, function()
      local fast = false
      if type(IsShiftKeyDown) == "function" then
        local okS, sh = pcall(IsShiftKeyDown)
        if okS and (sh == true or sh == 1) then fast = true end
      end
      local n = select(1, MDQ.nudgeArrow(kk, fast))
      if (tonumber(n) or 0) > 0 then
        refill()                        -- 动了就把列表行里的补偿量刷新（与拖拽收尾同一口径）
      end
    end)
    if ab ~= nil then
      p.arrows[k] = ab
      -- 悬停说明（纹理/字体串不吃鼠标 ⇒ 提示挂在这个 Button 上；同红 × 那一颗的做法）
      ab:SetScript("OnEnter", function()
        local tip = _G["GameTooltip"]
        if tip == nil or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
        if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
        pcall(tip.SetOwner, tip, ab, "ANCHOR_RIGHT")
        pcall(tip.AddLine, tip, string.format("%s %s", tostring(MDQ.NUDGE_DIRS[kk][1]), L("WF_EDIT_ARROW_TIP")), 1.00, 0.82, 0.25)
        pcall(tip.Show, tip)
      end)
      ab:SetScript("OnLeave", function()
        local tip = _G["GameTooltip"]
        if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
      end)
    end
  end
  -- ★★★1.75.60o（用户：「迷雾贴图列表在单选的情况下支持选中图层的高度和宽度调整.」）：
  --   **第二排 = 尺寸**（宽− / 宽+ / 高− / 高+；紧跟在位置箭头下面 —— 先挪位置、再对尺寸，是同一件事的两步）。
  --   ★**只在「恰好选中一块」时生效**（用户点名的「单选」）：多选一起改尺寸有两种都说得通的语义
  --     （各自表值 + 同一个 Δ / 统一成一个尺寸）⇒ **不猜**，多选时按钮画灰、点了如实说原因。
  --   ★文案走三语键（`WF_EDIT_WDEC/WINC/HDEC/HINC`）；能不能按看**颜色**（单选 = 绿、其余 = 灰）。
  p.sizes = {}
  for k = 1, table.getn(MDQ.SIZE_DIRS) do
    local kk = k
    local sb = mkBtn(L(MDQ.SIZE_DIRS[k].key), 6 + (k - 1) * 46, 44, 1, function()
      local fast = false
      if type(IsShiftKeyDown) == "function" then
        local okS, sh = pcall(IsShiftKeyDown)
        if okS and (sh == true or sh == 1) then fast = true end
      end
      local n = select(1, MDQ.sizeStep(kk, fast))
      if (tonumber(n) or 0) > 0 then refill() end
    end)
    if sb ~= nil then
      p.sizes[k] = sb
      sb:SetScript("OnEnter", function()
        local tip = _G["GameTooltip"]
        if tip == nil or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
        if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
        pcall(tip.SetOwner, tip, sb, "ANCHOR_RIGHT")
        pcall(tip.AddLine, tip, string.format("%s %s", L(MDQ.SIZE_DIRS[kk].key), L("WF_EDIT_SIZE_TIP")), 0.55, 1.00, 0.55)
        pcall(tip.Show, tip)
      end)
      sb:SetScript("OnLeave", function()
        local tip = _G["GameTooltip"]
        if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
      end)
    end
  end
  p.bAll = mkBtn(L("WF_EDIT_ALL"), 6, 58, 2, function()
    local n = MDQ.selAll()
    refill()
    say(string.format("世界迷雾·编辑：[全选] 本图 %d 块（新增选中 %d）｜ 选中的一起拖",
      tonumber(MDQ.lastRenderN) or 0, n))
  end)
  p.bNone = mkBtn(L("WF_EDIT_NONE"), 68, 58, 2, function()
    MDQ.selInit()
    refill()
    say("世界迷雾·编辑：[全清] 选中集已清空（补偿**不受影响**）")
  end)
  p.bZero = mkBtn(L("WF_EDIT_ZERO"), 130, 58, 2, function()
    local file = tostring(select(1, smMapInfo()) or "")
    local n, fb = MDQ.selZero(file)
    refill()
    say(string.format("世界迷雾·编辑：[归零选中] 删掉 %d 条存档补偿（本图现存 %d 条）%s", n,
      select(1, MDQ.editCount(file)),
      (fb > 0) and string.format(" ｜ 其中 **%d 块回落到文件基线**（`MapOverlayOffset.lua` 的值，不是 0）", fb) or ""))
  end)
  -- 重置清理：清掉补偿 ⇒ 恢复成「只用 MapOverlayData.lua 的原始表值」渲染
  p.bReset = mkBtn(L("WF_EDIT_RESET"), 6, 90, 3, function()
    local file = tostring(select(1, smMapInfo()) or "")
    local mine = select(1, MDQ.editSaveCount(file))
    if not MDQ.panelArmOK("map") then
      -- ★1.75.60d：预告只数**会被清掉的存档**；文件基线在游戏内是只读的 ⇒ 顺便把「清完回落到哪」说清
      local fMine = select(1, MDQ.editFileCount(file))
      say(string.format("世界迷雾·编辑：**重置本图**会清掉本图**存档**补偿 **%d** 条（不可撤销）%s ⇒ **3 秒内再点一次**确认",
        mine, (fMine > 0) and string.format("；清完**回落到文件基线**（`MapOverlayOffset.lua` 本图 %d 条，文件不动）", fMine) or ""))
      return
    end
    local n = MDQ.editClear(file)
    MDQ.selInit()
    refill()
    -- ★1.75.60d：清的是**存档** ⇒ 独立偏移量数据库（文件基线）还在 ⇒ 如实说回落到哪一层
    local fMine = select(1, MDQ.editFileCount(file))
    if fMine > 0 then
      say(string.format("世界迷雾·编辑：本图存档补偿**已清** %d 条 ⇒ **回落到独立偏移量数据库**（`MapOverlayOffset.lua` 本图 %d 条仍在生效；要清文件只能重生 `gen_mapoffset.js`）", n, fMine))
    else
      say(string.format("世界迷雾·编辑：本图补偿**已重置** %d 条 ⇒ 此后按 `MapOverlayData.lua` 的原始表值渲染", n))
    end
  end)
  p.bResetAll = mkBtn(L("WF_EDIT_RESETALL"), 100, 90, 3, function()
    local tot = select(2, MDQ.editSaveCount(nil))
    if not MDQ.panelArmOK("all") then
      local fTot = select(2, MDQ.editFileCount(nil))
      say(string.format("世界迷雾·编辑：**重置全部地图**会清掉所有地图的**存档**补偿共 **%d** 条（不可撤销）%s ⇒ **3 秒内再点一次**确认",
        tot, (fTot > 0) and string.format("；清完**回落到文件基线**（`MapOverlayOffset.lua` 共 %d 条，文件不动）", fTot) or ""))
      return
    end
    local n = MDQ.editClear(nil)
    MDQ.selInit()
    refill()
    local fTot = select(2, MDQ.editFileCount(nil))
    if fTot > 0 then
      say(string.format("世界迷雾·编辑：**全部地图**的存档补偿已清 %d 条 ⇒ **回落到独立偏移量数据库**（`MapOverlayOffset.lua` 共 %d 条仍在生效；要清文件只能重生 `gen_mapoffset.js`）", n, fTot))
    else
      say(string.format("世界迷雾·编辑：**全部地图**的补偿已重置 %d 条 ⇒ 全项目回到只用 `MapOverlayData.lua` 原始表值", n))
    end
  end)
  -- ★★★1.75.60b：**编辑模式的两个视图开关**（用户：「编辑模式右侧增加原始贴图层的显示和隐藏,
  --   迷雾贴图层的显示和隐藏」）。两颗按钮**各自独立、互不隐含** ⇒ 四种组合都能摆出来看
  --   （对位时最有用的一格 = **原始显示 + 迷雾隐藏**：屏上只剩客户端原来那张图，位置差多少一目了然）。
  --   ★文案每拍由 `panelViewPaint` 重画（`：显示` / `：隐藏` + 颜色）—— 1.12 没有勾选框控件，改文案最省。
  --   ★写口 = `MDQ.editViewSet`（命令 `/ehm mapfit 编辑 原始 [on|off]` 走同一个口 ⇒ 不会各写一半）。
  p.bNative = mkBtn(L("WF_EDIT_NATIVE"), 6, MDQ.PANEL_W - 12, 4, function()
    MDQ.editViewSet("native")
    refill()
    say(string.format("世界迷雾·编辑：%s", MDQ.editViewLine()))
  end)
  p.bFog = mkBtn(L("WF_EDIT_FOG"), 6, MDQ.PANEL_W - 12, 5, function()
    MDQ.editViewSet("fog")
    refill()
    say(string.format("世界迷雾·编辑：%s（金色拖拽柄是编辑 UI，**照旧留着**）", MDQ.editViewLine()))
  end)
  -- ★★★1.75.60l：**第七排 = 迷雾贴图统一透明度**（用户：「在迷雾贴图列表内设置迷雾贴图的透明度,
  --   统一设置全部贴图的透明度,方便和地图原始层对照」）—— 一颗按钮，**左键循环预设档**；
  --   文案/颜色每拍由 `panelAlphaPaint` 重画（同两颗视图开关的口径 ⇒ 按钮上写的永远等于真值）。
  --   ★精确值走命令：`/ehm mapfit 编辑 透明度 <0-100>`（同一个写口 `MDQ.fogAlphaSet`）。
  p.bAlpha = mkBtn(L("WF_EDIT_ALPHA"), 6, MDQ.PANEL_W - 12, 6, function()
    MDQ.fogAlphaStep(1)
    refill()
    say(string.format("世界迷雾·编辑：**%s = %d%%**（会话态、只在编辑模式内生效；再点继续换档 100/75/50/25/10/0，"
      .. "要精确值用 `/ehm mapfit 编辑 透明度 <0-100>`）",
      L("WF_EDIT_ALPHA"), MDQ.fogAlphaPct()))
  end)

  -- ★★★1.75.60m（用户：「迷雾贴图重置也能重置**插件的偏移量**，不单是用户自定义的偏移量」）：
  --   **第八/九排 = 连插件偏移量数据库一起重置**（把 `MapOverlayOffset.lua` 那几条也用**存档 0 影**压掉 ⇒ 回原始表值）。
  --   ★为什么单立两颗按钮：这是**更深一层**的破坏性动作（上面那两颗只清你自己的增量、清完**回落插件基线**），
  --     语义不同 ⇒ 不塞进同一颗按钮、也不做成隐藏手势（破坏性动作一律**显式 + 两次点击确认**）。
  --   ★顺带一个好事：这么重置过之后跑一次 `node gen_mapoffset.js`，那几条会被**从插件数据库里删掉**（发布给别人的那份也干净）。
  p.bResetFile = mkBtn(L("WF_EDIT_RESETPLUGIN"), 6, MDQ.PANEL_W - 12, 7, function()
    local file = tostring(select(1, smMapInfo()) or "")
    local fMine = select(1, MDQ.editFileCount(file))
    if not MDQ.panelArmOK("mapFile") then
      say(string.format("世界迷雾·编辑：**重置本图（含插件偏移量）**会把 `MapOverlayOffset.lua` 本图的 **%d 条**在存档里写成 **0 影**"
        .. "（= 连插件基线一起压掉 ⇒ 本图回到 `MapOverlayData.lua` 的**原始表值**），同时清掉你自己的存档增量（不可撤销）"
        .. " ⇒ **3 秒内再点一次**确认；★想改回去：再点一次上面的「重置本图」（把 0 影删掉）就回落插件基线", fMine))
      return
    end
    local n, nm = MDQ.editResetPlugin(file)
    MDQ.selInit()
    refill()
    say(string.format("世界迷雾·编辑：**含插件基线**的重置完成 —— 压掉 **%d 条**（%d 张图）⇒ 本图按 `MapOverlayData.lua` 原始表值渲染"
      .. "；★这些是存档里的 **0 影**（可逆：普通「重置本图」删掉它们就回落插件基线）；"
      .. "要让**别人也拿到这份重置**：跑一次 `node gen_mapoffset.js`（0 影 = 从库里删除）", n, nm))
  end)
  p.bResetFileAll = mkBtn(L("WF_EDIT_RESETPLUGINALL"), 6, MDQ.PANEL_W - 12, 8, function()
    local fTot = select(2, MDQ.editFileCount(nil))
    if not MDQ.panelArmOK("allFile") then
      say(string.format("世界迷雾·编辑：**重置全部（含插件偏移量）**会把 `MapOverlayOffset.lua` **全部 %d 条**在存档里写成 **0 影**"
        .. "（= 连插件基线一起压掉 ⇒ 所有地图回到 `MapOverlayData.lua` 的原始表值），同时清掉所有地图的存档增量（不可撤销）"
        .. " ⇒ **3 秒内再点一次**确认", fTot))
      return
    end
    local n, nm = MDQ.editResetPlugin(nil)
    MDQ.selInit()
    refill()
    say(string.format("世界迷雾·编辑：**含插件基线**的重置完成（全部）—— 压掉 **%d 条**（%d 张图）｜ 本图现存补偿 %d 条",
      n, nm, select(1, MDQ.editCount(tostring(select(1, smMapInfo()) or "")))))
  end)
  -- ★★★1.75.60p（用户：「迷雾列表底部添加个保存操作->执行/reload」）：**第十排 = 保存（写盘 + 重载）**。
  --   ★为什么需要它：本客户端 **SavedVariables 只在 /reload（或退出）时才写盘** ⇒ 编辑模式里调完一堆补偿后，
  --     不 /reload 就等于「数据只在内存里」（崩溃/被踢 = 全白调）。这一排就是那个「落盘」的显式入口。
  --   ★★★**不许自己直接 ReloadUI**：/reload 会清空聊天框、也会丢掉会话态（视图开关 / 选中集 / 拖拽柄）
  --     ⇒ 走全项目**唯一**的确认窗 `Core.lua` 的 `EVAL_RELOAD_ASK`（1.75.59c 定的口径：切换开关要提示 reload）
  --     ——「确定重载」才真 `RunScript("ReloadUI()")`，「稍后」什么都不做；正文里**如实点出要存几条**。
  --   ★**拿不到那个口绝不静默**（老核心 / 未载入）：如实转一行聊天让用户自己敲 /reload —— 既不假装已保存、
  --     也绝不替他重载（`/reload` 是 Protected，只有那条已验证的 RunScript 绕行路）。
  p.bSave = mkBtn(L("WF_EDIT_SAVE"), 6, MDQ.PANEL_W - 12, 9, function()
    local file = tostring(select(1, smMapInfo()) or "")
    local mine, tot = MDQ.editSaveCount(file)
    local ask = rawget(_G, "EVAL_RELOAD_ASK")
    if type(ask) == "function" then
      pcall(ask, L("WF_EDIT_SAVE_TITLE"), L("WF_EDIT_SAVE_BODY", mine, tot))
      -- ★★★1.75.60r（同一条真机报障）：**点完必须看得见反馈** —— 确认窗若因层级被地图盖住，
      --   用户看到的就是「点了没反应」（连点都没得点）。⇒ 回显一行：窗自己的显隐/strata/level + 地图框的
      --   strata/level + **谁占着鼠标** + 要存几条（按钮已 `wfEcho()` 盖章 ⇒ 这一行不受「调试日志」挡）。
      --   ★判读：鼠标焦点不是面板/按钮 ⇒ 点击被别的帧吃掉；窗「收起」⇒ 那个确认口没弹出来。
      say(string.format("世界迷雾·编辑：保存 ⇒ 确认窗 %s（strata=%s level=%s）｜ 地图框 strata=%s level=%s ｜ 鼠标焦点 = %s"
        .. " ｜ 存档 **本图 %d 条 / 全部 %d 条**（本客户端只在 /reload 时写盘：点确认窗的「确定重载」，或自己敲 /reload）",
        MDQ.frameDiagShown(rawget(_G, "EVAL_RELOAD_ASK_FRAME")),
        MDQ.frameDiagField(rawget(_G, "EVAL_RELOAD_ASK_FRAME"), "GetFrameStrata"),
        MDQ.frameDiagField(rawget(_G, "EVAL_RELOAD_ASK_FRAME"), "GetFrameLevel"),
        MDQ.frameDiagField(_G["WorldMapDetailFrame"], "GetFrameStrata"),
        MDQ.frameDiagField(_G["WorldMapDetailFrame"], "GetFrameLevel"),
        MDQ.frameDiagFocus(), mine, tot))
    else
      say(string.format("世界迷雾·编辑：存档里的迷雾补偿 = 本图 %d 条 / 全部 %d 条（worldFogCfg.edit）；"
        .. "本客户端只在 /reload 时写盘 ⇒ **请你手动 /reload 一次**（拿不到确认窗，绝不替你重载）", mine, tot))
    end
  end)
  -- 滚轮：连续窗口逐行 + 链式接管（本项目唯一标准）
  pcall(p.EnableMouseWheel, p, true)
  local prevWheel = nil
  if type(p.GetScript) == "function" then
    local okg, g = pcall(p.GetScript, p, "OnMouseWheel")
    if okg and type(g) == "function" then prevWheel = g end
  end
  p:SetScript("OnMouseWheel", function(a, b)
    local dir = 0
    if type(EVAL_WHEEL_DIR) == "function" then dir = tonumber(EVAL_WHEEL_DIR(a, b)) or 0 end
    if MDQ.editOn() and dir ~= 0 then
      local cnt = tonumber(MDQ.lastRenderN) or 0
      local off = (tonumber(MDQ.panelOff) or 0) - dir
      local maxOff = math.max(0, cnt - MDQ.PANEL_CAP)
      if off < 0 then off = 0 end
      if off > maxOff then off = maxOff end
      MDQ.panelOff = off
      MDQ.panelFill(tostring(select(1, smMapInfo()) or ""), cnt)
      return
    end
    if prevWheel then pcall(prevWheel, a, b) end
  end)
  pcall(p.Hide, p)
  MDQ.panel = p
  return p
end

-- 位置：优先右侧、放不下翻左侧（每次 sync 都判一次 ⇒ 换分辨率/换地图都能自愈）
MDQ.panelPlace = function()
  local p = MDQ.panel
  local fr = _G["WorldMapDetailFrame"]
  if p == nil or fr == nil then return false end
  local right = nil
  if type(fr.GetRight) == "function" then
    local ok, v = pcall(fr.GetRight, fr)
    if ok then right = tonumber(v) end
  end
  local sw = nil
  local up = _G["UIParent"]
  if up ~= nil and type(up.GetWidth) == "function" then
    local ok, v = pcall(up.GetWidth, up)
    if ok then sw = tonumber(v) end
  end
  pcall(p.ClearAllPoints, p)
  if right ~= nil and sw ~= nil and (right + MDQ.PANEL_W + 14) > sw then
    pcall(p.SetPoint, p, "TOPRIGHT", fr, "TOPLEFT", -8, 0)
  else
    pcall(p.SetPoint, p, "TOPLEFT", fr, "TOPRIGHT", 8, 0)
  end
  return true
end

MDQ.panelFill = function(file, cnt)
  local p = MDQ.panel
  if p == nil then return 0 end
  local total = tonumber(cnt) or 0
  local off = tonumber(MDQ.panelOff) or 0
  local maxOff = math.max(0, total - MDQ.PANEL_CAP)
  if off < 0 then off = 0 end
  if off > maxOff then off = maxOff end
  MDQ.panelOff = off
  if p.title ~= nil then
    pcall(p.title.SetText, p.title, L("WF_EDIT_TITLE", tostring(file ~= "" and file or "?")))
  end
  if p.cnt ~= nil then
    -- ★1.75.59p：计数器一行给全 —— 「显示范围 / 总块数 ｜ 已选 N ｜ **本图已补偿 M**」
    --   （M > 0 就是在用补偿；重置清理之后这一格会回到 0，一眼看得出生效没生效）
    local mine = select(1, MDQ.editCount(file))
    local hidN = MDQ.blkHideCount()
    -- ★1.75.60o：**恰好选中一块**时把「这一块现在的尺寸」点在计数行上（用户正在调的就是这个数）
    local szTxt = ""
    if (tonumber(MDQ.selCount()) or 0) == 1 then
      local si = MDQ.selSizeNow(file)
      if si ~= nil then
        szTxt = string.format(" ｜ 尺寸 %d×%d", math.floor(si.fw + 0.5), math.floor(si.fh + 0.5))
      end
    end
    pcall(p.cnt.SetText, p.cnt, string.format("%d-%d / %d ｜ %s ｜ %s%s%s",
      (total > 0) and (off + 1) or 0, math.min(off + MDQ.PANEL_CAP, total), total,
      L("WF_EDIT_SEL", MDQ.selCount()), L("WF_EDIT_FIXED", mine), szTxt,
      -- ★1.75.60e：有逐块隐藏时在计数行点出来（排查时提醒自己「有块被藏着」）
      (hidN > 0) and string.format(" ｜ 已藏 %d", hidN) or ""))
  end
  -- ★武装态画法（幂等；过窗自动弹回原文案 ⇒ 不需要额外计时器）
  pcall(MDQ.panelArmPaint)
  -- ★1.75.60b：两颗**视图开关**按钮的文案/颜色（每拍重画 ⇒ 按钮上写的永远等于真值，
  --   不会出现「按钮说显示、其实还藏着」这类自相矛盾）
  pcall(MDQ.panelViewPaint)
  -- ★1.75.60l：透明度那一行也每拍重画（同口径 ⇒ 命令改了值、按钮上的字当拍就对上）
  pcall(MDQ.panelAlphaPaint)
  -- ★1.75.60n：箭头那一排也每拍重画（有选中 = 金 / 没选中 = 灰 ⇒ 按不按得动一眼看得出）
  pcall(MDQ.panelNudgePaint)
  -- ★1.75.60o：尺寸那一排同理（**恰好选中一块** = 绿 / 其余 = 灰）
  pcall(MDQ.panelSizePaint)
  local shown = 0
  -- ★1.75.60h：存档那一层**整表取一次**（下面逐行判「这个数是存档的还是文件基线的」用；循环里不重复取）
  local saveSub = MDQ.editMap(file, false)
  for r = 1, MDQ.PANEL_CAP do
    local rb = p.rows[r]
    local bi = off + r
    local sg = (rb ~= nil and bi <= total) and MDQ.slot[bi] or nil
    if rb ~= nil then
      if sg == nil then
        pcall(rb.Hide, rb)
      else
        local sel = MDQ.selHas(sg.area, sg.tile)
        local hid = MDQ.blkHidden(sg.area, sg.tile)
        local rec = MDQ.editRec(file, sg.area, sg.tile)
        -- ★★★1.75.60h：**这个数是从哪一层来的**必须看得见 —— 存档里没有、只有**文件基线**时点出来
        --   （真机报障「右键会导致 x 轴数据偏移」的**观感**根因：右键删掉存档增量后数字变成文件的，
        --     而行里没有任何标记 ⇒ 看着就像「右键把数据改了」）。★只在「回落」这一种情形加标记，
        --   用户自己拖出来的那些行（存档）保持原样，不添噪声。
        local fromFile = (rec ~= nil) and (saveSub == nil or saveSub[MDQ.editRowKey(sg.area, sg.tile)] == nil)
        local pfx = sel and "▶" or (hid and "×" or "　")
        local txt
        if rec ~= nil then
          -- ★1.75.60o：带尺寸补偿的行在同一对括号里点出来（`w+6 h-3`；没有尺寸补偿就一个字节不加）
          local rdw, rdh = tonumber(rec.dw) or 0, tonumber(rec.dh) or 0
          local szm = ""
          if (math.abs(rdw) >= 0.05) or (math.abs(rdh) >= 0.05) then
            szm = string.format(" w%+.0f h%+.0f", rdw, rdh)
          end
          txt = string.format("%s%d. %s#%d （x%+.1f y%+.1f%s%s）", pfx, bi,
            tostring(sg.area), tonumber(sg.tile) or 0, tonumber(rec.x) or 0, tonumber(rec.y) or 0,
            szm, fromFile and " ｜文件" or "")
        else
          txt = string.format("%s%d. %s#%d", pfx, bi, tostring(sg.area), tonumber(sg.tile) or 0)
        end
        if rb.fs ~= nil then
          pcall(rb.fs.SetText, rb.fs, txt)
          -- ★1.75.60e：逐块隐藏的行 = **灰**（排查时一眼看出「这块被藏了」）；优先级 = 已选 > 隐藏 > 常态
          if sel then pcall(rb.fs.SetTextColor, rb.fs, 1.00, 0.86, 0.35)
          elseif hid then pcall(rb.fs.SetTextColor, rb.fs, 0.50, 0.50, 0.50)
          elseif rec ~= nil then pcall(rb.fs.SetTextColor, rb.fs, 0.55, 0.90, 1.00)
          else pcall(rb.fs.SetTextColor, rb.fs, 0.83, 0.83, 0.83) end
        end
        pcall(rb.Show, rb)
        -- ★1.75.60i：红 ×（单独重置）**每拍现算显示条件** = 已选中 ∧ 这一行是你自己的存档增量
        --   （`rec ~= nil and not fromFile`）⇒ 存档被删/换图/取消选中，它就自己收起来，不需要额外记账。
        if rb.rst ~= nil then
          -- ★1.75.60m：**只要这一行有可清的东西就摆红 ×**（rec = 存档 ∪ 插件基线）——
          --   只有插件基线时左键会如实说「要连它一起清就按右键」，所以这颗按钮不再是无用的
          if sel and (rec ~= nil) then pcall(rb.rst.Show, rb.rst)
          else pcall(rb.rst.Hide, rb.rst) end
        end
        shown = shown + 1
      end
    end
  end
  return shown
end

-- ★1.75.59p：破坏性动作的**两次点击确认**（`panelArmOK` 第一次点 = 只是武装 + 报清几条；3 秒内再点 = 真清）。
--   ★为什么不用弹窗：1.12 没有销毁帧的 API，弹窗建了就得常驻；按钮自己变文案 + 聊天说明更省也更不易误触。
MDQ.panelArmOK = function(key)
  local p = MDQ.panel
  local now = (type(GetTime) == "function") and GetTime() or 0
  local a = (p ~= nil) and p.arm or nil
  if type(a) == "table" and a.key == key and (now - (tonumber(a.at) or 0)) <= 3.0 then
    p.arm = nil
    return true
  end
  if p ~= nil then p.arm = { key = key, at = now } end
  return false
end

-- 武装态的画法（幂等）：武装中的那颗按钮改成「再点确认」，过窗自动弹回原文案。
--   ★由 `panelFill` 每拍调一次 ⇒ 窗口过期后文案自己弹回，不需要额外计时器。
MDQ.panelArmPaint = function()
  local p = MDQ.panel
  if p == nil then return false end
  local now = (type(GetTime) == "function") and GetTime() or 0
  local a = p.arm
  if type(a) == "table" and (now - (tonumber(a.at) or 0)) > 3.0 then p.arm = nil a = nil end
  local armed = (type(a) == "table") and a.key or nil
  if p.bReset ~= nil and p.bReset.fs ~= nil then
    if armed == "map" then pcall(p.bReset.fs.SetText, p.bReset.fs, L("WF_EDIT_ARM"))
    else pcall(p.bReset.fs.SetText, p.bReset.fs, tostring(p.bReset.base)) end
  end
  if p.bResetAll ~= nil and p.bResetAll.fs ~= nil then
    if armed == "all" then pcall(p.bResetAll.fs.SetText, p.bResetAll.fs, L("WF_EDIT_ARM"))
    else pcall(p.bResetAll.fs.SetText, p.bResetAll.fs, tostring(p.bResetAll.base)) end
  end

  -- ★1.75.60m：那两颗「含插件基线」的重置按钮也走同一套武装态画法（各自独立武装 ⇒ 不会互相顶掉）
  if p.bResetFile ~= nil and p.bResetFile.fs ~= nil then
    if armed == "mapFile" then pcall(p.bResetFile.fs.SetText, p.bResetFile.fs, L("WF_EDIT_ARM"))
    else pcall(p.bResetFile.fs.SetText, p.bResetFile.fs, tostring(p.bResetFile.base)) end
  end
  if p.bResetFileAll ~= nil and p.bResetFileAll.fs ~= nil then
    if armed == "allFile" then pcall(p.bResetFileAll.fs.SetText, p.bResetFileAll.fs, L("WF_EDIT_ARM"))
    else pcall(p.bResetFileAll.fs.SetText, p.bResetFileAll.fs, tostring(p.bResetFileAll.base)) end
  end
  return true
end

-- ★★★1.75.60b：两颗视图开关按钮的文案与颜色（由 `panelFill` **每拍**调一次 ⇒ 幂等、永远等于真值）。
--   ★为什么每拍重画而不是只在点击时改一次：`arm` 态 / 换图 / 关编辑模式复位 / 命令改标志
--     都会让真值变，逐个出口去记得刷迟早漏一个；每拍一次 `SetText` × 2 是最省也最不会自相矛盾的做法。
MDQ.panelViewPaint = function()
  local p = MDQ.panel
  if p == nil then return false end
  local function paint(btn, key, on)
    if btn == nil or btn.fs == nil then return end
    local txt = L(key) .. "：" .. (on and L("WF_EDIT_SHOW") or L("WF_EDIT_HIDE"))
    pcall(btn.fs.SetText, btn.fs, txt)
    if on then pcall(btn.fs.SetTextColor, btn.fs, 0.55, 1.00, 0.55)
    else pcall(btn.fs.SetTextColor, btn.fs, 0.68, 0.68, 0.68) end
  end
  paint(p.bNative, "WF_EDIT_NATIVE", MDQ.viewNative())
  paint(p.bFog, "WF_EDIT_FOG", MDQ.viewFog())
  return true
end

MDQ.panelPick = function(r)
  local p = MDQ.panel
  if p == nil then return false end
  local bi = (tonumber(MDQ.panelOff) or 0) + tonumber(r)
  local sg = MDQ.slot[bi]
  if sg == nil then return false end
  MDQ.selToggle(sg.area, sg.tile)
  -- ★1.75.60t：收尾走**同一份实现**（列表点选 / 地图单选 / Shift 多选三处共用）—— 别各写一遍刷新
  MDQ.selAfterChange()
  return true
end

-- ★★★1.75.60e：列表行**右键 = 这一块贴图的显示/隐藏**（排查用；只改显示，补偿数据不动）。
--   ★用户点我们的界面 = 他主动问的 ⇒ 盖章回显（1.75.59f 的口径；不盖章「调试日志」关着时点了像没反应）。
-- ★★★1.75.60t（用户：「地图内右键类似在列表页内的右键效果.隐藏这个图层」）：逐块显示/隐藏的**唯一实现**
--   —— 入口从「列表行」扩到「地图内的柄 / 序号角标」，所以参数从**行号**改成**池位号**：
--     列表行那条路自己换算（`panelHideOne(r)`），地图里本来就有池位号（柄 = `i`）⇒ 两处共用这一份。
--   ★只改显示、**补偿数据一个字不动**（与 1.75.60e 定的口径一致）；被藏的行/角标变灰 + × 前缀，一眼看得出。
MDQ.blkHideBySlot = function(bi, srcTxt)
  local sg = MDQ.slot[tonumber(bi) or 0]
  if sg == nil then return false end
  local hidden = MDQ.blkToggle(sg.area, sg.tile)
  local file = tostring(select(1, smMapInfo()) or "")
  MDQ.panelFill(file, tonumber(MDQ.lastRenderN) or 0)
  pcall(MDQ.editRefresh)      -- 下一拍渲染就把那块藏掉/放出来（silent 路，写前比对 ⇒ 稳态零写）
  wfEcho()
  say(string.format("世界迷雾·编辑：「%s#%d」贴图 = **%s**（只改显示，不动补偿；%s再点一次恢复）",
    tostring(sg.area), tonumber(sg.tile) or 0, hidden and "**隐藏**" or "**显示**", tostring(srcTxt or "右键")))
  return true
end
MDQ.panelHideOne = function(r)
  return MDQ.blkHideBySlot((tonumber(MDQ.panelOff) or 0) + tonumber(r), "右键")
end

-- ★★★1.75.60i：列表行前的**红 × = 单独重置这一条**（用户：「点击则重置这条数据」）——
--   它是**单块归零的唯一入口**（右键已退出数据面，见 `MDQ.zeroOne` 顶部注释）。
--   ★一次点击就动手（不做两次确认）：它是**明确瞄准的红钮**、只影响这一行，且只在这一行**有自己的存档增量**时出现
--     （`panelFill` 现算显示条件）⇒ 不存在「点了没反应」；批量清理那两颗按钮照旧两次确认。
--   ★拖拽中点它 = **先把这次拖拽收尾**（否则接着松手又写回一条 ⇒ 看着像「点了没用」）。
MDQ.panelZeroOne = function(r, deep)
  local bi = (tonumber(MDQ.panelOff) or 0) + tonumber(r)
  local sg = MDQ.slot[bi]
  if sg == nil then return false end
  if type(MDQ.dragSt) == "table" then pcall(MDQ.editEnd, "重置单条") end
  -- ★1.75.60m：`deep = true`（红 × 的**右键**）= 连**插件偏移量基线**一起清（写 0 影 ⇒ 回原始表值）
  local ok = MDQ.zeroOne(bi, deep == true)
  local file = tostring(select(1, smMapInfo()) or "")
  MDQ.panelFill(file, tonumber(MDQ.lastRenderN) or 0)
  pcall(MDQ.editRefresh)
  return ok
end

-- 由 `MDQ.render` 收尾调用：与图层几何**同一拍**同步（不同源就会指错块）
MDQ.panelSync = function(file, n, k)
  if not (MDQ.editOn and MDQ.editOn()) then return MDQ.panelHide("编辑模式关着") end
  local p = MDQ.panelBuild()
  if p == nil then return nil end
  -- ★换图就**清空选中集 + 行偏移复位**（选中集按 `区域#块号` 存，跨图残留会指到别的图上同名的区域）
  --   ★1.75.60e：**逐块隐藏集也一起清**（同键 ⇒ 跨图残留同样会指错块；藏是排查动作，跟图走）
  if MDQ.selMap ~= file then
    MDQ.selMap = file
    MDQ.sel = {}
    MDQ.blkHide = {}
    MDQ.flashIdx, MDQ.flashAt = nil, 0   -- ★1.75.60j：关联操作的高亮态**跟图走**（跨图残留会亮错块）
    MDQ.panelOff = 0
  end
  MDQ.panelPlace()
  pcall(p.Show, p)
  -- ★拖拽中不重建行文本（逐帧一次 `string.format` × 16 行 = 白烧；松手时 `editEnd` 会刷一次）
  if type(MDQ.dragSt) == "table" then return true end
  MDQ.panelFill(file, tonumber(n) or 0)
  return true
end

-- 整组拖拽时的成员表（点中的那块**在选中集里** ⇒ 整组；否则只它自己）
MDQ.dragMembers = function(file, sg, m, nNow)
  local out = {}
  local function addOne(s2, needSel)
    if s2 == nil then return end
    -- ★★★1.75.59p：整组那条路**必须逐个过选中集** —— 少了这一句 = 「选中一块 ⇒ 全图一起动」
    --   （本 harness ㉕⑤ 第一次跑就抓到了这个：A#2 不该有记录却有）。
    if needSel and not MDQ.selHas(s2.area, s2.tile) then return end
    local base = (type(m) == "table") and m[s2.area] or nil
    local bw, bh, bx, by = nil, nil, nil, nil
    if base ~= nil then bw, bh, bx, by = MDQ.expectRect(base, s2.tile) end
    if bx == nil then return end       -- ★配对不上基础表 ⇒ 这一块不进成员（绝不拿孤儿补偿硬算）
    local rec = MDQ.editRec(file, s2.area, s2.tile)
    table.insert(out, {
      area = s2.area, tile = s2.tile,
      x0 = (rec ~= nil) and (tonumber(rec.x) or 0) or 0,
      y0 = (rec ~= nil) and (tonumber(rec.y) or 0) or 0,
      bx = bx, by = by, bw = bw, bh = bh,
    })
  end
  if MDQ.selHas(sg.area, sg.tile) then
    for i = 1, tonumber(nNow) or 0 do addOne(MDQ.slot[i], true) end
  end
  if table.getn(out) == 0 then addOne(sg, false) end
  return out
end

-- ============ ★★★1.75.60n：**选中图层 ⇒ 列表底部箭头点击微调**（像素级）============
-- 用户要求（原话）：「清理之前关于键盘方向键控制微调的功能.调整为在迷雾图层列表底部增加个上下左右箭头
--   点击进行微调」。
-- ★★为什么把 1.75.60k 那套「监听方向键」**整条撤掉**（这是硬性理由，不是口味问题）：
--   本客户端 `EnableKeyboard(true)` 的帧**会吃掉键盘**（在案证据 = `tools\SimpleMap.lua` 那条
--   「地图帧抢了键盘输入；禁掉它的键盘，游戏按键才恢复」）⇒ 想监听方向键就必须先判「焦点在图上」，
--   而那一层反复带来两种误判（「按了没反应」/「WASD 失灵」）。**改成点界面按钮 = 零歧义**：
--   没有焦点问题、不会吃按键、不需要还键 —— 相应的一整族判据（keyFocus / keySync / 还键收口 /
--   本会话收到过哪些键）**全部删除**，不留在代码里当死重。
-- ★六条口径（改这里之前先读完）：
--   ① **入口 = 面板列表底部那一排四个箭头**（↑ ↓ ← →；`MDQ.panel.arrows`，建在 `panelBuild` 里，
--      行号 0 = 紧贴列表下沿 ⇒ 用户点箭头时眼睛还停在列表上）。文案只有箭头字形（面板宽度有限），
--      **按不按得动看颜色**：有选中 = 金、没选中 = 灰（`MDQ.panelNudgePaint` 每拍重画）。
--   ② **一点 = 1 屏幕像素**（用户点名的「像素级」）；**按住 Shift 点 = 10 屏幕像素**。
--      ★换算**照抄拖拽那一套**（同一个公式、绝不另立口径）：Δ表 = Δ屏 ÷ (k × es)，y 取负。
--   ③ **写同一张补偿表、同一种记录**（worldFogCfg.edit；字段逐字同拖拽：
--      x,y,bx,by,bw,bh,k,es,coef,src,sx,sy,t）⇒ 箭头点出来的与拖出来的**完全等价**
--      （node gen_mapoffset.js 一样能烘进 MapOverlayOffset.lua，别的玩家一样看得到矫正后的贴图）。
--      ★成员表复用**同一个构造口** `MDQ.dragMembers` ⇒ 多选 = 整组一起动（与拖拽完全一致）。
--   ④ **没选中 / 编辑模式关 / 迷雾关 ⇒ 一个字节都不动 + 如实说出为什么**（`MDQ.nudgeArrow` 按
--      `MDQ.nudge` 的第 4 个返回分档说话 —— 「点了没反应」这一族最容易被当成「插件坏了」）。
--   ⑤ **判不出就不动手**：选中的块在 MapOverlayData.lua 里配对不上（孤儿）⇒ 一块都不动 + 如实出声（铁律）。
--   ⑥ **回显限频**：连点箭头会连发 ⇒ 聊天只每 `MDQ.NUDGE_SAY_SEC`(0.6s) 一行（实时反馈是地图上的高亮 +
--      补偿量本身）；`MDQ.nudgeLast` 留着最近一行给探针。
-- ★真机取证（只读）：`/ehm mapfit 微调` 打印「步长 / 选中几块 / 最近一次微调」，并把这几行写进
--   取证环 `mapFitTrace`（AI 直接读存档）。
MDQ.NUDGE_STEP = 1        -- 一点 = 1 **屏幕**像素（用户点名的「像素级」）
MDQ.NUDGE_FAST = 10       -- Shift + 箭头 = 10 屏像素
MDQ.NUDGE_SAY_SEC = 0.6   -- 聊天回显限频（连点会连发，不许每点一次刷一行）
MDQ.nudgeLast, MDQ.nudgeSayAt = "", 0
-- 四个方向（顺序 = 面板上从左到右；[1] = 按钮文案，[2]/[3] = **屏幕**位移，正 y 向上）
MDQ.NUDGE_DIRS = {
  { "↑", 0, 1 }, { "↓", 0, -1 }, { "←", -1, 0 }, { "→", 1, 0 },
}

-- ★微调主体（**唯一入口**）：dxScr/dyScr = **屏幕**位移（正 x 向右 / 正 y **向上**，与 GetCursorPosition 同口径）。
--   返回：(真正写进去几块, 选中几块, 能配对的成员几块, 结果码)
--   结果码 = "ok" / "editoff"（编辑模式关）/ "fogoff"（关闭世界迷雾关）/ "nosel"（没选中）/
--     "noslot"（本拍没有块）/ "orphan"（配对不上，已出声）/ "full"（一条都没写进去，已出声）
MDQ.nudge = function(dxScr, dyScr, what)
  if not (MDQ.editOn and MDQ.editOn()) then return 0, 0, 0, "editoff" end
  if not MDQ.swm() then return 0, 0, 0, "fogoff" end
  local file = tostring(select(1, smMapInfo()) or "")
  local nSel = tonumber(MDQ.selCount()) or 0
  if file == "" or nSel <= 0 then return 0, nSel, 0, "nosel" end
  local n0 = tonumber(MDQ.lastRenderN) or 0
  local sg0 = nil
  for i = 1, n0 do
    local sg = MDQ.slot[i]
    if sg ~= nil and MDQ.selHas(sg.area, sg.tile) then sg0 = sg break end
  end
  if sg0 == nil then return 0, nSel, 0, "noslot" end
  -- ★成员表走**拖拽那一个构造口**（多选 = 整组一起动；孤儿不进成员 ⇒ 配对不上就不动手）
  local members = MDQ.dragMembers(file, sg0, MDQ.areaOf(file), n0)
  local nMem = table.getn(members)
  if nMem == 0 then
    say(string.format("世界迷雾·编辑：微调 —— 选中的 %d 块在 MapOverlayData.lua 里**一块都配不上** ⇒ 这次**一个字都没动**（配对不上就不动手）", nSel))
    return 0, nSel, 0, "orphan"
  end
  local k = tonumber(MDQ.lastK) or 1
  if k <= 0 then k = 1 end
  local chain, csrc = MDQ.editMeasure()
  local coef = k * chain
  if coef == nil or coef <= 0 then coef = 1 end
  -- ★与拖拽**同一个公式**：Δ表 = Δ屏 ÷ (k × es)；y 取负（屏幕 y 向上为正、表口径 y 向下为正）
  local ddx = (tonumber(dxScr) or 0) / coef
  local ddy = -(tonumber(dyScr) or 0) / coef
  local stepX, stepY = tonumber(dxScr) or 0, tonumber(dyScr) or 0
  local t0 = (date and tostring(date("%m-%d %H:%M:%S")) or "?")
  local n, firstKey, fa, ft, fx, fy = 0, nil, "?", "?", 0, 0
  for _, mbr in ipairs(members) do
    local rec = MDQ.editRec(file, mbr.area, mbr.tile)
    local x0 = (rec ~= nil) and (tonumber(rec.x) or 0) or 0
    local y0 = (rec ~= nil) and (tonumber(rec.y) or 0) or 0
    local nx, ny = x0 + ddx, y0 + ddy
    local put = {
      x = nx, y = ny,
      bx = mbr.bx, by = mbr.by, bw = mbr.bw, bh = mbr.bh,
      k = k, es = chain, coef = coef, src = csrc,
      -- ★屏幕位移与补偿量**同源累计**（sx ≈ x × coef ⇒ 我读到存档就能双向换算，与拖拽同口径）
      sx = (tonumber(rec and rec.sx) or 0) + stepX,
      sy = (tonumber(rec and rec.sy) or 0) + stepY,
      t = t0,
    }
    -- ★1.75.60q：尺寸补偿**原样带过去**（否则一点箭头就把刚调好的宽高冲掉 —— 真机报障那次）
    MDQ.editCarrySize(put, rec)
    if MDQ.editPut(file, mbr.area, mbr.tile, put) then
      n = n + 1
      if firstKey == nil then
        firstKey = MDQ.editRowKey(mbr.area, mbr.tile)
        fa, ft, fx, fy = tostring(mbr.area), tostring(mbr.tile), nx, ny
      end
    end
  end
  if n <= 0 then
    say("世界迷雾·编辑：微调 —— 这一次**一块都没写进去**（补偿表满了？见上面那行提示）")
    return 0, nSel, nMem, "full"
  end
  pcall(MDQ.editRefresh)                     -- 与拖拽**同一条 silent 渲染路**（立刻跟手；写前比对 ⇒ 稳态零写）
  -- 反馈：调过的第一块亮 1.2 秒（连点箭头时它一直亮着 =「正在调的是这一块」）
  local firstIdx = 0
  if firstKey ~= nil then
    for i = 1, n0 do
      local sg = MDQ.slot[i]
      if sg ~= nil and MDQ.editRowKey(sg.area, sg.tile) == firstKey then firstIdx = i break end
    end
  end
  if firstIdx > 0 then pcall(MDQ.focusFlash, firstIdx, 1.2) end
  local line = string.format("（%s）动了 %d 块 ｜ 以「%s#%s」为例：表口径补偿 x=%+.2f y=%+.2f（k=%.3f es=%.3f）",
    tostring(what or "?"), n, fa, ft, fx, fy, k, chain)
  MDQ.nudgeLast = line
  local nowT = (type(GetTime) == "function") and GetTime() or 0
  if (nowT - (tonumber(MDQ.nudgeSayAt) or 0)) >= (tonumber(MDQ.NUDGE_SAY_SEC) or 0.6) then
    MDQ.nudgeSayAt = nowT
    local extra = ""
    if nMem > 1 then
      extra = string.format("（整组 %d 块）", nMem)
    elseif nSel > nMem then
      extra = string.format("（选中 %d 块，能配对的只有 %d 块 ⇒ 只动了这 %d 块）", nSel, nMem, n)
    end
    -- ★点箭头也是**用户主动操作** ⇒ 与「点我们自己的按钮 / 敲命令」同等待遇：盖章打开回显窗口
    --   （「调试日志」关着时也看得见；同 1.75.59p 的面板按钮口径）。抽块单跑时 wfEcho 不在切片里 ⇒ nil 跳过。
    if type(wfEcho) == "function" then pcall(wfEcho) end
    say("世界迷雾·编辑：箭头微调" .. extra .. " " .. line)
    pcall(MDQ.editLogPut, "微调：" .. line .. extra)
  end
  return n, nSel, nMem, "ok"
end

-- 箭头按钮的入口（**唯一入口**）：i = `MDQ.NUDGE_DIRS` 下标；fast = Shift（×NUDGE_FAST）
--   ★它只做两件事：查方向表 + 把「为什么没动」如实说出来 —— 数据面一个字都不碰（全在 `MDQ.nudge` 里）。
MDQ.nudgeArrow = function(i, fast)
  local d = MDQ.NUDGE_DIRS[tonumber(i) or 0]
  if d == nil then return 0, "baddir" end
  local step = tonumber(MDQ.NUDGE_STEP) or 1
  if step <= 0 then step = 1 end
  if fast == true then step = step * (tonumber(MDQ.NUDGE_FAST) or 10) end
  local n, _, _, why = MDQ.nudge(d[2] * step, d[3] * step, tostring(d[1]))
  n = tonumber(n) or 0
  if n <= 0 then
    -- ★「为什么点了没反应」必须当场说清（这一族最容易被当成「插件坏了」）
    local msg = nil
    if why == "nosel" then
      msg = "**先在右侧列表点一行**（或按 [全选]）再点箭头 —— 没选中任何一块时箭头不生效"
    elseif why == "editoff" then
      msg = "编辑模式没开 ⇒ 箭头不生效"
    elseif why == "fogoff" then
      msg = "「关闭世界迷雾」没开 ⇒ 箭头不生效"
    elseif why == "noslot" then
      msg = "本图这一拍还没有可调的块（等地图画完再点）"
    elseif why == "baddir" then
      msg = "方向认不出（内部错误）"
    end
    -- ★orphan / full 两种：`MDQ.nudge` 自己已经如实出声 ⇒ 这里不重复说（绝不刷两行）
    if msg ~= nil then say("世界迷雾·编辑：箭头「" .. tostring(d[1]) .. "」" .. msg) end
  end
  return n, why
end

-- 箭头那一排的**按需改色**（由 `panelFill` 每拍调一次 ⇒ 幂等、永远等于真值）：
--   有选中 = 金（点得动）/ 没选中 = 灰（点了会如实说「先选中」）。同 `panelViewPaint` / `panelAlphaPaint` 的口径。
MDQ.panelNudgePaint = function()
  local p = MDQ.panel
  if p == nil or type(p.arrows) ~= "table" then return false end
  local on = (tonumber(MDQ.selCount()) or 0) > 0
  for k = 1, table.getn(p.arrows) do
    local b = p.arrows[k]
    if b ~= nil and b.fs ~= nil then
      if on then pcall(b.fs.SetTextColor, b.fs, 1.00, 0.82, 0.25)
      else pcall(b.fs.SetTextColor, b.fs, 0.45, 0.45, 0.45) end
    end
  end
  return true
end

-- 状态一行（体检「编辑」与命令「微调」共用一份口径，不各写一套）
MDQ.nudgeLine = function()
  return string.format("箭头微调（面板列表底部 ↑↓←→）：步长=%s 屏像素/点（Shift ×%s）｜ 选中 %d 块 ｜ 最近一次=%s",
    tostring(MDQ.NUDGE_STEP), tostring(MDQ.NUDGE_FAST), tonumber(MDQ.selCount()) or 0,
    ((tostring(MDQ.nudgeLast or "") ~= "") and tostring(MDQ.nudgeLast) or "（还没有）"))
end

-- 取证口（/ehm mapfit 微调）：**一条命令**回答「选中之后点箭头为什么没反应」
MDQ.nudgeLines = function()
  local out = {}
  table.insert(out, MDQ.nudgeLine())
  table.insert(out, "　入口 = **迷雾贴图列表底部那一排四个箭头**（↑ ↓ ← →）—— 点一下 = 1 屏幕像素；按住 Shift 点 = 10 屏像素")
  -- ★1.75.60o：尺寸那一排也摊在这里（同一族、同一把尺子）
  table.insert(out, MDQ.sizeLine())
  table.insert(out, "　★**尺寸那一排（宽-/宽+/高-/高+）= 第二排**：只对**单选一块**生效；最终尺寸 = 基础表块尺寸 + 补偿（表口径），UV 不动 ⇒ 拉伸的是这一块本身")
  table.insert(out, "　★箭头是**灰的** ⇒ 一块都没选中（先在列表点一行，或按 [全选]）；连点会并入限频回显（每 0.6 秒一行）")
  table.insert(out, "　★上一版的**键盘方向键监听已整条撤掉**（本客户端 EnableKeyboard 的帧会吃掉按键 ⇒「焦点」那一层反复带来两种误判）；改成点按钮 = 没有焦点问题、不吃按键")
  return out
end

-- ============ ★★★1.75.60o：**单选 ⇒ 调整这一块的高/宽**（面板列表底部第二排）============
-- 用户要求（原话）：「迷雾贴图列表在单选的情况下支持选中图层的高度和宽度调整.」
-- ★五条口径（改这里之前先读完）：
--   ① **只在「恰好选中一块」时生效**（用户点名的「单选」）：0 块 ⇒ 说话让他先选；≥2 块 ⇒ 如实说
--      「多选不做尺寸调整（一次只调一块）」。★为什么锁死单选：多选一起改尺寸有**两种都说得通**的语义
--      （各自表值 + 同一个 Δ / 统一成一个尺寸）⇒ **不猜**，宁可少做一半。
--   ② **一次点击 = 1 屏幕像素**（与位置箭头**同一把尺子**：同一个 `MDQ.NUDGE_STEP` / `NUDGE_FAST`）、
--      **按住 Shift 点 = 10 像素**；换算照抄那一套：`Δ表 = Δ屏 ÷ (k × es)`。
--   ③ **写同一张记录**（`worldFogCfg.edit`）：`dw/dh` = **尺寸补偿**（表口径增量，与 `x/y` 完全对称）、
--      `sw/sh` = 原始屏幕尺寸增量（同源累计：`sw × coef ≈ dw`，给 AI 读存档双向换算用）；
--      ★**位置字段原样带过去**（`x/y` 抄当前生效那条）—— 否则「只改尺寸」会顺手把插件基线 / 用户自己拖的位移抹掉。
--   ④ **最终尺寸 = 表值 + 补偿**，唯一出口 `MDQ.editSize`（渲染那一趟与体检读的是同一个口）⇒
--      基础表重生 / 换缩放级别都不影响它；★**UV 不动**：拉伸/压缩的是这一块本身的采样，不是换一块内容。
--   ⑤ **有上下限**（`SIZE_MIN`=2 / `SIZE_MAX`=4096 表像素）：夹到时**如实说**，绝不静默吞掉这一下。
-- ★真机取证（只读）：`/ehm mapfit 微调` 的第二句就是尺寸那一行（`MDQ.sizeLine`），行同时进取证环 `mapFitTrace`。
MDQ.SIZE_MIN, MDQ.SIZE_MAX = 2, 4096
-- 四个按钮（顺序 = 面板上从左到右；`key` = 三语文案键，`axis` = 动的哪一轴，`sign` = 屏幕方向，正 = 变大）
MDQ.SIZE_DIRS = {
  { key = "WF_EDIT_WDEC", axis = "w", sign = -1 },
  { key = "WF_EDIT_WINC", axis = "w", sign = 1 },
  { key = "WF_EDIT_HDEC", axis = "h", sign = -1 },
  { key = "WF_EDIT_HINC", axis = "h", sign = 1 },
}

-- 「本图当前**单选**的那一块」= `{ area, tile, bw, bh, bx, by, dw, dh, fw, fh, rec }`
--   取不到 ⇒ `nil, 原因`（`nosel` 一块都没选 / `multi` 多选 / `noslot` 本拍没有块 / `orphan` 基础表里配不上）
--   ★它是**只读**的（面板每拍调它画计数行、按钮点击也调它取基准）⇒ 不许在这里写任何存档。
MDQ.selSizeNow = function(file)
  local nSel = tonumber(MDQ.selCount()) or 0
  if nSel ~= 1 then return nil, (nSel <= 0) and "nosel" or "multi" end
  local n0 = tonumber(MDQ.lastRenderN) or 0
  local sg0 = nil
  for i = 1, n0 do
    local sg = MDQ.slot[i]
    if sg ~= nil and MDQ.selHas(sg.area, sg.tile) then sg0 = sg break end
  end
  if sg0 == nil then return nil, "noslot" end
  local f = tostring(file or "")
  -- ★口径：`expectRect` 吃的是**区域记录**（`m[区域]`），不是整张图的表（`dragMembers` 同款）
  local base = MDQ.areaOf(f)
  local area = (type(base) == "table") and base[sg0.area] or nil
  local bw, bh, bx, by = nil, nil, nil, nil
  if type(area) == "table" then bw, bh, bx, by = MDQ.expectRect(area, sg0.tile) end
  if bw == nil then return nil, "orphan" end
  local rec = MDQ.editRec(f, sg0.area, sg0.tile)
  local dw = (rec ~= nil) and (tonumber(rec.dw) or 0) or 0
  local dh = (rec ~= nil) and (tonumber(rec.dh) or 0) or 0
  return { area = sg0.area, tile = sg0.tile, bw = bw, bh = bh, bx = bx, by = by,
    dw = dw, dh = dh, fw = bw + dw, fh = bh + dh, rec = rec }, "ok"
end

-- **唯一写口**：`which` = 1..4（`MDQ.SIZE_DIRS` 下标）；`fast` = Shift（×NUDGE_FAST）。
--   返回 (写了 1 块 / 0, 原因码)；原因码 = ok / editoff / fogoff / nomap / nosel / multi / noslot / orphan / baddir / clamped / full
MDQ.sizeStep = function(which, fast)
  local d = MDQ.SIZE_DIRS[tonumber(which) or 0]
  if d == nil then return 0, "baddir" end
  -- ★「为什么点了没反应」必须**当场说清**（与位置箭头同一把尺子）：这一族最容易被当成「插件坏了」
  if not (MDQ.editOn and MDQ.editOn()) then
    say("世界迷雾·编辑：尺寸不生效 —— **编辑模式没开**")
    return 0, "editoff"
  end
  if not MDQ.swm() then
    say("世界迷雾·编辑：尺寸不生效 —— **「关闭世界迷雾」没开**")
    return 0, "fogoff"
  end
  local file = tostring(select(1, smMapInfo()) or "")
  if file == "" then return 0, "nomap" end
  local info, why = MDQ.selSizeNow(file)
  if info == nil then
    local msg = nil
    if why == "nosel" then
      msg = "**先在右侧列表点一行**（或按 [全选] 再收到一块）—— 尺寸**只对单选一块生效**"
    elseif why == "multi" then
      msg = "**多选了** ⇒ 尺寸**只对单选一块生效**（先按 [全清] 再点一行）"
    elseif why == "noslot" then
      msg = "本图这一拍还没有可调的块（等地图画完再点）"
    elseif why == "orphan" then
      msg = "这一块在 MapOverlayData.lua 里**配不上** ⇒ 尺寸不生效（配对不上就不动手）"
    end
    if msg ~= nil then say("世界迷雾·编辑：尺寸「" .. L(d.key) .. "」" .. msg) end
    return 0, why
  end
  -- ★与位置微调**同一套换算**（绝不另立第二套）：Δ表 = Δ屏 ÷ (k × es)
  local k = tonumber(MDQ.lastK) or 1
  if k <= 0 then k = 1 end
  local chain, csrc = MDQ.editMeasure()
  local coef = k * chain
  if coef == nil or coef <= 0 then coef = 1 end
  local step = tonumber(MDQ.NUDGE_STEP) or 1
  if step <= 0 then step = 1 end
  if fast == true then step = step * (tonumber(MDQ.NUDGE_FAST) or 10) end
  local dScr = (tonumber(d.sign) or 1) * step       -- 屏幕方向：正 = 变大
  local dTab = dScr / coef                          -- 表口径增量
  -- 夹进 [SIZE_MIN, SIZE_MAX]（表口径）；夹到了 ⇒ 记下来，下面如实说
  local base = (d.axis == "w") and info.bw or info.bh
  local d0 = (d.axis == "w") and info.dw or info.dh
  local lo = (tonumber(MDQ.SIZE_MIN) or 2) - base
  local hi = (tonumber(MDQ.SIZE_MAX) or 4096) - base
  local v = d0 + dTab
  local hit = nil
  if v < lo then v = lo hit = "min" end
  if v > hi then v = hi hit = "max" end
  local rec = info.rec
  local dw, dh = info.dw, info.dh
  if d.axis == "w" then dw = v else dh = v end
  local fw, fh = info.bw + dw, info.bh + dh
  -- 夹到极限（这一下**一个字节都不会变**）⇒ 如实说，不写存档
  if math.abs(dw - info.dw) < 1e-6 and math.abs(dh - info.dh) < 1e-6 then
    say(string.format("世界迷雾·编辑：尺寸**已经到%s**（%s = %d×%d 表口径）⇒ 这一次一个字节都没动",
      (hit == "min") and "最小档" or "最大档", L(d.key),
      math.floor(fw + 0.5), math.floor(fh + 0.5)))
    return 0, "clamped"
  end
  -- ★屏幕位移与补偿量**同源累计**：取**实际生效**的位移（夹过之后）⇒ `sw × coef ≈ dw` 恒成立
  local applScr = ((d.axis == "w") and (dw - info.dw) or (dh - info.dh)) * coef
  local sw0 = (tonumber(rec and rec.sw) or 0)
  local sh0 = (tonumber(rec and rec.sh) or 0)
  local sw, sh = sw0, sh0
  if d.axis == "w" then sw = sw0 + applScr else sh = sh0 + applScr end
  local t0 = (date and tostring(date("%m-%d %H:%M:%S")) or "?")
  -- ★位置字段**原样带过去**（否则「只改尺寸」会把插件基线/自己拖的位移抹掉）
  if not MDQ.editPut(file, info.area, info.tile, {
    x = (tonumber(rec and rec.x) or 0), y = (tonumber(rec and rec.y) or 0),
    dw = dw, dh = dh,
    bx = info.bx, by = info.by, bw = info.bw, bh = info.bh,
    k = k, es = chain, coef = coef, src = csrc,
    sx = (tonumber(rec and rec.sx) or 0), sy = (tonumber(rec and rec.sy) or 0),
    sw = sw, sh = sh, t = t0,
  }) then
    say("世界迷雾·编辑：尺寸**没记下来**（补偿表满了？先用「编辑 清」清掉一些）")
    return 0, "full"
  end
  pcall(MDQ.editRefresh)                     -- 与位置微调**同一条 silent 渲染路**（立刻跟手）
  -- 关联操作高亮：调过的那一块亮 1.2 秒（复用 1.75.60j 的口径）
  local idx0 = 0
  for i = 1, tonumber(MDQ.lastRenderN) or 0 do
    local sg = MDQ.slot[i]
    if sg ~= nil and sg.area == info.area and sg.tile == info.tile then idx0 = i break end
  end
  if idx0 > 0 then pcall(MDQ.focusFlash, idx0, 1.2) end
  local line = string.format("（%s）尺寸：表值 %g×%g ＋ 补偿 %+.2f×%+.2f ⇒ **%g×%g**（表口径；k=%.3f es=%.3f）%s",
    L(d.key), info.bw, info.bh, dw, dh, fw, fh, k, chain,
    (hit ~= nil) and (" ｜★已夹到" .. ((hit == "min") and "最小档" or "最大档")) or "")
  MDQ.nudgeLast = line
  local nowT = (type(GetTime) == "function") and GetTime() or 0
  if (nowT - (tonumber(MDQ.nudgeSayAt) or 0)) >= (tonumber(MDQ.NUDGE_SAY_SEC) or 0.6) then
    MDQ.nudgeSayAt = nowT
    -- ★点尺寸按钮也是**用户主动操作** ⇒ 与点箭头 / 敲命令同等待遇：盖章打开回显窗口
    if type(wfEcho) == "function" then pcall(wfEcho) end
    say("世界迷雾·编辑：尺寸微调 " .. line)
    pcall(MDQ.editLogPut, "尺寸：" .. line)
  end
  return 1, "ok"
end

-- 尺寸那一排的**按需改色**（由 `panelFill` 每拍调一次 ⇒ 幂等）：**恰好选中一块** = 绿（调得动）/ 其余 = 灰。
--   ★为什么与箭头的金**不同色**：两排按钮干的是两件事（位置 / 尺寸），一眼分得开就不用来回试。
MDQ.panelSizePaint = function()
  local p = MDQ.panel
  if p == nil or type(p.sizes) ~= "table" then return false end
  local one = (tonumber(MDQ.selCount()) or 0) == 1
  for k = 1, table.getn(p.sizes) do
    local b = p.sizes[k]
    if b ~= nil and b.fs ~= nil then
      if one then pcall(b.fs.SetTextColor, b.fs, 0.55, 1.00, 0.55)
      else pcall(b.fs.SetTextColor, b.fs, 0.45, 0.45, 0.45) end
    end
  end
  return true
end

-- 尺寸那一行状态（体检「编辑」与命令「微调」共用一份口径）
MDQ.sizeLine = function()
  local file = tostring(select(1, smMapInfo()) or "")
  local info, why = MDQ.selSizeNow(file)
  local head = string.format("尺寸补偿（面板第二排 宽-/宽+/高-/高+）：步长=%s 屏像素/点（Shift ×%s）",
    tostring(MDQ.NUDGE_STEP), tostring(MDQ.NUDGE_FAST))
  if info == nil then
    local w = "一块都没选中（先在列表点一行）"
    if why == "multi" then w = "**多选了** ⇒ 尺寸只支持**单选一块**（先把选中集收到一块）"
    elseif why == "noslot" then w = "本拍没有可调的块（等地图画完再点）"
    elseif why == "orphan" then w = "这一块在 MapOverlayData.lua 里**配不上** ⇒ 不生效（配对不上就不动手）" end
    return head .. " ｜ 现在**不可调**：" .. w
  end
  return string.format("%s ｜ 单选「%s#%d」：表值 %g×%g ＋ 补偿 %+.2f×%+.2f ⇒ **最终 %g×%g**（表口径）",
    head, tostring(info.area), tonumber(info.tile) or 0, info.bw, info.bh, info.dw, info.dh, info.fw, info.fh)
end

-- 命令口（宿主 `/ehm mapfit <子命令>` 分流到这里）：返回 true = 本模块处理了
--   ★★★1.75.59h：**再收一层「整串」容忍**（`"mapfit perf"` ⇒ `"perf"`）—— 1.75.56 拆分起宿主那侧递的是
--   **整串**，而这里比的是裸子命令 ⇒ `残留/贴图/perf/swm` 四条**静默降级成折算 diag**（真机截图定案：
--   敲 `perf` 只出 diag）。调用方已修（递裸子命令），这里容错是为了**这类失效不许有第二次**：
--   它不报错、不白屏，只是「命令跑了但没内容」—— 只能靠判据与容错兜，不靠人眼。
MDQ.cmd = function(sub)
  sub = tostring(sub or "")
  sub = string.match(sub, "^mapfit%s+(.*)$") or string.match(sub, "^叠加层%s+(.*)$") or sub
  -- ★★★1.75.59f：**命令回显窗口盖章**（用户敲的命令，回显在「调试日志」关着时也要看得见）
  if type(GetTime) == "function" then WF_ECHO_AT = GetTime() + WF_ECHO_SEC end
  if sub == "残留" or sub == "stale" or sub == "残留层" or sub == "残留贴图" then
    -- ★1.75.59f：体检是**你敲的** ⇒ 除进取证环外**同时回显**（关着总闸门也看得到；上面已盖章）
    for _, l in ipairs(MDQ.staleProbe()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "检查" or sub == "check" or sub == "体检" then
    -- ★1.75.59i：**一句话结论**（用户：「别让我看数字」）—— 见 `MDQ.holdVerdict` 的注释（只读、零副作用）
    for _, l in ipairs(MDQ.holdVerdict()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "自检" or sub == "selfcheck" or sub == "全诊" then
    -- ★★★1.75.59l：**一条命令跑完全部只读诊断 + 全文落盘 + 自己 reload**（用户定：
    --   「命令不要分步骤.玩家是不知道如何执行的.最多配合你打开地图」）⇒ 玩家**只需开图 + 敲这一条命令**：
    --   本命令跑完 → 全文写进有界环 → **自己调 `ReloadUI`**（本客户端只在 /reload 时写盘）⇒ 存档落地，
    --   AI 直接读 `SavedVariables\EvalHelp.lua`。★玩家**不需要**再做什么（聊天回显 /reload 后仍在，看得见）。
    local lines = MDQ.fitBattery()
    local ringN = MDQ.fitDiagPut(lines)
    -- 聊天只回显少量关键行（防刷屏）：结论行 + 两个决定性的数
    local concl, l3, l2 = "", "", ""
    for _, l in ipairs(lines) do
      if string.find(l, "结论", 1, true) == 1 then concl = l
      elseif string.find(l, "[3] 我方活句柄", 1, true) == 1 then l3 = l
      elseif string.find(l, "[2] 名字族", 1, true) == 1 then l2 = l end
    end
    for _, l in ipairs({ "[自检] **只读**跑完（不写地图、不调 holdTick）", l2, l3, concl }) do
      if tostring(l) ~= "" then mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    end
    mfLog("[mapfit] [自检] 全文 %d 行已存入 worldFogCfg.fitDiag（环 %d，现 %d 行）",
      table.getn(lines), tonumber(MDQ.FIT_DIAG_MAX) or 500, ringN)
    -- ★★★1.75.59m：**延后重载**（用户真机反馈：「`/ehm mapfit 自检` 执行直接重载了.然后啥事没干」）：
    --   本客户端 `/reload` 会**清空聊天框** ⇒ 旧写法「跑完立刻 `ReloadUI`」等于把上面那几行回显**当场抹掉**
    --   （玩家看到的就是「重载了、什么都没发生」）。⇒ 这里只**盖章**，由节拍帧到点执行（见 `wfBeat` 第一段），
    --   并把「N 秒后自动落盘」明说出来 ⇒ 玩家有时间把结论看完，然后它自己重载。
    local waitSec = tonumber(MDQ.SELF_RELOAD_SEC) or 6
    MDQ.selfReloadAt = ((type(GetTime) == "function") and GetTime() or 0) + waitSec
    pcall(MDQ.beatSync)   -- 有待办 ⇒ 即使开关关着也要把节拍挂上（否则到点没人执行）
    say(string.format("[mapfit] [自检] 全文 **%d 行已就绪**（存 `worldFogCfg.fitDiag`）⇒ **%d 秒后自动 /reload 落盘**"
      .. "（先把上面几行看完；重载后存档里就是全文，AI 自己读）", table.getn(lines), waitSec))
    return true
  elseif sub == "检查 alpha" or sub == "check alpha" then
    -- ★1.75.59j：**alpha 只读探针**（一个字节都不写）
    for _, l in ipairs(MDQ.alphaProbe()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif string.find(sub, "^检查 alpha 试") or string.find(sub, "^check alpha 试") then
    -- ★1.75.59j：**一次性自证实验**（写 1 条「不是我们的」层 → 逐拍读回 → 必还原）
    local k = (string.find(sub, "贴图", 1, true) ~= nil) and "tex" or "alpha"
    for _, l in ipairs(MDQ.trialStart(k)) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "检查 alpha 停" or sub == "check alpha stop" then
    local t = MDQ.trialStop("手动停")
    if t == nil then say("[mapfit] 实验：当前没有在跑的实验") else
      for _, l in ipairs(t) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    end
    return true
  elseif sub == "贴图" then
    for _, l in ipairs(MDQ.texProbe()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "贴图版本" or sub == "texpack"
      or string.find(sub, "^贴图版本%s") or string.find(sub, "^texpack%s") then
    -- ★1.75.60z：**分版本贴图整套已清理**（用户：「清理功能: MDQ.packs 虽然还列着 live/p9 清理掉图层渲染机制」）
    --   ⇒ 这里如实说明「这条命令已经没有了」，绝不静默掉回别的档（否则又是一次「命令跑了但没内容」）。
    say("[mapfit] 贴图版本：**该功能已清理**（分版本贴图 / `_v` 目录那套已整条删除）"
      .. " ｜ 现在只有一条路：**自带 `media\\WorldMap\\` 优先 → 客户端自带**"
      .. " ｜ 想体检路径与探针：`/ehm mapfit 贴图`")
    return true
  elseif sub == "perf" or sub == "性能" then
    for _, l in ipairs(MDQ.perfProbe()) do mfLog("[perf] %s", l) say("[perf] " .. tostring(l)) end
    return true
  elseif sub == "图层" or sub == "layer" or sub == "图层状态" then
    -- ★★★1.75.64：**图层类型（区域彩图 / 区域实景）** 的只读状态 + 真机自证
    --   ① 现模式 + 两套补偿各几条（分家是否生效，一眼可见）；
    --   ② **实景贴图探针**（自带那份 + **负对照**）⇒ 「这张图的 JPG 到底加载得出来吗」不必靠猜；
    --   ③ 帧与基线：实景要**与客户端地图坐标系对齐**（矩形 → 可见帧 1002x668；
    --      ★1.75.67 实测：客户端把美术按**瓦片 1:1 原尺寸**画进帧、多出的右 22px / 下 100px 被裁掉；
    --        而**手绘城区本身是示意图**（偏西 160~210px / 偏北 100~130px、公园↔要塞跨度为真实 2.5 倍）
    --        ⇒ 逐地物贴合只能靠编辑模式微调，下面的实时几何读数用来分辨「基线不对」与「美术示意」）。
    local jm = MDQ.jpgMode()
    say("世界迷雾·图层类型 = **" .. (jm and "区域实景" or "区域彩图") .. "**"
      .. "（/ehm mapfit 图层 彩图|实景 切换）")
    local f = select(1, smMapInfo())
    say(string.format("　本图=%s ｜ 帧=WorldMapDetailFrame ｜ 基线=%s",
      tostring(f),
      (function()
        if not jm then
          local m = MDQ.areaOf(tostring(f))
          local n = 0
          if type(m) == "table" then for _ in pairs(m) do n = n + 1 end end
          return string.format("彩图 %d 区块位", n)
        end
        local r = MDQ.jpgBase(tostring(f))
        if type(r) ~= "table" then return "**实景表里没有这张图（不接管）**" end
        return string.format("实景 %sx%s @%s,%s", tostring(r[1]), tostring(r[2]), tostring(r[3]), tostring(r[4]))
      end)()))
    if jm then
      local p = MDQ.jpgPath(tostring(f))
      local r = MDQ.probeTrust(p)
      say("　实景贴图：" .. p .. " ｜ 探针="
        .. ((r == true) and "**加载得出来**" or (r == false and "**探不到** ⇒ 本图不接管" or "判不出（放拦）")))
      say("　负对照：" .. p .. MDQ.probeBogus .. " ｜ 探针="
        .. ((MDQ.probeTrust(p .. MDQ.probeBogus) == nil) and "**也报有 ⇒ 判不出 ⇒ 放拦（本客户端对不存在的文件也报尺寸）**"
          or "可信（不存在 ⇒ 探不到）"))
      say("　★写法 = **不带扩展名**（`media\\WorldMapJpg\\<图>`）—— 1.75.62 真机验证过的载入方式（见 CHANGELOG 1.75.62）。")
      -- ★★★1.75.67：**实时几何读数**（只读，零写入）—— 用来当场分辨两种「对不上」：
      --   ① 美术本身是手绘示意图（离线已证：客户端把地图美术按 **瓦片 1:1 原尺寸**画进帧、被 1002x668 帧裁切；
      --      而手绘城区相对矩形推算位置整体偏西/偏北 ⇒ 换任何线性基线都不可能逐地物重合）；
      --   ② 运行时几何不对（倍率 k 取错 / 锚点错）—— 这一条只有真机能判，故把「写进去的」与「读回来的」并排列出。
      local fr = _G["WorldMapDetailFrame"]
      local function rd(o, m)
        if o == nil or m == nil then return "?" end
        local ok, v = pcall(o[m], o)
        if ok and v ~= nil then return tostring(v) end
        return "?"
      end
      local okE, esNow = pcall(smEffScale, fr)
      if not okE then esNow = "?" end
      say(string.format("　帧几何：逻辑 %s x %s ｜ 有效缩放 %s ｜ 上次渲染 k=%s ｜ 上次写入 %sx%s @%s,%s",
        rd(fr, "GetWidth"), rd(fr, "GetHeight"), tostring(esNow), tostring(MDQ.lastK),
        tostring(MDQ.lastW), tostring(MDQ.lastH), tostring(MDQ.lastTox), tostring(MDQ.lastToy)))
      local st = MDQ.slot[1]
      if type(st) == "table" and st.tex ~= nil then
        local p1 = { pcall(st.tex.GetPoint, st.tex, 1) }
        say(string.format("　实景纹理读回：宽高 %s x %s ｜ 锚点偏移 %s,%s ｜ 渲染账 k=%s ｜ 有补偿=%s",
          rd(st.tex, "GetWidth"), rd(st.tex, "GetHeight"),
          tostring(p1[4]), tostring(p1[5]), tostring(st.k), tostring(st.off ~= nil)))
        say("　★判读：**读回宽高 ≈ 基线 x k**（k 为 1 时 ≈ 基线）⇒ 几何按口径落地；"
          .. "若读回明显小于基线 ⇒ 倍率 k 没取到 1（本图无引擎叠加层数据时按外框有效缩放兜底）——"
          .. "那才是「实景比地图小一圈」；若读回 ≈ 基线而画面仍与手绘图错位 ⇒ 属美术本身示意（用编辑模式微调）。")
        -- ★★★1.75.67b：**屏测（真屏幕像素，含全部缩放）** —— 唯一能判「贴图到底铺没铺满帧」的口径：
        --   `GetWidth/GetHeight` 在**帧**上含父链缩放、在**纹理**上是逻辑值（本项目在案的两条实测，
        --   互相冲突 ⇒ 不许拿两个读回值直接比）。⇒ 一律比**屏幕矩形**（`MDQ.scrBox` = 唯一实现）：
        --   比值 ≈ 1 ⇒ 铺满帧；≈ 有效缩放 ⇒ 只铺了那么多（运行时已由 `MDQ.unitFit` 自证校正，见 jpgRender）。
        local fSw, fSh = MDQ.scrBox(fr)
        local tSw, tSh = MDQ.scrBox(st.tex)
        local upEs = "?"
        local okU, vU = pcall(smEffScale, _G["UIParent"])
        if okU and vU ~= nil then upEs = tostring(vU) end
        if fSw ~= nil and tSw ~= nil and fSw > 0 then
          say(string.format("　屏测：帧 %dx%d ｜ 实景贴图 %dx%d ｜ 贴图/帧 = %.3f",
            math.floor(fSw + 0.5), math.floor(fSh + 0.5), math.floor(tSw + 0.5), math.floor(tSh + 0.5), tSw / fSw))
        else
          say("　屏测：读不到屏幕矩形（老客户端 / 纹理还没建）⇒ 退回「读回宽高 ÷ 基线」判断")
        end
        say(string.format("　缩放链：帧 smEffScale=%s ｜ 帧 GetEffectiveScale=%s ｜ UIParent smEffScale=%s"
          .. " ｜ 已测得的客户端倍率口径 unitFit=%s（nil = 还没量到；★贴图/帧 应 ≈ 1）",
          tostring(esNow), rd(fr, "GetEffectiveScale"), upEs, tostring(MDQ.unitFit)))
      else
        say("　实景纹理读回：本会话还没渲染过（先开一次地图、再敲本命令）")
      end
    end
    local mine, tot = MDQ.editCount(tostring(f))
    local fmine, ftot = MDQ.editFileCount(tostring(f))
    say(string.format("　补偿分家：本模式 本图 %d / 全部 %d 条（存档）｜ 插件基线 本图 %d / 全部 %d 条（%s）",
      mine, tot, fmine, ftot, jm and "MapOverlayOffsetJPG.lua" or "MapOverlayOffset.lua"))
    say("　★渲染优先级：实景层写 **OVERLAY** 绘制层（彩图那批在 ARTWORK）⇒ 同组内遮盖其它层；原绘制层进原值账，关开关/切换时还回。")
    return true
  elseif sub == "图层 彩图" or sub == "layer art" then
    return MDQ.layerSet(MDQ.LAYER_ART)
  elseif sub == "图层 实景" or sub == "layer jpg" then
    return MDQ.layerSet(MDQ.LAYER_JPG)
  elseif sub == "swm" then
    say("世界迷雾 = **" .. (MDQ.swm() and "开" or "关") .. "**"
      .. " ｜ 接管守护=" .. (MDQ.swm() and "开" or "关")
      .. " ｜ 残留图层清理=" .. (MDQ.staleOn() and "开" or "关")
      .. "（开关：工具箱 → 世界迷雾；或 /ehm mapfit swm on|off）")
    return true
  elseif sub == "swm on" then
    return MDQ.fogSet(true)
  elseif sub == "swm off" then
    return MDQ.fogSet(false)
  elseif sub == "编辑" or sub == "edit" or sub == "补偿" then
    -- ★1.75.59o：补偿体检（只读；**带与 `MapOverlayData.lua` 的配对结果**）
    for _, l in ipairs(MDQ.editLines()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "编辑 配对" or sub == "edit join" then
    -- ★与上面那条**同一份**（配对体检本来就含在 `editLines` 里）——
    --   留这个别名只是为了让用法行里写的 `[on|off|配对|清|清全部]` 与实现**逐字对得上**
    for _, l in ipairs(MDQ.editLines()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "编辑 on" or sub == "edit on" then
    return MDQ.editSet(true)
  elseif sub == "编辑 off" or sub == "edit off" then
    return MDQ.editSet(false)
  elseif string.find(sub, "^编辑 原始") or string.find(sub, "^edit native") then
    -- ★1.75.60b：视图开关「原始贴图层」（**唯一写口 `editViewSet`**，与右侧面板那颗按钮同一个口）。
    --   无参数 = 反转；带 on/off 显式指定。★它**不是**配置 ⇒ 不落存档，关编辑模式即复位。
    local v = MDQ.editArgOnOff(sub)
    MDQ.editViewSet("native", v)
    say("世界迷雾·编辑：" .. MDQ.editViewLine())
    return true
  elseif string.find(sub, "^编辑 雾") or string.find(sub, "^编辑 迷雾")
    or string.find(sub, "^edit fog") then
    local v = MDQ.editArgOnOff(sub)
    MDQ.editViewSet("fog", v)
    say("世界迷雾·编辑：" .. MDQ.editViewLine())
    return true
  elseif string.find(sub, "^编辑 透明度") or string.find(sub, "^edit alpha") then
    -- ★1.75.60l：**迷雾贴图统一透明度**（与面板第五排那颗按钮**同一个写口** MDQ.fogAlphaSet）
    local a = string.match(sub, "(%d+%.?%d*)%s*%%?%s*$")
    if a == nil then
      say("世界迷雾·编辑：" .. MDQ.editViewLine())
      say(string.format("　用法：/ehm mapfit 编辑 透明度 <0-100>（认 50 = 50%%、0.5 = 50%%）"
        .. "｜ 面板上那颗「%s」按钮左键循环 100/75/50/25/10/0 ｜ **会话态、只在编辑模式内生效**",
        L("WF_EDIT_ALPHA")))
      return true
    end
    local okA = MDQ.fogAlphaSet(a)
    if okA ~= true then
      say(string.format("世界迷雾·编辑：%s **只在编辑模式内生效** ⇒ 请先打开编辑模式"
        .. "（工具箱 → 关闭世界迷雾 → [设置] → 编辑模式；或 `/ehm mapfit 编辑 on`）", L("WF_EDIT_ALPHA")))
      return true
    end
    say(string.format("世界迷雾·编辑：**%s = %d%%** ⇒ %s", L("WF_EDIT_ALPHA"), MDQ.fogAlphaPct(), MDQ.editViewLine()))
    return true
  elseif string.find(sub, "^编辑 重置插件") or string.find(sub, "^edit pluginreset") then
    -- ★1.75.60m：**连插件偏移量数据库一起重置**（与面板第六/七排两颗按钮**同一个写口** `MDQ.editResetPlugin`）
    local which = string.match(sub, "(本图|全部)%s*$")
    local file = nil
    if which ~= "全部" then file = tostring(select(1, smMapInfo()) or "") end
    local n, nm = MDQ.editResetPlugin(file)
    MDQ.selInit()
    pcall(MDQ.editRefresh)
    say(string.format("世界迷雾·编辑：**含插件基线**的重置完成（%s）—— 压掉 **%d 条**（%d 张图）⇒ 按 `MapOverlayData.lua` 原始表值渲染"
      .. "；★这些是存档里的 **0 影**（可逆）；跑一次 `node gen_mapoffset.js` 就会把这几条**从插件数据库里删掉**（别人也拿到这份重置）",
      (which == "全部") and "全部地图" or ("本图 " .. tostring(file or "?")), n, nm))
    return true  elseif sub == "编辑 清" or sub == "edit clear" then
    local f = tostring(select(1, smMapInfo()) or "")
    local n = MDQ.editClear(f)
    MDQ.editRefresh()
    say(string.format("世界迷雾·编辑：本图（%s）补偿已清 %d 条", (f ~= "" and f or "?"), n))
    return true
  elseif sub == "编辑 清全部" or sub == "edit clearall" then
    local n = MDQ.editClear(nil)
    MDQ.editRefresh()
    say(string.format("世界迷雾·编辑：**全部地图**的补偿已清 %d 条", n))
    return true
  elseif sub == "微调" or sub == "nudge" or sub == "箭头" then
    -- ★1.75.60n：**一条命令**回答「选中之后点箭头为什么没反应」（只读；行同时进取证环 mapFitTrace）
    for _, l in ipairs(MDQ.nudgeLines()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  elseif sub == "重复" or sub == "dup" then
    -- ★1.75.59q：同序号重复的**只读体检**（用户截图里那份「拖不动的重复图」就是它）
    for _, l in ipairs(MDQ.dupProbe()) do mfLog("[mapfit] %s", l) say("[mapfit] " .. tostring(l)) end
    return true
  end
  return false
end

-- 工具箱**模块行**（一行数据在 `Toolbox.lua`；控件/悬停/下拉/结算全在这里）
local TB_ROWS = rawget(_G, "EVAL_TB_MOD_ROWS")
if type(TB_ROWS) ~= "table" then TB_ROWS = {} rawset(_G, "EVAL_TB_MOD_ROWS", TB_ROWS) end
TB_ROWS["worldFog"] = function(r, it)
  if type(r) ~= "table" then return false end
  -- 主开关：读 = 合并真值（`MDQ.swm()`，1.75.59c 起 nil ⇒ 默认**关**）；写 = 唯一写口 `MDQ.fogSet`
  r.get = function() return MDQ.swm() end
  r.set = function(v) pcall(MDQ.fogSet, v and true or false) end
  r.extra:Hide()                       -- ★行上不重复显示摘要（只在 [设置] 悬停里）
  r.add.text:SetText(L("TB_LDDRAG_SET"))
  r.add.btn:Show()
  r.add.btn:SetScript("OnEnter", function()
    local tip = _G["GameTooltip"]
    if not tip or type(tip.SetOwner) ~= "function" or type(tip.AddLine) ~= "function" then return end
    pcall(tip.SetMinimumWidth, tip, 460)
    pcall(tip.SetOwner, tip, r.add.btn, "ANCHOR_RIGHT")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.AddLine, tip, L("TB_SM_SWM_TIP1"), 0.62, 0.82, 1.00)
    -- ★1.75.60d（用户：「某些区域地图如有偏移反馈插件评论,或者QQ 群.会进行偏移矫正」）：第二行 = 反馈渠道
    pcall(tip.AddLine, tip, L("TB_SM_SWM_TIP2"), 1.00, 0.82, 0.35)
    -- ★1.75.65：第三行 = **默认档说明**（本版起默认勾选（开）+ 区域实景；取消勾选 = 回到客户端原始地图）
    pcall(tip.AddLine, tip, L("TB_SM_SWM_TIP3"), 0.72, 0.92, 0.72)
    pcall(tip.Show, tip)
  end)
  r.add.btn:SetScript("OnLeave", function()
    local tip = _G["GameTooltip"]
    if tip and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  r.add.btn:SetScript("OnClick", function()
    if type(EVAL_DD_OPEN) ~= "function" then say("关闭世界迷雾设置失败：下拉控件未载入") return end
    -- ★1.75.59f：这是**用户主动点开的设置菜单** ⇒ 回显算「你问它答」，盖章让本模块的播报走常开出口
    if type(GetTime) == "function" then WF_ECHO_AT = GetTime() + WF_ECHO_SEC end
    -- ★1.75.59o：第一项 = **编辑模式**（本游戏专属坐标补偿；拖拽柄 + 地图右侧贴图列表只在它开着时出现）
    -- ★1.75.60z：**贴图版本这一项已彻底删除**（机制一起清理，见文件上方那段注释）。
    -- ★★★1.75.64：第三/四项 = **图层类型（区域彩图 / 区域实景）**，用户点名要**单选**：
    --   两行**互斥**（勾只给当前模式那一行；点谁切谁 ⇒ 天然单选），切换走唯一写口 `MDQ.layerSet`
    --   （它自己负责「关断四件事」：交还上一套的层 + 会话态清零 + 立刻刷一拍）。
    -- ★★★1.75.65（用户：「图片内的关闭世界迷雾这个选项可以删除.重复了.」）：**下拉里不再登记开关项**
    --   —— 开关的真值入口 = **工具箱这一行自己的勾选框**（外加等价命令 `/ehm mapfit swm on|off`）；
    --   下拉里再放一条「关闭世界迷雾！」= 同一个开关两个入口，既重复又容易各写一半。
    --   ⇒ 本下拉只剩三项，且**全是「不是开关」的档**（编辑模式 + 图层类型单选）。
    local items = { L("TB_SM_EDIT"), L("TB_SM_LAYER_ART"), L("TB_SM_LAYER_JPG") }
    local keys = { "editMode", "layerArt", "layerJpg" }
    -- ★★★1.75.65b（用户：「关闭世界迷雾->设置->**图层单选切换要能正确的更新到弹窗内**」）：
    --   勾的状态**只有一个来源 = `menuSel()` 现算**（编辑模式 = 第 1 行；图层类型 = 当前模式那一行）。
    --   ★为什么必须这样：下拉组件在 `multi` 模式下点一行**只切换那一行自己的勾**（`ddUI.sel[pi]`），
    --     它**不认识「互斥」** ⇒ 单选语义（另一行必须熄）只能由宿主刷；不刷就会出现
    --     「两行都勾着」/「勾在彩图上而实际是实景」= **弹窗与真值不一致**（用户这次报的就是它）。
    --   ★做法照抄本项目的既有 idiom（`Toolbox.lua` 的频道互斥菜单 / `DataSearch.lua` 的负面类型多选）：
    --     打开时 `selected = menuSel()`、**每次点完再 `EVAL_DD_SYNC(menuSel())` 整表重绘**
    --     —— 与「勾选状态每次由数据重算后整表重绘」是同一条纪律，绝不靠面板自己那份状态。
    --   ★顺带修正两种「乐观勾」：被点那一项其实没生效（例如切到同一个模式 = `layerSet` 幂等返回 false）
    --     时，重绘会把勾**按真值拨回去**（组件已经先把那一行的勾切掉了）。
    local function menuSel()
      local t = {}
      if MDQ.editOn() then t[1] = true end
      if MDQ.jpgMode() then t[3] = true else t[2] = true end     -- ★单选：只勾当前那一行
      return t
    end
    local tips = { { L("TB_SM_EDIT_TIP1") }, { L("TB_SM_LAYER_TIP1") }, { L("TB_SM_LAYER_TIP2") } }
    EVAL_DD_OPEN(r.add.btn, items, function(pi, on)
      -- ★用户点我们自己的菜单项 = **他主动问的**（同 1.75.59p 的面板按钮口径）⇒ **先盖章再动手**：
      --   章晚了（动作里面那几句 `say` 已经发出去）就挡在「调试日志」门外 = 用户点了像没反应。
      if type(wfEcho) == "function" then pcall(wfEcho) end
      if keys[pi] == "editMode" then pcall(MDQ.editSet, on == true)
      elseif keys[pi] == "layerArt" then pcall(MDQ.layerSet, MDQ.LAYER_ART)
      elseif keys[pi] == "layerJpg" then pcall(MDQ.layerSet, MDQ.LAYER_JPG) end
      -- ★单选 / 状态回正：面板不关 ⇒ 当场按真值整表重画勾（唯一来源 = menuSel()）
      if type(EVAL_DD_SYNC) == "function" then pcall(EVAL_DD_SYNC, menuSel()) end
      if type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end
    end, { multi = true, selected = menuSel(), locked = {}, tips = tips })
  end)
  return true
end

-- ★★★1.75.57c 审计（与 1.75.57 清掉那 25 个死 `EVAL_WF_*` 用同一把尺子）：这里原来还挂着 8 个旧名字
--   （`EVAL_SM_FOG_ON` / `FOG_SET` · `SWM_ON` / `SWM_SET` · `STALE_ON` / `STALE_SET` · `SWM_TIP` / `SWM_TIPS`），
--   一律**转调**当时的合并写口。搬家之后**活入口已经全部就位**（工具箱模块行 `TB_ROWS["worldFog"]` 的勾选框
--   与 `[设置]` 下拉 · `/ehm mapfit swm [on|off]` · 模块自己的 `MDQ.cmd`），而全仓扫（`.lua` / `.js` / `.toc`
--   的**非注释行**）对这 8 个名字**零引用** ⇒ 按纪律「读值口要么挂在活命令上、要么别加」**删掉**：
--   留着就是下一轮「误接回来」的耦合面（`EVAL_SM_SWM_SET` 这种名字最容易被当成「官方写口」再接一次）。
--   ★判据 = `tmp/swm_harness.js` 的白名单钉（MOD 里出现旧别名 ⇒ 当场转红）。

-- ============ 载入期一次性清账 / 归位（1.75.56 从 SimpleMap 的载入钩子搬过来）============
--   ★为什么必须在 VARIABLES_LOADED：文件执行期存档表还是空的（迁移早调 = 从空表继承出空配置）。
--   ★★用**新标记键** `probeCleared52`：`cacheCleared51` 在老存档里已经是 true，复用它这段根本不跑。
do
  if type(CreateFrame) == "function" and type(UIParent) ~= "nil" then
    local mg = CreateFrame("Frame", "EH_WF_CLEAN", UIParent)
    mg:RegisterEvent("VARIABLES_LOADED")
    mg:SetScript("OnEvent", function()
      wfMigrate()   -- ★1.75.56c：把老存档里属于迷雾的键搬进自己的子树
      -- ① 上一轮「全图核验」探针的存档键一次性清掉（那些命令已整条删除）
      if not SM_CFG.probeCleared52 then
        SM_CFG.probeCleared52 = true
        local np, nk = 0, {}
        for _, k in ipairs({ "mapData", "mapDataLog", "mapDataArm" }) do
          if SM_CFG[k] ~= nil then SM_CFG[k] = nil np = np + 1 table.insert(nk, k) end
        end
        if np > 0 and type(say) == "function" then
          say("世界迷雾：已清理上一轮全图核验探针的存档（" .. table.concat(nk, " / ") .. "）")
        end
      end
      -- ② 只在本会话有效的诊断档（策略/详细日志）回默认 —— 忘了关就会一直刷屏
      if SM_CFG.mapFitMode ~= nil then SM_CFG.mapFitMode = nil end
      if SM_CFG.mapFitVerbose ~= nil then SM_CFG.mapFitVerbose = nil end
      -- ③ 清本地地图签名缓存 + 旧调试日志（一次性；用户 1.75.51 定的口径）
      if not SM_CFG.cacheCleared51 then
        SM_CFG.cacheCleared51 = true
        local nc = 0
        for _, k in ipairs({ "mapFitOrig", "mapFitVer", "mapFitTrace", "mapFitCapLog" }) do
          if SM_CFG[k] ~= nil then SM_CFG[k] = nil nc = nc + 1 end
        end
        if nc > 0 then pcall(mfLog, "清缓存：存档老键 %d 个（一次性）", nc) end
      end
      -- ④ ★★★1.75.65（用户：「默认设置 开启世界迷雾->选中实景地图,关闭彩图」）：**默认档 = 开 + 区域实景**。
      --   · `swmOverlay` / `staleClean`（1.75.52 起同一个控制）：键为 nil（从没写过）⇒ **落成显式 true**
      --     —— 项目纪律：开关值要显式，别让「默认」反复顶改；★**显式 false（用户主动关过）永远是关**，绝不顶改。
      --   · `layerMode`：nil ⇒ 落成显式 `"jpg"`；★**显式 `"art"`（用户选过彩图）保持彩图**。
      --   ★老用户升级时这是**行为改变**（1.75.59c~1.75.64 那几版默认是「关 + 彩图」）⇒ **如实播报一次**，
      --     绝不悄悄改掉；之后键已存在 ⇒ 不再播报。
      --   ★老版本单独关过 / 单独开过某一边的存档：只认它自己那一键的显式值（另一半缺失才跟默认走）。
      local wfFresh = (SM_CFG.swmOverlay == nil)
      if wfFresh then
        if SM_CFG.staleClean == false then SM_CFG.swmOverlay = false     -- ★不许写成 and/or 链（false 会被吞）
        else SM_CFG.swmOverlay = true end
      end
      if SM_CFG.staleClean == nil then SM_CFG.staleClean = (SM_CFG.swmOverlay == true) end
      local lmFresh = (SM_CFG.layerMode == nil)
      if lmFresh then SM_CFG.layerMode = MDQ.LAYER_JPG end
      -- ★1.75.59o：**编辑模式也落成显式布尔**（默认关；项目纪律：开关值不留 nil，别让「默认」反复顶改）。
      --   补偿表本身（`edit` / `editJpg` / `editLog`）是**用户数据**，一律不碰（只有用户显式「编辑 清」才动）。
      if SM_CFG.editMode == nil then SM_CFG.editMode = false end
      -- ★1.75.60z：**分版本贴图的死键一次性清掉**（该机制已整条清理；留着只会让以后的排查
      --   看到 `texPack = "live"` 却找不到任何读它的代码）。键本身是配置不是用户数据 ⇒ 直接清。
      if SM_CFG.texPack ~= nil then SM_CFG.texPack = nil end
      -- ★1.75.69：**「贴图格式测试」的取证环一次性清掉**（`tools\TexTest.lua` + `media\TexTest\` 已按用户指令整条删除；
      --   它只写过 `EVAL_HELP_CONFIG.texTestCfg.ring` 这一个取证环 ⇒ 留着就是「有键无代码」的迷惑项）。
      local G = rawget(_G, "EVAL_HELP_CONFIG")
      if type(G) == "table" and G.texTestCfg ~= nil then G.texTestCfg = nil end
      if type(SM_CFG.edit) ~= "table" and SM_CFG.edit ~= nil then SM_CFG.edit = nil end
      if type(SM_CFG.editJpg) ~= "table" and SM_CFG.editJpg ~= nil then SM_CFG.editJpg = nil end
      if type(SM_CFG.editLog) ~= "table" and SM_CFG.editLog ~= nil then SM_CFG.editLog = nil end
      if wfFresh and type(say) == "function" then
        --   ★播报必须与**实际落成的值**一致（老存档里单独关过清理的那一支是关 ⇒ 不许照念「默认开」那套词）
        if MDQ.swm() then
          say("世界迷雾 = 开（本版起**默认就是「开 + 区域实景」**：不想让插件重画地图就取消工具箱里的勾选并 /reload；"
            .. "开关：工具箱 → UI 工具 →「关闭世界迷雾」）")
        else
          say("世界迷雾 = 关（★尊重你以前**单独关过「残留图层清理」**那一次选择 ⇒ 本版默认档没顶改它；"
            .. "要开：工具箱 → UI 工具 →「关闭世界迷雾」勾上并 /reload）")
        end
      end
      if lmFresh and type(say) == "function" then
        say("世界迷雾·图层类型 = **区域实景**（本版起的默认档）；要换回游戏手绘彩图：同一行的 [设置] → 「图层：区域彩图」")
      end
      -- ④b ★1.75.59l：**改动记号落盘**（每次 `/reload` 都刷一次）—— 存档里有了它，
      --   「客户端现在跑的是哪一份代码」当场可判（本节就是今天绕了一圈才确认「跑的是旧版」的那件事）。
      SM_CFG.buildTag = tostring(MDQ.BUILD)
      -- ⑤ **节拍与开关同步**（默认关 ⇒ 载入期就不挂 OnUpdate：关掉零动作 = 真摘，不是每帧早退）
      pcall(MDQ.beatSync)
      pcall(mg.UnregisterEvent, mg, "VARIABLES_LOADED")
    end)
  end
end

-- ============ 对外桥（只留**真正在用**的三个口）============
--   ★★★1.75.57 审计（用户：「世界迷雾功能独立于大地图缩放.不要做强关联.」）：原来这里挂了 27 个 `EVAL_WF_*`，
--     但搬家后宿主（SimpleMap）**只用两个** ⇒ 其余 25 个是**死口**（本项目纪律：读值口要么挂在活命令上、
--     要么别加 —— 死口就是下一轮「误接回来」的耦合面）。处置：只留下面三个，其余全删。
--   · `EVAL_WF_ON` —— 「迷雾开关开着没」（只读；`/ehm` 与诊断用，★**折算让位不许再用它** —— 见下一条）。
--   · `EVAL_WF_CMD` —— `/ehm mapfit 残留|贴图|perf|swm [on|off]|编辑 [on|off|配对|清|清全部]` 的命令分流（模块自带命令口）。
--   · `EVAL_WF_TAKES_MAP` —— ★1.75.57d：**「迷雾这一拍真的接管了本图吗」**（只读，转 `MDQ.takesMap`）——
--       折算让位的**唯一**判据（旧写法只看开关 ⇒ 触发「两边都不缩放探索层」那个用户报障）。
--   ★迷雾自己的渲染/护守/清理/收尾**不再对外暴露**：节拍帧 `EH_WF_FEAT` 与工具箱行都在本文件里，
--     宿主既不需要、也不该调用它们（这正是「不做强关联」的落地方式）。
EVAL_WF_ON = function() return MDQ.swm() end
EVAL_WF_TAKES_MAP = function() return MDQ.takesMap() end
EVAL_WF_CMD = function(sub) return MDQ.cmd(sub) end

