-- ============================================================
-- EH_Bag —— EvalHelp 子插件：整合背包（自研零依赖）
--
-- ★设计口径（用户定）：功能与 UI 参考 TurtleWoW 的 OneBag
--   （D:\game\TurtleWoW\Interface\AddOns\OneBag），但**不搬运它的代码、不内嵌第三方库**
--   （它硬依赖 !Libs 的 Ace2 / DewDrop / OneStorage，本客户端没有 !Libs）。纯 Lua + 客户端 API。
--
-- ★★参考插件的功能清单（逐项对齐，▲ = 本文件实现位置）：
--   ① 整合显示：背包 0~4 一窗                        ▲ containers()/layout()
--   ② 钥匙链（-2）+ 钥匙按钮                        ▲ KEYRING / keyringBtn
--   ③ 银行：主格（-1，24 格）+ 银行包 5~10           ▲ BANK/BANKBAGS + bankOpen
--   ④ 银行包条（6 格，点=显隐、拖=换包、缺格标红+花费）▲ bankBar()
--   ⑤ 背包条（背包 + 4 包 + 钥匙）                   ▲ build()/layout()
--   ⑥ 品质描边（自带白框 media\slotframe.tga 按品质染色）   ▲ newItemButton/paintButton
--   ⑦ 搜索框                                        ▲ 搜索框 + applyFilter
--   ⑧ 类型筛选 = 8 颗图标按钮（单选/右键取消/悬停出件数）▲ B.CATS/cat8Of/catSet
--      + 品质筛选 = 5 颗彩色圆点                        ▲ qualSet/refreshQualDots
--   ⑧b 背包顺序（正序 / 倒序，参考 show.direction）    ▲ c.direction/cycleDir
--   ⑨ 一键整理                                      ▲ EH_BagSort.lua
--   ⑩ 金钱显示                                      ▲ moneyStr/ehMoney
--   ⑪ 计数（已用/总/空）                            ▲ refreshAll
--   ⑫ 悬停背包图标 ⇒ 高亮这包的所有格子               ▲ B.hoverBag/paintButton
--   ⑬ 开合流程：hook IsBagOpen/ToggleBag/OpenBag/CloseBag/Open(Close)Backpack/ToggleBackpack
--      + 银行/商贩/交易/拍卖 SHOW 自动开窗、CLOSED 自动关窗  ▲ installHooks/事件表
--   ⑭ 藏掉客户端原生容器帧（ContainerFrame1..N）      ▲ hideNative/ContainerFrame_Update 包装
--   ⑬b 玩家按键能开、也能关（★真机报障「能开不能关」）▲ intentOpen/intentClose/intentToggle
--   ⑮ 位置记忆 / ESC 关闭 / 关闭按钮 / 拖动柄          ▲ power 前几节
--   ⑯ 换包（把包拖到背包条图标上）                    ▲ bar 按钮 OnReceiveDrag
--   ★未实现（如实报告，不冒充已做）：
--     · OneView 跨角色物品总览 —— 参考用它自带的 OneStorage-2.0 做**跨角色持久化**，
--       那是另一整套存档结构与角色选择 UI；要做得先定「谁来持久化、存哪些角色」。
--     · DewDrop 右键配置菜单 —— 参考用它弹配置；本插件用 `/ebag` 命令 + 两个循环按钮覆盖同一批选项。
--
-- ★★★三条项目纪律在本文件里的落点：
--   1) 「一个模块只许一个节拍帧」⇒ 全文只有 B.tick 一个 OnUpdate，挂/摘走唯一入口 B.pumpSync。
--   2) 「注释绝不许与语句写在同一行」。
--   3) 「对象句柄守卫一律 isObj（table/userdata），绝不写 ~= nil」。
--
-- ★★★真机报障取证（用户 2026-10-05）：「背包按键能开、不能关」「银行背包没生效」「样式有问题」。
--   ① **不能关的真因**：客户端的切换逻辑问的是 `ContainerFrame1:IsShown()`，而我们把原生帧**藏了**
--      ⇒ 它**永远走「打开」分支** ⇒ 每次都调 Open* ⇒ 我们每次 show ⇒ 关不掉。
--      修法 = 「已经开着还收到一次『打开』⇒ 当成关闭」（intentOpen），并保留 B.trace 取证环。
--   ② 银行 = 参考的 OneBank 那套容器与事件（见上表 ③④）。
--   ③ 样式 = 每个格子补上**白框美术**（自带 `media\slotframe.tga`，照参考插件的白色圆角边框、
--      透明底）并按品质染色（旧版空格是纯黑方块）。
-- ============================================================

local B = {}
_G.EH_BAG = B

-- 构建标记（唯一来源）：改本文件顺手 +1，用于「客户端跑的是哪一份」取证
local BAG_BUILD = "0.3.32"

local function strVal(v)
  return tostring(v)
end

-- ===== 自带三语文案（自包含：主插件没载入也能正常显示）=====
local BAG_T = {
  zhCN = {
    TITLE = "背包",
    CAP_FMT = "%d/%d 背包 · 空 %d",
    MONEY_FMT = "",
    SEARCH = "搜索…",
    FILTER_TYPE = "类型: ",
    FILTER_QUAL = "品质: ",
    TYPE_ALL = "全部",
    TYPE_EQUIP = "装备",
    TYPE_CONSUME = "消耗品",
    TYPE_TRADE = "商品",
    TYPE_QUEST = "任务",
    TYPE_CONTAINER = "容器",
    TYPE_OTHER = "其它",
    TYPE_REAGENT = "材料",
    TYPE_PROJECTILE = "弹药",
    CAT_QUEST = "任务",
    CAT_EQUIP = "装备",
    CAT_CONSUME = "消耗品",
    CAT_TRADE = "商业技能",
    CAT_REAGENT = "材料",
    CAT_CONTAINER = "容器",
    CAT_PROJECTILE = "弹药",
    CAT_OTHER = "杂项",
    CAT_TIP_COUNT = "物品数量: %d",
    CAT_TIP_USE = "点击：筛选该类型",
    CAT_TIP_AGAIN = "再点：取消筛选",
    FILTER_NOW = "当前筛选: ",
    QUAL_ALL = "全部",
    QUAL_TIP_USE = "点击：只看这一档 · 再点一次：取消",
    QUAL_COMBINED = "普通/粗糙",
    MENU_BAGBREAK = "背包断行",
    MENU_VALIGN = "底部对齐",
    MENU_DIR = "背包顺序",
    DIR_FWD = "正序",
    DIR_REV = "倒序",
    QUAL0 = "粗糙",
    QUAL1 = "普通",
    QUAL2 = "优秀",
    QUAL3 = "精良",
    QUAL4 = "史诗",
    QUAL5 = "传说",
    QUAL6 = "神器",
    SORT = "整理",
    SORTING = "整理中…",
    HINT = "左键拾取/放下, 右键使用, Shift+左键: 聊天发送链接, Ctrl+左键 试穿, Shift+拖动 拆分",
    HINT_TITLE = "操作提示",
    BAG_TIP_FMT = "%s（%d 格）",
    BAG_TIP_USE = "左键：显示/隐藏这一包（并高亮它的格子） 拖物品到这里：放进这个包",
    BANK_TITLE = "银行",
    BANK_PANE = "银行主格",
    BANK_BAG_FMT = "银行包 %d",
    BANK_BAG_LOCKED = "银行包位 %d（未购买：去银行窗口买一格）",
    BANK_SLOTS_FMT = "银行包位 %d/%d · 下一格 %s",
    KEYRING = "钥匙链",
    KEYRING_TIP_FMT = "钥匙链（%d 格）",
    KEYRING_TIP_USE = "左键：显示/隐藏钥匙格 · 拖钥匙到这里：放进钥匙链",
    EMPTY = "空",
    TIP_COUNT = "数量: %d",
    CONFLICT = "检测到已载入的整合背包插件：%s —— 两套整合窗同开会互相打架，本次 EH_Bag 已自动让位（不接管背包、不碰原生容器帧）。请到插件列表里禁用其中一个，然后 /reload；或敲 /ebag force 让 EH_Bag 强行接管。",
    YIELD_CMD = "当前处于「让位」状态（检测到其它整合背包插件）。禁用它们并 /reload，或用 /ebag force 强行接管。",
    OFF = "EH_Bag 已关闭：原生背包恢复（/ebag on 打开）",
    ON = "EH_Bag 已打开",
    ENABLE_FIRST = "EH_Bag 当前是关闭状态：先 /ebag on（或在配置窗「子插件」里勾选 EH_Bag 后 /reload）",
    HELP_HINT = "背包窗已打开；/ebag help 看命令",
    SORT_BUSY = "整理已在进行中",
    SORT_COMBAT = "战斗中不整理（防止误操作与不必要的服务器写动作）",
    SORT_CURSOR = "光标上有物品，先放下再整理",
    SORT_NONE = "没有需要整理的东西",
    SORT_START = "开始整理：%d 件物品，预计 %d 步（每步 %.2fs，可随时再敲 /ebag sort 停止）",
    SORT_DONE = "整理完成：%d 步 / %.1fs",
    SORT_STOP = "整理已停止：%s（已走 %d 步）",
    SORT_STOP_CMD = "玩家手动停止",
    SORT_STOP_COMBAT = "进入战斗",
    SORT_STOP_CURSOR = "光标被占用",
    SORT_STOP_LOCKED = "物品被锁定",
    SORT_STOP_NOFREE = "所有背包一格空位都没有（整理需要空格做中转）",
    SORT_STOP_MOVES = "达到步数上限",
    SORT_STOP_TIMEOUT = "超时",
    SORT_STOP_GONE = "窗口被关闭",
    SPLIT_TITLE = "拆分数量",
    SPLIT_INFO = "%s（共 %d 个）",
    SPLIT_NOW = "移动数量",
    SPLIT_HALF = "一半",
    SPLIT_ALL = "全部",
    SPLIT_OK = "确定",
    SPLIT_SAY = "拆分：%s 移动 %d/%d 个",
    SPLIT_NOSPLIT = "拆分没成功（客户端没把物品放到光标上）—— 已如实收工，东西还在原格",
    SPLIT_STUCK = "拆分中断：光标上还有物品，已如实收工，请你手动放下（绝不清光标）",
    SPLIT_DRAG_TIP = "拖到同种物品上（或按住 Shift 拖）= 问你要移动几个",
    AUTO_ON = "已开启：打开银行/商贩/交易/拍卖时自动开背包窗",
    AUTO_OFF = "已关闭：不再自动开背包窗",
    PROBE_HEAD = "体检 构建 %s ｜ 开关 %s ｜ 让位 %s ｜ 接管 %s ｜ 窗口 %s ｜ 银行 %s ｜ 节拍 %s",
    TRACE_EMPTY = "（取证环是空的：先按几下背包键再来看）",
    TRACE_HEAD = "开合取证（%d 条，最新在后）",
    VIEW = "总览",
    OPT = "设置",
    VIEW_TITLE = "跨角色总览",
    VIEW_NONE = "存档里还没有任何角色快照（换角色登录一次就会记下）",
    VIEW_CHAR_FMT = "%s ｜ %s %s",
    VIEW_CAP_FMT = "已用 %d/%d 格 ｜ 物品 %d 件",
    VIEW_RO = "只读：这是别的角色的快照，拿不出来",
    VIEW_HINT = "左键 = 把物品链接插到聊天框",
    VIEW_SEC_BAG = "背包",
    VIEW_SEC_BANK = "银行",
    VIEW_MORE_FMT = "（窗内放不下，只显示 %d/%d 件）",
    BAGIDX_FMT = "背包 %d",
    ST_ON = "开",
    ST_OFF = "关",
    MENU_EDGES = "格框染品质",
    MENU_BAR = "背包条",
    MENU_COLS_FMT = "每行列数：%d",
    MENU_STATUS = "体检（写到聊天框）",
    MENU_SCALE = "界面缩放",
    MENU_SCALE_HINT = "%s%%（左键 +10%% · 右键 -10%%）",
    MENU_GAP = "整理步进",
    GAP_SLOW = "逐项",
    GAP_MID = "标准",
    GAP_FAST = "快",
    GAP_TURBO = "极快",
    MENU_VSIZE = "总览格子",
    VS_SMALL = "小",
    VS_MID = "中",
    VS_BIG = "大",
    MENU_TINT = "品质染色",
    TINT_STD = "标准",
    TINT_VIVID = "鲜丽",
    TINT_ULTRA = "极鲜",
    MENU_BG = "背景透明度",
MENU_CGAP = "格子间距",
    DEF_SAY_314 = "背包初始设置已更新：背包顺序=倒序 · 整理步进=快(0.2s) · 界面缩放=80% · 背包条=关 · 钥匙链=关（右键「设置」或 /ebag help 可随时改回）",
    MENU_WIN_CENTER = "窗口回到屏幕中间",
    WIN_CENTERED = "窗口已回到屏幕中间（%s）",
    SCALE_SAY = "界面缩放 = %s%%（重新载入后生效）",
    SCALE_ASK_TITLE = "界面缩放已改",
    SCALE_ASK_BODY = "背包界面缩放已改为 %s%%。现在就重新载入界面让它生效吗？",
    SCALE_ASK_MANUAL = "请手动 /reload 一次，让新缩放生效",
    AUTO_LABEL = "自动开窗",
    CHARS_HEAD = "跨角色快照（%d 个角色，最新在前）",
    CHARS_LINE = "%s ｜ 物品 %d 件 ｜ 等级 %s",
    SNAP_OK = "已记录本角色快照：%s",
    SNAP_FAIL = "跳过：拿不到角色名（快照不写一个字节）",
  },
  enUS = {
    TITLE = "Bags",
    CAP_FMT = "%d/%d bags · free %d",
    MONEY_FMT = "",
    SEARCH = "Search...",
    FILTER_TYPE = "Type: ",
    FILTER_QUAL = "Quality: ",
    TYPE_ALL = "All",
    TYPE_EQUIP = "Equip",
    TYPE_CONSUME = "Consumable",
    TYPE_TRADE = "Trade",
    TYPE_QUEST = "Quest",
    TYPE_CONTAINER = "Container",
    TYPE_OTHER = "Other",
    TYPE_REAGENT = "Reagent",
    TYPE_PROJECTILE = "Ammo",
    CAT_QUEST = "Quest",
    CAT_EQUIP = "Equipment",
    CAT_CONSUME = "Consumable",
    CAT_TRADE = "Trade skill",
    CAT_REAGENT = "Reagent",
    CAT_CONTAINER = "Container",
    CAT_PROJECTILE = "Ammo",
    CAT_OTHER = "Misc",
    CAT_TIP_COUNT = "Items: %d",
    CAT_TIP_USE = "Click: filter by this type",
    CAT_TIP_AGAIN = "Click again: clear",
    FILTER_NOW = "Filter: ",
    QUAL_ALL = "All",
    QUAL_TIP_USE = "Click: show only this quality - click again: clear",
    QUAL_COMBINED = "Common/Poor",
    MENU_BAGBREAK = "Break rows per bag",
    MENU_VALIGN = "Align to bottom",
    MENU_DIR = "Bag order",
    DIR_FWD = "Forward",
    DIR_REV = "Reverse",
    QUAL0 = "Poor",
    QUAL1 = "Common",
    QUAL2 = "Uncommon",
    QUAL3 = "Rare",
    QUAL4 = "Epic",
    QUAL5 = "Legendary",
    QUAL6 = "Artifact",
    SORT = "Sort",
    SORTING = "Sorting...",
    HINT = "Left: pick up/drop · Right: use · Shift+Left: link · Ctrl+Left: dress up · Shift+drag: split",
    HINT_TITLE = "Controls",
    BAG_TIP_FMT = "%s (%d slots)",
    BAG_TIP_USE = "Left: show/hide this bag (and highlight its slots) · Drop an item here: put it into this bag",
    BANK_TITLE = "Bank",
    BANK_PANE = "Bank pane",
    BANK_BAG_FMT = "Bank bag %d",
    BANK_BAG_LOCKED = "Bank bag %d (not purchased: buy one at the bank window)",
    BANK_SLOTS_FMT = "Bank bags %d/%d · next slot %s",
    KEYRING = "Keyring",
    KEYRING_TIP_FMT = "Keyring (%d slots)",
    KEYRING_TIP_USE = "Left: show/hide keys · Drop a key here: put it into the keyring",
    EMPTY = "Empty",
    TIP_COUNT = "Count: %d",
    CONFLICT = "Another merged-bag addon is loaded: %s -- two merged bag windows would fight each other, so EH_Bag yields this session (no bag takeover, native container frames untouched). Disable one of them and /reload, or type /ebag force to take over anyway.",
    YIELD_CMD = "Yielding (another merged-bag addon detected). Disable it and /reload, or use /ebag force.",
    OFF = "EH_Bag disabled: native bags restored (/ebag on to enable)",
    ON = "EH_Bag enabled",
    ENABLE_FIRST = "EH_Bag is currently off: use /ebag on (or tick EH_Bag in the config window's Plugins tab, then /reload)",
    HELP_HINT = "Bag window opened; /ebag help for commands",
    SORT_BUSY = "Sorting is already running",
    SORT_COMBAT = "Not sorting in combat (avoids mis-clicks and needless server writes)",
    SORT_CURSOR = "Something is on the cursor; drop it first",
    SORT_NONE = "Nothing to sort",
    SORT_START = "Sorting: %d items, about %d steps (%.2fs each; /ebag sort again to stop)",
    SORT_DONE = "Sort finished: %d steps / %.1fs",
    SORT_STOP = "Sort stopped: %s (after %d steps)",
    SORT_STOP_CMD = "stopped by player",
    SORT_STOP_COMBAT = "combat started",
    SORT_STOP_CURSOR = "cursor got occupied",
    SORT_STOP_LOCKED = "item locked",
    SORT_STOP_NOFREE = "no free slot in any bag (sorting needs one as a buffer)",
    SORT_STOP_MOVES = "step cap reached",
    SORT_STOP_TIMEOUT = "timed out",
    SORT_STOP_GONE = "window closed",
    SPLIT_TITLE = "Split stack",
    SPLIT_INFO = "%s (%d total)",
    SPLIT_NOW = "Amount",
    SPLIT_HALF = "Half",
    SPLIT_ALL = "All",
    SPLIT_OK = "OK",
    SPLIT_SAY = "Split: moving %d/%d of %s",
    SPLIT_NOSPLIT = "Split failed (the client did not put the items on the cursor) - nothing was changed, the stack is still in its slot",
    SPLIT_STUCK = "Split aborted: something is still on the cursor; please place it yourself (the cursor is never cleared)",
    SPLIT_DRAG_TIP = "Drop onto the same item (or hold Shift) to be asked how many to move",
    AUTO_ON = "Auto-open enabled: banks/merchants/trade/AH will open the bag window",
    AUTO_OFF = "Auto-open disabled",
    PROBE_HEAD = "probe build %s | on %s | yield %s | taking over %s | window %s | bank %s | tick %s",
    TRACE_EMPTY = "(trace ring is empty: press the bag key a few times first)",
    TRACE_HEAD = "open/close trace (%d entries, newest last)",
    VIEW = "Overview",
    OPT = "Options",
    VIEW_TITLE = "All characters",
    VIEW_NONE = "No character snapshots yet (log in with another character once)",
    VIEW_CHAR_FMT = "%s | %s %s",
    VIEW_CAP_FMT = "used %d/%d | items %d",
    VIEW_RO = "Read-only: another character's snapshot, cannot be taken",
    VIEW_HINT = "Left click = insert the item link into chat",
    VIEW_SEC_BAG = "Bags",
    VIEW_SEC_BANK = "Bank",
    VIEW_MORE_FMT = " (window fits only %d/%d)",
    BAGIDX_FMT = "Bag %d",
    ST_ON = "on",
    ST_OFF = "off",
    MENU_EDGES = "Quality borders",
    MENU_BAR = "Bag bar",
    MENU_COLS_FMT = "Columns: %d",
    MENU_STATUS = "Probe (prints to chat)",
    MENU_SCALE = "UI scale",
    MENU_SCALE_HINT = "%s%% (left-click +10%%, right-click -10%%)",
    MENU_GAP = "Sort step",
    GAP_SLOW = "one by one",
    GAP_MID = "normal",
    GAP_FAST = "fast",
    GAP_TURBO = "very fast",
    MENU_VSIZE = "Overview cell",
    VS_SMALL = "small",
    VS_MID = "medium",
    VS_BIG = "large",
    MENU_TINT = "Quality tint",
    TINT_STD = "Standard",
    TINT_VIVID = "Vivid",
    TINT_ULTRA = "Ultra",
    MENU_BG = "Background opacity",
MENU_CGAP = "Slot spacing",
    DEF_SAY_314 = "Bag defaults updated: order=reversed · sort step=fast(0.2s) · UI scale=80% · bag bar=off · keyring=off (right-click Settings or /ebag help to change back)",
    MENU_WIN_CENTER = "Center window on screen",
    WIN_CENTERED = "Window centered on screen (%s)",
    SCALE_SAY = "UI scale = %s%% (takes effect after reload)",
    SCALE_ASK_TITLE = "UI scale changed",
    SCALE_ASK_BODY = "Bag UI scale is now %s%%. Reload the UI now?",
    SCALE_ASK_MANUAL = "Please /reload once to apply the new scale",
    AUTO_LABEL = "Auto open",
    CHARS_HEAD = "Character snapshots (%d, newest first)",
    CHARS_LINE = "%s | items %d | level %s",
    SNAP_OK = "Snapshot recorded for this character: %s",
    SNAP_FAIL = "Skipped: no character name (nothing written)",
  },
  ruRU = {
    TITLE = "Сумки",
    CAP_FMT = "%d/%d сумки · свободно %d",
    MONEY_FMT = "",
    SEARCH = "Поиск...",
    FILTER_TYPE = "Тип: ",
    FILTER_QUAL = "Качество: ",
    TYPE_ALL = "Все",
    TYPE_EQUIP = "Снаряжение",
    TYPE_CONSUME = "Расходники",
    TYPE_TRADE = "Товары",
    TYPE_QUEST = "Задания",
    TYPE_CONTAINER = "Контейнер",
    TYPE_OTHER = "Прочее",
    TYPE_REAGENT = "Реагент",
    TYPE_PROJECTILE = "Боеприпасы",
    CAT_QUEST = "Задания",
    CAT_EQUIP = "Снаряжение",
    CAT_CONSUME = "Расходники",
    CAT_TRADE = "Профессии",
    CAT_REAGENT = "Реагенты",
    CAT_CONTAINER = "Контейнер",
    CAT_PROJECTILE = "Боеприпасы",
    CAT_OTHER = "Прочее",
    CAT_TIP_COUNT = "Предметов: %d",
    CAT_TIP_USE = "ЛКМ: фильтр по этому типу",
    CAT_TIP_AGAIN = "Ещё раз: сброс",
    FILTER_NOW = "Фильтр: ",
    QUAL_ALL = "Все",
    QUAL_TIP_USE = "ЛКМ: только это качество - ещё раз: сброс",
    QUAL_COMBINED = "Обычное/Хлам",
    MENU_BAGBREAK = "Разрыв строк по сумкам",
    MENU_VALIGN = "Выравнивание по низу",
    MENU_DIR = "Порядок сумок",
    DIR_FWD = "Прямой",
    DIR_REV = "Обратный",
    QUAL0 = "Хлам",
    QUAL1 = "Обычное",
    QUAL2 = "Необычное",
    QUAL3 = "Редкое",
    QUAL4 = "Эпическое",
    QUAL5 = "Легендарное",
    QUAL6 = "Артефакт",
    SORT = "Сортировать",
    SORTING = "Сортировка...",
    HINT = "ЛКМ: взять/положить · ПКМ: использовать · Shift+ЛКМ: ссылка · Ctrl+ЛКМ: примерка · Shift+перетаскивание: разделить",
    HINT_TITLE = "Управление",
    BAG_TIP_FMT = "%s (%d ячеек)",
    BAG_TIP_USE = "ЛКМ: показать/скрыть сумку (и подсветить её ячейки) · Перетащите предмет сюда: положить в эту сумку",
    BANK_TITLE = "Банк",
    BANK_PANE = "Ячейки банка",
    BANK_BAG_FMT = "Сумка банка %d",
    BANK_BAG_LOCKED = "Ячейка банка %d (не куплена: купите в окне банка)",
    BANK_SLOTS_FMT = "Сумки банка %d/%d · следующая ячейка %s",
    KEYRING = "Связка ключей",
    KEYRING_TIP_FMT = "Связка ключей (%d ячеек)",
    KEYRING_TIP_USE = "ЛКМ: показать/скрыть ключи · Перетащите ключ сюда",
    EMPTY = "Пусто",
    TIP_COUNT = "Количество: %d",
    CONFLICT = "Обнаружен другой аддон объединённых сумок: %s -- два таких окна мешают друг другу, поэтому EH_Bag уступает (не перехватывает сумки и не трогает родные фреймы). Отключите один из них и сделайте /reload, либо введите /ebag force.",
    YIELD_CMD = "Режим уступки (обнаружен другой аддон сумок). Отключите его и /reload, либо /ebag force.",
    OFF = "EH_Bag выключен: родные сумки восстановлены (/ebag on — включить)",
    ON = "EH_Bag включён",
    ENABLE_FIRST = "EH_Bag сейчас выключен: введите /ebag on (или включите EH_Bag во вкладке суб-аддонов и сделайте /reload)",
    HELP_HINT = "Окно сумок открыто; /ebag help — команды",
    SORT_BUSY = "Сортировка уже идёт",
    SORT_COMBAT = "В бою не сортируем (во избежание ошибок и лишних записей на сервер)",
    SORT_CURSOR = "На курсоре предмет; сначала положите его",
    SORT_NONE = "Нечего сортировать",
    SORT_START = "Сортировка: %d предметов, около %d шагов (%.2fс каждый; /ebag sort — остановить)",
    SORT_DONE = "Сортировка завершена: %d шагов / %.1fс",
    SORT_STOP = "Сортировка остановлена: %s (после %d шагов)",
    SORT_STOP_CMD = "остановлено игроком",
    SORT_STOP_COMBAT = "начался бой",
    SORT_STOP_CURSOR = "курсор занят",
    SORT_STOP_LOCKED = "предмет заблокирован",
    SORT_STOP_NOFREE = "во всех сумках нет ни одной свободной ячейки (для сортировки нужен буфер)",
    SORT_STOP_MOVES = "достигнут лимит шагов",
    SORT_STOP_TIMEOUT = "таймаут",
    SORT_STOP_GONE = "окно закрыто",
    SPLIT_TITLE = "Разделить стопку",
    SPLIT_INFO = "%s (всего %d)",
    SPLIT_NOW = "Количество",
    SPLIT_HALF = "Половина",
    SPLIT_ALL = "Всё",
    SPLIT_OK = "OK",
    SPLIT_SAY = "Разделение: перенос %d/%d — %s",
    SPLIT_NOSPLIT = "Разделить не удалось (клиент не положил предметы на курсор) — ничего не изменено, стопка на месте",
    SPLIT_STUCK = "Разделение прервано: на курсоре остались предметы; поставьте их сами (курсор никогда не очищается)",
    SPLIT_DRAG_TIP = "Бросьте на такой же предмет (или удерживайте Shift), чтобы задать количество",
    AUTO_ON = "Автооткрытие включено: банк/торговец/обмен/аукцион откроют окно сумок",
    AUTO_OFF = "Автооткрытие выключено",
    PROBE_HEAD = "проверка сборка %s | вкл %s | уступка %s | перехват %s | окно %s | банк %s | тик %s",
    TRACE_EMPTY = "(кольцо трассировки пусто: сначала понажимайте клавишу сумок)",
    TRACE_HEAD = "трассировка открытия/закрытия (%d записей, новые в конце)",
    VIEW = "Обзор",
    OPT = "Настройки",
    VIEW_TITLE = "Все персонажи",
    VIEW_NONE = "Снимков персонажей пока нет (зайдите другим персонажем один раз)",
    VIEW_CHAR_FMT = "%s | %s %s",
    VIEW_CAP_FMT = "занято %d/%d | предметов %d",
    VIEW_RO = "Только чтение: это снимок другого персонажа",
    VIEW_HINT = "ЛКМ = вставить ссылку на предмет в чат",
    VIEW_SEC_BAG = "Сумки",
    VIEW_SEC_BANK = "Банк",
    VIEW_MORE_FMT = " (в окно влезло только %d/%d)",
    BAGIDX_FMT = "Сумка %d",
    ST_ON = "вкл",
    ST_OFF = "выкл",
    MENU_EDGES = "Рамки по качеству",
    MENU_BAR = "Панель сумок",
    MENU_COLS_FMT = "Столбцов: %d",
    MENU_STATUS = "Проверка (в чат)",
    MENU_SCALE = "Масштаб интерфейса",
    MENU_SCALE_HINT = "%s%% (ЛКМ +10%%, ПКМ -10%%)",
    MENU_GAP = "Шаг сортировки",
    GAP_SLOW = "по одному",
    GAP_MID = "обычно",
    GAP_FAST = "быстро",
    GAP_TURBO = "очень быстро",
    MENU_VSIZE = "Ячейка обзора",
    VS_SMALL = "мелкая",
    VS_MID = "средняя",
    VS_BIG = "крупная",
    MENU_TINT = "Окраска качества",
    TINT_STD = "Стандарт",
    TINT_VIVID = "Яркая",
    TINT_ULTRA = "Максимум",
    MENU_BG = "Прозрачность фона",
MENU_CGAP = "Интервал ячеек",
    DEF_SAY_314 = "Настройки сумок обновлены: порядок=обратный · шаг сортировки=быстро(0.2с) · масштаб=80% · панель сумок=выкл · кольцо ключей=выкл (правый клик «Настройки» или /ebag help)",
    MENU_WIN_CENTER = "Окно в центр экрана",
    WIN_CENTERED = "Окно возвращено в центр экрана (%s)",
    SCALE_SAY = "Масштаб интерфейса = %s%% (после перезагрузки)",
    SCALE_ASK_TITLE = "Масштаб изменён",
    SCALE_ASK_BODY = "Масштаб сумок теперь %s%%. Перезагрузить интерфейс?",
    SCALE_ASK_MANUAL = "Сделайте /reload, чтобы применить масштаб",
    AUTO_LABEL = "Автооткрытие",
    CHARS_HEAD = "Снимки персонажей (%d, новые первыми)",
    CHARS_LINE = "%s | предметов %d | уровень %s",
    SNAP_OK = "Снимок этого персонажа записан: %s",
    SNAP_FAIL = "Пропущено: нет имени персонажа (ничего не записано)",
  },
}

local function bagLocale()
  local loc = "zhCN"
  if type(GetLocale) == "function" then
    local ok, v = pcall(GetLocale)
    if ok and type(v) == "string" and v ~= "" then loc = v end
  end
  if BAG_T[loc] == nil then loc = "enUS" end
  return loc
end

B.loc = bagLocale()

local function L(key, ...)
  local t = BAG_T[B.loc] or BAG_T.zhCN
  local s = t[key]
  if s == nil then s = BAG_T.zhCN[key] end
  if s == nil then return strVal(key) end
  if select("#", ...) == 0 then return s end
  local ok, f = pcall(string.format, s, ...)
  if ok and type(f) == "string" then return f end
  return s
end

-- ===== 说话出口 =====
-- ★分档（项目纪律 1.75.59f）：自动播报受主插件「调试日志」闸门管；
--   玩家主动敲命令的回显、以及「让位」这类必须看见的结论走强制可见口。
local function rawSay(msg)
  if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, "|cff66ccff[EH_Bag]|r " .. strVal(msg))
  end
end

local function say(msg)
  local text = "[EH_Bag] " .. strVal(msg)
  if type(EVAL_SAY) == "function" then
    local ok = pcall(EVAL_SAY, text)
    if ok then
      B.traceAdd("say", tostring(msg))
      return
    end
  end
  rawSay(msg)
end

local function sayForce(msg)
  local text = "[EH_Bag] " .. strVal(msg)
  if type(EVAL_SAY_FORCE) == "function" then
    local ok = pcall(EVAL_SAY_FORCE, text)
    if ok then
      B.traceAdd("sayF", tostring(msg))
      return
    end
  end
  rawSay(msg)
end

B.say = say
B.sayForce = sayForce
B.L = L

-- ===== 配置（SavedVariables，见 EH_Bag.toc）=====
local DEF = {
  cols = 12,
  cell = 37,
  gap = 4,
  -- ★★★0.3.14：**默认关**（用户：「背包的初始设置参考第三张图片」= 那一行写着「背包条：关」）。
  --   ★读口口径 = **只有显式 true 才是开**（`B.barSync` / 菜单行都判 `c.bar == true`）——
  --   缺键一律按关（绝不用 `~= false` 那种「nil 也算开」的写法，那正是旧版把默认值当成死键的坑）。
  bar = false,
  edges = true,
  dim = 0.25,
  -- ★★★0.3.14：整理步进默认档 **0.20s（快）** —— 用户「背包的初始设置参考第三张图片」
  --   （第三张图那一行是「整理步进：0.2s（快）」）。★0.3.11 那条「0.20 ⇒ 升回 0.45」的迁移
  --   **整条撤掉**（留着它会把新默认档当场顶回 0.45），改成反向迁移，见 `B.cfg()`。
  moveGap = 0.20,
  autoShow = true,
  -- ★★★0.3.14：界面缩放默认 **80%**（第三张图：「界面缩放：80%」）—— `B.z()` 的坏数据回落也读它。
  scale = 0.80,
  -- ★0.3.12：总览格子档位系数（0.8 = 小 / 0.9 = 中 / 1.0 = 大）。缺键/坏数据一律按**小**（B.vsizeIdx 兜底）。
  vsize = 0.80,
  -- ★0.3.13：品质染色浓淡档位（**存档里存的是档位序号** 1/2/3，与 `B.TINTS` 同序）。
  --   **默认档 = 2 = 鲜丽**（用户：「装备染色还不够亮眼.需要更加鲜丽的颜色」）——
  --   ★**默认档只在 DEF 写一次**，`B.tintIdx()` 的坏数据回落也读它（绝不两处各写一个 2）。
  tint = 2,
  -- ★0.3.14：窗背景透明度（用户：「背包背景透明度参考第二张图片的背景透明度」——
  --   第二张图是参考插件 OneBag，它源码里的默认就是 `SetBackdropColor(0, 0, 0, .45)`）⇒ 取 **0.45**。
  --   唯一读口 `B.bgK()`、唯一写口 `B.bgSet()`、唯一应用口 `B.bgApply()`（三处共用这一个数）。
  bgAlpha = 0.45,
  -- ★0.3.14：背包顺序默认 **倒序**（第三张图：「背包顺序：倒序」）；
  --   ★只有**缺键**才算「没选过」⇒ 落到新默认；显式写过 `"fwd"`（玩家自己选的正序）一个字节都不动。
  direction = "rev",
}

-- 整理步进的合法区间（唯一来源；`B.cfg()` 夹取 + `/ebag gap` 写口都读它）——
-- ★下限的意义 = 「坏存档/手改存档不许把我们拖成每帧几十次写动作」（项目频率防护铁律）。
B.MOVEGAP_MIN = 0.10
B.MOVEGAP_MAX = 2.00

function B.cfg()
  if type(EH_BAG_CFG) ~= "table" then
    EH_BAG_CFG = {}
  end
  local c = EH_BAG_CFG
  if c.on == nil then
    c.on = true
  end
  if type(c.show) ~= "table" then
    c.show = {}
  end
  if type(c.cols) ~= "number" then c.cols = DEF.cols end
  if type(c.moveGap) ~= "number" then c.moveGap = DEF.moveGap end
  -- ★★★0.3.14 整理步进默认档 **0.45 → 0.20**（用户：「背包的初始设置参考第三张图片」= 0.2s（快））：
  --   反过来迁移 —— 老存档里的 `0.45` **只可能**是 0.3.11~0.3.13 我替用户选的默认档
  --   （`B.gapSet()` **每次**都写 `moveGapMigrated = true`，而全项目写 `moveGap` 只有它一个口）
  --   ⇒ 没打过标记的 0.45 一次性升成新默认（0.20）；**玩家自己调过的任何值一个字节都不动**。
  --   ★0.3.11 那条「0.20 ⇒ 0.45」的旧迁移**已整条删除**（留着会把新默认档当场顶回去）。
  if c.moveGap == 0.45 and c.moveGapMigrated ~= true then
    c.moveGap = DEF.moveGap
    c.moveGapMigrated = true
  end
  -- ★下限夹取（不信存档）：坏数据/手改存档不许把我们拖成「一帧几十次写动作」
  if c.moveGap < B.MOVEGAP_MIN then c.moveGap = B.MOVEGAP_MIN end
  if c.autoShow == nil then c.autoShow = DEF.autoShow end
  -- ★0.3.13 品质染色档位：缺键/坏数据（含字符串、越界）一律落成默认档（DEF.tint = 鲜丽）——
  --   `B.tintIdx()` 自己也会回落，这里只负责把「存档里那个坏值」当场纠正成合法序号。
  if type(c.tint) ~= "number" then c.tint = DEF.tint end
  -- ★0.3.14 背包顺序：**只有缺键**才落新默认（倒序）；显式 `"fwd"`（玩家选过的正序）原样保留。
  if c.direction ~= "fwd" and c.direction ~= "rev" then c.direction = DEF.direction end
  -- ★0.3.14 背景透明度：坏数据（字符串/越界）当场纠正成默认档；合法值原样（不夹到档位上 —— 玩家手调的值要尊重）。
  local bg = c.bgAlpha
  if type(bg) ~= "number" or bg < 0 or bg > 1 then c.bgAlpha = DEF.bgAlpha end
  return c
end

local function enabled()
  return B.cfg().on == true
end

-- 是否真的在接管：开着 + 没让位
function B.active()
  return enabled() and (B.yield ~= true)
end

local function bagShown(bag)
  local c = B.cfg()
  local v = c.show[bag]
  if v == nil then
    -- ★★★0.3.14：**钥匙链默认关**（用户：「背包的初始设置参考第三张图片」= 那一行写着「钥匙链：关」）。
    --   背包 0~4 与银行包照旧默认开；★只认**显式 false**（玩家点过）= 关，缺键按上面这条默认走。
    return bag ~= B.KEYRING
  end
  return v and true or false
end

B.bagShown = bagShown

-- ★对象守卫（项目 idiom）：宽容桩对「没设过的字段」会返回函数值 ⇒ 绝不写 `~= nil`
local function isObj(o)
  local t = type(o)
  return t == "table" or t == "userdata"
end

B.isObj = isObj

-- ===== 取证环（有界 30 条，落存档 ⇒ AI 能读「按键到底调了哪个函数」）=====
function B.traceAdd(name, extra)
  local c = B.cfg()
  if type(c.trace) ~= "table" then c.trace = {} end
  local t = c.trace
  local vis = "0"
  if B.visible == true then vis = "1" end
  local bk = "0"
  if B.bankOpen == true then bk = "1" end
  table.insert(t, string.format("%s %s [vis=%s bank=%s]", strVal(name), strVal(extra or ""), vis, bk))
  while table.getn(t) > 30 do
    table.remove(t, 1)
  end
end

-- ===== 容器（唯一来源：谁是背包、谁是银行、谁是钥匙链）=====
B.KEYRING = (type(KEYRING_CONTAINER) == "number") and KEYRING_CONTAINER or -2
B.BANK = (type(BANK_CONTAINER) == "number") and BANK_CONTAINER or -1
B.BAGS = { 0, 1, 2, 3, 4 }
B.BANKBAGS = { 5, 6, 7, 8, 9, 10 }
B.BANK_PANE_SLOTS = 24

local function bagSlotsRaw(bag)
  if type(GetContainerNumSlots) ~= "function" then return 0 end
  local ok, n = pcall(GetContainerNumSlots, bag)
  if ok and type(n) == "number" and n > 0 then return n end
  return 0
end

local function keyringSize()
  if type(GetKeyRingSize) == "function" then
    local ok, n = pcall(GetKeyRingSize)
    if ok and type(n) == "number" and n > 0 then return n end
  end
  return bagSlotsRaw(B.KEYRING)
end

-- ★跨文件共用口（EH_BagSort.lua 是另一个 chunk，读不到本文件的 local）
function B.bagSlots(bag)
  if bag == B.BANK then
    -- 银行主格：只有银行开着才有内容（客户端固定 24 格）
    if B.bankOpen ~= true then return 0 end
    return B.BANK_PANE_SLOTS
  end
  if bag == B.KEYRING then
    if bagShown(B.KEYRING) == false then return 0 end
    return keyringSize()
  end
  if bagShown(bag) == false then return 0 end
  return bagSlotsRaw(bag)
end

-- ★★物理格数（**不看显示开关**）：整理引擎要它 —— 「收起」只影响**看不看得见**，
--   不影响「这一格还存不存在、能不能放东西」（用户报「在有空格的情况下会提示空位不足」的修法）。
B.bagSlotsRaw = bagSlotsRaw

-- 当前窗口该显示哪些容器（顺序 = 显示顺序）
function B.containers()
  local out = {}
  local i
  for i = 1, table.getn(B.BAGS) do
    table.insert(out, B.BAGS[i])
  end
  if bagShown(B.KEYRING) and keyringSize() > 0 then
    table.insert(out, B.KEYRING)
  end
  if B.bankOpen == true then
    table.insert(out, B.BANK)
    for i = 1, table.getn(B.BANKBAGS) do
      table.insert(out, B.BANKBAGS[i])
    end
  end
  return out
end

function B.isBankContainer(bag)
  if bag == B.BANK then return true end
  local i
  for i = 1, table.getn(B.BANKBAGS) do
    if B.BANKBAGS[i] == bag then return true end
  end
  return false
end

-- ===== 界面缩放（0.3.3）=====
-- ★★ 缩放一律走**几何重建**，绝不用 SetScale —— 本客户端 SetScale 会让点击框漂移（项目在案）。
--   唯一真值 c.scale（0.7~1.5，0.1 一档，默认 1）；B.z() 现算，B.build / B.layout / B.buildView /
--   B.buildMenu 全乘这个系数；字体在 font() 里按同一系数重设字号。
--   改了缩放 ⇒ 提示 /reload（窗件建一次就常驻，1.12 没有销毁帧的 API ⇒ 重载才是唯一干净的重建路）。
--   ★数值类区间 50%~120%、递步 10%（用户定：「界面缩放需要能否支持数值类调整区间50-120,递步10」）
B.SCALE_MIN = 0.5
B.SCALE_MAX = 1.2
B.SCALE_STEP = 0.1

function B.z()
  local v = B.cfg().scale
  -- ★0.3.14：坏数据/缺键一律回到**默认档 `DEF.scale`（80%）**—— 旧写法退回 1（100%）。
  --   ★同一个数只写一次（DEF），这里绝不另写一个字面量。
  if type(v) ~= "number" then v = DEF.scale end
  if v < B.SCALE_MIN then v = B.SCALE_MIN end
  if v > B.SCALE_MAX then v = B.SCALE_MAX end
  return v
end

-- ===== 窗背景透明度（0.3.14；用户：「背包背景透明度参考第二张图片的背景透明度」）=====
--   ★参考插件 OneBag 源码里的默认就是 `SetBackdropColor(0, 0, 0, .45)` ⇒ 我们取 **0.45**（唯一来源 `DEF.bgAlpha`）。
--   ★★★三个唯一：**读口** `B.bgK()`（自己夹取、坏数据退默认档）/ **写口** `B.bgSet(v)`（菜单「背景透明度」行
--     与 `/ebag alpha` 共用）/ **应用口** `B.bgApply()`（窗背板 + 格子中性底色，一处算完 —— 散在两处就是下一个漏改点）。
--   ★★**绝不用 `SetAlpha(窗帧)`**：那会把图标、文字、格子一起变淡；用户要的是「**背景**透明」
--     （第二张图里道具图标是不透明的，透出来的只有窗底与空格）。
B.BG_MIN = 0
B.BG_MAX = 100
-- 菜单行点一下走一档（与 `/ebag alpha` 同一个写口；手调过的怪值 ⇒ 循环一律回第一档，口径同 B.GAP_CYCLE）
B.BG_LEVELS = { 100, 85, 70, 55, 45, 30, 15, 0 }

B.bgK = function()
  local v = B.cfg().bgAlpha
  if type(v) ~= "number" or v < 0 or v > 1 then v = DEF.bgAlpha end
  return v
end

B.bgPct = function()
  return math.floor(B.bgK() * 100 + 0.5)
end

B.bgText = function()
  return strVal(B.bgPct()) .. "%"
end

-- ★唯一应用口：窗背板（两条建成路各自兑现：SetBackdrop 那条 / 自建 bg 纹理那条）+ 格子中性底色
function B.bgApply()
  local a = B.bgK()
  local f = B.ui.frame
  if isObj(f) then
    if type(f.SetBackdropColor) == "function" then
      pcall(f.SetBackdropColor, f, 0.03, 0.03, 0.03, a)
    end
    if isObj(f.ehBg) then pcall(f.ehBg.SetAlpha, f.ehBg, a) end
  end
  -- ★0.3.17：总览窗同一把尺子（两条建成路各自兑现；句柄没建出来就跳过 —— fail-open）
  local vf = B.ui.viewFrame
  if isObj(vf) then
    if type(vf.SetBackdropColor) == "function" then
      pcall(vf.SetBackdropColor, vf, 0.03, 0.03, 0.03, a)
    end
    if isObj(vf.ehVBg) then pcall(vf.ehVBg.SetAlpha, vf.ehVBg, a) end
  end
  -- 格子的中性底色（空格 / 白装 / 悬停 / 关掉染色）跟着走；唯一绘制口在 paintButton，这里只是重画一趟
  if type(B.refreshAll) == "function" then B.refreshAll() end
end

-- ★唯一写口：认百分数（`alpha 45`）也认小数（`alpha 0.45`）；无参数 = 只读播报（活口）；坏输入 ⇒ 一个字节都不动
B.bgSet = function(v)
  local n = tonumber(v)
  if n == nil then
    sayForce(L("MENU_BG") .. " = " .. B.bgText() .. "（0~100 的百分数，或 /ebag alpha 0.45）")
    return
  end
  if n > 1 then n = n / 100 end
  if n < 0 then n = 0 end
  if n > 1 then n = 1 end
  n = math.floor(n * 100 + 0.5) / 100
  B.cfg().bgAlpha = n
  B.bgApply()
  sayForce(L("MENU_BG") .. " = " .. B.bgText())
end

B.bgCycle = function()
  local n = table.getn(B.BG_LEVELS)
  local cur = B.bgPct()
  local i
  for i = 1, n do
    if B.BG_LEVELS[i] == cur then
      B.bgSet(B.BG_LEVELS[(i % n) + 1])
      return
    end
  end
  B.bgSet(B.BG_LEVELS[1])
end

-- ★★★0.3.31g 格子边距（格子与格子之间的间距，用户：「增加个格子边距的参数.我微调下.」）：
--   **三个唯一**：读口 `B.cgap()`（自己夹取 0~16 + 坏数据退 `DEF.gap` = 4）· 写口 `B.cgapSet(v)`
--   （认数字 0~16；**无参数 = 只读播报** = 活口；坏输入一个字节都不动）· 布局 `B.layout()` 只读这一个口。
--   ★存档键 = `c.gap`（0.3.0 起就有的**休眠键**：一直有读没有写 —— 本次给它接上写口）；老存档没这键 ⇒ 默认 4，零迁移。
--   ★单位 = **未缩放像素**（与 `c.cell` 同口径；布局里再乘 z —— 改界面缩放时间距按比例走，与现状一致）。
--   ★作用面 = 只影响**主背包网格**（x/y 步进 · 行数 · 网格宽高 ⇒ 窗口宽高跟着走）；
--     左侧背包条排距（`barCell + 4*z`）与跨角色总览间距**各走各的尺子，不碰**。
B.CGAP_MIN, B.CGAP_MAX = 0, 16
B.cgap = function()
  local v = tonumber(B.cfg().gap)
  if v == nil then return DEF.gap end
  if v < B.CGAP_MIN then return B.CGAP_MIN end
  if v > B.CGAP_MAX then return B.CGAP_MAX end
  return v
end
B.cgapSet = function(v)
  local n = tonumber(v)
  if n == nil then
    sayForce("格子间距 = " .. strVal(B.cgap()) .. "px（用法 /ebag cgap 0~16；0 = 格子紧贴）")
    return false
  end
  if n < B.CGAP_MIN then n = B.CGAP_MIN end
  if n > B.CGAP_MAX then n = B.CGAP_MAX end
  B.cfg().gap = n
  B.ui.needLayout = true
  B.layout()
  if type(B.refreshAll) == "function" then B.refreshAll() end
  sayForce("格子间距 = " .. strVal(n) .. "px（/ebag cgap 0~16；0 = 格子紧贴）")
  return true
end

-- ★菜单行「格子间距」与 `/ebag cgap` 共用的循环口（与 `B.bgCycle` 同一配方；手调怪值 ⇒ 循环一律回第一档）
B.CGAP_LEVELS = { 0,1,2, 4 }
B.cgapCycle = function()
  local n = table.getn(B.CGAP_LEVELS)
  local cur = B.cgap()
  local i
  for i = 1, n do
    if B.CGAP_LEVELS[i] == cur then
      B.cgapSet(B.CGAP_LEVELS[(i % n) + 1])
      return
    end
  end
  B.cgapSet(B.CGAP_LEVELS[1])
end

-- 背包条按钮边长（base = 总览里的物品图标大小；用户点名「大小跟总览内的物品图标相同」）
B.BARCELL = 30

-- ★★格子图标的缩放系数（唯一来源）：图标 = 格子边长 × 这个系数、**居中**。
--   旧写法把图标铺满整格（TOPLEFT/BOTTOMRIGHT 各内缩 3px）⇒ 把经典格框那圈环整个盖住
--   （用户报「装备物品图标能否小一点.居中框对齐」）。总览格子与背包格子共用这一个系数。
--   ★历史：0.3.5 = 0.86 → 0.3.6 = 0.75（用户：「背包的物品图标小一点」）—— 那两版都是**用缩小图标**
--     来「让环露出来」，代价是图标明显小于格框（用户 0.3.9 报「物品图标和物品背景的框大小不匹配」）。
--   ★★★0.3.9 起 = **1（图标 = 整格）+ 把格框画到图标之上** —— 这才是客户端自己的口径：
--     客户端 `ItemButtonTemplate.xml`：按钮 37×37 · `$parentIconTexture` 铺满整格（BORDER 层）·
--     `$parentNormalTexture` = `UI-Quickslot2` **64×64 居中**（那张图里环只有中央 ≈37px ⇒ 环的可见
--     尺寸正好 = 整格）⇒ 原生观感 = **图标填满格位、那一圈环压在图标边缘**（不是把图标缩小）。
--   ★★★0.3.11 再改一次（用户：「物品稀有等级染色颜色高亮点.是否本身图标遮盖了染色边框.
--     图标是否可以小一点点」）：0.3.9 的「图标 = 整格」在本客户端**把整格底色（品质染色）整块盖住**了
--     —— 底色那一层是 `BACKGROUND`（见 newItemButton 的 `ehFill`），图标铺满整格 ⇒ 屏上只剩图标，
--     染出来的品质色只在**格与格之间的缝**里露一点点（用户看到的「染色被图标遮住」）。
--     ⇒ 图标收到 **0.9**：四周各让出半格 5% 的宽边，**品质底色与格框环当场露出来**，
--     而图标本身仍然基本铺满（不是 0.75/0.86 那种「明显小一圈」）。
B.ICON_K = 0.9

function B.scalePct()
  return strVal(math.floor(B.z() * 100 + 0.5))
end

function B.scaleAskReload()
  local ask = _G.EVAL_RELOAD_ASK
  if type(ask) == "function" then
    pcall(ask, L("SCALE_ASK_TITLE"), L("SCALE_ASK_BODY", B.scalePct()))
  else
    sayForce(L("SCALE_ASK_MANUAL"))
  end
end

function B.scaleSet(v)
  local n = tonumber(v)
  if n == nil then n = 1 end
  -- ★数值类入口**认百分数也认小数**（/ebag scale 85 = 0.85；/ebag scale 0.85 同样认）
  if n > 2 then n = n / 100 end
  if n < B.SCALE_MIN then n = B.SCALE_MIN end
  if n > B.SCALE_MAX then n = B.SCALE_MAX end
  n = math.floor(n * 10 + 0.5) / 10
  local c = B.cfg()
  if c.scale == n then
    sayForce(L("SCALE_SAY", B.scalePct()))
    return
  end
  c.scale = n
  B.traceAdd("scale", strVal(n))
  sayForce(L("SCALE_SAY", B.scalePct()))
  B.scaleAskReload()
end

-- 缩放上下调一档（菜单行「界面缩放」：左键 +10% / 右键 −10%）。
-- ★到顶/到底**夹住**，不再回绕（旧写法到顶回最低 ⇒ 用户按两下会莫名其妙跳到 50%）
function B.scaleStepBy(dir)
  local n = B.z()
  if dir == -1 then n = n - B.SCALE_STEP else n = n + B.SCALE_STEP end
  if n < B.SCALE_MIN then n = B.SCALE_MIN end
  if n > B.SCALE_MAX then n = B.SCALE_MAX end
  B.scaleSet(n)
end

function B.scaleCycle()
  B.scaleStepBy(1)
end

-- ★★★0.3.11 命名档位（**唯一来源**）：`/ebag gap 逐项|标准|快` 与设置菜单「整理步进」循环档
--   都读这一张表 —— 两处各写一份就是下一个漏改点。数值仍受 `B.MOVEGAP_MIN/MAX` 夹取（见 B.gapSet）。
B.GAP_WORDS = { ["逐项"] = 0.45, ["标准"] = 0.30, ["快"] = 0.20, ["极快"] = 0.12 }
B.GAP_CYCLE = { 0.45, 0.30, 0.20, 0.12 }

-- 当前档位的「人话」描述（菜单行与播报共用同一份口径）
B.gapText = function()
  local g = tonumber(B.cfg().moveGap) or DEF.moveGap
  local name = nil
  if math.abs(g - 0.45) < 0.005 then name = L("GAP_SLOW")
  elseif math.abs(g - 0.30) < 0.005 then name = L("GAP_MID")
  elseif math.abs(g - 0.20) < 0.005 then name = L("GAP_FAST")
  elseif g <= 0.15 then name = L("GAP_TURBO") end
  return strVal(g) .. "s" .. ((name ~= nil) and ("（" .. name .. "）") or "")
end

-- 菜单行：循环档位（0.45 → 0.30 → 0.20 → 0.12 → 回到 0.45）。
--   ★玩家手调过的怪值（例如 0.37）⇒ 一律**回到第一档**（0.45），绝不猜「下一个」是哪一档。
B.gapCycle = function()
  local g = tonumber(B.cfg().moveGap) or DEF.moveGap
  local n = table.getn(B.GAP_CYCLE)
  local i
  for i = 1, n do
    if math.abs(g - B.GAP_CYCLE[i]) < 0.005 then
      B.gapSet(B.GAP_CYCLE[(i % n) + 1])
      return
    end
  end
  B.gapSet(B.GAP_CYCLE[1])
end

-- ★★★「整理步进」的**唯一写口**（`/ebag gap <秒|档位名>`、菜单「整理步进」都走它）：
--   范围 `B.MOVEGAP_MIN..MAX`，坏输入一律不动 + 如实说；写进 `c.moveGap` 后**立刻生效**
--   （不必 /reload —— 整理节拍每拍现读 `B.cfg().moveGap`），并**如实播报一步/秒**。
--   ★与 `B.cfg()` 的下限夹取**同一把尺子**：两处必须一致，否则「写进去的」与「跑起来的」不是一个数。
--   ★0.3.11：认档位名（逐项 0.45 / 标准 0.30 / 快 0.20 / 极快 0.12）—— 玩家记不住小数。
function B.gapSet(v)
  local c = B.cfg()
  local n = tonumber(v)
  if n == nil and type(v) == "string" then
    local key = strVal(v)
    n = B.GAP_WORDS[key]
    if n == nil then
      local k2 = string.gsub(key, "%s+", "")
      n = B.GAP_WORDS[k2]
    end
  end
  if n == nil then
    sayForce("整理步进当前 = " .. B.gapText() .. "（用法 /ebag gap 0.45 或 /ebag gap 逐项|标准|快|极快，范围 "
      .. strVal(B.MOVEGAP_MIN) .. "~" .. strVal(B.MOVEGAP_MAX) .. "）")
    return
  end
  -- ★认小数也认「百分秒」写法（与 `/ebag scale` 同一个 idiom）：`gap 45` = 0.45s、`gap 20` = 0.20s
  if n > 2 then n = n / 100 end
  if n < B.MOVEGAP_MIN then n = B.MOVEGAP_MIN end
  if n > B.MOVEGAP_MAX then n = B.MOVEGAP_MAX end
  n = math.floor(n * 100 + 0.5) / 100
  c.moveGap = n
  c.moveGapMigrated = true        -- 玩家显式选过 ⇒ 默认档迁移永远不再碰它
  B.traceAdd("gap", strVal(n))
  sayForce("整理步进 = " .. B.gapText() .. "（约 " .. strVal(math.floor(1 / n * 10 + 0.5) / 10)
    .. " 步/秒；★想让整理**一件一件动给你看**就别低于 0.30 —— 越小越快、越看不出过程。"
    .. "一步最多一对 PickupContainerItem，太快要小心反滥用限流）")
end

-- ===== 物品读取（唯一入口：图标/数量/品质/类型/分类都从这里出）=====
local QUAL_RGB = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1.00, 1.00, 1.00 },
  [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1.00, 0.50, 0.00 },
  [6] = { 0.90, 0.80, 0.50 },
}

local function qualRGB(q)
  if type(GetItemQualityColor) == "function" then
    local ok, r, g, b = pcall(GetItemQualityColor, q)
    if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  local c = QUAL_RGB[q] or QUAL_RGB[1]
  return c[1], c[2], c[3]
end

B.qualRGB = qualRGB

-- ===== 「鲜丽」品质配色（0.3.13；用户：「装备染色还不够亮眼.需要更加鲜丽的颜色」）=====
--   ★★★**唯一变换 `B.vividRGB(r,g,b)`**（底色与格框**共用同一份**，两处各算一次就是下一个漏改点）：
--     ① **非中性色才变**（最亮 − 最暗 < 0.02 ⇒ 原样返回）—— 否则白装/灰装/空格那种 r=g=b 的灰
--        会被「拉满亮度」变成纯白（本项目真机口径：白/灰必须保持中性，绝不能跟着变色）；
--     ② **提纯**：以最亮通道为基准，把其它通道**按系数压离**它（`sat`）；
--     ③ **拉满亮度**：整体按 `1/最亮通道` 缩放 ⇒ 最亮通道恒 = 1（蓝/紫这种「本来偏暗」的品质色
--        一眼就亮起来 —— 真机截图里看着发暗的正是它们）；
--     ★★★**②③ 只在 `sat > 1` 时才做** ⇒ 标准档（`sat = 1`）**逐元素原样**、与 0.3.10~0.3.12
--        的观感逐字节一致（那是用户随时能退回去的回头路，不许被亮度归一化悄悄改掉）；
--     ④ 结果一律夹进 0~1（**负值必须夹**：`sat` 压过头会算出负数，直接喂 SetVertexColor = 真机上颜色错乱）。
B.TINTS = {
  { k = 0.85, sat = 1.00 },   -- ① 标准（0.3.10/0.3.12 的观感：底色压暗、格框原色）—— 回头路
  { k = 1.00, sat = 1.25 },   -- ② 鲜丽（**新默认档**）
  { k = 1.00, sat = 1.55 },   -- ③ 极鲜（更纯、更少的白）
}
B.TINT_KEYS = { "TINT_STD", "TINT_VIVID", "TINT_ULTRA" }
B.tintIdx = function()
  local k = B.cfg().tint
  local i
  -- 存档里存的是**档位序号**（1/2/3）；缺键/坏数据 ⇒ 默认档（`DEF.tint`，**唯一来源**，别再写字面量 2）
  if type(k) == "number" then
    for i = 1, table.getn(B.TINTS) do
      if i == math.floor(k + 0.5) then return i end
    end
  end
  return DEF.tint
end
B.tintK = function() return B.TINTS[B.tintIdx()].k end

-- ★★★0.3.31 每档品质亮度系数 `B.QUAL_K`（用户 2026-10-06：「我想降低绿色的亮度提高蓝色的亮度应该调整哪些参数」→「A 试下」）：
--   ★唯一来源 = 这张表 · 唯一读口 = `B.qualK(q)` · **唯一作用点 = `paintButton` 的两个写口**：
--     底色 = 颜色 × k（乘完逐通道夹 0~1 ⇒ 色相不变、只变明暗）；辉光 = 写值 α × k（`B.glowAlpha` 夹到 ≤1）。
--     别处一律不乘：格框（`B.SLOT_DIM` 中性）· 悬停金 · 顶栏品质圆点 —— 它们不是「这一格的品质观感」。
--   ★**只做用户逐档手调，绝不做自动归一**（0.3.29 那套已按用户要求撤销；这张表就是替代它的「手动档」）。
--   ★默认档（按用户两句话直接落值）：绿降 0.80 · 蓝升 1.15 —— 参照 0.3.30 的实算观感（绿 108.2 / 蓝 62.3）：
--     绿 0.80 ⇒ 底色 ×0.8 + 辉光写值 0.68（观感 ≈ 69）；蓝 1.15 ⇒ 辉光写值 0.9775（观感 ≈ 82，底色颜色已被夹到顶）。
--     想两档完全拉平：绿 0.87 / 蓝 1.15（两档观感都 ≈ 82）。微调**只改这张表里的数**。
--   ★0.3.31e 改判：辉光 alpha **只走顶点色**（不再与 `SetAlpha` 相乘）⇒ 写值 = 观感本身（**线性**），
--     且「初始打开 == 悬停恢复」（单通道两态都落地）。**最终定档（用户真机微调后定）**：基准 `B.GLOW_A` = 0.85² = 0.7225、
--     绿 = 0.80 本体（观感 0.578 = 基准的 80%）· 蓝 = 1.3225 = 1.15²（观感 0.955，与 0.3.31 稳态相同）。
B.QUAL_K = {
  [2] = 0.80,   -- 优秀（绿）：★用户最终定档（0.3.31e 单通道后按观感**线性**生效）⇒ 观感 = 基准 × 0.80 = 0.578，恰为基准的 80%（降两成）
  [3] = 1.3225, -- 稀有（蓝）：= 1.15²（同上 ⇒ 保住 0.955）
}
B.qualK = function(q)
  local k = B.QUAL_K[tonumber(q) or -1]
  if type(k) ~= "number" then return 1 end
  if k < 0 then return 0 end
  if k > 2 then return 2 end   -- 上限夹取：写再大的数也只是「亮到顶」，不许失控
  return k
end
-- 读值口（`/ebag status` 的「外观」行列出当前系数；没有系数就如实写「全部 1」）
B.qualKLine = function()
  local ks = {}
  for q = 2, 6 do
    local k = B.QUAL_K[q]
    if type(k) == "number" then table.insert(ks, "q" .. q .. "=" .. strVal(k)) end
  end
  if table.getn(ks) == 0 then return "（无，全部 1）" end
  return table.concat(ks, " · ")
end
B.tintText = function()
  local i = B.tintIdx()
  return L(B.TINT_KEYS[i] or "TINT_VIVID")
end

B.vividRGB = function(r, g, b)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return 0, 0, 0 end
  local mx = r
  if g > mx then mx = g end
  if b > mx then mx = b end
  local mn = r
  if g < mn then mn = g end
  if b < mn then mn = b end
  -- ① 中性色（白/灰）原样返回：绝不把白装/灰装/空格染成别的颜色
  if (mx - mn) < 0.02 or mx < 0.01 then return r, g, b end
  local sat = B.TINTS[B.tintIdx()].sat or 1
  -- ★★★②+③ **整套变换只在 `sat > 1` 时才做**：`sat == 1`（标准档）= **逐元素原样** ——
  --   连「拉满亮度」那一步也不做，否则标准档就不再等于 0.3.10~0.3.12 的旧观感
  --   （旧观感 = 品质原色，底色再乘 k=0.85；这是用户随时能退回去的那条回头路，必须逐字节等价）。
  if sat > 1 then
    r = mx - (mx - r) * sat
    g = mx - (mx - g) * sat
    b = mx - (mx - b) * sat
    -- 拉满亮度：整体按 `1/最亮通道` 缩放 ⇒ 最亮通道恒 = 1（蓝/紫这种「本来偏暗」的品质色一眼就亮起来）
    local k = 1 / mx
    r, g, b = r * k, g * k, b * k
  end
  -- ④ 夹进 0~1（**负值必须夹**：`sat` 压过头会算出负数，直接喂 SetVertexColor = 真机上颜色错乱）
  if r < 0 then r = 0 elseif r > 1 then r = 1 end
  if g < 0 then g = 0 elseif g > 1 then g = 1 end
  if b < 0 then b = 0 elseif b > 1 then b = 1 end
  return r, g, b
end

-- 唯一写口（菜单行 / `/ebag tint` 都走它）：认档位序号也认档位名
B.tintSet = function(v)
  local c = B.cfg()
  local i = B.tintIdx()
  local j
  if type(v) == "number" then
    for j = 1, table.getn(B.TINTS) do
      if j == math.floor(v + 0.5) then i = j end
    end
  elseif type(v) == "string" then
    local s = strVal(v)
    for j = 1, table.getn(B.TINT_KEYS) do
      if s == strVal(L(B.TINT_KEYS[j])) or s == strVal(B.TINT_KEYS[j]) then i = j end
    end
  end
  c.tint = i
  B.refreshAll()
  sayForce(L("MENU_TINT") .. " = " .. B.tintText())
  return true
end
B.tintCycle = function()
  local n = table.getn(B.TINTS)
  local i = B.tintIdx() + 1
  if i > n then i = 1 end
  B.tintSet(i)
end

-- 物品类型串（GetItemInfo 第 5 个返回）在 zhCN 是本地化的中文
-- ⇒ 一律拿客户端自己的 ITEM_CLASS_* 常量比（那个常量本身就是本地化串）。
local CLASS_FALLBACK = {
  zhCN = {
    ["武器"] = "equip", ["护甲"] = "equip", ["容器"] = "container",
    ["消耗品"] = "consume", ["商品"] = "trade", ["任务"] = "quest",
    ["任务物品"] = "quest", ["配方"] = "trade", ["钱币"] = "trade",
    ["箭矢"] = "consume", ["弹药"] = "consume", ["杂项"] = "other",
  },
  enUS = {
    Weapon = "equip", Armor = "equip", Container = "container",
    Consumable = "consume", ["Trade Goods"] = "trade", Quest = "quest",
    Recipe = "trade", Money = "trade", Projectile = "consume", Quiver = "consume",
    Misc = "other",
  },
  ruRU = {},
}

local CLASS_GLOBALS = {
  equip = { "ITEM_CLASS_WEAPON", "ITEM_CLASS_ARMOR" },
  container = { "ITEM_CLASS_CONTAINER" },
  consume = { "ITEM_CLASS_CONSUMABLE", "ITEM_CLASS_PROJECTILE", "ITEM_CLASS_QUIVER" },
  trade = { "ITEM_CLASS_TRADE_GOODS", "ITEM_CLASS_RECIPE", "ITEM_CLASS_MONEY" },
  quest = { "ITEM_CLASS_QUEST" },
}

-- ★候选集：一个类别在**本机可能是哪几个字面量**（客户端常量 + 当前语言表 + 英文字面量）
--   ★★绝不「取第一个候选就返回」：首版就是先命中中文表里的「商品」就短路，导致英文串永远配不上
local CLASS_CATS = { "equip", "container", "consume", "trade", "quest" }

local function classCands(cat)
  local out = {}
  local g = CLASS_GLOBALS[cat]
  if g then
    local i
    for i = 1, table.getn(g) do
      local v = _G[g[i]]
      if type(v) == "string" and v ~= "" then table.insert(out, v) end
    end
  end
  if cat == "other" then
    local v = _G["ITEM_CLASS_MISC"]
    if type(v) == "string" and v ~= "" then table.insert(out, v) end
  end
  local loc = B.loc
  local tbl = CLASS_FALLBACK[loc]
  local lit, c
  if tbl then
    for lit, c in pairs(tbl) do if c == cat then table.insert(out, lit) end end
  end
  if loc ~= "enUS" then
    for lit, c in pairs(CLASS_FALLBACK.enUS) do if c == cat then table.insert(out, lit) end end
  end
  return out
end

local TYPE_CAT_CACHE = {}

-- ★单一入口：所有「按类型分流」的地方（排序 / 类型筛选）都读这一个函数。
--   ★★第一判据 = **装备槽位 token**（`GetItemInfo` 第 8 个返回，如 INVTYPE_WEAPON）—— 语言无关。
function B.catOf(itemType, equipLoc)
  if type(equipLoc) == "string" and equipLoc ~= "" then return "equip" end
  if type(itemType) ~= "string" or itemType == "" then return "other" end
  local hit = TYPE_CAT_CACHE[itemType]
  if hit ~= nil then return hit end
  local cat = "other"
  local i, j
  for i = 1, table.getn(CLASS_CATS) do
    local cands = classCands(CLASS_CATS[i])
    for j = 1, table.getn(cands) do
      if cands[j] == itemType then
        cat = CLASS_CATS[i]
        break
      end
    end
    if cat ~= "other" then break end
  end
  TYPE_CAT_CACHE[itemType] = cat
  return cat
end

-- ★★8 类图标筛选（照参考 OneBag 的 CreateCategoryModule 逐项对齐：图标 + 配色 + 金框选中 + 悬停件数）
--   ★★与排序用的 B.catOf 是**两套词表**、故意不合并：排序那套只有 5 类
--     （equip/container/consume/trade/quest），改它的词表会动到整理引擎的判据；
--     这里按参考的 8 类（quest/equip/consume/trade/reagent/container/projectile/other）另立一套，
--     两者只在「装备槽位 token 优先」这一条口径上一致。
--   ★图标名一律取 `doc/图标路径清单.txt` 里核对过的（清单 = 宏图标枚举，存在性白名单）
B.CATS = {
  { id = "quest",      key = "CAT_QUEST",      icon = "INV_Misc_Note_02",     r = 1.00, g = 0.82, b = 0.00 },
  { id = "equip",      key = "CAT_EQUIP",      icon = "INV_Chest_Plate01",    r = 0.70, g = 0.70, b = 0.90 },
  { id = "consume",    key = "CAT_CONSUME",    icon = "INV_Potion_01",        r = 0.40, g = 0.90, b = 0.40 },
  { id = "trade",      key = "CAT_TRADE",      icon = "Trade_BlackSmithing",  r = 0.90, g = 0.60, b = 1.00 },
  { id = "reagent",    key = "CAT_REAGENT",    icon = "INV_Misc_Dust_02",     r = 1.00, g = 0.90, b = 0.50 },
  { id = "container",  key = "CAT_CONTAINER",  icon = "INV_Misc_Bag_11",      r = 0.70, g = 0.70, b = 0.70 },
  { id = "projectile", key = "CAT_PROJECTILE", icon = "INV_Ammo_Arrow_01",    r = 0.50, g = 0.80, b = 1.00 },
  { id = "other",      key = "CAT_OTHER",      icon = "INV_Misc_QuestionMark", r = 0.60, g = 0.60, b = 0.60 },
}

-- 判定次序 = 参考的次序，但把「弹药」提到「消耗品」之前
--   （参考把 Projectile 归在 consume 的检查之后 ⇒ 弹药会先被当消耗品；这里按更精确的先判）
local CAT8_ORDER = { "quest", "equip", "projectile", "container", "consume", "reagent", "trade" }

-- 客户端常量（那个常量本身就是本地化串；本客户端没有的就自然跳过）
local CAT8_GLOBALS = {
  quest = { "ITEM_CLASS_QUEST" },
  equip = { "ITEM_CLASS_WEAPON", "ITEM_CLASS_ARMOR" },
  projectile = { "ITEM_CLASS_PROJECTILE" },
  container = { "ITEM_CLASS_CONTAINER", "ITEM_CLASS_QUIVER" },
  consume = { "ITEM_CLASS_CONSUMABLE" },
  reagent = { "ITEM_CLASS_REAGENT" },
  trade = { "ITEM_CLASS_TRADE_GOODS", "ITEM_CLASS_RECIPE", "ITEM_CLASS_MONEY" },
}

-- 语言字面量（zhCN 三处通用 + 英文字面量兜底；ruRU 认不出就落 other —— 判不出不硬猜）
local CAT8_LIT = {
  quest = { "任务", "任务物品", "Quest", "Key", "钥匙" },
  equip = { "武器", "护甲", "Weapon", "Armor" },
  projectile = { "弹药", "箭矢", "Projectile", "Ammo" },
  container = { "容器", "Container", "Quiver", "箭袋" },
  consume = { "消耗品", "食物", "药水", "烹饪", "Consumable", "Food", "Potion" },
  reagent = { "材料", "试剂", "Reagent" },
  trade = { "商品", "商业技能", "交易商品", "配方", "食谱", "钱币", "Trade Goods", "Recipe", "Money" },
}

local CAT8_CACHE = {}

-- 8 类判定唯一入口（图标筛选与悬停件数共用）
function B.cat8Of(itemType, equipLoc)
  if type(equipLoc) == "string" and equipLoc ~= "" then return "equip" end
  if type(itemType) ~= "string" or itemType == "" then return "other" end
  local hit = CAT8_CACHE[itemType]
  if hit ~= nil then return hit end
  local cat = "other"
  local i, j, k
  for i = 1, table.getn(CAT8_ORDER) do
    local id = CAT8_ORDER[i]
    local cands = {}
    local g = CAT8_GLOBALS[id]
    if g ~= nil then
      for j = 1, table.getn(g) do
        local v = _G[g[j]]
        if type(v) == "string" and v ~= "" then table.insert(cands, v) end
      end
    end
    local lit = CAT8_LIT[id]
    if lit ~= nil then
      for j = 1, table.getn(lit) do table.insert(cands, lit[j]) end
    end
    for k = 1, table.getn(cands) do
      if cands[k] == itemType then
        cat = id
        break
      end
    end
    if cat ~= "other" then break end
  end
  CAT8_CACHE[itemType] = cat
  return cat
end

local function fillInfoFromLink(rec)
  if type(rec.link) ~= "string" or rec.link == "" then return rec end
  local nm = string.match(rec.link, "%[(.-)%]")
  if nm ~= nil then rec.name = nm end
  local id = string.match(rec.link, "item:(%d+)")
  if id == nil then return rec end
  rec.id = tonumber(id)
  if rec.id == nil or type(GetItemInfo) ~= "function" then return rec end
  local ok, n, _, q, _, t, sub, maxStack, eqLoc = pcall(GetItemInfo, rec.id)
  if not ok then return rec end
  if type(n) == "string" and n ~= "" then rec.name = n end
  if type(q) == "number" then rec.quality = q end
  rec.itemType = t
  rec.subType = sub
  rec.equipLoc = eqLoc
  if type(maxStack) == "number" then rec.maxStack = maxStack end
  return rec
end

-- 读一格：无物品返回 nil。
-- ★银行主格（BANK_CONTAINER）走的是**人物装备槽** 40..63（vanilla BankButtonIDToInvSlotID = slot+39），
--   不能用容器 API 读 —— 这是「银行背包没生效」最容易踩的一处。
function B.itemAt(bag, slot)
  if bag == nil or slot == nil then return nil end
  if bag == B.BANK then
    if type(GetInventoryItemLink) ~= "function" then return nil end
    local inv = 39 + slot
    if type(BankButtonIDToInvSlotID) == "function" then
      local okI, v = pcall(BankButtonIDToInvSlotID, slot)
      if okI and type(v) == "number" and v > 0 then inv = v end
    end
    local rec = { bag = bag, slot = slot, invSlot = inv, bankMain = true, count = 1, quality = 1 }
    local ok1, link = pcall(GetInventoryItemLink, "player", inv)
    if ok1 and type(link) == "string" and link ~= "" then rec.link = link end
    if type(GetInventoryItemTexture) == "function" then
      local ok2, tex = pcall(GetInventoryItemTexture, "player", inv)
      if ok2 and type(tex) == "string" and tex ~= "" then rec.texture = tex end
    end
    if type(GetInventoryItemCount) == "function" then
      local ok3, cnt = pcall(GetInventoryItemCount, "player", inv)
      if ok3 and type(cnt) == "number" then rec.count = cnt end
    end
    if rec.link == nil and rec.texture == nil then return nil end
    rec.name = "?"
    return fillInfoFromLink(rec)
  end
  if type(GetContainerItemInfo) ~= "function" then return nil end
  local ok, texture, count, locked = pcall(GetContainerItemInfo, bag, slot)
  if not ok then return nil end
  local link
  if type(GetContainerItemLink) == "function" then
    local ok2, l = pcall(GetContainerItemLink, bag, slot)
    if ok2 then link = l end
  end
  if (texture == nil or texture == "") and (link == nil or link == "") then return nil end
  local rec = { bag = bag, slot = slot, texture = texture, count = count or 1, locked = locked and true or false }
  if type(link) == "string" and link ~= "" then
    rec.link = link
    rec.name = "?"
    return fillInfoFromLink(rec)
  end
  rec.name = "?"
  return rec
end

-- ===== 金钱 =====
local function moneyStr(m)
  if type(m) ~= "number" then return "" end
  if m < 0 then m = 0 end
  local g = math.floor(m / 10000)
  local s = math.floor(math.fmod(m, 10000) / 100)
  local c = math.fmod(m, 100)
  local out = {}
  if g > 0 then table.insert(out, "|cffffd700" .. strVal(g) .. "g|r") end
  if s > 0 or g > 0 then table.insert(out, "|cffc7c7cf" .. strVal(s) .. "s|r") end
  table.insert(out, "|cffeda55f" .. strVal(c) .. "c|r")
  return table.concat(out, " ")
end

function B.moneyStr()
  if type(GetMoney) ~= "function" then return "" end
  local ok, m = pcall(GetMoney)
  if not ok then return "" end
  return moneyStr(m)
end

-- ★★★0.3.16 金钱行 = 「数字 + 金币小图标」（用户：「图2,金币类小图标他是如何应用的参考一下」）
--   参考**客户端自己的做法**（原件在 `tmp/mpq_out/Interface/FrameXML/MoneyFrame.xml`）：
--   它**不用内联贴图转义**（整份 FrameXML 里 `|T` 出现 0 次），而是**一张图集 + TexCoords**：
--     `Interface\MoneyFrame\UI-MoneyIcons`（每格 19×19）——金 `0~0.25` / 银 `0.25~0.5` / 铜 `0.5~0.75`
--     （第四格本客户端未用）；每颗币 = 一个 texture 锚 `RIGHT`，数字 FontString 锚在它**左边**（-19）。
--   ⇒ 我们照同一套：三对「数字 + 图标」按 RIGHT 链排开（几何唯一来源 = B.metrics 里那一段）。
--   ★显隐口径与客户端 `MoneyFrame_Update` 一致：金/银为 0（且高位也为 0）不显示、铜恒显示。
--   ★0.3.24 资源独立性审计（用户问：「外部依赖的图标资源有没复制到当前子插件内？」）：
--     本子插件里**引用第三方插件目录（`Interface\AddOns\<别的插件>\…`）的地方 = 0 处**；
--     下面这个 `Interface\MoneyFrame\…` 与 `Interface\Buttons\…` 都是**客户端自带**的 UI 素材
--     （证据：客户端自己的 `Interface\FrameXML\MoneyFrame.xml` 就在用这张图集）—— 那是游戏本体的一部分，
--     不是「别人的插件目录」；★自己 media 里的三张（slotframe/slotfill/slotglow）已经复制进来了。
--     ⇒ 这张图集也做**读回自证**（B.mnyOK）：明确读不到就只画文字并补 g/s/c 后缀，绝不留三个认不出的数字。
B.MNY_TEX = "Interface\\MoneyFrame\\UI-MoneyIcons"
B.MNY_UV = { g = { 0, 0.25 }, s = { 0.25, 0.5 }, c = { 0.5, 0.75 } }
B.MNY_RGB = { g = { 1.00, 0.84, 0.00 }, s = { 0.80, 0.80, 0.84 }, c = { 0.93, 0.65, 0.37 } }
B.MNY_SUF = { g = "g", s = "s", c = "c" }
B.mnyOK = nil    -- ★0.3.24 图集读回自证：true=有 / false=明确没有（只画文字）/ nil=判不出（保持现状）

-- ★★★0.3.26 **资源绝对自包含**（用户：「分析排查 子插件代码内很多 Interface\\ 相关路径的设置，非当前插件目录
--   …看下还有哪些资源没有复制到当前插件目录内。要做好子插件资源绝对不引用外部目录文件」）：
--   凡是**固定路径的贴图**一律复制进 `media\`（来源 = TurtleWoW `Data\interface.MPQ`，`tmp/mpq_take.js` 逐字节取出；
--   每张的出处/用途写在 `media\README.txt`），代码里**一律走「自带优先 → 客户端那份兜底」**：
--   自带探不到 / 判不出 ⇒ 退回客户端那条路径 = 与「没复制」逐字节一致的行为（绝不因为探针不可信把界面画没）。
--   ★唯一的两个例外（**没法自带**，如实记在 README 与 `/ebag res` 里）：
--     ① **物品/法术/宏图标**：贴图路径由客户端数据现给（`GetContainerItemInfo` 第 1 个返回、`GetSpellTexture`…），
--        我们只是把客户端给的路径**原样**交给 `SetTexture` —— 那是游戏本体的物品美术，不是「别的插件目录」；
--     ② **`/Game/Interface/Icons/<名>_TEX`**：本客户端的 UE 资产路径（EmberVeil 美术在 UE pak 里、取不出来）
--        ⇒ 只作为分类图标的**最后兜底**（第一顺位已经是自带的 `media\<名>`）。
B.MEDIA = "Interface\\AddOns\\EH_Bag\\media\\"
B.OWN_FORMS = { "", ".blp" }   -- 插件目录里的散装贴图：**无后缀优先**（1.75.62 在案），再试 .blp
B.CTL = {}                     -- 每个后缀的**负对照**结论缓存（true = 对照探不到 ⇒ 这个写法可信）

-- ★探针（照 1.75.53 那把尺子）：**每次新建**一张不设宽高的纹理 → `SetTexture(路径)` → 读 `GetWidth`
--   （客户端报的是**贴图文件**像素尺寸：文件在 ⇒ >0、不在 ⇒ 0、判不出 ⇒ nil）。
--   ★必须每次新建（复用会有「上一次文件尺寸残留 ⇒ 假结果」的风险）；1.12 **没有销毁纹理的 API**
--     ⇒ 这些探针纹理建完就 `SetTexture(nil)` + `Hide` 留着（数量有界：2 张对照 + 每个资源 ≤2 张，只在建窗期跑一趟）。
function B.texProbe(f, path)
  if isObj(f) ~= true then return nil end
  local t
  if pcall(function() t = f:CreateTexture(nil, "BACKGROUND") end) ~= true then return nil end
  if isObj(t) ~= true then return nil end
  local okS = pcall(t.SetTexture, t, path)
  local okW, w = pcall(t.GetWidth, t)
  pcall(t.SetTexture, t, nil)
  pcall(t.Hide, t)
  if okS ~= true or okW ~= true then return nil end
  if type(w) ~= "number" then return nil end
  return (w > 0)
end

-- ★负对照（**每个后缀只探一次**）：同目录、同后缀、**绝不存在**的一个名字 ——
--   本客户端对不存在的文件也可能报出非 0 尺寸（带扩展名的路径尤其明显）⇒ 对照也报「有」= 这一档**判不出**。
--   返回 true（可信）/ false（不可信）/ nil（探测本身不可用 ⇒ 这次不缓存，下次再问）。
function B.ctlTrust(f, suf)
  local hit = B.CTL[suf]
  if hit ~= nil then return hit end
  local v = B.texProbe(f, B.MEDIA .. "ehbag_absent_probe" .. suf)
  if v == nil then return nil end
  B.CTL[suf] = (v == false)
  return B.CTL[suf]
end

-- ★「在 media\ 里给 name 找一条自带路径」= **唯一实现**（金钱图集也走它）。
--   返回：选中的路径（找不到 = nil）· 命中的后缀 · 是否**探到过**任何一种写法。
--   ★第 3 个返回专门用来把理由说准：探到过、但对照也报「有」⇒ 原因是**探针不可信**（不是「文件不在」）。
function B.resPick(f, name)
  if type(name) ~= "string" or name == "" then return nil, nil, false end
  local saw = false
  local i
  for i = 1, table.getn(B.OWN_FORMS) do
    local suf = B.OWN_FORMS[i]
    local hit = B.texProbe(f, B.MEDIA .. name .. suf)
    if hit == true then saw = true end
    if hit == true and B.ctlTrust(f, suf) == true then return B.MEDIA .. name .. suf, suf, true end
  end
  return nil, nil, saw
end

-- ★固定资源清单（**唯一来源**）：media\ 里的文件名（= 客户端那张图的基础名）→ 客户端兜底路径。
--   加新素材只加一行；`/ebag res` 与 `/ebag status` 都从这一份现算。
B.RES_LIST = {
  { "WHITE8X8",              "Interface\\Buttons\\WHITE8X8" },
  { "ChatFrameBackground",   "Interface\\ChatFrame\\ChatFrameBackground" },
  { "UI-Tooltip-Border",     "Interface\\Tooltips\\UI-Tooltip-Border" },
  { "ButtonHilight-Square",  "Interface\\Buttons\\ButtonHilight-Square" },
  { "Button-Backpack-Up",    "Interface\\Buttons\\Button-Backpack-Up" },
  { "UI-Button-KeyRing",     "Interface\\Buttons\\UI-Button-KeyRing" },
  { "KeyRing-Bag-Icon",      "Interface\\ContainerFrame\\KeyRing-Bag-Icon" },
  { "INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark" },
  -- ★顶栏 8 类筛选图标（`B.CATS[].icon` 的基础名；客户端兜底 = 归档里的 Interface\Icons\<名>，
  --   本客户端还能认 UE 资产路径 `/Game/Interface/Icons/<名>_TEX`，那一条留在 catIconSet 里当第二顺位）
  { "INV_Misc_Note_02",      "Interface\\Icons\\INV_Misc_Note_02" },
  { "INV_Chest_Plate01",     "Interface\\Icons\\INV_Chest_Plate01" },
  { "INV_Potion_01",         "Interface\\Icons\\INV_Potion_01" },
  { "Trade_BlackSmithing",   "Interface\\Icons\\Trade_BlackSmithing" },
  { "INV_Misc_Dust_02",      "Interface\\Icons\\INV_Misc_Dust_02" },
  { "INV_Misc_Bag_11",       "Interface\\Icons\\INV_Misc_Bag_11" },
  { "INV_Ammo_Arrow_01",     "Interface\\Icons\\INV_Ammo_Arrow_01" },
}
B.RES = {}          -- name -> 选中的路径（建窗期一次性算好）
B.RES_WHY = {}      -- name -> 取证：为什么（自带:无后缀 / 自带:.blp / 客户端:自带读不到 / 客户端:探测不可信）
B.resAt = nil       -- 上一次扫描时刻（取证）

-- ★扫描口（**建窗期调一次**，`f` = 主帧 —— 探针要一个宿主帧）：逐个资源走 resPick 并缓存结论。
function B.resScan(f)
  if isObj(f) ~= true then return false end
  B.CTL = {}
  local i
  for i = 1, table.getn(B.RES_LIST) do
    local nm = B.RES_LIST[i][1]
    local cp = B.RES_LIST[i][2]
    local p, suf, saw = B.resPick(f, nm)
    if p ~= nil then
      B.RES[nm] = p
      B.RES_WHY[nm] = "自带:" .. ((suf == "") and "无后缀" or suf)
    else
      B.RES[nm] = cp
      B.RES_WHY[nm] = "客户端:" .. (saw and "探测不可信" or "自带读不到")
    end
  end
  B.resAt = GetTime()
  return true
end

-- ★唯一读口：这条资源该用哪条路径（没扫过 / 名字不认识 ⇒ 客户端那条 = fail-open，与 0.3.25 之前一致）。
function B.res(name, clientPath)
  local v = B.RES[name]
  if type(v) == "string" and v ~= "" then return v end
  return clientPath
end

-- ★★金钱图集（0.3.25 起就自带一份）：来源判定也走**同一套** resPick（探针 + 负对照）；
--   它比别的资源多一层「自带**读回为空** ⇒ 当场退回客户端」的安全网（见 build 里那一段）。
B.MNY_SEL = nil      -- 建窗期一次性算好：真正 SetTexture 用的那条路径
B.MNY_WHY = "未探测" -- 取证：为什么选了它（自带:无后缀 / 自带:.blp / 客户端:自带读不到 / 客户端:探测不可信）
function B.mnyPickUI(f)
  local p, suf, saw = B.resPick(f, "moneyicons")
  if p ~= nil then
    B.MNY_SEL = p
    B.MNY_WHY = "自带:" .. ((suf == "") and "无后缀" or suf)
    return p
  end
  B.MNY_SEL = B.MNY_TEX
  B.MNY_WHY = "客户端:" .. (saw and "探测不可信" or "自带读不到")
  return B.MNY_TEX
end

-- 把一串钱数画进金钱行（**唯一绘制口**）；m 不是数字 / 负数 ⇒ 按 0（与旧 moneyStr 的判据一致）
function B.moneyPaint(m)
  local f = B.ui.frame
  if f == nil then return end
  if type(m) ~= "number" or m < 0 then m = 0 end
  local g = math.floor(m / 10000)
  local s = math.floor(math.fmod(m, 10000) / 100)
  local c = math.fmod(m, 100)
  local T, I = f.ehMoneyT, f.ehMoneyI
  if type(T) ~= "table" or type(I) ~= "table" then return end
  -- ★0.3.24：图集**明确读不到**时（B.mnyOK == false）只画文字 + 币种后缀（金/银/铜一眼分得清）
  local bad = (B.mnyOK == false)
  local function one(k, v, show)
    local t, ic = T[k], I[k]
    if isObj(t) then
      pcall(t.SetText, t, strVal(v) .. (bad and (B.MNY_SUF[k] or "") or ""))
      if show then pcall(t.Show, t) else pcall(t.Hide, t) end
    end
    if isObj(ic) then
      if show and not bad then pcall(ic.Show, ic) else pcall(ic.Hide, ic) end
    end
  end
  one("g", g, g > 0)
  one("s", s, s > 0 or g > 0)
  one("c", c, true)
end

function B.moneyRefresh()
  if type(GetMoney) ~= "function" then return end
  local ok, m = pcall(GetMoney)
  if not ok then return end
  B.moneyPaint(m)
end

-- ===== 界面 =====
-- ===== 跨角色快照（OneView 的唯一数据源）=====
-- ★依据：本客户端（vanilla）`## SavedVariables` 是**账号级共享**的（一个账号一份文件）
--   ⇒ 每个角色登录时把自己的背包/银行写进同一份存档，别的角色登录就读得到。
--   参考 OneBag 的 OneView 走的是 `!Libs` 的 OneStorage-2.0（同一机制、只是库化），
--   本子插件零依赖 ⇒ 自己存一份（更小：只存有物品的格）。
-- ★一律有界：角色数 B.CHAR_MAX、**每角色物品总数** B.CHAR_ITEM_MAX、同角色快照最小间隔 B.SNAP_GAP 秒。
B.CHAR_MAX = 16
B.CHAR_ITEM_MAX = 300
B.SNAP_GAP = 20

-- 角色键（照参考：名字 + 服务器）。★拿不到名字 ⇒ 如实返回 nil，一个字节都不写。
function B.charKey()
  local n, r
  if type(UnitName) == "function" then
    local ok, a, b = pcall(UnitName, "player")
    if ok then
      if type(a) == "string" and a ~= "" then n = a end
      if type(b) == "string" and b ~= "" then r = b end
    end
  end
  if r == nil and type(GetRealmName) == "function" then
    local ok, v = pcall(GetRealmName)
    if ok and type(v) == "string" and v ~= "" then r = v end
  end
  if n == nil then return nil end
  if r == nil then return n end
  return n .. "-" .. r
end

local function nowSec()
  if type(time) == "function" then
    local ok, v = pcall(time)
    if ok and type(v) == "number" then return v end
  end
  return 0
end

-- 容器容量（★与「显示与否」无关：快照要的是**真实内容**，隐藏一个背包不该把它的数据抹掉）
local function capOf(bag)
  if bag == B.BANK then
    if B.bankOpen ~= true then return 0 end
    return B.BANK_PANE_SLOTS
  end
  if bag == B.KEYRING then return keyringSize() end
  return bagSlotsRaw(bag)
end

-- 压成「只有物品的格」的顺序表 + 每容器的用量。
-- budget = 共享的剩额表（整个角色所有容器一共只准存 B.CHAR_ITEM_MAX 条 ⇒ 存档有界）
local function packBags(bags, budget)
  local out, meta = {}, {}
  local i
  for i = 1, table.getn(bags) do
    local bag = bags[i]
    local n = capOf(bag)
    local list = {}
    local used = 0
    if n > 0 then
      local s
      for s = 1, n do
        local it = B.itemAt(bag, s)
        if it ~= nil then
          -- ★★★0.3.24：**链接读不到就反查一次**（有界；只对缺链接的物品做，绝不每件都做）。
          --   真机取证（存档 chars[角色].bk）：银行主格的记录**只有贴图、没有链接、名字是 "?"**
          --   —— 本客户端 `GetInventoryItemLink("player", 40..63)` 对银行槽不给链接（贴图那一路是好的）。
          --   不反查的话，跨角色总览里银行物品永远只能显示「? ×N 只读…」（用户截图就是这个）。
          if (type(it.link) ~= "string" or it.link == "") and type(B.richTry) == "function" then
            pcall(B.richTry, bag, s, it)
          end
          used = used + 1
          if budget.n > 0 then
            budget.n = budget.n - 1
            table.insert(list, {
              s = s,
              l = it.link,
              t = it.texture,
              c = it.count or 1,
              q = it.quality or 0,
              n = it.name,
              rl = it.rl,        -- ★0.3.24：链接彻底拿不到时的「气泡行」兜底（有界，见 B.RICH_*）
            })
          end
        end
      end
    end
    out[bag] = list
    meta[bag] = { u = used, n = n, on = (bagShown(bag) and 1 or 0) }
  end
  return out, meta
end

-- 写一份快照。why = "force" 时不受最小间隔限制。
function B.snapshot(why)
  local key = B.charKey()
  if key == nil then
    B.snapWhy = "无角色名"
    return false
  end
  local now = 0
  if type(GetTime) == "function" then now = GetTime() end
  if why ~= "force" and B.snapAt ~= nil and (now - B.snapAt) < B.SNAP_GAP then
    return false
  end
  B.snapAt = now
  B.richN = 0            -- ★0.3.24：每次快照重置「反查次数」（有界：B.RICH_MAX，见 B.richTry）
  local c = B.cfg()
  if type(c.chars) ~= "table" then c.chars = {} end
  local store = c.chars
  local rec = store[key]
  if type(rec) ~= "table" then
    rec = {}
    store[key] = rec
  end
  rec.k = key
  rec.n = string.match(key, "^(.-)%-") or key
  rec.t = nowSec()
  local lv
  if type(UnitLevel) == "function" then
    local ok, v = pcall(UnitLevel, "player")
    if ok and type(v) == "number" and v > 0 then lv = v end
  end
  rec.lv = lv
  local cls
  if type(UnitClass) == "function" then
    local ok, v = pcall(UnitClass, "player")
    if ok and type(v) == "string" and v ~= "" then cls = v end
  end
  rec.cls = cls
  if type(GetMoney) == "function" then
    local ok, m = pcall(GetMoney)
    if ok and type(m) == "number" then rec.money = m end
  end
  local budget = { n = B.CHAR_ITEM_MAX }
  -- 背包 0~4：每次都刷
  local it, itM = packBags(B.BAGS, budget)
  rec.it = it
  rec.itM = itM
  -- 钥匙链：开着才有内容（关掉时保留上一次的数据，不抹）
  if bagShown(B.KEYRING) then
    local kt, ktM = packBags({ B.KEYRING }, budget)
    rec.kt = kt[B.KEYRING]
    rec.ktM = ktM[B.KEYRING]
  end
  if B.bankOpen == true then
    local bk = { B.BANK }
    local j
    for j = 1, table.getn(B.BANKBAGS) do
      table.insert(bk, B.BANKBAGS[j])
    end
    local bt, btM = packBags(bk, budget)
    rec.bk = bt
    rec.bkM = btM
  end
  -- ★角色有界：超上限按「最后见到」淘汰最老的那个（绝不无界增长）
  local keys = {}
  local kk
  for kk in pairs(store) do
    table.insert(keys, kk)
  end
  while table.getn(keys) > B.CHAR_MAX do
    local oldI, oldT = 1, nil
    local i
    for i = 1, table.getn(keys) do
      local r2 = store[keys[i]]
      local t2 = 0
      if type(r2) == "table" and type(r2.t) == "number" then t2 = r2.t end
      if oldT == nil or t2 < oldT then oldT, oldI = t2, i end
    end
    store[keys[oldI]] = nil
    table.remove(keys, oldI)
  end
  B.snapWhy = strVal(why or "") .. " 已记录"
  return true
end

-- 本角色在快照里的坐标（供命令/状态行显示）
function B.snapLine()
  local key = B.charKey()
  local c = B.cfg()
  local n = 0
  local k
  local store = c.chars
  if type(store) == "table" then
    for k in pairs(store) do
      n = n + 1
    end
  end
  return strVal(key or "?") .. " ｜ 存档里角色数=" .. strVal(n)
end

B.ui = { buttons = {}, bags = {}, bankButtons = {}, label = {}, needLayout = true, btnList = {} }

local FONT_CHAIN = { "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontNormal" }

local function setFontFS(fs)
  if isObj(fs) == false then return end
  local i
  for i = 1, table.getn(FONT_CHAIN) do
    local fo = _G[FONT_CHAIN[i]]
    if fo ~= nil and type(fs.SetFontObject) == "function" then
      if pcall(fs.SetFontObject, fs, fo) then return end
    end
  end
end

local function solid(tex, r, g, b, a)
  if isObj(tex) == false then return end
  -- ★0.3.26：纯色贴图也走「自带优先」（自带 white8x8.blp → 客户端 WHITE8X8）
  pcall(tex.SetTexture, tex, B.res("WHITE8X8", "Interface\\Buttons\\WHITE8X8"))
  pcall(tex.SetVertexColor, tex, r, g, b, a or 1)
end

local function font(parent)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  setFontFS(fs)
  -- ★界面缩放：字体跟着缩（读回字体链的路径/字号再按 z 重设；读不到就保持原样 —— 绝不猜）
  local okZ, z = pcall(B.z)
  if okZ and type(z) == "number" and z ~= 1 and type(fs.GetFont) == "function" then
    local ok, path, size, flags = pcall(fs.GetFont, fs)
    if ok and type(path) == "string" and path ~= "" and type(size) == "number" and size > 0 then
      pcall(fs.SetFont, fs, path, size * z, flags)
    end
  end
  return fs
end

-- ★★★干净边框（0.3.7）：旧写法把**九宫格边框贴图** `UI-Tooltip-Border` 用 SetPoint 拉满整颗按钮 ⇒
--   它的角饰被拉成**竖线/横线**（用户报「总览 / 整理 / 设置 / X 关闭按钮的背景都有竖线」的真因；
--   同一个坑 0.3.3 在背包条上踩过一次）。现在改用**四条 1px 纯色边**（WHITE8X8 + SetVertexColor ——
--   项目 §三.3：纯色纹理只有这条路可靠），与客户端美术零依赖、任何尺寸都不会拉出线条。
--   ★对外交出的是**代理表**（方法名与 Texture 同形：Show / Hide / IsShown / SetVertexColor / SetAlpha）
--   ⇒ 调用点一个字节都不用改；`isObj()`（table/userdata）照旧为真。
local function mkEdge(parent, inset)
  local i = inset or 0
  local strips = {}
  local shown = true
  local function strip(a1, x1, y1, a2, x2, y2, w, h)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetPoint(a1, parent, a1, x1, y1)
    t:SetPoint(a2, parent, a2, x2, y2)
    if w ~= nil then pcall(t.SetWidth, t, w) end
    if h ~= nil then pcall(t.SetHeight, t, h) end
    solid(t, 1, 1, 1, 1)
    table.insert(strips, t)
    return t
  end
  strip("TOPLEFT", i, -i, "TOPRIGHT", -i, -i, nil, 1)
  strip("BOTTOMLEFT", i, i, "BOTTOMRIGHT", -i, i, nil, 1)
  strip("TOPLEFT", i, -i, "BOTTOMLEFT", i, i, 1, nil)
  strip("TOPRIGHT", -i, -i, "BOTTOMRIGHT", -i, i, 1, nil)
  local e = { strips = strips, inset = i }
  e.SetVertexColor = function(self, r, g, b, a)
    local k
    for k = 1, table.getn(strips) do pcall(strips[k].SetVertexColor, strips[k], r, g, b, a or 1) end
  end
  e.SetAlpha = function(self, a)
    local k
    for k = 1, table.getn(strips) do pcall(strips[k].SetAlpha, strips[k], a) end
  end
  e.Show = function(self)
    shown = true
    local k
    for k = 1, table.getn(strips) do pcall(strips[k].Show, strips[k]) end
  end
  e.Hide = function(self)
    shown = false
    local k
    for k = 1, table.getn(strips) do pcall(strips[k].Hide, strips[k]) end
  end
  e.IsShown = function(self) return shown end
  return e
end

-- 自绘小按钮（项目范式：纯 Lua、金边、无字体时也画得出字）
local function mkBtn(parent, w, h, text, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0.14, 0.12, 0.07, 1)
  local edge = mkEdge(b, 0)
  edge:SetVertexColor(0.62, 0.52, 0.20, 1)
  b.ehBtnEdge = edge
  local fs = font(b)
  -- ★文字**真正居中**（水平 + 垂直都显式声明：本客户端不给 JustifyV 时会按默认基线画，
  --   「x」这种单字符看着就偏 —— 用户报「x 在按钮位置没居中」）
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(fs.SetJustifyH, fs, "CENTER")
  pcall(fs.SetJustifyV, fs, "MIDDLE")
  fs:SetText(text)
  pcall(fs.SetTextColor, fs, 0.95, 0.90, 0.78)
  b.label = fs
  if type(onClick) == "function" then b:SetScript("OnClick", onClick) end
  return b
end

B.mkBtn = mkBtn

-- 类型图标加载（唯一口）：本客户端的图标路径有两种写法 —— 宏图标表给的是 Unreal 资产路径
--   `/Game/Interface/Icons/<名>_TEX`（doc/图标路径清单.txt 逐条核过 8 个名字都在），而容器/
--   装备那些是 `Interface\Icons\<名>`。★真机报障「图标行全是 ?」⇒ 一个字节都不硬猜：
--   逐个写法 SetTexture 后**读回自证**（只判非空 —— 本客户端会把路径归一，与原串比 = 天天假报），
--   第一个读回非空的就当选中；两种都空 ⇒ 如实记一行（B.catIconWhy），绝不静默。
local function catIconSet(tex, name)
  if isObj(tex) == false then return nil end
  -- ★★★0.3.26：顺位 = **自带（media\<基础名>）→ 客户端 UE 资产路径 → 客户端归档路径**
  --   （前两条都可能拿不到；逐条 `SetTexture` 后**读回自证**，第一条读回非空的当选；
  --    `B.RES[name]` 是建窗期 `B.resScan` 算好的结果，没扫过就跳过这一档 = fail-open）
  local forms = {}
  local own = B.RES[name]
  if type(own) == "string" and own ~= "" then forms[table.getn(forms) + 1] = own end
  forms[table.getn(forms) + 1] = "/Game/Interface/Icons/" .. name .. "_TEX"
  forms[table.getn(forms) + 1] = "Interface\\Icons\\" .. name
  local i
  for i = 1, table.getn(forms) do
    pcall(tex.SetTexture, tex, forms[i])
    local ok, got = pcall(tex.GetTexture, tex)
    if ok and type(got) == "string" and got ~= "" then
      B.catIconWhy = forms[i]
      return forms[i]
    end
  end
  B.catIconWhy = name .. " (两种写法都读不回贴图)"
  return nil
end


-- ★★★0.3.15 格框美术 = **参考插件那张「白色圆角边框 + 透明背景」**（用户：「白包边框能否参考图片内的
--   边框使用白色搭配透明背景?」）。素材从参考插件的 `media\BagSlot2.tga` **逐字节复制**进本插件自带目录
--   （`addons\EH_Bag\media\slotframe.tga`）⇒ 零依赖：别人没装那个参考插件也照样显示
--   （项目铁律「插件要绝对独立，依赖的东西要复制到插件内自己载入」；出处见该目录 README.txt）。
--   ★几何（从那张图实测得来，别再猜）：画布 **64×64**、画框只占中间 **39×39**
--     （alpha>32 的 bbox = x 12..50 / y 13..51）⇒ 「画框外缘正好落在格子边上」的绘制边长 = 格子 × `B.SLOT_K`。
--     旧写法 `64 / 37` 是 UI-Quickslot2 那张环的比例，换成这张图会外扩约 5%。
--   ★写法带 `.tga` 后缀：本插件 `media\Flags\<名>.tga` 就是这么载入的（本项目在案：插件目录里的散装
--     文件要写扩展名，不带后缀是给客户端归档里的美术用的）。
B.SLOT_TEX = "Interface\\AddOns\\EH_Bag\\media\\slotframe.tga"
B.SLOT_K = 64 / 39
-- ★★★0.3.16 底色 = **同一条轮廓的圆角实心底**（用户：「图5,装备染色之后.所在的格子背景好像有个
--   四个角比较突兀排查下是哪个影响」）：0.3.15 的底色是**整格正方形**（TOPLEFT/BOTTOMRIGHT 拉到格子边），
--   而格框是**圆角**的 ⇒ ① 正方形的四个角从圆角框的弯角外露出来 = 那四个「突兀的角」；
--   ② 底色与框只要差一个像素，就会在某一侧漏出一条彩色边 —— 用户报的「染色边框好像加错位置」
--      （对真机截图逐像素量过：框本身没画错，是**底色探出了框外**约 1 逻辑像素）。
--   ⇒ 底色改用 `media\slotfill.tga`：由 `slotframe.tga` **逐行按画框最左/最右填满**派生出的实心形状
--     （生成脚本 `tmp/mk_slotfill.js`，读回自证 = 轮廓与画框逐行一致、四角仍透明）
--     ⇒ **底色与框同形 · 同锚点（CENTER）· 同尺寸（格子 × B.SLOT_K）** ⇒ 结构上不可能再错位、也不可能有方角。
--   ★颜色写纯白，由 `applyFillTint` 染品质色（与框同一份颜色来源）。
B.SLOT_FILL = "Interface\\AddOns\\EH_Bag\\media\\slotfill.tga"
-- ★★★0.3.16 空格/普通品质的框**不再是纯白**（用户：「图四参考右边的边框.背包空格背包边框白色稍微暗一点」）：
--   纯白（1,1,1）在暗背景上太抢眼；**这条是唯一来源**；品质色（≥2）与悬停金框不受影响。
B.SLOT_DIM = 0.72
-- ★★★0.3.18 圆角辉光（用户：「图2 我看透明辉光的背景是生效了的.然后装备染色采用这个辉光染色效果」）：
--   参考插件 OneBag 的 `colors.glow` 一路 = 客户端 `UI-ActionButton-Border` + **ADD** + alpha 0.8
--   （0.3.17 逐像素量过：框 3px + 向内偏色 +81→+53→+32→+10→0，约 6~8px 的衰减带 = **泛光**，不是实色填充）。
--   ★而客户端容器模板**自带**的 `HighlightTexture = ButtonHilight-Square`（ADD）与
--     `PushedTexture = UI-Quickslot-Depress` 都是**方框**贴图 ⇒ 套在我们的**圆角**框上就是「外方内圆」——
--     用户报的「外层其实还有一个小边框 / 空格有两层边框」的真因（0.3.9 只收了 NormalTexture）。
--   ⇒ 两条一起做：① 那两张方框贴图也**收起**；② 自带一张**同轮廓**的圆角辉光 `slotglow.tga`
--     （由 `slotframe.tga` 派生，生成脚本 `tmp/mk_slotglow.js`：框上最亮 · 向内渐弱 · 向外只留一点点 ·
--      画布四角透明），按品质染色、ADD 压在图标之上。
B.SLOT_GLOW = "Interface\\AddOns\\EH_Bag\\media\\slotglow.tga"
B.GLOW_A = 0.7225          -- 品质辉光强度（★0.3.31e 单通道：写值 = 观感本身、不再平方 ⇒ 取旧基准 0.85 的平方 ⇒ 稳态观感与 0.3.30 逐值相同；0.3.20 的「与悬停同一把尺子」照旧）
B.GLOW_A_HOVER = 0.7225    -- 悬停辉光强度（与品质档同值 ⇒ 悬停与品质的差别**只有颜色**；要单独调悬停只改这一处）
-- ★★★0.3.18b：空格的白框 = **一圈更暗的框**（用户看完 0.3.18 的截图后选定「留一圈更暗的框（内部底块仍全透明）」）——
--   0.3.18 那一版是 **0 = 完全透明**（用户原话「默认空格…把白色的边框设置透明色」），真机截图逐像素核过
--   「空格一个像素都不画」（整行只有有物品的格子才有框边）⇒ 按用户指令改成留框。
--   ★**内部那层底色块照旧全透明**（`applyFillTint(..., 0)`）⇒ 观感 = 只有一圈暗框、里面透出背板。
--   ★唯一来源：这个常量只此一处，`applySlotTint(btn, B.SLOT_DIM, …, B.SLOT_EMPTY_A)` 只此一处调用。
B.SLOT_EMPTY_A = 0.35

-- 格框染色（空格/白装 = **白框**、悬停 = 金框、品质 ≥2 = 品质色；三处格子共用同一把尺子）
-- ★★★0.3.27 真因修复（用户：「仔细看方格边框左右两排空格边框是不同的…右边的样式是在鼠标获取焦点,离开后的样式。
--   左边是打开背包不做任何动作的样式。需要调整为初始就是右边的样式」）：
--   ★事实（**两轮**真机现象**唯一**自洽的解释，别再猜）：本客户端把**顶点色第 4 参**与 `SetAlpha`
--     **相乘**，而这两个通道的**落地时机不一样** —— **顶点色在「刚开窗」那一拍就落地，`SetAlpha` 不落地**
--     （纹理保持建仓默认 1）。
--     · 0.3.25 之前（两个通道都写 a）：初始 = 顶点 0.35 **落地** × SetAlpha 0.35 **不落地(=1)** = **0.35**
--       （= 0.3.25 用户点名的「图1 是正确的」）；悬停离开后 = 0.35 × 0.35 ≈ 0.12（= 同一位用户报的「变淡」）。
--     · 0.3.25 之后（顶点恒 1、alpha 全押 `SetAlpha`）：初始 = 1 × **1** = **纯白**（= 本轮用户报的「左边那排」）；
--       悬停离开后 = 1 × 0.35 = **0.35**（= 本轮用户点名的「右边才是要的」）。
--     ⇒ 两次报障点名的「要的观感」是**同一档 0.35**，错的永远是**初始那一拍**。
--   ⇒ 定案：**alpha 走顶点色第 4 参**（它两态都落地），**`SetAlpha` 恒显式写 1**
--     （把那个乘数钉成 1 ⇒ 无论它落不落地都不参与缩放）⇒ **初始 == 悬停离开后 == `B.SLOT_EMPTY_A`**。
--   ★为什么不改回「两个通道都写 a」：悬停离开后两个通道都落地 ⇒ 0.35 × 0.35 ≈ 0.12（0.3.25 那条报障复发）。
--   ★为什么不继续「顶点恒 1 + 由 `SetAlpha` 承担 alpha」：初始那一拍 `SetAlpha` 不落地 ⇒ 纯白（本轮报障）。
--   ★不动的邻居（**有意为之，不是漏改**）：`applyGlowTint`（辉光）两通道都写同一值 = 既有观感
--     （用户没报它，改了就是一次没人要的视觉变化）；`applyFillTint`（底色）只写顶点色、
--     不透明度本来就是 0/1 两档，不受相乘影响。
--   ★配套保险（建仓初值，见 `newItemButton` 的 `slotArt`）：格框一建出来就写**空格默认态**
--     （`B.SLOT_DIM` + `B.SLOT_EMPTY_A`）⇒ 万一「刚开窗」那一拍整拍写入都没落地，屏上也是正确亮度。
local function applySlotTint(btn, r, g, b, a)
  if isObj(btn.ehSlot) == false then return end
  pcall(btn.ehSlot.SetVertexColor, btn.ehSlot, r, g, b, a or 1)
  pcall(btn.ehSlot.SetAlpha, btn.ehSlot, 1)
end

-- ★0.3.18 辉光的**唯一写口**（ADD 混合 + 强度走 SetAlpha）。
-- ★★★0.3.21 真因修复（用户：「装备染色的边框1px.初始未生效,但是在鼠标悬浮获取焦点之后才生效」）：
--   旧写法是「先写属性、后 Show」，而辉光建出来就是 `Hide` 的 ⇒ 第一次绘制是在**隐藏态**里写
--   `SetVertexColor`/`SetAlpha`，本客户端**隐藏态的属性写入不落地**（底色 `ehFill` 从不 Hide，
--   所以它一直正常 —— 这正是「只有边框不见、底色照旧」的原因），于是这一格在鼠标扫过
--   （那时纹理已经是可见态）之前**一直画不出辉光** = 用户看到的「初始未生效、悬浮后才生效」。
--   ⇒ 两条一起做：
--     ① **顺序：先 `Show` 再写属性**（属性必须在可见态落笔）—— 顺序即判据；
--     ② **静默态只把 alpha 归 0，不再 `Hide`**（`Hide` 之后又要 `Show` 的那条路就是本 bug 的策源地）。
--        代价如实记：空格子的辉光纹理常驻显示（一层 alpha=0 的 ADD 纹理），绘制开销可忽略；
--        关窗时父帧 `Hide` ⇒ 纹理随之不可见，关断四件事不受影响。
--   ★两个通道都写（与 `applySlotTint` 同一条 idiom）：顶点色 alpha + `SetAlpha`，真机认哪个都行。
-- ★★★0.3.30 辉光「亮度归一」**已按用户要求整体撤销 —— 不要调暗**
--   用户原话：「**查看最近一次参考蓝色边框的样式调暗边框亮度问题.调回去.不要调暗**」。
--   ★0.3.29 当年做了什么（**教训留着、代码不留**）：以稀有(蓝)为参考色，按 `(参考色亮度 ÷ 本颜色亮度) ^ 0.5`
--     把每一档**写进去的 α** 缩一遍，让「有效 α² × 颜色亮度」五档相等（写值 α = 蓝 0.85 · 绿 0.65 ·
--     紫 0.88 · 橙 0.69 · 悬停金 0.56）—— 观感确实齐了，**代价 = 所有比蓝亮的档一律被调暗**
--     （悬停金的有效透明度 0.72 → 约 0.31）⇒ 用户点名不要这个。
--     ★当初为什么会走这条路：ADD 混合抬升的是**颜色自己的亮度**（Rec.601，鲜丽档实算）：
--       稀有(蓝) (0,0.382,1) = 0.338 ｜ 优秀(绿) (0,1,0) = 0.587 ｜ 史诗(紫) = 0.315
--       传说(橙) = 0.519 ｜ 悬停金 (0.95,0.80,0.25) = 0.783
--     ⇒ 同一个 α 下**绿格比蓝格亮 1.7 倍**（真机截图里「绿框又粗又亮、蓝框细细一条」）。
--   ★撤销口径 = **α 原样写下去**（品质档 `B.GLOW_A`、悬停档 `B.GLOW_A_HOVER`，两档仍同值 ⇒ 0.3.20 那条
--     「机制和悬浮辉光相同效果,只是颜色不同而已」的**颜色**口径不变）；归一那一套（`B.GLOW_REF_Q` ·
--     `B.GLOW_POW` · `B.GLOW_L_MIN` · `B.GLOW_A_MAX` · `B.glowRefLuma`）**一并删除**，不留死代码、
--     也不留「有键无代码」的迷惑项。
--   ★★★**必读的代价（如实报备：0.3.28 那条报障会回来）**：亮色档（绿 / 橙 / 悬停金）又会比蓝档看着更亮更粗。
--     要「各档一样细」就只能做归一，而**按参考色归一 = 调暗亮色**（本次被否掉的就是这条）；**唯一不调暗的做法**
--     是把参考色换成**最亮那一档**（把暗色往亮里抬、上限 1 ⇒ 蓝变亮，而不是绿变暗）—— 那是另一个决定，
--     **未经用户点头不许加**。
--   ★`B.glowAlpha(r,g,b,a)` **仍留着**：它是**唯一写口** `applyGlowTint` 里的**唯一换算点**，现在只做
--     「归一化 + 上限 1」（等价于原样）⇒ 以后要再归一（或改走「按最亮档归一」）**只改这一个函数**，
--     调用点一个字节都不用动。
B.lumaRGB = function(r, g, b)
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return 0 end
  return 0.299 * r + 0.587 * g + 0.114 * b
end
-- ★0.3.30：**归一已撤销 ⇒ 这里不再按颜色亮度缩放，只夹取**（见上方长注释；要再归一就只改这一个函数）
B.glowAlpha = function(r, g, b, a)
  local base = tonumber(a) or 0
  if base <= 0 then return 0 end
  if base > 1 then base = 1 end
  return base
end
-- 读值/播报用的薄壳（与真正画上去的同一条路：`vividRGB(qualRGB(q))` → `glowAlpha`）
B.glowAlphaOfQ = function(q, base)
  local r, g, b = B.vividRGB(qualRGB(q))
  return B.glowAlpha(r, g, b, base)
end

local function applyGlowTint(btn, r, g, b, a)
  if isObj(btn.ehGlow) == false then return end
  -- ★0.3.30：这里仍是**全项目唯一的一处 α 换算**（`B.glowAlpha`）—— 但 0.3.29 的「亮度归一」已按用户要求
  --   撤销 ⇒ 现在是**原样写基准值**（不再调暗亮色档；经过与撤销原因见上方长注释）
  a = B.glowAlpha(r, g, b, a)
  if (a or 0) <= 0 then
    -- ★0.3.31e 单通道：静默 = 顶点 α 0；`SetAlpha` 恒显式写 1（初始 == 悬停恢复，与 0.3.27 空格框同一配方）
    pcall(btn.ehGlow.SetVertexColor, btn.ehGlow, 0, 0, 0, 0)
    pcall(btn.ehGlow.SetAlpha, btn.ehGlow, 1)
    return
  end
  pcall(btn.ehGlow.Show, btn.ehGlow)
  -- ★0.3.31e 单通道：alpha **只走顶点色第 4 参**（它两态都落地），`SetAlpha` 恒钉 1 ⇒ 有效观感 = 写值本身（不再平方）
  pcall(btn.ehGlow.SetVertexColor, btn.ehGlow, r, g, b, a)
  pcall(btn.ehGlow.SetAlpha, btn.ehGlow, 1)
end

-- ★★★整格底色（0.3.7；用户：「背包物品……需要对物品进行稀有度着色」+ 选定「整格底色按品质染色」）：
--   照参考插件的做法 —— 它把**槽位美术**（BagSlot）按品质染色 ⇒ 整格一眼看出绿/蓝/紫/橙。
--   我们等效地染 `btn.ehFill`（那格不透明的暗底），并**只对品质 ≥2 生效**（参考的 `special` 就是
--   `quality > 1`）⇒ 白装/灰装保持中性底色，不会把「值得注意的」淹没。
--   ★同一件事只有一个门：`c.edges`（菜单「格框染品质」）—— 关掉 = 底色与外框都回中性。
local FILL_DARK = { 0.05, 0.05, 0.05, 0.85 }
-- ★★★0.3.10：底色亮度系数 0.55 → **0.85**（用户：「物品稀有等级染色颜色高亮点」）。
-- ★★★0.3.13：**这个常量退休了** —— 亮度系数搬进 `B.TINTS` 的档位表（标准档 k = 0.85 与这里同值，
--   所以「标准档」= 0.3.10~0.3.12 的观感一字不差）；默认档是**鲜丽**（`k = 1.00` + 提纯变换）。
--   要再亮/再暗就改那张表（唯一来源），**别在这里再加第二个系数**（两处口径 = 下一个漏改点）。

local function applyFillTint(btn, r, g, b, a)
  if isObj(btn.ehFill) == false then return end
  pcall(btn.ehFill.SetVertexColor, btn.ehFill, r, g, b, a or 1)
end

-- 物品格子：优先继承客户端模板（那样悬停/冷却/品质色都是原生的），
-- 模板不存在或不认（pcall 失败）就自建一套等价外观 —— 两条路最终都写进同一组句柄。
local function newItemButton(parent, bag, slot)
  local name = nil
  if bag >= 0 then
    name = "EH_BagItem" .. strVal(bag) .. "_" .. strVal(slot)
  else
    name = "EH_BagItemM" .. strVal(-bag) .. "_" .. strVal(slot)
  end
  local btn
  local ok = pcall(function()
    btn = CreateFrame("Button", name, parent, "ContainerFrameItemButtonTemplate")
  end)
  if not ok then btn = nil end
  local selfMade = false
  -- ★自建图标句柄走 local 传递，绝不回读「可能没设过」的字段（宽容桩里未设字段会返回函数）
  local ownIcon
  local cell0 = B.cfg().cell or DEF.cell
  if btn == nil then
    local ok2
    ok2, btn = pcall(CreateFrame, "Button", name, parent)
    if not ok2 or btn == nil then return nil end
    selfMade = true
    B.selfMade = (B.selfMade or 0) + 1
    local icon = btn:CreateTexture(nil, "BORDER")
    -- ★图标**居中 + 整格**（cell × B.ICON_K，0.3.9 起 = 1）：与客户端 ItemButtonTemplate 同口径 ——
    --   图标铺满格位，**那一圈环画在图标之上**（见下方 slotArt 的层）⇒ 图标不再比格框小一圈。
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetWidth(cell0 * B.ICON_K)
    icon:SetHeight(cell0 * B.ICON_K)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
    ownIcon = icon
  end
  -- ★EmberVeil 上模板自带的 NormalTexture 会在格子正中画一个方块 ⇒ 熄掉，改用经典格框
  if type(btn.SetNormalTexture) == "function" then pcall(btn.SetNormalTexture, btn, "") end
  if type(btn.GetNormalTexture) == "function" then
    local okN, nt = pcall(btn.GetNormalTexture, btn)
    if okN and isObj(nt) then
      pcall(nt.SetTexture, nt, nil)
      pcall(nt.Hide, nt)
    end
  end
  -- ★★★0.3.18：模板自带的另外两张**方框**贴图一起收起（用户：「外层其实还有一个小边框存在 /
  --   空格有两层边框」的真因）：`HighlightTexture = ButtonHilight-Square`（ADD 方框）与
  --   `PushedTexture = UI-Quickslot-Depress`（白方框）——它们的形状是**方**的，我们的框是**圆角**的，
  --   叠在一起就是「外方内圆」两层。★收法照 0.3.9 收 NormalTexture 那一套（**两条腿都做**：
  --   只 SetXxx("") 在某些客户端仍会画出白底，只 Hide 又会被客户端下次 SetXxx 顶回来）。
  if type(btn.SetHighlightTexture) == "function" then pcall(btn.SetHighlightTexture, btn, "") end
  if type(btn.GetHighlightTexture) == "function" then
    local okH, ht = pcall(btn.GetHighlightTexture, btn)
    if okH and isObj(ht) then
      pcall(ht.SetTexture, ht, nil)
      pcall(ht.Hide, ht)
    end
  end
  if type(btn.SetPushedTexture) == "function" then pcall(btn.SetPushedTexture, btn, "") end
  if type(btn.GetPushedTexture) == "function" then
    local okP, pt = pcall(btn.GetPushedTexture, btn)
    if okP and isObj(pt) then
      pcall(pt.SetTexture, pt, nil)
      pcall(pt.Hide, pt)
    end
  end
  -- ★整格暗底（空格也看得见格子，不用纯黑方块）
  --   ★★★0.3.14 **内缩必须为 0**（用户：「装备品质染色三个级别设置了但是对装备内的染色一点作用都没」）：
  --     这一层就是「整格品质底色」，而图标是**不透明**的、边长 = 格子 × `B.ICON_K`(0.9) 居中
  --     ⇒ 图标四周只留 5% 的边。旧写法内缩 **2px**（格子 37 时上下共 4px > 图标让出的 3.7px）
  --     ⇒ 底色被图标**整片盖住** = 换档看得见变化才怪。★判据 = 「底色的边长 ≥ 图标的边长」。
  -- ★★★0.3.16：底色 = **圆角实心底**（`B.SLOT_FILL`），**与格框同锚点同尺寸**（CENTER / 格子 × B.SLOT_K）
  --   —— 旧写法「整格正方形」的方角会从圆角框外露出来（用户报「四个角突兀」/「边框加错位置」）。
  local fill = btn:CreateTexture(nil, "BACKGROUND")
  local fk = B.SLOT_K
  fill:SetWidth((B.cfg().cell or DEF.cell) * fk)
  fill:SetHeight((B.cfg().cell or DEF.cell) * fk)
  fill:SetPoint("CENTER", btn, "CENTER", 0, 0)
  pcall(fill.SetTexture, fill, B.SLOT_FILL)
  -- ★建仓默认就**透明**（中性格底不铺色；真值每拍由 paintButton 写）
  pcall(fill.SetVertexColor, fill, 0.05, 0.05, 0.05, 0)
  btn.ehFill = fill
  -- ★白框（0.3.15：美术换成参考插件那张白色圆角边框；品质色在 paintButton 里染）
  --   ★0.3.9：层 = **ARTWORK（画在图标之上）** —— 客户端把 `$parentNormalTexture` 放在图标那一层之上
  --   （图标在 XML 里是 BORDER）⇒ 图标填满格、框压在图标边缘，两者天然「大小匹配」。
  local slotArt = btn:CreateTexture(nil, "ARTWORK")
  local art = B.SLOT_K
  slotArt:SetWidth((B.cfg().cell or DEF.cell) * art)
  slotArt:SetHeight((B.cfg().cell or DEF.cell) * art)
  slotArt:SetPoint("CENTER", btn, "CENTER", 0, 0)
  pcall(slotArt.SetTexture, slotArt, B.SLOT_TEX)
  -- ★★★0.3.27：建仓初值 = **空格默认态**（`B.SLOT_DIM` + `B.SLOT_EMPTY_A`），**不是纯白**。
  --   理由见 `applySlotTint` 上方那段（两个 alpha 通道的落地时机不同）：建仓就把正确初值写下去
  --   ⇒ 即使「刚开窗」那一拍整拍写入都没落地，屏上也是**用户点名的那个初始观感**；
  --   旧写法写 1,1,1,1 ⇒ 那一拍画出来就是用户报的「左边那排亮框」（有物品的格子会在同一拍被
  --   `paintButton` 覆盖成自己的颜色，一帧内看不出）。
  pcall(slotArt.SetVertexColor, slotArt, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_EMPTY_A)
  btn.ehSlot = slotArt
  -- ★★★0.3.18 辉光层（用户要的「辉光染色」）：**同轮廓**的圆角辉光 + **ADD** 混合，画在框**之上**
  --   层序：图标 BORDER < 格框 ARTWORK < 辉光 OVERLAY（与参考插件「泛光压在图标之上」同一口径）。
  --   建出来就是**收起 + alpha 0** 的（真值每拍由 paintButton 写，绝不靠客户端默认值）。
  local glow = btn:CreateTexture(nil, "OVERLAY")
  glow:SetWidth((B.cfg().cell or DEF.cell) * B.SLOT_K)
  glow:SetHeight((B.cfg().cell or DEF.cell) * B.SLOT_K)
  glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
  pcall(glow.SetTexture, glow, B.SLOT_GLOW)
  pcall(glow.SetBlendMode, glow, "ADD")
  -- ★0.3.21：建出来就是**显示态 + 全透明**（**不 Hide**，两个 alpha 通道一起归 0）——
  --   本客户端在隐藏态写属性不落地（见 applyGlowTint 上方那段：那正是「初始没有染色边框」的真因）。
  pcall(glow.SetVertexColor, glow, 1, 1, 1, 0)
  -- ★0.3.31e：建仓就把乘数通道钉成 1（顶点 α 0 保持全透明；写 0 反而让「初始打开读回 1」与「稳态读回写值」对不上）
  pcall(glow.SetAlpha, glow, 1)
  btn.ehGlow = glow
  -- 句柄分派（显式两分支，绝不 or 回读）
  if ownIcon ~= nil then
    btn.ehIcon = ownIcon
  elseif name ~= nil then
    btn.ehIcon = _G[name .. "IconTexture"]
  else
    btn.ehIcon = nil
  end
  -- ★模板自带的图标也**居中 + 略小**（两条路同一外观；缩放时 B.layout 再按新格子重摆一次）
  if isObj(btn.ehIcon) and ownIcon == nil then
    pcall(btn.ehIcon.ClearAllPoints, btn.ehIcon)
    pcall(btn.ehIcon.SetPoint, btn.ehIcon, "CENTER", btn, "CENTER", 0, 0)
    pcall(btn.ehIcon.SetWidth, btn.ehIcon, cell0 * B.ICON_K)
    pcall(btn.ehIcon.SetHeight, btn.ehIcon, cell0 * B.ICON_K)
    btn.ehIconK = cell0
  end
  -- ★★★数量一律用**我们自己的** FontString：客户端模板自带的 `_G[name.."Count"]` 在本客户端
  --   **一个像素都不画**（真机：背包/银行/装备格子一个数字都没有 —— 用户报「装备物品的数量信息也没了」）。
  local ownCount = font(btn)
  ownCount:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
  pcall(ownCount.SetJustifyH, ownCount, "RIGHT")
  pcall(ownCount.SetTextColor, ownCount, 1, 1, 1)
  -- 模板自带的数量 FontString：**藏掉**（它不渲染，留着只会与我们的重叠）
  if name ~= nil then
    local tc = _G[name .. "Count"]
    if isObj(tc) then
      pcall(tc.SetText, tc, "")
      pcall(tc.Hide, tc)
    end
  end
  btn.ehCount = ownCount
  if name ~= nil then
    btn.ehCooldown = _G[name .. "Cooldown"]
  else
    btn.ehCooldown = nil
  end
  -- ★0.3.18 冷却倒计时数字：客户端与参考插件**都只有扫动动画、没有数字**（OneBag 里一行冷却代码都没有）
  --   ⇒ 这层数字是本插件加的，走同一个格子的 FontString（OVERLAY，居中、暖白）。
  --   ★★★0.3.19：**必须把它抬到冷却 Model 之上** —— 模板那个 `$parentCooldown` 是同一个按钮的子件
  --   （Model），同层时 Model 画在按钮自己的 region 之上 ⇒ 数字被那一圈扫动整个盖住/压暗
  --   （用户报「未能正确显示倒计时」的一半原因）。抬高**子件**是唯一有效路（抬高父帧不带动子件）。
  btn.ehCDText = font(btn)
  pcall(btn.ehCDText.SetPoint, btn.ehCDText, "CENTER", btn, "CENTER", 0, 0)
  pcall(btn.ehCDText.SetJustifyH, btn.ehCDText, "CENTER")
  pcall(btn.ehCDText.SetTextColor, btn.ehCDText, 1, 0.95, 0.6)
  if type(btn.ehCDText.SetFrameLevel) == "function" then
    local lv0 = 0
    if type(btn.GetFrameLevel) == "function" then
      local okL, vL = pcall(btn.GetFrameLevel, btn)
      if okL and type(vL) == "number" then lv0 = vL end
    end
    pcall(btn.ehCDText.SetFrameLevel, btn.ehCDText, lv0 + 8)
  end
  -- 压着一圈深色扫动 ⇒ 加一层黑描边（读不出这两个 API 就照旧画，绝不因为描边失败就不画数字）
  pcall(btn.ehCDText.SetShadowColor, btn.ehCDText, 0, 0, 0, 1)
  pcall(btn.ehCDText.SetShadowOffset, btn.ehCDText, 1, -1)
  pcall(btn.ehCDText.SetText, btn.ehCDText, "")
  pcall(btn.ehCDText.Hide, btn.ehCDText)
  btn.ehBag = bag
  btn.ehSlot_ = slot
  btn:SetWidth(B.cfg().cell or DEF.cell)
  btn:SetHeight(B.cfg().cell or DEF.cell)
  if type(btn.EnableMouse) == "function" then pcall(btn.EnableMouse, btn, true) end
  return btn
end

-- ===== 点击契约（照 OneBag：全部自己在 Lua 里实现，绝不信 FrameXML 的点击脚本）=====
-- ★HOLD = 「这一拖是我拖起来的」的账（0.3.7 起还要记**物品信息**：拆分确认窗靠它算数量/名字）。
--   ★被清成 nil 的每一个字段都要清干净（谁读谁判 nil）—— 半截记录比没有记录更危险。
local HOLD = { bag = nil, slot = nil, id = nil, name = nil, count = nil, quality = nil, bankMain = false, shift = false, downShift = false }

local function holdForget()
  HOLD.bag, HOLD.slot = nil, nil
  HOLD.id, HOLD.name, HOLD.count, HOLD.quality = nil, nil, nil, nil
  HOLD.bankMain = false
  HOLD.shift = false
  HOLD.downShift = false
end

local function holdSet(rec)
  HOLD.bag, HOLD.slot = rec.bag, rec.slot
  HOLD.id = rec.id
  HOLD.name = rec.name
  HOLD.count = rec.count
  HOLD.quality = rec.quality
  HOLD.bankMain = (rec.bankMain == true)
  -- ★修饰键**不在这里记**：pickUp 也被「光标空着时 Shift+左键 = 插链接」那条路调用，
  --   那里记下来的会是「链接意图」而不是「拖拽意图」⇒ 只由 OnDragStart（起拖）那一路单独盖。
  HOLD.shift = false
end

local function cursorHas()
  if type(CursorHasItem) ~= "function" then return false end
  local ok, has = pcall(CursorHasItem)
  return (ok and has) and true or false
end

-- ★修饰键的唯一读口（读不到 / 报错一律 = false）。
--   ★★★为什么要「起拖时记账」：拖拽是**跨好几拍**的动作，落格那一刻再去读 Shift 未必还读得到
--   （本客户端的修饰键状态在鼠标操作期间的可读性没有保证）；起拖那一刻玩家一定还按着 Shift
--   ⇒ OnDragStart 把结果记进 HOLD.shift，落格时按「记账 ∨ 实时读」取用（拿不到就退回实时读 = fail-open）。
local function shiftDown()
  if type(IsShiftKeyDown) ~= "function" then return false end
  local ok, v = pcall(IsShiftKeyDown)
  return (ok and v) and true or false
end

-- ===== 拖动/落格/拆分 取证环（有界 20 条、**落存档** ⇒ AI 能读「这一落到底读到了什么」）=====
--   ★与开合取证环（B.traceAdd 那条 30 条的环）**分开**：拖放是高频动作，混在一个环里
--   会把开合的证据冲掉。判据 =「代码没跑」与「条件没满足」必须能分开 —— 环里有 idrag/isplit
--   两行 = 处理器跑了且读到了东西；一行都没有 = 客户端压根没调我们的脚本。
function B.splitAdd(tag, extra)
  local c = B.cfg()
  if type(c.splitTrace) ~= "table" then c.splitTrace = {} end
  local t = c.splitTrace
  table.insert(t, string.format("%s %s [cur=%s hold=%s shift=%s]", strVal(tag), strVal(extra or ""),
    (cursorHas() and "1" or "0"), (HOLD.bag == nil) and "-" or (strVal(HOLD.bag) .. "," .. strVal(HOLD.slot)),
    (shiftDown() and "1" or "0")))
  while table.getn(t) > 20 do
    table.remove(t, 1)
  end
end

local function pickUp(rec)
  if rec == nil then return end
  if rec.bankMain == true and type(PickupInventoryItem) == "function" then
    pcall(PickupInventoryItem, rec.invSlot)
    holdSet(rec)
    return
  end
  if type(PickupContainerItem) ~= "function" then return end
  pcall(PickupContainerItem, rec.bag, rec.slot)
  if cursorHas() then
    holdSet(rec)
  else
    holdForget()
  end
end

local function useSlot(rec)
  if rec == nil then return end
  if type(UseContainerItem) == "function" then
    pcall(UseContainerItem, rec.bag, rec.slot)
  end
end

local function linkItem(link)
  if type(link) ~= "string" or link == "" then return end
  if type(ChatEdit_InsertLink) == "function" then
    if pcall(ChatEdit_InsertLink, link) then return end
  end
  if _G.ChatFrameEditBox ~= nil and type(_G.ChatFrameEditBox.Insert) == "function" then
    pcall(_G.ChatFrameEditBox.Insert, _G.ChatFrameEditBox, link)
  end
end

local function dressUp(link)
  if type(link) ~= "string" or link == "" then return end
  if type(DressUpItemLink) == "function" then pcall(DressUpItemLink, link) end
end

-- ===== 物品信息（沿用客户端默认行为 + 「延后读回」自证）=====
-- ★真机报障「物品信息显示空」（截图里就是一个空的黑框）：旧写法 `if pcall(tip.SetBagItem, …) then 显示 end`
--   把「调用没抛错」当成「填上了」—— 而本项目早有定案：本客户端 widget 的 Set* 方法**返回值不可信**
--   （`WTT:SetPlayerBuff` 返回恒 nil 却照旧把行填好）。⇒ **读完再决定**：客户端默认信息到底填了几行？
-- ★★★0.3.6 再改一次（用户：「背包内的物品提示和角色总览内的物品提示信息流程不同吗? 背包内的物品
--   提示工作异常. 和角色总览的内的图片 tooltip 信息展示相同.」）—— 两处都是真 bug：
--   ① **当场读回不算数**：本客户端 NumLines 有延迟（SetBagItem 之后立刻读常常是 0 行），旧写法当场
--      SetText 覆盖 ⇒ 把客户端本来填好的**完整**物品信息（属性/商人价/用法）换成我们那三行简版
--      = 用户眼里的「和总览那份简版气泡一样」。现在改成**两拍**：当场只 Show + 登记 B.tipPend，
--      过 B.TIP_WAIT 秒由 B.tipTick 复核 —— 读到内容就一个字都不动，仍读不出才写自建文本。
--   ② ★★★**Hide 只在「客户端口没内容 且 我们一个字都写不进去」时才发**：旧写法 `if wrote ~= true then Hide`
--      （wrote 只表示「我们写过 SetText」）把**客户端自己填好的那一路也一起藏了** ⇒ 真机 = 悬停背包物品
--      什么都不显示，而上一份气泡的残行还留在屏上（「和总览的一样」的另一半）。
--   最近一次判定记在 B.tipLast / B.tipWhy（`/ebag tip` 摊开）。
--   ★这两个助手写成 B 表字段（不是文件级 local）：主 chunk 的局部量有 200 上限，能不加就不加。
B.TIP_WAIT = 0.15
B.tipLines = function(tip)
  if type(tip.NumLines) ~= "function" then return nil end
  local ok, n = pcall(tip.NumLines, tip)
  if ok and type(n) == "number" then return n end
  return nil
end

-- 气泡第一行的**文本**（第二条读回口径）：NumLines 读不出时的兜底证据。
--   ★行 FontString 是客户端的 `<帧名>TextLeft1`（拿不到帧名就退回 GameTooltipTextLeft1）
B.tipLine1 = function(tip)
  local nm = nil
  if isObj(tip) and type(tip.GetName) == "function" then
    local okn, v = pcall(tip.GetName, tip)
    if okn and type(v) == "string" and v ~= "" then nm = v end
  end
  local fs = nil
  if nm ~= nil then fs = _G[nm .. "TextLeft1"] end
  if isObj(fs) == false then fs = _G.GameTooltipTextLeft1 end
  if isObj(fs) == false or type(fs.GetText) ~= "function" then return nil end
  local ok, v = pcall(fs.GetText, fs)
  if ok and type(v) == "string" then return v end
  return nil
end

-- ★★「到底填上了没有」的唯一判据（两条读回口径）：绝大多数情况 NumLines 说了算；
--   它读不出（本客户端有可能）才退回第一行文本。返回 has, judged —— **judged=false = 判不出**，
--   调用方必须按「判不出」处理（fail-open），绝不拿 Set* 的返回值当判据（本客户端 Set* 恒 nil）。
B.tipRead = function(tip)
  local n = B.tipLines(tip)
  if type(n) == "number" then return (n > 0), true end
  local txt = B.tipLine1(tip)
  if type(txt) == "string" then return (string.len(txt) > 0), true end
  return false, false
end

-- ★★★0.3.10：客户端**自己的**物品信息 = 两级写法（唯一实现，当场与复核两处共用）：
--   ① **容器口** —— 银行主格 `SetInventoryItem("player", invSlot)`、其余容器格（含钥匙链 -2）`SetBagItem(bag, slot)`
--      （与客户端自己的 `ContainerFrameItemButton_OnEnter` 逐字同口径：它也调 `GameTooltip:SetBagItem(parent:GetID(), this:GetID())`）；
--   ② **链接口** —— 容器口读不回内容时再试 `SetHyperlink(rec.link)`：这条是**总览气泡**一直在走的路，
--      真机截图实证它能出**完整**信息（标题 / 部位 / 伤害 / 属性 / 耐久 / 商人价）。
--   ⇒ 两级都试过才允许判「客户端填不上」；每级都 `ClearLines` + 重设 owner（绝不与上一份混行）。
--   返回 path（nil = 两级都没读回内容）, filled, has, judged, tried（试过哪几条，给取证口看）。
--   ★写成 B 表字段而不是文件级 local：主 chunk 局部量有上限，能不加就不加（同 tipRead 的做法）。
B.tipClientTry = function(tip, owner, rec)
  local has, judged
  local tried = {}
  if rec.bankMain == true and type(tip.SetInventoryItem) == "function" then
    table.insert(tried, "inv")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT")
    pcall(tip.SetInventoryItem, tip, "player", rec.invSlot)
    has, judged = B.tipRead(tip)
    if judged == true and has == true then return "inv", true, has, judged, "inv" end
  end
  if rec.bankMain ~= true and rec.bag ~= nil and type(tip.SetBagItem) == "function" then
    table.insert(tried, "bag")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT")
    pcall(tip.SetBagItem, tip, rec.bag, rec.slot)
    has, judged = B.tipRead(tip)
    if judged == true and has == true then return "bag", true, has, judged, "bag" end
  end
  if type(rec.link) == "string" and rec.link ~= "" and type(tip.SetHyperlink) == "function" then
    table.insert(tried, "hyper")
    if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
    pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT")
    pcall(tip.SetHyperlink, tip, rec.link)
    has, judged = B.tipRead(tip)
    if judged == true and has == true then return "hyper", true, has, judged, "hyper" end
  end
  return nil, false, has, judged, table.concat(tried, "+")
end

-- ===== 快照富化（0.3.24）：链接读不到时的「反查」 =====
-- ★★★真机取证（读存档 `EH_Bag.lua` 的 `chars[…]`）：**银行主格的记录有贴图、没有链接、名字是 "?"**
--   —— 本客户端 `GetInventoryItemLink("player", 40..63)` 对银行槽不给链接（`GetInventoryItemTexture` 正常）。
--   ⇒ 跨角色总览里银行物品只能掉进「? ×N 只读…」的自建兜底（用户截图就是这一格）；
--     背包段（`it`）同一份快照里 49 条**链接/名字齐全** ⇒ 问题只在「链接拿不到的那些格」。
--   ★修法四步，全都 fail-open、全都读回自证：
--     ① 名字：自建 tooltip 的第一行文本（至少不再显示 "?"）；
--     ② 容器口链接：`GetContainerItemLink(BANK_CONTAINER, slot)` 也试一次 ——
--        **必须与①的名字逐字相同才认**（拿不到证据就一个字节都不碰：存错链接 = 显示别人物品的信息）；
--     ③ 行里若带 `item:<id>` / `|Hitem:…|h` 就抠出来（有它就是最好的一条路：气泡能走客户端口）；
--     ④ 行兜底：仍旧没有链接 ⇒ 把这件物品的**行**存进快照 `rl`，总览气泡逐行画出来（行里带色码 ⇒ 品质色照旧）。
--   ★为什么必须存行：**别的角色**的物品在我们这儿，链接一缺就再没有别的信息源（读不到对方的容器）。
--   ★一律有界：每次快照最多反查 B.RICH_MAX 件 · 每件最多 B.RICH_LINES 行 · 每行最多 B.RICH_LEN 字符。
B.RICH_MAX = 24
B.RICH_LINES = 12
B.RICH_LEN = 64

-- 自建隐形 tooltip（与宿主 `Engine.lua` 的 `EVAL_HELP_WTT` **同一条已验证配方**：
--   先试带模板名，拿不到再退回匿名 CreateFrame）。
--   ★帧名 ≠ 函数名（项目铁律：具名帧会顶掉同名全局函数）；建一次复用、**永不 Show** ——
--   借玩家的 `GameTooltip` 读数会清空他正看的物品提示（项目在案的坑，WTT 隔离那条）。
B.readTipGet = function()
  local t = B.readTip
  if isObj(t) then return t end
  if type(CreateFrame) ~= "function" then return nil end
  local f = nil
  local ok, v = pcall(CreateFrame, "GameTooltip", "EH_BagReadTip", UIParent, "GameTooltipTemplate")
  if ok and isObj(v) then f = v end
  if f == nil then
    local ok2, v2 = pcall(CreateFrame, "GameTooltip", "EH_BagReadTip", UIParent)
    if ok2 and isObj(v2) then f = v2 end
  end
  if f == nil then return nil end
  pcall(f.Hide, f)
  B.readTip = f
  return f
end

-- 读自建 tooltip 第 i 行左列的文本。
--   ★只认**我们自己那个帧**名下的行（`<帧名>TextLeft<i>`）—— 绝不回退到 `GameTooltipTextLeft1`
--     （那是玩家正看的气泡，读它就是串味）。
B.readTipLeft = function(tip, i)
  if isObj(tip) == false or type(tip.GetName) ~= "function" then return nil end
  local okn, nm = pcall(tip.GetName, tip)
  if not okn or type(nm) ~= "string" or nm == "" then return nil end
  local fs = _G[nm .. "TextLeft" .. strVal(i)]
  if isObj(fs) == false or type(fs.GetText) ~= "function" then return nil end
  local ok, v = pcall(fs.GetText, fs)
  if ok and type(v) == "string" then return v end
  return nil
end

-- 按**字符**截断（★绝不用 string.sub 按字节 —— 汉字会被切半个，屏上就是乱码方块；项目在案）
B.readClip = function(s, n)
  if type(s) ~= "string" then return "" end
  if type(n) ~= "number" or n <= 0 then return s end
  local i, cnt, len = 1, 0, string.len(s)
  while i <= len do
    local b = string.byte(s, i)
    local step = 1
    if b >= 240 then step = 4
    elseif b >= 224 then step = 3
    elseif b >= 192 then step = 2 end
    if cnt >= n then return string.sub(s, 1, i - 1) end
    cnt = cnt + 1
    i = i + step
  end
  return s
end

-- 反查一件「链接读不到」的物品：bankMain 走 inventory 口、其余容器走容器口（与 B.tipClientTry 同口径）。
--   返回 true = 真读到了内容（rec 可能已补上 name / link / rl）。
B.richTry = function(bag, slot, rec)
  if type(rec) ~= "table" then return false end
  if (B.richN or 0) >= B.RICH_MAX then return false end
  local tip = B.readTipGet()
  if tip == nil or type(tip.SetOwner) ~= "function" then return false end
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.SetOwner, tip, UIParent, "ANCHOR_NONE")
  local okFill = false
  if rec.bankMain == true and type(tip.SetInventoryItem) == "function" then
    okFill = pcall(tip.SetInventoryItem, tip, "player", rec.invSlot or (39 + slot))
  elseif type(tip.SetBagItem) == "function" then
    okFill = pcall(tip.SetBagItem, tip, bag, slot)
  end
  if okFill ~= true then return false end
  local has, judged = B.tipRead(tip)
  if not (judged == true and has == true) then return false end
  B.richN = (B.richN or 0) + 1
  -- 行（有界）：行数优先 NumLines，读不出才逐行读到空
  local nM = B.RICH_LINES
  local ln = B.tipLines(tip)
  if type(ln) == "number" and ln < nM then nM = ln end
  local lines = {}
  local i
  for i = 1, nM do
    local s = B.readTipLeft(tip, i)
    if type(s) ~= "string" or s == "" then break end
    table.insert(lines, B.readClip(s, B.RICH_LEN))
  end
  if table.getn(lines) == 0 then return false end
  local first = lines[1]
  -- ① 名字：剥掉色码 / 链接标记，只留纯名字（后面两步都要拿它做校验）
  local nm = string.gsub(first, "|c%x%x%x%x%x%x%x%x", "")
  nm = string.gsub(nm, "|r", "")
  nm = string.gsub(nm, "|Hitem:[^|]*|h", "")
  nm = string.gsub(nm, "|h", "")
  nm = string.gsub(nm, "%[(.-)%]", "%1")
  if type(nm) == "string" and nm ~= "" then rec.name = nm end
  local why = "名字=" .. strVal(rec.name or "?")
  -- ② 容器口链接（名字逐字相同才认）
  if rec.bankMain == true and (type(rec.link) ~= "string" or rec.link == "")
    and type(GetContainerItemLink) == "function" then
    local okc, cl = pcall(GetContainerItemLink, bag, slot)
    if okc and type(cl) == "string" and cl ~= "" then
      if type(nm) == "string" and nm ~= "" and string.match(cl, "%[(.-)%]") == nm then
        rec.link = cl
        fillInfoFromLink(rec)
        why = why .. " ｜ 容器口链接(名字一致)"
      else
        why = why .. " ｜ 容器口有链接但名字对不上 ⇒ 不采用"
      end
    end
  end
  -- ③ 行里的 `item:<id>` / `|Hitem:…|h`
  local lk = string.match(first, "|H(item:[^|]*)|h")
  if lk == nil then lk = string.match(first, "(item:%d+[%d:]*)") end
  if lk ~= nil and (type(rec.link) ~= "string" or rec.link == "") then
    rec.link = lk
    fillInfoFromLink(rec)      -- 顺带补 id/品质（刚才那次 SetInventoryItem 已经把物品写进客户端缓存）
    why = why .. " ｜ 行里抠出链接 " .. strVal(lk)
  end
  -- ④ 行兜底（有界）
  if type(rec.link) ~= "string" or rec.link == "" then
    rec.rl = lines
    why = why .. " ｜ 无链接 ⇒ 存行 " .. strVal(table.getn(lines))
  end
  B.richWhy = "反查 " .. strVal(bag) .. "," .. strVal(slot) .. " ⇒ " .. why
  return true
end

-- ★★★0.3.11 真因（真机「背包物品信息一直是个空箱」的最后一块拼图）：
--   客户端模板 `ContainerFrameItemButtonTemplate` 自带 `<OnUpdate> ContainerFrameItemButton_OnUpdate(arg1)`，
--   而它每满 `TOOLTIP_UPDATE_TIME`(0.2s) 就调一次**它自己的** `ContainerFrameItemButton_OnEnter()`：
--     `GameTooltip:SetOwner(...)` + `GameTooltip:SetBagItem(button:GetParent():GetID(), button:GetID())`
--   —— 我们的格子挂在**共享容器** `ehContent` 下、又没有 ID ⇒ 这一下等于「**清空气泡**再填成空箱」，
--   而且**每 0.2s 来一次** ⇒ 我们刚写好的内容（无论客户端口的还是自建的）0.2s 后必被抹掉。
--   0.3.10 只补了「登记待办要叫节拍」，挡不住这条**客户端自己的**定时重设 ⇒ 真机上照旧是空箱。
--   ⇒ 两条一起做：① `bindItemButton` 里**接管 OnUpdate**（换掉模板那条，抹的动作不再发生）；
--     ② 下面这个「空箱重申」兜底：万一还有谁把气泡清空了，**只在首行无字时**按同一个填口补回来。
B.TIP_GUARD_GAP = 0.25   -- 重申节流（只在悬停那一格上跑，且只在气泡真的空了才写）
B.TIP_GUARD_MAX = 8      -- 每次悬停最多重申几次（有界：绝不无限重写）

-- 「气泡现在是空箱吗」= 与 `B.tipTick` 第 1 步**同一把尺子**（有字 ⇒ 有内容；有行无字 / 判不出 ⇒ 空箱）
B.tipBlank = function(tip)
  if tip == nil then return false end
  local txt = B.tipLine1(tip)
  if type(txt) == "string" and string.len(txt) > 0 then return false end
  local n = B.tipLines(tip)
  if type(n) == "number" and n > 0 and type(txt) ~= "string" then return false end
  return true
end

-- 物品信息取证环（有界 12 条、**落存档** ⇒ AI 自己读存档即可；与 splitTrace 分开，别互相冲掉）
B.tipTraceAdd = function(line)
  local c = B.cfg()
  if type(c.tipTrace) ~= "table" then c.tipTrace = {} end
  local t = c.tipTrace
  table.insert(t, strVal(line))
  while table.getn(t) > 12 do table.remove(t, 1) end
end

local function mkTip(owner, rec)
  local tip = _G.GameTooltip
  if tip == nil or type(tip.SetOwner) ~= "function" then return end
  B.tipLast = nil
  B.tipWhy = nil
  B.tipPend = nil
  pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT")
  local path, n, has, judged
  local wrote = false          -- 我们自己写了字（SetText 成功）
  local filled = false         -- 客户端自己的口**真填上了内容**（只有它才配 Show，且绝不许被我们覆盖）
  if rec == nil then
    path = "empty"
    if type(tip.SetText) == "function" then
      pcall(tip.SetText, tip, L("EMPTY"), 0.7, 0.7, 0.7)
      wrote = true
    end
  else
    -- ① 客户端**自己的**物品信息（沿用默认行为）：容器口 → 链接口（见 B.tipClientTry）
    local tried
    path, filled, has, judged, tried = B.tipClientTry(tip, owner, rec)
    -- ② 两级都没读回内容（**判不出**也算）⇒ **一个字都不写**，只登记延后复核待办。
    --   ★★★为什么不当场兜底：本客户端 NumLines 有延迟，刚 SetBagItem 完立刻读常常是 0 行
    --   ⇒ 当场 SetText 覆盖 = 把客户端本来填好的完整物品信息换成我们那三行简版。
    --   ★★★0.3.10 真因（用户：「背包内的信息箱提示还是空白的」）：**登记待办之后必须当场
    --   把节拍帧挂起来**（`B.pumpSync()`）—— 否则那一刻节拍通常是**摘着**的（背包窗开着、
    --   没有整理/拖拽/刷新待办）⇒ `B.tipTick` 永远不跑 ⇒ 客户端口填不上时**永远等不到兜底**
    --   ⇒ 屏上就留一个**空箱子**（我们的 Show 已经发出去了）。`B.viewPend` 同一处同样缺这一句。
    if filled ~= true then
      B.tipPend = { owner = owner, rec = rec, t = GetTime(), tried = tried }
      B.pumpSync()   -- ★真因修复：挂节拍（挂/摘只走这一个口）
      B.tipWhy = "客户端两级口（" .. strVal(tried) .. "）当场都读不回内容（"
        .. ((judged == true) and "0 行" or "判不出")
        .. "）⇒ 延后 " .. strVal(B.TIP_WAIT) .. "s 重问 + 再兜底"
      if type(tip.Show) == "function" then pcall(tip.Show, tip) end
      B.tipLast = { path = "pend", tried = tried, lines = B.tipLines(tip), has = B.tipRead(tip),
                    bag = rec.bag, slot = rec.slot, name = rec.name }
      return
    end
  end
  n = B.tipLines(tip)
  has = B.tipRead(tip)
  B.tipLast = { path = path, lines = n, has = has, bag = rec and rec.bag, slot = rec and rec.slot, name = rec and rec.name }
  -- ★★★Hide 只在「客户端口没内容 **且** 我们一个字都写不进去」时才发 ——
  --   旧写法 `if wrote ~= true then Hide` 把**客户端自己填好的那一路也一起藏了**
  --   （wrote 只表示「我们写过 SetText」）⇒ 真机 = 悬停背包物品什么都不显示，
  --   而上一份气泡的残行还留在屏上（用户报「背包内的物品提示和总览的一样」）。
  --   客户端真填上了 ⇒ 一律 Show，一个字节都不改。
  if filled ~= true and wrote ~= true then
    B.tipWhy = strVal(path) .. " 连标题都写不进去（SetText 不可用）"
    if type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    return
  end
  if type(tip.Show) == "function" then pcall(tip.Show, tip) end
end

-- ★★延后复核（由唯一节拍帧 B.pump 调；B.pumpNeed 在有待办时保持挂载）：
--   两条出口都如实记账 —— ① 客户端的行只是**延迟**填上的 ⇒ 一个字都不动（这才是「沿用客户端
--   默认行为」）；② 到点确实 0 行 ⇒ 才写我们自己的文本兜底（名字/数量/用法），连标题都写不进去
--   才 Hide（绝不留空箱子）。
function B.tipTick()
  local p = B.tipPend
  if p == nil then return end
  if GetTime() - p.t < B.TIP_WAIT then return end
  B.tipPend = nil
  local tip = _G.GameTooltip
  if tip == nil then return end
  local rec = p.rec
  -- ★★★0.3.10 第 1 步（**顺序即判据**）：**先只读、一个字节都不碰** ——
  --   客户端的行常常只是**延迟**填上来的，读到内容 ⇒ 认客户端口、原样 Show（这正是「沿用客户端默认行为」）。
  --   ★为什么这一读必须排在「重问客户端」之前：重问那一趟带 `ClearLines` ⇒ 排在前面会把**刚迟到的那份
  --   完整信息当场抹掉**，然后只能退回我们那三行简版 = 0.3.6 那条老雷原样复现（harness 专条守着）。
  local n0 = B.tipLines(tip)
  local txt0 = B.tipLine1(tip)
  local hasText0 = (type(txt0) == "string" and string.len(txt0) > 0)
  if hasText0 == true or (type(n0) == "number" and n0 > 0 and type(txt0) ~= "string") then
    B.tipLast = { path = "client", tried = p.tried, lines = n0, has = true,
                  bag = rec and rec.bag, slot = rec and rec.slot, name = rec and rec.name }
    B.tipWhy = "客户端口的行是**延迟**填上的（复核读到 " .. strVal(n0) .. " 行）⇒ 一个字都没动"
    if type(tip.Show) == "function" then pcall(tip.Show, tip) end
    return
  end
  -- ★★第 2 步：读回**行数已有、只是没有文字**（本客户端会出现这种「有行无字」的气泡）⇒
  --   **不再重问客户端**：重问那一趟带 `ClearLines`，会把这几行**当场抹掉**，而它们恰恰是我们
  --   要保住的（下一步走**追加式**兜底，绝不清行、绝不抢标题 = fail-open）。
  --   判据用**进 tick 那一刻**读到的 `n0`（重问之后行数就没了，「追加还是覆盖」会永远判成覆盖）。
  local append = (type(n0) == "number" and n0 > 0)
  -- ★★第 3 步：确实读成空 ⇒ **再重问一次客户端两级口**（延迟也可能超过一个 TIP_WAIT）
  if append == false and rec ~= nil and isObj(p.owner) then
    local path2, filled2, _, _, tried2 = B.tipClientTry(tip, p.owner, rec)
    if filled2 == true then
      B.tipLast = { path = path2, tried = tried2, lines = B.tipLines(tip), has = true,
                    bag = rec.bag, slot = rec.slot, name = rec.name }
      B.tipWhy = "客户端两级口第 2 拍才填上（" .. strVal(path2) .. "）⇒ 一个字都没动"
      if type(tip.Show) == "function" then pcall(tip.Show, tip) end
      return
    end
  end
  if rec == nil then return end
  -- ★★第 4 步：**分级的自建兜底**（用户报的「空箱子」在这里收口）：
  --   ⒜ 行数 0 / 判不出 ⇒ **覆盖式**（ClearLines + SetText 名字 + 数量 + 用法）—— 确定是空箱子；
  --   ⒝ 行数 > 0 但首行没有文字 ⇒ **追加式**（AddLine 补名字 + 数量 + 用法，旧行一个都不动）。
  local okAdd = (type(tip.AddLine) == "function")
  if append == false and type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  if isObj(p.owner) then pcall(tip.SetOwner, tip, p.owner, "ANCHOR_RIGHT") end
  local wrote = false
  local nm = strVal(rec.name or "")
  if string.len(nm) == 0 then nm = "?" end
  local qr, qg, qb = qualRGB(tonumber(rec.quality) or 1)
  if append == true then
    if okAdd then
      pcall(tip.AddLine, tip, nm, qr, qg, qb)
      wrote = true
    end
  elseif type(tip.SetText) == "function" then
    pcall(tip.SetText, tip, nm, 1, 1, 1)
    wrote = true
  end
  if okAdd and type(rec.count) == "number" and rec.count > 1 then
    pcall(tip.AddLine, tip, L("TIP_COUNT", rec.count), 0.85, 0.85, 0.85)
  end
  if okAdd then pcall(tip.AddLine, tip, L("HINT"), 0.7, 0.7, 0.7) end
  B.tipLast = { path = (append and "append" or "text"), tried = p.tried,
                lines = B.tipLines(tip), has = B.tipRead(tip),
                bag = rec.bag, slot = rec.slot, name = rec.name }
  if wrote ~= true then
    B.tipWhy = "延后复核仍读不回内容，且连标题都写不进去（SetText/AddLine 不可用）"
    if type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    return
  end
  B.tipWhy = append and "行数>0 但首行无文字（空箱子）⇒ 追加式兜底（不清行、不抢标题）"
    or "两级口与复核都读不回内容 ⇒ 覆盖式兜底（名字/数量/用法）"
  if type(tip.Show) == "function" then pcall(tip.Show, tip) end
end

-- ★0.3.11 空箱重申（唯一实现；由 bindItemButton 接管的那条 OnUpdate 调）：
--   ① 只碰**属于本格**的气泡（别人的/别的模块的气泡一个字节都不动）；
--   ② 气泡里**有字就一拍都不写**（沿用客户端内容 = 本项目既定口径）；
--   ③ 真空了才按**同一个填口**重填一次（mkTip：容器口 → 链接口 → 自建兜底），并记账；
--   ④ 有界：每次悬停最多 `B.TIP_GUARD_MAX` 次，超了如实停手（绝不无限重写）。
--   ★定义在 mkTip **之后**（它要调 mkTip）；写成 B 表字段 = 不占主 chunk 的 local 预算。
B.tipReassert = function(btn)
  if isObj(btn) ~= true then return end
  local tip = _G.GameTooltip
  if tip == nil then return end
  if type(tip.IsOwned) == "function" then
    local ok, v = pcall(tip.IsOwned, tip, btn)
    if not ok then return end
    if v ~= true and v ~= 1 then return end
  end
  if B.tipBlank(tip) ~= true then
    B.tipWipes = 0     -- 有内容 ⇒ 归零（这一格是好的，别把账带进下一次悬停）
    return
  end
  if (B.tipWipes or 0) >= B.TIP_GUARD_MAX then return end
  B.tipWipes = (B.tipWipes or 0) + 1
  B.tipWhy = "气泡被清成空箱 ⇒ 第 " .. strVal(B.tipWipes) .. " 次重申（模板 OnUpdate 已被我们接管）"
  B.tipTraceAdd("重申#" .. strVal(B.tipWipes) .. " 格=" .. strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_))
  -- ★0.3.18：空格不弹提示（与 OnEnter 同一口径）—— 重申这条路也不许把「空」写回气泡
  local recE1 = B.itemAt(btn.ehBag, btn.ehSlot_)
  if recE1 == nil then return end
  mkTip(btn, recE1)
end

local function bindItemButton(btn)
  btn:SetScript("OnClick", function()
    local rec = B.itemAt(btn.ehBag, btn.ehSlot_)
    local mb = arg1
    if type(mb) ~= "string" then mb = nil end
    -- ★★★0.3.8：**光标上有东西 ⇒ 这一下是「落格」**（不是链接 / 换装），且与拖放**共用同一个决策口**
    --   ① 空格：光标有东西 ⇒ 落格（旧写法只认 rec == nil 那一支，落在**有物品**的格子上就被下面的
    --      Shift 分支抢走 ⇒ 插一条链接到聊天框、东西还挂在光标上 = 用户眼里的「Shift 拆分失效」）；
    --   ② 有物品：先问「要不要拆」（splitTry），不接管才普通落格（沿客户端自己的交换语义）。
    if cursorHas() == true then
      if type(B.splitTry) == "function" and B.splitTry(btn.ehBag, btn.ehSlot_) == true then return end
      B.dropOnSlot(btn.ehBag, btn.ehSlot_)
      return
    end
    if rec == nil then return end
    local shift = shiftDown()
    local ctrl = false
    if type(IsControlKeyDown) == "function" then
      local ok, v = pcall(IsControlKeyDown)
      ctrl = (ok and v) and true or false
    end
    if (shift or ctrl) and mb ~= "RightButton" then
      if shift then linkItem(rec.link) end
      if ctrl then dressUp(rec.link) end
      return
    end
    if mb == "RightButton" then
      useSlot(rec)
      return
    end
    pickUp(rec)
  end)
  btn:SetScript("OnMouseDown", function(button)
    if type(button) ~= "string" then button = arg1 end
    if button ~= "LeftButton" then return end
    -- ★★★0.3.9：**每一次左键按下**都刷新一份 Shift 的账（无条件 —— 绝不留给上一次的账）。
    --   理由：玩家习惯「先按住 Shift 再拖」，按下那一刻的读数比落格那一刻可靠得多；
    --   而「每一次都刷新」保证它不会从一次按press漏到下一次（stale true = 普通拖拽也弹窗）。
    --   ★这一份**不参与**「Shift+左键 = 插链接」那条判定（那条只看 OnClick 的实时读），
    --   只在 splitTry 里当第三个来源；holdForget 会清掉它。
    HOLD.downShift = shiftDown()
    if HOLD.bag == nil then
      HOLD.bag, HOLD.slot = btn.ehBag, btn.ehSlot_
    end
  end)
  btn:SetScript("OnDragStart", function()
    local rec = B.itemAt(btn.ehBag, btn.ehSlot_)
    if rec == nil then return end
    -- ★0.3.7：Shift 不再是「立刻拆一半」（旧 splitSlot）—— 拆分统一交给**落格时的确认窗**
    --   （用户定：合并时弹 · Shift 拖也弹）；两套语义并存 = 下一次改一处的漏改点。
    local cur0 = cursorHas()
    pickUp(rec)
    -- ★★★0.3.8：**起拖这一刻**把 Shift 记进账（落格时未必还读得到 ⇒ 见 shiftDown 的注释）。
    --   只在真的拿起来了才记（拿不起来 = 这一下不是我们拖的，账必须干净）。
    if HOLD.bag ~= nil then HOLD.shift = shiftDown() end
    -- ★取证（铁律 4：日志必须能区分「代码没跑」与「条件没满足」）——
    --   0.3.9 补三项：拿起**之前**光标上有没有东西（= 客户端自己有没有先拿起）、拿起**之后**有没有、
    --   以及原格此刻读成什么。这三项一次就能判定本客户端的拖拽模型（东西拿起后原格会不会立刻读空）。
    B.splitAdd("idrag", strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_)
      .. " 记账=" .. (HOLD.shift and "1" or "0") .. " got=" .. ((HOLD.bag ~= nil) and "1" or "0")
      .. " 拿起前cur=" .. (cur0 and "1" or "0") .. " 拿起后cur=" .. (cursorHas() and "1" or "0")
      .. " src=" .. ((B.itemAt(btn.ehBag, btn.ehSlot_) ~= nil) and "full" or "empty"))
  end)
  btn:SetScript("OnReceiveDrag", function()
    -- ★取证：落格那一下就报「谁落的 / Shift 读到了没 / 账还在不在」
    B.splitAdd("idrop", strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_)
      .. " 账=" .. (HOLD.shift and "1" or "0"))
    -- ★先问「要不要拆」；不拆（或问不了）才走普通落格 —— 顺序即判据（拆不了绝不许静默照搬整堆）
    if type(B.splitTry) == "function" and B.splitTry(btn.ehBag, btn.ehSlot_) == true then return end
    B.dropOnSlot(btn.ehBag, btn.ehSlot_)
  end)
  btn:SetScript("OnEnter", function()
    -- ★★★0.3.19：**先记账再判空**（顺序即判据）—— 悬停高亮跟「格子里有没有东西」无关
    --   （空格悬停照旧要点亮金色辉光）。旧写法只在 0.3.18 之前靠模板自带的 HighlightTexture，
    --   那张方框贴图被我们收掉之后就**没有任何悬停反馈**了。
    B.hoverBtn = btn
    if type(B.paintOne) == "function" then B.paintOne(btn) end
    -- ★★★0.3.18：**空格不弹提示**（用户：「空格不需要显示tootip」）——连记账都不留，
    --   上一格的气泡照旧收掉（绝不许留在空格上）。
    local recE0 = B.itemAt(btn.ehBag, btn.ehSlot_)
    if recE0 == nil then
      B.tipHold = nil
      local tipE0 = _G.GameTooltip
      if tipE0 ~= nil and type(tipE0.Hide) == "function" then pcall(tipE0.Hide, tipE0) end
      return
    end
    -- ★0.3.11：记账「现在悬停的是这一格」—— 空箱重申与那句「模板 OnUpdate 已接管」只在它身上跑
    B.tipHold = btn
    B.tipGuardAt = GetTime() + B.TIP_GUARD_GAP
    B.tipWipes = 0
    mkTip(btn, recE0)
    -- ★★★0.3.22：**通知宿主的「装备比较」**（外部悬停口 `EVAL_EC_HOVER`）——
    --   我们把格子的 `OnEnter` 覆盖成自己的处理体 ⇒ 客户端那条 `ContainerFrameItemButton_OnEnter`
    --   （= EC 容器腿的唯一写点，证据 = `Interface\FrameXML\ContainerFrame.xml` 模板里那句调用）
    --   在代理视图里**永远不会被调到**，而 EC 的焦点路只认拾取/商人/任务行 ⇒ 两条腿都断
    --   = 用户报的「装备比较在背包插件内不能正常生效」。
    --   ★放在 `mkTip` **之后**：EC 要用气泡首行名字做校验，气泡先就位它才认得出；
    --     `mkTip` 走延后复核时（当场读回 0 行）EC 的 0.15s 节拍会在气泡填好后再认一次（自愈）。
    --   ★拿不到那个口 ⇒ 什么都不做（解耦 + fail-open：老版本宿主照旧；本子插件零依赖）。
    local ecH = rawget(_G, "EVAL_EC_HOVER")
    if type(ecH) == "function" and type(recE0.link) == "string" then
      btn.ehEcLink = recE0.link
      pcall(ecH, recE0.link, recE0.name)
    else
      btn.ehEcLink = nil
    end
  end)
  btn:SetScript("OnLeave", function()
    -- ★★★0.3.19：**按身份还回去**（`== btn`）—— 鼠标从 A 格划到 B 格时，本客户端可能先到 B 的
    --   OnEnter 再到 A 的 OnLeave（顺序不保证）⇒ 无条件清空会把**刚点亮的那一格**当场熄掉。
    if B.hoverBtn == btn then
      B.hoverBtn = nil
      if type(B.paintOne) == "function" then B.paintOne(btn) end
    end
    if B.tipHold == btn then B.tipHold = nil end
    -- ★★★0.3.22：按 **link** 报「离开了」（EC 侧按 link 匹配才清）——
    --   鼠标从 A 格划到 B 格时，A 的 `OnLeave` 可能**后到** ⇒ 无条件清会把刚报上来的 B 当场抹掉
    --   （与上面 `B.hoverBtn == btn` 那条身份判定同一族）。
    local ecL = rawget(_G, "EVAL_EC_LEAVE")
    if type(ecL) == "function" and type(btn.ehEcLink) == "string" then pcall(ecL, btn.ehEcLink) end
    -- ★鼠标走了 ⇒ 延后复核作废（绝不在鼠标离开之后再回头去改那口气泡）
    B.tipPend = nil
    -- ★0.3.11：把这次悬停的判决落进**有界取证环**（落存档）⇒ AI 读存档就能判「没跑到」还是「被抹了」
    local tl = B.tipLast
    if type(tl) == "table" then
      B.tipTraceAdd("悬停 " .. strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_)
        .. " " .. strVal(tl.name) .. " ｜ path=" .. strVal(tl.path)
        .. " tried=" .. strVal(tl.tried) .. " ｜ 行=" .. strVal(tl.lines)
        .. " ｜ 重申=" .. strVal(B.tipWipes or 0))
    end
    local tip = _G.GameTooltip
    if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  -- ★★★0.3.11 真因修复：**接管模板那条 OnUpdate**（长注释见文件上方 B.tipBlank 处）——
  --   模板的 `ContainerFrameItemButton_OnUpdate` 每 0.2s 用**坏掉的容器口**把气泡清成空箱
  --   （我们的格子在共享容器 `ehContent` 下、又没有 ID）⇒ 换掉它：只在「气泡属于本格且首行无字」时重申。
  --   ★每格每帧只做一次「现在悬停的是不是我」的比较，其余什么都不读（不违反「用不着就别跑」）。
  btn.ehTipAt = 0
  btn:SetScript("OnUpdate", function()
    if B.tipHold ~= btn then return end
    local t = GetTime()
    if t < (B.tipGuardAt or 0) then return end
    B.tipGuardAt = t + B.TIP_GUARD_GAP
    B.tipReassert(btn)
  end)
  if type(btn.RegisterForClicks) == "function" then
    pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp")
  end
  if type(btn.RegisterForDrag) == "function" then
    pcall(btn.RegisterForDrag, btn, "LeftButton")
  end
end

-- 把光标上的东西放进某格（银行主格 = 装备槽）
function B.dropOnSlot(bag, slot)
  if bag == B.BANK then
    local inv = 39 + slot
    if type(BankButtonIDToInvSlotID) == "function" then
      local ok, v = pcall(BankButtonIDToInvSlotID, slot)
      if ok and type(v) == "number" and v > 0 then inv = v end
    end
    if type(PickupInventoryItem) == "function" then pcall(PickupInventoryItem, inv) end
    return
  end
  if type(PickupContainerItem) == "function" then pcall(PickupContainerItem, bag, slot) end
end

-- ===== 拆分确认窗（0.3.7；用户：「拖拽完成之后需要弹窗进行物品数量的拆分确认」）=====
-- ★★★触发口径（用户选定 = B+C 组合）：
--   ① **落到同种物品上**（会合并 / 装不下）⇒ 弹窗问「移动几个」（默认 = 目标还装得下的量）；
--   ② **按住 Shift 拖** ⇒ 任何目标都弹（含空格，用于「拆一半放到别处」）。
--   其余情况（普通整堆搬）一个字节都不打扰。
--
-- ★★★为什么是「自建窗」而不是客户端的 StackSplitFrame：
--   客户端原生那条路是 `OpenStackSplitFrame(...)`（FrameXML：Shift+左键 ⇒ 拆窗，确认后
--   `SplitContainerItem(bag, slot, n)`）—— 而本客户端有没有那个口，我们**没有真机证据**
--   （本项目铁律：拿不准就不依赖）。自建窗零依赖、可离线 harness 真跑，且照样用**客户端自己的
--   `SplitContainerItem`** 完成拆分（不是我们自己挪物品）。
--
-- ★★★安全铁律（照项目「批量移动物品」那条）：**绝不清光标**。任何一步读不到预期状态 ⇒
--   当场如实收工、把东西留给玩家自己放（清光标 = 丢件，1.75.x 整理引擎首版就是这么丢过两件）。
-- ★★★0.3.23 几何（用户：「拆分数量弹窗删除取消按钮…然后将确定按钮和上面一层的按钮同一行」）：
--   ① **取消按钮整条删除** —— 取消出口只剩全屏捕手（点窗外面），行为一个字节没变（仍是 splitApply(false)）；
--   ② [确定] 挪到 −/＋/一半/全部 **同一条带** ⇒ 窗口不必再给底部留一排 ⇒ **变矮**。
--   ★★★窗宽**从这一排按钮现算**（不是手感数字）：两边距 + 各按钮宽 + 各缝 ⇒ 将来改任一宽度，
--     右边距**自动**还是对的（写死一个数的话，改一颗按钮就会让 [确定] 顶出窗框 / 右边距跑偏）。

function B.buildSplit()
  if isObj(B.ui.split) then return true end
  if type(CreateFrame) ~= "function" then return false end
  local z = B.z()
  -- 这一排的几何**只有这一处**（窗宽由它现算；判据 = [确定] 右缘 = 窗宽 − pad）
  local pad, bw, bh = 10, 22, 18       -- 左右边距 / −＋ 按钮宽 / 整排按钮高
  local halfW, allW, okW = 40, 40, 58  -- [一半] / [全部] / [确定] 宽
  local g2, g3, g4 = 2, 4, 6           -- 缝：＋→[一半] 2 · [一半]→[全部] 2 · [全部]→[确定] 6
  local splitW = pad * 2 + bw + g2 + bw + g3 + halfW + g2 + allW + g4 + okW
  local splitH = 80                    -- 三行文字 + 一排按钮 + 下边距（取消按钮删掉后比 0.3.22 矮 24）
  local f = CreateFrame("Frame", "EH_BagSplitFrame", UIParent)
  f:SetWidth(splitW * z)
  f:SetHeight(splitH * z)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0.05, 0.05, 0.05, 0.97)
  local edge = mkEdge(f, 0)
  edge:SetVertexColor(0.62, 0.52, 0.20, 1)
  f.ehEdge = edge
  if type(f.SetFrameStrata) == "function" then pcall(f.SetFrameStrata, f, "DIALOG") end
  if type(f.SetFrameLevel) == "function" then pcall(f.SetFrameLevel, f, 96) end
  local title = font(f)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", pad * z, -6 * z)
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)
  pcall(title.SetText, title, L("SPLIT_TITLE"))
  f.ehSplitTitle = title
  local info = font(f)
  info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3 * z)
  pcall(info.SetTextColor, info, 0.85, 0.85, 0.85)
  f.ehSplitInfo = info
  local nowL = font(f)
  nowL:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -6 * z)
  pcall(nowL.SetTextColor, nowL, 0.70, 0.70, 0.70)
  pcall(nowL.SetText, nowL, L("SPLIT_NOW"))
  f.ehSplitNowL = nowL
  local cnt = font(f)
  cnt:SetPoint("LEFT", nowL, "RIGHT", 6 * z, 0)
  pcall(cnt.SetTextColor, cnt, 1, 0.85, 0.30)
  f.ehSplitCount = cnt
  -- 数量：− / ＋（一点一个；Shift 不管它 —— 数量范围本来就只有 1..总数）
  local minus = mkBtn(f, bw * z, bh * z, "-", function() B.splitStep(-1) end)
  minus:SetPoint("TOPLEFT", nowL, "BOTTOMLEFT", 0, -4 * z)
  f.ehSplitMinus = minus
  local plus = mkBtn(f, bw * z, bh * z, "+", function() B.splitStep(1) end)
  plus:SetPoint("LEFT", minus, "RIGHT", g2 * z, 0)
  f.ehSplitPlus = plus
  local half = mkBtn(f, halfW * z, bh * z, L("SPLIT_HALF"), function() B.splitSetHalf() end)
  half:SetPoint("LEFT", plus, "RIGHT", g3 * z, 0)
  f.ehSplitHalf = half
  local all = mkBtn(f, allW * z, bh * z, L("SPLIT_ALL"), function() B.splitSetAll() end)
  all:SetPoint("LEFT", half, "RIGHT", g2 * z, 0)
  f.ehSplitAll = all
  -- ★★★0.3.23：[确定] 与 −/＋/一半/全部 **同一排**（锚在 [全部] 右缘、同高 bh）——
  --   用**锚点链**落位 ⇒ 不管字体实际多高，它永远跟那一排同一条中线（不是按算出来的 y 硬摆）。
  local okb = mkBtn(f, okW * z, bh * z, L("SPLIT_OK"), function() B.splitApply(true) end)
  okb:SetPoint("LEFT", all, "RIGHT", g4 * z, 0)
  f.ehSplitOK = okb
  -- 全屏捕手（**唯一取消出口** —— 0.3.23 起「取消」按钮已整条删除）：点窗外面 = 取消（把那一整堆放回原格）——
  --   ★层级 95 < 窗 96 但 > 菜单 92 ⇒ 「拆分窗在最上面」只有一条路
  local catch = CreateFrame("Button", "EH_BagSplitCatch", UIParent)
  local sw, sh = 1024, 768
  if type(GetScreenWidth) == "function" then
    local ok1, v = pcall(GetScreenWidth)
    if ok1 and type(v) == "number" and v > 0 then sw = v end
  end
  if type(GetScreenHeight) == "function" then
    local ok2, v = pcall(GetScreenHeight)
    if ok2 and type(v) == "number" and v > 0 then sh = v end
  end
  catch:SetWidth(sw)
  catch:SetHeight(sh)
  catch:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  if type(catch.SetFrameStrata) == "function" then pcall(catch.SetFrameStrata, catch, "DIALOG") end
  if type(catch.SetFrameLevel) == "function" then pcall(catch.SetFrameLevel, catch, 95) end
  catch:SetScript("OnClick", function() B.splitApply(false) end)
  pcall(catch.Hide, catch)
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, true) end
  pcall(f.Hide, f)
  B.ui.split = f
  B.ui.splitCatch = catch
  return true
end

-- 数量显示（唯一绘制口）
function B.splitFill()
  local f = B.ui.split
  if isObj(f) == false or B.split == nil then return end
  local s = B.split
  if isObj(f.ehSplitInfo) then
    pcall(f.ehSplitInfo.SetText, f.ehSplitInfo, L("SPLIT_INFO", strVal(s.name or "?"), s.total))
  end
  if isObj(f.ehSplitCount) then pcall(f.ehSplitCount.SetText, f.ehSplitCount, strVal(s.n)) end
end

local function splitClamp(n)
  local s = B.split
  if s == nil then return 1 end
  n = tonumber(n) or 1
  if n < 1 then n = 1 end
  if n > s.total then n = s.total end
  return n
end

function B.splitStep(d)
  if B.splitOn ~= true then return end
  B.split.n = splitClamp(B.split.n + (tonumber(d) or 0))
  B.splitFill()
end

function B.splitSetHalf()
  if B.splitOn ~= true then return end
  B.split.n = splitClamp(math.floor(B.split.total / 2))
  B.splitFill()
end

function B.splitSetAll()
  if B.splitOn ~= true then return end
  B.split.n = splitClamp(B.split.total)
  B.splitFill()
end

-- 把光标上那一整堆放回原格（唯一「还回去」的口）：成功 = 光标已空
function B.splitReturn()
  local s = B.split
  if s == nil then return false end
  if cursorHas() ~= true then return true end
  if s.bankMain == true then return false end
  if type(PickupContainerItem) ~= "function" then return false end
  pcall(PickupContainerItem, s.hb, s.hs)
  if cursorHas() == true then
    -- ★放不回去（原格被人塞了东西 / 客户端拒收）⇒ 如实说，**绝不清光标**
    B.splitLast = { path = "stuck", name = s.name, hb = s.hb, hs = s.hs }
    sayForce(L("SPLIT_STUCK"))
    return false
  end
  return true
end

function B.splitHide()
  if isObj(B.ui.split) then pcall(B.ui.split.Hide, B.ui.split) end
  if isObj(B.ui.splitCatch) then pcall(B.ui.splitCatch.Hide, B.ui.splitCatch) end
  B.splitOn = false
end

-- ok = true ⇒ 按当前数量动手；ok = false ⇒ 取消（原样放回）
function B.splitApply(ok)
  if B.splitOn ~= true then return false end
  local s = B.split
  if s == nil then
    B.splitHide()
    return false
  end
  local n = splitClamp(s.n)
  local total = s.total
  B.splitOn = false
  if ok ~= true then
    B.splitReturn()
    B.splitHide()
    B.splitLast = { path = "cancel", name = s.name, n = n, total = total, hb = s.hb, hs = s.hs }
    return true
  end
  if n >= total then
    -- 整堆搬 = 普通落格（不拆；光标上就是那一整堆）
    B.dropOnSlot(s.tb, s.ts)
    B.splitHide()
    B.splitLast = { path = "all", name = s.name, n = total, total = total, tb = s.tb, ts = s.ts }
    return true
  end
  -- ① 先把整堆放回原格（原格此刻是空的 —— 东西在我们拖起来的那一刻就离开它了）
  local back = B.splitReturn()
  if back ~= true then
    B.splitHide()
    return true
  end
  -- ② 用**客户端自己的** SplitContainerItem 把 n 个放到光标上
  local got = false
  if type(SplitContainerItem) == "function" then
    local okc = pcall(SplitContainerItem, s.hb, s.hs, n)
    got = okc and cursorHas()
  end
  if got ~= true then
    B.splitLast = { path = "nosplit", name = s.name, n = n, total = total, hb = s.hb, hs = s.hs }
    B.splitHide()
    sayForce(L("SPLIT_NOSPLIT"))
    return true
  end
  -- ③ 落到目标格（同 id 会合并；合并只吃目标装得下的部分）
  B.dropOnSlot(s.tb, s.ts)
  B.splitHide()
  B.splitLast = { path = "split", name = s.name, n = n, total = total, tb = s.tb, ts = s.ts }
  sayForce(L("SPLIT_SAY", strVal(s.name or "?"), n, total))
  return true
end

-- 落到某格时先问「要不要拆」：返回 true = 拆分窗接管了这一落（调用方**不许**再落格）
function B.splitTry(tb, ts)
  local h = HOLD
  local sp = shiftDown()
  local tgt = nil
  if tb ~= nil and ts ~= nil then tgt = B.itemAt(tb, ts) end
  -- 原格此刻的读数（下面那条守卫与取证行共用同一次读）
  local src = nil
  if h.bag ~= nil and h.slot ~= nil then src = B.itemAt(h.bag, h.slot) end
  local srcId = (src ~= nil) and src.id or nil
  -- ★★取证行：落格这一落到底读到了什么（含「我们那份账」）—— 与 idrag/idrop 两行合起来，
  --   「客户端没调我们的脚本」与「调了但某个条件没满足」当场分得开。
  B.splitAdd("isplit", "tb=" .. strVal(tb) .. ",ts=" .. strVal(ts)
    .. " n=" .. strVal(h.count) .. " 记账=" .. (h.shift and "1" or "0")
    .. " 按下=" .. (h.downShift and "1" or "0") .. " 实时=" .. (sp and "1" or "0")
    .. " src=" .. ((src ~= nil) and ("id" .. strVal(srcId)) or "empty")
    .. " myId=" .. strVal(h.id)
    .. " bm=" .. (h.bankMain and "1" or "0") .. " open=" .. ((B.splitOn == true) and "1" or "0")
    .. " tgt=" .. ((tgt ~= nil) and strVal(tgt.id) or "-")
    .. " room=" .. ((tgt ~= nil) and strVal((tgt.maxStack or 1) - (tgt.count or 1)) or "-"))
  if B.splitOn == true then return false end
  if tb == nil or ts == nil then return false end
  if tb == B.BANK then return false end                 -- 银行主格走装备槽 API，拆不了
  if cursorHas() ~= true then return false end
  if h.bag == nil or h.slot == nil then return false end -- 不是我们拖起来的 ⇒ 一个字节都不插手
  if h.bankMain == true then return false end
  -- ★★★0.3.9 放宽「过期账守卫」（真机取证换来的，**这是「Shift 拖动拆分一直不弹窗」的真因**）：
  --   真机 `/ebag split` 每一落都是 `src=full` —— 本客户端在**拖拽期间**（东西已在光标上）
  --   `GetContainerItemInfo` **仍然报原格有物品**（把东西搬到光标上不等于那一格立刻读成空）
  --   ⇒ 旧写法「原格非空就 return false」= **每一次都拦下**，拆分窗永远不弹。
  --   现在只拦「原格换成了**别的**物品」（那才是真的过期账：玩家自己放回去了 / 被别人塞了）；
  --   同 id ⇒ 就是「同一堆东西在光标上、原格还没读空」⇒ 照常往下走（拆/合并都安全）。
  if src ~= nil and h.id ~= nil and srcId ~= nil and srcId ~= h.id then return false end
  local total = tonumber(h.count) or 1
  if total < 2 then return false end
  local merge = (tgt ~= nil and tgt.bankMain ~= true and tgt.id ~= nil and h.id ~= nil and tgt.id == h.id)
  -- ★★★0.3.8/0.3.9：Shift = **按下时记的账 ∨ 起拖时记的账 ∨ 实时读**（三条任一成立就弹）——
  --   拖拽是跨好几拍的动作，修饰键在鼠标操作期间能不能读到没有保证；按下鼠标那一刻玩家一定按着
  --   Shift（玩家习惯是先按住 Shift 再拖）⇒ 多记一份「按下」的账，落格时读不到也照样弹。
  local shift = (h.shift == true) or (h.downShift == true) or (sp == true)
  local def
  if merge then
    local room = (tgt.maxStack or 1) - (tgt.count or 1)
    if room < 1 then return false end                   -- 目标已满 ⇒ 没什么可并的 ⇒ 走普通落格
    def = total
    if room < def then def = room end
  elseif shift then
    def = total
  else
    return false
  end
  if B.buildSplit() ~= true then return false end
  B.split = {
    total = total, n = def, name = h.name, id = h.id,
    hb = h.bag, hs = h.slot, bankMain = false,
    tb = tb, ts = ts, merge = merge,
  }
  B.splitOn = true
  B.splitFill()
  local f = B.ui.split
  -- 摆在主窗中间（确定性；鼠标附近会让它跟着抖）—— 窗口不可见就退到屏幕正中
  local wf = B.ui.frame
  if isObj(wf) and B.visible == true and type(f.SetPoint) == "function" then
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "CENTER", wf, "CENTER", 0, 0)
  elseif type(f.SetPoint) == "function" then
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "CENTER", UIParent, "CENTER", 0, 0)
  end
  if isObj(B.ui.splitCatch) then pcall(B.ui.splitCatch.Show, B.ui.splitCatch) end
  pcall(f.Show, f)
  B.splitLast = { path = "ask", name = h.name, n = def, total = total, tb = tb, ts = ts, merge = merge }
  B.splitAdd("ask", "def=" .. strVal(def) .. "/" .. strVal(total) .. " merge=" .. (merge and "1" or "0")
    .. " shift=" .. (shift and "1" or "0") .. " tb=" .. strVal(tb) .. ",ts=" .. strVal(ts))
  return true
end

-- ===== 建窗 =====
local function barButton(parent, index, opts)
  local b = CreateFrame("Button", nil, parent)
  local sz = opts.size or (B.BARCELL or 30)
  b:SetWidth(sz)
  b:SetHeight(sz)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") end
  if type(b.RegisterForDrag) == "function" then pcall(b.RegisterForDrag, b, "LeftButton") end
  -- ★0.3.16：按钮底也走**圆角实心底**（与格框/格子同一轮廓、同一把尺子；当前是透明的）
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetWidth(sz * B.SLOT_K)
  fill:SetHeight(sz * B.SLOT_K)
  fill:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(fill.SetTexture, fill, B.SLOT_FILL)
  pcall(fill.SetVertexColor, fill, 0.06, 0.06, 0.06, 0)
  local icon = b:CreateTexture(nil, "BORDER")
  -- ★0.3.9：图标**铺满按钮**（旧写法四边各内缩 3px ⇒ 比格框小一圈，用户报「图标和框大小不匹配」）；
  --   那一圈环改画在图标**之上**（见下方 edge 的层）—— 与背包格子、与客户端 ItemButtonTemplate 同口径。
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  b.ehIcon = icon
  -- ★白框（与格子同一张美术 `B.SLOT_TEX`）：旧写法是 UI-Tooltip-Border —— 那是「九宫格边框」贴图，
  --   拉成按钮大小时会画出乱七八糟的白线（用户报「左侧背包条线条错乱」的真因）
  --   ⇒ 与 newItemButton 同一口径：白框居中 + 按 `B.SLOT_K` 放大到「画框外缘 = 按钮边」（染色位照旧走 ehEdge）
  --   ★0.3.9：层 = ARTWORK（画在图标之上，框压住图标边缘）
  local edge = b:CreateTexture(nil, "ARTWORK")
  local k = B.SLOT_K
  edge:SetWidth(sz * k)
  edge:SetHeight(sz * k)
  edge:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(edge.SetTexture, edge, B.SLOT_TEX)
  pcall(edge.SetVertexColor, edge, 1, 1, 1, 1)
  b.ehEdge = edge
  b.ehBag = opts.bag
  b.ehIndex = index
  if type(opts.onClick) == "function" then b:SetScript("OnClick", opts.onClick) end
  if type(opts.onEnter) == "function" then b:SetScript("OnEnter", opts.onEnter) end
  b:SetScript("OnLeave", function()
    local tip = _G.GameTooltip
    if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    B.hoverBag = nil
    B.refreshAll()
  end)
  if type(opts.onReceiveDrag) == "function" then b:SetScript("OnReceiveDrag", opts.onReceiveDrag) end
  if type(opts.onDragStart) == "function" then b:SetScript("OnDragStart", opts.onDragStart) end
  return b
end

-- ===== 窗口拖拽：可靠释放（0.3.4，主窗与总览窗共用一套）=====
-- ★真机报障「鼠标拖拽释放操作监听最顶级父类.现在拖拽开始之后不能正常拖动停止拖拽操作」：
--   旧写法用 StartMoving/StopMovingOrSizing —— 那一套**只有 OnDragStop 一条收尾路**，拖拽柄一旦丢了
--   鼠标捕获那个事件就永远不来 ⇒ 窗口黏在光标上（本项目铁律：拖拽绝不 SetMovable/StartMoving）。
--   ⇒ 现按项目**已验证的三件套**实现（与 tools/DragFrames.lua 同一配方）：
--     **OnMouseDown 起 + GetCursorPosition 现算 + 全屏接盘收尾**；位移一律按**屏幕**算，
--     落锚后用「实测系数」自纠正（本客户端 SetPoint 的偏移量含缩放，猜不得 —— DragFrames 同款做法）。
B.DRAG_IDLE = 8.0   -- 光标 8s 不动 ⇒ 当作已经松手（最后一道保险，绝不永久黏住）
B.DRAG_MAX = 30.0   -- 单次拖拽总时长上限（防呆）

-- ★两只全屏接盘的**唯一显隐口**（主 = 顶级父类 WorldFrame，备份 = UIParent）
B.dragCatches = function(on)
  local list = { B.ui.dragCatch, B.ui.dragCatch2 }
  local i
  for i = 1, 2 do
    local c = list[i]
    if isObj(c) then
      if on == true then pcall(c.Show, c) else pcall(c.Hide, c) end
    end
  end
end

-- target = 被拖的窗（缺省 = 主窗）；key = 落点写进存档的哪个键（"point" / "vpoint"）
B.dragStart = function(target, key)
  local f = target
  if not isObj(f) then f = B.ui.frame end
  if f == nil or B.dragging == true then return end
  -- ★0.3.12：起拖前先自愈 —— 「被夹在屏幕边上、逻辑锚点在屏外」的窗口直接拖是**拖不动**的
  --   （手指走了 500px，逻辑值从 3000 变 2500、画面一动不动）⇒ 先回正中，这一拖才有手感
  if f == B.ui.frame then B.winAuto("起拖前") end
  if type(GetCursorPosition) ~= "function" then return end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and type(cx) == "number" and type(cy) == "number") then return end
  local okp, a1, a2, a3, a4, a5 = false, nil, nil, nil, nil, nil
  if type(f.GetPoint) == "function" then okp, a1, a2, a3, a4, a5 = pcall(f.GetPoint, f, 1) end
  local es = 1
  if type(f.GetEffectiveScale) == "function" then
    local oke, v = pcall(f.GetEffectiveScale, f)
    if oke and type(v) == "number" and v > 0.05 then es = v end
  end
  -- ★相对帧也要存下来（总览窗是锚在主窗右边上的 —— 重锚回 UIParent 位置就飞了）
  local rel = (okp and isObj(a2)) and a2 or nil
  if rel == nil then rel = rawget(_G, "UIParent") end
  if not isObj(rel) then rel = f end
  local st = {
    x0 = cx, y0 = cy, lastX = cx, lastY = cy, idle = 0, age = 0,
    pa = (okp and type(a1) == "string") and a1 or "CENTER",
    pb = (okp and type(a3) == "string") and a3 or "CENTER",
    rel = rel, key = (type(key) == "string") and key or "point",
    ox = (okp and type(a4) == "number") and a4 or 0,
    oy = (okp and type(a5) == "number") and a5 or 0,
    appX = 0, appY = 0, kx = es, ky = es,
  }
  if type(f.GetLeft) == "function" then
    local okl, v = pcall(f.GetLeft, f)
    if okl and type(v) == "number" then st.l0 = v end
  end
  if type(f.GetBottom) == "function" then
    local okb, v = pcall(f.GetBottom, f)
    if okb and type(v) == "number" then st.b0 = v end
  end
  B.dragSt = st
  B.dragTarget = f
  B.dragging = true
  -- ★★鼠标键状态**自校准**：起拖那一刻左键必定是按下的 ⇒ 此刻报 true 才敢信它；
  --   报 false / 报错 = 本客户端不支持或语义不符 ⇒ 整条路废掉
  --   （否则「键一松」那条路会在下一拍把刚起的拖拽当场结束 = 拖不动）。
  B.dragApiOK = false
  if type(IsMouseButtonDown) == "function" then
    local okd, down = pcall(IsMouseButtonDown, "LeftButton")
    B.dragApiOK = (okd and down == true)
  end
  B.dragCatches(true)
  B.traceAdd("drag", "start api=" .. strVal(B.dragApiOK and 1 or 0) .. " es=" .. string.format("%.2f", es))
  B.pumpSync()
end

-- 每拍推进：光标屏幕位移 ⇒ 落锚 ⇒ **量回自证**纠正系数；顺带兜底收尾（光标久不动 / 超时）
B.dragStep = function(dt)
  local st = B.dragSt
  local f = B.dragTarget
  if st == nil or not isObj(f) then return end
  if type(GetCursorPosition) ~= "function" then return end
  local okc, cx, cy = pcall(GetCursorPosition)
  if not (okc and type(cx) == "number" and type(cy) == "number") then return end
  local totX, totY = cx - st.x0, cy - st.y0
  -- 位移没变就不重发锚点（每拍无谓重写会闪）
  if math.abs(totX - st.appX) > 0.5 or math.abs(totY - st.appY) > 0.5 then
    if type(f.SetPoint) == "function" and st.kx > 0.02 and st.ky > 0.02 then
      local ox, oy = st.ox, st.oy
      local nx = ox + (totX - st.appX) / st.kx
      local ny = oy + (totY - st.appY) / st.ky
      local beforeL, beforeB
      if type(f.GetLeft) == "function" then
        local okl, v = pcall(f.GetLeft, f)
        if okl and type(v) == "number" then beforeL = v end
      end
      if type(f.GetBottom) == "function" then
        local okb, v = pcall(f.GetBottom, f)
        if okb and type(v) == "number" then beforeB = v end
      end
      if pcall(f.SetPoint, f, st.pa, st.rel, st.pb, nx, ny) then
        st.ox, st.oy = nx, ny
        st.appX, st.appY = totX, totY
        -- ★量回自证：实测「屏幕位移 ÷ 偏移改变量」= 真实系数（下一拍落锚就用它，越走越准）
        local dOffX, dOffY = nx - ox, ny - oy
        if beforeL ~= nil and math.abs(dOffX) > 1 and type(f.GetLeft) == "function" then
          local okl, v = pcall(f.GetLeft, f)
          if okl and type(v) == "number" and math.abs(v - beforeL) > 0.5 then
            local k = (v - beforeL) / dOffX
            if k > 0.05 and k < 20 then st.kx = k end
          end
        end
        if beforeB ~= nil and math.abs(dOffY) > 1 and type(f.GetBottom) == "function" then
          local okb, v = pcall(f.GetBottom, f)
          if okb and type(v) == "number" and math.abs(v - beforeB) > 0.5 then
            local k = (v - beforeB) / dOffY
            if k > 0.05 and k < 20 then st.ky = k end
          end
        end
      end
    end
  end
  -- 兜底 A：光标长时间不动 ⇒ 当作已经松手（绝不永久黏住）
  if math.abs(cx - st.lastX) < 0.5 and math.abs(cy - st.lastY) < 0.5 then
    st.idle = st.idle + dt
    if st.idle >= (B.DRAG_IDLE or 8) then
      B.traceAdd("drag", "idle-end")
      B.dragStop("idle")
      return
    end
  else
    st.idle = 0
    st.lastX, st.lastY = cx, cy
  end
  st.age = st.age + dt
  if st.age >= (B.DRAG_MAX or 30) then
    B.traceAdd("drag", "max-end")
    B.dragStop("timeout")
  end
end

-- ★唯一收尾口（幂等）：四条路全汇到这里 —— 柄 OnMouseUp / 柄 OnDragStop / 全屏接盘 / 节拍读键状态
B.dragStop = function(why)
  if B.dragging ~= true then return end
  local st = B.dragSt
  local f = B.dragTarget or B.ui.frame
  B.dragging = false
  B.dragSt = nil
  B.dragTarget = nil
  B.dragCatches(false)
  if not isObj(f) then return end
  -- 兜底：万一有别的代码把窗口置成「移动中」，这里一并停掉（我们**从不** StartMoving）
  if type(f.StopMovingOrSizing) == "function" then pcall(f.StopMovingOrSizing, f) end
  -- 落点记忆（口径：GetPoint(1) 的锚点四元组原样存 —— 无损、且不必掺缩放）
  local c = B.cfg()
  local key = (st ~= nil and type(st.key) == "string") and st.key or "point"
  -- ★★★0.3.12：**绝不把离谱锚点写进存档**（用户报障的根因就在这里）——
  --   切屏幕/光标跳变会让这一拖的位移变成几千像素 ⇒ 存档里留下屏外的逻辑锚点
  --   ⇒ 下一局开窗还是"依附在屏幕右边、拖不动"。越界就**当场回正中**并如实出声。
  local offWhy = (type(f.GetPoint) == "function") and B.winOff(f) or nil
  if offWhy ~= nil then
    B.recenter("拖拽落点越界 ⇒ " .. strVal(offWhy))
  elseif type(f.GetPoint) == "function" then
    local ok, a1, a2, a3, a4, a5 = pcall(f.GetPoint, f, 1)
    if ok and type(a4) == "number" and type(a5) == "number" then
      c[key] = { a = a1 or "CENTER", b = a3 or "CENTER", x = a4, y = a5 }
    end
  end
  B.traceAdd("drag", "stop " .. strVal(why or ""))
end

-- 关窗/收总览时结束它自己的那次拖拽（关断四件事：绝不留一个吃点击的空层）
function B.dragStopIf(target)
  if B.dragging == true and B.dragTarget == target then B.dragStop("owner-hide") end
end

-- ===== 窗口「越界自愈」+ 回到屏幕中间（0.3.12）=====
--   ★用户报障原话：「在某次拖拽的时候不小心切换屏幕之后.导致背包一直被依附在右侧屏幕
--     无法拖拽回左侧。增加个功能自动重置背包到当前屏幕中间定位」。
--   ★★★真因（两条叠在一起，缺一条都解释不了现象）：
--     ① 拖拽期间切屏幕 ⇒ `GetCursorPosition()` 跳变 ⇒ 位移 `totX` 一下变成几千 ⇒ **逻辑锚点**
--        被写成几千像素的离谱值（我们从不校验）⇒ 收尾又把这份离谱值**写进了 `c.point`**；
--     ② 窗口开着 `SetClampedToScreen` ⇒ **画面被夹在屏幕边上**，而逻辑位置在屏外 ⇒
--        之后每一次拖动都只是在「把屏外的逻辑位置往回调」：手指在屏幕上走了 500px，
--        逻辑值从 3000 变 2500、**画面一动不动**（要拖 3000px 才回来 —— 屏幕根本没有那么宽）。
--   ⇒ 三条一起做：
--     ① 判据 `B.winOff(f)`：**纯逻辑判据**（不比 GetLeft/GetBottom —— 那两条与本客户端的锚点
--        不是同一口径，项目在案）—— CENTER/CENTER+UIParent 的窗口，偏移量的数学上界 =
--        (屏幕 − 窗)/2 + 容差（SetClampedToScreen 让**画面**停在屏内，而**逻辑偏移可以任意大**）；
--        别的锚点组合只用「|x| > 屏幕尺寸」这种放得很宽的兜底。**判不出 ⇒ nil**（一个字节都不动）。
--     ② 唯一复位口 `B.recenter(why)`：清 `c.point`/`c.vpoint` + 主窗回屏幕正中 + 总览窗重挂回主窗
--        + 如实出声（行为改变必须出声）+ 进取证环。
--     ③ 三个调用点：**开窗**（覆盖上一局留下的坏存档）/ **起拖前**（先修好再拖，否则手感还是"拖不动"）
--        / **收尾**（绝不把离谱锚点写进存档 —— 这才是根因）。另给菜单一行 + `/ebag center`。
B.OFF_PAD = 24   -- 上界容差（像素）：贴边停靠的窗口留一点余量，免得把正常位置判成越界

B.screenWH = function()
  local w, h = 0, 0
  if isObj(UIParent) then
    if type(UIParent.GetWidth) == "function" then
      local ok, v = pcall(UIParent.GetWidth, UIParent)
      if ok and type(v) == "number" and v > 1 then w = v end
    end
    if type(UIParent.GetHeight) == "function" then
      local ok, v = pcall(UIParent.GetHeight, UIParent)
      if ok and type(v) == "number" and v > 1 then h = v end
    end
  end
  if w <= 1 then w = 1024 end
  if h <= 1 then h = 768 end
  return w, h
end

B.winOff = function(f)
  if isObj(f) ~= true then return nil end
  if type(f.GetPoint) ~= "function" then return nil end
  local ok, pa, rel, pb, x, y = pcall(f.GetPoint, f, 1)
  if not (ok and type(x) == "number" and type(y) == "number") then return nil end
  local sw, sh = B.screenWH()
  local w, h = 0, 0
  if type(f.GetWidth) == "function" then
    local okw, v = pcall(f.GetWidth, f)
    if okw and type(v) == "number" and v > 1 then w = v end
  end
  if type(f.GetHeight) == "function" then
    local okh, v = pcall(f.GetHeight, f)
    if okh and type(v) == "number" and v > 1 then h = v end
  end
  local limX, limY
  if pa == "CENTER" and pb == "CENTER" and isObj(rel) and rel == UIParent then
    -- ★我们自己的两个窗都是 CENTER/CENTER + UIParent ⇒ 偏移量的**数学上界** = (屏幕 − 窗)/2
    --   （窗口开着 SetClampedToScreen ⇒ 客户端把画面夹在屏内，而**逻辑偏移可以是任意大**：
    --    玩家把窗拖到右缘时 x ≈ (sw − w)/2 就顶住了；再大只可能来自「光标跳变」那条路）。
    --   ★不用 GetLeft/GetBottom 去「量回」：本客户端/桩里那两条与锚点**不是同一口径**
    --     （项目在案：几何断言一律比锚点、别比 GetLeft —— 比了就是假红/假绿）。
    limX = (sw - w) / 2 + (B.OFF_PAD or 24)
    limY = (sh - h) / 2 + (B.OFF_PAD or 24)
  else
    -- 别的锚点组合（总览窗锚在主窗上）算不出上界 ⇒ 只用**放得很宽**的兜底判据（判不出不动手）
    limX = sw
    limY = sh
  end
  if limX < 40 then limX = 40 end
  if limY < 40 then limY = 40 end
  if math.abs(x) > limX or math.abs(y) > limY then
    return "锚点在屏外（" .. strVal(math.floor(x)) .. "," .. strVal(math.floor(y))
      .. " ｜ 允许 " .. strVal(math.floor(limX)) .. "）"
  end
  return nil
end

-- 总览窗重挂回主窗右侧（唯一处；recenter 与 /ebag reset 共用）
B.viewRehost = function()
  local vf = B.ui.viewFrame
  if isObj(vf) ~= true then return end
  local host = B.ui.frame
  pcall(vf.ClearAllPoints, vf)
  if isObj(host) then
    pcall(vf.SetPoint, vf, "TOPLEFT", host, "TOPRIGHT", 4, 0)
  else
    pcall(vf.SetPoint, vf, "CENTER", UIParent, "CENTER", 0, 0)
  end
end

-- ★唯一复位口：主窗 + 总览窗一起回屏幕正中（清位置记忆 ⇒ 下一局开窗也是正中）
B.recenter = function(why)
  local c = B.cfg()
  c.point = nil
  c.vpoint = nil
  local f = B.ui.frame
  if isObj(f) then
    pcall(f.ClearAllPoints, f)
    pcall(f.SetPoint, f, "CENTER", UIParent, "CENTER", 0, 0)
  end
  B.viewRehost()
  B.traceAdd("recenter", strVal(why or ""))
  sayForce(L("WIN_CENTERED", strVal(why or "")))
  return true
end

-- 自动档：位置越界才动手（正常位置一次调用只读一次 GetPoint，什么都不写）
B.winAuto = function(where)
  local why = B.winOff(B.ui.frame)
  if why == nil then return false end
  B.recenter(strVal(where or "") .. "：" .. why)
  return true
end
function B.build()
  if B.ui.frame ~= nil then return true end
  if type(CreateFrame) ~= "function" then return false end
  local c = B.cfg()
  local W, H = 520, 420
  local f = CreateFrame("Frame", "EH_BagFrame", UIParent)
  f:SetWidth(W)
  f:SetHeight(H)
  -- ★★★0.3.26：**资源来源一次性判定**（自带优先 → 客户端兜底；探针 + 负对照，见 B.resScan）——
  --   必须排在**任何贴图创建之前**（下面 SetBackdrop 的 bgFile/edgeFile 就是第一批消费者）。
  B.resScan(f)
  if type(f.SetClampedToScreen) == "function" then pcall(f.SetClampedToScreen, f, true) end
  -- ★不设 SetMovable —— 拖拽走项目已验证三件套（StartMoving 那套只有 OnDragStop 一条收尾路，
  --   丢了鼠标捕获就永远收不了尾 = 用户报的「拖拽开始之后不能正常停止拖拽」）。
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, true) end
  local okBD = pcall(f.SetBackdrop, f, {
    bgFile = B.res("ChatFrameBackground", "Interface\\ChatFrame\\ChatFrameBackground"),
    edgeFile = B.res("UI-Tooltip-Border", "Interface\\Tooltips\\UI-Tooltip-Border"),
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  if okBD then
    -- ★0.3.14：窗底 alpha 走唯一读口 `B.bgK()`（默认 0.45 —— 用户要的「第二张图那种通透感」）
    pcall(f.SetBackdropColor, f, 0.03, 0.03, 0.03, B.bgK())
    pcall(f.SetBackdropBorderColor, f, 0.55, 0.45, 0.18, 1)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    solid(bg, 0.03, 0.03, 0.03, B.bgK())
    -- ★这条退路也要交出句柄：`B.bgApply()` 得能改到它（两条建成路各自兑现，绝不只做 SetBackdrop 那一条）
    f.ehBg = bg
  end
  if type(f.SetFrameStrata) == "function" then pcall(f.SetFrameStrata, f, "DIALOG") end
  if type(f.SetFrameLevel) == "function" then pcall(f.SetFrameLevel, f, 80) end

  -- 位置记忆（口径：把 GetPoint(1) 的锚点四元组原样存下来 —— 无损、且不必掺缩放）
  local p = c.point
  local px, py, pa, pb = 0, 0, "CENTER", "CENTER"
  if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then
    px, py = p.x, p.y
    if type(p.a) == "string" then pa = p.a end
    if type(p.b) == "string" then pb = p.b end
    -- ★越界回归（项目铁律：每个记忆位置的窗口都要回归）：离谱值一律回正中
    if math.abs(px) > 4000 or math.abs(py) > 4000 then
      px, py, pa, pb = 0, 0, "CENTER", "CENTER"
      c.point = nil
    end
  end
  pcall(f.SetPoint, f, pa, UIParent, pb, px, py)

  -- 拖动柄：必须是 Button（Frame 的 OnDragStart 在本客户端不触发，项目铁律）
  local drag = CreateFrame("Button", "EH_BagDrag", f)
  B.ui.drag = drag
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
  drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -8)
  drag:SetHeight(22)
  if type(drag.EnableMouse) == "function" then pcall(drag.EnableMouse, drag, true) end
  if type(drag.RegisterForClicks) == "function" then pcall(drag.RegisterForClicks, drag, "LeftButtonUp") end
  if type(drag.RegisterForDrag) == "function" then pcall(drag.RegisterForDrag, drag, "LeftButton") end
  -- ★起拖 = OnMouseDown（项目已验证配方；OnDragStart 只作兜底，两者都幂等）
  drag:SetScript("OnMouseDown", function(button)
    if type(button) ~= "string" then button = arg1 end
    if button == "LeftButton" then B.dragStart(f, "point") end
  end)
  drag:SetScript("OnDragStart", function() B.dragStart(f, "point") end)
  drag:SetScript("OnDragStop", function() B.dragStop("dragstop") end)
  -- ★收尾路 ①：柄上的鼠标捕获还在时，松开那一下会回到柄
  drag:SetScript("OnMouseUp", function() B.dragStop("mouseup") end)
  -- ★收尾路 ②：全屏接盘（**两只同生共死**）。
  --   主接盘挂**最顶级父类**（用户点名）：本客户端开全屏地图会隐藏 UIParent（项目在案 —— EvalHelp.lua 的
  --   ddHost() 就是为此改挂 WorldFrame：「开图时不隐藏、关图后也一直在」），挂 UIParent 的接盘开图时
  --   一个像素都不渲染、也收不到事件 ⇒ 开图时收不了尾。
  --   ★但 WorldFrame 自己的矩形是否满屏**没有实测证据** ⇒ 再在 UIParent 上挂一只**备份**（两只同时显示、
  --   同时收起，唯一隐藏出口 = B.dragStop）；任何一只收到松开都能收尾，两边都不留吃点击的空层。
  --   strata = FULLSCREEN_DIALOG（压过地图帧那个 FULLSCREEN）、level 抬到 9999 ⇒ 谁也盖不住它。
  local function mkCatch(host, nm)
    local c2 = CreateFrame("Button", nm, host)
    local okAll = false
    if type(c2.SetAllPoints) == "function" then okAll = pcall(c2.SetAllPoints, c2, host) end
    if okAll ~= true then
      pcall(c2.SetPoint, c2, "TOPLEFT", host, "TOPLEFT", 0, 0)
      pcall(c2.SetPoint, c2, "BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    end
    if type(c2.SetFrameStrata) == "function" then pcall(c2.SetFrameStrata, c2, "FULLSCREEN_DIALOG") end
    if type(c2.SetFrameLevel) == "function" then pcall(c2.SetFrameLevel, c2, 9999) end
    if type(c2.EnableMouse) == "function" then pcall(c2.EnableMouse, c2, true) end
    if type(c2.RegisterForClicks) == "function" then pcall(c2.RegisterForClicks, c2, "LeftButtonUp") end
    c2:SetScript("OnMouseUp", function() B.dragStop("catch") end)
    c2:SetScript("OnClick", function() B.dragStop("catch") end)
    pcall(c2.Hide, c2)
    return c2
  end
  local dhost = rawget(_G, "WorldFrame")
  if not isObj(dhost) then dhost = rawget(_G, "UIParent") end
  if not isObj(dhost) then dhost = f end
  B.ui.dragCatch = mkCatch(dhost, "EH_BagDragCatch")
  B.ui.dragHost = dhost
  local uip = rawget(_G, "UIParent")
  B.ui.dragCatch2 = nil
  if isObj(uip) and uip ~= dhost then B.ui.dragCatch2 = mkCatch(uip, "EH_BagDragCatch2") end
  local title = font(f)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)
  f.ehTitle = title

  -- ★容量行放**底部左侧**（照参考 Info1 = "143/160背包"）；**金钱放底部右侧**（照参考 MoneyFrame）
  --   ★0.3.15：这里的初值跟着 B.metrics() 一起改成「离框 16z 边 / 14z 底」（两处不一致 =
  --   万一度量那一步早退，窗就是一半新一半旧）
  local cap = font(f)
  cap:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  pcall(cap.SetJustifyH, cap, "LEFT")
  pcall(cap.SetTextColor, cap, 0.95, 0.85, 0.45)
  f.ehCap = cap

  -- ★★★0.3.16 金钱行 = 三对「数字 + 金币图标」（图集 + TexCoords，照客户端 MoneyFrame 的做法）
  --   链的顺序（从右到左）：铜图标 → 铜数字 → 银图标 → 银数字 → 金图标 → 金数字
  --   ★锚点一律由 B.metrics 用 z 重设（单一来源）；这里给初始锚，metrics 万一早退也照样能用。
  --   ★0.3.25：图集路径先过**来源判定口**（自带优先 → 客户端兜底，见 B.mnyPickUI）——建窗期只算一次。
  local mnyPath = B.mnyPickUI(f) or B.MNY_TEX
  local moneyT, moneyI = {}, {}
  local mkList = { "c", "s", "g" }
  local mi
  for mi = 1, table.getn(mkList) do
    local k = mkList[mi]
    local ic = f:CreateTexture(nil, "ARTWORK")
    pcall(ic.SetTexture, ic, mnyPath)
    pcall(ic.SetTexCoord, ic, B.MNY_UV[k][1], B.MNY_UV[k][2], 0, 1)
    pcall(ic.Hide, ic)          -- ★显隐走显式控件清单（建出来先收起，由 moneyPaint 定夺）
    moneyI[k] = ic
    local t = font(f)
    pcall(t.SetJustifyH, t, "RIGHT")
    pcall(t.SetTextColor, t, B.MNY_RGB[k][1], B.MNY_RGB[k][2], B.MNY_RGB[k][3])
    pcall(t.Hide, t)
    moneyT[k] = t
  end
  f.ehMoneyT = moneyT
  f.ehMoneyI = moneyI
  -- ★★★0.3.24/0.3.26 **外部美术可用性自证**：金钱图集与那 15 张固定贴图现在**都自带一份**（见 B.RES_LIST），
  --   但自带那份也可能读不出来 ⇒ 建窗期**读回自证一次**：明确读不到（判不出**不算**）就让 moneyPaint
  --   只画文字 + 补 g/s/c 后缀 —— 免得三个数字分不清（fail-open：宁可文字加后缀，也绝不留三个认不出的数字）。
  B.mnyOK = nil
  if isObj(moneyI.c) and type(moneyI.c.GetTexture) == "function" then
    local okT, vT = pcall(moneyI.c.GetTexture, moneyI.c)
    if okT then B.mnyOK = (type(vT) == "string" and vT ~= "") end
  end
  -- ★★★0.3.25：选了自带那份、但**读回明确为空** ⇒ 当场退回客户端那份（只退一次，退完不再纠缠）——
  --   这是「自带优先」的安全网：探针万一被判成「有」而实际画不出来，金钱行照旧有图标（绝不静默变差）。
  if B.mnyOK == false and B.MNY_SEL ~= B.MNY_TEX then
    B.MNY_WHY = B.MNY_WHY .. "→读回为空，退回客户端"
    B.MNY_SEL = B.MNY_TEX
    local k3, v3
    for k3, v3 in pairs(moneyI) do pcall(v3.SetTexture, v3, B.MNY_TEX) end
    local okT2, vT2 = pcall(moneyI.c.GetTexture, moneyI.c)
    if okT2 then B.mnyOK = (type(vT2) == "string" and vT2 ~= "") end
  end
  moneyI.c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
  moneyT.c:SetPoint("RIGHT", moneyI.c, "LEFT", -2, 0)
  moneyI.s:SetPoint("RIGHT", moneyT.c, "LEFT", -7, 0)
  moneyT.s:SetPoint("RIGHT", moneyI.s, "LEFT", -2, 0)
  moneyI.g:SetPoint("RIGHT", moneyT.s, "LEFT", -7, 0)
  moneyT.g:SetPoint("RIGHT", moneyI.g, "LEFT", -2, 0)

  local close = mkBtn(f, 18, 18, "X", function()
    B.hide("close")
  end)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -9)
  f.ehClose = close
  -- 标题栏三颗小按钮（照参考：整理 = packupButton / 设置 = configButton 都在标题栏）
  local optb = mkBtn(f, 22, 18, L("OPT"), nil)
  optb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -31, -9)
  optb:SetScript("OnClick", function()
    B.menuToggle(optb)
  end)
  f.ehOptBtn = optb
  local sortb = mkBtn(f, 30, 18, L("SORT"), function()
    B.sortStart(true)
  end)
  sortb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -56, -9)
  f.ehSortBtn = sortb
  local viewb = mkBtn(f, 30, 18, L("VIEW"), function()
    B.viewToggle()
  end)
  viewb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -89, -9)
  f.ehViewBtn = viewb

  -- 搜索框（EditBox 在本客户端有「疑似不渲染」的先例 ⇒ 配一行回声保底）
  local sbox = CreateFrame("Frame", nil, f)
  sbox:SetPoint("TOPLEFT", f, "TOPLEFT", 102, -30)
  sbox:SetWidth(230)
  sbox:SetHeight(20)
  f.ehSbox = sbox
  local sfill = sbox:CreateTexture(nil, "BACKGROUND")
  sfill:SetPoint("TOPLEFT", sbox, "TOPLEFT", 0, 0)
  sfill:SetPoint("BOTTOMRIGHT", sbox, "BOTTOMRIGHT", 0, 0)
  -- ★★★0.3.22：搜索框**背景透明度 = 0**（用户：「输入框的边框和格子的边框机制相同.背景透明度0」）——
  --   与格子同一套观感：里面透出背板，只靠一圈边框界定范围（旧写法是不透明暗底 0.10,0.10,0.10,1）。
  solid(sfill, 0.10, 0.10, 0.10, 0)
  -- ★★★0.3.22：搜索框的**边框 = 与格子同一套机制**（用户点名）：同一张自带白框贴图 `B.SLOT_TEX`、
  --   同一个绘制层（`ARTWORK`，与 `ehSlot` 一致）、同一色调（`B.SLOT_DIM`，与空格/普通品质同色）。
  -- ★★★0.3.23 修「铺满长条 ⇒ 边框被横向拉扁」（用户截图：两端成了两根粗竖条、上下两条线细得几乎看不见）：
  --   旧写法把整张 64×64 **铺满**长条 ⇒ 竖直的两条线按**横向**比例被放大（160px 宽 ≈ 12 倍）、
  --   水平的上下两条线按**纵向**被压扁（≈ 0.25 倍）⇒ 一头粗一头细，看着就不像个框。
  --   现在改**横向三片切**（同一张图、同一套机制，只是切开画）：
  --     左端片 = 圆角那一段（源 u 12/64..16/64）· 中段片（16/64..47/64，只含上下两条**横**线 ——
  --     横着拉伸不改变线宽）· 右端片（47/64..51/64）；
  --   ★纵向也只取画框那一带（源 v 13/64..52/64）⇒ 每片高 = 框高、**等比**缩放 ⇒ 四周线宽一致，
  --     且与格子同一比例（源 3px / 画框 39px，实测 slotframe.tga：画框 x 12..50 · y 13..51 · 圆角≈3px）。
  --   ★几何现算在 `B.sboxEdgeFit(w, h)`（顶栏掉第二排 / 换缩放都跟着走）——**唯一几何口**仍由 B.ctrlApply 调。
  local sedgeL = sbox:CreateTexture(nil, "ARTWORK")
  pcall(sedgeL.SetTexture, sedgeL, B.SLOT_TEX)
  pcall(sedgeL.SetTexCoord, sedgeL, 12 / 64, 16 / 64, 13 / 64, 52 / 64)
  pcall(sedgeL.SetVertexColor, sedgeL, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, 1)
  local sedgeM = sbox:CreateTexture(nil, "ARTWORK")
  pcall(sedgeM.SetTexture, sedgeM, B.SLOT_TEX)
  pcall(sedgeM.SetTexCoord, sedgeM, 16 / 64, 47 / 64, 13 / 64, 52 / 64)
  pcall(sedgeM.SetVertexColor, sedgeM, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, 1)
  local sedgeR = sbox:CreateTexture(nil, "ARTWORK")
  pcall(sedgeR.SetTexture, sedgeR, B.SLOT_TEX)
  pcall(sedgeR.SetTexCoord, sedgeR, 47 / 64, 51 / 64, 13 / 64, 52 / 64)
  pcall(sedgeR.SetVertexColor, sedgeR, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, 1)
  f.ehSboxEdgeL, f.ehSboxEdgeM, f.ehSboxEdgeR = sedgeL, sedgeM, sedgeR
  pcall(B.sboxEdgeFit, sbox:GetWidth(), sbox:GetHeight())
  local edit = CreateFrame("EditBox", nil, sbox)
  edit:SetPoint("LEFT", sbox, "LEFT", 6, 0)
  edit:SetPoint("RIGHT", sbox, "RIGHT", -24, 0)
  edit:SetHeight(18)
  edit:SetAutoFocus(false)
  if type(edit.SetMaxLetters) == "function" then pcall(edit.SetMaxLetters, edit, 24) end
  if type(edit.SetFontObject) == "function" then
    local fo = _G.GameFontHighlightSmall or _G.GameFontNormalSmall
    if fo ~= nil then pcall(edit.SetFontObject, edit, fo) end
  end
  edit:SetText(L("SEARCH"))
  pcall(edit.SetTextColor, edit, 0.85, 0.85, 0.85)
  local clr = mkBtn(sbox, 18, 16, "x", function()
    edit:SetText(L("SEARCH"))
    pcall(edit.ClearFocus, edit)
    B.searchText = ""
    B.applyFilter()
  end)
  clr:SetPoint("RIGHT", sbox, "RIGHT", -2, 0)
  -- ★0.3.16：这颗 ✕ 的**边框不画**（用户：「图3,搜索右侧的 x 按钮边框可以不显示」）
  if isObj(clr.ehBtnEdge) then pcall(clr.ehBtnEdge.Hide, clr.ehBtnEdge) end
  f.ehSboxClr = clr
  -- ★★★操作提示 = 一颗「?」的**悬停气泡**（用户：「操作提示进行tooltip 提示。不要文字」）：
  --   旧写法把整句 HINT 常驻在顶栏右侧 ⇒ 窄窗口下被截断、又白占一行位置。现在顶栏一个文字控件都没有。
  local hb = mkBtn(f, 16, 16, "?", function() sayForce(L("HINT")) end)
  -- ★0.3.16：这颗 ? 的**边框也不画**（用户：「左侧的? 按钮边框也可以不显示」）
  if isObj(hb.ehBtnEdge) then pcall(hb.ehBtnEdge.Hide, hb.ehBtnEdge) end
  hb:SetScript("OnEnter", function()
    local tip = _G.GameTooltip
    if tip == nil or type(tip.SetOwner) ~= "function" then return end
    pcall(tip.SetOwner, tip, hb, "ANCHOR_RIGHT")
    if type(tip.SetText) == "function" then pcall(tip.SetText, tip, L("HINT_TITLE"), 1, 0.82, 0.25) end
    if type(tip.AddLine) == "function" then
      -- 整句按「 · 」拆行（一行一句话，气泡窄也读得清）；拆不出分隔符就整句一行
      local s = L("HINT")
      local k = 0
      for part in string.gmatch(s, "[^·]+") do
        local t = string.gsub(part, "^%s+", "")
        t = string.gsub(t, "%s+$", "")
        if string.len(t) > 0 and k < 8 then
          pcall(tip.AddLine, tip, t, 0.85, 0.85, 0.85)
          k = k + 1
        end
      end
      if k == 0 then pcall(tip.AddLine, tip, s, 0.85, 0.85, 0.85) end
    end
    if type(tip.Show) == "function" then pcall(tip.Show, tip) end
  end)
  hb:SetScript("OnLeave", function()
    local tip = _G.GameTooltip
    if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  f.ehHelp = hb
  -- 旧的回声行句柄留着（1.12 没有销毁帧的 API）但**永远收起、永不写字**（题面要求「不要文字」）
  local echo = font(f)
  echo:SetPoint("TOPLEFT", f, "TOPLEFT", 226, -50)
  echo:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -50)
  pcall(echo.SetJustifyH, echo, "LEFT")
  echo:SetText("")
  pcall(echo.Hide, echo)
  f.ehEcho = echo

  edit:SetScript("OnEditFocusGained", function()
    if edit:GetText() == L("SEARCH") then edit:SetText("") end
  end)
  edit:SetScript("OnTextChanged", function()
    local txt = edit:GetText()
    if txt == L("SEARCH") then return end
    B.searchText = string.lower(txt or "")
    B.applyFilter()
  end)
  edit:SetScript("OnEscapePressed", function()
    edit:SetText(L("SEARCH"))
    pcall(edit.ClearFocus, edit)
    B.searchText = ""
    B.applyFilter()
  end)
  f.ehEdit = edit

  -- ★★类型筛选 = 8 颗图标按钮（照参考 OneBag 的 CreateCategoryModule）
  --   参考是 36×36 一整排、放在标题栏下方；本窗口顶部空间有限 ⇒ 24×24 同排（语义/图标/配色一字不改）
  --   参考口径照搬：**单选**（点已选中的那颗 = 取消）、**右键 = 取消**、选中金框、悬停出名称 + 件数 + 用法
  local cats = {}
  local ci
  for ci = 1, table.getn(B.CATS) do
    local info = B.CATS[ci]
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(24)
    b:SetHeight(24)
    if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
    if type(b.RegisterForClicks) == "function" then
      pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
    end
    if ci == 1 then
      b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -50)
    else
      b:SetPoint("LEFT", cats[ci - 1], "RIGHT", 2, 0)
    end
    local cbg = b:CreateTexture(nil, "BACKGROUND")
    cbg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    cbg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    solid(cbg, info.r, info.g, info.b, 0.30)
    b.ehCatBg = cbg
    local cic = b:CreateTexture(nil, "ARTWORK")
    cic:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
    cic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    catIconSet(cic, info.icon)
    pcall(cic.SetTexCoord, cic, 0.07, 0.93, 0.07, 0.93)
    b.ehCatIcon = cic
    local chl = b:CreateTexture(nil, "HIGHLIGHT")
    chl:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    chl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    pcall(chl.SetTexture, chl, B.res("ButtonHilight-Square", "Interface\\Buttons\\ButtonHilight-Square"))
    pcall(chl.SetBlendMode, chl, "ADD")
    b.ehCatHl = chl
    -- 选中金框 = 四条 1px 纯色边（0.3.7：旧写法拿九宫格边框贴图拉满 ⇒ 拉出一堆竖线）
    local ced = mkEdge(b, -1)
    ced:SetVertexColor(1, 0.82, 0.25, 1)
    ced:Hide()
    b.ehCatEdge = ced
    b.ehCat = info.id
    b:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        B.catSet("all")
      elseif c.fType == info.id then
        B.catSet("all")
      else
        B.catSet(info.id)
      end
    end)
    b:SetScript("OnEnter", function() B.catTip(b, info) end)
    b:SetScript("OnLeave", function()
      local tip = _G.GameTooltip
      if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    end)
    cats[ci] = b
  end
  f.ehCatBtns = cats
  -- ★品质筛选 = 一排彩色圆点（照参考 OneBagQuality：传说/史诗/精良/优秀/普通+粗糙）
  --   左键 = 只看这一档 · 再点 = 取消 · 右键 = 取消；真值仍是 c.fQual（-1 = 全部，1 = 普通及以下）
  B.QUAL_DOTS = {
    { id = 5, key = "QUAL5" },
    { id = 4, key = "QUAL4" },
    { id = 3, key = "QUAL3" },
    { id = 2, key = "QUAL2" },
    { id = 1, key = "QUAL1" },
  }
  local dots = {}
  local di
  for di = 1, table.getn(B.QUAL_DOTS) do
    local info = B.QUAL_DOTS[di]
    local r, g, b = qualRGB(info.id)
    local d = CreateFrame("Button", nil, f)
    d:SetWidth(16)
    d:SetHeight(16)
    if type(d.EnableMouse) == "function" then pcall(d.EnableMouse, d, true) end
    if type(d.RegisterForClicks) == "function" then
      pcall(d.RegisterForClicks, d, "LeftButtonUp", "RightButtonUp")
    end
    if di == 1 then
      d:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -31)
    else
      d:SetPoint("LEFT", dots[di - 1], "RIGHT", 2, 0)
    end
    -- 暗色底片（fail-open：万一圆点字形画不出来，也还看得见一块**彩色**的小片子）
    local fill = d:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -1, 1)
    solid(fill, r * 0.34, g * 0.34, b * 0.34, 1)
    d.ehFill = fill
    -- ★金框 = 四条 1px 纯色边（0.3.7：九宫格边框贴图拉满会画出竖线）
    local edge = mkEdge(d, 0)
    edge:SetVertexColor(1, 0.85, 0.25, 1)
    edge:Hide()   -- ★金框只在**选中**那一颗上（未选中一颗框都不画 —— 一排小圆点才干净）
    d.ehEdge = edge
    -- ★★★圆点 = 一个**完整的「●」字符**（用户：「稀有度筛选换成小圆点涂色」）：
    --   旧写法 `string.sub(L(info.key), 1, 1)` 按**字节**截中文 ⇒ 屏上是一颗**乱码方块**
    --   （真机截图里那个黑方块就是它）。档名一个字都不显示 —— 颜色本身就是信息。
    local txt = font(d)
    txt:SetPoint("CENTER", d, "CENTER", 0, 0)
    txt:SetText("●")
    pcall(txt.SetTextColor, txt, r, g, b)
    d.ehText = txt
    d.ehRGB = { r, g, b }
    d.ehQual = info.id
    d:SetScript("OnClick", function()
      local mb = arg1
      if mb == "RightButton" then
        B.qualSet(-1)
      else
        B.qualSet((c.fQual == info.id) and -1 or info.id)
      end
    end)
    d:SetScript("OnEnter", function()
      local tip = _G.GameTooltip
      if tip == nil or type(tip.SetOwner) ~= "function" then return end
      pcall(tip.SetOwner, tip, d, "ANCHOR_RIGHT")
      if type(tip.SetText) == "function" then pcall(tip.SetText, tip, L(info.key), r, g, b) end
      if type(tip.AddLine) == "function" then
        pcall(tip.AddLine, tip, L("QUAL_TIP_USE"), 0.7, 0.7, 0.7)
        pcall(tip.AddLine, tip, L("FILTER_NOW") .. B.filterQualLabel(), 0.60, 0.80, 1.00)
      end
      if type(tip.Show) == "function" then pcall(tip.Show, tip) end
    end)
    d:SetScript("OnLeave", function()
      local tip = _G.GameTooltip
      if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
    end)
    dots[di] = d
  end
  f.ehQualDots = dots

  -- 内容区（格子全放这里，按行折行）—— ★初值跟着 B.metrics()/B.ctrlApply() 的新内边距走（16z / 32z）
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -80)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 32)
  if type(content.EnableMouse) == "function" then pcall(content.EnableMouse, content, false) end
  f.ehContent = content

  -- 分区标题（银行）
  local blabel = font(f)
  pcall(blabel.SetTextColor, blabel, 0.95, 0.82, 0.35)
  blabel:SetText(L("BANK_TITLE"))
  pcall(blabel.Hide, blabel)
  f.ehBankLabel = blabel

  -- 底部状态行（银行包位提示）
  local bstat = font(f)
  bstat:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 28)
  pcall(bstat.SetJustifyH, bstat, "LEFT")
  pcall(bstat.SetTextColor, bstat, 0.80, 0.80, 0.80)
  bstat:SetText("")
  f.ehBankStat = bstat

  -- 左侧背包条（与 OneBag 同形：独立窄条，**紧贴主窗左缘**，随主窗一起走）
  --   ★0.3.9（用户：「左侧的背包图标位置要紧贴着有着背包框」）：条宽的内边距 4z → 2z、锚点 -4z → 0
  --   ⇒ 图标右缘离窗框只剩 2z（旧写法 4z 内边距 + 4z 锚点 = 8z 的空档）。
  local zB = B.z()
  local barCell = (B.BARCELL or 30) * zB
  local barW = barCell + 4 * zB
  B.ui.barCell = barCell
  local bar = CreateFrame("Frame", "EH_BagBarFrame", UIParent)
  bar:SetWidth(barW)
  bar:SetHeight(6 * (barCell + 4 * zB) + 10 * zB)
  bar:SetPoint("TOPRIGHT", f, "TOPLEFT", 0, -4 * zB)
  if type(bar.SetFrameStrata) == "function" then pcall(bar.SetFrameStrata, bar, "DIALOG") end
  if type(bar.SetFrameLevel) == "function" then pcall(bar.SetFrameLevel, bar, 79) end
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  barBg:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  solid(barBg, 0.03, 0.03, 0.03, 0.85)
  f.ehBar = bar

  local i
  for i = 1, table.getn(B.BAGS) do
    local bag = B.BAGS[i]
    local b = barButton(bar, i, {
      bag = bag,
      size = barCell,
      onClick = function()
        local c2 = B.cfg()
        c2.show[bag] = not bagShown(bag)
        B.ui.needLayout = true
        B.layout()
        B.refreshAll()
        B.refreshBar()
      end,
      onReceiveDrag = function()
        if type(CursorHasItem) ~= "function" then return end
        local ok, has = pcall(CursorHasItem)
        if not ok or not has then return end
        if bag == 0 then
          if type(PutItemInBackpack) == "function" then pcall(PutItemInBackpack) end
        else
          if type(PutItemInBag) == "function" then pcall(PutItemInBag, bag) end
        end
      end,
      onDragStart = function()
        if bag == 0 then return end
        local inv
        if type(ContainerIDToInventoryID) == "function" then
          local ok, v = pcall(ContainerIDToInventoryID, bag)
          if ok then inv = v end
        end
        if inv == nil then inv = 19 + bag end
        if type(PickupInventoryItem) == "function" then pcall(PickupInventoryItem, inv) end
      end,
      onEnter = function()
        B.hoverBag = bag
        B.refreshAll()
        local tip = _G.GameTooltip
        if tip == nil or type(tip.SetOwner) ~= "function" then return end
        pcall(tip.SetOwner, tip, B.ui.bags[bag], "ANCHOR_RIGHT")
        local nm = L("TITLE")
        if type(GetBagName) == "function" then
          local ok, v = pcall(GetBagName, bag)
          if ok and type(v) == "string" and v ~= "" then nm = v end
        end
        if type(tip.SetText) == "function" then
          pcall(tip.SetText, tip, L("BAG_TIP_FMT", nm, bagSlotsRaw(bag)), 1, 0.82, 0.25)
        end
        if type(tip.AddLine) == "function" then
          pcall(tip.AddLine, tip, L("BAG_TIP_USE"), 0.80, 0.80, 0.80)
        end
        if type(tip.Show) == "function" then pcall(tip.Show, tip) end
      end,
    })
    -- ★排距必须与银行包条、钥匙链**同一把尺子**（`barCell + 4*zB`）：
    --   旧写法写死 `41`（= 老 37 格 + 4）且不带 zB ⇒ 第 5 格顶在 −169、钥匙链顶在 −175 ⇒ **互相压住 24px**
    b:SetPoint("TOP", bar, "TOP", 0, -5 * zB - (i - 1) * (barCell + 4 * zB))
    B.ui.bags[bag] = b
  end

  -- 钥匙链按钮（背包条最下面一格）
  local kb = barButton(bar, 99, {
    bag = B.KEYRING,
    onClick = function()
      local c2 = B.cfg()
      c2.show[B.KEYRING] = not bagShown(B.KEYRING)
      B.ui.needLayout = true
      B.layout()
      B.refreshAll()
      B.refreshBar()
    end,
    onReceiveDrag = function()
      if type(CursorHasItem) ~= "function" then return end
      local ok, has = pcall(CursorHasItem)
      if not ok or not has then return end
      if type(PutKeyInKeyRing) == "function" then
        pcall(PutKeyInKeyRing)
      elseif type(PutItemInBag) == "function" then
        pcall(PutItemInBag, B.KEYRING)
      end
    end,
    onDragStart = function()
      if type(PickupInventoryItem) == "function" then pcall(PickupInventoryItem, 20) end
    end,
    onEnter = function()
      B.hoverBag = B.KEYRING
      B.refreshAll()
      local tip = _G.GameTooltip
      if tip == nil or type(tip.SetOwner) ~= "function" then return end
      pcall(tip.SetOwner, tip, B.ui.keyringBtn, "ANCHOR_RIGHT")
      if type(tip.SetText) == "function" then
        pcall(tip.SetText, tip, L("KEYRING_TIP_FMT", keyringSize()), 1, 0.82, 0.25)
        pcall(tip.AddLine, tip, L("KEYRING_TIP_USE"), 0.80, 0.80, 0.80)
      end
      if type(tip.Show) == "function" then pcall(tip.Show, tip) end
    end,
  })
  kb:SetPoint("TOP", bar, "TOP", 0, -5 * zB - table.getn(B.BAGS) * (barCell + 4 * zB))
  B.ui.keyringBtn = kb

  -- 银行包条（银行开着才显示）
  local bbar = CreateFrame("Frame", "EH_BagBankBar", UIParent)
  bbar:SetWidth(barW)
  bbar:SetHeight(6 * (barCell + 4 * zB) + 10 * zB)
  -- ★0.3.9：银行包条跟着背包条一起贴窗口（两条之间仍是 8z 的固定间隔）
  bbar:SetPoint("TOPRIGHT", f, "TOPLEFT", -(barW + 8 * zB), -4 * zB)
  if type(bbar.SetFrameStrata) == "function" then pcall(bbar.SetFrameStrata, bbar, "DIALOG") end
  if type(bbar.SetFrameLevel) == "function" then pcall(bbar.SetFrameLevel, bbar, 79) end
  local bbarBg = bbar:CreateTexture(nil, "BACKGROUND")
  bbarBg:SetPoint("TOPLEFT", bbar, "TOPLEFT", 0, 0)
  bbarBg:SetPoint("BOTTOMRIGHT", bbar, "BOTTOMRIGHT", 0, 0)
  solid(bbarBg, 0.03, 0.03, 0.03, 0.85)
  f.ehBankBar = bbar

  for i = 1, table.getn(B.BANKBAGS) do
    local bag = B.BANKBAGS[i]
    local inv = 63 + i
    local b = barButton(bbar, i, {
      bag = bag,
      size = barCell,
      onClick = function()
        if B.bankOpen ~= true then return end
        local c2 = B.cfg()
        c2.show[bag] = not bagShown(bag)
        B.ui.needLayout = true
        B.layout()
        B.refreshAll()
      end,
      onReceiveDrag = function()
        if type(CursorHasItem) ~= "function" then return end
        local ok, has = pcall(CursorHasItem)
        if not ok or not has then return end
        if type(PutItemInBag) == "function" then pcall(PutItemInBag, inv) end
      end,
      onDragStart = function()
        if type(PickupInventoryItem) == "function" then pcall(PickupInventoryItem, inv) end
      end,
      onEnter = function()
        B.hoverBag = bag
        B.refreshAll()
        local tip = _G.GameTooltip
        if tip == nil or type(tip.SetOwner) ~= "function" then return end
        pcall(tip.SetOwner, tip, B.ui.bankButtons[bag], "ANCHOR_RIGHT")
        local nm = L("BANK_BAG_FMT", i)
        local n = bagSlotsRaw(bag)
        if n > 0 and type(GetBagName) == "function" then
          local ok, v = pcall(GetBagName, bag)
          if ok and type(v) == "string" and v ~= "" then nm = v end
        end
        if type(tip.SetText) == "function" then
          if n > 0 then
            pcall(tip.SetText, tip, L("BAG_TIP_FMT", nm, n), 1, 0.82, 0.25)
            pcall(tip.AddLine, tip, L("BAG_TIP_USE"), 0.80, 0.80, 0.80)
          else
            pcall(tip.SetText, tip, L("BANK_BAG_LOCKED", i), 1, 0.4, 0.4)
          end
        end
        if type(tip.Show) == "function" then pcall(tip.Show, tip) end
      end,
    })
    b:SetPoint("TOP", bbar, "TOP", 0, -5 * zB - (i - 1) * (barCell + 4 * zB))
    B.ui.bankButtons[bag] = b
  end

  B.ui.frame = f
  B.ui.needLayout = true
  B.metrics()   -- ★界面几何收口（缩放全靠它重建）

  -- ESC 关闭（客户端原生惯例；表不在就跳过）
  if type(UISpecialFrames) == "table" and B.escHooked ~= true then
    B.escHooked = true
    table.insert(UISpecialFrames, "EH_BagFrame")
  end

  f:Hide()
  bar:Hide()
  bbar:Hide()
  B.layout()
  B.refreshBar()
  return true
end

-- ===== 右键设置菜单（参考插件走 DewDrop；本子插件零依赖 ⇒ 自建一颗小菜单）=====
B.MENU_W0 = 214      -- 单列宽（基准；分两列时总宽 = 2 × 这个）
B.MENU_ROW_H0 = 18
B.MENU_PAD0 = 8
B.MENU_W = 214
B.MENU_ROW_H = 18
B.MENU_PAD = 8
-- ★多列排布（用户：「设置整理下支持多列项配置」）：条数 ≤ MENU_MAXROWS0 走单列，超了就分
--   MENU_COLS 列（每列 ≤ MENU_MAXROWS0 行）。
B.MENU_COLS = 2
-- ★0.3.11：9 → 10（menuItems() 17 → 18 条：多了「整理步进」那一行）。
-- ★0.3.12：10 → **11**（menuItems() 18 → **20** 条：又多了「总览格子」与「窗口回到屏幕中间」两行）⇒
--   `per = ceil(20/2) = 10` 仍只有 10 行/列 ⇒ **菜单高度与版式一字未变**，池则再多留出一格余量。
-- ★0.3.13：条数 20 → 21（多了「品质染色」）⇒ `per = 11` = 11 + 10，池 22 ⇒ 余量 1。
-- ★0.3.14：11 → **12**（条数 21 → **22**：又多了「背景透明度」）⇒ `per = ceil(22/2) = 11` **仍只有 11 行/列**
--   ⇒ **菜单高度与版式一字未变**；池 24 ⇒ 余量 2（池必须**恒大于**行数，见下）。
B.MENU_MAXROWS0 = 12
-- 行池：★必须恒 ≥ menuItems() 的条数，且**留一格余量** —— 行是**建一次复用**的池，
--   超池的行**静默不显示**（不报错、看着就是「少了一项」）⇒ 加了新行忘了加池 = 那一行神秘消失。
--   池 = MENU_COLS × MENU_MAXROWS0 = 24（现 menuItems() 23 条 ⇒ 余量 1 行；★0.3.31h「格子间距」那行就是这么挤进池的）。
B.MENU_ROWS = 24

-- ★★★开关行的「状态配色」（0.3.7；用户：「设置栏的开关状态在当前设置背景没正确匹配颜色，开状态和
--   关状态有个颜色」）：开 = 绿、关 = 红、纯数值行（列数/顺序/缩放/动作行）= 中性金。
--   ★单一来源 = 下面这三张表 + menuStateRGB()：行文字色、行左端标记色都从它现算（绝不两处各写一份）。
local MENU_ON_RGB  = { 0.62, 0.95, 0.55 }
local MENU_OFF_RGB = { 0.95, 0.58, 0.52 }
local MENU_VAL_RGB = { 0.92, 0.88, 0.76 }
local MENU_MARK_ON  = { 0.30, 0.85, 0.35 }
local MENU_MARK_OFF = { 0.85, 0.30, 0.25 }
local MENU_MARK_VAL = { 0.62, 0.52, 0.20 }

-- on == true ⇒ 开色；on == false ⇒ 关色；nil ⇒ 中性（非开关行）
local function menuTextRGB(on)
  if on == true then return MENU_ON_RGB[1], MENU_ON_RGB[2], MENU_ON_RGB[3] end
  if on == false then return MENU_OFF_RGB[1], MENU_OFF_RGB[2], MENU_OFF_RGB[3] end
  return MENU_VAL_RGB[1], MENU_VAL_RGB[2], MENU_VAL_RGB[3]
end

local function menuStateRGB(on)
  if on == true then return MENU_MARK_ON[1], MENU_MARK_ON[2], MENU_MARK_ON[3] end
  if on == false then return MENU_MARK_OFF[1], MENU_MARK_OFF[2], MENU_MARK_OFF[3] end
  return MENU_MARK_VAL[1], MENU_MARK_VAL[2], MENU_MARK_VAL[3]
end

-- 菜单行：★不用 mkBtn —— 它的 UI-Tooltip-Border 金框会把每一行画成「一格一格的空箱子」
--   （用户报「设置UI 显示有点错乱」）。扁平行 = 深底 + 左端金色标记 + 悬停高亮 + 左对齐文字。
local function menuRow(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(w)
  b:SetHeight(h)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp") end
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
  solid(bg, 0.10, 0.09, 0.07, 0.90)
  b.ehMenuBg = bg
  local mark = b:CreateTexture(nil, "ARTWORK")
  mark:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
  mark:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
  mark:SetWidth(2)
  solid(mark, 0.62, 0.52, 0.20, 1)
  b.ehMenuMark = mark
  b:SetScript("OnEnter", function()
    pcall(bg.SetVertexColor, bg, 0.20, 0.18, 0.10, 0.95)
    pcall(mark.SetVertexColor, mark, 1, 0.85, 0.30, 1)
  end)
  b:SetScript("OnLeave", function()
    pcall(bg.SetVertexColor, bg, 0.10, 0.09, 0.07, 0.90)
    local mr, mg, mb = menuStateRGB(b.ehOn)
    pcall(mark.SetVertexColor, mark, mr, mg, mb, 1)
  end)
  local fs = font(b)
  fs:SetPoint("LEFT", b, "LEFT", 8, 0)
  pcall(fs.SetJustifyH, fs, "LEFT")
  pcall(fs.SetTextColor, fs, 0.92, 0.88, 0.76)
  -- ★限宽在行内（两列排布时，长文案绝不许穿到右边那一列上去）
  if type(fs.SetWidth) == "function" and w > 20 then pcall(fs.SetWidth, fs, w - 12) end
  b.label = fs
  return b
end

-- 容器显示名（菜单行与总览分区标题共用同一份；别处不许再拼第二份）
local function bagLabel(bag)
  if bag == B.BANK then return L("BANK_PANE") end
  if bag == B.KEYRING then return L("KEYRING") end
  if bag >= 5 then return L("BANK_BAG_FMT", bag - 4) end
  if bag == 0 then return L("TITLE") end
  return L("BAGIDX_FMT", bag)
end

B.bagLabel = bagLabel

local function onOff(v)
  if v then return L("ST_ON") end
  return L("ST_OFF")
end

-- 背包条显隐（唯一写口：窗口开着 且 **c.bar == true** 才显示）
-- ★原来 DEF.bar 是个没人读的死键 ⇒ 这里接上「设置菜单 → 背包条」
--   ★0.3.14：默认档改成**关**（用户：「背包的初始设置参考第三张图片」= 那一行写着「背包条：关」）
--   ⇒ 判据必须写成「**只有显式 true 才算开**」；旧写法 `c.bar ~= false` 把「缺键」也当成开
--   （那是「默认开」的写法）—— 默认档一改，读口不跟着改 = 勾选框显示关、条还在屏上。
function B.barSync()
  local f = B.ui.frame
  if f == nil or isObj(f.ehBar) == false then return end
  local want = (B.visible == true) and (B.cfg().bar == true)
  if want then
    if type(f.ehBar.Show) == "function" then pcall(f.ehBar.Show, f.ehBar) end
  else
    if type(f.ehBar.Hide) == "function" then pcall(f.ehBar.Hide, f.ehBar) end
  end
end

-- 品质筛选（圆点）：唯一写口 —— 写 c.fQual + 刷新圆点着色 + 重筛
function B.qualSet(v)
  local c = B.cfg()
  if type(v) ~= "number" then v = -1 end
  c.fQual = v
  B.refreshQualDots()
  B.applyFilter()
end

-- 圆点着色（唯一绘制口）：选中的那档 = 圆点全亮 + 金框；其余压暗、**一个框都不画**
function B.refreshQualDots()
  local f = B.ui.frame
  if f == nil or type(f.ehQualDots) ~= "table" then return end
  local c = B.cfg()
  local i
  for i = 1, table.getn(f.ehQualDots) do
    local d = f.ehQualDots[i]
    local on = (c.fQual == d.ehQual)
    -- ★用 SetTextColor 的 alpha 分档（FontString 上没有 SetAlpha 这条口 —— 别去猜）
    if isObj(d.ehText) then
      local rgb = d.ehRGB
      if type(rgb) == "table" then
        pcall(d.ehText.SetTextColor, d.ehText, rgb[1], rgb[2], rgb[3], on and 1 or 0.45)
      end
    end
    if isObj(d.ehFill) then pcall(d.ehFill.SetAlpha, d.ehFill, on and 1 or 0.70) end
    if isObj(d.ehEdge) then
      if on then
        pcall(d.ehEdge.SetVertexColor, d.ehEdge, 1, 0.85, 0.25, 1)
        pcall(d.ehEdge.Show, d.ehEdge)
      else
        pcall(d.ehEdge.Hide, d.ehEdge)
      end
    end
  end
end

-- 类型筛选（8 颗图标）：唯一写口 —— 白名单式写 c.fType（垃圾值一律当「全部」）+ 刷新金框 + 重筛
function B.catSet(id)
  local c = B.cfg()
  local ok = false
  if type(id) == "string" then
    local i
    for i = 1, table.getn(B.CATS) do
      if B.CATS[i].id == id then ok = true end
    end
  end
  if ok ~= true then id = "all" end
  c.fType = id
  B.refreshCatBtns()
  B.applyFilter()
end

-- 图标行着色（唯一绘制口）：选中的那颗金框 + 底色/图标不透明，其余压暗
function B.refreshCatBtns()
  local f = B.ui.frame
  if f == nil or type(f.ehCatBtns) ~= "table" then return end
  local c = B.cfg()
  local i
  for i = 1, table.getn(f.ehCatBtns) do
    local b = f.ehCatBtns[i]
    local on = (c.fType == b.ehCat)
    if isObj(b.ehCatEdge) then
      if on then
        pcall(b.ehCatEdge.Show, b.ehCatEdge)
      else
        pcall(b.ehCatEdge.Hide, b.ehCatEdge)
      end
    end
    if isObj(b.ehCatBg) then pcall(b.ehCatBg.SetAlpha, b.ehCatBg, on and 0.75 or 0.30) end
    if isObj(b.ehCatIcon) then pcall(b.ehCatIcon.SetAlpha, b.ehCatIcon, on and 1 or 0.65) end
  end
end

-- 本类物品件数（悬停提示用）：只数「窗口里现在真正在显示的容器」
function B.catCount(id)
  local n = 0
  local list = B.containers()
  local i, s
  for i = 1, table.getn(list) do
    local bag = list[i]
    local cnt = B.bagSlots(bag)
    for s = 1, cnt do
      local rec = B.itemAt(bag, s)
      if rec ~= nil and B.cat8Of(rec.itemType, rec.equipLoc) == id then n = n + 1 end
    end
  end
  return n
end

-- 图标悬停提示（照参考：类别名 + 件数 + 两条用法；末尾补一行「当前筛选」）
function B.catTip(b, info)
  local tip = _G.GameTooltip
  if tip == nil or type(tip.SetOwner) ~= "function" then return end
  pcall(tip.SetOwner, tip, b, "ANCHOR_RIGHT")
  if type(tip.SetText) == "function" then pcall(tip.SetText, tip, L(info.key), info.r, info.g, info.b) end
  if type(tip.AddLine) == "function" then
    pcall(tip.AddLine, tip, L("CAT_TIP_COUNT", B.catCount(info.id)), 0.7, 0.7, 0.7)
    pcall(tip.AddLine, tip, L("CAT_TIP_USE"), 0, 1, 0)
    pcall(tip.AddLine, tip, L("CAT_TIP_AGAIN"), 1, 1, 0)
    pcall(tip.AddLine, tip, L("FILTER_NOW") .. B.filterTypeLabel(), 0.60, 0.80, 1.00)
  end
  if type(tip.Show) == "function" then pcall(tip.Show, tip) end
end

-- 每行列数循环（8→10→12→14→16→8）
function B.cycleCols()
  local c = B.cfg()
  local seq = { 8, 10, 12, 14, 16 }
  local cur = tonumber(c.cols) or DEF.cols
  local idx = 1
  local i
  for i = 1, table.getn(seq) do
    if seq[i] <= cur then idx = i end
  end
  idx = idx + 1
  if idx > table.getn(seq) then idx = 1 end
  c.cols = seq[idx]
  B.ui.needLayout = true
  B.layout()
  B.refreshAll()
  say(L("MENU_COLS_FMT", c.cols))
end

-- 命令口改完顺序后的重排（与菜单那颗按钮同一套动作，避免两处各写一份）
function B.cycleDirCheck()
  B.ui.needLayout = true
  B.layout()
  B.refreshAll()
end

-- 背包顺序（参考的 show.direction）：'fwd'（默认，背包在前）/ 'rev'（最后一个包在前）
function B.cycleDir()
  local c = B.cfg()
  if c.direction == "rev" then
    c.direction = "fwd"
  else
    c.direction = "rev"
  end
  B.ui.needLayout = true
  B.layout()
  B.refreshAll()
  say(L("MENU_DIR") .. "：" .. ((c.direction == "rev") and L("DIR_REV") or L("DIR_FWD")))
end

-- 菜单行清单（单一来源：右键菜单与 /ebag 命令共用同一批开关）
function B.menuItems()
  local c = B.cfg()
  local out = {}
  local i
  for i = 1, table.getn(B.BAGS) do
    local bag = B.BAGS[i]
    table.insert(out, {
      on = bagShown(bag),
      text = bagLabel(bag) .. "：" .. onOff(bagShown(bag)),
      fn = function()
        c.show[bag] = (bagShown(bag) == false)
        B.ui.needLayout = true
        B.layout()
        B.refreshAll()
        B.refreshBar()
      end,
    })
  end
  table.insert(out, {
    on = bagShown(B.KEYRING),
    text = bagLabel(B.KEYRING) .. "：" .. onOff(bagShown(B.KEYRING)),
    fn = function()
      c.show[B.KEYRING] = (bagShown(B.KEYRING) == false)
      B.ui.needLayout = true
      B.layout()
      B.refreshAll()
      B.refreshBar()
    end,
  })
  table.insert(out, {
    on = (c.edges ~= false),
    text = L("MENU_EDGES") .. "：" .. onOff(c.edges ~= false),
    fn = function()
      c.edges = not (c.edges ~= false)
      B.refreshAll()
    end,
  })
  -- ★★★0.3.13：品质染色浓淡（用户：「装备染色还不够亮眼.需要更加鲜丽的颜色」）
  --   点一下循环 标准 → 鲜丽 → 极鲜（写口 B.tintSet / 线 B.tintCycle，与 `/ebag tint` 共用）
  table.insert(out, {
    text = L("MENU_TINT") .. "：" .. B.tintText(),
    fn = function() B.tintCycle() end,
  })
  table.insert(out, {
    -- ★0.3.14：默认关 ⇒ 状态与切换都必须判「**显式 true**」（旧写法 `~= false` = 默认开的写法）
    on = (c.bar == true),
    text = L("MENU_BAR") .. "：" .. onOff(c.bar == true),
    fn = function()
      c.bar = not (c.bar == true)
      -- ★★★0.3.12 真因修复：这里原来只调 `B.refreshBar()`（它**只画图标/染色、绝不碰显隐**）
      --   ⇒ `c.bar` 变了、屏上一点反应都没有 = 用户报的「背包条显示/隐藏无法正确生效」。
      --   显隐唯一实现是 `B.barSync()`（`B.show`/`B.layout` 都走它）⇒ 改完必须调它，再重画图标。
      B.barSync()
      B.refreshBar()
    end,
  })
  -- ★★★0.3.14：窗背景透明度（用户：「背包背景透明度参考第二张图片的背景透明度」——
  --   参考插件 OneBag 的默认是黑 0.45）⇒ 点一下循环档位（写口 B.bgSet / 线 B.bgCycle，与 `/ebag alpha` 共用）
  table.insert(out, {
    text = L("MENU_BG") .. "：" .. B.bgText(),
    fn = function() B.bgCycle() end,
  })
  -- ★★★0.3.31h：格子边距（用户：「将以上间距添加入背包设置」）⇒ 点一下循环档位（写口 B.cgapSet / 线 B.cgapCycle，与 `/ebag cgap` 共用；池 24 余量 2 → 1，几何常量不动）
  table.insert(out, {
    text = L("MENU_CGAP") .. "：" .. strVal(B.cgap()) .. "px",
    fn = function() B.cgapCycle() end,
  })
  table.insert(out, {
    on = (c.autoShow ~= false),
    text = L("AUTO_LABEL") .. "：" .. onOff(c.autoShow ~= false),
    fn = function()
      c.autoShow = not (c.autoShow ~= false)
      say(c.autoShow and L("AUTO_ON") or L("AUTO_OFF"))
    end,
  })
  table.insert(out, {
    text = L("MENU_COLS_FMT", tonumber(c.cols) or DEF.cols),
    fn = function() B.cycleCols() end,
  })
  table.insert(out, {
    on = (c.bagBreak == true),
    text = L("MENU_BAGBREAK") .. "：" .. onOff(c.bagBreak == true),
    fn = function()
      c.bagBreak = (c.bagBreak ~= true)
      B.ui.needLayout = true
      B.layout()
      B.refreshAll()
    end,
  })
  table.insert(out, {
    on = (c.vAlign == "bottom"),
    text = L("MENU_VALIGN") .. "：" .. onOff(c.vAlign == "bottom"),
    fn = function()
      if c.vAlign == "bottom" then c.vAlign = "top" else c.vAlign = "bottom" end
      B.ui.needLayout = true
      B.layout()
      B.refreshAll()
    end,
  })
  table.insert(out, {
    text = L("MENU_DIR") .. "：" .. ((c.direction == "rev") and L("DIR_REV") or L("DIR_FWD")),
    fn = function() B.cycleDir() end,
  })
  table.insert(out, {
    text = L("SORT"),
    fn = function() B.sortStart(true) end,
  })
  -- ★★★0.3.11：整理步进一行（左键 = 循环档位：逐项 0.45 → 标准 0.30 → 快 0.20 → 极快 0.12）。
  --   用户 0.3.11 报「逐项展示整理过程没有了」⇒ 把「整理要多快」变成**一眼能看见、一点能改**的一行，
  --   而不是只藏在 `/ebag gap` 里（写口仍是同一个 B.gapSet ⇒ 不可能各写一半）。
  table.insert(out, {
    text = L("MENU_GAP") .. "：" .. B.gapText(),
    fn = function() B.gapCycle() end,
  })
  table.insert(out, {
    text = L("MENU_SCALE") .. "：" .. L("MENU_SCALE_HINT", B.scalePct()),
    fn = function() B.scaleStepBy(1) end,
    fnR = function() B.scaleStepBy(-1) end,
  })
  -- ★★★0.3.12：总览格子一行（用户：「缩小图标方便显示更多的信息」）
  --   点一下循环 小 → 中 → 大（写口 B.vsizeSet / 线 B.vsizeCycle，与 `/ebag vsize` 共用）
  table.insert(out, {
    text = L("MENU_VSIZE") .. "：" .. B.vsizeText(),
    fn = function() B.vsizeCycle() end,
  })
  -- ★★★0.3.12：窗口回到屏幕中间（用户：「自动重置背包到当前屏幕中间定位」——
  --   自动自愈在 B.show / B.dragStart / B.dragStop 三处；这一行是**手动兜底**，
  --   给「窗口明明在屏上、但就是想把它摆回正中」的场合用）
  table.insert(out, {
    text = L("MENU_WIN_CENTER"),
    fn = function() B.recenter(L("MENU_WIN_CENTER")) end,
  })
  table.insert(out, {
    text = L("VIEW_TITLE"),
    fn = function() B.viewToggle() end,
  })
  table.insert(out, {
    text = L("MENU_STATUS"),
    fn = function() B.status() end,
  })
  return out
end

-- 菜单：建一次、之后只 Show/Hide（1.12 没有销毁帧的 API ⇒ 建出来就留着）
function B.buildMenu()
  if B.ui.menu ~= nil then return true end
  if type(CreateFrame) ~= "function" then return false end
  -- ★菜单也随界面缩放（只在这里算一次；menuOpen 用同一组常量算高度）
  local zM = B.z()
  B.MENU_W = B.MENU_W0 * zM
  B.MENU_ROW_H = B.MENU_ROW_H0 * zM
  B.MENU_PAD = B.MENU_PAD0 * zM
  local m = CreateFrame("Frame", "EH_BagMenuFrame", UIParent)
  m:SetWidth(B.MENU_W)
  m:SetHeight(B.MENU_ROWS * B.MENU_ROW_H + B.MENU_PAD)
  if type(m.EnableMouse) == "function" then pcall(m.EnableMouse, m, true) end
  local okBD = pcall(m.SetBackdrop, m, {
    bgFile = B.res("ChatFrameBackground", "Interface\\ChatFrame\\ChatFrameBackground"),
    edgeFile = B.res("UI-Tooltip-Border", "Interface\\Tooltips\\UI-Tooltip-Border"),
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  if okBD then
    pcall(m.SetBackdropColor, m, 0.04, 0.04, 0.04, 0.96)
    pcall(m.SetBackdropBorderColor, m, 0.62, 0.52, 0.20, 1)
  else
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", m, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", 0, 0)
    solid(bg, 0.04, 0.04, 0.04, 0.96)
  end
  if type(m.SetFrameStrata) == "function" then pcall(m.SetFrameStrata, m, "DIALOG") end
  if type(m.SetFrameLevel) == "function" then pcall(m.SetFrameLevel, m, 92) end
  local rows = {}
  local i
  for i = 1, B.MENU_ROWS do
    local r = menuRow(m, B.MENU_W - 8, B.MENU_ROW_H - 2)
    r:SetPoint("TOPLEFT", m, "TOPLEFT", 4, -4 - (i - 1) * B.MENU_ROW_H)
    r:SetScript("OnClick", function()
      -- ★右键 = 那一行的**反向动作**（有 fnR 才认，例如「界面缩放」右鍵 −10%），没有就等同左键
      local fn = r.ehFn
      if arg1 == "RightButton" and type(r.ehFnR) == "function" then fn = r.ehFnR end
      if type(fn) == "function" then pcall(fn) end
      -- ★★点完**不关菜单**（用户定：「在设置一个选项之后不要关闭UI，UI 关闭只在非当前 UI 弹窗内点击才触发」）
      --   ⇒ 唯一的关闭出口是全屏捕手 EH_BagMenuCatch；这里只当场重画（开关行的文字/选中态都变了）
      B.menuFill()
    end)
    pcall(r.Hide, r)
    table.insert(rows, r)
  end
  B.ui.menu = m
  B.ui.menuRows = rows
  -- 全屏捕手（项目铁律：点弹窗外即关 = 宿主自建全屏捕获 Button；唯一隐藏出口要把它一起隐藏）
  -- ★★★0.3.7 改层级（用户：「拖拽在设置背包开关切换这以后.有些物品无法进行拖拽」）：
  --   捕手原来 88 > 主窗 80 ⇒ **菜单开着时整扇背包窗都被它盖住**（0.3.5 起点完一行菜单不关 ⇒
  --   菜单一直开着 ⇒ 格子全点不动、也拖不动）。现在捕手压到**窗口之下**（76 < 窗口 80 < 菜单 92）
  --   ⇒ 窗口区域（含格子/拖拽柄）照旧能点能拖，窗口以外的全屏区域仍由捕手负责「点外面即关」。
  local catch = CreateFrame("Button", "EH_BagMenuCatch", UIParent)
  local sw, sh = 1024, 768
  if type(GetScreenWidth) == "function" then
    local ok, v = pcall(GetScreenWidth)
    if ok and type(v) == "number" and v > 0 then sw = v end
  end
  if type(GetScreenHeight) == "function" then
    local ok, v = pcall(GetScreenHeight)
    if ok and type(v) == "number" and v > 0 then sh = v end
  end
  catch:SetWidth(sw)
  catch:SetHeight(sh)
  catch:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  if type(catch.SetFrameStrata) == "function" then pcall(catch.SetFrameStrata, catch, "DIALOG") end
  if type(catch.SetFrameLevel) == "function" then pcall(catch.SetFrameLevel, catch, 76) end
  catch:SetScript("OnClick", function() B.menuClose() end)
  pcall(catch.Hide, catch)
  B.ui.menuCatch = catch
  -- ★捕手不再盖窗口 ⇒ 补充那条「点在窗口上也算点外面」的路（0.3.5 口径不变：点弹窗外面就关）。
  --   ★子件（格子 / 拖拽柄 / 顶栏控件）在父帧之上 ⇒ 点它们**不会**走到这里 ⇒ 拖拽照旧可用。
  local wf = B.ui.frame
  if isObj(wf) and type(wf.SetScript) == "function" then
    wf:SetScript("OnMouseDown", function()
      if B.menuShown == true then B.menuClose() end
    end)
  end
  pcall(m.Hide, m)
  return true
end

function B.menuClose()
  B.menuShown = false
  if isObj(B.ui.menu) then pcall(B.ui.menu.Hide, B.ui.menu) end
  if isObj(B.ui.menuCatch) then pcall(B.ui.menuCatch.Hide, B.ui.menuCatch) end
end

-- ★★菜单重画（**唯一**填充/排布口）：menuOpen 与「点完一行」都走它 ⇒ 开关行文字、行数、
--   列数、菜单高宽永远是**同一份实现**算出来的（两处各写一份 = 下一个漏改点）。
--   返回菜单总宽（menuOpen 用它做「右边放不下就翻左边」的判据）。
function B.menuFill()
  local m = B.ui.menu
  if isObj(m) == false then return 0 end
  local rows = B.ui.menuRows
  if type(rows) ~= "table" then return 0 end
  local zM = B.z()
  B.MENU_ROW_H = B.MENU_ROW_H0 * zM
  B.MENU_PAD = B.MENU_PAD0 * zM
  local items = B.menuItems()
  local n = table.getn(items)
  local cols = B.MENU_COLS
  -- ★装得下就单列（单列最窄、最不挡视线），装不下才分列
  if n <= B.MENU_MAXROWS0 then cols = 1 end
  local per = math.ceil(n / cols)
  if per < 1 then per = 1 end
  local colW = B.MENU_W0 * zM
  B.MENU_W = cols * colW
  B.MENU_N = n
  B.MENU_COLS_NOW = cols
  local i
  for i = 1, table.getn(rows) do
    local r = rows[i]
    local it = items[i]
    if it == nil then
      pcall(r.Hide, r)
    else
      local ci = math.floor((i - 1) / per)
      local ri = (i - 1) - ci * per
      r.ehFn = it.fn
      r.ehFnR = it.fnR
      -- ★开关行按状态上色（开=绿 / 关=红 / 纯数值行=中性）：文字与左端标记同一份来源
      r.ehOn = it.on
      if isObj(r.label) then
        pcall(r.label.SetText, r.label, it.text)
        local tr, tg, tb = menuTextRGB(r.ehOn)
        pcall(r.label.SetTextColor, r.label, tr, tg, tb)
      end
      if isObj(r.ehMenuMark) then
        local mr, mg, mb = menuStateRGB(r.ehOn)
        pcall(r.ehMenuMark.SetVertexColor, r.ehMenuMark, mr, mg, mb, 1)
      end
      pcall(r.ClearAllPoints, r)
      pcall(r.SetPoint, r, "TOPLEFT", m, "TOPLEFT", 4 + ci * colW, -4 - ri * B.MENU_ROW_H)
      pcall(r.SetWidth, r, colW - 8)
      pcall(r.SetHeight, r, B.MENU_ROW_H - 2)
      if isObj(r.label) and type(r.label.SetWidth) == "function" then
        pcall(r.label.SetWidth, r.label, colW - 20)
      end
      pcall(r.Show, r)
    end
  end
  pcall(m.SetWidth, m, B.MENU_W)
  pcall(m.SetHeight, m, per * B.MENU_ROW_H + B.MENU_PAD)
  return B.MENU_W
end

function B.menuOpen(anchor)
  if B.buildMenu() == false then return end
  local m = B.ui.menu
  B.menuFill()
  pcall(m.ClearAllPoints, m)
  local host = anchor
  if isObj(host) == false then host = B.ui.frame end
  -- ★挂在窗口**侧边**（旧写法挂 BOTTOMRIGHT ⇒ 菜单压在窗口右半边 = 用户眼里的「错乱」）；
  --   右边放不下就翻到左边（屏幕夹取，读不到屏幕宽度就按右边走 = fail-open）
  local onRight = true
  if isObj(host) and type(host.GetRight) == "function" then
    local okr, r = pcall(host.GetRight, host)
    local sw = 1024
    if type(GetScreenWidth) == "function" then
      local oks, v = pcall(GetScreenWidth)
      if oks and type(v) == "number" and v > 0 then sw = v end
    end
    if okr and type(r) == "number" and (r + B.MENU_W) > (sw - 4) then onRight = false end
  end
  if isObj(host) then
    if onRight then
      pcall(m.SetPoint, m, "TOPLEFT", host, "TOPRIGHT", 2, -4)
    else
      pcall(m.SetPoint, m, "TOPRIGHT", host, "TOPLEFT", -2, -4)
    end
  else
    pcall(m.SetPoint, m, "CENTER", UIParent, "CENTER", 0, 0)
  end
  if isObj(B.ui.menuCatch) then pcall(B.ui.menuCatch.Show, B.ui.menuCatch) end
  pcall(m.Show, m)
  B.menuShown = true
  B.traceAdd("menu", strVal(B.MENU_N or 0) .. " 行/" .. strVal(B.MENU_COLS_NOW or 1) .. " 列")
end

function B.menuToggle(anchor)
  if B.menuShown == true then
    B.menuClose()
  else
    B.menuOpen(anchor)
  end
end

-- ===== OneView（跨角色总览，只读）=====
-- ★与参考 OneBag 的 OneView 同形：独立窗口 + 角色切换 + 逐容器网格 + 只读。
--   数据全部来自 B.snapshot 写进账号级存档的快照；点/拖**不会**动物品（那是别人角色的格子）。
B.VCELL0 = 30   -- 基准（界面缩放 × 档位系数都由 B.viewMetrics() 现算 —— 只乘在这里）
B.VGAP0 = 3
B.VCELL = 30
B.VGAP = 3
B.VCOLS = 9
B.VITEM_MAX = 240
B.VCONTENT_W = 310   -- 内容区基准宽（= 窗宽 330 − 两侧各 10；buildView 与 B.viewMetrics 同一算式）
-- ★★★0.3.17：总览窗的**窗高 / 内容区上下留白**也从这里来 —— 旧写法在 buildView 里写死 `436`/`-72`/`32`，
--   而「窗内放得下几行」也要用同一份数 ⇒ 一处真值两处用（写两份 = 下一个漏改点）。
B.VWIN_H = 436      -- 基准窗高（buildView 的 H = B.VWIN_H * zV）
B.VTOP_GAP = 72     -- 内容区顶（标题行 + 角色行 + 容量行占位）
B.VBOT_GAP = 32     -- 内容区底（金钱行/提示行让位）
B.VHEAD_MAX = 2     -- 段标题池上限（背包段 / 银行段两条 —— 段数是常数，池有界）
-- ★★★0.3.12：总览格子档位（用户：「缩小图标方便显示更多的信息」）—— **唯一来源**，
--   菜单行「总览格子」与 `/ebag vsize 小|中|大` 共用。
--   ★用户问「缩小图标之后对应的图标背景是否也要同时缩小?」⇒ **是，而且四样共用一个来源**：
--     格子边长 `B.VCELL` ⇒ ① 格框环 = 格子 × 64/37、② 图标 = 格子 × ICON_K、
--     ③ 品质底色内缩 = 格子 × 0.07（旧写法写死 2px ⇒ 缩格子后底边相对变粗）、④ 底框边长 = 格子。
--     缩一个数四处一起缩 ⇒ 绝不出现「图标小了、背景还是原尺寸」的错位。
B.VSIZES = { { k = 0.80 }, { k = 0.90 }, { k = 1.00 } }   -- 小 / 中 / 大（默认 = 小）
B.VSIZE_KEYS = { "VS_SMALL", "VS_MID", "VS_BIG" }
B.vsizeIdx = function()
  local k = tonumber(B.cfg().vsize)
  local i
  if k ~= nil then
    for i = 1, table.getn(B.VSIZES) do
      if math.abs(k - B.VSIZES[i].k) < 0.001 then return i end
    end
  end
  return 1     -- 缺键 / 坏数据 ⇒ 第一档（= 小 = 0.3.12 起的新默认档）
end
B.vsizeK = function() return B.VSIZES[B.vsizeIdx()].k end
B.vsizeText = function()
  local i = B.vsizeIdx()
  return L(B.VSIZE_KEYS[i] or "VS_SMALL")
end

-- 唯一写口（菜单行 / `/ebag vsize` 都走它）：认系数（0.8/0.9/1.0）也认档位名（小/中/大）
B.vsizeSet = function(v)
  local c = B.cfg()
  local i = B.vsizeIdx()
  local j
  if type(v) == "number" then
    for j = 1, table.getn(B.VSIZES) do
      if math.abs(v - B.VSIZES[j].k) < 0.001 then i = j end
    end
  elseif type(v) == "string" then
    local s = strVal(v)
    for j = 1, table.getn(B.VSIZE_KEYS) do
      if s == strVal(L(B.VSIZE_KEYS[j])) or s == strVal(B.VSIZE_KEYS[j]) then i = j end
    end
  end
  c.vsize = B.VSIZES[i].k
  B.viewMetrics()
  if type(B.viewFill) == "function" then B.viewFill(true) end
  sayForce(L("MENU_VSIZE") .. " = " .. B.vsizeText()
    .. "（格子 " .. strVal(math.floor(B.VCELL + 0.5)) .. "px ｜ " .. strVal(B.VCOLS) .. " 列）")
  return true
end
B.vsizeCycle = function()
  local n = table.getn(B.VSIZES)
  local i = B.vsizeIdx() + 1
  if i > n then i = 1 end
  B.vsizeSet(B.VSIZES[i].k)
end

-- ★唯一几何口：格子边长 / 间距 / 列数（界面缩放 × 档位系数只乘在这里；
--   列数按内容区宽**现算** ⇒ 换档位后列数自动跟上，绝不写死 9）
B.viewMetrics = function()
  local z = B.z()
  local k = B.vsizeK()
  B.VCELL = B.VCELL0 * z * k
  B.VGAP = B.VGAP0 * z * k
  local avail = (B.VCONTENT_W or 310) * z
  local pitch = B.VCELL + B.VGAP
  local cols = 9
  if pitch > 0.01 then cols = math.floor((avail + B.VGAP) / pitch) end
  if cols < 4 then cols = 4 end
  if cols > 24 then cols = 24 end
  B.VCOLS = cols
end

-- 格子几何**幂等**重设（唯一处）：边长真变了才重发；环/图标/底色/辉光/**底框**一起跟上
B.viewFit = function(b)
  if isObj(b) ~= true then return end
  local cell = B.VCELL
  if b.ehCell == cell then return end
  b.ehCell = cell
  pcall(b.SetWidth, b, cell)
  pcall(b.SetHeight, b, cell)
  -- ★★★0.3.16：底色与格框**同一轮廓、同一把尺子**（圆角实心底 `B.SLOT_FILL` + CENTER + 格子 × B.SLOT_K）
  --   —— 旧写法「整格正方形」的方角会从圆角框外露出来（用户报「四个角突兀」）。
  --   ★★★0.3.20：**辉光层也是这三层之一**（同锚点同尺寸）—— 旧写法漏了它 ⇒ 总览格悬停/品质辉光
  --     停在未缩放的尺寸上（与主窗同一个真因）。
  if isObj(b.ehFill) then
    pcall(b.ehFill.ClearAllPoints, b.ehFill)
    pcall(b.ehFill.SetPoint, b.ehFill, "CENTER", b, "CENTER", 0, 0)
    pcall(b.ehFill.SetWidth, b.ehFill, cell * B.SLOT_K)
    pcall(b.ehFill.SetHeight, b.ehFill, cell * B.SLOT_K)
  end
  if isObj(b.ehGlow) then
    pcall(b.ehGlow.SetWidth, b.ehGlow, cell * B.SLOT_K)
    pcall(b.ehGlow.SetHeight, b.ehGlow, cell * B.SLOT_K)
  end
  -- ★框的放大系数 = **B.SLOT_K**（= 64/39：那张白框贴图 64×64 的画布上，画框只占中间 39×39
  --   ⇒ 乘这个系数后**画框外缘**正好落在格子边上）。
  --   ★0.3.12 的旧写法 `64 / B.VCELL` 再乘 B.VCELL ⇒ **恒等于 64px**（与格子多大无关）⇒ 框比格子大一圈、
  --   图标看着「没对齐」—— 用户报「跨角色总览图标没居中对齐」的真因就是它；0.3.12~0.3.14 用 `64/37`
  --   （UI-Quickslot2 那张环的比例），0.3.15 换素材后跟着改成 `B.SLOT_K`。
  local k = B.SLOT_K
  if isObj(b.ehSlot) then
    pcall(b.ehSlot.SetWidth, b.ehSlot, cell * k)
    pcall(b.ehSlot.SetHeight, b.ehSlot, cell * k)
  end
  if isObj(b.ehIcon) then
    pcall(b.ehIcon.SetWidth, b.ehIcon, cell * B.ICON_K)
    pcall(b.ehIcon.SetHeight, b.ehIcon, cell * B.ICON_K)
  end
end

-- 存档里所有角色（按「最后见到」倒序；时间相同按名字，保证顺序稳定）
function B.viewChars()
  local c = B.cfg()
  local out = {}
  if type(c.chars) ~= "table" then return out end
  local k, r
  for k, r in pairs(c.chars) do
    if type(r) == "table" then
      local t = 0
      if type(r.t) == "number" then t = r.t end
      table.insert(out, { k = k, r = r, t = t })
    end
  end
  table.sort(out, function(a, b)
    if a.t ~= b.t then return a.t > b.t end
    return strVal(a.k) < strVal(b.k)
  end)
  return out
end

local function viewCharLine(e)
  local r = e.r
  return L("VIEW_CHAR_FMT", strVal(r.n or e.k), strVal(r.cls or "?"), strVal(r.lv or "?"))
end

-- ★★★只读物品的气泡 = **客户端的物品信息**（SetHyperlink 是聊天链接那条路，本客户端用它画完整
--   物品信息：属性 / 商人价 / 用法）+ 与格子气泡**同一个两拍口径**。
--   ★0.3.8 真机报障「跨角色总览里所有的物品信息都是空白的」的两条真因：
--     ① 旧写法只拿 `rec.l` 试一次 SetHyperlink；快照里没有链接（或链接形态客户端不认）时
--        连第二条路都没有 ⇒ 直接掉进我们那三行简版；
--     ② 更常见的一条：**当场读回 0 行就当「客户端没填上」**（本客户端 NumLines 有延迟，
--        项目在案）⇒ 立刻 SetText 覆盖 ⇒ 把客户端本来填好的完整信息换成「名字 + 只读」。
--        ⇒ 现在与 mkTip 同一个口径：当场读不出**一个字都不写**，只登记延后复核（B.viewPend），
--        到点仍读不出才写自建文本兜底。
local function viewRichTry(tip, rec)
  if type(rec) ~= "table" then return false end
  if type(tip.SetHyperlink) ~= "function" then return false end
  -- 两种**客户端自己的**写法都试：完整链接（聊天链接同款）→ 极简 `item:<id>`
  --   （本客户端自己的 FrameXML 就是这么调的：CustomMerchantFrame / Turtle_TransmogUI）
  local tries = {}
  if type(rec.l) == "string" and rec.l ~= "" then table.insert(tries, rec.l) end
  local id = nil
  if type(rec.l) == "string" then id = string.match(rec.l, "item:(%d+)") end
  if id ~= nil then table.insert(tries, "item:" .. id) end
  local i
  for i = 1, table.getn(tries) do
    pcall(tip.SetHyperlink, tip, tries[i])
    local has, judged = B.tipRead(tip)
    -- ★「调了」不等于「填上了」：widget 的 Set* 返回值恒 nil 不可信（项目在案）⇒ 读完再决定；
    --   **判不出**按「客户端填上了」处理（fail-open：绝不拿判不出当没填上去覆盖人家的内容）。
    if has == true or judged ~= true then return true end
  end
  return false
end

local function viewTip(owner, rec)
  local tip = _G.GameTooltip
  if tip == nil or type(tip.SetOwner) ~= "function" then return end
  -- ★★换填之前先把上一份的行抹掉（只抹行、不 Hide）：本客户端换填时旧行会留在「行数之外」
  --   （项目在案的坑，EquipCompare 那条同源）⇒ 不抹就会把背包格子的原生信息混进快照气泡里
  --   —— 两个流程的展示必须**互不串味**（用户正是拿总览那份来跟背包的对比）。
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  pcall(tip.SetOwner, tip, owner, "ANCHOR_RIGHT")
  B.viewPend = nil
  local rich = viewRichTry(tip, rec)
  B.viewTipRich = rich
  B.viewWhy = nil
  if rich ~= true then
    B.viewPend = { owner = owner, rec = rec, t = GetTime() }
    -- ★★★0.3.10：登记待办**必须当场挂节拍**（同 mkTip 那条真因）—— 那一刻节拍通常是摘着的，
    --   不挂就永远不会有人来跑 B.viewTick ⇒ 客户端口没填上时气泡永远空着。
    B.pumpSync()
    B.viewWhy = "总览气泡当场读回 0 行 ⇒ 延后 " .. strVal(B.TIP_WAIT)
      .. "s 复核（绝不当场覆盖客户端的内容）"
  end
  if type(tip.Show) == "function" then pcall(tip.Show, tip) end
end

-- 总览气泡的延后复核（由唯一节拍帧 B.pump 调；与格子气泡同一个 TIP_WAIT 口径）：
--   读到内容 ⇒ 认客户端的口、一个字都不动；到点仍 0 行 ⇒ 才写自建文本兜底。
function B.viewTick()
  local p = B.viewPend
  if p == nil then return end
  if GetTime() - p.t < B.TIP_WAIT then return end
  B.viewPend = nil
  local tip = _G.GameTooltip
  if tip == nil then return end
  -- ★0.3.10：到点**先重问一次客户端口**（延迟可能超过 TIP_WAIT），再决定 —— 顺序即判据。
  local rec0 = p.rec
  if isObj(p.owner) and viewRichTry(tip, rec0) == true then
    B.viewTipRich = true
    B.viewWhy = "客户端口是延迟填上的（第 2 拍才读回）⇒ 一个字都没动"
    if type(tip.Show) == "function" then pcall(tip.Show, tip) end
    return
  end
  local has, judged = B.tipRead(tip)
  if judged == true and has == true then
    B.viewTipRich = true
    B.viewWhy = "客户端口的行是延迟填上的：延后复核读到内容 ⇒ 一个字都没动"
    return
  end
  local rec = p.rec
  local showed = false
  if type(tip.ClearLines) == "function" then pcall(tip.ClearLines, tip) end
  if isObj(p.owner) then pcall(tip.SetOwner, tip, p.owner, "ANCHOR_RIGHT") end
  B.viewTipRich = false
  if type(rec) ~= "table" then
    if type(tip.SetText) == "function" then pcall(tip.SetText, tip, L("EMPTY"), 0.7, 0.7, 0.7) end
  elseif type(rec.rl) == "table" and table.getn(rec.rl) > 0 then
    -- ★★★0.3.24：快照里存了**这件物品的行**（只在链接彻底拿不到时才存，见 B.richTry ④）⇒ 逐行画出来。
    --   行是客户端自己画过的那份文本（带色码）⇒ 名字的品质色 / 属性分色照旧；第一行 SetText、其余 AddLine。
    local rl = rec.rl
    local i3
    for i3 = 1, table.getn(rl) do
      if i3 == 1 then
        if type(tip.SetText) == "function" then
          pcall(tip.SetText, tip, strVal(rl[i3]))
          showed = true
        end
      elseif type(tip.AddLine) == "function" then
        pcall(tip.AddLine, tip, strVal(rl[i3]))
      end
    end
    if type(tip.AddLine) == "function" then pcall(tip.AddLine, tip, L("VIEW_RO"), 0.62, 0.62, 0.62) end
  else
    -- 名字按品质上色（与格子里的图标/边框同一份色源）
    local qr, qg, qb = qualRGB(rec.q)
    if type(tip.SetText) == "function" then
      pcall(tip.SetText, tip, strVal(rec.n or "?"), qr, qg, qb)
      showed = true
    end
    if (rec.c or 1) > 1 and type(tip.AddLine) == "function" then
      pcall(tip.AddLine, tip, "×" .. strVal(rec.c), 0.9, 0.9, 0.9)
    end
    if type(tip.AddLine) == "function" then
      pcall(tip.AddLine, tip, L("VIEW_RO"), 0.62, 0.62, 0.62)
    end
  end
  if showed ~= true then
    B.viewWhy = "延后复核仍是 0 行，且连标题都写不进去（SetText 不可用）"
  elseif type(rec) == "table" and type(rec.rl) == "table" and table.getn(rec.rl) > 0 then
    B.viewWhy = "延后复核仍是 0 行 ⇒ 用**快照存下来的行**画（这一件的链接拿不到）"
  else
    B.viewWhy = "延后复核仍是 0 行 ⇒ 自建文本兜底（名字/品质色/数量/只读）"
  end
  if type(tip.Show) == "function" then pcall(tip.Show, tip) end
end

local function viewPaint(b, rec)
  b.ehRec = rec
  local tex = rec.t
  if isObj(b.ehIcon) then
    if type(tex) == "string" and tex ~= "" then
      pcall(b.ehIcon.SetTexture, b.ehIcon, tex)
    else
      pcall(b.ehIcon.SetTexture, b.ehIcon, B.res("INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark"))
    end
    pcall(b.ehIcon.Show, b.ehIcon)
  end
  if isObj(b.ehSlot) then
    if B.cfg().edges ~= false then
      -- ★0.3.13：总览格框与背包格框**同一份颜色**（提纯 + 拉满亮度后的品质色）
      local vr, vg, vb = B.vividRGB(qualRGB(rec.q))
      pcall(b.ehSlot.SetVertexColor, b.ehSlot, vr, vg, vb, 1)
    else
      -- ★0.3.15：关掉「格框染品质」⇒ **白框**（旧写法写 0.30 灰 —— 那不是「白框」这把尺子）
      --   ★0.3.16：亮度走唯一来源 `B.SLOT_DIM`（与背包格同一把尺子）
      pcall(b.ehSlot.SetVertexColor, b.ehSlot, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, 1)
    end
  end
  if isObj(b.ehCount) then
    if (rec.c or 1) > 1 then
      pcall(b.ehCount.SetText, b.ehCount, strVal(rec.c))
    else
      pcall(b.ehCount.SetText, b.ehCount, "")
    end
  end
end

-- 按钮池（池有界、跨次复用 —— 每次重建 = 白造几百个帧）
-- ★0.3.12：几何一律交给 B.viewFit（幂等、四处同源）⇒ 换档位 / 改缩放后**复用池里的旧格子也会跟上**
local function viewBtnAt(n)
  if type(B.ui.viewButtons) ~= "table" then B.ui.viewButtons = {} end
  local pool = B.ui.viewButtons
  local b = pool[n]
  if b ~= nil then
    B.viewFit(b)
    return b
  end
  if n > B.VITEM_MAX then return nil end
  local f = B.ui.viewFrame
  if f == nil or isObj(f.ehViewContent) == false then return nil end
  b = CreateFrame("Button", nil, f.ehViewContent)
  if type(b.EnableMouse) == "function" then pcall(b.EnableMouse, b, true) end
  if type(b.RegisterForClicks) == "function" then pcall(b.RegisterForClicks, b, "LeftButtonUp") end
  -- ★0.3.16：总览格底也走**圆角实心底**（与背包格同一把尺子；当前透明，几何由 B.viewFit 统一设）
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(fill.SetTexture, fill, B.SLOT_FILL)
  pcall(fill.SetVertexColor, fill, 0.05, 0.05, 0.05, 0)
  b.ehFill = fill
  -- ★0.3.9：框画在图标**之上**（与背包格子同一口径 —— 框压边 ⇒ 两者大小匹配）
  --   ★0.3.15：美术换成自带白框（`B.SLOT_TEX`，与背包格/背包条同一张）
  local art = b:CreateTexture(nil, "ARTWORK")
  art:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(art.SetTexture, art, B.SLOT_TEX)
  pcall(art.SetVertexColor, art, 1, 1, 1, 1)
  b.ehSlot = art
  local icon = b:CreateTexture(nil, "BORDER")
  icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)
  b.ehIcon = icon
  local cnt = font(b)
  cnt:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
  pcall(cnt.SetJustifyH, cnt, "RIGHT")
  pcall(cnt.SetTextColor, cnt, 1, 1, 1)
  b.ehCount = cnt
  b:SetScript("OnEnter", function() viewTip(b, b.ehRec) end)
  b:SetScript("OnLeave", function()
    -- ★鼠标走了 ⇒ 延后复核作废（绝不在鼠标离开之后再回头去改那口气泡）——与格子气泡同一条纪律
    B.viewPend = nil
    local tip = _G.GameTooltip
    if tip ~= nil and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
  end)
  b:SetScript("OnClick", function()
    local rec = b.ehRec
    if type(rec) ~= "table" then return end
    local link = rec.l
    if type(link) ~= "string" or link == "" then return end
    linkItem(link)
    -- 客户端没有插入口时至少把链接打出来（可点、可看），绝不静默
    if type(ChatEdit_InsertLink) ~= "function" then sayForce(link) end
  end)
  b.ehCell = nil          -- 建出来先算一次几何（viewFit 只在边长真变了才发 Set*）
  B.viewFit(b)
  pool[n] = b
  return b
end

-- ★★★0.3.12：**分背包标题整条去掉**（用户：「跨角色总览的物品聚合一下.不需要分背包展示」）
--   ⇒ 一个连续网格：背包 0~4 → 钥匙链 → 银行（顺序不变、只是不再插标题、不再按包另起一行），
--     同屏能放的物品数由「格子档位 + 列数现算」决定（小档 12 列 × 13 行）。
--   ★同名物品**不合并**成一格（每条各自的链接/悬停才是它能点的原因）；要合并再说一句。
--   （删除的是 `viewHeadAt` 那个标题池与 `B.VHEAD_MAX`/`B.viewHeadNeed` —— 不留死代码）

-- ★★★0.3.17：**段标题池**（两段：背包 / 银行）—— 与格子池同一套纪律：**建一次复用**、**有界**（`B.VHEAD_MAX`）；
--   1.12 没有销毁帧的 API ⇒ 池是唯一做法；超上限**如实不画**（绝不无限建帧）。
--   ★标题是 FontString ⇒ 不吃鼠标（纯显示，不需要热区）。
local function viewHeadAt(n)
  if type(B.ui.viewHeads) ~= "table" then B.ui.viewHeads = {} end
  local pool = B.ui.viewHeads
  local t = pool[n]
  if t ~= nil then return t end
  if n > B.VHEAD_MAX then return nil end
  local f = B.ui.viewFrame
  if f == nil or isObj(f.ehViewContent) == false then return nil end
  t = font(f.ehViewContent)
  pcall(t.SetJustifyH, t, "LEFT")
  pcall(t.SetTextColor, t, 0.72, 0.68, 0.55)
  pool[n] = t
  return t
end

-- 状态行（每拍现算；与几何重建分开 —— 让它便宜到可以每拍跑）
-- ★0.3.17：`shown` = 窗内**真画得下**的格数（viewFill 现算）—— 小于物品数就把差额如实写进容量行，
--   绝不静默截断（「放不下」也是一种事实，用户要看得见）。返回值 = used/total/items（给调用方复用，别各算一遍）。
function B.viewStat(e, shown)
  local f = B.ui.viewFrame
  if f == nil then return end
  local r = e.r
  local used, total, items = 0, 0, 0
  local function acc(m, list)
    if type(m) == "table" then
      if type(m.u) == "number" then used = used + m.u end
      if type(m.n) == "number" then total = total + m.n end
    end
    if type(list) == "table" then items = items + table.getn(list) end
  end
  local i
  for i = 1, table.getn(B.BAGS) do
    local bag = B.BAGS[i]
    local m = (type(r.itM) == "table") and r.itM[bag] or nil
    local l = (type(r.it) == "table") and r.it[bag] or nil
    acc(m, l)
  end
  acc(r.ktM, r.kt)
  if type(r.bkM) == "table" then
    local bag
    for bag in pairs(r.bkM) do
      local l = (type(r.bk) == "table") and r.bk[bag] or nil
      acc(r.bkM[bag], l)
    end
  end
  if isObj(f.vCap) then
    local txt = L("VIEW_CAP_FMT", used, total, items)
    if type(shown) == "number" and shown < items then txt = txt .. L("VIEW_MORE_FMT", shown, items) end
    pcall(f.vCap.SetText, f.vCap, txt)
  end
  if isObj(f.vMoney) then
    local ms = ""
    if type(r.money) == "number" then ms = moneyStr(r.money) end
    pcall(f.vMoney.SetText, f.vMoney, ms)
  end
  return used, total, items
end

function B.viewFill(force)
  local f = B.ui.viewFrame
  if f == nil then return end
  -- ★0.3.12：几何先现算（档位/缩放都只乘在 viewMetrics 里），列数与格子边长同一来源
  B.viewMetrics()
  local chars = B.viewChars()
  B.viewList = chars
  local n = table.getn(chars)
  local i
  -- 每次先全收（显式控件清单，绝不靠父子传播）
  if type(B.ui.viewButtons) == "table" then
    local p1 = B.ui.viewButtons
    for i = 1, table.getn(p1) do pcall(p1[i].Hide, p1[i]) end
  end
  -- ★段标题一起收（显式控件清单：显隐绝不靠父子传播）
  if type(B.ui.viewHeads) == "table" then
    local p2 = B.ui.viewHeads
    for i = 1, table.getn(p2) do pcall(p2[i].Hide, p2[i]) end
  end
  B.viewNeed = 0
  if n == 0 then
    if isObj(f.vChar) then pcall(f.vChar.SetText, f.vChar, L("VIEW_TITLE")) end
    if isObj(f.vCap) then pcall(f.vCap.SetText, f.vCap, L("VIEW_NONE")) end
    if isObj(f.vMoney) then pcall(f.vMoney.SetText, f.vMoney, "") end
    B.viewSig = "empty"
    return
  end
  if type(B.viewIdx) ~= "number" or B.viewIdx < 1 then B.viewIdx = 1 end
  if B.viewIdx > n then B.viewIdx = n end
  local e = chars[B.viewIdx]
  local r = e.r
  if isObj(f.vChar) then pcall(f.vChar.SetText, f.vChar, viewCharLine(e)) end
  B.viewStat(e)
  -- ★★★0.3.17：**分两段**（背包段 / 银行段，各带一行小标题）—— 用户：「跨角色总览里，背包和银行的物品要分离开显示」
  --   ★段内仍是一个**连续网格**（不按包另起一行 —— 0.3.12 那条纪律不变）；两段之间插一行小标题。
  --   ★「背包段」= 背包 0~4 + **钥匙链**（随身物，跟背包同一段）；「银行段」= 银行主格 + 银行包。
  --   ★空段不出标题、不占位；标题**独占一行**（必须从行首开始）⇒ 行预算把它算进去。
  local bagList, bankList = {}, {}
  do
    local i2
    for i2 = 1, table.getn(B.BAGS) do
      local bag = B.BAGS[i2]
      local m = (type(r.itM) == "table") and r.itM[bag] or nil
      if type(m) == "table" and (m.n or 0) > 0 then
        local list = (type(r.it) == "table") and r.it[bag] or nil
        if type(list) == "table" then
          local j2
          for j2 = 1, table.getn(list) do table.insert(bagList, list[j2]) end
        end
      end
    end
    if type(r.ktM) == "table" and (r.ktM.n or 0) > 0 and type(r.kt) == "table" then
      local j2
      for j2 = 1, table.getn(r.kt) do table.insert(bagList, r.kt[j2]) end
    end
    if type(r.bkM) == "table" then
      local order = { B.BANK }
      local j2
      for j2 = 1, table.getn(B.BANKBAGS) do table.insert(order, B.BANKBAGS[j2]) end
      for j2 = 1, table.getn(order) do
        local bag = order[j2]
        local m = r.bkM[bag]
        if type(m) == "table" and (m.n or 0) > 0 then
          local list = (type(r.bk) == "table") and r.bk[bag] or nil
          if type(list) == "table" then
            local k2
            for k2 = 1, table.getn(list) do table.insert(bankList, list[k2]) end
          end
        end
      end
    end
  end
  local bagN, bankN = table.getn(bagList), table.getn(bankList)
  -- ★行预算：内容区高（与 buildView 同一份常量）÷ 行距 ⇒ 放得下几行；标题行按「非空段数」扣
  local zV = B.z()
  local pitch = B.VCELL + B.VGAP
  local rowsMax = 1
  if pitch > 0.01 then
    rowsMax = math.floor(((B.VWIN_H - B.VTOP_GAP - B.VBOT_GAP) * zV + B.VGAP) / pitch)
  end
  if rowsMax < 1 then rowsMax = 1 end
  local headRows = 0
  if bagN > 0 then headRows = headRows + 1 end
  if bankN > 0 then headRows = headRows + 1 end
  local capCells = (rowsMax - headRows) * B.VCOLS
  if capCells < 0 then capCells = 0 end
  local shown = bagN + bankN
  if shown > capCells then shown = capCells end
  if shown > B.VITEM_MAX then shown = B.VITEM_MAX end
  B.viewFits = shown
  B.viewStat(e, shown)
  -- ★格子边长与列数进签名：换档位 / 改缩放 / 改窗口宽 ⇒ 必须重排（否则旧格子留在旧位置）
  --   ★段边界（bagN）、标题行数（headRows）与「真正画几格」（shown）也要进签名：
  --     物品在两个容器之间挪动时总数可能一字不变，只有段边界变 —— 不签名就会拿旧排布（标题位置/断点全错）。
  local sig = strVal(e.k) .. "@" .. strVal(r.t) .. "#" .. strVal(B.viewIdx) .. "/" .. strVal(n)
    .. "|c" .. strVal(math.floor(B.VCELL * 100 + 0.5)) .. "x" .. strVal(B.VCOLS)
    .. "|b" .. strVal(bagN) .. "|h" .. strVal(headRows) .. "|m" .. strVal(shown)
  -- ★同一角色同一份快照 ⇒ 几何一分钱都不重摆（refreshAll 会以 ≤4/s 的节奏喊它）
  if force ~= true and B.viewSig == sig then return end
  B.viewSig = sig
  local cx, cy, col, row = 0, 0, 0, 0
  local drawn, headN = 0, 0
  local function newRow()
    cx = 0
    col = 0
    cy = cy - pitch
    row = row + 1
  end
  -- ★段标题：独占一行、必须从行首开始；池里的句柄按段序取（pool 有界，取不到就如实不画）
  local function putHead(txt)
    if row >= rowsMax then return end
    if col > 0 then newRow() end
    headN = headN + 1
    local h = viewHeadAt(headN)
    if h ~= nil then
      pcall(h.ClearAllPoints, h)
      pcall(h.SetPoint, h, "TOPLEFT", f.ehViewContent, "TOPLEFT", 0, cy)
      pcall(h.SetWidth, h, B.VCOLS * pitch - B.VGAP)
      pcall(h.SetText, h, txt)
      pcall(h.Show, h)
    end
    newRow()
  end
  local function put(rec)
    if drawn >= shown then return end
    if row >= rowsMax then return end
    B.viewNeed = B.viewNeed + 1
    local b = viewBtnAt(B.viewNeed)
    if b == nil then return end
    pcall(b.ClearAllPoints, b)
    pcall(b.SetPoint, b, "TOPLEFT", f.ehViewContent, "TOPLEFT", cx, cy)
    viewPaint(b, rec)
    pcall(b.Show, b)
    drawn = drawn + 1
    col = col + 1
    if col >= B.VCOLS then newRow() else cx = cx + pitch end
  end
  if bagN > 0 then
    putHead(L("VIEW_SEC_BAG"))
    local j3
    for j3 = 1, bagN do put(bagList[j3]) end
  end
  if bankN > 0 then
    putHead(L("VIEW_SEC_BANK"))
    local j3
    for j3 = 1, bankN do put(bankList[j3]) end
  end
  B.viewDrawn = drawn
end

function B.buildView()
  if B.ui.viewFrame ~= nil then return true end
  if type(CreateFrame) ~= "function" then return false end
  if B.build() == false then return false end
  -- ★界面缩放 + 格子档位：总览格子/间距/列数都走唯一几何口 B.viewMetrics()（读口仍是 B.VCELL/B.VGAP/B.VCOLS）
  B.viewMetrics()
  local zV = B.z()
  -- ★0.3.15：与主窗同一把尺子 —— 左右内边距 10zV → 14zV、高 +6zV（底行文字抬到 14zV，
  --   内容区下缘跟着让到 32zV；只挪文字不放高 = 文字压在格子上）
  local W, H = ((B.VCONTENT_W or 310) + 28) * zV, (B.VWIN_H or 436) * zV
  local f = CreateFrame("Frame", "EH_BagViewFrame", UIParent)
  f:SetWidth(W)
  f:SetHeight(H)
  if type(f.SetClampedToScreen) == "function" then pcall(f.SetClampedToScreen, f, true) end
  -- ★不设 SetMovable（同主窗：拖拽走已验证三件套）
  if type(f.EnableMouse) == "function" then pcall(f.EnableMouse, f, true) end
  local okBD = pcall(f.SetBackdrop, f, {
    bgFile = B.res("ChatFrameBackground", "Interface\\ChatFrame\\ChatFrameBackground"),
    edgeFile = B.res("UI-Tooltip-Border", "Interface\\Tooltips\\UI-Tooltip-Border"),
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
  })
  if okBD then
    -- ★0.3.17：总览窗背板 alpha **与主窗同一来源**（`B.bgK()`）—— 旧写法写死 0.92，成了「主窗能调、总览不能调」，
    --   而这一个数在两处出现就是下一个漏改点（`B.bgApply` 也是靠句柄改到它）。
    pcall(f.SetBackdropColor, f, 0.03, 0.03, 0.03, B.bgK())
    pcall(f.SetBackdropBorderColor, f, 0.55, 0.45, 0.18, 1)
  else
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    solid(bg, 0.03, 0.03, 0.03, B.bgK())
    -- ★这条退路也要交出句柄：`B.bgApply()` 得能改到它（两条建成路各自兑现，绝不只做 SetBackdrop 那一条）
    f.ehVBg = bg
  end
  if type(f.SetFrameStrata) == "function" then pcall(f.SetFrameStrata, f, "DIALOG") end
  if type(f.SetFrameLevel) == "function" then pcall(f.SetFrameLevel, f, 82) end
  -- ★位置记忆 c.vpoint 接上读写口（旧写法只写不读 = 又一个死键）：拖过总览就以存档为准，
  --   没拖过才贴主窗右侧；离谱值一律回默认（每个记忆位置的窗口都要越界回归 —— 项目铁律）
  local host = B.ui.frame
  local vp = B.cfg().vpoint
  local vUse = false
  local vpa, vpb, vpx, vpy = "TOPLEFT", "TOPRIGHT", 4, 0
  if type(vp) == "table" and type(vp.x) == "number" and type(vp.y) == "number"
    and math.abs(vp.x) <= 4000 and math.abs(vp.y) <= 4000 then
    vUse = true
    if type(vp.a) == "string" then vpa = vp.a end
    if type(vp.b) == "string" then vpb = vp.b end
    vpx, vpy = vp.x, vp.y
  end
  if vUse and isObj(host) then
    pcall(f.SetPoint, f, vpa, host, vpb, vpx, vpy)
  elseif isObj(host) then
    pcall(f.SetPoint, f, "TOPLEFT", host, "TOPRIGHT", 4, 0)
  else
    pcall(f.SetPoint, f, "CENTER", UIParent, "CENTER", 0, 0)
  end
  local drag = CreateFrame("Button", "EH_BagViewDrag", f)
  drag:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -8)
  drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -74, -8)
  drag:SetHeight(22)
  if type(drag.EnableMouse) == "function" then pcall(drag.EnableMouse, drag, true) end
  if type(drag.RegisterForClicks) == "function" then pcall(drag.RegisterForClicks, drag, "LeftButtonUp") end
  if type(drag.RegisterForDrag) == "function" then pcall(drag.RegisterForDrag, drag, "LeftButton") end
  -- ★与主窗同一套三件套（共用全屏接盘与幂等收尾口；落点写 c.vpoint）
  drag:SetScript("OnMouseDown", function(button)
    if type(button) ~= "string" then button = arg1 end
    if button == "LeftButton" then B.dragStart(f, "vpoint") end
  end)
  drag:SetScript("OnDragStart", function() B.dragStart(f, "vpoint") end)
  drag:SetScript("OnDragStop", function() B.dragStop("dragstop") end)
  drag:SetScript("OnMouseUp", function() B.dragStop("mouseup") end)
  local title = font(f)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
  pcall(title.SetTextColor, title, 0.95, 0.82, 0.35)
  title:SetText(L("VIEW_TITLE"))
  f.vTitle = title
  local prev = mkBtn(f, 18, 18, "<", function() B.viewStep(-1) end)
  prev:SetPoint("TOPRIGHT", f, "TOPRIGHT", -56, -9)
  f.vPrev = prev
  local nextB = mkBtn(f, 18, 18, ">", function() B.viewStep(1) end)
  nextB:SetPoint("TOPRIGHT", f, "TOPRIGHT", -34, -9)
  f.vNext = nextB
  local close = mkBtn(f, 18, 18, "X", function() B.viewClose() end)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -9)
  f.vClose = close
  local ch = font(f)
  ch:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
  pcall(ch.SetWidth, ch, W - 28 * zV)
  pcall(ch.SetJustifyH, ch, "LEFT")
  pcall(ch.SetTextColor, ch, 1, 1, 1)
  ch:SetText("")
  f.vChar = ch
  local cap = font(f)
  cap:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -50)
  pcall(cap.SetWidth, cap, W - 28 * zV)
  pcall(cap.SetJustifyH, cap, "LEFT")
  pcall(cap.SetTextColor, cap, 0.80, 0.80, 0.80)
  cap:SetText("")
  f.vCap = cap
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", f, "TOPLEFT", 14 * zV, -(B.VTOP_GAP or 72) * zV)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14 * zV, (B.VBOT_GAP or 32) * zV)
  if type(content.EnableMouse) == "function" then pcall(content.EnableMouse, content, false) end
  f.ehViewContent = content
  local money = font(f)
  money:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
  pcall(money.SetJustifyH, money, "LEFT")
  pcall(money.SetTextColor, money, 1, 0.85, 0.30)
  money:SetText("")
  f.vMoney = money
  local hint = font(f)
  hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
  pcall(hint.SetJustifyH, hint, "RIGHT")
  pcall(hint.SetTextColor, hint, 0.62, 0.62, 0.62)
  hint:SetText(L("VIEW_HINT"))
  f.vHint = hint
  B.ui.viewFrame = f
  pcall(f.Hide, f)
  return true
end

function B.viewClose()
  B.viewShown = false
  -- ★关窗 ⇒ 气泡的延后复核一起作废（绝不在窗收起来之后还去改那口气泡）
  B.viewPend = nil
  if type(B.dragStopIf) == "function" then B.dragStopIf(B.ui.viewFrame) end
  if isObj(B.ui.viewFrame) then pcall(B.ui.viewFrame.Hide, B.ui.viewFrame) end
end

function B.viewOpen()
  if B.buildView() == false then return false end
  local f = B.ui.viewFrame
  B.viewShown = true
  B.viewIdx = nil
  B.viewSig = nil
  -- 先记一份自己的最新快照，再画（顺序即判据：不然总览里自己那份是旧的）
  -- ★这里用 force：开总览是玩家主动动作，跳过「20s 最小间隔」才不会看到自己的旧数据
  B.snapshot("force")
  pcall(f.Show, f)
  B.viewFill(true)
  B.traceAdd("view", "open")
  return true
end

function B.viewToggle()
  if B.viewShown == true then
    B.viewClose()
  else
    B.viewOpen()
  end
end

function B.viewStep(d)
  local n = table.getn(B.viewList or {})
  if n == 0 then return end
  if type(B.viewIdx) ~= "number" then B.viewIdx = 1 end
  B.viewIdx = B.viewIdx + d
  if B.viewIdx < 1 then B.viewIdx = n end
  if B.viewIdx > n then B.viewIdx = 1 end
  B.viewFill(true)
end

-- 数据变了才重画；关掉接管/让位时当场收回（关断四件事里的资源回收）
function B.viewSync()
  if B.viewShown ~= true then return end
  if B.active() == false then
    B.viewClose()
    return
  end
  B.viewFill(false)
end

-- 存档里各角色一览（/ebag chars）
function B.charsDump()
  local chars = B.viewChars()
  local n = table.getn(chars)
  if n == 0 then
    sayForce(L("VIEW_NONE"))
    return
  end
  sayForce(L("CHARS_HEAD", n))
  local i
  for i = 1, n do
    local e = chars[i]
    local r = e.r
    local items = 0
    local bag, list
    if type(r.it) == "table" then
      for bag, list in pairs(r.it) do items = items + table.getn(list) end
    end
    if type(r.kt) == "table" then items = items + table.getn(r.kt) end
    if type(r.bk) == "table" then
      for bag, list in pairs(r.bk) do items = items + table.getn(list) end
    end
    sayForce(L("CHARS_LINE", strVal(r.n or e.k), items, strVal(r.lv or "?")))
  end
end

-- ===== 布局（几何重建，唯一入口）=====
function B.layout()
  local f = B.ui.frame
  if f == nil then return end
  local c = B.cfg()
  local z = B.z()
  local cell = (c.cell or DEF.cell) * z
  local gap = B.cgap() * z   -- ★0.3.31g：唯一读口（夹取 + 坏数据退默认；存档键 c.gap 接上写口了）
  -- ★背包条/银行包条的**排距尺子**与格框无关（`B.BARCELL`）：旧写法拿格框的 `cell + 4`
  --   去排左侧条 ⇒ 左条 41 一格、右条 34 一格（两条不等高，左侧看着「又大又散」）
  local barCell = (B.BARCELL or 30) * z
  local cols = c.cols or DEF.cols
  if cols < 4 then cols = 4 end
  if cols > 20 then cols = 20 end
  local x, y = 0, 0
  local col = 0
  local maxRow = 0
  local maxBottom = 0
  -- ★连续排布 = 参考的默认档（bagBreak = false）：包与包之间**不断行**、不留尾部空格
  --   （1.75.76b 真机报障「背包内容是错乱的」的真因：我们原来硬编码「每包另起一行」，
  --    每个包尾都留一串空格子 ⇒ 半空的包看起来稀稀拉拉）
  local bagBreak = (c.bagBreak == true)
  -- ★底部对齐 = 参考的 vAlign=Bottom：先数总格数，把第一行往右推，使**最后一行贴底**
  if c.vAlign == "bottom" then
    local totalN = 0
    local l0 = B.containers()
    local n0 = table.getn(l0)
    local j
    for j = 1, n0 do
      local b0 = l0[j]
      if c.direction == "rev" then b0 = l0[n0 + 1 - j] end
      local nn = B.bagSlots(b0)
      if nn > 0 then
        if bagBreak and totalN > 0 and math.fmod(totalN, cols) > 0 then
          totalN = totalN + (cols - math.fmod(totalN, cols))
        end
        totalN = totalN + nn
      end
    end
    local rem = math.fmod(totalN, cols)
    if totalN > 0 and rem > 0 then
      col = cols - rem
      x = col * (cell + gap)
    end
  end
  -- ★分区标题默认收起（银行关掉时不许留在屏上）
  if isObj(f.ehBankLabel) then pcall(f.ehBankLabel.Hide, f.ehBankLabel) end
  local list = B.containers()
  -- ★背包顺序（参考的 show.direction）：'rev' = 从最后一个包开始排。
  --   ★只影响「怎么摆格子」—— 容器表 / 背包条 / 跨角色快照一律不动（那些是「容器是什么」）。
  local rev = (c.direction == "rev")
  local nList = table.getn(list)
  local i
  for i = 1, nList do
    local bag = list[i]
    if rev then bag = list[nList + 1 - i] end
    local n = B.bagSlots(bag)
    local isBank = B.isBankContainer(bag)
    -- 进银行区先摆一个分区标题
    if isBank and B.ui.bankLabeled ~= true then
      B.ui.bankLabeled = true
      if col ~= 0 then
        col = 0
        x = 0
        y = y - (cell + gap)
      end
      local lb = f.ehBankLabel
      if isObj(lb) then
        pcall(lb.ClearAllPoints, lb)
        pcall(lb.SetPoint, lb, "TOPLEFT", f.ehContent, "TOPLEFT", 0, y - 2)
        pcall(lb.Show, lb)
      end
      y = y - 18
    end
    local s
    for s = 1, n do
      local btn = B.ui.buttons[bag] and B.ui.buttons[bag][s]
      if btn ~= nil then
        if col >= cols then
          col = 0
          x = 0
          y = y - (cell + gap)
        end
        if type(btn.ClearAllPoints) == "function" then pcall(btn.ClearAllPoints, btn) end
        btn:SetPoint("TOPLEFT", f.ehContent, "TOPLEFT", x, y)
        btn:SetWidth(cell)
        btn:SetHeight(cell)
        if isObj(btn.ehSlot) then
          local art = B.SLOT_K
          pcall(btn.ehSlot.SetWidth, btn.ehSlot, cell * art)
          pcall(btn.ehSlot.SetHeight, btn.ehSlot, cell * art)
        end
        -- ★0.3.16：底色与框**同尺寸同锚点**（改格子边长就一起改；只在真变了才发 Set*）
        -- ★★★0.3.20：**辉光层一起重设**（它也是「格子 × B.SLOT_K」的三层之一）——
        --   旧写法只重设 slot/fill/icon ⇒ 辉光一直停在**建仓时那份还没缩放的尺寸**上
        --   （默认 80% 缩放档下比格框大 1/0.8 = **25%**）⇒ 用户看到的
        --   「稀有度染色（旧写法染硬框）与悬停辉光不是同一个边框尺寸」的真因就是它。
        if btn.ehFillK ~= cell then
          btn.ehFillK = cell
          if isObj(btn.ehFill) then
            pcall(btn.ehFill.SetWidth, btn.ehFill, cell * B.SLOT_K)
            pcall(btn.ehFill.SetHeight, btn.ehFill, cell * B.SLOT_K)
          end
          if isObj(btn.ehGlow) then
            pcall(btn.ehGlow.SetWidth, btn.ehGlow, cell * B.SLOT_K)
            pcall(btn.ehGlow.SetHeight, btn.ehGlow, cell * B.SLOT_K)
          end
        end
        -- ★图标：居中 + cell × B.ICON_K（只在格子边长变了才重摆 —— 别每拍发 4 个 Set*）
        if isObj(btn.ehIcon) and btn.ehIconK ~= cell then
          btn.ehIconK = cell
          pcall(btn.ehIcon.ClearAllPoints, btn.ehIcon)
          pcall(btn.ehIcon.SetPoint, btn.ehIcon, "CENTER", btn, "CENTER", 0, 0)
          pcall(btn.ehIcon.SetWidth, btn.ehIcon, cell * B.ICON_K)
          pcall(btn.ehIcon.SetHeight, btn.ehIcon, cell * B.ICON_K)
          pcall(btn.ehIcon.SetTexCoord, btn.ehIcon, 0.08, 0.92, 0.08, 0.92)
        end
        if type(btn.Show) == "function" then pcall(btn.Show, btn) end
        x = x + cell + gap
        col = col + 1
        if col > maxRow then maxRow = col end
        local btm = -y + cell
        if btm > maxBottom then maxBottom = btm end
      end
    end
    -- ★只有「背包断行」开着才在包与包之间换行（默认连续排布）
    if bagBreak and n > 0 and col > 0 then
      col = 0
      x = 0
      y = y - (cell + gap)
    end
  end
  B.ui.bankLabeled = false
  -- ★★行数与网格高一律按「最后一格真正的下缘」算：旧写法 floor(-y/(cell+gap)) 在**末行没填满**时
  --   会少算一行 ⇒ 窗口矮一行、末行溢出到窗框外（压在背包条上）—— 「看着错乱」的第二个成因。
  if maxBottom <= 0 then maxBottom = 0 end
  B.ui.rows = math.max(1, math.ceil(maxBottom / (cell + gap)))
  local gridW = cols * (cell + gap)
  local gridH = maxBottom + gap
  -- ★0.3.15：左右内边距 12z → 16z（内容区左缘/右缘、标题、底行文字全按 16z 对齐）
  local W = gridW + 32 * z
  if W < 320 * z then W = 320 * z end
  f:SetWidth(W)
  -- ★★★窗口宽一变，顶栏就可能重新分排（搜索框掉第二排）⇒ 内容区顶与窗口高必须**跟着一起改**：
  --   先落宽、再让 B.ctrlApply() 按新宽重排并把「顶栏占多高」报回来。
  --   （只改一边 = 第一行格子被顶栏压住 —— 这个坑本项目踩过一次）
  local topOff = B.ctrlApply()
  -- ★0.3.15：底部内边距 26z → 32z（底行文字抬到 14z，格子下缘必须让开 —— 否则文字压在格子上）
  local H = gridH + topOff + 32 * z + 2 * z
  if H < 200 * z then H = 200 * z end
  f:SetHeight(H)
  -- 玩家背包条
  local bar = f.ehBar
  if isObj(bar) then
    local n2 = 0
    local k
    for k = 1, table.getn(B.BAGS) do
      local bag = B.BAGS[k]
      local b = B.ui.bags[bag]
      if isObj(b) then
        if bagShown(bag) then
          pcall(b.Show, b)
          pcall(b.ClearAllPoints, b)
          b:SetPoint("TOP", bar, "TOP", 0, -5 * z - n2 * (barCell + 4 * z))
          n2 = n2 + 1
        else
          pcall(b.Hide, b)
        end
      end
    end
    if isObj(B.ui.keyringBtn) then
      local kb = B.ui.keyringBtn
      -- ★★「钥匙链：关」= 左侧钥匙按钮**一起隐藏**（0.3.7；用户：「设置->钥匙链关状态,需要背包左侧的
      --   钥匙的图标隐藏.背包对应的格子也隐藏」）。旧写法只把图标**变暗** ⇒ 关掉了按钮还杵在那儿；
      --   格子那一半本来就对（B.bagSlots(KEYRING) 关掉时返回 0 ⇒ 既不进容器表、也被世代号扫尾收起）。
      --   ★可见性只有这一处（refreshBar 只画图标/染色，绝不碰显隐 —— 免得两处口径打架）。
      if keyringSize() > 0 and bagShown(B.KEYRING) then
        pcall(kb.Show, kb)
        pcall(kb.ClearAllPoints, kb)
        kb:SetPoint("TOP", bar, "TOP", 0, -5 * z - n2 * (barCell + 4 * z))
        n2 = n2 + 1
      else
        pcall(kb.Hide, kb)
      end
    end
    bar:SetHeight(math.max(1, n2) * (barCell + 4 * z) + 10 * z)
  end
  -- 银行包条
  local bbar = f.ehBankBar
  if isObj(bbar) then
    if B.bankOpen == true then
      pcall(bbar.Show, bbar)
    else
      pcall(bbar.Hide, bbar)
    end
  end
  -- ★陈旧格子清理**不在这里**：它按「本拍 B.refreshBag 有没有盖过章」判（唯一实现 = B.refreshAll 末尾）——
  --   摆在 layout 里会拿不到世代号（layout 与 refreshBag 的调用次序不保证），也会变成两处各判一次。
  B.ui.needLayout = false
end

-- ===== 搜索框边框（三片切）的唯一几何口 =====
--   ★★★0.3.23：为什么必须切开画（用户截图：「搜索输入框还有点问题」= 两端两根粗竖条）——
--   把整张 64×64 白框**铺满**长条时，竖直的两条线按**横向**比例放大、水平的上下两条线按**纵向**压扁
--   ⇒ 边框四周粗细差好几倍。切开后每片都是**等比**的（片高 = 框高、源 v 13..52 = 画框那一带 39px）
--   ⇒ 线宽 = 框高 × 3/39，与格子（格宽 × 3/39）**同一个比例**，四周一致。
--   ★w / h = **已乘 z** 的框宽/框高（由唯一几何口 `B.ctrlApply` 传入）；坏数据 ⇒ 一个字节都不写。
--   ★框太短（中段算出来 ≤ 0）⇒ 中段**收起**（宁可不画，也不让两片叠出双线）。
function B.sboxEdgeFit(w, h)
  local f = B.ui.frame
  if isObj(f) == false or isObj(f.ehSbox) == false then return false end
  local ww, hh = tonumber(w), tonumber(h)
  if ww == nil or hh == nil or ww <= 0 or hh <= 0 then return false end
  local L, M, R = f.ehSboxEdgeL, f.ehSboxEdgeM, f.ehSboxEdgeR
  if isObj(L) == false or isObj(M) == false or isObj(R) == false then return false end
  local cap = hh * 4 / 39            -- 端片宽：源 4px（圆角 3px + 1px 直边）× 等比
  if cap * 2 > ww then cap = ww / 2 end
  local mid = ww - cap * 2
  if mid < 0 then mid = 0 end
  -- ★★★顺序铁律（照 0.3.21 那条「本客户端在**隐藏态**写属性不落地」）：
  --   **先把中段显示出来、再写几何** —— 上一拍框太短会把它 `Hide`，这一拍若先写宽高再 Show，
  --   那次写入落在隐藏态 ⇒ Show 出来的是上一拍的旧宽（同一个坑本项目在辉光上踩过一次）。
  if mid > 0.5 then pcall(M.Show, M) else pcall(M.Hide, M) end
  pcall(L.ClearAllPoints, L)
  pcall(L.SetPoint, L, "TOPLEFT", f.ehSbox, "TOPLEFT", 0, 0)
  pcall(L.SetWidth, L, cap)
  pcall(L.SetHeight, L, hh)
  pcall(M.ClearAllPoints, M)
  pcall(M.SetPoint, M, "TOPLEFT", L, "TOPRIGHT", 0, 0)
  pcall(M.SetWidth, M, mid)
  pcall(M.SetHeight, M, hh)
  pcall(R.ClearAllPoints, R)
  pcall(R.SetPoint, R, "TOPRIGHT", f.ehSbox, "TOPRIGHT", 0, 0)
  pcall(R.SetWidth, R, cap)
  pcall(R.SetHeight, R, hh)
  return true
end

-- ===== 顶栏筛选控件布局（唯一入口）=====
--   ★一排搞定（用户：「下一行的装备类型过滤和稀有度同一行右对齐，缩小自定义输入框的宽度」）：
--     类型图标(8) → 操作提示「?」 → 搜索框 → 稀有度小圆点（**右对齐**）
--   ★搜索框自适应：一排塞不下（< CTRL_MINSEARCH × z）就把**搜索框与圆点**掉到第二排
--     （宁可多占一排，也绝不把输入框挤成一个点）；返回内容区顶偏移（已乘 z，用的时候取负）。
B.CTRL_TOP = 34       -- 第一排顶（z 系数）★0.3.15：30 → 34（标题/右上按钮那一行整体下移 4z，见 B.metrics）
B.CTRL_PITCH = 26     -- 排距
B.CTRL_H = 24         -- 排高
B.CTRL_GAP = 6        -- 控件排与内容区之间的间隙
B.CTRL_MINSEARCH = 110

function B.ctrlApply()
  local f = B.ui.frame
  local z = B.z()
  local W = 516 * z
  if isObj(f) and type(f.GetWidth) == "function" then
    local ok, v = pcall(f.GetWidth, f)
    if ok and type(v) == "number" and v > 0 then W = v end
  end
  local x0 = 14 * z            -- ★0.3.15：左内边距 10z → 14z（与标题/底行的 14~16z 同一把尺子）
  local catSz = 24 * z
  local catGap = 2 * z
  local qbSz = 16 * z
  local sH = 20 * z
  local dotSz = 16 * z
  local dotGap = 2 * z
  local rightM = 16 * z        -- ★0.3.15：右内边距 12z → 16z
  local row1 = B.CTRL_TOP * z
  local pitch = B.CTRL_PITCH * z
  local nCat = table.getn(B.CATS)
  local catW = nCat * catSz + (nCat - 1) * catGap
  local qbX = x0 + catW + 3 * z
  local leftEdge = qbX + qbSz
  local nDot = table.getn(B.QUAL_DOTS or {})
  if nDot < 1 then nDot = 1 end
  local dotW = nDot * dotSz + (nDot - 1) * dotGap
  local dotLeft = W - rightM - dotW
  local minS = B.CTRL_MINSEARCH * z
  local rows = 1
  local sL = leftEdge + 4 * z
  local sR = dotLeft - 4 * z
  if (sR - sL) < minS then
    rows = 2
    sL = x0
    sR = dotLeft - 4 * z
    if (sR - sL) < minS then sR = sL + minS end
  end
  local sRow = row1
  local dotRow = row1
  if rows > 1 then
    sRow = row1 + pitch
    dotRow = row1 + pitch
  end
  local i
  -- 类型图标
  if isObj(f) and type(f.ehCatBtns) == "table" then
    for i = 1, table.getn(f.ehCatBtns) do
      local b = f.ehCatBtns[i]
      if isObj(b) then
        pcall(b.ClearAllPoints, b)
        pcall(b.SetPoint, b, "TOPLEFT", f, "TOPLEFT", x0 + (i - 1) * (catSz + catGap), -row1)
        pcall(b.SetWidth, b, catSz)
        pcall(b.SetHeight, b, catSz)
      end
    end
  end
  -- 操作提示「?」
  if isObj(f) and isObj(f.ehHelp) then
    pcall(f.ehHelp.ClearAllPoints, f.ehHelp)
    pcall(f.ehHelp.SetPoint, f.ehHelp, "TOPLEFT", f, "TOPLEFT", qbX, -(row1 + (catSz - qbSz) / 2))
    pcall(f.ehHelp.SetWidth, f.ehHelp, qbSz)
    pcall(f.ehHelp.SetHeight, f.ehHelp, qbSz)
  end
  -- 稀有度小圆点（右对齐）
  if isObj(f) and type(f.ehQualDots) == "table" then
    for i = 1, table.getn(f.ehQualDots) do
      local b = f.ehQualDots[i]
      if isObj(b) then
        pcall(b.ClearAllPoints, b)
        pcall(b.SetPoint, b, "TOPLEFT", f, "TOPLEFT", dotLeft + (i - 1) * (dotSz + dotGap),
          -(dotRow + (catSz - dotSz) / 2))
        pcall(b.SetWidth, b, dotSz)
        pcall(b.SetHeight, b, dotSz)
      end
    end
  end
  -- 搜索框（含 ✕ 与输入框）
  if isObj(f) and isObj(f.ehSbox) then
    pcall(f.ehSbox.ClearAllPoints, f.ehSbox)
    pcall(f.ehSbox.SetPoint, f.ehSbox, "TOPLEFT", f, "TOPLEFT", sL, -(sRow + (catSz - sH) / 2))
    pcall(f.ehSbox.SetWidth, f.ehSbox, (sR - sL))
    pcall(f.ehSbox.SetHeight, f.ehSbox, sH)
    -- ★★★0.3.23：三片切边框跟着这一处的宽高走（**唯一几何口** = 这里；换缩放/掉第二排都经过它）
    if type(B.sboxEdgeFit) == "function" then pcall(B.sboxEdgeFit, (sR - sL), sH) end
  end
  if isObj(f) and isObj(f.ehSboxClr) and isObj(f.ehSbox) then
    pcall(f.ehSboxClr.ClearAllPoints, f.ehSboxClr)
    pcall(f.ehSboxClr.SetPoint, f.ehSboxClr, "RIGHT", f.ehSbox, "RIGHT", -2 * z, 0)
    pcall(f.ehSboxClr.SetWidth, f.ehSboxClr, 18 * z)
    pcall(f.ehSboxClr.SetHeight, f.ehSboxClr, 16 * z)
  end
  if isObj(f) and isObj(f.ehEdit) and isObj(f.ehSbox) then
    pcall(f.ehEdit.ClearAllPoints, f.ehEdit)
    pcall(f.ehEdit.SetPoint, f.ehEdit, "LEFT", f.ehSbox, "LEFT", 6 * z, 0)
    pcall(f.ehEdit.SetPoint, f.ehEdit, "RIGHT", f.ehSbox, "RIGHT", -24 * z, 0)
    pcall(f.ehEdit.SetHeight, f.ehEdit, 18 * z)
  end
  -- 旧的回声行一律收起（顶栏不再有常驻文字）
  if isObj(f) and isObj(f.ehEcho) then pcall(f.ehEcho.Hide, f.ehEcho) end
  -- 内容区顶（顶栏占了多高，格子就从哪儿开始摆）
  local topOff = B.CTRL_TOP + (rows - 1) * B.CTRL_PITCH + B.CTRL_H + B.CTRL_GAP
  if isObj(f) and isObj(f.ehContent) then
    pcall(f.ehContent.ClearAllPoints, f.ehContent)
    -- ★0.3.15：内容区左内边距 12z → 16z（与 B.metrics 的 BOTTOMRIGHT -16z 成对；改一边 = 格子歪）
    pcall(f.ehContent.SetPoint, f.ehContent, "TOPLEFT", f, "TOPLEFT", 16 * z, -(topOff * z))
  end
  return topOff * z
end

-- ===== 界面几何唯一口（缩放全靠它重建；★绝不用 SetScale）=====
--   建窗后调一次；z 变了就 /reload（窗件不能销毁 ⇒ 重载才是唯一干净的重建路）。
--   ★所有固定件的锚点/尺寸**只在这里落一次**：加新控件 = 在这里补一行，别在别处写第二份几何。
function B.metrics()
  local f = B.ui.frame
  if f == nil then return end
  local z = B.z()
  local barCell = (B.BARCELL or 30) * z
  -- ★0.3.9：条宽 = 按钮边长 + 2z（两侧各 2z 内边距），右缘**贴齐**窗口左缘（锚点 0）——
  --   用户报「左侧的背包图标位置要紧贴着有着背包框」：旧写法 4z 内边距 + -4z 锚点 = 8z 空档。
  local barW = barCell + 4 * z
  B.ui.barCell = barCell
  local function ap(o, p, rp, x, y)
    if isObj(o) == false then return end
    pcall(o.ClearAllPoints, o)
    pcall(o.SetPoint, o, p, f, rp or p, x or 0, y or 0)
  end
  local function wh(o, w, h)
    if isObj(o) == false then return end
    pcall(o.SetWidth, o, w)
    if h ~= nil then pcall(o.SetHeight, o, h) end
  end
  local d = B.ui.drag
  if isObj(d) then
    pcall(d.ClearAllPoints, d)
    pcall(d.SetPoint, d, "TOPLEFT", f, "TOPLEFT", 4 * z, -8 * z)
    pcall(d.SetPoint, d, "TOPRIGHT", f, "TOPRIGHT", -112 * z, -8 * z)
    pcall(d.SetHeight, d, 22 * z)
  end
  -- ★★★0.3.15 文字/件的**边框内边距**（用户：「文字类信息能否增加和边框的一点边距」）：
  --   顶行 6z→10z、底行 8z→14z、左右 10~12z→14~16z。★窗高/内容区跟着一起放（见 B.layout 的
  --   `+ 32z` 与 B.ctrlApply 的 CTRL_TOP = 34）—— **只挪文字不放高** = 文字压到格子或掉出框外。
  ap(f.ehTitle, "TOPLEFT", "TOPLEFT", 14 * z, -10 * z)
  ap(f.ehCap, "BOTTOMLEFT", "BOTTOMLEFT", 16 * z, 14 * z)
  -- ★★★0.3.16 金钱行（三对「数字 + 金币图标」）的**唯一几何来源**：
  --   铜图标贴右下角 → 铜数字在它左边 → 银图标 → 银数字 → 金图标 → 金数字（整链 RIGHT 对齐）
  --   ★链上每颗都锚在**前一颗**上 ⇒ 不能用 ap（那个口固定锚在窗口上），改用 apRel（锚点唯一来源仍是这里）
  local function apRel(o, p, tgt, rp, x, y)
    if isObj(o) == false or isObj(tgt) == false then return end
    pcall(o.ClearAllPoints, o)
    pcall(o.SetPoint, o, p, tgt, rp, x or 0, y or 0)
  end
  local MT, MI = f.ehMoneyT, f.ehMoneyI
  if type(MI) == "table" and isObj(MI.c) then
    ap(MI.c, "BOTTOMRIGHT", "BOTTOMRIGHT", -16 * z, 14 * z)
    wh(MI.c, 14 * z, 14 * z)
    if isObj(MT.c) then apRel(MT.c, "RIGHT", MI.c, "LEFT", -2 * z, 0) end
    if isObj(MI.s) and isObj(MT.c) then
      apRel(MI.s, "RIGHT", MT.c, "LEFT", -7 * z, 0)
      wh(MI.s, 14 * z, 14 * z)
    end
    if isObj(MT.s) and isObj(MI.s) then apRel(MT.s, "RIGHT", MI.s, "LEFT", -2 * z, 0) end
    if isObj(MI.g) and isObj(MT.s) then
      apRel(MI.g, "RIGHT", MT.s, "LEFT", -7 * z, 0)
      wh(MI.g, 14 * z, 14 * z)
    end
    if isObj(MT.g) and isObj(MI.g) then apRel(MT.g, "RIGHT", MI.g, "LEFT", -2 * z, 0) end
  end
  ap(f.ehBankStat, "BOTTOMLEFT", "BOTTOMLEFT", 16 * z, 28 * z)
  ap(f.ehClose, "TOPRIGHT", "TOPRIGHT", -10 * z, -9 * z)
  wh(f.ehClose, 18 * z, 18 * z)
  ap(f.ehOptBtn, "TOPRIGHT", "TOPRIGHT", -31 * z, -9 * z)
  wh(f.ehOptBtn, 22 * z, 18 * z)
  ap(f.ehSortBtn, "TOPRIGHT", "TOPRIGHT", -56 * z, -9 * z)
  wh(f.ehSortBtn, 30 * z, 18 * z)
  ap(f.ehViewBtn, "TOPRIGHT", "TOPRIGHT", -89 * z, -9 * z)
  wh(f.ehViewBtn, 30 * z, 18 * z)
  if isObj(f.ehContent) then
    pcall(f.ehContent.ClearAllPoints, f.ehContent)
    pcall(f.ehContent.SetPoint, f.ehContent, "BOTTOMRIGHT", f, "BOTTOMRIGHT", -16 * z, 32 * z)
  end
  -- ★顶栏（类型图标 / 操作提示 / 搜索框 / 稀有度圆点）+ 内容区顶：**唯一口** B.ctrlApply()
  --   （内容区 TOPLEFT 也在它里面落锚 ⇒ 别在这里再写第二份几何）
  B.ctrlApply()
  local bar = f.ehBar
  if isObj(bar) then
    pcall(bar.ClearAllPoints, bar)
    -- ★右缘 = 窗口左缘（x = 0，紧贴）
    pcall(bar.SetPoint, bar, "TOPRIGHT", f, "TOPLEFT", 0, -4 * z)
    pcall(bar.SetWidth, bar, barW)
  end
  local bbar = f.ehBankBar
  if isObj(bbar) then
    pcall(bbar.ClearAllPoints, bbar)
    pcall(bbar.SetPoint, bbar, "TOPRIGHT", f, "TOPLEFT", -(barW + 8 * z), -4 * z)
    pcall(bbar.SetWidth, bbar, barW)
  end
end

-- ===== 刷新 =====
local function ensureButtons()
  local f = B.ui.frame
  if f == nil then return end
  local list = B.containers()
  -- 银行包位可能还没买：即使当前槽位是 0，也把 1..N 的按钮建出来（买到后立刻能用）
  local extra = {}
  local i
  if B.bankOpen == true then
    for i = 1, table.getn(B.BANKBAGS) do
      table.insert(extra, { bag = B.BANKBAGS[i], slots = bagSlotsRaw(B.BANKBAGS[i]) })
    end
    table.insert(extra, { bag = B.BANK, slots = B.BANK_PANE_SLOTS })
  end
  for i = 1, table.getn(list) do
    local bag = list[i]
    local n = B.bagSlots(bag)
    if n <= 0 then n = bagSlotsRaw(bag) end
    -- ★没有格子就不要建空表（否则「未购买的银行包」会留下一个空壳，
    --   体检/断言「这一包有没有格子」就得靠数长度，指不准）
    if n > 0 then
      if B.ui.buttons[bag] == nil then
        B.ui.buttons[bag] = {}
      end
      local s
      for s = 1, n do
        if B.ui.buttons[bag][s] == nil then
          local btn = newItemButton(f.ehContent, bag, s)
          if btn ~= nil then
            bindItemButton(btn)
            B.ui.buttons[bag][s] = btn
            table.insert(B.ui.btnList, btn)   -- ★扁平清单：陈旧格子清理要一趟扫全（不 pairs 遍历）
            B.ui.needLayout = true
          end
        end
      end
    end
  end
  for i = 1, table.getn(extra) do
    local bag = extra[i].bag
    local n = extra[i].slots
    if n > 0 then
      if B.ui.buttons[bag] == nil then B.ui.buttons[bag] = {} end
      local s
      for s = 1, n do
        if B.ui.buttons[bag][s] == nil then
          local btn = newItemButton(f.ehContent, bag, s)
          if btn ~= nil then
            bindItemButton(btn)
            B.ui.buttons[bag][s] = btn
            table.insert(B.ui.btnList, btn)   -- ★扁平清单：陈旧格子清理要一趟扫全（不 pairs 遍历）
            B.ui.needLayout = true
          end
        end
      end
    end
  end
end

-- ===== 冷却（0.3.18 重写：照客户端自己的 Cooldown.lua）=====
-- ★★★真因（用户：「物品使用了之后.会有个公共CD 的一直在转圈.不能正确停止」）：
--   客户端把冷却做成一个 **Model 子帧**（`$parentCooldown`，`inherits="CooldownFrameTemplate"`），
--   由 `Interface\FrameXML\Cooldown.lua` 的 `CooldownFrame_SetTimer(cd, start, duration, enable)` 驱动：
--     **start > 0 且 duration > 0 且 enable > 0** 才 `SetSequence(0)` + `Show()`，**否则一律 Hide()**；
--     显示之后由 Model 自己的 `OnUpdateModel` 逐帧画扫动、`OnAnimFinished` 到点**自己收起**。
--   ★旧写法错在两处：① 用 `SetCooldown`（1.12 的 Cooldown 是 **Model**，没有这个 API ⇒ pcall 静默失败）；
--     ② **丢掉 enable**（只看 dur > 0）⇒ 公共CD/物品CD 结束（enable 归 0）之后照样 `Show()`，
--     模型停在旧序列上 = **一直转圈停不下来**；空格（物品被吃掉/被挪走）那一支更是**提前 return**，
--     连 Hide 都跑不到 ⇒ 那一圈转圈留到下一件物品上。
--   ★参考插件 OneBag 的做法（实证：它的 `OneBag.lua` 里**一行冷却代码都没有**，只监听
--     `BAG_UPDATE_COOLDOWN`；模板里挂的是同一个 `CooldownFrameTemplate`）⇒ **冷却全交给客户端**，
--     我们就走同一条路，只在它上面加「数字倒计时」（客户端与 OneBag 都只有扫动动画、没有数字）。
B.CD_GAP = 0.2          -- 倒计时数字的刷新节拍（只在**真有冷却**时挂节拍；用完即摘）
B.CD_EPS = 0.05         -- 到期余量：`start+dur` 只比 now 早这么一点 ⇒ 当「已到期」
B.CD_MAX = 86400        -- 单次冷却上限的常识门（超过 ⇒ 判成坏数据，不入账）
B.CD_TRACE_MAX = 16     -- 冷却取证环上限（有界、落存档）
B.cdList = {}           -- 正在冷却的格子（有界：≤ 格数；空表 = 节拍不挂）
B.cdN = 0               -- 上表长度（`B.pumpNeed` 的第四条腿）
B.cdWriteN = 0          -- 真发过几次客户端调用（取证：`/ebag cd`）
B.cdSkipN = 0           -- 写前比对跳过几次（★这几个数只增不减，用来一眼看出「有没有每拍瞎发」）

-- ★★★0.3.19 真因（用户报障：「药水类使用完未能正确显示倒计时.然后会一直不停的循环公共cd 转圈特效」）：
--   本客户端 `GetContainerItemCooldown` 在**冷却早已走完**之后仍可能继续报 `enable > 0`（药水最明显：
--   那一圈是 1.5s 的公共CD，走完之后客户端还把同一个 `start/duration` 摆在原处）⇒ 0.3.18 那一版
--   **每 0.2s 重新调一次 `CooldownFrame_SetTimer`**，而客户端的实现是**无条件**
--   `SetSequence(0)` + `Show()`（见 `FrameXML\Cooldown.lua` 第 7~8 行）⇒ **扫动被反复从头重启**
--   = 屏上「公共CD 一直在循环转圈」；数字那一支又因为 `剩 = start+dur-now <= 0` 只画出一个「0」。
--   ⇒ 两条一起收：① **只认「真在走」的冷却**（`cdLive` 唯一判定口，已到期/坏数据一律不收）；
--     ② **写前比对**（值没变就一个字节都不碰客户端 —— 也就绝不会再重启扫动），外加**读回自证**
--     （该显示却被客户端收起来了 ⇒ 才补发一次，自愈）。
--   ★取证：每一格「原始三元组变了」就落一行进 `EH_BAG_CFG.cdTrace`（有界 16、落存档）⇒
--     AI 读存档即可判「客户端到底报了什么」，`/ebag cd` 摊开。
B.cdTraceAdd = function(line)
  local c = B.cfg()
  if type(c.cdTrace) ~= "table" then c.cdTrace = {} end
  local t = c.cdTrace
  table.insert(t, strVal(line))
  while table.getn(t) > B.CD_TRACE_MAX do table.remove(t, 1) end
end

-- ★★★唯一判定口（纯函数、可离线断言）：只有「真在走」的冷却才认
--   返回 on, why（why 进取证环 —— 一眼看出是「没冷却」还是「已到期」还是「enable=0」）
B.cdLive = function(start, dur, enable, now)
  if type(start) ~= "number" or type(dur) ~= "number" or type(enable) ~= "number" then
    return false, "判不出"
  end
  if start <= 0 then return false, "无冷却" end
  if dur <= 0 then return false, "时长为 0" end
  if enable <= 0 then return false, "enable=0" end
  if dur > B.CD_MAX then return false, "时长超上限" end
  if (start + dur) <= (now + B.CD_EPS) then return false, "已到期(客户端仍报 enable>0)" end
  return true, "在走"
end

-- 读回自证：true / false / **nil = 判不出**（判不出绝不当成「收起了」，否则会每拍瞎补发）
B.cdShown = function(cd)
  if isObj(cd) == false then return nil end
  if type(cd.IsShown) == "function" then
    local ok, v = pcall(cd.IsShown, cd)
    if ok then return (v == true or v == 1) end
  end
  return nil
end

-- ★唯一写口（客户端）：只在「真变了」或「该显示却没显示」时才惊动它 —— 绝不每拍重发
local function cdSet(btn, start, dur, enable)
  local cd = btn.ehCooldown
  if isObj(cd) == false then return false end
  local now = GetTime()
  local on = B.cdLive(start, dur, enable, now)
  local shown = B.cdShown(cd)
  if on then
    local same = (btn.ehCdS == start and btn.ehCdD == dur and btn.ehCdE == enable)
    if same and shown ~= false then
      B.cdSkipN = B.cdSkipN + 1        -- ★写前比对：没变就别碰（碰了 = 客户端 SetSequence(0) 重启扫动）
      return true
    end
    B.cdWriteN = B.cdWriteN + 1
    local ok = false
    if type(CooldownFrame_SetTimer) == "function" then
      ok = pcall(CooldownFrame_SetTimer, cd, start, dur, enable)
    end
    if ok ~= true then
      -- 兜底（拿不到那个全局时）：与 Cooldown.lua **同一口径** —— 写字段 + 第 0 段 + Show
      cd.start, cd.duration, cd.stopping = start, dur, 0
      pcall(cd.SetSequence, cd, 0)
      pcall(cd.Show, cd)
    end
    btn.ehCdS, btn.ehCdD, btn.ehCdE = start, dur, enable
    if B.cdShown(cd) == false then
      B.cdTraceAdd("写后自证：格=" .. strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_) .. " 客户端仍没收起/没显示")
    end
    return true
  end
  -- 收：账上还记着 or 客户端还显示着 ⇒ 才发这一次（都不成立就一个字节都不碰）
  if btn.ehCdS ~= nil or shown == true then
    B.cdWriteN = B.cdWriteN + 1
    btn.ehCdS, btn.ehCdD, btn.ehCdE = nil, nil, nil
    if type(CooldownFrame_SetTimer) == "function" then
      pcall(CooldownFrame_SetTimer, cd, 0, 0, 0)   -- 客户端那条 else 分支就是 Hide
    else
      cd.start, cd.duration, cd.stopping = 0, 0, 0
    end
    pcall(cd.Hide, cd)
  else
    B.cdSkipN = B.cdSkipN + 1
    btn.ehCdS, btn.ehCdD, btn.ehCdE = nil, nil, nil
  end
  return false
end

-- 冷却数字排版：≥1h 用「2h」· ≥1min 用「4m12s」· ≥10s 用「12s」· <10s 保留一位小数
--   ★0.3.19：秒那一档补上 `s` 后缀 —— 光写「12」会跟格子右下角的**数量**混起来（用户看不清哪个是倒计时）
local function cdFmt(rem)
  if rem >= 3600 then return strVal(math.floor(rem / 3600 + 0.5)) .. "h" end
  if rem >= 60 then
    local mm = math.floor(rem / 60)
    local ss = math.floor(rem - mm * 60 + 0.5)
    if ss >= 60 then mm, ss = mm + 1, 0 end
    if ss == 0 then return strVal(mm) .. "m" end
    return strVal(mm) .. "m" .. strVal(ss) .. "s"
  end
  if rem >= 10 then return strVal(math.floor(rem + 0.5)) .. "s" end
  local t = math.floor(rem * 10 + 0.5) / 10
  if t < 0 then t = 0 end
  return strVal(t)
end

local function cdListAdd(btn)
  if btn.ehCdOn == true then return end
  btn.ehCdOn = true
  table.insert(B.cdList, btn)
  B.cdN = table.getn(B.cdList)
end

local function cdListDel(btn)
  if btn.ehCdOn ~= true then return end
  btn.ehCdOn = nil
  local i
  for i = table.getn(B.cdList), 1, -1 do
    if B.cdList[i] == btn then table.remove(B.cdList, i) end
  end
  B.cdN = table.getn(B.cdList)
end

-- ★唯一绘制口：**每一格每一拍都走它**（空格也要走 —— 空格必须把转圈收掉，这就是「停不下来」的修法）
local function cdPaint(btn, rec)
  local cd = btn.ehCooldown
  if isObj(cd) == false then return false end
  local start, dur, enable = 0, 0, 0
  if rec ~= nil and rec.bankMain ~= true and type(GetContainerItemCooldown) == "function" then
    local ok, s1, d1, e1 = pcall(GetContainerItemCooldown, btn.ehBag, btn.ehSlot_)
    if ok then start, dur, enable = s1, d1, e1 end
  end
  local now = GetTime()
  local on, why = B.cdLive(start, dur, enable, now)
  -- ★取证环：**只在原始三元组变了**时记一行（真机取证靠它，且绝不刷屏）
  local raw = strVal(start) .. "," .. strVal(dur) .. "," .. strVal(enable)
  if btn.ehCdRaw ~= raw then
    btn.ehCdRaw = raw
    local rem0 = (start + dur) - now
    if rem0 < 0 then rem0 = 0 end
    B.cdTraceAdd("格=" .. strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_)
      .. " raw=" .. raw .. " 剩=" .. strVal(math.floor(rem0 * 10 + 0.5) / 10)
      .. " 判定=" .. (on and "显示" or ("收起(" .. strVal(why) .. ")")))
  end
  local live = cdSet(btn, start, dur, enable)
  local txt = btn.ehCDText
  if isObj(txt) then
    local rem = (start + dur) - now
    if live and rem > 0 then
      pcall(txt.SetText, txt, cdFmt(rem))
      pcall(txt.Show, txt)
    else
      pcall(txt.SetText, txt, "")
      pcall(txt.Hide, txt)
    end
  end
  if live then cdListAdd(btn) else cdListDel(btn) end
  return live
end

-- 节拍腿：只走**正在冷却**的那几格（有界、按需）—— 到点把冷却收干净的也是它
function B.cdTick()
  local list = B.cdList
  if type(list) ~= "table" then return end
  local i
  for i = table.getn(list), 1, -1 do
    local btn = list[i]
    local shown = true
    if isObj(btn) and type(btn.IsShown) == "function" then
      local okS, v = pcall(btn.IsShown, btn)
      if okS and v == false then shown = false end
    end
    if isObj(btn) ~= true or shown ~= true then
      if isObj(btn) then cdListDel(btn) else table.remove(list, i) end
    else
      cdPaint(btn, B.itemAt(btn.ehBag, btn.ehSlot_))
    end
  end
  B.cdN = table.getn(B.cdList)
end

-- 关窗 / 关接管：冷却账与数字一起收（关断四件事里的「数据重置」）
function B.cdForget()
  local list = B.cdList
  if type(list) ~= "table" then
    B.cdList = {}
  else
    local i
    for i = table.getn(list), 1, -1 do
      local btn = list[i]
      if isObj(btn) then
        btn.ehCdOn = nil
        -- ★0.3.19：写前比对的那份账也一起清（否则「关窗→再开窗」会以为客户端还显示着 ⇒ 少发一次写）
        btn.ehCdS, btn.ehCdD, btn.ehCdE = nil, nil, nil
        btn.ehCdRaw = nil
        if isObj(btn.ehCDText) then
          pcall(btn.ehCDText.SetText, btn.ehCDText, "")
          pcall(btn.ehCDText.Hide, btn.ehCDText)
        end
        if isObj(btn.ehCooldown) then pcall(btn.ehCooldown.Hide, btn.ehCooldown) end
      end
      table.remove(list, i)
    end
  end
  B.cdN = 0
  if type(B.pumpSync) == "function" then B.pumpSync() end
end

-- 一格的样子：图标 / 数量 / 整格底色 + 格框染色（品质 / 悬停高亮） / 辉光 / 冷却
local function paintButton(btn, rec)
  if btn == nil then return end
  local c = B.cfg()
  -- ★★★0.3.19：「悬停」有两个来源，缺一个就是用户报的「格子悬停没有辉光」——
  --   ① `B.hoverBag` = **背包条图标**悬停 ⇒ 那一包所有格子一起亮（照参考 OneBag 的 HighlightBagSlots）；
  --   ② `B.hoverBtn` = **这一格自己**被悬停（格子 OnEnter 写、OnLeave 清）。
  --   0.3.18 把模板自带的 HighlightTexture（方框）收掉之后，只剩 ① ⇒ 鼠标扫过格子**什么都不发生**；
  --   现在 ② 用我们自己的**辉光贴图（透明度控制）**补回来（绝不把那两张方框贴图放回来 —— 那是「外方内圆」）。
  local hovered = (B.hoverBag ~= nil and B.hoverBag == btn.ehBag) or (B.hoverBtn ~= nil and B.hoverBtn == btn)
  if rec == nil then
    if isObj(btn.ehIcon) then pcall(btn.ehIcon.SetTexture, btn.ehIcon, nil) end
    if isObj(btn.ehCount) then pcall(btn.ehCount.SetText, btn.ehCount, "") end
    -- ★空格：底色 = **完全透明**（0.3.15 用户定：「白色搭配透明背景」）+ **一圈更暗的框**（0.3.18b；悬停由金色辉光点亮）。
    --   ★0.3.14 那版是「中性暗底 alpha 跟背景透明度走（B.bgK()）」—— 现在底层不画了，
    --     格位由那一圈暗框界定（框亮、里面透出背板）。
    applyFillTint(btn, FILL_DARK[1], FILL_DARK[2], FILL_DARK[3], 0)
    -- ★★★0.3.18b：空格**留一圈更暗的框**（alpha = B.SLOT_EMPTY_A）—— 沿革：0.3.18 按用户原话
    --   「默认空格…把白色的边框设置透明色」做成 **0 = 一个像素都不画**；真机截图逐像素核过
    --   「空格整格没有框边」（穿过空格看到的是场景）之后，用户选定「留一圈更暗的框（内部底块仍全透明）」
    --   ⇒ 框回来、底色照旧透明；悬停给一层**金色圆角辉光**（不描金框）。
    --   ★「外方内圆」的两层边框仍不会回来：模板那两张方框贴图在 newItemButton 里被收起。
    applySlotTint(btn, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_EMPTY_A)
    if hovered then
      applyGlowTint(btn, 0.95, 0.80, 0.25, B.GLOW_A_HOVER)
    else
      applyGlowTint(btn, 0, 0, 0, 0)
    end
    -- ★空格也要走冷却口：物品被吃掉/挪走之后，那一圈转圈必须**当场收掉**
    cdPaint(btn, rec)
    return
  end
  if isObj(btn.ehIcon) then pcall(btn.ehIcon.SetTexture, btn.ehIcon, rec.texture) end
  if isObj(btn.ehCount) then
    if (rec.count or 1) > 1 then
      pcall(btn.ehCount.SetText, btn.ehCount, strVal(rec.count))
    else
      pcall(btn.ehCount.SetText, btn.ehCount, "")
    end
  end
  -- ★★★整格底色按品质（0.3.7）：品质 ≥2 才上色（照参考的 special = quality > 1），
  --   白装/灰装/关掉「格框染品质」/ 悬停高亮时一律回中性暗底。
  --   ★0.3.13：颜色走**唯一变换 `B.vividRGB`**（提纯 + 拉满亮度）再乘档位系数 `B.tintK()`；
  --     标准档（sat=1、k=0.85）与 0.3.10~0.3.12 的观感逐字节一致 ⇒ 想要旧观感就用 `/ebag tint 标准`。
  local q = tonumber(rec.quality) or 1
  if c.edges ~= false and hovered ~= true and q >= 2 then
    local vr, vg, vb = B.vividRGB(qualRGB(q))
    local kk = B.tintK()
    -- ★0.3.31 每档亮度系数（B.QUAL_K / B.qualK，唯一作用点之一）：乘在颜色上 ⇒ 明暗变、色相不变；
    --   >1 的分量逐通道夹回 1（不许喂 >1 给 SetVertexColor）
    local qk = B.qualK(q)
    applyFillTint(btn, math.min(1, vr * kk * qk), math.min(1, vg * kk * qk), math.min(1, vb * kk * qk), 1)
  else
    -- ★0.3.15：中性格底 = **透明**（白装/灰装/悬停/关掉染色都只留框，不再铺一层暗底）
    applyFillTint(btn, FILL_DARK[1], FILL_DARK[2], FILL_DARK[3], 0)
  end
  -- ★★★0.3.19：悬停**不再把格框染成金色**（旧写法 = 屏上一圈硬金线），悬停**只由纹理图的透明度表达**。
  --   用户定：「边框使用纹理图控制.按照之前的悬浮纹理透明度控制,不需要边框使用像素宽度边框.
  --   可以参考背包插件那边的实现方式」⇒ 现在悬停 = 那层**辉光图**（自带 `media\slotglow.tga`，ADD）
  --   的 alpha 拉到 `B.GLOW_A_HOVER`。
  --   ★参考 OneBag 的 `HighlightBagSlots`（`tools` 外的 `tmp/OneBag/OneCore.lua:822-837`）就是这一套：
  --   `SetNormalTexture(UI-ActionButton-Border)` + `SetBlendMode("ADD")` + **`SetAlpha(.8)`** + 顶点色
  --   —— 亮暗全靠**贴图的透明度**，不是描一条像素宽度的边框；我们这层辉光图与它同一手法
  --   （而且轮廓与本插件的圆角框同源，不会出现「外方内圆」）。
  -- ★★★0.3.20：**格框（硬框贴图）一律中性色**，稀有度**不再染硬框** ——
  --   用户定：「稀有度染色也设置相同的边框尺寸.机制和悬浮辉光相同效果,只是颜色不同而已」。
  --   ★为什么原来两者看着不一样：三层（底色 `ehFill` / 格框 `ehSlot` / 辉光 `ehGlow`）的
  --     **对象尺寸本来就完全相同**（都是 `格子 × B.SLOT_K`、都锚 CENTER），差别在**贴图轮廓** ——
  --     格框那张是 ~3px 的**实线**环，辉光那张是「实线 + 向内渐弱」的**泛光**；
  --     0.3.19 起悬停只剩泛光、稀有度却还是「实线环 + 泛光」两套 ⇒ 观感上就是两个尺寸。
  --   ⇒ 现在稀有度 = **只由那层辉光表达**（与悬停同一层、同一尺寸、同一强度），
  --     悬停与品质的差别**只剩颜色**（金 vs 品质色）。★`c.edges == false`（菜单「格框染品质」关掉）
  --     仍然一个字节都不写色（下面辉光那一段会整条回中性）⇒ 门还在，只是作用点挪到辉光。
  if isObj(btn.ehSlot) then
    applySlotTint(btn, B.SLOT_DIM, B.SLOT_DIM, B.SLOT_DIM)
  end
  -- 悬停 = 金色辉光（**唯一**的悬停表达）· 非悬停 = 品质辉光 · 中性 ⇒ 收起
  if hovered then
    applyGlowTint(btn, 0.95, 0.80, 0.25, B.GLOW_A_HOVER)
  elseif c.edges ~= false and q >= 2 then
    local vr, vg, vb = B.vividRGB(qualRGB(q))
    -- ★0.3.31 每档亮度系数：辉光乘在**写值 α** 上（B.glowAlpha 夹到 ≤1；颜色保持 vivid 原色、色相不变）
    applyGlowTint(btn, vr, vg, vb, B.GLOW_A * B.qualK(q))
  else
    applyGlowTint(btn, 0, 0, 0, 0)
  end
  -- ★0.3.18：冷却**每格都走同一个口**（含空格 —— 见 cdPaint 上方长注释）
  cdPaint(btn, rec)
end

-- ★★★0.3.19：只重画**一格**（格子悬停高亮用）—— 走与 `refreshBag` **同一个绘制口** `paintButton`。
--   为什么不做「全窗 refreshAll()」：悬停是高频动作（鼠标扫过一排格子 = 十几次），
--   全窗重画要把每个容器的每格 `itemAt` 重算一遍 = 白开销。
--   为什么不做「就地只改辉光/框色」：格框与辉光的**唯一判定**在 paintButton 里（悬停金 / 品质色 / 中性），
--   在这里再抄一份判定 = 下一个漏改点（0.3.18 刚把两处合成一处）。
--   ★拿不到格子身份（不是数字）⇒ 如实返回 false，一个字节都不动。
function B.paintOne(btn)
  if isObj(btn) ~= true then return false end
  -- ★格号字段是 `ehSlot_`（数字）；`ehSlot` 是**那圈格框纹理对象**，两者差一个下划线、混用即崩
  local bag, slot = btn.ehBag, btn.ehSlot_
  if type(bag) ~= "number" or type(slot) ~= "number" then return false end
  paintButton(btn, B.itemAt(bag, slot))
  return true
end


-- 筛选：命中保留 alpha 1、未命中变暗（与搜索同一套语义；照 OneBag 不重排格子）
local function matchFilter(rec)
  local c = B.cfg()
  if rec == nil then return true end
  local fType = c.fType
  if type(fType) == "string" and fType ~= "all" then
    if B.catOf(rec.itemType, rec.equipLoc) ~= fType then return false end
  end
  local fQual = c.fQual
  if type(fQual) == "number" and fQual >= 0 then
    if (rec.quality or 1) ~= fQual then return false end
  end
  local q = B.searchText
  if type(q) == "string" and q ~= "" then
    local nm = string.lower(rec.name or "")
    if string.find(nm, q, 1, true) == nil then return false end
  end
  return true
end

function B.refreshBag(bag)
  local t = B.ui.buttons[bag]
  if t == nil then return 0 end
  local n = B.bagSlots(bag)
  -- ★★收起的容器（逐背包收起 / 钥匙链收起 / 银行关窗）**一格都不画**：旧写法这里退回
  --   `bagSlotsRaw(bag)`（物理上还有格数）⇒ 末尾那句 `btn.Show` 把陈旧格子又点亮，
  --   与 layout 的陈旧格子清理打架 = 用户报「底部多出来一个异常的区块」。
  if n <= 0 then return 0 end
  local c = B.cfg()
  local dim = c.dim or DEF.dim
  local used = 0
  local gen = B.ui.liveGen      -- ★本拍 refreshAll 的世代号：盖过章的格子才算「活着的」
  local s
  for s = 1, n do
    local btn = t[s]
    if btn ~= nil then
      btn.ehLive = gen
      local rec = B.itemAt(bag, s)
      -- ★0.3.21：**先把这一格显示出来、再画子件**（父按钮隐藏时写子件属性同样不落地 ——
      --   与辉光那条同源；末尾那句 Show 照旧留着当幂等兜底）
      if type(btn.Show) == "function" then pcall(btn.Show, btn) end
      paintButton(btn, rec)
      if rec ~= nil then used = used + 1 end
      if rec ~= nil and matchFilter(rec) == false then
        pcall(btn.SetAlpha, btn, dim)
      else
        pcall(btn.SetAlpha, btn, 1)
      end
      if type(btn.Show) == "function" then pcall(btn.Show, btn) end
    end
  end
  return used
end

function B.refreshAll()
  if B.ui.frame == nil then return end
  -- ★陈旧格子清理的世代号：下面 refreshBag 逐格盖章，末尾按它把**没盖到的**格子收起来
  local gen = (B.ui.liveGen or 0) + 1
  B.ui.liveGen = gen
  ensureButtons()
  if B.ui.needLayout then B.layout() end
  -- ★一次遍历同时算「已用/总数」（第二遍重读 = 白跑一倍客户端调用）
  local used, total = 0, 0
  local list = B.containers()
  local k
  for k = 1, table.getn(list) do
    local bag = list[k]
    -- ★只有「本趟真在窗口里摆出来的容器」才画格子（与 B.layout 同一把尺子：n = B.bagSlots(bag) > 0）——
    --   收起的包 / 关掉的银行格子一个都别 Show（旧写法对「已收起但物理上还有格数」的包照旧 refreshBag
    --   ⇒ 末尾的 Show 把陈旧格子点亮）。容量统计照旧按物理格数算，只是不画。
    local live = (B.bagSlots(bag) > 0)
    if live or bagSlotsRaw(bag) > 0 then
      total = total + math.max(B.bagSlots(bag), bagSlotsRaw(bag))
    end
    if live then used = used + B.refreshBag(bag) end
  end
  -- ★★★陈旧格子清理（0.3.6；用户报「底部多出来一个异常的区块」）：**本拍没被 B.refreshBag 盖过章的格子
  --   一律收起** —— 银行关窗 / 逐背包收起 / 钥匙链收起 / 拔掉的包 / 格数变少时多出来的那一批，全是我们
  --   建过的按钮（1.12 **没有销毁帧/纹理的 API** ⇒ 只能显式 Hide）。旧写法只「画在容器表里的容器」⇒
  --   关一次银行，那 24 个格子就留在窗框**下面**（子帧能画到父帧外）＝屏上多出来的那个方块；
  --   刚建出来还没来得及摆的新格子也会被这一趟收掉（新建帧默认是显示的）。
  local bl = B.ui.btnList
  local bi
  for bi = 1, table.getn(bl) do
    local bb = bl[bi]
    if isObj(bb) and bb.ehLive ~= gen then
      if isObj(bb.ehIcon) then pcall(bb.ehIcon.SetTexture, bb.ehIcon, nil) end
      if isObj(bb.ehCount) then pcall(bb.ehCount.SetText, bb.ehCount, "") end
      if type(bb.Hide) == "function" then pcall(bb.Hide, bb) end
    end
  end
  local f = B.ui.frame
  if isObj(f.ehTitle) then pcall(f.ehTitle.SetText, f.ehTitle, L("TITLE")) end
  if isObj(f.ehCap) then
    pcall(f.ehCap.SetText, f.ehCap, L("CAP_FMT", used, total, total - used))
  end
  -- ★0.3.16：金钱行 = 三对「数字 + 金币图标」（唯一绘制口 B.moneyPaint / 唯一读口 B.moneyRefresh）
  B.moneyRefresh()
  B.refreshCatBtns()
  B.refreshQualDots()
  B.refreshBankStat()
  B.refreshBar()
  B.viewSync()
end

function B.applyFilter()
  if B.ui.frame == nil then return end
  local list = B.containers()
  local k
  for k = 1, table.getn(list) do
    B.refreshBag(list[k])
  end
end

-- 银行包位状态行（参考的 UpdateBagSlotStatus：缺的包位标红 + 下一格花费）
function B.refreshBankStat()
  local f = B.ui.frame
  if f == nil or isObj(f.ehBankStat) == false then return end
  if B.bankOpen ~= true then
    pcall(f.ehBankStat.SetText, f.ehBankStat, "")
    return
  end
  local num, full
  if type(GetNumBankSlots) == "function" then
    local ok, a, b = pcall(GetNumBankSlots)
    if ok then num, full = a, b end
  end
  if type(num) ~= "number" then
    pcall(f.ehBankStat.SetText, f.ehBankStat, L("BANK_TITLE"))
    return
  end
  local costTxt = "?"
  if full == true then
    costTxt = L("EMPTY")
  elseif type(GetBankSlotCost) == "function" then
    local ok, cost = pcall(GetBankSlotCost, num)
    if ok and type(cost) == "number" then costTxt = moneyStr(cost) end
  end
  pcall(f.ehBankStat.SetText, f.ehBankStat, L("BANK_SLOTS_FMT", num, 6, costTxt))
end

function B.refreshBar()
  local f = B.ui.frame
  if f == nil then return end
  local k
  for k = 1, table.getn(B.BAGS) do
    local bag = B.BAGS[k]
    local b = B.ui.bags[bag]
    if isObj(b) then
      local tex
      local inv
      if bag == 0 then
        tex = B.res("Button-Backpack-Up", "Interface\\Buttons\\Button-Backpack-Up")
      else
        if type(ContainerIDToInventoryID) == "function" then
          local ok, v = pcall(ContainerIDToInventoryID, bag)
          if ok then inv = v end
        end
        if inv == nil then inv = 19 + bag end
        if type(GetInventoryItemTexture) == "function" then
          local ok, v = pcall(GetInventoryItemTexture, "player", inv)
          if ok and type(v) == "string" and v ~= "" then tex = v end
        end
      end
      if tex ~= nil and isObj(b.ehIcon) then pcall(b.ehIcon.SetTexture, b.ehIcon, tex) end
      if isObj(b.ehEdge) then
        if bagShown(bag) then
          pcall(b.ehEdge.SetVertexColor, b.ehEdge, 0.85, 0.70, 0.20, 1)
        else
          pcall(b.ehEdge.SetVertexColor, b.ehEdge, 0.35, 0.35, 0.35, 1)
        end
      end
      if isObj(b.ehIcon) then
        if bagShown(bag) then
          pcall(b.ehIcon.SetVertexColor, b.ehIcon, 1, 1, 1)
        else
          pcall(b.ehIcon.SetVertexColor, b.ehIcon, 0.45, 0.45, 0.45)
        end
      end
    end
  end
  local kb = B.ui.keyringBtn
  if isObj(kb) then
    if isObj(kb.ehIcon) then
      local ok, tex = pcall(kb.ehIcon.SetTexture, kb.ehIcon, B.res("KeyRing-Bag-Icon", "Interface\\ContainerFrame\\KeyRing-Bag-Icon"))
      if not ok then pcall(kb.ehIcon.SetTexture, kb.ehIcon, B.res("UI-Button-KeyRing", "Interface\\Buttons\\UI-Button-KeyRing")) end
      -- ★这里只画图标：显隐一律由 layout 决定（「钥匙链：关」⇒ 整个按钮 Hide，见 B.layout）
      pcall(kb.ehIcon.SetVertexColor, kb.ehIcon, 1, 1, 1)
    end
  end
  -- 银行包条
  local i
  for i = 1, table.getn(B.BANKBAGS) do
    local bag = B.BANKBAGS[i]
    local b = B.ui.bankButtons[bag]
    if isObj(b) then
      local inv = 63 + i
      local tex
      if type(GetInventoryItemTexture) == "function" then
        local ok, v = pcall(GetInventoryItemTexture, "player", inv)
        if ok and type(v) == "string" and v ~= "" then tex = v end
      end
      if isObj(b.ehIcon) then
        if tex ~= nil then
          pcall(b.ehIcon.SetTexture, b.ehIcon, tex)
          pcall(b.ehIcon.SetVertexColor, b.ehIcon, 1, 1, 1)
        else
          pcall(b.ehIcon.SetTexture, b.ehIcon, nil)
        end
      end
      if isObj(b.ehEdge) then
        if tex ~= nil then
          if bagShown(bag) then
            pcall(b.ehEdge.SetVertexColor, b.ehEdge, 0.85, 0.70, 0.20, 1)
          else
            pcall(b.ehEdge.SetVertexColor, b.ehEdge, 0.35, 0.35, 0.35, 1)
          end
        else
          -- 未购买的包位：红框（参考同款）
          pcall(b.ehEdge.SetVertexColor, b.ehEdge, 1.0, 0.1, 0.1, 1)
        end
      end
    end
  end
end

-- 筛选项文案（图标行的 8 类 + 「全部」；唯一来源 —— 悬停提示与命令回显都读它）
local TYPE_KEYS = {
  all = "TYPE_ALL", equip = "TYPE_EQUIP", consume = "TYPE_CONSUME", trade = "TYPE_TRADE",
  quest = "TYPE_QUEST", container = "TYPE_CONTAINER", other = "TYPE_OTHER",
  reagent = "TYPE_REAGENT", projectile = "TYPE_PROJECTILE",
}

function B.filterTypeLabel()
  local c = B.cfg()
  local cur = c.fType
  if type(cur) ~= "string" then cur = "all" end
  return L(TYPE_KEYS[cur] or "TYPE_ALL")
end

function B.filterQualLabel()
  local c = B.cfg()
  local q = c.fQual
  if type(q) ~= "number" or q < 0 then return L("QUAL_ALL") end
  if q > 6 then q = 6 end
  return L("QUAL" .. strVal(q))
end

-- ===== 显隐 =====
function B.show(reason)
  if B.active() == false then
    if B.yield == true then
      sayForce(L("YIELD_CMD"))
    else
      sayForce(L("ENABLE_FIRST"))
    end
    return false
  end
  if B.build() == false then return false end
  local f = B.ui.frame
  if type(f.Show) == "function" then pcall(f.Show, f) end
  B.visible = true
  -- ★0.3.12：开窗先自愈一次（覆盖上一局留在存档里的「屏外逻辑锚点」= 用户报的"依附在右边拖不动"）
  B.winAuto("开窗")
  B.barSync()
  B.ui.needLayout = true
  B.layout()
  B.refreshAll()
  -- ★★★0.3.25：**隔着几拍再画一趟**（延后 0.05s，由唯一节拍帧执行）——
  --   真机「隐藏态写属性不落地」那一家族（0.3.21 的辉光、0.3.25 的空格框）都发生在
  --   「窗口刚 `Show`、同一帧里就写属性」这一拍：本客户端要等对象**真正可见之后**写的属性才落地
  --   ⇒ 开窗这一趟只当**第一次尝试**，到点那一拍写下去的才与玩家看到的一致。
  --   代价 = 每次开窗多一趟 `refreshAll`（几十格的 Set*，可忽略）；换到的是
  --   「**初始状态 == 悬停之后的状态**」这条承诺（用户点名：空格框不该悬停一次就变样）。
  --   ★走既有的延后刷新口（`B.refreshAt` + `B.pumpNeed` 第一条腿），不新增计时器/不新增节拍帧。
  B.refreshAt = GetTime() + 0.05
  if type(B.pumpSync) == "function" then B.pumpSync() end
  B.hideNative()
  -- 音效（照参考 OneBag 的 OnShow/OnHide：开窗 igBackPackOpen / 关窗 igBackPackClose）
  if type(PlaySound) == "function" then pcall(PlaySound, "igBackPackOpen") end
  B.traceAdd("show", strVal(reason or ""))
  -- ★「打开提示」每个会话只打一次（每次开窗都刷一行 = 玩家眼里的噪声）
  if reason ~= "silent" and B.saidHello ~= true then
    B.saidHello = true
    say(L("HELP_HINT"))
  end
  return true
end

function B.hide(reason)
  local f = B.ui.frame
  if f ~= nil then
    if type(f.Hide) == "function" then pcall(f.Hide, f) end
    if isObj(f.ehBar) and type(f.ehBar.Hide) == "function" then pcall(f.ehBar.Hide, f.ehBar) end
    if isObj(f.ehBankBar) and type(f.ehBankBar.Hide) == "function" then pcall(f.ehBankBar.Hide, f.ehBankBar) end
  end
  B.visible = false
  B.menuClose()
  -- ★拆分确认窗也在「关窗」这条路收（关断四件事）：**把光标上那一整堆放回原格**（绝不清光标 —— 清 = 丢件）
  if type(B.splitApply) == "function" and B.splitOn == true then B.splitApply(false) end
  -- ★关窗当面结束拖拽（「关断四件事」：不留黏在光标上的窗口、也不留吃点击的接盘）
  if type(B.dragStop) == "function" then B.dragStop() end
  if type(PlaySound) == "function" then pcall(PlaySound, "igBackPackClose") end
  B.traceAdd("hide", strVal(reason or ""))
  -- 关窗即停止整理（「关断四件事」里的节拍停止：sortStopFn 会真摘节拍）
  if B.sortOn == true and type(B.sortStopFn) == "function" then
    B.sortStopFn(L("SORT_STOP_GONE"))
  end
  -- ★0.3.18：冷却账与倒计时数字一起收（「关断四件事」的数据重置）⇒ 下次开窗从零算
  if type(B.cdForget) == "function" then B.cdForget() end
  -- ★0.3.19：悬停账也一起收 —— 关窗时鼠标可能还停在哪一格上（客户端不一定补发 OnLeave）
  --   ⇒ 下次开窗那一格会自带金框/金辉光
  if type(B.hoverForget) == "function" then B.hoverForget() end
  return true
end

-- ★★★0.3.19：关窗也要把「悬停了哪一格」这份会话账清掉（关断四件事的数据重置）——
--   否则关窗再开窗时那一格会**自带金框/金辉光**（鼠标早就不在那儿了）。
function B.hoverForget()
  B.hoverBtn = nil
  B.hoverBag = nil
end

function B.toggle()
  if B.visible == true then
    B.hide("toggle")
  else
    B.show("toggle")
  end
end

-- ★★★真机报障的关键修法（「能开不能关」）：
--   客户端的切换逻辑问的是 `ContainerFrame1:IsShown()`，而我们把原生帧藏了 ⇒ 它**永远走「打开」分支**
--   ⇒ 每次按键都调 Open* ⇒ 我们每次 show ⇒ 关不掉。
--   ⇒ 语义修正：「已经开着还收到一次『打开』」只可能是玩家按了切换键 ⇒ 当成关闭。
function B.intentOpen()
  if B.visible == true then
    B.hide("toggle")
  else
    B.show("silent")
  end
end

function B.intentClose()
  B.hide("close")
end

function B.intentToggle()
  B.toggle()
end

-- ★「自动开窗」（银行/商贩/交易/拍卖 SHOW）必须是**确保显示**，绝不能走 intentOpen ——
--   玩家在背包窗开着时打开银行，走 intentOpen 会把它**关掉**（那是给按键切换用的语义）。
function B.ensureShown()
  if B.visible ~= true then
    B.show("silent")
  end
end

-- ===== 原生容器帧：隐藏 + 全局接管 =====
local NATIVE_FRAMES = { "ContainerFrame1", "ContainerFrame2", "ContainerFrame3", "ContainerFrame4", "ContainerFrame5" }

function B.hideNative()
  if B.active() == false then return end
  local i
  for i = 1, table.getn(NATIVE_FRAMES) do
    local fr = _G[NATIVE_FRAMES[i]]
    if isObj(fr) and type(fr.Hide) == "function" then pcall(fr.Hide, fr) end
  end
end

-- 参考 OneBag 的 OnEnable 包装清单（只包**存在**的那些；不存在的如实记进 trace，不硬造全局）
local WRAP_NAMES = {
  "IsBagOpen", "ToggleBag", "OpenBag", "CloseBag",
  "OpenBackpack", "CloseBackpack", "ToggleBackpack",
  "OpenAllBags", "CloseAllBags",
  "ContainerFrame_Update",
}

-- 唯一包装口：先存原函数（按身份比对还原），再装我们的
function B.wrapGlobal(name, fn)
  local cur = _G[name]
  if type(cur) ~= "function" then return false end
  if B.orig and B.orig[name] ~= nil then return true end
  B.orig = B.orig or {}
  B.orig[name] = cur
  _G[name] = fn
  return true
end

function B.unwrapAll()
  if B.orig == nil then return end
  local list = {}
  local n
  for n in pairs(B.orig) do
    table.insert(list, n)
  end
  local i
  for i = 1, table.getn(list) do
    local name = list[i]
    local wrapped = _G[name]
    -- ★按身份比对：期间被别人套过包装就不许冲掉别人的
    if type(wrapped) == "function" and B.wrapperOf and B.wrapperOf[name] == wrapped then
      _G[name] = B.orig[name]
    end
  end
  B.orig = nil
  B.wrapperOf = nil
end

function B.installHooks()
  if B.hooked == true then return end
  B.orig = B.orig or {}
  B.wrapperOf = B.wrapperOf or {}
  local function reg(name, fn)
    if B.wrapGlobal(name, fn) then
      B.wrapperOf[name] = _G[name]
    else
      B.missing = B.missing or {}
      B.missing[name] = true
    end
  end

  reg("IsBagOpen", function()
    B.traceAdd("IsBagOpen", "")
    if B.active() then
      return B.visible and true or false
    end
    local o = B.orig and B.orig.IsBagOpen
    if o ~= nil then return pcall(o) end
    return false
  end)
  reg("ToggleBag", function(bag)
    B.traceAdd("ToggleBag", strVal(bag))
    if B.active() then
      if bag ~= nil and B.isBankContainer(bag) and B.bankOpen ~= true then return end
      B.intentToggle()
      return
    end
    local o = B.orig and B.orig.ToggleBag
    if o ~= nil then pcall(o, bag) end
  end)
  reg("OpenBag", function(bag)
    B.traceAdd("OpenBag", strVal(bag))
    if B.active() then
      B.intentOpen()
      return
    end
    local o = B.orig and B.orig.OpenBag
    if o ~= nil then pcall(o, bag) end
  end)
  reg("CloseBag", function(bag)
    B.traceAdd("CloseBag", strVal(bag))
    if B.active() then
      B.intentClose()
      return
    end
    local o = B.orig and B.orig.CloseBag
    if o ~= nil then pcall(o, bag) end
  end)
  reg("OpenBackpack", function()
    B.traceAdd("OpenBackpack", "")
    if B.active() then
      B.intentOpen()
      return
    end
    local o = B.orig and B.orig.OpenBackpack
    if o ~= nil then pcall(o) end
  end)
  reg("CloseBackpack", function()
    B.traceAdd("CloseBackpack", "")
    if B.active() then
      B.intentClose()
      return
    end
    local o = B.orig and B.orig.CloseBackpack
    if o ~= nil then pcall(o) end
  end)
  reg("ToggleBackpack", function()
    B.traceAdd("ToggleBackpack", "")
    if B.active() then
      B.intentToggle()
      return
    end
    local o = B.orig and B.orig.ToggleBackpack
    if o ~= nil then pcall(o) end
  end)
  reg("OpenAllBags", function()
    B.traceAdd("OpenAllBags", "")
    if B.active() then
      B.intentOpen()
      return
    end
    local o = B.orig and B.orig.OpenAllBags
    if o ~= nil then pcall(o) end
  end)
  reg("CloseAllBags", function()
    B.traceAdd("CloseAllBags", "")
    if B.active() then
      B.intentClose()
      return
    end
    local o = B.orig and B.orig.CloseAllBags
    if o ~= nil then pcall(o) end
  end)
  reg("ContainerFrame_Update", function(frame)
    if B.active() then
      if isObj(frame) and type(frame.Hide) == "function" then pcall(frame.Hide, frame) end
      return
    end
    local o = B.orig and B.orig.ContainerFrame_Update
    if o ~= nil then pcall(o, frame) end
  end)
  B.hooked = true
end

-- ===== 互斥检测 =====
local RIVALS = { "OneBag", "OneBank", "OneRing", "OneView", "Bagnon", "Combuctor", "ArkInventory", "AllBags" }

function B.detectRivals()
  local found = {}
  local i
  for i = 1, table.getn(RIVALS) do
    local id = RIVALS[i]
    local hit = false
    if type(IsAddOnLoaded) == "function" then
      local ok, v = pcall(IsAddOnLoaded, id)
      if ok and v then hit = true end
    end
    -- 第二信号：它的全局对象在（= 文件真的跑过了；插件没启用时不会有）
    if hit == false and _G[id] ~= nil then
      hit = true
    end
    if hit then table.insert(found, id) end
  end
  return found
end

-- ===== 单一节拍帧（全文唯一一个 OnUpdate；挂/摘只走 pumpSync）=====
function B.pumpNeed()
  if B.dragging == true then return true end   -- ★拖拽中必须有拍子（收尾路 ③ 要读鼠标键）
  if B.refreshAt ~= nil then return true end
  if B.snapDue ~= nil then return true end
  if B.sortOn == true then return true end
  if B.tipPend ~= nil then return true end    -- ★物品气泡的延后复核待办（到点那一下必须有人执行）
  if B.viewPend ~= nil then return true end   -- ★总览气泡的延后复核待办（同一个口径）
  if (B.cdN or 0) > 0 then return true end    -- ★0.3.18 冷却倒计时（有冷却才有拍子；空表即摘）
  return false
end

function B.pumpSync()
  local t = B.tick
  if t == nil then return end
  local need = B.pumpNeed()
  if need and B.tickOn ~= true then
    if pcall(t.SetScript, t, "OnUpdate", B.pump) then
      B.tickOn = true
    end
  elseif (not need) and B.tickOn == true then
    pcall(t.SetScript, t, "OnUpdate", nil)
    B.tickOn = false
  end
end

function B.pump()
  if B.pumpNeed() == false then
    B.pumpSync()
    return
  end
  local dt = tonumber(arg1) or 0.05
  -- ★拖拽推进 + 收尾路 ③：不依赖任何帧收到「松开」事件 —— 直接读鼠标键状态（键一松当场收尾）；
  --   但**只在自校准通过时**才采信（起拖那一刻它必须报「按着」，否则整条路不用 —— 见 B.dragStart）。
  if B.dragging == true then
    if B.dragApiOK == true and type(IsMouseButtonDown) == "function" then
      local okd, down = pcall(IsMouseButtonDown, "LeftButton")
      if not okd then
        B.dragApiOK = false
      elseif down == false then
        B.dragStop("api")
      end
    end
    if B.dragging == true and type(B.dragStep) == "function" then B.dragStep(dt) end
  end
  if B.refreshAt ~= nil then
    if GetTime() >= B.refreshAt then
      B.refreshAt = nil
      B.refreshAll()
    end
  end
  -- ★跨角色快照：延后到点才写（等物品移动/银行加载落定；20s 最小间隔在 B.snapshot 里兜底）
  if B.snapDue ~= nil and GetTime() >= B.snapDue then
    B.snapDue = nil
    B.snapshot("due")
  end
  if B.sortOn == true and type(B.sortStep) == "function" then
    B.sortStep(dt)
  end
  -- ★物品气泡的延后复核：一拍之内做完（要么认客户端的内容、要么写自建文本兜底）
  if B.tipPend ~= nil then B.tipTick() end
  -- ★总览气泡同一个口径（两条流程各管各的待办，绝不互相顶掉）
  if B.viewPend ~= nil and type(B.viewTick) == "function" then B.viewTick() end
  -- ★0.3.18 冷却倒计时：只走**正在冷却**的那几格（B.cdList 有界）；到点把冷却收干净的也是它
  if (B.cdN or 0) > 0 and (B.cdAt or 0) <= GetTime() then
    B.cdAt = GetTime() + B.CD_GAP
    if type(B.cdTick) == "function" then B.cdTick() end
  end
  B.pumpSync()
end

function B.markDirty(delay)
  B.refreshAt = GetTime() + (delay or 0.25)
  B.pumpSync()
end

-- ===== 事件（照参考：银行/商贩/交易/拍卖 SHOW ⇒ 开窗；CLOSED ⇒ 关窗）=====
local EVENT_FRAME_EVENTS = {
  "BAG_UPDATE", "BAG_UPDATE_COOLDOWN", "ITEM_LOCK_CHANGED", "PLAYER_ENTERING_WORLD",
  "PLAYER_MONEY", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
}
local OPEN_EVENTS = { "BANKFRAME_OPENED", "MERCHANT_SHOW", "TRADE_SHOW", "AUCTION_HOUSE_SHOW" }
local CLOSE_EVENTS = { "BANKFRAME_CLOSED", "MERCHANT_CLOSED", "TRADE_CLOSED", "AUCTION_HOUSE_CLOSED" }

function B.setBankOpen(on)
  local was = B.bankOpen
  B.bankOpen = on and true or false
  B.ui.needLayout = true
  B.traceAdd("bank", (on and "open" or "close"))
  if was == B.bankOpen then
    B.markDirty(0.15)
    return
  end
  if B.active() and B.visible == true then
    B.layout()
    B.markDirty(0.15)
  end
  B.refreshAll()
end

function B.installEvents()
  if B.evFrame ~= nil then return end
  local ev = CreateFrame("Frame")
  B.evFrame = ev
  ev:SetScript("OnEvent", function()
    -- ★本客户端事件名可能从全局 event 或 arg1 进来，两处都认
    local eventName = event
    if type(eventName) ~= "string" then eventName = arg1 end
    if type(eventName) ~= "string" then return end
    if eventName == "BANKFRAME_OPENED" then
      B.setBankOpen(true)
      -- ★银行格子是「开窗之后才逐格填上」的 ⇒ 隔 1.2s 再记，绝不记一份空银行
      B.snapDue = GetTime() + 1.2
      B.pumpSync()
      if B.active() and B.cfg().autoShow ~= false then B.ensureShown() end
      return
    end
    if eventName == "BANKFRAME_CLOSED" then
      B.setBankOpen(false)
      return
    end
    local i
    for i = 1, table.getn(OPEN_EVENTS) do
      if OPEN_EVENTS[i] == eventName then
        if B.active() and B.cfg().autoShow ~= false then B.ensureShown() end
        return
      end
    end
    for i = 1, table.getn(CLOSE_EVENTS) do
      if CLOSE_EVENTS[i] == eventName then
        if eventName ~= "MAIL_CLOSED" then B.intentClose() end
        return
      end
    end
    if eventName == "PLAYER_ENTERING_WORLD" then
      B.ui.needLayout = true
      B.markDirty(0.4)
      -- 登录后 3s 记一份（这时背包/银行数据才齐）
      B.snapDue = GetTime() + 3
      B.pumpSync()
    else
      -- BAG_UPDATE 会连发（一次移动就一发）⇒ 一律去抖，绝不每次全刷
      B.markDirty(0.25)
      -- 物品变动后 2s 记一份（等落定；快照自己还有 20s 最小间隔）
      B.snapDue = GetTime() + 2
    end
  end)
  local i
  for i = 1, table.getn(EVENT_FRAME_EVENTS) do
    pcall(ev.RegisterEvent, ev, EVENT_FRAME_EVENTS[i])
  end
  for i = 1, table.getn(OPEN_EVENTS) do
    pcall(ev.RegisterEvent, ev, OPEN_EVENTS[i])
  end
  for i = 1, table.getn(CLOSE_EVENTS) do
    pcall(ev.RegisterEvent, ev, CLOSE_EVENTS[i])
  end
end

-- ===== 初始化 / 开关 =====
function B.countNative()
  local n = 0
  local i
  for i = 1, table.getn(NATIVE_FRAMES) do
    if _G[NATIVE_FRAMES[i]] ~= nil then n = n + 1 end
  end
  B.nativeCount = n
  return n
end

function B.setEnabled(on)
  local c = B.cfg()
  c.on = on and true or false
  if c.on then
    B.yield = false
    local rivals = B.detectRivals()
    if table.getn(rivals) > 0 and c.force ~= true then
      B.yield = true
      sayForce(L("CONFLICT", table.concat(rivals, ", ")))
      return false
    end
    B.installHooks()
    B.hideNative()
    B.show("silent")
    sayForce(L("ON"))
    return true
  end
  B.hide("off")
  B.viewClose()
  B.menuClose()
  B.unwrapAll()
  B.hooked = false
  B.yield = false
  sayForce(L("OFF"))
  return true
end

function B.init()
  local c = B.cfg()
  if type(c.fType) ~= "string" then c.fType = "all" end
  if type(c.fQual) ~= "number" then c.fQual = -1 end
  B.countNative()
  B.installEvents()
  if B.tick == nil then
    B.tick = CreateFrame("Frame", "EH_BagTick")
    B.tickOn = false
  end
  if B.active() == false then
    if B.yield == true then
      sayForce(L("CONFLICT", table.concat(B.detectRivals(), ", ")))
    end
    return
  end
  B.installHooks()
  B.hideNative()
  -- ★0.3.14 一次性出声：这一版把**初始设置**改了（背包顺序=倒序 · 整理步进=快 0.2s · 界面缩放=80% ·
  --   背包条=关 · 钥匙链=关）—— 老存档里那几项原本是旧默认值 ⇒ 用户的实际观感会变，
  --   按项目铁律「**行为改变必须出声**」如实说一次（标记位防重复；玩家自己改回去的值一个字节都不动）。
  if B.cfg().def314Said ~= true then
    B.cfg().def314Said = true
    sayForce(L("DEF_SAY_314"))
  end
  -- 载入后 4s 记一份自己的快照（PLAYER_ENTERING_WORLD 可能已经过去了）
  B.snapDue = GetTime() + 4
  B.pumpSync()
end

-- ===== 命令 =====
local function usage()
  sayForce("/ebag = 开/关背包窗")
  sayForce("/ebag on | off = 打开 / 关闭接管（off 还给原生背包）")
  sayForce("/ebag sort = 一键整理（再敲一次 = 停止）")
  sayForce("/ebag cat <类型> = 类型筛选（all|quest|equip|consume|trade|reagent|container|projectile|other）")
  sayForce("/ebag dir fwd|rev = 背包顺序（正序 / 倒序）")
  sayForce("/ebag qual <档> = 品质筛选（all|0~6）")
  sayForce("/ebag cols N = 每行列数（4~20，当前 " .. strVal(B.cfg().cols) .. "）")
  sayForce("/ebag gap [秒|档位] = 整理步进（当前 " .. B.gapText()
    .. "；档位 逐项=0.45 标准=0.30 快=0.20 极快=0.12，范围 0.10~2.00 —— ★越小越快、越看不出逐项过程）")
  sayForce("/ebag auto on|off = 银行/商贩/交易/拍卖时自动开窗（当前 " .. (B.cfg().autoShow and "开" or "关") .. "）")
  sayForce("/ebag reset = 窗口位置回正中 + 全部背包/钥匙/银行包显示")
  sayForce("/ebag center = 窗口回到屏幕中间（越界自愈的手动兜底；开窗/起拖/拖拽收尾会自动做）")
  sayForce("/ebag vsize 小|中|大 = 跨角色总览格子大小（当前 " .. B.vsizeText() .. "，越小同屏放得越多）")
  sayForce("/ebag tint 标准|鲜丽|极鲜 = 品质染色浓淡（当前 " .. B.tintText() .. "，与「格框染品质」那行独立）")
  sayForce("/ebag alpha <0~100> = 窗口背景透明度（当前 " .. B.bgText() .. "；也认小数 alpha 0.45）")
  sayForce("/ebag cgap [0~16] = 格子间距（当前 " .. strVal(B.cgap()) .. "px；0 = 格子紧贴，只影响主背包网格）")
  sayForce("/ebag force | yield = 强行接管 / 恢复自动让位")
  sayForce("/ebag view = 跨角色总览（OneView：读存档里各角色的快照，只读）")
  sayForce("/ebag menu = 设置菜单（窗口**右上**「设置」那颗按钮同一个口）")
  sayForce("/ebag chars = 列出存档里已记录的角色")
  sayForce("/ebag snap = 立刻记录本角色快照（跨角色总览的数据源）")
  sayForce("/ebag status = 体检（开关/让位/挂钩/容器/格子数/构建）")
  sayForce("/ebag tip = 物品信息最近一次判定（走的哪条路 / 客户端默认口读到几行）")
  sayForce("/ebag split = 拆分确认窗（最近一次：问了几个 / 移动了几个 / 取消还是落格）")
  sayForce("/ebag cd = 冷却体检（在走几格 / 客户端写了几次 / 写前比对跳过几次 / 取证环）")
  sayForce("/ebag bankread = 银行读数体检（只读：银行主格逐格的链接/贴图/气泡名，明细落存档）")
  sayForce("/ebag res = 资源体检（只读：15 条固定贴图的「自带/客户端」来源 + 负对照，逐条摊开）")
  sayForce("/ebag trace [N|clear] = 开合取证环（按键到底调了哪个函数）")
  sayForce("构建 " .. BAG_BUILD)
end

-- ★★★0.3.27 现场读数：格框**实际写进去的两个通道**（不透明度走**顶点色第 4 参**；`SetAlpha` 必须恒 1）。
--   为什么值得单列一行：用户两轮报障（0.3.25「悬停一次就变淡」／0.3.27「初始比悬停离开后亮」）都是
--   同一件事 —— 两个 alpha 通道被客户端**相乘**，而且**落地时机不同**（顶点色在「刚开窗」那一拍
--   就落地、`SetAlpha` 不落地）。离线 harness 的桩只记值，既不模拟相乘、也不模拟落地时机
--   ⇒ **真机读数才是唯一判据**。
--   判读：`顶点α=0.35 ｜ SetAlpha=1` = 修好的形态（初始 == 悬停离开后 == B.SLOT_EMPTY_A）；
--         `顶点α=1 ｜ SetAlpha=0.35` = 退回 0.3.25 那一版（初始会亮成纯白）；
--         `顶点α=0.35 ｜ SetAlpha=0.35` = 退回两通道都写那一版（悬停离开后 ≈ 0.12，变淡）。
function B.slotAlphaLine()
  local t = (type(B.ui) == "table") and B.ui.buttons or nil
  if type(t) ~= "table" then return "无格子" end
  local list = t[0]
  local btn = (type(list) == "table") and list[1] or nil
  if isObj(btn) ~= true or isObj(btn.ehSlot) ~= true then return "无格子（先开一次窗）" end
  local okv, _, _, _, a1 = pcall(btn.ehSlot.GetVertexColor, btn.ehSlot)
  local oka, a2 = pcall(btn.ehSlot.GetAlpha, btn.ehSlot)
  local rec = B.itemAt(0, 1)
  return "首格=" .. ((rec == nil) and "空" or "有物")
    .. " ｜ 顶点α=" .. ((okv == true) and strVal(a1) or "?")
    .. " ｜ SetAlpha=" .. ((oka == true) and strVal(a2) or "?")
    .. "（空格应为 顶点α=" .. strVal(B.SLOT_EMPTY_A) .. " / SetAlpha=1）"
end

-- ★★★0.3.26：负对照名字（`media\ehbag_absent_probe` / `….blp`）**绝不许真的存在** —— 它们是
--   「本客户端对不存在的文件也报尺寸」那条的探针；真的存在 = 自带优先那条路永远判「不可信」而退回客户端。
--   返回「居然读得到的对照条数」（正常恒 0）；闸门那边另有一条**文件系统**钉（这两个文件必须不存在）。
function B.resNegCheck()
  local bad = 0
  local f = (type(B.ui) == "table") and B.ui.frame or nil
  local i
  for i = 1, table.getn(B.OWN_FORMS) do
    if B.texProbe(f, B.MEDIA .. "ehbag_absent_probe" .. B.OWN_FORMS[i]) == true then bad = bad + 1 end
  end
  return bad
end

-- ★0.3.26 资源来源一行摘要（status 用；`/ebag res` 才是逐条摊开）
function B.resLine()
  local own, cli, why = 0, 0, {}
  local i
  for i = 1, table.getn(B.RES_LIST) do
    local nm = B.RES_LIST[i][1]
    if type(B.RES[nm]) == "string" and B.RES[nm] ~= B.RES_LIST[i][2] then
      own = own + 1
    else
      cli = cli + 1
      why[table.getn(why) + 1] = nm
    end
  end
  local s = "自带 " .. strVal(own) .. "/" .. strVal(table.getn(B.RES_LIST)) .. " 条"
    .. (cli > 0 and (" ｜ 客户端兜底 " .. strVal(cli) .. " 条（" .. table.concat(why, ",") .. "）") or "")
  if B.resAt == nil then s = s .. " ★还没扫过（开一次窗就扫）" end
  return s
end

-- ★0.3.26 **只读**资源体检（一条命令、零步骤）：逐条摊开「自带两种写法 + 负对照 + 选定路径 + 理由」。
function B.resProbe()
  local f = B.ui.frame
  if isObj(f) ~= true then
    sayForce(L("ENABLE_FIRST"))
    return false
  end
  sayForce("资源体检（0.3.26）：清单 " .. strVal(table.getn(B.RES_LIST)) .. " 条 ｜ 目录 " .. B.MEDIA
    .. " ｜ 扫描时刻=" .. ((B.resAt ~= nil) and strVal(B.resAt) or "还没扫过"))
  local i
  for i = 1, table.getn(B.RES_LIST) do
    local nm = B.RES_LIST[i][1]
    local cp = B.RES_LIST[i][2]
    -- 现场**重新探一遍**（不写缓存 ⇒ 只读、不动运行期结论）
    local live = {}
    local k
    for k = 1, table.getn(B.OWN_FORMS) do
      local suf = B.OWN_FORMS[k]
      local h = B.texProbe(f, B.MEDIA .. nm .. suf)
      local c = B.texProbe(f, B.MEDIA .. "ehbag_absent_probe" .. suf)
      live[table.getn(live) + 1] = ((suf == "") and "无后缀" or suf) .. "="
        .. ((h == true) and "有" or ((h == false) and "无" or "判不出"))
        .. "(对照" .. ((c == true) and "有" or ((c == false) and "无" or "判不出")) .. ")"
    end
    local useOwn = (type(B.RES[nm]) == "string" and B.RES[nm] ~= cp)
    sayForce("  " .. nm .. "：" .. ((useOwn and "★用自带 " or "客户端 ") .. strVal(B.RES[nm]))
      .. " ｜ " .. strVal(B.RES_WHY[nm] or "未探测") .. " ｜ 现场 " .. table.concat(live, " · "))
  end
  sayForce("  说明：物品/法术/宏图标由客户端数据现给（没法自带）；`/Game/Interface/Icons/…` 是本客户端的 UE 资产路径，"
    .. "只作分类图标第二顺位；负对照命中 = " .. strVal(B.resNegCheck()) .. " 条（应恒 0）")
  return true
end

function B.status()
  local c = B.cfg()
  local rivals = B.detectRivals()
  sayForce(L("PROBE_HEAD", BAG_BUILD,
    (c.on and "开" or "关"),
    (B.yield and "是" or "否"),
    (B.active() and "是" or "否"),
    (B.visible and "开着" or "收着"),
    (B.bankOpen and "开着" or "关着"),
    (B.tickOn and "挂着" or "真摘")))
  sayForce("互斥插件=" .. (table.getn(rivals) > 0 and table.concat(rivals, ", ") or "无")
    .. " ｜ 挂钩=" .. (B.hooked and "已装" or "未装")
    .. " ｜ 原生容器帧=" .. strVal(B.countNative())
    .. " ｜ 自动开窗=" .. (c.autoShow and "开" or "关"))
  local miss = {}
  local n
  for n in pairs(B.missing or {}) do
    table.insert(miss, n)
  end
  sayForce("原生入口存在情况：包住 " .. strVal(B.orig and "有" or "无")
    .. " ｜ 不存在的入口=" .. (table.getn(miss) > 0 and table.concat(miss, ",") or "无"))
  local total, used = 0, 0
  local list = B.containers()
  local k
  for k = 1, table.getn(list) do
    local bag = list[k]
    local nn = math.max(B.bagSlots(bag), bagSlotsRaw(bag))
    total = total + nn
    local s
    for s = 1, nn do
      if B.itemAt(bag, s) ~= nil then used = used + 1 end
    end
  end
  sayForce("容器=" .. table.concat(list, ",") .. " ｜ 格子=" .. strVal(used) .. "/" .. strVal(total)
    .. " ｜ 自建格子=" .. strVal(B.selfMade or 0)
    .. " ｜ 每行列数=" .. strVal(c.cols) .. " ｜ 整理步进=" .. strVal(c.moveGap) .. "s")
  -- ★0.3.14 外观现场读数（活口）：**品质染色**（档位 + 该档对「精良(蓝)」算出来的实际颜色 = 设置到底生没生效）
  --   与**背景透明度**（百分比）。用户报「三个级别设置了但一点作用都没」⇒ 有这一行才能一眼判「设置写了没」
  --   与「画出来是什么色」（前者看档位、后者看那三个数；两组数不匹配 = 卡的中间那一段）。
  do
    local q3r, q3g, q3b = B.vividRGB(qualRGB(3))
    local kk = B.tintK() * B.qualK(3)   -- ★0.3.31：外观行的实算色与真正画出去的同一个口径（含每档系数）
    sayForce("外观：品质染色=" .. B.tintText() .. "（" .. strVal(B.tintIdx()) .. "/" .. strVal(table.getn(B.TINTS))
      .. " ｜ 精良(蓝)实算 " .. string.format("%.3f,%.3f,%.3f", q3r * kk, q3g * kk, q3b * kk) .. "）"
      .. " ｜ 格框染品质=" .. (c.edges ~= false and "开" or "关")
      .. " ｜ 逐档系数=" .. B.qualKLine() .. " ｜ 格子间距=" .. strVal(B.cgap()) .. "px ｜ 背景透明度=" .. B.bgText() .. " ｜ 图标系数=" .. strVal(B.ICON_K)
      .. " ｜ 界面缩放=" .. strVal(math.floor(B.z() * 100 + 0.5)) .. "%")
    -- ★0.3.30 辉光读数（活口）：**写进 alpha 的值**（= 基准值原样，0.3.29 的归一已按用户要求撤销）
    --   + **观感读数**（有效 α² × 颜色亮度 —— ★各档**不相等是正常的**，它只解释「为什么亮色档看着更亮更粗」）。
    do
      local a3 = B.glowAlphaOfQ(3, B.GLOW_A * B.qualK(3))
      local a2 = B.glowAlphaOfQ(2, B.GLOW_A * B.qualK(2))
      local a4 = B.glowAlphaOfQ(4, B.GLOW_A * B.qualK(4))
      local a5 = B.glowAlphaOfQ(5, B.GLOW_A * B.qualK(5))
      local ag = B.glowAlpha(0.95, 0.80, 0.25, B.GLOW_A_HOVER)
      -- 观感 = **有效 α**（★0.3.31e 单通道：= 写值本身，不再平方）× 该颜色的亮度（**只读，不做归一**）
      local function feel(a, r, g, b) return a * B.lumaRGB(r, g, b) * 255 end   -- ★0.3.31e 单通道：有效 = 写值本身（不再平方）
      local r3, g3, b3 = B.vividRGB(qualRGB(3))
      local r2, g2, b2 = B.vividRGB(qualRGB(2))
      local r4, g4, b4 = B.vividRGB(qualRGB(4))
      local r5, g5, b5 = B.vividRGB(qualRGB(5))
      sayForce("辉光写值 α(0.3.31 逐档系数 B.QUAL_K · 无归一)：蓝 " .. string.format("%.2f", a3)
        .. " ｜绿 " .. string.format("%.2f", a2)
        .. " ｜紫 " .. string.format("%.2f", a4)
        .. " ｜橙 " .. string.format("%.2f", a5)
        .. " ｜悬停金 " .. string.format("%.2f", ag)
        .. "（基准 = 品质 " .. string.format("%.2f", B.GLOW_A)
        .. " / 悬停 " .. string.format("%.2f", B.GLOW_A_HOVER) .. "）")
      sayForce("观感读数(有效α×颜色亮度，仅读数·不做归一)：蓝 " .. string.format("%.1f", feel(a3, r3, g3, b3))
        .. " ｜绿 " .. string.format("%.1f", feel(a2, r2, g2, b2))
        .. " ｜紫 " .. string.format("%.1f", feel(a4, r4, g4, b4))
        .. " ｜橙 " .. string.format("%.1f", feel(a5, r5, g5, b5))
        .. " ｜悬停金 " .. string.format("%.1f", feel(ag, 0.95, 0.80, 0.25)))
    end
  end
  -- ★0.3.24 外部资源 + 快照反查的现场读数（活口）：
  --   · 金钱图集**自带一份**（0.3.25 起：`media\moneyicons.blp`，来源判定见 `B.mnyPickUI`），
  --     客户端那份兜底；两处都是外部文件 ⇒ 建窗期读回自证一次，明确读不到就只画文字（补 g/s/c 后缀）。
  --   · 反查次数 = 本次快照里「链接读不到 ⇒ 用自建气泡反查」用掉多少（上限 B.RICH_MAX，有界）。
  sayForce("外部资源自证：金钱图集="
    .. (B.mnyOK == true and "读得到"
      or (B.mnyOK == false and "★读不到 ⇒ 金钱只画文字（带 g/s/c 后缀）" or "判不出（不补后缀）"))
    .. "（来源 " .. strVal(B.MNY_WHY) .. "）"
    .. " ｜ 负对照=" .. strVal(B.resNegCheck()) .. " 条（应恒 0）"
    .. " ｜ 快照反查=" .. strVal(B.richN or 0) .. "/" .. strVal(B.RICH_MAX) .. " 次"
    .. ((B.richWhy ~= nil) and (" ｜ 最近一次 " .. strVal(B.richWhy)) or ""))
  -- ★0.3.26 固定资源来源一行摘要（逐条摊开走 `/ebag res`）
  sayForce("资源来源：" .. B.resLine() .. " ｜ 负对照=" .. strVal(B.resNegCheck()) .. " 条（应恒 0）")
  -- ★0.3.25 空格框自证（用户报的「悬停之后变淡」只有这一行判得出来：真机是不是两个通道被相乘）
  sayForce("空格框自证：" .. B.slotAlphaLine())
  if type(GetNumBankSlots) == "function" then
    local ok, num, full = pcall(GetNumBankSlots)
    if ok then sayForce("银行包位=" .. strVal(num) .. "/6 ｜ 满=" .. (full and "是" or "否")) end
  end
  sayForce("跨角色快照：" .. B.snapLine() .. " ｜ 总览=" .. (B.viewShown and "开着" or "收着")
    .. " ｜ 菜单=" .. (B.menuShown and "开着" or "收着")
    -- ★0.3.7 取证：菜单捕手的层级（修「菜单开着时格子拖不动」的那条）—— 必须**低于**主窗
    .. " ｜ 菜单捕手 level=" .. strVal(isObj(B.ui.menuCatch) and select(2, pcall(B.ui.menuCatch.GetFrameLevel, B.ui.menuCatch)) or "无")
    .. " ｜ 拆分窗=" .. (B.splitOn and "开着" or "收着")
    .. " ｜ 落格取证环=" .. strVal(type(B.cfg().splitTrace) == "table" and table.getn(B.cfg().splitTrace) or 0) .. " 条")
  -- ★0.3.19 冷却与悬停的现场读数（活口）：`写` 一直涨 = 又在每拍瞎发；`悬停格` 有值 = 格子悬停记账在
  sayForce("冷却：" .. strVal(B.cdN) .. " 格在走 ｜ 客户端写=" .. strVal(B.cdWriteN)
    .. " 次 ｜ 比对跳过=" .. strVal(B.cdSkipN) .. " 次"
    .. " ｜ 悬停格=" .. ((isObj(B.hoverBtn) and (strVal(B.hoverBtn.ehBag) .. "," .. strVal(B.hoverBtn.ehSlot_))) or "无")
    .. " ｜ 悬停背包=" .. strVal(B.hoverBag))
  local tl = B.tipLast
  sayForce("物品信息：最近一次=" .. (type(tl) == "table"
    and (strVal(tl.path) .. " ｜ 客户端读回 " .. strVal(tl.lines == nil and "判不出" or tl.lines) .. " 行"
      .. " ｜ 读回有内容=" .. (tl.has == true and "是" or "否"))
    or "还没悬停过格子")
    .. (type(B.tipWhy) == "string" and (" ｜ " .. B.tipWhy) or "")
    .. " ｜ 延时待办=" .. ((B.tipPend ~= nil) and "在" or "无"))
end

-- 物品信息取证：最近一次悬停走的哪条路 / 客户端默认口读到几行（读不回来才用自建文本兜底）
function B.tipDump()
  local t = B.tipLast
  if type(t) ~= "table" then
    sayForce("物品信息：还没有悬停过格子的记录（把鼠标停在一个物品上再看）")
    return
  end
  sayForce("物品信息：路径=" .. strVal(t.path)
    .. " ｜ 客户端读回行数=" .. strVal(t.lines == nil and "判不出" or t.lines)
    .. " ｜ 读回有内容=" .. (t.has == true and "是" or "否")
    .. " ｜ 袋=" .. strVal(t.bag) .. " 格=" .. strVal(t.slot) .. " ｜ 名字=" .. strVal(t.name))
  sayForce("  总览气泡（SetHyperlink）最近一次读回有内容=" .. (B.viewTipRich == true and "是" or "否/没走过"))
  sayForce("  总览气泡：延后复查待办=" .. ((B.viewPend ~= nil) and "在（等复核）" or "无")
    .. (type(B.viewWhy) == "string" and (" ｜ " .. B.viewWhy) or ""))
  local gt = _G.GameTooltip
  sayForce("  延时兜底：等待=" .. strVal(B.TIP_WAIT) .. "s ｜ 待办=" .. ((B.tipPend ~= nil) and "在（等复核）" or "无")
    .. " ｜ 气泡 ClearLines=" .. (((isObj(gt) and type(gt.ClearLines) == "function")) and "有" or "没有/判不出"))
  if type(B.tipWhy) == "string" then sayForce("  上一次走的兜底原因：" .. B.tipWhy) end
  -- ★0.3.11：空箱重申的读数 + 那次悬停的判决环（落存档 ⇒ AI 自己读，不必让玩家转述）
  sayForce("  ★空箱重申：本次悬停已重申=" .. strVal(B.tipWipes or 0) .. " 次（上限 " .. strVal(B.TIP_GUARD_MAX)
    .. "，每 " .. strVal(B.TIP_GUARD_GAP) .. "s 一拍）｜ 悬停中=" .. ((B.tipHold ~= nil) and "是（模板 OnUpdate 已被我们接管）" or "否"))
  local tt = B.cfg().tipTrace
  local tn = (type(tt) == "table") and table.getn(tt) or 0
  if tn == 0 then
    sayForce("  物品信息取证环：空的（悬停过物品的话应该有「悬停 …」行）")
  else
    local from = tn - 5
    if from < 1 then from = 1 end
    sayForce("  物品信息取证环（共 " .. strVal(tn) .. " 条，最新 6 条）：")
    local i
    for i = from, tn do sayForce("    " .. strVal(i) .. ". " .. strVal(tt[i])) end
  end
end

-- 拖动/落格/拆分取证：最近一次账 + 三处读数的有界环（判「脚本没跑」还是「条件没满足」）
--   ★环落存档（EH_BAG_CFG.splitTrace）⇒ AI 可以直接读账号存档，不必让玩家转述。
function B.splitDump()
  local sl = B.splitLast
  if type(sl) ~= "table" then
    sayForce("拆分确认窗：还没用过（拖一堆到同种物品上，或按住 Shift 拖）")
  else
    sayForce("拆分确认窗：窗=" .. (B.splitOn and "开着" or "收着")
      .. " ｜ 最近一次=" .. strVal(sl.path)
      .. " ｜ 物品=" .. strVal(sl.name or "?")
      .. " ｜ 移动=" .. strVal(sl.n) .. "/" .. strVal(sl.total)
      .. " ｜ 目标=" .. strVal(sl.tb) .. "," .. strVal(sl.ts))
  end
  sayForce("判据：合并时弹 · Shift 拖也弹 · 取消=整堆放回原格 · 全程绝不清光标")
  local t = B.cfg().splitTrace
  local nn = 0
  if type(t) == "table" then nn = table.getn(t) end
  if nn == 0 then
    sayForce("落格取证环：空的（有拖放的话应该有 idrag / idrop / isplit / ask 四族）")
    return
  end
  sayForce("落格取证环（共 " .. strVal(nn) .. " 条，最新在后）：")
  local from = nn - 5
  if from < 1 then from = 1 end
  local i
  for i = from, nn do sayForce("  " .. strVal(i) .. ". " .. strVal(t[i])) end
end

function B.traceDump(n)
  local c = B.cfg()
  local t = c.trace
  if type(t) ~= "table" or table.getn(t) == 0 then
    sayForce(L("TRACE_EMPTY"))
    return
  end
  if type(n) ~= "number" or n < 1 then n = 10 end
  sayForce(L("TRACE_HEAD", table.getn(t)))
  local from = table.getn(t) - n + 1
  if from < 1 then from = 1 end
  local i
  for i = from, table.getn(t) do
    sayForce("  " .. strVal(i) .. ". " .. strVal(t[i]))
  end
end

-- ★★★0.3.19 冷却体检（活口）：把「判定口径 + 现在正冷却的格子 + 写前比对的账 + 取证环」一次摊开
--   —— 用户报的「公共CD 一直转圈」只能靠这几组数分清：**写发得太多**（cdWriteN 一直涨）
--   还是**客户端报的冷却早已到期**（环里出现「已到期(客户端仍报 enable>0)」）。
function B.cdDump()
  local now = GetTime()
  sayForce("冷却：" .. strVal(B.cdN) .. " 格在走 ｜ 客户端写=" .. strVal(B.cdWriteN)
    .. " 次 ｜ 写前比对跳过=" .. strVal(B.cdSkipN) .. " 次（跳过占比高 = 没在每拍瞎发）")
  sayForce("  口径：start>0 且 dur>0 且 enable>0 且 dur≤" .. strVal(B.CD_MAX)
    .. " 且 start+dur > now+" .. strVal(B.CD_EPS) .. " 才算「在走」；已到期一律收起")
  sayForce("  节拍=" .. (B.tickOn and "挂着" or "真摘") .. " ｜ 间隔=" .. strVal(B.CD_GAP) .. "s ｜ now=" .. strVal(now))
  local list = B.cdList
  local n = (type(list) == "table") and table.getn(list) or 0
  if n == 0 then
    sayForce("  正在冷却的格子：无（空表 = 节拍不挂这条腿）")
  else
    local i
    for i = 1, n do
      local btn = list[i]
      if isObj(btn) then
        local s1, d1, e1 = btn.ehCdS, btn.ehCdD, btn.ehCdE
        local rem = -1
        if type(s1) == "number" and type(d1) == "number" then rem = (s1 + d1) - now end
        local txt = "?"
        if isObj(btn.ehCDText) and type(btn.ehCDText.GetText) == "function" then
          local okT, v = pcall(btn.ehCDText.GetText, btn.ehCDText)
          if okT then txt = strVal(v) end
        end
        sayForce("  " .. strVal(i) .. ". 格=" .. strVal(btn.ehBag) .. "," .. strVal(btn.ehSlot_)
          .. " 记=" .. strVal(s1) .. "," .. strVal(d1) .. "," .. strVal(e1)
          .. " 剩=" .. strVal(math.floor(rem * 10 + 0.5) / 10) .. "s 数字=" .. txt)
      else
        sayForce("  " .. strVal(i) .. ". （坏格子句柄）")
      end
    end
  end
  local t = B.cfg().cdTrace
  local tn = (type(t) == "table") and table.getn(t) or 0
  if tn == 0 then
    sayForce("  冷却取证环：空的（还没画过任何冷却格）")
    return
  end
  local from = tn - 5
  if from < 1 then from = 1 end
  sayForce("  冷却取证环（共 " .. strVal(tn) .. " 条，上限 " .. strVal(B.CD_TRACE_MAX) .. "，最新 6 条）：")
  local i
  for i = from, tn do sayForce("    " .. strVal(i) .. ". " .. strVal(t[i])) end
end

-- ★★★0.3.24 **只读**探针：银行主格的「读数体检」—— 回答「为什么快照里银行物品没有链接」。
--   一条命令、零步骤、自己落盘：逐格把四条读数摊开写进有界环 `EH_BAG_CFG.bankProbe`（上限 24 条），
--   AI 自己读存档即可定案（不让用户转述）；聊天框只回显结论行。
--   ★全只读：只 `Get*`，加上**自建隐形 tooltip** 的 Set*（那是我们自己的帧，绝不碰玩家的 GameTooltip）。
function B.bankProbe()
  local c = B.cfg()
  c.bankProbe = {}                       -- 每次重跑清空：一次运行一组读数，不给判读添乱
  local ring = c.bankProbe
  B.richN = 0                            -- 反查预算重置（探针是独立的一次读数）
  local i
  local nHave, nInvLink, nInvTex, nBoxLink, nBoxTex, nName = 0, 0, 0, 0, 0, 0
  for i = 1, B.BANK_PANE_SLOTS do
    local inv = 39 + i
    if type(BankButtonIDToInvSlotID) == "function" then
      local okb, v = pcall(BankButtonIDToInvSlotID, i)
      if okb and type(v) == "number" and v > 0 then inv = v end
    end
    local lk, tx, blk, btx = nil, nil, nil, nil
    if type(GetInventoryItemLink) == "function" then
      local ok1, v1 = pcall(GetInventoryItemLink, "player", inv)
      if ok1 and type(v1) == "string" and v1 ~= "" then lk = v1 end
    end
    if type(GetInventoryItemTexture) == "function" then
      local ok2, v2 = pcall(GetInventoryItemTexture, "player", inv)
      if ok2 and type(v2) == "string" and v2 ~= "" then tx = v2 end
    end
    if type(GetContainerItemLink) == "function" then
      local ok3, v3 = pcall(GetContainerItemLink, B.BANK, i)
      if ok3 and type(v3) == "string" and v3 ~= "" then blk = v3 end
    end
    if type(GetContainerItemInfo) == "function" then
      local ok4, v4 = pcall(GetContainerItemInfo, B.BANK, i)
      if ok4 and type(v4) == "string" and v4 ~= "" then btx = v4 end
    end
    if tx ~= nil or btx ~= nil then
      nHave = nHave + 1
      if lk ~= nil then nInvLink = nInvLink + 1 end
      if tx ~= nil then nInvTex = nInvTex + 1 end
      if blk ~= nil then nBoxLink = nBoxLink + 1 end
      if btx ~= nil then nBoxTex = nBoxTex + 1 end
      -- 自建 tooltip 的读数（名字 / 行数 / 有没有抠出链接）—— 与快照那条路**同一个口**，保证读数同源
      local nm, nl = "判不出", 0
      local hasLk = false
      local rec = { bankMain = true, invSlot = inv, bag = B.BANK, slot = i }
      local okr = pcall(B.richTry, B.BANK, i, rec)
      if okr then
        if type(rec.name) == "string" and rec.name ~= "" and rec.name ~= "?" then nm = rec.name end
        if type(rec.link) == "string" and rec.link ~= "" then hasLk = true end
        if type(rec.rl) == "table" then nl = table.getn(rec.rl) end
      end
      if nm ~= "判不出" then nName = nName + 1 end
      table.insert(ring, "格" .. strVal(i) .. " inv=" .. strVal(inv)
        .. " ｜ 装备口链接=" .. (lk ~= nil and "有" or "无") .. " 贴图=" .. (tx ~= nil and "有" or "无")
        .. " ｜ 容器口链接=" .. (blk ~= nil and "有" or "无") .. " 贴图=" .. (btx ~= nil and "有" or "无")
        .. " ｜ 气泡名=" .. strVal(nm)
        .. (hasLk and "（抠出链接）" or (" 行=" .. strVal(nl))))
    end
  end
  local head = "银行读数：有物品 " .. strVal(nHave) .. " 格"
    .. " ｜ 装备口 GetInventoryItem* 链接 " .. strVal(nInvLink) .. " / 贴图 " .. strVal(nInvTex)
    .. " ｜ 容器口(-1) 链接 " .. strVal(nBoxLink) .. " / 贴图 " .. strVal(nBoxTex)
    .. " ｜ 自建气泡读得出名字 " .. strVal(nName)
    .. " ｜ 银行窗=" .. (B.bankOpen and "开着" or "关着")
  table.insert(ring, "◆ " .. head)
  while table.getn(ring) > 24 do table.remove(ring, 1) end
  sayForce(head)
  sayForce("（逐格明细 " .. strVal(table.getn(ring)) .. " 条已落盘；本命令**全只读**）")
end

function B.cmd(msg)
  msg = string.lower(strVal(msg or ""))
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  if msg == "" or msg == "ui" or msg == "show" then
    if B.visible == true then
      B.hide("cmd")
    else
      B.show("cmd")
    end
  elseif msg == "on" then
    B.setEnabled(true)
  elseif msg == "off" then
    B.setEnabled(false)
  elseif msg == "sort" or msg == "整理" then
    B.sortStart(true)
  elseif msg == "bank" or msg == "银行" then
    B.setBankOpen(not B.bankOpen)
    sayForce("银行容器=" .. (B.bankOpen and "显示" or "隐藏") .. "（这是给无银行环境做预览用的开关）")
  elseif msg == "view" or msg == "总览" then
    B.viewToggle()
  elseif msg == "chars" or msg == "角色" then
    B.charsDump()
  elseif msg == "snap" or msg == "快照" then
    local ok = B.snapshot("force")
    sayForce(ok and L("SNAP_OK", B.snapLine()) or L("SNAP_FAIL"))
  elseif msg == "menu" or msg == "设置" then
    B.menuToggle(isObj(B.ui.frame) and B.ui.frame.ehOptBtn or nil)
  elseif msg == "status" then
    B.status()
  elseif msg == "tip" or msg == "物品信息" then
    B.tipDump()
  elseif msg == "split" or msg == "拆分" then
    B.splitDump()
  elseif msg == "cd" or msg == "冷却" then
    B.cdDump()
  elseif msg == "bankread" or msg == "银行读数" then
    B.bankProbe()
  elseif msg == "res" or msg == "资源" or msg == "资源体检" then
    -- ★0.3.26 只读：逐条摊开「自带两种写法 + 负对照 + 选定路径 + 理由」（一条命令、零步骤、不写存档）
    B.resProbe()
  elseif msg == "trace" or msg == "取证" then
    B.traceDump(10)
  elseif msg == "trace clear" or msg == "取证清空" then
    B.cfg().trace = {}
    sayForce("开合取证环已清空")
  elseif msg == "auto" then
    sayForce("自动开窗当前 = " .. (B.cfg().autoShow and "开" or "关") .. "（/ebag auto on|off）")
  elseif msg == "auto on" or msg == "auto off" then
    local on = (msg == "auto on")
    B.cfg().autoShow = on
    sayForce(on and L("AUTO_ON") or L("AUTO_OFF"))
  elseif msg == "cat" or msg == "类型" then
    sayForce(L("FILTER_NOW") .. B.filterTypeLabel()
      .. "（/ebag cat all|quest|equip|consume|trade|reagent|container|projectile|other）")
  elseif msg == "qual" or msg == "品质" then
    sayForce(L("FILTER_NOW") .. B.filterQualLabel() .. "（/ebag qual all|0~6）")
  elseif msg == "dir" or msg == "顺序" then
    sayForce(L("MENU_DIR") .. "：" .. ((B.cfg().direction == "rev") and L("DIR_REV") or L("DIR_FWD"))
      .. "（/ebag dir fwd|rev）")
  elseif msg == "reset" then
    local c = B.cfg()
    c.point = nil
    c.vpoint = nil           -- 总览窗的位置记忆也一起复位（否则「复位」了它还停在旧处）
    c.show = {}
    c.cols = DEF.cols
    local f = B.ui.frame
    if f ~= nil then
      pcall(f.ClearAllPoints, f)
      f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    B.viewRehost()           -- ★0.3.12：总览窗也跟着回主窗右侧（不然它还停在旧锚点上）
    B.ui.needLayout = true
    B.layout()
    B.refreshAll()
    sayForce("已复位：窗口回正中、全部背包/钥匙/银行包显示、每行 " .. strVal(DEF.cols) .. " 格")
  elseif msg == "center" or msg == "居中" then
    -- ★★★0.3.12：手动兜底（自动自愈在 开窗 / 起拖前 / 拖拽收尾 三处）
    B.recenter(L("MENU_WIN_CENTER"))
  elseif msg == "force" then
    B.cfg().force = true
    sayForce("已设 force：下次 /ebag on 或 /reload 后强行接管（与其它整合背包插件同开风险自负）")
  elseif msg == "yield" then
    B.cfg().force = false
    sayForce("已取消 force：恢复「检测到别的整合背包插件就让位」")
  elseif msg == "help" or msg == "?" then
    usage()
  else
    local n = string.match(msg, "^cols%s+(%d+)$")
    local tn = string.match(msg, "^trace%s+(%d+)$")
    local cn = string.match(msg, "^cat%s+([%a]+)$")
    local dn = string.match(msg, "^dir%s+([%a]+)$")
    local qn = string.match(msg, "^qual%s+([%a%d]+)$")
    -- ★步进：认小数也认百分秒（`0.2` / `.2` / `20`(=0.20)）；多字节字面量在模式里是安全的
    local gn = string.match(msg, "^gap%s+([%d%.]+)$")
    if gn == nil then gn = string.match(msg, "^步进%s+([%d%.]+)$") end
    -- ★0.3.12：总览格子档位（`/ebag vsize 小|中|大` 或系数 0.8/0.9/1.0）
    local vn = string.match(msg, "^vsize%s+(.+)$")
    if vn == nil then vn = string.match(msg, "^格子%s+(.+)$") end
    -- ★0.3.13：品质染色浓淡（`/ebag tint 标准|鲜丽|极鲜` 或序号 1/2/3）
    local tn2 = string.match(msg, "^tint%s+(.+)$")
    if tn2 == nil then tn2 = string.match(msg, "^染色%s+(.+)$") end
    -- ★0.3.14：窗背景透明度（`/ebag alpha 45` 或 `alpha 0.45`；无参数 = 只读播报）
    local an = string.match(msg, "^alpha%s*(.*)$")
    if an == nil then an = string.match(msg, "^透明度%s*(.*)$") end
    -- ★0.3.31g：格子边距（`/ebag cgap 0~16`；无参数 = 只读播报）
    local kn = string.match(msg, "^cgap%s*(.*)$")
    if kn == nil then kn = string.match(msg, "^间距%s*(.*)$") end
    if an ~= nil then
      if an == "" then
        B.bgSet(nil)                                     -- 无参数 = 只读播报（活口）
      else
        B.bgSet(an)
      end
    elseif kn ~= nil then
      if kn == "" then
        B.cgapSet(nil)                                   -- 无参数 = 只读播报（活口）
      else
        B.cgapSet(kn)
      end
    elseif tn2 ~= nil then
      local tv = tonumber(tn2)
      B.tintSet(tv ~= nil and tv or tn2)
    elseif vn ~= nil then
      local vv = tonumber(vn)
      B.vsizeSet(vv ~= nil and vv or vn)
    elseif n ~= nil then
      local v = tonumber(n)
      if v ~= nil and v >= 4 and v <= 20 then
        B.cfg().cols = v
        B.ui.needLayout = true
        B.layout()
        B.refreshAll()
        sayForce("每行列数 = " .. strVal(v))
      else
        sayForce("列数要在 4~20 之间")
      end
    elseif tn ~= nil then
      B.traceDump(tonumber(tn))
    elseif dn ~= nil then
      if dn == "rev" or dn == "fwd" then
        B.cfg().direction = dn
        B.cycleDirCheck()
        sayForce(L("MENU_DIR") .. "：" .. ((dn == "rev") and L("DIR_REV") or L("DIR_FWD")))
      else
        sayForce("顺序只能写 fwd 或 rev")
      end
    elseif cn ~= nil then
      B.catSet(cn)
      sayForce(L("FILTER_NOW") .. B.filterTypeLabel())
    elseif qn ~= nil then
      if qn == "all" then
        B.qualSet(-1)
        sayForce(L("FILTER_NOW") .. B.filterQualLabel())
      else
        local qv = tonumber(qn)
        if qv == nil or qv < 0 or qv > 6 then
          sayForce("品质档要在 0~6 之间，或写 all")
        else
          B.qualSet(qv)
          sayForce(L("FILTER_NOW") .. B.filterQualLabel())
        end
      end
    elseif msg == "cols" then
      sayForce("当前每行列数 = " .. strVal(B.cfg().cols) .. "（用法 /ebag cols 12）")
    elseif msg == "gap" or msg == "步进" then
      B.gapSet(nil)   -- 无参数 = 只读播报（同一份口径）
    elseif gn ~= nil then
      B.gapSet(gn)
    elseif msg == "scale" or msg == "缩放" then
      sayForce(L("SCALE_SAY", B.scalePct()))
    elseif string.match(msg, "^scale%s+") ~= nil or string.match(msg, "^缩放%s+") ~= nil then
      B.scaleSet(tonumber(string.match(msg, "%s+(%S+)$")))
    else
      usage()
    end
  end
end

-- ===== 载入 =====
B.init()

if type(SlashCmdList) == "table" then
  SLASH_EHBAG1 = "/ebag"
  SlashCmdList["EHBAG"] = function(msg)
    B.cmd(msg)
  end
end
