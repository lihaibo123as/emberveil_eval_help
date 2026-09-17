# EvalHelp — All-Class Casting Helper

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class casting helper addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **49 condition types** (grouped dropdowns; the member-picker row additionally offers 4 "candidate" conditions) × multiple key-bound profiles, all configured visually, for any class. Three more built-in pages: a **Toolbox** (merchant / social / quest automation), **Data search** (quests / items / mobs·NPC + a world-map annotation layer, requires UnrealQuest) and an **Icon library** (the client-built-in macro icons: grouped, hover shows the path, searchable and pageable).

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions, plus text import/export for sharing |
| 🧩 **Case templates** | config window, one-key macro tab, bottom `[Case Templates]` | **11 groups / 27 entries** ready-made profiles (grouped by class) → **grouped two columns + wrapping within a group**; one click to import, hover to see what's inside |
| 🧰 **Toolbox** | config window, tab 3 | Merchant assistant (auto-repair / auto-sell grey / buy and discard by name) + party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices**) + auto quest accept & turn-in (hold Shift to pause temporarily) + quest notification channel |
| 🗺️ **Data search** | config window, tab 4 | Quest / item / mob·NPC / object search with instant results and unlimited drill-down; a **world-map annotation layer** (16 categories redrawn live as the map changes) and one-click pinning from any row with coordinates (requires UnrealQuest) |
| 🖼️ **Icon library** | config window, tab 5 | The client's built-in macro icons grouped by prefix, hover shows the path, searchable and pageable; plus a "used by this addon" group (listing the icons this addon uses) |
| 📊 **Combat info UI** | `/eh ui` | HP / power / target bars + profile switcher row + skill icon row (lit gold = conditions met, click to edit) |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.71.10** | 📐 Combat-info UI profile row: measured widths + wrapping | Reported: "some profiles overflow the width" — the row used to split the width **equally**, so long names overlapped their neighbours → now each cell is sized by its **measured name width**, wrapped greedily, stretched to fill the row, and the text is width-clamped; ★renames/adds re-layout automatically (signature compare), no measuring in the tick |
| **1.71.9** | ▲ Reorder buttons are real triangles now + 🖼️ icon library 6 → 9 rows per page | The skill list's reorder/scroll buttons changed from `^`/`v` to **real triangles ▲/▼** (the caret looked like a dash, and `v` was just a letter); the icon library now shows **108 → 162 icons per page** (18 columns × 9 rows, +102px of grid height) |
| **1.71.8** | 🧩 Case-template window: grouped two columns + wrap within a group | Group titles and profile buttons **run to the right on the same line and wrap back to this column when they no longer fit**; **a group is the smallest indivisible unit** (split into two columns in order, the split point being the one that **minimises the difference in row count** — no greedy fill); every group starts on a new line; with the Chinese window the column width is 310, the 11 groups lay out as 8+7 rows, and the window is 660×240 |
| **1.71.7** | 🧑‍🤝‍🧑 Party/raid case-template audit (designated skill + party/raid-member conditions) | 17 party/raid templates went from "target-selection row + candidate conditions" (two rows working together) to "**designated skill + party/raid-member condition**" (one self-sufficient row: the condition scans members and switches target itself); ★member conditions must come first on a row; the shaman Healing Wave threshold corrected along the way; the audit landed as **4 automatic gates + an end-to-end run** (executing the template text for real) |
| **1.71.6** | 🧩 Case-template window moved to a flow (auto-wrapping) layout | Group titles and buttons **run to the right on the same line and wrap back to the left edge when they no longer fit**; button widths measured with `GetStringWidth()`; the window height is computed from the content (660×180); ★real data never produced a wrap → a **synthetic-data** assertion entry point was added to force the wrapping path |
| **1.71.5** | 🧹 Case templates: "one-key party dispel / one-key raid dispel" added | Covers both the **magic + disease** chains (priest = Dispel Magic + Cure Disease; paladin switches to Cleanse; druid/mage/shaman switch to poison/curse); ★the two-column split went from the greedy "fill until past halfway" to **walking every split point and taking the smallest row-count difference** |
| **1.71.4** | 🧩 Case-template window reworked to two columns + 📚 templates expanded to 11 groups / 25 entries | The window is widened to share its source with the config window and split into two columns (**split by class group**, a group is never broken apart); a golden "!" tooltip added to the title; four new groups (priest / druid / warlock / shaman) plus a party/raid utility group; ★the "class filter" now also supports **candidate conditions** (parsing / export / editor all opened up together) |
| **1.71.3** | 🛑 Stop attack + 🤝 Follow + 📤 share/receive rework + 🔇 channel mute + 🛍 auto-buy rework + 🖼 icon-library tab + 🧑‍🤝‍🧑 candidate conditions | One click stops [casting + Auto Shot + wand auto-repeat + melee auto-attack] (≈ pressing ESC); `FollowByName` follow (including a fix for the **full-width colon** silently breaking things); share drops the "raid" channel, the receiver keeps only the newest transfer + four caps + rate-limited notices; mutes "joined/entered/left channel" notices; auto-buy reworked to **buy in batches + verify each purchase + four-way clamping** ("buy amount" = an absolute target); a 5th tab "Icon library" added; dedicated icons for the "target selection:" family + honest logging for party-member selection; **candidate conditions + picking people by comparator**; "class multi-select / subgroup multi-select" added to party/raid-member conditions |
| **1.71.2** | 🧙 Condition regroup + config-window cleanup + 📂 templates out of the script | Casting-family conditions renamed and consolidated into the **Skill state** group (Casting / Cast time / Cast remaining ‖ T:Casting / T:Cast time / T:Cast remaining); the duplicate **[Receive]** button removed, the "Toggles" heading hidden, **[Share]** got a step-by-step tooltip; the example-template library moved to per-class files under `examples/`; ★a batch of **silent-failure** bugs fixed (an unresolvable aura is now reported instead of treated as "absent", exported conditions are no longer dropped, the 1px bar shadow, the test stub sharing one position) |
| **1.71.1** | 🩺 Party/Raid scan | One key scans your party/raid and picks by condition (lowest HP/mana, has magic debuff, missing a buff) → switches target → the spell lands on them |

> 📜 Detailed per-version notes live in **[CHANGELOG.md](CHANGELOG.md)**; earlier history is in the git commit log.

## 💡 Practical Scenarios

> **Buff classes: one key to re-buff specific nearby classes** — a priest re-applying Fortitude to raid members one by one, a druid pawing the whole raid, a mage handing out Intellect — one macro key does it all: no more clicking teammates, no more remembering who's still missing it.

```
# 方案: 一键补韧（牧师示例——配置窗 [导入导出] 直接粘贴即用）
- 真言术:韧 | 非战斗 & 选取目标:最近友方 & 目标职业:战士/盗贼/猎人
```

| Key point | Explanation |
| :-- | :-- |
| 🎹 **Key rhythm** | Just spam the key — the first press's `选取目标:最近友方` instantly switches your target to a nearby teammate (a side-effect condition); by the second press the state has refreshed and the class matches → Fortitude goes out |
| 🧩 **Condition combo** | `目标职业` multi-select = OR relation — tick whichever classes you want to buff; `非战斗` prevents accidental target switching mid-combat |
| 🎯 **Designated-MT variant** | `真言术:韧 | 非战斗 & 选取目标:指定名称:主坦名字` (v1.29.0: the name dropdown offers the last 5 targets, or ✎ custom input) |
| 🔄 **Rotating targets** | "Nearest friendly" picks by distance — standing still keeps buffing the same person; take two steps to get a different nearest target and rotate through everyone |

> **Hunters / warlocks: one-key pet command** (v1.29.0+ special skill "pet command", no action slot needed):
> ```
> # 方案: 宠物助手
> - 宠物:攻击 | 战斗中 & 可攻击
> - 宠物:被动姿态 | 非战斗
> - 宠物:跟随 | 非战斗
> ```
> Pet attacks automatically when you enter combat and heels when you leave — the 8 commands (attack / follow / stay / stop attack / three stances / dismiss) are listed in the [CHANGELOG](CHANGELOG.md).

> **One-key consumables / gear swap** (v1.32.0+ special skill "item use" — the editor's second-level dropdown live-scans your bags, with icons and counts):
> ```
> # 方案: 一键补给
> - 物品:弱效巨魔之血药水 | 无buff:再生     ← 身上没有「再生」就喝一瓶
> - 物品:烤鹌鹑 | 无buff:进食充分           ← 没有「进食充分」就吃一口
> ```
> Buffs from potions/food (Regeneration, Well Fed…) can be picked directly in the "self missing-buff" condition dropdown: ○ = currently active / ◇ = seen once and remembered forever (across sessions).
> Gear swap works the same way: `物品:夜幕 | 非战斗` — UseContainerItem on equipment auto-equips it (unbound BoE pops a confirmation first); one key to swap weapons/trinkets.

## UI Preview

**Config window · Global tab** (`/eh cfg` or the EH icon next to the minimap): log / UI toggles + built-in help

![Config window · Global tab](preview/main.png)

**Config window · One-key macro tab**: left profile bar (multiple profiles ≤12, click to switch / right-click to rename) + skill list (order = priority, checkbox = enabled, conditions visible at a glance) + [Add Skill] / [Import-Export]; bottom row = three feature toggles + [Templates] / [Share] / [Close]

![Config window · One-key macro tab](preview/cfg.png)

**Case-template window** (bottom of the one-key macro tab, `[Case Templates]`): 11 groups / 27 ready-made profiles grouped by class, laid out as **two columns of groups with wrapping inside each group** — one click imports a profile, hover shows its contents

![Case-template window](preview/skill_tpl.png)

**Skill editor** (opened via [Edit] or by clicking a skill icon): per-row independent condition editing — condition type / params all chosen from dropdowns (49 condition types, plus 4 "candidate" conditions reserved for member-picker rows; grouped as self / target / aura / party·raid member / skill), relation column toggles & (all-in-group) / | (any-group), live preview

![Skill editor](preview/skill_doif.png)

**Skill two-level dropdown · four kinds** (a skill row in the editor = `[Category▾][Item▾]` side-by-side double dropdown, options with icons):

- **Character skills**: whitelist + a scan of every skill on your action bars
- **Pet commands**: 8 pet commands (direct Pet API calls, no action slot), command icons self-learned from the pet action bar
- **Target selection**: 9 switch modes (nearest enemy / last target / target's target / by name / clear target…); the macro switches target first, then acts
- **Item use**: live bag scan (with icons + counts) + custom name — consumables used directly, equipment auto-equipped

**Aura checks (4 types)**: self buff / target debuff / target buff / self debuff (yes/no toggle, live items ◆○●▲) — `无buff:再生` drives one-key potion drinking, `无目标buff:奥术智慧` drives buff rounds:

**Combat info UI + Status info UI** (`/eh ui` / `/eh st`): HP / power / target bars + profile switcher row + skill icon row (hover tooltip shows trigger conditions, lit gold = conditions currently met, click an icon to open its editor); the status window shows all state variables live + the recent-cast log (per-cast skill / target / per-condition √/× verdicts)

![Combat info UI and status info UI](preview/info.png)

**Toolbox (Tab3)**: merchant assistant (auto-repair equipment / auto-sell grey items / auto-buy and auto-discard specified items) + party & social (auto-confirm role check / hide guild member login notifications / **hide "joined·left channel" notices**) + auto quest accept & turn-in (optionally paused while holding Shift) + quest notification channel (off / self / say / party)

![Toolbox](preview/tools.png)

> ⚠️ **Requires** the **UnrealQuest** addon — every record shown here (quests / items / mobs / NPCs) comes from its database. If it is missing or disabled, this tab shows an installation guide instead and hides the controls.

**Data search (Tab4)**: four search kinds — quest / item / mob·NPC / object; type to search (top 10 matches); unlimited drill-down, and hovering an item row shows the in-game item tooltip

**Data search · details and drill-down**: quest / item / mob details — objectives and description, start / end NPC, required items; every link can be clicked to drill further, and rows with coordinates carry a map icon at the end

![Data search · quest details](preview/dataset_search.png)

**Data search · map annotations**: the "Map annotations (N)" control = master toggle + category multi-select (16 categories: 5 gathering nodes + 11 town services, with all-on / all-off shortcuts); checked categories are drawn live as the map changes

![Data search · map annotation categories](preview/dataset.png)

**Data search · map pinning**: click the map icon at the end of a row to open the world map on that zone; hover a pin to see what it holds (e.g. a vein's container drop table)

![Data search · map pinning](preview/dataset_map.png)

## Quick Start

1. Drag the skills you want onto your action bars (any class — the plugin recognizes whatever is on your bars).
2. In game, run `/eh go rescan` so the plugin learns the slots (`/eh go` shows the scan result).
3. Create a macro with the one-line body `/run EVAL_GO()`, drag it onto a key, and spam away.
4. Start from a **case template**: open `/eh cfg` → one-key macro tab → [Import/Export] → [Case Templates], pick your class and import — then tweak thresholds via the golden EH icon by the minimap; `/eh debug` shows the decision reason for every key press in chat.

## Installation

**Option 1: download a release (recommended)** — grab the latest `EvalHelp-vX.Y.Z.zip` from the [Releases page](https://gitee.com/xeval/emberveil_eval_help/releases) and extract it into `Interface/AddOns/` (after extraction it should look like `AddOns/EvalHelp/EvalHelp.toc`):

```
https://gitee.com/xeval/emberveil_eval_help/releases/download/v1.24.1/EvalHelp-v1.24.1.zip
```

**Option 2: clone the source** — `git clone git@gitee.com:xeval/emberveil_eval_help.git`, put the whole directory into `Interface/AddOns/` and make sure the folder is named `EvalHelp`.

Directory layout:

```
Interface/AddOns/
└── EvalHelp/
    ├── EvalHelp.toc     ← folder rule: Folder/Folder.toc
    ├── EvalHelp.lua
    └── README.md
```

## Command Reference

| Operation | Effect |
|---|---|
| `/eh` or `/evalhelp` | Print one status snapshot to the chat frame immediately |
| `/eh log` | Toggle "write to log file" (UELog, default on) |
| `/eh auto` | Toggle "auto-print on entering/leaving combat" (default off) |
| `/eh ui` | Toggle the combat info UI (HP / power / target bars + status row + skill icon row) |
| `/eh st` | Toggle the status info UI (live overview of Cat-style state variables) |
| `/eh go` | One-key macro: recognized skill slots + cooldown readiness overview (the legacy `/eh war` command group still works) |
| `/eh go rescan` | Rescan the action bars (run once after dragging skills onto bars) |
| `/eh wdebug` or `/eh debug` | Debug log toggle (decision reason per key press: skip reasons / trigger trace) |
| `/eh cfg` or the minimap EH icon | Open the config window (log toggles / one-key toggle / threshold sliders) |
| `/eh help` | List commands |
| macro `/run EVAL_HELP()` | Status-log function entry |
| macro `/run EVAL_GO()` or `/run EVAL_GO(0)` | One-key macro entry (0 or no argument = the currently active profile) |
| macro `/run EVAL_GO(2)` or `/run EVAL_GO2()` | Functional profile call: directly trigger profile 2 (index 1-12 or a profile name `EVAL_GO("武器战")`) without switching the active one — bind different profiles to different keys |

## Combat Info UI (/eh ui)

- HP bar (green→red gradient + numeric percentage), power bar (rage red / mana blue / energy yellow / focus orange), target bar;
- Status row: in combat / out of combat · stance · auto-attack toggle;
- Skill icon row: driven by the active profile — lit = ready or active, shows cooldown seconds while cooling down;
- **Hold the title bar to drag** it anywhere (position saved to SavedVariables, restored on relog); mousewheel zoom 0.5~1.6 (full-frame rebuild —
  this client's SetScale has a hit-region drift quirk);
- OnUpdate refreshes every 0.15s; no refresh while hidden.

## Config Window (/eh cfg, UI modeled on the UnrealQuest settings panel, tabbed)

- Dark window with golden border, draggable title bar (position memory), "Close" button at bottom-right;
- **Tab "Global"** (not class-related): logging (write log file / auto-print on combat change), UI (combat info UI / status info UI toggles), help (getting-started tips);
- **Tab "One-key macro"** (window 560×420, wider for EN/RU): **multi-profile skill editor** — left profile bar (up to 12 profiles, [+] to create, click to switch) + global toggles (**Enable one-key macro** / auto attack (priority: Auto Shot > Shoot (wand) > melee, with range check and auto-downgrade) / debug log) + **active-profile dropdown selector** (expands all profiles; fully linked with the profile bar / combat UI profile row / Shift+macro press); right side: skill rule list (order = priority, checkbox = skill toggle, [Up] reorders, [Edit] opens the skill editor, [Del] removes) + the **[Add Skill]** button at the list's top-right (opens the editor directly to add — skill picked from a dropdown, conditions configured row by row, saved straight into the list);
- **Skill editor** (opened via [Edit] or clicking an icon): **every picker is a dropdown** (skill name / condition type / comparator / stance number / buff·debuff skill names — click to expand the full list, pick to use; the dropdown panel is generalized as the global widget EVAL_DD_OPEN) + enable checkbox; **per-row independent condition editing** — each row = [relation][condition type][param][result preview][delete]; the relation column toggles `&`/`|` on click (first row is fixed "when"); the condition-type dropdown offers 28 types grouped as self / target / aura / skill (numeric / boolean / stance / buff / debuff / ready / usable / not-queued / has-target / target relation / target class / combo points…); params vary by type: numeric = comparator dropdown + [-][+] steppers, boolean/flag = yes/no cycler, stance = yes/not + stance-number dropdown, aura = skill-name dropdown (with appended live items: ◆ current target debuffs / ○ current self buffs — picking one learns its name→texture mapping into the config, so non-action-bar debuffs applied by mobs also match afterwards; you must have a target selected before opening the dropdown to get live items), target selection = target-kind dropdown (nearest enemy / nearest friendly / nearest party / nearest raid / last enemy / last target / target's target / by name / clear target; **by name** pops a name dropdown after selection = last 5 enemy names + ✎ custom-input popup — a rule without a name set never fires), target class = **multi-select dropdown** (hunter / priest / mage / warlock / shaman / rogue / warrior / druid; click to toggle √ without closing the panel; multi-select is an OR relation — compared against UnitClass English tokens, stable across languages); **target selection is a side-effect condition** — when it evaluates true it immediately switches your current target (always passes), used for rules like "pick the nearest enemy before charging"; [+ Add Condition] appends a row (up to 8); a live preview of the condition string sits at the bottom, [Save] writes back to the profile;
- **Condition syntax**: `怒气>30 & 战斗中 | 非战斗` — `&` = all-in-group, `|` = any-group; supports 怒气/目标血/自身血/能量%/进战/连击 + comparators (连击 = GetComboPoints, rogue/druid only, always 0 for other classes), 战斗中/非战斗/可攻击/可流血/精英/Boss/目标战斗中/普攻/Alt/Shift/Ctrl, 姿态N/非姿态N, 无buff:名/有buff:名/无debuff:名/有debuff:名 (with stack thresholds `有debuff:破甲攻击>=3` / `无debuff:破甲攻击<3`, 1.31.0), 就绪/可用/未排队, 选取目标:种类 (e.g. `选取目标:最近敌人`, `选取目标:目标的目标`, `选取目标:指定名称:嗜血者` — kinds match the editor dropdown), 目标职业:名/名 (e.g. `目标职业:战士/法师`; separators `/` `、` `,` all work — `|` cannot separate classes because it is the group-OR separator; English tokens like `tClass:WARRIOR/MAGE` are also accepted), `!` prefix negates;
- **Profile command fallback**: `/eh go list` / `/eh go add 技能 条件` / `/eh go del N` / `/eh go newprof 名` / `/eh go prof N`;
- **Profile rename**: **right-click** a sidebar profile button → **rename popup** (input box + golden echo line mirroring what you type in real time — you can see your text even if the input box doesn't render; Enter/OK applies, Esc/Cancel closes); command `/eh go rename 新名` (renames the active profile);
- **Profile delete**: [Del] next to a profile button (**two-step confirm**: click again within 5 seconds, red highlight warning); command `/eh go delprof N` (defaults to the active profile); at least one profile is always kept; the active index auto-shrinks after deletion;
- **Profile import/export (md text)**: `/eh go io` or the [Import/Export] button on the one-key macro tab — the window includes a fallback preview area (visible even if the EditBox doesn't render) + a config-file path hint (if you can't copy: profiles are auto-saved to `%LOCALAPPDATA%\Azeroth\Saved\Account\<account>\SavedVariables\EVAL_HELP.lua`, fresh after logging out — open in Notepad and copy); export = current profile → md text, all selected (Ctrl+C to save as .md and share); import = paste a whole profile text and click "Import as new profile" (replaces the current one if all 12 slots are full); **[Case Templates]** opens the class-grouped template library for one-click import (Arms-warrior template first); a `!` before a skill name = disabled;
- Sliders apply in real time and auto-save; the selected tab is remembered too (cfg.cfgTab).

## Player State Table EVAL_HELP_STATE (modeled on Cat's global-variable design)

Refreshed once per macro-key entry / UI heartbeat / target-change event; macros only read variables and never call APIs:

| Field | Meaning (Cat counterpart) |
|---|---|
| hp/hpMax/hpPct | Player health |
| power/powerMax/powerPct/powerType | Power (0 mana, 1 rage, 2 focus, 3 energy) |
| inCombat / combatTime | Combat state / seconds in combat (MPInCombat/MPInCombatTime) |
| formIndex / form | Current stance |
| alt / shift / ctrl | Modifier keys |
| autoAttack | Auto-attack toggle (MPAutoAttack) |
| hasTarget / targetName / tLevel | Target basics |
| tHp / tHpMax / tHpPct | Target health |
| canAttack | Target attackable = exists + not dead + UnitCanAttack |
| canBleed | Can bleed (MPTargetBleed: elementals/mechanicals excluded + black/white lists) |
| tCreatureType / tClassification | Creature type / classification |
| isBoss / isElite | Boss / elite (MPIsBossTarget) |
| class / race / level | Class / race / level |

The bleedable list can be extended at runtime: `/run EVAL_BLEED_BLACKLIST["怪名"]=true` (or WHITELIST to force bleedable).
One-key macros for other classes can simply call `EVAL_HELP_UPDATE_STATE()` and read the `EVAL_HELP_STATE` fields.

## Configurable Skill-Casting Rule Engine (EVAL_RULE_RUN)

Each skill = one rule: `{ skill="技能名", when={...conditions...}, why="日志原因" }`, evaluated in order; the first rule that fully passes fires.

| Condition | Meaning | State source |
|---|---|---|
| combat=true/false | In / out of combat | inCombat |
| combatTime={">",3} | Seconds in combat | combatTime |
| power={">",30} / powerPct | Rage/energy value, % | power/powerPct |
| hpPct={"<",50} | Own HP % | hpPct |
| tHpPct={">",10} | Target HP % | tHpPct |
| canAttack=true | Cast target: hostile & attackable | canAttack |
| canBleed=true | Target can bleed | canBleed |
| isBoss / isElite | Target classification | isBoss/isElite |
| tInCombat | Target in combat | tInCombat |
| form=1 / formNot=1 | Stance | formIndex |
| alt/shift/ctrl=true | Modifier keys | alt/shift/ctrl |
| autoAttack | Auto-attack toggle | autoAttack |
| hasBuff/noBuff="战斗怒吼" | Own buff present/absent | playerBuffs |
| hasDebuff/noDebuff="断筋" | Target debuff present/absent | targetDebuffs |
| ready=true | Cooldown ready (skill side) | GetActionCooldown |
| usable=true | Usable — Overpower-type (skill side) | IsUsableAction |
| notQueued=true | Not queued into the next auto-attack | IsCurrentAction |

Usable directly in a macro too: `/run EVAL_RULE_RUN({ {skill="压制", when={usable=true}} })`
Conditions that can't be done: interrupting a target's cast (the client has no UnitCastingInfo), distance, swing timing.

## One-Key Macro (/run EVAL_GO())

Drag the skills you want onto your action bars first, then `/eh go rescan` so the plugin learns the slots.
Each key press performs exactly one action: rules are evaluated top to bottom and the first skill whose conditions all pass is cast.
Every action is written to the log file; with `/eh debug` on, the chat frame shows why each skill was skipped — handy for tuning thresholds.

## Development Notes (reference: OneJudge / EmberveilQoL / Cat)

1. Read SavedVariables only after VARIABLES_LOADED; OnEvent event names come in three compatible forms (1st arg / 2nd arg / global event);
2. Predicate functions return true/false/nil (not 1/nil) — use loose truthiness checks;
3. Addons cannot call Protected functions (CastSpellByName etc.); casting goes through UseAction(action slot);
4. UI building blocks: texture-fill bars instead of StatusBar; font fallback FZLBJW→FRIZQT→ARIALN; SetScale has quirks — zoom via rebuild;
5. Divide saved drag coordinates by GetEffectiveScale; pcall EnableMouseWheel throughout;
6. UnrealQuest ClientAPI field-tested additions: solid-color textures use Interface\Buttons\WHITE8X8 + SetVertexColor;
   **no Slider widget** (hand-rolled track Frame + thumb Button + RegisterForDrag);
   the drag recipe includes a two-step warm-up (StartMoving→StopMovingOrSizing→StartMoving);
   the minimap button's parent must be UIParent, not Minimap — anchor chain Minimap→MinimapCluster→UIParent;
   buttons need RegisterForClicks("LeftButtonUp"); hover highlight via OnEnter/OnLeave border-color changes;
7. **Drag handles must be Buttons** (CreateFrame("Frame")'s OnDragStart never fires on this client — the root cause of un-draggable title bars);
   raise with SetFrameLevel(+10), **never strata** (a documented failed approach);
   on drag start SetMovable(true) + the two-step warm-up; StopMovingOrSizing on release.

Log files: `%LOCALAPPDATA%\Azeroth\Saved\Logs`
Config save: `%LOCALAPPDATA%\Azeroth\Saved\Account\<your account>\SavedVariables\EVAL_HELP.lua` (written on logout / reload)

## Self-Rescue (read this first when something's wrong)

1. **`/reload` first**: skills not recognized, UI glitches, just updated addon files — a reload fixes the vast majority of cases (your config is saved and won't be lost);
2. Moved skills around / dragged new ones onto bars → `/eh go rescan` to rescan;
3. Want to watch the decision process → `/eh debug` (why each skill fired or didn't, per-condition √/×);
4. Still stuck → file an Issue at <https://gitee.com/xeval/emberveil_eval_help.git> (attaching an `/eh st` status screenshot + the log file helps a lot).

## Contributing (welcome aboard!)

- Repository: <https://gitee.com/xeval/emberveil_eval_help.git> (after `git clone`, symlink or copy `EvalHelp/` into `Interface/AddOns/` and you're ready to develop and debug);
- **Developer guide**: see `DEVELOPMENT.md` (architecture map / field-tested UI recipes for this client / rule engine & profile data structures / the mandatory syntax check before committing);
- **AI collaboration memory**: `CLAUDE.md` is this project's AI development memory (AI assistants such as DeepSeek Harness / Claude Code can read it to get up to speed fast);
- Workflow convention: bump the version number on every change (lua header comment + `local VERSION` + toc, three places in sync), and run `node luacheck.js` for a full syntax parse after editing;
- Extending to new classes: skills come from **action-bar scanning** — anything dragged onto your bars is recognized, so there is no per-class skill whitelist; the rule engine / profiles / UI are all class-agnostic;
- This addon is developed with **DeepSeek Harness AI** assistance — you're welcome to bring your own AI along too.

## Acknowledgements

- Field-tested UI recipes from: UnrealQuest (ClientAPI.lua); state-variable design from: Cat (TurtleWoW); original reference: OneJudge.
- Thanks to every player who tested and gave feedback.
