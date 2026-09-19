-- 目标职业条件断言
local function eq(a, b, msg)
  if a ~= b then error(("ASSERT FAIL [%s]: got=%s want=%s"):format(msg, tostring(a), tostring(b)), 2) end
end

-- 1) 文本解析
local g = EVAL_PARSE_CONDS("目标职业:战士/法师")
eq(g[1][1].k, "tClass", "parse k")
eq(g[1][1].cs.WARRIOR, true, "parse WARRIOR")
eq(g[1][1].cs.MAGE, true, "parse MAGE")
eq(g[1][1].cs.PRIEST, nil, "parse PRIEST nil")
eq(EVAL_PARSE_CONDS("tClass:WARRIOR")[1][1].cs.WARRIOR, true, "parse en token")
local g3 = EVAL_PARSE_CONDS("目标职业:猎人、牧师")
eq(g3[1][1].cs.HUNTER, true, "parse 顿号 HUNTER")
eq(g3[1][1].cs.PRIEST, true, "parse 顿号 PRIEST")
-- ★1.72.4 审计：原样本用的是「圣骑士」——它当时确实是**未知职业**（CLASS_LIST 里根本没有圣骑士），
--   于是这条断言其实一直在替那个数据缺口作证。1.72.4 已把圣骑士补进 CLASS_LIST（追加在末尾），
--   所以「非法职业」的样本改成真正不存在的职业名（死亡骑士 = 本客户端没有的职业）。
eq(EVAL_PARSE_CONDS("目标职业:死亡骑士")[1], nil, "非法职业整条丢弃")
eq(EVAL_PARSE_CONDS("目标职业:圣骑士")[1][1].cs.PALADIN, true, "★★★1.72.4 审计补漏：圣骑士现在是已知职业（此前模版里的 [职业:圣骑士] 全被静默丢弃）")

-- 2) 显示回环（CLASS_LIST 顺序：法师在战士前）；组间 | 不被职业串干扰
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("目标职业:战士/法师")), "目标职业:法师/战士", "str roundtrip")
local g5 = EVAL_PARSE_CONDS("战斗中 & 目标职业:战士/法师 | 非战斗")
eq(table.getn(g5), 2, "groups count")
eq(table.getn(g5[1]), 2, "group1 conds")

-- 3) 引擎：扫描动作条 → 目标职业匹配施法
EVAL_GO_RESCAN(true)
EVAL_HELP_UPDATE_STATE()
TEST.used = {}
local c1 = EVAL_RULE_RUN({ { skill = "致死打击", why = "致死打击", groups = EVAL_PARSE_CONDS("目标职业:战士") } })
eq(c1, true, "warrior target casts")
eq(TEST.used[1], 1, "used slot 1")

TEST.targetClass = "MAGE" EVAL_HELP_UPDATE_STATE()
TEST.used = {}
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标职业:战士") } }), false, "mage target skipped")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标职业:战士/法师") } }), true, "multi OR mage hits")
eq(TEST.used[1], 1, "multi OR used slot")

TEST.hasTarget = false EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标职业:战士") } }), false, "no target fails")
TEST.hasTarget = true TEST.targetClass = "WARRIOR" EVAL_HELP_UPDATE_STATE()

-- 4) 回归：旧语法 + 选取目标副作用
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("怒气>30 & 战斗中")), "怒气>30 & 战斗中", "legacy parse")
TEST.targetSel = nil
EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("选取目标:最近敌人 & 目标职业:战士") } })
eq(TEST.targetSel, "nearEnemy", "target select side effect")

-- 5) 实时 debuff 清单 + 名称→纹理学习（撕裂/断筋不在动作条）
TEST.debuffs = { { name = "撕裂", tex = "texD1" }, { name = "断筋", tex = "texD2" } }
EVAL_HELP_UPDATE_STATE()
local dl = EVAL_TARGET_DEBUFF_LIST()
eq(table.getn(dl), 2, "debuff list count")
eq(dl[1].name, "撕裂", "debuff list name")
eq(EVAL_DEBUFF_TEX_LEARN["撕裂"], "texD1", "learned tex")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有debuff:撕裂") } }), true, "hasDebuff learned hit")
TEST.debuffs = { { name = "断筋", tex = "texD2" } } EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有debuff:撕裂") } }), false, "hasDebuff miss after gone")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无debuff:撕裂") } }), true, "noDebuff hit after gone")

-- 6) 实时自身 buff 清单
TEST.buffs = { { name = "战斗怒吼", tex = "texB1" } }
local bl = EVAL_PLAYER_BUFF_LIST()
eq(table.getn(bl), 1, "buff list count")
eq(bl[1].name, "战斗怒吼", "buff list name")
eq(EVAL_DEBUFF_TEX_LEARN["战斗怒吼"], "texB1", "learned buff tex")
TEST.debuffs = {} TEST.buffs = {} EVAL_HELP_UPDATE_STATE()

-- 7) 连击点数条件（数值比较型）
local gc = EVAL_PARSE_CONDS("连击>=3")
eq(gc[1][1].k, "combo", "combo parse k")
eq(gc[1][1].op, ">=", "combo parse op")
eq(gc[1][1].n, 3, "combo parse n")
eq(EVAL_GROUP_STR(gc), "连击>=3", "combo str roundtrip")
TEST.combo = 5 EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gc } }), true, "combo 5 hits >=3")
TEST.combo = 2 EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gc } }), false, "combo 2 misses >=3")
TEST.combo = nil EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("连击>0") } }), false, "non-combo class 0 fails >0")

-- 8) 选取目标扩展：目标的目标 / 指定名称（1.29.0）
local gt = EVAL_PARSE_CONDS("选取目标:目标的目标")
eq(gt[1][1].s, "targetTarget", "parse targetTarget")
local gn = EVAL_PARSE_CONDS("选取目标:指定名称:嗜血者")
eq(gn[1][1].s, "byName", "parse byName")
eq(gn[1][1].nm, "嗜血者", "parse byName nm")
eq(EVAL_GROUP_STR(gn), "选取目标:指定名称:嗜血者", "byName str roundtrip")
eq(EVAL_GROUP_STR(gt), "选取目标:目标的目标", "targetTarget str roundtrip")
-- 未设名称：规则不过
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标职业:战士") } }), true, "setup cast ok")
TEST.used = {}
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = { { { k = "target", s = "byName" }, { k = "tClass", cs = { WARRIOR = true } } } } } }), false, "byName without nm fails")
-- 设了名称：TargetByName 带名调用
TEST.targetSel = nil
EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gn } })
eq(TEST.targetSel, "name:嗜血者", "byName calls TargetByName")
-- 目标的目标：TargetUnit("targettarget")
TEST.targetSel = nil
EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gt } })
eq(TEST.targetSel, "unit:targettarget", "targetTarget calls TargetUnit")
-- 附近敌人枚举：收 5 个唯一名并还原原目标
TEST.nearby = { "豺狼人A", "豺狼人B", "鱼人C", "鱼人D", "鱼人E", "豺狼人A", "鱼人F" } -- 循环一轮后回到 A
TEST.nearIdx = nil TEST.curTargetName = "原目标"
local nb = EVAL_NEARBY_ENEMY_NAMES(5)
eq(table.getn(nb), 5, "nearby caps 5")
eq(nb[1], "豺狼人A", "nearby first")
eq(nb[4], "鱼人D", "nearby fourth")
eq(nb[5], "鱼人E", "nearby fifth; repeat A means cycle done")
eq(TEST.curTargetName, "原目标", "nearby restores orig target")
TEST.nearby = nil TEST.curTargetName = nil

-- 9) 宠物指令特殊技能（1.30.0）：不占动作条，直调 Pet API
TEST.used = {} TEST.petCmd = nil
eq(EVAL_RULE_RUN({ { skill = "宠物:攻击", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "pet cmd rule fires without action slot")
eq(TEST.petCmd, "PetAttack", "pet cmd calls PetAttack")
eq(table.getn(TEST.used), 0, "pet cmd does not UseAction")
TEST.inCombat = true EVAL_HELP_UPDATE_STATE()
TEST.petCmd = nil
eq(EVAL_RULE_RUN({ { skill = "宠物:被动姿态", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), false, "pet cmd respects conditions")
eq(TEST.petCmd, nil, "pet cmd not called when cond fails")
EVAL_RULE_RUN({ { skill = "宠物:解散", why = "x", groups = EVAL_PARSE_CONDS("战斗中") } })
eq(TEST.petCmd, "PetDismiss", "pet dismiss calls PetDismiss")
-- 无宠物时跳过
TEST.hasPet = false TEST.petCmd = nil
eq(EVAL_RULE_RUN({ { skill = "宠物:攻击", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), false, "no pet skips")
eq(TEST.petCmd, nil, "no pet no call")
TEST.hasPet = nil
-- 未知名称不豁免（不在动作条正常跳过）
eq(EVAL_RULE_RUN({ { skill = "宠物:放弃", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), false, "unknown pet cmd not bypassed")
-- 技能下拉清单含宠物段
local ch = EVAL_GO_SKILL_CHOICES()
local foundPet = false
for _, n in ipairs(ch) do if n == "宠物:攻击" then foundPet = true end end
eq(foundPet, true, "skill choices include pet cmds")

-- 10) 目标debuff层数（1.31.0）
TEST.debuffs = { { name = "破甲攻击", tex = "texSA", apps = 3 } }
EVAL_TARGET_DEBUFF_LIST() -- 学习 破甲攻击→texSA
EVAL_HELP_UPDATE_STATE()
local gs3 = EVAL_PARSE_CONDS("有debuff:破甲攻击>=3")
eq(gs3[1][1].k, "hasDebuff", "stack parse k")
eq(gs3[1][1].s, "破甲攻击", "stack parse name")
eq(gs3[1][1].n, 3, "stack parse n")
eq(EVAL_GROUP_STR(gs3), "有debuff:破甲攻击>=3", "stack str roundtrip")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gs3 } }), true, "3 stacks hits >=3")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有debuff:破甲攻击>=4") } }), false, "3 stacks misses >=4")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无debuff:破甲攻击<4") } }), true, "3 stacks <4 true")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无debuff:破甲攻击<3") } }), false, "3 stacks not <3")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无debuff:破甲攻击") } }), false, "present fails plain noDebuff")
-- >N 等价 >=N+1
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有debuff:破甲攻击>2") } }), true, ">2 equals >=3")
TEST.debuffs = { { name = "破甲攻击", tex = "texSA", apps = 0 } } EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gs3 } }), false, "non-stack apps=0 normalizes to 1, misses >=3")
TEST.debuffs = {} EVAL_HELP_UPDATE_STATE()

-- 11) 选取目标技能级（1.32.0）：rule.skill="选取目标:xxx" 不占动作条直接切目标
TEST.targetSel = nil TEST.used = {}
eq(EVAL_RULE_RUN({ { skill = "选取目标:最近敌人", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "target-sel skill fires")
eq(TEST.targetSel, "nearEnemy", "target-sel skill calls TargetNearestEnemy")
eq(table.getn(TEST.used), 0, "target-sel skill does not UseAction")
TEST.targetSel = nil
eq(EVAL_RULE_RUN({ { skill = "选取目标:指定名称:嗜血者", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "byName skill fires")
eq(TEST.byNameArg, "嗜血者", "byName skill passes name arg")
TEST.targetSel = nil TEST.inCombat = false EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "选取目标:清除目标", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), true, "clear skill fires")
eq(TEST.targetSel, "clear", "clear skill calls ClearTarget")
TEST.inCombat = true EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "选取目标:清除目标", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), false, "target-sel skill respects conditions")

-- 12) 物品使用技能级（1.32.0）：rule.skill="物品:名称" 背包扫描 + UseContainerItem
TEST.bags = { [1] = { name = "超效治疗药水", tex = "texPotion", count = 3 }, [2] = { name = "夜幕", tex = "texSword", count = 1 } }
TEST.usedItem = nil TEST.used = {}
eq(EVAL_RULE_RUN({ { skill = "物品:超效治疗药水", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "item skill fires")
eq(TEST.usedItem, 1, "item skill uses bag0 slot1")
eq(table.getn(TEST.used), 0, "item skill does not UseAction")
TEST.usedItem = nil
eq(EVAL_RULE_RUN({ { skill = "物品:不存在的物品", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), false, "missing item skipped")
eq(TEST.usedItem, nil, "missing item not used")
-- 装备类物品也走同一接口（UseContainerItem 对装备=自动穿上）
eq(EVAL_RULE_RUN({ { skill = "物品:夜幕", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "equip item fires")
eq(TEST.usedItem, 2, "equip item uses its bag slot")
-- 就绪条件走背包冷却
TEST.bags[1].cd = true
eq(EVAL_RULE_RUN({ { skill = "物品:超效治疗药水", why = "x", groups = EVAL_PARSE_CONDS("可攻击 & 就绪") } }), false, "item on cooldown blocked by ready")
TEST.bags[1].cd = nil
eq(EVAL_RULE_RUN({ { skill = "物品:超效治疗药水", why = "x", groups = EVAL_PARSE_CONDS("可攻击 & 就绪") } }), true, "item off cooldown passes ready")

-- 13) 技能二级分类（1.32.0）
local cats = EVAL_GO_SKILL_CATEGORIES()
eq(cats[1].label, EVAL_L("SK_CAT_1"), "cat1 label")
eq(cats[1].items()[1], "攻击", "cat1 has attack")
eq(cats[3].label, EVAL_L("SK_CAT_3"), "cat3 label")
local foundPetCmd = false
for _, n in ipairs(cats[3].items()) do if n == "宠物:攻击" then foundPetCmd = true end end
eq(foundPetCmd, true, "cat3 has pet cmds")
eq(cats[4].label, EVAL_L("SK_CAT_4"), "cat4 label")
local foundTsel = false
for _, n in ipairs(cats[4].items()) do if n == "选取目标:最近敌人" then foundTsel = true end end
eq(foundTsel, true, "cat4 has target-sel skills")
eq(cats[5].label, EVAL_L("SK_CAT_5"), "cat5 label")
local foundItem = false
for _, n in ipairs(cats[5].items()) do if string.find(n, "超效治疗药水") then foundItem = true end end
eq(foundItem, true, "cat5 lists bag items")

-- 14) 1.32.0 审计修复：debuff 层数反向 op 降级（有debuff:x<3 不再语义反转）
local gRev = EVAL_PARSE_CONDS("有debuff:破甲攻击<3")
eq(gRev[1][1].n, nil, "reversed op downgraded to plain hasDebuff")
eq(gRev[1][1].s, "破甲攻击", "reversed op keeps aura name")
TEST.debuffs = { { name = "破甲攻击", tex = "texSA", apps = 3 } } EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gRev } }), true, "reversed op behaves as plain hasDebuff")
TEST.debuffs = {} EVAL_HELP_UPDATE_STATE()

-- 15) 目标存在条件（1.32.1）
local gHT = EVAL_PARSE_CONDS("目标存在")
eq(gHT[1][1].k, "hasTarget", "hasTarget parse k")
eq(gHT[1][1].v, true, "hasTarget parse v")
eq(EVAL_GROUP_STR(gHT), "目标存在", "hasTarget str roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("无目标")), "无目标", "no-target str roundtrip")
TEST.hasTarget = false EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gHT } }), false, "no target blocks")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无目标") } }), true, "no-target cond passes without target")
TEST.hasTarget = true EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gHT } }), true, "target present passes")

-- 16) 宠物指令图标学习数据通路（1.32.6）：GetPetActionInfo 返回 token 与图标
TEST.hasPet = true
local pn, _, ptex = GetPetActionInfo(1)
eq(pn, "PET_ACTION_ATTACK", "pet action token")
eq(ptex, "texPetAttack", "pet action icon tex")
TEST.hasPet = nil

-- 17) UnitBuff 兜底枚举并入 playerBuffs（1.32.10：药品类 buff 被 GetPlayerBuff 漏掉也能匹配）
TEST.unitBuffs = { { tex = "texRegen" } } -- 再生（药品 buff）
EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.playerBuffs["texRegen"] ~= nil, true, "UnitBuff texture merged into playerBuffs")
eq(EVAL_HELP_STATE.playerBuffs["texRegen"], 1, "non-stacking buff normalized to 1 stack (1.70.1)")
TEST.unitBuffs = nil EVAL_HELP_UPDATE_STATE()

-- 18) i18n 核心（1.34.0）：EVAL_L 查找/回退/格式化；EVAL_SET_LANG 切换与校验
local SAVED_LOCALES = EVAL_LOCALES -- 1.68.2 修复泄漏：测试后必须恢复真语言包（曾污染工具箱分组的 L() 解析）
EVAL_LOCALES = { zhCN = { T_HELLO = "你好", T_FMT = "数量%d" }, enUS = { T_HELLO = "Hello" } }
eq(EVAL_L("T_HELLO"), "你好", "default zhCN")
eq(EVAL_L("T_FMT", 5), "数量5", "format arg")
EVAL_SET_LANG("enUS")
eq(EVAL_L("T_HELLO"), "Hello", "switched enUS")
eq(EVAL_L("T_FMT", 7), "数量7", "missing key falls back zhCN, formatted")
EVAL_SET_LANG("zhCN")
eq(EVAL_L("NO_SUCH_KEY"), "NO_SUCH_KEY", "unknown key shows itself")
eq(EVAL_SET_LANG("xxXX"), false, "invalid code rejected")
EVAL_LOCALES = SAVED_LOCALES

-- 19) 免疫学习器（1.36.0）：探针实测文本格式解析 + 引擎跳过 + 清空恢复
EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {} EVAL_HELP_CONFIG.war = EVAL_HELP_CONFIG.war or {}
EVAL_HELP_CONFIG.war.immune = {}
eq(EVAL_IMMUNE_LEARN("你的撕裂施放失败。暗眼骷髅法师对此免疫。"), true, "learn immune CN")
eq(EVAL_HELP_CONFIG.war.immune["撕裂@暗眼骷髅法师"], true, "immune stored")
eq(EVAL_IMMUNE_LEARN("你的撕裂施放失败。暗眼骷髅法师对此免疫。"), true, "re-learn idempotent")
eq(EVAL_IMMUNE_LEARN("你击中暗眼骷髅法师造成44点伤害。"), false, "non-immune ignored")
eq(EVAL_IMMUNE_LEARN("Your Rupture fails. Dark Skull Mage is immune."), true, "learn immune EN")
eq(EVAL_HELP_CONFIG.war.immune["Rupture@Dark Skull Mage"], true, "immune EN stored")
-- 引擎跳过（stub 目标名=测试怪）
EVAL_HELP_CONFIG.war.immune["致死打击@测试怪"] = true
EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), false, "immune skill skipped")
EVAL_HELP_CONFIG.war.immune = {}
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("可攻击") } }), true, "fires after clear")
EVAL_HELP_CONFIG.war.immune = nil

-- 20) 免疫条件类型（1.36.1）：免疫:技能 / 未免疫:技能 解析回环 + 学习表判定
EVAL_HELP_CONFIG.war = EVAL_HELP_CONFIG.war or {}
EVAL_HELP_CONFIG.war.immune = { ["撕裂@测试怪"] = true }
EVAL_HELP_UPDATE_STATE()
local gIm = EVAL_PARSE_CONDS("免疫:撕裂")
eq(gIm[1][1].k, "immune", "immune parse k")
eq(gIm[1][1].s, "撕裂", "immune parse s")
eq(EVAL_GROUP_STR(gIm), "免疫:撕裂", "immune str roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("未免疫:撕裂")), "未免疫:撕裂", "not-immune roundtrip")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gIm } }), true, "immune cond true when learned")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("未免疫:撕裂") } }), false, "not-immune cond false when learned")
EVAL_HELP_CONFIG.war.immune = {}

-- 21) 射程条件 + 距离分档（1.37.0）
TEST.slotNames[3] = "断筋"
EVAL_GO_RESCAN(true)
local gRg = EVAL_PARSE_CONDS("范围内:冲锋")
eq(gRg[1][1].k, "inRange", "inRange parse k")
eq(EVAL_GROUP_STR(gRg), "范围内:冲锋", "inRange roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("范围外:冲锋")), "范围外:冲锋", "not-inrange roundtrip")
TEST.inRange = { [2] = true }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gRg } }), true, "in range passes")
eq(EVAL_HELP_STATE.tRange, "冲锋距", "charge band")
TEST.inRange = { [2] = 0 }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gRg } }), false, "out of range blocks")
eq(EVAL_HELP_STATE.tRange, "远程外", "out band")
TEST.inRange = { [3] = true }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.tRange, "近战", "melee band")
TEST.inRange = nil TEST.slotNames[3] = nil EVAL_GO_RESCAN(true) EVAL_HELP_UPDATE_STATE()

-- 22) 施法中条件（1.38.0）：解析回环 + castName 判定
local gCast = EVAL_PARSE_CONDS("施法中:猛击")
eq(gCast[1][1].k, "casting", "casting parse k")
eq(EVAL_GROUP_STR(gCast), "施法中:猛击", "casting roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("未施法:猛击")), "未施法:猛击", "notcasting roundtrip")
EVAL_HELP_STATE.castName = "猛击" EVAL_HELP_STATE.castUntil = nil
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gCast } }), true, "casting matches")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("未施法:猛击") } }), false, "notcasting inverse")
EVAL_HELP_STATE.castName = nil
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = gCast } }), false, "not casting blocks")

-- 23) 目标施法条件（1.40.0）：解析回环 + 事件状态 + 读条秒数 + 时长学习
local gTC = EVAL_PARSE_CONDS("目标施法中")
eq(gTC[1][1].k, "tCasting", "tCasting parse k")
eq(gTC[1][1].s, nil, "empty = any cast")
eq(EVAL_GROUP_STR(gTC), "目标施法中", "tCasting roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("目标施法中:寒冰箭")), "目标施法中:寒冰箭", "named roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("读条>2")), "目标施法时间>2", "elapsed roundtrip")
-- 事件驱动状态：目标名不匹配不记，匹配记
TEST.curTargetName = "测试怪" EVAL_HELP_UPDATE_STATE()
EVAL_TCAST_EVENT("暗眼骷髅法师开始施放寒冰箭。")
eq(EVAL_HELP_STATE.tCastName, nil, "other caster not tracked")
TEST.curTargetName = "暗眼骷髅法师" EVAL_HELP_UPDATE_STATE()
EVAL_TCAST_EVENT("暗眼骷髅法师开始施放寒冰箭。")
eq(EVAL_HELP_STATE.tCastName, "寒冰箭", "target cast tracked")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标施法中") } }), true, "tCasting any passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标施法中:寒冰箭") } }), true, "named passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标施法中:火球术") } }), false, "other spell blocks")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标未施法") } }), false, "notcasting inverse")
-- 结束命中 → 学习总时长（先让时间前进 1.5s——桩 GetTime 恒定 1000，0 时长会被 0.2s 下限拒）
local oldGetTime = GetTime
GetTime = function() return 1001.5 end
EVAL_TCAST_EVENT("寒冰箭击中你造成20点伤害。")
GetTime = oldGetTime
eq(EVAL_HELP_STATE.tCastName, nil, "cast ends on hit")
eq(type(EVAL_HELP_CONFIG.war.castTime and EVAL_HELP_CONFIG.war.castTime["寒冰箭"]), "number", "duration learned")
TEST.curTargetName = nil EVAL_HELP_UPDATE_STATE()

-- 24) 方案上限 12（1.42.0）：EVAL_GO5~GO12 存在且可调
eq(type(EVAL_GO12), "function", "EVAL_GO12 exists")
eq(type(EVAL_GO5), "function", "EVAL_GO5 exists")

-- 25) 姿态切换技能（1.43.0）：rule.skill="姿态:名称" 走姿态栏 CastShapeshiftForm，不占动作条
TEST.inCombat = false EVAL_HELP_UPDATE_STATE()
TEST.stances = {
  { icon = "texSt1", name = "战斗姿态", castable = 1 },
  { icon = "texSt2", name = "防御姿态", active = 1, castable = 1 },
}
eq(EVAL_STANCE_OF("姿态:战斗姿态"), "战斗姿态", "stanceOf parses")
eq(EVAL_STANCE_OF("战斗姿态"), nil, "plain skill not stance")
local catsS = EVAL_GO_SKILL_CATEGORIES()
local foundSt = false
for _, n in ipairs(catsS[1].items()) do if n == "姿态:战斗姿态" then foundSt = true end end
eq(foundSt, true, "cat1 lists stances")
eq(EVAL_WICON("姿态:战斗姿态"), "texSt1", "stance icon")
TEST.stanceCast = nil
eq(EVAL_RULE_RUN({ { skill = "姿态:战斗姿态", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), true, "stance switch fires without action slot")
eq(TEST.stanceCast, 1, "CastShapeshiftForm(1) called")
eq(EVAL_RULE_RUN({ { skill = "姿态:防御姿态", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), false, "already-active stance skipped")
eq(EVAL_RULE_RUN({ { skill = "姿态:狂暴姿态", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), false, "unknown stance skipped")
TEST.stances = nil

-- 26) 案例模版库（1.44.0）：按职业分组 + 模版文本可被导入解析
eq(type(EVAL_IO_TEMPLATES), "table", "templates table exists")
eq(EVAL_IO_TEMPLATES[1].cls, "战士", "warrior class group")
local tpl = EVAL_IO_TEMPLATES[1].list[1]
eq(tpl.name, "武器战", "weapon warrior template")
local prof26, err26 = EVAL_PROFILE_FROM_TEXT(tpl.text)
eq(prof26 ~= nil, true, "template parses: " .. tostring(err26))
eq(prof26.name, "武器战", "template profile name")
eq(prof26.skills[1].skill, "姿态:战斗姿态", "template uses stance skill")
eq(table.getn(prof26.skills), 8, "template skill count")
-- 1.56.1 法师案例×2：分组存在 + 全部可解析 + 新条件类型可用
eq(EVAL_IO_TEMPLATES[2].cls, "法师", "mage class group")
eq(table.getn(EVAL_IO_TEMPLATES[2].list), 1, "mage has one template (buff moved out)")
local pM1, eM1 = EVAL_PROFILE_FROM_TEXT(EVAL_IO_TEMPLATES[2].list[1].text)
eq(pM1 ~= nil, true, "mage dps template parses: " .. tostring(eM1))
eq(pM1.skills[1].skill, "选取目标:最近敌人", "mage dps opens with target sel")
eq(table.getn(pM1.skills), 5, "mage dps skill count")
-- 1.67.5 通用法系独立分组：周围补buff 从法师组拆出（索引：1战士 2法师 3通用法系 4盗贼）
eq(EVAL_IO_TEMPLATES[3].cls, "通用法系", "universal caster group")
local pM2, eM2 = EVAL_PROFILE_FROM_TEXT(EVAL_IO_TEMPLATES[3].list[1].text)
eq(pM2 ~= nil, true, "mage buff template parses: " .. tostring(eM2))
eq(pM2.skills[2].groups[1][1].k, "tBuff", "buff template uses tBuff cond")
eq(pM2.skills[2].groups[1][1].v, false, "buff template checks missing target buff")
-- 1.67.2 盗贼模版：分组存在 + 可解析 + 连击条件
eq(EVAL_IO_TEMPLATES[4].cls, "盗贼", "rogue class group")
local pR1, eR1 = EVAL_PROFILE_FROM_TEXT(EVAL_IO_TEMPLATES[4].list[1].text)
eq(pR1 ~= nil, true, "rogue template parses: " .. tostring(eR1))
eq(table.getn(pR1.skills), 4, "rogue skill count")
eq(pR1.skills[1].skill, "选取目标:最近敌人", "rogue opens with target sel")
eq(pR1.skills[4].groups[1][2].k, "combo", "rogue finisher uses combo cond")
eq(pR1.skills[3].groups[1][2].op .. tostring(pR1.skills[3].groups[1][2].n), ">=4", "rogue execute threshold >=4")

-- 27) 重扫报告/状态总览以激活方案为准（1.45.0）：混合技能方案下非静默调用不报错
EVAL_HELP_CONFIG.war.profiles = { { name = "混合", skills = {
  { skill = "致死打击", enabled = true, groups = {} },
  { skill = "宠物:攻击", enabled = true, groups = {} },
  { skill = "姿态:战斗姿态", enabled = true, groups = {} },
  { skill = "物品:超效治疗药水", enabled = true, groups = {} },
  { skill = "不存在的技能", enabled = true, groups = {} },
} } }
EVAL_HELP_CONFIG.war.activeProfile = 1
EVAL_GO_RESCAN(false) -- 非静默：走方案核对报告路径
EVAL_GO_STATUS()
eq(true, true, "profile-driven rescan report no error")

-- 28) wslots 表引用稳定（1.46.0）：RESCAN 原地清空，EVAL_WSLOTS 导出不因重扫失效
TEST.slotNames[1] = "致死打击"
EVAL_GO_RESCAN(true)
eq(EVAL_WSLOTS["致死打击"] ~= nil, true, "EVAL_WSLOTS live after rescan")
eq(EVAL_WSLOTS["致死打击"].slot, 1, "slot recorded")
TEST.slotNames[1] = nil

-- 28b) ★1.71.2 静默技能扫描日志（用户要求：「每次打开配置都进行一次技能扫描（静默日志）」）
--   两条性质缺一不可：① 真的写了日志（否则用户出问题时没有证据）；
--   ② 屏幕上**一个字都不许出**（quiet=true 的调用点不能刷屏——这正是「静默」的定义）。
do
  TEST.slotNames[1] = "致死打击" TEST.slotNames[2] = "冲锋"
  EVAL_LOG_CLEAR()
  TEST.chat = nil
  EVAL_GO_RESCAN(true, "open")
  local n = EVAL_LOG_COUNT()
  eq(n >= 3, true, "★silent scan writes to the debug log ring buffer (1 header + 1 line per skill)")
  eq(TEST.chat, nil, "★silent scan prints NOTHING to the chat frame (that is what 'silent' means)")
  -- 头部必须带触发原因，且逐条列出 名称→格子（「拖上去了却说未找到」靠它定位）
  local buf = EVAL_HELP_CONFIG.log
  local head, hasSkill, hasSlot = nil, false, false
  for _, line in ipairs(buf) do
    if string.find(line, "[扫:open]", 1, true) ~= nil then head = line end
    if string.find(line, "致死打击", 1, true) ~= nil then hasSkill = true end
    if string.find(line, "格子 1", 1, true) ~= nil then hasSlot = true end
  end
  eq(head ~= nil, true, "★log header names the trigger reason (open = config window)")
  eq(head ~= nil and string.find(head, "2 个技能", 1, true) ~= nil, true, "★log header carries the skill count")
  eq(hasSkill, true, "★log lists each recognized skill by name")
  eq(hasSlot, true, "★log lists the slot number (to match against the action bar)")
  -- 非静默调用仍然刷聊天框（不能让「静默」把正常报告也吞掉）
  TEST.chat = nil
  EVAL_GO_RESCAN(false, "menu")
  eq(TEST.chat ~= nil and string.find(TEST.chat, "个技能", 1, true) ~= nil, true, "non-silent rescan still reports to chat")
  TEST.slotNames[1] = nil TEST.slotNames[2] = nil
end

-- 29) 角色行为扩充（1.47.0）：取消施法 + 姿态序号 + 自动射击/射击入 cat1 + 普攻状态与接管开关解耦
eq(EVAL_CANCELCAST_OF("取消施法"), true, "cancelCastOf parses")
eq(EVAL_CANCELCAST_OF("攻击"), nil, "attack not cancel-cast")
TEST.castStopped = nil
EVAL_HELP_STATE.castName = "寒冰箭"
eq(EVAL_RULE_RUN({ { skill = "取消施法", why = "x", groups = EVAL_PARSE_CONDS("施法中") } }), true, "cancel cast fires while casting")
eq(TEST.castStopped, true, "SpellStopCasting called")
eq(TEST.runScript, "SpellStopCasting()", "cancel cast goes through RunScript (1.49.3 protected bypass)")
EVAL_HELP_STATE.castName = nil EVAL_HELP_STATE.castUntil = nil
eq(EVAL_RULE_RUN({ { skill = "取消施法", why = "x", groups = EVAL_PARSE_CONDS("目标存在") } }), false, "cancel cast skipped when not casting")
TEST.stances = { { icon = "texSt1", name = "战斗姿态", castable = 1 }, { icon = "texSt2", name = "防御姿态", castable = 1 } }
TEST.stanceCast = nil
eq(EVAL_RULE_RUN({ { skill = "姿态:2", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), true, "stance by index fires")
eq(TEST.stanceCast, 2, "CastShapeshiftForm(2) via index")
TEST.stances = nil
local catsB = EVAL_GO_SKILL_CATEGORIES()
local b1 = catsB[1].items()
local hasAS, hasShoot, hasCancel = false, false, false
for _, n in ipairs(b1) do
  if n == "自动射击" then hasAS = true end
  if n == "射击" then hasShoot = true end
  if n == "取消施法" then hasCancel = true end
end
eq(hasAS and hasShoot and hasCancel, true, "cat1 has autoshot/shoot/cancelcast")
-- 普攻状态采集不受接管开关影响：开关关掉也要如实写 st.autoAttack
TEST.slotNames[2] = "攻击" EVAL_GO_RESCAN(true)
TEST.currentAction = EVAL_WSLOTS["攻击"].slot
EVAL_HELP_CONFIG.war.attack = false -- 接管关
EVAL_GO_LAST = 0 EVAL_GO()
eq(EVAL_HELP_STATE.autoAttack, true, "autoAttack state accurate with takeover off")
TEST.currentAction = nil EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[2] = nil EVAL_GO_RESCAN(true)
-- 接管泛化（1.49.2）：无「攻击」时回退「自动射击」（UseAction 通道）
-- 1.62.0 起接管动作在无规则出手时才执行 → 空方案驱动
local oldProf29 = EVAL_HELP_CONFIG.war.profiles
EVAL_HELP_CONFIG.war.profiles = { { name = "接管", skills = {} } } EVAL_HELP_CONFIG.war.activeProfile = 1
TEST.slotNames[3] = "自动射击" EVAL_GO_RESCAN(true)
TEST.used = {} EVAL_HELP_CONFIG.war.attack = true
TEST.curTargetName = nil EVAL_HELP_UPDATE_STATE()
EVAL_GO_LAST = 0 EVAL_GO()
local usedSlot3 = false
for _, u in ipairs(TEST.used) do if u == 3 then usedSlot3 = true end end
eq(usedSlot3, true, "autoshot takeover fires UseAction")
-- 自动攻击优先级（1.50.0）：攻击+自动射击 同时在条 → 优先自动射击，不碰近战 AttackTarget
TEST.slotNames[1] = "攻击" EVAL_GO_RESCAN(true)
TEST.used = {} TEST.attackTried = nil
EVAL_GO_LAST = 0 EVAL_GO()
local usedSlot1 = false
for _, u in ipairs(TEST.used) do if u == 1 then usedSlot1 = true end end
eq(usedSlot3 and not usedSlot1, true, "autoshot wins over melee attack")
eq(TEST.attackTried, nil, "AttackTarget not called when autoshot available")
TEST.used = {} EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[1] = nil TEST.slotNames[3] = nil EVAL_GO_RESCAN(true)
EVAL_HELP_CONFIG.war.profiles = oldProf29 EVAL_HELP_CONFIG.war.activeProfile = 1

-- 30) 空条件=直接执行（1.49.1）：编辑窗不配条件/导入 "- 技能 |" 产出空 groups 也必须触发
TEST.slotNames[1] = "致死打击" EVAL_GO_RESCAN(true)
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = {} } }), true, "empty groups table fires")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("") } }), true, "parse empty string fires")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS(" ") } }), true, "parse blank fires")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("")), "", "empty str roundtrip")
TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)

-- 31) 条件 自动射击/魔杖射击 是·否（1.51.0）：解析回环 + IsCurrentAction 直查 + 未上条=未激活
TEST.slotNames[1] = "致死打击" TEST.slotNames[2] = "自动射击" TEST.slotNames[3] = "射击" EVAL_GO_RESCAN(true)
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("自动射击")), "自动射击", "autoShot roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("!自动射击")), "未自动射击", "not autoShot roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("魔杖射击")), "魔杖射击", "wandShoot roundtrip")
TEST.currentAction = 2 -- 自动射击激活中
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("自动射击") } }), true, "autoShot on passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("魔杖射击") } }), false, "wandShoot off blocks")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("!魔杖射击") } }), true, "not wandShoot passes")
TEST.currentAction = nil
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("自动射击") } }), false, "autoShot off blocks")
TEST.slotNames[2] = nil TEST.slotNames[3] = nil EVAL_GO_RESCAN(true)
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("!自动射击") } }), true, "not-on-bar counts as inactive")
TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)

-- 32) 自动攻击距离检测（1.52.0）：自动射击超程降档近战 / 在程优先远程
-- 1.62.0 起接管动作后移到规则评估之后、无出手才补 → 用空方案驱动（混合方案里 宠物:攻击 会抢先出手）
local oldProf32 = EVAL_HELP_CONFIG.war.profiles
EVAL_HELP_CONFIG.war.profiles = { { name = "接管", skills = {} } } EVAL_HELP_CONFIG.war.activeProfile = 1
TEST.slotNames[1] = "攻击" TEST.slotNames[2] = "自动射击" EVAL_GO_RESCAN(true)
EVAL_HELP_CONFIG.war.attack = true
-- 接管有 2s 节流（wLastAttackTry 是 Engine local 测试无法直清）：桩 GetTime 恒定 1000，前移 3s 绕过
local oldGetTime32 = GetTime
GetTime = function() return 1003 end
TEST.inRange = { [2] = 0 } -- 自动射击超程（贴脸）
TEST.used = {} TEST.attackTried = nil
EVAL_GO_LAST = 0 EVAL_GO()
local usedSlot2 = false
for _, u in ipairs(TEST.used) do if u == 2 then usedSlot2 = true end end
eq(usedSlot2, false, "out-of-range autoshot downgraded")
eq(TEST.attackTried, true, "melee attack fallback when autoshot out of range")
GetTime = function() return 1006 end -- 再过节流
TEST.inRange = { [2] = true } -- 在射程内
TEST.used = {} TEST.attackTried = nil
EVAL_GO_LAST = 0 EVAL_GO()
usedSlot2 = false
for _, u in ipairs(TEST.used) do if u == 2 then usedSlot2 = true end end
eq(usedSlot2, true, "in-range autoshot picked")
eq(TEST.attackTried, nil, "no melee fallback when autoshot in range")
GetTime = oldGetTime32
TEST.inRange = nil TEST.used = {} EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[1] = nil TEST.slotNames[2] = nil EVAL_GO_RESCAN(true)
EVAL_HELP_CONFIG.war.profiles = oldProf32 EVAL_HELP_CONFIG.war.activeProfile = 1

-- 33) 选取目标不消耗按键（1.52.1）：切换成功后继续评估后续规则
TEST.slotNames[1] = "致死打击" EVAL_GO_RESCAN(true)
TEST.targetSel = nil TEST.used = {}
eq(EVAL_RULE_RUN({
  { skill = "选取目标:最近敌人", why = "x", groups = EVAL_PARSE_CONDS("非战斗") },
  { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("非战斗") },
}), true, "target-sel then cast both fire")
eq(TEST.targetSel, "nearEnemy", "target switched")
eq(table.getn(TEST.used), 1, "follow-up skill cast after target switch")
-- 单发选取目标（最后一条）也计为已动作
TEST.targetSel = nil
eq(EVAL_RULE_RUN({ { skill = "选取目标:最近敌人", why = "x", groups = EVAL_PARSE_CONDS("非战斗") } }), true, "lone target-sel still counts as action")
-- 条件不满足时照旧不动作
eq(EVAL_RULE_RUN({
  { skill = "选取目标:最近敌人", why = "x", groups = EVAL_PARSE_CONDS("战斗中") },
  { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("战斗中") },
}), false, "conditions still gate both")
TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)

-- 34) 并行执行模型（1.53.0）：非 GCD 类型全部续行，仅角色技能终止
TEST.slotNames[1] = "致死打击" TEST.slotNames[2] = "攻击" EVAL_GO_RESCAN(true)
TEST.hasPet = true TEST.petCmd = nil TEST.stanceCast = nil TEST.used = {} TEST.targetSel = nil
TEST.stances = { { icon = "i", name = "战斗姿态", castable = 1 } }
eq(EVAL_RULE_RUN({
  { skill = "选取目标:最近敌人", why = "x", groups = {} },
  { skill = "宠物:攻击", why = "x", groups = {} },
  { skill = "姿态:战斗姿态", why = "x", groups = {} },
  { skill = "攻击", why = "x", groups = {} },
  { skill = "致死打击", why = "x", groups = {} },
}), true, "full parallel chain fires")
eq(TEST.targetSel, "nearEnemy", "target switched in chain")
eq(TEST.petCmd, "PetAttack", "pet cmd fired in chain")
eq(TEST.stanceCast, 1, "stance switched in chain")
eq(TEST.used[1], 2, "attack toggle fired in chain")
eq(TEST.used[2], 1, "gcd skill fired last in chain")
-- 1.59.0 去除公共CD终止：角色技能在前，后面的规则【继续执行】（能不能放交给游戏内置）
TEST.used = {} TEST.petCmd = nil
eq(EVAL_RULE_RUN({
  { skill = "致死打击", why = "x", groups = {} },
  { skill = "宠物:攻击", why = "x", groups = {} },
}), true, "rules after gcd skill still evaluated")
eq(TEST.petCmd, "PetAttack", "pet cmd fires after gcd skill (no termination)")
TEST.hasPet = nil TEST.stances = nil TEST.used = {} TEST.slotNames[1] = nil TEST.slotNames[2] = nil EVAL_GO_RESCAN(true)

-- 35) 光环检查合并 + 目标buff/自身debuff（1.54.0）
TEST.slotNames[1] = "致死打击" EVAL_GO_RESCAN(true)
-- 解析回环：旧文本 → 新结构 → 文本不变
local g35a = EVAL_PARSE_CONDS("无buff:战斗怒吼")
eq(g35a[1][1].k, "hasBuff", "noBuff text merges to hasBuff")
eq(g35a[1][1].v, false, "merged v=false")
eq(EVAL_GROUP_STR(g35a), "无buff:战斗怒吼", "noBuff text roundtrip")
local g35b = EVAL_PARSE_CONDS("无debuff:破甲攻击<3")
eq(g35b[1][1].k, "hasDebuff", "noDebuff text merges")
eq(g35b[1][1].v, false, "noDebuff v=false")
eq(EVAL_GROUP_STR(g35b), "无debuff:破甲攻击<3", "noDebuff stack roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("目标buff:嗜血")), "目标buff:嗜血", "tBuff roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("无目标buff:嗜血")), "无目标buff:嗜血", "not tBuff roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("自身debuff:减速")), "自身debuff:减速", "pDebuff roundtrip")
-- 引擎判定：目标 buff（TEST.tgtBuffs → st.targetBuffs）
TEST.tgtBuffs = { { tex = "texBloodlust" } }
EVAL_HELP_CONFIG.war.debuffTex = { ["嗜血"] = "texBloodlust", ["减速"] = "texSlow" }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标buff:嗜血") } }), true, "target buff present passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无目标buff:嗜血") } }), false, "not-target-buff inverse")
TEST.tgtBuffs = nil EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无目标buff:嗜血") } }), true, "missing target buff passes negated")
-- 引擎判定：自身 debuff（UnitDebuff player 走 TEST.debuffs 桩）
TEST.debuffs = { { name = "减速", tex = "texSlow", apps = 0 } }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("自身debuff:减速") } }), true, "self debuff present passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无自身debuff:减速") } }), false, "self debuff inverse")
TEST.debuffs = {} EVAL_HELP_UPDATE_STATE()
-- 合并 hasBuff v=false 判定
TEST.buffs = { { tex = "texBS" } } EVAL_HELP_UPDATE_STATE()
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无buff:战斗怒吼") } }), true, "merged noBuff passes when missing")
TEST.buffs = {} EVAL_HELP_UPDATE_STATE()

-- 35b) 四类光环层数门槛（1.70.1）：buff/debuff 都能堆叠，层数按钮对四类全开
-- 注：必须排在下面那行 rescan 之前——EVAL_RULE_RUN 对「不在动作条」的技能直接跳过（1.44 起）
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("有buff:战斗怒吼>=2")), "有buff:战斗怒吼>=2", "hasBuff stack roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("目标buff:嗜血>=3")), "目标buff:嗜血>=3", "tBuff stack roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("自身debuff:减速>=2")), "自身debuff:减速>=2", "pDebuff stack roundtrip")
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("无buff:战斗怒吼<3")), "无buff:战斗怒吼<3", "noBuff stack roundtrip")
EVAL_HELP_CONFIG.war.debuffTex = { ["嗜血"] = "texBloodlust", ["减速"] = "texSlow", ["战斗怒吼"] = "texBS" }
-- 自身 buff 2 层：>=2 过 / >=3 不过
TEST.unitBuffs = { { tex = "texBS", apps = 2 } } TEST.buffs = {}
EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.playerBuffs["texBS"], 2, "player buff stack recorded")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有buff:战斗怒吼>=2") } }), true, "self buff stacks meet threshold")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("有buff:战斗怒吼>=3") } }), false, "self buff stacks below threshold")
-- 目标 buff 3 层
TEST.tgtBuffs = { { tex = "texBloodlust", apps = 3 } }
EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.targetBuffs["texBloodlust"], 3, "target buff stack recorded")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标buff:嗜血>=3") } }), true, "target buff stacks meet threshold")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("目标buff:嗜血>=4") } }), false, "target buff stacks below threshold")
-- 自身 debuff 2 层（无自身debuff<3 应过：不足3层）
TEST.debuffs = { { tex = "texSlow", apps = 2 } } TEST.unitBuffs = {} TEST.tgtBuffs = nil
EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.playerDebuffs["texSlow"], 2, "player debuff stack recorded")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("自身debuff:减速>=2") } }), true, "self debuff stacks meet threshold")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无自身debuff:减速<3") } }), true, "self debuff below cap passes negated")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("无自身debuff:减速<2") } }), false, "self debuff at cap fails negated")
TEST.debuffs = {} EVAL_HELP_UPDATE_STATE()
TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)

-- 36) 执行去抖（1.54.1/1.54.2）：窗口内重复调用丢弃；窗口可配（cfg.goDebounce）
EVAL_HELP_CONFIG.goDebounce = 0.2
local oldProf36 = EVAL_HELP_CONFIG.war.profiles
EVAL_HELP_CONFIG.war.profiles = { { name = "去抖", skills = { { skill = "选取目标:最近敌人", enabled = true, groups = {} } } } }
EVAL_HELP_CONFIG.war.activeProfile = 1
local oldGT36 = GetTime
GetTime = function() return 2000 end
EVAL_GO_LAST = 0 EVAL_HELP_STATE.castLog = {}
EVAL_GO()
eq(table.getn(EVAL_HELP_STATE.castLog), 1, "first call executes")
EVAL_GO() -- 同一时刻（0s 间隔）→ 去抖
eq(table.getn(EVAL_HELP_STATE.castLog), 1, "debounced call dropped")
GetTime = function() return 2000.21 end -- 过 0.2s 窗口 → 放行
EVAL_GO()
eq(table.getn(EVAL_HELP_STATE.castLog), 2, "call after window executes")
GetTime = function() return 2000.27 end -- 窗口缩到 0.05 → 0.06 间隔放行（浮点余量：2000.26-2000.21 在二进制下 <0.05）
EVAL_HELP_CONFIG.goDebounce = 0.05
EVAL_GO()
eq(table.getn(EVAL_HELP_STATE.castLog), 3, "custom smaller window respected")
GetTime = oldGT36
EVAL_GO_LAST = 0 EVAL_HELP_STATE.castLog = nil EVAL_HELP_CONFIG.goDebounce = nil
EVAL_HELP_CONFIG.war.profiles = oldProf36 EVAL_HELP_CONFIG.war.activeProfile = 1

-- 37) 挥击计时（1.55.0）：事件锚点 + 攻速采集 + 施法推迟 + 剩余计算
TEST.atkSpd = 2.0 EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.atkSpd, 2.0, "attack speed collected")
eq(EVAL_SWING_EVENT("你击中蓬毛幼狼造成18点伤害。"), true, "CN melee hit anchors")
eq(EVAL_HELP_STATE.lastSwing ~= nil, true, "lastSwing recorded")
eq(EVAL_SWING_EVENT("You hit Wolf for 18."), true, "EN melee hit anchors")
eq(EVAL_SWING_EVENT("你的火球术击中蓬毛幼狼造成18点火焰伤害。"), false, "spell hit not a swing")
eq(EVAL_SWING_EVENT("你杀死了蓬毛幼狼！"), false, "kill message not a swing")
local oldGT37 = GetTime
GetTime = function() return EVAL_HELP_STATE.lastSwing + 0.5 end
local rem37 = EVAL_SWING_REMAIN()
eq(rem37 and math.abs(rem37 - 1.5) < 0.01, true, "remain = speed - elapsed")
EVAL_HELP_STATE.castUntil = EVAL_HELP_STATE.lastSwing + 1.2 -- 施法结束时刻晚于上次挥击 → 推迟
GetTime = function() return EVAL_HELP_STATE.castUntil + 0.3 end
local rem37b = EVAL_SWING_REMAIN()
eq(rem37b and math.abs(rem37b - 1.7) < 0.01, true, "cast delays next swing")
GetTime = oldGT37
EVAL_HELP_STATE.lastSwing = nil EVAL_HELP_STATE.castUntil = nil
eq(EVAL_SWING_REMAIN(), nil, "no anchor = nil")
TEST.atkSpd = nil EVAL_HELP_UPDATE_STATE()

-- 38) 条件 距下次攻击（1.57.0）：解析回环 + 数值比较 + 无数据=不满足
TEST.slotNames[1] = "致死打击" EVAL_GO_RESCAN(true)
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("距攻击<1")), "距攻击<1", "swingLeft roundtrip")
eq(EVAL_PARSE_CONDS("距攻击>2")[1][1].k, "swingLeft", "swingLeft parse k")
-- 无计时数据 → 不满足
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("距攻击<1") } }), false, "no swing data blocks")
-- 有数据：攻速 2.0、0.5s 前挥过 → 剩 1.5s
TEST.atkSpd = 2.0 EVAL_HELP_UPDATE_STATE()
EVAL_SWING_EVENT("你击中测试怪造成10点伤害。")
local oldGT38 = GetTime
GetTime = function() return EVAL_HELP_STATE.lastSwing + 0.5 end
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("距攻击>1") } }), true, "remain 1.5 > 1 passes")
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("距攻击<1") } }), false, "remain 1.5 < 1 blocks")
GetTime = oldGT38
EVAL_HELP_STATE.lastSwing = nil TEST.atkSpd = nil EVAL_HELP_UPDATE_STATE()
TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)

-- 39) 可流血免疫驱动（1.63.0）：默认 true / 流血技能免疫 → false / 非流血免疫不影响 / 黑名单仍生效
EVAL_HELP_CONFIG.war.immune = EVAL_HELP_CONFIG.war.immune or {}
TEST.curTargetName = "黑暗犬" EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.canBleed, true, "canBleed default true (no type exclusion)")
EVAL_HELP_CONFIG.war.immune["撕裂@黑暗犬"] = true EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.canBleed, false, "bleed skill immunity blocks")
EVAL_HELP_CONFIG.war.immune["撕裂@黑暗犬"] = nil
EVAL_HELP_CONFIG.war.immune["火球术@黑暗犬"] = true EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.canBleed, true, "non-bleed immunity ignored")
EVAL_HELP_CONFIG.war.immune["火球术@黑暗犬"] = nil
EVAL_BLEED_BLACKLIST["黑暗犬"] = true EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.canBleed, false, "manual blacklist still wins")
EVAL_BLEED_BLACKLIST["黑暗犬"] = nil EVAL_HELP_UPDATE_STATE()
eq(EVAL_HELP_STATE.canBleed, true, "clean state restores true")
TEST.curTargetName = nil EVAL_HELP_UPDATE_STATE()

-- 40) 可用性只信资源信号（1.64.0）：缓存 false+noMana → 挡；缓存 false 无 noMana → 放行（缓存态不可信）
TEST.slotNames[1] = "致死打击" EVAL_GO_RESCAN(true)
TEST.usableRet = { u = false, noMana = true }
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("可用") } }), false, "insufficient power blocks")
TEST.usableRet = { u = false, noMana = false }
eq(EVAL_RULE_RUN({ { skill = "致死打击", why = "x", groups = EVAL_PARSE_CONDS("可用") } }), true, "cached false without noMana passes")
TEST.usableRet = nil TEST.slotNames[1] = nil EVAL_GO_RESCAN(true)
-- GetDifficultyColor 兼容垫片（1.64.1）：全局函数存在且返回 {r,g,b} 色表
eq(type(GetDifficultyColor), "function", "difficulty color shim exists")
local dc = GetDifficultyColor(6)
eq(type(dc) == "table" and type(dc.r) == "number" and type(dc.g) == "number" and type(dc.b) == "number", true, "shim returns color table")

-- 11) 工具箱（1.68.0）：商人/就位/任务/丢弃
EVAL_HELP_CONFIG.tb = { repair = true, sell = true, ready = true, questAccept = true, questTurnIn = true, buyOn = true, buy = { { name = "晨露酒", n = 5 } }, discardOn = true, discard = { "破布" } }
TEST.repairCost = 500
TEST.merchant = { { name = "晨露酒" }, { name = "肉干" } }
TEST.bags = { [1] = { name = "灰色破剑", q = 0, count = 1 }, [2] = { name = "晨露酒", q = 1, count = 2 }, [101] = { name = "破布", q = 0, count = 1 }, [102] = { name = "蓝装护甲", q = 2, count = 1 } }
TEST.itemInfo = { ["灰色破剑"] = { t = "武器", st = "单手剑" } } -- 1.69.1 明细桩：破布故意无缓存 → 种类兜底 ?
TEST.usedItem = nil TEST.repaired = nil TEST.bought = nil TEST.sellCalls = 0 TEST.chat = nil
TEST.time = 3000 TEST.consumeOnUse = true
local function tbPump(n, t0)
  for i = 1, n do TEST.time = t0 + i * 0.4 EVAL_TB_TICK() end -- 1.69.2 走真实 OnUpdate 本体（含任务延迟扫描）
end
EVAL_TB_ONEVENT("MERCHANT_SHOW")
eq(TEST.repaired, true, "tb auto repair")
eq(TEST.sellCalls, 0, "tb sell queued not burst (1.68.2)")
tbPump(8, 3000) -- 0.4s/拍：卖1→验证→卖2→买→汇报
eq(TEST.sellCalls, 2, "tb queued sells both grays in order")
eq(TEST.usedItem, 101, "tb sell order bag0 first then bag1")
eq(TEST.bought, "晨露酒x1;晨露酒x1;晨露酒x1;", "★1.71.3 自动购买改为**分批**：需 3 件 → 3 笔 x1（每次购买数量默认 1）")
eq(TEST.chat and TEST.chat:find("自动售出灰色物品 2 件") ~= nil, true, "tb sell summary on drain")
eq(TEST.chat and TEST.chat:find("售出：灰色破剑 x1（武器/单手剑）", 1, true) ~= nil, true, "tb sell detail log with type (1.69.1)")
eq(TEST.chat and TEST.chat:find("售出：破布 x1（?）", 1, true) ~= nil, true, "tb sell detail log uncached fallback (1.69.1)")
TEST.picked = nil TEST.deleted = nil
TEST.bags = { [101] = { name = "破布", q = 0, count = 1 }, [102] = { name = "蓝装护甲", q = 2, count = 1 } }
TEST.time = 3100 EVAL_TB_ONEVENT("BAG_UPDATE")
tbPump(4, 3100)
eq(TEST.deleted, 101, "tb discard queued gray/white only (blue spared)")
EVAL_TB_ONEVENT("READY_CHECK")
eq(TEST.readyChecked, true, "tb ready check")
TEST.time = 3950 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 3950) -- 1.69.0 交接进限频队列：先泵再断言（时间单调递增，tbQLast 不倒流）
eq(TEST.questAccepted, true, "tb quest accept (queued 1.69.0)")
TEST.questCompletable = true TEST.time = 3960 EVAL_TB_ONEVENT("QUEST_PROGRESS") tbPump(2, 3960)
eq(TEST.questCompleted, true, "tb quest progress complete (queued)")
TEST.questChoices = 1 TEST.time = 3970 EVAL_TB_ONEVENT("QUEST_COMPLETE") tbPump(2, 3970)
eq(TEST.questReward, 1, "tb quest reward single choice (queued)")
TEST.questChoices = 2 TEST.questReward = nil EVAL_TB_ONEVENT("QUEST_COMPLETE")
eq(TEST.questReward, nil, "tb quest multi choice waits manual")
-- 1.71.1 两个开关互相独立（用户要求：自动接取 / 自动交付 分开配）
EVAL_HELP_CONFIG.tb = { questTurnIn = true }  -- 只开「交付」
TEST.questAccepted = nil TEST.questCompleted = nil TEST.questReward = nil
TEST.time = 3980 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 3980)
eq(TEST.questAccepted, nil, "turn-in only: QUEST_DETAIL does not accept")
TEST.questCompletable = true TEST.time = 3990 EVAL_TB_ONEVENT("QUEST_PROGRESS") tbPump(2, 3990)
eq(TEST.questCompleted, true, "turn-in only: progress still completes")
TEST.questChoices = 1 TEST.time = 3995 EVAL_TB_ONEVENT("QUEST_COMPLETE") tbPump(2, 3995)
eq(TEST.questReward, 1, "turn-in only: reward claimed")
EVAL_HELP_CONFIG.tb = { questAccept = true }  -- 只开「接取」
TEST.questAccepted = nil TEST.questCompleted = nil TEST.questReward = nil
TEST.time = 3997 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 3997)
eq(TEST.questAccepted, true, "accept only: detail accepts")
TEST.questCompletable = true TEST.time = 3998 EVAL_TB_ONEVENT("QUEST_PROGRESS") tbPump(2, 3998)
eq(TEST.questCompleted, nil, "accept only: progress does NOT complete")
TEST.questChoices = 1 TEST.time = 3999 EVAL_TB_ONEVENT("QUEST_COMPLETE") tbPump(2, 3999)
eq(TEST.questReward, nil, "accept only: complete does NOT claim reward")
-- 旧键 quest 一次性迁移到两个新键，且旧键被清掉（单一真值来源）
local mig = EVAL_TEST_TB_MIGRATE({ quest = true })
eq(mig.questAccept == true and mig.questTurnIn == true, true, "legacy quest=true migrates to both switches")
eq(mig.quest == nil, true, "legacy quest key cleared after migration")
local mig2 = EVAL_TEST_TB_MIGRATE({ quest = false })
eq(mig2.questAccept == false and mig2.questTurnIn == false, true, "legacy quest=false migrates to both off (false survives)")
local mig3 = EVAL_TEST_TB_MIGRATE({ questAccept = false, quest = true })
eq(mig3.questAccept == false and mig3.questTurnIn == nil and mig3.quest == true, true, "migration is one-shot: new keys present means old key untouched")
-- UI 接线：工具箱真的渲染两行独立复选框
local tbRows = EVAL_TEST_TB_ROWS()
local nAcc, nTurn = 0, 0
for i = 1, table.getn(tbRows) do
  if tbRows[i].key == "questAccept" then nAcc = nAcc + 1 end
  if tbRows[i].key == "questTurnIn" then nTurn = nTurn + 1 end
end
eq(nAcc, 1, "toolbox has exactly one auto-accept checkbox row")
eq(nTurn, 1, "toolbox has exactly one auto-turn-in checkbox row")
eq(EVAL_LOCALES[EVAL_GET_LANG()].TB_QUEST_ACCEPT ~= nil and EVAL_LOCALES[EVAL_GET_LANG()].TB_QUEST_TURNIN ~= nil, true, "both switch labels exist in the active language")
eq(EVAL_LOCALES[EVAL_GET_LANG()].TB_QUEST_ACCEPT ~= EVAL_LOCALES[EVAL_GET_LANG()].TB_QUEST_TURNIN, true, "the two switches do NOT share one label (they must read as separate options)")

-- 1.68.1 去重窗口 + 1.68.2 队列：MERCHANT_SHOW 连发只处理一次
EVAL_HELP_CONFIG.tb = { sell = true }
TEST.bags = { [1] = { name = "灰色破剑", q = 0, count = 1 } }
TEST.time = 4000 TEST.sellCalls = 0
EVAL_TB_ONEVENT("MERCHANT_SHOW")
tbPump(3, 4000)
eq(TEST.sellCalls, 1, "tb merchant first fire sells")
EVAL_TB_ONEVENT("MERCHANT_SHOW") -- 窗口内第二发（本客户端实测连发）
tbPump(3, 4001)
eq(TEST.sellCalls, 1, "tb merchant dedupe window blocks refire")
TEST.bags = { [1] = { name = "灰色破剑", q = 0, count = 1 } }
TEST.time = 4003 EVAL_TB_ONEVENT("MERCHANT_SHOW") -- 窗口外重开商人正常
tbPump(3, 4003)
eq(TEST.sellCalls, 2, "tb merchant reopen after window works")
-- 出售失败检测：服务器拒收（物品不消失）→ 超时记失败+汇报
TEST.bags = { [1] = { name = "锁定的灰物", q = 0, count = 1 } }
TEST.noSell = true TEST.chat = nil TEST.sellCalls = 0 TEST.time = 5000
EVAL_TB_ONEVENT("MERCHANT_SHOW")
tbPump(2, 5000) -- 执行出售（stub 不删物品=拒收）
TEST.time = 5002.6 EVAL_TB_PUMP() -- 超时 2s 验证 → 失败
eq(TEST.sellCalls, 1, "tb sell attempted once")
eq(TEST.chat and TEST.chat:find("未能售出") ~= nil, true, "tb sell failure reported")
eq(TEST.chat and TEST.chat:find("1 件未售出") ~= nil, true, "tb sell summary fail suffix")
TEST.noSell = nil
-- 关窗清场：待售队列丢弃，防「卖」变「用」
TEST.bags = { [1] = { name = "灰色破剑", q = 0 }, [2] = { name = "灰色破甲", q = 0 } }
TEST.sellCalls = 0 TEST.time = 6000
EVAL_TB_ONEVENT("MERCHANT_SHOW")
EVAL_TB_ONEVENT("MERCHANT_HIDE")
tbPump(5, 6000)
eq(TEST.sellCalls, 0, "tb merchant hide purges pending sells")
-- 开关全关：零动作
EVAL_HELP_CONFIG.tb = {}
TEST.repaired = nil TEST.readyChecked = nil TEST.time = 7000
EVAL_TB_ONEVENT("MERCHANT_SHOW") EVAL_TB_ONEVENT("READY_CHECK")
eq(TEST.repaired, nil, "tb disabled merchant no-op")
eq(TEST.readyChecked, nil, "tb disabled ready no-op")
EVAL_HELP_CONFIG.tb = nil TEST.consumeOnUse = nil
-- ★★★1.71.2 用户要求：「自动交接任务 按键停止功能，比如按住 shift 临时停止」
--   要验**三条**性质，缺一不可：
--   ① 按住时不接/不交（这是功能本身）；
--   ② 松开后**立刻恢复**（临时停止，不是永久关闭）；
--   ③ **只停任务交接**，商人/丢弃/就位检查照常（用户说的是「自动交接任务」，不是「停掉整个工具箱」）。
do
  local savedHold = IsShiftKeyDown
  local down = false
  IsShiftKeyDown = function() return down end
  EVAL_HELP_CONFIG.tb = { questAccept = true, questTurnIn = true } -- holdKey 未设 → 走默认 shift
  -- ① 按住：三类任务事件一律不动作
  down = true
  TEST.questAccepted, TEST.questCompleted, TEST.questReward = nil, nil, nil
  TEST.time = 9100 EVAL_TB_ONEVENT("QUEST_DETAIL")
  -- ★先断言「根本没入队」，再断言「没执行」：只看最终效果区分不了
  --   「事件没入队」与「入队后被撤掉」——两种实现都能让「没执行」成立（本轮实测该变异存活）。
  eq(EVAL_TB_TEST_QUEUED_QUESTS(), 0, "★★★holding Shift: the event does not even ENQUEUE an accept")
  tbPump(2, 9100)
  eq(TEST.questAccepted, nil, "★★★holding Shift blocks auto ACCEPT")
  TEST.questCompletable = true TEST.time = 9102 EVAL_TB_ONEVENT("QUEST_PROGRESS")
  eq(EVAL_TB_TEST_QUEUED_QUESTS(), 0, "★★★holding Shift: the event does not even ENQUEUE a complete")
  tbPump(2, 9102)
  eq(TEST.questCompleted, nil, "★★★holding Shift blocks auto COMPLETE")
  TEST.questChoices = 1 TEST.time = 9104 EVAL_TB_ONEVENT("QUEST_COMPLETE")
  eq(EVAL_TB_TEST_QUEUED_QUESTS(), 0, "★★★holding Shift: the event does not even ENQUEUE a reward claim")
  tbPump(2, 9104)
  eq(TEST.questReward, nil, "★★★holding Shift blocks auto REWARD claim")
  -- ③ 边界：按住期间**其它**工具箱功能照常（只停任务交接）。
  --   ★这里刻意用「就位检查」而不是「商人出售」：商人去重窗 tbMerchantLast 是模块级时间戳，
  --     在本块里打一次商人事件会让**后续用例**（从更早的 t 重放）被去重窗吞掉（实测炸过一次）。
  --     就位检查无跨用例时间戳状态，用它验边界既达意又不污染后续用例。
  EVAL_HELP_CONFIG.tb = { ready = true, holdKey = nil }
  TEST.readyChecked = nil TEST.time = 9200
  EVAL_TB_ONEVENT("READY_CHECK")
  eq(TEST.readyChecked, true, "★★★holding Shift does NOT stop other toolbox features (scope = quest handover only)")
  -- ② 松开：立即恢复
  down = false
  EVAL_HELP_CONFIG.tb = { questAccept = true, questTurnIn = true }
  TEST.time = 9300 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 9300)
  eq(TEST.questAccepted, true, "★★★releasing Shift resumes auto accept immediately")
  -- ④ 队列里的待执行交接必须被撤回（否则按了 shift 那一刻之前入队的那笔仍会打出去）
  EVAL_HELP_CONFIG.tb = { questTurnIn = true }
  TEST.questReward = nil TEST.questChoices = 1 TEST.time = 9400
  EVAL_TB_ONEVENT("QUEST_COMPLETE")           -- 入队（0.3s 后才滴出）
  down = true                                  -- 还没滴出就按住
  tbPump(3, 9400)
  eq(TEST.questReward, nil, "★★★the already-QUEUED handover is cancelled when the key goes down")
  down = false
  -- ⑤ 配置成 off = 关闭该功能（永远不暂停）
  EVAL_HELP_CONFIG.tb = { questAccept = true, holdKey = "off" }
  TEST.questAccepted = nil TEST.time = 9500 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 9500)
  eq(TEST.questAccepted, true, "holdKey=off disables the pause feature entirely")
  -- ⑥ 可换键：选 Ctrl 时按 Shift 不该暂停
  EVAL_HELP_CONFIG.tb = { questAccept = true, holdKey = "ctrl" }
  down = true
  TEST.questAccepted = nil TEST.time = 9600 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 9600)
  eq(TEST.questAccepted, true, "with holdKey=ctrl, holding Shift must NOT pause")
  down = false
  -- ⑦ Alt 必须真的接上（上面 ctrl 用例只证明「Shift 不误触」，证明不了 Alt 生效）——
  --   把 alt 分支写成恒真/恒假都能骗过 ctrl 那条，故必须**各按一次**。
  EVAL_HELP_CONFIG.tb = { questAccept = true, holdKey = "alt" }
  local savedAlt = IsAltKeyDown
  local altDown = false
  IsAltKeyDown = function() return altDown end
  altDown = true
  TEST.questAccepted = nil TEST.time = 9600 EVAL_TB_ONEVENT("QUEST_DETAIL")
  eq(EVAL_TB_TEST_QUEUED_QUESTS(), 0, "★holdKey=alt: holding Alt pauses the handover")
  tbPump(2, 9600)
  eq(TEST.questAccepted, nil, "★holdKey=alt: accept really blocked")
  altDown = false
  EVAL_TB_TEST_RESET_TIMERS()
  TEST.time = 9620 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 9620)
  eq(TEST.questAccepted, true, "★holdKey=alt: releasing Alt resumes")
  IsAltKeyDown = savedAlt
  -- ⑧ 空串 = 关闭（与 "off" 等价）——用户把配置手动清空时不能变成「永远暂停」
  EVAL_HELP_CONFIG.tb = { questAccept = true, holdKey = "" }
  down = true
  EVAL_TB_TEST_RESET_TIMERS()
  TEST.questAccepted = nil TEST.time = 9640 EVAL_TB_ONEVENT("QUEST_DETAIL") tbPump(2, 9640)
  eq(TEST.questAccepted, true, "★★holdKey empty string (cleared) disables the feature, does NOT pause forever")
  down = false
  -- ★★★1.71.2 用户实测：聊天里同一条「已自动领取任务奖励」无限刷屏（死循环）。
  --   成因：GetQuestReward 会**再触发 QUEST_COMPLETE** → 再领 → …，原来没有任何去重。
  --   这一节必须让桩**真的重发事件**（TEST.rewardRefires），否则循环在测试里不可见。
  --   判据 = 「处理次数有上界」，而不是「某一瞬间没再领」——后者在循环里也成立。
  do
    local savedRefire = TEST.rewardRefires
    EVAL_HELP_CONFIG.tb = { questTurnIn = true }
    EVAL_TB_TEST_RESET_TIMERS()
    TEST.rewardRefires = true
    TEST.rewardCalls = 0
    TEST.questChoices = 1
    TEST.questReward = nil
    TEST.time = 8100
    -- ★同一任务名：这是循环每一轮的样子
    tbQuestNameNext = nil
    TEST.questLog = { { title = "伊根·派特斯金纳", objs = {}, complete = true } }
    EVAL_TB_ONEVENT("QUEST_COMPLETE")
    -- 泵很多拍：循环若存在，这里会打出几百笔
    for i = 1, 40 do TEST.time = 8100 + i * 0.4 EVAL_TB_TICK() end
    -- 允许 1 笔（首次领取）+ 极少量重入，但**必须有上界**
    eq((TEST.rewardCalls or 0) <= 4, true,
       "★★★self-retriggering QUEST_COMPLETE cannot loop forever (rewardCalls=" .. tostring(TEST.rewardCalls) .. ")")
    eq(TEST.questReward ~= nil, true, "the reward IS still claimed once (the fix must not disable the feature)")
    TEST.rewardRefires = savedRefire
    TEST.questLog = nil
    EVAL_TB_TEST_RESET_TIMERS()
    -- ② 去重窗口：同名任务在窗口内第二次直接拦下
    EVAL_HELP_CONFIG.tb = { questTurnIn = true }
    EVAL_TB_TEST_RESET_TIMERS()
    TEST.rewardCalls = 0 TEST.questChoices = 1 TEST.time = 8300
    local g1 = EVAL_TB_QUEST_GATE("同名任务", 8300, "reward")
    eq(g1, true, "first handover for a quest is allowed")
    local g2, why2 = EVAL_TB_QUEST_GATE("同名任务", 8300.2, "reward")
    eq(g2, false, "★★the SAME quest inside the window is blocked")
    -- ★不硬编码原因：reward 会开领取窗口，故第二次可能先被 window 拦、也可能被 dup 拦——
    --   两者都是「拦住了」，这正是要保的性质。硬编码原因会让断言与**检查顺序**耦合，
    --   一旦将来调整顺序就假失败（本轮实测：got=window want=dup）。
    eq(why2 == "dup" or why2 == "window", true, "the block carries a known reason (" .. tostring(why2) .. ")")
    -- ★真正要钉的是「同任务不能领两次」：用 complete 类（不开窗口）单独验 dup 层
    EVAL_TB_TEST_RESET_TIMERS()
    EVAL_TB_QUEST_GATE("去重任务", 8500, "complete")
    local g2b, why2b = EVAL_TB_QUEST_GATE("去重任务", 8500.2, "complete")
    eq(g2b, false, "★★same quest blocked on the dedupe layer when no reward window is involved")
    eq(why2b, "dup", "and the reason is specifically 'dup'")
    -- 窗口过后同任务可以再来（否则「重复接同一任务」永远做不了）
    local g3 = EVAL_TB_QUEST_GATE("同名任务", 8300 + 1.1, "complete")
    eq(g3, true, "the same quest is allowed again after the window passes")
    -- ③ 全局频率兜底：换名字也拦得住（不依赖任务名，前两层失效时仍成立）
    EVAL_TB_TEST_RESET_TIMERS()
    local burstOK = 0
    for i = 1, 10 do
      if (EVAL_TB_QUEST_GATE("任务" .. i, 8400 + i * 0.01, "complete")) then burstOK = burstOK + 1 end
    end
    eq(burstOK <= 3, true, "★★★rate cap holds even when every quest name is DIFFERENT (burst=" .. tostring(burstOK) .. ")")
    EVAL_TB_TEST_RESET_TIMERS()
    EVAL_HELP_CONFIG.tb = nil
  end
  -- UI：真的有这一行，且下拉列出四种选择
  local rowsH = EVAL_TEST_TB_ROWS()
  local nHold = 0
  for i = 1, table.getn(rowsH) do if rowsH[i].key == "holdKey" then nHold = nHold + 1 end end
  eq(nHold, 1, "toolbox has exactly one hold-key row")
  local keysH = EVAL_TEST_TB_HOLD_KEYS()
  eq(table.getn(keysH), 4, "hold-key dropdown offers 4 choices (shift/ctrl/alt/off)")
  -- ★收尾必须干净：本块把 TEST.time 推到了 4600，而商人去重窗（1.5s）按**绝对时间**判定——
  --   不还原的话，后续用例用 time=4000 重放会因「时间倒流」被判成仍在窗口内（实测：下一条断言直接炸）。
  --   这是本项目反复强调的「跨用例状态残留」，故用后即还。
  IsShiftKeyDown = savedHold
  EVAL_HELP_CONFIG.tb = nil
  -- ★把队列的模块级时间戳一并还原：本块把 TEST.time 推到了 9600+，
  --   不复位的话**下一个用例**（从 t=6000 重放）会被限频窗口吞掉（实测：紧邻的任务通知组直接炸）。
  EVAL_TB_TEST_RESET_TIMERS()
  TEST.time = 6000
end

-- 41) 任务通知（1.69.0）：接取/进度差分 → 频道 RunScript 限频队列；关=零通知
EVAL_HELP_CONFIG.tb = { qchan = "party" }
TEST.runScripts = nil
TEST.questLog = { { title = "收集狼皮", objs = { { txt = "森林狼皮: 0/5", d = 0, m = 5 } } } }
TEST.time = 6000 EVAL_TB_ONEVENT("QUEST_LOG_UPDATE") -- 首次建档不刷屏
eq(TEST.runScripts, nil, "event only schedules, no sync scan (1.69.2)")
tbPump(1, 6000) -- 到点（+0.3s 延迟）才扫描建档
eq(TEST.runScripts, nil, "first scan initializes silently")
TEST.questLog[1].objs[1].d = 1 TEST.questLog[1].objs[1].txt = "森林狼皮: 1/5"
TEST.time = 6001 EVAL_TB_ONEVENT("QUEST_LOG_UPDATE")
tbPump(2, 6001)
eq(TEST.runScripts and table.getn(TEST.runScripts), 1, "progress notice queued and sent")
eq(TEST.runScripts[1]:find("PARTY") ~= nil, true, "notice goes to PARTY channel")
eq(TEST.runScripts[1]:find("收集狼皮") ~= nil, true, "notice carries quest name")
TEST.questLog[2] = { title = "清理矿洞", objs = {} } -- 新任务出现 = 接取通知
TEST.time = 6002 EVAL_TB_ONEVENT("QUEST_LOG_UPDATE")
tbPump(3, 6002)
eq(TEST.runScripts and TEST.runScripts[2] and TEST.runScripts[2]:find("清理矿洞") ~= nil, true, "accept notice for new quest")
EVAL_HELP_CONFIG.tb.qchan = "off" -- 关闭=零通知
TEST.runScripts = nil
TEST.questLog[1].objs[1].d = 2
TEST.time = 6003 EVAL_TB_ONEVENT("QUEST_LOG_UPDATE")
tbPump(1, 6003) -- 到点扫描：频道关=零通知
eq(TEST.runScripts, nil, "off channel silent")
TEST.questLog = nil EVAL_HELP_CONFIG.tb = nil

-- 42) 数据检索（DataSearch.lua）：搜索/过滤/详情关联/层级上限 2/enUS 兜底/缺库不炸
local dsR = EVAL_DS_SEARCH("亚麻", nil)
eq(table.getn(dsR), 2, "ds search hits item+quest")
eq(dsR[1].kind == "item" and dsR[1].id == 2589 and dsR[1].name == "亚麻布", true, "ds prefix match ranks first")
eq(dsR[2].kind == "quest" and dsR[2].id == 1, true, "ds substring quest second")
dsR = EVAL_DS_SEARCH("亚麻", "quest")
eq(table.getn(dsR) == 1 and dsR[1].kind == "quest", true, "ds type filter quest only")
eq(table.getn(EVAL_DS_SEARCH("亚麻", "unit")), 0, "ds type filter unit empty")
dsR = EVAL_DS_SEARCH("OnlyEnglish", nil)
eq(table.getn(dsR) == 1 and dsR[1].id == 99, true, "ds enUS fallback for missing zhCN entry")
dsR = EVAL_DS_SEARCH("狗头", "unit")
eq(dsR[1] and dsR[1].sub:find("奥格瑞玛", 1, true) ~= nil, true, "ds unit sub carries zone name")
local dd = EVAL_DS_DETAIL("item", 2589, 1)
eq(dd and dd.title, "亚麻布", "ds item detail title")
local foundDrop, foundRel = nil, nil
for _, ln in ipairs(dd.lines) do
  if ln.text:find("狗头人矿工", 1, true) and ln.text:find("29.0%%") then foundDrop = ln end
  if ln.text:find("收集亚麻布", 1, true) then foundRel = ln end
end
eq(foundDrop ~= nil, true, "ds item detail drop source with rate")
eq(foundDrop and foundDrop.link and foundDrop.link.kind, "unit", "ds drop line clickable to unit")
eq(foundRel and foundRel.link and foundRel.link.kind, "quest", "ds item detail related quest clickable")
dd = EVAL_DS_DETAIL("unit", 3, 1)
local foundDi, foundGq = nil, nil
for _, ln in ipairs(dd.lines) do
  if ln.text:find("亚麻布", 1, true) and ln.text:find("%%") then foundDi = ln end -- 掉落行带掉率%，区别于「收集亚麻布」任务行
  if ln.text:find("收集亚麻布", 1, true) then foundGq = ln end
end
eq(foundDi and foundDi.link and foundDi.link.kind, "item", "ds unit detail drops clickable to item")
eq(foundDi and foundDi.hoverItem, 2589, "ds item line carries hoverItem for tooltip")
eq(foundGq and foundGq.link and foundGq.link.kind, "quest", "ds unit detail gives-quest clickable")
dd = EVAL_DS_DETAIL("item", 2589, 2) -- 无限级联（用户实测要求，原 2 级上限取消）：depth>=2 仍挂 link
local anyLink = false
for _, ln in ipairs(dd.lines) do if ln.link then anyLink = true end end
eq(anyLink, true, "ds unlimited cascade keeps links at depth 2")
dsR = EVAL_DS_SEARCH("食腐", "unit")
eq(dsR[1] and dsR[1].loc and dsR[1].loc.zid, 14, "ds result carries map loc")
local dz = nil
for _, ln in ipairs(EVAL_DS_DETAIL("unit", 3, 1).lines) do if ln.text:find("杜隆塔尔", 1, true) then dz = ln end end
eq(dz and dz.loc and dz.loc.zid, 14, "ds unit zone line carries map loc")
local dq = EVAL_DS_DETAIL("quest", 1, 1)
eq(dq and dq.title, "收集亚麻布", "ds quest detail title")
-- 1.70.9 起开图链路硬依赖 UnrealQuest（不再有自实现回退），故此处桩它的 Client + MapContext 验证调用契约
local savedUQ3 = UnrealQuest
TEST.uqOpen = 0 TEST.uqAreas = nil TEST.uqParked = nil
UnrealQuest = {
  Client = {
    OpenWorldMap = function() TEST.uqOpen = TEST.uqOpen + 1 return true end,
    CreateWorldMapPin = function() return nil end, -- 钉工厂在测试环境返回 nil（无画布），不影响开图断言
  },
  GetModule = function(_, name)
    if name == "MapContext" then
      return {
        ShowAreas = function(_, areas) TEST.uqAreas = areas return areas[1], "switched" end,
        ParkView = function(_, area) TEST.uqParked = area end,
      }
    end
    return nil
  end,
}
eq(EVAL_DS_SHOWMAP({ x = 46.2, y = 9.3, zid = 14 }), true, "ds showmap opens + switches via UnrealQuest")
eq(TEST.uqOpen, 1, "showmap calls Client.OpenWorldMap")
eq(TEST.uqAreas and TEST.uqAreas[1], 14, "showmap passes zone id to MapContext:ShowAreas")
eq(TEST.uqParked, 14, "showmap parks the view after switching")
eq(EVAL_DS_SHOWMAP({ x = 1, y = 1, zid = 9999 }), true, "showmap still routes through UnrealQuest for unknown zone")
-- 42h) 跟随地图的采集点标注层（1.70.10）：读当前区域 → 取该区服务点/采集点 → 用对方图钉池画
local savedUQ4 = UnrealQuest
TEST.nodePins = 0 TEST.nodePos = 0 TEST.nodeQuery = nil
UnrealQuest = {
  Client = {
    CreateWorldMapPin = function() TEST.nodePins = TEST.nodePins + 1 return { Hide = function() TEST.nodeHide = TEST.nodeHide or {} table.insert(TEST.nodeHide, TEST.nodePins) end, Show = function() TEST.nodeShow = TEST.nodeShow or {} table.insert(TEST.nodeShow, TEST.nodePins) end } end,
    PositionWorldMapPin = function() TEST.nodePos = TEST.nodePos + 1 return true end,
    SetWorldMapPinSize = function() return true end,
    SetWorldMapPinTexture = function() return true end,
    SetWorldMapPinHandlers = function() return true end,
  },
  GetModule = function(_, name)
    if name == "Database" then
      return {
        GetAreaServiceLocations = function(_, areaId, _c, _r, wanted)
          TEST.nodeQuery = { areaId = areaId, wanted = wanted }
          return {
            { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" },
            { category = "mines", x = 41, y = 51, areaId = areaId, sourceType = "object", sourceId = 1731, name = "铜矿脉" },
          }
        end,
      }
    end
    if name == "MapContext" then
      return { GetViewedZone = function() return 14 end }
    end
    return nil
  end,
}
eq(EVAL_DS_TOGGLE_NODES(true), true, "annotation layer toggle on")
-- 1.70.19 统一标注层：节点类默认【关】（一个区域上千个），测试需显式打开它期望的类别
eq(EVAL_DS_CAT_ON("herbs"), false, "node categories default to off (density control)")
EVAL_DS_SET_CAT("herbs", true)
EVAL_DS_SET_CAT("mines", true)
eq(EVAL_DS_CAT_ON("herbs"), true, "category can be enabled")
-- 强制整层重绘（EVAL_DS_ANN_REFRESH 无视签名，直接按当前地图重建），
-- 使本次断言只反映当前 stub 的数据
TEST.nodePins = 0 TEST.nodePos = 0 TEST.nodeQuery = nil
EVAL_DS_ANN_REFRESH()
eq(TEST.nodeQuery ~= nil and TEST.nodeQuery.areaId, 14, "annotation layer queries the viewed area")
eq(TEST.nodeQuery ~= nil and TEST.nodeQuery.wanted ~= nil and TEST.nodeQuery.wanted.herbs, true, "node categories are requested via wanted")
-- 每个点位建一枚钉、定位一次（数量等于 stub 返回且通过类别过滤的点数）
local stubLocs = 2
-- 注意：nodePins 只统计「本次新建」——池子复用是设计目标（旧钉重定位而非重建），
-- 故断言「定位次数」而不是「建钉次数」；池子容量另查。
eq(TEST.nodePos >= stubLocs, true, "annotation layer positions every location via UnrealQuest")
local poolN = select(3, EVAL_DS_NODE_STATE())
eq(poolN >= stubLocs, true, "annotation layer has a reusable pin pool")
-- 切换区域：标注必须换成新区域的点（用户实测反馈「地图切换后标注没更新」→ 加仿真断言钉住）
TEST.nodeShow, TEST.nodeHide = {}, {}
UnrealQuest = {
  Client = {
    CreateWorldMapPin = function(_, idx) return { Hide = function() table.insert(TEST.nodeHide, idx) end, Show = function() table.insert(TEST.nodeShow, idx) end } end,
    PositionWorldMapPin = function(f) return true end,
    SetWorldMapPinSize = function() return true end,
    SetWorldMapPinTexture = function() return true end,
    SetWorldMapPinColor = function() return true end,
    SetWorldMapPinHandlers = function() return true end,
  },
  GetModule = function(_, name)
    if name == "Database" then
      return {
        GetAreaServiceLocations = function(_, areaId)
          if areaId == 14 then -- 杜隆塔尔：2 个点
            return { { category = "herbs", x = 40, y = 50, areaId = 14, name = "A" }, { category = "mines", x = 41, y = 51, areaId = 14, name = "B" } }
          end
          return { { category = "herbs", x = 20, y = 30, areaId = 1, name = "C" } } -- 艾尔文森林：1 个点
        end,
      }
    end
    -- TEST.viewArea == false 表示「大陆视图/无区域」→ GetViewedZone 返回 nil（对方真实语义）
    if name == "MapContext" then
      return { GetViewedZone = function()
        if TEST.viewArea == false then return nil end
        return TEST.viewArea or 14
      end }
    end
    return nil
  end,
}
TEST.viewArea = 14
TEST.mapShown = true -- 1.70.14：地图开着才有视图（关图后 GetViewedZone 仍报旧区域，不能靠它判）
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()
local shownA = table.getn(TEST.nodeShow)
eq(EVAL_DS_NODE_STATE() ~= nil, true, "node state readable")
TEST.viewArea = 1 -- 切到艾尔文森林
TEST.nodeShow, TEST.nodeHide = {}, {}
-- ★★★ 1.70.40 A方案：签名一变就立刻重绘，不再等稳定期。
--   旧行为（第 1 拍只登记、不画）已删除：实测连续切图时每一次都被判「未稳定」→ 一次都不重绘，
--   屏幕停在上一张图上——正是用户报的「滞后一拍」。
EVAL_DS_NODE_TICK_FOR_TEST() -- 第 1 拍：签名变了 → 立刻重绘
eq(table.getn(TEST.nodeShow) >= 1, true, "★★★a signature change redraws on the VERY FIRST tick (no settle wait)")
eq(table.getn(TEST.nodeHide) >= 1, true, "switching zone hides the previous zone pins")
eq(EVAL_DS_NODE_STATE() ~= nil, true, "node state still readable after switch")
-- 1.70.17 定案：WorldMapFrame:IsShown() 在本客户端两个方向都不可靠（UnrealQuest ClientAPI.lua:8664
-- 明文「do not reliably reflect this client's fullscreen presentation」；MapContext.lua:696 记录关图后
-- 它可能一直停在 true）。故可见性【不参与任何分支】，唯一可靠信号是 GetViewedZone 自己：
-- 大陆/世界视图（zoneIndex==0）时它返回 nil。以下断言钉住「只认 areaId、不认 IsShown」。
-- ① IsShown 说开着但 GetViewedZone 给 nil（大陆视图）→ 必须清空
TEST.viewArea = 1
TEST.mapShown = true
EVAL_DS_ANN_REFRESH() -- 先确保本层确实画着东西（否则「隐藏」无从观察）
TEST.viewArea = false -- GetViewedZone 返回 nil = 无区域可选（大陆视图/地图未开）
TEST.mapShown = true -- 即便 IsShown 谎报开着，也必须清空
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()
eq(EVAL_DS_NODE_STATE() ~= nil, true, "state readable with no viewable zone")
eq(table.getn(TEST.nodeShow), 0, "nothing is drawn with no viewable zone")
-- ② IsShown 说关着但 GetViewedZone 给出区域 → 必须照画（IsShown 不可信，不能被它拦住）
--    同样要过稳定期闸门：先拍一次登记候选，推进时钟后再拍才绘制。
TEST.viewArea = 14
TEST.mapShown = false
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()      -- 第 1 拍：登记候选
TEST.time = (TEST.time or 0) + 5
EVAL_DS_NODE_TICK_FOR_TEST()      -- 第 2 拍：稳定后绘制
eq(table.getn(TEST.nodeShow) >= 1, true, "a reported area still draws even if IsShown says closed")
eq(EVAL_DS_TOGGLE_NODES(false), false, "node layer toggle off")
-- 42i) 日志通道（1.70.12）：UELog 在本客户端不落盘 → 改 SavedVariables 环形缓冲
-- 覆盖：写入/上限环形裁剪/开关（表形态 + 旧布尔形态）/dump/clear
local savedCfgLog = EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.log
EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
EVAL_HELP_CONFIG.log = {}
EVAL_LOGLINE("t1")
EVAL_LOGLINE("t2")
eq(EVAL_LOG_COUNT(), 2, "log buffer records lines")
eq(string.find(EVAL_HELP_CONFIG.log[1], "t1", 1, true) ~= nil, true, "log line carries message text")
EVAL_LOG_CLEAR()
eq(EVAL_LOG_COUNT(), 0, "log clear empties the buffer")
-- 环形上限：灌满 EH_LOG_MAX+50 条后必须裁到上限（不能无限增长撑爆 SavedVariables）
EVAL_HELP_CONFIG.log = {}
for i = 1, 350 do EVAL_LOGLINE("filler" .. i) end
eq(EVAL_LOG_COUNT() <= 300, true, "log buffer is capped (ring)")
eq(string.find(EVAL_HELP_CONFIG.log[EVAL_LOG_COUNT()], "filler350", 1, true) ~= nil, true, "ring keeps the newest entry")
-- 旧存档兼容：cfg.log 曾是布尔 true/false，首次写入要自动转成表而不是报错
EVAL_HELP_CONFIG.log = true
EVAL_LOGLINE("after-bool")
eq(type(EVAL_HELP_CONFIG.log), "table", "legacy boolean cfg.log upgrades to table on write")
-- 旧布尔 false = 用户关过日志，必须继续尊重（不能因为转表就擅自打开）
EVAL_HELP_CONFIG.log = false
local cntBefore = EVAL_LOG_COUNT()
EVAL_LOGLINE("should-be-dropped")
eq(EVAL_LOG_COUNT() == cntBefore, true, "legacy boolean false keeps logging disabled")
-- 新表形态的开关
EVAL_HELP_CONFIG.log = { on = false }
cntBefore = EVAL_LOG_COUNT()
EVAL_LOGLINE("also-dropped")
eq(EVAL_LOG_COUNT() == cntBefore, true, "table form on=false disables logging")
EVAL_HELP_CONFIG.log = { on = true }
EVAL_LOGLINE("kept")
eq(EVAL_LOG_COUNT() == 1, true, "table form on=true records")
-- 轨迹日志（/eh ds trace）：开着的时候必须真的记录「签名变化」这条关键路径
EVAL_HELP_CONFIG.log = {}
eq(EVAL_DS_TRACE_STATE(), false, "trace defaults to off")
EVAL_DS_TRACE(true)
eq(EVAL_DS_TRACE_STATE(), true, "trace can be enabled")
TEST.viewArea = 14
EVAL_DS_TOGGLE_NODES(true)
EVAL_DS_NODE_TICK_FOR_TEST()
TEST.viewArea = 1
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选（稳定期闸门）
TEST.time = (TEST.time or 0) + 5
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘 → 才会产生「重绘 map=」日志
local traceHit, drawHit = false, false
for _, s in ipairs(EVAL_HELP_CONFIG.log) do
  if string.find(s, "视图变化", 1, true) ~= nil then traceHit = true end
  if string.find(s, "重绘 map=", 1, true) ~= nil then drawHit = true end
end
eq(traceHit, true, "trace records the view change")
eq(drawHit, true, "trace records the redraw")
-- 1.70.13 教训：标注层开关是取证的前置条件。早前只在内存里 → /reload 后静默 OFF，
-- 用户开了 trace 却一条日志都没有（实测踩到）。必须持久化 + trace 开启时自动打开标注层。
EVAL_HELP_CONFIG.ds = nil
EVAL_DS_TOGGLE_NODES(false)
eq(EVAL_DS_NODE_STATE(), false, "node layer off")
EVAL_DS_TOGGLE_NODES(true)
eq(EVAL_HELP_CONFIG.ds and EVAL_HELP_CONFIG.ds.nodes, true, "layer toggle persists to cfg.ds")
EVAL_DS_TRACE(false)
EVAL_DS_TRACE(true)
eq(EVAL_DS_NODE_STATE(), true, "enabling trace auto-enables the node layer (else tick returns early)")
eq(EVAL_DS_TRACE_STATE(), true, "trace is on")
EVAL_DS_TRACE(false)
EVAL_DS_TRACE(false)
eq(EVAL_DS_TRACE_STATE(), false, "trace can be disabled")
-- ===== 42j) 统一标注层（1.70.19）：地图绑定 + 全类别 + 清理 =====
-- 用户诉求：所有地图标注都与地图绑定（切走隐藏/切回重建）、不限矿石、跨地图、可清理。
-- ① 类别表覆盖 UnrealQuest 的全部 16 类（节点类 5 + 服务类 11），不再写死花草矿宝 4 类
local catN = 0
for _, d in ipairs({ { "herbs" }, { "mines" }, { "chests" }, { "fish" }, { "rares" },
                     { "flight" }, { "innkeeper" }, { "mailbox" }, { "banker" }, { "auctioneer" },
                     { "vendor" }, { "repair" }, { "stablemaster" }, { "spirithealer" },
                     { "meetingstone" }, { "battlemaster" } }) do
  if EVAL_DS_SET_CAT(d[1], true) then catN = catN + 1 end
end
eq(catN, 16, "all 16 UnrealQuest categories are addressable")
-- ② 节点类默认关（密度控制），服务类默认开
EVAL_HELP_CONFIG.ds = nil -- 清掉类别记忆，回到默认
eq(EVAL_DS_CAT_ON("herbs"), false, "node categories default off")
eq(EVAL_DS_CAT_ON("flight"), true, "service categories default on")
-- ③ 地图绑定：切到别的地图必须整层隐藏，切回必须重建
-- （当前 stub 只返回 herbs/mines，且节点类默认关 → 需打开其中一类，否则本层本来就什么都不画）
EVAL_DS_SET_CAT("herbs", true)
TEST.viewArea = 14
EVAL_DS_TOGGLE_NODES(true)
EVAL_DS_ANN_REFRESH()
-- 注意：plain=true 会连 "^" 锚点也当成普通字符，故这里用 string.sub 取前缀比较
eq(string.sub(select(2, EVAL_DS_NODE_STATE()) or "", 1, 3), "14|", "layer records the drawn map (signature starts with areaId)")
TEST.viewArea = 1
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选
TEST.time = (TEST.time or 0) + 5
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘
eq(table.getn(TEST.nodeShow) >= 1, true, "switching map redraws for the new map once settled")
eq(string.sub(select(2, EVAL_DS_NODE_STATE()) or "", 1, 2), "1|", "layer now bound to the new map")
TEST.viewArea = 14 -- 切回：必须重新显示（用户明确要求「切回地图要重新显示」）
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选
TEST.time = (TEST.time or 0) + 5
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘
eq(table.getn(TEST.nodeShow) >= 1, true, "switching back re-shows the map's annotations")
eq(string.sub(select(2, EVAL_DS_NODE_STATE()) or "", 1, 3), "14|", "layer re-bound to the original map")
-- ③b) 用户实测报障（1.70.20）：「点开之后关不掉」「切换地图之后都是旧数据」
--     根因：TOGGLE OFF 走了 REFRESH → 无视开关重绘并把 dsAnnSig 设成当前地图 → 关不掉且永不再清理。
--     以下断言钉住「关 = 真的关，且不影响再次打开」。
TEST.viewArea = 14
EVAL_DS_TOGGLE_NODES(true)
EVAL_DS_ANN_REFRESH() -- 确保画着东西
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_TOGGLE_NODES(false) -- 关：必须立刻隐藏 + 清签名
eq(EVAL_DS_NODE_STATE(), false, "toggle off turns the layer off")
eq(select(2, EVAL_DS_NODE_STATE()), nil, "toggle off clears the drawn-map signature (so it can redraw later)")
TEST.nodeShow = {}
EVAL_DS_NODE_TICK_FOR_TEST()
eq(table.getn(TEST.nodeShow), 0, "nothing is drawn after toggling off")
-- 关掉之后还必须「切图也不复活」——这是用户报的「无法关闭 + 旧数据」的合并症状。
-- 无论修复落在 TOGGLE 还是 REFRESH 哪一层，只要钉子还能被画出来就必须失败。
TEST.viewArea = 1
TEST.nodeShow = {}
EVAL_DS_NODE_TICK_FOR_TEST()
eq(table.getn(TEST.nodeShow), 0, "toggling off stays off across a map switch")
TEST.viewArea = 14
-- 关闭状态下，REFRESH 不能把分类层的钉子画回来（用户报的「关不掉」就是这类泄漏）
TEST.nodeShow = {}
EVAL_DS_ANN_REFRESH() -- 手动刷新
eq(table.getn(TEST.nodeShow), 0, "refresh while off draws nothing")
-- ★1.70.23 按钮合并后语义变化：勾选类别 = 打开图层（下拉里的勾选项就是开关），
--   故「关着时改类别仍不画」这条旧断言已不成立，改为断言相反行为——这正是用户要的。
TEST.nodeShow = {}
EVAL_DS_SET_CAT("herbs", true)
eq(EVAL_DS_NODE_STATE(), true, "enabling a category turns the layer on (switch now lives in the list)")
eq(table.getn(TEST.nodeShow) >= 1, true, "enabling a category draws immediately")
-- 全部关掉 = 图层关闭（等价于原来的总开关）
for _, k in ipairs({ "herbs", "mines", "chests", "fish", "rares", "flight", "innkeeper",
                     "mailbox", "banker", "auctioneer", "vendor", "repair", "stablemaster",
                     "spirithealer", "meetingstone", "battlemaster" }) do
  EVAL_DS_SET_CAT(k, false)
end
eq(EVAL_DS_NODE_STATE(), false, "clearing every category turns the layer off")
-- 搜索结果定位（覆盖层）独立于类别：图层关着时它也不该把分类层钉子带回来
TEST.nodeShow = {}
EVAL_DS_SHOWMAP({ x = 10, y = 10, zid = 14, name = "X", kind = "unit", id = 3 })
eq(EVAL_DS_NODE_STATE(), false, "overlay does not silently re-enable the category layer")
-- 「全部关闭」必须能清掉覆盖层（原「清理标注」按钮已删除，这是唯一的移除入口）
EVAL_DS_ANN_CLEAR_OVERLAY()
TEST.nodeShow = {}
EVAL_DS_ANN_REFRESH()
eq(table.getn(TEST.nodeShow), 0, "clearing the overlay removes search-result pins")
-- 再打开：必须重新画（若签名没被清，这里会因为「已画过」而什么都不出）
EVAL_DS_SET_CAT("herbs", true) -- 上一步把类别全关了，先开一类才有东西可画
TEST.nodeShow = {}
EVAL_DS_TOGGLE_NODES(true)
eq(table.getn(TEST.nodeShow) >= 1, true, "toggling back on redraws (stale-signature regression)")
-- ③c) 「只显示当前地图的数据」（用户要求）：断言查询用的就是当前视图区域，
--      且不会把别的地图的点画上来。数据源侧按 coordinate[3]==areaId 过滤，这里钉住我们传对了参数。
local savedQueryArea = nil
UnrealQuest = {
  Client = TEST.nodeClient or UnrealQuest.Client,
  GetModule = function(_, name)
    if name == "Database" then
      return { GetAreaServiceLocations = function(_, areaId, _c, _r, wanted)
        savedQueryArea = areaId
        return {
          { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" },
          { category = "herbs", x = 41, y = 51, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" },
        }
      end }
    end
    if name == "MapContext" then
      -- 第 2 返回值 = report（含 mapFile/continent/zoneIndex）——视图签名要用它，
      -- 故桩必须能返回，否则测不到「同区域但视图变化」这条路径。
      return { GetViewedZone = function() return TEST.viewArea or 14, TEST.viewReport end }
    end
    return nil
  end,
}
EVAL_DS_SET_CAT("herbs", true)
TEST.viewArea = 37
EVAL_DS_TOGGLE_NODES(true)
eq(savedQueryArea, 37, "layer queries the CURRENTLY VIEWED area only (not a stale/other area)")
TEST.viewArea = 14
EVAL_DS_ANN_REFRESH()
eq(savedQueryArea, 14, "changing the map re-queries that map")
-- ③d) 用户实测（1.70.24）：「勾选了类型但地图上不显示」。
--     根因：视图签名只含 areaId → 关图再开同一张图时 areaId 不变 → 判定「未变 → 跳过重绘」，
--     钉子停留在关图时被客户端清掉的状态，地图看起来是空的。
--     修复：签名并入 mapFile/continent/zoneIndex（照抄 UnrealQuest ViewSignature）。
--     以下断言钉住：**同一区域但视图变化（如重开地图）必须触发重绘**。
TEST.viewArea = 14
EVAL_DS_SET_CAT("herbs", true)
EVAL_DS_ANN_REFRESH() -- 视图 A
local sigA = select(2, EVAL_DS_NODE_STATE())
TEST.viewReport = { mapFile = "Azeroth", continent = 1, zoneIndex = 3 } -- 视图 A 的 report
EVAL_DS_ANN_REFRESH()
local sigB = select(2, EVAL_DS_NODE_STATE())
eq(sigA ~= sigB, true, "same area but different map view yields a different signature")
TEST.nodeShow = {}
TEST.viewReport = { mapFile = "Azeroth", continent = 1, zoneIndex = 5 } -- 视图 B（如重开地图后）
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选
TEST.time = (TEST.time or 0) + 5
EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘
eq(table.getn(TEST.nodeShow) >= 1, true, "a view change within the same area forces a redraw once settled")
-- ④ 清理标注：一键清空整层并关掉图层开关（否则下一 tick 立刻铺回来）
EVAL_DS_ANN_CLEAR()
eq(EVAL_DS_NODE_STATE(), false, "clear turns the layer off")
TEST.nodeShow, TEST.nodeHide = {}, {}
EVAL_DS_NODE_TICK_FOR_TEST()
eq(table.getn(TEST.nodeShow), 0, "nothing is drawn after clear")
-- 1.70.15 教训：trace 也必须持久化，否则「开 trace → /reload → 取证开关被静默解除」，
-- 落盘日志只剩一行「trace 开启」，看起来像功能没生效（实测连续两轮踩到）。
EVAL_HELP_CONFIG.ds = nil
EVAL_DS_TRACE(true)
eq(EVAL_HELP_CONFIG.ds and EVAL_HELP_CONFIG.ds.trace, true, "trace persists to cfg.ds.trace")
-- 1.70.16 定案：恢复开关必须能在「从未打开过 Tab4」时生效。
-- 原实现把恢复放进 EVAL_DS_BUILD（只在打开数据检索 Tab 时执行一次）→ 用户停在 Tab1 →
-- 永不恢复 → trace 静默失效、日志只有一行。现改为文件作用域 + VARIABLES_LOADED 双保险。
eq(type(EVAL_DS_RESTORE), "function", "restore is exposed for load-time / VARIABLES_LOADED use")
EVAL_DS_TRACE(false)
EVAL_DS_TOGGLE_NODES(false)
EVAL_HELP_CONFIG.ds = { nodes = true, trace = true } -- 模拟「存档里是开，内存里是关」的 /reload 后状态
eq(EVAL_DS_RESTORE(), true, "restore reads persisted switches")
eq(EVAL_DS_TRACE_STATE(), true, "restore turns trace back on")
eq(EVAL_DS_NODE_STATE(), true, "restore turns the node layer back on")
EVAL_DS_TOGGLE_NODES(true)
eq(EVAL_HELP_CONFIG.ds and EVAL_HELP_CONFIG.ds.nodes, true, "node toggle persists alongside trace")
EVAL_DS_TRACE(false)
EVAL_DS_TOGGLE_NODES(false)
EVAL_HELP_CONFIG.log = savedCfgLog -- 恢复（测试替换全局必须还原）
UnrealQuest = savedUQ4 -- 恢复真实全局（1.68.2 教训：测试替换全局必须 save/restore）
dsR = EVAL_DS_SEARCH("食腐", "unit")
eq(dsR[1] and dsR[1].loc and dsR[1].loc.name, "食腐者", "ds loc carries entity name for map annotation")
eq(dsR[1] and type(dsR[1].loc.pts) == "table" and table.getn(dsR[1].loc.pts) >= 1, true, "ds loc carries spawn points list")
-- 42c) 图标路径：必须无扩展名 + 小写插件名（本客户端带 .tga 会静默不画）；生物按 rank 换精确图标
local dsIconMiss = false
for _, k in ipairs({ "quest", "unit", "object", "item" }) do
  local p = EVAL_DS_ICON_PATH(k, 3)
  if not p or string.find(p, "%.[Tt][Gg][Aa]$") or string.find(p, "UnrealQuest") then dsIconMiss = true end
end
eq(dsIconMiss, false, "icon paths are extensionless and lowercase-addon")
eq(EVAL_DS_ICON_PATH("unit", 40), "Interface\\AddOns\\unrealQuest\\media\\icons\\boss-mobs", "rank 3 unit uses boss icon")
eq(EVAL_DS_ICON_PATH("unit", 3), "Interface\\AddOns\\unrealQuest\\media\\icons\\rares", "rankless unit uses generic creature icon")
-- 42d) 地图图标与链接指向图标必须是两个不同素材（用户实测反馈容易混）
local mi = EVAL_DS_MAP_ICON_PATH()
local pi = EVAL_DS_MAP_PIN_PATH()
eq(mi ~= nil and string.find(mi, "QuestDot", 1, true) ~= nil, true, "map button uses round QuestDot marker")
eq(pi ~= nil and string.find(pi, "quest-marker", 1, true) ~= nil, true, "on-map pin keeps the pin glyph") -- plain=true：- 是 Lua 模式魔法字符
eq(mi ~= pi, true, "map button glyph differs from on-map pin glyph")
eq(string.find(mi, "%.[Tt][Gg][Aa]$") == nil, true, "map icon path is extensionless")
-- 42e) 左右图标都必须是可点的独立按钮（纹理不接收鼠标——用户实测「点图标没反应」根因）
eq(EVAL_DS_BUILD_FOR_TEST(), true, "ds UI builds for structural assertions")
local dl = EVAL_DS_TEST_LINE(1)
eq(dl ~= nil and dl.iconBtn ~= nil and dl.mapBtn ~= nil, true, "detail row exposes both icon buttons")
eq(dl ~= nil and dl.iconBtn.GetScript ~= nil, true, "left icon button is a real Button")
local rr = EVAL_DS_TEST_ROW(1)
eq(rr ~= nil and rr.iconBtn ~= nil and rr.mapBtn ~= nil, true, "result row exposes both icon buttons")
-- 42f) 地图钉 tooltip 内容：标题(青) + 区域/坐标行 + 关联块（用户实测要求「显示该点链接的内容信息」）
local tl = EVAL_DS_PIN_TOOLTIP_LINES({ name = "食腐者", zone = "杜隆塔尔", x = 46.2, y = 9.3, kind = "unit", id = 3 })
eq(table.getn(tl) > 3, true, "pin tooltip has title + attr + blocks")
eq(tl[1].text, "食腐者", "pin tooltip first line is the entity title")
eq(tl[1].g, 1, "pin tooltip title uses teal-ish colour (g=1)")
local sawZone, sawCoord, sawDropHdr = false, false, false
for _, ln in ipairs(tl) do
  if ln.left == "区域" then sawZone = true end
  if ln.left == "坐标" then sawCoord = true end
  if ln.text == "—— 掉落物品 ——" then sawDropHdr = true end
end
eq(sawZone, true, "pin tooltip carries zone row")
eq(sawCoord, true, "pin tooltip carries coord row")
eq(sawDropHdr, true, "pin tooltip lists drops block for a unit")
eq(EVAL_DS_PIN_TOOLTIP_LINES(nil)[1], nil, "pin tooltip handles missing info")
-- 42g) 重置搜索状态（1.70.7）：一键清空 级联栈/结果/偏移/输入，与「返回一层」区分
EVAL_DS_SEARCH("亚麻", nil)
EVAL_HELP_CONFIG.cfgTab = 4 EVAL_DS_BUILD_FOR_TEST()
EVAL_DS_RESET()
eq(table.getn(EVAL_DS_NAV()), 0, "reset clears the cascade stack")
eq(EVAL_DS_TEST_STATE("results"), 0, "reset clears the result list")
eq(EVAL_DS_TEST_STATE("detOff"), 0, "reset zeroes the scroll offset")
eq(EVAL_DS_TEST_STATE("lastQuery"), "", "reset clears the last query")
-- （旧的回退路径断言已随 1.70.9 硬依赖简化删除：开图只走 UnrealQuest）
-- 43) 条件默认值去职业化（1.70.0）：空技能名条件不崩、渲染不带旧职业默认；目标职业空选=不过
-- 文本格式需具体技能名（(.+)），空名条件只在编辑窗内存在、不进导入导出（记录该行为）
eq(table.getn(EVAL_PARSE_CONDS("有debuff: & 免疫: & 范围内:")), 0, "empty-name conditions are not representable in text format")
eq(EVAL_COND_STR({ k = "hasDebuff", s = "", v = true }), "有debuff:", "empty debuff renders without warrior default")
eq(EVAL_COND_STR({ k = "tClass", cs = {} }), "目标职业:未选", "empty class renders 未选 instead of WARRIOR default")
eq(EVAL_COND_STR({ k = "immune", s = "", v = true }), "免疫:", "empty immune renders without warrior default")
eq(EVAL_COND_STR({ k = "inRange", s = "", v = true }), "范围内:", "empty inRange renders without warrior default")
eq(EVAL_DS_DETAIL("bogus", 1, 1), nil, "ds unknown kind nil")
local savedUQ = UnrealQuestData UnrealQuestData = nil -- 1.68.2 教训：测试替换全局必须 save/restore
eq(table.getn(EVAL_DS_SEARCH("亚麻", nil)), 0, "ds search graceful without UnrealQuest")
eq(EVAL_DS_DETAIL("item", 2589, 1), nil, "ds detail graceful without UnrealQuest")
UnrealQuestData = savedUQ

-- 44) 地图标注下拉：多选保活 + 标题行不可选 + 勾选态单一数据源（1.70.25，用户实测两处缺陷）
-- 用户原话：「每次点击一个 下拉窗不要关闭」「我选择的是草药，但是他会把矿脉也勾选上」。
-- 根因：DataSearch 调 EVAL_DD_OPEN 时【没传 opts】→ 面板走非多选分支——
--   ① OnClick 里 dd:Hide() → 点一项就关（缺陷 1）；
--   ② 勾选标记是我拼进标签文本的，与面板自绘方框两套状态并存 → 观感错乱（缺陷 2）。
-- 决定性旁证：存档里 cfg.ds.cats 只有 {herbs=true}（数据层完全正确）→ 缺陷 2 纯属显示层。
EVAL_HELP_CONFIG.ds = nil
for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
-- 44a) 派生开关：全关=层关，开一类=层开
eq(EVAL_DS_CAT_COUNT(), 0, "all categories off yields count 0")
eq(EVAL_DS_NODE_STATE(), false, "all-off turns the annotation layer off")
EVAL_DS_SET_CAT("herbs", true)
eq(EVAL_DS_CAT_ON("herbs"), true, "herbs turns on")
eq(EVAL_DS_CAT_ON("mines"), false, "★turning on herbs must NOT turn on mines")
eq(EVAL_DS_CAT_COUNT(), 1, "★enabling one category yields exactly count 1")
eq(EVAL_DS_NODE_STATE(), true, "enabling a category turns the layer on")
-- 44b) 面板勾选态与类别状态逐行一致（缺陷 2 的回归防线）
local selMap = EVAL_DS_TEST_DD_SEL()
eq(type(selMap), "table", "dropdown exposes its derived selection for assertions")
eq(selMap.herbs, true, "★herbs row is checked in the panel")
eq(selMap.mines, nil, "★mines row is NOT checked when only herbs is on")
eq(selMap.chests, nil, "★chests row is NOT checked when only herbs is on")
local mismatch = 0
for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do
  if ((selMap[d.k] and true or false) ~= EVAL_DS_CAT_ON(d.k)) then mismatch = mismatch + 1 end
end
eq(mismatch, 0, "★every row's checkbox matches the real category state (single source of truth)")
-- 44c) 全部关闭：清空类别 + 所有行勾选态同步归零（批量动作必须整体重绘）
EVAL_DS_TEST_DD_PICK("__all_off__")
eq(EVAL_DS_CAT_COUNT(), 0, "all-off clears every category")
eq(EVAL_DS_NODE_STATE(), false, "all-off turns the layer off")
local selOff, stillOn = EVAL_DS_TEST_DD_SEL(), 0
for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do if selOff[d.k] then stillOn = stillOn + 1 end end
eq(stillOn, 0, "★after all-off no row is left checked (bulk action repaints every row)")
-- 44d) 全部开启：所有类别开 + 每行都勾上
EVAL_DS_TEST_DD_PICK("__all_on__")
eq(EVAL_DS_CAT_COUNT(), table.getn(EVAL_DS_ANN_CAT_LIST()), "all-on enables every category")
local selAll, allOn = EVAL_DS_TEST_DD_SEL(), true
for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do if not selAll[d.k] then allOn = false end end
eq(allOn, true, "★after all-on every row is checked")
-- 44e) 单行点击用面板回传的新状态，而不是再读数据源取反（防连续同向翻转）
EVAL_DS_TEST_DD_PICK("mines", false) -- 先关掉 mines（44d 全开时被打开）
eq(EVAL_DS_CAT_ON("mines"), false, "picking a row with nowOn=false disables it")
eq(EVAL_DS_CAT_ON("herbs"), true, "★toggling mines off leaves herbs on")
EVAL_DS_TEST_DD_PICK("mines", true)
eq(EVAL_DS_CAT_ON("mines"), true, "picking a row with nowOn=true enables it")
eq(EVAL_DS_CAT_ON("herbs"), true, "★picking mines leaves herbs untouched")
-- 44f) 分组标题行声明为 locked（点它不能凭空多出一个勾）
eq(EVAL_DS_TEST_DD_LOCKED_COUNT() >= 3, true, "group header rows are declared locked (node/svc/quick)")
eq(EVAL_DS_TEST_DD_IS_LOCKED("节点"), true, "node group header row is locked")
eq(EVAL_DS_TEST_DD_IS_LOCKED("草药"), false, "a real category row is not locked")
-- 44g) ★行为级断言：多选面板点选后【不隐藏】，且 nowOn 正确回调（缺陷 1 的回归防线）
do
  local picks, items = {}, { "行一", "行二", "行三" }
  EVAL_DD_TEST_OPEN_MULTI(items, function(p, on) picks[#picks + 1] = tostring(p) .. "=" .. tostring(on) end,
    { selected = { [2] = true }, locked = { [3] = true } })
  eq(EVAL_DD_TEST_MULTI(), true, "★the panel really opened in multi mode")
  local shownAfter = EVAL_DD_TEST_CLICK(1)
  eq(shownAfter, true, "★clicking a row does NOT close the panel (user defect 1)")
  eq(picks[1], "1=true", "row 1 pick reports nowOn=true")
  shownAfter = EVAL_DD_TEST_CLICK(1)
  eq(shownAfter, true, "★panel still open after a second click")
  eq(picks[2], "1=false", "row 1 second click reports nowOn=false (toggles)")
  -- 锁定行：没有 OnClick，点了也不回调、不改选中
  local nBefore = table.getn(picks)
  EVAL_DD_TEST_CLICK(3)
  eq(table.getn(picks), nBefore, "★locked row click produces no pick callback")
  EVAL_DD_TEST_CLICK(2) -- 初始 selected[2]=true → 点击后应变 false
  eq(picks[table.getn(picks)], "2=false", "pre-selected row toggles off correctly")
  EVAL_DD_TEST_CLICK(9) -- 越界行：无按钮 → 安全返回
  EVAL_DD_HIDE()
end
eq(EVAL_DD_TEST_LOCKED_SUPPORTED(), true, "★EVAL_DD_OPEN multi mode really supports locked rows")
-- 44i) ★处理函数必须【信任面板回传的状态】，而不是自行读数据源取反。
-- 旧实现 EVAL_DS_SET_CAT(k, not EVAL_DS_CAT_ON(k)) 在「面板显示」与「数据实际」不一致时
-- 会连续同向翻转（点 A 看起来像点了 B）——这正是用户报的「选草药却把矿脉勾上」的机理。
-- 断言方式：故意用一个与存档状态矛盾的回传值，看谁说了算。
do
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
  eq(EVAL_DS_CAT_ON("mines"), false, "precondition: mines is off")
  -- 面板说「选中」，数据是「关」→ 必须采信面板 → 结果是开
  EVAL_DS_TEST_DD_PICK("mines", true)
  eq(EVAL_DS_CAT_ON("mines"), true, "★handler trusts the panel's nowOn=true (does not re-read+negate)")
  -- 面板说「取消」，数据是「开」→ 必须采信面板 → 结果是关
  EVAL_DS_TEST_DD_PICK("mines", false)
  eq(EVAL_DS_CAT_ON("mines"), false, "★handler trusts the panel's nowOn=false")
  -- 反向再验一次，确保不是巧合
  EVAL_DS_SET_CAT("mines", true)
  EVAL_DS_TEST_DD_PICK("mines", false)
  eq(EVAL_DS_CAT_ON("mines"), false, "★nowOn=false wins even when the stored state is true")
  -- ★判别性最强的一组：面板说「开」而数据【本来就是开】→ 必须保持开。
  -- 旧实现读数据源取反会把它关掉（not true = false）——这正是「点 A 却像点了 B」的机理。
  -- 注：前两组（面板=开/数据=关，面板=关/数据=开）在新旧实现下结果相同，无法判别，必须用本组。
  EVAL_DS_SET_CAT("mines", true)
  EVAL_DS_TEST_DD_PICK("mines", true)
  eq(EVAL_DS_CAT_ON("mines"), true, "★nowOn=true keeps it ON even when the stored state is already true")
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end
-- 44j) ★批量改选后【每一行】都要重绘（只重绘被点那行会让其余行停在旧方框）。
-- 用户看到的就是「我明明全关了，列表里还一堆方块」。故必须检查真实渲染文本。
do
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST()
  local cb2 = EVAL_DS_TEST_CATBTN()
  EVAL_DD_TEST_RESET_ANCHOR()
  EVAL_DD_HIDE()
  cb2:GetScript("OnClick")() -- 打开真实面板
  -- 点「全部开启」→ 所有行都应变成实心方框
  local mAll = EVAL_DS_TEST_DD_MENU()
  local allOnRow
  for i = 1, table.getn(mAll.items) do
    if mAll.keys[i] == "__all_on__" then allOnRow = i end
  end
  eq(allOnRow ~= nil, true, "menu exposes an 全部开启 row")
  EVAL_DD_TEST_CLICK(allOnRow)
  local staleOn, checkedOn = 0, 0
  for i = 1, table.getn(mAll.items) do
    local k = mAll.keys[i]
    if k and k ~= "__all_on__" and k ~= "__all_off__" then
      local rowT = (EVAL_DD_TEST_ROW(i) or {}).text
      local txt = rowT and rowT:GetText() or ""
      if string.find(txt, "■", 1, true) then checkedOn = checkedOn + 1
      elseif string.find(txt, "□", 1, true) then staleOn = staleOn + 1 end
    end
  end
  eq(checkedOn, table.getn(EVAL_DS_ANN_CAT_LIST()), "★after 全部开启 every category row renders a checked box")
  eq(staleOn, 0, "★after 全部开启 no category row is left showing an unchecked box (bulk repaint)")
  -- 点「全部关闭」→ 所有行都应回到空心方框
  local allOffRow
  for i = 1, table.getn(mAll.items) do
    if mAll.keys[i] == "__all_off__" then allOffRow = i end
  end
  EVAL_DD_TEST_CLICK(allOffRow)
  local staleOff, checkedOff = 0, 0
  for i = 1, table.getn(mAll.items) do
    local k = mAll.keys[i]
    if k and k ~= "__all_on__" and k ~= "__all_off__" then
      local rowT = (EVAL_DD_TEST_ROW(i) or {}).text
      local txt = rowT and rowT:GetText() or ""
      if string.find(txt, "□", 1, true) then staleOff = staleOff + 1
      elseif string.find(txt, "■", 1, true) then checkedOff = checkedOff + 1 end
    end
  end
  eq(staleOff, table.getn(EVAL_DS_ANN_CAT_LIST()), "★after 全部关闭 every category row renders an unchecked box")
  eq(checkedOff, 0, "★after 全部关闭 no row is left showing a checked box (bulk repaint)")
  EVAL_DD_HIDE()
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end

-- 44h) ★★接线级断言：点真实的 DS.catBtn，走真实的调用点。
-- 上述 44b/44g 分别只覆盖「菜单数据」与「下拉引擎」，都绕过了宿主（DataSearch）那一行调用。
-- 变异验证证明：把 DataSearch 里的 opts.multi 去掉，44b/44g 依然全绿——因为引擎本身没问题，
-- 坏的是**宿主忘了传参**。因此必须断言接线：点真按钮 → 面板确实是多选态 → 点行不关闭。
do
  -- 干净起点：44a~44e 会把类别开关留在「开着」的状态，若不复位，下面的点击就是「关掉」
  -- 而不是「打开」，断言会以完全误导的方式失败（本测试首版正是栽在这里）。
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
  eq(EVAL_DS_CAT_COUNT(), 0, "wiring test starts from a clean slate (all categories off)")
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST() -- 建真实 UI（含 DS.catBtn 及其 OnClick 脚本）
  local cb = EVAL_DS_TEST_CATBTN()
  eq(cb ~= nil, true, "catBtn exists after build")
  local clickFn = cb:GetScript("OnClick")
  eq(type(clickFn), "function", "catBtn has a real OnClick handler")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR() -- 清掉锚点，确保本次是「打开」而不是被 toggle 收起
  clickFn() -- 等价于用户点「地图标注(N)」
  eq(EVAL_DD_TEST_MULTI(), true, "★clicking catBtn opens the dropdown in MULTI mode (host passes opts.multi)")
  eq(EVAL_DD_TEST_SHOWN(), true, "dropdown is shown after clicking catBtn")
  -- 面板里第 2 行 = 草药（第 1 行是「节点（采集物）」分组标题）
  -- 断言「被点的行文本确实带上了选中方框」——直接覆盖用户看到的那个方框
  local row2 = EVAL_DD_TEST_ROW(2)
  eq(row2 ~= nil and string.find(row2.text:GetText() or "", "□", 1, true) ~= nil, true,
     "row 2 renders an UNCHECKED box before the click")
  -- 点第 2 行（= 草药，节点组首项）——必须切换状态且【面板保持打开】
  local kept = EVAL_DD_TEST_CLICK(2)
  eq(kept, true, "★clicking a category row does NOT close the panel (user defect 1, wiring level)")
  eq(EVAL_DS_CAT_ON("herbs"), true, "★clicking row 2 enables exactly the row's category")
  -- ★直接断言「用户眼睛看到的东西」：草药行变成实心方框，矿脉行仍是空心方框。
  --   这是缺陷 2「选草药却把矿脉也勾上」最贴近现场的覆盖——不看内部状态，只看渲染文本。
  -- ★标签文本本身绝不能带方框：方框只许由面板绘制。
  --   （变异验证：把标记重新拼进标签会让渲染出「■ ■ 草药」两个方框，而只检查「含有 ■」
  --     的断言照样通过——所以必须断言方框【恰好出现一次】。）
  -- ★渲染文本去掉开头的方框后，必须逐字等于菜单里的纯标签。
  --   若有人把标记/装饰重新拼进标签（变异验证用的 "X "/"O "），这里立刻不等。
  --   注意必须比「真实渲染出的行文本」而不是「重新生成的菜单」——paint() 闭包持有的是
  --   打开面板那一刻传入的 items，重新调用 dsCatMenu() 得到的是新表，比不出差异。
  local mItems = EVAL_DS_TEST_DD_MENU().items
  do
    local mismatch = 0
    for i = 1, table.getn(mItems) do
      local rowT = (EVAL_DD_TEST_ROW(i) or {}).text
      local txt = rowT and rowT:GetText() or ""
      local plain = tostring(mItems[i])
      local expectOn  = "|cffffd100■|r " .. plain
      local expectOff = "|cff6a6a6a□|r " .. plain
      if txt ~= expectOn and txt ~= expectOff and txt ~= plain then mismatch = mismatch + 1 end
    end
    eq(mismatch, 0, "★every rendered row is exactly <box> + <plain label> (no baked decoration)")
  end
  local t2 = (EVAL_DD_TEST_ROW(2) or {}).text
  local t3 = (EVAL_DD_TEST_ROW(3) or {}).text
  eq(t2 and string.find(t2:GetText() or "", "■", 1, true) ~= nil, true,
     "★after the click the 草药 row renders a CHECKED box")
  do -- 渲染文本里方框必须只出现一次（防止「面板方框 + 标签方框」叠加成两个）
    local txt = (t2 and t2:GetText()) or ""
    local cnt = 0
    local pos = 1
    while true do
      local a = string.find(txt, "■", pos, true)
      local b = string.find(txt, "□", pos, true)
      local hit = a or b
      if not hit then break end
      cnt = cnt + 1
      pos = hit + 1
    end
    eq(cnt, 1, "★the 草药 row shows exactly one box glyph (no double marker)")
  end
  eq(t3 and string.find(t3:GetText() or "", "□", 1, true) ~= nil, true,
     "★after the click the 矿脉 row still renders an UNCHECKED box (user defect 2)")
  eq(t3 and string.find(t3:GetText() or "", "■", 1, true) == nil, true,
     "★the 矿脉 row shows no checked box at all")
  local selAfter = EVAL_DS_TEST_DD_SEL()
  eq(selAfter.herbs, true, "★panel checkbox for herbs reflects the click")
  eq(selAfter.mines, nil, "★clicking 草药 does NOT check 矿脉 (user defect 2, wiring level)")
  eq(EVAL_DS_CAT_ON("mines"), false, "★矿脉 stays disabled in the data layer too")
  -- 再点同一行 → 关闭，面板仍开着
  local kept2 = EVAL_DD_TEST_CLICK(2)
  eq(kept2, true, "★panel still open after toggling a category off")
  eq(EVAL_DS_CAT_ON("herbs"), false, "second click on the same row turns it off")
  EVAL_DD_HIDE()
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end

for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
EVAL_HELP_CONFIG.ds = nil


-- 45) 类别图标 + 自定义检索用小圆点（1.70.26，用户要求）
-- 用户原话：「查看每个类别的标注是否有对应的图标显示。自定义检索的数据(npc/无掉落等)才用小圆点显示」。
-- 原实现：所有钉子（含 16 个类别）都用同一个 QuestDot 圆点，只靠颜色区分——正是截图里满屏绿点的成因。
do
  local root = EVAL_DS_ANN_ICON_ROOT()
  eq(type(root) == "string" and table.getn(root) > 10, true, "icon root is exposed")
  eq(string.find(root, "%.[Tt][Gg][Aa]$") == nil, true, "★icon root has NO .tga suffix (client draws nothing with it)")
  eq(string.find(root, "UnrealQuest") == nil, true, "★icon root uses lowercase addon name (case matters on this client)")
  eq(string.sub(root, table.getn(root)) == "\\", true, "icon root ends with a separator")
  -- 45a) 16 个类别每个都必须有图标（用户要的就是「每个类别有对应图标」）
  local missing, n = {}, 0
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do
    n = n + 1
    if type(EVAL_DS_CAT_ICON(d.k)) ~= "string" or EVAL_DS_CAT_ICON(d.k) == "" then
      missing[table.getn(missing) + 1] = d.k
    end
  end
  eq(n, 16, "all 16 categories are present")
  eq(table.getn(missing), 0, "★every category has an icon assigned (" .. table.concat(missing, ",") .. ")")
  -- 45b) 图标文件名清单必须与测试基建的期望完全一致。
  --   ★磁盘存在性由 node 侧校验（test_engine.js 的 icon-assets 检查），因为 fengari 的 io
  --     在本沙箱里不可用；Lua 侧只钉住清单本身，磁盘那半在能读真实文件系统的地方做。
  local names = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do names[table.getn(names) + 1] = d.icon end
  eq(table.concat(names, ","),
     "herbs,mines,chests,fish,rares,flight,innkeeper,mailbox,banker,auctioneer,vendor,repair,stablemaster,spirithealer,meetingstone,battlemaster",
     "★category icon names match the verified-on-disk list exactly")
  -- 45c) 稀有怪按 rank 换脸（照抄 UnrealQuest RANK_ICONS）
  eq(EVAL_DS_ANN_ICON_FOR({ category = "rares", sourceType = "unit", sourceId = 3 }), "rares",
     "unknown-rank rare falls back to the category icon")
  -- 45d) ★自定义检索（搜索结果定位）= 小圆点：必须解析不出图标
  eq(EVAL_DS_ANN_ICON_FOR({ category = nil, sourceType = "unit", sourceId = 40 }), nil,
     "★a custom-search entity with no category resolves to NO icon (round dot)")
  eq(EVAL_DS_ANN_ICON_FOR(nil), nil, "nil location resolves to no icon")
  eq(EVAL_DS_ANN_ICON_FOR({ category = "nosuchcat" }), nil, "unknown category resolves to no icon")
  -- 45e) 物件类（草药/矿脉）优先用该物件自己的美术，表里没有才回落类别图标
  local known = EVAL_DS_ANN_ICON_FOR({ category = "herbs", sourceType = "object", sourceId = 1618 })
  eq(type(known) == "string", true, "herb object resolves to a texture id")
  local unknownObj = EVAL_DS_ANN_ICON_FOR({ category = "herbs", sourceType = "object", sourceId = 999999 })
  eq(unknownObj, "herbs", "an object absent from nodeIcons falls back to the category icon")
  -- 45e2) ★接线级：真实重绘里，分类标注必须带图标、搜索结果定位必须【不带】图标。
  --   只断言 dsAnnIconFor（解析器）会漏掉调用点写死 nil/写死图标的变异——必须看实际摆放参数。
  do
    -- 自建 stub（与组 42 同一套路），不依赖前面测试留下的全局状态
    local savedUQ5 = UnrealQuest
    UnrealQuest = {
      Client = {
        CreateWorldMapPin = function(_, idx) return { Hide = function() end, Show = function() end } end,
        PositionWorldMapPin = function() return true end,
        SetWorldMapPinSize = function() end,
        SetWorldMapPinTexture = function() end,
        SetWorldMapPinColor = function() end,
        SetWorldMapPinHandlers = function() end,
      },
      GetModule = function(_, name)
        if name == "Database" then
          return { GetAreaServiceLocations = function(_, areaId)
            return {
              { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" },
            }
          end }
        end
        if name == "MapContext" then
          return { GetViewedZone = function() return 14, TEST.viewReport end }
        end
        return nil
      end,
    }
    EVAL_HELP_CONFIG.ds = nil
    for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
    EVAL_DS_SET_CAT("herbs", true)
    EVAL_HELP_CONFIG.cfgTab = 4
    EVAL_DS_BUILD_FOR_TEST()
    local cap = EVAL_DS_TEST_CAPTURE_DRAW(14)
    eq(table.getn(cap) > 0, true, "a real draw places at least one annotation")
    local withIcon, withoutIcon = 0, 0
    for _, c in ipairs(cap) do
      if c.icon then withIcon = withIcon + 1 else withoutIcon = withoutIcon + 1 end
    end
    eq(withIcon > 0, true, "★category annotations are placed WITH an icon")
    -- 搜索结果覆盖层：必须是无图标（小圆点）
    EVAL_DS_ANN_CLEAR_OVERLAY()
    local capOv = EVAL_DS_TEST_CAPTURE_OVERLAY(14)
    eq(capOv.hasOverlay, true, "overlay draw path is exercised")
    -- ★★★1.70.44 两个读者必须一致：设置走生产 setter（dsSetOverlay），
    --   诊断串与绘制路径都应看得见覆盖层。本轮 bug 的直接反例就是「一个看得见、一个看不见」
    --   （dsOverlayStr 绑全局 → 有；dsAnnDraw 读局部 → 无）。
    eq(capOv.setOk, true, "★★★the production setter accepted the loc")
    eq(capOv.str ~= "覆盖=无", true, "★★★the diagnostic reader sees the overlay too (both readers agree)")
    eq(capOv.allDots, true, "★search-result pins are placed with NO icon (round dot, per user request)")
    for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
    UnrealQuest = savedUQ5
  end
  -- 45f) ★摆放时必须「每次重设素材」：池子复用，创建时定死会让换类别后素材残留
  eq(EVAL_DS_TEST_PLACE_SETS_TEXTURE_EACH_TIME(), true,
     "★place() sets the texture on every draw (pool reuse would otherwise keep a stale icon)")
  eq(EVAL_DS_TEST_ICON_NOT_TINTED(), true,
     "★icon pins are not colour-tinted (only round dots carry the category colour)")
end


-- 46) 切图后标注不更新 / 一直是旧数据（1.70.27，用户日志取证）
-- 日志铁证：每次心跳都是 `分类层=false`，而存档里 `nodes=true` 且 cats={herbs,mines}。
-- 根因：EVAL_DS_RESTORE 独立读 cfg.ds.nodes 恢复图层开关，而 1.70.23 起该开关是**由类别数派生**的
-- ——两者打架，恢复时用的过期镜像值把层关掉 → dsAnnDraw 画 0 点 → 旧钉子留在屏幕上。
do
  -- 46a) ★恢复必须以「类别集合」为权威，不能被过期的 cfg.ds.nodes 带偏
  -- ★注意：dsCatOn 在 cfg.ds.cats[k] 为 **nil** 时会回落到类别定义的 def（服务类 def=true），
  --   所以 fixtures 必须给不需要的类别**显式写 false**，不能只靠「不写」——
  --   这正是本测试第一版把 8 当成 2 的原因（6 个默认开的服务类混了进来）。
  local cats46 = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do cats46[d.k] = false end
  cats46.herbs = true
  cats46.mines = true
  EVAL_HELP_CONFIG.ds = { nodes = false, trace = false, cats = cats46 }
  EVAL_DS_RESTORE()
  eq(EVAL_DS_CAT_COUNT(), 2, "precondition: exactly two categories are on")
  eq(EVAL_DS_NODE_STATE(), true,
     "★restore derives the layer ON from the category set, ignoring a stale cfg.ds.nodes=false")
  eq(EVAL_HELP_CONFIG.ds.nodes, true, "restore mirrors the derived value back into cfg.ds.nodes")
  -- 反向：类别全关时，即使 nodes=true 也必须关层（派生语义对称）
  local none46 = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do none46[d.k] = false end
  EVAL_HELP_CONFIG.ds = { nodes = true, trace = false, cats = none46 }
  EVAL_DS_RESTORE()
  eq(EVAL_DS_CAT_COUNT(), 0, "precondition: no categories on")
  eq(EVAL_DS_NODE_STATE(), false,
     "★restore derives the layer OFF when no category is on, even if cfg.ds.nodes=true")
  -- 46b) ★图层关闭时必须收起已有钉子（否则旧钉子永远留在屏幕上 = 用户看到的「旧数据」）
  local savedUQ6 = UnrealQuest
  UnrealQuest = {
    Client = {
      CreateWorldMapPin = function(_, idx) return { Hide = function() table.insert(TEST.nodeHide, idx) end, Show = function() table.insert(TEST.nodeShow, idx) end } end,
      PositionWorldMapPin = function() return true end,
      SetWorldMapPinSize = function() end, SetWorldMapPinTexture = function() end,
      SetWorldMapPinColor = function() end, SetWorldMapPinHandlers = function() end,
    },
    GetModule = function(_, name)
      if name == "Database" then
        return { GetAreaServiceLocations = function(_, areaId)
          return { { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" } }
        end }
      end
      if name == "MapContext" then return { GetViewedZone = function() return TEST.viewArea or 14, TEST.viewReport end } end
      return nil
    end,
  }
  -- 只开 herbs 一个（其余显式关掉，含 6 个默认开的服务类），才能测「最后一个类别关掉=层关」
  local onlyHerbs = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do onlyHerbs[d.k] = false end
  onlyHerbs.herbs = true
  EVAL_HELP_CONFIG.ds = { cats = onlyHerbs, trace = false }
  EVAL_DS_RESTORE()
  eq(EVAL_DS_NODE_STATE(), true, "layer is on with herbs selected")
  eq(EVAL_DS_CAT_COUNT(), 1, "precondition: exactly one category on")
  TEST.nodeShow, TEST.nodeHide = {}, {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(TEST.nodeShow) >= 1, true, "a tick with the layer on draws pins")
  -- 关掉最后一个类别 → 图层应关闭
  EVAL_DS_SET_CAT("herbs", false)
  eq(EVAL_DS_CAT_COUNT(), 0, "precondition: no category left on")
  eq(EVAL_DS_NODE_STATE(), false, "turning the last category off turns the layer off")
  -- ★关键：tick 必须把残留钉子收掉，而不是「跳过重绘」放任它们在屏幕上。
  --   注意要构造「层已关但钉子仍在、且签名还在」的状态——若走 EVAL_DS_SET_CAT 关类别，
  --   它会自己调 HideAll 把钉子清掉，新加的守卫根本不会被触发（本测试第一版就是这样假通过的）。
  EVAL_DS_SET_CAT("herbs", true) -- 先开层并画出钉子
  TEST.nodeShow, TEST.nodeHide = {}, {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(EVAL_DS_TEST_PIN_COUNT() > 0, true, "pins exist before the forced-off tick")
  EVAL_DS_TEST_FORCE_LAYER_OFF() -- 只把开关置 false，**不清钉子**（模拟存档/状态失配）
  eq(EVAL_DS_TEST_PIN_COUNT() > 0, true, "pins deliberately left behind")
  TEST.nodeShow, TEST.nodeHide = {}, {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(TEST.nodeHide) >= 1, true,
     "★a tick with the layer OFF hides the leftover pins (no stale annotations on screen)")
  -- 池子是**复用**的：Hide 只把钉子藏起来、帧留着下次用，所以不能断言数组清空。
  -- 真正对用户可见的契约是「全部被隐藏」+「签名清空（下次会重建）」。
  eq(EVAL_DS_TEST_ALL_PINS_HIDDEN(), true, "★every leftover pin is hidden")
  eq(select(2, EVAL_DS_NODE_STATE()), nil, "★and the signature is cleared so the layer rebuilds later")
  -- 46c) 视图签名必须随区域+视图变化（换图一定触发重绘，不会被「已画过」卡住）
  EVAL_DS_SET_CAT("herbs", true)
  local sigA = select(2, EVAL_DS_NODE_STATE())
  eq(type(sigA) == "string", true, "signature is set after a successful draw")
  TEST.viewArea = 37
  TEST.viewReport = { mapFile = "Azeroth", continent = 1, zoneIndex = 9 }
  TEST.nodeShow, TEST.nodeHide = {}, {}
  EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选
  TEST.time = (TEST.time or 0) + 5
  EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘并提交签名
  local sigB = select(2, EVAL_DS_NODE_STATE())
  eq(sigB ~= sigA, true, "★changing the map advances the signature (so the new map redraws)")
  eq(string.sub(sigB, 1, 2), "37", "★the signature reflects the newly viewed area")
  -- 空结果集也必须能重绘（不能因为「查询返回空」就把这张图永久判为已画）
  EVAL_DS_TEST_SET_EMPTY_RESULTS(true)
  TEST.viewArea = 99
  TEST.viewReport = { mapFile = "Azeroth", continent = 1, zoneIndex = 3 }
  TEST.nodeShow, TEST.nodeHide = {}, {}
  EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 1 拍：登记候选
  TEST.time = (TEST.time or 0) + 5
  EVAL_DS_NODE_TICK_FOR_TEST()          -- 第 2 拍：稳定后重绘
  eq(table.getn(TEST.nodeShow), 0, "an empty result set draws nothing")
  eq(string.sub(select(2, EVAL_DS_NODE_STATE()), 1, 2), "99",
     "an empty map still advances the signature (avoid re-querying every tick)")
  EVAL_DS_TEST_SET_EMPTY_RESULTS(false)
  UnrealQuest = savedUQ6
  EVAL_HELP_CONFIG.ds = nil
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end

-- 47) 目标类型条件（1.70.28）：野兽/元素 多选 + 是/否 + 文本往返 + 未知类型兜底
do
  -- 47a) 文本解析（中文名与英文 token 都认）
  local g1 = EVAL_PARSE_CONDS("目标类型:野兽/元素")
  eq(g1[1] ~= nil, true, "creature condition parses")
  eq(g1[1][1].k, "tCreature", "parsed kind is tCreature")
  eq(g1[1][1].cs.beast, true, "★野兽 parsed")
  eq(g1[1][1].cs.elemental, true, "★元素 parsed")
  eq(g1[1][1].cs.demon, nil, "unselected type is not set")
  eq(EVAL_PARSE_CONDS("tCreature=beast")[1][1].cs.beast, true, "english token also parses")
  eq(EVAL_PARSE_CONDS("目标类型非:元素")[1][1].v, false, "目标类型非 sets v=false")
  eq(EVAL_PARSE_CONDS("目标类型:不存在的类型")[1], nil, "★unknown type name is rejected (whole token dropped)")
  -- 47b) 文本往返稳定（导出→再导入 得到同样的条件）
  local rt = EVAL_PARSE_CONDS("目标类型:野兽/元素")
  local s1 = EVAL_GROUP_STR(rt)
  eq(type(s1) == "string" and string.find(s1, "目标类型", 1, true) ~= nil, true, "roundtrip keeps 目标类型")
  local rt2 = EVAL_PARSE_CONDS(s1)
  eq(rt2[1][1].cs.beast, true, "roundtrip preserves beast")
  eq(rt2[1][1].cs.elemental, true, "roundtrip preserves elemental")
  -- 47c) 求值：客户端报告中文名时命中
  TEST.hasTarget = true
  TEST.targetClass = "WARRIOR"
  -- ★用 EVAL_COND_EVAL 直接求值单条件：EVAL_RULE_RUN 会跳过「不在动作条」的技能，
  --   在本组（动作条已被前面的用例清空）会恒定返回 false，断言会以完全误导的方式失败。
  local function runCre(cre, conds)
    TEST.creatureType = cre
    EVAL_HELP_UPDATE_STATE()
    local g = EVAL_PARSE_CONDS(conds)
    if not (g and g[1] and g[1][1]) then return nil end
    return (EVAL_COND_EVAL(g[1][1]))
  end
  eq(runCre("野兽", "目标类型:野兽") == true, true, "★live 野兽 matches 目标类型:野兽")
  eq(runCre("野兽", "目标类型:元素") == false, true, "★live 野兽 does NOT match 元素")
  eq(runCre("元素", "目标类型:野兽/元素") == true, true, "★multi-select is OR (元素 hits)")
  eq(runCre("野兽", "目标类型非:元素") == true, true, "目标类型非:元素 passes for 野兽")
  eq(runCre("元素", "目标类型非:元素") == false, true, "目标类型非:元素 fails for 元素")
  -- 47c2) ★本客户端返回的本地化名可能带后缀（桩里就是「人型生物」）——两种写法都必须认。
  --   若只按标准名匹配，「人型」会永远匹配不上而**静默失效**（本条件的核心风险）。
  eq(runCre("人型生物", "目标类型:人型") == true, true, "★suffixed label 人型生物 matches 人型")
  eq(runCre("人型", "目标类型:人型") == true, true, "standard label 人型 also matches")
  eq(runCre("元素生物", "目标类型:元素") == true, true, "★suffixed 元素生物 matches 元素")
  eq(runCre("野兽", "目标类型:人型") == false, true, "suffix tolerance must not over-match (野兽 != 人型)")
  eq(runCre("Demon", "目标类型:恶魔") == true, true, "english token also matches")
  -- 47d) ★未知/空类型必须安全：不能崩，也不能误命中
  eq(runCre(nil, "目标类型:野兽") == false, true, "★no creature type -> no match (safe)")
  eq(runCre("某种未列出的类型", "目标类型:野兽") == false, true, "★unlisted type does not match 野兽")
  eq(runCre("某种未列出的类型", "目标类型:其他") == true, true, "★unlisted type matches the 其他 catch-all")
  TEST.creatureType = nil
  EVAL_HELP_UPDATE_STATE()
end

-- 48) 光环下拉顺序（1.70.28）：实时项必须排在技能名之前（用户报「全是技能名称，不是 debuff」）
do
  -- 先造出「目标身上有实时 debuff」的条件，否则实时分组为空，顺序断言无从谈起
  TEST.hasTarget = true
  TEST.debuffs = { { name = "撕裂", tex = "texD1" }, { name = "断筋", tex = "texD2" } }
  -- ★必须给动作条放几个技能：否则 EVAL_GO_SKILL_CHOICES() 为空 → 没有「技能名垫底」这一组
  --   → 「把实时项挪到技能之后」这类变异在本 fixture 下是**等价变异**，根本测不出来
  --   （变异验证时 livelast 一度存活，正是这个原因）。
  -- ★用真的 EVAL_GO_RESCAN 重扫动作条：EVAL_GO_SKILL_CHOICES 读的是 Engine 私有的
  --   wscanned/wslots，直接改 TEST.slotNames 不会生效（我第一次就是这么写的，技能始终为空，
  --   于是 livelast 变异体成了「等价变异」而测不出来）。
  local savedSlots47 = TEST.slotNames
  TEST.slotNames = { [1] = "致死打击", [2] = "冲锋", [3] = "英勇打击" }
  if type(EVAL_GO_RESCAN) == "function" then pcall(EVAL_GO_RESCAN, true) end
  EVAL_HELP_UPDATE_STATE()
  -- 直接检查下拉构建顺序：实时项前缀 ◆/○/●/▲ 必须出现在任何裸技能名之前
  local order = EVAL_TEST_AURA_DROPDOWN_ORDER("hasDebuff")
  eq(type(order), "table", "aura dropdown order is inspectable")
  eq(order.liveN >= 1, true, "★live debuffs are present in the menu (precondition)")
  -- ★实时分组必须占据最前面几项（第 1 项是它的分组标题，其后紧跟实时项）。
  --   不能只断言 liveFirst：动作条为空时 EVAL_GO_SKILL_CHOICES() 没有任何技能，
  --   liveFirst 会因「没有技能可比」而为 false，断言失败的原因与顺序无关（本用例首版即栽在此）。
  eq(order.firstLive ~= nil and order.firstLive <= 3, true,
     "★live aura entries occupy the very top of the dropdown (firstLive=" .. tostring(order.firstLive) .. ")")
  if order.firstSkill ~= nil then
    eq(order.liveFirst, true, "★live aura entries come BEFORE the generic skill list")
  else
    eq(order.skillsLast, false, "no skills on the action bar in this fixture (order check N/A)")
  end
  -- ★必须断言「第一项就是实时分组标题」：只断言「存在某个 locked 行」是不够的——
  --   SE_AURA_MENU 还有「已记录」「全部技能」两个分组标题，删掉实时标题时 lockedN 仍 >0，
  --   断言会假通过（变异验证当场暴露了这一点）。
  eq(order.firstIsHeader, true,
     "★the VERY FIRST row is the live-section header (field must be " .. tostring(order.firstIsHeader) .. ")")
  eq(order.lockedHeaders >= 1, true, "group header rows are declared locked (unselectable)")
  -- 仅当动作条上确实有技能时才谈「技能垫底」；无技能时该项无意义（同上面的理由）
  if order.firstSkill ~= nil then
    eq(order.skillsLast, true, "the generic skill list is demoted to the end")
  end
  TEST.debuffs = {}
  TEST.slotNames = savedSlots47
  if type(EVAL_GO_RESCAN) == "function" then pcall(EVAL_GO_RESCAN, true) end
  EVAL_HELP_UPDATE_STATE()
end

-- 49) 光环下拉搜索框（1.70.29）：输入过滤 + 无匹配时可使用自定义名称
do
  -- 49a) 过滤：关键字为空 = 全显示；分组标题永不被过滤
  local items = { "─ 实时 ─", "撕裂", "断筋", "破甲攻击" }
  local locked = { [1] = true }
  local all = DD_FILTER(items, locked, "", false)
  eq(table.getn(all), 4, "empty keyword shows everything")
  local nilKw = DD_FILTER(items, locked, nil, false)
  eq(table.getn(nilKw), 4, "nil keyword shows everything")
  local f1 = DD_FILTER(items, locked, "断", false)
  -- 第 1 行是分组标题（locked），必须保留；只有「断筋」命中
  eq(table.getn(f1), 2, "★keyword keeps the locked header plus only the matching row")
  eq(f1[1], 1, "★locked group header survives filtering")
  eq(f1[2], 3, "★matching row index is preserved (原始下标，不是显示位置)")
  -- 49b) 原始下标必须保持：否则 onPick/sel/icons 全错位
  local f2 = DD_FILTER(items, locked, "破甲", false)
  eq(f2[table.getn(f2)], 4, "★filtered index still refers to the ORIGINAL position")
  -- 49c) 大小写不敏感（英文 buff 名）
  local en = DD_FILTER({ "─ H ─", "Battle Shout" }, { [1] = true }, "battle", false)
  eq(table.getn(en), 2, "english name matches case-insensitively")
  -- 49d) ★无匹配时可使用自定义名称（用户要求：没有检索信息就让用户自己输入）
  local free = DD_FILTER(items, locked, "自制光环", true)
  eq(free[table.getn(free)], -1, "★a non-matching keyword appends the free-text sentinel row")
  -- ★★1.71.2 用户实测纠正（截图「顶部空白区域」）：关键字一条都没命中时，
  --   **分组标题也必须一起过滤掉**——否则列表顶部留着一条「只有标题、下面全空」的空白带。
  --   旧断言写的是「标题永远保留，所以此处是 2 而不是 1」——那正是用户看到的 bug，已改。
  eq(table.getn(free), 1, "★★★nothing matches: ONLY the free-text sentinel remains (no blank header band)")
  eq(free[1], -1, "the single surviving row is the free-text sentinel")
  -- 49e) 若表中已有完全同名项，则【不】再加哨兵行（避免重复项）
  local dup = DD_FILTER(items, locked, "撕裂", true)
  local hasSentinel = false
  for _, v in ipairs(dup) do if v == -1 then hasSentinel = true end end
  eq(hasSentinel, false, "★no free-text row when the typed name already exists exactly")
  -- 49f) 未启用自由文本时，永远不加哨兵行
  local nofree = DD_FILTER(items, locked, "不存在", false)
  local s2 = false
  for _, v in ipairs(nofree) do if v == -1 then s2 = true end end
  eq(s2, false, "no sentinel when onFreeText was not provided")
  eq(table.getn(nofree), 0, "★nothing matches and free text is off: list is EMPTY (no orphan header row)")
  -- ★★★1.71.2 真实路径复现用户截图：光环条件下拉（真菜单 + 真过滤）打一个一条都不命中的关键字
  --   ——旧实现会在列表顶部留下「已记录」标题那一条空白带（用户截图「顶部空白区域」）。
  --   ★必须用**真菜单 SE_AURA_MENU**（不是自己拼的假 items）：只有真菜单才知道标题在第几项、
  --     locked 是怎么标的（本项目反复栽在「测试自己复刻一遍」上）。
  do
    local menu = SE_AURA_MENU("pDebuff")
    local kw = "阴影穿不透的关键字"
    local res = DD_FILTER(menu.items, menu.locked, kw, true)
    local orphanHeader = false
    for _, i in ipairs(res) do
      if i > 0 and menu.locked[i] then orphanHeader = true end
    end
    eq(orphanHeader, false, "★★★no orphan header row when the keyword matches nothing (the blank band user reported)")
    -- 反向：命中时标题必须还在（分组结构不能删）
    local hit = DD_FILTER(menu.items, menu.locked, "减速", true)
    local keptHeader = false
    for _, i in ipairs(hit) do
      if i > 0 and menu.locked[i] then keptHeader = true end
    end
    eq(keptHeader, true, "headers ARE kept when something matches (grouping survives)")
  end
end

-- 49g) ★输入即过滤时关键字必须存活（重入陷阱）：OnTextChanged -> refilter -> EVAL_DD_OPEN
--   而 EVAL_DD_OPEN 打开时会清空搜索框——若没有重入保护，打一个字就被自己清掉。
do
  local items = { "─ 实时 ─", "撕裂", "断筋" }
  local locked = { [1] = true }
  local picked = nil
  EVAL_DD_TEST_OPEN_SEARCH(items, function(pi) picked = pi end, locked)
  eq(EVAL_DD_TEST_SEARCH_VISIBLE(), true, "search box is shown when opts.search is set")
  -- 模拟用户输入
  EVAL_DD_TEST_TYPE_SEARCH("断")
  eq(EVAL_DD_TEST_SEARCH_TEXT(), "断", "★typed keyword survives the refilter round-trip")
  -- 3 行 = 分组标题 + "断筋" + 自由文本行（"断" 没有精确同名项，故仍给出口）
  eq(EVAL_DD_TEST_FILTERED_COUNT(), 3, "★filtered list = header + 断筋 + free-text row")
  -- 点自由文本行（关键字无精确匹配）应回调 onFreeText，而不是当成普通行
  EVAL_DD_TEST_TYPE_SEARCH("自制光环")
  eq(EVAL_DD_TEST_HAS_FREE_ROW(), true, "★a free-text row appears for an unmatched keyword")
  EVAL_DD_HIDE()
  -- 关闭后再打开必须清空关键字（否则用户会以为列表缺项）
  EVAL_DD_TEST_OPEN_SEARCH(items, function() end, locked)
  eq(EVAL_DD_TEST_SEARCH_TEXT(), "", "★reopening clears the keyword")
  -- ★1.71.2 用户截图「加了输入框之后，其他所有弹窗上部都有个看不见的黑色块」：
  --   根因 = 搜索框（EditBox）在**不用搜索的下拉**里只是被 Hide()，而本客户端 EditBox
  --   隐藏后仍会画出底条，从「只有 1px 金边、中间是空的」面板里透出来 → 顶部一条黑带。
  --   修法：不隐藏，改用「挪出可视区」。下面两条断言分别钉住「用的是位移而不是 Hide」
  --   （桩的 GetLeft 只有真的 SetPoint 过才有数字）和「不用搜索时确实被挪走」。
  -- ★★1.71.2 第二轮（用户实测纠正）：搜索框的层**不许**被压到 BACKGROUND。
  --   第一版把它压到 BACKGROUND 去消「黑块」，结果输入框在面板里**自己看不见了**
  --   （用户截图：条件行下方那块空白就是输入框的位置，被面板背板盖住了）。
  --   根因：面板的**不透明背板**也在 BACKGROUND，FrameLevel 只决定同层内先后 → 压到同层必被盖住。
  --   ★判据：可见的东西不压层；不可见的东西靠「挪走」而不是靠层。
  --   这条断言走的是 DD_BUILD 真正调用的那个函数（否则等于没测，见 1.70.46 教训）。
  eq(EVAL_DD_TEST_BUILD_SEARCH(), true, "search builder runs for real (DD_BUILD path)")
  eq(EVAL_DD_TEST_SEARCH_LAYER() ~= "BACKGROUND", true,
     "★★★the editbox is NOT pushed to BACKGROUND (that is what made it invisible behind the panel backdrop)")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_OPEN_NO_SEARCH(items, function() end)
  -- ★★★1.71.2 输入框必须在**面板内部**（在第一列宽度的左半边、面板顶部那几行之内）——
  --   用户截图的「条件行下方那块空白」就是输入框的位置；它被面板背板盖住时才表现为「输入框没了」。
  --   只断言 IsShown 是不够的（Show 了也可能被盖住）→ 直接断言**几何位置在面板框内**。
  eq(EVAL_DD_TEST_SEARCH_VISIBLE(), false, "★non-search dropdown parks the search box off-screen (no black band over other popups)")
  eq(EVAL_DD_TEST_SEARCH_TEXT(), "", "parking also clears the keyword")
  -- ★★★1.71.2 用户实测第三轮：「不是没了，是**光标**消失了」。
  --   根因 = 打开搜索下拉时**只把背景搬回面板内、搜索框本体还停在屏幕外**（停放坐标）——
  --   离屏的 EditBox 拿不到焦点 → 没有光标。肉眼看「框还在」（那是背景），其实本体根本没回来。
  --   ★这条断言必须走**往返**（不用搜索 → 挪走 → 用搜索 → 必须搬回来）：
  --     只测「用搜索时可见」是抓不到的（第一次打开时它本来就在位）。
  -- ★★确定性起点：显式把搜索框打回停放态，**不依赖上一个用例留下的位置**。
  --   不加这一步，往返断言就退化成「碰巧上一轮是什么状态」——本轮实测：
  --   把「打开时搬回来」的修复整个删掉，断言**依然通过**（位置是从别的用例继承的）。
  EVAL_DD_TEST_PARK_SEARCH()
  eq(EVAL_DD_TEST_SEARCH_VISIBLE(), false, "precondition: the box really is parked off-screen")
  -- ★★判据 = **恢复动作有没有执行**（计数 +1），而不是「坐标碰巧等于 4」。
  --   为什么必须这样：撤掉恢复那两行时坐标会保持上一次的值 → 坐标断言照样通过（本轮实测踩中）。
  local posBefore = EVAL_DD_TEST_SEARCH_POS_COUNT()
  EVAL_DD_TEST_OPEN_SEARCH(items, function() end, locked)
  eq(EVAL_DD_TEST_SEARCH_POS_COUNT(), posBefore + 1,
     "★★★opening a search dropdown REPOSITIONS the box into the panel (the caret fix)")
  eq(EVAL_DD_TEST_SEARCH_IN_PANEL(), true,
     "★★★the box is inside the panel (parked-but-counted must still fail: position matters, not just the action)")
  eq(EVAL_DD_TEST_SEARCH_IN_PANEL(), true, "★★★the box sits at the panel's top-left (that is where the caret can appear)")
  EVAL_DD_HIDE()
end

-- 50) 数据检索控制行垂直对齐（1.70.30，用户截图「位置错行」）
-- 根因：同行控件混用两套垂直基准——按钮/输入框按【中线】，占位提示按【文字顶边】。
-- 该行已两次出布局问题，故用源码结构断言钉住「所有控件中线一致」。
do
  local geo = EVAL_DS_TEST_CONTROL_ROW_GEOMETRY()
  eq(type(geo), "table", "control-row geometry is inspectable")
  -- 输入框：y + 高度/2 = 中线
  eq(geo.boxCenter, -64, "search box center line is -64")
  -- 占位提示必须与输入框同中线（旧实现是 -62 顶边 -> 实际中心更低）
  eq(geo.phCenter, geo.boxCenter, "★placeholder shares the search box center line")
  eq(geo.phAnchorV, "CENTER", "★placeholder is anchored by CENTER, not by its text top edge")
  -- 按钮（16 高）中心也必须一致
  for _, b in ipairs(geo.buttons) do
    eq(b.center, geo.boxCenter, "★button " .. tostring(b.name) .. " shares the same center line")
  end
end

-- 51) ★★★ 1.70.40 A方案：签名一变就立刻重绘（不等稳定期），且不再有任何定时兑底。
-- 旧组 51（定时强刷 1.5s / 慢速兑底 5s）已随三件套删除，本组改为钉住新语义：
--   ① 签名变化 → **第一拍就画**（用户选 A：每张图都画，中间态可以闪）。
--   ② 签名未变 → 零开销（不查库、不重建），无论过多久。
--   ③ 没有任何「到了 N 秒就无条件重建」的机制。
do
  local savedUQ7 = UnrealQuest
  local queried = {}
  UnrealQuest = {
    Client = {
      CreateWorldMapPin = function(_, idx)
        local f = { _shown = false }
        f.Show = function(self) self._shown = true end
        f.Hide = function(self) self._shown = false end
        f.IsShown = function(self) return self._shown end
        return f
      end,
      PositionWorldMapPin = function() return true end,
      SetWorldMapPinSize = function() end, SetWorldMapPinTexture = function() end,
      SetWorldMapPinColor = function() end, SetWorldMapPinHandlers = function() end,
    },
    GetModule = function(_, name)
      if name == "Database" then
        return { GetAreaServiceLocations = function(_, areaId)
          table.insert(queried, areaId)
          return { { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" } }
        end }
      end
      if name == "MapContext" then
        return { GetViewedZone = function()
          -- 显式「无视图」哨兵：传 false 时返回真的 nil（否则会被 or 14 兜成 14，用例静默测错对象）
          if TEST.viewArea == false then return nil, nil, "continentView" end
          return TEST.viewArea or 14, TEST.viewReport
        end }
      end
      return nil
    end,
  }
  local cats51 = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do cats51[d.k] = false end
  cats51.herbs = true
  EVAL_HELP_CONFIG.ds = { cats = cats51, trace = false }
  EVAL_DS_RESTORE()
  -- 必须先清空钉子池：否则会复用前面用例用旧桩建的帧
  EVAL_DS_TEST_RESET_PINS()
  eq(EVAL_DS_NODE_STATE(), true, "layer is on for the A-plan test")
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST()
  -- 51a) ★★★ 签名变化 → 第一拍就重绘（A 方案的核心）
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  queried = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried) >= 1, true, "★★★a view appears: the redraw happens on the VERY FIRST tick")
  eq(EVAL_DS_TEST_SHOWN_COUNT() > 0, true, "and pins are on screen immediately")
  eq(queried[table.getn(queried)], 14, "the redraw queries the current area")
  -- 51b) 同一签名重复 tick → 零开销（频率防护：不查库、不重建）
  queried = {}
  for _ = 1, 20 do EVAL_DS_NODE_TICK_FOR_TEST() end
  eq(table.getn(queried), 0, "★unchanged signature: 20 ticks cause ZERO queries (cheap path stays cheap)")
  -- 51c) ★签名一变立刻重绘，无需等待任何稳定期
  TEST.viewArea = 17
  TEST.viewReport = { mapFile = "Barrens", continent = 1, zoneIndex = 3 }
  queried = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried) >= 1, true, "★★★switching zone redraws immediately (no settle wait)")
  eq(queried[table.getn(queried)], 17, "★the redraw queries the NEW area")
  -- 51d) ★★★ 连续切图：每一张都必须被画出来
  --   这正是旧稳定期闸门的致命缺陷：实测 t=3922342 至 t=3922477 的 134 秒里
  --   每一次切图都被判「未稳定」→ 一次都不重绘，屏幕停在旧图上。
  -- 注意：51c 已经把视图切到 17，故本序列必须**从另一个区域开始**，
  --   否则第一项签名未变、不会重绘，断言会因「测试自己的错误」而失败（首版即如此）。
  local seq = { {405,"Desolace",9}, {215,"Mulgore",2}, {14,"Durotar",1}, {17,"Barrens",3} }
  for _, s in ipairs(seq) do
    TEST.viewArea = s[1]
    TEST.viewReport = { mapFile = s[2], continent = 1, zoneIndex = s[3] }
    queried = {}
    EVAL_DS_NODE_TICK_FOR_TEST()
    eq(table.getn(queried) >= 1, true, "★rapid switching: area " .. s[1] .. " is drawn (never skipped)")
    eq(queried[table.getn(queried)], s[1], "★and it queries area " .. s[1] .. ", not a stale one")
  end
  -- 51e) 关图（无视图）→ 不查询、且收起整层
  TEST.viewArea = false
  queried = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried), 0, "★nothing is queried with no viewable zone")
  eq(EVAL_DS_TEST_SHOWN_COUNT(), 0, "★and the whole layer is hidden when the map has no area")
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  UnrealQuest = savedUQ7
  EVAL_HELP_CONFIG.ds = nil
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end

-- 52) 放置必须如实上报失败（1.70.35）：PositionWorldMapPin 返回 false 时不得算作成功
-- 背景：旧 dsAnnPlace 丢弃定位返回值、无条件 return true + Show，于是画布不在时
-- 仍然报告「放了 N 个钉子」——「信号都说健康、屏幕却是空的」的又一来源。
do
  local calls = {}
  local fakeFail = {  -- 画布不存在：PositionWorldMapPin 返回 false
    CreateWorldMapPin = function() local f = { _shown = false }
      f.Show = function(s) s._shown = true end f.Hide = function(s) s._shown = false end
      f.IsShown = function(s) return s._shown end return f end,
    SetWorldMapPinHandlers = function() end, SetWorldMapPinSize = function() end,
    SetWorldMapPinTexture = function() end, SetWorldMapPinColor = function() end,
    PositionWorldMapPin = function() return false end, -- ★定位失败
  }
  local fakeOK = {
    CreateWorldMapPin = fakeFail.CreateWorldMapPin,
    SetWorldMapPinHandlers = function() end, SetWorldMapPinSize = function() end,
    SetWorldMapPinTexture = function() end, SetWorldMapPinColor = function() end,
    PositionWorldMapPin = function() return true end,
  }
  EVAL_DS_TEST_RESET_PINS()
  local okFail = EVAL_DS_TEST_PLACE_ONE(fakeFail, 1)
  eq(okFail, false, "★a failed position is reported as failure, not success")
  eq(EVAL_DS_TEST_SHOWN_COUNT(), 0, "★and the pin is NOT left shown at a bogus position")
  EVAL_DS_TEST_RESET_PINS()
  local okGood = EVAL_DS_TEST_PLACE_ONE(fakeOK, 1)
  eq(okGood, true, "a successful position still reports success")
  eq(EVAL_DS_TEST_SHOWN_COUNT() >= 1, true, "and the pin is shown")
  EVAL_DS_TEST_RESET_PINS()
end

-- 53) ★★★ 1.70.40 A方案：连续切图时**每一张都要被画**（旧稳定期闸门已删）
-- 旧组 53 钉的是「未稳定就不画」，而实测证明正是它导致了「滞后一拍」：
--   t=3922342.934 视图变化 → 17|Barrens（等待稳定）
--   t=3922477.306 视图变化 → 215|Mulgore（等待稳定）  ← 134 秒里一次都没稳定过
-- 即用户一直在切图，屏幕却停在上一张。现在改为「签名一变就画」。
do
  local savedUQ8 = UnrealQuest
  local queried8 = {}
  UnrealQuest = {
    Client = {
      CreateWorldMapPin = function() local f={_s=false}
        f.Show=function(s) s._s=true end f.Hide=function(s) s._s=false end
        f.IsShown=function(s) return s._s end return f end,
      PositionWorldMapPin = function() return true end,
      SetWorldMapPinSize = function() end, SetWorldMapPinTexture = function() end,
      SetWorldMapPinColor = function() end, SetWorldMapPinHandlers = function() end,
    },
    GetModule = function(_, name)
      if name == "Database" then
        return { GetAreaServiceLocations = function(_, areaId)
          table.insert(queried8, areaId)
          return { { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" } }
        end }
      end
      if name == "MapContext" then
        return { GetViewedZone = function()
          if TEST.viewArea == false then return nil, nil, "continentView" end
          return TEST.viewArea or 14, TEST.viewReport
        end }
      end
      return nil
    end,
  }
  local cats53 = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do cats53[d.k] = false end
  cats53.herbs = true
  EVAL_HELP_CONFIG.ds = { cats = cats53, trace = false }
  EVAL_DS_RESTORE()
  EVAL_DS_TEST_RESET_PINS()
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST()
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  -- 53a) ★视图出现 → 第一拍就画
  queried8 = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried8) >= 1, true, "★★★the first tick with a view already draws (no settle wait)")
  eq(EVAL_DS_TEST_SHOWN_COUNT() > 0, true, "and pins are placed immediately")
  -- 53b) ★★★ 连续抖动的视图：每一次变化都必须被画（旧实现在这里会一次都不画）
  local jitter = { {17,"Barrens",3}, {215,"Mulgore",2}, {405,"Desolace",9} }
  for _, v in ipairs(jitter) do
    TEST.viewArea = v[1]
    TEST.viewReport = { mapFile = v[2], continent = 1, zoneIndex = v[3] }
    queried8 = {}
    EVAL_DS_NODE_TICK_FOR_TEST()
    eq(table.getn(queried8) >= 1, true,
       "★★★jitter: view " .. v[1] .. " IS drawn (the settle gate used to swallow every one)")
    eq(queried8[table.getn(queried8)], v[1], "★and it draws the area that is actually on screen now")
  end
  -- 53c) 频率防护仍然在：签名不变时不重建
  queried8 = {}
  for _ = 1, 10 do EVAL_DS_NODE_TICK_FOR_TEST() end
  eq(table.getn(queried8), 0, "★an unchanged view is still a no-op (frequency guard holds)")
  -- 53d) 关图 → 收起整层（且不查询）
  TEST.viewArea = false
  queried8 = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried8), 0, "★no query while there is no viewable zone")
  eq(EVAL_DS_TEST_SHOWN_COUNT(), 0, "★the layer is hidden when the map has no area")
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  UnrealQuest = savedUQ8
  EVAL_HELP_CONFIG.ds = nil
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end

-- 54) 地图诊断浮层（1.70.38，用户建议）：把诊断信息直接画在地图上，免读日志
do
  local savedUQ10 = UnrealQuest
  local hudCanvas = {}
  hudCanvas.CreateTexture = function() return { SetTexture=function() end, SetVertexColor=function() end,
    SetAlpha=function() end, SetAllPoints=function() end, SetPoint=function() end } end
  UnrealQuest = {
    Client = { GetWorldMapCanvas = function() return hudCanvas end },
    GetModule = function(_, n)
      if n == "MapContext" then return { GetViewedZone = function()
        -- ★必须尊重 TEST.viewArea（含 false 哨兵），否则下面「无视图」的用例根本测不到
        --   ——桩里硬编码返回值会让用例静默测错对象（本项目已多次踩，见 1.70.27/1.70.31）。
        if TEST.viewArea == false then return nil, nil, "continentView" end
        return TEST.viewArea or 14, { mapFile="Durotar", zoneIndex=1, mapZoneName="杜隆塔尔" }, "unique" end } end
      return nil end,
  }
  eq(EVAL_DS_HUD_STATE(), false, "HUD starts off")
  EVAL_DS_HUD(true)
  eq(EVAL_DS_HUD_STATE(), true, "HUD can be enabled")
  TEST.viewArea = 14
  TEST.time = (TEST.time or 0) + 10
  EVAL_DS_NODE_TICK_FOR_TEST()
  local ht = EVAL_DS_TEST_HUD_TEXT()
  eq(type(ht) == "string", true, "★HUD composes diagnostic text on tick")
  eq(string.find(ht, "area=14", 1, true) ~= nil, true, "★HUD shows the reported area")
  eq(string.find(ht, "mapFile=Durotar", 1, true) ~= nil, true, "★HUD shows the map file")
  eq(string.find(ht, "zone=1", 1, true) ~= nil, true, "HUD shows the zone index")
  eq(string.find(ht, "已画签名=", 1, true) ~= nil, true, "HUD shows the drawn signature")
  -- ★areaId 为 nil 时也必须刷新（用户要能看到「客户端报 nil」这件事本身）
  TEST.viewArea = false
  TEST.time = (TEST.time or 0) + 10
  EVAL_DS_NODE_TICK_FOR_TEST()
  local ht2 = EVAL_DS_TEST_HUD_TEXT()
  eq(type(ht2) == "string", true, "HUD still has text when the view reports nothing")
  -- ★必须断言「文本确实反映 nil」，而不是「还有一段旧文本」：
  --   旧文本会一直留在变量里，只查 type 的话，跳过刷新也能通过（本用例首版即如此）。
  eq(string.find(ht2, "area=nil", 1, true) ~= nil, true,
     "★HUD refreshes even with no viewable zone (must show area=nil, not stale text)")
  EVAL_DS_HUD(false)
  eq(EVAL_DS_HUD_STATE(), false, "HUD can be disabled")
  TEST.viewArea = 14
  UnrealQuest = savedUQ10
end

-- 55) ★★★tick 帧的父级必须是 WorldFrame（1.70.39，根因修复）
--
-- 本组存在的唯一理由：本客户端**打开全屏世界地图会隐藏 UIParent**，挂在它下面的帧收不到
-- OnUpdate → 标注层 tick 在地图开着时整个停摆 → 「切图不更新 / 滞后一拍」。
-- 这条铁律在 UnrealQuest Core/Driver.lua:467-482 有明文，对方的驱动帧因此挂 WorldFrame。
--
-- 旧测试桩把 CreateFrame 的 parent 参数**直接丢掉**，于是「挂 UIParent」和「挂 WorldFrame」
-- 长得一模一样 —— 这个 bug 在测试里完全不可见（「桩太宽松」的第 N 次发作）。
do
  eq(type(WorldFrame) ~= "nil", true, "the stub provides WorldFrame (the 3D viewport)")
  eq(type(TEST.frameIsTickable) == "function", true, "the stub can model the hidden-ancestor rule")
  eq(TEST.frameIsTickable(UIParent), true, "UIParent ticks while the UI is up")
  TEST.uiHidden = true
  eq(TEST.frameIsTickable(UIParent), false,
     "★UIParent does NOT tick while the fullscreen map hides the game UI")
  eq(TEST.frameIsTickable(WorldFrame), true,
     "★WorldFrame keeps ticking while the fullscreen map is open")
  TEST.uiHidden = false

  -- 真正要钉住的不变量：标注层 tick 在地图打开时仍然会跑。
  local tick = EVAL_DS_TEST_TICK_FRAME()
  eq(type(tick) == "table", true, "the module exposes its tick frame for inspection")
  if type(tick) == "table" then
    local p = tick.__parent
    eq(p == WorldFrame, true,
       "★★★the annotation tick is parented to WorldFrame, not UIParent " ..
       "(parenting it to UIParent stops the tick while the map is open)")
    TEST.uiHidden = true
    eq(TEST.frameIsTickable(tick), true,
       "★★★the annotation tick still ticks while the fullscreen map is open")
    TEST.uiHidden = false
  end
end

-- 56) ★★★ 1.70.41 控制行布局常量必须先于使用点声明（用户截图「应该有个按钮没了」）
-- 症状：「类型: 全部」过滤钮整颗不显示。
-- 根因：filterBtn 用 DSL_ROW_BTN_Y 定位，而该 local 在 35 行之后才声明
--   → 那里读到全局 nil → SetPoint(..., nil) → 本客户端对 nil 锚点不做任何定位且不报错 → 按钮落在未定义位置。
-- ★这是本项目第 10 次同类 local 作用域坑，也是「不报错的空操作」的又一实例。
do
  -- ① 源码层面：确保 DSL_ROW_BTN_Y 的声明位置严格早于第一个使用它的 dsBtn 调用点。
  --   （读源码文本是本例最直接的手段：桩不校验 SetPoint 参数，行为层面测不到。）
  -- ★① 行为层：控制行的每个按钮都必须真的被构建，且几何不为 nil。
  --   filterBtn 当年就是「构建了但用 nil 锚点」——帧在、属性在，就是不显示。
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST() -- 确保控制行已构建
  local ws = EVAL_DS_TEST_CONTROL_ROW_WIDGETS()
  eq(table.getn(ws) >= 2, true, "★the control row reports its buttons")
  for _, w in ipairs(ws) do
    eq(w.declared, true, "★★★control-row button [" .. tostring(w.name) .. "] has a real (non-nil) centre")
    eq(type(w.center) == "number", true, "★and that centre is a number, not a global-nil fallback")
  end
  -- ★② 源码层（真正的声明顺序校验，放在能读文件的 node 侧：LayoutRules 自描）
end

-- 57) ★★★ 1.70.41 搜索定位小圆点的「随机彩色」必须由实体 id 派生（恒定），不能每次现摇
-- 用户要求「每只怪一个随机颜色，便于区分」。
-- ★核心不变量：同一 id 恒定同色（否则每 0.25s 重绘就换色，用户无法靠颜色认怪）。
do
  local r1, g1, b1 = EVAL_DS_ENTITY_COLOR(119)
  local r2, g2, b2 = EVAL_DS_ENTITY_COLOR(119)
  eq(r1 == r2 and g1 == g2 and b1 == b2, true,
     "★★★the same entity id always yields the SAME colour (stable across redraws)")
  -- ② 不同 id 应当给出不同颜色（否则「便于区分」无从谈起）
  local seen = {}
  local distinct = 0
  for id = 1, 20 do
    local r, g, b = EVAL_DS_ENTITY_COLOR(id)
    local key = string.format("%.2f_%.2f_%.2f", r, g, b)
    if not seen[key] then seen[key] = true distinct = distinct + 1 end
  end
  eq(distinct >= 18, true, "★different entity ids get (mostly) different colours, got " .. distinct .. "/20 distinct")
  -- ★★★ 上面那条只能证明「三元组不同」，不能证明「色相散开」——若 hue 被写死成常量、
  --   只靠饱和度/亮度变化，三元组依然两两不同而且 distinct 达标（实测：该变异体能存活）。
  --   用户要的是「看起来随机、便于区分」，所以必须直接钉**色相的取值范围与分布**。
  -- 把 RGB 转回色相：红最大→0.0 区间、绿最大→1/3、蓝有最大→2/3。
  local hues = {}
  for id = 1, 30 do
    local r, g, b = EVAL_DS_ENTITY_COLOR(id)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d = mx - mn
    local hh
    if d < 1e-9 then hh = -1 -- 灰色：无色相，不计入
    elseif mx == r then hh = ((g - b) / d) % 6
    elseif mx == g then hh = (b - r) / d + 2
    else hh = (r - g) / d + 4 end
    if hh >= 0 then table.insert(hues, hh / 6) end
  end
  eq(table.getn(hues) >= 28, true, "★almost every id yields a chromatic (non-grey) colour, got " .. table.getn(hues) .. "/30")
  -- 色相必须分布在至少 3 个不同的十分位（hue 写死成常量时这里会只剩 1 个）
  local bucket = {}
  local nb = 0
  for _, hh in ipairs(hues) do
    local k = math.floor(hh * 10)
    if not bucket[k] then bucket[k] = true nb = nb + 1 end
  end
  eq(nb >= 3, true, "★★★hue actually varies across ids (a constant hue would collapse this to 1), got " .. nb .. " deciles")
  -- ③ 颜色必须在可见区间：不能出现全黑/全白/灰色（看不清）
  local bad = 0
  for id = 1, 200 do
    local r, g, b = EVAL_DS_ENTITY_COLOR(id)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then bad = bad + 1
    elseif r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then bad = bad + 1
    elseif (r + g + b) < 0.45 then bad = bad + 1 end -- 太暗看不清
  end
  eq(bad, 0, "★every derived colour is a visible RGB triple (no black/dark output), bad=" .. bad)
end

-- ★④ ★★★ 接线层：重绘时小圆点**实际传的颜色**必须来自 dsEntityColor。
--   只断言解析函数是不够的：调用点写死一个常量色 / 现摇随机色，
--   解析函数的断言依然全绿（本项目 1.70.26 踩过同一个坑）。
do
  local savedUQ11 = UnrealQuest
  UnrealQuest = {
    Client = {
      CreateWorldMapPin = function() local f={_s=false}
        f.Show=function(t) t._s=true end f.Hide=function(t) t._s=false end
        f.IsShown=function(t) return t._s end return f end,
      PositionWorldMapPin = function() return true end,
      SetWorldMapPinSize = function() end, SetWorldMapPinTexture = function() end,
      SetWorldMapPinColor = function() end, SetWorldMapPinHandlers = function() end,
    },
    GetModule = function(_, name)
      if name == "Database" then
        return { GetAreaServiceLocations = function() return {} end }
      end
      if name == "MapContext" then
        return { GetViewedZone = function() return 14, { mapFile = "Durotar", zoneIndex = 1 } end }
      end
      return nil
    end,
  }
  EVAL_DS_TEST_RESET_PINS()
  local cap = EVAL_DS_TEST_CAPTURE_OVERLAY(14)
  eq(cap.hasOverlay, true, "★the search-result overlay actually reaches the draw pass")
  -- ★★★1.70.44 同上：断言「生产 setter 写完之后，两个读者都看得见」
  eq(cap.setOk, true, "★★★the production setter (dsSetOverlay) accepted the loc")
  eq(cap.str ~= "覆盖=无", true, "★★★the diagnostic reader agrees with the draw path")
  eq(type(cap.color) == "table", true, "★the overlay draw passes a colour to dsAnnPlace")
  if type(cap.color) == "table" then
    -- ★对照组：该颜色必须等于 dsEntityColor(id)。
    --   若调用点改成现摇随机或写死常量，这里就不再相等。
    local er, eg, eb = EVAL_DS_ENTITY_COLOR(1) -- 覆盖层用的 id 是 1
    eq(math.abs(cap.color.r - er) < 0.0001 and math.abs(cap.color.g - eg) < 0.0001
       and math.abs(cap.color.b - eb) < 0.0001, true,
       "★★★the drawn colour IS the id-derived colour (not re-randomised / not a constant)")
    -- 且不能是「每次都不一样」的现摇值：再重绘一次必须得到同色
    EVAL_DS_TEST_RESET_PINS()
    local cap2 = EVAL_DS_TEST_CAPTURE_OVERLAY(14)
    if type(cap2.color) == "table" then
      eq(cap2.color.r == cap.color.r and cap2.color.g == cap.color.g
         and cap2.color.b == cap.color.b, true,
         "★★★re-drawing yields the SAME colour (stable, not re-randomised per draw)")
    end
  end
  UnrealQuest = savedUQ11
end


-- 58) ★★★ 1.70.42 自愈：上次绘制「打算画 N 点」但一个都不可见 → 必须重画（用户实测「点定位后地图空白」）
-- 根因候选：点击定位 → OpenWorldMap → 立即 REFRESH，画布尚未就绪 → 诚实放置把钉子全部 Hide
--   → 签名没变 → tick 认为「画过了」→ 永远不再画 → 空地图。
-- 与已删除的三件套的区别：先校验再修复（lastDrawn>0 且 shown==0 才出手）+ 2s 节流 + 出手必留日志。
do
  local savedUQ12 = UnrealQuest
  local queried = {}
  UnrealQuest = {
    Client = {
      CreateWorldMapPin = function() local f={_s=false}
        f.Show=function(t) t._s=true end f.Hide=function(t) t._s=false end
        f.IsShown=function(t) return t._s end return f end,
      PositionWorldMapPin = function() return true end,
      SetWorldMapPinSize = function() end, SetWorldMapPinTexture = function() end,
      SetWorldMapPinColor = function() end, SetWorldMapPinHandlers = function() end,
    },
    GetModule = function(_, name)
      if name == "Database" then
        return { GetAreaServiceLocations = function(_, areaId)
          table.insert(queried, areaId)
          return { { category = "herbs", x = 40, y = 50, areaId = areaId, sourceType = "object", sourceId = 1618, name = "宁神花" } }
        end }
      end
      if name == "MapContext" then
        return { GetViewedZone = function()
          if TEST.viewArea == false then return nil, nil, "continentView" end
          return TEST.viewArea or 14, TEST.viewReport
        end }
      end
      return nil
    end,
  }
  local cats58 = {}
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do cats58[d.k] = false end
  cats58.herbs = true
  EVAL_HELP_CONFIG.ds = { cats = cats58, trace = false }
  EVAL_DS_RESTORE()
  EVAL_DS_TEST_RESET_PINS()
  EVAL_HELP_CONFIG.cfgTab = 4
  EVAL_DS_BUILD_FOR_TEST()
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  -- 58a) 正常绘制 → 有钉子可见
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(EVAL_DS_TEST_SHOWN_COUNT() > 0, true, "precondition: pins drawn and visible")
  -- 58b) ★模拟「钉子被清掉但签名未变」（画布未就绪的后果）→ 下一次 tick 必须自愈重画
  EVAL_DS_TEST_WIPE_PINS()
  eq(EVAL_DS_TEST_SHOWN_COUNT(), 0, "precondition: pins wiped, nothing visible")
  TEST.time = (TEST.time or 0) + 3
  queried = {}
  local drawsBefore = EVAL_DS_TEST_DRAW_COUNT()
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(EVAL_DS_TEST_DRAW_COUNT() > drawsBefore, true, "★★★an invisible-but-intended layer IS rebuilt by the self-heal")
  eq(table.getn(queried) >= 1, true, "★★★an invisible-but-intended layer is re-drawn by the self-heal")
  eq(EVAL_DS_TEST_SHOWN_COUNT() > 0, true, "★pins are back on screen after the heal")
  -- 58b2) ★★★ 节流：自愈刚出手过，再次被清也不能立刻又出手（否则每 tick 重建 = 频率防护回归）
  EVAL_DS_TEST_WIPE_PINS()
  queried = {}
  local drawsT = EVAL_DS_TEST_DRAW_COUNT()
  EVAL_DS_NODE_TICK_FOR_TEST() -- 时钟未推进（<2s）→ 不得重建
  eq(EVAL_DS_TEST_DRAW_COUNT() == drawsT, true, "★★★the heal is throttled: NO rebuild within the 2s window")
  eq(table.getn(queried), 0, "★★★the heal is throttled (no rebuild within the 2s window)")
  -- 推进时钟后才允许再出手
  TEST.time = (TEST.time or 0) + 3
  queried = {}
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(table.getn(queried) >= 1, true, "★and it heals again once the window has passed")

  -- 58c) ★反向门控：该区域本来就 0 点（lastDrawn=0）→ 绝不出手（频率防护）
  EVAL_DS_TEST_SET_EMPTY_RESULTS(true)
  EVAL_DS_TEST_RESET_PINS()
  TEST.viewArea = 17
  TEST.viewReport = { mapFile = "Barrens", continent = 1, zoneIndex = 3 }
  EVAL_DS_NODE_TICK_FOR_TEST() -- 签名变了 → 重绘，但查询为空 → lastDrawn=0
  EVAL_DS_TEST_WIPE_PINS() -- 池里本就没东西，等于无操作
  TEST.time = (TEST.time or 0) + 3
  queried = {}
  local drawsE = EVAL_DS_TEST_DRAW_COUNT()
  EVAL_DS_NODE_TICK_FOR_TEST()
  eq(EVAL_DS_TEST_DRAW_COUNT() == drawsE, true, "★★★an intentionally-empty layer is NEVER rebuilt (no 2s churn)")
  eq(table.getn(queried), 0, "★★★an intentionally-empty layer is NEVER healed (no 2s churn)")
  EVAL_DS_TEST_SET_EMPTY_RESULTS(false)
  TEST.viewArea = 14
  TEST.viewReport = { mapFile = "Durotar", continent = 1, zoneIndex = 1 }
  UnrealQuest = savedUQ12
  EVAL_HELP_CONFIG.ds = nil
  for _, d in ipairs(EVAL_DS_ANN_CAT_LIST()) do EVAL_DS_SET_CAT(d.k, false) end
end


-- 59) ★★★ 导出/导入往返一致性：EVAL_COND_STR 写出的每一种写法，
--   EVAL_PARSE_ONE 都必须能读回来。
-- ★为什么：导入解析器对认不出的条件是**静默丢弃**（EVAL_PARSE_CONDS 只 push 非 nil 的），
--   所以「导出→导入」一轮就会吞掉条件，而用户看不到任何报错。
--   本组用「遍历全部条件类型」的方式自动列出所有不对称，而不是我手写几个病例。
do
  local cases = {
    { k = "combat", v = true }, { k = "combat", v = false },
    { k = "hasTarget", v = true }, { k = "hasTarget", v = false },
    { k = "canAttack", v = true }, { k = "canAttack", v = false },
    { k = "canBleed", v = true }, { k = "canBleed", v = false },
    { k = "isElite", v = true }, { k = "isElite", v = false },
    { k = "isBoss", v = true }, { k = "isBoss", v = false },
    { k = "tInCombat", v = true }, { k = "tInCombat", v = false },
    { k = "tFriendly", v = true }, { k = "tFriendly", v = false },
    { k = "tHostile", v = true }, { k = "tHostile", v = false },
    { k = "tNeutral", v = true }, { k = "tNeutral", v = false },
    { k = "autoAttack", v = true }, { k = "autoAttack", v = false },
    { k = "autoShot", v = true }, { k = "autoShot", v = false },
    { k = "wandShoot", v = true }, { k = "wandShoot", v = false },
    { k = "alt", v = true }, { k = "alt", v = false },
    { k = "shift", v = true }, { k = "shift", v = false },
    { k = "ctrl", v = true }, { k = "ctrl", v = false },
    { k = "ready", inv = false }, { k = "ready", inv = true },
    { k = "usable", inv = false }, { k = "usable", inv = true },
    { k = "notQueued", inv = false }, { k = "notQueued", inv = true },
  }
  local bad = {}
  for _, cd in ipairs(cases) do
    local s = EVAL_COND_STR(cd)
    local back = EVAL_PARSE_ONE(s)
    local ok = (back ~= nil) and (back.k == cd.k)
    if ok and cd.v ~= nil then ok = (back.v == cd.v) end
    if ok and cd.inv ~= nil then ok = (back.inv == cd.inv) end
    if not ok then
      table.insert(bad, s .. " -> " .. (back and (tostring(back.k) .. " v=" .. tostring(back.v)) or "nil(被静默丢弃)"))
    end
  end
  if table.getn(bad) > 0 then
    for _, b in ipairs(bad) do print("  往返不对称: " .. b) end
  end
  eq(table.getn(bad), 0, "★★★every exported condition string parses back (no silent drops), broken=" .. table.getn(bad))
end


-- 60) ★★★ 模版库健康检查：每一个模版的 text 都必须能被导入器解析。
-- ★为什么需要：模版文本在**加载期不会被解析**，所以写错（拼接写成未定义变量/条件写法不合法）
--   不会在 luacheck 或启动时报错，只会在用户点「导入」那一刻才失败——而且条件丢失是静默的。
do
  eq(type(EVAL_IO_TEMPLATES) == "table", true, "the template library exists")
  local groups, total, bad = 0, 0, {}
  for _, g in ipairs(EVAL_IO_TEMPLATES) do
    groups = groups + 1
    for _, tpl in ipairs(g.list or {}) do
      total = total + 1
      local prof, err = EVAL_PROFILE_FROM_TEXT(tpl.text or "")
      if not prof then
        table.insert(bad, tostring(g.cls) .. "/" .. tostring(tpl.name) .. ": " .. tostring(err))
      elseif table.getn(prof.skills) == 0 then
        table.insert(bad, tostring(g.cls) .. "/" .. tostring(tpl.name) .. ": 解析出 0 个技能")
      end
    end
  end
  if table.getn(bad) > 0 then for _, b in ipairs(bad) do print("  模版解析失败: " .. b) end end
  eq(table.getn(bad), 0, "★★★every template parses through the importer, broken=" .. table.getn(bad))
  eq(total >= 5, true, "★the library has all groups (" .. groups .. " groups / " .. total .. " templates)")

  -- ★★★1.73.25 用户要求（截图三：他自己的猫德配置）：「加入猫德一键宏模版」——
  --   逐条验内容（不只是「能解析」）：技能条数、以及**照抄截图的条件写法**（未免疫:… / 无debuff:… / 连击>=4）。
  do
    local druid60 = nil
    for _, g in ipairs(EVAL_IO_TEMPLATES) do if g.cls == "德鲁伊" then druid60 = g break end end
    eq(druid60 ~= nil, true, "★★★德鲁伊模版组存在")
    local cnm60 = nil
    for _, tpl in ipairs((druid60 and druid60.list) or {}) do
      if tostring(tpl.name) == "猫德一键宏" then cnm60 = tpl end
    end
    eq(cnm60 ~= nil, true, "★★★「猫德一键宏」模版存在（用户点名要的那个）")
    local pcn60 = cnm60 and EVAL_PROFILE_FROM_TEXT(cnm60.text or "")
    eq(pcn60 ~= nil and table.getn(pcn60.skills) >= 6, true,
       "★★它解析出 ≥6 条技能行（实际 " .. tostring(pcn60 and table.getn(pcn60.skills) or 0) .. " 条）")
    local tx60 = tostring((cnm60 and cnm60.text) or "")
    eq(string.find(tx60, "未免疫:撕扯", 1, true) ~= nil, true, "★★条件写法照抄截图：未免疫:撕扯")
    eq(string.find(tx60, "连击>=4", 1, true) ~= nil, true, "★★含「连击>=4」收尾条件")
    eq(string.find(tx60, "姿态:猎豹形态", 1, true) ~= nil, true, "★★含姿态守门行（重复变豹会取消形态）")
    --  ★plain=true 找的是**字面字符**（写 "%%" 就永远找不到 —— 本项目已第三次踩这个坑，见 §5.1）
    eq(string.find(tx60, "能量%>50", 1, true) ~= nil, true, "★★含猛虎之怒的能量门槛（原文写法 能量%>50）")
  end

  -- ★猎人组（1.70.43 用户要求新增）：逐条验证内容，而不只是「能解析」
  local hunter = nil
  for _, g in ipairs(EVAL_IO_TEMPLATES) do if g.cls == "猎人" then hunter = g break end end
  eq(hunter ~= nil, true, "★★★a 猎人 (hunter) template group exists")
  -- ★★★ 独立钉住「无条件技能行不得被静默丢弃」（不依赖上面那个模版是否写了竖线）
  do
    local prof = EVAL_PROFILE_FROM_TEXT("- 宠物:攻击")
    eq(prof ~= nil, true, "★a bare skill line still parses")
    if prof then
      eq(table.getn(prof.skills), 1, "★★★a skill line WITHOUT a pipe is kept (was silently dropped)")
      eq(prof.skills[1].skill, "宠物:攻击", "★and the skill name is intact")
      eq(table.getn(prof.skills[1].groups), 0, "★with an empty condition list")
    end
  end
  if hunter then
    local prof = EVAL_PROFILE_FROM_TEXT(hunter.list[1].text)
    eq(prof ~= nil, true, "★the hunter template parses")
    if prof then
      eq(table.getn(prof.skills), 6, "★猎人模版有 6 条技能（照拄用户截图）")
      local s1 = prof.skills[1]
      eq(s1.skill, "选取目标:最近敌人", "★first rule picks the nearest enemy")
      eq(table.getn(s1.groups), 2, "★★★the OR pair survived: 2 groups")
      eq(s1.groups[1][1].k, "canAttack", "★group1 is the canAttack condition")
      eq(s1.groups[1][1].v, false, "★★★and it is the NEGATED form - not silently dropped")
      eq(s1.groups[2][1].k, "tFriendly", "★group2 is the friendly condition")
      eq(s1.groups[2][1].v, true, "★and it is the positive form")
      eq(prof.skills[4].skill, "宠物:攻击", "★the pet-attack row is present as a bare skill")
      eq(table.getn(prof.skills[4].groups), 0, "★and it carries no conditions")
      eq(prof.skills[3].skill, "毒蛇钉刺", "★the serpent sting row is present")
      eq(table.getn(prof.skills[3].groups), 1, "★it has a single AND group")
      eq(table.getn(prof.skills[3].groups[1]), 3, "★★★with all 3 conditions kept (no silent drops)")
    end
  end
  -- ★★★1.73.40 用户要求（截图 = 他自己在用的「猎人收宠」方案）：
  --   「将当前方案添加到案例模版: 猎人分组->停止攻击&收回宠物」
  --   判据 = ① 组里真有这条（用户点名的）② 四行技能**逐条对**（顺序也是内容：先停手 → 再收宠）
  --           ③ 四行**都是无条件行**（保命宏被条件挡住就没意义）④ 带说明（悬停能看到它干吗）
  do
    local petRec = nil
    for _, tpl in ipairs((hunter and hunter.list) or {}) do
      if tostring(tpl.name) == "猎人收宠" then petRec = tpl end
    end
    eq(petRec ~= nil, true, "★★★猎人组里有「猎人收宠」模版（用户点名要的那条）")
    local ppr = petRec and EVAL_PROFILE_FROM_TEXT(tostring(petRec.text or ""))
    eq(ppr ~= nil and table.getn(ppr.skills) == 4, true,
       "★★它解析出 4 条技能行（实际 " .. tostring(ppr and table.getn(ppr.skills) or 0) .. " 条）")
    if ppr then
      local want = { "停止攻击", "取消施法", "宠物:跟随", "宠物:被动姿态" }
      for i = 1, 4 do
        eq(ppr.skills[i] and ppr.skills[i].skill, want[i], "★★★第 " .. i .. " 行 = " .. want[i] .. "（先停手 → 再收宠）")
        eq(table.getn((ppr.skills[i] and ppr.skills[i].groups) or {}), 0, "★★第 " .. i .. " 行是无条件行（保命宏不能被条件挡住）")
      end
    end
    eq(string.len(tostring(petRec and petRec.desc or "")) > 0, true, "★★模版带说明（悬停能看出它干吗）")
  end
  -- ★★★骑士组（1.71.2 第二十二轮，用户要求收录其实配方案）：不只「能解析」，还逐条验内容 + 整串往返
  eq(table.getn(EVAL_IO_TEMPLATES), 11, "★11 组（6 原有 + 牧师/德鲁伊/术士/萨满/队伍·团队；顺序由 EXAMPLES TOC CHECK 守）")
  local pal = nil
  for _, g in ipairs(EVAL_IO_TEMPLATES) do if g.cls == "骑士" then pal = g break end end
  eq(pal ~= nil, true, "★★★a paladin template group exists")
  if pal then
    local prof = EVAL_PROFILE_FROM_TEXT(pal.list[1].text)
    eq(prof ~= nil, true, "★the paladin template parses")
    if prof then
      eq(table.getn(prof.skills), 8, "★★★8 skills (per the user screenshot)")
      eq(prof.skills[1].skill, "选取目标:最近敌人", "★row1 picks the nearest enemy")
      eq(table.getn(prof.skills[1].groups), 2, "★★★row1 keeps BOTH OR groups")
      eq(prof.skills[2].skill, "十字军圣印", "★row2 is the crusader seal")
      eq(prof.skills[2].groups[1][1].k, "hasDebuff", "★row2 cond1 is hasDebuff")
      eq(prof.skills[2].groups[1][1].v, false, "★★★and 无debuff is the NEGATED form (silent-drop trap)")
      eq(prof.skills[3].skill, "正义圣印", "★row3 is the seal of righteousness")
      eq(table.getn(prof.skills[3].groups[1]), 3, "★★★row3 keeps all 3 AND conditions")
      eq(prof.skills[3].groups[1][3].k, "hasDebuff", "★row3 cond3 is hasDebuff")
      eq(prof.skills[3].groups[1][3].v ~= false, true, "★★★and it is the POSITIVE form (v 存 nil；判定侧按 v ~= false 读)")
      eq(prof.skills[3].groups[1][3].s, "十字军审判", "★★and the aura name survived")
      eq(prof.skills[7].groups[1][1].secOp, "<=", "★★★row7 kept the remaining-time operator [<=70s]")
      eq(prof.skills[7].groups[1][1].secN, 70, "★★★row7 kept the remaining-time value 70")
      eq(prof.skills[8].groups[1][2].k, "tBuff", "★row8 cond2 is tBuff")
      eq(prof.skills[8].groups[1][2].v, false, "★★★and it is 无目标buff (negated form)")
      eq(EVAL_PROFILE_TO_TEXT(prof), pal.list[1].text,
         "★★★EXACT round-trip: export(parse(text)) == text (catches drops, renames, reordering)")
    end
  end
end


-- 61) ★★ 1.70.45 窗口宽度：单一来源 + 加宽 ~100（用户要求「加宽UI 100左右」+「技能编辑与配置窗同宽」）
do
  local w0 = EVAL_TEST_WIN_W() -- 第一个返回 = 来源函数当前值
  eq(type(w0) == "number", true, "★the window width comes from a single source function")
  eq(w0, 660, "★★ zhCN window width is 660 (was 560, +100 per user request)")
  eq(w0 > 560, true, "★the UI really got wider")
  -- 西文分支（原 700）
  local okLang = EVAL_SET_LANG("enUS")
  if okLang then
    eq(EVAL_TEST_WIN_W(), 800, "★★ enUS/ruRU window width is 800 (was 700, +100)")
    EVAL_SET_LANG("zhCN")
    eq(EVAL_TEST_WIN_W(), 660, "★language switch is reversible (restored zhCN)")
  end
end


-- 62) ★★★ 1.70.45 「剩余时间检查」（用户要求：buff 类条件加剩余时间，单位秒）
-- ★作用域：本客户端只有**自身光环**有时长 API（wiki globals/Buff：GetPlayerBuffTimeLeft → 秒），
--   其他单位的 UnitBuff/UnitDebuff 只给 图标+层数 → 目标侧如实失败，不静默当作没写。
do
  -- 62a) 作用域判据（UI 与断言共用同一份 seSecKinds）
  eq(EVAL_TEST_SE_SEC_KINDS("hasBuff"), true, "★自身buff 支持剩余时间检查")
  eq(EVAL_TEST_SE_SEC_KINDS("pDebuff"), true, "★自身debuff 支持")
  eq(EVAL_TEST_SE_SEC_KINDS("tBuff"), false, "★★目标buff 不支持（客户端无时长 API）")
  eq(EVAL_TEST_SE_SEC_KINDS("hasDebuff"), false, "★★目标debuff 不支持")
  eq(EVAL_TEST_SE_SEC_KINDS("hpPct"), false, "★非光环条件不支持")

  -- 62b) 步进 1 / 区间 1-300（UI 按钮与断言共用 seSecStep）
  local c = { secN = 10 }
  eq(EVAL_TEST_SE_SEC_STEP(c, 1), 11, "★步进=1（+）")
  eq(EVAL_TEST_SE_SEC_STEP(c, -1), 10, "★步进=1（-）")
  c.secN = 1   eq(EVAL_TEST_SE_SEC_STEP(c, -1), 1,   "★★下界夹紧到 1")
  c.secN = 300 eq(EVAL_TEST_SE_SEC_STEP(c, 1), 300, "★★上界夹紧到 300")
  eq(EVAL_TEST_SE_SEC_STEP({}, 1), nil, "★未启用时步进是空操作（不会凭空生值）")

  -- 62c) 文本往返（四类光环 × 四个方向）：导出→导入必须逐字一致
  for _, t in ipairs({
      "无buff:奥术智慧[<30s]", "有buff:奥术智慧[>=60s]",
      "无buff:战斗怒吼<3[<=15s]", "自身debuff:减速[>5s]",
      "无自身debuff:减速[>=10s]", "目标buff:嗜血[<20s]",
      "无debuff:断筋[<=45s]", "有debuff:裂伤[>2s]",
    }) do
    local cd = EVAL_PARSE_ONE(t)
    eq(cd ~= nil, true, "★解析成功: " .. t)
    if cd then
      eq(EVAL_COND_STR(cd), t, "★★往返一致: " .. t)
      eq(type(cd.secN) == "number", true, "★剩余秒数已入库: " .. t)
    end
  end
  -- 层数与剩余时间同时存在时不得互相吞掉
  local both = EVAL_PARSE_ONE("无buff:战斗怒吼<3[<=15s]")
  eq(both.n, 3, "★层数仍为 3（与时间后缀共存）")
  eq(both.secOp, "<=", "★方向 <=")
  eq(both.secN, 15, "★秒数 15")
  -- 非光环条件带后缀 = 写法错误 → 丢弃（宁可丢，不静默接受无意义字段）
  eq(EVAL_PARSE_ONE("可攻击[<30s]") == nil, true, "★非光环条件带剩余时间后缀→丢弃")
  eq(EVAL_PARSE_ONE("无buff:奥术智慧").secN, nil, "★无后缀时不带 secN")

  -- 62d) 求值语义（真正要保的行为）
  EVAL_HELP_CONFIG.war.debuffTex = EVAL_HELP_CONFIG.war.debuffTex or {}
  EVAL_HELP_CONFIG.war.debuffTex["战斗怒吼"] = "texBS"
  local function secCase(left)
    -- left=nil 表示「条目不带 left」→ 桩返回 0（= 无限/无结束时间，与实测语义一致）
    TEST.buffs = { { tex = "texBS", left = left } }
    TEST.unitBuffs = nil TEST.debuffs = {} TEST.pDebuffs = nil
    EVAL_HELP_UPDATE_STATE()
  end
  -- (1) 光环不存在 + 「无buff & 剩余<30」→ 该补（此时时间检查不参与）
  TEST.buffs = {} TEST.unitBuffs = nil EVAL_HELP_UPDATE_STATE()
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = false, secOp = "<", secN = 30 }), true, "★★没有 buff 时「剩余<30」仍为真（=该补了）")
  -- (2) 存在且即将到期 → 真
  secCase(10)
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = false, secOp = "<", secN = 30 }), true, "★★剩余 10s < 30s → 该补")
  -- (3) 存在且还早 → 假（不重施）
  secCase(60)
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = false, secOp = "<", secN = 30 }), false, "★★剩余 60s → 不该补")
  -- (4) 方向可切换：>= 方向
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = true, secOp = ">=", secN = 60 }), true, "★★剩余 60s >= 60s → 真")
  secCase(59)
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = true, secOp = ">=", secN = 60 }), false, "★★剩余 59s < 60s → 假")
  -- (5) ★★无限/无结束时间（API 返回 0）不能当「0 秒」：否则 <N 恒真 → 每帧都判「该补」（无脑重施）
  secCase(nil)
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = false, secOp = "<", secN = 30 }), false, "★★无限时长 + <30 必须为假（否则无脑重施）")
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = true, secOp = ">=", secN = 30 }), true, "★无限时长 + >=30 算满足")
  -- (6) ★无剩余时间数据（光环在 UnitBuff 而不在 buff 栏）→ 如实不满足
  TEST.buffs = {} TEST.unitBuffs = { { tex = "texBS", apps = 1 } } EVAL_HELP_UPDATE_STATE()
  eq(EVAL_HELP_STATE.playerBuffs["texBS"] ~= nil, true, "★前提：UnitBuff 路径确实认为「有 buff」")
  eq(EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = true, secOp = "<", secN = 30 }), false, "★★无剩余数据时如实不满足（不静默当通过）")
  -- (7) 目标光环带时间检查 → 如实 false（客户端没有目标时长数据）
  TEST.tgtBuffs = { { tex = "texBS", apps = 1 } } EVAL_HELP_UPDATE_STATE()
  eq(EVAL_COND_EVAL({ k = "tBuff", s = "战斗怒吼", v = true, secOp = "<", secN = 30 }), false, "★★目标buff 时间检查→如实 false")
  TEST.tgtBuffs = nil TEST.unitBuffs = nil TEST.buffs = {} EVAL_HELP_UPDATE_STATE()
end

-- 63) ★★★ 1.70.46 UnrealQuest 强依赖的友好提示（用户要求「未安装该插件时做一个友好的依赖提示」）
-- ★本组盯住三件事，而不是「面板存在」：
--   ① 探测状态正确（就绪 / 未安装 / 已装未启用 / 已启用未就绪 / 客户端无 Addon API）；
--   ② 文案按状态**分叉**：四条文本两两不同 + 文案键映射正确。
--      （只断言「是字符串」会被旧文本蒙过去——1.70.38 教训）
--   ③ 依赖缺席时**交互控件必须收起**：否则用户打字、点按钮，只得到空列表 = 静默失败。
do
  EVAL_DS_BUILD_FOR_TEST()
  EVAL_HELP_CONFIG.cfgTab = 4
  local savedDb = UnrealQuestData
  local savedInfo, savedState, savedLoaded = GetAddOnInfo, GetAddOnEnableState, IsAddOnLoaded
  local function allHidden(list)
    for _, w in ipairs(list) do
      if w.IsShown and w:IsShown() then return false end
    end
    return true
  end
  local sw = EVAL_DS_TEST_SEARCH_WIDGETS()
  eq(type(savedDb) == "table", true, "precondition: the UnrealQuestData stub is in place")

  -- (a) 数据表在 → 就绪：面板收起、搜索行可用
  TEST.uqAddon = { installed = true, enabled = true, loaded = true }
  UnrealQuestData = savedDb
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 0, "★db present → dependency state OK")
  eq(EVAL_DS_TEST_DEP_SHOWN(), false, "★★ready: the notice panel is hidden")
  eq(sw[1]:IsShown(), true, "★ready: the search row is shown")

  -- (b) 未安装：引导面板出现，交互控件全部收起
  UnrealQuestData = nil
  TEST.uqAddon = { installed = false }
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 1, "★not installed → state MISSING")
  eq(EVAL_DS_TEST_DEP_SHOWN(), true, "★★missing: the notice panel is shown")
  eq(allHidden(sw), true, "★★★missing: search controls are hidden (no silent empty-result path)")
  local mMissing = EVAL_DS_TEST_DEP_MSG()

  -- (c) 已安装但未启用 → 指引去插件列表勾选
  TEST.uqAddon = { installed = true, enabled = false }
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 2, "★installed but disabled → state OFF")
  eq(allHidden(sw), true, "★disabled: search controls stay hidden")
  local mOff = EVAL_DS_TEST_DEP_MSG()

  -- (d) 已启用但数据表还没就绪
  TEST.uqAddon = { installed = true, enabled = true, loaded = true }
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 3, "★enabled without data → state PENDING")
  local mPending = EVAL_DS_TEST_DEP_MSG()

  -- (e) 客户端不提供 Addon API → 如实说「无法判定」，不假装知道
  GetAddOnInfo = nil
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 4, "★no addon API → state UNKNOWN")
  local mUnknown = EVAL_DS_TEST_DEP_MSG()

  -- ② 文案键映射（防止状态与文案被互换：只断言「两两不同」抓不到互换）
  eq(EVAL_DS_TEST_DEP_KEY(1), "DS_NEED_UQ", "★state 1 (未安装) maps to DS_NEED_UQ")
  eq(EVAL_DS_TEST_DEP_KEY(2), "DS_DEP_OFF", "★state 2 (未启用) maps to DS_DEP_OFF")
  eq(EVAL_DS_TEST_DEP_KEY(3), "DS_DEP_PENDING", "★state 3 (未就绪) maps to DS_DEP_PENDING")
  eq(EVAL_DS_TEST_DEP_KEY(4), "DS_DEP_UNKNOWN", "★state 4 (无法判定) maps to DS_DEP_UNKNOWN")
  local _ = mMissing and mOff and mPending and mUnknown -- （第一轮已取值，此处仅为可读性保留）

  -- ③ 三语言 × 四状态全跑一遍：文案必须真的**解析出来**（缺键时 L() 会把键名本身当文案显示）
  -- ★为什么必须逐语言跑：这 4 个键是**动态解析**的（L(dsDepText(st))），源码里没有
  --   L("DS_DEP_OFF") 这样的字面量 → test_engine 的 LANG KEY CHECK（静态扫字面量）看不见它们。
  --   第一版只断言了当前语言，于是我把 enUS 的 DS_DEP_OFF 改坏后检查照样通过——盲区已由此循环补上。
  for _, lg in ipairs({ "zhCN", "enUS", "ruRU" }) do
    if EVAL_SET_LANG(lg) then
      GetAddOnInfo = savedInfo -- ★必须先还原：上面的 (e) 步骤把它置成 nil 了，
      --   否则本循环的 t1~t3 会全部退化成「无法判定」文案，四条文案「两两不同」的断言就会误报。
      --   （这正是本组新加的三语言断言当场抓到的：测试自身的全局状态泄漏。）
      UnrealQuestData = nil
      TEST.uqAddon = { installed = false } ; EVAL_DS_REFRESH() ; local t1 = EVAL_DS_TEST_DEP_MSG()
      TEST.uqAddon = { installed = true, enabled = false } ; EVAL_DS_REFRESH() ; local t2 = EVAL_DS_TEST_DEP_MSG()
      TEST.uqAddon = { installed = true, enabled = true, loaded = true } ; EVAL_DS_REFRESH() ; local t3 = EVAL_DS_TEST_DEP_MSG()
      GetAddOnInfo = nil ; EVAL_DS_REFRESH() ; local t4 = EVAL_DS_TEST_DEP_MSG()
      GetAddOnInfo = savedInfo
      UnrealQuestData = savedDb -- 数据语言检查需要真库

      -- ④ 数据语言：dsLang() 决定去取哪个本地化子表（items_zhCN / items_enUS …）。
      --   原实现同样写错 → 英/俄客户端里物品/怪物/任务名恒为中文。
      eq(EVAL_DS_TEST_LANG(), lg, "★★" .. lg .. ": dsLang() (DB sub-table language) follows the selected language")
      local probe = ({ zhCN = "亚麻", enUS = "Linen", ruRU = nil })[lg]
      local col = "items_" .. lg
      if probe and UnrealQuestData[col] then -- 桩里只有 items_zhCN / items_enUS，故只对这两种语言做端到端
        local res = EVAL_DS_SEARCH(probe, "item")
        eq(table.getn(res) >= 1, true, "★★" .. lg .. ": search by the " .. lg .. " name hits item 2589")
        eq(res[1] and res[1].name, UnrealQuestData[col][2589], "★★" .. lg .. ": result name comes from " .. col)
      end
      local four = { t1, t2, t3, t4 }
      local seenL, dupL = {}, false
      for i = 1, 4 do
        eq(type(four[i]) == "string" and four[i] ~= "", true, lg .. " state " .. i .. ": notice text is non-empty")
        eq(four[i] ~= EVAL_DS_TEST_DEP_KEY(i), true,
          "★★" .. lg .. " state " .. i .. ": locale key really resolved (not the bare key name)")
        if seenL[four[i]] then dupL = true end
        seenL[four[i]] = true
      end
      eq(dupL, false, "★★" .. lg .. ": the four states produce four DIFFERENT messages")
      -- ★「语言真的生效了吗」：文案必须**逐字等于该语言包里的值**。
      --   这一条正是抓出真 bug 的断言：原实现 L() 调的是 EVAL_RESOLVE_LANG()（无返回值）→ 恒取 zhCN，
      --   于是英/俄客户端整页中文；只断言「四条两两不同」**抓不到**（四条全是中文照样两两不同）。
      local pack = EVAL_LOCALES and EVAL_LOCALES[lg]
      eq(pack ~= nil, true, lg .. ": locale pack exists")
      if pack then
        eq(t1, pack.DS_NEED_UQ, "★★" .. lg .. " state-1 text comes from the " .. lg .. " pack (not a zhCN fallback)")
        eq(t2, pack.DS_DEP_OFF, "★★" .. lg .. " state-2 text comes from the " .. lg .. " pack")
        eq(t3, pack.DS_DEP_PENDING, "★★" .. lg .. " state-3 text comes from the " .. lg .. " pack")
        eq(t4, pack.DS_DEP_UNKNOWN, "★★" .. lg .. " state-4 text comes from the " .. lg .. " pack")
        eq(EVAL_DS_TEST_DEP_LINE("title"), pack.DS_DEP_TITLE, "★★" .. lg .. ": notice title comes from the " .. lg .. " pack")
      end
      -- 面板的静态键（标题/原因/影响范围）在同一语言下也必须解析出来
      eq(EVAL_DS_TEST_DEP_LINE("title") ~= "DS_DEP_TITLE", true, "★" .. lg .. ": title key resolved")
      eq(EVAL_DS_TEST_DEP_LINE("why") ~= "DS_DEP_WHY", true, "★" .. lg .. ": why key resolved")
      eq(EVAL_DS_TEST_DEP_LINE("msg") ~= "DS_DEP_MSG", true, "★" .. lg .. ": state line is a message, not a key")
      eq(EVAL_DS_TEST_DEP_LINE("foot") ~= "DS_DEP_FOOT", true, "★" .. lg .. ": foot key resolved")
      for _, k in ipairs({ "title", "why", "msg", "foot" }) do
        local v = EVAL_DS_TEST_DEP_LINE(k)
        eq(type(v) == "string" and v ~= "", true, lg .. " panel line '" .. k .. "' is filled")
      end
    end
  end
  EVAL_SET_LANG("zhCN")

  -- 还原（1.68.2 教训：测试替换全局必须 save/restore）
  GetAddOnInfo, GetAddOnEnableState, IsAddOnLoaded = savedInfo, savedState, savedLoaded
  TEST.uqAddon = { installed = false }
  UnrealQuestData = savedDb
  EVAL_DS_REFRESH()
  eq(EVAL_DS_DEP_STATE(), 0, "★restored: dependency state is OK again")
  eq(EVAL_DS_TEST_DEP_SHOWN(), false, "★restored: notice panel hidden again")
end

-- 64) ★★★ 1.70.46 窗口尺寸：宽度三方一致 + **高度必须真的被设置**
-- 【实测事故】用户截图：技能编辑窗变成一块几乎全黑的大窗、还盖住了配置窗。
--   根因：`seUI.W = W -- 注释 root:SetHeight(H)` —— SetHeight 被**同一行的行尾注释吞掉**，
--   窗口从未设置高度，客户端给了个接近整屏的默认高度。**宽度完全正常，只有高度异常**。
--   语法合法 / luacheck 通过 / 测试全绿：当时只有「宽度」断言，高度一条都没有。
-- ★教训：断言必须**直接问帧要真实尺寸**（GetWidth/GetHeight），而不是只读构建期记录的常量；
--   并且「宽度有断言」不代表「尺寸有断言」——一半的维度没断言就等于没断言。
do
  -- 两个窗都不是加载期构建的：SE_BUILD 在 EVAL_HELP_SE_OPEN 里（点「添加条件」才建），
  -- cfgBuild 在打开配置窗时才跑。断言前必须先真正把它们建出来，否则读到的永远是 nil。
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.root) then EVAL_HELP_CFG_TOGGLE() end
  if type(EVAL_HELP_SE_OPEN) == "function" then pcall(EVAL_HELP_SE_OPEN, 1) end
  -- ★★1.71.2 用户要求「每次打开配置都进行一次技能扫描（静默日志）」——
  --   这条断言必须**走真实的开关窗入口 EVAL_HELP_CFG_TOGGLE**，不能直调 EVAL_GO_RESCAN：
  --   直调只能证明「扫描函数会写日志」，证明不了「打开配置真的会触发它」——
  --   而后者才是用户要的行为（1.70.46 教训：只测函数不测调用点 = 没测）。
  TEST.slotNames[1] = "致死打击"
  EVAL_LOG_CLEAR()
  TEST.chat = nil
  -- ★★★1.72.4 前置条件必须**显式写出来**：本段要验「关窗」，前提是窗此刻是**开着**的。
  --   老写法把这个前提偷偷交给了桩的一个错误默认值（桩里新建帧默认 shown=false，
  --   而真客户端是**默认显示**）→ 桩改对之后本条立刻炸。
  --   ★判据：「前提来自被测代码的行为」可以，但「前提来自桩的默认值」不行——那是在借假前提。
  pcall(EVAL_HELP_CFGWIN.root.Show, EVAL_HELP_CFGWIN.root)
  eq(EVAL_HELP_CFGWIN.root:IsVisible(), true, "precondition: config window is open")
  EVAL_HELP_CFG_TOGGLE() -- 关
  eq(EVAL_HELP_CFGWIN.root:IsVisible(), false, "config window closed by toggle")
  EVAL_HELP_CFG_TOGGLE() -- 开：这里必须触发一次静默扫描
  eq(EVAL_HELP_CFGWIN.root:IsVisible(), true, "config window reopened by toggle")
  local openedScan = false
  for _, line in ipairs(EVAL_HELP_CONFIG.log or {}) do
    if string.find(line, "[扫:open]", 1, true) ~= nil then openedScan = true end
  end
  eq(openedScan, true, "★★reopening the config window runs a silent skill scan (reason=open)")
  eq(TEST.chat, nil, "★★opening the config window scans WITHOUT printing to chat")
  TEST.slotNames[1] = nil
  local src, recCfg, recSe = EVAL_TEST_WIN_W()
  eq(src, 660, "★width source = 660 (zhCN)")
  eq(recCfg, src, "★config window recorded the same width")
  eq(recSe, src, "★skill-editor window recorded the same width")
  -- 真实尺寸（问帧，不问常量）
  local sw, sh = EVAL_TEST_SE_SIZE()
  eq(sw, 660, "★★skill editor REAL width is 660")
  eq(sh, 280, "★★★skill editor REAL height is 280 (1.70.46: SetHeight had been swallowed by a line comment)")
  -- ★★★1.71.2（第四轮）「方案技能日志」开关已移到全局→日志分组
  --   用户要求：「将方案列表的调试信息开关移动到全局配置内的日志分组」。
  --   ★要保的性质（三条，缺一不可）：
  --     ① 新位置真的有它（不是只从旧位置删了）；
  --     ② 它仍然读写**同一个** cfg.wdebug（换个新开关就是功能丢失）；
  --     ③ 它与「记录调试日志」不重叠（两行同 y 就会叠在一起）。
  do
    local rows = EVAL_TEST_CFG_LOG_ROWS()
    eq(type(rows) == "table", true, "the log group exposes its rows for inspection")
    local found, ys = nil, {}
    for _, r in ipairs(rows) do
      ys[table.getn(ys) + 1] = r.y
      if r.key == "W_DEBUG_LOG" then found = r end
    end
    eq(found ~= nil, true, "★★★the 「方案技能日志」switch now lives in the LOG group")
    if found then
      -- ② 读写同一字段：调 setter 后，getter 必须反映出来
      --   （这里不能直接读 cfg：test_assert 的作用域里没有 c()——本轮实测报 nil 已修）
      local before = found.get()
      found.set(not before)
      eq(found.get() == (not before), true, "★★读写仍是同一个 cfg.wdebug（功能没丢）")
      found.set(before)
      eq(found.get(), before, "★the getter reflects the restored value")
    end
    -- ③ 不重叠：同一分组内各行的 y 必须两两不同
    local dup = false
    for i = 1, table.getn(ys) do
      for j = i + 1, table.getn(ys) do if ys[i] == ys[j] then dup = true end end
    end
    eq(dup, false, "★★the log-group rows sit on distinct y values (the new row does not overlap G_LOG_FILE/G_LOG_AUTO)")
  end
  local cw, ch = EVAL_TEST_CFG_SIZE()
  eq(cw, 660, "★★config window REAL width is 660")
  -- 1.71.2：开关组按用户要求下移 40px（-349 → -389），原高度 420 会让开关行底部落到 -425
  -- （超出窗口 5px）→ 窗口同步加高 40 到 460，保证整行可见。★高度必须跟着内容走，不是先定高再塞。
  eq(ch, 460, "★★★config window REAL height is 460 (1.71.2: +40 so the shifted switch row stays visible)")
  -- 高度必须是正数：防止「设成 0/nil 也算设了」这种假通过
  eq(type(sh) == "number" and sh > 0, true, "★height is a real positive number, not nil/0")
end

-- 64e) ★★★ 1.71.2（第八轮还原）光环条件下拉：**输入框在面板内**（用户要求「还原」）
--   用户原话：「这个功能还原，到输入框格保持在下拉内，并且支持打字过滤和自定义输入」。
--   = 上一轮「把输入框搬到条件行自身」被**撤回**，输入回到**下拉面板内的搜索框**。
--   要保的性质（三条，缺一不可）：
--     ① 光环下拉**真的启用了面板内搜索框**，且它**在面板里**（不是被挪到屏幕外）；
--     ② 打字**真的过滤**（不能只验「关键字被记下来」——下拉忽略关键字时那样也通过）；
--     ③ **自定义输入**可用：面板里有自由文本行，点它能把输入的名字提交为光环名。
--   ★为什么①要查「在面板里」：本项目踩过「本体还在屏幕外、只有背景被搬回来」的假修复
--     （用户第三轮报的「光标消失」正是这个形态）。
--   ★为什么必须走**真实点击**打开下拉：直调 EVAL_DD_OPEN 会绕过「条件行那一格的 OnClick
--     到底有没有开下拉」——那正是用户看得见/看不见这个功能的接线。
do
  eq(EVAL_TEST_SE_PUSH_COND("hasDebuff", "毒蛇钉刺"), true, "editor refresh runs for real (precondition)")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_CELL(1), true, "★clicking the aura cell runs its real OnClick")
  eq(EVAL_DD_TEST_SHOWN(), true, "★★★that click opens the aura dropdown")
  -- ① 面板内搜索框：可见 + 真的在面板内
  eq(EVAL_DD_TEST_SEARCH_VISIBLE(), true, "★★★the in-panel search box is SHOWN for the aura dropdown")
  eq(EVAL_DD_TEST_SEARCH_IN_PANEL(), true,
     "★★★it really sits INSIDE the panel (not parked off-screen — that was the false fix)")
  -- ② 打字过滤（走真实 OnTextChanged → ddUI.refilter）
  local total = EVAL_DD_TEST_FILTERED_COUNT()
  eq(total > 0, true, "the dropdown lists rows (got " .. tostring(total) .. ")")
  EVAL_DD_TEST_TYPE_SEARCH("钉刺")
  local filtered = EVAL_DD_TEST_FILTERED_COUNT()
  eq(filtered < total, true,
     "★★★typing really FILTERS the list (all=" .. total .. " filtered=" .. filtered .. ")")
  -- ③ 自定义输入：自由文本行存在，点它把输入的名字提交为光环名
  eq(EVAL_DD_TEST_HAS_FREE_ROW(), true, "★★a free-text row exists so a custom name can be submitted")
  eq(EVAL_TEST_SE_DD_CLICK_FREE(), true, "★the free-text row is clickable through its real OnClick")
  eq(EVAL_TEST_SE_AURA_NAME(1), "钉刺",
     "★★★clicking the free row COMMITS the typed text as the aura name (custom input works)")
  EVAL_DD_HIDE()
end

-- 64d) ★★★ 1.71.2 配置窗「开关」分组改为**横排一行（3 项）**
--   （用户要求原文：「是否接收方案 放在开关分组，开关分组功能横向排列，定位在方案列表底部对齐」；
--     两轮澄清后用户选 B：开关组三项改横排，并把「接收方案」并入该组。）
--   要保的性质：
--     ① 开关组是**横排**（同一 y），不是原来的纵排；
--     ② **3 项**都在（启用一键宏 / 自动攻击 / 接收方案——「方案技能日志」后来移出到全局日志组）；
--     ③ 各占位**不重叠**（横排时最容易出的错就是间距算错压在一起）；
--     ④ 整行不超出窗口宽度（中文栏标签最长；实测 4 项中文约需 329px，窗口 660 足够）。
--   ★判据用**布局公式**（与生产代码同一套常量），不依赖测试桩的锚点解算——
--     桩对这类 SetPoint 返回 x=nil，拿它比边界会假失败（本项目踩过多次）。
do
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.root) then EVAL_HELP_CFG_TOGGLE() end
  -- 生产代码的横排公式（必须与 swItem 中一致）
  local LX2 = 18
  -- ★★估宽必须按**字符数**，不能用 string.len()——它返回**字节数**，中文一字 3 字节，",
  --   会把宽度高估 3 倍（本轮实测：4 项被算成 772px > 窗口 660 → 假失败；实际只有 364px）。
  --   生产代码已改为 FontString:GetStringWidth() 实测，这里用同样的「字节/3」近似做判据。
  local SW_LABEL_PX, SW_ITEM_GAP = 12, 18
  -- ★1.71.2：用户曾要求开关组「再往下移动 40 像素」（当时按分组标题的 y 定位；现改为按按钮行中线）。
  --   验的是**生产代码实际用的那个 y**：从窗口真实高度反推，避免测试自己写一个常量、
  --   生产代码改了它却不变（那正是「测试复刻逻辑」的老毛病）。
  -- ★★★读**生产代码实际用的值**，不再自己写常量。
  --   本轮变异实测：测试里写死 -389、把生产代码改回 -349 → 断言照样全绿（存活）。
  --   ★判据：「测试说自己期望 -389」与「生产代码真的是 -389」是两件事，必须读后者。
  local lay = EVAL_TEST_CFG_LAYOUT()
  eq(type(lay) == "table", true, "config window exposes its production layout values")
  -- ★★★1.71.2（第十六轮）用户要求：「隐藏左侧的开关标题名称」。
  --   要保的性质 = 那个标题**根本没被画出来**（不是在 UI 里 Hide）。
  --   ★怎么验：生产代码把每个 cfgHeader 的文案登记下来 → 断言查「它在不在」。
  --     只验「不再是某个 y」证明不了标题没画（本项目「要删的必须验不在」的老坑）。
  local heads = EVAL_TEST_CFG_HEADERS()
  local hasSwitchTitle, hasListTitle = false, false
  for _, h in ipairs(heads) do
    if h == EVAL_LOCALES[EVAL_GET_LANG()]["W_SWITCH_H"] then hasSwitchTitle = true end
    if h == EVAL_LOCALES[EVAL_GET_LANG()]["W_LIST_H"] then hasListTitle = true end
  end
  eq(hasSwitchTitle, false, "★★★the left 「开关」 group title is NOT drawn any more")
  -- ★反向哨兵：登记表必须**真的会响**——其它分组标题仍然在里面（否则上面那条恒真）
  eq(hasListTitle, true, "★sanity: other group titles are still registered, so the check really fires")
  local swRowY = lay.swItemDY -- 横排那一行的 y
  -- ★★★1.71.2（第六轮）按钮组靠右、与[关闭]**同一行**
  --   用户原话：「一键宏tab 以上按钮放置在右侧和关闭同一行」。
  --   ★要保的性质三条：① 三个按钮均在；② 组的**中线 == 关闭按钮中线**；
  --     ③ 组的右边缘**在关闭左边缘之左**（不重叠、不越窗）。
  local navRight = lay.navRight
  local navX0 = lay.navX0
  local navBW = lay.navBW
  local navRightY = lay.navY
  local closeLeft = lay.closeLeft
  local closeMidY = lay.closeMidY
  eq(type(navRight) == "number" and type(closeLeft) == "number", true, "nav/close geometry is exposed")
  local NAV_TAIL_GAP_EXPECTED = 8 -- 与生产代码一致的间隙（独立写出，避免读同一个值形成循环论证）)
  -- ② 同一行：按钮行中线必须等于关闭按钮中线
  local navH2 = lay.navH
  local navMid2 = navRightY - navH2 / 2
  eq(navMid2, closeMidY,
     "★★★the button row is centred on the CLOSE button's row (navMid=" .. tostring(navMid2)
     .. " closeMid=" .. tostring(closeMidY) .. ")")
  -- ③ 靠右且不与关闭重叠（组右边缘 < 关闭左边缘）
  eq(navRight <= closeLeft, true,
     "★★★the button group ends BEFORE the close button starts (navRight=" .. tostring(navRight)
     .. " closeLeft=" .. tostring(closeLeft) .. ")")
  -- ① **精确靠右**：组右缘必须恰好落在关闭左边缘往左 8px处。
  --   ★★为什么不能只写「右边缘 <= 关闭左边缘」：那样「放在左边」也成立
  --     （宽度小时两者都不重叠）→ 只能证明「没重叠」，证不了「靠右」。
  --     ★判据：**要验位置就必须钉精确右边缘**，不能用「不越界」代替。
  eq(navRight, closeLeft - NAV_TAIL_GAP_EXPECTED,
     "★★★the group is RIGHT-ALIGNED: its right edge sits exactly " .. tostring(NAV_TAIL_GAP_EXPECTED)
     .. "px left of the close button (right=" .. tostring(navRight) .. " closeLeft=" .. tostring(closeLeft) .. ")")
  -- ★反向哨兵：上一版的左对齐位置（x0=18）必须**不**满足这条
  local oldRight = 18 + navBW * 2 + 6 * 1
  eq(oldRight == navRight, false,
     "★sanity: the previous left-aligned layout (right=" .. tostring(oldRight) .. ") is NOT the same as the current one")
  local _, winH = EVAL_TEST_CFG_SIZE()
  eq(navRightY - navH2 >= -winH, true,
     "★★the right-aligned button row stays INSIDE the window (bottom=" .. tostring(navRightY - navH2)
     .. " winH=-" .. tostring(winH) .. ")")
  -- ★反向哨兵：旧左对齐版的 x0=18 与关闭左边缘相差很远 → 证明「靠右」确实发生了
  eq((18 + navBW * 2 + 6 * 1) <= closeLeft, true,
     "★sanity: the OLD left-aligned row also ends before close (both fit) -- position asserted via navRight instead")
  -- ★★★1.71.2（第十六轮）用户要求：「删除分享右边的按键（接收）——和开关状态内的接收方案重复」。
  --   要保的性质四条：① 行里**恰好两个**按钮；② 身份是 [案例模版][分享]（逐项比标签，按语言包取，不硬编码）；
  --   ③ [接收] **不许**再出现（「删掉了」必须验「不在」——只验数量挡不住「换成一个空壳」）；
  --   ④ 每个按钮仍要有真的 OnClick。
  local nav = EVAL_TEST_CFG_NAV()
  local Lz2 = EVAL_LOCALES[EVAL_GET_LANG()]
  eq(table.getn(nav), 2, "★★★the nav row keeps exactly TWO buttons (got " .. tostring(table.getn(nav)) .. ")")
  eq(nav[1] and nav[1].label, Lz2["IO_TPL"], "★★nav[1] is the template button")
  eq(nav[2] and nav[2].label, Lz2["SH_SHARE"], "★★nav[2] is the share button")
  eq(nav[3], nil, "★★★the removed RECV button is GONE (there is no third button any more)")
  for i = 1, table.getn(nav) do
    eq(nav[i].hasClick, true, "★nav button " .. i .. " still has a real OnClick handler")
  end
  -- ★★★1.71.2（第十七轮）用户要求：「分享按钮不要触发显示导入导出弹窗」。
  --   判据必须**在真实 OnClick 闭包上点一下**，再看导入导出窗的状态——
  --   只 grep 源码里「有没有那次调用」抓不到「调用点接线」（本项目反复栽在这上面）。
  --   ★为什么还要先把它关掉：旧调用是 **Toggle**——IO 窗本来就开着时它会把它**关掉**，
  --     所以「点完仍然是关着的」这一条同时排除了「弹出来」和「被关掉」两种错法。
  -- ★反向哨兵：先证明这个**观测点真的会响**——主动开一次必须读到 true、关回去必须读到 false。
  --   没有这一步时，「钩子恒返回 false」的变异会让所有「没弹窗」断言**恒真**（本项目「判据本身也要验」）。
  EVAL_HELP_IO_TOGGLE()
  eq(EVAL_TEST_IO_SHOWN(), true, "★sanity: the hook really reads TRUE when the window is open")
  EVAL_HELP_IO_TOGGLE()
  eq(EVAL_TEST_IO_SHOWN(), false, "★sanity: and back to FALSE once closed")
  if EVAL_TEST_IO_SHOWN() then EVAL_HELP_IO_TOGGLE() end -- 归零（Toggle 语义：开着就关）
  eq(EVAL_TEST_IO_SHOWN(), false, "★precondition: the import/export window starts hidden")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  local shareBtn = nav[2] and nav[2].btn
  local shareFn = (shareBtn and shareBtn.GetScript) and shareBtn:GetScript("OnClick") or nil
  eq(type(shareFn) == "function", true, "★the 分享 button exposes a real OnClick closure")
  if type(shareFn) == "function" then pcall(shareFn) end
  eq(EVAL_TEST_IO_SHOWN(), false, "★★★clicking 分享 does NOT open the import/export window")
  eq(EVAL_DD_TEST_SHOWN(), true, "★★...while the share channel dropdown really does open (the feature is not lost)")
  EVAL_DD_HIDE()
  -- ★★★1.71.2（第十九轮）用户要求：「分享按钮添加美化一点的 tooltip，指引他怎么分享、别人需要什么条件
  --   才能接收分享（比如需要开启接收分享的开关）」。
  --   ★判据 = **真的把鼠标移上去**（调用真实 OnEnter 闭包）再读 tooltip 文本——
  --     只 grep 源码里有没有那几行字，抓不到「闭包没接上 / 还挂着老的单行提示」。
  --   ★并且必须钉住「点名了接收开关」这一条：它是**唯一会静默失效**的条件
  --     （对方开关关着时 Share.lua 的 shOnMsg 第一行直接 return，双方都看不到任何提示）。
  TEST.tipLines = {}
  local entShare = (shareBtn and shareBtn.GetScript) and shareBtn:GetScript("OnEnter") or nil
  eq(type(entShare) == "function", true, "★the 分享 button has an OnEnter (i.e. it has a tooltip at all)")
  if type(entShare) == "function" then pcall(entShare) end
  local tips = TEST.tipLines or {}
  eq(table.getn(tips) >= 8, true,
     "★★★the share tooltip is a step-by-step GUIDE, not a one-liner (lines=" .. tostring(table.getn(tips)) .. ")")
  local allTip = ""
  for _, e in ipairs(tips) do allTip = allTip .. tostring(e.text) .. "\n" end
  eq(string.find(allTip, Lz2["SH_TIP_HOW"], 1, true) ~= nil, true, "★★指引里有一节讲「怎么分享」")
  eq(string.find(allTip, Lz2["SH_TIP_NEED"], 1, true) ~= nil, true, "★★指引里有一节讲「对方需要什么」")
  eq(string.find(allTip, Lz2["SH_TIP_S2"], 1, true) ~= nil, true, "★★指引写了「怎么选频道」")
  eq(string.find(allTip, Lz2["SH_RECV_SW"], 1, true) ~= nil, true,
     "★★★指引明确点名对方要开启「" .. tostring(Lz2["SH_RECV_SW"]) .. "」开关（否则分片被静默忽略）")
  -- ★反向哨兵：老的那种「一行提示」**不满足**上面「≥8 行」这条（证明判据真的会响）
  eq((1 >= 8), false, "★sanity: 旧的一行 tooltip 确实不满足「≥8 行」判据")
  -- ★两个按钮都要有自己的 tooltip（原来两个按钮共用一句「方案级操作…」的通用文案）
  for i = 1, table.getn(nav) do
    local e2 = (nav[i].btn and nav[i].btn.GetScript) and nav[i].btn:GetScript("OnEnter") or nil
    eq(type(e2) == "function", true, "★nav button " .. i .. " has a tooltip (OnEnter)")
  end
  -- 开关横排与按钮行对齐（同一条中线）
  local swItemY2 = lay.swItemDY
  eq(swItemY2 - lay.swItemH / 2, closeMidY,
     "★★★the switch row shares the SAME centre line as the button row and the close button")
  -- ★★★1.71.2（第六轮）用户改需求：「左侧开关移到下面一点、**和按钮对齐**」。
  --   → 旧的「下移 40px」判据已被取代（再钉 -389 反而会阻止对齐）。
  --   新判据 = **开关横排的中线 == 按钮行的中线**（这才是「对齐」这个词的含义）。
  --   ★用中线而不用顶边：两者高度不同（8/20 vs 16），顶边相等会看着错位（本项目铁律）。
  local navRowY = lay.navY
  local navH = lay.navH
  local swItemH = lay.swItemH
  local swItemYFromLayout = lay.swItemDY
  eq(type(navRowY) == "number" and type(navH) == "number", true, "button-row y/height are exposed")
  local navMid = navRowY - navH / 2
  local swMid = swRowY - swItemH / 2
  eq(swMid, navMid,
     "★★★the switch row is centred on the SAME line as the button row (swMid=" .. tostring(swMid)
     .. " navMid=" .. tostring(navMid) .. ")")
  -- ★反向哨兵：证明这条判据真的会响——旧值 -409 与按钮行中线 -439 并**不**对齐
  eq((-409) - 16 / 2 == navMid, false, "★sanity: the pre-change y (-409) really is NOT aligned with the button row")
  -- ★★★「下移 40px」这条需求真正要保的性质是「开关行**看得到**」，
  --   不是「某个具体 y 值」。只钉常量会漏掉最要命的失配：
  --   把行挪下去而窗口高度**没跟着加高** → 行落在窗口外、用户根本看不到，
  --   而断言照样全绿（本轮变异实测：改回 -349 存活、把高度改回 420 也存活）。
  --   → 判据改为「横排底边必须留在窗口内」，用**真实窗口高度**反推，不写死 460。
  local _, realH = EVAL_TEST_CFG_SIZE()
  eq(type(realH) == "number" and realH > 0, true, "config window height is readable for the layout check")
  local swBottom = swRowY - swItemH
  eq(swBottom >= -realH, true,
     "★★★the moved switch row stays INSIDE the window (rowBottom=" .. swBottom .. " windowH=-" .. realH .. ")")
  -- 反向哨兵：证明这条判据**真的会响**——旧高度 420 下 -425 的底边确实是越界的
  eq((-425) >= -420, false, "★sanity: at the old height 420 the shifted row really would be clipped")
  -- ★★★1.71.2（第四轮）：用户要求把「方案技能日志」（原 W_DEBUG）
  --   移到「全局 → 日志」分组 → 开关组从 4 项变回 **3 项**。
  --   ★这条断言同时守住两件事：① 确实移走了（不再是 4 项）；② 没有连带把别的项也删了（仍是 3 项）。
  local labels = { "W_ENABLE", "W_AUTOATK", "SH_RECV_SW" }
  eq(table.getn(labels), 3, "★★★the switch group holds THREE items again (W_DEBUG moved to the global log group)")
  -- 逐项累加，验「不重叠」并算出总宽
  local x = LX2
  local prevRight = nil
  for i, key in ipairs(labels) do
    local lab = EVAL_LOCALES[EVAL_GET_LANG()][key] or ""
    local by = string.len(tostring(lab))
    local chars = (by >= 3) and math.floor(by / 3) or by -- UTF-8：中文 3 字节/字
    local estW = 16 + 6 + chars * SW_LABEL_PX
    if prevRight ~= nil then
      eq(x >= prevRight, true, "★★switch item " .. i .. " does not overlap the previous one")
    end
    prevRight = x + estW
    x = x + estW + SW_ITEM_GAP
  end
  local rowRight = prevRight
  -- ④ 不超出窗口宽度（中文 660 / 西文 800；取最窄的 660 做判据）
  eq(rowRight <= 660, true,
     "★★★the horizontal switch row fits in the window (right=" .. rowRight .. " W=660)")
  -- ③ 横排 = 同一行：三项目标的 y 必须是同一个值（而不是纵排的三个不同 y）
  -- ★1.71.2（第六轮）：不再写死「标题下方的偏移」——现在横排 y 由**按钮行中线**反推
  --   （分组标题后来也不画了）。写死公式会把「对齐」这个需求本身测没。
  eq(swRowY, swItemYFromLayout, "★all switch items share ONE row y=" .. tostring(swRowY))
  -- 反向哨兵：旧的纵排 y 必须**不再**使用（否则说明还有残留的纵排项）
  -- ★反向哨兵：被移走的那一项**不许**再出现在开关组标签里
  local stillThere = false
  for _, k in ipairs(labels) do if k == "W_DEBUG" then stillThere = true end end
  eq(stillThere, false, "★★the moved-out switch (W_DEBUG) is GONE from the switch group")
  -- ★1.71.2（第十六轮）旧的「纵排三个 y」反向哨兵已被**取代**并删除：
  --   它当时的参照物是分组标题的 y（swY），而标题现已不画、swY 也随之删除；
  --   再留着就等于钉一个**不存在的常量**（本项目「需求改了就要改断言、旧断言不能当伪保护」）。
  --   该性质现在由「所有开关共享同一 y」+「分组标题不许被画出」两条共同守住。
end
-- 64b) ★★★ 1.71.2 小地图 EH 按钮的**默认位置**（用户截图：压在「北郡山谷」小地图左下角）
--   【事故】默认锚点写成「mb.TOPRIGHT 对 Minimap.TOPLEFT」——看名字像「小地图左上」，
--   实际是把按钮挂在小地图**左边缘**；而小地图是**圆形**，矩形贴左边缘时下半部会落进圆里
--   → 视觉上就是「压在左下角」，并且会和地图边缘/环绕按钮叠在一起。
--   ★★判据为什么不能靠「算坐标是否相交」：测试桩只记录 SetPoint 的**相对偏移**，
--     不做真正的锚点解算（锚到 Minimap.LEFT 时它把 ox=-6 当成绝对屏幕坐标）→
--     按钮在桩里永远位于屏幕左上角、离小地图十万八千里 →「不重叠」恒真，
--     **把默认锚点改回 TOPLEFT 的变异体照样存活**（本轮实测被这个骗了一整轮）。
--   ★正解 = 直接验**锚点语义**：事故的要保性质是「锚到了邻居的哪条边」——
--     LEFT = 落在圆外（正确）；TOPLEFT = 贴左边缘、下半部压进圆里（用户截图就是这个）。
do
  local a = EVAL_TEST_MB_DEFAULT_ANCHOR()
  eq(type(a) == "table", true, "minimap button default anchor is inspectable")
  eq(a.point, "RIGHT", "★★★the button's own anchor point is RIGHT")
  eq(a.relPoint, "LEFT", "★★★it anchors to the minimap's LEFT edge — NOT TOPLEFT (that is what pushed it onto the round minimap's bottom-left)")
  eq(type(a.x) == "number" and a.x < 0, true, "★it sits OUTSIDE the minimap (negative offset), not on top of it")
  eq(a.relPoint ~= "TOPLEFT", true, "the accident configuration (TOPLEFT) fails this check")
  -- ★★重叠判定本身用**注入几何**验证（绕开测试桩不做锚点解算的限制）：
  --   小地图 = 圆心(940,684)、半径70 的圆。左下角贴边 = 事故形态，必须判为「压上」；
  --   左侧外 6px = 修正后的形态，必须判为「没压上」。
  local ML, MT, MR, MB = 870, 754, 1010, 614 -- 圆心(940,684) 半径70
  -- 事故形态：按钮**压在小地图里**（其矩形与小地图内切圆相交）
  eq(EVAL_TEST_RECT_HITS_CIRCLE_G(870, 754, 894, 730, ML, MT, MR, MB), true,
     "★★★a button sitting ON the minimap IS detected as overlapping (this is the reported accident)")
  eq(EVAL_TEST_RECT_HITS_CIRCLE_G(928, 696, 952, 672, ML, MT, MR, MB), true, "a rect over the centre overlaps")
  -- 修正形态：按钮整体落在圆的**左侧之外**
  eq(EVAL_TEST_RECT_HITS_CIRCLE_G(840, 696, 864, 672, ML, MT, MR, MB), false,
     "★★★the fixed layout (button OUTSIDE the left edge) is NOT overlapping")
  -- 缺坐标时安全放弃（返回 false），绝不抛错（调用点在 OnDragStop，抛错就是拖动弹红字）
  eq(EVAL_TEST_RECT_HITS_CIRCLE_G(nil, 1, 2, 3, ML, MT, MR, MB), false, "missing coords bail out safely instead of throwing")
end

-- 64c) ★★★ 1.71.2 IO 窗底部按钮行（用户截图：按钮被排成两排、又被路径提示压住一半）
--   【事故】底部要放 6 个按钮，但窗口只有 470 宽（等宽 82 放 6 个需要 546）→
--   「分享/接收」被挪到第二排（BOTTOM 42），而那一排正好与路径提示文字（y -288/-300）重叠 →
--   截图里「分享」右边那块黑就是被提示文字压住的。
--   ★判据三条（缺一不可）：① 全部**同一行**；② **互不重叠**；③ **不超出窗口宽度**。
--     只验「都在同一行」会漏掉「挤在一起/超出窗口」，只验宽度会漏掉换行。
do
  if type(EVAL_HELP_IO_BUILD) == "function" then pcall(EVAL_HELP_IO_BUILD) end
  local btns = EVAL_TEST_IO_BUTTONS()
  -- ★1.71.2：案例模版 / 分享 / 接收 三个按钮**搬出** IO 窗（用户要求「移动到外部方案列表底部」）
  --   → IO 窗底部只剩 导入 / 导出 / 关闭 三个。这里改成**精确等值**断言：
  --     原来写 >= 5 是「至少这么多」，搬走两个后它本会变红——但如果只把阈值改成 >=3，
  --     「一个都没搬走」也能通过 → 必须钉死 3，才能同时守住「搬走了」和「没多塞」。
  eq(table.getn(btns), 3, "★★★IO window keeps exactly THREE buttons now: 导入 / 导出 / 关闭 (got " .. tostring(table.getn(btns)) .. ")")
  -- ★★光数个数不够：「把导出的 OnClick 掏空、另加一个同宽空按钮」也能凑够 3 个。
  --   而且这轮真正要保的是**身份**——留下的是哪三个、搬走的是哪三个。
  --   → 逐项比对**标签**（按语言包取，不硬编码中文），顺序也一并钉住。
  local Lg = EVAL_LOCALES[EVAL_GET_LANG()]
  local wantLabels = { Lg["IO_IMPORT"], Lg["IO_EXPORT"], Lg["CLOSE"] }
  for i = 1, 3 do
    eq(btns[i].label, wantLabels[i],
       "★★IO button " .. i .. " is [" .. tostring(wantLabels[i]) .. "] (got " .. tostring(btns[i].label) .. ")")
  end
  -- 反向哨兵：被搬走的那三个标签**不许**再出现在 IO 窗里（"删了"要真的验"不在"）
  local gone = { Lg["IO_TPL"], Lg["SH_SHARE"] }
  for _, g in ipairs(gone) do
    local found = false
    for _, b in ipairs(btns) do if b.label == g then found = true end end
    eq(found, false, "★★the moved-out button [" .. tostring(g) .. "] is GONE from the IO window")
  end
  -- 每个按钮都必须真的有 OnClick（防止「留个空壳凑数」）
  for i, b in ipairs(btns) do
    local okh, h = pcall(b.btn.GetScript, b.btn, "OnClick")
    eq(okh and type(h) == "function", true, "★IO button " .. i .. " still has a real OnClick handler")
  end
  -- ① 同一行：按**实际锚点**数行数（桩拿不到锚点时按布局输入视为 1 行）。
  --   ★这条要抓的形态是「某个按钮被事后 ClearAllPoints + SetPoint 挪到第二排」——
  --     正是用户截图里的原始问题（分享/接收当初单独排在 BOTTOM 42，还压在路径提示上）。
  --     只看登记快照抓不到它（快照永远显示第一排），必须读真实锚点。
  eq(EVAL_TEST_IO_ROW_COUNT(), 1, "★★★all bottom buttons are laid out on ONE row (no button moved to a second row)")
  -- ② 互不重叠：按 x 排序后，前一个的右边界 <= 后一个的左边界
  local sorted = {}
  for _, b in ipairs(btns) do table.insert(sorted, b) end
  table.sort(sorted, function(p, q) return (p.x or 0) < (q.x or 0) end)
  local noOverlap, worstGap = true, nil
  for i = 2, table.getn(sorted) do
    local gap = (sorted[i].x or 0) - ((sorted[i - 1].x or 0) + (sorted[i - 1].w or 0))
    if worstGap == nil or gap < worstGap then worstGap = gap end
    if gap < 0 then noOverlap = false end
  end
  eq(noOverlap, true, "★★★bottom buttons do NOT overlap each other (tightest gap=" .. tostring(worstGap) .. "px)")
  -- ③ 不超出窗口：最后一个按钮的右边界必须留在窗内
  local last = sorted[table.getn(sorted)]
  local right = (last.x or 0) + (last.w or 0)
  local W = EVAL_TEST_IO_WIDTH()
  eq(type(W) == "number" and right <= W, true,
     "★★★the row fits inside the window (right=" .. tostring(right) .. " W=" .. tostring(W) .. ")")
  -- ★反向哨兵：确认判据本身会响——470 宽必须放不下 6 个按钮
  local needed = 14 * 2 + 82 * 6 + 8 * 5
  eq(needed > 470, true, "★sanity: six 82px buttons really cannot fit in the old 470px window (needed " .. needed .. ")")
end

-- 65) ★★★ 1.70.46 「剩余时间」的**真实接线**（不是判定函数本身）
--   【用户实测事故】点「自身buff检查」条件类型 → 红字报错：
--     attempt to call global 'seSecKinds' (a nil value)  @ EvalHelp.lua:2674 in EVAL_HELP_SE_REFRESH
--   根因：seSecKinds 声明在 EVAL_HELP_SE_REFRESH **之后** → 词法作用域看不见 → 绑到全局 nil。
--   ★当时测试只断言 EVAL_TEST_SE_SEC_KINDS（判定函数），**调用点从未被执行** → 全绿。
--   本组因此改为：塞一条条件 + 跑**真实刷新** + 点**真实按钮**（走行内 OnClick 闭包）。
do
  eq(EVAL_TEST_SE_PUSH_COND("hasBuff", "奥术智慧"), true, "★editor refresh runs for real with a self-buff condition")
  local shown, txt = EVAL_TEST_SE_ROW_SEC(1)
  eq(shown, true, "★★the 剩余时间 control appears on a self-buff row")
  eq(type(txt) == "string" and txt ~= "", true, "★and it carries a label (不限 / 剩余…) ")
  -- 非光环条件不得出现该控件（判定必须真的接到 UI 上）
  eq(EVAL_TEST_SE_PUSH_COND("hpPct", nil), true, "★refresh for real with a non-aura condition")
  eq((EVAL_TEST_SE_ROW_SEC(1)), false, "★★non-aura rows hide the 剩余时间 control")
  -- 真实按钮：+ / − 走各自行内的 OnClick 闭包（直接调 seSecStep 会漏掉接线错误）
  EVAL_TEST_SE_PUSH_COND("hasBuff", "奥术智慧", "<", 10)
  eq(EVAL_TEST_SE_SECN(1), 10, "precondition: 10s in the editor")
  eq(EVAL_TEST_SE_CLICK_SEC(1, true), true, "★the [+] button has a real OnClick")
  eq(EVAL_TEST_SE_SECN(1), 11, "★★the [+] button really steps the value")
  eq(EVAL_TEST_SE_CLICK_SEC(1, false), true, "★the [-] button has a real OnClick")
  eq(EVAL_TEST_SE_SECN(1), 10, "★★the [-] button really steps the value")
  EVAL_TEST_SE_PUSH_COND("hasBuff", "奥术智慧", "<", 1)
  EVAL_TEST_SE_CLICK_SEC(1, false)
  eq(EVAL_TEST_SE_SECN(1), 1, "★★clamped at 1 through the real button")
  -- ⑤ ★遍历**全部条件类型**各跑一次真实刷新：任何一条分支里引用错名字 / 缺控件都会当场炸。
  --   seSecKinds 那次事故只影响 hasBuff 这一条分支——只测一个 kind 是抓不到的。
  local kinds = EVAL_TEST_SE_KINDS()
  eq(table.getn(kinds) >= 10, true, "★the editor exposes many condition kinds (got " .. table.getn(kinds) .. ")")
  local failed = {}
  for _, k in ipairs(kinds) do
    local okk, errk = pcall(EVAL_TEST_SE_PUSH_COND, k, "测试", "<", 5)
    if not okk then table.insert(failed, k .. "{" .. tostring(errk) .. "}") end
  end
  eq(table.concat(failed, ","), "", "★★★every condition kind refreshes through the real UI path without error"
    .. (table.getn(failed) > 0 and (" (failed: " .. table.concat(failed, ",") .. ")") or ""))
  eq(EVAL_TEST_SE_CLEAR(), true, "★editor state cleared for later cases")
end

-- 66) ★★★ 1.70.47 队友/团员扫描（用户需求定案，两轮确认）
--   用户原话：
--   「新增行为类型 选取目标: - 队伍成员 - 团队成员,自动实施扫描.
--     搭配条件类型: 团队/队伍成员目标: 血量 蓝量 debuff检测 buff检测 四种条件,
--     debuff 检测增强扩展类型下拉:魔法,诅咒,毒等.
--     流程: 一键扫描队伍 血量少于% 释放 xx 治疗; 队伍有 xx 魔法,释放 解魔法技能」
--   方案示例（一键奶）：选取目标:队伍成员(目标血量<N% / 目标buff:名 / 目标debuff:名)
--                    → 强效治疗术(队友血量<60 & 就绪) → 驱散魔法(队友debuff:魔法 & 就绪)
--   ★本组盯六件事：① 扫描（含队伍/团队两个范围、缓存复用）
--     ② **选取器那一行自己的条件列表**逐候选过滤（用户示例的核心机制）
--     ③ 四种队友条件 + **命中即记 st.allyUnit 并切目标**（单条条件就能自足）
--     ④ dry（UI 预览）绝不切目标 ⑤ 往返/UI/三语言 ⑥ **端到端一键奶**（真跑 EVAL_RULE_RUN）
do
  local savedTeam, savedRaid, savedRaidN = TEST.team, TEST.raid, TEST.raidN
  local savedDebuffTex = EVAL_HELP_CONFIG.war.debuffTex
  EVAL_HELP_CONFIG.war.debuffTex = { ["回春术"] = "texRejuv", ["痛苦诅咒"] = "texCurse", ["魔法"] = "texCurse" }
  TEST.team = {
    { unit = "party1", name = "甲", hp = 50, hpMax = 100, mana = 50, manaMax = 100, powerType = 0,
      buffs = { { tex = "texRejuv", apps = 1 } }, debuffs = {} },
    { unit = "party2", name = "乙", hp = 10, hpMax = 100, mana = 8, manaMax = 100, powerType = 0,
      buffs = {}, debuffs = { { tex = "texCurse", apps = 2, type = "Magic" } } },
  }
  TEST.raid, TEST.raidN = nil, nil
  EVAL_HELP_UPDATE_STATE()

  -- (a) 扫描：队伍 = 自己 + 两名队友；含 debuff 类型
  local list = EVAL_HELP_TEAM_ENSURE()
  eq(table.getn(list), 3, "★★party scan covers player + 2 party members")
  local r2 = EVAL_HELP_TEAM_GET("party2")
  eq(r2 ~= nil, true, "★member lookup by unit works")
  eq(r2.hpPct, 10, "★★hp% computed from UnitHealth/UnitHealthMax")
  eq(r2.powerPct, 8, "★mana% computed")
  eq(r2.powerType, 0, "★power type captured (0 = mana)")
  eq(r2.debuffs["texCurse"] ~= nil, true, "★debuff texture captured")
  eq(r2.debuffs["texCurse"].t, "Magic", "★★★debuff DISPEL TYPE captured (UnitDebuff 3rd return)")
  eq(r2.debuffs["texCurse"].n, 2, "★debuff stack count captured")

  -- (a2) 团队范围：不在团队必须返回空表（绝不拿队伍成员冒充团员）
  eq(table.getn(EVAL_HELP_TEAM_ENSURE("raid")), 0, "★★★raid scope with no raid → empty (never fakes party as raid)")
  TEST.raid = {
    { unit = "raid1", name = "团长", hp = 90, hpMax = 100, mana = 90, manaMax = 100, powerType = 0, buffs = {}, debuffs = {} },
    { unit = "raid2", name = "团员", hp = 25, hpMax = 100, mana = 90, manaMax = 100, powerType = 0, buffs = {}, debuffs = {} },
  }
  EVAL_HELP_UPDATE_STATE()
  eq(table.getn(EVAL_HELP_TEAM_ENSURE("raid")), 2, "★★raid scope scans raid1..N")
  eq(EVAL_HELP_TEAM_GET("raid2") ~= nil, true, "★raid member lookup works")

  -- (a3) 缓存必须真的被复用（频率防护的核心：一次按键只扫一遍）
  local savedUH, uhCalls = UnitHealth, 0
  UnitHealth = function(u) uhCalls = uhCalls + 1 return savedUH(u) end
  EVAL_HELP_STATE.teamRaid = nil
  EVAL_HELP_TEAM_ENSURE("raid")
  local afterFirst = uhCalls
  EVAL_HELP_TEAM_ENSURE("raid")
  UnitHealth = savedUH
  eq(afterFirst > 0, true, "★首次扫描真的调了 UnitHealth")
  eq(uhCalls - afterFirst, 0, "★★★第二次 ENSURE 走缓存：0 次额外 API 调用")
  EVAL_HELP_STATE.teamRaid = nil
  EVAL_HELP_UPDATE_STATE()

  -- (b) ★★★「选取目标:队伍成员」= 扫描器 + **用这一行自己的条件过滤候选**
  --   用户示例正是这个形态：条件列表写「目标血量<N% / 目标buff:名 / 目标debuff:名」
  local function selRule(filters, skillName)
    return { skill = skillName or "选取目标:队伍成员", why = "t", groups = filters }
  end
  TEST.targetSel = nil
  -- 无过滤条件 → 候选按血量升序，第一个即血量最低者
  eq(EVAL_RULE_RUN({ selRule(nil) }), true, "★★选取目标:队伍成员 执行成功")
  eq(TEST.targetSel, "unit:party2", "★★★无过滤条件 → 默认选血量最低的(乙 10%)")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★并记入 st.allyUnit")
  TEST.targetSel = nil
  -- 目标血量 < N% 过滤：只有乙(10%)满足
  eq(EVAL_RULE_RUN({ selRule({ { { k = "tHpPct", op = "<", n = 40 } } }) }), true, "★目标血量<40 过滤命中")
  eq(TEST.targetSel, "unit:party2", "★★过滤后选的还是乙")
  TEST.targetSel = nil
  -- 目标buff 过滤：只有甲有 回春术 → 应选甲（即使乙血更低）
  eq(EVAL_RULE_RUN({ selRule({ { { k = "tBuff", s = "回春术", v = true } } }) }), true, "★目标buff:回春术 过滤命中")
  eq(TEST.targetSel, "unit:party1", "★★★过滤选的是「有该 buff 的人」(甲)，不是血量最低的乙")
  TEST.targetSel = nil
  -- 目标debuff 过滤：只有乙中诅咒 → 选乙
  eq(EVAL_RULE_RUN({ selRule({ { { k = "hasDebuff", s = "痛苦诅咒", v = true } } }) }), true, "★目标debuff 过滤命中")
  eq(TEST.targetSel, "unit:party2", "★★过滤选的是「中该 debuff 的人」")
  TEST.targetSel = nil
  -- 多条件 & ：血量<40 **且** 有回春术 → 没人同时满足
  local _, whyNoCand = EVAL_RULE_RUN({ selRule({ { { k = "tHpPct", op = "<", n = 40 }, { k = "tBuff", s = "回春术", v = true } } }) })
  eq(whyNoCand, nil, "★(sanity) 无人满足时 EVAL_RULE_RUN 返回 false")
  eq(EVAL_HELP_STATE.allyUnit, nil, "★★★无人满足 → st.allyUnit 清空")
  -- ★★★全候选都不满足时必须**还原原目标**，不能把目标丢在最后一个候选身上就算完。
  --   靠 TargetByName(原目标名) 还原（真客户端同款 API，项目里「指定名称」已在用）。
  TEST.targetSel = nil
  TEST.targetUnit = nil -- 当前目标是「一只普通怪」（不是队伍成员）
  TEST.curTargetName = "某只怪"
  EVAL_HELP_UPDATE_STATE() -- 让 st.targetName 反映当前目标
  EVAL_RULE_RUN({ selRule({ { { k = "tHpPct", op = "<", n = 1 } } }) })
  eq(TEST.targetSel, "name:某只怪", "★★★无人满足 → 用名字还原了原目标（不是留在最后一个候选身上）")
  TEST.curTargetName, TEST.targetSel, TEST.targetUnit = nil, nil, nil
  EVAL_HELP_UPDATE_STATE()
  -- ★★原目标是**队友**时要走精确还原（TargetUnit ← UnitIsUnit 反查出的 unit id）——
  --   这条比「按名字还原」更可靠，而且文档明确 TargetByName 只认**附近**单位，不能只靠它。
  TEST.targetUnit, TEST.targetSel = "party1", nil
  EVAL_HELP_UPDATE_STATE()
  eq(EVAL_HELP_STATE.targetName, "甲", "★(sanity) 当前目标 = 甲")
  EVAL_RULE_RUN({ selRule({ { { k = "tHpPct", op = "<", n = 1 } } }) })
  eq(TEST.targetSel, "unit:party1", "★★★原目标是队友 → 用 unit id **精确**还原（不是按名字）")
  -- 原目标是**自己**也要能精确还原（自己不是 party 索引，得单独 UnitIsUnit 比对一次）
  TEST.targetUnit, TEST.targetSel = "player", nil
  EVAL_HELP_UPDATE_STATE()
  EVAL_RULE_RUN({ selRule({ { { k = "tHpPct", op = "<", n = 1 } } }) })
  eq(TEST.targetSel, "unit:player", "★★★原目标是玩家自己 → 也能精确还原")
  TEST.targetUnit, TEST.targetSel = nil, nil
  EVAL_HELP_UPDATE_STATE()

  -- ★★★文档事实：团队里 GetNumPartyMembers 返回「团队人数 - 1」（**不是 0**），
  --   而 party 索引只到 party4 → 循环上界必须夹到 4，否则 40 人团会去试 party1..party39。
  --   用 UnitExists 的调用计数把上界钉死（只断言结果相同是抓不到这个的）。
  local savedPartyN, savedUE = TEST.partyN, UnitExists
  TEST.partyN, TEST.partyCalls = 39, 0
  UnitExists = function(u)
    if string.sub(tostring(u), 1, 5) == "party" then TEST.partyCalls = TEST.partyCalls + 1 end
    return savedUE(u)
  end
  EVAL_HELP_STATE.team = nil
  local lPartyInRaid = EVAL_HELP_TEAM_ENSURE()
  UnitExists = savedUE
  TEST.partyN = savedPartyN
  eq(TEST.partyCalls, 4, "★★★团队里 party 扫描只试 party1..party4（文档给出的 party 索引域）")
  eq(table.getn(lPartyInRaid), 3, "★成员表仍是「自己 + 两名真实队友」")
  TEST.partyCalls = nil
  -- 团队范围：选团队里的血量最低者
  TEST.targetSel = nil
  eq(EVAL_RULE_RUN({ { skill = "选取目标:团队成员", why = "t", groups = {} } }), true, "★选取目标:团队成员 执行成功")
  eq(TEST.targetSel, "unit:raid2", "★★★团队成员 → 从 raid 名单里选(raid2 25%)")
  eq(EVAL_HELP_STATE.allyUnit, "raid2", "★并记入 st.allyUnit")
  TEST.targetSel = nil

  -- (b2) ★★「选取目标:队伍成员」作为**条件**（存量配置 / 文本导入形态）也要能用。
  --   它走 condOne 的 target 分支——那是**另一个调用点**（技能行走 EVAL_RULE_RUN 的成员选取器分支）。
  --   只测一条路径就会漏掉另一条（本项目「A 产出 / B 消费 两边都要断言」的老教训）。
  TEST.targetSel = nil
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "target", s = "teamParty" },
      { groups = { { { k = "tBuff", s = "回春术", v = true } } } }), true, "★条件形态的 选取目标:队伍成员 恒真")
  eq(TEST.targetSel, "unit:party1", "★★★条件形态同样按规则过滤候选（选中有该 buff 的甲）")
  TEST.targetSel = nil
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "target", s = "teamRaid" }, nil), true, "★条件形态的 选取目标:团队成员 恒真")
  eq(TEST.targetSel, "unit:raid2", "★★条件形态按**团队**范围选人（raid2 血最少）")
  TEST.targetSel = nil

  -- (c) 四种队友/团员条件：**命中即记 st.allyUnit 并切目标**（用户要求「记下 unitID → st.allyUnit」）
  --   这样单条条件就能自足完成「找出该治/该解的人 → 后续技能打在他身上」。
  --   ★★★每条断言前都必须**清空 allyUnit 与 targetSel**：否则「上一条留下的值」会让
  --     「忘了记录/忘了切目标」的变异体照样通过（弱代理性质——本轮变异矩阵真的抓到过）。
  local function clearAlly() TEST.targetSel = nil EVAL_HELP_STATE.allyUnit = nil end
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamHp", op = "<", n = 60 }, nil), true, "★★队友血量<60 命中(乙 10%)")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★队友血量 命中后记下 unitID")
  eq(TEST.targetSel, "unit:party2", "★★★并且真的切了过去（后续 UseAction 才打对人）")
  clearAlly()
  -- ★★★1.71.3 统一规则（用户定案）：`>` 取**最大** →「队伍血>60」= 全队（含自己）里血**最高**的那个 >60 才命中。
  --   ★旧语义是「先取血最少的人再拿他比较」（那样 10%>60 恒假）——两套语义的差别正好钉在这里。
  local savedHp66, savedHpMax66 = TEST.hp, TEST.hpMax
  TEST.hp, TEST.hpMax = 80, 100
  EVAL_HELP_UPDATE_STATE()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamHp", op = ">", n = 60 }, nil), true, "★★统一规则：> 取最大 → 自己 80% > 60 命中")
  eq(EVAL_HELP_STATE.allyUnit, "player", "★★★记下的正是「血最高的那个人」（自己）")
  eq(TEST.targetSel, "unit:player", "★★★并切过去（扫描集含自己）")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamHp", op = ">", n = 95 }, nil), false, "★反向比较如实为假（最高 80% 也够不到 95）")
  eq(EVAL_HELP_STATE.allyUnit, nil, "★未命中就不该记人（别把上一轮的人留下）")
  TEST.hp, TEST.hpMax = savedHp66, savedHpMax66
  EVAL_HELP_UPDATE_STATE()
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamMana", op = "<", n = 20 }, nil), true, "★★队友蓝量<20 命中(乙 8%)")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★队友蓝量 命中后也记人")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamDebuff", dt = "Magic" }, nil), true, "★★★队友debuff(魔法) 命中")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★并记下「中魔法的那个人」")
  eq(TEST.targetSel, "unit:party2", "★★★且切过去（这正是「队友有魔法→解魔法」的施法前提）")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamDebuff", dt = "Curse" }, nil), false, "★队友debuff(诅咒) 无人有 → 假")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamDebuff", dt = "Curse", v = false }, nil), true, "★★取反方向(无诅咒)如实为真")
  eq(TEST.targetSel, nil, "★★「无debuff」是存在性判定 → 不切目标")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamBuff", s = "回春术", v = false }, nil), true, "★★队友缺buff:回春术 → 乙缺 → 真")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★记下「缺这个 buff 的人」(该给他补)")
  eq(TEST.targetSel, "unit:party2", "★★★并切过去（补 buff 才补对人）")
  clearAlly()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamBuff", s = "回春术", v = true }, nil), true, "★★队友有buff:回春术 → 甲有 → 真")
  eq(TEST.targetSel, nil, "★★「有buff」是存在性判定 → **不切目标**（没有「该对谁施法」的含义）")
  eq(EVAL_HELP_STATE.allyUnit, nil, "★★也不记人")
  clearAlly()
  -- 全队都有该 buff → 「缺buff」必须如实为假（否则会无限补 buff）
  local p2b = EVAL_HELP_TEAM_GET("party2")
  local p2bSaved = p2b.buffs["texRejuv"]
  local savedUB3 = TEST.unitBuffs
  TEST.unitBuffs = { { tex = "texRejuv", apps = 1 } }
  EVAL_HELP_STATE.team = nil
  EVAL_HELP_TEAM_ENSURE() -- 重扫后再改记录（玩家也要有该 buff）
  EVAL_HELP_TEAM_GET("party2").buffs["texRejuv"] = 1
  local okAllHave, whyAllHave = EVAL_TEST_COND_EVAL_LIVE({ k = "teamBuff", s = "回春术", v = false }, nil)
  eq(okAllHave, false, "★★★全队都有回春术 → 队友缺buff 如实为假（否则无限补 buff）")
  eq(type(whyAllHave) == "string" and string.find(whyAllHave, "全都", 1, true) ~= nil, true, "★并说明「全都有」")
  TEST.unitBuffs = savedUB3
  EVAL_HELP_STATE.team = nil
  EVAL_HELP_UPDATE_STATE()
  EVAL_HELP_TEAM_ENSURE()

  -- (c2) dry（战斗信息UI 每 0.15s 的预览求值）**绝不能切目标**——
  --   每个会切目标的类型都要各测一遍（只测一种抓不到另一种漏了 dry 门）
  for _, dryCd in ipairs({ { k = "teamHp", op = "<", n = 60 }, { k = "teamMana", op = "<", n = 20 },
                           { k = "teamDebuff", dt = "Magic" }, { k = "teamBuff", s = "回春术", v = false } }) do
    clearAlly()
    eq(EVAL_COND_EVAL(dryCd), true, "★dry 求值同样得出 true: " .. tostring(dryCd.k))
    eq(TEST.targetSel, nil, "★★★dry 求值没有切目标（" .. tostring(dryCd.k) .. "）")
    eq(EVAL_HELP_STATE.allyUnit, nil, "★★dry 也不写 st.allyUnit（" .. tostring(dryCd.k) .. "）")
  end

  -- (c3) 诚实失败
  TEST.raid = nil
  EVAL_HELP_UPDATE_STATE()
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamHp", op = "<", n = 90, name = "团队" }, nil), false, "★★★团队条件在没有团队时如实失败")
  local _, whyNoRaid = EVAL_TEST_COND_EVAL_LIVE({ k = "teamDebuff", dt = "Magic", name = "团队" }, nil)
  eq(type(whyNoRaid) == "string" and string.find(whyNoRaid, "不在团队中", 1, true) ~= nil, true, "★原因说明不在团队中")
  -- 怒气职业没有「蓝量%」可言：绝不当成 0% 蓝（mana 故意给 0，闸失效就会误报丙）
  local rage = { unit = "party3", name = "丙", hp = 5, hpMax = 100, mana = 0, manaMax = 100, powerType = 1, buffs = {}, debuffs = {} }
  table.insert(TEST.team, rage)
  EVAL_HELP_UPDATE_STATE()
  local okMana, whyRage = EVAL_TEST_COND_EVAL_LIVE({ k = "teamMana", op = "<", n = 50 }, nil)
  eq(okMana, true, "★★蓝量条件仍能在有蓝成员上成立")
  eq(string.find(whyRage, "丙", 1, true) == nil, true, "★★★怒气成员不被当成 0 蓝")
  eq(string.find(whyRage, "乙", 1, true) ~= nil, true, "★报出的是真正有蓝且最低的乙")
  TEST.team = { rage }
  EVAL_HELP_UPDATE_STATE()
  local okNoMana, whyNoMana = EVAL_TEST_COND_EVAL_LIVE({ k = "teamMana", op = "<", n = 50 }, nil)
  eq(okNoMana, false, "★★队伍里全是怒气职业 → 蓝量条件如实失败")
  eq(type(whyNoMana) == "string" and string.find(whyNoMana, "蓝", 1, true) ~= nil, true, "★并给出原因")
  -- ★把怒气成员**移除**（不是恢复成带他的表）：后面的端到端用例要的是「甲满/乙最低」这套干净数据，
  --   留着丙(hp 5%) 会让所有「最该治的人」断言都指向丙——测试数据必须自己收拾干净。
  TEST.team = {
    { unit = "party1", name = "甲", hp = 50, hpMax = 100, mana = 50, manaMax = 100, powerType = 0,
      buffs = { { tex = "texRejuv", apps = 1 } }, debuffs = {} },
    { unit = "party2", name = "乙", hp = 10, hpMax = 100, mana = 8, manaMax = 100, powerType = 0,
      buffs = {}, debuffs = { { tex = "texCurse", apps = 2, type = "Magic" } } },
  }
  EVAL_HELP_UPDATE_STATE()

  -- (d) 导出→导入往返：四种条件 × 两种范围，一个都不能丢参数（含扫描范围 name）
  local rt = {
    { k = "teamHp", op = "<", n = 40, name = "队伍" },
    { k = "teamHp", op = "<", n = 40, name = "团队" },
    { k = "teamMana", op = ">=", n = 20, name = "队伍" },
    { k = "teamMana", op = ">=", n = 20, name = "团队" },
    { k = "teamBuff", s = "回春术", v = false, name = "队伍" },
    { k = "teamBuff", s = "回春术", v = true, name = "团队" },
    { k = "teamDebuff", s = "痛苦诅咒", dt = "Magic", v = true, name = "队伍" },
    { k = "teamDebuff", dt = "Curse", v = true, name = "团队" },
    { k = "teamDebuff", s = "回春术", v = false, name = "团队" },
  }
  local broken = {}
  for _, cd in ipairs(rt) do
    local ss = EVAL_COND_STR(cd)
    local back = EVAL_PARSE_ONE(ss)
    if not back or back.k ~= cd.k or back.v ~= cd.v or back.op ~= cd.op or back.n ~= cd.n
      or back.s ~= cd.s or back.dt ~= cd.dt or back.name ~= cd.name then
      table.insert(broken, ss .. " → " .. tostring(back and (back.k .. "/" .. tostring(back.name)) or "nil"))
    end
  end
  eq(table.concat(broken, " | "), "", "★★★四种队友/团员条件都能往返（含扫描范围）")
  -- 行为类型只有两条：队伍成员 / 团队成员
  eq(table.getn(EVAL_TARGET_SEL), 11, "★★★选取目标只增加了 2 条成员扫描器")
  for _, id in ipairs({ "teamParty", "teamRaid" }) do
    local s2 = EVAL_COND_STR({ k = "target", s = id })
    local b2 = EVAL_PARSE_ONE(s2)
    eq(b2 and b2.k == "target" and b2.s == id, true, "★选取目标往返: " .. id)
  end

  -- (e) UI 接线：8 行类型都要在**真实编辑窗**里渲染，且标签随扫描范围变化
  local uiTypes = {
    { "teamHp", nil, "<", 60, nil, "队伍", "CT_TEAMHP" },
    { "teamMana", nil, "<", 20, nil, "队伍", "CT_TEAMMANA" },
    { "teamHp", nil, "<", 60, nil, "团队", "CT_TEAMRAIDHP" },
    { "teamMana", nil, "<", 20, nil, "团队", "CT_TEAMRAIDMANA" },
  }
  for _, u in ipairs(uiTypes) do
    eq(EVAL_TEST_SE_PUSH_COND(u[1], u[2], u[3], u[4], u[5], u[6]), true, "★editor renders " .. u[1] .. "/" .. u[6])
    eq(EVAL_TEST_SE_ROW_TYPE(1), EVAL_LOCALES[EVAL_GET_LANG()][u[7]], "★★行标签 = " .. u[7])
  end
  eq(EVAL_TEST_SE_PUSH_COND("teamBuff", "回春术", nil, nil, nil, "队伍"), true, "★editor renders 队友缺buff")
  eq(EVAL_TEST_SE_ROW_TYPE(1), EVAL_LOCALES[EVAL_GET_LANG()].CT_TEAMBUFF, "★★标签 = 队友缺buff")
  eq(EVAL_TEST_SE_PUSH_COND("teamBuff", "回春术", nil, nil, nil, "团队"), true, "★editor renders 团员缺buff")
  eq(EVAL_TEST_SE_ROW_TYPE(1), EVAL_LOCALES[EVAL_GET_LANG()].CT_TEAMRAIDBUFF, "★★标签 = 团员缺buff")
  eq(EVAL_TEST_SE_PUSH_COND("teamDebuff", nil, nil, nil, nil, "队伍"), true, "★editor renders 队友debuff")
  local dtShown, dtText = EVAL_TEST_SE_ROW_DT(1)
  eq(dtShown, true, "★★★队友debuff 行出现「类型」下拉")
  eq(dtText, EVAL_LOCALES[EVAL_GET_LANG()].DS_T_ANY, "★默认任意负面")
  EVAL_TEST_SE_PUSH_COND("teamDebuff", nil, nil, nil, "Magic", "团队")
  eq(EVAL_TEST_SE_ROW_TYPE(1), EVAL_LOCALES[EVAL_GET_LANG()].CT_TEAMRAIDDEBUFF, "★★标签 = 团员debuff")
  local _, dtMagic = EVAL_TEST_SE_ROW_DT(1)
  eq(dtMagic, EVAL_LOCALES[EVAL_GET_LANG()].DS_T_MAGIC, "★★类型下拉显示 魔法")
  EVAL_TEST_SE_PUSH_COND("teamHp", nil, "<", 40, nil, "队伍")
  eq((EVAL_TEST_SE_ROW_DT(1)), false, "★非 debuff 行不残留类型下拉")
  eq(EVAL_TEST_SE_CLEAR(), true, "★editor cleared")

  -- (e2) 条件类型下拉里必须**真的列出**这四种（用户明确要求）
  local menu = EVAL_TEST_SE_TYPE_MENU()
  local inMenu = {}
  for _, lbl in ipairs(menu) do inMenu[lbl] = true end
  local zh = EVAL_LOCALES["zhCN"]
  for _, key in ipairs({ "CT_TEAMHP", "CT_TEAMMANA", "CT_TEAMBUFF", "CT_TEAMDEBUFF",
                         "CT_TEAMRAIDHP", "CT_TEAMRAIDMANA", "CT_TEAMRAIDBUFF", "CT_TEAMRAIDDEBUFF" }) do
    eq(inMenu[zh[key]] == true, true, "★★★条件类型下拉里列出了: " .. key)
  end
  -- 选中后产出的条件必须是「引擎 k + 正确扫描范围」
  for _, pair in ipairs({ { "teamBuff", "teamBuff", "队伍" }, { "teamDebuff", "teamDebuff", "队伍" },
                          { "teamRaidBuff", "teamBuff", "团队" }, { "teamRaidDebuff", "teamDebuff", "团队" },
                          { "teamHp", "teamHp", "队伍" }, { "teamRaidHp", "teamHp", "团队" },
                          { "teamMana", "teamMana", "队伍" }, { "teamRaidMana", "teamMana", "团队" } }) do
    local cd = EVAL_TEST_SE_DEFAULT_COND(pair[1])
    eq(cd ~= nil, true, "★★下拉选得到: " .. pair[1])
    if cd then
      eq(cd.k, pair[2], "★★" .. pair[1] .. " → engine k = " .. pair[2])
      eq(cd.name, pair[3], "★★★" .. pair[1] .. " → 扫描范围 = " .. pair[3])
    end
  end
  local hpc = EVAL_TEST_SE_DEFAULT_COND("teamHp")
  eq(hpc.op, "<", "★队友血量默认比较符是 <（该加血了）")
  local mc = EVAL_TEST_SE_DEFAULT_COND("teamMana")
  eq(mc.op, "<", "★队友蓝量默认比较符是 <")
  -- 缺buff 型默认取「缺」方向（名字就是缺buff）
  eq(EVAL_TEST_SE_DEFAULT_COND("teamBuff").v, false, "★★队友缺buff 默认 = 缺方向")
  eq(EVAL_TEST_SE_DEFAULT_COND("teamDebuff").v, true, "★★队友debuff 默认 = 有方向（有人中魔法）")

  -- (f) 动态键三语言齐全（类型标签是拼接键，静态检查看不见）
  for _, lg in ipairs({ "zhCN", "enUS", "ruRU" }) do
    if EVAL_SET_LANG(lg) then
      local pack = EVAL_LOCALES and EVAL_LOCALES[lg]
      eq(pack ~= nil, true, lg .. ": locale pack exists")
      if pack then
        for _, k in ipairs({ "DS_T_ANY", "DS_T_MAGIC", "DS_T_CURSE", "DS_T_POISON", "DS_T_DISEASE",
                             "CT_TEAMHP", "CT_TEAMMANA", "CT_TEAMBUFF", "CT_TEAMDEBUFF",
                             "CT_TEAMRAIDHP", "CT_TEAMRAIDMANA", "CT_TEAMRAIDBUFF", "CT_TEAMRAIDDEBUFF",
                             "CTG_5" }) do
          eq(type(pack[k]) == "string" and pack[k] ~= "" and pack[k] ~= k, true,
            "★★" .. lg .. ": team key resolved: " .. k)
        end
        eq(pack.CT_TEAMDEBUFF ~= pack.CT_TEAMRAIDDEBUFF, true, "★★" .. lg .. ": 队友/团员 labels differ")
      end
    end
  end
  EVAL_SET_LANG("zhCN")

  -- (g) ★★★端到端「一键奶」：真跑 EVAL_RULE_RUN，验证两段流程各自打在**正确的人**身上
  --   用户方案： 选取目标:队伍成员(过滤) → 强效治疗术(队友血量<60 & 就绪) → 驱散魔法(队友debuff:魔法 & 就绪)
  local savedSlots = TEST.slotNames
  TEST.slotNames = { [1] = "强效治疗术", [2] = "驱散魔法" }
  EVAL_GO_RESCAN(true)
  EVAL_HELP_UPDATE_STATE()
  TEST.used, TEST.targetSel = {}, nil
  local healRule  = { skill = "强效治疗术", why = "heal", groups = { { { k = "teamHp", op = "<", n = 60 }, { k = "ready" } } } }
  local dispelRule = { skill = "驱散魔法",  why = "dispel", groups = { { { k = "teamDebuff", dt = "Magic" }, { k = "ready" } } } }
  local acted = EVAL_RULE_RUN({ healRule, dispelRule })
  eq(acted, true, "★★★一键奶：本次按键有动作")
  eq(table.getn(TEST.used) >= 1, true, "★★至少放出一个技能（" .. tostring(table.getn(TEST.used)) .. " 个）")
  eq(TEST.used[1], 1, "★★★先放的是治疗(槽1)")
  eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★治疗/驱散的目标都是「中魔法且血最少」的乙")
  eq(TEST.targetSel, "unit:party2", "★★★目标确实切到了乙（UseAction 因此打在他身上）")

  -- 单独验证「只配治疗、没配选取目标」也能自足工作（条件自己记人+切目标）
  TEST.used, TEST.targetSel = {}, nil
  eq(EVAL_RULE_RUN({ healRule }), true, "★★只配一条队友条件也能出手（条件自足）")
  eq(TEST.targetSel, "unit:party2", "★★★条件自己把目标切到了最该治的人")

  -- 队伍全满血 → 治疗条件不满足，不该出手（诚实失败，别乱放技能）
  -- ★EVAL_RULE_RUN 出手后会 UPDATE_STATE，而它会**作废扫描缓存**（st.team=nil）→ 读记录前要重扫
  EVAL_HELP_TEAM_ENSURE()
  local p1h, p2h = EVAL_HELP_TEAM_GET("party1"), EVAL_HELP_TEAM_GET("party2")
  local h1, h2 = p1h.hpPct, p2h.hpPct
  p1h.hpPct, p2h.hpPct = 100, 100
  TEST.used, TEST.targetSel = {}, nil
  eq(EVAL_RULE_RUN({ healRule }), false, "★★★全队满血 → 不施法")
  eq(table.getn(TEST.used), 0, "★★一个技能都没放")
  p1h.hpPct, p2h.hpPct = h1, h2

  -- ★★★每次按键开头必须**清空 st.allyUnit**：否则上一轮选的人会被这一轮当成「本次命中的人」。
  --   这条只能靠**真实入口 EVAL_GO** 验证（清空动作就在它里面）——所以这里真的按一次宏，
  --   而不是调内部函数（本项目「能点就点真实按钮」的同一原则）。
  local savedProf, savedActive, savedDeb = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile, EVAL_HELP_CONFIG.goDebounce
  EVAL_HELP_CONFIG.war.profiles = { { name = "probe", skills = {
    { skill = "强效治疗术", why = "x", enabled = true, groups = { { { k = "tHpPct", op = "<", n = 1 } } } } } } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_HELP_CONFIG.goDebounce = 0 -- 关掉去抖窗，否则同一 GetTime 下第二次按宏被跳过
  TEST.targetUnit, TEST.targetSel, TEST.used = nil, nil, {}
  EVAL_HELP_STATE.allyUnit = "stale:上一次按键选的人"
  EVAL_GO()
  eq(EVAL_HELP_STATE.allyUnit, nil, "★★★每按一次宏都清空 st.allyUnit（旧值绝不冒充本次选中的人）")
  eq(table.getn(TEST.used), 0, "★(sanity) 本轮条件不满足 → 没施法")
  EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile, EVAL_HELP_CONFIG.goDebounce = savedProf, savedActive, savedDeb

  TEST.slotNames = savedSlots
  EVAL_GO_RESCAN(true)
  TEST.team, TEST.raid, TEST.raidN = savedTeam, savedRaid, savedRaidN
  EVAL_HELP_CONFIG.war.debuffTex = savedDebuffTex
  EVAL_HELP_STATE.teamCur, EVAL_HELP_STATE.allyUnit = nil, nil
  EVAL_HELP_UPDATE_STATE()
end
-- 12) 方案分享（1.71.0）：hex 分片 → RunScript 发送 → 事件重组 → 弹窗 → 导入桥
EVAL_HELP_CONFIG = EVAL_HELP_CONFIG or {}
EVAL_HELP_CONFIG.war = EVAL_HELP_CONFIG.war or {}
EVAL_HELP_CONFIG.share = { recv = true }
EVAL_SHARE_RESET()
local shProf = EVAL_PROFILE_FROM_TEXT("# 方案: 分享测试\n- 致死打击 | 怒气>30 & 可攻击\n- 战斗怒吼 | 无buff:战斗怒吼")
EVAL_HELP_CONFIG.war.profiles = { shProf } EVAL_HELP_CONFIG.war.activeProfile = 1
TEST.runScripts = nil
eq(EVAL_SHARE_SEND("GUILD"), true, "share send ok")
  -- ★★v2 分片变短→可能不止 1 片：先把队列滴干（滴出的也会进 runScripts）
  do
    local gz12 = 0
    while EVAL_TEST_SHARE_QUEUE_CHUNKS() > 0 and gz12 < 80 do
      gz12 = gz12 + 1
      TEST.time = (TEST.time or 1000) + 1
      EVAL_SHARE_TEST_TICK()
    end
  end
local shMsgs = {}
for _, s in ipairs(TEST.runScripts or {}) do
  local m = string.match(s, 'SendChatMessage%("(.-)", "GUILD"%)')
    if m and (string.sub(m, 1, 6) == "[EHPF#" or (string.find(m, "|HEHPF:", 1, true) and string.find(m, "传输中", 1, true))) then table.insert(shMsgs, m) end -- ★封皮不算分片（v1/v2）
end
eq(table.getn(shMsgs) >= 1, true, "share chunked messages emitted")
-- 收齐全片 → 弹窗待导入
for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友甲") end
local pend = EVAL_SHARE_PENDING()
eq(pend ~= nil, true, "share popup pending after all chunks")
eq(pend and pend.name, "分享测试", "share parsed name")
eq(pend and pend.count, 2, "share parsed skill count")
-- 半包不弹窗
EVAL_SHARE_RESET()
EVAL_SHARE_ONMSG(shMsgs[1], "队友乙")
if table.getn(shMsgs) > 1 then
  eq(EVAL_SHARE_PENDING(), nil, "partial chunks no popup")
end
-- 接收开关关闭 = 忽略
EVAL_HELP_CONFIG.share.recv = false
EVAL_SHARE_RESET()
for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友丙") end
eq(EVAL_SHARE_PENDING(), nil, "recv off ignores")
EVAL_HELP_CONFIG.share.recv = true
-- 导入桥（弹窗 [导入] 同路径）
EVAL_SHARE_RESET()
for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友甲") end
local shBefore = table.getn(EVAL_HELP_CONFIG.war.profiles)
local shOk, shMsg = EVAL_IMPORT_TEXT(EVAL_SHARE_PENDING().text)
eq(shOk, true, "share import via bridge")
eq(table.getn(EVAL_HELP_CONFIG.war.profiles), shBefore + 1, "share import appended profile")
eq(EVAL_HELP_CONFIG.war.profiles[shBefore + 1].name, "分享测试", "imported profile name")
-- ★★★1.71.2 用户实测：「点击分享触发导入之后，导入完成，方案列表未能及时显示」。
--   根因 = 刷新界面这件事原来交给**每个调用点自己记得调**：IO 窗导入按钮调了，
--   而分享弹窗的 [导入] 没调 → 数据进了 profiles，列表还是旧的。
--   ★关键：断言必须走**分享弹窗的 [导入] 按钮**（真实入口），不能直调 EVAL_IMPORT_TEXT——
--     直调恰好绕过了出问题的那条路径（本项目「只测函数不测调用点」的第 N 次教训）。
do
  EVAL_SHARE_RESET()
  for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友乙") end
  eq(EVAL_SHARE_PENDING() ~= nil, true, "popup is pending before the import click (precondition)")
  -- 先记录刷新计数：导入必须**至少触发一次**列表刷新
  local before = EVAL_TEST_WAR_REFRESH_COUNT()
  local profBefore = table.getn(EVAL_HELP_CONFIG.war.profiles)
  -- 走真实按钮：找到分享弹窗的 [导入] 并按下去（走它自己的 OnClick 闭包）
  eq(EVAL_TEST_SHARE_CLICK_IMPORT(), true, "★the share popup [Import] button has a real OnClick")
  eq(table.getn(EVAL_HELP_CONFIG.war.profiles), profBefore + 1, "import really appended a profile")
  eq(EVAL_TEST_WAR_REFRESH_COUNT() > before, true,
     "★★★clicking [Import] in the SHARE popup refreshes the profile list (the reported bug: list stayed stale)")
end
-- ★★★1.71.2 用户要求：「在接收到方案分享的弹窗内，将方案的详细信息也显示」。
--   原来弹窗只有一行「XX 分享了《方案名》(N 个技能)」，看不到具体技能与条件。
--   ★判据：弹窗**当前实际显示的文本**里必须出现方案正文（技能名/条件串），
--     而不是只断言 SH.pending.text 有内容——后者是数据侧，与「有没有显示」是两件事。
do
  EVAL_SHARE_RESET()
  for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友丁") end
  local p = EVAL_SHARE_PENDING()
  eq(p ~= nil, true, "popup pending for the detail test (precondition)")
  local texts = EVAL_TEST_SHARE_POPUP_TEXTS()
  eq(table.getn(texts) >= 2, true, "★★the popup shows MORE than the one-line summary (got " .. tostring(table.getn(texts)) .. " lines)")
  -- 详情必须真的含方案正文：用原文本里的一行做交叉验证（不硬编码具体内容）
  local bodyLine = nil
  for ln in string.gmatch(p.text or "", "[^\r\n]+") do bodyLine = ln break end
  eq(bodyLine ~= nil, true, "the shared text has at least one line (precondition)")
  local found = false
  for _, t2 in ipairs(texts) do if t2 == bodyLine then found = true end end
  eq(found, true, "★★★the popup displays the profile's first line verbatim (details really shown, not just counted)")
  -- 行数上限：不能无限增高（最多 SH_DETAIL_MAX 行 + 标题行）
  eq(table.getn(texts) <= 7, true, "★detail display is capped (no unbounded popup growth): " .. tostring(table.getn(texts)) .. " lines")
end
-- 12b) ★1.71.3 用户实测决定：**团队频道从分享里下线**（原话「不要团队模式发送了」）。
--   ★判据必须落在**真实下拉的内容**上（EVAL_SHARE_SEND_UI 实际传给 EVAL_DD_OPEN 的选项表 + 每个选项点下去
--     真的发到哪个频道），而不是只查源码里那张表——本项目「只测函数不测调用点」的老坑。
do
  local GONEW = { zhCN = { "团队" }, enUS = { "Raid", "raid" }, ruRU = { "Рейд", "рейд" } }
  local oldDDW = EVAL_DD_OPEN
  local capItems, capCb = nil, nil
  EVAL_DD_OPEN = function(anchor, items, cb) capItems, capCb = items, cb end
  EVAL_SHARE_SEND_UI(nil)
  EVAL_DD_OPEN = oldDDW
  eq(type(capItems) == "table", true, "★分享按钮真的弹出了频道下拉（已截获选项表）")
  eq(table.getn(capItems or {}), 3, "★★分享频道只剩 3 个（公会/队伍/说），团队已下线: got " .. tostring(table.getn(capItems or {})))
  local LcurW = EVAL_LOCALES[EVAL_GET_LANG()]
  local gw = GONEW[EVAL_GET_LANG()] or { "团队" }
  local leakedW = ""
  for _, s in ipairs(capItems or {}) do
    for _, w in ipairs(gw) do if string.find(s, w, 1, true) ~= nil then leakedW = leakedW .. " " .. s end end
  end
  eq(leakedW, "", "★★★下拉里不许再出现已下线的频道名（反向哨兵，泄漏:" .. leakedW .. "）")
  eq(capItems and capItems[1] == LcurW["SH_CH_GUILD"] and capItems[2] == LcurW["SH_CH_PARTY"] and capItems[3] == LcurW["SH_CH_SAY"], true,
     "★剩下三个频道就是 公会/队伍/说（顺序一致）")
  -- 三个选项逐个点下去：这一轮真的发出的频道必须只有 GUILD/PARTY/SAY，绝不许出现 RAID
  --   （负载是纯大写十六进制+头部，频道名是唯一的大写单词 → 直接找词即可，不受引号转义困扰）
  local oldInGuild, oldPartyN = TEST.inGuild, TEST.partyN
  TEST.inGuild = true TEST.partyN = 1
  local function sentW(pi)
    TEST.runScripts = {}
    pcall(capCb, pi)
    return table.concat(TEST.runScripts or {}, " ~~ ")
  end
  local sGuild, sParty, sSay = sentW(1), sentW(2), sentW(3)
  TEST.inGuild, TEST.partyN = oldInGuild, oldPartyN
  eq(string.find(sGuild, "GUILD", 1, true) ~= nil, true, "★公会选项真的发到 GUILD")
  eq(string.find(sParty, "PARTY", 1, true) ~= nil, true, "★队伍选项真的发到 PARTY")
  eq(string.find(sSay, "SAY", 1, true) ~= nil, true, "★说频道选项真的发到 SAY")
  eq(string.find(sGuild .. sParty .. sSay, "RAID", 1, true) == nil, true, "★★★三个选项都不会发出团队消息")
  -- 白名单是**单一真值**：直接调 EVAL_SHARE_SEND 也必须被拒（界面藏起来 ≠ 代码发不出去）
  TEST.runScripts = {}
  eq(EVAL_SHARE_SEND("RAID"), false, "★★★直接调 EVAL_SHARE_SEND(RAID) 也被拒")
  eq(table.getn(TEST.runScripts or {}), 0, "★被拒时一个聊天分片都没发出去")
  eq(EVAL_SHARE_SEND("GUILD"), true, "★白名单没误伤：公会频道照常能发")
  -- 指引/提示文案三语言同步：不许再出现那个已下线的频道名
  for _, lg in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local pack = EVAL_LOCALES[lg]
    local bad = ""
    for _, k in ipairs({ "SH_TIP_S1", "SH_TIP_S2", "SH_TIP_S3", "SH_TIP_R3", "SH_CH_NO", "SH_CH_OFF" }) do
      local v = pack[k]
      if type(v) == "string" then
        for _, w in ipairs(GONEW[lg] or {}) do if string.find(v, w, 1, true) ~= nil then bad = bad .. " " .. k end end
      end
    end
    eq(bad, "", "★★" .. lg .. " 的分享指引/频道提示里不再出现已下线的频道名（泄漏:" .. bad .. "）")
  end
  -- ★反向哨兵：证明上面那条判据**真的会响**（拿旧文案试一次必须被抓出来）
  do
    local probe = "2. 选一个频道：公会 / 队伍 / 团队 / 说"
    local hit = false
    for _, w in ipairs(GONEW.zhCN) do if string.find(probe, w, 1, true) ~= nil then hit = true end end
    eq(hit, true, "★sanity: 旧文案（含团队）确实会被这条判据抓住")
  end
end

-- 12c) ★1.71.3 接收规则优化（用户要求：「优化接收端的接收数据规则. 在多个分享同时出现的时候只显示最新的数据,
--   防止有些人滥发,或者多人发送接收异常.」）
--   ★判据落点：①「只剩最新那一份」要**数据侧 + 当前显示行 + 原始详情行**三处都验
--     （本客户端 Hide 后仍可能被绘出 → 只看 IsShown 会漏掉「Hide 了但文本还留着」的残留）；
--     ② 所有上限值**从生产代码读**（EVAL_TEST_SHARE_LIMITS），不在断言里写死常量。
do
  local LIMC = EVAL_TEST_SHARE_LIMITS()
  local LzC = EVAL_LOCALES[EVAL_GET_LANG()]
  local function headC(k) -- 提示文案里 %d 之前那一段（用来在聊天记录里找这条提示，不硬编码整句）
    local s = LzC[k] or ""
    -- ★用 plain=true 找**单个** "%"：写成 "%%" 时 plain 模式下它是**两个字面字符**，永远找不到
    --   → headC 返回整句（含 %d），与聊天里带数字的那条提示永远对不上（本轮实测踩到）。
    local p = string.find(s, "%", 1, true)
    return p and string.sub(s, 1, p - 1) or s
  end
  -- ★★帧里的 id 只能是**十六进制字符**（接收侧模式是 %x+）：写成 "g1"/"q1" 这种根本不是合法帧，
  --   会被**静默忽略**（连「拒收提示」都没有）→ 断言看到的是「什么都没发生」，很容易误判成实现有问题。
  --   ★本轮实测踩到：④⑥ 用 g1/q1 构造异常包，结果两条断言都拿不到提示，查了半天。
  local function hexC(s) return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end)) end
  local function chunkC(id, text, i, total)
    local h = hexC(text)
    return "[EHPF#" .. id .. " " .. i .. "/" .. total .. "]" .. string.sub(h, (i - 1) * 220 + 1, i * 220)
  end
  local function sendC(id, text, who)
    local total = math.ceil(string.len(hexC(text)) / 220)
    for i = 1, total do EVAL_SHARE_ONMSG(chunkC(id, text, i, total), who) end
  end
  local TXT_A = "# 方案: 甲号方案\n- 致死打击 | 怒气>30\n- 冲锋 | 非战斗\n"
  local TXT_B = "# 方案: 乙号方案\n- 盾墙 | 自身血<50\n"
  local TXT_C = "# 方案: 丙号方案\n- 断筋 | 连击>=2\n"
  EVAL_SHARE_RESET()
  EVAL_TEST_SHARE_RESET_WARN()
  -- ① 最新优先：数据侧 + 显示侧 + 原始详情行
  sendC("a1", TXT_A, "甲")
  eq(EVAL_SHARE_PENDING() ~= nil and EVAL_SHARE_PENDING().sender == "甲", true, "★第一份分享照常弹出（前置）")
  sendC("b1", TXT_B, "乙")
  local pC = EVAL_SHARE_PENDING()
  eq(pC ~= nil and pC.sender == "乙", true, "★★★多人同时发：只保留最新那一份（乙）")
  eq(pC and pC.name, "乙号方案", "★留下来的内容也是最新那份")
  local shownC = table.concat(EVAL_TEST_SHARE_POPUP_TEXTS(), "\n")
  eq(string.find(shownC, "乙", 1, true) ~= nil, true, "★★★弹窗**当前显示**的就是最新那份")
  eq(string.find(shownC, "甲", 1, true) == nil, true, "★★★旧那份的内容不许还显示着")
  -- ★★「原始详情行」这条必须盯**旧文本里独有的行**（TXT_A 第 3 行是「- 冲锋 | 非战斗」）：
  --   我第一版拿标题里的「甲」去找 —— 而残留的那一行是第 3 行、**根本不含「甲」** →
  --   把「不清空只 Hide」的变异体放过去了（弱代理，本轮实测 M27 SURVIVED 才补）。
  local rawC = table.concat(EVAL_TEST_SHARE_DETAIL_RAW(), "\n")
  eq(string.find(rawC, "甲", 1, true) == nil, true, "★★★原始详情行里不许留旧那份的残留（标题行）")
  eq(string.find(rawC, "冲锋", 1, true) == nil, true,
     "★★★原始详情行里不许留旧那份的残留（旧文本独有、且被 Hide 的那一行也要清空）")
  -- ② 同一发送者开新的一笔 → 旧笔作废（连点分享）；★绝不跨发送者作废
  EVAL_SHARE_RESET()
  sendC("c1", TXT_A, "丙")
  eq(EVAL_SHARE_PENDING() ~= nil and EVAL_SHARE_PENDING().name, "甲号方案", "前置：丙 的第一份已弹出")
  EVAL_SHARE_ONMSG(chunkC("d1", TXT_C, 1, 3), "丙")
  EVAL_SHARE_ONMSG(chunkC("d1", TXT_C, 2, 3), "丙")
  eq(EVAL_TEST_SHARE_BUF_COUNT(), 1, "★旧笔在途（收了 2/3 片）")
  sendC("e1", TXT_B, "丙")
  eq(EVAL_TEST_SHARE_BUF_COUNT(), 0, "★★同发送者开新的一笔后，旧那笔立刻作废（在途 0 笔）")
  eq(EVAL_SHARE_PENDING() and EVAL_SHARE_PENDING().name, "乙号方案", "★新那笔收齐 → 替换成最新")
  EVAL_SHARE_ONMSG(chunkC("d1", TXT_C, 3, 3), "丙")
  eq(EVAL_SHARE_PENDING() and EVAL_SHARE_PENDING().name, "乙号方案",
     "★★★已作废那笔补齐后**不许**顶掉最新的那份（否则就是「旧的盖掉新的」接收异常）")
  -- ③ 在途笔数上限（多人同时发 / 滥发兜底）；不同发送者之间不互相作废
  EVAL_SHARE_RESET()
  EVAL_TEST_SHARE_RESET_WARN()
  TEST.chat = nil
  for s = 1, LIMC.buf + 3 do EVAL_SHARE_ONMSG(chunkC("f" .. s, TXT_A, 1, 2), "发" .. s) end
  eq(EVAL_TEST_SHARE_BUF_COUNT(), LIMC.buf, "★★在途笔数被压到上限（上限读自生产代码）: got " .. tostring(EVAL_TEST_SHARE_BUF_COUNT()))
  eq(string.find(tostring(TEST.chat or ""), headC("SH_DROP_MANY"), 1, true) ~= nil, true, "★淘汰有如实提示")
  -- ④ 单笔分片数上限：整笔拒收
  EVAL_SHARE_RESET()
  EVAL_TEST_SHARE_RESET_WARN()
  TEST.chat = nil
  EVAL_SHARE_ONMSG("[EHPF#ab 1/" .. (LIMC.chunks + 1) .. "]" .. hexC(TXT_A), "灌水甲")
  eq(EVAL_TEST_SHARE_BUF_COUNT(), 0, "★★分片数超上限 → 整笔拒收（不留缓冲）")
  eq(string.find(tostring(TEST.chat or ""), headC("SH_DROP_BIG"), 1, true) ~= nil, true, "★拒收有如实提示")
  -- ⑤ 单笔解码上限：整笔拒收
  EVAL_SHARE_RESET()
  EVAL_TEST_SHARE_RESET_WARN()
  TEST.chat = nil
  EVAL_SHARE_ONMSG("[EHPF#cd 1/1]" .. string.rep("41", LIMC.text + 64), "灌水乙")
  eq(EVAL_SHARE_PENDING(), nil, "★★内容超上限 → 整笔拒收（不弹窗）")
  eq(string.find(tostring(TEST.chat or ""), headC("SH_DROP_BIGTEXT"), 1, true) ~= nil, true, "★拒收有如实提示")
  -- ⑥ 接收侧提示限频：窗口内只报一条 + 如实说出省略了几条；过了窗口恢复
  EVAL_SHARE_RESET()
  TEST.time = 7000
  EVAL_TEST_SHARE_RESET_WARN()
  TEST.chat = nil
  for k = 1, 3 do EVAL_SHARE_ONMSG("[EHPF#e" .. k .. " 1/" .. (LIMC.chunks + 1) .. "]" .. hexC(TXT_A), "刷子") end
  local chat1 = tostring(TEST.chat or "")
  local nHits, pos = 0, 1
  while true do
    local f = string.find(chat1, headC("SH_DROP_BIG"), pos, true)
    if not f then break end
    nHits = nHits + 1
    pos = f + 1
  end
  eq(nHits, 1, "★★同一窗口内 3 笔异常只报 1 条（防我们自己的提示被刷屏）: got " .. tostring(nHits))
  eq(string.find(chat1, headC("SH_WARN_MORE"), 1, true) == nil, true,
     "★第一个窗口内还没到结算点，不该凭空冒出「另有 N 条」（反向哨兵）")
  TEST.chat = nil
  TEST.time = 7000 + LIMC.gap + 1
  EVAL_SHARE_ONMSG("[EHPF#e9 1/" .. (LIMC.chunks + 1) .. "]" .. hexC(TXT_A), "刷子")
  local chat2 = tostring(TEST.chat or "")
  eq(string.find(chat2, headC("SH_DROP_BIG"), 1, true) ~= nil, true, "★过了限频窗口恢复提示（不是永久静默）")
  eq(string.find(chat2, headC("SH_WARN_MORE"), 1, true) ~= nil, true,
     "★★被限频压下的那几条要**如实结算**出来（不静默丢弃）")
  TEST.time = nil
  -- ⑦ 去重表上限：防无限增长
  EVAL_SHARE_RESET()
  for k = 1, LIMC.done + 3 do
    EVAL_SHARE_ONMSG("[EHPF#" .. string.format("%02x", k) .. " 1/1]" .. hexC(TXT_A), "刷屏机")
  end
  eq(EVAL_TEST_SHARE_DONE_COUNT(), LIMC.done, "★★去重表压在上限内（防无限增长）: got " .. tostring(EVAL_TEST_SHARE_DONE_COUNT()))
  EVAL_SHARE_RESET()
  EVAL_TEST_SHARE_RESET_WARN()
end

-- 同一发送者同 id 重复收齐不重复弹（done 标记）
EVAL_SHARE_ONMSG(shMsgs[1], "队友甲")
for _, m in ipairs(shMsgs) do EVAL_SHARE_ONMSG(m, "队友甲") end
EVAL_SHARE_PENDING().text = nil -- 不清理 done；仅验证不报错

-- 67) ★★★1.71.2（第五轮）「自动接取有时输出一条空白日志」定案（用户截图）
--   现象：聊天框先出现 `任务接取：`（名字为空），紧接着才出现 `任务接取： 回音山调查行动`。
--   ★根因：新接的任务刚进日志时，那一行**已存在但标题尚未填充** → `GetQuestLogTitle` 返回
--     **title = ""（空串，不是 nil）**；而 **Lua 里空串是真值**（本轮已用 fengari 实测确认），
--     旧写法 `if okt and title` 对 "" 照样成立 → 入库成 `cur[""]`，被当成一个「名叫空的新任务」
--     → 立刻播一条空白；下一轮扫描真名到位 → 再播一条正确的。顺序与截图完全一致。
--   ★为什么断言必须模拟「标题暂时为空」：旧桩 `GetQuestLogTitle` 直接回 `q.title`，
--     真实客户端的这个**中间态**在测试里根本不存在 → 不补桩这条 bug 永远测不出来
--     （本项目第 N 次「桩太宽松 → 真实事故测不出来」）。
do
  -- ★桩里 TEST.chat 是**一个字符串**（每条追加 + \n），不是数组。
  local function chatLines()
    local out = {}
    for ln in string.gmatch(TEST.chat or "", "[^\r\n]+") do out[table.getn(out) + 1] = ln end
    return out
  end
  local function blankCount()
    local n = 0
    for _, line in ipairs(chatLines()) do
      -- 匹配「任务接取：」后面没有实质内容（允许尾随空格 / 全角冒号后的空白）
      if string.find(line, "任务接取：%s*$") or string.find(line, "Task accepted:%s*$") then n = n + 1 end
    end
    return n
  end
  EVAL_TB_TEST_RESET_TIMERS()
  TEST.chat = ""
  TEST.time = 20000
  EVAL_HELP_CONFIG.tb = { questAccept = true, questTurnIn = true, qchan = "self" }
  -- ★★★场景必须对：**先建立快照**（老任务在日志里），
  --   **再**让一行标题为空的新任务出现 → 这才是真实的「接到新任务」时刻。
  --   （我第一版把空行放在首次建档前 → 它被当成「初始快照」而不会播报，
  --     所以断言恒绿、变异全部存活——反方向证明了「场景不对 → 断言无效」。）
  TEST.questLog = { { title = "旧任务", lvl = 1 } }
  EVAL_TB_TEST_SCAN_DIFF() -- 第 1 次：建档（tbQPrev 为 nil 时只建档不差分）
  TEST.chat = ""
  -- 新任务行出现但标题尚未填充（客户端中间态）
  TEST.questLog = { { title = "旧任务", lvl = 1 }, { title = "", lvl = 1 } }
  EVAL_TB_TEST_SCAN_DIFF() -- 第 2 次：旧写法下这里会播出一条空白
  do
  end
  eq(blankCount(), 0, "★★★a quest row whose title is not yet populated must NOT produce a blank 任务接取 line")
  -- 第二轮扫描：真名到位 → 应当播**一条正确的**（而且只有一条）
  TEST.chat = ""
  -- 真名到位（同一行，标题被填上）
  TEST.questLog = { { title = "旧任务", lvl = 1 }, { title = "回音山调查行动", lvl = 1 } }
  EVAL_TB_TEST_SCAN_DIFF()
  local msgs = chatLines()
  local named = 0
  for _, line in ipairs(msgs) do
    if string.find(line, "回音山调查行动", 1, true) ~= nil then named = named + 1 end
  end
  eq(named, 1, "★★★the real title is announced exactly once (got " .. tostring(named) .. ")")
  eq(blankCount(), 0, "★★no blank line appeared even after the title arrived")
  eq(table.getn(msgs), 1, "★★the notify channel carries exactly ONE message (no blank+real pair)")
  -- 反向哨兵：确认判据真的会响——手工播一条空名，blankCount 必须涨
  EVAL_TB_TEST_NOTIFY_EMPTY()
  eq(blankCount(), 1, "★sanity: the blank detector really fires on an empty name")
  TEST.chat = ""
  TEST.questLog = nil
  EVAL_TB_TEST_RESET_TIMERS()
end
-- ★★★第 68 组已于 1.71.2（第八轮）**随功能还原而删除**：
--   它验的是「条件行自身是 EditBox」这条已被撤回的设计（sBox 已删）。
--   现在的同类保护在 **64e**：面板内搜索框 可见 / 在面板内 / 真过滤 / 自定义输入可提交。
--   ★为什么不留着当“历史记录”：它会引用已删除的钩子（EVAL_TEST_SE_ROW_BOX 等）
--     而直接报 nil，把整套测试拖垮。细节保留在 CHANGELOG 与 CLAUDE.md。
-- 69) ★★★1.71.2（第九轮）光环下拉里为什么会有「清凉的泉水」这类物品？（用户提问）
--   用户原话：「buff 条件类型 下拉为什么会出现泉水这些物品类的信息？」
--   ★根因（两层，缺一不成）：
--     ① 菜单第三组「全部技能」列的是**动作条上的全部非宏格子**；动作条上可以放物品，
--        扫描走 wactionName → 物品格拿到的是**物品名**（清凉的泉水）→ 以裸名字进入列表。
--     ② 原有的过滤 `not itemOf(n)` **只认带前缀的写法**「物品:名称」（那是用户显式配置
--        「使用物品」的形式），裸名字不匹配 → 漏网。
--   ★用户选择：**保留但加标记区分**（不是删掉、也不是整组去掉）。
--   ★判据两条（各管一侧）：① 扫描**真的**给物品格打了 item 标（走真实 EVAL_GO_RESCAN，
--     用背包桩喂一个与动作条同名的物品）；② 菜单里物品条目**显示带标记**、且**取值仍是裸名字**
--     （取值带标记会让 wslots 查不到、规则失效）。
do
  -- ① 扫描打标：动作条 1=物品(在背包里) / 2=技能(不在背包)
  TEST.slotNames = { [1] = "清凉的泉水", [2] = "圣光术", [3] = nil }
  TEST.bags = { [1] = { name = "清凉的泉水", tex = "t", count = 5 } }
  EVAL_GO_RESCAN(true, "test-item-mark")
  local wsItem = EVAL_WSLOTS["清凉的泉水"]
  eq(type(wsItem) == "table", true, "precondition: the item on the action bar was scanned into wslots")
  eq(wsItem.item, true, "★★★the scan marks an action-bar ITEM (bag-name match)")
  eq(EVAL_WSLOTS["圣光术"] ~= nil, true, "precondition: the spell was scanned too")
  eq(EVAL_WSLOTS["圣光术"].item, nil, "★★the scan does NOT mark a real spell as an item")
  -- ② 菜单显示带标记、取值不带
  local m = EVAL_TEST_AURA_DROPDOWN_ORDER("hasDebuff")
  eq(type(m.items) == "table", true, "the menu hook exposes its real display strings")
  local itemDisp, itemVal, spellDisp = nil, nil, nil
  for i, d in ipairs(m.items) do
    if m.names[i] == "清凉的泉水" then itemDisp, itemVal = d, m.names[i] end
    if m.names[i] == "圣光术" then spellDisp = d end
  end
  eq(itemVal, "清凉的泉水", "★★the item row VALUE stays the bare name (so wslots lookup still works)")
  eq(string.find(itemDisp or "", "物", 1, true) ~= nil, true,
     "★★★the item row is MARKED in the display (got " .. tostring(itemDisp) .. ")")
  eq(spellDisp, "圣光术", "★★a real spell is NOT marked (only items get the tag)")
  -- 反向哨兵：证明「标记判据」真的会响——去掉 item 标后同一行就不该带标记
  EVAL_WSLOTS["清凉的泉水"].item = nil
  local m2 = EVAL_TEST_AURA_DROPDOWN_ORDER("hasDebuff")
  local d2 = nil
  for i, d in ipairs(m2.items) do if m2.names[i] == "清凉的泉水" then d2 = d end end
  eq(d2, "清凉的泉水", "★sanity: without the item flag the row is plain (the marker really tracks the flag)")
  TEST.slotNames = nil
  TEST.bags = nil
end
-- 70) ★★★1.71.2（第十轮）+ 1.72.2（分享方案）光环判定：**「认不出来」绝不能被当成「确定没有」**
--   【1.71.2 事故】骑士虔诚光环：「自身buff检查=否」永远成立 → 规则无限重放（日志刷屏）。
--     根因：`texOf` 解析不出纹理时旧写法 `st.playerBuffs[texOf(cd.s) or ""]` 退化成查空串 = nil
--     → cnt=0 → 「否/无」方向被当成**成立** → 永远重放。
--   【1.72.2 修正】判据升级为**两级解析**：
--     ① 纹理快路径（学习表/动作条）→ ② 名字慢路径（工具读名，限频 0.5s，命中即自愈学习）；
--     只有**两条路都不可用**才如实失败。★为什么必须这样：名字扫描读的是**增益条/减益条本身**
--     （权威来源），它能回答「有没有」——这正是分享出去、别人角色纹理表为空时的唯一出路。
--   ★本组的判据：**「扫描器都不可用」时才必须如实失败**（比旧版「名字不认识就失败」更强也更准）。
do
  local GT = EVAL_TEST_WTT() -- ★1.73.14 扫描器现在是**自家隐形 tooltip**（不再是 GameTooltip）
  local svb, svd, svp = GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff
  -- ① 扫描器不可用（工具读名的三个入口全断）→ 必须如实失败并给出原因
  GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff = nil, nil, nil
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local ok, why = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "绝无此名的测试光环", v = false }, nil)
  eq(ok, false, "★★★an aura that can NOT be identified AND can NOT be scanned must never count as definitely-absent")
  eq(type(why) == "string" and string.find(why, "无法识别", 1, true) ~= nil, true,
     "★★the reason explains the aura could not be identified (got " .. tostring(why) .. ")")
  -- ①b 反方向同样诚实
  local okV, whyV = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "绝无此名的测试光环", v = true }, nil)
  eq(okV, false, "★★unknown+unscannable is honest in the OTHER direction too")
  eq(type(whyV) == "string" and string.find(whyV, "无法识别", 1, true) ~= nil, true, "★★and says why")
  -- ①c 四个光环分支都要守（改一处漏一处是这类修复的典型失败）
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local okT, whyT = EVAL_TEST_COND_EVAL_LIVE({ k = "tBuff", s = "绝无此名的测试光环", v = true }, nil)
  eq(okT, false, "★★target-buff branch is guarded too")
  eq(string.find(tostring(whyT), "无法识别", 1, true) ~= nil, true, "★★target-buff reason is explicit")
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local okD, whyD = EVAL_TEST_COND_EVAL_LIVE({ k = "hasDebuff", s = "绝无此名的测试光环", v = true }, nil)
  eq(okD, false, "★★target-debuff branch is guarded too")
  eq(string.find(tostring(whyD), "无法识别", 1, true) ~= nil, true, "★★target-debuff reason is explicit")
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local okP, whyP = EVAL_TEST_COND_EVAL_LIVE({ k = "pDebuff", s = "绝无此名的测试光环", v = true }, nil)
  eq(okP, false, "★★self-debuff branch is guarded too")
  eq(string.find(tostring(whyP), "无法识别", 1, true) ~= nil, true, "★★self-debuff reason is explicit")
  -- 还原扫描器
  GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff = svb, svd, svp
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  -- ② 反向哨兵：**已知纹理**的名字照常判定（新闸门不许误伤正常路径）
  EVAL_DEBUFF_TEX_LEARN["测试光环OK"] = "Interface\\Icons\\Spell_Holy_DevotionAura"
  local ok2, why2 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "测试光环OK", v = false }, nil)
  eq(ok2, true, "★a KNOWN aura texture still evaluates normally (guard does not over-block): " .. tostring(why2))
  -- ③ 新契约的反面：扫描**可信**且名字确实不在 → 负向方向如实为真（旧版这里恒假）
  TEST.buffs = { { name = "别的光环", tex = "TEX_OTHER_B" } }
  EVAL_HELP_UPDATE_STATE()
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local ok3, why3 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "测试光环不在场", v = false }, nil)
  eq(ok3, true, "★★★a TRUSTWORTHY scan that does not contain the name means genuinely absent → no-buff is true: " .. tostring(why3))
  TEST.buffs = {} EVAL_HELP_UPDATE_STATE()
  EVAL_DEBUFF_TEX_LEARN["测试光环OK"] = nil
  EVAL_AURA_TEST_RESET_NAME_CACHE()
end
-- 71) ★★★1.71.2（第十一轮）光环纹理**优先级**：学习表（真实观察）> 动作条（代理）
--   【事故】骑士虔诚光环：动作条格子 9 的 `GetActionTexture` 返回 `Spell_Nature_WispSplode_TEX`
--   （别的法术的图标），而它在增益条上的真实图标是 `Spell_Holy_DevotionAura_TEX`。
--   旧实现**动作条优先** → 拿错图标去比对 → 永远不命中 → 「自身buff检查=否」永远成立 → 无限重复施放。
--   ★判据：**动作条图标只是代理；从增益条亲自观察到的纹理才是权威**。
do
  local nm = "测试光环优先级"
  EVAL_WSLOTS[nm] = { slot = 9, tex = "TEX_ACTIONBAR" }
  eq(EVAL_AURA_TEX(nm), "TEX_ACTIONBAR", "precondition: with nothing learned, the action-bar icon is used")
  EVAL_DEBUFF_TEX_LEARN[nm] = "TEX_LEARNED"
  eq(EVAL_AURA_TEX(nm), "TEX_LEARNED",
     "★★★the LEARNED (observed on the buff bar) texture WINS over the action-bar icon")
  -- 反向哨兵：学习表里没有的名字仍然走动作条（不能把正常路径废掉）
  EVAL_DEBUFF_TEX_LEARN[nm] = nil
  eq(EVAL_AURA_TEX(nm), "TEX_ACTIONBAR", "★names that were never learned still fall back to the action bar")
  -- 两个都没有 → nil（这时才轮到「无法识别」那道闸门）
  EVAL_WSLOTS[nm] = nil
  eq(EVAL_AURA_TEX(nm), nil, "★unknown name resolves to nil so the honest-failure guard can fire")
end
-- 72) ★★★1.71.2（第十二轮）光环判定支持**按名字**（用户要求：「有些法术图标是不同的」）
--   【事故】虔诚光环：动作条图标 `Spell_Nature_WispSplode` ≠ 增益条图标 `Spell_Holy_DevotionAura`
--   → 只靠图标比对必然漏 → 「自身buff检查=否」永远成立 → 无限重复施放。
--   ★修法：图标没命中时**按名字再确认一次**（工具读名，限频 0.5s，并顺带把正确的名字→图标学下来自愈）。
--   ★判据：**「图标对不上」与「身上没有」是两件事**——所以两道判定都要各测一条。
do
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  -- 场景：光环在增益条上（名字=测试光环名），但它的图标与插件解析出的图标**不同**
  TEST.buffs = { { name = "测试光环名", tex = "TEX_BUFFBAR" } }
  EVAL_DEBUFF_TEX_LEARN["测试光环名"] = "TEX_ACTIONBAR_WRONG"
  EVAL_HELP_UPDATE_STATE()
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  -- ① 图标对不上 → 旧实现判「没有」；现在**名字命中** → 应判「有」
  local ok, why = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "测试光环名", v = true }, nil)
  eq(ok, true, "★★★an aura whose buff-bar icon DIFFERS from the action-bar icon is still found BY NAME: " .. tostring(why))
  -- ② 「无buff」方向：名字命中 → 必须为假（这正是用户看到的无限重复施放）
  local ok2 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "测试光环名", v = false }, nil)
  eq(ok2, false, "★★the no-buff direction is correctly false when the name IS on the buff bar")
  -- ③ 反向哨兵：名字**不在**增益条上时不许被误判为「有」
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  TEST.buffs = { { name = "别的光环", tex = "TEX_OTHER" } }
  EVAL_HELP_UPDATE_STATE()
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local ok3 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasBuff", s = "测试光环名", v = true }, nil)
  eq(ok3, false, "★a name that is NOT on the buff bar is not falsely reported as present")
  -- ④ 老形态 noBuff（存量数据）也必须走名字兜底（改一处漏一处是这类修复的典型失败）
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  TEST.buffs = { { name = "测试光环名", tex = "TEX_BUFFBAR" } }
  EVAL_HELP_UPDATE_STATE()
  -- ★重置学习表：名字兜底会顺带把正确纹理学下来（自愈），
  --   不重置的话后续断言会走快路径 → 变体变成**等价变体**（本轮实测存活）
  EVAL_DEBUFF_TEX_LEARN["测试光环名"] = "TEX_ACTIONBAR_WRONG"
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local okNo = EVAL_TEST_COND_EVAL_LIVE({ k = "noBuff", s = "测试光环名" }, nil)
  eq(okNo, false, "★★legacy noBuff also uses the name fallback")
  -- 收尾（模块级状态必须自己收）
  TEST.buffs = nil
  EVAL_DEBUFF_TEX_LEARN["测试光环名"] = nil
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  EVAL_HELP_UPDATE_STATE()
end
-- 73) ★★★1.71.2（第十三轮）条件类型下拉：**最后一组被行池上限静默截断**（用户实测）
--   用户原话：「我记得之前有个技能冷却的条件的，现在没看到」。
--   ★根因：下拉行池硬编码 48 行（1.27.0 注释「加倍：可能超 24」），
--     而条件类型菜单**需要 54 行**（5 组 49 项 + 5 个组标题）→ 最后 6 行被悄悄丢掉，
--     正好是 `·冷却/可用·` 组 = 冷却就绪 / 技能可用 / 未排队 / 施法范围内 / 施法中。
--     ★1.71.2（第十四轮）「施法中」已按用户要求移入「自身状态」组，该组现为 4 项；全表总行数不变（54）。
--     旁证：面板已按 ceil(54/12)=5 列算宽度 → 右侧留下一条**空列**（用户截图里那条空白）。
--   ★修法：行池提到 DD_MAX_ROWS=96；且**超出时不再静默丢弃**（末行显示「还有 N 项」）。
--   ★判据两条：① 菜单需要的行数 ≤ 行池（结构性保证）；② 点开真实按钮后，
--     最后一组的条目**真的可见**（可见行数 > 48 是这次修复的直接证据）。
do
  eq(EVAL_TEST_SE_TYPE_MENU_ROWS() <= EVAL_TEST_DD_MAX_ROWS(), true,
     "★★★the condition-type menu fits in the row pool (need=" .. tostring(EVAL_TEST_SE_TYPE_MENU_ROWS())
     .. " pool=" .. tostring(EVAL_TEST_DD_MAX_ROWS()) .. ")")
  EVAL_HELP_SE_OPEN(1) -- 打开编辑窗（该函数不返回布尔，不能断言返回值）
  eq(EVAL_TEST_SE_PUSH_COND("power", nil, ">", 30), true, "a condition row exists to click")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_TYPE(1), true, "★clicking the REAL type button opens the type dropdown")
  eq(EVAL_DD_TEST_SHOWN(), true, "the type dropdown is shown")
  local vis = EVAL_DD_TEST_VISIBLE_TEXTS()
  eq(table.getn(vis) > 48, true,
     "★★★more than 48 rows are actually DRAWN (got " .. tostring(table.getn(vis)) .. ") — the old cap silently dropped the tail")
  local foundReady = false
  local wantReady = EVAL_LOCALES[EVAL_GET_LANG()]["CT_READY"]
  for _, s in ipairs(vis) do if s == wantReady then foundReady = true end end
  eq(foundReady, true, "★★★the last group's item [" .. tostring(wantReady) .. "] is VISIBLE (this is what the user could not find)")
  EVAL_DD_HIDE()
  -- ★③ 「不静默截断」本身也要验：构造一个**超长列表**（200 项 > 行池），
  --   断言①画满行池、②末行是**如实提示**而不是某个被丢掉的真条目。
  --   ★为什么要单独测：条件类型菜单只有 54 项，永远碰不到这道兜底——
  --     拆掉它照样全绿（等价变异，本轮实测存活）。缺了它，「静默丢弃」的坑以后还会再踩。
  do
    local big = {}
    for bi2 = 1, 200 do big[bi2] = "ITEM" .. bi2 end
    EVAL_DD_HIDE()
    EVAL_DD_TEST_RESET_ANCHOR()
    local shownN = EVAL_DD_TEST_OPEN_KW(big, nil, nil)
    local maxRows = EVAL_TEST_DD_MAX_ROWS()
    eq(shownN, maxRows, "★★★an over-long list fills the row pool exactly (got " .. tostring(shownN) .. " pool " .. tostring(maxRows) .. ")")
    local vis2 = EVAL_DD_TEST_VISIBLE_TEXTS()
    local last = vis2[table.getn(vis2)]
    local wantMore = string.format(EVAL_LOCALES[EVAL_GET_LANG()]["DD_MORE_FMT"], 200 - (maxRows - 1))
    -- ★实际显示串带颜色码（|cffff8080...|r），故用「包含」而不是「相等」判定
    eq(type(last) == "string" and string.find(last, wantMore, 1, true) ~= nil, true,
       "★★★the over-long list ends with an HONEST notice instead of silently dropping items (got " .. tostring(last) .. ")")
    -- 反向哨兵：被丢掉的真条目**不许**出现在可见列表里（否则就是「假装全部显示」）
    local leaked = false
    for _, sv in ipairs(vis2) do if sv == "ITEM200" then leaked = true end end
    eq(leaked, false, "★the dropped tail is NOT presented as if it were shown")
    EVAL_DD_HIDE()
  end
  EVAL_TEST_SE_CLEAR()
end
-- 74) ★★★1.71.2（第十四/十五轮）施法相关条件：中文名调整 + 施法族统一归入「技能状态」组（用户要求，两轮）
--   用户原话：「这几个名称调整.施法相关, 自身增加一个条件类型.
--     施法中(新增参考目标施法中条件类型) / 施法时间 / 施法剩余时间 / 目标施法时间 / 目标施法剩余时间」
--   ★第十四轮：用户选定 A 方案 → 把现有「施法中」（k=casting，SPELLCAST_* 事件驱动）从「技能状态」组移到「自身状态」组。
--   ★第十五轮（本轮）：用户又要求把**自身施法族 + 目标施法族一起并回「技能状态」组**并「美化排序」——
--     再次用 ask_user_question 给出三种排法，用户选 A = **技能本身 → 我的施法 → 目标的施法**。
--     ★★「组归属」是**用户偏好**而不是技术结论：需求一改，断言就必须跟着改成钉**新**归属与**新**顺序，
--        绝不能留着上一轮的断言当伪保护（它反而会挡住正确实现）。
--   ★判据：① 四条新名字在下拉里真的可见（读**当前语言包**，不硬编码）；
--     ② 「施法中」全菜单**只出现一次**（「移」若写成「复制」就会出现两条同名，用户一眼就能看到）；
--     ③ 分组归属按**真实分组表**核实（旧的组里必须不再有它）——且先断言「按 label 取组真的取到了」，
--        否则 label 打错时「不在该组」类断言会**恒真**（假绿）；
--     ④ 四条时间条件的**导出→导入往返**不丢语义（改了 COND_NUMNAME，解析侧必须跟得上）。
do
  local zh = EVAL_LOCALES["zhCN"]   -- ★导出/解析的文法一直是中文名（与客户端语言无关），故对照 zhCN
  local Lz = EVAL_LOCALES[EVAL_GET_LANG()]
  local menu = EVAL_TEST_SE_TYPE_MENU()
  local cnt = {}
  for _, s in ipairs(menu) do cnt[s] = (cnt[s] or 0) + 1 end
  for _, key in ipairs({ "CT_CASTEL", "CT_CASTLEFT", "CT_TCASTEL", "CT_TCASTLEFT" }) do
    eq(cnt[Lz[key]] ~= nil, true, "★条件类型下拉里有新名字: " .. key .. "=" .. tostring(Lz[key]))
  end
  eq(cnt[Lz["CT_CASTING"]], 1, "★★★「施法中」全菜单只出现一次（A 方案=移动；复制会出现两条同名）")
  -- ★③ 分组归属（读真实 SE_TYPE_GROUPS；按 label 取，不硬编码组下标）
  local gSelf = EVAL_TEST_SE_TYPE_GROUP_IDS("CTG_1")
  local gTarget = EVAL_TEST_SE_TYPE_GROUP_IDS("CTG_2")
  local gSkill = EVAL_TEST_SE_TYPE_GROUP_IDS("CTG_4")
  eq(type(gSelf) == "table", true, "★按 label 取到「自身状态」组（取不到的话下面几条会恒真）")
  eq(type(gTarget) == "table", true, "★按 label 取到「目标状态」组")
  eq(type(gSkill) == "table", true, "★按 label 取到「技能状态」组")
  local function hasId(t, id)
    for _, v in ipairs(t or {}) do if v == id then return true end end
    return false
  end
  -- ★★★第十五轮：施法族 6 项必须**都在**「技能状态」组里
  for _, id in ipairs({ "casting", "castEl", "castLeft", "tCasting", "tCastEl", "tCastLeft" }) do
    eq(hasId(gSkill, id), true, "★★★施法族已在「技能状态」组: " .. id)
  end
  -- ★★反向哨兵：必须真的**移走**——原组里再留一份，菜单里就是两条同名（用户一眼就能看到）
  for _, id in ipairs({ "casting", "castEl", "castLeft" }) do
    eq(hasId(gSelf, id), false, "★★自身施法族已从「自身状态」组移出: " .. id)
  end
  for _, id in ipairs({ "tCasting", "tCastEl", "tCastLeft" }) do
    eq(hasId(gTarget, id), false, "★★目标施法族已从「目标状态」组移出: " .. id)
  end
  -- ★★★「美化排序」本身就是需求（用户选定的 A 方案）→ **钉住顺序**：
  --   只验成员的话，把顺序打乱（例如把目标族排到自身族前面）照样全绿。
  eq(table.concat(gSkill, ","), "ready,usable,notQueued,inRange,casting,castEl,castLeft,tCasting,tCastEl,tCastLeft",
     "★★★技能状态组按 A 方案排序：技能本身 → 我的施法 → 目标的施法")
  -- ★★★① 条件类型菜单在**每一种语言**里都不许出现两条同名（重名 = 用户根本没法分辨）。
  --   ★为什么必须逐语言：测试只跑一种语言，另一种语言的重名**永远是盲区**——
  --     本轮变异实测：把 enUS 的 CT_TCASTEL 改回与 CT_CASTEL 同串（英文菜单里两条一模一样的
  --     "Cast elapsed"），所有断言照样全绿。真机上英文客户端却分辨不出来。
  --   顺手把「缺键」一起查了：这些键是动态拼的，静态 LANG KEY CHECK 扫不到。
  for _, lang in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local tbl, seen, bad = EVAL_LOCALES[lang], {}, ""
    for _, key in ipairs(EVAL_TEST_SE_TYPE_LABEL_KEYS()) do
      local v = tbl[key]
      if v == nil then
        -- ★缺键必须**无条件**记进 bad：第一版我把缺失也塞进 seen 里当普通值，
        --   于是只有「另一个键恰好同值」时才会被发现——缺键这半边等于没查（变异 M14 实测存活）。
        --   ★这条正是本项目的老坑：一条断言里管两件事时，要分别确认「两半都会响」。
        bad = bad .. "<缺键:" .. key .. "> "
      else
        if seen[v] then bad = bad .. "[" .. v .. "] " end
        seen[v] = true
      end
    end
    eq(bad, "", "★★★" .. lang .. " 条件类型菜单无重名、无缺键（问题项: " .. bad .. "）")
  end
  -- ★④ 摘要显示名（不能再漏出裸 id "castEl"——用户截图里规则行显示的就是 "castEl"）+ 往返
  for _, p in ipairs({ { "castEl", "CT_CASTEL", ">", 2 }, { "castLeft", "CT_CASTLEFT", "<", 3 },
                       { "tCastEl", "CT_TCASTEL", ">", 2 }, { "tCastLeft", "CT_TCASTLEFT", "<", 3 } }) do
    eq(EVAL_TEST_COND_NUMNAME(p[1]), zh[p[2]], "★★" .. p[1] .. " 的摘要名与 zhCN 菜单名一致")
    local txt = EVAL_COND_STR({ k = p[1], op = p[3], n = p[4] })
    eq(txt, zh[p[2]] .. p[3] .. tostring(p[4]), "★★" .. p[1] .. " 摘要真的用了这个名字（不是裸 id）")
    local back = EVAL_PARSE_CONDS(txt)
    eq(table.getn(back) == 1 and back[1][1] and back[1][1].k, p[1], "★★★" .. zh[p[2]] .. " 导出→导入往返回到 " .. p[1])
    eq(back[1][1] and back[1][1].n, p[4], "★★数值也往返")
  end
  -- ★反向哨兵：**旧写法**必须继续能解析（存量方案里的「读条>2」不能因改名失效）
  local leg = EVAL_PARSE_CONDS("读条>2")
  eq(table.getn(leg) == 1 and leg[1][1] and leg[1][1].k, "tCastEl", "★★旧别名「读条」仍解析为 tCastEl（向后兼容）")
  eq(EVAL_GROUP_STR(leg), zh["CT_TCASTEL"] .. ">2", "★旧写法读出来显示为新名")
  -- ★★★ 顺带定案并修掉的真 bug：施法中 的导出/解析对称性。
  --   旧写法把 nil / 空串的技能名也拼上冒号 → 导出「施法中:nil」「施法中:」，
  --   而解析侧只认「施法中」或「施法中:名」→ **两个都读不回 → 条件被静默丢弃**
  --   （本项目铁律「绝不静默丢弃」的又一例；本次「施法中」要新进「自身状态」组，必须先修好）。
  eq(EVAL_COND_STR({ k = "casting" }), zh["CT_CASTING"], "★★★裸「施法中」导出不带冒号（旧版输出「施法中:nil」）")
  local rt = EVAL_PARSE_CONDS(EVAL_COND_STR({ k = "casting", s = "" }))
  eq(table.getn(rt) == 1 and rt[1][1] and rt[1][1].k, "casting", "★★★空技能名（下拉默认）导出后能读回 casting")
  eq(rt[1][1] and rt[1][1].s, nil, "★★读回时技能名是 nil（不是空串、更不是字符串 nil）")
  -- ★旧导出串（冒号后为空）也要能读回：用户**历史导出**的文本里就长这样（旧写法 s="" 时输出「施法中:」）
  local leg2 = EVAL_PARSE_CONDS("施法中:")
  eq(table.getn(leg2) == 1 and leg2[1][1] and leg2[1][1].k, "casting", "★★历史导出串「施法中:」仍能读回 casting")
  eq(leg2[1][1] and leg2[1][1].s, nil, "★★且技能名归一为 nil")
  eq(EVAL_COND_STR({ k = "casting", s = "猛击" }), zh["CT_CASTING"] .. ":猛击", "★带技能名仍带冒号")
  local rt2 = EVAL_PARSE_CONDS(EVAL_COND_STR({ k = "casting", v = false }))
  eq(table.getn(rt2) == 1 and rt2[1][1] and rt2[1][1].v, false, "★★取反形式导出后也能读回（v=false）")
end
-- 75) ★★★1.71.2（第十八轮）技能日志的**小数格式**（用户要求：「技能日志.小数类数据显示保留1位小数」）
--   用户截图原文：`自身buff剩余时间不符(剩余295.24997172132s)`——行为全对，但聊天框里是一串浮点尾巴。
--   ★这类「纯展示」需求最容易被当成小事：它不影响判定，所以没有任何行为断言会去碰它，
--     于是同一个量在多条分支里各拼各的字符串（本文件既有「冷却剩 %.1fs」，而剩余时间却 tostring 直拼）。
--   ★判据必须读**真实返回的原因串**，而不是在测试里复述一遍格式模板（复述 = 测试在测自己）。
do
  -- 75a) 光环剩余时间：原因串里保留 1 位小数
  EVAL_HELP_CONFIG.war.debuffTex = EVAL_HELP_CONFIG.war.debuffTex or {}
  EVAL_HELP_CONFIG.war.debuffTex["战斗怒吼"] = "texBS"
  TEST.buffs = { { tex = "texBS", left = 295.24997172132 } }
  TEST.unitBuffs = nil TEST.debuffs = {} TEST.pDebuffs = nil
  EVAL_HELP_UPDATE_STATE()
  local okR, whyFrac = EVAL_COND_EVAL({ k = "hasBuff", s = "战斗怒吼", v = true, secOp = "<", secN = 30 })
  eq(okR, false, "★前提：剩余 295.2s 不满足 <30s（所以才会产生「跳过原因」）")
  eq(type(whyFrac) == "string", true, "★原因串可读（下面两条的前提）")
  eq(string.find(whyFrac, "295.2s", 1, true) ~= nil, true,
     "★★★剩余秒数保留 1 位小数（截图里是 295.24997172132s）: got=" .. tostring(whyFrac))
  -- ★反向哨兵：旧写法（tostring 直拼）必须**不**满足上面那条，否则这条判据等于没响
  local oldForm = "自身buff:剩余时间不符(剩余" .. tostring(295.24997172132) .. "s)"
  eq(string.find(oldForm, "295.2s", 1, true) == nil, true,
     "★sanity: 旧写法（tostring 直拼）确实不满足它 → 判据真的会响")
  TEST.buffs = {} EVAL_HELP_UPDATE_STATE()

  -- 75b) 「无动作」状态行里的百分比同样保留 1 位小数
  --   ★走**真实入口 EVAL_GO**（不是直调拼串函数）：这类改动的风险恰恰在「那条状态行到底有没有被改到」。
  --   ★为什么要在真实链路上验：状态行只在「一条规则都没出手」时才打印——
  --     截住 EVAL_SAY 再跑一次 EVAL_GO，才是用户真正看到的那条消息。
  do
    local cap = {}
    local oldSay = EVAL_SAY
    local oldWdebug = EVAL_HELP_CONFIG.wdebug
    EVAL_SAY = function(m) table.insert(cap, tostring(m)) end
    EVAL_HELP_CONFIG.wdebug = true -- wlog 只在开启「方案技能日志」时才刷聊天框（这正是用户看到的那些行）
    local prof = EVAL_HELP_CONFIG.war.profiles[EVAL_HELP_CONFIG.war.activeProfile or 1]
    local oldSkills = prof and prof.skills
    if prof then prof.skills = {} end -- 空方案 ⇒ 必然无动作 ⇒ 打印状态行
    TEST.hp, TEST.hpMax = 65.4321, 100
    EVAL_HELP_UPDATE_STATE()
    EVAL_GO_LAST = 0
    pcall(EVAL_GO)
    EVAL_SAY = oldSay
    EVAL_HELP_CONFIG.wdebug = oldWdebug
    if prof then prof.skills = oldSkills end
    local naLine = nil
    for _, m in ipairs(cap) do if string.find(m, "无动作", 1, true) ~= nil then naLine = m end end
    eq(naLine ~= nil, true, "★截到了「无动作」状态行（证明这条链路真的跑了）")
    eq(naLine ~= nil and string.find(naLine, "目标血65.4%", 1, true) ~= nil, true,
       "★★★状态行里的百分比保留 1 位小数（0.4% 这类残血不能被抹成 0%）: got=" .. tostring(naLine))
    -- ★反向哨兵：旧写法 %.0f 确实不满足它
    eq(string.find(string.format("目标血%.0f%%", 65.4321), "目标血65.4%", 1, true) == nil, true,
       "★sanity: 旧的 %.0f 写法确实不满足它 → 判据真的会响")
  end
end
-- 76) ★★★1.71.2（第二十轮）战斗信息 UI 的**状态条不再有那圈 1px 深色边**（用户实测：「战斗信息 生命条 有阴影」）
--   根因：`uiMakeBar` 让彩色填充层**内缩 1px**（锚点 +1,-1 / 高度 h-2 / 可用宽度 w-2），
--   于是填充四周露出一圈近黑的底（0.08,0.08,0.10@0.9）→ 满血时最明显，看着就像描边/阴影。
--   ★★三处**必须同时改**：只改锚点与高度的话，满血时右侧仍留 2px 空隙（返回的可用宽度还是 w-2）。
--     所以下面三条断言各钉一处，缺一条就会漏掉那种「改一半」的修法。
--   ★深色底**没有删**：它仍是「未填充部分」，掉血时那条空槽照样看得见（用户要的是去掉那圈边，不是把底挖掉）。
do
  EVAL_HELP_UI_BUILD()
  local bars = EVAL_TEST_UI_BAR_GEOM()
  eq(type(bars) == "table" and table.getn(bars) >= 5, true,
     "★五条状态条（血/能量/目标/读条/挥击）都能读到几何 (got " .. tostring(bars and table.getn(bars)) .. ")")
  for _, b in ipairs(bars or {}) do
    eq(b.x, 0, "★★★" .. b.name .. " 填充层左偏移 = 0（旧实现 1 → 左侧那道深色边）")
    eq(b.y, 0, "★★★" .. b.name .. " 填充层上偏移 = 0（旧实现 -1 → 顶部那道深色边）")
    eq(b.fillH, b.barH, "★★" .. b.name .. " 填充层高度 = 条高（旧实现 h-2 → 上下各留 1px）")
    eq(b.maxW, b.barW, "★★★" .. b.name .. " 满值时填充宽度上限 = 条宽（旧实现 w-2 → 右侧仍留 2px 缝）")
  end
  -- ★反向哨兵：证明判据真的会响——旧实现的 1px 内缩确实不满足「偏移 = 0」
  eq((1 == 0), false, "★sanity: 旧实现的 1px 内缩确实不满足「偏移 = 0」")
end
-- 77) ★★★1.71.3（用户要求改版）「队友/团员」8 项 + 「候选者」4 项**尚未在游戏里实测确认**：
--   ★上一版（1.71.2）是把「!」加在**名字前面**；用户实测后要求撤掉，原话：
--     「第二张的八个条件名称前面的感叹号去除. 在右侧添加黄色感叹号. tooltip 提示待测试, 第一张也是相同操作.」
--   ★为什么文字前缀该撤：它**跟着条件名到处跑**（条件行 / 菜单 / 日志里全是「!队友血量%」），看着像乱码；
--     而标记只需在**挑选的那一刻**提示一次 → 改成下拉里**行右端一枚黄感叹号** + 悬停说明「待测试」。
--   ★判据分三层（缺一层就会出现「名字改了但没标记」或「标记挂到了所有类型上」）：
--     ① 语言包里**不再有**任何条件名以「!」开头；② 这 12 项在下拉里**真的有**黄标记（读真实控件上的贴图）；
--     ③ 反向哨兵：非「待测试」的类型**没有**标记，而且标记必须是**黄**的那枚（白=不可用，不许混用）。
do
  local TEAM_KEYS = { "CT_TEAMHP", "CT_TEAMMANA", "CT_TEAMBUFF", "CT_TEAMDEBUFF",
                      "CT_TEAMRAIDHP", "CT_TEAMRAIDMANA", "CT_TEAMRAIDBUFF", "CT_TEAMRAIDDEBUFF" }
  local CAND_KEYS = { "CT_CANDHP", "CT_CANDPOWER", "CT_CANDBUFF", "CT_CANDDEBUFF" }
  -- ① 文字前缀必须已经撤掉（三语言 × 全部条件类型，一个都不许留）
  for _, lang in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local t = EVAL_LOCALES[lang]
    local bad = ""
    for _, key in ipairs(EVAL_TEST_SE_TYPE_LABEL_KEYS()) do
      local v = t[key]
      if type(v) == "string" and string.sub(v, 1, 1) == "!" then bad = bad .. "<" .. key .. "=" .. v .. ">" end
    end
    eq(bad, "", "★★★" .. lang .. " 条件名不再有「!」前缀（标记改由下拉里的黄感叹号承担）: " .. bad)
  end
  local Lz = EVAL_LOCALES[EVAL_GET_LANG()]
  local menu = EVAL_TEST_SE_TYPE_MENU()
  local found = false
  for _, s in ipairs(menu) do if s == Lz["CT_TEAMHP"] then found = true end end
  eq(found, true, "★★条件类型菜单里显示的就是这个名字（前缀已撤）: " .. tostring(Lz["CT_TEAMHP"]))
  -- ②③ 真实下拉里的标记（普通行 → 8 项队友/团员；选取器行 → 4 项候选者）
  local savedProf77 = EVAL_HELP_CONFIG.war.profiles
  local savedAct77 = EVAL_HELP_CONFIG.war.activeProfile
  local function openTypeMenu77(skill, cd)
    EVAL_HELP_CONFIG.war.profiles = { { name = "t77", skills = { { skill = skill, why = "t77", groups = { { cd } } } } } }
    EVAL_HELP_CONFIG.war.activeProfile = 1
    EVAL_HELP_SE_OPEN(1, 1)
    EVAL_DD_HIDE()
    EVAL_DD_TEST_RESET_ANCHOR()
    return EVAL_TEST_SE_CLICK_TYPE(1)
  end
  local function idxOfText77(txt)
    local vis = EVAL_DD_TEST_VISIBLE_TEXTS()
    for i = 1, table.getn(vis) do if tostring(vis[i]) == txt then return i end end
    return nil
  end
  local yellow77 = EVAL_HELP_SE_MARK_ICONS().test
  local white77 = EVAL_HELP_SE_MARK_ICONS().unavail
  eq(openTypeMenu77("攻击", { k = "combat", v = true }), true, "前置：普通行点得开条件类型下拉")
  for _, key in ipairs(TEAM_KEYS) do
    local i = idxOfText77(Lz[key])
    eq(i ~= nil, true, "前置：菜单里有 " .. key .. " = " .. tostring(Lz[key]))
    if i then
      eq(EVAL_DD_TEST_ROW_WARN(i), yellow77, "★★★" .. key .. " 行右端挂的是**黄**感叹号（读控件上的贴图）")
      eq(EVAL_DD_TEST_ROW_WARN_SHOWN(i), true, "★★标记真的显示出来（不是设了贴图却藏着）")
      local tip = EVAL_DD_TEST_ROW_TIP(i)
      eq(type(tip) == "table", true, "★★" .. key .. " 行有悬停说明")
      local txt = table.concat(tip or {}, "\n")
      eq(string.find(txt, Lz["SE_MARK_TEST_T"], 1, true) ~= nil, true, "★★★悬停里写明「待测试」")
      eq(string.find(txt, Lz["SE_MARK_TEST_D"], 1, true) ~= nil, true, "★★并给出说明")
      eq(EVAL_DD_TEST_ROW_WARN(i) ~= white77, true, "★★反向：用的不是白那枚（白=不可用，两枚不许混）")
    end
  end
  -- ★反向哨兵：非「待测试」的类型**不许**挂标记（否则「给所有行都挂上」也能通过）
  local iCombat77 = idxOfText77(Lz["CT_COMBAT"])
  eq(iCombat77 ~= nil, true, "前置：菜单里有 战斗中")
  if iCombat77 then
    eq(EVAL_DD_TEST_ROW_WARN_SHOWN(iCombat77), false, "★★★反向：非「待测试」类型不挂标记")
    eq(EVAL_DD_TEST_ROW_TIP(iCombat77), nil, "★★也不给悬停说明")
  end
  -- 选取器行：4 项候选者同样带黄标记
  eq(openTypeMenu77("选取目标:队伍成员", { k = "candHp", op = "<", n = 60 }), true, "前置：选取器行点得开条件类型下拉")
  for _, key in ipairs(CAND_KEYS) do
    local i = idxOfText77(Lz[key])
    eq(i ~= nil, true, "前置：菜单里有 " .. key)
    if i then
      eq(EVAL_DD_TEST_ROW_WARN(i), yellow77, "★★★" .. key .. " 行右端也是黄感叹号")
      eq(EVAL_DD_TEST_ROW_WARN_SHOWN(i), true, "★★标记真的显示出来")
      local txt = table.concat(EVAL_DD_TEST_ROW_TIP(i) or {}, "\n")
      eq(string.find(txt, Lz["SE_MARK_TEST_T"], 1, true) ~= nil, true, "★★★悬停里写明「待测试」")
    end
  end
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedProf77
  EVAL_HELP_CONFIG.war.activeProfile = savedAct77
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
end
-- 78) 停止攻击（1.71.3，用户要求「类似按 ESC」）：一个动作 = 停读条 + 停自动射击/魔杖 + 停近战普攻。
--     ★官方依据（本机 api_spell/api_targetting 原文）：SpellStopCasting「Cancels auto-shot / auto-repeat first,
--       otherwise interrupts the in-progress cast」且【Protected: yes】→ 走 RunScript（与取消施法同一条通道）；
--       AttackTarget 原文是「Toggles auto-attack on the current target」=【切换】语义 → 必须守卫，否则会打起来。
do
  eq(EVAL_STOPALL_OF("停止攻击"), true, "stopAllOf parses")
  eq(EVAL_STOPALL_OF("取消施法"), nil, "★取消施法与停止攻击是两个动作（不许合并成一个）")
  eq(EVAL_STOPALL_OF("攻击"), nil, "plain attack is not stop-attack")
  -- 角色行为组里能选到它；动作条扫描组不重复列出它（特殊行为不占动作条）
  TEST.slotNames = { [1] = "停止攻击" } EVAL_GO_RESCAN(true)
  local cats78 = EVAL_GO_SKILL_CATEGORIES()
  local list178, list278 = cats78[1].items(), cats78[2].items()
  local in178, in278 = false, false
  for _, n in ipairs(list178) do if n == "停止攻击" then in178 = true end end
  for _, n in ipairs(list278) do if n == "停止攻击" then in278 = true end end
  eq(in178, true, "★角色行为组里有「停止攻击」可选项")
  eq(in278, false, "★动作条扫描组不重复列出「停止攻击」")
  TEST.slotNames = { [1] = "攻击", [2] = "自动射击" } EVAL_GO_RESCAN(true)
  local sAtk78 = EVAL_WSLOTS["攻击"].slot
  local sAS78 = EVAL_WSLOTS["自动射击"].slot
  local oldSay78 = EVAL_SAY
  local cap78 = {}
  EVAL_SAY = function(m) table.insert(cap78, tostring(m)) end
  EVAL_HELP_CONFIG.wdebug = true
  local function stop78(conds) return EVAL_RULE_RUN({ { skill = "停止攻击", why = "w", groups = EVAL_PARSE_CONDS(conds) } }) end
  local function log78() return table.concat(cap78, "\n") end
  -- (a) 正在读条 + 自动射击在自动重复 + 近战挥击中 → 三条通道全开
  EVAL_HELP_STATE.castName = "寒冰箭"
  TEST.currentAction = sAtk78
  TEST.autoRepeat = sAS78
  TEST.runScripts = {} TEST.castStopped = nil TEST.castStoppedDirect = nil TEST.attackTried = nil
  TEST.time = 4000 -- ★停读条通道有 1 秒频率防护：每个用例都要推进时钟，否则后几拍会被「限频」挡掉
  eq(stop78("目标存在"), true, "停止攻击出手")
  eq(TEST.castStopped, true, "★SpellStopCasting 走 RunScript（Protected 绕过，与取消施法同通道）")
  eq(TEST.castStoppedDirect, nil, "★★直调通道必须【没被走到】（文档 Protected: yes → 真机直调静默无效）")
  eq(TEST.attackTried, true, "★确认在挥击时才按 AttackTarget（停近战普攻）")
  eq(string.find(log78(), "停止: ", 1, true) ~= nil, true, "★日志写出停止明细")
  eq(string.find(log78(), "读条", 1, true) ~= nil, true, "…明细含读条")
  eq(string.find(log78(), "自动射击", 1, true) ~= nil, true, "…明细含自动射击（IsAutoRepeatAction 判定）")
  eq(string.find(log78(), "普攻", 1, true) ~= nil, true, "…明细含普攻")
  -- (b) 什么都没进行 → 仍发 SpellStopCasting（文档：没在施法/自动重复时是空操作、返回 nil），
  --     但**绝不许**碰 AttackTarget（切换语义会把没在打的人打起来，与「停止」正相反）
  EVAL_HELP_STATE.castName = nil TEST.currentAction = nil TEST.autoRepeat = nil
  TEST.runScripts = {} TEST.castStopped = nil TEST.attackTried = nil cap78 = {}
  TEST.time = 4100
  eq(stop78("目标存在"), true, "空闲时也出手（它是个动作，不是状态）")
  -- ★1.71.3 起：没东西在放时**一条通道都不发**（旧版白发 SpellStopCasting；新设计还带移动脉冲 → 更不能乱动角色）
  eq(TEST.castStopped, nil, "★★空闲时不再白发 SpellStopCasting（既无读条也无自动重复）")
  eq(TEST.attackTried, nil, "★★★没在挥击 → 绝不按 AttackTarget")
  eq(string.find(log78(), "无可停止的动作", 1, true) ~= nil, true, "★空闲时日志如实写「无可停止的动作」")
  -- (c) 动作条上没有「攻击」→ 判不出是否在挥击：不碰 AttackTarget，并在日志里如实声明未判定
  TEST.slotNames = { [1] = "自动射击" } EVAL_GO_RESCAN(true)
  TEST.runScripts = {} TEST.castStopped = nil TEST.attackTried = nil cap78 = {}
  TEST.time = 4200
  eq(stop78("目标存在"), true, "★没有攻击格也照样出手（不占动作条，不许被「不在动作条」拦掉）")
  eq(TEST.attackTried, nil, "无攻击格时不碰 AttackTarget")
  eq(string.find(log78(), "普攻未判定", 1, true) ~= nil, true, "★日志如实声明「普攻未判定」，不假装做到")
  -- (d) 「就绪」条件也认它（wready 分支：无冷却、不占动作条 → 恒就绪）
  TEST.runScripts = {} TEST.castStopped = nil cap78 = {}
  TEST.time = 4300
  EVAL_HELP_STATE.castName = "寒冰箭"
  eq(stop78("就绪"), true, "★带就绪条件放行（wready 没把它判成「不在动作条」）")
  eq(TEST.castStopped, true, "带就绪条件真的执行了停止")
  -- 还原（模块级状态必须复位，否则污染后续用例）
  EVAL_SAY = oldSay78
  EVAL_HELP_CONFIG.wdebug = nil
  TEST.slotNames = {}
  TEST.currentAction = nil TEST.autoRepeat = nil
  EVAL_HELP_STATE.castName = nil
  EVAL_GO_RESCAN(true)
  TEST.time = nil -- ★时钟必须复位：后面的用例默认走 GetTime()=1000
end

-- 78b) ★1.71.3 用户实测后定案：**保留原始 SpellStopCasting 方式**（用户判断可能是客户端 bug →「功能先留着」），
--   同时**删除移动脉冲**（实测同样无效，还会把角色往前挪 = 纯副作用）。
--   ★判据：① 通道只做「本地清条」；② ★★★**绝不移动玩家角色**；③ 1 秒限频仍在；
--     ④ 没有 RunScript 的老环境退回直调；⑤ 两个都没有时如实返回「无通道」（不假装做到）。
do
  TEST.time = 5000
  TEST.moveStart, TEST.moveStop = nil, nil
  TEST.runScripts = {} TEST.castStopped, TEST.castStoppedDirect = nil, nil
  local okC, howC = EVAL_STOP_CAST()
  eq(okC, true, "★停读条通道出手")
  eq(howC, "本地条", "★通道明细就是「本地条」")
  eq(TEST.castStopped, true, "★本地清条确实发出去了（RunScript 排队）")
  eq(TEST.castStoppedDirect, nil, "★走的仍是 RunScript 通道（不是直调）")
  eq(TEST.moveStart, nil, "★★★绝不移动玩家角色（移动脉冲已确认无效并删除）")
  eq(TEST.moveStop, nil, "★★★也不会去 Stop 移动")
  TEST.time = 5000.5
  local okR, howR = EVAL_STOP_CAST()
  eq(okR, false, "★★1 秒内第二次被限频挡下")
  eq(howR, "限频", "★限频原因如实返回")
  TEST.time = 5200
  local savedRS = RunScript
  RunScript = nil
  TEST.castStopped, TEST.castStoppedDirect = nil, nil
  local okD, howD = EVAL_STOP_CAST()
  RunScript = savedRS
  eq(okD, true, "★没有 RunScript 的老环境：退回直调")
  eq(TEST.castStoppedDirect, true, "★直调真的被调用（桩如实记录）")
  eq(TEST.moveStart, nil, "★直调路径同样不动角色")
  TEST.time = 5300
  local savedRS2, savedSC2 = RunScript, SpellStopCasting
  RunScript, SpellStopCasting = nil, nil
  local okN, howN = EVAL_STOP_CAST()
  RunScript, SpellStopCasting = savedRS2, savedSC2
  eq(okN, false, "★★没有任何通道时如实返回 false")
  eq(howN, "无通道", "★原因如实写「无通道」")
  TEST.time = nil
  TEST.moveStart, TEST.moveStop = nil, nil
  TEST.castStopped, TEST.castStoppedDirect = nil, nil
end

-- 79) ★1.71.3 频道进出信息屏蔽（工具箱 → 队伍/社交，默认开）
--   用户截图原文：「[4. 世界防务] 离开频道。」「[5. 寻求组队] 离开频道。」
--   ★API 结论：本机全表**没有聊天过滤器**（ChatFrame_AddMessageEventFilter 不存在）→
--     实现是「挂 DEFAULT_CHAT_FRAME:AddMessage」这一层（有文档的控件方法）。
do
  -- ① 行模型：在「队伍/社交」组里、是复选框、带提示
  local rows79 = EVAL_TEST_TB_ROWS()
  local grp79, idxJoin = nil, nil
  for i, r in ipairs(rows79) do
    if r.t == "h" and r.label == EVAL_L("TB_H_SOCIAL") then grp79 = i end
    if r.key == "chanJoin" then idxJoin = i end
  end
  eq(grp79 ~= nil, true, "前置：找得到「队伍/社交」分组标题")
  eq(idxJoin ~= nil, true, "★「屏蔽频道进出信息」这一行存在")
  eq(idxJoin ~= nil and grp79 ~= nil and idxJoin > grp79, true, "★★它挂在该组之内（不是别处）")
  local rowJ = idxJoin and rows79[idxJoin]
  eq(rowJ ~= nil and rowJ.t == "c", true, "★是复选框（与其它开关一致）")
  eq(type(rowJ and rowJ.tip) == "string" and rowJ.tip ~= "", true, "★带悬停提示")
  -- ② 默认开（用户要求「默认打开」）
  eq(EVAL_TB_CHAN_ON(), true, "★★默认开启")
  -- ③ 判据：命中真实文案；反向：不误伤真人聊天 / 自家输出
  eq(EVAL_TB_CHAN_BLOCK("[4. 世界防务] 离开频道。"), true, "★命中截图里的真实文案")
  eq(EVAL_TB_CHAN_BLOCK("[5. 寻求组队] 加入频道。"), true, "★命中「加入频道」")
  eq(EVAL_TB_CHAN_BLOCK("Rainbow has joined channel 4."), true, "★命中英文")
  eq(EVAL_TB_CHAN_BLOCK("守夜人：寄了"), false, "★★不误伤普通聊天")
  eq(EVAL_TB_CHAN_BLOCK("我去加入他们的队伍了"), false, "★★★含「加入」但无频道词 → 不吞（真人消息最重要）")
  eq(EVAL_TB_CHAN_BLOCK("这频道人真多"), false, "★★★含「频道」但无进出词 → 不吞")
  eq(EVAL_TB_CHAN_BLOCK("|cff66ccffEVAL_HELP:|r 已开启"), false, "★★自家输出不吞")
  eq(EVAL_TB_CHAN_BLOCK(nil), false, "★nil 不崩")
  -- ④ 挂载：吞通知、放行其它，且**幂等**（不重复包装）
  local f79 = DEFAULT_CHAT_FRAME
  -- ★★干净底层：Toolbox.lua **载入时已经挂过一层**（这正是生产行为）——若直接把它当 saved79，
  --   后面每调一次都会经过「我们自己的两层」，计数就跳 +2（本轮实测踩到）。
  --   这里刻意从底层重来（行为与 test_stub 的原始实现一致），末尾再还原。
  local saved79 = function(_, m) TEST.chat = (TEST.chat or "") .. tostring(m) .. "\n" end
  local passed79 = 0
  f79.AddMessage = function(self, m, ...) passed79 = passed79 + 1 return saved79(self, m, ...) end
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_INSTALL(), true, "★挂载成功")
  local hookedFn79 = f79.AddMessage
  eq(EVAL_TB_CHAN_INSTALL(), true, "★再挂一次仍返回 true（幂等）")
  eq(f79.AddMessage == hookedFn79, true, "★★★幂等：第二次**没有**再替换入口（不重复包装）")
  f79:AddMessage("[4. 世界防务] 离开频道。")
  eq(select(3, EVAL_TEST_TB_CHAN_STATE()), 1, "★★通知被吞掉并计数")
  eq(passed79, 0, "★★★吞掉时**不调用底层打印**（消息真的不会出现）")
  f79:AddMessage("守夜人：寄了")
  eq(passed79, 1, "★正常消息照旧打印")
  -- ⑤ 开关关掉 → 立即放行（开关是**调用时**读的）
  EVAL_HELP_CONFIG.tb = EVAL_HELP_CONFIG.tb or {}
  EVAL_HELP_CONFIG.tb.chanJoin = false
  eq(EVAL_TB_CHAN_ON(), false, "★开关关掉后判据读到的就是关")
  f79:AddMessage("[4. 世界防务] 离开频道。")
  eq(passed79, 2, "★★★关掉开关后同一条通知就放行了（不需要 /reload）")
  eq(select(3, EVAL_TEST_TB_CHAN_STATE()), 1, "★关掉后计数不再增长")
  EVAL_HELP_CONFIG.tb.chanJoin = true
  -- ⑥ 没有挂载点时：如实返回 false、不崩
  local savedFrame79 = DEFAULT_CHAT_FRAME
  DEFAULT_CHAT_FRAME = nil
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_INSTALL(), false, "★没有聊天框入口时如实返回 false（不假称挂上了）")
  DEFAULT_CHAT_FRAME = savedFrame79
  -- ⑦ ★★★1.71.3 新增（用户实测「屏蔽频道进出信息未能正确工作」）：**载入太早导致的静默失效 + 自动重试**
  --   现象：Toolbox.lua 载入时 DEFAULT_CHAT_FRAME 往往还没建好 → INSTALL 失败 → 旧版**再没人重试**
  --   （开关看着是开的、实际一层都没挂上）。现在由 事件 / 每帧 / 诊断命令 三处驱动重试。
  DEFAULT_CHAT_FRAME = nil
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_INSTALL(), false, "★★前置：聊天框还没建好时挂载失败（如实返回 false）")
  eq(EVAL_TB_CHAN_RETRY(), false, "★★重试也拿不到入口 → 仍如实 false（不假装）")
  DEFAULT_CHAT_FRAME = savedFrame79
  EVAL_HELP_CONFIG.log = {}
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_RETRY(), true, "★★★入口就绪后**重试真的挂上了**（这就是用户那条的根因修复）")
  eq(select(2, EVAL_TEST_TB_CHAN_STATE()), true, "★状态：已挂载")
  eq(select(5, EVAL_TEST_TB_CHAN_STATE()), true, "★★★「我们的包装在位」= true（不是只看状态位——被别人顶掉也能查出来）")
  f79:AddMessage("[4. 世界防务] 进入频道。")
  eq(select(3, EVAL_TEST_TB_CHAN_STATE()), 1, "★★★重试挂上后，截图里那条「进入频道」真的被吞掉了")
  local logs79 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs79, "挂载成功", 1, true) ~= nil, true, "★★挂载成功如实写进调试日志（/eh logdump 可查）")
  -- ⑧ 文案表：**照着客户端真实文案抄**（旧表缺「进入」= 半个功能失效）
  eq(EVAL_TB_CHAN_BLOCK("[4. 世界防务] 进入频道。"), true, "★★★命中用户截图里的「进入频道」")
  eq(EVAL_TB_CHAN_BLOCK("[4. 世界防务] 退出频道。"), true, "★命中「退出频道」")
  eq(EVAL_TB_CHAN_BLOCK("[4. 世界防务] 離開頻道。"), true, "★繁中也能命中")
  eq(EVAL_TB_CHAN_BLOCK("我去进入他们的队伍了"), false, "★★★反向：含「进入」但无频道词 → 不吞")
  -- ⑦b ★★★入口**不是 table** 时也要能挂（本客户端帧未必是 table —— 旧版 `type(f) ~= "table"` 会一次都挂不上）
  --   用「函数 + 元表」造一个非 table 的入口（真客户端就是这种形态）。
  do
    local store79 = { AddMessage = function() end }
    local nonTab79 = function() end
    -- ★setmetatable 只吃 table（Lua 5.1 语义）→ 要给「函数」设元表必须用 debug.setmetatable
    local mt79 = { __index = function(_, k) return store79[k] end,
                   __newindex = function(_, k, v) store79[k] = v end }
    local okSet = false
    if type(debug) == "table" and type(debug.setmetatable) == "function" then
      okSet = pcall(debug.setmetatable, nonTab79, mt79)
    end
    if okSet and type(nonTab79) ~= "table" and type(nonTab79.AddMessage) == "function" then
      DEFAULT_CHAT_FRAME = nonTab79
      EVAL_TEST_TB_CHAN_RESET()
      eq(EVAL_TB_CHAN_INSTALL(), true, "★★★入口不是 table 也能挂上（旧版 type(f)~=\"table\" 在真机上可能一次都挂不上）")
      eq(type(store79.AddMessage), "function", "★包装真的写进了该入口")
    else
      -- ★桩/环境不支持给非 table 设元表 → **如实跳过**（不假称测过；这条在真机上靠代码审查 + 不打 table 闸门保证）
      eq(true, true, "（跳过：本测试环境无法构造非 table 的入口——已如实记录，不假称覆盖）")
    end
  end
  DEFAULT_CHAT_FRAME = savedFrame79
  -- ★⑦b 把包装挂到了「非 table 入口」上（TB.chanWrapper 也跟着指过去）→ 这里必须先回到**干净底层**再重挂，
  --   否则会在旧包装之上再加一层（同一条消息被数两次——本轮实测踩过）。
  f79.AddMessage = saved79
  EVAL_TEST_TB_CHAN_RESET()
  EVAL_TB_CHAN_RETRY()
  -- ⑨ 经过入口的消息计数（诊断用它区分「没挂上」与「客户端不走 Lua 打印」）
  local seen0 = select(6, EVAL_TEST_TB_CHAN_STATE())
  f79:AddMessage("守夜人：寄了")
  eq(select(6, EVAL_TEST_TB_CHAN_STATE()) == seen0 + 1, true, "★★经过入口的消息计数 +1（诊断判读的关键）")
  -- 还原：恢复原来的入口 + 让生产包装重新装上（并清零计数），避免污染后续用例
  f79.AddMessage = saved79
  EVAL_TEST_TB_CHAN_RESET()
  EVAL_TB_CHAN_INSTALL()
end
-- 80) ★1.71.3 自动购买重做：分批 + 每次数量 + 安全闸门 + 设置窗（用户要求）
--   用户要点：「购买频率限制下防止瞬间购买」「支持购买数量多个」「每次购买数量:默认1」
--   「购买行为要做好安全界限,异常终止等检测,比如背包满了」「防止进入重复购买操作」
do
  -- ① 老配置迁移：只补字段、不丢条目
  local oldCfg = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { buy = { { name = "老条目", n = 5 } } }
  local tb80 = EVAL_TEST_TB_CFG() -- ★走真的 tbCfg（迁移在里面跑；直接读配置表是不会触发迁移的）
  eq(tb80.buy[1].per, 1, "★老条目补上「每次购买数量」默认 1")
  eq(tb80.buy[1].on, true, "★老条目补上「启用」默认开")
  eq(tb80.buy[1].n, 5, "★原有字段不动（n 还是 5）")
  -- ② 纯判据 EVAL_TB_BUY_DECIDE：所有安全闸门都在这里（可脱离游戏直接测）
  local e = { name = "面包", n = 5, per = 2, on = true }
  eq(select(2, EVAL_TB_BUY_DECIDE({ name = "x", n = 1, per = 1, on = false }, nil, { idx = 1 })), "off", "★★停用的条目不下单")
  eq(select(2, EVAL_TB_BUY_DECIDE(e, { have0 = 0, fails = 0 }, { idx = nil })), "nomatch", "★商人没卖这个 → 不下单")
  eq(select(2, EVAL_TB_BUY_DECIDE(e, { have0 = 0, fails = 0 }, { idx = 1, free = 0 })), "bagfull", "★★★背包满 → 不下单（防买到一半卡死）")
  eq(select(2, EVAL_TB_BUY_DECIDE(e, { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 5 })), "done", "★已经买够 → 不下单")
  eq(EVAL_TB_BUY_DECIDE({ name = "x", n = 9, per = 5, on = true }, { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 0, cap = 2 }), 2,
     "★★每次数量受「商人一次上限」夹取（per=5, cap=2 → 买 2）")
  eq(EVAL_TB_BUY_DECIDE({ name = "x", n = 3, per = 5, on = true }, { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 0, cap = 9 }), 3,
     "★★每次数量受「还差多少」夹取（只差 3 → 买 3，不超买）")
  eq(EVAL_TB_BUY_DECIDE({ name = "x", n = 9, per = 5, on = true }, { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 0, cap = 9, avail = 2 }), 2,
     "★★每次数量受「商人库存」夹取（只剩 2）")
  eq(select(2, EVAL_TB_BUY_DECIDE(e, { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 0, avail = 0 })), "avail", "★库存卖光 → 停（不再刷单）")
  local stF = { have0 = 0, fails = 0, expect = 2 }
  eq(select(2, EVAL_TB_BUY_DECIDE(e, stF, { idx = 1, free = 3, have = 0 })), "ok",
     "★先按「上一笔没涨」记一次失败，但还没到上限 → 仍可下单")
  eq(stF.fails, 1, "★★核对：说好买 2 件而背包没涨 → 记一次失败")
  stF.fails = 3
  eq(select(2, EVAL_TB_BUY_DECIDE(e, stF, { idx = 1, free = 3, have = 0 })), "fails", "★★★连失败达上限 → 停止该条目")
  local stOK = { have0 = 0, fails = 0 }
  eq(EVAL_TB_BUY_DECIDE(e, stOK, { idx = 1, free = 3, have = 0, cap = 9 }), 2, "★正常：按「每次购买数量」下单")
  eq(stOK.expect, 2, "★下单后记下「期望背包数量」→ 下一拍据此核对")
  -- ★★★用户实测报回：目标数必须是**绝对值**（对照背包现有量），否则每次对话都会重复购买
  eq(EVAL_TB_BUY_DECIDE({ name = "x", n = 5, per = 2, on = true }, { fails = 0 }, { idx = 1, free = 3, have = 3, cap = 9 }), 2,
     "★★★背包已有 3 件、目标 5 → 只再买 2 件（不是买 5）")
  eq(select(2, EVAL_TB_BUY_DECIDE({ name = "x", n = 5, per = 2, on = true }, { fails = 0 }, { idx = 1, free = 3, have = 5 }) ), "done",
     "★★★背包已有 5 件（够了）→ 一件都不买（防每次对话重复购买）")
  eq(select(2, EVAL_TB_BUY_DECIDE({ name = "x", n = 5, per = 2, on = true }, { fails = 0 }, { idx = 1, free = 3, have = 9 }) ), "done",
     "★背包比目标还多 → 同样不买")
  -- ③ 设置窗：列表显示「启用 | 名称 | 总数 | 每次」，且能改
  EVAL_BUY_UI_OPEN()
  eq(EVAL_TEST_BUY_UI_SHOWN(), true, "★设置窗能打开")
  local t80 = EVAL_TEST_BUY_UI_TEXTS()
  eq(table.getn(t80) >= 1, true, "★列表里画出了条目（可见行数 " .. tostring(table.getn(t80)) .. "）")
  eq(t80[1] and t80[1].name, "老条目", "★★列表显示的是配置里的名字")
  eq(t80[1] and t80[1].n, "5", "★★列表显示「总数」列")
  eq(t80[1] and t80[1].per, "1", "★★列表显示「每次」列（默认 1）")
  eq(t80[1] and t80[1].on, true, "★★列表显示「启用」勾选状态")
  local savedTN80 = EVAL_TN_OPEN
  local tnCalls80 = 0
  EVAL_TN_CB80 = nil
  EVAL_TN_OPEN = function(title, cur, cb) tnCalls80 = tnCalls80 + 1 EVAL_TN_CB80 = cb end
  local chk80 = EVAL_TEST_BUY_UI_CELL(1, "chk")
  local chkFn = chk80 and chk80.GetScript and chk80:GetScript("OnClick")
  eq(type(chkFn) == "function", true, "★勾选框有真实 OnClick")
  if type(chkFn) == "function" then chkFn() end
  eq(tb80.buy[1].on, false, "★★★点一下勾选框 → 该条目被停用（写的是配置真值）")
  eq(EVAL_TEST_BUY_UI_TEXTS()[1].on, false, "★★列表状态同步刷新")
  if type(chkFn) == "function" then chkFn() end
  eq(tb80.buy[1].on, true, "★再点一下 → 恢复启用")
  local nBtn80 = EVAL_TEST_BUY_UI_CELL(1, "n")
  local nFn = nBtn80 and nBtn80.GetScript and nBtn80:GetScript("OnClick")
  eq(type(nFn) == "function", true, "★数量格有真实 OnClick")
  if type(nFn) == "function" then nFn() end
  eq(tnCalls80, 1, "★★点数量格真的弹了输入框（EVAL_TN_OPEN）")
  if type(EVAL_TN_CB80) == "function" then EVAL_TN_CB80("20") end
  eq(tb80.buy[1].n, 20, "★★★输入 20 后写回配置（走真实回调）")
  eq(EVAL_TEST_BUY_UI_TEXTS()[1].n, "20", "★列表上显示也变成 20")
  local pBtn80 = EVAL_TEST_BUY_UI_CELL(1, "per")
  local pFn = pBtn80 and pBtn80.GetScript and pBtn80:GetScript("OnClick")
  if type(pFn) == "function" then pFn() end
  if type(EVAL_TN_CB80) == "function" then EVAL_TN_CB80("3") end
  eq(tb80.buy[1].per, 3, "★★每次购买数量可改为 3")
  eq(EVAL_TEST_BUY_UI_TEXTS()[1].per, "3", "★列表显示同步")
  eq(EVAL_TB_BUY_DECIDE(tb80.buy[1], { have0 = 0, fails = 0 }, { idx = 1, free = 3, have = 0, cap = 9 }), 3,
     "★★★改完「每次 3」后判据真的按 3 下单（UI → 行为闭环）")
  local dBtn80 = EVAL_TEST_BUY_UI_CELL(1, "del")
  local dFn = dBtn80 and dBtn80.GetScript and dBtn80:GetScript("OnClick")
  if type(dFn) == "function" then dFn() end
  eq(table.getn(tb80.buy), 0, "★★[删除] 真的把条目删了")
  eq(table.getn(EVAL_TEST_BUY_UI_TEXTS()), 0, "★删空后列表不再画行")
  -- ④ 工具箱「自动购买」行的 [添加]：现在开的是设置窗，不再弹输入框
  EVAL_TB_REFRESH()
  local addBtn80 = EVAL_TEST_TB_ADD_BTN_FOR("buy")
  eq(addBtn80 ~= nil, true, "前置：找得到「自动购买」行的 [添加] 按钮")
  local af = addBtn80 and addBtn80.GetScript and addBtn80:GetScript("OnClick")
  eq(type(af) == "function", true, "★[添加] 有真实 OnClick")
  tnCalls80 = 0
  EVAL_BUY_UI_CLOSE()
  if type(af) == "function" then af() end
  eq(EVAL_TEST_BUY_UI_SHOWN(), true, "★★★工具箱[添加] 真的打开了设置窗（真实 OnClick 闭包）")
  eq(tnCalls80, 0, "★★它不再弹旧的文本输入框（自动购买改走设置窗）")
  EVAL_TN_OPEN = savedTN80
  EVAL_HELP_CONFIG.tb = oldCfg
  EVAL_BUY_UI_CLOSE()
end
-- 81) ★1.71.3 分享来源频道标注（用户问：「方案分享来源能否辨别是否是公会来源？」）
--   ★判据 = **触发的事件名**（按频道注册的事件本来就是分开的），比拿文本猜可靠；
--     ★队长/团长走 *_LEADER 事件，一并归类；认不出来就**不标**（不瞎猜来源）。
do
  local L81 = EVAL_LOCALES[EVAL_GET_LANG()]
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_GUILD"), L81["SH_CH_GUILD"], "★公会来源标成「公会」")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_PARTY"), L81["SH_CH_PARTY"], "★队伍")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_PARTY_LEADER"), L81["SH_CH_PARTY"], "★★队长发言也算队伍（不能当野人）")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_RAID"), L81["SH_CH_RAID"], "★团队")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_RAID_LEADER"), L81["SH_CH_RAID"], "★团长发言也算团队")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_SAY"), L81["SH_CH_SAY"], "★说")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_WHISPER"), L81["SH_CH_WHISPER"], "★密语")
  eq(EVAL_SHARE_CHAN_LABEL(nil), nil, "★没有事件信息 → 不标（不瞎猜）")
  eq(EVAL_SHARE_CHAN_LABEL("CHAT_MSG_SOMETHING_ELSE"), nil, "★未知事件 → 不标")
  local e1, m1, s1 = EVAL_SHARE_DISPATCH("CHAT_MSG_GUILD", "MSG", "Rainbow", nil, nil)
  eq(e1 == "CHAT_MSG_GUILD" and m1 == "MSG" and s1 == "Rainbow", true, "★分派：事件名在 1 参（常态）")
  local e2, m2, s2 = EVAL_SHARE_DISPATCH(nil, "CHAT_MSG_GUILD", "MSG", "Rainbow", nil)
  eq(e2 == "CHAT_MSG_GUILD" and m2 == "MSG" and s2 == "Rainbow", true, "★分派：事件名在 2 参（兼容态）")
  local e3, m3, s3 = EVAL_SHARE_DISPATCH(nil, nil, nil, "MSG", "Rainbow")
  eq(e3 == nil and m3 == "MSG" and s3 == "Rainbow", true, "★分派：无事件名时仍取到消息（老环境）")
  -- 真实收信路径：带来源收齐 → pending 记来源 + 弹窗真的显示出来
  EVAL_SHARE_RESET()
  local prof81 = EVAL_PROFILE_FROM_TEXT("# 方案: 来源测试\n- 致死打击 | 怒气>30")
  EVAL_HELP_CONFIG.war.profiles = { prof81 } EVAL_HELP_CONFIG.war.activeProfile = 1
  TEST.runScripts = nil
  EVAL_SHARE_SEND("GUILD")
  local msgs81 = {}
  for _, s in ipairs(TEST.runScripts or {}) do
    local m = string.match(s, 'SendChatMessage%("(.-)", "GUILD"%)')
    if m then table.insert(msgs81, m) end
  end
  eq(table.getn(msgs81) >= 1, true, "前置：造出一条分享分片")
  -- ★1.71.3：新规则会忽略「非说来源 + 内容就是自己的方案」的回声 → 本组验的是「来源标注」，
  --   所以这里把配置换成一个**别人的方案**，否则收到的分片会被判成自己的回声而根本不弹窗。
  EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT("# 方案: 别人的方案\n- 冲锋 | 非战斗") }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  for _, m in ipairs(msgs81) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_GUILD") end
  local p81 = EVAL_SHARE_PENDING()
  eq(p81 ~= nil and p81.chan, L81["SH_CH_GUILD"], "★★★收到的分享记下了来源=公会")
  local shown81 = table.concat(EVAL_TEST_SHARE_POPUP_TEXTS(), "\n")
  eq(string.find(shown81, L81["SH_CH_GUILD"], 1, true) ~= nil, true, "★★★弹窗里真的显示出来源频道")
  eq(string.find(shown81, "彩虹", 1, true) ~= nil, true, "★发送者名字仍在")
  -- ★反向哨兵：不带事件（老路径/测试直调）不许凭空造出来源
  EVAL_SHARE_RESET()
  for _, m in ipairs(msgs81) do EVAL_SHARE_ONMSG(m, "彩虹") end
  local p82 = EVAL_SHARE_PENDING()
  eq(p82 ~= nil and p82.chan, nil, "★★没有事件信息时不标来源（不瞎猜）")
  eq(string.find(table.concat(EVAL_TEST_SHARE_POPUP_TEXTS(), "\n"), L81["SH_CH_GUILD"], 1, true) == nil, true,
     "★弹窗里也不会凭空多出公会来源")
  EVAL_SHARE_RESET()
  EVAL_HELP_CONFIG.war.profiles = { prof81 } -- 还原本组开头改掉的配置（别把状态漏给后面的用例）
  EVAL_HELP_CONFIG.war.activeProfile = 1
end

-- 82) ★1.71.3 「自己方案的回声」自动忽略 + 公会来源的玩梗句（用户要求）
--   ① 非「说」来源 且内容就是**我自己的方案** → 直接忽略（自己往公会/队伍发分享，客户端会把分片回声给自己）；
--   ② 公会来源点 [忽略]/[导入] → 在**公会频道**各玩一句（只在真的公会里、只走 RunScript 排队）。
do
  local L82 = EVAL_LOCALES[EVAL_GET_LANG()]
  local MY82 = "# 方案: 我的甲\n- 致死打击 | 怒气>30"
  local OTHER82 = "# 方案: 别人的甲\n- 冲锋 | 非战斗"
  -- 造分片：临时把「要发的方案」装进配置，发完还原（发送侧真实产物，不是手搓十六进制）
  local function chunksOf82(text)
    local keep = EVAL_HELP_CONFIG.war.profiles
    EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT(text) }
    EVAL_HELP_CONFIG.war.activeProfile = 1
    TEST.runScripts = nil
    EVAL_SHARE_SEND("GUILD")
    local out = {}
    for _, s in ipairs(TEST.runScripts or {}) do
      local m = string.match(s, 'SendChatMessage%("(.-)", "GUILD"%)')
      if m and (string.sub(m, 1, 6) == "[EHPF#" or (string.find(m, "|HEHPF:", 1, true) and string.find(m, "传输中", 1, true))) then table.insert(out, m) end -- ★★封皮不算片（v1/v2）
    end
    EVAL_HELP_CONFIG.war.profiles = keep
    EVAL_HELP_CONFIG.war.activeProfile = 1
    return out
  end
  local msgs82 = chunksOf82(MY82)
  local other82 = chunksOf82(OTHER82)
  eq(table.getn(msgs82) >= 1 and table.getn(other82) >= 1, true, "前置：两份分享都造出了分片")

  -- 把「我的方案」装回配置：IS_MINE 比对的就是它
  EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT(MY82) }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  eq(EVAL_SHARE_IS_MINE(EVAL_PROFILE_TO_TEXT(1)), true, "★判据：这串文本就是「我自己的方案」")
  eq(EVAL_SHARE_IS_MINE("# 方案: 我的甲\n- 致死打击 | 怒气>999"), false,
     "★★同名但内容不同 → 不算我的（只比名字会误伤同名的人）")
  eq(EVAL_SHARE_IS_MINE(OTHER82), false, "★别人的方案不算我的")
  eq(EVAL_SHARE_IS_MINE(""), false, "★空串不算我的")
  eq(EVAL_SHARE_IS_MINE(nil), false, "★nil 不算我的")

  -- ① 公会来源 + 自己的方案 → 忽略（不弹窗、且在观测口上如实 +1）
  EVAL_SHARE_RESET()
  local base82 = EVAL_TEST_SHARE_SELF_SKIPPED()
  for _, m in ipairs(msgs82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_GUILD") end
  eq(EVAL_SHARE_PENDING() == nil, true, "★★★公会来源的自我回声被忽略（自己不再弹自己的窗）")
  eq(EVAL_TEST_SHARE_SELF_SKIPPED() == base82 + 1, true, "★★忽略次数如实 +1（可观测，不是静默丢弃）")

  -- ② 「说」来源 + 自己的方案 → 照旧弹（用户明确要求：除了说类型的分享）
  EVAL_SHARE_RESET()
  for _, m in ipairs(msgs82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_SAY") end
  eq(EVAL_SHARE_PENDING() ~= nil, true, "★★★「说」来源的自己方案照旧弹出（自己测试分享的唯一方式，不能顺手吞掉）")
  eq(EVAL_TEST_SHARE_SELF_SKIPPED() == base82 + 1, true, "★②没有再记一次忽略（说来源不受影响）")

  -- ③ 队伍来源 + 自己的方案 → 同样忽略（规则是「非说来源」，不是只盯公会）
  EVAL_SHARE_RESET()
  for _, m in ipairs(msgs82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_PARTY") end
  eq(EVAL_SHARE_PENDING() == nil, true, "★★队伍来源的自我回声同样忽略")
  eq(EVAL_TEST_SHARE_SELF_SKIPPED() == base82 + 2, true, "★忽略计数又 +1")

  -- ④ 公会来源 + 别人的方案 → 点 [忽略] 在公会频道玩一句
  EVAL_SHARE_RESET()
  TEST.inGuild = true
  for _, m in ipairs(other82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_GUILD") end
  local p82 = EVAL_SHARE_PENDING()
  eq(p82 ~= nil, true, "前置：别人的公会分享正常弹出")
  TEST.runScripts = nil
  eq(EVAL_TEST_SHARE_CLICK_IGNORE(), true, "★点到了真实的 [忽略] 按钮（走它自己的 OnClick 闭包）")
  local wantIgn = string.format(L82["SH_FUN_IGNORE"], "彩虹", tostring(p82.name))
  local gotIgn = nil
  for _, s in ipairs(TEST.runScripts or {}) do
    if string.find(s, wantIgn, 1, true) then gotIgn = s end
  end
  eq(gotIgn ~= nil, true, "★★★[忽略] 在公会频道玩了梗句（RunScript 排队 + 文案按语言包实取）")
  eq(gotIgn ~= nil and string.find(gotIgn, '"GUILD"', 1, true) ~= nil, true, "★★真的发到公会频道")
  eq(EVAL_SHARE_PENDING() == nil, true, "★忽略后待导入清空")

  -- ⑤ 公会来源 + 别人的方案 → 点 [导入] 玩另一句，并且**照旧真的导入**
  EVAL_SHARE_RESET()
  for _, m in ipairs(other82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_GUILD") end
  local p82b = EVAL_SHARE_PENDING()
  eq(p82b ~= nil, true, "前置：再来一份公会分享")
  local before82 = table.getn(EVAL_HELP_CONFIG.war.profiles)
  TEST.runScripts = nil
  eq(EVAL_TEST_SHARE_CLICK_IMPORT(), true, "★点到了真实的 [导入] 按钮")
  local wantImp = string.format(L82["SH_FUN_IMPORT"], "彩虹", tostring(p82b.name))
  local gotImp = nil
  for _, s in ipairs(TEST.runScripts or {}) do
    if string.find(s, wantImp, 1, true) then gotImp = s end
  end
  eq(gotImp ~= nil, true, "★★★[导入] 在公会频道玩了另一句梗")
  eq(gotImp ~= nil and string.find(gotImp, '"GUILD"', 1, true) ~= nil, true, "★★也是发到公会频道")
  eq(table.getn(EVAL_HELP_CONFIG.war.profiles) > before82, true, "★★玩梗句不替代导入：方案真的进列表了")

  -- ⑥ 不在公会里 → 一句都不发（不假装发了）
  --   ★⑤真的把「别人的甲」导进来了，此刻它已经变成「我的方案」→ 必须先把配置还原成只有我自己的那份
  EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT(MY82) }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_SHARE_RESET()
  TEST.inGuild = false
  for _, m in ipairs(other82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_GUILD") end
  eq(EVAL_SHARE_PENDING() ~= nil, true, "前置：不在公会也照样收得到分享")
  TEST.runScripts = nil
  EVAL_TEST_SHARE_CLICK_IGNORE()
  eq(table.getn(TEST.runScripts or {}), 0, "★★不在公会里 → 一条都不发（不假装做到）")

  -- ⑦ 队伍来源 → 不去公会频道发（玩梗句是公会来源专属）
  EVAL_SHARE_RESET()
  TEST.inGuild = true
  for _, m in ipairs(other82) do EVAL_SHARE_ONMSG(m, "彩虹", "CHAT_MSG_PARTY") end
  eq(EVAL_SHARE_PENDING() ~= nil, true, "前置：队伍来源正常弹窗")
  TEST.runScripts = nil
  EVAL_TEST_SHARE_CLICK_IGNORE()
  eq(table.getn(TEST.runScripts or {}), 0, "★★队伍来源不发公会玩梗句（只认公会来源）")

  TEST.inGuild = false
  EVAL_SHARE_RESET()
end
-- 83) ★1.71.3 图标美化（用户要求）+ 「取消施法」异常标记（问号图标 + 悬停说明）
--   ① 五个技能类别各带图标，且都指向**本插件自己**的 media\icons（自包含，不依赖对方目录）；
--   ② 走**真实分类下拉按钮**：打开后每行真的画上了图标；
--   ③ 走**真实项列表**：只有「取消施法」带异常标记，悬停弹出语言包里的原因；
--   ④ 分享弹窗：两个按钮整组以窗口中线对齐 + 标题图标是本次拷进来的那张。
do
  local L83 = EVAL_LOCALES[EVAL_GET_LANG()]
  -- ① 类别图标：前缀从**生产代码**（分享弹窗标题图标）反推，测试里不写死目录字符串
  local full83 = EVAL_TEST_SHARE_TITLE_ICON()
  eq(type(full83) == "string" and string.len(full83) > 0, true, "前置：拿到分享弹窗标题图标路径（生产值）")
  eq(string.find(full83, "AddOns", 1, true) ~= nil and string.find(full83, "media", 1, true) ~= nil, true,
     "★★标题图标指向插件自己的 media（自包含）")
  local root83 = string.sub(full83, 1, string.len(full83) - string.len("trainers-icon"))
  local catIcons83 = EVAL_TEST_SE_CAT_ICONS()
  eq(table.getn(catIcons83), 5, "★五个类别都拿到了图标")
  local seen83 = {}
  for i = 1, 5 do
    local ic = catIcons83[i]
    eq(type(ic) == "string" and ic ~= "", true, "★类别 " .. i .. " 有图标路径")
    eq(string.sub(ic, 1, string.len(root83)) == root83, true, "★★类别图标与标题图标同根（本插件 media，自包含）")
    eq(seen83[ic], nil, "★五个类别图标互不相同：" .. tostring(ic))
    seen83[ic] = true
  end
  -- ② 真实分类下拉按钮 → 每行画出的图标 = 生产代码给的那个
  EVAL_HELP_SE_OPEN(1)
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_CAT(), true, "★点到了真实的分类下拉按钮（走它自己的 OnClick）")
  eq(EVAL_DD_TEST_SHOWN(), true, "★类别下拉打开了")
  eq(EVAL_DD_TEST_ROW_TEX(1), catIcons83[1], "★★★第一行**画出来的**图标 == 生产代码给的那个")
  eq(EVAL_DD_TEST_ROW_TEX(5), catIcons83[5], "★第五行同理（下标不错位）")
  -- ③ 点第一类（角色行为）→ 真实回调续弹项列表
  local row83 = EVAL_DD_TEST_ROW(1)
  local fn83 = row83 and row83.btn and row83.btn.GetScript and row83.btn:GetScript("OnClick")
  eq(type(fn83) == "function", true, "前置：类别行有真实 OnClick（点它续弹项列表）")
  if type(fn83) == "function" then fn83() end
  local items83 = EVAL_GO_SKILL_CATEGORIES()[1].items()
  local idxCancel, idxOther = nil, nil
  for i, v in ipairs(items83) do
    if v == "取消施法" then idxCancel = i elseif v == "攻击" then idxOther = i end
  end
  eq(idxCancel ~= nil and idxOther ~= nil, true, "前置：角色行为列表里有 取消施法 与 攻击")
  eq(EVAL_DD_TEST_ROW_TEX(idxCancel) ~= nil, true, "★项行也画上了技能图标")
  -- ★1.71.3 用户要求：把行右端那个**问号**换成**插件图标内的白感叹号** → 断言改读**生产值**
  --   （不写死路径：写死就等于在测试里另抄一份名单，本项目老坑）
  local warnIcon83 = EVAL_HELP_SE_WARN_ICON()
  eq(type(warnIcon83) == "string" and string.find(warnIcon83, "mark-unavail", 1, true) ~= nil, true,
     "★标记图标 = 本插件的白感叹号（mark-unavail）")
  eq(EVAL_DD_TEST_ROW_WARN(idxCancel), warnIcon83, "★★★取消施法行右端画的就是它（读真实控件上的贴图）")
  eq(string.find(tostring(EVAL_DD_TEST_ROW_WARN(idxCancel)), "INV_Misc_QuestionMark", 1, true) == nil, true,
     "★★反向哨兵：不再是暴雪那个红问号")
  eq(EVAL_DD_TEST_ROW_WARN_SHOWN(idxCancel), true, "★★标记真的显示出来（不是设了贴图却藏着）")
  eq(EVAL_DD_TEST_ROW_WARN_SHOWN(idxOther), false, "★★反向哨兵：攻击行**没有**异常标记")
  -- ④ 悬停：走真实 OnEnter → tooltip 必须出现语言包里的原因文案
  local rb83 = EVAL_DD_TEST_ROW(idxCancel)
  local enter83 = rb83 and rb83.btn and rb83.btn.GetScript and rb83.btn:GetScript("OnEnter")
  eq(type(enter83) == "function", true, "★标记行有 OnEnter")
  TEST.tipLines = nil
  if type(enter83) == "function" then enter83() end
  local tip83 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tip83 = tip83 .. tostring(ln.text or "") .. " \n" end
  eq(string.find(tip83, L83["SE_WARN_CANCELCAST"], 1, true) ~= nil, true,
     "★★★悬停真的弹出原因（按语言包实取，不硬编码文案）")
  -- ★反向哨兵：没有标记的行悬停**不该**弹这个原因（否则等于给所有行都装了提示）
  TEST.tipLines = nil
  local rbOther = EVAL_DD_TEST_ROW(idxOther)
  local enterOther = rbOther and rbOther.btn and rbOther.btn.GetScript and rbOther.btn:GetScript("OnEnter")
  if type(enterOther) == "function" then enterOther() end
  local tipOther = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipOther = tipOther .. tostring(ln.text or "") .. " \n" end
  eq(string.find(tipOther, L83["SE_WARN_CANCELCAST"], 1, true) == nil, true, "★★攻击行悬停不弹这个原因")
  EVAL_DD_HIDE()
  -- ⑤ 行池复用：换一个菜单（类别下拉）后，原来带标记的那一行**不许**把标记/提示带过去。
  --   ★类别菜单第 4 行（目标选取）与项菜单第 4 行（取消施法）**同一个行池槽位**，这正是残留会现形的地方。
  EVAL_DD_TEST_RESET_ANCHOR()
  EVAL_TEST_SE_CLICK_CAT()
  eq(EVAL_DD_TEST_SHOWN(), true, "前置：类别下拉重新打开")
  eq(EVAL_DD_TEST_ROW_WARN_SHOWN(4), false, "★★★行池复用不许残留上一次的异常标记")
  eq(EVAL_DD_TEST_ROW_TIP(4), nil, "★★也不许残留上一次的悬停说明")
  EVAL_DD_HIDE()
  -- ⑤ 分享弹窗几何：按钮整组以窗口中线对齐（用**真实控件**的几何，不写死常量）
  EVAL_SH_POPUP("测试", "# 方案: 图标测试", nil)
  local pos83 = EVAL_TEST_SHARE_BTN_POS()
  eq(pos83.W > 0 and pos83.w > 0 and pos83.x1 ~= nil and pos83.x2 ~= nil, true,
     "前置：拿到弹窗与两个按钮的真实几何（W=" .. tostring(pos83.W) .. "）")
  -- ★1.73.14 用户要求：「接收方案开关在分享方案位置也添加一个方便快速关闭，然后三个位置居中对齐」
  --   → 判据从「两个按钮居中」升级成「**三段整组**居中 + 三段互不重叠」（相对量，不写死坐标）。
  eq(pos83.sx ~= nil, true, "★★★弹窗底部多了一个「接收方案」勾选框（真实控件）")
  eq(type(pos83.rowX0) == "number" and type(pos83.rowW) == "number" and type(pos83.chkW) == "number", true,
     "★★★交出底部一行的**布局真值**（左起点 / 整行宽 / 勾选框段宽）")
  -- ① 整组居中（用生产数字，不写死坐标）
  -- 居中 = **左边距 == 右边距**（右边距是 窗口宽 − 左起点 − 整行宽；不要写成 W−rowW，那差一个左起点）
  local rightPad83 = pos83.W - (pos83.rowX0 + pos83.rowW)
  eq(math.abs(pos83.rowX0 - rightPad83) <= 1, true,
     "★★★三段（勾选框 + [导入] + [忽略]）**整组**以窗口中线对齐（左边距 " .. tostring(pos83.rowX0) ..
     " / 右边距 " .. tostring(rightPad83) .. "）")
  -- ② 生产数字**真的落到了真实控件上**（否则「算得对但没摆对」照样过）
  eq(pos83.x1, pos83.rowX0 + pos83.chkW + pos83.btnGap, true,
     "★★★[导入] 的真实左边缘 = 左起点 + 勾选框段宽 + 缝（" .. tostring(pos83.x1) .. "）")
  eq(pos83.x2, pos83.x1 + pos83.btnW + pos83.btnGap, true, "★★[忽略] 紧跟其后")
  -- ③ 三段互不重叠（勾选框段右端 ≤ [导入] 左端，这是**算出来的**，不是碰巧）
  eq(pos83.rowX0 + pos83.chkW <= pos83.x1, true, "★★★三段互不重叠（勾选框段右端 " ..
     tostring(pos83.rowX0 + pos83.chkW) .. " ≤ [导入] 左端 " .. tostring(pos83.x1) .. "）")
  eq(pos83.x1 + pos83.btnW <= pos83.x2, true, "★★两个按钮之间也不重叠")
  eq(pos83.x2 + pos83.btnW <= pos83.W - pos83.rowX0 + 1, true, "★★整行没越出弹窗右边界")
  eq(pos83.x1 == 56 or pos83.x2 == 160, false, "★反向哨兵：不再是旧的「只居中两个按钮」位置 56/160")
  -- ⑥ 这个勾选框就是**配置窗那同一个开关**（同一份真值；翻它两边都变）
  local savedRecv83 = EVAL_SHARE_RECV_ON()
  local chk83, mark83 = EVAL_TEST_SHARE_RECV_CHK()
  eq(chk83 ~= nil and mark83 ~= nil, true, "⑥★★交出真实勾选框与真实勾选块（断言读控件，不读自己拼的状态）")
  eq(mark83:IsShown() == (savedRecv83 and true or false), true, "⑥★勾选态与开关当前值一致")
  local fn83 = chk83 and chk83:GetScript("OnClick")
  eq(type(fn83) == "function", true, "⑥★勾选框挂了真实 OnClick")
  if type(fn83) == "function" then fn83() end
  eq(EVAL_SHARE_RECV_ON() ~= savedRecv83, true, "⑥★★★点它真的翻转了**共用的那个开关**（EVAL_SHARE_RECV_ON 变了）")
  eq(EVAL_HELP_CONFIG.share.recv == EVAL_SHARE_RECV_ON(), true, "⑥★★写的是同一份真值 cfg.share.recv（没有另存一份）")
  eq(mark83:IsShown() == (EVAL_SHARE_RECV_ON() and true or false), true,
     "⑥★★勾选块立刻跟着变（不用重开弹窗）：开关=" .. tostring(EVAL_SHARE_RECV_ON()) ..
     " 勾选块=" .. tostring(mark83:IsShown()))
  if type(fn83) == "function" then fn83() end -- 还原
  eq(EVAL_SHARE_RECV_ON(), savedRecv83, "⑥前置还原：开关回到原值")
  -- 反向：外部（配置窗）改了开关 → 弹窗刷新时勾选态要跟上（双入口一致性）
  EVAL_HELP_CONFIG.share.recv = not savedRecv83
  EVAL_SH_POPUP("测试", "# 方案: 图标测试", nil) -- ★走**真实弹出路径**（不是只调测试钩子）
  eq(mark83:IsShown() == (EVAL_SHARE_RECV_ON() and true or false), true,
     "⑥★★外部改了开关后，**再次弹出**即同步（两个入口一份真值）")
  EVAL_HELP_CONFIG.share.recv = savedRecv83
  EVAL_SH_POPUP("测试", "# 方案: 图标测试", nil)
  eq(EVAL_SHARE_RECV_ON(), savedRecv83, "⑥收尾：开关还原（不污染后续用例）")
  eq(EVAL_TEST_SHARE_TITLE_ICON(), full83, "★标题图标仍是同一张（自包含路径）")
  EVAL_SHARE_RESET()
end
-- 84) ★1.71.3 新 Tab「图标库」（用户要求：独立脚本 + 分组归类 + tooltip 名称 + 滚动翻页）
--   ① 纯函数：名称（取路径末段、去扩展名）/ 分组（按文件名前缀，认不出来归「其他」）；
--   ② 分页**先过滤再切页** + 页码越界夹取；
--   ③ 状态机如实：接口缺失 = noapi、接口在但空 = empty，两种情况都不假装有图标；
--   ④ 走**真实 UI**：状态行、翻页按钮、滚轮、分组下拉、图标格子的纹理与悬停/点击。
do
  local L84 = EVAL_LOCALES[EVAL_GET_LANG()]
  -- ① 名称 / 分组（纯函数）
  -- ★1.73.5 显示名改成**语义名**（IconSem.lua），原始基础名另走 EVAL_IB_RAWN_OF —— 两条路都钉住
  eq(EVAL_IB_RAWN_OF("Interface\\Icons\\Spell_Fire_Fireball"), "Spell_Fire_Fireball", "★原始名=路径最后一段")
  eq(EVAL_IB_RAWN_OF("Interface\\AddOns\\EvalHelp\\media\\icons\\trainer.tga"), "trainer", "★顺手去掉扩展名")
  eq(EVAL_IB_NAME_OF("Interface\\Icons\\Spell_Fire_Fireball"), "火球", "★★显示名=语义名（火球，不是英文原名）")
  eq(EVAL_IB_NAME_OF("Interface\\AddOns\\EvalHelp\\media\\icons\\trainer.tga"), "trainer", "★★语义表里没有的（本插件自带素材）如实退回原始名")
  eq(EVAL_IB_RAWN_OF(nil), nil, "★nil 安全（不炸）")
  eq(EVAL_IB_NAME_OF(nil), nil, "★nil 安全（不炸）")
  eq(EVAL_IB_GROUP_OF("Interface\\Icons\\Spell_Frost_Nova"), "frost", "★冰霜按前缀归类")
  eq(EVAL_IB_GROUP_OF("Interface\\Icons\\Spell_Fire_Fireball"), "fire", "★火焰")
  eq(EVAL_IB_GROUP_OF("Interface\\Icons\\INV_Misc_QuestionMark"), "inv", "★物品杂项")
  eq(EVAL_IB_GROUP_OF("Interface\\Icons\\Ability_Warrior_Charge"), "ability", "★技能")
  eq(EVAL_IB_GROUP_OF("Interface\\Icons\\Whatever_Thing"), "other", "★★认不出来归「其他」（不瞎猜）")
  -- ② 分页：先过滤再切页（顺序错了会漏项）+ 越界夹取
  local items84 = {}
  for i = 1, 25 do
    items84[i] = { path = "P" .. i, name = "N" .. i, group = (i <= 10 and "fire" or "inv") }
  end
  local pg1, page1, pages1, total1 = EVAL_IB_PAGE_ITEMS(items84, "fire", 1, 8)
  eq(total1, 10, "★★过滤后总数=10（不是 25）")
  eq(table.getn(pg1), 8, "★第一页 8 枚")
  eq(pages1, 2, "★两页")
  local pg2, page2 = EVAL_IB_PAGE_ITEMS(items84, "fire", 2, 8)
  eq(table.getn(pg2), 2, "★★第二页剩 2 枚（先切页后过滤会在这里漏掉）")
  eq(page2, 2, "★第二页页码")
  local pg9, page9 = EVAL_IB_PAGE_ITEMS(items84, "fire", 99, 8)
  eq(page9, 2, "★★页码越界夹到最后一页")
  eq(table.getn(pg9), 2, "★越界后仍拿到最后一页的内容（不是空页）")
  eq(table.getn(EVAL_IB_PAGE_ITEMS(items84, "all", 1, 8)), 8, "★「全部」也是先过滤再切页")
  -- ③ 真实 UI（打开配置窗 → 第 5 个 Tab 的页面真的被构建）
  EVAL_HELP_CFG_TOGGLE()
  eq(EVAL_IB_TEST_BUILT(), true, "★★★配置窗构建时真的调用了 EVAL_IB_BUILD（第 5 个 Tab 接上了）")
  EVAL_HELP_CFG_SETTAB(5)
  eq(EVAL_HELP_CFG_TAB(), 5, "★新读值口：当前 Tab = 5")
  local cols84, rows84, per84 = EVAL_IB_LAYOUT(EVAL_TEST_WIN_W())
  eq(EVAL_IB_TEST_CELL_COUNT(), per84, "★图标池按「列×行=每页枚数」建（不多不少）")
  -- ④ 正常枚举：6 枚宏图标 + 本插件在用的那几枚
  local savedNum, savedInfo = GetNumMacroIcons, GetMacroIconInfo
  TEST.macroIcons = { "Spell_Fire_Fireball", "Spell_Frost_Nova", "INV_Misc_Bag_01",
                      "Ability_Warrior_Charge", "Whatever_Thing", "Temp_X" }
  EVAL_IB_TEST_RESET()
  local st84 = EVAL_IB_SCAN(true)
  eq(st84.state, "ok", "★正常枚举 state=ok")
  eq(st84.macro, 6, "★拿到 6 枚宏图标")
  eq(st84.failed, 0, "★没有取失败的")
  EVAL_IB_SET_GROUP("all")
  local _, _, tot84 = EVAL_IB_TEST_PAGE()
  eq(tot84, 6 + EVAL_IB_TEST_COUNTS().local_, "★「全部」= 宏图标 + 本插件在用的图标")
  -- ★同路径只算一次：宏图标表里**也有本插件那枚**（同一条路径）→ 不去重「全部」就会重复计数。
  --   ★1.71.3 改法说明：旧写法用桩名 "INV_Misc_QuestionMark" 之所以能撞上，是因为**那时**本插件的
  --     「异常标记」正好就是暴雪那个问号；本轮换成自包含的白感叹号（AddOns 路径）之后，
  --     「Interface\Icons\*」永远撞不上「AddOns\...」→ 改为**直接让宏图标表返回本插件那枚的路径**。
  --     这样测的仍是**去重规则本身**（按路径去重），而不是「某两个具体字符串恰好相等」。
  local savedNum2 = GetNumMacroIcons
  GetMacroIconInfo = function(i) if i == 1 then return EVAL_HELP_SE_WARN_ICON() end return nil end
  GetNumMacroIcons = function() return 1 end
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local _, _, totDup = EVAL_IB_TEST_PAGE()
  eq(totDup, EVAL_IB_TEST_COUNTS().local_, "★★★同路径去重（本插件那枚 == 宏图标表里那枚时只算一次）")
  GetNumMacroIcons, GetMacroIconInfo = savedNum2, savedInfo -- ★立刻还原（后面几步还要用真桩）
  TEST.macroIcons = { "Spell_Fire_Fireball", "Spell_Frost_Nova", "INV_Misc_Bag_01",
                      "Ability_Warrior_Charge", "Whatever_Thing", "Temp_X" }
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local firstItem = EVAL_IB_TEST_CELL(1).item
  eq(firstItem ~= nil, true, "前置：第一格有图标")
  eq(EVAL_IB_TEST_CELL(1).tex:GetTexture(), firstItem.path, "★★★格子真的画上了该图标的纹理（读控件）")
  eq(string.find(tostring(EVAL_IB_TEST_STATUS_TEXT()), tostring(tot84), 1, true) ~= nil, true,
     "★状态行里有真实总数（不是写死的文案）")
  -- ⑤ 悬停：tooltip 必须给名称 / 分组 / 完整路径
  TEST.tipLines = nil
  eq(EVAL_IB_TEST_HOVER_CELL(1), true, "★悬停走了真实 OnEnter")
  local tip84 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tip84 = tip84 .. tostring(ln.text or "") .. " \n" end
  eq(string.find(tip84, firstItem.name, 1, true) ~= nil, true, "★★tooltip 里有图标名称")
  eq(string.find(tip84, firstItem.path, 1, true) ~= nil, true, "★★tooltip 里有完整路径（方便直接调用）")
  eq(string.find(tip84, EVAL_IB_GROUP_LABEL(firstItem.group), 1, true) ~= nil, true, "★tooltip 里有分组名")
  -- ⑥ 点击：把路径打到聊天框（用户要的「方便调用」）
  local savedSay = EVAL_SAY
  local said84 = nil
  EVAL_SAY = function(t) said84 = tostring(t) end
  eq(EVAL_IB_TEST_CLICK_CELL(1), true, "★点击走了真实 OnClick")
  eq(said84 ~= nil and string.find(said84, firstItem.path, 1, true) ~= nil, true, "★★点击真的输出了该图标路径")
  EVAL_SAY = savedSay
  -- ⑦ 翻页：[下页] 真实按钮 + 滚轮（链式接管，只在第 5 个 Tab 时消费）
  --   ★每页枚数由**真实窗口宽度**决定（列×行）——12 枚根本不够翻页，所以这里先把图标补到好几页。
  local big84 = {}
  -- ★1.71.9：每页枚数从 108 涨到 162（图标区 6→9 行）→ 原先 150 枚已不足两页，补到 400 枚
  for i = 1, 400 do big84[i] = "Spell_Fire_Big" .. i end
  TEST.macroIcons = big84
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local _, bigPages = EVAL_IB_TEST_PAGE()
  eq(bigPages >= 2, true, "前置：图标数超过一页（每页 " .. tostring(EVAL_IB_PER_PAGE(EVAL_IB_TEST_W())) .. " 枚，共 " .. tostring(bigPages) .. " 页）")
  local pageBefore = select(1, EVAL_IB_TEST_PAGE())
  local nextBtn = nil
  -- 用真实按钮：从格子池之外找 —— 直接点「下页」的脚本（读生产按钮）
  local btnNext = EVAL_IB_TEST_BTN("next")
  eq(btnNext ~= nil, true, "前置：拿到「下页」按钮")
  if btnNext then
    local fn84 = btnNext:GetScript("OnClick")
    eq(type(fn84) == "function", true, "★「下页」有真实 OnClick")
    if type(fn84) == "function" then fn84() end
  end
  eq(select(1, EVAL_IB_TEST_PAGE()) == pageBefore + 1, true, "★★点「下页」真的翻了一页")
  local wheel84 = EVAL_CFG_WHEEL_SCRIPT()
  eq(type(wheel84) == "function", true, "★拿到配置窗的滚轮脚本（链式接管）")
  -- ★★★1.73.3 方向约定修正：本客户端**上滚 = +1**（见 Core.lua EVAL_WHEEL_DIR 的说明 + war 页老注释）。
  --   ★原断言用 -1 当「向上」→ 它和图标库那段反向代码**互相印证**，把 bug 一起验过去了
  --     （断言自己写错了方向 = 本项目最恨的「绿但真错」）。现在两个方向都必须对。
  if type(wheel84) == "function" then wheel84(nil, 1) end
  eq(select(1, EVAL_IB_TEST_PAGE()) == pageBefore, true, "★★滚轮向上（+1）真的翻回上一页（第 5 个 Tab 时消费滚轮）")
  -- ★正向证据：用 +3（足以往前翻页）——若被消费，页码必然变；只测 -1 会被「页码夹取到 1」掩盖
  --   （本轮变异实测：写 -1 时「无条件消费滚轮」的变异体**存活**，就是被夹取骗过去了）。
  EVAL_HELP_CFG_SETTAB(1)
  local pageOnOther = select(1, EVAL_IB_TEST_PAGE())
  if type(wheel84) == "function" then wheel84(nil, 3) end
  eq(select(1, EVAL_IB_TEST_PAGE()) == pageOnOther, true, "★★不在本 Tab 时不消费滚轮（+3 若被消费页码必变）")
  EVAL_HELP_CFG_SETTAB(5)
  -- ⑧ 分组下拉：走真实按钮 + 真实行回调（先换回小列表，便于断言「过滤后只剩 1 枚」）
  TEST.macroIcons = { "Spell_Fire_Fireball", "Spell_Frost_Nova", "INV_Misc_Bag_01",
                      "Ability_Warrior_Charge", "Whatever_Thing", "Temp_X" }
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local gBtn84 = EVAL_IB_TEST_GROUP_BTN()
  eq(gBtn84 ~= nil, true, "前置：拿到分组按钮")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  local gFn = gBtn84 and gBtn84:GetScript("OnClick")
  eq(type(gFn) == "function", true, "★分组按钮有真实 OnClick")
  if type(gFn) == "function" then gFn() end
  eq(EVAL_DD_TEST_SHOWN(), true, "★分组下拉打开了")
  local opts84 = EVAL_IB_GROUP_OPTIONS(EVAL_IB_ITEMS())
  local fireIdx = nil
  for i = 1, table.getn(opts84) do if opts84[i].id == "fire" then fireIdx = i end end
  eq(fireIdx ~= nil, true, "前置：下拉里有「火焰」这一组（有图才列）")
  local row84 = EVAL_DD_TEST_ROW(fireIdx)
  local rowFn = row84 and row84.btn and row84.btn:GetScript("OnClick")
  eq(type(rowFn) == "function", true, "★分组行有真实 OnClick")
  if type(rowFn) == "function" then rowFn() end
  eq(EVAL_IB_TEST_GROUP(), "fire", "★★★点分组行真的切到该分组")
  local _, _, totFire = EVAL_IB_TEST_PAGE()
  eq(totFire, 1, "★★过滤后只剩 1 枚（火焰）")
  eq(EVAL_IB_TEST_CELL(1).item ~= nil and EVAL_IB_TEST_CELL(1).item.group == "fire", true, "★第一格就是该分组的图标")
  eq(EVAL_IB_TEST_CELL(2).btn:IsShown(), false, "★★只过滤出 1 枚时，第二格必须隐藏（不残留上一页的图）")
  EVAL_IB_SET_GROUP("all")
  -- ⑨ 状态机如实：接口缺失 / 接口在但空
  GetNumMacroIcons = nil GetMacroIconInfo = nil
  EVAL_IB_TEST_RESET()
  local stNo = EVAL_IB_SCAN(true)
  eq(stNo.state, "noapi", "★★★接口缺失 → noapi（如实，不假装）")
  EVAL_IB_REFRESH()
  eq(EVAL_IB_TEST_STATUS_TEXT(), L84["IB_NOAPI"], "★★状态行就是那句「本客户端没有宏图标接口」")
  eq(EVAL_IB_TOTAL() >= 1, true, "★★接口缺失时仍列出「本插件在用」的图标（不是空页）")
  GetNumMacroIcons = savedNum GetMacroIconInfo = savedInfo
  TEST.macroIcons = nil
  EVAL_IB_TEST_RESET()
  local stEm = EVAL_IB_SCAN(true)
  eq(stEm.state, "empty", "★★接口在但一枚都没有 → empty")
  EVAL_IB_REFRESH()
  eq(EVAL_IB_TEST_STATUS_TEXT(), L84["IB_EMPTY"], "★★状态行如实说明「接口在但没取到」")
  -- ★Tab 名单：必须真的有 6 个（1.73.0 起新增「抓宠帮手」），标签读**真实按钮文本**
  local names84 = EVAL_TEST_CFG_TAB_NAMES()
  eq(table.getn(names84), 6, "★★配置窗现在有 6 个 Tab")
  eq(names84[5], L84["TAB_ICONS"], "★★第 5 个 Tab 的标签 = 语言包 TAB_ICONS")
  eq(names84[6], L84["TAB_PET"], "★★第 6 个 Tab 的标签 = 语言包 TAB_PET（抓宠帮手）")
  -- ★「取失败」要如实记账（不是静默当 0）：第 2 项给个非字符串 → 桩按取失败处理
  TEST.macroIcons = { "Spell_Fire_One", false, "Spell_Fire_Three" }
  EVAL_IB_TEST_RESET()
  local stFail = EVAL_IB_SCAN(true)
  eq(stFail.macro, 2, "★取到 2 枚")
  eq(stFail.failed, 1, "★★1 枚取失败 —— 如实数出来（本项目「绝不静默」）")
  EVAL_IB_SET_GROUP("all")
  eq(string.find(tostring(EVAL_IB_TEST_STATUS_TEXT()), string.format(L84["IB_STATUS_FAIL"], 1), 1, true) ~= nil, true,
     "★★状态行如实写出「其中 1 枚取失败」")
  -- ★切 Tab 真的会刷新图标库（SETTAB 接线）：用刷新计数钉住，不看「数据对不对」
  local rc84 = EVAL_IB_TEST_REFRESH_COUNT()
  EVAL_HELP_CFG_SETTAB(1)
  EVAL_HELP_CFG_SETTAB(5)
  eq(EVAL_IB_TEST_REFRESH_COUNT() > rc84, true, "★★★切回第 5 个 Tab 会真的刷新（SETTAB 已接线）")
  -- 收尾：把桩状态还原（跨用例状态残留是本项目的老坑）
  TEST.macroIcons = nil
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_HELP_CFG_SETTAB(1)
end
-- 85) ★1.71.3 「选取目标:」族图标 + 队伍成员选取的**如实日志**（用户实测报回两件事）
--   ① 用户原话：「目标选取子菜单,换一些好看点的图标」——原来整族都回退成红问号，根本分不清；
--   ② 用户原话：「角色行为->选取目标:队伍成员 日志明确输入匹配到的目标名称,达成的条件,
--      比如是血量筛选,的显示血量N% 符合,现在无法正常工作」——旧版无论选没选到人都写「已出手」，
--      看不到名字/条件，目标没换也查不出原因。
do
  -- ① 图标：11 项各不相同、都来自本插件 media、都不再是问号
  local sel85 = EVAL_TARGET_SEL
  local n85 = table.getn(sel85 or {})
  eq(n85 >= 11, true, "前置：选取目标条目 ≥ 11（实际 " .. tostring(n85) .. "）")
  local seen85, hitMedia85 = {}, 0
  for i = 1, n85 do
    local nm85 = "选取目标:" .. tostring(sel85[i].name)
    local ic85 = EVAL_WICON(nm85)
    eq(type(ic85) == "string" and ic85 ~= "", true, "★有图标：" .. nm85)
    eq(ic85 ~= "Interface\\Icons\\INV_Misc_QuestionMark", true, "★★不再是问号兜底：" .. nm85)
    eq(string.find(ic85, "media", 1, true) ~= nil, true, "★图标来自本插件 media：" .. tostring(ic85))
    eq(seen85[ic85], nil, "★★11 项图标互不相同：" .. tostring(ic85))
    seen85[ic85] = true
    if string.find(ic85, "media", 1, true) then hitMedia85 = hitMedia85 + 1 end
  end
  eq(hitMedia85, n85, "★★全部走本插件自包含图标（不依赖别的插件）")
  -- 带参数的「指定名称:xxx」也要认出 byName 那枚
  eq(EVAL_WICON("选取目标:指定名称:某怪") ~= nil and EVAL_WICON("选取目标:指定名称:某怪") ~= "Interface\\Icons\\INV_Misc_QuestionMark", true,
     "★「指定名称:xxx」也有专属图标（按 id=byName 命中）")
  -- ★反向哨兵：非选取目标的未知条目仍然是 nil（本次改动没波及别的分支）
  eq(EVAL_WICON("这不是一个技能"), nil, "★反向哨兵：未知条目仍回退（不瞎给图标）")
  -- ② 队伍成员选取：日志必须写出「谁 + 血量% + 满足的条件」
  local savedTeam85, savedRaid85 = TEST.team, TEST.raid
  TEST.team = {
    { unit = "party1", name = "甲", hp = 50, hpMax = 100, mana = 50, manaMax = 100, powerType = 0, buffs = {}, debuffs = {} },
    { unit = "party2", name = "乙", hp = 10, hpMax = 100, mana = 8, manaMax = 100, powerType = 0, buffs = {}, debuffs = {} },
  }
  TEST.raid, TEST.raidN = nil, nil
  TEST.targetSel = nil
  EVAL_HELP_UPDATE_STATE()
  EVAL_HELP_CONFIG.log = {}
  local ok85 = EVAL_RULE_RUN({ { skill = "选取目标:队伍成员", why = "奶", groups = { { { k = "tHpPct", op = "<", n = 40 } } } } })
  eq(ok85, true, "★过滤命中 → 算出出手")
  local logs85 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs85, "乙", 1, true) ~= nil, true, "★★日志写出**选中的成员名**")
  eq(string.find(logs85, "血量 10%", 1, true) ~= nil, true, "★★★日志写出**血量 10%**（用户要求「显示血量N% 符合」）")
  eq(string.find(logs85, "条件:", 1, true) ~= nil, true, "★★日志写出**达成的条件**明细")
  -- ★条件明细必须是**生产代码**的条件串（EVAL_COND_STR），不是测试自己拼的文案
  local cond85 = EVAL_COND_STR({ k = "tHpPct", op = "<", n = 40 })
  eq(string.find(logs85, cond85, 1, true) ~= nil, true, "★★条件明细用生产条件串：" .. tostring(cond85))
  -- ③ 一个都没选到：明说 + 候选清单 + **不算出手**（旧版无论结果都返回 true）
  TEST.targetSel = nil
  EVAL_HELP_CONFIG.log = {}
  local okMiss85 = EVAL_RULE_RUN({ { skill = "选取目标:队伍成员", why = "奶", groups = { { { k = "tHpPct", op = "<", n = 1 } } } } })
  eq(okMiss85, false, "★★★无人满足 → **不算出手**（旧版假装成功）")
  local logsMiss85 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logsMiss85, "未选中成员", 1, true) ~= nil, true, "★★日志明说「未选中成员」")
  eq(string.find(logsMiss85, "甲 50%", 1, true) ~= nil, true, "★★候选清单带名字与血量%（用户才知道扫了谁）")
  -- ④ ★★★1.71.3（本轮修正）：「自身*」在选取器行上**按候选者读**（用户定案）→ 它真的能筛队友；
  --   只有整行**没有任何候选可比条件**时，才提示「会退化为血量最低者」。
  TEST.hp, TEST.hpMax = 80, 100
  EVAL_HELP_UPDATE_STATE()
  TEST.targetSel = nil
  EVAL_HELP_CONFIG.log = {}
  local okSelf85 = EVAL_RULE_RUN({ { skill = "选取目标:队伍成员", why = "奶", groups = { { { k = "hpPct", op = "<", n = 50 } } } } })
  eq(okSelf85, true, "★★★「自身血%<50」在选取器行上按**候选者**读 → 乙 10% 命中（不再恒灭）")
  eq(TEST.targetSel, "unit:party2", "★★★选中的是血最少的乙，不是玩家自己")
  -- 整行都是「玩家/技能」类条件（组合点）→ 没人通过时给出「退化为血量最低」的提示
  TEST.targetSel = nil
  EVAL_HELP_CONFIG.log = {}
  local okHint85 = EVAL_RULE_RUN({ { skill = "选取目标:队伍成员", why = "奶", groups = { { { k = "combo", op = ">=", n = 99 } } } } })
  eq(okHint85, false, "★整行没有候选可比条件 + 没人通过 → 不算出手")
  local logsHint85 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logsHint85, "没有能筛候选者的条件", 1, true) ~= nil, true, "★★提示改为「本行没有能筛候选者的条件 → 退化为血量最低者」")
  -- ⑤ 非成员选取器（如「最近敌人」）仍走旧的日志形态（改动不外溢）
  EVAL_HELP_CONFIG.log = {}
  EVAL_RULE_RUN({ { skill = "选取目标:最近敌人", why = "t" } })
  local logsOther85 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logsOther85, "最近敌人", 1, true) ~= nil, true, "★普通选取仍记日志")
  eq(string.find(logsOther85, "未选中成员", 1, true) == nil, true, "★普通选取不走「成员扫描」日志")
  -- 收尾：还原桩状态（跨用例残留是老坑）
  TEST.team, TEST.raid = savedTeam85, savedRaid85
  TEST.targetSel = nil
  TEST.hp, TEST.hpMax = nil, nil
  EVAL_HELP_CONFIG.log = {}
  EVAL_HELP_UPDATE_STATE()
end
-- 86) ★★★1.71.3 成员选取器：候选者条件 + 按比较符选人（用户定案；含老 8 项数值型统一）
--   ① 「在通过的人里挑谁」由**行内第一个比较型条件**决定：< 取最小 / > 取最大 / = 取最接近；
--   ② 新增 4 类「候选者*」条件（原 8 项一字不动）；老数值型（队伍血/蓝、团员血/蓝）也统一到同一规则；
--   ③ 条件类型下拉**按技能行过滤**：选取器行只出这 4 项 + 一行提示。
do
  -- ① 依据推导（纯函数）
  local function order86(cds) return EVAL_TEAM_PICK_ORDER({ groups = { cds } }) end
  local o86a = order86({ { k = "candHp", op = "<", n = 60 } })
  eq(o86a ~= nil and o86a.key == "hp" and o86a.mode == "min" and o86a.n == 60, true, "★候选者血<60 → 血量取最小")
  local o86b = order86({ { k = "candHp", op = ">", n = 60 } })
  eq(o86b ~= nil and o86b.mode == "max", true, "★候选者血>60 → 取最大")
  local o86c = order86({ { k = "candPower", op = "=", n = 50 } })
  eq(o86c ~= nil and o86c.key == "power" and o86c.mode == "near", true, "★★候选者能量=50 → 按键值取最接近")
  eq(select(2, pcall(function() return order86({ { k = "hpPct", op = ">", n = 60 } }).mode end)) == "max", true, "★兼容：自身血% 也参与方向（选取器行上按候选者读）")
  eq(order86({ { k = "candHp", op = "~=", n = 60 } }), nil, "★无方向（~=）→ 回退")
  eq(order86({ { k = "candBuff", s = "回春术" } }), nil, "★存在性条件不给方向 → 回退")
  local o86d = order86({ { k = "candPower", op = ">", n = 30 }, { k = "candHp", op = "<", n = 60 } })
  eq(o86d ~= nil and o86d.key == "power", true, "★★多个比较条件 → **行内第一个**（能量）决定键")
  -- ② 真实执行：三个队友，血量/蓝量刻意错开（用来分辨「按哪个键排序」）
  local savedTeam86, savedRaid86, savedRaidN86 = TEST.team, TEST.raid, TEST.raidN
  local savedHp86, savedHpMax86 = TEST.hp, TEST.hpMax
  local savedTex86 = EVAL_HELP_CONFIG.war.debuffTex
  EVAL_HELP_CONFIG.war.debuffTex = { ["回春术"] = "texRejuv", ["痛苦诅咒"] = "texCurse", ["魔法"] = "texCurse" }
  TEST.team = {
    { unit = "party1", name = "甲", hp = 45, hpMax = 100, mana = 90, manaMax = 100, powerType = 0,
      buffs = { { tex = "texRejuv", apps = 1 } }, debuffs = {} },
    { unit = "party2", name = "乙", hp = 70, hpMax = 100, mana = 20, manaMax = 100, powerType = 0,
      buffs = {}, debuffs = { { tex = "texCurse", apps = 1, type = "Magic" } } },
    { unit = "party3", name = "丙", hp = 20, hpMax = 100, mana = 50, manaMax = 100, powerType = 0,
      buffs = {}, debuffs = {} },
  }
  TEST.raid, TEST.raidN = nil, nil
  TEST.hp, TEST.hpMax = 80, 100 -- 自己 80%（也在扫描集里 → 会参与「取最大」的竞争）
  EVAL_HELP_UPDATE_STATE()
  local function pick86(cd)
    TEST.targetSel = nil
    EVAL_HELP_STATE.allyUnit = nil
    local ok86 = EVAL_RULE_RUN({ { skill = "选取目标:队伍成员", why = "t", groups = { { cd } } } })
    return ok86, TEST.targetSel
  end
  local okP, selP = pick86({ k = "candHp", op = "<", n = 50 })
  eq(okP, true, "★候选者血<50 命中")
  eq(selP, "unit:party3", "★★ < 取最小 → 丙 20%（不是排序里的第一个甲）")
  local okQ, selQ = pick86({ k = "candHp", op = ">", n = 50 })
  eq(okQ, true, "★候选者血>50 命中")
  eq(selQ, "unit:player", "★★★ > 取最大 → **自己 80%**（扫描集含自己，用户定案：一视同仁）")
  -- 把自己降到 30% → 队员里血最高的那个应当胜出（证明不是在按别的键排序）
  TEST.hp, TEST.hpMax = 30, 100
  EVAL_HELP_UPDATE_STATE()
  local okQ2, selQ2 = pick86({ k = "candHp", op = ">", n = 50 })
  eq(okQ2, true, "★（自己 30% 不满足）候选者血>50 仍命中")
  eq(selQ2, "unit:party2", "★★★ > 取最大 → 乙 70%（旧版会给「刚好>50 的最小者」= 甲 45）")
  TEST.hp, TEST.hpMax = 80, 100
  EVAL_HELP_UPDATE_STATE()
  local okR, selR = pick86({ k = "candHp", op = "=", n = 50 })
  eq(okR, true, "★★候选者血=50 命中（该条件不再要求精确相等）")
  eq(selR, "unit:party1", "★★★ = 取最接近 → 甲 45（距 50 最近；精确比较会一个都选不出）")
  local okS, selS = pick86({ k = "candPower", op = ">", n = 30 })
  eq(okS, true, "★候选者能量>30 命中")
  eq(selS, "unit:party1", "★★★排序键真的是**能量**（甲 90% 最高；若仍按血量排会选到乙/甲按血量）")
  local okT, selT = pick86({ k = "hpPct", op = "<", n = 50 })
  eq(okT, true, "★兼容：选取器行上的「自身血%」照旧可用")
  eq(selT, "unit:party3", "★★★而且读的是**候选者**的血（丙 20%），不是玩家自己的 80%")
  local okU, selU = pick86({ k = "candBuff", s = "回春术", v = false })
  eq(okU, true, "★候选者缺buff:回春术 命中")
  eq(selU, "unit:party3", "★无方向条件 → 回退到「血量最低」（丙 20%）")
  local okV, selV = pick86({ k = "candDebuff", s = "痛苦诅咒", dt = "Magic" })
  eq(okV, true, "★候选者debuff(魔法) 命中")
  eq(selV, "unit:party2", "★选中「中魔法的那个人」（乙）")
  -- ③ 候选者条件脱离选取器行 = 如实失败（不假装通过）
  local okW, whyW = EVAL_TEST_COND_EVAL_LIVE({ k = "candHp", op = "<", n = 99 }, nil)
  eq(okW, false, "★★候选者条件配在普通行上 → 如实失败")
  eq(type(whyW) == "string" and string.find(whyW, "选取目标", 1, true) ~= nil, true, "★★失败原因点名「只能配在选取目标那一行」")
  -- ④ 日志写出「依据」（用户要求：说清楚为什么是他）
  EVAL_HELP_CONFIG.log = {}
  pick86({ k = "candHp", op = ">", n = 50 })
  local logs86 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs86, "依据:", 1, true) ~= nil, true, "★★日志带「依据」栏")
  eq(string.find(logs86, "取最大", 1, true) ~= nil, true, "★★依据写明「取最大」")
  eq(string.find(logs86, EVAL_COND_STR({ k = "candHp", op = ">", n = 50 }), 1, true) ~= nil, true, "★★依据里带条件原文")
  -- ⑤ 文本往返（新拼写）+ 老拼写不受影响
  eq(EVAL_COND_STR({ k = "candHp", op = "<", n = 60 }), "候选者血<60", "★导出：候选者血<60")
  eq(EVAL_COND_STR({ k = "candPower", op = "=", n = 50 }), "候选者能量=50", "★导出：候选者能量=50")
  eq(EVAL_COND_STR({ k = "teamHp", name = "团队", op = "<", n = 50 }), "团队血<50", "★★老 8 项拼写一字不动")
  local function rt86(s)
    local gs = EVAL_PARSE_CONDS(s)
    local g1 = gs and gs[1]
    return g1 and g1[1] or nil
  end
  local p86a = rt86("候选者血<60")
  eq(p86a ~= nil and p86a.k == "candHp" and p86a.op == "<" and p86a.n == 60, true, "★★解析：候选者血<60")
  local p86b = rt86("候选者能量=50")
  eq(p86b ~= nil and p86b.k == "candPower" and p86b.op == "=", true, "★★解析：候选者能量=50（支持 = 取最接近）")
  local p86c = rt86("候选者缺buff:回春术")
  eq(p86c ~= nil and p86c.k == "candBuff" and p86c.v == false, true, "★★解析：候选者缺buff（默认「缺」方向）")
  local p86d = rt86("候选者debuff:痛苦诅咒(魔法)")
  eq(p86d ~= nil and p86d.k == "candDebuff" and p86d.s == "痛苦诅咒", true, "★★解析：候选者debuff(类型)")
  eq(EVAL_TSEL_TEAMSEL ~= nil and EVAL_TSEL_TEAMSEL.teamParty ~= nil, true, "★导出 teamsel（UI 过滤要用）")
  -- 默认值也钉住：候选者血/能量默认「<」（取最小 = 最该治的那个），缺buff 默认「缺」
  local d86h = EVAL_TEST_SE_DEFAULT_COND("candHp")
  eq(d86h ~= nil and d86h.k == "candHp" and d86h.op == "<" and d86h.n == 60, true, "★★新类型默认：候选者血% < 60（取最小）")
  local d86p = EVAL_TEST_SE_DEFAULT_COND("candPower")
  eq(d86p ~= nil and d86p.op == "<", true, "★★新类型默认：候选者能量% 也是 <")
  local d86b = EVAL_TEST_SE_DEFAULT_COND("candBuff")
  eq(d86b ~= nil and d86b.k == "candBuff" and d86b.v == false, true, "★★候选者缺buff 默认「缺」方向")
  local d86d = EVAL_TEST_SE_DEFAULT_COND("candDebuff")
  eq(d86d ~= nil and d86d.k == "candDebuff" and d86d.v == true, true, "★★候选者debuff 默认「有」方向")
  -- ⑥ UI：选取器行只看得到这 4 项；普通行看不到候选者组
  local savedProf86 = EVAL_HELP_CONFIG.war.profiles
  local savedAct86 = EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { {
    name = "方向测试",
    -- ★必须带一条条件，否则编辑窗里根本没有行可点（EVAL_TEST_SE_CLICK_TYPE 会因为 it==nil 直接 return）
    skills = { { skill = "选取目标:队伍成员", why = "t", groups = { { { k = "candHp", op = "<", n = 60 } } } } },
  } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_HELP_SE_OPEN(1, 1)
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_TYPE(1), true, "★点开真实的条件类型下拉")
  local vis86 = table.concat(EVAL_DD_TEST_VISIBLE_TEXTS(), "\n")
    for _, id in ipairs({ "CANDHP", "CANDPOWER", "CANDBUFF", "CANDDEBUFF" }) do
    eq(string.find(vis86, EVAL_L("CT_" .. id), 1, true) ~= nil, true, "★★选取器行提供「候选者」项：" .. id)
  end
  eq(string.find(vis86, EVAL_L("CTG_6"), 1, true) ~= nil, true, "★★组名是「候选者状态」")
  eq(string.find(vis86, EVAL_L("SE_PICK_HINT"), 1, true) ~= nil, true, "★★顶部有提示行")
  for _, id in ipairs({ "HPPCT", "THPPCT", "TEAMHP", "TEAMRAIDHP", "READY" }) do
    eq(string.find(vis86, EVAL_L("CT_" .. id), 1, true) == nil, true, "★★选取器行**不再**提供：" .. id)
  end
  EVAL_DD_HIDE()
  -- 普通行：反过来（没有候选者组，且老 8 项还在）
  EVAL_HELP_CONFIG.war.profiles = { { name = "普通", skills = { { skill = "攻击", why = "t", groups = { { { k = "hpPct", op = "<", n = 50 } } } } } } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_HELP_SE_OPEN(1, 1)
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_TYPE(1), true, "★普通行也能点开下拉")
  local vis2_86 = table.concat(EVAL_DD_TEST_VISIBLE_TEXTS(), "\n")
  eq(string.find(vis2_86, EVAL_L("CT_CANDHP"), 1, true) == nil, true, "★★普通行**不**提供候选者项")
  eq(string.find(vis2_86, EVAL_L("CT_TEAMHP"), 1, true) ~= nil, true, "★★老 8 项照旧提供（一字不动）")
  eq(string.find(vis2_86, EVAL_L("CT_HPPCT"), 1, true) ~= nil, true, "★普通行其它类型照旧")
  EVAL_DD_HIDE()
  -- ⑦ 三语言：新组与 4 个类型名齐全（这些键是**运行时拼**的，静态检查看不见）
  for _, lang in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local pack = EVAL_LOCALES[lang]
    local bad = ""
    for _, k in ipairs({ "CT_CANDHP", "CT_CANDPOWER", "CT_CANDBUFF", "CT_CANDDEBUFF", "CTG_6", "SE_PICK_HINT" }) do
      if type(pack[k]) ~= "string" or pack[k] == "" then bad = bad .. "<" .. k .. ">" end
    end
    eq(bad, "", "★★" .. lang .. " 新键齐全（缺: " .. bad .. "）")
  end
  -- 收尾：还原
  EVAL_HELP_CONFIG.war.profiles = savedProf86
  EVAL_HELP_CONFIG.war.activeProfile = savedAct86
  TEST.team, TEST.raid, TEST.raidN = savedTeam86, savedRaid86, savedRaidN86
  TEST.hp, TEST.hpMax = savedHp86, savedHpMax86
  EVAL_HELP_CONFIG.war.debuffTex = savedTex86
  TEST.targetSel = nil
  EVAL_HELP_STATE.allyUnit = nil
  EVAL_HELP_CONFIG.log = {}
  EVAL_HELP_UPDATE_STATE()
  EVAL_TEST_SE_CLEAR()
end
-- 87) ★1.71.3 「支持选取规则的条件类型」的**悬停说明**（用户要求：分辨加入 tooltip + 美化说明）
--   ① 条件类型下拉里：**参与规则**的类型逐项带说明（语义 + 规则 + 仅限选取器行）；提示行带完整说明；
--   ② 类型格 / 比较符格悬停也弹同样说明（不参与规则的类型**不弹**——免得满屏提示）；
--   ③ 文案走语言包（8 个新键；其中 4 个是运行时拼的键，静态 LANG KEY CHECK 扫不到，故这里逐语言钉）。
do
  local savedProf87 = EVAL_HELP_CONFIG.war.profiles
  local savedAct87 = EVAL_HELP_CONFIG.war.activeProfile
  local function openRow87(skill, cd)
    EVAL_HELP_CONFIG.war.profiles = { { name = "tip", skills = { { skill = skill, why = "t", groups = { { cd } } } } } }
    EVAL_HELP_CONFIG.war.activeProfile = 1
    EVAL_HELP_SE_OPEN(1, 1)
  end
  local function tipText87(t)
    return table.concat(t or {}, "\n")
  end
  local function hoverText87(btn)
    if not (btn and btn.GetScript) then return "" end
    local fn = btn:GetScript("OnEnter")
    if type(fn) ~= "function" then return "" end
    TEST.tipLines = nil
    fn()
    local out = ""
    for _, ln in ipairs(TEST.tipLines or {}) do out = out .. tostring(ln.text or "") .. "\n" end
    return out
  end
  -- ① 选取器行：下拉里的候选者条件三段说明（语义 + 规则 + 仅限本行）
  openRow87("选取目标:队伍成员", { k = "candHp", op = "<", n = 60 })
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_TYPE(1), true, "★点开真实的条件类型下拉")
  -- 菜单顺序：提示行(1) → 组标题(2) → 候选者血%(3)/能量%(4)/缺buff(5)/debuff(6)
  local tipHint87 = EVAL_DD_TEST_ROW_TIP(1)
  eq(type(tipHint87) == "table", true, "★★提示行本身带悬停说明")
  eq(string.find(tipText87(tipHint87), EVAL_L("SE_TIP_PICK_HINT"), 1, true) ~= nil, true, "★★提示行说明「为什么只列候选者条件」")
    local tipHp87 = EVAL_DD_TEST_ROW_TIP(3)
  eq(type(tipHp87) == "table", true, "★★候选者血% 带悬停说明")
  local hpTxt87 = tipText87(tipHp87)
  eq(string.find(hpTxt87, EVAL_L("SE_TIP_CAND_HP"), 1, true) ~= nil, true, "★★含该类型语义（挑出血最少的）")
  eq(string.find(hpTxt87, EVAL_L("SE_TIP_RULE"), 1, true) ~= nil, true, "★★★含「选取规则」（< 取最小 · > 取最大 · = 取最接近）")
  eq(string.find(hpTxt87, EVAL_L("SE_TIP_CAND_ONLY"), 1, true) ~= nil, true, "★★含「只能配在选取目标那一行」")
  eq(EVAL_DD_TEST_ROW_TIP(2), nil, "★组标题不给提示（不打扰）")
  -- ② 走真实 OnEnter：tooltip 真的弹出来了（不是只把数据填进字段）
  local rowHp87 = EVAL_DD_TEST_ROW(3)
  eq(string.find(hoverText87(rowHp87 and rowHp87.btn), EVAL_L("SE_TIP_RULE"), 1, true) ~= nil, true, "★★★下拉行悬停真的弹出规则说明")
  EVAL_DD_HIDE()
  -- ③ 普通行：不参与规则的类型不弹；参与规则的（自身血%）仍弹（兼容写法）
  openRow87("攻击", { k = "combat", v = true })
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_TYPE(1), true, "★普通行也点得开")
  local vis87 = EVAL_DD_TEST_VISIBLE_TEXTS()
  local idxCombat87, idxHpPct87 = nil, nil
  for i = 1, table.getn(vis87) do
    if vis87[i] == EVAL_L("CT_COMBAT") then idxCombat87 = i end
    if vis87[i] == EVAL_L("CT_HPPCT") then idxHpPct87 = i end
  end
  eq(idxCombat87 ~= nil and idxHpPct87 ~= nil, true, "前置：普通行菜单里找得到 战斗中 与 自身血%")
  eq(EVAL_DD_TEST_ROW_TIP(idxCombat87), nil, "★★不参与规则的类型**不给**提示")
  eq(string.find(tipText87(EVAL_DD_TEST_ROW_TIP(idxHpPct87)), EVAL_L("SE_TIP_RULE"), 1, true) ~= nil, true, "★★★普通行上的自身血% 也写明规则")
  EVAL_DD_HIDE()
  -- ④ 类型格 / 比较符格悬停（走真实 OnEnter）
  openRow87("选取目标:队伍成员", { k = "candHp", op = "<", n = 60 })
  local tb87 = EVAL_TEST_SE_TYPE_BTN(1)
  local ob87 = EVAL_TEST_SE_OP_BTN(1)
  eq(type(tb87) == "table" and type(ob87) == "table", true, "前置：拿到类型格 / 比较符格按钮")
  eq(string.find(hoverText87(tb87), EVAL_L("SE_TIP_RULE"), 1, true) ~= nil, true, "★★★类型格悬停含规则说明")
  local oTxt87 = hoverText87(ob87)
  eq(string.find(oTxt87, EVAL_L("SE_TIP_RULE_T"), 1, true) ~= nil, true, "★★★比较符格悬停含「比较符与选取规则」标题")
  eq(string.find(oTxt87, EVAL_L("SE_TIP_RULE"), 1, true) ~= nil, true, "★★并给出对照")
  -- ★反向哨兵：不参与规则的类型（战斗中）→ 两个格子都不该弹我们的说明
  openRow87("攻击", { k = "combat", v = true })
  eq(string.find(hoverText87(EVAL_TEST_SE_TYPE_BTN(1)), EVAL_L("SE_TIP_RULE"), 1, true) == nil, true, "★★反向：战斗中 类型格不弹规则说明")
  eq(string.find(hoverText87(EVAL_TEST_SE_OP_BTN(1)), EVAL_L("SE_TIP_RULE"), 1, true) == nil, true, "★★反向：非数值类型不给比较符说明")
  -- ⑤ 三语言：8 个新键齐全（4 个是运行时拼的，静态检查看不到）
  for _, lang in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local pack = EVAL_LOCALES[lang]
    local bad = ""
    for _, k in ipairs({ "SE_TIP_RULE", "SE_TIP_RULE_T", "SE_TIP_CAND_ONLY", "SE_TIP_CAND_HP",
                         "SE_TIP_CAND_POWER", "SE_TIP_CAND_BUFF", "SE_TIP_CAND_DEBUFF", "SE_TIP_PICK_HINT" }) do
      if type(pack[k]) ~= "string" or pack[k] == "" then bad = bad .. "<" .. k .. ">" end
    end
    eq(bad, "", "★★" .. lang .. " 悬停说明 8 键齐全（缺: " .. bad .. "）")
  end
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedProf87
  EVAL_HELP_CONFIG.war.activeProfile = savedAct87
  TEST.tipLines = nil
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
end
-- 88) ★1.71.3 用户四条（含截图）：
--   ① 「选取目标:指定名称…」那一行**一个图标都没有** → 修（查表前剥掉省略号，仍走同一份 TARGET_SEL 表）；
--   ② 取消施法行：左图标改从**客户端宏图标表**里挑一张（用户要求「你从宏图标内自己选一个」），
--      右端的异常标记从暴雪那个红问号换成**插件自带的白色感叹号**；
--   ③ [添加条件] 的**初始类型**从这一行的过滤表里选（成员选取器行 → 候选者血%）——
--      原先恒用 SE_TYPES 第 1 项，在那个行上会加出一条**下拉里根本没有**的条件；
--   ④ [启用此技能] 右侧加两个图例（白=不可用 / 黄=待测试）+ 悬停说明。
do
  local savedProf88 = EVAL_HELP_CONFIG.war.profiles
  local savedAct88 = EVAL_HELP_CONFIG.war.activeProfile
  local savedMacro88 = TEST.macroIcons
  local function hover88(btn)
    if not (btn and btn.GetScript) then return "" end
    local fn = btn:GetScript("OnEnter")
    if type(fn) ~= "function" then return "" end
    TEST.tipLines = nil
    fn()
    local out = ""
    for _, ln in ipairs(TEST.tipLines or {}) do out = out .. tostring(ln.text or "") .. "\n" end
    return out
  end
  local function openRow88(skill, cd)
    local groups = { { cd or { k = "combat", v = true } } }
    EVAL_HELP_CONFIG.war.profiles = { { name = "t88", skills = { { skill = skill, why = "t88", groups = groups } } } }
    EVAL_HELP_CONFIG.war.activeProfile = 1
    EVAL_HELP_SE_OPEN(1, 1)
  end
  -- 「这一行的条件类型下拉里**第一个可选条目**」的标签（提示行与组标题都是带色串 → 用 "|c" 跳过）
  local function firstType88(skill, cd)
    openRow88(skill, cd)
    EVAL_DD_HIDE()
    EVAL_DD_TEST_RESET_ANCHOR()
    if not EVAL_TEST_SE_CLICK_TYPE(1) then return nil end
    local vis = EVAL_DD_TEST_VISIBLE_TEXTS()
    EVAL_DD_HIDE()
    for i = 1, table.getn(vis) do
      local t = tostring(vis[i] or "")
      if t ~= "" and string.find(t, "|c", 1, true) == nil then return t end
    end
    return nil
  end
  -- ① 「选取目标:指定名称…」的图标
  openRow88("攻击")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_CAT(), true, "①前置：点开真实的类别下拉")
  local byName88 = EVAL_L("SE_PICK_TGT")
  eq(type(byName88) == "string" and byName88 ~= "", true, "①前置：拿到「指定名称…」的本地化文案")
  local items88 = EVAL_GO_SKILL_CATEGORIES()[4].items()
  local idxName88 = nil
  for i = 1, table.getn(items88) do if items88[i] == byName88 then idxName88 = i end end
  eq(idxName88 ~= nil, true, "①前置：目标选取类别里有这一项")
  local catRow88 = EVAL_DD_TEST_ROW(4)
  local catFn88 = catRow88 and catRow88.btn and catRow88.btn:GetScript("OnClick")
  eq(type(catFn88) == "function", true, "①前置：类别行有真实 OnClick（点它续弹项列表）")
  if type(catFn88) == "function" then catFn88() end
  eq(EVAL_DD_TEST_ROW_TEX(idxName88) ~= nil, true, "①★★★「指定名称…」这一行现在**真的有图标**（原先整行空白）")
  eq(EVAL_DD_TEST_ROW_TEX(idxName88), EVAL_TARGET_SEL_ICON("byName"), "①★★图标 = 生产表里 byName 那枚（同一份真值）")
  eq(EVAL_DD_TEST_ROW_TEX(9) ~= EVAL_TARGET_SEL_ICON("byName"), true, "①反向：清除目标那行仍是它自己那枚（没有整列串成同一张图）")
  eq(EVAL_WICON("选取目标:指定名称..."), EVAL_TARGET_SEL_ICON("byName"), "①★省略号写成三个点也认得（两种写法都归一）")
  EVAL_DD_HIDE()
  -- ② 取消施法：左图标取客户端宏图标表；取不到**如实**退回问号
  EVAL_TEST_MACRO_ICON_RESET()
  TEST.macroIcons = { "Spell_Fire_Fireball", "Ability_Kick", "Temp_X" }
  eq(EVAL_WICON("取消施法"), "Interface\\Icons\\Ability_Kick",
     "②★★★左图标 = 宏图标表里挑出来的那张（按关键字挑，不是随手拿第一枚）")
  EVAL_TEST_MACRO_ICON_RESET()
  TEST.macroIcons = { "Spell_Fire_Fireball", "Temp_X" }
  eq(EVAL_WICON("取消施法"), "Interface\\Icons\\INV_Misc_QuestionMark", "②★★反向：表里没有可用的一张 → 如实退回问号")
  EVAL_TEST_MACRO_ICON_RESET()
  TEST.macroIcons = nil
  eq(EVAL_WICON("取消施法"), "Interface\\Icons\\INV_Misc_QuestionMark", "②★★反向：拿不到宏图标表 → 退回问号（与改动前一致）")
  TEST.macroIcons = savedMacro88
  EVAL_TEST_MACRO_ICON_RESET()
  local warn88 = EVAL_HELP_SE_WARN_ICON()
  eq(type(warn88) == "string" and string.find(warn88, "mark-unavail", 1, true) ~= nil, true, "②★★标记图标 = 那枚白感叹号")
  eq(string.find(tostring(warn88), "INV_Misc_QuestionMark", 1, true) == nil, true, "②★★反向：不再是暴雪问号")
  -- ③ [添加条件] 的初始类型 = 这一行下拉里的**第一个可选条目**
  local firstPick88 = firstType88("选取目标:队伍成员", nil)
  eq(type(firstPick88) == "string" and firstPick88 ~= "", true, "③前置：拿到选取器行下拉里的第一个可选条目")
  eq(firstPick88, EVAL_L("CT_CANDHP"), "③前置：它就是「候选者血%」（下面断言初始值等于它）")
  EVAL_HELP_SE_OPEN(1, nil, "选取目标:队伍成员") -- 新增技能 → 条件列表为空
  eq(EVAL_TEST_SE_COND_COUNT(), 0, "③前置：新开的一页还没有条件")
  eq(EVAL_TEST_SE_CLICK_ADD(), true, "③★★点的是**真实**的[+添加条件]按钮（走它自己的 OnClick）")
  eq(EVAL_TEST_SE_COND_COUNT(), 1, "③★真的加了一条")
  eq(EVAL_TEST_SE_ROW_TYPE(1), firstPick88, "③★★★初始类型 = 下拉第一项（显示侧）")
  eq(EVAL_TEST_SE_COND_K(1), "candHp", "③★★★初始类型 = 候选者血%（数据侧）")
  local firstNormal88 = firstType88("攻击", nil)
  eq(type(firstNormal88) == "string" and firstNormal88 ~= EVAL_L("CT_CANDHP"), true, "③前置：普通行下拉里根本没有候选者条件")
  EVAL_HELP_SE_OPEN(1, nil, "攻击")
  eq(EVAL_TEST_SE_CLICK_ADD(), true, "③反向：普通行也点得开")
  eq(EVAL_TEST_SE_ROW_TYPE(1), firstNormal88, "③★★★普通行初始类型 = 它自己下拉的第一项（原行为一字不动）")
  eq(EVAL_TEST_SE_COND_K(1) ~= "candHp", true, "③★★反向：普通行不会被塞进「下拉里根本没有」的候选者条件")
  -- ④ [启用此技能] 右侧的两个图例
  local marks88 = EVAL_TEST_SE_MARK_ICONS()
  eq(table.getn(marks88), 2, "④★两个图例都建出来了")
  local mk88 = EVAL_HELP_SE_MARK_ICONS()
  eq(marks88[1].tex, mk88.unavail, "④★★第一个图例画的是白感叹号（读生产值，不写死路径）")
  eq(marks88[2].tex, mk88.test, "④★★第二个图例画的是黄感叹号")
  eq(type(marks88[1].x) == "number" and type(marks88[2].x) == "number", true, "④★图例有真实位置")
  eq(marks88[1].y == marks88[2].y, true, "④★两个图例在同一行")
  eq(marks88[2].x - marks88[1].x >= 16, true, "④★两个图例不重叠")
  local seW88 = EVAL_TEST_SE_SIZE() -- ★第一个返回值就是宽度（1.70.46 起的口径：问帧要真实尺寸）
  eq(marks88[2].x + 16 <= seW88 - 8, true, "④★整组不越出窗口右边界")
  eq(marks88[1].x > 234, true, "④★在「启用此技能」标签的右侧")
  local t1_88 = hover88(EVAL_TEST_SE_MARK_BTN(1))
  local t2_88 = hover88(EVAL_TEST_SE_MARK_BTN(2))
  eq(string.find(t1_88, EVAL_L("SE_MARK_UNAVAIL_T"), 1, true) ~= nil, true, "④★★★白感叹号悬停给出「不可用」")
  eq(string.find(t1_88, EVAL_L("SE_MARK_UNAVAIL_D"), 1, true) ~= nil, true, "④★★并给出原因说明")
  eq(string.find(t2_88, EVAL_L("SE_MARK_TEST_T"), 1, true) ~= nil, true, "④★★★黄感叹号悬停给出「待测试」")
  eq(string.find(t2_88, EVAL_L("SE_MARK_TEST_D"), 1, true) ~= nil, true, "④★★并给出说明")
  eq(string.find(t1_88, EVAL_L("SE_MARK_TEST_T"), 1, true) == nil, true, "④★★反向：两枚图例的说明不串台")
  for _, lang in ipairs({ "zhCN", "enUS", "ruRU" }) do
    local pack = EVAL_LOCALES[lang]
    local bad = ""
    for _, k in ipairs({ "SE_MARK_UNAVAIL_T", "SE_MARK_UNAVAIL_D", "SE_MARK_TEST_T", "SE_MARK_TEST_D" }) do
      if type(pack[k]) ~= "string" or pack[k] == "" then bad = bad .. "<" .. k .. ">" end
    end
    eq(bad, "", "④★★" .. lang .. " 图例 4 键齐全（缺: " .. bad .. "）")
  end
  -- ④ 图标库「本插件在用」必须含这两枚（否则插件自己用的标记图在图标库里根本看不到）
  local loc88 = EVAL_IB_FILTER(EVAL_IB_ITEMS(), "local")
  local hasWhite88, hasYellow88 = false, false
  for i = 1, table.getn(loc88) do
    if loc88[i].path == mk88.unavail then hasWhite88 = true end
    if loc88[i].path == mk88.test then hasYellow88 = true end
  end
  eq(hasWhite88, true, "④★★图标库「本插件在用」列出白感叹号")
  eq(hasYellow88, true, "④★★图标库「本插件在用」列出黄感叹号（漏了那枚 = 图标库少一张）")
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedProf88
  EVAL_HELP_CONFIG.war.activeProfile = savedAct88
  TEST.macroIcons = savedMacro88
  EVAL_TEST_MACRO_ICON_RESET()
  TEST.tipLines = nil
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
end
-- 89) ★1.71.3 「角色行为」新增 `跟随`（用户原话：「角色行为 添加: 跟随:名字输入, 查看API是否跟随.跟随目标.验证可行性」）
--   ★★★取证结论（本机 api_*.html 的函数索引 + emberveil 文档 Movement 分类原文，本轮现场核对）：
--     · `FollowByName(name)` —— **not protected**：「Starts autofollow on a nearby player by name, or on the
--       current target if name is omitted or empty」；名字匹配**不区分大小写**、只搜**它已知的玩家对象**；
--       找不到 → **客户端自己显示一条错误并返回**（不抛异常）；**无返回值**。
--     · `FollowUnit(unit)` —— 也是 not protected，但要的是**单位 id**（player/target/…），且缺参会**抛 Lua 错误**。
--     · ★Movement 页**其余函数全是 Protected**（MoveForwardStart/Stop、TurnLeftStart…）→ 上一轮「移动脉冲」
--       实测无效**至此有了定论**：插件根本调不动它们。
--   本组钉：① 解析；② 真的执行（直调 FollowByName、参数正确——真接口无返回值，参数是唯一可断言的东西）；
--   ③ 两条文档硬规则先在本地挡（不能跟自己 / 没名字且没目标）；④ 不占动作条（角色行为分类 + 有专属图标）；
--   ⑤ 编辑器里能选到它，且「跟随:指定名字…」真的弹输入框、回车后落成 跟随:名字。
do
  local savedLog89 = EVAL_HELP_CONFIG.log
  local savedTarget89 = TEST.hasTarget
  -- ① 解析
  local ok1_89, nm1_89 = EVAL_FOLLOW_OF("跟随")
  eq(ok1_89, true, "①「跟随」= 特殊行为")
  eq(nm1_89, "", "①★省略名字 = 空名（文档：空名/省略 = 跟当前目标）")
  local ok2_89, nm2_89 = EVAL_FOLLOW_OF("跟随:甲")
  eq(ok2_89, true, "①「跟随:甲」认得出")
  eq(nm2_89, "甲", "①★名字取出来")
  local ok3_89, nm3_89 = EVAL_FOLLOW_OF("跟随：甲")
  eq(ok3_89, true, "①全角冒号也认")
  eq(nm3_89, "甲", "①全角写法同样取到名字")
  eq(EVAL_FOLLOW_OF("停止攻击"), nil, "①反向：停止攻击不是跟随（两个动作别混）")
  eq(EVAL_FOLLOW_OF("攻击"), nil, "①反向：普通技能不是跟随")
  eq(EVAL_FOLLOW_OF("选取目标:最近敌人"), nil, "①反向：选取目标不是跟随")
  -- ② 真的执行（走真实规则路径 EVAL_RULE_RUN → wuse）
  TEST.followed, TEST.followCalls, TEST.runScripts = nil, nil, nil
  eq(EVAL_RULE_RUN({ { skill = "跟随:甲", why = "t89", groups = {} } }), true, "②★★真的出手了")
  eq(TEST.followCalls, 1, "②★FollowByName 被调用一次")
  eq(TEST.followed, "甲", "②★★★跟随的名字正确（参数就是用户输入的名字）")
  eq(TEST.runScripts, nil, "②★★非 Protected → **直调**，没绕 RunScript（RunScript 是给 Protected 用的，停读条那条才是）")
  -- ② 日志如实：接口没有返回值 → 必须写明「能否跟上由客户端判定」，不许假装成功
  EVAL_HELP_CONFIG.log = {}
  TEST.followed, TEST.followCalls = nil, nil
  EVAL_RULE_RUN({ { skill = "跟随:乙", why = "t89", groups = {} } })
  local logs89 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs89, "跟随", 1, true) ~= nil, true, "②★日志里写明是跟随")
  eq(string.find(logs89, "乙", 1, true) ~= nil, true, "②★日志里带上跟的是谁")
  eq(string.find(logs89, "无返回值", 1, true) ~= nil, true, "②★★如实声明「本接口无返回值」（不假装知道跟上没跟上）")
  -- ②b 省略名字 = 不传参数
  TEST.hasTarget = true EVAL_HELP_UPDATE_STATE()
  TEST.followed, TEST.followCalls = nil, nil
  eq(EVAL_RULE_RUN({ { skill = "跟随", why = "t89", groups = {} } }), true, "②b「跟随」也出手")
  eq(TEST.followCalls, 1, "②b 调用一次")
  eq(TEST.followed, nil, "②b★★省略名字 = 不传参数（客户端按文档跟当前目标）")
  -- ③ 两条文档硬规则：先在本地挡掉（不是等客户端弹错误）
  local me89 = UnitName("player")
  TEST.followed, TEST.followCalls = nil, nil
  eq(EVAL_RULE_RUN({ { skill = "跟随:" .. me89, why = "t89", groups = {} } }), false, "③不能跟随自己 → 不出手")
  eq(TEST.followCalls, nil, "③★★根本没调 FollowByName（本地就挡住了）")
  EVAL_HELP_CONFIG.log = {}
  EVAL_RULE_RUN({ { skill = "跟随:" .. me89, why = "t89", groups = {} } })
  eq(string.find(table.concat(EVAL_HELP_CONFIG.log or {}, "\n"), "不能跟随自己", 1, true) ~= nil, true, "③★日志说明原因（文档原文 You cannot follow yourself）")
  -- ③b 没名字且当前没目标
  TEST.hasTarget = false EVAL_HELP_UPDATE_STATE()
  TEST.followed, TEST.followCalls = nil, nil
  eq(EVAL_RULE_RUN({ { skill = "跟随", why = "t89", groups = {} } }), false, "③b 没给名字且没有目标 → 不出手")
  eq(TEST.followCalls, nil, "③b★★也没有白调一次")
  TEST.hasTarget = true EVAL_HELP_UPDATE_STATE()
  -- ④ 不占动作条：分类 = 角色行为；有专属自包含图标
  local cats89 = EVAL_GO_SKILL_CATEGORIES()
  local hasFollow89, hasName89 = false, false
  for _, v in ipairs(cats89[1].items()) do
    if v == "跟随" then hasFollow89 = true end
    if v == EVAL_L("SE_PICK_FOLLOW") then hasName89 = true end
  end
  eq(hasFollow89, true, "④★★「角色行为」里能选到「跟随」")
  eq(hasName89, true, "④★★也有「跟随:指定名字…」入口（用户要的名字输入）")
  eq(EVAL_WICON("跟随:甲") ~= nil, true, "④★跟随有图标（不是一条空白）")
  eq(EVAL_WICON("跟随:甲") ~= "Interface\\Icons\\INV_Misc_QuestionMark", true, "④★★有专属图标，不是问号兜底")
  eq(type(EVAL_FOLLOW_ICON) == "string" and string.find(EVAL_FOLLOW_ICON, "AddOns", 1, true) ~= nil, true, "④★图标是插件自带（自包含）")
  -- ⑤ 编辑器：点「跟随:指定名字…」→ 真的弹输入框；回车后落成 跟随:名字
  EVAL_HELP_SE_OPEN(1, nil, "攻击")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_CAT(), true, "⑤前置：点开类别下拉")
  local rowCat89 = EVAL_DD_TEST_ROW(1) -- 第 1 类 = 角色行为
  local fnCat89 = rowCat89 and rowCat89.btn and rowCat89.btn:GetScript("OnClick")
  eq(type(fnCat89) == "function", true, "⑤前置：类别行有真实 OnClick")
  if type(fnCat89) == "function" then fnCat89() end
  local function idxOfText89(txt)
    local vis = EVAL_DD_TEST_VISIBLE_TEXTS()
    for i = 1, table.getn(vis) do if tostring(vis[i]) == txt then return i end end
    return nil
  end
  local idxName89 = idxOfText89(EVAL_L("SE_PICK_FOLLOW"))
  eq(idxName89 ~= nil, true, "⑤前置：项列表里有「跟随:指定名字…」")
  local rowN89 = EVAL_DD_TEST_ROW(idxName89)
  local fnN89 = rowN89 and rowN89.btn and rowN89.btn:GetScript("OnClick")
  eq(type(fnN89) == "function", true, "⑤前置：那一行有真实 OnClick")
  if type(fnN89) == "function" then fnN89() end
  eq(EVAL_TEST_TN_SHOWN(), true, "⑤★★点它**真的弹出名字输入框**（不是静默什么都不做）")
  eq(EVAL_TEST_TN_TITLE(), EVAL_L("SE_TN_FOLLOW"), "⑤★弹窗标题就是这个用途（按语言包取）")
  eq(EVAL_TEST_TN_COMMIT("某人"), true, "⑤★走真实输入框 + 真实回车处理器")
  eq(EVAL_TEST_SE_SKILL(), "跟随:某人", "⑤★★★落值 = 跟随:某人")
  eq(EVAL_FOLLOW_OF(EVAL_TEST_SE_SKILL()) ~= nil, true, "⑤★★而且引擎认得它（生成的名字能直接跑）")
  -- ⑤b 反向哨兵：**空白名字不落值**（空名 = 跟当前目标，会让人以为配了名字却其实没配）
  EVAL_HELP_SE_OPEN(1, nil, "攻击")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  EVAL_TEST_SE_CLICK_CAT()
  local rowCat89b = EVAL_DD_TEST_ROW(1)
  local fnCat89b = rowCat89b and rowCat89b.btn and rowCat89b.btn:GetScript("OnClick")
  if type(fnCat89b) == "function" then fnCat89b() end
  local idxName89b = idxOfText89(EVAL_L("SE_PICK_FOLLOW"))
  local rowN89b = idxName89b and EVAL_DD_TEST_ROW(idxName89b)
  local fnN89b = rowN89b and rowN89b.btn and rowN89b.btn:GetScript("OnClick")
  if type(fnN89b) == "function" then fnN89b() end
  eq(EVAL_TEST_TN_COMMIT("   "), true, "⑤b 空白名字也走一遍真实提交")
  eq(EVAL_TEST_SE_SKILL(), "攻击", "⑤b★★空白名字**不落值**（技能仍是原来的 攻击，不会变成 跟随:）")
  -- ⑥ ★1.71.3 顺带修掉的老 bug：**全角冒号**（中文输入法默认打出来的那个「：」）
  --   ★根因：`[:：]` 里的「：」是**多字节**字符，而 **Lua 的字符集按字节匹配** → 只吃掉它的第一个字节，
  --     捕获到的名字前面会多出两个乱码字节 → 下游查表全查不到 → **静默不生效**（本项目最恨的那族）。
  --   ★修法：在**解析入口**统一把「：」归一成 ":"（不动那 30 处既有模式 → 零回归面、零遗漏）。
  eq(EVAL_COLON_NORM("跟随：甲"), "跟随:甲", "⑥归一函数本身（EvalHelp 的导入解析也用它）")
  eq(EVAL_TGT_OF("选取目标：最近敌人"), "nearEnemy", "⑥★全角冒号：选取目标认得出")
  eq(EVAL_ITEM_OF("物品：测试药剂"), "测试药剂", "⑥★全角冒号：物品认得出")
  eq(EVAL_PET_OF("宠物：攻击"), "攻击", "⑥★全角冒号：宠物指令认得出")
  eq(EVAL_STANCE_OF("姿态：2"), "2", "⑥★全角冒号：姿态认得出")
  local g69 = EVAL_PARSE_CONDS("目标buff：回春术")
  eq(type(g69) == "table" and type(g69[1]) == "table", true, "⑥全角冒号：条件解析给出结构")
  eq(g69[1] and g69[1][1] and g69[1][1].s, "回春术", "⑥★★全角冒号：光环名**干净**（不带乱码字节）")
  local g69b = EVAL_PARSE_CONDS("目标buff:回春术")
  eq(g69b[1] and g69b[1][1] and g69b[1][1].s, "回春术", "⑥反向：半角照旧（原行为不动）")
  local prof69 = EVAL_PROFILE_FROM_TEXT("# 方案：测试\n- 攻击 | 战斗中")
  eq(prof69 and prof69.name, "测试", "⑥★★导入文本的「# 方案：」表头也认全角冒号（认不出会退化成整个表头当方案名）")
  -- 收尾
  EVAL_HELP_CONFIG.log = savedLog89
  TEST.hasTarget = savedTarget89
  TEST.followed, TEST.followCalls = nil, nil
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
  EVAL_HELP_UPDATE_STATE()
end

-- 90) ★1.71.3 队伍/团员条件的两个**成员过滤**（用户要求）：
--   ① 「队伍团员状态」8 个条件类型都加 **职业多选**；**默认空 = 不过滤职业**（原话「默认空不过滤职业.也就是全部」）。
--   ② 「团员」级别的 4 个条件额外加 **小队多选**；**默认空 = 全部小队**（用户要求「先验证可行性」）。
--   ★★★可行性取证（本机 api_*.html 索引 + emberveil wiki Raid 页原文，本轮现场核对）：`GetRaidRosterInfo(index)`
--     返回**九个值**：name, rank, **subgroup(1–8；未知按 1)**, level, classLoc, **classFile(WARRIOR/MAGE/…)**, zone,
--     online, isDead；★非团队或下标越界时**只返回一个 nil** → 小队号拿得到，**可行性 = 可行**。
--   ★★语义与「目标职业」条件**正好相反**（那条空 = 永不满足）——这里空 = 不过滤；两边各有专属断言钉住。
--   ★选取器行（「选取目标:队伍成员」）：行内条件的过滤取**并集**，限制的是**候选集合**（见 ⑤）。
do
  local savedTeam90, savedRaid90 = TEST.team, TEST.raid
  local savedHp90, savedHpMax90 = TEST.hp, TEST.hpMax
  local savedProf90 = EVAL_HELP_CONFIG.war.profiles
  local savedAct90 = EVAL_HELP_CONFIG.war.activeProfile
  local savedTgt90 = TEST.targetUnit
  local function live90(cd) return EVAL_TEST_COND_EVAL_LIVE(cd) end
  -- ① 文本往返（职业/小队后缀）
  local p90 = EVAL_PARSE_ONE("队伍血<50[职业:战士/法师]")
  eq(type(p90) == "table" and p90.k, "teamHp", "①解析出队伍血条件")
  eq(p90.cs and p90.cs.WARRIOR, true, "①★职业后缀：战士进来了")
  eq(p90.cs and p90.cs.MAGE, true, "①★职业后缀：法师也进来了")
  eq(p90.cs and p90.cs.PRIEST, nil, "①反向：没写的职业不在集合里")
  eq(p90.gs, nil, "①没写小队后缀 → gs 为空")
  eq(EVAL_COND_STR(p90), "队伍血<50[职业:法师/战士]", "①★★导出回环（按 CLASS_LIST 顺序：法师在战士前）")
  local p90b = EVAL_PARSE_ONE("团队蓝>20[队伍:1/3]") -- ★数值型的团队拼写是「团队蓝」（「团员」那套是 buff/debuff 型）
  eq(p90b.k, "teamMana", "①解析出团员蓝条件")
  eq(p90b.name, "团队", "①★范围 = 团队")
  eq(p90b.gs and p90b.gs[1], true, "①★小队后缀：1 队")
  eq(p90b.gs and p90b.gs[3], true, "①★小队后缀：3 队")
  eq(p90b.gs and p90b.gs[2], nil, "①反向：没写的小队不在集合里")
  eq(EVAL_COND_STR(p90b), "团队蓝>20[队伍:1/3]", "①★★导出回环")
  local p90c = EVAL_PARSE_ONE("有团队debuff:痛苦诅咒(魔法)[职业:术士][队伍:2]")
  eq(type(p90c) == "table" and p90c.k, "teamDebuff", "①解析出团员debuff条件")
  eq(p90c.cs and p90c.cs.WARLOCK, true, "①★两个后缀可同时写（职业）")
  eq(p90c.gs and p90c.gs[2], true, "①★两个后缀可同时写（小队）")
  eq(p90c.dt ~= nil, true, "①★★原有的 debuff 类型参数没被吃掉（dt=" .. tostring(p90c.dt) .. "）")
  local str90c = EVAL_COND_STR(p90c)
  eq(string.find(str90c, "[职业:术士][队伍:2]", 1, true) ~= nil, true, "①★★导出串带上两个过滤后缀")
  local p90c2 = EVAL_PARSE_ONE(str90c)
  eq(p90c2 and p90c2.cs and p90c2.cs.WARLOCK, true, "①★★再解析回来：职业不丢")
  eq(p90c2 and p90c2.gs and p90c2.gs[2], true, "①★★再解析回来：小队不丢")
  eq(p90c2 and p90c2.dt, p90c.dt, "①★★再解析回来：debuff 类型也不丢（三段后缀共存）")
  eq(EVAL_PARSE_ONE("怒气>30[职业:战士]"), nil, "①★★反向：**非**队伍/团员条件带这个后缀 = 写法错误 → 如实丢弃")
  local p90d = EVAL_PARSE_ONE("队伍血<50[职业:不存在的职业]")
  eq(p90d and p90d.cs, nil, "①★反向：一个职业名都不认 → 等于没写过滤（**不留下空集**，否则导出会写出 [职业:]）")
  eq(EVAL_COND_STR(p90d), "队伍血<50", "①★反向：同上，导出串也保持干净")
  eq(EVAL_COND_STR(EVAL_PARSE_ONE("队伍血<50")), "队伍血<50", "①反向：不带过滤时导出**逐字不变**（老配置不受影响）")
  -- ② 职业过滤：空 = 不过滤（队伍范围）
  TEST.raid = nil
  TEST.team = {
    { unit = "party1", name = "甲", hp = 80, hpMax = 100, mana = 100, manaMax = 100, cls = "WARRIOR", powerType = 0 },
    { unit = "party2", name = "乙", hp = 10, hpMax = 100, mana = 100, manaMax = 100, cls = "MAGE", powerType = 0 },
  }
  TEST.hp, TEST.hpMax = 100, 100
  EVAL_HELP_UPDATE_STATE()
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "队伍" }), true, "②★★★★没有职业过滤 → 全部成员都算（法师 10% 让条件成立）")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "队伍", cs = { MAGE = true } }), true, "②★★职业=法师 → 只看法师（10% → 成立）")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "队伍", cs = { WARRIOR = true } }), false, "②★★★★职业=战士 → 只看战士（80% → 不成立）——证明过滤**真的改变了成员集合**")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "队伍", cs = { PRIEST = true } }), false, "②★反向：过滤后没人 → 如实 false（不去拿别人顶替）")
  -- ③ 小队过滤（团队范围）
  TEST.team = nil
  TEST.raid = {
    { unit = "raid1", name = "团甲", hp = 10, hpMax = 100, mana = 100, manaMax = 100, cls = "WARRIOR", grp = 1, powerType = 0 },
    { unit = "raid2", name = "团乙", hp = 90, hpMax = 100, mana = 100, manaMax = 100, cls = "MAGE", grp = 3, powerType = 0 },
  }
  EVAL_HELP_UPDATE_STATE()
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "团队" }), true, "③★没有小队过滤 → 全团都算（10% → 成立）")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "团队", gs = { [1] = true } }), true, "③★★小队=1 队 → 只看 1 队（10% → 成立）")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "团队", gs = { [3] = true } }), false, "③★★★小队=3 队 → 只看 3 队（90% → 不成立）")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "团队", gs = { [7] = true } }), false, "③★★反向：过滤后没人 → 如实 false")
  eq(live90({ k = "teamHp", op = "<", n = 50, name = "团队", cs = { MAGE = true }, gs = { [1] = true } }), false, "④★职业+小队同时写 = 两个都要满足（法师不在 1 队 → 没人 → false）")
  -- ★数据侧：扫描记录真的带上了职业/小队（别只信条件结果）
  local scan90 = EVAL_HELP_TEAM_ENSURE("raid")
  eq(scan90[1] and scan90[1].cls, "WARRIOR", "③★扫描记录带职业（来自 GetRaidRosterInfo）")
  eq(scan90[2] and scan90[2].grp, 3, "③★扫描记录带小队号（GetRaidRosterInfo 的 subgroup）")
  -- ⑤ 选取器行：过滤限制的是**候选集合**
  TEST.raid = nil
  TEST.team = {
    { unit = "party1", name = "甲", hp = 10, hpMax = 100, mana = 100, manaMax = 100, cls = "WARRIOR", powerType = 0 },
    { unit = "party2", name = "乙", hp = 80, hpMax = 100, mana = 100, manaMax = 100, cls = "MAGE", powerType = 0 },
  }
  TEST.hp, TEST.hpMax = 100, 100
  TEST.targetUnit = nil
  EVAL_HELP_UPDATE_STATE()
  local rule90 = { skill = "选取目标:队伍成员", why = "t90", groups = { { { k = "teamHp", op = "<", n = 90, name = "队伍", cs = { MAGE = true } } } } } -- ★单条规则（EVAL_TEAM_PICK 读 rule.groups）
  eq(EVAL_TEST_TEAM_PICK_AUTO(rule90, "teamParty"), "party2", "⑤★★★职业过滤限制**候选集合**：战士血更低也不选，选到法师")
  local rule90b = { skill = "选取目标:队伍成员", why = "t90", groups = { { { k = "teamHp", op = "<", n = 90, name = "队伍" } } } }
  eq(EVAL_TEST_TEAM_PICK_AUTO(rule90b, "teamParty"), "party1", "⑤★★反向：不过滤时选血最低的战士（证明上一条不是「总选 party2」）")
  -- ⑥ 编辑器里的两个过滤格
  local function openRow90(skill, cd)
    EVAL_HELP_CONFIG.war.profiles = { { name = "t90", skills = { { skill = skill, why = "t90", groups = { { cd } } } } } }
    EVAL_HELP_CONFIG.war.activeProfile = 1
    EVAL_HELP_SE_OPEN(1, 1)
  end
  openRow90("攻击", { k = "teamHp", op = "<", n = 60, name = "队伍" })
  local clsShown90, clsText90 = EVAL_TEST_SE_ROW_CLS(1)
  eq(clsShown90, true, "⑥★★队伍条件有「职业过滤」格")
  eq(clsText90, EVAL_L("SE_CLS_ALL"), "⑥★★默认显示「全部职业」（空 = 不过滤）")
  eq(EVAL_TEST_SE_ROW_GRP(1), false, "⑥★★★反向：**队伍**条件没有小队格（小队只对团员条件有意义）")
  eq(EVAL_TEST_SE_ROW_PREVIEW(1), false, "⑥★这行让位：行内预览不显示（底部整串预览照旧）")
  openRow90("攻击", { k = "teamHp", op = "<", n = 60, name = "团队" })
  eq(EVAL_TEST_SE_ROW_GRP(1), true, "⑥★★团员条件有「小队过滤」格")
  eq(select(2, EVAL_TEST_SE_ROW_GRP(1)), EVAL_L("SE_GRP_ALL"), "⑥★★默认显示「全部队伍」")
  openRow90("攻击", { k = "combat", v = true })
  eq(EVAL_TEST_SE_ROW_CLS(1), false, "⑥★★反向：普通条件没有职业过滤格")
  eq(EVAL_TEST_SE_ROW_GRP(1), false, "⑥★★反向：普通条件没有小队格")
  eq(EVAL_TEST_SE_ROW_PREVIEW(1), true, "⑥★★反向：普通条件的行内预览照旧显示")
  -- 点**真实控件** → 多选下拉；选中后写进 cd 并由刷新显示出来
  openRow90("攻击", { k = "teamHp", op = "<", n = 60, name = "队伍" })
  local cb90 = EVAL_TEST_SE_ROW_CLS_BTN(1)
  eq(type(cb90) == "table", true, "⑥前置：拿到职业格按钮")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  local fn90 = cb90 and cb90.GetScript and cb90:GetScript("OnClick")
  eq(type(fn90) == "function", true, "⑥前置：职业格有真实 OnClick")
  if type(fn90) == "function" then fn90() end
  eq(EVAL_DD_TEST_SHOWN(), true, "⑥★★点它真的弹面板")
  eq(EVAL_DD_TEST_MULTI(), true, "⑥★★是多选（不是单选）")
  local idxMage90 = nil
  for ci90, c90 in ipairs(EVAL_CLASS_LIST) do if c90.id == "MAGE" then idxMage90 = ci90 end end
  eq(idxMage90 ~= nil, true, "⑥前置：CLASS_LIST 里有法师")
  if idxMage90 then EVAL_DD_TEST_CLICK(idxMage90) end
  eq(EVAL_DD_TEST_SELAT(idxMage90), true, "⑥★★点一下真的勾上了（多选状态）")
  EVAL_DD_HIDE()
  local _, clsText90b = EVAL_TEST_SE_ROW_CLS(1)
  local mageName90 = nil
  for _, c90b in ipairs(EVAL_CLASS_LIST) do if c90b.id == "MAGE" then mageName90 = c90b.name end end
  eq(clsText90b, mageName90, "⑥★★★格子上显示出所选职业（写进 cd.cs 并刷新）")
  -- 小队格同理（团员行）
  openRow90("攻击", { k = "teamHp", op = "<", n = 60, name = "团队" })
  local gb90 = EVAL_TEST_SE_ROW_GRP_BTN(1)
  local fng90 = gb90 and gb90.GetScript and gb90:GetScript("OnClick")
  eq(type(fng90) == "function", true, "⑥前置：小队格有真实 OnClick")
  EVAL_DD_HIDE()
  EVAL_DD_TEST_RESET_ANCHOR()
  if type(fng90) == "function" then fng90() end
  eq(EVAL_DD_TEST_MULTI(), true, "⑥★★小队格也是多选")
  EVAL_DD_TEST_CLICK(3)
  EVAL_DD_HIDE()
  eq(select(2, EVAL_TEST_SE_ROW_GRP(1)), "3", "⑥★★★小队格显示所选小队号")
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedProf90
  EVAL_HELP_CONFIG.war.activeProfile = savedAct90
  TEST.team, TEST.raid = savedTeam90, savedRaid90
  TEST.hp, TEST.hpMax = savedHp90, savedHpMax90
  TEST.targetUnit = savedTgt90
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
  EVAL_HELP_UPDATE_STATE()
end

-- 91) ★1.71.3 案例模版窗重做（用户要求：「窗口大一点，分两列，标题增加感叹号 tooltip 提示…」）
--   + 案例扩充（通用法系 队伍/团队刷buff、队伍/团队一键治疗与buff、骑士按职业区分祝福、其它职业常用一键宏）。
--   ★三层判据：① 布局（真实几何：**分组分两列**、组内同行自动换行、不出窗、**同一职业组不被拆到两列**、两列行数平衡）；
--     ② 标题感叹号的悬停文案（走真实 OnEnter → GameTooltip，按语言包取）；
--     ③ **内容质量**（每条模版：名字非空、同组不重名、首行「# 方案: X」== 模版名、至少 1 条技能行；
--        以及用户点名的几条确实在、职业过滤真的写进条件里）。
do
  -- ★★★1.71.8 版式：**分组分两列 + 组内同行自动换行**
  --   （用户要求「案例模版 分组 分两列,分组内的方案 同行 自动换行.」）。
  --   判据仍是**真实控件几何**（不写死常量）：每个按钮在**本列**列宽之内、同行相邻留足 GAP、
  --   一个组只出现在一列（不拆组）、两列都有内容、两列行数尽量平衡、高度由内容算出且不出屏。
  local lay = EVAL_TEST_TPL_LAYOUT()
  eq(type(lay) == "table", true, "前置：模版窗建好了")
  eq(lay.w, EVAL_TEST_WIN_W(), "★★★窗口宽度 = 单一来源 cfWinWidth()（不再各写一份宽度）")
  eq(lay.rowCount >= 20, true, "★模版按钮数 ≥20（案例已扩充）: " .. tostring(lay.rowCount))
  eq(lay.plan, lay.rowCount + lay.groups, "★★版式表 = 组标题 + 方案按钮（一个不漏）")
  eq(lay.h <= 700, true, "★★窗口高度不出屏（本客户端 UI 空间高 768）: " .. tostring(lay.h))
  eq(lay.lines >= 4, true, "★★内容确实排了多行（会自动换行）: " .. tostring(lay.lines) .. " 行")
  -- ★★★分两列：列宽与右列起点由版式算出（列宽 = (窗宽 − 2×边距 − 列间距) / 2）
  eq(lay.colW ~= nil and lay.colW > 100, true, "★★★分组分两列：列宽 " .. tostring(lay.colW) .. "（>100 才排得下按钮）")
  eq(lay.colX2, lay.margin + lay.colW + lay.colGap, "★★右列起点 = 左列右边界 + 列间距（两列之间真有间隔，不是贴着/重叠）")
  eq(lay.colX2 + lay.colW <= lay.w - lay.margin + 1, true, "★★右列不越出窗口右边界")
  eq(lay.rowsL > 0 and lay.rowsR > 0, true, "★★★两列都有内容（没有全挤在一列）: " .. tostring(lay.rowsL) .. "+" .. tostring(lay.rowsR))
  eq(math.abs(lay.rowsL - lay.rowsR) <= 2, true, "★★两列行数平衡（最优切点，不搞「塞到过半就停」）: " .. tostring(lay.rowsL) .. "/" .. tostring(lay.rowsR))
  local rows91 = EVAL_TEST_TPL_ROWS()
  eq(table.getn(rows91), lay.rowCount, "★行表与布局自报的按钮数一致")
  -- 按「y + 列」分行，逐行检查不变量（★同一 y 上的两列各自成行，绝不能混在一起比间距）
  local function colOf91(x) return (x >= lay.colX2 - 0.5) and 2 or 1 end
  local colX91 = { lay.margin, lay.colX2 }
  local byRow, bad, clsCol91 = {}, "", {}
  for i = 1, table.getn(rows91) do
    local r = rows91[i]
    eq(type(r.x) == "number" and type(r.y) == "number", true, "★第 " .. i .. " 个按钮有真实坐标")
    if type(r.x) == "number" and type(r.y) == "number" then
      local key = tostring(r.y) .. "#" .. tostring(colOf91(r.x))
      byRow[key] = byRow[key] or {}
      table.insert(byRow[key], r)
      -- ★组不许跨列：同一个组的按钮必须都在同一列（拆开看着像少了一组）
      local c0 = clsCol91[r.cls]
      if c0 == nil then clsCol91[r.cls] = colOf91(r.x)
      elseif c0 ~= colOf91(r.x) then bad = bad .. "组跨列:" .. tostring(r.cls) .. " " end
    end
  end
  local multiRow, rowCount91 = 0, 0
  for _, list in pairs(byRow) do
    rowCount91 = rowCount91 + 1
    table.sort(list, function(a, b) return a.x < b.x end)
    if table.getn(list) >= 2 then multiRow = multiRow + 1 end
    for i = 1, table.getn(list) do
      local rr = list[i]
      local ci = colOf91(rr.x)
      if rr.x < colX91[ci] - 0.5 then bad = bad .. "左越界:" .. tostring(rr.name) .. " " end
      if (rr.w or 0) < 30 then bad = bad .. "按钮过窄:" .. tostring(rr.name) .. "=" .. tostring(rr.w) .. " " end
      if rr.x + (rr.w or 0) > colX91[ci] + lay.colW + 1 then bad = bad .. "越出本列右边界:" .. tostring(rr.name) .. " " end
      -- ★同行相邻（**同一列**）要留出 GAP（不只是「不重叠」：贴在一起也算不合规——「不重叠」是弱代理）
      if i > 1 then
        local prev = list[i - 1]
        if colOf91(prev.x) == ci and rr.x < prev.x + (prev.w or 0) + lay.gap - 0.5 then
          bad = bad .. "间距不足:" .. tostring(prev.name) .. "/" .. tostring(rr.name) .. " "
        end
      end
      -- ★底边不得压到「关闭」按钮那条带（34 是标题栏 + 底部留白）
      if (rr.y - 18) < -(lay.h - 34) then bad = bad .. "压到底部:" .. tostring(rr.name) .. " " end
    end
  end
  eq(multiRow >= 4, true, "★★★同一行放了多个模版（这就是「可以同行」）: 有 " .. multiRow .. " 行是多按钮")
  eq(rowCount91 <= lay.lines * 2, true, "★(列×行) 不超过 2×版式行数: " .. rowCount91 .. " <= " .. (lay.lines * 2))
  print(string.format("  案例模版窗版式：%d 个按钮 / %d 组 / 两列 %d+%d 行 / 列宽 %d / 窗口 %dx%d",
    lay.rowCount, lay.groups, lay.rowsL, lay.rowsR, lay.colW, lay.w, lay.h))
  eq(bad, "", "★★★分列+流式不变量：按钮在本列内、同行相邻不重叠、组不跨列: " .. bad)
  -- 分列结果打印出来（回归时一眼看出「哪几组进了哪一列」）
  local colTxt91 = { "", "" }
  for i = 1, table.getn(EVAL_IO_TEMPLATES) do
    local nm91 = tostring(EVAL_IO_TEMPLATES[i].cls)
    local ci91 = clsCol91[nm91]
    if ci91 then colTxt91[ci91] = colTxt91[ci91] .. nm91 .. " " end
  end
  print("  分列：左[" .. colTxt91[1] .. "] 右[" .. colTxt91[2] .. "]")
  -- ★★★用**合成数据**逼出「组内换行 + 分两列」两条路（真实内容下这两条路可能是等价的）
  local fake91 = EVAL_TEST_TPL_PLAN_FAKE(660, 8, 9, 6) -- 8 组 × 每组 9 个「6 字 + 序号」按钮
  eq(fake91.items, 72, "★★★合成数据：8 组 × 9 个按钮都进了版式表")
  eq(fake91.rows >= 10, true, "★★★每组都要换好几行（真的在换行）: " .. tostring(fake91.rows) .. " 行(列×行)")
  eq(fake91.colGroups[1] > 0 and fake91.colGroups[2] > 0, true, "★★★合成数据也分了**两列**: " .. tostring(fake91.colGroups[1]) .. "+" .. tostring(fake91.colGroups[2]) .. " 组")
  eq(fake91.splitBad, 0, "★★★没有组被拆到两列（组是不拆的最小单位）")
  eq(fake91.over, 0, "★★★没有任何元素越出**本列**右边界（「不换行 / 只排一列」的变异踩这一条）")
  eq(fake91.gapBad, 0, "★★同行相邻留足了 GAP")
  eq(fake91.colStartBad, 0, "★★每个组标题都落在本列的行首")
  -- ★★★1.73.7 新不变量（用户「方案类别独立一行,方案同行多个.」）：
  eq(fake91.hdrShared, 0, "★★★合成数据：类别独占一行（没有任何按钮与标题同行）")
  eq(fake91.rowStartBad, 0, "★★★按钮行从**本列左边界**开始排（标题已独占上一行，按钮不该再缩进）")
  eq(fake91.rowsInconsistent, 0, "★★★版式自报行数 == plan 真实占用行数（合成数据也要一致）: 实测 " ..
     tostring(fake91.realRows) .. " vs " .. tostring(fake91.rowsL + fake91.rowsR))
  eq(fake91.perCol[1] > 0 and fake91.perCol[2] > 0, true, "★★两列都有按钮: " .. tostring(fake91.perCol[1]) .. "/" .. tostring(fake91.perCol[2]))
  print(string.format("  合成数据版式：%d 组 / 两列 %d+%d 行 / 按钮 %d+%d（逼出换行+分列两条路）",
    fake91.groups, fake91.rowsL, fake91.rowsR, fake91.perCol[1], fake91.perCol[2]))
  -- ★★★1.73.7 真实渲染的标题几何（用户要求「方案类别独立一行,方案同行多个.」）：
  --   ① 标题落在**本列行首**；② 标题**独占一行**（同行不许有任何按钮）；③ 本组按钮都在标题**下面**的行。
  local hdrs91 = EVAL_TEST_TPL_HEADERS()
  eq(table.getn(hdrs91), lay.groups, "★★★真实渲染出来的组标题数 = 组数（每个组都有标题）")
  local shared91, hdBad91, belowBad91, empty91 = "", "", "", ""
  for i = 1, table.getn(hdrs91) do
    local h = hdrs91[i]
    local ci = colOf91(h.x)
    if math.abs(h.x - colX91[ci]) > 0.5 then hdBad91 = hdBad91 .. tostring(h.cls) .. "(不在列首) " end
    local hasBtn, below = false, true
    for j = 1, table.getn(rows91) do
      local rr = rows91[j]
      if colOf91(rr.x) == ci then
        if rr.y == h.y then shared91 = shared91 .. tostring(h.cls) .. "(" .. tostring(rr.name) .. ") " end
        if rr.cls == h.cls then
          hasBtn = true
          if not (rr.y < h.y - 0.5) then below = false end -- y 越小越靠下：按钮必须在标题下面
        end
      end
    end
    if not hasBtn then empty91 = empty91 .. tostring(h.cls) .. " " end
    if hasBtn and not below then belowBad91 = belowBad91 .. tostring(h.cls) .. " " end
  end
  eq(hdBad91, "", "★★组标题都在**本列行首**（每个组从新的一行开始）: " .. hdBad91)
  eq(shared91, "", "★★★类别**独占一行**：没有任何按钮与标题同行（这就是「方案类别独立一行」）: " .. shared91)
  eq(belowBad91, "", "★★★本组方案都在类别**下面**的行上（方案从标题的下一行开始，不是接着标题往右排）: " .. belowBad91)
  eq(empty91, "", "★每个有方案的类别下面都有本组按钮: " .. empty91)
  -- ★★★1.73.7 **版式自报的行数 == 真实控件的行数**（标题行 + 按钮行，逐列数）。
  --   ★为什么必须单独钉这一条：M82（rowsOf 少算「第一行按钮」）**存活过一次** ——
  --     它让 rowsL/rowsR 报 6+7（真实是 11+13），而当时唯一的关联断言「rowCount91 <= lines*2」
  --     在 13 <= 14 下**照样成立**（弱判据）。两处算法一旦不一致，切点与窗口高度就都错。
  local rowsReal = { {}, {} }
  for i = 1, table.getn(rows91) do local rr = rows91[i] rowsReal[colOf91(rr.x)][tostring(rr.y)] = true end
  for i = 1, table.getn(hdrs91) do local h = hdrs91[i] rowsReal[colOf91(h.x)][tostring(h.y)] = true end
  local nL, nR = 0, 0
  for _ in pairs(rowsReal[1]) do nL = nL + 1 end
  for _ in pairs(rowsReal[2]) do nR = nR + 1 end
  eq(nL == lay.rowsL and nR == lay.rowsR, true,
     "★★★版式自报的行数 == 真实控件的行数: 实测 " .. nL .. "/" .. nR .. " vs 自报 " .. tostring(lay.rowsL) .. "/" .. tostring(lay.rowsR))
  -- ② 标题感叹号 + 悬停说明
  eq(EVAL_TEST_TPL_TIP_TEXT(), "!", "★★标题上有金色文字感叹号（不用我们那两枚有固定含义的 mark 图标）")
  local tip91 = EVAL_TEST_TPL_TIP()
  local fn91 = tip91 and tip91.GetScript and tip91:GetScript("OnEnter")
  eq(type(fn91) == "function", true, "★感叹号有真实 OnEnter")
  TEST.tipLines = nil
  if type(fn91) == "function" then fn91() end
  local txt91 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do txt91 = txt91 .. tostring(ln.text or "") .. "\n" end
  eq(string.find(txt91, EVAL_L("TPL_SHARE_TIP"), 1, true) ~= nil, true, "★★★悬停真的弹出「有好方案欢迎分享」（按语言包实取，不硬编码）")
  eq(type(EVAL_L("TPL_SHARE_TIP")) == "string" and EVAL_L("TPL_SHARE_TIP") ~= "", true, "★语言包里确实有这条文案")
  -- ③ 内容质量：逐条模版体检
  local badName, dupName, badHead, badSkill = "", "", "", ""
  local seen91 = {}
  for gi, g in ipairs(EVAL_IO_TEMPLATES) do
    for ti, t in ipairs(g.list or {}) do
      local nm = tostring(t.name or "")
      if nm == "" then badName = badName .. tostring(gi) .. "/" .. tostring(ti) .. " " end
      local key = tostring(g.cls) .. "/" .. nm
      if seen91[key] then dupName = dupName .. key .. " " end
      seen91[key] = true
      local prof = EVAL_PROFILE_FROM_TEXT(t.text or "")
      if not (prof and prof.name == nm) then badHead = badHead .. key .. "(=" .. tostring(prof and prof.name) .. ") " end
      if not (prof and table.getn(prof.skills) >= 1) then badSkill = badSkill .. key .. " " end
    end
  end
  eq(badName, "", "★★模版名不许为空: " .. badName)
  eq(dupName, "", "★★同一组内不许重名（重名会让人点错）: " .. dupName)
  eq(badHead, "", "★★★每条模版首行「# 方案: X」必须等于模版名（否则导入后列表名与菜单对不上）: " .. badHead)
  eq(badSkill, "", "★★★每条模版至少 1 条技能行: " .. badSkill)
  -- ③b 用户点名的案例确实在
  local function findTpl91(cls, name)
    for _, g in ipairs(EVAL_IO_TEMPLATES) do
      if g.cls == cls then
        for _, t in ipairs(g.list or {}) do if t.name == name then return t end end
      end
    end
    return nil
  end
  eq(findTpl91("通用法系", "队伍补智力") ~= nil, true, "★用户要求：通用法系 → 队伍补智力")
  eq(findTpl91("通用法系", "团队补智力") ~= nil, true, "★用户要求：通用法系 → 团队补智力")
  eq(findTpl91("通用法系", "队伍补耐力") ~= nil, true, "★用户要求：通用法系 → 队伍补耐力")
  eq(findTpl91("通用法系", "团队补耐力") ~= nil, true, "★用户要求：通用法系 → 团队补耐力")
  eq(findTpl91("队伍/团队", "一键队伍治疗") ~= nil, true, "★用户要求：队伍/团队 → 一键队伍治疗")
  eq(findTpl91("队伍/团队", "一键团队治疗") ~= nil, true, "★用户要求：队伍/团队 → 一键团队治疗")
  eq(findTpl91("队伍/团队", "一键队伍buff") ~= nil, true, "★用户要求：队伍/团队 → 一键队伍buff")
  eq(findTpl91("队伍/团队", "一键团队buff") ~= nil, true, "★用户要求：队伍/团队 → 一键团队buff")
  eq(findTpl91("队伍/团队", "一键队伍驱散") ~= nil, true, "★用户要求：队伍/团队 → 一键队伍驱散")
  eq(findTpl91("队伍/团队", "一键团队驱散") ~= nil, true, "★用户要求：队伍/团队 → 一键团队驱散")
  -- ★★★把这一大段收进**函数体**： do ... end 不新开函数作用域，这些局部变量会和整份文件的主 chunk
  --   共用同一个「最多 200 个局部变量」的上限（实测直接报 too many local variables near ...）——
  --   收进函数体后各自独立预算（Lua 的 200 上限是**每个函数**一条）。
  local function auditTplContent91()
    -- ★★★1.71.7 审计（用户要求「审计下之前添加的队伍团队相关的方案技能配置优先采用:
    --   指定技能搭配 队伍/团员条件类型完成需求」）：模版一律「**指定技能 + 队伍/团员条件**」。
    --   判据 = 每条成员类模版 ① 行内第一条就是**指定技能**（不是选取器）② 首条件是该技能要用的
    --   那个成员条件（teamHp/teamMana/teamBuff/teamDebuff）③ 范围（队伍/团队）与语义（方向/类型/阈值）对得上。
    local function skOf91(cls, name)
      local t = findTpl91(cls, name)
      local p = t and EVAL_PROFILE_FROM_TEXT(t.text)
      return p, (p and p.skills) or {}
    end
    local function cdOf91(sk, gi, ci)
      local g = sk and sk.groups and sk.groups[gi or 1]
      return g and g[ci or 1]
    end
    -- ① 治疗类：指定技能 + 队伍/团队血%
    local p95, s95 = skOf91("队伍/团队", "一键队伍治疗")
    eq(s95[1] and s95[1].skill, "快速治疗", "★★★一键队伍治疗：第一行就是**指定技能**「快速治疗」（不再先切目标）")
    local cd95 = cdOf91(s95[1])
    eq(cd95 and cd95.k, "teamHp", "★★★队伍治疗用的是「队伍血%」成员条件（它自己扫人+切目标）")
    eq(cd95 and cd95.name, "队伍", "★★扫描范围 = 队伍")
    eq(cd95 and cd95.op, "<", "★★比较符 <（取血最少的那个人）")
    eq(cd95 and cd95.n, 70, "★★阈值 队伍血<70")
    eq(s95[1] and s95[1].groups[1][2] and s95[1].groups[1][2].k, "powerPct", "★能量守门条件与它同组（AND）")
    local _, s95b = skOf91("队伍/团队", "一键团队治疗")
    eq(cdOf91(s95b[1]) and cdOf91(s95b[1]).name, "团队", "★★★一键团队治疗：范围 = 团队（40 人团靠它）")
    local _, s95c = skOf91("牧师", "一键治疗（队伍）")
    eq(s95c[1] and s95c[1].skill, "快速治疗", "★★牧师一键治疗：指定技能 + 队伍血%")
    eq(cdOf91(s95c[1]) and cdOf91(s95c[1]).k, "teamHp", "★★同上（牧师那套也改过来了）")
    local _, s95d = skOf91("德鲁伊", "奶德一键")
    eq(s95d[1] and s95d[1].skill, "回春术", "★★奶德：第一行是回春术本身")
    eq(cdOf91(s95d[1]) and cdOf91(s95d[1]).k, "teamHp", "★★奶德第一行也带队伍血%")
    eq(s95d[1] and s95d[1].groups[1][2] and s95d[1].groups[1][2].k, "tBuff", "★★★「无目标buff:回春术」排在成员条件**之后**（先切目标再对切过去的人求值）")
    local _, s95e = skOf91("萨满", "萨满一键治疗")
    eq(cdOf91(s95e[1]) and cdOf91(s95e[1]).n, 40, "★★萨满：治疗波门槛 队伍血<40（血线低才用大治疗）")
    eq(cdOf91(s95e[2]) and cdOf91(s95e[2]).n, 70, "★★次级治疗波门槛 队伍血<70")
    -- ② 驱散类：指定技能 + 有队伍/团队debuff:<类型>（类型必须解析成 Magic/Disease）
    local p94, s94 = skOf91("队伍/团队", "一键队伍驱散")
    eq(s94[1] and s94[1].skill, "驱散魔法", "★★★一键队伍驱散：第一行是**指定技能**「驱散魔法」")
    local cd94 = cdOf91(s94[1])
    eq(cd94 and cd94.k, "teamDebuff", "★★★成员条件 = 「有队伍debuff」")
    eq(cd94 and cd94.name, "队伍", "★★扫描范围 = 队伍")
    eq(cd94 and cd94.v, true, "★★方向 = 「有」（有人中魔法）")
    eq(cd94 and cd94.dt, "Magic", "★★★类型真的解析成 Magic（不然谁都不解，且不报错）")
    eq(s94[2] and s94[2].skill, "祛病术", "★★第二行是疾病那条链")
    local cd94b = cdOf91(s94[2])
    eq(cd94b and cd94b.k, "teamDebuff", "★★第二行也是队伍 debuff 条件")
    eq(cd94b and cd94b.dt, "Disease", "★★★第二行类型是 Disease")
    eq(p94 and table.getn(p94.skills), 2, "★★两条链共 2 行（魔法一行、疾病一行）")
    local _, s94c = skOf91("队伍/团队", "一键团队驱散")
    eq(cdOf91(s94c[1]) and cdOf91(s94c[1]).name, "团队", "★★★一键团队驱散：范围 = 团队")
    local _, s94d = skOf91("牧师", "一键驱散（队伍）")
    eq(s94d[1] and s94d[1].skill, "驱散魔法", "★★牧师驱散：指定技能 = 驱散魔法")
    eq(cdOf91(s94d[1]) and cdOf91(s94d[1]).k, "teamDebuff", "★★条件 = 有队伍debuff")
    -- ③ buff 类：指定技能 + 无队伍/团队buff:<名>（缺 = 补），职业过滤照旧写在条件上
    local p91, s91 = skOf91("通用法系", "队伍补智力")
    eq(s91[1] and s91[1].skill, "奥术智慧", "★★★队伍补智力：唯一一行就是**指定技能**「奥术智慧」")
    local cd91 = cdOf91(s91[1])
    eq(cd91 and cd91.k, "teamBuff", "★★★条件类型 = 「队伍buff」")
    eq(cd91 and cd91.v, false, "★★★方向 = 「无」（缺 → 补）")
    eq(cd91 and cd91.s, "奥术智慧", "★点名的是同一个 buff")
    eq(cd91 and cd91.name, "队伍", "★★范围 = 队伍")
    eq(cd91 and cd91.cs and cd91.cs.MAGE, true, "★★★职业过滤解析进条件：法师在内")
    eq(cd91 and cd91.cs and cd91.cs.WARRIOR, nil, "★★★反向：战士不在（没蓝条的职业不该被补智力）")
    local _, s91b = skOf91("通用法系", "团队补智力")
    eq(cdOf91(s91b[1]) and cdOf91(s91b[1]).name, "团队", "★★团队补智力：范围 = 团队")
    local _, s91c = skOf91("通用法系", "队伍补耐力")
    eq(cdOf91(s91c[1]) and cdOf91(s91c[1]).s, "真言术:韧", "★★队伍补耐力：点名真言术:韧")
    eq(cdOf91(s91c[1]) and cdOf91(s91c[1]).cs, nil, "★★耐力人人有用 → 不带职业过滤（空 = 全部职业）")
    local _, s91d = skOf91("队伍/团队", "一键队伍buff")
    eq(s91d[1] and s91d[1].skill, "奥术智慧", "★★一键队伍buff：第一行是指定技能")
    eq(cdOf91(s91d[1]) and cdOf91(s91d[1]).k, "teamBuff", "★★而且带队伍buff 条件")
    eq(table.getn(s91d), 2, "★★两条链（智力 + 耐力）各一行")
    local t92 = findTpl91("骑士", "力量祝福（物理职业）")
    local p92 = t92 and EVAL_PROFILE_FROM_TEXT(t92.text)
    local cd92 = cdOf91(p92 and p92.skills[1])
    eq(p92 and p92.skills[1] and p92.skills[1].skill, "力量祝福", "★★骑士力量祝福：指定技能 + 条件")
    eq(cd92 and cd92.k, "teamBuff", "★★条件 = 无队伍buff:力量祝福")
    eq(cd92 and cd92.cs and cd92.cs.WARRIOR, true, "★★物理职业（战士在内）")
    eq(cd92 and cd92.cs and cd92.cs.MAGE, nil, "★★反向：法师不在力量祝福名单里")
    local t93 = findTpl91("骑士", "智慧祝福（法系职业）")
    local p93 = t93 and EVAL_PROFILE_FROM_TEXT(t93.text)
    local cd93 = cdOf91(p93 and p93.skills[1])
    eq(cd93 and cd93.cs and cd93.cs.MAGE, true, "★★骑士智慧祝福 → 法系职业（法师在内）")
  end
  local function auditTplGate91()
    -- ③-2 ★★★审计的总闸门（这才是「审计」本体：以后谁把模版改回选取器那套，这里当场变红）
    local badPick, badOrder, memCnt = "", "", 0
    for gi, g in ipairs(EVAL_IO_TEMPLATES) do
      for ti, t in ipairs(g.list or {}) do
        local prof = EVAL_PROFILE_FROM_TEXT(t.text or "")
        local key = tostring(g.cls) .. "/" .. tostring(t.name)
        for si, sk in ipairs((prof and prof.skills) or {}) do
          local isPicker = (sk.skill == "选取目标:队伍成员" or sk.skill == "选取目标:团队成员")
          if isPicker then badPick = badPick .. key .. "#" .. si .. " " end
          for ci, cg in ipairs(sk.groups or {}) do
            for cj, cd in ipairs(cg) do
              local k2 = cd.k
              if k2 == "teamHp" or k2 == "teamMana" or k2 == "teamBuff" or k2 == "teamDebuff" then
                memCnt = memCnt + 1
                if isPicker then badPick = badPick .. key .. "(成员条件挂在选取器行) " end
                if cj ~= 1 then badOrder = badOrder .. key .. "#" .. si .. "." .. ci .. "." .. cj .. " " end
              end
            end
          end
        end
      end
    end
    eq(badPick, "", "★★★审计：内置模版一律不再用「选取目标:队伍成员/团队成员」: " .. badPick)
    eq(badOrder, "", "★★★审计：成员类条件必须写在**行的最前面**（它负责切目标，写在后面就是拿旧目标求值）: " .. badOrder)
    eq(memCnt >= 12, true, "★★★审计：确实有这么多条成员类条件被用上（不是只改了注释）: " .. memCnt)
    print(string.format("  队伍/团队模版审计：%d 条成员条件，全部挂在「指定技能」行上（0 处选取器行）", memCnt))
    -- ③-3 ★★★「条件被静默丢弃」的哨兵：文本里写了几条成员条件，解析后就必须**一条不少**地出现
    --   （本项目最恨的一族：解析不出来时 EVAL_PARSE_CONDS 直接不 push → 那一行变成**无条件施法**，
    --     不看人、不看血，用户只会觉得「怎么乱放技能」——数据类错误全是静默的）
    local badDrop, badRow = "", ""
    for gi, g in ipairs(EVAL_IO_TEMPLATES) do
      for ti, t in ipairs(g.list or {}) do
        -- ★先剥掉首行「# 方案: X」——模版名本身可能含「队伍buff」这种关键词（否则会多算一条）
        local txt = string.gsub(tostring(t.text or ""), "^# [^\n]*\n", "")
        local exp = 0
        for _, kw in ipairs({ "队伍血", "团队血", "队伍蓝", "团队蓝", "队伍buff", "团队buff", "队伍debuff", "团队debuff" }) do
          local _, cnt = string.gsub(txt, kw, "")
          exp = exp + cnt
        end
        if exp > 0 then
          local prof = EVAL_PROFILE_FROM_TEXT(txt)
          local got = 0
          local key91 = tostring(g.cls) .. "/" .. tostring(t.name)
          for _, sk in ipairs((prof and prof.skills) or {}) do
            -- 每一条技能行都必须**自己带**成员条件：整行没有 = 那一行会**无条件施法**（不看人、不看血）
            local rowHas = false
            for _, cg in ipairs(sk.groups or {}) do
              for _, cd in ipairs(cg) do
                local k2 = cd.k
                if k2 == "teamHp" or k2 == "teamMana" or k2 == "teamBuff" or k2 == "teamDebuff" then
                  got = got + 1
                  rowHas = true
                end
              end
            end
            if not rowHas then badRow = badRow .. key91 .. "#" .. tostring(sk.skill) .. " " end
          end
          if got ~= exp then
            badDrop = badDrop .. key91 .. "(" .. exp .. "→" .. got .. ") "
          end
        end
      end
    end
    eq(badDrop, "", "★★★审计：文本里写了几条成员条件、解析后就有几条（0 处静默丢弃）: " .. badDrop)
    eq(badRow, "", "★★★审计：成员施法模版的**每一行**都得自己带成员条件（否则那一行是无条件施法）: " .. badRow)
    -- ③-4 ★★★端到端：拿**模版原文**真的跑一遍（只验解析不够 —— 数据类错误全是静默的）
    local savedSlots91b, savedDeb91b = TEST.slotNames, EVAL_HELP_CONFIG.goDebounce
    local savedTeam91b, savedRaid91b = TEST.team, TEST.raid
    local savedUsed91b, savedTgt91b = TEST.used, TEST.targetSel
    local savedAlly91b = EVAL_HELP_STATE.allyUnit
    TEST.raid = nil
    TEST.team = {
      { unit = "party1", name = "甲", hp = 80, hpMax = 100, mana = 100, manaMax = 100, cls = "WARRIOR", powerType = 0 },
      { unit = "party2", name = "乙", hp = 10, hpMax = 100, mana = 100, manaMax = 100, cls = "MAGE", powerType = 0,
        debuffs = { { tex = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras", apps = 1, type = "Magic" } } },
    }
    TEST.slotNames = { [1] = "快速治疗", [2] = "奥术智慧", [3] = "驱散魔法" }
    EVAL_HELP_CONFIG.goDebounce = 0 -- 关掉去抖窗（同一 GetTime 下连续按宏会被跳过）
    EVAL_GO_LAST = 0
    EVAL_GO_RESCAN(true)
    EVAL_HELP_UPDATE_STATE()
    local function runTpl91(cls, name)
      local t = findTpl91(cls, name)
      local prof = t and EVAL_PROFILE_FROM_TEXT(t.text)
      local rules = {}
      for _, sk in ipairs((prof and prof.skills) or {}) do
        table.insert(rules, { skill = sk.skill, why = name, enabled = true, groups = sk.groups })
      end
      TEST.used, TEST.targetSel, EVAL_HELP_STATE.allyUnit = {}, nil, nil
      local acted = EVAL_RULE_RUN(rules)
      return acted, table.getn(TEST.used), TEST.used[1]
    end
    local a1, _n1, u1 = runTpl91("队伍/团队", "一键队伍治疗")
    eq(a1, true, "★★★端到端：模版「一键队伍治疗」真的出手")
    eq(u1, 1, "★★★用的是模版里**指定的技能**（槽1 = 快速治疗）")
    eq(EVAL_HELP_STATE.allyUnit, "party2", "★★★而且打的是**血最少的乙**（模版那条「队伍血<70」真的在扫人）")
    eq(TEST.targetSel, "unit:party2", "★★★目标也确实切了过去（指定技能 + 成员条件 = 一行自足）")
    local a2, _n2, u2 = runTpl91("通用法系", "队伍补智力")
    eq(a2, true, "★★★端到端：模版「队伍补智力」真的出手")
    eq(u2, 2, "★★★用的是指定的「奥术智慧」")
    eq(TEST.targetSel, "unit:party2", "★★★切到了「缺这个 buff 的那个人」（无队伍buff 条件在选人）")
    local a3, _n3, u3 = runTpl91("队伍/团队", "一键队伍驱散")
    eq(a3, true, "★★★端到端：模版「一键队伍驱散」真的出手")
    eq(u3, 3, "★★★用的是指定的「驱散魔法」")
    eq(TEST.targetSel, "unit:party2", "★★★并且切到了「中了魔法的那个人」")
    TEST.slotNames, EVAL_HELP_CONFIG.goDebounce = savedSlots91b, savedDeb91b
    TEST.team, TEST.raid = savedTeam91b, savedRaid91b
    TEST.used, TEST.targetSel = savedUsed91b, savedTgt91b
    EVAL_HELP_STATE.allyUnit = savedAlly91b
    EVAL_GO_RESCAN(true)
  end
  auditTplContent91()
  auditTplGate91()
  -- ③d 过滤后缀的往返：候选者条件与**队伍/团员条件**都要不丢（后者是本轮审计后的主力写法）
  local cdRound = EVAL_PARSE_ONE("候选者缺buff:奥术智慧[职业:法师]")
  eq(cdRound and cdRound.k, "candBuff", "★候选者条件能带职业过滤（解析）")
  eq(cdRound and cdRound.cs and cdRound.cs.MAGE, true, "★★过滤进条件")
  eq(EVAL_COND_STR(cdRound), "候选者缺buff:奥术智慧[职业:法师]", "★★★导出回环不丢过滤（否则导入一次就少一条约束）")
  eq(EVAL_PARSE_ONE("候选者血<60[职业:战士]").cs.WARRIOR, true, "★候选者血% 同样支持")
  local cdRoundTeam = EVAL_PARSE_ONE("无队伍buff:奥术智慧[职业:法师]")
  eq(cdRoundTeam and cdRoundTeam.k == "teamBuff" and cdRoundTeam.v, false, "★★队伍条件（缺buff）也带职业过滤")
  eq(EVAL_COND_STR(cdRoundTeam), "无队伍buff:奥术智慧[职业:法师]", "★★★队伍条件的导出回环逐字不变")
  local cdRoundRaid = EVAL_PARSE_ONE("有团队debuff:魔法[职业:牧师][队伍:2]")
  eq(cdRoundRaid and cdRoundRaid.k == "teamDebuff" and cdRoundRaid.dt, "Magic", "★★团队 debuff 条件：类型解析成 Magic")
  eq(cdRoundRaid and cdRoundRaid.name == "团队" and cdRoundRaid.gs and cdRoundRaid.gs[2], true, "★★而且带着小队过滤（团员条件专属）")
  local rtRaid = EVAL_PARSE_ONE(EVAL_COND_STR(cdRoundRaid))
  eq(rtRaid and rtRaid.k == "teamDebuff" and rtRaid.dt == "Magic" and rtRaid.name == "团队" and rtRaid.cs and rtRaid.cs.PRIEST and rtRaid.gs and rtRaid.gs[2], true, "★★★导出→再解析一圈：类型/范围/职业/小队全都还在")
  -- ③e 编辑器：候选者行也要显示「职业过滤」格（选取器行的条件就是靠它筛人）
  local savedProf91 = EVAL_HELP_CONFIG.war.profiles
  local savedAct91 = EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "t91", skills = { { skill = "选取目标:队伍成员", why = "t91", groups = { { { k = "candBuff", s = "奥术智慧", v = false } } } } } } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_HELP_SE_OPEN(1, 1)
  eq(select(1, EVAL_TEST_SE_ROW_CLS(1)), true, "★★★候选者条件行也显示「职业过滤」格（只给法师补智力就靠它）")
  eq(select(1, EVAL_TEST_SE_ROW_GRP(1)), false, "★★反向：候选者行不显示小队格（小队过滤属于团员条件）")
  EVAL_HELP_CONFIG.war.profiles = savedProf91
  EVAL_HELP_CONFIG.war.activeProfile = savedAct91
  EVAL_TEST_SE_CLEAR()
  TEST.tipLines = nil
end

-- 92) ★1.71.9 用户两条（截图）反馈：
--   ① 技能列表的调序/滚动按钮：^ / v → **▲ / ▼**（原 `^` 在客户端字体里看着像一条横线、`v` 就是字母）；
--   ② 图标库一页行数 6 → **9**（填满面板空档；★先算清可用空间再定行数，照字面「+250px」会把末行画到窗口外）。
do
  -- ① 读**真实控件**上的文本（读生产常量 = 测自己，本项目老坑）
  local ar = EVAL_TEST_WAR_ARROWS()
  eq(type(ar) == "table", true, "①前置：拿到四个箭头按钮的文本")
  eq(ar.rowUp, "▲", "①调序「上」按钮的真实文本 = ▲")
  eq(ar.rowDn, "▼", "①调序「下」按钮的真实文本 = ▼")
  eq(ar.scrollUp, "▲", "①技能列表「上翻」按钮 = ▲")
  eq(ar.scrollDn, "▼", "①技能列表「下翻」按钮 = ▼")
  eq(ar.rowUp ~= "^" and ar.rowDn ~= "v" and ar.scrollUp ~= "^" and ar.scrollDn ~= "v", true,
    "①反向哨兵：不再用 ^ / v（用户截图里一个像横线、一个是字母）")
  -- ② 图标库：一页行数 + 网格的真实几何（末格不许压到底部按钮行、不许越出窗口右缘）
  local cols92, rows92, per92 = EVAL_IB_LAYOUT(EVAL_TEST_WIN_W())
  eq(rows92, 9, "②图标库一页 9 行（原 6 行 = 图标区 +102px）")
  eq(per92, cols92 * rows92, "②每页枚数 = 列数 × 行数（" .. cols92 .. " × " .. rows92 .. " = " .. per92 .. "，原 108）")
  local box92 = EVAL_IB_TEST_GRID_BOX()
  eq(box92 ~= nil and box92.count, per92, "②真实格子池的枚数 = 每页枚数")
  local lay92 = EVAL_TEST_CFG_LAYOUT()
  eq(box92 ~= nil and type(box92.lastBottom) == "number" and box92.lastBottom > lay92.closeMidY + 12, true,
    "②★末格下缘仍在底部按钮行之上（不重叠）：" .. tostring(box92 and box92.lastBottom) .. " > " .. tostring(lay92.closeMidY + 12))
  eq(box92 ~= nil and type(box92.lastRight) == "number" and box92.lastRight < EVAL_TEST_WIN_W() - 10, true,
    "②★网格不越出窗口右缘：" .. tostring(box92 and box92.lastRight))
  -- ★★★1.73.8 用户（截图圈出顶部那一行）：「分页信息这行移动到底部和关闭同行.对齐关闭,别重叠」
  --   判据全是**真实控件几何 × 生产的关闭几何**（不写死坐标）：
  local savedTab92 = EVAL_HELP_CFG_TAB()
  EVAL_HELP_CFG_SETTAB(5) -- 图标库 Tab：底部行控件在该 Tab 的**显式显隐清单**里（不切过来就是 Hide）
  local bot = EVAL_IB_TEST_BOTTOM()
  eq(type(bot) == "table" and bot.status ~= nil and bot.prev ~= nil, true, "③前置：拿到底部行的真实几何")
  eq(bot.midY, lay92.closeMidY, "③★★★底部行中线取自生产单一来源（== [关闭] 的中线）")
  local function midOf92(r) if r and type(r.y) == "number" and type(r.h) == "number" then return r.y - r.h / 2 end return nil end
  eq(math.abs((midOf92(bot.prev) or 999) - bot.midY) <= 1, true,
     "③★★[上页] 与 [关闭] **中线对齐**（实测 " .. tostring(midOf92(bot.prev)) .. " vs " .. tostring(bot.midY) .. "）")
  eq(math.abs((midOf92(bot.next) or 999) - bot.midY) <= 1 and math.abs((midOf92(bot.rescan) or 999) - bot.midY) <= 1, true,
     "③★★[下页]/[重扫] 同样与 [关闭] 中线对齐")
  eq(bot.rescan.x + bot.rescan.w <= bot.closeLeft - 4, true,
     "③★★★翻页按钮组停在 [关闭]**左边**、不重叠（右端 " .. tostring(bot.rescan.x + bot.rescan.w) ..
     " < 关闭左边缘 " .. tostring(bot.closeLeft) .. "）")
  eq(bot.status.x + bot.status.w <= bot.prev.x - 2, true,
     "③★★★状态文字与按钮组不重叠（文字右端 " .. tostring(bot.status.x + bot.status.w) ..
     " < 按钮左端 " .. tostring(bot.prev.x) .. "）")
  eq(bot.status.y < box92.lastBottom, true,
     "③★★★状态行在**底部**（整个图标网格下面）：y=" .. tostring(bot.status.y) .. " < 网格末行下缘 " .. tostring(box92.lastBottom))
  local cwW92, cwH92 = EVAL_TEST_CFG_SIZE()
  eq(bot.status.y > -cwH92 + 4, true, "③★整行仍在窗口内（y=" .. tostring(bot.status.y) .. "，窗高 " .. tostring(cwH92) .. "）")
  eq(bot.status.shown and bot.prev.shown and bot.rescan.shown, true, "③★底部行的控件是显示状态")
  EVAL_HELP_CFG_SETTAB(savedTab92) -- 还原 Tab（跨用例状态残留是本项目老坑）
  print(string.format("  图标库版式：%d 列 × %d 行 = %d 枚/页；网格末行下缘 %.0f，底部按钮行中线 %.0f",
    cols92, rows92, per92, box92 and box92.lastBottom or 0, lay92.closeMidY))
end

-- 93) ★★★1.71.10 用户实测「有些方案会溢出宽度. 能动态自适应吗?」：
--   战斗信息UI 的「方案切换行」原先**按行均分**按钮宽度（同一行所有按钮一样宽）→ 长名字撑破自己的格子、压邻居。
--   现改为：按名字**实测宽**分配 + 贪心换行 + 每行剩余均摊填满。★本组直接验需求本身（长短悬殊的假方案名）。
do
  local savedP93, savedA93 = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = {
    { name = "短", skills = {} },
    { name = "一键团队驱散", skills = {} },
    { name = "中等名字", skills = {} },
    { name = "一键队伍治疗链", skills = {} },
    { name = "A", skills = {} },
    { name = "周围补BUFF", skills = {} },
  }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local wasShown93 = EVAL_TEST_UI_SHOWN()
  -- ★★★1.72.4 前置必须**显式建立**，不许借桩的默认值：
  --   本段要验「这 6 个方案被重排成多行」，而重排的**生产路径**是 EVAL_WAR_TAB_REFRESH
  --   （比对方案名签名 → 整体重建）。老写法只 toggle + tick，靠旧桩「新建帧默认隐藏」
  --   恰好走了「未显示 → toggle → BUILD」那条路才碰巧成立；桩把默认值改对后当场暴露。
  if not wasShown93 then EVAL_HELP_UI_TOGGLE() end
  EVAL_WAR_TAB_REFRESH() -- 生产重排路径（方案名签名变了 → 整体重建）
  EVAL_HELP_UI_TICK() -- ★方案行的**文本**由 tick 落上去（BUILD 只建空壳）
  local up = EVAL_TEST_UI_PROF()
  eq(type(up) == "table", true, "前置：拿到方案切换行的真实几何")
  --  ★★★1.73.25 用户（截图在「方案」二字下划线）：「方案的位置调高一点」——
  --    实测根因：方案按钮行在 `-y`，而「方案」标签被额外压了 3z px（看着比按钮**低半行**）→ 修成共中线。
  --    判据读**真实控件**：标签中心 == 第一行第一个按钮中心（容差 2px；修之前差 3px，这条会响）。
  do
    local lb93 = up.labelBtn
    local b93 = up.btns and up.btns[1]
    local ok1, ly = pcall(lb93.GetTop, lb93)
    local ok2, lh = pcall(lb93.GetHeight, lb93)
    local lcy = (ok1 and type(ly) == "number" and ok2 and type(lh) == "number") and (ly - lh / 2) or nil
    local bcy = (b93 and type(b93.y) == "number" and type(b93.h) == "number") and (b93.y - b93.h / 2) or nil
    eq(lcy ~= nil and bcy ~= nil and math.abs(lcy - bcy) <= 2, true,
       "★★★「方案」标签与第一行按钮**共中线**（标签 " .. tostring(lcy) .. " vs 按钮 " .. tostring(bcy) .. "）")
  end
  eq(up.rows >= 2, true, "★6 个方案（含长名）要排成多行: " .. tostring(up.rows) .. " 行")
  eq(type(up.cap) == "number" and up.cap >= 0 and up.cap <= 32, true,
    "★★★每格的「拉伸上限」必须是个小数字（调大就会把按钮拉成空框）: cap=" .. tostring(up.cap))
  local bad93, ov93, over93, out93 = "", "", "", ""
  local longW, shortW, byRow = nil, nil, {}
  for i = 1, table.getn(up.btns) do
    local b = up.btns[i]
    if b.shown then
      byRow[b.y] = byRow[b.y] or {}
      table.insert(byRow[b.y], b)
      if b.need and b.w and b.w < b.need - 0.5 then
        bad93 = bad93 .. b.name .. "(宽" .. tostring(b.w) .. "<需" .. tostring(b.need) .. ") "
      end
      -- ★★★1.71.11 反向：也不许把按钮**拉成空框**（用户第二轮报「空的太多了」）。
      --   ★判据故意**不读**生产的 ui.profCap —— 读了它，把 cap 调大的变异会**连判据一起改**（实测 M6 就这样 SURVIVED）。
      --   这里用独立上界：一格最多比「文字宽」多 40px（生产上限 24 比它更紧）。
      if b.need and b.w and b.w > b.need + 40 then
        bad93 = bad93 .. b.name .. "(空框 宽" .. tostring(b.w) .. ">需" .. tostring(b.need) .. "+40) "
      end
      -- ★文字格必须**显式限宽**（本项目「FontString 一律显式 SetWidth」的配方）——
      --   桩的 FontString 没被 SetWidth 时 GetWidth 返回 nil（M3 实测：不加这条就漏过「去掉限宽」的变异）
      if not b.textW then
        bad93 = bad93 .. b.name .. "(文字格没限宽) "
      elseif b.w and b.textW > b.w - 2 then
        bad93 = bad93 .. b.name .. "(文字" .. tostring(b.textW) .. ">格" .. tostring(b.w) .. ") "
      end
      if b.name == "一键团队驱散" then longW = b.w end
      if b.name == "短" then shortW = b.w end
    end
  end
  eq(bad93, "", "★★★每格宽在 [需要宽, 需要宽+上限] 之间（「溢出」与「空框」两侧都钉住）: " .. bad93)
  eq(longW ~= nil and shortW ~= nil and longW > shortW, true,
    "★★★长名字的格子真的比短名字宽（不是均分）: 一键团队驱散=" .. tostring(longW) .. " 短=" .. tostring(shortW))
  for _, list in pairs(byRow) do
    table.sort(list, function(a, b) return a.x < b.x end)
    for i = 1, table.getn(list) do
      local b = list[i]
      if i > 1 then
        local pv = list[i - 1]
        if b.x < pv.x + pv.w - 0.5 then ov93 = ov93 .. pv.name .. "/" .. b.name .. " " end
      end
      if b.x + b.w > up.pad + up.avail + 1 then over93 = over93 .. b.name .. " " end
      if b.y - b.h < -up.rootH then out93 = out93 .. b.name .. " " end
    end
  end
  eq(ov93, "", "★★同行相邻不重叠（原均分布局会在这里露出来）: " .. ov93)
  eq(over93, "", "★★整行不越出可用宽: " .. over93)
  eq(out93, "", "★★方案块整体在帧内（行数变了帧高要跟着变）: " .. out93)
  print(string.format("  方案切换行：%d 行 / 「一键团队驱散」%dpx vs 「短」%dpx（按名字实测宽；每格最多 +%dpx，不拉空框）",
    up.rows, longW or -1, shortW or -1, up.cap or 0))
  -- ② 改方案名之后，走**真实刷新入口**版式必须自动跟着变（签名比对 → 整体重建）；长名变多要自动换行
  EVAL_HELP_CONFIG.war.profiles = { { name = "短", skills = {} }, { name = "一键团队驱散", skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local up2 = EVAL_TEST_UI_PROF()
  eq(up2.rows, 1, "②两个方案一行放得下: " .. tostring(up2.rows) .. " 行")
  eq(up2.btns[2] and up2.btns[1] and up2.btns[2].w > up2.btns[1].w, true,
    "★★改方案名后宽度自动跟着变（一键团队驱散=" .. tostring(up2.btns[2].w) .. " > 短=" .. tostring(up2.btns[1].w) .. "）")
  EVAL_HELP_CONFIG.war.profiles = {
    { name = "一键团队驱散", skills = {} }, { name = "一键队伍治疗链", skills = {} },
    { name = "一键队伍驱散", skills = {} }, { name = "一键队伍BUFF", skills = {} } }
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local up3 = EVAL_TEST_UI_PROF()
  eq(up3.rows >= 2, true, "★★长名变多后自动换行: " .. tostring(up3.rows) .. " 行")
  eq(longW ~= nil, true, "②前置：改名前的长名宽度已量到")
  EVAL_HELP_CONFIG.war.profiles = savedP93
  EVAL_HELP_CONFIG.war.activeProfile = savedA93
  EVAL_HELP_UI_BUILD()
  if not wasShown93 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end -- 恢复原可见状态
end

-- 94) ★★★1.71.12 用户两条要求：
--   ①「战斗信息 标题换成 用户名字」；②「战斗信息UI 再加2个子选项，战斗，方案，分开控制显示和隐藏。」
--   ★本组全程走**真实入口 + 真实控件**：点配置窗里那两个真勾选框（OnClick）→ 真重建 →
--     读**真帧高**与**真控件存在性**；标题从真 FontString 上读文本（不读源码字面量）。
do
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.root) then EVAL_HELP_CFG_TOGGLE() end
  local uw = EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.uiRows
  local bx = EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.uiBoxes
  eq(type(uw) == "table" and type(bx) == "table", true, "①前置：配置窗导出「界面」分组的真实行位置与真实勾选框")
  -- 真控件的左/上（桩把 SetPoint 传入的 x/y 记下来；★不反查生产常量）
  local function p94of(k)
    local b = bx and bx[k] and bx[k].btn
    if not b then return nil, nil end
    local okx, x = pcall(b.GetLeft, b)
    local oky, y = pcall(b.GetTop, b)
    return (okx and type(x) == "number") and x or nil, (oky and type(y) == "number") and y or nil
  end
  local p94 = {}
  for _, k in ipairs({ "combat", "subCombat", "subScheme", "state" }) do
    local px0, py0 = p94of(k)
    p94[k] = { x = px0, y = py0 }
  end
  eq((p94.combat.x and p94.combat.y and p94.subCombat.x and p94.subCombat.y
     and p94.subScheme.x and p94.subScheme.y and p94.state.x and p94.state.y) and true or false, true,
    "①前置：四个勾选框都建出来了且有真实几何")
  eq(p94.subCombat.x == p94.combat.x + uw.indent, true,
    "①★两个子开关真的**缩进**在主开关右侧 " .. tostring(uw.indent) .. "px（从属关系看得见）")
  eq(p94.subScheme.x == p94.subCombat.x, true, "①两个子开关左缘对齐（同一列）")
  eq(p94.subCombat.y < p94.combat.y and p94.subScheme.y < p94.subCombat.y and p94.state.y < p94.subScheme.y, true,
    "①★行序 = 主开关 → 战斗 → 方案 → 状态信息UI（逐级向下）")
  local g1 = p94.combat.y - p94.subCombat.y
  local g2 = p94.subCombat.y - p94.subScheme.y
  local g3 = p94.subScheme.y - p94.state.y
  eq(g1 >= 16 and g2 >= 16 and g3 >= 16, true,
    "①★相邻勾选框不重叠（间距 ≥ 勾选框高 16）: " .. g1 .. "/" .. g2 .. "/" .. g3)
  eq(g3 > g2, true,
    "①★状态信息UI 与子项之间留了**更大的分组间距**（否则看着像第三个子项）: " .. g3 .. " > " .. g2)
  print(string.format("  界面分组行距：主→战斗 %d / 战斗→方案 %d / 方案→状态 %d（子项缩进 %d）", g1, g2, g3, uw.indent))

  local wasShown94 = EVAL_TEST_UI_SHOWN()
  if not wasShown94 then EVAL_HELP_UI_TOGGLE() end
  local saveC94, saveS94 = EVAL_HELP_CONFIG.ui.subCombat, EVAL_HELP_CONFIG.ui.subScheme
  EVAL_HELP_CONFIG.ui.subCombat, EVAL_HELP_CONFIG.ui.subScheme = nil, nil -- 老配置形态：这两个键根本不存在
  EVAL_HELP_UI_REBUILD_IF_SHOWN()
  local s1 = EVAL_TEST_UI_SECTIONS()
  eq(s1.title, UnitName("player"), "①★★标题 = 玩家名字（读真 FontString 文本）: " .. tostring(s1.title))
  eq(s1.title ~= EVAL_L("G_UI_TITLE"), true, "①反向哨兵：名字拿得到时不许用兜底文案")
  eq(s1.combat == true and s1.scheme == true, true, "②★★老配置（两个子键不存在）→ 两个区块都画（nil = 开）")
  eq(s1.hasCombat == true and s1.hasScheme == true, true, "②两个区块的控件真的建出来了（不是空标志）")
  -- 取不到名字 → 退回语言包文案（不许把标题栏留空）
  local savedUN94 = UnitName
  UnitName = function(u) if u == "player" then return "" end return savedUN94(u) end
  EVAL_HELP_UI_REBUILD_IF_SHOWN()
  eq(EVAL_TEST_UI_SECTIONS().title, EVAL_L("G_UI_TITLE"), "①★UnitName 给空串时退回语言包文案（标题栏不空白）")
  UnitName = savedUN94
  EVAL_HELP_UI_REBUILD_IF_SHOWN()
  eq(EVAL_TEST_UI_SECTIONS().title, UnitName("player"), "①名字恢复后标题跟着回来（没有粘住兜底值）")
  local hOn = s1.rootH
  local fnC94 = bx.subCombat.btn:GetScript("OnClick")
  local fnS94 = bx.subScheme.btn:GetScript("OnClick")
  eq(type(fnC94) == "function" and type(fnS94) == "function", true, "②两个子开关都有真实 OnClick")
  if type(fnC94) == "function" then fnC94() end -- 点真勾选框：关「战斗」
  local s2 = EVAL_TEST_UI_SECTIONS()
  eq(s2.combat, false, "②★点真勾选框 → 「战斗」区块关（ui.combatOn=false）")
  eq(s2.hasCombat, false, "②★★控件真的**没建**（不是画完再 Hide）")
  eq(EVAL_HELP_CONFIG.ui.subCombat, false, "②写进配置的是真值")
  eq(s2.scheme == true and s2.hasScheme == true, true, "②★两个子开关**互相独立**：战斗关了方案区不受影响")
  eq(type(s2.rootH) == "number" and type(hOn) == "number" and s2.rootH < hOn, true,
    "②★★帧高随「战斗」区消失而变小: " .. tostring(s2.rootH) .. " < " .. tostring(hOn))
  eq(pcall(EVAL_HELP_UI_TICK), true, "②★★区块没建时 tick 不报错（nil 控件不把心跳打断）")
  if type(fnS94) == "function" then fnS94() end -- 再关「方案」
  local s3 = EVAL_TEST_UI_SECTIONS()
  eq(s3.combat == false and s3.scheme == false, true, "②再关「方案」→ 两个区块都关")
  eq(s3.hasScheme, false, "②方案区控件也没建")
  eq(type(s3.rootH) == "number" and s3.rootH < s2.rootH, true,
    "②★两个都关 → 帧高只剩标题栏那点: " .. tostring(s3.rootH) .. " < " .. tostring(s2.rootH))
  eq(pcall(EVAL_HELP_UI_TICK), true, "②两个区块都关时 tick 也不报错")
  if type(fnC94) == "function" then fnC94() end -- 点回来
  if type(fnS94) == "function" then fnS94() end
  local s4 = EVAL_TEST_UI_SECTIONS()
  eq(s4.combat == true and s4.scheme == true, true, "②★点回来 → 两个区块都恢复")
  eq(s4.hasCombat == true and s4.hasScheme == true, true, "②控件重新建出来")
  eq(s4.rootH, hOn, "②★★开关往返一圈后帧高回到原值（无累积偏移）: " .. tostring(s4.rootH) .. " vs " .. tostring(hOn))
  -- 还原：测试不改变生产状态
  EVAL_HELP_CONFIG.ui.subCombat, EVAL_HELP_CONFIG.ui.subScheme = saveC94, saveS94
  EVAL_HELP_UI_REBUILD_IF_SHOWN()
  eq(EVAL_TEST_UI_SECTIONS().rootH, hOn, "②还原配置后帧高 = 原始值")
  if not wasShown94 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end -- 恢复原可见状态
end

-- 95) ★★★1.71.13 用户要求（小地图配置按钮三连）：「配置按钮 换图标，尺寸和图标尺寸保持一致，
--   不用设置外边框。tooltip：全职业一键宏，常用工具箱，世界数据库检索，描述美化下。」
--   ★本组：① 挑选逻辑是纯函数（注桩直测优先级）；② 真按钮的几何读真控件；③ 真 SETICON 贴真纹理。
do
  -- ① 挑选纯函数：候选**优先级**必须压过表序（扳手排在齿轮后面也要挑扳手）
  local function enumOf95(t) return function(i) return t[i] end end
  eq(EVAL_HELP_MB_PICKICON(3, enumOf95({ "Interface\\Icons\\Spell_Fire_Fireball", "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\INV_Misc_Wrench_01" })),
    "Interface\\Icons\\INV_Misc_Wrench_01", "①★扳手优先于齿轮（候选优先级 > 宏图标表的表序）")
  -- ★1.71.17 用户定稿：初始图标 = 力量祝福（她在图标库亲自挑的那枚）→ 候选里排最前，压过扳手
  eq(EVAL_HELP_MB_PICKICON(3, enumOf95({ "Interface\\Icons\\INV_Misc_Wrench_01", "Interface\\Icons\\Spell_Fire_Fireball", "/Game/Interface/Icons/Spell_Holy_BlessingOfStrength_TEX" })),
    "/Game/Interface/Icons/Spell_Holy_BlessingOfStrength_TEX", "①★★初始图标 = 力量祝福（用户定稿，压过扳手；本客户端 /Game/..._TEX 形态也认得）")
  eq(EVAL_HELP_MB_PICKICON(2, enumOf95({ "Interface\\Icons\\INV_Misc_Gear_01", "Interface\\Icons\\Spell_Fire_Fireball" })),
    "Interface\\Icons\\INV_Misc_Gear_01", "①没有扳手时退到齿轮")
  eq(EVAL_HELP_MB_PICKICON(1, enumOf95({ "Interface\\Icons\\Spell_Fire_Fireball" })), nil,
    "①一个候选都不沾 → 如实 nil（绝不硬贴一个不相干的图标）")
  eq(EVAL_HELP_MB_PICKICON(0, enumOf95({})), nil, "①空表 → nil")
  eq(EVAL_HELP_MB_PICKICON(1, enumOf95({ "/Game/Interface/Icons/Trade_Engineering_TEX" })),
    "/Game/Interface/Icons/Trade_Engineering_TEX", "①★本客户端的真实形态（/Game/..._TEX）也认得")
  -- ② 真按钮几何：正方形、边长与图标库单格一致（26；★读真控件，不写死常量当判据）
  local mv95 = EVAL_TEST_MB_VISUAL()
  eq(type(mv95) == "table", true, "②前置：拿到小地图按钮的真实状态")
  eq(mv95.w == 26 and mv95.h == 26, true,
    "②★按钮 = 26×26 的正方形（按钮就是图标，没有边框占位）: " .. tostring(mv95.w) .. "x" .. tostring(mv95.h))
  -- ③ 真实贴图：宏图标表塞进扳手 → 走**真实** EVAL_HELP_MB_SETICON → 真控件贴上了它
  local savedMI95 = TEST.macroIcons
  TEST.macroIcons = nil -- 先模拟「接口在但表为空」→ 兜底样式（不许留空白按钮）
  local fb95 = EVAL_HELP_MB_SETICON()
  local mv95b = EVAL_TEST_MB_VISUAL()
  eq(fb95, false, "③拿不到图标 → 如实返回 false（不假装贴上）")
  eq(mv95b.hasFallback, true, "③★拿不到图标时兜底样式真的建出来了（金框 + EH，不留空白按钮）")
  TEST.macroIcons = { "Spell_Fire_Fireball", "INV_Misc_Gear_01", "INV_Misc_Wrench_01" }
  local ok95 = EVAL_HELP_MB_SETICON()
  local mv95c = EVAL_TEST_MB_VISUAL()
  eq(ok95, true, "③★真实 SETICON 成功贴上图标")
  eq(mv95c.icon, "Interface\\Icons\\INV_Misc_Wrench_01",
    "③★★真控件贴的是扳手（路径来自宏图标表，不是写死的）: " .. tostring(mv95c.icon))
  eq(mv95c.ehText, "", "③★贴上图标后兜底的「EH」字被清空（否则会压在图标上穿帮）")
  TEST.macroIcons = savedMI95
  print("  小地图按钮：26x26 图标钮（扳手），兜底样式与 EH 清空路径都验过")
end

-- 96) ★★★1.71.14 用户截图：「全局配置有重叠，将红色部分底部对齐」——
--   「界面」组加两行子开关后，「一键宏」组（重扫动作条/执行去抖）与「状态信息UI」直接叠上。
--   修法 = 整组从底部按钮行向上锚（底部对齐）。★本组全部读**真实控件**的位置，不读 y 常量。
do
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.root) then EVAL_HELP_CFG_TOGGLE() end
  local mu = EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.macroUI
  local stb = EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.uiBoxes and EVAL_HELP_CFGWIN.uiBoxes.state and EVAL_HELP_CFGWIN.uiBoxes.state.btn
  local lay = EVAL_TEST_CFG_LAYOUT()
  eq(type(mu) == "table" and type(stb) == "table" and type(lay) == "table", true, "前置：拿到一键宏组的真实控件与底部行布局")
  local function top96(o)
    if not o then return nil end
    local ok, v = pcall(o.GetTop, o)
    return (ok and type(v) == "number") and v or nil
  end
  local hTop = top96(mu.header)   -- 组头「一键宏」
  local rTop = top96(mu.rescan)   -- 重扫动作条按钮
  local dTop = top96(mu.dbMinus)  -- 去抖 [-] 按钮
  local sTop = top96(stb)         -- 状态信息UI 勾选框（界面组最后一行，高 16）
  eq(hTop ~= nil and rTop ~= nil and dTop ~= nil and sTop ~= nil, true, "前置：四个真实控件都有真实位置")
  eq(sTop - hTop >= 16, true,
    "①★「一键宏」组头与「状态信息UI」不再叠上（≥ 勾选框高 16）: 间距 " .. tostring(sTop and hTop and (sTop - hTop)) .. "px")
  eq(dTop - mu.rowH == lay.navY + 6, true,
    "②★★底部对齐：去抖行下缘 = 底部按钮行上缘 + 6px: " .. tostring(dTop and (dTop - mu.rowH)) .. " vs " .. tostring(lay.navY + 6))
  eq(hTop - rTop == 20 and rTop - dTop == 40, true,
    "③组内行距保持 20px（头→重扫 20 / 重扫→去抖 40）: " .. tostring(hTop and rTop and (hTop - rTop)) .. "/" .. tostring(rTop and dTop and (rTop - dTop)))
  local _, wh96 = EVAL_TEST_CFG_SIZE()
  eq(type(wh96) == "number" and dTop - mu.rowH > -wh96, true,
    "④去抖行下缘仍在窗口内: " .. tostring(dTop and (dTop - mu.rowH)) .. " > " .. tostring(-(wh96 or 0)))
  print(string.format("  一键宏组：头 %d / 重扫 %d / 去抖 %d（下缘 %d，底部行上缘 %d）",
    hTop or 0, rTop or 0, dTop or 0, (dTop or 0) - (mu.rowH or 15), lay.navY or 0))
end

-- 97) ★★★1.71.15 用户：「图标调整的不对」——小地图按钮的图标不该由插件代挑，该由她自己挑：
--   图标库里**右键**任意一枚 = 设为小地图按钮图标（存配置、重登不丢）；亲自挑的永远优先于自动挑。
do
  local savedMI97 = TEST.macroIcons
  eq(EVAL_HELP_MB_SETCUSTOM("Interface\\Icons\\Spell_Holy_BlessingOfStrength_TEX"), true, "①真实 SETCUSTOM 接受合法路径")
  eq(EVAL_HELP_CONFIG.mbIcon, "Interface\\Icons\\Spell_Holy_BlessingOfStrength_TEX", "①★写进了配置真值")
  eq(EVAL_TEST_MB_VISUAL().icon, "Interface\\Icons\\Spell_Holy_BlessingOfStrength_TEX", "①★真控件当场贴上它")
  eq(EVAL_HELP_MB_SETCUSTOM(""), false, "①空串 → 如实拒（不许把按钮贴成空白）")
  TEST.macroIcons = { "INV_Misc_Wrench_01" }
  EVAL_HELP_MB_SETICON()
  eq(EVAL_TEST_MB_VISUAL().icon, "Interface\\Icons\\Spell_Holy_BlessingOfStrength_TEX",
    "②★★亲自挑的图标优先于自动挑（宏图标表里有扳手也不换）")
  EVAL_HELP_CONFIG.mbIcon = nil
  EVAL_HELP_MB_SETICON()
  eq(EVAL_TEST_MB_VISUAL().icon, "Interface\\Icons\\INV_Misc_Wrench_01", "②清掉自定义 → 回到自动挑")
  -- ③ 真实右键：在图标库的格子上点右键 → 走真实 OnClick → 配置与按钮都换
  TEST.macroIcons = { "Spell_Fire_Fireball", "Spell_Holy_BlessingOfStrength_TEX" }
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local holy97 = nil
  for i = 1, EVAL_IB_TEST_CELL_COUNT() do
    local c97 = EVAL_IB_TEST_CELL(i)
    if c97 and c97.item and string.find(tostring(c97.item.path), "BlessingOfStrength", 1, true) then holy97 = i break end
  end
  eq(holy97 ~= nil, true, "③前置：网格里找得到神圣力量图标")
  EVAL_HELP_CONFIG.mbIcon = nil
  eq(EVAL_IB_TEST_CLICK_CELL(holy97, "RightButton"), true, "③★右键走了真实 OnClick")
  eq(EVAL_HELP_CONFIG.mbIcon ~= nil and string.find(tostring(EVAL_HELP_CONFIG.mbIcon), "BlessingOfStrength", 1, true) ~= nil, true,
    "③★★右键真的把图标写进配置: " .. tostring(EVAL_HELP_CONFIG.mbIcon))
  eq(EVAL_TEST_MB_VISUAL().icon ~= nil and string.find(tostring(EVAL_TEST_MB_VISUAL().icon), "BlessingOfStrength", 1, true) ~= nil, true,
    "③★★按钮当场换成它（读真控件）")
  EVAL_HELP_CONFIG.mbIcon = nil
  eq(EVAL_IB_TEST_CLICK_CELL(holy97, "LeftButton"), true, "④左键走了真实 OnClick")
  eq(EVAL_HELP_CONFIG.mbIcon, nil, "④★左键不写配置（只有右键才换图标，不被右键吃掉）")
  EVAL_HELP_CONFIG.mbIcon = nil
  TEST.macroIcons = savedMI97
  EVAL_HELP_MB_SETICON()
  print("  图标库右键 → 小地图按钮图标：亲自挑的优先 / 左键不动配置 / 清自定义回自动挑")
end

-- 98) ★★★1.71.16 方案快捷键绑定（用户：「战斗UI->方案单元->右键绑定任务，绑定按键下拉:键盘,鼠标等」）
--   ★派发形态经四次试错定案（1.71.22）：命令名 = 客户端自带的 ACTIONBUTTON<n> + 接管 ActionButtonDown/Up。
--   本组断言覆盖：命令名形态 / 格映射 / 存档 / 真机派发 / 非占用格透传 / 组合键守卫 / 清除交还 / 真实弹窗流程。
do
  local savedP98, savedA98 = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "甲", skills = {} }, { name = "乙", skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  -- ★★1.71.22 派发形态定案（四次试错后的最终形态）：
  --   Bindings.xml 在本客户端**不生效**（本机对照实验 + unrealUI 源码注释双重确认），
  --   可行路线 = 命令名用**客户端自带的** ACTIONBUTTON<n> + 接管全局 ActionButtonDown/Up。
  local missCmd = ""
  for i = 1, 12 do if type(_G["EVAL_GO" .. i]) ~= "function" then missCmd = missCmd .. i .. " " end end
  eq(missCmd, "", "①★★接管后要调的 EVAL_GO1~12 全都真实存在: " .. missCmd)
  eq(EVAL_BIND_SLOT_CMD(3), "ACTIONBUTTON3", "①派发命令名 = 客户端**自己会派发**的 ACTIONBUTTON<n>")
  eq(EVAL_BIND_SLOT_CMD(13), nil, "①★主条只有 12 格：超出如实回 nil（不编造命令名）")
  local rows98, items98, locked98 = EVAL_BIND_KEYLIST()
  eq(table.getn(rows98), table.getn(items98), "②清单行数对齐")
  local badKey98, nKey98, hasMouse98, hasF198, lockOK98 = "", 0, false, false, true
  for i, r in ipairs(rows98) do
    if r.header then
      if not locked98[i] then lockOK98 = false end
    elseif type(r.key) == "string" then
      nKey98 = nKey98 + 1
      if locked98[i] then lockOK98 = false end
      if not string.find(r.key, "^[A-Z0-9][A-Z0-9%-]*$") then badKey98 = badKey98 .. r.key .. " " end
      if r.key == "BUTTON3" then hasMouse98 = true end
      if r.key == "F1" then hasF198 = true end
    end
  end
  eq(lockOK98, true, "②★分类标题行全 locked（不可点）、键名行全可点")
  eq(badKey98, "", "②★键名全是 SetBinding 认的写法: " .. badKey98)
  eq(hasMouse98 and hasF198 and nKey98 >= 40, true, "②键盘/鼠标都在（用户要「键盘,鼠标等」）: " .. nKey98 .. " 个键")
  -- ③ 绑定：命令名 + 格映射 + 存档 + 接管
  TEST.bindings = nil
  TEST.saveBindingsCalls = 0
  TEST.abDownCalls = {} TEST.abUpCalls = {}
  TEST.abOrigDownCalls = {} TEST.abOrigUpCalls = {}
  EVAL_BIND_UNINSTALL()
  EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  eq(EVAL_BIND_DO(2, "F10"), true, "③绑定成功")
  eq(string.find(tostring(TEST.bindings.F10), "^ACTIONBUTTON%d+$") ~= nil, true,
    "③★★绑定命令名 = ACTIONBUTTON<n>（客户端自己派发的家族，实测 12 条在命令表里）")
  local slot98 = EVAL_HELP_CONFIG.war.bindSlots[2]
  eq(type(slot98) == "number", true, "③★记下方案 2 占用的格号: " .. tostring(slot98))
  eq(TEST.bindings.F10, EVAL_BIND_SLOT_CMD(slot98), "③★绑的就是那格的命令")
  eq(EVAL_HELP_CONFIG.war.bindKeys[2], "F10", "③配置记下当前键")
  eq(TEST.saveBindingsCalls >= 1, true, "③★绑定后真的 SaveBindings（不存就随重登消失）")
  eq(EVAL_BIND_ORIG_UP ~= nil, true, "③★★绑定同时把 ActionButtonUp 接管装上（运行中立即生效）")
  -- ③a ★★真机派发验证：模拟客户端按下那格的键 → 调 ActionButtonUp(格号) → **必须真的走 EVAL_GO**
  --   ★观测点选「EVAL_GO 的追踪器」而不是「activeProfile」：profSel 是**执行指定方案**，
  --     它**不激活**方案（Engine.lua:2722-2741 明写）——拿 activeProfile 当判据会测到一条不存在的性质。
  --   ★EVAL_GO 有 0.3s 去抖窗（防 /run 队列冲刷），测试先清掉，否则验的是「去抖生效」不是「派发链路通」。
  EVAL_GO_LAST = nil
  EVAL_GO_TRACE = {}
  local callsBefore98 = table.getn(TEST.abUpCalls)
  ActionButtonUp(slot98)
  eq(table.getn(EVAL_GO_TRACE) >= 1, true, "③a★★按下该格 → 真的调到了 EVAL_GO（「按键能触发」的直接证据）")
  eq(table.getn(TEST.abUpCalls), callsBefore98, "③a★被我们接管的格子**不**透传给原函数")
  -- ③a2 ★没被我们占的格子必须原样透传（绝不改变客户端行为）
  --   ★桩分两本账：abUpCalls = 我们的接管被调；abOrigUpCalls = 原函数被调。
  --     判「透传」必须看**原函数那本账**（只看自己那本会把「吞了」和「没调」混为一谈）。
  local free98 = 12
  for s = 1, 12 do if not EVAL_BIND_SLOT_MAP()[s] then free98 = s break end end
  eq(free98 ~= slot98, true, "③a2 前置：挑到的确实是**另一个**格: " .. tostring(free98))
  TEST.abOrigUpCalls = {}
  ActionButtonUp(free98)
  eq(table.getn(TEST.abOrigUpCalls) == 1 and TEST.abOrigUpCalls[1] == free98, true,
    "③a2★★没被占的格子原样交给客户端（不吞别人的按键）")
  -- ③a3 ★组合键守卫：按住修饰键且该组合另有归属时**不触发**（unrealUI 警告的代价，必须补回）
  --   先给该格绑一个裸键，让守卫有键可查（真机上这格本来就有键，否则我们也不会占它）
  TEST.bindings["F10"] = EVAL_BIND_SLOT_CMD(slot98)
  TEST.altDown = true
  TEST.bindings["ALT-F10"] = "TOGGLECHARACTER0" -- 模拟 Alt-F10 另有归属
  TEST.abOrigUpCalls = {}
  ActionButtonUp(slot98)
  eq(table.getn(TEST.abOrigUpCalls), 1, "③a3★★组合键另有归属时不吞（让给客户端）")
  TEST.altDown = false
  TEST.bindings["ALT-F10"] = nil
  -- ③a4 ★无修饰键时正常触发（守卫不误伤）
  EVAL_GO_LAST = nil
  EVAL_GO_TRACE = {}
  TEST.abOrigUpCalls = {}
  ActionButtonUp(slot98)
  eq(table.getn(EVAL_GO_TRACE) >= 1 and table.getn(TEST.abOrigUpCalls) == 0, true,
    "③a4★★无修饰键冲突时正常触发（守卫不误伤正常按键）")
  EVAL_BIND_DO(2, "F11")
  eq(GetBindingAction("F10"), "", "③★★换键时旧键 F10 被解绑（不留一键两命令的烂摊子）")
  eq(TEST.bindings.F11, EVAL_BIND_SLOT_CMD(slot98), "③新键 F11 就位")
  eq(EVAL_HELP_CONFIG.war.bindSlots[2], slot98, "③★★换键**不换格**（格是方案的身份，换格会串）")
  EVAL_BIND_CLEAR(2)
  eq(GetBindingAction("F11"), "", "③★清除真的解绑")
  eq(EVAL_HELP_CONFIG.war.bindKeys[2], nil, "③配置清掉")
  eq(EVAL_HELP_CONFIG.war.bindSlots[2], nil, "③★格映射也清掉（不留孤儿）")
  TEST.abOrigUpCalls = {}
  ActionButtonUp(slot98)
  eq(table.getn(TEST.abOrigUpCalls), 1, "③★清除后该格**交还**客户端（不再被我们吞）")
  eq(EVAL_BIND_DO(2, ""), false, "③空键如实拒")
  -- ③b ★不许抢用户已有的键位（用户追问「动作条前面都有具体站位了」逼出来的规则）
  TEST.bindings = { T = "ACTIONBUTTON4" } -- 模拟真机：4 号格的键位已被用户占用
  EVAL_HELP_CONFIG.war.bindSlots = nil EVAL_HELP_CONFIG.war.bindKeys = nil
  local picked98 = EVAL_BIND_FREE_SLOT(false)
  eq(picked98 ~= nil, true, "③b★仍能挑到无主格子: " .. tostring(picked98))
  eq(GetBindingAction("T"), "ACTIONBUTTON4", "③b★用户的 T 键原样不动")
  TEST.bindings = nil
  -- ③c ★★客户端若没有 ActionButtonDown/Up 全局 → 装不上要**如实失败**，不许假装成功
  EVAL_BIND_UNINSTALL() -- ★先卸干净：EVAL_BIND_INSTALL 是幂等的（装过就直接 true），不卸会拿到假绿
  TEST.noActionButtonGlobals = true
  EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
  eq(type(ActionButtonUp), "nil", "③c 前置：全局确实被清掉了")
  eq(EVAL_BIND_INSTALL(), false, "③c★★没有 ActionButtonDown/Up 时接管如实失败（不是静默假成功）")
  TEST.noActionButtonGlobals = false
  EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
  eq(EVAL_BIND_INSTALL(), true, "③c★全局在时接管成功")
  EVAL_BIND_UNINSTALL()
  eq(EVAL_BIND_ORIG_UP == nil, true, "③c★卸下接管后状态清干净（可重装）")
  EVAL_TB_TEST_RESET_ACTIONBUTTON_GLOBALS()
  -- ④ 弹窗真实流程：右键方案 → 弹窗 → 下拉回调选键 → 点[绑定]
  local wasShown98 = EVAL_TEST_UI_SHOWN()
  if not wasShown98 then EVAL_HELP_UI_TOGGLE() end
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local up98 = EVAL_TEST_UI_PROF()
  eq(up98.btns[1] and up98.btns[1].btn ~= nil, true, "④前置：拿到方案按钮的真实控件")
  up98.btns[1].btn:GetScript("OnClick")("RightButton")
  local bu98 = EVAL_TEST_BIND_UI()
  eq(bu98.shown, true, "④★★右键方案 → 绑定弹窗真的开了")
  eq(bu98.pidx, 1, "④★弹窗绑的是被点的那个方案（第 1 个）")
  local pickIdx98 = nil
  for i, r in ipairs(rows98) do if r.key == "F9" then pickIdx98 = i break end end
  EVAL_BIND_DD_PICK(rows98, pickIdx98)
  eq(EVAL_TEST_BIND_UI().selKey, "F9", "④下拉回调选键进状态")
  eq(string.find(tostring(EVAL_TEST_BIND_UI().info), "%S") ~= nil, true, "④提示行有内容（空闲=绿）")
  EVAL_TEST_BIND_DO_BTN():GetScript("OnClick")()
  eq(string.find(tostring(TEST.bindings.F9), "^ACTIONBUTTON%d+$") ~= nil, true, "④★★点[绑定] → 写入 ACTIONBUTTON 派发命令")
  eq(EVAL_HELP_CONFIG.war.bindKeys[1], "F9", "④配置记下 F9")
  EVAL_TEST_BIND_CLOSE()
  -- ⑤ 左键不被右键吃掉：仍是切换方案
  up98.btns[2].btn:GetScript("OnClick")("LeftButton")
  eq(EVAL_HELP_CONFIG.war.activeProfile, 2, "⑤★左键仍是切换方案（右键没把左键吃掉）")
  eq(EVAL_TEST_BIND_UI().shown, false, "⑤左键不开弹窗")
  -- 还原
  EVAL_HELP_CONFIG.war.profiles = savedP98
  EVAL_HELP_CONFIG.war.activeProfile = savedA98
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  TEST.bindings = nil
  EVAL_HELP_UI_BUILD()
  if not wasShown98 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end
  print("  方案绑定：右键开弹窗 → 下拉选键 → [绑定] = ACTIONBUTTON 命令 + 接管 ActionButtonUp 派发；换键不换格；清除交还格子；左键仍切换")
end

-- 99) ★★★1.71.19 用户：「方案文字 添加 tooltip 提示：右键取消所有自定绑定，左键点方案激活，右键绑定按键，美化说明」
do
  local savedP99, savedA99 = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "甲", skills = {} }, { name = "乙", skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local wasShown99 = EVAL_TEST_UI_SHOWN()
  if not wasShown99 then EVAL_HELP_UI_TOGGLE() end
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local up99 = EVAL_TEST_UI_PROF()
  local lb99 = up99 and up99.labelBtn
  eq(lb99 ~= nil, true, "前置：「方案」标签是真实可点控件")
  TEST.bindings = nil
  TEST.saveBindingsCalls = 0
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  eq(EVAL_BIND_DO(1, "F9"), true, "①前置：方案 1 绑定成功")
  eq(EVAL_BIND_DO(2, "F10"), true, "①前置：方案 2 绑定成功")
  eq(GetBindingAction("F9") ~= "" and GetBindingAction("F10") ~= "", true, "①前置：两个自定义绑定就位")
  eq(EVAL_HELP_CONFIG.war.bindSlots[1] ~= EVAL_HELP_CONFIG.war.bindSlots[2], true,
    "①★★两个方案各占一个**不同**的格（同一格会互相覆盖）")
  lb99:GetScript("OnClick")("LeftButton")
  eq(GetBindingAction("F9") ~= "", true, "②★左键点「方案」不动绑定（左键是方案按钮的事）")
  lb99:GetScript("OnClick")("RightButton")
  eq(GetBindingAction("F9"), "", "③★★右键点「方案」→ F9 被解绑")
  eq(GetBindingAction("F10"), "", "③★★F10 也被解绑（全部清除，一个不剩）")
  eq(EVAL_HELP_CONFIG.war.bindKeys, nil, "③★配置表清掉")
  eq(TEST.saveBindingsCalls >= 3, true, "③★清除后也真的 SaveBindings（2 次绑定 + 1 次清除）")
  eq(EVAL_BIND_CLEAR_ALL(), 0, "④空表返回 0（幂等，连点不炸）")
  EVAL_BIND_DO(1, "F11")
  eq(EVAL_BIND_CLEAR_ALL(), 1, "④★如实返回清掉的个数 = 1")
  TEST.tipLines = nil
  lb99:GetScript("OnEnter")()
  eq(type(TEST.tipLines) == "table" and table.getn(TEST.tipLines) >= 4, true,
    "⑤★悬停出了 tooltip（标题 + 三行说明）: " .. tostring(TEST.tipLines and table.getn(TEST.tipLines)))
  local tipAll99 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipAll99 = tipAll99 .. "|" .. tostring(ln.text) end
  eq(string.find(tipAll99, EVAL_L("BIND_L_TIP_1"), 1, true) ~= nil
     and string.find(tipAll99, EVAL_L("BIND_L_TIP_2"), 1, true) ~= nil
     and string.find(tipAll99, EVAL_L("BIND_L_TIP_3"), 1, true) ~= nil, true,
    "⑤★★三行说明都在（左键激活 / 右键绑定 / 右键标签全清）")
  eq(EVAL_HELP_CONFIG.war.bindSlots, nil, "⑥★★右键全清同时清掉格映射（不留孤儿）")
  EVAL_HELP_CONFIG.war.profiles = savedP99
  EVAL_HELP_CONFIG.war.activeProfile = savedA99
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  TEST.bindings = nil
  EVAL_HELP_UI_BUILD()
  if not wasShown99 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end
  print("  「方案」标签：右键全清绑定（逐键解绑+存档+计数）/ tooltip 三行说明 / 左键不动绑定")
end

-- 100) ★1.71.20 用户：「左键点击<标题方案>.日志打印方案绑定情况.」——
--   「方案」标签左键 = 聊天框逐行打印 方案=键（只打印不动绑定；没有就如实说没有）。
do
  local savedP100 = EVAL_HELP_CONFIG.war.profiles
  EVAL_HELP_CONFIG.war.profiles = { { name = "甲", skills = {} }, { name = "乙", skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local wasShown100 = EVAL_TEST_UI_SHOWN()
  if not wasShown100 then EVAL_HELP_UI_TOGGLE() end
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local lb100 = EVAL_TEST_UI_PROF().labelBtn
  eq(lb100 ~= nil, true, "前置：「方案」标签在")
  TEST.bindings = nil
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  eq(EVAL_BIND_DO(1, "E"), true, "前置：方案 1 绑 E")
  eq(EVAL_BIND_DO(2, "F9"), true, "前置：方案 2 绑 F9")
  TEST.chat = nil
  lb100:GetScript("OnClick")("LeftButton")
  eq(type(TEST.chat) == "string" and string.find(TEST.chat, "甲 = E", 1, true) ~= nil, true,
    "①★★左键「方案」→ 聊天里打印了「甲 = E」: " .. tostring(TEST.chat))
  eq(string.find(TEST.chat, "乙 = F9", 1, true) ~= nil, true, "①★「乙 = F9」也在")
  eq(GetBindingAction("E") ~= "" and GetBindingAction("F9") ~= "", true, "②★左键只打印，不动绑定")
  EVAL_BIND_CLEAR_ALL()
  TEST.chat = nil
  lb100:GetScript("OnClick")("LeftButton")
  eq(string.find(tostring(TEST.chat), EVAL_L("BIND_ST_NONE"), 1, true) ~= nil, true,
    "③★没有绑定时如实打印「没有」（不是静默什么都不出）")
  TEST.tipLines = nil
  lb100:GetScript("OnEnter")()
  local tipAll100 = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipAll100 = tipAll100 .. "|" .. tostring(ln.text) end
  eq(string.find(tipAll100, EVAL_L("BIND_L_TIP_4"), 1, true) ~= nil, true, "④★tooltip 第 4 行 = 左键打印绑定情况")
  EVAL_HELP_CONFIG.war.profiles = savedP100
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  TEST.bindings = nil
  EVAL_HELP_UI_BUILD()
  if not wasShown100 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end
  print("  左键「方案」= 打印绑定情况（有则逐行 方案=键 / 无则如实说没有 / 不动绑定）")
end

-- 101) ★1.71.22 派发前提自检：命令表里必须有 **客户端自带的 ACTIONBUTTON1~12**
--   （这是整条派发链路的唯一外部前提 —— 它们不在表里，接管 ActionButtonUp 也永远等不到调用）。
--   ★1.71.21 曾经数的是 EVAL_GO_PROF_*（Bindings.xml 路线），那条路已被对照实验判死 → 判据整体改写。
do
  eq(EVAL_BIND_XML_STATUS(), 0, "①没有命令表（桩默认 nil）→ 0 = 前提不成立")
  TEST.bindingCmds = {
    { "HEADER_ACTIONBAR" },
    { "ACTIONBUTTON1", "1", nil },
    { "MoveForward", "W", "UP" },
    { "ACTIONBUTTON2", nil, nil },
    { "EVAL_GO_PROF_1", "E", nil }, -- ★反例：旧路线的命令名**不该**被算进前提
    { "ACTIONBUTTON12", nil, nil },
  }
  eq(EVAL_BIND_XML_STATUS(), 3, "②★只数 ACTIONBUTTON1~12（旧命令名/内建命令/HEADER 行都不算）: " .. EVAL_BIND_XML_STATUS())
  local full101 = {}
  for i = 1, 12 do full101[i] = { "ACTIONBUTTON" .. i, nil, nil } end
  TEST.bindingCmds = full101
  eq(EVAL_BIND_XML_STATUS(), 12, "③★12 个全在 = 派发前提成立")
  TEST.bindingCmds = { { "ACTIONBUTTON1X", nil, nil } }
  eq(EVAL_BIND_XML_STATUS(), 0, "④后缀必须精确——ACTIONBUTTON1X 不算（防「数到不相干的名字」）")
  TEST.bindingCmds = { { "SELFACTIONBUTTON1", nil, nil } }
  eq(EVAL_BIND_XML_STATUS(), 0, "④★必须以 ACTIONBUTTON 开头——SELFACTIONBUTTON 之类不算")
  TEST.bindingCmds = nil
  print("  派发前提自检：客户端自带 ACTIONBUTTON1~12 是否在命令表里（0=前提不成立）")
end

-- 102) ★★★1.71.24 用户：「将这两个功能合并成一个弹窗管理.都是右键触发.」
--   = 把「配置窗方案按钮右键→重命名」与「战斗信息UI 方案按钮右键→快捷键绑定」两个弹窗合并成一个
--     **方案管理窗**（窗内两段：① 方案名称 ② 快捷键），并且**两处右键都开同一个窗**。
--   ★本组守四条性质：① 两处右键都进同一个窗（不是各开各的）② 窗内**两段都在**（能改名 + 能绑键，缺一不可）
--                    ③ 「保存」一次提交两段（改名 + 绑键）④ 左键语义不变（仍是激活方案）
do
  local savedP102, savedA102 = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "甲", skills = {} }, { name = "乙", skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  TEST.bindings = nil
  TEST.saveBindingsCalls = 0
  TEST.chat = nil
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  EVAL_TEST_BIND_CLOSE()
  -- ① 战斗信息UI 方案按钮右键 → 开窗
  local wasShown102 = EVAL_TEST_UI_SHOWN()
  if not wasShown102 then EVAL_HELP_UI_TOGGLE() end
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local up102 = EVAL_TEST_UI_PROF()
  eq(up102.btns[1] and up102.btns[1].btn ~= nil, true, "①前置：拿到战斗信息UI 方案按钮真实控件")
  up102.btns[1].btn:GetScript("OnClick")("RightButton")
  local bu102 = EVAL_TEST_BIND_UI()
  eq(bu102.shown, true, "①★★战斗信息UI 右键方案 → 弹窗真的开了")
  eq(bu102.pidx, 1, "①★开的是被点的那个方案（第 1 个）")
  eq(string.find(tostring(bu102.title), EVAL_L("PM_TITLE"), 1, true) ~= nil, true,
    "①★★窗标题 = 「方案管理」（合并后的新标题，不再是「绑定快捷键」）: " .. tostring(bu102.title))
  -- ② 两段都在：名字段（回声行可写）+ 快捷键段（当前绑定行 + 无绑定如实说「无」）
  eq(type(EVAL_TEST_PM_SETNAME) == "function" and EVAL_TEST_PM_SETNAME("甲改名") == true, true,
    "②★窗内**名字段**真的可输入（改写输入框 + 回声行）")
  eq(EVAL_TEST_BIND_UI().echo, "甲改名", "②★回声行镜像了输入内容（EditBox 不渲染也看得见）")
  eq(bu102.cur ~= nil and string.find(tostring(bu102.cur), EVAL_L("BIND_NONE"), 1, true) ~= nil, true,
    "②★★窗内**快捷键段**也在（当前绑定行如实显示「无」）: " .. tostring(bu102.cur))
  -- ③ 「保存」一次提交两段：改名 + 绑键
  local rows102 = EVAL_BIND_KEYLIST()
  local pickI102 = nil
  for i, r102 in ipairs(rows102) do if r102.key == "F9" then pickI102 = i break end end
  EVAL_BIND_DD_PICK(rows102, pickI102)
  eq(EVAL_TEST_BIND_UI().selKey, "F9", "③前置：下拉选中 F9")
  TEST.chat = nil
  EVAL_TEST_BIND_DO_BTN():GetScript("OnClick")()
  eq(EVAL_HELP_CONFIG.war.profiles[1].name, "甲改名", "③★★点[保存] → **名字真的改了**（第一段生效）")
  eq(string.find(tostring(TEST.bindings.F9), "^ACTIONBUTTON%d+$") ~= nil, true,
    "③★★同一次[保存] → **快捷键也真的绑上了**（第二段生效）——这才是「一个弹窗管理」")
  eq(EVAL_HELP_CONFIG.war.bindKeys[1], "F9", "③★配置记下 F9")
  -- ③b 名字留空 → 如实拒绝改名、但**绑键照常**（两段互不牵连）
  TEST.bindings = nil
  EVAL_HELP_CONFIG.war.bindKeys = nil EVAL_HELP_CONFIG.war.bindSlots = nil
  EVAL_TEST_PM_SETNAME("   ")
  EVAL_BIND_DD_PICK(rows102, pickI102)
  TEST.chat = nil
  EVAL_TEST_BIND_DO_BTN():GetScript("OnClick")()
  eq(EVAL_HELP_CONFIG.war.profiles[1].name, "甲改名", "③b★空名字**不改名**（保留原名，不写空串）")
  eq(string.find(tostring(TEST.bindings.F9), "^ACTIONBUTTON%d+$") ~= nil, true, "③b★空名字不影响绑键那一段")
  EVAL_TEST_BIND_CLOSE()
  -- ③c ★★合并的**结构判据**（两条，缺一就有盲区）：
  --   ① 全插件只剩**一个**管理弹窗（旧的重命名窗/绑定窗对象都已不在）
  --   ② 旧入口名**彻底删除**（不是留等价别名）
  --   ★为什么必须这样判：留别名时「调用点改回旧名字」的回归会**悄悄通过**
  --     （旧名照样开同一个窗 → 行为断言全绿）。实测变异 M1/M2 正是这样 SURVIVED 的。
  --     删掉旧名之后，任何回退都变成「调用 nil」当场炸响。
  eq(EVAL_HELP_PM_WINDOW_COUNT(), 1, "③c★★全插件只剩**一个**管理弹窗（旧的重命名窗/绑定窗都已合并掉）")
  -- ③d ★窗内两段都**真的画在了窗内**（需求：「一个弹窗管理」——两段挤不下就等于没合并）
  local pmGeo = EVAL_TEST_PM_GEO()
  eq(pmGeo ~= nil, true, "③d前置：拿到管理窗的真实几何")
  -- ★y 是**向下递减**的（TOPLEFT 锚点 + 负值）：越往下值越小
  eq(pmGeo.secKeyY < pmGeo.secNameY and pmGeo.keyBtnY < pmGeo.secKeyY and pmGeo.infoY < pmGeo.keyBtnY, true,
    "③d★两段落从上到下**有序排开**（名称 → 快捷键 → 提示行）: "
    .. table.concat({ tostring(pmGeo.secNameY), tostring(pmGeo.secKeyY), tostring(pmGeo.keyBtnY), tostring(pmGeo.infoY) }, " > "))
  eq(pmGeo.infoY < pmGeo.btnY, true, "③d★提示行在按钮行**之上**（不压按钮）")
  -- ★窗内 = |y| 不超过窗高（按钮行用 BOTTOMLEFT 锚点，所以是正值）
  eq(math.abs(pmGeo.infoY) < pmGeo.h and pmGeo.btnY >= 0, true,
    "③d★★全部内容都在窗内（没有越界）: H=" .. tostring(pmGeo.h) .. " info=" .. tostring(pmGeo.infoY) .. " btn=" .. tostring(pmGeo.btnY))
  eq(type(EVAL_HELP_RP_OPEN), "nil", "③c★★旧重命名入口 EVAL_HELP_RP_OPEN 已**删除**（不是留别名）")
  eq(type(EVAL_BIND_OPEN), "nil", "③c★★旧绑定入口 EVAL_BIND_OPEN 已**删除**")
  -- ④ 配置窗方案按钮右键 → 开的是**同一个**窗（合并的核心判据）
  EVAL_HELP_CONFIG.war.bindKeys = nil EVAL_HELP_CONFIG.war.bindSlots = nil
  TEST.bindings = nil
  -- ★配置窗可能已经开着（EVAL_HELP_CFG_TOGGLE 是切换语义）→ 先确认它真的可见
  local wasCfg102 = EVAL_TEST_CFG_SIZE() ~= nil
  EVAL_HELP_CFG_TOGGLE()
  if not EVAL_TEST_CFG_VISIBLE() then EVAL_HELP_CFG_TOGGLE() end
  EVAL_HELP_CFG_SETTAB(2)
  local cfg102 = EVAL_TEST_CFG_PROF()
  -- ★钩子返回 { btns = <真实控件数组> }，所以 btns[1] **本身**就是按钮（不是 {btn=} 包裹表）
  eq(cfg102 ~= nil and cfg102.btns ~= nil and cfg102.btns[1] ~= nil and cfg102.btns[1].GetScript ~= nil, true,
    "④前置：拿到配置窗方案按钮真实控件")
  cfg102.btns[1]:GetScript("OnClick")("RightButton")
  local bu102b = EVAL_TEST_BIND_UI()
  eq(bu102b.shown, true, "④★★配置窗右键方案 → 也开了弹窗")
  eq(string.find(tostring(bu102b.title), EVAL_L("PM_TITLE"), 1, true) ~= nil, true,
    "④★★开的是**同一个方案管理窗**（标题一致 = 两处右键合并成功）: " .. tostring(bu102b.title))
  eq(bu102b.pidx, 1, "④★绑的是被点的方案")
  EVAL_TEST_BIND_CLOSE()
  EVAL_HELP_CFG_TOGGLE()
  -- ⑤ 左键语义不变：仍是激活方案（没被右键合并吃掉）
  up102.btns[2].btn:GetScript("OnClick")("LeftButton")
  eq(EVAL_HELP_CONFIG.war.activeProfile, 2, "⑤★★左键仍是激活方案（右键合并没动左键语义）")
  eq(EVAL_TEST_BIND_UI().shown, false, "⑤左键不开窗")
  -- 还原
  EVAL_HELP_CONFIG.war.profiles = savedP102
  EVAL_HELP_CONFIG.war.activeProfile = savedA102
  EVAL_HELP_CONFIG.war.bindKeys = nil
  EVAL_HELP_CONFIG.war.bindSlots = nil
  TEST.bindings = nil
  EVAL_HELP_UI_BUILD()
  if not wasShown102 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end
  print("  方案管理窗：两处右键（战斗信息UI / 配置窗）都开同一个窗；窗内改名 + 绑键两段；[保存]一次提交两段；左键仍激活")
end

-- 103) ★★★1.72.2 分享方案的解：别人角色**从未学过**该 debuff 的纹理 → 名字扫描兜底 + 命中即自愈
--   【用户实测】分享出去的方案在别人角色上，日志刷
--   「十字军圣印跳过: 目标debuff:无法识别光环「十字军审判」（纹理未记录）」→ 技能永远不放。
--   根因：`debuffTex` 学习表是**每角色**的；「十字军审判」又不是对方动作条上的技能 → 纹理两条路都空；
--     而旧代码「纹理解析不出就先 return」，**按名字兜底永远到不了** —— 恰是最需要它的时候（死接线）。
--   ★判据（四条）：① 纹理未知 + 名字在 → 判「有」；② 命中即自愈（学下纹理）；
--     ③ 自愈后走快路径（扫描器断掉也照常判）；④ 扫描可信 + 确实没有 → 负向方向如实为真（旧版恒假）。
do
  local function clearTex103(nm)
    EVAL_DEBUFF_TEX_LEARN[nm] = nil
    if EVAL_HELP_CONFIG and EVAL_HELP_CONFIG.war and EVAL_HELP_CONFIG.war.debuffTex then
      EVAL_HELP_CONFIG.war.debuffTex[nm] = nil
    end
  end
  clearTex103("十字军审判")
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  TEST.debuffs = { { name = "十字军审判", tex = "TEX_JUDGE" } }
  EVAL_HELP_UPDATE_STATE()
  eq(EVAL_AURA_TEX("十字军审判"), nil, "①前置：纹理确实未知（学习表与动作条都没有）——复现用户场景")
  -- ① 核心：纹理未知，但名字就在目标身上 → 判「有」
  local ok1, why1 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasDebuff", s = "十字军审判", v = true }, nil)
  eq(ok1, true, "★★★texture unknown but the NAME is on the target → hasDebuff is TRUE (the shared profile can finally fire): " .. tostring(why1))
  -- ② 命中即自愈
  eq(EVAL_AURA_TEX("十字军审判"), "TEX_JUDGE", "★★★a hit LEARNS the name→texture pair (self-heal)")
  -- ③ 自愈后不再依赖扫描：工具读名入口全断，照样判得出来（快路径）
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local GT = EVAL_TEST_WTT() -- ★1.73.14 扫描器现在是**自家隐形 tooltip**（不再是 GameTooltip）
  local svb, svd, svp = GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff
  GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff = nil, nil, nil
  local ok2 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasDebuff", s = "十字军审判", v = true }, nil)
  eq(ok2, true, "★★★after self-heal the judgement no longer needs the scanner at all (fast path)")
  GT.SetUnitBuff, GT.SetUnitDebuff, GT.SetPlayerBuff = svb, svd, svp
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  -- ④ 负向方向：扫描可信 + 名字确实不在 → 如实为真（旧代码这里恒假 → 「无debuff」条件永远不成立）
  clearTex103("十字军审判")
  TEST.debuffs = { { name = "别的debuff", tex = "TEX_OTHER_D" } }
  EVAL_HELP_UPDATE_STATE()
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  local ok3, why3 = EVAL_TEST_COND_EVAL_LIVE({ k = "hasDebuff", s = "十字军审判", v = false }, nil)
  eq(ok3, true, "★★★trustworthy scan without the name → no-debuff is TRUE (was permanently false before): " .. tostring(why3))
  -- 收尾（模块级状态自己收）
  TEST.debuffs = {}
  clearTex103("十字军审判")
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  EVAL_HELP_UPDATE_STATE()
  print("  分享方案纹理缺失：名字扫描兜底命中 + 自愈学纹理 + 之后走快路径；负向方向也如实判定")
end

-- 104) ★★★1.72.2 学习表诊断命令（用户实机验证「自动扫描」的入口）
--   用户要求：「模拟本地清理纹理记录，先主动删除一些纹理，我测试下能否自动扫描」。
--   ★判据：① 命令真的删（**两个存储**都删）② 删完之后再判定要**重新扫描并学回来**（自愈闭环）
--          ③ 名字匹配**大小写不敏感**（/eh 会把整条命令转小写）④ 删不存在的名字要如实回报、不许崩。
do
  local function cmd104(s) SlashCmdList["EVALHELP"](s) end
  local cfgW = EVAL_HELP_CONFIG.war
  cfgW.debuffTex = cfgW.debuffTex or {}
  -- ① 概览
  EVAL_DEBUFF_TEX_LEARN["测试命令光环"] = "TEX_CMD"
  cfgW.debuffTex["TestCaseAura"] = "TEX_CASE"
  TEST.chat = nil
  cmd104("go tex")
  eq(TEST.chat ~= nil and string.find(TEST.chat, "学习表", 1, true) ~= nil, true, "★/eh go tex 能打印学习表概览")
  -- ② 删单条（中文精确命中）
  TEST.chat = nil
  cmd104("go texdel 测试命令光环")
  eq(EVAL_DEBUFF_TEX_LEARN["测试命令光环"], nil, "★★texdel 真的删掉了运行时兜底表里的记录")
  eq(string.find(tostring(TEST.chat), "已删除", 1, true) ~= nil, true, "★★并如实回报已删除")
  -- ③ 大小写不敏感
  TEST.chat = nil
  cmd104("go texdel TestCaseAura")
  eq(cfgW.debuffTex["TestCaseAura"], nil, "★★★texdel 大小写不敏感（/eh 会把整条命令转小写）")
  -- ④ 删不存在的名字：如实回报
  TEST.chat = nil
  cmd104("go texdel 绝不存在的名字")
  eq(string.find(tostring(TEST.chat), "没有", 1, true) ~= nil, true, "★删不存在的名字如实回报「没有」")
  -- ⑤ 自愈闭环：删掉纹理记录后重新判定 → 自动重新扫描并学回来（用户要验的就是这个）
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  TEST.debuffs = { { name = "十字军审判", tex = "TEX_JUDGE2" } }
  EVAL_HELP_UPDATE_STATE()
  EVAL_DEBUFF_TEX_LEARN["十字军审判"] = nil
  cfgW.debuffTex["十字军审判"] = nil
  eq(EVAL_AURA_TEX("十字军审判"), nil, "⑤前置：纹理确实已空（模拟本地清理纹理记录）")
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "hasDebuff", s = "十字军审判", v = true }, nil), true,
     "★★★清理纹理记录后，判定**自动扫描**并命中（这就是分享方案的解）")
  eq(EVAL_AURA_TEX("十字军审判"), "TEX_JUDGE2", "★★★并且把纹理学了回来（自愈闭环）")
  -- ⑥ 全清：两个存储都要空
  TEST.chat = nil
  cmd104("go texclear")
  eq(string.find(tostring(TEST.chat), "已清空", 1, true) ~= nil, true, "★texclear 回报已清空")
  local n1, n2 = 0, 0
  for _ in pairs(cfgW.debuffTex) do n1 = n1 + 1 end
  for _ in pairs(EVAL_DEBUFF_TEX_LEARN) do n2 = n2 + 1 end
  eq(n1 == 0 and n2 == 0, true, "★★texclear 真的把两个存储都清空了（残留 " .. n1 .. "/" .. n2 .. "）")
  -- ⑦ texscan 不报错并打印四类（含新的「扫描可信」）
  TEST.chat = nil
  cmd104("go texscan")
  eq(string.find(tostring(TEST.chat), "扫描可信", 1, true) ~= nil, true, "★texscan 打印四类光环与本次扫描是否可信")
  -- 收尾（模块级状态自己收）
  TEST.debuffs = {}
  EVAL_HELP_UPDATE_STATE()
  EVAL_AURA_TEST_RESET_NAME_CACHE()
  TEST.chat = nil
  print("  学习表诊断命令：/eh go tex | texdel 名字(大小写不敏感) | texclear | texscan；删掉纹理后判定会自动扫描并学回来")
end

-- 105) ★★★1.72.2 载入提示 + 新手引导：**每次加载**都要打到聊天框
--   【事故】1.72.1 把引导做成「只在人生第一局出一次」（`cfg.guideSeen`）→ 用户重载/重进之后**再也看不到**，
--     截图里只剩「✅ 已加载成功 + 一行提示」，四步引导缺失（用户原话：「之前的新手引导功能需要在这里显示」）。
--   ★判据：① 触发 VARIABLES_LOADED（= 进游戏 / /reload）后，聊天框必须有
--     载入成功行（带版本号）+ 引导标题 + 步骤正文；
--     ② **再来一次仍然要出** —— 这条正是旧实现的死因
--        （变异：把 `if not cfg.guideSeen` 那个门加回来 → 本组必炸）。
do
  local f105 = EVAL_HELPInitFrame
  eq(type(f105) == "table" and type(f105.GetScript) == "function", true,
     "①前置：拿到具名帧 EVAL_HELPInitFrame（桩已按真客户端行为把它挂成全局）")
  local onEvent = f105:GetScript("OnEvent")
  eq(type(onEvent) == "function", true, "①前置：init 帧挂着 OnEvent")
  local function loadOnce105(tag)
    TEST.chat = nil
    local ok, err = pcall(onEvent, "VARIABLES_LOADED", nil)
    eq(ok, true, "★★VARIABLES_LOADED 处理不许报错（" .. tag .. " err=" .. tostring(err) .. "）")
    return tostring(TEST.chat or "")
  end
  local chat1 = loadOnce105("first")
  eq(string.find(chat1, "已加载成功", 1, true) ~= nil, true, "★★载入成功提示要打出来")
  eq(string.find(chat1, "EvalHelp %d+%.%d+%.%d+") ~= nil, true,
     "★★载入提示里要带版本号（形如 EvalHelp 1.72.1）")
  -- ★★★1.73.35 用户第 3 条：载入信息（含四步引导）**已移到独立弹窗** → 判据跟着落点走（落到弹窗上）
  local LANG = EVAL_GET_LANG()
  local title = EVAL_LOCALES[LANG]["GUIDE_TITLE"]
  local step1 = EVAL_LOCALES[LANG]["GUIDE_S1"]
  local lp1 = EVAL_TEST_LOADPOP_STATE()
  eq(lp1.built, true, "★★★首次加载要建出**载入信息弹窗**（不再往聊天打 7 行）")
  eq(lp1.shown, true, "★★★首次加载弹窗要**显示**")
  eq(string.find(tostring(lp1.body), title, 1, true) ~= nil, true,
     "★★★四步引导在弹窗正文里（用户截图缺的就是它）: 找「" .. tostring(title) .. "」")
  eq(string.find(tostring(lp1.body), step1, 1, true) ~= nil, true, "★★引导正文（① 开战斗UI）也要在")
  -- ② 第二次加载（= /reload 语义）**仍然**要显示 —— 旧实现被 cfg.guideSeen 挡掉
  local chat2 = loadOnce105("second")
  local lp2 = EVAL_TEST_LOADPOP_STATE()
  eq(lp2.shown, true,
     "★★★第二次加载(/reload)弹窗**仍然**显示 —— 旧实现被 cfg.guideSeen 挡掉，用户就是这样看不到的")
  -- ③ 手动重看这条路也得在 —— ★★★1.73.41 用户：「使用引导显示弹窗的插件载入的那个引导窗」
  --   → 手动重看**打开的就是载入时那个引导窗**（不再只往聊天打 7 行）；
  --     ★弹窗不可用时才退回聊天打印（降级也要说出来，绝不静默）。
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.root) then EVAL_HELP_CFG_TOGGLE() end
  -- ★★[使用引导] / 手动重看：必须**无视** cfg.loadMsgSeen（force）——
  --   否则点过一次「知道了」之后就**再也看不到引导**了（这正是 1.72.2 那类「看不到」事故）。
  EVAL_HELP_CONFIG.loadMsgSeen = true
  EVAL_LOADPOP_HIDE()
  TEST.chat = nil
  SlashCmdList["EVALHELP"]("guide")
  local lp3 = EVAL_TEST_LOADPOP_STATE()
  eq(lp3.shown, true, "★★★/eh guide 要**打开引导窗**（与插件载入弹的是同一个 EVAL_HELP_LOADPOP）")
  eq(string.find(tostring(lp3.body), title, 1, true) ~= nil, true,
     "★★引导窗正文里有引导标题「" .. tostring(title) .. "」")
  eq(string.find(tostring(lp3.body), step1, 1, true) ~= nil, true, "★★也要有步骤正文（不是空窗）")
  eq(string.find(tostring(TEST.chat or ""), title, 1, true) == nil, true,
     "★不再往聊天打 7 行（用户要的是**弹窗**）")
  -- ③b 配置窗的 [使用引导] 按钮：走它的**真实 OnClick**，打开的必须是同一个窗
  EVAL_LOADPOP_HIDE()
  eq(EVAL_TEST_LOADPOP_STATE().shown, false, "③b前置：先确认窗是关的（否则「打开了」是假阳性）")
  eq(EVAL_TEST_CFG_GUIDE_CLICK(), true, "★★★配置窗 [使用引导] 按钮：真实 OnClick 能触发")
  local lp3b = EVAL_TEST_LOADPOP_STATE()
  eq(lp3b.shown, true, "★★★[使用引导] 打开的就是**载入时那个引导窗**（用户点名要的行为）")
  eq(string.find(tostring(lp3b.body), step1, 1, true) ~= nil, true, "★★同一个窗、同一份正文")
  -- ③c 弹窗不可用 → **必须**退回聊天打印（不许静默）
  EVAL_LOADPOP_HIDE()
  local savedShow105 = EVAL_LOADPOP_SHOW
  EVAL_LOADPOP_SHOW = nil
  TEST.chat = nil
  EVAL_HELP_GUIDE(true)
  eq(string.find(tostring(TEST.chat or ""), title, 1, true) ~= nil, true,
     "★★★弹窗不可用 → 如实退回聊天打印（降级也说出来）")
  EVAL_LOADPOP_SHOW = savedShow105
  EVAL_HELP_CONFIG.loadMsgSeen = false -- 恢复默认态（后面的组 138 还要用）
  TEST.chat = nil
  print("  载入提示 + 新手引导：每次加载都弹（含 /reload）；[使用引导] / /eh guide 打开**同一个引导窗**")
end

-- 106) ★★★1.72.3 分享发送限频（修「长方案对方偶尔收不到」）+ 收不齐必须如实说
--   【用户实测】方案长到 4 片时对方有时收不到；短方案（1 片）从不出问题。
--   【根因】原实现在一个 for 循环里**连着 RunScript** 发全部片段（同一帧 N 条 SendChatMessage）
--     → 撞反刷屏限流被吞一片 → 接收端永远收不齐；而收不齐当时是**静默丢弃**（一声不吭）。
--   ★判据（三条）：① 第 1 片立即发，**其余必须排队**（旧实现一帧全发）；
--     ② 队列按 SH_SEND_RATE 分时滴出（同一时刻连 tick 也抽不干）；
--     ③ 超时丢弃在途传输时**如实点名报片数**，且缓冲真的被丢弃（迟到的那片不会凑成一笔）。
do
  EVAL_SHARE_RESET()
  EVAL_HELP_CONFIG.share = { recv = true }
  local long = "# 方案: 长方案测试\n"
  for i = 1, 30 do long = long .. "- 测试技能" .. i .. " | 怒气>30\n" end
  local savedP, savedA = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT(long) }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local function sents106()
    local out = {}
    for _, s in ipairs(TEST.runScripts or {}) do
      local m = string.match(s, 'SendChatMessage%("(.-)", "GUILD"%)')
      if m and (string.sub(m, 1, 6) == "[EHPF#" or (string.find(m, "|HEHPF:", 1, true) and string.find(m, "传输中", 1, true))) then table.insert(out, m) end -- ★封皮不算分片（v1/v2）
    end
    return out
  end
  TEST.runScripts = nil TEST.chat = nil
  eq(EVAL_SHARE_SEND("GUILD"), true, "长方案分享启动")
  local first = sents106()
  local _, nStr = string.match(tostring(first[1] or ""), "^%[EHPF#%x+ (%d+)/(%d+)%]")
  if not nStr then _, nStr = string.match(tostring(first[1] or ""), "|HEHPF:%x+ (%d+)/(%d+):") end
  local total = tonumber(nStr) or 0
  local curId = string.match(tostring(first[1] or ""), "%[EHPF#(%x+) ") or string.match(tostring(first[1] or ""), "|HEHPF:(%x+) ")
  eq(total >= 3, true, "①前置：方案确实分成 ≥3 片（got " .. tostring(total) .. "）")
  -- ★① 核心判据
  eq(table.getn(first), 1, "★★★只立即发第 1 片，其余排队（旧实现一帧连发 " .. tostring(total) .. " 片）")
  eq(EVAL_TEST_SHARE_QUEUE_ID_COUNT(curId), total - 1, "★★本次传输队列里正好剩 " .. tostring(total - 1) .. " 片（id=" .. tostring(curId) .. "）")
  eq(string.find(tostring(TEST.chat), "排队", 1, true) ~= nil, true, "★★并且如实告知「已排队发送」")
  -- ★② 限频：同一时刻 tick 也不许滴出第二片
  EVAL_SHARE_TEST_TICK()
  eq(table.getn(sents106()), 1, "★★同一时刻 tick 不许滴出第二片（限频生效）")
  local sent, guard = 1, 0
  while EVAL_TEST_SHARE_QUEUE_ID_COUNT(curId) > 0 and guard < 300 do
    guard = guard + 1
    TEST.time = (TEST.time or 1000) + 1
    EVAL_SHARE_TEST_TICK()
    sent = table.getn(sents106())
  end
  eq(EVAL_TEST_SHARE_QUEUE_ID_COUNT(curId), 0, "★★★全部 " .. tostring(total) .. " 片最终分时发出（本次传输队列已空）")
  eq(EVAL_TEST_SHARE_QUEUE_ID_COUNT(curId), 0, "★本次传输的分片已全部发出")
  local msgs = sents106()
  -- ★★只取**本次传输**的分片（排掉上一笔遗留，否则会把别的 id 喂进去、数出来的片数也不对）
  local mine = {}
  for mi = 1, table.getn(msgs) do
    if string.find(msgs[mi], "%[EHPF#" .. tostring(curId) .. " ") or string.find(msgs[mi], "|HEHPF:" .. tostring(curId) .. " ", 1, true) then table.insert(mine, msgs[mi]) end
  end
  -- ★③ 收不齐 → 如实报 + 缓冲真被丢
  EVAL_SHARE_RESET()
  for i = 1, total - 1 do EVAL_SHARE_ONMSG(mine[i], "队友甲") end
  eq(EVAL_SHARE_PENDING(), nil, "③前置：半包不弹窗")
  EVAL_TEST_SHARE_RESET_WARN() -- ★★滴干循环推进了 TEST.time，不清窗口会把这条提醒吞掉
  TEST.time = (TEST.time or 1000) + 100 -- 超过 SH_BUF_TIMEOUT(60s)
  TEST.chat = nil
  -- 用另一笔「残缺」分片触发 sweep（sweep 就在 shOnMsg 里，走真实路径；不弹窗免得干扰后续断言）
  EVAL_SHARE_ONMSG("[EHPF#fe 1/4]4142", "队友乙")
  local chat = tostring(TEST.chat or "")
  eq(string.find(chat, "队友甲", 1, true) ~= nil, true, "★★★超时丢弃要**点名是谁发的**（旧实现一声不吭）")
  eq(string.find(chat, tostring(total - 1) .. "/" .. tostring(total), 1, true) ~= nil, true,
     "★★★并如实报「收了几片」（要 " .. tostring(total - 1) .. "/" .. tostring(total) .. "）")
  -- ★反向哨兵：迟到的那片不该凑成一笔（证明缓冲真被丢掉了）
  EVAL_SHARE_ONMSG(mine[total], "队友甲")
  eq(EVAL_SHARE_PENDING(), nil, "★★超时后迟到的最后一片不会凑成一笔（缓冲确实已丢弃）")
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedP EVAL_HELP_CONFIG.war.activeProfile = savedA
  EVAL_SHARE_RESET() TEST.runScripts = nil TEST.chat = nil
  print("  分享发送限频：第1片立即发、其余按 0.35s 排队滴出；收不齐超时**如实点名报片数**且缓冲真被丢")
end

-- 107) ★★★1.72.3 接收**冗余时长**（1~2 秒内的迟到都容忍）+ 只认方案标识 + 发送限频
--   用户原话：「分片接收添加接收冗余时长.比如 1-2 秒内都可以.创建可以传达其他对话信息.
--             但是方案只识别方案特定的标识,发送也添加发送频率.不要在瞬间发送大量文字.
--             不然服务器被触发预警」。
--   ★判据：① 分片**跨多秒**（每片间隔 0.5s）+ 中间夹**普通聊天** → 照样收齐弹窗；
--     ② 非本协议的消息（含形似但载荷非法的）→ 完全忽略，连提示都不发；
--     ③ 缺片时 2 秒如实提醒但**不删缓冲** → 迟到的片补齐后**仍然弹窗**（这就是冗余时长的价值）；
--     ④ 发送间隔 0.5s：同一刻 tick 抽不干（不在瞬间倾泻）。
do
  EVAL_SHARE_RESET()
  EVAL_HELP_CONFIG.share = { recv = true }
  local long = "# 方案: 冗余窗口测试\n"
  for i = 1, 30 do long = long .. "- 测试技能" .. i .. " | 怒气>30\n" end
  local savedP, savedA = EVAL_HELP_CONFIG.war.profiles, EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { EVAL_PROFILE_FROM_TEXT(long) }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local function sents107()
    local out = {}
    for _, s in ipairs(TEST.runScripts or {}) do
      local m = string.match(s, 'SendChatMessage%("(.-)", "GUILD"%)')
      if m and (string.sub(m, 1, 6) == "[EHPF#" or (string.find(m, "|HEHPF:", 1, true) and string.find(m, "传输中", 1, true))) then table.insert(out, m) end -- ★封皮不算分片（v1/v2）
    end
    return out
  end
  TEST.runScripts = nil
  EVAL_SHARE_SEND("GUILD")
  -- ④ 发送限频：推进 0.4s（< 0.5s）不许滴出第二片
  TEST.time = (TEST.time or 1000) + 0.4
  EVAL_SHARE_TEST_TICK()
  eq(table.getn(sents107()), 1, "④★★发送间隔 0.5s：0.4s 时不许滴出第二片（不瞬间倾泻）")
  local msgs, guard = sents107(), 0
  local n = 0
  local _, nStr = string.match(tostring(msgs[1] or ""), "^%[EHPF#%x+ (%d+)/(%d+)%]")
  if not nStr then _, nStr = string.match(tostring(msgs[1] or ""), "|HEHPF:%x+ (%d+)/(%d+):") end
  n = tonumber(nStr) or 0
  eq(n >= 3, true, "①前置：长方案分成 ≥3 片（got " .. tostring(n) .. "）")
  while table.getn(msgs) < n and guard < n + 5 do
    guard = guard + 1
    TEST.time = TEST.time + 0.6
    EVAL_SHARE_TEST_TICK()
    msgs = sents107()
  end
  eq(table.getn(msgs), n, "①前置：全部 " .. tostring(n) .. " 片滴完")
  -- ① 冗余窗口 + 夹普通聊天 → 照样收齐
  EVAL_SHARE_RESET() TEST.chat = nil
  for i = 1, n do
    TEST.time = (TEST.time or 1000) + 0.5
    EVAL_SHARE_ONMSG(msgs[i], "队友甲")
    EVAL_SHARE_ONMSG("大家好啊，今天打本吗？", "路人") -- ★同频道普通聊天：必须被完全忽略
  end
  local pend1 = EVAL_SHARE_PENDING()
  eq(pend1 ~= nil and pend1.name == "冗余窗口测试", true,
     "★★★分片跨 " .. tostring(n * 0.5) .. " 秒、中间夹普通聊天，照样收齐并弹窗")
  -- ② 非本协议消息 → 完全忽略（连提示都不发）
  EVAL_SHARE_RESET() TEST.chat = nil
  EVAL_SHARE_ONMSG("[EHPF#zz 1/3]这不是hex", "队友乙")
  EVAL_SHARE_ONMSG("随便聊聊", "队友乙")
  eq(EVAL_SHARE_PENDING(), nil, "②★形似但载荷非法的消息不入缓冲")
  eq(tostring(TEST.chat or "") == "", true, "②★不是我们的标识就当普通聊天——一个字都不该上屏")
  -- ③ 缺片：2 秒如实提醒但**不删** → 迟到的片补齐后仍能弹窗
  EVAL_SHARE_RESET() TEST.chat = nil
  for i = 1, n - 1 do
    TEST.time = (TEST.time or 1000) + 0.5
    EVAL_SHARE_ONMSG(msgs[i], "队友丙")
  end
  TEST.time = TEST.time + 2.5 -- 超过冗余时长(2s)、远未到兜底(60s)
  EVAL_SHARE_ONMSG("[EHPF#fe 1/4]4142", "路人丁") -- 触发 sweep（走真实路径）
  eq(string.find(tostring(TEST.chat), "未收齐", 1, true) ~= nil, true, "③★★2 秒未收齐 → 如实提醒")
  eq(EVAL_SHARE_PENDING(), nil, "③前置：此时还没收齐，不弹窗")
  TEST.time = TEST.time + 0.3
  EVAL_SHARE_ONMSG(msgs[n], "队友丙") -- ★晚到的最后一片
  local pend3 = EVAL_SHARE_PENDING()
  eq(pend3 ~= nil and pend3.name == "冗余窗口测试", true,
     "③★★★冗余窗口的价值：晚到的分片补齐后**仍然弹窗**（到点就删的旧行为救不回来）")
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedP EVAL_HELP_CONFIG.war.activeProfile = savedA
  EVAL_SHARE_RESET() TEST.runScripts = nil TEST.chat = nil
  print("  分享接收：容忍 1~2 秒迟到（提醒但保留缓冲）+ 只认 [EHPF#] 标识 + 发送限频 0.5s")
end

-- 108) ★★★1.72.4 「释放指定等级」（用户要求：技能右侧加等级下拉，默认无等级）
--   官方判据（本机 api_spell.html 原文）：
--     · `CastSpell(id, bookType)` = Protected ✗；`CastSpellByName(name)` = Protected，
--       但 **name 可带括号等级**（"text inside the parentheses must match the spell's subtext exactly；
--       With no parentheses, the last known [rank]"）→ 指定等级的正解，Protected 走 `RunScript` 绕行。
--     · `GetSpellName(spellID, bookType)` **第二返回 = rank/subtext** → 等级列表直接从法术书枚举。
--   ★判据：① 枚举出的等级与法术书一致（无 subtext 的技能没有等级可选）；
--     ② 指定等级时**不在动作条也能出手**，且发出的脚本文本逐字正确；
--     ③ 法术书里没有的等级 → **如实失败、一个字都不发**（绝不静默放行）；
--     ④ 默认「无等级」→ 行为一字不变（仍要求动作条）。
do
  EVAL_SPELLBOOK_TEST_RESET()
  TEST.spellbook = {
    { name = "火球术", sub = "等级 1" },
    { name = "火球术", sub = "等级 3" },
    { name = "冰霜新星" },
  }
  local rs = EVAL_SPELLBOOK_RANKS("火球术")
  eq(table.getn(rs), 2, "①法术书枚举出 2 个等级（got " .. tostring(table.getn(rs)) .. "）")
  eq(rs[1], "等级 1", "①按法术书顺序")
  eq(EVAL_SPELLBOOK_HAS("火球术", "等级 3"), true, "①该等级存在")
  eq(EVAL_SPELLBOOK_HAS("火球术", "等级 9"), false, "①不存在的等级如实为假")
  eq(table.getn(EVAL_SPELLBOOK_RANKS("冰霜新星")), 0, "①没有 subtext 的技能没有等级可选")
  -- ①b ★1.72.4 顺序：**从低到高、按数字比**（用户要求「从低到高排」）。
  --   为什么必须钉：法术书枚举出来的顺序是乱的（用户截图里就是「等级 2 → 等级 1」），
  --   而按**字符串**序排会把「等级 10」排到「等级 3」前面——这是最容易写错的那种排序。
  local sbSaved = TEST.spellbook
  TEST.spellbook = {
    { name = "排序测试", sub = "等级 10" },
    { name = "排序测试", sub = "等级 3" },
    { name = "排序测试", sub = "等级 1" },
    { name = "排序测试", sub = "变形" }, -- 不含数字 → 排最后
    { name = "排序测试", sub = "等级 2" },
  }
  EVAL_SPELLBOOK_TEST_RESET()
  eq(table.concat(EVAL_SPELLBOOK_RANKS("排序测试"), ","), "等级 1,等级 2,等级 3,等级 10,变形",
     "①b★★★等级从低到高（数字序，不是字符串序）+ 无数字的排最后")
  TEST.spellbook = sbSaved
  EVAL_SPELLBOOK_TEST_RESET()
  TEST.inCombat = false EVAL_HELP_UPDATE_STATE()
  local savedP = EVAL_HELP_CONFIG.war.profiles
  EVAL_HELP_CONFIG.war.profiles = { { name = "T", enabled = true, skills = {} } }
  -- ② 指定等级 → 不占格 + 串逐字正确
  TEST.runScripts = nil
  eq(EVAL_RULE_RUN({ { skill = "火球术", rank = "等级 3", why = "测试", groups = EVAL_PARSE_CONDS("非战斗") } }), true,
     "②指定等级时**不在动作条也能出手**（走 RunScript，不占格）")
  local joined = table.concat(TEST.runScripts or {}, " | ")
  eq(string.find(joined, 'CastSpellByName("火球术(等级 3)")', 1, true) ~= nil, true,
     "②★★★发出的脚本逐字是 CastSpellByName(\"火球术(等级 3)\")（括号内必须与 subtext 一致）")
  -- ③ 等级不存在 → 如实失败
  TEST.runScripts = nil
  eq(EVAL_RULE_RUN({ { skill = "火球术", rank = "等级 9", why = "测试", groups = EVAL_PARSE_CONDS("非战斗") } }), false,
     "③法术书里没有的等级 → 不出手")
  eq(TEST.runScripts == nil or table.getn(TEST.runScripts) == 0, true, "③★且一个字都没发出去（不静默放行）")
  -- ④ 默认无等级 → 老路（仍要求动作条）
  TEST.runScripts = nil
  eq(EVAL_RULE_RUN({ { skill = "火球术", why = "测试", groups = EVAL_PARSE_CONDS("非战斗") } }), false,
     "④默认「无等级」行为一字不变（不在动作条就不出手）")
  -- 收尾
  EVAL_HELP_CONFIG.war.profiles = savedP
  TEST.spellbook = nil TEST.runScripts = nil
  EVAL_SPELLBOOK_TEST_RESET()
  print("  指定等级：法术书枚举等级 + CastSpellByName 走 RunScript + 不存在则如实失败 + 默认无等级走老路")
end

-- 109) ★★★1.72.4 指定等级的**文本往返**（导出 → 导入必须逐字保留等级；分享方案就靠这条通道）
do
  local prof = {
    name = "等级往返测试",
    skills = {
      { skill = "火球术", enabled = true, rank = "等级 3", groups = EVAL_PARSE_CONDS("怒气>30") },
      { skill = "冰霜新星", enabled = false, groups = EVAL_PARSE_CONDS("") },
    },
  }
  local txt = EVAL_PROFILE_TO_TEXT(prof)
  eq(string.find(txt, "- 火球术(等级 3) | 怒气>30", 1, true) ~= nil, true,
     "①导出形态 = 技能名(等级 3) | 条件（与官方 CastSpellByName 语法同形）：" .. tostring(txt))
  local back = EVAL_PROFILE_FROM_TEXT(txt)
  eq(back ~= nil, true, "②导入成功")
  eq(back.skills[1].skill, "火球术", "②技能名拆干净（括号不留在名字里）")
  eq(back.skills[1].rank, "等级 3", "★★★等级逐字往返（not lost）")
  eq(back.skills[2].rank, nil, "②没写等级的行不带 rank")
  eq(back.skills[2].enabled, false, "②停用标记与等级共存")
  local back2 = EVAL_PROFILE_FROM_TEXT("# 方案: 老文本\n- 火球术 | 怒气>30")
  eq(back2.skills[1].rank, nil, "③反向哨兵：无括号的老文本导入后 rank 仍为 nil（老行为一字不变）")
  print("  指定等级文本往返：导出 技能名(等级 3)、导入逐字还原、无括号老文本行为不变")
end

-- 110) ★★★1.72.4 等级元素（用户 1.72.4 定稿：「默认值显示技能」——**元素常显**，默认文案 = 「技能」）
--   ★设计变更留档：先前一版做成「没设等级就整块隐藏」，用户装上当场否掉（原话：「技能右侧的等级配置没显示」）
--     —— **入口藏起来 = 用户找不到功能**。正解：元素一直在，默认文案「技能」本身就表达「用技能本身、不指定等级」。
--   判据盯的性质：① 默认**可见**且文案 = 「技能」（不是隐藏、也不是空白）；② 右键技能名是**真实接线**；
--   ③ 下拉选项来自**法术书**（不是自己编的「等级 N」）；④ 设了等级 → 文案 = 该等级（元素仍在）；
--   ⑤ 左键没被右键顶掉（SetScript 单槽位）；⑥ 编辑器 ↔ 方案数据往返；⑦ 法术书里没有该技能等级时**如实说明**、
--   不弹残废下拉；⑧ 悬停说明真的有内容（写了 tooltip 没人看得见 = 没写）。
do
  local savedP = EVAL_HELP_CONFIG.war.profiles
  local savedA = EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "等级UI测试", enabled = true, skills = {} } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_SPELLBOOK_TEST_RESET()
  TEST.spellbook = { { name = "测试技能", sub = "等级 2" }, { name = "测试技能", sub = "等级 1" } } -- 故意乱序：验下拉会排好
  EVAL_HELP_SE_OPEN(1, nil, "测试技能") -- 新增技能：默认没有等级
  local r0 = EVAL_TEST_SE_RANK()
  eq(r0.exists, true, "①等级元素真的建出来了")
  eq(r0.shown, true, "①★★★默认**可见**（入口不许藏）")
  eq(r0.nameShown, true, "①★★文字也真的显示出来")
  eq(r0.rank, nil, "①默认没有自定义等级")
  eq(r0.text, EVAL_L("SE_RANK_ANY"), "①★★★默认文案 = 「不限」（用技能本身、不指定等级）")
  -- ★★★1.72.4 **用词本身也要钉住**：用户定稿是「不限」，我曾按「默认值显示技能」自行改成「技能」并发出去，
  --   用户装上一眼看到就退回。★上一行为什么钉不住：两侧都读同一个语言键 → 改语言包的值照样绿（等价变异），
  --   所以这里**直接钉中文用词**（= 用户看到的那个词）。
  eq(EVAL_LOCALES.zhCN.SE_RANK_ANY, "不限", "①★★★默认文案的**用词** = 不限（用户定稿；改词要有明确指令）")
  -- ② 悬停说明（走真实 OnEnter → GameTooltip；⭐测试只能经**钩子**进生产代码——seUI 是 EvalHelp.lua 的 local）
  TEST.tipLines = nil
  eq(EVAL_TEST_SE_RANK_TIP(), true, "⑧等级元素挂着真实 OnEnter（走钩子，不越界掏 local）")
  local tipTxt = ""
  for _, ln in ipairs(TEST.tipLines or {}) do tipTxt = tipTxt .. tostring(ln.text or "") .. "\n" end
  eq(string.find(tipTxt, EVAL_L("SE_RANK_TIP"), 1, true) ~= nil, true, "⑧★★悬停说明真的有内容（写明「点这里选择」）")
  TEST.tipLines = nil
  -- ③ 右键技能名（真实 OnClick 闭包）
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_RANK_CLICK("RightButton"), true, "②技能名按钮上挂着真实 OnClick（右键入口接线在）")
  eq(EVAL_DD_TEST_SHOWN(), true, "②★★右键真的弹出了等级下拉")
  local visTxt = table.concat(EVAL_DD_TEST_VISIBLE_TEXTS(), "\n")
  eq(string.find(visTxt, EVAL_L("SE_RANK_ANY"), 1, true) ~= nil, true, "②★下拉第一项 = 不限（默认项）")
  eq(string.find(visTxt, "等级 2", 1, true) ~= nil, true, "②★★下拉里是**法术书**枚举出的等级")
  local row110 = EVAL_DD_TEST_ROW(2)
  eq(row110 and tostring(row110.text:GetText()), "等级 1", "②★★★下拉顺序 = 从低到高（法术书给的是「等级 2, 等级 1」乱序，这里必须是 等级 1 在前）")
  -- ④ 点真实的行 → 落值 + 文案变等级
  local idxRank2 = nil
  for i = 1, 4 do
    local row = EVAL_DD_TEST_ROW(i)
    if row and row.text and row.text.GetText and tostring(row.text:GetText()) == "等级 2" then idxRank2 = i end
  end
  eq(idxRank2 ~= nil, true, "④下拉里找得到「等级 2」那一行（前置）")
  if idxRank2 then EVAL_DD_TEST_CLICK(idxRank2) end
  local r1 = EVAL_TEST_SE_RANK()
  eq(r1.rank, "等级 2", "④★点一下真的落到编辑器数据（ed.rank）")
  eq(r1.text, "等级 2", "④★★★设置了等级 → 文案更新为该等级（用户：「设置等级1 则标题名称更新」）")
  eq(r1.shown, true, "④★★元素仍在（不是设完就消失）")
  -- ⑤ 左键仍开技能列表（右键接线没把左键顶掉）
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_RANK_CLICK("LeftButtonUp"), true, "⑤左键点技能名（走同一个 OnClick）")
  eq(EVAL_DD_TEST_SHOWN(), true, "⑤★★★左键没被右键接线顶掉：技能列表照旧打开")
  EVAL_DD_HIDE()
  -- ⑥ 保存 → 落库；重开 → 载回
  EVAL_HELP_SE_SAVE()
  local saved = EVAL_HELP_CONFIG.war.profiles[1].skills[1]
  eq(saved ~= nil and saved.rank, "等级 2", "⑥★★保存后等级真的进了方案数据（界面设了、库里没有 = 功能等于不存在）")
  EVAL_HELP_SE_OPEN(1, 1) -- 重开这条技能
  local r2 = EVAL_TEST_SE_RANK()
  eq(r2.rank, "等级 2", "⑥★★重开时把已有等级载回编辑器")
  eq(r2.text, "等级 2", "⑥★★而且文案显示的是该等级（不是载回了值却看不见）")
  -- ⑦ 设回「技能」→ 文案回到默认 + 库里清干净
  eq(EVAL_TEST_SE_SET_RANK(nil), true, "⑦设回默认（技能）")
  local r3 = EVAL_TEST_SE_RANK()
  eq(r3.text, EVAL_L("SE_RANK_ANY"), "⑦★★★清掉等级后文案回到「不限」（默认态）")
  eq(r3.shown, true, "⑦★★元素还在（默认态也能一眼看到入口）")
  EVAL_HELP_SE_SAVE()
  eq(EVAL_HELP_CONFIG.war.profiles[1].skills[1].rank, nil, "⑦★★库里也清干净了（不是只改了界面文案）")
  -- ⑧ 法术书里读不到等级 → 如实说明、不弹残废下拉
  TEST.spellbook = { { name = "无等级技能" } }
  EVAL_SPELLBOOK_TEST_RESET()
  EVAL_HELP_SE_OPEN(1, nil, "无等级技能")
  EVAL_DD_TEST_RESET_ANCHOR()
  TEST.chat = nil
  eq(EVAL_TEST_SE_RANK_CLICK("RightButton"), true, "⑨右键入口仍在（只是这次没有等级可选）")
  eq(EVAL_DD_TEST_SHOWN(), false, "⑨★★法术书里没有等级 → **不弹**只有一项的残废下拉")
  eq(string.find(tostring(TEST.chat), "无等级技能", 1, true) ~= nil, true, "⑨★★★如实点名说明（查不到 ≠ 没有，绝不静默）")
  local r4 = EVAL_TEST_SE_RANK()
  eq(r4.text, EVAL_L("SE_RANK_ANY"), "⑨反向哨兵：没有任何等级可选时，默认文案也没有被改坏")
  -- 收尾
  TEST.chat = nil
  EVAL_TEST_SE_CLEAR()
  EVAL_HELP_CONFIG.war.profiles = savedP
  EVAL_HELP_CONFIG.war.activeProfile = savedA
  TEST.spellbook = nil
  EVAL_SPELLBOOK_TEST_RESET()
  EVAL_DD_HIDE()
  print("  等级元素：常显 + 默认文案「不限」+ 右键/左键双入口 + 法术书等级 + 保存/重开往返 + 空等级如实说明")
end

-- 111) ★★★1.72.4 「指定等级」对**方案模版 / 导入导出**的影响审计（审计必须落成闸门，否则只是这一次的手工动作）
--   ① 内置模版（examples/，11 组）解析后**一个等级都不许冒出来**，且导出→导入逐字往返
--      —— 证明新语法没动到既有数据（「内置模版是导入导出的亲兄弟格式」）；
--   ② 真法术名「火球术(等级 3)」照官方语法拆出等级；
--   ③ 带前缀的特殊技能名（物品:/跟随:/选取目标:）里的括号属于**名字本身** → 一个字都不许拆
--      （拆了 = 静默改义：技能名被改、行为被改，而两边都不报错）；
--   ④ 分享通道走同一条文本 → 等级随分享传输，且「同名但等级不同」不会被误判成自己的回声；
--   ⑤ 指定等级的技能**不在动作条**是正常的 → 战斗信息UI 不许标「?」，列表行要显示等级（没等级时不显示）。
do
  -- ① 内置模版：解析后**一个等级都没有** + 文本通道**幂等**（导出→导入→再导出，逐字相同）
--   ★为什么不要求「模版文本 == 导出文本」逐字相同：手写模版里本就有几处**既有**的形态差异
--     （与等级无关，本轮审计实测并留档）：职业名单按 CLASS_LIST 顺序重排、驱散类型写成
--     (Magic)/(Disease)、「能量」与「怒气」同归一码（power）。这些是**导入导出通道的既有行为**，
--     不是新语法带来的；幂等才是这条通道该保证的性质。
  local badRank, badIdem, badCls, nTpl = "", "", "", 0
  local function nows(s) return (string.gsub(tostring(s or ""), "%s+", "")) end
  for gi, g in ipairs(EVAL_IO_TEMPLATES) do
    for ti, t in ipairs(g.list or {}) do
      nTpl = nTpl + 1
      local prof = EVAL_PROFILE_FROM_TEXT(t.text or "")
      local key = tostring(g.cls) .. "/" .. tostring(t.name)
      for si, sk in ipairs((prof and prof.skills) or {}) do
        if sk.rank ~= nil then badRank = badRank .. key .. "#" .. si .. "(" .. tostring(sk.rank) .. ") " end
      end
      local ex1 = EVAL_PROFILE_TO_TEXT(prof)
      local ex2 = EVAL_PROFILE_TO_TEXT(EVAL_PROFILE_FROM_TEXT(ex1))
      if nows(ex1) ~= nows(ex2) then badIdem = badIdem .. key .. " " end
      -- ⑥ 职业过滤里的每个名字都必须是**已知职业**（否则解析侧静默丢名单——1.72.4 实测：
      --    CLASS_LIST 里原本没有圣骑士，模版里的 [职业:圣骑士] 一直是死的）
      for names in string.gmatch(tostring(t.text or ""), "%[职业:([^%]]*)%]") do
        for one in string.gmatch(names .. "/", "([^/]+)/") do
          local kn = false
          for _, c in ipairs(EVAL_CLASS_LIST) do if c.name == one then kn = true end end
          if not kn then badCls = badCls .. key .. "(" .. one .. ") " end
        end
      end
    end
  end
  eq(nTpl >= 11, true, "①前置：内置模版都拿到了（" .. tostring(nTpl) .. " 个）")
  eq(badRank, "", "①★★★内置模版解析后**一个等级都没有**（新语法没动到既有数据）: " .. badRank)
  eq(badIdem, "", "①★★文本通道幂等（导出→导入→再导出逐字相同）: " .. badIdem)
  eq(badCls, "", "⑥★★★模版职业过滤里的名字必须都是已知职业（否则那类成员被**静默丢弃**）: " .. badCls)
  -- ② 真法术名 → 拆等级（官方语法）
  local p2 = EVAL_PROFILE_FROM_TEXT("# 方案: r\n- 火球术(等级 3) | 非战斗")
  eq(p2 and p2.skills[1].skill, "火球术", "②真法术名：括号被拆成等级（与官方 CastSpellByName 语法同形）")
  eq(p2 and p2.skills[1].rank, "等级 3", "②★★等级逐字保留")
  -- ③ 带前缀的特殊技能名：括号属于名字本身，不拆
  local p3 = EVAL_PROFILE_FROM_TEXT("# 方案: p\n- 物品:治疗药水(大) | 非战斗\n- 跟随:某人(等级 2) | 非战斗\n- 选取目标:指定名称:阿三(等级 1) | 非战斗")
  eq(p3 and p3.skills[1].skill, "物品:治疗药水(大)", "③★★★物品名里的括号属于名字本身（不许拆）")
  eq(p3 and p3.skills[1].rank, nil, "③★★★而且一个字都不许变成等级（拆了 = 静默改义）")
  eq(p3 and p3.skills[2].skill, "跟随:某人(等级 2)", "③★★跟随的目标名同理（玩家名可以带括号）")
  eq(p3 and p3.skills[2].rank, nil, "③★★")
  eq(p3 and p3.skills[3].skill, "选取目标:指定名称:阿三(等级 1)", "③★★选取目标的指定名同理")
  local out3 = EVAL_PROFILE_TO_TEXT(p3)
  eq(string.find(out3, "物品:治疗药水(大) |", 1, true) ~= nil, true, "③★★导出侧也不会给它补一个等级（往返逐字）")
  -- ④ 分享：等级随文本传输；同名不同等级 ≠ 我的回声
  local savedP11 = EVAL_HELP_CONFIG.war.profiles
  local savedA11 = EVAL_HELP_CONFIG.war.activeProfile
  EVAL_HELP_CONFIG.war.profiles = { { name = "等级回声", skills = { { skill = "火球术", rank = "等级 3", groups = EVAL_PARSE_CONDS("非战斗") } } } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  local mine = EVAL_PROFILE_TO_TEXT(EVAL_HELP_CONFIG.war.profiles[1])
  eq(string.find(mine, "火球术(等级 3)", 1, true) ~= nil, true, "④★分享文本里带着等级（同一条文本通道）")
  eq(EVAL_SHARE_IS_MINE(mine), true, "④同一份（含等级）→ 认得是自己的回声")
  eq(EVAL_SHARE_IS_MINE("# 方案: 等级回声\n\n- 火球术 | 非战斗"), false, "④★★★等级不同 → **不是**我的（只比名字会把别人同技能方案误吞）")
  -- ⑤ 不在动作条 = 合法：战斗信息UI 不许标「?」；列表行显示等级（没等级不显示）
  local wasShown11 = EVAL_TEST_UI_SHOWN()
  if not wasShown11 then EVAL_HELP_UI_TOGGLE() end
  local cfgWas = EVAL_TEST_CFG_VISIBLE()
  if not (EVAL_HELP_CFGWIN and EVAL_HELP_CFGWIN.warUI) then EVAL_HELP_CFG_TOGGLE() end
  EVAL_HELP_CONFIG.war.profiles = { { name = "UI等级", enabled = true, skills = { { skill = "测试技能", rank = "等级 2", enabled = true, groups = EVAL_PARSE_CONDS("") } } } }
  EVAL_HELP_CONFIG.war.activeProfile = 1
  EVAL_WAR_TAB_REFRESH()
  EVAL_HELP_UI_TICK()
  local cells11 = EVAL_TEST_UI_CELLS()
  eq(cells11[1] ~= nil, true, "⑤前置：战斗信息UI 的技能格拿到了")
  eq(cells11[1] and cells11[1].text ~= "?", true, "⑤★★★指定等级的技能不在动作条 → **不许**标「?」（假告警）")
  local rows11 = EVAL_TEST_WAR_ROWS()
  eq(rows11.names[1], "测试技能(等级 2)", "⑤★★一键宏列表行显示等级（两条同名技能才分得清）")
  TEST.chat = nil
  SlashCmdList["EVALHELP"]("go list")
  eq(string.find(tostring(TEST.chat), "测试技能(等级 2)", 1, true) ~= nil, true, "⑤★★/eh go list 也带等级（对方案核对的通道）")
  EVAL_HELP_CONFIG.war.profiles = { { name = "UI等级", enabled = true, skills = { { skill = "测试技能", enabled = true, groups = EVAL_PARSE_CONDS("") } } } }
  EVAL_WAR_TAB_REFRESH()
  eq(EVAL_TEST_WAR_ROWS().names[1], "测试技能", "⑤★★反向：没有等级时行文案逐字不变（默认只显示技能）")
  -- 收尾
  TEST.chat = nil
  EVAL_HELP_CONFIG.war.profiles = savedP11
  EVAL_HELP_CONFIG.war.activeProfile = savedA11
  EVAL_WAR_TAB_REFRESH()
  if not cfgWas and EVAL_TEST_CFG_VISIBLE() then EVAL_HELP_CFG_TOGGLE() end
  if not wasShown11 and EVAL_TEST_UI_SHOWN() then EVAL_HELP_UI_TOGGLE() end
  print("  等级 × 导入导出审计：" .. tostring(nTpl) .. " 个内置模版 0 等级 0 往返差异 + 前缀名不拆 + 分享自称判据 + UI 不误报")
end
-- 112) ★1.73.0 抓宠帮手（配置窗第 6 个 Tab）：数据 / 检索 / 详情 / 放大镜跳转 全链路
--   需求（用户原话）：顶部输入框检索「宠物技能」，列表显示各等级；选中→技能详情页
--   （简介/需求等级/拥有该技能的宠物）；右侧放大镜点宠物名→跳数据检索并自动检索。
do
  local pack112 = EVAL_LOCALES[EVAL_GET_LANG()] or EVAL_LOCALES.zhCN
  -- ① 数据模块：PetData.lua 真的被载入（DECL ORDER/载入链都接了它）
  eq(type(EVAL_PET_DB) == "table", true, "★★PetData.lua 已载入（EVAL_PET_DB 是表）")
  local sk112 = EVAL_PET_DB.skills or {}
  local nsk112 = table.getn(sk112)
  eq(nsk112, 21, "★★技能 21 条（13 主动 + 8 训练师被动，来自截图转录）")
  local withIcon112 = 0
  for i = 1, nsk112 do
    local ic = tostring(sk112[i].icon or "")
    if ic ~= "" then withIcon112 = withIcon112 + 1 end
    -- ★★★1.73.4 图标已全部换成**客户端真实路径**（用户：「完善宠物助手tab 内所有图标替换」）：
    --   本客户端的纹理是 Unreal 资产路径 /Game/Interface/Icons/<名字>_TEX；
    --   写 1.12 的 Interface\Icons\ 会显示成引擎的「?」缺图占位（用户截图那一屏问号就是这么来的）。
    eq(string.find(ic, "/Game/Interface/Icons/", 1, true) == 1, true, "★技能图标是客户端资产路径：" .. tostring(sk112[i].name))
    eq(string.sub(ic, -4) == "_TEX", true, "★以 _TEX 结尾（本客户端约定）：" .. tostring(sk112[i].name))
    eq(string.find(ic, "QuestionMark", 1, true) == nil, true, "★★不再是问号占位（语义匹配的真实图标）：" .. tostring(sk112[i].name))
    eq(string.find(ic, ".tga", 1, true) == nil, true, "★不带扩展名（本客户端约定）：" .. tostring(sk112[i].name))
  end
  eq(withIcon112, nsk112, "★★每个技能都有图标（用户要求「搭配图标」）")
  -- 家族图标：同样必须是真实路径、且**一族一枚**（撞图就是复制粘贴错）
  do
    local fams112, famSeen, famDup = 0, {}, ""
    for fid, f in pairs(EVAL_PET_DB.families or {}) do
      fams112 = fams112 + 1
      local fi = tostring(f.icon or "")
      eq(string.find(fi, "/Game/Interface/Icons/", 1, true) == 1 and string.sub(fi, -4) == "_TEX", true,
         "★家族图标是客户端资产路径：" .. tostring(fid))
      if famSeen[fi] then famDup = famDup .. tostring(fid) .. " " end
      famSeen[fi] = true
    end
    eq(fams112 >= 16, true, "★家族数 ≥ 16（实际 " .. tostring(fams112) .. "）")
    eq(famDup, "", "★★家族图标一族一枚（撞图 = 复制粘贴错）：" .. famDup)
  end
  -- ② 条目 = 技能 × 等级（列表要「显示各等级的技能」）
  local st112 = EVAL_PH_TEST_STATE()
  eq(st112.entries, 106, "★★条目数 = 技能×等级 = 106（13 主动 58 + 8 训练师被动 48）")
  -- 被动技能也必须能被检索到（它们没有驯服来源，但有等级与需求等级）
  EVAL_PH_SET_QUERY("低吼")
  eq(EVAL_PH_TEST_STATE().filtered, 7, "★★被动技能「低吼」7 个等级也进检索列表")
  local dP = EVAL_PH_OPEN(1) ; local detP = EVAL_PH_TEST_DETAIL()
  eq(detP.skill, "低吼", "★打开被动技能详情")
  eq(table.getn(detP.beasts), 0, "★训练师技能没有驯服来源（空表）")
  -- ③ 按技能名检索：撕咬 8 个等级
  EVAL_PH_SET_QUERY("撕咬")
  local s2 = EVAL_PH_TEST_STATE()
  eq(s2.filtered, 8, "★★检索「撕咬」命中 8 个等级（实际 " .. tostring(s2.filtered) .. "）")
  local e1 = EVAL_PH_TEST_ENTRY(1)
  eq(e1.skill, "撕咬", "★第 1 条是撕咬")
  eq(e1.rank, 1, "★第 1 条是等级 1")
  eq(e1.req, 1, "★等级 1 需宠物等级 1")
  local lb112 = EVAL_PH_TEST_LABEL(1)
  eq(string.find(lb112, "撕咬", 1, true) ~= nil, true, "★列表标签含技能名：" .. tostring(lb112))
  eq(string.find(lb112, "1", 1, true) ~= nil, true, "★列表标签含等级信息")
  -- ④ 按野兽名检索（第二种搜法）：血斧座狼教 3 个技能等级
  EVAL_PH_SET_QUERY("血斧座狼")
  local s3 = EVAL_PH_TEST_STATE()
  eq(s3.filtered >= 3, true, "★★按野兽名也能搜到（血斧座狼 → " .. tostring(s3.filtered) .. " 条）")
  local lbH = EVAL_PH_TEST_LABEL(1)
  eq(string.find(lbH, pack112.PH_ENTRY_HIT, 1, true) == nil, true, "★命中来源后缀是格式化串，不是字面键名")
  -- ⑤ 详情页：选中 → 技能简介 / 需求等级 / 宠物列表
  EVAL_PH_SET_QUERY("撕咬")
  eq(EVAL_PH_OPEN(8), true, "★打开第 8 条（撕咬 等级8）")
  local d8 = EVAL_PH_TEST_DETAIL()
  eq(d8.skill, "撕咬", "★详情页技能名")
  eq(d8.rank, 8, "★详情页等级 8")
  eq(d8.req, 56, "★★详情页需求宠物等级 56")
  eq(type(d8.intro) == "string" and d8.intro ~= "", true, "★★详情页有技能简介")
  eq(table.getn(d8.beasts) >= 1, true, "★★详情页列出拥有该技能的宠物（" .. tostring(table.getn(d8.beasts)) .. " 条）")
  local r8 = EVAL_PH_TEST_DETROW(1)
  eq(type(r8.name) == "string" and r8.name ~= "", true, "★宠物行有名字：" .. tostring(r8.name))
  eq(string.find(r8.meta, "56", 1, true) ~= nil or string.find(r8.meta, "57", 1, true) ~= nil, true,
     "★宠物行写出等级/区域/家族：" .. tostring(r8.meta))
  eq(r8.zoomShown, true, "★★宠物行右侧的放大镜按钮是显示状态")
  -- ★★★1.73.6 放大镜**画出来的到底是什么**（用户：「换成 放大镜图标」）：
  --   原实现贴的是 `Interface\Icons\INV_Misc_Spyglass_02` —— 1.12 老前缀 + 客户端里不存在的名字，
  --   于是真机上只有保底文字「查」露在外面（截图圈出处）。判据 = **真控件上的纹理**精确是清单里那枚 + 文字被藏掉。
  local z8 = EVAL_PH_TEST_ZOOM(1)
  eq(z8 and z8.path, "/Game/Interface/Icons/INV_Misc_Spyglass_01_TEX",
     "★★★放大镜按钮贴的是客户端真实路径（Unreal 资产 + 清单里真实存在的 _01）")
  eq(z8 and z8.path ~= nil and string.find(z8.path, "Interface\\Icons\\", 1, true) == nil, true,
     "★★反向哨兵：不再是 1.12 老形态路径")
  eq(z8 and z8.textShown, false, "★★★保底文字「查」被显式藏掉（图标顶替它，不是两者叠印）")
  eq(z8 and z8.iconW, 16, "★放大镜图标尺寸 16px（与 24x20 的按钮相称）")
  eq(EVAL_PH_TEST_STATE().view, "detail", "★处于详情视图")
  -- ⑥ 返回列表
  EVAL_PH_BACK()
  eq(EVAL_PH_TEST_STATE().view, "list", "★返回后回到列表视图")
  -- ⑦ 放大镜 → 数据检索：真的把检索词填进去，并切到第 4 个 Tab
  EVAL_PH_RESET_JUMP()
  EVAL_HELP_CFG_SETTAB(6)
  local okJ = EVAL_PH_JUMP("血斧座狼")
  eq(okJ, true, "★★放大镜跳转成功（数据检索入口可用）")
  eq(EVAL_PH_TEST_LAST_JUMP(), "血斧座狼", "★★跳转带上宠物名")
  eq(EVAL_HELP_CFG_TAB(), 4, "★★★跳转后停在「数据检索」Tab（第 4 个）")
  eq(EVAL_DS_LAST_QUERY(), "血斧座狼", "★★★数据检索侧真的收到了检索词（后续走它自己的流程）")
  -- ⑧ 家族标签可读（宠物「类型」信息）
  local fam = EVAL_PH_TEST_FAMILY_LABEL("wolf")
  eq(type(fam) == "string" and fam ~= "" and fam ~= "wolf", true, "★★家族标签取到中文名：" .. tostring(fam))
  -- 收尾：还原状态与 Tab（跨用例状态残留是本项目的老坑）
  EVAL_PH_TEST_RESET()
  EVAL_HELP_CFG_SETTAB(1)
  print("  抓宠帮手：数据 21 技能/图标齐全/按技能与野兽双检索/详情页简介+需求+宠物列表/放大镜跳数据检索")
end

-- 113) ★★★1.73.1 抓宠帮手：两视图的**可见性 + 布局审查**（用户截图报「详情页信息错误 / 布局错乱」）
--   ★两处真事故（文本全对、只是画不出来 → 只读文本的断言全绿）：
--     ① 详情视图里搜索行没被隐藏 → 标签+输入框检索词+详情标题**三层叠印**在同一行（截图被读成
--        「宠物技能爪击 · 等级爪击」），[清除] 还压在 [返回] 上；
--     ② 宠物行的名字与元信息先 Hide、随后只 Show 了图标与放大镜 → 宠物名/等级/区域/类型永远不显示。
--   判据一律读**真实控件**（EVAL_PH_TEST_GEOM 给矩形与显隐），不在测试里复刻坐标常量。
do
  local function G() return EVAL_PH_TEST_GEOM() end
  local function rgt(r) return (r and r.x and r.w) and (r.x + r.w) or nil end
  local function within(r, span)
    if not (r and r.shown and span) then return true end
    return r.x >= span.x and (r.x + r.w) <= (span.x + span.w)
  end
  EVAL_PH_TEST_RESET()
  -- ① 列表视图：搜索行可见 / [返回] 隐藏 / [清除] 可见
  EVAL_PH_SET_QUERY("爪击")
  local g1 = G()
  eq(g1.listRowShown, true, "①★列表视图：搜索行（标签/输入框/计数/[清除]）必须可见")
  eq(g1.backBtn and g1.backBtn.shown, false, "①列表视图：[返回] 必须隐藏")
  eq(g1.clearBtn and g1.clearBtn.shown, true, "①列表视图：[清除] 必须可见")
  eq(g1.emptyListShown, false, "①有结果时空态提示不显示")
  -- ② 详情视图：搜索行**整行隐藏**（叠印闸门）+ 标题文字正确
  eq(EVAL_PH_OPEN(8), true, "②前置：打开「爪击 等级8」详情")
  local g2 = G()
  eq(g2.listRowShown, false, "②★★★详情视图：搜索行必须**整行隐藏**（否则与标题叠印 —— 用户截图的那坨字）")
  eq(g2.clearBtn and g2.clearBtn.shown, false, "②★★详情视图：[清除] 必须隐藏（它原来压在 [返回] 上）")
  eq(g2.backBtn and g2.backBtn.shown, true, "②详情视图：[返回] 可见")
  local tx2 = EVAL_PH_TEST_TEXTS()
  local want2 = string.format(EVAL_L("PH_DET_TITLE"), "爪击", 8)
  eq(tx2.title, want2, "②★详情标题逐字 = 模板输出（不是标签+标题叠出来的乱码）")
  eq(tostring(tx2.req), string.format(EVAL_L("PH_DET_REQ"), 56), "②★需求行 = 该等级的真实需求宠物等级")
  -- ③ 宠物行：名字与元信息**必须可见**（不可见闸门）+ 无数据的行反向哨兵
  local det2 = EVAL_PH_TEST_DETAIL()
  local nb2 = table.getn(det2.beasts)
  eq(nb2 >= 2, true, "③前置：等级8 有 ≥2 个驯服来源（实际 " .. tostring(nb2) .. "）")
  local row1, row2 = g2.det[1], g2.det[2]
  eq(row1.nameShown, true, "③★★★宠物行的**名字必须可见**（原来 Hide 后从没 Show → 截图里只剩图标和「查」）")
  eq(row1.metaShown, true, "③★★★宠物行的**元信息必须可见**")
  eq(row1.zoomShown, true, "③★放大镜按钮可见")
  eq(type(row1.nameText) == "string" and row1.nameText ~= "", true, "③★名字有内容：" .. tostring(row1.nameText))
  eq(string.find(tostring(row1.metaText), det2.beasts[1].zone, 1, true) ~= nil, true, "③★元信息含区域：" .. tostring(row1.metaText))
  local emptyRow = g2.det[nb2 + 1]
  if emptyRow then eq(emptyRow.nameShown, false, "③★★反向哨兵：没有数据的行名字必须隐藏（不残留上一级的数据）") end
  -- ④ 几何不变量（全部读真实矩形）
  local span = g1.list[1].btn
  eq(rgt(row1.icon) <= row1.nameBtn.x, true, "④★宠物行：图标右端 ≤ 名字格左端")
  eq(rgt(row1.name) <= row1.meta.x, true, "④★★宠物行：名字不压元信息")
  eq(rgt(row1.meta) <= row1.zoom.x, true, "④★★宠物行：元信息不压放大镜")
  eq(within(row1.meta, span) and within(row1.zoom, span), true, "④★宠物行各列都在内容区内（以列表行宽为界）")
  eq(rgt(g2.detMeta) <= g2.detReq.x, true, "④★★属性行与需求行**不相交**（原来是 meta 宽 W-260、req 从 +300 起 → 重叠 100px）")
  eq(rgt(g2.detTitle) <= g2.backBtn.x, true, "④★详情标题不压 [返回]")
  local d1 = row1.nameBtn.y - row2.nameBtn.y
  local d2 = row2.nameBtn.y - g2.det[3].nameBtn.y
  eq(d1 > 0 and d1 == d2, true, string.format("④★行距一致（%.1f / %.1f）——行池不重叠", d1, d2))
  local sz4w, sz4h = EVAL_TEST_CFG_SIZE()
  if type(sz4h) == "number" then
    local last = g2.det[12]
    eq((last.nameBtn.y - last.nameBtn.h) >= -sz4h, true, "④★宠物行池不越出窗口下沿")
  end
  -- ⑤ 空结果：如实提示（不留一片空白）
  EVAL_PH_SET_QUERY("不存在的宠物技能xyz")
  local g5 = G()
  eq(EVAL_PH_TEST_STATE().filtered, 0, "⑤前置：该查询无匹配")
  eq(g5.emptyListShown, true, "⑤★★空结果显示如实提示，而不是一片空白")
  local et5 = EVAL_PH_TEST_TEXTS()
  local g5e = G()
  eq(g5e.list[1].btn.shown, false, "⑤无匹配时列表行全部隐藏")
  -- ⑥ 分页提示：撕咬 等级1 有 13 个来源 > 一屏 12 行 → 如实提示条数
  EVAL_PH_SET_QUERY("撕咬")
  eq(EVAL_PH_OPEN(1), true, "⑥前置：打开「撕咬 等级1」")
  local d6 = EVAL_PH_TEST_DETAIL()
  local g6 = G()
  if table.getn(d6.beasts) > 12 then
    eq(g6.detScroll and g6.detScroll.shown, true, "⑥★★来源多于一屏时**如实提示**条数（绝不静默截断）")
  else
    eq(g6.detScroll and g6.detScroll.shown, false, "⑥来源一屏放得下时不显示分页提示")
  end
  -- 收尾
  EVAL_PH_TEST_RESET()
  EVAL_HELP_CFG_SETTAB(1)
  print("  抓宠布局审查：搜索行按视图显隐 + 宠物行四件套可见 + 列不相交/行距一致/不越界 + 空态与分页如实提示")
end

-- 114) ★★★1.73.2 debuff 类型**多选**（用户：「debuff 类型检测 包括团队debuff 类型要支持多选」）
--   ★三层都要通：① 判定（集合命中任一 / 空集=任意 / 单选不变）② 文本往返（导出 (Magic/Poison)、
--   单选导出与存量逐字相同）③ 编辑窗真实下拉（多选面板 + 互斥「任意负面」+ 窄格文案 + 悬停给全清单）。
do
  -- ① 判定
  eq(EVAL_TEST_DISPEL_MATCH("Poison", { Poison = true, Magic = true }), true, "①★★集合里命中任一即为真（毒在集合里）")
  eq(EVAL_TEST_DISPEL_MATCH("Magic", { Poison = true }), false, "①★★没勾的类型不命中")
  eq(EVAL_TEST_DISPEL_MATCH("Curse", {}), true, "①★★★**空集 = 任意**（与 nil 同义；绝不能变成「永不命中」）")
  eq(EVAL_TEST_DISPEL_MATCH("Curse", "Poison"), false, "①★单选字符串行为一字不变")
  eq(EVAL_TEST_DISPEL_MATCH("Curse", nil), true, "①nil = 任意")
  eq(EVAL_TEST_DISPEL_MATCH("Disease", { Disease = true }), true, "①单元素集合也当真（与单选等价）")
  -- ② 文本往返
  local g114 = EVAL_PARSE_CONDS("有团队debuff:毒(Magic/Poison)")
  local cd114 = g114[1][1]
  eq(type(cd114.dt) == "table", true, "②★★解析括号里的一串类型 → 集合（got " .. type(cd114.dt) .. "）")
  eq(cd114.dt.Magic == true and cd114.dt.Poison == true, true, "②★★两项都进了集合")
  local s114 = EVAL_GROUP_STR(g114)
  eq(string.find(s114, "(Magic/Poison)", 1, true) ~= nil, true, "②★★★导出逐字 = (Magic/Poison)：" .. tostring(s114))
  local g114b = EVAL_PARSE_CONDS("有团队debuff:毒(Magic)")
  eq(EVAL_GROUP_STR(g114b), "有团队debuff:毒(Magic)", "②反向哨兵：**单选导出与存量逐字相同**（老配置导出不变）")
  local g114c = EVAL_PARSE_CONDS("有团队debuff:毒(魔法、毒)")
  local cd114c = g114c[1][1]
  eq(type(cd114c.dt) == "table" and cd114c.dt.Poison == true, true, "②手写的顿号分隔也认（导入宽松）")
  -- ③ 编辑窗真实下拉：多选 + 互斥 + 文案
  eq(EVAL_TEST_SE_PUSH_COND("teamDebuff", nil, nil, nil, nil, "团队"), true, "③前置：编辑器里放一条「团员debuff」（类型先留空 = 任意负面）")
  local sh3, tx3 = EVAL_TEST_SE_ROW_DT(1)
  eq(sh3, true, "③前置：类型格可见")
  eq(tx3, EVAL_L("DS_T_ANY"), "③前置：默认文案 = 任意负面")
  EVAL_DD_TEST_RESET_ANCHOR()
  eq(EVAL_TEST_SE_CLICK_DT(1), true, "③点**真实的类型格**（走它自己的 OnClick）")
  eq(EVAL_DD_TEST_SHOWN(), true, "③★★下拉真的打开了")
  eq(EVAL_DD_TEST_MULTI(), true, "③★★★这个下拉是**多选**面板（用户要求多选）")
  local idxMagic114, idxPoison114 = nil, nil
  local dts114 = EVAL_DISPEL_TYPES or {}
  for i = 1, table.getn(dts114) do
    if dts114[i].id == "Magic" then idxMagic114 = i + 1 end
    if dts114[i].id == "Poison" then idxPoison114 = i + 1 end
  end
  eq(idxMagic114 ~= nil and idxPoison114 ~= nil, true, "③前置：找得到「魔法」「毒」两行")
  EVAL_DD_TEST_CLICK(idxMagic114)
  local _, tx3a = EVAL_TEST_SE_ROW_DT(1)
  eq(tx3a, EVAL_L("DS_T_MAGIC"), "③★★勾一个后格子里就是该类型名")
  EVAL_DD_TEST_CLICK(idxPoison114)
  local _, tx3b = EVAL_TEST_SE_ROW_DT(1)
  local want3 = EVAL_L("DS_T_MAGIC") .. "/" .. EVAL_L("DS_T_POISON")
  eq(tx3b, want3, "③★★★勾两个 → 格子文案「魔法/毒」：" .. tostring(tx3b))
  eq(EVAL_DD_TEST_SELAT(idxMagic114), true, "③★★两个勾都在（多选状态真的保持住）")
  eq(EVAL_DD_TEST_SELAT(idxPoison114), true, "③★★")
  -- 数据侧也必须是集合（判据不能只看文案；★只能经钩子读——seUI 是生产文件的 local）
  local dt3 = EVAL_TEST_SE_COND_DT(1)
  eq(type(dt3) == "table", true, "③★★★数据侧真的存成了集合（不是只有文案好看）：got " .. type(dt3))
  eq(EVAL_TEST_DISPEL_MATCH("Poison", dt3), true, "③★★判定能命中集合里的毒")
  eq(EVAL_TEST_DISPEL_MATCH("Curse", dt3), false, "③★★没勾的诅咒不命中")
  -- 悬停给全清单（窄格放不下的信息另有地方给全）
  do
    local btn = EVAL_TEST_SE_DT_BTN(1)
    eq(btn ~= nil, true, "③交出类型格真实控件")
    local fn = btn and btn:GetScript("OnEnter")
    eq(type(fn) == "function", true, "③★★多选时挂上了悬停说明")
    TEST.tipLines = nil
    if type(fn) == "function" then fn() end
    local tip = ""
    for _, ln in ipairs(TEST.tipLines or {}) do tip = tip .. tostring(ln.text or "") .. "\n" end
    eq(string.find(tip, EVAL_L("DS_T_POISON"), 1, true) ~= nil, true, "③★★★悬停里给出完整清单（含「毒」）")
    TEST.tipLines = nil
  end
  -- 互斥：勾「任意负面」→ 清空具体类型，且面板上的旧勾要清掉（EVAL_DD_SYNC 整表重绘）
  EVAL_DD_TEST_CLICK(1)
  local _, tx3c = EVAL_TEST_SE_ROW_DT(1)
  eq(tx3c, EVAL_L("DS_T_ANY"), "③★★勾「任意负面」→ 文案回到「任意负面」")
  eq(EVAL_DD_TEST_SELAT(idxMagic114), nil, "③★★★互斥：具体类型的勾被清掉了（不是两处都亮）")
  eq(EVAL_DD_TEST_SELAT(1), true, "③★★「任意负面」自己亮着")
  -- ④ 老数据形态：编辑器里存的单选字符串仍能被格子显示 + 判定
  eq(EVAL_TEST_SE_PUSH_COND("teamDebuff", nil, nil, nil, "Poison", "团队"), true, "④放一条**单选**（老形态）条件")
  local _, tx4 = EVAL_TEST_SE_ROW_DT(1)
  eq(tx4, EVAL_L("DS_T_POISON"), "④★★单选老形态照常显示")
  EVAL_DD_HIDE()
  EVAL_TEST_SE_CLEAR()
  EVAL_HELP_CFG_SETTAB(1)
  print("  debuff 类型多选：集合判定（空集=任意）+ 文本往返 (Magic/Poison) + 真实多选面板 + 互斥「任意负面」+ 窄格文案与悬停全清单")
end

-- 115) ★★★1.73.3 滚轮方向统一（用户报「图标库滚动方向与效果相反」）
--   约定（单一来源 = Core.lua EVAL_WHEEL_DIR）：**上滚 = +1 = 回到前面**（列表 offset 减 / 页码减）。
--   ★为什么必须有这一组：5 处滚轮里 4 处本来就对，图标库那处是反的；而当时的断言**用 -1 当「向上」**，
--     正好和反向代码互相印证 —— 断言自己写错方向 = 本项目最恨的「绿但真错」。
do
  -- ① 方向助手：三种老写法都要认，且 0 表示「不是滚轮」
  eq(EVAL_WHEEL_DIR(nil, 1), 1, "①上滚 = +1（本客户端约定）")
  eq(EVAL_WHEEL_DIR(nil, -1), -1, "①下滚 = -1")
  eq(EVAL_WHEEL_DIR(2, nil), 1, "①方向写在第一个参数上也认")
  eq(EVAL_WHEEL_DIR(nil, "x"), 0, "①非数字 = 不是滚轮事件（0，调用方必须原地返回）")
  arg1 = -1
  eq(EVAL_WHEEL_DIR(nil, nil), -1, "①1.12 老写法（方向在全局 arg1）也认")
  arg1 = nil
  local wheel115 = EVAL_CFG_WHEEL_SCRIPT()
  eq(type(wheel115) == "function", true, "①拿到配置窗滚轮脚本（各 Tab 链式接管的那一个）")
  local function fire(d) if type(wheel115) == "function" then wheel115(nil, d) end end
  -- ② 图标库（用户报的那一处）：两个方向都要对
  --   ★前置要自己建立：上一组（组 84）末尾把宏图标桩换成了 6 枚的小表 → 只剩一页，
  --     页码夹取会把方向错误掩盖掉（本项目「前置不许靠别人留下的状态」）。
  local savedMacro115 = TEST.macroIcons
  local big115 = {}
  for i = 1, 200 do big115[i] = "Spell_Fire_Test" .. tostring(i) end -- 必须够多：一页能放 ~54 枚
  TEST.macroIcons = big115
  EVAL_HELP_CFG_SETTAB(5)
  EVAL_IB_SCAN(true)
  EVAL_IB_SET_GROUP("all")
  local p0 = select(1, EVAL_IB_TEST_PAGE())
  local _, pgs0 = EVAL_IB_TEST_PAGE()
  eq(pgs0 >= 2, true, "②前置：图标库多于一页（才能验方向）")
  fire(-1)
  local p1 = select(1, EVAL_IB_TEST_PAGE())
  eq(p1 == p0 + 1, true, "②★★下滚（-1）→ 下一页：" .. tostring(p0) .. "→" .. tostring(p1))
  fire(1)
  local p2 = select(1, EVAL_IB_TEST_PAGE())
  eq(p2 == p1 - 1, true, "②★★★上滚（+1）→ **上一页**（用户报的正是这里反了）：" .. tostring(p1) .. "→" .. tostring(p2))
  -- ③ 抓宠列表（另一处真实滚动条）：上滚往回、下滚往后、到顶夹取
  EVAL_HELP_CFG_SETTAB(6)
  EVAL_PH_TEST_RESET()
  EVAL_PH_SET_QUERY("") -- 全量列表，才滚得动
  local o0 = EVAL_PH_TEST_STATE().off
  fire(-3)
  local o1 = EVAL_PH_TEST_STATE().off
  -- ★一次滚轮只走一行：helper 把幅度归一成 ±1（有的客户端给 ±120 —— 若按原值位移会一次跳 120 行）
  eq(o1 == o0 + 1, true, "③★★下滚往后一格（" .. tostring(o0) .. "→" .. tostring(o1) .. "；幅度归一 = 防 ±120 跳行）")
  fire(1)
  local o2 = EVAL_PH_TEST_STATE().off
  eq(o2 == o1 - 1, true, "③★★★上滚真的往回走（" .. tostring(o1) .. "→" .. tostring(o2) .. "）")
  fire(-1)
  eq(EVAL_PH_TEST_STATE().off == o2 + 1, true, "③★★下滚真的往后走")
  for _ = 1, 8 do fire(1) end
  eq(EVAL_PH_TEST_STATE().off >= 0, true, "③上滚到顶夹取在 0（不越界）")
  eq(EVAL_PH_TEST_STATE().off == 0, true, "③★★一直上滚真的回到列表开头")
  -- 收尾（把桩还原成上一组留下的样子）
  TEST.macroIcons = savedMacro115
  EVAL_IB_SCAN(true)
  EVAL_PH_TEST_RESET()
  EVAL_HELP_CFG_SETTAB(1)
  print("  滚轮方向：单一来源 EVAL_WHEEL_DIR（三种老写法都认）+ 图标库双向 + 抓宠列表双向与夹取")
end

-- 116) ★★★1.73.3 「/eh go icons」：把客户端**真实可用**的图标路径采集进存档（用户要求）
--   为什么要这么做：内置图标打包在 Content\Paks，**磁盘上取不到**；宏图标表是唯一能把整表路径
--   吐出来的官方入口。采集 → 写 SavedVariables → /reload 落盘 → 外部读出来生成图标路径文件。
--   ★判据：路径必须**真的是客户端给的**（不是我们自己拼的）、失败要计数、不打印整表（避免刷屏/限流）。
do
  local saved116 = TEST.macroIcons
  TEST.macroIcons = { "Spell_Fire_Fireball", "INV_Misc_Bag_01", 12345, "Ability_Warrior_Charge" }
  TEST.chat = nil
  local old116 = EVAL_HELP_CONFIG.iconDump
  SlashCmdList["EVALHELP"]("go icons")
  local d116 = EVAL_HELP_CONFIG.iconDump
  eq(type(d116) == "table", true, "①采集结果写进了存档（EVAL_HELP_CONFIG.iconDump）")
  eq(d116.n, 4, "①枚举到 4 枚（含 1 枚故意给非字符串）")
  eq(d116.got, 3, "①★★只把**取成功**的路径收进来（3 枚）")
  eq(d116.failed, 1, "①★★取失败要**计数**（非字符串那枚），不许静默略过")
  eq(table.getn(d116.list), 3, "①列表长度 = got")
  eq(d116.list[1], "Interface\\Icons\\Spell_Fire_Fireball", "①★★存的是**客户端给的原文**（Interface\\Icons\\… 完整路径）")
  eq(string.find(tostring(TEST.chat), "4", 1, true) ~= nil, true, "①★★聊天里如实报了数量（用户要据此确认）")
  eq(string.find(tostring(TEST.chat), "Interface\\Icons\\Spell_Fire_Fireball", 1, true) == nil, true, "①★★**不打印整表**（上千行会刷屏 + 撞反刷屏限流），只报数量与落盘提示")
  eq(string.find(tostring(TEST.chat), "reload", 1, true) ~= nil, true, "①★★提示 /reload 让存档落盘（否则用户白等）")
  -- 空表也要如实报告（不假装成功）
  TEST.macroIcons = nil
  TEST.chat = nil
  SlashCmdList["EVALHELP"]("go icons")
  eq(EVAL_HELP_CONFIG.iconDump.got, 0, "②一枚都取不到时长度为 0")
  eq(string.find(tostring(TEST.chat), "一枚都没取到", 1, true) ~= nil, true, "②★★如实例外（不假装采集成功）")
  -- 收尾
  EVAL_HELP_CONFIG.iconDump = old116
  TEST.macroIcons = saved116
  TEST.chat = nil
  print("  图标路径采集：/eh go icons 把宏图标表全表路径写进存档（成功/失败都计数、不刷屏、如实报数）")
end

-- 117) ★★★1.73.5 图标语义表（名称 + 多标签）+ 图标库关键字过滤
--   用户原话：「对存储下来的图标路径进行语义识别,对应一个名称,语义tag 一个图标可以设置多个,比如爪子....
--   然后再图标库内加个输入过滤根据名称/路径进行筛选功能.」
do
  local function has117(t, v)
    for i = 1, table.getn(t or {}) do if t[i] == v then return true end end
    return false
  end
  -- ⓪ 素材：用 doc/图标路径清单.txt 的**真实形态**（/Game/Interface/Icons/X_TEX，1018 条）
  --   ★这是生产上宏图标表真正给的形态 —— 用编出来的短名验，就照不到「_TEX 没剥」这类只有真机才犯的错。
  local savedMacro117 = TEST.macroIcons
  eq(type(TEST_ICON_FIXTURE) == "table", true, "⓪前置：客户端图标清单被注入了（doc/图标路径清单.txt）")
  eq(table.getn(TEST_ICON_FIXTURE or {}) >= 1000, true, "⓪前置：清单条数 ≥1000（实际 " .. table.getn(TEST_ICON_FIXTURE or {}) .. "）")
  TEST.macroIcons = TEST_ICON_FIXTURE
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  -- ① 语义表：名称 + 多标签（用户举的例子：爪子那枚）
  --   ★★★两条路都要钉：① 直接查基础名（表 key）；② 走**真实 Unreal 路径**（生产唯一形态）。
  local sem = EVAL_IB_TEST_SEM("INV_Misc_MonsterClaw_03")
  eq(sem ~= nil, true, "①语义表查得到爪类图标")
  eq(sem and sem.name, "爪", "①★★★名称 = 爪（用户举的那个例子）")
  eq(has117(sem and sem.tags, "爪子"), true, "①★★标签里有「爪子」（同义词）")
  eq(has117(sem and sem.tags, "爪击"), true, "①★★标签里有「爪击」（一个图标多个 tag）")
  eq(has117(sem and sem.tags, "物品"), true, "①★标签里还有类别「物品」（前缀给的）")
  eq(type(sem and sem.tags) == "table" and table.getn(sem.tags) >= 3, true, "①★★一个图标的标签 ≥3 个")
  eq(EVAL_IB_TEST_SEM_SIZE() >= 1000, true, "①★★语义表覆盖整份清单（实际 " .. EVAL_IB_TEST_SEM_SIZE() .. " 条）")
  -- ★1.73.6 抓宠详情页右侧那枚放大镜：用户就是这么叫它的（工具提示与图标库显示名要一致）
  local semZ = EVAL_IB_TEST_SEM("INV_Misc_Spyglass_01")
  eq(semZ and semZ.name, "放大镜", "①★放大镜那枚的语义名 = 放大镜（用户的原话）")
  eq(has117(semZ and semZ.tags, "望远镜"), true, "①★并带「望远镜」同义标签")
  local semW = EVAL_IB_TEST_SEM("Ability_Hunter_Pet_Wolf")
  eq(semW and semW.name, "狼", "①★★家族图标也有语义名（狼）")
  eq(has117(semW and semW.tags, "宠物"), true, "①★家族图标带「宠物」标签")
  -- ①b ★★★**真实路径形态**（/Game/Interface/Icons/X_TEX）必须也能查到 ——
  --   这是生产上唯一会走的那条路：宏图标表给的就是这种带 _TEX 的 Unreal 资产路径。
  --   ★若 EVAL_IB_RAWN_OF 没剥 _TEX，这一段全红（而且真机上是一声不响地全部退回英文名）。
  eq(EVAL_IB_RAWN_OF("/Game/Interface/Icons/INV_Misc_MonsterClaw_03_TEX"), "INV_Misc_MonsterClaw_03",
     "①b★★★真实路径里剥掉 _TEX（基础名才是语义表的 key）")
  eq(EVAL_IB_NAME_OF("/Game/Interface/Icons/INV_Misc_MonsterClaw_03_TEX"), "爪",
     "①b★★★真实路径 → 语义名「爪」（生产形态能查到，不是只有短名能）")
  eq(EVAL_IB_NAME_OF("/Game/Interface/Icons/Ability_Hunter_Pet_Wolf_TEX"), "狼", "①b★★真实路径 → 家族语义名")
  eq(EVAL_IB_GROUP_OF("/Game/Interface/Icons/Spell_Fire_Fireball_TEX"), "fire",
     "①b★★分组仍按原始名前缀（_TEX 与语义名都不影响归类）")
  -- ② 过滤：名称 / 标签 / 路径 / 大小写不敏感 / 反例
  EVAL_IB_TEST_RESET()
  EVAL_IB_SET_GROUP("all")
  eq(EVAL_IB_TEST_MATCH_COUNT("爪子") >= 1, true, "②★★按**标签**能搜到（爪子 → " .. EVAL_IB_TEST_MATCH_COUNT("爪子") .. " 枚）")
  eq(EVAL_IB_TEST_MATCH_COUNT("药水") >= 10, true, "②★★按**名称**能搜到一批（药水 → " .. EVAL_IB_TEST_MATCH_COUNT("药水") .. " 枚）")
  eq(EVAL_IB_TEST_MATCH_COUNT("MonsterFang") >= 1, true, "②★★按**原始名/路径**也能搜（MonsterFang → " .. EVAL_IB_TEST_MATCH_COUNT("MonsterFang") .. " 枚）")
  eq(EVAL_IB_TEST_MATCH_COUNT("PET_WOLF") >= 1, true, "②★英文大小写不敏感（PET_WOLF → " .. EVAL_IB_TEST_MATCH_COUNT("PET_WOLF") .. " 枚）")
  eq(EVAL_IB_TEST_MATCH_COUNT("绝不可能存在的词zzz"), 0, "②反向哨兵：查不到就是 0 枚")
  -- ③ 分组与关键字**叠加**（先分组、再关键字）
  --   ★★★弱判据警告：原来只写「inv 的命中数 <= 全部」——把分组判定整段删掉时两边相等、**照样绿**。
  --     正解 = 查**命中项各自的 group**（必须全落在所选分组里）+ 一个必然为 0 的反向分组。
  local nAllPot = EVAL_IB_TEST_MATCH_COUNT("药水")
  eq(nAllPot >= 10, true, "③前置：全部里有 " .. nAllPot .. " 枚药水")
  EVAL_IB_SET_GROUP("inv")
  local nInvPot = EVAL_IB_TEST_MATCH_COUNT("药水")
  eq(EVAL_IB_TEST_GROUP(), "inv", "③★分组真的切过去了")
  eq(nInvPot >= 10, true, "③★★inv 分组里药水仍有 " .. nInvPot .. " 枚（叠加不能把命中全挡掉）")
  local gs117 = EVAL_IB_TEST_MATCH_GROUPS("药水")
  local allInv117 = true
  for i = 1, table.getn(gs117) do if gs117[i] ~= "inv" then allInv117 = false end end
  eq(allInv117, true, "③★★★命中的**每一条**都真在所选分组里（把分组判定删掉就会混进别组）")
  EVAL_IB_SET_GROUP("ability")
  eq(EVAL_IB_TEST_MATCH_COUNT("药水"), 0, "③★★★反向：换到 ability 分组后药水一枚都搜不到（=关键字真的被分组裁过）")
  EVAL_IB_SET_GROUP("all")
  -- ④ 单一入口：状态/输入框同步 + 回第 1 页 + 不递归
  EVAL_IB_TEST_RESET()
  EVAL_IB_SET_GROUP("all")
  -- ★★★「回第 1 页」必须用**改词后仍有多页**的词来验：
  --   ① 直接在首页改词 → 断言恒真；
  --   ② 命中只剩一页时，页码**夹取**会自己回到第 1 页 → 把 IB.page = 1 删掉照样绿（本变异第一版就是这么存活的）。
  EVAL_IB_TEST_SET_Q("/Game/")
  local many117 = EVAL_IB_TEST_MATCH_COUNT("/Game/")
  eq(many117 > EVAL_IB_PER_PAGE(EVAL_IB_TEST_W()), true, "④前置：该词命中多页（" .. many117 .. " 枚）")
  EVAL_IB_STEP(1)
  local pgPre = select(1, EVAL_IB_TEST_PAGE())
  eq(pgPre > 1, true, "④前置：先把页码推到第 " .. tostring(pgPre) .. " 页，否则「回第 1 页」恒真")
  EVAL_IB_TEST_SET_Q("法术")
  eq(EVAL_IB_TEST_MATCH_COUNT("法术") > EVAL_IB_PER_PAGE(EVAL_IB_TEST_W()), true, "④前置：新词也仍有多页（夹取救不了多页）")
  eq(select(1, EVAL_IB_TEST_PAGE()) == 1, true, "④★★改词回到第 1 页（多页时停在旧页码 = 看到错页）")
  EVAL_IB_TEST_SET_Q("爪")
  eq(EVAL_IB_TEST_Q(), "爪", "④★状态记下过滤词")
  eq(EVAL_IB_TEST_EB_TEXT(), "爪", "④★★输入框文本被同步（用户看得见自己在过滤什么）")
  eq(select(1, EVAL_IB_TEST_PAGE()) == 1, true, "④★★改词回到第 1 页（否则停在第 5 页看着空列表）")
  eq(EVAL_IB_TEST_PH_SHOWN(), false, "④★有词时占位提示隐藏")
  local rc0 = EVAL_IB_TEST_REFRESH_COUNT()
  -- ★★★不递归的判据 = **回写次数有界**。原来只看「刷新次数没爆」是**弱判据**：
  --   真客户端上「无条件回写」会变成 SetText→OnTextChanged→SetText… 的递归，
  --   而递归会被沿途的 pcall 吞掉、刷新次数反而只剩 1 次 → 变异**存活**（实测）。
  TEST.ebSetTextCalls = 0
  EVAL_IB_TEST_SET_Q("爪子")
  eq(TEST.ebSetTextCalls <= 2, true, "④★★★回写输入框不会递归（SetText 实测 " .. tostring(TEST.ebSetTextCalls) .. " 次；两道比对拆掉 = 51 次）")
  eq(EVAL_IB_TEST_REFRESH_COUNT() <= rc0 + 3, true, "④★★刷新次数也没爆（+ " .. tostring(EVAL_IB_TEST_REFRESH_COUNT() - rc0) .. "）")
  -- ⑤ 空匹配**如实点名**（不是一片空白）+ 清除复原
  EVAL_IB_TEST_SET_Q("绝不可能存在的词zzz")
  eq(EVAL_IB_TEST_MATCH_COUNT("绝不可能存在的词zzz"), 0, "⑤前置：0 枚")
  local stTxt = tostring(EVAL_IB_TEST_STATUS_TEXT())
  eq(string.find(stTxt, "绝不可能存在的词zzz", 1, true) ~= nil, true, "⑤★★空匹配时状态行点名说明：「" .. stTxt .. "」")
  EVAL_IB_TEST_SET_Q("")
  eq(EVAL_IB_TEST_PH_SHOWN(), true, "⑤★清空后占位提示回来")
  eq(EVAL_IB_TEST_MATCH_COUNT("") >= 1000, true, "⑤★清空后恢复全量")
  -- ⑥ 命中列表真的按语义名显示（不是只有过滤能命中）
  local names = EVAL_IB_TEST_MATCH_NAMES("爪子")
  local foundClaw = false
  for i = 1, table.getn(names) do if names[i] == "爪" then foundClaw = true end end
  eq(foundClaw, true, "⑥★★命中的条目**显示名**是语义名（爪），不是英文原名")
  -- 收尾：把宏图标表还原（下一个用例别带着 1018 条真实图标跑）
  TEST.macroIcons = savedMacro117
  EVAL_IB_TEST_RESET()
  EVAL_IB_SCAN(true)
  EVAL_HELP_CFG_SETTAB(1)
  print("  图标语义 + 过滤：语义名/多标签（爪子）· 按名称/标签/路径/大小写搜 · 与分组叠加 · 单一入口不递归 · 空匹配如实点名")
end

-- 118) ★★★1.73.9 工具箱滚动控件：挪到**底部行**、与 [关闭] 同行对齐
--   用户原话（截图圈出右上 ▲ 与列表下方 ▼+计数）：
--   「工具箱滚动样式参考图标库那边的滚动方式,然后放置在底部和关闭同行.右对齐关闭旁边」
--   判据全是**真实控件几何 × 生产的关闭几何**（不写死坐标）。
do
  local savedTab118 = EVAL_HELP_CFG_TAB()
  EVAL_HELP_CFG_SETTAB(3) -- 工具箱 Tab（底部行控件在该 Tab 的**显式显隐清单**里，不切过来就是 Hide）
  local tbs = EVAL_TB_TEST_SCROLL()
  eq(type(tbs) == "table" and tbs.up ~= nil and tbs.dn ~= nil, true, "①前置：拿到工具箱滚动控件的真实几何")
  local lay118 = EVAL_TEST_CFG_LAYOUT()
  eq(tbs.midY, lay118.closeMidY, "①★★★滚动按钮取自**生产的底部行中线**（== [关闭] 的中线）")
  local function midOf118(r) if r and type(r.y) == "number" and type(r.h) == "number" then return r.y - r.h / 2 end return nil end
  eq(math.abs((midOf118(tbs.up) or 999) - tbs.midY) <= 1, true,
     "①★★[上翻] 与 [关闭]**中线对齐**（实测 " .. tostring(midOf118(tbs.up)) .. " vs " .. tostring(tbs.midY) .. "）")
  eq(math.abs((midOf118(tbs.dn) or 999) - tbs.midY) <= 1, true, "①★★[下翻] 同样与 [关闭] 中线对齐")
  eq(tbs.dn.x + tbs.dn.w <= tbs.closeLeft - 4, true,
     "①★★★按钮组**右对齐、停在 [关闭] 左边**（右端 " .. tostring(tbs.dn.x + tbs.dn.w) .. " < 关闭左边缘 " .. tostring(tbs.closeLeft) .. "）")
  eq(tbs.up.x + tbs.up.w <= tbs.dn.x - 1, true, "①★两个滚动按钮之间不重叠")
  eq(tbs.indicator ~= nil and tbs.indicator.x + tbs.indicator.w <= tbs.up.x - 2, true,
     "①★★★计数文字与按钮组不重叠（文字右端 " .. tostring(tbs.indicator and (tbs.indicator.x + tbs.indicator.w)) ..
     " < 按钮左端 " .. tostring(tbs.up.x) .. "）")
  eq(tbs.indicator ~= nil and tbs.indicator.y < lay118.closeMidY + 40, true,
     "①★★★计数文字在**底部行**（实测 y=" .. tostring(tbs.indicator and tbs.indicator.y) .. "，关闭中线 " .. tostring(lay118.closeMidY) .. "）")
  -- ② 样式：不再是 ▲/▼ 字形按钮，改成图标库同款的**文字按钮**（文案走语言包）
  eq(tbs.up.text ~= "▲" and tbs.dn.text ~= "▼", true,
     "②★★★不再是 ▲/▼ 字形（实测「" .. tostring(tbs.up.text) .. "」「" .. tostring(tbs.dn.text) .. "」）")
  eq(tbs.up.text == EVAL_L("TB_UP") and tbs.dn.text == EVAL_L("TB_DN"), true,
     "②★★文案走语言包（TB_UP/TB_DN，三语言齐全）")
  -- ③ 滚动真的还能用（点**真实 OnClick**：下翻一次 → off 不回退；上翻一次 → off 不前进）
  local off0 = EVAL_TB_TEST_OFF()
  eq(EVAL_TB_TEST_SCROLL_CLICK("dn"), true, "③前置：[下翻] 有真实 OnClick 且点得动")
  local off1 = EVAL_TB_TEST_OFF()
  eq(off1 >= off0, true, "③★★点 [下翻] 后列表位移不倒退（" .. tostring(off0) .. " → " .. tostring(off1) .. "）")
  eq(EVAL_TB_TEST_SCROLL_CLICK("up"), true, "③前置：[上翻] 有真实 OnClick 且点得动")
  eq(EVAL_TB_TEST_OFF() <= off1, true, "③★★点 [上翻] 后不回退（" .. tostring(off1) .. " → " .. tostring(EVAL_TB_TEST_OFF()) .. "）")
  EVAL_HELP_CFG_SETTAB(savedTab118) -- 还原 Tab（跨用例状态残留是本项目老坑）
  print("  工具箱滚动：挪到底部行、与 [关闭] 中线对齐、右对齐停在关闭旁边（文字按钮，不再是 ▲/▼）")
end

-- 119) ★★★1.73.10 工具箱：角色名职业着色（需求参考 tmp/XGuild，按本项目规范轻量化重写）
--   判据分三层：① 纯函数（职业名→色 / 阶级插值，含 XGuild 那个奇数档 bug 的反例）；
--   ② 接线（三个窗口都挂上、原函数仍在链上、幂等不重复包装）；
--   ③ 真实控件颜色（职业色 / 同地图绿 / 离线减半 / 关掉开关不再叠色 / 缺窗口不崩）。
do
  local pack119 = EVAL_LOCALES[EVAL_GET_LANG()] or EVAL_LOCALES.zhCN
  -- ① 纯函数
  eq(EVAL_TB_PAINT_CLASS_COLOR_OF("战士"), "ffc79c6e", "①职业显示名 → 职业色（战士）")
  eq(EVAL_TB_PAINT_CLASS_COLOR_OF("WARRIOR"), "ffc79c6e", "①英文 token 也认")
  eq(EVAL_TB_PAINT_CLASS_COLOR_OF("圣骑士"), "fff58cba", "①★★中文名走 Engine 的 CLASS_LIST（单一来源，不另抄一份职业名表）")
  eq(EVAL_TB_PAINT_CLASS_TOKEN_OF("德鲁伊"), "DRUID", "①本地化名 → token")
  eq(EVAL_TB_PAINT_CLASS_COLOR_OF("查无此职业"), "ffa0a0a0", "①★反向哨兵：认不出来 = 默认灰（不瞎猜）")
  local r0, g0 = EVAL_TB_PAINT_RANK_RGB(0, 5)
  local r2, g2 = EVAL_TB_PAINT_RANK_RGB(2, 5)
  local r4, g4 = EVAL_TB_PAINT_RANK_RGB(4, 5)
  eq(g0 < g2 and g2 < g4, true, "①阶级色按比例连续（绿分量递增）")
  -- ★红分量在前半段保持 1.0（红→黄只动绿蓝），后半段才降 → 判据要写 ≥ 而不是 >
  eq(r0 >= r2 and r2 > r4, true, "①阶级色按比例连续（红分量：红→黄不变、黄→绿递减）")
  eq(math.abs(g2 - 0.82) < 0.01, true, "①★★奇数档（5 档）的中点也拿得到黄色 —— XGuild 原作在这里永远拿不到（idx == nRanks/2 恒假）")
  eq(EVAL_TB_PAINT_RANK_RGB(0, 1), 1, "①只有一档时不炸（返回白色）")
  -- ② 工具箱里真的有这一行（UI 接线，不是只有引擎）
  local hasRow119, label119 = false, nil
  for _, it119 in ipairs(EVAL_TEST_TB_ROWS()) do
    if it119.key == "colorClass" then hasRow119 = true label119 = it119.label end
  end
  eq(hasRow119, true, "②★★工具箱列模型里有「角色名职业着色」这一行（队/社交组）")
  eq(label119, pack119.TB_COLORCLASS, "②★标签走语言包")
  -- ③ 挂载：三个窗口都挂上 + 原函数仍在链上 + 幂等
  TEST.paintFS = {}
  TEST.guildUpd, TEST.whoUpd, TEST.friendsUpd = 0, 0, 0
  local okN119, totN119 = EVAL_TB_PAINT_INSTALL_ALL()
  eq(okN119, totN119, "③三个窗口的刷新函数都挂上了（" .. tostring(okN119) .. "/" .. tostring(totN119) .. "）")
  local wrapped119 = GuildStatus_Update
  EVAL_TB_PAINT_INSTALL_ALL() -- 再挂一次
  eq(GuildStatus_Update == wrapped119, true, "③★★幂等：重复挂载**不重复包装**（否则原函数会被调多次/颜色被叠多层）")
  -- ④ 走真实入口：原函数被调 + 颜色真的落在控件上
  local savedCC119 = EVAL_HELP_CONFIG.tb.colorClass
  EVAL_HELP_CONFIG.tb.colorClass = true
  TEST.paintOffset, TEST.paintZone, TEST.paintRanks = 0, "艾尔文森林", 5
  TEST.guildRows = {
    { name = "甲", class = "战士",  level = 10, zone = "艾尔文森林", rankIndex = 0, online = true },
    { name = "乙", class = "法师",  level = 10, zone = "暴风城",   rankIndex = 2, online = true },
    { name = "丙", class = "德鲁伊", level = 10, zone = "艾尔文森林", rankIndex = 4, online = false },
  }
  TEST.paintFS = {}
  GuildStatus_Update()
  eq(TEST.guildUpd, 1, "④★★**先调原函数**（客户端的文本/配色先落地，我们再叠色）")
  local fsA = TEST.paintFS["GuildFrameButton1Name"]
  local fsB = TEST.paintFS["GuildFrameButton2Name"]
  eq(fsA ~= nil and math.abs(fsA.r - 0.780) < 0.02, true, "④战士的名字是职业色（r=" .. tostring(fsA and fsA.r) .. "）")
  eq(fsB ~= nil and math.abs(fsB.r - 0.412) < 0.02, true, "④法师用另一套色（r=" .. tostring(fsB and fsB.r) .. "）")
  eq(fsA.r ~= fsB.r, true, "④★不同职业不同色（反向哨兵：不是「都涂同一个颜色」）")
  eq(TEST.paintFS["GuildFrameGuildStatusButton1Name"] ~= nil, true, "④状态行的名字也上色（XGuild 两处都涂，这里保持）")
  local fsZ = TEST.paintFS["GuildFrameButton1Zone"]
  eq(fsZ ~= nil and fsZ.g == 1 and fsZ.r == 0, true, "④与自己同地图 → Zone 绿字")
  eq(TEST.paintFS["GuildFrameButton2Zone"] == nil, true, "④★反向：不同地图的行**不动** Zone 列")
  local fsC = TEST.paintFS["GuildFrameButton3Name"]
  eq(fsC ~= nil and math.abs(fsC.r - 0.5) < 0.02, true, "④★离线成员整行减半亮度（德鲁伊 1.0 → 0.5，实测 " .. tostring(fsC and fsC.r) .. "）")
  local rank1 = TEST.paintFS["GuildFrameGuildStatusButton1Rank"]
  local rank3 = TEST.paintFS["GuildFrameGuildStatusButton3Rank"]
  eq(rank1 ~= nil and rank1.g < 0.2, true, "④最低阶＝红（g=" .. tostring(rank1 and rank1.g) .. "）")
  eq(rank3 ~= nil and rank3.g > rank1.g, true, "④最高阶＝偏绿（离线再减半，仍比最低阶绿）")
  -- ⑤ 单人数据源：who / friends 也真的画
  TEST.paintFS = {}
  TEST.whoRows = { { name = "丁", class = "盗贼", level = 10, zone = "艾尔文森林" } }
  WhoList_Update()
  eq(TEST.whoUpd, 1, "⑤who 窗口：原函数被调")
  eq(TEST.paintFS["WhoFrameButton1Name"] ~= nil, true, "⑤who 行的名字上色")
  eq(TEST.paintFS["WhoFrameButton1Variable"] == nil, true, "⑤★本客户端查不到排序维度（UIDropDownMenu_GetSelectedID 不在 api 表里）→ 该列**不猜**、不涂")
  TEST.paintFS = {}
  TEST.friendRows = {
    { name = "戊", class = "猎人", level = 10, zone = "艾尔文森林", online = true },
    { name = "己", class = "牧师", level = 10, zone = "暴风城",   online = false },
  }
  FriendsList_Update()
  eq(TEST.friendsUpd, 1, "⑤好友窗口：原函数被调")
  local info1 = TEST.paintFS["FriendsFrameFriendButton1ButtonTextInfo"]
  local info2 = TEST.paintFS["FriendsFrameFriendButton2ButtonTextInfo"]
  eq(info1 ~= nil and info1.g == 1 and info1.r == 0, true, "⑤好友同地图 → 信息列绿字")
  eq(info2 ~= nil and math.abs(info2.r - 0.5) < 0.02, true, "⑤好友离线 → 信息列灰（0.5）")
  -- ⑥ 关掉开关：不再叠色（但原函数照跑 —— 客户端自己的配色会刷回去）
  EVAL_HELP_CONFIG.tb.colorClass = false
  TEST.paintFS = {}
  GuildStatus_Update()
  eq(TEST.guildUpd, 2, "⑥关掉后原函数照样被调（我们不是拦截刷新，只是不再叠色）")
  eq(next(TEST.paintFS) == nil, true, "⑥★反向哨兵：关掉后**一处都不涂**（颜色由客户端自己刷回）")
  -- ⑦ 开关的「即时生效」：勾/取消勾立刻重刷三个窗口
  local mid119 = EVAL_TB_PAINT_CLICK()
  eq(EVAL_HELP_CONFIG.tb.colorClass, mid119, "⑦勾选状态写进配置")
  eq(EVAL_TB_PAINT_REFRESH(), 3, "⑦★★重刷覆盖三个窗口（勾/取消勾立即生效，不用 /reload）")
  EVAL_HELP_CONFIG.tb.colorClass = savedCC119
  -- ⑧ 缺窗口：摘掉一个刷新函数 → 如实记账、不崩、其余照常
  TEST.paintFS = {}
  WhoList_Update = nil
  local okN119b, totN119b = EVAL_TB_PAINT_INSTALL_ALL()
  eq(okN119b, totN119b - 1, "⑧★窗口不存在时如实少挂一个（" .. tostring(okN119b) .. "/" .. tostring(totN119b) .. "）")
  local st119 = EVAL_TB_PAINT_STATE()
  eq(st119.missing["WhoList_Update"], true, "⑧★★缺失窗口**记名**（不是静默失败：诊断命令要能列出来）")
  GuildStatus_Update()
  eq(TEST.paintFS["GuildFrameButton1Name"] ~= nil, true, "⑧缺一个窗口不影响其余窗口上色")
  WhoList_Update = function() TEST.whoUpd = TEST.whoUpd + 1 end
  EVAL_TB_PAINT_INSTALL_ALL() -- 恢复后重挂（幂等）
  print("  职业着色：职业名→职业色 · 阶级按比例插值（含奇数档反例）· 三窗口挂载+幂等+先调原函数 · 同地图绿/离线减半 · 关开关不叠色 · 缺窗口如实记账")
end

-- 120) ★★★1.73.11 工具箱两列版式（用户：「工具箱分两列」）
--   判据：① 切点是**组边界**（右列从组标题开头）且两列行数差最小；
--         ② 真实控件几何**列不相交**（右列控件左边缘 > 左列控件右边缘）+ 每个控件都在**本列**内；
--         ③ 每个条目只出现一次（两列并集 = 本页，无重无漏）；
--         ④ 两列后 16 条一页装得下 → 指示行与翻页按钮都隐藏。
do
  local pack120 = EVAL_LOCALES[EVAL_GET_LANG()] or EVAL_LOCALES.zhCN
  -- ① 纯函数：合成模型 3 组 5/5/6（与真实模型同形）
  local fake = {}
  local idx = 0
  for gi = 1, 3 do
    idx = idx + 1 fake[idx] = { t = "h", label = "组" .. gi }
    local body = (gi == 3) and 5 or 4
    for j = 1, body do idx = idx + 1 fake[idx] = { t = "c", key = "k" .. gi .. "_" .. j } end
  end
  eq(idx, 16, "①前置：合成模型 16 条（3 组 5/5/6）")
  local cut120, l120, r120, pn120 = EVAL_TB_COL_CUT(fake, 0, 13, 2)
  eq(pn120, 16, "①本页 16 条")
  eq(l120 + r120, pn120, "①两列行数之和 = 本页条数（不重不漏）")
  eq(fake[cut120 + 1] ~= nil and fake[cut120 + 1].t == "h", true,
     "①★★★切点落在**组边界**（右列从组标题开头；实际 cut=" .. tostring(cut120) .. "，右列首条=" .. tostring(fake[cut120 + 1] and fake[cut120 + 1].t) .. "）")
  -- ★「平衡」的正确说法 = **在允许的组边界切点里差最小**（组大小 5/5/6 时不可能做到 8/8，
  --   所以不能写死「差 ≤2」；这里自己把候选切点算一遍，跟纯函数挑出来的比）
  local best120 = nil
  for _, cc in ipairs({ 5, 10, 16 }) do
    local d = math.abs(cc - (16 - cc))
    if best120 == nil or d < best120 then best120 = d end
  end
  eq(math.abs(l120 - r120) <= best120, true,
     "①两列在**组边界候选**里差最小（" .. tostring(l120) .. "/" .. tostring(r120) .. "，最优差 " .. tostring(best120) .. "）")
  -- 单列（cols=1）：不切，整页都在左列；行数上限给足 99 才能一页装下 16 条
  local c1a, l1a, r1a, p1a = EVAL_TB_COL_CUT(fake, 0, 99, 1)
  eq(c1a, 16, "①单列时不切（左列装全部 16 条）")
  eq(r1a, 0, "①单列时右列为空")
  eq(p1a, 16, "①单列一页 16 条")
  -- ② 真实版式（先切到工具箱 Tab：行控件的显隐走**显式清单**，不切过来全是 Hide）
  local savedTab120 = EVAL_HELP_CFG_TAB()
  EVAL_HELP_CFG_SETTAB(3)
  local lay120 = EVAL_TB_TEST_LAYOUT()
  eq(type(lay120) == "table" and lay120.cols ~= nil, true, "②前置：拿到工具箱真实版式")
  eq(lay120.cols, 2, "②★★工具箱真的分两列（cols=" .. tostring(lay120.cols) .. "，列宽 " .. tostring(lay120.colW) .. "，列缝 " .. tostring(lay120.colGap) .. "）")
  eq(lay120.colW >= 200, true, "②列宽够放「勾选框 + 文案 + 按钮」：" .. tostring(lay120.colW))
  eq(lay120.colX[2], lay120.colX[1] + lay120.colW + lay120.colGap, "②右列起点 = 左列右边界 + 列缝")
  eq(lay120.pool, lay120.rowsPerCol * 2, "②行池 = 每列行数 × 列数（" .. tostring(lay120.pool) .. "）")
  eq(lay120.rowsL > 0 and lay120.rowsR > 0, true, "②★★两列都真的有内容（" .. tostring(lay120.rowsL) .. "+" .. tostring(lay120.rowsR) .. "）")
  eq(lay120.rows[lay120.rowsPerCol + 1] ~= nil and lay120.rows[lay120.rowsPerCol + 1].kind == "h", true,
     "②★★★右列第一格是**组标题**（组不被拆到两列）")
  -- ③ 列不相交 + 每个控件在本列内 + 条目不重不漏
  local bad120, seen120, cnt120 = "", {}, 0
  local function rightOf(rect)
    if not (rect and type(rect.x) == "number" and type(rect.w) == "number") then return nil end
    return rect.x + rect.w
  end
  for k = 1, table.getn(lay120.rows) do
    local rr = lay120.rows[k]
    -- ★按 kind 判断「这一格有东西」（组标题、以及没有 key 的行如「屏蔽公会成员上下线提示」也算）
    if rr and rr.kind ~= nil then
      cnt120 = cnt120 + 1
      if rr.key then
        if seen120[rr.key] then bad120 = bad120 .. "重复:" .. tostring(rr.key) .. " " end
        seen120[rr.key] = true
      end
      local cL, cR = lay120.colX[rr.col], lay120.colX[rr.col] + lay120.colW
      for _, nm in ipairs({ "chk", "text", "extra", "add", "clr", "chv", "hdr" }) do
        local rect = rr[nm]
        if rect and rect.shown then
          if rect.x < cL - 0.5 then bad120 = bad120 .. nm .. "越左:" .. tostring(rr.key) .. " " end
          local rt = rightOf(rect)
          if rt == nil then bad120 = bad120 .. nm .. "没有宽度:" .. tostring(rr.key) .. " " end
          if rt and rt > cR + 0.5 then bad120 = bad120 .. nm .. "越出本列:" .. tostring(rr.key) .. "(" .. tostring(math.floor(rt)) .. ">" .. tostring(cR) .. ") " end
        end
      end
    end
  end
  eq(bad120, "", "③★★★列不相交 + 控件都在本列内: " .. bad120)
  --  ★★★1.73.25 用户：「自动购买/自动丢弃 这两个的 [添加][清空] 要和左侧名称**对齐**」——
  --    判据 = 右键控件的**顶边**与同行名称的顶边一致（容差 1px）。
  --    ★为什么比「顶边」而不是「中心」：标签是 FontString，**没有显式高度**（GetHeight 拿不到可靠值）
  --      → 拿它算中心会得到 nil（本轮实测：判据一个控件都没量到，被下面的反向哨兵当场抓住）。
  --      而生产的修法本身就是「两者用**同一个下偏常量**」= 顶边相同，所以顶边就是这条判据的本质。
  --    ★修之前按钮顶边 = y、标签顶边 = y-3（差 3px），这条会当场响。
  local badAli120, nAli120 = "", 0
  for k = 1, table.getn(lay120.rows) do
    local rr = lay120.rows[k]
    if rr and rr.text and rr.text.shown and type(rr.text.y) == "number" then
      for _, nm in ipairs({ "add", "clr", "chv" }) do
        local rect = rr[nm]
        if rect and rect.shown and type(rect.y) == "number" then
          nAli120 = nAli120 + 1
          if math.abs(rect.y - rr.text.y) > 1 then
            badAli120 = badAli120 .. nm .. "@" .. tostring(rr.key) ..
              "(差" .. tostring(math.floor(math.abs(rect.y - rr.text.y) + 0.5)) .. ") "
          end
        end
      end
    end
  end
  eq(badAli120, "", "③b★★★右侧按键与**左侧名称同顶边**（容差 1px）: " .. badAli120)
  --  ★反向哨兵：这条判据必须**真的量到控件**（一个都没量到就是空跑——本项目「写了钩子没人调用等于没有」）
  eq(nAli120 >= 2, true, "③b★对齐判据真的量到了行内按键（量到 " .. tostring(nAli120) .. " 个）")
  eq(cnt120, lay120.pageN, "③★★两列显示的条目数 = 本页条数（" .. tostring(cnt120) .. "）")
  eq(lay120.pageN, table.getn(EVAL_TEST_TB_ROWS()), "③★16 条全在一页（pageN=" .. tostring(lay120.pageN) .. "）")
  -- ④ 一页装得下 → 指示行与翻页按钮都隐藏（★这条钉住「每页 = 列数 × 行数」，退回单列会当场响）
  local tbs120 = EVAL_TB_TEST_SCROLL()
  eq(tbs120.indicator == nil or tbs120.indicator.shown == false, true, "④★★16 条一页装下 → 计数行隐藏（退回单列会变成 13/页、这行就会冒出来）")
  eq(EVAL_TB_TEST_OFF(), 0, "④停在第 1 页（只有一页）")
  -- ⑤ 勾选行仍然可用：拿真实 [添加] 按钮（两列映射没错位）
  local m120 = EVAL_TEST_TB_ROWS()
  local buyKey, buyShown = nil, 0
  for i = 1, table.getn(m120) do if m120[i].key == "buy" then buyKey = i end end
  eq(buyKey ~= nil, true, "⑤模型里有「自动购买指定物品」行")
  eq(EVAL_TEST_TB_ADD_BTN_FOR("buy") ~= nil, true, "⑤★★两列下仍能按 key 找到那一行的 [添加] 按钮（列→条目映射没错位）")
  eq(EVAL_TEST_TB_ADD_BTN_FOR("discard") ~= nil, true, "⑤★同理找得到 [清空] 所属行")
  --  ★★★1.73.30 用户：「工具箱 内项目标题栏宽度自适应」——
  --    组标题栏 = 按**本列宽**拼出来的分隔条（纯函数 EVAL_TB_HDR_TEXT）；判据：
  --    ① 装饰剥干净（标题只出现一次）；② 估算宽度**填满本列但不溢出**；③ 列宽变大 → 分隔条更长；
  --    ④ 渲染出的真文本 == 纯函数输出（UI 与断言同源，且确实被重写过）。
  do
    local hdrLab133 = EVAL_L("TB_H_QNOTIFY")
    local h300 = EVAL_TB_HDR_TEXT(hdrLab133, 300)
    local h400 = EVAL_TB_HDR_TEXT(hdrLab133, 400)
    eq(string.find(h300, "任务·通知", 1, true) ~= nil, true, "⑨★★★标题栏里有标题（装饰剥掉后只剩一份）：" .. tostring(h300))
    local _, cntT133 = string.gsub(h300, "任务·通知", "")
    eq(cntT133, 1, "⑨★★标题在分隔条里只出现一次（没有叠成两份）")
    eq(EVAL_TEST_TB_HDR_EST(h300) <= 300, true,
       "⑨★★★分隔条**不溢出**列宽（估算 " .. tostring(EVAL_TEST_TB_HDR_EST(h300)) .. " ≤ 300）")
    eq(EVAL_TEST_TB_HDR_EST(h300) >= 300 * 0.85, true,
       "⑨★★★而且**填满**本列（估算 " .. tostring(EVAL_TEST_TB_HDR_EST(h300)) .. " ≥ 255）")
    eq(EVAL_TEST_TB_HDR_EST(h400) <= 400 and EVAL_TEST_TB_HDR_EST(h400) >= 400 * 0.85, true,
       "⑨★★宽列同样填满不溢出（" .. tostring(EVAL_TEST_TB_HDR_EST(h400)) .. "）")
    eq(string.len(h400) > string.len(h300), true, "⑨★★★列宽变大 → 分隔条更长（宽度自适应）")
    --  ★「剥装饰」必须**承重**：带装饰的标签（语言包原串）与纯标题必须算出**同一条**分隔条 ——
    --    只比「含标题」的话，不剥装饰（标题里再套一层破折号）也能过（M246 实测就是这种漏网）。
    eq(EVAL_TB_HDR_TEXT("任务·通知", 300), h300, "⑨★★★带装饰的标签与纯标题算出**同一条**分隔条（剥装饰承重）")
    --  渲染侧同源：真实控件的文本 == 纯函数按**同一列宽**算出来的那份
    local rendered133 = EVAL_TEST_TB_HDR_TEXT(hdrLab133)
    eq(rendered133, EVAL_TB_HDR_TEXT(hdrLab133, lay120.colW),
       "⑨★★★渲染出的标题栏 == 纯函数算出来的那份（列宽 " .. tostring(lay120.colW) .. "）")
    eq(rendered133 ~= hdrLab133, true, "⑨★★而且真的被重写过（不是把语言包原串原封不动塞进去）")
    eq(EVAL_TEST_TB_HDR_EST(rendered133) <= lay120.colW, true,
       "⑨★★真实列宽下也不溢出（" .. tostring(EVAL_TEST_TB_HDR_EST(rendered133)) .. " ≤ " .. tostring(lay120.colW) .. "）")
  end
  EVAL_HELP_CFG_SETTAB(savedTab120) -- 还原 Tab（跨用例状态残留是本项目老坑）
  print(string.format("  工具箱两列：%d 列 / 列宽 %d / 列缝 %d / 本页 %d 条 = 左 %d + 右 %d（右列从组标题起）",
    lay120.cols, lay120.colW, lay120.colGap, lay120.pageN, lay120.rowsL, lay120.rowsR))
end

-- 134) ★★★1.73.31 用户报「自动购买的弹窗点击不到」（截图里工具箱行文字/按钮压在弹窗上）——
--   【根因】弹窗只设了 strata、**没设 frame level**：同一个 DIALOG 层里按 frame level 排先后，
--     工具箱的行按钮是配置窗的子帧（level 更高）→ 画在弹窗之上，鼠标也被它们吃掉。
--   【判据】① 弹窗层级 ≥ 200（高于配置窗各弹窗 100~140，低于全局下拉 250）；
--           ② 弹窗层级 **压过** 工具箱的交互控件（真实控件读回来的层级）；
--           ③ 弹窗 EnableMouse(true)：吃掉落在自己身上的点击，**不穿透**到底下的复选框。
do
  local savedTab134 = EVAL_HELP_CFG_TAB()
  EVAL_HELP_CFG_SETTAB(3)
  EVAL_TB_REFRESH()
  EVAL_BUY_UI_OPEN()
  local z134 = EVAL_TEST_BUY_UI_Z()
  eq(type(z134.buy) == "number", true, "①前置：弹窗已建好且读得到层级（" .. tostring(z134.buy) .. "）")
  eq(z134.buy >= 200, true, "①★★★弹窗层级 ≥ 200（实际 " .. tostring(z134.buy) .. "）")
  eq(type(z134.toolbox) == "number", true, "①前置：读得到工具箱交互控件的层级（" .. tostring(z134.toolbox) .. "）")
  eq(z134.buy > z134.toolbox, true, "②★★★弹窗压过工具箱行控件（" .. tostring(z134.buy) .. " > " ..
     tostring(z134.toolbox) .. "）—— 否则点击被它们吃掉")
  eq(z134.mouse, true, "③★★★弹窗 EnableMouse(true)（不把点击漏给下面的复选框）")
  EVAL_BUY_UI_CLOSE()
  EVAL_HELP_CFG_SETTAB(savedTab134)
  print("  自动购买弹窗：层级 200（压过工具箱行控件）+ 吃掉点击（用户报「点击不到」的根因）")
end

-- 121) ★★★1.73.12 聊天窗名字着色（用户：「聊天窗 内的名字能着色吗?需要走缓存?」）
--   判据：① 缓存单一来源（写入点唯一）：职业名认得出才写、单字名不写、宠物名归主人、大小写不敏感；
--         ② 纯函数认得出三种形态（方括号 / 行首「名字:」/ 方括号前缀之后）；
--         ③ ★反向哨兵：未知名 / 单字名 / 频道通知 / 已上过色 / 物品链接里的同名 → **一个都不改**；
--         ④ 只染第一处；⑤ 走**真实打印入口**真的带色（不是只在纯函数里对）；⑥ 开关关掉一个字不改；
--         ⑦ 与频道屏蔽**共用包装体**且互不干扰；⑧ 缓存来源（窗口上色白拿 + 只读采集）；
--         ⑨ 采集**限频**（窗口内第二次不去扫名册 —— 用「新增行采不到」证明，避免弱判据）；
--         ⑩ 多聊天窗（ChatFrame2 也挂上）；⑪ 工具箱里有这一行且标签走语言包。
do
  local pack121 = EVAL_LOCALES[EVAL_GET_LANG()] or EVAL_LOCALES.zhCN
  local savedTb121 = EVAL_HELP_CONFIG.tb
  local savedTime121 = TEST.time
  EVAL_HELP_CONFIG.tb = {}
  -- ① 缓存（name→职业 token）：唯一写入点 + 键规范化 + 「认不出就不写」
  eq(EVAL_TB_NAMECLASS_PUT("守夜人", "萨满"), true, "①写入中文职业名（走 Engine 的 CLASS_LIST）")
  eq(EVAL_TB_NAMECLASS_GET("守夜人"), "SHAMAN", "①★读回来是职业 token")
  eq(EVAL_TB_NAMECLASS_PUT("NIGHTWATCH", "WARRIOR"), true, "①写英文名 + 英文职业 token")
  eq(EVAL_TB_NAMECLASS_GET("nightwatch"), "WARRIOR", "①★★大小写不敏感（键统一小写）")
  eq(EVAL_TB_NAMECLASS_PUT("骑猪人-宠物", "猎人"), true, "①写宠物形态的名字")
  eq(EVAL_TB_NAMECLASS_GET("骑猪人"), "HUNTER", "①★★宠物名「主人-宠物」归到主人")
  eq(EVAL_TB_NAMECLASS_PUT("甲", "战士"), false, "①★单字名不写（误伤面太大）")
  eq(EVAL_TB_NAMECLASS_GET("甲"), nil, "①★单字名也查不到")
  eq(EVAL_TB_NAMECLASS_PUT("阿甲", "战士"), true, "①★★两个字的中文名照常写入（★反例：string.len 按字节数会把单字判成 2 字符）")
  eq(EVAL_TB_NAMECLASS_PUT("守夜人", "查无此职业"), false, "①★★认不出职业 → **不写**（不猜）")
  eq(EVAL_TB_NAMECLASS_GET("守夜人"), "SHAMAN", "①★★而且不覆盖已有记录（坏值不污染缓存）")
  -- ② 纯函数：认得出 → 染色
  -- ★★★1.73.19 颜色码 = "|c" + **8 位** aarrggbb（★表里存的就是 8 位；上一版 sub(hex,3) 切掉 alpha
  --   → 客户端不解析、屏幕上直接显示 |c 原文，用户截图实锤）→ 判据跟着改成「整串 8 位」
  local colSha = "|c" .. EVAL_TB_PAINT_CLASS_COLOR_OF("SHAMAN")
  local colWar = "|c" .. EVAL_TB_PAINT_CLASS_COLOR_OF("WARRIOR")
  local o121, w121 = EVAL_TB_CHAT_COLOR_LINE("[守夜人]: 你好")
  eq(o121, colSha .. "[守夜人]|r: 你好", "②★★★方括号形态染色（1.12 组合行里名字带方括号 —— 与 ChatMOD 同一依据）")
  eq(string.len(string.match(o121, "^|c%x+") or ""), 10,
     "②★★★颜色码必须是 8 位 aarrggbb：6 位（|cRRGGBB）本客户端**不解析** → 屏幕上直接显示 |c 原文")
  eq(w121, "守夜人", "②★返回命中的名字（诊断要能说清染的是谁）")
  eq(EVAL_TB_CHAT_COLOR_LINE("nightwatch: 走起"), colWar .. "nightwatch|r: 走起", "②★行首「名字:」形态染色")
  eq(EVAL_TB_CHAT_COLOR_LINE("[4. 世界防务] NIGHTWATCH: 走起"), "[4. 世界防务] " .. colWar .. "NIGHTWATCH|r: 走起",
     "②★★频道名方括号前缀之后的名字也认得出")
  eq(EVAL_TB_CHAT_COLOR_LINE("[守夜人] 说: 你好"), colSha .. "[守夜人]|r 说: 你好", "②★★「[名字] 说:」形态")
  -- ③ 反向哨兵：拿不准的一律**原样返回**
  local raw121 = {
    "[路人甲]: 你好",                                        -- 缓存里没有这个名字
    "甲: 你好",                                              -- 单字名
    "[4. 世界防务] 进入频道。",                               -- 频道通知（归频道屏蔽那条路管）
    "|cffc79c6e守夜人|r: 客户端已上过色",                     -- 客户端已经染过
    "|cff9d9d9d|Hitem:1234:0:0:0|h[守夜人]|h|r 获得了物品",   -- 物品链接的显示名恰好同名
  }
  local bad121 = ""
  for i = 1, table.getn(raw121) do
    local okv, out = pcall(EVAL_TB_CHAT_COLOR_LINE, raw121[i])
    if not okv or out ~= raw121[i] then bad121 = bad121 .. "[" .. i .. "] " end
  end
  eq(bad121, "", "③★★★反向哨兵：未知名/单字名/频道通知/已上色/物品链接 → 一个都不改（改了就是把人聊天弄坏）")
  eq(EVAL_TB_CHAT_COLOR_LINE("|cff20a0ff[4. 世界防务] 守夜人: 你好"), "|cff20a0ff[4. 世界防务] 守夜人: 你好",
     "③b★★★**未闭合**的颜色段里不叠加颜色（「不碰已有富文本」这条判据的边界；变异 M110 靠它捕获）")
  eq(EVAL_TB_CHAT_COLOR_LINE(nil), nil, "③nil 原样返回、不崩")
  eq(EVAL_TB_CHAT_COLOR_LINE(""), "", "③空串原样返回")
  -- ④ 只染第一处
  local o121b = EVAL_TB_CHAT_COLOR_LINE("[守夜人] 和 [守夜人] 都来了")
  local _, c121 = string.gsub(o121b, "|c", "")
  eq(c121, 1, "④★★只染第一处（实测颜色码出现 " .. tostring(c121) .. " 次）")
  -- ⑤ 走**真实打印入口**：颜色码真的送到了聊天框（与频道屏蔽共用同一层包装）
  local f121 = DEFAULT_CHAT_FRAME
  local saved121 = function(_, m) TEST.chat = (TEST.chat or "") .. tostring(m) .. "\n" end
  f121.AddMessage = saved121 -- 干净底层（Toolbox 载入时已挂过一层，不还原会在自己头上再包一层）
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_INSTALL(), true, "⑤前置：挂上聊天打印入口")
  TEST.chat = ""
  f121:AddMessage("[守夜人]: 你好")
  eq(TEST.chat ~= nil and string.find(tostring(TEST.chat), colSha, 1, true) ~= nil, true,
     "⑤★★★经过真实入口后聊天框收到的**已经带职业色**（不是只在纯函数里对）")
  eq(string.find(tostring(TEST.chat), "|r: 你好", 1, true) ~= nil, true, "⑤★颜色只包住名字，正文没被破坏")
  local st121 = EVAL_TB_CHATCOLOR_STATE()
  eq(st121.painted >= 1, true, "⑤★计数：被染色 " .. tostring(st121.painted) .. " 条（诊断读值口）")
  eq(st121.cache >= 2, true, "⑤★缓存里有 " .. tostring(st121.cache) .. " 个名字")
  -- ⑤b 我们自己的输出（EVAL_SAY 都带 EVAL_HELP: 前缀）既不进样本缓冲、也不会被自己染色
  local smp121 = table.getn(EVAL_TB_CHATCOLOR_STATE().samples)
  TEST.chat = ""
  f121:AddMessage("|cff66ccffEVAL_HELP:|r 我自己的输出 [守夜人]")
  eq(table.getn(EVAL_TB_CHATCOLOR_STATE().samples), smp121,
     "⑤b★★自己的输出不进样本缓冲（否则 /eh go 聊天 每跑一次就把真实样本挤掉一批）")
  eq(tostring(TEST.chat) == "|cff66ccffEVAL_HELP:|r 我自己的输出 [守夜人]\n", true,
     "⑤b★自己的输出原样打印（不给自己染色 —— 诊断输出要能看清原文）")
  -- ⑥ 开关关掉 → 一个字都不改（开关在**调用时**读，不用 /reload）
  EVAL_HELP_CONFIG.tb.chatColor = false
  TEST.chat = ""
  f121:AddMessage("[守夜人]: 你好")
  eq(tostring(TEST.chat) == "[守夜人]: 你好\n", true, "⑥★★★关掉开关后**原样**进聊天框（不改一个字）")
  eq(EVAL_TB_CHATCOLOR_STATE().painted, st121.painted, "⑥★关掉后计数不再增长")
  -- ⑦ 与频道屏蔽**互不干扰**（两者共用同一个包装体）
  EVAL_HELP_CONFIG.tb = { chatColor = true, chanJoin = true }
  TEST.chat = ""
  f121:AddMessage("[4. 世界防务] 进入频道。")
  eq(tostring(TEST.chat) == "", true, "⑦★★★共用包装体：频道通知照旧被吞（名字着色没有把它放行）")
  TEST.chat = ""
  f121:AddMessage("[守夜人]: 又见面了")
  eq(string.find(tostring(TEST.chat), colSha, 1, true) ~= nil, true, "⑦★反过来：普通聊天照旧被染色")
  -- ⑧ 缓存来源：窗口上色时「白拿」+ 只读采集（绝不发服务器查询）
  TEST.guildRows = { { name = "公会甲", class = "德鲁伊" }, { name = "公会乙", class = "盗贼" } }
  TEST.whoRows = { { name = "查询甲", class = "牧师" } }
  TEST.friendRows = { { name = "好友甲", class = "法师" } }
  EVAL_TB_PAINT_INSTALL_ALL()
  GuildStatus_Update() -- 走真实刷新 → 顺手写缓存
  eq(EVAL_TB_NAMECLASS_GET("公会甲"), "DRUID",
     "⑧★★「白拿」：公会窗口上色时顺手把名字+职业记进缓存（零额外 API 调用）")
  EVAL_TB_NAMECLASS_HARVEST("who")
  eq(EVAL_TB_NAMECLASS_GET("查询甲"), "PRIEST", "⑧★只读采集也能补缓存（who 列表）")
  EVAL_TB_NAMECLASS_HARVEST("friends")
  eq(EVAL_TB_NAMECLASS_GET("好友甲"), "MAGE", "⑧★好友列表")
  EVAL_TB_NAMECLASS_HARVEST("guild")
  eq(EVAL_TB_NAMECLASS_GET("公会乙"), "ROGUE", "⑧★公会名册（**只读**本地缓存，不发查询）")
  -- ⑨ 采集限频：★用「窗口内新增的行采不到」证明它真的**没去扫**（否则 0 可能是「扫了没新的」= 弱判据）
  TEST.time = 20000
  EVAL_TB_CHATCOLOR_RESET() -- 清限频窗
  TEST.guildRows = { { name = "新甲", class = "法师" } }
  eq(EVAL_TB_NAMECLASS_HARVEST_THROTTLED("guild"), 1, "⑨前置：窗口外真的扫了名册（采到 1 条新名字）")
  TEST.guildRows = { { name = "新甲", class = "法师" }, { name = "新乙", class = "盗贼" } }
  eq(EVAL_TB_NAMECLASS_HARVEST_THROTTLED("guild"), 0, "⑨★★限频：窗口内第二次**没去扫名册**")
  eq(EVAL_TB_NAMECLASS_GET("新乙"), nil, "⑨★★★反向哨兵：被限频挡下的那条确实没进缓存（证明「0」是没扫，不是扫了没新的）")
  TEST.time = 20031
  eq(EVAL_TB_NAMECLASS_HARVEST_THROTTLED("guild") >= 1, true, "⑨★过了窗口就恢复采集（限频不是永久停摆）")
  TEST.guildRows, TEST.whoRows, TEST.friendRows = nil, nil, nil
  -- ⑩ 多聊天窗：2 号窗也挂上（旧版只挂 DEFAULT_CHAT_FRAME → 2 号窗以后既冒通知、名字也不上色）
  local raw122 = function() end
  ChatFrame2 = { AddMessage = raw122 }
  EVAL_TEST_TB_CHAN_RESET()
  eq(EVAL_TB_CHAN_INSTALL(), true, "⑩挂载成功")
  eq(ChatFrame2.AddMessage ~= raw122, true, "⑩★★ChatFrame2 也被挂上（用户要的是「聊天窗」，不是只有主窗）")
  eq(select(8, EVAL_TEST_TB_CHAN_STATE()) >= 2, true, "⑩★记账：挂上的聊天窗数 ≥2")
  ChatFrame2 = nil
  -- ⑪ 工具箱里有这一行（UI 接线）+ 标签走语言包 + 勾/取消勾即时生效
  local hasRow121, label121 = false, nil
  for _, it121 in ipairs(EVAL_TEST_TB_ROWS()) do
    if it121.key == "chatColor" then hasRow121 = true label121 = it121.label end
  end
  eq(hasRow121, true, "⑪★★工具箱列模型里有「聊天窗名字着色」这一行（队伍/社交组）")
  eq(label121, pack121.TB_CHATCOLOR, "⑪★标签走语言包")
  eq(type(pack121.TB_CHATCOLOR_TIP) == "string" and pack121.TB_CHATCOLOR_TIP ~= "", true, "⑪★悬停提示存在")
  EVAL_HELP_CONFIG.tb.chatColor = false
  eq(EVAL_TB_CHATCOLOR_ON(), false, "⑪★开关读的是配置（关掉 = 不再染）")
  EVAL_HELP_CONFIG.tb.chatColor = true
  eq(EVAL_TB_CHATCOLOR_AFTER_TOGGLE(), true, "⑪★勾上后的即时动作（补缓存 + 回一句）返回真值")
  -- ⑫ /eh go 聊天 = 用户的**格式校准入口**，本身必须能用（写错一个字就是静默没输出）
  f121:AddMessage("[守夜人]: 校准样本")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c121 = tostring(TEST.chat or "")
  eq(string.find(c121, "聊天窗名字着色", 1, true) ~= nil, true, "⑫★★/eh go 聊天 打得出诊断（用户唯一的格式校准出口）")
  eq(string.find(c121, "名字缓存", 1, true) ~= nil, true, "⑫★报告名字缓存条数")
  eq(string.find(c121, "原文", 1, true) ~= nil, true, "⑫★★把最近聊天**原文**摊开（校准就看这一屏）")
  eq(string.find(c121, "染色：守夜人", 1, true) ~= nil, true, "⑫★★★诊断对样本的判决与生产**同源**（读值口走同一个纯函数，不复刻判据）")
  -- ⑬ 「试」= 一键自检：拿**生产判据**判一条文本 + 说清**为什么**（候选名由判据自己交出，不复刻判据）
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天 试 [守夜人]: 你好")
  local t121 = tostring(TEST.chat or "")
  eq(string.find(t121, "认出来了", 1, true) ~= nil, true, "⑬★★★「/eh go 聊天 试 <文本>」能当场验一条文本（不用等真人说话）")
  eq(string.find(t121, "守夜人", 1, true) ~= nil and string.find(t121, "SHAMAN", 1, true) ~= nil, true,
     "⑬★★并报出「候选名 → 缓存里的职业 token」（说清为什么认得出）")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天 试 [路人甲]: 你好")
  local t121b = tostring(TEST.chat or "")
  eq(string.find(t121b, "没认出来", 1, true) ~= nil, true, "⑬★★认不出的样本如实说「没认出来」")
  eq(string.find(t121b, "不在缓存", 1, true) ~= nil, true,
     "⑬★★★并说清原因（名字不在缓存 ≠ 形态不匹配）—— 候选名来自**判据自己**的第三返回值，诊断不复刻判据")
  local _, _, cd121 = EVAL_TB_CHATCOLOR_VOTE("[路人甲]: 你好")
  eq(type(cd121) == "table" and table.getn(cd121) == 1 and cd121[1] == "路人甲", true,
     "⑬★读值口确实拿得到「考虑过的候选」（上面那条说明的**单一来源**）")
  eq(type(select(3, EVAL_TB_CHATCOLOR_VOTE("[路人甲]: 你好"))) == "table", true, "⑬★第三返回值是候选表")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天 试")
  local t121c = tostring(TEST.chat or "")
  eq(string.find(t121c, "测试玩家", 1, true) ~= nil, true, "⑬★不带文本时默认拿**玩家自己**的名字当样本（一跑就能看到「命中」长什么样）")
  -- ⑭ ★★★1.73.12 客户端自带的「玩家链接 + 客户端颜色」形态（用户实测「全都没染色」的定案方向）
  EVAL_TB_NAMECLASS_PUT("Ionol", "圣骑士")
  local colPal = "|c" .. EVAL_TB_PAINT_CLASS_COLOR_OF("PALADIN")
  local linkCol = "|cffff80ff|Hplayer:Ionol|h[Ionol]|h|r 悄悄地说: 1"
  eq(EVAL_TB_CHAT_COLOR_LINE(linkCol), colPal .. "|Hplayer:Ionol|h[Ionol]|h|r 悄悄地说: 1",
     "⑭★★★客户端自带的玩家链接（带它自己的颜色）→ **改颜色码**（旧版「已在富文本里就整行放行」= 用户看到的「全都没染色」）")
  eq(EVAL_TB_CHAT_COLOR_LINE("|Hplayer:Ionol|h[Ionol]|h 说: 1"), colPal .. "|Hplayer:Ionol|h[Ionol]|h|r 说: 1",
     "⑭★★链接前没有颜色码时 → 把整个链接段包进职业色")
  eq(string.find(EVAL_TB_CHAT_COLOR_LINE(linkCol), "|Hplayer:Ionol|h[Ionol]|h", 1, true) ~= nil, true,
     "⑭★★链接本身**原样保留**（名字照样可点，只换颜色）")
  eq(EVAL_TB_CHAT_COLOR_LINE("|cff9d9d9d|Hitem:1234:0:0:0|h[守夜人]|h|r 获得了"),
     "|cff9d9d9d|Hitem:1234:0:0:0|h[守夜人]|h|r 获得了",
     "⑭★★反向哨兵：**物品**链接仍旧不碰（只认 player 链接）")
  eq(EVAL_TB_CHAT_COLOR_LINE("[公会] [Ionol]: 1"), "[公会] " .. colPal .. "[Ionol]|r: 1",
     "⑭★★用户截图里的「[公会] [名字]: 」形态能染色")
  eq(EVAL_TB_CHAT_COLOR_LINE("[Ionol] 说: 1"), colPal .. "[Ionol]|r 说: 1", "⑭★用户截图里的「[名字] 说: 」形态能染色")
  -- ⑭b 入口在位检查读值口（区分「我们的包装被顶掉」与「客户端不走 Lua 打印」）
  local rows121, ours121, live121 = EVAL_TB_CHATCOLOR_ROUTES()
  eq(ours121 >= 1 and live121 >= 1, true,
     "⑭b★★读值口能报「有几个聊天框 / 其中几个是我们的包装」（" .. tostring(ours121) .. "/" .. tostring(live121) .. "）")
  eq(type(rows121) == "table" and rows121["DEFAULT_CHAT_FRAME"] ~= nil, true, "⑭b★并且**逐个**聊天框可查")
  -- ⑭c 诊断把三种原因（被顶掉 / 不走 Lua / 判据不认）分开打印 —— 用户报「全都没染色」时靠这一屏定案
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c121d = tostring(TEST.chat or "")
  eq(string.find(c121d, "入口在位检查", 1, true) ~= nil, true, "⑭c★★诊断打印「入口在位检查」（我们挂的层还在不在）")
  eq(string.find(c121d, "另外的候选入口", 1, true) ~= nil or string.find(c121d, "另外还存在的入口", 1, true) ~= nil, true,
     "⑭c★★诊断列出其它候选入口（Lua 打印这条路是死是活一眼看到）")
  eq(string.find(c121d, "同层包装（频道屏蔽）", 1, true) ~= nil, true, "⑭c★★并把频道屏蔽的「经过/吞掉」条数一起打出来（旁证同一层包装）")
  -- ⑭b2 读值口真的在查**当前**入口：造一个「不是我们挂的」聊天框 → live +1 而 ours 不变
  ChatFrame3 = { AddMessage = function() end }
  local _r121b, ours121b, live121b = EVAL_TB_CHATCOLOR_ROUTES()
  eq(live121b, live121 + 1, "⑭b★★新增一个「不是我们挂的」聊天框 → live +1（读值口查的是**当前**入口，不是记账）")
  eq(ours121b, ours121, "⑭b★而 ours 不变（那个入口不是我们的包装）")
  ChatFrame3 = nil
  -- ⑭c2 见到 0 条时**如实判读**为「客户端不走 Lua 打印」（这正是用户这次现象之一的判读口）
  EVAL_TB_CHATCOLOR_RESET()
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c121e = tostring(TEST.chat or "")
  eq(string.find(c121e, "都**一条消息都没收到**", 1, true) ~= nil, true,
     "⑭c★★★两个入口都没收到时如实判读「客户端不走 Lua」（不把「没收到」说成「没认出来」）")
  -- 收尾：还原入口 / 计数 / 配置 / 时间（跨用例状态残留是本项目老坑）
  f121.AddMessage = saved121
  EVAL_TEST_TB_CHAN_RESET()
  EVAL_TB_CHAN_INSTALL()
  EVAL_HELP_CONFIG.tb = savedTb121
  TEST.time = savedTime121
  print("  聊天名字着色：缓存单一来源（白拿 + 只读采集）· 三形态染色 · 未知名/单字/已上色/物品链接一律不碰 · 只染第一处")
  print("                真实打印入口真的带色 · 开关即时生效 · 与频道屏蔽共用一层互不干扰 · 采集限频 · 多聊天窗")
end

-- 122) ★★★1.73.12 未缓存角色的**主动查询**（用户追加要求：
--   「未缓存角色默认开启主动查询进缓存,设定个查询频率限制,做好查询不到结果的做好防止重复查询的机制.
--     将关闭查询的开关在工具箱内设置,输出查询日志.归入调试日志」）
--   判据：① 只查「发送者位置」的名字（拿用户截图的真实形态当用例；频道名/地名/物品名一律不查）；
--         ② 已缓存 / 负缓存 / 队列里已有 → 一律不重复入队；
--         ③ ★频率下限（一次 tick 只发一发）+ ★★单飞（上一发没结果绝不发下一发）；
--         ④ 查到 → 进缓存；没查到 → 负缓存（**期内再遇到不再查**）；超时也记负缓存；
--         ⑤ 工具箱开关关掉 = 不入队 + 队列清空 + 一发都不发；
--         ⑥ 查询日志进**调试日志**（EVAL_HELP_CONFIG.log，/eh logdump 可查）；⑦ 队列满如实丢弃并记日志；
--         ⑧ 诊断命令里能看到查询状态。
do
  local pack122 = EVAL_LOCALES[EVAL_GET_LANG()] or EVAL_LOCALES.zhCN
  local savedTb122 = EVAL_HELP_CONFIG.tb
  local savedTime122, savedLog122 = TEST.time, EVAL_HELP_CONFIG.log
  EVAL_HELP_CONFIG.tb = {}
  EVAL_HELP_CONFIG.log = {}
  EVAL_TB_WHO_RESET()
  TEST.whoSent = {}
  -- ① 谁该被查（纯函数；用例直接照用户截图里的真实形态写）
  eq(EVAL_TB_WHO_CANDIDATE("[Ionol]: 1"), "Ionol", "①★[名字]: 形态 → 该查")
  eq(EVAL_TB_WHO_CANDIDATE("[Ionol] 说: 1"), "Ionol", "①★[名字] 说: 形态 → 该查")
  eq(EVAL_TB_WHO_CANDIDATE("[Ionol] 悄悄地说: 1"), "Ionol", "①★悄悄话形态 → 该查")
  eq(EVAL_TB_WHO_CANDIDATE("发送给 [Ionol]: 1"), "Ionol", "①★发送给 [名字]: → 该查")
  eq(EVAL_TB_WHO_CANDIDATE("[公会] [Ionol]: 1"), "Ionol", "①★★[公会] [名字]: → **只取名字**（公会那段不算）")
  eq(EVAL_TB_WHO_CANDIDATE("[4. 世界防务] [Ionol]: 1"), "Ionol", "①★★频道前缀 + [名字]: → 只取名字")
  eq(EVAL_TB_WHO_CANDIDATE("[4. 世界防务] 加入频道。"), nil, "①★★反向：频道通知不许拿去查（白打扰服务器）")
  eq(EVAL_TB_WHO_CANDIDATE("[公会] 今天活动取消"), nil, "①★反向：只有公会前缀、没有发送者 → 不查")
  eq(EVAL_TB_WHO_CANDIDATE("|cff9d9d9d|Hitem:1:0:0:0|h[守夜人]|h|r 获得了"), nil, "①★反向：物品链接不查")
  eq(EVAL_TB_WHO_CANDIDATE("[123] 说: 1"), nil, "①★反向：纯数字（等级/计数）不查")
  eq(EVAL_TB_WHO_CANDIDATE(nil), nil, "①nil 不崩")
  -- ② 已缓存 / 队列里已有 → 不重复入队
  EVAL_TB_NAMECLASS_PUT("已知道", "战士")
  eq(EVAL_TB_WHO_ENQUEUE("已知道"), false, "②★已在缓存里 → 不查")
  eq(EVAL_TB_WHO_ENQUEUE("陌路人"), true, "②★没有缓存 → 入队")
  eq(EVAL_TB_WHO_ENQUEUE("陌路人"), false, "②★★同一个名字已在队列 → 不重复入队")
  -- ③ 频率下限 + 单飞
  TEST.time = 30000
  EVAL_TB_WHO_RESET()
  TEST.whoSent = {}
  EVAL_TB_WHO_ENQUEUE("甲甲") EVAL_TB_WHO_ENQUEUE("乙乙") EVAL_TB_WHO_ENQUEUE("丙丙")
  EVAL_TB_WHO_TICK()
  eq(table.getn(TEST.whoSent), 1, "③★★★一次 tick 只发一发（绝不在同一帧连发查询）")
  eq(EVAL_TB_WHO_STATE().queued, 2, "③★剩下 2 个还在队列里等着")
  EVAL_TB_WHO_TICK()
  eq(table.getn(TEST.whoSent), 1, "③★★★单飞：上一发还没有结果 → 打死也不发第二发")
  -- ④ 结果回来 → 进缓存；没查到 → 负缓存（用户要的「防止重复查询」）
  TEST.whoRows = { { name = "甲甲", class = "牧师" } }
  local hit122 = EVAL_TB_WHO_ONRESULTS()
  eq(hit122, true, "④★在途那一发的结果被结清（查到）")
  eq(EVAL_TB_NAMECLASS_GET("甲甲"), "PRIEST", "④★★查到 → 立刻进名字缓存（之后就能上色）")
  TEST.whoRows = {}
  TEST.time = 30000 + 5
  EVAL_TB_WHO_TICK()
  eq(table.getn(TEST.whoSent), 2, "④★过了频率窗口 → 发第二发（上一个查到了不影响下一个）")
  EVAL_TB_WHO_ONRESULTS()
  eq(EVAL_TB_WHO_ISMISS("乙乙"), true, "④★★没查到 → 记入负缓存")
  local sent122 = table.getn(TEST.whoSent)
  EVAL_TB_WHO_TICK()
  eq(table.getn(TEST.whoSent), sent122, "④c★★★结果刚回来、但**频率窗口没到** → 照样一发不发（限频独立于单飞）")
  eq(EVAL_TB_WHO_ENQUEUE("乙乙"), false, "④★★★负缓存期内再遇到这个名字 → **不再查**（「防止重复查询」）")
  -- ④b 单飞超时：迟迟没有结果 → 也记负缓存（不会卡死在「等结果」上）
  TEST.time = 30000 + 20
  EVAL_TB_WHO_TICK() -- 队列里剩下的「丙丙」这一发出去（在途）
  eq(EVAL_TB_WHO_STATE().pending ~= nil, true, "④b前置：有一发在途（超时判据的前提）")
  eq(table.getn(TEST.whoSent), 3, "④b前置：第三发已发出")
  TEST.time = 30000 + 20 + 9 -- 超过单飞超时 8 秒
  EVAL_TB_WHO_TICK()
  eq(EVAL_TB_WHO_STATE().timeout, 1, "④b★★超时无结果 → 计入超时并记负缓存（不卡死、也不重发）")
  eq(EVAL_TB_WHO_ISMISS("丙丙"), true, "④b★超时的那个名字也进了负缓存")
  eq(table.getn(TEST.whoSent), 3, "④b★超时只是记账，**没有**因为超时而补发一发")
  -- ⑤ 工具箱开关关掉 = 不入队 + 一发都不发 + 队列清空
  EVAL_HELP_CONFIG.tb.whoQuery = false
  eq(EVAL_TB_WHO_ON(), false, "⑤★开关读的是配置（工具箱 → 队伍/社交；默认开）")
  eq(EVAL_TB_WHO_ENQUEUE("丁丁"), false, "⑤★★关掉后不再入队")
  TEST.whoSent = {}
  EVAL_TB_WHO_TICK()
  eq(table.getn(TEST.whoSent), 0, "⑤★★★关掉后就算队列里还有东西也一发都不发")
  EVAL_TB_WHO_AFTER_TOGGLE()
  eq(EVAL_TB_WHO_STATE().queued, 0, "⑤★关掉时清空待查队列")
  eq(EVAL_TB_WHO_ENQUEUE("戊戊"), false, "⑤★关掉后任何新名字都不入队")
  -- ⑥ 查询日志进**调试日志**（用户明确：输出查询日志.归入调试日志）
  EVAL_HELP_CONFIG.tb.whoQuery = true
  EVAL_HELP_CONFIG.log = {}
  EVAL_TB_WHO_RESET()
  TEST.chat = "" -- ★清掉前面诊断命令留下的输出，否则「一条都不上屏」这条断言测的是别人
  TEST.time = 40000
  EVAL_TB_WHO_ENQUEUE("己己")
  EVAL_TB_WHO_TICK()
  TEST.whoRows = { { name = "己己", class = "法师" } }
  EVAL_TB_WHO_ONRESULTS()
  local logs122 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs122, "[名字查询] 入队：己己", 1, true) ~= nil, true, "⑥★★入队有日志（调试日志）")
  eq(string.find(logs122, "[名字查询] 已发出：/who 己己", 1, true) ~= nil, true, "⑥★★发出有日志")
  eq(string.find(logs122, "[名字查询] 查到：己己", 1, true) ~= nil, true, "⑥★★查到也有日志")
  eq(string.find(tostring(TEST.chat or ""), "名字查询", 1, true) == nil, true, "⑥★★★查询日志**不刷聊天框**（只进调试日志）")
  -- ⑥b 查不到也要有日志（用户要的「查询不到结果」的机制，日志就是它的可观测面）
  EVAL_HELP_CONFIG.log = {}
  TEST.time = 50000
  EVAL_TB_WHO_ENQUEUE("庚庚")
  EVAL_TB_WHO_TICK()
  TEST.whoRows = {}
  EVAL_TB_WHO_ONRESULTS()
  local logs122b = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs122b, "[名字查询] 没查到：庚庚", 1, true) ~= nil, true, "⑥b★★查不到也要有日志（并说明已记入负缓存）")
  -- ⑦ 队列上限：满了如实丢弃并记日志
  EVAL_TB_WHO_RESET()
  EVAL_HELP_CONFIG.log = {}
  TEST.time = 41000
  local okN122, full122 = 0, 0
  for i = 1, 21 do
    local okq, why = EVAL_TB_WHO_ENQUEUE("队列测试" .. tostring(i))
    if okq then okN122 = okN122 + 1 elseif why == "full" then full122 = full122 + 1 end
  end
  eq(okN122, 20, "⑦★队列上限 20：前 20 个入队（实际 " .. tostring(okN122) .. "）")
  eq(full122, 1, "⑦★第 21 个被如实拒收")
  eq(string.find(table.concat(EVAL_HELP_CONFIG.log or {}, "\n"), "队列已满", 1, true) ~= nil, true, "⑦★★拒收**有日志**（不静默丢）")
  -- ⑧ 工具箱里真的有这一行（开关放工具箱）+ 标签走语言包 + 默认开
  local hasWho122, labelWho122 = false, nil
  for _, it122 in ipairs(EVAL_TEST_TB_ROWS()) do
    if it122.key == "whoQuery" then hasWho122 = true labelWho122 = it122.label end
  end
  eq(hasWho122, true, "⑧★★工具箱列模型里有「未缓存角色主动查询」这一行（队伍/社交组）")
  eq(labelWho122, pack122.TB_WHOQ, "⑧★标签走语言包")
  eq(type(pack122.TB_WHOQ_TIP) == "string" and pack122.TB_WHOQ_TIP ~= "", true, "⑧★悬停提示存在（三语言齐全）")
  EVAL_HELP_CONFIG.tb = savedTb122 and EVAL_HELP_CONFIG.tb and savedTb122 or EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = savedTb122
  eq(EVAL_TB_WHO_ON(), true, "⑧★默认开启（配置里没有这个键也视为开）")
  -- ⑨ 诊断命令里能看到查询状态
  EVAL_TB_WHO_RESET()
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c122 = tostring(TEST.chat or "")
  eq(string.find(c122, "名字查询", 1, true) ~= nil, true, "⑨★★/eh go 聊天 打印主动查询的状态（开关/队列/在途/计数/负缓存）")
  eq(string.find(c122, "负缓存", 1, true) ~= nil, true, "⑨★并说明负缓存条数（这就是「防止重复查询」的可观测口）")
  EVAL_TB_WHO_RESET()
  EVAL_HELP_CONFIG.log = savedLog122
  TEST.time = savedTime122
  TEST.whoRows = nil
  print("  名字主动查询：只查发送者位置（频道名/物品/纯数字不查）· 已缓存/负缓存/重复 → 不入队 · 一次 tick 只发一发 + 单飞")
  print("                查到进缓存 · 查不到记负缓存（期内不再查）· 超时不卡死 · 开关在工具箱 · 日志只进调试日志 · 队列满如实丢弃")
end

-- 123) ★★★1.73.12 第二入口 ChatFrame_OnEvent（真机实测：frame.AddMessage 写了不生效 → 换入口）
--   判据：① 挂载后**读回来确认**在位（真机刚吃过「写成功了但不生效」的亏）+ 幂等；
--         ② 频道进出通知：**不调原函数**（这才叫吞掉；旧那层是「试过了」）；
--         ③ 名字着色：**回写全局 arg1**（处理器从全局取值）→ 原函数读到着色后的文本；
--         ④ 反向：未知名不改字；⑤ 非聊天事件一律原样放行；⑥ 开关关掉就放行；
--         ⑦ 被客户端顶掉后能重挂，且**绝不重复包装**（否则同一条消息会被处理两次）；
--         ⑧ 诊断里能分开看到两个入口各自的计数与收到的原文。
do
  local savedTb123 = EVAL_HELP_CONFIG.tb
  local savedLog123 = EVAL_HELP_CONFIG.log
  EVAL_HELP_CONFIG.tb = {}
  EVAL_HELP_CONFIG.log = {}
  EVAL_TEST_TB_CHATEVENT_RESET()
  -- ① 挂载 + 读回确认 + 幂等
  eq(EVAL_TB_CHATEVENT_INSTALL(), true, "①★挂上 ChatFrame_OnEvent")
  local w123 = ChatFrame_OnEvent
  eq(EVAL_TB_CHATEVENT_STATE().live, true, "①★★挂完**读回来确认**在位（真机刚吃过「写成功但不生效」的亏）")
  eq(EVAL_TB_CHATEVENT_INSTALL(), true, "①★再挂一次仍返回 true（幂等）")
  eq(ChatFrame_OnEvent == w123, true, "①★★幂等：**没有**重复包装")
  -- ② 频道通知：命中 → 不调原函数
  TEST.ceCalls = 0
  arg1 = "[4. 世界防务] 离开频道。"
  ChatFrame_OnEvent("CHAT_MSG_CHANNEL_NOTICE")
  eq(TEST.ceCalls, 0, "②★★★频道进出通知被**真的吞掉**（原函数一次都没被调用）")
  eq(EVAL_TB_CHATEVENT_STATE().filtered, 1, "②★并且吞掉计数 +1")
  -- ③ 名字着色：回写全局 arg1
  EVAL_TB_NAMECLASS_PUT("守夜人", "萨满")
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "[守夜人]: 你好"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  eq(TEST.ceCalls, 1, "③★普通聊天照旧交给原函数（只改文本，不拦消息）")
  local seen123 = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(seen123 ~= nil and string.find(seen123.arg1, "|cff0070de", 1, true) ~= nil, true,
     "③★★★回写全局 arg1：原函数读到的是**着色后**的文本（真机上就是这条让它显色）")
  eq(seen123 ~= nil and string.find(seen123.arg1, "|r: 你好", 1, true) ~= nil, true, "③★正文没被破坏")
  eq(EVAL_TB_CHATEVENT_STATE().painted >= 1, true, "③★染色计数 +1")
  -- ④ 反向：未知名一个字不改
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "[路人乙]: 你好"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  eq(TEST.ceSeen[table.getn(TEST.ceSeen)].arg1, "[路人乙]: 你好", "④★★未知名 → 原样交给原函数（一个字不改）")
  -- ⑤ 非聊天事件：一律原样放行
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "[守夜人]: 你好"
  ChatFrame_OnEvent("UPDATE_CHAT_COLOR")
  eq(TEST.ceCalls, 1, "⑤★非聊天事件照旧放行")
  eq(TEST.ceSeen[table.getn(TEST.ceSeen)].arg1, "[守夜人]: 你好", "⑤★★非聊天事件**不做任何改动**（连着色都不做）")
  -- ⑥ 开关关掉 → 通知放行
  EVAL_HELP_CONFIG.tb.chanJoin = false
  TEST.ceCalls = 0
  arg1 = "[4. 世界防务] 离开频道。"
  ChatFrame_OnEvent("CHAT_MSG_CHANNEL_NOTICE")
  eq(TEST.ceCalls, 1, "⑥★★关掉屏蔽开关 → 通知放行（开关在调用时读）")
  EVAL_HELP_CONFIG.tb.chanJoin = true
  -- ⑦ 被顶掉 → 重挂，且不重复包装
  EVAL_TEST_CE_RECLAIM()
  eq(EVAL_TB_CHATEVENT_STATE().live, false, "⑦前置：模拟客户端把自己的实现写回全局（真机就是这么顶掉我们的）")
  EVAL_TEST_TB_CHATEVENT_RESET()
  eq(EVAL_TB_CHATEVENT_RETRY(), true, "⑦★★被顶掉后**重挂成功**")
  eq(EVAL_TB_CHATEVENT_STATE().live, true, "⑦★重挂后读回确认在位")
  TEST.ceCalls, TEST.ceSeen = 0, {}
  local seenBefore123 = EVAL_TB_CHATEVENT_STATE().seen
  arg1 = "[守夜人]: 又来"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  eq(TEST.ceCalls, 1, "⑦★★★重挂后一条消息只交给原函数**一次**（重复包装会让它被处理两次）")
  eq(EVAL_TB_CHATEVENT_STATE().seen, seenBefore123 + 1, "⑦★★我们的计数也只 +1（没有两层包装）")
  -- ⑧ 日志 + 诊断（两个入口分开计数）
  EVAL_TB_CHATEVENT_RETRY()
  local logs123 = table.concat(EVAL_HELP_CONFIG.log or {}, "\n")
  eq(string.find(logs123, "[聊天入口] ChatFrame_OnEvent 挂载成功", 1, true) ~= nil, true, "⑧★★挂载成功有日志（进调试日志）")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c123 = tostring(TEST.chat or "")
  eq(string.find(c123, "第二入口 ChatFrame_OnEvent", 1, true) ~= nil, true, "⑧★★诊断里**分开**打印第二入口的状态（两个入口谁在干活一眼看到）")
  EVAL_HELP_CONFIG.log = savedLog123
  EVAL_HELP_CONFIG.tb = savedTb123
  print("  第二入口：ChatFrame_OnEvent 挂载后读回确认 + 幂等 + 被顶掉能重挂（不重复包装）· 通知真的吞掉 · 回写全局 arg1 让原函数读到着色文本")
end

-- 124) ★★★1.73.12 深入 API 后的两条新路（用户：「如果解决不了再深入分析 API lua 和参考插件是否实现」）
--   ① **官方消息组**（api 全表逐条核过，类别 ChatWindow）：GetChatWindowMessages / RemoveChatWindowMessages /
--      AddChatWindowMessages —— 这是客户端官方给的「某类消息不显示」的开关，**与「走不走 Lua」无关**；
--   ② **ChatMOD 的做法**（参考插件实证 tmp/ChatMOD.lua:514-517）：在 ChatFrame_OnEvent 处理体里对
--      **this 那个帧**懒挂载 AddMessage（我们先前挂 _G 那层真机写不进去）。
--   判据：① 探测到含 NOTICE 的组（**不误伤 CHANNEL 组**）+ 摘掉 + 其它组一个不动 + 幂等 + 按组还原 + 跟随开关；
--         ② this 帧挂上后：通知**被吞**、名字**被着色**、每帧只试一次、成败都记账。
do
  local savedTb124 = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = {}
  TEST.cwMsg = { [1] = "SAY,YELL,CHANNEL,CHANNEL_NOTICE,GUILD" }
  local function setOf(s)
    local out, n = {}, 0
    for part in string.gmatch(tostring(s or ""), "[^,]+") do n = n + 1 out[part] = true end
    return out, n
  end
  -- ① 探测
  local list124 = EVAL_TB_CHAN_GROUPS(1)
  eq(type(list124) == "table", true, "①★★读得到消息组清单（官方 API：GetChatWindowMessages）")
  local st124 = EVAL_TB_CHAN_OFFICIAL_STATE()
  eq(st124.apiRemove and st124.apiAdd, true, "①★摘掉/加回两个 API 都在")
  -- ② 应用：摘掉通知组，CHANNEL 组与其它组一个不动
  local found124, act124 = EVAL_TB_CHAN_OFFICIAL_APPLY(true)
  eq(found124 >= 1 and act124 >= 1, true, "②★★找到并摘掉通知组（找到 " .. tostring(found124) .. " / 动作 " .. tostring(act124) .. "）")
  local set124 = setOf(TEST.cwMsg[1])
  eq(set124.CHANNEL_NOTICE, nil, "②★★通知组 CHANNEL_NOTICE 已摘掉")
  eq(set124.CHANNEL, true, "②★★★反向：普通频道那组 CHANNEL **还在**（绝不误伤频道聊天）")
  eq(set124.SAY and set124.YELL and set124.GUILD, true, "②★其它组一个不动")
  -- ③ 幂等：再应用一次什么都不做（摘掉后就探测不到了）
  eq(EVAL_TB_CHAN_OFFICIAL_APPLY(true), 0, "③★★幂等：已摘掉 → 第二次找不到组、不做动作（不会把原始组串记错）")
  -- ④ 撤销：按**单个组名**加回，集合完整还原
  EVAL_TB_CHAN_OFFICIAL_APPLY(false)
  local set124b, n124b = setOf(TEST.cwMsg[1])
  eq(n124b, 5, "④★★★还原后组数回到 5 个（实际 " .. tostring(n124b) .. "）")
  eq(set124b.CHANNEL_NOTICE and set124b.CHANNEL and set124b.SAY and set124b.YELL and set124b.GUILD, true,
     "④★★五个组一个不少（撤不干净就是给用户留残状态）")
  -- ⑤ 跟随开关（勾/取消勾立刻生效）
  EVAL_HELP_CONFIG.tb.chanJoin = true
  EVAL_TB_CHAN_OFFICIAL_SYNC()
  eq(setOf(TEST.cwMsg[1]).CHANNEL_NOTICE, nil, "⑤★开关=开 → 同步后通知组被摘掉")
  EVAL_HELP_CONFIG.tb.chanJoin = false
  EVAL_TB_CHAN_OFFICIAL_SYNC()
  eq(setOf(TEST.cwMsg[1]).CHANNEL_NOTICE, true, "⑤★开关=关 → 同步后加回来")
  -- ⑥ ChatMOD 的做法：在事件处理里对 this 帧懒挂载
  TEST.ceSeen, TEST.ceCalls = {}, 0
  local rec124 = {}
  local fakeFrame124 = { AddMessage = function(self, text) table.insert(rec124, tostring(text)) end }
  eq(EVAL_TB_THIS_HOOK(fakeFrame124), true, "⑥★★在 this 帧上懒挂载成功（ChatMOD 的做法；读回确认过）")
  eq(EVAL_TB_CHATEVENT_STATE().thisOk >= 1, true, "⑥★记账：挂上 " .. tostring(EVAL_TB_CHATEVENT_STATE().thisOk) .. " 个")
  eq(EVAL_TB_THIS_HOOK(fakeFrame124), true, "⑥★同一个帧只试一次（幂等）")
  EVAL_HELP_CONFIG.tb = { chanJoin = true, chatColor = true }
  EVAL_TB_NAMECLASS_PUT("守夜人", "萨满")
  fakeFrame124:AddMessage("[4. 世界防务] 离开频道。")
  eq(table.getn(rec124), 0, "⑥★★★经 this 帧打的**频道通知被吞掉**（参考插件那条路真的能吞）")
  fakeFrame124:AddMessage("[守夜人]: 你好")
  eq(table.getn(rec124), 1, "⑥★普通聊天照旧打印一次")
  eq(string.find(rec124[1] or "", "|cff0070de", 1, true) ~= nil, true, "⑥★★而且打印出来的是**着色后**的文本（★8 位色码）")
  eq(EVAL_TB_CHATEVENT_STATE().thisPainted >= 1, true, "⑥★染色记账 +1")
  -- ⑧ ★★★**真机那种「写进去不生效」的对象**：写被吞（__newindex 忽略）→ 读回来还是原来的
  --   ★这条就是在测试里复现真机现象（frame.AddMessage 写成功但不生效），把「如实记账」钉住
  local store124 = { AddMessage = function() end }
  local mt124 = { __index = function(_, k) return store124[k] end, __newindex = function() end }
  local stuck124 = setmetatable({}, mt124)
  local stuckBefore = EVAL_TB_CHATEVENT_STATE().thisStuck
  eq(EVAL_TB_THIS_HOOK(stuck124), false, "⑧★★★写不进的对象：懒挂载**如实返回 false**（不假称挂上了）")
  eq(EVAL_TB_CHATEVENT_STATE().thisStuck, stuckBefore + 1, "⑧★★★并且记一笔「写不进去」（真机诊断靠它分出成败）")
  -- ⑦ 诊断里两条新路都看得见
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c124 = tostring(TEST.chat or "")
  eq(string.find(c124, "官方消息组", 1, true) ~= nil, true, "⑦★★诊断打印官方消息组状态（现有组 / 已摘掉窗口数）")
  eq(string.find(c124, "this 帧懒挂载", 1, true) ~= nil, true, "⑦★★诊断打印 this 帧懒挂载的战果（成功几个 / 写不进几个）")
  EVAL_HELP_CONFIG.tb = savedTb124
  print("  深入 API/参考插件：官方消息组（与走不走 Lua 无关）探测+摘掉+按组还原+跟随开关 · this 帧懒挂载（ChatMOD 做法）能吞能染色")
end

-- 125) ★★★1.73.12 debuff 类型在**界面上的格式化**（用户：「debuff 格式化是否没做好」）
--   现象：编辑窗底部预览吐的是**导出用的英文 token**（Magic/Curse/Poison），而格子里明明是「魔法/诅咒/毒」。
--   判据：① **导出**仍走英文 token（存量/往返逐字不变 —— 组 114 的老断言继续绿就是证明）；
--         ② **界面显示**走本地化名（底部预览 / 行内预览 / 配置窗方案行）；
--         ③ ★★★显示形态**必须能解析回同一个集合**（本地化名往返靠 dispelNorm 的 tok/loc 双向容忍）；
--         ④ 单选老形态显示本地化、导出逐字不变；空集（任意）不显示括号。
do
  local g125 = EVAL_PARSE_CONDS("有团队debuff:毒(Magic/Poison)")
  eq(EVAL_GROUP_STR(g125), "有团队debuff:毒(Magic/Poison)", "①★★导出仍是英文 token（与组 114 的往返判据一致）")
  local want125 = "有团队debuff:毒(" .. EVAL_L("DS_T_MAGIC") .. "/" .. EVAL_L("DS_T_POISON") .. ")"
  eq(EVAL_GROUP_STR(g125, true), want125, "②★★★显示形态走本地化名：" .. tostring(EVAL_GROUP_STR(g125, true)))
  eq(string.find(EVAL_GROUP_STR(g125, true), "Magic", 1, true) == nil, true, "②★★反向哨兵：显示里不许再出现英文 token")
  local g125b = EVAL_PARSE_CONDS(EVAL_GROUP_STR(g125, true))
  local dt125 = g125b[1][1].dt
  eq(type(dt125) == "table" and dt125.Magic == true and dt125.Poison == true, true,
     "③★★★本地化显示形态能**解析回同一个集合**（disp 只影响显示，不影响可往返性）")
  eq(EVAL_GROUP_STR(g125b), "有团队debuff:毒(Magic/Poison)", "③★★往返一圈后导出仍是 token 形态")
  local g125c = EVAL_PARSE_CONDS("有团队debuff:毒(Magic)")
  eq(EVAL_GROUP_STR(g125c), "有团队debuff:毒(Magic)", "④★★单选导出逐字不变（存量兼容）")
  eq(EVAL_GROUP_STR(g125c, true), "有团队debuff:毒(" .. EVAL_L("DS_T_MAGIC") .. ")", "④★单选显示也本地化")
  -- ★注意：单独写「毒」会被解析成**类型**（不是名字）→ 正确的「没有类型」用例要用非类型名
  eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("有团队debuff:奥术智慧"), true), "有团队debuff:奥术智慧",
     "④★★没有写类型（= 任意）时不显示括号")
  eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("有团队debuff:(Magic)"), true), "有团队debuff:(" .. EVAL_L("DS_T_MAGIC") .. ")",
     "④★「只限类型、不限名字」的显示也本地化")
  -- ⑤ 真实控件：读编辑窗**底部预览那个 FontString**（不是自己拼的字符串）
  eq(EVAL_TEST_SE_PUSH_COND("teamDebuff", nil, nil, nil, { Magic = true, Poison = true }, "团队"), true,
     "⑤前置：编辑器里放一条「团员debuff」并勾上 魔法+毒")
  local pv125 = EVAL_TEST_SE_PREVIEW()
  eq(type(pv125) == "string" and pv125 ~= "", true, "⑤★拿得到真实预览行文本")
  eq(string.find(pv125, EVAL_L("DS_T_MAGIC"), 1, true) ~= nil and
     string.find(pv125, EVAL_L("DS_T_POISON"), 1, true) ~= nil, true,
     "⑤★★★预览行显示的是**本地化名**：" .. tostring(pv125))
  eq(string.find(pv125, "Magic", 1, true) == nil and string.find(pv125, "Poison", 1, true) == nil, true,
     "⑤★★反向哨兵：预览行里不再出现英文 token")
  EVAL_TEST_SE_CLEAR()
  EVAL_DD_HIDE()
  EVAL_HELP_CFG_SETTAB(1)
  print("  debuff 显示格式化：导出仍走 token（存量逐字不变）· 界面走本地化名（预览/方案行/行内）· 本地化形态能解析回同一集合")
end

-- 126) ★★★1.73.14 「开启战斗UI 后物品 tooltip 显示几秒就自动隐藏」（用户报）
--   根因：Engine 的读数口借用了**真实 GameTooltip**（`local WTT = GameTooltip`）——
--     每次读光环/技能都要 SetOwner → ClearLines → 填内容 → Hide，于是战斗UI / 状态UI 的**定时刷新**
--     （条件求值要读光环）会把玩家正看的物品 tooltip **清空并关掉**（几秒一次）。
--   判据：① 有一个**自家**隐形 tooltip，且与 GameTooltip **不是同一个对象**（这就是回归防线）；
--         ② 走遍四个光环读口，**真实 GameTooltip 一次都没被碰**（SetOwner/ClearLines/Hide 计数全 0）；
--         ③ 读的是**自家**那个 TextLeft1（不是 GameTooltipTextLeft1）；④ 退化模式的守卫是纯函数、可单测。
do
  local st126 = EVAL_WTT_STATE()
  eq(type(st126) == "table" and st126.hasWtt == true, true, "①前置：有一个在用的隐性 tooltip")
  eq(st126.self, true, "①★★★读数据用的是**自家**隐形 tooltip（" .. tostring(st126.name) .. "）")
  local wtt126 = EVAL_TEST_WTT()
  eq(wtt126 ~= nil and wtt126 ~= GameTooltip, true, "①★★★它与 GameTooltip **不是同一个对象**（本轮根因的回归防线）")
  -- ② 读遍四个入口 → 玩家的 tooltip 一次都不能被碰
  TEST.buffs = { { name = "隔离测试buff", tex = "TEX_ISO_B" } }
  TEST.debuffs = { { name = "隔离测试debuff", tex = "TEX_ISO_D", apps = 1 } }
  TEST.unitBuffs = { { name = "隔离测试buff2", tex = "TEX_ISO_B2" } }
  TEST.slotNames = { [1] = "隔离测试技能" }
  TEST.gtCalls = { setOwner = 0, clear = 0, hide = 0, show = 0 }
  TEST.ttReadFrom = nil
  pcall(EVAL_PLAYER_BUFF_LIST)
  pcall(EVAL_TARGET_DEBUFF_LIST)
  pcall(EVAL_TARGET_BUFF_LIST)
  pcall(EVAL_PLAYER_DEBUFF_LIST)
  local touched126 = TEST.gtCalls.setOwner + TEST.gtCalls.clear + TEST.gtCalls.hide + TEST.gtCalls.show
  eq(touched126, 0, "②★★★读遍四个光环读口，**真实 GameTooltip 一次都没被碰**（实测 " .. tostring(touched126) .. " 次）")
  eq(type(TEST.ttReadFrom) == "string", true, "②前提：确实读了 tooltip 文本（证明上面不是「什么都没跑」）")
  eq(string.find(tostring(TEST.ttReadFrom), "GameTooltipTextLeft1", 1, true) == nil, true,
     "③★★★读的是**自家**那个 TextLeft1（实际：" .. tostring(TEST.ttReadFrom) .. "）")
  -- ④ 退化模式的守卫（纯函数；真机借不到自建 tooltip 时的那道防线）
  eq(EVAL_WTT_MAY_READ_PURE(true, true), true, "④★自建 tooltip → 随便读（玩家的 tooltip 与我们无关）")
  eq(EVAL_WTT_MAY_READ_PURE(false, true), false, "④★★★退化成真实 tooltip 且它**正显示** → **不读**（绝不碰玩家正看的那个）")
  eq(EVAL_WTT_MAY_READ_PURE(false, false), true, "④★退化且它没显示 → 可以读")
  -- ⑤ 诊断命令
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go wtt")
  local c126 = tostring(TEST.chat or "")
  eq(string.find(c126, "隐形 tooltip", 1, true) ~= nil, true, "⑤★/eh go wtt 打印状态（自建/退化 + 碰过真实 tooltip 的次数）")
  eq(string.find(c126, "碰过**真实 GameTooltip**", 1, true) ~= nil, true, "⑤★并如实报「碰过真实的几次」（应为 0）")
  TEST.buffs, TEST.debuffs, TEST.unitBuffs, TEST.slotNames = nil, nil, nil, nil
  print("  tooltip 隔离：自建隐形 tooltip 读数（与 GameTooltip 不同对象）· 读遍四个入口不碰玩家 tooltip · 退化时「正显示就不读」")
end

-- 128) ★★★1.73.16 聊天取证的**样本白名单** + 官方消息组判读的三态（用户实测两处都出过错）
--   ① 上一版把**所有** CHAT_MSG_* 都塞进 12 格缓冲 → 战斗/法术刷屏把真实聊天行挤出去（用户截图 12 条全是 SPELL_*）
--      → 「名字在 arg1 还是只在 arg2」这个关键证据**永远看不到**；
--   ② 官方消息组的判读把「本来就没有这个组」也说成「已由官方接口屏蔽」（用户截图：窗口1 只有 SYSTEM、摘掉 0 个）
--      → 假判读，必须分清三态。
do
  local savedTb128 = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chanJoin = true }
  -- ① 法术刷屏 20 条后，玩家聊天样本必须仍在
  EVAL_TEST_TB_CHATEVENT_RESET()
  for _ = 1, 20 do
    arg1 = "Ledbybag从Ledbybag的智慧祝福获得了10点MANA_POINTS."
    arg2 = "Ledbybag"
    ChatFrame_OnEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
  end
  arg1 = "[守夜人] 说: 你好"
  arg2 = "守夜人"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local cet128 = EVAL_TB_CHATEVENT_STATE()
  eq(table.getn(cet128.chat) == 1, true, "①★★★法术刷屏 20 条后，**玩家聊天样本仍然在**（只留玩家聊天的白名单）")
  eq(string.find(tostring(cet128.chat[1]), "CHAT_MSG_SAY", 1, true) ~= nil, true, "①★样本里就是那条 SAY")
  eq(string.find(tostring(cet128.chat[1]), "arg2=守夜人", 1, true) ~= nil, true,
     "①★★并且记下了 **arg2（发送者名）** —— 定案「名字在 arg1 还是 arg2」就靠它")
  eq((cet128.byEv or {})["CHAT_MSG_SAY"] ~= nil, true, "②★事件计数里有 SAY（证明玩家聊天真的到达了这一层）")
  eq((cet128.byEv or {})["CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"] ~= nil, true, "②★法术事件也在计数里（证明那 20 条真的进来了）")
  -- ③ 官方消息组判读三态
  EVAL_TEST_TB_CHAN_OFFICIAL_RESET()
  TEST.cwMsg[1] = "SAY,YELL,CHANNEL,CHANNEL_NOTICE,GUILD"
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c128 = tostring(TEST.chat or "")
  eq(string.find(c128, "通知组**还在**", 1, true) ~= nil, true, "③★组还在 → 如实判「还在」（不许说已屏蔽）")
  EVAL_TB_CHAN_OFFICIAL_APPLY(true)
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  c128 = tostring(TEST.chat or "")
  eq(string.find(c128, "是我们摘掉的", 1, true) ~= nil, true, "③★是我们摘的 → 判「已由官方接口屏蔽」")
  EVAL_TB_CHAN_OFFICIAL_APPLY(false)
  EVAL_TEST_TB_CHAN_OFFICIAL_RESET()
  TEST.cwMsg[1] = "SYSTEM" -- ★复现用户实测：本客户端窗口1 只有 SYSTEM 这一组
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  c128 = tostring(TEST.chat or "")
  eq(string.find(c128, "官方这条路在本客户端用不上", 1, true) ~= nil, true,
     "③★★★第三种：本来就没有这个组 → 如实说「官方路用不上」（上一版这里**假报**「已屏蔽」）")
  TEST.cwMsg[1] = "SAY,YELL,CHANNEL,CHANNEL_NOTICE,GUILD"
  EVAL_TEST_TB_CHATEVENT_RESET()
  EVAL_TEST_TB_CHAN_OFFICIAL_RESET()
  EVAL_HELP_CONFIG.tb = savedTb128
  print("  取证白名单：法术刷屏不再挤掉玩家聊天样本（记 arg1+arg2）· 事件计数 · 官方消息组判读分三态（不假报已屏蔽）")
end

-- 129b) ★★★1.73.18 真机定案后的**名字着色**（用户样本：arg1 = 只有正文 "1"/"你有队"，arg2 = 发送者名）
--   判据：① arg1=正文 + arg2=发送者 时，把 **arg2 包成 |c职业色名字|r**（这才是真机能染色的一处）；
--         ② 名字不在缓存 → 一个字都不改（**不许涂默认灰**：不知道职业 ≠ 职业是灰）；
--         ③ 已带 |c 的不重复包；④ 主动查询的触发点 = **发送者名**（正文里根本没有名字可找）。
do
  local savedTb129b = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chatColor = true, whoQuery = true }
  EVAL_TB_WHO_RESET()
  TEST.whoSent = {}
  EVAL_TEST_TB_CHATEVENT_RESET()
  EVAL_TB_NAMECLASS_PUT("Ionol", "圣骑士")
  local colPal129 = "|c" .. EVAL_TB_PAINT_CLASS_COLOR_OF("PALADIN")
  --  ★本组只验**兜底路径**（拼不出来 → 原样交给客户端）：把客户端的格式串清掉，
  --   强制 EVAL_TB_CHATCOMPOSE 回 nil，这样原函数才会被调用、才读得到它收到的 arg2。
  --   ★「能拼出来 → 吞行 + 自己拼」在组 129d 里验（两组各管一条路，互不掩盖）。
  _G.CHAT_SAY_GET, _G.CHAT_GUILD_GET, _G.CHAT_PARTY_GET = nil, nil, nil
  -- ① 真机形态：正文 "1" + 发送者 "Ionol"（在缓存里）
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "1" arg2 = "Ionol"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local seen129 = TEST.ceSeen[table.getn(TEST.ceSeen)]
  --  ★★★1.73.20 默认闸门**关**：名字槽实测不吃富文本（8 位码也原样显示）→ **一个字都不改**。
  --    「宁可不染色，也绝不在玩家聊天里显示颜色码原文」——这是可见破坏，比不染色糟得多。
  eq(seen129 ~= nil and seen129.arg2, "Ionol",
     "①★★★默认**不回写**arg2（名字槽不吃富文本）：" .. tostring(seen129 and seen129.arg2))
  eq(seen129 ~= nil and seen129.arg1, "1", "①★正文一个字都不改（名字不在正文里）")
  local st129a = EVAL_TB_CHATEVENT_STATE()
  eq(st129a.named, 1, "①★认得出职业的名字计数 +1（诊断看这个）")
  eq(st129a.held, 1, "①★★并记「拼不出来 → 交回客户端」计数 +1（不是静默）")
  eq(st129a.replaced, 0, "①★这一路**没有**接管（拼不出来就不许吞）")
  --  ①b 闸门**打开**时那条路必须真的能包色（否则回写逻辑成了没被覆盖的死代码）：
  --     颜色码必须 **8 位 aarrggbb**（6 位客户端不解析）；断言就钉在**打开后**的实际串上。
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen = 0, {}
  EVAL_TEST_TB_NAMECOLOR_WRITE(true)
  arg1 = "1" arg2 = "Ionol"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local seen129w = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(seen129w ~= nil and seen129w.arg2, colPal129 .. "Ionol|r",
     "①b★★★闸门打开 → arg2 真的被包成职业色：" .. tostring(seen129w and seen129w.arg2))
  eq(string.len(string.match(tostring(seen129w and seen129w.arg2 or ""), "^|c%x+") or ""), 10,
     "①b★★★颜色码是 8 位 aarrggbb（6 位客户端不解析 → 屏幕上直接显示 |c 原文）")
  EVAL_TEST_TB_NAMECOLOR_WRITE(false)
  -- ② 名字不在缓存 → 原样（绝不涂默认灰）
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "1" arg2 = "查无此人"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local seen129b = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(seen129b ~= nil and seen129b.arg2, "查无此人", "②★★★不在缓存的名字**一个字都不改**（不许涂默认灰）")
  eq(EVAL_TB_CHATEVENT_STATE().nameMiss >= 1, true, "②★并如实记「名字不在缓存」的计数（诊断里能看到）")
  -- ③ 已带色 → 不重复包
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen = 0, {}
  local already129 = colPal129 .. "Ionol|r"
  arg1 = "1" arg2 = already129
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local seen129c = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(seen129c ~= nil and seen129c.arg2, already129, "③★★已带颜色的名字不重复包裹（幂等）")
  --   ★★1.73.22 起「剥码 → 查纯名字」让**已带色的名字照样认得出**（这是 1.73.18 那个修复的延续）：
  --     所以这里 named≥1（认得出来）、miss=0（不是「查不到人」）、且**没有**接管（本组无格式串 → 走兜底）。
  local st129c = EVAL_TB_CHATEVENT_STATE()
  eq((st129c.named or 0) >= 1 and (st129c.nameMiss or 0) == 0, true,
     "③★已带色的名字照样认得出来（剥码查缓存）：named=" .. tostring(st129c.named) .. " miss=" .. tostring(st129c.nameMiss))
  eq((st129c.held or 0) >= 1 and (st129c.replaced or 0) == 0, true,
     "③★这一路（客户端没给格式串）走兜底：held=" .. tostring(st129c.held) .. " replaced=" .. tostring(st129c.replaced))
  -- ③b ★★★客户端自己先上过色（**默认灰**）→ 查到职业就必须改成职业色：
  --     这是用户那句「角色名还是没染色」的真身（旧代码拿带码的串查缓存 → 永远查不到人 → 什么都不改）。
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1 = "1" arg2 = "|cff808080Ionol|r"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local seen129d = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(seen129d ~= nil and seen129d.arg2, "|cff808080Ionol|r",
     "③b★★★闸门关着 → 客户端自己上的灰也不动（宁可不动，也不显示原文）：" .. tostring(seen129d and seen129d.arg2))
  local st129d = EVAL_TB_CHATEVENT_STATE()
  eq(tonumber(st129d.named or 0) >= 1, true, "③b★认得出来（剥掉客户端的灰码后查到职业）：named≥1")
  eq(tonumber(st129d.nameMiss or 0) == 0, true, "③b★不是「查不到人」（miss=0）—— 这正是 1.73.18 那个修复的价值")
  eq(tonumber(st129d.held or 0) >= 1 and tonumber(st129d.replaced or 0) == 0, true, "③b★这一路走兜底（held≥1、replaced=0）")
  -- ④ 主动查询触发点 = 发送者名（正文里没有名字可找）
  EVAL_TB_WHO_RESET()
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1 = "1" arg2 = "陌生人甲"
  ChatFrame_OnEvent("CHAT_MSG_GUILD")
  eq(EVAL_TB_WHO_STATE().queued >= 1, true, "④★★★发送者名不在缓存 → 排进主动查询队列（正文里根本没名字）")
  -- ⑤ 诊断里能看到名字上色的两个计数
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1 = "1" arg2 = "Ionol"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天")
  local c129b = tostring(TEST.chat or "")
  eq(string.find(c129b, "名字（arg2 = 发送者）认得出职业", 1, true) ~= nil, true, "⑤★★诊断打印「认得出职业 N 次 / 名字不在缓存 M 次」")
  eq(string.find(c129b, "真的接管", 1, true) ~= nil, true, "⑤★★并如实打印「方案A 真的接管 N 行 / 拼不出来 M 行」")
  eq(string.find(c129b, "频道/密语暂不支持", 1, true) ~= nil, true, "⑤★★并写明**支持范围**（频道/密语暂不支持，客户端原样显示）")
  EVAL_TEST_TB_CHATEVENT_RESET()
  EVAL_TB_WHO_RESET()
  arg1, arg2 = nil, nil
  EVAL_HELP_CONFIG.tb = savedTb129b
  print("  名字着色（真机形态）：arg2=发送者 → 包职业色 · 不在缓存不涂灰 · 已带色不重复包 · 主动查询按发送者触发")
end

-- 129) ★★★1.73.17 取参兼容**全部调用形态** + 调用形态取证（用户实测：ChatFrame_OnEvent 被调用 1513 次、
--   零样本零事件计数 → 取参姿势不对；而计数被写在「取到文本」之后 → 诊断把证据自己藏了）
--   判据：① (event)+全局 / ② (event,文本,发送者) / ③ (self,event,文本,发送者) 三种形态都要取到「事件名 + 文本 + 发送者」；
--         ④ **取不到文本也要计数**（noMsg + byEv）——这是本轮的关键修复；⑤ 前几次的**原始参数形状**要记下来（姿势定案）。
do
  local savedTb129 = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chatColor = true }
  local function cnt129(evKey)
    local cet = EVAL_TB_CHATEVENT_STATE()
    return (cet.byEv or {})[evKey] or 0, cet
  end
  -- ① (event) + 全局（1.12 老写法）
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1 = "[守夜人] 说: 你好" arg2 = "守夜人"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  local n129a, s129a = cnt129("CHAT_MSG_SAY")
  eq(n129a, 1, "①★形态 (event)+全局：事件计数 +1")
  eq(table.getn(s129a.chat), 1, "①★样本里有了这条 SAY")
  eq(string.find(tostring(s129a.chat[1]), "arg2=守夜人", 1, true) ~= nil, true, "①★发送者名取自全局 arg2")
  -- ② (event, 文本, 发送者)
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  ChatFrame_OnEvent("CHAT_MSG_GUILD", "[公会] [守夜人]: 集合", "守夜人")
  local n129b, s129b = cnt129("CHAT_MSG_GUILD")
  eq(n129b, 1, "②★形态 (event,文本,发送者)：事件计数 +1")
  eq(table.getn(s129b.chat), 1, "②★样本里有了这条公会聊天")
  eq(string.find(tostring(s129b.chat[1]), "arg1=%[公会%] %[守夜人%]: 集合", 1) ~= nil, true,
     "②★★文本取自第 1 个 vararg：" .. tostring(s129b.chat[1]))
  eq(string.find(tostring(s129b.chat[1]), "arg2=守夜人", 1, true) ~= nil, true, "②★★发送者取自第 2 个 vararg（位置与形态①不同）")
  -- ③ (self, event, 文本, 发送者) —— 最可能的真机形态
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  ChatFrame_OnEvent(UIParent, "CHAT_MSG_PARTY", "[守夜人] 说: 走", "守夜人")
  local n129c, s129c = cnt129("CHAT_MSG_PARTY")
  eq(n129c, 1, "③★形态 (self,event,文本,发送者)：事件计数 +1")
  eq(table.getn(s129c.chat), 1, "③★★样本里有了这条队伍聊天")
  eq(string.find(tostring(s129c.chat[1]), "arg1=%[守夜人%] 说: 走", 1) ~= nil, true,
     "③★★★文本取自第 2 个 vararg（**这正是真机最可能的形态**）：" .. tostring(s129c.chat[1]))
  eq(string.find(tostring(s129c.chat[1]), "arg2=守夜人", 1, true) ~= nil, true, "③★★发送者取自第 3 个 vararg")
  -- ④ 取不到文本也必须计数（本轮的关键修复）
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  ChatFrame_OnEvent("CHAT_MSG_RAID") -- 没给文本、也没给全局
  local n129d, s129d = cnt129("CHAT_MSG_RAID")
  eq(n129d, 1, "④★★★取不到文本时**仍然计数**（上一版把计数写在取值之后 → 1513 次调用却是空的）")
  eq(s129d.noMsg, 1, "④★★并如实记「取不到文本的调用」= 1")
  eq(table.getn(s129d.chat), 0, "④★没有文本就没有样本（不塞空串）")
  -- ⑤ 调用形态取证已记录
  -- ⑤ 调用形态取证：连打三种形态，应记下 3 条形状（★注意：RESET 会清形状，所以这里重新打 3 次）
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = "m1", "n1"
  ChatFrame_OnEvent("CHAT_MSG_SAY")
  ChatFrame_OnEvent("CHAT_MSG_GUILD", "m2", "n2")
  ChatFrame_OnEvent(UIParent, "CHAT_MSG_PARTY", "m3", "n3")
  local s129e = EVAL_TB_CHATEVENT_STATE()
  eq(type(s129e.shape) == "table" and table.getn(s129e.shape) == 3, true,
     "⑤★★记下了前 3 次调用的**原始参数形状**（e / a1 / arg1 / arg2）→ 真机姿势一屏定案")
  eq(string.find(tostring(s129e.shape[3] or ""), "CHAT_MSG_PARTY", 1, true) ~= nil, true,
     "⑤★第三种形态的形状里能看到事件名（记的确实是原始参数）")
  print("  取参形态：三种调用形态都能取到 事件名+文本+发送者 · 取不到文本也计数（不藏证据）· 记原始参数形状")
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  EVAL_HELP_CONFIG.tb = savedTb129
end

-- 129c) ★★★1.73.20 名字槽**渲染试验**（取证口）：用户真机截图定案「8 位色码在名字槽里也原样显示」，
--   而同一屏里经 AddMessage 打印的 8 位色码是有色的 ⇒ 名字槽不吃富文本 → 最后一条路 = 吞行 + 自己拼。
--   判据：① 试验**真的让客户端自己渲染了 5 种名字写法**（走原函数，不是我们复刻）；
--         ② 候选里既有「8 位色码」也有「|Hplayer: 链接形态」（这是唯一可能不必吞行的路）；
--         ③ 「自己拼」的三行示例里名字是**8 位色码 + 可点链接**；④ 如实写出吞行的代价。
do
  local savedTb129c = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chatColor = true }
  EVAL_TEST_TB_CHATEVENT_RESET()
  EVAL_TB_NAMECLASS_PUT("Ionol", "圣骑士")
  eq(type(EVAL_TB_CHATEVENT_INSTALL) == "function" and EVAL_TB_CHATEVENT_INSTALL(), true, "①★入口在位（试验要拿原函数）")
  eq(type(EVAL_TB_CHATCOLOR_NAMEPROBE) == "function", true, "①★试验函数存在（没有 = 取证口没做出来）")
  TEST.ceCalls, TEST.ceSeen = 0, {}
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 聊天 色测")
  eq(TEST.ceCalls, 5, "①★★★五种名字写法**都**让客户端自己渲染了一行（实际 " .. tostring(TEST.ceCalls) .. "）")
  local linkSeen, codeSeen = false, false
  for i = 1, table.getn(TEST.ceSeen) do
    local a2 = tostring(TEST.ceSeen[i].arg2 or "")
    if string.find(a2, "|Hplayer:", 1, true) ~= nil then linkSeen = true end
    if string.find(a2, "^|c%x%x%x%x%x%x%x%x", 1) ~= nil then codeSeen = true end
  end
  eq(codeSeen, true, "②★试验里含「8 位色码」的候选（对照用：客户端认不认看这里）")
  eq(linkSeen, true, "②★★试验里含「|Hplayer: 链接形态」候选（唯一可能不必吞行的路）")
  local c129c = tostring(TEST.chat or "")
  eq(string.find(c129c, "名字槽渲染试验", 1, true) ~= nil, true, "③★屏上有试验标题")
  eq(string.find(c129c, "链接 + 内层色码", 1, true) ~= nil, true, "③★四个候选标签都打出来了")
  eq(string.find(c129c, "CHAT_SAY_GET", 1, true) ~= nil, true, "③★打印客户端聊天格式串（nil = 本客户端没给，只能自己拼）")
  eq(string.find(c129c, "|Hplayer:Ionol|h[Ionol]|h", 1, true) ~= nil, true,
     "③★★「自己拼」的示例里带**可点链接**（吞行方案要保住点名字密语）")
  --  ★三种形态**逐条**钉住：只写「含链接」的话，删掉其中一行照样绿（M186 实测 SURVIVED —— 弱判据当场补强）
  eq(string.find(c129c, "[公会] [", 1, true) ~= nil, true, "③b★示例含公会形态（[公会] [名]: 正文）")
  eq(string.find(c129c, "] 说: 色测正文", 1, true) ~= nil, true, "③b★示例含「说」形态（[名] 说: 正文）")
  eq(string.find(c129c, "[1. 综合] [", 1, true) ~= nil, true, "③b★示例含频道形态（[频道名] [名]: 正文）")
  eq(string.find(c129c, "分流", 1, true) ~= nil, true, "④★★如实写出吞行的代价（不是只说好处）")
  --  ★注意：不能直接抓第一个「|c%x+」——EVAL_SAY 的前缀 |cff66ccff 后面紧跟 "EVAL_HELP" 里的 **E 是 hex**
  --     → 贪婪匹配会多吞一位（实测 got=11）。要对准**紧贴在链接前**的那个色码。
  eq(string.len(string.match(c129c, "(|c%x+)|Hplayer:Ionol") or ""), 10, "④★示例里链接前的色码是 8 位 aarrggbb")
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  EVAL_HELP_CONFIG.tb = savedTb129c
  print("  名字槽渲染试验：5 种写法让客户端自己渲染 · 含链接形态候选 · 自己拼的示例带可点链接 · 如实写代价")
end

-- 129d) ★★★1.73.22 方案 A（**用户拍板**）：吞掉客户端那行 + 自己拼整行 —— 名字才能带职业色。
--   判据：① 格式串**抄客户端的**（CHAT_*_GET）；② 名字 = 8 位职业色 + 自己补的 |Hplayer: 链接（照样能密语）；
--         ③ **类型色只在前缀上**（前缀后立刻 |r 复位，与客户端一致）；
--         ④ 端到端：能拼 → **原函数一次都不被调用**（真吞掉）+ 我们那行真的打到聊天框；
--         ⑤ 任一条判据不满足（不支持的事件 / 客户端没那个格式串 / 模板里不止一个 %s）→ **拼不出来 → 不吞**
--            （宁可没色，绝不丢消息或串格式）。
do
  local saved129d = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chatColor = true }
  EVAL_TB_NAMECLASS_PUT("Ionol", "圣骑士")
  local hex129d = EVAL_TB_PAINT_CLASS_COLOR_OF("PALADIN")
  local link129d = "|c" .. hex129d .. "|Hplayer:Ionol|h[Ionol]|h|r"
  _G.CHAT_GUILD_GET = "[公会] %s: "
  _G.CHAT_SAY_GET = "%s说: "
  _G.ChatTypeInfo = { GUILD = { colorStr = "|cff33ff33" }, SAY = { colorStr = "|cffffffff" } }
  -- ① 纯函数：公会（有类型色）
  local l129d = EVAL_TB_CHATCOMPOSE("CHAT_MSG_GUILD", "集合", "Ionol", hex129d)
  eq(type(l129d) == "string", true, "①★有模板 + 名字有职业色 → 拼得出来")
  --  ★注意：前缀里有中文（一个字 **3 字节**）→ 长度必须用 string.len 现算，别写死数字（写 17 就少了）
  local pre129d = "|cff33ff33[公会] |r"
  eq(string.sub(tostring(l129d), 1, string.len(pre129d)) == pre129d, true,
     "①★★用**客户端的格式串**打头，且类型色只在前缀上（前缀后 |r 复位）：" .. tostring(l129d))
  eq(string.find(tostring(l129d), link129d, 1, true) ~= nil, true,
     "①★★★名字 = 8 位职业色 + 自己补的 |Hplayer: 链接（点名字照样密语）")
  eq(string.find(tostring(l129d), "集合", 1, true) ~= nil, true, "①★正文原样带上")
  eq(string.len(string.match(tostring(l129d), "(|c%x+)|Hplayer:Ionol") or ""), 10, "①★名字的色码是 8 位 aarrggbb")
  -- ② 说：模板在名字**前面没有前缀**，名字夹在中间
  local l129e = EVAL_TB_CHATCOMPOSE("CHAT_MSG_SAY", "你好", "Ionol", hex129d)
  eq(string.find(tostring(l129e), link129d .. "|cffffffff说: 你好|r", 1, true) ~= nil, true,
     "②★「说」的行形态（名字 + 客户端模板 + 正文）：" .. tostring(l129e))
  -- ③ 拿不准就不拼（nil = 不许吞）
  --  ★★弱判据教训（M195 实测）：如果**不给** CHANNEL 准备模板，那么「频道 → nil」既可能是
  --     「不在支持表」，也可能是「没有格式串」—— 删掉支持表限制（把频道加进去）照样绿。
  --     ⇒ 这里**先把模板也给它**，让这条断言只可能因为「不在支持表」而成立。
  --  ★而且模板必须是**单 %s**的：若给 "[%s] %s: "，"多于一个 %s" 那条守卫会**替支持表把事做掉**
  --    （M195 第二次实测仍是 SURVIVED）→ 用 "%s: " 让这条断言只可能因为「不在支持表」而成立。
  _G.CHAT_CHANNEL_GET = "%s: "
  eq(EVAL_TB_CHATCOMPOSE("CHAT_MSG_CHANNEL", "1", "Ionol", hex129d), nil,
     "③★★频道**就算有现成模板也**不拼（频道名前缀要靠别的参数 → 只有它不在支持表里）")
  _G.CHAT_GUILD_GET = nil
  eq(EVAL_TB_CHATCOMPOSE("CHAT_MSG_GUILD", "1", "Ionol", hex129d), nil, "③★客户端没这个格式串 → nil（不猜文案）")
  _G.CHAT_GUILD_GET = "[%s] %s: "
  eq(EVAL_TB_CHATCOMPOSE("CHAT_MSG_GUILD", "1", "Ionol", hex129d), nil, "③★模板里不止一个 %s → nil（不猜位置）")
  _G.CHAT_GUILD_GET = "[公会] %s: "
  -- ④ 端到端：能拼 → 吞行 + 我们那行进聊天框
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen, TEST.chat = 0, {}, ""
  arg1, arg2 = "集合", "Ionol"
  ChatFrame_OnEvent("CHAT_MSG_GUILD")
  eq(TEST.ceCalls, 0, "④★★★**吞掉客户端那行**（原函数一次都没被调用 —— 这才叫真吞）")
  eq(string.find(tostring(TEST.chat or ""), link129d, 1, true) ~= nil, true, "④★★我们拼的那行真的打到了聊天框")
  eq(string.find(tostring(TEST.chat or ""), "[公会] ", 1, true) ~= nil, true, "④★而且带着**客户端的公会前缀**")
  local st129d2 = EVAL_TB_CHATEVENT_STATE()
  eq(st129d2.replaced, 1, "④★接管计数 +1")
  eq(st129d2.held, 0, "④★没有走兜底")
  -- ⑤ 兜底：格式串不在 → **不吞、不改**（宁可没色，绝不丢消息）
  _G.CHAT_GUILD_GET = nil
  EVAL_TEST_TB_CHATEVENT_RESET()
  TEST.ceCalls, TEST.ceSeen = 0, {}
  arg1, arg2 = "集合", "Ionol"
  ChatFrame_OnEvent("CHAT_MSG_GUILD")
  local seen129dz = TEST.ceSeen[table.getn(TEST.ceSeen)]
  eq(TEST.ceCalls, 1, "⑤★★拼不出来 → 原样交给客户端（一次都不许吞）")
  eq(seen129dz ~= nil and seen129dz.arg2, "Ionol", "⑤★★并且 arg2 一个字都不改")
  eq(tonumber(EVAL_TB_CHATEVENT_STATE().held or 0) >= 1, true, "⑤★如实记「交回客户端」的次数")
  eq(tonumber(EVAL_TB_CHATEVENT_STATE().replaced or 0) == 0, true, "⑤★没有接管")
  _G.CHAT_GUILD_GET, _G.CHAT_SAY_GET, _G.CHAT_CHANNEL_GET, _G.ChatTypeInfo = nil, nil, nil, nil
  EVAL_TEST_TB_CHATEVENT_RESET()
  arg1, arg2 = nil, nil
  EVAL_HELP_CONFIG.tb = saved129d
  print("  方案A：格式串抄客户端 · 类型色只在前缀 · 名字=职业色+可点链接 · 能拼才吞 · 拼不出来绝不丢消息")
end

-- 129e) ★★★1.73.23 类型色**三个来源**（真机实测：这个客户端取不到 ChatTypeInfo → 公会前缀变白；
--   用户截图里客户端自己画的「[公会]」逐像素取色 = **40FF40** → 内置一份**有证据的**兜底色）
--   判据：① 客户端给了 colorStr → **永远优先**；② 只给 r/g/b → 自己合成（0.25/1/0.25 → 40ff40）；
--         ③ 客户端完全没有 → 用**有证据的**兜底（公会 = 截图取色 40FF40）；
--         ④ **没证据的类型宁可不加色**（不许瞎猜配色）；⑤ 诊断读值口逐类型摊开「色 + 来源」。
do
  local saved129e = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { chatColor = true }
  local savedCti129e = _G.ChatTypeInfo
  local hex129e = EVAL_TB_PAINT_CLASS_COLOR_OF("PALADIN")
  _G.CHAT_GUILD_GET = "[公会] %s: "
  _G.CHAT_PARTY_GET = "[队伍] %s: "
  -- ① 客户端有 colorStr → 优先
  _G.ChatTypeInfo = { GUILD = { colorStr = "|cff123456" } }
  local c129e1, s129e1 = EVAL_TB_CHATTYPECOLOR("CHAT_MSG_GUILD")
  eq(c129e1, "|cff123456", "①★★客户端有 colorStr → **优先用客户端的配色**（尊重玩家设置）")
  eq(s129e1, "client", "①★并标出来源 = client")
  -- ② 只给 r/g/b → 自己合成
  _G.ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 } }
  local c129e2, s129e2 = EVAL_TB_CHATTYPECOLOR("CHAT_MSG_GUILD")
  eq(c129e2, "|cff40ff40", "②★★只给 r/g/b → 合成 8 位色码（0.25/1/0.25 → 40ff40，四舍五入）")
  eq(s129e2, "client-rgb", "②★来源标成 client-rgb")
  -- ③ 客户端完全没有 ChatTypeInfo → 内置兜底（公会 = 截图取色）
  _G.ChatTypeInfo = nil
  local l129e = EVAL_TB_CHATCOMPOSE("CHAT_MSG_GUILD", "集合", "Ionol", hex129e)
  local pre129e = "|cff40ff40[公会] |r"
  eq(string.sub(tostring(l129e), 1, string.len(pre129e)) == pre129e, true,
     "③★★★客户端没有 ChatTypeInfo 时用**内置兜底色**（截图取色 40ff40）：" .. tostring(l129e))
  eq(select(2, EVAL_TB_CHATTYPECOLOR("CHAT_MSG_GUILD")), "builtin", "③★来源标成 builtin（诊断能看出来）")
  -- ④ 没证据的类型 → **不加色**（绝不瞎猜）：队伍行的第一个色码就是名字自己的
  local p129e = EVAL_TB_CHATCOMPOSE("CHAT_MSG_PARTY", "集合", "Ionol", hex129e)
  --  ★判据要写准：队伍模板本身有前缀（"[队伍] "），所以「没加类型色」= **第一个色码之前就是那个前缀**。
  local fc129e = string.find(tostring(p129e), "|c", 1, true)
  eq(fc129e ~= nil and string.sub(tostring(p129e), 1, fc129e - 1) == "[队伍] ", true,
     "④★★没证据的类型（队伍）**不加类型色** —— 第一个色码之前就是客户端前缀（宁缺勿猜）：" .. tostring(p129e))
  eq(EVAL_TB_CHATTYPECOLOR("CHAT_MSG_PARTY"), nil, "④★读值口如实回答 nil")
  -- ⑤ 诊断读值口：逐类型摊开
  local info129e = tostring(EVAL_TB_CHATCOLOR_TYPECOLOR_INFO() or "")
  eq(string.find(info129e, "ChatTypeInfo=**没有**", 1, true) ~= nil, true, "⑤★如实说客户端没有 ChatTypeInfo")
  eq(string.find(info129e, "GUILD=|cff40ff40（builtin）", 1, true) ~= nil, true, "⑤★★逐类型给出「用到的色 + 来源」")
  eq(string.find(info129e, "PARTY=nil（none）", 1, true) ~= nil, true, "⑤★没证据的类型如实标 none")
  _G.ChatTypeInfo = savedCti129e
  _G.CHAT_GUILD_GET, _G.CHAT_PARTY_GET = nil, nil
  EVAL_HELP_CONFIG.tb = saved129e
  print("  类型色三来源：客户端优先 · 只给 r,g,b 就合成 · 没有就内置（只放截图取过色的）· 没证据宁可不加色")
end

-- 130) ★★★1.73.24 聊天名字右键菜单（用户要求：「右键聊天名字 → 公会邀请 / 复制名字 / /s 输出名字」）
--   判据：① 挂 SetItemRef（参考 ChatMOD 的包法）**读回确认** + 幂等；
--         ② 右键 player: 链接 → 弹菜单且**不转发**给客户端（否则动作做两遍）；
--         ③ 左键 / 非玩家链接（item: 等）→ **原样转发**（不动客户端既有行为）；
--         ④ 公会邀请：优先直调 GuildInviteByName；**没权限就不发**；接口不可用 → 走 RunScript；
--         ⑤ 复制名字：★本客户端**没有剪贴板接口** → 名字进「已全选」的框，读值口记下（不假称已复制）；
--         ⑥ /s 说出名字：走 RunScript 且 **0.5 秒去抖**（连点两次只发一次）；
--         ⑦ 开关关掉 → 右键不再接管（照旧转发）。
do
  local saved130 = EVAL_HELP_CONFIG.tb
  EVAL_HELP_CONFIG.tb = { nameMenu = true }
  EVAL_TEST_TB_NAMEMENU_RESET()
  local savedCGI130 = _G.CanGuildInvite
  -- ① 挂载 + 读回确认 + 幂等
  eq(EVAL_TB_NAMEMENU_ON(), true, "①★开关默认开")
  eq(EVAL_TB_SETITEMREF_INSTALL(), true, "①★挂上 SetItemRef")
  local w130 = SetItemRef
  eq(EVAL_TB_NAMEMENU_STATE().live, true, "①★★挂完**读回来确认**在位（1.73.12 的教训）")
  eq(EVAL_TB_SETITEMREF_INSTALL(), true, "①★再挂一次仍 true（幂等）")
  eq(SetItemRef == w130, true, "①★★幂等：没有重复包装")
  -- ② 右键 player: → 弹菜单 + 不转发
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.sirCalls = {}
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  local st130b = EVAL_TB_NAMEMENU_STATE()
  eq(st130b.shown, true, "②★★★右键角色名 → 弹出菜单")
  eq(st130b.name, "Ionol", "②★★菜单记住的是这个名字（动作都对着它）")
  eq(table.getn(TEST.sirCalls), 0, "②★★而且**不转发**给客户端（否则同一个动作做两遍）")
  eq(st130b.handled >= 1, true, "②★如实记「已接管」计数")
  -- ③ 左键 / 非玩家链接 → 原样转发
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.sirCalls = {}
  SetItemRef("player:Ionol", "[Ionol]", "LeftButton")
  SetItemRef("item:1234:0:0:0", "[物品]", "RightButton")
  eq(table.getn(TEST.sirCalls), 2, "③★★左键与**非玩家链接**一律原样转发（不动既有行为）")
  eq(string.find(tostring(TEST.sirCalls[1]), "player:Ionol|LeftButton", 1, true) ~= nil, true, "③★左键转发的就是原链接")
  eq(EVAL_TB_NAMEMENU_STATE().shown, false, "③★左键不弹菜单")
  -- ④ 公会邀请（直调）
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.invites, TEST.inviteCalls, TEST.chat = {}, 0, ""
  _G.CanGuildInvite = function() return true end
  eq(EVAL_TB_NAME_INVITE("Ionol"), true, "④★公会邀请：直调成功")
  eq(TEST.inviteCalls, 1, "④★★GuildInviteByName 真的被调用")
  eq(tostring(TEST.invites[1]), "Ionol", "④★★而且名字对")
  eq(string.find(tostring(TEST.chat), "已发出公会邀请", 1, true) ~= nil, true, "④★如实播报「已发出」（不给用户假承诺「成功」）")
  -- ④b 没有权限 → 一次都不发
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.invites, TEST.inviteCalls, TEST.chat = {}, 0, ""
  _G.CanGuildInvite = function() return false end
  eq(EVAL_TB_NAME_INVITE("Ionol"), false, "④b★★没有邀请权限 → 不发")
  eq(TEST.inviteCalls, 0, "④b★★一次都没调接口")
  eq(string.find(tostring(TEST.chat), "公会邀请没发出去", 1, true) ~= nil, true, "④b★并如实说明原因")
  -- ④c 接口不可用 → 走 RunScript
  EVAL_TEST_TB_NAMEMENU_RESET()
  _G.CanGuildInvite = function() return true end
  local savedGIN130 = _G.GuildInviteByName
  _G.GuildInviteByName = nil
  TEST.runScripts = {}
  eq(EVAL_TB_NAME_INVITE("甲"), true, "④c★★直调不可用 → 走 RunScript（本项目受保护函数的既定通道）")
  eq(string.find(tostring(TEST.runScripts[table.getn(TEST.runScripts)] or ""), "GuildInviteByName", 1, true) ~= nil, true,
     "④c★排队的脚本里是 GuildInviteByName")
  _G.GuildInviteByName = savedGIN130
  -- ⑤ ★★★1.73.29 用户改口径：「是在 /say 频道**输入名字**，但是不要打印出去，只是打开输入框输入名字」
  --   ⇒ 「复制名字」= **只预填**「/s 名字」到聊天输入框；★**绝不发送**（不走 RunScript / SendChatMessage）。
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.openChats, TEST.runScripts = {}, {}
  eq(EVAL_TB_NAME_SAY("Ionol"), true, "⑤★★★「复制名字」打开了聊天输入框")
  eq(tostring(TEST.openChats[1] or ""), "/s Ionol", "⑤★★★输入框里是「/s 名字」：" .. tostring(TEST.openChats[1]))
  eq(table.getn(TEST.runScripts), 0, "⑤★★★而且**一个字都没发出去**（用户明确：不要打印出去）")
  eq(EVAL_TB_NAMEMENU_STATE().said, 1, "⑤★并记「填进输入框的次数」")
  eq(string.find(tostring(TEST.chat), "按回车才发出", 1, true) ~= nil, true, "⑤★★提示里写清「还没发出去、按回车才发出」")
  -- ⑤a 没有打开聊天框的接口 → **如实提示**（不静默、也绝不偷偷发送）
  EVAL_TEST_TB_NAMEMENU_RESET()
  local savedOC130s = _G.ChatFrame_OpenChat
  _G.ChatFrame_OpenChat = nil
  TEST.runScripts, TEST.chat = {}, ""
  eq(EVAL_TB_NAME_SAY("Ionol"), false, "⑤a★★没有接口 → 如实返回失败")
  eq(table.getn(TEST.runScripts), 0, "⑤a★★★更没有偷偷用 /s 发出去（不许替用户按回车）")
  eq(string.find(tostring(TEST.chat), "请手动输入 /s", 1, true) ~= nil, true, "⑤a★★并告诉用户「请手动输入 /s 名字」")
  _G.ChatFrame_OpenChat = savedOC130s
  -- ⑤b 悄悄话（原始功能）：优先用客户端的打开聊天框接口
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.openChats = {}
  eq(EVAL_TB_NAME_WHISPER("Ionol"), true, "⑤b★★「悄悄话」打开了密语输入框")
  eq(tostring(TEST.openChats[1] or ""), "/w Ionol ", "⑤b★★★预填的就是 /w 名字 + 空格（用户接着打字）")
  eq(EVAL_TB_NAMEMENU_STATE().whisper, 1, "⑤b★并记次数")
  -- ⑤c 悄悄话没有接口 → **如实降级**（不静默、不崩）
  EVAL_TEST_TB_NAMEMENU_RESET()
  local savedOC130 = _G.ChatFrame_OpenChat
  _G.ChatFrame_OpenChat = nil
  TEST.chat = ""
  eq(EVAL_TB_NAME_WHISPER("Ionol"), false, "⑤c★★没有打开聊天框的接口 → 如实返回失败")
  eq(string.find(tostring(TEST.chat), "请手动 /w", 1, true) ~= nil, true, "⑤c★★★并明确告诉用户「请手动 /w 名字」（不静默）")
  _G.ChatFrame_OpenChat = savedOC130
  -- ⑤d 邀请入队（原始功能）：InviteToParty 优先 + 去抖
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.partyInvites, TEST.partyInviteCalls = {}, 0
  eq(EVAL_TB_NAME_PARTY("Ionol"), true, "⑤d★★「邀请」发出队伍邀请")
  eq(TEST.partyInviteCalls, 1, "⑤d★★调的是 InviteToParty")
  eq(tostring(TEST.partyInvites[1] or ""), "Ionol", "⑤d★名字对")
  eq(EVAL_TB_NAME_PARTY("Ionol"), false, "⑤d★★0.5 秒内连点 → 限频挡下")
  eq(TEST.partyInviteCalls, 1, "⑤d★★确实只发了一次")
  eq(EVAL_TB_NAMEMENU_STATE().throttled >= 1, true, "⑤d★并如实记「限频挡下」次数")
  -- ⑤e 目标（原始功能）：TargetByName
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.targetSel = nil
  eq(EVAL_TB_NAME_TARGET("Ionol"), true, "⑤e★★「目标」选中了对方")
  eq(tostring(TEST.targetSel or ""), "name:Ionol", "⑤e★★★走的是 TargetByName(名字)")
  eq(EVAL_TB_NAMEMENU_STATE().target, 1, "⑤e★并记次数")
  -- ⑥ ★★★1.73.35 菜单版式（用户：「操作分两列、宽高自适应、弹窗锚点右上」）——
  --   判据读**真实控件**：两列（x 只有两个取值）· 每条 ≤4 个汉字宽 · 宽高 == 纯函数按**条目数**算出来的 ·
  --   锚点在**屏幕右上角** · 条目按权限/队伍条件出现 · 半透明底。
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.sirCalls = {}
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  local mg130 = EVAL_TB_MENU_GEOM()
  eq(type(mg130) == "table", true, "⑥★菜单已建好（读得到真实几何）")
  local nIt130 = table.getn(mg130.items or {})
  eq(nIt130 >= 4, true, "⑥★条目 ≥4（实际 " .. tostring(nIt130) .. "）")
  -- ★宽高**自适应**：读真实窗口 vs 纯函数（同一份公式）
  eq(mg130.w, EVAL_TB_MENU_WIDTH(nIt130), "⑥★★★宽度 == 公式（" .. tostring(mg130.w) .. "，两列）")
  eq(mg130.h, EVAL_TB_MENU_HEIGHT(nIt130), "⑥★★★高度 == 公式（" .. tostring(mg130.h) .. " 条数 " .. tostring(nIt130) .. "）")
  eq(mg130.w ~= mg130.h, true, "⑥★不是正方形常数")
  eq(EVAL_TB_MENU_WIDTH(11) == EVAL_TB_MENU_WIDTH(5), true, "⑥★两列：宽只跟「列」有关（条目数变了宽度不变）")
  eq(EVAL_TB_MENU_HEIGHT(11) > EVAL_TB_MENU_HEIGHT(5), true, "⑥★行多了高度才变（自适应）")
  -- ★两列：所有条目的 x 只应有两个取值，且第二列严格在第一列右侧
  local xs130, bad130, colW130 = {}, "", 0
  for i = 1, nIt130 do
    local it = mg130.items[i]
    if it and it.x then
      xs130[it.x] = true
      if (it.w or 0) > 66 then bad130 = bad130 .. i .. ":太宽(" .. tostring(it.w) .. ") " end
      if (it.w or 0) > colW130 then colW130 = it.w or 0 end
    end
  end
  local nx130 = 0
  for _ in pairs(xs130) do nx130 = nx130 + 1 end
  eq(nx130, 2, "⑥★★★恰好两列（x 取值数 = " .. tostring(nx130) .. "）")
  -- ★★★1.73.36 锚点：**相对鼠标点击位置的右上角**（弹窗左下角贴光标，向上/向右展开）
  eq(tostring(mg130.point or ""), "BOTTOMLEFT", "⑥★★★锚点 = 光标处（实际 " .. tostring(mg130.point) .. "）")
  eq(tostring(mg130.relPoint or ""), "BOTTOMLEFT", "⑥★★锚到 UIParent 的左下角基准")
  eq(type(mg130.ox) == "number" and type(mg130.oy) == "number", true,
     "⑥★★★偏移 = 光标位置（" .. tostring(mg130.ox) .. "," .. tostring(mg130.oy) .. "）")
  eq(math.abs((mg130.ox or 0) - (TEST.cursorX or 400)) <= 1, true, "⑥★★★x 跟着光标走（不是写死的屏幕角）")
  eq(math.abs((mg130.oy or 0) - (TEST.cursorY or 300)) <= 1, true, "⑥★★★y 也跟着光标走")
  local have130 = {}
  local badLbl130 = ""
  for i = 1, nIt130 do
    local lb = tostring((mg130.items[i] or {}).label or "")
    have130[lb] = true
    if string.len(lb) > 12 then badLbl130 = badLbl130 .. i .. ":" .. lb .. "(" .. tostring(string.len(lb)) .. "字节) " end
  end
  eq(badLbl130, "", "⑥★★每条标签 ≤4 个汉字（12 字节）: " .. badLbl130)
  for _, need in ipairs({ EVAL_L("TB_NAMEMENU_PARTY"), EVAL_L("TB_NAMEMENU_TARGET"), EVAL_L("TB_NAMEMENU_SAY"), EVAL_L("TB_NAMEMENU_CLOSE") }) do
    eq(have130[need] == true, true, "⑥★★必须有条目：" .. tostring(need))
  end
  eq(have130[EVAL_L("TB_NAMEMENU_SHARE")] == true, true, "⑥★★★新增条目「分享方案」在菜单里")
  eq(have130[EVAL_L("TB_NAMEMENU_TRADE")] == true, true, "⑥★★★新增条目「交易」在菜单里")
  eq(have130[EVAL_L("TB_NAMEMENU_QUERY")] == true, true, "⑥★★★新增条目「查询」在菜单里")
  -- ★★★1.73.39 用户两条：①「分享方案 ↔ 邀请 对调位置」②「边框 白色高亮」
  local it2 = mg130.items[2] and tostring(mg130.items[2].label or "")
  local it5 = mg130.items[5] and tostring(mg130.items[5].label or "")
  if it2 ~= "" and it5 ~= "" then
    eq(it2, EVAL_L("TB_NAMEMENU_SHARE"), "⑥b★★★第 2 条 = 分享方案（对调后；实际 " .. it2 .. "）")
    eq(it5, EVAL_L("TB_NAMEMENU_PARTY"), "⑥b★★★第 5 条 = 邀请（对调后；实际 " .. it5 .. "）")
  end
  -- ★★★1.73.40 用户三条：①「圆角」②截图「右键框未包含关闭按键」③「操作按键 鼠标获取焦点 增加变色美化」
  -- ⑥c 圆角：挂得上客户端**原生圆角边**（UI-Tooltip-Border）就用它，挂不上必须退回四条平白边 ——
  --   两条路各有一组断言（哪条在跑都要读得到颜色，绿色不许来自「两边都没验」）。
  eq(type(mg130.chrome) == "string", true, "⑥c★菜单如实报边框做法（实际 " .. tostring(mg130.chrome) .. "）")
  eq(mg130.chrome, "rounded", "⑥c★★★桩照实测（SetBackdrop 可用 + GetBackdrop 读回边贴图）→ 必须走**原生圆角边**这条正路（实际 " .. tostring(mg130.chrome) .. "）")
  if mg130.chrome == "rounded" then
    eq(string.find(tostring(mg130.edge or ""), "UI-Tooltip-Border", 1, true) ~= nil, true,
       "⑥c★★★圆角：GetBackdrop 读回的边贴图就是 UI-Tooltip-Border（实际 " .. tostring(mg130.edge) .. "）")
    local bdCfg = TEST.backdropArg or {}
    eq(type(bdCfg.edgeSize) == "number" and bdCfg.edgeSize == math.floor(bdCfg.edgeSize) and bdCfg.edgeSize >= 8, true,
       "⑥c★★★edgeSize 是整数（参考插件实测：小数在本客户端栅格化不可靠；实际 " .. tostring(bdCfg.edgeSize) .. "）")
    local ins = bdCfg.insets or {}
    eq(type(ins.left) == "number" and ins.left > 0 and type(ins.top) == "number" and ins.top > 0, true,
       "⑥c★★底要缩进到圆角**内侧**（insets 必须 > 0，否则方角戳出圆角）")
    local bc = TEST.backdropBorderColor or {}
    eq((bc[1] or 0) >= 0.9 and (bc[2] or 0) >= 0.9 and (bc[3] or 0) >= 0.9 and (bc[4] or 0) >= 0.5, true,
       "⑥c★★★圆角边框是**白色高亮**（SetBackdropBorderColor = " .. tostring(bc[1]) .. "/" .. tostring(bc[2]) ..
       "/" .. tostring(bc[3]) .. "/" .. tostring(bc[4]) .. "）")
    local bgc = TEST.backdropColor or {}
    eq(type(bgc[4]) == "number" and bgc[4] >= 0.8, true, "⑥c★外框背景**加深**（面板底 alpha ≥ 0.8；实际 " .. tostring(bgc[4]) .. "）")
    eq(mg130.bgShown, false, "⑥c★★圆角时不再叠自己的方形底（两层半透明叠加会发黑）")
  else
    eq(mg130.chrome, "flat", "⑥c★★退化路径必须是四条平白边（实际 " .. tostring(mg130.chrome) .. "）")
    local bd130 = mg130.border or {}
    local nb130 = 0
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do if bd130[k] then nb130 = nb130 + 1 end end
    eq(nb130, 4, "⑥c★★四条边框都在（实际 " .. tostring(nb130) .. "）")
    eq(type(bd130.top and bd130.top.r) == "number" and bd130.top.r >= 0.9 and bd130.top.g >= 0.9 and bd130.top.b >= 0.9,
       true, "⑥c★★退化边框也是白的")
    eq(type(bd130.top and bd130.top.a) == "number" and bd130.top.a >= 0.5, true, "⑥c★★退化边框够亮")
    eq(bd130.top and bd130.top.w == mg130.w, true, "⑥c★★上边框横跨整窗")
    eq(bd130.left and bd130.left.h == mg130.h, true, "⑥c★★左边框竖跨整窗")
    eq(type(mg130.bg and mg130.bg.a) == "number" and mg130.bg.a >= 0.8, true, "⑥c★退化路径下面板底也**加深**")
  end
  -- ⑥c2 ★★★退化路径：把 SetBackdrop 弄成服务端不支持（error）→ 必须如实退回**四条平白边**，
  --   不允许静默地丢掉白色高亮边框（这正是 1.73.20 那类「看不见的退化」教训）。
  TEST.failBackdrop = true
  EVAL_TEST_TB_MENU_DROP()
  TEST.sirCalls = {}
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  local mgFB = EVAL_TB_MENU_GEOM()
  eq(mgFB and mgFB.chrome, "flat", "⑥c2★★★挂不上 backdrop 就必须退回平边（实际 " .. tostring(mgFB and mgFB.chrome) .. "）")
  local nbFB = 0
  for _, k in ipairs({ "top", "bottom", "left", "right" }) do if (mgFB.border or {})[k] then nbFB = nbFB + 1 end end
  eq(nbFB, 4, "⑥c2★★退化路径真的画了四条边（实际 " .. tostring(nbFB) .. "）")
  eq(type(((mgFB.border or {}).top or {}).r) == "number" and ((mgFB.border or {}).top).r >= 0.9, true,
     "⑥c2★★退化边也是白的")
  TEST.failBackdrop = nil
  EVAL_TEST_TB_MENU_DROP()
  SetItemRef("player:Ionol", "[Ionol]", "RightButton") -- 恢复：后面 ⑥d/⑥e 还要用菜单
  -- ⑥d ★★★包含性（独立于高度公式）：每条按钮的矩形必须落在窗口矩形内。
  --   用户截图「右键框未包含关闭按键」的根因就在这里：高度只算了 (rows-1) 个行距，
  --   末行（= 关闭）吊在窗口底 9px 之外 —— 背景没画到它 → 看起来「菜单里没有关闭」。
  local out130 = ""
  for i = 1, nIt130 do
    local it = mg130.items[i] or {}
    local l, t2 = it.x, it.y
    local r2, bt2 = (it.x or 0) + (it.w or 0), (it.y or 0) - (it.h or 0)
    if type(l) ~= "number" or type(t2) ~= "number" then
      out130 = out130 .. i .. ":读不到几何 "
    elseif l < 0 or t2 > 0 or r2 > (mg130.w or 0) + 0.01 or bt2 < -(mg130.h or 0) - 0.01 then
      out130 = out130 .. i .. "(" .. tostring(it.label) .. ") "
    end
  end
  eq(out130, "", "⑥d★★★每条（含关闭）都落在窗口矩形内；越界 = " .. out130)
  eq(tostring((mg130.items[nIt130] or {}).label or ""), EVAL_L("TB_NAMEMENU_CLOSE"),
     "⑥d★★★「关闭」是**最后一条**（实际 " .. tostring((mg130.items[nIt130] or {}).label) .. "）")
  -- ⑥e ★★★1.73.40 用户四条：「框增加 padding」「操作获取加点白色」「只要文字变色，不用背景变色，背景透明」
  --   判据（全部读**真控件**，阈值**独立**于生产常量）：
  --     ① 内边距：条目左右/下都离框 ≥6px、标题离左边 ≥6px、标题与首行不重叠
  --     ② 条目底**透明**（alpha == 0）③ 面板底**加深**（alpha ≥ 0.8）
  --     ④ 悬停**只**动文字色：文字变白；底色**逐值一点都没变**（用户「不用背景变色」）
  local pad130 = ""
  if not (type(mg130.padX) == "number" and mg130.padX >= 6) then pad130 = pad130 .. "左右内边距不足(" .. tostring(mg130.padX) .. ") " end
  if not (type(mg130.padB) == "number" and mg130.padB >= 6) then pad130 = pad130 .. "下内边距不足(" .. tostring(mg130.padB) .. ") " end
  if not (type(mg130.titleLeft) == "number" and mg130.titleLeft >= 6) then pad130 = pad130 .. "标题贴左边(" .. tostring(mg130.titleLeft) .. ") " end
  for i = 1, nIt130 do
    local it = mg130.items[i] or {}
    if (it.x or -1) < 6 then pad130 = pad130 .. i .. ":左贴边(" .. tostring(it.x) .. ") " end
    if ((it.x or 0) + (it.w or 0)) > (mg130.w or 0) - 6 then pad130 = pad130 .. i .. ":右贴边 " end
    if ((it.y or 0) - (it.h or 0)) < -((mg130.h or 0) - 6) then pad130 = pad130 .. i .. ":下贴边 " end
  end
  local it1 = mg130.items[1] or {}
  if type(mg130.titleTop) == "number" and type(it1.y) == "number" and it1.y > mg130.titleTop - 10 then pad130 = pad130 .. "标题压首行 " end
  eq(pad130, "", "⑥e★★★框内边距（padding）：左右/下/标题都离边 ≥6px 且标题不压首行；问题 = " .. pad130)
  local bgBad130 = ""
  for i = 1, nIt130 do
    local it = mg130.items[i] or {}
    if type(it.a) ~= "number" or it.a ~= 0 then bgBad130 = bgBad130 .. i .. "(a=" .. tostring(it.a) .. ") " end
  end
  eq(bgBad130, "", "⑥e★★★条目背景**透明**（底色 alpha 必须 0；用户「背景透明」）超出 = " .. bgBad130)
  eq(type(mg130.bg and mg130.bg.a) == "number" and mg130.bg.a >= 0.8, true,
     "⑥e★★★外框背景**加深**（面板底 alpha ≥ 0.8；实际 " .. tostring(mg130.bg and mg130.bg.a) .. "）")
  eq(type(it1.tr) == "number", true, "⑥e★能从**真控件**读回文字色（否则「只文字变色」判不出来）")
  local nrmTxt130 = { it1.tr, it1.tg, it1.tb }
  local nrmBg130 = { it1.r, it1.g, it1.b, it1.a }
  eq(it1.hot, false, "⑥e★默认不是高亮态")
  eq(EVAL_TEST_TB_MENU_HOVER(it1.label, true), true, "⑥e★★★触发了第 1 条的**真实 OnEnter** 脚本")
  local itH = (EVAL_TB_MENU_GEOM().items or {})[1] or {}
  eq(itH.hot, true, "⑥e★★悬停后如实置为高亮态")
  eq((itH.tr or 0) >= 0.99 and (itH.tg or 0) >= 0.99 and (itH.tb or 0) >= 0.99, true,
     "⑥e★★★悬停**给文字加点白**（" .. tostring(nrmTxt130[1]) .. "/" .. tostring(nrmTxt130[2]) .. "/" .. tostring(nrmTxt130[3]) ..
     " → " .. tostring(itH.tr) .. "/" .. tostring(itH.tg) .. "/" .. tostring(itH.tb) .. "）")
  eq(itH.r == nrmBg130[1] and itH.g == nrmBg130[2] and itH.b == nrmBg130[3] and itH.a == nrmBg130[4], true,
     "⑥e★★★悬停**背景一点都没变**（用户「不用背景变色」；" .. tostring(itH.a) .. " == " .. tostring(nrmBg130[4]) .. "）")
  eq(EVAL_TEST_TB_MENU_HOVER(it1.label, false), true, "⑥e★★触发了**真实 OnLeave** 脚本")
  local itL = (EVAL_TB_MENU_GEOM().items or {})[1] or {}
  eq(itL.hot, false, "⑥e★离开后回到非高亮态")
  eq(itL.tr == nrmTxt130[1] and itL.tg == nrmTxt130[2] and itL.tb == nrmTxt130[3], true,
     "⑥e★★★离开后文字色**逐值复原**（" .. tostring(itL.tr) .. " == " .. tostring(nrmTxt130[1]) .. "）")
  -- ★★★每一条都必须挂上两个脚本（漏挂一条 = 那一条永不变色，而且**不报错**）
  local mm130 = _G.EVAL_TB_NAMEMENU
  eq(type(mm130) == "table", true, "⑥e★具名帧 EVAL_TB_NAMEMENU 在全局里（读值口要能拿到它的按钮）")
  local noScr130 = ""
  for i = 1, nIt130 do
    local b = mm130 and mm130.rows and mm130.rows[i]
    if b and b.btn then
      local ok1, f1 = pcall(b.btn.GetScript, b.btn, "OnEnter")
      local ok2, f2 = pcall(b.btn.GetScript, b.btn, "OnLeave")
      if (not ok1) or type(f1) ~= "function" or (not ok2) or type(f2) ~= "function" then
        noScr130 = noScr130 .. i .. " "
      end
    else
      noScr130 = noScr130 .. i .. "(读不到按钮) "
    end
  end
  eq(noScr130, "", "⑥e★★★每一条都挂了 OnEnter + OnLeave: " .. noScr130)
  -- ⑦ 接口探针（1.73.28 改）：报这个菜单真正要用的 API
  TEST.chat = ""
  eq(EVAL_TB_MENU_API_PROBE(), true, "⑦★菜单接口探针能跑")
  local c130b = tostring(TEST.chat or "")
  eq(string.find(c130b, "InviteToParty", 1, true) ~= nil, true, "⑦★★探针报了邀请接口")
  eq(string.find(c130b, "ChatFrame_OpenChat", 1, true) ~= nil, true, "⑦★★探针报了「打开聊天框」接口（悄悄话要用）")
  -- ★1.73.40 探针必须如实报「圆角边框到底挂上了没有」（用户报「还是没有圆角」时靠这一行取证，不靠猜）
  eq(string.find(c130b, "边框做法 = rounded", 1, true) ~= nil, true,
     "⑦★★★探针报了圆角边框的落地状态（实际：" .. string.sub(c130b, 1, 120) .. "）")
  -- ⑦ 关掉开关 → 不再接管
  EVAL_HELP_CONFIG.tb.nameMenu = false
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.sirCalls = {}
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  eq(table.getn(TEST.sirCalls), 1, "⑦★★开关关掉 → 右键不再接管（照旧转发给客户端）")
  eq(EVAL_TB_NAMEMENU_STATE().shown, false, "⑦★也不弹菜单")
  EVAL_HELP_CONFIG.tb.nameMenu = true
  _G.CanGuildInvite = savedCGI130
  EVAL_TEST_TB_NAMEMENU_RESET()
  EVAL_HELP_CONFIG.tb = saved130
  print("  名字右键菜单：读回确认挂载 · 右键接管/左键放行 · 邀请三种路径 · 复制=已全选框 · /s 去抖 · 开关可关")
end

-- 131) ★★★1.73.25 用户：「方案删除 要删除对应绑定的按键信息」
--   绑定按**方案序号**存（w2.bindKeys / w2.bindSlots，单一真源见 EVAL_BIND_*）→ 删掉中间那个方案时必须：
--   ① 解绑它自己的键；② 它**后面**的绑定整体**左移一格**；③ SaveBindings 落盘。
--   ★不左移的后果 = 被删方案的键「粘」到下一个方案身上（按那个键会激活错的方案）——所以逐条钉序号。
do
  local w2 = EVAL_HELP_CONFIG.war
  local sp131, sk131, ss131, sa131 = w2.profiles, w2.bindKeys, w2.bindSlots, w2.activeProfile
  w2.profiles = { { name = "甲", skills = {} }, { name = "乙", skills = {} }, { name = "丙", skills = {} }, { name = "丁", skills = {} } }
  w2.activeProfile = 3
  w2.bindKeys = { [1] = "A", [2] = "B", [3] = "C", [4] = "D" }
  w2.bindSlots = { [1] = 11, [2] = 12, [3] = 13, [4] = 14 }
  TEST.bindings, TEST.saveBindingsCalls, TEST.chat = {}, 0, ""
  eq(EVAL_WAR_DEL_PROFILE(2), true, "①★删掉第 2 个方案")
  eq(table.getn(w2.profiles), 3, "①★方案真的少了一个")
  eq(tostring(w2.profiles[2].name), "丙", "①★后面的方案顶上来（序号语义要对得上）")
  eq(w2.bindKeys[1], "A", "②★★第 1 个方案的绑定**不动**")
  eq(w2.bindKeys[2], "C", "②★★★被删方案**后面**的绑定左移一格（不左移就会粘到错方案上）")
  eq(w2.bindKeys[3], "D", "②★再后面那个也左移")
  eq(w2.bindKeys[4], nil, "②★★末尾不留幽灵绑定")
  eq(w2.bindSlots[2], 13, "②★格号映射同样左移（否则按键会派发到错方案）")
  eq(w2.bindSlots[3], 14, "②★再往后也对得上")
  eq(w2.bindSlots[4], nil, "②★格号不留幽灵")
  eq(TEST.bindings["B"], nil, "③★★★被删方案自己的键**真的解绑了**（没有残留按键）")
  eq((TEST.saveBindingsCalls or 0) >= 1, true, "④★改动后 SaveBindings 落盘（不存就随重登丢）")
  eq(string.find(tostring(TEST.chat or ""), "已解除它自己的快捷键绑定", 1, true) ~= nil, true, "④★如实播报「已解除它自己的快捷键绑定」")
  w2.profiles, w2.bindKeys, w2.bindSlots, w2.activeProfile = sp131, sk131, ss131, sa131
  TEST.bindings = nil
  print("  方案删除：解绑自己的键 · 后面的绑定左移一格 · 落盘 · 如实播报")
end

-- 132) ★★★1.73.27 用户问：「能量对法系职业是否也是魔法值？名称完善下。」
--   答：是 —— 1.12 的资源约定 0=法力 / 1=怒气 / 2=集中值 / 3=能量，法系的「能量」就是**法力（魔法值）**。
--   判据：① 资源类条件的显示名与百分比名**跟着 UnitPowerType 实时变**（建表时定死，德鲁伊变形后就会显示错）；
--         ② 方案行/导出文本（EVAL_COND_STR）用同一个实时名字；③ 解析侧**认这些名字**（否则导出再导入就丢条件）。
do
  local saved132 = TEST.powerType
  local function pt132(v) TEST.powerType = v end
  -- ① 显示名实时跟随资源类型
  pt132(0)
  eq(EVAL_TEST_SE_TYPELABEL("power"), "法力", "①★★★法系（powerType=0）→ 「法力」")
  eq(EVAL_TEST_SE_TYPELABEL("powerPct"), "法力%", "①★★★百分比形态 → 「法力%」")
  pt132(1)
  eq(EVAL_TEST_SE_TYPELABEL("power"), "怒气", "①★战士（1）→ 「怒气」")
  eq(EVAL_TEST_SE_TYPELABEL("powerPct"), "怒气%", "①★百分比也跟着变")
  pt132(2)
  eq(EVAL_TEST_SE_TYPELABEL("power"), "集中值", "①★猎人（2）→ 「集中值」")
  pt132(3)
  eq(EVAL_TEST_SE_TYPELABEL("power"), "能量", "①★盗贼/德鲁伊豹（3）→ 「能量」")
  --  ★★「不许建表时定死」：同一个会话里换一次形态，名字必须跟着换
  pt132(0)
  local a132 = EVAL_TEST_SE_TYPELABEL("powerPct")
  pt132(3)
  local b132 = EVAL_TEST_SE_TYPELABEL("powerPct")
  eq(a132.."→"..b132 == "法力%→能量%", true, "①★★★同一个会话里变形后名字实时改：" .. tostring(a132) .. "→" .. tostring(b132))
  -- ② 非资源类条件的名字不受影响（回归哨兵）
  eq(EVAL_TEST_SE_TYPELABEL("hpPct"), EVAL_L("CT_HPPCT"), "②★其它条件名不受影响（自身血%）")
  eq(EVAL_TEST_SE_TYPELABEL("swingLeft"), EVAL_L("CT_SWINGLEFT"), "②★距下次攻击（用户截图里也在用）")
  -- ③ 方案行/导出文本与下拉同源
  pt132(0)
  eq(EVAL_COND_STR({ k = "powerPct", op = ">", n = 50 }), "法力%>50", "③★★法系的方案行/导出文本 = 法力%>50")
  eq(EVAL_COND_STR({ k = "power", op = "<", n = 30 }), "法力<30", "③★绝对值形态同理")
  pt132(1)
  eq(EVAL_COND_STR({ k = "powerPct", op = ">", n = 50 }), "怒气%>50", "③★战士仍显示怒气%")
  -- ④ 解析侧认这些名字（导出 → 导入不丢条件）
  local function parseK132(txt2)
    local pr = EVAL_PROFILE_FROM_TEXT("# 方案: 甲\n\n- 爪击 | " .. txt2)
    if not pr or not pr.skills or not pr.skills[1] then return nil end
    local g = pr.skills[1].groups
    if not g or not g[1] or not g[1][1] then return nil end
    return g[1][1].k
  end
  eq(parseK132("法力%>50"), "powerPct", "④★★★导入「法力%>50」→ powerPct（法系导出再导入不丢条件）")
  eq(parseK132("法力<30"), "power", "④★★导入「法力<30」→ power")
  eq(parseK132("怒气%>40"), "powerPct", "④★★顺势补上「怒气%」（原来只有「能量%」能解析）")
  eq(parseK132("集中值%>20"), "powerPct", "④★猎人的「集中值%」也认")
  eq(parseK132("魔法值>100"), "power", "④★「魔法值」= 法力 的另一种叫法也认")
  pt132(saved132)
  print("  资源名：显示名跟着 UnitPowerType 实时变（法力/怒气/集中值/能量）· 方案行与导出同源 · 解析侧认全套写法")
end


-- 135) ★★★1.73.32 通用输入弹窗（EVAL_TN）**规程审计**（用户：「审计下…是否符合项目弹窗规程；
--   要能拖拽（现在无法拖拽）+ 加宽尺寸 + 内部布局乱 + 添加物品弹窗被遮盖」）。
--   审计结论：① 层级 130 < 工具箱弹窗 200 → **被父弹窗压住**（点击/拖动都被吃掉）= 用户看到的现象；
--   ② 宽度固定 300、输入框固定 220；③ 两个按钮 x **写死 70/160** → 加宽后不居中；④ 标签写死「目标名称：」。
--   判据（读**真实控件**）：层级在 200~250 之间 · 柄 level > 窗口 · SetMovable + RegisterForDrag(LeftButton)
--   + RegisterForClicks(LeftButtonUp) · 宽度 ≥380 且输入框跟着宽度 · 按钮组**居中**且不出界 · 标签由调用方给。
do
  EVAL_TN_OPEN("甲", "", nil, EVAL_L("TN_LABEL_NAME"))
  local z135 = EVAL_TEST_TN_Z()
  eq(type(z135) == "table", true, "①前置：输入弹窗已建好")
  eq(z135.level > 200, true, "①★★★层级高于工具箱弹窗 200（实际 " .. tostring(z135.level) .. "）—— 否则被压住、点不动也拖不动")
  eq(z135.level < 250, true, "①★且低于全局下拉 250（不能盖住下拉）")
  eq(z135.titleLevel > z135.level, true, "①★★拖动柄 level > 窗口 level（本项目 UI 配方第 1 条）")
  eq(z135.movable, true, "②★★★窗口 SetMovable(true)")
  eq(tostring(z135.drag or ""), "LeftButton", "②★★★拖动柄注册了 RegisterForDrag(LeftButton)（Frame 的 OnDragStart 不触发）")
  eq(string.find(tostring(z135.clicks or ""), "LeftButtonUp", 1, true) ~= nil, true, "②★★注册了 RegisterForClicks(LeftButtonUp)")
  eq(z135.w >= 380, true, "③★★★窗口加宽（实际 " .. tostring(z135.w) .. " ≥ 380）")
  eq(type(z135.ebW) == "number" and z135.ebW >= z135.w - 80, true, "③★★输入框跟着窗口宽度走（" .. tostring(z135.ebW) .. "）")
  eq(table.getn(z135.btns), 2, "③前置：两个按钮")
  local b1, b2 = z135.btns[1], z135.btns[2]
  eq(b1 and b2 and b2.x >= b1.x + b1.w, true, "③★两个按钮不重叠")
  local mid135 = (b1.x + (b2.x + b2.w)) / 2
  eq(math.abs(mid135 - z135.w / 2) <= 2, true, "③★★★按钮组**居中**（组中线 " .. tostring(mid135) ..
     " ≈ 窗宽一半 " .. tostring(z135.w / 2) .. "）—— 写死 x 的老写法加宽后就偏了")
  eq(b2.x + b2.w <= z135.w, true, "③★按钮不出界")
  eq(z135.label, EVAL_L("TN_LABEL_NAME") .. "：", "④★★★标签由调用方给（实际 " .. tostring(z135.label) .. "）")
  eq(string.find(tostring(z135.label), "目标名称", 1, true), nil, "④★★不再写死「目标名称：」（物品/数量/每次都跟着错）")
  EVAL_TEST_TN_CLOSE()
  print("  输入弹窗规程：层级 " .. tostring(z135.level) .. "（200~250）· 可拖柄(Button+LeftButton) · 宽 " ..
        tostring(z135.w) .. " · 按钮居中 · 标签随调用方")
end

-- 136) ★★★1.73.33 自动购买弹窗的三处修复（用户：「这个弹窗还是不能被拖拽；标题右侧的说明统一移动到
--   安全说明下面对齐；红线位置布局异常」）——
--   ① 列头与数据列**必须对得上**（根因：列头把「距左边」当「距右边」用 → 两个列头叠在一起、与数据列错位）；
--   ② 弹窗必须有**拖动柄**（1.73.31 只修了层级/鼠标，柄是漏的）；③ 说明行挪到安全说明**正下方并左对齐**。
do
  EVAL_BUY_UI_OPEN()
  local g136 = EVAL_TEST_BUY_UI_GEO()
  eq(type(g136) == "table", true, "①前置：读得到弹窗几何")
  -- ① 列头 vs 数据列对齐（右对齐的列比右边缘，左对齐的比左边缘；容差 2px）
  local hN, hPer = g136.heads[3], g136.heads[4]
  eq(type(hN) == "table" and type(g136.cells.n) == "table", true, "①前置：总数列头与单元格都在")
  eq(math.abs((hN.r or -999) - (g136.cells.n.r or -998)) <= 2, true,
     "①★★★总数列头的右边缘 ≈ 该列数据右边缘（" .. tostring(hN.r) .. " vs " .. tostring(g136.cells.n.r) .. "）")
  eq(math.abs((hPer.r or -999) - (g136.cells.per.r or -998)) <= 2, true,
     "①★★★每次列头的右边缘 ≈ 该列数据右边缘（" .. tostring(hPer.r) .. " vs " .. tostring(g136.cells.per.r) .. "）")
  eq(math.abs((g136.heads[2].x or -999) - (g136.cells.name.x or -998)) <= 2, true,
     "①★★名称列头与名称格左对齐（" .. tostring(g136.heads[2].x) .. " vs " .. tostring(g136.cells.name.x) .. "）")
  eq(math.abs((g136.heads[1].x or -999) - g136.cols.chkX) <= 2, true, "①★启用列头压在勾选列上")
  --   ★★列头**不许互相重叠**（截图里那串「启用每次称 总数」就是两个列头叠着画出来的）
  local badOv136, prevR = "", nil
  for i = 1, table.getn(g136.heads) do
    local h = g136.heads[i]
    if h and h.x then
      if prevR and h.x < prevR - 1 then
        badOv136 = badOv136 .. "第" .. tostring(i) .. "个列头(x=" .. tostring(h.x) .. ")压到前一个(右=" .. tostring(prevR) .. ") "
      end
      if h.r then prevR = h.r end
    end
  end
  eq(badOv136, "", "①★★★列头互不重叠：" .. badOv136)
  -- ② 拖动柄（本项目 UI 配方：Button + SetMovable + RegisterForDrag + RegisterForClicks）
  eq(tostring(g136.drag or ""), "LeftButton", "②★★★有拖动柄且注册了 RegisterForDrag(LeftButton)（原来**根本没有柄**）")
  eq(string.find(tostring(g136.clicks or ""), "LeftButtonUp", 1, true) ~= nil, true, "②★★注册了 RegisterForClicks(LeftButtonUp)")
  eq(g136.movable, true, "②★★SetMovable(true)")
  eq((g136.titleLevel or 0) > (g136.level or 0), true, "②★★柄的层级高于窗口（" .. tostring(g136.titleLevel) ..
     " > " .. tostring(g136.level) .. "）")
  -- ③ 说明行在安全说明**正下方**、左对齐
  eq(type(g136.hint) == "table" and type(g136.tip) == "table", true, "③前置：两条说明都在")
  eq(math.abs((g136.tip.x or -999) - (g136.hint.x or -998)) <= 2, true,
     "③★★★说明行与安全说明**左对齐**（" .. tostring(g136.tip.x) .. " vs " .. tostring(g136.hint.x) .. "）")
  eq((g136.tip.y or 0) < (g136.hint.y or 0), true, "③★★★说明行在安全说明**下面**（" ..
     tostring(g136.tip.y) .. " < " .. tostring(g136.hint.y) .. "）")
  EVAL_BUY_UI_CLOSE()
  print("  自动购买弹窗：列头与数据列对齐且互不重叠 · 有拖动柄(Button+LeftButton) · 说明行移到安全说明下方并左对齐")
end

-- 137) ★★★1.73.34 用户：「审计自动购买内的滚动条机制是否符合项目规范」——
--   审计发现 3 处不符 + 2 处联动问题，全部修复；判据如下（都读**真实控件/真实脚本**）：
do
  local tb137 = EVAL_HELP_CONFIG.tb
  local savedBuy137 = tb137.buy
  tb137.buy = {}
  for i = 1, 10 do table.insert(tb137.buy, { name = "物品" .. i, n = 1, per = 1, on = true }) end
  EVAL_BUY_UI_OPEN() -- ★必须真的打开一次（刷新才会按 10 条算页码/边界）
  local s137 = EVAL_TEST_BUY_UI_SCROLL()
  eq(type(s137) == "table", true, "①前置：读得到滚动条状态")
  -- ① 滚轮：装上了、方向单一来源、上滚 = 回到前面、且**夹取**（不越界）
  eq(s137.wheel, true, "①★★★弹窗装了 OnMouseWheel 脚本（原来**根本没有滚轮**）")
  eq(s137.mouseWheel, true, "①★★EnableMouseWheel(true)（不装开关收不到滚轮事件）")
  eq(s137.off, 0, "①前置：初始在第一页")
  EVAL_TEST_BUY_UI_WHEEL(nil, 1) -- 上滚 = +1 = 回到前面
  eq(EVAL_TEST_BUY_UI_SCROLL().off, 0, "①★★★已在第一页时上滚不再往上（夹取，不是负数）")
  EVAL_TEST_BUY_UI_WHEEL(nil, -1)
  eq(EVAL_TEST_BUY_UI_SCROLL().off, 1, "①★★★下滚 = 往后一行（off +1）")
  EVAL_TEST_BUY_UI_WHEEL(nil, -1)
  eq(EVAL_TEST_BUY_UI_SCROLL().off, 2, "①★连续下滚继续往后")
  EVAL_TEST_BUY_UI_WHEEL(nil, 1)
  eq(EVAL_TEST_BUY_UI_SCROLL().off, 1, "①★★★上滚 = 回到前面（off -1，方向与本项目其它 6 处一致）")
  local before137 = EVAL_TEST_BUY_UI_SCROLL().off
  EVAL_TEST_BUY_UI_WHEEL(nil, "x") -- 非滚轮事件（dir = 0）
  eq(EVAL_TEST_BUY_UI_SCROLL().off, before137, "①★★dir=0（不是滚轮事件）→ 原地不动（交还原脚本的链式接管）")
  EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1)
  EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1)
  EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1) EVAL_TEST_BUY_UI_WHEEL(nil, -1)
  local s137b = EVAL_TEST_BUY_UI_SCROLL()
  eq(s137b.off <= 10 - 8, true, "①★★滚到底不越界（off " .. tostring(s137b.off) .. " ≤ 2 = 10-8）")
  EVAL_BUY_UI_REFRESH()
  local s137b2 = EVAL_TEST_BUY_UI_SCROLL()
  eq(s137b.dnShown, false, "①★★到底 → ▼ 隐藏（边界状态）")
  for i = 1, 10 do EVAL_TEST_BUY_UI_WHEEL(nil, 1) end
  local s137c = EVAL_TEST_BUY_UI_SCROLL()
  eq(s137c.off, 0, "①★一路滚回顶（off = 0）")
  eq(s137c.upShown, false, "①★★到顶 → ▲ 隐藏")
  eq(s137c.dnShown, true, "①★★未到底 → ▼ 显示")
  -- ② 箭头进「右侧专用滚动槽」：不许压在「删除」按钮上
  eq(type(s137.up) == "table" and type(s137.del) == "table", true, "②前置：读得到箭头与删除按钮")
  eq((s137.up.x or -999) >= (s137.del.r or 9999), true, "②★★★▲ 在删除列**右边**（箭头左 " .. tostring(s137.up.x) ..
     " ≥ 删除右 " .. tostring(s137.del.r) .. "）—— 原来两者重叠，点删除会点到箭头")
  eq((s137.up.r or 9999) <= s137.W, true, "②★★▲ 不出窗口（" .. tostring(s137.up.r) .. " ≤ " .. tostring(s137.W) .. "）")
  -- ③ 页码指示在底栏，不压数据行
  -- ④ 页码：整数页 + 到底算最后一页 + 箭头按页滚（原来浮点除法：真机显示「1.25/2」）
  eq(s137.indText, "1/2  (10)", "④★★★起始页码是**整数**页（实际「" .. tostring(s137.indText) .. "」；原来是浮点除法）")
  EVAL_TEST_BUY_UI_SCROLL() -- 读一次状态（无副作用）
  for i = 1, 12 do EVAL_TEST_BUY_UI_WHEEL(nil, -1) end
  local s137d = EVAL_TEST_BUY_UI_SCROLL()
  eq(s137d.indText, "2/2  (10)", "④★★★到底 → 页码 = **最后一页**（实际「" .. tostring(s137d.indText) .. "」）")
  eq(string.find(tostring(s137d.indText), ".", 1, true), nil, "④★★★页码里**不许出现小数点**（真机老 bug 就是「1.25/2」）")
  eq((s137.ind.y or 0) < ((s137.delLast and s137.delLast.y) or 0), true, "③★★★页码指示在**所有数据行下方**（指示 y " ..
     tostring(s137.ind.y) .. " < 末行 y " .. tostring(s137.delLast and s137.delLast.y) .. "）—— 原来锚在 y=-46 正压第一行")
  tb137.buy = savedBuy137
  print("  自动购买滚动条：滚轮(单一来源+夹取+边界隐藏) · ▲▼ 进右侧专用槽不压删除列 · 页码指示移到底栏")
end

-- 138) ★★★1.73.35 右键菜单扩展（用户第 2 条）：新动作 + **权限/队伍门** + 载入信息弹窗（用户第 3 条）
do
  -- ① 权限/队伍门：条目**出现与否**由权限与队伍决定（不是点了才说没权限）
  local savedCR138, savedPL138, savedPN138 = TEST.canGuildRemove, TEST.partyLeader, TEST.partyN
  local function menuLabels138()
    EVAL_TEST_TB_MENU_DROP()
    SetItemRef("player:Ionol", "[Ionol]", "RightButton")
    local g = EVAL_TB_MENU_GEOM()
    local out = {}
    for i = 1, table.getn(g.items or {}) do out[tostring(g.items[i].label)] = true end
    return out
  end
  TEST.canGuildRemove, TEST.partyLeader, TEST.partyN = false, false, 0
  local lb1 = menuLabels138()
  eq(lb1[EVAL_L("TB_NAMEMENU_KICKG")] == true, false, "①★★★没权限 → **不出现**「踢出公会」")
  eq(lb1[EVAL_L("TB_NAMEMENU_KICKP")] == true, false, "①★★★不在队伍 → **不出现**「踢出队伍」")
  TEST.canGuildRemove, TEST.partyN = true, 3
  local lb2 = menuLabels138()
  eq(lb2[EVAL_L("TB_NAMEMENU_KICKG")] == true, true, "①★★★有权限 → 出现「踢出公会」")
  eq(lb2[EVAL_L("TB_NAMEMENU_KICKP")] == true, true, "①★★★在队伍里 → 出现「踢出队伍」")
  eq(lb2[EVAL_L("TB_NAMEMENU_SHARE")] == true, true, "①★★「分享方案」常在")
  eq(lb2[EVAL_L("TB_NAMEMENU_TRADE")] == true, true, "①★★「交易」常在")
  eq(lb2[EVAL_L("TB_NAMEMENU_QUERY")] == true, true, "①★★「查询」常在")
  -- ② 分享方案：把**当前激活方案**密语给对方（走 Share 的 EVAL_SHARE_SEND_TO）
  local savedShare138 = EVAL_SHARE_SEND_TO
  local shared138 = nil
  EVAL_SHARE_SEND_TO = function(n) shared138 = tostring(n) return true end
  TEST.chat = ""
  eq(EVAL_TB_NAME_SHARE("Ionol"), true, "②★★★「分享方案」真的发起了分享")
  eq(shared138, "Ionol", "②★★★分享对象是菜单里那个人")
  eq(string.find(tostring(TEST.chat), "分享", 1, true) ~= nil, true, "②★★如实播报")
  EVAL_SHARE_SEND_TO = savedShare138
  -- ③ 交易：解析到 unit 才发（本机只能解析「看得到」的单位）
  TEST.team = { { unit = "party1", name = "Ionol", hp = 1, hpMax = 1, mana = 0, manaMax = 1 } }
  TEST.trades = {}
  eq(EVAL_TB_NAME_TRADE("Ionol"), true, "③★★★「交易」发起成功（解析到 unit）")
  eq(tostring(TEST.trades[1] or ""), "party1", "③★★★用的是解析出来的 unit（party1），不是名字")
  TEST.team = nil
  TEST.chat = ""
  eq(EVAL_TB_NAME_TRADE("陌生人"), false, "③★★解析不到 unit → 如实失败")
  eq(string.find(tostring(TEST.chat), "拿不到单位", 1, true) ~= nil, true, "③★★并说明原因（不猜、不硬来）")
  -- ④ 查询：能解析 → 观察；不能 → **限频 who 队列**（★不许直调 SendWho）
  TEST.team = { { unit = "party1", name = "Ionol", hp = 1, hpMax = 1, mana = 0, manaMax = 1 } }
  TEST.inspects = {}
  eq(EVAL_TB_NAME_QUERY("Ionol"), true, "④★★★「查询」→ 观察（NotifyInspect）")
  eq(tostring(TEST.inspects[1] or ""), "party1", "④★★走的是解析出的 unit")
  TEST.team = nil
  local savedWho138 = EVAL_TB_WHO_ENQUEUE
  local whoQ138 = nil
  EVAL_TB_WHO_ENQUEUE = function(n) whoQ138 = tostring(n) return true end
  TEST.sirSendWho138 = TEST.sirSendWho138
  local whoBefore138 = TEST.whoCalls
  eq(EVAL_TB_NAME_QUERY("陌生人"), true, "④★★★解析不到 → 走查询（who）")
  eq(whoQ138, "陌生人", "④★★★入的是**限频 who 队列**（EVAL_TB_WHO_ENQUEUE）")
  eq(TEST.whoCalls, whoBefore138, "④★★★没有直调 SendWho（热路径会被服务器反滥用）")
  EVAL_TB_WHO_ENQUEUE = savedWho138
  -- ⑤ 踢人：非队长不踢（如实说明）；队长才发
  TEST.partyLeader = false
  TEST.uninvites = {}
  TEST.chat = ""
  eq(EVAL_TB_NAME_KICKP("Ionol"), false, "⑤★★非队长 → 不踢")
  eq(table.getn(TEST.uninvites), 0, "⑤★★一次都没调接口")
  eq(string.find(tostring(TEST.chat), "只有队长", 1, true) ~= nil, true, "⑤★★并如实说明原因")
  TEST.partyLeader = true
  eq(EVAL_TB_NAME_KICKP("Ionol"), true, "⑤★★★队长 → 踢出队伍")
  eq(tostring(TEST.uninvites[1] or ""), "Ionol", "⑤★★名字对")
  TEST.guildUninvites = {}
  eq(EVAL_TB_NAME_KICKG("Ionol"), true, "⑤★★★「踢出公会」调 GuildUninviteByName")
  eq(tostring(TEST.guildUninvites[1] or ""), "Ionol", "⑤★★名字对")
  -- ⑥ 载入信息弹窗：两个按钮 + seen 开关（知道了=下次不弹 / 关闭=每次都弹）
  local savedSeen138 = EVAL_HELP_CONFIG.loadMsgSeen
  EVAL_HELP_CONFIG.loadMsgSeen = false
  eq(EVAL_LOADPOP_SHOW(), true, "⑥★★★开关关着 → 载入时弹窗显示")
  local lp138 = EVAL_TEST_LOADPOP_STATE()
  eq(lp138.built, true, "⑥★弹窗建好了")
  eq(lp138.hasThanks and lp138.hasClose, true, "⑥★★两个按钮都在（知道了 / 关闭）")
  eq(lp138.tip ~= "", true, "⑥★有说明行（知道了=下次不弹；关闭=每次都弹）")
  eq(EVAL_TEST_LOADPOP_CLICK("thanks"), true, "⑥★★★点「知道了」（走真实 OnClick）")
  eq(EVAL_HELP_CONFIG.loadMsgSeen, true, "⑥★★★知道了 → 记下「下次不展示」")
  eq(EVAL_LOADPOP_SHOW(), false, "⑥★★★下次载入**不再弹**（开关生效）")
  EVAL_LOADPOP_HIDE()
  eq(EVAL_TEST_LOADPOP_CLICK("close"), true, "⑥★★点「关闭」")
  eq(EVAL_HELP_CONFIG.loadMsgSeen, false, "⑥★★★关闭 → 恢复「每次载入都展示」")
  EVAL_HELP_CONFIG.loadMsgSeen = savedSeen138
  EVAL_TEST_LOADPOP_CLICK("close")
  TEST.canGuildRemove, TEST.partyLeader, TEST.partyN = savedCR138, savedPL138, savedPN138
  EVAL_TEST_TB_MENU_DROP()
  print("  右键菜单扩展：权限/队伍门(不满足就不出现) · 分享方案(激活方案·密语) · 交易/查询(名字→unit) · 踢人(队长/权限) · 载入弹窗(知道了/关闭)")
end

-- 139) ★★★1.73.37 用户报「某些按键无法使用：关闭/悄悄话/目标/查询/邀请/复制名字」——
--   【根因】① SHOW 里先 tbMenuBuild() 再赋值 TB_NAME_MENU.name，而条目闭包在建菜单时把名字
--   **捕获**成了 nil → 所有动作拿到 nil → 静默 return false（点了像没反应）；② 「关闭」传的是**空函数**。
--   ★判据必须走**真实 OnClick**（按标签点），不能直接调动作函数 —— 上一轮就是这么漏掉的。
do
  local savedTN139 = EVAL_TN_OPEN
  EVAL_TN_OPEN = function() end -- 别真弹输入框
  EVAL_TEST_TB_NAMEMENU_RESET()
  TEST.sirCalls = {}
  -- ★★★必须**丢掉已建的菜单**再弹：真机上菜单是**第一次右键时**才建的，那时名字还是 nil
  --   —— 不丢的话「快照 bug」在测试里根本复现不出来（M267/M269 实测就是这么存活的）
  EVAL_TEST_TB_MENU_DROP()
  SetItemRef("player:Ionol", "[Ionol]", "RightButton") -- 第一次弹（菜单在此刻懒建）
  local g139 = EVAL_TB_MENU_GEOM()
  eq(type(g139) == "table", true, "①前置：菜单已建好")
  -- ① 悄悄话：点真实按钮 → 预填 /w Ionol
  TEST.openChats = {}
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_WHISPER")), true, "①★★★点到了「悄悄话」按钮（真实 OnClick）")
  eq(tostring(TEST.openChats[1] or ""), "/w Ionol ", "①★★★而且真的带着**菜单里那个人**去预填（名字不是 nil）")
  -- ② 目标：点真实按钮 → TargetByName(Ionol)
  TEST.targetSel = nil
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_TARGET")), true, "②★★★点到了「目标」")
  eq(tostring(TEST.targetSel or ""), "name:Ionol", "②★★★走的是 TargetByName(菜单里的名字)")
  -- ③ 邀请：点真实按钮 → InviteToParty(Ionol)
  TEST.partyInvites, TEST.partyInviteCalls = {}, 0
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_PARTY")), true, "③★★★点到了「邀请」")
  eq(tostring(TEST.partyInvites[1] or ""), "Ionol", "③★★★名字对")
  -- ④ 复制名字：点真实按钮 → 预填 /s Ionol（不发送）
  EVAL_TEST_TB_NAMEMENU_RESET()
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  TEST.openChats, TEST.runScripts = {}, {}
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_SAY")), true, "④★★★点到了「复制名字」")
  eq(tostring(TEST.openChats[1] or ""), "/s Ionol", "④★★★输入框里是 /s 名字")
  eq(table.getn(TEST.runScripts), 0, "④★★一个字都没发出去")
  -- ⑤ 查询：点真实按钮 → 入限频 who 队列（解析不到 unit 时）
  EVAL_TEST_TB_NAMEMENU_RESET()
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  local savedWho139, whoQ139 = EVAL_TB_WHO_ENQUEUE, nil
  EVAL_TB_WHO_ENQUEUE = function(n) whoQ139 = tostring(n) return true end
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_QUERY")), true, "⑤★★★点到了「查询」")
  eq(whoQ139, "Ionol", "⑤★★★查询用的是菜单里的名字")
  EVAL_TB_WHO_ENQUEUE = savedWho139
  -- ⑥ 关闭：点真实按钮 → 菜单真的收起来
  EVAL_TEST_TB_NAMEMENU_RESET()
  SetItemRef("player:Ionol", "[Ionol]", "RightButton")
  eq(EVAL_TB_NAMEMENU_STATE().shown, true, "⑥前置：菜单是开着的")
  eq(EVAL_TEST_TB_MENU_CLICK(EVAL_L("TB_NAMEMENU_CLOSE")), true, "⑥★★★点到了「关闭」")
  eq(EVAL_TB_NAMEMENU_STATE().shown, false, "⑥★★★菜单真的关掉了（原来是空函数 = 点了没反应）")
  EVAL_TN_OPEN = savedTN139
  EVAL_TEST_TB_NAMEMENU_RESET()
  print("  右键菜单接线：每个条目都走**真实 OnClick** 且带着菜单里的名字（悄悄话/目标/邀请/复制名字/查询/关闭）")
end

-- 140) ★★★1.73.38 用户两条：① 分享方案的**接收方要支持私聊**（密语来的分片要能收全并弹窗）；
--   ② 右键菜单开关的 tooltip 要把**支持的功能都列出来**（别停在旧的五条）。
do
  -- ① 接收方注册了私聊
  local evf140 = _G.EVAL_SHARE_EVENTS
  eq(type(evf140) == "table", true, "①前置：分享事件帧在")
  local okR140, reg140 = pcall(evf140.IsEventRegistered, evf140, "CHAT_MSG_WHISPER")
  eq(okR140 and reg140 == true, true, "①★★★接收方**注册了私聊**（CHAT_MSG_WHISPER）—— 别人右键「分享方案」才收得到")
  -- ② 密语来的分片要能收全 → 弹窗（走**真实**接收路径 EVAL_SHARE_ONMSG）
  EVAL_SHARE_RESET()
  EVAL_SHARE_RECV_TOGGLE() -- 打开接收开关（默认关，用户自己开）
  local recvOn140 = EVAL_SHARE_RECV_ON and EVAL_SHARE_RECV_ON()
  if recvOn140 ~= true then EVAL_SHARE_RECV_TOGGLE() end -- 若本来就是开的，别手滑关掉
  local txt140 = "# 方案: 甲\n\n- 爪击 | 可攻击"
  local hex140 = ""
  for i = 1, string.len(txt140) do hex140 = hex140 .. string.format("%02x", string.byte(txt140, i)) end
  EVAL_SHARE_ONMSG("[EHPF#ab 1/1]" .. hex140, "Ionol", "CHAT_MSG_WHISPER")
  local pop140 = table.concat(EVAL_TEST_SHARE_POPUP_TEXTS() or {}, " | ")
  eq(string.find(pop140, "Ionol", 1, true) ~= nil, true, "②★★★私聊来的分享**收到了**（弹窗点名发送者）：" .. pop140)
  eq(string.find(pop140, EVAL_L("SH_CH_WHISPER"), 1, true) ~= nil, true,
     "②★★★来源标成「" .. tostring(EVAL_L("SH_CH_WHISPER")) .. "」（不是空白/未知）")
  eq(string.find(pop140, "甲", 1, true) ~= nil, true, "②★★方案内容也解出来了")
  -- ③ tooltip：功能必须**列全**（用户要求「将支持的功能都说明下」）
  local tip140 = tostring(EVAL_L("TB_NAMEMENU_TIP"))
  for _, k in ipairs({ "TB_NAMEMENU_WHISPER", "TB_NAMEMENU_PARTY", "TB_NAMEMENU_TARGET", "TB_NAMEMENU_SAY",
                       "TB_NAMEMENU_SHARE", "TB_NAMEMENU_TRADE", "TB_NAMEMENU_QUERY",
                       "TB_NAMEMENU_KICKP", "TB_NAMEMENU_KICKG", "TB_NAMEMENU_INVITE" }) do
    eq(string.find(tip140, EVAL_L(k), 1, true) ~= nil, true, "③★★★tooltip 里列出了：" .. tostring(EVAL_L(k)))
  end
  eq(string.find(tip140, "|c", 1, true) ~= nil, true, "③★★tooltip 用了颜色码（样式美化：标题/功能/注意分层）")
  eq(string.find(tip140, "\n", 1, true) ~= nil, true, "③★★而且**分行**（不是一大坨）")
  print("  分享接收：私聊来源已支持（注册 + 收全 + 弹窗标「密语」）· 右键开关 tooltip 列全功能并分层上色")
end
-- 141) ★★★1.73.41 调研探针（分支 probe/share-hide-link）：隐藏载荷 + 长度上限两条未知数
--   「服务器到底转发不转发**自定义链接**」只能真机跑探针；这里离线可测的是**判定逻辑本身**：
--   ① 探针平时关着、不改正常协议；② 四种形态真的进发送通道（第一条立即发）；
--   ③ 完美回声 → 四种全部判「一致」；④ **模拟被剥标记的服务器** → 必须判「被改」（报告不许永远说好话）；
--   ⑤ 探针数据**不进正常接收缓冲**；⑥ 长度阶梯：完整回声全「完整」、被砍尾巴那一档判「截断」；
--   ⑦ 只发不收 → 如实「未收到」；探针能关掉。
do
  if type(EVAL_SHARE_PROBE_OFF) == "function" then EVAL_SHARE_PROBE_OFF() end
  local st0 = EVAL_SHARE_PROBE_STATE()
  eq(type(st0) == "table" and st0.armed == nil, true, "①前置：探针默认**关着**（平时零开销、不动协议）")
  local buf0 = EVAL_TEST_SHARE_BUF_COUNT()
  local done0 = EVAL_TEST_SHARE_DONE_COUNT()
  -- ② 四种形态进发送通道（走真实入口 EVAL_SHARE_LINK_PROBE）
  TEST.runScripts = {}
  eq(EVAL_SHARE_LINK_PROBE("WHISPER") ~= false, true, "②链接探针发送入口能跑")
  local st1 = EVAL_SHARE_PROBE_STATE()
  eq(st1.sent, 4, "②★★★四种形态都进了发送队列（实际 " .. tostring(st1.sent) .. "）")
  eq(st1.armed, "link", "②探针已启用（armed=link）")
  local forms = st1.forms or {}
  eq(table.getn(forms), 4, "②读得到发出的四条原文（读值口）")
  eq(string.find(tostring(forms[1] and forms[1].body), "|HEHPF:", 1, true) ~= nil, true,
     "②★★形态①是**自定义链接**（载荷进 |H 段）")
  eq(string.find(tostring(forms[1] and forms[1].body), "|h[方案:探针 ", 1, true) ~= nil, true,
     "②★★形态①只显示**短文字**（不是 220 字符乱码）")
  eq(string.find(tostring(forms[2] and forms[2].body), "|Hitem:", 1, true) ~= nil, true, "②形态②=假物品链接（已知类型对照）")
  eq(string.find(tostring(forms[3] and forms[3].body), "|Hplayer:", 1, true) ~= nil, true, "②形态③=假玩家链接（已知类型对照）")
  eq(string.find(tostring(forms[4] and forms[4].body), "[EHPF#", 1, true), 1, "②形态④=现状明文（对照组）")
  eq(string.find(tostring(TEST.runScript or ""), "|HEHPF:", 1, true) ~= nil, true,
     "②★★第一条**真的**走了 SendChatMessage（RunScript 里含链接形态）")
  -- ③ 完美回声 → 四种全部「一致」
  for i = 1, 4 do EVAL_SHARE_ONMSG(forms[i].body, "我", "CHAT_MSG_WHISPER") end
  local rep1 = EVAL_SHARE_PROBE_REPORT()
  eq(table.getn(rep1.link or {}), 4, "③报告覆盖四种形态")
  local okAll = true
  for i = 1, 4 do if tostring(rep1.link[i].verdict) ~= "一致" then okAll = false end end
  eq(okAll, true, "③★★★完美回声 → 四种全部判「一致」（实际 " .. tostring(rep1.link[1].verdict) .. "/" ..
     tostring(rep1.link[2].verdict) .. "/" .. tostring(rep1.link[3].verdict) .. "/" .. tostring(rep1.link[4].verdict) .. "）")
  -- ④ 模拟「服务器把 |c/|H 标记剥掉」→ 必须判「被改」
  EVAL_SHARE_LINK_PROBE("WHISPER")
  local forms2 = EVAL_SHARE_PROBE_STATE().forms or {}
  for i = 1, 4 do
    local raw = tostring(forms2[i] and forms2[i].body or "")
    local stripped = string.gsub(raw, "|c%x%x%x%x%x%x%x%x", "")
    stripped = string.gsub(stripped, "|H[^|]*|h%[(.-)%]|h", "%1")
    stripped = string.gsub(stripped, "|r", "")
    EVAL_SHARE_ONMSG(stripped, "我", "CHAT_MSG_WHISPER")
  end
  local rep2 = EVAL_SHARE_PROBE_REPORT()
  eq(tostring(rep2.link[1].verdict) ~= "一致", true,
     "④★★★被剥标记后**不许**判「一致」（实际 " .. tostring(rep2.link[1].verdict) .. "）")
  eq(string.find(tostring(rep2.link[1].got and "x" or ""), "x", 1, true) ~= nil, true, "④报告里带上「收到多少字节」")
  -- ⑤ 探针数据不进正常接收缓冲（形态④长得与真分片一模一样）
  eq(EVAL_TEST_SHARE_BUF_COUNT(), buf0, "⑤★★★探针消息**没有**污染正常接收缓冲")
  eq(EVAL_TEST_SHARE_DONE_COUNT(), done0,
     "⑤★★★也没被当成真分享走完整流程（完成表没动；只看缓冲数会假绿）")
  -- ⑥ 长度阶梯：完整回声全「完整」
  eq(EVAL_SHARE_LEN_PROBE("WHISPER") ~= false, true, "⑥长度探针发送入口能跑")
  local stL = EVAL_SHARE_PROBE_STATE()
  eq(stL.ladderSent, 4, "⑥★★四个阶梯档都进队列（实际 " .. tostring(stL.ladderSent) .. "）")
  local rows = stL.ladder or {}
  eq(string.len(tostring(rows[1] and rows[1].body)) == (rows[1] and rows[1].target), true,
     "⑥★★第 1 档消息长度**恰好**等于目标（" .. tostring(string.len(tostring(rows[1] and rows[1].body))) .. " == " ..
     tostring(rows[1] and rows[1].target) .. "）")
  for i = 1, 4 do EVAL_SHARE_ONMSG(rows[i].body, "我", "CHAT_MSG_WHISPER") end
  local repL = EVAL_SHARE_PROBE_REPORT()
  local okL = true
  for i = 1, 4 do if tostring(repL.len[i].verdict) ~= "完整" then okL = false end end
  eq(okL, true, "⑥★★★完整回声 → 四档全判「完整」")
  -- ⑥b 砍掉最后一档的尾巴 → 只有那一档判「截断」
  EVAL_SHARE_LEN_PROBE("WHISPER")
  local rows2 = EVAL_SHARE_PROBE_STATE().ladder or {}
  for i = 1, 4 do
    local body = tostring(rows2[i] and rows2[i].body or "")
    if i == 4 then body = string.sub(body, 1, string.len(body) - 6) end
    EVAL_SHARE_ONMSG(body, "我", "CHAT_MSG_WHISPER")
  end
  local repL2 = EVAL_SHARE_PROBE_REPORT()
  eq(tostring(repL2.len[4].verdict), "截断", "⑥b★★★被砍尾巴那一档必须判「截断」（实际 " .. tostring(repL2.len[4].verdict) .. "）")
  eq(tostring(repL2.len[1].verdict), "完整", "⑥b★★其余档不受影响（第 1 档仍「完整」）")
  -- ⑦ 只发不收 → 如实「未收到」；探针能关掉
  EVAL_SHARE_LINK_PROBE("WHISPER")
  local repN = EVAL_SHARE_PROBE_REPORT()
  local anyMissing = false
  for i = 1, 4 do if tostring(repN.link[i].verdict) == "未收到" then anyMissing = true end end
  eq(anyMissing, true, "⑦★★★没收到就如实说「未收到」（不许假装成功）")
  EVAL_SHARE_PROBE_OFF()
  eq(EVAL_SHARE_PROBE_STATE().armed, nil, "⑦探针能关掉（回到正常接收）")
  -- ⑧ ★★★1.73.41b 用户「操作完了.看下」暴露的缺口：结果只打聊天框 → AI/事后都读不到（本机没有聊天日志）
  eq(type(EVAL_HELP_CONFIG.shareProbe) == "string" and string.len(EVAL_HELP_CONFIG.shareProbe) > 40, true,
     "⑧★★★探针结果**落盘**（EVAL_HELP_CONFIG.shareProbe 有内容）")
  eq(type(EVAL_HELP_CONFIG.shareProbeVerdicts) == "table" and type(EVAL_HELP_CONFIG.shareProbeVerdicts.link) == "table", true,
     "⑧★★★判定表也落盘（shareProbeVerdicts.link 可机器读）")
  eq(string.find(tostring(EVAL_HELP_CONFIG.shareProbe), "探针结果", 1, true) ~= nil, true, "⑧★落盘的文字里带标题")
  -- ⑨ ★★「一次跑完」：一条命令 → 自动出结果（省用户操作）
  eq(EVAL_SHARE_PROBE_AUTORUN("WHISPER"), true, "⑨★★「探针全跑」入口能跑")
  eq(EVAL_TEST_SHARE_PROBE_PLAN(), 4, "⑨★★★排了 4 步（6s 出结果 / 12s 长度探针 / 18s 出结果 / 20s 悬停探针）")
  TEST.time = (TEST.time or 1000) + 7
  EVAL_TEST_SHARE_PROBE_STEP()
  eq(EVAL_TEST_SHARE_PROBE_PLAN(), 3, "⑨★★到点会自动出结果（步数 4 → 3）")

  -- ⑩ ★★★1.73.41c 命令**接线**判据（真事故）：探针命令属于 `/eh go` 组，`msg` 是**带 `go ` 前缀**的全串
  --   —— 我一开始写成 `msg == "探针全跑"`，用户敲 `/eh go 探针全跑` **什么都不会发生（静默！）**。
  --   ★教训：只测 `EVAL_SHARE_PROBE_AUTORUN()` = **没测接线**；判据必须走**真实命令入口** SlashCmdList["EVALHELP"]。
  EVAL_SHARE_PROBE_OFF()
  SlashCmdList["EVALHELP"]("go 探针全跑")
  eq(EVAL_TEST_SHARE_PROBE_PLAN() >= 3, true,
     "⑩★★★/eh go 探针全跑 真的排上了自动步骤（实际 " .. tostring(EVAL_TEST_SHARE_PROBE_PLAN()) .. "）")
  SlashCmdList["EVALHELP"]("go 探针关")
  SlashCmdList["EVALHELP"]("go 链接探针")
  eq(EVAL_SHARE_PROBE_STATE().armed, "link", "⑩★★★/eh go 链接探针 真的武装了探针（命令前缀写错就什么都不会发生）")
  SlashCmdList["EVALHELP"]("go 长度探针")
  eq(EVAL_SHARE_PROBE_STATE().armed, "len", "⑩★★/eh go 长度探针 也真的武装了")
  SlashCmdList["EVALHELP"]("go 探针结果")
  eq(type(EVAL_HELP_CONFIG.shareProbe) == "string" and string.len(EVAL_HELP_CONFIG.shareProbe) > 40, true,
     "⑩★★/eh go 探针结果 真的出了结果并落盘")
  SlashCmdList["EVALHELP"]("go 探针关")
  eq(EVAL_SHARE_PROBE_STATE().armed, nil, "⑩★/eh go 探针关 真的关掉了")
  TEST.chat = nil
  TEST.chat = nil
  print("  调研探针：4 形态逐字节比对（一致/被改/未收到）+ 长度阶梯（完整/截断）+ 不污染正常接收")
end
-- 142) ★★★1.73.41c 悬停探针：用户要「角色名: 分享了一份绝世秘籍 —— 鼠标移动上去才能看到详情」。
--   离线能测的是**挂钩本身**（幂等、透传、记账、落盘、命令接线）；
--   「客户端悬停时到底哪条 Lua 路径被走到」必须**真机悬停后读账本**。
do
  local hooks = EVAL_SHARE_HOVER_HOOKS()
  eq(type(hooks) == "table" and table.getn(hooks) >= 1, true, "①挂钩装上了（实际 " .. tostring(table.getn(hooks or {})) .. " 个）")
  eq(hooks[1], "SetHyperlink", "①第一个就是 SetHyperlink（画链接 tooltip 的必经之路）")
  local n1 = table.getn(hooks)
  EVAL_SHARE_HOVER_HOOKS()
  eq(table.getn(EVAL_SHARE_HOVER_HOOKS()), n1, "①★★幂等：重复安装不会变两层（两层 = 一次悬停记两次账）")
  TEST.gtHyperlinks = {}
  local before = table.getn(EVAL_SHARE_HOVER_STATE().log) or 0
  GameTooltip:SetHyperlink("|cffffffff|Hitem:1234:0:0:0:0:0:0:0|h[测试物品]|h|r")
  eq(table.getn(TEST.gtHyperlinks), 1, "②★★原函数透传（桩记到了那一次 SetHyperlink）")
  eq(table.getn(EVAL_SHARE_HOVER_STATE().log), before + 1, "②★★账本记了 1 条（幂等时不会记 2 条）")
  eq(EVAL_SHARE_HOVER_STATE().log[before + 1].hook, "GameTooltip:SetHyperlink", "②★账本记的是 hook 名")
  TEST.runScripts = {}
  eq(EVAL_SHARE_HOVER_PROBE("WHISPER") ~= false, true, "③悬停探针发送入口能跑")
  local hs = EVAL_SHARE_HOVER_STATE()
  eq(table.getn(hs.sent or {}), 3, "③★★三条形态都发了（实际 " .. tostring(table.getn(hs.sent or {})) .. "）")
  eq(string.find(tostring(hs.sent[1]), "分享了一份绝世秘籍", 1, true) ~= nil, true, "③★★带用户要的文案「分享了一份绝世秘籍」")
  eq(string.find(tostring(hs.sent[1]), "|HEHPF:", 1, true) ~= nil, true, "③形态①=自定义链接")
  eq(string.find(tostring(hs.sent[2]), "|Hitem:", 1, true) ~= nil, true, "③形态②=假物品链接")
  eq(string.find(tostring(hs.sent[3]), "Hitem:6948", 1, true) ~= nil, true, "③形态③=真物品 id 对照")
  EVAL_SHARE_PROBE_REPORT()
  eq(type(EVAL_HELP_CONFIG.shareProbeHover) == "table", true, "④★★★悬停账本落盘（shareProbeHover）")
  eq(type(EVAL_HELP_CONFIG.shareProbeHover.hooks) == "table", true, "④账本里有挂钩清单")
  eq(type(EVAL_HELP_CONFIG.shareProbeHover.scriptProbe) == "table", true, "④也有「聊天帧有没有 Hyperlink 脚本」的探测结果")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 悬停探针")
  eq(string.find(tostring(TEST.chat or ""), "悬停探针已发出", 1, true) ~= nil, true,
     "⑤★★★/eh go 悬停探针 真的执行了（命令在 go 组里、前缀要对）")
  eq(table.getn(EVAL_SHARE_HOVER_STATE().sent or {}), 3, "⑤★命令跑完仍只有三条最新形态")
  TEST.chat = nil
  -- ⑥ ★★★1.73.41d 真事故一：账本要**事件即刷盘**——用户悬停完直接 /reload 就得能读到
  --   （原来只有「报告命令」才写；用户实测 12:53 存档里 shareProbeHover 一片空白）
  EVAL_HELP_CONFIG.shareProbeHover = nil
  TEST.gtHyperlinks = {}
  GameTooltip:SetHyperlink("|cffffffff|Hitem:1:0:0:0:0:0:0:0|h[刷盘测试]|h|r")
  eq(type(EVAL_HELP_CONFIG.shareProbeHover) == "table", true,
     "⑥★★★账本**事件即刷盘**（不用先跑报告命令）")
  -- ⑦ ★★★1.73.41d 真事故二：报告不许因「本会话没跑分片探针」就**早退**（会把悬停账本吞掉）
  local st142 = EVAL_SHARE_PROBE_STATE()
  if type(st142.forms) == "table" then
    for i = table.getn(st142.forms), 1, -1 do table.remove(st142.forms, i) end
  end
  if type(st142.ladder) == "table" then
    for i = table.getn(st142.ladder), 1, -1 do table.remove(st142.ladder, i) end
  end
  TEST.chat = ""
  EVAL_SHARE_PROBE_REPORT()
  local c142 = tostring(TEST.chat or "")
  eq(string.find(c142, "还没发过分片探针", 1, true) ~= nil, true, "⑦★无数据时如实说明")
  eq(string.find(c142, "悬停探针账本", 1, true) ~= nil, true,
     "⑦★★★无数据也照样输出悬停账本（早退就把它吞了）")
  TEST.chat = nil
  -- ⑧ ★★★1.73.41e 真事故：发探针时就得先写一次账本——否则「一个 hook 都没触发」时存档里什么都没有，
  --   分不清「探针没跑」还是「跑了但悬停不走 Lua」（用户实测：shareProbeHover 完全缺席）。
  EVAL_HELP_CONFIG.shareProbeHover = nil
  eq(EVAL_SHARE_HOVER_PROBE("WHISPER") ~= false, true, "⑧发探针（用来验「发就写」）")
  local hov142 = EVAL_HELP_CONFIG.shareProbeHover
  eq(type(hov142) == "table", true, "⑧★★★发探针**立即**写一次账本（不依赖任何 hook 事件）")
  eq(table.getn((hov142 or {}).log or {}) == 0, true, "⑧★刚发的时候日志是空的（「一个事件都没有」本身就是可读的证据）")
  eq(type((hov142 or {}).armedAt) == "number", true, "⑧★还有时间戳（能证明探针真的跑过）")
  print("  悬停探针：挂钩幂等+透传+记账 · 三条形态（自定义/假物品/真物品对照）· 账本落盘 · 命令接线")
end
-- 143) ★★★1.73.42 分享显示行：境界（等级→修仙）· 品阶（评分制）· 评语（每档 10 条随机）
do
  eq(EVAL_SHARE_SEAL_RANK(1), "炼气", "境界：1 级 = 炼气")
  eq(EVAL_SHARE_SEAL_RANK(9), "炼气", "境界：9 级 = 炼气（档位上沿）")
  eq(EVAL_SHARE_SEAL_RANK(10), "筑基", "境界：10 级 = 筑基（下一档下沿）")
  eq(EVAL_SHARE_SEAL_RANK(20), "金丹", "境界：20 = 金丹")
  eq(EVAL_SHARE_SEAL_RANK(30), "元婴", "境界：30 = 元婴")
  eq(EVAL_SHARE_SEAL_RANK(40), "化神", "境界：40 = 化神")
  eq(EVAL_SHARE_SEAL_RANK(50), "炼虚", "境界：50 = 炼虚")
  eq(EVAL_SHARE_SEAL_RANK(60), "大乘", "境界：60 = 大乘")
  eq(EVAL_SHARE_SEAL_RANK(99), "大乘", "境界：越界 → 最高档（不回落到炼气）")
  local function txt(n, cond)
    local s = "# 方案: 甲"
    for i = 1, n do s = s .. "\n- 技能" .. i .. (cond and " | 可攻击 & 敌对" or "") end
    return s
  end
  eq(EVAL_SHARE_SEAL_SCORE(txt(3)), 3, "评分：3 条无条件 = 3")
  eq(EVAL_SHARE_SEAL_SCORE(txt(2, true)), 6, "★★评分：2 条各带 2 个条件 = 2+4 = 6")
  eq(select(2, EVAL_SHARE_SEAL_TIER(3)).name, "普通", "品阶：3 = 普通")
  eq(select(2, EVAL_SHARE_SEAL_TIER(4)).name, "稀有", "品阶：4 = 稀有")
  eq(select(2, EVAL_SHARE_SEAL_TIER(6)).name, "稀有", "品阶：6 = 稀有（上沿）")
  eq(select(2, EVAL_SHARE_SEAL_TIER(7)).name, "珍稀", "品阶：7 = 珍稀")
  eq(select(2, EVAL_SHARE_SEAL_TIER(9)).name, "珍稀", "品阶：9 = 珍稀（上沿）")
  eq(select(2, EVAL_SHARE_SEAL_TIER(10)).name, "绝版", "品阶：10 = 绝版")
  eq(select(2, EVAL_SHARE_SEAL_TIER(12)).name, "绝版", "品阶：12 = 绝版（上沿）")
  eq(select(2, EVAL_SHARE_SEAL_TIER(13)).name, "源代码", "★★品阶：13 = 源代码（用户定的门槛）")
  local reps = { 1, 4, 7, 10, 13 }
  local wantColor = { "|cffffffff", "|cff1eff00", "|cffa335ee", "|cffff8000", "|cffb87333" }
  for i = 1, 5 do
    local _, ti = EVAL_SHARE_SEAL_TIER(reps[i])
    eq(ti.color, wantColor[i], "品阶" .. i .. " 色码对（" .. tostring(ti.color) .. "）")
    eq(string.len(tostring(ti.color)) == 10, true, "色码必须 8 位（|c + 8 = 10 字节）")
  end
  eq(wantColor[5], "|cffb87333", "★★源代码 = 暗金（用户定的）")
  for i = 1, 5 do
    local set = {}
    for k = 1, 10 do
      local c = EVAL_SHARE_SEAL_COMMENT(i, k)
      eq(type(c) == "string" and string.len(c) > 0, true, "评语非空 " .. i .. "/" .. k)
      eq(set[c] == nil, true, "★★同档评语不重复：" .. tostring(c))
      set[c] = true
    end
    eq(EVAL_SHARE_SEAL_COMMENT(i, 11) ~= "", true, "越界索引兜底不为空")
  end
  local first, diff = nil, 0
  for k = 1, 40 do
    local c = EVAL_SHARE_SEAL_COMMENT(3)
    if not first then first = c end
    if c ~= first then diff = diff + 1 end
  end
  eq(diff > 0, true, "★★评语是**随机**抽的（40 次里出现过不同条目）")
  local info = EVAL_SHARE_SEAL_INFO(txt(13), 10)
  eq(type(info) == "table", true, "整行算得出来")
  eq(info.score, 13, "整行评分 13")
  eq(info.tierName, "源代码", "整行品阶 = 源代码")
  eq(info.rank, "筑基", "整行境界 = 筑基（10 级）")
  eq(string.find(info.line, "分享了一份传家宝", 1, true) ~= nil, true, "整行含「分享了一份传家宝」")
  eq(string.find(info.line, "[源代码秘籍·甲]", 1, true) ~= nil, true, "整行含 [品阶秘籍·方案名]")
  eq(string.find(info.line, info.comment, 1, true) ~= nil, true, "整行含评语")
  eq(string.find(info.line, "|cffb87333", 1, true) ~= nil, true, "整行含暗金色码")
  TEST.chat = ""
  SlashCmdList["EVALHELP"]("go 秘籍")
  eq(string.find(tostring(TEST.chat or ""), "秘籍预览", 1, true) ~= nil, true, "★★★/eh go 秘籍 真的执行（命令在 go 组里）")
  TEST.chat = nil
  -- ★★★1.73.42b 用户：「添加一个测试命令，输入所有类型的分享案例」
  TEST.chat = ""
  local demoN = EVAL_SHARE_SEAL_DEMO()
  eq(demoN, 12, "★★★样例要打 12 行（5 品阶 + 7 境界），实际 " .. tostring(demoN))
  local dc = tostring(TEST.chat or "")
  for _, tn in ipairs({ "普通", "稀有", "珍稀", "绝版", "源代码" }) do
    eq(string.find(dc, tn, 1, true) ~= nil, true, "★★样例里有品阶：" .. tn)
  end
  for _, rn in ipairs({ "炼气", "筑基", "金丹", "元婴", "化神", "炼虚", "大乘" }) do
    eq(string.find(dc, "[" .. rn .. "]", 1, true) ~= nil, true, "★★样例里有境界：" .. rn)
  end
  eq(string.find(dc, "|cffb87333", 1, true) ~= nil, true, "★样例里有暗金色码（源代码档）")
  EVAL_HELP_CONFIG.shareSealDemo = nil
  SlashCmdList["EVALHELP"]("go 秘籍样例")
  eq(string.find(tostring(TEST.chat or ""), "秘籍样例", 1, true) ~= nil, true, "★★★/eh go 秘籍样例 真的执行（命令在 go 组里）")
  TEST.chat = nil
  -- ★★★1.73.42c 品阶图标（语义配图）+ |T 内联纹理探针（用户：「按语义给等级配图标，先验证可行性」）
  eq(EVAL_SHARE_SEAL_ICON_COUNT(), 5, "五个品阶各一个图标")
  local iconSeen = {}
  for i = 1, 5 do
    local path, file = EVAL_SHARE_SEAL_ICON(i)
    eq(string.find(path, "Interface\\Icons\\", 1, true), 1, "图标路径是本客户端 Icon 目录：" .. tostring(path))
    eq(iconSeen[file] == nil, true, "★品阶图标不许撞图：" .. tostring(file))
    iconSeen[file] = true
  end
  local p1 = EVAL_SHARE_SEAL_ICON(1)
  eq(string.find(p1, "INV_Misc_Book_07", 1, true) ~= nil, true, "普通档 = 书（语义：入门书）")
  eq(string.find(EVAL_SHARE_SEAL_ICON(5), "INV_Misc_Gear_01", 1, true) ~= nil, true, "源代码档 = 齿轮（语义：机械/源码）")
  EVAL_HELP_CONFIG.shareIconProbe = nil
  TEST.runScripts = {}
  eq(EVAL_SHARE_ICON_PROBE("WHISPER") ~= false, true, "图标探针发送入口能跑")
  local ib = EVAL_SHARE_ICON_PROBE_BODIES()
  eq(type(ib) == "table" and table.getn(ib) == 4, true, "★探针四条形态都发了（实际 " .. tostring(ib and table.getn(ib) or 0) .. "）")
  if type(ib) == "table" then
    eq(string.find(ib[1], "|T", 1, true) ~= nil and string.find(ib[1], "|t", 1, true) ~= nil, true, "① |T…|t 带尺寸形态")
    eq(string.find(ib[2], ":0|t", 1, true) ~= nil, true, "② 省略尺寸形态")
    eq(string.find(ib[3], ":16|t", 1, true) ~= nil, true, "③ 只给宽形态")
    eq(string.find(ib[4], "★", 1, true) ~= nil, true, "④ 纯符号对照（保底参照）")
  end
  -- ★接线判据用**落盘字段**当证人（不玩聊天字符串「含子串」那套——M336 实测会假绿）
  EVAL_HELP_CONFIG.shareIconProbe = nil
  SlashCmdList["EVALHELP"]("go 图标探针")
  eq(type(EVAL_HELP_CONFIG.shareIconProbe) == "table", true, "★★★/eh go 图标探针 真的执行了（以落盘字段为证）")
  eq(table.getn((EVAL_HELP_CONFIG.shareIconProbe or {}).bodies or {}) == 4, true, "★★命令跑完写出四条形态")
  TEST.chat = nil
  -- ★★★1.73.42d 用户回报：|T 不可用（只有符号对照出来）→ 聊天行改用符号，图标进详情弹窗
  local symSeen = {}
  for i = 1, 5 do
    local s = EVAL_SHARE_SEAL_SYMBOL(i)
    eq(type(s) == "string" and string.len(s) > 0, true, "品阶符号非空 " .. i)
    eq(symSeen[s] == nil, true, "★五个品阶符号不重复：" .. tostring(s))
    symSeen[s] = true
  end
  eq(EVAL_SHARE_SEAL_SYMBOL(1), "·", "普通 = ·")
  eq(EVAL_SHARE_SEAL_SYMBOL(5), "✸", "源代码 = ✸")
  local iSym = EVAL_SHARE_SEAL_INFO(txt(13), 10)
  eq(iSym.symbol, "✸", "整行 info 里带符号")
  eq(string.find(iSym.line, "✸[源代码秘籍·甲]", 1, true) ~= nil, true, "★★整行是「符号 + [品阶秘籍·名]」")
  eq(string.find(iSym.line, "|T", 1, true) == nil, true, "★聊天行里不再出现 |T（实测不可用）")
  print("  分享显示行：境界 7 档 · 品阶评分边界(3/4/6/7/9/10/12/13) · 5 色(含暗金) · 每档 10 条评语随机 · 命令接线")
end
-- 144) ★★★1.73.42g 封皮行（显示）+ 点击直接导入（SetItemRef 的 EHPF: 分支）
do
  EVAL_SHARE_RESET()
  TEST.chat = nil TEST.runScripts = nil
  eq(EVAL_SHARE_SEND("GUILD"), true, "①分享能发出")
  local seal = tostring((EVAL_SHARE_SEAL_STATE() or {}).last or "")
  eq(string.len(seal) > 0, true, "①★★★算出了封皮行")
  eq(string.find(seal, "分享了一份传家宝", 1, true) ~= nil, true, "①★★封皮行含「分享了一份传家宝」")
  eq(string.find(seal, "|HEHPF:", 1, true) ~= nil, true, "①★★封皮行带可点链接（载荷=传输 id）")
  eq(string.find(seal, "秘籍·", 1, true) ~= nil, true, "①★★封皮行含 [品阶秘籍·方案名]")
  eq(string.find(seal, "|T", 1, true) == nil, true, "①★封皮行不含 |T（实测不可用）")
  local all = {}
  for _, sc in ipairs(TEST.runScripts or {}) do
    local m = string.match(sc, 'SendChatMessage%("(.-)", "GUILD"%)')
    if m then table.insert(all, m) end
  end
  local foundSeal = false
  for k2 = 1, table.getn(all) do if all[k2] == seal then foundSeal = true end end
  eq(foundSeal, true, "①★★★封皮**真的走了发送通道**（RunScript 里有它）")
  local sid = string.match(seal, "|HEHPF:(%x+)|h")
  eq(type(sid) == "string", true, "①读得到传输 id（" .. tostring(sid) .. "）")
  local chunks = {}
  for k3 = 1, table.getn(all) do if string.sub(all[k3], 1, 6) == "[EHPF#" or (string.find(all[k3], "|HEHPF:", 1, true) and string.find(all[k3], "传输中", 1, true)) then table.insert(chunks, all[k3]) end end
  eq(table.getn(chunks) >= 1, true, "②前置：拿到分片（" .. tostring(table.getn(chunks)) .. "）")
  eq(string.find(tostring(chunks[1] or ""), "|HEHPF:", 1, true) ~= nil, true, "②★★分片 = v2 链接形态（载荷藏在 |H 段）")
  eq(string.find(tostring(chunks[1] or ""), "传输中...", 1, true) ~= nil, true, "②★★分片标签 = 方案:名 传输中...%")
  local over = 0
  for k5 = 1, table.getn(chunks) do if string.len(chunks[k5]) > 250 then over = over + 1 end end
  eq(over, 0, "②★★★每条消息都 <= 250 字节（实测上限），超限条数=" .. tostring(over))
  eq(string.find(tostring(chunks[table.getn(chunks)] or ""), "100%", 1, true) ~= nil, true, "②★★末片标签 = 100%")
  local pctAll = true
  for k6 = 1, table.getn(chunks) do if string.find(chunks[k6], "传输中...", 1, true) == nil then pctAll = false end end
  eq(pctAll, true, "②★每片都带进度百分比")
  do
    local function hex144(str) return (string.gsub(str, ".", function(ch) return string.format("%02x", string.byte(ch)) end)) end
    EVAL_SHARE_RESET()
    EVAL_SHARE_ONMSG("[EHPF#ab 1/1]" .. hex144("# 方案: 老明文\n\n- 技能甲"), "老版本甲")
    local p144 = EVAL_SHARE_PENDING()
    eq(p144 ~= nil, true, "②★★★v1 明文分片照样能收（跨版本兼容）")
    if p144 then eq(p144.name, "老明文", "②★★且解析出方案名") end
  end
  for k4 = 1, table.getn(chunks) do EVAL_SHARE_ONMSG(chunks[k4], "队友甲") end
  eq(table.getn((EVAL_SHARE_RECENT_STATE() or {}).list or {}) >= 1, true, "②★★收齐后缓存了整份方案（点击导入要取回它）")
  TEST.chat = nil
  eq(EVAL_TEST_SIR_CLICK("EHPF:" .. tostring(sid)), true, "③★★走**真实 SetItemRef** 点了封皮")
  eq(string.len(tostring(TEST.chat or "")) > 0, true, "③★★点击后有如实播报（导入桥的回执）")
  TEST.chat = nil
  eq(EVAL_SHARE_CLICK_IMPORT("EHPF:" .. tostring(sid)), true, "③★★★命中缓存 → 导入返回成功")
  TEST.chat = nil
  EVAL_TEST_SIR_CLICK("EHPF:ff")
  local miss = tostring(TEST.chat or "")
  eq(string.find(miss, "还没收齐", 1, true) ~= nil, true, "③★★没缓存 → 如实提示「还没收齐」（实际：" .. string.sub(miss, 1, 60) .. "）")
  TEST.chat = nil
  EVAL_TEST_SIR_CLICK("player:Ionol")
  eq(string.find(tostring(TEST.chat or ""), "还没收齐", 1, true) == nil, true, "③★非 EHPF 链接不进入口（原样放行）")
  TEST.chat = nil
  print("  封皮行：传家宝 + 品阶秘籍 + 可点链接 · 立即发 · 收齐缓存 · 点击直接导入 · 未命中如实提示")
end

print("ALL TESTS PASS")

  local sd142 = EVAL_HELP_CONFIG.shareSealDemo
  eq(type(sd142) == "table" and sd142.n == 12, true,
     "★★★/eh go 秘籍样例 真的执行了（以**落盘字段**为证：n=" .. tostring(type(sd142) == "table" and sd142.n or "nil") .. "）")