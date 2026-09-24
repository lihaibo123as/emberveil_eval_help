# EvalHelp — All-Class Toolkit

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class toolkit addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **49 condition types** (grouped dropdowns; the member-picker row additionally offers 4 "candidate" conditions) × multiple key-bound profiles, all configured visually, for any class. Five more built-in pages: a **Toolbox** (merchant / social / quest automation / three helpers / rare alert relay), **Quests & Gear** (chains · gear · four search kinds + a world-map annotation layer, requires UnrealQuest), an **Icon library** (the client-built-in macro icons: grouped, hover shows the path, searchable and pageable), a **Pet helper** (pet abilities → taming source → spawn-point lookup) and **Sub-addons** (enable/disable optional sub-addons).

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions, plus text import/export for sharing; **seven tabs**: General · Macro Setup · Toolbox · Quests & Gear · Icon library · Pet Helper · Sub-addons |
| 📤 **Profile sharing** | `[Share]` on the config "one-click macro" page / chat link | chunked send to guild/party/say (rate-limited), the receiver clicks [Import] to commit; **tier cover** (`[tier manual · name]` clickable link + confirm popup) · **score tiers** (since 1.74.21: ≥50 points **and** 4+ of the 5 condition groups covered for Divine · five colours) · **title gacha** (5×15 · custom title) · the "Genesis" easter egg · the receiver lottery-replies with a role-play line (title tier × manual tier) |
| 🧩 **Case templates** | config window, one-key macro tab, bottom `[Case Templates]` | **12 groups / 35 entries** ready-made profiles (grouped by class) → **grouped two columns + wrapping within a group**; one click to import, hover to see what's inside |
| 🧰 **Toolbox** | config window, tab 3 | **UI tools** (map zoom / drag handles / per-layer tweaks) · merchant assistant (auto-repair / auto-sell grey / buy & discard by name) · party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices** (multi-select keywords) / class-colored names in chat / right-click name menu / on-demand /who lookup) · quests (auto accept & turn-in, hold Shift to pause / notification channel) · **three helpers** (one-click feed · hunter / consumables / one-click & auto dismount) · **rare alert relay** (a chat line the moment the quest addon spots a rare — click the name to target it) |
| 🧭 **Quests & Gear** | config window, tab 4 | **Chain view**: one chain laid out node by node (quest · level · reward, each node with a magnifier); **Gear view**: obtainable gear listed by level (weapons first · kind multi-select · placeholder for missing icons); **four search kinds**: quest / item / mob·NPC / object (instant, unlimited drill-down); **world-map annotation layer** (16 categories redrawn live, requires UnrealQuest) |
| 🖼️ **Icon library** | config window, tab 5 | The client's built-in macro icons grouped by prefix, hover shows the path, searchable and pageable; plus a "used by this addon" group (listing the icons this addon uses) |
| 🐾 **Pet helper** | config window, tab 6 | Search pet abilities (icon + per-rank list) → detail page: description / required level / **taming source** (which mob, where) → the magnifier jumps to Quests & Gear for spawn points |
| 🧩 **Sub-addons** | config window, tab 7 | Enable / disable optional sub-addons and open their UI (currently **Layer Debug** EH_DebugBox); the simple map and friends became main-addon toolbox modules |
| 📊 **Combat info UI** | `/eh ui` | HP / power / target bars + profile switcher row + skill icon row (lit gold = conditions met, click to edit) |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## 🏁 Milestones (1.52.0 → 1.75.1)

- **🔀 Two branches merged + width/height only for chat frames + pet action bar** (1.75.1): `probe/map-scale` (frame dragging / layer fixes / map zoom) and the quest-line branch **merged into master** (5 conflicts reviewed one by one, 3 merge side-effects fixed, plus the `TEST LOAD ORDER CHECK` iron rule); **layer-drag width/height now applies to CHAT frames only** (single source `dfSizeOK`; other windows get those rows **hidden** and the popup height back) and is **persisted in SavedVariables** (written back on relog / profile apply); the always-on layer list gained the **pet action bar** (appears on demand ⇒ bounded `UNIT_PET` follow, frame name probed at runtime, absent reported honestly); addon wording "all-class casting tool" → "**all-class toolkit**", tab 4 "Data Search" → "**Quests & Gear**"; also fixed "classic quest lines are not findable by step name" ("Of Love and Family" was in the pack as step 4/5 of the auto line "Redemption", only its step names were dropped to `#id`) ⇒ **1585 step names restored** plus a generated-artifact gate.
- **🧭 Quest-chain search: full 4-60 sweep, sorted by reward, weapons first** (1.75.0; tab 4 is now "Quests & Gear"): **62 curated classic chains + 611 auto-detected quest lines (673 in the list: 18 with ≥10 steps · 17 dungeon-openers/epics · longest 24 steps)** backed by a full sweep — **751** quests with gear rewards / **1262** items (**990** in the gear view), each verified against `database.emberveil.org`; **rewards come first** (rare weapons on top: Whirlwind weapons, Verigan's Fist, Staff of Westfall, Crescent Staff/Wingblade, Tombstone Scepter, Outlaw Sabre), and every chain lists its **full accept-order steps** (quest id · level · zone); reward rows show the **native item tooltip on hover**, step rows **open the quest detail on click**; the fetch/build scripts live **independently in `quest/`** (zero coupling; rerun with `node quest/build.js`); the data ships with the addon, so chains still work **without UnrealQuest**; a **[Quest chains]** panel sits right of the map-annotation button: gear is listed by obtainable level with real item icons, clicking a piece shows **which chain rewards it** plus that chain's full steps, and one click jumps into Data Search; faction is a strict three-way split (Alliance / Horde / Shared), **every quest node has a magnifier** (the addon's own `database` icon) that jumps into Data Search by quest name **without closing the panel**, the list area **fills the whole window** (row count computed from window height, never hard-coded), the gear detail shows a **large icon + large title** with item info on hover, paging uses **text buttons [Prev][Next]** aligned left next to [Back] and always visible in both views, and item info hides correctly when focus leaves, plus level/type/tier filters, paged list with wheel, draggable.
- **⏱️ Shot timer + "Next Shot In" condition + three UI completions** (1.74.29 → 1.74.30): hunter auto-shot now has its **own timer** (settled by a live-client probe: the spell-channel line containing "Auto Shot" is the anchor and `UnitRangedDamage[1]` the speed, independent from melee) plus the new numeric condition; the combat UI **active profile cell is outlined in its tier colour**; both helpers pickers show **native item details**; the feed helper borders its icon by `GetPetHappiness()` (**happy = bright green**); consumable-helper left click no longer opens the picker.
- **🔔 Tier thresholds + per-character settings + rare-alert relay** (1.74.19 → 1.74.28): profile rating reworked (an empty skill scores 0 · conditions weighted 1/2/3 · a 12-point per-skill cap · coverage caps below four condition families · **Divine ≥ 50 points**), the three helpers keep their settings **per character**, a profile shared by a player ("Divine Storm") joined the paladin templates, and the **rare-alert relay** — one chat line the moment the quest addon spots a rare (name coloured by rank and clickable: **left-click targets it / right-click marks its spawn point on the map**; clicking it is one target call, and a miss is reported as an error; the whole thing now lives in `tools/RareWatch.lua` with a toolbox switch; both helpers popups now filter non-usable bag items by type).
- **🎬 Sharing experience loop** (1.74.1 → 1.74.6): 40 scene lines (accept/ignore × with/without target × 3 languages; title coloured by tier, and the measured rule "a colour code must carry a link") · profile **author/source** in 4 kinds + profile-list tooltip (tier · source · skill count) · all **8 "no popup" branches logged** · the easter-egg reaction is **no longer wired** (kept) · fixed the "self-echo" misjudgement (someone else's share was swallowed when you already had the same profile).
- **🧰 Two toolbox helpers + dispel types** (1.74.5 → 1.74.6): **Hunter → auto-feed** and the **consumable helper** (one 8×N icon grid · multi-select · greyed out when used up; unverified features carry a **yellow "to be tested" mark**) · **self/target debuffs now support "dispel type"** — same semantics as party/candidate debuffs (empty name + type = "any debuff of that type").
- **🎉 Sharing system rework: cover line · tiers · titles · easter egg · reactions** (1.73.35 → 1.74.0): 85 commits released at once — share cover line (`[Tier manual · name]` as a clickable link, click opens a confirm popup instead of auto-importing), score-based tiers (25+ = Divine, five colours incl. bright blue), **title gacha** (5 tiers × 15 cards, only-up, custom title + colour), the "Genesis" easter egg (3-condition gate) + **role-play reactions** (title tier × manual tier, lottery-picked, guild/say/party, and the scheme name is a clickable link to the receive page).
- **🧪 Real-client forensics for links/colour codes** (1.73.35 → 1.74.0): whether custom links survive the server, the true 250-byte message cap, hover mechanics, on-disk ledgers — nailed down the "colour-code sending rules" (one colour segment first + **must carry a link**, 1 msg/sec, only `[EHPF#]` is recognised).
- **🖥 Title-bar badges + tier colouring** (1.73.55 → 1.74.0): combat-HUD / status-UI title bars share one layout — player name → title → tier badge → current profile; profile rows are tier-coloured (HUD + config + templates share one tier computation).
- **💬 Chat names: coloring + right-click menu** (1.73.12 → 1.73.29): after pinning down that the name lives in `arg2` and the name slot does **not** parse rich text, plan A (swallow the client line, compose our own) finally colors names by class; right-click offers **whisper / invite / target / guild invite / copy name** (copy = **prefill `/s name`, never auto-send**); translucent narrow menu with adaptive height.

## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.75.1** | 🔀 **Two branches merged + width/height only for chat frames + pet action bar** | ① `probe/map-scale` (frame dragging / layer fixes / map zoom) and the quest-line branch **merged into master**: 5 conflicts reviewed one by one, 3 merge side-effects fixed, plus a new iron rule `TEST LOAD ORDER CHECK` (in the harness `test_assert.lua` must come after every `tools/*.lua`, or the toolbox module-row assertions read nothing); ② **layer dragging: width/height only for CHAT frames, and persisted** (single source `dfSizeOK`; other windows get those two rows **hidden** and the popup height back — not greyed out; saving reads the original value **before** writing the new one, stored in SavedVariables so it survives relog); ③ the always-on layer list gained the **pet action bar** (runtime name probing + a bounded `UNIT_PET` follow; `PET_BAR_UPDATE` has no local evidence, so it is not registered); ④ addon wording "All-Class Casting Helper" → "**All-Class Toolkit**", tab 4 "Data Search" → "**Quests & Gear**" (tab width 74/78 → 84/88); ⑤ the hunter helper now shows an **explicit prompt + warning colour** instead of the vague "unrecognised" when no feed spell is chosen; ⑥ **classic quest lines are now findable by step name** (the user reported "Of Love and Family" missing — it *was* in the pack, as step 4/5 of the auto line "Redemption"; only its step names had been dropped and rendered as `#id`): **1585 step names restored**, searchable by step name, plus a new generated-artifact gate; ★step rows no longer render `#id` either (**the same bug lived in two layers** — dropped at build time, then unreachable at runtime) |
| **1.75.0** | 🧭 **Quest chains in Data Search** + a **Quest chains panel (gear first, faction split, per-node lookup)**: classic chains + a **full 4-60 sweep**, sorted by reward, weapons first | **Final tally**: **62** curated chains + **611** auto quest lines (**673** total · 18 with ≥10 steps · 17 dungeon-openers/epics · longest 24) + **751** gear-reward quests / **1262** items (**990** in the gear view) across **levels 4-60** — each verified against `database.emberveil.org`; rewards first (rare weapons on top: Whirlwind axe/sword/hammer, Verigan's Fist, Staff of Westfall, Crescent Staff, Wingblade, Tombstone Scepter, Outlaw Sabre) and **full accept-order steps** per chain (level + zone); reward rows show the **native item tooltip**, step rows **open the quest detail**; new "Quest chain" filter lists all chains on an empty query; fetch/build scripts live **independently in `quest/`**; data ships with the addon, so chains work **without UnrealQuest** |
| **1.74.30** | ⏱️ **Shot timer** (hunter auto-shot) + new condition **"Next Shot In"** + consumable-helper left click no longer opens the picker | The live-client probe settled it: the anchor is a `CHAT_MSG_SPELL_SELF_DAMAGE` line containing "Auto Shot" (**crit wording included**) and the speed is `UnitRangedDamage` return #1 (measured 2.09s). Melee and ranged keep **two independent anchors**; the combat UI gold bar, the status UI line and the `swingLeft` condition switch automatically while auto-shot runs (labels say "next shot" vs "next swing"). Self-calibration only kicks in on a **clear deviation** (client jitter is never treated as haste). New numeric condition "Next Shot In" (text `shotLeft<0.5`, editor initial value **0**); also fixes the inheritance bug that carried `30.0` into time-type conditions. Consumable-helper main icon: **left click no longer opens the picker** (right click only; left is for dragging) |
| **1.74.29** | 🖼️ Combat UI **active-profile border highlight** + native item details in both helpers pickers + feed-helper **happiness border** | The active profile cell gets four 1px border textures coloured by that profile tier (gold fallback) and updates as you switch; picker cells draw the **client native item tooltip** first (quality / type / "Use:" effect / price) then append the helper own lines; the feed helper icon border is computed from `GetPetHappiness()`: **happy = bright green**, content = gold, unhappy = red, no pet = default gold |
| **1.74.28** | Both helpers popups now **filter bag items by type** + a one-command verification | Three-tier judgement (quality -> `GetItemInfo(link)` -> an invisible self-built tooltip that also warms the client cache, so it self-heals): weapons / armor / grey / **herbs, ore, materials** / quest items / containers / ammo / keys / recipes are all dropped, and anything unclassifiable is kept; `/eh go 消耗品探针 过滤` prints the evidence per item |
| **1.74.27** | 🧹 Rare-alert relay **extracted into its own module** `tools/RareWatch.lua` + a **toolbox switch** | The whole block moved under `tools/` (two wiring points stay in the main file); the toolbox gains a Rare alert group with a switch that reads/writes the feature’s own single source of truth, and reports one status line when toggled |
| **1.74.26** | 🧹 Clicking the name **does one thing**: call the target function; a miss **is an error** | All coupling with the quest addon’s machinery (coordinates / nearest spawn / map projection / opening the map / distance wording) was removed on request, and the link token shrank from `EHRW:areaId:x:y:unitId` to `EHRW:<name>`; one click = one `TargetByName(name)`, reporting selected or an error |
| **1.74.25** | 📏 Targeting **message fix** (name the client limit + report the distance) + a target probe | The screenshot showed the rare **556 yards** away while the message blamed the creature - the real cause is that targeting by name only reaches units **near** the client (documented; at range it fails silently). The message now says so and quotes the distance; /eh go target probe settles it in one command by re-selecting your current target by its own name |
| **1.74.24** | 🎨 Rare alert **coloured by rank + clickable name** (left-click = target it / right-click = mark its spawn on the map) | The name is coloured by rank (elite silver / rare blue / rare elite purple / boss orange) with exactly one 8-digit colour code per line; the name is a link: **left-click switches your target to that rare** (TargetByName, with a before/after check so the result is reported honestly), **right-click opens the world map and marks its nearest recorded spawn**; commands /eh go 稀有 目标|定位|链接 |
| **1.74.23** | 🔔 **Rare-alert relay** (the quest addon spots a rare → one chat line) | The moment UnrealQuest shows its rare card, one chat line reports the creature name, the rank (elite / rare elite / boss / rare), the yards to the nearest recorded spawn and how many others came into range. Implemented by **wrapping its alert exit** (RareAlert:Show) rather than polling, with an automatic fallback to its public counter. Toggle and status: /eh go 稀有 |

> 📜 Detailed per-version notes live in **[CHANGELOG.md](CHANGELOG.md)**; earlier history is in the git commit log.

## 🧩 Case Templates (12 groups, 35 ready-made profiles)

> No need to build from scratch. Config window → "One-key macro" tab → **`[Case Templates]`** at the bottom → pick one by class, **click to import**.

| Item | Description |
| :-- | :-- |
| **Entry** | Config window, "One-key macro" tab, bottom `[Case Templates]` button |
| **Contents** | **12 groups / 35 profiles**: 战士 / 法师 / 通用法系 / 通用 / 盗贼 / 猎人 / 骑士 / 牧师 / 德鲁伊 / 术士 / 萨满 / 队伍·团队 (group headers keep the addon's own names) |
| **Layout** | Two columns by group, wrapping inside a group; **hover** a row to see its skills and conditions |
| **Import** | One click turns it into a profile — then edit, rename and bind a key as usual |

The **Party·Raid** group (6 profiles) covers one-key healing and one-key dispelling. All of them are written as
"**explicit skill + party (raid) member condition**": the condition scans the group, picks the lowest-HP member,
switches target, casts, and restores your original target — **you never click a teammate**.

> 💬 Got a good profile? Share it in the addon comments, or use `[Share]` in the config window to post it to guild / party / say.

## UI Preview

**Config window · Global tab** (`/eh cfg` or the EH icon next to the minimap): log / UI toggles + built-in help

![Config window · Global tab](preview/main.png)

**Case-template window** (bottom of the one-key macro tab, `[Case Templates]`): 12 groups / 35 ready-made profiles grouped by class, laid out as **two columns of groups with wrapping inside each group** — one click imports a profile, hover shows its contents

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

**Toolbox (Tab3)**: **UI tools** (map zoom / drag handles / per-layer tweaks) · merchant assistant (auto-repair / auto-sell grey / buy & discard by name) · party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices** (multi-select keywords) / class-colored names / right-click name menu / on-demand /who) · auto quest accept & turn-in plus notification channel (off / self / say / party; hold Shift to pause) · **three helpers** (one-click feed · hunter / consumables / one-click & auto dismount) · **rare alert relay**

![Toolbox](preview/tools.png)

> ⚠️ **Requires** the **UnrealQuest** addon — every record shown here (quests / items / mobs / NPCs) comes from its database. If it is missing or disabled, this tab shows an installation guide instead and hides the controls.

**Quests & Gear (Tab4)**: **chain view** (one chain from start to end, node by node: quest · level · reward, magnifier on every node) + **gear view** (obtainable gear by level, weapons first, kind multi-select) + **four search kinds** (quest / item / mob·NPC / object; instant, top 10 matches, unlimited drill-down, hovering an item row shows the in-game item tooltip); **world-map annotation layer** (16 categories redrawn live as the map changes) tooltip

**Gear view**: obtainable **gear listed by level** (weapons first) — click an entry to see which chain grants it and which quests are required; gear whose icon is not in the local cache yet is drawn as a **placeholder**, and clicking it queues that item first rows with coordinates carry a map icon at the end

![Quests & Gear · gear view](preview/quests_item.png)

**Chain view**: from start to end, node by node — every node carries a **magnifier** (look the quest up by name) and a level badge; the "Map annotations (N)" control = category multi-select (5 gathering nodes + 11 town services, with all-on / all-off shortcuts), drawn live as the map changes-off shortcuts); checked categories are drawn live as the map changes

![Quests & Gear · chain view](preview/quests_line.png)

**Pet helper (Tab 6)**: search pet abilities (icon + per-rank list) → the detail page lists the description / required level / **taming source** (which mob, where) → the magnifier jumps to Quests & Gear for spawn points — from "which pet learns this ability" to "where to tame it", end to end

![Pet helper · taming source](preview/pet_skill.png)

## Quick Start

1. Drag the skills you want onto your action bars (any class — the plugin recognizes whatever is on your bars).
2. In game, run `/eh go rescan` so the plugin learns the slots (`/eh go` shows the scan result).
3. **Bind a key (recommended, click-only)**: right-click any profile (the profile row in the combat UI or the profile list in settings) → Profile Manager → pick a key in the Hotkey dropdown → [Save] — pressing it runs that profile. **Alternative** if you prefer macros: create a macro with the one-line body `/run EVAL_GO()` and drag it onto a key.
4. **New here?** Type `/eh guide` for the four-step starter guide (combat UI → first profile → key binding → skill log); it also plays once automatically on first login.
5. Start from a **case template**: open `/eh cfg` → one-key macro tab → [Import/Export] → [Case Templates], pick your class and import — then tweak thresholds via the golden EH icon by the minimap; `/eh debug` shows the decision reason for every key press in chat.

## Installation

**Option 1: download a release (recommended)** — grab the latest `EvalHelp-vX.Y.Z.zip` from the [Releases page](https://gitee.com/xeval/emberveil_eval_help/releases) and extract it into `Interface/AddOns/` (after extraction it should look like `AddOns/EvalHelp/EvalHelp.toc`):

```
https://gitee.com/xeval/emberveil_eval_help/releases/download/v1.75.1/EvalHelp-v1.75.1.zip
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

## Self-Rescue (read this first when something's wrong)

1. **`/reload` first**: skills not recognized, UI glitches, just updated addon files — a reload fixes the vast majority of cases (your config is saved and won't be lost);
2. Moved skills around / dragged new ones onto bars → `/eh go rescan` to rescan;
3. Want to watch the decision process → `/eh debug` (why each skill fired or didn't, per-condition √/×);
4. Still stuck → file an Issue at <https://gitee.com/xeval/emberveil_eval_help.git> (attaching an `/eh st` status screenshot + the log file helps a lot).
5. **A shared profile never fires some skills**: usually that aura's texture was never learned on this machine — it is now scanned by name and learned automatically; `/eh go tex` lists the table, `/eh go texdel <name>` forgets one, `/eh go texclear` wipes it;

## Contributing (welcome aboard!)

- Repository: <https://gitee.com/xeval/emberveil_eval_help.git> (after `git clone`, symlink or copy `EvalHelp/` into `Interface/AddOns/` and you're ready to develop and debug);
- **Developer guide**: see `DEVELOPMENT.md` (architecture map / field-tested UI recipes for this client / rule engine & profile data structures / the mandatory syntax check before committing);
- **AI collaboration memory**: `CLAUDE.md` is this project's AI development memory (AI assistants such as DeepSeek Harness / Claude Code can read it to get up to speed fast);
- Workflow convention: bump the version number on every change (lua header comment + `local VERSION` + toc, three places in sync), and run `node luacheck.js` for a full syntax parse after editing;
- Extending to new classes: skills come from **action-bar scanning** — anything dragged onto your bars is recognized, so there is no per-class skill whitelist; the rule engine / profiles / UI are all class-agnostic;
- This addon is developed with **DeepSeek Harness AI** assistance — you're welcome to bring your own AI along too.

## Support Us

EvalHelp has been, and always will be, free and open source.

If it happens to help you and you feel like encouraging the author, you can sponsor a little computing power ☕. Every bit goes to the sharp end: more careful polish, faster bug fixes, and ready-made templates for more classes.

And of course, even just a star, a suggestion, or telling a guildmate about it means a great deal to us. Thank you for reading this far.

| Alipay | WeChat |
| :---: | :---: |
| ![Alipay QR](pay/bao.jpg) | ![WeChat QR](pay/wei.jpg) |

## Acknowledgements

- Field-tested UI recipes from: UnrealQuest (ClientAPI.lua); state-variable design from: Cat (TurtleWoW); original reference: OneJudge.
- Thanks to every player who tested and gave feedback.
