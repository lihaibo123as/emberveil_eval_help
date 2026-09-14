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
eq(cats[1].label, "角色行为", "cat1 label")
eq(cats[1].items()[1], "攻击", "cat1 has attack")
eq(cats[3].label, "宠物行为", "cat3 label")
local foundPetCmd = false
for _, n in ipairs(cats[3].items()) do if n == "宠物:攻击" then foundPetCmd = true end end
eq(foundPetCmd, true, "cat3 has pet cmds")
eq(cats[4].label, "目标选取", "cat4 label")
local foundTsel = false
for _, n in ipairs(cats[4].items()) do if n == "选取目标:最近敌人" then foundTsel = true end end
eq(foundTsel, true, "cat4 has target-sel skills")
eq(cats[5].label, "物品使用", "cat5 label")
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

print("ALL TESTS PASS")
