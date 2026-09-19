-- EvalHelp · Share.lua —— 方案分享（1.71.0 独立载入：聊天频道分片传输 + 事件扫描接收 + 弹窗导入）
-- 可行性结论（调研定案）：
--   发送：SendChatMessage 是 Protected → RunScript 聊天脚本队列绕行（1.49.3 已验证范式，视同玩家手输 /script）
--   传输：hex 编码防聊天系统吃掉 |、"、链接符；220 hex 字符/片（原始 110B），头部 ~20B，总 < 255B 消息上限
--   接收：CHAT_MSG_* 事件扫描（免疫学习器 1.36.0 同款通道），按 发送者+id 缓存分片，收齐弹窗
--   点击：弹窗是自家按钮（规避 SetItemRef 是否存在的未知数）——用户点 [导入] 才导入
-- 依赖仅全局件：EVAL_SAY / EVAL_DD_OPEN / EVAL_IMPORT_TEXT（EvalHelp 桥）/ EVAL_PROFILE_TO_TEXT

local SH = { buf = {}, done = {}, doneList = {} }  -- doneList=去重表的插入序（1.71.3 R6 上限淘汰用）
local SH_CHUNK = 220 -- 每片 hex 字符数
local SH_MSG_MAX = 250 -- ★单条预算（实测：250 通过、270 整条丢）

-- ===== 基础工具（文件独立：不依赖 Toolbox/EvalHelp 的 local 件） =====
local function shSay(t)
  if type(EVAL_SAY) == "function" then EVAL_SAY(t)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(t)) end
end

-- ★★★1.73.42j **修真事故**：语言来源必须是**读取器** EVAL_GET_LANG()。
--   老写法 `(type(EVAL_RESOLVE_LANG) == "function") and EVAL_RESOLVE_LANG() or "zhCN"` **恒等于 "zhCN"**：
--   Core.lua 的 ehResolveLang() 是**写入器**（每个分支裸 return、末尾 EH_LANG = "zhCN"）→ 返回 nil，
--   被 `or "zhCN"` 兜底（Lua 的 and/or 链没有布尔语义）→ 整个分享模块（接收弹窗/按钮/提示/封皮行）
--   在英/俄客户端里**一律显示中文**，而且全程不报错。DataSearch 与 Toolbox 在 1.70.46 已改，**Share 漏了**；
--   本轮把 50 条评语/境界/品阶迁进 Locales 时，新判据（切语言读值口必须变）当场把它逼了出来。
local function L(k)
  local lang = (type(EVAL_GET_LANG) == "function") and EVAL_GET_LANG() or "zhCN"
  local pack = EVAL_LOCALES and EVAL_LOCALES[lang]
  local v = pack and pack[k]
  if v == nil and EVAL_LOCALES and EVAL_LOCALES.zhCN then v = EVAL_LOCALES.zhCN[k] end
  return v or k
end

local function shSolid(tex, r, g, b, a)
  pcall(tex.SetTexture, tex, "Interface\\Buttons\\WHITE8X8")
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function shText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = false
  for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
    if pcall(fs.SetFontObject, fs, fo) then ok = true break end
  end
  if not ok then
    for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
      local okF, ok2 = pcall(fs.SetFont, fs, fp, size, "")
      if okF and ok2 then ok = true break end
    end
  end
  pcall(fs.SetTextColor, fs, r, g, b)
  return fs
end

-- ===== 配置（接收开关，默认开） =====
local function shCfg()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return { recv = true } end -- 未加载完成时按默认
  if type(c.share) ~= "table" then c.share = { recv = true } end
  if c.share.recv == nil then c.share.recv = true end
  return c.share
end

function EVAL_SHARE_RECV_ON()
  return shCfg().recv and true or false
end

function EVAL_SHARE_RECV_TOGGLE()
  local c = shCfg()
  c.recv = not c.recv
  shSay(L("SH_RECV_" .. (c.recv and "ON" or "OFF")))
  return c.recv
end

-- ===== hex 编解码（hex 切片不会劈开多字节汉字） =====
local function toHex(s)
  return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function fromHex(h)
  if type(h) ~= "string" or string.len(h) == 0 or math.mod(string.len(h), 2) ~= 0 then return nil end
  if string.find(h, "[^0-9a-fA-F]") then return nil end
  return (string.gsub(h, "..", function(cc) return string.char(tonumber(cc, 16)) end))
end

-- ===== 发送侧 =====
-- 频道有效性预检（不在该频道时 SendChatMessage 静默失败，提前提示）
-- ★1.71.3 用户实测决定：**团队（RAID）频道从分享里下线**——
--   原话「插件分享. 好像团队模式无法检测到.」→「不要团队模式发送了.」
--   ★为什么是删掉而不是去修：1.12 系客户端里**队长**发的队伍/团队聊天走 CHAT_MSG_*_LEADER 独立事件
--     （我们只注册了 CHAT_MSG_PARTY / CHAT_MSG_RAID），队长一分享，接收端就永远收不到——
--     而且失败是**静默**的：发送方还会照样提示「已发送 N 片」。与其留一个「看着能选、实际没人收到」的
--     频道，不如去掉。发送侧只保留 公会 / 队伍 / 说（接收侧事件注册保持原样：老版本往团队发的照样收）。
local SH_CHANS = {
  { id = "GUILD", name = function() return L("SH_CH_GUILD") end, ok = function() return type(IsInGuild) == "function" and IsInGuild() end },
  { id = "PARTY", name = function() return L("SH_CH_PARTY") end, ok = function() return type(GetNumPartyMembers) == "function" and (GetNumPartyMembers() or 0) > 0 end },
  { id = "SAY",   name = function() return L("SH_CH_SAY") end,   ok = function() return true end },
}


-- 1.71.3 频道白名单（单一真值）：下面这张表就是**唯一**来源 → 直接调 EVAL_SHARE_SEND(公会以外的旧频道) 也会被拒，
-- 不允许「界面上没有、代码里还能发」。
local function shChanOf(id)
  for _, c in ipairs(SH_CHANS) do if c.id == id then return c end end
  return nil
end
-- ★★★1.72.3 发送限频队列（修「长方案对方偶尔收不到」）
--   【用户实测】方案长到 4 片时对方有时收不到；短方案（1 片）从不出问题。
--   【根因】原实现把分片在**一个 for 循环里连着 RunScript** 发出去（同一帧 4 条 SendChatMessage）
--     → 撞客户端/服务器的反刷屏限流，被吞掉的那一片让接收端**永远收不齐**。
--   ★这正是本项目记忆体里写明的铁律：「RunScript 本身也是队列，**连发聊天同样会被反滥用踢线**，
--     通知类输出也要入限频队列」——分享发送当时没遵守。
--   【修法】第 1 片立即发（手感不变），其余进 FIFO，由 OnUpdate 每 SH_SEND_RATE 秒滴一片；
--     队列上限 SH_MAX_QUEUE 防失控（超出如实取消）。
-- ★★★1.73.43k 相邻两片**最小间隔**：0.5 → **1.0 秒**（每秒 1 条）。
--   【真机证据】用户两次变异测结果**互相矛盾**（同一形态一次出现、一次消失）⇒ 不是纯内容问题；
--   而「能正常显示」的那次分享只有 **4 条**消息（3 片 + 1 条分享信息），出问题那次是 **7 条** ⇒
--   最可能是**客户端/服务器对「短时间多条聊天」的限流**（本项目 §2 频率防护总则早就写过这个风险）。
--   ⇒ 间隔加倍，牺牲一点速度换「每一条都真的到得了」。
local SH_SEND_RATE = 1.0
local SH_MAX_QUEUE = 200  -- 发送队列上限（条）
local shTxQ, shTxLast = {}, 0
local shTxFrame

-- ★★★1.73.43c **取证打印必须先转义 `|`（写成 `||`）**：否则客户端把 `|HEHPF:…|h` 当链接吃掉、`|cff…` 当颜色吃掉，
--   打出来的「脚本原文」根本不是原文 —— 本轮第一份取证就是这么被瞒过去的（看到的脚本里 `|` 全没了）。
--   ★声明放在这里（上方探针要用它；DECL ORDER 检查守这条）。
local function shRawForPrint(t)
  return string.gsub(tostring(t or ""), "|", "||")
end
-- ★前置声明（本项目铁律：引用点在声明之前会解析成全局 nil）——
--   实现在 shNowT 之后，那里才拿得到计时函数。
local shTxEnqueue, shTxStep
local shSealRowApply -- ★1.73.42i 品阶栏刷新（前向声明：它在弹窗段才实现，但封皮晚到时也要能刷）
-- ★★★1.73.44 分片/信息行的**传输色**（单一来源）：色码是这个客户端最容易「整条吞掉消息」的成分
--   （非 8 位吞整条 · 一条多段吞整条 · 有色码但不带链接不画），而色表是会被改的
--   ⇒ 提成具名常量：① 分片体与封皮兜底色都从它取；② `/eh go 色码测` 也**从它取**（改色自动进测试，不写死就不会漏测）。
local SH_CHUNK_COLOR = "|cff9ad4ff"
-- ★1.73.35 分片构造**单一来源**（频道分享与「密语给某玩家」共用，避免两份实现漂移）
-- ★★★1.73.42h 方案名（分片标签与封皮行共用）：必须声明在 shBodies 之前
local function shSealName(text)
  local first = string.match(tostring(text or ""), "^([^\n]*)") or ""
  local nm = first
  local c1 = string.find(first, "：", 1, true)
  if c1 then nm = string.sub(first, c1 + 3) end
  local c2 = string.find(first, ":", 1, true)
  if c2 and (not c1 or c2 > c1) then nm = string.sub(first, c2 + 1) end
  nm = string.gsub(nm, "%|", "")
  nm = string.gsub(nm, "%[", "")
  nm = string.gsub(nm, "%]", "")
  nm = string.gsub(nm, "^%s+", "")
  nm = string.gsub(nm, "%s+$", "")
  if nm == "" then nm = "方案" end
  return string.sub(nm, 1, 18)
end
local function shBuildFor(text)
  local hex = toHex(text)
  -- ★1.73.42h 传输 id 用 **16 位**随机（原 8 位）：同一发送者连着分享两笔时，id 撞车会把两笔分片
  --   并在同一个接收缓冲里（真机上表现为串包；测试里表现为队列计数偶发多一片——8 位时约 4% 概率会撞）。
  local idh = string.format("%04x", math.random(0, 65535)) -- 本次传输 id（接收端按 发送者+id 归并分片）
  -- ★★★1.73.42h v2 分片体：载荷藏进自定义链接的 |H 段，聊天里**只显示**传输标签。
  -- ★★★1.73.47 用户：「方案:xxx 传输中 调整 -> 秘籍传输中...」⇒ 标签**不再带方案名**，只报「秘籍传输中...N%」
  --   （方案名在最后那条 `★[品阶秘籍·名]` 里出现一次就够；分片行短一点、也少占聊天宽度）。
  --   ★文案走 Locales（三语言同步），不在这里硬编码中文。
  -- ★1.73.43f label 可选：最后一片要把**分享信息**当标签（用户：「用能用的那几个」）
  local function chunkBody(idx, tot, part, label)
    local pct = math.ceil(idx * 100 / tot)
    if not label then label = string.format(L("SH_CHUNK_LABEL"), pct) end
    return SH_CHUNK_COLOR .. "|HEHPF:" .. idh .. " " .. idx .. "/" .. tot .. ":" .. part .. "|h[" .. label .. "]|h|r"
  end
  -- ★预算：单条 <= 250 字节（实测 250 通过、270 整条丢）→ 先量包装，剩下的都给 hex
  -- ★★★1.73.42h 量的必须是**最坏形状**，不能拿 idx=1/tot=1 当样本：样本的 "1/1" 与 "100%" 是最短的，
  --   长方案的 "18/18" + "56%" 会多出 1~2 字节 → 实测长方案有 10 片变成 251~252 字节（**超预算 = 真机上整条丢**）。
  --   （这条是「长方案片长判据」逼出来的真缺陷：短方案样本永远量不出这个偏差。）
  local wrapLen = string.len(chunkBody(99999, 99999, ""))
  local chunk = SH_MSG_MAX - wrapLen
  if chunk > SH_CHUNK then chunk = SH_CHUNK end
  if chunk < 40 then chunk = 40 end
  -- ★★★1.73.43f 用户：「如果特殊标识不可用就使用能用的前面能用你的那几个就可以. 不能用就删除」⇒
  --   **放弃「单独一条封皮消息」**（真机四轮已证明：那条我们确实发了，客户端就是不画），
  --   改成把分享信息**当最后一片的显示标签**：那一条与其余分片**逐字节同款结构**
  --   （同色前缀 + 同 `|HEHPF:` 链接 + 同 `[…]|h|r`），只是标签文字换成 `[档位]名 分享了 → [品阶秘籍·名] 评语`。
  --   ★这样用的是**已被证明能画**的同一条通道，而且**不再多发任何消息**。
  --   ★客户端那边照旧按链路载荷(id + i/n + hex)解析，标签只是显示 ⇒ 接收完全不受影响。
  local sealLine = nil
  if type(EVAL_SHARE_SEAL_INFO) == "function" then
    local okf, sinfo = pcall(EVAL_SHARE_SEAL_INFO, text)
    if okf and type(sinfo) == "table" and type(sinfo.line) == "string" and sinfo.line ~= "" then sealLine = sinfo.line end
  end
  local n = math.ceil(string.len(hex) / chunk)
  local bodies = {}
  for k = 1, n do
    bodies[k] = chunkBody(k, n, string.sub(hex, (k - 1) * chunk + 1, k * chunk))
  end
  --     发送队列里**再也不会有第二个来源**（这正是「特殊标识那条路走不通就别留着」的落地）。
  -- ★★★1.73.43i 用户真机回报：「A 身份行**没出现**」⇒ 按他自己定的规矩「**不能用就删除**」：
  --   **删掉 A 行**，把身份并进 B 行的**链接之后**（纯文本、不加色码、不加方括号）：
  --     B = `|c<品阶色>|HEHPF:<id> 0/1:0|h[<符号><品阶>秘籍·<方案名>]|h|r  <头衔>  <评语>`
  --   ★这个形态正是变异测里 **[4]「纯文本 + 一段色码 + 链接 + 标签 + 评语」** —— 那一测**当场画出来了** ✓
  --     （身份放在 `|h|r` **之后**＝「链接后的纯文本」这个位置，[4] 已验证没问题；不再用第二条消息。）
  --   ★序号仍写 0/1：接收端按「i < 1 越界」忽略，对收方案零影响；带 seal 标记（不算分片）。
  --   ★一条消息里**只有一段色码**（判据 + 源码检查 `SHARE MSG SHAPE CHECK` 都盯着这条）。
  -- ★★★1.73.43o 用户真机回报：「还是没显示玩家的**品级**」——身份是显示了（纯文本「阿凡提」✓），但**没有颜色** ⇒
  --   按用户自己定的原则「**多色码一行走不通就单色码一行一行发**」：把身份恢复成**独立一条**（只带它自己的那一段色码）：
  --     A 身份行 = `|c<身份色><头衔>|r <名字> 分享了`  ← 色码打头、**一段色码**、无链接、无方括号
  --   ★为什么现在敢恢复：v4 已证明「色码打头 + 一段色码」的形态没问题；而当初 A 行不显示是夹在**限流窗口**里的
  --     （v3 那轮整体被限流，v4 同形态就正常了）⇒ 现在间隔 1 秒、身份行排在分片之后、信息行之前。
  -- ★★★1.73.43p 真机再分析（用户第三次截图，1 秒间隔、同一次分享的干净对照）：
  --   · **B 行（一段色码 + `|HEHPF:` 链接 + `[标签]|h|r` + 尾巴）显示正常** ✓
  --   · **A 行（一段色码 + 纯文本，**没有链接**）依旧不显示** ✗
  --   ⇒ 把两条并排看，唯一差别就是「**有没有链接**」（颜色值也换成同款试过：仍是这一条差异最干净）。
  --   ⇒ A 行改成与 B **同款结构**：`|c<身份色>|HEHPF:<id> 0/1:0|h[<头衔>]|h|r <名字> 分享了`
  --     （= 变异测 v2 的 [4]「纯文本 + 一段色码 + 链接 + 标签 + 评语」那一形态，**当时就画出来了** ✓）。
  --   ★判定依据仍**只认形态**（色码打头 · 一段色码 · 带链接），不发明新写法。
  local sealA, sealB = nil, nil
  if sealLine and sealLine ~= "" and type(EVAL_SHARE_SEAL_INFO) == "function" then
    local okI, sinfo = pcall(EVAL_SHARE_SEAL_INFO, text)
    if okI and type(sinfo) == "table" then
      local titleTxt = (type(sinfo.titleName) == "string" and sinfo.titleName ~= "") and tostring(sinfo.titleName) or ""
      local titleCol2 = (type(sinfo.title) == "table" and type(sinfo.title.color) == "string") and sinfo.title.color or nil
      -- ★A 身份行：一段身份色 + 头衔 + 名字（**无方括号、无链接**；与自家 EVAL_HELP 行同款形态）
      if titleTxt ~= "" then
        local who2 = nil
        if type(UnitName) == "function" then
          local okN, vN = pcall(UnitName, "player")
          if okN and type(vN) == "string" and vN ~= "" then who2 = vN end
        end
        if who2 then
          -- ★同款结构：一段色码打头 + 链接（序号 0/1:0，接收端按越界忽略）+ `[标签]|h|r` + 尾巴文字
          sealA = ((titleCol2 and (titleCol2 .. "|HEHPF:" .. idh .. " 0/1:0|h[" .. titleTxt .. "]|h|r  ")) or (titleTxt .. " ")) .. who2 .. " 分享了"
          if string.len(sealA) > SH_MSG_MAX then sealA = nil end -- 长度守卫（同规矩）
        end
      end
      if type(sinfo.tierName) == "string" and type(sinfo.plan) == "string" then
        local sym2 = tostring(sinfo.symbol or "")
        local tierCol2 = (type(sinfo.color) == "string" and sinfo.color ~= "") and sinfo.color or SH_CHUNK_COLOR
        local cmt2 = (type(sinfo.comment) == "string") and sinfo.comment or ""
        -- ★★★1.73.50 用户（真机截图）：「分享信息：方案**右侧的玩家角色可以不显示**」⇒ B 行**不再带身份尾巴**。
        --   身份在 A 行（`|c<身份色>|HEHPF:id 0/1:0|h[头衔]|h|r 名字 分享了`）已经显示过一次了；
        --   B 行紧跟其后，再带一遍「阿凡提」就是**同一屏重复**（当初留它是怕 A 行画不出来 —— A 已实测正常）。
        --   ⇒ B 行只剩「品阶秘籍·方案 + 评语」，正是 v2 变异测里**已验证能画**的那个形态。
        -- ★1.73.43n 长度守卫：分享信息那条**必须与分片同规矩**（≤ SH_MSG_MAX）。
        --   超了先砍评语，还超就整条不发（**如实说一声**，绝不发一条会被客户端/服务器丢掉的超长消息）。
        local sealBase = tierCol2 .. "|HEHPF:" .. idh .. " 0/1:1|h[" .. sym2 .. tostring(sinfo.tierName) .. "秘籍·" .. tostring(sinfo.plan) .. "]|h|r  "
        sealB = sealBase .. cmt2
        if string.len(sealB) > SH_MSG_MAX then
          sealB = sealBase
          if string.len(sealB) > SH_MSG_MAX then
            sealB = nil
            shSay("分享信息行超过本客户端实测上限 " .. SH_MSG_MAX .. " 字节，本次省略（方案分片照常发送）")
          end
        end
      end
    end
  end
  -- ★1.73.43o 两条分享信息：A 身份行（带身份色）→ B 品阶行（带品阶色）；依次入队、排在所有分片之后
  SH.sealPendA, SH.sealPendB = sealA, sealB
  SH.sealSentLast = sealB or sealLine or ""
  SH.sealSentFirst = sealA or ""
  SH.sealLast = SH.sealSentLast
  return bodies -- ★★（上一版把这一行连同旧块一起替换掉了 → shBuildFor 返回 nil、分享直接失败；判据当场抓到）
end
local function shBodies()
  if type(EVAL_PROFILE_TO_TEXT) ~= "function" then shSay(L("SH_NOEXPORT")) return nil end
  if type(RunScript) ~= "function" then shSay(L("SH_NORUNSCRIPT")) return nil end
  local text = EVAL_PROFILE_TO_TEXT()
  if not text or text == "" then shSay(L("SH_EMPTY")) return nil end
  return shBuildFor(text)
end
-- ★★★1.73.42h 测试挂钩：任意文本 -> 分片。判「<=250B 预算」必须能喂**长方案**
--   （短方案只出一片，片长上限定多少都看不出来——变异「忽略预算、退回固定 220」曾在短方案下 SURVIVED），
--   同时长方案收回来要能逐字节复原（分片切法改错会在这里露出）。
function EVAL_TEST_SHARE_BUILD_TEXT(text) return shBuildFor(tostring(text or "")) end
function EVAL_SHARE_SEND_PROBE()
  local q, i = {}, 0
  for i = 1, table.getn(shTxQ) do
    local it = shTxQ[i]
    table.insert(q, { seal = it.seal and true or false, chan = tostring(it.chan or ""),
                      head = string.sub(tostring(it.body or ""), 1, 40), len = string.len(tostring(it.body or "")) })
  end
  local log = {}
  for i = 1, table.getn(SH.sentLog or {}) do
    local e = SH.sentLog[i]
    table.insert(log, { seal = e.seal and true or false, at = e.at, s = tostring(e.s or "") }) -- ★完整脚本（判据要数引号；聊天打印时再截断）
  end
  local seal = tostring(SH.sealSentLast or SH.sealLast or "")
  local sealA2 = tostring(SH.sealSentFirst or "") -- ★发送侧那条（接收侧有自己的字段）
  local probe = { sealLen = string.len(seal), seal = string.sub(seal, 1, 90),
                  sealPending = (SH.sealPendA ~= nil or SH.sealPendB ~= nil), sealA = SH.sealPendA, sealB = SH.sealPendB, sealPopped = SH.sealPopped or 0,
                  queueLen = table.getn(shTxQ), queue = q, sent = log,
                  ticker = (shTxFrame ~= nil),
                  tickerShown = (shTxFrame and type(shTxFrame.IsShown) == "function" and (pcall(shTxFrame.IsShown, shTxFrame) == true)) and true or false,
                  rate = SH_SEND_RATE, max = SH_MSG_MAX }
  local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgP) == "table" then cfgP.shProbe = probe end -- ★落盘证人（判据不玩聊天含子串）
  shSay("===== 分享发送 · 取证 =====")
  shSay("  身份行：长度 " .. tostring(string.len(sealA2)) .. " 字节 · " .. shRawForPrint(string.sub(sealA2, 1, 90)))
  shSay("  品阶行：长度 " .. tostring(probe.sealLen) .. " 字节" ..
        ((probe.sealLen == 0) and "（★空串！这就是「没显示」的原因）" or ("：" .. shRawForPrint(string.sub(seal, 1, 110)))))
  shSay("  分享信息进度：排队中残留=" .. tostring(probe.sealPending) .. "（A/B 两条）· 已从队列弹出 " .. tostring(probe.sealPopped) .. " 次")
  shSay("  队列剩余：" .. tostring(probe.queueLen) .. " 条" .. ((probe.queueLen > 0) and "（★卡住了：发完前别重复点）" or "（已发完）"))
  for i = 1, math.min(4, table.getn(q)) do
    shSay("    " .. i .. (q[i].seal and " [封皮]" or " [分片]") .. " " .. tostring(q[i].len) .. "B · " .. q[i].head)
  end
  shSay("  最近实际发出的脚本（新→旧，最多 6 条）：")
  local shown = 0
  for i = table.getn(log), 1, -1 do
    if shown < 6 then
      shown = shown + 1
      -- ★头 + 尾都打（中间省略）：只看头会把「链接怎么闭合的」这件事永远藏起来
      local full = tostring(log[i].s)
      local head = string.sub(full, 1, 56)
      local tail = string.sub(full, -26)
      shSay("    " .. (log[i].seal and "[封皮] " or "[分片] ") .. " " .. tostring(string.len(full)) .. "B · " ..
            shRawForPrint(head) .. " … " .. shRawForPrint(tail))
    end
  end
  if table.getn(log) == 0 then shSay("    （一条都没发出去 —— 连第 1 片都没有，说明发送路径没走到）") end
  return probe
end
-- ★1.73.35 右键菜单「分享方案」：把**当前激活方案**密语给这个玩家（同一份分片 + 同一限频队列，只多一个 target）
function EVAL_SHARE_SEND_TO(name)
  if type(name) ~= "string" or name == "" then return false end
  local bodies = shBodies()
  if not bodies then return false end
  return shTxEnqueue(bodies, "WHISPER", name)
end
function EVAL_SHARE_SEND(chanId)
  if not shChanOf(chanId) then shSay(L("SH_CH_OFF")) return false end -- 1.71.3 团队频道已下线，白名单外一律拒收
  local bodies = shBodies()
  if not bodies then return false end
  -- ★1.72.3 分片必须**限频发送**（同帧连发会被反刷屏吞掉 → 对方永远收不齐）
  return shTxEnqueue(bodies, chanId)
end
-- IO 窗 [分享] 按钮：频道下拉
function EVAL_SHARE_SEND_UI(anchor)
  if type(EVAL_DD_OPEN) ~= "function" then EVAL_SHARE_SEND("GUILD") return end
  local items, ids = {}, {}
  for _, c in ipairs(SH_CHANS) do
    table.insert(items, c.name())
    table.insert(ids, c.id)
  end
  EVAL_DD_OPEN(anchor, items, function(pi)
    local c = SH_CHANS[pi]
    if not c then return end
    if not c.ok() then shSay(L("SH_CH_NO")) return end
    EVAL_SHARE_SEND(c.id)
  end)
end

-- ===== 接收侧：事件扫描 + 分片缓存 + 收齐弹窗 =====
-- ★1.71.3 接收规则优化（用户要求：「优化接收端的接收数据规则. 在多个分享同时出现的时候只显示最新的数据，
--   防止有些人滥发，或者多人发送接收异常.」）
--   规则一览（每条都「如实告知 + 限频」）：
--   R1 **只保留最新一份**：收齐的新分享直接**替换**当前待导入的那份（同一个弹窗、单一数据槽，不叠加）
--      ——「最新」按**收齐时刻**算；被替换掉的那份如实说一句（谁取代了谁）。
--   R2 **同一发送者开始新的一笔 → 他旧的未收齐缓冲立刻作废**（连点两次分享时，旧那笔只到一半就丢弃）。
--      ★只按「发送者」作废旧笔，**绝不跨发送者**：不同人同时发时两边的分片会交错到达，
--        若互相作废（我第一版的想法）会**两边都收不齐**，比不做还糟。
--   R3 **在途传输笔数上限** SH_MAX_BUF：超出时丢弃最久未活动的一笔（多人同时发 / 滥发的兜底）。
--   R4 **单笔分片数上限** SH_MAX_CHUNKS：整笔拒收（防伪造「1/9999」这种超大包）。
--   R5 **单笔解码上限** SH_MAX_TEXT：整笔拒收（防超长内容）。
--   R6 **去重表上限** SH_MAX_DONE：按插入序丢最旧（防无限增长）。
--   R7 **接收侧提示统一限频** SH_WARN_GAP：窗口内只报一次，并在下一次真正报出时告知「另有 N 条已省略」。
--      ★为什么连我们自己的提示也要限频：提示同样是聊天消息——**滥发者能让我们的提示刷屏**。
--      ★限频的是「说不说」，**不是「拦不拦」**：数据侧的拒收/替换一律照常执行（绝不因为限频而静默放过）。
local SH_RECV_TOLERANCE = 2 -- ★1.72.3 **接收冗余时长**：某片最多容忍 2 秒的迟到/抖动（每片到达即重置计时）
local SH_BUF_TIMEOUT = 60   -- 在途传输**真正丢弃**的兜底时长（秒）——先提醒、再等，最后才丢
local SH_MAX_BUF = 4        -- 同时在途的传输笔数上限
local SH_MAX_CHUNKS = 40    -- 单笔分享的最大分片数（合法方案远小于此）
local SH_MAX_TEXT = 8192    -- 单笔分享解码后的最大字节数
local SH_MAX_DONE = 64      -- 去重表保留条数上限
local SH_WARN_GAP = 5       -- 接收侧提示的最短间隔（秒）

local function shNowT()
  return (type(GetTime) == "function") and GetTime() or 0
end

local shWarnLast, shWarnSkip = 0, 0
-- 限频提示：窗口内静默累计条数，下一次真正报出时把「省略了几条」一并说出（绝不静默丢弃）
local function shWarn(msg)
  shWarnSkip = shWarnSkip + 1
  local now = shNowT()
  if now - shWarnLast < SH_WARN_GAP then return end
  local skip = shWarnSkip - 1
  shWarnLast, shWarnSkip = now, 0
  shSay(msg .. ((skip > 0) and string.format(L("SH_WARN_MORE"), skip) or ""))
end

-- ★1.72.3 发送队列实现（实现在这里，因为要用上面的 shNowT）
-- ★★★1.73.43b 发送留痕：把**真正交给 RunScript 的脚本原文**留最近 12 条（含「是不是封皮」）。
--   为什么要有它：客户端**不回话**（RunScript 不报错、SendChatMessage 也不报错），
--   所以「封皮没显示」这类问题只能看「我们到底发了什么」——这就是唯一现场。
SH.sentLog = SH.sentLog or {}
local function shSentLog(script, isSeal)
  table.insert(SH.sentLog, { s = tostring(script), seal = isSeal and true or false, at = shNowT() })
  while table.getn(SH.sentLog) > 12 do table.remove(SH.sentLog, 1) end
end
-- ★★★脚本串必须中和引号/反斜杠：`SendChatMessage("…")` 里只要出现一个 `"`，**整条脚本作废**，
--   而 RunScript **一声不响**（玩家看到的就是「这条消息凭空消失」）。同名老坑：`tbSafeName` 就是为它写的。
-- ★★★1.73.43c **取证打印必须先转义 `|`（写成 `||`）**：否则客户端把 `|HEHPF:…|h` 当链接吃掉、`|cff…` 当颜色吃掉，
--   打出来的「脚本原文」根本不是原文 —— 本轮第一份取证就是这么被瞒过去的（看到的脚本里 `|` 全没了）。
--   ★声明放在这里（上方探针要用它；DECL ORDER 检查守这条）。
local function shScriptSafe(t)
  t = tostring(t or "")
  t = string.gsub(t, string.char(34), "'")
  t = string.gsub(t, string.char(92), "/")
  return t
end
-- 唯一的发送点（立即发与队列滴出都走它）→ 留痕不会漏
local function shSendNow(body, chanId, target, isSeal)
  local sc
  if target and target ~= "" then
    sc = 'SendChatMessage("' .. shScriptSafe(body) .. '", "' .. tostring(chanId) .. '", nil, "' .. shScriptSafe(target) .. '")'
  else
    sc = 'SendChatMessage("' .. shScriptSafe(body) .. '", "' .. tostring(chanId) .. '")'
  end
  shSentLog(sc, isSeal)
  if type(RunScript) == "function" then RunScript(sc) end
  return sc
end
function shTxStep()
  if table.getn(shTxQ) == 0 then
    if shTxFrame then pcall(shTxFrame.Hide, shTxFrame) end
    return
  end
  local now = shNowT()
  if now - shTxLast < SH_SEND_RATE then return end -- ★限频：到点才滴下一片
  shTxLast = now
  local job = table.remove(shTxQ, 1)
  if job.seal then SH.sealPopped = (SH.sealPopped or 0) + 1 end -- ★封皮真的从队列里出来了（留痕）
  -- ★1.73.35 密语分享：带 target 时补第 4 参（SendChatMessage(body, "WHISPER", nil, 目标)）
  --   ★1.73.43b 统一走 shSendNow：脚本串中和 + 留痕（立即发/队列滴出同一条路）
  shSendNow(job.body, job.chan, job.target, job.seal)
  if table.getn(shTxQ) == 0 and shTxFrame then pcall(shTxFrame.Hide, shTxFrame) end
end
local function shEnsureTxTicker()
  if not shTxFrame then
    shTxFrame = CreateFrame("Frame", "EVAL_SHARE_TX", UIParent)
    shTxFrame:SetScript("OnUpdate", shTxStep)
  end
  pcall(shTxFrame.Show, shTxFrame)
end
-- ★1.73.43g 分享信息现在可能有**两条**（A 身份行 / B 品阶行）—— 统一从这里数
local function shSealCount()
  local c = 0
  if type(SH.sealPendA) == "string" and SH.sealPendA ~= "" then c = c + 1 end
  if type(SH.sealPendB) == "string" and SH.sealPendB ~= "" then c = c + 1 end
  return c
end
function shTxEnqueue(bodies, chanId, target)
  local n = table.getn(bodies)
  local extra = shSealCount() -- ★上限如实算上分享信息那两条（它们排在分片之后）
  if table.getn(shTxQ) + n + extra > SH_MAX_QUEUE then
    shSay(string.format(L("SH_Q_FULL"), SH_MAX_QUEUE))
    return false
  end
  -- 第 1 片立即发（手感与旧版一致），其余排队（★同走 shSendNow：留痕不断层）
  shSendNow(bodies[1], chanId, target, false)
  for i = 2, n do table.insert(shTxQ, { body = bodies[i], chan = chanId, target = target }) end
  -- ★★★1.73.43f 分享信息排在**所有分片之后**（用户：「方案分享最后一步 展示分享信息」）；
  --   它是一条与分片**同款结构**的消息（见 shBuildFor），所以走同一条已被证明能画的通道。
  local hasSeal = false
  if type(SH.sealPendA) == "string" and SH.sealPendA ~= "" then
    table.insert(shTxQ, { body = SH.sealPendA, chan = chanId, target = target, seal = true })
    SH.sealPendA = nil hasSeal = true
  end
  if type(SH.sealPendB) == "string" and SH.sealPendB ~= "" then
    table.insert(shTxQ, { body = SH.sealPendB, chan = chanId, target = target, seal = true })
    SH.sealPendB = nil hasSeal = true
  end
  -- ★条数如实 = 分片 + 分享信息（0~2 条）；两条都排在分片之后
  local total = n + extra
  if total > 1 then
    shTxLast = shNowT()
    shEnsureTxTicker()
    shSay(string.format(L("SH_QUEUED"), total, (total - 1) * SH_SEND_RATE))
  else
    shSay(string.format(L("SH_SENT"), total))
  end
  return true
end
-- ★测试直调：驱动与 OnUpdate **同一个**函数（判据必须落在真实调用点/真实闭包上）
function EVAL_SHARE_TEST_TICK() shTxStep() end
-- ★1.73.43b 测试钩子：清空「发送留痕」（判据只看**本次分享**发出的脚本，不受前面用例污染）
-- ★★★1.73.43b 取证命令 `/eh go 分享探针`（用户报「还是没显示分享信息」）：把**唯一的现场**一次摊开 ——
--   客户端不回话（RunScript/SendChatMessage 都不报错），所以只能看：① 封皮行算什么了、多长；
--   ② 队列里还剩什么（是否卡着封皮）；③ **真正交给 RunScript 的脚本原文**；④ 封皮有没有被弹出过。
-- ★★★1.73.43d 一封「**变异测**」命令：把封皮拆成 9 种形态**编号**发到「说」频道（每 0.5 秒一条，同一限频队列），
--   用户只需回报「哪些编号出现了」—— 一次就把「是哪个字符/哪种结构让客户端吞消息」夹出来。
--   为什么这么干：客户端不回话，而这一个现象已经来回三轮（本轮已能证明「我们发了、客户端不画」）。
function EVAL_SHARE_SEAL_VARIANT_PROBE()
  -- ★★★1.73.43e 第二轮变异测（第一轮结论已定案两件事）：
  --   ① 第一轮里 **[4]「色码」那条整条没出现** —— 而那条是我手打错的**7 位色码**（`|cffff2c8`）⇒
  --      **客户端遇到不合法的颜色码会把整条消息吞掉**（不报错、不显示）——这是本次最有价值的客户端事实。
  --   ② 于是本轮把「色码/链接/符号/方括号/长度」逐个拆开，专门夹出**封皮那条**死在哪个成分上。
  --   ★所有色码一律用 8 位（`|cAARRGGBB`）字面量，不再手打。
  local TITLE_COL = "|cffffd700"   -- 彩蛋自定义头衔色（8 位；★1.73.45 起默认=帝王金，实际选用色见 shTitleCustomColor()）
  --   ★这里保留**字面量快照**（不变色）：本命令测的是**消息形态**（哪个结构会被客户端吞），颜色取哪个都一样；
  --     且本函数声明在 shTitleCustomColor() 之前，直接调用会踩「local 声明晚于使用」的铁律（DECL ORDER 守着）。
  local TIER_COL  = "|cffc00000"   -- 神级档品阶色（8 位；★1.73.60 起 = **深红**，取自 SH_SEAL_TIERS）
  local who, plan, cmt, sym, title = "Ionol", "武器战", "看懂？", "★", "阿凡提"
  if type(UnitName) == "function" then
    local ok, v = pcall(UnitName, "player")
    if ok and type(v) == "string" and v ~= "" then who = v end
  end
  local idh = "e251"
  local tinfo = nil
  if type(EVAL_PROFILE_TO_TEXT) == "function" and type(EVAL_SHARE_SEAL_INFO) == "function" then
    local t = EVAL_PROFILE_TO_TEXT()
    if type(t) == "string" and t ~= "" then
      tinfo = EVAL_SHARE_SEAL_INFO(t)
      if tinfo and tinfo.plan then plan = tostring(tinfo.plan) end
      if tinfo and tinfo.titleName then title = tostring(tinfo.titleName) end
      if tinfo and tinfo.comment then cmt = tostring(tinfo.comment) end
    end
  end
  local link = "|HEHPF:" .. idh .. "|h"
  local head = TITLE_COL .. "[" .. title .. "]|r" .. who .. " 分享了 → " .. TIER_COL .. sym
  local tailTxt = "[" .. plan .. "]|h|r " .. cmt
  local sFull    = head .. link .. tailTxt                       -- 现写法（完整封皮）
  local sNoTitle = who .. " 分享了 → " .. TIER_COL .. sym .. link .. tailTxt
  local sNoTier  = TITLE_COL .. "[" .. title .. "]|r" .. who .. " 分享了 → " .. sym .. link .. tailTxt
  local sNoCol   = "[" .. title .. "]" .. who .. " 分享了 → " .. sym .. link .. tailTxt
  local sNoLink  = head .. "[" .. plan .. "]|r " .. cmt
  -- ★★★1.73.43g 用户提问：「是因为同一段话不能加 2 个有颜色的连接吗?」⇒ 本轮把这点做成**A/B 对照**：
  --   [1] 一段色码 + 链接（= 分片同款，已知能画）   [2] 两段色码 + 链接（= 现封皮的颜色结构）
  --   再加上「标签里的 `·` 换掉」这一条 —— 目前**只剩这两个**结构差异还没被排除。
  -- ★★★1.73.43j 用户澄清：「**多色码一行走不通就单色码一行一行发**」；并指出 A 身份行**也是单色码**却没显示 ⇒
  --   「那就不是单/双色码的问题，而是**哪些特殊字符**让这一行无法显示」⇒ 本轮变异测专测 A 行原样与逐个要素替换：
  --   ★★★1.73.43m 用户问「是否是头衔上有特殊字符」→ 有反证（[4] 里就有「阿凡提」三个字，它**显示了** ✓），
  --   所以本轮换一条思路：把**三个可能轴**一次摊开 —— ①频道（说 / 小队）②链路载荷形态 ③有没有色码：
  --   [1] 说 · 色码+纯文本        [2] 小队 · 同一串            ← 频道轴（同串两频道）
  --   [3] 说 · 色码+`0/1:0`链接   [4] 说 · 色码+`1/1:00`链接   [5] 说 · 色码+无序号链接  ← 载荷轴
  --   [6] 说 · `0/1:0`链接(无色码)                             ← 色码轴
  --   [7] 说 · 纯文本(对照)      [8] 小队 · 纯文本(对照)
  --   [9] 说 · 现用 B 行原样     [10] 小队 · 现用 B 行原样      ← 现用形态 × 两频道
  local linkId = string.match(sFull, "|HEHPF:(%x+)") or "e251"
  local link0 = "|HEHPF:" .. tostring(linkId) .. " 0/1:0|h[" .. sym .. plan .. "]|h|r"
  local link1 = "|HEHPF:" .. tostring(linkId) .. " 1/1:00|h[" .. sym .. plan .. "]|h|r"
  local linkN = "|HEHPF:" .. tostring(linkId) .. "|h[" .. sym .. plan .. "]|h"
  local vs = {
    "[1] 说 · 色码+纯文本：" .. TIER_COL .. "[" .. title .. "]|r " .. who,
    "[2] 小队 · 同一串：" .. TIER_COL .. "[" .. title .. "]|r " .. who,
    "[3] 说 · 色码+0/1:0链接：" .. TIER_COL .. link0,
    "[4] 说 · 色码+1/1:00链接：" .. TIER_COL .. link1,
    "[5] 说 · 色码+无序号链接：" .. TIER_COL .. linkN,
    "[6] 说 · 0/1:0链接(无色码)：" .. link0,
    "[7] 说 · 纯文本对照：" .. who .. " 分享了",
    "[8] 小队 · 纯文本对照：" .. who .. " 分享了",
    "[9] 说 · 现用B行原样：" .. sFull,
    "[10] 小队 · 现用B行原样：" .. sFull,
  }
  local chans = { "SAY", "PARTY", "SAY", "SAY", "SAY", "SAY", "SAY", "PARTY", "SAY", "PARTY" }
  local n = table.getn(vs)
  for i = 1, n do table.insert(shTxQ, { body = vs[i], chan = chans[i] or "SAY" }) end
  shTxLast = shNowT()
  shEnsureTxTicker()
  local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
  local probe = { n = n, list = vs, at = shNowT(), idh = idh }
  if type(cfgP) == "table" then cfgP.shVariantProbe = probe end -- ★落盘证人
  shSay("===== 封皮变异测 v2（10 条，已排队到「说」）=====")
  shSay("  每条间隔 1 秒（★跑完请**等 30 秒以上**再跑第二次，期间别再分享 —— 短时间多条会被客户端/服务器吞，第二轮结果不可信）")
  shSay("  请把**实际出现的编号**告诉我（没出现的同样重要）")
  shSay("  1 说·色码+纯文本 · 2 小队·同一串 · 3 说·色码+0/1链接 · 4 说·色码+1/1链接 · 5 说·色码+无序号链接 · 6 说·链接无码 · 7 说·纯文本 · 8 小队·纯文本 · 9 说·现用B行 · 10 小队·现用B行")
  return probe
end

function EVAL_TEST_SHARE_SENTLOG_CLEAR() SH.sentLog = {} return true end
-- ★1.73.43f 测试钩子：把发送队列**一次滴干**（分片数会随方案长度变化，夹具必须先滴干再收集）
-- ★1.73.43f 测试钩子：把发送队列填到指定条数（验「队列上限把分享信息那一条也算进去」）
function EVAL_TEST_SHARE_QUEUE_FILL(n)
  shTxQ = {}
  local k = tonumber(n) or 0
  for i = 1, k do
    table.insert(shTxQ, { body = "|cff9ad4ff|HEHPF:ffff " .. i .. "/" .. k .. ":00|h[填队列]|h|r", chan = "SAY" })
  end
  return table.getn(shTxQ)
end
function EVAL_TEST_SHARE_DRAIN()
  local g = 0
  while table.getn(shTxQ) > 0 and g < 500 do
    g = g + 1
    if type(TEST) == "table" then TEST.time = (TEST.time or 1000) + 1 end
    shTxStep()
  end
  return g
end
-- ★按本次传输 id 数队列里的分片（不受上一笔遗留影响）
function EVAL_TEST_SHARE_QUEUE_ID_COUNT(idh)
  local want = tostring(idh or "")
  if want == "" then return -1 end
  local c = 0
  for q = 1, table.getn(shTxQ) do
    -- ★1.73.43f 封皮那条带 seal 标记、且序号是 0/1（不是分片）→ 不计数
    if not shTxQ[q].seal then
      local bd = tostring(shTxQ[q].body or "")
      if string.find(bd, "|HEHPF:" .. want .. " ", 1, true) or string.find(bd, "[EHPF#" .. want .. " ", 1, true) then c = c + 1 end
    end
  end
  return c
end
-- ★诊断：队列里到底是什么
function EVAL_TEST_SHARE_QUEUE_DUMP()
  local out = {}
  for q = 1, table.getn(shTxQ) do out[q] = string.sub(tostring(shTxQ[q].body or ""), 1, 34) end
  return out
end
function EVAL_SHARE_TEST_QUEUE_LEN() return table.getn(shTxQ) end-- ★★★1.72.3 **收不齐绝不静默**，且**给晚到的分片留冗余窗口**（用户要求：1~2 秒内都可以）。
--   两级判定：
--     ① 空闲超过 SH_RECV_TOLERANCE(2s) 仍未收齐 → **如实提醒**（点名发送者 + 收了几片），
--        ★但**不删缓冲**：发送是限频滴出的（每片 0.5s），漏一片时后面几片还会来；
--        晚到的那片若能补齐，这一笔照样弹窗（冗余窗口就是为它留的）。
--     ② 空闲超过 SH_BUF_TIMEOUT(60s) → 才真正丢弃（已提醒过就不再重复刷屏）。
--   ★为什么按「最后一片到达时刻」计时（b.t 每片刷新）：发送方在持续滴片时窗口不断顺延，
--     不会因为「方案长、总耗时 4~5 秒」而误报；只有**对方停止发送**之后才可能触发提醒。
local function shSweepBuf(now)
  for k, b in pairs(SH.buf) do
    local idle = now - b.t
    if idle > SH_BUF_TIMEOUT then
      SH.buf[k] = nil
      if not b.warned then
        shWarn(string.format(L("SH_RECV_PARTIAL"), tostring(b.from or "?"), b.got or 0, b.n or 0))
      end
    elseif idle > SH_RECV_TOLERANCE and not b.warned then
      b.warned = true
      shWarn(string.format(L("SH_RECV_PARTIAL"), tostring(b.from or "?"), b.got or 0, b.n or 0))
    end
  end
end
-- R3：在途笔数超上限 → 丢最久未活动的一笔（如实提示）
local function shTrimBuf()
  local cnt, oldK, oldT = 0, nil, nil
  for k, b in pairs(SH.buf) do
    cnt = cnt + 1
    if (oldT == nil) or (b.t < oldT) then oldK, oldT = k, b.t end
  end
  if cnt > SH_MAX_BUF and oldK then
    SH.buf[oldK] = nil
    shWarn(string.format(L("SH_DROP_MANY"), SH_MAX_BUF))
  end
end

-- R2：同一发送者开始新的一笔 → 他旧的未收齐缓冲作废（只看前缀，不走模式串，名字里有特殊字符也安全）
local function shDropSenderBufs(sender, keepKey)
  local pre = sender .. "#"
  local pl = string.len(pre)
  for k in pairs(SH.buf) do
    if k ~= keepKey and string.sub(k, 1, pl) == pre then SH.buf[k] = nil end
  end
end

-- R6：去重表按插入序丢最旧（doneList 只记顺序，真值仍在 done 里）
local function shMarkDone(key)
  SH.done[key] = true
  table.insert(SH.doneList, key)
  while table.getn(SH.doneList) > SH_MAX_DONE do
    local old = table.remove(SH.doneList, 1)
    SH.done[old] = nil
  end
end

-- ★1.71.3 收到分享时标出**来源频道**（用户要求：「能否辨别是否是公会来源」）。
--   判据就是**触发的那个事件名**（我们本来就按频道分别注册了事件）——比拿消息文本去猜可靠得多。
--   ★队长/团长的聊天走 *_LEADER 事件，一并归类（接收侧不能把队长当成野人）。
function EVAL_SHARE_CHAN_LABEL(ev)
  if type(ev) ~= "string" then return nil end
  if ev == "CHAT_MSG_GUILD" then return L("SH_CH_GUILD") end
  if ev == "CHAT_MSG_PARTY" or ev == "CHAT_MSG_PARTY_LEADER" then return L("SH_CH_PARTY") end
  if ev == "CHAT_MSG_RAID" or ev == "CHAT_MSG_RAID_LEADER" or ev == "CHAT_MSG_RAID_WARNING" then return L("SH_CH_RAID") end
  if ev == "CHAT_MSG_SAY" then return L("SH_CH_SAY") end
  if ev == "CHAT_MSG_WHISPER" then return L("SH_CH_WHISPER") end
  return nil -- 认不出来就**不标**（不瞎猜一个来源）
end

-- msg/sender 来自事件；ev = 触发的事件名（可缺：测试直调时为 nil）
-- ★1.71.3 这条分享内容是不是**我自己的方案**（用户要求：非「说」来源的自我回声直接忽略）。
--   判据：解析出来同名 → 把我的那份**序列化后逐字比对**（只比名字会误伤「同名不同内容」）。
function EVAL_SHARE_IS_MINE(text)
  if type(text) ~= "string" or text == "" then return false end
  if type(EVAL_PROFILE_FROM_TEXT) ~= "function" or type(EVAL_PROFILE_TO_TEXT) ~= "function" then return false end
  local prof = EVAL_PROFILE_FROM_TEXT(text)
  if type(prof) ~= "table" then return false end
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  local list = (type(c) == "table" and type(c.war) == "table") and c.war.profiles or nil
  if type(list) ~= "table" then return false end
  local function norm(s) return (string.gsub(tostring(s or ""), "%s+", "")) end
  local want = norm(text)
  for i, p in ipairs(list) do
    if type(p) == "table" and tostring(p.name) == tostring(prof.name) then
      local ok, mine = pcall(EVAL_PROFILE_TO_TEXT, p)
      if not (ok and type(mine) == "string") then ok, mine = pcall(EVAL_PROFILE_TO_TEXT, i) end
      if ok and type(mine) == "string" and norm(mine) == want then return true end
    end
  end
  return false
end

-- ★1.71.3 公会来源的分享：点按钮时在**公会频道**玩一句（用户指定的两句话）。
--   ★只在「触发事件是 CHAT_MSG_GUILD」且**真的在公会里**时才发（公会聊天 SendChatMessage 是 Protected → 走 RunScript，同分享发送）。
--   ★发不出去就返回 false（不假装发了）。
local function shGuildFun(fmtKey)
  local p = SH.pending
  if not p then return false end
  if p.ev ~= "CHAT_MSG_GUILD" then return false end
  if type(IsInGuild) == "function" then
    local okg, ing = pcall(IsInGuild)
    if okg and not ing then return false end
  end
  local txt = string.format(L(fmtKey), tostring(p.sender), tostring(p.name))
  if type(RunScript) ~= "function" then return false end
  pcall(RunScript, string.format("SendChatMessage(%q, %q)", txt, "GUILD"))
  EVAL_LOGLINE("[分享] 已在公会频道发送：" .. txt)
  return true
end

-- msg/sender 来自事件；ev = 触发的事件名（可缺：测试直调时为 nil）
-- ★1.73.41 调研探针状态 + 捕获（探针数据**绝不进正常接收缓冲**，避免污染导入流程）
local SH_PROBE = { armed = nil, sent = {}, recv = {}, ladderSent = {}, verdicts = nil }
local function shProbeCapture(msg, sender, ev)
  local p = SH_PROBE
  if not p.armed then return false end
  local mode = p.armed.mode or "?"
  p.recv[mode] = p.recv[mode] or {}
  table.insert(p.recv[mode], { raw = msg, sender = tostring(sender or "?"), ev = tostring(ev or "?"),
                               n = string.len(msg) })
  return true
end
-- ★★★1.73.42g 封皮行点击导入：收齐后缓存整份方案（FIFO 8 笔）
local SH_RECENT_MAX = 8
local function shRecentPut(key, text, sender, ev)
  SH.recent = SH.recent or {}
  SH.recentList = SH.recentList or {}
  if not SH.recent[key] then table.insert(SH.recentList, key) end
  SH.recent[key] = { text = text, sender = tostring(sender or "?"), ev = ev, t = shNowT() }
  while table.getn(SH.recentList) > SH_RECENT_MAX do
    local old = table.remove(SH.recentList, 1)
    SH.recent[old] = nil
  end
end
local function shSealNote(sender, id)
  SH.sealSeen = (SH.sealSeen or 0) + 1
  SH.sealRecvLast = tostring(sender or "?") .. "#" .. tostring(id or "?") -- ★接收侧自己的字段（不再盖发送侧）
end
local function shOnMsg(msg, sender, ev)
  if type(msg) ~= "string" then return end
  -- ★1.73.41 探针优先：命中探针标识的消息**只记进探针**，不进正常缓冲
  if SH_PROBE.armed and string.find(msg, SH_PROBE.armed.tag, 1, true) then
    shProbeCapture(msg, sender, ev)
    return
  end
  local idh, i, n, payload = string.match(msg, "^%[EHPF#(%x+) (%d+)/(%d+)%](%x*)$")
  if not idh then -- ★v2：载荷藏在自定义链接的 |H 段
    local inner = string.match(msg, "|HEHPF:([^|]*)|h")
    if inner then idh, i, n, payload = string.match(inner, "^(%x+) (%d+)/(%d+):(%x*)$") end
  end
  -- ★★★1.73.43f 分享信息那条的**统一处理**：老式（`|HEHPF:id|h`，无序号）与新式（`<id> 0/1:0`，与分片同款结构）
  --   都从这里进 —— 记「这一笔真的发完了」+ 身份/评语（只有发送端知道的那两样）。
  local function shSealCapture(sid)
    if not sid then return end
      -- ★★★1.73.42i 顺手把「只有发送端知道」的两样东西记下来，供接收弹窗的品阶栏用：
      --   ① 境界 = 封皮行开头的 [境界]；② 评语 = 链接显示段 `|h[品阶秘籍·名]|h` 里方括号之后那段。
      --   ★解析不出来就**不记** → 弹窗如实写「未知」，绝不拿本机角色/本机随机评语冒充发送端的。
      -- ★1.73.42k 境界前面多了**颜色码**（`|cff9d9d9d[炼气]|r`）→ 原来锚定行首的 `^%[` 会直接失效，
      --   改成取**行内第一个方括号组**（封皮行里境界总在最前，品阶方括号在链接显示段里，排在它后面）。
      -- ★★★1.73.42o 身份**连颜色一起**从封皮行读回来（用户：「最终只是文本发出去.而不是本地变量调用.
      --   「所以不存在在其他玩家上电脑上看不到空的情况」）→ 接收端**照抄发送端的显示**：
      --   连**彩蛋自定义**的头衔也能原样带色显示（本地卡表里查不到那 75 张也照样显示，绝不空白）。
      local idColor, idName = string.match(msg, "(|c%x%x%x%x%x%x%x%x)%[([^%]]*)%]")
      local rank, rankColor = nil, nil
      if idName and idName ~= "" then rank, rankColor = idName, idColor
      else rank = string.match(msg, "%[([^%]]*)%]") end
      -- ★★★1.73.43c 两种结构都要认：
      --   ① **新**（1.73.43c 起）：链接只包 `[品阶秘籍·名]`，评语在**链接之外**（与分片同款结构）→
      --      形如 `…|HEHPF:id|h[神级秘籍·名]|h|r 评语`；
      --   ② **老**（老版本发出来的）：链接一直开到评语之后 → 评语在链接**内**。
      --   ★只认一种 = 另一侧发来的封皮**评语全丢**（判据 145③ 当场抓到）。
      local comment = nil
      local inside, after = string.match(msg, "|HEHPF:[^|]*|h(%[.-%])|h(.*)$")
      if inside and after and string.gsub(after, "%s", "") ~= "" then
        comment = after
      else
        local disp = string.match(msg, "|HEHPF:[^|]*|h(.-)|h")
        if disp then
          local rb = string.find(disp, "%]")
          if rb then comment = string.sub(disp, rb + 1) end
        end
      end
      if comment then
        comment = string.gsub(comment, "|r", "")
        comment = string.gsub(comment, "^%s+", "")
        comment = string.gsub(comment, "%s+$", "")
        if comment == "" then comment = nil end
      end
      SH.sealMeta = SH.sealMeta or {}
      SH.sealMeta[sid] = { rank = rank, rankColor = rankColor, comment = comment } -- ★颜色也存（发送端怎么显示，我们就怎么显示）
      shSealNote(sender, sid)
      -- ★封皮**晚到**（单片分享：分片先弹出、封皮紧随其后）→ 当场补刷品阶栏（同一份实现）
      if type(shSealRowApply) == "function" and SH.pending and tostring(SH.pending.idh or "") == tostring(sid) then
        pcall(shSealRowApply)
      end
  end
  if not idh then
    shSealCapture(string.match(msg, "|HEHPF:(%x+)")) -- 老式封皮：没有序号、链接只带 id
    return
  end
  if not shCfg().recv then return end
  i, n = tonumber(i), tonumber(n)
  if not i or not n or n < 1 or i < 1 or i > n then
    -- ★1.73.43f 新式分享信息（序号 0/1）会走到这里 —— 它**带发送端信息**，顺手记进 meta（接收行为不变）
    if string.find(msg, " 分享了 → ", 1, true) then shSealCapture(idh) end
    return
  end
  if n > SH_MAX_CHUNKS then shWarn(string.format(L("SH_DROP_BIG"), n, SH_MAX_CHUNKS)) return end -- R4
  sender = tostring(sender or "?")
  local now = shNowT()
  shSweepBuf(now)
  local key = sender .. "#" .. idh
  local b = SH.buf[key]
  if not b then
    shDropSenderBufs(sender, key) -- R2
    b = { n = n, chunks = {}, got = 0, t = now, ev = ev, from = sender } -- ★1.72.3 记住谁发的（收不齐时要如实点名）
    SH.buf[key] = b
    shTrimBuf() -- R3
  end
  b.t = now
  if not b.chunks[i] then
    b.chunks[i] = payload
    b.got = b.got + 1
  end
  if b.got >= b.n then
    SH.buf[key] = nil
    if SH.done[key] then return end -- 同一笔重复收齐不重复弹
    shMarkDone(key)
    local parts = {}
    for j = 1, b.n do parts[j] = b.chunks[j] or "" end
    local text = fromHex(table.concat(parts))
    if not text then return end
    if string.len(text) > SH_MAX_TEXT then -- R5
      shWarn(string.format(L("SH_DROP_BIGTEXT"), string.len(text), SH_MAX_TEXT))
      return
    end
    shRecentPut(key, text, sender, b.ev) -- ★1.73.42g 收齐后缓存整份方案（点击封皮时取回）
    -- ★1.71.3 用户要求：**不是「说」来源** 且内容就是**我自己的方案** → 直接忽略
    --   （自己往公会/队伍/团队发分享时，客户端会把分片**回声给自己**，不忽略就会自己弹自己的窗）。
    --   ★先确认「知道来源」（b.ev 非空）：认不出来时照旧弹出——宁可多弹一次，也不误吞真分享。
    if b.ev and b.ev ~= "CHAT_MSG_SAY" and EVAL_SHARE_IS_MINE(text) then
      SH.selfSkipped = (SH.selfSkipped or 0) + 1
      EVAL_LOGLINE("[分享] 已忽略（自己的方案回声）：来源=" .. tostring(b.ev or "?") .. " 发送者=" .. tostring(sender))
      return
    end
    -- R1：只保留最新一份 —— 弹窗内容换成最新的，并如实说明替换了谁
    local old = SH.pending
    EVAL_SH_POPUP(sender, text, b.ev, idh) -- ★1.73.42i 带上传输 id（品阶栏要用它取发送端的境界/评语）
    if old then shWarn(string.format(L("SH_POP_REPLACED"), tostring(sender), tostring(old.sender))) end
  end
end

function EVAL_SHARE_ONMSG(msg, sender, ev) shOnMsg(msg, sender, ev) end -- 测试直调（ev 可缺）
-- ===== 1.73.41 调研探针（分支 probe/share-hide-link）=====================================
-- 目的（用户：「新开一个分支测试以上探针」）：把调研报告里**读码定不了的两个行为**一次问清楚 ——
--   ① 自定义链接 `|c..|H<类型>:<载荷>|h[短文字]|h|r` 经**服务器往返**后还在不在（|c/|H 会不会被剥、载荷会不会被改）；
--   ② 聊天消息**真实长度上限**（现在 220 hex 字符/片是照 255 估的，**没有实测**）。
-- ★纪律：探针**只发不解析** —— 命中探针标识的消息只进 `SH_PROBE.recv`，**绝不进正常接收缓冲**（不污染导入流程）。
-- ★不动正常协议：[分享] 按钮 / 右键菜单那条路一行都不改；探针只在显式命令下运行，平时零开销。
-- ★两个探针都靠**明文里的唯一 tag** 认形态：即使服务器把 |c/|H 整段剥掉，形态仍能被认出来（这是能不能定案的关键）。
function EVAL_SHARE_PROBE_ARM(mode, tag)
  if type(mode) ~= "string" or type(tag) ~= "string" then return false end
  SH_PROBE.armed = { mode = mode, tag = tag }
  SH_PROBE.recv[mode] = {}
  return true
end
function EVAL_SHARE_PROBE_OFF()
  SH_PROBE.armed = nil
  return true
end
function EVAL_SHARE_PROBE_STATE()
  local p = SH_PROBE
  return { armed = (p.armed and p.armed.mode) or nil, tag = (p.armed and p.armed.tag) or nil,
           sent = table.getn(p.sent or {}), got = table.getn((p.recv or {}).link or {}),
           ladderSent = table.getn(p.ladderSent or {}), ladderGot = table.getn((p.recv or {}).len or {}),
           forms = p.sent, ladder = p.ladderSent, verdicts = p.verdicts or {} }
end
-- 探针 ① 的四种形态：同一前缀 tag，各形态再带**各自唯一**的 tag（明文可见，剥标记也认得出）
local function shProbeForms(prefix)
  local out = {}
  local function disp(i) return prefix .. string.format("%02x", i) end
  local hex1 = toHex("PROBE-" .. disp(1))
  -- ① 自定义链接（候选 v2）：载荷进 |H 段，只显示 [方案:探针 …]；② / ③ 是已知类型对照；④ 是现状格式对照
  table.insert(out, { idx = 1, tag = disp(1), label = "① 自定义链接（候选 v2）",
    body = "|cff9ad4ff|HEHPF:" .. disp(1) .. " 1/1:" .. hex1 .. "|h[方案:探针 " .. disp(1) .. "]|h|r" })
  table.insert(out, { idx = 2, tag = disp(2), label = "② 假物品链接（已知类型 item:）",
    body = "|cff9d9d9d|Hitem:1234:0:0:0:0:0:0:0|h[探针物品 " .. disp(2) .. "]|h|r" })
  table.insert(out, { idx = 3, tag = disp(3), label = "③ 假玩家链接（已知类型 player:）",
    body = "|cffff80ff|Hplayer:Probe" .. disp(3) .. "|h[探针 " .. disp(3) .. "]|h|r" })
  local hex4 = toHex("PROBE-" .. disp(4))
  table.insert(out, { idx = 4, tag = disp(4), label = "④ 明文分片（现状格式，对照组）",
    body = "[EHPF#" .. disp(4) .. " 1/1]" .. hex4 })
  return out
end
-- 探针 ② 的长度阶梯：每条消息**恰好 target 字节**，尾部带哨兵 `E<target>E`（被截断时哨兵先没）
local SH_PROBE_LADDER = { 200, 230, 250, 270 }
local function shProbeLadder(prefix, ladder)
  ladder = ladder or SH_PROBE_LADDER
  local out = {}
  for i = 1, table.getn(ladder) do
    local target = ladder[i]
    local tg = prefix .. string.format("%02x", i)
    local tail = "E" .. tostring(target) .. "E"
    local head = "[LAD#" .. tg .. " " .. tostring(target) .. "]"
    local fill = target - string.len(head) - string.len(tail)
    if fill < 1 then fill = 1 end
    table.insert(out, { idx = i, tag = tg, target = target, tail = tail,
      body = head .. string.rep("a", fill) .. tail })
  end
  return out
end
local function shProbeRandomTag() return string.format("%04x", math.random(0, 65535)) end
local function shProbeSend(bodies, chanId)
  local target = nil
  if chanId == "WHISPER" then
    target = (type(UnitName) == "function") and UnitName("player") or nil
    if type(target) ~= "string" or target == "" then
      shSay("探针：拿不到自己的名字（UnitName 不可用）→ 请改用 /eh go 链接探针 队伍（需在队伍里）")
      return false
    end
  end
  return shTxEnqueue(bodies, chanId, target)
end
-- 探针 ①：发 4 种形态（默认密语自己：单机可测、不扰民）
function EVAL_SHARE_LINK_PROBE(chanId)
  chanId = (type(chanId) == "string" and chanId ~= "") and chanId or "WHISPER"
  local prefix = "be" .. shProbeRandomTag()
  local forms = shProbeForms(prefix)
  SH_PROBE.sent = forms
  if not EVAL_SHARE_PROBE_ARM("link", prefix) then return false end
  local bodies = {}
  for i = 1, table.getn(forms) do table.insert(bodies, forms[i].body) end
  local ok = shProbeSend(bodies, chanId)
  shSay("链接转发探针已发出（" .. tostring(chanId) .. "，限频队列约 " .. tostring(table.getn(bodies)) .. " 秒发完）：")
  for i = 1, table.getn(forms) do
    shSay("  " .. forms[i].label .. "  " .. tostring(string.len(forms[i].body)) .. " 字节")
  end
  shSay("  ★等 2~3 秒 → /eh go 探针结果（把整段结果贴给我）；★同时看一眼聊天框：哪一种显示成了短文字")
  return ok and true or false
end
-- 探针 ②：发长度阶梯
function EVAL_SHARE_LEN_PROBE(chanId, ladder)
  chanId = (type(chanId) == "string" and chanId ~= "") and chanId or "WHISPER"
  local prefix = "la" .. shProbeRandomTag()
  local rows = shProbeLadder(prefix, ladder)
  SH_PROBE.ladderSent = rows
  if not EVAL_SHARE_PROBE_ARM("len", prefix) then return false end
  local bodies = {}
  for i = 1, table.getn(rows) do table.insert(bodies, rows[i].body) end
  local ok = shProbeSend(bodies, chanId)
  shSay("长度阶梯探针已发出（" .. tostring(chanId) .. "）：目标 " .. tostring(table.getn(rows)) .. " 档")
  shSay("  ★等 3 秒 → /eh go 探针结果（看每档「收到多少字节 / 尾部哨兵在不在」）")
  return ok and true or false
end
-- 逐字节比对（返回首个不同处的字节位；完全相同返回 nil）
local function shProbeDiff(a, b)
  a, b = tostring(a), tostring(b)
  local n = math.min(string.len(a), string.len(b))
  for k = 1, n do if string.byte(a, k) ~= string.byte(b, k) then return k end end
  if string.len(a) ~= string.len(b) then return n + 1 end
  return nil
end
local function shProbeFind(mode, tag)
  local list = (SH_PROBE.recv or {})[mode] or {}
  for i = 1, table.getn(list) do
    if string.find(tostring(list[i].raw or ""), tostring(tag), 1, true) then return list[i] end
  end
  return nil
end
-- 方案名（显示用）：取导出文本首行 `# 方案: 名` 里的「名」；解析不出就退回「方案」
-- ===== 1.73.42 分享显示行：境界 · 品阶 · 评语（用户 2026-09-19 定稿）==================
-- 行格式：`<头衔色>[<头衔>]|r<角色名> 分享了 → <品阶色>[<品阶>秘籍·<方案名>]|r  <评语>`
--   ★★★1.73.42n 用户 2026-09-19 定稿（**头衔抽卡**替代了原来的「境界/档位名」）：
--     ① 档位数量 = **方案稀有度档数（5 档）**，不再按角色等级划分（等级那套逻辑全部下线）；
--     ② 晋升依据 = **方案库里各稀有度的数量**（达要求即晋升），**只升不降**；
--     ③ 每档 15 张卡池，**每档只抽一次**、不重复抽、抽到**唯一不变**（写进存档）；
--     ④ 预留彩蛋「创世神的关注」：可**一次性**自定义头衔，优先度最高（触发机制以后再接）。
--   品阶 = **技能条数 + 每条技能里的条件数**（评分制）：≤6 普通 / 7-12 稀有 / 13-18 珍稀 / 19-24 绝版 / **≥25 神级**；
--   ★★★1.73.61 用户：「品阶计算 25 以上算神级，其他依次调整下」——原来的四档都是 3 分宽（≤3/6/9/12），
--     神级门槛只比绝版高 1 分（13）⇒ 现在按**同一个宽度**重排（每档 6 分宽，24 封顶）再留 25+ 给神级；
--     ★判据把**每一个边界的两侧**都钉死（6/7 · 12/13 · 18/19 · 24/25），改阈值时漏一处当场响。
--   颜色：白 |cffffffff · 绿 |cff1eff00 · 紫 |cffa335ee · 橙 |cffff8000 · **深红 |cffc00000**（用户 1.73.60 定的 —— 原为亮蓝 00bfff，再之前是暗金 b87333）；
--   评语：每档 **10 条**（用户要求），分享时**随机抽一条**。
-- ★★★1.73.42j 这些表只存**结构 + 键**，文案一律走 Locales（L()）：文案散在源码里 = 换语言时不生效。
local SH_SEAL_TIERS = {
  { max = 6,  key = "SEAL_TIER_1", color = "|cffffffff" }, -- ★1.73.61 用户定：神级 = 25+，其余四档按同一宽度重排（每档 6 分）
  { max = 12,  key = "SEAL_TIER_2", color = "|cff1eff00" },
  { max = 18,  key = "SEAL_TIER_3", color = "|cffa335ee" },
  { max = 24,  key = "SEAL_TIER_4", color = "|cffff8000" },
  { max = 9999, key = "SEAL_TIER_5", color = "|cffc00000" }, -- ★★★1.73.60 用户：「方案品阶: 源代码 调整->神级 颜色深红」（亮蓝 00bfff → 深红 c00000）
}
local SH_SEAL_COMMENTS = {
  { "SEAL_C1_1", "SEAL_C1_2", "SEAL_C1_3", "SEAL_C1_4", "SEAL_C1_5", "SEAL_C1_6", "SEAL_C1_7", "SEAL_C1_8", "SEAL_C1_9", "SEAL_C1_10" },
  { "SEAL_C2_1", "SEAL_C2_2", "SEAL_C2_3", "SEAL_C2_4", "SEAL_C2_5", "SEAL_C2_6", "SEAL_C2_7", "SEAL_C2_8", "SEAL_C2_9", "SEAL_C2_10" },
  { "SEAL_C3_1", "SEAL_C3_2", "SEAL_C3_3", "SEAL_C3_4", "SEAL_C3_5", "SEAL_C3_6", "SEAL_C3_7", "SEAL_C3_8", "SEAL_C3_9", "SEAL_C3_10" },
  { "SEAL_C4_1", "SEAL_C4_2", "SEAL_C4_3", "SEAL_C4_4", "SEAL_C4_5", "SEAL_C4_6", "SEAL_C4_7", "SEAL_C4_8", "SEAL_C4_9", "SEAL_C4_10" },
  { "SEAL_C5_1", "SEAL_C5_2", "SEAL_C5_3", "SEAL_C5_4", "SEAL_C5_5", "SEAL_C5_6", "SEAL_C5_7", "SEAL_C5_8", "SEAL_C5_9", "SEAL_C5_10" },
}
-- ★★★1.73.42o **符号必须落在客户端字体真的有的区块**（用户真机反馈：「字符图标,珍稀,神级级别没生效」）——
--   实测：`·`(U+00B7) `◆`(U+25C6) `★`(U+2605) 都画得出来，而 `✦`(U+2726) `✸`(U+2738) **一个像素都不显示**
--   （它们属于 Dingbats 块 U+2700–U+27BF，本客户端字体没带这半边）。⇒ 五档只用**已实测可渲染**的区块：
--   Latin-1 补充 + Geometric Shapes（U+25A0–U+25FF）+ Miscellaneous Symbols（U+2600–U+26FF）。
--   阶梯按视觉分量递增：点 → 菱 → 方 → 圆 → 星（星是所有人都认得的「最好」）。
--   ★不许再用 Dingbats 花体字形；改这里务必先进游戏看一眼（源码检查 SEAL SYMBOL CHECK 只挡得住那一个块）。
local SH_SEAL_SYMBOLS = { "·", "◆", "■", "●", "★" }
-- ★★★1.73.42n 头衔的颜色 = **冷色系**（与品阶的暖色稀有度系**逐个不相等**，有判据守着）：
--   为什么必须错开：品阶用白/绿/紫/橙/深红；头衔若也用它，同一行里「[大元帅]」和「[神级秘籍]」
--   会看起来是同一档东西，**两个维度糊在一起**。
--   1 档 青灰 |cff8fa8b8 · 2 档 青 |cff00e5ff · 3 档 蓝 |cff4f9bff · 4 档 品红 |cffff4fd8 · 5 档 极光青绿 |cff5cffd2。
--   ★色码必须 8 位（`|c` + AARRGGBB）：6 位本客户端**不解析**，会把色码原文画进聊天（1.73.19 实测）。
local SH_TITLE_COLORS = { "|cff8fa8b8", "|cff00e5ff", "|cff4f9bff", "|cffff4fd8", "|cff5cffd2" }
-- ★★★1.73.45 彩蛋自定义名号的**默认色 = 烈焰赤**（原 1.73.42p 的淡金 |cfffff2c8 太素 —— 用户要求「霸气一点」，
--   并在候选里**选定「烈焰赤」**）。
--   ★颜色是主观偏好 ⇒ 顺带给**候选表 + 命令**：/eh go 名号色 把候选**各发一条编号预览**（真形态、真颜色），
--     /eh go 名号色 <编号> 当场选用并**存档**（cfg.title.customColor）—— 免得为了「霸气一点」来回改版。
--   ★候选一律**避开**品阶五档（白/绿/紫/橙/深红）与头衔五档（青灰/青/蓝/品红/青绿）：同屏不糊成一团（源码检查守着）。
--   ★顺序 = 默认（候选 1 即默认，单一来源）：改默认**只改顺序/第 1 项**，别的都不用动。
local SH_TITLE_CUSTOM_COLORS = {
  { code = "|cffff2400", key = "TC_FLAME" },  -- 1 烈焰赤（默认 —— 用户选定）
  { code = "|cffffd700", key = "TC_GOLD" },   -- 2 帝王金
  { code = "|cffdc143c", key = "TC_BLOOD" },  -- 3 龙血赤
  { code = "|cffb22222", key = "TC_DARK" },   -- 4 暗血赤
  { code = "|cffff8c00", key = "TC_MOLTEN" }, -- 5 熔金橙
}
-- ★单一来源：默认色**就是候选表第 1 项**（改候选表即改默认，永远对齐）
local SH_TITLE_CUSTOM_COLOR = SH_TITLE_CUSTOM_COLORS[1].code
-- 有效色（**渲染 / 分享 / 命令 / 断言都走这一个读值口**）：玩家选过且形态合法 → 用玩家的；否则用默认。
--   ★只认 8 位色码（|cAARRGGBB）：存档被手改成 6/7 位时**不许照发**（非 8 位客户端会整条吞消息，1.73.43e 实测）。
local function shTitleCustomColor()
  local cfgC = rawget(_G, "EVAL_HELP_CONFIG")
  local v = (type(cfgC) == "table" and type(cfgC.title) == "table") and cfgC.title.customColor or nil
  if type(v) == "string" and string.match(v, "^|c%x%x%x%x%x%x%x%x$") ~= nil then return v end
  return SH_TITLE_CUSTOM_COLOR
end
-- ===== 1.73.42n 头衔抽卡（用户 2026-09-19 定稿）==========================================
--   用户原话：「每个档位只抽卡一次.不重复抽卡.唯一不变.」+「档位可以和方案的档位数量相同. 每个档位卡池…15 个」
--     +「根据用户当前方案稀有度的数量, 达成档位的需求就晋升档位. 当我只升不降.」
--   ① 5 档（= 方案稀有度档数：普通/稀有/珍稀/绝版/神级）· 每档 15 张卡 · 全部是**头衔**（无人名）；
--   ② 晋升看**方案库里各稀有度的数量**（只升不降）；③ 每档**只抽一次**，抽到写进存档、**唯一不变**。
local SH_TITLES = {
  { "TITLE_1_1", "TITLE_1_2", "TITLE_1_3", "TITLE_1_4", "TITLE_1_5", "TITLE_1_6", "TITLE_1_7", "TITLE_1_8", "TITLE_1_9", "TITLE_1_10", "TITLE_1_11", "TITLE_1_12", "TITLE_1_13", "TITLE_1_14", "TITLE_1_15" },
  { "TITLE_2_1", "TITLE_2_2", "TITLE_2_3", "TITLE_2_4", "TITLE_2_5", "TITLE_2_6", "TITLE_2_7", "TITLE_2_8", "TITLE_2_9", "TITLE_2_10", "TITLE_2_11", "TITLE_2_12", "TITLE_2_13", "TITLE_2_14", "TITLE_2_15" },
  { "TITLE_3_1", "TITLE_3_2", "TITLE_3_3", "TITLE_3_4", "TITLE_3_5", "TITLE_3_6", "TITLE_3_7", "TITLE_3_8", "TITLE_3_9", "TITLE_3_10", "TITLE_3_11", "TITLE_3_12", "TITLE_3_13", "TITLE_3_14", "TITLE_3_15" },
  { "TITLE_4_1", "TITLE_4_2", "TITLE_4_3", "TITLE_4_4", "TITLE_4_5", "TITLE_4_6", "TITLE_4_7", "TITLE_4_8", "TITLE_4_9", "TITLE_4_10", "TITLE_4_11", "TITLE_4_12", "TITLE_4_13", "TITLE_4_14", "TITLE_4_15" },
  { "TITLE_5_1", "TITLE_5_2", "TITLE_5_3", "TITLE_5_4", "TITLE_5_5", "TITLE_5_6", "TITLE_5_7", "TITLE_5_8", "TITLE_5_9", "TITLE_5_10", "TITLE_5_11", "TITLE_5_12", "TITLE_5_13", "TITLE_5_14", "TITLE_5_15" },
}
-- 每档卡池张数 / 取键（越界一律夹到合法范围，绝不返回 nil 让上层炸）
function EVAL_TITLE_TIER_COUNT() return table.getn(SH_TITLES) end
function EVAL_TITLE_COUNT(tier)
  local list = SH_TITLES[tonumber(tier) or 1]
  return table.getn(list or {})
end
function EVAL_TITLE_KEY(tier, idx)
  local ti = tonumber(tier) or 1
  if ti < 1 then ti = 1 end
  if ti > table.getn(SH_TITLES) then ti = table.getn(SH_TITLES) end
  local list = SH_TITLES[ti]
  local n = table.getn(list)
  local k = tonumber(idx) or 1
  if k < 1 then k = 1 end
  if k > n then k = n end
  return list[k], ti, k
end
-- 方案表 → 评分（技能条数 + 条件数）：与品阶判定**同一套**（品阶与晋升档都用它，绝不各写一遍）
function EVAL_PROFILE_SCORE(prof)
  if type(prof) ~= "table" or type(prof.skills) ~= "table" then return 0 end
  local score = table.getn(prof.skills)
  for i = 1, table.getn(prof.skills) do
    local gs = prof.skills[i] and prof.skills[i].groups
    for g = 1, table.getn(gs or {}) do score = score + table.getn(gs[g] or {}) end
  end
  return score
end
-- 方案库 → 各稀有度数量（{ 普通, 稀有, 珍稀, 绝版, 神级 }）
function EVAL_TITLE_COUNTS()
  local out = { 0, 0, 0, 0, 0 }
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  local profs = cfgT and cfgT.war and cfgT.war.profiles
  if type(profs) ~= "table" then return out end
  for _, p in pairs(profs) do
    if type(p) == "table" then
      local idx = select(1, EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p)))
      if idx >= 1 and idx <= 5 then out[idx] = out[idx] + 1 end
    end
  end
  return out
end
-- 「稀有度 ≥ k」的方案总数
function EVAL_TITLE_GE(counts, k)
  local ge = 0
  counts = counts or {}
  for i = tonumber(k) or 1, 5 do ge = ge + (tonumber(counts[i]) or 0) end
  return ge
end
-- ★晋升判定（纯函数，判据直接喂数量进来看结果）：
--   1 档 = 有 ≥1 个方案；2 档 = 稀有及以上 ≥1；3 档 = 珍稀及以上 ≥1；4 档 = 绝版及以上 ≥1；5 档 = 神级 ≥1。
--   只升不降 ⇒ 调用方只往**更高**记（见 EVAL_TITLE_REFRESH）。
function EVAL_TITLE_TIER_FROM_COUNTS(counts)
  if EVAL_TITLE_GE(counts, 1) < 1 then return 0 end -- 一个方案都没有 → 还没入档
  local at = 1
  for i = 2, 5 do
    if EVAL_TITLE_GE(counts, i) >= 1 then at = i end
  end
  return at
end
-- 存档态（cfg.title）：tier = 已到的最高档；draws[档] = 抽到的序号；custom = 彩蛋自定义头衔
local function shTitleState()
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgT) ~= "table" then return nil end
  if type(cfgT.title) ~= "table" then cfgT.title = { tier = 0, draws = {} } end
  local t = cfgT.title
  if type(t.draws) ~= "table" then t.draws = {} end
  t.tier = tonumber(t.tier) or 0
  if t.tier < 0 then t.tier = 0 end
  return t
end
-- ★★★重新统计方案库并**对新达到的档各抽一次**（只升不降；已抽过的档**绝不重抽**）
function EVAL_TITLE_REFRESH()
  local t = shTitleState()
  if not t then return 0 end
  local counts = EVAL_TITLE_COUNTS()
  local reach = EVAL_TITLE_TIER_FROM_COUNTS(counts)
  t.counts = counts
  if reach > t.tier then
    for k = t.tier + 1, reach do
      -- ★「每个档位只抽卡一次」：抽过就保留原值（存档里已有 → 跳过），永不重抽、永不改写
      if t.draws[k] == nil then t.draws[k] = math.random(1, EVAL_TITLE_COUNT(k)) end
    end
    t.tier = reach
    t.at = shNowT()
  end
  return t.tier
end
-- 当前头衔（**彩蛋自定义优先度最高**）：没入档且没自定义 → 如实 nil（不编一个头衔出来）
function EVAL_TITLE_CURRENT()
  local t = shTitleState()
  if not t then return nil end
  local custom = nil
  if type(t.custom) == "string" and t.custom ~= "" then custom = t.custom end
  local tier = tonumber(t.tier) or 0
  if tier < 1 then
    if custom then return { tier = 0, name = custom, color = shTitleCustomColor(), custom = true } end
    return nil
  end
  local idx = tonumber(t.draws and t.draws[tier])
  local key, ti, k = EVAL_TITLE_KEY(tier, idx)
  local name, isCustom = L(key), false
  if custom then name, isCustom = custom, true end
  return { tier = ti, idx = (not isCustom) and k or nil, key = (not isCustom) and key or nil,
           name = name, color = isCustom and shTitleCustomColor() or (SH_TITLE_COLORS[ti] or SH_TITLE_COLORS[1]), custom = isCustom,
           counts = t.counts, at = t.at }
end
-- 按**名字**回找头衔（接收端只有封皮行里的文字）：返回档位与颜色；不是我们发的头衔（或对方是彩蛋自定义）
--   → 返回 nil，调用方用中性色显示原文（不猜档位、不编颜色）
function EVAL_TITLE_LOOKUP(name)
  local want = tostring(name or "")
  if want == "" then return nil end
  for ti = 1, table.getn(SH_TITLES) do
    local list = SH_TITLES[ti]
    for k = 1, table.getn(list) do
      if L(list[k]) == want then
        return { tier = ti, idx = k, key = list[k], color = SH_TITLE_COLORS[ti] or SH_TITLE_COLORS[1], name = want }
      end
    end
  end
  return nil
end
-- 距下一档还差什么（命令用）：
--   ★基准是**已到的档**（存档里的最高档，只升不降），不是「当前方案库算出来的档」——
--     否则玩家把方案删了之后会被提示「还差 1 个方案到 1 档」，与「只升不降」自相矛盾。
--   下一档要求 = 「稀有度 ≥ 下一档」的方案至少 1 个（have/need 如实交出来，命令里照实说）。
function EVAL_TITLE_PROGRESS()
  local counts = EVAL_TITLE_COUNTS()
  local t = shTitleState()
  local saved = (t and tonumber(t.tier)) or 0
  local out = { tier = saved, reach = EVAL_TITLE_TIER_FROM_COUNTS(counts), counts = counts, nextTier = nil, need = 0, have = 0 }
  if saved < table.getn(SH_TITLES) then
    out.nextTier = saved + 1
    out.have = EVAL_TITLE_GE(counts, out.nextTier)
    out.need = 1
  end
  return out
end
-- ★★★1.73.42n 彩蛋预留（用户：「之后会增加个彩蛋：玩家在编写方案达到一定机制.触发创世神的关注.
--   「可以有一次自定义弹窗修改这个头衔的机会. 这个自定义头像优先度最高. 并且只有一次修改机会.」）：
--   **触发机制以后再接**，这里只落两件硬事实：① 自定义头衔显示时压过抽到的卡；② **只有一次**（写入后再调一律拒绝）。
function EVAL_TITLE_SET_CUSTOM(name)
  local t = shTitleState()
  if not t then return false end
  if type(t.custom) == "string" and t.custom ~= "" then return false end -- ★只有一次：用过就拒绝
  name = tostring(name or "")
  name = string.gsub(name, "|", "") -- 竖线会破坏聊天行（分享行同样过滤）
  name = string.gsub(name, "^%s+", "")
  name = string.gsub(name, "%s+$", "")
  if name == "" then return false end
  if string.len(name) > 36 then name = string.sub(name, 1, 36) end -- 12 汉字：别把聊天行撑爆
  t.custom = name
  t.customAt = shNowT()
  return true
end
-- ★★★1.73.42r 重置（用户：「给我一个重置删除自定义的命令.测试」）——**只给命令用**（诊断/测试），
--   正常玩法里没有这条路：彩蛋一旦落笔就不可改（EVAL_TITLE_SET_CUSTOM 的「只有一次」守卫仍然生效）。
--   ★为什么要它：想再看一遍弹窗 / 想重新抽一次手气，必须能回到干净状态，否则测一次就废一个号。
function EVAL_TITLE_RESET_ALL()
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgT) ~= "table" then return false end
  cfgT.title = { tier = 0, draws = {} } -- ★档位与五档抽取记录一起清（下次重算会重新抽）
  return true
end
-- 诊断/测试用（游戏里没有「清空彩蛋」这条路：只有一次机会）
function EVAL_TITLE_CLEAR_CUSTOM()
  local t = shTitleState()
  if not t then return false end
  t.custom, t.customAt = nil, nil
  return true
end
-- 测试读值口：把存档里的原始状态交出来（判据读它，不读我们自己拼的显示串）
function EVAL_TITLE_STATE()
  local t = shTitleState()
  if not t then return nil end
  return { tier = t.tier, draws = t.draws, custom = t.custom, counts = t.counts, at = t.at }
end
-- 样例命令用：5 档各挑第 1 张，做成「示例分享行」（不碰存档）
function EVAL_TITLE_DEMO_LINES()
  local out = {}
  for ti = 1, table.getn(SH_TITLES) do
    local key = EVAL_TITLE_KEY(ti, 1)
    local col = SH_TITLE_COLORS[ti] or SH_TITLE_COLORS[1]
    table.insert(out, col .. "[" .. L(key) .. "]|r " .. SH_SEAL_SYMBOLS[ti] .. "[" .. L(SH_SEAL_TIERS[ti].key) .. "]")
  end
  return out
end
-- 评分 = 技能条数 + 技能内每个条件（★复用项目**同一个**导入解析器与**同一个**评分函数，不另写一套）
function EVAL_SHARE_SEAL_SCORE(text)
  if type(EVAL_PROFILE_FROM_TEXT) ~= "function" then return nil end -- 解析器不在 → 如实返回 nil（不假装算得出）
  local p = EVAL_PROFILE_FROM_TEXT(tostring(text or ""))
  if type(p) ~= "table" or type(p.skills) ~= "table" then return nil end
  return EVAL_PROFILE_SCORE(p)
end
function EVAL_SHARE_SEAL_TIER(score)
  score = tonumber(score) or 0
  local pick = table.getn(SH_SEAL_TIERS)
  for i = 1, table.getn(SH_SEAL_TIERS) do
    if score <= SH_SEAL_TIERS[i].max then pick = i break end
  end
  local t = SH_SEAL_TIERS[pick]
  -- ★返回**当场按当前语言解析**的副本：调用方（分享行/弹窗品阶栏/模版 tooltip）照旧读 .name/.color/.max，
  --   而语言在配置窗里能随时切 —— 缓存一份 name 会出现「切了语言还是旧文案」的静默不一致。
  return pick, { max = t.max, key = t.key, color = t.color, name = L(t.key) }
end
function EVAL_SHARE_SEAL_COMMENT(tierIdx, forced)
  local list = SH_SEAL_COMMENTS[tierIdx]
  if type(list) ~= "table" then return "" end
  local n = table.getn(list)
  local i = tonumber(forced) or math.random(1, n)
  if i < 1 or i > n then i = 1 end
  return L(list[i]), i
end
-- ★★★1.73.42i 详情弹窗「品阶栏」的**单一读值口**（渲染与断言同源，纯函数）。
--   ★分成两半，各自的诚实边界写死在返回值里（meta 为 nil 时就是「未知」三个字的来源）：
--     ① 品阶/评分/图标/符号/方案名：由**收到的方案文本**复算 —— 品阶本来就是方案的函数，接收端能独立算出来；
--     ② **身份（头衔）**：它是**抽卡结果**、是发送者的私人收藏 → 接收端**复现不了**，
--        只能以封皮行带来的为准（封皮里第一个方括号就是它）；没收到封皮行 → 如实「未知」。
--     ③ 评语：只有发送端知道（封皮行解析来的 meta）→ 拿不到就如实写「未知（未收到封皮行）」。
--   ★返回 nil 的唯一情形：文本解析不出方案（那就别画品阶栏，而不是随便给一档）。
function EVAL_SHARE_SEAL_ROW(text, meta)
  local score = EVAL_SHARE_SEAL_SCORE(text)
  if score == nil then return nil end
  local idx, tier = EVAL_SHARE_SEAL_TIER(score)
  local icon = EVAL_SHARE_SEAL_ICON(idx)
  local sym = EVAL_SHARE_SEAL_SYMBOL(idx)
  local plan = shSealName(text or "")
  -- ★1.73.42n 身份 = 封皮行里的头衔；能对上我们 75 张卡的，用**那一档的颜色**；
  --   对不上（对方档位更高/用了彩蛋自定义/版本不同）→ 中性色显示原文，**不猜档位、不编颜色**。
  local rank, rankColor, rankFrom = nil, nil, nil
  if type(meta) == "table" and type(meta.rank) == "string" and meta.rank ~= "" then
    rank, rankFrom = meta.rank, "seal"
    -- ★1.73.42o 颜色优先取**封皮行里发送端自带的那个**（纯文本传递，连彩蛋自定义头衔也照抄）；
    --   老版本封皮没带色码时才按名字反查我们那 75 张；再查不到 → 中性色显示原文（绝不显示成空白）。
    if type(meta.rankColor) == "string" and string.len(meta.rankColor) == 10 then
      rankColor, rankFrom = meta.rankColor, "seal-color"
    else
      local look = EVAL_TITLE_LOOKUP(rank)
      rankColor = look and look.color or "|cff8fa8b8"
    end
  end
  local comment = (type(meta) == "table") and meta.comment or nil
  local rankTxt = "未知（未收到封皮行）"
  if rank then rankTxt = tostring(rankColor) .. rank .. "|r" end
  local cmtTxt = "未知（未收到封皮行）"
  if type(comment) == "string" and comment ~= "" then cmtTxt = comment end
  return {
    tier = idx, tierName = tier.name, color = tier.color, symbol = sym, score = score,
    icon = icon, plan = plan, comment = comment,
    rank = rank, rankColor = rankColor, rankFrom = rankFrom,
    head = tier.color .. sym .. "[" .. tier.name .. "秘籍·" .. plan .. "]|r",
    meta = "品阶：" .. tier.name .. "（评分 " .. tostring(score) .. "）· 身份：" .. rankTxt,
    commentLine = "评语：" .. cmtTxt,
  }
end
-- 读值口：把一行显示内容算出来（测试与 /eh go 秘籍 预览共用；forcedIdx 只给测试用）
function EVAL_SHARE_SEAL_INFO(text, level, forcedIdx)
  local score = EVAL_SHARE_SEAL_SCORE(text)
  if score == nil then return nil end -- 算不出就如实 nil
  local idx, tier = EVAL_SHARE_SEAL_TIER(score)
  local comment, ci = EVAL_SHARE_SEAL_COMMENT(idx, forcedIdx)
  -- ★★★1.73.42n 头衔（抽卡身份）：先**按方案库重新统计 + 抽卡**（只升不降；已抽过的档绝不重抽），
  --   再取当前最高档的头衔。★头衔是**私人收藏** → 接收端复现不了，对面看到的以封皮行为准。
  --   ★一个方案都没有（还没入档）时**不编头衔**：整行不带方括号身份，如实从角色名开始。
  --   `level` 形参保留只为兼容老调用点（档位**不再**看等级，用户已明确）。
  EVAL_TITLE_REFRESH()
  local tt = EVAL_TITLE_CURRENT()
  local who = (type(UnitName) == "function") and UnitName("player") or "?"
  local name = shSealName(text or "")
  -- ★两个色码：头衔各档一色（与品阶色系不撞）；品阶色包住整个方括号（`[品阶秘籍·名]` 能被文字直接搜到）
  local sym = SH_SEAL_SYMBOLS[idx] or SH_SEAL_SYMBOLS[1]
  local idPart = ""
  if tt then idPart = tt.color .. "[" .. tt.name .. "]|r" end
  local line = idPart .. tostring(who) .. " 分享了 → " .. tier.color .. sym ..
               "[" .. tier.name .. "秘籍·" .. name .. "]|r  " .. comment
  return { score = score, tier = idx, tierName = tier.name, color = tier.color,
           title = tt, titleTier = tt and tt.tier or 0, titleName = tt and tt.name or nil,
           titleCustom = tt and tt.custom or false,
           comment = comment, commentIdx = ci, plan = name, line = line, symbol = sym }
end
-- ★1.73.42b 用户要求：「添加一个测试命令，输入所有类型的分享案例」
--   1.73.42n 起：**5 品阶分享行 + 5 档头衔示意行 = 10 行**（原来的「7 境界」是等级派生的，已下线）
--   目的：不用造真方案，就能一眼看全所有品阶与头衔档位的显示效果（含颜色与评语）
function EVAL_SHARE_SEAL_DEMO()
  local plan = (type(EVAL_PROFILE_TO_TEXT) == "function") and EVAL_PROFILE_TO_TEXT() or "# 方案: 样例"
  local base = "# 方案: " .. shSealName(plan)
  -- ★★★1.73.42k 等级**写进方案文本**（`- 技能1(60)`）：境界现在取自「方案里最大的技能等级」，
  --   所以在形参里传 level 已经不作数了——样例要能让 7 档境界真的各出现一次，就必须把等级写进方案。
  local function mk(n, lv)
    local s = base
    for k = 1, n do s = s .. "\n- 技能" .. k .. (lv and ("(" .. tostring(lv) .. ")") or "") end
    return s
  end
  -- ★1.73.61 每档取**档内中点**（≤6 / 7-12 / 13-18 / 19-24 / ≥25）——阈值改了这一行必须跟着改（否则样例串档）
  local reps = { 3, 9, 15, 21, 26 }
  local lines = {}
  for i = 1, table.getn(reps) do -- 5 品阶的分享行（身份就是**你当前的头衔**）
    local info = EVAL_SHARE_SEAL_INFO(mk(reps[i], 60), 60, i)
    if info then table.insert(lines, info.line) end
  end
  -- ★1.73.42n 再给 5 档头衔示意（每档第 1 张卡；不碰存档）——原来那 7 行「境界」是等级派生的，已下线
  local titleDemo = EVAL_TITLE_DEMO_LINES()
  for i = 1, table.getn(titleDemo) do table.insert(lines, titleDemo[i]) end
  -- ★★★1.73.42f 判据用的「证人」：把「跑了没 / 跑了几行」写进存档
  --   （上一轮 M336 实测：用聊天「含子串」判接线 → 被前一段输出顶住、断言假绿）
  local cfgD = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgD) == "table" then
    cfgD.shareSealDemo = { n = table.getn(lines), at = (type(GetTime) == "function") and GetTime() or 0 }
  end
  shSay("===== 秘籍样例（5 品阶分享行 + 5 档头衔示意，共 " .. tostring(table.getn(lines)) .. " 行）=====")
  for i = 1, table.getn(lines) do shSay("  " .. lines[i]) end
  return table.getn(lines)
end

-- ===== 1.73.44 「色码测」：把**分享真正会发到聊天的每一个色码**各发一条，实测哪个画不出来 ==========
-- 用户要求：「将现在所使用的所有颜色色码都测试下」。
-- 为什么值得做成命令（客户端对色码的口径很窄，而且**三种坑的症状完全不同**）：
--   ① 非 8 位色码（如 7 位）→ **整条消息被吞**（1.73.43e 真机定案）；
--   ② 一条消息里塞多段色码 → **整条被吞**（1.73.43h 真机定案）；
--   ③ 有色码但**不带链接** → 这条**不画**（1.73.43p 真机定案）。
--   ⇒ 色表（品阶 5 档 / 头衔 5 档 / 彩蛋专属色 / 分片传输色）**每次改动都该跑一次这个命令实测**，
--     而不是等玩家分享出去才发现少了一行（这三种坑都不报错，只是消息不见了）。
-- ★★列表**从色表实时生成、不手抄**：改了色表这个命令自动跟着变 —— 不写死就不会漏测（源码检查守这条）。
-- ★每条只放**一段色码**、带链接、色码打头（= 1.73.43p 验证过能画的形态），间隔 ≥1 秒（与分享同一条限频队列）。
function EVAL_SHARE_CHUNK_COLOR() return SH_CHUNK_COLOR end -- 读值口：色码测与断言同源

function EVAL_SHARE_COLOR_PROBE()
  local list = {}
  table.insert(list, { code = SH_CHUNK_COLOR, label = "分片传输色" })
  for i = 1, table.getn(SH_SEAL_TIERS) do
    local t = SH_SEAL_TIERS[i]
    table.insert(list, { code = t.color, label = "品阶" .. tostring(i) .. "·" .. L(t.key) })
  end
  for i = 1, table.getn(SH_TITLE_COLORS) do
    local nm = "头衔" .. tostring(i)
    if type(EVAL_TITLE_KEY) == "function" then
      local k = EVAL_TITLE_KEY(i, 1)
      if type(k) == "string" and k ~= "" then nm = nm .. "·" .. L(k) end
    end
    table.insert(list, { code = SH_TITLE_COLORS[i], label = nm })
  end
  table.insert(list, { code = shTitleCustomColor(), label = "彩蛋·自定义名号" })
  local n = table.getn(list)
  local bodies = {}
  for i = 1, n do
    local e = list[i]
    local idh = string.format("c0%02x", i)
    local body = e.code .. "|HEHPF:" .. idh .. " 0/1:0|h[色码测" .. tostring(i) .. "]|h|r  " .. tostring(e.label)
    if string.len(body) > SH_MSG_MAX then -- 长度守卫（与分享同规矩：超了先砍描述，绝不发会被丢的超长消息）
      body = e.code .. "|HEHPF:" .. idh .. " 0/1:0|h[" .. tostring(i) .. "]|h|r"
    end
    if string.len(body) > SH_MSG_MAX then body = nil end
    e.body = body
    table.insert(bodies, body or "")
    if body then table.insert(shTxQ, { body = body, chan = "SAY" }) end
  end
  shTxLast = shNowT()
  shEnsureTxTicker()
  local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgP) == "table" then cfgP.shColorProbe = { n = n, list = bodies, at = shNowT() } end -- ★落盘证人
  shSay("===== 色码测（" .. tostring(n) .. " 条，已排队到「说」频道）=====")
  shSay("  每条间隔 1 秒（★跑完请**等 30 秒以上**再跑第二次，期间别再分享/发言 —— 短时间多条会被吞，结果不可信）")
  shSay("  请把**实际出现的编号**告诉我（没出现的同样重要）")
  for i = 1, n do
    shSay("  [" .. tostring(i) .. "] " .. shRawForPrint(list[i].code) .. "  " .. tostring(list[i].label))
  end
  return { n = n, list = list, bodies = bodies, at = shNowT() }
end

-- ===== 1.73.42p 「创世者亲临」彩蛋窗口 ==================================================
--   用户要求：「先提供个命令.让我能触发创世神的关注…（名字）能体现位格.霸气. 然后弹窗内的文字美化一下.霸气一下.」
--   ★命名：**创世者亲临**（备选：本源垂青 / 造物主之约 / 万法之源的注视）——位格=创世者，动作=亲临，
--     文案全部走 Locales（CREATOR_*），改文案不用动代码。
--   ★触发机制以后再接（「写方案达到一定机制」）；现在先给命令 `/eh go 创世` 手动触发，玩家先看效果。
--   ★窗口配方照本项目弹窗规范：DIALOG + **明确 frame level 210**（高于分享弹窗 140 / 名称弹窗 130）+
--     EnableMouse + 可拖动 + 越界回归；EditBox 在本客户端**可能不渲染** → 必有**金色回声行**保底（1.15.1 教训）。
local shCreator = { root = nil }
function EVAL_TITLE_CUSTOM_COLOR() return shTitleCustomColor() end
-- ★★★1.73.45 「名号色」命令（用户：「彩蛋头衔 颜色设置霸气一点」）
--   ① /eh go 名号色 → 把候选色**各发一条编号预览**到「说」（形态与分享行同款：色码打头 + 链接 + [名号]|h|r + 说明）：
--      预览方括号里就是**玩家自己的名号**，看到什么就是分享出去的样子；
--   ② /eh go 名号色 <编号> → 当场选用并存档（cfg.title.customColor），立刻生效、重登仍在。
--   ★为什么给候选而不是直接改死：颜色是主观偏好，一次摊开让玩家自己挑，比「再霸气一点」来回改版快得多
--     （本项目已在「够不够亮 / 看不看得见」上往返好几轮）。候选一律**避开品阶与头衔五档**（源码检查守着）。
function EVAL_TITLE_CUSTOM_COLOR_LIST()
  local out = {}
  for i = 1, table.getn(SH_TITLE_CUSTOM_COLORS) do
    local e = SH_TITLE_CUSTOM_COLORS[i]
    out[i] = { n = i, code = e.code, key = e.key, name = L(e.key), current = (e.code == shTitleCustomColor()) }
  end
  return out
end
-- 选用：只认候选表里的编号（越界/非数字**如实返回 nil**，绝不悄悄改成默认）
function EVAL_TITLE_SET_CUSTOM_COLOR(n)
  n = tonumber(n)
  if not n or n < 1 or n > table.getn(SH_TITLE_CUSTOM_COLORS) then return nil end
  local cfgS = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgS) ~= "table" then return nil end
  cfgS.title = cfgS.title or {}
  cfgS.title.customColor = SH_TITLE_CUSTOM_COLORS[n].code
  return cfgS.title.customColor
end
function EVAL_SHARE_TITLE_COLOR_PROBE()
  local list = EVAL_TITLE_CUSTOM_COLOR_LIST()
  local n = table.getn(list)
  -- 预览标签 = **玩家自己的名号**（没有自定义名号就用抽到的那个；都没有才用中性示例名）
  local who = L("TC_SAMPLE")
  local cur = (type(EVAL_TITLE_CURRENT) == "function") and EVAL_TITLE_CURRENT() or nil
  if cur and type(cur.name) == "string" and cur.name ~= "" then who = cur.name end
  local bodies = {}
  for i = 1, n do
    local e = list[i]
    local idh = string.format("d0%02x", i)
    local body = e.code .. "|HEHPF:" .. idh .. " 0/1:0|h[" .. who .. "]|h|r  " .. tostring(i) .. "·" .. tostring(e.name)
    if string.len(body) > SH_MSG_MAX then body = e.code .. "|HEHPF:" .. idh .. " 0/1:0|h[" .. who .. "]|h|r" end
    if string.len(body) > SH_MSG_MAX then body = nil end
    e.body = body
    table.insert(bodies, body or "")
    if body then table.insert(shTxQ, { body = body, chan = "SAY" }) end
  end
  shTxLast = shNowT()
  shEnsureTxTicker()
  local cfgP = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgP) == "table" then cfgP.shTitleColorProbe = { n = n, list = bodies, at = shNowT() } end
  shSay(string.format(L("TC_PROBE_HEAD"), n))
  shSay(L("TC_PROBE_TIP"))
  for i = 1, n do
    shSay("  [" .. tostring(i) .. "] " .. shRawForPrint(list[i].code) .. "  " .. tostring(list[i].name) ..
          (list[i].current and ("  " .. L("TC_CUR")) or ""))
  end
  return { n = n, list = list, bodies = bodies, at = shNowT() }
end
-- 提交：把输入写进存档（**只有一次**，由 EVAL_TITLE_SET_CUSTOM 把守）——成功/失败都如实播报，绝不静默
local function shCreatorSubmit()
  if not (shCreator and shCreator.edit) then return false end
  local txt = ""
  local ok, v = pcall(shCreator.edit.GetText, shCreator.edit)
  if ok and type(v) == "string" then txt = v end
  if txt == "" and shCreator.echo then
    local ok2, v2 = pcall(shCreator.echo.GetText, shCreator.echo)
    if ok2 and type(v2) == "string" then txt = v2 end -- 回声行兜底（EditBox 不渲染时玩家看的是它）
  end
  local ok, key = EVAL_TITLE_CREATOR_TRY(txt)
  if ok then
    shSay(string.format(L(key), tostring(txt)))
    if shCreator.root then shCreator.root:Hide() end
    return true
  end
  shSay(L(key))
  -- ★名字不合法时**窗口留着**（让他改）；机缘已用尽才关窗（再留着也没意义）
  if key == "CREATOR_USED" and shCreator.root then shCreator.root:Hide() end
  return false
end
function EVAL_TITLE_CREATOR_SUBMIT() return shCreatorSubmit() end
-- ★1.73.42q 统一提交入口（弹窗与「命令后路」共用一份判断）：返回 ok, 消息键（CREATOR_DONE / CREATOR_USED / CREATOR_ERR）
function EVAL_TITLE_CREATOR_TRY(name)
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  local t = (type(cfgT) == "table" and type(cfgT.title) == "table") and cfgT.title or nil
  if t and type(t.custom) == "string" and t.custom ~= "" then return false, "CREATOR_USED" end
  if not EVAL_TITLE_SET_CUSTOM(name) then return false, "CREATOR_ERR" end
  return true, "CREATOR_DONE"
end
local function shCreatorClose(reason)
  if shCreator.root then shCreator.root:Hide() end
  if reason then shSay(reason) end
end
local function shCreatorBuild()
  if shCreator.root then return end
  local W, H = 470, 268
  local root = CreateFrame("Frame", "EVAL_TITLE_CREATOR", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 210) -- 高于分享弹窗 140 / 名称弹窗 130
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if type(EVAL_UIOFFSCREEN) == "function" and EVAL_UIOFFSCREEN(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 110)
  end
  -- 底板：近黑 + 三层金边（外暗金 1px、亮金 1px、内暗金）——「本源」的观感
  local bg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(bg, 0.03, 0.02, 0.01, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  local outer = root:CreateTexture(nil, "BORDER")
  shSolid(outer, 0.62, 0.48, 0.16, 1)
  outer:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  outer:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  local inner = root:CreateTexture(nil, "ARTWORK")
  shSolid(inner, 0.03, 0.02, 0.01, 1)
  inner:SetPoint("TOPLEFT", root, "TOPLEFT", 2, -2)
  inner:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -2, 2)
  local halo = root:CreateTexture(nil, "BORDER")
  shSolid(halo, 1.0, 0.90, 0.55, 1)
  halo:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  halo:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -1, 1)
  -- 顶部横幅 + 标题（两侧各一条金线做「匾额」观感）
  local banner = root:CreateTexture(nil, "ARTWORK")
  shSolid(banner, 0.20, 0.15, 0.05, 1)
  banner:SetPoint("TOPLEFT", root, "TOPLEFT", 3, -3)
  banner:SetPoint("TOPRIGHT", root, "TOPRIGHT", -3, -3)
  banner:SetHeight(34)
  local title = shText(root, 15, 1, 0.92, 0.55)
  title:SetPoint("TOP", root, "TOP", 0, -12)
  pcall(title.SetText, title, L("CREATOR_T"))
  shCreator.title = title
  for _, sx in ipairs({ -1, 1 }) do
    local ln = root:CreateTexture(nil, "ARTWORK")
    shSolid(ln, 0.75, 0.60, 0.22, 1)
    ln:SetHeight(1)
    ln:SetPoint("TOP", root, "TOP", sx * (W / 2 - 30), -30)
    ln:SetWidth(W / 2 - 70)
  end
  -- 四条霸气道白（居中逐行；本客户端多行 FontString 不稳 → 一行一个控件）
  local lineKeys = { "CREATOR_L1", "CREATOR_L2", "CREATOR_L3", "CREATOR_L4" }
  shCreator.lineFs = {}
  for i = 1, 4 do
    local fs = shText(root, 11, 0.95, 0.88, 0.62)
    fs:SetPoint("TOP", root, "TOP", 0, -42 - (i - 1) * 18)
    pcall(fs.SetWidth, fs, W - 40)
    pcall(fs.SetJustifyH, fs, "CENTER")
    pcall(fs.SetNonSpaceWrap, fs, false)
    pcall(fs.SetText, fs, L(lineKeys[i]))
    shCreator.lineFs[i] = fs
  end
  -- 当前名号（替换前的旧名，暗金小字）
  local curFs = shText(root, 10, 0.72, 0.66, 0.42)
  curFs:SetPoint("TOP", root, "TOP", 0, -122)
  pcall(curFs.SetWidth, curFs, W - 40)
  pcall(curFs.SetJustifyH, curFs, "CENTER")
  shCreator.curFs = curFs
  -- ★★★1.73.42q 输入区（用户真机报「没输入框」：EditBox 的**字体链断了就没字也没光标**，看着就像没有输入框）——
  --   ① 补 `EnableMouse`（不然点不进焦点）；② 字体对象全失败时**必须**再走 SetFont(字体路径) 兜底链
  --   （EvalHelp 的 TN/IO 窗同款做法：Fonts\FZLBJW.TTF → FRIZQT__ → ARIALN，带不带 OUTLINE 各试一次）；
  --   ③ 输入区画成**看得见的框**（暗底 + 四条金边，不是只画一条上边）；④ 空框里放提示字，一输入就藏；
  --   ⑤ 顶上再压一个**点击层**（本客户端 EditBox 自己收鼠标不保险 → 点框内任意处都 SetFocus）。
  local FIELD_W, FIELD_H, FIELD_Y = W - 120, 28, -140
  local box = root:CreateTexture(nil, "BACKGROUND")
  shSolid(box, 0.04, 0.04, 0.06, 1)
  box:SetPoint("TOP", root, "TOP", 0, FIELD_Y)
  box:SetWidth(FIELD_W) box:SetHeight(FIELD_H)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do -- 上下两条金边（左右各一条）
    local ln = root:CreateTexture(nil, "BORDER")
    shSolid(ln, 0.62, 0.50, 0.20, 1)
    ln:SetPoint(e, root, "TOP", 0, FIELD_Y - (e == "TOP" and 0 or (FIELD_H - 1)))
    ln:SetWidth(FIELD_W) ln:SetHeight(1)
  end
  for _, sx in ipairs({ -1, 1 }) do
    local ln = root:CreateTexture(nil, "BORDER")
    shSolid(ln, 0.62, 0.50, 0.20, 1)
    ln:SetPoint("TOP", root, "TOP", sx * (FIELD_W / 2), FIELD_Y)
    ln:SetWidth(1) ln:SetHeight(FIELD_H)
  end
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_TITLE_CREATOR_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true) -- ★不补这句：本客户端点不进焦点（用户实测「没输入框」的一半原因）
    eb:SetWidth(FIELD_W - 16) eb:SetHeight(FIELD_H - 8)
    eb:SetPoint("TOP", root, "TOP", 0, FIELD_Y - 5)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then -- ★字体对象都没有 → 走**字体路径链**（不然一个字都不画：看着就是「没有输入框」）
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 12, "OUTLINE")
        if not (okF and ok2) then okF, ok2 = pcall(eb.SetFont, eb, fp, 12, "") end
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 12) end
    pcall(eb.SetTextColor, eb, 1, 0.94, 0.72)
    pcall(eb.SetTextInsets, eb, 4, 4, 0, 0) -- 本客户端默认文字居中偏右（1.70.3 实测）
    pcall(eb.SetJustifyH, eb, "CENTER")
    pcall(eb.SetMaxLetters, eb, 12)
    pcall(eb.SetScript, eb, "OnMouseDown", function() pcall(eb.SetFocus, eb) end)
    pcall(eb.SetScript, eb, "OnTextChanged", function()
      local okt, tv = pcall(eb.GetText, eb)
      if type(tv) ~= "string" then tv = "" end
      if shCreator.echo then -- 回声行保底：EditBox 不渲染也看得见自己打的名字
        pcall(shCreator.echo.SetText, shCreator.echo, tv)
      end
      if shCreator.fieldHint then -- 有字就藏掉框内提示
        if tv == "" then pcall(shCreator.fieldHint.Show, shCreator.fieldHint)
        else pcall(shCreator.fieldHint.Hide, shCreator.fieldHint) end
      end
    end)
    pcall(eb.SetScript, eb, "OnEnterPressed", function() shCreatorSubmit() end) -- 回车即落笔
    pcall(eb.SetScript, eb, "OnEscapePressed", function() shCreatorClose(L("CREATOR_CLOSED")) end)
    shCreator.edit = eb
  end
  -- 空框内的提示（一输入就藏；EditBox 不给光标时至少这里看得见「该在这里写字」）
  local fieldHint = shText(root, 10, 0.55, 0.50, 0.38)
  fieldHint:SetPoint("TOP", root, "TOP", 0, FIELD_Y - 7)
  pcall(fieldHint.SetWidth, fieldHint, FIELD_W - 20)
  pcall(fieldHint.SetJustifyH, fieldHint, "CENTER")
  pcall(fieldHint.SetText, fieldHint, L("CREATOR_HINT"))
  shCreator.fieldHint = fieldHint
  -- 点击层：点框内任意处都聚焦 EdiBox（本客户端 EditBox 收鼠标不保险）
  local hit = CreateFrame("Button", nil, root)
  hit:SetWidth(FIELD_W) hit:SetHeight(FIELD_H)
  hit:SetPoint("TOP", root, "TOP", 0, FIELD_Y)
  pcall(hit.EnableMouse, hit, true)
  pcall(hit.RegisterForClicks, hit, "LeftButtonUp")
  pcall(hit.SetScript, hit, "OnClick", function()
    if shCreator.edit then pcall(shCreator.edit.SetFocus, shCreator.edit) end
  end)
  shCreator.fieldHit = hit
  local echo = shText(root, 11, 1, 0.92, 0.60)
  echo:SetPoint("TOP", root, "TOP", 0, -172)
  pcall(echo.SetWidth, echo, W - 60)
  pcall(echo.SetJustifyH, echo, "CENTER")
  pcall(echo.SetText, echo, "")
  shCreator.echo = echo
  local hint = shText(root, 9, 0.62, 0.58, 0.46)
  hint:SetPoint("TOP", root, "TOP", 0, -186)
  pcall(hint.SetText, hint, L("CREATOR_HINT"))
  shCreator.hint = hint
  -- 按钮：[落笔] / [放弃这份机缘]（居中两段）
  local function mkBtn(x, label, fr, fg, fb, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(150) b:SetHeight(24)
    b:SetPoint("TOP", root, "TOP", x, -206)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    shSolid(bb, 0.18, 0.14, 0.05, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = shText(b, 11, fr, fg, fb)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    pcall(bt.SetText, bt, label)
    pcall(b.SetScript, b, "OnClick", fn)
    return b, bt
  end
  local okBtn, okTxt = mkBtn(-80, L("CREATOR_OK"), 1, 0.92, 0.55, function() shCreatorSubmit() end)
  local noBtn, noTxt = mkBtn(80, L("CREATOR_CANCEL"), 0.72, 0.66, 0.52, function() shCreatorClose(L("CREATOR_CLOSED")) end)
  shCreator.ok, shCreator.okText = okBtn, okTxt
  shCreator.cancel, shCreator.cancelText = noBtn, noTxt
  -- 页脚：只有一次
  local one = shText(root, 9, 0.90, 0.72, 0.28)
  one:SetPoint("BOTTOM", root, "BOTTOM", 0, 10)
  pcall(one.SetText, one, L("CREATOR_ONE"))
  shCreator.oneFs = one
  root:Hide()
  shCreator.root = root
end
-- 打开（命令入口）：机缘用过就**如实拒绝**并说明，绝不再改；打开时把旧名号写在窗口里
function EVAL_TITLE_CREATOR_OPEN()
  shCreatorBuild()
  if not shCreator.root then return false end
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgT) == "table" then
    -- ★接线判据的**落盘证人**（M336 教训：别用「聊天含子串」判命令有没有跑）
    cfgT.shareCreatorOpen = { at = shNowT() }
  end
  local t = (type(cfgT) == "table" and type(cfgT.title) == "table") and cfgT.title or nil
  if t and type(t.custom) == "string" and t.custom ~= "" then
    shSay(L("CREATOR_USED"))
    return false
  end
  local cur = EVAL_TITLE_CURRENT()
  if shCreator.curFs then pcall(shCreator.curFs.SetText, shCreator.curFs, string.format(L("CREATOR_CUR"), cur and tostring(cur.name) or "—")) end
  if shCreator.edit then
    pcall(shCreator.edit.SetText, shCreator.edit, "")
    pcall(shCreator.edit.Show, shCreator.edit)
  end
  if shCreator.echo then pcall(shCreator.echo.SetText, shCreator.echo, "") end
  if shCreator.fieldHint then pcall(shCreator.fieldHint.Show, shCreator.fieldHint) end -- 空框提示回来
  shCreator.root:Show()
  if shCreator.edit then pcall(shCreator.edit.SetFocus, shCreator.edit) end
  shSay(L("CREATOR_ONE"))
  return true
end
function EVAL_TITLE_CREATOR_CLOSE() shCreatorClose(nil) end
-- ===== 测试钩子（读**真控件**，不读我们自己的账）=====
function EVAL_TEST_CREATOR_SHOWN()
  if not shCreator.root then return false end
  local ok, v = pcall(shCreator.root.IsShown, shCreator.root)
  return (ok and v) and true or false
end
local function shCreatorRead(fs)
  if not fs then return nil end
  local ok, v = pcall(fs.GetText, fs)
  if ok and type(v) == "string" then return v end
  return nil
end
function EVAL_TEST_CREATOR_TEXTS()
  local out = { lines = {} }
  out.title = shCreatorRead(shCreator.title)
  for i = 1, 4 do out.lines[i] = shCreatorRead(shCreator.lineFs and shCreator.lineFs[i]) end
  out.hint = shCreatorRead(shCreator.hint)
  out.ok = shCreatorRead(shCreator.okText)
  out.cancel = shCreatorRead(shCreator.cancelText)
  out.one = shCreatorRead(shCreator.oneFs)
  out.cur = shCreatorRead(shCreator.curFs)
  return out
end
function EVAL_TEST_CREATOR_INPUT(txt)
  if not shCreator.edit then return false end
  pcall(shCreator.edit.SetText, shCreator.edit, tostring(txt or ""))
  local ok, fn = pcall(shCreator.edit.GetScript, shCreator.edit, "OnTextChanged")
  if ok and type(fn) == "function" then pcall(fn, shCreator.edit, true) end -- 与真实逐字输入同一条路
  return true
end
function EVAL_TEST_CREATOR_ECHO() return shCreatorRead(shCreator.echo) end
-- ★1.73.42q 「没输入框」事故的专用读值口：EditBox 收不收鼠标 / 能不能聚焦 / 空框提示在不在
function EVAL_TEST_CREATOR_EDIT_MOUSE()
  if not shCreator.edit then return nil end
  return rawget(shCreator.edit, "__mouse") and true or false
end
function EVAL_TEST_CREATOR_EDIT_FONT() -- EditBox 实际设上的字体（两条路都没有 = 一个字都画不出 → 看着像「没输入框」）
  if not shCreator.edit then return nil end
  return { fo = rawget(shCreator.edit, "__fo"), path = rawget(shCreator.edit, "__font") }
end
function EVAL_TEST_CREATOR_FOCUS()
  if not shCreator.edit then return nil end
  local ok, v = pcall(shCreator.edit.HasFocus, shCreator.edit)
  return (ok and v) and true or false
end
function EVAL_TEST_CREATOR_FIELD_HINT_SHOWN()
  if not shCreator.fieldHint then return nil end
  local ok, v = pcall(shCreator.fieldHint.IsShown, shCreator.fieldHint)
  return (ok and v) and true or false
end
function EVAL_TEST_CREATOR_CLICK_FIELD() -- 模拟「点框内任意处」（本客户端 EditBox 收鼠标不保险 → 有点击层）
  if not shCreator.fieldHit then return false end
  local ok, fn = pcall(shCreator.fieldHit.GetScript, shCreator.fieldHit, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  pcall(fn)
  return true
end
function EVAL_TEST_CREATOR_CLICK(which)
  local b = (which == "cancel") and shCreator.cancel or shCreator.ok
  if not b then return false end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  pcall(fn)
  return true
end

-- ===== 1.73.42c 品阶图标 + 「|T 内联纹理」可行性探针（用户要求：按语义给等级配图标，先验证）=====
-- ★★★1.73.42l 图标由**用户指定**（2026-09-19 真机反馈：「案例方案内图标替换，名称和颜色背景都要符合以上规则」）：
--   按用户给的顺序对号入座 —— 神级=暗影蛋 INV_Misc_ShadowEgg · 绝版=暗影蛋 INV_Misc_ShadowEgg
--   · 普通=堕落灰烬使者 INV_Sword_2H_AshbringerCorrupt · 稀有=斧 INV_Axe_10 · 珍稀=矛 INV_Spear_04。
--   ⚠️ 用户给的「图1（神级）」与「图2（绝版）」是**同一张** INV_Misc_ShadowEgg（两张截图逐字相同）——
--      本轮先照他列的顺序都用它；要区分只需换掉本表里第 4 项（绝版）。
--   ★五个名字都在 IconSem.lua（客户端图标清单）里**逐字存在**（已核）→ 路径真实、本客户端画得出来。
--     ★文件名**不带** `_TEX` 后缀：`_TEX` 是客户端资源命名，插件侧路径一律 `Interface\Icons\<名>`。
-- ★但「聊天行里能不能画图标」是本客户端**未知数**：`|T` 标记在本仓库与两个参考插件里**使用次数为 0** ⇒ 必须实测。
local SH_SEAL_ICONS = {
  "INV_Axe_10", "INV_Spear_04", "INV_Sword_22", "INV_Sword_2H_AshbringerCorrupt", "INV_Misc_ShadowEgg",
}
-- ★★★1.73.42d 实测结论（用户回报探针）：`|T` 内联纹理**不可用**（只有纯符号对照 ④ 渲染出来）
--   → 聊天行改用**符号**按品阶区分；图标留到**点击后的详情弹窗**里（UI 纹理 100% 可行）。
function EVAL_SHARE_SEAL_SYMBOL(tierIdx)
  return SH_SEAL_SYMBOLS[tonumber(tierIdx) or 1] or SH_SEAL_SYMBOLS[1]
end
function EVAL_SHARE_SEAL_ICON(tierIdx)
  local f = SH_SEAL_ICONS[tonumber(tierIdx) or 1] or SH_SEAL_ICONS[1]
  return "Interface\\Icons\\" .. f, f
end
function EVAL_SHARE_SEAL_ICON_COUNT() return table.getn(SH_SEAL_ICONS) end
-- ★★★1.73.42l 品阶色码 → RGB（0..1）：案例模版行的**名称文字色**与**背景色**都用它，
--   与聊天行/弹窗用的是**同一张**色表（SH_SEAL_TIERS[].color）→ 三处永不漂移。
--   ★解析 8 位色码（`|c` + AARRGGBB）：从第 5 字节起取 R/G/B（**不切 alpha**——本项目 COLOR CODE LEN CHECK 守着
--     「不许把 8 位切出 6 位」那条真事故）；解析不出来就如实给 nil（调用方退回原来的暗黄底色）。
-- ★★★1.73.57 **色码 → RGB 的唯一解析口**：8 位 |cAARRGGBB → { r, g, b, hex }；
--   解析不出来**如实返回 nil**（调用方各自退回中性色，**绝不猜一个颜色**）。
--   ★只认**恰好 10 字节**（|c + 8 位 hex）—— 本项目 COLOR CODE LEN CHECK 守着「不许把 8 位切出 6 位」那条真事故；
--     ★不切 alpha（第 3~4 字节是 AA，R/G/B 从第 5 字节起）。
--   ★为什么抽成一个口：品阶色（方案列表 / 案例模版 / 标题栏徽标 / 分享封皮）与**头衔色**要的是同一件事 ——
--     原来只有 EVAL_SHARE_SEAL_TIER_RGB 一份实现；再加一份就是「同一规则两处实现」（本项目的老账）。
function EVAL_COLOR_RGB(code)
  if type(code) ~= "string" or string.len(code) ~= 10 or string.sub(code, 1, 2) ~= "|c" then return nil end
  local r = tonumber(string.sub(code, 5, 6), 16)
  local g = tonumber(string.sub(code, 7, 8), 16)
  local b = tonumber(string.sub(code, 9, 10), 16)
  if not r or not g or not b then return nil end
  return { r = r / 255, g = g / 255, b = b / 255, hex = code }
end
function EVAL_SHARE_SEAL_TIER_RGB(tierIdx)
  local i = tonumber(tierIdx) or 1
  local t = SH_SEAL_TIERS[i] or SH_SEAL_TIERS[1]
  return EVAL_COLOR_RGB(t and t.color)
end
-- 探针：4 种写法各一条（密语自己），④ 是纯符号对照（永远能渲染，作为保底参照）
function EVAL_SHARE_ICON_PROBE(chanId)
  chanId = (type(chanId) == "string" and chanId ~= "") and chanId or "WHISPER"
  local p = EVAL_SHARE_SEAL_ICON(1)
  local bodies = {
    "① |T" .. p .. ":16:16:0:0|t 书（|T 带尺寸）",
    "② |T" .. p .. ":0|t 书（|T 省略尺寸）",
    "③ |T" .. p .. ":16|t 书（|T 只给宽）",
    "④ ★ 书（纯符号对照——永远成功）",
  }
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfg) == "table" then
    cfg.shareIconProbe = { bodies = bodies, at = (type(GetTime) == "function") and GetTime() or 0 }
  end
  local ok = shProbeSend(bodies, chanId)
  shSay("图标探针已发出（" .. tostring(chanId) .. "）：请看一眼聊天框，**哪一种画出了图标**：")
  for i = 1, table.getn(bodies) do shSay("  " .. bodies[i]) end
  shSay("  ★判读：只有 ④ 出 = |T 不可用（聊天行改符号、图标进弹窗）；①/②/③ 出 = 聊天行可直接带图标")
  return ok and true or false
end
-- 读值口（测试用：不靠聊天字符串判接线，改读落盘字段）
function EVAL_SHARE_ICON_PROBE_BODIES()
  local cfg = rawget(_G, "EVAL_HELP_CONFIG")
  local p = type(cfg) == "table" and cfg.shareIconProbe
  return (type(p) == "table") and p.bodies or nil
end
-- ===== 1.73.41c 探针 ③：悬停 tooltip 机制发现 ===========================================
-- 用户需求（原话）：「角色名: 分享了一份绝世秘籍 —— 鼠标移动上去才能看到详细的方案信息」。
--   两个判断**读码定不了、必须实测**：
--     ① 聊天里的**自定义链接**悬停时客户端自己会不会弹 tooltip（引擎认不认这个类型）；
--     ② 会弹的话是**哪条 Lua 路径**画的（能不能被我们截住、换成方案详情）。
--   做法：把候选入口包一层**只记账、不改行为**（原函数照调、幂等），用户悬停/点击后读账本。
local SH_HOVER = { installed = false, hooks = {}, log = {}, counts = {}, sent = {}, scriptProbe = nil }
-- ★★★1.73.41d 事件即刷盘（真事故：用户悬停完直接 /reload → 账本没落盘，因为原来只有「报告」才写）
--   每次记账都把账本写进存档字段（小表、事件稀少，成本可忽略）：这样用户**只需悬停 + /reload**。
local function shHoverFlush()
  local c = rawget(_G, "EVAL_HELP_CONFIG")
  if type(c) ~= "table" then return end
  c.shareProbeHover = { hooks = SH_HOVER.hooks, log = SH_HOVER.log, counts = SH_HOVER.counts,
                        scriptProbe = SH_HOVER.scriptProbe, sent = SH_HOVER.sent,
                        armedAt = SH_HOVER.armedAt }
end
local function shHoverBump(name)
  SH_HOVER.counts[name] = (SH_HOVER.counts[name] or 0) + 1
  shHoverFlush() -- ★事件即刷盘
end
local function shHoverNote(hook, link)
  if table.getn(SH_HOVER.log) >= 40 then return end
  table.insert(SH_HOVER.log, { hook = tostring(hook), link = tostring(link or ""),
                               n = string.len(tostring(link or "")) })
  shHoverFlush() -- ★事件即刷盘
end
function EVAL_SHARE_HOVER_HOOKS()
  if SH_HOVER.installed then return SH_HOVER.hooks end
  SH_HOVER.installed = true
  local gt = rawget(_G, "GameTooltip")
  if type(gt) == "table" then
    local function wrap(name, wantLink)
      local orig = gt[name]
      if type(orig) ~= "function" then return false end
      gt[name] = function(self, ...)
        local a1 = ...
        shHoverBump(name)
        if wantLink then shHoverNote("GameTooltip:" .. name, type(a1) == "string" and a1 or "") end
        return orig(self, ...)
      end
      table.insert(SH_HOVER.hooks, name)
      return true
    end
    wrap("SetHyperlink", true) -- ★最关键：画链接 tooltip 的必经之路（能截住 = 能换成方案详情）
    wrap("SetItemByID", true)  -- 另一条可能被走的路（有就包，没有就跳过）
    wrap("Show", false)
    wrap("SetOwner", false)
    wrap("ClearLines", false)
    wrap("AddLine", false)
  end
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  local probe = {}
  if type(f) == "table" and type(f.GetScript) == "function" then
    for _, ev in ipairs({ "OnHyperlinkEnter", "OnHyperlinkLeave", "OnHyperlinkClick", "OnHyperlinkShow", "OnEnter" }) do
      local ok2, v = pcall(f.GetScript, f, ev)
      probe[ev] = (ok2 and type(v) == "function") and "已注册" or "无"
    end
  end
  SH_HOVER.scriptProbe = probe
  return SH_HOVER.hooks
end
function EVAL_SHARE_HOVER_STATE()
  return { installed = SH_HOVER.installed, hooks = SH_HOVER.hooks, log = SH_HOVER.log,
           counts = SH_HOVER.counts, sent = SH_HOVER.sent, scriptProbe = SH_HOVER.scriptProbe }
end
-- 发三条形态（都带「分享了一份绝世秘籍」这句文案），请用户**逐个悬停/点击**后读账本
function EVAL_SHARE_HOVER_PROBE(chanId)
  chanId = (type(chanId) == "string" and chanId ~= "") and chanId or "WHISPER"
  EVAL_SHARE_HOVER_HOOKS()
  local prefix = "ho" .. shProbeRandomTag()
  local t1 = prefix .. "01"
  local bodies = {}
  table.insert(bodies, "分享了一份绝世秘籍 → |cff9ad4ff|HEHPF:" .. t1 .. " 1/1:" .. toHex("HOVER-" .. t1) ..
                      "|h[绝世秘籍·自定义链接]|h|r")
  table.insert(bodies, "分享了一份绝世秘籍 → |cffa335ee|Hitem:1234:0:0:0:0:0:0:0|h[绝世秘籍·假物品链接]|h|r")
  table.insert(bodies, "分享了一份绝世秘籍 → |cffffffff|Hitem:6948:0:0:0:0:0:0:0|h[炉石·真物品id对照]|h|r")
  SH_HOVER.sent = bodies
  SH_HOVER.log = {}
  SH_HOVER.counts = {}
  SH_HOVER.armedAt = (type(GetTime) == "function") and GetTime() or 0
  -- ★★★1.73.41e 取证缺陷（用户实测：存档里 shareProbeHover 完全缺席）：只在「事件」里刷盘的话，
  --   一个 hook 都没触发时存档里**什么都没有** → 分不清「探针没跑」还是「跑了但悬停不走 Lua」。
  --   → 发探针时先写一次（含「装了哪些 hook」+ 空日志 + 时间戳）：这样「一个事件都没有」本身就是结论。
  shHoverFlush()
  local ok = shProbeSend(bodies, chanId)
  shSay("悬停探针已发出（" .. tostring(chanId) .. "）：请把鼠标**依次停在**聊天里那三条链接上各一下，再各点一下")
  shSay("  ① 自定义链接  ② 假物品链接  ③ 真物品 id(6948) 对照 —— **悬停完请先敲 /eh go 探针结果**（无条件写盘），再 /reload")
  return ok and true or false
end


-- 探针结果：**如实**报告（一致 / 被改 / 未收到；长度档位看实际字节数与尾部哨兵）
-- ★★★1.73.41b 用户「操作完了.看下」暴露的**取证缺口**：结果原来只打进**聊天框**，而本机没有聊天日志文件、
--   SavedVariables 里也没有 → AI/事后都读不到。现在**每条都同时落盘**（EVAL_LOGLINE + EVAL_HELP_CONFIG.shareProbe
--   的完整文字 + shareProbeVerdicts 判定表 + shareProbeRaw 发出/收到原文），/reload 之后就能读回来。
function EVAL_SHARE_PROBE_REPORT()
  local p = SH_PROBE
  local out = { link = {}, len = {} }
  local lines, rawS = {}, { link = {}, len = {} }
  local function emit(s)
    s = tostring(s)
    shSay(s)
    if type(EVAL_LOGLINE) == "function" then pcall(EVAL_LOGLINE, "[探针] " .. s) end
    table.insert(lines, s)
  end
  emit("===== 探针结果（发出 vs 收到）=====")
  if table.getn(p.sent or {}) == 0 and table.getn(p.ladderSent or {}) == 0 then
    -- ★★★1.73.41d 真事故：这里原来是 `return out`（早退）→ 用户在**没跑分片探针的会话里**敲报告，
    --   悬停账本就被吞掉、永远落不了盘（用户实测：12:53 存档里 shareProbeHover 一片空白）。
    emit("  （本会话还没发过分片探针：链接/长度部分无数据；下面的悬停账本照样输出）")
  end
  for i = 1, table.getn(p.sent or {}) do -- ★无数据时这个循环自然不进
    local f = p.sent[i]
    local r = shProbeFind("link", f.tag)
    local v, extra
    if not r then v, extra = "未收到", "（可能是：没回声 / 服务器丢了 / 还没到）"
    else
      local d = shProbeDiff(f.body, r.raw)
      if d == nil then v, extra = "一致", "（逐字节相同，" .. tostring(string.len(r.raw)) .. " 字节）"
      else v, extra = "被改", "（首个不同处第 " .. tostring(d) .. " 字节；发出=" ..
             string.sub(f.body, d, d + 14) .. " 收到=" .. string.sub(r.raw, d, d + 14) .. "）" end
      local hasC = string.find(r.raw, "|c", 1, true) ~= nil
      local hasH = string.find(r.raw, "|H", 1, true) ~= nil
      extra = extra .. "  标记：" .. (hasC and "|c 在" or "|c 没了") .. " / " .. (hasH and "|H 在" or "|H 没了")
    end
    out.link[i] = { label = f.label, tag = f.tag, sent = string.len(f.body),
                    got = r and string.len(r.raw) or 0, verdict = v }
    emit("  " .. f.label .. " → " .. v .. " " .. extra)
    if r then
      emit("     发出：" .. f.body)
      emit("     收到：" .. r.raw)
      rawS.link[i] = { idx = f.idx, tag = f.tag, verdict = v, sent = f.body, got = r.raw,
                       sender = r.sender, ev = r.ev }
    end
  end
  for i = 1, table.getn(p.ladderSent or {}) do
    local row = p.ladderSent[i]
    local r = shProbeFind("len", row.tag)
    local v, extra
    if not r then v, extra = "未收到", ""
    else
      local tailOK = string.find(r.raw, row.tail, 1, true) ~= nil
      local len = string.len(r.raw)
      if tailOK and len == row.target then v = "完整"
      else v = "截断" end
      extra = "（目标 " .. tostring(row.target) .. " → 收到 " .. tostring(len) .. "，尾部哨兵 " ..
              (tailOK and "在" or "没了") .. "）"
    end
    out.len[i] = { target = row.target, tag = row.tag, got = r and string.len(r.raw) or 0, verdict = v }
    emit("  长度档 " .. tostring(row.target) .. " → " .. v .. " " .. extra)
    if r then rawS.len[i] = { idx = row.idx, tag = row.tag, target = row.target, verdict = v,
                             got = r.raw, sender = r.sender, ev = r.ev } end
  end
  p.verdicts = out
  emit("  ★结论怎么读：① 若「自定义链接」= 一致 → 隐藏方案可行（服务器转发自定义链接）；" ..
       "② 若只有 ②③/④ 一致 → 自定义类型被服务器剥了，改走已知类型或退回「只缩短」；" ..
       "③ 长度档出现「截断」→ 记下那一档的真实字节数，SH_CHUNK 要按它重算")
  -- ★★1.73.41c 悬停探针账本（「鼠标移上去才能看到详情」能不能做，就看这里）
  do
    local h = SH_HOVER
    emit("  --- 悬停探针账本（谁在画 tooltip） ---")
    if not h.installed then
      emit("  还没装挂钩（先 /eh go 悬停探针）")
    else
      emit("  已挂：" .. table.concat(h.hooks, "、"))
      emit("  时间戳：" .. tostring(h.armedAt or 0) .. "；日志条数：" .. tostring(table.getn(h.log)))
      if table.getn(h.log) == 0 then
        emit("  ★一个事件都没有 = 悬停**不走 Lua**（这就是结论）→ 改用「点击看详情」或自绘悬停热区")
      end
      emit("  SetHyperlink 命中 " .. tostring(table.getn(h.log)) .. " 次（>0 = 有 Lua 路径画链接 tooltip，可截可换）")
      for i = 1, math.min(table.getn(h.log), 6) do
        emit("     [" .. i .. "] " .. tostring(h.log[i].hook) .. " → " .. tostring(h.log[i].link))
      end
      emit("  其它计数：SetOwner=" .. tostring(h.counts.SetOwner or 0) .. " ClearLines=" .. tostring(h.counts.ClearLines or 0) ..
           " AddLine=" .. tostring(h.counts.AddLine or 0))
      local sp = h.scriptProbe or {}
      emit("  聊天帧脚本探测：OnHyperlinkEnter=" .. tostring(sp.OnHyperlinkEnter) .. " / OnHyperlinkLeave=" .. tostring(sp.OnHyperlinkLeave) ..
           " / OnHyperlinkClick=" .. tostring(sp.OnHyperlinkClick) .. " / OnHyperlinkShow=" .. tostring(sp.OnHyperlinkShow))
    end
    local cfgH = rawget(_G, "EVAL_HELP_CONFIG")
    if type(cfgH) == "table" then
      cfgH.shareProbeHover = { hooks = h.hooks, log = h.log, counts = h.counts,
                               scriptProbe = h.scriptProbe, sent = h.sent }
    end
  end
  local cfgT = rawget(_G, "EVAL_HELP_CONFIG")
  if type(cfgT) == "table" then
    cfgT.shareProbe = string.sub(table.concat(lines, "\n"), 1, 8000)
    cfgT.shareProbeVerdicts = out
    cfgT.shareProbeRaw = rawS
  end
  emit("  ★已写入存档（EVAL_HELP_CONFIG.shareProbe）：/reload 后即可回传；也可 /eh logdump 查看")
  p.armed = nil
  return out
end
-- ★1.73.41b 「一次跑完」：用户只要敲一条命令、等 20 秒、再 /reload（结果就落盘了）——
--   探针结果原来只打聊天框，AI 事后读不到（用户「操作完了.看下」当场暴露这个缺口）。
local shProbeFrame, shProbePlan = nil, {}
local function shProbeNow()
  return (type(GetTime) == "function") and GetTime() or 0
end
local function shProbeTick()
  if not shProbeFrame then return end
  local step = shProbePlan[1]
  if not step then pcall(shProbeFrame.Hide, shProbeFrame) return end
  if shProbeNow() >= step.at then
    table.remove(shProbePlan, 1)
    pcall(step.fn)
  end
end
local function shProbeSchedule(delay, fn)
  if not shProbeFrame then
    shProbeFrame = CreateFrame("Frame", "EVAL_SHARE_PROBE_TICK", UIParent)
    shProbeFrame:SetScript("OnUpdate", shProbeTick)
  end
  pcall(shProbeFrame.Show, shProbeFrame)
  table.insert(shProbePlan, { at = shProbeNow() + delay, fn = fn })
  table.sort(shProbePlan, function(a, b) return a.at < b.at end)
end
function EVAL_SHARE_PROBE_AUTORUN(chanId)
  chanId = (type(chanId) == "string" and chanId ~= "") and chanId or "WHISPER"
  shSay("探针全跑（约 20 秒）：链接探针 → 6s 自动出结果 → 长度阶梯 → 6s 自动出结果")
  EVAL_SHARE_LINK_PROBE(chanId)
  shProbeSchedule(6, function() shSay("【自动】链接探针结果：") EVAL_SHARE_PROBE_REPORT() end)
  shProbeSchedule(12, function() EVAL_SHARE_LEN_PROBE(chanId) end)
  shProbeSchedule(18, function()
    shSay("【自动】长度阶梯结果：")
    EVAL_SHARE_PROBE_REPORT()
  end)
  -- ★1.73.41c 第 4 步：悬停探针（需用户**自己把鼠标停在链接上**）
  shProbeSchedule(20, function()
    EVAL_SHARE_HOVER_PROBE(chanId)
  end)
  return true
end
-- 测试钩子：驱动与 OnUpdate **同一个**函数（判据落在真实调用点）；PLAN 给出待跑步数
function EVAL_TEST_SHARE_PROBE_STEP() shProbeTick() end
function EVAL_TEST_SHARE_PROBE_PLAN() return table.getn(shProbePlan) end
-- ★1.71.3 事件分派（三态兼容）抽成函数：事件名在 1参 / 2参 / 全局 event，参数随之一档右移。
--   ★抽出来的理由：断言要验的是**真实分派逻辑**（不能在测试里重写一遍）。
function EVAL_SHARE_DISPATCH(ev, a1, a2, a3, a4)
  if type(ev) == "string" then return ev, a1, a2 end
  if type(a1) == "string" and string.find(a1, "^CHAT_MSG_") then return a1, a2, a3 end
  return nil, a3, a4
end

-- 聊天事件帧（三态兼容：事件名在 1参/2参/全局 event；参数随之一档右移）
local shf = CreateFrame("Frame", "EVAL_SHARE_EVENTS", UIParent)
shf:RegisterEvent("CHAT_MSG_GUILD")
shf:RegisterEvent("CHAT_MSG_PARTY")
shf:RegisterEvent("CHAT_MSG_RAID")
shf:RegisterEvent("CHAT_MSG_SAY")
shf:RegisterEvent("CHAT_MSG_WHISPER")
shf:SetScript("OnEvent", function()
  local ev, msg, sender = EVAL_SHARE_DISPATCH(event, arg1, arg2, arg3, arg4)
  shOnMsg(msg, sender, ev)
end)

-- ===== 接收弹窗（自绘；点 [导入] 走 EVAL_IMPORT_TEXT 桥） =====
local shp = {}
-- ★1.71.2 弹窗最多显示几行方案详情（超出折叠为「…还有 N 行」）。
--   为什么要有上限：方案最多 12 技能 × 每行可能很长的条件串，弹窗不能无限增高。
local SH_DETAIL_MAX = 6
-- ★★★1.73.42i 详情弹窗有「品阶行」：16px 品阶图标 + `★[品阶秘籍·名]`（带品阶色）—— 这一行就是**方案名**。
-- ★★★1.73.46 用户改版（红框那两行删掉 + 名字只留一处）：
--   ① 「品阶/身份」与「评语」两个控件**整个删除**（原来只是 Hide，看着还在）；
--   ② 标题行**不再重复《方案名》**（方案名由下面那行带品阶色的 `★[品阶秘籍·名]` 承担）——
--      只有**解析不出品阶**时才退回「标题里带名字」的旧写法（名字绝不能丢）。
--   布局算术（顶部为 0）：标题 -10 · 摘要行 -34 · 品阶行 -50（图标 16px 到 -66）
--     · 详情首行 -74（6 行 × 12 → 末行 -134、底约 -146）· 分隔线 底部+42 · 按钮行 底部 12~34（顶边 -166）
--   ⇒ 末行底与按钮顶之间约 20px 余量。★竖着放不下**唯一**的出路是加高窗口，
--     绝不许把详情行压到按钮上（那是「看不见的坏」：按钮被盖住/点不到，用户只会说「点不了」）。
local SH_SEAL_ROW_Y = -50   -- 品阶行顶部（品阶图标顶边）
local SH_SEAL_ROW_H = 16    -- 品阶图标边长
local SH_DETAIL_Y1 = -74    -- 详情首行（紧跟品阶行下方）
-- ★1.71.3 弹窗图标（自包含：这批 .tga 已从 UnrealQuest 拷进本插件 media\icons\）与标题栏高度
local SH_POP_ICON = "Interface\\AddOns\\EvalHelp\\media\\icons\\trainers-icon"
local SH_TITLE_H = 18

local function shPopupBuild()
  if shp.root then return end
  -- ★1.71.2 高度 130 → 200：要容纳「标题 + 6 行方案详情 + 按钮行」。
  --   算一遍：标题在 -10、详情首行 -52、6 行 × 12 = 至 -124、按钮行占底部 34 → 需要约 170，
  --   留余量取 200（长条件串还会占更宽，但不增高）。
  local W, H = 380, 200 -- ★1.73.46 216 → 200：那两行（品阶/身份 + 评语）删掉后空间富余，窗口收回原高（少挡画面）
  local root = CreateFrame("Frame", "EVAL_SHARE_POPUP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 190)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 140) -- 高于名称输入弹窗(130)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if type(EVAL_UIOFFSCREEN) == "function" and EVAL_UIOFFSCREEN(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    shSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  -- ★1.71.3 用户要求「根据新加的图标美化一下」：标题栏（底色条 + 左侧图标）+ 详情区下沉底板。
  local tbBg = root:CreateTexture(nil, "BACKGROUND")
  shSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  tbBg:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  tbBg:SetHeight(SH_TITLE_H)
  local title = shText(root, 11, 0.95, 0.82, 0.35)
  title:SetPoint("TOP", root, "TOP", 0, -10)
  title:SetText(L("SH_POP_T"))
  -- 标题左侧的图标：★标题是居中锚的，图标贴它左边（不参与居中计算，长标题也不会挤歪它）
  local tIcon = root:CreateTexture(nil, "ARTWORK")
  pcall(tIcon.SetTexture, tIcon, SH_POP_ICON)
  tIcon:SetWidth(14) tIcon:SetHeight(14)
  tIcon:SetPoint("RIGHT", title, "LEFT", -5, 0)
  shp.titleIcon = tIcon
  -- 详情区下沉底板 + 按钮上方的分隔线（观感分层，与配置窗同一套配色）
  local dPanel = root:CreateTexture(nil, "BACKGROUND")
  shSolid(dPanel, 0.02, 0.02, 0.02, 0.85)
  dPanel:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -46)
  dPanel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 44)
  local bSep = root:CreateTexture(nil, "BORDER")
  shSolid(bSep, 0.45, 0.38, 0.16, 1)
  bSep:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 10, 42)
  bSep:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -10, 42)
  bSep:SetHeight(1)
  local body = shText(root, 10, 0.92, 0.88, 0.80)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -34)
  pcall(body.SetWidth, body, W - 32)
  pcall(body.SetJustifyH, body, "LEFT")
  pcall(body.SetNonSpaceWrap, body, false) -- 不允许换行：过长的条件串宁可裁掉，也不要把行数搞乱
  shp.body = body
  -- ★1.71.2 用户要求：「在接收到方案分享的弹窗内，将方案的详细信息也显示」。
  --   原来只显示一行「XX 分享了《方案名》(N 个技能)」，用户看不到**具体有哪些技能/条件**，
  --   必须点导入进配置窗才知道内容。
  --   ★实现方式：按行显示（每条技能一个 FontString），而不是塞进一个多行 FontString——
  --     本客户端的多行 FontString 行高/换行行为不稳（本项目既有记录），逐行独立控件最可靠，
  --     也便于「最多显示 N 行」的裁剪与断言。
  shp.detailLines = {}
  for i = 1, SH_DETAIL_MAX do
    local fs = shText(root, 9, 0.80, 0.78, 0.70)
    fs:SetPoint("TOPLEFT", root, "TOPLEFT", 16, SH_DETAIL_Y1 - (i - 1) * 12) -- ★1.73.42i 顶端让给品阶栏
    pcall(fs.SetWidth, fs, W - 32)
    pcall(fs.SetJustifyH, fs, "LEFT")
    pcall(fs.SetNonSpaceWrap, fs, false)
    fs:Hide()
    -- ★注意：本弹窗是**独立弹窗**，不参与配置窗的 Tab 显隐契约，故没有 widgets 表可插。
    --   （误抄 EvalHelp.lua 的 page.widgets 写法会直接报 nil —— 本轮已避免。）
    shp.detailLines[i] = fs
  end
  -- ★★★1.73.42i 品阶栏：品阶**图标**（真 UI 纹理）+ 符号 + [品阶秘籍·名] + 品阶/评分 + 境界 + 评语。
  --   ★图标必须用真纹理：聊天行里的 `|T` 内联标记已**实测不可用**（1.73.42d 探针），UI 纹理 100% 可行。
  --   ★境界与评语**只有发送端知道**（随封皮行带来）→ 封皮还没到就如实写「未知」，
  --     绝不拿本机角色的境界/本机随机评语冒充发送端的（那是在骗用户）。
  local sealIcon = root:CreateTexture(nil, "ARTWORK")
  sealIcon:SetWidth(SH_SEAL_ROW_H) sealIcon:SetHeight(SH_SEAL_ROW_H)
  sealIcon:SetPoint("TOPLEFT", root, "TOPLEFT", 16, SH_SEAL_ROW_Y)
  pcall(sealIcon.SetTexture, sealIcon, EVAL_SHARE_SEAL_ICON(1)) -- 先给占位纹理（真值由 shSealRowApply 写）
  sealIcon:Hide()
  shp.sealIcon = sealIcon
  local sealHead = shText(root, 10, 0.95, 0.88, 0.72)
  sealHead:SetPoint("LEFT", sealIcon, "RIGHT", 6, 0)
  pcall(sealHead.SetNonSpaceWrap, sealHead, false)
  sealHead:Hide()
  shp.sealHead = sealHead
  -- ★★★1.73.46 用户（截图红框那两行）：「方案分享删除红色区域内的内容」⇒ 「品阶/身份」与「评语」
  --   两个控件**整个删掉**（原来是建出来再 Hide —— 那正是「看着还在」的来源；现在弹窗里只剩
  --   「图标 + `★[品阶秘籍·名]`」这一行，它就是方案名，标题行不再重复《方案名》）。
  --   ★那两行本来就是「未知（未收到封皮行）」的噪音：发送端的身份/评语接收端本来也复现不了。
  -- 几何真值（断言读它，不写死坐标）
  shp.sealY, shp.sealH = SH_SEAL_ROW_Y, SH_SEAL_ROW_H
  shp.detailY1 = SH_DETAIL_Y1
  shp.detailYN = SH_DETAIL_Y1 - (SH_DETAIL_MAX - 1) * 12
  shp.H = H
  shp.btnTop = -(H - 34) -- 按钮行顶边（顶部为 0 的坐标）
  -- ★1.73.14 用户要求：「接收方案开关在分享方案位置也添加一个方便快速关闭，然后三个位置居中对齐」
  --   【为什么加在弹窗里】收到别人分享时如果不想收，原来要：关弹窗 → 开配置窗 → 找到「接收方案」勾 → 取消（三步）；
  --     这里多一个常驻勾选框，**当场就能关掉**。
  --   ★★它读写的是**同一份真值**（EVAL_SHARE_RECV_ON / EVAL_SHARE_RECV_TOGGLE，与配置窗那个开关同一个），
  --     绝不另存一份状态（本项目「一份真值」铁律）。
  --   【布局】三段 = 「接收方案」勾选框 + [导入] + [忽略]，在弹窗宽度内**整体居中**（原来只有两个按钮居中）。
  local CHK_BOX, CHK_LBL_GAP = 16, 6
  local function shRecvLabelW(fs, label)
    pcall(fs.SetText, fs, tostring(label))
    if fs.GetStringWidth then
      local okw, v = pcall(fs.GetStringWidth, fs)
      if okw and type(v) == "number" and v > 0 then return v end
    end
    -- 兜底：只能按字符数估（★不能拿 string.len 当字符数：中文一字 3 字节）
    local by = string.len(tostring(label))
    return (((by >= 3) and math.floor(by / 3) or by)) * 13
  end
  -- 勾选框（复刻配置窗 cfgCheck 的金框/深底/亮块观感）；labelFS 由外面先建好（量宽后锚上来）
  local function shRecvCheck(x, y, label, tip, labelFS)
    local btn = CreateFrame("Button", nil, root)
    btn:SetWidth(CHK_BOX) btn:SetHeight(CHK_BOX)
    btn:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, y)
    pcall(btn.EnableMouse, btn, true)
    pcall(btn.RegisterForClicks, btn, "LeftButtonUp")
    local outer = btn:CreateTexture(nil, "BACKGROUND")
    shSolid(outer, 0.85, 0.70, 0.20, 1)
    outer:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    outer:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    local inner = btn:CreateTexture(nil, "ARTWORK")
    shSolid(inner, 0.10, 0.09, 0.06, 1)
    inner:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    local mark = btn:CreateTexture(nil, "OVERLAY")
    shSolid(mark, 0.95, 0.80, 0.25, 1)
    mark:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    if labelFS then pcall(labelFS.SetPoint, labelFS, "LEFT", btn, "RIGHT", CHK_LBL_GAP, 0) end
    pcall(btn.SetScript, btn, "OnEnter", function()
      if type(GameTooltip) == "nil" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, btn, "ANCHOR_RIGHT")
      pcall(GameTooltip.AddLine, GameTooltip, tostring(label), 1, 0.82, 0.3)
      pcall(GameTooltip.AddLine, GameTooltip, tostring(tip), 0.85, 0.85, 0.85, 1)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    pcall(btn.SetScript, btn, "OnLeave", function()
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    local function refresh()
      -- ★★★注意：**不能**写 `(type(f) == "function") and f() or true` ——
      --   f() 返回 false 时整个表达式会被 or 兜成 true（Lua 的 and/or 链没有布尔语义）→
      --   「关掉开关后勾选块仍然亮着」。本项目 1.70.46 在语言来源上踩过**一模一样的**写法
      --   （`... and EVAL_RESOLVE_LANG() or "zhCN"` 恒等于 zhCN），这里是第二次：照旧分两步写。
      local on = true
      if type(EVAL_SHARE_RECV_ON) == "function" then on = EVAL_SHARE_RECV_ON() and true or false end
      if on then pcall(mark.Show, mark) else pcall(mark.Hide, mark) end
    end
    pcall(btn.SetScript, btn, "OnClick", function()
      if type(EVAL_SHARE_RECV_TOGGLE) == "function" then pcall(EVAL_SHARE_RECV_TOGGLE) end
      refresh() -- 立刻反映（与配置窗那个开关是同一份真值，两边永远一致）
    end)
    refresh()
    return btn, mark, refresh
  end
  -- ★1.71.3 用户要求「按钮位置居中对齐下」+ 1.73.14 **三段整组居中**（勾选框 + [导入] + [忽略]）
  --   算一遍总宽再求左起点；宽度与间距是**单一来源**（CHK_*/BTN_*），三处各写一遍迟早漂移。
  local BTN_W, BTN_GAP = 90, 14
  local recvLbl = shText(root, 10, 0.92, 0.88, 0.80) -- ★真实标签（不再建「只为量宽」的幽灵控件：Hide 后仍可能被绘出）
  local recvLblW = shRecvLabelW(recvLbl, L("SH_RECV_SW"))
  local CHK_W = CHK_BOX + CHK_LBL_GAP + recvLblW
  local TOTAL_W = CHK_W + BTN_GAP + BTN_W + BTN_GAP + BTN_W
  local rowX0 = math.floor((W - TOTAL_W) / 2)
  if rowX0 < 10 then rowX0 = 10 end
  local chkX = rowX0
  local btnX1 = rowX0 + CHK_W + BTN_GAP
  local btnX2 = btnX1 + BTN_W + BTN_GAP
  local recvChk, recvMark, recvRefresh = shRecvCheck(chkX, 15, L("SH_RECV_SW"), L("SH_RECV_SW_TIP"), recvLbl)
  shp.recvChk, shp.recvLbl, shp.recvMark, shp.recvRefresh = recvChk, recvLbl, recvMark, recvRefresh
  -- 布局真值一起记下（诊断/断言读它，不写死坐标）
  shp.rowX0, shp.rowW, shp.chkW, shp.btnW, shp.btnGap = rowX0, TOTAL_W, CHK_W, BTN_W, BTN_GAP
  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(BTN_W) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    shSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = shText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  local importBtn = bBtn(btnX1, L("SH_IMPORT"), function()
    local p = SH.pending
    if not p then shp.root:Hide() return end
    if type(EVAL_IMPORT_TEXT) == "function" then
      local ok, msg = EVAL_IMPORT_TEXT(p.text)
      shSay(tostring(msg))
      if ok then
        shGuildFun("SH_FUN_IMPORT") -- 公会来源：点「导入/确认」在公会频道玩另一句（用户指定）
        shp.root:Hide()
        SH.pending = nil
      end
    else
      shSay(L("SH_NOIMPORT"))
    end
  end)
  local ignoreBtn = bBtn(btnX2, L("SH_IGNORE"), function()
    shGuildFun("SH_FUN_IGNORE") -- 公会来源：点「忽略」在公会频道玩一句（用户指定）
    shp.root:Hide()
    SH.pending = nil
  end)
  shp.ignoreBtn = ignoreBtn
  shp.importBtn = importBtn -- ★1.71.2 供断言走**真实按钮**（否则只能直调导入函数，绕过了出问题的路径）
  root:Hide()
  shp.root = root
end

-- ★★★1.73.42i 品阶行刷新（**唯一实现**）：弹窗弹出时调一次；封皮行**晚到**（单片方案）时再调一次。
--   两处走同一个函数 → 不会出现「弹窗里一套、晚到补写另一套」的漂移。
--   ★★★1.73.46 这一行现在**就是方案名**（用户改版：标题行不再重复《方案名》，身份/评语两行整个删掉）：
--     ① 品阶/评分/图标/符号由**收到的方案文本**复算（品阶本来就是方案的函数，接收端能独立算出来）；
--     ② 算不出（不是合法方案文本）→ **整行如实隐藏**，标题那边退回「带方案名」的旧写法（名字绝不丢）。
shSealRowApply = function()
  if not (shp.sealIcon and shp.sealHead) then return nil end
  local p = SH.pending
  local text = p and p.text
  local meta = nil
  if p and p.idh then meta = (SH.sealMeta or {})[tostring(p.idh)] end
  local row = (type(text) == "string") and EVAL_SHARE_SEAL_ROW(text, meta) or nil
  shp.sealRow = row
  if row then
    pcall(shp.sealIcon.SetTexture, shp.sealIcon, row.icon)
    pcall(shp.sealHead.SetText, shp.sealHead, row.head)
    shp.sealIcon:Show() shp.sealHead:Show()
  else
    -- 文本解析不出方案（不是合法方案文本）→ **整行如实隐藏**，不编造一个品阶出来
    -- ★先清空文本再 Hide：本客户端 Hide 过的控件仍可能被绘出（1.71.3 那轮「残留」的教训，
    --   详情行那边也是这么写的）→ 只 Hide 不清空 = 上一笔的品阶还挂在屏幕上（那是**假信息**）。
    pcall(shp.sealHead.SetText, shp.sealHead, "")
    shp.sealIcon:Hide() shp.sealHead:Hide()
  end
  return row
end
function EVAL_SH_POPUP(sender, text, ev, idh)
  shPopupBuild()
  -- ★1.73.14 每次弹出都刷新「接收方案」勾选态：开关可能在配置窗里被改过（**两个入口一份真值**，
  --   不刷新就会出现「配置窗显示关、弹窗里还亮着」的自相矛盾）
  if type(shp.recvRefresh) == "function" then pcall(shp.recvRefresh) end
  -- 预览解析（只读不导入）：拿方案名与技能数
  local name, count = "?", 0
  if type(EVAL_PROFILE_FROM_TEXT) == "function" then
    local prof = EVAL_PROFILE_FROM_TEXT(text)
    if prof then name = tostring(prof.name) count = table.getn(prof.skills or {}) end
  end
  local chanLab = EVAL_SHARE_CHAN_LABEL(ev)
  -- ★1.73.42i 记下**本次传输 id**：封皮行若晚到（单片方案：分片先到、封皮紧随），要靠它把品阶栏从「未知」补成真实值。
  SH.pending = { sender = sender, text = text, name = name, count = count, chan = chanLab, ev = ev, idh = idh }
  local showFrom = chanLab and ("[" .. chanLab .. "] " .. tostring(sender)) or tostring(sender)
  -- ★★★1.73.43e 用户（截图圈住标题里的《武器战》+ 划掉下面那三行）：「分享方案内**颜色替代武器战的位置**就可以，
  --   其他品阶,身份,评语都可以不显示」⇒ ① 那三行不再显示（见 shSealRowApply）；② **方案名用它的品阶色**（颜色补到名字上）。
  --   ★品阶由**收到的方案文本**本地重算（EVAL_SHARE_SEAL_SCORE/TIER，与聊天行/模版窗同一套判定），算不出就不加色（不猜）。
  -- ★模板 `SH_POP_GOT` 里**已经有《》**：这里只负责上色，绝不再补一层括号
  --   （第一版写成 `"《" .. name .. "》"` → 标题变成《《甲》》—— 判据的失败信息当场暴露了这个 bug）
  local nameTxt = tostring(name)
  local tcol = nil
  if type(EVAL_SHARE_SEAL_SCORE) == "function" and type(EVAL_SHARE_SEAL_TIER) == "function" then
    local okS, sc = pcall(EVAL_SHARE_SEAL_SCORE, text)
    if okS and sc ~= nil then
      local okT, ti, tier = pcall(EVAL_SHARE_SEAL_TIER, sc)
      if okT and type(tier) == "table" and type(tier.color) == "string" then tcol = tier.color end
    end
  end
  if tcol then nameTxt = tcol .. nameTxt .. "|r" end
  -- ★★★1.73.46 摘要行文本**挪到品阶行刷新之后**再写（那时才知道有没有品阶行可承担方案名）—— 见本函数末尾。
  -- ★1.71.2 详情：把导入文本按行显示，让用户在**点导入之前**就能看清内容。
  --   用**逐个 FontString** 而非一个多行 FontString（本客户端多行行为不稳，逐行最可靠）。
  --   最多 SH_DETAIL_MAX 行，超出时最后一行提示还剩多少（不静默截断——诚实告知）。
  if shp.detailLines then
    local lines = {}
    for ln in string.gmatch(text or "", "[^\r\n]+") do table.insert(lines, ln) end
    local shown, total = 0, table.getn(lines)
    for i = 1, SH_DETAIL_MAX do
      local fs = shp.detailLines[i]
      if fs then
        local l = lines[i]
        if l then
          fs:SetText(l)
          fs:Show()
          shown = i
        else
          -- ★1.71.3 先**清空文本**再 Hide：本客户端 Hide 过的控件仍可能被绘出（「黑块」那轮的教训），
          --   只 Hide 不清空 → 上一份分享的残留行还挂在屏幕上（正是「只显示最新数据」要消灭的东西）。
          fs:SetText("")
          fs:Hide()
        end
      end
    end
    -- 超出部分：复用最后一行显示「…还有 N 行」
    if total > SH_DETAIL_MAX and shp.detailLines[SH_DETAIL_MAX] then
      shp.detailLines[SH_DETAIL_MAX]:SetText(string.format(L("SH_POP_MORE"), total - SH_DETAIL_MAX + 1))
      shp.detailLines[SH_DETAIL_MAX]:Show()
    end
  end
  -- ★1.73.42i 品阶行（渲染与断言同源的那个纯函数说了算）
  if type(shSealRowApply) == "function" then shSealRowApply() end
  -- ★★★1.73.46 摘要行（用户选定方案 B）：「标题行去掉《方案名》，下面那行带品阶色的当方案名」。
  --   ⇒ 有品阶行时标题只报「谁 + 几个技能」；**解析不出品阶**时退回带名字的旧模板（名字绝不能丢）。
  local rowH = shp.sealRow
  if rowH ~= nil and type(rowH.head) == "string" and rowH.head ~= "" then
    shp.body:SetText(string.format(L("SH_POP_GOT_NAME"), showFrom, count))
  else
    shp.body:SetText(string.format(L("SH_POP_GOT"), showFrom, nameTxt, count))
  end
  shp.root:Show()
end

-- ★1.71.2（第十六轮）**删除 EVAL_SHARE_RECV_LABEL**（原先在这里）。
--   它唯一的作用是刷新那个「接收:开/关」按钮的文字，而那个按钮本轮已被用户要求删掉
--   （它与开关组的「接收方案」是同一个开关）→ 调用点归零，成为**孤儿函数**。
--   ★为什么必须删而不是留着：本项目刚刚才吃到一次「留着一份描述旧状态的代码」的亏
--     （见 EvalHelp.lua 里那段 `cfgWin.nav = nil` 的残留：按钮真的建了、登记却被清空，
--       而读它的测试钩子无人调用 → 整整几轮没人发现）。孤儿代码会让人以为「这块还有功能」。
--   ★若将来又需要「在某个按钮上显示接收开关状态」，照下面两行重写即可：
--     EVAL_SHARE_RECV_ON() 读当前值；文字用 string.format(L("SH_RECV"), L("SH_ON"/"SH_OFF"))。

-- ★1.71.2 测试钩子：弹窗**当前实际显示**的文本（标题行 + 详情行）。
--   用途：验「详情真的填进去了」。★必须读控件当前文本（走真实渲染），
--   不能只断言 SH.pending.text 里有内容——那是数据侧，与「有没有显示」是两件事。
function EVAL_TEST_SHARE_POPUP_TEXTS()
  local t = {}
  if shp.body then
    local okb, tb = pcall(shp.body.GetText, shp.body)
    if okb and type(tb) == "string" and tb ~= "" then table.insert(t, tb) end
  end
  for _, fs in ipairs(shp.detailLines or {}) do
    local okS, shown = pcall(fs.IsShown, fs)
    if okS and shown then
      local okt, txt = pcall(fs.GetText, fs)
      if okt and type(txt) == "string" and txt ~= "" then table.insert(t, txt) end
    end
  end
  return t
end

-- 测试观察口
-- ★1.71.3 接收规则的测试观测口：在途笔数 / 去重表条数 / **生产代码真用的上限值**
--   ★上限值必须从生产代码读（断言里写死常量 = 测试在测自己，本项目已踩过）。
function EVAL_TEST_SHARE_BUF_COUNT()
  local c = 0
  for _ in pairs(SH.buf) do c = c + 1 end
  return c
end
function EVAL_TEST_SHARE_DONE_COUNT()
  local c = 0
  for _ in pairs(SH.done) do c = c + 1 end
  return c
end
-- 也回调提示限频器的状态（断言需要在用例之间重置它，避免跨用例残留）
function EVAL_TEST_SHARE_RESET_WARN() shWarnLast = 0 shWarnSkip = 0 end
function EVAL_TEST_SHARE_LIMITS()
  return { buf = SH_MAX_BUF, chunks = SH_MAX_CHUNKS, text = SH_MAX_TEXT, done = SH_MAX_DONE, gap = SH_WARN_GAP }
end
-- ★1.71.3 观测口：弹窗详情行的**原始文本**（含被 Hide 的行）——
--   只读 IsShown 的行会漏掉「Hide 了但文本还留着」这种残留（本客户端 Hide 后仍可能被绘出）。
function EVAL_TEST_SHARE_DETAIL_RAW()
  local t = {}
  for _, fs in ipairs(shp.detailLines or {}) do
    local okt, txt = pcall(fs.GetText, fs)
    table.insert(t, (okt and type(txt) == "string") and txt or "")
  end
  return t
end

-- ★1.71.3 弹窗底部一行的位置/宽度（读**真实控件**；窗口宽也读真实控件）
-- ★1.73.14 三段版：勾选框 + [导入] + [忽略] —— 把勾选框与它标签的几何也交出来，
--   断言才能验「**三段整组**以窗口中线对齐」+「三段互不重叠」（而不是只验两个按钮）。
function EVAL_TEST_SHARE_BTN_POS()
  local out = { x1 = nil, x2 = nil, w = 0, W = 0, sx = nil, sw = 0, lw = 0 }
  if not shp.root then return out end
  local okW, ww = pcall(shp.root.GetWidth, shp.root)
  if okW and type(ww) == "number" then out.W = ww end
  local list = { shp.importBtn, shp.ignoreBtn }
  for i = 1, 2 do
    local b = list[i]
    if b then
      local okl, l = pcall(b.GetLeft, b)
      local okw, bw = pcall(b.GetWidth, b)
      if okl and type(l) == "number" then out["x" .. i] = l end
      if i == 1 and okw and type(bw) == "number" then out.w = bw end
    end
  end
  -- ★1.73.14 底部一行的**布局真值**（生产算出来的那些数）+ 两枚按钮的真实几何：
  --   断言用「生产数字」验整组居中（不写死坐标），再用「真实控件」验这些数字**真的落到了控件上**。
  out.rowX0 = shp.rowX0    -- 整行左起点（算出来的）
  out.rowW = shp.rowW      -- 整行总宽（勾选框段 + 缝 + 按钮 + 缝 + 按钮）
  out.chkW = shp.chkW      -- 勾选框整段宽（16 框 + 6 缝 + 标签实测宽）
  out.btnW = shp.btnW      -- 单个按钮宽
  out.btnGap = shp.btnGap  -- 缝
  if shp.recvChk then
    local okl, l = pcall(shp.recvChk.GetLeft, shp.recvChk)
    if okl and type(l) == "number" then out.sx = l end
  end
  return out
end
-- ★1.73.14 勾选框读值口：真实控件 + 真实勾选态（断言要读它，不读自己拼的状态）
function EVAL_TEST_SHARE_RECV_CHK()
  local mark = nil
  if shp.recvChk then
    local okm, m = pcall(shp.recvChk.GetChildren, shp.recvChk) -- 兜底：拿不到就直接用闭包记录的那个
    mark = shp.recvMark
  end
  return shp.recvChk, mark, shp.recvLbl
end
-- ★1.73.14 让测试驱动「弹窗显示时刷新勾选态」（与真实显示路径同一个函数）
function EVAL_TEST_SHARE_RECV_REFRESH()
  if type(shp.recvRefresh) == "function" then shp.recvRefresh() end
end
-- ★1.71.3 弹窗标题图标的**实际纹理**（读控件，不读常量——否则测的是「写死的字符串」而不是「画出来的东西」）
function EVAL_TEST_SHARE_TITLE_ICON()
  if not shp.titleIcon then return nil end
  local ok, t = pcall(shp.titleIcon.GetTexture, shp.titleIcon)
  return ok and t or nil
end
-- ★★★1.73.42i 品阶栏读值口：图标的**实际纹理** + 三行的**实际文本** + 几何真值。
--   ★断言必须读**真控件**（GetTexture/GetText）——只读自己算出来的那个 row 表等于在测自己。
function EVAL_TEST_SHARE_SEAL_ROW()
  local out = { icon = nil, head = nil, meta = nil, comment = nil, shown = false,
                tier = nil, rank = nil, score = nil,
                sealY = shp.sealY, sealH = shp.sealH, detailY1 = shp.detailY1,
                detailYN = shp.detailYN, btnTop = shp.btnTop, H = shp.H, W = nil }
  if shp.root then
    local okw, wv = pcall(shp.root.GetWidth, shp.root)
    if okw and type(wv) == "number" then out.W = wv end
  end
  if shp.sealIcon then
    local okt, tv = pcall(shp.sealIcon.GetTexture, shp.sealIcon)
    out.icon = (okt and type(tv) == "string") and tv or nil
    local oks, sv = pcall(shp.sealIcon.IsShown, shp.sealIcon)
    out.shown = (oks and sv) and true or false
  end
  local function rd(fs)
    if not fs then return nil end
    local okt, tv = pcall(fs.GetText, fs)
    if okt and type(tv) == "string" then return tv end
    return nil
  end
  out.head, out.meta, out.comment = rd(shp.sealHead), rd(shp.sealMeta), rd(shp.sealComment)
  -- ★1.73.43d 可见性也要交出来（用户要求「这块不显示」→ 判据必须读真控件的 IsShown，不看我们自己的意图）
  local function shownOf(f)
    -- ★1.73.46 控件已被**整个删除**（红框那两行）→ 「不存在」就等于「没显示」，返回 false 而不是 nil
    if not f then return false end
    if type(f.IsShown) ~= "function" then return nil end
    local ok, v = pcall(f.IsShown, f)
    -- ★★★`and/or` 链**没有布尔语义**（本项目 1.70.46 / 1.73.15 两次踩过）：
    --   `ok and (v and true or false) or nil` 在 v=false 时会**返回 nil** → 必须显式分步判。
    if not ok or v == nil then return nil end
    if v then return true end
    return false
  end
  out.iconShown, out.headShown = shownOf(shp.sealIcon), shownOf(shp.sealHead)
  out.metaShown, out.commentShown = shownOf(shp.sealMeta), shownOf(shp.sealComment)
  local r = shp.sealRow
  if type(r) == "table" then
    out.tier, out.rank, out.score = r.tier, r.rank, r.score
    -- ★1.73.42k 判据要验「境界是**方案算的**还是退回来信的」→ 来源与配色也要交出来
    out.rankFrom, out.rankColor, out.rankIdx = r.rankFrom, r.rankColor, r.rankIdx
  end
  return out
end
-- ★★★1.73.46 点击封皮链接 → **弹出「方案分享」窗，让玩家自己确认**（用户：「点击分享链接需要弹出方案分享,
--   让用户自己确认.不要自动导入.」）。
--   ★旧行为（1.73.42g）是**点一下就直接写进方案库** —— 一个没有确认的写操作：点错、误点、被别人的链接勾一下，
--     方案库就变了，用户无从反悔。新行为**只读**：把那一份取出来弹窗，[导入] 仍是唯一写入路径（用户自己按）。
--   ★查不到就**如实说**（沿用 SH_CLICK_MISS），绝不静默。
function EVAL_SHARE_CLICK_OPEN(link)
  local id = string.match(tostring(link or ""), "^EHPF:(%x+)")
  if not id then return false end
  local hit = nil
  for i = table.getn(SH.recentList or {}), 1, -1 do
    local k = SH.recentList[i]
    if k and string.sub(k, -string.len(id)) == id then hit = SH.recent[k] break end
  end
  if not hit then
    shSay(L("SH_CLICK_MISS"))
    return false
  end
  EVAL_SH_POPUP(hit.sender, hit.text, hit.ev, id) -- ★只弹窗；导入由弹窗里的 [导入] 按钮触发
  shSay(L("SH_CLICK_OPEN"))
  return true
end
function EVAL_SHARE_SEAL_STATE()
  return { last = SH.sealSentLast or SH.sealLast, first = SH.sealSentFirst, recvLast = SH.sealRecvLast,
           pending = (SH.sealPendA ~= nil or SH.sealPendB ~= nil),
           seals = SH.sealSeen or 0, meta = SH.sealMeta or {} } -- ★1.73.42i meta 供判据读；★1.73.43b 收发分开（境界/评语真的解析到了没）
end
function EVAL_SHARE_RECENT_STATE()
  return { list = SH.recentList or {}, recent = SH.recent or {}, seals = SH.sealSeen or 0, lastSeal = SH.sealLast }
end
function EVAL_TEST_SHARE_BUILD() return shBodies() end
-- ★队列里的**分片**数（v1 明文 + v2 链接两种形态都算；封皮不进队列）
function EVAL_TEST_SHARE_QUEUE_CHUNKS()
  local c = 0
  for q = 1, table.getn(shTxQ) do
    -- ★1.73.43f 分享信息那条**不是分片**（带 seal 标记）→ 不计数（否则「队列里正好 N 片」这类判据会多算一条）
    if not shTxQ[q].seal then
      local bd = tostring(shTxQ[q].body or "")
      if string.sub(bd, 1, 6) == "[EHPF#" or string.find(bd, "|HEHPF:", 1, true) then c = c + 1 end
    end
  end
  return c
end
function EVAL_SHARE_PENDING() return SH.pending end
function EVAL_SHARE_RESET()
  -- ★1.73.43f **发送侧也一起重置**：队列里可能还压着「分享信息」那一条（它在分片之后），
  --   只按 id 数分片的滴干循环会把这条**留在队列里**，下一个用例就会把它当成自己的第一片（真机上=串包，测试里=判据假红）。
  shTxQ = {}
  SH.sealPendA, SH.sealPendB = nil, nil
SH.buf = {} SH.done = {} SH.doneList = {} SH.pending = nil SH.recent = {} SH.recentList = {} SH.sealMeta = {} end -- ★1.73.42i 封皮元数据也清（跨用例不许残留）
-- ★1.71.2 测试钩子：按分享弹窗的 [导入] 按钮（走它自己的 OnClick 闭包）。
--   用户报的 bug 正是这条路径漏了刷新——直调 EVAL_IMPORT_TEXT 会绕过它、测不出来。
function EVAL_TEST_SHARE_SELF_SKIPPED() return SH.selfSkipped or 0 end
function EVAL_TEST_SHARE_CLICK_IGNORE()
  if not (shp.ignoreBtn and shp.ignoreBtn.GetScript) then return false end
  local fn = shp.ignoreBtn:GetScript("OnClick")
  if not fn then return false end
  fn()
  return true
end
function EVAL_TEST_SHARE_CLICK_IMPORT()
  if not (shp.importBtn and shp.importBtn.GetScript) then return false end
  local fn = shp.importBtn:GetScript("OnClick")
  if not fn then return false end
  fn()
  return true
end
