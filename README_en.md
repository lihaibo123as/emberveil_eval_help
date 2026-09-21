# EvalHelp — All-Class Casting Helper

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class casting helper addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **49 condition types** (grouped dropdowns; the member-picker row additionally offers 4 "candidate" conditions) × multiple key-bound profiles, all configured visually, for any class. Three more built-in pages: a **Toolbox** (merchant / social / quest automation), **Data search** (quests / items / mobs·NPC + a world-map annotation layer, requires UnrealQuest) and an **Icon library** (the client-built-in macro icons: grouped, hover shows the path, searchable and pageable).

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions, plus text import/export for sharing |
| 📤 **Profile sharing** | `[Share]` on the config "one-click macro" page / chat link | chunked send to guild/party/say (rate-limited), the receiver clicks [Import] to commit; **tier cover** (`[tier manual · name]` clickable link + confirm popup) · **score tiers** (25+ Divine · five colours) · **title gacha** (5×15 · custom title) · the "Genesis" easter egg · the receiver lottery-replies with a role-play line (title tier × manual tier) |
| 🧩 **Case templates** | config window, one-key macro tab, bottom `[Case Templates]` | **11 groups / 29 entries** ready-made profiles (grouped by class) → **grouped two columns + wrapping within a group**; one click to import, hover to see what's inside |
| 🧰 **Toolbox** | config window, tab 3 | Merchant assistant (auto-repair / auto-sell grey / buy and discard by name) + party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices**) + auto quest accept & turn-in (hold Shift to pause temporarily) + quest notification channel |
| 🗺️ **Data search** | config window, tab 4 | Quest / item / mob·NPC / object search with instant results and unlimited drill-down; a **world-map annotation layer** (16 categories redrawn live as the map changes) and one-click pinning from any row with coordinates (requires UnrealQuest) |
| 🖼️ **Icon library** | config window, tab 5 | The client's built-in macro icons grouped by prefix, hover shows the path, searchable and pageable; plus a "used by this addon" group (listing the icons this addon uses) |
| 📊 **Combat info UI** | `/eh ui` | HP / power / target bars + profile switcher row + skill icon row (lit gold = conditions met, click to edit) |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## 🏁 Milestones (1.52.0 → 1.74.12)

- **🎬 Sharing experience loop** (1.74.1 → 1.74.6): 40 scene lines (accept/ignore × with/without target × 3 languages; title coloured by tier, and the measured rule "a colour code must carry a link") · profile **author/source** in 4 kinds + profile-list tooltip (tier · source · skill count) · all **8 "no popup" branches logged** · the easter-egg reaction is **no longer wired** (kept) · fixed the "self-echo" misjudgement (someone else's share was swallowed when you already had the same profile).
- **🧰 Two toolbox helpers + dispel types** (1.74.5 → 1.74.6): **Hunter → auto-feed** and the **consumable helper** (one 8×N icon grid · multi-select · greyed out when used up; unverified features carry a **yellow "to be tested" mark**) · **self/target debuffs now support "dispel type"** — same semantics as party/candidate debuffs (empty name + type = "any debuff of that type").
- **🎉 Sharing system rework: cover line · tiers · titles · easter egg · reactions** (1.73.35 → 1.74.0): 85 commits released at once — share cover line (`[Tier manual · name]` as a clickable link, click opens a confirm popup instead of auto-importing), score-based tiers (25+ = Divine, five colours incl. deep red), **title gacha** (5 tiers × 15 cards, only-up, custom title + colour), the "Genesis" easter egg (3-condition gate) + **role-play reactions** (title tier × manual tier, lottery-picked, guild/say/party, and the scheme name is a clickable link to the receive page).
- **🧪 Real-client forensics for links/colour codes** (1.73.35 → 1.74.0): whether custom links survive the server, the true 250-byte message cap, hover mechanics, on-disk ledgers — nailed down the "colour-code sending rules" (one colour segment first + **must carry a link**, 1 msg/sec, only `[EHPF#]` is recognised).
- **🖥 Title-bar badges + tier colouring** (1.73.55 → 1.74.0): combat-HUD / status-UI title bars share one layout — player name → title → tier badge → current profile; profile rows are tier-coloured (HUD + config + templates share one tier computation).
- **💬 Chat names: coloring + right-click menu** (1.73.12 → 1.73.29): after pinning down that the name lives in `arg2` and the name slot does **not** parse rich text, plan A (swallow the client line, compose our own) finally colors names by class; right-click offers **whisper / invite / target / guild invite / copy name** (copy = **prefill `/s name`, never auto-send**); translucent narrow menu with adaptive height.
- **🧰 Toolbox dialog spec** (1.73.30 → 1.73.34): frame-level ladder (config 10 · edit 100 · input 220 · toolbox 200 · dropdown 250), drag handles must be Buttons, single-source column geometry, and the **scrollbar** brought up to spec (single-source wheel direction `EVAL_WHEEL_DIR` · dedicated scroll gutter · integer page numbers · arrows hidden at the ends).
- **🔋 Condition names and the syntax gate** (1.73.27 → 1.73.28): power names are computed **at display time** from `UnitPowerType` (mana / focus / rage / energy, druids follow their form) with the parser accepting every spelling (so exporting and re-importing never drops conditions); `luacheck` now parses **every file** (27 `.lua`) instead of one.
- **🔍 Shared-profile aura fix + guide on every load** (1.72.2): when another character never learned a debuff texture, the addon now **falls back to a name scan and self-heals** (a hit learns name→texture, then the fast path); the starter guide prints **on every load**; also fixed the `EVAL_DS_HUD` frame name shadowing its own global function (which made `/eh ds hud` silently dead)
- **⌨️ Profile hotkeys actually work** (1.71.16 → 1.72.0): after four dead ends, `ACTIONBUTTON<n>` + hooking `ActionButtonDown/Up` — zero cost: no macro slots, no stolen keys, live while the game runs.


## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.74.12** | ✂️ Split-use for consumables (fixes "one click eats the whole stack") + 🔍 probe command | ①This client's `UseContainerItem` consumes the **entire stack** (user-confirmed) → now we `SplitContainerItem` **one** off, `PutItemInBag` (a different bag) it, and use that single item; ★if splitting fails we **refuse honestly** instead of falling back to whole-stack use; ②new probe `/eh go 消耗品探针 [name]` (measures items-per-use, verifies counts, probes split APIs) |
| **1.74.11** | ⏱️ Feeding interval raised to 2s (above the 1.5s GCD) + 🧹 bag-candidate type filter | ①Feeding rate 1s → **2s** (leaves headroom over the 1.5s global cooldown, so the next feed never fires before the GCD is ready); queue entries are **consumed on dequeue** (no re-execution); ②both helpers' candidates now **drop non-edible items**: weapons / armor / quest items / poor quality (ore, herbs, junk); items whose type can't be read are **kept** (unknown ≠ inedible) |
| **1.74.10** | ✨ Cancel Self Buff: multi-select + 🐛 fix overlap + ✏️ duration wording | ①The cancel-buff cell becomes a **multi-select panel**: live self-buff scan + recorded auras + custom input, default "Any" = cancel all (stored as `取消自身buff:名1,名2`); ②the self-debuff row no longer overlaps "Any negative" with "Remaining time" (type cell moved to a free slot); ③"剩余" renamed to "时长" throughout |
| **1.74.9** | 🐛 Fix: empty entry in the skill dropdown | An action-bar slot whose tooltip read comes back blank passed the old `if name` check (empty string is truthy in Lua), so `wslots[""]` existed and the dropdown's first row was blank; such names are now dropped per the "unknown ≠ absent" rule, and the **slot number is logged** so the unnamed slot can be identified |
| **1.74.8** | ✂️ New skill action: Cancel Self Buff | In a plan, add `取消自身buff` (cancel every cancelable buff) or `取消自身buff:<aura>` (cancel just that one); a slot-free special skill alongside Cancel Cast / Stop Attack / Follow, always ready, icon borrowed from the aura itself, and it **honestly names** what it skipped instead of cancelling something else |
| **1.74.7** | 🐎 Riding · One-click dismount | New toolbox group: on-screen icon, left-click dismount (mount = cancelable aura via CancelPlayerBuff), right-click menu, optional auto-dismount |
| **1.74.6** | ☠️ **Self/target debuffs support "dispel type"** | Same rules as party/candidate debuffs: parse `name(type)` · filter by type when evaluating (**name matched but type differs = NOT a hit**) · **empty name + type = "any debuff of that type"** · one shared formatter (export tokens / localized display); also restores the type suffix `candDebuff` used to drop |
| **1.74.5** | 🎬 Share "scene lines" + 🧰 two toolbox helpers (auto-feed / consumables) | 40 scene lines (accept/ignore × with/without target × 3 languages; title coloured by tier, exactly one colour code) · profile author/source in 4 kinds + profile-list tooltip · all 8 "no popup" branches are logged now · the easter-egg reaction is **no longer wired** (kept) · hunter auto-feed & consumable helper share one 8×N icon grid (unverified features are marked "to be tested") |
| **1.74.4** | 🐞 Fix "invite shown for someone already in your party": require the target NOT be in your group | 1.74.1 only checked YOUR state → leader + already-in-party showed both "Invite" and "Kick" (contradiction); now: target not in your group AND (not in a party or you're the leader) |
| **1.74.3** | 📥 Fix "party-channel share never pops up" (user report) | In 1.12, party messages from the **leader** fire separate events `CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER`; the receiver registered only the plain ones → a leader's share never arrived. Both leader variants now registered |

> 📜 Detailed per-version notes live in **[CHANGELOG.md](CHANGELOG.md)**; earlier history is in the git commit log.

## 🧩 Case Templates (11 groups, 29 ready-made profiles)

> No need to build from scratch. Config window → "One-key macro" tab → **`[Case Templates]`** at the bottom → pick one by class, **click to import**.

| Item | Description |
| :-- | :-- |
| **Entry** | Config window, "One-key macro" tab, bottom `[Case Templates]` button |
| **Contents** | **11 groups / 29 profiles**: 战士 / 法师 / 通用法系 / 盗贼 / 猎人 / 骑士 / 牧师 / 德鲁伊 / 术士 / 萨满 / 队伍·团队 (group headers keep the addon's own names) |
| **Layout** | Two columns by group, wrapping inside a group; **hover** a row to see its skills and conditions |
| **Import** | One click turns it into a profile — then edit, rename and bind a key as usual |

The **Party·Raid** group (6 profiles) covers one-key healing and one-key dispelling. All of them are written as
"**explicit skill + party (raid) member condition**": the condition scans the group, picks the lowest-HP member,
switches target, casts, and restores your original target — **you never click a teammate**.

> 💬 Got a good profile? Share it in the addon comments, or use `[Share]` in the config window to post it to guild / party / say.

## UI Preview

**Config window · Global tab** (`/eh cfg` or the EH icon next to the minimap): log / UI toggles + built-in help

![Config window · Global tab](preview/main.png)

**Case-template window** (bottom of the one-key macro tab, `[Case Templates]`): 11 groups / 29 ready-made profiles grouped by class, laid out as **two columns of groups with wrapping inside each group** — one click imports a profile, hover shows its contents

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
