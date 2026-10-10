-- ============================================================================
-- EH_Damage · 增强伤害显示（浮动战斗信息）独立子插件
-- ----------------------------------------------------------------------------
-- 血统与边界（调研定案，别回头再踩）：
--   · 动画引擎参考 DamageEx(Nampower 2026-04-16)：动画槽池 + smoothstep 淡入淡出
--     (t*t*(3-2t)) + 暴击三段缩放 + 彩虹弧线(重力衰减) + 防重叠游标。
--   · DamageEx 的「结构化战斗事件 / GUID / 姓名板附着」全部依赖 Nampower 客户端
--     补丁，本客户端(EmberVeil) 一律没有 ⇒ 事件源只能走 SCT 模式
--     （解析 CHAT_MSG_* 文本事件）。
--     ★★姓名板附着**做不到**（2026-10-08 定案，别再重做）：本客户端姓名板是 UE 引擎 widget
--     （AzerothNameplateWidget/…WidgetComponent + HealthPlateComponent；Lua 侧只有 Show/HideNameplates
--     四个开关函数），且无 GUID / 单位位置 / 世界→屏幕 API ⇒ 自绘文字锚不到怪头顶那条浮动姓名板。
--   · 文本模式 = zhCN 尽力而为：**事件名与文本格式不许猜**（铁律 5）⇒ 内置
--     「捕获环」/edmg 捕获 + /edmg 事件 把真机原文落盘，供逐条校准模式表。
-- 客户端配方（项目既有判据）：
--   · OnUpdate 零形参：dt 只能从全局 arg1 取，取不到用 GetTime() 差值推。
--   · 节拍帧宿主 = WorldFrame（开全屏地图会隐藏 UIParent ⇒ 挂 UIParent 节拍停摆）。
--   · 一个模块只许一个节拍帧，挂/摘唯一入口 beatSync()；关断四件事（资源回收 /
--     节拍停止 / 数据重置 / 图层清理）。
--   · 1.12 无销毁帧/纹理 API ⇒ 槽池建一次、只 Show/Hide。
--   · 纯色纹理只有 Interface\Buttons\WHITE8X8 + SetVertexColor 可靠。
--   · 字体链 FZLBJW→FRIZQT→ARIALN 全程 pcall；FontString 不吃鼠标 ⇒ 热区用透明 Button。
-- ============================================================================

local BUILD = "0.2.48"

-- ★★★插件目录名 = 本文件所在目录 + `EH_Damage.toc` 的文件名 —— **聊天播报的前缀就用它**
--   （用户 2026-10-10：「插件载入信息换成插件目录名」：截图里旧的中文前缀与 `[EH_DPS]` 两种写法混着，
--    统一成「一眼看出是哪个插件目录」的目录名；与子插件 EH_DPS 的 `[EH_DPS]` 同一口径）
--   ★**单一来源**：`say` 是唯一拼前缀的地方（全文件不许再出现中文前缀那类字面量）；
--    真要改目录名 ⇒ **三处一起改**（目录名 / `EH_Damage.toc` / 这个常量）。
local ADDON_NAME = "EH_Damage"

local D = {}                      -- 命名空间（跨函数共享件全挂这里，控 local 数）
_G["EH_DMG"] = D                  -- 调试/桥接口（子插件独立，不依赖宿主）

-- ----------------------------------------------------------------------------
-- 配置：显示项（与暴雪「浮动战斗信息」面板逐行对齐）
--   ★★★def = 默认勾选，**2026-10-08 按用户真机截图 + 存档 `EH_DAMAGE_CFG` 逐项定稿**
--   （用户：「将以上作为默认值」）⇒ 以后改默认勾选只改这一列；★「恢复默认」也走这张表。
-- ----------------------------------------------------------------------------
local ITEMS = {
  { id = "lowHealth",    def = true,  zh = "生命法力过低显示" },
  { id = "auraGain",     def = false, zh = "效果显示" },
  { id = "auraFade",     def = false, zh = "效果消失显示" },
  { id = "combatState",  def = false, zh = "战斗状态显示" },
  { id = "misses",       def = true,  zh = "躲闪/招架/未击中显示" },
  { id = "mitigation",   def = true,  zh = "伤害减免显示" },
  { id = "reputation",   def = true,  zh = "声望显示" },
  { id = "reactSpell",   def = true,  zh = "反击法术和技能显示" },
  { id = "healerNames",  def = true,  zh = "友方治疗者姓名显示" },
  { id = "comboPoints",  def = true,  zh = "连击点显示" },
  { id = "energize",     def = false, zh = "能量获取显示" },
  { id = "honor",        def = true,  zh = "荣誉显示" },
  { id = "targetDamage", def = true,  zh = "目标伤害显示" },
  { id = "dotDamage",    def = false, zh = "周期性伤害" },
  { id = "petDamage",    def = true,  zh = "宠物伤害" },
  -- 附加项（截图之外、DamageEx 血统里有）：受到的伤害
  { id = "incoming",     def = true,  zh = "受到的伤害（附加）" },
}

local DIRS = { "up", "down", "arc", "angleUp", "angleDown", "horiz", "sprinkler", "sine",
               "burst", "burstL", "burstR" }
local DIR_ZH = { up = "向上滚动", down = "向下滚动", arc = "抛物线滚动",
                 angleUp = "斜上抛物", angleDown = "斜下抛物", horiz = "水平散开",
                 sprinkler = "洒水散开", sine = "正弦上升",
                 burst = "极速蹦出", burstL = "极速蹦出·斜左", burstR = "极速蹦出·斜右" }

-- ★★曲线函数库（0.2.23；用户：「模仿官方的伤害展现方式…有哪些曲线函数支持吗?增加专门曲线函数的配置项?」）
--   全部输入 t∈[0,1]、输出进度（绝对时间驱动）；官方 FCT 手感 = **缓出**（快起慢收）；
--   `back` 会**过冲到终点以上再回落**（~1.10 处），就是「蹦」的那一下。
local CURVES = {
  cubic = function(t) local u = 1 - t return 1 - u * u * u end,          -- 缓出立方（官方手感主力）
  quad  = function(t) local u = 1 - t return 1 - u * u end,              -- 缓出平方（稍柔）
  back  = function(t) local c1, c3 = 1.70158, 2.70158 local u = t - 1
            return 1 + c3 * u * u * u + c1 * u * u end,                  -- 回弹过冲（蹦）
  expo  = function(t) if t >= 1 then return 1 end return 1 - 2 ^ (-10 * t) end, -- 指数缓出（起步最暴）
}
local CURVE_ORD = { "cubic", "quad", "back", "expo" }
local CURVE_ZH = { cubic = "缓出立方", quad = "缓出平方", back = "回弹过冲", expo = "指数缓出" }

local function easeCurve(name, t)
  local fn = CURVES[name or "cubic"] or CURVES.cubic
  local ok, v = pcall(fn, t)
  if ok and type(v) == "number" then return v end
  return t
end

local DEF = {
  -- ★★★2026-10-08 默认档整份重定（用户真机截图 +「将以上作为默认值」）——
  --   下面每个值都对应面板上一格，改之前先问一句「用户是不是又调过面板了」：
  --   滚动方向 极速蹦出·斜右 · 速度 200 · 时长 2.5 · 曲线 指数缓出 · 移动上限 35%
  --   字号档位 特大(4/6) · 受击下移 -44 · 图集缩放 100% · 描边样式 同色光晕
  --   缩放曲线 指数缓出 · 初始缩放 40% · 暴击幅度 100% · 尾声缩小 25%
  --   自带字体图集 开 · 暴击缩放动画 开 · 技能图标 开 · 技能名文本 关
  --   ★只影响「新装 / 缺这个键的老存档」与「恢复默认」；已有显式值的存档一个字节都不动。
  master = true,
  direction = "burstR",    -- 极速蹦出·斜右
  curve = "expo",          -- 指数缓出（蹦出系方向用）
  clampPct = 35,           -- 移动上限（占屏 %；行程夹取 + 屏界保险丝，5~60）
  fontTier = 4,            -- 字号档位 1小/2中/3大/4特大/5巨大/6超大
  speed = 200,             -- 像素/秒
  duration = 2.5,          -- 秒
  critAnim = 1,            -- 暴击缩放动画开关
  showIcon = true,         -- 技能图标（法术书名→图标缓存，查不到就不画）
  showSpellText = false,   -- 技能名纯文本（默认关；开了 = 「撕裂 9」「次级治疗术 +154」这样带名字）
  posX = 0, posY = -60,    -- 主锚点（屏幕中心偏移，逻辑单位）★截图里没有锚点 ⇒ 这两项没动
  -- ★0.2.28 受击锚点下移量（用户真机报障「受到的伤害数字太下面的，距离锚点太远了」）：
  --   旧默认 -170 太靠下（-60 + -170 = 屏幕中线以下 230px）+ 「down」车道还会继续往下漂
  --   ⇒ 数字整段落在动作条那一带。默认收到 -120，并且**不再是只能改代码的死值**：
  --   面板「受击下移」±10 步进 + 编辑模式**第二个红色锚点可直接拖**（写的就是这个字段）。
  inOffY = -44,            -- 受到伤害行相对主锚点的下移量（负 = 更靠下）★2026-10-08 用户截图定稿
  -- ★0.2.29 战斗数字「自带字体图集」（R4：插件目录里的 TTF 离线渲成 TGA，运行期用纹理画数字）。
  --   为什么不用 SetFont 直接换字体：本客户端 `FontString:SetFont` 是**静默失败** API，而「自建 Font +
  --   SetFontObject(散装 TTF)」被客户端自带插件实测为「文字直接消失」（unrealUI 知识库
  --   fonts.setfont_silent_failure / RUNTIME_FAILURE_CONFIRMED）⇒ 走**已验证能加载的贴图路**。
  fontAtlas = true,        -- ★2026-10-08 默认改**开**（用户截图定稿：战斗数字直接用插件自带字体图集）
  faScale = 100,           -- 图集整体缩放 %（= 字号的**连续**微调；档位管粗调）
  -- ★0.2.30 图集**描边风格**（用户真机反馈「字体黑色边框能换个吗?美化一点吗?」）：
  --   旧版只有一种：纯白字 + 硬黑描边（0.06×格高，最大档 5px，观感偏「糊黑圈」）。
  --   现在每种风格**各自一套 TGA + 各自一套度量**（描边/暗晕不同 ⇒ 墨区不同），id 见 D.FAS_ORD。
  --   ★默认 = glow 同色光晕（2026-10-08 用户截图定稿；载入期一次性归一 + 如实出声见 cfgEnsure）。
  faEdge = "glow",         -- 描边风格 id（soft/hard/glow/shadow/plain）
  -- ★0.2.31 缩放动画（**图集行专用**）：用户问「这种形式的伤害数字是否就支持动画曲线平滑缩放了?」
  --   答案是「路子通了，但得写这段代码」—— 文字行那条路缩放已被 0.2.0~0.2.21 逐条真机证死；
  --   图集行的数字是**纹理格** ⇒ 宽/高/锚点可每拍现算 ⇒ 连续 + 曲线缓动成立（**只补发几何，不碰贴图/UV**）。
  animCurve = "expo",      -- 缩放曲线（复用 CURVES：cubic/quad/back/expo）★2026-10-08 用户截图定稿
  animAmp = 100,           -- **暴击鼓包**幅度 %（1 → 1+amp → 1；0 = 不鼓包，**不再管出生弹入**）
  -- ★0.2.34 出生弹入幅度**独立成一个参数**（用户：「伤害文字初始出现缩放增加可缩放参数」）：
  --   出生那一瞬的缩放 = animStart%，0.35s 内平滑回到 100%（`D.FA_POP_SEC`，走同一条 animCurve）。
  --   100 = 不弹入（出生即原尺寸）· <100 = 由小涨大 · **>100 = 由大缩回**（也是合法观感）。
  --   ★老存档兼容：0.2.31~0.2.33 里「幅度 = 0」就是「关掉缩放动画」的意思（当时只有那一个开关）
  --   ⇒ 迁移时把这种存档的 animStart 落成 100，原样保留用户那次选择（见 cfgEnsure）。
  animStart = 40,          -- ★2026-10-08 用户截图定稿（由小涨大，起点 40%）
  -- ★0.2.35 **尾声缩小**（用户：「尽量接近尾声动画同步. 缩小切隐藏」）：数字生命最后那段
  --   （**与淡出同一相位**：淡出占后 50% 的寿命，这里就跟着那 50% 走，到点正好一起消失）从 100% 缩到 (100-animEnd)%。
  --   0 = 不缩；100 = 缩到下限（`D.FA_K_MIN`=10%，不会出现 0 宽高纹理）⇒ 也就是「缩小切隐藏」。
  animEnd = 25,
  capture = false,         -- 诊断：捕获未识别的战斗文本进环
}
-- 受击下移的可调范围（面板步进与编辑模式拖拽**共用同一对常量**，绝不各写一份）
D.INOFF_MIN, D.INOFF_MAX = -400, -20
-- ★0.2.39 主锚点 X/Y 的面板步进范围（屏幕中心偏移的逻辑单位；±600 足够覆盖 1024×768 逻辑屏）
--   ★与 inOffY 同一把尺子：**整数**字段，面板「伤害锚点 X/Y」两颗 ± 走这里夹取
D.POS_MIN, D.POS_MAX = -600, 600
-- 图集缩放范围（同上：面板步进与读值口共用）
D.FAS_MIN, D.FAS_MAX = 60, 200
-- ★0.2.34 初始缩放范围（%）：<100 由小涨大 · 100 不弹入 · >100 由大缩回
D.ANS_MIN, D.ANS_MAX = 30, 150
-- ★0.2.35 尾声缩小范围（%）：0 = 不缩 · 100 = 缩到下限
D.AEN_MIN, D.AEN_MAX = 0, 100
-- ★0.2.31 缩放动画的常量（面板步进 / 读值口 / 档图挑选**共用同一批**，绝不各写一份）：
--   幅度范围 0~**200**%（默认 25；★0.2.33 上限 50 → 100；★0.2.41 按用户要求 100 → **200**）
--   · 出生弹入 0.35s · 暴击鼓包 0.35s；★面板步进仍是 ±5（0~200 = 41 档；低端精度比档数多更重要）
D.ANIM_MIN, D.ANIM_MAX = 0, 200
D.FA_POP_SEC, D.FA_CRIT_SEC = 0.35, 0.35
-- ★0.2.33 缩放系数下限：幅度 100% 时出生弹入的起点算出来是 **0 倍**（0 宽/高的纹理没意义，
--   「从 0 涨出来」视觉上也等于凭空出现）⇒ 夹到 10%。幅度 ≤ 90% 时这个下限**永远不会生效**。
D.FA_K_MIN = 0.1
-- ★0.2.30 描边风格 / ★0.2.37 追加 4 种「成品字形」风格：**顺序 = 面板 ± 循环顺序**，中文名 = 界面显示
--   · soft/hard/glow/shadow/plain = **参数式**（TTF 现渲，生成器 tmp/gen_fontatlas.py）
--   · out9c/shd9c/outwx/shdwx = 用户提供的**成品字形位图**（自带描边或阴影，离线切图，
--     生成器 tmp/gen_fontatlas_custom.py --install ⇒ media/fontdigits_<id>_<档>.tga + FontDigitsExtra.lua）
--   ★两族**并列可选、互不覆盖**：成品字形那边忽略「描边参数」（它自己没有参数）
D.FAS_ORD = { "soft", "hard", "glow", "shadow", "plain", "out9c", "shd9c", "outwx", "shdwx" }
D.FAS_ZH = {
  soft = "柔和暗晕", hard = "硬黑描边", glow = "同色光晕", shadow = "右下投影", plain = "无描边",
  -- ★成品字形那 4 个的**显示名刻意收短**：面板「描边样式」单元格的值框只有 66px，
  --   名字长了会折成两行压到下一行（现有「极速蹦出·斜右」就会折行）⇒ 全名留在 README / `/edmg 描边`
  out9c = "9c·硬描边", shd9c = "9c·软阴影", outwx = "武侠·硬描边", shdwx = "武侠·软阴影",
}
-- ★0.2.38 **「字体图集」分组**（用户：「我怎么没看到配置字体贴图的地方」）—— 面板**专门一行**选字形素材：
--   组内 `styles` = 这一套字形可选的样式（内置字体 = 5 种参数式描边；两套成品字形 = 硬描边/软阴影 两版）。
--   ★**配置真值仍然只有 `faEdge` 一个**（= 完整图集 id）⇒ 这一行与「描边样式」都是它的**派生视图**：
--     「字体图集」± 换组（组内取同一下标，越界夹到最后一个）、「描边样式」± 只在**当前组内**循环。
--   ★别再加第二个配置键（两个键会各自漂移；`faStyleSet` 是唯一写口）。
D.FAS_SETS = {
  { id = "ttf", zh = "内置字体", styles = { "soft", "hard", "glow", "shadow", "plain" } },
  { id = "f9c", zh = "9c原版",   styles = { "out9c", "shd9c" } },
  { id = "fwx", zh = "古风武侠", styles = { "outwx", "shdwx" } },
}

local say                                   -- ★前向声明：cfgEnsure 的迁移播报用到它（否则绑全局 nil）

local function cfgEnsure()
  local c = rawget(_G, "EH_DAMAGE_CFG")
  if type(c) ~= "table" then c = {} rawset(_G, "EH_DAMAGE_CFG", c) end
  -- ★0.2.0 一次性迁移（**必须先于 DEF 填缺**）：旧 fontSize 像素值 → 档位
  --   （改字号机制已被探针全否，档位字体对象才有效）；只有老存档（有 fontSize 没 fontTier）才折算
  if c.fontTier == nil and c.fontSize ~= nil then
    local px = tonumber(c.fontSize) or 44
    c.fontTier = (px <= 14 and 1) or (px <= 18 and 2) or (px <= 30 and 3) or 4
  end
  -- ★0.2.28 受击下移：**只升级「旧默认值」这一个确切值**（-170 —— 面板此前没有这个旋钮，
  --   所以存档里出现 -170 只可能是旧默认被物化），用户自己拖/调出来的值一个字节都不动；
  --   只做一次（inOffMig）+ 如实出声（行为改变必须出声：老用户会觉得数字位置变了）。
  if c.inOffY == -170 and c.inOffMig ~= true then
    c.inOffY = DEF.inOffY
    c.inOffMig = true
    if type(say) == "function" then
      -- ★聊天行是纯文本 ⇒ 不许出现 `**`（会原样画出来；项目在案）
      say("受击数字默认位置已上调（" .. tostring(DEF.inOffY) ..
        "）：面板「受击下移」可调，编辑模式里红色锚点可直接拖")
    end
  end
  -- ★0.2.28（同版收口）**受击下移只取整数**（用户真机截图：面板显示「-43.86591064453」还折成两行）：
  --   拖拽写的是光标差（浮点），所以这里把**已经存进去的浮点老值**一次性归整；之后写入口也一律取整。
  if type(c.inOffY) == "number" then c.inOffY = math.floor(c.inOffY + 0.5) end
  -- ★0.2.30 图集描边风格：老存档没有这个键 ⇒ 落成新默认（soft）并**如实出声一次**
  --   （行为改变必须出声：老用户会看到战斗数字的描边换了样；面板「描边样式」或 `/edmg 描边 hard` 可换回原观感）
  if c.faEdge == nil then
    c.faEdge = DEF.faEdge
    if type(say) == "function" then
      say("战斗数字描边已换成「" .. (D.FAS_ZH[DEF.faEdge] or DEF.faEdge) ..
        "」：面板「描边样式」± 或 /edmg 描边 <风格> 可换（hard = 原来的硬黑描边）")
    end
  elseif type(c.faEdge) ~= "string" or D.FAS_ZH[c.faEdge] == nil then
    c.faEdge = DEF.faEdge          -- 垃圾值（手改存档 / 旧实验）⇒ 归一到默认，绝不把不认识的 id 用下去
  end
  -- ★0.2.34 出生弹入幅度**独立成参数**：老存档里「幅度 = 0」原本就是「关掉缩放动画」（当时只有那一个开关）
  --   ⇒ 这种存档补上「初始缩放 100%」，把用户那次选择原样保留（只做一次 + 如实出声）；其余情况落默认 75%。
  if type(c.animStart) ~= "number" then
    if tonumber(c.animAmp) == 0 then
      c.animStart = 100
      if type(say) == "function" then
        say("缩放动画：幅度 0 = 关（你原来的选择已保留 —— 出生弹入也关掉了）；" ..
          "现在「初始缩放」与「暴击幅度」是两个独立参数，要弹入就调「初始缩放」")
      end
    else
      c.animStart = DEF.animStart
    end
  end
  -- ★0.2.36 默认档整份重定（用户截图 +「将以上作为默认值」）：**只补「缺的键」**——
  --   已有显式值的存档一个字节都不动（用户自己调出来的当然保留），所以真正会换观感的只有
  --   **0.2.31 之前的老存档**（它们没有 animAmp/animCurve/animEnd ⇒ 补上新的动画默认）⇒ 如实说一次。
  if c.direction ~= nil and c.animAmp == nil then
    if type(say) == "function" then
      say("默认档已更新（初始缩放 " .. tostring(DEF.animStart) .. "% · 暴击幅度 " ..
        tostring(DEF.animAmp) .. "% · 尾声缩小 " .. tostring(DEF.animEnd) .. "% · 缩放松紧曲线 " ..
        (CURVE_ZH[DEF.animCurve] or DEF.animCurve) .. "）：面板每一格都能改，恢复默认也回到这一套")
    end
  end
  for k, v in pairs(DEF) do if c[k] == nil then c[k] = v end end
  for _, it in ipairs(ITEMS) do
    if c["it_" .. it.id] == nil then c["it_" .. it.id] = it.def and true or false end
  end
  if type(c.ring) ~= "table" then c.ring = {} end
  return c
end
local function C() return cfgEnsure() end
local function itemOn(id) return C()["it_" .. id] == true end

-- ----------------------------------------------------------------------------
-- 小工具
-- ----------------------------------------------------------------------------
say = function(m)
  local f = rawget(_G, "DEFAULT_CHAT_FRAME")
  -- ★前缀 = 插件目录名（`ADDON_NAME`，见文件头）——全插件**唯一**拼聊天前缀的地方
  if f and f.AddMessage then pcall(f.AddMessage, f, "|cffff6666[" .. ADDON_NAME .. "]|r " .. tostring(m)) end
end

local TEX_WHITE = "Interface\\Buttons\\WHITE8X8"
local function solid(t, r, g, b, a)
  if type(t.SetTexture) == "function" then pcall(t.SetTexture, t, TEX_WHITE) end
  pcall(t.SetVertexColor, t, r, g, b, a)
end

local function mkFont(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local ok = pcall(fs.SetFontObject, fs, GameFontHighlight)
  if not ok then pcall(fs.SetFontObject, fs, GameFontNormal) end
  -- 字体链兜底（FZLBJW→FRIZQT→ARIALN，全程 pcall）
  pcall(function()
    if not fs:GetFont() then
      for _, f in ipairs({ "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }) do
        if pcall(fs.SetFont, fs, f, 12, "") then break end
      end
    end
  end)
  return fs
end

local function smoothstep(t) return t * t * (3 - 2 * t) end   -- DamageEx 同款淡入淡出曲线
local function clamp01(v) if v < 0 then return 0 elseif v > 1 then return 1 end return v end

-- ----------------------------------------------------------------------------
-- 技能名 → 图标（法术书扫描；GetSpellName/GetSpellTexture 是本客户端在案可用的两条 API）
--   ★只缓存法术书里有的：别人施的（如队友的「恢复」）只有你也会才查得到，查不到不画（绝不画 ? 图）
-- ----------------------------------------------------------------------------
D.iconCache = {}
-- ★★★0.2.47 载入期原生调用收窄：法术书扫描的**上界改成「现读」**，不再拿写死的 900 当探针。
--   ① **为什么改**：本函数在 `VARIABLES_LOADED` 那一拍（读条末尾）跑，是全插件唯一「载入期拿越界下标
--      批量打原生 API」的地方 —— `pcall` 只兜 Lua 异常，**兜不住原生访问违规** ⇒ 别的客户端/版本若对
--      越界下标不做检查，这里就是「一进游戏（读条）就崩」的现场。
--   ② **判据出处（客户端自带 FrameXML = 权威）**：`Interface\FrameXML\SpellBookFrame.lua:24/36` 写的是
--      `local name, texture, offset, numSpells = GetSpellTabInfo(i)` ⇒ **合法全局下标 = offset+1 .. offset+numSpells**；
--      宿主 `Engine.lua:2237~2240` 就是 `for i = off + 1, off + num`（真机在案）⇒ 上界 = 各 tab 的 `offset+numSpells` 最大值。
--   ③ ★★**读不出 / 读不齐 ⇒ 一律退回 900**（fail-open = 今天的行为）：**绝不因为判不出上界而少扫一格**
--      ⇒ 「判不出」只会让原生调用面回到原样，绝不会丢掉任何图标。
--   ④ ★★**返回值恒在 `1..900` 之间，绝不超过原上界 900**：客户端若报出天文数字/脏值，退回 900 而**不是**放大调用面。
--   ⑤ `SPELL_TOP_MARGIN` = 容忍 `GetSpellTabInfo` 报表差一两格（真实条数 ≤ 上界才不丢图标）；
--      正常客户端（越界返回 nil）这 8 格**一次都不会跑**（循环在真实末尾的下一格就 break），零代价。
--   ⑥ ★**保留「遇 nil 就 break」原语义**，绝**不**加「空串也算停」—— 空串现在是「跳过这一格、继续扫」，
--      改成停止会在遇到中间空串时丢掉它后面**所有**技能的图标（真机行为风险）。
local SPELL_TOP_MARGIN = 8
local function spellbookTop()
  if type(GetNumSpellTabs) ~= "function" or type(GetSpellTabInfo) ~= "function" then return 900 end
  local okN, nt = pcall(GetNumSpellTabs)
  if not okN or type(nt) ~= "number" or nt <= 0 then return 900 end
  local top = 0
  for tab = 1, nt do
    local okT, _nm, _tex, off, num = pcall(GetSpellTabInfo, tab)
    if not (okT and type(off) == "number" and type(num) == "number" and off >= 0 and num >= 0) then
      return 900                          -- 有一档判不出 ⇒ 整体退回原上界（绝不因判不出而少缓存图标）
    end
    if off + num > top then top = off + num end
  end
  if top <= 0 then return 900 end
  local b = top + SPELL_TOP_MARGIN
  if b > 900 then b = 900 end             -- ★上限绝不超过 900（脏值也不许放大调用面）
  return b
end
function D.iconScan()
  local c = {}
  if type(GetSpellName) == "function" and type(GetSpellTexture) == "function" then
    for i = 1, spellbookTop() do
      local okN, name = pcall(GetSpellName, i, "spell")
      if not okN or not name then break end
      local okT, tex = pcall(GetSpellTexture, i, "spell")
      if okT and tex and not c[name] then c[name] = tex end
    end
  end
  -- ★★0.2.27 宠物技能图标（用户：「宠物技能击中能显示对应图标吗?」；真机句式
  --   「Cat的撕咬击中雌性草原狮造成8点伤害。」）：
  --   来源① = **宠物动作条** `GetPetActionInfo(i)`（Pet 类 API，本客户端 exe/索引都在案；
  --     vanilla 形状 = name, subtext, texture, isToken, isActive, …）—— 撕咬/低吼这类宠物技能就在这里；
  --     token 形态的名字（PET_ACTION_*）要经 `_G` 转本地化名，转不出就当没有；
  --   来源② = 宠物法术书 `GetSpellName(i, "pet")`（客户端不认这个 bookType 就静默跳过，绝不当成错）。
  --   ★仍然守既有铁律：**查不到就一个图标都不画**（绝不画 ? 图）。
  if type(GetPetActionInfo) == "function" then
    for i = 1, 10 do
      local ok, n, _sub, tex, isToken = pcall(GetPetActionInfo, i)
      if ok and type(n) == "string" and n ~= "" then
        if isToken and type(rawget(_G, n)) == "string" then n = rawget(_G, n) end
        if type(tex) == "string" and tex ~= "" and not c[n] then c[n] = tex end
      end
    end
  end
  if type(GetSpellName) == "function" and type(GetSpellTexture) == "function" then
    for i = 1, 30 do
      local okN, name = pcall(GetSpellName, i, "pet")
      if not okN or type(name) ~= "string" or name == "" then break end
      local okT, tex = pcall(GetSpellTexture, i, "pet")
      if okT and tex and not c[name] then c[name] = tex end
    end
  end
  D.iconCache = c
end
local function iconOf(spellName)
  if not spellName then return nil end
  return D.iconCache and D.iconCache[spellName] or nil
end

-- ★0.2.27 从战斗文本里取「技能名」（配图用；句式 = 2026-10-08 用户真机日志）：
--   自己远程/技能：「你的自动射击击中雌性草原狮造成25点伤害。」「你的 撕裂 使 X 受到了…」
--   宠物技能　　：「Cat的撕咬击中雌性草原狮造成8点伤害。」（Cat = `UnitName("pet")`）
--   宠物普攻　　：「Cat击中雌性草原狮造成15点伤害。」⇒ **提不出技能名**（普攻不给图标，与玩家平砍同一把尺子）
--   玩家平砍　　：「你击中X造成12点伤害。」⇒ 同上
--   ★只用文本给名字、用 `UnitName("pet")` 锚定宠物，**不做任何「猜技能」**；查不到图标就不画。
local function spellFromMsg(m)
  if type(m) ~= "string" or m == "" then return nil end
  local sp = string.match(m, "^你的%s*(.-)%s*击中")        -- 自己的技能 / 远程自动射击
  if sp and sp ~= "" then return sp end
  local pet
  if type(UnitName) == "function" then
    local ok, v = pcall(UnitName, "pet")
    if ok and type(v) == "string" and v ~= "" then pet = v end
  end
  if pet and string.sub(m, 1, string.len(pet) + 1) == pet .. "的" then
    local rest = string.sub(m, string.len(pet) + 2)
    sp = string.match(rest, "^(.-)%s*击中") or string.match(rest, "^(.-)%s*对")
    if sp and sp ~= "" then return sp end
  end
  local who, sp2 = string.match(m, "^(.-)的(.-)%s*击中")    -- 宠物名兜底（拿不到 UnitName("pet") 时）
  if who and who ~= "你" and sp2 and sp2 ~= "" then return sp2 end
  return nil
end
D.spellFromMsg = spellFromMsg

-- ★★字号机制终案（0.2.0；探针 A~K 真机定案）：「改字号」（SetFont/SetTextHeight/帧缩放）
--   在本客户端全无效，但**分档字体对象**（Fonts.xml 自带大小的字体模板）有效，梯度 I<J<K。
--   ⇒ 字号 = 档位制：特大档数字行走 NumberFontNormalHuge（最大，数字优化；可能缺中文字形），
--   中文行走 GameFontNormalHuge（全字形）；其余档两族同名。
D.TIER = {
  { game = "GameFontNormal",       num = "GameFontNormal",       zh = "小" },
  { game = "GameFontNormalLarge",  num = "GameFontNormalLarge",  zh = "中" },
  { game = "GameFontNormalHuge",   num = "GameFontNormalHuge",   zh = "大" },
  { game = "GameFontNormalHuge",   num = "NumberFontNormalHuge", zh = "特大" },
  { game = "SystemFont_Huge3",     num = "SystemFont_Huge3",     zh = "巨大" },
  { game = "SystemFont_Huge4",     num = "SystemFont_Huge4",     zh = "超大" },
}
D.TIER_H = { 18, 24, 32, 48, 64, 84 }      -- 各档行距（防重叠用）
D.ICON_RATIO = 0.45                        -- 图标边长 = 行距 × 系数（0.2.10 起公式化：随档位动态现算，
                                           --   调档/加档自动跟随；要整体大小就调这一个系数，真机可调）
D.ICON_DY = -3                             -- 图标 y 微调（0.2.9；FontString 行盒比字形高 ⇒ 字面重心偏下，
                                           --   图标按行盒中心锚会偏高 ⇒ 下移对齐字面，真机可再调）
local KIND_NUMERIC = { damage = 1, dot = 1, pet = 1, heal = 1, incoming = 1, energize = 1, mitigation = 1 }
-- ★0.2.29：整条是否**纯 ASCII**（≤126）。数字字体（NumberFontNormalHuge = 客户端的大号数字字体）
--   **不含中文字形** ⇒ 「+298 [治疗者甲]」里的名字会被渲染成**空白**（真机截图里就是 `+298 []`，
--   括号在、字没了）⇒ 含非 ASCII 的整条一律退回**中文字体**（tt.game）。
local function isAsciiOnly(s)
  if type(s) ~= "string" then return false end
  for i = 1, string.len(s) do if string.byte(s, i) > 126 then return false end end
  return true
end
local function sizeApply(fs, tier, kind, asciiOnly)
  tier = math.max(1, math.min(table.getn(D.TIER), tonumber(tier) or 3))
  -- ★逐级向下回退：某一档的字体对象不存在（本客户端 Fonts.xml 未必全）就落下一档，绝不比配置的档显小
  for t = tier, 1, -1 do
    local tt = D.TIER[t]
    -- ★只有「整条纯 ASCII」才敢用数字字体（那族字体不含中文字形 ⇒ 中文名字会变成空白）
    local useNum = KIND_NUMERIC[kind] and (asciiOnly ~= false)
    local fo = rawget(_G, useNum and tt.num or tt.game)
    if fo then pcall(fs.SetFontObject, fs, fo) return end
  end
  local fo = rawget(_G, "GameFontNormal")
  if fo then pcall(fs.SetFontObject, fs, fo) end
end
local FONT_BASE = 22                    -- 历史常量（暴击系数语义已并入档位，留着防外部引用）
local FONT_CHAIN = { "Fonts\\FZLBJW.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF" }  -- mkFont 的字体链兜底

-- ----------------------------------------------------------------------------
-- 显示种类（kind）→ 颜色 / 车道 / 文案
--   车道 lane："out" = 主锚点（按 direction 滚动）；"in" = 受到伤害锚点（恒向下）
-- ----------------------------------------------------------------------------
local KIND = {
  damage    = { lane = "out", r = 1.00, g = 1.00, b = 0.30 },
  dot       = { lane = "out", r = 1.00, g = 0.60, b = 0.20 },
  pet       = { lane = "out", r = 0.50, g = 0.90, b = 1.00 },
  miss      = { lane = "out", r = 1.00, g = 0.40, b = 0.40 },
  mitigation= { lane = "out", r = 0.80, g = 0.60, b = 1.00 },
  auraGain  = { lane = "out", r = 0.50, g = 0.80, b = 1.00 },
  auraFade  = { lane = "out", r = 0.70, g = 0.70, b = 0.70 },
  combat    = { lane = "out", r = 1.00, g = 0.85, b = 0.30 },
  react     = { lane = "out", r = 1.00, g = 0.85, b = 0.30 },
  combo     = { lane = "out", r = 1.00, g = 0.50, b = 0.20 },
  honor     = { lane = "out", r = 1.00, g = 0.60, b = 0.80 },
  rep       = { lane = "out", r = 0.60, g = 1.00, b = 0.60 },
  energize  = { lane = "in",  r = 0.40, g = 0.70, b = 1.00 },
  heal      = { lane = "in",  r = 0.30, g = 1.00, b = 0.40 },
  incoming  = { lane = "in",  r = 1.00, g = 0.30, b = 0.30 },
  lowhp     = { lane = "in",  r = 1.00, g = 0.20, b = 0.20 },
  lowmana   = { lane = "in",  r = 0.30, g = 0.50, b = 1.00 },
}

-- kind → 控制它的显示项 id（nil = 不受开关管，总开关直接管）
local KIND_ITEM = {
  damage = "targetDamage", dot = "dotDamage", pet = "petDamage",
  miss = "misses", mitigation = "mitigation",
  auraGain = "auraGain", auraFade = "auraFade",
  combat = "combatState", react = "reactSpell",
  combo = "comboPoints", honor = "honor", rep = "reputation",
  energize = "energize", heal = "healerNames",
  incoming = "incoming", lowhp = "lowHealth", lowmana = "lowHealth",
}

-- ----------------------------------------------------------------------------
-- ★0.2.29 战斗数字「图集」渲染（R4）——把插件目录里的 TTF 离线渲成「每档一张 TGA」，运行期用纹理画数字
--   为什么走这条路：本客户端 `FontString:SetFont` 是**静默失败** API（保持继承字体、`GetFont` 还回报假读数），
--   而「自建 Font + SetFontObject(散装 TTF)」被客户端自带插件实测为「文字直接消失」
--   （unrealUI 知识库 fonts.setfont_silent_failure / RUNTIME_FAILURE_CONFIRMED）⇒ 用**已验证能加载的贴图路**。
--   收益：完全自包含（素材在 media\，两份都进包）、只影响本插件的战斗数字、**大小完全可控**
--   （档位管粗调 = 换图；`faScale` 管细调 = 缩放贴图）。
--   数据 = 生成物 `FontDigits.lua`（`python tmp/gen_fontatlas.py`）；charset 只有数字/符号 ⇒
--   **任何含中文或字母的整条一律回落 FontString**（不做半吊子混排；技能名行走回落，图标自然也不冲突）。
-- ----------------------------------------------------------------------------
local FA = { ready = false, ok = false, chars = "", nch = 0, idx = {}, tiers = {}, N = 0 }
local FA_MAXQ = 8            -- 单条最多几格（有界；40 槽 × 8 = 320 张上限，且**按需建** —— 开关关着一个都不建）

local function faEnsure()
  if FA.ready then return FA.ok end
  FA.ready = true
  local t = rawget(_G, "EVAL_EDMG_FONTDIGITS")
  if type(t) ~= "table" or type(t.tiers) ~= "table" then FA.ok = false return false end
  local ch = tostring(t.chars or "")
  if ch == "" then FA.ok = false return false end
  FA.chars, FA.nch = ch, string.len(ch)
  for i = 1, FA.nch do
    local one = string.sub(ch, i, i)
    if FA.idx[one] == nil then FA.idx[one] = i - 1 end      -- 字符 → atlas 第几格（0 基）
  end
  local n = 0
  for i = 1, table.getn(t.tiers) do
    local e = t.tiers[i]
    if type(e) == "table" and type(e.file) == "string" and tonumber(e.h) then
      -- ★0.2.29：**每格宽度逐字不同**（`cw` 字宽表 + `cx` 贴图内偏移 + `W` 总宽）；
      --   旧版只有等宽 `cellw`（保留兼容：没有 cw 时退回等宽排）。
      -- ★0.2.30：`st[风格]` = 每种描边风格**各自一套度量**（描边/暗晕不同 ⇒ 墨区不同，硬套一份会切边）；
      --   表里没有 `st`（旧生成的 FontDigits.lua）⇒ 全部风格都走顶层那套（= hard，向后兼容）。
      FA.tiers[i] = { file = e.file, h = tonumber(e.h), cellw = tonumber(e.cellw),
                      W = tonumber(e.W),
                      cw = (type(e.cw) == "table" and e.cw) or nil,
                      cx = (type(e.cx) == "table" and e.cx) or nil,
                      st = (type(e.st) == "table" and e.st) or nil }
      n = i
    end
  end
  FA.N, FA.ok = n, (n > 0)
  return FA.ok
end
-- 当前描边风格（配置值 → 白名单；不认识的值得不到 ⇒ 退默认 "soft"，绝不把垃圾值用下去）
local function faStyleNow()
  local v = C().faEdge
  if type(v) == "string" and D.FAS_ZH[v] ~= nil then return v end
  return DEF.faEdge
end
-- 风格的规范 id（接受 id 或**中文名**；都不认 ⇒ nil）
local function faStyleNorm(v)
  if type(v) ~= "string" or v == "" then return nil end
  if D.FAS_ZH[v] ~= nil then return v end
  for _, id in ipairs(D.FAS_ORD) do if D.FAS_ZH[id] == v then return id end end
  return nil
end
-- ★0.2.38 「字体图集」派生视图（配置真值只有 faEdge 一个，见 D.FAS_SETS 那段注释）
--   现在的风格属于哪一组（认不出 ⇒ 第一组 = 内置字体，绝不返回 nil）
local function faSetOf(style)
  for si = 1, table.getn(D.FAS_SETS) do
    local s = D.FAS_SETS[si]
    for k = 1, table.getn(s.styles) do if s.styles[k] == style then return s end end
  end
  return D.FAS_SETS[1]
end
local function faSetNow() return faSetOf(faStyleNow()) end
-- 找到某组里「当前风格的同下标」（越界夹到最后一个）—— 换组/点名组时共用，行为可预测
local function faSetPick(set)
  local cur = faStyleNow()
  local src = faSetNow().styles
  local idx = 1
  for k = 1, table.getn(src) do if src[k] == cur then idx = k break end end
  local n = table.getn(set.styles)
  if idx > n then idx = n end
  if idx < 1 then idx = 1 end
  return set.styles[idx]
end
-- 取某档、某风格的度量（★唯一取度量口）：返回 file, W, cw, cx
--   没有这个风格的表项（旧表 / `--only` 只重生成了一部分）⇒ 退回顶层那套（= hard）
local function faMetrics(t, style)  if type(t) ~= "table" then return nil end
  local e = t.st and t.st[style]
  if type(e) == "table" and type(e.file) == "string" then
    return e.file, tonumber(e.W), (type(e.cw) == "table" and e.cw) or nil, (type(e.cx) == "table" and e.cx) or nil
  end
  return t.file, t.W, t.cw, t.cx
end
-- 图集整体缩放（% → 倍率）；范围与面板步进**共用同一对常量**
local function faPct()
  return math.max(D.FAS_MIN, math.min(D.FAS_MAX, tonumber(C().faScale) or 100)) / 100
end
-- 整条都能用图集画吗（含中文/字母/空格一律 false ⇒ 回落字体）
local function faTextOK(s)
  if type(s) ~= "string" or s == "" then return false end
  if string.len(s) > FA_MAXQ then return false end
  for i = 1, string.len(s) do
    if FA.idx[string.sub(s, i, i)] == nil then return false end
  end
  return true
end
local function faQuad(s, i)
  if i > FA_MAXQ then return nil end
  s.fa = s.fa or {}
  if s.fa[i] then return s.fa[i] end
  if type(s.f.CreateTexture) ~= "function" then return nil end
  local ok, q = pcall(s.f.CreateTexture, s.f, nil, "OVERLAY")
  if not ok or not q then return nil end
  s.fa[i] = q
  return q
end
-- 槽复用：把上一次的数字格全部收起（换回文字行时必须做，否则两套叠着显示）
local function faClear(s)
  if not s.fa then return end
  for i = 1, FA_MAXQ do if s.fa[i] then pcall(s.fa[i].Hide, s.fa[i]) end end
end
-- 排一行：整组在 s.f 内**水平居中**（s.f 自己跟着轨迹走 ⇒ 数字天然跟着动画/淡入淡出）
--   ★★★**必须按「每个字自己的宽度」排**（`cw`）：等宽排会让窄字（尤其 `1`）后面空一大截 ——
--     真机报障原话「某些数字为什么空格有点大」（旧版格宽被最宽字形 `%` 撑出来）。UV 也按 `cx/W` 逐字切。
local function faLayout(s, text, tier, pct, r, g, b)
  if not FA.ok then return false end
  local t = FA.tiers[tier] or FA.tiers[FA.N]
  if not t then return false end
  -- ★0.2.30 先按**当前描边风格**取度量（file/W/cw/cx 四样同源，绝不混用两套 —— 混了就是错位切边）
  local file, tW, tcw, tcx = faMetrics(t, faStyleNow())
  if type(file) ~= "string" then return false end
  local n = string.len(text)
  if n == 0 or n > FA_MAXQ then return false end
  -- 第一趟：逐字查格号 + 累计总宽（宽度先按 1:1 累，最后统一乘缩放 ⇒ 少一轮乘法）
  local ci1, w1, total = {}, {}, 0
  for i = 1, n do
    local ci = FA.idx[string.sub(text, i, i)]
    if ci == nil then return false end
    local w = (tcw and tonumber(tcw[ci + 1])) or t.cellw
    if not w then return false end
    ci1[i], w1[i] = ci, w
    total = total + w
  end
  local h = t.h * pct
  local x = -(total * pct) / 2
  -- 第二趟：逐格写贴图/UV/几何（组内水平居中 ⇒ 每格锚在「本格中心」）
  for i = 1, n do
    local w = w1[i] * pct
    local q = faQuad(s, i)
    if not q then return false end
    local u0, u1
    if tcw and tcx and tW and tW > 0 then
      local cx0 = tonumber(tcx[ci1[i] + 1]) or 0
      u0, u1 = cx0 / tW, (cx0 + w1[i]) / tW
    else
      u0, u1 = ci1[i] / FA.nch, (ci1[i] + 1) / FA.nch      -- 兼容等宽旧表
    end
    pcall(q.SetTexture, q, file)
    -- ★★★SetTexCoord 的参数顺序是 **(left, right, top, bottom)** —— 与 WorldFog 画地图瓦片同一条口径。
    --   0.2.29 首版真机踩到：写成 (left, top, right, bottom) ⇒ 每格取到「错位的窄条」，
    --   屏上看起来就是乱码（截图：数字变成一格格竖条 + 拉长的方块）。★这条顺序不许再改。
    pcall(q.SetTexCoord, q, u0, u1, 0, 1)
    pcall(q.SetWidth, q, w) pcall(q.SetHeight, q, h)
    pcall(q.SetPoint, q, "CENTER", s.f, "CENTER", x + w / 2, 0)
    -- ★染色是**乘法**：字身是白→灰渐变（乘上颜色 = 该色的亮→暗）、描边/暗晕是近黑（乘完仍是暗色）
    --   ⇒ 每种描边风格都天然跟着数字颜色走，绝不会出现「红字配死黑边」那种割裂（0.2.30 五风格同此口径）
    pcall(q.SetVertexColor, q, r, g, b)
    pcall(q.Show, q)
    -- ★0.2.31 记下**基准几何**（宽 + 相对组中心的偏移）：缩放动画每拍只按这两样重算几何，
    --   贴图/UV 一个字节都不碰（UV 与缩放无关 ⇒ 没必要重发）
    s.faGeo = s.faGeo or {}
    s.faGeo[i] = { w = w, cx = x + w / 2 }
    x = x + w
  end
  for j = n + 1, FA_MAXQ do if s.fa and s.fa[j] then pcall(s.fa[j].Hide, s.fa[j]) end end
  s.faW, s.faH = total * pct, h            -- 整组尺寸（技能图标换锚到这一组的左缘时要用）
  s.faGN, s.faBH, s.faK = n, h, 1          -- 格数 / 基准格高 / 当前缩放（出生即 1，动画从这上面叠）
  return true
end
-- ----------------------------------------------------------------------------
-- ★0.2.31 缩放动画（图集行专用）—— 用户：「这种形式的伤害数字是否就支持动画曲线平滑缩放了?」
--   为什么文字行做不到、图集行能做：文字行的字号通道（SetFont/SetTextHeight/帧 SetScale/具名真对象 SetScale）
--   已被 0.2.0~0.2.21 逐条真机证死；图集行的数字是**纹理格**，宽/高/锚点本来就是我们每拍现算写的
--   ⇒ 连续缩放 + 曲线缓动成立。代价如实记：位图字体**放大**会插值发虚（**向下**缩不受影响）。
-- ----------------------------------------------------------------------------
-- 幅度（0~1 的倍率。配置是百分数）——★只表示**暴击鼓包**，出生弹入另有 animStart
local function animAmpNow()
  local v = tonumber(C().animAmp)
  if v == nil then v = DEF.animAmp end
  return math.max(0, math.min(D.ANIM_MAX, v)) / 100
end
-- 出生弹入的**起点倍率**（0.3~1.5；1 = 不弹入）
local function animStartNow()
  local v = tonumber(C().animStart)
  if v == nil then v = DEF.animStart end
  return math.max(D.ANS_MIN, math.min(D.ANS_MAX, v)) / 100
end
-- 尾声缩小的**幅度**（0~1；0 = 不缩）
local function animEndNow()
  local v = tonumber(C().animEnd)
  if v == nil then v = DEF.animEnd end
  return math.max(D.AEN_MIN, math.min(D.AEN_MAX, v)) / 100
end
-- ★E 用的**峰值系数**（唯一算式）：出生那段的最大值是 max(起点, 1)（起点 >100% 时峰值就是起点），
--   暴击那段再乘 (1+amp) ⇒ 取乘积上界（**保守**：只会多挑一档图，绝不放大 ⇒ 不发虚）
local function faPeakFactor(crit)
  local hs = animStartNow()
  if hs < 1 then hs = 1 end
  local amp = crit and animAmpNow() or 0
  return hs * (1 + amp)
end
-- ★E：按**峰值**挑档图 —— 峰值会超过原尺寸时，改用「够高的那一档图」再缩下来（素材密度 ≥ 峰值
--   ⇒ 动画全程都不放大、不发虚）；峰值 ≤ 1（只做出生弹入这种「先小后正」的动画）⇒ 原档不动（稳态最清晰）。
local function faPeakTier(baseTier, peak)
  local n = table.getn(D.TIER_H)
  if type(baseTier) ~= "number" or baseTier < 1 then baseTier = 1 end
  if baseTier > n then baseTier = n end
  if peak <= 1 or baseTier >= n then return baseTier end
  local want = (D.TIER_H[baseTier] or 0) * peak
  local t = baseTier
  while t < n and (D.TIER_H[t] or 0) < want do t = t + 1 end
  return t
end
-- 当前缩放系数（1 = 基准尺寸）：**出生弹入**（animStart → 1）+ **暴击鼓包**（1 → 1+amp → 1）+ **尾声缩小**（→ 1-end）
--   ★曲线吃**进度分数**（t/时长），不是秒（0.2.23 在滚动那边踩过一次，这里同一个口径）
--   ★每拍每槽都要调一次 ⇒ 配置只读一次（C() 会遍历一遍 DEF 补缺，热路径上别读两遍）
--   `fo` = **淡出进度**（0~1，由 tick 算好传进来；缺省 0）—— 尾声缩小与淡出**同相位**，
--   到点（t ≥ dur，槽被收掉）那一刻正好缩到位 ⇒ 观感就是「缩小切隐藏」。
local function animK(s, t, fo)
  local c = C()
  if t < 0 then t = 0 end
  fo = tonumber(fo) or 0
  local k = 1
  -- ① 出生弹入：起点 = 初始缩放%（<100 = 由小涨大 · 100 = 不弹入 · >100 = 由大缩回）
  local hs = animStartNow()
  if hs ~= 1 and t < D.FA_POP_SEC then
    k = hs + (1 - hs) * easeCurve(c.animCurve or DEF.animCurve, t / D.FA_POP_SEC)
  end
  -- ② 暴击鼓包（幅度 0 = 不鼓包；`s.crit` 已带 critAnim 开关的门）
  --   ★0.2.35 用**平滑包络**：前半起、后半落，两段都过 smoothstep ⇒ 起点/峰值/回正三处斜率都是 0，
  --     「放大回正」不再是一头撞回原尺寸（旧写法把缓出曲线**反着用**，末端斜率非 0 = 那一下顿）。
  local amp = animAmpNow()
  if s.crit == 1 and amp > 0 and t < D.FA_CRIT_SEC then
    local f = t / D.FA_CRIT_SEC
    local u = (f < 0.4) and smoothstep(f / 0.4) or smoothstep((1 - f) / 0.6)
    k = k * (1 + amp * u)
  end
  -- ③ 尾声缩小：与淡出同相位（fo = smoothstep 过的淡出进度），缩到 (1-end) 后随槽一起收掉
  local en = animEndNow()
  if en > 0 and fo > 0 then k = k * (1 - en * fo) end
  -- ★0.2.33 下限（初始缩放调到 30%、尾声缩到 100% 也不会更小；0 宽/高的纹理没意义）
  if k < D.FA_K_MIN then k = D.FA_K_MIN end
  return k
end
-- 把缩放系数落到几何上（**只发 SetWidth/SetHeight/SetPoint**；贴图与 UV 不动）
--   ★按「相对组中心的偏移 × k」摆 ⇒ 缩放天然以**组中心**为锚（不是每格各自缩放而散了队形）
local function faScaleApply(s, k)
  local n = s.faGN or 0
  if n <= 0 then return end
  for i = 1, n do
    local g = s.faGeo and s.faGeo[i]
    local q = s.fa and s.fa[i]
    if g and q then
      pcall(q.SetWidth, q, g.w * k)
      pcall(q.SetHeight, q, s.faBH * k)
      pcall(q.SetPoint, q, "CENTER", s.f, "CENTER", g.cx * k, 0)
    end
  end
  -- 技能图标跟着一起缩、并贴着整组左缘重锚（不缩 = 数字缩了图标不动，pop 那一下看着散）
  if s.icShown and s.icBase then
    local sz = s.icBase * k
    pcall(s.ic.SetWidth, s.ic, sz) pcall(s.ic.SetHeight, s.ic, sz)
    pcall(s.ic.SetPoint, s.ic, "RIGHT", s.f, "CENTER", -(s.faW or 0) * k / 2 - 2, D.ICON_DY or 0)
  end
  s.faK = k
end
-- 逐拍推进（唯一调用点 = tick；写前比对 ⇒ 稳态一个 Set* 都不发）
local function faScaleTick(s, t, fo)
  if not (s.faUsed and s.faTxt) then return end
  local want = animK(s, t, fo)
  if math.abs(want - (s.faK or 1)) > 0.0005 then faScaleApply(s, want) end
end

-- 只读自检：这个贴图路径到底能不能加载（返回「读到的文件宽」或 nil=判不出）
--   ★每次**新建**一张匿名探针纹理（复用会把上一次的文件尺寸读回来 ⇒ 假结果；WorldFog 同款配方）
local function faProbeTex(path)
  local host = rawget(_G, "UIParent")
  if not (type(host) == "table" or type(host) == "userdata") or type(host.CreateTexture) ~= "function" then return nil end
  local ok, tx = pcall(host.CreateTexture, host, nil, "ARTWORK")
  if not ok or tx == nil or type(tx.SetTexture) ~= "function" or type(tx.GetWidth) ~= "function" then return nil end
  pcall(tx.Hide, tx)
  if not pcall(tx.SetTexture, tx, path) then return nil end
  local okw, v = pcall(tx.GetWidth, tx)
  if okw and type(v) == "number" and v > 0 then return v end
  return nil
end
-- 当前风格在表里真的有**独立度量**吗（否 = 退回顶层那套 ⇒ 界面/体检要如实说，绝不假装换过）
--   ★`hard` 特殊：**顶层那套就是 hard**（生成器不重复写 `st.hard`，旧版单风格表也只有顶层那套）
--   ⇒ 它只要表读到了就算「有」，否则面板会对最该可用的那个风格报「表里没有」。
local function faEdgeOK()
  if not faEnsure() then return false end
  local t = FA.tiers[1]
  if t == nil then return false end
  local st = faStyleNow()
  if t.st and t.st[st] then return true end
  if st == "hard" then return true end
  return false
end
function D.faState()
  return {
    on = (C().fontAtlas == true), scale = tonumber(C().faScale) or 100,
    edge = faStyleNow(), edgeOK = faEdgeOK(),
    ok = faEnsure(), nch = FA.nch, N = FA.N,
    t1 = FA.tiers[1] and FA.tiers[1].file or nil,
  }
end
D.faEnsure, D.faTextOK, D.faClear, D.faLayout, D.faPct, D.faProbeTex, D.faMetrics =
  faEnsure, faTextOK, faClear, faLayout, faPct, faProbeTex, faMetrics
D.faStyleNow, D.faStyleNorm, D.faEdgeOK = faStyleNow, faStyleNorm, faEdgeOK
-- ★0.2.31 缩放动画的四个口（挂 D：离线 harness 直跑 + 真机 /run 也能查）
D.animK, D.faScaleApply, D.faScaleTick, D.faPeakTier, D.animAmpNow =
  animK, faScaleApply, faScaleTick, faPeakTier, animAmpNow
-- ★0.2.34 初始缩放（出生弹入）的口；★0.2.35 加尾声缩小
D.animStartNow, D.faPeakFactor = animStartNow, faPeakFactor
D.animEndNow = animEndNow

-- ----------------------------------------------------------------------------
-- 动画槽池（1.12 无销毁 API ⇒ 建一次只 Show/Hide；上限有界）
-- ----------------------------------------------------------------------------
local POOL_MAX = 40
D.pool = {}          -- i → { f, fs, active, ... }
D.poolN = 0
local ui                                  -- ★前向声明：tick 在它之前、面板段在它之后（否则 tick 里绑全局 nil）

local function slotAcquire()
  for i = 1, D.poolN do
    if not D.pool[i].active then return D.pool[i] end
  end
  if D.poolN >= POOL_MAX then return nil end
  if type(CreateFrame) ~= "function" then return nil end
  local f = CreateFrame("Frame", nil, UIParent)
  -- ★0.2.29 高度给足：图集模式的数字格是**本帧的子纹理**（最大档 84px），
  --   帧太小有被裁掉的风险（本客户端是 UE 封装，裁剪行为未知）⇒ 直接建大一点，零代价。
  -- ★0.2.33 再放大：缩放幅度上限提到 100% ⇒ 暴击峰值可达 **2 倍**（最大档 84px 的数字组按 6 位算约 420px
  --   ⇒ 峰值 ~840px）⇒ 帧宽给到 1024 覆盖这个量级。
  -- ★0.2.41 三度放大：幅度上限再到 **200%**，且峰值算式是 `max(animStart,1) × (1 + 幅度)`
  --   ⇒ 最坏组合（初始缩放 150% + 幅度 200%）= **3 倍**（6 位数字按最大档 ≈ 590px ⇒ 峰值 ~1770px、
  --   高 84×3 = 252px）⇒ 帧给到 **2048×512**。★如实边界：**8 位数字 + 最大档 + 3 倍**仍可能略微超出，
  --   而且本客户端到底裁不裁子纹理**没验过**（真机若看到大数字边缘被切，就是它在裁 —— 反馈我继续放大）。
  f:SetWidth(2048) f:SetHeight(512)
  -- ★带继承模板建 FontString（宿主 uiText 已验证配方），SetFontObject 再双保险
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  pcall(fs.SetFontObject, fs, GameFontNormal)
  pcall(fs.SetPoint, fs, "CENTER", f, "CENTER", 0, 0)
  pcall(fs.SetJustifyH, fs, "CENTER")
  local ic = f:CreateTexture(nil, "ARTWORK")          -- 技能图标（锚在文字左缘，不占槽位几何）
  pcall(ic.Hide, ic)
  D.poolN = D.poolN + 1
  D.pool[D.poolN] = { f = f, fs = fs, ic = ic, active = false }
  return D.pool[D.poolN]
end

local function slotRelease(s)
  s.active = false
  pcall(s.f.Hide, s.f)
end

local function slotReleaseAll()
  for i = 1, D.poolN do slotRelease(D.pool[i]) end
end

-- ★0.2.29 图集开关的**唯一写口**（面板勾选 / `/edmg 图集 开|关` 都走它）：
--   写配置 + **清空当前所有字**（否则会半新半旧地留着上一种画法的字）+ 刷新面板真值
function D.fontAtlasSet(on)
  local c = C()
  c.fontAtlas = on and true or false
  slotReleaseAll()
  for i = 1, D.poolN do local s = D.pool[i] if s.fa then faClear(s) end end
  if type(D.uiRefresh) == "function" then D.uiRefresh() end
  say("自带字体图集：" .. (c.fontAtlas and "开（战斗数字改用插件自带字体）" or "关（回到客户端字体）"))
end

-- ★0.2.30 描边风格的**唯一写口**（面板「描边样式」± / `/edmg 描边 <风格>` 都走它）：
--   只换**贴图**（几何/UV 由 faLayout 按该风格自己的度量重算）⇒ **不 clean 场**：屏上已经在飘的数字
--   当场按新风格重排（不然要等下一次出生才换，用户会以为「点了没反应」）。
--   ★不认识的风格 id ⇒ 一个字节都不写 + 返回 false（绝不把垃圾值写进存档）。
function D.faStyleSet(v)
  local id = faStyleNorm(v)
  if not id then return false end
  local c = C()
  c.faEdge = id
  for i = 1, D.poolN do
    local s = D.pool[i]
    if s.active and s.faUsed and s.faTxt then
      local col = s._faCol or { 1, 1, 1 }
      faLayout(s, s.faTxt, s._tier or s.tier, faPct(), col[1], col[2], col[3])
    end
  end
  if type(D.uiRefresh) == "function" then D.uiRefresh() end
  say("战斗数字描边：" .. (D.FAS_ZH[id] or id) .. "（" .. id .. "）" ..
    (faEdgeOK() and "" or " ｜ ★FontDigits.lua 里没有这种风格的度量 ⇒ 退回硬描边"))
  return true
end
-- 风格循环（面板「描边样式」± 用；方向 d=+1 正向、-1 反向）
--   ★0.2.38 起**只在当前「字体图集」组内循环**（分组见 D.FAS_SETS）：换字形用单独那一行（D.faGlyphStep），
--     否则 9 个 id 混在一条循环里，用户根本分不清「换字体」与「换描边」。
function D.faStyleStep(d)
  local st = faSetNow().styles
  local cur = faStyleNow()
  local i = 1
  for k = 1, table.getn(st) do if st[k] == cur then i = k break end end
  local n = table.getn(st)
  D.faStyleSet(st[((i - 1 + (d or 1)) % n) + 1])
end
-- ★0.2.38 「字体图集」行的 ±（面板新增那一行；/edmg 字体 共用写口 D.faStyleSet）
function D.faGlyphStep(d)
  local cur = faSetNow()
  local n = table.getn(D.FAS_SETS)
  local i = 1
  for k = 1, n do if D.FAS_SETS[k] == cur then i = k break end end
  D.faStyleSet(faSetPick(D.FAS_SETS[((i - 1 + (d or 1)) % n) + 1]))
end
-- `/edmg 字体 <内置|9c|武侠|组id>`：点名换一组（认组 id 也认中文名；不认 ⇒ false，一个字节都不写）
function D.faGlyphSet(v)
  if type(v) ~= "string" or v == "" then return false end
  local low = string.lower(v)
  for k = 1, table.getn(D.FAS_SETS) do
    local s = D.FAS_SETS[k]
    if s.id == low or s.zh == v then return D.faStyleSet(faSetPick(s)) end
  end
  return false
end
-- 读值口：字体图集（组 id / 中文名 / 组内可选样式串）
function D.faGlyphNow()
  local s = faSetNow()
  return s.id, s.zh, table.concat(s.styles, ",")
end

-- 唯一入口：往屏幕上放一条字
--   kind = KIND 键；text = 文案；crit = 1/0（暴击抬档动画）；spellName = 技能名（配图用，可省）
local function addText(kind, text, crit, spellName)
  if C().master ~= true then return false end
  local kd = KIND[kind]
  if not kd then return false end
  local gate = KIND_ITEM[kind]
  if gate and not itemOn(gate) then return false end

  local s = slotAcquire()
  if not s then return false end

  local c = C()
  local lane = kd.lane
  local x = c.posX or 0
  -- ★0.2.28：受击行的起点 = 主锚点 + 受击下移（同一个字段被面板步进 / 编辑模式红锚点 / 重置位置共用）
  local y = (lane == "in") and ((c.posY or 0) + (tonumber(c.inOffY) or DEF.inOffY)) or (c.posY or 0)

  -- ★防重叠（0.1.2 重写；真机报障「技能伤害定位越来越高」的根因）：
  --   新字**永远从锚点出发** —— 先到的字已经漂走了，天然不叠；
  --   只有「同一瞬间连发」（AOE 爆发：最近那条还贴着锚点没漂开一个行距）才往上/下摞一格。
  --   旧写法 = 黏性游标只有车道全空才复位 ⇒ 连续战斗时车道永远不空 ⇒ 每条都 +行距 ⇒ 无限爬高。
  local dir = (lane == "in") and "down" or (c.direction or "up")
  local spacing = D.TIER_H[c.fontTier or 3] or 24
  local edge = nil                                   -- 同车道里**离锚点最近**那条的当前 y
  for i = 1, D.poolN do
    local s = D.pool[i]
    if s.active and s.kind and KIND[s.kind] and KIND[s.kind].lane == lane then
      local cy = s.cy or s.y0
      if dir == "down" then
        if (not edge) or cy > edge then edge = cy end   -- down 车道：最靠上 = 离锚点最近
      else
        if (not edge) or cy < edge then edge = cy end   -- up/arc 车道：最靠下 = 离锚点最近
      end
    end
  end
  if edge and math.abs(edge - y) < spacing then
    if dir == "down" then y = edge - spacing else y = edge + spacing end
  end

  s.active = true
  s.kind = kind
  s.crit = (crit == 1 and C().critAnim == 1) and 1 or 0
  -- ★0.2.26b：暴击**文字身份**与「暴击动画」开关**解耦**（用户：「致命一击 没有标红」——
  --   首版把红色挂在 s.crit 上，而它被 critAnim 挡着 ⇒ 关掉暴击动画的人看不到红）：
  --   红不红只由事件文本的「致命」标记决定；字号抬档仍走 s.crit（开关管动画，不管颜色）。
  s.critTxt = (crit == 1) and 1 or 0
  s.t0 = GetTime and GetTime() or 0
  s.dur = c.duration or 2.0
  s.tier = c.fontTier or 3
  s.x0, s.y0 = x, y
  s.cy = y                  -- 出生即当前 y（槽是复用的：不清掉的话会吃到上一条命的残值）
  s.side = (math.random(0, 1) == 1) and 1 or -1
  s.dir = dir

  if C().showSpellText == true and spellName then
    text = tostring(spellName) .. " " .. tostring(text)        -- 技能名纯文本（默认关）
  end
  -- ★0.2.26：暴击伤害值变红（用户：「暴击的时候将伤害值变红色」）—— 判定走 critTxt（与动画开关解耦）；
  --   槽是复用的但颜色每次出生都重写 ⇒ 不会串色。
  local faR, faG, faB = kd.r, kd.g, kd.b
  if s.critTxt == 1 then faR, faG, faB = 1, 0.15, 0.1 end
  local faTxt = tostring(text)
  -- ★0.2.29 图集优先（R4）：**整条都能用图集画**才走图集（含中文/字母/空格一律回落客户端字体 ⇒ 老行为不变）
  s.faTxt, s.faUsed = nil, false
  if C().fontAtlas == true and faEnsure() and faTextOK(faTxt) then
    -- ★0.2.31 E：峰值会超过基准尺寸时才挑更高的档图（见 faPeakTier）；基准视觉尺寸一个字都不变
    --   ★0.2.34 峰值口径收进 faPeakFactor（初始缩放 >100% 也会算进峰值；暴击再乘鼓包幅度）
    local layTier, layPct = s.tier, faPct()
    local useTier = faPeakTier(s.tier, faPeakFactor(s.crit == 1))
    if useTier ~= s.tier then
      layTier = useTier
      layPct = layPct * (D.TIER_H[s.tier] or 24) / (D.TIER_H[useTier] or 24)
    end
    if faLayout(s, faTxt, layTier, layPct, faR, faG, faB) then
      s.faTxt, s.faUsed = faTxt, true
    end
  end
  if s.faUsed then
    pcall(s.fs.SetText, s.fs, "")        -- 文字让位给数字格（两套绝不叠着画）
    s._faCol = { faR, faG, faB }         -- 换描边风格时要在原地重排，颜色沿用出生时那份
  else
    faClear(s)                           -- 槽复用：换回文字行时把上次的数字格收起
    pcall(s.fs.SetText, s.fs, faTxt)
  end
  pcall(s.fs.SetTextColor, s.fs, faR, faG, faB)
  s._ascii = isAsciiOnly(faTxt)               -- ★含中文的整条必须走中文字体（否则名字渲染成空白）
  sizeApply(s.fs, s.tier, kind, s._ascii)                      -- ★分档字体对象（探针定案，见上）
  s._tier = s.tier
  -- 技能图标（0.2.4）：锚在文字左缘；查不到/没传/关着就不画（绝不画 ? 图）
  local icon = (C().showIcon ~= false) and iconOf(spellName) or nil
  if icon then
    -- 图标边长随字号档位动态现算（行距 × ICON_RATIO；本客户端量不出真实字高，这是最近似的动态口径）
    local sz = math.max(6, math.floor((D.TIER_H[s.tier] or 24) * (D.ICON_RATIO or 0.45) + 0.5))
    pcall(s.ic.SetTexture, s.ic, icon)
    pcall(s.ic.SetWidth, s.ic, sz) pcall(s.ic.SetHeight, s.ic, sz)
    -- ★图集行没有 FontString 文字 ⇒ 锚到**数字组的左缘**（否则图标会飘到空格子的左缘上压住数字）
    if s.faUsed then
      pcall(s.ic.SetPoint, s.ic, "RIGHT", s.f, "CENTER", -(s.faW or 0) / 2 - 2, D.ICON_DY or 0)
    else
      pcall(s.ic.SetPoint, s.ic, "RIGHT", s.fs, "LEFT", -2, D.ICON_DY or 0)
    end
    pcall(s.ic.Show, s.ic)
    s.icShown, s.icBase = true, sz      -- ★0.2.31 缩放动画要用基准尺寸（图标跟数字一起缩、一起重锚）
  else
    pcall(s.ic.Hide, s.ic)
    s.icShown, s.icBase = false, nil
  end
  pcall(s.f.SetAlpha, s.f, 0)
  pcall(s.f.SetPoint, s.f, "CENTER", UIParent, "CENTER", s.x0, s.y0)
  pcall(s.f.Show, s.f)
  return true
end
D.addText = addText

-- ----------------------------------------------------------------------------
-- 动画推进（节拍帧唯一 handler；OnUpdate 零形参 ⇒ dt 走全局 arg1 / GetTime 差值）
-- ----------------------------------------------------------------------------
local function tick()
  if C().master ~= true then return end          -- 双闸之一：节拍函数第一行
  local now = GetTime and GetTime() or 0

  local c = C()
  for i = 1, D.poolN do
    local s = D.pool[i]
    if s.active then
      local t = now - s.t0
      if t >= s.dur then
        slotRelease(s)
      else
        -- 透明度：前 10% smoothstep 淡入，后 50% smoothstep 淡出
        --   ★0.2.35 顺手把**淡出进度 `fo`** 留下来喂给缩放动画（尾声缩小与淡出同相位 ⇒ 
        --   「缩小切隐藏」= 缩到位那一刻正好也是 t≥dur 收槽那一刻，绝不出现「先缩没、又空飘一会儿」）
        local a, fo
        if t < s.dur * 0.1 then a = smoothstep(t / (s.dur * 0.1)) fo = 0
        elseif t > s.dur * 0.5 then
          fo = smoothstep((t - s.dur * 0.5) / (s.dur * 0.5))
          a = 1 - fo
        else a = 1 fo = 0 end
        -- 位移（绝对时间驱动：t = now - t0，与帧率无关）
        local x, y = s.x0, s.y0
        if s.dir == "down" then
          y = s.y0 - (c.speed or 90) * t
        elseif s.dir == "arc" then
          -- 彩虹弧线（0.2.1 加高：用户「抛物线能否抛高一点再下落」）：
          --   峰值 = vy0²/(4g) ≈ 72px · 0.6s 到顶 · 之后加速下落到锚点以下
          local vy0, g = 240, 200
          y = s.y0 + vy0 * t - g * t * t
          x = s.x0 + 60 * t * s.side
        elseif s.dir == "angleUp" then
          -- 斜上抛物（0.2.2；DamageEx 斜上族）：斜向冲出后缓落
          x = s.x0 + (c.speed or 90) * 0.8 * t * s.side
          y = s.y0 + (c.speed or 90) * 1.4 * t - 120 * t * t
        elseif s.dir == "angleDown" then
          -- 斜下抛物（0.2.2）
          x = s.x0 + (c.speed or 90) * 0.8 * t * s.side
          y = s.y0 - (c.speed or 90) * 1.2 * t - 60 * t * t
        elseif s.dir == "horiz" then
          -- 水平散开（0.2.2；DamageEx 水平族）：左右交替横移 + 微浮沉
          x = s.x0 + (c.speed or 90) * 1.2 * t * s.side
          y = s.y0 + math.sin(t * 3) * 6
        elseif s.dir == "sprinkler" then
          -- 洒水散开（0.2.2；DamageEx 洒水器族）：前 0.3s 快速斜喷，之后缓升微摆
          if t < 0.3 then
            x = s.x0 + 300 * t * s.side
            y = s.y0 + 220 * t
          else
            x = s.x0 + 90 * s.side + math.sin(t * 8) * 10 * s.side
            y = s.y0 + 66 + 30 * (t - 0.3)
          end
        elseif s.dir == "sine" then
          -- 正弦上升（0.2.2；DamageEx OTHER 族的 sin 手法）：直上 + 左右正弦摆
          x = s.x0 + math.sin(t * 6) * 40
          y = s.y0 + (c.speed or 90) * t
        elseif s.dir == "burst" or s.dir == "burstL" or s.dir == "burstR" then
          -- 极速蹦出（0.2.3；用户：「模仿官方的伤害展现方式：中间极速蹦出来、方向朝上」）：
          --   官方 FCT = **缓出曲线**（快起慢收）；`back` 曲线过冲到终点以上再回落 = 「蹦」
          --   ★曲线吃「进度分数」t/dur（0..1），不是秒
          local f = t / s.dur
          local e = easeCurve(c.curve, f)
          local dist = (c.speed or 90) * s.dur * 0.45          -- 总行程（速度×时长定，比例恒定）
          y = s.y0 + dist * e
          if s.dir == "burstL" then x = s.x0 - 70 * f * f
          elseif s.dir == "burstR" then x = s.x0 + 70 * f * f end
        else
          y = s.y0 + (c.speed or 90) * t
        end
        -- ★★★0.2.25 行程上限 + 屏界保险丝（用户：「有没一个参数这是动画移动的上限或者下限占屏幕
        --   百分百?有时候技能都飘到屏幕外面去了」+「A+B」）：
        --   A = 行程夹取：|x−x0| ≤ 屏宽×上限%、|y−y0| ≤ 屏高×上限%（到顶的字**原地停住继续淡出**，
        --       对方向/曲线/速度/时长全兼容 —— 夹取是轨迹算完之后的最后一步）；
        --   B = 屏界夹取：最终坐标恒在屏内（CENTER 锚口径：±宽/2、±高/2）—— 锚点贴边也出不了屏。
        do
          local cPct = tonumber(c.clampPct) or 30
          if cPct < 5 then cPct = 5 elseif cPct > 60 then cPct = 60 end
          local sw, sh = 1024, 768
          if type(UIParent) == "table" then
            local okw, w1 = pcall(UIParent.GetWidth, UIParent)
            if okw and type(w1) == "number" and w1 > 0 then sw = w1 end
            local okh, h1 = pcall(UIParent.GetHeight, UIParent)
            if okh and type(h1) == "number" and h1 > 0 then sh = h1 end
          end
          local mx, my = sw * cPct / 100, sh * cPct / 100
          if x - s.x0 > mx then x = s.x0 + mx elseif s.x0 - x > mx then x = s.x0 - mx end
          if y - s.y0 > my then y = s.y0 + my elseif s.y0 - y > my then y = s.y0 - my end
          local hx, hy = sw / 2, sh / 2
          if x > hx then x = hx elseif x < -hx then x = -hx end
          if y > hy then y = hy elseif y < -hy then y = -hy end
        end
        -- 暴击：0.35s 窗口内抬一档（特大封顶），窗口外落回配置档 —— 档位制下的「缩放」语义
        --   ★0.2.31：**只对文字行**保留抬档；图集行改成**平滑缩放鼓包**（见 faScaleTick）——
        --   纹理本来就能连续缩放，硬跳档反而每 0.35s 多做一次整组重排（换图 + 逐格重写）。
        if s.crit == 1 and not (s.faUsed and s.faTxt) then
          local wantTier = (t < 0.35) and math.min(table.getn(D.TIER), (s.tier or 3) + 1) or (s.tier or 3)
          if wantTier ~= s._tier then
            s._tier = wantTier
            sizeApply(s.fs, wantTier, s.kind, s._ascii)
          end
        end
        -- ★0.2.31 图集行缩放动画（出生弹入 + 暴击鼓包 + **0.2.35 尾声缩小**）：只补发几何，写前比对 ⇒ 稳态一个 Set* 都不发
        faScaleTick(s, t, fo)
        pcall(s.f.SetPoint, s.f, "CENTER", UIParent, "CENTER", x, y)
        pcall(s.f.SetAlpha, s.f, clamp01(a))
        s.cy = y                                        -- 当前 y（防重叠取「离锚点最近一条」要用）
      end
    end
  end

  -- 编辑模式：拖拽推进 + 模拟战斗
  if D.editOn then
    D.editTick(now)
  end
  -- 配置面板拖拽（同一节拍驱动，不再立第二个节拍帧）
  if ui.drag then
    D.uiDragTick()
  end
end
D.tick = tick

-- ----------------------------------------------------------------------------
-- 节拍帧：唯一挂/摘入口（宿主 WorldFrame；一个模块只许一个节拍帧）
-- ----------------------------------------------------------------------------
D.frame = nil
local function beatSync()
  if type(CreateFrame) ~= "function" then return end
  local want = C().master == true
  if not D.frame then
    local parent = rawget(_G, "WorldFrame") or UIParent
    D.frame = CreateFrame("Frame", "EH_DMG_BEAT", parent)
  end
  if want then
    pcall(D.frame.SetScript, D.frame, "OnUpdate", tick)     -- 重挂同一 handler（幂等）
  else
    pcall(D.frame.SetScript, D.frame, "OnUpdate", nil)      -- 真摘，不靠每帧早退
  end
end
D.beatSync = beatSync

-- ----------------------------------------------------------------------------
-- 事件解析（SCT 模式；zhCN 模式表尽力而为，未识别的进捕获环）
--   ★事件名/文本格式不许猜 ⇒ /edmg 捕获 打开后原文落环，/edmg 事件 查看。
-- ----------------------------------------------------------------------------
local RING_MAX = 80                     -- 0.2.8 加大（深度捕获要装一场战斗的负载）
local function ringPush(line)
  local c = C()
  local r = c.ring
  table.insert(r, tostring(line))
  while table.getn(r) > RING_MAX do table.remove(r, 1) end
end

-- ★★★句形去重落环（真机取证口）：把这句战斗文本的「句形」（数字统一换成 `#`）记一次 ——
--   一串同形的伤害只留一行、会话内有界（SHAPE_MAX）⇒ 打完一场就有一份「本客户端到底有哪几种
--   战斗句式」的清单，供模式表逐条校准（真机踩过：不看清真实句式就改匹配规则 = 整车失效）。
--   ★调用点在运行时（事件/命令），赋值在载入期 ⇒ 用 D. 字段而不是 local（不许先引用后声明）。
D.shapeSeen = {}
local SHAPE_MAX = 40
local function shapeCount()
  local n = 0
  for _ in pairs(D.shapeSeen) do n = n + 1 end
  return n
end
D.shapeCount = shapeCount
function D.noteShape(tag, m)
  if type(m) ~= "string" or m == "" then return end
  local shape = string.gsub(m, "%d+", "#")
  local key = tostring(tag) .. "|" .. shape
  if D.shapeSeen[key] then return end
  if shapeCount() >= SHAPE_MAX then return end        -- 有界：满了就不再记（绝不无界增长）
  D.shapeSeen[key] = true
  ringPush("SHAPE " .. key)
end

local function capture(ev, msg)
  if C().capture then ringPush(tostring(ev) .. " | " .. tostring(msg)) end
end

-- 通用提取：伤害数字 + 致命标记 + 目标名（尽力而为的多模式）
local function numOf(msg) local n = string.match(msg, "(%d+)") return tonumber(n) end
local function isCrit(msg) return string.find(msg, "致命") ~= nil end

-- 事件表：ev → 处理器（全部用全局 arg1 原文）
local EVH = {}

-- 光环/展示类去重（0.2.14）：归一键 + 时间窗内同名只出一条（窗口可配）
D.recent = {}
local function dupOk(key, win)
  local now = GetTime and GetTime() or 0
  if D.recent[key] and (now - D.recent[key]) < (win or 1.0) then return false end
  D.recent[key] = now
  return true
end

EVH["CHAT_MSG_COMBAT_SELF_HITS"] = function(m)
  -- ★0.2.27「提不出数字不硬显示」（与 incoming/DOT 早已定下的尺子统一）：非伤害文本
  --   （真机例：「你施放毒蛇钉刺失败：尚未恢复」「Cat的撕咬没有击中雌性草原狮。」）落到这个事件上时
  --   旧写法 `numOf(m) or m` 会把**整句原文当伤害值画在屏幕上** ⇒ 现在一律不画、只记句形供校准。
  local n = numOf(m)
  if not n then D.noteShape("hit-nonum", m) return end
  addText("damage", n, isCrit(m) and 1 or 0, spellFromMsg(m))
end
EVH["CHAT_MSG_SPELL_SELF_DAMAGE"] = function(m)
  local n = numOf(m)
  if not n then D.noteShape("spell-nonum", m) return end
  -- 技能名（配图用）：真机句式「你的 撕裂 使 噬骨者 受到了 9 点物理伤害。」「你的自动射击击中X造成25点伤害。」
  local sp = string.match(m, "^你的%s*(.-)%s*使") or spellFromMsg(m)
  addText("damage", n, isCrit(m) and 1 or 0, sp)
  -- 减免后缀（……点被抵抗/吸收/格挡）：减免显示开着时补一条
  local abs = string.match(m, "（(%d+)点被(.+)）") or string.match(m, "(%d+)点被抵抗")
  if abs and itemOn("mitigation") then addText("mitigation", "-" .. abs .. " 减免", 0) end
end
EVH["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"] = function(m)
  -- ★★★0.2.24 归属门（真机报障：「某些其他骑士的奉献神圣伤害会在牧师的伤害界面上显示?」）：
  --   这族事件的「目标类别」是敌对玩家/生物，**来源不限**（vanilla 语义：附近任何人的 DoT 跳在
  --   怪身上都会进战斗日志）⇒ 别人的奉献（范围周期神圣伤害）会显示成我们的 dot ⇒ 只认自己的：
  --   真机已校准句式一律「你的 …」开头（「你的 撕裂 使 X 受到了 9 点伤害。」）；不是就跳过+落环。
  if string.sub(m, 1, 3) ~= "你" then capture("DOT-OTHER", m) return end
  local n = numOf(m)
  if not n then capture("DOT-NONUM", m) return end   -- 0.2.4：提不出数字不硬显示（同 incoming 的尺子）
  local sp = string.match(m, "^你的%s*(.-)%s*使") or string.match(m, "^你的%s*(.-)%s*击中")
          or string.match(m, "^你的%s*(.-)%s*对")
  addText("dot", n, 0, sp)
end
EVH["CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE"] = EVH["CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE"]

EVH["CHAT_MSG_COMBAT_SELF_MISSES"] = function(m)
  local w = string.find(m, "躲闪") and "躲闪" or string.find(m, "招架") and "招架"
         or string.find(m, "未击中") and "未击中" or string.find(m, "抵抗") and "抵抗" or "未命中"
  addText("miss", w, 0)
end
EVH["CHAT_MSG_SPELL_SELF_MISSES"] = EVH["CHAT_MSG_COMBAT_SELF_MISSES"]

-- ★★0.2.27 宠物伤害（用户真机反馈：「宠物伤害显示匹配应该还有问题」）：
--   **提不出数字不硬显示**（旧写法 `numOf(m) or m` 会把整句原文当伤害值画在屏幕上 ——
--   与 incoming/DOT 早已定下的尺子不一致，宠物句式恰好是「未校准」那一套 ⇒ 必然踩中）；
--   句形落环走 `SHAPE pet-nonum|…`，一场仗下来就能看到宠物伤害的真实句式。
local function petHit(m)
  local n = numOf(m)
  if not n then D.noteShape("pet-nonum", m) return end
  addText("pet", n, isCrit(m) and 1 or 0, spellFromMsg(m))
end
EVH["CHAT_MSG_COMBAT_PET_HITS"] = petHit
EVH["CHAT_MSG_SPELL_PET_DAMAGE"] = petHit
EVH["CHAT_MSG_COMBAT_PET_MISSES"] = function(m) EVH["CHAT_MSG_COMBAT_SELF_MISSES"](m) end

-- ----------------------------------------------------------------------------
-- ★0.2.45 能量获取（怒气/法力/能量…）—— **解析与显示只写一份、两个事件都调**
--   真机句式与**事件归属**（来源 = 用户 2026-10-10 截图 + 他自己存档的捕获环 · 账号 LIHAIBOAS2）：
--     RAW CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS |1=你从血性狂暴获得了1点RAGE_POINTS。   ← 血性狂暴
--     RAW CHAT_MSG_SPELL_SELF_BUFF          |1=你从怒不可遏获得了1点RAGE_POINTS。   ← 怒不可遏
--     RAW CHAT_MSG_SPELL_SELF_BUFF          |1=你从冲锋获得了9点RAGE_POINTS。       ← 冲锋
--   ★同一件事走**两个不同事件** ⇒ 谁都不能假设「只有周期性那一支」。
--   ★★真 bug（用户报障原话「目前这个匹配到是一个绿色的战斗数值」）：`CHAT_MSG_SPELL_SELF_BUFF`
--     的处理器是**治疗**，而它的兜底模式 `(%d+)%s*点` 会把「…获得了1点RAGE_POINTS。」吃成
--     绿色的「+1」（治疗色 0.30,1.00,0.40）⇒ 修法 = 能量句在**治疗之前**先被认出来，
--     且**整个治疗族（3 个事件）都不许再把能量句当治疗**（反向钉）。
-- ----------------------------------------------------------------------------
-- 能量 token → 中文（真机是**未翻译 token**：RAGE_POINTS；中文 token 一并认，便于其它客户端/其它句式）
local POWER_ZH = { RAGE_POINTS = "怒气", RAGE = "怒气", MANA_POINTS = "法力", MANA = "法力",
                   ENERGY_POINTS = "能量", ENERGY = "能量", FOCUS_POINTS = "集中值", FOCUS = "集中值",
                   HAPPINESS_POINTS = "快乐", HAPPINESS = "快乐",
                    ["怒气"] = "怒气", ["法力"] = "法力", ["能量"] = "能量",
                    ["集中值"] = "集中值", ["快乐"] = "快乐" }

-- 唯一解析口：整句 → 数字 + 能量中文名 + 来源名；**不是能量句一律 nil**（交给别的处理器）
--   ★★★token 必须落在上面那张白名单里才算能量句 —— 绝不能只看「获得了 N 点 X」的形状：
--     同形状的「你获得了40点生命值。」是**治疗**，只差一个词 ⇒ 认不出来就如实放行（拿不到证据不硬认）。
local function energizeParse(m)
  if type(m) ~= "string" then return nil end
  -- ★Lua 模式的 `?` 按字节作用 ⇒ 「了?」会切掉半个汉字（项目老坑）⇒ 两条模式分别试
  local n, pw = string.match(m, "^你从.-获得%s*(%d+)%s*点(.-)。")
  if not n then n, pw = string.match(m, "^你从.-获得了%s*(%d+)%s*点(.-)。") end
  if not n then n, pw = string.match(m, "^你获得(%d+)点(.+)") end
  if not n then n, pw = string.match(m, "^你获得了(%d+)点(.+)") end
  if not n then return nil end
  pw = string.gsub(tostring(pw or ""), "^%s*(.-)%s*$", "%1")   -- 真机文本空格多 ⇒ 剥净再映射
  local zh = POWER_ZH[pw] or POWER_ZH[string.upper(pw)]
  if not zh then return nil end
  return tonumber(n), zh, string.match(m, "^你从%s*(.-)%s*获得")   -- 来源名（天赋/光环名，配图用）
end

-- 唯一显示口：能量句 ⇒ 屏上「怒气+1」（0.2.45 起**名字在前**；旧写法是「+1 怒气」）
--   ★返回 true/false = **这句是不是能量句**（与「显示项开着没有」无关）——
--     治疗族拿它当闸门用（true ⇒ 本条已被能量通道接手，绝不许再当治疗画）。
local function energizeShow(m)
  local n, zh, src = energizeParse(m)
  if not n then return false end
  addText("energize", zh .. "+" .. n, 0, src)
  return true
end

-- 治疗（友方治疗者姓名）：这族事件同时会报「施加 buff」类**无数字**文本（如「X 对你施放了 恢复。」）
--   —— 真机实锤：无数字硬显示 ⇒ 屏上一个「+?」⇒ 没有数字一律不当治疗跳（buff 施加由效果显示管）
--   ★本客户端真机句式（0.2.3 战斗日志截图）：「你因 losol 的 恢复 而获得了 40 点生命值。」
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]  = function(m)
  -- ★0.2.45 反向钉：能量句**绝不许**被治疗处理器吃成绿色数字（本族 3 个事件共用这一份处理器）
  if energizeShow(m) then return end
  local n = string.match(m, "获得%s*(%d+)%s*点") or string.match(m, "治疗你%s*(%d+)%s*点")
         or string.match(m, "恢复%s*(%d+)%s*点") or string.match(m, "(%d+)%s*点")
  if not n then capture("HEAL-NONUM", m) return end
  -- ★真机文本「的」前后带空格 ⇒ 提取名字必须把空白一起剥掉；技能名配图（你因 X 的 **恢复** 而…）
  local who = string.match(m, "^你因%s*(.-)%s*的") or string.match(m, "^%s*(.-)%s*的")
  local sp = string.match(m, "^你因%s*.-的%s*(.-)%s*而") or string.match(m, "^.-的%s*(.-)%s*治疗你")
          or string.match(m, "^.-的%s*(.-)%s*使")
  -- ★0.2.29 空名字不给空括号（真机截图里出现过「+298 []」：`^你因的…` 这类句式会捕获到**空串**，
  --   而空串在 Lua 里是真值 ⇒ 旧写法就画出一对空方括号）
  if who == "" then who = nil end
  addText("heal", "+" .. n .. (who and (" [" .. who .. "]") or ""), 0, sp)
end
EVH["CHAT_MSG_SPELL_PARTY_BUFF"]         = EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]
EVH["CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF"] = EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"]

-- 自我治疗（0.2.5；真机句式「你的 次级治疗术 治疗了你 154 点生命值。」
--   「你的 次级治疗术 对你造成极效治疗，恢复了 247 点生命值。」）
EVH["CHAT_MSG_SPELL_SELF_BUFF"] = function(m)
  -- ★★0.2.45 真机报障的**真凶**：「你从怒不可遏获得了1点RAGE_POINTS。」走的是**这个**事件
  --   （不是周期性那一支）⇒ 旧写法落到下面的治疗兜底 `(%d+)%s*点` ⇒ 屏上一个**绿色**「+1」。
  --   能量句先认（认出来就交给能量通道），其余照旧走自我治疗。
  if energizeShow(m) then return end
  local sp = string.match(m, "^你的%s*(.-)%s*治疗") or string.match(m, "^你的%s*(.-)%s*对你造成")
  local n = string.match(m, "治疗了你%s*(%d+)%s*点") or string.match(m, "恢复了%s*(%d+)%s*点")
         or string.match(m, "(%d+)%s*点")
  if not n then capture("SELFHEAL-NONUM", m) return end
  addText("heal", "+" .. n, 0, sp)
end

EVH["CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS"] = function(m)
  -- ★0.2.45：能量句的解析搬到**唯一口** `energizeParse`/`energizeShow`（见上文那段）——
  --   真机「你从血性狂暴获得了1点RAGE_POINTS。」走**这个**事件（怒不可遏/冲锋走 SPELL_SELF_BUFF）。
  if energizeShow(m) then return end
  -- ★★0.2.46：别人给我的治疗 tick **也落在这个事件上**（用户 2026-10-10 真机捕获环：
  --   `RAW CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS |1=你因Iosol的恢复而获得了40点生命值。` ⇒ 被记成
  --   `PERIODIC_SELF_BUFFS?` = **一条都不显示**）—— 这条句子与「友方治疗者」那条事件上的**形状完全一样**
  --   ⇒ **绝不另写一份治疗解析**，直接交给**同一个处理器**（它自带「提不出数字不硬显示」）。
  --   ★只放行「你因…点生命值」与「你获得…点生命值」两种**治疗句**形状：本事件还有
  --     「你获得了恢复的效果。」这类**效果句**，无脑转发会把它们全变成 `HEAL-NONUM` 而**丢掉效果显示**。
  if string.find(m, "点生命值", 1, true) and (string.find(m, "^你因") or string.find(m, "^你获得")) then
    EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF"](m)
    return
  end
  -- ★模式次序（0.2.14 修）：先整句（「…获得了 X 。」两种主语），再「效果」形 ——
  --   `(.-)效果` 按首个「效果」截会得到「恢复的」（与整句形「恢复的效果」归一不到一起 = 去重失效）
  local a = string.match(m, "^你获得了(.+)。") or string.match(m, "^你从.-获得了(.+)。")
         or string.match(m, "^你获得(.+)效果") or string.match(m, "^你从.-获得了(.+)效果")
  -- ★0.2.14 去重（真机截图：同一次「恢复」出了两条）—— 本客户端对同一次 buff 施加会发
  --   两种句式（「你从 X 获得了恢复效果。」+「你获得了恢复的效果。」）⇒ 归一名字、1s 窗内同名只出一条
  if a then
    local key = string.gsub(a, "的效果$", "")
    key = string.gsub(key, "效果$", "")
    if not dupOk("ag:" .. key, 1.0) then return end
    addText("auraGain", "+ " .. a, 0, a)
  else capture("PERIODIC_SELF_BUFFS?", m) end
end

EVH["CHAT_MSG_SPELL_AURA_GONE_SELF"] = function(m)
  local a = string.match(m, "^(.+)效果从你身上消失") or string.match(m, "^(.+)消失了")
  if a then
    local key = string.gsub(a, "的效果$", "")
    key = string.gsub(key, "效果$", "")
    if not dupOk("af:" .. key, 1.0) then return end
  end
  addText("auraFade", "- " .. (a or m), 0, a)
end

EVH["CHAT_MSG_COMBAT_HONOR_GAIN"] = function(m)
  local n = numOf(m)
  addText("honor", n and ("+" .. n .. " 荣誉") or m, 0)
end

-- 受到的伤害（附加项 incoming；0.2.3 补上 —— 真机句式「噬骨者击中你造成32点伤害。」）：
--   事件名按 vanilla 候选注册（pcall 逐个试，不存在的被客户端静默忽略；哪个真发火捕获环说话）
--   ★0.2.4 真机实锤：这类事件的 arg1 负载可能是**裸名字**（不是整句文本）⇒ 提不出数字
--     一律不显示（否则屏上出「-losol」这种垃圾），原文落环待校准（与治疗的「+?」同一把尺子）
--   ★★0.2.27 归属门：这条必须**是打在我身上**的 —— 真机例「雌性草原狮击中Cat造成8点伤害。」
--     是**宠物挨打**（2026-10-08 用户日志），旧写法会把它显示成红色「-8」当作我受到的伤害。
--     判据 = 整句里必须出现「你」（vanilla zhCN 的自我受击句式一律含「你」）。
local function inHit(m)
  if type(m) ~= "string" or not string.find(m, "你", 1, true) then
    D.noteShape("in-other", m) return
  end
  local n = numOf(m)
  if not n then capture("INCOMING-NONUM", m) return end
  addText("incoming", "-" .. n, isCrit(m) and 1 or 0)
end
local function inMiss(m)
  if type(m) ~= "string" or not string.find(m, "你", 1, true) then
    D.noteShape("inmiss-other", m) return
  end
  local w = string.find(m, "躲闪") and "躲闪" or string.find(m, "招架") and "招架"
         or string.find(m, "未击中") and "未击中" or string.find(m, "抵抗") and "抵抗" or "未命中"
  addText("incoming", w, 0)
end
EVH["CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"]   = inHit
EVH["CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"]       = inHit
EVH["CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"]   = inHit
EVH["CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE"]      = inHit
EVH["CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"]  = inMiss
EVH["CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES"]     = inMiss
EVH["CHAT_MSG_COMBAT_FACTION_CHANGE"] = function(m)
  local fac, n = string.match(m, "你在(.+)中的声望.+(%d+)点")
  addText("rep", "+" .. (n or "?") .. " 声望" .. (fac and ("·" .. fac) or ""), 0)
end

EVH["PLAYER_REGEN_DISABLED"] = function() addText("combat", "进入战斗", 0) end
EVH["PLAYER_REGEN_ENABLED"]  = function() addText("combat", "离开战斗", 0) end
EVH["SPELLS_CHANGED"]        = function() D.iconScan() end
-- ★0.2.27 宠物技能图标：宠物换了/动作条变了就重扫图标缓存（不然新学的技能要 /reload 才有图）
EVH["PET_BAR_UPDATE"]        = function() D.iconScan() end
EVH["UNIT_PET"]              = function(u) if u == "pet" or u == nil then D.iconScan() end end

EVH["UNIT_COMBO_POINTS"] = function(u)
  if u ~= "player" then return end
  local n
  if type(GetComboPoints) == "function" then
    local ok, v = pcall(GetComboPoints, "player", "target")
    if ok and type(v) == "number" then n = v
    else local ok2, v2 = pcall(GetComboPoints, "target") if ok2 then n = tonumber(v2) end end
  end
  if n and n > 0 then addText("combo", "连击点 ×" .. n, 0) end
end

-- 生命/法力过低（跨阈值一次，恢复后重新武装）
D.lowArmed = { hp = true, mana = true }
EVH["UNIT_HEALTH"] = function(u)
  if u ~= "player" or not itemOn("lowHealth") then return end
  local h, hm = UnitHealth("player"), UnitHealthMax("player")
  if hm and hm > 0 then
    local p = h / hm
    if p < 0.20 and D.lowArmed.hp then D.lowArmed.hp = false addText("lowhp", "生命值过低！", 1)
    elseif p >= 0.35 then D.lowArmed.hp = true end
  end
end
EVH["UNIT_MANA"] = function(u)
  if u ~= "player" or not itemOn("lowHealth") then return end
  if type(UnitPowerType) == "function" and UnitPowerType("player") ~= 0 then return end  -- 只报蓝条职业
  local v, vm = UnitMana("player"), UnitManaMax("player")
  if vm and vm > 0 then
    local p = v / vm
    if p < 0.20 and D.lowArmed.mana then D.lowArmed.mana = false addText("lowmana", "法力值过低！", 0)
    elseif p >= 0.35 then D.lowArmed.mana = true end
  end
end

-- 事件注册清单（注册本身 pcall 逐个试；不存在的事件名客户端会静默忽略或报错，都兜住）
local EVENTS = {
  "CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES",
  "CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_SELF_MISSES",
  "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE", "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
  "CHAT_MSG_COMBAT_PET_HITS", "CHAT_MSG_COMBAT_PET_MISSES", "CHAT_MSG_SPELL_PET_DAMAGE",
  "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", "CHAT_MSG_SPELL_PARTY_BUFF", "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
  "CHAT_MSG_SPELL_SELF_BUFF",
  "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS", "CHAT_MSG_SPELL_AURA_GONE_SELF",
  "CHAT_MSG_COMBAT_HONOR_GAIN", "CHAT_MSG_COMBAT_FACTION_CHANGE",
  "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES",
  "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS", "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES",
  "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE", "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
  "PET_BAR_UPDATE", "UNIT_PET",                       -- ★0.2.27 宠物技能图标重扫
  "UNIT_COMBO_POINTS", "UNIT_HEALTH", "UNIT_MANA",
}

D.evFrame = nil
local function eventSync()
  if type(CreateFrame) ~= "function" then return end
  local want = C().master == true
  if not D.evFrame then
    D.evFrame = CreateFrame("Frame", "EH_DMG_EVENT")
    D.evFrame:SetScript("OnEvent", function()
      local ev = rawget(_G, "event")
      local m = rawget(_G, "arg1")
      -- ★0.2.4 深度捕获：开着捕获时把**全部事件原始负载**（event + arg1/2/3）落环 ——
      --   本客户端事件负载与聊天文本未必同构（真机实锤：incoming 的 arg1 可能是裸名字），
      --   校准解析必须看负载原文，不看聊天框。★0.2.8：UNIT_* 不记（每帧都发，会刷爆环）。
      if C().capture and ev and string.sub(ev, 1, 5) ~= "UNIT_" then
        ringPush("RAW " .. tostring(ev) .. " |1=" .. tostring(m) ..
          " |2=" .. tostring(rawget(_G, "arg2")) .. " |3=" .. tostring(rawget(_G, "arg3")))
      end
      local h = ev and EVH[ev] or nil
      if h then
        local ok, err = pcall(h, m)
        if not ok then ringPush("ERR " .. tostring(ev) .. " | " .. tostring(err)) end
      elseif ev and string.sub(ev, 1, 9) == "CHAT_MSG_" then
        capture(ev, m)                       -- 未识别的战斗文本：捕获开着就落环
      end
    end)
  end
  for _, ev in ipairs(EVENTS) do
    if want then pcall(D.evFrame.RegisterEvent, D.evFrame, ev)
    else pcall(D.evFrame.UnregisterEvent, D.evFrame, ev) end
  end
end

-- ----------------------------------------------------------------------------
-- 编辑模式：拖拽锚点 + 模拟战斗（实时预览参数效果）
-- ----------------------------------------------------------------------------
D.editOn = false
D.editUI = nil
D.simOn = false
D.simNext = 0
D.simIdx = 0

-- ----------------------------------------------------------------------------
-- ★0.2.32 模拟战斗的**技能名池**（用户：「模拟战斗的时候随便添加个攻击技能的图标做图标和文字的测试案例」）
--   以前模拟战斗**一个 spellName 都不传** ⇒ 图标通道从来没被它覆盖到（0.2.31 图标跟着数字一起缩放后更需要它）。
--   三条纪律：① 候选**必须真的能解析出图标**才入池（名字写错 / 这个角色没学过 = 静默不画图 ⇒ 这个测试案例等于没测）；
--   ② `D.iconScan` 重扫法术书后**按缓存对象身份重新过滤**（学了新技能不用 /reload）；
--   ③ 一个都解析不出 ⇒ **退回不带名字**（宁可没有图标，也绝不画错图）+ 如实说一次。
-- ----------------------------------------------------------------------------
local SIM_SKILLS = {
  atk = { "英勇打击", "致死打击", "背刺", "邪恶攻击", "火球术", "冰霜震击", "闪电箭", "自动射击", "猛击", "斩击" },
  pet = { "撕咬", "爪击", "冲锋", "低吼", "闪电吐息" },
}
local SIM_POOL, SIM_POOL_CACHE, SIM_NO_SAY = nil, nil, false

local function simPoolEnsure()
  if SIM_POOL and SIM_POOL_CACHE == D.iconCache then return end
  SIM_POOL = { atk = {}, pet = {} }
  SIM_POOL_CACHE = D.iconCache
  local hit = 0
  for k, list in pairs(SIM_SKILLS) do
    for i = 1, table.getn(list) do
      if iconOf(list[i]) then table.insert(SIM_POOL[k], list[i]) hit = hit + 1 end
    end
  end
  if hit == 0 and not SIM_NO_SAY then
    SIM_NO_SAY = true
    say("模拟战斗：法术书里没有候选技能 ⇒ 样例只测文字、不配图标（学一个候选技能，或改 SIM_SKILLS 候选表）")
  end
end
-- 取一个（轮转）**能解析出图标**的技能名；该类池空 ⇒ 退回攻击池；两池都空 ⇒ nil（退回无图标）
local function simSkill(cls)
  simPoolEnsure()
  local pool = SIM_POOL or {}
  local list = pool[cls]
  if (not list or table.getn(list) == 0) and cls ~= "atk" then list = pool.atk end
  if not list or table.getn(list) == 0 then return nil end
  D.simSkillIdx = ((D.simSkillIdx or 0) % table.getn(list)) + 1
  return list[D.simSkillIdx]
end
-- 池子的一行人话（开关播报与 `/edmg 状态` **共用同一份**，绝不各拼一遍）
local function simPoolLine()
  simPoolEnsure()
  local atk = (SIM_POOL and SIM_POOL.atk) or {}
  local pet = (SIM_POOL and SIM_POOL.pet) or {}
  if table.getn(atk) == 0 and table.getn(pet) == 0 then return "无（只测文字、不配图标）" end
  local s = table.concat(atk, "/")
  if table.getn(pet) > 0 then s = s .. " ｜ 宠物：" .. table.concat(pet, "/") end
  return s
end

local SIM_SEQ = {
  { kind = "damage",    fn = function() return tostring(math.random(80, 900)) end, crit = 0, sk = "atk" },
  { kind = "damage",    fn = function() return tostring(math.random(400, 1600)) end, crit = 1, sk = "atk" },
  { kind = "dot",       fn = function() return tostring(math.random(20, 120)) .. " ·持续" end, crit = 0, sk = "atk" },
  { kind = "pet",       fn = function() return tostring(math.random(30, 220)) .. " ·宠物" end, crit = 0, sk = "pet" },
  { kind = "heal",      fn = function() return "+" .. math.random(100, 600) .. " [治疗者甲]" end, crit = 0 },
  { kind = "incoming",  fn = function() return "-" .. math.random(50, 400) end, crit = 0 },
  { kind = "auraGain",  fn = function() return "+ 奥术智慧" end, crit = 0 },
  { kind = "auraFade",  fn = function() return "- 奥术智慧" end, crit = 0 },
  { kind = "combat",    fn = function() return (D.simIdx % 2 == 0) and "进入战斗" or "离开战斗" end, crit = 0 },
  { kind = "miss",      fn = function()
      local w = { "躲闪", "招架", "未击中" }
      return w[math.random(1, 3)]
    end, crit =0 },
  { kind = "mitigation",fn = function() return "-" .. math.random(10, 90) .. " 减免" end, crit = 0 },
  { kind = "energize",  fn = function() return "法力+" .. math.random(5, 40) end, crit = 0 },
  { kind = "honor",     fn = function() return "+" .. math.random(10, 200) .. " 荣誉" end, crit = 0 },
  { kind = "combo",     fn = function() return "连击点 ×" .. math.random(1, 5) end, crit = 0 },
  { kind = "rep",       fn = function() return "+" .. math.random(5, 25) .. " 声望·暴风城" end, crit = 0 },
  { kind = "lowhp",     fn = function() return "生命值过低！" end, crit = 1 },
}

local function simFire()
  -- 只放「当前勾选」的种类：未勾的跳过（连跳一圈还没勾的就静默一轮）
  for _ = 1, table.getn(SIM_SEQ) do
    D.simIdx = (D.simIdx % table.getn(SIM_SEQ)) + 1
    local e = SIM_SEQ[D.simIdx]
    local gate = KIND_ITEM[e.kind]
    if not gate or itemOn(gate) then
      -- ★0.2.32 第 4 参 = 技能名 ⇒ 走**图标通道**（`iconOf` 查法术书缓存；池空时 simSkill 返回 nil
      --   ⇒ 退回无图标，与老行为一字不差）。★图标行/文字行两条路都覆盖：开着「技能名文本」时
      --   文本含中文 ⇒ 该行走 FontString 且图标锚在文字左缘；关着时纯数字走图集、图标锚数字组左缘。
      local sp = nil
      if e.sk then sp = simSkill(e.sk) end
      addText(e.kind, e.fn(), e.crit, sp)
      return
    end
  end
end

local function editEnsureUI()
  if D.editUI then return true end
  if type(CreateFrame) ~= "function" then return false end
  -- ★0.2.28 两个锚点（用户真机报障「受到的伤害数字太下面的，距离锚点太远了」）：
  --   金色 = 主锚点（伤害/治疗/效果那几条 lane="out" 的车道）· 红色 = 受击锚点（lane="in"）。
  --   同一套配方建两份实例，拖动分别写 posX/posY 与 inOffY；1.12 无销毁 API ⇒ 建一次只 Show/Hide。
  local function mkAnchor(fname, label, cr, cg, cb)
    local a = CreateFrame("Button", fname, UIParent)
    a:SetWidth(170) a:SetHeight(30)
    if type(a.EnableMouse) == "function" then pcall(a.EnableMouse, a, true) end
    pcall(a.RegisterForDrag, a, "LeftButton")
    local bg = a:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0) bg:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
    solid(bg, 0.10, 0.08, 0.04, 0.85)
    for _, e in ipairs({ "TOP", "BOTTOM" }) do
      local t = a:CreateTexture(nil, "BORDER") solid(t, cr, cg, cb, 1)
      t:SetPoint(e .. "LEFT", a, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", a, e .. "RIGHT", 0, 0) t:SetHeight(1)
    end
    for _, s in ipairs({ "LEFT", "RIGHT" }) do
      local t = a:CreateTexture(nil, "BORDER") solid(t, cr, cg, cb, 1)
      t:SetPoint("TOP" .. s, a, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, a, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
    end
    local fs = mkFont(a)
    pcall(fs.SetPoint, fs, "CENTER", a, "CENTER", 0, 0)
    pcall(fs.SetText, fs, label)
    pcall(fs.SetTextColor, fs, cr, cg, cb)
    return a, fs
  end
  local f, fs = mkAnchor("EH_DMG_ANCHOR", "伤害锚点（拖动）", 0.95, 0.82, 0.35)
  local g, gs = mkAnchor("EH_DMG_INANCHOR", "受击锚点（拖动）", 1.00, 0.45, 0.30)
  -- 拖拽三件套（项目已验证）：OnMouseDown 起 + 节拍里 GetCursorPosition 现算 + 鼠标键状态收尾
  f:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    D.drag = { which = "main", sx = cx, sy = cy, bx = C().posX or 0, by = C().posY or 0 }
  end)
  f:SetScript("OnMouseUp", function() D.drag = nil end)
  g:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    D.drag = { which = "in", sx = cx, sy = cy, by = tonumber(C().inOffY) or DEF.inOffY }
  end)
  g:SetScript("OnMouseUp", function() D.drag = nil end)
  D.editUI = { f = f, fs = fs, g = g, gs = gs }
  return true
end

local function editPlace()
  if not D.editUI then return end
  local c = C()
  pcall(D.editUI.f.SetPoint, D.editUI.f, "CENTER", UIParent, "CENTER", c.posX or 0, c.posY or 0)
  -- 受击锚点 = 主锚点 + 受击下移（与 addText 里 lane="in" **同一条算式**，绝不各写一份）
  if D.editUI.g then
    pcall(D.editUI.g.SetPoint, D.editUI.g, "CENTER", UIParent, "CENTER",
      c.posX or 0, (c.posY or 0) + (tonumber(c.inOffY) or DEF.inOffY))
  end
end

local function editSet(on)
  D.editOn = on and true or false
  if D.editOn then
    if not editEnsureUI() then say("编辑模式不可用（建不出控件）") D.editOn = false return end
    editPlace()
    pcall(D.editUI.f.Show, D.editUI.f)
    if D.editUI.g then pcall(D.editUI.g.Show, D.editUI.g) end
    say("编辑模式：开 —— 金色锚点 = 伤害行起点，红色锚点 = 受击行起点（都能直接拖）")
  else
    if D.editUI then
      pcall(D.editUI.f.Hide, D.editUI.f)
      if D.editUI.g then pcall(D.editUI.g.Hide, D.editUI.g) end
    end
    D.drag = nil
    say("编辑模式：关")
  end
end
D.editSet = editSet

-- ★0.2.32 模拟战斗的**唯一开关口**（面板「模拟战斗」按钮与 `/edmg 模拟` 共用）
--   —— 以前两处各写一遍「翻转 + 必要时进编辑模式 + 清 simNext + 播报」，改一处漏一处；
--   现在播报里还会**如实点出用哪些样例技能**（池空就直说「一个都解析不出」）。
function D.simSet(on)
  D.simOn = on and true or false
  if D.simOn and not D.editOn then editSet(true) end
  D.simNext, D.simIdx = 0, 0
  if type(D.uiRefresh) == "function" then D.uiRefresh() end
  if not D.simOn then say("模拟战斗：关") return end
  say("模拟战斗：开（编辑锚点处持续放样例数字 · 样例技能：" .. simPoolLine() .. "）")
end

-- 编辑模式的每拍（由 tick 在 editOn 时调用）
function D.editTick(now)
  -- 拖拽推进：读光标 + 键状态收尾（GetCursorPosition 与 SetPoint 同单位是本客户端既有口径，真机复核）
  if D.drag then
    if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
      D.drag = nil
    else
      local cx, cy = GetCursorPosition()
      local c = C()
      if D.drag.which == "in" then
        -- 受击锚点：只认垂直位移（红锚点相对主锚点画，水平跟着主锚点走）
        -- ★0.2.28（同版收口）：**先取整再夹**（光标是浮点 ⇒ 不取整会把 -43.86591064453 写进存档）
        local v = math.floor((D.drag.by or DEF.inOffY) + (cy - D.drag.sy) + 0.5)
        c.inOffY = math.max(D.INOFF_MIN, math.min(D.INOFF_MAX, v))
      else
        -- ★0.2.39 主锚点也**取整**（0.2.39 起 posX/posY 进了面板 = 用户会读它 ⇒ 与 inOffY 同一把尺子：
        --   「凡是把光标差写进存档的字段，都要问一句它该不该是小数」；小数位是亚逻辑单位，肉眼不可见）
        c.posX = math.floor(D.drag.bx + (cx - D.drag.sx) + 0.5)
        c.posY = math.floor(D.drag.by + (cy - D.drag.sy) + 0.5)
      end
      editPlace()
    end
  end
  -- 模拟战斗（0.2.12 加密：0.45s 一拍、每拍两条 —— 用户「频率再快一点、信息密集一点」）
  if D.simOn and now >= D.simNext then
    D.simNext = now + 0.45
    simFire()
    simFire()
  end
end

-- ----------------------------------------------------------------------------
-- 配置面板（/edmg ui）：15+1 显示项勾选 + 参数行 + 编辑模式/模拟战斗入口
-- ----------------------------------------------------------------------------
ui = { built = false, px = 0, py = 0 }    -- px/py = 面板拖出的位置（会话态，不落存档）

local function uiSolidBtn(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w) b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  local bb = b:CreateTexture(nil, "BACKGROUND")
  bb:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) bb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  solid(bb, 0.22, 0.17, 0.07, 1)
  local t = mkFont(b)
  pcall(t.SetPoint, t, "CENTER", b, "CENTER", 0, 0)
  pcall(t.SetText, t, label)
  b:SetScript("OnClick", onClick)
  return b, t, bb
end

local function uiRefresh()
  if not ui.built then return end
  local c = C()
  for _, row in ipairs(ui.itemRows) do
    if row.get() then pcall(row.mk.Show, row.mk) else pcall(row.mk.Hide, row.mk) end
  end
  pcall(ui.dirText.SetText, ui.dirText, DIR_ZH[c.direction] or c.direction)
  pcall(ui.sizeText.SetText, ui.sizeText, (D.TIER[c.fontTier or 3].zh) .. "（" .. tostring(c.fontTier or 3) .. "/" .. table.getn(D.TIER) .. "）")
  pcall(ui.speedText.SetText, ui.speedText, tostring(c.speed))
  pcall(ui.durText.SetText, ui.durText, string.format("%.1f", c.duration or 2.0))
  pcall(ui.curveText.SetText, ui.curveText, CURVE_ZH[c.curve or "cubic"] or tostring(c.curve))
  pcall(ui.clampText.SetText, ui.clampText, tostring(tonumber(c.clampPct) or 30) .. "%")
  -- ★0.2.28（同版收口）受击下移**只显示整数**（用户：「受击位移只 int 类型处理下不需要保留小数位」）
  local inV = math.floor((tonumber(c.inOffY) or DEF.inOffY) + 0.5)
  pcall(ui.inText.SetText, ui.inText, tostring(inV))
  -- ★0.2.39 主锚点 X/Y（面板旋钮）：与受击下移**同一口径 = 显示整数**（字段本身也已取整，见 editTick）
  if ui.posXText then
    pcall(ui.posXText.SetText, ui.posXText, tostring(math.floor((tonumber(c.posX) or DEF.posX) + 0.5)))
    pcall(ui.posYText.SetText, ui.posYText, tostring(math.floor((tonumber(c.posY) or DEF.posY) + 0.5)))
  end
  pcall(ui.faText.SetText, ui.faText, tostring(tonumber(c.faScale) or 100) .. "%")
  -- ★0.2.30 描边风格：显示中文名 + id（表里没有这种风格的度量时如实点出来，绝不假装换过）
  pcall(ui.faEdgeText.SetText, ui.faEdgeText,
    (D.FAS_ZH[D.faStyleNow()] or D.faStyleNow()) .. (D.faEdgeOK() and "" or "（表里没有）"))
  -- ★0.2.38 字体图集（字形素材；派生自 faEdge —— 与「描边样式」一起看才是完整选择）
  if ui.faSetText then
    local _, gzh = D.faGlyphNow()
    pcall(ui.faSetText.SetText, ui.faSetText, tostring(gzh or "?"))
  end
  -- ★0.2.31 缩放动画：曲线名 + 幅度%（0 = 关，显示成「关」比显示 0% 直观）；★0.2.34 加初始缩放
  pcall(ui.acText.SetText, ui.acText, CURVE_ZH[c.animCurve or DEF.animCurve] or tostring(c.animCurve))
  local aa = tonumber(c.animAmp) or DEF.animAmp
  pcall(ui.aaText.SetText, ui.aaText, (aa <= 0) and "关" or (tostring(aa) .. "%"))
  local an = tonumber(c.animStart) or DEF.animStart
  pcall(ui.anStartText.SetText, ui.anStartText, (an == 100) and "不弹入" or (tostring(an) .. "%"))
  local ae = tonumber(c.animEnd) or DEF.animEnd
  pcall(ui.anEndText.SetText, ui.anEndText, (ae <= 0) and "不缩" or (tostring(ae) .. "%"))
  pcall(ui.editText.SetText, ui.editText, D.editOn and "编辑模式：开" or "编辑模式：关")
  pcall(ui.simText.SetText, ui.simText, D.simOn and "模拟战斗：开" or "模拟战斗：关")
  pcall(ui.masterMk.Show, ui.masterMk)
  if c.master ~= true then pcall(ui.masterMk.Hide, ui.masterMk) end
end

local function uiBuild()
  if ui.built then return true end
  if type(CreateFrame) ~= "function" then return false end
  local W, H = 470, 594                  -- ★0.2.40 勾选区 2 列 → **3 列**（7 行）后高度重算：
                                         --   表头+总开关 62 + 勾选 7 行 154 + 参数区 296（4×HDR 20 + 9×ROW 24）+ 按钮/备注 ~82
                                         --   （变更史：424 → 448 → 472 → 496 → 520（0.2.35）→ 544（0.2.38）→ 660（0.2.39 分组）→ 594（0.2.40 勾选三列））
  local root = CreateFrame("Frame", "EH_DMG_UI", UIParent)
  root:SetWidth(W) root:SetHeight(H)
  root:SetPoint("CENTER", UIParent, "CENTER", ui.px, ui.py)
  pcall(root.SetFrameStrata, root, "DIALOG")
  pcall(root.SetFrameLevel, root, 90)
  if type(root.EnableMouse) == "function" then pcall(root.EnableMouse, root, true) end
  local bg = root:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0) bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  -- ★0.2.40 **完全不透明**（用户点头改的）：原 0.96 会留 4% 透光 ⇒ 面板背后飘过的战斗文字/世界/
  --   动作条会透过面板显示成**淡黄横条**（实测 rgb(19,18,15) vs 底色 (13,11,7)）；改成 1 之后面板内干净。
  --   ★反向钉：第 5 个参**不许再退回 0.96**（改了就等于把「黄条」请回来）。
  solid(bg, 0.05, 0.04, 0.03, 1)
  for _, e in ipairs({ "TOP", "BOTTOM" }) do
    local t = root:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint(e .. "LEFT", root, e .. "LEFT", 0, 0) t:SetPoint(e .. "RIGHT", root, e .. "RIGHT", 0, 0) t:SetHeight(1)
  end
  for _, s in ipairs({ "LEFT", "RIGHT" }) do
    local t = root:CreateTexture(nil, "BORDER") solid(t, 0.85, 0.70, 0.20, 1)
    t:SetPoint("TOP" .. s, root, "TOP" .. s, 0, 0) t:SetPoint("BOTTOM" .. s, root, "BOTTOM" .. s, 0, 0) t:SetWidth(1)
  end

  local title = mkFont(root)
  pcall(title.SetPoint, title, "TOP", root, "TOP", 0, -10)
  pcall(title.SetText, title, "增强伤害显示（EH_Damage v" .. BUILD .. "）")
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)

  -- ★标题栏 = 面板拖拽柄（已验证三件套：OnMouseDown 起 + 节拍里 GetCursorPosition 现算 + 键状态收尾；
  --   绝不 SetMovable/StartMoving —— 那套只有一条收尾路，柄一丢捕获窗口就黏在光标上）
  local dh = CreateFrame("Button", nil, root)
  dh:SetWidth(W - 24) dh:SetHeight(24)
  dh:SetPoint("TOP", root, "TOP", 0, -2)
  if type(dh.EnableMouse) == "function" then pcall(dh.EnableMouse, dh, true) end
  if type(dh.SetFrameLevel) == "function" then pcall(dh.SetFrameLevel, dh, 95) end
  dh:SetScript("OnMouseDown", function()
    local cx, cy = GetCursorPosition()
    ui.drag = { sx = cx, sy = cy, bx = ui.px, by = ui.py }
  end)
  dh:SetScript("OnMouseUp", function() ui.drag = nil end)
  ui.dragHandle = dh

  -- 总开关
  local mchk = CreateFrame("CheckButton", nil, root)
  mchk:SetWidth(16) mchk:SetHeight(16)
  mchk:SetPoint("TOPLEFT", root, "TOPLEFT", 18, -34)
  if type(mchk.EnableMouse) == "function" then pcall(mchk.EnableMouse, mchk, true) end
  local mo = mchk:CreateTexture(nil, "BACKGROUND")
  mo:SetPoint("TOPLEFT", mchk, "TOPLEFT", 0, 0) mo:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", 0, 0)
  solid(mo, 0.85, 0.70, 0.20, 1)
  local mb = mchk:CreateTexture(nil, "ARTWORK")
  mb:SetPoint("TOPLEFT", mchk, "TOPLEFT", 1, -1) mb:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", -1, 1)
  solid(mb, 0.10, 0.09, 0.06, 1)
  local mmk = mchk:CreateTexture(nil, "OVERLAY")
  mmk:SetPoint("TOPLEFT", mchk, "TOPLEFT", 3, -3) mmk:SetPoint("BOTTOMRIGHT", mchk, "BOTTOMRIGHT", -3, 3)
  solid(mmk, 0.95, 0.80, 0.25, 1)
  mchk:SetScript("OnClick", function()
    C().master = not (C().master == true)
    if C().master then eventSync() else slotReleaseAll() end
    beatSync()
    uiRefresh()
    say("总开关：" .. (C().master and "开" or "关（已收层、停节拍、摘事件）"))
  end)
  local mlabel = mkFont(root)
  pcall(mlabel.SetPoint, mlabel, "LEFT", mchk, "RIGHT", 6, 0)
  pcall(mlabel.SetText, mlabel, "总开关（关掉 = 收层 + 停节拍 + 摘事件）")
  ui.masterMk = mmk

  -- 勾选网格（0.2.6 重排：显示项 + 开关类参数全收进网格，填掉左列空档 —— 用户定）
  ui.itemRows = {}
  local function mkItem(zh, get, set, x, y)
    local chk = CreateFrame("CheckButton", nil, root)
    chk:SetWidth(14) chk:SetHeight(14)
    chk:SetPoint("TOPLEFT", root, "TOPLEFT", x, y)
    if type(chk.EnableMouse) == "function" then pcall(chk.EnableMouse, chk, true) end
    local o = chk:CreateTexture(nil, "BACKGROUND")
    o:SetPoint("TOPLEFT", chk, "TOPLEFT", 0, 0) o:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", 0, 0)
    solid(o, 0.85, 0.70, 0.20, 1)
    local b2 = chk:CreateTexture(nil, "ARTWORK")
    b2:SetPoint("TOPLEFT", chk, "TOPLEFT", 1, -1) b2:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -1, 1)
    solid(b2, 0.10, 0.09, 0.06, 1)
    local mk = chk:CreateTexture(nil, "OVERLAY")
    mk:SetPoint("TOPLEFT", chk, "TOPLEFT", 2, -2) mk:SetPoint("BOTTOMRIGHT", chk, "BOTTOMRIGHT", -2, 2)
    solid(mk, 0.95, 0.80, 0.25, 1)
    chk:SetScript("OnClick", function() set(not get()) uiRefresh() end)
    local lb = mkFont(root)
    pcall(lb.SetPoint, lb, "LEFT", chk, "RIGHT", 5, 0)
    pcall(lb.SetText, lb, zh)
    pcall(lb.SetTextColor, lb, 0.92, 0.88, 0.80)
    table.insert(ui.itemRows, { get = get, mk = mk })
  end
  local TOGGLES = {}
  for _, it in ipairs(ITEMS) do
    local id = it.id
    table.insert(TOGGLES, { zh = it.zh,
      get = function() return itemOn(id) end,
      set = function(v) C()["it_" .. id] = v and true or false end })
  end
  table.insert(TOGGLES, { zh = "暴击缩放动画",
    get = function() return C().critAnim == 1 end, set = function(v) C().critAnim = v and 1 or 0 end })
  table.insert(TOGGLES, { zh = "技能图标",
    get = function() return C().showIcon ~= false end, set = function(v) C().showIcon = v and true or false end })
  table.insert(TOGGLES, { zh = "技能名文本",
    get = function() return C().showSpellText == true end, set = function(v) C().showSpellText = v and true or false end })
  -- ★0.2.29 网格最后一个空位（第 20 格）：战斗数字改用**插件自带字体图集**（R4；默认关）
  table.insert(TOGGLES, { zh = "自带字体图集",
    get = function() return C().fontAtlas == true end, set = function(v) D.fontAtlasSet(v) end })
  -- ★0.2.40 勾选区改 **3 列**（用户：「将以上的开关3列进行排列」）：
  --   **列优先**填（与旧 2 列同一口径，只换行数/列数 ⇒ 顺序仍是老用户认得的那个顺序）：20 项 = 7 + 7 + 6 行。
  --   ★列距 150 是**核过最长标签**定的（列起点 = 18 / 168 / 318；面板内宽 = 470−36 = 434）：
  --     · 最长的「友方治疗者姓名显示」（9 个汉字 ≈ 108px）落在第 2 列 ⇒ 168 + 14(框) + 5(间隙) + 108 = 295 < 318 ✓
  --     · 第 3 列只有短的（「受到的伤害（附加）」最长 ≈ 108）⇒ 318 + 19 + 108 = 445 < 470−18 = 452 ✓（7px 余量）
  local GRID_ROWS, GRID_DX = 7, 150
  local y0 = -62
  for i, tg in ipairs(TOGGLES) do
    local col = math.floor((i - 1) / GRID_ROWS)     -- 列优先：前 7 项第 1 列、再 7 项第 2 列、余下第 3 列
    local row = (i - 1) % GRID_ROWS + 1
    mkItem(tg.zh, tg.get, tg.set, 18 + col * GRID_DX, y0 - (row - 1) * 22)
  end

  -- 数值/多选参数（0.2.6 重排：2×2 两列 —— 用户定）
  local py = y0 - GRID_ROWS * 22 - 14
  local function paramCell(label, x, y, getSet)
    local lb = mkFont(root)
    pcall(lb.SetPoint, lb, "TOPLEFT", root, "TOPLEFT", x, y)
    pcall(lb.SetTextColor, lb, 0.95, 0.80, 0.30)
    pcall(lb.SetText, lb, label)
    local bm = uiSolidBtn(root, "-", 22, 18, function() getSet(-1) uiRefresh() end)
    bm:SetPoint("TOPLEFT", root, "TOPLEFT", x + 78, y + 2)
    local val = mkFont(root)
    pcall(val.SetPoint, val, "TOPLEFT", root, "TOPLEFT", x + 106, y)
    pcall(val.SetWidth, val, 66)
    pcall(val.SetJustifyH, val, "LEFT")
    local bp = uiSolidBtn(root, "+", 22, 18, function() getSet(1) uiRefresh() end)
    bp:SetPoint("TOPLEFT", root, "TOPLEFT", x + 176, y + 2)
    return val
  end
  local PX1, PX2 = 18, 250
  -- ★0.2.39 参数区**按功能分组**（用户：「如何将这些参数进行功能分组方便配置」）—— 四组：
  --   ① 运动（怎么飘 / 飘多远 / 活多久）② 位置（从哪里开始飘 = 锚点）
  --   ③ 字形（字体素材 + 描边 + 字号粗调/细调）④ 缩放动画（出生 → 暴击 → 尾声）
  --   ★**纯布局改动**：真值、唯一写口、命令、读值口一个字节都没改（只是把同一批参数重排 + 加分组标题）。
  --   ★**行位只有一个来源** = 游标 `py`：`grp()` 吃掉 HDR、每排完一行调一次 `rowGap()`
  --     ⇒ 以后增删参数**只动这一段相邻两行**，绝不手写 `py - 168` 这类魔数（改一处漏三处的老雷）。
  local ROW, HDR = 24, 20            -- 参数行距 / 组标题行高（4×HDR + 9×ROW = 296 = 这一段的总占用）
  local function grp(zh)
    local g = mkFont(root)
    pcall(g.SetPoint, g, "TOPLEFT", root, "TOPLEFT", PX1, py)
    pcall(g.SetText, g, zh)
    pcall(g.SetTextColor, g, 1.00, 0.90, 0.55)
    -- ★★★0.2.42 修「一块一块黄色的背景区块」（用户真机截图原话：「这里有设置什么背景吗?怎么一块一块黄色的背景区块.」）
    --   **真凶 = 下面两行 `pcall(ln.SetWidth, …)` / `pcall(ln.SetHeight, …)` 漏传 self**
    --   （`pcall(X.方法, …)` 实参第一个必须是 X —— 与 0.2.11「参数行标签一行都不显示」同一条老雷）：
    --   两个 Set 都被 pcall 静默吞掉 ⇒ 这条分隔线**从来没拿到过尺寸** ⇒ 客户端按**默认尺寸 ≈32×32**
    --   画成金色方块。★真机截图取证：方块取色恰好 (104,83,39) = 0.42,0.34,0.16（= 分隔线颜色）；
    --   方块左上角正好落在分隔线锚点 `(PX1, py-15)`；实测 31×32 逻辑像素 ⇒ 每组**前两行参数标签**
    --   正好压在它上面 = 用户看到的一块块黄底（四组 = 四个方块；「时长」那一行不在方块里，所以它没有）。
    --   ⇒ 修法 = 补上 `ln` 这两个实参；顺带把 `solid` 提到几何之前（与面板边框同一套次序：
    --     先贴图/染色、后定尺寸 —— 面板边框就是这么写的，真机实测是一条正常 1px 亮线）。
    --   ★反向钉：这两行的第一个实参不许再丢（丢了 = 金色方块立刻回来）。
    local ln = root:CreateTexture(nil, "ARTWORK")     -- 组标题下的细分隔线（1px）
    solid(ln, 0.42, 0.34, 0.16, 1)
    pcall(ln.SetPoint, ln, "TOPLEFT", root, "TOPLEFT", PX1, py - 15)
    pcall(ln.SetWidth, ln, W - 2 * PX1)
    pcall(ln.SetHeight, ln, 1)
    py = py - HDR
  end
  local function rowGap() py = py - ROW end

  -- ① 运动（轨迹）：每条数字都吃这五个
  grp("【运动】怎么飘 · 飘多远 · 活多久")
  -- ★循环类参数（方向）：`+` 正向、`-` 反向（0.2.12；旧写法两颗都正滚 = 用户眼里的「调节异常」）
  ui.dirText = paramCell("滚动方向", PX1, py, function(d)
    local c = C()
    local i = 1
    for k, v in ipairs(DIRS) do if v == c.direction then i = k break end end
    local n = table.getn(DIRS)
    c.direction = DIRS[((i - 1 + (d or 1)) % n) + 1]
  end)
  ui.speedText = paramCell("速度", PX2, py, function(d) local c = C() c.speed = math.max(20, math.min(400, (c.speed or 90) + d * 10)) end)
  rowGap()
  -- ★0.2.23 曲线函数（蹦出系方向用；循环类：`-` 反向）
  ui.curveText = paramCell("曲线", PX1, py, function(d)
    local c = C()
    local i = 1
    for k, v in ipairs(CURVE_ORD) do if v == (c.curve or "cubic") then i = k break end end
    local n = table.getn(CURVE_ORD)
    c.curve = CURVE_ORD[((i - 1 + (d or 1)) % n) + 1]
  end)
  -- ★0.2.25 移动上限（占屏 %，行程夹取 + 屏界保险丝，见 tick）
  ui.clampText = paramCell("移动上限", PX2, py, function(d)
    local c = C() c.clampPct = math.max(5, math.min(60, (tonumber(c.clampPct) or 30) + d * 5))
  end)
  rowGap()
  ui.durText = paramCell("时长", PX1, py, function(d) local c = C() c.duration = math.max(0.5, math.min(6, (c.duration or 2.0) + d * 0.25)) end)
  rowGap()

  -- ② 位置（锚点）：只决定**起点在哪** —— 金色锚点 = 伤害行起点 · 红色锚点 = 受击行起点（编辑模式里都能拖）
  grp("【位置】从哪里开始（编辑模式可拖锚点）")
  -- ★0.2.39 主锚点 X/Y 面板旋钮（用户点名「补」）：此前 posX/posY **只能**在编辑模式拖金色锚点。
  --   ★**整数**口径与受击下移同一把尺子（光标是浮点 ⇒ 步进先取整再加 ±10、写回整数、显示整数）
  ui.posXText = paramCell("伤害锚点 X", PX1, py, function(d)
    local c = C()
    local cur = math.floor((tonumber(c.posX) or DEF.posX) + 0.5)
    c.posX = math.max(D.POS_MIN, math.min(D.POS_MAX, cur + d * 10))
  end)
  ui.posYText = paramCell("伤害锚点 Y", PX2, py, function(d)
    local c = C()
    local cur = math.floor((tonumber(c.posY) or DEF.posY) + 0.5)
    c.posY = math.max(D.POS_MIN, math.min(D.POS_MAX, cur + d * 10))
  end)
  rowGap()
  -- ★0.2.28 受击下移（受到伤害那一行相对主锚点往下多少；编辑模式的**红色锚点**写的就是这个字段）
  --   写入口**一律取整**（用户：「受击位移只 int 类型处理下不需要保留小数位」）
  ui.inText = paramCell("受击下移", PX1, py, function(d)
    local c = C()
    local cur = math.floor((tonumber(c.inOffY) or DEF.inOffY) + 0.5)
    c.inOffY = math.max(D.INOFF_MIN, math.min(D.INOFF_MAX, cur + d * 10))
  end)
  rowGap()

  -- ③ 字形（字体素材 + 描边 + 字号粗调/细调）
  grp("【字形】字体素材与描边")
  -- ★0.2.38 「字体图集」（用户原话：「我怎么没看到配置字体贴图的地方」）：选的是**字形素材**
  --   （内置字体 / 9c原版 / 古风武侠），右边的「描边样式」只在**当前这一组内**循环。
  --   ★派生视图：真正的配置真值仍只有 `faEdge` 一个（见 D.FAS_SETS 那段注释）。
  ui.faSetText = paramCell("字体图集", PX1, py, function(d) D.faGlyphStep(d) end)
  -- ★0.2.30 图集描边风格（用户：「字体黑色边框能换个吗?美化一点吗?」）—— ± 循环（写口 = D.faStyleSet）
  ui.faEdgeText = paramCell("描边样式", PX2, py, function(d) D.faStyleStep(d) end)
  rowGap()
  ui.sizeText = paramCell("字号档位", PX1, py, function(d)
    local c = C()
    local n = table.getn(D.TIER)
    c.fontTier = (((c.fontTier or 3) - 1 + (d or 1)) % n) + 1
  end)
  -- ★0.2.29 图集缩放（图集模式的**连续**字号微调；档位管粗调 = 换更粗的一档图）
  ui.faText = paramCell("图集缩放", PX2, py, function(d)
    local c = C()
    c.faScale = math.max(D.FAS_MIN, math.min(D.FAS_MAX, (tonumber(c.faScale) or 100) + d * 5))
  end)
  rowGap()

  -- ④ 缩放动画（**只对图集行生效** —— 文字行的缩放通道已被真机证死，见文件头注释）：出生 → 暴击 → 尾声
  grp("【缩放动画】出生 · 暴击 · 尾声（只对图集行）")
  -- ★0.2.31 缩放曲线（与「运动 → 曲线」共用 CURVES 表）
  ui.acText = paramCell("缩放曲线", PX1, py, function(d)
    local c = C()
    local i = 1
    for k, v in ipairs(CURVE_ORD) do if v == (c.animCurve or DEF.animCurve) then i = k break end end
    local n = table.getn(CURVE_ORD)
    c.animCurve = CURVE_ORD[((i - 1 + (d or 1)) % n) + 1]
  end)
  -- ★0.2.34 初始缩放（出生弹入的起点；100 = 不弹入、>100 = 由大缩回）
  ui.anStartText = paramCell("初始缩放", PX2, py, function(d)
    local c = C()
    local cur = tonumber(c.animStart) or DEF.animStart
    c.animStart = math.max(D.ANS_MIN, math.min(D.ANS_MAX, cur + d * 5))
  end)
  rowGap()
  -- ★0.2.34 暴击幅度（0 = **只关鼓包、不关弹入**）
  ui.aaText = paramCell("暴击幅度", PX1, py, function(d)
    local c = C()
    local cur = tonumber(c.animAmp) or DEF.animAmp
    c.animAmp = math.max(D.ANIM_MIN, math.min(D.ANIM_MAX, cur + d * 5))
  end)
  -- ★0.2.35 尾声缩小（淡出那一段同步缩小，到点随槽一起收掉 = 「缩小切隐藏」）
  ui.anEndText = paramCell("尾声缩小", PX2, py, function(d)
    local c = C()
    local cur = tonumber(c.animEnd) or DEF.animEnd
    c.animEnd = math.max(D.AEN_MIN, math.min(D.AEN_MAX, cur + d * 5))
  end)
  rowGap()

  -- 底部按钮
  local by = py - 6
  local e1; e1, ui.editText = uiSolidBtn(root, "编辑模式", 96, 20, function() editSet(not D.editOn) uiRefresh() end)
  e1:SetPoint("TOPLEFT", root, "TOPLEFT", 18, by)
  local e2; e2, ui.simText = uiSolidBtn(root, "模拟战斗", 96, 20, function() D.simSet(not D.simOn) end)
  e2:SetPoint("TOPLEFT", root, "TOPLEFT", 122, by)
  local e3 = uiSolidBtn(root, "重置位置", 84, 20, function()
    local c = C() c.posX, c.posY, c.inOffY = DEF.posX, DEF.posY, DEF.inOffY
    slotReleaseAll()
    editPlace() uiRefresh() say("两个锚点已重置（伤害 + 受击）")
  end)
  e3:SetPoint("TOPLEFT", root, "TOPLEFT", 226, by)
  local e4 = uiSolidBtn(root, "恢复默认", 84, 20, function()
    local c = C()
    for k, v in pairs(DEF) do c[k] = v end
    for _, it in ipairs(ITEMS) do c["it_" .. it.id] = it.def and true or false end
    editPlace() uiRefresh() say("已恢复默认配置")
  end)
  e4:SetPoint("TOPLEFT", root, "TOPLEFT", 318, by)
  local e5 = uiSolidBtn(root, "关闭", 60, 20, function() pcall(root.Hide, root) end)
  e5:SetPoint("TOPLEFT", root, "TOPLEFT", W - 78, by)

  local note = mkFont(root)
  pcall(note.SetPoint, note, "BOTTOMLEFT", root, "BOTTOMLEFT", 18, 12)
  pcall(note.SetText, note, "/edmg 事件=捕获环 · /edmg 捕获 · /edmg 编辑 · /edmg 状态 · /edmg 开|关")
  pcall(note.SetTextColor, note, 0.65, 0.65, 0.65)

  ui.root = root
  ui.built = true
  uiRefresh()
  return true
end

local function uiToggle()
  if not uiBuild() then say("配置面板不可用（建不出控件）") return end
  if ui.root:IsShown() then pcall(ui.root.Hide, ui.root)
  else uiRefresh() pcall(ui.root.Show, ui.root) end
end
D.uiRefresh = uiRefresh          -- ★0.2.29：给 D.fontAtlasSet 用（表字段 = 晚绑定，绝不写裸 local 名）
D.uiToggle = uiToggle

-- 面板拖拽推进（由唯一节拍帧 tick 驱动；不再立第二个节拍帧）
function D.uiDragTick()
  local d = ui.drag
  if not d then return end
  if type(IsMouseButtonDown) == "function" and not IsMouseButtonDown("LeftButton") then
    ui.drag = nil
    return
  end
  local cx, cy = GetCursorPosition()
  ui.px = d.bx + (cx - d.sx)
  ui.py = d.by + (cy - d.sy)
  -- 越界回归（读不到屏幕尺寸就不夹，fail-open）
  local okW, sw = pcall(UIParent.GetWidth, UIParent)
  if okW and type(sw) == "number" then
    local m = sw / 2 - 60
    if ui.px > m then ui.px = m elseif ui.px < -m then ui.px = -m end
  end
  local okH, sh = pcall(UIParent.GetHeight, UIParent)
  if okH and type(sh) == "number" then
    local m2 = sh / 2 - 40
    if ui.py > m2 then ui.py = m2 elseif ui.py < -m2 then ui.py = -m2 end
  end
  pcall(ui.root.ClearAllPoints, ui.root)
  pcall(ui.root.SetPoint, ui.root, "CENTER", UIParent, "CENTER", ui.px, ui.py)
end

-- ----------------------------------------------------------------------------
-- 总开关 / 关断四件事
-- ----------------------------------------------------------------------------
local function setMaster(on)
  local c = C()
  c.master = on and true or false
  if c.master then
    eventSync()
    say("EH_Damage 已开启（/edmg ui 配置 · /edmg 编辑 进入编辑模式）")
  else
    -- ① 资源回收：槽全部收回（1.12 无销毁 API ⇒ Hide + 清账）
    slotReleaseAll()
    -- ③ 数据重置：游标/拖拽/低血武装复位
    D.drag = nil
    D.lowArmed.hp = true D.lowArmed.mana = true
    D.shapeSeen = {}                 -- 句形去重表也随关断清（下次打开从零记）
    -- ④ 图层清理：编辑锚点收起（★0.2.28：**两个都要收** —— 只收金色那个会留一个红色空层吃点击）
    if D.editUI then
      pcall(D.editUI.f.Hide, D.editUI.f)
      if D.editUI.g then pcall(D.editUI.g.Hide, D.editUI.g) end
    end
    D.editOn = false D.simOn = false
    eventSync()      -- 摘全部事件
    say("EH_Damage 已关闭（收层 · 停节拍 · 摘事件）")
  end
  beatSync()         -- ② 节拍停止/重挂（唯一入口）
  uiRefresh()
end
D.setMaster = setMaster


-- ----------------------------------------------------------------------------
-- 命令
-- ----------------------------------------------------------------------------
local function cmd(msg)
  msg = tostring(msg or "")
  msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")
  local sub = string.lower(msg)
  if sub == "" or sub == "ui" then uiToggle() return end
  if sub == "编辑" or sub == "edit" then editSet(not D.editOn) uiRefresh() return end
  if sub == "模拟" or sub == "sim" then D.simSet(not D.simOn) return end
  if sub == "开" or sub == "on" then setMaster(true) return end
  if sub == "关" or sub == "off" then setMaster(false) return end
  if sub == "捕获" or sub == "capture" then
    local c = C() c.capture = not c.capture
    say("捕获未识别战斗文本：" .. (c.capture and "开（落存档环）" or "关"))
    return
  end
  if sub == "事件" or sub == "events" then
    local r = C().ring
    local n = table.getn(r)
    say("捕获环（" .. n .. " 条，最新在后）：")
    local from = math.max(1, n - 14)
    for i = from, n do say("  " .. r[i]) end
    return
  end
  if sub == "状态" or sub == "status" then
    local c = C()
    say("状态：总开关=" .. (c.master and "开" or "关") ..
      " 方向=" .. (DIR_ZH[c.direction] or "?") ..
      " 字号=" .. (D.TIER[c.fontTier or 3].zh) .. " 速度=" .. tostring(c.speed) ..
      " 时长=" .. string.format("%.1f", c.duration or 0) ..
      " 锚点=(" .. tostring(math.floor((tonumber(c.posX) or 0) + 0.5)) .. "," ..
        tostring(math.floor((tonumber(c.posY) or 0) + 0.5)) .. ")" ..
      " 受击下移=" .. tostring(math.floor((tonumber(c.inOffY) or DEF.inOffY) + 0.5)) ..
      " 上限=" .. tostring(tonumber(c.clampPct) or 30) .. "%" ..
      " 图集=" .. (c.fontAtlas == true and "开" or "关") .. "/" .. tostring(tonumber(c.faScale) or 100) .. "%" ..
      "/" .. (D.FAS_ZH[D.faStyleNow()] or D.faStyleNow()) ..
      " 缩放动画=" .. (CURVE_ZH[c.animCurve or DEF.animCurve] or "?") .. "/" ..
        ((tonumber(c.animAmp) or DEF.animAmp) <= 0 and "关" or (tostring(tonumber(c.animAmp) or DEF.animAmp) .. "%")) ..
        "/初始" .. tostring(tonumber(c.animStart) or DEF.animStart) .. "%" ..
        "/尾声" .. tostring(tonumber(c.animEnd) or DEF.animEnd) .. "%" ..
      " 槽=" .. D.poolN .. "/" .. POOL_MAX ..
      " 编辑=" .. (D.editOn and "开" or "关") .. " 模拟=" .. (D.simOn and "开" or "关") ..
      " 模拟技能=" .. simPoolLine() ..
      " v" .. BUILD)
    return
  end
  if sub == "测试" or sub == "test" then
    addText("damage", "888", 1)
    addText("dot", "66 ·持续", 0)
    addText("heal", "+233 [治疗者甲]", 0)
    say("已放 3 条测试字")
    return
  end
  -- ★0.2.29/0.2.30 图集体检（一条命令、零步骤、只读落盘）：读表 · 逐档探贴图能不能加载（带负对照）
  --   ★0.2.30 加一段「**每种风格**各探一张（tier1）」⇒ 换风格后文件没同步过来这一句话就能看出来。
  if sub == "图集" or sub == "atlas" then
    local ok = faEnsure()
    local c = C()
    local st = faStyleNow()
    local gid, gzh = D.faGlyphNow()
    local head = "自带字体图集：开关=" .. (c.fontAtlas == true and "开" or "关") ..
      " 缩放=" .. tostring(tonumber(c.faScale) or 100) .. "%" ..
      " 字体=" .. tostring(gzh) .. "(" .. tostring(gid) .. ")" ..
      " 描边=" .. (D.FAS_ZH[st] or st) .. "(" .. st .. ")" ..
      " 表=" .. (ok and (tostring(FA.N) .. " 档 / " .. tostring(FA.nch) .. " 字符" ..
        (FA.tiers[1] and FA.tiers[1].st and " / 多风格" or " / 单风格(旧表)")) or "读不到 FontDigits.lua")
    say(head)
    -- 负对照：同目录、同后缀、不可能存在的名字（本客户端对「不存在」也可能报非 0 尺寸 ⇒ 判不出）
    local neg = faProbeTex("Interface\\AddOns\\EH_Damage\\media\\__no_such_digits.tga")
    ringPush("FA " .. head .. " ｜ 负对照读回宽=" .. tostring(neg))
    -- 逐档（**当前风格**）：读回宽必须 == 该风格自己的表宽（否则就是切边/取错风格）
    local bad = 0
    for i = 1, math.min(FA.N, 12) do
      local t = FA.tiers[i]
      local file, W = faMetrics(t, st)
      local w = faProbeTex(file)
      local fit = (w == nil or not W or w == W) and "对" or "★不符"
      if not w or (W and w ~= W) then bad = bad + 1 end
      ringPush("FA tier" .. tostring(i) .. " 风格=" .. st .. " 表宽=" .. tostring(W) ..
        " 读回宽=" .. tostring(w) .. " " .. fit .. " ｜ " .. tostring(file))
      say("  " .. tostring(i) .. " 档（" .. (D.FAS_ZH[st] or st) .. "）：读回宽=" .. tostring(w) ..
        "（表宽=" .. tostring(W) .. " " .. fit .. "）")
    end
    -- 每种风格各探 tier1 一张（换风格的文件没同步 ⇒ 这一行当场看得出来）
    local line = "各风格 tier1 探针："
    for _, id in ipairs(D.FAS_ORD) do
      local file, W = faMetrics(FA.tiers[1], id)
      local w = faProbeTex(file)
      line = line .. " " .. id .. "=" .. tostring(w) .. "/" .. tostring(W) ..
        ((type(file) == "string" and w and W and w == W) and "" or "(★)")
    end
    say(line)
    ringPush("FA " .. line)
    say(neg and "★探针不可信（负对照也报出宽）⇒ 以屏上实际效果为准" or "探针可信（负对照读不到宽）")
    if ok then addText("damage", "1234567", 0) say("已放 1 条样例数字（当前档位 + 当前描边）") end
    if bad > 0 then say("有 " .. tostring(bad) .. " 档探不到贴图或表宽不符（文件没同步到游戏目录？）") end
    return
  end
  if sub == "图集开" or sub == "图集关" then
    D.fontAtlasSet(sub == "图集开")
    return
  end
  -- ★0.2.38 **`/edmg 字体`**：列/切「字体图集」（字形素材组）——面板那一行的命令入口，同一个写口 D.faStyleSet
  local fontArg = string.match(sub, "^字体%s+(.*)$") or string.match(sub, "^font%s+(.*)$")
  if sub == "字体" or sub == "font" or fontArg then
    local a = fontArg or ""
    if a == "" then
      local gid, gzh = D.faGlyphNow()
      local line = "字体图集：" .. tostring(gzh) .. "（" .. tostring(gid) .. "）· 描边样式："
        .. (D.FAS_ZH[D.faStyleNow()] or "?") .. "（" .. D.faStyleNow() .. "）"
      say(line)
      for k = 1, table.getn(D.FAS_SETS) do
        local s = D.FAS_SETS[k]
        local one = "  " .. s.zh .. "（" .. s.id .. "）= " .. table.concat(s.styles, " / ")
        say(one)
      end
      say("/edmg 字体 内置|9c|武侠 切换；两种成品字形来自 fonts\\ 里的位图素材（离线切图，见 README）")
      return
    end
    if not D.faGlyphSet(a) then
      say("认不出这套字体图集：" .. a .. "（可选 内置字体 / 9c原版 / 古风武侠，或组 id ttf/f9c/fwx）")
    end
    return
  end
  -- ★0.2.30 描边风格：`/edmg 描边` 列当前 + 全部可选；`/edmg 描边 soft` 直接设（id 或中文名都认）
  --   ★参数从**已小写归一**的整串里抠（多字节「描边」当字面量安全 —— 危险的是 `[...]` 字节集）
  local edgeArg = string.match(sub, "^描边%s+(.*)$") or string.match(sub, "^edge%s+(.*)$")
  if sub == "描边" or sub == "edge" or edgeArg then
    local a = edgeArg or ""
    if a == "" then
      -- ★0.2.38 按「字体图集」分组列（9 个 id 平铺会让人分不清「换字形」与「换描边」）
      local gid, gzh = D.faGlyphNow()
      say("字体图集：" .. tostring(gzh) .. "（" .. tostring(gid) .. "）｜ 当前描边："
        .. (D.FAS_ZH[D.faStyleNow()] or "?") .. "（" .. D.faStyleNow() .. "）")
      for k = 1, table.getn(D.FAS_SETS) do
        local s = D.FAS_SETS[k]
        local line = "  " .. s.zh .. "：" 
        for j = 1, table.getn(s.styles) do
          local id = s.styles[j]
          line = line .. " · " .. id .. "=" .. (D.FAS_ZH[id] or id)
        end
        say(line)
      end
      say(faEdgeOK() and "当前风格在表里有独立度量（FontDigits.lua / FontDigitsExtra.lua 都在）"
        or "★表里没有这种风格的度量 ⇒ 实际用的是硬描边（重跑生成器再同步：见 README「素材」那节）")
      return
    end
    if not D.faStyleSet(a) then
      say("认不出这种风格：" .. a .. "（/edmg 字体 看当前图集可选的样式，或用 /edmg 描边 列全部）")
    end
    return
  end
  say("命令：/edmg ui · 编辑 · 模拟 · 开|关 · 捕获 · 事件 · 状态 · 测试 · 图集 · 字体 [内置|9c|武侠] · 描边 [风格]")
end
D.cmd = cmd

if type(SlashCmdList) == "table" then
  SlashCmdList["EHDAMAGE"] = function(m) cmd(m) end
  rawset(_G, "SLASH_EHDAMAGE1", "/edmg")
  rawset(_G, "SLASH_EHDAMAGE2", "/edamage")
end

-- ----------------------------------------------------------------------------
-- 载入：toc 预载 + 载入期零副作用（不建帧）；VARIABLES_LOADED 后按真值武装
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("VARIABLES_LOADED")
boot:SetScript("OnEvent", function()
  local c = cfgEnsure()
  D.iconScan()                       -- 技能名→图标缓存（配图；法术书变了由 SPELLS_CHANGED 重扫）
  if c.master then eventSync() end
  beatSync()
  -- ★0.2.48 字体度量表缺档 / 读不到 ⇒ **如实报一行**（绝不让它静默；也绝不因此判「插件坏了」）
  --   来源 = FontDigitsExtra.lua（它跑在本文件**之前**，那一刻 say() 还不存在 ⇒ 只能先落一个全局）
  local fm = rawget(_G, "EVAL_EDMG_EXTRA_MISS")
  if type(fm) == "string" and fm ~= "" then
    say("★" .. fm .. " ⇒ 缺的那几档回落内置字体（其余照旧，功能不受影响）")
  end
  say("增强伤害显示 v" .. BUILD .. " 已载入（/edmg 打开配置 · /edmg 编辑 编辑模式 · /edmg 测试）")
end)

-- ----------------------------------------------------------------------------
-- 读值口（生产诊断；名字带 TEST 但保留 —— 真机取证与离线 harness 都走它们）
-- ----------------------------------------------------------------------------
function _G.EVAL_EDMG_STATE()
  local c = C()
  local active = 0
  for i = 1, D.poolN do if D.pool[i].active then active = active + 1 end end
  simPoolEnsure()          -- ★0.2.32 模拟战斗会用的样例技能（真实解析出来的；读取口顺带刷一次池）
  return {
    version = BUILD, master = c.master, direction = c.direction,
    fontTier = c.fontTier, speed = c.speed, duration = c.duration,
    posX = c.posX, posY = c.posY, inOffY = tonumber(c.inOffY) or DEF.inOffY,
    inOffMin = D.INOFF_MIN, inOffMax = D.INOFF_MAX, clampPct = tonumber(c.clampPct) or 30,
    inAnchor = (D.editUI and D.editUI.g) and true or false,
    -- ★0.2.29 自带字体图集（R4）：开关 / 缩放 / 表读到了没 / 档数 / 字符数
    fontAtlas = (c.fontAtlas == true), faScale = tonumber(c.faScale) or 100,
    faScaleMin = D.FAS_MIN, faScaleMax = D.FAS_MAX,
    -- ★0.2.30 描边风格：当前 id / 全部可选 / 表里有没有这种风格的独立度量
    faEdge = D.faStyleNow(), faEdgeList = table.concat(D.FAS_ORD, ","), faEdgeOK = D.faEdgeOK(),
    -- ★0.2.38 字体图集（字形素材组）：当前组 id / 中文名 / 组内可选样式串（派生自 faEdge，不是第二个配置键）
    faGlyph = select(1, D.faGlyphNow()), faGlyphZh = select(2, D.faGlyphNow()),
    -- ★0.2.31 缩放动画（图集行）：曲线 / 幅度% / 两段时长 / 幅度上下限（0 = 关）
    -- ★0.2.34 加**初始缩放**（出生弹入起点；100 = 不弹入）与峰值口径
    animCurve = (c.animCurve or DEF.animCurve), animAmp = tonumber(c.animAmp) or DEF.animAmp,
    animStart = tonumber(c.animStart) or DEF.animStart,
    animStartMin = D.ANS_MIN, animStartMax = D.ANS_MAX,
    -- ★0.2.35 尾声缩小（与淡出同相位）
    animEnd = tonumber(c.animEnd) or DEF.animEnd, animEndMin = D.AEN_MIN, animEndMax = D.AEN_MAX,
    animMin = D.ANIM_MIN, animMax = D.ANIM_MAX, popSec = D.FA_POP_SEC, critSec = D.FA_CRIT_SEC,
    faOK = faEnsure(), faN = FA.N, faChars = FA.nch,
    -- ★0.2.48 字体度量表缺档 / 读不到的如实记号（nil = 一切正常；来源 = FontDigitsExtra.lua）
    faMiss = (type(rawget(_G, "EVAL_EDMG_EXTRA_MISS")) == "string" and rawget(_G, "EVAL_EDMG_EXTRA_MISS")) or nil,
    pool = D.poolN, active = active,
    shapeN = shapeCount(),                        -- 句形环已记多少种（真机取证口）
    editOn = D.editOn, simOn = D.simOn, ring = table.getn(c.ring or {}),
    -- ★0.2.32 模拟战斗的样例技能池（都已确认能解析出图标 ⇒ 池空就是真没图标可配）
    simAtk = table.concat((SIM_POOL and SIM_POOL.atk) or {}, ","),
    simPet = table.concat((SIM_POOL and SIM_POOL.pet) or {}, ","),
    tickAttached = (D.frame ~= nil), build = BUILD,
  }
end
function _G.EVAL_EDMG_TEST_ADD(kind, text, crit) return addText(kind, text, crit) end
function _G.EVAL_EDMG_TEST_TICK(dt)                       -- 离线点火（动画走 GetTime 绝对时间，dt 仅作兼容入口）
  rawset(_G, "arg1", dt or 0.05)
  tick()
end
function _G.EVAL_EDMG_TEST_PARSE(ev, msg)                 -- 离线直跑某个事件处理器
  local h = EVH[ev]
  if not h then return false, "no handler" end
  return pcall(h, msg)
end
