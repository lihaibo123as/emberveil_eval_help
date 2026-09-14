# EvalHelp — All-Class Casting Helper

> EmberVeil (1.12.1 / Lua 5.1) addon: one-line macro `/run EVAL_GO()` driven by a rule engine — **5 skill categories** (Actions / Skills / Pet / Targeting / Items) × **28 conditions** (grouped dropdowns) × multiple key-bound profiles. Fully visual configuration, works for every class.
>
> 中文说明见 [README.md](README.md) · Русский: [README_ru.md](README_ru.md)

| Module | Entry | What you get |
| :-- | :-- | :-- |
| 🗡️ One-key macro | macro `/run EVAL_GO()` | Any action-bar skill, pet commands, target switching and item use in profiles; unlimited skills per profile; ≤4 profiles on separate keys |
| ⚙️ Config window | minimap EH icon · `/eh cfg` | Visual profile/skill/condition editing, md-text import/export |
| 📊 Combat info UI | `/eh ui` | HP/power/target bars + profile row + skill icon row (gold = conditions met, click to edit) |
| 🔍 State info UI | `/eh st` | Live state variables + per-press condition verdicts √× |
| 📝 State log | `/eh` | Chat + log file |

## Install

Download the latest `EvalHelp-vX.Y.Z.zip` from [Releases](https://gitee.com/xeval/emberveil_eval_help/releases) and extract to `Interface/AddOns/` (you should get `AddOns/EvalHelp/EvalHelp.toc`).

Or `git clone git@gitee.com:xeval/emberveil_eval_help.git` and place the folder as `Interface/AddOns/EvalHelp`.

## Quick Start

1. Drag your skills onto the action bars, then click **[Rescan Action Bars]** (General tab) or run `/eh go rescan`
2. Create a macro with body `/run EVAL_GO()`, drag it to a key and spam it
3. Profiles: `/eh cfg` → Macro Setup → [Add Skill]; Shift+macro key cycles the active profile
4. Run a profile directly: `/run EVAL_GO(2)` or `/run EVAL_GO("Name")` — bind different profiles to different keys

## Example profiles

```
# Profile: One-click补给 (auto potion)
- 物品:弱效巨魔之血药水 | 无buff:再生

# Profile: Pet assistant (hunter/warlock)
- 宠物:攻击 | 战斗中 & 可攻击
- 宠物:被动姿态 | 非战斗
```

Note: rule text (conditions, skill names, import/export) stays in the client language — only the UI shell is localized (zhCN/enUS/ruRU, flag selector top-right of the config window).

## Commands

`/eh` state log · `/eh cfg` config · `/eh ui` combat UI · `/eh st` state UI · `/eh go` status · `/eh go rescan` rescan · `/eh go list` profiles · `/eh go io` import/export · `/eh debug` verbose decisions · `/eh help` all commands

> 📌 Under active development — feedback welcome via [Issues](https://gitee.com/xeval/emberveil_eval_help/issues). 🤖 Built with DeepSeek Harness AI assistance.
