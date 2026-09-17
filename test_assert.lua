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
eq(EVAL_PARSE_CONDS("目标职业:圣骑士")[1], nil, "非法职业整条丢弃")

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
eq(EVAL_GROUP_STR(EVAL_PARSE_CONDS("读条>2")), "读条>2", "elapsed roundtrip")
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
EVAL_HELP_CONFIG.tb = { repair = true, sell = true, ready = true, quest = true, buyOn = true, buy = { { name = "晨露酒", n = 5 } }, discardOn = true, discard = { "破布" } }
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
eq(TEST.bought, "晨露酒x3;", "tb queued buy after sells")
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
  -- 分组标题(1) + 哨兵行(-1) = 2 项：标题永远保留，所以此处是 2 而不是 1
  eq(table.getn(free), 2, "the locked header plus the sentinel are shown when nothing matches")
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
  eq(table.getn(nofree), 1, "only the header is shown when nothing matches and free text is off")
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
  local src, recCfg, recSe = EVAL_TEST_WIN_W()
  eq(src, 660, "★width source = 660 (zhCN)")
  eq(recCfg, src, "★config window recorded the same width")
  eq(recSe, src, "★skill-editor window recorded the same width")
  -- 真实尺寸（问帧，不问常量）
  local sw, sh = EVAL_TEST_SE_SIZE()
  eq(sw, 660, "★★skill editor REAL width is 660")
  eq(sh, 280, "★★★skill editor REAL height is 280 (1.70.46: SetHeight had been swallowed by a line comment)")
  local cw, ch = EVAL_TEST_CFG_SIZE()
  eq(cw, 660, "★★config window REAL width is 660")
  eq(ch, 420, "★★★config window REAL height is 420")
  -- 高度必须是正数：防止「设成 0/nil 也算设了」这种假通过
  eq(type(sh) == "number" and sh > 0, true, "★height is a real positive number, not nil/0")
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
    if not pcall(EVAL_TEST_SE_PUSH_COND, k, "测试", "<", 5) then table.insert(failed, k) end
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
  eq(EVAL_TEST_COND_EVAL_LIVE({ k = "teamHp", op = ">", n = 60 }, nil), false, "★反向比较如实为假")
  eq(EVAL_HELP_STATE.allyUnit, nil, "★未命中就不该记人（别把上一轮的人留下）")
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
print("ALL TESTS PASS")
