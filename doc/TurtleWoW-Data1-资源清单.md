# TurtleWoW `Data1` 资源盘点（可被插件利用的部分）

> 生成方式：`node tmp/mpq_scan.js`（只读表头 + hash/block 表 + 解 `(listfile)`）
> 追加分析：`node tmp/mpq_query.js` · `node tmp/mpq_take.js` · `node tmp/wm_coverage_data1.js` · `node tmp/wm_overlap.js`
> 盘点对象：`D:\game\TurtleWoW\Data1`（22 个 `.mpq` + `Interface\Cinematics` 4 个 avi，共约 11.6 GB）

## 0. 先说两条本机口径

1. **`D:\game\TurtleWoW\Data` 已经不存在** —— 数据目录现在就是 `Data1`（`Test-Path Data` = False）。
   旧脚本 `tmp/wm_unpack.js` / `tmp/wm_coverage.js` 里写死的 `D:\game\TurtleWoW\Data\interface.MPQ`
   **已经指向不存在的路径**，要重跑必须先改这个常量（新脚本 `tmp/wm_coverage_data1.js` 用 Data1 全档重算，见 §3）。
2. **归档覆盖顺序（实证，不是猜的）**：`patch-Z.mpq` **最后加载**（优先级最高）。
   判据 = 同名文件内容对比：`Interface\FrameXML\GlobalStrings.lua` 在
   `patch-8` = **0 个汉字**、`patch-9` = **0 个汉字**、`patch-Z` = **41740 个汉字 / 5253 行**（如 `ABANDON_QUEST = "放弃任务";`）。
   本机客户端显示中文 ⇒ 中文那份必然盖在英文那份之上 ⇒ patch-Z 在 patch-8/9 之后。
   全部归档优先级（低 → 高）：基础档（`backup/base/dbc/fonts/interface/misc/model/sound/speech/terrain/texture/wmo`）
   → `patch.MPQ` → `patch-2` … → `patch-9` → **`patch-Z.mpq`**。
   ★同名的**块内容真的不一样**（样本 `Interface\WorldMap\Durotar\DRYGULCHRAVINE1.blp`：interface = 88580 字节 / patch-3 = 66708 / patch-9 = 65684 / patch-Z = 65684 但 md5 不同）
   ⇒ 取哪一档决定屏幕上的图长什么样，**提取一律按优先级取最高档那份**（`tmp/mpq_take.js` 已内置）。

## 1. 22 个归档总表

| 归档 | 大小 | 清单条目 | blp | 含 icons 路径 | 含 worldmap | 音频 |
|---|---|---|---|---|---|---|
| backup.MPQ | 6.1MB | 135 | 0 | 0 | 0 | 0 |
| base.MPQ | 12.0MB | 146 | 0 | 0 | 0 | 0 |
| dbc.MPQ | 4.0MB | 140 | 0 | 0 | 3 | 0 |
| fonts.MPQ | 1.2MB | 4 | 0 | 0 | 0 | 0 |
| interface.MPQ | 66.5MB | 4908 | 4644 | 2030 | 1475 | 0 |
| misc.MPQ | 6.3MB | 834 | 0 | 0 | 0 | 0 |
| model.MPQ | 182.3MB | 7838 | 0 | 0 | 0 | 0 |
| patch-2.MPQ | 8.7MB | 92 | 6 | 0 | 0 | 8 |
| patch-3.mpq | 1964.8MB | 16470 | 9560 | 552 | 1268 | 1799 |
| patch-4.mpq | 367.2MB | 4615 | 2926 | 115 | 323 | 79 |
| patch-5.mpq | 248.7MB | 2183 | 1779 | 0 | 215 | 22 |
| patch-6.mpq | 430.3MB | 3903 | 2602 | 84 | 393 | 59 |
| patch-7.mpq | 167.1MB | 1623 | 973 | 460 | 25 | 110 |
| patch-8.mpq | 462.2MB | 4976 | 3647 | 199 | 367 | 99 |
| patch-9.mpq | 483.3MB | 6358 | 4439 | 229 | 2624 | 314 |
| patch-Z.mpq | 319.2MB | 4571 | 1218 | 0 | 1218 | 3336 |
| patch.MPQ | 1820.8MB | 26350 | 17626 | 676 | 214 | 790 |
| sound.MPQ | 895.3MB | 3242 | 0 | 0 | 0 | 3241 |
| speech.MPQ | 218.6MB | 3327 | 0 | 0 | 0 | 3327 |
| terrain.MPQ | 1048.8MB | 2426 | 0 | 0 | 0 | 0 |
| texture.MPQ | 634.0MB | 42045 | 42045 | 0 | 1 | 0 |
| wmo.MPQ | 346.8MB | 5858 | 0 | 0 | 0 | 0 |

- **22/22 归档都解出了 `(listfile)`**，名字并集 **122067 条**（清单落 `tmp/mpq_lists/*.txt`，可直接 grep）。
- 加密归档（`patch-4/8/9/Z`）按 `FIX_KEY` + 扇区解密读通；未支持 **PKWARE implode** 与 **SPARSE** 压缩（见 §6 失败清单）。

## 2. ★最有价值的一类：客户端自己的 Lua / XML 源码

**归档里带着整份 FrameXML**（`interface.MPQ` 92 个 lua + 289 个 xml，各补丁再覆盖；并集 **431 个 FrameXML 文件**）。
已按优先级取出 **365 个**到 `tmp/mpq_out/Interface/...`（4.47 MB，纯文本，可直接 grep）。

已核实的、对项目直接有用的几处（都是**读源码而非猜**）：

| 文件 | 能解决什么 |
|---|---|
| `FrameXML/BonusActionBarFrame.xml` | `ShapeshiftBarFrame`（第 203 行）与 `BonusActionBarFrame`（第 48 行）**帧名与父级都有明文**（`parent="MainMenuBar"`）⇒ 工具模块里 `cands` 候选表不必再靠探针猜 |
| `FrameXML/MainMenuBar.xml` | `MainMenuBarTexture0~3`（第 232 行起）确认存在；★`MainMenuBarAnimFrame` **全份源码里搜不到**（LayerFix 的 `barBg` 清单里那一条没有本地证据） |
| `FrameXML/WorldMapFrame.xml` | `WorldMapDetailFrame`（第 443 行）与瓦片挂点（第 570 行） |
| `FrameXML/UnitPopup.lua` | 客户端**自己的**右键菜单条件（第 440~481 行）：`INVITE` 禁用条件 = `inParty and (not isLeader and not isAssistant)`；`UNINVITE` = `not inParty or not isLeader`；`LEAVE` = `not inParty`；`PROMOTE` 还要 `UnitIsConnected` 且名字不是自己 ⇒ 与队伍菜单三条条件（R5）**逐条一致**，可当权威口径 |
| `FrameXML/Hooks.lua` | 客户端**自己**就包 tooltip 方法（第 131~148 行：`{GameTooltip, ShoppingTooltip1, ShoppingTooltip2}`，取原方法 → 装包装 → **逐个透传返回值**）⇒ 包装手法与返回值口径有官方范例 |
| `FrameXML/GameTooltip.lua` | `SetPlayerBuff` **不在 Lua 里**（只在 `BuffFrame.lua:101/140` 被调用）⇒ 引擎侧方法，佐证「替换 widget 方法无效」的结论 |
| `FrameXML/LootFrame.lua` | 拾取窗真实实现（`LootFrame_OnEvent` @45、`LootButton_Update` 段 @155~199、`GetLootSlotLink` @237）—— 自动拾取调研结论可以逐行复核 |
| `FrameXML/UIDropDownMenu.lua` · `UIParent.lua` · `ChatFrame.lua` · `Minimap.xml`（`SetTrackingSpell` @169） | 下拉/父级/聊天/追踪的官方实现 |
| `Turtle_*.lua` | TurtleWoW 自研界面源码：`Turtle_TransmogUI`（`Turtle_TransmogSets.lua` 幻化套装表）· `Turtle_ShopUI` · `Turtle_GuildBankUI` · `Turtle_InspectTalentsUI`（`Turtle_TalentsData.lua` 天赋数据）· `Turtle_ArenaUI` · `Turtle_Barbershop` |
| `Interface\AddOns\*` | 客户端自带插件 83 个文件：`Blizzard_*` 源码 + `Turtle_General` / `Turtle_GroupUI` / **`LFT`（Looking For Turtle，含完整图集/音效/数据）** + 17 个 `.toc` |

## 3. ★世界地图探索层贴图（可让插件自带贴图从 18 图扩到 53 图）

`MapOverlayData.lua` 表里 53 图 / 1019 块，用 **Data1 全档**逐块核（`tmp/wm_coverage_data1.js`）：

- **53 图 / 1019 块 = 100% 齐全**，解压后合计 **44.8 MB**；
- 现 `media\WorldMap` 自带只有 **18 图 / 345 块**（那是当年只从 `Data\interface.MPQ` 挖的结果）；
- 可**新增自带** 36 图，例：`StonetalonMountains(38块)` `Redridge(30)` `Alterac(29)` `EasternPlaguelands(28)` `Barrens(26)` `Northwind(25)` `LochModan(25)` `SwampOfSorrows(25)` `Badlands(24)` `Silithus(24)` `Gilneas(23)` `Hyjal(23)` `Tirisfal(22)` `Wetlands(21)` `Tanaris(21)` `Feralas(20)`…（完整清单见脚本输出）
- 块来源分布：**patch-Z 供 656 块 · patch-9 供 363 块**（两档互补，缺一不可）；
- 重叠情况：1019 块里 **1010 块多档都有** ⇒ 「取哪一档」是硬判据（§0 已定优先级）。

★表外的图：Data1 里的地图名并集 **175 张**，比表里的 53 张多约 120 张（副本层、TurtleWoW 自研图：`BlackrockDepths2f`、`UpperKarazhan`、`WindhornCanyon`、`ThornGorge`、`StormwroughtRuins`、`EmeraldSanctum`…）。
这些**贴图在归档里**（例如 patch-9 有 132 张图），但**表里没有它们的尺寸/偏移** ⇒ 想接管得先有表数据（来源：`WorldMapArea.dbc` + `AreaTable.dbc`，或运行期 `GetMapOverlayInfo`）——**目前没做，别当成已有能力**。

## 4. 其余可利用资源

### 4.1 DBFilesClient 数据表（158 个，离线数据源）
`dbc.MPQ` 140 个 + 各补丁覆盖（136 个表多档都有，取最高档）。
关心的表都在：`spell.dbc` · `spellicon.dbc` · `talent.dbc` · `skilllineability.dbc` · `map.dbc` · `areatable.dbc` · `worldmaparea.dbc` · `faction.dbc` · `chrclasses.dbc` · `chrraces.dbc` · `itemclass.dbc` · `itemsubclass.dbc` · `spellcasttimes/spellduration/spellradius/spellrange.dbc` · `spellitemenchantment.dbc` · `itemdisplayinfo.dbc`。
★**没有** `item.dbc` / `itemcache.dbc` / `questcache.dbc` / `creaturecache.dbc` ⇒ **物品名/价格/任务奖励拿不到**，仍得走网站抓取（与现有 `gen_itemprices.js` 的结论一致）。

### 4.2 图标
全档 `Interface\Icons\` **4174 个**（`interface.MPQ` 2022 · `patch.MPQ` 671 · `patch-3` 551 · `patch-7` 460 · `patch-9` 227 · `patch-8` 199 · `patch-4/6` 等）。
运行期插件本来就靠 `GetNumMacroIcons`/`GetMacroIconInfo` 取，**不需要自带**；可取的是「离线校验某个图标名是否真的存在」（现有 `doc/图标路径清单.txt` 可用归档重新生成一份，更全）。

### 4.3 字体
`fonts.MPQ`：`ARIALN.TTF` `FRIZQT__.TTF` `MORPHEUS.TTF` `SKURRI.TTF`。
`patch-Z.mpq`：`ARIALN.ttf` `FRIZQT.ttf` **`FZBWJW.ttf` `FZJZJW.ttf` `FZLBJW.ttf` `FZXHJW.ttf` `FZXHLJW.ttf`** `MORPHEUS.ttf` `SKURRI.ttf.ttf`
⇒ 项目字体链里的中文那一条（`FZLBJW`）**确实随客户端提供**（在 patch-Z 里，不是散装文件）。★字体有版权，只能依赖客户端，不能随插件分发。

### 4.4 音频（约 1.2 万条 wav/mp3/ogg）
`sound.MPQ` 3241（`Sound\Creature` 1435 · `Character` 576 · `Item` 368 · `Spells` 285 · `Doodad` 199 · `Music` 127）
`speech.MPQ` 3327（NPC 语音）· `patch-Z` 3336（`Sound\Character` 2078 + `Creature` 1238）· `patch-3` 2008 · `patch.MPQ` 790 · `patch-9` 314（`Sound\Interface` 289）…
⇒ 想加音效时**有一大批 UI 音效名可查**（`Sound\Interface\...`）；但播放要走 `PlaySound`/`PlaySoundFile`，后者在本客户端是否存在仍是未验证项。

### 4.5 界面素材
`Interface\` 并集子目录：`WorldMap 4578` · `Icons 4174` · `Glues 451` · `FrameXML 431` · `ShopFrame 350` · `Buttons 160` · `TalentFrame 117` · `TransmogFrame 69` · `Cursor 37` · `Minimap 39` · `PvPRankBadges 17` · `FullScreenTextures` …
运行期要靠的几处已核：`Interface\Buttons\WHITE8X8.blp` ✅（interface.MPQ）· `Interface\TargetingFrame\UI-RaidTargetingIcons.blp` ✅（**只在 patch.MPQ**）· `Interface\Icons\INV_Misc_Head_Dragon_01.blp` ✅。

### 4.6 对插件基本没用的
`model.MPQ`（7838 个 .m2 模型）· `terrain.MPQ`（2352 个 .adt 地形）· `wmo.MPQ`（5858 个建筑）· `misc.MPQ`（World 的 .wlq/.wlw/.bls 等）· `backup/base.MPQ`（文档/安装器）· `Data1\Interface\Cinematics`（4 个 avi，95 MB 片头）。

## 5. 复跑命令（全部只读）

```bat
node tmp/mpq_scan.js                       :: 扫全部归档 → tmp/mpq_lists\*.txt + tmp/mpq_scan_summary.txt
node tmp/mpq_query.js                      :: 分类报告（WorldMap / Lua / 字体 / 图标 / DBC / 音频 / Interface 子目录）
node tmp/mpq_take.js --report "<正则>"      :: 某名字在哪些档里有
node tmp/mpq_take.js --take "<正则>" --out <目录> [--from <某档>] [--dry]
                                           :: 按优先级取最高档那份（--from 强制某一档，用于 A/B）
node tmp/wm_coverage_data1.js              :: 表内 53 图逐块核 Data1 → 整张齐全清单与体积
node tmp/wm_overlap.js                     :: 多档重叠统计 + 同名块逐档 md5 比对（样本）
node tmp/cmp_locale.js                     :: patch-8/9/Z 的 GlobalStrings 中英文对照（覆盖顺序判据）
```

## 6. 已知失败 / 未验证（如实记）

- **14 个文件取不出来**（`tmp/mpq_take.js` 报 `未知掩码`）：各 `Blizzard_*\Localization.lua`（12 个，patch.MPQ）· `Turtle_InspectTalentsUI\Turtle_TalentsData.lua`（patch-8）· `FrameXML\Options\Functions.lua`（patch-9）⇒ 属 **加密文件里的 SPARSE / 非 zlib 压缩**，读取器未实现，不是文件不存在。
- **旧的 `tmp/wm_unpack.js` / `tmp/wm_coverage.js` 指向的 `Data\interface.MPQ` 已不存在**，直接用会报错。
- **「客户端认不认插件目录里的 `.blp`」仍未真机验证**（与 1.75.53 判据里那条待验证项同一件事）。
- §0 的覆盖顺序是**离线实证**（中文覆盖英文），真机若要 100% 定死，可放一个同名小文件进两个 patch 档做 A/B；目前按 patch-Z 最高处理。
- DBC 是**二进制**，要读需自己解（无第三方路径依赖的前提下，先写解析器再说，别凭表名推断字段）。
