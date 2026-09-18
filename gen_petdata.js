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
const FAM = [
  ['wolf','狼',['狼','座狼']],
  ['spider','蜘蛛',['蜘蛛','狼蛛','结网蛛','食苔蛛','爬行者','独行蛛','撕裂者','贝瑟莱斯','雷克提拉克','拉克西斯']],
  ['cat','猫科',['豹','虎','狮','捕食者','潜行者','巡行者','霜刃','猛虎','战虎','猎虎','巴尔瑟拉','辛达尔','断牙','拉克西里','月夜']],
  ['bear','熊',['熊']],
  ['boar','野猪',['野猪','斗猪','山猪','阿迦玛','格朗特','公主']],
  ['crab','蟹',['蟹']],
  ['turtle','龟',['龟','克雷什','加摩拉','阿库麦尔']],
  ['crocolisk','鳄鱼',['鳄']],
  ['bat','蝙蝠',['蝙蝠','盲眼猎手']],
  ['bird','鸟类',['秃鹫','碎尸鸟','大鹏','火鹏','斯比弗雷尔','扎里科特','尖啸者','雷鹰']],
  ['owl','枭',['枭','猫头鹰','奥尔姆']],
  ['gorilla','猩猩',['猩猩','乌卡洛克','尤尔查']],
  ['windserpent','风蛇',['风蛇','飞蛇','哈卡之子']],
  ['scorpid','蝎',['蝎','萨科斯','科拉克','克里拉克']],
  ['tallstrider','陆行鸟',['陆行鸟']],
];
function familyOf(name) {
  for (const f of FAM) { for (const kw of f[2]) { if (name.indexOf(kw) >= 0) return f; } }
  return ['other','其他'];
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
  if (m && curRank) { const f = familyOf(m[2]); curRank.beasts.push({ zone: m[1], name: m[2], level: m[3], fam: f[0] }); continue; }
}
const out = [];
// ★★图标改用**客户端内置图标**（用户 1.73.0 指示：先用内置随便选一个占位，下次再确认真实路径）。
//   占位 = INV_Misc_QuestionMark（1.12 必有的问号图标，明确表示「待确认」）；
//   真实路径确定后**只改这张表**（每个技能一行），其余代码与数据不用动。
const ICONROOT = 'Interface\\\\Icons\\\\INV_Misc_QuestionMark';
out.push('-- EvalHelp · PetData.lua —— 猎人宠物技能数据（1.73.0 独立载入）');
out.push('-- 数据来源：用户提供的宠物技能总表截图（doc/pet_info.png），转录整理见 doc/宠物技能数据.md。');
out.push('-- 结构：skills（技能定义+图标）/ ranks[技能名]（各等级：需求宠物等级 + 驯服来源）/ families（家族→图标）。');
out.push('-- 图标：**客户端内置图标**（Interface\\Icons\...）——先用 INV_Misc_QuestionMark 占位，真实路径待用户确认后只改本文件的 ICONROOT 一行。');
out.push('');
out.push('EVAL_PET_DB = {}');
out.push('');
out.push('EVAL_PET_DB.skills = {');
for (const name of skills) {
  const m = META[name];
  if (!m) continue;
  out.push('  { id = ' + Q + m[0] + Q + ', name = ' + Q + name + Q + ', cost = ' + m[2] + ', cast = ' + Q + m[3] + Q + ', range = ' + Q + m[4] + Q + ', cd = ' + Q + m[5] + Q + ', kind = ' + Q + m[6] + Q + ', intro = ' + Q + m[7] + Q + ', icon = ' + Q + ICONROOT + Q + ' },');
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
out.push('EVAL_PET_DB.families = {');
for (const f of FAM.concat([['other','其他']])) { out.push('  ' + f[0] + ' = { label = ' + Q + f[1] + Q + ', icon = ' + Q + ICONROOT + Q + ' },'); }
out.push('}');
out.push('');

out.push('return EVAL_PET_DB');
fs.writeFileSync('PetData.lua', out.join(NL));
const bc = [...rankMap.values()].reduce((a, r) => a + r.reduce((x, y) => x + y.beasts.length, 0), 0);
console.log('skills=' + skills.length + ' beasts=' + bc + ' lines=' + out.length);