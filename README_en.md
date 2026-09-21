# EvalHelp — All-Class Casting Helper

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class casting helper addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **49 condition types** (grouped dropdowns; the member-picker row additionally offers 4 "candidate" conditions) × multiple key-bound profiles, all configured visually, for any class. Three more built-in pages: a **Toolbox** (merchant / social / quest automation), **Data search** (quests / items / mobs·NPC + a world-map annotation layer, requires UnrealQuest) and an **Icon library** (the client-built-in macro icons: grouped, hover shows the path, searchable and pageable).

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions, plus text import/export for sharing |
| 📤 **Profile sharing** | `[Share]` on the config "one-click macro" page / chat link | chunked send to guild/party/say (rate-limited), the receiver clicks [Import] to commit; **tier cover** (`[tier manual · name]` clickable link + confirm popup) · **score tiers** (since 1.74.21: ≥50 points **and** 4+ of the 5 condition groups covered for Divine · five colours) · **title gacha** (5×15 · custom title) · the "Genesis" easter egg · the receiver lottery-replies with a role-play line (title tier × manual tier) |
| 🧩 **Case templates** | config window, one-key macro tab, bottom `[Case Templates]` | **12 groups / 35 entries** ready-made profiles (grouped by class) → **grouped two columns + wrapping within a group**; one click to import, hover to see what's inside |
| 🧰 **Toolbox** | config window, tab 3 | Merchant assistant (auto-repair / auto-sell grey / buy and discard by name) + party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices**) + auto quest accept & turn-in (hold Shift to pause temporarily) + quest notification channel |
| 🗺️ **Data search** | config window, tab 4 | Quest / item / mob·NPC / object search with instant results and unlimited drill-down; a **world-map annotation layer** (16 categories redrawn live as the map changes) and one-click pinning from any row with coordinates (requires UnrealQuest) |
| 🖼️ **Icon library** | config window, tab 5 | The client's built-in macro icons grouped by prefix, hover shows the path, searchable and pageable; plus a "used by this addon" group (listing the icons this addon uses) |
| 📊 **Combat info UI** | `/eh ui` | HP / power / target bars + profile switcher row + skill icon row (lit gold = conditions met, click to edit) |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## 🏁 Milestones (1.52.0 → 1.74.27)

- **🔔 Tier thresholds + per-character settings + rare-alert relay** (1.74.19 → 1.74.27): profile rating reworked (an empty skill scores 0 · conditions weighted 1/2/3 · a 12-point per-skill cap · coverage caps below four condition families · **Divine ≥ 50 points**), the three helpers keep their settings **per character**, a profile shared by a player ("Divine Storm") joined the paladin templates, and the **rare-alert relay** — one chat line the moment the quest addon spots a rare (name coloured by rank and clickable: **left-click targets it / right-click marks its spawn point on the map**; clicking it is one target call, and a miss is reported as an error; the whole thing now lives in `tools/RareWatch.lua` with a toolbox switch).
- **🎬 Sharing experience loop** (1.74.1 → 1.74.6): 40 scene lines (accept/ignore × with/without target × 3 languages; title coloured by tier, and the measured rule "a colour code must carry a link") · profile **author/source** in 4 kinds + profile-list tooltip (tier · source · skill count) · all **8 "no popup" branches logged** · the easter-egg reaction is **no longer wired** (kept) · fixed the "self-echo" misjudgement (someone else's share was swallowed when you already had the same profile).
- **🧰 Two toolbox helpers + dispel types** (1.74.5 → 1.74.6): **Hunter → auto-feed** and the **consumable helper** (one 8×N icon grid · multi-select · greyed out when used up; unverified features carry a **yellow "to be tested" mark**) · **self/target debuffs now support "dispel type"** — same semantics as party/candidate debuffs (empty name + type = "any debuff of that type").
- **🎉 Sharing system rework: cover line · tiers · titles · easter egg · reactions** (1.73.35 → 1.74.0): 85 commits released at once — share cover line (`[Tier manual · name]` as a clickable link, click opens a confirm popup instead of auto-importing), score-based tiers (25+ = Divine, five colours incl. bright blue), **title gacha** (5 tiers × 15 cards, only-up, custom title + colour), the "Genesis" easter egg (3-condition gate) + **role-play reactions** (title tier × manual tier, lottery-picked, guild/say/party, and the scheme name is a clickable link to the receive page).
- **🧪 Real-client forensics for links/colour codes** (1.73.35 → 1.74.0): whether custom links survive the server, the true 250-byte message cap, hover mechanics, on-disk ledgers — nailed down the "colour-code sending rules" (one colour segment first + **must carry a link**, 1 msg/sec, only `[EHPF#]` is recognised).
- **🖥 Title-bar badges + tier colouring** (1.73.55 → 1.74.0): combat-HUD / status-UI title bars share one layout — player name → title → tier badge → current profile; profile rows are tier-coloured (HUD + config + templates share one tier computation).
- **💬 Chat names: coloring + right-click menu** (1.73.12 → 1.73.29): after pinning down that the name lives in `arg2` and the name slot does **not** parse rich text, plan A (swallow the client line, compose our own) finally colors names by class; right-click offers **whisper / invite / target / guild invite / copy name** (copy = **prefill `/s name`, never auto-send**); translucent narrow menu with adaptive height.
- **🧰 Toolbox dialog spec** (1.73.30 → 1.73.34): frame-level ladder (config 10 · edit 100 · input 220 · toolbox 200 · dropdown 250), drag handles must be Buttons, single-source column geometry, and the **scrollbar** brought up to spec (single-source wheel direction `EVAL_WHEEL_DIR` · dedicated scroll gutter · integer page numbers · arrows hidden at the ends).
- **🔋 Condition names and the syntax gate** (1.73.27 → 1.73.28): power names are computed **at display time** from `UnitPowerType` (mana / focus / rage / energy, druids follow their form) with the parser accepting every spelling (so exporting and re-importing never drops conditions); `luacheck` now parses **every file** (27 `.lua`) instead of one.
- **🔍 Shared-profile aura fix + guide on every load** (1.72.2): when another character never learned a debuff texture, the addon now **falls back to a name scan and self-heals** (a hit learns name→texture, then the fast path); the starter guide prints **on every load**; also fixed the `EVAL_DS_HUD` frame name shadowing its own global function (which made `/eh ds hud` silently dead)


## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.74.27** | 🧹 Rare-alert relay **extracted into its own module** `tools/RareWatch.lua` + a **toolbox switch** | The whole block moved under `tools/` (two wiring points stay in the main file); the toolbox gains a Rare alert group with a switch that reads/writes the feature’s own single source of truth, and reports one status line when toggled |
| **1.74.26** | 🧹 Clicking the name **does one thing**: call the target function; a miss **is an error** | All coupling with the quest addon’s machinery (coordinates / nearest spawn / map projection / opening the map / distance wording) was removed on request, and the link token shrank from `EHRW:areaId:x:y:unitId` to `EHRW:<name>`; one click = one `TargetByName(name)`, reporting selected or an error |
| **1.74.25** | 📏 Targeting **message fix** (name the client limit + report the distance) + a target probe | The screenshot showed the rare **556 yards** away while the message blamed the creature - the real cause is that targeting by name only reaches units **near** the client (documented; at range it fails silently). The message now says so and quotes the distance; /eh go target probe settles it in one command by re-selecting your current target by its own name |
| **1.74.24** | 🎨 Rare alert **coloured by rank + clickable name** (left-click = target it / right-click = mark its spawn on the map) | The name is coloured by rank (elite silver / rare blue / rare elite purple / boss orange) with exactly one 8-digit colour code per line; the name is a link: **left-click switches your target to that rare** (TargetByName, with a before/after check so the result is reported honestly), **right-click opens the world map and marks its nearest recorded spawn**; commands /eh go 稀有 目标|定位|链接 |
| **1.74.23** | 🔔 **Rare-alert relay** (the quest addon spots a rare → one chat line) | The moment UnrealQuest shows its rare card, one chat line reports the creature name, the rank (elite / rare elite / boss / rare), the yards to the nearest recorded spawn and how many others came into range. Implemented by **wrapping its alert exit** (RareAlert:Show) rather than polling, with an automatic fallback to its public counter. Toggle and status: /eh go 稀有 |
| **1.74.22** | 🧩 "Divine Storm" joins the paladin case templates (shared by Rainbow) + 🎭 template names rebuilt on the **Azeroth lore × their own tier** + 📝 templates support **author/note** + 🔆 Divine tier recoloured to **bright blue** | ①The user's own "Divine Storm" profile (13-skill retribution paladin) is now a paladin case template: the text came verbatim from the addon's **own exporter** (reading the saved profile table) and passed an `export(parse(text)) == text` round-trip, so nothing was retyped by hand; ②**all 34 templates renamed with rewritten descriptions**, named from Azeroth lore according to **each template's own tier** (Common = mortal world, e.g. "Inn Rest / First-Aid Vial" · Rare = elite, e.g. "Kirin Tor Mage / Uncrowned Assassin" · Rare-elite = hero, e.g. "Ranger Lord / Emerald Hunt" · Legendary = legend, e.g. "Hellscream / Silver Hand"; the mythic-tier "Divine Storm" already reads as a spell name → **kept as-is**); ③template entries gained optional `author`/`note` — hovering shows "Author: Rainbow" and "Note: a selfless paladin share from LM-Rainbow of the Dragon Realm", and the import records that author as the profile source (templates without `author` still record "Academy"); ④the **Divine tier colour** moved from deep red `c00000` to **bright blue `00bfff`** (single source `SH_SEAL_TIERS` — config window / template window / share cover / title badge all follow). |
| **1.74.21** | 🎯 God tier threshold changed to **50 points** | Bands are now ≤11 Common / 12-23 Rare / 24-35 Epic / 36-49 Legendary / **≥50 Divine**; the coverage caps (23/35/49) and every derived sample follow the tier table automatically |
| **1.74.20** | 👤 Settings **stored per character** (three helpers) | The consumable / hunter-feed / dismount helpers now keep their **whole** config (toggles · item and food lists · icon cache · floating-icon position, 15 keys) in a **per-character** saved variable EVAL_HELP_CHAR — each character gets its own settings instead of overwriting each other; existing settings are inherited once on first login; profiles / language / log / share switches stay account-wide |
| **1.74.19** | 🏅 Profile tiers + title promotion **reworked (much harder)** | Old rule: an **empty skill still scored 1 point** → 25 empty skills was God tier (reproduced); conditions were all worth the same; every title step above 1 needed only **one** profile. New rule: **empty skills score 0** · conditions weighted by group (self/skill 1 · target/aura 2 · party 3) · per-skill cap 12 · identical duplicate conditions counted once · **coverage cap** (fewer than 4 of the 5 condition groups keeps you below God tier) · bands ≤14/15-34/35-69/70-119/**≥120 God tier** · title requirements 1/2/3/3/2 with **step-by-step** escalation |
| **1.74.18** | ⇕️ Combat HUD icon band **wraps automatically**, height adapts | The old fixed 2 rows × 8 cells silently dropped everything from skill 17 on; now the band wraps at 8 per row to fit however many skills the active profile has, and the frame height grows/shrinks with the row count (content below follows); a count change is picked up by the heartbeat, and BUILD and the heartbeat share **one** row-count function |

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

![Combat info UI and status info UI](preview/info.png)

**Toolbox (Tab3)**: merchant assistant (auto-repair equipment / auto-sell grey items / auto-buy and auto-discard specified items) + party & social (auto-confirm role check / hide guild member login notifications / **hide "joined·left channel" notices**) + auto quest accept & turn-in (optionally paused while holding Shift) + quest notification channel (off / self / say / party)

![Toolbox](preview/tools.png)

> ⚠️ **Requires** the **UnrealQuest** addon — every record shown here (quests / items / mobs / NPCs) comes from its database. If it is missing or disabled, this tab shows an installation guide instead and hides the controls.

**Data search (Tab4)**: four search kinds — quest / item / mob·NPC / object; type to search (top 10 matches); unlimited drill-down, and hovering an item row shows the in-game item tooltip

**Data search · details and drill-down**: quest / item / mob details — objectives and description, start / end NPC, required items; every link can be clicked to drill further, and rows with coordinates carry a map icon at the end

![Data search · quest details](preview/dataset_search.png)

**Data search · map annotations**: the "Map annotations (N)" control = master toggle + category multi-select (16 categories: 5 gathering nodes + 11 town services, with all-on / all-off shortcuts); checked categories are drawn live as the map changes

![Data search · map annotation categories](preview/dataset.png)

**Pet helper (Tab 6)**: search pet abilities (icon + per-rank list) → the detail page lists the description / required level / **taming source** (which mob, where) → the magnifier jumps to Data Search for spawn points — from "which pet learns this ability" to "where to tame it", end to end

![Pet helper · search abilities](preview/pet_skill_search.png)

![Pet helper · taming source](preview/pet_skill_info.png)

## Quick Start

1. Drag the skills you want onto your action bars (any class — the plugin recognizes whatever is on your bars).
2. In game, run `/eh go rescan` so the plugin learns the slots (`/eh go` shows the scan result).
3. **Bind a key (recommended, click-only)**: right-click any profile (the profile row in the combat UI or the profile list in settings) → Profile Manager → pick a key in the Hotkey dropdown → [Save] — pressing it runs that profile. **Alternative** if you prefer macros: create a macro with the one-line body `/run EVAL_GO()` and drag it onto a key.
4. **New here?** Type `/eh guide` for the four-step starter guide (combat UI → first profile → key binding → skill log); it also plays once automatically on first login.
5. Start from a **case template**: open `/eh cfg` → one-key macro tab → [Import/Export] → [Case Templates], pick your class and import — then tweak thresholds via the golden EH icon by the minimap; `/eh debug` shows the decision reason for every key press in chat.

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
