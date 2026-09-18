# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md` 与 git 提交历史，不进这里。
> **发布流程见第 2 节**（每次发版必做 **9 步**：文档 6 步 + 提交打附注标签 + 推送 + 出包建 Release）；**项目位置 / 当前版本 / 在途状态见第八节**「项目位置与现状」。
> **完整版本要点汇总在文档最末尾（第九节）**——超预算时**最先被截断的就是它**，属预期，不影响前面的铁律与判据。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**；★头部只保留比较新的记忆（最多 20 个版本）。
> ★要查「某个功能/某个坑现在怎么写」→ 先看第五、六节的判据，再看 `DEVELOPMENT.md` 与源码。

## ★★★发布 release 流程（用户定；每次发版必做 **9 步**）

> ★★**「release / 发布版本」= 下面 9 步全做完**，不是只 git push（用户 1.72.0 明确：
> 「release 要做的事也包含以上」——指推送 + 打附注标签 + 出 zip 发布包 + 建 Release 页）。

1. **统计里程碑**：根据上一次 release 版本至最新，统计**跨越了哪些版本、每个版本的里程碑是什么**。
2. **项目说明更新信息**：`README.md` / `README_en.md` / `README_ru.md`；★项目说明里的**版本记录只保留最近 10 个**。
   ★★**版本行必须插进「更新日志」表里，不能插进开头的「模块」功能表**（README 有**两张**表：
   开头那张是「模块 / 入口 / 一览」功能表，「## 更新日志」下面那张才是版本表）——
   1.72.0 实事故：用脚本插行时按「**第一张**表的表头分隔行」定位，把 4 个版本行插进了**功能表**里，
   用户在 GitHub 首页一眼看到功能表里混着版本号（★脚本按结构定位但结构假设错了：不报错、只是位置不对）。
   ★判据已落成源码检查 **`README TABLE CHECK`**（3 个 README × 版本行必须全在更新日志标题之后 × 恰好 10 行；
   CHANGELOG 则保留完整历史 ≥20 行），变异 3/3 全捕获 —— 插错表/少一行/删历史都会当场响。
   ★★**README 板块顺序（用户 1.72.0 定）**：**`## 🏁 里程碑` 在 `## 更新日志` 上面**
   —— 即「**项目文件内的更新日志在里程碑下面**」；1.72.0 已把里程碑整块移到更新日志之前，顺序由 `MILESTONE CHECK` 守着（反了当场 FAIL）。
3. **扫描项目文件内的旧版信息**：版本号、文件结构、功能清单、过时描述 → 逐处排查并清理。
4. **按「上次 release → 最新」更新对应板块内容**：README 的功能/用法板块、`DEVELOPMENT.md` 的架构板块等。
   ★★**README 的 `## 🏁 里程碑` 必须同步**（这是第 1 步「统计里程碑」的落地处）：
   ① 标题范围改成最新版本（如 `1.52.0 → 1.72.0`）；
   ② ★★★**整个板块只留 10 条、每条一行**（用户 1.72.0 明确：「里程碑在精简下，控制在 **10 个点、10 行文字以内**」）
   —— **不再按 `### <上次> → <最新>` 分小节**：最新的写最前面，超过 10 条就删最旧的（细节全在 `CHANGELOG.md`）；
   ③ 每条 = `- **emoji 主题**（版本范围）：做了什么 + 一句关键判据/教训`（**一条就是一行**，别堆细节）；
   ★★★**每条必须以 `- ` 开头（列表项）** —— 1.72.0 实事故：10 条写成**连续普通段落行**，Markdown 把相邻行
   **合并成一大段**（用户在 GitHub 上看到的就是「排版混乱」一大坨）；★这类「内容对、只是渲染不对」的坑行为断言照不到，
   只能靠结构检查守 —— 已是 `MILESTONE CHECK` 第⑤条（把任一条的 `- ` 去掉 → 当场 FAIL）。
   ★★**三语言同步**：zh / en / ru **都已有该板块**（1.72.0 起补齐）—— **不许只给某个语种补一小段**（会孤悬），
   要加就三语一起加；**新增/翻译都要三语言都更新版本表**。
   ★★★**是「归纳」不是「罗列」**（用户 1.72.0 明确）：「里程碑是要你总结上个里程碑到最新版本的信息归纳，
   而不是把版本信息全部罗列，不然内容太多了 —— **每次里程碑归纳内容最终控制在 10 条以内**」，
   随后又收紧：「**控制在 10 个点、10 行文字以内**」→ 细节归 `CHANGELOG.md`，板块里每条只留一句话。
   ★判据已落成源码检查 **`MILESTONE CHECK`**（第 17 道：3 个 README 都有 🏁 板块 + **里程碑在更新日志之前** +
   标题范围末端 == 当前 VERSION + **板块正文非空行 1..10** + **每条都是 `- ` 列表项**），变异全捕获。
   ★★**「如何总结里程碑」= 上面这三条**（① 归纳不罗列、**一条一行** ② 三语言一起 ③ **全板块 ≤10 行**），
   取素材走发布流程第 1 步（上次 release → 最新跨越的版本与各自的里程碑），细节一律留在 `CHANGELOG.md`。
5. **更新文件内的版本记录**：`CHANGELOG.md` 保留**完整**版本记录；`EvalHelp.lua` 的 `local VERSION` 与 `EvalHelp.toc` 的 `## Version` **同步**（`VERSION` 源码检查守着）。
6. **审计记忆体（本文件 `CLAUDE.md`）**：版本要点**汇总统计后放到文档末尾**；★**头部只保留比较新的记忆注意事项（最多 20 个版本）**
   —— ★**不要再把一堆逐版本记录堆到记忆体头部**（那是异常，会让文件超预算被截断，且把铁律挤出视野）。
7. **提交 + 打「附注」标签**：`git commit` → `git tag -a vX.Y.Z -F <说明文件>`。
   ★★**必须是附注标签（`-a`），不是轻量标签** —— 轻量标签只是个 commit 指针、**没有说明**，
   而 Release 页要用它的说明当正文（1.72.0 踩过：先打了轻量标签，只能 `git tag -a ... -f` 重打再强推）。
   说明内容 = 该版本的「头条 + 里程碑 + 安装方式 + 质量声明」，与 CHANGELOG 的详情小节同源。
   ★★**写标签说明文件绝不能用 PowerShell 的 `>` 重定向** —— `>` 默认写 **UTF-16LE**，
   `git tag -F` 按原始字节读进去 → 标签说明**整段乱码**（1.72.0 实踩：
   `git cat-file -p v1.72.0` 出来是 "E v a l H e l p" 这种夹 null 字节的样子）。
   正解：用 `write` 工具写 UTF-8 文件（无 BOM），或 PowerShell 下 `Out-File -Encoding utf8`；
   ★打完后**必须回读复核**：`git cat-file -p vX.Y.Z | Select-Object -Skip 5 -First 3` 应正常显示中文。
8. **推送（三个都推）**：`git push origin master && git push github master`，然后**标签也要推**
   `git push origin --tags && git push github --tags`（★只推分支不推标签 = Release 页找不到 tag）。
9. **出发布包 + 建 Release 页**：
   - **发布包** `EvalHelp-vX.Y.Z.zip`（放在 `Interface/AddOns/` 下，与仓库同级——**不要放进仓库**）：
     顶层一个 `EvalHelp\` 文件夹，内容 = `.toc` 实际清单（**必须按 toc 逐个核对**：
     1.72.0 发现随包的 `EvalHelp-v1.71.2.zip` **只有 25 个文件、缺 `IconBrowser.lua` + 5 个 examples** →
     用户装那个包会**直接报错**；正确包是 **60 个文件**）。打包脚本见下方「发布包怎么打」。
   - **Release 页**：★**这一步我（AI）做不到，需要用户手动操作** ——
     建 Release 要走 **GitHub/Gitee API + token**，而本机 `gh` CLI **未安装**、环境变量与凭据文件里
     **都没有任何 token**（实测 `POST /repos/.../releases` 返回 **401 Unauthorized**）。
     ★按会话规则**不申请权限提升**，所以**如实告知用户去网页建**，并把 URL 与要填的标题/说明/附件给全。
     GitHub: `https://github.com/lihaibo123as/emberveil_eval_help/releases/new`（选已存在的 tag → 标题 →
     说明可从 `git tag -n99 vX.Y.Z` 取 → 附件拖 zip → Publish）；
     Gitee: `https://gitee.com/xeval/emberveil_eval_help/releases/new`（同样选 tag + 上传同一个 zip）。

**更新日志维护规则（1.28.0 起，用户定）**：① 详情写 `CHANGELOG.md` 的 `## 🎯 vX.Y.Z — 主题` 小节（要点 / 典型用法 / 设计亮点，配一个 emoji）；
② `README.md` 顶部「更新日志」速览表加一行（`| **X.Y.Z** | emoji 主题 | 一句话亮点 |`，**最新在上**）；③ **README 不再放版本详情**（保持精简，详情只进 CHANGELOG）。

**发布包怎么打（第 9 步的脚本，实测可用）**：★在 `Interface/AddOns/` 下执行（**不是插件目录**），产物与仓库同级。
```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$src = "$PWD\EvalHelp"; $out = "$PWD\EvalHelp-vX.Y.Z.zip"
$staging = "$env:TEMP\eh_pkg"
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory -Path "$staging\EvalHelp" | Out-Null
# ★只装运行必需：.toc + 7 个 .lua 模块 + Locales + examples + media + 三语言 README/CHANGELOG/DEVELOPMENT
Copy-Item "$src\EvalHelp.toc","$src\Core.lua","$src\Engine.lua","$src\EvalHelp.lua","$src\Toolbox.lua","$src\DataSearch.lua","$src\Share.lua","$src\IconBrowser.lua" "$staging\EvalHelp\"
Copy-Item "$src\README.md","$src\README_en.md","$src\README_ru.md","$src\CHANGELOG.md","$src\DEVELOPMENT.md" "$staging\EvalHelp\"
Copy-Item "$src\Locales","$src\examples","$src\media" "$staging\EvalHelp\" -Recurse
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.72.0 基准 = **60 个**）：少一个就是缺文件，用户装了会**直接报错**。
★**不装**：`luacheck.js`/`test_*.lua`/`test_engine.js`（测试）、`preview/`（截图）、`node_modules/`、
`api_*.html`、`.git/`、`bindings/`、`_icons_scan/`、`pay/`。

**推送信息**：分支 `master`；远端 `origin`=gitee（`git@gitee.com:xeval/emberveil_eval_help.git`）、`github`=`git@github.com:lihaibo123as/emberveil_eval_help.git`（1.29.0 起双远程，每次**两端都推**：`git push origin master && git push github master`；本地仓库 = 插件目录本身）；★推送用**默认密钥 `~/.ssh/id_rsa`**（`gitee_id_rsa` 未被授权，别用 `-i` 指定它）。
★★**两个库一律走 SSH（`git@xxx` 形式）+ 本机默认密钥** —— 用户 1.72.0 明确：「发布两个库，记住都走 git@xxx 本地密钥形式」。
即：**不用 HTTPS、不用 token、不用 `-i` 另指密钥**；推送前先 `git remote -v` 核一眼**两个远端都是 `git@`**，
再用 `ssh -T git@github.com` / `ssh -T git@gitee.com` 双端验签（1.72.0 实测：GitHub `Hi lihaibo123as!`、Gitee `Hi eval(@xeval)!`）。
★两个远端名固定：**`origin` = gitee**、**`github` = github**。

## 一、铁律

### 1. ★★★改完必须跑语法检查 + 测试（本项目因它白丢过好几个版本的功能）
- **Lua 整文件编译**：任何一处语法错误 → **整个插件无法载入**，且 UE 日志里**看不到**（`%LOCALAPPDATA%\Azeroth\Saved\Logs` 是空目录——本客户端落盘日志通道全废）。
  1.9.0 曾有两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 **1.9.0~1.11.0 全部功能实际未生效**；旧的 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助。
- **每次改完 .lua 必跑两条，两条都要 exit 0**：`node luacheck.js`（fengari 真实 Lua 解析，报错带行号，显示 **SYNTAX OK** 才算完）+ `node test_engine.js`（`test_stub.lua` 打桩 WoW API/UI mock + 5.1 垫片，加载整个 `EvalHelp.lua` 后跑 `test_assert.lua`，显示 **ALL TESTS PASS**）。
  fengari 已装在工作区 node_modules（npm 走代理 `127.0.0.1:10809`）。
- ★★**判据必须同时看「退出码」与「输出文本」**：源码检查失败走 `process.exitCode = 1` 而**脚本照跑到底**，于是 `ALL TESTS PASS` **照样打印**——只看这句话会**漏报**。
  行为断言失败打的是 **`ASSERT FAIL`**，源码检查失败打的是 **`: FAIL`**（两者都要在输出里找）。
- **源码级检查**（`test_engine.js` 内，**改了对应区域就必须让它们继续通过**）：`WIN WIDTH`（窗口宽度单一来源）· `DECL ORDER`（**7 个文件**的顶层 local 声明早于使用）· `LAYOUT`（`EVAL_DS_BUILD` 布局常量）· `VERSION`（源码 VERSION == toc）· `LANG KEY`（`L("字面量")` 三语言齐全）· `LANG SOURCE`（取语言只认 `EVAL_GET_LANG`）· `WINDOW SIZE`（自建窗真的设了宽与高）· `COMMENT SWALLOW`（语句没被行尾注释吞掉）· `ICON`（图标素材真实存在）。
  后续又加到 **15 道以上**：`STOP ATTACK WIRING`（第 13 道：`stopAllOf`/`followOf` 那 7 个站点接线）· `UI ICON`（第 14 道：纹理路径逐个核到磁盘 + 类别图标不许撞图）· `CHAN RETRY WIRING`（第 15 道：`tbChanRetry()` ≥3 处接线 + 手动重试入口）· `EXAMPLES TOC`（磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序 + 数据不许搬回生产文件）· `README TABLE`（第 16 道：3 个 README 的版本行必须全在「更新日志」表里、恰好 10 行；CHANGELOG 保留完整历史 —— 守「发版脚本把版本行插错表」这类**不报错只是位置不对**的事故）· `MILESTONE`（第 17 道：3 个 README 都有 🏁 板块 + **里程碑在更新日志之上** + 标题范围末端 == 当前 VERSION + **板块正文 1..10 行**（10 个点、一条一行）+ **每条都是 `- ` 列表项**—— 守「顺序反了 / 里程碑又写成版本流水账 / 只更新了 CHANGELOG 忘了里程碑范围 / 排版被合并成一大段」）。
  ★判据：**行为断言照不到 UI 接线（漏接不报错、只是显示不对）→ 必须用源码检查补位**；两类检查互补，缺一就有盲区。
- **断言组 1~66+**：覆盖解析/引擎/UI/布局/语言/标注层；**新增功能请顺带加组**（写在 `test_assert.lua` 末尾 `print("ALL TESTS PASS")` 之前）。

### 2. ★★★任务/地图类问题 → 先读 UnrealQuest 对应流程代码（用户明确定，1.70.40）
- **用户原话**：「记住下次碰到任务地图相关的问题优先排查任务插件的对应流程代码」。
- **触发条件**：凡是涉及 **任务 / 地图 / 标注 / 世界地图 / 地图坐标 / 地图切换** 的问题——**第一个动作是去读 UnrealQuest 的对应流程代码**，不要先自己推断，也不要先往日志上加东西。
- **读哪里（按问题类型）**：

  | 问题 | 先读 |
  |---|---|
  | 定时/刷新不生效、生命周期 | `Core/Driver.lua`（**帧父级、OnUpdate 派发**——1.70.39 的坑就在这） |
  | 当前看的是哪张图 | `Map/MapContext.lua`（`GetViewedZone` / `Inspect`） |
  | 怎么画、什么时候重绘 | `Map/WorldMapPins.lua`（`ViewSignature` ~678、`Refresh` ~4449） |
  | 某个 API 在本客户端能不能用 | `Compatibility/ClientAPI.lua`（**实测配方库**，含大量「本客户端不支持 X」的明文） |
  | 图标素材路径 | `Map/NpcPins.lua`（CATEGORIES 表 + `IconForLocation`） |

- **怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库**信息密度最高**的内容。
- **停下信号**：当发现自己在「加日志 → 看日志 → 猜 → 再加日志」里转第二圈，**立刻停手去读对方代码**；**若读完仍未解决 → 转入下方铁律 4「取证协议」**。
- **两次代价（都是绕了远路）**：**1.70.17** 自己发明用 `IsShown` 判地图可见性，而对方 `ClientAPI.lua:8664` 早写明这 API 在本客户端**不可靠** → 引入回归；**1.70.39** tick 挂 `UIParent` 导致开图时 OnUpdate 停摆，而对方 `Driver.lua:467-482` 把机理和正确做法全写在注释里——用日志推断**五轮**没找到，**用户一句「可以查看任务插件…」当场破案**。

### 3. ★★★队伍/团队·血量/蓝量·buff/debuff 检测 → 先读 Heart（及它依赖的 C 库）（用户明确定，1.70.46）
- **用户原话**：「涉及到团队/队伍信息获取，血量，蓝量，buff/debuff 等检测 参考 `D:\game\TurtleWoW\Interface\AddOns\Heart` 插件的实现机制」。
- **触发条件**：凡涉及 **队伍/团队（party/raid）成员枚举 · 单位解析（名字 ↔ unit id）· 血量/蓝量/资源与百分比 · buff/debuff 检测（有没有 / 层数 / tooltip 文本 / 已持续时长）**，或遇到「**客户端根本没给这个 API**」——第一个动作是去读 Heart 与 C 的对应实现，不要自己从零推。
- ★**本机就是游戏主机**（用户 1.70.46 明确）：**EmberVeil**（`G:\...\Emberveil\live\Azeroth`）与 **TurtleWoW**（`D:\game\TurtleWoW`）都在本机，**可直接读对方源码、也可直接进游戏实测**——不存在「另一台机器」，不要再拿远端当借口。
- **读哪里（按问题定位）**：

  | 问题 | 先读 |
  |---|---|
  | 名字 → unit id（从聊天/战斗文字里的人名反查单位） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 「慢查」遍历 `raid1..N`/`raidpetN`、`party1..N`/`partypetN`、`player`/`pet`、`target`/`targettarget`/`mouseover`） |
  | `target`/`mouseover` → 具体队伍成员 | `C\C_AKA.lua`（用 `UnitIsUnit` 逐个比对，返回 `raid3`/`party1` 之类；便于把当前目标当成员查数据） |
  | buff/debuff 全量采集的数据结构 | `C\C_SetPlayerData.lua`（**16 buff + 16 debuff 槽**扫描 → `C_player_data[名字].Buff[纹理] = {Name,Type,Text,Count,Tick,Time}`） |
  | 采集驱动 + 多插件共用时的仲裁 | `C\C_UpdatePlayerData.lua`（遍历 raid/party/target/targettarget/mouseover/pet；★**同一轮更新只允许一个调用者**） |
  | 「某单位有没有某 buff/debuff」 | `C\C_UnitGotBuff.lua` / `C\C_UnitGotDebuff.lua`（按**名字**查 `C_buff_texture_map` → 纹理 → **要求 `Tick == CurrentTick`** 才算「有」，且返回**数据条目**而非布尔） |
  | **用 tooltip 读客户端没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData` / `C_GetDebuffData` / `C_GetSpellData` |
  | 队伍/团队主逻辑、血量优先级与治疗决策 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`UnitHealth`/`UnitHealthMax`/`UnitMana`/`UnitPowerType`；`hpDeficit = UnitHealthMax - UnitHealth`、`priority * (healvalue / UnitHealthMax)` 的权重算法） |
  | 事件与跨插件通信 | `Heart\Heart_event.lua`（`RegisterEvent` / `SendAddonMessage`）、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua`（**钩各种单位框插件**） |
  | 图腾 / 需要 tooltip 扫描的跟踪 | `Heart\Heart_Totem.lua`（31 处 tooltip 调用） |

- **★必抄的五个机制（「实现机制」的干货）**：
  1. **隐形 tooltip 当 API 用**（`C.xml`）：`<GameTooltip name="C_Tooltip" hidden="true" inherits="GameTooltipTemplate">` + `PLAYER_LOGIN` 时 `SetOwner(UIParent,"ANCHOR_NONE")`（1.10 hack）与 `SetClampedToScreen(0)`（1.11 hack）。读取时**先清要用的行再 Set**（`C_TooltipTextLeft1:SetText()` 无参 = 清空），再 `C_Tooltip:SetUnitBuff(unit, slot)` / `SetUnitDebuff` / `SetSpell` / `SetAction`，然后 `GetText()` 取行——**buff 的名称/类型、第二行文本（常含剩余时长）、法术的耗蓝/射程/施法时间都从这里来**。
  2. **Tick 新鲜度**：每轮刷新把 `CurrentTick + 1`；查询侧要求 `entry.Tick == CurrentTick` 才算「现在有」——**从结构上杜绝把上一轮/过期数据当成现行状态**（比「加时间戳自己判过期」更简单可靠）。
  3. **贵调用只在「新出现」时做**：tooltip 调用很贵 → 只有**首次见到**该 buff 才去读；已知且**层数未变**时只刷新 Tick 并累加 `Time`，不做 tooltip；扫描时 **buff 与 debuff 槽都空就提前 return**（正合「频率防护总则」）。
  4. **名字 ↔ unit 解析与宠物命名约定**：宠物一律 `主人名-宠物名`；反查先走缓存再「慢查」，**缓存命中也要用 `UnitExists` + 名字复核**（unit id 会变）。
  5. **共用更新函数的单调用者仲裁**：`C_UpdatePlayerData` 用 `C_last_update_player_data_caller == this:GetName()` 判断，**别人正在这一轮更新就直接 return**，并用 `GetTime()` 统计本次耗时——多插件共用一份数据时的去重与自测。
- **⚠️ 重要边界（别抄错东西）**：Heart/C 是 **TurtleWoW** 客户端插件，本项目跑在 **EmberVeil**；本机的 `C\C.lua` **已被用户改写**成「治疗施法监控（CastingSpeed）」并依赖 **SuperWoW** 扩展（`SUPERWOW_STRING`、`UNIT_CASTEVENT`、`UnitExists(unit)` 第二返回值 = GUID）。→ **参考它的机制与范式，但每个 API 在 EmberVeil 上是否可用必须实测**（本项目另有「EmberVeil 无 SuperWoW / 无 UnitCastingInfo」的记录，别因为 Heart 能用就假定我们也能用）。

### 4. ★★★同一个问题**两三轮没解决** → 立刻转「操作日志 + 测试流程」，让用户配合取证（用户明确定，1.70.46）
- **用户原话**：「碰到两三轮提问都无法解决的，尽快用记录操作日志的方式 + 提供测试流程。我会配合你完成问题排查。」
- **触发条件（硬性计数，不许糊弄）**：**同一个现象**已经来回「改一版 → 让用户再试 → 还是不对」**第 2 轮结束时就要准备取证，第 3 轮必须转取证模式**。继续凭猜测改代码 = 浪费时间且可能引入新回归（本项目已有两次代价）。
- **转入取证模式 = 一次交付这三样（缺一不可）**：
  1. **操作日志（插桩点选在分叉处）**：记录「输入是什么 → 判据取值是什么 → 走了哪个分支 → 结果是什么」。★核心要求：日志必须能**区分「代码没跑」和「条件没满足」**（1.70.16 教训：心跳日志被写在 `if not 开关 then return end` **之后**，整条链路静默，白猜三轮）。用 `dsLogAlways` 这类**不受 trace 开关门控**的通道记用户点击与异常路径。
  2. **测试流程（编号、可照抄、含期望现象）**：从**干净状态**开始（`/reload` 或重进游戏），一步一件事，每步写「做什么 → 期望看到什么」；需要多场景就分开列（场景A 首次打开 / 场景B 切换 / 场景C 关闭再开）。★**异常时也要让用户把剩下的步骤走完**（出错那一刻之后的行为同样是证据）。
  3. **回传物说明**：日志怎么拿（`/eh logdump` 打聊天框，或直接读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）+ **提醒本客户端日志只在 `/reload`/退出时落盘**，所以要先 `/reload`；再加现象描述/截图更佳。
- ★**能做成命令就别让用户手工复现**：给「一键探针」而不是「请你试十遍」——本项目已有范式：`/eh ds rnd`（随机点探针、如实统计成败）、`/eh ds hud`（把状态画在屏幕上）、`/eh ds trace`、`/eh go probe`。**把取证做成命令，是效率最高的协作方式**（1.70.35~38 正是靠它一行定案）。
- **取证模式的纪律**：**一次只验一个假设**（同时改多处 → 分不清是谁生效）；**不要只丢一句「把日志发我」**（必须带完整测试流程，否则用户不知道要复现什么）；拿到日志先**对齐时间轴**（日志行自带相对时间戳 `"%.3f 消息"`，按时间戳重排看事件先后——1.70.31 正是重排后一眼看出 `map=nil`）；日志里出现**两句自相矛盾**的话（如「层已关且无覆盖层」与「覆盖=草刺野猪」）→ 立刻怀疑**同一变量的两个绑定**（1.70.44 的定案方式）。
  ★**用户配合是已知条件**：本机就是游戏主机，可直接 `/reload` 实测，**不要吝啬开口要日志**，也不要因为怕麻烦用户而继续盲改。

## 二、频率防护总则（高频 API 调用场景）

- **原则**：凡是可能**高频触发**的 API 调用流程，设计阶段就必须考虑频率防护——**不要等被踢线/刷屏/翻倍后再补**。
- **判定方法**：设想最坏情况「一帧/一秒内会被触发多少次」；服务器写动作超过 **~1-2 次/s** 的一律限频，客户端事件**先假设会连发**。
- **三类范式（已有实现直接复用）**：
  1. **服务器写动作 → 限频队列**：`tbQ` + OnUpdate 滴出 `TB_RATE=0.3s`（1.68.2：一帧 24 次 `UseContainerItem` 被服务器反滥用踢线；1.69.0 交接 API/任务通知同入队）。配套：逐笔验证状态机 `tbPending`（槽位物品消失=成功 / 超时 2s=失败）、执行前二次校验防槽位变动、`MERCHANT_HIDE` 清待办防「卖变用」。
  2. **事件驱动 → 去抖窗口/节流**：`MERCHANT_SHOW` 本客户端连发两次（1.68.1 加 1.5s 去重窗 `tbMerchantLast`）；`BAG_UPDATE` 0.5s 节流（1.68.0）。教训：事件驱动功能上线后**一律假设事件连发**，高频事件必去抖。
  3. **执行入口 → 去抖窗口**：`EVAL_GO` 入口 0.2s 窗口（1.54.1：`/run` 宏走 RunScript pending 队列，连按堆积、松手后陈旧调用冲刷 = 目标狂切）；窗口可配 `cfg.goDebounce` 0~1.0（1.54.2），附 `EVAL_GO_TRACE` 追踪器取证。
- **Protected 函数**（`SendChatMessage`/`SpellStopCasting` 等）绕行 = `RunScript` 聊天脚本（pending script 队列）——注意 **RunScript 本身也是队列**，连发聊天同样会被反滥用踢线，通知类输出也要入限频队列。

## 三、本客户端已实测的 UI 配方（UnrealQuest ClientAPI.lua 验证）

1. **拖动柄必须用 Button**（Frame 的 `OnDragStart` 不触发）；`SetFrameLevel(父+10)` 抬高（**用 strata 抬高是记录在案的失败做法**）；`EnableMouse` + `RegisterForClicks("LeftButtonUp")` + `RegisterForDrag("LeftButton")`；`StartMoving` 前 warm-up 两步（StartMoving→StopMovingOrSizing→StartMoving）。
2. **strata 层级陷阱**：配置窗是 DIALOG；其上方弹窗（技能编辑窗/导入导出窗）**必须同 DIALOG + `SetFrameLevel(90~100)`**，MEDIUM/HIGH 都会被 DIALOG 盖住（1.11.2 实测修复）；弹窗也要 `uiOffscreen` 越界回归。
3. **纯色纹理**只有 `Interface\Buttons\WHITE8X8` + `SetVertexColor` 可靠。
4. **无原生 Slider / 无下拉控件**：滑条 = 自制轨道 + 拇指；**下拉一律用全局件 `EVAL_DD_OPEN(锚点,选项表,回调)`**（1.19.0 由 SE 专用泛化；UIParent+DIALOG+level250，多列 12 行/列，贴屏底自动上翻；宿主窗口 `OnHide` 里调 `EVAL_DD_HIDE()`）；1.19.0 起插件内所有 `[<][>]` 循环器已全部改下拉。
5. **可见性契约**：显隐走**显式控件清单** Show/Hide，不靠父子传播（容器 `EnableMouse(false)`，交互件单独 `EnableMouse(true)`）。
6. **位置记忆**：`GetCenter`/`GetLeft` **含缩放**，存取要除 `GetEffectiveScale`；每个记忆位置的窗口都要 `uiOffscreen` 越界回归。
7. **禁用 `SetScale`**（点击框漂移），缩放 = 按 z 系数**几何重建**；字体链 `FZLBJW→FRIZQT→ARIALN` 全程 `pcall`。
8. **小地图按钮父级必须是 `UIParent`**（不能是 Minimap）；悬停用 `OnEnter`/`OnLeave` + GameTooltip，**不用 `SetHighlightTexture`**。


## 四、架构要点 + 编辑工具注意事项 + 当前功能地图

### 4.1 架构要点（改代码前先读这段）
- **状态表 `st`（`EVAL_HELP_STATE`）**：所有判定数据走 `UPDATE_STATE()` **一次刷新、各处只读**（Cat 思路，不重复调 API）；含 `playerBuffs`/`targetDebuffs` 纹理集合、`castLog` 释放日志（最近 5 条带条件 trace）。
- **规则引擎**：规则 = `{ skill, enabled, groups }`；`groups` = 组内 `&`、组间 `|`；`EVAL_RULE_RUN` 顺序执行第一条全过的；兼容旧 `when={}` 格式；`condOne`/`groupsOK`/`EVAL_PARSE_CONDS`/`EVAL_COND_STR`/`EVAL_GROUP_STR` 是核心。
- **方案数据**：`cfg.war.profiles` + `activeProfile`；`EVAL_WAR_ENSURE_PROFILES` 做缺省迁移；SavedVariables 自动持久化。
- **方案切换**：配置窗侧栏按钮 / 激活方案 `[<][>]` 选择器 / 战斗信息UI 方案行 / **Shift+按宏**（★Shift 已被切换占用，**方案条件里别用 Shift**，用 Alt/Ctrl）。
- **文本格式**（导入导出 / `zs_wq.md`）：`# 方案: 名` + `- 技能 | 条件` 行；技能名前 `!` = 停用；解析容忍 md 杂物行。
- **函数作用域陷阱**：`warCfg`/`c()` 是配置段 local，战斗信息UI 段在其之前 → UI 段用 `uiWarCfg()`（直接走 `EVAL_HELP_CONFIG` 全局）；`wslots`/`WAR_SKILLS` 是战士段 local，配置段在其后可用。
- 受保护函数（`CastSpellByName` 等）插件**不能调**，施法一律 `UseAction(slot)` + `pcall`；谓词返回 `true/false/nil`，**绝不 `==1`**。
- **`EVAL_GO` 目标门槛教训（1.21.7）**：规则引擎化后**不能有**「无可攻击目标就 return」的全局前置——是否需目标交给**每条规则的条件**；否则纯自身 buff 方案（如只有战斗怒吼）永远执行不到。
- 本客户端**无 `UnitCastingInfo`**（打断条件做不了）、**无 SuperWoW**（无精确距离数值/挥击计时）。
- **射程检测已有官方 API**（排查 emberveil.org/wiki/lua 确认）：`IsActionInRange(slot)` 已实现——`true`=在射程内 / `0`=超出射程 / `1`=自动攻击(不测距) / `nil`=无目标或技能解析失败；`ActionHasRange(slot)` 返回技能是否有射程；`CheckInteractDistance(unit,idx)` 已实现但客户端不分档码数（`idx<4` 统一交互距离，4 恒 false）——可做规则引擎「在射程内」条件，技能本来就在动作条上直接传 slot。
- **物品 API**（wiki 已确认签名，游戏内实测待做）：`UseContainerItem(bag,slot)` 消耗品直接用/装备自动穿（BoE 未绑弹确认）；`GetContainerItemInfo`→texture,count,locked,quality,readable；`GetContainerItemLink`→`|Hitem..|h[名称]|h`；`GetContainerItemCooldown`→start,duration,enable；`GetItemInfo` 第 9 返回值 = 纹理（只读本地缓存）。**无 `EquipItemByName`/`UseItemByName`**。★本客户端插件保护清单未文档化，`UseContainerItem` 是否被禁需实测——若被禁会**静默失败**（`pcall` 兜住不炸）。
- **`seBtn` 返回包裹表 `{btn,bg,text}` 不是按钮本体**：锚下拉/加 FontString 必须用 `.btn`（`mkSmall` 相反：直接返回 `b,bt`）——1.21.4 修复 SE 技能名按钮把包裹表当按钮用（`uiText` 炸 CreateFontString、SE_BUILD 半成品窗口）。
- **Lua local 作用域从声明语句【之后】开始**：RHS 里的闭包**捕获不到正在声明的 local 自己** → `local b = mk(..., function() ...引用b... end)` 的 `b` 是**全局 nil**！OnClick 要等赋值完再单独 `SetScript` 挂——1.21.4 修复激活方案下拉（`DD_OPEN` anchorBtn nil）。
- **EditBox 疑似不渲染**（1.15.1 用户报告 IO 窗口空白：`pcall` 全「成功」但什么都不可见）→ IO 窗加 FontString 保底预览区（`EVAL_HELP_IO_REFRESH`）；EditBox 字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`；**文本类 UI 一律给 FontString 保底**；单行输入弹窗用**回声行**保底（`OnTextChanged` 镜像到 FontString，1.17.0 重命名弹窗 `EVAL_HELP_RP_*` 范式）。

### 4.2 编辑工具注意事项
- `run_code` 里**没有 `require`**；node 脚本一律写工作区 `.js` 文件再 `pwsh node xx.js`（内联 `-e` 引号会炸）；`pwsh` 要加 `2>&1 | Out-String` 否则 stderr 丢失。
- `edit` 工具：本会话内须先 `read` 过该文件；`old_string` 要精确（注意缩进空格数；批量失败先 `grep` 核对实际状态再重试）；**node 外部改过文件后必须重新 read 才能 edit**。
- 大块插入用「写块文件 + node 边界替换脚本」，小改动用 `edit` 工具逐处替换。
- 写文件若报 `file no longer exists`：换文件名重建（fs-observation 缓存）。
- DSH 策略 danger-full-access、审批关闭 → **可直接写游戏 AddOns 目录**。
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（★**文件名是 `EvalHelp.lua` 不是 `EVAL_HELP.lua`**，1.29.0 改名后旧文件 `EVAL_HELP.lua` 是历史残留；小退/reload 时客户端写入）——**这也是现在读调试日志的地方**。

### 4.3 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行 + 方案技能行 + 条件 tooltip + 实时条件亮金）| `/eh st` 状态信息UI（状态变量 + 最近释放条件明细）。
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**五个 Tab**：① 全局（日志/界面/帮助）② 一键宏设置（方案栏 + 技能列表 + `[添加技能]` + `[导入导出]`；1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**）③ 工具箱（`Toolbox.lua`，1.68.0）④ 数据检索（`DataSearch.lua`）⑤ **图标库**（`IconBrowser.lua`，1.71.3；★1.71.3 起是**第 5 个** Tab —— 旧记录写「四个 Tab」是过期信息）。
- 技能编辑窗：点 `[编]` 或技能图标打开，条件逐行独立配置（类型/参数/删/添加），关系列切 `&`/`|`；条件类型分 5 组（`CTG_5` = **队友/团员状态**：队友血量%/队友蓝量%/队友debuff/队友缺buff + 团员同名四型）。
- **队友/团员怎么用（1.70.47）**——两种用法都能独立工作：① **只配条件**（最省事）：技能行加 `队友血量% <60` → 条件自己**扫描全队取血最低者**、切目标、记 `st.allyUnit`，技能就打在他身上；解魔法同理。② **要自定义筛选**：加一行行为 `选取目标:队伍成员`（或 `团队成员`），把筛选条件写在这**一行**上（`目标血量<N%` / `目标buff:名` / `目标debuff:名`）→ 按血量升序逐候选判定，选第一个全过的。**规则按顺序全部执行**，所以「选取器 → 治疗 → 驱散」在一次按键里依次生效。
- **定位：通用职业一键宏框架**（1.18.0 起全部用户可见描述已去「战士」化；技能白名单仅作下拉置顶，1.24.0 起重扫记录全部上条技能，任意技能可入方案/条件）；一键宏 `/run EVAL_GO()`；方案函数式调用 `/run EVAL_GO(2)` 或 `EVAL_GO1~4()`（执行指定方案并且激活，绑多按键）；技能需拖上动作条，改动后 `/eh go rescan`；`/eh war` 是旧命令别名（1.21.1 起改名 `/eh go`，handler 里仍兼容）。
- 调试：`/eh debug`（跳过原因 + 触发 trace）| `/eh go list` | `/eh logdump` 调试日志 | `/eh ds`、`/eh ds trace` 数据检索诊断。
- **命令组 1.21.1 改名 `/eh war` → `/eh go`**（handler 入口 `string.gsub(msg,"^war","go")` 兼容旧命令；sub 偏移量随 war→go 长度差 -1 已同步）。

## 五、关键判据汇总（按主题；来自最近 ≤20 个版本）


### 5.1 Lua / 解析
- ★★★**多字节字符绝不能进 Lua 的 `[...]` 字符集**（按字节匹配）；`|` 也不是交替。`[:：]` 只吃掉「：」首字节 → 名字前多两个乱码字节 → **选取目标/物品/宠物/姿态/条件解析全线静默失效**。修法：`colonNorm()` 在**解析入口**归一；正解是 `(.+)` 抓下来再 `==` 比。
- ★★★**Lua 模式里 `%` 自己是转义符**：`%.`=字面点、`%%`=字面百分号（把 `%.` 写成 `%%` → 那条分支**永远是死的**）；`string.find(s,"%%",1,true)` 在 plain 模式找的是两个字面字符 → 永远找不到（要找 `%` 写 `"%"`）。**plain 参数与模式转义是两回事。**
- ★★★**方括号组必须成对解析**（`(.-)` 会吞掉 `[职业:术士][队伍:2]`）→ 内容用 `[^%]]-`、半角/全角分别匹配；**解析出空集 ≠ 没写**（写了不存在的职业名就不建集合，否则导出 `[职业:]`）。
- ★★★**主 chunk 最多 200 个局部队变量**，且 `do ... end` **不新开函数作用域** → 大段断言要收进 `local function`；**`ipairs` 遇 nil 立即停止**（表首 nil → 循环体一次都不执行）→ 可能含 nil 的表不用 ipairs。
- ★★**空字符串在 Lua 里是真值**（`GetQuestLogTitle` 给 `""`）→「键存在」与「有内容」是两件事（入库层与播报层各挡一道）；`string.len` 是**字节数** → 宽度按字符数估（`FontString:GetStringWidth()`，退化「字节数/3」）。

### 5.2 静默失败族（数据 / 序列化 / 开关）
- ★★★**「查不到」与「没有」是两件事**：查不到必须**如实报错**（`texOf` 回 nil 退化成查空串 → `cnt=0` → 「否/无」成立 → **规则无限重放刷屏**）。
- ★★★**静默丢弃 = 那一行变成无条件施法** → 文本里写了几条成员条件、解析后就必须有几条；**数据类错误全是静默的**（类型写错一个字就谁都不解/打错人，不报错）→ 模版与配置必须配体检断言。
- ★★★**导出侧写的形态与解析侧认的形态必须成对验**（`施法中:` / `施法中:nil` 都读不回 = **导入即丢条件**）；**「有过滤」≠「过滤得住」**（`itemOf(n)` 只认带前缀的「物品:名」，动作条物品经 `wactionName` 是裸名 → 漏网）。
- ★★★**两个日志开关不能合并**（`cfg.log.on`=数据层总闸门、`cfg.wdebug`=输出层「说不说」）；**命名也是功能**（「调试日志」vs「记录调试日志」→ 改「方案技能日志」）；★静默 = 只进日志、一个字都不上屏，**绝不走 `EVAL_SAY`**。
- ★★**判据表要照客户端真实文案抄**（真实文案是「**进入**频道。」，旧表只有「加入」→ 那一半功能根本没生效）；**「尝试过」≠「挂上了」**（载入即挂必须**失败重试**：`Toolbox.lua` 载入那刻 `DEFAULT_CHAT_FRAME` 还没建好）。
- ★★**Lua 的 function 不是 table** → 不能 `wrapper.__flag = true`（身份判定只能 `cur == TB.chanWrapper`）；**标记只加在显示串上**（动作条物品 `[物]` 只改显示、取值仍裸名）→ ① 扫描真打标 ② 显示带标**且取值不带**；**「还原/撤回」不是回退到有 bug 的状态**；**跨玩家功能的提示要写出「对方那一侧的前提」**（`shOnMsg` 的 `if not shCfg().recv then return end` = 静默忽略 → 必须点名「接收方案」开关）。

### 5.3 测试与断言
- ★★★**桩必须记住被测代码读的每一个状态**（焦点/纹理/位置与层/锚点语义/tooltip 行/切目标 `TEST.targetUnit`）；★**「桩有错状态」比「桩没状态」更隐蔽**（`newMock()` 漏写 `local x,y` → 所有对象**共享最后一次写入的位置**）。
- ★★★**桩对「无效调用」必须如实表现为无效**：`SpellStopCasting` 直调只置 `castStoppedDirect`、**只有 RunScript 排队才置 `castStopped`**，并断言「直调通道没被走到」——否则分辨不出直调/排队，核心修复**永远测不出来**。
- ★★★**「没执行」证明不了「没入队」** → 直接问队列（`EVAL_TB_TEST_QUEUED_QUESTS()`）；**断言里写死布局常量 = 测的是测试自己**（`swY=-389` 在生产改回 `-349` 时照样绿）→ 读生产导出的真值（`EVAL_TEST_CFG_LAYOUT()`）。
- ★★★**真实数据测不出换行/分列**（按钮串刚好放得下 → 删掉换行判断照样绿）→ 用**合成数据**入口（`EVAL_TEST_TPL_PLAN_FAKE`）把分支逼出来。
- ★★★**冗余防护的变异必须整组拆**（只拆一道、另一道仍会挡住 → 两处单拆都 SURVIVED，会把有效断言误判成无效）。
- ★★★**变异锚点必须唯一定位到目标那一行**（`b:SetScript("OnClick",fn)` 有 6~7 处、`OnEnter` 6 处）→ **整行对齐**、**命中数必须 == 1**、CRLF 先摘 CR、**变异体本身必须语法合法**；★报 ANCHOR-MISS 时**先怀疑锚点**。
- ★★★**判「捕获」要同时看退出码与输出文本**（`: FAIL` 只覆盖源码检查，行为断言打 `ASSERT FAIL`；`execSync` 抛异常时正文在 **`e.stdout`**；`-Last 6` 会漏掉打在 **stderr** 上的 `LANG KEY CHECK` FAIL）。
- ★★**断言必须落在真实调用点/真实闭包/真实入口上**；**观测点必须配反向哨兵**、「删掉了」验「不在」、**写了钩子没人调用等于没有**；**模块级状态必须纳入 `EVAL_TB_TEST_RESET_TIMERS`**（放**文件末尾**，否则 DECL ORDER CHECK 抓 4 条 FAIL）；**判据要盯要保的那条性质本身**（「刷新次数 +1」而不是「数据对不对」）；**等价变异如实记录、未覆盖就说未覆盖**。

### 5.4 UI 与布局
- ★★★**「隐藏」= 不画，不是 `Hide()`**：EditBox 用 `Hide()` 后文字/底条**仍会被绘出**且层高于 `BACKGROUND` → 黑带；修法 = **不透明背板 + 控件挪出可视区**（`DD_SEARCH_PARK=-4000`；`alpha=0` 是混合）；判据随之改判「左边缘是否被挪走」。
- ★★★**锚点描述的是「邻居的哪条边」，不是「我想要哪个角」**：`mb.TOPRIGHT` 对 `Minimap.TOPLEFT` 看着像左上、实际贴左边缘，而小地图是**圆**的 → 要落圆外必须 `RIGHT` 对 `LEFT`。
- ★★★**分列切点 = 两列行数差最小**（遍历所有切点），**别用「塞到过半就停」的贪心**（25 条时 18/18，加 2 条就变 22/16）；**组是不拆的最小单位**；**版式抽成纯函数**（`tplFlowPlan`/`tplTwoColPlan`）= 位置的单一来源、渲染只读 plan；**组标题不许孤悬行尾**（要「标题+本组第一个按钮」一起放得下）、**每组从新行开始**。
- ★★★**绝不静默截断**：行池 `DD_MAX_ROWS=96`，超出时**末行如实显示**「…… 还有 N 项未显示」；分享详情 `SH_DETAIL_MAX=6` 同理（详情用**逐个 FontString 按行**）。
- ★★**「面板按 N 列排版」≠「实际画得出 N 列」**（行池硬编 48 而菜单需 54 → 最后 6 行**静默丢弃** + 第 5 列全空）；**分列/换行不变量（读真实控件几何）**：按钮在**本列**列宽内（不是「窗内」）/ 同行留足 GAP（**同 y 的两列各自成行**）/ **组不跨列** / 两列都有内容 / 行数差 ≤2 / 右列起点 = 左列右边界 + 列间距 / 标题在本列行首。
- ★★**布局算法要选「增删内容后仍成立」的那种**；**布局需求验性质不验数字**；**需求是「相对量」就验相对量**（「再往下移动 40 像素」→ `swY == 原值 - 40`）；**同一行一律中线对齐**（按钮 20 与勾选框 16 高度不同）；**中文宽度按字符数估**（4 项算成 772px > 660 的假失败）；**窗口宽度由最宽一行控件总宽反推**；**布局常量单一来源**（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。

### 5.5 API 与客户端事实
- ★★★**`SpellStopCasting()` 一个调用覆盖三类**（读条 / 自动射击 / 魔杖自动重复），且 **【Protected: yes】** → 必须走 **RunScript 排队**（**直调在真机静默无效**）。★**「进度条没了」≠「读条被取消」**（只清本地 UI）→ 定案「**功能保留、真中断做不到**」（客户端修好则无需改码）；试过的「移动脉冲」实测同样无效、**代码已删但桩留着当反向哨兵**。
- ★★★**「Toggles / 切换」类 API 一律要「当前状态守卫」**：`AttackTarget()` = **Toggles** auto-attack → 必须先 `IsCurrentAction(攻击格)` 确认在挥击，否则会把没在打的人打起来；判不出来就**不碰** + 日志**如实声明**「普攻未判定」。
- ★★★**Movement 只有 `FollowByName` / `FollowUnit` 不是 Protected**（`MoveForwardStart/Stop`、`TurnLeftStart` 全是）——**回顾性解释了「移动脉冲」为什么无效**。`FollowByName`：空名=跟当前目标、只搜**已知**玩家、找不到由**客户端自己报错**、**无返回值**、**直调不走 RunScript**；两条硬规则本地先挡（不能跟随自己 / 没名字且没目标）。
- ★★★**`GetRaidRosterInfo(i)` 九个返回值**（name/rank/**subgroup 1–8**/level/classLoc/**classFile**/zone/online/isDead），**非团队或越界只回一个 nil** → 小队号拿得到（可行性=可行）；队伍成员没有小队号概念 → 恒记 1；职业取 `UnitClass` 第二返回；一次调用两用省 40 次 `UnitClass`。
- ★★★**1370 个 API 里没有任何 aura 专用函数**；`GetPlayerBuff(i,f)` 的 i 是**增益条 0 基下标**且跳过 hidden/tracking → 它与 `UnitBuff` **都只枚举「上了增益条的光环」**；「光环是否特殊」在 API 层**没有区别** → 别把文档的「可能」当成「就是」。
- ★★★**没有文件读取 API**（沙箱无 `io`/`os`）→ 「从文件载入」唯一形式 = **把文件列进 .toc**。
- ★★★**`GetQuestReward` 会再触发 `QUEST_COMPLETE`**（自触发循环）→ 三层防护缺一不可（同名去重 / 领取窗口闸门 / 全局频率上限），**兜底层不许依赖任务名**，闸门必须拦在**播报之前**；「已入队」的交接也要能撤（`tbQPump` 按拍丢弃 `kind=="quest"` 并如实 say）。
- ★★★**`UnitDebuff` 第 3 返回 = dispel token**（Magic/Curse/…）→「解魔法/解诅咒」下拉**不需要自建名字表**；★中文客户端实际取值域仍以实测为准（`dispelMatch` 三级兜底、入库存英文 id）。
- ★★★**`UnitMana` 是「主能量」且有显示缩放**（怒气 ÷10、幸福 ÷1000）→「蓝量」条件**必须先判 `UnitPowerType(unit)==0`**；血量/蓝量对队伍/团队成员有效、**超距离走 roster 数据**。
- ★★★**施法 API 全是 Protected**（`CastSpellByName`（且只有 onSelf）/ `CastSpell` / `SpellTargetUnit` / `SpellStopTargeting` / `SpellStopCasting`）→ **插件无法直接把法术打给队友**；`TargetUnit` **非 Protected** → **唯一路径 = 切目标 → `UseAction(slot)` → 还原原目标**（`UseAction` 第 3 参 onSelf = 对自己）；`Targetting` 分类另有 `TargetLastTarget`/`ClearTarget`/`TargetByName`/`TargetNearestPartyMember` 等。
- ★★**1.12 系队长/团长聊天走独立事件**（`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER`）→ 只注册 `CHAT_MSG_PARTY/RAID` 的接收端**永远收不到**（且失败静默）→ 分享发送侧只留 公会/队伍/说、接收侧注册保持原样；**来源判据 = 触发的事件名**、**认不出来就不标**、三态分派抽 `EVAL_SHARE_DISPATCH`。
- ★★**本机 `api_*.html` 只有函数索引（1370 条）、没有事件列表** → 事件类问题只能两套都注册或 `/eh go probe` 取证；宏图标表 `GetNumMacroIcons`/`GetMacroIconInfo` 给的是**路径**、整套打包在 `Content\Paks`（磁盘取不到）、**纹理不用写进 .toc**；★**纹理路径写错时什么都不画**（不报错不崩只是空白）→ 路径必须解析到磁盘核对。

### 5.6 内容 / 数据质量
- ★★★**模版四条体检**：名字非空 / 同组不重名 / 首行 `# 方案: X` **等于**模版名 / 至少 1 条技能行；并点名检查用户要的那几条在。
- ★★★**「职业过滤」必须同时支持候选者条件**（解析白名单 + 导出 `teamFilterSuffix` + 编辑器格**三处一起**放开）→ **新能力要沿「数据能到的地方」全打通**（解析/导出/UI/求值）；**过滤作用点分两处**：单条条件按**它自己的** `cs`/`gs` 收窄（`teamFilterList(list, cd)`）、**选取器行**按行内条件的**并集**收窄候选（`teamFilterList(list, nil, rule)`）——这才是「挑一个法师」。
- ★★★**「成员过滤」空集 = 不过滤**（不选 = 全部），与**「目标职业」空 = 永不满足**正好相反 → 不共用判据也不共用文案；**成员类条件必须写在一行的最前面**（它负责**扫人 + 切目标**；写在后面 = 后面的条件拿「切之前的目标」求值，静默出错）。
- ★★★**拆数据文件 = 一处真值变两处同步**（磁盘 + .toc），漏任一处都**静默**；`EXAMPLES TOC CHECK` 四条（双向一致 missing/ghost、toc 顺序=选单顺序、数据不许搬回生产文件、examples 排在 `EvalHelp.lua` 之后）；★**新增被装载的数据文件时，装载表本身就是测试的一部分**（1.71.4 漏加 5 个文件 → 新模版一条没被测，`getn(EVAL_IO_TEMPLATES)==6` 照样绿）。
- ★★★**改名只改显示名、id 一律不动**（存量方案/导出/解析不受影响）；显示名真源是语言包 `CT_<UPPER(id)>`，`SE_TYPES[i].name` 只是副本 → **两处都改、三语言同改**。
- ★★**文本往返走单一通道**（`EVAL_PARSE_ONE` 剥 / `teamFilterSuffix` 写）；**空集不写** → 老配置导出**逐字不变**；非队伍/团员类型带后缀 = 写法错误 → **如实丢弃**。
- ★★**菜单标签是运行时拼键** → 静态 `LANG KEY CHECK` 扫不到 → 必须配「**逐语言**菜单无重名/无缺键」断言（只跑一种语言时另一种永远是盲区）；★改名时顺手核三语言白捡一个真 bug（enUS/ruRU 两条原本同串）；`tips`/图标表必须用**下标赋值**填充（`table.insert(t,nil)` 是 **no-op**）。
- ★★**光环纹理优先级**：动作条图标只是**代理**，增益条上亲自观察到的才是**权威** → 学习表优先；**「图标对不上」≠「身上没有」** → 图标没命中时按名字再确认（`auraNameHit`）；**频率防护三层**（只在没命中时才做 / 0.5s 缓存 / `learnAuraTex` 自愈回快路径）。

### 5.7 流程与纪律
- ★★★**「审计 / 排查」必须落成可执行的闸门**（断言 / 源码检查），否则只是这一次的手工动作，下次照样被改回去。
- ★★★**「数据变了」与「界面更新」是同一件事，必须在同一个地方做**：刷新放**写入点**（`ioImportText`）而不是散落各调用点（`Share.lua` 分享弹窗漏调 `EVAL_WAR_TAB_REFRESH` → 数据进了 profiles、列表还是旧的）。
- ★★★**改需求时必须回头删掉描述旧状态的记录**（与代码相反的注释/赋值**比没有更危险**）；★注释里的「为什么」**也会过期**；**动手前先查「它是不是已经存在」**（要「新增」的 `k=casting` 本来就是「自身施法中」）→ 否则造出两条同名条目。
- ★★**先核实「那次调用 / 那个按钮是不是必需、是不是真重复」再删**（判据 = 落到**同一个写入点**才算重复）；**「组归属」是用户偏好不是技术结论**，需求一改必须钉**新**归属与**新**顺序（**顺序本身也是需求**）。
- ★★**只有 `quiet=true` 且带 `why` 的调用点写日志**；看门狗式（可能每帧触发）**不写**，否则 300 行环形缓冲被刷满；日志 = 头部「原因 + 技能总数」+ 逐条「技能名 → 格子号」；标签要能区分触发原因（open/menu/auto），**不拿 quiet 兼职当原因**。
- ★★**抽纯函数以便脱离环境直测**（`EVAL_TB_HOLD_ACTIVE` / `tbMigrateQuest`+`EVAL_TEST_TB_MIGRATE` / `DD_MAKE_SEARCH`+`EVAL_DD_TEST_BUILD_SEARCH`）；**分享回声与来源**：判据用「**同名 且 序列化后逐字相同**」（只比名字会误伤同名方案）、**「说」这个例外必须留着**（用户自测分享的唯一方式）、★★★**「认不出来」不许吞**（宁可多弹一次，也不误吞别人的真分享）。
- ★★**接收端数据规则**：只有**同一发送者开新的一笔**才作废他旧的未收齐缓冲，**绝不跨发送者**（不同人同时发分片交错到达，跨发送者作废会让两边都收不齐——**并发要先推演消息到达顺序**）；四道上限（在途 4 笔 / 单笔 40 片 / 单笔解码 8192 字节 / 去重表 64 条）超限**整笔拒收 + 如实提示**；提示限频 5s ★★**限频的是「说不说」，不是「拦不拦」**；**弹窗详情要「先清空文本再 Hide」**（Hide 过仍可能被绘出），★**找残留要找「只可能来自旧文本」的标志物**。

### 5.8 队伍 / 团队·目标切换（1.70.46 文档核对，可行性已验证）
- ★★**唯一可行路径 = `TargetUnit(unit)`（非 Protected）切过去 → 技能行 `UseAction` → 还原原目标**；**条件命中即「记人 + 切目标」**（`st.allyUnit`）：单条 `队友血量<60` 就自足完成「找出该治的人 → 后续技能打在他身上」；★**只在非 dry 时切**（dry = 战斗信息UI 每 0.15s 的预览求值）；`EVAL_GO` **每次按键开头清空 `st.allyUnit`**。
- ★★**切目标只发生在有意义的方向**（血量/蓝量、debuff「有」、缺 buff）；debuff「无」/ buff「有」是**存在性判定 → 不切**；**选取器 = 扫描器 + 过滤器**：按**本行**的条件列表逐个候选过滤，**候选顺序 = 血量% 升序**；★**过滤要真的切过去再判定**；★**全员不满足要还原原目标**（`UnitIsUnit` 反查 unit id 精确还原优先；`TargetByName` 只认「附近」、会静默失败）。
- ★★**成员选取器要跳过常规条件预判**（`TARGET_SEL_TEAMSEL` 标记）——那条路径**不经过 `condOne`**，而 `condOne` 的 target 分支是**另一个调用点** → **两处都要测**。
- ★★**惰性扫描（频率防护）**：`UPDATE_STATE` 只丢缓存、**绝不扫描**（每 0.15s 被调）；真正扫描在 `EVAL_HELP_TEAM_ENSURE`，**按宏那一轮一次**、缓存复用（有 API 调用计数断言）；★**诚实失败**（不在队/团、成员无蓝、无人符合 → false + 原因，绝不退回自身血量）。

## 六、历史教训汇总（1.70.0 ~ 1.70.36，按主题；不再逐版本）

### A. Lua `local` 作用域（累计 13 次，头号杀手）
- **判据**：Lua 作用域是**词法**的——引用点在 `local` 声明之前，那个名字**永远**解析成全局，**与运行时调用顺序无关** → 「声明晚于引用」一定是真 bug。
- **防法**：`EVAL_DS_*`/`EVAL_TEST_*` 导出函数一律**物理定义在被引用的 local 之后**；互相引用的布局常量集中在函数**开头**；状态块整体上移到所有使用点之前；**DECL ORDER CHECK 自动扫（7 个文件）**。
- ★★★**合并冲突在 Lua 里不报错（1.71.1）**：两分支各自给**同一个全局**赋值 → 合并后两份定义，Lua 认为合法（**后赋值者静默获胜**）。实例：v1.71.0 给测试桩补的简版 `GetNumPartyMembers/GetNumRaidMembers` 盖掉了支持 `TEST.team/TEST.raid` 的富版 → **队伍扫描只扫到自己**（组 66 `got=1 want=3` 当场炸）。★luacheck / 语法检查 / 单文件审查**都看不出来**，只有**跑测试**能发现；`git diff` 里同一函数名出现两次要立刻当错误。
- **例外（不得不提前引用）**：用**前置声明** `local f`（**无 `=`**）放在使用点之前，实现处写 `function f(...)`（**不带 `local`**，否则是新建第二个绑定）。1.70.47 实战 `auraTexOf`。
- ★★**检查器自身的盲区（1.70.47 两次踩中）**：① 看不见「无 `=` 的前置声明」（旧正则只认 `local x = ...` 与 `local function x`）→ 按它的建议去修反而让名字**彻底脱离检查范围**；② CRLF 行尾的 CR 被 `(.+)$` 吃进名字 → 声明不可见。★**检查器必须覆盖「它自己推荐的那套写法」的所有变体**，且**要用变异证明它真的会响**（用「撤销前置声明」变异自测 → `DECL ORDER CHECK: FAIL - Engine.lua: auraTexOf used at 326 but declared at 505`）。**没被变异验证过的检查 = 没有**。
- ★★**仍存在的盲区**：DECL ORDER CHECK 按**名字**判定 → 「某名字在 A 函数里是 local、在 B 函数里被当全局用」它**看不见**（同名有函数内 local 就整条跳过）。1.70.47 的 `texOf` 正这样漏掉，且外层有 `pcall` → **不报红字、只表现为「选人结果不对」**，只有**执行真实路径的断言**才抓到。

### B. 静默失败族（不报错、pcall 全成功、行为却错）

### C. 断言与测试（「绿」不代表对）
- **桩太宽松**：Show/Hide 空操作、IsShown 恒 nil、CreateFrame 丢 parent、GetWidth/GetHeight 恒 nil、SetWidth/SetHeight 不记录 → 「行为级/父级/尺寸」断言全部失效。★**写断言前先确认桩有状态**。
- **只测解析函数、不测调用点**（第 4 次发作）：断言 `dsEntityColor(id)` 抓不到调用点现摇随机；断言判定函数抓不到 UI 分支里引用错名字。★**「A 产出配置、B 消费配置」两边都要断言**；能点就点**真实按钮**。
- **等价变异 / 变异体没落地**：结果相同的用例证明不了任何事；CRLF 上用 `\n` 锚点会静默替换失败（**变异后必须回读确认结构真的变了**）。

### D. 布局与 UI（本客户端实测）
- **同一行/栏混用「顶边对齐」与「中线对齐」必然错位**（字体链不同时行高会变）→ 要么全顶边要么全中线，**按中线更稳**；`中线 = 顶边 - 高度/2`（y 越往下越负）。
- **FontString 一律显式 `SetWidth`**，否则宽度由内容决定、换语言就溢出压到别的控件；**改布局要一起改「隐形跟随件」**（占位提示/聚焦热区/背景纹理的宽度常跟着某控件写死，grep 旧宽度值能找出来）。
- **`root:SetScript` 是单槽位**：多 Tab 共用根帧时先 `GetScript` 取旧处理器做**链式转发**，否则静默顶掉别人的滚轮。

### E. 兜底机制的设计纪律
- **前提被证伪的兜底必须删掉**（不能因为「留着无害」而保留——5s 全量重建、稳定期闸门都在空转还让人以为有保护）。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`；开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数、没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」）→ 匹配要剥掉「生物」再比。
- **无 CombatLog API、无免疫查询函数、无 UnitCastingInfo、无 SuperWoW**（精确距离/挥击计时做不了）。

### F3. 官方文档现场核对记录（1.70.47 逐条查 emberveil.org，2026-09）
- **Protected（文档明写 addons cannot call this）**：`CastSpellByName`、`SpellTargetUnit`、`SpellStopCasting`；★`TargetUnit`/`TargetByName`/`ClearTarget`/`UseAction`/`IsUsableAction`/`IsActionInRange` 条目里**都没有 Protected 标记**——这正是「切目标 → UseAction」这条唯一可行路径的依据。
- ★**`UnitIsUnit` 相同返回 `true`、不同返回 `nil`（文档原话 never false）** → 只能看真值，**不能写 `== true`**。
- ★**`GetNumPartyMembers()` 在团队里返回「团队人数 - 1」**（不是 0），而 **party 索引只有 `party1..party4` 且不含自己** → **不能拿它当 party 循环上界**（40 人团会去试 party1..party39；已夹到 4 并有调用计数断言守着）。**`GetNumRaidMembers()` = 团队人数含自己，非团队时 0** → raid 直接 `raid1..N`，不用再补 `player`。

### G. 任务/地图专题的关键事实
- tick 帧必须挂 **`WorldFrame`**；视图签名必须含 **areaId + mapFile + continent + zoneIndex**（只比 areaId 会让「关图再开同一张图」被判「未变」）。
- 采集点数据在 `meta.herbs/mines/chests/fish` 里是**负 ID**（负号 = 类型编码），查 objects 表要取反。
- 对方地图标注层**没有地图事件可用，全靠 `REFRESH_INTERVAL=0.25` 轮询**——不要自己发明事件层。

### H. Lua 5.1 / 本客户端语言坑
- `string.find(s, "^14|", 1, true)`：**plain=true 会把 `^` 也当普通字符**；`|` 在 Lua 模式里是**字面量**（不是交替）。
- ★★**中文/多字节串上的模式匹配（1.70.47 一次踩中两个，代价是「整类条件解析不出来」）**：① `|` 不是交替（`(队伍|团队)` 只在匹配字面串时成立）；② **字符组 `[伍团]` 按字节匹配**——set 只吃**一个字节**，`[伍团]` 实际是 `{228,188,141,229,155,162}`，匹配到「伍」首字节后剩两尾字节对不上后续 `buff`，照样失败。**正确写法：用 `(.+)` 抓下来再 `==` 比较**。★症状有欺骗性：**编辑窗能存、导出也正常，但重新导入时条件静默消失**；只有「导出→导入」**往返断言**能抓住（本轮靠组 66 当场定位）。

### I. 参考代码路径（**先读对方**，见铁律 2 / 3）
- **UnrealQuest**：`...\Interface\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（实测配方库，注释里全是坑）、`Core/Driver.lua`（帧父级/生命周期）、`Map/MapContext.lua`、`Map/WorldMapPins.lua`、`Map/NpcPins.lua`（CATEGORIES/RANK_ICONS）。
- **Cat（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计参考）；**OneJudge**：`...\AddOns\OneJudge\OneJudge.lua`（最初的参考：纯色纹理配方）。
- **Heart + C（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Heart`（团队/治疗框架）与它依赖的共享库 `...\AddOns\C`（隐形 tooltip + 单位/buff 采集）——**队伍/血量/蓝量/buff 检测见铁律 3**。

## 七、开源仓库 / 官方 API 文档 / 待开发计划

### 7.1 开源仓库（1.21.0 起）
- 库内含：`README.md`（开源门面 + `preview/` 界面图）、`CHANGELOG.md`（更新日志详情）、`DEVELOPMENT.md`（开发者指南）、`CLAUDE.md`（AI 记忆体副本，改主记忆后同步过去）、`luacheck.js`、`test_engine.js`/`test_stub.lua`/`test_assert.lua`（冒烟测试）、`example/zs_wq.md`。
- **更新日志维护规则（1.28.0 起，用户定）**：① 详情写 `CHANGELOG.md` 的 `## 🎯 vX.Y.Z — 主题` 小节（要点/典型用法/设计亮点，配一个 emoji）；② README 顶部「更新日志」速览表加一行（`| **X.Y.Z** | emoji 主题 | 一句话亮点 |`，**最新在上**）；③ **README 不再放版本详情**（保持精简）。
- **`preview/` 图片只用用户提供的**（当前 main.png=全局页 / cfg.png=一键宏设置页 / skill_cfg.png=技能编辑窗 / info.png=战斗信息UI+状态信息UI）；我加的截图已被用户要求删除——**别再自行往里放图**。

### 7.2 官方 API 文档（用户提供 2026）
- **Lua API 清单：https://emberveil.org/wiki/lua**（1370 条目，页面内嵌**全量 JSON 索引可脚本解析**；分类页如 `/wiki/lua/globals/Action` 有签名 + 返回值文档）。
- ★**本机就是游戏主机**：EmberVeil 与 TurtleWoW 都在本机，改码 → `node luacheck.js`/`test_engine.js` → `/reload` 实测都在同一台机器上完成（推送 gitee 仅为备份/发布）。

### 7.3 待开发计划（搁置项）
- **免疫学习器**（✅ 1.36.0 已完成实装：探针验证 → 事件解析 → 学习表 → 引擎跳过；探针 `/eh go probe immune/dump` 保留作诊断工具）：
  - 已排查结论：**无 CombatLog API、无免疫查询函数**、wiki 无事件文档页（`/wiki/lua/events` 404）；但 `Frame:RegisterEvent`/`RegisterAllEvents` 可用。
  - 设计方向：订阅 `CHAT_MSG_*` 战斗文字事件，从消息串解析「免疫」→ `cfg.war.immune["技能@怪名"]` 持久化 → `EVAL_RULE_RUN` 对同名怪自动跳过该技能（可流血黑白名单 `EVAL_BLEED_BLACKLIST` 的自动化升级版）。
  - 前置步骤：先做探针 `/eh go probe`（30s 事件抓取写调试日志缓存）拿真实事件名 + 免疫文本格式，再写解析器；复用 `autoFrame` OnEvent 三态兼容范式（事件名在 1 参 / 2 参 / 全局 event）。
  - 相关基建：`st.canBleed` 判定链（白名单 > 黑名单 > 生物类型排除）。

## 八、项目位置与现状

- **插件目录**：`G:\game\u5wow\Azeroth\Binaries\Win64\Games\Emberveil\live\Azeroth\Interface\AddOns\EvalHelp\`（1.21 后由 EVAL_HELP 改名 **EvalHelp**；★**目录名 == toc 基名**才加载；改名时游戏必须关闭，否则 Access denied）。
- **文件结构（1.39.0 起模块化，不是单文件）**：`EvalHelp.toc` + `Locales/{zhCN,enUS,ruRU}.lua` + `Core.lua`（输出/i18n/状态采集）+ `Engine.lua`（规则引擎）+ `EvalHelp.lua`（UI/斜杠命令/init）+ `Toolbox.lua`（工具箱 Tab3）+ `DataSearch.lua`（数据检索 Tab4）+ `Share.lua`（方案分享，1.71.0）+ `IconBrowser.lua`（图标库 Tab5）+ `examples/*.lua`（**11 个数据文件**）；文档 `README.md`/`README_en.md`/`README_ru.md`/`CHANGELOG.md`/`DEVELOPMENT.md`/`CLAUDE.md`；测试 `luacheck.js`/`test_engine.js`/`test_stub.lua`/`test_assert.lua`。**行数随开发变化，别当固定值引用**。
- ★**toc 载入顺序（以 `EvalHelp.toc` 为唯一真值）**：`Locales/{zhCN,enUS,ruRU}` → `Core` → `Engine` → `EvalHelp` → **`examples/*`（11 个数据文件，必须排在 EvalHelp.lua 之后）** → `Toolbox` → `DataSearch` → `Share` → `IconBrowser`（★`EXAMPLES TOC CHECK` 守着「磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序」）。
- ★**新增 .lua 模块要同时改三处**：`EvalHelp.toc` 载入列表、`test_engine.js` 的加载数组（否则测试根本不加载它）、`DECL ORDER CHECK` 的文件清单（**目前 7 个文件**：EvalHelp/Core/Engine/Toolbox/DataSearch/Share/IconBrowser —— Share 与 IconBrowser 已纳入，不再是盲区）。
- ★**案例模版数据文件（1.71.2 新增 `examples/*.lua`）只需改两处**：`EvalHelp.toc` + `test_engine.js` 加载数组（它们没有顶层 local，故不进 DECL ORDER 清单）。
- **当前版本**：**1.72.1**（头条 = **新手上路友好化**：加载成功提示 + 首次进入自动播报四步新手指引；
  ① 建议开启战斗信息UI（/eh ui）② 配置第一个宏（/eh cfg → 添加技能 / 案例模版）③ **绑键首选「右键方案 → 方案管理 → 快捷键 → [保存]」**（用户定：让用户点点点就能完成），**创建宏降级为备选一行** ④ 技能释放异常 → 开技能日志（战斗日志→方案）+ /eh logdump ⑤ 小地图 EH 图标悬停有说明、点击开配置台）；
  入口三处：首次自动播报 / 配置窗全局页 [使用引导] 按钮 / ` /eh guide`（也认「新手」）；三语言 README 同步（版本表 10 行、里程碑范围 1.72.1、en/ru 补赞助板块、zh 快速上手清掉战士措辞）；
  ★**已推送**（origin + github 两端 + tag）。
  - 上一版 **1.72.0**（★一次覆盖 v1.71.3 ~ v1.71.24 的大版本发布：上一次发布是 v1.71.2，中间积压 22 个版本 / 26 个提交全在本地 → 合并成一个个 minor 版本一次发布；
  头条 = **方案快捷键从「永远不触发」到真正生效**（四次试错：CLICK 劫持鼠标 → 裸命令名不派发 → **Bindings.xml 本客户端不读** → **接管 ActionButtonDown/Up**）；
  另有**右键功能合并**成「方案管理」窗、案例模版窗三次改版、图标库 Tab、战斗信息UI 系列精修）；
  - 上游 **1.71.24**（右键合并成「方案管理」窗：① 方案名称 ② 快捷键，[保存] 一次提交两段；★★**不为旧入口留别名**——留别名会让「调用点改回旧名字」的回归悄悄通过）；
  **1.71.22**（★方案快捷键真正生效：`ACTIONBUTTON<n>` + 接管全局 `ActionButtonDown/Up`，零成本/不占宏位/不抢键位/运行中立即生效）；
  **1.71.2**（施法条件归组 + 配置窗整理 + 案例模版外置 + 一批「静默失败」修复）；**1.71.0**（方案分享 `Share.lua`）由另一分支提交后合并进来；
- **★工作流铁律（用户定）**：**默认**——用户实测验证通过之前**不发版、不推送**（改动只落工作区文件，让用户 `/reload` 直接实测；
  ★**报告里不要催促提交**）。
  ★★**1.71.6 起用户追加**：「**下次完成测试可以直接提交版本**」——即**本地测试双绿（两条都 exit 0）即可直接 commit + 打 tag**，不必等游戏内实测；
  **推送仍需用户明确要求**（v1.71.3~v1.71.24 已提交 + 打 tag；★**v1.72.0 是用户明确要求发布后推送的**——
  这批 22 个版本积压太久，合并成 1.72.0 一次推到 origin + github 两端）。★1.71.1/1.71.2 两次发版也是用户明确要求的结果。
- **数据检索 Tab4（在途主功能）**：
  - **数据源**：`UnrealQuestData` 全局表**懒惰读取**（EvalHelp 载入早于 UnrealQuest，载入期拿不到）；对方缺席时整页只显示**安装引导**并**收起全部交互控件**（1.70.46）。
  - **硬依赖**：地图/图钉/坐标/tooltip 全部复用 UnrealQuest API（1.70.9 用户拍板，自实现回退已删）；引用它的素材必须**原样抄它的路径常量**。
  - **分层**：`EVAL_DS_SEARCH`/`DETAIL`/`SHOWMAP` 逻辑层与 UI 分离，可 node 直测；反查索引懒构建 + 会话缓存。
  - **标注层**：统一单池 + 16 类别 + 地图绑定（`DS_ANN_MAX=500`）；**tick 帧必须挂 `WorldFrame`**（挂 `UIParent` 会因全屏地图隐藏 UI 而整个停摆）。
  - **测试**：组 42 系列（搜索/详情/地图/标注层/日志通道）+ 组 61~65（窗口尺寸/剩余时间/依赖提示/真实接线）。
- **自查清单**：任何 .lua 改完必跑 `node luacheck.js` + `node test_engine.js`（见第一节铁律 1），**两条都要 exit 0**。

## 九、版本要点汇总（最近 20 版，每版 1~2 行；完整记录见 CHANGELOG.md 与 git log）

> ⚠️ 这一节位于**文档最末尾**：超预算时**最先被截断的就是它**（预期行为）。要查某版本细节请看 `CHANGELOG.md` 或 `git log`；判据请看第五节。

1. **1.72.0** — 🎉 **一次覆盖 v1.71.3~v1.71.24 的大版本发布**（上一次发布是 v1.71.2，中间积压 22 个版本 / 26 个提交）。头条 = **方案快捷键从「永远不触发」到真正生效**（四次试错：CLICK 劫持鼠标 → 裸命令名不派发 → **Bindings.xml 本客户端不读** → **接管 ActionButtonDown/Up**；零成本/不占宏位/不抢键位/运行中立即生效）；另有**右键功能合并**成「方案管理」窗、案例模版窗三次改版、图标库 Tab、战斗信息UI 系列精修。断言组扩到 102，各版本变异测试全捕获。
2. **1.71.24** — **右键功能合并成一个「方案管理」弹窗**（用户：「将这两个功能合并成一个弹窗管理.都是右键触发.」）：此前配置窗方案右键=重命名窗、战斗信息UI 方案右键=绑定窗（两个窗两套 chrome）→ 合并成一个窗，窗内两段 ① 方案名称 ② 快捷键，**[保存] 一次提交两段**（互不牵连：空名字只拒绝改名、绑键照常）；**两处右键都开同一个窗**、左键语义不变。★★关键决定 = **不为旧入口留别名**（留别名会让「调用点改回旧名字」的回归悄悄通过 —— 实测变异 M1/M2 正是这样 SURVIVED 的）→ 删掉旧名 + 补「数窗 / 旧名不存在」两条**结构断言**；组 102 + 变异 **8/8** 全捕获。
3. **1.71.23** — **清理四次试错留下的死探针**：删掉 `go bind2`/`go bind3`/`go actbar` 三个**写入型**探针（验的都是已被证伪的 CLICK / 裸命令名 / Bindings.xml 路线 —— 留着只会误导后人），`go bind` 从「写入试验」改为**只读现状检查**（派发前提 / 接管状态 / 逐方案绑定与占用格）；`EvalHelp.lua` 净减 **205 行**；`/eh go diag` 保留为唯一诊断入口。
4. **1.71.22** — ★方案快捷键**真正生效**：四次试错定案 —— ①CLICK 劫持鼠标、②裸命令名不派发、③**Bindings.xml 本客户端根本不读**（ArchiTotem 启用+完整重启后命令表里依然没有它的 `CAST_*`，恒 226 行；unrealUI 源码注释同日记录同一结论）/ ④**可行路线 = 命令名用客户端自带的 `ACTIONBUTTON<n>` + 插件接管全局 `ActionButtonDown/Up`**（`/eh go diag` 实测四者 `type=function`、`SetOverrideBindingClick=nil`）。零成本：不占宏名额/不占动作格/**不抢已有键位**/**运行中立即生效**；补回组合键守卫；清除时**把格交还客户端**；删掉已证伪的 `Bindings.xml`；组 98 重写 + 组 101 判据改写 + 变异 6/6 全捕获。
5. **1.71.21** — **Bindings.xml 随插件自带**（用户三问的定案：文件插件发 = 零配置 / 绑定走弹窗 = 零手动 / 用户只重启客户端一次；`EVAL_BIND_XML_STATUS()` 登录自检：命令表没有 EVAL_GO_PROF_* 就如实提醒重启一次）；★文档深挖定案：`RunBinding` 派发靠客户端侧 **press/release 处理器**、插件无法注册（`SetConsoleKey` = 写明「什么都不做」的兼容桩）→ 裸名永不触发、注册只走启动命令表；组 101（精确前缀计数）+ 变异 2/2 全捕获。
6. **1.71.20** — 左键点「方案」= **打印当前绑定情况**（逐行 方案=键、只打印不动绑定、没有就如实说没有）；★用户边界 = **游戏运行态无法生效的方案不考虑**（Bindings.xml 需重启客户端 → 删除出局）；附 `/eh go bind3` 无尾 CLICK 探针（候选元凶 = 隐藏按钮没禁鼠标/没挪出屏幕）；组 100 + 变异 4/4 全捕获。
7. **1.71.19** — 「方案」标签**可点化**：悬停三行美化说明（左键激活 / 右键绑定 / 右键标签全清）+ **右键 = `EVAL_BIND_CLEAR_ALL()`**（逐键解绑 + 清表 + 存档 + 返回个数，幂等）；组 99（真实右键/真实悬停 tooltip）+ 变异 4/4 全捕获。
8. **1.71.18** — 绑定派发**弃用 CLICK 改裸命令名 `EVAL_GO<i>`**（用户实测：CLICK 命令串被客户端解析岔了——E 没触发、鼠标左右键转屏被劫持但会触发插件 = 链路通、命令串错）；★教训 = **绑定表接受 ≠ 派发会执行**，派发形态必须实弹验证；反向哨兵「每个派发命令名都必须 `type(_G[...])=="function"`」；变异 3/3 全捕获。
9. **1.71.17** — 初始默认图标改**「力量祝福」**（用户定稿：她右键挑的金色拳头 → 默认也用同一枚，`^SPELL_HOLY_BLESSINGOFSTRENGTH` 排候选最前；亲自挑的仍永远优先）；变异 2/2 全捕获。
10. **1.71.16** — **方案快捷键绑定**（先 `/eh go bind` 验证：SetBinding 接受自定义命令名，无需 Bindings.xml）：方案行**右键** → 美化弹窗（分类下拉选键：功能键/数字/字母/鼠标/组合键 + 冲突提示）；派发 = **CLICK 隐藏按钮**（`CLICK EVAL_GO_KEY_i:LeftButton`，vanilla 经典招）；★T2 只证明「命令名能存进绑定表」，“按下真的触发”附实弹探针 `/eh go bind2` 复核；换键自动解旧键 + 绑定即 `SaveBindings`；组 98 + 变异 6/6 全捕获。
11. **1.71.15** — 图标库**右键 = 设为小地图按钮图标**（修「图标调整的不对」：她的图标让她自己挑，`cfg.mbIcon` 持久化、**亲自挑的永远优先**于自动挑，`/eh go mbicon [reset]` 查/清）；★定案范式 = 「代挑被否 → 给挑选入口」而不是再代挑一次；组 97（真实右键 OnClick）+ 变异 3/3 全捕获。
12. **1.71.14** — 全局页「一键宏」组**底部对齐**（修与「状态信息UI」重叠：1.71.12 加两行子开关把它顶到组头上）——整组改**从底部按钮行向上锚**（去抖行下缘 = `NAV_ROW_Y + 6`，行距不变）；★「界面组加行 → 下方组要跟着挪」这类连锁，断言读**真实控件**位置（`cfgWin.macroUI`）才接得住；组 96 + 变异 3/3 全捕获。
13. **1.71.13** — 小地图配置按钮**改图标钮**（无边框、26×26 与图标库单格同边长、图标占满整钮；运行时从宏图标表**按名字优先级**挑：扳手 > 工程学 > 齿轮，不写死路径；挑不到退回旧「金框 + EH」不留空白按钮）+ tooltip 美化（三功能描述，5 键 × 三语言）+ 探针 `/eh go bind`（快捷键可行性 T0/T1/T2）；★宏图标路径只能运行时查 `GetMacroIconInfo`（打包在 Content\Paks，磁盘取不到）；组 95 + 变异 5/5 全捕获。
14. **1.71.12** — 战斗信息UI：**标题改用玩家名**（取不到退回语言包文案，不留空白）+ **「战斗 / 方案」两个子开关**（分开控制显示与隐藏：关 = **整块不画**、布局随之前移、帧高变小；`nil` = 开，老配置行为不变）；★tick 的普攻判定不随区块一起跳过；组 94 全程点**真勾选框**验真重建，变异 8/8 全捕获。
15. **1.71.11** — 方案行给「拉伸」设上限（每格最多比名字宽 +24px，超出留在行尾）——修用户第二轮报的「空的太多了」；★判据补「不许拉成空框」的反向哨兵，且**故意不读生产上限**（读了会被一起变异：M6 实测 SURVIVED，换成独立上界后才捕获）。
16. **1.71.10** — 战斗信息UI **方案切换行**改「按名字实测宽 + 贪心换行 + 每行均摊填满」（修用户报的「方案溢出宽度」）；改名/增删走签名比对整体重建，tick 里不量宽。
17. **1.71.9** — 技能列表调序/滚动按钮 `^`/`v` → **真三角 ▲/▼**；图标库一页 **6 → 9 行**（162 枚/页，原 108；行数是先算清可用空间定的）。
18. **1.71.8** — 案例模版窗改**分组分两列 + 组内同行自动换行**（11 组 27 条；中文 660×240）。
19. **1.71.7** — **队伍/团队案例模版审计**：17 条模版改「指定技能 + 队伍/团员条件」。
20. **1.71.6** — 案例模版窗改**流式（自动换行）布局**（中文 660×180，5 行）。
21. **1.71.5** — 案例模版补「一键队伍驱散 / 一键团队驱散」（覆盖魔法 + 疾病）。
