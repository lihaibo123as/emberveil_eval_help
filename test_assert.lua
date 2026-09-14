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

print("ALL TESTS PASS")
