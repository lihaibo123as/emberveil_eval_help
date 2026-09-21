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

local VERSION = "1.74.9"
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
local noSlotOk = EVAL_NO_SLOT_OK -- ★1.72.4 「不占动作条也合法」的单一判据（含指定等级）——UI 侧不许再各写一份名单
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
-- ★1.74.5 导出给别的模块用（工具箱要在「一键喂食」行右侧挂**同一枚黄感叹号 = 待测试**）：
--   路径只在这里写一次 —— 别的模块自己拼路径的话，改名/挪目录只会**静默画空白**（UI ICON CHECK 也照不到）。
EVAL_UI_MARK_TEST = SE_MARK_TEST
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

-- ★★★1.73.53 标题栏文案的**单一来源**：玩家名优先；取不到（载入极早期 / 某些客户端 UnitName 给 nil 或空串）
--   **如实退回**窗口自己的名字 —— 直接 SetText(nil) 会让标题栏空着，比旧文案更糟。
--   ★两处共用（战斗信息UI / 状态信息UI）：用户 1.73.53 要求「状态信息UI 标题也显示玩家角色」，
--     与 1.71.12 的「战斗信息 标题换成用户名字」是同一条规矩 —— 同一条规矩只写一遍（本项目老账）。
local function uiTitleName(fallbackKey)
  local nm = UnitName("player")
  if type(nm) == "string" and nm ~= "" then return nm end
  return L(fallbackKey)
end

-- ★★★1.73.58 **方案品阶读值口**（战斗信息UI 方案行 / 配置窗方案列表 / 标题栏徽标**共用同一份判定**）：
--   返回 rgb, tierIdx, score；**算不出来（Share 未载入 / 坏数据 / 方案表空）如实返回 nil** ——
--   调用方各自退回原有配色，**绝不硬编一个品阶**（本项目「查不到与没有是两件事」的老账）。
--   ★**现算不缓存**（用户 1.73.49：「品阶每次打开方案自动计算完善」）：EVAL_PROFILE_SCORE 只做 table.getn 级
--     累加、不调任何客户端 API ⇒ 放在 0.15s 的 tick 里也是安全的。
local function uiProfileTierRGB(prof)
  if type(prof) ~= "table" then return nil end
  if type(EVAL_PROFILE_SCORE) ~= "function" or type(EVAL_SHARE_SEAL_TIER) ~= "function"
     or type(EVAL_SHARE_SEAL_TIER_RGB) ~= "function" then return nil end
  local okS, sc = pcall(EVAL_PROFILE_SCORE, prof)
  if not okS or type(sc) ~= "number" then return nil end
  local okT, ti = pcall(EVAL_SHARE_SEAL_TIER, sc)
  if not okT or type(ti) ~= "number" then return nil end
  local okR, rgb = pcall(EVAL_SHARE_SEAL_TIER_RGB, ti)
  if not okR or type(rgb) ~= "table" then return nil end
  return rgb, ti, sc
end

-- ★★★1.73.58 **方案按钮配色**（用户：「方案根据品阶染色」）——与**配置窗方案列表 / 案例模版**同一套规则：
--   文字色 = 品阶色；底色 = 品阶色 ×（当前激活 0.45 / 其余 0.22）。三处共用一张品阶表，**不另抄色**。
--   ★算不出品阶 → **如实退回**原来的暗金底 + 暖色字（不硬编一个品阶，也不报错）。
local function uiProfBtnPaint(pb, prof, sel)
  if not (pb and pb.bg and pb.text) then return false end
  local rgb = uiProfileTierRGB(prof)
  if rgb then
    local k = sel and 0.45 or 0.22
    pcall(pb.bg.SetVertexColor, pb.bg, rgb.r * k, rgb.g * k, rgb.b * k, 1)
    pcall(pb.text.SetTextColor, pb.text, rgb.r, rgb.g, rgb.b)
    ui.profTierCalc = (ui.profTierCalc or 0) + 1 -- 记数：判据要能证明「这次真的按品阶算了」
    return true
  end
  pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
  pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.72, sel and 0.9 or 0.68, sel and 0.4 or 0.55)
  return false
end

-- ★★★1.73.55 标题栏中段的**方案档位**（用户：「这位置增加显示玩家方案的档位」）。
--   · 档位 = 当前**激活方案**按 `EVAL_PROFILE_SCORE` 现算出来的品阶 —— 与方案列表 / 案例模版 / 分享封皮
--     用的是**同一张表**（Share.lua 的 SH_SEAL_TIERS），符号与色码都从它那几个读值口取，**不在这里另抄一份**
--     （本项目「同一规则两处实现 = 迟早漂移」的老账）。
--   · **不缓存**：用户 1.73.49 定的规矩「品阶每次打开方案自动计算完善」——配置窗侧栏每次都现算，标题栏同理，
--     否则改了方案内容 / 换了激活方案，标题上挂的还是上一轮的档位（界面与真值自相矛盾）。
--   · **算不出就如实返回 nil**（Share 未载入 / 方案表空 / 坏数据）→ 调用方如实清空徽标，
--     **绝不硬编一个档位**（本项目「查不到与没有是两件事」的老账）。
--   · 代价：EVAL_PROFILE_SCORE 只做 table.getn 级别的累加（不调任何客户端 API）⇒ tick 里现算是安全的。
local function uiProfileTierText()
  local w2 = uiWarCfg()
  local prof = w2.profiles and w2.profiles[w2.activeProfile or 1]
  if type(prof) ~= "table" then return nil end
  local rgb, ti, sc = uiProfileTierRGB(prof) -- ★1.73.58 与方案行/方案列表共用同一个读值口
  if not rgb then return nil end
  -- ★★注意 pcall 的返回：`EVAL_SHARE_SEAL_TIER` 返回 **档位序号 + 品阶表** 两个值 ⇒
  --   pcall 之后是 ok, 序号, 品阶表 —— 写成 `local okT, tier = pcall(...)` 拿到的是**序号**（number），
  --   于是 `type(tier) ~= "table"` 恒成立 → 整个徽标恒为 nil（1.73.59 实踩，组 164 当场报 got=nil）。
  local okT, _pick, tier = pcall(EVAL_SHARE_SEAL_TIER, sc)
  if not okT or type(tier) ~= "table" then return nil end
  local sym = ""
  if type(EVAL_SHARE_SEAL_SYMBOL) == "function" then
    local okY, sy = pcall(EVAL_SHARE_SEAL_SYMBOL, ti)
    if okY and type(sy) == "string" then sym = sy end
  end
  return { tier = ti, score = sc, text = "[" .. sym .. tostring(tier.name or "") .. "]", rgb = rgb }
end

-- ★★★1.73.57 标题栏的**玩家头衔**（用户：「显示玩家的头衔」）。
--   · 单一来源 = EVAL_TITLE_CURRENT()（彩蛋自定义**优先度最高**、抽卡头衔兜底、**没入档就如实 nil**）——
--     这里不再判一次档位/卡池（那是 Share.lua 的规矩）。
--   · 颜色也用它给的那个色码（抽到的头衔 = 该档头衔色；彩蛋自定义 = 专属名号色），经 EVAL_COLOR_RGB 解析；
--     解析不出来 → 中性色显示原文（**不猜颜色**、也不因为解析失败就不显示头衔）。
local function uiPlayerTitle()
  if type(EVAL_TITLE_CURRENT) ~= "function" then return nil end
  local okT, cur = pcall(EVAL_TITLE_CURRENT)
  if not okT or type(cur) ~= "table" then return nil end
  local nm = cur.name
  if type(nm) ~= "string" or nm == "" then return nil end
  local rgb = nil
  if type(EVAL_COLOR_RGB) == "function" then
    local okR, r2 = pcall(EVAL_COLOR_RGB, cur.color)
    if okR and type(r2) == "table" then rgb = r2 end
  end
  return { name = nm, rgb = rgb, custom = cur.custom and true or false }
end

-- ★★★1.73.59 标题栏徽标的**登记表**（按**窗口键**登记：重建时覆盖同一个键，不会越积越多 = 幽灵控件的另一种形态）。
--   ★为什么要登记表：用户 1.73.59 要求「状态信息名称和头衔 参考战斗信息做相同的布局」——
--     若两个窗口各写一遍「名字 → [品阶] → 头衔」，迟早漂移（本项目「同一规则两处实现」的老账）。
--     ⇒ 建徽标的是**同一个函数**、刷新的是**同一份实现**，两个窗口只负责把自己那一对登记进来。
local uiTitleBadgeSets = {}

-- 建一对徽标并登记：锚在 titleFs（标题文字）的右边缘依次排开 —— 名字 → 档位 → 头衔。
--   ★标题是只锚了 LEFT 的 FontString（宽度随文字自适应）⇒ 徽标天然跟随，**不需要手工量宽**。
-- ★★★1.73.62 用户：「战斗信息 标题 品阶和头衔 位置对调. 描述调整 头衔 品阶.方案名称」
--   ⇒ 三个文字从左到右的顺序定为 **头衔 → 品阶 → 方案名称**（都挂在玩家名右边，依次锚前一个的右边缘）。
--   为什么把顺序与内容都放在**这一个**公用件里：两个窗口共用它 ⇒ 战斗信息UI 与状态信息UI 永远同一套布局
--   （用户 1.73.59 就是这么要求的；改这里 = 两个窗口一起改，不会再各自漂移）。
--   ★标题是只锚了 LEFT 的 FontString（宽度随文字自适应）⇒ 后面的都天然跟随，**不需要手工量宽**。
local function uiTitleBadgesMake(key, parent, z, titleFs)
  local gap = math.floor(8 * z)
  local size = math.max(9, math.floor(10 * z))
  -- ① 头衔（1.73.62 起排在最前）
  local ifs = uiText(parent, size, 0.72, 0.70, 0.62)
  ifs:SetPoint("LEFT", titleFs, "RIGHT", gap, 0)
  pcall(ifs.SetJustifyH, ifs, "LEFT")
  pcall(ifs.SetNonSpaceWrap, ifs, false)
  -- ② 品阶徽标
  local tfs = uiText(parent, size, 0.72, 0.70, 0.62)
  tfs:SetPoint("LEFT", ifs, "RIGHT", gap, 0)
  pcall(tfs.SetJustifyH, tfs, "LEFT")
  pcall(tfs.SetNonSpaceWrap, tfs, false)
  -- ③ 当前方案名
  local pfs = uiText(parent, size, 0.72, 0.70, 0.62)
  pfs:SetPoint("LEFT", tfs, "RIGHT", gap, 0)
  pcall(pfs.SetJustifyH, pfs, "LEFT")
  pcall(pfs.SetNonSpaceWrap, pfs, false)
  uiTitleBadgeSets[key] = { tier = tfs, title = ifs, plan = pfs }
  return ifs, tfs, pfs
end

-- 写三个徽标（头衔 → 品阶 → 方案名）的文案与颜色。
--   ★诚实规矩（三处都一样）：**算不出来就如实清空 + 收回中性灰** —— 既不硬编一个头衔/档位/方案名，
--     也不沿用上一个颜色（那会画出一个假的）。
--   ★文案没变就不碰控件（不每帧写 SetText）。
local function uiTitleBadgePaint(set)
  if type(set) ~= "table" then return end
  local function put(fs, txt, rgb, r2, g2, b2)
    if not fs then return end
    local okc, cur = pcall(fs.GetText, fs)
    if not (okc and tostring(cur or "") == txt) then pcall(fs.SetText, fs, txt) end
    if rgb then
      pcall(fs.SetTextColor, fs, rgb.r, rgb.g, rgb.b)
    else
      pcall(fs.SetTextColor, fs, r2 or 0.72, g2 or 0.70, b2 or 0.62)
    end
  end
  -- ① 头衔（彩蛋自定义 = 专属名号色；抽到的 = 该档头衔色）
  local ti = uiPlayerTitle()
  put(set.title, (ti and ti.name) or "", ti and ti.rgb or nil)
  -- ② 品阶（该方案的品阶色）
  local info = uiProfileTierText()
  put(set.tier, (info and info.text) or "", info and info.rgb or nil)
  -- ③ 当前方案名（颜色 = **该方案的品阶色**，与紧挨着的品阶徽标同源；算不出 → 中性灰）
  local w2 = uiWarCfg()
  local prof = w2.profiles and w2.profiles[w2.activeProfile or 1]
  local pname = (type(prof) == "table" and type(prof.name) == "string") and prof.name or ""
  put(set.plan, pname, uiProfileTierRGB(prof))
end

-- ★★★1.73.57/1.73.59 刷新口：**所有登记的窗口一次刷完**（BUILD 里一次 + tick 里每次）。
local function uiTitleBadgeRefresh()
  for _, set in pairs(uiTitleBadgeSets) do uiTitleBadgePaint(set) end
  return true
end

-- ★★★1.73.54 **标题栏右侧的快捷开关**（用户：「将上面两个开关（战斗区/方案区）在标题栏右侧对应添加两个开关，
--   快速开启关闭；**标题左对齐、控制开关右对齐**」）。
--   ★为什么是小方框：标题栏总宽只有 ~224px（还要放玩家名，名字可能很长）；方框 + **悬停提示**最省地方，
--     提示文案直接复用配置窗那两条（`G_UI_SUBC_TIP` / `G_UI_SUBS_TIP`）——**文案单一来源**，不另抄一份。
--   ★点一下 = 改**同一份配置**（`uiCfg().subCombat/subScheme`）+ **整帧重建**（与配置窗那条路殊途同归）+
--     顺手 `cfgWin.refresh()`（两个入口一份真值，界面必须同步 —— 本项目「两份状态」的老账）。
--   ★配方照本项目 UI 规程：Button + EnableMouse + RegisterForClicks（Frame 的点击不吃）；
--     层级 = 标题栏 +1（保证盖在拖动柄之上、点得到；**不用 strata 抬高**那条失败做法）。
local function uiTitleToggle(parent, z, xRight, getter, setter, tip)
  local box = math.floor(13 * z)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(box) b:SetHeight(box)
  b:SetPoint("RIGHT", parent, "RIGHT", xRight, 0)
  pcall(b.EnableMouse, b, true)
  pcall(b.RegisterForClicks, b, "LeftButtonUp")
  local okLvl, lvl = pcall(parent.GetFrameLevel, parent)
  if okLvl and type(lvl) == "number" then pcall(b.SetFrameLevel, b, lvl + 1) end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.10, 0.09, 0.07, 1)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  local mark = uiText(b, math.max(9, math.floor(11 * z)), 1, 0.85, 0.35)
  mark:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.mark = mark -- ★读值口：断言读**真控件**上的方块（不读我们自己的记账）
  local function onNow()
    if type(getter) ~= "function" then return true end
    local ok, v = pcall(getter)
    if not ok then return true end
    if v then return true end
    return false
  end
  b.refresh = function()
    local on = onNow()
    pcall(mark.SetText, mark, on and "■" or "")
    pcall(bg.SetVertexColor, bg, on and 0.45 or 0.10, on and 0.35 or 0.09, on and 0.10 or 0.07, 1)
  end
  b:SetScript("OnClick", function()
    local on = onNow()
    if type(setter) == "function" then pcall(setter, not on) end -- setter 内部会写配置 + 整帧重建
    b.refresh()
    -- ★配置窗同步（同一份真值）：走**全局桥** EVAL_HELP_CFGWIN —— 不能用 cfgWin 这个 local，
    --   它声明在本文件后段（DECL ORDER 检查当场抓到过：EvalHelp.lua:211 used before declared at 855）。
    local cw = rawget(_G, "EVAL_HELP_CFGWIN")
    if type(cw) == "table" and type(cw.refresh) == "function" then pcall(cw.refresh) end
  end)
  if type(tip) == "string" and tip ~= "" then
    b:SetScript("OnEnter", function()
      pcall(GameTooltip.SetOwner, GameTooltip, b, "ANCHOR_RIGHT")
      pcall(GameTooltip.AddLine, GameTooltip, tip, 0.9, 0.88, 0.72, true)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    b:SetScript("OnLeave", function() pcall(GameTooltip.Hide, GameTooltip) end)
  end
  b.refresh()
  return b
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
  ui.tierText, ui.tierShown, ui.tierScore, ui.tierIdx = nil, nil, nil, nil -- ★1.73.55 标题栏档位徽标（同上：不清会写成幽灵控件）
  ui.titleText, ui.titleShown, ui.titleCustom = nil, nil, nil -- ★1.73.57 标题栏玩家头衔（同上）
  ui.planText, ui.planShown = nil, nil -- ★1.73.62 标题栏当前方案名（同上）

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
  -- ★★★1.73.54 用户：「标题左对齐、控制开关右对齐」——标题从**居中**改成**贴左**（给右侧两个开关让位）。
  title:SetPoint("LEFT", titleBar, "LEFT", math.floor(6 * z), 0)
  pcall(title.SetJustifyH, title, "LEFT")
  pcall(title.SetNonSpaceWrap, title, false)
  -- ★1.71.12 用户要求：「战斗信息 标题换成 用户名字」；★1.73.53 起与状态信息UI 共用同一个取名函数
  title:SetText(uiTitleName("G_UI_TITLE"))
  -- ★★★1.73.55/1.73.57 标题栏中段：**方案档位徽标** + **玩家头衔**（用户：「这位置增加显示玩家方案的档位」/
  --   「显示玩家的头衔」）——从**标题文字的右边缘**起依次排开 ⇒ 自然跟在玩家名后面；
  --   最右边才是那两个快捷开关；四个控件从左到右依次排开，互不遮挡。
  --   ★建徽标走公用件 uiTitleBadgesMake（**状态信息UI 用同一个件做同一套布局**，见 1.73.59），
  --     文案/颜色由 uiTitleBadgeRefresh() 写（BUILD 一次 + tick 每次）。
  ui.titleText, ui.tierText, ui.planText = uiTitleBadgesMake("ui", titleBar, z, title) -- ★1.73.62 顺序：头衔 → 品阶 → 方案名
  uiTitleBadgeRefresh()
  -- ★★★1.73.54 标题栏右侧的两个**快捷开关**（战斗区 / 方案区）——与配置窗「界面」组里那两个缩进子开关**同一份真值**：
  --   左→右 = 战斗区、方案区（与配置窗从上到下的顺序一致）；各自贴右端、宽 13、间隔 4；
  --   点一下立刻开/关对应区块（整帧重建，窗口高度随之变化）。
  do
    local togW = math.floor(13 * z)
    local togGap = math.floor(4 * z)
    local xScheme = -math.floor(6 * z)
    local xCombat = xScheme - (togW + togGap)
    ui.tglScheme = uiTitleToggle(titleBar, z, xScheme,
      function() local u3 = uiCfg() return not (u3.subScheme == false) end,
      function(v) local u3 = uiCfg() u3.subScheme = v and true or false EVAL_HELP_UI_BUILD() end,
      L("G_UI_SUBS_TIP"))
    ui.tglCombat = uiTitleToggle(titleBar, z, xCombat,
      function() local u3 = uiCfg() return not (u3.subCombat == false) end,
      function(v) local u3 = uiCfg() u3.subCombat = v and true or false EVAL_HELP_UI_BUILD() end,
      L("G_UI_SUBC_TIP"))
  end

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
    -- ★1.71.19 用户要求：「方案文字 添加 tooltip 提示：右键取消所有自定绑定，左键点击具体的方案激活方案，
    --   右键绑定方案按键，美化说明下」——「方案」二字本身做成可点标签：
    --   悬停出三行操作说明；**右键点它 = 清除全部自定义绑定**（EVAL_BIND_CLEAR_ALL）。
    local plb = CreateFrame("Button", nil, root)
    plb:SetWidth(labelW) plb:SetHeight(btnH)
    -- ★★★1.73.25 用户（截图在「方案」二字下划线）：「方案的位置调高一点」——
    --   实测根因：方案按钮行在 `-y`，而「方案」标签被额外压了 3z px（y + 3z）→ 标签比按钮**低半行**。
    --   正解 = 标签与第一行按钮**共中线**（同一 y），不再各算各的（改这一处不影响下方按钮与技能带）。
    plb:SetPoint("TOPLEFT", root, "TOPLEFT", pad, -y)
    pcall(plb.EnableMouse, plb, true)
    pcall(plb.RegisterForClicks, plb, "LeftButtonUp", "RightButtonUp")
    local plabel = uiText(plb, math.max(8, math.floor(9 * z)), 0.95, 0.82, 0.35)
    plabel:SetPoint("LEFT", plb, "LEFT", 0, 0)
    plabel:SetText("方案")
    ui.profLabelBtn = plb -- 供断言点真控件
    plb:SetScript("OnEnter", function()
      if GameTooltip and GameTooltip.SetOwner then
        pcall(GameTooltip.SetOwner, GameTooltip, plb, "ANCHOR_RIGHT")
        pcall(GameTooltip.AddLine, GameTooltip, L("BIND_L_TIP_T"), 1, 0.85, 0.35)
        pcall(GameTooltip.AddLine, GameTooltip, L("BIND_L_TIP_1"), 0.92, 0.88, 0.80)
        pcall(GameTooltip.AddLine, GameTooltip, L("BIND_L_TIP_2"), 0.92, 0.88, 0.80) -- 1.71.24：右键开的是「方案管理」窗（改名 + 绑键）
        pcall(GameTooltip.AddLine, GameTooltip, L("BIND_L_TIP_3"), 1.00, 0.65, 0.30)
        pcall(GameTooltip.AddLine, GameTooltip, L("BIND_L_TIP_4"), 0.55, 0.85, 0.45) -- 1.71.20 左键 = 打印绑定情况
        pcall(GameTooltip.Show, GameTooltip)
      end
    end)
    plb:SetScript("OnLeave", function()
      if GameTooltip and GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
    end)
    plb:SetScript("OnClick", function(a, b)
      local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
      if mbtn == "RightButton" then
        local n = EVAL_BIND_CLEAR_ALL()
        say(string.format(L("BIND_ALL_CLEARED"), n))
      else
        EVAL_BIND_STATUS() -- ★1.71.20 左键点「方案」= 打印当前绑定情况（只打印，不动绑定）
      end
    end)
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
        -- ★1.71.24 右键 = **方案管理弹窗**（与配置窗同一个窗：改名 + 快捷键；左键仍是切换）
        if mbtn == "RightButton" then
          EVAL_PM_OPEN(pidx)
          return
        end
        local w2 = uiWarCfg()
        if w2.profiles and w2.profiles[pidx] then
          w2.activeProfile = pidx
          say("切换到方案: " .. tostring(w2.profiles[pidx].name))
        end
      end)
      profBtns[i] = { btn = pb, bg = pbg, text = pt }
      -- ★1.73.58 建出来就按品阶上色（不等 0.15s 后的 tick，免得先闪一下暗金）
      uiProfBtnPaint(profBtns[i], w20.profiles and w20.profiles[i], (w20.activeProfile or 1) == i)
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
    -- 悬停 tooltip 看触发条件；左键=切启用/停用、右键=开编辑窗；亮金=条件当前满足；动作条技能带冷却倒数）
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
      pcall(cb.RegisterForClicks, cb, "LeftButtonUp", "RightButtonUp") -- ★1.74.2 右键 = 技能配置弹窗（光注册左键 = 右键永远到不了分派代码）
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
        GameTooltip:AddLine(tostring(r.skill) .. (r.rank and ("(" .. tostring(r.rank) .. ")") or ""), 1, 0.82, 0.3) -- ★1.72.4 等级一并显示
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
      cb:SetScript("OnClick", function(a, b)
        local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
        local w2 = uiWarCfg()
        local prof = w2.activeProfile or 1
        local p = w2.profiles and w2.profiles[prof]
        local r = p and p.skills and p.skills[ci]
        if not r then return end
        -- ★★★1.74.2 右键 = 技能配置弹窗（原左键动作搬家）；左键 = 快速切换启用/停用（用户定）
        if mbtn == "RightButton" then
          EVAL_HELP_SE_OPEN(prof, ci)
          return
        end
        local on = r.enabled ~= false
        r.enabled = not on
        say("技能 " .. tostring(r.skill) .. (on and (" = " .. L("TIP_OFF")) or (" = " .. L("TIP_ON"))))
        EVAL_WAR_TAB_REFRESH() -- ★数据变了 → 界面同步刷新（配置窗技能列表的勾选走这份真值；1.71.1 教训：刷新放写入点）
        EVAL_HELP_UI_TICK()    -- 战斗信息UI 立刻重画（不等下一个 0.15s 心跳，点击反馈要即时）
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
      local d = EVAL_WHEEL_DIR(a, b) -- ★1.73.3 方向单一来源（上滚=+1）
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

  -- ★★★1.73.55 标题栏的**方案档位**徽标：跟着「当前激活方案」走 —— 切换方案 / 改方案内容 / 切语言之后，
  --   下一个心跳就更新（现算，见 uiProfileTierText 的说明）。
  --   ★**不看「方案区」子开关**：徽标画在标题栏里，方案区关掉时它照样说明「现在用的是哪一档」。
  uiTitleBadgeRefresh()

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
        -- ★★★1.73.58 用户：「方案根据品阶染色」——与**配置窗方案列表 / 案例模版**同一套规则
        --   （文字 = 品阶色，底色 = 品阶色 × 激活 0.45 / 否则 0.22；算不出品阶 → 如实退回暗金底 + 暖色字）。
        uiProfBtnPaint(pb, prof, sel)
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
        if enabled and (s or noSlotOk(r.skill, r.rank)) and r.groups then -- ★1.72.4 单一判据：宠物/选取目标/物品/姿态/取消施法/停止攻击/跟随/**指定等级** 都不占动作条，也都要参与亮金
          local okp = groupsOK(r, true) -- dry: 亮金预览不触发选取目标等副作用
          pass = okp and true or false
        end
        if not enabled then
          pcall(pc.icon.SetVertexColor, pc.icon, 0.25, 0.25, 0.25)
          pc.text:SetText("停")
        elseif not s and not noSlotOk(r.skill, r.rank) then -- ★1.72.4 单一判据：这些不占动作条不算缺失（★指定等级的技能不在动作条是正常的，不许标「?」）
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
  local tabNames = { L("TAB_GLOBAL"), L("TAB_MACRO"), L("TAB_TOOLBOX"), L("TAB_DS"), L("TAB_ICONS"), L("TAB_PET") } -- ★1.73.0 第 6 个 Tab：抓宠帮手（PetHelper.lua 独立载入）
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
  -- 1.72.1 [使用引导]：五步新手指引（用户要求：给不懂宏的新人友好引导）
  -- ★★★1.73.41 用户：「使用引导显示弹窗的插件载入的那个引导窗」→ 这个按钮**打开载入时那个引导窗**
  --   （`EVAL_HELP_LOADPOP`，与插件载入时弹的**同一个窗**），不再只往聊天打 7 行。
  do
    local gb = CreateFrame("Button", nil, root)
    gb:SetWidth(70) gb:SetHeight(15)
    gb:SetPoint("TOPLEFT", root, "TOPLEFT", RX + 44, -52)
    pcall(gb.EnableMouse, gb, true)
    pcall(gb.RegisterForClicks, gb, "LeftButtonUp")
    local gg = gb:CreateTexture(nil, "BACKGROUND")
    uiSolid(gg, 0.22, 0.18, 0.10, 1)
    gg:SetPoint("TOPLEFT", gb, "TOPLEFT", 0, 0)
    gg:SetPoint("BOTTOMRIGHT", gb, "BOTTOMRIGHT", 0, 0)
    local gt = uiText(gb, 9, 0.95, 0.82, 0.35)
    gt:SetPoint("CENTER", gb, "CENTER", 0, 0)
    gt:SetText(L("GUIDE_BTN"))
    gb:SetScript("OnClick", function() EVAL_HELP_GUIDE(true) end)
    cfgWin.guideBtn = gb -- ★1.73.41 读值口用：断言必须走这个按钮的**真实 OnClick**
    table.insert(G, gb)
    table.insert(G, gt)
  end
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
    -- ★★★1.73.48 用户：「方案列表的图标和配色方案采用相同规则」⇒ 与**案例模版**同一套：
    --   ① 品阶图标（IconSem 真纹理，13px，与模版窗同尺寸）；② 名称文字色 = 品阶色；
    --   ③ 底色 = 品阶色 × 0.22（当前激活的亮到 × 0.45）。四处（聊天行/分享弹窗/模版/方案列表）**同一张色表**。
    --   ★文字让出左侧图标位（3 + 13 + 4 = 20）并按模板规矩**左对齐 + 垂直居中**（否则文字压在图标上）。
    local pIcon = pb:CreateTexture(nil, "ARTWORK")
    pIcon:SetWidth(13) pIcon:SetHeight(13)
    pIcon:SetPoint("LEFT", pb, "LEFT", 3, 0)
    pIcon:Hide()
    local pt = uiText(pb, 10, 0.92, 0.88, 0.80)
    pt:SetPoint("LEFT", pb, "LEFT", 20, 0)
    pcall(pt.SetWidth, pt, 90 - 20 - 4)
    pcall(pt.SetJustifyH, pt, "LEFT")
    pcall(pt.SetJustifyV, pt, "MIDDLE")
    pcall(pt.SetNonSpaceWrap, pt, false)
    local pidx = i
    cfgWin.profBtns = cfgWin.profBtns or {}
    cfgWin.profBtns[i] = pb -- ★测试钩子：交出真实控件（右键合并的断言要真的点它）
    pcall(pb.RegisterForClicks, pb, "LeftButtonUp", "RightButtonUp")
    pb:SetScript("OnClick", function(a, b)
      local w2 = warCfg()
      local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButton"
      -- ★1.71.24 右键 = **方案管理弹窗**（改名 + 快捷键合并到一起；用户：「将这两个功能合并成一个弹窗管理」）
      if mbtn == "RightButton" and pidx <= table.getn(w2.profiles) then
        EVAL_PM_OPEN(pidx)
        return
      end
      if pidx <= table.getn(w2.profiles) then
        w2.activeProfile = pidx
      elseif pidx == table.getn(w2.profiles) + 1 and table.getn(w2.profiles) < MAXPROF then
        table.insert(w2.profiles, { name = "方案" .. tostring(table.getn(w2.profiles) + 1), skills = {}, src = "manual", author = (type(UnitName) == "function" and UnitName("player")) or nil }) -- ★1.73.63 手动创建（彩蛋闸门要认）★1.74.5 作者=自己名字彩蛋闸门要认）
        w2.activeProfile = table.getn(w2.profiles)
        say("新建方案: " .. tostring(w2.profiles[w2.activeProfile].name))
      end
      EVAL_WAR_TAB_REFRESH()
    end)
    -- ★1.74.5 方案列表 tooltip：悬停显示**评级（品阶）+ 来源（作者）+ 基本信息**（用户要求）
    pcall(pb.SetScript, pb, "OnEnter", function()
      local w2 = warCfg()
      if pidx > table.getn(w2.profiles) then return end
      local prof = w2.profiles[pidx]
      if not prof or type(GameTooltip) ~= "table" then return end
      pcall(function()
        GameTooltip:SetOwner(pb, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tostring(prof.name or "?"), 1, 0.82, 0.2)
        local sc = (type(EVAL_PROFILE_SCORE) == "function") and EVAL_PROFILE_SCORE(prof) or nil
        local tier = (sc ~= nil and type(EVAL_SHARE_SEAL_TIER) == "function") and select(2, EVAL_SHARE_SEAL_TIER(sc)) or nil
        if type(tier) == "table" and tier.color then
          local r, g, b = 1, 1, 1
          if type(EVAL_COLOR_RGB) == "function" then local rr, gg, bb = EVAL_COLOR_RGB(tier.color); r, g, b = rr or 1, gg or 1, bb or 1 end
          GameTooltip:AddLine(L("PROF_TIP_RATING") .. "：" .. tostring(tier.name) .. "（" .. tostring(sc) .. " 分）", r, g, b)
        end
        GameTooltip:AddLine(L("PROF_TIP_SOURCE") .. "：" .. tostring(EVAL_PROF_AUTHOR_LABEL(prof)), 0.85, 0.85, 0.85)
        GameTooltip:AddLine(tostring(table.getn(prof.skills or {})) .. " " .. L("PROF_TIP_SKILLS"), 0.7, 0.7, 0.7)
        GameTooltip:Show()
      end)
    end)
    pcall(pb.SetScript, pb, "OnLeave", function() pcall(function() GameTooltip:Hide() end) end)
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
    warUI.profBtns[i] = { btn = pb, bg = pbg, text = pt, del = delB, delBg = delBg, icon = pIcon } -- ★1.73.48 图标也交出来（断言读真控件）
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
  -- ★★★1.73.8 交给其它 Tab 页的**底部行几何**（生产读值口，不是测试专用）：
  --   图标库的「分页信息 + 翻页按钮」要挪到与 [关闭] **同一行**并对齐它。
  --   ★为什么必须从这里读：CLOSE_MIDY / CLOSE_LEFT 是**本文件的单一来源**，别的文件读不到 local ——
  --     各写一份 y 就是「两份真值」，改一处必然漂移（与「窗口宽度单一来源 cfWinWidth()」同一条律）。
  EVAL_HELP_CFG_BOTTOM = { w = W, midY = CLOSE_MIDY, closeLeft = CLOSE_LEFT, closeW = CLOSE_W,
                           closeH = CLOSE_H, rowY = NAV_ROW_Y, rowH = NAV_H, navX0 = NAV_X0 }
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
    root:SetScript("OnMouseWheel", function(a, b)
      -- ★1.73.3 方向统一走 EVAL_WHEEL_DIR（上滚=+1；本客户端老写法把方向放在全局 arg1，helper 三种都认）
      local dir = EVAL_WHEEL_DIR(a, b)
      if dir == 0 then return end
      warUI.offset = math.max(0, (warUI.offset or 0) - dir) -- 上滚 = 回到前面
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
  if type(EVAL_PH_BUILD) == "function" then EVAL_PH_BUILD(root, pages[6], refreshes) end -- 抓宠帮手 Tab（PetHelper.lua 独立载入）
  EVAL_HELP_CFG_SETTAB(c().cfgTab or 1)
  return root
end

-- ===== 方案管理弹窗（1.71.24：把「重命名」与「快捷键绑定」两个右键功能合并成一个窗） =====
-- ★用户需求：「将这两个功能合并成一个弹窗管理，都是右键触发」——
--   此前：配置窗方案按钮右键 = 重命名弹窗；战斗信息UI 方案按钮右键 = 绑定弹窗（两个窗、两套 chrome）。
--   现在：**任一处右键方案按钮都开本窗**，窗内分两段：① 方案名称 ② 快捷键。
--   ★左键语义不变（仍是激活方案）——只合并「右键」这一路。
-- ★EditBox 在本客户端可能不渲染 → 保留回声行（OnTextChanged 实时镜像，盲打也可见）的保底范式。
local pmUI = {}

function EVAL_PM_BUILD()
  if pmUI.root then return end
  local W, H = 320, 232
  local root = CreateFrame("Frame", "EVAL_HELP_PM", UIParent)
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
  pmUI.title = title
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  -- ===== ① 方案名称 =====
  local secName = uiText(root, 10, 0.85, 0.70, 0.20)
  secName:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -32)
  secName:SetText(L("PM_SEC_NAME"))
  pmUI.secName = secName
  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_PM_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(240) eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", root, "TOPLEFT", 24, -70)
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
    ebBg:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -64)
    ebBg:SetWidth(W - 36) ebBg:SetHeight(24)
    local ebEdge = root:CreateTexture(nil, "BORDER")
    uiSolid(ebEdge, 0.85, 0.70, 0.20, 0.8)
    ebEdge:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -64)
    ebEdge:SetWidth(W - 36) ebEdge:SetHeight(1)
    pmUI.eb = eb
  else
    local noEb = uiText(root, 9, 0.7, 0.5, 0.5)
    noEb:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -70)
    noEb:SetText(L("RP_NOEB"))
  end
  -- 回声行：EditBox 不渲染时的保底可见性
  local echo = uiText(root, 11, 1, 0.9, 0.4)
  echo:SetPoint("TOPLEFT", root, "TOPLEFT", 24, -94)
  pcall(echo.SetWidth, echo, W - 48)
  pcall(echo.SetJustifyH, echo, "LEFT")
  pmUI.echo = echo
  if pmUI.eb then
    pmUI.eb:SetScript("OnTextChanged", function()
      local ok, t = pcall(pmUI.eb.GetText, pmUI.eb)
      if ok and type(t) == "string" then echo:SetText(t) end
    end)
  end

  -- ===== ② 快捷键 =====
  local secKey = uiText(root, 10, 0.85, 0.70, 0.20)
  secKey:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -116)
  secKey:SetText(L("PM_SEC_KEY"))
  pmUI.secKey = secKey
  local curText = uiText(root, 10, 0.92, 0.88, 0.80)
  curText:SetPoint("TOPLEFT", root, "TOPLEFT", 20, -134)
  pmUI.curText = curText
  local keyBtn = CreateFrame("Button", nil, root)
  keyBtn:SetWidth(W - 36) keyBtn:SetHeight(20)
  keyBtn:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -152)
  pcall(keyBtn.EnableMouse, keyBtn, true)
  pcall(keyBtn.RegisterForClicks, keyBtn, "LeftButtonUp")
  local kbBg = keyBtn:CreateTexture(nil, "BACKGROUND")
  uiSolid(kbBg, 0.16, 0.13, 0.08, 1)
  kbBg:SetPoint("TOPLEFT", keyBtn, "TOPLEFT", 0, 0)
  kbBg:SetPoint("BOTTOMRIGHT", keyBtn, "BOTTOMRIGHT", 0, 0)
  local keyText = uiText(keyBtn, 10, 0.95, 0.82, 0.35)
  keyText:SetPoint("CENTER", keyBtn, "CENTER", 0, 0)
  pmUI.keyBtn, pmUI.keyText = keyBtn, keyText
  keyBtn:SetScript("OnClick", function()
    local rows, items, locked = EVAL_BIND_KEYLIST()
    EVAL_DD_OPEN(keyBtn, items, function(pi) EVAL_BIND_DD_PICK(rows, pi) end, { locked = locked })
  end)
  local infoText = uiText(root, 9, 0.65, 0.65, 0.65)
  infoText:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -176)
  pcall(infoText.SetWidth, infoText, W - 36)
  pmUI.infoText = infoText

  -- ===== 按钮行 =====
  local function bBtn(x, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(84) b:SetHeight(22)
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
  -- ★「保存」= 一次把两段都提交（改名 + 绑键），符合「合并成一个弹窗管理」的语义
  pmUI.saveBtn = bBtn(12, L("BTN_OK"), function() EVAL_PM_SAVE() end)
  pmUI.clearBtn = bBtn(108, L("BIND_CLEAR"), function()
    local p = warCfg().profiles and warCfg().profiles[pmUI.pidx]
    EVAL_BIND_CLEAR(pmUI.pidx)
    say(string.format(L("BIND_CLEARED"), tostring(p and p.name)))
    pmUI.selKey = nil
    pmRefresh()
  end)
  bBtn(204, L("BTN_CANCEL"), function()
    if type(EVAL_DD_HIDE) == "function" then pcall(EVAL_DD_HIDE) end
    root:Hide()
  end)

  root:SetScript("OnHide", function()
    if type(EVAL_DD_HIDE) == "function" then pcall(EVAL_DD_HIDE) end -- 下拉贴 UIParent，宿主关了要一起收
  end)
  root:Hide()
  pmUI.root = root
end

-- 刷新显示（标题 / 当前键 / 名字回填 / 冲突提示）——单一刷新点，改名与绑键都走它
function pmRefresh()
  local w2 = warCfg()
  local p = pmUI.pidx and w2.profiles and w2.profiles[pmUI.pidx]
  pmUI.title:SetText(L("PM_TITLE") .. "：" .. (p and tostring(p.name) or "?"))
  local cur = w2.bindKeys and w2.bindKeys[pmUI.pidx]
  pmUI.curText:SetText(string.format(L("BIND_CUR"), (type(cur) == "string" and cur ~= "") and cur or L("BIND_NONE")))
  pmUI.keyText:SetText(pmUI.selKey or L("BIND_PICK"))
  local info, ir, ig, ib = L("PM_HINT"), 0.65, 0.65, 0.65
  if pmUI.selKey then
    local okA, act = pcall(GetBindingAction, pmUI.selKey)
    act = (okA and type(act) == "string") and act or ""
    local cmd = (pmUI.pidx and w2.bindSlots and w2.bindSlots[pmUI.pidx]) and EVAL_BIND_SLOT_CMD(w2.bindSlots[pmUI.pidx]) or ""
    if act == "" or (cmd ~= "" and act == cmd) then
      info, ir, ig, ib = L("BIND_FREE"), 0.55, 0.85, 0.45
    else
      info, ir, ig, ib = string.format(L("BIND_CONFLICT"), act), 1.00, 0.65, 0.30
    end
  end
  pmUI.infoText:SetText(info)
  pcall(pmUI.infoText.SetTextColor, pmUI.infoText, ir, ig, ib)
end

function EVAL_PM_PICK(key)
  pmUI.selKey = key
  pmRefresh()
end

-- ① 改名（从输入框取值；空名如实拒绝、不改动）
function EVAL_PM_APPLY_NAME()
  local nm = ""
  if pmUI.eb then
    local ok, t = pcall(pmUI.eb.GetText, pmUI.eb)
    if ok and type(t) == "string" then nm = t end
  end
  nm = string.gsub(nm, "^%s*(.-)%s*$", "%1")
  if nm == "" then return false end
  local w2 = warCfg()
  local p = pmUI.pidx and w2.profiles and w2.profiles[pmUI.pidx]
  if not p then return false end
  p.name = nm
  return true
end

-- ★保存 = 改名 +（选了键就）绑键，一次提交；两条都失败才报「什么都没做」
function EVAL_PM_SAVE()
  local w2 = warCfg()
  local p = pmUI.pidx and w2.profiles and w2.profiles[pmUI.pidx]
  if not p then return false, "noprof" end
  local did = false
  if EVAL_PM_APPLY_NAME() then
    did = true
    say(string.format(L("PM_RENAMED"), tostring(p.name)))
  end
  if pmUI.selKey then
    local ok2, err = EVAL_BIND_DO(pmUI.pidx, pmUI.selKey)
    if ok2 then
      did = true
      say(string.format(L("BIND_DONE"), pmUI.selKey, tostring(p.name)))
      pmUI.selKey = nil
    else
      say(string.format(L("BIND_FAIL"), tostring(err)))
    end
  end
  if not did then say(L("PM_NAME_EMPTY")) end
  pmRefresh()
  EVAL_WAR_TAB_REFRESH() -- ★数据变了 → 界面同步刷新（1.71.1 教训：刷新放写入点）
  return did
end

-- 打开（两处右键共用这一个入口）——名字回填 + 焦点 + 刷新
function EVAL_PM_OPEN(idx)
  EVAL_PM_BUILD()
  local w2 = warCfg()
  if not (w2.profiles and w2.profiles[idx]) then return false end
  pmUI.pidx = idx
  pmUI.selKey = nil
  local nm = tostring(w2.profiles[idx].name or "")
  if pmUI.eb then
    pcall(pmUI.eb.SetText, pmUI.eb, nm)
    pcall(pmUI.eb.SetFocus, pmUI.eb)
  end
  if pmUI.echo then pmUI.echo:SetText(nm) end
  pmRefresh()
  pmUI.root:Show()
  return true
end

-- ★★1.71.24 关键决定：**不为旧入口留别名**。
--   留别名会让「调用点改回旧名字」这种回归**悄悄通过**（旧名照样开同一个窗 → 行为断言全绿），
--   实测变异 M1/M2 正是这样 SURVIVED 的 → 删掉旧名，任何回退都会当场变成「调用 nil」而炸响。
--   （旧名 EVAL_HELP_RP_OPEN / EVAL_BIND_OPEN 的调用点已全部改指 EVAL_PM_OPEN。）


-- ===== 通用名称输入弹窗（1.29.0：仿 1.17.0 重命名弹窗回声行范式——EditBox 可能不渲染 → 金色回声行保底） =====
-- EVAL_TN_OPEN(标题, 当前值, onOk(名称))；确定/回车回调，取消/Esc 直接关。
local tnUI = {}

function EVAL_TN_BUILD()
  if tnUI.root then return end
  -- ★★★1.73.32 用户报「添加物品弹窗被遮盖 / 无法拖拽」——【审计结论】
  --   ① 层级：本弹窗是 130，而工具箱里从它**打开**的「自动购买设置」弹窗是 200（1.73.31 刚抬上去）
  --      → 子弹窗被父弹窗压住，**点击与拖动都被父弹窗吃掉**（用户看到的正是这个）；
  --   ② 宽度：原来固定 300，标题长一点就顶满、输入框只有 220；
  --   ③ 内部布局：两个按钮的 x 是**写死的**（70/160）→ 窗口一加宽就不居中，看着"乱"；
  --      标签还写死成「目标名称：」（那是「指定目标」用法的文案，物品/数量/每次都跟着错）。
  --   ⇒ 层级改成 **220**（高于工具箱各弹窗 200、低于全局下拉 250）；宽度 400；按钮按宽度**居中**；标签由调用方给。
  local W, H = 400, 150
  local root = CreateFrame("Frame", "EVAL_HELP_TN", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 220) -- ★高于工具箱弹窗(200)，低于全局下拉(250)
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
  pcall(titleBar.SetFrameLevel, titleBar, 221)
  pcall(titleBar.EnableMouse, titleBar, true)
  pcall(titleBar.RegisterForClicks, titleBar, "LeftButtonUp")
  pcall(titleBar.RegisterForDrag, titleBar, "LeftButton")
  local tbBg = titleBar:CreateTexture(nil, "BACKGROUND")
  uiSolid(tbBg, 0.14, 0.11, 0.06, 1)
  tbBg:SetPoint("TOPLEFT", titleBar, "TOPLEFT", 0, 0)
  tbBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
  local title = uiText(titleBar, 10, 0.95, 0.82, 0.35)
  title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
  pcall(title.SetWidth, title, W - 20)
  pcall(title.SetJustifyH, title, "CENTER")
  tnUI.titleText = title
  tnUI.titleBar = titleBar -- ★1.73.32 读值口要读它的拖动注册/层级
  tnUI.btns = {}
  titleBar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  titleBar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)

  local lab = uiText(root, 10, 0.85, 0.85, 0.85)
  lab:SetPoint("TOPLEFT", root, "TOPLEFT", 16, -36)
  pcall(lab.SetWidth, lab, W - 32)
  lab:SetText(L("TN_LABEL") .. "：") -- ★1.73.32 由 EVAL_TN_OPEN 的第 4 参覆盖（原来是写死的「目标名称：」）
  tnUI.label = lab

  local okEb, eb = pcall(CreateFrame, "EditBox", "EVAL_HELP_TN_EB", root)
  if okEb and eb then
    pcall(eb.SetAutoFocus, eb, false)
    pcall(eb.EnableMouse, eb, true)
    eb:SetWidth(W - 60) eb:SetHeight(18) -- ★1.73.32 跟着窗口宽度走（原来写死 220）
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

  -- ★1.73.32 按钮改为**按窗口宽度居中**（原来 x 写死 70/160 → 窗口一宽就偏在左边，看着乱）
  local btnW, btnGap = 90, 20
  local function bBtn(slot, label, fn)
    local total = btnW * 2 + btnGap
    local x = math.floor((W - total) / 2 + (slot - 1) * (btnW + btnGap))
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(btnW) b:SetHeight(22)
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
    table.insert(tnUI.btns, b)
  end
  bBtn(1, L("BTN_OK"), function() apply() end)
  bBtn(2, L("BTN_CANCEL"), function() root:Hide() end)
  tnUI.btnW, tnUI.btnGap, tnUI.W = btnW, btnGap, W

  root:Hide()
  root:SetScript("OnHide", function() tnUI.onOk = nil end)
  tnUI.root = root
end

-- ★1.73.32 第 4 参 label = 输入框上方那行标签（不给就用通用「输入」；不同用法各说各的，别再一律写「目标名称：」）
function EVAL_TN_OPEN(title, cur, onOk, label)
  EVAL_TN_BUILD()
  tnUI.onOk = onOk
  if tnUI.titleText then tnUI.titleText:SetText(title or L("TN_LABEL")) end
  if tnUI.label then tnUI.label:SetText((label or L("TN_LABEL")) .. "：") end
  if tnUI.eb then
    pcall(tnUI.eb.SetText, tnUI.eb, cur or "")
    pcall(tnUI.eb.SetFocus, tnUI.eb)
  end
  if tnUI.echo then tnUI.echo:SetText(cur or "") end
  tnUI.root:Show()
end
-- ★★★1.73.32 读值口：通用输入弹窗的**规程审计**（层级 / 拖动协议 / 宽度 / 内部布局 / 标签）
function EVAL_TEST_TN_Z()
  if not tnUI.root then return nil end
  local function num(o, m)
    if not o or type(o[m]) ~= "function" then return nil end
    local ok, v = pcall(o[m], o)
    return (ok and type(v) == "number") and v or nil
  end
  local function val(o, m)
    if not o or type(o[m]) ~= "function" then return nil end
    local ok, v = pcall(o[m], o)
    if ok and v ~= nil then return v end
    return nil
  end
  local out = { w = num(tnUI.root, "GetWidth"), h = num(tnUI.root, "GetHeight"),
                level = num(tnUI.root, "GetFrameLevel"), movable = val(tnUI.root, "IsMovable"),
                ebW = num(tnUI.eb, "GetWidth"), btns = {} }
  out.titleLevel = num(tnUI.titleBar, "GetFrameLevel")
  out.drag = val(tnUI.titleBar, "GetDragRegistered")
  out.clicks = val(tnUI.titleBar, "GetClicksRegistered")
  local okL, labT = pcall(tnUI.label.GetText, tnUI.label)
  out.label = (okL and tostring(labT or "")) or ""
  for i = 1, table.getn(tnUI.btns or {}) do
    local b = tnUI.btns[i]
    table.insert(out.btns, { x = num(b, "GetLeft"), w = num(b, "GetWidth"), y = num(b, "GetTop") })
  end
  return out
end
function EVAL_TEST_TN_CLOSE() if tnUI.root then pcall(tnUI.root.Hide, tnUI.root) end return true end
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
  local n0 = table.getn(w2.profiles)
  if n0 <= 1 then say("至少保留一个方案") return false end
  if not w2.profiles[idx] then return false end
  local nm = tostring(w2.profiles[idx].name)
  -- ★★★1.73.25 用户：「方案删除 要删除对应绑定的按键信息」。
  --   绑定是按**方案序号**存的（w2.bindKeys[pidx] / w2.bindSlots[pidx]，单一真源见 EVAL_BIND_*）→
  --   删掉第 idx 个方案时必须做三件事，缺一就会留下错位/幽灵按键：
  --   ① 把 idx 那一格**解绑 + 清空**（EVAL_BIND_CLEAR，它自带 SaveBindings）；
  --   ② 把 idx **之后**的绑定**整体左移一格**（★不左移 = 被删方案的键会「粘」到下一个方案身上）；
  --   ③ 左移之后再 SaveBindings 落盘（前一步存的是中间状态，这里必须再存一次）。
  local freed, moved = false, 0
  if type(EVAL_BIND_CLEAR) == "function" then
    local ok = pcall(EVAL_BIND_CLEAR, idx)
    if ok and w2.bindKeys and w2.bindKeys[idx] == nil then freed = true end
    -- ★EVAL_BIND_CLEAR 里的判据已经清过一遍；这里再确认一次「解绑真的生效」（不许只看返回值）
    local stillKey = w2.bindKeys and w2.bindKeys[idx]
    if stillKey == nil and w2.bindSlots and w2.bindSlots[idx] == nil then freed = true end
  end
  local function tbShiftBind(tbl)
    if type(tbl) ~= "table" then return end
    local nt = {}
    for i = 1, n0 do
      if i ~= idx and tbl[i] ~= nil then
        local j = (i < idx) and i or (i - 1)
        nt[j] = tbl[i]
        moved = moved + 1
      end
    end
    for k in pairs(tbl) do tbl[k] = nil end
    for k, v in pairs(nt) do tbl[k] = v end
  end
  tbShiftBind(w2.bindKeys)
  tbShiftBind(w2.bindSlots)
  if moved > 0 and type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  say("已删除方案: " .. nm ..
      (freed and "（已解除它自己的快捷键绑定）" or "") ..
      (moved > 0 and ("；后面 " .. tostring(moved) .. " 个方案的绑定已左移一格") or ""))
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
-- ★1.73.49 方案列表「品阶重算」次数（每次刷新按方案内容重算一次；判据读它证明「打开就算」）
local warProfTierCalc = 0
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
-- ★★★1.73.49 品阶重算计数（用户：「品阶每次打开方案自动计算完善」）——「打开了就重算」这件事必须**可断言**
function EVAL_TEST_WAR_TIER_CALC_COUNT() return warProfTierCalc end
-- ★★★1.73.48 方案列表行的**外观读值口**（「图标和配色与案例模版同一套」这条判据读它）：
--   一律读**真控件**（GetTexture / IsShown / GetTextColor / GetVertexColor）——本项目「读自己拼的账 = 测自己」的老坑。
-- ★★★1.73.49 取证命令 `/eh go 方案图标`：方案列表每行的 **品阶 → 请求的纹理 → 客户端实际报回来的纹理 → 是否显示**
--   一次摊开。为什么要有它：真机上「图标是黑的」有三种完全不同的原因（没请求 / 请求了没生效 / 生效了没画出来），
--   而它们的区别**只能靠读回来的纹理路径**分辨（本项目「写成功 ≠ 写进去生效」那一族）。
function EVAL_WAR_PROF_ICON_PROBE()
  if not EVAL_TEST_CFG_LAYOUT() then pcall(EVAL_HELP_CFG_TOGGLE) end
  pcall(EVAL_WAR_TAB_REFRESH)
  local rows = EVAL_TEST_WAR_PROF_ROWS()
  local n = table.getn(rows)
  say("===== 方案图标探针（方案列表 " .. tostring(n) .. " 行）=====")
  for i = 1, n do
    local v = rows[i]
    if tostring(v.name or "") ~= "" then
      say(string.format("  [%d] %s · 实际纹理=%s · 传参=%s · 显示=%s",
        i, tostring(v.name), tostring(v.icon or "nil"), tostring(v.iconArgs or "?"), tostring(v.iconShown)))
    end
  end
  say("  ★「实际纹理=nil」= SetTexture 没生效；有路径但图黑 = 传参/纹理本身问题（正常应传 1 个参数）")
  return rows
end
function EVAL_TEST_WAR_PROF_ROWS()
  local w = cfgWin.warUI or {}
  local out = {}
  for i, e in ipairs(w.profBtns or {}) do
    local o = { name = nil, icon = nil, iconShown = false, textR = nil, textG = nil, textB = nil,
                bgR = nil, bgG = nil, bgB = nil, justify = nil }
    if e.text then
      local okt, tv = pcall(e.text.GetText, e.text)
      if okt and type(tv) == "string" then o.name = tv end
      local okc, r, g, b = pcall(e.text.GetTextColor, e.text)
      if okc then o.textR, o.textG, o.textB = r, g, b end
      local okj, jv = pcall(e.text.GetJustifyH, e.text)
      if okj and type(jv) == "string" then o.justify = jv end
    end
    if e.bg then
      local okv, r, g, b = pcall(e.bg.GetVertexColor, e.bg)
      if okv then o.bgR, o.bgG, o.bgB = r, g, b end
    end
    if e.icon then
      local okt, tv = pcall(e.icon.GetTexture, e.icon)
      if okt and type(tv) == "string" then o.icon = tv end
      local oks, sv = pcall(e.icon.IsShown, e.icon)
      o.iconShown = (oks and sv) and true or false
      -- ★1.73.49 「SetTexture 传了几个实参」也要读得回来（真机黑图正是**多传了第二个参数**）
      if type(e.icon.GetSetTextureArgs) == "function" then
        local oka, av = pcall(e.icon.GetSetTextureArgs, e.icon)
        if oka and type(av) == "number" then o.iconArgs = av end
      end
    end
    out[i] = o
  end
  return out
end

function EVAL_WAR_TAB_REFRESH()
  warRefreshTick() -- ★1.71.2 计数（见 warRefreshTick 说明：只验数据验不出「没刷新」）
  if not EVAL_IS_SCANNED() then EVAL_GO_RESCAN(true, "auto") end -- 1.32.9 自愈：初始化重扫若早于动作条就绪，这里补扫（否则技能行图标全灰）
  local warUI = cfgWin.warUI
  if not warUI then return end
  -- ★★★1.73.56 用户真机 bug：「在 Tab 切到全局等**非一键宏**的 Tab 之后，关闭重新打开**会把一键宏的技能列表页显示出来**」。
  --   根因：本函数是**数据刷新**，却顺带 Show/Hide 自己那一页的控件（技能行 / 方案删除钮 / 方案图标 / 滚动条…），
  --   而它**不只被「切到本 Tab」调用** —— 打开配置窗时无条件被调一次（EVAL_HELP_CFG_TOGGLE）、
  --   方案管理弹窗应用改名时也被调（EVAL_PM_APPLY）⇒ 停在别的 Tab 时这些控件被重新 Show 出来，
  --   **盖在当前那一页上**（用户截图：全局页上叠着一整套技能列表）。
  --   ★可见性只由 **Tab 切换**负责（EVAL_HELP_CFG_SETTAB 的控件清单 Show/Hide，本项目的可见性契约）；
  --     所以这里**只在「一键宏」Tab 正激活时才动显隐**，数据（文字 / 配色 / 图标 / 品阶）照旧每次都刷。
  --   ★顺序也对得上：SETTAB(2) 先把本页控件全 Show，再调本函数把「没有对应技能的空行」Hide 掉。
  local warTabOn = (cfgWin.tab == 2)
  local w2 = warCfg()
  for i, pb in ipairs(warUI.profBtns) do
    local prof = w2.profiles[i]
    if prof then
      pb.text:SetText(tostring(prof.name or ("方案" .. i)))
      local sel = (w2.activeProfile or 1) == i
      -- ★★★1.73.48 用户：「方案列表的图标和配色方案采用相同规则」——即**案例模版那一套**：
      --   图标 = 该方案品阶的 IconSem 纹理；文字色 = 品阶色；底色 = 品阶色 × 0.22（当前激活 × 0.45）。
      --   ★算不出品阶（老存档 / 坏数据 / Share 未载入）→ **如实退回**原来的暗金底 + 暖色字，**不硬编一个品阶**。
      -- ★★★1.73.49 用户：「品阶每次打开方案自动计算完善」⇒ 每次刷新**当场按方案内容重算**（不看缓存），
      --   并**计数**（判据要能证明「这次打开真的算了」，而不是只看界面长得对）。
      local trgb, tidx = nil, nil
      warProfTierCalc = warProfTierCalc + 1
      -- ★1.73.58 品阶判定抽成 uiProfileTierRGB（**方案列表与战斗信息UI 方案行共用同一份**，不再各写一遍）
      trgb, tidx = uiProfileTierRGB(prof)
      if trgb then
        local k = sel and 0.45 or 0.22
        pcall(pb.bg.SetVertexColor, pb.bg, trgb.r * k, trgb.g * k, trgb.b * k, 1)
        pcall(pb.text.SetTextColor, pb.text, trgb.r, trgb.g, trgb.b)
        if pb.icon then
          -- ★★★1.73.49 真机「图标还是黑的」的根因：`EVAL_SHARE_SEAL_ICON` **返回两个值**（路径 + 文件名），
          --   直接**内联成实参**时 Lua 会把两个都展开 → 实际调用成了 `SetTexture(路径, 文件名)`；
          --   而本客户端的 `SetTexture` 第二参是 **wrap 模式**（现代签名）→ 拿到一个字符串 → 尺寸对、**整块纯黑**
          --   （正是用户截图里那个 13×13 的黑方块）。★模板窗那边写的是 `local tiPath = …` 再传 → 一直正常。
          --   ⇒ ① 只取第一个返回值；② 写完**读回来确认**（本项目在 ChatFrame_OnEvent 上吃过「写成功 ≠ 写进去」的亏）。
          local ipath = EVAL_SHARE_SEAL_ICON(tidx)
          if type(ipath) == "string" and ipath ~= "" then
            pcall(pb.icon.SetTexture, pb.icon, ipath)
            local okr, got = pcall(pb.icon.GetTexture, pb.icon)
            if (not okr) or type(got) ~= "string" or got == "" then
              warUI.iconNoTex = (warUI.iconNoTex or 0) + 1 -- 如实记账（探针会打印它）
            end
            if warTabOn then pcall(pb.icon.Show, pb.icon) end
          else
            if warTabOn then pcall(pb.icon.Hide, pb.icon) end
          end
        end
      else
        pcall(pb.bg.SetVertexColor, pb.bg, sel and 0.45 or 0.16, sel and 0.35 or 0.13, sel and 0.10 or 0.08, 1)
        pcall(pb.text.SetTextColor, pb.text, sel and 1 or 0.75, sel and 0.9 or 0.72, sel and 0.4 or 0.6)
        if pb.icon and warTabOn then pb.icon:Hide() end
      end
    elseif i == table.getn(w2.profiles) + 1 then
      pb.text:SetText("+")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.10, 0.10, 0.10, 1)
      if pb.icon and warTabOn then pb.icon:Hide() end
    else
      pb.text:SetText("")
      pcall(pb.bg.SetVertexColor, pb.bg, 0.06, 0.05, 0.04, 1)
      if pb.icon and warTabOn then pb.icon:Hide() end
    end
    -- [删] 仅存在的方案显示；待确认状态红色高亮
    if pb.del then
      if prof then
        if warTabOn then pb.del:Show() end
        local armed = (warUI.delArm == i) and (GetTime() - (warUI.delArmT or 0) < 5)
        pcall(pb.delBg.SetVertexColor, pb.delBg, armed and 0.75 or 0.25, 0.10, 0.10, 1)
      else
        if warTabOn then pb.del:Hide() end
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
      if warTabOn then pcall(warUI.scrollUp.Show, warUI.scrollUp) pcall(warUI.scrollDn.Show, warUI.scrollDn) end
    else
      if warTabOn then pcall(warUI.scrollUp.Hide, warUI.scrollUp) pcall(warUI.scrollDn.Hide, warUI.scrollDn) end
    end
  end
  for ri, row in ipairs(warUI.rows) do
    local r = p and p.skills[ri + warUI.offset]
    local widgets = { row.chk, row.icon, row.name, row.conds, row.up, row.dn, row.edit, row.del }
    for _, wgt in ipairs(widgets) do
      -- ★1.73.56 显隐只在「一键宏」Tab 激活时动（见函数开头 warTabOn 的说明）
      if warTabOn then
        if r then pcall(wgt.Show, wgt) else pcall(wgt.Hide, wgt) end
      end
    end
    if r then
      if warTabOn then
        if r.enabled ~= false then row.mark:Show() else row.mark:Hide() end
      end
      local t0 = wicon(r.skill)
      if t0 then
        pcall(row.icon.SetTexture, row.icon, t0)
        pcall(row.icon.SetVertexColor, row.icon, 1, 1, 1)
      else
        uiSolid(row.icon, 0.25, 0.25, 0.25, 1)
      end
      row.name:SetText(tostring(r.skill) .. (r.rank and ("(" .. tostring(r.rank) .. ")") or "")) -- ★1.72.4 有等级才显示（默认仍是纯技能名）
      row.conds:SetText(uiEsc(EVAL_GROUP_STR(r.groups, true))) -- 1.61.1 | 显示转义（★1.73.12 界面走本地化名）
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
  -- ★★★1.73.63 彩蛋闸门检查：本函数是**方案/技能任何改动的汇聚点**（增删方案、编辑技能保存、导入、切 Tab 都走它）
  --   ⇒ 彩蛋的自动触发挂在这里最省事也最不容易漏（检查本身很便宜，且播报过就早退）。
  if type(EVAL_TITLE_EGG_CHECK) == "function" then pcall(EVAL_TITLE_EGG_CHECK) end
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
  if idx == 6 and type(EVAL_PH_REFRESH) == "function" then pcall(EVAL_PH_REFRESH) end -- 抓宠帮手
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

-- ★1.71.24 管理窗几何（供「两段都在窗内、有序排开」的断言读**生产真值**，不写死常量）
function EVAL_TEST_PM_GEO()
  if not (pmUI and pmUI.root) then return nil end
  -- ★GetPoint 返回 (point, relTo, relPoint, x, y) 五个值——取第 5 个 y
  local function yOf(f)
    if not f then return nil end
    local ok, _p, _r, _rp, _x, y = pcall(f.GetPoint, f, 1)
    return (ok and type(y) == "number") and y or nil
  end
  local okh, hh = pcall(pmUI.root.GetHeight, pmUI.root)
  return {
    h = (okh and hh) or nil,
    secNameY = yOf(pmUI.secName), secKeyY = yOf(pmUI.secKey),
    keyBtnY = yOf(pmUI.keyBtn), infoY = yOf(pmUI.infoText), btnY = yOf(pmUI.saveBtn),
  }
end

-- ★1.71.24 全插件还剩几个「方案管理类」弹窗（合并的**结构判据**）：
--   ★行为断言抓不到「调用点改回旧名字」——因为旧名字是别名、开出来还是同一个窗
--     （变异 M1/M2 就是这么 SURVIVED 的）→ 必须直接**数窗**：只剩 pmUI 一个才算合并成功。
function EVAL_HELP_PM_WINDOW_COUNT()
  local n = 0
  if pmUI and pmUI.root then n = n + 1 end
  if type(rpUI) == "table" and rpUI.root then n = n + 1 end
  if type(bindUI) == "table" and bindUI.root then n = n + 1 end
  return n
end

-- ★1.71.24 配置窗是否可见（EVAL_HELP_CFG_TOGGLE 是**切换**语义，断言前必须先确认真开着）
function EVAL_TEST_CFG_VISIBLE()
  if not (cfgWin and cfgWin.root) then return false end
  local ok, v = pcall(cfgWin.root.IsVisible, cfgWin.root)
  return (ok and v) and true or false
end

-- ★1.71.24 交出配置窗的方案按钮真实控件（供「两处右键开同一个窗」的断言真的点它）
function EVAL_TEST_CFG_PROF()
  return cfgWin and cfgWin.profBtns and { btns = cfgWin.profBtns } or nil
end

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
    -- ★★★1.73.49 用户：「品阶每次打开方案自动计算完善」——不管这次落在哪个 Tab，**打开就按当前方案内容重算一遍**
    --   方案列表的品阶/图标/配色（SETTAB 只在 Tab=2 时刷；这里补一次，保证切过去的瞬间就是最新的）。
    if type(EVAL_WAR_TAB_REFRESH) == "function" then pcall(EVAL_WAR_TAB_REFRESH) end
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
  -- ★1.71.17 用户定稿：初始图标 = **力量祝福**（Spell_Holy_BlessingOfStrength，金色拳头，一眼是「增益/强化」）——
  --   她在图标库亲自挑过这枚当按钮图标（见 1.71.15），并要求初始默认也用同一枚；
  --   其次才是「工具箱」气质：扳手 > 工程学 > 齿轮 > 小装置 > 书（★大写化后做前缀匹配，名尾的 _TEX 不妨碍）
  local CANDS = { "^SPELL_HOLY_BLESSINGOFSTRENGTH", "^INV_MISC_WRENCH", "^TRADE_ENGINEERING", "^INV_MISC_GEAR", "^INV_GIZMO", "^INV_MISC_BOOK" }
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
-- ★★派发方案演进（四次试错，用户实测逐条淘汰；**最终定案见下方「方案快捷键派发」大段注释**）：
--   ① CLICK 隐藏按钮派发（vanilla 经典招）——客户端把「CLICK <按钮>:LeftButton」解析岔了，
--     **触发被挂到鼠标左右键**、原始转屏被顶掉（插件确实被触发 = 链路通、命令串形态错）→ 弃用；
--   ② 裸命令名 `EVAL_GO<i>` —— **绑定表接受但不派发**（用户实测：绑定成功、按键不触发）；
--   ③ Bindings.xml 登记 —— **本客户端根本不读插件的 Bindings.xml**（对照实验 + unrealUI 源码双重确认）→ 弃用；
--   ④ ★最终 = 命令名用**客户端自带的** ACTIONBUTTON<n> + 插件接管 ActionButtonDown/Up 翻译成 EVAL_GO(方案)。
-- ★持久化：绑定后 SaveBindings(GetCurrentBindingSet())——不存就随重登消失（实测当前 set = 1）。

-- 派发自检（纯函数语义）：客户端命令表里有没有 ACTIONBUTTON1~12 —— 这是本方案的**唯一外部前提**。
--   返回 12 = 前提成立（按键会被派发，插件接管后即可触发）；0 = 表里一条都没有（异常，如实报）；-1 = API 缺失。
function EVAL_BIND_XML_STATUS()
  if type(GetNumBindings) ~= "function" or type(GetBinding) ~= "function" then return -1 end
  local okN, n = pcall(GetNumBindings)
  if not (okN and type(n) == "number") then return -1 end
  local cnt = 0
  for i = 1, math.min(n, 600) do
    local okG, cmd = pcall(GetBinding, i)
    if okG and type(cmd) == "string" and string.find(cmd, "^ACTIONBUTTON%d+$") then cnt = cnt + 1 end
  end
  return cnt
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

-- 下拉选中回调（命名导出 = 测试能直调，不依赖真的点开下拉）：标题行不选、键名行进状态。
-- ★1.71.24 合并后进的是「方案管理窗」的状态（EVAL_PM_PICK）——旧名 EVAL_BIND_PICK 保留为别名。
--   ★这里引用的是**全局** EVAL_PM_PICK（定义在文件下方）；绝不能用 `local EVAL_PM_PICK` 前置声明，
--     否则会把下方那个全局定义整个遮住（Lua 词法作用域 —— 声明之后的名字都解析成 local，而实现写在声明之前）。
function EVAL_BIND_DD_PICK(rows, pi)
  local row = rows and rows[pi]
  if row and row.key and type(EVAL_PM_PICK) == "function" then EVAL_PM_PICK(row.key) end
end

function EVAL_BIND_PICK(key)
  if type(EVAL_PM_PICK) == "function" then return EVAL_PM_PICK(key) end
end

-- 逻辑层（UI 与测试共用一份实现）：绑定 / 清除。★换键时把旧键解绑；绑定后立刻 SaveBindings 持久化。
--   ★1.71.22 最终形态：命令名 = 客户端**自己认**的 ACTIONBUTTON<n>（实测 12 条在命令表里），
--     派发由本文件下方的 EVAL_BIND_INSTALL() 接管 ActionButtonUp 完成（不占宏名额、不占动作格）。
function EVAL_BIND_DO(pidx, key)
  if type(key) ~= "string" or key == "" then return false, "nokey" end
  local w2 = warCfg()
  if not (w2.profiles and w2.profiles[pidx]) then return false, "noprof" end
  -- 已有格就直接复用；没有才挑一个**完全无主**的格（不抢用户已有的键位）
  w2.bindSlots = w2.bindSlots or {}
  local slot = w2.bindSlots[pidx]
  if type(slot) ~= "number" then
    slot = EVAL_BIND_FREE_SLOT()
    if not slot then return false, "noslot" end
    w2.bindSlots[pidx] = slot
  end
  local cmd = EVAL_BIND_SLOT_CMD(slot)
  if not cmd then return false, "noslotcmd" end
  local ok, r = pcall(SetBinding, key, cmd)
  if not (ok and r) then return false, "reject" end
  w2.bindKeys = w2.bindKeys or {}
  local old = w2.bindKeys[pidx]
  if type(old) == "string" and old ~= "" and old ~= key then pcall(SetBinding, old) end -- 换键：解掉旧键
  w2.bindKeys[pidx] = key
  if type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  -- 保证接管已装上（运行中立即生效；装过就是幂等的 no-op）
  EVAL_BIND_INSTALL()
  return true, key, slot
end

-- ★1.71.20 左键点「方案」标签：把当前绑定情况打到聊天框（用户：「左键点击<标题方案>.日志打印方案绑定情况.」）。
--   ★只打印、不动任何绑定；没有绑定时**如实说没有**（不是静默什么都不出）。
function EVAL_BIND_STATUS()
  local w2 = warCfg()
  local n = 0
  say("— " .. L("BIND_L_TIP_T") .. " —")
  if w2.bindKeys then
    for i = 1, table.getn(w2.profiles or {}) do
      local key = w2.bindKeys[i]
      if type(key) == "string" and key ~= "" then
        n = n + 1
        say(string.format(L("BIND_ST_ROW"), i, tostring(w2.profiles[i].name or i), key))
      end
    end
  end
  if n == 0 then say(L("BIND_ST_NONE")) end
  return n
end

-- ★1.71.19 一键清除**全部**自定义绑定（右键点「方案」标签）：逐键解绑 + 清表 + 存档；返回清掉的个数。
function EVAL_BIND_CLEAR_ALL()
  local w2 = warCfg()
  local n = 0
  if w2.bindKeys then
    for _, key in pairs(w2.bindKeys) do
      if type(key) == "string" and key ~= "" then pcall(SetBinding, key) n = n + 1 end
    end
    w2.bindKeys = nil
  end
  -- 格映射一并清掉（我们只是借用了这个命令行，没动过格子里的东西，无需还原动作格）
  w2.bindSlots = nil
  if type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  return n
end

function EVAL_BIND_CLEAR(pidx)
  local w2 = warCfg()
  local old = w2.bindKeys and w2.bindKeys[pidx]
  if type(old) == "string" and old ~= "" then pcall(SetBinding, old) end
  if w2.bindKeys then w2.bindKeys[pidx] = nil end
  if w2.bindSlots then w2.bindSlots[pidx] = nil end
  if type(SaveBindings) == "function" then
    pcall(SaveBindings, (type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet()) or 1)
  end
  return true
end

-- ============================================================================
-- ★1.71.22 方案快捷键派发：接管 ActionButtonUp / ActionButtonDown（实测可行路线）
--
--   ★为什么不是 Bindings.xml（两条独立证据一致判死）：
--     ① 本机对照实验（2026-09-18）：把 ArchiTotem **启用**后**完整重启**客户端，
--        它的 CAST_EARTH_TOTEM 依然不在命令表里（连一条 CAST_* 都没有），表恒为 226 行。
--     ② 同机同客户端的 unrealUI 插件在源码注释里写明它自己踩过同一个坑（2026-08-19 实测）：
--        「Bindings.xml declarations -- unrealUI's 60 commands were absent from a
--          225-entry binding table」→ 它最后也放弃这条路（「nothing here depends on that」）。
--     ③ 结论：SetBinding 会**照单全收**任何字符串（Keybinds.ini 里真能看到那行），
--        但客户端的命令表只含它自带的条目 → 按键时查不到执行体 → **静默无反应**。
--
--   ★可行路线（实测 type 已核）：客户端把 ACTIONBUTTON<n> 的按键派发到**全局函数**
--     ActionButtonDown(index) / ActionButtonUp(index) —— 插件**可以替换这两个全局**。
--       /eh go diag 实测：ActionButtonDown=function ActionButtonUp=function
--                        MultiActionButtonDown=function MultiActionButtonUp=function
--                        SetOverrideBindingClick=nil ClearOverrideBindings=nil  （后者确认堵死）
--
--   链路：SetBinding(键, "ACTIONBUTTON<格>")  ← 客户端**自己会派发**（12 条命令实测在表里）
--         + 接管 ActionButtonUp，把「格号 → 方案号」的映射翻译成 EVAL_GO(方案号)。
--   ★零成本：不占宏名额、不占动作格、不改用户的任何现有按键、游戏运行中立即生效。
--
--   ★代价（unrealUI 源码明确警告，必须自己补回）：
--     本客户端是按**物理键**触发 ActionButtonDown/Up 的，不是按精确组合键 ——
--     替换掉原函数就丢掉了客户端原有的「组合键保护」，
--     于是「绑到 ACTIONBUTTONn 的裸键」在按住 Alt/Ctrl/Shift 时也会触发。
--     这里按 unrealUI 的做法重建守卫：按住修饰键时若该组合键另有归属，就不当作动作条按键。
-- ============================================================================

-- 动作格命令名（纯函数，测试直测）：客户端**自己认**的只有 ACTIONBUTTON1..12（主条 12 格）。
function EVAL_BIND_SLOT_CMD(slot)
  if slot and slot >= 1 and slot <= 12 then return "ACTIONBUTTON" .. tostring(slot) end
  return nil
end

-- 原始全局（接管前保存；OnDisable/清理时还回去，绝不把客户端留在被改状态）
EVAL_BIND_ORIG_DOWN = nil
EVAL_BIND_ORIG_UP = nil

-- 格号 → 方案号 映射（从配置重建，纯读；返回 table）。★单一真源 = cfg.bindKeys/bindSlots
function EVAL_BIND_SLOT_MAP()
  local w2 = warCfg()
  local map = {}
  local slots = w2.bindSlots
  if type(slots) == "table" then
    for pidx, slot in pairs(slots) do
      if type(slot) == "number" then map[slot] = pidx end
    end
  end
  return map
end

-- 组合键守卫：按住修饰键时，若「修饰键+该键」另有归属 → 这次按键不该算作动作条按键。
--   ★判据严格照抄 unrealUI：拿该格命令的主键，拼出修饰前缀，查 GetBindingAction；
--     不等于本格命令 = 被别的功能占了 → 不触发（把这一下让给客户端）。
function EVAL_BIND_MODIFIER_STOLEN(index)
  local prefix = ""
  if type(IsAltKeyDown) == "function" and IsAltKeyDown() then prefix = prefix .. "ALT-" end
  if type(IsControlKeyDown) == "function" and IsControlKeyDown() then prefix = prefix .. "CTRL-" end
  if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
  if prefix == "" then return false end -- 没按修饰键 = 不可能被偷
  local cmd = EVAL_BIND_SLOT_CMD(index)
  if not cmd or type(GetBindingKey) ~= "function" then return false end
  local okk, k1, k2 = pcall(GetBindingKey, cmd)
  if not okk then return false end
  for _, k in ipairs({ k1, k2 }) do
    if type(k) == "string" and k ~= "" and not string.find(k, "-", 1, true) then
      -- 裸键 → 拼出组合形态，看它是不是被别的命令占着
      local chord = prefix .. k
      local oka, act = pcall(GetBindingAction, chord)
      if oka and type(act) == "string" and act ~= "" and act ~= cmd then return true end
    end
  end
  return false
end

-- 文本输入中不该触发动作（聊天框开着时按键是文字）——照抄 unrealUI 的守卫
function EVAL_BIND_TEXT_BLOCKS()
  if type(ChatFrame1) == "table" and type(ChatFrame1.IsShown) == "function" then
    local ok, shown = pcall(ChatFrame1.IsShown, ChatFrame1)
    if ok and shown then
      local e = ChatFrame1.editBox
      if type(e) == "table" and type(e.IsShown) == "function" then
        local ok2, s2 = pcall(e.IsShown, e)
        if ok2 and s2 then return true end
      end
    end
  end
  return false
end

-- ★接管：把「动作格被按下」翻译成「执行对应方案」。返回 true = 接管成功（可断言）。
function EVAL_BIND_INSTALL()
  if EVAL_BIND_ORIG_UP then return true end -- 幂等：装过就不再包一层
  if type(ActionButtonUp) ~= "function" or type(ActionButtonDown) ~= "function" then return false end
  EVAL_BIND_ORIG_DOWN = ActionButtonDown
  EVAL_BIND_ORIG_UP = ActionButtonUp
  local origDown, origUp = EVAL_BIND_ORIG_DOWN, EVAL_BIND_ORIG_UP
  ActionButtonDown = function(index)
    -- 只有我们占的格子才吞；其余原样交给客户端（绝不改变别人的行为）
    local pidx = EVAL_BIND_SLOT_MAP()[index]
    if pidx and not EVAL_BIND_TEXT_BLOCKS() and not EVAL_BIND_MODIFIER_STOLEN(index) then return end
    return origDown(index)
  end
  ActionButtonUp = function(index)
    local map = EVAL_BIND_SLOT_MAP()
    local pidx = map[index]
    if pidx and not EVAL_BIND_TEXT_BLOCKS() and not EVAL_BIND_MODIFIER_STOLEN(index) then
      if type(EVAL_GO) == "function" then pcall(EVAL_GO, pidx) end
      return
    end
    return origUp(index)
  end
  return true
end

-- 卸下接管（还原全局）——重置配置/禁用时用，保证不把客户端留在被改状态
function EVAL_BIND_UNINSTALL()
  if EVAL_BIND_ORIG_DOWN then ActionButtonDown = EVAL_BIND_ORIG_DOWN end
  if EVAL_BIND_ORIG_UP then ActionButtonUp = EVAL_BIND_ORIG_UP end
  EVAL_BIND_ORIG_DOWN, EVAL_BIND_ORIG_UP = nil, nil
  return true
end

-- 找一个空闲的动作格命令：优先「该格没放东西 且 该命令没绑键」的（完全无主，不抢用户键位）。
--   ★用户 1.71.22 追问「动作条前面都有具体站位了」→ 所以两轮挑；返回 slot 或 nil。
function EVAL_BIND_FREE_SLOT(allowTaken)
  local fallback = nil
  for s = 1, 12 do
    if not EVAL_BIND_SLOT_MAP()[s] then -- 没被我们占用
      local cmd = EVAL_BIND_SLOT_CMD(s)
      local occupied = false
      if type(HasAction) == "function" then
        local okh, has = pcall(HasAction, s)
        occupied = (okh and has) and true or false
      end
      local taken = false
      if cmd and type(GetBindingKey) == "function" then
        local okk, ks = pcall(GetBindingKey, cmd)
        taken = (okk and type(ks) == "string" and ks ~= "")
      end
      if not occupied and not taken then return s end      -- ① 完全无主：格子空 + 键没人用
      if not occupied and fallback == nil then fallback = s end -- ② 备选：格子空但键被占
    end
  end
  if allowTaken then return fallback end
  return fallback
end

-- ===== 方案管理弹窗断言钩子（1.71.24：重命名 + 快捷键合并后的单一弹窗） =====
-- ★名字保留 EVAL_TEST_BIND_*（既有断言组 98/99/100 都在用）——语义已扩为「方案管理窗」。
-- ★读真控件/真数据，不读常量。
function EVAL_TEST_BIND_UI()
  local out = { built = (pmUI.root ~= nil) and true or false, pidx = pmUI.pidx, selKey = pmUI.selKey,
    shown = false, title = nil, cur = nil, info = nil, echo = nil }
  if pmUI.root then
    local ok, v = pcall(pmUI.root.IsVisible, pmUI.root)
    out.shown = (ok and v) and true or false
  end
  if pmUI.title then
    local ok, t = pcall(pmUI.title.GetText, pmUI.title)
    out.title = ok and tostring(t or "") or nil
  end
  if pmUI.curText then
    local ok, t = pcall(pmUI.curText.GetText, pmUI.curText)
    out.cur = ok and tostring(t or "") or nil
  end
  if pmUI.infoText then
    local ok, t = pcall(pmUI.infoText.GetText, pmUI.infoText)
    out.info = ok and tostring(t or "") or nil
  end
  if pmUI.echo then
    local ok, t = pcall(pmUI.echo.GetText, pmUI.echo)
    out.echo = ok and tostring(t or "") or nil
  end
  return out
end
-- ★改名后弹窗要真的开：合并窗的「保存」按钮（改名 + 绑键一次提交）
function EVAL_TEST_BIND_DO_BTN() return pmUI.saveBtn end
function EVAL_TEST_BIND_CLOSE() if pmUI.root then pmUI.root:Hide() end end
-- ★合并窗专有：直接驱动输入框（EditBox 不渲染也能测逻辑），返回是否成功
function EVAL_TEST_PM_SETNAME(nm)
  if not pmUI.eb then return false end
  local ok = pcall(pmUI.eb.SetText, pmUI.eb, tostring(nm or ""))
  if ok and pmUI.echo then pcall(pmUI.echo.SetText, pmUI.echo, tostring(nm or "")) end
  return ok
end


-- ============ 状态信息 UI（展示 Cat 式角色状态表 EVAL_HELP_STATE 的实时值） ============
-- /eh st 开关；标题栏拖动（位置记忆+越界回归）；每 0.15s 刷新一次 EVAL_HELP_UPDATE_STATE()。
-- 内容 = 状态模块全部字段：玩家数值/战斗计时/姿态/修饰键/普攻 + 目标可攻击/可流血/精英Boss 等。

local stui = { root = nil, body = nil, title = nil }
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
  -- ★1.73.59 与战斗信息UI 同款：清掉上一轮的徽标引用（ui 表是复用的，不清就会写**幽灵控件**）
  stui.titleText, stui.tierText, stui.planText = nil, nil, nil
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
  -- ★★★1.73.59 用户：「状态信息名称和头衔 参考战斗信息做相同的布局」——原来标题**居中**，现在与战斗信息UI 一致：
  --   标题**贴左**，右边依次排 档位徽标 → 头衔（同一个公用件 uiTitleBadgesMake，同一份刷新实现）。
  title:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
  pcall(title.SetJustifyH, title, "LEFT")
  pcall(title.SetNonSpaceWrap, title, false)
  -- ★★★1.73.53 用户（截图确认）：「战斗记录（状态信息UI）标题将玩家角色显示」——
  --   与战斗信息UI 同一条规矩：有玩家名就用玩家名；取不到退回窗口自己的名字（G_ST_TITLE，走语言包，不硬编码中文）。
  title:SetText(uiTitleName("G_ST_TITLE"))
  stui.title = title -- ★读值口（判据读**真控件**，不读我们自己的意图）
  stui.titleText, stui.tierText, stui.planText = uiTitleBadgesMake("st", titleBar, 1, title) -- ★1.73.59/1.73.62 与战斗信息UI 同一套（头衔 → 品阶 → 方案名）
  uiTitleBadgeRefresh() -- 建完立刻写一次（不等 tick，免得开窗先空一下；与战斗信息UI 同款）
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
  -- ★1.73.59 与战斗信息UI 同款两个徽标（档位 + 头衔）也要跟着刷 —— 登记表里一次刷完，两个窗口共用一份实现。
  uiTitleBadgeRefresh()
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
        ago, tostring(e.skill) .. (e.rank and ("(" .. tostring(e.rank) .. ")") or ""), -- ★1.72.4 等级一并显示
        (e.target and e.target ~= "") and ("→" .. e.target) or "",
        (e.why and e.why ~= "") and (" |cff909090← " .. tostring(e.why) .. "|r") or ""))
      if e.trace and e.trace ~= "" then
        table.insert(lines, "  |cff70b070" .. e.trace .. "|r")
      end
    end
  end
  stui.body:SetText(table.concat(lines, "\n"))
end

-- ★★★1.73.53 读值口：状态信息UI 标题栏的**真实文本**（判据读真控件；用户要求它显示玩家角色名）
-- ★1.73.59 状态信息UI 是否可见（EVAL_HELP_ST_TOGGLE 是**切换**语义，断言前要先确认真开着）
function EVAL_TEST_ST_VISIBLE()
  if not (stui and stui.root) then return false end
  local ok, v = pcall(stui.root.IsVisible, stui.root)
  return (ok and v) and true or false
end
function EVAL_TEST_ST_TITLE()
  if not stui.title then return nil end
  local ok, v = pcall(stui.title.GetText, stui.title)
  return (ok and type(v) == "string") and v or nil
end
-- ★★★1.73.59 读值口：状态信息UI 标题栏的**布局与两个徽标**（用户：「状态信息名称和头衔 参考战斗信息做相同的布局」）。
--   一律读**真控件**（GetText / GetPoint / GetJustifyH / GetTextColor）—— 不读我们自己的记账；
--   与 EVAL_TEST_UI_TITLEBAR 同款字段，便于断言「两个窗口同一套布局」。
function EVAL_TEST_ST_TITLEBAR()
  local out = { title = nil, titlePoint = nil, titleJustify = nil, titleX = nil, tier = nil, ptitle = nil }
  local function fsOf(fs, prefix)
    if not fs then return end
    local okt, tv = pcall(fs.GetText, fs)
    if okt and type(tv) == "string" then out[prefix] = tv end
    local okp, pt, rel, rp, px = pcall(fs.GetPoint, fs)
    if okp and type(pt) == "string" then
      out[prefix .. "Point"], out[prefix .. "RelTo"], out[prefix .. "RelPoint"], out[prefix .. "X"] = pt, rel, rp, px
    end
    local okc, cr, cg, cb = pcall(fs.GetTextColor, fs)
    if okc and type(cr) == "number" then out[prefix .. "Color"] = { cr, cg, cb } end
  end
  if stui.title then
    local okt, tv = pcall(stui.title.GetText, stui.title)
    if okt and type(tv) == "string" then out.title = tv end
    local okp, pt, _rel, _rp, px = pcall(stui.title.GetPoint, stui.title)
    if okp and type(pt) == "string" then out.titlePoint = pt out.titleX = px end
    local okj, jv = pcall(stui.title.GetJustifyH, stui.title)
    if okj and type(jv) == "string" then out.titleJustify = jv end
    out.titleFs = stui.title
  end
  fsOf(stui.tierText, "tier")
  fsOf(stui.titleText, "ptitle")
  fsOf(stui.planText, "plan")
  out.tierFs, out.ptitleFs, out.planFs = stui.tierText, stui.titleText, stui.planText
  return out
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

-- ★★★1.73.27 用户问：「能量对法系职业是否也是魔法值？名称完善下。」
--   【答】是 —— 本客户端沿用 1.12 的资源约定（UnitPowerType：0=法力 / 1=怒气 / 2=集中值 / 3=能量）：
--     法系职业的「能量」就是**法力（魔法值）**。Core 的 EVAL_POWERLABEL() 会按**当前形态**实时给出正确名字
--     （德鲁伊变豹=能量、变熊=怒气、人形态=法力）⇒ **不能在建表时定死**，必须显示的那一刻才取。
--   ⇒ 下拉与按钮上的「怒气/能量」「能量%」换成**实时资源名**（法力 / 法力%），与方案行、导出文本一致。
local function seTypeLabel(id)
  local key = string.upper(tostring(id or ""))
  local function powerName()
    if type(EVAL_POWERLABEL) ~= "function" then return nil end
    local ok, v = pcall(EVAL_POWERLABEL)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
  end
  if key == "POWER" then
    return powerName() or L("CT_" .. key)
  elseif key == "POWERPCT" then
    local p = powerName()
    if p then return p .. "%" end
  end
  return L("CT_" .. key)
end
-- 读值口：断言与 UI 读**同一份**名字（本项目「不许在断言里另写一套判据」的纪律）
function EVAL_TEST_SE_TYPELABEL(id) return seTypeLabel(id) end
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
  local lines = { "|cffffd100" .. seTypeLabel(id) .. "|r" }
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

-- ★1.72.4 测试观测口/注入口：「等级元素默认隐藏、设了才显示」必须能被断言（否则只是这一次的手工动作）
function EVAL_TEST_SE_RANK()
  local w = seUI and seUI.rankW
  local shown, nameShown, txt = false, false, nil
  if w and w.btn and w.btn.IsShown then
    local ok, v = pcall(w.btn.IsShown, w.btn)
    shown = (ok and v) and true or false
    if seUI.rankName and seUI.rankName.IsShown then
      local ok2, v2 = pcall(seUI.rankName.IsShown, seUI.rankName)
      nameShown = (ok2 and v2) and true or false
    end
  end
  if seUI and seUI.rankName and seUI.rankName.GetText then
    local ok3, v3 = pcall(seUI.rankName.GetText, seUI.rankName)
    if ok3 then txt = v3 end
  end
  return { exists = (w ~= nil), shown = shown, nameShown = nameShown,
           rank = (seUI and seUI.ed and seUI.ed.rank) or nil, text = txt }
end
-- ★1.72.4 断言入口：走**真实 OnEnter**（写 tooltip → 桩记录行），返回是否真的挂上了。
--   ★为什么不让测试自己掏控件：seUI 是本文件的 **local**，测试脚本够不着（1.72.4 实测：
--     测试里写 seUI.rankW.btn 全是 nil，断言看起来在验接线、其实什么都没读到）。
function EVAL_TEST_SE_RANK_TIP()
  local w = seUI and seUI.rankW
  if not (w and w.btn and w.btn.GetScript) then return nil end
  local ok, fn = pcall(w.btn.GetScript, w.btn, "OnEnter")
  if not (ok and type(fn) == "function") then return nil end
  fn()
  return true
end
function EVAL_TEST_SE_SET_RANK(rk)
  if not (seUI and seUI.ed) then return false end
  seUI.ed.rank = (rk == nil or rk == "") and nil or rk
  EVAL_HELP_SE_REFRESH()
  return true
end
-- ★走**真实 OnClick 闭包**：右键入口这条接线必须被执行（只调判定函数测不出「压根没接上」）
function EVAL_TEST_SE_RANK_CLICK(btn)
  if not (seUI and seUI.skillBtn) then return false end
  local ok, fn = pcall(seUI.skillBtn.GetScript, seUI.skillBtn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn(seUI.skillBtn, btn or "RightButton")
  return true
end
-- ★1.73.2 可驱散类型集合的本地化清单（tooltip 用）：62px 的窄格只列得下 2 项，
--   完整清单必须**另有地方给全**——不因为格子窄就把用户选的信息藏掉（本项目「绝不静默截断」）。
local function seDispelAllNames(ids)
  local out = {}
  for _, v in ipairs(ids or {}) do table.insert(out, L("DS_T_" .. string.upper(tostring(v)))) end
  return table.concat(out, "/")
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
  -- ★1.72.4 等级元素：**常显**（用户：「默认值显示技能」）——没设等级时显示「技能」，设了就显示该等级。
  --   ★「隐藏入口」被用户当场否掉（「技能右侧的等级配置没显示」）：入口藏起来 = 用户找不到功能，
  --     所以元素一直在，默认文案本身就是「当前用的是技能本身（不指定等级）」这层含义。
  if seUI.rankName then seUI.rankName:SetText(ed.rank or L("SE_RANK_ANY")) end
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
      row.typeBtn.text:SetText(seTypeLabel(td.id)) -- ★1.73.27 实时资源名（法系显示「法力」）
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
      -- ★1.74.6 自身/目标 debuff 也要「负面类型」（用户：「查看自身/目标debuff 条件类型配置项，
      --   需要参考队伍debuff 配置支持 debuff 负面类型功能」）—— 与 teamDebuff/candDebuff **同一支控件**、同一份 EVAL_DISPEL_LIST 文案。
      local isDebuffKind181 = ((td.base or td.id) == "teamDebuff") or td.id == "candDebuff"
                                or td.id == "pDebuff" or td.id == "hasDebuff"
      if isDebuffKind181 then -- ★1.71.3 候选者debuff 也要类型下拉
        -- ★1.73.2 多选：显示串 = 0 项「任意负面」/ 1 项该类型名 / ≥2 项「A/B…」
        --   窄格（62px）只列得下 2 项，多的用 …；**完整清单走 tooltip**（不因为格子窄就藏信息）
        local ids = EVAL_DISPEL_LIST(cd.dt)
        local n = table.getn(ids)
        local lbl = L("DS_T_ANY")
        if n == 1 then
          lbl = L("DS_T_" .. string.upper(ids[1]))
        elseif n >= 2 then
          local parts = { L("DS_T_" .. string.upper(ids[1])), L("DS_T_" .. string.upper(ids[2])) }
          lbl = table.concat(parts, "/") .. (n > 2 and "…" or "")
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
      row.preview:SetText(EVAL_COND_STR(cd, true)) -- ★1.73.12 界面显示走本地化名（导出仍走 token）
      -- ★让位：这两格占的正是行内预览的位置 → 队伍/团员那 8 行不显示行内预览（底部整串预览照旧）
      if isTeamKind then pcall(row.preview.Hide, row.preview) else pcall(row.preview.Show, row.preview) end
      pcall(row.del.btn.Show, row.del.btn)
    end
  end
  -- 底部实时预览（整串条件）
  -- ★1.73.12 底部预览是**给人看的** → 走本地化显示（第二个参数 true）；导出/存档仍用 token 形态
  seUI.preview:SetText(uiEsc(EVAL_GROUP_STR(seLinearToGroups(ed.conds), true))) -- 1.61.1 | 显示转义
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
    -- ★1.74.8 取消自身buff：同样弹名字输入（空名不接受 —— 空名会变成「取消全部」，语义完全不同，
    --   必须让用户显式选那一项，不能靠留空**误**触发「全取消」）
    if v == L("SE_PICK_CANCELBUFF") then
      EVAL_TN_OPEN(L("SE_TN_CANCELBUFF"), "", function(nm)
        if nm and nm ~= "" then seUI.ed.skill = "取消自身buff:" .. nm EVAL_HELP_SE_REFRESH() end
      end)
      return
    end
    seUI.ed.skill = string.match(v, "^(物品[:：].-)×%d+$") or v
    seUI.ed.rank = nil -- ★1.72.4 换技能必须清空旧等级（那个等级对新技能无效，留着只会如实失败）
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
  -- ★1.72.4 「释放指定等级」下拉（用户要求：技能右侧可选 技能/等级1/等级2…；默认值显示「技能」）。
  --   ★两个入口共用本函数：① 点技能名右侧的等级元素 ② 技能名上右键（快捷方式）。
  --   ★选项来自**法术书**（GetSpellName 第二返回 = rank/subtext），保证括号内文本与客户端逐字相符
  --     （CastSpellByName 的括号内容必须与 subtext 完全一致，所以不能自己编「等级 N」）。
  --   ★默认「技能」= 老行为（技能须在动作条上、走 UseAction）。
  --   ★锚点用技能名按钮：位置稳定，弹出不受等级元素自身文案宽度影响。
  local function seOpenRankMenu()
    if not (seUI and seUI.ed) then return end
    local ranks = EVAL_SPELLBOOK_RANKS(seUI.ed.skill)
    if table.getn(ranks) == 0 then
      -- ★★「查不到」≠「没有」：法术书里读不到该技能的等级 → **如实说明**，
      --   绝不弹一个只有「技能」一项的残废下拉（用户只会以为功能坏了）。
      say(string.format(L("SE_RANK_NONE"), tostring(seUI.ed.skill)))
      return
    end
    local opts = { L("SE_RANK_ANY") }
    for i = 1, table.getn(ranks) do opts[i + 1] = ranks[i] end
    EVAL_DD_OPEN(seUI.skillBtn, opts, function(pi)
      if not seUI.ed then return end
      seUI.ed.rank = (pi == 1) and nil or ranks[pi - 1]
      EVAL_HELP_SE_REFRESH()
    end)
  end
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
  -- ★1.72.4 技能名右键 = 设置/清除释放等级（等级元素默认隐藏 → 这是默认状态下的唯一入口）
  --   ★必须链式转发 seBtn 已挂的左键处理器：SetScript 是单槽位，直接覆盖 = 左键点技能名打不开列表。
  pcall(skBtn.RegisterForClicks, skBtn, "LeftButtonUp", "RightButtonUp")
  local skPrevClick = skBtn:GetScript("OnClick")
  skBtn:SetScript("OnClick", function(a, b)
    local mbtn = (type(a) == "string" and a) or (type(b) == "string" and b) or (type(arg1) == "string" and arg1) or "LeftButtonUp"
    if string.find(mbtn, "RightButton", 1, true) then seOpenRankMenu() return end
    if skPrevClick then skPrevClick(a, b) end
  end)
  seUI.skillName = skName
  -- ★1.72.4 「释放指定等级」元素：**常显在技能名右侧**（用户：「默认值显示技能」）。
  --   文案 = 当前等级；没设等级时显示「技能」= 用技能本身（老行为：要求技能在动作条上、走 UseAction）。
  --   点它 / 右键技能名 都能开下拉；选项来自**法术书**（GetSpellName 第二返回），与 subtext 逐字相符。
  local rkW = seBtn(root, 218, -24, 88, 16, L("SE_RANK_ANY"), seOpenRankMenu)
  seUI.rankBtn = rkW.btn
  seUI.rankName = rkW.text
  seUI.rankW = rkW
  -- 悬停说明（就一个元素，文字太短说不清语义 → 用 tooltip 补；与技能名右键入口同一份说明）
  pcall(rkW.btn.EnableMouse, rkW.btn, true)
  rkW.btn:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(rkW.btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L("SE_RANK_TIP"), 1, 0.82, 0.3)
    GameTooltip:AddLine(L("SE_RANK_TIP2"), 0.62, 0.55, 0.40)
    GameTooltip:Show()
  end)
  rkW.btn:SetScript("OnLeave", function()
    if GameTooltip and GameTooltip.Hide then pcall(GameTooltip.Hide, GameTooltip) end
  end)
  local enChk = CreateFrame("Button", nil, root)
  enChk:SetWidth(14) enChk:SetHeight(14)
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
  local SE_MARK_X -- ★1.72.4 右对齐起点：在下面按窗口宽度反推（不再写死 x）
  seUI.marks = {}
  -- ★文案写成**字面量** L("SE_MARK_...")（而不是 tkey="..." 运行时拼）：
  --   静态 LANG KEY CHECK 才扫得到这三语言 4 个键（运行时拼的键正是它扫不到的盲区）。
  local SE_MARK_DEFS = {
    { tex = SE_MARK_UNAVAIL, tip = function() return { L("SE_MARK_UNAVAIL_T"), L("SE_MARK_UNAVAIL_D") } end },
    { tex = SE_MARK_TEST,    tip = function() return { L("SE_MARK_TEST_T"),    L("SE_MARK_TEST_D") }    end },
  }
  -- ★1.72.4 **右边对齐**（用户要求：「启动此技能开关 + 图标 右边对齐」）
  --   按窗口宽度反推起点（中文 660 / 西文 800，单一来源 seUI.W）：
  --   整组宽 = 勾选框 14 + 间隙 4 + 标签实测宽 enW + 间隙 14 + 图例 (N-1)*20+16，右侧留白 16。
  --   ★兜底：窗口再窄也不许越过等级下拉（218..306）→ 起点不小于 320。
  --   ★必须先 ClearAllPoints 再锚：不能靠「再加一个锚点」——多锚点会把控件拉伸（本项目老教训）。
  do
    local markN = table.getn(SE_MARK_DEFS)
    local marksW = (markN - 1) * 20 + 16
    local enX = (seUI.W or 660) - 16 - marksW - 14 - enW - 18
    if enX < 320 then enX = 320 end
    pcall(enChk.ClearAllPoints, enChk)
    enChk:SetPoint("TOPLEFT", root, "TOPLEFT", enX, -25)
    pcall(enLabel.ClearAllPoints, enLabel)
    enLabel:SetPoint("TOPLEFT", root, "TOPLEFT", enX + 18, -27)
    SE_MARK_X = enX + 18 + enW + 14
  end
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
              table.insert(items, seTypeLabel(SE_TYPES[ti2].id)) -- ★1.73.27 下拉里也显示实时资源名
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
    -- ★1.73.2 多选（用户：「debuff 类型检测 包括团队debuff 类型要支持多选」）：
    --   · 下拉走**多选**面板（opts.multi）——面板不会因为点一下而关闭，可以连着勾几个；
    --   · 「任意负面」= 空集，与具体类型**互斥**（勾了类型就自动取消它，反之亦然）；
    --   · 勾选状态每次由 cd.dt **重算**后整表重绘（EVAL_DD_SYNC）——不靠面板自己那份状态，
    --     否则「先勾任意、再勾魔法」会留下两处勾。
    row.dtBtn = seBtn(root, 348, y, 62, 15, L("DS_T_ANY"), function()
      local it2 = seUI.ed and seUI.ed.conds[i]
      if not it2 then return end
      local cd = it2.cd
      local dts = EVAL_DISPEL_TYPES or {}
      local items = { L("DS_T_ANY") }
      for _, t in ipairs(dts) do table.insert(items, L("DS_T_" .. string.upper(t.id))) end
      local function selOf(dt)
        local s = {}
        local ids = EVAL_DISPEL_LIST(dt)
        if table.getn(ids) == 0 then s[1] = true end
        for pi = 2, table.getn(items) do
          for _, v in ipairs(ids) do if v == dts[pi - 1].id then s[pi] = true end end
        end
        return s
      end
      EVAL_DD_OPEN(row.dtBtn.btn, items, function(pi, on)
        local ids = EVAL_DISPEL_LIST(cd.dt)
        local set = {}
        for _, v in ipairs(ids) do set[v] = true end
        if pi == 1 then
          if on then set = {} end -- 「任意负面」= 清空全部（互斥）
        else
          local id = dts[pi - 1].id
          if on then set[id] = true else set[id] = nil end
        end
        -- 按 DISPEL_TYPES 的固定顺序收成列表 → 折叠回入库形态（0 项 nil / 1 项字符串 / ≥2 项集合）
        local list = {}
        for _, t in ipairs(dts) do if set[t.id] then table.insert(list, t.id) end end
        cd.dt = EVAL_DISPEL_FOLD(list)
        pcall(EVAL_DD_SYNC, selOf(cd.dt))
        EVAL_HELP_SE_REFRESH()
      end, { multi = true, selected = selOf(cd.dt) })
    end)
    reg(row.dtBtn.btn)
    seHoverTip(row.dtBtn.btn, function()
      local it3 = seUI.ed and seUI.ed.conds[i]
      local ids = EVAL_DISPEL_LIST(it3 and it3.cd and it3.cd.dt)
      if table.getn(ids) < 2 then return nil end
      return { "|cffffd100" .. L("DS_T_TIP_T") .. "|r", string.format(L("DS_T_TIP"), seDispelAllNames(ids)) }
    end)
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
-- ★1.73.12 预览行读值口：底部预览是**真实 FontString**，断言要读它（不能读自己拼的字符串）
function EVAL_TEST_SE_PREVIEW()
  if seUI == nil or seUI.preview == nil then return nil end
  local ok, t = pcall(function() return seUI.preview:GetText() end)
  return ok and t or nil
end
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
-- ★1.73.2 点**真实的类型格**（走它自己的 OnClick → 打开多选面板）
function EVAL_TEST_SE_CLICK_DT(i)
  local row = seUI.rows and seUI.rows[i]
  if not (row and row.dtBtn) then return false end
  local ok, fn = pcall(row.dtBtn.btn.GetScript, row.dtBtn.btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  fn()
  return true
end
-- ★1.73.2 交出类型格真实控件（悬停说明断言用）
function EVAL_TEST_SE_DT_BTN(i)
  local row = seUI.rows and seUI.rows[i]
  return (row and row.dtBtn and row.dtBtn.btn) or nil
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
-- ★1.73.2 读第 i 行条件的**类型值**（原样交出：可能是 nil / 单选字符串 / 多选集合）
function EVAL_TEST_SE_COND_DT(i)
  local ed = seUI and seUI.ed
  local it = ed and ed.conds and ed.conds[i]
  return it and it.cd and it.cd.dt or nil
end
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
      if ti and not SE_TYPES[ti].hidden then table.insert(out, seTypeLabel(SE_TYPES[ti].id)) end -- ★1.73.27 读值口与 UI 同源
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

-- ★1.74.2 读值口：技能编辑窗**真的显示着**（问帧，不问我们自己的记账——「读自己拼的账 = 测自己」）
function EVAL_TEST_SE_SHOWN()
  if not seUI.root then return false end
  local ok, s = pcall(seUI.root.IsShown, seUI.root)
  return (ok and s and true) or false
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

-- ★1.72.4 断言入口：一键宏设置页的**技能行**（读真实控件文案，验「有等级才显示等级」）
-- ★★★1.73.56 除文案外，还要交出**每行的真实可见性**与当前 Tab：
--   本轮真机 bug 是「停在别的 Tab 时刷新数据，把一键宏的技能行重新 Show 出来、叠在当前那页上」——
--   只验文案/数据**完全照不到**这类错（本项目「漏接不报错、只是显示不对」的老账）。
--   ★读的是真控件（FontString/Button 的 IsShown），不是我们自己的记账。
function EVAL_TEST_WAR_ROWS()
  local cw = EVAL_HELP_CFGWIN
  local wu = cw and cw.warUI
  local out = { n = 0, names = {}, shown = {}, profDel = {}, tab = (cw and cw.tab) or nil }
  if not (wu and wu.rows) then return out end
  for i, row in ipairs(wu.rows) do
    local ok, t = pcall(row.name.GetText, row.name)
    out.n = i
    out.names[i] = (ok and tostring(t or "")) or ""
    local oks, sv = pcall(row.name.IsShown, row.name)
    out.shown[i] = (oks and sv) and true or false
  end
  for i, pb in ipairs(wu.profBtns or {}) do
    if pb.del then
      local okd, dv = pcall(pb.del.IsShown, pb.del)
      out.profDel[i] = (okd and dv) and true or false
    end
  end
  return out
end

function EVAL_TEST_CFG_LAYOUT()
  local cw = EVAL_HELP_CFGWIN
  return cw and cw.layout or nil
end

-- ★1.73.41 读值口：配置窗 [使用引导] 按钮（走它的**真实 OnClick**，不是直调动作函数）
function EVAL_TEST_CFG_GUIDE_CLICK()
  local cw = EVAL_HELP_CFGWIN
  local b = cw and cw.guideBtn
  if not b then return false end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if ok and type(fn) == "function" then pcall(fn) return true end
  return false
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
    r.rank = ed.rank -- ★1.72.4 等级随技能一起保存（不保存 = 用户设了等级却永远不生效）
    say("已保存技能: " .. tostring(ed.skill) .. (ed.rank and ("(" .. tostring(ed.rank) .. ")") or "") .. " → " .. uiEsc(EVAL_GROUP_STR(groups))) -- ★1.72.4 等级一并回报
  else
    -- 1.33.0 取消 8 技能上限（配置窗列表支持滚动）
    table.insert(p.skills, { skill = ed.skill, enabled = ed.enabled, groups = groups, why = ed.skill, rank = ed.rank }) -- ★1.72.4
    say("已添加技能: " .. tostring(ed.skill) .. (ed.rank and ("(" .. tostring(ed.rank) .. ")") or "") .. " → " .. uiEsc(EVAL_GROUP_STR(groups))) -- ★1.72.4 等级一并回报
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
    ed.rank = r.rank -- ★1.72.4 载入已有等级（编辑时标题要显示它）
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
--   - 火球术(等级 3) | 非战斗      （★1.72.4 技能名后的括号 = **施法等级**，与官方 CastSpellByName 语法同形；
--                                  括号内必须与**法术书 subtext 逐字相符** → 它是**每语言**的文本
--                                  （等级 3 / Rank 3 / Ранг 3），**跨语言客户端不通用**：
--                                  对方法术书里没有该串时引擎**如实失败**，绝不退化成「无等级乱放」）
-- ★等级只对**真法术名**成立：带前缀的特殊技能名（物品:/宠物:/姿态:/跟随:/选取目标:）里的括号
--   属于名字本身，导入时**不拆**（守卫见 EVAL_PROFILE_FROM_TEXT）。
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
local function ioImportText(text, author)
  local prof, err = EVAL_PROFILE_FROM_TEXT(text)
  if not prof then return false, "导入失败: " .. tostring(err) end
  if type(author) == "string" and author ~= "" then prof.author = author end -- ★1.74.5 记录方案来源（作者：技能学院=案例模版 / 玩家名=别人分享）
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

-- ★★★1.74.5 方案「作者/来源」标签（用户：「给方案增加一个作者类型」）——顶层全局纯函数，供方案列表 tooltip 与断言复用。
--   四类：自创（src ~= text，**作者值=创建者名，但显示只写「自创」**）· 案例模版（author = 技能学院）·
--        别人分享（author = 发送者名）· 导入（文本粘贴，无作者记录）。
--   ★★★用户原话澄清（1.74.5）：「别称的意思就是方案内显示自创（实际值是自己名字）；其他显示类型的显示实际的作者」
--   ⇒ 自创那一类**只显示「自创」**（自己的名字照旧记进 prof.author 存档，只是不上屏）；
--     案例模版 / 别人分享 / 导入 三类显示**真实作者**（技能学院 / 玩家名 / 无）。
function EVAL_PROF_AUTHOR_LABEL(prof)
  if type(prof) ~= "table" then return "?" end
  if prof.src ~= "text" then return EVAL_L("PROF_SRC_SELF") end -- ★自创 = 只写「自创」（别称语义，不显示自己的名字）
  if type(prof.author) == "string" and prof.author ~= "" then
    if prof.author == "技能学院" then return EVAL_L("PROF_SRC_TEMPLATE") .. "：" .. EVAL_L("PROF_SRC_ACADEMY") end
    return EVAL_L("PROF_SRC_SHARE") .. "：" .. tostring(prof.author)
  end
  return EVAL_L("PROF_SRC_IMPORT")
end

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
    table.insert(lines, "- " .. dis .. tostring(r.skill) .. (r.rank and ("(" .. tostring(r.rank) .. ")") or "") .. " | " .. EVAL_GROUP_STR(r.groups)) -- ★1.72.4 等级与官方语法同形
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
        -- ★1.72.4 「技能名(等级 3)」→ 拆出等级（与官方 CastSpellByName 语法同形；括号内必须与 subtext 逐字相符）
        local rank2 = nil
        -- ★★★1.72.4 守卫：**带前缀的特殊技能名**（物品:/宠物:/姿态:/跟随:/选取目标:/取消施法/停止攻击）
        --   走的是各自的分派，**永远不是法术**；它们名字里的括号属于名字本身
        --   （如「物品:治疗药水(大)」「跟随:某人(等级 2)」）——拆开 = **静默改义**（技能名被改、行为被改，
        --   而导入侧与使用侧都不报错）。★只有真法术名才可能带官方等级括号，才允许拆。
        --   ★判据：本守卫 + 断言组 111（前缀名带括号 → 逐字保留；真法术名 → 照拆）。
        if not (itemOf(sn) or petCmdOf(sn) or stanceOf(sn) or followOf(sn) or targetSelOf(sn) or cancelCastOf(sn) or stopAllOf(sn)) then
          local base2, rk2 = string.match(sn, "^(.-)%s*%(([^()]+)%)$")
          if base2 and base2 ~= "" and rk2 and rk2 ~= "" then sn, rank2 = condTrim(base2), condTrim(rk2) end
        end
        if sn ~= "" and string.len(sn) <= 48 then
          table.insert(skills, { skill = sn, enabled = enabled, groups = EVAL_PARSE_CONDS(conds or ""), why = sn, rank = rank2 })
        end
      end
    end
  end
  if table.getn(skills) == 0 then return nil, "没解析到技能行（格式: - 技能名 | 条件）" end
  -- ★★★1.73.63 来源标记：**凡是从文本解析出来的方案**（导入文本 / 案例模版 / 分享接收 / examples）都盖 src = "text"——
  --   彩蛋「创世者亲临」的触发条件之一是「**自己手动创建**的方案达到神级」，所以必须能分辨来源（用户 1.73.63 定）。
  --   ★盖在**唯一的解析出口**上：不用去每个导入入口分别打标（那样迟早漏一处，就是本项目「两份状态」的老账）。
  --   ★手工创建的方案在插入点写 src = "manual"；**老存档没有 src** 的按「手动」算（见 EVAL_TITLE_CREATOR_GATE）。
  return { name = name or "导入方案", skills = skills, src = "text" } -- 1.33.0 取消 8 技能上限
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
  local function rgb3(f, o)
    local ok, r, g, b = pcall(f, o)
    if ok and type(r) == "number" then return { r, g, b } end
    return nil
  end
  local okw, ww = pcall(ui.root.GetWidth, ui.root)
  local okh, hh = pcall(ui.root.GetHeight, ui.root)
  -- 1.71.19 交出「方案」标签按钮（右键全清的断言要真点它）
  local out = { labelBtn = ui.profLabelBtn, rows = ui.profRows or 0, avail = ui.profAvail or 0, pad = ui.profPad or 0, cap = ui.profCap or 0,
    need = ui.profNeed, rootW = (okw and ww) or nil, rootH = (okh and hh) or nil, btns = {},
    tierCalc = ui.profTierCalc or 0 }
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
      -- ★1.73.58 品阶染色：交出**真控件**上的文字色与底色（不读我们自己的记账）
      textRGB = rgb3(pb.text.GetTextColor, pb.text),
      bgRGB = rgb3(pb.bg.GetVertexColor, pb.bg),
    }
  end
  return out
end

-- ★★1.72.4 断言入口：战斗信息UI「方案技能带」每格的**真实文字**（读控件，不读常量）。
--   判据：不在动作条但**合法**的技能（指定等级 / 特殊技能）不许被标成 "?"（假告警）。
function EVAL_TEST_UI_CELLS()
  local out = {}
  if not (ui and ui.profCells) then return out end
  for i, pc in ipairs(ui.profCells) do
    local ok, t = pcall(pc.text.GetText, pc.text)
    out[i] = { text = (ok and tostring(t or "")) or "", shown = true }
  end
  return out
end

-- ★★★1.74.2 断言入口：点战斗信息UI 技能带第 i 格（走它**真实的 OnClick 闭包**，可指定按键）。
--   ★为什么必须走真实闭包：左/右键的分派就写在那一段里，直接调动作函数测不出「接线断了 / 分派写反」
--   （本项目老判据：UI 接线漏接不报错，只能在真实 OnClick 上点才暴露）。
function EVAL_TEST_UI_CLICK_CELL(i, button)
  if not (ui and ui.profCells and ui.profCells[i] and ui.profCells[i].btn) then return false end
  local ok, fn = pcall(ui.profCells[i].btn.GetScript, ui.profCells[i].btn, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  pcall(fn, button or "LeftButton")
  return true
end

-- ★★★1.71.12 断言入口：两个子开关（战斗 / 方案）的**真实生效结果**——
--   刻意读 `ui.combatOn/schemeOn`（BUILD 时定下）+ 控件的**存在性**，而不是回读配置：
--   配置写了什么与「这一轮到底建没建」是两件事（本项目「配置产出/消费两边都要断言」的判据）。
--   另附标题文本与帧宽高（标题 = 玩家名、帧高要随子开关变化）。
-- ★★★1.73.54 读值口：HUD 标题栏（标题的**锚点/对齐** + 右侧两个快捷开关的真控件/锚点/方块文本）。
--   一律读真控件（GetPoint/GetText/IsShown）—— 本项目「读自己拼的账 = 测自己」的老坑。
function EVAL_TEST_UI_TITLEBAR()
  local out = { title = nil, titlePoint = nil, titleJustify = nil, titleX = nil, combat = nil, scheme = nil }
  -- ★★★1.73.55 档位徽标：读**真控件**上的文案 / 锚点 / 文字色 —— 不读 ui.tierShown、ui.tierScore 这类
  --   我们自己的记账（本项目「读自己拼的账 = 测自己」的老坑）。
  out.tier, out.tierPoint, out.tierRelTo, out.tierRelPoint, out.tierX, out.tierColor = nil, nil, nil, nil, nil, nil
  if ui.title then
    local okt, tv = pcall(ui.title.GetText, ui.title)
    if okt and type(tv) == "string" then out.title = tv end
    local okp, pt, _rel, _rp, px = pcall(ui.title.GetPoint, ui.title)
    if okp and type(pt) == "string" then out.titlePoint = pt out.titleX = px end
    local okj, jv = pcall(ui.title.GetJustifyH, ui.title)
    if okj and type(jv) == "string" then out.titleJustify = jv end
  end
  local function one(b)
    if not b then return nil end
    local o = { point = nil, x = nil, w = nil, mark = nil, shown = nil, hasClick = false }
    local okp, pt, _rel, _rp, px = pcall(b.GetPoint, b)
    if okp and type(pt) == "string" then o.point = pt o.x = px end
    local okw, wv = pcall(b.GetWidth, b)
    if okw and type(wv) == "number" then o.w = wv end
    if b.mark then
      local okt, tv = pcall(b.mark.GetText, b.mark)
      if okt and type(tv) == "string" then o.mark = tv end
    end
    local oks, sv = pcall(b.IsShown, b)
    o.shown = (oks and sv) and true or false
    if type(b.GetScript) == "function" then
      local okc, fn = pcall(b.GetScript, b, "OnClick")
      o.hasClick = (okc and type(fn) == "function") or false
    end
    return o
  end
  out.combat, out.scheme = one(ui.tglCombat), one(ui.tglScheme)
  out.combatBtn, out.schemeBtn = ui.tglCombat, ui.tglScheme -- 真控件（点击钩子要用）
  out.titleFs = ui.title -- 真控件（档位徽标锚在它的右边缘上，断言要比对 relTo）
  if ui.tierText then
    out.tierText = ui.tierText
    local okt, tv = pcall(ui.tierText.GetText, ui.tierText)
    if okt and type(tv) == "string" then out.tier = tv end
    local okp, pt, rel, rp, px = pcall(ui.tierText.GetPoint, ui.tierText)
    if okp and type(pt) == "string" then
      out.tierPoint, out.tierRelTo, out.tierRelPoint, out.tierX = pt, rel, rp, px
    end
    local okc, cr, cg, cb = pcall(ui.tierText.GetTextColor, ui.tierText)
    if okc and type(cr) == "number" then out.tierColor = { cr, cg, cb } end
  end
  -- ★★★1.73.57/1.73.62 玩家头衔 + 当前方案名（同款读值口：真控件的文案 / 锚点 / 文字色 —— 不读我们自己的记账）
  out.ptitle, out.ptitlePoint, out.ptitleRelTo, out.ptitleRelPoint, out.ptitleX, out.ptitleColor = nil, nil, nil, nil, nil, nil
  out.plan, out.planPoint, out.planRelTo, out.planRelPoint, out.planX, out.planColor = nil, nil, nil, nil, nil, nil
  local function fsOf(fs, prefix)
    if not fs then return end
    out[prefix .. "Fs"] = fs
    local okt, tv = pcall(fs.GetText, fs)
    if okt and type(tv) == "string" then out[prefix] = tv end
    local okp, pt, rel, rp, px = pcall(fs.GetPoint, fs)
    if okp and type(pt) == "string" then
      out[prefix .. "Point"], out[prefix .. "RelTo"], out[prefix .. "RelPoint"], out[prefix .. "X"] = pt, rel, rp, px
    end
    local okc, cr, cg, cb = pcall(fs.GetTextColor, fs)
    if okc and type(cr) == "number" then out[prefix .. "Color"] = { cr, cg, cb } end
  end
  fsOf(ui.titleText, "ptitle")
  fsOf(ui.planText, "plan")
  return out
end
-- ★★★测试钩子：点标题栏右侧的快捷开关 —— 走它**真实的 OnClick 闭包**（不直调 setter）。
--   ★为什么必须这样：本项目真事故「直接调动作函数全绿、按钮接线断了也不知道」（1.73.37 右键菜单那轮）。
function EVAL_TEST_UI_TITLEBAR_CLICK(which)
  local b = (which == "scheme") and ui.tglScheme or ui.tglCombat
  if not (b and type(b.GetScript) == "function") then return false end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if not (ok and type(fn) == "function") then return false end
  pcall(fn)
  return true
end
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
-- ★★★1.73.7 案例模版窗的**版式计算**（纯函数：不建控件、不碰 UI）——用户最新要求：
--   「方案类别独立一行,方案同行多个.」
--   ① 窗口按列宽一分为二：colW = (W - 2*margin - colGap) / 2（窄到放不下两列时退化单列，不硬撑）；
--   ② **组是不拆的最小单位**：按顺序切成「左段 / 右段」，一个组绝不会跨到另一列（拆开看着像少了一组）；
--   ③ ★★★**类别独占一行**：组标题自己占一行（行首 = 本列左边界），**本组按钮从下一行开始**、
--      从本列左边界依次往右排、放不下就换行回本列左边界（「方案同行多个」）；
--      ★这一条推翻了 1.71.5~1.71.8 的「标题 + 按钮同行流式」：那时标题会被按钮挤在行尾、
--        续行又没有标题，长组看着像**两个类别**（用户截图里【通用法系】/【牧师】/【队伍/团队】就是这个观感）。
--      ★代价 = 每组多占一行 → 窗口高度自动变高（本窗高度一直是**算出来的**，不用手改常量）。
--   ④ 切点 = **两列行数差最小**（遍历所有切点）——★别用「塞到过半就停」的贪心：
--      它在当前数据上看着对，内容一改就失衡（1.71.5 的教训）。
--   ★★为什么是纯函数：布局的核心（分列 + 换行）埋在 BUILD 里就只能用真实模版数据测，
--     而真实内容下「不换行 / 只排一列」都可能是**等价**的 → 必须能用**合成数据**逼它换行、逼它分列。
--   返回 plan, 最末一行 y, 左列行数, 右列行数, 列宽, 右列左边界 x
-- ★★★1.73.42z 案例模版行：品阶图标占的宽度必须**算进按钮宽**（用户真机：「添加图片之后方案显示不全」）——
--   原来只在渲染时把文字**让出**图标位（`e.w - 22`），按钮宽却仍按「名字宽 + 16」算 ⇒ 文字区比名字还窄 6px，
--   于是名字被裁（「法…」「力量祝福（物理…」）。现在**测量与摆放共用同一个常量**（单一来源）。
local TPL_ICON_W = 20 -- 图标 13 + 左边距 3 + 与文字的缝 4
local TPL_ROW_PAD = 16 -- 按钮左右内边距（原来写死在两处，这里收成一份）
-- ★★★1.73.48 用户真机截图：「右侧还有位置，但标题却显示…」——量宽给的是**正好**名字宽，
--   差一两个像素就触发客户端的省略号。⇒ ① 按钮宽**多留 TPL_MEASURE_SAFE**；② 文字框用「按钮宽 − 图标位 − 右留白」，
--   于是文字框比名字估算宽出 12px 的余量（宁可右边缘空一点，也不许把名字裁掉）。
local TPL_MEASURE_SAFE = 6 -- 量宽的保险余量（GetStringWidth 与真实渲染可能有 1~2px 差）
local TPL_TEXT_PAD = 4    -- 左对齐时文字框右侧留白（原来文字框 == 名字宽，见上）
local function tplTwoColPlan(W, groups, measure, margin, gap, rowH, colGap)
  local colW = math.floor((W - margin * 2 - colGap) / 2)
  if colW < 60 then colW = W - margin * 2 end -- 窗口太窄：退化成单列（硬分两列会把按钮压成一条）
  local colX = { margin, margin + colW + colGap }
  local colMax = { colX[1] + colW, colX[2] + colW }
  local n = table.getn(groups)
  -- ★★★1.73.48 按钮宽 = **单一来源**（本轮又踩了一次「两处各算一遍」：只给 rowsOf 加了量宽余量、
  --   摆放那段没加 → 自报行数与真实占用行数当场不一致，被组 91 的判据抓个正着）。
  local function btnWof(name)
    local bw = measure(tostring(name)) + TPL_ROW_PAD + TPL_ICON_W + TPL_MEASURE_SAFE
    if bw > colW then bw = colW end
    return bw
  end
  -- ① 一个组在**本列列宽**下要占几行 = **标题 1 行** + 按钮行（组内同行 + 自动换行）
  --   ★1.73.7 按钮从**本列左边界**起排（标题已独占上一行）——所以这里 px 从 colX[1] 开始，
  --     与下方摆放逻辑必须**逐字一致**（两处算得不一样 = 切点与真实高度不符，本项目老坑）。
  local function rowsOf(c)
    -- ★★★别漏掉「第一行按钮」：标题独占 1 行之后，**第一个按钮就是新的一行**
    --   （第一版写成 rows=1 起数、只在换行时 +1 → 每组少算一行，切点与真实高度不符；
    --     真实数据上表现为 rowsL/rowsR 报 6+7 而实际要 11 行 —— 两处算法必须逐字一致。）
    local btnRows, px = 0, colX[1]
    for _, p in ipairs(c.list) do
      local bw = btnWof(p.name)
      if btnRows == 0 or px + bw > colMax[1] + 0.5 then
        btnRows = btnRows + 1 px = colX[1]
      end
      px = px + bw + gap
    end
    return 1 + btnRows -- 1 = 标题独占的那一行
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
  -- ③ 照切点摆两列：每组从新行开始，**标题独占一行**（在本列行首），按钮从下一行起流式排
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
        -- ★★★1.73.7 类别**独占一行**（用户：「方案类别独立一行」）：这一行只放标题，
        table.insert(plan, { kind = "header", cls = c.cls, x = x0, y = py, w = lw })
        -- 按钮从**下一行**开始、从本列左边界起排（用户：「方案同行多个」）
        py = py - rowH
        local px = x0
        for _, p in ipairs(c.list) do
          local bw = btnWof(p.name)
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
  -- ★★★1.73.7 版式（用户最新要求）：「**方案类别独立一行，方案同行多个**」——
  --   · **类别标题独占一行**（本列行首），本组方案从**下一行**起从左往右排、放不下就换行回本列左边界；
  --   · 每个按钮宽度 = FontString:GetStringWidth() **实测** + 内边距（拿不到就按「字符数 × 9px」近似）；
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

  -- ★★★1.73.7 **「类别一行 + 方案同行多个」布局**（用户要求：「方案类别独立一行,方案同行多个.」）：
  --   ① 先算 plan（位置单一来源）：**标题独占一行**，本组按钮从下一行起依次往右排、放不下就换行回本列左边界；
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
      b.tierBgTex = bb -- ★1.73.42l 供判据读**真实背景色**（桩会记账，真机 GetVertexColor 可读）
      local bt = uiText(b, 9, 0.88, 0.88, 0.88)
      b.tierText = bt -- ★1.73.42l 供判据读**真实文字色**
      bt:SetPoint("CENTER", b, "CENTER", 0, 0)
      pcall(bt.SetWidth, bt, e.w - 8) -- 实测宽度留的内边距足够；超长名仍裁掉（tooltip 里有全名）
      pcall(bt.SetNonSpaceWrap, bt, false)
      bt:SetText(tostring(p.name)) -- 1.67.6 行内只留模版名；描述+方案内容移入 tooltip
      -- ★★★1.73.47 用户：「案例模版→方案标题左对齐·垂直居中」⇒ 名字**左对齐**（居中时两边都裁，长名从中间截断、
      --   看不出是哪个方案）+ 行内**垂直居中**。★在**建控件时设一次**（有品阶/无品阶两条路共用），品阶分支不再改对齐 ——
      --   免得出现「有品阶的居左、没品阶的居中」这种漂移。
      pcall(bt.SetJustifyH, bt, "LEFT")
      pcall(bt.SetJustifyV, bt, "MIDDLE")
      -- ★★★1.73.42e 用户要求：「案例模版内的方案根据以上方案等级配置对应的图标显示」
      --   品阶 = 技能条数 + 条件数（**与分享显示行同一套判定** EVAL_SHARE_SEAL_*）；图标来自 IconSem 语义表；
      --   ★按钮几何一律不动（免得破坏「分列/不重叠/不越界」那几条判据）——只把**文字让出图标位**。
      local sScore = (type(EVAL_SHARE_SEAL_SCORE) == "function") and EVAL_SHARE_SEAL_SCORE(p.text) or nil
      if sScore then
        local tiIdx = select(1, EVAL_SHARE_SEAL_TIER(sScore))
        local tiPath = EVAL_SHARE_SEAL_ICON(tiIdx)
        local tiTex = b:CreateTexture(nil, "ARTWORK")
        pcall(tiTex.SetTexture, tiTex, tiPath)
        tiTex:SetPoint("LEFT", b, "LEFT", 3, 0)
        tiTex:SetWidth(13)
        tiTex:SetHeight(13)
        b.tierIcon, b.tierIdx, b.tierScore = tiTex, tiIdx, sScore
        -- ★1.73.42z 文字区 = 按钮宽 − 内边距 − 图标位（与 tplTwoColPlan 的测量**同源**）→ 名字放得下、不再被裁。
        --   ★★★1.73.47 **「居中」已作废**（1.73.42z 那条「名称没居中」是上一轮的要求；用户现在要「左对齐·垂直居中」）
        --     ⇒ 对齐统一在建控件时设一次（LEFT + MIDDLE），这里**只让位、不动对齐**。
        -- ★★★1.73.48 用户真机：「方案标题没垂直居中」——【根因】建控件时锚的是 CENTER，这里又 `SetPoint("LEFT")`：
        --   真客户端里这是**两个锚点**（同一个 FontString 被两头拽），文字因此偏上几个像素；
        --   旧桩只记最后一次锚点 → 这个 bug 在测试里完全不可见（本轮先补桩、再修代码）。
        --   ⇒ 先 ClearAllPoints 再锚 LEFT（**唯一锚点** = 真正的垂直居中）。
        pcall(bt.ClearAllPoints, bt)
        pcall(bt.SetPoint, bt, "LEFT", b, "LEFT", TPL_ICON_W, 0)
        pcall(bt.SetWidth, bt, e.w - TPL_ICON_W - TPL_TEXT_PAD)
        -- ★★★1.73.42l 用户：「案例方案内图标替换，名称和颜色背景都要符合以上规则」
        --   ① 名称文字 = **品阶色**（与聊天行/弹窗同一张色表，经 EVAL_SHARE_SEAL_TIER_RGB 解析）；
        --   ② 行背景 = 同色调**压暗到 22%**（饱和底色会把文字吃掉——本项目「文字色 vs 背景色」那条老教训）；
        --   ③ 悬停 = 同色调 42%（比常态亮，但不跳色）；解析不出色码就退回原来的暗黄底，绝不闪成黑块。
        tiRGB = (type(EVAL_SHARE_SEAL_TIER_RGB) == "function") and EVAL_SHARE_SEAL_TIER_RGB(tiIdx) or nil
        if tiRGB then
          pcall(bt.SetTextColor, bt, tiRGB.r, tiRGB.g, tiRGB.b)
          b.tierTextR, b.tierTextG, b.tierTextB = tiRGB.r, tiRGB.g, tiRGB.b
          local br, bgc, bbc = tiRGB.r * 0.22, tiRGB.g * 0.22, tiRGB.b * 0.22
          pcall(bb.SetVertexColor, bb, br, bgc, bbc, 1)
          b.tierBgR, b.tierBgG, b.tierBgB = br, bgc, bbc
          b.tierHoverR, b.tierHoverG, b.tierHoverB = tiRGB.r * 0.42, tiRGB.g * 0.42, tiRGB.b * 0.42
        end
      end
      table.insert(tplUI.rowBtns, { name = tostring(p.name), cls = tostring(e.cls), btn = b })
      b:SetScript("OnEnter", function()
        if b.tierHoverR then pcall(bb.SetVertexColor, bb, b.tierHoverR, b.tierHoverG, b.tierHoverB, 1)
        else pcall(bb.SetVertexColor, bb, 0.30, 0.25, 0.12, 1) end
        pcall(function()
          GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
          GameTooltip:AddLine(tostring(p.name), 1, 0.85, 0.3)
          if b.tierScore then
            local _, ti = EVAL_SHARE_SEAL_TIER(b.tierScore)
            -- ★1.73.42l tooltip 里的品阶行也用**该品阶的颜色**（与行内名称、分享行一致）
            GameTooltip:AddLine("品阶：" .. tostring(ti.name) .. "（评分 " .. tostring(b.tierScore) .. "）",
              b.tierTextR or 1, b.tierTextG or 0.9, b.tierTextB or 0.5)
          end
          if p.desc then GameTooltip:AddLine(tostring(p.desc), 0.85, 0.85, 0.85, true) end
          for ln2 in string.gmatch(tostring(p.text or ""), "([^\n]+)") do
            if string.sub(ln2, 1, 1) == "-" then GameTooltip:AddLine(ln2, 0.65, 0.65, 0.65, true) end -- 技能行预览
          end
          GameTooltip:Show()
        end)
      end)
      b:SetScript("OnLeave", function()
        if b.tierBgR then pcall(bb.SetVertexColor, bb, b.tierBgR, b.tierBgG, b.tierBgB, 1)
        else pcall(bb.SetVertexColor, bb, 0.12, 0.10, 0.06, 1) end
        pcall(GameTooltip.Hide, GameTooltip)
      end)
      b:SetScript("OnClick", function()
        local ok, msg = ioImportText(p.text, "技能学院") -- ★1.74.5 案例模版来源
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
-- ★★★1.73.42l 案例模版行的「品阶外观」读值口：图标纹理 + 名称**文字色** + 行**背景色**（都读**真控件**，
--   不读我们自己记的账——本项目「断言读自己拼的状态 = 测自己」的老坑）。
function EVAL_TEST_TPL_TIER(i)
  EVAL_HELP_TPL_BUILD()
  local e = (tplUI.rowBtns or {})[tonumber(i) or 0]
  if not e or not e.btn then return nil end
  local b = e.btn
  local out = { name = e.name, cls = e.cls, tier = b.tierIdx, score = b.tierScore, icon = nil,
                textR = nil, textG = nil, textB = nil, bgR = nil, bgG = nil, bgB = nil, want = nil }
  if b.tierIcon then
    local ok, t = pcall(b.tierIcon.GetTexture, b.tierIcon)
    out.icon = ok and t or nil
  end
  if b.tierText then
    local okt, tr, tg, tb = pcall(b.tierText.GetTextColor, b.tierText)
    if okt then out.textR, out.textG, out.textB = tr, tg, tb end
  end
  if b.tierBgTex then
    local okv, vr, vg, vb = pcall(b.tierBgTex.GetVertexColor, b.tierBgTex)
    if okv then out.bgR, out.bgG, out.bgB = vr, vg, vb end
  end
  -- ★1.73.42z 布局判据要的：文字区宽 / 对齐方式 / 按钮宽（用户：「显示不全」+「名称没居中」）
  if b.tierText then
    local okw, wv = pcall(b.tierText.GetWidth, b.tierText)
    if okw and type(wv) == "number" then out.textW = wv end
    local okj, jv = pcall(b.tierText.GetJustifyH, b.tierText)
    if okj and type(jv) == "string" then out.textJustify = jv end
    -- ★★★1.73.47 垂直对齐也要读得回来（用户：「垂直居中」）——桩没记就永远验不到（桩保真铁律）
    local okjv, jvv = pcall(b.tierText.GetJustifyV, b.tierText)
    if okjv and type(jvv) == "string" then out.textJustifyV = jvv end
    -- ★★★1.73.48 锚点也要读回来：**两个锚点**会把文字拽歪（用户真机「没垂直居中」的根因）
    if type(b.tierText.GetAnchorCount) == "function" then
      local okn, nv = pcall(b.tierText.GetAnchorCount, b.tierText)
      if okn and type(nv) == "number" then out.textAnchors = nv end
    end
    if type(b.tierText.GetAnchorNames) == "function" then
      local oknm, nmv = pcall(b.tierText.GetAnchorNames, b.tierText)
      if oknm and type(nmv) == "string" then out.textAnchorNames = nmv end
    end
    local okyt, yv = pcall(b.tierText.GetTop, b.tierText)
    if okyt and type(yv) == "number" then out.textTop = yv end
  end
  local okbw, bwv = pcall(b.GetWidth, b)
  if okbw and type(bwv) == "number" then out.btnW = bwv end
  if type(EVAL_SHARE_SEAL_TIER_RGB) == "function" and b.tierIdx then out.want = EVAL_SHARE_SEAL_TIER_RGB(b.tierIdx) end
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
  local rowStartBad = 0 -- ★1.73.7 按钮行必须从**本列左边界**开始（标题已独占上一行，不该再缩进）
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
      if e.kind == "item" and i == 1 and math.abs(e.x - x0) > 0.5 then rowStartBad = rowStartBad + 1 end
      if i > 1 then
        local prev = list[i - 1]
        if colOf(prev.x) == ci and e.x < prev.x + prev.w + 6 - 0.5 then gapBad = gapBad + 1 end
      end
    end
  end
  -- ★★★1.73.7 新不变量：「类别独占一行」= 任何**标题行**上都不许有按钮（这一行整行留给类别）
  local withItem = {}
  for key, list in pairs(byRow) do
    for _, e in ipairs(list) do if e.kind == "item" then withItem[key] = true break end end
  end
  local hdrShared = 0
  for _, list in pairs(byRow) do
    for _, e in ipairs(list) do
      if e.kind == "header" then
        local key = tostring(e.y) .. "#" .. tostring(colOf(e.x))
        if withItem[key] then hdrShared = hdrShared + 1 end
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
  -- ★1.73.7 版式自报的行数必须 == plan 里真实占用的行数（标题行 + 按钮行）：
  --   rowsOf 与摆放逻辑**必须逐字一致**，少算一行时切点与窗口高度都会错，而它**不报错**。
  local realRows = 0
  for _ in pairs(byRow) do realRows = realRows + 1 end
  local rowsInconsistent = (realRows == rowsL + rowsR) and 0 or 1
  return { items = items, groups = gn, rows = rows, perCol = perCol, colGroups = { g1, g2 },
    over = over, gapBad = gapBad, colStartBad = colStartBad, splitBad = splitBad,
    hdrShared = hdrShared, rowStartBad = rowStartBad, realRows = realRows, rowsInconsistent = rowsInconsistent,
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
    -- ★1.73.41 调研探针（分支 probe/share-hide-link）：只做取证，**不动分享协议**
    elseif msg == "go 链接探针" or string.find(msg, "^go 链接探针%s") or msg == "go linkprobe" then
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
    elseif msg == "go 长度探针" or string.find(msg, "^go 长度探针%s") or msg == "go lenprobe" then
      if type(EVAL_SHARE_LEN_PROBE) == "function" then
        local chanL = "WHISPER"
        if string.find(msg, "公会", 1, true) then chanL = "GUILD"
        elseif string.find(msg, "队伍", 1, true) or string.find(msg, "小队", 1, true) then chanL = "PARTY" end
        EVAL_SHARE_LEN_PROBE(chanL)
      else
        say("分享模块未载入（EVAL_SHARE_LEN_PROBE 不存在）")
      end
    elseif msg == "go 探针全跑" or msg == "go probeall" then
      if type(EVAL_SHARE_PROBE_AUTORUN) == "function" then
        EVAL_SHARE_PROBE_AUTORUN("WHISPER")
      else
        say("分享模块未载入（EVAL_SHARE_PROBE_AUTORUN 不存在）")
      end
    elseif msg == "go 图标探针" or msg == "go iconprobe" then
      if type(EVAL_SHARE_ICON_PROBE) == "function" then
        EVAL_SHARE_ICON_PROBE("WHISPER")
      else
        say("图标探针：分享模块未载入（EVAL_SHARE_ICON_PROBE 不存在）")
      end
    -- ★★★1.73.42p 彩蛋「创世者亲临」：先给命令手动触发（用户：「先提供个命令.让我能触发创世神的关注」），
    --   真正的触发机制（写方案达到某机制）以后再接。机缘**只有一次**，用过就如实拒绝。
    elseif msg == "go 创世" or msg == "go 彩蛋" or msg == "go creator"
        or string.find(msg, "^go 创世%s") or string.find(msg, "^go 彩蛋%s") or string.find(msg, "^go creator%s") then
      if type(EVAL_TITLE_CREATOR_OPEN) == "function" then
        -- ★1.73.42q **命令后路**：`/eh go 创世 <名号>` 直接落笔（万一 EditBox 还是打不了字，这条也走得通）
        local argC = string.match(msg, "^go [^%s]+%s+(.+)$")
        if argC and type(EVAL_TITLE_CREATOR_TRY) == "function" then
          local okC, keyC, msgC = EVAL_TITLE_CREATOR_TRY(argC) -- ★1.73.63 第三个返回值 = 闸门未过时的「还差什么」
          if okC then say(string.format(EVAL_L(keyC), tostring(argC))) else say(msgC or EVAL_L(keyC)) end
        else
          EVAL_TITLE_CREATOR_OPEN() -- 打不开（机缘已用尽）时它自己会如实播报 CREATOR_USED
        end
      else
        say("创世者亲临：分享模块未载入（EVAL_TITLE_CREATOR_OPEN 不存在）")
      end
    -- ★★★1.73.43b 分享发送取证（用户：「还是没显示分享信息」）
    -- ★★★1.73.43d 封皮变异测：9 种编号形态发到「说」，用户回报「哪些编号出现」即可定位
    elseif msg == "go 封皮测" or msg == "go shvariant" or msg == "go 变异测" then
      if type(EVAL_SHARE_SEAL_VARIANT_PROBE) == "function" then
        EVAL_SHARE_SEAL_VARIANT_PROBE()
      else
        say("封皮变异测：Share 模块未载入")
      end
    elseif msg == "go 分享探针" or msg == "go shprobe" or msg == "go 发送探针" then
      if type(EVAL_SHARE_SEND_PROBE) == "function" then
        EVAL_SHARE_SEND_PROBE()
      else
        say("分享探针：Share 模块未载入（EVAL_SHARE_SEND_PROBE 不存在）")
      end
    -- ★★★1.74.3 接收诊断（用户报「队伍频道接收完方案不弹窗」）：接收开关 + 七个事件注册情况 + 最近真收到的事件名
    elseif msg == "go 分享事件" or msg == "go sharevents" or msg == "go 接收事件" then
      if type(EVAL_SHARE_RECV_PROBE) == "function" then
        EVAL_SHARE_RECV_PROBE()
      else
        say("分享事件：Share 模块未载入（EVAL_SHARE_RECV_PROBE 不存在）")
      end
    -- ★★★1.73.44 色码测（用户要求「将现在所使用的所有颜色色码都测试下」）：
    --   把分享真正会发到聊天的每一个色码各发一条编号消息（列表**从色表实时生成**，不手抄）——
    --   这个客户端对色码的口径很窄（非 8 位吞整条 / 多段吞整条 / 无链接不画），三种坑都不报错，只能实测。
    elseif msg == "go 色码测" or msg == "go colortest" or msg == "go 颜色测" or msg == "go palette" then
      if type(EVAL_SHARE_COLOR_PROBE) == "function" then
        EVAL_SHARE_COLOR_PROBE()
      else
        say("色码测：Share 模块未载入（EVAL_SHARE_COLOR_PROBE 不存在）")
      end
    -- ★★★1.73.45 名号色（用户：「彩蛋头衔 颜色设置霸气一点」）：不带编号 = **逐条编号预览候选**（真形态真颜色）；
    --   带编号 = 当场选用并存档（cfg.title.customColor，立刻生效、重登仍在）。
    elseif msg == "go 名号色" or msg == "go 头衔色" or msg == "go titlecolor"
        or string.find(msg, "^go 名号色%s") or string.find(msg, "^go 头衔色%s") or string.find(msg, "^go titlecolor%s") then
      if type(EVAL_SHARE_TITLE_COLOR_PROBE) == "function" then
        local argC = string.match(msg, "^go [^%s]+%s+(%S+)$")
        if argC then
          local colC = (type(EVAL_TITLE_SET_CUSTOM_COLOR) == "function") and EVAL_TITLE_SET_CUSTOM_COLOR(argC) or nil
          if colC then
            local listC = (type(EVAL_TITLE_CUSTOM_COLOR_LIST) == "function") and EVAL_TITLE_CUSTOM_COLOR_LIST() or nil
            local nmC = (listC and listC[tonumber(argC)] and listC[tonumber(argC)].name) or ""
            say(string.format(EVAL_L("TC_SET_FMT"), tostring(colC) .. tostring(nmC) .. "|r"))
          else
            local nC = (type(EVAL_TITLE_CUSTOM_COLOR_LIST) == "function") and table.getn(EVAL_TITLE_CUSTOM_COLOR_LIST()) or 0
            say(string.format(EVAL_L("TC_BAD"), nC))
          end
        else
          EVAL_SHARE_TITLE_COLOR_PROBE()
        end
      else
        say("名号色：Share 模块未载入（EVAL_SHARE_TITLE_COLOR_PROBE 不存在）")
      end
    -- ★★★1.73.42s 取证：右键名字菜单的能力 + 记账（用户：「右键邀请触发」＝点了没反应）
    -- ★★★1.73.51 名字染色缓存取证（用户：「分析玩家姓名染色缓存是什么时候载入的」）：
    --   把每个来源的**条数 + 职业原文 → token** 一次摊开（真机上「没数据 / 认不出职业 / 入口没挂上」三选一）。
    elseif msg == "go 名字缓存" or msg == "go namcache" or msg == "go 染色缓存" then
      if type(EVAL_TB_NAMECLASS_PROBE) == "function" then
        EVAL_TB_NAMECLASS_PROBE()
      else
        say("名字缓存探针：工具箱未载入（EVAL_TB_NAMECLASS_PROBE 不存在）")
      end
    -- ★★★1.73.49 方案列表图标取证（用户：「方案左侧的图片还没显示」）
    elseif msg == "go 方案图标" or msg == "go proficon" or msg == "go 图标探针2" then
      if type(EVAL_WAR_PROF_ICON_PROBE) == "function" then
        EVAL_WAR_PROF_ICON_PROBE()
      else
        say("方案图标探针：配置窗未载入（EVAL_WAR_PROF_ICON_PROBE 不存在）")
      end
    elseif msg == "go 名字探针" or msg == "go namemenu" or msg == "go 社交探针" then
      if type(EVAL_TB_NAME_PROBE) == "function" then
        EVAL_TB_NAME_PROBE() -- 能力与记账都在它里面打出来并落盘
      else
        say("名字探针：工具箱未载入（EVAL_TB_NAME_PROBE 不存在）")
      end
    -- ★★★1.73.42r 重置（用户：「给我一个重置删除自定义的命令.测试」）——诊断/测试用，正常玩法没有这条路
    elseif msg == "go 重置名号" or msg == "go 清名号" or msg == "go resetname" then
      if type(EVAL_TITLE_CLEAR_CUSTOM) == "function" then
        local cfgR = EVAL_HELP_CONFIG
        local hadR = (type(cfgR) == "table" and type(cfgR.title) == "table" and type(cfgR.title.custom) == "string" and cfgR.title.custom ~= "")
        EVAL_TITLE_CLEAR_CUSTOM()
        if hadR then
          local curR = (type(EVAL_TITLE_CURRENT) == "function") and EVAL_TITLE_CURRENT() or nil
          say(string.format(EVAL_L("TITLE_RST_CUSTOM"), curR and tostring(curR.name) or EVAL_L("TITLE_RST_NAME")))
        else
          say(EVAL_L("TITLE_RST_CUSTOM_NONE"))
        end
      else
        say("重置名号：分享模块未载入（EVAL_TITLE_CLEAR_CUSTOM 不存在）")
      end
    elseif msg == "go 重置头衔" or msg == "go 清头衔" or msg == "go resettitle" then
      if type(EVAL_TITLE_RESET_ALL) == "function" then
        local cfgR2 = EVAL_HELP_CONFIG
        local had2 = (type(cfgR2) == "table" and type(cfgR2.title) == "table" and ((tonumber(cfgR2.title.tier) or 0) > 0 or type(cfgR2.title.custom) == "string"))
        EVAL_TITLE_RESET_ALL()
        if type(EVAL_TITLE_REFRESH) == "function" then EVAL_TITLE_REFRESH() end -- 立刻按当前方案库重算重抽
        if had2 then say(EVAL_L("TITLE_RST_ALL")) else say(EVAL_L("TITLE_RST_ALL_NONE")) end
      else
        say("重置头衔：分享模块未载入（EVAL_TITLE_RESET_ALL 不存在）")
      end
    -- ★★★1.73.42n 头衔抽卡：当前头衔 + 五档抽取记录 + 距下一档还差什么（用户：「每个档位只抽卡一次」）
    elseif msg == "go 头衔" or msg == "go title" or msg == "go 抽卡" then
      if type(EVAL_TITLE_REFRESH) == "function" and type(EVAL_TITLE_PROGRESS) == "function" then
        EVAL_TITLE_REFRESH() -- 打开就重算一次（只升不降；已抽过的档绝不重抽）
        local cur = (type(EVAL_TITLE_CURRENT) == "function") and EVAL_TITLE_CURRENT() or nil
        local prg = EVAL_TITLE_PROGRESS()
        say("===== 头衔抽卡（5 档 × 15 张 · 每档只抽一次 · 只升不降）=====")
        if cur then
          say("  当前头衔：" .. tostring(cur.color) .. "[" .. tostring(cur.name) .. "]|r" ..
              (cur.custom and "（**创世神的关注**·自定义，优先度最高）" or ("（第 " .. tostring(cur.tier) .. " 档抽到）")))
        else
          say("  当前头衔：还没有（方案库里至少要有一个方案才入档）")
        end
        local st = (type(EVAL_TITLE_STATE) == "function") and EVAL_TITLE_STATE() or nil
        local draws = (st and st.draws) or {}
        for i = 1, 5 do
          local cname = (type(EVAL_SHARE_SEAL_TIER) == "function") and select(2, EVAL_SHARE_SEAL_TIER(({ 1, 4, 7, 10, 13 })[i])).name or ("档" .. i)
          local d = tonumber(draws[i])
          if d then
            say("  第 " .. i .. " 档（" .. cname .. "）：已抽到 " .. tostring(EVAL_L(EVAL_TITLE_KEY(i, d))))
          elseif (st and tonumber(st.tier) or 0) >= i then
            say("  第 " .. i .. " 档（" .. cname .. "）：已到达但没抽到卡（存档异常，重登会补抽）")
          else
            say("  第 " .. i .. " 档（" .. cname .. "）：未达到")
          end
        end
        if prg.nextTier then
          say("  距第 " .. tostring(prg.nextTier) .. " 档：还差 " .. tostring(prg.need - prg.have) ..
              " 个「稀有度 ≥ " .. tostring(prg.nextTier) .. "」的方案（现有 " .. tostring(prg.have) .. " 个）")
        else
          say("  已是最高档（封顶）")
        end
      else
        say("头衔：分享模块未载入（EVAL_TITLE_REFRESH 不存在）")
      end
    elseif msg == "go 秘籍样例" or msg == "go sealdemo" then
      if type(EVAL_SHARE_SEAL_DEMO) == "function" then
        EVAL_SHARE_SEAL_DEMO()
      else
        say("秘籍样例：分享模块未载入（EVAL_SHARE_SEAL_DEMO 不存在）")
      end
    elseif msg == "go 秘籍" or msg == "go seal" then
      -- ★1.73.42 预览：显示行（境界/品阶/评语）到底长什么样，先在游戏里看一眼
      if type(EVAL_SHARE_SEAL_INFO) == "function" and type(EVAL_PROFILE_TO_TEXT) == "function" then
        local info = EVAL_SHARE_SEAL_INFO(EVAL_PROFILE_TO_TEXT())
        if not info then
          say("秘籍预览：算不出来（方案解析器/导出不可用）")
        else
          say("秘籍预览（评分 " .. tostring(info.score) .. " → " .. tostring(info.tierName) .. "）：")
          say("  " .. info.line)
        end
      else
        say("秘籍预览：分享模块未载入（EVAL_SHARE_SEAL_INFO 不存在）")
      end
    elseif msg == "go 悬停探针" or msg == "go hovprobe" then
      if type(EVAL_SHARE_HOVER_PROBE) == "function" then
        EVAL_SHARE_HOVER_PROBE("WHISPER")
      else
        say("分享模块未载入（EVAL_SHARE_HOVER_PROBE 不存在）")
      end
    -- ★别用 `go probe`：那个已经被「光环探针」占了（同一个 if 链里的 go probe）→ 用 proberes
    elseif msg == "go 探针结果" or msg == "go proberes" then
      if type(EVAL_SHARE_PROBE_REPORT) == "function" then
        EVAL_SHARE_PROBE_REPORT()
      else
        say("分享模块未载入（EVAL_SHARE_PROBE_REPORT 不存在）")
      end
    elseif msg == "go 探针关" or msg == "go probeoff" then
      if type(EVAL_SHARE_PROBE_OFF) == "function" then
        EVAL_SHARE_PROBE_OFF()
        say("探针已关闭（回到正常接收）")
      end
    elseif msg == "guide" or msg == "help2" or msg == "新手" then -- 1.72.1 新手指引重看
      EVAL_HELP_GUIDE(true)
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
        table.insert(w2.profiles, { name = (nm and nm ~= "") and nm or ("方案" .. tostring(table.getn(w2.profiles) + 1)), skills = {}, src = "manual", author = (type(UnitName) == "function" and UnitName("player")) or nil }) -- ★1.73.63 手动创建（彩蛋闸门要认）★1.74.5 作者=自己名字
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
          say(string.format("%d. %s %s | %s", i, tostring(r.skill) .. (r.rank and ("(" .. tostring(r.rank) .. ")") or ""), -- ★1.72.4 等级一并显示（对方案核对的唯一通道）
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
    elseif msg == "go diag" then
      -- ★1.71.22 绑定链路一键取证（诊断工具，保留）：把每一环的现场证据**写进 SavedVariables**
      --   （聊天框刷得快、/reload 就没了，所以走盘）。
      --   读数：① 命令表里有没有我们的命令 / ArchiTotem 目击（Bindings.xml 路线是否成立，**已判死**，
      --           留着便于下次复核）② 客户端自带的 ACTIONBUTTON 家族（我们的派发前提）
      --         ③ 宏 API + 名额  ④ 动作条空格子  ⑤ 键位现状  ⑥ 转发全局是否存在
      --         ⑦ 命令表全表逐行  ⑧ 当前绑定集
      --   ★全部只读；跑完 /reload（把结果落盘），然后直接读文件。
      local out = {}
      local function add(s) out[table.getn(out) + 1] = s end
      -- ① 命令表
      local okN, nB = pcall(GetNumBindings)
      local our, witEarth, witName = 0, 0, nil
      if okN and type(nB) == "number" then
        for i = 1, math.min(nB, 600) do
          local okG, cmd = pcall(GetBinding, i)
          if okG and type(cmd) == "string" then
            if string.find(cmd, "^EVAL_GO_PROF_%d+$") then our = our + 1 end
            if cmd == "CAST_EARTH_TOTEM" then witEarth = i end
            if witName == nil and string.find(cmd, "^CAST_") then witName = cmd end
          end
        end
      end
      add("1 命令表行数=" .. tostring(okN and nB or "ERR") .. " | 我们的 EVAL_GO_PROF_*=" .. our
        .. " | ArchiTotem 目击=" .. (witEarth > 0 and ("有(第" .. witEarth .. "行)") or "无") .. " 首个CAST_=" .. tostring(witName))
      -- ② 动作条命令家族
      local ab, abN = {}, 0
      if okN and type(nB) == "number" then
        for i = 1, math.min(nB, 600) do
          local okG, cmd = pcall(GetBinding, i)
          if okG and type(cmd) == "string" then
            if string.find(cmd, "^ACTIONBUTTON%d+$") then abN = abN + 1 if abN <= 3 then ab[abN] = cmd end end
          end
        end
      end
      local abTxt = ""
      for _, c in ipairs(ab) do abTxt = abTxt .. c .. " " end
      add("2 ACTIONBUTTON 家族=" .. abN .. " 条（如 " .. (abTxt ~= "" and abTxt or "-") .. "）")
      -- ③ 宏
      add("3 宏 API：Create=" .. tostring(type(CreateMacro) == "function") .. " Pickup=" .. tostring(type(PickupMacro) == "function")
        .. " Place=" .. tostring(type(PlaceAction) == "function") .. " Delete=" .. tostring(type(DeleteMacro) == "function")
        .. " EditMacro=" .. tostring(type(EditMacro) == "function"))
      if type(GetNumMacros) == "function" then
        local okm, g, c = pcall(GetNumMacros)
        add("   宏名额：通用=" .. tostring(okm and g or "?") .. " 本角色=" .. tostring(okm and c or "?"))
      end
      -- ④ 动作条空格子
      if type(HasAction) == "function" then
        local free, occ = {}, 0
        for s = 1, 120 do
          local okh, has = pcall(HasAction, s)
          if okh and has then occ = occ + 1
          elseif okh and not has and table.getn(free) < 8 then free[table.getn(free) + 1] = s end
        end
        local ft = ""
        for _, s in ipairs(free) do ft = ft .. s .. " " end
        add("4 已占=" .. occ .. "/120 空位=" .. (ft ~= "" and ft or "无"))
      else
        add("4 HasAction 不可用")
      end
      -- ⑤ 键位现状
      local function gba(k)
        local ok, v = pcall(GetBindingAction, k)
        return (ok and type(v) == "string") and v or "ERR"
      end
      add("5 E 键 → " .. gba("E") .. " | F1 → " .. gba("F1") .. " | BUTTON1 → " .. gba("BUTTON1"))
      -- ⑥ ★1.71.22 命令表实样：把前 8 行**原样**打出来 + 末尾 8 行（看表里到底长什么样、EVAL_ 命令在不在别处）
      if okN and type(nB) == "number" then
        local head, tail = {}, {}
        for i = 1, math.min(nB, 600) do
          local okG, cmd, cat, k1, k2 = pcall(GetBinding, i)
          if okG then
            local line = i .. ":" .. tostring(cmd) .. "|" .. tostring(cat) .. "|" .. tostring(k1) .. "|" .. tostring(k2)
            if i <= 8 then head[table.getn(head) + 1] = line end
            if i > nB - 8 then tail[table.getn(tail) + 1] = line end
          end
        end
        add("6 表头 " .. table.concat(head, " ; "))
        add("6 表尾 " .. table.concat(tail, " ; "))
        -- 把整张表按行存下来（分 10 段，避免单行过长），我读文件时能逐个核对
        local seg, segN = {}, 0
        for i = 1, math.min(nB, 600) do
          local okG, cmd, cat, k1 = pcall(GetBinding, i)
          if okG then
            seg[table.getn(seg) + 1] = i .. "=" .. tostring(cmd) .. "@" .. tostring(k1)
            if table.getn(seg) >= 60 then
              segN = segN + 1
              add("7." .. segN .. " " .. table.concat(seg, ","))
              seg = {}
            end
          end
        end
        if table.getn(seg) > 0 then
          segN = segN + 1
          add("7." .. segN .. " " .. table.concat(seg, ","))
        end
      end
      -- ⑥b ★★1.71.22 unrealUI 实证路线核对：它的注释写明「vanilla 绑定命令走全局
      --   ActionButtonDown/Up」——若这两个全局在本客户端存在，就能用它们**接管**任意 ACTIONBUTTON<n> 的派发
      --   （比「宏 + 动作条」更直接：不用占宏名额、不用占动作格）。
      add("6b ActionButtonDown=" .. type(ActionButtonDown) .. " ActionButtonUp=" .. type(ActionButtonUp)
        .. " MultiActionButtonDown=" .. type(MultiActionButtonDown) .. " MultiActionButtonUp=" .. type(MultiActionButtonUp)
        .. " GetBuildInfo=" .. tostring(select(2, GetBuildInfo())))
      add("6b UseAction=" .. type(UseAction) .. " SetOverrideBindingClick=" .. type(SetOverrideBindingClick)
        .. " ClearOverrideBindings=" .. type(ClearOverrideBindings))
      -- ⑦ 绑定集合（GetCurrentBindingSet 与 GetBindingAction 是否看同一张表）
      add("8 当前绑定集=" .. tostring(type(GetCurrentBindingSet) == "function" and GetCurrentBindingSet() or "?"))
      -- 落盘（SavedVariables 只在 /reload/退出时写，这里先塞进配置表）
      EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
      EVAL_HELP_CONFIG.bindDiag = out
      for _, s in ipairs(out) do say("DIAG " .. s) end
      say("★已写入 SavedVariables —— 请 /reload，然后我直接读文件（聊天框内容已存底）")
    elseif msg == "go bind" then
      -- ★1.71.22 现状检查（**诊断用，不再做写入试验**）：派发链路现在是
      --   SetBinding(键, "ACTIONBUTTON<格>") + 接管 ActionButtonUp，所以这里只报「这条链路各环的现状」。
      --   旧的 T1/T2 写入型试验已删除（它们验的是已被判死的 Bindings.xml 路线，留着只会误导）。
      say("— 方案快捷键现状（只读）—")
      local function gba(k)
        local ok, v = pcall(GetBindingAction, k)
        return (ok and type(v) == "string") and v or nil
      end
      -- ① 派发前提：客户端自带的 ACTIONBUTTON1~12 在不在命令表里
      say("① 派发前提：命令表里 ACTIONBUTTON1~12 共 " .. tostring(EVAL_BIND_XML_STATUS()) .. " 条（12 = 前提成立）")
      -- ② 接管状态：两个转发全局是否已被我们替换
      say("② 接管状态：ActionButtonUp=" .. type(ActionButtonUp) .. " 已接管=" .. tostring(EVAL_BIND_ORIG_UP ~= nil))
      -- ③ 逐方案报绑定与占用格
      local w2 = warCfg()
      local n = 0
      for i = 1, table.getn(w2.profiles or {}) do
        local key = w2.bindKeys and w2.bindKeys[i]
        if type(key) == "string" and key ~= "" then
          n = n + 1
          local slot = w2.bindSlots and w2.bindSlots[i]
          say(string.format(L("BIND_ST_ROW"), i, tostring(w2.profiles[i].name or i), key)
            .. "  → ACTIONBUTTON" .. tostring(slot) .. "（读回 " .. tostring(gba(key)) .. "）")
        end
      end
      if n == 0 then say(L("BIND_ST_NONE")) end
      say("绑法：战斗信息UI 方案行**右键**开弹窗；清空：右键「方案」标签；诊断：/eh go diag（写盘，需 /reload）")
    elseif msg == "go icons" then
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
    elseif msg == "go tex" then
      -- ★1.72.2 光环「名字→纹理」学习表诊断（**分享方案排查专用**）：
      --   别人角色没学过某个 debuff 的纹理时，判定会先走「按名字扫描」并自动学回来；
      --   这里可以看学到了什么、删掉单条、或全清——用来实机验证「自动扫描」到底有没有工作。
      local store = (EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex) or {}
      local n1, n2, i = 0, 0, 0
      for _ in pairs(store) do n1 = n1 + 1 end
      for _ in pairs(EVAL_DEBUFF_TEX_LEARN or {}) do n2 = n2 + 1 end
      say("— 光环「名字→纹理」学习表（分享方案排查）—")
      say("持久表 cfg.war.debuffTex = " .. n1 .. " 条；运行时兜底表 = " .. n2 .. " 条")
      for k, v in pairs(store) do
        i = i + 1
        if i > 12 then break end
        say("  " .. tostring(k) .. " → " .. tostring(v))
      end
      if n1 > 12 then say("  …另有 " .. (n1 - 12) .. " 条未列出") end
      say("删单条 /eh go texdel 名字 ｜ 全清 /eh go texclear ｜ 立即扫一遍 /eh go texscan")
    elseif string.find(msg, "^go texdel ") then
      -- ★1.72.2 删掉一条学习记录 → 下次判定应**重新扫描并自动学回来**（这正是你要验的「自动扫描」）
      local want = string.sub(msg, 11) -- "go texdel " 共 10 字符
      local hit = nil
      local function delFrom(t)
        if type(t) ~= "table" then return end
        if t[want] ~= nil then hit = want t[want] = nil return end
        for k in pairs(t) do -- ★/eh 会把整条命令转小写，所以名字要**大小写不敏感**匹配
          if type(k) == "string" and string.lower(k) == want then hit = k t[k] = nil return end
        end
      end
      delFrom(EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex)
      delFrom(EVAL_DEBUFF_TEX_LEARN)
      EVAL_AURA_TEST_RESET_NAME_CACHE()
      if hit then
        say("已删除学习记录：" .. tostring(hit) .. " —— 下次判定会**重新扫描**并按名字自动学回来")
      else
        say("学习表里没有「" .. tostring(want) .. "」这条（可能本来就没学过）")
      end
    elseif msg == "go texclear" then
      local n = 0
      local function clearT(t)
        if type(t) ~= "table" then return end
        for k in pairs(t) do n = n + 1 t[k] = nil end
      end
      clearT(EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex)
      clearT(EVAL_DEBUFF_TEX_LEARN)
      EVAL_AURA_TEST_RESET_NAME_CACHE()
      say("已清空光环学习表（" .. n .. " 条）—— 之后光环判定会先按名字扫描、并自动学回来")
    elseif msg == "go texscan" then
      -- ★1.72.2 立即扫一遍四类光环：名字=纹理 + **本次扫描是否可信**（三态设计的直接证据）
      local G = { { "自身buff", EVAL_PLAYER_BUFF_LIST }, { "自身debuff", EVAL_PLAYER_DEBUFF_LIST },
                  { "目标buff", EVAL_TARGET_BUFF_LIST }, { "目标debuff", EVAL_TARGET_DEBUFF_LIST } }
      say("— 光环立即扫描（扫描可信 = 每个看到的光环槽都读到了名字）—")
      for _, g in ipairs(G) do
        local list, okScan = g[2]()
        local cnt = 0
        for _ in ipairs(list or {}) do cnt = cnt + 1 end
        say(string.format("%s：读到 %d 个（扫描可信=%s）", g[1], cnt, tostring(okScan == true)))
        for _, d in ipairs(list or {}) do say("    " .. tostring(d.name) .. " = " .. tostring(d.tex)) end
      end
    -- ★★1.74.5 实测踩中：string.sub 是**字节**下标，"go 喂食" 是 3+3+3 = **9 字节**（写成 1,5 时前缀永远不等
    --   → 命令**静默无反应**，正是本项目「前缀写错」那一族）。判据 = 组 176⑩ 走真实 SlashCmdList 入口。
    elseif string.sub(msg, 1, 9) == "go 喂食" then
      -- ★1.74.5 猎人助手（tools/HunterHelper.lua）：/eh go 喂食（一键喂食）｜ 喂食 设 <食物> ｜ 喂食 技能 <名>
      --   以及取证命令 /eh go 喂食探针 [扫书|施放 <名>|喂 <包> <格>|拖|收光标]（用户实测用；见该文件头部）
      if type(EVAL_HH_CMD) == "function" then
        EVAL_HH_CMD(msg)
      else
        say("猎人助手模块没载入（tools/HunterHelper.lua 是否列进了 EvalHelp.toc？）")
      end
    -- ★1.74.5 消耗品助手：/eh go 消耗品（状态）｜ 消耗品 用 <物品名> ｜ 消耗品 清
    --   "go 消耗品" = 3 + 9 = **12 字节**（string.sub 是字节下标 —— 写错就静默失效，见组 176⑩ 的教训）
    elseif string.sub(msg, 1, 12) == "go 消耗品" then
      if type(EVAL_CH_CMD) == "function" then
        EVAL_CH_CMD(msg)
      else
        say("消耗品助手模块没载入（tools/ConsumableHelper.lua 是否列进了 EvalHelp.toc？）")
      end
    -- ★1.74.7 骑乘助手（tools/DismountHelper.lua）：/eh go 下马（立即下马）｜ 下马 状态（探针）
    --   "go 下马" = 3 + 6 = **9 字节**（string.sub 是字节下标；两个汉字各 3 字节）
    elseif string.sub(msg, 1, 9) == "go 下马" then
      if type(EVAL_DH_CMD) == "function" then
        EVAL_DH_CMD(msg)
      else
        say("骑乘助手模块没载入（tools/DismountHelper.lua 是否列进了 EvalHelp.toc？）")
      end
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
      --   本机 API 全表（1370 条）里**没有聊天过滤器**（ChatFrame_AddMessageEventFilter 之类不存在）。
      --   ★现状（两次审计定案）：判据 = **事件名优先**，只吞 CHAT_MSG_CHANNEL_NOTICE
      --     （你自己进出频道的回执，即截图里「[8. Trade] 进入频道。」那类；
      --     「玩家的进入信息」JOIN/LEAVE 不拦），文本判据兜底，官方消息组是客户端级另一道。
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
        local on, hooked, cnt, samples, live, seenAll, tries, _fr, _cs, _mi, evtCnt, evtLast = EVAL_TEST_TB_CHAN_STATE()
        say("— 频道进出信息 屏蔽 诊断 —")
        say("开关：屏蔽=" .. (on and "开" or "关") .. "（默认开；配置窗 → 工具箱 → 队伍/社交）")
        say("入口：DEFAULT_CHAT_FRAME=" .. ((DEFAULT_CHAT_FRAME and "有") or "无")
          .. " 已挂载=" .. tostring(hooked) .. " 我们的包装在位=" .. tostring(live) .. "（尝试 " .. tostring(tries) .. " 次）")
        say("经过入口的聊天消息：" .. tostring(seenAll) .. " 条；其中被吞：" .. tostring(cnt) .. " 条")
        say("事件判据吞掉（自己的进出回执 NOTICE）：" .. tostring(evtCnt) .. " 条；最后：" .. tostring(evtLast or "（无）"))
        -- ★取证：api 索引里没有事件清单 → 「事件到底发不发」只能靠到达计数（「判据没拦」与「事件没发」一目了然）
        local evChan = ""
        if type(EVAL_TB_CHATEVENT_STATE) == "function" then
          local st = EVAL_TB_CHATEVENT_STATE()
          if st and type(st.byEv) == "table" then
            for k, n in pairs(st.byEv) do
              if string.find(k, "^CHAT_MSG_CHANNEL") then evChan = evChan .. k .. "=" .. tostring(n) .. " " end
            end
          end
        end
        say("频道事件到达计数：" .. (evChan ~= "" and evChan or "（暂无：进出频道一次后再看）"))
        -- ★★★参考插件 NoJoinLeaveSpam 的 `/njls mute <频道>` 判据输入 = **arg9（频道名）**，且它只在
        --   CHAT_MSG_CHANNEL_JOIN / _LEAVE 上生效 —— 这一屏就是「它在本客户端成不成立」的直接证据。
        local cArgs = {}
        if type(EVAL_TB_CHATEVENT_STATE) == "function" then
          local stc = EVAL_TB_CHATEVENT_STATE()
          if stc and type(stc.chanArgs) == "table" then cArgs = stc.chanArgs end
        end
        if table.getn(cArgs) > 0 then
          say("频道事件原文（事件 ｜ arg8 ｜ arg9 ｜ arg1）—— /njls 的判据就是 arg9：")
          for _, line in ipairs(cArgs) do say("  " .. tostring(line)) end
        else
          say("频道事件原文：暂无（进出频道一次后再看）")
        end
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
    elseif msg == "go 着色" or string.find(msg or "", "^go 着色") == 1 then
      -- ★1.73.10 取证：角色名职业着色到底挂上了没有、画了多少处。
      --   ★为何要给命令：「窗口不存在/控件改名」在本客户端是**静默**的（不报错、只是没颜色），
      --     必须能把「没挂上 / 挂上了但取不到数据 / 数据有了但控件不在」这三种情况分开。
      local sarg = string.match(msg or "", "^go 着色%s*(.-)%s*$") or ""
      if type(EVAL_TB_PAINT_RETRY) == "function" and (string.find(sarg, "^装") == 1 or sarg == "") then
        pcall(EVAL_TB_PAINT_RETRY) -- 顺手重试一次（幂等）
      end
      if type(EVAL_TB_PAINT_STATE) ~= "function" then
        say("职业着色：本版本没有这个功能（EVAL_TB_PAINT_STATE 不存在）")
      else
        local st = EVAL_TB_PAINT_STATE()
        say("— 角色名职业着色 诊断 —")
        say("开关：着色=" .. (st.on and "开" or "关") .. "（工具箱 → 队伍/社交；默认开）")
        local listsN = 0
        if type(EVAL_TB_PAINT_LISTS) == "function" then listsN = table.getn(EVAL_TB_PAINT_LISTS()) end
        local ins, mis = {}, {}
        for k in pairs(st.installed or {}) do table.insert(ins, tostring(k)) end
        for k in pairs(st.missing or {}) do table.insert(mis, tostring(k)) end
        say("已挂载刷新函数（" .. tostring(table.getn(ins)) .. "/" .. tostring(listsN) .. "）：" ..
          ((table.getn(ins) > 0) and table.concat(ins, "、") or "（无）"))
        say("本客户端没有的窗口：" .. ((table.getn(mis) > 0) and table.concat(mis, "、") or "（无）"))
        say("窗口刷新被调：" .. tostring(st.calls) .. " 次；累计上色：" .. tostring(st.painted) ..
          " 处；最近一次扫了 " .. tostring(st.rows) .. " 行（尝试挂载 " .. tostring(st.tries) .. " 次）")
        if not st.wired then
          say("|cffff8080判读：一条都还没挂上 → 这三个刷新函数在本客户端不存在或名字不同（把清单发我）|r")
        elseif st.calls == 0 then
          say("|cffff8080判读：挂上了但窗口从未刷新过 → 打开一次公会/查询/好友窗口再看这一屏|r")
        elseif st.painted == 0 then
          say("|cffff8080判读：窗口刷新了但**一处都没画上** → 控件名与预期不同（GuildFrameButton1Name 之类），把这一屏发我|r")
        else
          say("判读：正常工作中（颜色由本插件叠加；关掉开关会恢复客户端原本配色）")
        end
        say("用法：/eh go 着色 = 重试挂载并打印诊断（打开公会/查询/好友窗口后看更准）")
      end
    elseif msg == "go wtt" or string.find(msg or "", "^go wtt") == 1 then
      -- ★1.73.14 取证（用户报「开启战斗UI 后物品 tooltip 显示几秒就自动隐藏」）：
      --   读数用的「隐形 tooltip」到底是不是**自家的**；以及我们**碰过真实 GameTooltip 几次**。
      if type(EVAL_WTT_STATE) ~= "function" then
        say("隐形 tooltip：本版本没有这个读值口")
      else
        local w = EVAL_WTT_STATE()
        say("— 隐形 tooltip（读光环/技能数据用）诊断 —")
        say("在用对象：" .. tostring(w.name) .. "；自建=" .. tostring(w.self) .. "；说明=" .. tostring(w.why))
        say("碰过**真实 GameTooltip** 的次数：" .. tostring(w.touches) .. "（★应为 0；>0 = 退了化又真去读过）")
        if w.self then
          say("判读：走的是**自家** tooltip → 玩家的物品 tooltip 永远不会被我们清空/关闭（这条就是本轮的根因修复）")
        else
          say("|cffff8080判读：退化用 GameTooltip —— 只在它**没显示**时才读；若仍看到 tooltip 被关，把这一屏发我|r")
        end
      end
    elseif msg == "go 聊天" or string.find(msg or "", "^go 聊天") == 1 then
      -- ★1.73.12 取证：聊天窗名字着色到底**认不认得出**名字（= 格式校准入口）。
      --   ★为什么必须有这个命令：客户端聊天行的**真实文案**我们看不到（本机客户端没有 FrameXML 源码，
      --     只能从 ChatMOD 那种时代相同的老插件反推）→ 判据按推断写，就必须有地方**对照真相**。
      --     这里把最近 12 条**原文**摊开，连同「我们的判据对它的判决」一起打出来（铁律 4 的取证协议：
      --     能做成命令就别让用户手工复现）。
      local sarg = string.match(msg or "", "^go 聊天%s*(.-)%s*$") or ""
      if type(EVAL_TB_CHAN_INSTALL) == "function" and (string.find(sarg, "^装") == 1 or sarg == "") then
        pcall(EVAL_TB_CHAN_INSTALL) -- 顺手重试一次挂载（含 ChatFrame2..7）
      end
      -- ★★1.73.12 「试」= 一键自检：拿**生产判据**判一条文本并说明**为什么**是这个结果。
      --   用法：/eh go 聊天 试 [守夜人]: 你好 —— 不用等真人说话就能当场验形态；
      --   ★「为什么」的来源 = 判据**自己**交出的候选名（EVAL_TB_CHATCOLOR_VOTE 第三返回值），
      --     绝不在诊断里另写一套判据复刻（本项目「读值口不许复刻映射逻辑」的同一族纪律）。
      if string.find(sarg, "^试") == 1 then
        local sample = string.match(sarg, "^试%s*(.*)$") or ""
        if sample == "" then
          -- ★默认样本 = **玩家自己**（他一定在自己的缓存里）→ 不带参数跑一下就看得见「命中」长什么样
          local okn, pnm = pcall(UnitName, "player")
          if okn and type(pnm) == "string" and pnm ~= "" then sample = "[" .. pnm .. "]: 你好"
          else sample = "[守夜人]: 你好" end
        end
        say("样本：" .. sample)
        local hit, who, cands = false, nil, nil
        if type(EVAL_TB_CHATCOLOR_VOTE) == "function" then hit, who, cands = EVAL_TB_CHATCOLOR_VOTE(sample) end
        say("判据：" .. (hit and ("认出来了 → 会把「" .. tostring(who) .. "」染成职业色") or "**没认出来** → 会原样放行（不碰）"))
        if type(cands) == "table" and table.getn(cands) > 0 then
          local parts = {}
          for i = 1, table.getn(cands) do
            local nm = cands[i]
            local tok = (type(EVAL_TB_NAMECLASS_GET) == "function") and EVAL_TB_NAMECLASS_GET(nm)
            table.insert(parts, nm .. (tok and ("（缓存=" .. tostring(tok) .. "）") or "（**不在缓存**）"))
          end
          say("判据考虑过的候选：" .. table.concat(parts, "、"))
        else
          say("判据**没找到任何候选名字** → 形态与推断不符（这一行完整原文发我，我按真实形态改判据）")
        end
        say("提示：把聊天框里**真实的一行**整行贴过来试试，例如 /eh go 聊天 试 [名字]: 你好")
      end
      -- ★★★1.73.20 「色测」= 名字槽渲染试验：用户真机截图逐字放大定案「8 位色码在名字槽里也原样显示」
      --   而同一屏里经 AddMessage 打印的 8 位色码是有色的 ⇒ 名字槽不吃富文本。
      --   最后一条路 = 吞掉客户端那行、自己拼整行（代价：窗口分流/气泡/音效）→ **先取证再定方案**。
      -- ★1.73.26 起「右键」= 右键菜单相关诊断（1.73.28 改为报「这个菜单真正要用的接口」在不在）
      if string.find(sarg, "^右键") == 1 then
        if type(EVAL_TB_MENU_API_PROBE) == "function" then
          pcall(EVAL_TB_MENU_API_PROBE)
        else
          say("右键菜单接口探针：本版本没有（EVAL_TB_MENU_API_PROBE 不存在）")
        end
        if type(EVAL_TB_MENU_GEOM) == "function" then
          local mg = EVAL_TB_MENU_GEOM()
          if mg then
            say("我们自绘菜单的几何：宽 " .. tostring(mg.w) .. " ｜ 背景 alpha " ..
                tostring(mg.bg and mg.bg.a) .. " ｜ 条目：" .. tostring(table.getn(mg.items)) .. " 条")
          else
            say("我们自绘菜单：还没建（右键一次名字再看）")
          end
        end
        say("提示：把这一屏发我 —— 有 UnitPopupMenus 就能做成**真·官方风格**（我们的条目注入官方菜单）")
      end
      if string.find(sarg, "^色测") == 1 then
        if type(EVAL_TB_CHATCOLOR_NAMEPROBE) == "function" then
          pcall(EVAL_TB_CHATCOLOR_NAMEPROBE)
        else
          say("名字槽渲染试验：本版本没有（EVAL_TB_CHATCOLOR_NAMEPROBE 不存在）")
        end
        say("提示：把这一屏发我 —— ①~⑤ 里哪一行名字**有色/可点**，以及「自己拼」那三行你能不能接受")
      end
      if type(EVAL_TB_CHATCOLOR_STATE) ~= "function" then
        say("聊天名字着色：本版本没有这个功能（EVAL_TB_CHATCOLOR_STATE 不存在）")
      else
        local st = EVAL_TB_CHATCOLOR_STATE()
        say("— 聊天窗名字着色 诊断 —")
        say("开关：着色=" .. (st.on and "开" or "关") .. "（工具箱 → 队伍/社交；默认开）")
        say("聊天窗入口：挂上 " .. tostring(st.frames) .. " 个；不可用 " .. tostring(st.miss) .. " 个")
        say("名字缓存：" .. tostring(st.cache) .. " 个（来源：公会/查询/好友窗口上色时白拿 + 队伍/团队/自己/目标）")
        say("经过入口的消息：" .. tostring(st.seen) .. " 条；被染色：" .. tostring(st.painted) .. " 条" ..
          (st.last and ("（最近：" .. tostring(st.last) .. "）") or ""))
        -- ★★★1.73.12 取证：把三种「现象相同、修法不同」的原因分开（用户报「全都没染色」时靠这一屏定案）
        --   ① 我们的包装**不在位**（被客户端/别的插件顶掉）→ 重挂即可；
        --   ② 包装在位但**一条聊天都没经过它** → 客户端不走 Lua 打印（Lua 层做不到，要换入口）；
        --   ③ 收得到聊天行却一条都没认出来 → 判据/格式问题（下面的原文就是依据）。
        if type(EVAL_TB_CHATCOLOR_ROUTES) == "function" then
          local rows, ours, live, sameAsDefault, found = EVAL_TB_CHATCOLOR_ROUTES()
          say("入口在位检查：有聊天框 " .. tostring(live) .. " 个；其中**是我们的包装** " .. tostring(ours) .. " 个" ..
            "；与主窗同一对象 " .. tostring(sameAsDefault) .. " 个")
          local notOurs, missList = 0, {}
          for k, v in pairs(rows or {}) do
            if v.exists and not v.ours then
              notOurs = notOurs + 1
              table.insert(missList, tostring(k))
            end
          end
          if notOurs > 0 then
            table.sort(missList)
            say("|cffff8080这些聊天框的入口**不是我们挂的**：" .. table.concat(missList, "、") ..
              "（= 被顶掉了，/eh go 聊天 装 可立刻重挂）|r")
          end
          if type(found) == "table" and table.getn(found) > 0 then
            say("另外还存在的入口：" .. table.concat(found, "、") .. "（若上面「经过入口」一直 0，就换这些挂）")
          else
            say("另外的候选入口：一个都不存在（ChatFrame_OnEvent / ChatFrame_MessageEventHandler 等）")
          end
        end
        -- ★1.73.12 第二入口：本客户端 frame.AddMessage 写了不生效（实测 0/8），改挂 ChatFrame_OnEvent
        if type(EVAL_TB_CHATEVENT_STATE) == "function" then
          local ce = EVAL_TB_CHATEVENT_STATE()
          say("第二入口 ChatFrame_OnEvent：函数存在=" .. tostring(ce.exists) .. " 我们的层在位=" .. tostring(ce.live) ..
            "；被调用 " .. tostring(ce.seen) .. " 次（吞掉 " .. tostring(ce.filtered) .. " / 染色 " ..
            tostring(ce.painted) .. "）（尝试挂载 " .. tostring(ce.tries) .. " 次）")
          say("  this 帧懒挂载（ChatMOD 的做法）：成功 " .. tostring(ce.thisOk) .. " 个 / **写不进去** " ..
            tostring(ce.thisStuck) .. " 个；经它收到 " .. tostring(ce.thisSeen) .. " 条（吞掉 " ..
            tostring(ce.thisFiltered) .. " / 染色 " .. tostring(ce.thisPainted) .. "）")
          -- ★★★1.73.16 只打**玩家聊天**样本（上一版把战斗/法术消息也塞进 12 格缓冲 → 真实聊天行被挤出去，
          --   用户截图里 12 条全是 CHAT_MSG_SPELL_*，格式证据永远看不到）。arg1 + arg2 一起打：
          --   「名字到底在 arg1 里（可直接改文本）还是只在 arg2 里（要改别的招）」就看这一屏。
          if type(ce.chat) == "table" and table.getn(ce.chat) > 0 then
            say("  经它收到的**玩家聊天**（arg1/arg2；★格式定案看这里）：")
            for i = 1, table.getn(ce.chat) do
              say("   " .. i .. ". " .. string.gsub(tostring(ce.chat[i]), "|", "||"))
            end
          else
            say("  （玩家聊天样本为空 —— 说一句 / 在公会频道发一句，再回来看这一屏）")
          end
          if type(ce.byEv) == "table" then
            local es = {}
            for k, v in pairs(ce.byEv) do table.insert(es, { k = tostring(k), v = tonumber(v) or 0 }) end
            table.sort(es, function(x, y) return x.v > y.v end)
            local parts = {}
            for i = 1, math.min(8, table.getn(es)) do
              table.insert(parts, es[i].k .. "=" .. tostring(es[i].v))
            end
            if table.getn(parts) > 0 then
              say("  事件计数（前 " .. table.getn(parts) .. " 种）：" .. table.concat(parts, "、"))
            else
              say("|cffff8080  事件计数为空（被调用 " .. tostring(ce.seen) .. " 次却一条都没记上）|r")
            end
          end
          -- ★★★1.73.17 调用形态 + 取不到文本的计数（用户实测：1513 次调用、零样本零计数 → 姿势问题）
          say("  名字（arg2 = 发送者）认得出职业：" .. tostring(ce.named or 0) .. " 次；名字不在缓存：" ..
            tostring(ce.nameMiss or 0) .. " 次（★miss 很大 = 缓存里没这些人，先去打开一次公会/查询窗口）")
          say("  方案A「吞行 + 自己拼」：真的接管 " .. tostring(ce.replaced or 0) ..
            " 行；拼不出来（**交回客户端、不染色**）" .. tostring(ce.held or 0) .. " 行")
          say("  ★支持：说/喊/公会/官员/队伍/团队（格式串取自客户端自己的 CHAT_*_GET）；" ..
            "频道/密语暂不支持（客户端原样显示）")
          if type(EVAL_TB_CHATCOLOR_TYPECOLOR_INFO) == "function" then
            say("  类型色来源（client=客户端设置 / client-rgb=只给 r,g,b / builtin=内置兜底 / none=不加色）：")
            say("    " .. EVAL_TB_CHATCOLOR_TYPECOLOR_INFO())
          end
          say("  取不到文本的调用：" .. tostring(ce.noMsg or 0) .. " 次（若 ≈ 被调用总数 → 取参姿势不对）")
          if type(ce.shape) == "table" and table.getn(ce.shape) > 0 then
            say("  调用形态（前 " .. table.getn(ce.shape) .. " 次的原样参数；★姿势定案看这里）：")
            for i = 1, table.getn(ce.shape) do
              say("   " .. i .. ". " .. string.gsub(tostring(ce.shape[i]), "|", "||"))
            end
          end
          if ce.exists and not ce.live then
            say("|cffff8080判读：ChatFrame_OnEvent 存在但我们的层不在位（被顶掉了）→ /eh go 聊天 装 可立刻重挂|r")
          end
        end
        -- ★1.73.12 官方「消息组」屏蔽（与走不走 Lua **无关**的那条路；深入 API 后的发现）
        if type(EVAL_TB_CHAN_OFFICIAL_STATE) == "function" then
          local off = EVAL_TB_CHAN_OFFICIAL_STATE()
          local gl = (type(off.groups) == "table") and table.concat(off.groups, ",") or
                     ("（读不到：" .. tostring(off.err) .. "）")
          say("官方消息组：API 可用=" .. tostring(off.apiRemove) .. "/" .. tostring(off.apiAdd) ..
            "；窗口1 现有组=" .. gl .. "；已摘掉通知组的窗口=" .. tostring(off.saved) ..
            "（判据：组名含 " .. tostring(off.hint) .. "）")
          if type(off.groups) == "table" then
            local hasNotice = false
            for i = 1, table.getn(off.groups) do
              if string.find(string.upper(off.groups[i]), off.hint, 1, true) ~= nil then hasNotice = true end
            end
            -- ★★★1.73.16 判读必须**分清三种情况**（上一版把「本来就没有这个组」也说成「已由官方接口屏蔽」——
            --   用户截图实测：窗口1 只有 SYSTEM 一组、我们一个都没摘，却打了「已屏蔽」= 假判读，必须改）：
            if hasNotice then
              say("|cffff8080判读：通知组**还在**（没摘掉，或开关是关的）→ 若开屏蔽却仍在，把这一屏发我|r")
            elseif off.saved > 0 then
              say("判读：**是我们摘掉的**（已摘 " .. tostring(off.saved) .. " 个窗口）→ 频道进出通知由官方接口屏蔽（与 Lua 无关）")
            else
              say("|cffff8080判读：本客户端**没有**含 " .. tostring(off.hint) .. " 的消息组（窗口1 只有 " .. gl ..
                "）→ **官方这条路在本客户端用不上**；频道进出通知只能靠 Lua 层文本匹配（走 ChatFrame_OnEvent）|r")
            end
          end
        end
        -- 频道屏蔽与本功能**共用同一层包装** → 它的计数是判断「客户端走不走 Lua 打印」的旁证
        if type(EVAL_TEST_TB_CHAN_STATE) == "function" then
          local _on, _hk, chFiltered, _sp, chLive, chSeen = EVAL_TEST_TB_CHAN_STATE()
          say("同层包装（频道屏蔽）：经过 " .. tostring(chSeen) .. " 条；吞掉 " .. tostring(chFiltered) ..
            " 条；我们的包装在位=" .. tostring(chLive))
        end
        -- ★1.73.12 未缓存角色的**主动查询**（用户要求：默认开 + 限频 + 防重复查询 + 可关 + 日志进调试日志）
        if type(EVAL_TB_WHO_STATE) == "function" then
          local w = EVAL_TB_WHO_STATE()
          say("名字查询（主动 /who）：开关=" .. (w.on and "开" or "关") .. "；队列 " .. tostring(w.queued) ..
            "；在途 " .. (w.pending and tostring(w.pending) or "无") .. "；已发 " .. tostring(w.sent) ..
            " 次（查到 " .. tostring(w.hit) .. " / 查不到 " .. tostring(w.missN) .. " / 超时 " ..
            tostring(w.timeout) .. " / 丢 " .. tostring(w.dropped) .. "）")
          say("负缓存 " .. tostring(w.missed) .. " 条（" .. tostring(w.ttl) .. " 秒内**不重复查**；限频 " ..
            tostring(w.gap) .. " 秒/发，单飞超时 " .. tostring(w.pend) .. " 秒，队列上限 " .. tostring(w.qmax) .. "）")
          if w.noApi then
            say("|cffff8080判读：本客户端没有 SendWho → 主动查询不可用（已自动退化为只用本地缓存）|r")
          end
          -- 最近 3 条查询日志（完整日志走 /eh logdump；用户要求「查询日志归入调试日志」）
          local buf = (type(EVAL_HELP_CONFIG) == "table" and type(EVAL_HELP_CONFIG.log) == "table") and
                      EVAL_HELP_CONFIG.log or {}
          local shown = 0
          for i = table.getn(buf), 1, -1 do
            local ln = tostring(buf[i])
            if string.find(ln, "[名字查询]", 1, true) ~= nil then
              say("  " .. ln)
              shown = shown + 1
              if shown >= 3 then break end
            end
          end
          if shown == 0 then say("（调试日志里还没有查询记录；完整日志用 /eh logdump）") end
        end
        local sm = st.samples
        if type(sm) == "table" and table.getn(sm) > 0 then
          say("最近 " .. table.getn(sm) .. " 条聊天**原文** → 我们的判决（★格式校准就看这一屏）：")
          for i = 1, table.getn(sm) do
            local raw = tostring(sm[i])
            local hit, who = false, nil
            if type(EVAL_TB_CHATCOLOR_VOTE) == "function" then hit, who = EVAL_TB_CHATCOLOR_VOTE(raw) end
            -- ★把 | 打成 ||（客户端会显示成一个 |）：否则颜色码会被当场渲染出来，看不出**原文**是什么样
            say("  " .. i .. ". " .. string.gsub(raw, "|", "||") .. "  →" ..
              (hit and ("染色：" .. tostring(who)) or "没认出来"))
          end
          say("判读：上面若有形如 [名字] 或 名字: 的原文却判成「没认出来」→ 把这一屏发我（判据照真实格式改）")
        else
          say("（还没有经过入口的聊天消息 —— 先说一句话 / 进一个频道，再回来看这一屏）")
        end
        local ceSeen = 0
        if type(EVAL_TB_CHATEVENT_STATE) == "function" then ceSeen = EVAL_TB_CHATEVENT_STATE().seen or 0 end
        if st.frames == 0 then
          say("|cffff8080判读：一个聊天窗都没挂上 → 聊天框还没就绪或接口不同（可用 /eh go 聊天 装 重试）|r")
        elseif st.cache == 0 then
          say("|cffff8080判读：挂上了但缓存是空的 → 打开一次公会/查询/好友窗口（或组一次队）再回来看|r")
        elseif st.seen == 0 and (ceSeen or 0) == 0 then
          say("|cffff8080判读：**两个聊天入口**（AddMessage 包装 / ChatFrame_OnEvent）都**一条消息都没收到** → " ..
            "客户端聊天完全不走 Lua（Lua 层着色/屏蔽都做不到），把这一屏发我|r")
        elseif st.seen == 0 and (ceSeen or 0) > 0 then
          say("判读：AddMessage 那层收不到（本客户端正常现象），但 **ChatFrame_OnEvent 这层在收消息** → 着色/屏蔽都由它干活")
        elseif st.painted == 0 and type(st.samples) == "table" and table.getn(st.samples) > 0 then
          say("|cffff8080判读：收得到聊天行、但一条都没认出来 → **判据/格式**问题，上面那几行原文就是依据（发我）|r")
        else
          say("判读：正常工作中（名字按职业色；认不出来的名字保持原样）")
        end
        say("用法：/eh go 聊天 = 重试挂载并打印诊断；/eh go 聊天 装 = 只重试挂载")
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
      say("/eh go probe 增益探针（逐条枚举自身 buff） | /eh go 光环 [名字] 光环定向探查 | /eh go diag 绑定链路一键取证（写盘，需 /reload）")
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
      say("图标路径采集: /eh go icons —— 把客户端宏图标表全表路径写入存档（/reload 后落盘）")
      say("数据检索诊断: /eh ds | /eh ds hud 地图诊断浮层(推荐) | /eh ds snap 一键快照 | /eh ds rnd 随机点测试 + rndstat 统计 | /eh ds trace 轨迹日志 | /eh ds probe 详情行几何")
      say("地图标注: 一个「地图标注(N)」按钮即可——点开勾选类别（=开关）；/eh ds cat <类别> on|off 命令行等价 | /eh ds clear 清空")
    else
      EVAL_HELP()
    end
  end
end

-- ============ 新手引导（1.72.1）：首次加载自动提示 + /eh guide 随时重看 ============
-- 用户需求（原话要点）：加载成功要有提示；建议开启战斗UI；技能释放异常时开技能日志（战斗日志→方案）；
--   对不熟悉宏的新人给出友好指引——怎么打开战斗UI、怎么配第一个宏、怎么绑按键。
function EVAL_HELP_GUIDE(force)
  -- ★★★1.73.41 用户：「使用引导显示弹窗的插件载入的那个引导窗」——
  --   引导的**唯一展示处** = 载入时那个引导窗（`EVAL_HELP_LOADPOP`）：[使用引导] 按钮 / `/eh guide` /
  --   载入提示 三条路都走它（同一个窗、同一份正文、同一个 `cfg.loadMsgSeen` 开关，不搞两份）。
  --   ★只有弹窗**不可用**时才退回聊天打印 —— 这种降级也必须**说出来**（绝不静默什么都不发生）。
  if type(EVAL_LOADPOP_SHOW) == "function" then
    local ok, shown = pcall(EVAL_LOADPOP_SHOW, true)
    if ok and shown then return true end
  end
  say(L("GUIDE_TITLE"))
  say(L("GUIDE_S1"))
  say(L("GUIDE_S2"))
  say(L("GUIDE_S3"))
  say(L("GUIDE_S3B")) -- 1.72.1 备选：宏流程（用户要求：首选右键绑键，宏降为备选）
  say(L("GUIDE_S4"))
  say(L("GUIDE_S5"))
  if force then say(L("GUIDE_MORE")) end
  return true
end

-- ★★★1.73.35 用户第 3 条：**插件载入信息移到独立弹窗**（原来往聊天框打 7 行）——
--   两个操作： [知道了] = 下次载入不再弹（**tooltip 说明**，写进 cfg.loadMsgSeen）；
--              [关闭]   = 每次载入都弹（cfg.loadMsgSeen = false）。
--   ★「初始打开与帮助窗同一个控制」：两者都读同一个 cfg.loadMsgSeen —— 弹窗上点「知道了」，
--     帮助/引导也不再自动弹；配置窗里改回 true 即恢复（单一来源，不搞两份开关）。
local loadUI = {}
-- 读值口（断言与 UI 同源）
function EVAL_TEST_LOADPOP_STATE()
  local shown = false
  if loadUI.root and type(loadUI.root.IsShown) == "function" then
    local ok, v = pcall(loadUI.root.IsShown, loadUI.root)
    shown = (ok and v) and true or false
  end
  return { built = (loadUI.root ~= nil), shown = shown,
           seen = (type(cfg) == "table" and cfg.loadMsgSeen) and true or false,
           hasThanks = (loadUI.thanks ~= nil), hasClose = (loadUI.closeBtn ~= nil),
           lines = loadUI.lineCount or 0, tip = loadUI.tipText or "",
           body = loadUI.bodyText or "" }
end
local function loadPopBuild()
  if loadUI.root then return end
  local W, H = 460, 210
  local root = CreateFrame("Frame", "EVAL_HELP_LOADPOP", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 230) -- 高于输入弹窗(220)，低于全局下拉(250)
  pcall(root.SetMovable, root, true)
  pcall(root.EnableMouse, root, true)
  local bg = root:CreateTexture(nil, "BACKGROUND")
  uiSolid(bg, 0.06, 0.05, 0.04, 0.97)
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  -- 拖动柄（规程：必须是 Button + 全套注册；窗口自身可拖）
  local bar = CreateFrame("Button", nil, root)
  bar:SetWidth(W - 4) bar:SetHeight(22)
  bar:SetPoint("TOP", root, "TOP", 0, -2)
  pcall(bar.SetFrameLevel, bar, 231)
  pcall(bar.EnableMouse, bar, true)
  pcall(bar.RegisterForClicks, bar, "LeftButtonUp")
  pcall(bar.RegisterForDrag, bar, "LeftButton")
  bar:SetScript("OnDragStart", function()
    pcall(root.SetMovable, root, true)
    pcall(root.StartMoving, root)
    pcall(root.StopMovingOrSizing, root)
    pcall(root.StartMoving, root)
  end)
  bar:SetScript("OnDragStop", function() pcall(root.StopMovingOrSizing, root) end)
  local t = uiText(bar, 11, 0.95, 0.82, 0.35)
  t:SetPoint("CENTER", bar, "CENTER", 0, 0)
  t:SetText(string.format(L("LOAD_OK"), VERSION))
  local body = uiText(root, 10, 0.88, 0.86, 0.80)
  body:SetPoint("TOPLEFT", root, "TOPLEFT", 14, -34)
  pcall(body.SetWidth, body, W - 28)
  pcall(body.SetJustifyH, body, "LEFT")
  local lines = { L("LOAD_HINT"), L("GUIDE_TITLE"), L("GUIDE_S1"), L("GUIDE_S2"), L("GUIDE_S3"), L("GUIDE_S4") }
  body:SetText(table.concat(lines, "\n"))
  loadUI.lineCount = table.getn(lines)
  loadUI.bodyText = table.concat(lines, "\n") -- ★读值口：断言要能读弹窗正文（引导已从聊天移到这里）
  local tip = uiText(root, 9, 0.62, 0.60, 0.52)
  tip:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 14, 44)
  pcall(tip.SetWidth, tip, W - 28)
  pcall(tip.SetJustifyH, tip, "LEFT")
  tip:SetText(L("LOADPOP_TIP"))
  loadUI.tipText = L("LOADPOP_TIP")
  -- 按钮（本文件没有通用按钮件 → 就地建一个；与 EVAL_TN 的 bBtn 同款）
  local function mkBtn(x, w2, label, fn)
    local b = CreateFrame("Button", nil, root)
    b:SetWidth(w2) b:SetHeight(22)
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
  -- [知道了] = 下次不再弹（悬停 tooltip 说明）
  local thanks = mkBtn(W - 220, 100, L("LOADPOP_THANKS"), function()
    if type(cfg) == "table" then cfg.loadMsgSeen = true end
    pcall(root.Hide, root)
    say(L("LOADPOP_THANKS_TIP"))
  end)
  -- [关闭] = 每次载入都显示
  local closeB = mkBtn(W - 112, 100, L("LOADPOP_CLOSE"), function()
    if type(cfg) == "table" then cfg.loadMsgSeen = false end
    pcall(root.Hide, root)
  end)
  loadUI.thanks, loadUI.closeBtn = thanks, closeB
  -- 悬停 tooltip（用户要求「知道了」要有 tooltip 提醒）
  local function hover(btn, text)
    if not btn or type(btn.SetScript) ~= "function" then return end
    pcall(btn.SetScript, btn, "OnEnter", function()
      if type(GameTooltip) ~= "table" and type(GameTooltip) ~= "userdata" then return end
      pcall(GameTooltip.SetOwner, GameTooltip, btn, "ANCHOR_RIGHT")
      pcall(GameTooltip.ClearLines, GameTooltip)
      pcall(GameTooltip.AddLine, GameTooltip, text)
      pcall(GameTooltip.Show, GameTooltip)
    end)
    pcall(btn.SetScript, btn, "OnLeave", function() pcall(GameTooltip.Hide, GameTooltip) end)
  end
  hover(thanks, L("LOADPOP_THANKS_HOVER"))
  hover(closeB, L("LOADPOP_CLOSE_HOVER"))
  pcall(root.Hide, root)
  loadUI.root = root
end
-- 载入时调用：cfg.loadMsgSeen 为真就不再弹（force = 手动重看，无视开关）
function EVAL_LOADPOP_SHOW(force)
  if not force and type(cfg) == "table" and cfg.loadMsgSeen then return false end
  loadPopBuild()
  pcall(loadUI.root.Show, loadUI.root)
  return true
end
function EVAL_LOADPOP_HIDE()
  if loadUI.root then pcall(loadUI.root.Hide, loadUI.root) end
end
-- 测试：走**真实 OnClick**（不是只调钩子）
function EVAL_TEST_LOADPOP_CLICK(which)
  loadPopBuild()
  local b = (which == "close") and loadUI.closeBtn or loadUI.thanks
  if not b then return false end
  local ok, fn = pcall(b.GetScript, b, "OnClick")
  if ok and type(fn) == "function" then pcall(fn) return true end
  return false
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
    -- ★★★1.73.42n 头衔抽卡：进游戏就重算一次（方案库可能变了）——**只升不降**，已抽过的档绝不重抽；
    --   新达到的档在这里完成「每档只抽一次」的抽取（不必等玩家去点分享或敲命令）。
    if type(EVAL_TITLE_REFRESH) == "function" then pcall(EVAL_TITLE_REFRESH) end
    -- ★1.73.63 登录也查一次彩蛋闸门（离线时方案可能已经达标：比如上次在别的机器上编辑过存档）
    if type(EVAL_TITLE_EGG_CHECK) == "function" then pcall(EVAL_TITLE_EGG_CHECK) end
    -- ★1.71.22 方案快捷键派发上线：登录时把 ActionButtonDown/Up 接管装上（运行中立即生效，无需重启）。
    --   ★装不上要**如实说**（客户端若没这两个全局，按键就永远不会触发 —— 不许假装成功）。
    if type(EVAL_BIND_INSTALL) == "function" then
      if not EVAL_BIND_INSTALL() then
        say("方案快捷键：本客户端没有 ActionButtonDown/Up 全局，按键派发装不上（功能不可用）")
      end
    end
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
    -- ★1.74.5 猎人助手「一键喂食」：上次开着的话恢复图标（含拖到的位置）——
    --   用户实测：开着一键喂食、把图标拖好，/reload 后图标**不见了**；
    --   根因 = 开关只存状态，而图标帧是「点开关那一下」才懒建的，登录流程里没人重建它。
    if type(EVAL_HH_RESTORE) == "function" then pcall(EVAL_HH_RESTORE) end
    -- ★1.74.5 消耗品助手（tools/ConsumableHelper.lua）：同一条纪律 —— 上次开着就恢复
    if type(EVAL_CH_RESTORE) == "function" then pcall(EVAL_CH_RESTORE) end
    -- ★1.74.7 骑乘助手（tools/DismountHelper.lua）：开关开着就重建下马图标（仍懒：关着一个帧都不建）；
    --   顺带确保自动下马的事件帧在（它在模块内自查开关，关着不注册）
    if type(EVAL_DH_RESTORE) == "function" then pcall(EVAL_DH_RESTORE) end
    if type(EVAL_DH_EVENTS_ENSURE) == "function" then pcall(EVAL_DH_EVENTS_ENSURE) end
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
    -- 1.72.1：加载成功提示 + 新手引导
    -- ★1.72.2（用户要求：「之前的新手引导功能需要在这里显示」）：引导改成**每次加载都打**——
    --   原来用 cfg.guideSeen 只出一次，新人不一定第一局就盯着聊天框，错过就**再也看不到**了。
    --   ★废弃键：cfg.guideSeen 不再读写（存量存档里残留的 true 无害，不再影响行为）。
    say(string.format(L("LOAD_OK"), VERSION))
    -- ★★★1.73.35 用户第 3 条：载入信息**移到独立弹窗**（原来往聊天打 7 行）——
    --   聊天只留一行「已加载」，指引/提示全在弹窗里；弹窗的 [知道了]/[关闭] 决定下次还弹不弹。
    if type(EVAL_LOADPOP_SHOW) == "function" then
      EVAL_LOADPOP_SHOW()
    else
      say(L("LOAD_HINT"))
      EVAL_HELP_GUIDE(false)
    end
  end
end)