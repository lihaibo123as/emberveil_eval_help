-- EvalHelp · PetData.lua —— 猎人宠物数据（1.73.0 独立载入）
-- ★★★本文件是**生成物**（生成器 = 仓库根目录 gen_petdata.js，数据源 = doc/宠物技能数据.lua + 本生成器里的家族属性表）：
--   **绝不手改本文件** —— 改数据请改生成器再跑 `node gen_petdata.js`，否则下次生成会把手改冲掉。
-- 数据来源：① 宠物技能总表截图（doc/pet_info.png）② 家族基础属性表截图（doc/猎人宠物属性和技能图.jpg，转录见 doc/猎人宠物家族属性.md）。
-- 结构：skills（技能定义+图标）/ ranks[技能名]（各等级：需求宠物等级 + 驯服来源野兽 + fam）/ families（家族 id → 名称+图标+三加成+食物+天生技能+客户端家族名候选）/ famOrder（图片行序）。
-- ★★fam（野兽→家族）按**图片的「家族→技能」三列**定案（用户 2026-09-25：「以最新的图片为准」）：
--   ① 技能交集唯一 ⇒ 图片直接定案 ② 名字关键字（只在候选内、最长匹配优先，修了「狼蛛被当狼」的老 bug）
--   ③ 显式覆写（同系列兄弟/知名命名怪，见生成器 FAM_OVERRIDE 与理由）④ 名字硬证据（…鳄鱼/…蛛）⑤ 其余如实 other。
--   ★`skNoJudge` = 不作判据的技能（图片列与来源表真冲突）；闸门读它，例外清单只有这一处来源。
-- 图标：**本客户端真实纹理路径**（/Game/Interface/Icons/<名字>_TEX，Unreal 资产路径）——取自 doc/图标路径清单.txt，由 PET ICON CHECK 逐条核对存在性；★1.12 的 Interface\Icons\ 写法在本客户端只显示成引擎的「?」缺图占位。

EVAL_PET_DB = {}

EVAL_PET_DB.skills = {
  { id = "bite", name = "撕咬", cost = 35, cast = "瞬发", range = "5码", cd = "10秒", kind = "主动", intro = "撕咬目标，宠物最基础的伤害技能", icon = "/Game/Interface/Icons/Ability_Racial_Cannibalize_TEX", iconIdx = 139 },
  { id = "claw", name = "爪击", cost = 25, cast = "瞬发", range = "5码", cd = "无", kind = "主动", intro = "快速爪击，无冷却但消耗集中值", icon = "/Game/Interface/Icons/Ability_Druid_Rake_TEX", iconIdx = 255 },
  { id = "dash", name = "突进", cost = 20, cast = "瞬发", range = "—", cd = "30秒", kind = "主动", intro = "短时间大幅提升移动速度，追击或脱离用", icon = "/Game/Interface/Icons/Ability_Druid_Dash_TEX" },
  { id = "dive", name = "俯冲", cost = 20, cast = "瞬发", range = "—", cd = "30秒", kind = "主动", intro = "飞行系宠物的冲刺，效果同突进", icon = "/Game/Interface/Icons/INV_Feather_01_TEX" },
  { id = "charge", name = "冲锋", cost = 35, cast = "瞬发", range = "8-25码", cd = "25秒", kind = "主动", intro = "冲锋并定身目标，下一次攻击附加伤害", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Boar_TEX", iconIdx = 700 },
  { id = "howl", name = "嚎叫", cost = 60, cast = "瞬发", range = "15码", cd = "10秒", kind = "主动", intro = "为队友的下一次攻击附加伤害", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Wolf_TEX", iconIdx = 695 },
  { id = "lightning", name = "闪电吐息", cost = 50, cast = "瞬发", range = "20码", cd = "无", kind = "主动", intro = "远程自然伤害，风蛇专属", icon = "/Game/Interface/Icons/Spell_Nature_Lightning_TEX" },
  { id = "prowl", name = "潜伏", cost = 40, cast = "瞬发", range = "—", cd = "10秒", kind = "主动", intro = "进入潜行，下一次攻击获得额外伤害", icon = "/Game/Interface/Icons/Ability_Stealth_TEX" },
  { id = "scorpid", name = "蝎毒", cost = 30, cast = "瞬发", range = "—", cd = "4秒", kind = "主动", intro = "持续自然伤害，可叠加5次", icon = "/Game/Interface/Icons/Ability_PoisonSting_TEX" },
  { id = "screech", name = "尖啸", cost = 20, cast = "瞬发", range = "8码", cd = "4秒", kind = "主动", intro = "降低范围内敌人的攻击强度", icon = "/Game/Interface/Icons/Spell_Shadow_PsychicScream_TEX" },
  { id = "shell", name = "甲壳护盾", cost = 10, cast = "瞬发", range = "—", cd = "180秒", kind = "主动", intro = "降低受到的伤害，代价是攻击间隔变长", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Turtle_TEX", iconIdx = 710 },
  { id = "thunder", name = "雷霆践踏", cost = 60, cast = "瞬发", range = "8码", cd = "60秒", kind = "主动", intro = "范围自然伤害，猩猩专属", icon = "/Game/Interface/Icons/Ability_ThunderClap_TEX" },
  { id = "cower", name = "畏缩", cost = 25, cast = "瞬发", range = "5码", cd = "5秒", kind = "主动", intro = "降低仇恨值（与低吼共享冷却）", icon = "/Game/Interface/Icons/Ability_Druid_Cower_TEX" },
  { id = "growl", name = "低吼", cost = 15, cast = "瞬发", range = "5码", cd = "5秒", kind = "被动-训练师", intro = "提高仇恨，宠物坦克核心（训练师学习）", icon = "/Game/Interface/Icons/Ability_Physical_Taunt_TEX" },
  { id = "stamina", name = "持久耐力", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高宠物耐力（训练师学习）", icon = "/Game/Interface/Icons/Spell_Nature_UnyeildingStamina_TEX" },
  { id = "natarmor", name = "自然护甲", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高宠物护甲（训练师学习）", icon = "/Game/Interface/Icons/Spell_Nature_SpiritArmor_TEX" },
  { id = "fireres", name = "火焰抗性", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高火焰抗性（训练师学习）", icon = "/Game/Interface/Icons/Spell_FireResistanceTotem_01_TEX" },
  { id = "frostres", name = "冰霜抗性", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高冰霜抗性（训练师学习）", icon = "/Game/Interface/Icons/Spell_Fire_FrostResistanceTotem_TEX" },
  { id = "shadowres", name = "暗影抗性", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高暗影抗性（训练师学习）", icon = "/Game/Interface/Icons/Spell_Shadow_SealOfKings_TEX", iconIdx = 133 },
  { id = "natureres", name = "自然抗性", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高自然抗性（训练师学习）", icon = "/Game/Interface/Icons/Spell_Nature_NatureResistanceTotem_TEX" },
  { id = "arcaneres", name = "奥术抗性", cost = 0, cast = "被动", range = "—", cd = "—", kind = "被动-训练师", intro = "提高奥术抗性（训练师学习）", icon = "/Game/Interface/Icons/Spell_Arcane_ArcaneResilience_TEX" },
}

EVAL_PET_DB.ranks = {
  ["撕咬"] = {
    { rank = 1, req = 1, beasts = {
      { zone = "丹莫罗", name = "雪狼", level = "6-7", fam = "wolf" },
      { zone = "丹莫罗", name = "冬狼", level = "6-8", fam = "wolf" },
      { zone = "杜隆塔尔", name = "巨齿鳄鱼", level = "9-11", fam = "crocolisk" },
      { zone = "艾尔文森林", name = "森林蜘蛛", level = "5-6", fam = "spider" },
      { zone = "艾尔文森林", name = "森林灰狼", level = "7-8", fam = "wolf" },
      { zone = "莫高雷", name = "草原狼", level = "5-6", fam = "wolf" },
      { zone = "莫高雷", name = "草原捕食者", level = "7-8", fam = "cat" },
      { zone = "泰达希尔", name = "邪恶的基塞伊斯", level = "5", fam = "cat" },
      { zone = "泰达希尔", name = "树林蜘蛛", level = "3-4", fam = "spider" },
      { zone = "提瑞斯法林地", name = "夜行蜘蛛", level = "3-4", fam = "spider" },
      { zone = "提瑞斯法林地", name = "夜行雌蜘蛛", level = "5", fam = "spider" },
      { zone = "西部荒野", name = "山狗", level = "10-11", fam = "wolf" },
      { zone = "西部荒野", name = "山狗首领", level = "11-12", fam = "wolf" },
    } },
    { rank = 2, req = 8, beasts = {
      { zone = "贫瘠之地", name = "绿洲钳嘴龟", level = "15-16", fam = "turtle" },
      { zone = "丹莫罗", name = "饥饿的冬狼", level = "8-9", fam = "wolf" },
      { zone = "丹莫罗", name = "狂暴的冬狼", level = "10", fam = "wolf" },
      { zone = "艾尔文森林", name = "觅食的灰狼", level = "9-10", fam = "wolf" },
      { zone = "艾尔文森林", name = "母蜘蛛", level = "10", fam = "spider" },
      { zone = "洛克莫丹", name = "森林潜伏者", level = "10-11", fam = "spider" },
      { zone = "洛克莫丹", name = "洛克鳄", level = "14-15", fam = "crocolisk" },
      { zone = "莫高雷", name = "草原狼前锋", level = "9-10", fam = "wolf" },
      { zone = "赤脊山", name = "狼蛛", level = "14", fam = "spider" },
    } },
    { rank = 3, req = 16, beasts = {
      { zone = "灰谷", name = "幽爪奔跑者", level = "19-20", fam = "wolf" },
      { zone = "黑暗深渊副本", name = "阿库麦尔食鱼龟", level = "23-24", fam = "turtle" },
      { zone = "黑暗深渊副本", name = "加摩拉", level = "25", fam = "turtle" },
      { zone = "暮色森林", name = "绿色独行蛛", level = "21-22", fam = "spider" },
      { zone = "暮色森林", name = "鲁伯斯", level = "23", fam = "wolf" },
      { zone = "希尔斯布莱德丘陵", name = "森林食苔蛛", level = "20-21", fam = "spider" },
      { zone = "洛克莫丹", name = "林木潜伏者", level = "17-18", fam = "spider" },
      { zone = "赤脊山", name = "巨型狼蛛", level = "19-20", fam = "spider" },
      { zone = "石爪山脉", name = "贝瑟莱斯", level = "21", fam = "spider" },
      { zone = "石爪山脉", name = "深苔爬行者", level = "16-17", fam = "spider" },
      { zone = "石爪山脉", name = "深苔结网蛛", level = "19-20", fam = "spider" },
      { zone = "哀嚎洞穴副本", name = "变异鳄鱼", level = "18-19", fam = "crocolisk" },
    } },
    { rank = 4, req = 24, beasts = {
      { zone = "灰谷", name = "幽爪前锋", level = "27-28", fam = "wolf" },
      { zone = "灰谷", name = "野棘潜伏者", level = "28-29", fam = "spider" },
      { zone = "黑暗深渊副本", name = "阿库麦尔钳嘴龟", level = "26-27", fam = "turtle" },
      { zone = "暮色森林", name = "黑色破坏者", level = "24-25", fam = "wolf" },
      { zone = "暮色森林", name = "巨型黑色破坏者", level = "25-26", fam = "wolf" },
      { zone = "暮色森林", name = "拉克西斯", level = "27", fam = "spider" },
      { zone = "希尔斯布莱德丘陵", name = "老食苔蛛", level = "26-27", fam = "spider" },
      { zone = "希尔斯布莱德丘陵", name = "巨型食苔蛛", level = "24-26", fam = "spider" },
    } },
    { rank = 5, req = 32, beasts = {
      { zone = "阿拉希高地", name = "巨型平原狼蛛", level = "35-36", fam = "spider" },
      { zone = "阿拉希高地", name = "平原狼蛛", level = "32-33", fam = "spider" },
      { zone = "荒芜之地", name = "峭壁山狗", level = "35-36", fam = "wolf" },
      { zone = "尘泥沼泽", name = "暗牙爬行者", level = "38-39", fam = "spider" },
      { zone = "尘泥沼泽", name = "暗牙潜伏者", level = "36-37", fam = "spider" },
      { zone = "尘泥沼泽", name = "暗牙蜘蛛", level = "35-36", fam = "spider" },
      { zone = "尘泥沼泽", name = "尘泥鳄鱼", level = "35-36", fam = "crocolisk" },
      { zone = "尘泥沼泽", name = "尘泥杂斑鳄鱼", level = "38-39", fam = "crocolisk" },
      { zone = "尘泥沼泽", name = "泥石海龟", level = "36-37", fam = "turtle" },
      { zone = "千针石林", name = "盐壳钳嘴龟", level = "34-35", fam = "turtle" },
    } },
    { rank = 6, req = 40, beasts = {
      { zone = "艾萨拉", name = "林木隐匿者", level = "47-48", fam = "spider" },
      { zone = "荒芜之地", name = "巴纳布斯", level = "39", fam = "cat" },
      { zone = "尘泥沼泽", name = "死沼巨鳄", level = "45", fam = "crocolisk" },
      { zone = "尘泥沼泽", name = "尘泥利齿鳄鱼", level = "40-41", fam = "crocolisk" },
      { zone = "尘泥沼泽", name = "泥石钳嘴龟", level = "41-42", fam = "turtle" },
      { zone = "费伍德森林", name = "魔爪狼", level = "47-48", fam = "wolf" },
      { zone = "菲拉斯", name = "长牙奔跑者", level = "40-41", fam = "wolf" },
      { zone = "菲拉斯", name = "咆哮者", level = "42", fam = "wolf" },
    } },
    { rank = 7, req = 48, beasts = {
      { zone = "费伍德森林", name = "魔爪掠夺者", level = "51-52", fam = "wolf" },
      { zone = "辛特兰", name = "铁背龟", level = "51", fam = "turtle" },
      { zone = "辛特兰", name = "海水钳嘴龟", level = "49-50", fam = "turtle" },
      { zone = "辛特兰", name = "邪枝巨狼", level = "50-51", fam = "wolf" },
      { zone = "安戈洛环形山", name = "乌卡洛克", level = "52-53", fam = "gorilla" },
      { zone = "西瘟疫之地", name = "生病的狼", level = "53-54", fam = "wolf" },
      { zone = "西瘟疫之地", name = "瘟疫潜伏者", level = "54-55", fam = "spider" },
      { zone = "灼热峡谷", name = "雷克提拉克", level = "49", fam = "spider" },
      { zone = "暴风城", name = "下水道鳄鱼", level = "50", fam = "crocolisk" },
      { zone = "悲伤沼泽", name = "死亡狼蛛", level = "40-41", fam = "spider" },
      { zone = "悲伤沼泽", name = "盐齿钳嘴鳄", level = "41-42", fam = "crocolisk" },
      { zone = "菲拉斯", name = "铁鬃熊王", level = "48-49", fam = "bear" },
      { zone = "诅咒之地", name = "掠夺者科拉克", level = "53", fam = "bird" },
    } },
    { rank = 8, req = 56, beasts = {
      { zone = "黑石塔副本", name = "血斧座狼", level = "56-57", fam = "wolf" },
      { zone = "冬泉谷", name = "老碎齿熊", level = "57-58", fam = "bear" },
      { zone = "冬泉谷", name = "冬泉鸣枭", level = "57-59", fam = "bird" },
    } },
  },
  ["爪击"] = {
    { rank = 1, req = 1, beasts = {
      { zone = "杜隆塔尔", name = "小海湾蟹", level = "5-6", fam = "crab" },
      { zone = "杜隆塔尔", name = "萨科斯", level = "4", fam = "scorpid" },
      { zone = "杜隆塔尔", name = "蝎子", level = "3", fam = "scorpid" },
      { zone = "丹莫罗", name = "冰爪熊", level = "7-8", fam = "bear" },
      { zone = "泰达希尔", name = "巨翼枭", level = "5-6", fam = "owl" },
    } },
    { rank = 2, req = 8, beasts = {
      { zone = "银松森林", name = "凶猛的灰斑熊", level = "11-12", fam = "bear" },
      { zone = "泰达希尔", name = "巨翼猎枭", level = "8-9", fam = "owl" },
    } },
    { rank = 3, req = 16, beasts = {
      { zone = "希尔斯布莱德丘陵", name = "灰熊", level = "21-22", fam = "bear" },
      { zone = "灰谷", name = "灰谷熊", level = "21-22", fam = "bear" },
      { zone = "灰谷", name = "巨钳蟹", level = "19-20", fam = "crab" },
      { zone = "黑海岸", name = "薊熊", level = "11-12", fam = "bear" },
      { zone = "黑海岸", name = "潮行蟹", level = "13-14", fam = "crab" },
      { zone = "丹莫罗", name = "癞爪", level = "11", fam = "wolf" },
      { zone = "丹莫罗", name = "游荡的冰爪熊", level = "12", fam = "bear" },
      { zone = "艾尔文森林", name = "森林熊幼崽", level = "8-9", fam = "bear" },
      { zone = "洛克莫丹", name = "黑熊首领", level = "16-17", fam = "bear" },
      { zone = "洛克莫丹", name = "奥尔苏迪", level = "20", fam = "bear" },
      { zone = "西部荒野", name = "猎行蛛", level = "17-18", fam = "spider" },
    } },
    { rank = 4, req = 24, beasts = {
      { zone = "千针石林", name = "恐蝎劫掠者", level = "31-32", fam = "scorpid" },
      { zone = "黑暗深渊副本", name = "刺毛甲壳蟹", level = "25-26", fam = "crab" },
      { zone = "凄凉之地", name = "荒土巨钳蝎", level = "30-31", fam = "scorpid" },
      { zone = "尘泥沼泽", name = "尘泥钳嘴鳄鱼", level = "37-38", fam = "crocolisk" },
    } },
    { rank = 5, req = 32, beasts = {
      { zone = "凄凉之地", name = "荒土鞭尾蝎", level = "34-35", fam = "scorpid" },
    } },
    { rank = 6, req = 40, beasts = {
      { zone = "塔纳利斯", name = "沙漠猎食蝎", level = "40-41", fam = "scorpid" },
      { zone = "荆棘谷", name = "虎王邦加拉什", level = "43", fam = "cat" },
    } },
    { rank = 7, req = 48, beasts = {
      { zone = "菲拉斯", name = "铁鬃熊王", level = "48-49", fam = "bear" },
      { zone = "诅咒之地", name = "掠夺者科拉克", level = "53", fam = "bird" },
    } },
    { rank = 8, req = 56, beasts = {
      { zone = "冬泉谷", name = "老碎齿熊", level = "57-58", fam = "bear" },
      { zone = "冬泉谷", name = "冬泉鸣枭", level = "57-59", fam = "bird" },
    } },
  },
  ["突进"] = {
    { rank = 1, req = 30, beasts = {
      { zone = "荒芜之地", name = "断牙", level = "37", fam = "cat" },
      { zone = "荒芜之地", name = "峭壁山狗", level = "35-36", fam = "wolf" },
      { zone = "荒芜之地", name = "老峭壁山狗", level = "38-40", fam = "wolf" },
      { zone = "凄凉之地", name = "骨爪土狼", level = "33-35", fam = "hyena" },
      { zone = "凄凉之地", name = "玛格拉姆骨爪土狼", level = "37-38", fam = "hyena" },
      { zone = "血色修道院副本", name = "血色猎犬", level = "33-34", fam = "wolf" },
      { zone = "荆棘谷", name = "库尔森战虎", level = "32-33", fam = "cat" },
      { zone = "荆棘谷", name = "荆棘谷猛虎", level = "32-33", fam = "cat" },
      { zone = "荆棘谷", name = "辛达尔", level = "37", fam = "cat" },
    } },
    { rank = 2, req = 40, beasts = {
      { zone = "荒芜之地", name = "山脊雄豹", level = "40-41", fam = "cat" },
      { zone = "诅咒之地", name = "灰鬃野猪", level = "48-49", fam = "boar" },
      { zone = "诅咒之地", name = "格朗特", level = "50", fam = "boar" },
      { zone = "菲拉斯", name = "长牙奔跑者", level = "40-41", fam = "wolf" },
      { zone = "辛特兰", name = "海崖奔跳者", level = "42", fam = "wolf" },
      { zone = "辛特兰", name = "银鬃捕猎者", level = "47-48", fam = "wolf" },
      { zone = "荆棘谷", name = "巴尔瑟拉", level = "40", fam = "cat" },
      { zone = "荆棘谷", name = "老年深喉猎豹", level = "42-43", fam = "cat" },
      { zone = "荆棘谷", name = "虎王邦加拉什", level = "43", fam = "cat" },
      { zone = "塔纳利斯", name = "疱爪土狼", level = "44-45", fam = "hyena" },
      { zone = "塔纳利斯", name = "疯狂的疱爪土狼", level = "47-48", fam = "hyena" },
    } },
    { rank = 3, req = 50, beasts = {
      { zone = "燃烧平原", name = "黑石座狼", level = "54-55", fam = "wolf" },
      { zone = "冬泉谷", name = "霜刃捕食者", level = "59-60", fam = "cat" },
      { zone = "冬泉谷", name = "拉克西里", level = "59", fam = "cat" },
      { zone = "诅咒之地", name = "格朗特", level = "50", fam = "boar" },
      { zone = "辛特兰", name = "邪枝巨狼", level = "50-51", fam = "wolf" },
      { zone = "黑石塔副本", name = "血斧座狼", level = "56-57", fam = "wolf" },
    } },
  },
  ["俯冲"] = {
    { rank = 1, req = 30, beasts = {
      { zone = "阿拉希高地", name = "山地秃鹫", level = "34-35", fam = "bird" },
      { zone = "阿拉希高地", name = "山地秃鹫幼崽", level = "31-32", fam = "bird" },
      { zone = "剃刀沼泽副本", name = "沼泽蝙蝠", level = "30-31", fam = "bat" },
      { zone = "凄凉之地", name = "恐怖飞鸟", level = "36-37", fam = "bird" },
      { zone = "奥达曼副本", name = "利齿蝙蝠", level = "38-39", fam = "bat" },
    } },
    { rank = 2, req = 40, beasts = {
      { zone = "费伍德森林", name = "铁喙猫头鹰", level = "48-49", fam = "owl" },
      { zone = "塔纳利斯", name = "大鹏", level = "41-43", fam = "bird" },
      { zone = "塔纳利斯", name = "火鹏", level = "43-45", fam = "bird" },
      { zone = "菲拉斯", name = "阿拉瑟希斯", level = "49", fam = "windserpent" },
      { zone = "菲拉斯", name = "游荡的山谷尖啸者", level = "44-46", fam = "windserpent" },
      { zone = "菲拉斯", name = "山谷尖啸者", level = "41-43", fam = "windserpent" },
    } },
    { rank = 3, req = 50, beasts = {
      { zone = "费伍德森林", name = "铁喙狩猎者", level = "50-51", fam = "owl" },
      { zone = "费伍德森林", name = "铁喙尖啸者", level = "52-53", fam = "bird" },
      { zone = "费伍德森林", name = "智者奥尔姆", level = "53", fam = "owl" },
      { zone = "冬泉谷", name = "冬泉鸣枭", level = "57-59", fam = "bird" },
      { zone = "荒芜之地", name = "扎里科特", level = "55", fam = "bird" },
      { zone = "诅咒之地", name = "斯比弗雷尔", level = "52", fam = "bird" },
      { zone = "东瘟疫之地", name = "天灾蝙蝠", level = "53-55", fam = "bat" },
    } },
  },
  ["冲锋"] = {
    { rank = 1, req = 1, beasts = {
      { zone = "杜隆塔尔", name = "杂斑野猪", level = "1-2", fam = "boar" },
      { zone = "杜隆塔尔", name = "可怕的杂斑野猪", level = "6-7", fam = "boar" },
      { zone = "杜隆塔尔", name = "老杂斑野猪", level = "8-9", fam = "boar" },
      { zone = "杜隆塔尔", name = "堕落的杂斑野猪", level = "10-11", fam = "boar" },
      { zone = "丹莫罗", name = "小型峭壁野猪", level = "3", fam = "boar" },
      { zone = "丹莫罗", name = "峭壁野猪", level = "5-6", fam = "boar" },
      { zone = "丹莫罗", name = "老峭壁野猪", level = "7-8", fam = "boar" },
      { zone = "艾尔文森林", name = "石牙野猪", level = "5-6", fam = "boar" },
      { zone = "艾尔文森林", name = "公主的随从", level = "7", fam = "boar" },
      { zone = "艾尔文森林", name = "石皮野猪", level = "7-8", fam = "boar" },
      { zone = "莫高雷", name = "年幼的斗猪", level = "3-4", fam = "boar" },
      { zone = "莫高雷", name = "刺背斗猪", level = "4-5", fam = "boar" },
      { zone = "泰达希尔", name = "草刺野猪", level = "1-2", fam = "boar" },
    } },
    { rank = 2, req = 12, beasts = {
      { zone = "洛克莫丹", name = "老山猪", level = "16-17", fam = "boar" },
      { zone = "洛克莫丹", name = "癞皮山猪", level = "14-15", fam = "boar" },
      { zone = "赤脊山", name = "巨型血牙野猪", level = "16-17", fam = "boar" },
      { zone = "西部荒野", name = "幼年血牙野猪", level = "12-13", fam = "boar" },
      { zone = "西部荒野", name = "血牙野猪", level = "14-15", fam = "boar" },
    } },
    { rank = 3, req = 24, beasts = {
      { zone = "剃刀沼泽副本", name = "阿迦玛", level = "24-25", fam = "boar" },
      { zone = "剃刀沼泽副本", name = "暴怒的阿迦玛", level = "25-26", fam = "boar" },
      { zone = "剃刀沼泽副本", name = "腐烂的阿迦玛", level = "28", fam = "boar" },
      { zone = "赤脊山", name = "贝利格拉布", level = "24", fam = "boar" },
    } },
    { rank = 4, req = 48, beasts = {
      { zone = "诅咒之地", name = "灰鬃野猪", level = "48-49", fam = "boar" },
      { zone = "诅咒之地", name = "格朗特", level = "50", fam = "boar" },
    } },
    { rank = 5, req = 60, beasts = {
      { zone = "东瘟疫之地", name = "天灾野猪", level = "60", fam = "boar" },
    } },
  },
  ["嚎叫"] = {
    { rank = 1, req = 10, beasts = {
      { zone = "银松森林", name = "座狼", level = "10-11", fam = "wolf" },
      { zone = "西部荒野", name = "山狗首领", level = "11-12", fam = "wolf" },
    } },
    { rank = 2, req = 24, beasts = {
      { zone = "暮色森林", name = "巨型黑色破坏者", level = "25-26", fam = "wolf" },
      { zone = "灰谷", name = "幽爪前锋", level = "27-28", fam = "wolf" },
      { zone = "荒芜之地", name = "老峭壁山狗", level = "38-40", fam = "wolf" },
      { zone = "菲拉斯", name = "长牙奔跑者", level = "40-41", fam = "wolf" },
      { zone = "辛特兰", name = "银鬃狼", level = "43-44", fam = "wolf" },
      { zone = "辛特兰", name = "银鬃嗥狼", level = "45-46", fam = "wolf" },
    } },
    { rank = 3, req = 40, beasts = {
      { zone = "菲拉斯", name = "长牙嚎叫者", level = "43-44", fam = "wolf" },
      { zone = "费伍德森林", name = "魔爪狼", level = "47-48", fam = "wolf" },
    } },
    { rank = 4, req = 56, beasts = {
      { zone = "黑石塔副本", name = "血斧座狼", level = "56-57", fam = "wolf" },
    } },
  },
  ["闪电吐息"] = {
    { rank = 1, req = 1, beasts = {
      { zone = "哀嚎洞穴副本", name = "变异刺喉蛇", level = "16-17", fam = "windserpent" },
    } },
    { rank = 2, req = 12, beasts = {
      { zone = "哀嚎洞穴副本", name = "变异尖牙风蛇", level = "20-21", fam = "windserpent" },
      { zone = "哀嚎洞穴副本", name = "变异剧毒风蛇", level = "20-21", fam = "windserpent" },
      { zone = "贫瘠之地", name = "雷鹰雏鸟", level = "18-20", fam = "windserpent" },
      { zone = "贫瘠之地", name = "雷鹰破云者", level = "20-22", fam = "windserpent" },
      { zone = "贫瘠之地", name = "大型雷鹰", level = "23-24", fam = "windserpent" },
    } },
    { rank = 3, req = 24, beasts = {
      { zone = "千针石林", name = "风蛇", level = "25-26", fam = "windserpent" },
      { zone = "千针石林", name = "毒性风蛇", level = "26-28", fam = "windserpent" },
      { zone = "千针石林", name = "老风蛇", level = "27-29", fam = "windserpent" },
    } },
    { rank = 4, req = 36, beasts = {
      { zone = "菲拉斯", name = "山谷尖啸者", level = "41-43", fam = "windserpent" },
      { zone = "菲拉斯", name = "游荡的山谷尖啸者", level = "44-46", fam = "windserpent" },
      { zone = "菲拉斯", name = "阿拉瑟希斯", level = "49", fam = "windserpent" },
    } },
    { rank = 5, req = 48, beasts = {
      { zone = "沉没的神庙副本", name = "哈卡莱霜翼飞蛇", level = "49-50", fam = "windserpent" },
      { zone = "沉没的神庙副本", name = "哈卡莱挖掘者", level = "49-50", fam = "windserpent" },
    } },
    { rank = 6, req = 60, beasts = {
      { zone = "祖尔格拉布副本", name = "哈卡之子", level = "60", fam = "windserpent" },
    } },
  },
  ["潜伏"] = {
    { rank = 1, req = 30, beasts = {
      { zone = "奥特兰克山脉", name = "山地狮", level = "32-33", fam = "cat" },
      { zone = "荒芜之地", name = "山脊巡行者", level = "36-37", fam = "cat" },
      { zone = "荆棘谷", name = "深喉猎豹", level = "37-38", fam = "cat" },
      { zone = "悲伤沼泽", name = "暗影黑豹", level = "39-40", fam = "cat" },
    } },
    { rank = 2, req = 40, beasts = {
      { zone = "荒芜之地", name = "山脊雄豹", level = "40-41", fam = "cat" },
      { zone = "荆棘谷", name = "老年深喉猎豹", level = "42-43", fam = "cat" },
    } },
    { rank = 3, req = 50, beasts = {
      { zone = "荆棘谷", name = "丛林猎豹", level = "50", fam = "cat" },
      { zone = "冬泉谷", name = "霜刃捕食者", level = "59-60", fam = "cat" },
      { zone = "祖尔格拉布", name = "祖利安雌猎虎", level = "60", fam = "cat" },
    } },
  },
  ["蝎毒"] = {
    { rank = 1, req = 8, beasts = {
      { zone = "杜隆塔尔", name = "毒尾蝎", level = "9-10", fam = "scorpid" },
      { zone = "杜隆塔尔", name = "堕落的蝎", level = "10-11", fam = "scorpid" },
      { zone = "杜隆塔尔", name = "死亡毒蝎", level = "11", fam = "scorpid" },
      { zone = "贫瘠之地", name = "异种爬行者", level = "20-21", fam = "scorpid" },
      { zone = "贫瘠之地", name = "异种群居蝎", level = "21-22", fam = "scorpid" },
    } },
    { rank = 2, req = 24, beasts = {
      { zone = "凄凉之地", name = "荒土巨钳蝎", level = "30-31", fam = "scorpid" },
      { zone = "凄凉之地", name = "荒土鞭尾蝎", level = "34-35", fam = "scorpid" },
      { zone = "凄凉之地", name = "荒土毒尾蝎", level = "38-39", fam = "scorpid" },
      { zone = "千针石林", name = "恐蝎劫掠者", level = "31-32", fam = "scorpid" },
      { zone = "千针石林", name = "恐蝎", level = "33-34", fam = "scorpid" },
      { zone = "千针石林", name = "邪刺恐蝎", level = "35", fam = "scorpid" },
    } },
    { rank = 3, req = 40, beasts = {
      { zone = "塔纳利斯", name = "沙漠猎食蝎", level = "40-41", fam = "scorpid" },
      { zone = "塔纳利斯", name = "沙漠鞭尾蝎", level = "43-44", fam = "scorpid" },
      { zone = "塔纳利斯", name = "沙漠疾行蝎", level = "46-47", fam = "scorpid" },
      { zone = "诅咒之地", name = "厚甲毒刺蝎", level = "50-51", fam = "scorpid" },
      { zone = "燃烧平原", name = "毒尖蝎", level = "52-53", fam = "scorpid" },
      { zone = "燃烧平原", name = "死鞭蝎", level = "54", fam = "scorpid" },
      { zone = "希利苏斯", name = "石鞭蝎", level = "54-55", fam = "scorpid" },
    } },
    { rank = 4, req = 56, beasts = {
      { zone = "燃烧平原", name = "火尾蝎", level = "56-57", fam = "scorpid" },
      { zone = "希利苏斯", name = "石鞭巨钳蝎", level = "56-57", fam = "scorpid" },
      { zone = "希利苏斯", name = "石鞭掠夺者", level = "58-59", fam = "scorpid" },
      { zone = "希利苏斯", name = "克里拉克", level = "56", fam = "scorpid" },
    } },
  },
  ["尖啸"] = {
    { rank = 1, req = 8, beasts = {
      { zone = "西部荒野", name = "大碎尸鸟", level = "16-17", fam = "bird" },
    } },
    { rank = 2, req = 24, beasts = {
      { zone = "千针石林", name = "盐湖秃鹫", level = "32-34", fam = "bird" },
      { zone = "凄凉之地", name = "恐怖撕裂者", level = "39-40", fam = "bird" },
      { zone = "奥达曼副本", name = "利齿蝙蝠", level = "38-39", fam = "bat" },
    } },
    { rank = 3, req = 40, beasts = {
      { zone = "费伍德森林", name = "铁喙猫头鹰", level = "48-49", fam = "owl" },
      { zone = "费伍德森林", name = "智者奥尔姆", level = "52", fam = "owl" },
      { zone = "西瘟疫之地", name = "食腐秃鹫", level = "50-52", fam = "bird" },
    } },
    { rank = 4, req = 56, beasts = {
      { zone = "东瘟疫之地", name = "巨型天灾蝙蝠", level = "56-58", fam = "bat" },
      { zone = "冬泉谷", name = "冬泉鸣枭", level = "57-59", fam = "bird" },
    } },
  },
  ["甲壳护盾"] = {
    { rank = 1, req = 20, beasts = {
      { zone = "黑暗深渊副本", name = "阿库麦尔食鱼龟", level = "23-24", fam = "turtle" },
      { zone = "黑暗深渊副本", name = "加摩拉", level = "25", fam = "turtle" },
      { zone = "希尔斯布莱德丘陵", name = "钳嘴龟", level = "30-31", fam = "turtle" },
      { zone = "辛特兰", name = "铁背龟", level = "51", fam = "turtle" },
      { zone = "哀嚎洞穴副本", name = "克雷什", level = "20", fam = "turtle" },
    } },
  },
  ["雷霆践踏"] = {
    { rank = 1, req = 30, beasts = {
      { zone = "荆棘谷", name = "丛林大猩猩", level = "37-38", fam = "gorilla" },
      { zone = "荆棘谷", name = "迷雾谷猩猩", level = "32-33", fam = "gorilla" },
    } },
    { rank = 2, req = 40, beasts = {
      { zone = "菲拉斯", name = "格罗多克大猩猩", level = "49-50", fam = "gorilla" },
      { zone = "荆棘谷", name = "老迈的迷雾谷猩猩", level = "40-41", fam = "gorilla" },
    } },
    { rank = 3, req = 50, beasts = {
      { zone = "安戈洛环形山", name = "安戈洛猩猩", level = "50-51", fam = "gorilla" },
      { zone = "安戈洛环形山", name = "尤尔查", level = "55", fam = "gorilla" },
    } },
  },
  ["畏缩"] = {
    { rank = 1, req = 5, beasts = {
      { zone = "贫瘠之地", name = "老平原陆行鸟", level = "8-9", fam = "tallstrider" },
      { zone = "贫瘠之地", name = "敏捷的平原陆行鸟", level = "12-13", fam = "tallstrider" },
      { zone = "丹莫罗", name = "雪豹幼崽", level = "5-6", fam = "cat" },
      { zone = "杜隆塔尔", name = "杜隆塔尔猛虎", level = "7-8", fam = "cat" },
      { zone = "黑海岸", name = "森林陆行鸟雏鸟", level = "11-13", fam = "tallstrider" },
      { zone = "黑海岸", name = "月夜猛虎幼崽", level = "10-11", fam = "cat" },
      { zone = "莫高雷", name = "平原狮", level = "7-8", fam = "cat" },
      { zone = "莫高雷", name = "马兹拉纳其", level = "9", fam = "tallstrider" },
      { zone = "泰达希尔", name = "夜刃豹", level = "5-6", fam = "cat" },
    } },
    { rank = 2, req = 15, beasts = {
      { zone = "希尔斯布莱德丘陵", name = "饥饿的山地狮", level = "23-24", fam = "cat" },
      { zone = "贫瘠之地", name = "暴躁的平原陆行鸟", level = "16-17", fam = "tallstrider" },
      { zone = "贫瘠之地", name = "草原狮王", level = "15-16", fam = "cat" },
      { zone = "石爪山脉", name = "夜行虎", level = "23-24", fam = "cat" },
      { zone = "黑海岸", name = "月夜雄虎", level = "17-18", fam = "cat" },
      { zone = "黑海岸", name = "凶猛的森林陆行鸟", level = "17-19", fam = "tallstrider" },
    } },
    { rank = 3, req = 25, beasts = {
      { zone = "希尔斯布莱德丘陵", name = "野生山地狮", level = "27-28", fam = "cat" },
      { zone = "剃刀沼泽副本", name = "盲眼猎手", level = "32", fam = "bat" },
      { zone = "剃刀沼泽副本", name = "沼泽蝙蝠", level = "30-31", fam = "bat" },
      { zone = "千针石林", name = "峭壁捕猎者", level = "25-26", fam = "cat" },
      { zone = "荆棘谷", name = "黑豹", level = "32-33", fam = "cat" },
      { zone = "荆棘谷", name = "猎豹幼崽", level = "30-31", fam = "cat" },
      { zone = "荆棘谷", name = "荆棘谷猛虎幼崽", level = "30-31", fam = "cat" },
    } },
    { rank = 4, req = 35, beasts = {
      { zone = "荒芜之地", name = "山脊巡行者", level = "36-37", fam = "cat" },
      { zone = "荒芜之地", name = "山脊雄豹", level = "38-39", fam = "cat" },
      { zone = "奥达曼副本", name = "利齿蝙蝠", level = "38-39", fam = "bat" },
      { zone = "东瘟疫之地", name = "天灾蝙蝠", level = "53-55", fam = "bat" },
      { zone = "荆棘谷", name = "丛林猎豹", level = "50", fam = "cat" },
    } },
    { rank = 5, req = 45, beasts = {
      { zone = "东瘟疫之地", name = "毒性瘟疫蝙蝠", level = "54-56", fam = "bat" },
    } },
    { rank = 6, req = 55, beasts = {
      { zone = "冬泉谷", name = "幼霜刃豹", level = "55-56", fam = "cat" },
    } },
  },
  ["低吼"] = {
    { rank = 1, req = 10, beasts = {
    } },
    { rank = 2, req = 10, beasts = {
    } },
    { rank = 3, req = 20, beasts = {
    } },
    { rank = 4, req = 30, beasts = {
    } },
    { rank = 5, req = 40, beasts = {
    } },
    { rank = 6, req = 50, beasts = {
    } },
    { rank = 7, req = 60, beasts = {
    } },
  },
  ["持久耐力"] = {
    { rank = 1, req = 10, beasts = {
    } },
    { rank = 2, req = 12, beasts = {
    } },
    { rank = 3, req = 18, beasts = {
    } },
    { rank = 4, req = 24, beasts = {
    } },
    { rank = 5, req = 30, beasts = {
    } },
    { rank = 6, req = 36, beasts = {
    } },
    { rank = 7, req = 42, beasts = {
    } },
    { rank = 8, req = 48, beasts = {
    } },
  },
  ["自然护甲"] = {
    { rank = 1, req = 10, beasts = {
    } },
    { rank = 2, req = 12, beasts = {
    } },
    { rank = 3, req = 18, beasts = {
    } },
    { rank = 4, req = 24, beasts = {
    } },
    { rank = 5, req = 30, beasts = {
    } },
    { rank = 6, req = 36, beasts = {
    } },
    { rank = 7, req = 42, beasts = {
    } },
    { rank = 8, req = 48, beasts = {
    } },
  },
  ["火焰抗性"] = {
    { rank = 1, req = 20, beasts = {
    } },
    { rank = 2, req = 30, beasts = {
    } },
    { rank = 3, req = 40, beasts = {
    } },
    { rank = 4, req = 50, beasts = {
    } },
    { rank = 5, req = 60, beasts = {
    } },
  },
  ["冰霜抗性"] = {
    { rank = 1, req = 20, beasts = {
    } },
    { rank = 2, req = 30, beasts = {
    } },
    { rank = 3, req = 40, beasts = {
    } },
    { rank = 4, req = 50, beasts = {
    } },
    { rank = 5, req = 60, beasts = {
    } },
  },
  ["暗影抗性"] = {
    { rank = 1, req = 20, beasts = {
    } },
    { rank = 2, req = 30, beasts = {
    } },
    { rank = 3, req = 40, beasts = {
    } },
    { rank = 4, req = 50, beasts = {
    } },
    { rank = 5, req = 60, beasts = {
    } },
  },
  ["自然抗性"] = {
    { rank = 1, req = 20, beasts = {
    } },
    { rank = 2, req = 30, beasts = {
    } },
    { rank = 3, req = 40, beasts = {
    } },
    { rank = 4, req = 50, beasts = {
    } },
    { rank = 5, req = 60, beasts = {
    } },
  },
  ["奥术抗性"] = {
    { rank = 1, req = 20, beasts = {
    } },
    { rank = 2, req = 30, beasts = {
    } },
    { rank = 3, req = 40, beasts = {
    } },
    { rank = 4, req = 50, beasts = {
    } },
    { rank = 5, req = 60, beasts = {
    } },
  },
}

-- 家族在数据里的**输出顺序 = 图片行序**（由生成器 FAM_ORDER 生成；界面与探针都读它，不许手写第二份顺序）
EVAL_PET_DB.famOrder = { "cat", "raptor", "bat", "owl", "spider", "windserpent", "gorilla", "crab", "scorpid", "bear", "boar", "turtle", "bird", "crocolisk", "hyena", "tallstrider", "wolf" }

-- ★`skNoJudge` = **不作家族分类判据**的技能（图片的列与驯服来源真冲突；见 gen_petdata.js 的 SK_NO_JUDGE 注释）。
--   闸门按它算「fam 标注与图片的冲突」，所以这份例外**只有一处来源**（改这里就够）。
EVAL_PET_DB.skNoJudge = { "畏缩" }

EVAL_PET_DB.families = {
  cat = { label = "猫科", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Cat_TEX", cname = { "猫", "Cat" },
    dmg = 10, armor = 0, hp = -2, foods = { "鱼", "肉" },
    sk = { dmg = { "撕咬", "爪击" }, spd = { "突进" }, sp = { "潜伏", "畏缩" } } },
  raptor = { label = "迅猛龙", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Raptor_TEX", cname = { "Raptor" },
    dmg = 10, armor = 3, hp = -5, foods = { "肉" },
    sk = { dmg = { "撕咬", "爪击" }, spd = {  }, sp = {  } } },
  bat = { label = "蝙蝠", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Bat_TEX", cname = { "Bat" },
    dmg = 7, armor = 0, hp = 0, foods = { "水果", "蘑菇" },
    sk = { dmg = { "撕咬" }, spd = { "俯冲" }, sp = { "尖啸" } } },
  owl = { label = "猫头鹰", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Owl_TEX", cname = { "枭", "Owl" },
    dmg = 7, armor = 0, hp = 0, foods = { "肉" },
    sk = { dmg = { "爪击" }, spd = { "俯冲" }, sp = { "尖啸" } } },
  spider = { label = "蜘蛛", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Spider_TEX", cname = { "Spider" },
    dmg = 7, armor = 0, hp = 0, foods = { "肉" },
    sk = { dmg = { "撕咬" }, spd = {  }, sp = {  } } },
  windserpent = { label = "风蛇", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_WindSerpent_TEX", cname = { "Wind Serpent", "WindSerpent" },
    dmg = 7, armor = 0, hp = 0, foods = { "面包", "奶酪", "鱼" },
    sk = { dmg = { "撕咬" }, spd = { "俯冲" }, sp = { "闪电吐息" } } },
  gorilla = { label = "猩猩", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Gorilla_TEX", cname = { "Gorilla" },
    dmg = 2, armor = 0, hp = 4, foods = { "水果", "蘑菇" },
    sk = { dmg = { "撕咬" }, spd = {  }, sp = { "雷霆践踏" } } },
  crab = { label = "螃蟹", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Crab_TEX", cname = { "蟹", "Crab" },
    dmg = -5, armor = 13, hp = -4, foods = { "面包", "鱼", "水果", "蘑菇" },
    sk = { dmg = { "爪击" }, spd = {  }, sp = {  } } },
  scorpid = { label = "蝎子", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Scorpid_TEX", cname = { "蝎", "Scorpid" },
    dmg = -6, armor = 10, hp = 0, foods = { "肉" },
    sk = { dmg = { "爪击" }, spd = {  }, sp = { "蝎毒" } } },
  bear = { label = "熊", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Bear_TEX", cname = { "Bear" },
    dmg = -9, armor = 5, hp = 8, foods = { "面包", "奶酪", "鱼", "水果", "蘑菇", "肉" },
    sk = { dmg = { "撕咬", "爪击" }, spd = {  }, sp = {  } } },
  boar = { label = "猪", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Boar_TEX", cname = { "野猪", "Boar" },
    dmg = -10, armor = 9, hp = 4, foods = { "面包", "奶酪", "鱼", "水果", "蘑菇", "肉" },
    sk = { dmg = { "撕咬" }, spd = { "突进" }, sp = { "冲锋" } } },
  turtle = { label = "乌龟", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Turtle_TEX", cname = { "龟", "Turtle" },
    dmg = -10, armor = 13, hp = 0, foods = { "鱼", "水果", "蘑菇" },
    sk = { dmg = { "撕咬" }, spd = {  }, sp = { "甲壳护盾" } } },
  bird = { label = "食腐鸟", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Vulture_TEX", cname = { "鸟类", "Carrion Bird" },
    dmg = 0, armor = 5, hp = 0, foods = { "鱼", "肉" },
    sk = { dmg = { "撕咬", "爪击" }, spd = { "俯冲" }, sp = { "尖啸" } } },
  crocolisk = { label = "鳄鱼", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Crocolisk_TEX", cname = { "Crocolisk" },
    dmg = 0, armor = 10, hp = -5, foods = { "鱼", "肉" },
    sk = { dmg = { "撕咬" }, spd = {  }, sp = {  } } },
  hyena = { label = "土狼", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Hyena_TEX", cname = { "鬣狗", "Hyena" },
    dmg = 0, armor = 5, hp = 0, foods = { "水果", "肉" },
    sk = { dmg = { "撕咬" }, spd = { "突进" }, sp = {  } } },
  tallstrider = { label = "陆行鸟", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_TallStrider_TEX", cname = { "Tallstrider" },
    dmg = 0, armor = 0, hp = 5, foods = { "奶酪", "水果", "蘑菇" },
    sk = { dmg = { "撕咬" }, spd = { "突进" }, sp = {  } } },
  wolf = { label = "狼", icon = "/Game/Interface/Icons/Ability_Hunter_Pet_Wolf_TEX", cname = { "Wolf" },
    dmg = 0, armor = 5, hp = 0, foods = { "肉" },
    sk = { dmg = { "撕咬" }, spd = { "突进" }, sp = { "嚎叫" } } },
  other = { label = "其他", icon = "/Game/Interface/Icons/Ability_Hunter_BeastCall_TEX" },
}

return EVAL_PET_DB