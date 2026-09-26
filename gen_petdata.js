const fs = require('fs');
const NL = String.fromCharCode(10);
const Q = String.fromCharCode(34);
const src = fs.readFileSync('doc/宠物技能数据.lua', 'utf8').split(/\r?\n/);
const META = {
  '撕咬': ['bite','sk_bite',35,'瞬发','5码','10秒','主动','撕咬目标，宠物最基础的伤害技能'],
  '爪击': ['claw','sk_claw',25,'瞬发','5码','无','主动','快速爪击，无冷却但消耗集中值'],
  '突进': ['dash','sk_dash',20,'瞬发','—','30秒','主动','短时间大幅提升移动速度，追击或脱离用'],
  '俯冲': ['dive','sk_dive',20,'瞬发','—','30秒','主动','飞行系宠物的冲刺，效果同突进'],
  '冲锋': ['charge','sk_charge',35,'瞬发','8-25码','25秒','主动','冲锋并定身目标，下一次攻击附加伤害'],
  '嚎叫': ['howl','sk_howl',60,'瞬发','15码','10秒','主动','为队友的下一次攻击附加伤害'],
  '闪电吐息': ['lightning','sk_lightning',50,'瞬发','20码','无','主动','远程自然伤害，风蛇专属'],
  '潜伏': ['prowl','sk_prowl',40,'瞬发','—','10秒','主动','进入潜行，下一次攻击获得额外伤害'],
  '蝎毒': ['scorpid','sk_scorpid',30,'瞬发','—','4秒','主动','持续自然伤害，可叠加5次'],
  '尖啸': ['screech','sk_screech',20,'瞬发','8码','4秒','主动','降低范围内敌人的攻击强度'],
  '甲壳护盾': ['shell','sk_shell',10,'瞬发','—','180秒','主动','降低受到的伤害，代价是攻击间隔变长'],
  '雷霆践踏': ['thunder','sk_thunder',60,'瞬发','8码','60秒','主动','范围自然伤害，猩猩专属'],
  '畏缩': ['cower','sk_cower',25,'瞬发','5码','5秒','主动','降低仇恨值（与低吼共享冷却）'],
  '低吼': ['growl','sk_growl',15,'瞬发','5码','5秒','被动-训练师','提高仇恨，宠物坦克核心（训练师学习）'],
  '持久耐力': ['stamina','sk_stamina',0,'被动','—','—','被动-训练师','提高宠物耐力（训练师学习）'],
  '自然护甲': ['natarmor','sk_natarmor',0,'被动','—','—','被动-训练师','提高宠物护甲（训练师学习）'],
  '火焰抗性': ['fireres','sk_fireres',0,'被动','—','—','被动-训练师','提高火焰抗性（训练师学习）'],
  '冰霜抗性': ['frostres','sk_frostres',0,'被动','—','—','被动-训练师','提高冰霜抗性（训练师学习）'],
  '暗影抗性': ['shadowres','sk_shadowres',0,'被动','—','—','被动-训练师','提高暗影抗性（训练师学习）'],
  '自然抗性': ['natureres','sk_natureres',0,'被动','—','—','被动-训练师','提高自然抗性（训练师学习）'],
  '奥术抗性': ['arcaneres','sk_arcaneres',0,'被动','—','—','被动-训练师','提高奥术抗性（训练师学习）'],
};
// ★★★1.75.3 家族**显示名**改按图片用名（doc/猎人宠物属性和技能图.jpg → doc/猎人宠物家族属性.md）：
//   蟹→螃蟹 · 蝎→蝎子 · 龟→乌龟 · 枭→猫头鹰 · 鸟类→食腐鸟 · 野猪→猪。
//   为什么要改：家族卡的「标题」与「客户端家族名对账」都以此为准（单一来源 = 图片），
//   旧短名与英文名一律进 `cname`（客户端 UnitCreatureFamily 返回值形态**待真机探针定案**，多列一个候选不伤人）。
//   ★★★keyword 表（第 3 列）本轮**按图片重标家族时一并修正**（用户：「以最新的图片为准」）：
//     · spider 补 `蛛`（覆盖「猎行蛛」）、删 `撕裂者`（凄凉之地「恐怖撕裂者」其实是食腐鸟，旧标注就是它带歪的）；
//     · scorpid 删 `科拉克`（掠夺者科拉克教撕咬+爪击，不是蝎）；
//     · wolf 补 `猎犬`；hyena/raptor 补上土狼系与迅猛龙的关键字（上一版故意留空，现已能判）。
//   ★**匹配规则改为「候选家族内、最长关键字优先」**（旧版是「FAM 顺序里谁先命中」⇒ `狼` 抢走「狼蛛」）。
const FAM = [
  ['wolf','狼',['狼','座狼','猎犬']],
  ['spider','蜘蛛',['蜘蛛','狼蛛','蛛','结网蛛','食苔蛛','爬行者','独行蛛','贝瑟莱斯','雷克提拉克','拉克西斯']],
  ['cat','猫科',['豹','虎','狮','捕食者','潜行者','巡行者','霜刃','猛虎','战虎','猎虎','巴尔瑟拉','辛达尔','断牙','拉克西里','月夜']],
  ['bear','熊',['熊']],
  ['boar','猪',['野猪','斗猪','山猪','阿迦玛','格朗特','公主']],
  ['crab','螃蟹',['蟹']],
  ['turtle','乌龟',['龟','克雷什','加摩拉','阿库麦尔']],
  ['crocolisk','鳄鱼',['鳄']],
  ['bat','蝙蝠',['蝙蝠','盲眼猎手']],
  ['bird','食腐鸟',['秃鹫','碎尸鸟','大鹏','火鹏','斯比弗雷尔','扎里科特','尖啸者','雷鹰']],
  ['owl','猫头鹰',['枭','猫头鹰','奥尔姆']],
  ['gorilla','猩猩',['猩猩','乌卡洛克','尤尔查']],
  ['windserpent','风蛇',['风蛇','飞蛇','哈卡之子']],
  ['scorpid','蝎子',['蝎','萨科斯','克里拉克']],
  ['tallstrider','陆行鸟',['陆行鸟']],
  ['raptor','迅猛龙',['迅猛龙']],
  ['hyena','土狼',['土狼','疱爪','骨爪','鬣狗']],
];

// ★★家族在数据表里的**输出顺序 = 图片行序**（doc/猎人宠物家族属性.md 的 17 行，raptor 第 2 / hyena 第 15）：
//   探针的「家族属性表」与将来的家族视图都直接按这个顺序列，不另写一份序表（两处顺序 = 两处真值）。
//   ★声明位置必须在 SK_ALLOW（按它现算「技能→允许家族」）**之前**。
const FAM_ORDER = ['cat', 'raptor', 'bat', 'owl', 'spider', 'windserpent', 'gorilla', 'crab', 'scorpid',
                   'bear', 'boar', 'turtle', 'bird', 'crocolisk', 'hyena', 'tallstrider', 'wolf'];

// ===== 家族基础属性（图片逐行转录：伤害/护甲/生命加成 + 食物 + 天生技能三列）=====
// ★来源：doc/猎人宠物属性和技能图.jpg（用户提供）→ doc/猎人宠物家族属性.md（转录 + 与现有 fam 标注的对账）。
// ★字段口径：
//   · dmg/armor/hp = 相对标准宠物的**百分比修正**；图里写「-」= 无加成 ⇒ 这里写 **0**
//     （★`other` 家族**不给这三个字段** ⇒ 界面/探针读不到就该说「未收录」，绝不当成 0）。
//   · foods = 可吃食物类（六类：面包 / 奶酪 / 鱼 / 水果 / 蘑菇 / 肉）；探测命令的闸门会逐条核对它在这个集合内。
//   · sk = 该家族**天生会**的技能，三列对应图片的 伤害技能 / 加速技能 / 特殊技能；
//     技能名必须存在于 `skills` 表（PetFamily.js 闸门逐条核对 —— 写野名字当场 FAIL）。
//     ★★狼的「特殊技能」图里写作**狂怒之嚎**：用户 2026-09-25 定案「**同个**」（与 skills 表里的「嚎叫」是同一技能两名）
//       ⇒ 这里**只写本插件用名** `嚎叫`（一个技能一个名字），别名关系记在 doc/猎人宠物家族属性.md 与项目记忆里。
//   · cname = 客户端 `UnitCreatureFamily(unit)` **可能**给出的名字（本地化名，用于把客户端真值对回 id）。
//     ★这是**匹配候选**不是判据：多列一个只会「多认出一个」，认不出时探针**如实打原文**（绝不猜）。
//     真机返回值形态待 `/eh go 宠物家族` 定案。label 自身由匹配器自动接受，不必在 cname 里重复。
const FAM_STATS = {
  cat:         { dmg: 10,  armor: 0,  hp: -2, foods: ['鱼','肉'],                        sk: { dmg: ['撕咬','爪击'], spd: ['突进'], sp: ['潜伏','畏缩'] }, cname: ['猫','Cat'] },
  raptor:      { dmg: 10,  armor: 3,  hp: -5, foods: ['肉'],                             sk: { dmg: ['撕咬','爪击'], spd: [],       sp: [] },            cname: ['Raptor'] },
  bat:         { dmg: 7,   armor: 0,  hp: 0,  foods: ['水果','蘑菇'],                    sk: { dmg: ['撕咬'],        spd: ['俯冲'], sp: ['尖啸'] },      cname: ['Bat'] },
  owl:         { dmg: 7,   armor: 0,  hp: 0,  foods: ['肉'],                             sk: { dmg: ['爪击'],        spd: ['俯冲'], sp: ['尖啸'] },      cname: ['枭','Owl'] },
  spider:      { dmg: 7,   armor: 0,  hp: 0,  foods: ['肉'],                             sk: { dmg: ['撕咬'],        spd: [],       sp: [] },            cname: ['Spider'] },
  windserpent: { dmg: 7,   armor: 0,  hp: 0,  foods: ['面包','奶酪','鱼'],                sk: { dmg: ['撕咬'],        spd: ['俯冲'], sp: ['闪电吐息'] },  cname: ['Wind Serpent','WindSerpent'] },
  gorilla:     { dmg: 2,   armor: 0,  hp: 4,  foods: ['水果','蘑菇'],                    sk: { dmg: ['撕咬'],        spd: [],       sp: ['雷霆践踏'] },  cname: ['Gorilla'] },
  crab:        { dmg: -5,  armor: 13, hp: -4, foods: ['面包','鱼','水果','蘑菇'],         sk: { dmg: ['爪击'],        spd: [],       sp: [] },            cname: ['蟹','Crab'] },
  scorpid:     { dmg: -6,  armor: 10, hp: 0,  foods: ['肉'],                             sk: { dmg: ['爪击'],        spd: [],       sp: ['蝎毒'] },      cname: ['蝎','Scorpid'] },
  bear:        { dmg: -9,  armor: 5,  hp: 8,  foods: ['面包','奶酪','鱼','水果','蘑菇','肉'], sk: { dmg: ['撕咬','爪击'], spd: [],     sp: [] },            cname: ['Bear'] },
  boar:        { dmg: -10, armor: 9,  hp: 4,  foods: ['面包','奶酪','鱼','水果','蘑菇','肉'], sk: { dmg: ['撕咬'],      spd: ['突进'], sp: ['冲锋'] },      cname: ['野猪','Boar'] },
  turtle:      { dmg: -10, armor: 13, hp: 0,  foods: ['鱼','水果','蘑菇'],                sk: { dmg: ['撕咬'],        spd: [],       sp: ['甲壳护盾'] },  cname: ['龟','Turtle'] },
  bird:        { dmg: 0,   armor: 5,  hp: 0,  foods: ['鱼','肉'],                        sk: { dmg: ['撕咬','爪击'], spd: ['俯冲'], sp: ['尖啸'] },      cname: ['鸟类','Carrion Bird'] },
  crocolisk:   { dmg: 0,   armor: 10, hp: -5, foods: ['鱼','肉'],                        sk: { dmg: ['撕咬'],        spd: [],       sp: [] },            cname: ['Crocolisk'] },
  hyena:       { dmg: 0,   armor: 5,  hp: 0,  foods: ['水果','肉'],                      sk: { dmg: ['撕咬'],        spd: ['突进'], sp: [] },            cname: ['鬣狗','Hyena'] },
  tallstrider: { dmg: 0,   armor: 0,  hp: 5,  foods: ['奶酪','水果','蘑菇'],              sk: { dmg: ['撕咬'],        spd: ['突进'], sp: [] },            cname: ['Tallstrider'] },
  wolf:        { dmg: 0,   armor: 5,  hp: 0,  foods: ['肉'],                             sk: { dmg: ['撕咬'],        spd: ['突进'], sp: ['嚎叫'] },      cname: ['Wolf'] },
};
// ===== 野兽 → 家族 的定案（1.75.3 第二轮；用户 2026-09-25 明确定：「64 条 fam 冲突逐条定案 → **以最新的图片为准**」）=====
// 定案优先级（**图片优先**，名字只用来消歧；绝不再靠「哪个关键字先命中」）：
//   ⓪ **用户点名定案**（`FAM_USER`，最高优先级；用户逐只给出的，不参与推断）
//   ① **技能交集唯一** ⇒ 图片直接定案（图片的三列技能 = 该家族会什么：教「嚎叫」的只能是狼、
//      教「闪电吐息」的只能是风蛇、同教会「撕咬+爪击+俯冲+尖啸」的只有食腐鸟…）
//   ② 名字关键字消歧 —— **只在①给出的候选家族里找**，且**最长匹配优先**
//      （★修 1.73.0 的老 bug：FAM 表里 wolf 排在 spider 前、`狼` 先命中 ⇒「狼蛛/平原狼蛛/死亡狼蛛」全被标成狼）
//   ③ 显式覆写表 `FAM_OVERRIDE`（同系列兄弟 / 知名命名怪；每行都写理由，真机探针可复核）
//   ④ 名字**硬证据**（名字里直接写着家族名词，如「…鳄鱼」「…蛛」）——与图片技能列冲突时**记进 image-exception**
//   ⑤ 其余**如实落 `other`**（图片给不出信号、候选多义 ⇒ 绝不猜）
//   ★实测（1.75.3 收尾）：**237 只唯一名全部定案、`other` 归零**；与图片冲突只剩 3 条例外（名字硬证据 2 条 + 用户定案 1 条）。
// ★**非判据技能**：图片只把「畏缩」列在猫科，而 12 条驯服来源（陆行鸟/蝙蝠/枭/熊…）都教畏缩 ⇒
//   这一列与来源表真冲突、以图片为准会得出「陆行鸟是猫」这种荒谬结论 ⇒ **排除出分类判据**（另记为图-数据冲突，探针可定案）。
//   ★生成物里会带出 `skNoJudge`，闸门（PetFamily.js）读它 —— 免得两处各写一份例外清单。
const SK_NO_JUDGE = ['畏缩'];
// ⓪ **用户点名定案**（最高优先级；用户 2026-09-25 逐只给出，不参与推断、直接采纳）
//    ★副作用（已如实记账）：`癞爪 → 狼` 与图片的**狼列**冲突（它教「爪击3」，而图片里狼只有撕咬）
//      ⇒ 会进 image-exception（闸门逐字冻结）；`峭壁捕猎者` 只会畏缩（非判据技能）⇒ 图片本来给不出信号，按用户定案。
const FAM_USER = {
  '邪恶的基塞伊斯': 'cat',    // C1 泰达希尔(5) 撕咬1
  '森林潜伏者': 'spider',     // C2 洛克莫丹(10-11) 撕咬2
  '林木潜伏者': 'spider',     // C3 洛克莫丹(17-18) 撕咬3
  '野棘潜伏者': 'spider',     // C4 灰谷(28-29) 撕咬4
  '林木隐匿者': 'spider',     // C5 艾萨拉(47-48) 撕咬6
  '巴纳布斯': 'cat',          // C6 荒芜之地(39) 撕咬6
  '瘟疫潜伏者': 'spider',     // C7 西瘟疫之地(54-55) 撕咬7
  '癞爪': 'wolf',             // C8 丹莫罗(11) 爪击3 ← 与图片狼列冲突（记为第 3 条例外）
  '海崖奔跳者': 'wolf',       // C9 辛特兰(42) 突进2
  '峭壁捕猎者': 'cat',        // C10 千针石林(25-26) 畏缩3
};
// 技能 → 允许的家族集合（从 FAM_STATS 的**三列技能**现算，不手写第二份）
const SK_ALLOW = (() => {
  const m = {};
  for (const id of FAM_ORDER) for (const g of ['dmg','spd','sp']) for (const sk of FAM_STATS[id].sk[g]) (m[sk] = m[sk] || {})[id] = 1;
  return m;
})();
// 显式覆写（第 ③ 步）：**每条都要有理由**，且必须落在①的候选集合内（否则说明理由本身与图片矛盾）
const FAM_OVERRIDE = {
  '山狗': 'wolf', '峭壁山狗': 'wolf',            // 同系列「山狗首领 / 老峭壁山狗」教嚎叫 ⇒ 图片判为狼
  '幽爪奔跑者': 'wolf',                          // 同系列「幽爪前锋」教嚎叫
  '黑色破坏者': 'wolf',                          // 同系列「巨型黑色破坏者」教嚎叫
  '咆哮者': 'wolf', '魔爪掠夺者': 'wolf',         // 同系列「长牙奔跑者 / 长牙嚎叫者 / 魔爪狼」教嚎叫
  '银鬃捕猎者': 'wolf',                          // 同系列「银鬃狼 / 银鬃嗥狼」教嚎叫
  '鲁伯斯': 'wolf',                              // 知名命名怪（暮色森林）：vanilla 为狼
  '奥尔苏迪': 'bear',                            // 知名命名怪（洛克莫丹）：vanilla 为熊
  '铁喙狩猎者': 'owl',                           // 同系列「铁喙猫头鹰」= 猫头鹰
  '掠夺者科拉克': 'bird',                        // 教撕咬+爪击；候选里按命名怪（诅咒之地）为食腐鸟
  '恐怖撕裂者': 'bird', '恐怖飞鸟': 'bird',       // 凄凉之地「恐怖」系列 = 食腐鸟（旧标 spider 来自已删的 '撕裂者' 关键字）
  '暗牙潜伏者': 'spider',                        // 同系列「暗牙蜘蛛 / 暗牙爬行者」均蜘蛛
  '马兹拉纳其': 'tallstrider',                   // 知名命名怪（莫高雷）：vanilla 为陆行鸟
  '盲眼猎手': 'bat',                             // 剃刀沼泽命名怪：蝙蝠
};
// 名字 → 家族：候选内、**最长关键字**优先（同长按 FAM 顺序）；cand 为 null = 不限候选
function famByName(name, cand) {
  let best = null, bestLen = 0;
  for (const f of FAM) {
    if (cand && cand.indexOf(f[0]) < 0) continue;
    for (const kw of f[2]) {
      if (name.indexOf(kw) >= 0 && kw.length > bestLen) { best = f[0]; bestLen = kw.length; }
    }
  }
  return best;
}
// 每只野兽教哪些技能（第二遍才能拿到 ⇒ 先收集）
let beastSkills = null;
function classifyBeast(name) {
  const skSet = (beastSkills && beastSkills[name]) || {};
  let cand = null; const used = [];
  for (const sk of Object.keys(skSet)) {
    if (SK_NO_JUDGE.indexOf(sk) >= 0) continue;
    const allow = SK_ALLOW[sk];
    if (!allow) continue;              // 图片三列里没有的技能（训练师技能等）不作判据
    used.push(sk);
    cand = (cand === null) ? Object.keys(allow) : cand.filter(id => allow[id]);
  }
  if (FAM_USER[name]) return { fam: FAM_USER[name], how: '用户定案', used, cand };
  if (cand !== null && cand.length === 0) return { fam: 'other', how: '矛盾(技能交集为空)', used, cand };
  if (cand && cand.length === 1) return { fam: cand[0], how: '图片技能', used, cand };
  const nm2 = famByName(name, cand);
  if (nm2) return { fam: nm2, how: '图片技能+名字', used, cand };
  if (FAM_OVERRIDE[name]) return { fam: FAM_OVERRIDE[name], how: '覆写', used, cand };
  const nm4 = famByName(name, null);
  if (nm4) return { fam: nm4, how: '名字硬证据(与图片冲突,记例外)', used, cand };
  return { fam: 'other', how: '无从判定(留 other)', used, cand };
}
const skills = []; const rankMap = new Map();
let curSkill = null; let curRank = null;
for (const raw of src) {
  const line = raw.replace(/\r$/, '');
  let m = line.match(/^\s*\{ name = "([^"]+)", cost = (\d+)/);
  if (m) { skills.push(m[1]); continue; }
  m = line.match(/^\s*\["([^"]+)"\] = \{$/);
  if (m) { curSkill = m[1]; rankMap.set(curSkill, []); continue; }
  m = line.match(/^\s*\{ rank = (\d+), reqPetLevel = (\d+), beasts = \{$/);
  if (m) { curRank = { rank: parseInt(m[1],10), req: parseInt(m[2],10), beasts: [] }; rankMap.get(curSkill).push(curRank); continue; }
  m = line.match(/^\s*\{ zone = "([^"]*)", name = "([^"]*)", level = "([^"]*)" \},$/);
  if (m && curRank) { curRank.beasts.push({ zone: m[1], name: m[2], level: m[3], fam: 'other' }); continue; }
}
// 第二遍：收集「野兽 → 教的技能」→ 定案家族 → 回写
beastSkills = {};
for (const name of skills) for (const r of (rankMap.get(name) || [])) for (const b of r.beasts) {
  (beastSkills[b.name] = beastSkills[b.name] || {})[name] = 1;
}
const famDecided = {}, famHow = {}, retag = [], imgExcept = {}, nameLost = [];
for (const name of skills) for (const r of (rankMap.get(name) || [])) for (const b of r.beasts) {
  if (!famDecided[b.name]) {
    const d = classifyBeast(b.name);
    famDecided[b.name] = d.fam; famHow[b.name] = d.how;
    // 名字指向的家族被判掉的情况（供文档/复核；例：冬泉鸣枭 名字含「枭」而图片判食腐鸟）
    const byName = famByName(b.name, null);
    if (byName && byName !== d.fam && d.how.indexOf('名字硬证据') < 0 && d.how !== '用户定案') {
      nameLost.push(b.name + '：名字像 ' + byName + ' → 判 ' + d.fam + '（' + d.how + '）');
    }
  }
  b.fam = famDecided[b.name];
  retag.push({ name: b.name, fam: b.fam, how: famHow[b.name] });
  // ★image-exception **按最终数据算**（不看 `how`）—— 这样「用户定案」引入的冲突（癞爪→狼）也跑不掉，
  //   而闸门 PetFamily.js 用的正是同一口径（它读生成物），两边永远一致。
  if (b.fam !== 'other' && SK_NO_JUDGE.indexOf(name) < 0 && SK_ALLOW[name] && !SK_ALLOW[name][b.fam]) {
    imgExcept[name + ' ← ' + b.name + '（' + famHow[b.name] + '）'] = 1;
  }
}
const uniqueRetag = [...new Set(retag.map(r => r.name + '|' + r.fam + '|' + r.how))];
const famDist = {};
for (const r of retag) famDist[r.fam] = (famDist[r.fam] || 0) + 1;
console.log('家族定案：' + Object.keys(famDecided).length + ' 只唯一名 → ' + JSON.stringify(
  Object.keys(famHow).reduce((a, k) => { const h = famHow[k]; a[h] = (a[h] || 0) + 1; return a; }, {})));
console.log('家族分布（按条目）：' + Object.keys(famDist).sort((a, b) => famDist[b] - famDist[a]).map(k => k + '=' + famDist[k]).join(' '));
const exceptList = Object.keys(imgExcept);
if (exceptList.length) console.log('★image-exception（与图片冲突，闸门逐字冻结）：\n   ' + exceptList.join('\n   '));
if (nameLost.length) console.log('☆名字被图片判掉（复核清单）：\n   ' + nameLost.join('\n   '));
const leftOther = Object.keys(famDecided).filter(k => famDecided[k] === 'other');
console.log('仍留 other（' + leftOther.length + ' 只）：' + (leftOther.join('、') || '（无 —— 全部定案）'));
void uniqueRetag;
const out = [];
// ★★★1.73.4 图标全部换成**客户端真实路径**（用户要求：「完善宠物助手tab 内所有图标替换，先根据语义从系统图标文件内自己匹配对应语义相似的图标」）。
//   ★本客户端的纹理路径是 **Unreal 资产路径**：/Game/Interface/Icons/<名字>_TEX
//     —— 不是 1.12 的 Interface\Icons\<名字>（那种写法在这个客户端会显示成引擎的「?」缺图占位，
//     就是用户截图里那一屏问号的来源）。
//   ★下面每个名字都来自游戏内采集的清单（/eh go icons → doc/图标路径清单.txt，1018 条），
//     由 test_engine.js 的 PET ICON CHECK **逐条精确核对存在性**——写错一个当场 FAIL。
const ICONPREFIX = '/Game/Interface/Icons/';
const ICONSUFFIX = '_TEX';
const iconPath = n => ICONPREFIX + n + ICONSUFFIX;
// ★★★1.75.3（用户指定）**技能图标改用宏图标号**（用户原话：「宠物技能图标调整: 撕咬->宏图标139 · 爪击->255 ·
//   嚎叫->695 · 冲锋->700 · 甲壳护盾->710（原话「夹克护盾」=笔误）· 暗影抗性->133」）：
//   · 号的来源 = 插件**图标库（Tab5）悬停提示里的「宏图标序号：N」**（`IconBrowser.lua` 的 `it.idx`，由
//     `GetMacroIconInfo(i)` 实时枚举得到）⇒ 语义 = **宏图标表下标**，不是清单行号。
//   · ★★★**为什么不能离线把号翻译成路径**：`doc/图标路径清单.txt` 是**按字母排序**的白名单（1018 条相邻全有序），
//     而客户端的宏图标表**不是字母序**（先例：DF 的 346 号在客户端是 `INV_Misc_Fish_20`，而清单里 Fish_20 在第 342 条、
//     第 346 条是 `INV_Misc_Flower_02`）⇒ **行号 ≠ 号**，离线查表必然拿错图。
//   ⇒ 所以：**号进数据（`iconIdx`），纹理运行期解析**（`GetMacroIconInfo(号)`，PetHelper 的 `EVAL_PH_SKILL_ICON`）；
//     `icon`（下面 SKILL_ICON 那套语义路径）**保留为兜底** —— 接口不在/越界/空时用它，绝不去编一个路径。
const SKILL_ICON_IDX = {
  bite: 139,       // 撕咬
  claw: 255,       // 爪击
  howl: 695,       // 嚎叫
  charge: 700,     // 冲锋
  shell: 710,      // 甲壳护盾
  shadowres: 133,  // 暗影抗性
};
// 技能图标（**兜底**用）：按语义挑（撕咬=獠牙、爪击=爪、突进=疾跑、低吼=嘲讽、抗性=对应抗性图腾…）
// ★★★1.75.9 **兜底已换成「客户端真值」**（用户跑 `/eh go 图标号` 的读数，见 doc/宠物技能数据.md 的图标表）：
//   兜底只在「GetMacroIconInfo 接口不在 / 号越界 / 返回空」时用；换成真值后，即使接口失效，界面显示的**仍是用户选的那枚图**。
//   条数、语义都对得上（爪击=Rake 撕抓 · 冲锋=野猪冲锋 · 嚎叫=狼头 · 甲壳护盾=龟壳 · 撕咬=啃咬 · 暗影抗性=暗影之印）。
const SKILL_ICON = {
  bite:      'Ability_Racial_Cannibalize',        // ★真值（139 号）
  claw:      'Ability_Druid_Rake',                // ★真值（255 号）
  dash:      'Ability_Druid_Dash',                // 疾跑 = 突进
  dive:      'INV_Feather_01',                    // 羽毛 = 俯冲（飞行冲刺）
  charge:    'Ability_Hunter_Pet_Boar',           // ★真值（700 号）
  howl:      'Ability_Hunter_Pet_Wolf',           // ★真值（695 号）
  lightning: 'Spell_Nature_Lightning',            // 闪电 = 闪电吐息
  prowl:     'Ability_Stealth',                   // 潜行 = 潜伏
  scorpid:   'Ability_PoisonSting',               // 毒刺 = 蝎毒
  screech:   'Spell_Shadow_PsychicScream',        // 尖啸
  shell:     'Ability_Hunter_Pet_Turtle',         // ★真值（710 号）
  thunder:   'Ability_ThunderClap',               // 雷霆践踏
  cower:     'Ability_Druid_Cower',               // 畏缩
  growl:     'Ability_Physical_Taunt',            // 嘲讽 = 低吼（提高仇恨）
  stamina:   'Spell_Nature_UnyeildingStamina',    // 耐力
  natarmor:  'Spell_Nature_SpiritArmor',          // 护甲（自然）
  fireres:   'Spell_FireResistanceTotem_01',      // 火抗图腾
  frostres:  'Spell_Fire_FrostResistanceTotem',   // 冰抗图腾
  shadowres: 'Spell_Shadow_SealOfKings',          // ★真值（133 号）
  natureres: 'Spell_Nature_NatureResistanceTotem',// 自然抗性图腾
  arcaneres: 'Spell_Arcane_ArcaneResilience',     // 奥术抗性
};
// 家族图标：客户端自带一整套 **Ability_Hunter_Pet_***（一一对应，不撞图；raptor/hyena 也在清单里）
const FAM_ICON = {
  wolf: 'Ability_Hunter_Pet_Wolf', cat: 'Ability_Hunter_Pet_Cat', bear: 'Ability_Hunter_Pet_Bear',
  boar: 'Ability_Hunter_Pet_Boar', crab: 'Ability_Hunter_Pet_Crab', turtle: 'Ability_Hunter_Pet_Turtle',
  crocolisk: 'Ability_Hunter_Pet_Crocolisk', bat: 'Ability_Hunter_Pet_Bat', bird: 'Ability_Hunter_Pet_Vulture',
  owl: 'Ability_Hunter_Pet_Owl', gorilla: 'Ability_Hunter_Pet_Gorilla', windserpent: 'Ability_Hunter_Pet_WindSerpent',
  scorpid: 'Ability_Hunter_Pet_Scorpid', tallstrider: 'Ability_Hunter_Pet_TallStrider',
  spider: 'Ability_Hunter_Pet_Spider', raptor: 'Ability_Hunter_Pet_Raptor',
  hyena: 'Ability_Hunter_Pet_Hyena', other: 'Ability_Hunter_BeastCall',
};
// ★★家族在数据表里的**输出顺序 = 图片行序**（doc/猎人宠物家族属性.md 的 17 行）—— 声明已提前到 FAM 表之后
//   （SK_ALLOW 要按它现算；见上方 FAM_ORDER）
out.push('-- EvalHelp · PetData.lua —— 猎人宠物数据（1.73.0 独立载入）');
out.push('-- ★★★本文件是**生成物**（生成器 = 仓库根目录 gen_petdata.js，数据源 = doc/宠物技能数据.lua + 本生成器里的家族属性表）：');
out.push('--   **绝不手改本文件** —— 改数据请改生成器再跑 `node gen_petdata.js`，否则下次生成会把手改冲掉。');
out.push('-- 数据来源：① 宠物技能总表截图（doc/pet_info.png）② 家族基础属性表截图（doc/猎人宠物属性和技能图.jpg，转录见 doc/猎人宠物家族属性.md）。');
out.push('-- 结构：skills（技能定义+图标）/ ranks[技能名]（各等级：需求宠物等级 + 驯服来源野兽 + fam）/ families（家族 id → 名称+图标+三加成+食物+天生技能+客户端家族名候选）/ famOrder（图片行序）。');
out.push('-- ★★fam（野兽→家族）按**图片的「家族→技能」三列**定案（用户 2026-09-25：「以最新的图片为准」）：');
out.push('--   ① 技能交集唯一 ⇒ 图片直接定案 ② 名字关键字（只在候选内、最长匹配优先，修了「狼蛛被当狼」的老 bug）');
out.push('--   ③ 显式覆写（同系列兄弟/知名命名怪，见生成器 FAM_OVERRIDE 与理由）④ 名字硬证据（…鳄鱼/…蛛）⑤ 其余如实 other。');
out.push('--   ★`skNoJudge` = 不作判据的技能（图片列与来源表真冲突）；闸门读它，例外清单只有这一处来源。');
out.push('-- 图标：**本客户端真实纹理路径**（/Game/Interface/Icons/<名字>_TEX，Unreal 资产路径）——取自 doc/图标路径清单.txt，由 PET ICON CHECK 逐条核对存在性；★1.12 的 Interface\\Icons\\ 写法在本客户端只显示成引擎的「?」缺图占位。');
out.push('');
out.push('EVAL_PET_DB = {}');
out.push('');
out.push('EVAL_PET_DB.skills = {');
for (const name of skills) {
  const m = META[name];
  if (!m) continue;
  // ★有宏图标号的技能：号进数据（运行期解析纹理）；`icon` 仍是**兜底**（取不到号时用，绝不编路径）
  const idx = SKILL_ICON_IDX[m[0]];
  out.push('  { id = ' + Q + m[0] + Q + ', name = ' + Q + name + Q + ', cost = ' + m[2] + ', cast = ' + Q + m[3] + Q + ', range = ' + Q + m[4] + Q + ', cd = ' + Q + m[5] + Q + ', kind = ' + Q + m[6] + Q + ', intro = ' + Q + m[7] + Q + ', icon = ' + Q + iconPath(SKILL_ICON[m[0]]) + Q +
           (idx ? ', iconIdx = ' + idx : '') + ' },');
}
out.push('}');
out.push('');
// ---- 训练师被动技能：截图里的等级表（需求宠物等级；无驯服来源） ----
const PASSIVE_RANKS = {
  '低吼':     [10,10,20,30,40,50,60],
  '持久耐力': [10,12,18,24,30,36,42,48],
  '自然护甲': [10,12,18,24,30,36,42,48],
  '火焰抗性': [20,30,40,50,60],
  '冰霜抗性': [20,30,40,50,60],
  '暗影抗性': [20,30,40,50,60],
  '自然抗性': [20,30,40,50,60],
  '奥术抗性': [20,30,40,50,60],
};
for (const name of skills) {
  const arr = PASSIVE_RANKS[name];
  if (!arr) continue;
  const list = rankMap.get(name) || [];
  list.length = 0;
  arr.forEach((req, i) => list.push({ rank: i + 1, req: req, beasts: [] }));
  rankMap.set(name, list);
}
out.push('EVAL_PET_DB.ranks = {');
for (const name of skills) {
  const rk = rankMap.get(name) || [];
  out.push('  [' + Q + name + Q + '] = {');
  for (const r of rk) {
    out.push('    { rank = ' + r.rank + ', req = ' + r.req + ', beasts = {');
    for (const b of r.beasts) { out.push('      { zone = ' + Q + b.zone + Q + ', name = ' + Q + b.name + Q + ', level = ' + Q + b.level + Q + ', fam = ' + Q + b.fam + Q + ' },'); }
    out.push('    } },');
  }
  out.push('  },');
}
out.push('}');
out.push('');
out.push('-- 家族在数据里的**输出顺序 = 图片行序**（由生成器 FAM_ORDER 生成；界面与探针都读它，不许手写第二份顺序）');
out.push('EVAL_PET_DB.famOrder = { ' + FAM_ORDER.map(id => Q + id + Q).join(', ') + ' }');
out.push('');
// ★非判据技能（例外清单**只此一份**：生成器写出、闸门 PetFamily.js 读它，免得两处各写一份）
out.push('-- ★`skNoJudge` = **不作家族分类判据**的技能（图片的列与驯服来源真冲突；见 gen_petdata.js 的 SK_NO_JUDGE 注释）。');
out.push('--   闸门按它算「fam 标注与图片的冲突」，所以这份例外**只有一处来源**（改这里就够）。');
out.push('EVAL_PET_DB.skNoJudge = { ' + SK_NO_JUDGE.map(x => Q + x + Q).join(', ') + ' }');
out.push('');
out.push('EVAL_PET_DB.families = {');
// ★生成期自检：图片行序必须与 keyword 表 **逐条一一对应**（少一条/多一条 = 家族表悄悄缺项）
{
  const ids = FAM.map(f => f[0]);
  const missing = ids.filter(id => FAM_ORDER.indexOf(id) < 0);
  const extra = FAM_ORDER.filter(id => ids.indexOf(id) < 0);
  const noStat = FAM_ORDER.filter(id => !FAM_STATS[id]);
  if (missing.length || extra.length || noStat.length) {
    throw new Error('FAM_ORDER 与 FAM/FAM_STATS 不一致：FAM 多出 [' + missing + ']，序表多出 [' + extra + ']，缺属性 [' + noStat + ']');
  }
}
const FAM_BY_ID = {};
for (const f of FAM) FAM_BY_ID[f[0]] = f;
const famLine = (id) => {
  const f = FAM_BY_ID[id], st = FAM_STATS[id];
  const q = (arr) => '{ ' + arr.map(x => Q + x + Q).join(', ') + ' }';
  out.push('  ' + id + ' = { label = ' + Q + f[1] + Q + ', icon = ' + Q + iconPath(FAM_ICON[id]) + Q +
           ', cname = ' + q(st.cname) + ',');
  out.push('    dmg = ' + st.dmg + ', armor = ' + st.armor + ', hp = ' + st.hp + ', foods = ' + q(st.foods) + ',');
  out.push('    sk = { dmg = ' + q(st.sk.dmg) + ', spd = ' + q(st.sk.spd) + ', sp = ' + q(st.sk.sp) + ' } },');
};
for (const id of FAM_ORDER) famLine(id);
// `other` = 现表专有的「未归类」桶：**故意不带 dmg/armor/hp**（读不到 = 未收录，绝不当成 0）
out.push('  other = { label = ' + Q + '其他' + Q + ', icon = ' + Q + iconPath(FAM_ICON.other) + Q + ' },');
out.push('}');
out.push('');

out.push('return EVAL_PET_DB');
fs.writeFileSync('PetData.lua', out.join(NL));
const bc = [...rankMap.values()].reduce((a, r) => a + r.reduce((x, y) => x + y.beasts.length, 0), 0);
console.log('skills=' + skills.length + ' beasts=' + bc + ' families=' + (FAM_ORDER.length + 1) + ' lines=' + out.length);