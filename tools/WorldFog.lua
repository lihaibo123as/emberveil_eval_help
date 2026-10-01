-- ============================================================
-- EH_WorldFog 世界迷雾（S_WorldMap 表驱动全渲染 + 残留清理 + 接管守护）
-- ★★★1.75.56 从 tools/SimpleMap.lua 整族搬出来（用户：「将开启迷雾功能独立个脚本文件代码管理」）——
--   为什么要独立：这一族与「缩放大地图」（黑幕/透明/缩放/位置记忆/探索层折算）是两件独立的事，
--   混在一个文件里时，任何一边的改动都可能把另一边带坏（1.75.52 摘「探索层适配」就是这么连带摘掉的）。
--   · 本文件**只放迷雾**：`MDQ` 全族（渲染/池位/护守/残留清理/贴图来源/开关收尾/体检探针）。
--   · 与 SimpleMap 的往来**一律走桥**（载入期零依赖、调用时才读）：
--       - 本文件要用 SimpleMap 的 8 个内部件（配置表 / 地图身份 / 有效缩放 / 播报出口）
--         ⇒ 由 SimpleMap 暴露 `EVAL_SM_*`，这里用**懒代理**接（见下 `br()` 与别名段）。
--       - SimpleMap 要用本文件的 ⇒ 本文件末尾统一挂 `EVAL_WF_*`。
--   · 载入期**零副作用**（不建帧 / 不挂事件 / 不读写存档 / 不建计时器）：只有表与函数声明。
--   · 载入顺序：`.toc` 里排在 `tools\SimpleMap.lua` **之后**（桥是调用时读，晚载入也不会踩空）。
-- ============================================================

-- 桥读取器：拿到就调，拿不到返回 nil（**绝不缓存** —— 载入期 SimpleMap 可能还没跑完）
local function br(name)
  local f = rawget(_G, name)
  if type(f) == "function" then return f end
  return nil
end

-- 配置子树：懒代理（读写都现取 EVAL_SM_CFG()，与 SimpleMap 的 EH_SIMPLEMAP_CFG 是**同一张表**）
--   ★拿不到桥时退化成一张**本地孤儿表**（功能等于关着）—— 绝不抛错、也绝不静默改别人的表。
local WF_ORPHAN = {}
local SM_CFG = setmetatable({}, {
  __index = function(_, k)
    local g = br("EVAL_SM_CFG")
    local t = g and g() or nil
    if type(t) == "table" then return t[k] end
    return WF_ORPHAN[k]
  end,
  __newindex = function(_, k, v)
    local g = br("EVAL_SM_CFG")
    local t = g and g() or nil
    if type(t) == "table" then t[k] = v return end
    WF_ORPHAN[k] = v
  end,
})

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
MDQ.srcPick = {}     -- 地图 → 选中的写法："own:blp" / "own:tga" / "own:raw" / "client" / "none"
                     --   （`texPath` 按它拼；`srcOf` 把前三种归一成 "own"）
MDQ.ownExtOf = function(key)
  local s = tostring(key)
  if string.sub(s, 1, 4) ~= "own:" then return "" end
  local e = string.sub(s, 5)
  if e == "raw" then return "" end
  return "." .. e
end

-- 本图的贴图来源（每图判一次，缓存）："own:blp" / "own:tga" / "own:raw" / "client" / "none"
MDQ.srcKey = function(file)
  local s = MDQ.srcPick[file]
  if s ~= nil then return s end
  local m = MDQ.areaOf(file)
  local areas = {}
  if type(m) == "table" then for a in pairs(m) do table.insert(areas, a) end end
  table.sort(areas)
  local a0 = areas[1]
  if a0 == nil then MDQ.srcPick[file], MDQ.texSrc[file] = "none", "none" return "none" end
  local unclear = false
  for _, ext in ipairs(MDQ.ownForms) do
    local own = MDQ.probeTrust(string.format("%s%s\\%s1%s", MDQ.ownPfx, file, a0, ext))
    if own == true then
      local key = (ext == "") and "own:raw" or ("own:" .. string.sub(ext, 2))
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

-- 实际写进 `SetTexture` 的路径（自带那份能用就用自带的 ⇒ 拷进 media 即自包含）
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
  out[table.getn(out) + 1] = string.format("贴图体检：地图=%s（%sx%s）｜ 表里 %s ｜ 来源判定=%s",
    tostring(file), tostring(w), tostring(h),
    (function() local m = MDQ.areaOf(tostring(file)); if type(m) ~= "table" then return "**没有这张图**" end
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
  local m = MDQ.areaOf(tostring(file))
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
    out[table.getn(out) + 1] = string.format("② 本表 %d 区 ｜ 首个区域=%s ⇒ 我们拼的路径（自带那份逐个写法都试）：",
      table.getn(areas), tostring(a0))
    for _, ext in ipairs(MDQ.ownForms) do
      local p = string.format("%s%s\\%s1%s", MDQ.ownPfx, tostring(file), tostring(a0), ext)
      out[table.getn(out) + 1] = fmt(p, MDQ.probeTrust(p))
    end
    out[table.getn(out) + 1] = fmt(cliP, rc)
    out[table.getn(out) + 1] = "　（每个写法都带**负对照**：同目录同后缀的不可能文件名；对照也说「有」⇒ 该写法判不出 ⇒ 退回客户端）"
    local key = tostring(MDQ.srcKey(tostring(file)))
    local src = MDQ.srcOf(tostring(file))
    out[table.getn(out) + 1] = "　⇒ 选中写法：" .. key
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

-- 开关真值（唯一入口）：`SM_CFG.swmOverlay`（nil/false = 关 = 默认；true = 开）。
--   ★**落存档**（这是产品开关，与「只在本会话有效」的诊断档不同）；写入点只有两个：
--     `EVAL_SM_SWM_SET`（设置下拉 / 命令都走它）与老键迁移。
MDQ.swm = function()
  -- ★★★1.75.52（用户：「缩放大地图->设置->**默认开启全图**」）：真值 = `SM_CFG.swmOverlay`，**默认开**——
  --   键为 nil ⇒ **当场物化 true**（本项目「默认开」的定式，同 EC/HH）；**显式关过（false）永远是关**
  --   （读的时候绝不用 `or true` 顶回用户的选择）。
  if type(SM_CFG) == "table" and SM_CFG.swmOverlay == nil then SM_CFG.swmOverlay = true end
  return (type(SM_CFG) == "table") and SM_CFG.swmOverlay == true
end

-- 期望分块数（列×行）
MDQ.tiles = function(w, h)
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
MDQ.expectRect = function(rec, t)
  if type(rec) ~= "table" then return nil end
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
MDQ.hideFrom = function(from, file)
  local n = 0
  local lo = tonumber(from) or 1
  if lo < 1 then lo = 1 end
  for i = lo, MDQ.poolMax do
    local t = rawget(_G, "WorldMapOverlay" .. tostring(i)) or MDQ.own[i]
    if t ~= nil then
      local ours = (MDQ.ownSet[t] == true)
      -- ★只有「还没记过账的客户端池位」才需要读一次 IsShown（记过的不再读 ⇒ 稳态零额外开销）
      local wasShown = false
      if (not ours) and MDQ.holdHid[t] == nil then
        local okS, sh = pcall(t.IsShown, t)
        wasShown = (okS and sh == true)
      end
      pcall(t.Hide, t)
      -- ★1.75.54：藏了就**作废那一格的写前比对**（否则下次要显示它时会被判「没变」而不 Show ⇒ 缺块）
      if MDQ.slot[i] ~= nil then MDQ.slot[i].shown = false end
      if wasShown then pcall(MDQ.holdNote, t, file, "接管藏（多余池位）") end
      n = n + 1
      if i > (tonumber(MDQ.poolSeen) or 0) then MDQ.poolSeen = i end
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
MDQ.areaOf = function(file)
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
  MDQ.newN = 0
  -- ★★★1.75.52 六改 c：**本拍我们真正写过的那批对象**（`wroteObj`）—— 「接管守护」的安全底线：
  --   守护只许藏「本拍**没**写过、名字又属池位族」的东西；**一个都没认出来 ⇒ 判不出 ⇒ 一个字节都不碰**。
  --   真机日志取证（`/ehm mapfit 残留` 落盘）：`渲染 22 块（客户端既有 0 ｜ 新加 22）` 与
  --   `守护：藏原生 22 ｜ 枚举池位 22` **同时出现** ⇒ 枚举里那 22 个不是我们画的（我们画的没被枚举到
  --   或身份每拍都变）⇒ 旧写法会把它们当原生全藏，等于把我们刚画的一起藏掉 = **整张空白图**。
  MDQ.wroteObj = {}
  MDQ.lastW, MDQ.lastH, MDQ.lastArea, MDQ.lastTex = nil, nil, nil, nil
  if type(m) ~= "table" then
    -- ★★★1.75.52 六改 b：**表里没有这张图 ⇒ 只收我们自建的那几层，客户端自己的探索层保持原样**
    --   （用户真机报障：「删完之后数据库查询出来的层有没添加进去，现在全都是空白的」——
    --    数据库没有这张图时**无从替代**，把原生全藏只会得到一片空白；
    --    本项目铁律「拿不到证据就一个字节都不碰」。）
    MDQ.lastRenderN = 0
    local hid = MDQ.hideOwnFrom(1)
    return 0, 0, false, true,
      ("本图不在 S_WorldMap 表里（数据库没有这张图 ⇒ 客户端自己的探索层**保持原样**；只收起我们自建的 " .. tostring(hid) .. " 层）"), 0, 0
  end
  local areas = {}
  for a in pairs(m) do table.insert(areas, a) end
  table.sort(areas)                 -- ★顺序必须确定（同一张图每次渲染的层序一致，便于逐层对照取证）
  local n, nArea, full = 0, 0, true
  local nExist, fail = 0, nil
  MDQ.wroteN, MDQ.skipN = 0, 0   -- ★1.75.54：本拍真发了几次写 / 因没变跳过了几块（取证 + 安全阀判据）
  for _, a in ipairs(areas) do
    local rec = m[a]
    local total = MDQ.tiles(rec and rec[1], rec and rec[2])
    if total > 0 then
      nArea = nArea + 1
      for t = 1, total do
        if n >= MDQ.poolMax then full = false fail = "max" break end
        local pw, ph, ox, oy = MDQ.expectRect(rec, t)
        if pw then
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
            and sg.file == file and sg.area == a and sg.tile == t then
            MDQ.skipN = MDQ.skipN + 1
          else
            -- ★★★1.75.54e：**写之前先把原值读下来**（只对「复用客户端自己的池位」这条来源）——
            --   关掉开关时靠它把这一格还原成客户端原来那份（否则我们的几何永远留在客户端对象上）。
            if how == "existing" then pcall(MDQ.origGrab, n, tex) end
            local fdw, fdh = MDQ.fileDim(pw), MDQ.fileDim(ph)
            pcall(tex.SetTexture, tex, MDQ.texPath(file, a, t))
            pcall(tex.SetTexCoord, tex, 0, pw / fdw, 0, ph / fdh)
            pcall(tex.SetWidth, tex, pw * k)
            pcall(tex.SetHeight, tex, ph * k)
            pcall(tex.ClearAllPoints, tex)
            pcall(tex.SetPoint, tex, "TOPLEFT", fr, "TOPLEFT", ox * k, -(oy * k))
            pcall(tex.Show, tex)
            MDQ.slot[n] = { tex = tex, file = file, area = a, tile = t, k = k, shown = true }
            MDQ.wroteN = MDQ.wroteN + 1
          end
          if MDQ.lastW == nil then
            MDQ.lastW, MDQ.lastH = pw * k, ph * k   -- ★**写进去的**（自证与播报都按它说）
            MDQ.lastTw, MDQ.lastTh = pw, ph         -- ★表值（播报里「表 X ⇒ 写 Y」两个都摊开）
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
  MDQ.hideFrom(n + 1, file)
  MDQ.lastRenderN = n   -- ★六改 b：本拍真的画出了几块（「接管守护」拿它判「有没有东西可替代」）
  local why = nil
  if not full then
    why = (fail == "max")
      and ("纹理池上限 " .. MDQ.poolMax .. " 已满（已渲染 " .. n .. " 块 ⇒ 表里还有区域没画出来）")
      or ("**本客户端建不出新图层**（CreateTexture 失败，已渲染 " .. n .. " 块）")
  end
  return n, nArea, true, full, why, nExist, (tonumber(MDQ.newN) or 0)
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
MDQ.origGrab = function(n, t)
  if t == nil then return nil end
  local rec = MDQ.origIdx[n]
  if rec ~= nil and rec.obj == t then return rec end
  rec = { obj = t, pts = {}, ok = true }
  local okt, tex = pcall(t.GetTexture, t)
  if okt then rec.tex = tex else rec.ok = false end
  local okw, w = pcall(t.GetWidth, t)
  if okw then rec.w = tonumber(w) end
  local okh, h = pcall(t.GetHeight, t)
  if okh then rec.h = tonumber(h) end
  local oks, sh = pcall(t.IsShown, t)
  if oks then rec.shown = (sh == true) else rec.ok = false end
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
  MDQ.origIdx[n] = rec
  return rec
end

-- 把复用的客户端池位**还回原样**（贴图 / UV / 宽高 / 锚点 / 显隐；幂等）。返回 还回 N 个, 抓不到原值 M 个。
--   ★抓不到原值（本客户端某个读口缺席 / 探针失败）⇒ **绝不把我们写的那份留在屏幕上**：先把这一格藏起来
--     （客户端下一次摆版式会自己恢复），并如实记一行 —— 宁可暂时少一块，也不留一张缩放不对的图。
MDQ.origRestore = function(why)
  local n, bad = 0, 0
  for idx, rec in pairs(MDQ.origIdx or {}) do
    local t = rec and rec.obj
    if t ~= nil then
      if rec.ok and rec.tex ~= nil and rec.w ~= nil and rec.h ~= nil and table.getn(rec.pts) > 0 then
        pcall(t.SetTexture, t, rec.tex)
        if rec.tc ~= nil then pcall(t.SetTexCoord, t, rec.tc[1], rec.tc[2], rec.tc[3], rec.tc[4]) end
        pcall(t.SetWidth, t, rec.w)
        pcall(t.SetHeight, t, rec.h)
        pcall(t.ClearAllPoints, t)
        for _, p in ipairs(rec.pts) do pcall(t.SetPoint, t, p[1], p[2], p[3], p[4], p[5]) end
        if rec.shown == true then pcall(t.Show, t) else pcall(t.Hide, t) end
        n = n + 1
      else
        bad = bad + 1
        pcall(t.Hide, t)
      end
      -- 交还给客户端 ⇒ 身份账一并撤掉（否则下一次接管会把它当「我们自建的」而不敢动它）
      MDQ.ownSet[t] = nil
      MDQ.wroteObj[t] = nil
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
  MDQ.newN = 0
  MDQ.saidMk = nil
  if n > 0 then
    pcall(mfLog, "收层（%s）：我们补建的 %d 个叠加层已 Hide（纹理不能销毁，只能藏；藏了就不再被当成客户端的层）",
      tostring(why), n)
  end
  return n
end

-- ★★★1.75.54d/54e：**「打开世界迷雾」关掉 = 把这一路上动过的东西全部交还给客户端**（幂等，一拍一次）。
--   顺序（即判据）：① `MDQ.release` = 藏起我们自建的层 + 还回守护/收尾藏过的原生层 + 还原复用池位的原值；
--                    ② 残留清理的账再还一次（它跟这个开关一起写，两族都不会漏）；
--                    ③ 会话状态复位（安全阀/渲染账/性能计数）⇒ 下次打开从零开始，不带着上一轮的降档跑。
--   ★**只做一次**（`MDQ.offDone` 门）：关着时 tick 每拍都会走到这里，逐拍还回是白烧（且会让播报刷屏）。
MDQ.shutdown = function(why)
  if MDQ.offDone then return 0 end
  MDQ.offDone = true
  MDQ.lastRenderN = 0
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
  local m = MDQ.areaOf(file)   -- ★六改 b：与 `MDQ.holdN` / `MDQ.render` 同一个表查找（大小写不敏感）
  -- ★★★1.75.53（用户：「插件要绝对独立…不然发布上去别人又可能找不到贴图」）：**贴图准入** ——
  --   表里有这张图，但「自带 media 那一份」与「客户端自带的 Interface\WorldMap 那一份」**都加载不出来**
  --   ⇒ **这一张图一帧都不接管**（不渲染、不藏原生、不建层），并且把之前藏过的原生层**当场还回**。
  --   依据 = 本项目铁律「拿不到证据就一个字节都不碰」：宁可保持客户端原样，也绝不画出一片空白图。
  if type(m) == "table" and MDQ.srcOf(file) == "none" then
    pcall(MDQ.release, "本图贴图加载不出来")   -- 把上一张图藏过的原生层与本图自建的层都还回/收起
    MDQ.lastRender = { map = file, n = 0, areas = 0, inTbl = true, full = false, k = 1, src = "none",
      why = "本应用加载不出这批贴图（自带 media\\WorldMap 与客户端 Interface\\WorldMap 都没有）" }
    if type(MDQ.noTexSaid) ~= "table" then MDQ.noTexSaid = {} end
    if not MDQ.noTexSaid[file] then
      MDQ.noTexSaid[file] = true
      pcall(smFitSay, "打开世界迷雾：地图=%s ｜ 本客户端**加载不出**这批探索层贴图"
        .. "（`media\\WorldMap\\%s\\…` 与 `Interface\\WorldMap\\%s\\…` 两份都探不到）"
        .. "⇒ **这一张图不接管**（客户端自己的探索层保持原样；不渲染、不藏原生）。体检：/ehm mapfit 贴图",
        tostring(file), tostring(file), tostring(file))
    end
    return 0, 0, "本图贴图加载不出来（不接管）"
  end
  -- ★★★1.75.51（用户：「缩放要根据当前缩放级别和数据库实时计算」）：倍率**现读**，不留常数。
  local k, kSrc = 1, "表里没有这张图（不渲染）"
  if type(m) == "table" then k, kSrc = MDQ.kLive(file, m, es) end
  -- ★1.75.54b：**节流那一拍强制整批重写**（`force = withGuard ~= false`）—— 客户端会在我们写完之后自己
  --   再摆一次它那批池位纹理（首次开图尤其明显），只靠「写前比对」会跳过重申 ⇒ 客户端那套缩放不对的
  --   几何留在屏上（用户报的「首次地图打开客户端自身的贴图缩放异常」）。逐帧那条 silent 路才用比对省开销。
  local n, nArea, inTbl, full, why, nExist, nNew = MDQ.render(file, k, withGuard ~= false)
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
    pcall(smFitSay, "打开世界迷雾：本拍耗时 **%.0f ms**（地图=%s ｜ %d 块 ｜ 客户端叠加层 %d 条）"
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
    local line = string.format("打开世界迷雾：地图=%s ｜ 表里 %d 区 ⇒ 渲染 %d 块（客户端既有 %d ｜ 新加 %d）"
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

-- 开关真值（唯一入口）：`SM_CFG.staleClean` —— nil = **默认开**（用户要的就是「别让不属这张图的贴图留在图上」）；
--   显式 false = 关（关掉零动作：不再新藏 + 当场把藏账里的层全部还回）。
MDQ.staleOn = function()
  return SM_CFG.staleClean ~= false
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
  --   ★**只在「本图在表里」时让位**（用户要求「全图默认开」之后这更重要）：表里没有这张图的图
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
--   所以要做好守护程序 —— **数量、存在性都要检查**」）⇒ **只在「打开世界迷雾」开着时接管**（用户选的口径 B）：
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
MDQ.HOLD_LEDGER_MAX = 600  -- ★真机日志取证：客户端每拍重建自己的池位 ⇒ 无界账一小时就攒到 3960 条

-- 池位名字里的**尾号**（`WorldMapOverlay7` → 7）；认不出（字母后缀 / 没有后缀）⇒ nil，**绝不猜**
MDQ.poolIdx = function(o)
  local nm = string.lower(frameName(o) or "")
  if string.find(nm, "worldmapoverlay", 1, true) ~= 1 then return nil end
  local d = string.match(nm, "(%d+)$")
  return d and tonumber(d) or nil
end

-- 本图**应有几块**（表推；数量口径唯一来源，与 `MDQ.render` 同一算法与同一上限）
--   ★1.75.54：**按图名缓存** —— 它每拍被 `holdTick` 与 `staleTick` 各调一次，逐拍遍历整张区域表是白费；
--   表是**载入期常量**（生成物），所以缓存安全；`MDQ.holdNCache` 只随访问过的图增长（≤ 图数）。
MDQ.holdNCache = {}
MDQ.holdN = function(file)
  local key = tostring(file or "")
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
MDQ.holdNote = function(o, file, tag)
  if o == nil or MDQ.holdHid[o] ~= nil then return false end
  local nm = frameName(o)
  local okp, path = pcall(o.GetTexture, o)
  if not okp then path = nil end
  if MDQ.holdOrder == nil then MDQ.holdOrder = {} end
  MDQ.holdHid[o] = { name = nm, path = tostring(path), again = 0 }
  table.insert(MDQ.holdOrder, o)
  -- ★藏账**有界**（真机日志：一小时不到就攒到 3960 条 —— 客户端每拍重建自己的池位对象
  --   ⇒ 无界账会把内存与「关开关时逐个 Show」都拖垮）。超上限时把最老的**放回去**（绝不永久藏）。
  while table.getn(MDQ.holdOrder) > MDQ.HOLD_LEDGER_MAX do
    local old = table.remove(MDQ.holdOrder, 1)
    if old ~= nil and MDQ.holdHid[old] ~= nil then
      pcall(old.Show, old)     -- ★放回（绝不永久藏）
      MDQ.holdHid[old] = nil
    end
  end
  MDQ.staleLogPut(string.format("%s：地图=%s ｜ 客户端原生层 %s ｜ 贴图=%s",
    tostring(tag or "接管藏"), tostring(file), tostring(nm), tostring(path)))
  return true
end

-- ★接管守护（**每拍都跑**）：藏原生 + 数量守护（超出本图块数的池位）+ 存在性守护（我们自建的块被藏就复位）
--   返回：藏了原生 N 个, 复位我们自建的 M 个, 枚举到池位 K 个, 本图应有 W 块, 「又冒出来再藏」A 次
MDQ.holdTick = function(file)
  if not MDQ.swm() then return 0, 0, 0, 0, 0 end
  local fr = _G["WorldMapDetailFrame"]
  if not ((type(fr) == "table" or type(fr) == "userdata") and type(fr.GetRegions) == "function") then
    return 0, 0, 0, 0, 0
  end
  local want = MDQ.holdN(file)
  local drew = tonumber(MDQ.lastRenderN) or 0
  -- ★★★1.75.52 六改 b（用户真机报障「全都是空白的」）：**数据库里没有这张图 / 一块都没画出来**
  --   ⇒ **一个字节都不碰**（客户端的探索层保持原样）。理由两条：
  --     ① 本项目铁律「拿不到证据就一个字节都不碰」—— 不知道这张图该有什么，就没有替代依据；
  --     ② 旧写法（原生全藏 + 不自行添加）在「表里没有这张图」时 = **整张图空白**，比残留更糟。
  if want <= 0 or drew <= 0 then return 0, 0, 0, want, 0 end
  local okr, regs = pcall(function() return { fr:GetRegions() } end)
  if not okr then return 0, 0, 0, want, 0 end
  local hid, reshow, seen, again, oursSeen = 0, 0, 0, 0, 0
  local kills, shows = {}, {}
  -- ===== 第一趟：只**判定**，一个字节都不写 =====
  for _, o in ipairs(regs) do
    -- 唯一的证据 = **名字**属叠加层池位族；名字不合（底图瓦片 / 匿名装饰）⇒ 一个字节都不碰
    if o ~= nil and MDQ.stalePoolName(o) then
      seen = seen + 1
      local idx = MDQ.poolIdx(o)
      -- ★★★1.75.54c（真机 `/ehm mapfit 残留` 截图定案）：**旧身份账在本客户端永远不成立** ——
      --   枚举出来的 `WorldMapOverlay*` 与我们写进去的那批**不是同一批对象**（同号还能出现两条），
      --   于是每拍都判「盲 ⇒ 一个字节都不碰」⇒ **原生层一个都没被藏**（用户看到的叠影/缩放异常）。
      --   ⇒ 「我们画的」改成**对着当前活句柄比对象**（序号取自名字）：
      --     `o == _G["WorldMapOverlay"..idx]`（客户端当前活的那条池位，我们正往里写）
      --     或 `o == MDQ.own[idx]`（我们自建的）。**同一个序号的两条里只有活的那条算我们的**，
      --     另一条（重复/残留）照旧按「数量守护 / 非我们 ⇒ 藏」处理 ⇒ 叠影消失、我们画的不受影响。
      --   ★旧账（`ownSet`/`wroteObj`）仍然算数（二者取并集，只增不减，绝不把我们的层误藏）。
      local live = (idx ~= nil) and (o == rawget(_G, "WorldMapOverlay" .. tostring(idx)) or o == MDQ.own[idx])
      local ours = live or (MDQ.ownSet[o] == true) or (MDQ.wroteObj[o] == true)
      if ours then oursSeen = oursSeen + 1 end
      local oks, shown = pcall(o.IsShown, o)
      -- ★原生层**不看序号**（它就是客户端自己那套 / 上一张图的残留）；我们自建的层按**数量**判（超出即藏）
      local kill = (not ours) or (idx ~= nil and idx > want)
      if oks and shown == true and kill then
        table.insert(kills, { o = o, ours = ours })
      elseif oks and shown == false and ours and idx ~= nil and idx <= want then
        table.insert(shows, o)   -- 存在性守护：我们自建的块被藏了 ⇒ 待会儿还回来
      end
    end
  end
  -- ★★★第二趟之前的安全门（1.75.52 六改 c；真机日志取证换来的）：**枚举里一个「我们画的」都认不出**
  --   而本拍明明画出来了 ⇒ 本客户端要么把我们建的纹理排在下一次枚举里、要么对象身份每拍都换
  --   ⇒ **判不出谁是原生 ⇒ 一个字节都不碰**（旧写法会把它们当原生全藏 = 连自己画的一起藏 = 空白图）。
  --   ★出声一次（常开出口）并指明取证命令，绝不让它变成静默失效。
  if oursSeen == 0 and seen > 0 then
    MDQ.holdStat.map, MDQ.holdStat.want = tostring(file), want
    MDQ.holdStat.hid, MDQ.holdStat.again, MDQ.holdStat.reshow = 0, 0, 0
    MDQ.holdStat.seen, MDQ.holdStat.ours = seen, 0
    MDQ.holdStat.at = (type(GetTime) == "function") and GetTime() or 0
    MDQ.holdStat.blind = true
    local mkB = smMapKey() or tostring(file)
    if MDQ.holdSaidBlind ~= mkB then
      MDQ.holdSaidBlind = mkB
      pcall(smFitSay, "接管守护：地图=%s ｜ 枚举到 **%d** 个叠加层池位，但**一个都不是我们刚画的**"
        .. "（本拍画了 %d 块）⇒ **判不出谁是原生 ⇒ 一个字节都不碰**（宁可保留原生的，也绝不留空白图）。"
        .. "取证：/ehm mapfit 残留（首两行给渲染账与枚举数）",
        tostring(file), seen, drew)
    end
    return 0, 0, seen, want, 0
  end
  MDQ.holdStat.blind = false
  -- ===== 第二趟：动手（藏原生 + 数量守护），并复位被藏的我们自建的块 =====
  for _, o in ipairs(shows) do
    if pcall(o.Show, o) then reshow = reshow + 1 end
  end
  for _, it in ipairs(kills) do
    local o, ours = it.o, it.ours
    if pcall(o.Hide, o) then
      hid = hid + 1
      if not ours then
        local rec = MDQ.holdHid[o]
        if rec == nil then
          -- ★1.75.54e：新记一条走**唯一写账口**（有界 + 落盘 + 超上限放回最老的）
          MDQ.holdNote(o, file, "接管藏")
        else
          rec.again = (tonumber(rec.again) or 0) + 1
          again = again + 1
          -- ★「客户端又把它 Show 出来了」= 用户报障的那条现象；每个对象最多记 3 次（环有界、不刷屏）
          if rec.again <= 3 then
            MDQ.staleLogPut(string.format("接管再藏（第 %d 次）：地图=%s ｜ 原生层 %s（客户端自己又 Show 出来了）",
              rec.again, tostring(file), tostring(rec.name)))
          end
        end
      end
    end
  end
  local st = MDQ.holdStat
  st.map, st.want = tostring(file), want
  st.hid, st.again, st.reshow, st.seen = hid, again, reshow, seen
  st.ours = oursSeen
  st.at = (type(GetTime) == "function") and GetTime() or 0
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

-- 把我们藏过的**客户端原生层**全部还回（关开关 / 关功能 / 关图 / 关模块；幂等）⇒「绝不永久藏」
MDQ.holdShowAll = function(why)
  local n = 0
  for o in pairs(MDQ.holdHid) do
    pcall(o.Show, o)
    MDQ.holdHid[o] = nil
    n = n + 1
  end
  MDQ.holdOrder = {}
  if n > 0 then
    pcall(mfLog, "接管守护（%s）：把藏过的 %d 个客户端原生探索层全部 Show 还回", tostring(why), n)
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
    "接管守护（打开世界迷雾 %s）：地图=%s ｜ 表推本图应有 %d 块 ｜ "
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
          local ours = (MDQ.ownSet[o] == true)
          local idx = MDQ.poolIdx(o)
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

-- ============ 对外桥（SimpleMap 用；名字统一 EVAL_WF_*）============
--   ★SimpleMap 侧**绝不再直接碰 MDQ**（那是本文件私有的）⇒ 拆开后两边的耦合面就只有这一排名字。
--   ★★为什么**逐条写**（不用 `for k,v in pairs(API) do rawset(_G,"EVAL_WF_"..k,v) end` 那种动态挂）：
--     动态挂法对**全仓静态闸门**（`node scan_dangling.js`）是不可见的 ⇒ 一旦本文件掉出 `.toc` 或载入失败，
--     SimpleMap 里那 15 处调用就是**全局 nil 调用**（多半还被 pcall 吞掉 = 静默半死），而闸门一句话都不报。
--     逐条写 = 闸门看得见、grep 得到、以后改名也不会漏。
EVAL_WF_READY = function() return type(br("EVAL_SM_CFG")) == "function" end
EVAL_WF_ON = function() return MDQ.swm() end
EVAL_WF_STALE_ON = function() return MDQ.staleOn() end
EVAL_WF_HAS_LEDGER = function()
  local t = MDQ.staleHid
  if type(t) ~= "table" then return false end
  for _ in pairs(t) do return true end
  return false
end
EVAL_WF_RENDER = function(...) return MDQ.renderCurrent(...) end
EVAL_WF_RELEASE = function(...) return MDQ.release(...) end
EVAL_WF_SHUTDOWN = function(...) return MDQ.shutdown(...) end
EVAL_WF_STALE_SHOWALL = function(...) return MDQ.staleShowAll(...) end
EVAL_WF_HOLD_SHOWALL = function(...) return MDQ.holdShowAll(...) end
EVAL_WF_STALE_TICK = function(...) return MDQ.staleTick(...) end
EVAL_WF_HOLD_TICK = function(...) return MDQ.holdTick(...) end
EVAL_WF_STALE_FORGET = function(...) return MDQ.staleForget(...) end
EVAL_WF_STALE_NAMES = function(...) return MDQ.staleNames(...) end
EVAL_WF_STALE_PROBE = function(...) return MDQ.staleProbe(...) end
EVAL_WF_HOLD_PROBE = function(...) return MDQ.holdProbe(...) end
EVAL_WF_PERF_PROBE = function(...) return MDQ.perfProbe(...) end
EVAL_WF_TEX_PROBE = function(...) return MDQ.texProbe(...) end
EVAL_WF_CACHE_CLEAR = function(...) return MDQ.cacheClear(...) end
EVAL_WF_OFF_RESET = function() MDQ.offDone = false end
EVAL_WF_PERF_GUARD = function() return MDQ.perfGuard == true end
EVAL_WF_STALE_SEC = function() return MDQ.STALE_SEC end
EVAL_WF_STALE_GAP = function() return MDQ.STALE_GAP end
EVAL_WF_STALE_GAP_IDLE = function() return MDQ.STALE_GAP_IDLE end

