// EvalHelp · gen_iconsem.js —— 由 doc/图标路径清单.txt 生成 IconSem.lua（图标语义表：名称 + 多标签）
// 用法：node gen_iconsem.js   （数据源只有那份客户端采集的清单，单一真值）
// 规则：① 前缀给「类别/学派/职业」标签；② 词表给中文名与同义词标签；③ 认不出的词保留英文原文，
//   名称退回原始基础名（如实，不编）——覆盖率会打印出来。
const fs = require("fs");
const NL = String.fromCharCode(10);
const Q = String.fromCharCode(34);
const PREFIX = "/Game/Interface/Icons/";
const SUFFIX = "_TEX";
// ① 前缀 → 标签（顺序敏感：长的先匹配）
const PRES = [
  ["Spell_Fire_", "火焰", "法术"], ["Spell_Frost_", "冰霜", "法术"], ["Spell_Ice_", "冰霜", "法术"],
  ["Spell_Nature_", "自然", "法术"], ["Spell_Shadow_", "暗影", "法术"], ["Spell_Holy_", "神圣", "法术"],
  ["Spell_Arcane_", "奥术", "法术"], ["Spell_Magic_", "魔法", "法术"], ["Spell_Totem_", "图腾", "法术"],
  ["Spell_", "法术"],
  ["Ability_Hunter_Pet_", "宠物", "猎人"], ["Ability_Hunter_", "猎人", "技能"], ["Ability_Warrior_", "战士", "技能"],
  ["Ability_Rogue_", "盗贼", "技能"], ["Ability_Druid_", "德鲁伊", "技能"], ["Ability_Creature_", "生物", "技能"],
  ["Ability_Mount_", "坐骑"], ["Ability_Racial_", "种族"], ["Ability_", "技能"],
  ["INV_Misc_", "物品", "杂物"], ["INV_", "物品"], ["Trade_", "商业"], ["Racial_", "种族"], ["Temp", "临时"],
];
// ② 词表：英文词 → [中文名, 同义词...]（同义词全进标签；第一个词作中文名候选）
const W = {
  Potion: ["药水"], Food: ["食物"], Drink: ["饮料"], Gem: ["宝石"], Herb: ["草药"], Cloth: ["布"], Ore: ["矿石"],
  Ingot: ["锭"], Bandage: ["绷带"], Bomb: ["炸弹"], Dust: ["尘"], Essence: ["精华"], Crystal: ["水晶"],
  Ruby: ["红宝石"], Emerald: ["绿宝石"], Topaz: ["黄玉"], Opal: ["猫眼石"], Pearl: ["珍珠"], Amethyst: ["紫水晶"],
  Bloodstone: ["血石"], Arcanite: ["奥金锭"], Stone: ["石头", "岩石"], Bone: ["骨头", "骨骸"], Organ: ["器官"],
  Head: ["头"], MonsterHead: ["怪物头"], MonsterClaw: ["爪", "爪子", "爪击", "尖爪"], MonsterScales: ["鳞片", "鳞"],
  MonsterFang: ["獠牙", "牙", "尖牙"], Shell: ["甲壳", "壳", "龟壳"], Pelt: ["毛皮"], Horn: ["角"],
  Sword: ["剑"], Weapon: ["武器"], Axe: ["斧"], Mace: ["锤"], Hammer: ["锤"], Spear: ["矛"], Halberd: ["戟"],
  Staff: ["法杖"], Wand: ["魔杖"], Bow: ["弓"], Crossbow: ["弩"], Rifle: ["步枪"], Gun: ["枪"], Musket: ["火枪"],
  Ammo: ["弹药"], Arrow: ["箭"], Bullet: ["子弹"], ThrowingKnife: ["飞刀"], ShortBlade: ["短刃"], Dagger: ["匕首"],
  Shield: ["盾", "盾牌"], Armor: ["护甲"], ArmorKit: ["护甲片"], Boots: ["靴", "鞋子"], Chest: ["胸甲"],
  Helmet: ["头盔"], Gauntlets: ["手套"], Trinket: ["饰品"], Amulet: ["护符"], Jewelry: ["珠宝"], Crown: ["王冠"],
  Key: ["钥匙"], Book: ["书", "书籍"], StoneTablet: ["石板"], Scroll: ["卷轴"], Banner: ["旗帜"], Token: ["徽记"],
  Talisman: ["护符"], Orb: ["宝珠"], Rune: ["符文"], Egg: ["蛋"], Fish: ["鱼"], Wine: ["酒"], Milk: ["奶"],
  Feather: ["羽毛", "羽"], Basket: ["篮子"], Pipe: ["烟斗"], Wrench: ["扳手"], Gizmo: ["装置"], Gizmos: ["装置"],
  Gunpowder: ["火药"], Battery: ["电池"], Cask: ["木桶"], Flask: ["药瓶"], EmptyFlask: ["空药瓶"], Gift: ["礼物"],
  Present: ["礼物"], Holiday: ["节日"], SummerFest: ["仲夏节"], Christmas: ["冬幕节"], Flower: ["花"],
  Blood: ["血"], Vampire: ["吸血鬼"], Ghost: ["幽灵"], Skull: ["骷髅"], Zombie: ["僵尸"], Demon: ["恶魔"],
  Dragon: ["龙"], Drake: ["幼龙"], QirajiCrystal: ["其拉水晶"], AhnQirajTrinket: ["安其拉饰品"], QirajIdol: ["其拉雕像"],
  Beast: ["野兽"], Pet: ["宠物"], Wolf: ["狼", "座狼"], Cat: ["猫科", "猫"], Bear: ["熊"], Boar: ["野猪", "猪"],
  Crab: ["蟹", "螃蟹"], Turtle: ["龟", "乌龟"], Crocolisk: ["鳄鱼"], Bat: ["蝙蝠"], Vulture: ["秃鹫", "鸟"],
  Owl: ["枭", "猫头鹰"], Gorilla: ["猩猩"], WindSerpent: ["风蛇", "蛇"], Scorpid: ["蝎", "蝎子"],
  TallStrider: ["陆行鸟"], Spider: ["蜘蛛"], Hyena: ["鬣狗"], Raptor: ["迅猛龙"], Kodo: ["科多兽"],
  RidingHorse: ["坐骑·马"], Charger: ["军马"], Dreadsteed: ["恐惧战马"], NightmareHorse: ["梦魇"],
  MechaStrider: ["机械陆行鸟"], MountainRam: ["山羊坐骑"], BlackDireWolf: ["黑狼坐骑"], WhiteDireWolf: ["白狼坐骑"],
  BlackPanther: ["黑豹坐骑"], JungleTiger: ["丛林虎坐骑"], PinkTiger: ["粉虎坐骑"], WhiteTiger: ["白虎坐骑"],
  Undeadhorse: ["亡灵马"], Attack: ["攻击"], Strike: ["打击"], Bolt: ["箭", "弹"], Shot: ["射击"],
  CriticalStrike: ["暴击"], CriticalShot: ["致命射击"], MeleeDamage: ["近战伤害"], Damage: ["伤害"],
  Bite: ["咬", "撕咬", "啃咬"], FerociousBite: ["凶猛撕咬"], Claw: ["爪", "爪子", "爪击"], Ravage: ["撕碎"],
  Mangle: ["裂伤"], Maul: ["重殴"], Rake: ["撕抓"], Swipe: ["横扫"], Bash: ["重击"], Kick: ["踢"],
  Gouge: ["凿击"], Ambush: ["伏击"], BackStab: ["背刺"], CheapShot: ["肾击"], Disembowel: ["剖腹"],
  SupriseAttack: ["突袭"], SwiftStrike: ["迅捷打击"], ImpalingBolt: ["穿刺之箭"], AimedShot: ["瞄准射击"],
  Quickshot: ["快速射击"], RunningShot: ["移动射击"], SniperShot: ["狙击"], Marksmanship: ["射击精通"],
  Roar: ["咆哮"], ChallangingRoar: ["挑战咆哮"], DemoralizingRoar: ["挫志咆哮"], Howl: ["嚎叫"], Growl: ["低吼"],
  Taunt: ["嘲讽"], Enrage: ["激怒"], Frenzy: ["狂乱"], GhoulFrenzy: ["食尸鬼狂乱"], Defend: ["防御"],
  Dodge: ["闪避"], Parry: ["招架"], Block: ["格挡"], Dash: ["疾跑", "突进", "冲刺"], Sprint: ["疾跑"],
  Speed: ["速度", "迅捷"], Slow: ["减速"], Root: ["定身"], Ensnare: ["缠绕"], Snare: ["诱捕"],
  Stealth: ["潜行", "隐身"], Invisibilty: ["隐形"], Prowl: ["潜伏"], Cower: ["畏缩", "缩头"],
  Poison: ["毒", "毒素", "中毒"], PoisonSting: ["毒刺"], Poisons: ["毒药"], Venom: ["毒液"],
  Disease: ["疾病", "疫病"], Curse: ["诅咒"], NullifyPoison: ["解毒"], NullifyDisease: ["解病"],
  RemoveCurse: ["解诅咒"], DispelMagic: ["驱散魔法"], AbolishMagic: ["废除魔法"], Cure: ["治疗", "治愈"],
  Heal: ["治疗"], MendPet: ["治疗宠物"], Rejuvenation: ["回春"], Renew: ["恢复"], Regen: ["回复"],
  Blessing: ["祝福"], GreaterBlessingofKings: ["强效王者祝福"], Aura: ["光环"], Seal: ["圣印"],
  Judgement: ["审判"], Excorcism: ["驱邪术"], Holy: ["神圣"], Light: ["圣光"], Resurrection: ["复活"],
  Reincarnation: ["复生"], RaiseDead: ["亡者复生"], Immolation: ["献祭"], SelfDestruct: ["自爆"],
  Fireball: ["火球"], FireBolt: ["火焰箭"], Fire: ["火焰", "火"], FireArmor: ["火焰护甲"],
  Frostbolt: ["寒冰箭"], Frost: ["冰霜", "冰"], Glacier: ["冰川"], Stun: ["眩晕"], Freezing: ["冰冻"],
  IceShock: ["冰霜震击"], IceClaw: ["冰爪"], FrostArmor: ["冰霜护甲"], ChillingArmor: ["寒冷护甲"],
  Lightning: ["闪电"], LightningShield: ["闪电之盾"], LightningBolt: ["闪电箭"], ChainLightning: ["闪电链"],
  ThunderBolt: ["雷霆箭"], ThunderClap: ["雷霆一击"], Thunder: ["雷霆", "雷"], Storm: ["风暴"],
  Nature: ["自然"], NaturesBlessing: ["自然之赐"], NatureTouchGrow: ["自然生长"], NatureTouchDecay: ["自然腐朽"],
  StrangleVines: ["缠绕藤蔓"], WispSplode: ["小精灵爆炸"], MoonGlow: ["月光"], StarFire: ["星火"],
  Shadow: ["暗影", "阴影"], ShadowWard: ["暗影防护"], BlackPlague: ["黑死病"], ChillTouch: ["冰冻之触"],
  MindSteal: ["心灵窃取"], PsychicScream: ["尖啸", "精神尖啸"], DeathScream: ["死亡尖啸"], RagingScream: ["狂暴尖啸"],
  Fear: ["恐惧"], Charm: ["魅惑"], Sleep: ["睡眠"], Hibernation: ["休眠"], ManaBurn: ["法力燃烧"],
  SiphonMana: ["吸取法力"], ManaRecharge: ["法力回复"], ManaRegen: ["法力回复"], ManaShield: ["法力护盾"],
  Arcane: ["奥术"], ArcaneIntellect: ["奥术智慧"], ArcaneResilience: ["奥术抗性"], Blink: ["闪现"],
  Portal: ["传送门"], Teleport: ["传送"], StarFire2: ["星火"],
  Resist: ["抗性"], ResistMagic: ["魔法抗性"], ResistNature: ["自然抗性"], Resistance: ["抗性"],
  FireResistanceTotem: ["火抗图腾"], FrostResistanceTotem: ["冰抗图腾"], NatureResistanceTotem: ["自然抗性图腾"],
  MagicImmunity: ["魔法免疫"], AntiMagicShell: ["反魔法护盾"], WardOfDraining: ["汲取结界"], NullWard: ["虚无结界"],
  SpiritArmor: ["自然护甲", "灵魂护甲"], UnyeildingStamina: ["持久耐力"], Stamina: ["耐力"],
  BlessingOfStamina: ["耐力祝福"], BlessingOfMight: ["力量祝福"], BlessingOfStrength: ["力量祝福"],
  Strength: ["力量"], Agility: ["敏捷"], Intellect: ["智力"], Spirit: ["精神"],
  BeastCall: ["召唤野兽"], BeastCall02: ["召唤野兽"], BeastTaming: ["驯服野兽"], BeastTraining: ["训练野兽"],
  BeastSooth: ["安抚野兽"], BeastSoothe: ["安抚野兽"], MendPet2: ["治疗宠物"], Pathfinding: ["寻路"],
  EagleEye: ["鹰眼"], EyeOfTheOwl: ["枭之眼"], AspectOfTheMonkey: ["猴之守护"],
  FiegnDead: ["假死"], FeignDeath: ["假死"], DualWield: ["双武器"], TravelForm: ["旅行形态"],
  AquaticForm: ["水栖形态"], CatForm: ["猎豹形态"], CatFormAttack: ["猫形态攻击"], BearForm: ["熊形态"],
  Challange: ["挑战"], Totem: ["图腾"], Earth: ["大地"], Wind: ["风"], Water: ["水"], Flame: ["烈焰"],
  Bloodlust: ["嗜血"], BullRush: ["野蛮冲撞"], ShockWave: ["冲击波"], Earthquake: ["地震"],
  Kodo: ["科多兽"], Worg: ["座狼"], Raptor2: ["迅猛龙"], Organ2: ["器官"],
  HolidayGift: ["节日礼物"], Wood: ["木材"], Metal: ["金属"], Glass: ["玻璃"], Leather: ["皮革"],
  Mail: ["锁甲"], Plate: ["板甲"], ClothArmor: ["布甲"], Scroll2: ["卷轴"], Letter: ["信件"],
  Map: ["地图"], Compass: ["罗盘"], Lantern: ["灯笼"], Torch: ["火把"], Candle: ["蜡烛"],
  // ★1.73.6 放大镜（抓宠详情页右侧按钮用的那枚；用户就是这么叫它的）
  Spyglass: ["放大镜", "望远镜"],
  Devour: ["吞噬"], Harass: ["侵扰"], Pierce: ["穿刺"], Avatar: ["化身"], BloodRage: ["血性狂暴"],
  Cannibalize: ["食尸"], ShadowMeld: ["影遁"], Ultravision: ["夜视"], Repair: ["修理"], Disguise: ["伪装"],
  Distract: ["扰敌"], DualWeild: ["双武器"], Eviscerate: ["剔骨"], Cursed: ["被诅咒"], Golem: ["魔像"],
  Rage: ["怒气"], Meld: ["隐匿"], Clap: ["轰鸣"], Corrupt: ["堕落"], Ashbringer: ["灰烬使者"],
  Barrier: ["屏障"], Ward: ["结界"], Salve: ["药膏"], Elixir: ["药剂"], Mighty: ["强效"], Might: ["力量"],
  Wisdom: ["智慧"], Kings: ["王者"], Sanctuary: ["庇护"], Sacrifice: ["牺牲"], Freedom: ["自由"],
  Protection: ["保护"], Retribution: ["惩戒"], Fury: ["狂怒"], Focus: ["专注"], Meditation: ["冥想"],
  Concentration: ["专注"], Clearcasting: ["清晰施法"], IceBarrier: ["寒冰屏障"], IceBlock: ["寒冰屏障"],
  IceLance: ["冰枪"], ConeOfCold: ["冰锥术"], Blizzard: ["暴风雪"], Flamestrike: ["烈焰风暴"],
  Pyroblast: ["炎爆术"], Scorch: ["灼烧"], Ignite: ["点燃"], FireBlast: ["火焰冲击"], FrostNova: ["冰霜新星"],
  Counterspell: ["法术反制"], Spellsteal: ["法术窃取"], ArcaneExplosion: ["奥术爆炸"], Evocation: ["唤醒"],
  Shade: ["幽影"], TrueSight: ["真实视界"], FarSight: ["远视"], Slowing: ["缓速"], Reanimate: ["复生"],
  Unholy: ["邪恶"], Death: ["死亡"], Coil: ["缠绕"], Plague: ["瘟疫"], Decay: ["腐朽"], Bane: ["灾祸"],
  Spellstone: ["法术石"], Firestone: ["火焰石"], Soulstone: ["灵魂石"], Healthstone: ["治疗石"],
  Shard: ["碎片"], Scythe: ["镰刀"], Cloak: ["披风"], Tabard: ["战袍"], Shirt: ["衬衣"], Ring: ["戒指"],
  Necklace: ["项链"], Pendant: ["吊坠"], Locket: ["项链"], Cape: ["斗篷"], Belt: ["腰带"], Gloves: ["手套"],
  Pants: ["护腿"], Leggings: ["护腿"], Pauldrons: ["护肩"], Bracers: ["护腕"], Vambraces: ["护腕"],
};
const lines = fs.readFileSync("doc/图标路径清单.txt", "utf8").split(/\r?\n/).filter(l => l && l.charAt(0) !== "#");
const out = [];
const seen = {};
let named = 0, fallback = 0;
for (const raw of lines) {
  const path = raw.trim();
  if (path.indexOf(PREFIX) !== 0) continue;
  const base = path.slice(PREFIX.length).replace(/_TEX$/, "");
  if (seen[base]) continue;
  seen[base] = true;
  const tags = [];
  const pushTag = t => { if (t && tags.indexOf(t) < 0) tags.push(t); };
  let rest = base, name = null;
  for (const p of PRES) { if (base.indexOf(p[0]) === 0) { rest = base.slice(p[0].length); for (let i = 1; i < p.length; i++) pushTag(p[i]); break; } }
  // 逐个词查表：先整体命中（MonsterClaw 要整体命中），不中再按驼峰拆子词拼中文
  //   （FrostResistanceTotem → 冰霜+抗性+图腾；纯数字段跳过，不当标签）
  const isNum = s => /^[0-9]+$/.test(s);
  const camel = s => { const o = []; let cur = ""; for (const ch of s) { if (ch >= "A" && ch <= "Z" && cur) { o.push(cur); cur = ch; } else cur += ch; } if (cur) o.push(cur); return o; };
  const names = [];
  const parts = rest.split("_");
  for (const w of parts) {
    if (isNum(w)) continue;
    const hit = W[w];
    if (hit) { pushTag(hit[0]); for (let i = 1; i < hit.length; i++) pushTag(hit[i]); names.push(hit[0]); continue; }
    let any = false; const sub = [];
    for (const sw of camel(w)) {
      const h2 = W[sw];
      if (h2) { pushTag(h2[0]); for (let i = 1; i < h2.length; i++) pushTag(h2[i]); sub.push(h2[0]); any = true; }
      else sub.push(isNum(sw) ? "" : sw);
    }
    if (any) for (const x of sub) if (x && !/[A-Za-z]/.test(x)) names.push(x); // 只收已翻译的部分（半英半中的名字更糟）
    else pushTag(w.toLowerCase());
  }
  if (names.length) name = names.join("");
  if (name) named++; else { name = base; fallback++; }
  out.push("  [" + Q + base + Q + "] = " + Q + name + "|" + tags.join("/") + Q + ",");
}
const head = [
  "-- EvalHelp · IconSem.lua —— 图标语义表（由 gen_iconsem.js 从 doc/图标路径清单.txt 生成，勿手改）",
  "--   key   = 图标基础名（/Game/Interface/Icons/<key>_TEX）",
  "--   value = \"名称|标签1/标签2/…\"（标签含中文同义词 + 类别/学派/职业 + 未识别英文词，便于过滤）",
  "--   ★名称认不出来时**退回原始英文名**（如实，不编）；覆盖率见生成脚本输出。",
  "--   改词表/前缀规则 → 改 gen_iconsem.js 重跑（单一真值 = 那份客户端采集的清单）。",
  "EVAL_ICON_SEM = {",
].join(NL);
fs.writeFileSync("IconSem.lua", head + NL + out.join(NL) + NL + "}" + NL + "return EVAL_ICON_SEM" + NL, "utf8");
console.log("icons=" + out.length + " named=" + named + " fallback=" + fallback +
  " (" + Math.round(named * 100 / (named + fallback)) + "% 有中文名)");