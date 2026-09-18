# TurtleWoW 插件生态清单（功能参考用）

> **用途**：仅供 EvalHelp 开发时**功能参考与对标**——了解同类插件做到什么程度、用了什么思路。
> 本文件**不是**依赖清单，EvalHelp 不依赖其中任何插件；也不代表推荐安装。
>
> **扫描来源**：`D:\soft\game\TurtleWoW\Interface\AddOns`（本机 TurtleWoW 客户端）
> **扫描范围**：104 个插件目录，合计约 235 MB
> **扫描时间**：2026-09

---

## 规模概览

| 项 | 值 |
| :-- | :-- |
| 插件目录数 | 104 |
| 总占用 | ≈ 235 MB |
| 内置模块（无 toc，不可管理） | 13 个（`Blizzard_*` 11 + `Turtle_General.pub` / `Turtle_GroupUI.pub`） |

**体积 Top 8**：TWThreat 50MB · Atlas 38MB · pfQuest 24MB · pfQuest-turtle 24MB · Automatonex 22MB · LunaUnitFrames 15MB · BigWigs 5.4MB · ShaguPlates 5.2MB

---

## 按功能分类

### 🗺️ 任务 / 地图 / 导航

| 插件 | 功能 |
| :-- | :-- |
| pfQuest + pfQuest-turtle | 任务数据库与地图指引（乌龟服数据） |
| Atlas / AtlasLoot / AtlasQuest | 副本地图浏览器 / 副本掉落查询 / 副本任务查询（三件套） |
| ModernMapMarkers | 副本、团本、世界Boss、船/飞艇/地铁位置标注 |
| PizzaWorldBuffs | 世界地图显示帐篷、龙头 Buff 计时、暗影马戏团位置 |
| FastQuest | 显示任务等级、把进行中任务载入追踪 |
| S_WorldMap / S_MiniMap | 简易世界地图（透明度可调）/ 简易小地图 |

### ⚔️ 团队 / 战斗辅助

| 插件 | 功能 |
| :-- | :-- |
| BigWigs | Boss 技能预警（经典团本预警框架） |
| TWThreat | 乌龟服原生仇恨统计（魔改免进战斗版） |
| XRS | 团队状态信息面板 |
| LootHog / RollTracker / XyTracker | Roll 点统计建议 / Roll 点监视过滤 / 许愿与出分记录 |
| shiqu 强制拾取 · LootFilter | 团长强制拾取 BoP / 自动过滤、开贝壳、确认装绑、摧毁垃圾 |
| AutoMarker | SuperWoW 自动标记团本怪物（带 GUI） |
| TSTargetMark / STargetMark | 目标姓名板标记箭头 |
| RangeController | `/FW` 调节战斗记录收集范围（低配降负载） |
| Warmup | 启动信息监视（插件内存占用） |

### 🧙 职业专属

| 插件 | 功能 |
| :-- | :-- |
| Heart (redHeart) | 治疗框架，依赖 C 库做血量/蓝量/buff 采集 |
| C | 公共函数库 + **隐形 tooltip**（多个插件依赖） |
| Decursive | 一键驱散（遍历团队解 debuff） |
| PallyPower | 圣骑士祝福分配助手（`/pp`） |
| Cryolysis | 法师法术/技能/材料管理 |
| DruidManaBar | 变形状态下显示法力条 |
| whx（曦） | 牧师一键宏（治疗/神打/震击/救赎/单刷斯坦索姆，依赖 UnitXP_SP3） |
| TrinketMenu | 饰品管理（自动换饰品） |
| Punschrulle | 高度可定制施法条 |

### 🎒 物品 / 背包 / 装备

| 插件 | 功能 |
| :-- | :-- |
| OneBag / OneBank / OneRing / OneView | OneBag 系列（整合背包/银行/环形/查看） |
| Outfitter | 一键换装（场景自动换，乌龟服定制版） |
| GBDSwitcher | 地精洗脑装置自动切换装备与动作条 |
| EN_AutoEquip | 一键切换套装 |
| Tmog | 幻化试衣间 + 收藏管理 |
| Fizzle | 角色面板显示耐久与品质 |
| S_ItemTip / RDbItems / StatCompare / BetterCharacterStats | 装等 / NPC 售价 / 属性对比 / 三维属性统计 |
| EQCompare | 聊天框物品链接与已装备对比 |

### 💬 聊天 / 社交 / 界面

| 插件 | 功能 |
| :-- | :-- |
| ChatMOD / ChatMats / S_ChatBar | 全能聊天增强 / 链接配方材料 / 聊天条 |
| IgnorePlus | 按玩家名或关键词屏蔽聊天 |
| PlayerLinkEnhance / PaleInk / SimpleWhisper | 玩家链接增强 / 多角色备注 / 简密 |
| zTip / !OmniCC | 单位提示增强 / 全界面冷却数字 |
| diminfo | 信息数据条 |
| MinimapButtonBag-TurtleWoW | 小地图按钮收纳 |
| MCP | 主菜单加「插件管理」（不退出游戏加载/禁用插件） |
| BaudErrorFrame | 错误报告增强 |

### 🛠️ 工具 / 自动化

| 插件 | 功能 |
| :-- | :-- |
| Automatonex | Automaton 工具箱强化版（60+ 小工具，`/auto`） |
| SuperMacro | 超长宏（7000 字）+ 按键运行 |
| SuperCleveRoidMacros | 智能宏（`/cleveroid`） |
| Meeting | 集合石（找队伍） |
| Interact | 零售版交互键移植 |
| NampowerSettings | Nampower 模组配套设置 |
| ActionBarProfiles / zBar / zBarEx | 动作条配置保存 / 额外动作条 |
| MonkeySpeed / MonkeyLibrary | 速度计 / MonkeyMods 公共库 |
| DoubleExperience | 双倍经验积攒查看 |
| FishingBuddy | 钓鱼助手 |
| AdvancedTradeSkillWindow | 增强商业技能窗口 |
| Chronometer | Ace2 计时器 |
| TurtleMail | 邮箱增强 |
| DebuffFilter | 增益/减益过滤到独立框架 |
| ShaguPlates | 姓名板（施法条、职业色） |
| LunaUnitFrames | 现代风格单位框架 |
| RangeColor / SmallerRollFrames | 动作条距离染色 / 缩小 Roll 框 |
| !Libs (2.27) | **不可禁用的基础函数库**（多数插件依赖） |
| UnitXP_SP3_Addon | UnitXP SP3 模组控制菜单 |

### 🎮 客户端内置（无 toc，不可管理）

`Blizzard_AuctionUI` · `Blizzard_BattlefieldMinimap` · `Blizzard_BindingUI` · `Blizzard_CombatText` · `Blizzard_CraftUI` · `Blizzard_GMSurveyUI` · `Blizzard_InspectUI` · `Blizzard_MacroUI` · `Blizzard_RaidUI` · `Blizzard_TalentUI` · `Blizzard_TradeSkillUI` · `Blizzard_TrainerUI` · `Turtle_General.pub` · `Turtle_GroupUI.pub`

---

## 对 EvalHelp 的参考价值（按优先级）

| 插件 | 可借鉴之处 |
| :-- | :-- |
| **Heart + C** | 队伍/团队采集范式：tick 新鲜度校验、隐形 tooltip 读客户端未暴露信息、名字↔unitID 缓存与宠物命名约定（1.71.1 队友扫描已参考） |
| **Decursive** | 一键驱散的目标遍历顺序与 debuff 类型判定、扫描节流策略（与队友驱散条件同域） |
| **Automatonex** | 工具箱功能的广度与模块化组织（Toolbox.lua 同源思路，见 `../Toolbox.lua`） |
| **PallyPower** | 职业专属分配的配置数据结构与角色分工表达 |
| **RangeColor / RangeController** | 距离状态的呈现方式与性能调节策略（对照我们的射程条件） |
| **pfQuest / Atlas** | 大数据量插件的懒惰加载与缓存组织（对照 DataSearch 数据检索） |

---

> 本清单仅为**功能对标参考**。EvalHelp 的运行不依赖以上任何插件（数据检索 Tab 依赖 UnrealQuest 属另一回事，见主 README）。
