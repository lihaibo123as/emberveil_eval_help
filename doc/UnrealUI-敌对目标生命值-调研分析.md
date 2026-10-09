# UnrealUI 敌对目标生命值 调研分析（是否有数据 / 是否能显示）

调研对象：`Interface\AddOns.Disabled\unrealUI`（toc `## Version: 0.10.2` · `## Interface: 11200` · 本机**已停用**，可作参考实现）
调研日期：2026-10-09 ｜ 依据源码：`core\unitvitals.lua`（439 行全文）+ `Database\unit_vitals.lua`（435 KB，**逐条复算**）+ `Database\unit_names{,_zhCN,_ruRU}.lua` + `modules\unitframes.lua`（相关段）+ `modules\tooltip.lua`（相关段）+ `core\commands.lua`（自检口）+ `locales\enUS.lua`
依据数据：本机存档真机读数（`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS2`）+ `doc\通道信息记录.md` + 官方 wiki（emberveil.org）+ 本服数据库站（database.emberveil.org，47 条抽样对照）

**结论一句话**：客户端的敌对目标**只有百分比**（没有绝对生命值）；unrealUI 的「有数据」靠的是**自带一份本服生物生命值库**（10,369 条模板 + 三语名字表），按「名字 + 等级」反查、再用公式复算最大生命值 ⇒ **能显示**（它把目标框的「84%」换成「1121 / 1536」）。本插件现成就有两个显示位（战斗UI 目标条 / 状态UI 目标血行）与一个条件位（`目标血%`），**缺的只是绝对值来源**。

---

## 0. 先回答两个问题

| 问题 | 答案 | 一句话依据 |
| --- | --- | --- |
| 敌对目标生命值**有数据**吗？ | 客户端**没有**（只有 0~100 百分比）；**插件里可以有** —— unrealUI 自带一份本服生物表 | `core\unitvitals.lua:6-12` + `modules\unitframes.lua:581-589` 真机实测 |
| **能显示**吗？ | **能**，而且 unrealUI 已经做了（目标框打「当前 / 上限」真数字 + 蓝量同理） | `unitframes.lua:830-866`（`healthdyn` token）|
| 那份插件数据**是本服的吗**？ | 是 —— 本轮**独立复算**：站点点对点 **47/47 全一致**（含首领） | `node tmp/site_vs_vitals2.js` |
| 直接拿来用**稳**吗？ | 七条边界必须先认（§6），其中 3 条会**静默显示假数或过期数** | 见 §6 |

---

## 1. 客户端事实：敌对单位只有百分比（五条证据，从硬到软）

| # | 证据 | 锚点 | 强度 |
| --- | --- | --- | --- |
| ① | **真机探针读数**：鼠标悬停世界单位实测 `96/100`、`97/100`、`91/100`（**满值恒 100**）；并把目标框打成「84 - 84%」同数字打两遍 | `unrealUI\modules\unitframes.lua:583-589`（引 `behavior.json` probeVersion 1.9.0） | ★★★ 同客户端实测 |
| ② | 客户端**自己的** tooltip 血条是**固定 0-100 范围**，与单位真实血池无关 | `unrealUI\modules\tooltip.lua:383-385` | ★★★ 客户端行为 |
| ③ | 只有「你 / 宠物 / 队伍 / 队友宠物」是绝对值，**其它单位一律 percent-scaled** | `unitframes.lua:521-528`（`REAL_HEALTH_UNITS`）+ `:581-582` | ★★ 实现口径（与①互证） |
| ④ | 本插件自己的口径也一直按百分比用：`pct(cur,max)` 直接算目标血%；测试桩的**目标 `hpmax` 缺省值就是 100** | `Core.lua:342-345, 376`；`test_stub.lua:651-652` | ★★ 本项目既有假定 |
| ⑤ | 官方 wiki 的 `UnitHealth/UnitHealthMax` **没有**写敌对单位百分比，只写「超距队友用 roster 口径」⇒ 文档侧**既不能证实也不能证伪** | `emberveil.org/wiki/lua/globals/Unit`（本轮已抓，`tmp/wiki_unit_probe.js`） | ★ 文档现状（**别据此说"官方没说过所以是假"**） |

★ 结论：**「敌对目标只给百分比」是 vanilla 血统的既定行为**（这也是历史上 MobHealth 一族插件存在的原因），unrealUI 在本客户端**实测过**，与本项目既有假定一致。**但本插件的取证链里目前没有一条"自己量的原始读数"** —— 若要写进本插件记忆体，建议补一条只读探针（附录 A.2-4「`combat seen` 式取证位」+ A.4 步骤 1）。

---

## 2. 数据从哪来：unrealUI 的三件套

| 文件 | 规模 | 内容 |
| --- | --- | --- |
| `Database\unit_vitals.lua` | **435 KB** / 10,616 行 | `units[id] = {class, rank, levelMin, levelMax, healthMultiplier, manaMultiplier}` **10,369 条**；`classLevel[class][level] = {hp, mana}` **189 条**（class **1 / 2 / 8** × 等级 **1~63**）；`rankHpRate`（本批**全是 1.0**）；带 `revision`(sha1) / `migration`(20260822042038) / `patch`(10) 三个**版本记号** |
| `Database\unit_names.lua`（enUS） | 326 KB / 10,363 键 | 名字 → id；首行闸门 `if locale == "ruRU" or locale == "zhCN" then return end` |
| `Database\unit_names_zhCN.lua` | 326 KB / 10,239 键（其中汉字键 **9,338**） | 首行 `if GetLocale() ~= "zhCN" then return end` |
| `Database\unit_names_ruRU.lua` | 508 KB / 10,248 键 | 同上（ruRU 闸门） |
| `core\unitvitals.lua` | 439 行 | 逻辑本体（查表 / 复算 / 当前值跟踪 / 三个对外的只读口） |

**三份名字表是「互斥备选」不是叠加**（toc 注释 `unrealUI.toc:42-45`）：每个文件首行按 `GetLocale()` 早退 ⇒ 只有一份建表；**客户端 locale 决定用哪份**（不是插件的语言设置）——因为这些名字要跟 `UnitName` 的返回**逐字比对**。

### 公式（`core\unitvitals.lua:17-19, 182-205`）

```
maxHealth = max(1, roundf( rankHpRate[rank] × classLevel[class][level][1] × healthMultiplier ))
maxMana   = roundf( classLevel[class][level][2] × manaMultiplier )     -- 仅 powerType == 0（mana）
```

`roundf(x>0)` = `floor(x+0.5)`。**蓝量只覆盖 mana**：VMaNGOS 给非施法者的怒气内部上限 1000（显示 100）、能量上限 100 ⇒ 那两个本来就是客户端给的 0~100 数，套表只会引入比例错误。

### 查表口径（关键：本客户端**没有** `UnitGUID` / 生物 id）

`core\unitvitals.lua:29-36` 明写：本客户端**不暴露任何 unit GUID / creature id**，可用的键只有**名字 + 等级**；作者实测「10,364 个模板 → 15,284 个 (名字,等级) 键，**其中 0 个**带着两个不同的最大生命值」⇒ 同名不同 id 的，任何等级区间覆盖该单位的候选都能代言。**本轮我独立复算了这条性质，成立（见 §3）。**

等级读不到或 `??`（`UnitLevel` 返 **-1**）⇒ 直接 `return nil`（`V.Vitals` 的 `level < 1` 守卫）：**不猜等级，绝不打印一个错误的上限**。

---

## 3. 本轮独立复算（全部可复算，脚本在 `tmp\`）

| 复算项 | 结果 | 脚本 |
| --- | --- | --- |
| 公式复算（真机战斗日志里的怪名） | 峭壁野猪 `1125` L5=**102** L6=120 · 大峭壁野猪 `1126` L6=**120** L7=137 · 黑熊幼崽 `1128` L5=**122** L6=144 | `node tmp/unreal_vitals_probe2.js` |
| **与本站点逐条对照**（`database.emberveil.org/creature/<id>` 的 `health.max`） | **47/47 一致 · 0 不一致**（覆盖 rank 0/1/2/3/4 全档、class 1/2/8、等级 4~60；含首领 Onyxia `10184`=1,099,230 · `10540`=537,240 · `11978`=152,600 · `14988`=91,560 · `17766`=24,416） | `node tmp/site_vs_vitals2.js`（走代理） |
| 怪名命中（取 `doc\通道信息记录.md` §6 的真机原文怪名） | 大峭壁野猪=1126 · 黑熊幼崽=1128 · 峭壁野猪=1125 **全部命中 zhCN 表** | `node tmp/unreal_vitals_probe.js` |
| ★**(名字,等级) → 最大生命值 唯一性** | enUS **15,287** 键 / zhCN **15,129** 键 / ruRU **15,118** 键 ⇒ **冲突 0**（复现了作者的 15,284 口径） | `node tmp/vitals_conflict_check.js` |
| ★**三语名字表取并集**（本轮新增的改进点） | 名字键 29,407 · (名,级) 键 43,574 · 覆盖 **10,367 / 10,369** id · **冲突仍为 0** ⇒ 比「按 locale 选一份」（zhCN 只覆盖 10,239）**多覆盖 128 个 id** | `node tmp/vitals_union_check.js` |
| zhCN 缺名的 128 个 id 是什么 | 全是**真实怪**（`Defias Rioter` 5043 / `Dalaran Mage` 1914 / `Bleak Worg` 3861 …），站点上这些 id **也只有英文名** ⇒ 属「本服 zhCN 数据里这批没有中文名」，不是生成漏掉 | `node tmp/vitals_missing_names.js` · `tmp/vitals_gap_probe.js` |
| 数据自造可行性 | 站点 `/creatures` 列表 **9,936 条**、**服务端渲染分页**（`?page=N`），但**列表页不含血量**（只有 min/max 等级与类型）⇒ 自造要么爬 ~10k 个 `/creature/<id>` 详情页，要么另找服务端表 | `node tmp/site_creatures_list.js` |

⇒ **「自带一份本服生物表」这条路在本服是成立的**（不是我猜的，是站点点对点校过的）。

---

## 4. 「当前血量」怎么来：它不是读数，是**估计**（这一节决定"能不能当真"）

`core\unitvitals.lua:22-27, 243-357` 的口径很干净：

1. **种子**：`SyncFromPercent` = `round(max × UnitHealth / UnitHealthMax)` —— 客户端的百分比把它**钉在一个"上限的 1% 宽"的带子里**。
2. **带内精修**：`UNIT_COMBAT(unit, action, modifier, amount, school)` 里 `HEAL` 加、`WOUND` 减（`MISS/DODGE/PARRY/BLOCK/RESIST/ABSORB` 一律不动），把值在带子里推动 ⇒ 目标框的绝对数字在**两次百分比跳变之间也会动**（`unitframes.lua:4367-4376` 专门把它并进"变没变"的比较，否则读数会卡住）。
3. **仲裁**：`OnHealth` 每次 `UNIT_HEALTH` 复查一次 —— 跟踪值若跑出**百分比带 ±1%**（`max×(v-1)/max ~ max×(v+1)/max`）就**丢弃跟踪值、回到百分比算的值**。作者原话：**"百分比永远赢"，漏掉一个事件不会让读数飘走**。
4. **满 / 空**取精确端点（`v >= max ⇒ max`、`v <= 0 ⇒ 0`，不量化）。
5. **只跟踪 `target` 一个单位**（"它才是客户端报伤害的那个单位"），且**同一只怪、非强制重绑时保留累计值**（`ResetTarget(force)`）。
6. **触发点**：`PLAYER_TARGET_CHANGED` · `PLAYER_ENTERING_WORLD`（`force=true`）· `UNIT_HEALTH` · `UNIT_COMBAT`（`V:OnEnable`，`unitvitals.lua:425-438`）。
7. **缓带有界**：`(名字:等级) → 值` 缓存上限 **400**，超了整表丢弃（"一个会话打死几千只不同的怪"不会无界增长）。

### ★★ 本客户端的**未取证**点（照抄前必看）

`unitvitals.lua:327-334` 作者自己写明：`UNIT_COMBAT` 在 `query_compat.py` 里**两个方向都没有记录**，这条是**从 UnrealPfUI 的 `libs/libhealth.lua` 搬过来的**（`WORKING_SOURCE`，**非** runtime 验证）；因为整条精修是**加法**，事件不来最多退化成"百分比估计"（准确到 1%）。

**本插件自己的真机记录**（`doc\通道信息记录.md` §2b；本轮又从存档复读了一遍）：
- `UNIT_COMBAT` **实测 107 次**，`arg1=target`、`arg2=WOUND`、**`arg3=空`**（`LIHAIBOAS2` 存档 `cfg.meleeProbe` 环内第 `[119]` 条 = 存档文件 `L13113`；复读脚本 `node tmp/read_target_hp_evidence.js`）
- ★但本插件的探针**只记 `arg1..arg3`**（`Engine.lua:7069-7071`）⇒ **`arg4 = amount` 在本客户端从未被记录过**。「事件在发」已证实；**「它带的数值是不是伤害量」还没证实** —— 这正是采用"事件精修"前的**唯一前置核实**（探针机制现成：⑨ 段扩成 `a1..a4` 即可）。
- 若不想依赖这条未验证通道：本插件**已经在解析战斗日志伤害文本**（`CHAT_MSG_COMBAT_SELF_HITS` 等，挥击计时/围攻探针都在用）⇒ 走日志精修是**同一前提下的等价路线**（代价：只在 zhCN/enUS 成立）。

---

## 5. 它怎么显示（"能不能显示"的实证）

| 位置 | 做法 | 锚点 |
| --- | --- | --- |
| 自绘目标框文本 | token 表驱动：`healthdyn` 在**表命中**时打 `1121 / 1536`（`Abbreviate` 缩写），否则退回 `84%`；满血时打上限本身；`healthval` 只打当前值（表未命中就**留空**）；`healthpct` 打 `N%`（`math.ceil`） | `unitframes.lua:786-866` |
| Classic 主题（把框还给客户端） | 客户端自己那套框**没有**绝对值可打 ⇒ 在原生血条/蓝条上各盖**一条插件自建 FontString**（挂在自家 catcher 上、每次重绑**重新量一次**原生子件中心偏移；量不到就退回帧心） | `unitframes.lua:4028-4060`（`classicNative.BindVitals`，段头注释 `:3982-3997`）|
| 只对 `target` 做这件事 | 注释写明理由：**它才是客户端既报百分比、又报伤害的那个单位** | `unitframes.lua:4025-4027` |
| 开关 | `exactVitals` **默认开**；悬停文案直说"客户端只报百分比，打开后打真数字并把当前值按看到的伤害精修" | `core\unitvitals.lua:52`；`locales\enUS.lua:386-389` |
| 自检口 | `/uui check` 打印：开关 / 表在不在 / 名字表在不在（**哪一份 locale**）/ 索引好没 / 缓存条数 / 当前跟踪的键与值 / **combat seen**（打过一场还是 false ⇒ 事件不来，读数一直只有百分比） | `core\commands.lua:248-265` |

★ 三个「好的设计」值得单独记：⒜ **判不出就退回百分比**（绝不显示 0 或假数）；⒝ **`combat seen` 把"通道存不存在"变成可读的取证**（而不是又一个假设）；⒞ **上限有界 + 只 track 目标**（性能与内存口径）。

---

## 6. 边界与坑（照抄前必读；★标的三条会**静默**出假数/过期数）

1. ★**`??` / 骷髅怪查不到**：官方 wiki 原文 —— `UnitLevel`「Hostile units 10+ levels above the player, and world bosses, report **-1** (skull)」⇒ 越高等级首领、世界首领**永远拿不到绝对值**（unrealUI 的 `level < 1 ⇒ nil` 是**故意的**：宁可只有百分比，也不打印错的上限）。
2. ★**名字对不上就查不到**：本插件 zhCN 表覆盖 10,239 / 10,369（**缺 128 个**）。修法（比 unrealUI 更稳）＝**三语名字表取并集**：本轮实测覆盖 **10,367 / 10,369**，且 **(名字,等级) 冲突仍为 0**（§3）。对非中/英/俄客户端，仍只能退回百分比。
3. ★**数据会过期**：unrealUI 自己写「a realm that has retuned its creatures would make them **wrong rather than absent**」⇒ 表版本必须**带记号**（照本项目 `worldFogCfg.buildTag` 惯例）并能**随时重生成**；玩家/宠物/队友**不许**套表（客户端本来就给绝对值，套了是二次换算）。
4. **当前值不是精确读数**（§4）：只能当"带内估计"，**绝不当"精确血量"对外承诺**；百分比永远是仲裁者。
5. **事件通道未取证**：`UNIT_COMBAT` **「在发」已证实**（真机 107 次），但**它带的 `arg4` 是不是伤害量没量过**（§4 末）⇒ 采用"事件精修"前先探针。★同族提醒：本项目已有「**exe 里 0 命中、真机却在发**」的先例（`ACTIONBAR_UPDATE_COOLDOWN`，见 `CLAUDE.md` §5.5）⇒ **"查不到"既不等于"不存在"，也不等于"能用"**，只能真机量。
6. **体积**：vitals 435 KB + 三语名字表 1.16 MB ≈ **1.6 MB**（本项目主包体量大，不是阻碍，但要决定是"三语全带"还是"精简到只带名字+上限"）。
7. **出处与许可**：unrealUI 本体 MIT，但**数据是 VMaNGOS 世界数据 / 本服数据库快照** ⇒ 建议照本项目既有先例**自造生成物 + 出处许可说明文件**（`doc\地图层数据-出处与许可.md` 那一套），**不要**直接把第三方数据文件当自家数据搬进包（本项目"不与第三方做关联"的既定口径）。

---

## 附录 A：与本插件对照 + 取什么

### A.1 现状对照

| 维度 | 本插件现状 | UnrealUI | 差异性质 |
| --- | --- | --- | --- |
| 敌对目标**上限** | **没有**（只有百分比） | 10,369 条模板复算出的精确上限 | ★本插件**缺** |
| 敌对目标**当前值** | 百分比（`st.tHpPct`） | 绝对值（估计：百分比带 + 事件精修） | 本插件缺绝对值 |
| 显示位 | 战斗UI **目标血条**（`EvalHelp.lua:1341-1347`，文本「名字 N%」）· 状态UI **目标血行**（`:5200`） | 目标框 token（「1121 / 1536」）+ Classic 主题补两条 FontString | 平（**显示位我们现成有**） |
| 进规则引擎 | ✅ 条件 `目标血%`（`tHpPct`，含文本口径「目标血」`Engine.lua:5094`） | ❌ 无（纯显示） | **本插件优势要保住** |
| 语言无关性 | 条件与显示都不依赖语言 | 只依赖 `UnitName`（三语各一份表） | 平 |
| 蓝量 | 只对队友/宠物有（`tPowerPct` 等） | 敌对目标 mana 也给绝对值 | 本插件缺 |

### A.2 值得抄（按优先级）

1. ★★★**「上限 = 表复算」这件事本身** —— 这是唯一能拿到敌对目标绝对值的路（客户端给不了）。**落点不用新建 UI**：战斗UI 目标条文本从「名字 N%」扩成「名字 1,234 / 5,678 (22%)」、状态UI 目标血行同理。**零风险的一半先做**：`current = round(max × tHpPct/100)`（纯百分比换算，不需要任何事件通道）。
2. ★★★**`判不出 ⇒ 退回百分比` 的 fail-open 口径**：表里没有 / 等级 −1 / 名字对不上 / 表没载入 ⇒ **照旧走百分比**（要显"未知"就写「—」，**绝不用 0 冒充真值**）。这与本项目「拿不到证据就一个字节都不碰」同尺。
3. ★★**三语名字表取并集**（我们比它做得更好）：本轮已证 **10,367 / 10,369 覆盖 + 0 冲突**（`tmp/vitals_union_check.js`）；unrealUI 是"一个 locale 一份、互斥加载"，zhCN 下少 128 个 id。
4. ★★**`combat seen` 式的"通道到底来没来"取证位**（照抄它的形态，不抄它的通道）：本项目已有 ⑨ 段参数序列 + `cfg.meleeProbe` 有界落盘 + `/eh go melee 报告`，把 `UNIT_COMBAT` 的 **`arg4`** 加进去，一次战斗就能定案"能不能拿它精修"。
5. ★★**「百分比永远赢」的仲裁口径**（若做精修）：跟踪值跑出 ±1% 带就丢弃估计值 —— 这条是"漏事件不飘"的全部保障；没有它，绝对数字会**越打越偏**。
6. ★**缓存有界 + 只 track 目标**（400 条上限、`target` 单单位）—— 与本项目"有界账"同尺。
7. ★**版本记号**：`revision`(sha1) / `migration` / `patch` 三个字段随数据走 ⇒ 真机排查"客户端跑的是哪份数据"时立刻可判（本项目 `buildTag` 同款）。

### A.3 不建议抄

1. **自家单位框 / Classic 主题补 FontString 那一整套** —— 本插件是"规则引擎 + 信息 UI"，不是皮肤框架；显示位我们现成有（目标条 + 状态行）。
2. **按 locale 互斥加载名字表** —— 直接用并集（A.2-3），并且**与客户端 locale 解耦**（我们的查表键只是字符串，不需要跟显示语言一致）。
3. **把 `UNIT_COMBAT` 当既成事实** —— 本客户端 `arg4` 未取证（§4 末）；先探针，后写代码。
4. **照搬 435 KB 数据文件的生成口径** —— 应自造生成物 + 出处许可（§6-7）。

### A.4 若要做，建议的落地顺序

| 步骤 | 内容 | 风险 | 前置核实 |
| --- | --- | --- | --- |
| 1 | 只读探针：把 `UNIT_COMBAT` 的 **`arg1..arg4`** 全量入 ⑨ 段（现成机制），打一场战斗 + `/reload`，我读存档 | 极低（只加一列取证） | 无 |
| 2 | 数据来源决策：自造生成物（爬站点 / 另找服务端表）vs 快照一份（含出处许可文件） | 低（离线，零运行时依赖） | 站点 `/creatures` 9,936 条 + `/creature/<id>` 有 `health.max`（本轮已验）；爬 10k 页的耗时与限频要评估 |
| 3 | 只做"上限 + 百分比换算"的**显示**（A.2-1 的零风险半边）：战斗UI 目标条 / 状态UI 目标血行 | 低 | 无（纯乘法） |
| 4 | 三语并集名字表 + 版本记号 + `判不出退回百分比`（A.2-2/3/7） | 低-中 | 步骤 2 的数据 |
| 5 | 条件口扩一个「目标剩余血量（绝对值）」/「目标最大生命值」（照 `tHpPct` 的**四处成对**写法：`SE_TYPES` + `CTG_2.ids` + 三语 `CT_*` + `COND_NUM`/`parseOneRaw`/`EVAL_COND_STR`/`EVAL_PARSE_ONE`） | 中（文本口径漏一处 = 导出能看导入即丢） | 步骤 3/4 落地后 |
| 6 | （可选）当前值精修：`UNIT_COMBAT` 或**战斗日志伤害**（我们已解析）+「百分比永远赢」仲裁 | 中-高（假数风险最高的一段） | **步骤 1 的读数**；没有它就别做 |

★ 全部改完仍按本项目纪律：只跑 `node luacheck.js` + `node sync_game.js`，**不许声称"过了全套闸门"**，真机实测才是最终判据。

---

## 附录 B：本轮脚本清单（全只读，可复算）

| 脚本 | 作用 |
| --- | --- |
| `tmp/unreal_vitals_probe.js` | 名字表形态 + 真机怪名命中 + units/classLevel 规模 |
| `tmp/unreal_vitals_probe2.js` | 按 unrealUI 公式复算 maxHealth（真机怪名逐等级）+ 数据自洽性 |
| `tmp/site_vs_vitals.js` / `tmp/site_vs_vitals2.js` | 与本服数据库站 `health.max` 对照（后者 = 47 条抽样全一致） |
| `tmp/site_creature_probe.js` / `tmp/site_creature_dump.js` | 站点生物页取数形态（`health:{current,max}`） |
| `tmp/site_creatures_list.js` | 站点列表页形态（9,936 条 / 服务端分页 / **无血量列**） |
| `tmp/vitals_conflict_check.js` | (名字,等级) → 最大生命值 唯一性（三语各一份） |
| `tmp/vitals_union_check.js` | 三语并集的安全性（覆盖 10,367/10,369 + 0 冲突） |
| `tmp/vitals_missing_names.js` / `tmp/vitals_gap_probe.js` | zhCN 缺名 128 个 id 的性质 |
| `tmp/read_target_hp_evidence.js` | 从本机存档复读 `UNIT_COMBAT` 真机读数（全账号） |
| `tmp/wiki_unit_probe.js` / `tmp/wiki_level_probe.js` | 官方 wiki 原文（UnitHealth/UnitHealthMax/UnitLevel） |
