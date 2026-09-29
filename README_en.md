# EvalHelp — All-Class Toolkit

> 🌍 Languages: [中文](README.md) · **English** · [Русский](README_ru.md) (in-game language: flag switcher at the top-right of the config window)

> 🗣️ Note: rule text (skill names / condition keywords / import-export snippets) stays in the client language (Chinese) — the rule data layer is never translated.

> EmberVeil (1.12.1 / Lua 5.1) **all-class toolkit addon**: a one-line macro body `/run EVAL_GO()`, driven by a rule engine — **five skill categories** (character actions / character skills / pet commands / target selection / item use) × **49 condition types** (grouped dropdowns; the member-picker row additionally offers 4 "candidate" conditions) × multiple key-bound profiles, all configured visually, for any class. Five more built-in pages: a **Toolbox** (merchant / social / quest automation / three helpers / rare alert relay / **loot under cursor**), **Quests & Gear** (chains · gear · four search kinds + a world-map annotation layer, requires UnrealQuest), an **Icon library** (the client-built-in macro icons: grouped, hover shows the path, searchable and pageable), a **Pet helper** (pet abilities → taming source → spawn-point lookup) and **Sub-addons** (enable/disable optional sub-addons).

| Module | Entry | At a glance |
| :-- | :-- | :-- |
| 🗡️ **Universal one-key macro** | macro `/run EVAL_GO()` | Five skill categories: character actions (Attack / Auto Shot / Shoot / Cancel Casting / Stance swap) / skills / pet commands / target selection / item use; unlimited skills per profile (scrollable list); up to ≤12 profiles, each bindable to its own key for direct triggering |
| ⚙️ **Config window** | minimap EH icon · `/eh cfg` | Fully visual editing of profiles / skills / conditions (**four-state relations** `&` / `|` / `&&` / `||`, so you can nest OR inside AND), plus text import/export for sharing; **seven tabs**: General · Macro Setup · Toolbox · Quests & Gear · Icon library · Pet Helper · Sub-addons |
| 📤 **Profile sharing** | `[Share]` on the config "one-click macro" page / chat link | chunked send to guild/party/say (rate-limited), the receiver clicks [Import] to commit; **tier cover** (`[tier manual · name]` clickable link + confirm popup) · **score tiers** (since 1.74.21: ≥50 points **and** 4+ of the 5 condition groups covered for Divine · five colours) · **title gacha** (5×15 · custom title) · the "Genesis" easter egg · the receiver lottery-replies with a role-play line (title tier × manual tier) |
| 🧩 **Case templates** | config window, one-key macro tab, bottom `[Case Templates]` | **12 groups / 38 entries** ready-made profiles (grouped by class) → **grouped two columns + wrapping within a group**; one click to import, hover to see what's inside |
| 🧰 **Toolbox** | config window, tab 3 | **UI tools** (map zoom / drag handles / per-layer tweaks / **loot under cursor**: window snapping + one click = next item / **top info bar**: zone·money·bags·network·professions·memory) · merchant assistant (auto-repair / auto-sell grey / buy & discard by name / **item prices**: learn real prices at a merchant · hover shows a price line · bag & bank valuation) · party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices** (multi-select keywords) / class-colored names in chat / right-click name menu / on-demand /who lookup) · quests (auto accept & turn-in, hold Shift to pause / notification channel) · **three helpers** (one-click feed · hunter / consumables / one-click & auto dismount) · **rare alert relay** (a chat line the moment the quest addon spots a rare — click the name to target it) |
| 🧭 **Quests & Gear** | config window, tab 4 | **Chain view**: one chain laid out node by node (quest · level · reward, each node with a magnifier); **Gear view**: obtainable gear listed by level (weapons first · kind multi-select · placeholder for missing icons); **four search kinds**: quest / item / mob·NPC / object (instant, unlimited drill-down); a **Tree sub-page** (parent-child quest hierarchy from the site's unlocks/requires union; indentation is the hierarchy, multi-parent nodes are labelled); **zone and level multi-select** filters; row tails carry **reward icons plus required-material icons** (the "Req" marker lists every material on hover, quest items are filtered out); **world-map annotation layer** (16 categories redrawn live; a **magnifier at the map's right edge opens the category dropdown** and clicking outside closes it; annotations are **also drawn on the minimap**; requires UnrealQuest) |
| 🖼️ **Icon library** | config window, tab 5 | The client's built-in macro icons grouped by prefix, hover shows the path, searchable and pageable; plus a "used by this addon" group (listing the icons this addon uses) |
| 🐾 **Pet helper** | config window, tab 6 | Search pet abilities (icon + per-rank list) → detail page: description / required level / **taming source** (which mob, where) → the magnifier jumps to Quests & Gear for spawn points |
| 🧩 **Sub-addons** | config window, tab 7 | Enable / disable optional sub-addons and open their UI (currently **Layer Debug** EH_DebugBox); the simple map and friends became main-addon toolbox modules |
| 🔍 **Status info UI** | `/eh st` | Live overview of all state variables + per-condition √/× verdicts for the most recent casts |
| 📝 **Status log** | `/eh` | Written to both the chat frame and the log file |

> 📌 Continuously improving — testing and feedback welcome!　🐞 [Bug reports / suggestions](https://gitee.com/xeval/emberveil_eval_help.git) (Issues)　🤖 Developed with DeepSeek Harness AI assistance (see "Contributing" at the bottom)

## 🏁 Milestones (1.52.0 → 1.75.43)

- **🐾 Feed Pet helper: the progress bar actually works now + real-time decay estimate + icon geometry**（1.75.42）：the bar had **never been displayed since 1.75.10** — its auto-start predicate `EVAL_HH_ENABLED` was **never defined anywhere** (so the engine never started; the saved variables had no `hhHappyProbe` key as proof) ⇒ it now uses the file's own master gate `hhOn()`: the percentage is aligned with the **measured happiness band** (0 / 33 / 66 / 100 — green→yellow lands exactly on 66%), the decay is **measured per loyalty tier** (top loyalty 7.2 points/s = 0.72%/s as the anchor, lower tiers filled in by measurement — **no invented multipliers**), and the bar refreshes **every 0.2s** (single paint entry / single colour source / really removed when turned off); icon geometry is unified into two **identical** black slots (bottom bar · square 26×26 · 18px centred image).
- **🧹 Restored 7 definitions wrongly deleted by the 1.75.34 orphan cleanup + a repo-wide dangling gate**（1.75.42）：a real-client error `attempt to call global 'shNoPop'` exposed collateral damage from that cleanup ⇒ a **full audit** (517 deleted names classified into hard / soft / zero references) and **verbatim restoration of 7 definitions** (the share “no popup” log outlet · the quest-line tooltip-handle port (**guarded ⇒ died silently**) · 2 diagnostic commands · 1 probe read port); plus a new gate, **`scan_dangling.js` part 2 · repo-wide** (the old version only scanned the `addons/` subfolder ⇒ the main plugin files were a blind spot) that separates **“unguarded = guaranteed crash”** from “guarded = silent death”.
- **🧾 Top info bar + 💰 Item prices**（1.75.40 / 1.75.43）：the toolbox gains a **six-segment info bar** (zone · money · bags · network · professions · memory; ported from the open-source SimpleInfoBar / MIT, same feature scope, new implementation and look) and **item prices**: while a merchant window is open the real sell price is extracted from the tooltip (the amount only arrives in the global `arg1` and is the **whole-stack total**), with vanilla base prices as fallback; hovering bag / bank / loot / quest-reward items shows a price line (stack total + per-item price); ★ it reads **no private fields of any third-party addon** and ships 13,994 base prices with sources / licence.

- **🎯 Skill editor: multi-select for aura conditions** (1.75.39): the ten buff/debuff conditions (self / target buff·debuff + party·raid + candidate) now accept **several auras** (tap to toggle, searchable, custom input; checkmarks survive closing and reopening the list) — **any selected one passing is enough** (OR); the "not / lacking" direction is its dual (**every** item must need a refresh, not "one missing is enough"); the first row of the list states the rule, hovering the name cell lists every selected item + direction, and the log / condition trace reports "any hit → X" / "all must → X"; ★old saves need no migration (cd.s still read, single-value export byte-identical)
- **🛡 Drag Frames: anchor blocks + attribute guard + fast tier** (1.75.36f~n, shipped with 1.75.37): the final fix for the bottom-bar trio "floats up on keypress / does not return after combat / scrambles after /reload" — **every persistent layer gets its own anchor block under UIParent** (absolute coordinates, CENTER←CENTER anchor ⇒ scale-independent; the three old pitfalls — inter-anchor chains / unit mismatch / stale world coords — gone at once; per-layer colour + title + alpha 0.8, shown only in edit mode and hidden with it); the **attribute guard** polls read-only every 0.3s and writes only on drift, heals position only in combat, toggle = edit ⇄ guard mode; when something moves it switches to a **bounded 30 fps window** (`/eh go 框拖拽守卫 压测` measures the real per-tick cost); chat frames get position-only guarding.; 1.75.38: the **stance bar and the bonus action bar** are persistent layers too (one anchor block each; keys untouched → saves and guard records unaffected)
- **🐾 Pet Helper: per-creature attack speed + pet list view** (1.75.36 → 1.75.37): attack speed is **per creature** (552 Petopia entries reconciled 552/552; same family spans tiers — cats 1.0~2.0 while 471/552 are 2.0) — the skill detail lists each tame source's own speed ("?" when unknown, never faked), family tooltips carry **family range + fast named pets** (Broken Tooth 1.0 · Deathmaw 1.2 · King Bangalash 1.4 · Rak'Shiri 1.5…) + Frenzy points; new **pet list view** (skills ⇄ pets toggle, sorted by speed, icon skill column, zone names EN→CN 52/52) also covers the 12 rare pets missing from the teaching table.
- **🔎 One-key Auto Attack now stays on + probe housekeeping** (1.75.31 → 1.75.35): the auto-attack top-up does a **live range re-check before pressing** plus a **bounded recheck window** — when a target enters range, or a spell/target switch cancels it, it comes back by itself in ≤1.25s (no extra key press needed); we also removed **487 orphan test read-ports (−185 KB of source)** and moved 23 probe commands into `tools/Probes.lua` (toc-preloaded, **zero load-time side effects**); combat-UI skill cells now use a dark fill + a 4×1px gold border.

- **🔀 Two-level condition relations (plan B) + seamless name-cache refresh** (1.75.28): the relation cell is now a **four-state cycle** `&` same-term AND / `|` same-term OR / `&&` term-to-term AND / `||` segment-to-segment OR (precedence `& > | > && > ||`) so you can finally write **OR inside AND**: `(A|B) & C`; ★ **zero migration** (old text evaluates identically; a 152-case harness checks it); the chat name cache now **keeps old values and refreshes in the background**; ★ **four real fixes** (the execution gate only knew the old storage format, so new-format rules became unconditional and fired on every press on yourself · text export lost conditions · joint party selection was applied per term instead of per old group · aura lookup now normalises colons); the skill editor gained **operator help on hover**; the case template "Guardian of One" was replaced by the live profile "Lifelong Vigil" (12 skills).

- **🎨 Chat-name extras + by-name aura fixes** (1.75.27): the "Color chat names" row gained a **[Settings] multi-select** (Level / Zone; Level on by default) — format `[zone][level][name]` (zone = green on your map · level = difficulty-coloured · name = class-coloured link, still clickable); the name cache gained level/zone columns with a **5-minute lazy TTL** (an expired name is re-fetched on its next appearance via local re-harvest + active /who — no full-roster polling); ★fixed "Cancel self-buff: X says 'not present' while it is" in three layers: the name reader checked `SetPlayerBuff`’s **return value** (always nil ⇒ the by-name path never worked — the real culprit) · colon normalisation on both sides now · prefix parsing no longer rewrites the name itself (`item:`/`stance:` fixed the same way).
- **🧲 Loot under cursor (one click = next item)** (1.75.26): the loot window **snaps under the mouse when it opens**, then **every click brings the next item under the cursor** (it says "nothing left" only at the end); ★ the hook runs **after the native `OnClick`**, never on mouse-down (moving the window on press makes the *release* land on another slot ⇒ **you loot the next item and skip this one**); ★ **slot-compaction is proven at runtime** (slot-name maps compared before/after each click — if the client compacts, the window is moved back and switching happens in place, so nothing is skipped); plus **quality marks** (gold = coins) and an optional **follow-mouse** mode; ★ the window is only **shifted in place, never `ClearAllPoints`** (the old way let the client re-add its own anchor ⇒ two vertical anchors on one frame **stretched the window**; now with open-time cleanup + `/eh go lootcursor fix`). The toolbox "Quests" category also went from two headers to one group.
## Changelog

| Version | Theme | One-line highlight |
| :-- | :-- | :-- |
| **1.75.43** | 💰 **Item prices: merchant-price learning + hover price line + bag / bank valuation** | ① This client has **no** “sell price by item id” API (`GetItemInfo` stops at texture) ⇒ the price can only be extracted while a **merchant window is open** via `OnTooltipAddMoney` fired by `GameTooltip:SetBagItem` (the amount arrives **only in the global `arg1`** and is the **whole-stack total**) ⇒ learning is **side-effect free**; “**not sellable**” and “**not learned yet**” are recorded separately and **a 0 price is never written**; three tiers = learned price → vanilla base price (marked “base”) → **nothing written** (not found ≠ free); ② the hover price line covers bags / bank / loot / quest rewards (stack total + per-item price in brackets); ③ ★ it reads **no private fields of any third-party addon** (unrealUI / OneBag / pfSellData etc. appear **0 times**), and ships 13,994 base prices with sources / licence; ④ one row in the toolbox “Merchant” group (default off = opt-in), `/eh go 物品价`. |
| **1.75.42** | 🐾 **Feed Pet helper: the progress bar really works + real-time decay estimate + icon geometry** + 🧹 **restored 7 definitions wrongly deleted in 1.75.34 + repo-wide dangling gate** | ① ★ fixed “the feed progress bar **has never been shown**” (its auto-start predicate `EVAL_HH_ENABLED` was **never defined anywhere** ⇒ the engine never started); ② the percentage is aligned with the **measured band** and clamped into it (“green → yellow” = **66%**, no longer 100%); ③ **decay** feeds the estimate: top loyalty **7.2 points/s = 0.72%/s** as the anchor + **measured per loyalty tier** (no invented multipliers for tiers 1–5) + **0.2s live refresh** (single paint entry / single colour source / really removed when off); ④ icon geometry: the bar moved to the **bottom**, structurally identical to the top XP bar (thin black, no highlight line) · icon back to **square 26×26** · inner image **18px centred**; ⑤ ★ **restored the 7 wrongly deleted definitions** (exposed by a real-client error): share log outlet · quest-line tooltip-handle port (guarded ⇒ **died silently**) · 2 diagnostic commands · 1 probe read port; ⑥ toolbox: retired the “pending test” exclamation marks · fixed the **orphan trailing group header** · added a **repo-wide dangling gate** (separating “crash” from “silent death”). |
| **1.75.40** | 🧾 **Top info bar (ported from the open-source SimpleInfoBar, MIT)** | Six segments (zone · money · bags · network · professions · memory): **same feature scope, new implementation and look**; three-language strings; one toolbox row (default off); `/eh go 信息条`; evidence readings land in `cfg.ibProbe`. |
| **1.75.39** | 🎯 **Skill editor: multi-select for aura conditions (OR logic)** + 🎛 **Drag Frames: stance bar / bonus action bar as persistent layers** | ① the ten buff/debuff conditions now take several auras: **any selected one passing is enough**, the "not/lacking" direction requires every item to need a refresh (old saves need no migration · single-value export byte-identical) · checkmarks are restored when the list is reopened (fixes "selected items invisible") · single-choice lists mark the current value with a gold dot · new "selected but not listed" group · the log reports the decision basis; ② two more persistent layers + renamed entries |
| **1.75.37** | 🐾 **Pet Helper: pet list view** + 🛡 **Drag Frames: anchor blocks + attribute guard** | ① new **pet list** (skills ⇄ pets toggle · 552 creatures sorted by attack speed · icon skill column · zones EN→CN 52/52); ② Drag Frames **anchor blocks** = one UIParent-absolute anchor block per persistent layer (CENTER anchor ⇒ scale-independent · per-layer colour + title · alpha 0.8 · shown only in edit mode, hidden with it) ⇒ fixes the "floats on keypress / no return after combat / scramble after reload" trio; ③ **attribute guard** 0.3s read-only polls, writes only on drift, position-only in combat, edit ⇄ guard modes; ④ **fast tier**: bounded 30 fps window while things move (`/eh go 框拖拽守卫 压测` measures real cost); ⑤ chat frames: position-only guard, size editing intact. |
| **1.75.36** | 🐾 **Pet Helper: per-creature attack speed + fast named-pet lists** | ① speed is **per creature** (552 Petopia entries reconciled 552/552 · four external sources agree) — same family spans tiers (cats 1.0~2.0), 471/552 = 2.0; ② the skill detail shows each tame source's **own speed** ("?" when unknown, never faked as 2.0), family tooltips carry **family range + fast named pets + Frenzy points**; ③ command `/eh go 宠物家族 攻速`; ④ 15 legacy names normalized + 2 adjudicated values; the generator throws on bad data (never silent). |
| **1.75.35** | 🔎 **Auto-attack fix + probe housekeeping** | ① auto attack: **live range re-check before pressing + bounded recheck window** (self-heals within ≤1.25s when a spell or target switch cancels it); ② **487 orphan read-ports removed** (−185 KB of source); ③ 23 probe commands moved into `tools/Probes.lua` (toc-preloaded, zero load-time side effects); ④ combat-UI skill cells: dark fill + a 4×1px gold border (target portrait kept). |
| **1.75.28** | 🔀 **Two-level condition relations (plan B: four connectors) + seamless name-cache refresh + the "rule became unconditional" fix** | ① relation cell: **four-state cycle** `&` / `|` / `&&` / `||` (precedence `& > | > && > ||`) ⇒ OR-inside-AND such as `(A|B)&C`; ② **zero migration**: storage is the linear `rule.expr` (old `groups` derived on the fly), old text evaluates **identically** (harness **152 cases**); ③ ★ three real regressions fixed: **the execution gate only knew the old format** (new-format rules fell into the legacy `when` path where `condOK({})` is always true ⇒ **fired on every press, casting on yourself**) · **export dropped conditions** · **joint party selection ran per term instead of per old group**; plus colon-normalised `auraTexOf`; ④ name cache now **keeps old values and refreshes in the background** (`tbNameStale`, 60s/name); ⑤ operator help in the skill editor (header = rules + precedence + examples, each cell = current + next); ⑥ case template "Guardian of One" → **"Lifelong Vigil"** (12 skills, line-by-line from a live save, end-to-end verified 12/12). |
| **1.75.27** | 🎨 **Chat-name [Settings] (level/zone extras) + 5-minute lazy cache TTL + "cancel self-buff says not present" fix** | ① the "Color chat names" row gained a [Settings] multi-select (Level on by default / Zone): format `[zone][level][name]` (zone = green on your map · level = difficulty colour · name = class-coloured clickable link); ② the name cache gained level/zone columns (single write point `tbNameClassPut`) + **5-minute lazy TTL** (single judge `tbNameFresh`; expired names are re-fetched on their next appearance via HEAL local re-harvest + active /who — no full polling); ③ ★"Cancel self-buff: X says not present while it is" fixed in three layers: **the name reader trusted `SetPlayerBuff`’s return value** (always nil ⇒ the by-name path never worked) · colon normalised on both sides (`auraNameHit` too) · prefix parsing no longer rewrites the name (`itemOf`/`stanceOf` same fix). |
| **1.75.26** | 🧲 **Loot under cursor: window snapping + one click = next item + quality marks (new tool module)** | ① new `tools/LootCursor.lua` (toolbox "UI tools" → "Loot under cursor"): the loot window **snaps under the mouse on open**, then **every click brings the next item under the cursor** (no waiting for the loot reply); ② ★ the hook runs **after the native `OnClick`** (never on `OnMouseDown`: moving on press makes the release land on another slot = loot the next item, skip this one); ③ "next item" = `lcNextSlot` (lowest occupied slot after i, else wrap) + ★ **compaction proven at runtime**; ④ quality marks (on by default · gold for coins · texture readback) + follow-mouse mode (off by default); ⑤ ★ **shift in place only, never `ClearAllPoints`** (the old way let the client re-add its own anchor ⇒ two vertical anchors **stretched** the window) ⇒ open-time cleanup + `/eh go lootcursor fix`; ⑥ zero action when off (unhook / hide marks / restore the open-time position); ⑦ the toolbox "Quests" category merged from two headers into one group. |

> 📜 Detailed per-version notes live in **[CHANGELOG.md](CHANGELOG.md)**; earlier history is in the git commit log.

## 🧩 Case Templates (12 groups, 38 ready-made profiles)

> No need to build from scratch. Config window → "One-key macro" tab → **`[Case Templates]`** at the bottom → pick one by class, **click to import**.

| Item | Description |
| :-- | :-- |
| **Entry** | Config window, "One-key macro" tab, bottom `[Case Templates]` button |
| **Contents** | **12 groups / 38 profiles**: 战士 / 骑士 / 猎人 / 盗贼 / 牧师 / 萨满 / 法师 / 术士 / 德鲁伊 / 通用法系 / 通用 / 队伍·团队 (group headers keep the addon's own names) |
| **Layout** | Two columns by group, wrapping inside a group; **hover** a row to see its skills and conditions |
| **Import** | One click turns it into a profile — then edit, rename and bind a key as usual |

The **Party·Raid** group (6 profiles) covers one-key healing and one-key dispelling. All of them are written as
"**explicit skill + party (raid) member condition**": the condition scans the group, picks the lowest-HP member,
switches target, casts, and restores your original target — **you never click a teammate**.

> 💬 Got a good profile? Share it in the addon comments, or use `[Share]` in the config window to post it to guild / party / say.

## UI Preview

**Config window · Global tab** (`/eh cfg` or the EH icon next to the minimap): log / UI toggles + built-in help

![Config window · Global tab](preview/main.png)

**Case-template window** (bottom of the one-key macro tab, `[Case Templates]`): 12 groups / 38 ready-made profiles grouped by class, laid out as **two columns of groups with wrapping inside each group** — one click imports a profile, hover shows its contents

![Case-template window](preview/skill_tpl.png)

**Skill editor** (opened via [Edit] or by clicking a skill icon): per-row independent condition editing — condition type / params all chosen from dropdowns (49 condition types, plus 4 "candidate" conditions reserved for member-picker rows; grouped as self / target / aura / party·raid member / skill), the relation column is a **four-state cycle** `&` same-item AND / `｜` same-item OR / `&&` new-item AND / `｜｜` new-segment OR (precedence `& > ｜ > && > ｜｜` — you can finally write 「OR inside AND」), live preview

![Skill editor](preview/skill_doif.png)

**Skill two-level dropdown · four kinds** (a skill row in the editor = `[Category▾][Item▾]` side-by-side double dropdown, options with icons):

- **Character skills**: whitelist + a scan of every skill on your action bars
- **Pet commands**: 8 pet commands (direct Pet API calls, no action slot), command icons self-learned from the pet action bar
- **Target selection**: 9 switch modes (nearest enemy / last target / target's target / by name / clear target…); the macro switches target first, then acts
- **Item use**: live bag scan (with icons + counts) + custom name — consumables used directly, equipment auto-equipped

**Aura checks (4 types, multi-select names)**: self buff / target debuff / target buff / self debuff (yes/no toggle, live items ◆○●▲) — the **name cell takes several auras** (tap to toggle, searchable, custom input; checkmarks survive reopening): **any selected one passing is enough** (OR), while the "not / lacking" direction requires **every** item to need a refresh; the first list row states the rule, hovering the name cell lists all selected items + direction, and the log says "any hit → X" / "all must → X" — `无buff:再生/治疗药水` drives one-key potion drinking, `无目标buff:奥术智慧/野性印记` drives buff rounds:

**Combat info UI + Status info UI** (`/eh ui` / `/eh st`): HP / power / target bars + profile switcher row + skill icon row (hover tooltip shows trigger conditions, lit gold = conditions currently met, click an icon to open its editor); the status window shows all state variables live + the recent-cast log (per-cast skill / target / per-condition √/× verdicts)

**Toolbox (Tab3)**: **UI tools** (map zoom / drag handles / per-layer tweaks / **loot under cursor**: window snapping + one click = next item / **top info bar**: zone·money·bags·network·professions·memory) · merchant assistant (auto-repair / auto-sell grey / buy & discard by name / **item prices**: learn real prices at a merchant · hover shows a price line · bag & bank valuation) · party & social (auto-confirm role check / hide guild login notices / **hide "joined·left channel" notices** (multi-select keywords) / class-colored names / right-click name menu / on-demand /who) · auto quest accept & turn-in plus notification channel (off / self / say / party; hold Shift to pause) · **three helpers** (one-click feed · hunter / consumables / one-click & auto dismount) · **rare alert relay** · ★this round **Layer dragging** becomes **anchor blocks**: in edit mode every persistent layer shows a small coloured block at its centre (absolute anchor), and a 0.3s read-mostly **attribute guard** keeps custom positions — not yet in this screenshot, to be re-shot; ★ the new “**top info bar**” and “**item prices**” rows, and the feed helper's new progress bar, are **also not in this screenshot yet — to be re-shot**

![Toolbox](preview/tools.png)

> ⚠️ **Requires** the **UnrealQuest** addon — every record shown here (quests / items / mobs / NPCs) comes from its database. If it is missing or disabled, this tab shows an installation guide instead and hides the controls.

**Quests & Gear (Tab4)**: **chain view** (one chain from start to end, node by node: quest · level · reward, magnifier on every node) + **gear view** (obtainable gear by level, weapons first, kind multi-select) + **four search kinds** (quest / item / mob·NPC / object; instant, top 10 matches, unlimited drill-down, hovering an item row shows the in-game item tooltip); **world-map annotation layer** (16 categories redrawn live as the map changes) tooltip

**Gear view**: obtainable **gear listed by level** (weapons first) — click an entry to see which chain grants it and which quests are required; gear whose icon is not in the local cache yet is drawn as a **placeholder**, and clicking it queues that item first rows with coordinates carry a map icon at the end

![Quests & Gear · gear view](preview/quests_item.png)

**Chain view**: from start to end, node by node — every node carries a **magnifier** (look the quest up by name) and a level badge; the "Map annotations (N)" control = category multi-select (5 gathering nodes + 11 town services, with all-on / all-off shortcuts), drawn live as the map changes-off shortcuts); checked categories are drawn live as the map changes

![Quests & Gear · chain view](preview/quests_line.png)

**Quest tree (parent / child quests)**: click a quest name inside a chain to expand its **prerequisites ⇄ follow-ups** — which quests this one unlocks and which ones must be done first (the site has two relation rows, plus a chain-next fallback); a tree is capped at 600 rows, and 「multiple prerequisites」 vs 「hit the cap」 are counted separately and reported honestly

![Quest tree (parent / child quests)](preview/quests_tree.png)

**Pet helper (Tab 6)**: search pet abilities (icon + per-rank list) → the detail page lists the description / required level / **taming source** (which mob, where) → the magnifier jumps to Quests & Gear for spawn points — from "which pet learns this ability" to "where to tame it", end to end — ★new this round: a **pet list view** (skills ⇄ pets toggle, 552 creatures sorted by attack speed, per-row speed column + skill icons) and **per-creature attack-speed data** (tame sources / family tooltips / `/eh go 宠物家族 攻速`) (screenshot to be re-shot)

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
