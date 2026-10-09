# UnrealUI 近战 / 远程攻击计时（Swing Bar）调研分析

调研对象：`Interface\AddOns\unrealUI`（toc `## Version: 0.10.2`）
调研日期：2026-10-09 ｜ 依据源码：`unrealUI` 0.10.2（`modules\swingbar.lua` 1094 行全文 + `core\weapons.lua` / `core\compat.lua` / `modules\autoattack.lua` / `core\init.lua`）
结论一句话：**它不是"拿武器速度自走一个循环条"，而是"等客户端真的报出一次攻击 → 拿它当锚点 → 用实测周期（中位数）画条，并且绝不 wrap"。**

---

## 0. 相关文件与分工

| 文件 | 职责 |
| --- | --- |
| `modules\swingbar.lua` | **计时本体**：三条车道（主手 / 副手 / 远程）、事件钟、周期学习、绘制、距离闸门 |
| `core\weapons.lua` | 武器槽与远程动作的共享读取：`HasOffhandWeapon` / `HasRangedWeapon` / `HasBowOrGun` / `RangedAttackState` / `FindRangedSlot` |
| `core\compat.lua` | `U.MeleeInteractRange`（近战距离的近似，唯一实现） |
| `modules\autoattack.lua` | 自动攻击开关模块；对外给只读口 `U.IsAutoAttacking` / `U.IsAttackTargetValid`，`U.MeleeSwingTiming` 的消费者 |
| `core\init.lua` | `U.RegisterUpdate`（节流调度器，金分割相位错开）/ `U.DeferOnce`（推到下一帧执行一次） |

---

## 1. 三条车道与"速度"来源

`swingbar.lua:273-297 ReadWeaponSpeeds`（每 0.5s 跑一次，`EQUIPMENT_INTERVAL`）：

- **主手** = `UnitAttackSpeed("player")` **第 1 个返回**。
- **副手** = `UnitAttackSpeed("player")` **第 2 个返回**，但**必须先过 `U.HasOffhandWeapon()`**。
  - 客户端怪癖（`core\weapons.lua:1-6` 注释 + 官方文档原文）：第 2 个返回是"玩家**远程槽里有武器**就有"，它**绑在槽 18 上**，因此**不能**用来判断副手；`OffhandHasWeapon` 在本客户端**恒返 false**。
  - `HasOffhandWeapon` 真值 = 槽 17 的 `GetInventoryItemLink` → `GetItemInfo` 第 8 返回 `equipLoc ∈ {INVTYPE_WEAPON, INVTYPE_WEAPONOFFHAND}` ⇒ 盾/副手物品/未缓存装备**不会**造出一条副手车道。
- **远程** = 仅当 `U.HasRangedWeapon()`（槽 18 `equipLoc ∈ {INVTYPE_RANGED, INVTYPE_RANGEDRIGHT, INVTYPE_THROWN}`）才读 `UnitRangedDamage("player")` **第 1 个返回**（官方文档：`number — ranged swing time in seconds`）。
- `Positive()` 只认 `> 0` 的数字；读不到就是 `nil`（该车道没有速度）。

`SetLaneSpeed`（`swingbar.lua:246-271`）处理**变速**（急速 / 换装）：

- 事件钟车道：**保留周期时间戳**（装备与激活能给速度，但给不了"第一刀"），新速度为 nil 时清锚。
- 非事件钟车道（魔杖回退）：按**已走比例**重算锚点（`startedAt = now - progress * speed`），不把条子打回 0。
- 变速一律 `ForgetLanePeriod()` —— 学到的周期全部作废，重新学。

---

## 2. 什么时候这三条车道"活着"

`swingbar.lua:351-371 RefreshAttackState`（每 0.08s，`STATE_INTERVAL`）：

```
ranged, _, _, autoShot = U.RangedAttackState()
shotDriven = autoShot or U.HasBowOrGun()          -- 弓/枪/弩 = 事件钟；魔杖 = 否
melee      = U.IsAutoAttacking()                  -- 见 §3
SetActive(main,  melee and not ranged)
SetActive(off,   melee and not ranged)
SetActive(ranged, ranged)
```

- `ranged` = `IsAutoRepeatAction(slot)` 为真（`core\weapons.lua:158-165`）。
- `slot` 由 `FindRangedSlot()` 扫 1..120 格确定：优先"正在 auto-repeat 的格"，其次**按名字**认出的 Auto Shot 格（`Auto Shot / Tir automatique / Автоматическая стрельба / 自动射击`，无英文依赖的图标/子类判据），最后才是"图标纹理 = 槽 18 武器纹理"的通用 Shoot 兜底。
- `U.IsAutoAttacking`（`autoattack.lua:352-369, 413`）= 扫到 Attack 动作格（`IsAttackAction`）后读 `IsCurrentAction`；**"真"总是可信，"假"只有本会话见过一次"真"之后才可信**（否则会把正在跑的攻击切掉）。
- `SetActive`（`:336-349`）：只有 `lane.speed ~= nil` 才可能为真；状态变化时清时钟（事件钟）或置 `startedAt = now`（非事件钟）。

**"事件钟"= 主手、副手（恒定），远程仅在弓/枪时**（`:893-896`、`:354-360`）。魔杖**故意**留在旧的"按速度自走 + wrap"回退上（文件头 `:13-14`：魔杖自己的射击生命周期还没实测过）。

---

## 3. 近战计时：锚点来自战斗日志

### 3.1 锚点事件（`swingbar.lua:1064-1069`）

| 事件 | 处理 | 语义 |
| --- | --- | --- |
| `CHAT_MSG_COMBAT_SELF_HITS` / `_CRITS` / `_MISSES` | `OnMeleeSwing` | **白字命中 / 暴击 / 未命中（含闪避招架）都算一次完成的挥击** |
| `CHAT_MSG_SPELL_SELF_DAMAGE` | `OnSpecialSwing` | "下一刀"类技能（英勇打击 / 猛禽一击） |
| `PLAYER_ENTER_COMBAT` | 内联 | 只在**从未锚定**时给锚（**不算一次挥击**，`swings` 不加） |
| `PLAYER_LEAVE_COMBAT` | 内联 | 两条近战车道失效 |

实测依据（文件头 `:16-37`）：同一把 Worn Axe（`UnitAttackSpeed` 报 2.00）连挥五次间隔 **2.029–2.038s**（均值 2.0345，散布 9ms）；另一轮八次里六次 2.024–2.041 ⇒ **战斗日志是稳定的挥击锚点，但真实周期比报的速度长 1.7% 左右**。`PLAYER_ENTER_COMBAT` 实测比交战第一刀白字早 ~10ms、比攻击开关晚 0.28s ⇒ 它是"挥击标记"而不是"开关标记"（这也正是它能救"被下一刀技能吃掉的首刀"的原因）。

### 3.2 归属：哪只手挥的这一刀

`ClaimMeleeLane`（`:694-711`）：客户端**从不说哪只手挥的**，所以按"自己时钟谁更逾期"认领：

```
score = now - (lane.startedAt + LanePeriod(lane))   -- 正数 = 已过期
```

- 从未锚定的车道**直接拿走**（那是它唯一的起锚机会）。
- 否则**逾期最多者胜**。旧版比的是**绝对距离**（`|now - due|`），会让"还早 0.3s"的车道压过"已晚 0.4s"的车道 —— 现已改成"过期优先"。

### 3.3 特殊攻击（下一刀技能）

`OnSpecialSwing`（`:740-747`）：只认**主手**，且只在 `now - startedAt >= LanePeriod(main) - SPECIAL_SWING_GRACE(0.2s)` 时才当成一次挥击。

- 理由：这类技能会**消耗主手那一刀**，但伤害从"法术通道"报出来；不补这一下，车道会在每次英勇打击/猛禽一击之后白等整整一个周期。
- 技能名/语言相关 ⇒ **故意不做名字匹配**；也**绝不会用它起锚**（未锚定的车道仍然只等真白字）。

### 3.4 周期学习（这一版的核心）

`RecordLaneInterval` + `LanePeriod`（`:156-197`）：

- 每次 `AnchorLane(lane, at)` 都把 `at - lane.startedAt` 当成一个实测间隔记下来。
- **接受带**：`0.9×speed ≤ interval ≤ 1.35×speed`（把翻倍 / 抖动 / 掉线的窗口先挡在门外）。
- **窗口 = 最近 5 个**（`PERIOD_SAMPLES`），**≥3 个**（`PERIOD_MIN_SAMPLES`）才生效，取**中位数** ⇒ `lane.period`。
- **夹取**（`LanePeriod`）：`period < speed` ⇒ 用 `speed`（客户端不可能比报的速度更快）；`period > speed × 1.2`（`PERIOD_MAX_SCALE`）⇒ 取上限；否则用 `period`。
- 中位数而不是平均数 ⇒ 偶发的一次延迟周期被忽略，而不是被追着放大。

> 效果：报 2.00s 的武器，条子按 **~2.03s** 走 ⇒ 不再每个周期提前 20–35ms 到 ready，也不再持续漂移。

### 3.5 绘制：**永不 wrap**

`DrawLane`（`:653-692`），事件钟车道：

```
elapsed = now - lane.startedAt
elapsed = math.min(elapsed, period)     -- ★ 夹住，不是取模
```

- **停在 ready（满格 / 剩余 0.0）**，直到下一次真实挥击事件来重新锚定。
- 为什么：只要 wrap，就会在"移动 / 超距 / 被别的动作延迟"时**凭空造出一次没发生的挥击**（文件头 `:16-26` 说的"invented cycles the client never performed"）。宁可略微超前，也绝不超过一次真实挥击。
- 非事件钟（魔杖）那条才走 `math.mod(elapsed, speed)` 自走。

标签：`string.format("%s %.1f|%.1f", 标签, lane.speed, remaining)`（`FormatLane` `:600-609`）——
**左边写武器自己的速度，右边写剩余**，在 `|` 处切成两个 FontString。
⇒ **标签报的是"报的速度"，条子跑的是"观测周期"**，两者故意不同。

其它两种绘制态：

- 没有速度：`SetMinMax(0,1)`、值 0.4（纯装饰的静态条）。
- 未激活 / 未就绪，但**处于编辑模式（`U.IsUnlocked()`）**：画出 40% 的样子当占位。

---

## 4. 远程计时：`ACTIONBAR_UPDATE_COOLDOWN` 的批次校验

### 4.1 为什么不用更"正统"的信号

文件头 `:8-14`：

- `rangedshot.v1` 抓包发现 **Auto Shot 的激活远早于它第一次原生周期通知**；
- `GetActionCooldown` 全程返回 **0/0/1**（拿不到周期）；
- 伤害到达延迟**不固定**；
- ⇒ 只能用**实测过的 `ACTIONBAR_UPDATE_COOLDOWN` 节奏**当周期信号，并且**排除施法/打断批次**。
- 明确定性：**这是周期信号，不是投射物动画的精确时间戳**。

### 4.2 施法闸门（`:570-574`）

`SPELLCAST_START` / `SPELLCAST_CHANNEL_START` ⇒ `casting = true`；`STOP` / `FAILED` / `INTERRUPTED` / `CHANNEL_STOP` ⇒ `false`。
**每个施法事件都记 `blockedAt` 并把 `generation + 1`**（`InvalidateRangedPulse`）⇒ 让"还挂着的待定射击通知"当场作废。

### 4.3 主流程（`:576-598`）

```
ACTIONBAR_UPDATE_COOLDOWN
  └─ 闸门：模块开着 ∧ ranged 车道存在 ∧ shotDriven
           ∧ not casting ∧ blockedAt ≠ 本事件时间
  └─ RangedAttackState() 必须 active 且有 slot
  └─ 记下 generation = rangedClock.generation
  └─ U.DeferOnce("swingbar.ranged-shot", …)   -- 推到 next driver tick，等事件批结束
        └─ 复核：generation 未变 ∧ 非 casting ∧ 模块仍开着
                 ∧ 仍 active ∧ slot 未变 ∧ 速度仍在
        └─ SetActive + AnchorLane(at) + RefreshRange + UpdateTickRate + Layout
```

- 理由（注释 `:584-586`）：抓包里**打断期间也会来 cooldown 事件，而 stop 事件晚于它** —— 所以必须**让整个事件批跑完再判**，任何 stop / cast / 装备变化 / 换目标都能把它作废。
- 远程的绘制与近战**共用同一套事件钟**（min 夹取、不 wrap）。

### 4.4 弓/枪 vs 魔杖

- `STOP_AUTOREPEAT_SPELL` / `START_AUTOREPEAT_SPELL` 只清远程时钟与 `casting` 标志、立刻刷一次状态（`:1032-1044`）。
- `shotDriven` 变化时才切 `lanes.ranged.eventClock`（`:354-360`）—— **魔杖保留按速度自走的旧回退**。

---

## 5. 距离闸门：只显示"打得到"的车道

`RefreshRange`（`:299-314`，每 0.15s，`RANGE_INTERVAL`）：

```
valid = U.IsAttackTargetValid()     -- UnitExists ∧ ¬UnitIsDead ∧ ¬UnitIsGhost ∧ UnitCanAttack(player,target)
ranged: IsActionInRange(slot)       -- 超程 = 0 ⇒ false；读不到(nil) ⇒ 因为要求 == true，也算 false
melee : U.MeleeInteractRange("target")   -- 读不到(nil) ⇒ 降级按"在范围内"
meleeInRange = valid and MeleeInRange() and not (ranged and rangedInRange)
```

- **近战没有真 API**（`core\compat.lua:1025-1054`）：本客户端 `IsActionInRange` 对近战自动攻击**恒返 1**、从不测距；`CheckInteractDistance` 把所有 `distIndex < 4` 并成一个交互距离、`≥ 4` 直接 false ⇒ 实现里只用 index 1，**只为满足文档签名**。这个距离**比真实武器距离宽一点**（已被接受为近似）：近战车道会**略早**出现，而不是人已经跑进去了还在屏上晃。
- **同一时刻只显示一种武器模式**（注释 `:311-313`）：即使客户端的攻击标志重叠，弓/枪的真实最小/最大射程也**压过**宽松的近战近似。
- 最终车道可见性（`Layout` `:426-438`）：`enabled ∧ speed ∧ ((active ∧ inRange ∧ LaneReady) or unlocked)`。
  - `LaneReady`（`:152-154`）= 非事件钟，或**已经锚定过**（"什么都没观测到"就不画）。

---

## 6. 节拍与性能

- `UpdateTickRate`（`:325-334`）：**开着 ∧ 任一车道 active ∧ 已锚** ⇒ `interval = 0`（**跟随渲染帧**，条子才动得顺）；否则回落到 `STATE_INTERVAL = 0.08s`。
- `Tick`（`:907-932`）内部再分三档：装备 **0.5s** / 攻击状态 **0.08s** / 距离 **0.15s**，然后 `Layout` + 三条 `DrawLane`。
- `U.RegisterUpdate`（`core\init.lua:433-458`）：interval 是"节流秒数"，`0` = 每帧；注册时用**黄金分割小数**给每个消费者一个**相位偏移**，并且**结转溢出**而不是清零 —— 避免同速消费者永远撞在同一帧上（注释 `:419-424`、`:362-372`）。

---

## 7. 对外的只读探针口（不改行为）

- `U.RangedSwingTiming()`（`:633-637`）→ `Now, speed, startedAt, active, shown, rangedInRange`
- `U.MeleeSwingTiming()`（`:641-651`）→ `Now, 主手 speed/startedAt/active/shown, 副手 speed/startedAt/active/shown, meleeInRange, LanePeriod(主手), LanePeriod(副手), 主手 swings 计数`
- 消费者：`autoattack.lua:378-384 MeleeSwingObserved()`（`swings > 0` = "真的在挥"）只用于 `U.AutoAttackState()`（`:748-752`）这个**诊断面**。
  ⚠️ 注释 `autoattack.lua:34-39` 明确记着：曾试图拿它**覆盖**攻击开关状态判定，**已回退** —— 那是"从症状反推"，不是实测，还弄坏了盗贼的普通点击起手。

---

## 8. 已知边界与代价（如实记录）

1. **近战距离是近似**（交互距离 > 真实武器距离）⇒ 车道出现略早。
2. **双持时"哪只手挥的"是推断**（谁更逾期谁认领），可能认错手。
3. **魔杖仍是按速度自走 + wrap**（其射击生命周期未实测）。
4. **远程周期信号 = `ACTIONBAR_UPDATE_COOLDOWN`**，不是投射物动画时间戳；`GetActionCooldown` 在本客户端不可用（恒 0/0/1）。
5. **事件钟不 wrap** 的代价：被打断/超距/延迟的那一刀会让条子**停在满格**直到下一刀真实事件（这是设计选择，不是 bug）。
6. 速度一变（换装/急速）⇒ **学到的周期全部作废**，要重新攒 3 个样本才恢复"实测周期"，之前先用报的速度。

---

## 9. 一句话总览

```
速度 ← UnitAttackSpeed(第1/第2返回) / UnitRangedDamage(第1返回)   [0.5s 刷新，带装备身份校验]
激活 ← IsCurrentAction(Attack格) / IsAutoRepeatAction(远程格)     [0.08s 刷新]
锚点 ← 主副手：战斗日志白字/暴击/未命中 (+ 下一刀技能，带 0.2s 宽限)
       远程  ：ACTIONBAR_UPDATE_COOLDOWN（批次延迟复核 + 施法闸门）
周期 ← 最近 5 个实测间隔 → ≥3 个取中位数 → 夹在 [speed, speed×1.2]
绘制 ← elapsed = min(now - anchor, period)   ★ 永不 wrap，停在 ready
闸门 ← 目标可攻击 ∧ (近战交互距离近似 / 远程 IsActionInRange) ⇒ 只显示打得到的车道
```

---

# 附录 A：与本插件（EvalHelp）的取值 / 计算对比

> 本插件对应实现：`Engine.lua:3773-3900`（计时本体）· `Core.lua:758-768`（速度采集）·
> `EvalHelp.lua:1252-1266`（战斗UI 金色细条）/ `:5099-5110`（状态UI 行）/ `:11592-11602`（事件派发）·
> `Engine.lua:3003-3011`（条件 `swingLeft` / `shotLeft`）· `Engine.lua:3903-4030`（射击探针）。

## A.1 一句话结论

**两边是同一套思路（无计时 API ⇒ 事件锚点 + API 速度），差别在三处**：
本插件是「**一次事件定锚 → 纯推算 → 0.15s 重画**」；UnrealUI 是「**持续观测 → 学实测周期 → 车道活着时每帧画**」。
本插件多出来的东西是 UnrealUI 没有的：**接进规则引擎**（`距下次攻击` / `距下次射击` 条件）与**施法推迟**。

## A.2 逐维度对比

| 维度 | EvalHelp（本插件） | UnrealUI | 谁更好 |
| :-- | :-- | :-- | :-- |
| 主手速度源 | `UnitAttackSpeed` 第1返回（`Core.lua:760`） | 同 | 平 |
| 副手速度 | 第2返回**直接用**，仅用于状态UI 显示「（副手 %.1fs）」 | 第2返回**必须先过槽17装备身份校验** | **UnrealUI**（见 A.4-1） |
| 远程速度源 | `UnitRangedDamage` 第1返回 + `0.1<v<20` 夹取 | 同 + `HasRangedWeapon` 前置 | UnrealUI 略好 |
| 速度刷新 | 每拍 `UPDATE_STATE` 重读 | 0.5s 缓存 | 平 |
| 远程"在射击中" | `IsAutoRepeatAction(wslots[名].slot)`，名字只认 `自动射击/射击/Auto Shot/Shoot` | 扫 1..120 槽 + 隐形 tooltip 取动作名 + 4 语言 Auto Shot 表 + 纹理兜底；弓枪由**装备子类**判定、魔杖单独分路 | UnrealUI（鲁棒 + 分路） |
| 近战"在挥击" | `IsCurrentAction(wslots["攻击"].slot)`（只影响 `st.autoAttack`，不参与计时） | 同族（`U.IsAutoAttacking`）+「假值要见过一次真值才可信」守卫 | 平 |
| 近战锚点事件 | **只有** `CHAT_MSG_COMBAT_SELF_HITS`，且要文本 `^你击中/^你爆击/^You hit/^You crit` | `HITS` + `CRITS` + `MISSES` 三条，**不解析正文** | 各有取舍（见 A.4-4 / A.5-4） |
| 未命中/闪避/招架 | **不锚**（那三条走 `SELF_MISSES`，本插件没注册） | 算一次挥击、照样锚 | UnrealUI |
| 下一刀技能（英勇/猛禽） | **不补偿**（`SPELL_SELF_DAMAGE` 在本插件只用于认"自动射击"） | `OnSpecialSwing`：主手已到/超 due−0.2s 时补锚 | UnrealUI |
| 开战首刀 | 不管（`PLAYER_ENTER_COMBAT` 只进 `st.inCombat`） | 未锚定时用 `PLAYER_ENTER_COMBAT` 起锚（不计挥击数） | UnrealUI |
| 周期 | **一律用 API 报的速度**（近战）；远程有"自校准比值" | **学实测周期**：最近 5 个间隔取中位数、夹在 `[speed, 1.2×speed]` | 各有取舍（见 A.4-5） |
| 远程自校准 | 攒 `dt ÷ API` 比值，样本 ≥4 且中位数落在 `[0.9,1.1]` **之外**才修正（`Engine.lua:3803-3841`） | 不修速度值，改成"用观测周期画、标签仍报 API 值" | 两种思路都成立；本插件更保守 |
| 施法推迟挥击 | ✅ `anchor = max(lastSwing, castUntil)`（`:3789`） | ❌ 没有；靠"不 wrap + 等真事件"容忍 | **本插件** |
| 不 wrap | 天然（`rem` 夹 0，不取模） | 显式设计（`min` 夹取） | 平 |
| 双持归属 | 不区分（一个锚） | 按"谁更逾期"认领 | 本插件够用（副手不参与计时） |
| 距离/射程闸门 | ❌ 没有（条子与射程无关） | ✅ 有（近战交互距离近似 / 远程 `IsActionInRange`） | UnrealUI（信息更真） |
| 重画节拍 | **0.15s**（`UI_TICK`，且只在战斗UI 可见时） | 车道活着时**每帧**，否则 0.08s | UnrealUI（观感） |
| 脱战 / 无锚点 | 条子**仍常显满格「攻击就绪」** | 车道隐藏 | UnrealUI（本插件这条是假信息） |
| 锚点失效 | `st.lastSwing` / `st.lastShot` **从不失效**（换装/离战/换目标都留着） | 变速度就作废周期并清锚 | UnrealUI |
| 接进规则引擎 | ✅ 条件 `距下次攻击`（`swingLeft`）/ `距下次射击`（`shotLeft`），可写「距攻击 < 0.3 就按英勇打击」 | ❌ 纯显示 | **本插件（UnrealUI 没有条件系统）** |
| 取证 | 射击探针（会话内存 32 行 + `EVAL_LOGLINE` 共享环）、报告直接打 Δt 与比值表 | 只读口 `RangedSwingTiming` / `MeleeSwingTiming`（给外部抓包脚本用） | 平（本插件的比值表更适合人眼看结论） |

## A.3 相同点（两边都对、不用改）

1. **速度 API 与返回值位置完全一致**：`UnitAttackSpeed` 主手第1 / 副手第2；`UnitRangedDamage` 第1 是秒/击。
2. **远程与近战是两套独立锚点**，互不覆盖。
3. **都不 wrap 到"凭空多打一刀"**（本插件靠 `rem` 夹 0，UnrealUI 靠 `min` 夹取）。
4. **都在真机量过**：本插件 `1.74.30` 用 `/eh go 射击探针` 实测 8 发（Δt 均值 2.16 vs API 2.09，比值 1.03）；UnrealUI 的 `rangedshot.v1` / `meleeswing.v1` 是两个独立抓包。
5. **都对"读不到"如实降级**：本插件 `nil` → UI 显「—」、条件不满足；UnrealUI 无速度 → 不画。

## A.4 本插件**值得抄**的（按优先级）

### 1. 副手速度必须过装备身份校验（**最值得抄，且直接命中本项目铁律**）
- 现状：`Core.lua:761-762` 直接取 `UnitAttackSpeed` 第2返回写进 `st.atkSpdOff`，**没有校验**。
- 官方文档原文（本仓库 `api_unit.html`）：第2返回是「off-hand swing time **if unit is a player with a weapon in the ranged slot**」
  —— 也就是**槽18 有弓/枪就可能给出第2返回**（UnrealUI 的 `combat.weapon_slots_and_ranged_handoff` 明记此坑，`OffhandHasWeapon` 在本客户端恒 false）。
- 后果：猎人（远程槽有武器）的状态UI 会打出**假的「（副手 %.1fs）」**。只影响显示（副手不参与计时），但属明确的假信息。
- 改法（照抄 `unrealUI\core\weapons.lua:37-40` 的口径）：槽17 的 `GetInventoryItemLink → GetItemInfo` 第8返回 `equipLoc ∈ {INVTYPE_WEAPON, INVTYPE_WEAPONOFFHAND}` 才写，否则置 nil。
- 先核实（不许猜）：用 `/eh go 射击探针 报告` 的 ② 行（已打印主手/副手），在**只有弓、无副手武器**的角色上看第2返回是否有值。

### 2. 锚点要"失效 + 新鲜度"，别再常显「攻击就绪」
- 现状两处：① `st.lastSwing` / `st.lastShot` **从不失效**（换武器、离战、换目标都留着）；
  ② 战斗UI 细条判据只有 `rem and spdBar`（`EvalHelp.lua:1259`），`rem` 被夹成 0 后**永远画满格「攻击就绪」**——脱战后、甚至只是站在城里都常显。
- 后果：**假信息**（"随时能打" ≠ "这一刀就在此刻"），与本项目「查不到 ≠ 没有」「不拿 0 冒充现状」同一把尺子。
- 改法：① 换装（`UNIT_INVENTORY_CHANGED`）/ 离战 / 换目标时把锚置 nil；② 条子加新鲜度闸门（`now - anchor ≤ 2×spd` 或 `st.inCombat`）才画，否则收起或显「—」。
  UnrealUI 的对应概念 = `LaneReady(lane)`（已锚定才有意义）+ 车道按 active/范围显隐。

### 3. 远程锚点事件化（语言无关）——**若俄语客户端在支持范围内，这条是"整条功能失效"级**
- 现状：`EVAL_SHOT_IS` 只认「自动射击 / Auto Shot」**两串文本**（`Engine.lua:3810-3815`）；`EVAL_SHOT_ACTIVE` 只认 `wslots` 里的四个**键名**（`:3861-3870`），而 `wslots` 的键 = 客户端本地化动作名（`Engine.lua:172,185`）。
  ⇒ 在**俄语客户端**（本插件已带 `Locales\ruRU.lua`，属支持范围）两条都命中不了：**射击计时静默失效并退回近战计时**。
- 值得抄的点：**锚点用 `ACTIONBAR_UPDATE_COOLDOWN` 事件 + 批次延迟复核**，识别用多语言名字表 + 装备子类，**全程不看战斗日志正文** ⇒ 语言无关。
- 代价与风险：`ACTIONBAR_UPDATE_COOLDOWN` 在本插件的**事件探针候选表里没有**（`Engine.lua:6515-6550` 那批实测事件里没有它）⇒ **必须先写计数探针确认真伪**（UnrealUI 声称实测过，但不能当本插件的证据）。探针范式现成（`EVAL_SHOT_PROBE_FEED` 那套：事件名计数 + 参数 + 落 `EVAL_LOGLINE`）。
- 同族提示：`EVAL_SWING_EVENT` 的文本判据（`^你击中/^你爆击/^You hit/^You crit`）**同样只在 zhCN/enUS 成立**。这不是本问题独有的坑，而是本插件**所有战斗日志文本解析**（免疫学习、目标施法学习、射击/挥击计时）的共同结构性风险 ⇒ 要修就一次决策：**要么给非中英客户端补文本表，要么逐步换事件/结构化通道**（`COMBAT_TEXT_UPDATE` 已被本插件探针实测到 56 次、`arg1=DAMAGE`，正是"不解析文本就能拿伤害"的候选，见 `Engine.lua:6544,6577`）。

### 4. 锚点补 `MISSES`（小改，但**不能照抄"不解析正文"**）
- 现状：被闪避/招架/未命中的那一刀不进锚点。影响面**小**（不学周期 ⇒ 不累积漂移；`swingLeft` 在 ready 上多停一个周期，而"0 = 已就绪"本来就是对的语义）。
- ★但抄的时候要点在**两边各取一半**：本插件 `addons\EH_Damage` 的真机取证明确记着，**非伤害文本也会落到 `CHAT_MSG_COMBAT_SELF_HITS`**（例：「你施放毒蛇钉刺失败：尚未恢复」「Cat的撕咬没有击中雌性草原狮。」）⇒ UnrealUI 那种"来者不锚、统统当挥击"在本客户端**有误锚风险**，而本插件现有的文本闸门正好挡着它 ⇒ **事件名多挂一条 + 保留"这条文本确实像一次挥击"的闸门**。

### 5. 周期学习（可选，收益与成本都中等）
- 现状：近战直接用 API 报的速度；已知实测偏差约 1.7%（UnrealUI 量到 2.00 报值 vs 2.03 实测）⇒ 本插件表现为「就绪」提示早 20~35ms，不累积。
- 对**显示**影响很小；对条件 `距下次攻击 < N` 才有意义（`N = 0.3` 时那 30ms 就是 10% 的窗口）。
- 若要抄，建议只搬最稳的两条：**接受带**（`interval` 超出 `0.9~1.35×speed` 就丢弃）+ **夹取**（周期夹在 `[speed, 1.2×speed]`）；中位数窗口可后置。
  ★并且**统一到一处**：本插件已有远程自校准（`SHT`），别再造第三套 —— 建议一个 `EVAL_PERIOD_LEARN(kind, dt, apiSpeed)` 同时服务近战/远程。

### 6. 呈现层（要动结构，收益是观感）
- 现状 0.15s 重画 ⇒ 条子是**跳**的；UnrealUI 在"车道活着"时**升到每帧**、否则回落 0.08s。
- 本插件的 tick 是**整块战斗UI 一个节拍** ⇒ **不要**把主 tick 改成每帧（会拖上血条/能量/技能行整块重画）。正解 = **给 swing 条单独一个每帧小帧**（只在有数据且在战斗时挂、否则**真摘** —— 正是本项目「用的时候才启用、不用就关闭」那条铁律的形态）。

## A.5 **不建议抄**的

1. **三条车道 / 可拖动 mover / Forever 图集美术** —— 定位不同：本插件是规则引擎 + 信息UI，不是 UI 皮肤。
2. **双持"逾期优先"归属推断** —— 本插件副手不参与计时，抄了只增加维护面。
3. **把 `OnSpecialSwing` 做成"按技能名匹配"** —— UnrealUI 自己都刻意不做（名字/语言相关）。
4. **丢掉本插件自己的两条优势**：`anchor = max(lastSwing, castUntil)`（施法推迟挥击，UnrealUI 没有）与 `swingLeft/shotLeft` 条件口（UnrealUI 无条件系统）。抄别家时这两条要保住。

## A.6 建议的落地顺序

| 步骤 | 内容 | 风险 | 前置核实 |
| :-- | :-- | :-- | :-- |
| 1 | 副手速度加装备身份校验（A.4-1） | 极低（一处取值 + 一处显示回落） | `/eh go 射击探针 报告` ② 行在"只有弓"的角色上取值 |
| 2 | 锚点失效 + 条子新鲜度闸门（A.4-2） | 低 | 无 |
| 3 | 锚点补 `MISSES` + 保留文本闸门（A.4-4） | 低 | 已在案（`SELF_MISSES` 在本客户端存在：`EH_Damage` 与射击探针都在用） |
| 4 | 远程锚点事件化（A.4-3） | 中（新探针 + 改锚点通道） | **先探针确认 `ACTIONBAR_UPDATE_COOLDOWN` 真伪**；确认俄语客户端是否在支持范围 |
| 5 | 周期学习（A.4-5）/ swing 条独立每帧帧（A.4-6） | 中 | 无 |

★ 全部改完仍按本项目纪律：只跑 `node luacheck.js` + `node sync_game.js`，**不许声称"过了全套闸门"**，真机实测才是最终判据。
