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
eq(EVAL_HELP_STATE.playerBuffs["texRegen"], true, "UnitBuff texture merged into playerBuffs")
TEST.unitBuffs = nil EVAL_HELP_UPDATE_STATE()

-- 18) i18n 核心（1.34.0）：EVAL_L 查找/回退/格式化；EVAL_SET_LANG 切换与校验
EVAL_LOCALES = { zhCN = { T_HELLO = "你好", T_FMT = "数量%d" }, enUS = { T_HELLO = "Hello" } }
eq(EVAL_L("T_HELLO"), "你好", "default zhCN")
eq(EVAL_L("T_FMT", 5), "数量5", "format arg")
EVAL_SET_LANG("enUS")
eq(EVAL_L("T_HELLO"), "Hello", "switched enUS")
eq(EVAL_L("T_FMT", 7), "数量7", "missing key falls back zhCN, formatted")
EVAL_SET_LANG("zhCN")
eq(EVAL_L("NO_SUCH_KEY"), "NO_SUCH_KEY", "unknown key shows itself")
eq(EVAL_SET_LANG("xxXX"), false, "invalid code rejected")

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
EVAL_GO()
eq(EVAL_HELP_STATE.autoAttack, true, "autoAttack state accurate with takeover off")
TEST.currentAction = nil EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[2] = nil EVAL_GO_RESCAN(true)
-- 接管泛化（1.49.2）：无「攻击」时回退「自动射击」（UseAction 通道）
TEST.slotNames[3] = "自动射击" EVAL_GO_RESCAN(true)
TEST.used = {} EVAL_HELP_CONFIG.war.attack = true
TEST.curTargetName = nil EVAL_HELP_UPDATE_STATE()
EVAL_GO()
local usedSlot3 = false
for _, u in ipairs(TEST.used) do if u == 3 then usedSlot3 = true end end
eq(usedSlot3, true, "autoshot takeover fires UseAction")
-- 自动攻击优先级（1.50.0）：攻击+自动射击 同时在条 → 优先自动射击，不碰近战 AttackTarget
TEST.slotNames[1] = "攻击" EVAL_GO_RESCAN(true)
TEST.used = {} TEST.attackTried = nil
EVAL_GO()
local usedSlot1 = false
for _, u in ipairs(TEST.used) do if u == 1 then usedSlot1 = true end end
eq(usedSlot3 and not usedSlot1, true, "autoshot wins over melee attack")
eq(TEST.attackTried, nil, "AttackTarget not called when autoshot available")
TEST.used = {} EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[1] = nil TEST.slotNames[3] = nil EVAL_GO_RESCAN(true)

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
TEST.slotNames[1] = "攻击" TEST.slotNames[2] = "自动射击" EVAL_GO_RESCAN(true)
EVAL_HELP_CONFIG.war.attack = true
-- 接管有 2s 节流（wLastAttackTry 是 Engine local 测试无法直清）：桩 GetTime 恒定 1000，前移 3s 绕过
local oldGetTime32 = GetTime
GetTime = function() return 1003 end
TEST.inRange = { [2] = 0 } -- 自动射击超程（贴脸）
TEST.used = {} TEST.attackTried = nil
EVAL_GO()
local usedSlot2 = false
for _, u in ipairs(TEST.used) do if u == 2 then usedSlot2 = true end end
eq(usedSlot2, false, "out-of-range autoshot downgraded")
eq(TEST.attackTried, true, "melee attack fallback when autoshot out of range")
GetTime = function() return 1006 end -- 再过节流
TEST.inRange = { [2] = true } -- 在射程内
TEST.used = {} TEST.attackTried = nil
EVAL_GO()
usedSlot2 = false
for _, u in ipairs(TEST.used) do if u == 2 then usedSlot2 = true end end
eq(usedSlot2, true, "in-range autoshot picked")
eq(TEST.attackTried, nil, "no melee fallback when autoshot in range")
GetTime = oldGetTime32
TEST.inRange = nil TEST.used = {} EVAL_HELP_CONFIG.war.attack = nil TEST.slotNames[1] = nil TEST.slotNames[2] = nil EVAL_GO_RESCAN(true)

print("ALL TESTS PASS")
