-- tools/Probes.lua —— 探针 / 取证命令的**集中地**（1.75.35；用户：「探针默认不载入.抽取到 ./tools/Probes.lua」）
--
-- ★★★载入契约（用户明确要求「探针默认不载入」）：**列进 .toc 预载，但载入期零副作用** ——
--   本文件顶层只做两件事：声明桥/局部量、把命令体登记进注册表 PR；
--   **绝不** CreateFrame / SetScript / RegisterEvent / 读写 SavedVariables / 建计时器。
--   一切资源都在**命令真的被敲**那一刻才建（首用才建，同 tools/HunterHelper.lua）。
--   ★为什么不能真正「文件级懒加载」：本客户端 LoadAddOn 是 **Protected**（插件调不了），也没有
--     文件读取 API ⇒ 唯一合法形式就是「toc 预载 + 载入期零副作用 + 首用才建」；
--     把文件从 .toc 拿掉 = 命令根本不存在（那不是懒加载，是删功能）。
--
-- ★★模块纪律（CLAUDE.md §5.1）：模块只准调**全局桥**，绝不调宿主 local ⇒ 本文件自带同名 local：
--   say → EVAL_SAY ｜ c() / cfg → EVAL_HELP_CONFIG（**懒代理**，载入期不抓快照）｜
--   warCfg() → EVAL_HELP_CONFIG.war ｜ wslots → EVAL_WSLOTS ｜ 其余一律走 EVAL_* 全局读值口。
--
-- ★调用方（EvalHelp.lua 的 /eh 斜杠链）只留一行接线：EVAL_PR_RUN("<ID>", msg)。
--   别名条件**仍留在主文件**（命令发现顺序与别名唯一性判据不变）。
--
-- ★**故意没搬进来**的 3 个大探针（留在 EvalHelp.lua）：go probe / go 探针关 / go mbicon ——
--   它们直接读写宿主的 ui / stui / minimapBtn / autoFrame / mbBack / mbWhy / auraTexOf / init / loadUI
--   等内部件（30+ 处），搬走得把这一堆全暴露成全局桥（面更大更脆）；它们本来也只在命令触发时才跑。

local PR = {} -- id -> function(msg)：命令注册表（载入期只登记，不执行）

-- ===== 桥（一律**调用时**读全局，绝不在载入期抓快照 —— 本项目老雷）=====
local function say(s)
  if type(EVAL_SAY) == "function" then pcall(EVAL_SAY, s) end
end
local function conf()
  local t = rawget(_G, "EVAL_HELP_CONFIG")
  return (type(t) == "table") and t or nil
end
local function c() return conf() end
-- cfg 懒代理：读写当场转发到 EVAL_HELP_CONFIG（定式：绝不写 at and f() or nil）
local cfg = setmetatable({}, {
  __index = function(_, k) local t = conf() return t and t[k] or nil end,
  __newindex = function(_, k, v) local t = conf() if t then t[k] = v end end,
})
local function warCfg() local t = conf() return t and t.war or nil end
-- wslots 懒代理（动作条扫描结果由 Engine 导出；载入期可能还没扫）
local wslots = setmetatable({}, {
  __index = function(_, k) local ws = rawget(_G, "EVAL_WSLOTS") return type(ws) == "table" and ws[k] or nil end,
})

-- ===== 调用入口（唯一出口）=====
function EVAL_PR_RUN(id, msg)
  local fn = PR[id]
  if type(fn) ~= "function" then
    say("探针模块：没有这个命令（" .. tostring(id) .. "）")
    return false
  end
  local ok, err = pcall(fn, tostring(msg or ""))
  if not ok then say("探针出错（" .. tostring(id) .. "）：" .. tostring(err)) end -- ★绝不静默：探针自己炸了也要说
  return ok
end

-- 读值口：模块登记了哪些命令（不解析中文文本）
function EVAL_PR_IDS()
  local out = {}
  for k in pairs(PR) do table.insert(out, k) end
  table.sort(out)
  return out
end

-- ===== 命令体（从 EvalHelp.lua 的 /eh 链原样搬来；只把宿主 local 换成上面的桥）=====

PR["LINKPROBE"] = function(msg)
  -- ★可选频道：默认密语自己（单机可测）；自密语不回声时改用 队伍/公会（需有人在同一频道）
  if type(EVAL_SHARE_LINK_PROBE) == "function" then
    local chanP = "WHISPER"
    if string.find(msg, "公会", 1, true) then chanP = "GUILD"
    elseif string.find(msg, "队伍", 1, true) or string.find(msg, "小队", 1, true) then chanP = "PARTY"
    elseif string.find(msg, "说", 1, true) then chanP = "SAY" end
    EVAL_SHARE_LINK_PROBE(chanP)
  else
    say("分享模块未载入（EVAL_SHARE_LINK_PROBE 不存在）")
  end
end

PR["LENPROBE"] = function(msg)
  if type(EVAL_SHARE_LEN_PROBE) == "function" then
    local chanL = "WHISPER"
    if string.find(msg, "公会", 1, true) then chanL = "GUILD"
    elseif string.find(msg, "队伍", 1, true) or string.find(msg, "小队", 1, true) then chanL = "PARTY" end
    EVAL_SHARE_LEN_PROBE(chanL)
  else
    say("分享模块未载入（EVAL_SHARE_LEN_PROBE 不存在）")
  end
end

PR["PROBEALL"] = function(msg)
  if type(EVAL_SHARE_PROBE_AUTORUN) == "function" then
    EVAL_SHARE_PROBE_AUTORUN("WHISPER")
  else
    say("分享模块未载入（EVAL_SHARE_PROBE_AUTORUN 不存在）")
  end
end

PR["ICONPROBE"] = function(msg)
    if type(EVAL_SHARE_ICON_PROBE) == "function" then
      EVAL_SHARE_ICON_PROBE("WHISPER")
    else
      say("图标探针：分享模块未载入（EVAL_SHARE_ICON_PROBE 不存在）")
    end
  -- ★★★1.73.42p 彩蛋「创世者亲临」：先给命令手动触发（用户：「先提供个命令.让我能触发创世神的关注」），
  --   真正的触发机制（写方案达到某机制）以后再接。机缘**只有一次**，用过就如实拒绝。
end

PR["SHPROBE"] = function(msg)
    if type(EVAL_SHARE_SEND_PROBE) == "function" then
      EVAL_SHARE_SEND_PROBE()
    else
      say("分享探针：Share 模块未载入（EVAL_SHARE_SEND_PROBE 不存在）")
    end
  -- ★★★1.74.32 框体探针（动作条1~4 / 队伍层·团队层 的真实帧名 + **被动打开层**：
  --   公会/属性/拍卖/邮箱/任务/技能树 等）。★为什么在主插件里也开一条入口：
  --   原来只有子插件 `/edb bars` 一条路，而子插件那句 `pcall` 会把错误**静默吞掉** ——
  --   真机上就出现过「跑了命令、聊天框什么都不打、存档里也没痕迹」（无法判断是没跑还是跑挂了）。
  --   这里的入口走 `EVAL_DF_PROBE_SAFE`（记录开始/错误阶段 + 播报错误原文），且不依赖子插件是否载入。
end

PR["FRAMES"] = function(msg)
    -- ★先打一行**即时回显**再干活：它的唯一作用是让「命令到底跑到没有」一眼可判 ——
    --   看到这行 = 命令到达了（结果要么打出来、要么出错留档）；看不到这行 = 命令压根没到
    --   （插件没载入 / 打错字 / 分派没接上）—— 这与「跑了一半死了」是完全不同的两件事，
    --   本轮真机就卡在这个无法区分上（子插件的裸 pcall 把错误吞了）。
    say("框体探针：命令已收到，开始扫描（约 1 秒，别急）…")
    if type(EVAL_DF_PROBE_SAFE) == "function" then
      EVAL_DF_PROBE_SAFE()
    elseif type(EVAL_DF_PROBE_BARS) == "function" then
      local ok, err = pcall(EVAL_DF_PROBE_BARS)
      if not ok then say("|cffff6060框体探针出错|r：" .. tostring(err)) end
    else
      say("框体探针：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
    end
  -- ★★★1.74.33 开窗探针（**只读取证**）：被动窗口「打开时/定时重设自定义属性」的可行性。
  --   要回答的是：客户端会不会在**开窗那一刻**把我们写进去的缩放/宽高覆盖掉（＝这功能是不是必需），
  --   以及每个目标**原生有没有** OnShow 脚本（决定「链式接管 OnShow」可行还是得包 Show / 轮询）。
  --   ★纪律同「框体探针」：即时回显 + 只读（组 218① 用写接口计数器钉住）+ 有界 60 秒（到点自停并摘脚本）。
  --   ★英文别名 `go attrprobe` 是新的（`GO ALIAS UNIQUE CHECK` 会守住不被静默顶掉）。
end

-- ★★★1.75.60s：**图层定位探针**（只读）—— 一条命令回答「谁盖住了谁 / 怎么把窗放到最顶层」。
--   起因（真机报障）：/reload 确认窗原先留在 `DIALOG` strata，而世界地图帧是 `FULLSCREEN` strata
--   ⇒ 从地图里点「保存」时窗**整个躲在地图背后**，用户看到的就是「点了没反应 / 无法点击」。
--   ① **光标下的帧**（GetMouseFocus）+ 它的**父链**（每级 strata/level/显隐）⇒ 它若不是你刚点的那个按钮，
--      就是它吃掉了点击；② **本插件各窗 vs 地图框的层级对照** ⇒ 一眼看出哪个窗在地图上面 / 下面。
--   ★判读口径（本客户端在案）：strata 顺序 = BACKGROUND < LOW < MEDIUM < HIGH < DIALOG < FULLSCREEN <
--     **FULLSCREEN_DIALOG** < TOOLTIP（★1.75.60x 补齐：原来漏了 FULLSCREEN_DIALOG，而本插件好几处正靠它压过地图）；
--     **先比 strata，再比 level**（strata 大的永远在上面 —— level 再大也翻不过去）；
--     **子帧永远画在父帧之上**，但**抬高父帧不带动子件** ⇒ 行 / 输入框必须各自 SetFrameLevel。
--   ★「放最外层」= **三档**（1.75.60x）：① 普通窗之上 = DIALOG + 90~100；② **压过地图**（地图是 FULLSCREEN）=
--     `FULLSCREEN_DIALOG` + 高层级（确认窗用 FULLSCREEN/4000；要压过地图里**所有件** ⇒ 层级**现算**
--     `max(500, 地图各件最高层级 + 40)`，**绝不写死**）；③ 真·最外层 = `TOOLTIP`（代价 = 盖住 GameTooltip）。
--   用法：`/eh go 层级`（光标下的帧 + 对照表）｜`/eh go 层级 <帧名>`（查具名帧，例：EVAL_HELP_CFG）
PR["LAYER"] = function(msg)
  local tail = string.match(tostring(msg or ""), "^go%s+%S+%s*(.*)$") or ""
  tail = string.gsub(string.gsub(tail, "^%s+", ""), "%s+$", "")
  -- 取值助手（全 pcall；读不到如实回 "?" —— 体检口自己不许成为新的故障源）
  local function gv(o, m)
    if o == nil or m == nil then return "?" end
    local ok, fn = pcall(function() return o[m] end)
    if not (ok and type(fn) == "function") then return "?" end
    local ok2, v = pcall(fn, o)
    if not (ok2 and v ~= nil) then return "?" end
    return tostring(v)
  end
  local function nm(o)
    if o == nil then return "?" end
    local v = gv(o, "GetName")
    if v == "?" or v == "" then return "(无名)" end
    return v
  end
  local function sh(o)
    local v = gv(o, "IsShown")
    if v == "true" or v == "1" then return "显示" end
    if v == "false" or v == "0" then return "收起" end
    return "?"
  end
  local function one(o)
    return string.format("%s[strata=%s level=%s %s]", nm(o), gv(o, "GetFrameStrata"), gv(o, "GetFrameLevel"), sh(o))
  end
  -- 父链（**有界**：最多 8 级 + seen 去环 —— 本项目铁律「递归/遍历必须有界」）
  local function chainOf(o)
    local out, cur, n, seen = {}, o, 0, {}
    while cur ~= nil and n < 8 and seen[cur] ~= true do
      seen[cur] = true
      local par = nil
      local ok, fn = pcall(function() return cur.GetParent end)
      if ok and type(fn) == "function" then
        local ok2, v = pcall(fn, cur)
        if ok2 then par = v end
      end
      cur = par
      n = n + 1
      if cur ~= nil then
        out[#out + 1] = nm(cur) .. "(" .. gv(cur, "GetFrameStrata") .. "/" .. gv(cur, "GetFrameLevel") .. ")"
      end
    end
    if #out == 0 then return "（没有父帧 / 读到顶了）" end
    return table.concat(out, " < ")
  end
  say("== 图层定位（/eh go 层级）==")
  -- ★1.75.60x：strata 全序**要写全**（原来漏了 `FULLSCREEN_DIALOG`，而本插件好几处正靠它压过地图 —— 漏写会误导判读）
  say("  口径：strata 顺序 BACKGROUND<LOW<MEDIUM<HIGH<DIALOG<FULLSCREEN<FULLSCREEN_DIALOG<TOOLTIP ｜ **先比 strata 再比 level**"
    .. " ｜ 子帧永远在父帧之上（但抬高父帧不带动子件）")
  if tail ~= "" then
    local q = rawget(_G, tail)
    if q == nil then
      say("★查具名帧「" .. tail .. "」：`_G` 里没有这个名字（拼错 / 还没建出来 / 在别的插件里）")
    else
      say("★具名帧「" .. tail .. "」= " .. one(q))
      say("  父链 = " .. chainOf(q))
    end
  end
  if type(GetMouseFocus) == "function" then
    local okf, mf = pcall(GetMouseFocus)
    if okf and mf ~= nil then
      say("① 光标下的帧 = " .. one(mf))
      say("  父链 = " .. chainOf(mf))
      say("  ★它若不是你刚点的那个按钮 ⇒ **就是它吃掉了点击**（拿它的名字去 _G 里对 / 子插件 /edb loot 光标帧 细看）")
    else
      say("① 光标下的帧：GetMouseFocus 读不到（鼠标不在任何帧上？）")
    end
  else
    say("① 光标下的帧：本客户端没有 GetMouseFocus")
  end
  local rows = {
    "EVAL_RELOAD_ASK_FRAME", "EVAL_HELP_CFG", "EVAL_HELP_DD", "EVAL_HELP_DD_CATCH", "EVAL_HELP_SE", "EVAL_HELP_UI",
    "EVAL_DF_POP", "EVAL_DF_RLOAD_ASK", "EVAL_WF_EDITCATCH", "EVAL_WF_EDITLIST", "EH_DB_UI",
    "EH_DS_MAPICON", "WorldMapDetailFrame", "WorldMapFrame", "WorldMapButton",
  }
  say("② 本插件各窗 vs 地图框（同一把尺子：strata/level/显隐）")
  for i = 1, #rows do
    local o = rawget(_G, rows[i])
    if o == nil then
      say("   " .. rows[i] .. " = 不在（没建出来 / 名字变了）")
    else
      say("   " .. one(o) .. " ← " .. rows[i])
    end
  end
  -- ★★★2026-10-02：通用下拉的**内部四件**（面板 / 首行 / 搜索框 / 全屏捕手）也要能一眼看到 ——
  --   它们是**匿名帧**（`_G` 里查不到，上面的名字表够不着），而「弹窗压在地图下面」恰恰就出在这一层
  --   （只抬父帧不抬子件 ⇒ 行留在 DIALOG ⇒ 面板背景压在地图上、一行字都看不见）。
  if type(EVAL_DD_DIAG) == "function" then
    local okD, s = pcall(EVAL_DD_DIAG)
    say("   通用下拉实测（EVAL_HELP_DD）：" .. (okD and tostring(s) or "读不到"))
  else
    say("   通用下拉实测：读值口 EVAL_DD_DIAG 不在（EvalHelp.lua 没载入？）")
  end
  -- ★★★2026-10-02 二改：「怎么放最外层」= **照抄子插件「图层调试」那一套**（用户：「直接参考子插件 图层调试
  --   是如何将层显示在地图层上的.直接参考 将标注下拉也这种方式打开」）—— 别只背 strata：
  say("★放最外层（照抄图层调试那一套；★**先问宿主、再问 strata**）：")
  say("   ① 压过普通窗/地图设置面板 ⇒ DIALOG + level 90~100")
  say("   ② ★★★**压过世界地图 = 宿主 WorldFrame + `FULLSCREEN_DIALOG` + level 500~800**（图层调试的面板 500 /")
  say("      它自己的下拉 800 就是这一档，真机截图实证能压过地图）—— ★**先看宿主**：**开全屏地图会隐藏 UIParent**")
  say("      （子插件 `EH_DebugBox.lua:3261` 在案），挂在 UIParent 上的帧**一个像素都不渲染**，这时 strata 抬多高都没用")
  say("   ③ **真·最外层** ⇒ TOOLTIP + 高层级（图层调试的高亮框就是它；★代价 = 会盖住 GameTooltip ⇒ 纯显示层记得 EnableMouse(false)）")
  say("   ★两条配套：**层级现算**（`max(800, 地图各件最高层级+40)`，绝不写死 —— 写死的常数换客户端就被压住）；")
  say("     **抬了父帧必须逐个抬子件**（行/搜索框/行内独立帧都要 `SetFrameStrata` + `SetFrameLevel`，两样都不能省）")
end

PR["DFT"] = function(msg)
  -- ★★★1.75.36d 图层拖拽**逐目标**探针（用户：「逐项排查下」）：即时回显 + 只读 + 出错**如实报**（绝不吞）。
  --   读数落**有界环 `EVAL_HELP_CONFIG.dfProbe`（40 行）**（见 tools/DragFrames.lua 的 EVAL_DF_PROBE_TARGETS）。
  say("框拖拽探针：命令已收到，逐目标读数（约 0.5 秒，别急）…")
  if type(EVAL_DF_PROBE_TARGETS) == "function" then
    local ok, err = pcall(EVAL_DF_PROBE_TARGETS)
    if not ok then say("|cffff6060框拖拽探针出错|r：" .. tostring(err)) end
  else
    say("框拖拽探针：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
  end
end

-- ★★★1.75.101 重置面板的**只读**状态口（用户：「工具箱->图层拖拽->重置->功能调整: 点击下栏有自定义属性设置的
--   层/窗口列表,支持多选.确定提交重置.」）：本命令把「为什么面板没开 / 有没有开出来 / 列表里几条 / 选中几条」
--   一次摊开 —— 面板是界面件，用户看不到内部状态时只能靠这条命令定性（也供离线判据读同一份读数）。
--   一个字节都不写（纯读）。
PR["DFRST"] = function(msg)
  say("重置面板：命令已收到")
  if type(EVAL_DF_RST_STATE) ~= "function" then
    say("重置面板：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
    return
  end
  local built, shown, cov, listed, rowsShown, more, selN, cap = EVAL_DF_RST_STATE()
  say(string.format("  面板：%s ｜ %s ｜ 遮罩 %s",
    built and "已建" or "未建", shown and "显示中" or "没显示", cov and "显示中" or "没显示"))
  say(string.format("  列表：有自定义属性设置的层 %d 条 ｜ 面板显示 %d 行（行池上限 %d）｜ 超出未列 %d 条",
    tonumber(listed) or 0, tonumber(rowsShown) or 0, tonumber(cap) or 0, tonumber(more) or 0))
  say(string.format("  选中：%d 条（点行切换；[确定] 只重置选中的）", tonumber(selN) or 0))
  if (tonumber(listed) or 0) <= 0 then
    say("  ★清单为空 = 没有任何层设过自定义属性 ⇒ 点 [重置] 会如实播报、**不开面板**（这是对的，不是坏了）")
  end
end

PR["DFG"] = function(msg)
  -- ★★★1.75.36f 属性设置守卫（0.3s）的取证 / 操作口。用户报障原话：「宠物栏位置.在设置之后.
  --   偶然性拾取物品之后会被还原位置.」⇒ 给「有自定义属性的目标」加了 0.3s 一拍的**只读**守卫
  --   （见 tools/DragFrames.lua 的 dfGuard* 段；聊天框永远排除 —— 它自带拖动/拖角缩放）。
  --   本命令三个用途：① 看它到底在不在跑、候选几个、重设过几次（状态行）；
  --   ② 「重设」= 不动等下一拍，**立刻**按存档重设一次（宠物栏刚被客户端挪走时的手动补救）；
  --   ③ 「开」/「关」= 手动武装 / 停下（诊断用；正式开关仍在工具箱那一行）。
  --   ★状态一律走 EVAL_DF_GUARD_STATE()（**不在别处复刻映射逻辑**）。
  say("框拖拽守卫：命令已收到")
  if type(EVAL_DF_GUARD_STATE) ~= "function" then
    say("框拖拽守卫：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
    return
  end
  -- ★★★1.75.36g 真机报障定案（用户：「出战斗也不会回到设置的位置」）：**总开关关着**（`dragFrames.on = false`）
  --   ⇒ 守卫根本没武装过（`dfGuard` 环里一条都没有就是佐证）⇒ 登录时按存档应用一次之后，客户端在战斗中/
  --   之后把它挪走，**没有任何人拉回来**。这一行必须显式打出来，否则用户看到的只是含糊的「停着」。
  local master = (type(EVAL_DF_ENABLED) == "function") and (EVAL_DF_ENABLED() and true or false) or nil
  if master == true then
    say("  总开关（工具箱 → 「图层拖拽」）= **开** = **编辑模式** ⇒ 按你的要求**守卫不跑**（正在摆位置时不跟你抢）")
    say("     摆完把它**关掉** = 进入**守护模式**：那一刻会先按存档应用一次、再武装守卫（只治**有自定义记录**的层）")
  else
    say("  总开关（工具箱 → 「图层拖拽」）= **关** = **守护模式** ⇒ 守卫**应当自动武装**（只治**有自定义记录**的层；"
      .. "没有记录的层一个字节都不碰）")
  end
  local m = tostring(msg or "")
  -- ★1.75.36m 快档接口在不在（老版本没有 ⇒ 如实说一句，别静默）
  local hasFast = (type(EVAL_DF_GUARD_FAST) == "function") and (type(EVAL_DF_GUARD_FAST_STATE) == "function")
  if string.find(m, "重设", 1, true) ~= nil or string.find(m, "now", 1, true) ~= nil then
    local n = tonumber(EVAL_DF_GUARD_TICK()) or 0
    say("框拖拽守卫：立刻按存档重设 —— 本轮动手 " .. tostring(n) ..
      " 个目标（0 = 没有任何目标漂移，或模块总开关没开）")
  elseif string.find(m, "常快", 1, true) ~= nil or string.find(m, "always", 1, true) ~= nil then
    -- ★1.75.36m 常驻 30 帧档（**本会话**，不落存档）⇒ 你自己 A/B 体感 + 用「压测」看数字
    if not hasFast or type(EVAL_DF_GUARD_FAST_TOGGLE) ~= "function" then
      say("框拖拽守卫：本版本没有快档接口（模块要 1.75.36m 起）")
    else
      local onF = EVAL_DF_GUARD_FAST_TOGGLE()
      say("框拖拽守卫：常驻快档 = " .. (onF and "**开**（0.033s ≈ 30 帧/秒，一直跑）"
        or "**关**（回到 0.3s + 事件触发的**有界**快窗口）"))
      say("  （本会话有效、/reload 后失效；想先看代价就跑一次「压测」）")
    end
  elseif string.find(m, "压测", 1, true) ~= nil or string.find(m, "perf", 1, true) ~= nil then
    -- ★★真机实测（不靠估算）：立刻连跑 N 拍（默认 30 ≈ 快档下 1 秒的量）并报每拍耗时
    if not hasFast or type(EVAL_DF_GUARD_PERF_RUN) ~= "function" then
      say("框拖拽守卫：本版本没有压测接口（模块要 1.75.36m 起）")
    else
      local kk, wrote, ms, cands = EVAL_DF_GUARD_PERF_RUN(tonumber(string.match(m, "(%d+)")) or 30)
      say("框拖拽守卫：压测 " .. tostring(kk) .. " 拍（候选 " .. tostring(cands) .. " 个）—— 动手 "
        .. tostring(wrote) .. " 次（>0 = 确有目标在漂，顺便看看谁在动）")
      if type(ms) == "number" then
        local per = ms / ((tonumber(kk) or 0) > 0 and tonumber(kk) or 1)
        say(string.format("  共 %.2f ms，平均 %.3f ms/拍", ms, per))
        say(string.format("  折算：常驻 30 帧/秒 ≈ %.1f ms/秒（每 100 秒花 %.2f 秒）；平时 0.3s 一拍 ≈ %.1f ms/秒",
          per * 30, per * 30 / 10, per / 0.3))
      else
        say("  本客户端读不到 GetTime ⇒ 耗时无法量化（功能不受影响）")
      end
    end
  elseif string.find(m, "快", 1, true) ~= nil or string.find(m, "fast", 1, true) ~= nil then
    -- ★开一段**有界**快窗口（默认 1.5s；`快 5` = 5 秒）
    if not hasFast then
      say("框拖拽守卫：本版本没有快档接口（模块要 1.75.36m 起）")
    else
      local left = EVAL_DF_GUARD_FAST(tonumber(string.match(m, "(%d+%.?%d*)")), "probe")
      say(string.format("框拖拽守卫：快窗口已开 —— 剩 %.1f 秒（这段里 0.033s ≈ 30 帧/秒；过窗自动回落 0.3s）",
        tonumber(left) or 0))
    end
  elseif string.find(m, "关", 1, true) ~= nil or string.find(m, "off", 1, true) ~= nil then
    EVAL_DF_GUARD_OFF("probe")
    say("框拖拽守卫：已停下（真摘 OnUpdate，不留空转 tick）")
  elseif string.find(m, "开", 1, true) ~= nil or string.find(m, "arm", 1, true) ~= nil then
    local ok = EVAL_DF_GUARD_ARM("probe")
    say("框拖拽守卫：" .. (ok and "已武装（0.3s 一拍 · 每拍只读 · 有漂移才写）" or "武装失败（CreateFrame 不可用）")
      .. ((ok and master ~= true) and "（**本会话临时**：/reload 后失效 —— 要长期生效请把总开关打开）" or ""))
  end
  local on, fixes, cands, skipped, moved, blocked, noWrite = EVAL_DF_GUARD_STATE()
  say("框拖拽守卫 = " .. (on and "在跑" or "停着") .. "｜候选 " .. tostring(cands) ..
    " 个（已勾选 ∧ 有能写回的自定义属性；★聊天框只守坐标、不守尺寸/属性）｜累计重设 " .. tostring(fixes) ..
    " 次｜拖拽中整拍跳过 " .. tostring(skipped) .. " 次｜累计重设目标 " .. tostring(moved) .. " 个")
  say("  战斗中：位置写被客户端拒 " .. tostring(blocked) .. " 次｜本场战斗已放弃重试的目标 " .. tostring(noWrite) ..
    " 个（>0 = 这个客户端战斗中不放行写位置；出战斗会自动恢复重试）")
  -- ★1.75.36m 节拍 + 实测成本（用户问「1s 30帧 · 对性能影响大不」⇒ 这一行必须一眼看出**现在跑多快、花了多少**）
  if hasFast and type(EVAL_DF_GUARD_FAST_STATE) == "function" then
    local left, always, arms, pn, pms = EVAL_DF_GUARD_FAST_STATE()
    local rate = "平时 0.30s 一拍"
    if always == true then
      rate = "常驻快档 0.033s（≈30 帧/秒）"
    elseif tonumber(left) and tonumber(left) > 0 then
      rate = string.format("快窗口 0.033s（剩 %.1f 秒，过窗自动回落）", tonumber(left))
    end
    local perMs = 0
    if tonumber(pn) and tonumber(pn) > 0 and tonumber(pms) then perMs = tonumber(pms) / tonumber(pn) end
    say(string.format("  节拍：%s｜快窗口累计开过 %d 次｜实测 %d 拍 共 %.1f ms（平均 %.3f ms/拍 ⇒ 30 帧/秒 ≈ %.1f ms/秒）",
      rate, tonumber(arms) or 0, tonumber(pn) or 0, tonumber(pms) or 0, perMs, perMs * 30))
    say("  （想量化代价：`/eh go 框拖拽守卫 压测` 立刻连跑 30 拍；想常驻 30 帧：`常快`；临时加速：`快 [秒]`）")
  end
  -- ★★一致性检查（编辑模式 ⇄ 守护模式是一对互斥态，错配必须**当场点明**，不许含糊）
  if master ~= true and on ~= true then
    say("  ★异常：现在是**守护模式**（总开关关着）却显示守卫「停着」—— 正常应由关掉开关那一刻自动武装；"
      .. "请把工具箱那一行**开一次再关一次**，本会话救急可用本命令的「开」。")
  elseif master == true and on == true then
    say("  ★注意：现在是**编辑模式**，守卫本不该在跑（多半是手动「开」过）—— 把开关关掉即回到守护模式。")
  end
  local t = conf()
  local ring = t and t.dfGuard
  if type(ring) == "table" and table.getn(ring) > 0 then
    say("最近 " .. tostring(table.getn(ring)) .. " 条重设计录（有界环 40 行）：")
    for i = 1, table.getn(ring) do say("  " .. tostring(ring[i])) end
  else
    say("还没有任何重设计录（= 从没漂移过；平时一个写 API 都不发）")
  end
end

PR["CBT"] = function(msg)
  -- ★★★1.75.36g 「战斗中底部条组被顶上去」取证口（用户：「进入攻击状态,会把宠物动作栏顶到上面去,排查下」）。
  --   只读取证：0.25s 一拍，只在**真的变了**的那一拍落一行（矩形/锚点/父级/帧层/显隐/缩放）。
  --   读数落**有界环** `EVAL_HELP_CONFIG.dragCombat`（160 行）—— 原话只进聊天 = AI 读存档时取证断链（老教训）。
  --   子命令：默认=武装 · `停`=提前收工（照旧落档）· `看`=复读上次结果 · `采样`=立刻采一拍。
  if type(EVAL_DF_COMBAT_PROBE) ~= "function" then
    say("战斗探针：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
    return
  end
  local m = tostring(msg or "")
  if string.find(m, "停", 1, true) ~= nil or string.find(m, "stop", 1, true) ~= nil then
    EVAL_DF_COMBAT_PROBE_STOP("manual")
  elseif string.find(m, "看", 1, true) ~= nil or string.find(m, "show", 1, true) ~= nil then
    EVAL_DF_COMBAT_PROBE_SHOW()
  elseif string.find(m, "采样", 1, true) ~= nil or string.find(m, "tick", 1, true) ~= nil then
    say("战斗探针：立刻采一拍 —— 记录 " .. tostring(EVAL_DF_COMBAT_PROBE_TICK()) .. " 拍")
  else
    EVAL_DF_COMBAT_PROBE()
  end
end

PR["ATTRPROBE"] = function(msg)
    say("开窗探针：命令已收到")
    if type(EVAL_DF_PROBE_ATTR) ~= "function" then
      say("开窗探针：框拖拽模块未载入（tools/DragFrames.lua 没进 .toc？）")
    elseif string.find(msg or "", "停", 1, true) ~= nil then
      EVAL_DF_PROBE_ATTR_STOP("manual")
    elseif string.find(msg or "", "看", 1, true) ~= nil then
      EVAL_DF_PROBE_ATTR_SHOW()
    else
      EVAL_DF_PROBE_ATTR()
    end
  -- ★★★1.74.32 被动窗口的「小图标」（默认开）：`/eh go 框体图标` 开/关，加「状态」只报状态。
  --   ★为什么要有这条：图标是默认开的，总得给用户一个关掉它的入口（否则只能改存档）。
  --   ★★英文别名**绝不能用 `go icons`** —— 那个名字早就被组 116 的「图标路径采集」占了
  --     （`/eh go icons` = 把客户端真实图标路径采集进存档）。本轮第一版就是撞了它，
  --     被断言组 116 当场抓到；现在另有 `GO ALIAS UNIQUE CHECK` 在源码层守这件事。
end

PR["PROFICON"] = function(msg)
  if type(EVAL_WAR_PROF_ICON_PROBE) == "function" then
    EVAL_WAR_PROF_ICON_PROBE()
  else
    say("方案图标探针：配置窗未载入（EVAL_WAR_PROF_ICON_PROBE 不存在）")
  end
end

PR["NAMEMENU"] = function(msg)
    if type(EVAL_TB_NAME_PROBE) == "function" then
      EVAL_TB_NAME_PROBE() -- 能力与记账都在它里面打出来并落盘
    else
      say("名字探针：工具箱未载入（EVAL_TB_NAME_PROBE 不存在）")
    end
  -- ★★★1.73.42r 重置（用户：「给我一个重置删除自定义的命令.测试」）——诊断/测试用，正常玩法没有这条路
end

PR["SHOTPROBE"] = function(msg)
  -- ★1.74.29 射击计时取证（见 Engine.lua 的 EVAL_SHOT_PROBE 注释：先问清「速度从哪来 / 锚点落哪个事件」）
  local subS = string.gsub(msg, "^go%s*", "")
  subS = string.gsub(subS, "^射击探针%s*", "")
  subS = string.gsub(subS, "^shotprobe%s*", "")
  if type(EVAL_SHOT_PROBE) == "function" then EVAL_SHOT_PROBE(subS)
  else say("射击探针：引擎未载入（EVAL_SHOT_PROBE 不存在）") end
end

PR["TRACKPROBE"] = function(msg)
  -- ★1.74.31 追踪取证；★1.75.2 补名字主路（GameTooltip:SetTrackingSpell）+ 事件监听
  --   （见 Engine.lua 的 EVAL_TRACK_PROBE 注释：本客户端只有 GetTrackingTexture / SetTrackingSpell / CancelTrackingBuff）
  local subT = string.gsub(msg, "^go%s*", "")
  subT = string.gsub(subT, "^追踪探针%s*", "")
  subT = string.gsub(subT, "^trackprobe%s*", "")
  if type(EVAL_TRACK_PROBE) == "function" then EVAL_TRACK_PROBE(subT)
  else say("追踪探针：引擎未载入（EVAL_TRACK_PROBE 不存在）") end
end

PR["MELEE"] = function(msg)
  -- 1.75.11 近战围攻取证（见 Engine.lua 的 EVAL_MW_* 注释：附近敌人无枚举 API、事件名不许猜）
  local subM = string.gsub(msg, "^go%s*", "")
  subM = string.gsub(subM, "^近战探针%s*", "")
  subM = string.gsub(subM, "^近战%s*", "")
  subM = string.gsub(subM, "^melee%s*", "")
  if type(EVAL_MW_CMD) == "function" then EVAL_MW_CMD(subM)
  else say("近战探针：引擎未载入（EVAL_MW_CMD 不存在）") end
end

PR["HOVPROBE"] = function(msg)
    if type(EVAL_SHARE_HOVER_PROBE) == "function" then
      EVAL_SHARE_HOVER_PROBE("WHISPER")
    else
      say("分享模块未载入（EVAL_SHARE_HOVER_PROBE 不存在）")
    end
  -- ★别用 `go probe`：那个已经被「光环探针」占了（同一个 if 链里的 go probe）→ 用 proberes
end

PR["PROBERES"] = function(msg)
  if type(EVAL_SHARE_PROBE_REPORT) == "function" then
    EVAL_SHARE_PROBE_REPORT()
  else
    say("分享模块未载入（EVAL_SHARE_PROBE_REPORT 不存在）")
  end
end

PR["ATK"] = function(msg)
  -- ★1.75.29 子命令 = **自动攻击流程取证环**（用户：「能否将自动攻击的内部流程添加一些日志.我这边方便演示」）：
  --   每拍记三类行（复查 / 键首 / 判定+按后读回），落 cfg.atkProbe（有界 40 行，已进 Core 残渣键清单）。
  --   ★读数一律走**读值口 EVAL_ATK_PROBE()**（命令与断言共用同一份，不解析中文文本）。
  local subA, subAN = string.match(msg, "^go %S+%s+(%S+)%s*(%S*)$")
  if subA == "log" or subA == "日志" then
    local p = (type(EVAL_ATK_PROBE) == "function") and EVAL_ATK_PROBE() or nil
    if type(p) ~= "table" then
      say("[自动攻击取证] 读值口 EVAL_ATK_PROBE 不存在（Engine 没载入？）")
    else
      local box = c().atkProbe
      local out = (type(box) == "table" and type(box.out) == "table") and box.out or {}
      local n = table.getn(out)
      local want = tonumber(subAN) or n
      if want > n then want = n end
      if want < 1 then want = 0 end
      say(string.format("[自动攻击取证] 取证轮 %d ｜ 环 %d/%s 行（累计写入 %s）%s",
        p.seq, n, tostring(p.max or "?"), tostring(p.boxN or "?"),
        (type(p.boxT) == "string") and (" · 读于 " .. p.boxT) or ""))
      say("  三类行：aN 复查（上一拍补按/施法之后自动射击还在不在） ｜ aN 键首（档位/状态/槽位读数/节流/目标） ｜ aN 判定（补没补、为什么没补）")
      local gs = (type(EVAL_ATK_GUARD_STATE) == "function") and EVAL_ATK_GUARD_STATE() or nil
      if type(gs) == "table" and gs.active then
        say(string.format("  复查窗口：★进行中（%s ｜ 起因：%s ｜ 已拍 %s ｜ 已补按 %s ｜ 历时 %.2fs ｜ 上限 %s 拍 / %s 次 ｜ 窗口总长 %ss）",
          tostring(gs.name), tostring(gs.why), tostring(gs.ticks), tostring(gs.presses),
          tonumber(gs.age) or 0, tostring(gs.ticksMax), tostring(gs.pressMax), tostring(gs.span or "?")))
      else
        say("  复查窗口：空闲（没在跑；有界窗口跑完就摘掉 OnUpdate，不常驻）")
      end
      if n == 0 then
        say("  环是**空的** ⇒ 从载入到现在**一次都没走过自动攻击流程**（开关关着，或一次键都没按）——")
        say("     演示前请确认：/eh cfg 一键宏设置里「自动攻击」已勾选，并且真的按过宏键。")
      else
        for i = n - want + 1, n do
          if out[i] then say("  " .. tostring(out[i])) end
        end
      end
      say("  ★怎么读：出现「★★补按之后又被关掉了」= 补按确实发生过、但**施法落在补按之后**（变体 B）；")
      say("    出现「★★上一拍键首=开、未补按 ⇒ 现在=关」= 那一拍压根没补（变体 A：判定用的是按键前的旧状态）。")
      say("  ★零足迹：开关关着时一段都不写；专属环落存档 cfg.atkProbe ⇒ /reload 后我这边可直接读。")
      say("  ★聊天框实时行要开着「方案技能日志」：/eh wdebug（关着只写专属环，不刷屏）。")
    end
  elseif subA == "clear" or subA == "清" then
    c().atkProbe = { out = {} }
    say("[自动攻击取证] 已清空 cfg.atkProbe 的环（取证轮号不受影响；存档那份要 /reload 才落盘）")
  else
    say("[自动攻击取证] 用法：/eh go atk log [行数] 看流程取证环 ｜ /eh go atk clear 清空")
  end
end

PR["ATKHELP"] = function(msg)
  say("[自动攻击取证] 用法：/eh go atk log [行数] 看流程取证环 ｜ /eh go atk clear 清空")
end

PR["TSELSUB"] = function(msg)
  -- ★★★1.75.12 子命令 = **选取目标调用点取证环**（用户报障：「选取目标:最近敌人 + 冲锋：不按键时目标
  --   也在尸体与活怪之间来回跳」）——静态审计已证明插件里没有任何定时器切目标 ⇒ 只能读**调用点**，
  --   看「调用到底在不在来」。Engine 侧唯一调用口 `tselInvoke` 每条都记（谁调的 + 前后目标快照 +
  --   第几发按键轮 + 接受/丢弃两条腿的计数），落 `cfg.selProbe`（有界 40 行，已进 Core 残渣键清单）。
  --   ★读数一律走**读值口 EVAL_TSEL_PROBE()**（命令与断言共用同一份，不去解析中文文本）。
  local subT, subN = string.match(msg, "^go %S+%s+(%S+)%s*(%S*)$")
  if subT == "log" or subT == "日志" then
    local p = (type(EVAL_TSEL_PROBE) == "function") and EVAL_TSEL_PROBE() or nil
    if type(p) ~= "table" then
      say("[选取取证] 读值口 EVAL_TSEL_PROBE 不存在（Engine 没载入？）")
    else
      local box = c().selProbe
      local out = (type(box) == "table" and type(box.out) == "table") and box.out or {}
      local n = table.getn(out)
      local want = tonumber(subN) or n
      if want > n then want = n end
      if want < 1 then want = 0 end
      say(string.format("[选取取证] 累计调用 %d 次 ｜ 接受发 %d / 被去抖丢弃 %d ｜ 上一发距 +%sms ｜ 上一条丢弃距 +%sms ｜ 环 %d/%s 行%s",
        p.seq, p.acc, p.skip, tostring(p.lastAcc or "?"), tostring(p.lastSkip or "?"), n, tostring(p.max or "?"),
        (type(p.boxT) == "string") and (" · 读于 " .. p.boxT) or ""))
      say("  格式：[选取] #调用号 p按键轮 谁调的 函数(参数) 前快照 ⇒ 后快照 变/没变")
      if n == 0 then
        say("  环是**空的** ⇒ 从载入到现在**一次选取目标都没执行过**（连去抖丢弃也没记）——")
        say("     这句话本身就是判据：若这时目标仍在跳，那就**不是本插件切的**。")
      else
        for i = n - want + 1, n do
          if out[i] then say("  " .. tostring(out[i])) end
        end
      end
      say("  ★`p<N>` = 第 N 发**被接受的** EVAL_GO（同一发里的多次调用同号）；`p-` = 不在按键那一轮里（编辑窗下拉/探针）。")
      say("  ★聊天框实时行要开着「方案技能日志」：/eh wdebug；读数已落存档 cfg.selProbe ⇒ （/reload 后）我这边也能直接读。")
    end
  elseif subT == "clear" or subT == "清" then
    c().selProbe = { out = {} }
    say("[选取取证] 已清空 cfg.selProbe 的环（内存里的计数不受影响；存档那份要 /reload 才落盘）")
  else
    say("[选取取证] 用法：/eh go tsel log [行数] 看调用点取证环 ｜ /eh go tsel clear 清空 ｜ /eh go tsel 跑原探针（当前目标/目标的目标）")
  end
end

PR["TSEL"] = function(msg)
  -- ★★★1.75.10 取证：选取目标「**目标的目标**」（用户：「分析接口.验证选取目标的目标.可行性?」）。
  --   官方文档核到的事实（逐条都有出处，见 CLAUDE.md §5.8）：
  --     · conventions#unit-ids：`targettarget` = **当前目标的目标**，是合法 UnitID（大小写不敏感）；
  --     · Targetting 页 `TargetUnit(unit)`：**「Does nothing if that UnitID does not resolve.」**
  --       ⇒ 解析不到（没目标 / 目标自己没有目标）时**什么都不做**（★这正是本插件选它而不是 AssistUnit 的理由：
  --       AssistUnit 对解析不到的 UnitID 会**清掉当前目标**）。
  --   ★探针纪律：**只读 + 至多一次真切换**；「没有目标的目标」时**一次都不切**（不留副作用）。
  --   ★读数专属落盘 `cfg.tselProbe`（`say` 只进聊天框、不落日志环 ⇒ 不自己存一份我这边读不到）。
  local function tsSay(s)
    local box = c().tselProbe
    if type(box) ~= "table" or type(box.out) ~= "table" then box = { out = {} }; c().tselProbe = box end
    box.out[table.getn(box.out) + 1] = s
    while table.getn(box.out) > 12 do table.remove(box.out, 1) end
    say(s)
  end
  if type(UnitName) ~= "function" or type(UnitExists) ~= "function" then
    tsSay("[选取目标] 读不了：本客户端没有 UnitName/UnitExists（无法取证）")
  else
    local okT, hasT = pcall(UnitExists, "target")
    local _, nmT = pcall(UnitName, "target")
    local okTT, hasTT = pcall(UnitExists, "targettarget")
    local _, nmTT = pcall(UnitName, "targettarget")
    tsSay(string.format("[选取目标] 当前目标=%s（存在=%s）｜ 目标的目标=%s（存在=%s）｜ TargetUnit=%s",
      tostring(nmT), tostring(okT and hasT), tostring(nmTT), tostring(okTT and hasTT),
      (type(TargetUnit) == "function") and "有" or "**缺失**"))
    if not (okT and hasT) then
      tsSay("[选取目标] 现在**没有目标** ⇒ 不试切换（先选中一只怪/一个队友，再敲一次）")
    elseif not (okTT and hasTT) then
      tsSay("[选取目标] 这个目标**自己没有目标** ⇒ 「选取目标:目标的目标」会是**空操作**（TargetUnit 解析不到就什么都不做；当前目标不会被清）")
    elseif type(TargetUnit) ~= "function" then
      tsSay("[选取目标] TargetUnit 不存在 ⇒ 这条选取在本客户端做不了")
    else
      local okc, err = pcall(TargetUnit, "targettarget")
      local _, nmA = pcall(UnitName, "target")
      tsSay(string.format("[选取目标] 已执行 TargetUnit(\"targettarget\")：调用=%s%s ⇒ 切换后当前目标=%s（期望=%s）",
        tostring(okc), okc and "" or (" 错=" .. tostring(err)), tostring(nmA), tostring(nmTT)))
    end
    tsSay("读数已落存档 cfg.tselProbe（上限 12 行）⇒ /reload 后即可读存档")
  end
end

PR["ICONIDX"] = function(msg)
  local IDX_OUT_MAX = 40
  local function idxSay(s)
    s = tostring(s)
    local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
    if type(cfgP) == "table" then
      local box = cfgP.iconIdxProbe
      if type(box) ~= "table" then box = { out = {} } cfgP.iconIdxProbe = box end
      if type(box.out) ~= "table" then box.out = {} end
      table.insert(box.out, s)
      while table.getn(box.out) > IDX_OUT_MAX do table.remove(box.out, 1) end
      box.t = (type(date) == "function") and date("%H:%M:%S") or nil
    end
    say(s)
  end
  idxSay("— 宏图标号 → 图标（本客户端 GetMacroIconInfo；号 = 图标库悬停里的「宏图标序号」）—")
  local total = 0
  if type(GetNumMacroIcons) == "function" then
    local okn, v = pcall(GetNumMacroIcons)
    if okn and type(v) == "number" then total = v end
  end
  idxSay(string.format("接口：GetMacroIconInfo=%s ｜ 表内共 %d 枚", tostring(type(GetMacroIconInfo) == "function"), total))
  -- 单个号一行：**三态如实**（拿到 / 取不到 / 接口不在），绝不把「取不到」写成「没有这枚图」
  local function idxLine(idx, label)
    local tex, why = nil, nil
    if type(GetMacroIconInfo) ~= "function" then why = "接口不存在"
    else
      local ok, v = pcall(GetMacroIconInfo, idx)
      if not ok then why = "调用抛错"
      elseif type(v) ~= "string" or v == "" then why = "取不到（号越界 / 表里没有）"
      else tex = v end
    end
    local short = nil
    if tex then
      local tail = string.match(tex, "([^/\\]+)$") or tex
      short = string.gsub(tail, "_TEX$", "")
    end
    idxSay(string.format("  %s%d → %s", label or "", idx,
      tex and (tex .. "（" .. tostring(short) .. "）") or ("**" .. tostring(why) .. "**")))
  end
  local nums = {}
  for n in string.gmatch(msg, "%d+") do table.insert(nums, tonumber(n)) end
  local CAP = 12
  if table.getn(nums) == 0 then
    local db = rawget(_G, "EVAL_PET_DB")
    local list = {}
    for _, sk in ipairs((db and db.skills) or {}) do
      if type(sk.iconIdx) == "number" then table.insert(list, sk) end
    end
    idxSay(string.format("（未给号 ⇒ 报宠物技能在用的 %d 个号：读 PetData 的 iconIdx，与界面渲染**同一个解析口**）", table.getn(list)))
    if type(EVAL_PH_SKILL_ICON) ~= "function" then
      idxSay("  ⚠ 抓宠帮手模块没载入（EVAL_PH_SKILL_ICON 不存在）⇒ 只能报号、报不出纹理")
    end
    for i = 1, table.getn(list) do
      local sk = list[i]
      local tex = nil
      if type(EVAL_PH_SKILL_ICON) == "function" then
        local ok, v = pcall(EVAL_PH_SKILL_ICON, sk)
        if ok and type(v) == "string" then tex = v end
      end
      idxSay(string.format("  %s %d → %s", tostring(sk.name), sk.iconIdx, tex or "**取不到（已退回语义图标路径）**"))
    end
  else
    local m = table.getn(nums)
    if m > CAP then idxSay(string.format("给了 %d 个号 ⇒ 只报前 %d 个（避免刷屏/撞反刷屏限流）", m, CAP)) m = CAP end
    for i = 1, m do idxLine(nums[i], "") end
  end
  -- 存档落盘提示（★本命令的读数**专属落盘**，但客户端只在 /reload、小退、退出时才写盘）
  idxSay(string.format("读数已落存档 cfg.iconIdxProbe（上限 %d 行）⇒ /reload 后即可读存档", IDX_OUT_MAX))
  -- ★总闸门（调试日志）关着 ⇒ 上面一个字都到不了聊天框 ⇒ 走常开出口如实告知怎么开回来（静默族防线）
  if type(EVAL_CHAT_ON) == "function" then
    local okOn, on = pcall(EVAL_CHAT_ON)
    if okOn and not on and type(EVAL_SAY_FORCE) == "function" then
      pcall(EVAL_SAY_FORCE, "（「调试日志」关着 ⇒ 上面这些行看不到；/eh log 可开回来）")
    end
  end
end

PR["ICONS"] = function(msg)
  -- ★★★1.73.3 图标路径采集（用户要求）：「通过日志信息获取系统图标所有图片路径,存储到一个图标路径文件内」。
  --   为什么只能这样做：客户端的内置图标打包在 Content\Paks，**磁盘上取不到**；唯一能把整表路径
  --   吐出来的官方入口就是**宏图标表**（GetNumMacroIcons/GetMacroIconInfo 给的是路径字符串）。
  --   采集结果写进 SavedVariables（EVAL_HELP_CONFIG.iconDump）→ /reload 后落盘 → 由外部读出来
  --   生成图标路径文件（doc/图标路径清单.txt），供挑选/替换插件里的占位图标。
  --   ★不打印整表（上千行会刷屏 + 撞反刷屏限流），只报数量与落盘提示（如实、不静默）。
  local n = 0
  if type(GetNumMacroIcons) == "function" then
    local okn, v = pcall(GetNumMacroIcons)
    if okn and type(v) == "number" then n = v end
  end
  local list, fail = {}, 0
  for i = 1, n do
    local oki, tex = pcall(GetMacroIconInfo, i)
    if oki and type(tex) == "string" and tex ~= "" then table.insert(list, tex) else fail = fail + 1 end
  end
  EVAL_HELP_CONFIG.iconDump = {
    t = (type(GetTime) == "function") and GetTime() or 0,
    n = n, got = table.getn(list), failed = fail, list = list,
  }
  say("— 图标路径采集 —")
  say(string.format("枚举 %d 枚 / 收到 %d 枚 / 取失败 %d 枚", n, table.getn(list), fail))
  if table.getn(list) == 0 then
    say("一枚都没取到：本客户端可能没有宏图标表（如实报告，不假装采集成功）")
  else
    say("已写入存档（EVAL_HELP_CONFIG.iconDump）→ 请 /reload 或小退让存档落盘，然后让 AI 读取该文件")
  end
end

PR["IMMUNE"] = function(msg)
  -- 免疫事件探针（1.35.1，免疫学习器前置验证）：30 秒全事件抓取——CHAT_MSG_* 或参数含「免疫/immune」
  -- 的写调试日志；对免疫怪放技能后翻日志拿真实事件名+文本格式，再写解析器（事件 wiki 无文档页）
  say("免疫探针启动：30 秒内对免疫怪放技能（如撕裂）→ /eh go probe dump 看结果")
  local pf = CreateFrame("Frame")
  local t0 = GetTime()
  -- 1.35.5：0 条说明全事件抓取可能没收到——加全事件计数（判定 RegisterAllEvents 是否有效）
  -- + 显式注册候选事件名对照（计数键带 [R] 前缀区分通道）
  cfg.probeLog = {}
  cfg.probeEvents = {}
  local CAND = { "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_FAILED_LOCALPLAYER", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_SPELL_SELF_BUFF" }
  pf:SetScript("OnEvent", function()
    local a1, a2 = arg1, arg2
    local ev = (type(event) == "string") and event or nil
    local name = ev or (type(a1) == "string" and a1) or ""
    if name ~= "" then
      local pe = cfg.probeEvents
      pe[name] = (pe[name] or 0) + 1
      local sk = name .. "_s"
      if not pe[sk] then pe[sk] = tostring(a1) .. " | " .. tostring(a2) end
    end
    local hit = (string.find(name, "^CHAT_MSG") ~= nil)
    if not hit then
      for _, v in ipairs({ a1, a2 }) do
        if type(v) == "string" and (string.find(v, "免疫") or string.find(v, "immune")) then hit = true break end
      end
    end
    if hit then
      table.insert(cfg.probeLog, "PROBE " .. tostring(name) .. " | a1=" .. tostring(a1) .. " | a2=" .. tostring(a2))
      while table.getn(cfg.probeLog) > 120 do table.remove(cfg.probeLog, 1) end
    end
  end)
  local okAll = pcall(pf.RegisterAllEvents, pf)
  for _, en in ipairs(CAND) do pcall(pf.RegisterEvent, pf, "[R]" .. en) end -- 显式注册走同一帧（事件名前缀[R]区分）
  say("RegisterAllEvents pcall=" .. tostring(okAll) .. "；显式候选 " .. table.getn(CAND) .. " 个")
  pf:SetScript("OnUpdate", function()
    if GetTime() - t0 > 30 then
      pcall(pf.UnregisterAllEvents, pf)
      pf:SetScript("OnUpdate", nil)
      pf:SetScript("OnEvent", nil)
      say("免疫探针结束（30s），已记录 " .. table.getn(cfg.probeLog or {}) .. " 条 → /eh go probe dump 查看")
    end
  end)
end

PR["USABLE"] = function(msg)
  -- 可用性探针（1.60.1）：dump 技能格子的原始可用性值——IsUsableAction 在本客户端走缓存态
  -- （wiki 原文 Uses a cached usable state），疑似「可用却被跳过」时先跑这个拿现场数据。
  -- 用法：/eh go probe usable 冲锋（或 不带参数 = 当前方案全部动作条技能）
  local nm = string.match(msg, "^go probe usable%s*(.-)%s*$")
  local function dumpOne(n)
    local s = wslots[n]
    if not s then say(n .. ": |cffff0000不在动作条（先 /eh go rescan）|r") return end
    local oku, u, noMana = pcall(IsUsableAction, s.slot)
    local okr, inRg = pcall(IsActionInRange, s.slot)
    local okc, cst, dur = pcall(GetActionCooldown, s.slot)
    local okh, has = pcall(HasAction, s.slot)
    say(string.format("%s 格子%d: usable=%s(%s) noMana=%s inRange=%s cd=%s/%s HasAction=%s",
      n, s.slot,
      tostring(oku and u), tostring(oku), tostring(noMana),
      tostring(okr and inRg), tostring(cst), tostring(dur), tostring(okh and has)))
  end
  say("— 可用性探针 —")
  if nm and nm ~= "" then
    dumpOne(nm)
  else
    local p = warCfg().profiles[warCfg().activeProfile or 1]
    local any = false
    if p then for _, r in ipairs(p.skills) do if wslots[r.skill] then dumpOne(r.skill) any = true end end end
    if not any then say("（当前方案无动作条技能；可带参数：/eh go probe usable 冲锋）") end
  end
end

PR["DUMP"] = function(msg)
  -- 打印探针持久记录（1.35.4：探针结果的持久查看通道；打完免疫技能后用这个看）
  local pl = cfg.probeLog or {}
  say("— 探针记录 " .. table.getn(pl) .. " 条 —")
  for i, line in ipairs(pl) do say(i .. ". " .. line) end
  -- 1.35.5 全事件计数总览（判断事件系统是否工作）：按次数降序打前 25 个 + 首样本
  local pe = cfg.probeEvents or {}
  local names = {}
  for n, c2 in pairs(pe) do if type(c2) == "number" then table.insert(names, n) end end
  table.sort(names, function(a, b) return pe[a] > pe[b] end)
  say("— 事件计数（共 " .. table.getn(names) .. " 种）—")
  for i = 1, math.min(25, table.getn(names)) do
    local n = names[i]
    say(n .. " × " .. pe[n] .. "  样本: " .. tostring(pe[n .. "_s"]))
  end
  if table.getn(pl) == 0 and table.getn(names) == 0 then say("（全空——先 /eh go probe immune 并在 30 秒内对免疫怪放技能；若反复全空说明事件系统不可用）") end
end

-- ★1.75.40 顶部信息条（tools/InfoBar.lua）：命令体**留在模块自己文件里**（`EVAL_IB_CMD`），
--   这里只做转发 —— 与「纯命令本体进模块、要读宿主内部件的就地留」同一条纪律（本探针只读模块自己的状态）。
PR["IB"] = function(msg)
  if type(EVAL_IB_CMD) ~= "function" then
    say("顶部信息条：模块未载入（tools/InfoBar.lua 不在 .toc 或载入失败）")
    return
  end
  EVAL_IB_CMD(msg)
end

-- ===== 物品价探针（/eh go 物品价）=====
-- 背景（用户要求：「在不依赖其他插件的情况下能否实现物品售价预览？然后把物品售价比对的功能完善」）：
--   本客户端**没有**「由物品 id 拿售价」的 API（`GetItemInfo` 停在 texture，已按官方 wiki 原文核过），
--   唯一能从客户端嘴里撬出卖价的口径是：**商人窗开着时** `GameTooltip:SetBagItem` 会触发
--   `OnTooltipAddMoney`（带整栈售价）。而参考实现（客户端自带的另一份插件，已移出插件目录，
--   见其 modules/itemprice.lua 的 USER_CONFIRMED_INGAME 记录）写明了**两条硬事实**：
--     ① **替换 GameTooltip 的方法在本客户端不成立**（10 个 item setter 全被换掉，悬停时一个都没跑）
--        ⇒ 物品只能**从被悬停的按钮**识别，不能从 tooltip 识别；
--     ② `GameTooltip:SetTooltipMoney` **调用不报错但不显示**。
--   ⇒ 动手写模块之前，必须先把 4 个未知点问清（本探针只做这件事，**不写任何价格数据**）：
--     ① `GameTooltip.SetBagItem` 的字段替换到底活不活（「替换 widget 方法」那条路会不会是死的）；
--     ② `OnTooltipAddMoney` 把金额放在**第几个参数**（那份实现说位置不定，要试 a1..a4 + arg1）；
--     ③ **自建** GameTooltip 帧会不会触发 `OnTooltipAddMoney`（官方 wiki 没写，当时是未知）；
--     ④ 格子按钮能不能由**客户端自己的约定**稳定解析出 bag/slot（「独立模块」方案的地基）。
--   ★纪律：即时回显「命令已收到」；除「测①写入存活」那一次赋值（**当场还原**）外**全程只读**；
--     读数一律进专属有界环 `cfg.ipProbe`（`say` 只进聊天框、不落日志环 ⇒ 只上屏 = AI 读存档时断链）；
--     监听是**有界窗口**（到点自停并还原脚本），绝不常驻。
-- ★★1.75.41b **两个环必须分开**（首轮真机教训）：报告是「一次性 10 来行」，监听是「每次悬停几十行」
--   ⇒ 共用一个 60 行环时，用户跑完 `监听` 会把 `状态/采样` 的报告**整段刷掉**（首轮真机就是这个结果：
--   存档里只剩钱行，测③④的报告一行不剩）。现在：`ipProbe` = 报告环（25 行，只由 状态/采样 写）、
--   `ipListen` = 监听环（60 行，只由 监听 写）。
local IPR_RING = 25          -- 报告环上限
local IPR_LRING = 60         -- 监听环上限
local IPR_LISTEN_SECS = 60   -- 监听窗口（有界）

local IPR = {
  on = false, t0 = 0, secs = IPR_LISTEN_SECS,
  hooked = false, origScript = nil,
  wrapped = false, setBagOrig = nil,
  bagHits = 0, moneyHits = 0, saidMiss = 0,
  f = nil,
}

local function iprPush(key, cap, line)
  local t = cfg[key]
  if type(t) ~= "table" then t = {} cfg[key] = t end
  table.insert(t, tostring(line))
  while table.getn(t) > cap do table.remove(t, 1) end
end

local function iprRing(line) iprPush("ipProbe", IPR_RING, line) end
local function iprLRing(line) iprPush("ipListen", IPR_LRING, line) end

local function iprSay(s) say(s) iprRing(s) end
local function iprLSay(s) say(s) iprLRing(s) end
-- 监听的收尾摘要两边都留（报告侧也要有「监听到底跑没跑」的证人）
local function iprSayBoth(s) say(s) iprRing(s) iprLRing(s) end

-- 金额可能在 a1..a4 的任意位置（同款口径：先试四个形参），最后才试全局 arg1。
-- ★绝不用 `tostring(f())` 接多返回值（本项目老雷：只留第一个）。
local function iprAmount(a1, a2, a3, a4)
  local cand = { a1, a2, a3, a4, rawget(_G, "arg1") }
  for i = 1, 5 do
    local v = tonumber(cand[i])
    if v and v > 0 then return v, i end
  end
  return nil
end

local function iprHas(name) return type(rawget(_G, name)) == "function" end
local function iprMark(name)
  if iprHas(name) then return name .. "=有" end
  return "|cffff6060" .. name .. "=无|r"
end

-- 商人窗开没开：帧显隐为准（GetMerchantNumItems 可能残留），两个都报出来
local function iprMerchant()
  local n = 0
  if iprHas("GetMerchantNumItems") then
    local ok, v = pcall(GetMerchantNumItems)
    if ok and type(v) == "number" then n = v end
  end
  local shown = false
  local mf = rawget(_G, "MerchantFrame")
  if mf and mf.IsShown then
    local ok, s = pcall(mf.IsShown, mf)
    if ok then shown = s and true or false end
  end
  return shown, n
end

-- 测①：字段替换活不活。
-- ★★1.75.41c 第 2 轮真机定案：本客户端 **widget 方法每次读都是一个新对象**（同机另一份插件的自检命令
--   同机那份实现的记录也写了这条）⇒ `读回 == 写入值` **恒为假、`还原成功` 也无法自证** ——
--   第 2 轮报的「还原=否」是**假警报**，不是真丢了东西。真判据只有一个：**行为**（我们的包装到底跑没跑）。
local function iprTest1()
  local GT = rawget(_G, "GameTooltip")
  if not GT or type(GT.SetBagItem) ~= "function" then
    return "GameTooltip 或其 SetBagItem 不在（「替换 widget 方法」那条路根本没法走）"
  end
  local orig = GT.SetBagItem
  local ran = 0
  GT.SetBagItem = function(self, bag, slot) ran = ran + 1 return orig(self, bag, slot) end
  local readBack = (GT.SetBagItem ~= orig) -- 本客户端恒为真 ⇒ 不可当判据
  -- 只读纪律：工具提示正显示时**不直调**（会把玩家正看的 tooltip 重画）
  local shown = false
  if GT.IsShown then local okS, s = pcall(GT.IsShown, GT) if okS then shown = s and true or false end end
  local callNote = "跳过直调（工具提示正显示）"
  if not shown then
    local okC = pcall(function() GT:SetBagItem(0, 1) end)
    callNote = "直调跑到包装=" .. (ran > 0 and "是" or "**否**") .. "（pcall=" .. tostring(okC) .. "）"
  end
  pcall(function() GT.SetBagItem = orig end)
  return string.format("读回≠原值=%s（★不可当判据）· %s", readBack and "是" or "否", callNote)
end

-- 测③：自建 GameTooltip 帧扫背包 —— 它到底会不会触发 OnTooltipAddMoney
local function iprScanFrame()
  local f = rawget(_G, "EVAL_IP_SCAN")
  if f then return f end
  if type(CreateFrame) ~= "function" then return nil end
  local ok, fr = pcall(CreateFrame, "GameTooltip", "EVAL_IP_SCAN", UIParent)
  if not ok or not fr then return nil end
  f = fr
  if f.SetOwner then pcall(f.SetOwner, f, UIParent, "ANCHOR_NONE") end
  return f
end

-- 扫背包的公共实现：对给定 tooltip 逐格 SetBagItem，数钱行命中 + 记前几格明细。
-- ★明细里同时报「该格数量」与「金额」⇒ **一次就能判定金额是「整栈总价」还是「单价」**
--   （这是价格库正确性的地基；首轮真机只拿到了悬停的钱行，判不出这一条）。
local function iprSweepWith(tip, detail, cap)
  local hits, money = 0, 0
  local pendBag, pendSlot, pendCount, pendName = nil, nil, 1, "?"
  local old = (tip.GetScript) and tip:GetScript("OnTooltipAddMoney") or nil
  pcall(tip.SetScript, tip, "OnTooltipAddMoney", function(a1, a2, a3, a4)
    local v = iprAmount(a1, a2, a3, a4)
    hits = hits + 1
    if v then
      money = money + 1
      if table.getn(detail) < cap then
        local per = ""
        if pendCount and pendCount > 1 then
          per = "，每件≈" .. tostring(math.floor(v / pendCount + 0.5))
        end
        detail[#detail + 1] = string.format("格 %s,%s ×%s = %s%s（%s）",
          tostring(pendBag), tostring(pendSlot), tostring(pendCount), tostring(v), per, tostring(pendName))
      end
    end
  end)
  local slots = 0
  for bag = 0, 4 do
    local n = tonumber(GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local tex, cnt = GetContainerItemInfo(bag, slot)
      if tex and tex ~= "" then
        slots = slots + 1
        pendBag, pendSlot, pendCount = bag, slot, tonumber(cnt) or 1
        pendName = "?"
        if iprHas("GetContainerItemLink") then
          local lnk = GetContainerItemLink(bag, slot)
          if type(lnk) == "string" then
            local nm = string.match(lnk, "%[(.-)%]")
            if nm then pendName = nm end
          end
        end
        pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
        pcall(tip.SetBagItem, tip, bag, slot)
      end
    end
  end
  pcall(tip.SetScript, tip, "OnTooltipAddMoney", old)
  return slots, hits, money
end

-- 测③a：**自建** GameTooltip 帧扫背包（零副作用优先：完全不动玩家那个 tooltip）
--   ★★第 2 轮补的判据：还要数**自建帧自己建起来了几行文本** —— 否则「触发 0 次」分不清是
--   「tooltip 根本没建起来」还是「建起来了但自建帧不触发钱行」（第 2 轮就是分不清，白跑一轮）。
local function iprTest3()
  if not iprHas("GetContainerNumSlots") or not iprHas("GetContainerItemInfo") then
    return nil, "GetContainerNumSlots / GetContainerItemInfo 不全，扫不了背包"
  end
  local f = iprScanFrame()
  if not f then return nil, "自建 GameTooltip 失败（CreateFrame 出错）" end
  local detail = {}
  local slots, hits, money = iprSweepWith(f, detail, 6)
  -- 自建帧的文本行数（具名 GameTooltip 的字串名 = 帧名..TextLeftN）
  local lines, first = 0, nil
  for i = 1, 12 do
    local fs = rawget(_G, "EVAL_IP_SCANTextLeft" .. i)
    if fs == nil then break end
    local okT, t = pcall(fs.GetText, fs)
    if okT and type(t) == "string" and t ~= "" then
      lines = lines + 1
      if first == nil then first = t end
    end
  end
  pcall(f.Hide, f)
  return slots, hits, money, first, detail, lines
end

-- 测③b：**借用玩家那个 GameTooltip** 扫背包（第二种扫法：共用玩家那个 tooltip）。
--   ★★第 2 轮它被「工具提示正显示」挡掉了（用户鼠标正悬停在物品上）⇒ 现在改成**先藏起来再扫**
--   （命令是你主动敲的，闪一下可接受）；扫完再藏一次，绝不把它留在屏幕上显示背包物品。
local function iprTest3b()
  local GT = rawget(_G, "GameTooltip")
  if not GT then return nil, "GameTooltip 不在" end
  local wasShown = false
  if GT.IsShown then
    local okS, s = pcall(GT.IsShown, GT)
    if okS and s then wasShown = true pcall(GT.Hide, GT) end
  end
  local detail = {}
  local slots, hits, money = iprSweepWith(GT, detail, 6)
  pcall(GT.Hide, GT)
  return slots, hits, money, detail, wasShown
end

-- ③a/③b 两条扫价路径的公共播报：把「哪一格、几件、多少钱、每件≈多少」逐格打进报告环
--   ⇒ 存档里就能直接判「金额是整栈总价还是单价」，不用再问一轮。
local function iprSaySweep(mOpen)
  local s1, h1, m1, first, d1, lines = iprTest3()
  iprSay(string.format("③a 自建 tooltip（EVAL_IP_SCAN）扫背包：扫到 %s 格 → 触发 %s 次 / 拿到金额 %s 次",
    tostring(s1), tostring(h1), tostring(m1)))
  iprSay(string.format("    自建帧文本行=%s（首行=%s）← 0 行 = tooltip 根本没建起来，不是「不触发钱行」",
    tostring(lines), tostring(first)))
  if type(d1) == "table" then
    for i = 1, table.getn(d1) do iprSay("     " .. tostring(d1[i])) end
  end
  local s2, h2, m2, d2, wasShown = iprTest3b()
  if s2 == nil then
    -- ★跳过时第二个返回值是**原因**（不是次数）
    iprSay("③b 借用 GameTooltip 扫背包：**跳过** —— " .. tostring(h2))
  else
    iprSay(string.format("③b 借用 GameTooltip 扫背包：扫到 %s 格 → 触发 %s 次 / 拿到金额 %s 次%s",
      tostring(s2), tostring(h2), tostring(m2),
      wasShown and "（扫描前工具提示正显示，已先藏起来）" or ""))
    if type(d2) == "table" then
      for i = 1, table.getn(d2) do iprSay("     " .. tostring(d2[i])) end
    end
  end
  if not mOpen then
    iprSay("  ★商人窗没开时 ③a/③b **必然都是 0**（官方 wiki：只在商人窗触发）⇒ 先开个商人再跑 `/eh go 物品价 采样`")
  end
end

-- 测④：格子按钮能不能由**客户端自己的约定**解析出 bag/slot（独立模块的地基）。
--   ★口径（本项目要求「不与其它插件做关联」）：**只用** `GetID()`（格子号）+ 父级 `GetID()`（容器号）——
--   这正是客户端原生 `ContainerFrameItemButton_OnEnter` 取法；**不读任何插件自己的私有字段**。
--   扫法：从 UIParent 有界下探（深度 ≤ 4、节点 ≤ 400），把「父级 GetID 与自身 GetID 都是数字、
--   且挂了 OnEnter 脚本」的帧算作「可解析格子的按钮」——不管它是哪家背包插件、还是客户端原生的。
local function iprTest4()
  local nodes, btns, okN, sample = 0, 0, 0, nil
  local seen = {}
  local function visit(fr, depth)
    if fr == nil or depth > 4 or nodes > 400 then return end
    if seen[fr] then return end
    seen[fr] = true
    nodes = nodes + 1
    local okT, ot = pcall(function() return fr.GetObjectType and fr:GetObjectType() end)
    if okT and (ot == "Frame" or ot == "Button") then
      local sid = (type(fr.GetID) == "function") and fr:GetID() or nil
      local par = (type(fr.GetParent) == "function") and fr:GetParent() or nil
      local bid = (par and type(par.GetID) == "function") and par:GetID() or nil
      local okS, scr = pcall(function() return fr.GetScript and fr:GetScript("OnEnter") end)
      if type(sid) == "number" and type(bid) == "number" and okS and type(scr) == "function" then
        btns = btns + 1
        okN = okN + 1
        if not sample then
          sample = string.format("name=%s GetID=%s 父GetID=%s", tostring(fr.GetName and fr:GetName()), tostring(sid), tostring(bid))
        end
      end
      -- ★多返回值不能 tostring：整个 pcall 结果收进表（[1] = 成功与否，其后是子件）
      local kids = { pcall(fr.GetChildren, fr) }
      if kids[1] then
        for i = 2, table.getn(kids) do visit(kids[i], depth + 1) end
      end
    end
  end
  visit(UIParent, 1)
  local stock = (type(ContainerFrameItemButton_OnEnter) == "function")
  local stockBtn = rawget(_G, "ContainerFrame1Item1")
  return nodes, btns, okN, sample, stock, stockBtn
end

-- 监听（测②：金额参数位置；测①的真判据：原生悬停会不会走我们的包装）
local function iprStop()
  if not IPR.on then return false end
  local GT = rawget(_G, "GameTooltip")
  if GT then
    if IPR.hooked then pcall(GT.SetScript, GT, "OnTooltipAddMoney", IPR.origScript) end
    if IPR.wrapped and IPR.setBagOrig ~= nil then GT.SetBagItem = IPR.setBagOrig end
  end
  if IPR.f then
    pcall(IPR.f.SetScript, IPR.f, "OnUpdate", nil)
    pcall(IPR.f.Hide, IPR.f)
  end
  IPR.on, IPR.hooked, IPR.wrapped = false, false, false
  IPR.origScript, IPR.setBagOrig = nil, nil
  return true
end

local function iprStart(secs)
  local GT = rawget(_G, "GameTooltip")
  if not GT then iprSay("监听：GameTooltip 不在，没法监听") return end
  iprStop()
  IPR.bagHits, IPR.moneyHits, IPR.saidMiss = 0, 0, 0
  IPR.secs = tonumber(secs) or IPR_LISTEN_SECS
  if IPR.secs < 5 then IPR.secs = 5 end
  if IPR.secs > 600 then IPR.secs = 600 end

  IPR.origScript = (GT.GetScript) and GT:GetScript("OnTooltipAddMoney") or nil
  IPR.hooked = true
  pcall(GT.SetScript, GT, "OnTooltipAddMoney", function(a1, a2, a3, a4)
    local v, pos = iprAmount(a1, a2, a3, a4)
    IPR.moneyHits = IPR.moneyHits + 1
    local txt = "?"
    local fs = rawget(_G, "GameTooltipTextLeft1")
    if fs and fs.GetText then
      local okT, t = pcall(fs.GetText, fs)
      if okT and type(t) == "string" and t ~= "" then txt = t end
    end
    local line = string.format("钱行#%d 位置=%s 金额=%s 首行=%s ｜ a1=%s a2=%s a3=%s a4=%s arg1=%s",
      IPR.moneyHits, tostring(pos), tostring(v), txt,
      tostring(a1), tostring(a2), tostring(a3), tostring(a4), tostring(rawget(_G, "arg1")))
    iprLRing(line) -- ★监听的钱行进**监听环**（报告环留给 状态/采样，别互相刷掉）
    if v then
      say("  [钱行] " .. line)
    elseif IPR.saidMiss < 3 then
      IPR.saidMiss = IPR.saidMiss + 1
      say("  （这一拍四个参数都不像金额）" .. line)
    end
  end)

  -- 包装 SetBagItem：原生悬停若也走它 ⇒ 计数会涨（=「替换活着」的真判据）
  if type(GT.SetBagItem) == "function" then
    IPR.setBagOrig = GT.SetBagItem
    GT.SetBagItem = function(self, bag, slot)
      IPR.bagHits = IPR.bagHits + 1
      return IPR.setBagOrig(self, bag, slot)
    end
    IPR.wrapped = true
  end

  -- 驱动帧（首用才建、匿名）＋ 有界窗口：到点自停并还原
  if not IPR.f then
    if type(CreateFrame) ~= "function" then iprSay("监听：CreateFrame 不在，无法计时自停") return end
    local okF, fr = pcall(CreateFrame, "Frame")
    if not okF or not fr then iprSay("监听：建驱动帧失败") return end
    IPR.f = fr
  end
  IPR.t0 = (type(GetTime) == "function") and GetTime() or 0
  IPR.on = true
  pcall(IPR.f.SetScript, IPR.f, "OnUpdate", function()
    -- ★零形参：dt 从全局 arg1 取（本客户端 OnUpdate 回调一个参数都不传）
    if not IPR.on then return end
    local now = (type(GetTime) == "function") and GetTime() or (IPR.t0 + (tonumber(arg1) or 0))
    if (now - IPR.t0) >= IPR.secs then
      local b, mm = IPR.bagHits, IPR.moneyHits
      local secs2 = IPR.secs
      iprStop()
      iprSayBoth(string.format("监听结束（%d 秒）：SetBagItem 被调用 %d 次（>0 = 字段替换**真的活着**）· OnTooltipAddMoney 触发 %d 次",
        secs2, b, mm))
    end
  end)
  iprSayBoth(string.format("监听已开（%d 秒，到点自停并还原脚本）：现在去**开一个商人窗口**，把鼠标划过背包里几件**可卖**物品", IPR.secs))
end

PR["ITEMPRICE"] = function(msg)
  local m = tostring(msg or "")
  -- ★即时回显**只上屏、不进环**：它要回答的是「命令到底跑到没有」，而进环会让「环空」那条分支
  --   变成**永远走不到的死代码**（本探针的 harness 真跑抓到：`环` 先回显再读环 ⇒ 永远非空）。
  say("物品价探针：命令已收到（tools/Probes.lua 的 PR[\"ITEMPRICE\"]）")

  if string.find(m, "监听", 1, true) or string.find(m, "listen", 1, true) then
    local secs = tonumber(string.match(m, "%d+"))
    iprStart(secs)
    return
  end

  if string.find(m, "停", 1, true) or string.find(m, "stop", 1, true) then
    local b, mm = IPR.bagHits, IPR.moneyHits
    if iprStop() then
      iprSayBoth(string.format("监听已停并还原：SetBagItem 共 %d 次 · OnTooltipAddMoney 共 %d 次", b, mm))
    else
      iprSay("监听本来就没开（零动作）")
    end
    return
  end

  -- ★1.75.43 A1 落地后：**生产命令优先**交给模块（tools/ItemPrice.lua 的 EVAL_IP_CMD）——
  --   学价/扫 · 值/估值 · 清价/忘掉 · 空参数（=状态）；只有带「探针」二字才跑下面那四段取证。
  --   ★顺序即判据：这一段必须排在「环 / 清」之前，否则 `清价` 会被 `清`（清环）那条先吃掉。
  if not string.find(m, "探针", 1, true) then
    local prod = (m == "")
      or string.find(m, "学价", 1, true) or string.find(m, "扫", 1, true)
      or string.find(m, "值", 1, true) or string.find(m, "清价", 1, true) or string.find(m, "忘掉", 1, true)
    if prod then
      if type(EVAL_IP_CMD) == "function" then
        EVAL_IP_CMD(m)
        return
      end
      -- ★模块缺席（.toc 漏了 / 载入失败）⇒ 如实说一句，绝不静默（下面仍会跑探针取证）
      say("物品价模块未载入（tools/ItemPrice.lua 不在 .toc 或载入失败）—— 本次只跑探针取证")
    end
  end

  if string.find(m, "环", 1, true) or string.find(m, "log", 1, true) then
    local t = cfg.ipProbe
    local lt = cfg.ipListen
    local n = (type(t) == "table") and table.getn(t) or 0
    local ln = (type(lt) == "table") and table.getn(lt) or 0
    if n == 0 and ln == 0 then
      say("物品价探针：两个环都是空的")
      return
    end
    say("— 物品价探针 · 报告环（" .. n .. " 行，上限 " .. IPR_RING .. "）—")
    for i = 1, n do say(i .. ". " .. tostring(t[i])) end
    say("— 物品价探针 · 监听环（" .. ln .. " 行，上限 " .. IPR_LRING .. "）—")
    for i = 1, ln do say(i .. ". " .. tostring(lt[i])) end
    return
  end

  if string.find(m, "清", 1, true) or string.find(m, "clear", 1, true) then
    cfg.ipProbe = {}
    cfg.ipListen = {}
    say("物品价探针：两个环都已清空")
    return
  end

  -- 「采样」= 只跑测③a/③b（开完商人窗后重跑这一项）
  if string.find(m, "采样", 1, true) or string.find(m, "scan", 1, true) then
    local mOpen, merchN = iprMerchant()
    iprSay(string.format("— 物品价探针 · 采样（商人窗：%s，GetMerchantNumItems=%s）—",
      mOpen and "开" or "|cffff6060关|r", tostring(merchN)))
    iprSaySweep(mOpen)
    return
  end

  -- 默认 = 探针取证（四个未知点**已在 1.75.41~43 三轮真机问清**，这一段留作回归/复现用）
  local mOpen, merchN = iprMerchant()
  iprSay("— 物品价探针（回归取证；日常请用 `/eh go 物品价` 看状态、`学价`、`值`）—")
  iprSay("① 基础 API：" .. iprMark("GetItemInfo") .. " " .. iprMark("GetContainerItemLink") .. " "
    .. iprMark("GetContainerItemInfo") .. " " .. iprMark("GetItemQualityColor") .. " " .. iprMark("IsShiftKeyDown"))
  iprSay("   价格旁路：" .. iprMark("GetMerchantItemInfo") .. " " .. iprMark("GetMerchantItemLink") .. " "
    .. iprMark("GetMerchantNumItems") .. " " .. iprMark("GetBuybackItemInfo") .. " "
    .. iprMark("GetAuctionSellItemInfo") .. " " .. iprMark("CalculateAuctionDeposit"))
  iprSay("② 方法替换（GameTooltip.SetBagItem）：" .. iprTest1())
  iprSay("   ★这一项只证明「赋值没被拒绝」；**替换活不活**的真判据是 `监听` 里原生悬停的计数")
  iprSay(string.format("③ 商人窗：%s（GetMerchantNumItems=%s）", mOpen and "开" or "|cffff6060关|r", tostring(merchN)))
  iprSaySweep(mOpen)
  local nodes, btns, okN, sample, stock, stockBtn = iprTest4()
  iprSay(string.format("④ 从 UIParent 有界下探 %d 个节点 → 可解析出 bag/slot 的格子按钮 %d 个"
    .. "（口径 = 客户端约定：GetID + 父级 GetID，且挂了 OnEnter）", nodes, okN))

  iprSay("   样本：" .. tostring(sample))
  iprSay(string.format("   stock：ContainerFrameItemButton_OnEnter=%s · ContainerFrame1Item1=%s",
    stock and "有" or "|cffff6060无|r", stockBtn and "有" or "|cffff6060无|r"))
  iprSay("⑤ 日常命令：`/eh go 物品价`（状态）· `学价`（开商人窗后扫）· `值`（背包/银行估值）· `清价`")
  iprSay("   （报告进 cfg.ipProbe、监听进 cfg.ipListen，互不刷掉 ⇒ /reload 后落盘，AI 可直接读存档）")
end

-- ★★★1.75.93 装备 tooltip 取证（用户真机报障：「装备:黑色甲壳盾跳过: 判不出使用效果」⇒ 审计 tooltip 信息来源）。
--   一条命令摊开全链路：WTT 通道状态 → 定位（身上槽位 ∨ 背包格）→ SetInventoryItem/SetBagItem pcall 结果 →
--   NumLines → 逐行原文 → 使用效果判定（现场值 + 缓存值）→ 冷却三参。
--   ★原话进有界落盘环 `cfg.equipProbe`（40 行，最新在后）⇒ /reload 后 AI 可直接读存档，不让玩家转述。
--   命令：`/eh go 装备探针 [名字]`（不带名字 = 列出当前已装备清单）。
PR["EQUIPTIP"] = function(msg)
  local ring = {}
  local function out(s)
    s = tostring(s)
    if type(EVAL_SAY_FORCE) == "function" then pcall(EVAL_SAY_FORCE, s) else say(s) end -- ★命令回显 = 强制可见
    local cf = conf()
    if cf then
      if type(cf.equipProbe) ~= "table" then cf.equipProbe = {} end
      table.insert(cf.equipProbe, s)
      while table.getn(cf.equipProbe) > 40 do table.remove(cf.equipProbe, 1) end
    end
  end
  local nm = string.match(msg, "^go 装备探针%s+(.+)$") or string.match(msg, "^go etip%s+(.+)$") or ""
  out("— 装备 tooltip 取证 " .. date("%H:%M:%S") .. " —")
  -- ① 通道状态
  if type(EVAL_WTT_STATE) == "function" then
    local wst = EVAL_WTT_STATE()
    out("① tooltip 通道: " .. tostring(wst and wst.why) .. " ｜ 此刻可读="
      .. tostring(type(EVAL_WTT_MAY_READ) == "function" and EVAL_WTT_MAY_READ()))
  else
    out("① EVAL_WTT_STATE 不存在（Engine 未载入完整）")
  end
  local WTT = (type(EVAL_WTT_HANDLE) == "function") and EVAL_WTT_HANDLE() or nil
  out("   WTT=" .. (WTT and "有" or "|cffff6060无|r")
    .. " ｜ SetInventoryItem=" .. tostring(WTT and WTT.SetInventoryItem ~= nil)
    .. " ｜ SetBagItem=" .. tostring(WTT and WTT.SetBagItem ~= nil)
    .. " ｜ NumLines=" .. tostring(WTT and WTT.NumLines ~= nil))
  -- ② 不带名字 = 列已装备清单
  if nm == "" then
    out("② 当前已装备（纸娃娃槽位 1-19）：")
    local any = false
    if type(GetInventoryItemLink) == "function" then
      for slot = 1, 19 do
        local okl, link = pcall(GetInventoryItemLink, "player", slot)
        local n2 = okl and link and string.match(link, "%[(.-)%]")
        if n2 then any = true out("   槽" .. slot .. ": " .. n2) end
      end
    end
    if not any then out("   （一个都没读到）") end
    out("用法: /eh go 装备探针 <名字> —— 摊开那件装备的 tooltip 原文")
    return
  end
  -- ③ 定位：先身上，再背包（与 condOne 的 eUse 同一顺序）
  local eslot = (type(EVAL_FIND_EQUIPPED) == "function") and EVAL_FIND_EQUIPPED(nm) or nil
  local ebag, eslotB = nil, nil
  if not eslot and type(EVAL_IG_SCAN_BAGS) == "function" then
    local list = EVAL_IG_SCAN_BAGS({ 0, 1, 2, 3, 4 })
    for _, it2 in ipairs(list or {}) do
      if it2.name == nm then ebag, eslotB = it2.bag, it2.slot break end
    end
  end
  if not eslot and not ebag then
    out("③ 定位：|cffff6060身上和背包都没找到「" .. nm .. "」|r（名字须与链接里的真名逐字一致，全角/半角冒号已归一）")
    return
  end
  out("③ 定位: " .. (eslot and ("身上槽位 " .. eslot) or ("背包 [" .. ebag .. "," .. eslotB .. "]")))
  -- ④ 填 tooltip + pcall 结果
  if not WTT then out("④ WTT 不存在 ⇒ 整条 tooltip 路不可用") return end
  local okS, err
  if eslot then
    if not WTT.SetInventoryItem then out("④ WTT 没有 SetInventoryItem ⇒ 判不出") return end
    okS, err = pcall(WTT.SetInventoryItem, WTT, "player", eslot)
    out("④ SetInventoryItem(player," .. eslot .. ") pcall=" .. tostring(okS) .. (okS and "" or (" ｜ " .. tostring(err))))
  else
    if not WTT.SetBagItem then out("④ WTT 没有 SetBagItem ⇒ 判不出") return end
    okS, err = pcall(WTT.SetBagItem, WTT, ebag, eslotB)
    out("④ SetBagItem(" .. ebag .. "," .. eslotB .. ") pcall=" .. tostring(okS) .. (okS and "" or (" ｜ " .. tostring(err))))
  end
  -- ⑤ 逐行原文（NumLines 之内；之外是旧文本，不读）
  local wname = "GameTooltip"
  if type(EVAL_WTT_IS_SELF) == "function" and EVAL_WTT_IS_SELF() then
    local okn, n0 = pcall(function() return WTT:GetName() end)
    if okn and type(n0) == "string" and n0 ~= "" then wname = n0 end
  end
  local okN, nl = pcall(WTT.NumLines, WTT)
  nl = (okN and tonumber(nl)) or 0
  out("⑤ NumLines=" .. tostring(nl) .. "（行对象前缀 " .. wname .. "）")
  local maxR = nl
  if maxR > 20 then maxR = 20 end
  for row = 1, maxR do
    local fs = rawget(_G, wname .. "TextLeft" .. row)
    local t = (fs and fs.GetText) and (function() local ok2, x = pcall(function() return fs:GetText() end) return ok2 and x or "?" end)() or "|cffff6060<行对象不存在>|r"
    out("   " .. row .. ". " .. tostring(t))
  end
  if nl > 20 then out("   …（只列前 20 行）") end
  -- ⑥ 判定与冷却（★分两步写：eslot and A or B 在 A 返回 **false** 时会改走 B（参数 nil ⇒ nil），
  --   首轮取证就是这么把「false=没有」打成「nil=判不出」的——and/or 陷阱，与 condOne 同案）
  local hu = nil
  if eslot then
    if type(EVAL_EQUIP_HAS_USE) == "function" then hu = EVAL_EQUIP_HAS_USE(nm, eslot) end
  else
    if type(EVAL_BAG_HAS_USE) == "function" then hu = EVAL_BAG_HAS_USE(nm, ebag, eslotB) end
  end
  out("⑥ 使用效果判定: " .. tostring(hu) .. "（true=有 / false=没有 / nil=判不出；这步会写缓存）")
  local cf2 = conf()
  local cached = cf2 and rawget(_G, "EVAL_HELP_STATE") and rawget(_G, "EVAL_HELP_STATE").equipUseMap
  out("   缓存值: " .. tostring(cached and cached[nm] or "(无)"))
  if eslot and type(GetInventoryItemCooldown) == "function" then
    local okc, a, b, c2 = pcall(GetInventoryItemCooldown, "player", eslot)
    out("   冷却(GetInventoryItemCooldown): pcall=" .. tostring(okc) .. " ｜ start=" .. tostring(a) .. " dur=" .. tostring(b) .. " enable=" .. tostring(c2))
  elseif ebag and type(GetContainerItemCooldown) == "function" then
    local okc, a, b, c2 = pcall(GetContainerItemCooldown, ebag, eslotB)
    out("   冷却(GetContainerItemCooldown): pcall=" .. tostring(okc) .. " ｜ start=" .. tostring(a) .. " dur=" .. tostring(b) .. " enable=" .. tostring(c2))
  end
  out("（已记入存档环 equipProbe，/reload 后 AI 可直接读）")
end

-- 载入期到此结束：没有 CreateFrame / RegisterEvent / 存档读写 / 计时器。
