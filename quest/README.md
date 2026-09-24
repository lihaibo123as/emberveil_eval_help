# quest/ —— 任务线数据（独立工具区）

> 这个目录是**任务线检索**的数据源与生成工具。**与插件源码零耦合**：
> 插件运行期只读 `QuestData.lua`（纯数据）与 `QuestChains.lua`（纯逻辑），**从不调用这里的脚本**。

## 文件分工

| 文件 | 角色 | 进发布包？ |
|---|---|---|
| `fetch.js` | 抓取器：把 `database.emberveil.org` 的页面抓成 JSON 落到 `cache/` | ✗（开发工具） |
| `chains.js` | **策展清单**（人工知识）：哪 62 条任务线值得做、完整任务 ID 序列、阵营/档位/地区/点评 | ✗ |
| `build.js` | 生成器：读策展清单 + 缓存 → 产出 `QuestData.lua`（策展链） | ✗ |
| `sweep.js` | **全量任务列表**抓取（10-60 全部页；列表页自带奖励物品 id/品质/图标） | ✗ |
| `sweep_details.js` | **物品页 + 任务详情页**逐条抓取（装备判定/属性 · 「本系列第 N/M 部分」） | ✗ |
| `sweep_quests.js` | 指定等级段**全部任务详情**批量抓（并发可调、可中断；`--seed` 附名人线） | ✗ |
| `seed_series.js` | **名人任务线种子**：按**英文**关键词搜索 → 抓详情 → 大型/开门/史诗线进数据 | ✗ |
| `refetch_series.js` | 解析器改动后**重抓带系列的任务页**（缓存里存的是解析结果，不重抓不会更新） | ✗ |
| `resolve.js` | 步骤 id 补全件（站点有的页只给步骤名不给链接）—— 生成器与审计**共用**，避免口径漂移 | ✗ |
| `fix_curated_report.js` | 策展链 ↔ 站点系列 对照报告（人工修 `chains.js` 用） | ✗ |
| `probe_*.js` | 抓取期探针（规模 / 载荷 / 标签 / 行结构 / 搜索参数 / 经典关键词命中），只读 | ✗ |
| `build_bulk.js` | 生成器：读上面两份缓存 → 产出 `QuestBulk.lua`（全量任务/装备 + 自动任务线） | ✗ |
| `audit.js` | **审计**：装备链接 / 任务链接 / 列表页↔详情页双向一致 / 任务线完整性（可 `--online` 重新抓对账） | ✗ |
| `probe_*.js` | 抓取期探针（规模 / 载荷 / 标签分布 / 行结构），只读 | ✗ |
| `cache/` | 抓取缓存（列表页 HTML + 物品/任务 JSON，可随时重建，已进 `.gitignore`） | ✗ |
| `QuestData.lua` | **生成物**：策展链纯数据表（无函数），插件载入它 | ✓ |
| `QuestBulk.lua` | **生成物**：全量任务/装备/自动任务线（紧凑串记法），插件载入它 | ✓ |
| `QuestChains.lua` | **逻辑层**：搜索 / 筛选 / 详情模型（纯函数，无 UI、无副作用） | ✓ |


界面接线只有一处：`DataSearch.lua`（数据检索 Tab 的「任务线」检索源）。

## 逻辑层对外接口（`QuestChains.lua`）

| 接口 | 作用 |
|---|---|
| `EVAL_QC_READY` / `COUNT` / `SOURCE` / `LIST` | 数据是否就绪 / 条数 / 来源 / 全量链列表 |
| `EVAL_QC_SEARCH(词, 上限, 过滤)` | 按链名/任务名/物品名检索（空词 = 全列） |
| `EVAL_QC_DETAIL(key)` / `LINES(key)` | 详情模型 / 文案行（位次或键都可） |
| `EVAL_QC_ITEM_ROWS(filter)` | **装备视图**（练级要装备）：`{ loMin, loMax, faction, kinds={[种类]=true}, weaponOnly }` —— `kinds` 是**种类多选集合**，空集/缺省 = 全部；★**全量优先**（`QuestBulk` 在 → 10-60+ 所有带装备奖励的任务都在），全量缺席才退回策展链派生 |
| `EVAL_QC_ITEM_CHAINS(id)` | 由装备反查**策展任务线**（反向索引；查不到如实 nil） |
| `EVAL_QC_BULK_READY/META/QUEST/ITEM` | 全量数据是否可用 / 统计 / 单条任务 / 单条物品 |
| `EVAL_QC_BULK_ITEM_ROWS(filter)` | 全量装备行（每行带 `quests` = 来源任务数组与 `chains` = 命中的策展链） |
| `EVAL_QC_BULK_SOURCES(id)` | 单件装备的**来源任务**（等级升序；「由装备反查要做哪些任务」的主线） |
| `EVAL_QC_SERIES_LIST/COUNT/DETAIL/FACTION` | **自动任务线**（站点「本系列第 N/M 部分」拼出；含 30-60 与大型/开门线；详情形状与策展链一致） |
| `EVAL_QC_ITEM_KIND(it)` | 物品种类（取生成数据的 `k`：剑/斧/…/锁甲/盾牌/其它） |
| `EVAL_QC_KIND_LIST()` | 种类清单（**现算**：只列数据里真有的种类） |
| `EVAL_QC_KIND_GROUPS()` | 两个分组（武器子类型 / 其它种类），界面据此画分组标题（末行「全部」清空由界面自己加） |
| `EVAL_QC_IS_WEAPON(it)` | 武器判定**唯一来源**（`dps > 0`） |

## 用法

```powershell
# 连通性自检（会自动带上本机代理 127.0.0.1:10809）
node quest/fetch.js probe

# 按名找任务 ID（策展加新链时用）
node quest/fetch.js search "Defias Brotherhood"

# 抓单个任务 / 物品
node quest/fetch.js quest 166
node quest/fetch.js item 2042

# 按 chains.js 的策展清单抓全套（任务 + 奖励物品），走缓存、缺什么抓什么
node quest/fetch.js all

# 生成 quest/QuestData.lua（改完 chains.js 后必跑）
node quest/build.js            # 用缓存
node quest/build.js --force    # 全部重抓

# —— 全量（10-60+ 奖励里有装备的任务；用户 1.75.9 要求）——
node quest/sweep.js 10 60        # ① 扫任务列表（81 页，列表页奖励图标是**截断显示**，只作参考）
node quest/sweep_details.js all 4  # ② 物品页 + 任务详情页（奖励的**权威来源**）+ 补抓详情页新出现的物品
node quest/seed_series.js 4      # ③ 名人任务线（英文关键词：Naxxramas/Onyxia/Quel'Serrar…）→ 大型/开门线
node quest/refetch_series.js 4   # ④（解析器改过后才需要）重抓带系列的任务页，刷新缓存里的解析结果
node quest/sweep_quests.js 30 60 4   # ⑤（可选，耗时）30-60 全部任务详情 → 系列覆盖更全
node quest/build_bulk.js         # ⑥ 生成 quest/QuestBulk.lua（发货口径：奖励里有装备的任务）
node quest/audit.js              # ⑦ 审计（装备/任务链接 + 双向一致 + 任务线完整性；--online 重新抓对账）
```

改完 `QuestData.lua` 后，按项目铁律跑两道闸门（都要 exit 0）：

```powershell
node luacheck.js
node test_engine.js
```

## 加一条新任务线

1. 在 `chains.js` 里加一条（`key` / 名称 / 阵营 `A|H|B` / 档位 `S|A|B` / 等级区间 / 地区 / `quests` 完整 ID 序列 / 一句 `note`）；
   - `rewards` **不用手填** —— `build.js` 会从任务详情页的「选择一件 / 直接给予」自动取，并按物品页的 DPS 自动判定武器。
2. `node quest/build.js`；
3. 跑两道闸门（`QUEST TOC CHECK` / `QUEST WIRING CHECK` / 断言组 191 会一起守着）。

## 约定（为什么这么设计）

- **数据只离线**：本客户端**没有网络与文件读取 API**，插件只能读 `.toc` 里载入的文件 ⇒ 数据必须**预生成**成 Lua。
- **脚本独立**：抓取需要外网代理，放进插件运行期没有意义且会拖累发布包 ⇒ 只把**两个 .lua** 打进包（见 `CLAUDE_REFERENCE.md` 发布流程第 9 步，`PACK LIST CHECK` 守着）。
- **位次即身份**：链的 id = 它在 `EVAL_QC_LIST()` 里的位次；搜索与详情都走同一个列表 ⇒ 界面拿到搜索结果直接开详情就不会错位（断言 ⑤b + 变异 M1 专门守这条）。
- **诚实失败**：数据缺失一律 `nil`／空表，`EVAL_QC_READY()` 让调用方区分「没数据」与「没命中」。
