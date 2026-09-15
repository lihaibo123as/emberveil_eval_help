# EvalHelp — All-Class Casting Helper

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class casting helper addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **28 condition types** (grouped dropdowns) × multiple key-bound profiles, all configured visually, for any class.

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions, plus text import/export for sharing |
| 📊 **Combat info UI** | `/eh ui` | HP / power / target bars + profile switcher row + skill icon row (lit gold = conditions met, click to edit) |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.52.0** | 📏 Auto-attack range check | Auto Shot / wand out of range (IsActionInRange=0) now auto-falls back to melee auto-attack — point-blank hunters no longer swing their bow at thin air |
| **1.51.0** | 🎯 Shooting-state conditions | New conditions `自动射击` / `魔杖射击` (yes/no toggle); also fixed the old bug where `!` negation silently failed for all boolean conditions |
| **1.50.0** | 🏹 Auto attack | "Auto auto-attack takeover" renamed to "Auto Attack" + priority: Auto Shot > Shoot (wand) > melee auto-attack, auto-downgrades when unavailable, with hover tooltip |
| **1.49.3** | 🚑 Cancel-casting fix | SpellStopCasting is Protected in this client (direct addon calls do nothing) → rerouted through a RunScript chat script on the same path |
| **1.49.2** | 🔍 Leftover audit | Takeover generalized (hunter Auto Shot now works) + rage/stance logging made dynamic + duplicate T_RANGE definition removed + leftover file cleanup |
| **1.49.1** | ▶️ Empty conditions fire directly | A skill with no conditions now executes unconditionally (old behavior: empty-condition skills never fired) |
| **1.49.0** | 🎯 Enemy pre-selection removed | Pressing the macro no longer grabs the nearest enemy first — it fought with rules like `选取目标:最近友方`; enemy selection is fully handed to rules |
| **1.48.0** | 🧹 Whitelist cleared | Skill/param dropdowns are now pure action-bar scans — mages no longer see warrior skills; fresh-install default profile is empty (start from a case template) |
| **1.47.0** | 🏹 Character actions expanded | Added Cancel Casting / Auto Shot / Shoot; stances accept an index (`姿态:2`); fixed the coupling between auto-attack state and the takeover toggle |
| **1.46.0** | 🧩 Icon rows merged | Combat UI's two icon rows merged into one strip below the profile row (8 per row, wraps up to 16); fixed the all-? icon table-reference bug after rescan |
| **1.45.1** | 🔧 Checkbox alignment | Config checkboxes and labels now share a centerline anchor (the old boxes sat visibly too low) |
| **1.45.0** | 🎯 Profile-driven display | Combat UI skill icon row / rescan report / status overview all follow the active profile — the old fixed warrior skill list is retired, truly all-class |
| **1.44.1** | 🛟 Macro entry fallback | EVAL_GO no longer pops a nil red error when the engine isn't fully loaded; it now prints /reload and addon-enable troubleshooting tips in chat |
| **1.44.0** | 📋 Case templates | Import popup gains a "Case Templates" menu grouped by class — click to import directly (Arms-warrior template first); fixed the leftover import cap + missing condTrim bridge |
| **1.43.0** | ⚔️ Stance-swap skill | New character action `姿态:X` — switches the stance bar directly without occupying an action slot (CastShapeshiftForm is not protected), guarded when already active |
| **1.42.0** | 📚 12-profile cap | Profiles 4→12: compact config layout + 12 narrow switcher cells in the combat UI + the full EVAL_GO1~12 direct-trigger set |
| **1.41.2** | 🌉 Missing-bridge final review | Static analyzer split_audit.js caught 6 missing bridges from the split, all patched — audit CLEAN |
| **1.41.1** | 🚑 EVAL_GO hotfix | A bare cfg reference in Engine (a missed direct-access form) crashed macro presses; switched to global reads |
| **1.41.0** | 🎬 Three self-casting conditions | Casting supports any cast (empty param) + self cast-bar elapsed / remaining seconds; fixed the 1.39.0 split missing bridge |
| **1.40.0** | 🔮 Target casting state | Conditions "target casting / cast-bar elapsed / cast-bar remaining" — driven by chat text events + self-learned cast durations |
| **1.39.0** | 🧱 Modular refactor | The 4758-line single file split into Core / Engine / UI three modules, with cross-module global bridge exports |
| **1.38.1** | 📊 Cast-bar progress | Combat info UI gains a cast bar under the target bar (progress + remaining seconds; the status UI already had the casting row) |
| **1.38.0** | 🎬 "Casting" condition | SPELLCAST_* event-driven cast tracking; `施法中:X` prevents clipping your own cast |
| **1.37.0** | 📏 Range tiers + in-range condition | Target distance tier display (melee / charge range / beyond ranged) + condition `范围内:X` via IsActionInRange |
| **1.36.4** | 🚑 Immunity-toggle hotfix | immBtn was mis-nested inside the sDrop call causing a nil error on refresh; put back in place (i18n branch) |
| **1.36.3** | 🔘 Immunity toggle | The "target immune to skill" param area gains an `免疫`/`未免疫` toggle button (i18n branch) |
| **1.36.2** | 📏 Preview repositioned | Editor preview moved to the same row right of "+ Add Condition", no longer overlapping Save/Cancel (i18n branch) |
| **1.36.1** | 🧬 Immunity condition type | Conditions `免疫:技能` / `未免疫:技能` read the learned table — immune behavior becomes programmable (i18n branch) |
| **1.36.0** | 🛡️ Immunity learner | Auto-learns from immunity text events (skill@mob name); same-named mobs are no longer attempted with that skill (i18n branch) |
| **1.35.2** | 🧹 Editor slimming | Condition param [v] arrows all removed — the param text itself is the button (i18n branch) |
| **1.35.1** | 🛡️ Immunity probe | /eh go probe immune captures the immunity event prototype (i18n branch) |
| **1.35.0** | 🌐 i18n P1 | Editor / import-export / popups / hints fully translated, 28 condition names in the language pack, trilingual README (i18n branch) |
| **1.34.1** | 📐 Wide-language adaptation | EN/RU windows widened 560→700, right button column right-anchored, long text no longer overlaps (i18n branch) |
| **1.34.0** | 🌍 i18n P0 | zh/en/ru trilingual skeleton + flag picker in the config window; UI text via language packs (i18n branch) |
| **1.33.4** | 🧽 Cap leftover cleanup | The missed 8-skill cap in /eh go add removed; README intro and scenarios fully refreshed |
| **1.33.3** | 🚑 Scrolling hotfix | Hotfix for the 1.33.0 ROWS scope error (now uses the live row-pool length) |

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

**Config window · One-key macro tab**: left profile bar (multiple profiles ≤12, click to switch / right-click to rename) + skill list (order = priority, checkbox = enabled, conditions visible at a glance) + [Add Skill] / [Import-Export]

![Config window · One-key macro tab](preview/cfg.png)

**Skill editor** (opened via [Edit] or by clicking a skill icon): per-row independent condition editing — condition type / params all chosen from dropdowns (28 condition types, grouped as self / target / aura / skill), relation column toggles & (all-in-group) / | (any-group), live preview

![Skill editor](preview/skill_doif.png)

**Skill two-level dropdown**: skill row = [Category▾][Item▾] side-by-side double dropdown, options with icons — character skills (action-bar scan of all skills on your bars):

![Skill dropdown · character skills](preview/skill_person.png)

**Pet commands**: 8 pet commands (direct Pet API calls, no action slot), command icons self-learned from the pet action bar:

![Pet commands](preview/skill_pet.png)

**Target selection**: 9 switch modes (nearest enemy / last target / target's target / by name / clear target…), the macro switches target first, then acts:

![Target selection](preview/skill_target.png)

**Item use**: live bag scan (with icons + counts) + custom name — consumables used directly, equipment auto-equipped:

![Item use](preview/skill_item.png)

**Aura checks (4 types)**: self buff / target debuff / target buff / self debuff (yes/no toggle, live items ◆○●▲) — `无buff:再生` drives one-key potion drinking, `无目标buff:奥术智慧` drives buff rounds:

**Combat info UI + Status info UI** (`/eh ui` / `/eh st`): HP / power / target bars + profile switcher row + skill icon row (hover tooltip shows trigger conditions, lit gold = conditions currently met, click an icon to open its editor); the status window shows all state variables live + the recent-cast log (per-cast skill / target / per-condition √/× verdicts)

![Combat info UI and status info UI](preview/info.png)

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
