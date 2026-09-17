-- EvalHelp —— EmberVeil（1.12.1 / Lua 5.1）全职业施法工具
--   通用一键宏（条件规则引擎）+ 案例模版 + 方案分享 + 状态日志 + 战斗信息UI + 配置窗口
--   （配置窗内嵌 工具箱 / 数据检索 / 图标库 三个 Tab）。
--   ★版本号只有**两处**：本文件的 local VERSION 与 EvalHelp.toc 的 ## Version ——
--     由 test_engine.js 的 VERSION CHECK 守着（两侧必须一致）。
--     ★文件头**不再写版本号**：旧写法（「-- EvalHelp 1.70.44」）实际漂移了十几个版本都没人发现，
--       因为源码检查只比对 local VERSION 与 toc —— 同一件事写三遍必然漂移。
--   ★逐版本变更**不写在这里**：完整记录见 CHANGELOG.md 与 git log；设计与判据见 CLAUDE.md（记忆体）。
--
-- 参考 OneJudge 开发流程的关键约定：
--   1) 目录规则：Interface/AddOns/EvalHelp/EvalHelp.toc（文件夹名 == toc 基名）
--   2) 插件暴露全局函数，一键宏正文就一行：/run EVAL_GO()
--   3) 本客户端判断函数返回 true/false/nil（不是老 1.12 的 1/nil），必须宽松真值判断，
--      旧写法 UnitAffectingCombat("player") == 1 在 true 面前永远判假！
--   4) 配置用 SavedVariables（EVAL_HELP_CONFIG），要等 VARIABLES_LOADED 事件后才读。
--   5) 聊天输出用 DEFAULT_CHAT_FRAME:AddMessage；调试日志走 SavedVariables 环形缓冲（Core.lua）
--      （日志在 %LOCALAPPDATA%\Azeroth\Saved\Logs 下，不刷聊天框）。
--   6) 本客户端没有 /startattack、/castsequence；插件不能调 Protected 函数
--      （CastSpellByName 等），施法走 UseAction(动作条格子)。
--
-- 用法（/eh help 随时查看）：
--   一键宏：游戏内新建宏，正文一行  /run EVAL_GO()   拖到按键上连按（全职业通用框架）
--     前置：把 攻击/战斗姿态/冲锋/压制/断筋/撕裂/战斗怒吼/血性狂暴/猛击/英勇打击 拖上动作条，
--           然后 /eh go rescan 让插件识别槽位（/eh go 查看识别结果）
--     猛击需按住 Alt 再按宏键（本客户端无挥击计时 API，用 Alt 代替出手时机）
--   配置：小地图左侧金色 EH 图标 或 /eh cfg —— 日志开关、一键开关、怒气/血量阈值滑条
--   战斗信息UI：/eh ui —— 血/能量/目标条 + 技能图标行，按住标题栏拖动，滚轮缩放
--   状态信息UI：/eh st —— Cat 式角色状态变量总览（EVAL_HELP_STATE 实时值）
--   其他命令：/eh 输出状态日志 | /eh log 写日志开关 | /eh auto 进出战斗自动输出
--   调试日志：/eh logdump 查看（SavedVariables 环形缓冲；/eh wdebug 后聊天框同步显示决策原因）

local VERSION = "1.71.16"
local cfg = nil -- VARIABLES_LOADED 后指向 EVAL_HELP_CONFIG

-- ===== 跨模块别名（Core.lua / Engine.lua 先于本文件加载，见 toc） =====
local say, logLine = EVAL_SAY, EVAL_LOGLINE
local L = EVAL_L
local st = EVAL_HELP_STATE
local uiOffscreen = EVAL_UIOFFSCREEN
local powerLabel, currentForm = EVAL_POWERLABEL, EVAL_CURRENTFORM
local formatStats, collectStats = EVAL_FORMAT_STATS, EVAL_COLLECT_STATS
local autoFrame, onCombatEvent = EVAL_AUTOFRAME, EVAL_ON_COMBAT
local ehResolveLang = EVAL_RESOLVE_LANG
local wslots = EVAL_WSLOTS
local wicon = EVAL_WICON
local groupsOK = EVAL_GROUPS_OK
local auraTexOf = EVAL_AURA_TEX
local petCmdOf, targetSelOf, itemOf = EVAL_PET_OF, EVAL_TGT_OF, EVAL_ITEM_OF
local stanceOf = EVAL_STANCE_OF -- 1.43.0 姿态切换（姿态:名称）
local condTrim = EVAL_COND_TRIM -- 1.44.0 拆分漏桥补
local colonNorm = EVAL_COLON_NORM -- ★1.71.3 全角冒号归一（导入文本里用户可能打全角）：EVAL_PROFILE_FROM_TEXT 用裸 condTrim（旧例一直缺别名，游戏内点导入必炸）
local cancelCastOf = EVAL_CANCELCAST_OF -- 1.47.0 取消施法特殊行为
local stopAllOf = EVAL_STOPALL_OF -- 1.71.3 停止攻击特殊行为
local followOf = EVAL_FOLLOW_OF -- ★1.71.3 跟随特殊行为（同样不占动作条：亮金/分类/候选列表都要按它处理）
local tselTeam = EVAL_TSEL_TEAMSEL -- ★1.71.3 条件类型下拉要按「这一行是不是成员选取器」过滤
-- ★★★1.71.3 状态标记（全插件共用的**单一来源**）：白感叹号 = 不可用、黄感叹号 = 待测试。
--   用户要求：「右边换成**插件图标内的白色感叹号**」＋「启用此技能 右侧添加几个图标 寓意 tooltip：
--   白色感叹号 不可用 / 黄色感叹号 待测试」。
--   ★「取消施法」为什么是**不可用**：官方 API 里停止读条**只有 SpellStopCasting 一个**且标注为
--     【Protected: yes】——插件调用只清本地读条条、**服务端读条照旧**（详见 CLAUDE.md 1.71.3 该条）。
--   ★为什么是这两张图：它们本来就在本插件的 media\icons\ 里（UnrealQuest 那套任务标记，MIT）：
--     白色=低等级、黄色=普通，正是现成的「! 形标记」美术——不必再画、也不引入外部依赖。
--   ★★为什么另存两个**正方形**文件（mark-unavail / mark-test）：原图是 27x64 / 19x32 的细长条，
--     直接塞进 12x12 方格里会被**横向压扁**（本项目「宽高比」那一族事故）→ 转成方图后，
--     任何方格槽位直接 SetTexture 就是正确比例，代码里不用再算 SetTexCoord。
local SE_MEDIA_ROOT = "Interface\\AddOns\\EvalHelp\\media\\icons\\"
local SE_MARK_UNAVAIL = SE_MEDIA_ROOT .. "mark-unavail" -- 白感叹号：不可用
local SE_MARK_TEST = SE_MEDIA_ROOT .. "mark-test"       -- 黄感叹号：待测试
-- ★「取消施法」的异常标记用它（用户要求：把行右侧那个问号换成白感叹号）。
local SE_WARN_ICON = SE_MARK_UNAVAIL
local TARGET_SEL, TARGET_SEL_NAME = EVAL_TARGET_SEL, EVAL_TSEL_NAME
local CLASS_LIST = EVAL_CLASS_LIST
-- ============ 状态 UI（参考 Cat 的 CatUI-Melee 布局，构件法用 OneJudge HUD 的已验证写法） ============
-- /eh ui 开关窗口；按住顶部标题栏拖动换位置（自动记忆）；悬停滚轮缩放（0.5~1.6，自动重建）。
-- 内容：血条 / 能量条（怒气红·法力蓝·能量黄）/ 目标条 / 状态行 / 技能图标行。
-- 刷新：OnUpdate 每 0.15s 一次，窗口隐藏时不刷新（Cat 的 MPCatUIMeleeRun 同款节流）。
-- 注意（OneJudge 实测教训）：不用 SetScale（会引发命中区/位置漂移），缩放 = 几何尺寸 × 系数后重建；
--      不用 StatusBar 控件，用纯色 Texture 按宽度填充；字体按 FZLBJW→FRIZQT→ARIALN 顺序尝试。

local ui = { root = nil }
local UI_TICK = 0.15
local uiLastTick = 0

local function uiCfg()
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  if not cfg.ui then cfg.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
  return cfg.ui
end

-- 纯色纹理：SetTexture(RGB) 本客户端未文档化，先按颜色试，失败退回官方底图+顶点色（OneJudge 同款）
local function uiSolid(t, r, g, b, a)
  local ok = pcall(t.SetTexture, t, r, g, b)
  if not ok then
    pcall(t.SetTexture, t, "Interface\\Buttons\\WHITE8X8")
    pcall(t.SetVertexColor, t, r, g, b, a or 1)
  end
end

-- 字体字符串：中文字体优先（FZLBJW=方正隶变），失败逐级回退
-- 1.61.2 显示转义：| 在 FontString/聊天框里是颜色转义符，单个 | 会被吞；|| 转义在本客户端渲染异常（小方块）——
-- 改用全角竖线 ｜（U+FF5C，FZLBJW 中文字体自带全角字符，视觉与 | 一致）。数据层不受影响
local function uiEsc(s) return (string.gsub(tostring(s or ""), "|", "｜")) end

local function uiText(parent, size, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local set = false
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    local okF, ok2 = pcall(fs.SetFont, fs, fp, size, "OUTLINE")
    if not (okF and ok2) then okF, ok2 = pcall(fs.SetFont, fs, fp, size) end
    if okF and ok2 then set = true break end
  end
  if not set then pcall(fs.SetTextHeight, fs, size) end
  fs:SetTextColor(r, g, b)
  return fs
end

-- 一条状态条：深色底框 + 彩色填充层（宽度=比例）+ 居中文字
local function uiMakeBar(parent, w, h)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetWidth(w) bar:SetHeight(h)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.08, 0.08, 0.10, 0.9)
  bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  local fill = bar:CreateTexture(nil, "ARTWORK")
  uiSolid(fill, 0.5, 0.5, 0.5, 1)
  -- ★★★1.71.2（第二十轮）用户实测：「战斗信息 生命条 有阴影」——就是这三行。
  --   旧写法让彩色填充层**内缩 1px**（锚点 +1,-1、高度 h-2、可用宽 w-2）→
  --   满血时四周露出一圈近黑的底（0.08,0.08,0.10@0.9），看着就像描边/阴影。
  --   ★三处**必须同时改**：只改锚点与高度的话，满血时右侧仍留 2px 空隙（下面返回的 w 也是修复的一部分）。
  --   ★深色底**不删**——它仍是「未填充部分」，掉血后那条空槽照样看得见（用户要的是去掉那圈边）。
  fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  fill:SetHeight(h)
  pcall(fill.SetWidth, fill, 1)
  local text = uiText(bar, math.max(8, h - 6), 1, 1, 1)
  text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  -- ★1.71.2（第二十轮）返回的可用宽度改为 **w**（原 w-2，是配合 1px 内缩的）：
  --   填充层现在铺满整条，满值时就该占满条宽——否则右侧仍会留 2px 的深色缝。
  return bar, fill, text, w
end

-- 技能图标行（1.45.0 起）：内容以【激活方案的技能】为准，旧版固定战士清单（UI_ICONS）已废弃

-- 方案配置访问（配置段的 warCfg 在本段之后定义，这里直接走全局 SavedVariables + 迁移函数）
local function uiWarCfg()
  local cc = EVAL_HELP_CONFIG
  if type(cc) ~= "table" then cc = {} EVAL_HELP_CONFIG = cc end
  if type(cc.war) ~= "table" then cc.war = {} end
  EVAL_WAR_ENSURE_PROFILES(cc.war)
  return cc.war
end

-- 当前方案第 i 条规则（技能编辑窗/方案技能行共用）
local function uiWarActiveRule(i)
  local w2 = uiWarCfg()
  local p = w2.profiles and w2.profiles[w2.activeProfile or 1]
  return (p and p.skills) and p.skills[i] or nil
end

-- 重建/新建战斗信息UI（改缩放时整帧重建，见上方 SetScale 说明）
function EVAL_HELP_UI_BUILD()
  local u = uiCfg()
  local z = (type(u.scale) == "number" and u.scale >= 0.4) and u.scale or 1
  if ui.root then
    ui.root:Hide()
    pcall(ui.root.SetScript, ui.root, "OnUpdate", nil)
  end

  -- ★★★1.71.12 子开关「战斗 / 方案」= 关时对应区块**整块不画** → 这里必须先清掉上一轮的引用：
  --   ui 表是**复用**的（不是每轮新建），不清就会留下**上一轮控件**的引用，
  --   而 tick 里的存在性判据（`if ui.castBar then` / `if ui.profCells then`）会照样成立 → **写幽灵控件**。
  --   （与「桩有错状态比桩没状态更隐蔽」同族：留存的是旧状态，不是缺失。）
  ui.hpFill, ui.hpText, ui.hpW = nil, nil, nil
  ui.pwFill, ui.pwText, ui.pwW = nil, nil, nil
  ui.tgBar, ui.tgFill, ui.tgText, ui.tgW = nil, nil, nil, nil
  ui.tgRange, ui.status, ui.comboSegs = nil, nil, nil
  ui.castBar, ui.castFill, ui.castText, ui.castW = nil, nil, nil, nil
  ui.swingBar, ui.swingFill, ui.swingText, ui.swingW = nil, nil, nil, nil
  ui.profBtns, ui.profCells = nil, nil
  ui.profRows, ui.profNeed, ui.profAvail, ui.profPad, ui.profCap, ui.profSig = nil, nil, nil, nil, nil, nil

  local root = CreateFrame("Frame", "EVAL_HELP_UI", UIParent)
  pcall(root.SetFrameStrata, root, "MEDIUM")
  pcall(root.SetFrameLevel, root, 10)
  pcall(root.EnableMouse, root, true)   -- 本体只接收滚轮（缩放），不注册拖动
  pcall(root.SetMovable, root, true)

  local W = math.floor(240 * z)
  local pad = math.floor(8 * z)
  local barH = math.floor(14 * z)
  local gap = math.floor(4 * z)
  local cell = math.floor(26 * z)

  -- 标题栏 = 拖动手柄：只有按住标题条才能拖动窗口（需求 1）。
  -- UnrealQuest 实测五件套：Handle 必须是【Button】（Frame 的拖拽在本客户端不触发）、
  -- SetFrameLevel 抬高 +10（用 strata 抬高是记录在案的失败做法）、EnableMouse、
  -- RegisterForClicks、RegisterForDrag。
  local titleBarH = math.floor(16 * z)
  local titleBar = CreateFrame("Button", nil, root)
  -- 标题条与内容条同宽（内缩 pad；1.20.1 修复标题条两边超出内容区的问题）
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, 0)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -pad, 0)
  titleBar:SetHeight(titleBarH)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10)
  end
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 0.95)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, math.max(9, math.floor(11 * z)), 0.9, 0.8, 0.4)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  -- ★1.71.12 用户要求：「战斗信息 标题换成 用户名字」。
  --   ★取不到名字要**如实退回**旧文案（载入极早期 / 某些客户端 UnitName 可能给 nil 或空串）——
  --     直接 SetText(nil) 会让标题栏空着，比旧文案更糟。
  local pname = UnitName("player")
  if type(pname) ~= "string" or pname == "" then pname = L("G_UI_TITLE") end
  title:SetText(pname)

  -- ★★★1.71.12 用户要求：「战斗信息UI 再加2个子选项，战斗、方案，分开控制显示和隐藏。」
  --   ★语义：**nil = 开**（老配置里没有这两个键 → 行为与旧版逐字一致）；只有显式 false 才不画。
  --   ★为什么是「不画」而不是「画完再 Hide」：布局 y 必须随之前移（否则留一条空白带），帧高也要跟着变
  --     ——Hide 做不到这两件事（本项目「隐藏 = 不画」的既有判据，黑块那轮的教训）。
  --   ★两个区块各自独立：`战斗` = 血/能量/连击/目标条 + 读条 + 挥击条 + 状态行；
  --     `方案` = 方案切换行 + 技能图标带。
  local subCombat = (u.subCombat ~= false)
  local subScheme = (u.subScheme ~= false)

  -- 三条状态条：血 / 能量 / 目标（子开关「战斗」关掉时整块不画）
  local y = titleBarH + gap
  if subCombat then -- ★1.71.12 子开关「战斗」：关 = 血/能量/目标/读条/挥击/状态行整块不画
    local barW = W - pad * 2
    local hpBar, hpFill, hpText, hpW = uiMakeBar(root, barW, barH)
    hpBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + barH + gap
    local pwBar, pwFill, pwText, pwW = uiMakeBar(root, barW, barH)
    pwBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + barH + gap
    -- 连击点条（1.67.0，贼/德专属）：能量条下方一行 5 等宽小块——激活高亮金填充、未激活浅灰
    local comboSegs = nil
    do
      local okc, _cl, clsTok = pcall(UnitClass, "player")
      if clsTok == "ROGUE" or clsTok == "DRUID" then
        comboSegs = {}
        local segGap = 2
        local segW = math.floor((barW - segGap * 4) / 5)
        local segH = math.max(5, math.floor(7 * z))
        for ci = 1, 5 do
          local seg = root:CreateTexture(nil, "ARTWORK")
          uiSolid(seg, 0.25, 0.25, 0.25, 1)
          seg:SetWidth(segW) seg:SetHeight(segH)
          seg:SetPoint("TOPLEFT", root, "TOPLEFT", pad + (ci - 1) * (segW + segGap), -y)
          comboSegs[ci] = seg
        end
        y = y + segH + gap
      end
    end
    ui.comboSegs = comboSegs
    local tgBar, tgFill, tgText, tgW = uiMakeBar(root, barW, barH)
    tgBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + barH + gap

    -- 状态行：战斗状态 · 姿态 · 普攻
    local status = uiText(root, math.max(8, math.floor(10 * z)), 0.75, 0.75, 0.75)
    -- 施法读条（1.38.1）：目标条下方细条，仅读条中显示（进度=剩余/总时长，反向填充=正在消耗的时间）
    local castBar, castFill, castText, castW = uiMakeBar(root, barW, math.max(6, math.floor(8 * z)))
    castBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + math.max(6, math.floor(8 * z)) + gap
    ui.castBar, ui.castFill, ui.castText, ui.castW = castBar, castFill, castText, castW
    -- 挥击计时条（1.55.0）：读条下方细条——进度=距下次挥击（自学习锚点+攻速），金色
    local swBar, swFill, swText, swW = uiMakeBar(root, barW, math.max(6, math.floor(8 * z)))
    swBar:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + math.max(6, math.floor(8 * z)) + gap
    ui.swingBar, ui.swingFill, ui.swingText, ui.swingW = swBar, swFill, swText, swW
    status:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    y = y + math.floor(13 * z) + gap
    -- 目标距离文本（1.37.0）：目标条右缘（近战/冲锋距/远程外，EVAL_T_RANGE 分档）
    local tgRange = uiText(tgBar, math.max(8, math.floor(9 * z)), 1, 0.85, 0.4)
    tgRange:SetPoint("RIGHT", tgBar, "RIGHT", -4, 0)
    pcall(tgRange.SetJustifyH, tgRange, "RIGHT")
    ui.tgRange = tgRange
    -- ★★★1.71.12 这些 `ui.*` 赋值必须在**块内**：子开关「战斗」= 关时控件根本不建，
    --   块外再赋值就会把「这一轮没建」这件事盖掉（见 BUILD 开头的清空说明）。
    ui.hpFill, ui.hpText, ui.hpW = hpFill, hpText, hpW
    ui.pwFill, ui.pwText, ui.pwW = pwFill, pwText, pwW
    ui.tgBar, ui.tgFill, ui.tgText, ui.tgW = tgBar, tgFill, tgText, tgW
    ui.status = status
  end

  if subScheme then -- ★1.71.12 子开关「方案」：关 = 方案行与技能图标带整块不画（布局随之前移）
    -- 方案切换行：点击按钮换激活方案（一键宏立即换套路；Shift+按宏 / /eh go next 也可切）
    -- 1.56.0 自适应布局：行宽与上方状态条对齐（右缘一致）；方案多时自动换行。
    -- ★★★1.71.10 用户实测「有些方案会溢出宽度」——根因是**按钮宽度按行均分**（同一行所有按钮一样宽）：
    --   长名字（如「一键团队驱散」）撑破自己的按钮、压在邻居上。现改为**按名字实测宽度**分配：
    --     · 每格宽 = 量宽(名字) + 内边距，夹在 [minBW, 整行可用宽] 之间；
    --     · 按可用宽**贪心换行**（首行扣掉「方案」标签宽）；
    --     · 每行剩余空间**均摊**回该行按钮 —— 保住 1.56.0 的「每行填满」观感；
    --     · 文字格显式限宽 + 禁折行（名字极长时在自己的按钮里裁掉，不再压邻居）。
    --   ★量宽走 ruler FontString（挪出可视区量：本客户端 Hide 过的控件仍可能被绘出）；
    --     拿不到 GetStringWidth 时退化为「中文一字约 9px」的近似（本机 API 表里没有它）。
    --   ★方案名/数量变了要重排：由 EVAL_WAR_TAB_REFRESH 比对签名后**整体重建**
    --     （重建会重算行数 → 帧高与下方技能带一起挪）；每 0.15s 的 tick 里**不量宽**（频率防护）。
    local profBtns = {}
    local w20 = uiWarCfg()
    local nProf = (w20.profiles and table.getn(w20.profiles)) or 1
    local labelW = math.floor(28 * z)
    local btnH = math.floor(15 * z)
    local barAvailW = W - pad * 2
    local minBW = math.floor(34 * z) -- 单按钮最小宽（名字可读）
    local PGAP = 2
    local plabel = uiText(root, math.max(8, math.floor(9 * z)), 0.95, 0.82, 0.35)
    plabel:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -(y + math.floor(3 * z)))
    plabel:SetText("方案")
    -- 量宽尺（与方案按钮同字号；挪出可视区，不参与显示）
    local uiRuler = uiText(root, math.max(7, math.floor(9 * z)), 0.85, 0.80, 0.70)
    pcall(uiRuler.SetPoint, uiRuler, "TOPLEFT", root, "TOPLEFT", -2000, 0)
    local function uiMeasure(s)
      s = tostring(s or "")
      local w0 = 0
      pcall(uiRuler.SetText, uiRuler, s)
      if type(uiRuler.GetStringWidth) == "function" then
        local okv, v = pcall(uiRuler.GetStringWidth, uiRuler)
        if okv and type(v) == "number" and v > 0 then w0 = v end
      end
      if w0 <= 0 then w0 = math.floor(string.len(s) / 3 + 0.5) * 9 end -- 近似：中文字一字约 9px
      return w0
    end
    local function profNeed(name) -- 一格需要多宽（实测 + 内边距；夹在 [minBW, 整行宽]）
      local w0 = uiMeasure(name) + math.floor(10 * z)
      if w0 < minBW then w0 = minBW end
      if w0 > barAvailW then w0 = barAvailW end
      return w0
    end
    local needW = {}
    for i = 1, 12 do
      local prof = w20.profiles and w20.profiles[i]
      needW[i] = profNeed(prof and prof.name or ("方案" .. tostring(i)))
    end
    -- 贪心换行 + 每行剩余**限量**均摊（余数给前几格）→ geo[i] = { x, y, w }
    --   ★★★1.71.11 用户第二轮反馈「空的太多了」：上一版把每行剩余**全部**均摊 → 一行里只有一个短名时，
    --     那个按钮被拉成一个大空框（截图红圈）。现在给每格**设上限**：最多比「名字需要宽」多 MAX_EXTRA，
    --     超出的部分**留在行尾**（宁可行尾留白，也不做空框）——★上限值可调：想要「完全按名宽」就把 MAX_EXTRA 设 0。
    local MAX_EXTRA = math.floor(24 * z)
    local geo, rowIdx, x = {}, 0, pad + labelW
    local rowItems, rowAvail = {}, barAvailW - labelW
    local function flushRow()
      local k = table.getn(rowItems)
      if k == 0 then return end
      local sumW = 0
      for _, idx in ipairs(rowItems) do sumW = sumW + needW[idx] end
      local leftover = rowAvail - (k - 1) * PGAP - sumW
      if leftover < 0 then leftover = 0 end
      local add = math.floor(leftover / k)
      local capped = false
      if add > MAX_EXTRA then add = MAX_EXTRA capped = true end
      local extra = capped and 0 or (leftover - add * k)
      local xx = (rowIdx == 0) and (pad + labelW) or pad
      for n, idx in ipairs(rowItems) do
        local wI = needW[idx] + add + ((n <= extra) and 1 or 0)
        geo[idx] = { x = xx, y = -(y + rowIdx * (btnH + PGAP)), w = wI }
        xx = xx + wI + PGAP
      end
      rowItems = {}
    end
    for i = 1, math.max(1, math.min(12, nProf)) do
      local wI = needW[i]
      if table.getn(rowItems) > 0 and x + wI > pad + barAvailW + 0.5 then
        flushRow()
        rowIdx = rowIdx + 1
        rowAvail = barAvailW
        x = pad
      end
      table.insert(rowItems, i)
      x = x + wI + PGAP
    end
    flushRow()
    local rows = rowIdx + 1
    local geoFallback = { x = pad, y = -(y + rows * (btnH + PGAP)), w = needW[nProf] or minBW }
    for i = 1, 12 do
      local g0 = geo[i] or geo[nProf] or geoFallback
      local pb = CreateFrame("Button", nil, root)
      pb:SetWidth(g0.w) pb:SetHeight(btnH)
      pb:SetPoint("TOPLEFT", root, "TOPLEFT", g0.x, g0.y)
      pcall(pb.EnableMouse, pb, true)
      pcall(pb.RegisterForClicks, pb, "LeftButtonUp", "RightButtonUp") -- 1.71.16 右键 = 绑定快捷键
      local pbg = pb:CreateTexture(nil, "BACKGROUND")
      uiSolid(pbg, 0.16, 0.13, 0.08, 1)
      pbg:SetPoint("TOPLEFT", pb, "TOPLEFT", 0, 0)
      pbg:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", 0, 0)
      local pt = uiText(pb, math.max(7, math.floor(9 * z)), 0.85, 0.80, 0.70)
      pt:SetPoint("CENTER", pb, "CENTER", 0, 0)
      pcall(pt.SetWidth, pt, g0.w - 4) -- ★限宽：极长名在自己的按钮里裁掉，不压邻居
      pcall(pt.SetNonSpaceWrap, pt, false)
      local pidx = i
      pb:SetScript("OnClick", function(a, b)
        local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
        -- ★1.71.16 用户：「战斗UI->方案单元->右键绑定任务」——右键 = 弹窗绑定该方案的快捷键（左键仍是切换）
        if mbtn == "RightButton" then
          EVAL_BIND_OPEN(pidx)
          return
        end
        local w2 = uiWarCfg()
        if w2.profiles and w2.profiles[pidx] then
          w2.activeProfile = pidx
          say("切换到方案: " .. tostring(w2.profiles[pidx].name))
        end
      end)
      profBtns[i] = { btn = pb, bg = pbg, text = pt }
    end
    ui.profRows, ui.profNeed, ui.profAvail, ui.profPad, ui.profCap = rows, needW, barAvailW, pad, MAX_EXTRA -- ★1.71.10/1.71.11 供断言读生产真值
    -- ★1.71.10 版式签名（方案名序列）：EVAL_WAR_TAB_REFRESH 比它决定「要不要重建战斗信息UI」
    --   （方案名/数量变了 → 按钮宽度与行数都得重算，帧高与下方技能带也要随之挪 → 整体重建最省心）
    local sig0 = ""
    for i = 1, table.getn((w20 and w20.profiles) or {}) do
      sig0 = sig0 .. tostring(((w20.profiles[i]) or {}).name or "") .. "|"
    end
    ui.profSig = sig0
    y = y + rows * (btnH + PGAP) + gap -- 1.56.0 多行高度（行数按名字实宽算，行数变了帧高随之变）

    -- 技能图标带（1.46.0 两行合一：内容=激活方案技能，8 格/行超过自动换第二行，最多 16 格；
    -- 悬停 tooltip 看触发条件；点击开编辑窗；亮金=条件当前满足；动作条技能带冷却倒数）
    local profCells = {}
    local pcell = math.floor(24 * z)
    local pgap2 = math.floor(3 * z)
    for i = 1, 16 do
      local row0 = math.floor((i - 1) / 8)
      local col0 = (i - 1) - row0 * 8
      local px = pad + col0 * (pcell + pgap2)
      local cb = CreateFrame("Button", nil, root)
      cb:SetWidth(pcell) cb:SetHeight(pcell)
      cb:SetPoint("TOPLEFT", root, "TOPLEFT", px, -(y + row0 * (pcell + pgap2)))
      pcall(cb.EnableMouse, cb, true)
      pcall(cb.RegisterForClicks, cb, "LeftButtonUp")
      local cbg = cb:CreateTexture(nil, "BACKGROUND")
      uiSolid(cbg, 0.45, 0.38, 0.15, 1)
      cbg:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
      cbg:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
      local cicon = cb:CreateTexture(nil, "ARTWORK")
      uiSolid(cicon, 0.2, 0.2, 0.2, 1)
      cicon:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
      cicon:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
      local ctext = uiText(cb, math.max(7, math.floor(9 * z)), 1, 1, 0.4)
      ctext:SetPoint("CENTER", cb, "CENTER", 0, 0)
      local ci = i
      cb:SetScript("OnEnter", function()
        local r = uiWarActiveRule(ci)
        if not r then return end
        GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tostring(r.skill), 1, 0.82, 0.3)
        GameTooltip:AddLine((r.enabled ~= false) and ("|cff00ff00" .. L("TIP_ON") .. "|r") or ("|cffff0000" .. L("TIP_OFF") .. "|r"))
        GameTooltip:AddLine(L("TIP_COND_H"), 0.62, 0.55, 0.40)
        local gcount = 0
        for gi, g in ipairs(r.groups or {}) do
          gcount = gi
          local cs = {}
          for _, cd in ipairs(g) do table.insert(cs, EVAL_COND_STR(cd)) end
          GameTooltip:AddLine(string.format("%d. %s", gi, table.concat(cs, " & ")), 0.85, 0.85, 0.85)
        end
        if gcount == 0 then
          GameTooltip:AddLine(L("TIP_NOCOND"), 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(L("TIP_CLICK"), 0.5, 0.5, 0.5)
        GameTooltip:Show()
      end)
      cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      cb:SetScript("OnClick", function()
        local w2 = uiWarCfg()
        local p = w2.profiles and w2.profiles[w2.activeProfile or 1]
        if p and p.skills[ci] then EVAL_HELP_SE_OPEN(w2.activeProfile or 1, ci) end
      end)
      profCells[i] = { btn = cb, bg = cbg, icon = cicon, text = ctext }
    end
    -- ★1.71.12 同上：块内赋值（子开关「方案」= 关时既没有方案按钮也没有图标格）
    ui.profBtns, ui.profCells = profBtns, profCells -- 1.46.0 技能带=profCells（两行合一，ui.cells 已废）
    y = y + 2 * (pcell + pgap2) + pad -- 固定预留两行高度（空位刷新时整格隐藏，窗口尺寸稳定）
  else
    y = y + pad -- 方案块不画时只留底部内边距（否则内容贴着标题栏下缘）
  end

  root:SetWidth(W)
  root:SetHeight(y)
  root:ClearAllPoints()
  root:SetPoint("CENTER", UIParent, "CENTER", u.x or 0, u.y or -180)
  if uiOffscreen(root) then -- 记忆位置飞出屏幕 → 回归视野中心
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    u.x, u.y = 0, -180
  end

  -- 按住标题栏拖动换位置，松手记坐标（GetCenter 已含 effectiveScale，要除回去——OneJudge 1.7.2 的修复）
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, cx, cy = pcall(root.GetCenter, root)
    if ok and cx then
      local okw, w2 = pcall(UIParent.GetWidth, UIParent)
      local okh, h2 = pcall(UIParent.GetHeight, UIParent)
      if okw and okh and w2 and h2 then
        local oke, es = pcall(root.GetEffectiveScale, root)
        local k = (oke and type(es) == "number" and es > 0) and es or 1
        u.x = (cx - w2 / 2) / k
        u.y = (cy - h2 / 2) / k
      end
    end
  end)

  -- 悬停滚轮缩放（EnableMouseWheel 本客户端可能缺，全程 pcall——OneJudge 1.7.2 教训）
  if pcall(root.EnableMouseWheel, root, true) then
    pcall(root.SetScript, root, "OnMouseWheel", function(a, b)
      local d = 0
      if type(b) == "number" then d = b
      elseif type(a) == "number" then d = a
      elseif type(arg1) == "number" then d = arg1 end
      if d == 0 then return end
      local s = (u.scale or 1) + (d > 0 and 0.1 or -0.1)
      s = math.min(1.6, math.max(0.5, s))
      if math.abs(s - (u.scale or 1)) > 1e-9 then
        u.scale = s
        EVAL_HELP_UI_BUILD()
        if ui.root then ui.root:Show() end
      end
    end)
  end

  ui.root, ui.title = root, title
  -- ★1.71.12 子开关的**真实生效值**留在 ui 上：tick 只认这两个标志（且不每帧回读配置）。
  ui.combatOn, ui.schemeOn = subCombat, subScheme

  root:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - uiLastTick < UI_TICK then return end
    uiLastTick = now
    EVAL_HELP_UI_TICK()
  end)
end

-- 填充条刷新工具
local function uiSetBar(fill, text, maxW, frac, r, g, b, str)
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  pcall(fill.SetWidth, fill, math.max(1, maxW * frac))
  pcall(fill.SetVertexColor, fill, r, g, b, 1)
  text:SetText(str)
end

-- 每个心跳刷新（窗口隐藏时直接返回——Cat 同款）
function EVAL_HELP_UI_TICK()
  if not ui.root or not ui.root:IsVisible() then return end

  -- 统一走角色状态表（每次心跳刷新一次，之后只读变量——Cat 思路）
  EVAL_HELP_UPDATE_STATE()

  -- ★1.71.12 普攻判定**前置**：它写的是 `st.autoAttack`（状态表的一部分，规则引擎要用），
  --   所以**不能**跟着「战斗区画不画」一起被跳过（子开关只决定画不画，不改变状态）。
  local atkOn = false
  if wslots["攻击"] and type(IsCurrentAction) == "function" then
    local oka, cur = pcall(IsCurrentAction, wslots["攻击"].slot)
    atkOn = oka and cur and true or false
  end
  st.autoAttack = atkOn -- 同步进状态表（Cat 的 MPAutoAttack）

  -- ★1.71.12 子开关「战斗」= 关时这些控件**根本不存在**（ui.hpFill 等为 nil）→ 整段一起跳过。
  --   ★判据用 `ui.combatOn`（BUILD 时定下的标志），**不是**每帧回读配置——配置只在重建时才生效。
  if ui.combatOn then
  -- 血条：绿→红渐变
  local hfrac = (st.hpMax and st.hpMax > 0) and (st.hp / st.hpMax) or 0
  uiSetBar(ui.hpFill, ui.hpText, ui.hpW, hfrac, 1 - hfrac, hfrac, 0.15,
    string.format("%d/%d  %d%%", st.hp, st.hpMax, math.floor(hfrac * 100 + 0.5)))

  -- 能量条：按能量类型配色（0法力蓝 1怒气红 2集中橙 3能量黄）
  local pfrac = (st.powerMax and st.powerMax > 0) and (st.power / st.powerMax) or 0
  local pr, pg, pb = 0.25, 0.45, 0.90
  if st.powerType == 1 then pr, pg, pb = 0.90, 0.20, 0.25
  elseif st.powerType == 2 then pr, pg, pb = 0.90, 0.50, 0.20
  elseif st.powerType == 3 then pr, pg, pb = 1.00, 1.00, 0.40 end
  uiSetBar(ui.pwFill, ui.pwText, ui.pwW, pfrac, pr, pg, pb,
    string.format("%s %d/%d", powerLabel(), st.power, st.powerMax))

  -- 连击点段刷新（1.67.0）：激活段高亮金、未激活段浅灰
  if ui.comboSegs then
    local cp = st.combo or 0
    for ci = 1, 5 do
      if cp >= ci then uiSolid(ui.comboSegs[ci], 0.95, 0.80, 0.25, 1)
      else uiSolid(ui.comboSegs[ci], 0.25, 0.25, 0.25, 1) end
    end
  end

  -- 目标条
  if ui.tgRange then ui.tgRange:SetText(st.tRange or "") end -- 1.37.0 目标条右侧距离
  -- 1.38.1 施法读条：读条中=蓝底反向消耗进度+技能名+剩余秒；无读条=空条
  if ui.castBar then
    if st.castName then
      local total = (st.castStart and st.castUntil) and (st.castUntil - st.castStart) or 0
      local frac = (total > 0) and math.max(0, math.min(1, (st.castUntil - GetTime()) / total)) or 1
      uiSetBar(ui.castFill, ui.castText, ui.castW, frac, 0.25, 0.45, 0.85,
        tostring(st.castName) .. (st.castUntil and string.format(" %.1fs", math.max(0, st.castUntil - GetTime())) or ""))
    else
      uiSetBar(ui.castFill, ui.castText, ui.castW, 0, 0.1, 0.1, 0.1, "")
    end
  end
  -- 1.55.0 挥击计时条：有攻速+锚点数据时显示（进度=已过/攻速，文本=距下次攻击秒数/就绪）
  if ui.swingBar then
    local rem = EVAL_SWING_REMAIN and EVAL_SWING_REMAIN()
    if rem and st.atkSpd and st.atkSpd > 0 then
      local frac = math.max(0, math.min(1, 1 - rem / st.atkSpd))
      uiSetBar(ui.swingFill, ui.swingText, ui.swingW, frac, 0.85, 0.70, 0.25,
        rem > 0.05 and string.format("下次攻击 %.1fs", rem) or "攻击就绪")
    else
      uiSetBar(ui.swingFill, ui.swingText, ui.swingW, 0, 0.1, 0.1, 0.1, "")
    end
  end
  if st.hasTarget then
    local tfrac = st.tHpPct / 100
    uiSetBar(ui.tgFill, ui.tgText, ui.tgW, tfrac, 0.80, 0.20, 0.20,
      string.format("%s  %d%%", tostring(st.targetName), math.floor(tfrac * 100 + 0.5)))
  else
    uiSetBar(ui.tgFill, ui.tgText, ui.tgW, 0, 0.3, 0.3, 0.3, "无目标")
  end

  -- 状态行（普攻判定已在上方算好——见「前置」说明）
  local inCombat = st.inCombat
  local form = st.form or "无姿态"
  ui.status:SetText(string.format("%s · %s · 普攻:%s",
    inCombat and "|cffff5040战斗中|r" or "|cff80ff80非战斗|r",
    form, atkOn and "|cff00ff00开|r" or "|cff909090关|r"))
  end -- ★1.71.12 子开关「战斗」段结束

  -- 方案切换行：当前激活金色高亮，不存在的方案位隐藏
  --   ★1.71.12 子开关「方案」= 关时 ui.profBtns / ui.profCells 为 nil（BUILD 里根本没建）→ 下面两个循环自然跳过。
  if ui.profBtns then
    local w2 = uiWarCfg()
    for i, pb in ipairs(ui.profBtns) do
      local prof = w2.profiles and w2.profiles[i]
      if prof then
        pb.btn:Show()
        pb.text:SetText(tostring(prof.name or i))
        local sel = (w2.activeProfile or 1) == i
        pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
        pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.72, sel and 0.9 or 0.68, sel and 0.4 or 0.55)
      else
        pb.btn:Hide()
      end
    end
  end

  -- 技能图标带（1.46.0 两行合一）：亮金=条件当前满足，半暗=不满足，灰+停=已停用；动作条技能带冷却倒数
  -- ★1.71.12 子开关「方案」关掉时图标带不画 → 连带这次自动重扫也不需要（少一份无谓的动作条扫描）。
  if ui.schemeOn and not EVAL_IS_SCANNED() then EVAL_GO_RESCAN(true, "auto") end
  if ui.profCells then
    for i, pc in ipairs(ui.profCells) do
      local r = uiWarActiveRule(i)
      if not r then
        pc.btn:Hide()
      else
        pc.btn:Show()
        local s = wslots[r.skill]
        local t0 = wicon(r.skill)
        -- 1.66.0 选取目标类技能：有目标时图标实时画目标头像（SetPortraitTexture，刷新节拍内自然跟随切目标），无目标回退原图标
        if targetSelOf(r.skill) and st.hasTarget and type(SetPortraitTexture) == "function" then
          pcall(SetPortraitTexture, pc.icon, "target")
        elseif t0 then pcall(pc.icon.SetTexture, pc.icon, t0) end
        local enabled = r.enabled ~= false
        local pass = false
        if enabled and (s or petCmdOf(r.skill) or targetSelOf(r.skill) or itemOf(r.skill) or stanceOf(r.skill) or cancelCastOf(r.skill) or stopAllOf(r.skill) or followOf(r.skill)) and r.groups then -- 宠物/选取目标/物品/姿态/取消施法/停止攻击/跟随 不占动作条也参与亮金（1.30.0~1.71.3）
          local okp = groupsOK(r, true) -- dry: 亮金预览不触发选取目标等副作用
          pass = okp and true or false
        end
        if not enabled then
          pcall(pc.icon.SetVertexColor, pc.icon, 0.25, 0.25, 0.25)
          pc.text:SetText("停")
        elseif not s and not petCmdOf(r.skill) and not targetSelOf(r.skill) and not itemOf(r.skill) and not stanceOf(r.skill) and not cancelCastOf(r.skill) and not stopAllOf(r.skill) and not followOf(r.skill) then -- 特殊技能不占动作条不算缺失（1.30.0~1.71.3）
          pcall(pc.icon.SetVertexColor, pc.icon, 0.35, 0.35, 0.35)
          pc.text:SetText("?")
        else
          -- 冷却倒数（仅动作条技能；1.46.0 自旧图标行并入）
          local left = 0
          if s then
            local okc, cst, dur = pcall(GetActionCooldown, s.slot)
            if okc and type(cst) == "number" and type(dur) == "number" and cst > 0 and dur > 0 then
              left = cst + dur - GetTime()
            end
          end
          if left > 0 then
            pc.text:SetText(left >= 10 and string.format("%d", math.floor(left + 0.5)) or string.format("%.1f", left))
            pcall(pc.icon.SetVertexColor, pc.icon, 0.4, 0.4, 0.4)
          elseif pass then
            pcall(pc.icon.SetVertexColor, pc.icon, 1, 1, 1)
            pc.text:SetText("")
          else
            pcall(pc.icon.SetVertexColor, pc.icon, 0.55, 0.55, 0.55)
            pc.text:SetText("")
          end
        end
        if pass and enabled then
          pcall(pc.bg.SetVertexColor, pc.bg, 1, 0.85, 0.3, 1) -- 条件满足：亮金描边
        else
          pcall(pc.bg.SetVertexColor, pc.bg, 0.45, 0.38, 0.15, 1)
        end
      end
    end
  end
end

-- /eh ui 开关
function EVAL_HELP_UI_TOGGLE()
  local u = uiCfg()
  if ui.root and ui.root:IsVisible() then
    ui.root:Hide()
    u.enabled = false
    say("战斗信息UI: |cffff0000关|r")
  else
    EVAL_HELP_UI_BUILD()
    if ui.root then ui.root:Show() end
    u.enabled = true
    say("战斗信息UI: |cff00ff00开|r（按住标题栏拖动换位置，滚轮缩放）")
  end
end

-- ★1.71.12 子开关「战斗 / 方案」改动后**若窗口开着**要重建才能看到效果（几何随之前移）；窗口关着就什么都不做。
--   ★为什么必须重建而不是 Hide 控件：布局 y 与帧高都要跟着变（见 BUILD 里的说明）。
function EVAL_HELP_UI_REBUILD_IF_SHOWN()
  if not ui.root then return false end
  local ok, vis = pcall(ui.root.IsVisible, ui.root)
  if not (ok and vis) then return false end
  EVAL_HELP_UI_BUILD()
  if ui.root then ui.root:Show() end
  return true
end

-- ============ 配置窗口 + 小地图图标（参考 UnrealQuest 设置面板：深底金边 + 金框勾选 + 滑条 + 底部关闭） ============
-- 打开方式：小地图左侧金色「EH」图标，或 /eh cfg。改动即时写入 EVAL_HELP_CONFIG（SavedVariables 自动存档）。
-- 窗口按 UnrealQuest 的实测构件法：纯色纹理(WHITE8X8)+金边、自绘勾选框/滑条，不依赖任何客户端贴图/模板/Slider 控件。

local cfgWin = { root = nil, refresh = nil }
local EVAL_WLASTHINT = 0

local function c()
  if not cfg then cfg = EVAL_HELP_CONFIG or {}; EVAL_HELP_CONFIG = cfg end
  return cfg
end

local function warCfg()
  local cc = c()
  if not cc.war then
    cc.war = { enabled = true, attack = true } -- 1.48.0 战士阈值缺省已随默认方案一起清理
  end
  EVAL_WAR_ENSURE_PROFILES(cc.war) -- 方案数据迁移（缺省生成默认方案）
  return cc.war
end

-- 金框勾选框（参考截图的方形金框 checkbox）：Button + 外金框 + 内暗底 + 打勾金色块
local function cfgCheck(parent, x, y, label, get, set, list, tip, into) -- 1.50.0 可选 tip=悬停提示；1.71.12 可选 into=交出真实控件
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(16) b:SetHeight(16)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local outer = b:CreateTexture(nil, "BACKGROUND")
  uiSolid(outer, 0.85, 0.70, 0.20, 1)
  outer:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  outer:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local inner = b:CreateTexture(nil, "ARTWORK")
  uiSolid(inner, 0.10, 0.09, 0.06, 1)
  inner:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  inner:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  local mark = b:CreateTexture(nil, "OVERLAY")
  uiSolid(mark, 0.95, 0.80, 0.25, 1)
  mark:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  mark:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  local text = uiText(parent, 11, 0.92, 0.88, 0.80)
  -- 1.45.1 对齐修复：文字相对勾选框 RIGHT 锚定（纵向共中心线），不再用父级 y-3 估算——旧写法视觉上方框偏低
  text:SetPoint("LEFT", b, "RIGHT", 6, 0)
  text:SetText(label)
  -- ★1.71.12 可选 out 参数 `into`：把**真实控件**交出去——断言要能点真按钮、读真文字，
  --   凭「y 值反查」等于测测试自己（本项目老坑）。
  if into then into.btn = b into.text = text end
  if list then table.insert(list, b) table.insert(list, text) end
  local function refresh()
    if get() then mark:Show() else mark:Hide() end
  end
  b:SetScript("OnClick", function()
    set(not get())
    refresh()
  end)
  if tip then -- 悬停提示（勾选框与文字共用）
    local function showTip()
      GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
      GameTooltip:AddLine(tostring(label), 1, 0.82, 0.3)
      GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, 1)
      GameTooltip:Show()
    end
    b:SetScript("OnEnter", showTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pcall(text.EnableMouse, text, true)
    text:SetScript("OnEnter", showTip)
    text:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  refresh()
  return refresh
end

-- 阈值滑条：UnrealQuest 实测配方——本客户端不用 Slider 控件，
-- 用 track Frame + thumb Button + RegisterForDrag 自绘；拖动含 warm-up 两步；OnUpdate 实时回写数值。
local function cfgSlider(parent, x, y, w, label, get, set, list)
  local text = uiText(parent, 10, 0.92, 0.88, 0.80)
  text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  text:SetText(label)
  local valText = uiText(parent, 11, 1, 0.85, 0.35)
  valText:SetPoint("TOPLEFT", parent, "TOPLEFT", x + w + 6, y - 13)
  local track = CreateFrame("Frame", nil, parent)
  track:SetWidth(w) track:SetHeight(8)
  track:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
  local trackBg = track:CreateTexture(nil, "BACKGROUND")
  uiSolid(trackBg, 0.06, 0.05, 0.04, 1)
  trackBg:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
  trackBg:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, 0)
  local trackEdge = track:CreateTexture(nil, "BORDER")
  uiSolid(trackEdge, 0.85, 0.70, 0.20, 0.7)
  trackEdge:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 1)
  trackEdge:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, 1)
  trackEdge:SetHeight(1)
  local thumb = CreateFrame("Button", nil, track)
  thumb:SetWidth(12) thumb:SetHeight(14)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
  uiSolid(thumbTex, 0.95, 0.80, 0.25, 1)
  thumbTex:SetPoint("TOPLEFT", thumb, "TOPLEFT", 0, 0)
  thumbTex:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
  pcall(thumb.EnableMouse, thumb, true)
  pcall(thumb.RegisterForClicks, thumb, "LeftButtonUp")
  pcall(thumb.RegisterForDrag, thumb, "LeftButton")
  local dragging = false
  local function place(v)
    v = math.max(0, math.min(100, v or 0))
    thumb:ClearAllPoints()
    thumb:SetPoint("LEFT", track, "LEFT", (v / 100) * (w - 12), 0)
  end
  local function read()
    local ok1, tl = pcall(thumb.GetLeft, thumb)
    local ok2, kl = pcall(track.GetLeft, track)
    if not (ok1 and ok2 and tl and kl) then return nil end
    local usable = w - 12
    if usable <= 0 then return nil end
    local off = tl - kl
    if off < 0 then off = 0 elseif off > usable then off = usable end
    return math.floor(off / usable * 100 + 0.5)
  end
  thumb:SetScript("OnDragStart", function()
    pcall(thumb.SetMovable, thumb, true)
    pcall(thumb.StartMoving, thumb)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(thumb.StopMovingOrSizing, thumb)
    if pcall(thumb.StartMoving, thumb) then dragging = true end
  end)
  thumb:SetScript("OnUpdate", function()
    if not dragging then return end
    local v = read()
    if v then set(v) valText:SetText(tostring(v)) end
  end)
  thumb:SetScript("OnDragStop", function()
    local v = read()
    dragging = false
    pcall(thumb.StopMovingOrSizing, thumb)
    if v then set(v) valText:SetText(tostring(v)) end
    place(v or (get() or 0))
  end)
  if list then
    table.insert(list, text) table.insert(list, valText)
    table.insert(list, track) table.insert(list, thumb)
  end
  place(get() or 0)
  valText:SetText(tostring(get() or 0))
  return function() place(get() or 0) valText:SetText(tostring(get() or 0)) end
end

-- ★1.71.2 配置窗章节标题**登记表**（供断言核实「哪个标题真的画了」）。
--   为什么需要：标题是 FontString，测试桩无法从控件树反查它的文本，
--   而某轮的需求恰恰是「某个标题**不许**再画出来」——没有这份登记就只能靠人眼看截图。
local cfgHeaderTexts = {}

-- 章节标题
local function cfgHeader(parent, x, y, label, list)
  local t = uiText(parent, 11, 0.95, 0.80, 0.30)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  t:SetText(label)
  table.insert(cfgHeaderTexts, tostring(label))
  if list then table.insert(list, t) end
  return t -- 1.71.14 交出真实控件（断言要读它的真实位置，不是 y 常量）
end

-- ★1.70.45 窗口宽度的**单一来源**：配置窗与技能编辑窗必须同宽（用户要求），
--   且两份宽度必须由同一个函数给出——否则改一处漏一处（本项目「两份数据必须有断言盯着」的惯例）。
--   用户要求：在原来基础上加宽 ~100（中 560→660 / 西文 700→800）。
--   语言在构建期定型（切语言需 /reload），故这里按 EH_LANG 直接算即可。
local function cfWinWidth()
  return (EVAL_GET_LANG() ~= "zhCN") and 800 or 660
end

-- 构建配置窗口（只建一次；开关 = Show/Hide）
local function cfgBuild()
  if cfgWin.root then return cfgWin.root end
  local WIDE = (EVAL_GET_LANG() ~= "zhCN") -- 1.34.1 i18n：西文（英/俄）比中文宽 ~1.5 倍，窗口与右列自适应加宽
  -- ★1.71.2 高度 420 → **460**：用户要求开关组再下移 40px，
  --   而原高度下移到 -389 时底部会超出窗口 5px（实测算过）→ 同步加高 40 保持全部可见。
  local W, H = cfWinWidth(), 460 -- 1.70.45 加宽 ~100（原 700/560）；1.71.2 加高 40（开关组下移）
  local root = CreateFrame("Frame", "EVAL_HELP_CFG", UIParent)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.EnableMouse, root, true)
  pcall(root.SetMovable, root, true)
  root:SetWidth(W) root:SetHeight(H)
  cfgWin.W = W -- 1.70.45 记下实际宽度：断言「编辑窗与配置窗同宽」时读它（同一来源的**结果**，不是再抄一份）
  -- 位置：默认左移错开 UnrealQuest 的居中设置窗口；拖动后按记忆位置恢复
  root:ClearAllPoints()
  local pos = c().cfgPos
  if pos and type(pos.point) == "string" then
    pcall(root.SetPoint, root, pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  else
    root:SetPoint("CENTER", UIParent, "CENTER", -320, -30)
  end

  -- 深底 + 1px 金边（四边纯色纹理，不依赖客户端贴图）
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.95)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end

  -- 标题栏（拖动柄，与状态窗口同一套逻辑：Button + frame level +10，见状态窗口注释）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(20)
  local okLvl2, rootLvl2 = pcall(root.GetFrameLevel, root)
  if okLvl2 and type(rootLvl2) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl2 + 10)
  end
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)          -- warm-up 两步（UnrealQuest StartFrameDrag 实测配方）
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, point, _, relPoint, x, y = pcall(root.GetPoint, root, 1)
    if ok and type(point) == "string" then
      c().cfgPos = {
        point = point,
        relPoint = (type(relPoint) == "string") and relPoint or point,
        x = (type(x) == "number") and x or 0,
        y = (type(y) == "number") and y or 0,
      }
    end
  end)
  local title = uiText(titleBar, 12, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("CFG_TITLE") .. "  |cff8a7a5av" .. VERSION .. "|r") -- 1.67.1 标题栏显示版本号（暗金弱化色）

  -- 语言选择（1.34.0 i18n P0）：标题栏右上角国旗行 [CN][EN][RU]——国旗纹理盖住 ASCII 徽标，
  -- 纹理加载失败徽标仍在（任何语言都能找到回家的路）；选中=不透明/未选=30%透/悬停=95%；
  -- 不入 G/Wp 页清单——常驻标题栏两个 Tab 都可见；切换存 cfg.lang + 新语言提示 /reload
  local EH_FLAGS = {
    { code = "zhCN", badge = "CN", flag = "cn" },
    { code = "enUS", badge = "EN", flag = "en" },
    { code = "ruRU", badge = "RU", flag = "ru" },
  }
  cfgWin.langBtns = {}
  EVAL_HELP_CFGWIN = cfgWin -- 全局桥：供 EVAL_HELP_LANG_REFRESH（定义在本 local 声明之前）使用
  for i, lg in ipairs(EH_FLAGS) do
    local fb = CreateFrame("Button", nil, root)
    fb:SetWidth(18) fb:SetHeight(14)
    fb:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8 - (table.getn(EH_FLAGS) - i) * 21, -3)
    pcall(fb.EnableMouse, fb, true)
    pcall(fb.RegisterForClicks, fb, "LeftButtonUp")
    local okLF, tLvl = pcall(titleBar.GetFrameLevel, titleBar)
    if okLF and type(tLvl) == "number" then pcall(fb.SetFrameLevel, fb, tLvl + 5) end -- 高过拖动柄
    local fbg = fb:CreateTexture(nil, "BACKGROUND")
    uiSolid(fbg, 0.10, 0.09, 0.06, 1)
    fbg:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
    fbg:SetPoint("BOTTOMRIGHT", fb, "BOTTOMRIGHT", 0, 0)
    local badge = uiText(fb, 9, 0.92, 0.92, 0.92)
    badge:SetPoint("CENTER", fb, "CENTER", 0, 0)
    badge:SetText(lg.badge)
    local ft = fb:CreateTexture(nil, "ARTWORK")
    ft:SetPoint("TOPLEFT", fb, "TOPLEFT", 0, 0)
    ft:SetPoint("BOTTOMRIGHT", fb, "BOTTOMRIGHT", 0, 0)
    pcall(ft.SetTexture, ft, "Interface\\AddOns\\EvalHelp\\media\\Flags\\" .. lg.flag .. ".tga")
    fb.langCode = lg.code
    fb:SetScript("OnClick", function()
      if EVAL_SET_LANG(lg.code) then EVAL_HELP_LANG_REFRESH() end
    end)
    fb:SetScript("OnEnter", function() if EVAL_GET_LANG() ~= lg.code then pcall(fb.SetAlpha, fb, 0.95) end end)
    fb:SetScript("OnLeave", function() EVAL_HELP_LANG_REFRESH() end)
    cfgWin.langBtns[i] = fb
  end
  EVAL_HELP_LANG_REFRESH()

  local refreshes = {}

  -- Tab 按钮行（全局 / 一键宏设置；选中=金底亮字，未选=暗底灰字——参考 UnrealQuest 标签页风格）
  local pages = {}
  cfgWin.pages = pages
  local tabNames = { L("TAB_GLOBAL"), L("TAB_MACRO"), L("TAB_TOOLBOX"), L("TAB_DS"), L("TAB_ICONS") } -- ★1.71.3 第 5 个 Tab：图标库（IconBrowser.lua 独立载入）
  for i, name in ipairs(tabNames) do
    local tb = CreateFrame("Button", nil, root)
    tb:SetWidth(90) tb:SetHeight(18)
    tb:SetPoint("TOPLEFT", root, "TOPLEFT", 12 + (i - 1) * 96, -26)
    pcall(tb.EnableMouse, tb, true)
    pcall(tb.RegisterForClicks, tb, "LeftButtonUp")
    local tbg = tb:CreateTexture(nil, "BACKGROUND")
    uiSolid(tbg, 0.16, 0.13, 0.08, 1)
    tbg:SetPoint("TOPLEFT", tb, "TOPLEFT", 0, 0)
    tbg:SetPoint("BOTTOMRIGHT", tb, "BOTTOMRIGHT", 0, 0)
    local tt = uiText(tb, 11, 0.95, 0.82, 0.35)
    tt:SetPoint("CENTER", tb, "CENTER", 0, 0)
    tt:SetText(name)
    local idx = i
    tb:SetScript("OnClick", function() EVAL_HELP_CFG_SETTAB(idx) end)
    pages[i] = { btn = tb, bg = tbg, text = tt, widgets = {} }
  end

  local LX, RX, RW = 18, WIDE and 330 or 250, 160 -- RX 右列随语言加宽
  -- ★★1.71.2（第六轮）**关闭按钮几何提为单一来源**：
  --   用户要求「案例模版/分享/接收放到右侧、与[关闭]**同一行**」
  --   → 必须知道关闭按钮的左边缘与**中线 y**。若在两处各写一遍，
  --   改一个会漂移（本项目反复踩过：上一轮的测试副本就是这个形态）。
  --   ★判据同「窗口宽度单一来源 cfWinWidth()」。
  local CLOSE_W, CLOSE_H, CLOSE_RIGHT, CLOSE_BOTTOM = 64, 22, -12, 10
  local CLOSE_LEFT = W + CLOSE_RIGHT - CLOSE_W
  local CLOSE_MIDY = -(H - CLOSE_BOTTOM - CLOSE_H / 2)

  -- ===== Tab 1「全局」：日志 / 界面 / 帮助（非职业相关） =====
  local G = pages[1].widgets
  cfgHeader(root, LX, -56, L("G_LOG_H"), G)
  -- ★1.71.2（第四轮）：日志组各行的 y 提为**单一来源常量**。
  --   原因：测试可见的行表要记 y，若这里手写一份、cfgCheck 又写一份，
  --   两份会各自漂移（本轮实测：把新行改到 -122 造成重叠，断言竟然未发现）。
  --   ★与本项目「窗口宽度单一来源 cfWinWidth()」同一条律。
  local LOG_Y_FILE, LOG_Y_DBG, LOG_Y_AUTO = -74, -98, -122
  -- 1.70.12：勾选框读写 cfg.log.on（cfg.log 本体是日志环形缓冲表，不能再整体当布尔用）
  local lfRow = cfgCheck(root, LX, LOG_Y_FILE, L("G_LOG_FILE"),
    function() local lg = c().log return not (type(lg) == "table" and lg.on == false) end,
    function(v)
      if type(c().log) ~= "table" then c().log = {} end
      c().log.on = v and true or false
    end, G)
  table.insert(refreshes, lfRow)
  cfgWin.logRows = cfgWin.logRows or {}
  table.insert(cfgWin.logRows, { key = "G_LOG_FILE", y = LOG_Y_FILE })
  -- ★★★1.71.2（第四轮）用户要求：把方案列表的「方案技能日志」开关移到这里（日志分组内）。
  --   它与上面「记录调试日志」**不是同一功能**（排查记录见开关组处）：
  --     上面 = 总闸门（写不写日志）；本行 = 只把每次按键的决策原因同步刷到聊天框（说不说）。
  --   ★位置紧跟「记录调试日志」下方：两者同属日志输出，放一起才好对照理解。
  -- ★★★注册到测试可见的行表 —— **必须直接用真实的读写器**，
  --   不能再手写一份：我第一版就是手写的（另写一个 get/set 包一层），
  --   结果把上面 cfgCheck 的字段改成 c().auto，**断言照样全绿**（本轮变异实测 SURVIVED）——
  --   因为断言读的是那份手写副本，不是真正装上去的那个控件。
  --   ★判据：**测试读的必须是生产代码实际使用的那个对象**，不能是它的一份平行拷贝。
  local dbgGet = function() return c().wdebug end
  local dbgSet = function(v) c().wdebug = v end
  local dbgRow = cfgCheck(root, LX, LOG_Y_DBG, L("W_DEBUG_LOG"), dbgGet, dbgSet, G)
  table.insert(refreshes, dbgRow)
  cfgWin.logRows = cfgWin.logRows or {}
  table.insert(cfgWin.logRows, { key = "W_DEBUG_LOG", y = LOG_Y_DBG, get = dbgGet, set = dbgSet })
  -- 「进出战斗自动输出」顺势下移一行（原 -98 → -122），避免与上面新增项重叠
  table.insert(refreshes, cfgCheck(root, LX, LOG_Y_AUTO, L("G_LOG_AUTO"),
    function() return c().auto end, function(v) c().auto = v end, G))
  table.insert(cfgWin.logRows, { key = "G_LOG_AUTO", y = LOG_Y_AUTO })

  cfgHeader(root, LX, -138, L("G_UI_H"), G)
  -- ★★★1.71.12 用户要求：「战斗信息UI 再加2个子选项，战斗、方案，分开控制显示和隐藏。」
  --   行序 = 主开关 → 两个**缩进 16px** 的子开关（从属关系一眼可见）→ 状态信息UI
  --   （状态信息UI 与子项之间多留 6px 分组间距，免得被当成「第三个子项」）。
  --   ★y 值集中在这里定义并**导出**（`cfgWin.uiRows`）：断言读生产值，而不是自己再写一遍常量
  --     ——「测试复刻布局常量」是本项目反复吃亏的老毛病（生产改了它不跟着变）。
  local UIY_COMBAT = -156
  local UIY_SUBC = UIY_COMBAT - 20 -- 「战斗」子项
  local UIY_SUBS = UIY_SUBC - 20   -- 「方案」子项
  local UIY_STATE = UIY_SUBS - 26  -- 状态信息UI（与子项之间多 6px 分组间距）
  local UI_IND = 16                -- 子项缩进（勾选框 x 相对 LX）
  cfgWin.uiRows = { combat = UIY_COMBAT, subCombat = UIY_SUBC, subScheme = UIY_SUBS, state = UIY_STATE, indent = UI_IND }
  cfgWin.uiBoxes = { combat = {}, subCombat = {}, subScheme = {}, state = {} } -- 交出这四行的**真实控件**（断言要点它，不是改配置）
  table.insert(refreshes, cfgCheck(root, LX, UIY_COMBAT, L("G_UI_COMBAT"),
    function() local u = c(); return u.ui and u.ui.enabled end,
    function(v)
      local u = c()
      if not u.ui then u.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
      if v ~= (u.ui.enabled and true or false) then EVAL_HELP_UI_TOGGLE() end
    end, G, nil, cfgWin.uiBoxes.combat))
  -- 子开关「战斗」：★语义 = nil 视为开（老配置里没有这个键 → 行为与旧版逐字一致）。
  table.insert(refreshes, cfgCheck(root, LX + UI_IND, UIY_SUBC, L("G_UI_SUBC"),
    function() local u = c(); return not (u.ui and u.ui.subCombat == false) end,
    function(v)
      local u = c()
      if not u.ui then u.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
      u.ui.subCombat = v and true or false
      EVAL_HELP_UI_REBUILD_IF_SHOWN() -- 窗口开着就重建（几何要随之前移），关着什么都不做
    end, G, L("G_UI_SUBC_TIP"), cfgWin.uiBoxes.subCombat))
  -- 子开关「方案」：同上（方案行 + 技能图标带）
  table.insert(refreshes, cfgCheck(root, LX + UI_IND, UIY_SUBS, L("G_UI_SUBS"),
    function() local u = c(); return not (u.ui and u.ui.subScheme == false) end,
    function(v)
      local u = c()
      if not u.ui then u.ui = { enabled = false, x = 0, y = -180, scale = 1 } end
      u.ui.subScheme = v and true or false
      EVAL_HELP_UI_REBUILD_IF_SHOWN()
    end, G, L("G_UI_SUBS_TIP"), cfgWin.uiBoxes.subScheme))
  table.insert(refreshes, cfgCheck(root, LX, UIY_STATE, L("G_UI_STATE"),
    function() local u = c(); return u.st and u.st.enabled end,
    function(v)
      local u = c()
      if not u.st then u.st = { enabled = false, x = 330, y = -180 } end
      if v ~= (u.st.enabled and true or false) then EVAL_HELP_ST_TOGGLE() end
    end, G, nil, cfgWin.uiBoxes.state))

  cfgHeader(root, RX, -56, L("G_HELP_H"), G)
  -- 分组排版（1.21.5）：金色小标题 + 缩进条目 + 组间留白；命令行用亮米色区分
  -- 1.32.7 重整：清掉战士残留（猛击 Alt），补五分类/Shift切方案/重扫按钮/导入导出
  local helpLines = { -- 1.34.0 i18n：全部走语言包键
    { L("HELP_QS_H"), h = true },
    { L("HELP_QS_1") },
    { L("HELP_QS_2") },
    { L("HELP_QS_3") },
    { L("HELP_PROF_H"), h = true },
    { L("HELP_PROF_1"), cmd = true },
    { L("HELP_PROF_2"), cmd = true },
    { L("HELP_PROF_3"), cmd = true },
    { L("HELP_PROF_4"), cmd = true },
    { L("HELP_ADV_H"), h = true },
    { L("HELP_ADV_1") },
    { L("HELP_ADV_2") },
    { L("HELP_ADV_3") },
    { L("HELP_MISC_H"), h = true },
    { L("HELP_MISC_1") },
    { L("HELP_MISC_2") },
  }
  local hy = -74
  for _, e in ipairs(helpLines) do
    local ht
    if e.h then
      ht = uiText(root, 10, 0.95, 0.82, 0.35)         -- 组标题：金色，上方留白
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX, hy - 4)
      hy = hy - 21
    elseif e.cmd then
      ht = uiText(root, 9, 0.88, 0.82, 0.58)         -- 命令示例：亮米色
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX + 12, hy)
      hy = hy - 14
    else
      ht = uiText(root, 9, 0.65, 0.65, 0.65)         -- 普通条目：灰色
      ht:SetPoint("TOPLEFT", root, "TOPLEFT", RX + 12, hy)
      hy = hy - 14
    end
    ht:SetText(e[1])
    table.insert(G, ht)
  end

  -- ===== Tab 2「一键宏设置」：多方案 + 技能规则列表（可视化编辑器，全职业通用） =====
  local Wp = pages[2].widgets
  local warUI = { rows = {}, profBtns = {}, picker = {}, editing = nil, pickSkill = nil }
  cfgWin.warUI = warUI
  local MAXPROF = 12 -- 1.42.0 方案上限 4→12（间距 21→19 紧凑排列装下）

  -- 左栏：方案列表（多方案 Tab；最后一个 [+] 新建方案）
  cfgHeader(root, LX, -56, L("W_PROF_H"), Wp)
  for i = 1, MAXPROF + 1 do
    local pb = CreateFrame("Button", nil, root)
    pb:SetWidth(90) pb:SetHeight(17)
    pb:SetPoint("TOPLEFT", root, "TOPLEFT", LX, -74 - (i - 1) * 19)
    pcall(pb.EnableMouse, pb, true)
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp")
    local pbg = pb:CreateTexture(nil, "BACKGROUND")
    uiSolid(pbg, 0.16, 0.13, 0.08, 1)
    pbg:SetPoint("TOPLEFT", pb, "TOPLEFT", 0, 0)
    pbg:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", 0, 0)
    local pt = uiText(pb, 10, 0.92, 0.88, 0.80)
    pt:SetPoint("CENTER", pb, "CENTER", 0, 0)
    local pidx = i
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp", "RightButtonUp")
    pb:SetScript("OnClick", function(a, b)
      local w2 = warCfg()
      local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
      -- 右键 = 重命名弹窗（1.17.0：替代底部输入框流程，EditBox 不渲染也有回声行）
      if mbtn == "RightButton" and pidx <= table.getn(w2.profiles) then
        EVAL_HELP_RP_OPEN(pidx)
        return
      end
      if pidx <= table.getn(w2.profiles) then
        w2.activeProfile = pidx
      elseif pidx == table.getn(w2.profiles) + 1 and table.getn(w2.profiles) < MAXPROF then
        table.insert(w2.profiles, { name = "方案" .. tostring(table.getn(w2.profiles) + 1), skills = {} })
        w2.activeProfile = table.getn(w2.profiles)
        say("新建方案: " .. tostring(w2.profiles[w2.activeProfile].name))
      end
      EVAL_WAR_TAB_REFRESH()
    end)
    -- [删] 按钮（二次确认：5 秒内再点一次才删，防误删）
    local delB = CreateFrame("Button", nil, root)
    delB:SetWidth(15) delB:SetHeight(17)
    delB:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 92, -74 - (i - 1) * 19) -- 1.58.1 修偏移：与方案按钮同 19 间距（旧 21 逐行下沉，越往后越错位）
    pcall(delB.EnableMouse, delB, true)
    pcall(delB.RegisterForClicks, delB, "LeftButtonUp")
    local delBg = delB:CreateTexture(nil, "BACKGROUND")
    uiSolid(delBg, 0.25, 0.10, 0.10, 1)
    delBg:SetPoint("TOPLEFT", delB, "TOPLEFT", 0, 0)
    delBg:SetPoint("BOTTOMRIGHT", delB, "BOTTOMRIGHT", 0, 0)
    local delT = uiText(delB, 8, 0.95, 0.6, 0.5)
    delT:SetPoint("CENTER", delB, "CENTER", 0, 0)
    delT:SetText("删")
    delB:SetScript("OnClick", function()
      local w2 = warCfg()
      if pidx > table.getn(w2.profiles) then return end
      if warUI.delArm == pidx and GetTime() - (warUI.delArmT or 0) < 5 then
        warUI.delArm = nil
        EVAL_WAR_DEL_PROFILE(pidx)
      else
        warUI.delArm = pidx
        warUI.delArmT = GetTime()
        say("再点一次 [删] 确认删除方案: " .. tostring(w2.profiles[pidx].name))
        EVAL_WAR_TAB_REFRESH()
      end
    end)
    warUI.profBtns[i] = { btn = pb, bg = pbg, text = pt, del = delB, delBg = delBg }
    table.insert(Wp, pb)
    table.insert(Wp, delB)
  end

  -- ★★★1.71.2（第六轮）用户要求：「一键宏tab 以上按钮放置在右侧和关闭同一行」。
  --   即：【案例模版 / 分享】整组从左侧**靠右**，与右下角的 [关闭] 排在**同一水平线**上。
  --   ★1.71.2（第十六轮）用户要求：「删除分享右边的按键」——那正是 [接收]：
  --     它的 OnClick 就是 EVAL_SHARE_RECV_TOGGLE，与开关组的「接收方案」**是同一个开关**（用户判断正确），
  --     留着就是同一功能两个入口，还白占本行 84px。
  --   ★为什么靠右而不是继续靠左：左下角要让给开关组（见下方 swItem），
  --     两者各占一侧才不会互相挤（上一版正是因为都在左侧才显得拥挤）。
  --   ★定位算法（不写死坐标，两种语言宽度 660/800 自适应）：
  --     组右缘 = 关闭左边缘 - 8；已知组宽反推左边起点。
  --   ★纵向：**按钮行中线对齐关闭按钮中线**（本项目铁律：同一行混用顶边/中线对齐必然错位）。
  local NAV_GAP, NAV_H = 6, 20
  local NAV_TAIL_GAP = 8 -- 组右缘与关闭左边缘的间隙
  -- ★★两版对比（本轮实算过）：第一版把可用宽度**平分给三个按钮**
  --   → 每个 182px、整行从 x=18 铺到 576（几乎横贯全窗），看上去像一排巨块；
  --   而且**左边对齐与右边对齐数值上完全相等**（x0 两种算法都是 18）——
  --   意味着那个变体是**等价变体**，测不出来也是应该的。
  -- ★正确读法：按钮用**自然宽度**（够放下中文标签），**整组靠右**贴着关闭，
  --   左侧腾出来的空间正好给开关行用 —— 这才是「放在右侧」的本意。
  local NAV_BW = 78 -- 单个按钮宽（自然宽度：最长标签「案例模版」4 字 ×12px + 余量）
  local NAV_ROW_Y = CLOSE_MIDY + NAV_H / 2 -- 顶边 y（中线对齐关闭）
  local NAV_X0 = CLOSE_LEFT - NAV_TAIL_GAP - (NAV_BW * 2 + NAV_GAP * 1) -- 整组靠右（第十六轮 [接收] 已删 → 2 个按钮）
  local navBtns = {}
  local function navBtn(idx, label, fn, tip)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(NAV_BW) b:SetHeight(NAV_H)
    b:SetPoint("TOPLEFT", root, "TOPLEFT", NAV_X0 + (idx - 1) * (NAV_BW + NAV_GAP), NAV_ROW_Y)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.16, 0.13, 0.08, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 9, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    pcall(bt.SetWidth, bt, NAV_BW - 4) -- 限宽+不折行（本项目铁律：不限宽会溢出压到邻居）
    pcall(bt.SetNonSpaceWrap, bt, false)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    if tip then
      b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tostring(label), 1, 0.82, 0.3)
        -- ★1.71.2（第十九轮）tip 既可以是**一行字符串**（老写法），也可以是
        --   { {文本, r, g, b}, ... } 的**多行富提示**——分享按钮要分「怎么发 / 对方要满足什么」两段讲，
        --   塞进一行会被自动折行成一坨，读不出层次。
        --   ★用 ipairs 遍历是安全的：这张表由本文件自己构造、**没有 nil 洞**
        --     （分隔行写的是空格字符串，不是 nil——本项目在「ipairs 遇 nil 即停」上栽过两次）。
        if type(tip) == "table" then
          for _, ln in ipairs(tip) do
            if ln[1] ~= nil then
              GameTooltip:AddLine(tostring(ln[1]), ln[2] or 0.85, ln[3] or 0.85, ln[4] or 0.85, true)
            end
          end
        else
          GameTooltip:AddLine(tip, 0.85, 0.85, 0.85, 1)
        end
        GameTooltip:Show()
      end)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    table.insert(Wp, b)
    table.insert(Wp, bt)
    navBtns[idx] = { btn = b, text = bt, label = label } -- label 供断言逐项比对（不从控件反查，桩里文本不可靠）
    return b
  end
  -- ★★★1.71.2（第十九轮）分享按钮的 tooltip（用户要求）：「指引他怎么分享，别人需要什么条件才能接收分享，
  --   比如需要开启接收分享的开关」。
  --   ★为什么这条提示值得单独写：分享是**跨玩家**功能——**自己这端成功 ≠ 对方收得到**。
  --     最容易踩的坑就是「对方没开『接收方案』开关」：Share.lua 的 shOnMsg 第一行就是
  --     `if not shCfg().recv then return end` → **静默忽略，双方都没有任何提示**。
  --     所以那一条用绿色高亮：它是唯一「错了也不知道」的条件。
  --   ★文案全部走语言包（三语言齐），不在代码里写死中文。
  local function shareNavTip()
    return {
      { L("SH_TIP_HOW"),  1.00, 0.85, 0.35 },
      { L("SH_TIP_S1"),   0.88, 0.88, 0.88 },
      { L("SH_TIP_S2"),   0.88, 0.88, 0.88 },
      { L("SH_TIP_S3"),   0.88, 0.88, 0.88 },
      { " ",              0.50, 0.50, 0.50 }, -- 空行分段（写空格而不是 nil：见 navBtn 里 ipairs 的说明）
      { L("SH_TIP_NEED"), 1.00, 0.85, 0.35 },
      { L("SH_TIP_R1"),   0.88, 0.88, 0.88 },
      { string.format(L("SH_TIP_R2"), L("SH_RECV_SW")), 0.45, 1.00, 0.45 },
      { L("SH_TIP_R3"),   0.88, 0.88, 0.88 },
      { L("SH_TIP_R4"),   0.88, 0.88, 0.88 },
      { " ",              0.50, 0.50, 0.50 },
      { L("SH_TIP_FOOT"), 0.60, 0.60, 0.60 },
    }
  end
  navBtn(1, L("IO_TPL"), function()
    if type(EVAL_HELP_TPL_TOGGLE) == "function" then pcall(EVAL_HELP_TPL_TOGGLE) end
  end, L("CF_TPL_TIP"))
  navBtn(2, L("SH_SHARE"), function()
    -- ★★★1.71.2（第十七轮）用户要求：「分享按钮不要触发显示导入导出弹窗」→ **删掉那次 IO 窗调用**。
    --   ★先核实过「分享流程到底需不需要它」：**不需要**。分享走的是
    --     EVAL_SHARE_SEND → EVAL_PROFILE_TO_TEXT() 取当前方案文本 → hex 分片 → RunScript(SendChatMessage)，
    --     **全程不碰 IO 窗、也不碰它那个输入框**（原注释「分享流程需要 IO 窗承载 hex 文本」是旧设计的残留）。
    --   ★而且那个函数是 **Toggle**：IO 窗本来就开着时，点分享反而会把它**关掉**——比「多开一个窗」更糟。
    if type(EVAL_SHARE_SEND_UI) == "function" then pcall(EVAL_SHARE_SEND_UI, navBtns[2].btn) end
  end, shareNavTip())
  -- ★★★1.71.2（第十六轮）[接收] 按钮**已删除**（用户要求：「删除分享右边的按键，和开关状态内的接收方案重复」）。
  --   ★动手前核实过（不是照字面删）：它的 OnClick 调 EVAL_SHARE_RECV_TOGGLE() = 翻转 cfg.share.recv，
  --     而开关组第 3 项「接收方案」调的是**同一个函数** → 确实是重复入口，删掉不丢任何功能。
  cfgWin.nav = navBtns
  -- ★1.71.2 导出**生产代码真正用的布局值**：断言若自己再写一遍常量，
  --   生产代码改了它不会跟着变（「测试复刻逻辑」的老毛病，本轮变异实测：swY 改回 -349 存活）。
  --   让测试读真实值，才能验「开关组真的下移了 40px」这条需求本身。
  cfgWin.layout = { navY = NAV_ROW_Y, navH = NAV_H, navX0 = NAV_X0, navBW = NAV_BW,
                    navRight = NAV_X0 + NAV_BW * 2 + NAV_GAP * 1,
                    closeLeft = CLOSE_LEFT, closeMidY = CLOSE_MIDY, closeW = CLOSE_W, closeH = CLOSE_H,
                    swItemDY = nil }

  -- ★★★1.71.2（第六轮）用户要求：「左侧开关再移动到下面一点、**和按钮对齐**」。
  --   实现方式 = 把横排中线对齐到按钮行中线（NAV_ROW_Y - NAV_H/2）——**不写死 y**，避免与按钮行各自漂移。
  --   ★1.71.2（第十六轮）标题已隐藏，但横排位置**不变**（用户只要求藏标题，没要求挪行）。
  --   ★本项目铁律：同一行混用顶边/中线对齐必然错位 → 这里一律用**中线**反推。
  local SW_ITEM_H = 16 -- swItem 勾选框高度
  local swRowMid = NAV_ROW_Y - NAV_H / 2 -- 按钮行的中线
  local swItemY = swRowMid + SW_ITEM_H / 2 -- 开关横排的顶边 y（cfgCheck 用顶边）
  if cfgWin.layout then cfgWin.layout.swItemDY = swItemY; cfgWin.layout.swItemH = SW_ITEM_H end
  -- ★★★1.71.2（第十六轮）用户要求：「隐藏左侧的开关标题名称」→ **不再调用 cfgHeader**（根本不画）。
  --   ★为什么是「不画」而不是「画完再 Hide」：本客户端 Hide 之后控件仍可能被绘出（黑块那一轮吃过亏），
  --     不建才是真的不显示。swY（标题 y）随之删除——留着就是没人消费的死状态。
  -- ★★★1.71.2 用户要求（选 B）：「开关组三项改成**横排一行**，并把「接收方案」并入该组（共 4 项）」。
  --   原来三项纵排（在分组标题下方的 -18/-42/-66；该标题本轮已隐藏）。横排后每项占位 = 勾选框16 + 间距6 + 标签宽 + 项间隔。
  --   ★标签宽度只能**估算**（本客户端拿不到精确文本宽）→ 留足余量，中文按每字 12px 估。
  --   横排横跨窗口宽度：左栏只有 232px 而四项中文标签需要约 329px（实测算过，左栏放不下）。
  --   右边界给右下角「关闭」按钮让位（关闭在 W-76..W-12），故本行右缘不设限（四项远够不着）。
  local SW_ITEM_GAP = 18 -- 项间距
  local swX = LX
  -- ★★标签宽度：优先用 FontString:GetStringWidth() **实测**（文档里是 FontString(widget) 的方法）；",
  --   拿不到时退化为「按字符数估算」——**不能**用 string.len()：它返回**字节数**，",
  --   中文一字 3 字节 → 宽度被高估 3 倍（本轮实测：4 项被算成 772px，实际只有 364px）。",
  --   ★估算的字符数用「UTF-8 字节数 / 3」近似中文，西文（1 字节/字符）会偏小——",
  --     故实测优先，估算只作兜底且按**中文字数**保守取值。",
  local function swLabelWidth(fs, label)
    if fs and fs.GetStringWidth then
      local ok, w = pcall(fs.GetStringWidth, fs)
      if ok and type(w) == "number" and w > 0 then return w end
    end
    local by = string.len(tostring(label)) -- 字节数
    -- 粗略把字节数换算成字符数：>=3 字节的按 3 字节一字（中文），否则 1 字节一字（西文）
    local chars = (by >= 3) and math.floor(by / 3) or by
    return chars * 13
  end
  -- ★cfgCheck 返回的是 refresh **函数**（不是按钮），拿不到内部 FontString ——",
  --   故这里自建一个**离屏测量用** FontString，用同一字体链量宽度（量完即 Hide）。",
  --   本客户端 FontString:GetStringWidth() 在文档中存在（widgets/FontString#getstringwidth）。",
  local measure = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
    local okf = pcall(measure.SetFont, measure, fp, 11, "OUTLINE")
    if okf then break end
  end
  pcall(measure.Hide, measure)
  local function swItem(label, get, set, tip)
    local c1 = cfgCheck(root, swX, swItemY, label, get, set, Wp, tip)
    table.insert(refreshes, c1)
    pcall(measure.SetText, measure, tostring(label))
    swX = swX + 16 + 6 + swLabelWidth(measure, label) + SW_ITEM_GAP
    return c1
  end
  swItem(L("W_ENABLE"),
    function() return warCfg().enabled ~= false end,
    function(v) warCfg().enabled = v end)
  swItem(L("W_AUTOATK"),
    function() return warCfg().attack ~= false end,
    function(v) warCfg().attack = v end, L("W_AUTOATK_TIP"))
  -- ★★★1.71.2（第四轮）用户要求：「将方案列表的调试信息开关移动到全局配置内的日志分组」。
  --   排查结论（先查后动，本轮实测确认）：它与全局→日志的「记录调试日志」**不是同一个功能**，故**不合并**：
  --     · 「记录调试日志」= cfg.log.on = **总闸门**，Core.logLine 开头就是 if not logEnabled() then return end
  --       → 关掉后 EVAL_LOGLINE **一个字都不记**（数据层「写不写」）
  --     · 本开关 = cfg.wdebug → 只控制 Engine 里那一批 if ... wdebug then EVAL_SAY(...) end
  --       → **日志照写**，只是不把决策原因同步刷到聊天框（输出层「说不说」）
  --   ★为什么原来放在「开关」组是错的：本组其余三项（启用一键宏/自动攻击/接收方案）都是**功能开关**，
  --     惟独它是**日志输出开关**，语义不属于这一组 → 移到「全局 → 日志」分组。
  --   ★用户定名：**「方案技能日志」**（原名「调试日志」与「记录调试日志」几乎同名，
  --     并排显示时会被误认成重复项——本次排查正是由这个歧义引起的）。
  -- ★第 4 项：接收方案开关并入本组（用户要求）。
  --   它原来在 IO 窗的分享第二排；这里是**同一个开关的常驻入口**（读写同一个 cfg.share.recv，单一真值）。
  --   ★不是「搬运」而是「新增入口」：分享发送流程在 IO 窗内，把收发拆到两个窗口会让流程断裂。
  swItem(L("SH_RECV_SW"),
    function()
      if type(EVAL_SHARE_RECV_ON) == "function" then return EVAL_SHARE_RECV_ON() end
      local sh = rawget(_G, "EVAL_HELP_CONFIG") and EVAL_HELP_CONFIG.share
      return (type(sh) == "table") and (sh.recv ~= false) or true
    end,
    function(v)
      if type(EVAL_SHARE_RECV_TOGGLE) == "function" then pcall(EVAL_SHARE_RECV_TOGGLE) end
    end, L("SH_RECV_SW_TIP"))

  -- 右侧：技能规则列表（顺序=优先级；勾选=技能配置开关）
  local RX2 = 128
  cfgHeader(root, RX2, -56, L("W_LIST_H"), Wp)
  -- 1.60.0 列表高度衍生到底部：行数按窗口高度动态算（旧固定 8 行，底部大片空置）——
  -- 起始 y=-74、行距 24，底部给关闭按钮留 120px
  local ROWS = math.floor((H - 120) / 24)
  local function mkSmall(x, y, w, label, fn, list, rightAnch) -- 1.32.2 list：传 G 挂全局页；1.34.1 rightAnch：右缘锚定（i18n 宽窗自适应）
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(15)
    if rightAnch then b:SetPoint("TOPRIGHT", root, "TOPRIGHT", -x, y)
    else b:SetPoint("TOPLEFT", root, "TOPLEFT", x, y) end
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.16, 0.13, 0.08, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 9, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    table.insert(list or Wp, b)
    if list then table.insert(list, bt) end -- 文本属按钮子件随动，但 G 列表契约要求显式登记
    return b, bt
  end
  -- 方案导入/导出窗口入口（md 文本互转）
  -- [添加技能]：直接打开技能编辑窗新增（技能下拉 + 条件逐行配置 + 保存即入列表）
  mkSmall(WIDE and 122 or 92, -56, WIDE and 112 or 80, L("W_ADD"), function()
    EVAL_HELP_SE_OPEN(warCfg().activeProfile or 1)
  end, nil, true)
  mkSmall(16, -56, WIDE and 98 or 68, L("W_IO"), function() EVAL_HELP_IO_TOGGLE() end, nil, true)

  -- 全局 Tab「一键宏」组（1.32.2）：重扫动作条按钮，等同 /eh go rescan——拖动过技能后点一下即可
  -- ★1.71.14 用户截图：「全局配置有重叠，将红色部分底部对齐」——
  --   1.71.12 给「界面」组加了两行子开关后，本组头部（原 -212）与「状态信息UI」（-222 起、高 16）直接叠上。
  --   修法 = 整组改**从底部按钮行向上锚**（底部对齐）：去抖行下缘与导航/关闭按钮行上缘留 6px 间距，
  --   组内行距不变（20px 逐级向上）。★y 一律从 NAV_ROW_Y 推导（底部行 = 布局单一来源），不再写死 -212。
  local MACRO_DB_Y = NAV_ROW_Y + 6 + 15 -- 去抖 [-]/[+] 顶边（mkSmall 高 15）→ 行下缘 = NAV_ROW_Y + 6
  local MACRO_ROW = 20                  -- 组内行距（头 → 重扫 → 提示 → 去抖，与原 -212/-232/-252/-272 同距）
  local mhT = cfgHeader(root, LX, MACRO_DB_Y + MACRO_ROW * 3, L("G_MACRO_H"), G)
  local rsB, rsT = mkSmall(LX, MACRO_DB_Y + MACRO_ROW * 2, 130, L("G_RESCAN"), function() EVAL_GO_RESCAN(false, "menu") end, G)
  local rsTip = uiText(root, 8, 0.6, 0.6, 0.6)
  rsTip:SetPoint("TOPLEFT", root, "TOPLEFT", LX, MACRO_DB_Y + MACRO_ROW)
  rsTip:SetText(L("G_RESCAN_TIP"))
  table.insert(G, rsTip)
  -- 执行去抖窗口（1.54.2）：EVAL_GO 最小执行间隔秒数，默认 0.30（[-][+] 步进 0.05，0=关闭去抖）
  local dbLabel = uiText(root, 9, 0.75, 0.75, 0.75)
  dbLabel:SetPoint("TOPLEFT", root, "TOPLEFT", LX, MACRO_DB_Y - 2) -- 文本比按钮低 2px（中线对齐的老配方）
  dbLabel:SetText(L("G_DEBOUNCE"))
  table.insert(G, dbLabel)
  local dbVal = uiText(root, 9, 1, 0.85, 0.35)
  dbVal:SetPoint("TOPLEFT", root, "TOPLEFT", LX + 124, MACRO_DB_Y - 2)
  table.insert(G, dbVal)
  local function dbGet() return tonumber(c().goDebounce) or 0.3 end
  local function dbShow() dbVal:SetText(string.format("%.2fs", dbGet())) end
  local function dbStep(dv)
    local v = math.floor((dbGet() + dv) * 100 + 0.5) / 100
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    c().goDebounce = v
    dbShow()
  end
  local dbmB = mkSmall(LX + 100, MACRO_DB_Y, 20, "-", function() dbStep(-0.05) end, G)
  mkSmall(LX + 164, MACRO_DB_Y, 20, "+", function() dbStep(0.05) end, G)
  table.insert(refreshes, dbShow)
  -- ★1.71.14 交出真实控件：底部对齐 / 不重叠的断言要读**真位置**（读常量 = 测自己）
  cfgWin.macroUI = { header = mhT, rescan = rsB, dbMinus = dbmB, rowH = 15 }

  -- （1.21.6 起移除底部「激活方案」下拉：与左侧方案栏/战斗信息UI方案行/Shift+按宏//eh go prof N 功能重复）

  for ri = 1, ROWS do
    local y = -74 - (ri - 1) * 24
    local row = {}
    local chk = CreateFrame("Button", nil, root)
    chk:SetWidth(14) chk:SetHeight(14)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", RX2, y)
    pcall(chk.EnableMouse, chk, true)
    pcall(chk.RegisterForClicks, chk, "LeftButtonUp")
    local cOut = chk:CreateTexture(nil, "BACKGROUND")
    uiSolid(cOut, 0.85, 0.70, 0.20, 1)
    cOut:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0)
    cOut:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    local cIn = chk:CreateTexture(nil, "ARTWORK")
    uiSolid(cIn, 0.10, 0.09, 0.06, 1)
    cIn:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1)
    cIn:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
    local cMark = chk:CreateTexture(nil, "OVERLAY")
    uiSolid(cMark, 0.95, 0.80, 0.25, 1)
    cMark:SetPoint("TOPLEFT", chk, "TOPLEFT", 3, -3)
    cMark:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -3, 3)
    chk:SetScript("OnClick", function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local r = p and p.skills[ri + (warUI.offset or 0)]
      if r then
        r.enabled = (r.enabled == false) and true or false
        EVAL_WAR_TAB_REFRESH()
      end
    end)
    row.chk, row.mark = chk, cMark
    table.insert(Wp, chk)
    local icon = root:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 18, y)
    icon:SetWidth(15) icon:SetHeight(15)
    row.icon = icon
    table.insert(Wp, icon)
    local nm = uiText(root, 10, 0.92, 0.88, 0.80)
    nm:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 38, y - 2)
    row.name = nm
    table.insert(Wp, nm)
    local cds = uiText(root, 9, 0.70, 0.70, 0.70)
    cds:SetPoint("TOPLEFT", root, "TOPLEFT", RX2 + 102, y - 3)
    pcall(cds.SetWidth, cds, WIDE and 456 or 336) -- 1.33.0 让位滚动条；1.34.1 宽语言再加宽；1.70.45 随窗口 +100
    pcall(cds.SetJustifyH, cds, "LEFT")
    row.conds = cds
    table.insert(Wp, cds)
    -- 1.61.0 调序按钮改为箭头 + 新增下移；★1.71.9 用户截图反馈：「^ 看着像一条横线、v 是字母」
    --   → 换成真正的三角 **▲/▼**（与本插件「工具箱」「数据检索」的滚动按钮同一套字形，已验证能显示）。
    row.up, row.upText = mkSmall(88, y, 16, "▲", function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and idx > 1 and p.skills[idx] and p.skills[idx - 1] then
        p.skills[idx], p.skills[idx - 1] = p.skills[idx - 1], p.skills[idx]
        EVAL_WAR_TAB_REFRESH()
      end
    end, nil, true)
    row.dn, row.dnText = mkSmall(72, y, 16, "▼", function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and p.skills[idx] and p.skills[idx + 1] then
        p.skills[idx], p.skills[idx + 1] = p.skills[idx + 1], p.skills[idx]
        EVAL_WAR_TAB_REFRESH()
      end
    end, nil, true)
    row.edit = mkSmall(44, y, 24, L("W_EDIT"), function()
      -- 打开技能编辑窗（独立条件属性行 + & / | 关系调整）
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and p.skills[idx] then
        EVAL_HELP_SE_OPEN(w2.activeProfile or 1, idx)
      end
    end, nil, true)
    row.del = mkSmall(16, y, 24, L("W_DEL"), function()
      local p = warCfg().profiles[warCfg().activeProfile or 1]
      local idx = ri + (warUI.offset or 0)
      if p and p.skills[idx] then
        table.remove(p.skills, idx)
        EVAL_WAR_TAB_REFRESH()
      end
    end, nil, true)
    warUI.rows[ri] = row
  end

  -- 滚动条（1.33.0：技能数取消上限后的超高滚动）：▲ 上翻 / ▼ 下翻 + 滚轮；仅超出可见行数时显示
  --   ★1.71.9 与调序按钮一起换成三角（原先的 ^ 像横线、v 是字母）。
  warUI.offset = warUI.offset or 0
  warUI.scrollUp, warUI.scrollUpText = mkSmall(94, -74, 14, "▲", function()
    warUI.offset = math.max(0, (warUI.offset or 0) - 1)
    EVAL_WAR_TAB_REFRESH()
  end, nil, true)
  warUI.scrollDn, warUI.scrollDnText = mkSmall(94, -74 - (ROWS - 1) * 24, 14, "▼", function() -- 1.60.0 跟随动态行数（旧硬编码 -242）
    warUI.offset = (warUI.offset or 0) + 1
    EVAL_WAR_TAB_REFRESH() -- 上限在刷新里收敛
  end, nil, true)
  local okWheel = pcall(root.EnableMouseWheel, root, true)
  if okWheel then
    root:SetScript("OnMouseWheel", function()
      local d = arg1 -- 1.12 风格：滚轮方向在全局 arg1（上=+1）
      if type(d) ~= "number" then return end
      warUI.offset = math.max(0, (warUI.offset or 0) - d)
      EVAL_WAR_TAB_REFRESH()
    end)
  end

  -- ★★★1.71.2（第十六轮）**删除一段历史残留**（它比它记录的那个状态活得更久）。
  --   这里原本写着 `cfgWin.nav = nil`（注释：「不再有底部导航按钮组，断言据此判定」）——
  --   那是「三个按钮被搬到 IO 窗」那一轮的遗留；而**第六轮用户又要求把它们搬回配置窗底部**
  --   （见上方 navBtn），可这个块没删 → 按钮真的建出来了、登记却被当场清空。
  --   ★为什么几轮都没人发现：唯一会读它的 EVAL_TEST_CFG_NAV() **当时没有任何断言调用**（死代码），
  --     于是「导航按钮组」在测试里长期是**空的**；本轮加断言时才当场暴露（got=0 want=2）。
  --   ★判据：**改需求时必须回头删掉描述旧状态的记录**——一句与代码相反的注释比没有注释更危险，
  --     下一个人会照着注释做。导航按钮组只在**上方 navBtn 处**创建，不要在这里再加一组。
  -- ★★另一条留给后人的话：**导出的测试钩子没人用，就等于没有**——它的存在感会让人以为「这块有覆盖」。

  -- 底部关闭按钮（截图同款右下「关闭」）
  local close = CreateFrame("Button", nil, root)
  -- ★1.71.2（第十六轮）改用**单一来源**的几何常量：导航按钮组是按 CLOSE_LEFT / CLOSE_MIDY 对齐的，
  --   而这里是关闭按钮**真正被创建**的地方——两处各写一遍的话，改一处就会让导航组静默错位。
  close:SetWidth(CLOSE_W) close:SetHeight(CLOSE_H)
  close:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", CLOSE_RIGHT, CLOSE_BOTTOM)
  pcall(close.EnableMouse, close, true)
  pcall(close.RegisterForClicks, close, "LeftButtonUp")
  local cbg = close:CreateTexture(nil, "BACKGROUND")
  uiSolid(cbg, 0.16, 0.13, 0.08, 1)
  cbg:SetPoint("TOPLEFT", close, "TOPLEFT", 0, 0)
  cbg:SetPoint("BOTTOMRIGHT", close, "BOTTOMRIGHT", 0, 0)
  local ct = uiText(close, 11, 0.95, 0.82, 0.35)
  ct:SetPoint("CENTER", close, "CENTER", 0, 0)
  ct:SetText(L("CLOSE"))
  close:SetScript("OnClick", function() root:Hide() end)

  cfgWin.root = root
  root:SetScript("OnHide", function() EVAL_DD_HIDE() end) -- 关窗收起下拉（1.19.0）
  cfgWin.refresh = function() for _, r in ipairs(refreshes) do pcall(r) end end
  if type(EVAL_TB_BUILD) == "function" then EVAL_TB_BUILD(root, pages[3], refreshes) end -- 工具箱 Tab（1.68.0 Toolbox.lua 独立载入）
  if type(EVAL_DS_BUILD) == "function" then EVAL_DS_BUILD(root, pages[4], refreshes) end -- 数据检索 Tab（DataSearch.lua 独立载入，基于 UnrealQuest 数据库）
  if type(EVAL_IB_BUILD) == "function" then EVAL_IB_BUILD(root, pages[5], refreshes) end -- 图标库 Tab（IconBrowser.lua 独立载入）
  EVAL_HELP_CFG_SETTAB(c().cfgTab or 1)
  return root
end

-- ===== 方案重命名弹窗（1.17.0：替代底部输入框改名流程） =====
-- EditBox 在本客户端可能不渲染 → 加回声行（OnTextChanged 实时镜像输入内容，盲打也可见）
local rpUI = {}

function EVAL_HELP_RP_BUILD()
  if rpUI.root then return end
  local W, H = 300, 150
  local root = CreateFrame("Frame", "EVAL_HELP_RP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 120)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 4) titleBar:SetHeight(22)
  titleBar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 121)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("RP_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local lab = uiText(root, 10, 0.85, 0.85, 0.85)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  lab:SetText("新方案名：")

  -- 输入框（单行）
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_RP_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(220) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -54)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 11) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(24)
    local ebEdge = root:CreateTexture(nil, "BORDER")
    uiSolid(ebEdge, 0.85, 0.70, 0.20, 0.8)
    ebEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebEdge:SetWidth(W - 28) ebEdge:SetHeight(1)
    rpUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -54)
    noEb:SetText(L("RP_NOEB"))
  end

  -- 回声行：实时镜像输入内容（EditBox 不渲染时的保底可见性）
  local echo = uiText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -80)
  pcall(echo.SetWidth, echo, W - 40)
  pcall(echo.SetJustifyH, echo, "LEFT")
  rpUI.echo = echo
  if rpUI.eb then
    rpUI.eb:SetScript("OnTextChanged", function()
      local ok, t = pcall(rpUI.eb.GetText, rpUI.eb)
      if ok and type(t) == "string" then echo:SetText(t) end
    end)
  end

  local function apply()
    local nm = ""
    if rpUI.eb then
      local ok, t = pcall(rpUI.eb.GetText, rpUI.eb)
      if ok and type(t) == "string" then nm = t end
    end
    nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
    local w2 = warCfg()
    local p = rpUI.target and w2.profiles[rpUI.target]
    if p and nm ~= "" then
      p.name = nm
      say("方案已改名: " .. nm)
    end
    rpUI.target = nil
    root:Hide()
    EVAL_WAR_TAB_REFRESH()
  end
  if rpUI.eb then
    rpUI.eb:SetScript("OnEnterPressed", function() apply() end)
    rpUI.eb:SetScript("OnEscapePressed", function() root:Hide() end)
  end

  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(80) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(70, L("BTN_OK"), function() apply() end)
  bBtn(160, L("BTN_CANCEL"), function() root:Hide() end)

  root:Hide()
  rpUI.root = root
end

function EVAL_HELP_RP_OPEN(idx)
  EVAL_HELP_RP_BUILD()
  local w2 = warCfg()
  if not w2.profiles[idx] then return end
  rpUI.target = idx
  local nm = tostring(w2.profiles[idx].name or "")
  if rpUI.eb then
    pcall(rpUI.eb.SetText, rpUI.eb, nm)
    pcall(rpUI.eb.SetFocus, rpUI.eb)
  end
  if rpUI.echo then rpUI.echo:SetText(nm) end
  rpUI.root:Show()
end


-- ===== 通用名称输入弹窗（1.29.0：仿 1.17.0 重命名弹窗回声行范式——EditBox 可能不渲染 → 金色回声行保底） =====
-- EVAL_TN_OPEN(标题, 当前值, onOk(名称))；确定/回车回调，取消/Esc 直接关。
local tnUI = {}

function EVAL_TN_BUILD()
  if tnUI.root then return end
  local W, H = 300, 150
  local root = CreateFrame("Frame", "EVAL_HELP_TN", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 130) -- 高于技能编辑窗(100)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 4) titleBar:SetHeight(22)
  titleBar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 131)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  tnUI.titleText = title
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local lab = uiText(root, 10, 0.85, 0.85, 0.85)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  lab:SetText("目标名称：")

  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_TN_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(220) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -54)
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 11, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 11) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -48)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(24)
    tnUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -54)
    noEb:SetText(L("TN_NOEB"))
  end

  -- 回声行：实时镜像输入内容（盲打保底可见）
  local echo = uiText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -80)
  pcall(echo.SetWidth, echo, W - 40)
  pcall(echo.SetJustifyH, echo, "LEFT")
  tnUI.echo = echo
  if tnUI.eb then
    tnUI.eb:SetScript("OnTextChanged", function()
      local ok, t = pcall(tnUI.eb.GetText, tnUI.eb)
      if ok and type(t) == "string" then echo:SetText(t) end
    end)
  end

  local function apply()
    local nm = ""
    if tnUI.eb then
      local ok, t = pcall(tnUI.eb.GetText, tnUI.eb)
      if ok and type(t) == "string" then nm = t end
    end
    nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
    if nm ~= "" and tnUI.onOk then tnUI.onOk(nm) end
    root:Hide()
  end
  if tnUI.eb then
    tnUI.eb:SetScript("OnEnterPressed", function() apply() end)
    tnUI.eb:SetScript("OnEscapePressed", function() root:Hide() end)
  end

  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(80) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(70, L("BTN_OK"), function() apply() end)
  bBtn(160, L("BTN_CANCEL"), function() root:Hide() end)

  root:Hide()
  root:SetScript("OnHide", function() tnUI.onOk = nil end)
  tnUI.root = root
end

function EVAL_TN_OPEN(title, cur, onOk)
  EVAL_TN_BUILD()
  tnUI.onOk = onOk
  if tnUI.titleText then tnUI.titleText:SetText(title or "输入名称") end
  if tnUI.eb then
    pcall(tnUI.eb.SetText, tnUI.eb, cur or "")
    pcall(tnUI.eb.SetFocus, tnUI.eb)
  end
  if tnUI.echo then tnUI.echo:SetText(cur or "") end
  tnUI.root:Show()
end
-- ★1.71.3 断言入口：通用名称输入弹窗（跟随 / 物品 / 指定目标 都走它）。
--   ★为什么要它：这些「点了弹框输入」的入口以前**没有任何观测口**——「点了没反应」在测试里完全看不见，
--     而本轮「跟随:指定名字…」正是靠它落值（判据同「要验点了会弹，就必须点一下看结果」）。
function EVAL_TEST_TN_SHOWN()
  return (tnUI.root and tnUI.root:IsShown()) and true or false
end
function EVAL_TEST_TN_TITLE()
  if not tnUI.titleText then return nil end
  local ok, t = pcall(tnUI.titleText.GetText, tnUI.titleText)
  return ok and t or nil
end
-- 走**真实输入框 + 真实回车处理器**（等价于玩家打完字按回车），不是直接调回调
function EVAL_TEST_TN_COMMIT(txt)
  if not (tnUI.root and tnUI.eb) then return false end
  pcall(tnUI.eb.SetText, tnUI.eb, tostring(txt or ""))
  local ok, fn = pcall(tnUI.eb.GetScript, tnUI.eb, "OnEnterPressed")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end

-- 删除方案（至少保留一个；activeProfile 随删除左移/收敛）
function EVAL_WAR_DEL_PROFILE(idx)
  local w2 = warCfg()
  if table.getn(w2.profiles) <= 1 then say("至少保留一个方案") return false end
  if not w2.profiles[idx] then return false end
  say("已删除方案: " .. tostring(w2.profiles[idx].name))
  table.remove(w2.profiles, idx)
  if (w2.activeProfile or 1) > table.getn(w2.profiles) then
    w2.activeProfile = table.getn(w2.profiles)
  elseif (w2.activeProfile or 1) > idx then
    w2.activeProfile = (w2.activeProfile or 1) - 1
  end
  pcall(EVAL_WAR_TAB_REFRESH)
  return true
end

-- 一键宏 Tab 列表刷新（方案按钮选中态 / 技能行内容 / 图标选择器高亮）
-- ★1.71.2 方案列表刷新计数。
--   为什么需要它：用户报的 bug 是「导入完成但列表没刷新」——这是**调用有没有发生**的问题，
--   而「列表内容对不对」在数据层永远是对的（profiles 确实写进去了）。
--   ★判据：凡是要验「某动作有没有触发刷新」，就必须**计数**，不能只看最终数据。
--   ★必须声明在本函数**之前**（词法作用域）——放到后面会被 DECL ORDER CHECK 当场抓出。
local warRefreshCount = 0
local function warRefreshTick() warRefreshCount = warRefreshCount + 1 end
-- ★1.71.9 断言入口：技能列表「调序 ▲▼」与「滚动 ▲▼」四个按钮的**真实文本**。
--   ★为什么必须读控件：用户看到的是控件上的字，生产代码里的那份常量只是副本 ——
--     读常量 = 测自己（本项目「断言里写死布局常量」的老坑）。
function EVAL_TEST_WAR_ARROWS()
  local function txt(fs)
    if not fs then return nil end
    local ok, v = pcall(fs.GetText, fs)
    return ok and v or nil
  end
  -- ★读 cfgWin.warUI（文件级表，cfgBuild 建好后一直有效）——本函数定义在 cfgBuild 内部，
  --   直接引用那个局部名会解析成全局 nil（实测踩到：attempt to index a nil value (global 'warUI')）。
  local w = cfgWin.warUI or {}
  local out = { rowUp = nil, rowDn = nil, scrollUp = txt(w.scrollUpText), scrollDn = txt(w.scrollDnText) }
  local r1 = w.rows and w.rows[1]
  if r1 then out.rowUp = txt(r1.upText) out.rowDn = txt(r1.dnText) end
  return out
end
function EVAL_TEST_WAR_REFRESH_COUNT() return warRefreshCount end

function EVAL_WAR_TAB_REFRESH()
  warRefreshTick() -- ★1.71.2 计数（见 warRefreshTick 说明：只验数据验不出「没刷新」）
  if not EVAL_IS_SCANNED() then EVAL_GO_RESCAN(true, "auto") end -- 1.32.9 自愈：初始化重扫若早于动作条就绪，这里补扫（否则技能行图标全灰）
  local warUI = cfgWin.warUI
  if not warUI then return end
  local w2 = warCfg()
  for i, pb in ipairs(warUI.profBtns) do
    local prof = w2.profiles[i]
    if prof then
      pb.text:SetText(tostring(prof.name or ("方案" .. i)))
      local sel = (w2.activeProfile or 1) == i
      pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
      pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.75, sel and 0.9 or 0.72, sel and 0.4 or 0.6)
    elseif i == table.getn(w2.profiles) + 1 then
      pb.text:SetText("+")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.10, 0.10, 0.10, 1)
    else
      pb.text:SetText("")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.06, 0.05, 0.04, 1)
    end
    -- [删] 仅存在的方案显示；待确认状态红色高亮
    if pb.del then
      if prof then
        pb.del:Show()
        local armed = (warUI.delArm == i) and (GetTime() - (warUI.delArmT or 0) < 5)
        pcall(pb.delBg.SetVertexColor, pb.delBg, armed and 0.75 or 0.25, 0.10, 0.10, 1)
      else
        pb.del:Hide()
      end
    end
  end
  local p = w2.profiles[w2.activeProfile or 1]
  -- 1.33.0 滚动：offset 收敛到合法范围；滚动按钮仅在超高时显示
  local cnt = (p and p.skills) and table.getn(p.skills) or 0
  local rowsN = table.getn(warUI.rows) -- 1.33.3 修：ROWS 是 cfgBuild 内 local，本函数拿不到（nil 算术报错）
  local maxOff = math.max(0, cnt - rowsN)
  warUI.offset = math.max(0, math.min(warUI.offset or 0, maxOff))
  if warUI.scrollUp then
    if cnt > rowsN then
      pcall(warUI.scrollUp.Show, warUI.scrollUp) pcall(warUI.scrollDn.Show, warUI.scrollDn)
    else
      pcall(warUI.scrollUp.Hide, warUI.scrollUp) pcall(warUI.scrollDn.Hide, warUI.scrollDn)
    end
  end
  for ri, row in ipairs(warUI.rows) do
    local r = p and p.skills[ri + warUI.offset]
    local widgets = { row.chk, row.icon, row.name, row.conds, row.up, row.dn, row.edit, row.del }
    for _, wgt in ipairs(widgets) do
      if r then pcall(wgt.Show, wgt) else pcall(wgt.Hide, wgt) end
    end
    if r then
      if r.enabled ~= false then row.mark:Show() else row.mark:Hide() end
      local t0 = wicon(r.skill)
      if t0 then
        pcall(row.icon.SetTexture, row.icon, t0)
        pcall(row.icon.SetVertexColor, row.icon, 1, 1, 1)
      else
        uiSolid(row.icon, 0.25, 0.25, 0.25, 1)
      end
      row.name:SetText(tostring(r.skill))
      row.conds:SetText(uiEsc(EVAL_GROUP_STR(r.groups))) -- 1.61.1 | 显示转义
    end
  end
  -- ★★★1.71.10 方案名 / 数量变了 → 战斗信息UI 的「方案切换行」必须重排（按钮宽度按名字实测算、
  --   行数变了帧高与下方技能带也要跟着挪）→ **整体重建**。
  --   ★这里是用户改方案名的**唯一入口**（配置窗改名/增删、导入分享都最终走它），不是每帧路径；
  --     每 0.15s 的 tick 里**一次都不量宽**（频率防护）。
  local sigNow = ""
  for i = 1, table.getn(w2.profiles or {}) do
    sigNow = sigNow .. tostring((w2.profiles[i] or {}).name or "") .. "|"
  end
  if ui and ui.root and ui.profSig ~= nil and ui.profSig ~= sigNow then
    local wasShown = false
    pcall(function() wasShown = ui.root:IsVisible() and true or false end)
    EVAL_HELP_UI_BUILD()
    if ui.root and wasShown then pcall(ui.root.Show, ui.root) end
  end
  if ui then ui.profSig = sigNow end
end

-- Tab 切换：按控件列表显式 Show/Hide（本客户端可见性契约：走控件列表，不靠父框架传播）
function EVAL_HELP_CFG_SETTAB(idx)
  if not cfgWin.pages then return end
  cfgWin.tab = idx
  c().cfgTab = idx
  for i, p in ipairs(cfgWin.pages) do
    local on = (i == idx)
    for _, wgt in ipairs(p.widgets) do
      if on then pcall(wgt.Show, wgt) else pcall(wgt.Hide, wgt) end
    end
    if on then
      pcall(p.bg.SetVertexColor, p.bg, 0.45, 0.35, 0.10, 1)
      pcall(p.text.SetTextColor, p.text, 1, 0.90, 0.40)
    else
      pcall(p.bg.SetVertexColor, p.bg, 0.16, 0.13, 0.08, 1)
      pcall(p.text.SetTextColor, p.text, 0.70, 0.65, 0.55)
    end
  end
  if idx == 2 then pcall(EVAL_WAR_TAB_REFRESH) end
  if idx == 3 and type(EVAL_TB_REFRESH) == "function" then pcall(EVAL_TB_REFRESH) end -- 工具箱
  if idx == 4 and type(EVAL_DS_REFRESH) == "function" then pcall(EVAL_DS_REFRESH) end -- 数据检索
  if idx == 5 and type(EVAL_IB_REFRESH) == "function" then pcall(EVAL_IB_REFRESH) end -- 图标库
end

-- ★1.71.2 测试钩子：配置窗底部导航按钮（模版/分享/接收）的几何。
--   用途：验「它们在关闭按钮左侧、同一行、不重叠、不越界」——
--   否则这类布局问题只能靠人眼看截图（正是本轮改动的起因）。
-- ★1.71.3 读值口：当前激活的 Tab 序号。供**独立载入**的页面文件判断「本 Tab 是否激活」
--   （例如 IconBrowser 的滚轮翻页）——它们看不到 cfgWin（那是本文件的 local）。
function EVAL_HELP_CFG_TAB() return cfgWin.tab end
-- ★1.71.3 读值口：配置窗的滚轮脚本。多个页面（工具箱/数据检索/图标库）**链式接管**同一个 OnMouseWheel，
--   断言要验「谁消费了滚轮、谁转发出去」就必须拿到**装上去的那个真脚本**（不是在测试里复刻一份）。
-- ★1.71.3 读值口：配置窗各 Tab 的**标签文本**（读真实按钮，不读构建时的那份局部表）。
--   用途：新增 Tab 时「名单加了、按钮没加」或「语言键漏了」都会被断言当场抓住。
function EVAL_TEST_CFG_TAB_NAMES()
  local out = {}
  for i = 1, table.getn(cfgWin.pages or {}) do
    local p = cfgWin.pages[i]
    local ok, t = pcall(p.text.GetText, p.text)
    out[i] = ok and t or nil
  end
  return out
end
function EVAL_CFG_WHEEL_SCRIPT()
  if not cfgWin.root then return nil end
  local ok, fn = pcall(cfgWin.root.GetScript, cfgWin.root, "OnMouseWheel")
  return ok and fn or nil
end
-- ★1.71.3 读值口：技能编辑窗「异常标记」用的标记图标路径（现在是白感叹号）。
--   ★IconBrowser 的「本插件在用」分组要列出它，但**不能在那里另抄一份路径**——两份名单迟早漂移。
function EVAL_HELP_SE_WARN_ICON() return SE_WARN_ICON end
-- ★1.71.3 读值口：**整套**状态标记（白=不可用 / 黄=待测试）。
--   ★同样给 IconBrowser 用（两枚都要进「本插件在用」；只报白的会漏掉黄的那枚）。
function EVAL_HELP_SE_MARK_ICONS() return { unavail = SE_MARK_UNAVAIL, test = SE_MARK_TEST } end

function EVAL_TEST_CFG_NAV()
  local out = {}
  for i, e in ipairs(cfgWin.nav or {}) do
    local ok, p, _, _, ox, oy = pcall(e.btn.GetPoint, e.btn, 1)
    local okw, aw = pcall(e.btn.GetWidth, e.btn)
    local okc, fn = pcall(e.btn.GetScript, e.btn, "OnClick")
    out[i] = {
      x = (ok and type(ox) == "number") and ox or nil,
      y = (ok and type(oy) == "number") and oy or nil,
      point = ok and p or nil,
      w = (okw and type(aw) == "number") and aw or nil,
      -- ★1.71.2（第十六轮）身份与接线：label 取**登记值**（不从控件反查，桩里文本不可靠）；
      --   hasClick 用于「删掉一个按钮」这类需求的反向哨兵——**不许留空壳凑数**。
      label = e.label or "",
      hasClick = (okc and type(fn) == "function") and true or false,
      -- ★1.71.2（第十七轮）暴露按钮本体：断言要在**真实 OnClick 闭包**上点一下
      --   （例如「点分享不该弹出导入导出窗」——只有真点才知道）。
      btn = e.btn,
    }
  end
  return out
end

-- ★1.71.2（第十六轮）断言专用：配置窗**真的画出来的**章节标题文案（按绘制顺序）。
--   本轮需求是「隐藏左侧的开关标题」——要验的是「它根本没被画」，不是「它被 Hide 了」
--   （本客户端 Hide 后控件仍可能被绘出，本项目在黑块那一轮吃过亏）。
--   反向哨兵同样必要：断言「不在」时，必须先证明这份登记表**本来会响**（其它标题仍在里面）。
function EVAL_TEST_CFG_HEADERS()
  local out = {}
  for _, t in ipairs(cfgHeaderTexts) do table.insert(out, t) end
  return out
end

function EVAL_HELP_CFG_TOGGLE()
  local win = cfgBuild()
  if win:IsVisible() then
    win:Hide()
  else
    -- 每次弹窗计算位置：飞出屏幕（拖太远/改过分辨率）→ 回归视野中心
    if uiOffscreen(win) then
      win:ClearAllPoints()
      win:SetPoint("CENTER", UIParent, "CENTER", -320, 60)
      c().cfgPos = nil
    end
    if cfgWin.refresh then cfgWin.refresh() end
    -- ★1.71.2 用户要求「每次打开配置都进行一次技能扫描（静默日志）」：
    --   配置窗里的技能列表/图标/条件参数全靠 wslots（动作条扫描结果），
    --   而动作条随时会变（换装备、拖新技能、切天赋）——每次打开都以**当前**动作条为准。
    --   quiet=true：不刷聊天框，只写调试日志缓冲（EVAL_GO_RESCAN 内的静默日志分支）。
    if type(EVAL_GO_RESCAN) == "function" then pcall(EVAL_GO_RESCAN, true, "open") end
    EVAL_HELP_CFG_SETTAB(cfgWin.tab or c().cfgTab or 1)
    win:Show()
  end
end

-- ★★★1.71.2 用户截图：EH 按钮压在小地图**左下角**、和地图边缘/边框叠在一起。
--   根因：默认锚点写成「mb 的 TOPRIGHT 对 Minimap 的 TOPLEFT」——看名字像「小地图左上」，
--   实际是把按钮**挂在小地图左边缘**，而小地图是**圆形**：矩形按钮贴左边缘时，
--   上半部在小地图外（正常），下半部就落进圆形轮廓里 → 视觉上「压在左下角」。
--   ★判据（本轮定）：**锚点描述的是邻居的哪条边，不是「我想要哪个角」**——
--     要让按钮落在圆外侧，必须锚到 **Minimap 的右边缘（RIGHT）之外**，而不是 TOPLEFT。
--   同时：① 默认位置整体避开小地图下方的按钮簇；② 记忆位置若**压在小地图上**也要丢弃
--   （原来只判「飞出屏幕」，压在圆里不算越界 → 一旦拖进去就永久记住，用户每次登录都看到它压着）。
local MB_SIZE = 24
local function mbAnchorDefault(mb)
  if not mb then return end
  pcall(mb.ClearAllPoints, mb)
  -- 优先用 MinimapCluster（它是有实际尺寸的容器），退而用 Minimap
  local anchor = nil
  if type(MinimapCluster) == "table" or type(MinimapCluster) == "userdata" then anchor = MinimapCluster end
  if not anchor and (type(Minimap) == "table" or type(Minimap) == "userdata") then anchor = Minimap end
  if anchor then
    -- ★落在容器**左侧之外**、且**贴在垂直中部**（圆的左右两侧是最宽处，矩形不会被圆吃掉）
    local ok = pcall(mb.SetPoint, mb, "RIGHT", anchor, "LEFT", -6, 0)
    if ok then return end
  end
  pcall(mb.SetPoint, mb, "TOPRIGHT", UIParent, "TOPRIGHT", -8, -8)
end
-- 按钮是否「压在小地图上」（矩形与小地图外接方框相交）——比 uiOffscreen 更严的一层
-- ★★前置声明（无 = 号）：纯函数 EVAL_TEST_RECT_HITS_CIRCLE 定义在本函数**之后**，
--   而 Lua 的作用域是**词法**的——不前置声明的话，mbOverlapsMinimap 里的引用会绑到**全局 nil**，
--   表现为「拖动/登录时的越界判定直接红字」。这正是本项目累计十几次的同一类坑（A 节）。
local EVAL_TEST_RECT_HITS_CIRCLE
local function mbOverlapsMinimap(mb)
  if not mb then return false end
  local okm, m = pcall(function() return Minimap end)
  if not (okm and m) then return false end
  local okl, l = pcall(mb.GetLeft, mb) local okr, r = pcall(mb.GetRight, mb)
  local okt, t = pcall(mb.GetTop, mb) local okb, b = pcall(mb.GetBottom, mb)
  local oml, ml = pcall(m.GetLeft, m) local omr, mr = pcall(m.GetRight, m)
  local omt, mt = pcall(m.GetTop, m) local omb, mbb = pcall(m.GetBottom, m)
  if not (okl and okr and okt and okb and oml and omr and omt and omb) then return false end
  -- ★每个坐标都必须真的是数字：少一个就放弃判定（返回 false = 「没压上」），
  --   绝不让 nil 进入算术（本轮实测：桩的某一边缺失 → attempt to perform arithmetic on nil）。
  --   ★这条防御是**必要**的：本函数的调用点在 OnDragStop（用户松手那一刻），
  --     抛错会在拖动时弹红字——宁可漏判一次，也不能在交互路径上炸。
  -- ★同上：ipairs 遇 nil 即停，这里必须显式判定（该函数在 OnDragStop 上，抛错=拖动弹红字）
  if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then return false end
  if type(ml) ~= "number" or type(mr) ~= "number" or type(mt) ~= "number" or type(mbb) ~= "number" then return false end
  -- ★判定逻辑只有一份实现（下面的纯函数）：本函数只负责取坐标再调它。
  --   这样断言可以直接**注入几何**构造用例，不必依赖测试桩会做锚点解算（它不会）。
  return EVAL_TEST_RECT_HITS_CIRCLE(l, t, r, b, ml, mt, mr, mbb)
end
-- ★1.71.2 圆-矩形相交的纯函数（内切圆近似：小地图是圆的，矩形贴着左边缘时下半部会压进圆里）
--   留 2px 余量，避免「刚好擦边」被判成压上。
-- ★注意：因为上面有「前置声明 local EVAL_TEST_RECT_HITS_CIRCLE」，这里是给**那个 local** 赋值
--   （不是新建全局）。测试需要全局入口 → 下面单独挂一次导出桥（项目既有范式）。
function EVAL_TEST_RECT_HITS_CIRCLE(rl, rt, rr, rb, ml, mt, mr2, mb2)
  -- ★★绝不能用 ipairs 遍历「可能含 nil 的表」：Lua 的 ipairs 遇到 nil **立即停止**（不是跳过），
  --   表里第一个元素是 nil 时循环体一次都不执行 → nil 直接进入下面的算术 → 抛错。
  --   ★这正是本项目 1.71.1 记过的同一个坑（ipairs({st.team, st.teamRaid}) 遇 nil 洞即停）；
  --     那次代价是「团队成员查不到」，这次是「拖动弹红字」，形态不同、根因完全一样。
  --   → 改为显式逐个判定（八个值写八次，丑但绝对正确）。
  if type(rl) ~= "number" or type(rt) ~= "number" or type(rr) ~= "number" or type(rb) ~= "number" then return false end
  if type(ml) ~= "number" or type(mt) ~= "number" or type(mr2) ~= "number" or type(mb2) ~= "number" then return false end
  local cx, cy = (ml + mr2) / 2, (mt + mb2) / 2
  local rad = math.min(mr2 - ml, mt - mb2) / 2
  if rad <= 0 then return false end
  local nx = math.max(rl, math.min(cx, rr))
  local ny = math.max(rb, math.min(cy, rt))
  local dx, dy = nx - cx, ny - cy
  return (dx * dx + dy * dy) < (rad + 2) * (rad + 2)
end
EVAL_TEST_RECT_HITS_CIRCLE_G = EVAL_TEST_RECT_HITS_CIRCLE -- 全局导出桥（测试用）
-- 小地图图标：挂在**小地图外侧**的按钮。
-- UnrealQuest 实测要点：parent 用 UIParent（不是 Minimap——它是地图外的 chrome）；
-- 锚链 Minimap → MinimapCluster → UIParent 右上角；RegisterForClicks 注册点击；
-- 悬停用 OnEnter/OnLeave + GameTooltip 提示（不用 SetHighlightTexture）。
-- 按钮本身支持拖拽换位（Button 手柄配方），位置存 cfg.mbPos，重登恢复；
-- 拖动松手会跟着触发一次 OnClick，用 mbDragMoved 标记抑制这次误触。
-- ★1.71.13 用户要求：「配置按钮 换图标，尺寸和图标尺寸保持一致，不用设置外边框。」
--   → 按钮 = 一枚宏图标本身：图标**占满整个按钮**（无边框、无「EH」字），边长 26（与图标库单格一致）。
--   ★图标在 VARIABLES_LOADED 后从宏图标表**按名字**挑（载入期接口未必就绪，索引也不保证稳定）；
--     挑不到（接口缺席 / 没有匹配项）→ 退回旧的「金框 + 暗底 + EH」样式 ——
--     **不许留空白按钮**（图标拿不到时，打开配置窗的入口不能跟着消失）。
local minimapBtn = nil
local mbDragMoved = false
local mbIconTex = nil             -- 唯一的常驻视觉件：图标纹理（占满按钮）
local mbIconPath = nil            -- 已贴上的图标路径（nil = 还没贴上）
local mbRing, mbText = nil, nil   -- 兜底样式（仅图标拿不到时才建；悬停变色与「清空 EH 字」要引用）

-- ★图标挑选抽成**纯函数**（脱离游戏可测）：按候选前缀的**优先级**挑（不是宏图标表的表序）；
--   enumFn(i) → 路径或 nil（本客户端 GetMacroIconInfo 的形态，与 IconBrowser.lua 同源）。
function EVAL_HELP_MB_PICKICON(n, enumFn)
  if type(n) ~= "number" or n < 1 or type(enumFn) ~= "function" then return nil end
  -- 「工具箱」气质优先：扳手 > 工程学 > 齿轮 > 小装置 > 书（★大写化后做前缀匹配，名尾的 _TEX 不妨碍）
  local CANDS = { "^INV_MISC_WRENCH", "^TRADE_ENGINEERING", "^INV_MISC_GEAR", "^INV_GIZMO", "^INV_MISC_BOOK" }
  local names = {}
  for i = 1, n do
    local ok, p = pcall(enumFn, i)
    if ok and type(p) == "string" and p ~= "" then
      local seg = string.match(p, "[^\\/]+$") or p
      seg = string.match(seg, "^(.-)%.[%a]+$") or seg
      names[table.getn(names) + 1] = { path = p, up = string.upper(seg) }
    end
  end
  for _, pat in ipairs(CANDS) do
    for i = 1, table.getn(names) do
      if string.find(names[i].up, pat) then return names[i].path end
    end
  end
  return nil
end

do
  local mb = CreateFrame("Button", "EVAL_HELP_MINIMAP", UIParent)
  mb:SetWidth(26) mb:SetHeight(26) -- ★1.71.13 边长 26（与图标库单格一致；按钮 = 图标，无内缩）
  pcall(mb.SetFrameStrata, mb, "MEDIUM")
  pcall(mb.EnableMouse, mb, true)
  pcall(mb.RegisterForClicks, mb, "LeftButtonUp")
  pcall(mb.RegisterForDrag, mb, "LeftButton")
  mbAnchorDefault(mb) -- ★1.71.2 默认落在小地图**左侧之外**（旧的 TOPLEFT 锚点会压在圆的左下角）
  -- ★1.71.13 唯一的常驻视觉件 = 图标纹理（占满整个按钮，无边框）；
  --   贴图未到位前 = 暗底（与旧内底同色）；旧的「金框 + EH」只在 SETICON 失败时补建（见下）。
  local iconTex = mb:CreateTexture(nil, "ARTWORK")
  iconTex:SetPoint("TOPLEFT", mb, "TOPLEFT", 0, 0)
  iconTex:SetPoint("BOTTOMRIGHT", mb, "BOTTOMRIGHT", 0, 0)
  pcall(iconTex.SetTexture, iconTex, "Interface\\Buttons\\WHITE8X8")
  pcall(iconTex.SetVertexColor, iconTex, 0.12, 0.10, 0.06, 1)
  mbIconTex = iconTex
  mb:SetScript("OnDragStart", function()
    mbDragMoved = false
    pcall(mb.SetMovable, mb, true)
    pcall(mb.StartMoving, mb)              -- warm-up 两步（实测配方）
    pcall(mb.StopMovingOrSizing, mb)
    pcall(mb.StartMoving, mb)
  end)
  mb:SetScript("OnDragStop", function()
    pcall(mb.StopMovingOrSizing, mb)
    mbDragMoved = true
    local ok, point, _, relPoint, x, y = pcall(mb.GetPoint, mb, 1)
    if ok and type(point) == "string" then
      c().mbPos = {
        point = point,
        relPoint = (type(relPoint) == "string") and relPoint or point,
        x = (type(x) == "number") and x or 0,
        y = (type(y) == "number") and y or 0,
      }
      -- ★1.71.2 拖完当场校验：压在小地图上 / 飞出屏幕的位置**不落盘**，
      --   直接弹回默认锚点。放在这里而不是只放在登录恢复处：用户拖歪的那一刻就纠正，
      --   不必等下次登录才「自己跳回去」（那会显得像 bug）。
      if uiOffscreen(mb) or mbOverlapsMinimap(mb) then
        c().mbPos = nil
        mbAnchorDefault(mb)
      end
    end
  end)
  mb:SetScript("OnEnter", function()
    -- 悬停反馈：兜底样式染金框；图标模式给图标染一层金（未贴图前保持暗底不动）
    if mbRing then pcall(mbRing.SetVertexColor, mbRing, 1, 0.88, 0.40, 1)
    elseif mbIconPath then pcall(mbIconTex.SetVertexColor, mbIconTex, 1, 0.88, 0.40) end
    if GameTooltip and GameTooltip.SetOwner then
      pcall(GameTooltip.SetOwner, GameTooltip, mb, "ANCHOR_LEFT")
      if GameTooltip.AddLine then
        -- ★1.71.13 用户要求：tooltip 文案美化（全职业一键宏 / 常用工具箱 / 世界数据库检索），走语言包
        pcall(GameTooltip.AddLine, GameTooltip, L("MB_TIP_TITLE"), 1, 0.85, 0.35)
        pcall(GameTooltip.AddLine, GameTooltip, L("MB_TIP_1"), 0.92, 0.88, 0.80)
        pcall(GameTooltip.AddLine, GameTooltip, L("MB_TIP_2"), 0.92, 0.88, 0.80)
        pcall(GameTooltip.AddLine, GameTooltip, L("MB_TIP_3"), 0.92, 0.88, 0.80)
        pcall(GameTooltip.AddLine, GameTooltip, L("MB_TIP_HINT"), 0.6, 0.6, 0.6)
      end
      pcall(GameTooltip.Show, GameTooltip)
    end
  end)
  mb:SetScript("OnLeave", function()
    if mbRing then pcall(mbRing.SetVertexColor, mbRing, 0.85, 0.70, 0.20, 1)
    elseif mbIconPath then pcall(mbIconTex.SetVertexColor, mbIconTex, 1, 1, 1)
    elseif mbIconTex then pcall(mbIconTex.SetVertexColor, mbIconTex, 0.12, 0.10, 0.06, 1) end
    if GameTooltip and GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  mb:SetScript("OnClick", function()
    if mbDragMoved then mbDragMoved = false return end -- 拖动松手后的那次抬起不算点击
    EVAL_HELP_CFG_TOGGLE()
  end)
  minimapBtn = mb
end

-- ★贴图 + 状态同步只此一份（SETICON 自动挑 / SETCUSTOM 用户右键挑 共用）；
--   ★贴上图标时要把兜底留下的「EH」字**清空**（OVERLAY 层会压在图标上；「先清空再隐藏」的既有配方）。
local function mbApplyIcon(path)
  pcall(mbIconTex.SetTexture, mbIconTex, path)
  pcall(mbIconTex.SetVertexColor, mbIconTex, 1, 1, 1)
  mbIconPath = path
  if mbText then pcall(mbText.SetText, mbText, "") end
end

-- ★1.71.15 用户：「图标调整的不对」——她的图标让她自己挑：
--   图标库里**右键**任意一枚 → 存进 cfg.mbIcon 并立刻贴上（重登不丢；亲自挑的永远优先于自动挑）。
function EVAL_HELP_MB_SETCUSTOM(path)
  if type(path) ~= "string" or path == "" then return false end
  c().mbIcon = path
  if minimapBtn and mbIconTex then mbApplyIcon(path) end
  return true
end

-- ★1.71.13 给按钮贴图标：从宏图标表按名字挑一枚「工具」图标（挑选逻辑 = 上面的纯函数，可注桩直测）。
--   ★挑不到就建旧的「金框 + 暗底 + EH」兜底样式 —— **不许留空白按钮**（接口缺席时入口不能消失）。
function EVAL_HELP_MB_SETICON()
  if not minimapBtn or not mbIconTex then return false end
  -- ★1.71.15 她在图标库里右键挑过的图标**优先**（亲自挑的 > 自动挑的）
  local cu = c().mbIcon
  if type(cu) == "string" and cu ~= "" then
    mbApplyIcon(cu)
    return true
  end
  local path = nil
  if type(GetNumMacroIcons) == "function" and type(GetMacroIconInfo) == "function" then
    local okn, n = pcall(GetNumMacroIcons)
    if okn and type(n) == "number" and n > 0 then
      path = EVAL_HELP_MB_PICKICON(n, GetMacroIconInfo)
    end
  end
  if path then
    mbApplyIcon(path)
    return true
  end
  if not mbRing then -- 兜底只建一次
    local ring = minimapBtn:CreateTexture(nil, "BACKGROUND")
    uiSolid(ring, 0.85, 0.70, 0.20, 1)
    ring:SetPoint("TOPLEFT", minimapBtn, "TOPLEFT", 0, 0)
    ring:SetPoint("BOTTOMRIGHT", minimapBtn, "BOTTOMRIGHT", 0, 0)
    local mt = uiText(minimapBtn, 11, 1, 0.85, 0.30)
    mt:SetPoint("CENTER", minimapBtn, "CENTER", 0, 0)
    mt:SetText("EH")
    mbRing, mbText = ring, mt
  end
  return false
end

-- ★1.71.2 测试钩子：小地图按钮的默认锚点与重叠判定（否则只能靠人眼看界面）。
--   ★必须物理放在上面那个 do 块**之后**——minimapBtn / mbAnchorDefault / mbOverlapsMinimap
--     都是 local，写在使用点之前会解析成全局 nil（DECL ORDER CHECK 当场抓出 3 条 FAIL）。
function EVAL_TEST_MB_DEFAULT_ANCHOR()
  if not minimapBtn then return nil end
  mbAnchorDefault(minimapBtn)
  local ok, point, _, relPoint, x, y = pcall(minimapBtn.GetPoint, minimapBtn, 1)
  if not ok then return nil end
  return { point = point, relPoint = relPoint, x = x, y = y }
end
function EVAL_TEST_MB_OVERLAPS() return mbOverlapsMinimap(minimapBtn) end
function EVAL_TEST_MB_BTN() return minimapBtn end
-- ★1.71.13 断言入口：按钮的**真实几何与贴图状态**（图标模式 / 兜底模式），读真控件不写死常量。
function EVAL_TEST_MB_VISUAL()
  local out = { w = nil, h = nil, icon = mbIconPath, hasFallback = (mbRing ~= nil) and true or false, ehText = nil }
  if minimapBtn then
    local okw, w = pcall(minimapBtn.GetWidth, minimapBtn)
    out.w = (okw and type(w) == "number") and w or nil
    local okh, h = pcall(minimapBtn.GetHeight, minimapBtn)
    out.h = (okh and type(h) == "number") and h or nil
  end
  if mbText then
    local okt, t = pcall(mbText.GetText, mbText)
    out.ehText = (okt and tostring(t or "")) or nil
  end
  return out
end
function EVAL_TEST_MB_ANCHOR_CURRENT()
  if not minimapBtn then return nil end
  local ok, point, _, relPoint, x, y = pcall(minimapBtn.GetPoint, minimapBtn, 1)
  if not ok then return nil end
  return { point = point, relPoint = relPoint, x = x, y = y }
end

-- ============ 方案快捷键绑定（1.71.16，用户：「方案 右键能否弹窗设置 绑定快捷键」→ 先验证后实装） ============
-- ★可行性（/eh go bind 实测）：SetBinding 接受插件自定义命令名、无需 Bindings.xml 登记（T1/T2 全过）；
--   ★但那只证明「命令名能存进绑定表」——「按下键真的触发」走 **CLICK 派发**（vanilla 经典招：
--   SetBinding(key, "CLICK <命名按钮>:LeftButton")，按下键 = 客户端替我们点那个隐藏按钮 → OnClick → EVAL_GO(i)）。
--   配套实弹探针 /eh go bind2：现场复核 CLICK 派发与裸命令名派发哪种真的触发（10 秒倒计时如实报告）。
-- ★持久化：绑定后 SaveBindings(GetCurrentBindingSet())——不存就随重登消失（实测当前 set = 1）。

-- 派发命令名（纯函数，测试直测）：方案 i 的按键 = 点隐藏命名按钮 EVAL_GO_KEY_i
function EVAL_BIND_CMD(i)
  return "CLICK EVAL_GO_KEY_" .. tostring(i) .. ":LeftButton"
end

-- 每个方案一个隐藏命名按钮（按下绑定的键 → 客户端点它 → 执行并激活该方案）
for i = 1, 12 do
  local b = CreateFrame("Button", "EVAL_GO_KEY_" .. i, UIParent)
  local pi = i
  b:SetScript("OnClick", function() EVAL_GO(pi) end)
end

-- 按键清单（纯函数：下拉内容 = 分类标题 + 键名；locked 是「分类标题行」的下标集合——DD 的不可选行语义）。
--   ★键名必须是 SetBinding 认的写法（F1 / BUTTON3 / MOUSEWHEELUP / SHIFT-2…，wiki KeyBinding 页核对过）。
function EVAL_BIND_KEYLIST()
  local cats = {
    { label = L("BIND_CAT_F"),      keys = { "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" } },
    { label = L("BIND_CAT_NUM"),    keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" } },
    { label = L("BIND_CAT_LETTER"), keys = { "Q", "E", "R", "T", "F", "G", "Z", "X", "C", "V", "B" } },
    { label = L("BIND_CAT_MOUSE"),  keys = { "BUTTON3", "BUTTON4", "BUTTON5", "MOUSEWHEELUP", "MOUSEWHEELDOWN" } },
    { label = L("BIND_CAT_MOD"),    keys = { "SHIFT-1", "SHIFT-2", "SHIFT-3", "SHIFT-4", "CTRL-1", "CTRL-2", "CTRL-3", "CTRL-4", "ALT-1", "ALT-2", "ALT-3", "ALT-4", "SHIFT-Q", "SHIFT-E", "SHIFT-R" } },
  }
  local rows, items, locked = {}, {}, {}
  for _, cat in ipairs(cats) do
    local hi = table.getn(items) + 1
    items[hi] = "|cffaaaaaa" .. cat.label .. "|r"
    locked[hi] = true
    rows[hi] = { header = true }
    for _, k in ipairs(cat.keys) do
      local i = table.getn(items) + 1
      items[i] = "  " .. k
      rows[i] = { key = k }
    end
  end
  return rows, items, locked
end

-- 下拉选中回调（命名导出 = 测试能直调，不依赖真的点开下拉）：标题行不选、键名行进状态
function EVAL_BIND_DD_PICK(rows, pi)
  local row = rows and rows[pi]
  if row and row.key then EVAL_BIND_PICK(row.key) end
end

-- 逻辑层（UI 与测试共用一份实现）：绑定 / 清除。★换键时把旧键解绑；绑定后立刻 SaveBindings 持久化。
function EVAL_BIND_DO(pidx, key)
  if type(key) ~= "string" or key == "" then return false, "nokey" end
  local w2 = warCfg()
  if not (w2.profiles and w2.profiles[pidx]) then return false, "noprof" end
  local ok, r = pcall(SetBinding, key, EVAL_BIND_CMD(pidx))
  if not (ok and r) then return false, "reject" end
  w2.bindKeys = w2.bindKeys or {}
  local old = w2.bindKeys[pidx]
  if type(old) == "string" and old ~= "" and old ~= key then pcall(SetBinding, old) end -- 换键：解掉旧键
  w2.bindKeys[pidx] = key
  if type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  return true, key
end

function EVAL_BIND_CLEAR(pidx)
  local w2 = warCfg()
  local old = w2.bindKeys and w2.bindKeys[pidx]
  if type(old) == "string" and old ~= "" then pcall(SetBinding, old) end
  if w2.bindKeys then w2.bindKeys[pidx] = nil end
  if type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  return true
end

-- ===== 绑定弹窗（美化版：金边深底 + 标题栏拖动 + 分类下拉 + 冲突/空闲提示） =====
local bindUI = { root = nil, pidx = nil, selKey = nil }

local function bindRefresh()
  local w2 = warCfg()
  local p = bindUI.pidx and w2.profiles and w2.profiles[bindUI.pidx]
  bindUI.title:SetText(L("BIND_TITLE") .. "：" .. (p and tostring(p.name) or "?"))
  local cur = w2.bindKeys and w2.bindKeys[bindUI.pidx]
  bindUI.curText:SetText(string.format(L("BIND_CUR"), (type(cur) == "string" and cur ~= "") and cur or L("BIND_NONE")))
  bindUI.keyText:SetText(bindUI.selKey or L("BIND_PICK"))
  -- 冲突提示：选中键已被占用时如实橙色警告（绑定后替换）；空闲 = 绿
  local info, ir, ig, ib = "", 0.65, 0.65, 0.65
  if bindUI.selKey then
    local okA, act = pcall(GetBindingAction, bindUI.selKey)
    act = (okA and type(act) == "string") and act or ""
    if act == "" or act == EVAL_BIND_CMD(bindUI.pidx) then
      info, ir, ig, ib = L("BIND_FREE"), 0.55, 0.85, 0.45
    else
      info, ir, ig, ib = string.format(L("BIND_CONFLICT"), act), 1.00, 0.65, 0.30
    end
  end
  bindUI.infoText:SetText(info)
  pcall(bindUI.infoText.SetTextColor, bindUI.infoText, ir, ig, ib)
end

function EVAL_BIND_PICK(key)
  bindUI.selKey = key
  bindRefresh()
end

function EVAL_BIND_BUILD()
  if bindUI.root then return end
  local W, H = 300, 190
  local root = CreateFrame("Frame", "EVAL_HELP_BIND", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 120)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetWidth(W - 4) titleBar:SetHeight(22)
  titleBar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(titleBar.SetFrameLevel, titleBar, 121)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  bindUI.title = title
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local curText = uiText(root, 10, 0.92, 0.88, 0.80)
  curText:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  bindUI.curText = curText

  -- 选择按键（下拉：分类标题 + 键名；locked 行不可点）
  local keyBtn = CreateFrame("Button", nil, root)
  keyBtn:SetWidth(W - 32) keyBtn:SetHeight(20)
  keyBtn:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -60)
  pcall(keyBtn.EnableMouse, keyBtn, true)
  pcall(keyBtn.RegisterForClicks, keyBtn, "LeftButtonUp")
  local kbBg = keyBtn:CreateTexture(nil, "BACKGROUND")
  uiSolid(kbBg, 0.16, 0.13, 0.08, 1)
  kbBg:SetPoint("TOPLEFT", keyBtn, "TOPLEFT", 0, 0)
  kbBg:SetPoint("BOTTOMRIGHT", keyBtn, "BOTTOMRIGHT", 0, 0)
  local keyText = uiText(keyBtn, 10, 0.95, 0.82, 0.35)
  keyText:SetPoint("CENTER", keyBtn, "CENTER", 0, 0)
  bindUI.keyBtn, bindUI.keyText = keyBtn, keyText
  keyBtn:SetScript("OnClick", function()
    local rows, items, locked = EVAL_BIND_KEYLIST()
    EVAL_DD_OPEN(keyBtn, items, function(pi) EVAL_BIND_DD_PICK(rows, pi) end, { locked = locked })
  end)

  local infoText = uiText(root, 9, 0.65, 0.65, 0.65)
  infoText:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -86)
  bindUI.infoText = infoText
  local hint = uiText(root, 8, 0.55, 0.55, 0.55)
  hint:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -104)
  hint:SetText(L("BIND_HINT"))

  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(80) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    return b
  end
  bindUI.doBtn = bBtn(20, L("BIND_DO"), function()
    if not bindUI.selKey then
      bindUI.infoText:SetText(L("BIND_NOKEY"))
      pcall(bindUI.infoText.SetTextColor, bindUI.infoText, 1.00, 0.65, 0.30)
      return
    end
    local ok2, err = EVAL_BIND_DO(bindUI.pidx, bindUI.selKey)
    local p = warCfg().profiles and warCfg().profiles[bindUI.pidx]
    if ok2 then
      say(string.format(L("BIND_DONE"), bindUI.selKey, tostring(p and p.name)))
      bindUI.selKey = nil
      bindRefresh()
    else
      say(string.format(L("BIND_FAIL"), tostring(err)))
    end
  end)
  bindUI.clearBtn = bBtn(110, L("BIND_CLEAR"), function()
    EVAL_BIND_CLEAR(bindUI.pidx)
    local p = warCfg().profiles and warCfg().profiles[bindUI.pidx]
    say(string.format(L("BIND_CLEARED"), tostring(p and p.name)))
    bindUI.selKey = nil
    bindRefresh()
  end)
  bBtn(200, L("BTN_CANCEL"), function()
    if type(EVAL_DD_HIDE) == "function" then pcall(EVAL_DD_HIDE) end
    root:Hide()
  end)

  root:SetScript("OnHide", function()
    if type(EVAL_DD_HIDE) == "function" then pcall(EVAL_DD_HIDE) end -- 下拉贴 UIParent，宿主关了要一起收
  end)
  root:Hide()
  bindUI.root = root
end

function EVAL_BIND_OPEN(pidx)
  EVAL_BIND_BUILD()
  local w2 = warCfg()
  if not (w2.profiles and w2.profiles[pidx]) then return false end
  bindUI.pidx = pidx
  bindUI.selKey = nil
  bindRefresh()
  bindUI.root:Show()
  return true
end

-- ★断言钩子：弹窗与逻辑层的真实状态（读真控件/真数据，不读常量）
function EVAL_TEST_BIND_UI()
  local out = { built = (bindUI.root ~= nil) and true or false, pidx = bindUI.pidx, selKey = bindUI.selKey,
    shown = false, title = nil, cur = nil, info = nil }
  if bindUI.root then
    local ok, v = pcall(bindUI.root.IsVisible, bindUI.root)
    out.shown = (ok and v) and true or false
  end
  if bindUI.title then
    local ok, t = pcall(bindUI.title.GetText, bindUI.title)
    out.title = ok and tostring(t or "") or nil
  end
  if bindUI.curText then
    local ok, t = pcall(bindUI.curText.GetText, bindUI.curText)
    out.cur = ok and tostring(t or "") or nil
  end
  if bindUI.infoText then
    local ok, t = pcall(bindUI.infoText.GetText, bindUI.infoText)
    out.info = ok and tostring(t or "") or nil
  end
  return out
end
function EVAL_TEST_BIND_DO_BTN() return bindUI.doBtn end
function EVAL_TEST_BIND_CLOSE() if bindUI.root then bindUI.root:Hide() end end


-- ============ 状态信息 UI（展示 Cat 式角色状态表 EVAL_HELP_STATE 的实时值） ============
-- /eh st 开关；标题栏拖动（位置记忆+越界回归）；每 0.15s 刷新一次 EVAL_HELP_UPDATE_STATE()。
-- 内容 = 状态模块全部字段：玩家数值/战斗计时/姿态/修饰键/普攻 + 目标可攻击/可流血/精英Boss 等。

local stui = { root = nil, body = nil }
local stLastTick = 0
local ST_TICK = 0.15

local function stCfg()
  local cc = c()
  if not cc.st then cc.st = { enabled = false, x = 330, y = -180 } end
  return cc.st
end

local function stYesNo(v)
  return v and "|cff00ff00是|r" or "|cffff5040否|r"
end

function EVAL_HELP_ST_BUILD()
  local sc = stCfg()
  if stui.root then
    stui.root:Hide()
    pcall(stui.root.SetScript, stui.root, "OnUpdate", nil)
  end
  local W = 250
  local pad = 8
  local titleBarH = 16
  local root = CreateFrame("Frame", "EVAL_HELP_STUI", UIParent)
  pcall(root.SetFrameStrata, root, "MEDIUM")
  pcall(root.SetMovable, root, true)
  -- 本体不吃鼠标（UnrealQuest：容器 mouse-disabled，不吞世界点击）；拖动走标题栏 Button
  pcall(root.EnableMouse, root, false)

  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.92)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end

  -- 标题栏拖动柄（Button 配方）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(titleBarH)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then
    pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10)
  end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText("状态信息")
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function()
    pcall(root.StopMovingOrSizing, root)
    local ok, cx, cy = pcall(root.GetCenter, root)
    if ok and cx then
      local okw, w2 = pcall(UIParent.GetWidth, UIParent)
      local okh, h2 = pcall(UIParent.GetHeight, UIParent)
      if okw and okh and w2 and h2 then
        local oke, es = pcall(root.GetEffectiveScale, root)
        local k = (oke and type(es) == "number" and es > 0) and es or 1
        sc.x = (cx - w2 / 2) / k
        sc.y = (cy - h2 / 2) / k
      end
    end
  end)

  -- 正文：一个多行 FontString，逐行展示状态变量
  local body = uiText(root, 10, 0.85, 0.85, 0.85)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -(titleBarH + pad))
  pcall(body.SetWidth, body, W - pad * 2)
  pcall(body.SetJustifyH, body, "LEFT")

  root:SetWidth(W)
  root:SetHeight(titleBarH + pad * 2 + 15 * 14)
  root:ClearAllPoints()
  root:SetPoint("CENTER", UIParent, "CENTER", sc.x or 330, sc.y or -180)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 330, -180)
    sc.x, sc.y = 330, -180
  end

  stui.root, stui.body = root, body
  root:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - stLastTick < ST_TICK then return end
    stLastTick = now
    EVAL_HELP_ST_TICK()
  end)
end

-- 每次心跳：刷新状态表，逐行重排正文（Cat 的 CatUI-Melee 状态行同款展示）
function EVAL_HELP_ST_TICK()
  if not stui.root or not stui.root:IsVisible() then return end
  EVAL_HELP_UPDATE_STATE()
  local lines = {}
  table.insert(lines, string.format("%s  Lv%d %s%s",
    st.playerName or "?", st.level or 0, st.classLoc or "",
    st.raceLoc and (" · " .. st.raceLoc) or ""))
  table.insert(lines, string.format("血 %d/%d (%.0f%%)", st.hp, st.hpMax, st.hpPct))
  table.insert(lines, string.format("%s %d/%d (%.0f%%)%s", powerLabel(), st.power, st.powerMax, st.powerPct,
    (st.class == "ROGUE" or st.class == "DRUID") and string.format(" · 连击 %d", st.combo or 0) or ""))
  table.insert(lines, string.format("%s%s · %s",
    st.inCombat and "|cffff5040战斗中|r" or "|cff80ff80非战斗|r",
    st.inCombat and string.format(" %.1fs", st.combatTime) or "",
    st.form or "无姿态"))
  table.insert(lines, string.format("Alt:%s Shift:%s Ctrl:%s 普攻:%s",
    stYesNo(st.alt), stYesNo(st.shift), stYesNo(st.ctrl), stYesNo(st.autoAttack)))
  if st.atkSpd then -- 1.55.0 挥击计时行：攻速 + 距下次攻击（无锚点数据=—）
    local rem = EVAL_SWING_REMAIN and EVAL_SWING_REMAIN()
    table.insert(lines, string.format("攻速 %.1fs · 距下次攻击 %s%s", st.atkSpd,
      rem and string.format("%.1fs", rem) or "—",
      st.atkSpdOff and string.format("（副手 %.1fs）", st.atkSpdOff) or ""))
  end
  if st.castName then -- 1.38.0 施法中实时显示（含读条剩余秒数）
    table.insert(lines, string.format("施法中: %s%s", tostring(st.castName),
      st.castUntil and string.format(" 剩%.1fs", math.max(0, st.castUntil - GetTime())) or ""))
  end
  if st.hasTarget then
    table.insert(lines, string.format("目标: %s  Lv%d%s%s",
      tostring(st.targetName), st.tLevel or 0,
      st.isBoss and " |cffff4040Boss|r" or "",
      (not st.isBoss and st.isElite) and " |cffff9040精英|r" or ""))
    table.insert(lines, string.format("目标血 %.0f%% · 距离:%s · 可攻击:%s · 可流血:%s · 关系:%s",
      st.tHpPct, st.tRange or "—", stYesNo(st.canAttack), stYesNo(st.canBleed),
      st.tFriendly and "友善" or (st.tNeutral and "中立" or (st.tHostile and "敌对" or "?"))))
    table.insert(lines, string.format("类型:%s 分级:%s%s · 职业:%s",
      st.tCreatureType or "?", st.tClassification or "?",
      st.tInCombat and " · 目标战斗中" or "",
      tostring(st.tClassName or st.tClass or "?")))
  else
    table.insert(lines, "目标: |cff808080无|r")
  end
  -- 最近释放：技能 + 触发原因 + 条件逐项判定明细（规则引擎 trace）
  if st.castLog and table.getn(st.castLog) > 0 then
    table.insert(lines, "|cffc8a04a— 最近释放 —|r")
    local now = GetTime()
    for i = 1, 3 do
      local e = st.castLog[i]
      if not e then break end
      local ago = now - (e.t or now)
      table.insert(lines, string.format("|cff909090%.0fs前|r |cffffd050%s|r%s%s",
        ago, tostring(e.skill),
        (e.target and e.target ~= "") and ("→" .. e.target) or "",
        (e.why and e.why ~= "") and (" |cff909090← " .. tostring(e.why) .. "|r") or ""))
      if e.trace and e.trace ~= "" then
        table.insert(lines, "  |cff70b070" .. e.trace .. "|r")
      end
    end
  end
  stui.body:SetText(table.concat(lines, "\n"))
end

function EVAL_HELP_ST_TOGGLE()
  local sc = stCfg()
  if stui.root and stui.root:IsVisible() then
    stui.root:Hide()
    sc.enabled = false
    say("状态信息UI: |cffff0000关|r")
  else
    EVAL_HELP_ST_BUILD()
    if stui.root then stui.root:Show() end
    sc.enabled = true
    say("状态信息UI: |cff00ff00开|r（Cat 状态变量实时总览）")
  end
end

-- ============ 技能编辑窗（技能循环选择 + 独立条件属性行 + & / | 连接符） ============
-- 编辑模型：ed.conds = 线性条件列表 { {conn=nil|"&"|"|", cd=条件}, ... }；
-- conn 语义：& 并入当前组、| 新开一组 → 与引擎 groups（组内 & 、组间 | ）一一对应。
-- 本客户端无下拉控件：技能/条件类型/比较符/技能名全部用「点击循环」按钮实现。

local SE_TYPES = {
  { id = "power",      name = "怒气/能量",   kind = "num",   n = 30 },
  { id = "tHpPct",     name = "目标血%",     kind = "num",   n = 10 },
  { id = "hpPct",      name = "自身血%",     kind = "num",   n = 50 },
  { id = "powerPct",   name = "能量%",       kind = "num",   n = 10 },
  { id = "combatTime", name = "进战秒数",    kind = "num",   n = 3 },
  { id = "combo",      name = "连击点数",    kind = "num",   n = 1 }, -- 1.54.4 初始值 1（域 1-5）
  { id = "swingLeft",  name = "距下次攻击",  kind = "num",   n = 0.1 }, -- 1.57.0 挥击计时（秒）；1.58.0 时间型初始 0.1
  { id = "combat",     name = "战斗状态",    kind = "bool" },
  { id = "hasTarget",  name = "目标存在",    kind = "bool" },
  { id = "canAttack",  name = "目标可攻击",  kind = "bool" },
  { id = "canBleed",   name = "目标可流血",  kind = "bool" },
  { id = "tFriendly",  name = "目标友善",    kind = "bool" },
  { id = "tHostile",   name = "目标敌对",    kind = "bool" },
  { id = "tNeutral",   name = "目标中立",    kind = "bool" },
  { id = "isElite",    name = "目标精英",    kind = "bool" },
  { id = "isBoss",     name = "目标Boss",    kind = "bool" },
  { id = "tInCombat",  name = "目标战斗中",  kind = "bool" },
  { id = "autoAttack", name = "普攻已开",    kind = "bool" },
  { id = "autoShot",   name = "自动射击已开", kind = "bool" }, -- 1.51.0 猎人
  { id = "wandShoot",  name = "魔杖射击已开", kind = "bool" }, -- 1.51.0 法系
  { id = "alt",        name = "Alt按住",     kind = "bool" },
  { id = "shift",      name = "Shift按住",   kind = "bool" },
  { id = "ctrl",       name = "Ctrl按住",    kind = "bool" },
  { id = "form",       name = "当前姿态",    kind = "form" },
  { id = "hasBuff",    name = "自身buff检查",   kind = "skill", s = "" }, -- 1.54.0 合并（是/否切换）；1.70.0 去战士化：默认空需用户选（旧默认 战斗怒吼）
  { id = "pDebuff",    name = "自身debuff检查", kind = "skill", s = "" },          -- 1.54.0 新增
  { id = "hasDebuff",  name = "目标debuff检查", kind = "skill", s = "" },      -- 1.54.0 合并（是/否切换）；1.70.0 去战士化：默认空（旧默认 断筋）
  { id = "tBuff",      name = "目标buff检查",   kind = "skill", s = "" },          -- 1.54.0 新增
  { id = "ready",      name = "冷却就绪",    kind = "flag" },
  { id = "usable",     name = "技能可用",    kind = "flag" },
  { id = "notQueued",  name = "未排队",      kind = "flag" },
  { id = "target",     name = "选取目标",    kind = "target", s = "nearEnemy", hidden = true }, -- 1.32.0 提为技能级（技能下拉「目标选取」），新增条件下拉不再提供；存量条件仍渲染/求值
  { id = "tClass",     name = "目标职业",    kind = "class" },
  -- ★1.70.28 新增「目标类型」（野兽/元素/亡灵…）：用户要求「条件类型 添加: 目标类型: 野兽,元素 这种,
  --   支持下拉 支持 是/否」。kind="creature"：多选下拉（或关系，同 tClass）+ 是/否。
  --   取值来自 UnitCreatureType("target")，返回**本地化名**，故匹配同时比对本地化名与英文 token。
  { id = "tCreature",  name = "目标类型",    kind = "creature" },
  { id = "immune",    name = "目标免疫技能", kind = "skill", s = "" }, -- 1.36.1 免疫学习表判定；1.70.0 去战士化：默认空（旧默认 撕裂）
  { id = "inRange",   name = "施法范围内",  kind = "skill", s = "" }, -- 1.37.0 IsActionInRange；1.70.0 去战士化：默认空（旧默认 冲锋）
  { id = "casting",   name = "施法中",      kind = "skill", s = "" }, -- 1.38.0 SPELLCAST_* 事件驱动 -- 1.41.0 默认空=任意施法
  { id = "castEl",    name = "施法时间", kind = "num", n = 0.1 }, -- 1.58.0 时间型：初始 0.1（步进 0.1 区间 0-10）；1.71.2 改名（原「自身读条进行」）
  { id = "castLeft",  name = "施法剩余时间", kind = "num", n = 0.1 }, -- 1.71.2 改名（原「自身读条剩余」）
  { id = "tCasting",  name = "目标施法中",  kind = "skill", s = "" }, -- 1.40.0 空参数=任意施法
  { id = "tCastEl",   name = "目标施法时间", kind = "num", n = 0.1 }, -- 1.58.0 时间型：初始 0.1；1.71.2 改名（原「读条已进行」）
  { id = "tCastLeft", name = "目标施法剩余时间", kind = "num", n = 0.1 }, -- 1.71.2 改名（原「读条剩余」）
  -- ★1.70.47 队伍/团队条件（用户要求：一键扫描队伍 → 血量/蓝量/buff/debuff 检测）。
  --   ★★设计定案（用户拍板）：条件类型里**直接列出 队伍/团队 两套**（不搞范围下拉），
  --     并且条件**自己负责在队里挑人**——
  --     「队伍血量<50」= 队里**血最少的那个**是否低于 50%（不是只看某个人）
  --     「队伍debuff(魔法)」= 队里**是否有人中魔法** → 挑出那个人并切成当前目标 → 后面技能就解他
  --   扫描范围写进 **cd.name**（"队伍"/"团队"）；kind=num → 比较符+数值；
  --   kind=skill → 光环名下拉 + 是/否 + 层数；debuff 型再多个「类型」下拉（row.dtBtn）。
  { id = "teamHp",        name = "队友血量%",  kind = "num",   n = 60, name2 = "队伍" },
  { id = "teamMana",      name = "队友蓝量%",  kind = "num",   n = 20, name2 = "队伍" },
  { id = "teamBuff",      name = "队友缺buff", kind = "skill", s = "",  name2 = "队伍" },
  { id = "teamDebuff",    name = "队友debuff", kind = "skill", s = "",  name2 = "队伍" },
  { id = "teamRaidHp",    name = "团员血量%",  kind = "num",   n = 60, name2 = "团队", base = "teamHp" },
  { id = "teamRaidMana",  name = "团员蓝量%",  kind = "num",   n = 20, name2 = "团队", base = "teamMana" },
  { id = "teamRaidBuff",  name = "团员缺buff", kind = "skill", s = "",  name2 = "团队", base = "teamBuff" },
  { id = "teamRaidDebuff",name = "团员debuff", kind = "skill", s = "",  name2 = "团队", base = "teamDebuff" },
  -- ★★★1.71.3 候选者条件（用户要求：**原 8 项一字不动**，另外独立加这 4 项）——
  --   语义 = 「循环检索到的那个成员」（含自己；范围由「选取目标:队伍成员/团队成员」那一行决定）。
  --   ★只在**选取器行**的下拉里出现（见 typeBtn 的过滤）；配在别的行上求值时如实失败、不假装通过。
  { id = "candHp",     name = "候选者血%",   kind = "num",   n = 60 },
  { id = "candPower",  name = "候选者能量%", kind = "num",   n = 20 },
  { id = "candBuff",   name = "候选者缺buff",kind = "skill", s = "" },
  { id = "candDebuff", name = "候选者debuff",kind = "skill", s = "" },
}
local SE_BY_K = {}
for i, td in ipairs(SE_TYPES) do SE_BY_K[td.id] = i end
SE_BY_K["formNot"] = SE_BY_K["form"]
SE_BY_K["noBuff"] = SE_BY_K["hasBuff"] -- 1.54.0 存量数据归并显示
SE_BY_K["noDebuff"] = SE_BY_K["hasDebuff"]

-- ★1.70.47 队伍/团队类型解析：同一条引擎条件 k（teamHp/teamMana/teamBuff/teamDebuff）
--   在条件类型下拉里占两行——「队伍」与「团队」（分辨靠 cd.name）。
--   所以 cd.k 单独查 SE_BY_K 只能拿到第一行，必须带 name 一起查。
--   ★td.base = 引擎用的 k（团队行才需要，nil 表示 id 本身就是 k）；td.name2 = 扫描范围。
local function seTypeIndexOf(k, name)
  local fallback = nil
  for i, td in ipairs(SE_TYPES) do
    local bk = td.base or td.id
    if bk == k then
      if td.name2 == nil or td.name2 == name then return i end
      if not fallback then fallback = i end
    end
  end
  return fallback or SE_BY_K[k] or 1
end
local SE_OPS = { ">", ">=", "<", "<=", "==", "~=" }

-- ★目标类型表（1.70.28）：id 稳定（存进条件里），loc=中文显示名，tok=英文 token。
--   本客户端 UnitCreatureType 返回**本地化字符串**，故求值时两种写法都要认（enUS 客户端回英文）。
--   最后一项 "other" 用于兜住未列出的返回值——**绝不静默丢弃**，否则用户会遇到「明明是这个类型却不匹配」。
local CREATURE_TYPES = {
  { id = "beast",        loc = "野兽",   tok = "Beast" },
  { id = "dragonkin",    loc = "龙类",   tok = "Dragonkin" },
  { id = "demon",        loc = "恶魔",   tok = "Demon" },
  { id = "elemental",    loc = "元素",   tok = "Elemental" },
  { id = "giant",        loc = "巨人",   tok = "Giant" },
  { id = "undead",       loc = "亡灵",   tok = "Undead" },
  { id = "humanoid",     loc = "人型",   tok = "Humanoid" },
  { id = "critter",      loc = "小动物", tok = "Critter" },
  { id = "mechanical",   loc = "机械",   tok = "Mechanical" },
  { id = "notpecified",  loc = "未指定", tok = "Not specified" },
  { id = "totem",        loc = "图腾",   tok = "Totem" },
  { id = "other",        loc = "其他",   tok = "Other" },
}
local CREATURE_BY_ID = {}
for _, c in ipairs(CREATURE_TYPES) do CREATURE_BY_ID[c.id] = c end

-- 条件类型分组（1.32.5 下拉美化）：金色组标题行不可选；SE_TYPES 本体顺序不动，仅展示层分组
local SE_TYPE_GROUPS = {
  { label = "CTG_1", ids = { "power", "hpPct", "powerPct", "combatTime", "combo", "swingLeft", "combat", "autoAttack", "autoShot", "wandShoot", "alt", "shift", "ctrl", "form" } }, -- ★1.71.2（第十五轮）施法族（施法中/施法时间/施法剩余时间）已统一移入 CTG_4
  { label = "CTG_2", ids = { "tHpPct", "hasTarget", "canAttack", "canBleed", "tFriendly", "tHostile", "tNeutral", "isElite", "isBoss", "tInCombat", "tClass", "tCreature", "immune" } }, -- ★1.71.2（第十五轮）目标施法族（目标施法中/目标施法时间/目标施法剩余时间）已统一移入 CTG_4
  { label = "CTG_3", ids = { "hasBuff", "pDebuff", "hasDebuff", "tBuff" } }, -- 1.54.0 光环检查四型
  -- ★1.70.47 队伍/团队条件单列一组：**队伍与团队各列一份**（用户要求：
  --   「条件类型: 队伍debuff / 队伍buff / 团队debuff / 团队buff」——直接作为可选类型出现，不用范围下拉）
  { label = "CTG_5", ids = { "teamHp", "teamMana", "teamBuff", "teamDebuff", "teamRaidHp", "teamRaidMana", "teamRaidBuff", "teamRaidDebuff" } },
  -- ★1.71.3 候选者条件组：**只在成员选取器那一行**的下拉里显示（见 typeBtn 的过滤），普通行不出现
  { label = "CTG_6", ids = { "candHp", "candPower", "candBuff", "candDebuff" } },
  -- ★★★1.71.2（第十五轮）施法族归并（用户要求）：「自身施法相关 + 目标施法相关」全部并进本组。
  --   顺序 = 用户选定的 A 方案：**技能本身的状态 → 我的施法 → 目标的施法**（两段名字互为镜像：
  --   施法中/施法时间/施法剩余时间 ↔ 目标施法中/目标施法时间/目标施法剩余时间）。
  --   ★顺序本身就是需求，断言必须**钉住顺序**而不只钉成员（只钉成员时打乱排序照样全绿）。
  --   ★是「移」而不是「复制」：菜单里出现两条同名（例如两个「施法中」）用户根本没法分辨 →
  --     断言同时钉「本组必须有」与「原组必须没有」两条，只钉前者时复制也照样通过。
  { label = "CTG_4", ids = { "ready", "usable", "notQueued", "inRange", "casting", "castEl", "castLeft", "tCasting", "tCastEl", "tCastLeft" } },
}

local seUI = { root = nil, ed = nil, rows = {} }

local function seDefaultCond(ti)
  local td = SE_TYPES[ti]
  -- ★1.70.47 队伍/团队行：k 用引擎认的规范 id（td.base），扫描范围存 cd.name（td.name2）
  local ck = td.base or td.id
  if td.kind == "num" then
    if td.name2 then return { k = ck, op = "<", n = td.n, name = td.name2 } end
    -- ★候选者血%/能量%：默认「<」= 取最小（最该治/最缺蓝的那个），与新规则配套
    if ck == "candHp" or ck == "candPower" then return { k = ck, op = "<", n = td.n } end
    return { k = ck, op = ">", n = td.n }
  elseif td.kind == "bool" then return { k = td.id, v = true }
  elseif td.kind == "form" then return { k = "form", n = 1 }
  elseif td.kind == "skill" then
    local cd0 = { k = td.id, s = td.s }
    if td.id == "hasBuff" or td.id == "hasDebuff" or td.id == "tBuff" or td.id == "pDebuff" then cd0.v = true end -- 1.54.0 光环检查型默认「是」
    -- ★1.70.47 队友/团员光环型：写入扫描范围（cd.name）。
    --   「缺buff」默认取**无/缺**方向（名字就叫缺buff：任一队友缺它 → 该补）；
    --   「debuff」默认取**有**方向（「队友有魔法 → 解魔法」的正向语义）。
    if td.name2 then
      cd0.k = ck
      cd0.name = td.name2
      cd0.v = (ck ~= "teamBuff")
    end
    -- ★候选者光环型：缺buff 默认「缺」（v=false），debuff 默认「有」（与队友那套同一语义）
    if td.id == "candBuff" then cd0.v = false end
    if td.id == "candDebuff" then cd0.v = true end
    return cd0
  elseif td.kind == "target" then return { k = td.id, s = td.s }
  elseif td.kind == "class" then return { k = td.id, cs = {} } -- 1.70.0 去战士化：旧默认预选 WARRIOR（非战士职业新建即错）
  elseif td.kind == "creature" then return { k = td.id, cs = {}, v = true } -- 1.70.28 目标类型：默认「是」+ 空选择（空=永不满足，需用户点选）
  else return { k = td.id } end
end

-- ★★★1.71.3 条件类型的**悬停说明**（用户要求：「支持规则的条件类型」分别加 tooltip，并美化文案）。
--   ★只给**参与「挑谁」规则**的类型提示：4 个候选者类型 + 兼容写法（自身血%/能量%、目标血%）
--     + 老数值型（队伍/团员 血量·蓝量）；其它类型（技能就绪、姿态、按键…）**不给提示**——
--     ★判据：提示要报在有用的地方，每个条目都挂一段字等于没有提示。
local SE_TIP_RULE_KINDS = {
  candHp = true, candPower = true, candBuff = true, candDebuff = true,
  hpPct = true, powerPct = true, power = true, tHpPct = true,
  teamHp = true, teamMana = true, teamRaidHp = true, teamRaidMana = true,
}
local SE_TIP_SEM = {
  candHp = "SE_TIP_CAND_HP", candPower = "SE_TIP_CAND_POWER",
  candBuff = "SE_TIP_CAND_BUFF", candDebuff = "SE_TIP_CAND_DEBUFF",
}
-- ★★★1.71.3 「尚未在游戏里实测确认」的条件类型（用户要求：撤掉名字前面的「!」文字前缀，
--   改成**下拉里右侧一枚黄感叹号** + 悬停说明「待测试」）。
--   ★为什么要撤掉文字前缀：那个「!」会**跟着条件名到处跑**（条件行 / 菜单 / 日志里都是「!队友血量%」），
--     看着像乱码；而标记只需在**挑选的那一刻**提示一次。
--   ★这张表是「待测试」的**单一真值**：下拉的标记与悬停说明都从它取，不另写第二份名单。
--   ★★两枚标记不许混用：**黄**=待测试（本表）、**白**=不可用（cancelCastOf 那一族）。
local SE_TODO_KINDS = {
  teamHp = true, teamMana = true, teamBuff = true, teamDebuff = true,
  teamRaidHp = true, teamRaidMana = true, teamRaidBuff = true, teamRaidDebuff = true,
  candHp = true, candPower = true, candBuff = true, candDebuff = true,
}
-- 返回 tooltip 行表（逐行 AddLine）或 nil
local function seTypeTip(id)
  if id == nil then return nil end
  local isTodo = SE_TODO_KINDS[id] and true or false
  if not SE_TIP_RULE_KINDS[id] and not isTodo then return nil end
  local lines = { "|cffffd100" .. L("CT_" .. string.upper(id)) .. "|r" }
  if SE_TIP_SEM[id] then table.insert(lines, L(SE_TIP_SEM[id])) end
  if SE_TIP_RULE_KINDS[id] then table.insert(lines, "|cff9fe0ff" .. L("SE_TIP_RULE") .. "|r") end
  if SE_TIP_SEM[id] then table.insert(lines, "|cffa0a0a0" .. L("SE_TIP_CAND_ONLY") .. "|r") end
  if isTodo then
    -- ★文案复用「启用此技能」右侧那两枚标记的键（同一含义只有一套说法，不另写一份）
    table.insert(lines, "|cffffd100" .. L("SE_MARK_TEST_T") .. "|r")
    table.insert(lines, "|cffa0a0a0" .. L("SE_MARK_TEST_D") .. "|r")
  end
  return lines
end

-- groups → 线性编辑列表（复制条件，避免保存前污染已存数据）
local function seGroupsToLinear(groups)
  local list = {}
  for gi, g in ipairs(groups or {}) do
    for ci, cd in ipairs(g) do
      local conn
      if gi > 1 and ci == 1 then conn = "|"
      elseif ci > 1 then conn = "&" end
      local cp = {}
      for k, v in pairs(cd) do
        if type(v) == "table" then -- cs 等表字段拷一层，避免编辑期污染已存数据
          local c2 = {}
          for k2, v2 in pairs(v) do c2[k2] = v2 end
          cp[k] = c2
        else
          cp[k] = v
        end
      end
      -- 1.54.0 存量归一：noBuff/noDebuff → hasBuff/hasDebuff + v=false（编辑保存后即新格式）
      if cp.k == "noBuff" then cp.k = "hasBuff" cp.v = false
      elseif cp.k == "noDebuff" then cp.k = "hasDebuff" cp.v = false end
      table.insert(list, { conn = conn, cd = cp })
    end
  end
  return list
end

-- 线性列表 → groups：| 新开组，& 并入当前组
local function seLinearToGroups(list)
  local groups, cur = {}, nil
  for _, it in ipairs(list or {}) do
    if it.conn == "|" or not cur then
      cur = {}
      table.insert(groups, cur)
    end
    if it.cd then table.insert(cur, it.cd) end
  end
  return groups
end

local function seBtn(parent, x, y, w, h, label, fn)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local bb = b:CreateTexture(nil, "BACKGROUND")
  uiSolid(bb, 0.16, 0.13, 0.08, 1)
  bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local bt = uiText(b, 9, 0.92, 0.88, 0.80)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText(label)
  b:SetScript("OnClick", fn)
  return { btn = b, bg = bb, text = bt }
end

-- ===== 全局模拟下拉列表面板（1.19.0 由 SE 专用泛化：任意窗口可调用） =====
-- EVAL_DD_OPEN(锚点按钮, 选项表, 回调)；多列 12 行/列，贴屏底自动上翻；EVAL_DD_HIDE() 收起。
local DD_COLS = 12
local DD_MAX_ROWS = 96 -- ★行池上限（原硬编码 48；条件类型菜单需 54 行）
-- ★★★ 1.71.2（第十三轮）行池上限。原为硬编码 48，而**条件类型菜单需要 54 行**（五组 49 项 + 5 个组标题）
--   → 最后一组「冷却就绪/技能可用/未排队/施法范围内/施法中」**整组被静默丢掉**，
--   而且面板已按 5 列宽度布局 → 右侧留下一条空列（用户截图两个症状都对得上）。
--   ★1.71.2（第十五轮）施法族（自身 3 项 + 目标 3 项）已按用户要求统一并入 CTG_4「技能状态」组 → 该组现为 10 项；
--     全表总行数**仍然不变**（49 项 + 5 个组标题 = 54），行池上限的判断与结论都不受影响。
local SEARCH_H = 20 -- 1.70.29 搜索框占用的额外高度（0=不显示搜索框时的高度基准不变）
-- ★1.71.2 搜索框「停放坐标」：放在屏幕左上角外侧。
--   为什么不用 Hide()：本客户端 EditBox 用 Hide() 之后**它的文字/底条仍会被绘出**
--   （用户截图：搜索框消失后，所有弹窗上部留着一条看不见的黑块）→ 改用「挪出可视区」。
--   比 0.0 透明度更可靠（透明度是 alpha 混合，残留的黑色仍可能可见）。
local DD_SEARCH_PARK = -4000
local ddUI = {}

-- ★1.71.2 搜索框构建单独成函数（原来内联在 DD_BUILD 里）：
--   理由一：本客户端 EditBox 的「层」设置必须是可断言的——内联时它只在 DD_BUILD 里跑一次，
--     而 DD_BUILD 由「第一次打开下拉」触发，测试根本无法在受控时机执行它
--     （本项目 1.70.46 教训：只测解析函数、不测真实路径 = 等于没测）。
--   理由二：用户截图的「所有弹窗上部一条看不见的黑块」就是这里的层问题导致的，
--     必须有一条断言真的钉住 SetDrawLayer/SetFrameLevel 被调用过。
local function DD_MAKE_SEARCH(dd)
-- ★1.70.29 可选搜索框（opts.search）：光环/技能名单很长，用户要能输入关键字过滤，
--   并且在「列表里没有我要的名字」时可以直接提交自己输入的名称。
--   放在面板顶部，行区整体下移（高度由 EVAL_DD_OPEN 按 SEARCH_H 计入）。
local sb = CreateFrame("EditBox", nil, dd)
sb:SetWidth(160) sb:SetHeight(16)
sb:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -3)
sb:SetAutoFocus(false)
pcall(sb.EnableMouse, sb, true)
-- ★★1.71.2 第二轮用户实测纠正：**不要**把 EditBox 压到 BACKGROUND！
--   第一版这么做，结果输入框自己在面板里**彻底看不见了**（用户截图：条件行下方那块空白
--   其实正是输入框的位置，只是被面板背板盖住了）。
--   根因：压层的对象是「EditBox + 它的 FontString」，而面板的**不透明背板**也在 BACKGROUND——
--   FrameLevel 只决定**同一层内**的先后，压到同一层就会被背板整个盖住。
--   ★正解：EditBox 保持在正常层（可见），**靠「不用时挪出可视区」来消除干扰**（见 DD_SEARCH_PARK），
--     不需要也不应该动它的层。**可见的东西不压层，不可见的东西不靠层隐藏**——这是本轮的两条判据。
-- 本客户端 EditBox 默认文字居中偏右，必须显式压左并清内缩（1.70.3 实测）
pcall(sb.SetJustifyH, sb, "LEFT")
pcall(sb.SetJustifyV, sb, "MIDDLE")
pcall(sb.SetTextInsets, sb, 3, 0, 0, 0)
for _, f in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
  if pcall(sb.SetFontObject, sb, f) then break end
end
local sbBg = dd:CreateTexture(nil, "BACKGROUND")
uiSolid(sbBg, 0.10, 0.09, 0.06, 1)
-- (定位在 EVAL_DD_OPEN 里按面板宽度重设，这里只给初值)
ddUI.searchBg = sbBg
ddUI.search = sb
ddUI.searchText = ""
-- 1.71.2 初始即停放（不能用 Hide，见 DD_SEARCH_PARK 说明）
sb:ClearAllPoints()
sb:SetPoint("TOPLEFT", dd, "TOPLEFT", DD_SEARCH_PARK, 0)
sbBg:ClearAllPoints()
sbBg:SetPoint("TOPLEFT", dd, "TOPLEFT", DD_SEARCH_PARK, 0)
sb:SetScript("OnTextChanged", function()
  -- 输入即过滤（无服务器写动作，无需限频；但只在面板开启时生效）
  local t = ""
  pcall(function() t = sb:GetText() or "" end)
  ddUI.searchText = t
  if ddUI.refilter then pcall(ddUI.refilter) end
end)
sb:SetScript("OnEscapePressed", function() EVAL_DD_HIDE() end)
end

local function DD_BUILD()
  if ddUI.root then return end
  local dd = CreateFrame("Frame", "EVAL_HELP_DD", UIParent)
  pcall(dd.SetFrameStrata, dd, "DIALOG")
  pcall(dd.SetFrameLevel, dd, 250)
  pcall(dd.EnableMouse, dd, true)
  local bg = dd:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.98)
  bg:SetPoint("TOPLEFT", dd, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", 0, 0)
  -- ★1.71.2 关窗后「所有弹窗上部一条看不见的黑块」的根因就在这个搜索框：
  --   本客户的 EditBox 文字画在**高于 BACKGROUND 的层**（且会在自己背后画一条不透明底条），
  --   ddUI.searchBg（BACKGROUND）根本盖不住它。于是 EnableMouse(false) 隐藏后，
  --   面板四边的 1px 金线还在、中间是**空的**，那条黑底条就从空心里透出来（只有顶部一条带）。
  --   修法两层：① 面板补一块**不透明**背板挡住它；② 隐藏时把它挪到屏幕外（见 DD_SEARCH_PARK）。
  pcall(bg.SetDrawLayer, bg, "BACKGROUND")
  local solid = dd:CreateTexture(nil, "BACKGROUND")
  uiSolid(solid, 0.06, 0.05, 0.04, 1)
  solid:SetPoint("TOPLEFT", dd, "TOPLEFT", 1, -1)
  solid:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -1, 1)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = dd:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", dd, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", dd, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = dd:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, dd, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, dd, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  DD_MAKE_SEARCH(dd) -- ★1.71.2 搜索框构建（层设置/停放判定都在这一个函数里，便于断言）
  ddUI.rows = {}
  for i = 1, DD_MAX_ROWS do -- 1.27.0 加倍；1.71.2 再抬（条件类型菜单已需 54 行）
    local rb = CreateFrame("Button", nil, dd)
    rb:SetWidth(104) rb:SetHeight(14)
    pcall(rb.EnableMouse, rb, true)
    pcall(rb.RegisterForClicks, rb, "LeftButtonUp")
    local rbg = rb:CreateTexture(nil, "BACKGROUND")
    uiSolid(rbg, 0.10, 0.09, 0.06, 1)
    rbg:SetPoint("TOPLEFT", rb, "TOPLEFT", 0, 0)
    rbg:SetPoint("BOTTOMRIGHT", rb, "BOTTOMRIGHT", 0, 0)
    local rt = uiText(rb, 9, 0.85, 0.85, 0.85)
    rt:SetPoint("LEFT", rb, "LEFT", 4, 0)
    local ri = rb:CreateTexture(nil, "ARTWORK") -- 1.32.4 可选图标列（opts.icons）
    ri:SetWidth(12) ri:SetHeight(12)
    ri:SetPoint("LEFT", rb, "LEFT", 2, 0)
    ri:Hide()
    -- ★1.71.3 可选「异常标记」列（opts.warns[i] = 图标路径，opts.warnTip = 悬停说明）。
    --   用户要求：把「取消施法」这类**当前无法真正生效**的动作在行右端标个问号，悬停给出原因。
    --   ★标记与提示**每次重绘都要重设**（清空分支见渲染循环）：行池是复用的，
    --     不清就会把上一个菜单的标记/提示漏到下一个（本项目「状态残留」的老家族）。
    local rw = rb:CreateTexture(nil, "OVERLAY")
    rw:SetWidth(12) rw:SetHeight(12)
    rw:SetPoint("RIGHT", rb, "RIGHT", -2, 0)
    rw:Hide()
    local rec = { btn = rb, bg = rbg, text = rt, icon = ri, warn = rw, tip = nil }
    ddUI.rows[i] = rec
    rb:SetScript("OnEnter", function()
      pcall(rbg.SetVertexColor, rbg, 0.38, 0.30, 0.10, 1)
      if rec.tip and type(GameTooltip) ~= "nil" then
        pcall(GameTooltip.SetOwner, GameTooltip, rb, "ANCHOR_RIGHT")
        if type(rec.tip) == "table" then
          for ti = 1, table.getn(rec.tip) do pcall(GameTooltip.AddLine, GameTooltip, rec.tip[ti]) end
        else
          pcall(GameTooltip.SetText, GameTooltip, rec.tip)
        end
        pcall(GameTooltip.Show, GameTooltip)
      end
    end)
    rb:SetScript("OnLeave", function()
      pcall(rbg.SetVertexColor, rbg, 0.10, 0.09, 0.06, 1)
      if rec.tip and type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
  end
  dd:Hide()
  ddUI.root = dd
end

function EVAL_DD_HIDE() if ddUI.root then ddUI.root:Hide() end ddUI.anchor = nil end

-- ★1.71.2 供**宿主控件**（条件行里的光环名输入框）驱动的重过滤入口。
--   设计意图（用户要求）：把「输入关键字」放在**宿主那边**、而不是下拉面板内部，
--   于是下拉组件**完全不改**（不再有 ddUI.search / 残留黑块 / 光标那一整条链路的问题）。
--   ★过滤关键字来源改为「宿主传入」，故这里接收一个 kw 参数并复用 ddUI.refilter 的重入保护。
function EVAL_DD_REFILTER_OPEN(kw)
  if not ddUI.root then return false end
  local okS, shown = pcall(ddUI.root.IsShown, ddUI.root)
  if not (okS and shown) then return false end
  -- kw 传进来就更新（宿主 EditBox 每次输入都会调）；不传则沿用上次的关键字
  if kw ~= nil then ddUI.hostKw = kw end
  ddUI.searchText = ddUI.hostKw or ""
  if ddUI.refilter then pcall(ddUI.refilter) end
  return true
end

-- ★1.70.29 搜索过滤（纯函数，UI 与测试共用）：
--   输入 items/locked/关键字 -> 返回「按显示顺序排列的原始下标列表」。
--   · 关键字为空 = 不过滤（返回全部）
--   · 分组标题行（locked）**永不被过滤掉**：否则分组结构消失，用户看不懂列表
--   · 当关键字非空、启用自由文本、且表中没有与关键字完全同名的项时，
--     在末尾追加哨兵 -1（渲染为「✎ 使用输入的名称」）——满足「没有检索信息时让用户自己输入名称」
function DD_FILTER(items, locked, kw, allowFree)
  local out = {}
  local key = (kw ~= nil) and string.lower(tostring(kw)) or ""
  -- ★★1.71.2 两遍扫描（用户截图「顶部空白区域」）：
  --   第一遍先问「本次关键字有没有命中任何**可选行**」；
  --   第二遍才决定标题行的去留：
  --     · 有命中 → 标题照旧保留（那是分组结构，删了用户看不懂列表）
  --     · 一条都没命中 → **连标题一起过滤掉**
  --   起因：标题原本写死「永不被过滤」，于是像「阴影」这种一条都不命中的关键字，
  --   列表顶部会留下一条「只有标题、下面全空」的空白带——用户一眼就看到那块空白。
  --   ★注意顺序：必须先扫完可选行再决定标题，边扫边判会因「标题在第一项」而永远误判为有命中。
  local anyHit = false
  if key ~= "" then
    for i = 1, table.getn(items) do
      if not (locked and locked[i]) then
        if string.find(string.lower(tostring(items[i])), key, 1, true) ~= nil then anyHit = true break end
      end
    end
  end
  for i = 1, table.getn(items) do
    local keep = true
    if key ~= "" then
      if locked and locked[i] then
        keep = anyHit -- 标题：有命中才保留（全部落空时不留空带）
      else
        keep = (string.find(string.lower(tostring(items[i])), key, 1, true) ~= nil)
      end
    end
    if keep then table.insert(out, i) end
  end
  if allowFree and key ~= "" then
    local exact = false
    for i = 1, table.getn(items) do
      if not (locked and locked[i]) then
        if string.lower(tostring(items[i])) == key then exact = true break end
      end
    end
    if not exact then table.insert(out, -1) end
  end
  return out
end
-- 1.70.25：批量改选后按新的选中集重绘所有行（供「全部开启/全部关闭」这类宿主批量动作调用）。
-- 若不调用，被批量改动的行会保持旧方框，直到面板重开——表现为「勾选项与数据不一致」。
-- ★1.70.28 光环条件下拉菜单（文件作用域，UI 与测试共用）：
--   顺序 = ① 实时光环（目标/自身身上此刻真实存在的）→ ② 已记录过的光环名（跨会话持久）
--          → ③ 其余技能名（垫底，仍可选）。三组之间用不可点分组标题分隔。
--   ★为什么必须共用：先前测试自己复刻了一遍这个顺序，于是「删掉实时分组标题」这类变异
--   在测试里完全不可见（测试测的是副本）。抽到这里之后，UI 与断言看的是同一份代码。
function SE_AURA_MENU(k0)
  local items, names, locked = {}, {}, {}
  local function push(disp, nm)
    local i = table.getn(items) + 1
    items[i] = disp names[i] = nm
    return i
  end
  local function header(txt) -- 不可点分组标题（经 EVAL_DD_OPEN 的 opts.locked）
    local i = table.getn(items) + 1
    items[i] = "|cffaaaaaa" .. txt .. "|r"
    names[i] = nil
    locked[i] = true
  end
  local isAura = (k0 == "hasDebuff" or k0 == "noDebuff" or k0 == "hasBuff" or k0 == "noBuff" or k0 == "tBuff" or k0 == "pDebuff")
  -- ★1.70.29 若用户已输入关键字且表中无同名项，追加一行「使用输入的名称」——
  --   光环名可能不在任何名单里（自制/未记录/跨版本），没有这条用户就无路可走。
  --   注意：这里只登记候选，真正的过滤在 EVAL_DD_OPEN 里做（单一实现）。
  local kwNow = nil
  if type(ddUI) == "table" and ddUI.useSearch then
    kwNow = tostring(ddUI.searchText or "")
  end
  -- ① 实时光环（本条件对应单位身上「此刻真实存在」的光环）——**必须置顶**
  local liveN = 0
  if isAura then
    local live, mark = {}, "◆"
    if k0 == "hasDebuff" or k0 == "noDebuff" then
      live, mark = EVAL_TARGET_DEBUFF_LIST(), "◆"
    elseif k0 == "hasBuff" or k0 == "noBuff" then
      live, mark = EVAL_PLAYER_BUFF_LIST(), "○"
    elseif k0 == "tBuff" then
      live, mark = EVAL_TARGET_BUFF_LIST(), "●"
    elseif k0 == "pDebuff" then
      live, mark = EVAL_PLAYER_DEBUFF_LIST(), "▲"
    end
    liveN = table.getn(live)
    if liveN > 0 then
      header(L("SE_LIVE_AURA"))
      for _, d in ipairs(live) do push(mark .. d.name, d.name) end
    end
  end
  -- ② 已记录过的光环名（跨会话持久：光环此刻不在也能选——修「药水 buff 不及时显示」）
  if isAura then
    local seen = {}
    for _, n in ipairs(names) do seen[n] = true end
    local w2c = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war
    local lt = w2c and w2c.debuffTex
    local learned = {}
    if lt then for n in pairs(lt) do if not seen[n] and n ~= "" then table.insert(learned, n) end end end
    table.sort(learned)
    if table.getn(learned) > 0 then header(L("SE_LEARNED_AURA")) end
    for _, n in ipairs(learned) do push("◇" .. n, n) end
  end
  -- ③ 其余技能名（垫底；光环条件下它们大多不是光环，但保留以便手工指定）
  local rest = {}
  for _, n in ipairs(EVAL_GO_SKILL_CHOICES()) do
    if not petCmdOf(n) and not targetSelOf(n) and not itemOf(n) and not stanceOf(n) and not cancelCastOf(n) and not stopAllOf(n) and not followOf(n) then
      table.insert(rest, n)
    end
  end
  if table.getn(rest) > 0 then
    if isAura then header(L("SE_ALL_SKILLS")) end
    for _, n in ipairs(rest) do
      -- ★★★1.71.2（用户要求）：物品条目**保留但加标记区分**。
      --   用户实测问题：「buff 条件类型下拉为什么会出现泉水这些物品类的信息？」
      --   答案：本组是「动作条上的全部非宏格子」，而动作条上能放物品 → 裸名字混进来了。
      --   ★标记只改**显示串**（items[i]），不动**取值**（names[i]）——
      --     选中后写进 cd.s 的仍然是裸名字，否则 wslots 查不到、规则也会失效。
      --   ★为什么用**短标记 + 灰色**：下拉行的文字 FontString **没有限宽**（容易向右溢出到下一列），
      --     标记越短越安全；灰色本身也是一层区分（不占宽度）。
      local ws = wslots and wslots[n]
      if ws and ws.item then
        push(n .. " |cff888888[物]|r", n)
      else
        push(n, n)
      end
    end
  end
  return { items = items, names = names, locked = locked, liveN = liveN }
end
-- 测试直调（1.70.28）：报告光环下拉的构建顺序——**直接观察 SE_AURA_MENU 的真实输出**，
-- 而不是在测试里复刻一遍顺序（那会让「删掉实时分组标题」之类的变异完全不可见）。
function EVAL_TEST_AURA_DROPDOWN_ORDER(kindId)
  -- 直接看 SE_AURA_MENU（UI 用的那一份）的真实输出
  local m = SE_AURA_MENU(kindId)
  local items, locked, names = m.items, m.locked, m.names
  local firstLive, firstSkill, firstLearned = nil, nil, nil
  for i = 1, table.getn(items) do
    local it2 = items[i]
    if string.find(it2, "◆", 1, true) or string.find(it2, "○", 1, true)
      or string.find(it2, "●", 1, true) or string.find(it2, "▲", 1, true) then
      firstLive = firstLive or i
    elseif string.find(it2, "◇", 1, true) then
      firstLearned = firstLearned or i
    elseif not locked[i] and firstSkill == nil and it2 ~= "" then
      firstSkill = i
    end
  end
  local lockedN = 0
  for i = 1, table.getn(items) do if locked[i] then lockedN = lockedN + 1 end end
  return {
    n = table.getn(items),
    firstLive = firstLive, firstSkill = firstSkill,
    liveN = m.liveN,
    -- ★实时分组标题是否真的存在且排在第一位（只数 locked 行不够——菜单里还有其他分组标题，
    --   删掉实时这一条时 hasHeader 仍然为真，断言会假通过，本用例首版正是这样漏掉的）
    firstIsHeader = (locked[1] == true),
    firstItem = items[1],
    liveFirst = (firstLive ~= nil and firstSkill ~= nil and firstLive < firstSkill),
    hasHeader = (lockedN > 0),
    lockedHeaders = lockedN,
    -- ★1.71.2 加标记断言用：暴露**真实的显示串与取值表**（不在测试里重建一份）
    skillsLast = (m.liveN > 0 and firstSkill ~= nil and firstSkill > m.liveN),
    items = items, names = names,
  }
end

-- 1.70.25 测试直调：确认下拉件的多选/锁定能力【真的生效】，而不是只看标志位。
-- 背景：宿主（DataSearch 地图标注下拉）曾漏传 opts.multi，于是面板走非多选分支——
--   ① OnClick 里 dd:Hide() → 点一项就关（用户报「每次点击一个下拉窗不要关闭」）；
--   ② 勾选标记与面板自绘方框两套状态并存（用户报「选草药却把矿脉也勾上」）。
-- 因此断言必须覆盖「面板不因点选而隐藏」与「锁定行不产生勾」这两条可观察行为。
function EVAL_DD_TEST_OPEN_MULTI(items, onPick, opts)
  EVAL_DD_HIDE()
  if not ddUI.testAnchor then -- 惰性建一个测试用锚点（EVAL_DD_OPEN 必须拿到真实按钮来定位）
    local a = CreateFrame("Button", nil, UIParent)
    a:SetWidth(100) a:SetHeight(16)
    a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    a:Show()
    ddUI.testAnchor = a
  end
  opts = opts or {}
  opts.multi = true
  ddUI.anchor = nil -- 清掉上一轮的 toggle 判据，保证本次一定是「打开」而非「收起」
  EVAL_DD_OPEN(ddUI.testAnchor, items, onPick, opts)
  local shown = ddUI.root and ddUI.root:IsShown() and true or false
  return ddUI.multi and true or false, shown
end

-- 模拟点第 pi 行（走真实 OnClick 脚本，而非直接改状态），返回点击后面板是否仍显示
function EVAL_DD_TEST_CLICK(pi)
  local row = ddUI.rows and ddUI.rows[pi]
  if not (row and row.btn) then return nil end
  local fn = row.btn:GetScript("OnClick")
  if fn then fn() end
  return ddUI.root and ddUI.root:IsShown() and true or false, row
end

function EVAL_DD_TEST_MULTI() return ddUI.multi and true or false end
-- 1.70.29 搜索框行为（打开/输入/重入）测试直调
function EVAL_DD_TEST_OPEN_SEARCH(items, onPick, locked)
  EVAL_DD_HIDE()
  if not ddUI.testAnchor then
    local a = CreateFrame("Button", nil, UIParent)
    a:SetWidth(100) a:SetHeight(16)
    a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    a:Show()
    ddUI.testAnchor = a
  end
  ddUI.anchor = nil
  ddUI.searchText = ""
  EVAL_DD_OPEN(ddUI.testAnchor, items, onPick, { search = true, locked = locked, onFreeText = function() end })
  return true
end
-- ★1.71.2 判据从 IsShown() 改成「有没有被停放到屏幕外」：
--   本客户端 EditBox 用 Hide() 之后仍会画底条（用户截图「所有弹窗上部一条黑块」），
--   所以搜索框**不再走 Hide()**，而是挪出可视区 → IsShown() 恒真，不能再当可见性判据。
-- ★1.71.2 直接跑真实的搜索框构建（DD_BUILD 只在「第一次打开下拉」时执行，测试无法在受控时机触发它）。
--   用户截图的「所有弹窗上部一条看不见的黑块」是**层设置**问题，只有执行真实构建路径才能验证。
function EVAL_DD_TEST_BUILD_SEARCH()
  DD_BUILD()
  return ddUI.search ~= nil
end
-- 搜索框当前的「层」——桩把 SetDrawLayer 当空操作的话这里拿不到值，故同时暴露调用记录
function EVAL_DD_TEST_SEARCH_LAYER()
  if not ddUI.search then return nil end
  local ok, lay = pcall(function() return ddUI.search:GetDrawLayer() end)
  if ok and type(lay) == "string" then return lay end
  return nil
end
-- ★1.71.2 按**宿主关键字**打开下拉（复现光环条件那条路径：面板无搜索框、靠 opts.kw 过滤）。
--   返回可见行数，供断言验证「过滤真的生效」。
function EVAL_DD_TEST_OPEN_KW(items, kw, locked)
  EVAL_DD_HIDE()
  if not ddUI.testAnchor then
    local a = CreateFrame("Button", nil, UIParent)
    a:SetWidth(100) a:SetHeight(16)
    a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    a:Show()
    ddUI.testAnchor = a
  end
  ddUI.anchor = nil
  ddUI.searchText = ""
  ddUI.hostKw = nil
  EVAL_DD_OPEN(ddUI.testAnchor, items, function() end, { kw = kw, locked = locked })
  local n = 0
  for _, row in ipairs(ddUI.rows) do
    if row.btn and row.btn:IsShown() then n = n + 1 end
  end
  return n
end
-- 1.71.2 打开一个**不开搜索**的下拉（复现用户截图场景：条件类型/比较符/姿态号等短列表）
function EVAL_DD_TEST_OPEN_NO_SEARCH(items, onPick)
  EVAL_DD_HIDE()
  if not ddUI.testAnchor then
    local a = CreateFrame("Button", nil, UIParent)
    a:SetWidth(100) a:SetHeight(16)
    a:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -20)
    a:Show()
    ddUI.testAnchor = a
  end
  ddUI.anchor = nil
  ddUI.searchText = ""
  EVAL_DD_OPEN(ddUI.testAnchor, items, onPick)
  return true
end
function EVAL_DD_TEST_SEARCH_VISIBLE()
  if not ddUI.search then return false end
  local ok, x = pcall(ddUI.search.GetLeft, ddUI.search)
  if not (ok and type(x) == "number") then return false end
  return x > DD_SEARCH_PARK + 1
end
-- ★1.71.2 搜索框是否**真的回到面板内**（用户第三轮报的「光标消失」= 本体还在屏幕外，
--   只有背景被搬回来了）。判据 = 左边缘在面板左边缘附近，而不是停放坐标。
function EVAL_DD_TEST_SEARCH_IN_PANEL()
  if not ddUI.search then return false end
  local ok, x = pcall(ddUI.search.GetLeft, ddUI.search)
  if not (ok and type(x) == "number") then return false end
  return (x > DD_SEARCH_PARK + 1) and (x < 200)
end
-- ★1.71.2 把搜索框强制打到「停放态」——给往返断言一个**确定性起点**。
--   为什么必须有它：DD_BUILD 只在第一次打开下拉时执行（ddUI.root 已存在就 early-return），
--   所以测试里搜索框的初始位置是从**上一个用例**继承来的；不显式置位的话，
--   「先停放、再打开搜索」这条往返就变成了「碰巧上一轮是什么状态」——变异体照样能蒙混过关
--   （本轮实测：去掉「打开时搬回来」的修复，断言依然通过，就是栽在这个残留状态上）。
-- 记录搜索框被「搬回面板内」的次数。判据为什么用计数而不是坐标：
--   撤掉恢复动作时，坐标会**保持上一次的值**（本轮实测：变异体照样读到 x=4 → 断言假通过）；
--   计数才如实反映「这次打开有没有执行恢复动作」。
function EVAL_DD_TEST_SEARCH_POS_COUNT() return ddUI.posCount or 0 end
function EVAL_DD_TEST_PARK_SEARCH()
  local dd = ddUI.root
  if not (ddUI.search and dd) then return false end
  -- ★不用 GetParent()：**当时**测试桩对未知方法的兜底是「返回一个函数」，pcall 会成功但拿到函数而非帧
  --   （本轮实测 parkOk=false 就是这么来的）。ddUI.root 就是 DD_MAKE_SEARCH 里的那个 dd，直接用它。
  --   ★1.71.2（第二十轮）桩已补上真正的 GetParent（纹理能反查所在帧）——这里仍保留直接引用，
  --     因为它比「反查父帧」更**不含歧义**：少一层间接就少一个可能指错的对象。
  ddUI.search:ClearAllPoints()
  ddUI.search:SetPoint("TOPLEFT", dd, "TOPLEFT", DD_SEARCH_PARK, 0)
  return true
end
-- 供断言使用：面板本体（不是搜索框）当前是否显示
function EVAL_DD_TEST_ROOT_VISIBLE()
  return (ddUI.root and ddUI.root:IsShown()) and true or false
end
function EVAL_DD_TEST_SEARCH_TEXT() return tostring(ddUI.searchText or "") end
function EVAL_DD_TEST_TYPE_SEARCH(txt)
  -- 模拟用户逐字输入：先写进 EditBox，再触发 OnTextChanged（与真实路径一致）
  if ddUI.search then
    pcall(ddUI.search.SetText, ddUI.search, txt)
    local h = ddUI.search:GetScript("OnTextChanged")
    if h then h() end
  end
end
function EVAL_DD_TEST_FILTERED_COUNT()
  local n = 0
  for _, row in ipairs(ddUI.rows) do
    if row.btn and row.btn:IsShown() then n = n + 1 end
  end
  return n
end
function EVAL_DD_TEST_VISIBLE_TEXTS()
  local t = {}
  for _, row in ipairs(ddUI.rows) do
    if row.btn and row.btn:IsShown() and row.text then
      t[table.getn(t) + 1] = tostring(row.text:GetText())
    end
  end
  return t
end
function EVAL_DD_TEST_HAS_FREE_ROW()
  for _, row in ipairs(ddUI.rows) do
    if row.btn and row.btn:IsShown() and row.text then
      local t = row.text:GetText() or ""
      if string.find(t, "✎", 1, true) then return true end
    end
  end
  return false
end
function EVAL_DD_TEST_SHOWN() return (ddUI.root and ddUI.root:IsShown()) and true or false end
function EVAL_DD_TEST_RESET_ANCHOR() ddUI.anchor = nil end -- 让下一次 OPEN 一定是「打开」而非 toggle 收起
function EVAL_DD_TEST_ROW(i) return ddUI.rows and ddUI.rows[i] end
-- ★1.71.3 读**控件上实际设的纹理**（不是读 opts 传参——否则测的是「传了什么」而不是「画成了什么」）
function EVAL_DD_TEST_ROW_TEX(i)
  local row = ddUI.rows and ddUI.rows[i]
  if not (row and row.icon) then return nil end
  local ok, t = pcall(row.icon.GetTexture, row.icon)
  return ok and t or nil
end
function EVAL_DD_TEST_ROW_WARN(i)
  local row = ddUI.rows and ddUI.rows[i]
  if not (row and row.warn) then return nil end
  local ok, t = pcall(row.warn.GetTexture, row.warn)
  return ok and t or nil
end
function EVAL_DD_TEST_ROW_WARN_SHOWN(i)
  local row = ddUI.rows and ddUI.rows[i]
  if not (row and row.warn) then return false end
  local ok, s = pcall(row.warn.IsShown, row.warn)
  return (ok and s) and true or false
end
function EVAL_DD_TEST_ROW_TIP(i)
  local row = ddUI.rows and ddUI.rows[i]
  return row and row.tip or nil
end
function EVAL_DD_TEST_SELAT(i) return ddUI.sel and ddUI.sel[i] end
function EVAL_DD_TEST_LOCKED_SUPPORTED()
  -- 能力探测：开一个含锁定行的多选面板，锁定行必须【没有 OnClick】且【文本无方框】。
  local got = {}
  EVAL_DD_TEST_OPEN_MULTI({ "标题行", "可选项" }, function(p) got[#got + 1] = p end,
    { selected = {}, locked = { [1] = true } })
  local lockedRow = ddUI.rows and ddUI.rows[1]
  local okRow = ddUI.rows and ddUI.rows[2]
  if not (lockedRow and okRow) then return false end
  if lockedRow.btn:GetScript("OnClick") ~= nil then return false end -- 锁定行仍可点 → 不支持
  local t = lockedRow.text:GetText() or ""
  if string.find(t, "■", 1, true) or string.find(t, "□", 1, true) then return false end
  if okRow.btn:GetScript("OnClick") == nil then return false end -- 普通行必须可点
  EVAL_DD_HIDE()
  return true
end

function EVAL_DD_SYNC(sel)
  if not (ddUI.multi and ddUI.root) then return end
  ddUI.sel = sel or {}
  for _, row in ipairs(ddUI.rows) do
    if row._ddPaint and row.btn and row.btn:IsShown() then pcall(row._ddPaint) end
  end
end

-- anchorBtn 下方展开 items 列表；onPick(序号) 回调
-- opts.multi=true 多选模式（1.26.0）：点按切换选中（√ 金标）不关面板，onPick(序号, 是否选中) 逐项回调；
-- opts.selected = { [序号]=true } 初始选中集（面板重开时重建传入）。收起走 EVAL_DD_HIDE()/宿主窗 OnHide。
function EVAL_DD_OPEN(anchorBtn, items, onPick, opts)
  DD_BUILD()
  local dd = ddUI.root
  if not dd then return end
  -- 1.32.5 重复点击同一触发按钮 = 收起下拉（toggle）
  -- ★1.70.29：搜索框的「输入即过滤」会重入本函数（ddUI.reentrant=true），
  --   此时**绝不能走 toggle 分支**——否则用户每打一个字，下拉就被当成「再次点击锚点」而关闭。
  --   （这是实现搜索框时踩到的真 bug：过滤逻辑本身没错，错在重入被 toggle 吃掉。）
  local okS, shown = pcall(dd.IsShown, dd)
  if (not ddUI.reentrant) and okS and shown and ddUI.anchor == anchorBtn then EVAL_DD_HIDE() return end
  ddUI.anchor = anchorBtn
  -- ★1.70.29 输入即过滤：OnTextChanged 里重新走一遍本函数（参数与上次相同），
  --   保证过滤逻辑只有一份实现——若在别处复刻一份过滤，两处迟早会不一致。
  ddUI.refilter = function()
    if ddUI.anchor ~= anchorBtn then return end -- 面板已换宿主/已关闭：不要重开
    local okShown, sh = pcall(dd.IsShown, dd)
    if not (okShown and sh) then return end
    ddUI.reentrant = true
    EVAL_DD_OPEN(anchorBtn, items, onPick, opts)
    ddUI.reentrant = nil
  end
  ddUI.multi = (opts and opts.multi) and true or false
  ddUI.sel = (ddUI.multi and (opts.selected or {})) or nil -- 1.32.0 审计修复：multi 未传 selected 时索引 nil 隐患
  -- ★1.70.29：locked 不再以 multi 为前提。原先写成 (ddUI.multi and opts.locked) or nil，
  --   于是**非多选**的下拉（如光环条件菜单）拿不到 locked —— 一旦启用搜索，分组标题行会被
  --   关键字过滤掉（用户正在输入时分组结构整个消失）。locked 的语义是「该行不可选」，
  --   与「是否多选」无关，故独立存储。
  ddUI.locked = (opts and opts.locked) or nil
  -- ★1.70.29 搜索过滤：opts.search=true 时开启顶部输入框。
  --   filter 把「显示顺序」与「原始序号」分开——pi 始终是 items 里的原始下标，
  --   这样 onPick(pi) / ddUI.sel[pi] / opts.icons[pi] 全部语义不变，过滤只是「少显示几行」。
  local useSearch = (opts and opts.search) and true or false
  ddUI.useSearch = useSearch
  -- ★1.71.2 opts.kw = **宿主**提供的过滤关键字（条件行里的光环名输入框）。
  --   与 opts.search 的区别：kw 只提供「过滤词」，**不显示面板内搜索框**（用户要求去掉那个框）。
  --   ★过滤逻辑完全复用 DD_FILTER —— 单一实现，避免两处过滤行为漂移。
  if opts and opts.kw ~= nil then ddUI.searchText = tostring(opts.kw) end
  if not useSearch then ddUI.hostKw = (opts and opts.kw) or nil end
  -- 过滤关键字：面板内搜索框开启时用 searchText，否则用宿主提供的 hostKw
  local filterKw = useSearch and ddUI.searchText or ddUI.hostKw
  -- 过滤与「自由文本行」的判定抽成纯函数 DD_FILTER（见下）——UI 与测试共用同一份实现，
  -- 否则测试只能复刻逻辑，变异将不可见（本项目已三次踩到这个坑）。
  -- ★1.71.2 过滤关键字来源：面板内搜索框（useSearch）或**宿主输入框**（filterKw）。
  --   自由文本哨兵行只在「面板内有搜索框」时启用——宿主方案下由宿主自己提交自定义名称。
  local shownList = DD_FILTER(items, ddUI.locked, filterKw,
    useSearch and (opts.onFreeText ~= nil) or false)
  local nAll = table.getn(items)
  local n = table.getn(shownList)
  -- ★★★ 绝不静默截断（本项目铁律）：超出行池时**如实告知还有多少项**，而不是悄悄丢掉。
  local truncated, nDraw = 0, n
  if n > DD_MAX_ROWS then truncated = n - (DD_MAX_ROWS - 1) nDraw = DD_MAX_ROWS end
  local cols = math.ceil(nDraw / DD_COLS)
  if cols < 1 then cols = 1 end
  local icons = opts and opts.icons -- 1.32.4 可选图标列：与 items 同序的纹理表
  local warns = opts and opts.warns -- ★1.71.3 可选异常标记列：与 items 同序（值为纹理路径）
  local tips = opts and opts.tips   -- ★1.71.3 可选悬停说明：与 items 同序（字符串或 {行1,行2,…}）
  local colW = (icons or warns) and 124 or 108
  for slot, row in ipairs(ddUI.rows) do
    if slot <= nDraw then
      local i = shownList[slot]   -- 显示位置 -> 原始下标（负数 = 自由文本哨兵行）
      local pi = i                -- pi 保持「原始下标」语义（onPick/sel/icons 都按它索引）
      if truncated > 0 and slot == nDraw then
        -- ★截断提示行（不可点）
        row.icon:Hide()
        row.warn:Hide() -- ★1.71.3 截断提示行不许带异常标记/悬停（残留防护）
        row.tip = nil
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 4, 0)
        row.text:SetText("|cffff8080" .. string.format(L("DD_MORE_FMT"), truncated) .. "|r")
        row.btn:SetScript("OnClick", nil)
        local colT = math.floor((slot - 1) / DD_COLS)
        local riT = math.mod(slot - 1, DD_COLS)
        row.btn:ClearAllPoints()
        row.btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 4 + colT * colW, -(4 + SEARCH_H) - riT * 15)
        row._ddPaint = nil
        row.btn:Show()
      elseif i == -1 then
        row.icon:Hide()
        row.warn:Hide() -- ★1.71.3 自由文本行不许带异常标记/悬停（残留防护）
        row.tip = nil
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 4, 0)
        row.text:SetText("|cff40ff40✎|r " .. L("DD_USE_TYPED") .. " \"" .. tostring(ddUI.searchText) .. "\"")
        row.btn:SetScript("OnClick", function()
          local txt = ddUI.searchText
          EVAL_DD_HIDE()
          opts.onFreeText(txt)
        end)
        local col0 = math.floor((slot - 1) / DD_COLS)
        local ri0 = math.mod(slot - 1, DD_COLS)
        row.btn:ClearAllPoints()
        row.btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 4 + col0 * colW, -(4 + SEARCH_H) - ri0 * 15)
        row._ddPaint = nil
        row.btn:Show()
      else
      local ic = icons and icons[i]
      if ic then
        pcall(row.icon.SetTexture, row.icon, ic)
        row.icon:Show()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 18, 0)
      else
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.btn, "LEFT", 4, 0)
      end
      -- ★1.71.3 异常标记：有就显示并记下悬停说明，没有就**必须清掉**（行池复用，残留就是 bug）
      local wi = warns and warns[i]
      if wi then
        pcall(row.warn.SetTexture, row.warn, wi)
        row.warn:Show()
      else
        row.warn:Hide()
      end
      -- ★1.71.3 悬停说明：**逐项** tips 优先（用户要求：把「支持选取规则的条件类型」分别加 tooltip），
      --   没有逐项说明时才退回「异常标记」那句 warnTip。★每次重绘都要重设（行池复用，残留就是 bug）。
      row.tip = (tips and tips[i]) or (wi and opts.warnTip) or nil
      if ddUI.multi then
        -- 多选标记统一为「方框」样式，与配置窗自绘勾选框（cfgCheck）观感一致：
        -- 选中=|cffffd100■|r、未选=|cff6a6a6□|r（用户要求「支持第二张图的方式多选」）
        -- ★1.70.25：分组标题等「不可选行」用 opts.locked[序号]=true 声明——多选模式下它们
        --   仍会画出方框并接收点击，若不特殊处理，点标题行会凭空多出一个勾（本客户端用户实测
        --   「我选的是草药，矿脉也被勾上了」的诱因之一：行状态与数据源不一致时极易被读错）。
        --   locked 行改为渲染纯文本、不画方框、点击不切换也不回调。
        local locked = ddUI.locked and ddUI.locked[pi] and true or false
        local function paint()
          if locked then row.text:SetText(tostring(items[pi])) return end
          local on = ddUI.sel and ddUI.sel[pi] and true or false
          row.text:SetText((on and "|cffffd100■|r " or "|cff6a6a6a□|r ") .. tostring(items[pi]))
        end
        paint()
        row._ddPaint = locked and nil or paint -- 供 EVAL_DD_SYNC 批量重绘（全开/全关后刷新所有行）
        if locked then
          row.btn:SetScript("OnClick", nil)
        else
          row.btn:SetScript("OnClick", function()
            local nowOn = not (ddUI.sel[pi] and true or false)
            ddUI.sel[pi] = nowOn or nil
            paint()
            onPick(pi, nowOn)
          end)
        end
      else
        row.text:SetText(tostring(items[i]))
        row.btn:SetScript("OnClick", function() dd:Hide() onPick(pi) end)
      end -- 自由文本哨兵行
      end
      -- 布局按【显示位置 slot】，不是原始下标 i（过滤后两者不同）
      local col = math.floor((slot - 1) / DD_COLS)
      local ri = math.mod(slot - 1, DD_COLS)
      row.btn:ClearAllPoints()
      row.btn:SetPoint("TOPLEFT", dd, "TOPLEFT", 4 + col * colW, -(4 + SEARCH_H) - ri * 15)
      row.btn:Show()
    else
      row.btn:Hide()
    end
  end
  local rows = math.min(n, DD_COLS)
  local totalH = 8 + SEARCH_H + rows * 15
  dd:SetWidth(math.max(8 + cols * colW, useSearch and 200 or 0))
  dd:SetHeight(totalH)
  dd:ClearAllPoints()
  dd:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
  -- 贴屏底时改为向上展开
  local okb, ab = pcall(anchorBtn.GetBottom, anchorBtn)
  if okb and type(ab) == "number" then
    local oke, es = pcall(dd.GetEffectiveScale, dd)
    local k = (oke and type(es) == "number" and es > 0) and es or 1
    if ab < totalH * k + 20 then
      dd:ClearAllPoints()
      dd:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 2)
    end
  end
  -- 搜索框显隐与尺寸（放在行区上方）
  if ddUI.search then
    if useSearch then
      -- GetWidth 在测试桩里可能返回 nil：用 pcall + 兜底宽度，避免整条打开流程炸掉
      local ddW = 200
      local okw, wv = pcall(dd.GetWidth, dd)
      if okw and type(wv) == "number" and wv > 0 then ddW = wv end
      local w = math.max(60, ddW - 8)
      pcall(ddUI.search.SetWidth, ddUI.search, w - 4)
      -- ★★★1.71.2 第三轮（用户实测：「不是没了，是**光标**消失了」）：
      --   搜索框本体是显示的，丢的是**输入光标/聚焦状态**。
      --   根因就在这几行：原来只把 searchBg 重新锚回面板内，**搜索框自己却还停在停放坐标**
      --   （DD_SEARCH_PARK，屏幕外）——它没有任何 EditBox 的错，只是被上一次「不用搜索的下拉」
      --   挪走后再没搬回来；离屏的 EditBox 拿不到焦点，自然没有光标。
      --   ★教训：把控件「挪走」是一个**状态**，凡是挪走就必须在**所有**恢复路径上搬回来。
      --     只恢复背景不恢复本体，就是「一半搬回来」——肉眼看不出控件缺失，只表现为光标不见了。
      ddUI.search:ClearAllPoints()
      ddUI.search:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -3)
      pcall(ddUI.search.Show, ddUI.search)
      ddUI.posCount = (ddUI.posCount or 0) + 1 -- 「搬回来了」的计数（见 EVAL_DD_TEST_SEARCH_POS_COUNT）
      ddUI.searchBg:ClearAllPoints()
      ddUI.searchBg:SetPoint("TOPLEFT", dd, "TOPLEFT", 4, -3)
      ddUI.searchBg:SetWidth(w) ddUI.searchBg:SetHeight(16)
      pcall(ddUI.searchBg.Show, ddUI.searchBg)
      -- 每次【用户重新打开】才清空；过滤引发的重入必须保留关键字，
      -- 否则打字一个字就被自己清掉（本特性最容易踩的坑）。
      if not ddUI.reentrant then
        pcall(ddUI.search.SetText, ddUI.search, "")
        ddUI.searchText = ""
        pcall(ddUI.search.SetFocus, ddUI.search)
      end
    else
      -- ★1.71.2 不用 Hide()：本客户端 EditBox 隐藏后仍会画出底条（用户截图证据）→ 挪出屏幕
      ddUI.search:ClearAllPoints()
      ddUI.search:SetPoint("TOPLEFT", dd, "TOPLEFT", DD_SEARCH_PARK, 0)
      ddUI.searchBg:ClearAllPoints()
      ddUI.searchBg:SetPoint("TOPLEFT", dd, "TOPLEFT", DD_SEARCH_PARK, 0)
      ddUI.searchText = ""
    end
  end
  dd:Show()
end

-- ★1.70.46 这两个函数**必须声明在 EVAL_HELP_SE_REFRESH 之前**——它俩原本写在 SE_REFRESH 之后，
--   而 SE_REFRESH 里已经调用 seSecKinds → 那里绑到的是**全局**（声明在后的 local 不在它的词法作用域内），
--   于是「自身buff 条件类型」一点就红字报错 attempt to call global seSecKinds (a nil value)（用户截图）。
--   ★Lua 作用域是**词法**的：引用点若在 local 声明之前，永远看不到它；这与「调用顺序」无关。
--   ★这正是本项目累计十几次的同一类坑，也是 DECL ORDER CHECK 存在的理由（本轮把它扩到全部 .lua 文件）。
-- ★1.70.45 哪些条件类型支持「剩余时间检查」：**仅自身光环**。
--   依据（wiki globals/Buff）：只有自身光环有时长 API（GetPlayerBuffTimeLeft → 秒）；
--   其他单位的 UnitBuff/UnitDebuff 只返回 图标+层数，目标侧没有时长可查。
--   ★UI 与断言共用这一份判定——测试若自己复刻一遍，把这里改坏就测不出来（本项目已多次栽在这）。
local function seSecKinds(k)
  return (k == "hasBuff" or k == "pDebuff")
end

-- ★1.70.45 「剩余时间」步进：单位秒、步进 1、区间 1-300（用户指定）。
--   ± 按钮与断言共用本函数（测试自己复刻夹紧逻辑的话，把这里改坏就测不出来）。
local function seSecStep(cd, delta)
  if not (cd and type(cd.secN) == "number") then return end
  local v = cd.secN + delta
  if v < 1 then v = 1 elseif v > 300 then v = 300 end
  cd.secN = v
end

function EVAL_HELP_SE_REFRESH()
  local ed = seUI.ed
  if not ed or not seUI.root then return end
  -- 技能选择器
  local t0 = wicon(ed.skill)
  if t0 then
    pcall(seUI.skillIcon.SetTexture, seUI.skillIcon, t0)
    pcall(seUI.skillIcon.SetVertexColor, seUI.skillIcon, 1, 1, 1)
  else
    uiSolid(seUI.skillIcon, 0.25, 0.25, 0.25, 1)
  end
  seUI.skillName:SetText(tostring(ed.skill))
  if seUI.catName then -- 分类按钮文字 = 当前技能所属类（1.32.3）
    local cl = { L("SK_CAT_1"), L("SK_CAT_2"), L("SK_CAT_3"), L("SK_CAT_4"), L("SK_CAT_5") }
    local ci = 2
    if ed.skill == "攻击" or ed.skill == "自动射击" or ed.skill == "射击" or cancelCastOf(ed.skill) or stopAllOf(ed.skill) or followOf(ed.skill) or stanceOf(ed.skill) then ci = 1
    elseif petCmdOf(ed.skill) then ci = 3
    elseif targetSelOf(ed.skill) then ci = 4
    elseif itemOf(ed.skill) then ci = 5 end
    seUI.catName:SetText(cl[ci])
  end
  if ed.enabled then seUI.enMark:Show() else seUI.enMark:Hide() end
  -- 条件行
  for i, row in ipairs(seUI.rows) do
    local it = ed.conds[i]
    for _, wgt in ipairs(row.all) do pcall(wgt.Hide, wgt) end
    if it then
      local cd = it.cd
      row.conn.text:SetText(i == 1 and "当" or ((it.conn == "|") and "｜" or (it.conn or "&"))) -- 1.61.2 关系列同用全角竖线
      pcall(row.conn.btn.Show, row.conn.btn)
      local ti = seTypeIndexOf(cd.k, cd.name)
      local td = SE_TYPES[ti]
      row.typeBtn.text:SetText(L("CT_" .. string.upper(td.id)))
      pcall(row.typeBtn.btn.Show, row.typeBtn.btn)
      if td.kind == "num" then
        row.opBtn.text:SetText(cd.op or ">")
        -- 1.58.0 时间型一位小数显示（步进 0.1；防 0.30000000004 浮点噪音）
        local isTime = (cd.k == "swingLeft" or cd.k == "castEl" or cd.k == "castLeft" or cd.k == "tCastEl" or cd.k == "tCastLeft")
        row.valText:SetText(isTime and string.format("%.1f", cd.n or 0) or tostring(cd.n or 0))
        pcall(row.opBtn.btn.Show, row.opBtn.btn)
        pcall(row.minus.btn.Show, row.minus.btn)
        pcall(row.plus.btn.Show, row.plus.btn)
        pcall(row.valText.Show, row.valText)
      elseif td.kind == "bool" then
        row.valBtn.text:SetText(cd.v and "是" or "否")
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
      elseif td.kind == "flag" then
        row.valBtn.text:SetText(cd.inv and "否" or "是")
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
      elseif td.kind == "form" then
        row.valBtn.text:SetText(cd.k == "formNot" and "非" or "是")
        row.formN.text:SetText(tostring(cd.n or 1))
        pcall(row.valBtn.btn.Show, row.valBtn.btn)
        pcall(row.formN.btn.Show, row.formN.btn)
      elseif td.kind == "skill" then
        local disp = tostring(cd.s or "?")
        if cd.k == "tCasting" and (cd.s == nil or cd.s == "") then disp = L("TCAST_ANY") end -- 1.40.0 空参数=任意施法
        if cd.k == "casting" and (cd.s == nil or cd.s == "") then disp = L("TCAST_ANY") end -- 1.41.0 自身施法同规
        -- 1.70.0：空技能名（光环检查/免疫/范围）提示待选，避免旧职业化默认造成「条件恒不满足却不自知」
        if (cd.s == nil or cd.s == "") and cd.k ~= "casting" and cd.k ~= "tCasting" then disp = "未选择（点此选择）" end
        -- ★1.70.47 队伍debuff 的名称是**可选**的（不填 = 只看「有没有任意该类型的负面效果」）
        if (cd.k == "teamDebuff" or cd.k == "candDebuff") and (cd.s == nil or cd.s == "") then disp = L("DS_T_ANY") end
        local auraChk = (cd.k == "hasBuff" or cd.k == "hasDebuff" or cd.k == "tBuff" or cd.k == "pDebuff") -- 1.54.0 光环检查型 是/否
        -- ★1.70.47 队伍/团队光环型也要 是/否（「队伍有魔法」「团队无buff」都得能切）
        local teamAura = (cd.k == "teamBuff" or cd.k == "teamDebuff" or cd.k == "candBuff" or cd.k == "candDebuff") -- ★1.71.3 候选者光环型同样有 是/否
        if cd.k == "immune" or cd.k == "inRange" or cd.k == "casting" or cd.k == "tCasting" or auraChk or teamAura then
          if cd.k == "inRange" or cd.k == "casting" or cd.k == "tCasting" or auraChk or teamAura then
            row.immBtn.text:SetText((cd.v == false) and L("SE_NO") or L("SE_YES"))
          else
            row.immBtn.text:SetText((cd.v == false) and L("IMM_N") or L("IMM_Y"))
          end
          pcall(row.immBtn.btn.Show, row.immBtn.btn)
        end
        -- 1.70.1：层数门槛对【四类光环检查】全部开放（buff/debuff 都可能堆叠）；旧版只给 目标debuff 显示「层」，
        -- 且层按钮与是/否按钮坐标重叠→表现为「目标debuff 缺 是/否」（用户实测截图）
        if auraChk or teamAura or cd.k == "noDebuff" or cd.k == "noBuff" then
          if type(cd.n) == "number" and cd.n > 1 then
            disp = disp .. (((cd.v == false) and " <" or " ≥") .. cd.n) -- 看 v 方向：是=至少N层 / 否=不足N层
          end
          row.stk.text:SetText(type(cd.n) == "number" and cd.n > 1 and ("层" .. cd.n) or "层")
          pcall(row.stk.btn.Show, row.stk.btn)
        end
        -- ★1.70.45 剩余时间：只在自身光环上出现（seSecKinds 是 UI/断言共用的判据）；
        --   「不限」时只显示那一个按钮，启用后才出现 [-] 值 [+]。
        if seSecKinds(cd.k) then
          local secOn = (type(cd.secN) == "number")
          row.secOp.text:SetText(secOn and L("SE_SEC_FMT", cd.secOp or "<") or L("SE_SEC_UNLIM"))
          pcall(row.secOp.btn.Show, row.secOp.btn)
          if secOn then
            row.secText:SetText(tostring(cd.secN))
            pcall(row.secMinus.btn.Show, row.secMinus.btn)
            pcall(row.secPlus.btn.Show, row.secPlus.btn)
            pcall(row.secText.Show, row.secText)
          end
        end
        row.skillText:SetText(disp)
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      elseif td.kind == "target" then
        local disp = (cd.s == "byName") and ("指定:" .. tostring(cd.nm or "未设")) or (TARGET_SEL_NAME[cd.s] or tostring(cd.s or "?"))
        row.skillText:SetText(disp)
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      elseif td.kind == "class" then
        local ns = {}
        for _, c in ipairs(CLASS_LIST) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.name) end end
        row.skillText:SetText(table.getn(ns) > 0 and table.concat(ns, "/") or "未选择（永不满足）")
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
      elseif td.kind == "creature" then
        -- 1.70.28 目标类型：选中项 / 是-否；并附上「此刻客户端实际报告的类型」便于核对
        local ns = {}
        for _, c in ipairs(CREATURE_TYPES) do if cd.cs and cd.cs[c.id] then table.insert(ns, L("CRE_" .. string.upper(c.id))) end end
        local disp = table.getn(ns) > 0 and table.concat(ns, "/") or L("CRE_UNSELECTED")
        row.skillText:SetText(disp)
        pcall(row.sHit.Show, row.sHit)
        pcall(row.skillText.Show, row.skillText)
        row.immBtn.text:SetText((cd.v == false) and L("SE_NO") or L("SE_YES"))
        pcall(row.immBtn.btn.Show, row.immBtn.btn)
      end
      -- ★1.70.47 队伍debuff：类型下拉（魔法/诅咒/毒/疾病/任意）。
      --   显示名走 L("DS_T_*")，与 Engine 的 dispelMatch 共用同一套 id（Magic/Curse/…）。
      --   ★判据用「解析出来的类型」（td），不用原始 cd.k——队伍行与团队行的 cd.k 都是 teamDebuff，
      --     但类型下拉对**两行**都要出现；只认 cd.k 时团队行会漏掉这个控件。
      --     同时这里也是断言能真正走到的位置：EVAL_TEST_SE_ROW_DT 问的就是这个控件。
      if (td.base or td.id) == "teamDebuff" or td.id == "candDebuff" then -- ★1.71.3 候选者debuff 也要类型下拉
        local lbl = L("DS_T_ANY")
        if cd.dt and cd.dt ~= "" and cd.dt ~= "any" then
          lbl = L("DS_T_" .. string.upper(tostring(cd.dt)))
        end
        row.dtBtn.text:SetText(lbl)
        pcall(row.dtBtn.btn.Show, row.dtBtn.btn)
      end
      -- ★1.71.3 队伍/团员条件的「职业多选 / 小队多选」：
      --   ★显示串按语言包取，窄格最多列 3 项（多了用 …，格宽只有 56px）
      -- ★1.71.3 「成员类」条件 = 8 项队伍/团员 + 4 项候选者：这两族都能带「职业过滤」
      --   （候选者那 4 项是选取器行的过滤条件——「只给法师补智力」就是这么配的）；小队格仍只给团员条件。
      local mkid = td.base or td.id
      local isTeamKind = (mkid == "teamHp") or (mkid == "teamMana") or (mkid == "teamBuff") or (mkid == "teamDebuff")
                         or (mkid == "candHp") or (mkid == "candPower") or (mkid == "candBuff") or (mkid == "candDebuff")
      if isTeamKind then
        local ns = {}
        for _, c in ipairs(CLASS_LIST) do if cd.cs and cd.cs[c.id] then table.insert(ns, c.name) end end
        if table.getn(ns) > 3 then ns = { ns[1], ns[2], ns[3], "…" } end
        row.clsBtn.text:SetText(table.getn(ns) > 0 and table.concat(ns, "/") or L("SE_CLS_ALL"))
        pcall(row.clsBtn.btn.Show, row.clsBtn.btn)
        if cd.name == "团队" then -- ★小队多选**只对团员条件**有意义（队伍里人人都是 1 队）
          local gs2 = {}
          for gi = 1, 8 do if cd.gs and cd.gs[gi] then table.insert(gs2, tostring(gi)) end end
          row.grpBtn.text:SetText(table.getn(gs2) > 0 and table.concat(gs2, "/") or L("SE_GRP_ALL"))
          pcall(row.grpBtn.btn.Show, row.grpBtn.btn)
        end
      end
      row.preview:SetText(EVAL_COND_STR(cd))
      -- ★让位：这两格占的正是行内预览的位置 → 队伍/团员那 8 行不显示行内预览（底部整串预览照旧）
      if isTeamKind then pcall(row.preview.Hide, row.preview) else pcall(row.preview.Show, row.preview) end
      pcall(row.del.btn.Show, row.del.btn)
    end
  end
  -- 底部实时预览（整串条件）
  seUI.preview:SetText(uiEsc(EVAL_GROUP_STR(seLinearToGroups(ed.conds)))) -- 1.61.1 | 显示转义
end

local function SE_BUILD()
  if seUI.root then return end
  local W, H = cfWinWidth(), 280 -- 1.70.45：与配置窗同宽（原固定 470）
  local root = CreateFrame("Frame", "EVAL_HELP_SE", UIParent)
  root:SetWidth(W)
  seUI.W = W -- 1.70.45 记下实际宽度（供断言与 cfgWin.W 比对）
  -- ★1.70.46 实测事故：上一行原本写成 `... -- 注释 root:SetHeight(H)`，
  --   SetHeight 被行尾注释**吞掉** → 窗口从未设置高度 → 客户端给了个接近整屏的默认高度，
  --   技能编辑窗变成一块几乎全黑的大窗并盖住配置窗（用户截图）。宽度正确、只有高度异常。
  --   ★语法合法、luacheck 通过、测试全绿——当时没有任何断言盯着「高度真的被设置」。
  root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 60, 80)
  -- 配置窗是 DIALOG strata：本窗必须同级 + 更高 frameLevel，否则被配置窗盖住（1.11.2 修复）
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 100)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then -- 越界回归视野中心
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(16)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10) end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("SE_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- 技能选择行（1.32.3 二级下拉 UI）：[分类▾] [图标] [具体项▾]　启用
  -- 分类按钮在左（替代旧"技能:"标签位），项按钮在右——点哪个弹哪级，所见即两级
  local function seCatOfSkill(skill) -- 技能名 → 分类序号（EVAL_GO_SKILL_CATEGORIES 顺序）
    if skill == "攻击" or skill == "自动射击" or skill == "射击" or cancelCastOf(skill) or stopAllOf(skill) or followOf(skill) or stanceOf(skill) then return 1 end
    if petCmdOf(skill) then return 3 end
    if targetSelOf(skill) then return 4 end
    if itemOf(skill) then return 5 end
    return 2
  end
  -- 项列表 → 图标表（1.32.4：下拉行左侧显示技能/物品图标；wicon 统一入口含宠物/选取/物品兜底）
  local function seItemIcons(items)
    local icons, any = {}, false
    for i, v in ipairs(items) do
      local nm = string.match(v, "^(物品[:：].-)×%d+$") or v
      local t = wicon(nm)
      if t then icons[i] = t any = true end
    end
    return any and icons or nil
  end
  -- ★1.71.3 项列表 → 「异常标记」表（与 opts.icons 同序；nil = 该行不标）。
  --   ★为什么与 icons 分开而不是塞进同一条：图标回答「这是什么」，标记回答「它有问题」——
  --     两件事挤在一个字段里，会让「图标设了但标记没出来」这类 bug 永远测不出来。
  local function seItemWarns(items)
    local warns, any = {}, false
    for i, v in ipairs(items) do
      local nm = string.match(v, "^(物品[:：].-)×%d+$") or v
      if cancelCastOf(nm) then warns[i] = SE_WARN_ICON any = true end
    end
    return any and warns or nil
  end
  -- 悬停说明：两行（标题 + 原因）。★文案走语言包，三语言齐全（LANG KEY CHECK 守住字面量）。
  local function seWarnTip() return { L("SE_WARN_T"), L("SE_WARN_CANCELCAST") } end
  -- ★★★1.71.3 悬停说明（用户要求「分辨加入」）：**类型格**给出该类型的规则说明；**比较符格**给出
  --   「比较符 → 挑谁」的对照。★只在「参与规则的类型」上出现（其它类型不弹，免得满屏提示）。
  --   ★★本轮从行池循环里**提出来**（单一实现）：「启用此技能」右侧的图例悬停要用同一套写法，
  --     再写一份就是两处各写一遍（本项目「同一判据写两遍迟早漂移」的老坑）。
  local function seHoverTip(btn, tipFn)
    if type(btn) ~= "table" or type(btn.SetScript) ~= "function" then return end
    -- ★seBtn 不装 OnEnter/OnLeave（见其定义）→ 这里直接设即可；仍写成"只设一次"以免重复包装
    btn:SetScript("OnEnter", function()
      local tip = tipFn()
      if not (tip and type(GameTooltip) ~= "nil") then return end
      pcall(GameTooltip.SetOwner, GameTooltip, btn, "ANCHOR_RIGHT")
      for ti = 1, table.getn(tip) do pcall(GameTooltip.AddLine, GameTooltip, tip[ti]) end
      pcall(GameTooltip.Show, GameTooltip)
    end)
    btn:SetScript("OnLeave", function()
      if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
    end)
  end
  -- ★1.71.3「这一行是不是成员选取器」= **单一判据**（类型下拉过滤 + 新增条件的初始类型都用它）
  local function seIsPickerRow(skill)
    return (type(tselTeam) == "table") and (tselTeam[targetSelOf(skill)] ~= nil)
  end
  -- ★★★1.71.3 新增条件的**初始类型**从这一行的下拉过滤表里选（用户要求「添加初始值从过滤条件内选」）：
  --   成员选取器行 → 第一个候选者条件（候选者血%，就是下拉里排第一的那项）；
  --   其它行 → 仍是 SE_TYPES 第 1 项（**原行为一字不动**）。
  --   ★原先恒用第 1 项 → 在选取器行上会加出一条**下拉里根本没有**的条件（用户看到的正是这个）。
  local function seRowFirstType(skill)
    if seIsPickerRow(skill) then
      local tp = SE_BY_K["candHp"]
      if tp then return tp end
    end
    return 1
  end
  -- 项选中落值（两个下拉共用）：特殊项弹输入框，物品项剥 ×数量 展示后缀
  local function seApplySkillPick(v)
    if not v then return end
    if v == L("SE_PICK_ITEM") then
      EVAL_TN_OPEN(L("SE_TN_ITEM"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "物品:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    if v == L("SE_PICK_TGT") then
      EVAL_TN_OPEN(L("SE_TN_TARGET"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "选取目标:指定名称:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    -- ★1.71.3 跟随：同样弹名字输入（空名不接受——客户端把「空名字」当「跟当前目标」）
    if v == L("SE_PICK_FOLLOW") then
      EVAL_TN_OPEN(L("SE_TN_FOLLOW"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "跟随:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    seUI.ed.skill = string.match(v, "^(物品[:：].-)×%d+$") or v
    EVAL_HELP_SE_REFRESH()
  end
  -- 分类下拉（一级）
  local catW = seBtn(root, 16, -24, 72, 16, "", function()
    if not seUI.ed then return end
    local cats = EVAL_GO_SKILL_CATEGORIES()
    local labels, catIcons, anyIcon = {}, {}, false
    for i = 1, table.getn(cats) do
      local c = cats[i]
      labels[i] = c.label
      catIcons[i] = c.icon
      if c.icon then anyIcon = true end
    end
    -- ★1.71.3 用户要求「角色行为下拉添加图标美化」：类别行也带图标。
    --   ★图标来自 EVAL_GO_SKILL_CATEGORIES 的 icon 字段（**单一来源**，UI 层不另写一份映射）；
    --   ★用下标赋值而不是 table.insert：insert 遇到 nil 会**不插入**，整表错位。
    EVAL_DD_OPEN(seUI.catBtn, labels, function(ci)
      local cat = cats[ci]
      if not cat then return end
      -- 选完分类立即续弹该类的项列表（沿用 byName 续弹范式）
      local items = cat.items()
      EVAL_DD_OPEN(seUI.skillBtn, items, function(pi)
        seApplySkillPick(items[pi])
      end, { icons = seItemIcons(items), warns = seItemWarns(items), warnTip = seWarnTip() })
    end, { icons = anyIcon and catIcons or nil })
  end)
  seUI.catBtn = catW.btn
  seUI.catName = catW.text
  local icon = root:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", root, "TOPLEFT", 94, -24)
  icon:SetWidth(15) icon:SetHeight(15)
  seUI.skillIcon = icon
  -- 具体项下拉（二级）：直接弹当前分类的项列表
  -- 注意：seBtn 返回包裹表 { btn, bg, text }，不是按钮本体——锚点/加文字一律用 .btn（1.21.4 修复）
  local skW = seBtn(root, 114, -24, 100, 16, "", function()
    if not seUI.ed then return end
    local cats = EVAL_GO_SKILL_CATEGORIES()
    local cat = cats[seCatOfSkill(seUI.ed.skill)]
    if not cat then return end
    local items = cat.items()
    EVAL_DD_OPEN(seUI.skillBtn, items, function(pi)
      seApplySkillPick(items[pi])
    end, { icons = seItemIcons(items), warns = seItemWarns(items), warnTip = seWarnTip() })
  end)
  local skBtn = skW.btn
  seUI.skillBtn = skBtn
  local skName = uiText(skBtn, 10, 1, 0.9, 0.5)
  skName:SetPoint("CENTER", skBtn, "CENTER", 0, 0)
  pcall(skName.SetWidth, skName, 96) -- 长名（物品:xxx）裁剪防溢出到启用框
  pcall(skName.SetNonSpaceWrap, skName, false)
  seUI.skillName = skName
  local enChk = CreateFrame("Button", nil, root)
  enChk:SetWidth(14) enChk:SetHeight(14)
  enChk:SetPoint("TOPLEFT", root, "TOPLEFT", 216, -25)
  pcall(enChk.EnableMouse, enChk, true)
  pcall(enChk.RegisterForClicks, enChk, "LeftButtonUp")
  local enOut = enChk:CreateTexture(nil, "BACKGROUND")
  uiSolid(enOut, 0.85, 0.70, 0.20, 1)
  enOut:SetPoint("TOPLEFT", enChk, "TOPLEFT", 0, 0)
  enOut:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", 0, 0)
  local enIn = enChk:CreateTexture(nil, "ARTWORK")
  uiSolid(enIn, 0.10, 0.09, 0.06, 1)
  enIn:SetPoint("TOPLEFT", enChk, "TOPLEFT", 1, -1)
  enIn:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", -1, 1)
  local enMark = enChk:CreateTexture(nil, "OVERLAY")
  uiSolid(enMark, 0.95, 0.80, 0.25, 1)
  enMark:SetPoint("TOPLEFT", enChk, "TOPLEFT", 3, -3)
  enMark:SetPoint("BOTTOMRIGHT", enChk, "BOTTOMRIGHT", -3, 3)
  enChk:SetScript("OnClick", function()
    if seUI.ed then seUI.ed.enabled = not seUI.ed.enabled EVAL_HELP_SE_REFRESH() end
  end)
  seUI.enMark = enMark
  local enLabel = uiText(root, 9, 0.75, 0.75, 0.75)
  enLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 234, -27)
  enLabel:SetText(L("SE_ENABLE"))
  -- ★★★1.71.3 图例（用户要求「启用此技能 右侧添加几个图标 寓意 tooltip」）：
  --   白感叹号 = 不可用 / 黄感叹号 = 待测试；**意义只在悬停里**（用户要的就是这个）。
  --   ★★位置按「启用」标签的**实测宽度**推，不硬编码 x：英/俄语言包下窗口 800 宽、文案长得多，
  --     写死 x 会正好压在文字上（本项目「布局先用真实宽度算」的老教训；GetStringWidth 是 1.71.2 已在用的口径）。
  --     拿不到 GetStringWidth 时退化为「字符数 × 9px」（近似：中文一字约 9px）。
  local enW = 0
  if type(enLabel.GetStringWidth) == "function" then
    local okw, wv = pcall(enLabel.GetStringWidth, enLabel)
    if okw and type(wv) == "number" and wv > 0 then enW = wv end
  end
  if enW <= 0 then enW = math.floor(string.len(L("SE_ENABLE")) / 3 + 0.5) * 9 end
  local SE_MARK_X = 234 + enW + 14
  seUI.marks = {}
  -- ★文案写成**字面量** L("SE_MARK_...")（而不是 tkey="..." 运行时拼）：
  --   静态 LANG KEY CHECK 才扫得到这三语言 4 个键（运行时拼的键正是它扫不到的盲区）。
  local SE_MARK_DEFS = {
    { tex = SE_MARK_UNAVAIL, tip = function() return { L("SE_MARK_UNAVAIL_T"), L("SE_MARK_UNAVAIL_D") } end },
    { tex = SE_MARK_TEST,    tip = function() return { L("SE_MARK_TEST_T"),    L("SE_MARK_TEST_D") }    end },
  }
  for mi = 1, table.getn(SE_MARK_DEFS) do
    local md = SE_MARK_DEFS[mi]
    local mb = CreateFrame("Button", nil, root)
    mb:SetWidth(16) mb:SetHeight(16)
    mb:SetPoint("TOPLEFT", root, "TOPLEFT", SE_MARK_X + (mi - 1) * 20, -24)
    pcall(mb.EnableMouse, mb, true)
    local mt = mb:CreateTexture(nil, "ARTWORK")
    mt:SetWidth(12) mt:SetHeight(12)
    mt:SetPoint("CENTER", mb, "CENTER", 0, 0)
    pcall(mt.SetTexture, mt, md.tex)
    seHoverTip(mb, md.tip)
    seUI.marks[mi] = { btn = mb, tex = mt }
  end

  -- 条件表头
  local hd = uiText(root, 9, 0.60, 0.55, 0.40)
  hd:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -48)
  hd:SetText(L("SE_HEADER"))

  -- 8 行条件池
  for i = 1, 8 do
    local y = -64 - (i - 1) * 20
    local row = { all = {} }
    local function reg(w) table.insert(row.all, w) return w end
    row.conn = seBtn(root, 16, y, 26, 15, L("SE_WHEN"), function()
      local ed = seUI.ed
      if ed and i > 1 and ed.conds[i] then
        ed.conds[i].conn = (ed.conds[i].conn == "|") and "&" or "|"
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.conn.btn)
    row.typeBtn = seBtn(root, 46, y, 92, 15, L("SE_TYPE_PH"), function()
      -- 点开下拉列表：全部 26 种条件类型可见可选（1.14.0：替代盲循环；1.25.0 选取目标；1.26.0 目标职业；1.28.0 连击点数）
      local ed = seUI.ed
      local it = ed and ed.conds[i]
      if not it then return end
      -- 1.32.5 分组美化：金色组标题（idxMap=0 不可选）+ 四类分组；hidden 类型（选取目标）不进下拉
      local items, idxMap, tips, warns = {}, {}, {}, {}
      local anyWarn = false -- ★1.71.3 「待测试」类型 → 行右端挂**黄**感叹号
      -- ★★★1.71.3 条件类型**按技能行过滤**（用户要求）：这一行是成员选取器时，只提供「候选者状态」4 项——
      --   其余类型描述的是你自己/当前目标/技能本身，对「挑哪个队友」没有意义（选错就白配）。
      --   ★每次打开**现算**（换技能立刻跟着变）；已配好的旧行照旧显示、照旧能跑，只是下拉里不再提供。
      local pickerRow = seIsPickerRow(ed.skill) -- ★1.71.3 单一判据（与「添加条件」的初始类型同一份）
      if pickerRow then
        table.insert(items, "|cffff8080" .. L("SE_PICK_HINT") .. "|r")
        table.insert(idxMap, 0)
        -- ★提示行本身也带悬停说明（美化后的规则说明）
        -- ★★用**下标赋值**而不是 table.insert：insert(t, nil) 是 **no-op**，
        --   一旦某行不给提示就会让整张 tips 表错位（本轮实测踩到，与 1.71.3 类别图标那次同族）。
        tips[table.getn(items)] = { "|cffffd100" .. L("CTG_6") .. "|r", L("SE_TIP_PICK_HINT"),
                                    "|cff9fe0ff" .. L("SE_TIP_RULE") .. "|r" }
      end
      for _, grp in ipairs(SE_TYPE_GROUPS) do
        local isPickGrp = (grp.label == "CTG_6")
        if (pickerRow and isPickGrp) or ((not pickerRow) and (not isPickGrp)) then
          table.insert(items, "|cffffd100· " .. L(grp.label) .. " ·|r")
          table.insert(idxMap, 0)
          tips[table.getn(items)] = nil -- 组标题不给提示（显式赋值：insert(nil) 是 no-op，会错位）
          for _, id in ipairs(grp.ids) do
            local ti2 = SE_BY_K[id]
            if ti2 and not SE_TYPES[ti2].hidden then
              table.insert(items, L("CT_" .. string.upper(SE_TYPES[ti2].id)))
              table.insert(idxMap, ti2)
              tips[table.getn(items)] = seTypeTip(SE_TYPES[ti2].id)
              if SE_TODO_KINDS[SE_TYPES[ti2].id] then
                warns[table.getn(items)] = SE_MARK_TEST -- 黄=待测试（白那枚是「不可用」，不许混）
                anyWarn = true
              end
            end
          end
        end
      end
      EVAL_DD_OPEN(row.typeBtn.btn, items, function(ti0)
        local ti = idxMap[ti0]
        if not ti or ti == 0 then return end
        local old, new = it.cd, seDefaultCond(ti)
        if old.op and new.op then new.op, new.n = old.op, old.n end -- 同族参数保留
        local oldTd = SE_TYPES[seTypeIndexOf(old.k, old.name)]
        if old.s and new.s and oldTd and oldTd.kind == SE_TYPES[ti].kind then new.s = old.s end -- s 仅同族保留
        it.cd = new
        EVAL_HELP_SE_REFRESH()
      end, { tips = tips, warns = anyWarn and warns or nil })
    end)
    reg(row.typeBtn.btn)
    -- 数值参数：[比较符] [-] 值 [+]
    row.opBtn = seBtn(root, 142, y, 34, 15, ">", function()
      -- 比较符下拉（1.19.0：替代点按循环，可选项全可见）
      local it = seUI.ed and seUI.ed.conds[i]
      if not (it and it.cd.op) then return end
      EVAL_DD_OPEN(row.opBtn.btn, SE_OPS, function(oi)
        it.cd.op = SE_OPS[oi]
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.opBtn.btn)
    -- ★1.71.3 悬停说明：seHoverTip 已提到上面（与「启用」右侧图例共用同一份实现，见该处说明）。
    seHoverTip(row.typeBtn.btn, function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      return (it2 and it2.cd) and seTypeTip(it2.cd.k) or nil
    end)
    seHoverTip(row.opBtn.btn, function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if not (it2 and it2.cd and SE_TIP_RULE_KINDS[it2.cd.k]) then return nil end
      return { "|cffffd100" .. L("SE_TIP_RULE_T") .. "|r", L("SE_TIP_RULE") }
    end)
    -- 1.58.0 时间类型（秒）：步进 0.1、区间 0.0-10.0
    local SE_TIME_K = { swingLeft = true, castEl = true, castLeft = true, tCastEl = true, tCastLeft = true }
    row.minus = seBtn(root, 180, y, 20, 15, "-", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it and it.cd.n then
        if it.cd.k == "combo" then it.cd.n = math.max(1, it.cd.n - 1) -- 1.54.3 连击点数域 1-5（GetComboPoints 上限 5）
        elseif SE_TIME_K[it.cd.k] then it.cd.n = math.max(0, math.floor((it.cd.n - 0.1) * 10 + 0.5) / 10) -- 时间型 0.1 步进
        else it.cd.n = math.max(0, it.cd.n - 5) end
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.minus.btn)
    local vt = uiText(root, 9, 1, 0.9, 0.5)
    vt:SetPoint("TOPLEFT", root, "TOPLEFT", 204, y - 3)
    row.valText = vt
    reg(vt)
    row.plus = seBtn(root, 230, y, 20, 15, "+", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it and it.cd.n then
        if it.cd.k == "combo" then it.cd.n = math.min(5, it.cd.n + 1) -- 1.54.3 连击点数域 1-5
        elseif SE_TIME_K[it.cd.k] then it.cd.n = math.min(10, math.floor((it.cd.n + 0.1) * 10 + 0.5) / 10) -- 时间型 0.1 步进 上限 10.0
        else it.cd.n = math.min(300, it.cd.n + 5) end
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.plus.btn)
    -- 布尔/标志/姿态：是/否循环
    row.valBtn = seBtn(root, 142, y, 44, 15, L("SE_YES"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if it then
        local cd = it.cd
        local ti = seTypeIndexOf(cd.k, cd.name)
        local kind = SE_TYPES[ti].kind
        if kind == "bool" then cd.v = not cd.v
        elseif kind == "flag" then cd.inv = not cd.inv
        elseif kind == "form" then cd.k = (cd.k == "form") and "formNot" or "form" end
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.valBtn.btn)
    -- 姿态号下拉（1.19.0：替代 1/2/3 循环）
    -- 1.59.0 按角色实际姿态栏动态生成（GetNumShapeshiftForms + 名称；旧版硬编码 1/2/3，无姿态职业/德鲁伊对不上）
    row.formN = seBtn(root, 190, y, 30, 15, "1", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not (it and it.cd.n) then return end
      local items = {}
      if type(GetNumShapeshiftForms) == "function" then
        local okn, n = pcall(GetNumShapeshiftForms)
        if okn and n and n > 0 then
          for si = 1, n do
            local oki, _ic, nm = pcall(GetShapeshiftFormInfo, si)
            table.insert(items, tostring(si) .. ((oki and nm) and (" " .. nm) or ""))
          end
        end
      end
      if table.getn(items) == 0 then items = { "1" } end -- 无姿态栏职业兜底
      EVAL_DD_OPEN(row.formN.btn, items, function(ni)
        it.cd.n = ni -- onPick 传回序号=姿态栏索引
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.formN.btn)
    -- buff/debuff 技能名：显示 + [v] 下拉（1.19.0 移除 [<][>] 循环）
    local st2 = uiText(root, 9, 1, 0.9, 0.5)
    st2:SetPoint("TOPLEFT", root, "TOPLEFT", 142, y - 3)
    pcall(st2.SetWidth, st2, 100) -- 1.70.1 收窄：给右侧 是/否+层 让位
    row.skillText = st2
    reg(st2)
    -- ★★★1.71.2（第八轮）**还原**：条件行里的输入框改回纯文本**，输入改回面板内。
    --   用户原话：「这个功能还原，到输入框格保持在下拉内，并且支持打字过滤和自定义输入」。
    --   → 输入框回到**下拉面板内**（opts.search = true，见下方 sDrop 的 EVAL_DD_OPEN），
    --     本行只保留 FontString 做**显示**（点它仍然打开下拉，但不再聚焦打字）。
    --   ★为什么删掉 EditBox 而不是留着：它与这个 FontString **同坐标重叠**，
    --     留着就是两个显示体互相遮盖（本项目反复踩过「同坐标双控件」）；而且它的输入能力已由面板内搜索框取代。
    -- ★1.35.2 起：点击热区（透明 Button）—— 与文字 FontString 同坐标，负责接收点击。
    --   ★第七轮曾在这里与一个 EditBox（sBox）共存，而两者同坐标重叠 → 后建的 sHit 在上层，
    --   EditBox 拿不到焦点（那是当时的真 bug，已修）。
    --   ★★第八轮还原后 EditBox 已删，这里**只剩 sHit 一个点击体**，点一下就是开下拉。
    --   ★同坐标多控件的谁上谁下由**创建顺序**决定——这条教训保留（本项目反复踩过）。
    local sHit = CreateFrame("Button", nil, root)
    sHit:SetWidth(100) sHit:SetHeight(15)
    sHit:SetPoint("TOPLEFT", root, "TOPLEFT", 140, y)
    pcall(sHit.EnableMouse, sHit, true)
    pcall(sHit.RegisterForClicks, sHit, "LeftButtonUp")
    sHit:SetScript("OnEnter", function() pcall(st2.SetTextColor, st2, 1, 1, 0.85) end)
    sHit:SetScript("OnLeave", function() pcall(st2.SetTextColor, st2, 1, 0.9, 0.5) end)
    row.sHit = sHit
    reg(sHit)
    -- [v] 下拉：buff/debuff 技能名全列表（1.35.2 起按钮本体常驻隐藏，仅作处理器宿主）
    row.sDrop = seBtn(root, 246, y, 16, 15, "v", function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      local tdi = SE_TYPES[seTypeIndexOf(it.cd.k, it.cd.name)]
      if tdi and tdi.kind == "class" then
        -- 目标职业：多选下拉（或关系），点按切换 √ 不关面板（1.26.0）
        it.cd.cs = it.cd.cs or {}
        local items, sel = {}, {}
        for ci, c in ipairs(CLASS_LIST) do
          table.insert(items, c.name)
          if it.cd.cs[c.id] then sel[ci] = true end
        end
        EVAL_DD_OPEN(row.sHit, items, function(pi, on)
          it.cd.cs[CLASS_LIST[pi].id] = on or nil
          EVAL_HELP_SE_REFRESH()
        end, { multi = true, selected = sel })
        return
      end
      if tdi and tdi.kind == "creature" then
        -- 目标类型：多选（或关系），点按切换不关面板；首行显示客户端**此刻实际报告**的类型，
        -- 便于用户确认本客户端 UnitCreatureType 到底返回什么（该 API 曾被记为不可靠）
        it.cd.cs = it.cd.cs or {}
        local live = nil
        if type(UnitCreatureType) == "function" then
          local okc, tv = pcall(UnitCreatureType, "target")
          if okc and type(tv) == "string" and tv ~= "" then live = tv end
        end
        local items, sel, ids, lock = {}, {}, {}, {}
        if live then
          table.insert(items, "当前目标: " .. live) lock[1] = true
        end
        for _, c in ipairs(CREATURE_TYPES) do
          local i = table.getn(items) + 1
          table.insert(items, L("CRE_" .. string.upper(c.id)))
          table.insert(ids, c.id)
          if it.cd.cs[c.id] then sel[i] = true end
        end
        EVAL_DD_OPEN(row.sHit, items, function(pi, on)
          if lock[pi] then return end
          local id = ids[pi - (live and 1 or 0)]
          if not id then return end
          it.cd.cs[id] = on or nil
          EVAL_HELP_SE_REFRESH()
        end, { multi = true, selected = sel, locked = lock })
        return
      end
      if tdi and tdi.kind == "target" then
        -- 指定名称的名称下拉（1.29.0）：最近 5 敌名（循环枚举法）+ 自定义输入弹窗
        local function openNameDrop()
          local items = {}
          for _, n in ipairs(EVAL_NEARBY_ENEMY_NAMES(5)) do table.insert(items, n) end
          table.insert(items, "✎ 自定义名称…")
          local customIdx = table.getn(items)
          EVAL_DD_OPEN(row.sHit, items, function(pi)
            if pi >= customIdx then
              EVAL_TN_OPEN("指定目标名称（盲打看金色回声行）", it.cd.nm or "", function(nm)
                it.cd.nm = nm
                EVAL_HELP_SE_REFRESH()
              end)
            else
              it.cd.nm = items[pi]
              EVAL_HELP_SE_REFRESH()
            end
          end)
        end
        if it.cd.s == "byName" then
          openNameDrop() -- 已是指定名称：本下拉=选名称（换种类重选条件类型即可）
        else
          -- 选取目标：下拉官方 Targetting 函数种类（1.25.0 七种 + 1.29.0 目标的目标/指定名称）
          local items = {}
          for _, t in ipairs(TARGET_SEL) do table.insert(items, t.name) end
          EVAL_DD_OPEN(row.sHit, items, function(pi)
            it.cd.s = TARGET_SEL[pi].id
            EVAL_HELP_SE_REFRESH()
            if it.cd.s == "byName" then openNameDrop() end -- 选完种类立即选名称
          end)
        end
        return
      end
      -- ★1.70.28（用户要求「目标debuff 下拉信息优化，优先显示目标身上实时监测出来的debuff」）：
      --   顺序大改为 **实时光环在前、技能名在后**。旧实现把 EVAL_GO_SKILL_CHOICES()（动作条全部
      --   技能名）先 push，实时项再追加——下拉第一屏全是技能名，用户看到的正是「全是技能名称，
      --   不是 debuff 效果」，实时 debuff 被挤到下面翻不到。
      --   现在：① 实时项（◆/○/●/▲）置顶；② 已学习名 ◇ 次之；③ 其余技能名垫底（仍可选，
      --   但不再抢占视线）。三组之间插入不可点分隔行，让分类一眼可见。
      -- ★1.70.28 菜单结构抽到文件作用域 SE_AURA_MENU()：UI 与测试**共用同一份实现**。
      --   起因：我先前把顺序断言写成「测试里重新实现一遍顺序」，于是变异体（例如删掉实时分组标题）
      --   **测不出来**——测试看的是自己的副本，而不是真代码。抽成共用函数后变异立刻可见。
      local menu = SE_AURA_MENU(it.cd.k)
      local items, names, locked = menu.items, menu.names, menu.locked
      local icons = {}
      local anyIcon = false
      for i2, nm in ipairs(names) do
        local t = auraTexOf(nm)
        if t then icons[i2] = t anyIcon = true end
      end
      EVAL_DD_OPEN(row.sHit, items, function(pi)
        if locked[pi] then return end -- 分组标题行：不可选
        it.cd.s = names[pi]
        EVAL_HELP_SE_REFRESH()
      end, {
        icons = anyIcon and icons or nil, locked = locked,
        -- ★★★1.71.2（第八轮）用户要求**还原**：「这个功能还原，到输入框格保持在下拉内，
        --   并且支持打字过滤和自定义输入」。
        --   → 重新启用**面板内搜索框**：打字即过滤；自定义输入走 onFreeText（自由文本行）。
        --   ★★这不是把老 bug 请回来：该链路的两个历史问题修复**仍然全在**：
        --     ① 面板有**不透明背板**（挡住 EditBox 自带的黑底条）；
        --     ② 搜索框不用时靠**挪出可视区**（DD_SEARCH_PARK）而不是 Hide。
        search = true,
        onFreeText = function(txt)
          if txt == nil or txt == "" then return end
          it.cd.s = txt
          EVAL_HELP_SE_REFRESH()
        end,
      })
    end)
    row.sDrop.btn:Hide() -- 1.35.2 v 按钮常驻隐藏
    -- ★★★1.71.2（第八轮还原）点一下 = **只开下拉**（不再聚焦行内输入框——它已删）。
    --   输入改在**面板内的搜索框**（opts.search），面板一开就能直接打字过滤。
    --   ★旧的“合并两个行为”标记：那是因为行内 EditBox 需要聚焦；
    --     现在行内已回到纯文本，自然不需要聚焦这一步。
    sHit:SetScript("OnClick", function()
      local c = row.sDrop.btn:GetScript("OnClick")
      if c then c() end
    end)
    reg(row.sDrop.btn)
    -- 免疫条件的 免疫/未免疫 切换（1.36.3：kind=skill 共用参数区，仅 immune 类型显示）
    -- 1.36.4 修：此块 1.36.3 误嵌进 sDrop 调用中间，导致只在点击时才赋值（刷新时 immBtn nil 报错）
    row.immBtn = seBtn(root, 246, y, 40, 15, "", function() -- 1.70.1 布局：与「层」并排不重叠（旧 250 宽52 与 266 起宽20 的层按钮完全叠在一起→层覆盖是/否）
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      it.cd.v = (it.cd.v == false) and true or false
      EVAL_HELP_SE_REFRESH()
    end)
    reg(row.immBtn.btn)
    row.stk = seBtn(root, 290, y, 54, 15, L("SE_STK"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      local stkItems = { L("SE_STK_UNLIM") } for si = 2, 5 do table.insert(stkItems, L("SE_STK_FMT", si)) end
      EVAL_DD_OPEN(row.stk.btn, stkItems, function(pi)
        it.cd.n = (pi > 1) and pi or nil -- 序号2-5即层数2-5
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.stk.btn)
    -- ★1.70.45 剩余时间检查（仅自身 buff / 自身 debuff，判据见 seSecKinds）：
    --   [剩余▾] 选 不限 / < / <= / > / >=（复用比较符语义）；启用后出现 [-] [值] [+]
    --   单位秒、步进 1、区间 1-300（用户指定）。
    local SE_SEC_OPS = { "<", "<=", ">", ">=" }
    local secItems = {
      L("SE_SEC_UNLIM"), L("SE_SEC_FMT", "<"), L("SE_SEC_FMT", "<="),
      L("SE_SEC_FMT", ">"), L("SE_SEC_FMT", ">="),
    }
    row.secOp = seBtn(root, 348, y, 62, 15, L("SE_SEC_UNLIM"), function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if not it2 then return end
      EVAL_DD_OPEN(row.secOp.btn, secItems, function(pi)
        local cd = it2.cd
        if pi == 1 then
          cd.secOp, cd.secN = nil, nil -- 不限：彻底清掉，导出文本也就没有这段
        else
          cd.secOp = SE_SEC_OPS[pi - 1]
          if type(cd.secN) ~= "number" then cd.secN = 10 end -- 首次启用给个可用默认值
        end
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.secOp.btn)
    -- ★1.70.47 队伍debuff 的「可驱散类型」下拉（用户要求：debuff 检测增强扩展类型下拉 魔法/诅咒/毒等）。
    --   与 secOp **同一格 348/62**（两者按条件类型互斥显示：teamDebuff 用本钮、光环类用 secOp）。
    --   入库值是稳定英文 id（Magic/Curse/Poison/Disease/any），显示走 L("DS_T_*") 本地化——
    --   与 dispelMatch 的双向容忍配合：客户端返回本地化 token 也能匹配上。
    row.dtBtn = seBtn(root, 348, y, 62, 15, L("DS_T_ANY"), function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if not it2 then return end
      local dts = EVAL_DISPEL_TYPES or {}
      local items = { L("DS_T_ANY") }
      for _, t in ipairs(dts) do table.insert(items, L("DS_T_" .. string.upper(t.id))) end
      EVAL_DD_OPEN(row.dtBtn.btn, items, function(pi)
        local cd = it2.cd
        if pi == 1 then cd.dt = nil else cd.dt = dts[pi - 1].id end
        EVAL_HELP_SE_REFRESH()
      end)
    end)
    reg(row.dtBtn.btn)
    row.secMinus = seBtn(root, 414, y, 16, 15, "-", function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if it2 then
        seSecStep(it2.cd, -1) -- 步进 1，区间 1-300（共用函数，见 seSecStep）
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.secMinus.btn)
    local secTxt = uiText(root, 9, 1, 0.9, 0.5)
    secTxt:SetPoint("TOPLEFT", root, "TOPLEFT", 432, y - 3)
    pcall(secTxt.SetWidth, secTxt, 24)
    pcall(secTxt.SetJustifyH, secTxt, "LEFT")
    row.secText = secTxt
    reg(secTxt)
    row.secPlus = seBtn(root, 460, y, 16, 15, "+", function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if it2 then
        seSecStep(it2.cd, 1)
        EVAL_HELP_SE_REFRESH()
      end
    end)
    reg(row.secPlus.btn)
    -- ★★★1.71.3 队伍/团员条件的两个过滤格（用户要求）：
    --   ① 职业多选（8 项队伍/团员条件都有）；② 小队多选（只对**团员**条件，用户要求「先验证可行性」）。
    --   ★★语义与「目标职业」**正好相反**：空 = **不过滤**（用户原话「默认空不过滤职业.也就是全部」）。
    --   ★放在 484/544：这两格占的正是**行内预览**的位置 → 那 8 行改为不显示行内预览（让位），
    --     整行的完整条件在窗口底部的「预览:」里照旧能看到（那里才是唯一权威的整串显示）。
    row.clsBtn = seBtn(root, 484, y, 56, 15, L("SE_CLS_ALL"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      it.cd.cs = it.cd.cs or {}
      local items, sel = {}, {}
      for ci, c in ipairs(CLASS_LIST) do
        table.insert(items, c.name)
        if it.cd.cs[c.id] then sel[ci] = true end
      end
      EVAL_DD_OPEN(row.clsBtn.btn, items, function(pi, on)
        it.cd.cs[CLASS_LIST[pi].id] = on or nil
        EVAL_HELP_SE_REFRESH()
      end, { multi = true, selected = sel })
    end)
    reg(row.clsBtn.btn)
    row.grpBtn = seBtn(root, 544, y, 56, 15, L("SE_GRP_ALL"), function()
      local it = seUI.ed and seUI.ed.conds[i]
      if not it then return end
      it.cd.gs = it.cd.gs or {}
      local items, sel = {}, {}
      for gi = 1, 8 do
        table.insert(items, string.format(L("SE_GRP_FMT"), gi))
        if it.cd.gs[gi] then sel[gi] = true end
      end
      EVAL_DD_OPEN(row.grpBtn.btn, items, function(pi, on)
        it.cd.gs[pi] = on or nil
        EVAL_HELP_SE_REFRESH()
      end, { multi = true, selected = sel })
    end)
    reg(row.grpBtn.btn)
    seHoverTip(row.clsBtn.btn, function() return { "|cffffd100" .. L("SE_TIP_MEMCLS_T") .. "|r", L("SE_TIP_MEMCLS_D") } end)
    seHoverTip(row.grpBtn.btn, function() return { "|cffffd100" .. L("SE_TIP_MEMGRP_T") .. "|r", L("SE_TIP_MEMGRP_D") } end)
    -- 结果预览 + 删除
    local pv = uiText(root, 9, 0.55, 0.75, 0.55)
    pv:SetPoint("TOPLEFT", root, "TOPLEFT", 484, y - 3) -- 1.70.45 右移给「剩余时间」让位（原 348）
    row.preview = pv
    reg(pv)
    row.del = seBtn(root, W - 50, y, 28, 15, L("W_DEL"), function() -- 1.70.45 右缘锚定（原 420 固定）
      local ed = seUI.ed
      if ed and ed.conds[i] then table.remove(ed.conds, i) EVAL_HELP_SE_REFRESH() end
    end)
    reg(row.del.btn)
    seUI.rows[i] = row
  end

  -- 添加条件 + 预览 + 保存/取消
  local addW = seBtn(root, 16, -64 - 8 * 20 - 6, 96, 16, L("SE_ADD"), function()
    local ed = seUI.ed
    if ed and table.getn(ed.conds) < 8 then
      -- ★1.71.3 初始类型按**这一行的过滤表**选（用户要求「添加初始值从过滤条件内选」）
      table.insert(ed.conds, { conn = (table.getn(ed.conds) > 0) and "&" or nil, cd = seDefaultCond(seRowFirstType(ed.skill)) })
      EVAL_HELP_SE_REFRESH()
    end
  end)
  seUI.addBtn = addW.btn -- ★1.71.3 断言要能点**真实按钮**（走它自己的 OnClick 闭包）
  -- 1.36.2 预览挪到 [+添加条件] 右侧同行（原在底部与 保存/取消 按钮重叠）
  local pvLabel = uiText(root, 9, 0.60, 0.55, 0.40)
  pvLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 122, -64 - 8 * 20 - 9)
  pvLabel:SetText(L("SE_PREVIEW"))
  local pv = uiText(root, 9, 0.95, 0.82, 0.35)
  pv:SetPoint("TOPLEFT", root, "TOPLEFT", 158, -64 - 8 * 20 - 9)
  pcall(pv.SetWidth, pv, 300)
  pcall(pv.SetJustifyH, pv, "LEFT")
  seUI.preview = pv
  local function bBtn(x, w, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(22)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 12)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
  end
  bBtn(W - 182, 80, L("SE_SAVE"), function() EVAL_HELP_SE_SAVE() end) -- 1.70.45 右对齐（同配置窗观感）
  bBtn(W - 92, 80, L("BTN_CANCEL"), function() root:Hide() end) -- 1.70.45 右对齐
  root:Hide()
  root:SetScript("OnHide", function() EVAL_DD_HIDE() end)
  seUI.root = root
end

-- ★1.70.45 测试直调：剩余时间检查的共用判据 / 步进函数（UI 用的就是这两个）
function EVAL_TEST_SE_SEC_KINDS(k) return seSecKinds(k) end
function EVAL_TEST_SE_SEC_STEP(cd, delta) seSecStep(cd, delta) return cd and cd.secN end

-- ★1.70.46 测试直调：往编辑器里塞一条条件并跑**真实的**编辑器刷新。
--   存在理由＝一次真实事故：seSecKinds 曾被声明在 EVAL_HELP_SE_REFRESH **之后**，
--   于是 SE_REFRESH 里调用它时绑到**全局 nil** → 用户一点「自身buff检查」就红字报错
--   （attempt to call global 'seSecKinds' (a nil value)）。
--   ★而当时的测试**只断言了判定函数本身**（EVAL_TEST_SE_SEC_KINDS），
--   **调用点从未被执行** → 测试全绿、用户一点就炸。这是本项目第 4 次「只测解析函数、不测接线」。
function EVAL_TEST_SE_PUSH_COND(kind, name, op, n, dt, scope)
  if not seUI.root then EVAL_HELP_SE_OPEN(1) end
  if not seUI.root then return nil end
  if not seUI.ed then seUI.ed = { profIdx = 1, skillIdx = nil, skill = "测试技能", conds = {} } end
  seUI.ed.skill = seUI.ed.skill or "测试技能"
  -- ★1.70.47 scope：队伍/团队扫描范围（cd.name）——省略时按「队伍」，与真编辑器默认一致
  seUI.ed.conds = { { cd = { k = kind, s = name, v = true, secOp = op, secN = n, dt = dt, name = scope } } }
  EVAL_HELP_SE_REFRESH() -- 生产刷新路径（就是出事故的那条路）
  return true
end
-- 行首「条件类型」按钮的真实文案（1.70.47）：用来验证「团队debuff」这类标签真的渲染出来，
--   而不是只在 SE_TYPES 表里存在（表里有、界面上没有 = 用户看不到这个功能）。
function EVAL_TEST_SE_ROW_TYPE(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.typeBtn) then return nil end
  local ok, t = pcall(row.typeBtn.text.GetText, row.typeBtn.text)
  return ok and t or nil
end
-- 队伍debuff 的「类型」下拉控件（1.70.47）：可见性 + 显示文案（问真实控件）
function EVAL_TEST_SE_ROW_DT(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.dtBtn) then return nil, nil end
  local okS, s = pcall(row.dtBtn.btn.IsShown, row.dtBtn.btn)
  local okT, t = pcall(row.dtBtn.text.GetText, row.dtBtn.text)
  return (okS and s) and true or false, okT and t or nil
end
-- ★1.71.3 断言入口：队伍/团员条件的两个过滤格（职业 / 小队）——可见性 + 显示文案（问真实控件）
function EVAL_TEST_SE_ROW_CLS(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.clsBtn) then return nil, nil end
  local okS, s = pcall(row.clsBtn.btn.IsShown, row.clsBtn.btn)
  local okT, t = pcall(row.clsBtn.text.GetText, row.clsBtn.text)
  return (okS and s) and true or false, okT and t or nil
end
function EVAL_TEST_SE_ROW_GRP(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.grpBtn) then return nil, nil end
  local okS, s = pcall(row.grpBtn.btn.IsShown, row.grpBtn.btn)
  local okT, t = pcall(row.grpBtn.text.GetText, row.grpBtn.text)
  return (okS and s) and true or false, okT and t or nil
end
function EVAL_TEST_SE_ROW_PREVIEW(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.preview) then return false end
  local okS, s = pcall(row.preview.IsShown, row.preview)
  return (okS and s) and true or false
end
function EVAL_TEST_SE_ROW_CLS_BTN(i)
  local row = seUI.rows and seUI.rows[i]
  return (row and row.clsBtn and row.clsBtn.btn) or nil
end
function EVAL_TEST_SE_ROW_GRP_BTN(i)
  local row = seUI.rows and seUI.rows[i]
  return (row and row.grpBtn and row.grpBtn.btn) or nil
end
-- 行内「剩余时间」控件的可见性与文案（问真实控件，不问常量）
-- ★★★1.71.2（第八轮还原）**行内输入框已删**，输入回到面板内。
--   所以原来那批「行内输入框」钩子（ROW_BOX / BOX_TEXT / BOX_FOCUSED / TYPE_AURA / PRESS_ENTER / KW）
--   **全部删除**：它们指向的控件已不存在，留着只会让断言误判。
--   ★新断言改用**面板内搜索框**的现成钩子：EVAL_DD_TEST_SEARCH_VISIBLE / SEARCH_IN_PANEL /
--     TYPE_SEARCH / FILTERED_COUNT / HAS_FREE_ROW（全部问**真实控件**）。
-- ★保留：模拟点击那一格（走 sHit 的**真实 OnClick**）—— 现在它应该**只开下拉**。
function EVAL_TEST_SE_CLICK_CELL(i)
  local r = seUI and seUI.rows and seUI.rows[i]
  if not (r and r.sHit) then return false end
  local ok, fn = pcall(r.sHit.GetScript, r.sHit, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
-- ★读该行当前的光环名（cd.s）——验「自定义输入提交」用
function EVAL_TEST_SE_AURA_NAME(i)
  local ed = seUI and seUI.ed
  local it = ed and ed.conds and ed.conds[i]
  return it and it.cd and it.cd.s or nil
end
-- ★1.71.3 断言入口：读该行条件的**数据侧**类型 id（与显示侧的 ROW_TYPE 各钉一半——
--   「数据对了但没显示出来」与「显示了但数据不对」是两回事，本项目两边都栽过）
function EVAL_TEST_SE_COND_K(i)
  local ed = seUI and seUI.ed
  local it = ed and ed.conds and ed.conds[i]
  return it and it.cd and it.cd.k or nil
end
function EVAL_TEST_SE_SKILL() -- ★1.71.3 编辑器当前技能名（验「名字落值」用）
  return (seUI and seUI.ed and seUI.ed.skill) or nil
end
function EVAL_TEST_SE_COND_COUNT()
  local ed = seUI and seUI.ed
  return (ed and ed.conds and table.getn(ed.conds)) or 0
end
-- ★点**面板内的自由文本行**（✎ 开头）—— 验「列表里没有就用自己输入的名字」这条能力。
--   ★为什么要走真实 OnClick：直接调 onFreeText 会绕过「面板真的渲染出了这一行」，
--     而那正是用户能不能用这个功能的前提。
function EVAL_TEST_SE_DD_CLICK_FREE()
  if not ddUI.rows then return false end
  for _, row in ipairs(ddUI.rows) do
    if row.btn and row.btn:IsShown() and row.text then
      local t = row.text:GetText() or ""
      if string.find(t, "✎", 1, true) then
        local fn = row.btn:GetScript("OnClick")
        if fn then fn() return true end
      end
    end
  end
  return false
end

-- ★1.71.2（第十三轮）点**真实的条件类型按钮**（走它自己的 OnClick 闭包）→ 打开类型下拉。
--   为什么必须走真实 OnClick：行池上限这类 bug **只在真实构建路径上**才暴露，
--   测试自己拼一份 items 是测不出来的（本项目多次栽在「只测函数不测调用点」）。
-- ★1.71.3 点**真实的分类下拉按钮**（走它自己的 OnClick 闭包）→ 打开类别下拉。
--   为什么必须走真实按钮：本轮的图标/标记都是「调用点接线」，测试自己拼 opts 测不出来（老教训）。
function EVAL_TEST_SE_CLICK_CAT()
  if not (seUI and seUI.catBtn) then return false end
  local ok, fn = pcall(seUI.catBtn.GetScript, seUI.catBtn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
-- ★1.71.3 类别图标：读**生产代码**给的字段（不在测试里另写一份映射）
function EVAL_TEST_SE_CAT_ICONS()
  local cats = EVAL_GO_SKILL_CATEGORIES()
  local out = {}
  for i = 1, table.getn(cats) do out[i] = cats[i].icon end
  return out
end
-- ★1.71.3 悬停说明的断言入口：类型格 / 比较符格的**真实按钮**（要验接线就必须走它们的 OnEnter）
function EVAL_TEST_SE_TYPE_BTN(i)
  local r = seUI and seUI.rows and seUI.rows[i]
  return (r and r.typeBtn and r.typeBtn.btn) or nil
end
function EVAL_TEST_SE_OP_BTN(i)
  local r = seUI and seUI.rows and seUI.rows[i]
  return (r and r.opBtn and r.opBtn.btn) or nil
end
-- ★1.71.3 断言入口：「添加条件」的**真实按钮**（要验初始类型就必须走真实 OnClick——本项目老判据）
function EVAL_TEST_SE_CLICK_ADD()
  local b = seUI and seUI.addBtn
  if not (b and type(b.GetScript) == "function") then return false end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
-- ★1.71.3 断言入口：状态标记图例 —— 读**真实控件**上的贴图与位置（不是 opts 传参：
--   读传参只证明「传了什么」，证明不了「画成了什么」，本项目 UI ICON 那条的老判据）
function EVAL_TEST_SE_MARK_ICONS()
  local out = {}
  local ms = seUI and seUI.marks
  if type(ms) ~= "table" then return out end
  for i = 1, table.getn(ms) do
    local m = ms[i]
    local rec = { tex = nil, x = nil, y = nil, w = nil }
    if m and m.tex then
      local okt, t = pcall(m.tex.GetTexture, m.tex)
      rec.tex = okt and t or nil
      local okw, wv = pcall(m.tex.GetWidth, m.tex)
      rec.w = okw and wv or nil
    end
    if m and m.btn then
      local okx, xv = pcall(m.btn.GetLeft, m.btn)
      rec.x = okx and xv or nil
      local oky, yv = pcall(m.btn.GetTop, m.btn)
      rec.y = oky and yv or nil
    end
    out[i] = rec
  end
  return out
end
-- ★1.71.3 断言入口：图例按钮本体（悬停断言必须走**真实 OnEnter**）
function EVAL_TEST_SE_MARK_BTN(i)
  local m = seUI and seUI.marks and seUI.marks[i]
  return (m and m.btn) or nil
end
function EVAL_TEST_SE_CLICK_TYPE(i)
  local r = seUI and seUI.rows and seUI.rows[i]
  if not (r and r.typeBtn and r.typeBtn.btn) then return false end
  local ok, fn = pcall(r.typeBtn.btn.GetScript, r.typeBtn.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
-- ★行池上限（供断言直接读，不写死数字）
function EVAL_TEST_DD_MAX_ROWS() return DD_MAX_ROWS end
-- ★条件类型菜单**总共需要多少行**（真实遍历 SE_TYPE_GROUPS，不在测试里重算）
function EVAL_TEST_SE_TYPE_MENU_ROWS()
  local rows = 0
  for _, grp in ipairs(SE_TYPE_GROUPS) do
    rows = rows + 1 -- 组标题
    for _, id in ipairs(grp.ids) do
      local ti2 = SE_BY_K[id]
      if ti2 and not SE_TYPES[ti2].hidden then rows = rows + 1 end
    end
  end
  return rows
end
function EVAL_TEST_SE_ROW_SEC(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.secOp) then return nil, nil end
  local okS, s = pcall(row.secOp.btn.IsShown, row.secOp.btn)
  local okT, t = pcall(row.secOp.text.GetText, row.secOp.text)
  return (okS and s) and true or false, okT and t or nil
end
-- 点行内**真实按钮**（走它自己的 OnClick 闭包），而不是直接调 seSecStep——
-- 直接调共用函数会漏掉「按钮闭包根本没接上」这类接线错误（本项目已栽过数次）。
function EVAL_TEST_SE_CLICK_SEC(i, plus)
  local row = seUI.rows and seUI.rows[i]
  if not row then return nil end
  local b = nil
  if plus and row.secPlus then b = row.secPlus.btn
  elseif (not plus) and row.secMinus then b = row.secMinus.btn end
  if not b then return nil end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if not (ok and type(fn) == "function") then return nil end
  fn()
  return true
end
function EVAL_TEST_SE_SECN(i)
  local ed = seUI.ed
  if not (ed and ed.conds and ed.conds[i]) then return nil end
  return ed.conds[i].cd.secN
end
-- 收尾：清掉编辑器状态，避免把测试条件留给后面的用例（模块级状态必须自己收）
-- ★1.70.46 测试直调：全部**对用户可见**的条件类型 key。
--   供「每种条件都跑一遍真实刷新」的遍历断言用：
--   seSecKinds 那次事故只发生在 hasBuff 这一条分支里——只挑一个 kind 测是抓不到的。
function EVAL_TEST_SE_KINDS()
  local out = {}
  for _, td in ipairs(SE_TYPES) do
    if not td.hidden then table.insert(out, td.id) end
  end
  return out
end
-- ★1.70.47 测试直调：条件类型下拉**真正会列出的条目**（与 SE_BUILD 里构建 items 的逻辑同一份来源）。
--   用户明确要求「条件类型里要有 队伍buff / 队伍debuff / 团队buff / 团队debuff」——
--   只断言 SE_TYPES 表里有这几个 id 是不够的（表里有、下拉没列 = 用户根本选不到），
--   所以这里复刻的是**下拉入口那一份**遍历，并让测试核对本地化后的标签。
-- ★1.70.47 测试直调：模拟「在下拉里选中某个条件类型」→ 返回它生成的条件（走真实 seDefaultCond）。
--   用途：验证选「团队debuff」得到的是 **{k=teamDebuff, name=团队}**——
--   即「界面上选团队那一条」与「引擎按团队范围扫描」确实是同一件事（两侧接不上就白做）。
function EVAL_TEST_SE_DEFAULT_COND(typeId)
  local ti = SE_BY_K[typeId]
  if not ti then return nil end
  return seDefaultCond(ti)
end
function EVAL_TEST_SE_TYPE_MENU()
  local out = {}
  for _, grp in ipairs(SE_TYPE_GROUPS) do
    table.insert(out, L(grp.label))
    for _, id in ipairs(grp.ids) do
      local ti = SE_BY_K[id]
      if ti and not SE_TYPES[ti].hidden then table.insert(out, L("CT_" .. string.upper(SE_TYPES[ti].id))) end
    end
  end
  return out
end
-- ★1.71.2 断言专用：按**组标签**取真实分组表的 id 列表（返回副本，测试改不动生产表）。
--   ★为什么按 label 而不按下标：有人调整组的先后时，下标就会悄悄指错组。
--     但调用侧**必须同时断言「取到的不是 nil」**——否则 label 打错会让「不在该组」类断言恒真。
-- ★1.71.2 断言专用：条件类型菜单里每个条目所用的**语言包键**（按菜单顺序，跳过 hidden）。
--   存在理由：这些键是**运行时拼出来的**（"CT_" .. string.upper(id)），静态 LANG KEY CHECK
--   只扫源码里的 L("字面量")，**扫不到它们** → 「某语言缺键」「某语言两条同名」都只能在运行时逐语言核对。
function EVAL_TEST_SE_TYPE_LABEL_KEYS()
  local out = {}
  for _, grp in ipairs(SE_TYPE_GROUPS) do
    for _, id in ipairs(grp.ids) do
      local ti = SE_BY_K[id]
      if ti and not SE_TYPES[ti].hidden then table.insert(out, "CT_" .. string.upper(SE_TYPES[ti].id)) end
    end
  end
  return out
end
function EVAL_TEST_SE_TYPE_GROUP_IDS(label)
  for _, grp in ipairs(SE_TYPE_GROUPS) do
    if grp.label == label then
      local out = {}
      for _, v in ipairs(grp.ids) do table.insert(out, v) end
      return out
    end
  end
  return nil
end
function EVAL_TEST_SE_CLEAR()
  if seUI.root then pcall(seUI.root.Hide, seUI.root) end
  seUI.ed = nil
  return true
end

-- ★1.70.45 测试直调：窗口宽度三方对照（来源函数 / 配置窗实际 / 编辑窗实际）。
--   三者必须一致——「一个宽度两处各写一份」正是本项目反复踩的那类坑。
function EVAL_TEST_WIN_W()
  return cfWinWidth(), cfgWin.W, seUI.W
end

-- ★1.70.46 测试直调：两个自建窗的**实际尺寸**（不是构建期记录的常量，而是问帧本身）。
--   为什么要问帧：`SetHeight(H)` 曾被同一行的行尾注释吞掉，而两个窗口的宽度都正常，
--   于是「宽度对照」三条断言全绿、窗口却高得离谱。断言必须直接问帧要真实尺寸。
function EVAL_TEST_SE_SIZE()
  local r = seUI.root
  if not r then return nil, nil end
  local okw, w = pcall(r.GetWidth, r)
  local okh, h = pcall(r.GetHeight, r)
  return (okw and type(w) == "number") and w or nil, (okh and type(h) == "number") and h or nil
end
-- ★1.71.2 暴露配置窗**生产代码实际使用的布局值**（开关组 y / 按钮行 y / 项高）。
--   用途：断言必须验「生产代码真的把开关组下移了」——
--   测试自己写一份 -389 只能证明测试自己写了 -389（本轮变异实测：生产改回 -349 照样绿）。
-- ★1.71.2 暴露「全局 → 日志」分组的行（key + y + 读写器）。
--   用途：断言要验「方案技能日志开关**真的在日志组里**（而不是只从旧位置删了），
--   且仍读写同一个 cfg.wdebug」—— 只扫源码文本拿不到这两件事。
function EVAL_TEST_CFG_LOG_ROWS()
  local cw = EVAL_HELP_CFGWIN
  return cw and cw.logRows or nil
end

function EVAL_TEST_CFG_LAYOUT()
  local cw = EVAL_HELP_CFGWIN
  return cw and cw.layout or nil
end

function EVAL_TEST_CFG_SIZE()
  local cw = EVAL_HELP_CFGWIN
  local r = cw and cw.root
  if not r then return nil, nil end
  local okw, w = pcall(r.GetWidth, r)
  local okh, h = pcall(r.GetHeight, r)
  return (okw and type(w) == "number") and w or nil, (okh and type(h) == "number") and h or nil
end

function EVAL_HELP_SE_SAVE()
  local ed = seUI.ed
  if not ed then return end
  local w2 = warCfg()
  local p = w2.profiles[ed.profIdx]
  if not p then if seUI.root then seUI.root:Hide() end return end
  local groups = seLinearToGroups(ed.conds)
  if ed.skillIdx and p.skills[ed.skillIdx] then
    local r = p.skills[ed.skillIdx]
    r.skill = ed.skill
    r.enabled = ed.enabled
    r.groups = groups
    say("已保存技能: " .. tostring(ed.skill) .. " → " .. uiEsc(EVAL_GROUP_STR(groups)))
  else
    -- 1.33.0 取消 8 技能上限（配置窗列表支持滚动）
    table.insert(p.skills, { skill = ed.skill, enabled = ed.enabled, groups = groups, why = ed.skill })
    say("已添加技能: " .. tostring(ed.skill) .. " → " .. uiEsc(EVAL_GROUP_STR(groups)))
  end
  pcall(EVAL_WAR_TAB_REFRESH)
  if seUI.root then seUI.root:Hide() end
end

-- 打开编辑窗：skillIdx=nil 表示新增（presetSkill 预选技能）
function EVAL_HELP_SE_OPEN(profIdx, skillIdx, presetSkill)
  SE_BUILD()
  local w2 = warCfg()
  local p = w2.profiles[profIdx]
  if not p then return end
  local ed = { profIdx = profIdx, skillIdx = skillIdx }
  if skillIdx and p.skills[skillIdx] then
    local r = p.skills[skillIdx]
    ed.skill = r.skill
    ed.enabled = r.enabled ~= false
    ed.conds = seGroupsToLinear(r.groups)
  else
    ed.skill = presetSkill or "攻击" -- 1.48.0 白名单已删，兜底用「攻击」
    ed.enabled = true
    ed.conds = {}
  end
  seUI.ed = ed
  EVAL_HELP_SE_REFRESH()
  seUI.root:Show()
end

-- ============ 方案 导入/导出（md 文本互转，复制粘贴快速分享） ============
-- 存储/交换格式（与案例模版库 EVAL_IO_TEMPLATES 同格式；1.48.0 起 example/zs_wq.md 已删，模版在游戏内）：
--   # 方案: 武器战
--   - 压制 | 怒气>5 & 可用 & 就绪
--   - !猛击 | Alt & 怒气>20        （技能名前 ! = 该技能停用）
-- 解析容忍 markdown 杂物：# 开头 = 方案名，> 或 < 开头/超长行忽略，无 | 的行忽略。

local ioUI = { root = nil, eb = nil }
local tplUI = { root = nil } -- 1.44.0 案例模版选单

-- 案例模版库（1.44.0）：**数据已移出本文件**，改放 examples/ 下按职业分文件（见 EvalHelp.toc 的载入顺序）。
--   为什么拆：本文件已经很大，而模版是纯数据（改模版不该动引擎代码）。
--   为什么是「.lua 文件 + 列进 .toc」而不是「运行时读 .md」：本客户端**没有文件读取 API**
--   （Lua 沙箱里没有 io/os），插件读不了自己的目录 → 唯一受支持的「从文件载入」就是
--   把文件列进 .toc，让客户端把它当 Lua 模块加载。所以 examples/ 下每个文件都是
--   **可直接编辑的 Lua 数据文件**，里面的模版文本与导入导出格式完全一致（md）。
--   顺序 = .toc 里的顺序 = 模版选单里的顺序（EXAMPLES TOC CHECK 守着两者一致）。
--   本行只是兜底初始化（万一 examples 没被列进 toc，选单至少是空表而不是 nil 崩掉）；
--   它**不是**数据源——数据只在 examples/*.lua 里 append（同一个东西不能有两份真值）。
EVAL_IO_TEMPLATES = EVAL_IO_TEMPLATES or {}

-- 文本导入共用入口（1.44.0 抽出）：导入按钮与案例模版同走；成功返回 true+提示
-- ★★★1.71.2 导入成功后**必须在本函数内刷新方案列表**（用户实测：「点击分享触发导入之后，
--   导入完成，方案列表未能及时显示」）。
--   根因：原来「刷新界面」这件事交给**每个调用点自己记得调**——IO 窗的导入按钮调了
--   EVAL_WAR_TAB_REFRESH，而 Share.lua 的分享弹窗 [导入]**没调** → 数据已进 profiles，
--   配置窗列表却还是旧的（要切 Tab 或重开才出现）。
--   ★判据：**「数据变了」与「界面更新」是同一件事，必须在同一个地方做**——
--     把刷新放在写入点（本函数）而不是散落在各调用点，调用点就再也不可能漏。
--     （与本项目「A 产出配置、B 消费配置，两边都要断言」是同一类问题。）
local function ioImportText(text)
  local prof, err = EVAL_PROFILE_FROM_TEXT(text)
  if not prof then return false, "导入失败: " .. tostring(err) end
  local w2 = warCfg()
  local msg
  if table.getn(w2.profiles) < 12 then -- 1.44.0 修正：方案上限 1.42.0 已 4→12，此处残留旧值
    table.insert(w2.profiles, prof)
    w2.activeProfile = table.getn(w2.profiles)
    msg = "已导入为新方案: " .. tostring(prof.name) .. "（" .. table.getn(prof.skills) .. " 个技能）"
  else
    w2.profiles[w2.activeProfile or 1] = prof
    msg = "方案已满 12 个，已替换当前方案: " .. tostring(prof.name)
  end
  -- ★刷新方案列表（配置窗「一键宏设置」页）。pcall 包裹：分享弹窗可能在配置窗**从未建过**
  --   的情况下导入，此时刷新函数内部会自行 return，绝不能因此打断导入结果。
  if type(EVAL_WAR_TAB_REFRESH) == "function" then pcall(EVAL_WAR_TAB_REFRESH) end
  return true, msg
end

EVAL_IMPORT_TEXT = ioImportText -- 1.69.0 桥：Share.lua 方案分享弹窗的 [导入] 走这里

-- 方案 → md 文本（导出）
function EVAL_PROFILE_TO_TEXT(idx)
  local w2 = warCfg()
  -- ★1.71.2（第二十二轮）idx 也接受方案表本身（原先只认下标）：
  --   模版库的往返断言要验「导出(解析(文本)) == 文本」；不这样就只能把它塞进真实 profiles 再取回来，
  --   那会动到用户的方案列表（测试不该为了断言改数据）。
  --   向后兼容：现有调用传的是 nil 或数字，行为完全不变。
  local p = (type(idx) == "table") and idx or w2.profiles[idx or (w2.activeProfile or 1)]
  if not p then return "" end
  local lines = {}
  table.insert(lines, "# 方案: " .. tostring(p.name))
  table.insert(lines, "")
  for _, r in ipairs(p.skills or {}) do
    local dis = (r.enabled == false) and "!" or ""
    table.insert(lines, "- " .. dis .. tostring(r.skill) .. " | " .. EVAL_GROUP_STR(r.groups))
  end
  return table.concat(lines, "\n")
end

-- md 文本 → 方案表（导入）；失败返回 nil+原因
function EVAL_PROFILE_FROM_TEXT(text)
  if type(text) ~= "string" then return nil, "无文本" end
  text = string.gsub(text, "\r\n", "\n")
  text = string.gsub(text, "\r", "\n")
  local name, skills = nil, {}
  for line in string.gmatch(text .. "\n", "(.-)\n") do
    local l = EVAL_COND_TRIM(line)
    local nm = string.match(colonNorm(l), "^#%s*方案[:：]%s*(.+)$") or string.match(l, "^#%s*(.+)$") -- ★1.71.3 归一后才认全角冒号
    if nm then
      name = EVAL_COND_TRIM(nm)
    elseif string.sub(l, 1, 1) ~= ">" and string.sub(l, 1, 1) ~= "<" and l ~= "" then
      local body = string.match(l, "^[-*]%s*(.+)$") or l
      local sn, conds = string.match(body, "^([^|]+)|(.*)$")
      -- ★1.70.43 无条件技能行（如「- 宠物:攻击」）此前**被静默丢弃**：上面那条 Lua 模式里的
      --   竖线是**字面量**（Lua 模式没有 | 交替语义），所以「行内必须有竖线」是隐含要求。
      --   导出侧（EVAL_PROFILE_TO_TEXT）总是补一个竖线，故「自家导出→导入」不受影响；
      --   但**手写模版/手工粘贴**里漏写竖线，那一行就无声消失——正是本项目反复记的
      --   「不报错的空操作」。这里补一条兜底：没有竖线 ⇒ 视为「技能名 + 空条件」。
      if not sn then sn, conds = body, "" end
      if sn then
        sn = condTrim(sn)
        local enabled = true
        if string.sub(sn, 1, 1) == "!" then enabled = false sn = condTrim(string.sub(sn, 2)) end
        -- 技能名合理性守卫：超长按说明文字处理。1.56.1 上限 24→48 字节（16 汉字）——
        -- 带前缀技能名更长：选取目标:指定名称:嗜血者=39B、物品:弱效巨魔之血药水=36B，旧 24B 上限会把它们静默丢行
        if sn ~= "" and string.len(sn) <= 48 then
          table.insert(skills, { skill = sn, enabled = enabled, groups = EVAL_PARSE_CONDS(conds or ""), why = sn })
        end
      end
    end
  end
  if table.getn(skills) == 0 then return nil, "没解析到技能行（格式: - 技能名 | 条件）" end
  return { name = name or "导入方案", skills = skills } -- 1.33.0 取消 8 技能上限
end

function EVAL_HELP_IO_BUILD()
  if ioUI.root then return end
  -- ★1.71.2 宽度 470 → 560：用户截图里「分享/接收」被挤到第二排、又被路径提示压住。
  --   底部要排 **6 个**按钮（导入/导出/案例模版/分享/接收/关闭）——按等宽 82 + 8 间距算，
  --   470 宽最多放下 4 个，硬塞必然换行或互相压字。
  --   ★判据（本轮定）：**窗口宽度要由「最宽那一行的控件总宽」反推**，不能先定宽再往里塞。
  --   ★1.71.2 第三轮：案例模版/分享/接收已移到配置窗方案列表底部 → 底部只剩 3 个按钮
  --     （等宽 82 + 间距 8 = 262px），「6 个按钮需要 546」这条加宽依据消失 → 宽度回 **470**。
  local W, H = 470, 350
  local root = CreateFrame("Frame", "EVAL_HELP_IO", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  -- 同 1.11.2：抬到 DIALOG 同级 + 高 frameLevel，避免被配置窗（DIALOG）盖住
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 90)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  -- 标题栏拖动（Button 配方）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(16)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10) end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("IO_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- 操作说明
  local tip = uiText(root, 9, 0.75, 0.75, 0.75)
  tip:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -26)
  tip:SetText(L("IO_TIP"))

  -- 多行输入框（1.15.1：字体对象优先；本客户端 EditBox 可能不渲染，下方有保底预览区）
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_IO_EB", root)
  if okEb and eb then
    pcall(eb.SetMultiLine, eb, true)
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    -- 1.32.8 编辑区尺寸修正：EditBox 装进 ScrollFrame 精确裁剪到可视框（ebBg 内缩），
    -- 不再溢出盖住说明行/预览区；超高文本自动滚到底部。ScrollFrame 不可用时回退旧直挂布局。
    local okSF, sf = pcall(CreateFrame, "ScrollFrame", "EVAL_HELP_IO_SF", root)
    if okSF and sf and pcall(sf.SetScrollChild, sf, eb) then
      sf:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -40)
      sf:SetWidth(W - 32) sf:SetHeight(136)
      eb:SetPoint("TOPLEFT", sf, "TOPLEFT", 4, -2)
      eb:SetWidth(W - 48) eb:SetHeight(132)
      eb:SetScript("OnTextChanged", function()
        pcall(sf.UpdateScrollChildRect, sf)
        local okr, range = pcall(sf.GetVerticalScrollRange, sf)
        if okr and type(range) == "number" then pcall(sf.SetVerticalScroll, sf, range) end
      end)
      ioUI.sf = sf
    else
      eb:SetWidth(W - 40) eb:SetHeight(128)
      eb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -44)
    end
    local setF = false
    for _, fo in ipairs({ "GameFontHighlightSmall", "ChatFontNormal", "GameFontNormal" }) do
      if pcall(eb.SetFontObject, eb, fo) then setF = true break end
    end
    if not setF then
      for _, fp in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        local okF, ok2 = pcall(eb.SetFont, eb, fp, 10, "")
        if okF and ok2 then setF = true break end
      end
    end
    if not setF then pcall(eb.SetTextHeight, eb, 10) end
    pcall(eb.SetTextColor, eb, 1, 1, 1)
    local ebBg = root:CreateTexture(nil, "BACKGROUND")
    uiSolid(ebBg, 0.10, 0.09, 0.06, 1)
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -38)
    ebBg:SetWidth(W - 28) ebBg:SetHeight(140)
    local ebEdge = root:CreateTexture(nil, "BORDER")
    uiSolid(ebEdge, 0.85, 0.70, 0.20, 0.8)
    ebEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -38)
    ebEdge:SetWidth(W - 28) ebEdge:SetHeight(1)
    eb:SetScript("OnEscapePressed", function() pcall(eb.ClearFocus, eb) end)
    ioUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -44)
    noEb:SetText(L("IO_NOEB"))
  end

  -- 保底预览区：当前方案文本以 FontString 渲染（EditBox 不显示时也始终可见）
  local pvLabel = uiText(root, 9, 0.95, 0.82, 0.35)
  pvLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -184)
  pvLabel:SetText(L("IO_PV"))
  ioUI.pvLines = {}
  for i = 1, 8 do
    local ln = uiText(root, 9, 0.82, 0.82, 0.82)
    ln:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -196 - (i - 1) * 12)
    pcall(ln.SetWidth, ln, W - 40)
    pcall(ln.SetJustifyH, ln, "LEFT")
    ioUI.pvLines[i] = ln
  end

  -- 配置文件位置提示（1.20.2：EditBox 不可复制时的兜底——方案自动存盘，小退后文件即最新）
  local pathTip = uiText(root, 8, 0.55, 0.55, 0.55)
  pathTip:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -288)
  pcall(pathTip.SetWidth, pathTip, W - 28)
  pcall(pathTip.SetJustifyH, pathTip, "LEFT")
  pathTip:SetText(L("IO_PATH1"))
  local pathTip2 = uiText(root, 8, 0.68, 0.62, 0.30)
  pathTip2:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -300)
  pcall(pathTip2.SetWidth, pathTip2, W - 28)
  pcall(pathTip2.SetJustifyH, pathTip2, "LEFT")
  pathTip2:SetText("%LOCALAPPDATA%\\Azeroth\\Saved\\Account\\<你的账号>\\SavedVariables\\EVAL_HELP.lua")

  -- ★1.71.2 底部按钮统一走「一行等宽」布局（原来是各处硬编码 x/宽度 → 换语言就压字）。
  --   IO_GAP/IO_BW 是**单一来源**：所有按钮共用，改一个数整行自动重排。
  local IO_BW, IO_GAP, IO_PAD = 82, 8, 14
  -- 底部按钮行
  local function ioBtn(x, w, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w) b:SetHeight(24)
    b:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", x, 14)
    pcall(b.EnableMouse, b, true)
    pcall(b.RegisterForClicks, b, "LeftButtonUp")
    local bb = b:CreateTexture(nil, "BACKGROUND")
    uiSolid(bb, 0.22, 0.18, 0.10, 1)
    bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    local bt = uiText(b, 10, 0.95, 0.82, 0.35)
    bt:SetPoint("CENTER", b, "CENTER", 0, 0)
    -- ★1.71.2 显式限宽 + 禁止折行：FontString 不限宽时宽度由内容决定，
    --   换语言/改文案就会溢出压到相邻按钮（本项目既有铁律，底部这排是 6 个挨着的最容易中招）。
    pcall(bt.SetWidth, bt, w - 6)
    pcall(bt.SetNonSpaceWrap, bt, false)
    bt:SetText(label)
    b:SetScript("OnClick", fn)
    -- ★1.71.2 登记到 ioUI.btns：供断言检查「同一行 / 不重叠 / 不超出窗口」
    --   （否则「按钮排成两行」这种布局问题只能靠人眼看截图，正是本轮的起因）
    if not ioUI.btns then ioUI.btns = {} end
    table.insert(ioUI.btns, { btn = b, x = x, w = w, label = label, text = bt })
    return b
  end
  -- 按钮 x 一律由 IO_PAD + 序号 × (IO_BW + IO_GAP) 推出（单一来源，不写死坐标）
  local _bx = { [1] = IO_PAD, [2] = IO_PAD + (IO_BW + IO_GAP), [3] = IO_PAD + 2 * (IO_BW + IO_GAP),
                [4] = IO_PAD + 3 * (IO_BW + IO_GAP), [5] = IO_PAD + 4 * (IO_BW + IO_GAP),
                [6] = IO_PAD + 5 * (IO_BW + IO_GAP) }
  ioBtn(_bx[1], IO_BW, L("IO_IMPORT"), function()
    local text = ""
    if ioUI.eb then
      local ok, t = pcall(ioUI.eb.GetText, ioUI.eb)
      if ok and type(t) == "string" then text = t end
    end
    local ok, msg = ioImportText(text) -- 1.44.0 共用导入（含方案上限 12 修正）
    say(msg)
    if ok then pcall(EVAL_WAR_TAB_REFRESH) ioUI.root:Hide() end
  end)
  ioBtn(_bx[2], IO_BW, L("IO_EXPORT"), function()
    if ioUI.eb then
      pcall(ioUI.eb.SetText, ioUI.eb, EVAL_PROFILE_TO_TEXT())
      pcall(ioUI.eb.SetFocus, ioUI.eb)
      pcall(ioUI.eb.HighlightText, ioUI.eb)
    end
    EVAL_HELP_IO_REFRESH()
    say("已导出到输入框并全选：Ctrl+C 复制，存成 .md 即可分享（输入框不显示就看下方预览区）")
  end)
  -- ★★★1.71.2 用户要求（第三轮）：「导入导出内的**案例模版、分享、分享接收开关删除**，
  --   移动到外部方案列表底部」。
  --   所以这里**不再创建**那三个按钮；导入导出窗只保留：导入为新方案 / 导出当前方案 / 关闭。
  --   ★按钮序号保持 [1]导入 / [2]导出 / [3]关闭（连续，不留空洞）。
  ioBtn(_bx[3], IO_BW, L("CLOSE"), function() ioUI.root:Hide() end)

  -- 1.44.0 IO 窗关闭时模版选单联动关闭
  root:SetScript("OnHide", function() if tplUI.root then tplUI.root:Hide() end end)
  root:Hide()
  ioUI.root = root
end

-- ★1.71.2 测试钩子：IO 窗底部按钮行的几何（同一行判定 / 重叠 / 越界）
function EVAL_TEST_IO_BUTTONS()
  local out = {}
  for _, e in ipairs(ioUI.btns or {}) do
    -- ★x/w 取**登记值**（布局输入）——这才是「排布算得对不对」这条性质本身。
    --   为什么不取 GetPoint：测试桩不做锚点解算，对 5 参 SetPoint 调用回的偏移量不可靠
    --   （本轮实测：登记 x=14、GetPoint 却回 0）→ 直接用它会产生**假失败**。
    --   ★py 另外单独取（用于「有没有按钮被事后搬到别的行」），拿不到时置 nil 由断言侧处理。
    local ok, p, _, _, ox, oy = pcall(e.btn.GetPoint, e.btn, 1)
    local textW = nil
    if e.text then
      local okt, tw = pcall(e.text.GetWidth, e.text)
      if okt and type(tw) == "number" then textW = tw end
    end
    out[table.getn(out) + 1] = {
      label = e.label or "", x = e.x, w = e.w,
      point = ok and p or nil, px = ox,
      py = (ok and type(oy) == "number") and oy or nil,
      textW = textW,
      -- ★1.71.2 暴露按钮本体：断言要验「每个按钮真的有 OnClick」（防止留空壳凑数），
      --   只给标签与几何做不到这件事。
      btn = e.btn,
    }
  end
  return out
end
-- ★1.71.2 从**实际锚点**数底部按钮占了几行（拿不到锚点时按布局输入视为 1 行）。
--   用途：抓住「某个按钮被事后 ClearAllPoints + SetPoint 挪到第二排」这个形态
--   ——它正是用户截图里的原始问题（分享/接收当初单独排在 BOTTOM 42）。
function EVAL_TEST_IO_ROW_COUNT()
  local ys = {}
  for _, e in ipairs(ioUI.btns or {}) do
    local ok, _, _, _, _, oy = pcall(e.btn.GetPoint, e.btn, 1)
    if ok and type(oy) == "number" then ys[oy] = true end
  end
  local n = 0
  for _ in pairs(ys) do n = n + 1 end
  if n == 0 then return 1 end
  return n
end
function EVAL_TEST_IO_WIDTH()
  local ok, w = pcall(ioUI.root.GetWidth, ioUI.root)
  return (ok and type(w) == "number") and w or nil
end

-- ★1.71.2（第十七轮）断言专用：导入导出窗**当前是否可见**。
--   用途：验「某个按钮**不该**把它弹出来」——这类需求必须**点一下真实按钮**再看状态，
--   只 grep 源码里有没有那行调用抓不到「调用点接线」（本项目反复栽在这上面）。
-- ★1.71.2（第二十轮）断言专用：战斗信息 UI 每条状态条的真实几何
--   （填充层的内缩偏移/高度 + 所在条的宽高 + 满值时的宽度上限）。
--   本轮需求「生命条看着有阴影」= 填充层内缩 1px 露出的近黑底，是**纯几何**问题，只能读真实数值。
--   ★为什么要读「父帧」：偏移是相对条的，只验「偏移=0」证明不了「高度等于条高 / 满值不留缝」。
--   ★桩的纹理必须能 GetParent（本轮已补，见 test_stub.lua）。
function EVAL_TEST_UI_BAR_GEOM()
  local out = {}
  local spec = {
    { "hp", ui.hpFill, ui.hpW }, { "power", ui.pwFill, ui.pwW }, { "target", ui.tgFill, ui.tgW },
    { "cast", ui.castFill, ui.castW }, { "swing", ui.swingFill, ui.swingW },
  }
  for _, it in ipairs(spec) do
    local fill, maxW = it[2], it[3]
    local e = { name = it[1], maxW = maxW }
    if fill then
      local okp, _, _, _, ox, oy = pcall(fill.GetPoint, fill, 1)
      if okp then e.x, e.y = ox, oy end
      local okh, hh = pcall(fill.GetHeight, fill)
      if okh and type(hh) == "number" then e.fillH = hh end
      local okg, par = pcall(fill.GetParent, fill)
      if okg and type(par) == "table" then
        local okw2, ww = pcall(par.GetWidth, par)
        local okh2, hh2 = pcall(par.GetHeight, par)
        if okw2 and type(ww) == "number" then e.barW = ww end
        if okh2 and type(hh2) == "number" then e.barH = hh2 end
      end
    end
    table.insert(out, e)
  end
  return out
end
function EVAL_TEST_IO_SHOWN()
  if not ioUI.root then return false end
  local ok, v = pcall(ioUI.root.IsVisible, ioUI.root)
  return (ok and v) and true or false
end

-- ★★★1.71.10 断言入口：战斗信息UI「方案切换行」的**真实几何**（每格的位置/宽度 + 生产算出的「需要宽度」）。
--   要验的性质：① 每格宽 ≥ 它自己需要的宽（用户报的「方案溢出宽度」就是这个）；
--   ② 同行相邻不重叠、整行不越出可用宽；③ 长名字的格子真的比短名字宽（不是均分）；
--   ④ 方案块整体在帧内（行数变了帧高要跟着变）。
function EVAL_TEST_UI_SHOWN() 
  if not ui or not ui.root then return false end
  local ok, v = pcall(ui.root.IsVisible, ui.root)
  return (ok and v) and true or false
end
function EVAL_TEST_UI_PROF()
  if not ui or not ui.profBtns then return nil end
  local function num(f, o)
    local ok, v = pcall(f, o)
    return (ok and type(v) == "number") and v or nil
  end
  local okw, ww = pcall(ui.root.GetWidth, ui.root)
  local okh, hh = pcall(ui.root.GetHeight, ui.root)
  local out = { rows = ui.profRows or 0, avail = ui.profAvail or 0, pad = ui.profPad or 0, cap = ui.profCap or 0,
    need = ui.profNeed, rootW = (okw and ww) or nil, rootH = (okh and hh) or nil, btns = {} }
  for i, pb in ipairs(ui.profBtns) do
    local okT, txt = pcall(pb.text.GetText, pb.text)
    local oks, sh = pcall(pb.btn.IsShown, pb.btn)
    out.btns[i] = {
      btn = pb.btn, -- 1.71.16 交出真实控件（右键绑定的断言要真的点它）
      name = (okT and tostring(txt or "")) or "",
      shown = (oks and sh) and true or false,
      x = num(pb.btn.GetLeft, pb.btn), y = num(pb.btn.GetTop, pb.btn),
      w = num(pb.btn.GetWidth, pb.btn), h = num(pb.btn.GetHeight, pb.btn),
      textW = num(pb.text.GetWidth, pb.text), -- 文字格自身的宽（限宽后应 ≤ 按钮宽）
      need = ui.profNeed and ui.profNeed[i] or nil,
    }
  end
  return out
end

-- ★★★1.71.12 断言入口：两个子开关（战斗 / 方案）的**真实生效结果**——
--   刻意读 `ui.combatOn/schemeOn`（BUILD 时定下）+ 控件的**存在性**，而不是回读配置：
--   配置写了什么与「这一轮到底建没建」是两件事（本项目「配置产出/消费两边都要断言」的判据）。
--   另附标题文本与帧宽高（标题 = 玩家名、帧高要随子开关变化）。
function EVAL_TEST_UI_SECTIONS()
  local out = { combat = false, scheme = false, hasCombat = false, hasScheme = false,
    title = nil, rootW = nil, rootH = nil }
  if not ui then return out end
  out.combat = ui.combatOn and true or false
  out.scheme = ui.schemeOn and true or false
  out.hasCombat = (ui.hpFill ~= nil) and true or false
  out.hasScheme = (ui.profBtns ~= nil) and true or false
  if ui.title then
    local okt, t = pcall(ui.title.GetText, ui.title)
    out.title = (okt and tostring(t or "")) or nil
  end
  if ui.root then
    local okw, w = pcall(ui.root.GetWidth, ui.root)
    out.rootW = (okw and type(w) == "number") and w or nil
    local okh, h = pcall(ui.root.GetHeight, ui.root)
    out.rootH = (okh and type(h) == "number") and h or nil
  end
  return out
end

-- ============ 案例模版选单（1.44.0）：按职业分组，点击方案行直接导入 ============
-- ★★★1.71.8 案例模版窗的**版式计算**（纯函数：不建控件、不碰 UI）——用户要求：
--   「案例模版 分组 分两列, 分组内的方案 同行 自动换行.」
--   ① 窗口按列宽一分为二：colW = (W - 2*margin - colGap) / 2（窄到放不下两列时退化单列，不硬撑）；
--   ② **组是不拆的最小单位**：按顺序切成「左段 / 右段」，一个组绝不会跨到另一列（拆开看着像少了一组）；
--   ③ **组内流式**：标题后跟本组按钮，同一行依次往右排、放不下就换行回**本列**左边界；
--      每个组从新的一行开始（否则两组会挤在同一行，看着像一组）；
--   ④ 切点 = **两列行数差最小**（遍历所有切点）——★别用「塞到过半就停」的贪心：
--      它在当前数据上看着对，内容一改就失衡（1.71.5 的教训）。
--   ★★为什么是纯函数：布局的核心（分列 + 换行）埋在 BUILD 里就只能用真实模版数据测，
--     而真实内容下「不换行 / 只排一列」都可能是**等价**的 → 必须能用**合成数据**逼它换行、逼它分列。
--   返回 plan, 最末一行 y, 左列行数, 右列行数, 列宽, 右列左边界 x
local function tplTwoColPlan(W, groups, measure, margin, gap, rowH, colGap)
  local colW = math.floor((W - margin * 2 - colGap) / 2)
  if colW < 60 then colW = W - margin * 2 end -- 窗口太窄：退化成单列（硬分两列会把按钮压成一条）
  local colX = { margin, margin + colW + colGap }
  local colMax = { colX[1] + colW, colX[2] + colW }
  local n = table.getn(groups)
  -- ① 一个组在**本列列宽**下要占几行（组内同行 + 自动换行）
  local function rowsOf(c)
    local lw = measure("【" .. tostring(c.cls) .. "】")
    local px, rows = colX[1] + lw + gap, 1
    for _, p in ipairs(c.list) do
      local bw = measure(tostring(p.name)) + 16
      if bw > colW then bw = colW end
      if px + bw > colMax[1] + 0.5 then rows = rows + 1 px = colX[1] end
      px = px + bw + gap
    end
    return rows
  end
  -- ② 最优切点（两列行数差最小；组不拆）
  local rows, total = {}, 0
  for i = 1, n do rows[i] = rowsOf(groups[i]) total = total + rows[i] end
  local cut = n
  if n >= 2 then
    local best = nil
    for k = 1, n - 1 do
      local a = 0
      for i = 1, k do a = a + rows[i] end
      local diff = math.abs(a - (total - a))
      if best == nil or diff < best then best, cut = diff, k end
    end
  end
  -- ③ 照切点摆两列：每组从新行开始，标题在**本列行首**，组内同行自动换行
  local plan, minY = {}, -26
  local used = { 0, 0 }
  for ci = 1, 2 do
    local py, first = -26, true
    for i = 1, n do
      if (ci == 1 and i <= cut) or (ci == 2 and i > cut) then
        local c = groups[i]
        local x0, mx = colX[ci], colMax[ci]
        if not first then py = py - rowH end
        first = false
        used[ci] = used[ci] + rows[i]
        local lw = measure("【" .. tostring(c.cls) .. "】")
        table.insert(plan, { kind = "header", cls = c.cls, x = x0, y = py, w = lw })
        local px = x0 + lw + gap
        for _, p in ipairs(c.list) do
          local bw = measure(tostring(p.name)) + 16
          if bw > colW then bw = colW end
          if px + bw > mx + 0.5 then px = x0 py = py - rowH end
          table.insert(plan, { kind = "item", cls = c.cls, tpl = p, x = px, y = py, w = bw })
          px = px + bw + gap
        end
        if py < minY then minY = py end
      end
    end
  end
  return plan, minY, used[1], used[2], colW, colX[2]
end

function EVAL_HELP_TPL_BUILD()
  if tplUI.root then return end
  -- ★★★1.71.3 用户要求「窗口大一点、分两列」：案例多了以后单列会长出屏幕（本客户端 UI 空间高 768）。
  --   ★宽度跟配置窗**同一来源**（cfWinWidth：中文 660 / 西文 800）——不再各写一份宽度（本项目老坑）。
  local W = cfWinWidth()
  local MARGIN, GAP, ROW_H, COL_GAP = 14, 6, 20, 12 -- COL_GAP = 两列之间的间隔（1.71.8 分两列）
  -- ★★★1.71.5 版式：**流式（自动换行）布局**（用户要求：「模版不用一列，可以同行，自动换行布局」）。
  --   · 组标题与方案按钮**一起**从左往右排，放不下就换行（回到左边界）——不再「每行一个 / 每列一组」。
  --   · 每个按钮宽度 = FontString:GetStringWidth() **实测** + 内边距（拿不到就按「字符数 × 9px」近似）。
  --   · 版式先算成一张 plan 表（位置**单一来源**），再照它建控件；断言读的仍是**真实控件几何**。
  local H = 0 -- 高度由 plan 算出来（量完标签再 SetHeight）
  tplUI.rowBtns = {}
  tplUI.headerFs = {}
  tplUI.margin, tplUI.gap, tplUI.rowH, tplUI.colGap = MARGIN, GAP, ROW_H, COL_GAP
  local root = CreateFrame("Frame", "EVAL_HELP_TPL", UIParent)
  root:SetWidth(W) -- ★高度见下方「算完版式再 SetHeight」（本窗高度由内容决定）
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 95) -- 高于 IO 窗（90）
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  if uiOffscreen(root) then
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0)
    t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0)
    t:SetHeight(1)
  end
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER")
    uiSolid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. side, root, "TOP" .. side, 0, 0)
    t:SetPoint("BOTTOM" .. side, root, "BOTTOM" .. side, 0, 0)
    t:SetWidth(1)
  end
  -- 标题栏拖动（Button 配方）
  local titleBar = CreateFrame("Button", nil, root)
  titleBar:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -1)
  titleBar:SetPoint("TOPRIGHT", root, "TOPRIGHT", -1, -1)
  titleBar:SetHeight(16)
  local okLvl, rootLvl = pcall(root.GetFrameLevel, root)
  if okLvl and type(rootLvl) == "number" then pcall(titleBar.SetFrameLevel, titleBar, rootLvl + 10) end
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.16, 0.13, 0.08, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  title:SetText(L("TPL_TITLE"))
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- ★★★1.71.3 用户要求：标题上加个感叹号，悬停提示「有好方案欢迎分享」。
  --   ★★用**金色文字感叹号**，不用我们那两枚 mark 图标：那两枚的含义已经固定（白=不可用 / 黄=待测试），
  --     同一张图再表示「欢迎分享」= 含义叠加，用户会误判（「图标语义单一来源」那条）。
  local tipBtn = CreateFrame("Button", nil, titleBar)
  tipBtn:SetWidth(14) tipBtn:SetHeight(14)
  tipBtn:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
  pcall(tipBtn.EnableMouse, tipBtn, true)
  local tipTxt = uiText(tipBtn, 12, 0.95, 0.82, 0.35)
  tipTxt:SetPoint("CENTER", tipBtn, "CENTER", 0, 0)
  tipTxt:SetText("!")
  tipBtn:SetScript("OnEnter", function()
    pcall(tipTxt.SetTextColor, tipTxt, 1, 1, 1)
    if type(GameTooltip) == "nil" then return end
    pcall(GameTooltip.SetOwner, GameTooltip, tipBtn, "ANCHOR_LEFT")
    pcall(GameTooltip.AddLine, GameTooltip, L("TPL_SHARE_TIP"))
    pcall(GameTooltip.Show, GameTooltip)
  end)
  tipBtn:SetScript("OnLeave", function()
    pcall(tipTxt.SetTextColor, tipTxt, 0.95, 0.82, 0.35)
    if type(GameTooltip) ~= "nil" then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  tplUI.tipBtn = tipBtn
  tplUI.tipText = tipTxt

  -- ★★★1.71.5 **流式（自动换行）布局**（用户要求：「模版不用一列，可以同行，自动换行布局」）：
  --   ① 先算 plan（位置单一来源）：组标题与按钮**同一行里依次往右排**，放不下就换行回左边界；
  --      ★标题不许「孤零零留在行尾」——要求「标题 + 该组第一个按钮」能一起放下，否则先换行。
  --   ② 再照 plan 建控件（渲染只读 plan，位置不会两处各算一遍而漂移）。
  local ruler = uiText(root, 9, 0.88, 0.88, 0.88)
  pcall(ruler.SetPoint, ruler, "TOPLEFT", root, "TOPLEFT", -2000, 0) -- 量宽用的「尺」：挪出可视区（本客户端 Hide 过的控件仍可能被绘出）
  local function measure(label)
    local w = 0
    pcall(ruler.SetText, ruler, label)
    if type(ruler.GetStringWidth) == "function" then
      local okv, v = pcall(ruler.GetStringWidth, ruler)
      if okv and type(v) == "number" and v > 0 then w = v end
    end
    if w <= 0 then w = math.floor(string.len(label) / 3 + 0.5) * 9 end -- 近似：中文一字约 9px
    return w
  end
  -- 版式交给**纯函数**算（见 tplTwoColPlan 上方注释：分列与换行两条路都要能被合成数据逼出来）
  local plan, lastY, rowsL, rowsR, colW, colX2 = tplTwoColPlan(W, EVAL_IO_TEMPLATES, measure, MARGIN, GAP, ROW_H, COL_GAP)
  H = 34 + math.abs(lastY) + ROW_H + 20 -- 34 标题栏 + 内容 + 底部关闭按钮
  root:SetHeight(H)
  tplUI.plan = plan
  -- 两列的几何与行数（渲染不再重复算；断言读的也是这一份）
  tplUI.colW, tplUI.colX2 = colW, colX2
  tplUI.rowsL, tplUI.rowsR = rowsL, rowsR
  tplUI.lines = (rowsL > rowsR) and rowsL or rowsR
  for _, e in ipairs(plan) do
    if e.kind == "header" then
      local hd = uiText(root, 10, 0.95, 0.82, 0.35)
      hd:SetPoint("TOPLEFT", root, "TOPLEFT", e.x, e.y)
      hd:SetText("【" .. tostring(e.cls) .. "】")
      table.insert(tplUI.headerFs, { cls = tostring(e.cls), fs = hd })
    else
      local p = e.tpl
      local b = CreateFrame("Button", nil, root)
      b:SetPoint("TOPLEFT", root, "TOPLEFT", e.x, e.y)
      b:SetWidth(e.w) b:SetHeight(18)
      pcall(b.EnableMouse, b, true)
      pcall(b.RegisterForClicks, b, "LeftButtonUp")
      local bb = b:CreateTexture(nil, "BACKGROUND")
      uiSolid(bb, 0.12, 0.10, 0.06, 1)
      bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
      local bt = uiText(b, 9, 0.88, 0.88, 0.88)
      bt:SetPoint("CENTER", b, "CENTER", 0, 0)
      pcall(bt.SetWidth, bt, e.w - 8) -- 实测宽度留的内边距足够；超长名仍裁掉（tooltip 里有全名）
      pcall(bt.SetNonSpaceWrap, bt, false)
      bt:SetText(tostring(p.name)) -- 1.67.6 行内只留模版名；描述+方案内容移入 tooltip
      table.insert(tplUI.rowBtns, { name = tostring(p.name), cls = tostring(e.cls), btn = b })
      b:SetScript("OnEnter", function()
        pcall(bb.SetVertexColor, bb, 0.30, 0.25, 0.12, 1)
        pcall(function()
          GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
          GameTooltip:AddLine(tostring(p.name), 1, 0.85, 0.3)
          if p.desc then GameTooltip:AddLine(tostring(p.desc), 0.85, 0.85, 0.85, true) end
          for ln2 in string.gmatch(tostring(p.text or ""), "([^\n]+)") do
            if string.sub(ln2, 1, 1) == "-" then GameTooltip:AddLine(ln2, 0.65, 0.65, 0.65, true) end -- 技能行预览
          end
          GameTooltip:Show()
        end)
      end)
      b:SetScript("OnLeave", function()
        pcall(bb.SetVertexColor, bb, 0.12, 0.10, 0.06, 1)
        pcall(GameTooltip.Hide, GameTooltip)
      end)
      b:SetScript("OnClick", function()
        local ok, msg = ioImportText(p.text)
        say(msg)
        if ok then
          pcall(EVAL_WAR_TAB_REFRESH)
          EVAL_HELP_IO_REFRESH()
          root:Hide()
        end
      end)
    end
  end

  -- 关闭按钮（居中底部）
  local cb = CreateFrame("Button", nil, root)
  cb:SetWidth(64) cb:SetHeight(20)
  cb:SetPoint("BOTTOM", root, "BOTTOM", 0, 7)
  pcall(cb.EnableMouse, cb, true)
  pcall(cb.RegisterForClicks, cb, "LeftButtonUp")
  local cbb = cb:CreateTexture(nil, "BACKGROUND")
  uiSolid(cbb, 0.22, 0.18, 0.10, 1)
  cbb:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
  cbb:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
  local cbt = uiText(cb, 10, 0.95, 0.82, 0.35)
  cbt:SetPoint("CENTER", cb, "CENTER", 0, 0)
  cbt:SetText(L("CLOSE"))
  cb:SetScript("OnClick", function() root:Hide() end)

  root:Hide()
  tplUI.root = root
end

-- ★1.71.3 断言入口：案例模版窗（两列布局 + 标题感叹号）——读**真实控件**的几何与文案，
--   不在测试里写死布局常量（本项目「断言里写死常量 = 测自己」的老坑）。
function EVAL_TEST_TPL_LAYOUT()
  EVAL_HELP_TPL_BUILD()
  if not tplUI.root then return nil end
  local r = tplUI.root
  local okw, w = pcall(r.GetWidth, r)
  local okh, h = pcall(r.GetHeight, r)
  return {
    w = okw and w or nil, h = okh and h or nil,
    margin = tplUI.margin, gap = tplUI.gap, rowH = tplUI.rowH, colGap = tplUI.colGap,
    colW = tplUI.colW, colX2 = tplUI.colX2,
    rowsL = tplUI.rowsL or 0, rowsR = tplUI.rowsR or 0,
    lines = tplUI.lines or 0, plan = table.getn(tplUI.plan or {}),
    rowCount = table.getn(tplUI.rowBtns or {}),
    groups = table.getn(EVAL_IO_TEMPLATES or {}),
  }
end
function EVAL_TEST_TPL_ROWS()
  EVAL_HELP_TPL_BUILD()
  local out = {}
  for i, e in ipairs(tplUI.rowBtns or {}) do
    local okx, x = pcall(e.btn.GetLeft, e.btn)
    local oky, y = pcall(e.btn.GetTop, e.btn)
    local okw, w2 = pcall(e.btn.GetWidth, e.btn)
    out[i] = { name = e.name, cls = e.cls, x = okx and x or nil, y = oky and y or nil, w = okw and w2 or nil }
  end
  return out
end
function EVAL_TEST_TPL_HEADERS()
  EVAL_HELP_TPL_BUILD()
  local out = {}
  for i, e in ipairs(tplUI.headerFs or {}) do
    local okx, x = pcall(e.fs.GetLeft, e.fs)
    local oky, y = pcall(e.fs.GetTop, e.fs)
    out[i] = { cls = e.cls, x = okx and x or nil, y = oky and y or nil }
  end
  return out
end
-- ★★★1.71.8 断言入口：用**合成数据**逼版式函数的「组内换行」与「分两列」两条路
--   （真实内容下这两条路可能是等价的 —— 见 tplTwoColPlan 注释）。
--   参数：w 窗宽 / gn 组数 / per 每组按钮数 / chars 每个按钮名的字数；量宽用纯函数（中文一字约 9px）。
--   返回 { items, groups, rows, perCol, colGroups, over, gapBad, colStartBad, splitBad, balance, colW, colX2 }
function EVAL_TEST_TPL_PLAN_FAKE(w, gn, per, chars)
  local FAKE_CLS = string.char(0xe5, 0x81, 0x87) .. string.char(0xe7, 0xbb, 0x84) -- 合成组名（不写字面量：它会被当模版数据哨兵）
  local groups = {}
  for i = 1, gn do
    local list = {}
    for j = 1, per do
      table.insert(list, { name = string.rep("字", chars) .. tostring(i) .. "-" .. tostring(j) })
    end
    table.insert(groups, { cls = FAKE_CLS .. tostring(i), list = list })
  end
  local measure = function(s) return string.len(s) / 3 * 9 end
  local plan, _lastY, rowsL, rowsR, colW, colX2 = tplTwoColPlan(w, groups, measure, 14, 6, 20, 12)
  local colMax = { 14 + colW, colX2 + colW }
  local function colOf(x) return (x >= colX2 - 0.5) and 2 or 1 end
  local byRow = {}
  for _, e in ipairs(plan) do
    local key = tostring(e.y) .. "#" .. tostring(colOf(e.x))
    byRow[key] = byRow[key] or {}
    table.insert(byRow[key], e)
  end
  local items, rows, over, gapBad, colStartBad = 0, 0, 0, 0, 0
  local perCol, colGroups = { 0, 0 }, { {}, {} }
  for _, list in pairs(byRow) do
    rows = rows + 1
    table.sort(list, function(a, b) return a.x < b.x end)
    for i = 1, table.getn(list) do
      local e = list[i]
      local ci = colOf(e.x)
      if e.kind == "item" then items = items + 1 perCol[ci] = perCol[ci] + 1 end
      colGroups[ci][tostring(e.cls)] = true
      if e.x + e.w > colMax[ci] + 1 then over = over + 1 end -- 越出**本列**右边界
      local x0 = (ci == 1) and 14 or colX2
      if e.kind == "header" and math.abs(e.x - x0) > 0.5 then colStartBad = colStartBad + 1 end
      if i > 1 then
        local prev = list[i - 1]
        if colOf(prev.x) == ci and e.x < prev.x + prev.w + 6 - 0.5 then gapBad = gapBad + 1 end
      end
    end
  end
  local splitBad, g1, g2 = 0, 0, 0
  for _, c in ipairs(groups) do
    local seen = 0
    for ci = 1, 2 do if colGroups[ci][tostring(c.cls)] then seen = seen + 1 end end
    if seen ~= 1 then splitBad = splitBad + 1 end -- 一个组只许出现在一列
  end
  for _ in pairs(colGroups[1]) do g1 = g1 + 1 end
  for _ in pairs(colGroups[2]) do g2 = g2 + 1 end
  return { items = items, groups = gn, rows = rows, perCol = perCol, colGroups = { g1, g2 },
    over = over, gapBad = gapBad, colStartBad = colStartBad, splitBad = splitBad,
    balance = math.abs(rowsL - rowsR), rowsL = rowsL, rowsR = rowsR, colW = colW, colX2 = colX2 }
end
function EVAL_TEST_TPL_TIP() EVAL_HELP_TPL_BUILD() return tplUI.tipBtn end
function EVAL_TEST_TPL_TIP_TEXT()
  EVAL_HELP_TPL_BUILD()
  if not tplUI.tipText then return nil end
  local ok, t = pcall(tplUI.tipText.GetText, tplUI.tipText)
  return ok and t or nil
end
function EVAL_HELP_TPL_TOGGLE()
  if tplUI.root and tplUI.root:IsVisible() then tplUI.root:Hide() return end
  EVAL_HELP_TPL_BUILD()
  if tplUI.root then tplUI.root:Show() end
end

-- 预览区刷新：当前方案文本逐行填进保底 FontString（跳过空行；EditBox 不渲染时靠它看内容）
function EVAL_HELP_IO_REFRESH()
  if not ioUI.pvLines then return end
  local lines = {}
  for line in string.gmatch(EVAL_PROFILE_TO_TEXT() .. "\n", "(.-)\n") do
    if line ~= "" then table.insert(lines, line) end
  end
  for i, ln in ipairs(ioUI.pvLines) do
    ln:SetText(uiEsc(lines[i] or "")) -- 1.61.1 | 显示转义（编辑框原文不受影响）
  end
end

function EVAL_HELP_IO_TOGGLE()
  if ioUI.root and ioUI.root:IsVisible() then ioUI.root:Hide() return end
  EVAL_HELP_IO_BUILD()
  -- 每次打开默认填入当前方案的导出文本（看一眼格式 / 直接改）
  if ioUI.eb then pcall(ioUI.eb.SetText, ioUI.eb, EVAL_PROFILE_TO_TEXT()) end
  EVAL_HELP_IO_REFRESH()
  if ioUI.root then ioUI.root:Show() end
end

-- ============ 斜杠命令 /eh ============

if type(SlashCmdList) == "table" then
  SLASH_EVALHELP1 = "/eh"
  SLASH_EVALHELP2 = "/evalhelp"
  SlashCmdList["EVALHELP"] = function(msg)
    msg = string.lower(tostring(msg or ""))
    msg = string.gsub(msg, "^war", "go") -- /eh war 旧命令组兼容 → 通用 /eh go（1.21.1 改名）
    if msg == "log" then
      -- 1.70.12：日志改 SavedVariables 环形缓冲（UELog 在本客户端不落盘，已弃用）
      local on = not (type(cfg.log) == "table" and cfg.log.on == false)
      cfg.log = type(cfg.log) == "table" and cfg.log or {}
      cfg.log.on = not on
      say("日志记录: " .. ((not cfg.log.on) and "|cff00ff00开|r" or "|cffff0000关|r")
        .. "（缓冲 " .. EVAL_LOG_COUNT() .. " 条；/eh logdump 查看 /eh logclear 清空）")
    elseif msg == "logdump" or string.find(msg, "^logdump%s") then
      local n = EVAL_LOG_DUMP(tonumber(string.sub(msg, 9)))
      if n == 0 then say("日志缓冲为空") else say("已打印 " .. n .. " 条日志（最新的在最后）") end
    elseif msg == "logclear" then
      EVAL_LOG_CLEAR()
      say("日志缓冲已清空")
    elseif msg == "auto" then
      cfg.auto = not cfg.auto
      say("进出战斗自动输出: " .. (cfg.auto and "|cff00ff00开|r" or "|cffff0000关|r"))
    elseif msg == "ui" then
      EVAL_HELP_UI_TOGGLE()
    elseif msg == "cfg" or msg == "config" or msg == "set" then
      EVAL_HELP_CFG_TOGGLE()
    elseif msg == "st" or msg == "state" or msg == "info" then
      EVAL_HELP_ST_TOGGLE()
    elseif msg == "ds" then -- 数据检索诊断：采集点标注层的当前状态（切换区域不生效时用它取证）
      if type(EVAL_DS_NODE_DIAG) == "function" then
        say(EVAL_DS_NODE_DIAG())
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds trace" then -- 开/关采集点标注层的轨迹日志（默认关；取证时开，别长期开）
      if type(EVAL_DS_TRACE) == "function" then
        local on = EVAL_DS_TRACE()
        say("数据检索轨迹日志: " .. (on and "|cff00ff00开|r（切换地图后 /eh logdump 查看）" or "|cffff0000关|r"))
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds clear" or msg == "ds clean" then -- 清理地图标注（按钮已删除，命令保留作快捷方式）
      if type(EVAL_DS_ANN_CLEAR) == "function" then
        EVAL_DS_ANN_CLEAR()
        say("地图标注已清理（类别全关 = 图层关闭；用 /eh ds cat <类别> on 重新显示）")
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds on" then
      if type(EVAL_DS_TOGGLE_NODES) == "function" then
        EVAL_DS_TOGGLE_NODES(true)
        say("地图标注层: |cff00ff00开|r（随地图切换自动更新；与类别勾选联动）")
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds off" then
      if type(EVAL_DS_TOGGLE_NODES) == "function" then
        EVAL_DS_TOGGLE_NODES(false)
        say("地图标注层: |cffff0000关|r")
      else
        say("数据检索模块未载入")
      end
    elseif string.find(msg, "^ds cat ") then -- /eh ds cat herbs on|off
      local k, v = string.match(msg, "^ds cat%s+(%S+)%s*(%S*)$")
      if type(EVAL_DS_SET_CAT) == "function" and k then
        local want = (v ~= "off" and v ~= "0" and v ~= "false")
        if EVAL_DS_SET_CAT(k, want) then
          say(string.format("类别 %s: %s", k, want and "|cff00ff00开|r" or "|cffff0000关|r"))
        else
          say("未知类别: " .. tostring(k) .. "（可用：herbs mines chests fish rares flight innkeeper mailbox banker auctioneer vendor repair stablemaster spirithealer meetingstone battlemaster）")
        end
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds hud" then
      -- ★1.70.38 地图诊断浮层（用户建议）：把诊断信息直接画在世界地图上。
      -- 排查时一张截图即可给出「客户端报什么 / 我们画什么」的决定性证据。
      if type(EVAL_DS_HUD) == "function" then
        local on = EVAL_DS_HUD()
        say("地图诊断浮层: " .. (on and "|cff00ff00开|r（开图后左上角显示诊断文本）" or "|cffff0000关|r"))
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds rnd" then
      -- ★1.70.35 随机点测试（用户建议）：验证「地图打开之后还能不能继续画」。
      -- 开图后每 2 秒往随机位置放 8 个随机色钉子，并统计 PositionWorldMapPin 的真实成败。
      if type(EVAL_DS_RND) == "function" then
        local on = EVAL_DS_RND()
        say("随机点测试: " .. (on and "|cff00ff00开|r（每2秒8点，随机位置；看地图上有没有随机彩点）" or "|cffff0000关|r"))
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds rndstat" then
      if type(EVAL_DS_RND_DIAG) == "function" then say(EVAL_DS_RND_DIAG()) else say("数据检索模块未载入") end
    elseif msg == "ds snap" then
      -- ★1.70.34 一键快照：请在「看到错误标注的那一刻」执行，然后立刻 /reload 落盘。
      -- 它同时记录「客户端报告的区域」「画布实际贴图路径」「我们画的区域与钉子样本」，
      -- 用于判定是投影基准错位还是数据本身不对（多轮日志排查的瓶颈正在于此）。
      if type(EVAL_DS_SNAP) == "function" then
        say(EVAL_DS_SNAP())
        if type(EVAL_LOGLINE) == "function" then EVAL_LOGLINE("[DS][SNAP] " .. EVAL_DS_SNAP()) end
      else
        say("数据检索模块未载入")
      end
    elseif msg == "ds probe" then
      if type(EVAL_DS_PROBE) == "function" then
        for _, s in ipairs({ EVAL_DS_PROBE() }) do say(s) end
      else
        say("数据检索模块未载入")
      end
    elseif string.find(msg, "^go add ") then
      -- 兜底添加: /eh go add 技能名 条件串（如 /eh go add 压制 可用 & 就绪）
      local sn, conds = string.match(string.sub(msg, 8), "^(%S+)%s*(.*)$")
      if sn then
        local w2 = warCfg()
        local p = w2.profiles[w2.activeProfile or 1]
        if p then -- 1.33.4 取消 8 上限残留（1.33.0 漏改的 /eh go add 路径）
          table.insert(p.skills, { skill = sn, enabled = true, groups = EVAL_PARSE_CONDS(conds), why = sn })
          say("已添加: " .. sn .. " → " .. ((conds ~= "") and conds or "无条件"))
          pcall(EVAL_WAR_TAB_REFRESH)
        end
      end
    elseif string.find(msg, "^go del ") then
      local n = tonumber(string.sub(msg, 8))
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      if p and n and p.skills[n] then
        say("已删除: " .. tostring(p.skills[n].skill))
        table.remove(p.skills, n)
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif string.find(msg, "^go newprof") then
      local nm = string.match(msg, "^go newprof%s*(.*)$")
      local w2 = warCfg()
      if table.getn(w2.profiles) < 4 then
        table.insert(w2.profiles, { name = (nm and nm ~= "") and nm or ("方案" .. tostring(table.getn(w2.profiles) + 1)), skills = {} })
        w2.activeProfile = table.getn(w2.profiles)
        say("新建并切换到: " .. tostring(w2.profiles[w2.activeProfile].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      else
        say("最多 4 个方案")
      end
    elseif string.find(msg, "^go prof ") then
      local n = tonumber(string.sub(msg, 9))
      local w2 = warCfg()
      if n and w2.profiles[n] then
        w2.activeProfile = n
        say("切换到方案: " .. tostring(w2.profiles[n].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif string.find(msg, "^go delprof") then
      local n = tonumber(string.match(msg, "^go delprof%s*(%d*)$"))
      local w2 = warCfg()
      EVAL_WAR_DEL_PROFILE(n or (w2.activeProfile or 1))
    elseif string.find(msg, "^go rename ") or string.find(msg, "^go name ") then
      local nm = string.match(msg, "^go %S+%s+(.+)$")
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      if p and nm and nm ~= "" then
        p.name = nm
        say("方案已改名: " .. nm)
        pcall(EVAL_WAR_TAB_REFRESH)
      end
    elseif msg == "go next" then
      local w2 = warCfg()
      if table.getn(w2.profiles) > 1 then
        w2.activeProfile = (w2.activeProfile or 1) % table.getn(w2.profiles) + 1
        say("切换到方案: " .. tostring(w2.profiles[w2.activeProfile].name))
        pcall(EVAL_WAR_TAB_REFRESH)
      else
        say("只有一个方案（配置窗口 一键宏设置页 [+] 新建）")
      end
    elseif msg == "go io" or msg == "go export" or msg == "go import" then
      EVAL_HELP_IO_TOGGLE()
    elseif msg == "go list" then
      local w2 = warCfg()
      local p = w2.profiles[w2.activeProfile or 1]
      say("— 方案[" .. tostring(p and p.name) .. "] —")
      if p then
        for i, r in ipairs(p.skills) do
          say(string.format("%d. %s %s | %s", i, tostring(r.skill),
            (r.enabled ~= false) and "|cff00ff00开|r" or "|cffff0000关|r", uiEsc(EVAL_GROUP_STR(r.groups))))
        end
      end
    elseif msg == "go" then
      EVAL_GO_STATUS()
    elseif msg == "go rescan" then
      EVAL_GO_RESCAN(false, "menu")
    elseif msg == "go trace" then
      -- 执行追踪（1.54.2）：最近 12 次 EVAL_GO 调用时间戳+去抖标记——偶发「按一下执行两次」定位用
      local tr = EVAL_GO_TRACE
      if not tr or table.getn(tr) == 0 then
        say("执行追踪：暂无记录（先按几次宏再查）")
      else
        say("— EVAL_GO 执行追踪（新→旧，间隔=与前一次相差毫秒）—")
        for i, e in ipairs(tr) do
          local gap = (i > 1) and math.floor((tr[i - 1].t - e.t) * 1000 + 0.5) or 0
          say(string.format("%2d. t=%.3f  +%dms  %s", i, e.t, gap,
            e.skip and "|cffff5040×去抖丢弃|r" or "|cff00ff00√执行|r"))
        end
      end
    elseif msg == "go mbicon" or msg == "go mbicon reset" then
      -- ★1.71.15 小地图按钮图标：查当前 / 清掉自定义（清掉后回到自动挑；换图标走图标库右键，不必敲命令）
      if msg == "go mbicon reset" then
        c().mbIcon = nil
        EVAL_HELP_MB_SETICON()
        say("小地图按钮图标：已清掉自定义，回到自动挑选")
      else
        local cur = c().mbIcon
        say("小地图按钮图标：" .. (type(cur) == "string" and cur or "（自动挑选）") .. "（图标库里右键任意一枚可换；/eh go mbicon reset 清掉自定义）")
      end
    elseif msg == "go bind2" then
      -- ★派发实弹探针（1.71.16）：T2 只证明了「命令名能存进绑定表」——「按下键真的触发」要实弹验证。
      --   T3 = CLICK 派发（vanilla 经典招：CLICK <命名按钮>:LeftButton → 按键 = 客户端替我们点隐藏按钮）；
      --   T4 = 裸命令名派发（EVAL_TEST_KEYFIRE 全局函数 —— 客户端会不会把命令名解析成全局函数直接调）。
      --   两个空闲键各绑一种，10 秒内请各按一次；倒计时结束如实报告，然后解绑还原（不 SaveBindings）。
      if not EVAL_TEST_CLICKBTN then
        local tb = CreateFrame("Button", "EVAL_TEST_CLICKBTN", UIParent)
        tb:SetScript("OnClick", function() EVAL_TEST_CLICKFIRED = GetTime() end)
      end
      EVAL_TEST_CLICKFIRED, EVAL_TEST_KEYFIRE_T = nil, nil
      EVAL_TEST_KEYFIRE = function() EVAL_TEST_KEYFIRE_T = GetTime() end
      local free2 = {}
      for _, k in ipairs({ "F11", "F12", "F10", "F9", "8", "9", "CTRL-8", "CTRL-9", "ALT-8", "ALT-9", "BUTTON4", "BUTTON5" }) do
        local okv, v = pcall(GetBindingAction, k)
        if okv and v == "" then table.insert(free2, k) if table.getn(free2) >= 2 then break end end
      end
      if table.getn(free2) < 2 then
        say("找不到两个空闲键——先 /eh go bind 看哪些键空着，告诉我两个我来改探针")
      else
        local k1, k2 = free2[1], free2[2]
        pcall(SetBinding, k1, "CLICK EVAL_TEST_CLICKBTN:LeftButton")
        pcall(SetBinding, k2, "EVAL_TEST_KEYFIRE")
        say("— 派发实弹探针：10 秒内请按一次 " .. k1 .. "（CLICK 派发）和一次 " .. k2 .. "（裸命令名）—")
        local pf = CreateFrame("Frame")
        local t0 = GetTime()
        pf:SetScript("OnUpdate", function()
          if GetTime() - t0 < 10 then return end
          pf:SetScript("OnUpdate", nil)
          say("T3 CLICK 派发 " .. k1 .. "：" .. (EVAL_TEST_CLICKFIRED and "|cff00ff00★真的触发了|r（隐藏按钮 OnClick 收到）" or "|cffff5040×没触发|r"))
          say("T4 裸命令名 " .. k2 .. "：" .. (EVAL_TEST_KEYFIRE_T and "|cff00ff00★真的触发了|r（全局函数被调）" or "|cffff5040×没触发|r"))
          pcall(SetBinding, k1)
          pcall(SetBinding, k2)
          say("探针结束：两键已解绑还原（未 SaveBindings，改动随重登消失）")
        end)
      end
    elseif msg == "go bind" then
      -- ★快捷键可行性探针（1.71.12 用户要求「先验证」：方案右键弹窗设快捷键这条路能不能走）。
      --   ★安全边界：全程**不 SaveBindings**（内存改动换角色/重登自动消失），且每个试验键位用完立刻解绑还原。
      --   T0 = 枚举客户端命令表（GetNumBindings/GetBinding）——看命令名长什么样、有没有插件可挂的口子；
      --   T1 = 空闲键位绑 JUMP（已知合法命令）→ 期望 true 且读得回 → 证明 SetBinding/GetBindingAction 本身可用；
      --   T2 = 同键位绑 "EVAL_GO2"（插件自定义命令名）→ ★true = 不用 Bindings.xml 也能绑（右键弹窗直接可行）；
      --        false = 命令名必须先在 Bindings.xml 里登记（要客户端重启才生效）。
      say("— 快捷键可行性探针（不存档、不动现有绑定）—")
      local function gba(k)
        local ok, v = pcall(GetBindingAction, k)
        return (ok and type(v) == "string") and v or nil
      end
      -- T0：命令表概览
      local okN, nB = pcall(GetNumBindings)
      if okN and type(nB) == "number" then
        say("T0 命令表共 " .. nB .. " 行（前 12 行）：")
        local evalHits = 0
        for i = 1, math.min(nB, 300) do
          local okG, cmd, cat, k1, k2 = pcall(GetBinding, i)
          if okG and type(cmd) == "string" and string.sub(cmd, 1, 5) == "EVAL_" then evalHits = evalHits + 1 end
          if okG and i <= 12 then
            say("  " .. i .. ". " .. tostring(cmd) .. " | " .. tostring(cat) .. " | " .. tostring(k1) .. " | " .. tostring(k2))
          end
        end
        say("T0 以 EVAL_ 开头的命令行数 = " .. evalHits .. "（0 = 客户端没有给我们预留命令名）")
      else
        say("T0 GetNumBindings 不可用（" .. tostring(nB) .. "）——整条路判死")
      end
      -- 找一个空闲键位（GetBindingAction == "" 才算空；nil = API 不可用）
      local CAND94 = { "F10", "F11", "F12", "6", "7", "8", "9", "0", "SHIFT-2", "SHIFT-3", "CTRL-2", "ALT-2", "BUTTON3" }
      local freeKey = nil
      for _, k in ipairs(CAND94) do
        local v = gba(k)
        if v == "" then freeKey = k break end
      end
      if not freeKey then
        say("候选键位全被占用或 GetBindingAction 不可用 → 换一个再试（可自己挑个确定空闲的键告诉我）")
      else
        say("空闲键位 = " .. freeKey .. "（当前 GetBindingAction = 空串）")
        -- T1：绑已知合法命令 JUMP
        local ok1, r1 = pcall(SetBinding, freeKey, "JUMP")
        local back1 = gba(freeKey)
        say("T1 SetBinding(" .. freeKey .. ", JUMP) → " .. tostring(ok1 and r1) .. "，读回 = " .. tostring(back1))
        pcall(SetBinding, freeKey) -- 立刻解绑还原
        say("T1 已解绑，读回 = " .. tostring(gba(freeKey)) .. "（期望空串）")
        -- T2：绑插件自定义命令名（本探针的核心问题）
        local ok2, r2 = pcall(SetBinding, freeKey, "EVAL_GO2")
        local back2 = gba(freeKey)
        say("T2 SetBinding(" .. freeKey .. ", EVAL_GO2) → " .. tostring(ok2 and r2) .. "，读回 = " .. tostring(back2))
        if ok2 and r2 and back2 == "EVAL_GO2" then
          say("T2 ★可行：命令名不用登记——「方案右键弹窗设快捷键」可以直接用 SetBinding 做")
        else
          say("T2 ★被拒：命令名要先在 Bindings.xml 登记（<Binding name=\"EVAL_GO2\">）才接受——需要加文件 + 客户端重启")
        end
        pcall(SetBinding, freeKey) -- 收尾再清一次
      end
      say("探针结束：全程未 SaveBindings（GetCurrentBindingSet = " .. tostring(GetCurrentBindingSet and GetCurrentBindingSet() or "?") .. "），改动随重登消失")
    elseif msg == "go probe immune" then
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
    elseif string.sub(msg, 1, 15) == "go probe usable" then
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
    elseif msg == "go probe dump" then
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
    elseif msg == "go 频道" or string.find(msg or "", "^go 频道") == 1 then
      -- ★1.71.3 取证：屏蔽「频道进出信息」到底生效没有；以及有没有更干净的官方入口。
      --   本机 API 全表（1370 条）里**没有聊天过滤器**（ChatFrame_AddMessageEventFilter 之类不存在），
      --   现用的是「挂 DEFAULT_CHAT_FRAME:AddMessage」这一层。
      --   ★若这里显示「已过滤 0 条」而确实有人进出频道 → 说明客户端不走 Lua 打印，需要换方案（把结论发我）。
      local sarg = string.match(msg or "", "^go 频道%s*(.-)%s*$") or ""
      if string.find(sarg, "^装") == 1 then
        -- ★手动立刻重试挂载（自动重试已由 事件 / 每帧 / 诊断 三处驱动，这里是救急入口）
        local okd = (type(EVAL_TB_CHAN_INSTALL) == "function") and EVAL_TB_CHAN_INSTALL() and true or false
        say("立刻重试挂载：" .. (okd and "成功" or "失败（DEFAULT_CHAT_FRAME 现在不可用？）"))
      elseif string.find(sarg, "^试") == 1 then
        local sample = string.match(sarg, "^试%s*(.*)$") or ""
        if sample == "" then sample = "[4. 世界防务] 离开频道。" end
        say("样本：" .. sample)
        local hit = (type(EVAL_TB_CHAN_BLOCK) == "function") and EVAL_TB_CHAN_BLOCK(sample)
        say("判据：" .. (hit and "命中（会被吞掉）" or "不命中（会正常显示）"))
      else
        local on, hooked, cnt, samples, live, seenAll, tries = EVAL_TEST_TB_CHAN_STATE()
        say("— 频道进出信息 屏蔽 诊断 —")
        say("开关：屏蔽=" .. (on and "开" or "关") .. "（默认开；配置窗 → 工具箱 → 队伍/社交）")
        say("入口：DEFAULT_CHAT_FRAME=" .. ((DEFAULT_CHAT_FRAME and "有") or "无")
          .. " 已挂载=" .. tostring(hooked) .. " 我们的包装在位=" .. tostring(live) .. "（尝试 " .. tostring(tries) .. " 次）")
        say("经过入口的聊天消息：" .. tostring(seenAll) .. " 条；其中被吞：" .. tostring(cnt) .. " 条")
        if type(samples) == "table" and table.getn(samples) > 0 then
          for _, m in ipairs(samples) do say("  样本：" .. tostring(m)) end
        else
          say("  （暂无被吞样本）")
        end
        -- ★★1.71.3 判读：把「挂载没成功」与「客户端不走 Lua 打印」区分开——现象一样、修法完全不同
        if not live then
          say("|cffff8080判读：我们的包装没在位 → 挂载没成功（本版已自动重试；可用 /eh go 频道 装 立刻再试一次）|r")
        elseif seenAll == 0 then
          say("|cffff8080判读：入口在位，但一条聊天消息都没经过它 → 客户端不走 Lua 打印，需要换方案（把这屏发我）|r")
        else
          say("判读：入口在位且真的在转发；等一条「XX 进入/离开频道」再看「被吞」是否 +1")
        end
        if type(GetChatWindowMessages) == "function" then
          local okg, g1 = pcall(GetChatWindowMessages, 1)
          say("聊天窗口1 消息组：" .. ((okg and type(g1) == "string" and g1 ~= "") and g1 or "（读不到）"))
        else
          say("聊天窗口1 消息组：本客户端没有 GetChatWindowMessages 接口")
        end
        say("用法：/eh go 频道 试 [文本] = 试判据；/eh go 频道 装 = 立刻重试挂载")
      end
    elseif msg == "go immune" then
      local im = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.immune) or {}
      local n, keys = 0, {}
      for k in pairs(im) do n = n + 1 table.insert(keys, k) end
      table.sort(keys)
      say("免疫学习记录 " .. n .. " 条（/eh go immune clear 清空）:")
      for _, k in ipairs(keys) do say("  " .. k) end
    elseif msg == "go immune clear" then
    elseif msg == "go 停施法" or string.find(msg or "", "^go 停施法") == 1 then
      -- ★1.71.3 结论（用户两轮实测）：插件调 SpellStopCasting 在本客户端**只清本地进度条**、
      --   服务端读条照旧；「移动脉冲」实测同样无效（已删）。★用户判断这可能是**客户端 bug** →
      --   **功能先留着**（代码不删，客户端修好即生效）。本命令保留三档，方便日后复测。
      local sarg = string.match(msg or "", "^go 停施法%s*(.-)%s*$") or ""
      local function hasApi(n)
        if type(_G[n]) == "function" then return "有" end
        return "无"
      end
      say("— 停读法诊断（现状：插件只能清本地进度条，真中断做不到）—")
      say("接口检测：SpellStopCasting=" .. hasApi("SpellStopCasting") .. " RunScript=" .. hasApi("RunScript")
        .. " MoveForwardStart=" .. hasApi("MoveForwardStart") .. " MoveForwardStop=" .. hasApi("MoveForwardStop"))
      if sarg == "" then
        say("1 = 只调 SpellStopCasting（＝生产通道：会清本地进度条）")
        say("2 = 完整生产通道 EVAL_STOP_CAST()")
        say("3 = Jump（万一哪天客户端认这个）")
      elseif sarg == "1" then
        if type(RunScript) == "function" then pcall(RunScript, "SpellStopCasting()") end
        say("已发 SpellStopCasting（RunScript 排队）")
      elseif sarg == "2" then
        if type(EVAL_STOP_CAST) == "function" then
          local okc, howc = EVAL_STOP_CAST()
          say("已发：ok=" .. tostring(okc) .. " 明细=" .. tostring(howc))
        else say("EVAL_STOP_CAST 不存在（引擎没载入？）") end
      elseif sarg == "3" then
        if type(Jump) == "function" then pcall(Jump) say("已调 Jump()") else say("本客户端没有 Jump 接口") end
      else
        say("参数：1 / 2 / 3")
      end
    elseif msg == "go probe" or msg == "go 光环" or string.find(msg or "", "^go 光环 ") == 1 then
      -- buff 探针（1.33.1）：两条枚举+tooltip 读名路径原始值打印，诊断药品类 buff 不进下拉
      say("— buff 探针（结果同时写调试日志） —")
      local function pr(s) say(s) logLine(s) end
      pr("GetPlayerBuff=" .. tostring(type(GetPlayerBuff)) .. " UnitBuff=" .. tostring(type(UnitBuff)) .. " SetPlayerBuff=" .. tostring(type(GameTooltip.SetPlayerBuff)) .. " SetUnitBuff=" .. tostring(type(GameTooltip.SetUnitBuff)))
      pr("BuffButton0=" .. tostring(getglobal("BuffButton0") ~= nil) .. " BuffFrame=" .. tostring(getglobal("BuffFrame") ~= nil))
      for i = 0, 3 do
        local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
        pr(string.format("GPB(%d) ok=%s bi=%s(%s)", i, tostring(okb), tostring(bi), type(bi)))
        if okb and type(bi) == "number" and bi >= 0 then
          local okt, tex = pcall(GetPlayerBuffTexture, bi)
          pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
          pcall(function() GameTooltip:ClearLines() end)
          local oks, built = pcall(GameTooltip.SetPlayerBuff, GameTooltip, bi)
          local nm = GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText and GameTooltipTextLeft1:GetText()
          pr("  tex=" .. tostring(okt and tex) .. " | SetPlayerBuff ok=" .. tostring(oks) .. " built=" .. tostring(built) .. " name=" .. tostring(nm))
          pcall(function() GameTooltip:Hide() end)
        end
      end
      for i = 1, 4 do
        local oku, tex, apps = pcall(UnitBuff, "player", i)
        pr(string.format("UnitBuff(%d) ok=%s tex=%s apps=%s", i, tostring(oku), tostring(tex), tostring(apps)))
        if oku and tex then
          pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
          pcall(function() GameTooltip:ClearLines() end)
          local oks, built = pcall(GameTooltip.SetUnitBuff, GameTooltip, "player", i)
          local nm = GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText and GameTooltipTextLeft1:GetText()
          pr("  SetUnitBuff ok=" .. tostring(oks) .. " built=" .. tostring(built) .. " name=" .. tostring(nm))
          pcall(function() GameTooltip:Hide() end)
        end
      end
      -- ★★★1.71.2（第十轮）**指定光环名的定向探查**（用户实测：骑士「虔诚光环」判定失败）。
      --   为什么要它：官方文档明写 GetPlayerBuff/UnitBuff 只枚举**出现在增益条上的光环**，
      --   且「Hidden or tracking auras are skipped」——若该光环不占增益条槽位，两个 API 都看不到它。
      --   到底是「没有这个光环」还是「有但纹理对不上」，只有现场数据能分辨 → 做成一条命令。
      --   ★用法：/eh go 光环 虔诚光环   （不写名字则默认查「虔诚光环」）
      do
        local want = string.match(msg or "", "^go 光环%s+(.+)$") or "虔诚光环"
        want = string.gsub(want, "^%s*(.-)%s*$", "%1")
        local wslot = wslots and wslots[want]
        local wtex = auraTexOf(want)
        pr("【光环定向探查】目标名称=「" .. want .. "」")
        pr("  动作条有该格子吗：" .. (wslot and ("有（格子 " .. tostring(wslot.slot) .. "）") or "没有"))
        pr("  auraTexOf 解析纹理：" .. tostring(wtex))
        pr("  状态表里有这个纹理吗：" .. tostring(wtex and EVAL_HELP_STATE and EVAL_HELP_STATE.playerBuffs and EVAL_HELP_STATE.playerBuffs[wtex]))
        -- ★直接给出「插件此刻的判定」：这才是用户问题的答案（看数据还得自己推）
        local curCnt = (wtex and EVAL_HELP_STATE and EVAL_HELP_STATE.playerBuffs and tonumber(EVAL_HELP_STATE.playerBuffs[wtex])) or 0
        if EVAL_HELP_STATE and EVAL_HELP_STATE.playerBuffs and EVAL_HELP_STATE.playerBuffs[wtex] == true then curCnt = 1 end
        if not wtex then
          pr("  ⇒ 插件判定：**无法判定**（名字解析不出纹理）—— 修复后会如实报错，不再重复施放")
        elseif curCnt > 0 then
          pr("  ⇒ 插件判定：**有**该光环（层数 " .. curCnt .. "）→ 条件「自身buff检查=否」**不成立**，不应重复施放")
        else
          pr("  ⇒ 插件判定：**没有**该光环（纹理 " .. tostring(wtex) .. "）→ 条件「否」成立，会重复施放")
        end
        local gpbN, ubN, gpbHit, ubHit = 0, 0, nil, nil
        if type(GetPlayerBuff) == "function" then
          for i = 0, 31 do
            local okb, bi = pcall(GetPlayerBuff, i, "HELPFUL")
            if not okb or type(bi) ~= "number" or bi < 0 then break end
            gpbN = gpbN + 1
            local okt, tex = pcall(GetPlayerBuffTexture, bi)
            local nm
            if GameTooltip and GameTooltip.SetPlayerBuff then
              pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
              pcall(function() GameTooltip:ClearLines() end)
              pcall(GameTooltip.SetPlayerBuff, GameTooltip, bi)
              if GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText then nm = GameTooltipTextLeft1:GetText() end
              pcall(function() GameTooltip:Hide() end)
            end
            logLine(string.format("GPB[%d] bi=%d tex=%s name=%s", i, bi, tostring(tex), tostring(nm)))
            if (wtex and tex == wtex) or (nm and nm == want) then gpbHit = i end
          end
        end
        if type(UnitBuff) == "function" then
          for i = 1, 32 do
            local oku, tex = pcall(UnitBuff, "player", i)
            if not oku or not tex then break end
            ubN = ubN + 1
            local nm
            if GameTooltip and GameTooltip.SetUnitBuff then
              pcall(function() GameTooltip:SetOwner(UIParent, "ANCHOR_NONE") end)
              pcall(function() GameTooltip:ClearLines() end)
              pcall(GameTooltip.SetUnitBuff, GameTooltip, "player", i)
              if GameTooltipTextLeft1 and GameTooltipTextLeft1.GetText then nm = GameTooltipTextLeft1:GetText() end
              pcall(function() GameTooltip:Hide() end)
            end
            logLine(string.format("UB[%d] tex=%s name=%s", i, tostring(tex), tostring(nm)))
            if (wtex and tex == wtex) or (nm and nm == want) then ubHit = i end
          end
        end
        pr(string.format("  增益条共 %d 条（GetPlayerBuff）/ %d 条（UnitBuff）", gpbN, ubN))
        pr("  命中：GetPlayerBuff=" .. tostring(gpbHit or "未命中") .. "  UnitBuff=" .. tostring(ubHit or "未命中"))
        if not wtex then
          pr("  ⇒ 结论：**这个名字解析不出纹理** —— 旧版会把它当成「确定没有」（已修）")
        elseif gpbHit or ubHit then
          pr("  ⇒ 结论：光环**就在增益条上**，判定失败是别的原因（看上面的纹理值）")
        else
          pr("  ⇒ 结论：光环**没有出现在增益条上** —— 官方文档：两个 API 只枚举增益条上的光环")
        end
        if gpbN > 0 or ubN > 0 then
          pr("  （逐条明细已写入调试日志：/eh logdump）")
        end
      end
    elseif msg == "wdebug" or msg == "debug" then
      cfg.wdebug = not cfg.wdebug
      say("调试日志: " .. (cfg.wdebug and "|cff00ff00开|r" or "|cffff0000关|r"))
    elseif msg == "help" then
      say("—— EVAL_HELP 全职业施法工具（通用一键宏） ——")
      say("|cffffff00快速上手:|r ① 技能拖上动作条 ② /eh go rescan ③ 新建宏正文 /run EVAL_GO() 拖上按键连按")
      say("|cffffff00命令:|r /eh 输出状态 | /eh log 写日志开关 | /eh auto 进出战斗自动输出")
      say("/eh ui 战斗信息UI | /eh st 状态信息UI | /eh cfg 设置窗口（小地图旁 EH 图标同效）")
      say("/eh go 一键宏状态 | /eh go rescan 重扫动作条 | /eh debug 调试日志（/eh war 旧命令仍兼容）")
      say("/eh go probe 增益探针（逐条枚举自身 buff） | /eh go 光环 [名字] 光环定向探查 | /eh go bind 快捷键可行性探针")
      say("/eh go 停施法 1|2|3 停读法取证（本客户端停读条 API 只有 Protected 的 SpellStopCasting）")
      say("方案命令：/eh go list 查看 | go add 技能 条件 | go del N | go newprof 名 | go prof N | go rename 新名 | go delprof N")
      say("方案导入导出（md 文本复制粘贴）：/eh go io，内置案例模版按职业直接导入")
      say("方案切换：Shift+按一键宏 | /eh go next | 战斗信息UI 方案按钮")
      say("|cffffff00执行指定方案:|r 新建宏正文 /run EVAL_GO(参数) —— 不传或0=当前激活方案；方案号1~4 或 \"方案名\" = 只跑该方案（不切激活）")
      say("　例：/run EVAL_GO(2) 跑2号方案 | /run EVAL_GO(\"测试\") 跑名为测试的方案 | /run EVAL_GO1()~GO4() 同效快捷写法；不同方案各绑一个按键即可多套输出")
      say("|cffffff00提示:|r 猛击需按住 Alt 按宏键；宏入口 /run EVAL_HELP() 输出状态日志")
      say("|cffffff00异常自救:|r 技能不识别/界面异常/刚更新过插件 → 先 /reload 重载（配置已存盘不会丢）；重扫动作条 /eh go rescan")
      say("|cffffff00问题反馈:|r https://gitee.com/xeval/emberveil_eval_help.git —— 插件持续优化中，欢迎测试并留下宝贵意见")
      say("调试日志: /eh logdump 查看（存 SavedVariables，随 /reload 落盘）| /eh log 开关 | /eh logclear 清空")
      say("数据检索诊断: /eh ds | /eh ds hud 地图诊断浮层(推荐) | /eh ds snap 一键快照 | /eh ds rnd 随机点测试 + rndstat 统计 | /eh ds trace 轨迹日志 | /eh ds probe 详情行几何")
      say("地图标注: 一个「地图标注(N)」按钮即可——点开勾选类别（=开关）；/eh ds cat <类别> on|off 命令行等价 | /eh ds clear 清空")
    else
      EVAL_HELP()
    end
  end
end

-- ============ 初始化（SavedVariables 要等 VARIABLES_LOADED 才恢复） ============

local init = CreateFrame("Frame", "EVAL_HELPInitFrame", UIParent)
pcall(init.RegisterEvent, init, "VARIABLES_LOADED")
init:SetScript("OnEvent", function(a, b)
  -- 本客户端 OnEvent 参数传递有兼容差异：event 可能在第 1 参、第 2 参或全局 event
  local eventName
  if type(a) == "string" then eventName = a
  elseif type(b) == "string" then eventName = b
  elseif type(event) == "string" then eventName = event end

  if eventName == "VARIABLES_LOADED" then
    cfg = EVAL_HELP_CONFIG or {}
    EVAL_HELP_CONFIG = cfg
    ehResolveLang() -- 1.34.0 语言解析：cfg.lang 优先 → 客户端语言自动检测
    if cfg.log  == nil then cfg.log  = {} end -- 1.70.12 日志缓冲（旧存档里的 true/false 会在首次写入时自动转成表）
    -- 1.70.16：数据检索的取证开关恢复。必须在 VARIABLES_LOADED 再确认一次——
    -- DataSearch.lua 的载入期 SavedVariables 通常已还原，但首装/边缘时序下可能还没有；
    -- 而 tab tick 在 OnUpdate 上独立运行，不能依赖「用户打开过 Tab4」（踩过：恢复写在 BUILD 里，
    -- 用户停在 Tab1 → 永不恢复 → trace 静默失效）。
    if type(EVAL_DS_RESTORE) == "function" then pcall(EVAL_DS_RESTORE) end
    if cfg.auto == nil then cfg.auto = false end -- 默认不自动输出
    if cfg.wdebug == nil then cfg.wdebug = false end
    if not cfg.war then
      cfg.war = { enabled = true, attack = true } -- 1.48.0 同上
    end
    -- ★1.71.13 小地图按钮贴图标：载入期宏图标接口未必就绪 → 在 VARIABLES_LOADED 后挑；
    --   挑不到会自动退回旧的「金框 + EH」样式（不许留空白按钮）。
    if type(EVAL_HELP_MB_SETICON) == "function" then pcall(EVAL_HELP_MB_SETICON) end
    -- 小地图按钮：恢复拖到的位置（越界则清掉记忆，回到默认锚点）
    if cfg.mbPos and minimapBtn then
      pcall(minimapBtn.ClearAllPoints, minimapBtn)
      pcall(minimapBtn.SetPoint, minimapBtn, cfg.mbPos.point, UIParent,
        cfg.mbPos.relPoint or cfg.mbPos.point, cfg.mbPos.x or 0, cfg.mbPos.y or 0)
      -- ★1.71.2 丢弃记忆的判据从「飞出屏幕」扩到「压在小地图上」：
      --   用户截图里按钮压在小地图左下角，但它并**没有**飞出屏幕 → 旧判据放行 → 位置被永久记住，
      --   每次登录都看到同一个压边现象。现在两者任一成立就回到默认锚点。
      if uiOffscreen(minimapBtn) or mbOverlapsMinimap(minimapBtn) then
        cfg.mbPos = nil
        mbAnchorDefault(minimapBtn)
      end
    end
    -- 战斗信息UI：上次开着的话恢复显示
    if cfg.ui and cfg.ui.enabled then
      EVAL_HELP_UI_BUILD()
      if ui.root then ui.root:Show() end
    end
    -- 状态信息UI：上次开着的话恢复显示
    if cfg.st and cfg.st.enabled then
      EVAL_HELP_ST_BUILD()
      if stui.root then stui.root:Show() end
    end
    -- 注册进出战斗事件（pcall 防御：事件名若不存在不会崩）
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_REGEN_DISABLED")
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_REGEN_ENABLED")
    pcall(autoFrame.RegisterEvent, autoFrame, "PLAYER_TARGET_CHANGED") -- Cat：目标切换时刷新可流血等状态
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_SPELL_SELF_DAMAGE") -- 1.36.0 免疫学习器（探针实测事件名）
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_COMBAT_SELF_HITS") -- 1.55.0 挥击计时锚点（事件名不存在则静默无效）
    -- 1.38.0 施法中跟踪（1.12 无 UnitCastingInfo，只能走 SPELLCAST_* 事件；不存在则静默无效）
    for _, ev2 in ipairs({ "SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED", "SPELLCAST_INTERRUPTED", "SPELLCAST_DELAYED", "SPELLCAST_CHANNEL_START", "SPELLCAST_CHANNEL_STOP" }) do
      pcall(autoFrame.RegisterEvent, autoFrame, ev2)
    end
    -- 1.40.0 目标施法跟踪（探针实测事件）：生物施法文字走 CHAT_MSG_SPELL_CREATURE_VS_* 频道
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
    pcall(autoFrame.RegisterEvent, autoFrame, "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF")
    autoFrame:SetScript("OnEvent", function(ea, eb)
      local en
      if type(ea) == "string" then en = ea
      elseif type(eb) == "string" then en = eb
      elseif type(event) == "string" then en = event end
      if en == "PLAYER_REGEN_DISABLED" then
        EVAL_HELP_STATE.combatStart = GetTime() -- 精确进战时间（Cat 的 MPInCombatTime）
        onCombatEvent(true)
      elseif en == "PLAYER_REGEN_ENABLED" then
        EVAL_HELP_STATE.combatStart = nil
        onCombatEvent(false)
      elseif en == "PLAYER_TARGET_CHANGED" then
        EVAL_HELP_UPDATE_STATE()
      elseif en == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        -- 消息文本取全局 arg1；ea/eb 若承载事件名则不当消息用（三态兼容）
        local msgT = (type(arg1) == "string" and arg1) or ((type(ea) == "string" and ea ~= en) and ea) or (type(eb) == "string" and eb)
        if msgT then EVAL_IMMUNE_LEARN(msgT) end
      elseif en == "CHAT_MSG_COMBAT_SELF_HITS" then
        -- 1.55.0 挥击计时：平砍命中锚定 lastSwing（三态兼容取消息文本）
        local msgS = (type(arg1) == "string" and arg1) or ((type(ea) == "string" and ea ~= en) and ea) or (type(eb) == "string" and eb ~= en and eb) or nil
        if msgS then EVAL_SWING_EVENT(msgS) end
      -- 1.38.0 施法中跟踪：参数顺序做启发式——字符串=技能名、数字=时长ms（CHANNEL_START 的顺序与 START 相反）
      elseif en == "SPELLCAST_START" or en == "SPELLCAST_CHANNEL_START" then
        local a1, a2 = arg1, arg2
        local nm = (type(a1) == "string" and a1) or (type(a2) == "string" and a2) or nil
        local dur = (type(a1) == "number" and a1) or (type(a2) == "number" and a2) or 0
        st.castName = nm or "?"
        st.castStart = GetTime() -- 1.38.1 读条起点（进度=剩余/总时长）
        st.castUntil = (dur > 0) and (GetTime() + dur / 1000) or nil
      elseif en == "SPELLCAST_STOP" or en == "SPELLCAST_FAILED" or en == "SPELLCAST_INTERRUPTED" or en == "SPELLCAST_CHANNEL_STOP" then
        st.castName, st.castUntil = nil, nil
      elseif en == "SPELLCAST_DELAYED" then
        local d = (type(arg1) == "number" and arg1) or 0
        if st.castName and st.castUntil then st.castUntil = st.castUntil + d / 1000 end
      -- 1.40.0 目标施法：「X开始施放Y。」开始（X=当前目标才记）/「Y击中你/对你造成」结束并学习总时长
      elseif en == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" or en == "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE" or en == "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF" then
        local msgT = (type(arg1) == "string" and arg1) or ((type(ea) == "string" and ea ~= en) and ea) or (type(eb) == "string" and eb)
        if msgT then EVAL_TCAST_EVENT(msgT) end
      end
    end)
    say("全职业施法工具 " .. VERSION .. "（通用一键宏） — 一键宏 /run EVAL_GO() | /eh cfg 配置 | /eh help 帮助")
  end
end)