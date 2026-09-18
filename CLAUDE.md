# EVAL_HELP 插件项目记忆（EmberVeil 全职业施法工具）

> 本文件只记**铁律 / 判据 / 关键注意项**：逐版本细节在 `CHANGELOG.md` 与 git 提交历史，不进这里。
> **发布流程见第 2 节**（每次发版必做 **9 步**：文档 6 步 + 提交打附注标签 + 推送 + 出包建 Release）；**项目位置 / 当前版本 / 在途状态见第八节**「项目位置与现状」。
> **完整版本要点汇总在文档最末尾（第九节）**——超预算时**最先被截断的就是它**，属预期，不影响前面的铁律与判据。
> ★写入纪律：**先查有没有同类条目——宁可合并改写，不要追加流水账**；★头部只保留比较新的记忆（最多 20 个版本）。
> ★要查「某个功能/某个坑现在怎么写」→ 先看第五、六节的判据，再看 `DEVELOPMENT.md` 与源码。

## ★★★「提交版本」≠「release」（用户 1.72.1 明确划定）

- **用户原话**：「提交版本不要触发 release。在我明确要求 release 才进入这个环节」。
- **「提交版本」= 只做**：`git add <显式路径>` + `git commit`（+ 用户要求时 `git push origin master && git push github master`）。
- **「release / 发布版本」= 才做 9 步全套**：统计里程碑 → 三语言 README 更新 → 旧版信息扫描 → 里程碑同步 → 版本号与 CHANGELOG → 记忆体审计 → **打附注标签** → **推标签** → **出 zip 发布包 + 建 Release 页**。
- ★**判据**：只有用户**明确说出「release / 发布 / 出包 / 建 Release」**时才进第 7~9 步；只听到「提交版本」「提交」「commit」一律停在第 7 步的 commit（推送仅在用户同时要求时做）。
- ★**代价记录（1.72.1）**：用户说「提交版本」而我按 9 步跑完了全套（tag v1.72.1 已推两端 + zip 已出）——多做了用户没要求的事。**不确定时先问一句「要不要一并打标签/出包」，不要自行升级到 release**。
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
   ★另有 **`PACK LIST CHECK`**（第 18 道：1.73.0 加：记忆体第 9 步的发布包模块清单必须与 `EvalHelp.toc` 的顶层 `.lua` **逐个一致**，且「条目数基准」必须等于按打包口径现算的真实集合大小——守「新增模块后清单/基准过期，出包缺文件用户装不上」这一类**不报错、只是清单过时**的事故；变异：删掉清单里的 PetData.lua / 把基准 62 写回 60 / 清单塞不存在的模块 → 三发全中）。
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
# ★只装运行必需：.toc + 10 个 .lua 模块 + Locales + examples + media + 三语言 README/CHANGELOG/DEVELOPMENT
# ★★清单必须**跟着 EvalHelp.toc 走**（下面的模块名与基准数由源码检查 PACK LIST CHECK 守着，改漏一处当场 FAIL）
Copy-Item "$src\EvalHelp.toc","$src\Core.lua","$src\Engine.lua","$src\EvalHelp.lua","$src\Toolbox.lua","$src\DataSearch.lua","$src\Share.lua","$src\IconSem.lua","$src\IconBrowser.lua","$src\PetData.lua","$src\PetHelper.lua" "$staging\EvalHelp\"
Copy-Item "$src\README.md","$src\README_en.md","$src\README_ru.md","$src\CHANGELOG.md","$src\DEVELOPMENT.md" "$staging\EvalHelp\"
Copy-Item "$src\Locales","$src\examples","$src\media" "$staging\EvalHelp\" -Recurse
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.73.5 基准 = **63 个**；1.73.0 时是 62，多了 IconSem.lua）：少一个就是缺文件，用户装了会**直接报错**。
  ★这一条与上面的模块清单都有源码检查 `PACK LIST CHECK` 守着（清单与 .toc 逐个比对 + 基准数按打包口径现算），过时当场 FAIL。
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
- **源码级检查**（`test_engine.js` 内，**改了对应区域就必须让它们继续通过**）：`WIN WIDTH`（窗口宽度单一来源）· `DECL ORDER`（**9 个文件**的顶层 local 声明早于使用——1.73.0 起含 PetData/PetHelper）· `LAYOUT`（`EVAL_DS_BUILD` 布局常量）· `VERSION`（源码 VERSION == toc）· `LANG KEY`（`L("字面量")` 三语言齐全）· `LANG SOURCE`（取语言只认 `EVAL_GET_LANG`）· `WINDOW SIZE`（自建窗真的设了宽与高）· `COMMENT SWALLOW`（语句没被行尾注释吞掉）· `ICON`（图标素材真实存在）。
  后续又加到 **18 道以上**：`STOP ATTACK WIRING`（第 13 道：`stopAllOf`/`followOf` 那 7 个站点接线）· `UI ICON`（第 14 道：纹理路径逐个核到磁盘 + 类别图标不许撞图）· `CHAN RETRY WIRING`（第 15 道：`tbChanRetry()` ≥3 处接线 + 手动重试入口）· `EXAMPLES TOC`（磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序 + 数据不许搬回生产文件）· `README TABLE`（第 16 道：3 个 README 的版本行必须全在「更新日志」表里、恰好 10 行；CHANGELOG 保留完整历史 —— 守「发版脚本把版本行插错表」这类**不报错只是位置不对**的事故）· `MILESTONE`（第 17 道：3 个 README 都有 🏁 板块 + **里程碑在更新日志之上** + 标题范围末端 == 当前 VERSION + **板块正文 1..10 行**（10 个点、一条一行）+ **每条都是 `- ` 列表项**—— 守「顺序反了 / 里程碑又写成版本流水账 / 只更新了 CHANGELOG 忘了里程碑范围 / 排版被合并成一大段」）。
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
- ★★★1.72.3 **分享分片必须限频发送**（用户实测：「长方案对方有时候接收不到」，短方案 1 片从不出问题）。
  【根因】`Share.lua` 原实现在一个 for 循环里**连着 `RunScript('SendChatMessage(...)')`** 把 N 片一次发完
  （同一帧 N 条聊天）→ 撞反刷屏限流被吞一片 → 接收端**永远收不齐**（而收不齐当时还是静默丢弃，见 5.2）。
  ★这正是本节早就写明的铁律的又一次违反：「**RunScript 本身也是队列，连发聊天同样会被反滥用踢线**，通知类输出也要入限频队列」。
  【修法】第 1 片立即发（手感不变），其余进 FIFO 由 OnUpdate 每 `SH_SEND_RATE=0.5s` 滴一片（**2 条/秒**，给服务器留余量），
  队列上限 `SH_MAX_QUEUE=200`（超出如实取消）；★**绝不在瞬间倾泻大量文字**（用户明确：不然服务器被触发预警）。
  ★判据 = 断言组 106（只准立即发 1 片 + 同刻 tick 也抽不干 + 分时发完）；变异 M7（退回一帧全发）→ 当场 got=9 want=1。
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
- ★★★1.73.28 **别在 Lua 源码里手写转义**（本轮代价）：想写「引号 + 反斜杠」时手写 `"` / `\\` 极易写坏
  （实测把 `string.gsub(name, "[\"\\\\]", "")` 写成了 `"["\]"`）→ 而且 **luacheck 当时只查主文件、照样报 SYNTAX OK**，
  直到运行时 load 才炸（LOAD ERROR ... expected ')' near backslash）。正解 = 用 `string.char(34)` / `string.char(92)` 构造这类字符，
  抽成一个小函数（`tbSafeName`）复用；★同时把 `luacheck.js` 改成**逐个文件**检查（27 个 .lua），语法错误再也漏不过去。
- DSH 策略 danger-full-access、审批关闭 → **可直接写游戏 AddOns 目录**。
- **SavedVariables 落盘路径已实测**：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`（★**文件名是 `EvalHelp.lua` 不是 `EVAL_HELP.lua`**，1.29.0 改名后旧文件 `EVAL_HELP.lua` 是历史残留；小退/reload 时客户端写入）——**这也是现在读调试日志的地方**。

### 4.3 当前功能地图（用户视角）
- `/eh` 状态日志 | `/eh ui` 战斗信息UI（方案切换行 + 方案技能行 + 条件 tooltip + 实时条件亮金）| `/eh st` 状态信息UI（状态变量 + 最近释放条件明细）。
- `/eh cfg` 配置窗 660×420（中文）/ 800×420（西文），**六个 Tab**：① 全局（日志/界面/帮助）② 一键宏设置（方案栏 + 技能列表 + `[添加技能]` + `[导入导出]`；1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**）③ 工具箱（`Toolbox.lua`，1.68.0）④ 数据检索（`DataSearch.lua`）⑤ **图标库**（`IconBrowser.lua`，1.71.3）⑥ **抓宠帮手**（`PetHelper.lua` + `PetData.lua`，1.73.0：检索宠物技能 → 详情页驯服来源 → 放大镜跳数据检索）。
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
- ★★★1.73.15 **`cond and f() or fallback` 在 `f()` 返回 false 时恒取 fallback**（Lua 的 and/or 链**没有布尔语义**）：
  【第二次踩同一个坑】1.70.46 在语言来源上踩过（`... and EVAL_RESOLVE_LANG() or "zhCN"` 恒等于 "zhCN"）；
  1.73.15 又在新加的「接收方案」勾选框刷新里写成 `(type(f)=="function") and f() or true` →
  **关掉开关后勾选块仍然亮着**（界面与真值自相矛盾）。★正解 = **分两步**：
  `local on = true; if type(f) == "function" then on = f() and true or false end`；让 f 返回 nil/值也可以。
  ★判据：凡要表达「假」的分支，都不许走 and/or 链（变异 M163 用这条抓）。
- ★★**空字符串在 Lua 里是真值**（`GetQuestLogTitle` 给 `""`）→「键存在」与「有内容」是两件事（入库层与播报层各挡一道）；`string.len` 是**字节数** → 宽度按字符数估（`FontString:GetStringWidth()`，退化「字节数/3」）。

### 5.2 静默失败族（数据 / 序列化 / 开关）
- ★★★1.72.2 **具名帧会占用同名全局**：`CreateFrame("Frame", "X", parent)` 与 `function X(...)` **同名**时，
  真客户端里帧**顶掉函数** → 入口写的 `if type(X) == "function"` 不成立 → **命令静默失效**（无报错、无提示）。
  【实事故】`EVAL_DS_HUD`：`/eh ds hud` 第一次还能开，帧建出来之后**再也关不掉**（这个探针还是取证协议里要用的工具）。
  ★暴露途径 = **测试桩补上了真客户端行为**（旧桩 `CreateFrame` 只存 `__name`、不挂全局 → 「同名冲突」在测试里根本不存在）；
  桩改完后组 54 当场报 `attempt to call a table value`。★判据已落成源码检查 **`FRAME NAME CLASH CHECK`**
  （21 个具名帧逐个与全部 `function NAME(` 比对；变异 M6 = 把帧名改回同名 → 检查崩 + 组 54 崩，双重捕获）。
- ★★★1.72.3 **分享接收：冗余时长 + 只认标识**（用户要求：「分片接收添加接收冗余时长.比如 1-2 秒内都可以…
  但是方案只识别方案特定的标识」）。两级判定：
  ① 空闲超过 `SH_RECV_TOLERANCE=2s` 仍未收齐 → **如实提醒**（点名发送者 + 已收 k/n 片「仍在等剩余分片」），
     ★**但不删缓冲** —— 晚到的分片补齐后**照样弹窗**（这就是「冗余时长」的价值：旧行为到点就删，救不回来）；
  ② 空闲超过 `SH_BUF_TIMEOUT=60s` 才真正丢弃（已提醒过就不重复刷屏）。
  ★计时按**最后一片到达时刻**（每片刷新）→ 发送方持续滴片时窗口顺延，长方案（总耗时 4~5 秒）不会被误报。
  ★**只认 `[EHPF#<id> i/n]<hex>` 这一个标识**（整串锚定 `^...$` + 载荷必须是纯 hex）：
  同一頻道里的普通聊天、甚至形似但载荷非法的消息一律**完全忽略**（不入缓冲、连提示都不发）。
  ★判据 = 组 106（限频/收齐/超时点名）+ 组 107（跨秒收齐、夹普通聊天、非法消息忽略、**晚到补齐仍弹窗**）；
  变异 M8（退回静默）/ M9（退回「到点就删」）/ M10（取消防抖间隔）→ 全被捕获。
- ★★★**「查不到」与「没有」是两件事**：查不到必须**如实报错**（`texOf` 回 nil 退化成查空串 → `cnt=0` → 「否/无」成立 → **规则无限重放刷屏**）。
- ★★★**静默丢弃 = 那一行变成无条件施法** → 文本里写了几条成员条件、解析后就必须有几条；**数据类错误全是静默的**（类型写错一个字就谁都不解/打错人，不报错）→ 模版与配置必须配体检断言。
- ★★★**导出侧写的形态与解析侧认的形态必须成对验**（`施法中:` / `施法中:nil` 都读不回 = **导入即丢条件**）；**「有过滤」≠「过滤得住」**（`itemOf(n)` 只认带前缀的「物品:名」，动作条物品经 `wactionName` 是裸名 → 漏网）。
- ★★★**两个日志开关不能合并**（`cfg.log.on`=数据层总闸门、`cfg.wdebug`=输出层「说不说」）；**命名也是功能**（「调试日志」vs「记录调试日志」→ 改「方案技能日志」）；★静默 = 只进日志、一个字都不上屏，**绝不走 `EVAL_SAY`**。
- ★★**判据表要照客户端真实文案抄**（真实文案是「**进入**频道。」，旧表只有「加入」→ 那一半功能根本没生效）；**「尝试过」≠「挂上了」**（载入即挂必须**失败重试**：`Toolbox.lua` 载入那刻 `DEFAULT_CHAT_FRAME` 还没建好）。
- ★★★1.73.25 **按「序号」做键的数据，删中间项必须整体左移**（用户：「方案删除 要删除对应绑定的按键信息」）：
  cfg.war.bindKeys / bindSlots 都是 **[方案序号] = 值** → 删掉第 idx 个方案时要 ①**解绑它自己的键**（SetBinding + 清表）
  ②把 idx **之后**的绑定**整体左移一格**（★不左移 = 被删方案的键会「粘」到下一个方案上，按那个键就激活错方案）
  ③SaveBindings 落盘；★播报如实（「已解除它自己的快捷键绑定 / 后面 N 个已左移一格」）。
  判据 = 组 131 逐条钉序号与格号映射；变异 M215（不左移）/ M216（不解绑）全捕获。
- ★★**Lua 的 function 不是 table** → 不能 `wrapper.__flag = true`（身份判定只能 `cur == TB.chanWrapper`）；**标记只加在显示串上**（动作条物品 `[物]` 只改显示、取值仍裸名）→ ① 扫描真打标 ② 显示带标**且取值不带**；**「还原/撤回」不是回退到有 bug 的状态**；**跨玩家功能的提示要写出「对方那一侧的前提」**（`shOnMsg` 的 `if not shCfg().recv then return end` = 静默忽略 → 必须点名「接收方案」开关）。

- ★★★1.73.14 **「借用了别人的 UI 对象」= 静默破坏玩家界面**（用户报「开启战斗UI 后物品 tooltip 显示几秒就自动隐藏」）：
  【根因】`Engine.lua` 的读数口写的是 `local WTT = GameTooltip` —— 「隐形 tooltip 当 API 用」这个范式
  （Heart/C 的 `C_Tooltip`）**要求的是自己新建的那个**；借用真身时每次读都要
  `SetOwner(UIParent,"ANCHOR_NONE")` → `ClearLines()` → 填内容 → `Hide()`，
  于是**战斗UI / 状态UI 的定时刷新**（条件求值要读光环）会把玩家正看着的物品 tooltip **清空并关掉**（几秒一次）。
  ★正解：`CreateFrame("GameTooltip","EVAL_HELP_WTT",UIParent,"GameTooltipTemplate")` 自建 + `SetOwner(ANCHOR_NONE)` /
  `SetClampedToScreen(0)`（与 C.xml 同款 hack），读数一律走它；**读 TextLeft1 也必须读自家那个**
  （`<帧名>TextLeft1`，不是 `GameTooltipTextLeft1`）。
  ★退化路径（客户端不给该 frame 类型）必须有守卫：**真实 tooltip 正显示时就不读**——
  `EVAL_WTT_MAY_READ_PURE(isSelf, shown)` 抽成**纯函数**可单测，运行时 `EVAL_WTT_MAY_READ()` 包一层并计次。
  ★判据 = 组 126（自建且与 GameTooltip 不同对象 / 读遍四个入口**一次都不碰**真实 tooltip 的 SetOwner·ClearLines·Hide /
  读的是自家 FontString / 退化守卫三态）+ 源码检查 `WTT ISOLATION CHECK`（禁止 `local WTT = GameTooltip`、必须自建、
  必须读自家 FontString、必须有守卫与诊断；★**扫描前先摘注释**——说明文字里就写着那句反面教材，不摘就是假 FAIL）。
  变异 M154~M159 全捕获。
  ★★**桩保真（本轮两个关键点，缺一个这个 bug 在测试里就不存在）**：
  ① `CreateFrame("GameTooltip", ...)` 必须返回**另一个**独立 tooltip（真机语义），且**每个 tooltip 有它自己的 TextLeft1**；
  ② 真实 GameTooltip 的 `SetOwner/ClearLines/Hide` 要**记账**（`TEST.gtCalls`）→「读数有没有碰玩家的 tooltip」才**可断言**。
  ③ 这类 tooltip mock **必须是普通 table**（不能带 `__index` 兜底）：测试靠 `GT.SetUnitBuff = nil` 模拟「入口不可用」，
  带元表的 mock 会把 nil "复活"成兜底函数 → 前提根本建不起来（M157 实测；连带组 70 的「扫描器不可用」用例也会失效）。
  ★教训推广：**凡「借用共享 UI 对象」（GameTooltip / UIErrorsFrame / UIParent / 别人的帧）当读值口，都要问一句
  「我会不会把它清空/关掉/挪走」**——共享对象上的一次 SetOwner/ClearLines/Hide 就是玩家界面上的一次可见破坏。

- ★★★1.73.12 **「写成功了」≠「写进去生效了」**（用户真机截图定案，比上一条更毒一层）：
  `frame.AddMessage = wrapper` 在这个客户端**写入被吞掉**——pcall 不报错、INSTALL 自报「挂上 8 个 / 不可用 0 个」，
  而**逐框读回来**是「其中是我们的包装 **0 个**」。后果 = 频道屏蔽与名字着色**从来没拦到过一条消息**：
  ★「通知照旧显示」+「全都没染色」+「经过入口 0 条」**三个症状一个根因**。
  ★正解 = ① 挂入口**写完必须读回来确认**（`if _G.ChatFrame_OnEvent ~= wrapper then return false end`）；
  ② 换**普通全局函数**入口（本客户端 `ChatFrame_OnEvent` 是全局，写进去一定生效）：频道通知命中就
  **不调原函数**（这才叫真吞掉），名字着色把新文本**回写全局 arg1**（1.12 处理器从全局 arg1..arg9 取值）
  并作为第二参数转发；③ 非聊天事件一律原样放行（不许顺手改别的窗口事件）。
  ★判据 = 组 123 + 源码检查 `CHAT COLOR WIRING CHECK` 的「读回确认 + 幂等守卫」两条；变异 M137~M141/M142b 全捕获。
  ★★**诊断必须逐个入口分开计数**（AddMessage 那层 / ChatFrame_OnEvent 那层各自的 调用 / 吞掉 / 染色 + 收到的原文），
  否则「哪层在干活、哪层是死的」永远分不清（本轮正是靠 0/8 一眼定案）。
  ★★★**深入 API + 参考插件后的两条新路**（用户要求「解决不了就深入分析 API lua 和参考插件是否实现」）：
  ① **官方消息组**（api 全表 1369 条逐条核过，类别 ChatWindow）：`GetChatWindowMessages / RemoveChatWindowMessages /
     AddChatWindowMessages` —— 这是客户端官方给的「**某类消息不显示**」开关，**与「客户端走不走 Lua」完全无关**，
     是「屏蔽频道进出通知」最稳的实现。★组名清单 api 索引里**没有** → 现场从 GetChatWindowMessages 里探测
     「组名含 NOTICE」那一组（**不许猜组名**：猜错就是把别的消息一起屏蔽），摘掉前记下组名与原始组串，
     关掉开关时**按单个组名加回**（`AddChatWindowMessages` 收的是组名，塞整串会让集合重复 → 变异 M144 实测抓到）。
  ② **ChatMOD 的做法**（同代参考插件实证 `tmp/ChatMOD.lua:514-517`）：它在 **ChatFrame_OnEvent 处理体里**懒挂载——
     `this.AddMessage = S_AddMessage`，挂的是**事件里的 this 那个对象**，不是 `_G["ChatFrame1"]`。
     ★我们照做并**每帧只试一次 + 读回确认 + 成败都记账**（`thisOk` / `thisStuck`）。
  ★★**测试要能复现真机那种「写不进去」的对象**：用 `setmetatable({}, {__index=store, __newindex=function() end})` 造
     「写被吞、读回来还是原来的」帧（组 124 ⑧）—— 否则「如实记 thisStuck」这条判据在桩里**永远验不到**（M148 先存活后捕获）。
  变异 M143~M148 全捕获（不匹配组名 / 撤销塞整串 / 不做读回确认 / this 层不吞 / 同步不看开关 / 不记账）。

- ★★★1.73.18 **名字在 `arg2`，不在正文里**（用户「角色迷你还是没染色」两轮后靠**取证探针**定案）：
  真机样本逐条打印出 `arg1` = **只有正文**（`1` / `你有队`）、`arg2` = **发送者名**（`Ionol` / `猎狂`）——
  客户端自己把名字拼成「[名字] 说: 正文」⇒ **改 `arg1` 永远染不上色**；名字着色与「按发送者触发主动查询」都要挂在 **`arg2`** 上。
  ★着色姿势 =「**剥颜色码 → 用纯名字查缓存 → 用纯名字重建**」：① 客户端自己先上的**默认灰**照样改得成职业色
  （旧代码拿带码的串查缓存 → 永远查不到人）；② 已经是我们那层色 → 重建结果**逐字节相同** → 幂等（不重复包裹、两个计数都为 0）。
  ★★旧写法「看到 `|c` 就整段跳过」的那条守卫是**死代码**（同上：查缓存用的还是带码的串）→ 变异 M176 一开始**存活**；
  改成「重建 + 比相等」之后「剥码」才**承重**（删掉 → 灰名改不掉 → 当场捕获）。
  ★判据 = 组 129b（① arg2 包职业色且 arg1 一字不改 ② 不在缓存**不涂默认灰** ③ 幂等时 named/miss **都为 0** ③b 客户端灰 → 职业色
  ④ 主动查询按发送者名入队）；变异 M173b/M174~M180 全捕获；★**M173 单拆 SURVIVED = 等价变异**（直读 `arg2` 与兜底
  `tbCeSenderOf` 是**冗余的两条路**，单拆一条必被另一条抵消 → 必须**整组拆**，又一次印证 5.3 那条老经验）。

- ★★★1.73.19 **颜色码必须 8 位（`|cAARRGGBB`）—— 6 位客户端不解析、会把代码当普通文字画出来**（用户真机截图：
  聊天里出现「[|cf58cbaIonol|r]说: 1」这种**原文**，名字反而不显色）：
  【根因】职业色表存的本来就是 8 位（`fff58cba` = alpha + rgb），而写进聊天文本时用了 `string.sub(hex, 3)`
  **把 alpha 两位切掉** → `|cf58cba`（6 位）。★1.12 约定是 `|cAARRGGBB`，客户端只认 8 位才会解析。
  ★判据 = 源码检查 **`COLOR CODE LEN CHECK`**（禁止 `"|c" .. string.sub(` 切码写法 + 职业色表逐项必须 8 位）
  + 行为断言「色码 = `|c` + 8 位 hex」（arg2 / 正文包链接 / 正文改色码 三处各一条）；变异 M181~M184 全捕获。
  ★★教训：**「客户端约定」类的格式/长度错误，行为断言天然验不到**（断言比的是「我们自己写的串」，写 6 位它也觉得对）
  → 必须把约定本身写成**源码检查**；★M184（表里一项改成 6 位）**只有源码检查抓得到**（那项没被任何行为断言钉住）
  —— 「两类检查互补，缺一就有盲区」的又一实据。

- ★★★1.73.20 **名字槽（arg2）不吃富文本 —— 8 位色码也照样原样显示**（用户截图**逐字放大**后才定案）：
  同一屏里「名字槽中的 `|cfff58cba`」是**原文**，而我们经 `AddMessage` 打印的 8 位码**是有色的** ⇒ 与长度无关，
  是**这个槽位根本不做富文本解析**。★教训：**先分清「渲染通道」**——`AddMessage` 通道解析代码，聊天行的**名字槽**不解析；
  「名字没上色」别再一律往「色码长度」上赖（1.73.19 是长度，1.73.20 是槽位，两次症状相同、根因不同）。
  ★最后一条路只剩「**吞掉客户端那行 + 自己拼整行**」（代价：窗口分流 / 说喊气泡 / 音效），**不能靠猜** ⇒ 先做取证命令
  `/eh go 聊天 色测`（5 种名字写法让客户端自己渲染 + 打印客户端聊天格式串 + 展示自己拼的样子与代价）。
  ★★又一次**弱判据**：`含 "|Hplayer:Ionol|h[Ionol]|h"` 这种「**含**」断言会被**同屏另两行示例**顶住 → 删掉一行照样绿
  （M186 实测 SURVIVED）→ 正解 = **每种形态逐条**断言（公会 / 说 / 频道各一条）。
  ★★★**「还没弄好」的功能也要先止损**：定案之后，那段「以为能染色」的代码**每说一句话就把色码原文画进玩家聊天**
  （可见破坏 > 没功能）→ 立刻挂闸门 `TB_NAMECOLOR_WRITE=false`（**宁可不染色，也绝不显示乱码**），
  并把「**暂不回写 N 次**」连同原因放进诊断（**不许静默**）；★两条行为都留断言（关着 → arg2 一字不改；
  开着 → 真的包成 8 位色），**别让回写那段成为没被覆盖的死代码**（变异 M189~M192 全捕获）。

- ★★★1.73.22 **方案A：吞掉客户端那行 + 自己拼整行**（用户拍板；名字槽不吃富文本 ⇒ 这是唯一能染色的路）：
  ① **格式串抄客户端的**（`CHAT_SAY_GET`/`CHAT_YELL_GET`/`CHAT_GUILD_GET` 取证屏实测都在）—— 别自己发明文案；
  ② 类型色 `ChatTypeInfo[类型].colorStr` **只加前缀**（前缀后立刻 `|r` 复位，否则后面的正文会被带错色）；
  ③ 名字自己补 `|Hplayer:名字|h[名字]|h` 链接（**保住点名字密语**）；
  ④ ★★★**拿不准就不吞**（不在支持表 / 没那个格式串 / 模板不止一个 `%s` / 名字不在缓存 → 原样交给客户端）——
  **吞错了就是丢消息**，比没颜色严重得多；⑤ 频道/密语暂不支持（频道前缀要另给参数）→ 诊断里**如实写明支持范围**。
  ★★**弱判据实录（同一断言连着两次 SURVIVED 才定位）**：M195「频道不拼」先后被**另外两条守卫**替它挡掉
  （① 没给频道模板 → 「模板缺失」先返回 nil；② 给的模板是 `"[%s] %s: "` → 「多于一个 %s」又先返回 nil）→
  正解 = **把模板也给频道、且改成单 `%s`**，这条断言才只可能因为「不在支持表」而成立。
  ★★`string.find(post, "%%s", 1, true)` —— **plain 模式下找的是字面三个字符**，永远找不到 → 「模板不止一个 %s」
  这条判据**整个是死的**（组 129d③ 当场抓到）：plain 模式要写 `"%s"`（§5.1 那条老教训的又一次）。

- ★★★1.73.23 **类型色三来源 + 「没证据宁可不加色」**（用户当场报「公会前缀变白、名字有色」）：
  【根因】类型色只读客户端的 `ChatTypeInfo`，而这个客户端**取不到它** → 前缀拿不到色（名字靠自己拼的行内色，所以正常）。
  【修法】① 客户端 `ChatTypeInfo[类型].colorStr` **永远优先**；② 只给 `r/g/b` → 自己合成 8 位色码（四舍五入）；
  ③ 都没有 → **内置兜底表**。★兜底表**只放有证据的项**，没证据的类型如实 `none`（**宁可白着，绝不瞎猜配色**）。
  ★★**证据从哪来 = 拿取色器读用户截图**：客户端自己画的「[公会]」逐像素取色 = `40FF40`（与 vanilla 同值，29 次命中）
  —— 这就是「配色不许猜」的落地手段；诊断里**逐类型摊开来源**（client / client-rgb / builtin / none），
  下一次「某类前缀又白了」一屏就能定位是「客户端没给」还是「兜底漏了」。

- ★★★1.73.24 **右键聊天名字菜单**（用户要求；**先查 API 全表 + 参考插件**再动手，结论要落到注释里）：
  【排查结论（省得下次重查）】本客户端**有** `GuildInviteByName`（类别 Guild）与 `CanGuildInvite`；
  **没有** `SetClipboardText`/`GetClipboardText`（⇒「复制名字」**写不进系统剪贴板**，只能给「已全选」的框）；
  **没有** `UIDropDownMenu`/`ToggleDropDownMenu`（⇒ 菜单用自绘的 `tbText`/`tbBtn`）。
  【通道】参考 `tmp/ChatMOD.lua`（它包 `SetItemRef` 并塞自定义链接 `|Hinv:名字|h`）：**`SetItemRef` 是可写普通全局**
  （与 `ChatFrame_OnEvent` 同族）→ 包它 + **读回确认** + 幂等；我们**不塞自定义链接**（自己拼的行已带 `|Hplayer:`）
  ⇒ 只认 **player: 链接的右键**，**左键 / item: / quest: 等一律原样放行**（★接管必须「只认自己那一档」，否则抢掉客户端行为）。
  【不许假承诺】① 邀请先问 `CanGuildInvite`，**没权限就不发**并说明；直调不可用才走 `RunScript`；
  ② 「复制名字」如实说「本客户端没有剪贴板接口」（**不假称已复制**）；③ `/s` 是服务器写动作 → `RunScript` + **0.5 秒去抖**。
  ★判据组 130（读回确认/幂等 · 右键接管不转发 · 左键与非玩家链接放行 · 邀请三路径 · 复制读值口 · `/s` 去抖 · 开关真能关）
  + 变异 M205~M213 **全捕获**。

- ★★★1.73.27 **资源名（能量/法力/怒气/集中值）必须「显示时现算」**（用户问：「能量对法系职业是否也是魔法值？」）：
  `UnitPowerType` 约定 = **0 法力 / 1 怒气 / 2 集中值 / 3 能量**；★**德鲁伊随形态变**（豹=能量、熊=怒气、人=法力）
  ⇒ 把名字**写进建表时的表**（旧 `COND_NUMNAME.powerPct = "能量%"`）对法系/变形后的玩家就是**错的**（M230 实测：法系方案行显示「能量%>50」）。
  【修法】显示名一律走 `EVAL_POWERLABEL()`（Core 里按当前形态实时取值），下拉/按钮/方案行/导出**四处同源**。
  ★★★**改显示名＝改导出文本 → 解析侧必须同时认新写法**：补「法力/魔法/魔法值/蓝/集中值/集中/精力」及其 **% 形态**
  （还顺手补上原来就缺的「怒气%」）—— 否则**导出再导入就丢条件**（本项目「导出侧与解析侧必须成对验」的老纪律）。
  判据 = 组 132（名字跟随 powerType · 同一会话里变形后名字实时改 · 非资源类名不受影响 · 方案行与下拉同源 · 五种写法都能解析）；变异 M227~M231 全捕获。
- ★★★1.73.29 **「填进输入框」与「替用户发送」是两件事**（用户澄清：「在 /say 频道输入名字，但是不要打印出去，只是打开输入框」）：
  实现上就是**只预填、不回车**（`ChatFrame_OpenChat("/s 名字")` 或 `ChatEdit_ActivateChat` + 编辑框 `SetText`），
  **一律不碰** `SendChatMessage` / `RunScript`；退化的第三条路（两个接口都没有）也必须**如实提示「请手动输入」**——
  既不许静默，也**不许偷偷替用户发出去**。
  ★判据要**双向**：① 输入框里的内容对（`/s 名字`）② **一个字都没发出去**（RunScript 计数 0）——
  只验①会漏掉「顺手帮你发了」这种最讨嫌的越权（变异 M240 专门盯这个）。
  ★悄悄话与「复制名字」共用同一条预填实现（`tbMenuPrefill`），两条路各写一遍必然走样。
- ★★★1.73.30 **组标题栏宽度自适应 = 纯函数拼分隔条，渲染与断言同源**（用户：「工具箱 内项目标题栏宽度自适应」）：
  语言包里的标题自带装饰（`—— 任务·通知 ——`，字数固定）→ 列宽变了它不变 → 改成 `EVAL_TB_HDR_TEXT(标题, 列宽)`：
  **剥装饰 → 按本列宽补足两侧破折号**（宽度用「字符数 × 11px」估算，本机没有 GetStringWidth）；读值口读**真控件文本**
  （`EVAL_TEST_TB_HDR_TEXT`）→ 两者必须逐字相同（M244：渲染不用纯函数 → 当场响）。
  ★★**「含标题」是弱判据**：不剥装饰（标题里再套一层破折号）也能过 → 正解 = 断言「**带装饰的标签与纯标题算出同一条**」
  （M246 实测就是被这条抓住的）；另有「填满本列但不溢出」（M245 写死破折号数 / M247 算错可用宽度）。
  ★★**多字节字符不能进 Lua 字符集**（§5.1 老铁律）在这条上也踩得到：「—」是 U+2014（三字节）→ 用
  `string.char(226,128,148)` 构造后再 `string.sub` 比较，绝不写 `[—]`。
- ★★★1.73.31 **「弹窗点击不到」= 只设了 strata、没设 frame level**（用户报「自动购买的弹窗点击不到」，截图里工具箱行压在弹窗上）：
  同一个 strata 里先后**按 frame level 排**：配置窗的子帧（工具箱行按钮）level 更高 → 弹窗被画在下面、**鼠标也被它们吃掉**。
  ★修法三条（本项目的弹窗配方，照抄即可）：① `SetFrameStrata("DIALOG")`；② **明确 `SetFrameLevel(root, 200)`**
  （高于配置窗各弹窗 100~140、**低于**全局下拉 250）；③ `EnableMouse(true)` —— 不吃点击的话，弹窗**空白处的点击会穿透**
  到底下的复选框/按钮上（比"点不到"更隐蔽）。
  ★★**桩保真**：真客户端**子帧 level = 父帧 + 1**，桩必须模拟这条继承，否则弹窗 level 恒 0、这个 bug 在测试里**根本不存在**
  （M248 实测：不设层级时它的自然层级只有 2，而工具箱行控件在 12 以上）。
  ★判据读**真实控件的 GetFrameLevel**（弹窗 vs 工具箱交互控件）+ `IsMouseEnabled`，变异 M248/M249/M250 全捕获。
- ★★★1.73.32 **弹窗规程（本项目的「弹窗四级表」+ 三条硬规矩）**——用户让「审计弹窗是否符合项目弹窗规程」时可照这张表逐条核：
  层级阶梯（全是 `DIALOG`）：配置窗 **10** · 技能编辑窗 **100** · 导入导出 **120** · **通用输入弹窗 EVAL_TN 220** · 名称输入 130 · 分享 140 ·
  **工具箱内弹窗 200** · 全局下拉 `EVAL_DD_OPEN` **250**（最高，别被盖）。
  ① **从某个弹窗里打开的子弹窗，层级必须比它高** —— 否则被父弹窗压住：**点击与拖动一起失灵**
  （1.73.32 实测：`EVAL_TN` 130 被工具箱弹窗 200 压住 = 用户报的「被遮盖 / 无法拖拽」**同一个根因**）。
  ② **可拖拽 = 拖动柄必须是 Button**，并 `SetMovable(true)` + `RegisterForDrag("LeftButton")` + `RegisterForClicks("LeftButtonUp")` +
  `SetFrameLevel(窗口+1)`；`StartMoving` 用 warm-up 两步（Frame 的 `OnDragStart` 在本客户端不触发）。
  ③ **内部布局必须跟窗口宽度走**（按钮按宽度**居中**），不许写死 x —— 用户说「内部布局乱」十有八九就是窗口加宽后写死的坐标还留在原地。
  ④ 文案**由调用方给**：同一个通用弹窗被「物品名 / 数量 / 每次 / 指定目标」复用，标签写死就等于有一半用法文案是错的。
  ★判据读**真实控件**（`GetFrameLevel` / `GetDragRegistered` / `IsMovable` / 按钮的 `GetLeft` 与窗宽算中线）；
  ★★桩保真：`SetMovable/RegisterForDrag/RegisterForClicks/StartMoving` 都要能读回来，否则「能不能拖」这条判据根本无从下手。
- ★★★1.73.33 **「布局异常」的两种经典写法**（用户红线指出自动购买弹窗的列头与行尾）：
  ① **锚点偏移算错**：`SetPoint("TOPRIGHT", root, "TOPRIGHT", -x, …)` 里的 `x` 是**距右边**，而作者把「距左边」的数值填了进去
  → 列头跑到别的列上、两个列头**叠着画**（屏幕上是「启用每次称 总数」这种糊在一起的字）。
  ★正解 = **列几何单一来源**（一张表全用「距左边」表示、右对齐的列写右边缘），**列头与单元格都从它取**，
  并且**列头宽度 = 本列宽度**（否则盒子互相重叠、长文案串到隔壁列）。
  ★判据：列头右边缘 == 该列数据右边缘（±2px）+ 列头互不重叠（按 x 排序逐对比）——两条都读**真实控件**。
  ★★注意桩的坐标系：桩记录的是**锚点语义**（TOPRIGHT 的 x 是负偏移），读值口必须先换算成「距窗口左边」再比，
  否则左对齐/右对齐两种锚法根本没法放在一起比（1.73.33 实测：直接比会得到 -56 vs nil）。
  ② **「能不能拖」先问「有没有柄」**：拖动能力是**每个弹窗各自**的事（1.73.31 修好层级/鼠标 ≠ 能拖；柄是另加的东西）——
  规程 = Button 柄 + `SetMovable` + `RegisterForDrag("LeftButton")` + `RegisterForClicks("LeftButtonUp")` + level = 窗口+1 + warm-up 两步。
  ③ 说明文字的位置也是布局：用户要求「标题右侧的说明移到安全说明下面对齐」→ 判据 = **左边缘相同 + y 更低**（都读真控件）。
### 5.3 测试与断言
- ★★★1.72.4 **桩的「默认值」也是桩的一部分**：真客户端 `CreateFrame` 出来的帧**默认就是显示的**，而桩里写的是 `local shown = false` → 于是「没调 Hide 也断言 `IsShown()==false`」这类断言**恒真通过**：它不仅不检查，还**把「入口被藏起来」的真回归掩盖成绿灯**（1.72.4 实测：把「默认隐藏」写进代码后，去掉那两行 Hide 的变异竟然 SURVIVED；用户装上当场报「等级配置没显示」）。★判据：状态型桩错的往往不是「没状态」，而是**默认值反了**——桩建好后要**逐个默认值**与客户端对齐。连带 3 处测试的**隐式前置**（靠旧默认值碰巧成立）必须改成**显式建立**（`pcall(root.Show, root)` 并断言前置；重排走生产路径 `EVAL_WAR_TAB_REFRESH()`，不许靠 toggle 的副作用）。判据 = 组 110①⑧⑨ + 组 64/93 的显式前置；变异 M30（改回隐藏）/M32（桩退回假默认）都当场捕获。
- ★★1.72.4 **测试脚本够不着生产文件的 local**：`seUI` 是 `EvalHelp.lua` 的 local，测试里写 `seUI.rankW.btn:GetScript("OnEnter")` 读到的是 **nil**——断言看起来在验接线，其实**一个字段都没读到**。正解 = 加钩子 `EVAL_TEST_SE_RANK_TIP()` 走**真实 OnEnter**（`fn()` + 读桩记录的 tooltip 行）。★同类：写断言前先确认「这个名字在测试里真的解析到了东西」。
- ★★★**桩必须记住被测代码读的每一个状态**（焦点/纹理/位置与层/锚点语义/tooltip 行/切目标 `TEST.targetUnit`）；★**「桩有错状态」比「桩没状态」更隐蔽**（`newMock()` 漏写 `local x,y` → 所有对象**共享最后一次写入的位置**）。
- ★★★**桩对「无效调用」必须如实表现为无效**：`SpellStopCasting` 直调只置 `castStoppedDirect`、**只有 RunScript 排队才置 `castStopped`**，并断言「直调通道没被走到」——否则分辨不出直调/排队，核心修复**永远测不出来**。
- ★★★**「没执行」证明不了「没入队」** → 直接问队列（`EVAL_TB_TEST_QUEUED_QUESTS()`）；**断言里写死布局常量 = 测的是测试自己**（`swY=-389` 在生产改回 `-349` 时照样绿）→ 读生产导出的真值（`EVAL_TEST_CFG_LAYOUT()`）。
- ★★★**真实数据测不出换行/分列**（按钮串刚好放得下 → 删掉换行判断照样绿）→ 用**合成数据**入口（`EVAL_TEST_TPL_PLAN_FAKE`）把分支逼出来。
- ★★★**冗余防护的变异必须整组拆**（只拆一道、另一道仍会挡住 → 两处单拆都 SURVIVED，会把有效断言误判成无效）。
- ★★★1.73.28 **判据不许把语言包当期望值**（变异 M239 实测**存活**）：原来写 `want = { EVAL_L("TB_NAMEMENU_SAY"), ... }`，
  于是「把语言包里那条改掉」→ 菜单与期望值**一起变** → 断言照样绿（**在测自己**，本项目最恨的假绿）。
  ★正解 = 期望值写**字面**（用户点名的那几个词：「悄悄话/邀请/目标/公会邀请/复制名字/关闭」）——用户要的是屏幕上的词，
  判据就钉屏幕上的词；语言包只影响生产端，不参与判据。
- ★★★**变异锚点必须唯一定位到目标那一行**（`b:SetScript("OnClick",fn)` 有 6~7 处、`OnEnter` 6 处）→ **整行对齐**、**命中数必须 == 1**、CRLF 先摘 CR、**变异体本身必须语法合法**；★报 ANCHOR-MISS 时**先怀疑锚点**。
- ★★★**判「捕获」要同时看退出码与输出文本**（`: FAIL` 只覆盖源码检查，行为断言打 `ASSERT FAIL`；`execSync` 抛异常时正文在 **`e.stdout`**；`-Last 6` 会漏掉打在 **stderr** 上的 `LANG KEY CHECK` FAIL）。
- ★★**断言必须落在真实调用点/真实闭包/真实入口上**；**观测点必须配反向哨兵**、「删掉了」验「不在」、**写了钩子没人调用等于没有**；**模块级状态必须纳入 `EVAL_TB_TEST_RESET_TIMERS`**（放**文件末尾**，否则 DECL ORDER CHECK 抓 4 条 FAIL）；**判据要盯要保的那条性质本身**（「刷新次数 +1」而不是「数据对不对」）；**等价变异如实记录、未覆盖就说未覆盖**。
- ★★★1.73.5 **两条「弱判据」实录（本轮变异先存活、补强后才捕获 —— M65 / M67）**：
  ① **页码夹取会替断言把事做掉**——「改过滤词回第 1 页」在**命中只剩一页**时，`PAGE_ITEMS` 的越界夹取**自己就回到第 1 页** → 把 `IB.page = 1` 删掉照样绿；正解 = 用**改词后仍有多页**的词（`/Game/` 1018 枚 / `法术` 351 枚）先把页码推到第 2 页再改词（并把「先推到第 2 页」写成**前置断言**，M74 证明它真的挡得住）。
  ② **递归会被 `pcall` 吞掉**——「无条件回写输入框 → `SetText` 再触发 `OnTextChanged` → 递归」真会发生，但沿途 `pcall` 把递归错误吞了、刷新次数反而只剩 1 次 →「刷新次数没爆」这条断言**照样绿**；正解 = 让桩**计数**（`TEST.ebSetTextCalls`）再断言**次数有界**（实测 198 次 vs 有界 ≤2）。
- ★★1.73.5 **桩要模拟「EditBox 的 `SetText` 会再触发 `OnTextChanged`」**（真客户端行为，1.73.1 踩过）：旧桩不触发 → 「无条件回写」的变异**存活**、那条判据**永远验不到东西**；桩里到 50 层就 `error()`，免得测试卡死。★补上后顺带覆盖了 1.73.1 的 `EVAL_PH_SET_QUERY` 同款写法（全套测试仍全绿 = 没有别处犯这个错）。
- ★★★1.73.8 **变异脚本的「还原」必须来自运行前读入内存的原文 —— 绝不能 `git show HEAD:<file>`**：【实事故】本轮为了「还原得干净」用了 git 还原，而 1.73.8 的改动**还没提交** → 跑第一个变异就把 `IconBrowser.lua` + `EvalHelp.lua` 的改动**整段抹掉**（工作区被换成 HEAD 版本，只剩未纳入还原的 `test_assert.lua`），只能重做一遍。正解 = 开头把每个文件读进 `base`，每轮从 `base` 复制出 `work`、跑完把 `base` 写回。

### 5.4 UI 与布局
- ★★★1.73.28 **弹窗高度要「自适应内部条目」**（用户：「弹窗高度自适应内部项目」）：高度**由条目数算出来**
  （单一来源 `EVAL_TB_MENU_HEIGHT(条数)`，渲染处只调它），并且**条目本身按能力过滤**（没有「打开聊天框」接口就
  **不摆**「悄悄话」这条按了没用的项 → 条目少一行、高度跟着矮）。★判据不能只对「当前这一组」比数值：写死高度
  （恰好等于 6 条的公式值 100）照样绿 → 正解 = **换一组条目再比一次**（`EVAL_TEST_TB_MENU_DROP()` 强制重建 + 摘掉接口），
  断言「条目少一条 **且** 高度 = 新条数的公式值 **且** 确实变矮」（变异 M237/M238 靠这条抓）。
- ★★★1.73.25 **同一行的控件 y 必须「单一来源」**（用户报「自动购买的 [添加][清空] 与左侧名称没对齐」）：
  根因是标签 FontString 锚在 y-3、而行内按钮锚在 y → 差 3px（肉眼就是「按钮高半行」）。
  修法 = 两者共用同一个常量 TB_ROW_TXT_DY（横向不动）。★判据要读**真实控件顶边**（容差 1px）：M214 直接报出 6 个控件各差 3px。
  ★★**别用 FontString 的高度去算「中心」**：标签没有显式高度 → GetHeight 拿不到可靠值 → 判据把每行都跳过（**空跑**）却照样「绿」；
  本轮正是靠**反向哨兵**「这条判据必须真的量到 ≥2 个控件」当场抓到。
- ★★★1.73.26 **自绘 UI 的「风格」问题分两步走**（用户拿官方右键菜单截图问「能否保持官方风格」）：
  ① 先问**能不能借用官方件**（本例：把条目注入 `UnitPopupMenus` / `UnitPopupButtons` 那套官方菜单表）——
     但**必须先取证**（`/eh go 聊天 右键` 探针逐个报候选全局是否存在），不许凭印象假设它存在；
  ② 借用不成，就按用户给的**量化要求**做：半透明底（给出 alpha）、**宽度上限**（≤4 个汉字 = 62px）、条目 ≤4 字；
     ★并且**保留原有入口**（菜单里一条「官方菜单」把这次点击**原样转发**给客户端）——「我们加功能」不许以「吞掉既有行为」为代价。
  ★判据读**真实控件**（宽度 / `GetVertexColor` 的 alpha / 条目文字字节数）；★桩里没有 `GetVertexColor` 时
  「半透明」这类判据**读不到值**（本轮补桩后才成立）——「桩太宽松 → 断言失明」的又一例。
- ★★★1.73.3 **滚轮方向必须单一来源**（用户报「图标库的滚动方向和效果相反」）：6 处滚轮里只有图标库是反的（写成「d > 0 → 下一页」），其余 5 处都是「上滚 = 回到前面」（offset 减 / 上一页）。★★**真正的根因是断言写错了方向**：当时那条断言**用 -1 当「滚轮向上」**，与反向代码互相印证 → 反向 bug 被"验证"通过了（本项目最恨的「绿但真错」）。正解 = `Core.lua` 的 **`EVAL_WHEEL_DIR(a, b)`**：① 认 a / b / 全局 `arg1`（1.12 老写法）三种；② 非数字（可能是 self）判类型；③ **幅度归一成 ±1**（客户端给 ±120 时按原值位移会一次跳 120 行）。★判据 = 源码检查 **`WHEEL DIRECTION CHECK`**（6 处都必须走它 + 禁止「位移与方向同号」）+ 组 115（双向 + 到顶夹取）；变异 M52~M55 全捕获。★新增滚轮处理器的纪律：**用 helper、写双向断言**。
- ★★★1.73.1 **「按视图切换」必须把另一视图的控件整块隐藏**（用户截图「详情页信息错误」）：抓宠详情的搜索行从没被隐藏 → 标签 + 输入框里的检索词 + 详情标题**三层叠印**（被读成「宠物技能爪击 · 等级爪击」），[清除] 还压在 [返回] 上。★做法：把「同一行的控件」收成一个表（`PH.listRow`），刷新时按 `view` **整表 Show/Hide**——一个漏项就是一层叠印。判据 = 组 113②；变异 M42 捕获。
- ★★★1.73.1 **`Hide` 过的控件必须逐个 `Show`**（同一张截图里「宠物行只剩 ? 和 查」）：行池刷新把六个控件一起 `Hide`，随后**只 `Show` 了图标与放大镜** → 名字/元信息再没出现过。★这是本项目「显隐走显式清单、不靠父子传播」的**另一面**：清单里少写一个 Show 就是永久不显示。★★更毒的是**旧断言只读文本**（`SetText` 与显隐是两件事）→ 全绿出厂。判据 = 组 113③（读 `IsShown`）；变异 M40/M41 捕获。
- ★★1.73.1 **布局审查必须读真实矩形**（用户要求「严格审查布局错乱」）：把布局常量集中成单一来源，再断言**相对不变量**——列不相交（图标右端 ≤ 名字左端 ≤ 元信息左端 ≤ 放大镜左端）、行距一致、控件都在父行/窗口内、标题不压按钮。★不写死坐标值（那是「测测试自己」）：几何从 `EVAL_PH_TEST_GEOM()` 问真实控件要。实测两处真重叠：`detMeta` 宽 `W-260` 与 `detReq` 从 +300 起（重叠 100px）、计数文字宽 200 与 [清除]（右端 630 > 576）。判据 = 组 113④；变异 M43/M45b 捕获；★M45（只收窄元信息宽度）实测为**等价变异**（660/800 两档都不重叠），如实记录、不当成漏网。
- ★★1.73.1 **输入框：一个入口 + 回写要「比对后再写」**：改词这件事只允许走 `EVAL_PH_SET_QUERY`（`OnTextChanged` 也调它）；它不仅过滤，还**把视图退回列表**（否则「改了词还停在旧详情」，而空态提示是列表视图的控件 → 用户只看到一片空白）。★回写前必须 `GetText` 比对：本客户端 `SetText` 会再触发 `OnTextChanged`，无条件回写 = **递归**。
- ★★★1.72.4 **入口类控件永远不许藏**（用户当场否掉）：技能右侧的「等级」元素先前做成「没设等级就整块隐藏」，用户装上第一句话就是「技能右侧的等级配置没显示」= **功能等于不存在**。正解 = 元素**常显**，默认文案就是「**不限**」（这层文案自己表达「用技能本身、不指定等级」）★**用词是用户定的**：1.72.4 我按「默认值显示技能」自己改成了「技能」，用户当场改回「不限」——**别自己换用户的词**——★「隐藏」只配用在「这块信息此刻确实不存在」，**入口不许藏**；写在标题栏的提示（「右键技能名设等级」）救不了没有入口这件事（用户不会去读标题）。
- ★★1.72.4 **查不到 ≠ 没有（下拉版）**：法术书里读不到该技能的等级时，**如实说明**（`SE_RANK_NONE` 点名技能），**绝不弹只有一项的残废下拉**——用户看到「就一项」只会以为功能坏了。判据 = 组 110⑨（不弹面板 + 聊天有话说）。
- ★★★**「隐藏」= 不画，不是 `Hide()`**：EditBox 用 `Hide()` 后文字/底条**仍会被绘出**且层高于 `BACKGROUND` → 黑带；修法 = **不透明背板 + 控件挪出可视区**（`DD_SEARCH_PARK=-4000`；`alpha=0` 是混合）；判据随之改判「左边缘是否被挪走」。
- ★★★**锚点描述的是「邻居的哪条边」，不是「我想要哪个角」**：`mb.TOPRIGHT` 对 `Minimap.TOPLEFT` 看着像左上、实际贴左边缘，而小地图是**圆**的 → 要落圆外必须 `RIGHT` 对 `LEFT`。
- ★★★**分列切点 = 两列行数差最小**（遍历所有切点），**别用「塞到过半就停」的贪心**（25 条时 18/18，加 2 条就变 22/16）；**组是不拆的最小单位**；**版式抽成纯函数**（`tplFlowPlan`/`tplTwoColPlan`）= 位置的单一来源、渲染只读 plan；**组标题不许孤悬行尾**（★1.73.7 起这条**升级**成「标题独占一行」，见下一条）、**每组从新行开始**。
- ★★★**绝不静默截断**：行池 `DD_MAX_ROWS=96`，超出时**末行如实显示**「…… 还有 N 项未显示」；分享详情 `SH_DETAIL_MAX=6` 同理（详情用**逐个 FontString 按行**）。
- ★★**「面板按 N 列排版」≠「实际画得出 N 列」**（行池硬编 48 而菜单需 54 → 最后 6 行**静默丢弃** + 第 5 列全空）；**分列/换行不变量（读真实控件几何）**：按钮在**本列**列宽内（不是「窗内」）/ 同行留足 GAP（**同 y 的两列各自成行**）/ **组不跨列** / 两列都有内容 / 行数差 ≤2 / 右列起点 = 左列右边界 + 列间距 / 标题在本列行首。
- ★★★1.73.7 **「类别独立一行」= 标题行不许有按钮**（用户：「方案类别独立一行,方案同行多个.」）：版式从「标题 + 按钮同行流式」改成「**标题独占一行**（本列行首）+ 本组按钮从**下一行**起横向排、放不下自动换行」。★旧版式的毒点：续行**没有标题**（【通用法系】/【牧师】/【队伍/团队】的长组看着像**两个类别**，用户截图点名的就是这个）；★代价 = 每组多占一行 → 窗口高度自动变高（本窗高度一直是**算出来的**，不用手改常量；660×240 → **660×340**）。
  ★★**两处算法必须逐字一致，且要拿「自报值 vs 真实控件」钉住它**：`rowsOf`（算切点/高度）与摆放循环是同一件事的两份实现 —— 第一版 `rowsOf` **少算了「第一行按钮」**（标题已独占一行，第一个按钮就是新的一行），于是自报 6+7 行而真实是 11+13 行、切点跟着错。★更隐蔽的是**当时唯一关联的断言是弱判据**：`rowCount91 <= lines*2` 在 `13 <= 14` 下**照样成立** → 变异 **M82 存活**。正解 = 逐列数**真实控件**占用的行数（标题 + 按钮去重 y）必须 == 自报 `rowsL/rowsR`（真实与合成数据两条路各钉一条）→ M82 当场捕获。★新不变量还有：标题行**不许**有任何按钮（`hdrShared`）、按钮行必须从**本列左边界**起排（`rowStartBad`）、本组按钮必须在标题**下面**的行（`belowBad91`）；变异 M81~M84 全捕获。
- ★★★**新增「滚动 / 翻页 / 分页」控件的标准做法**（1.73.9 定型；已在跑的两处 = 图标库 + 工具箱）——
  用户前后两次提的是同一件事：「**放到最底部**、和 **[关闭] 同一行**、**右对齐关闭旁边**、**别重叠**」
  （1.73.8 原话「分页信息这行移动到底部和关闭同行.对齐关闭,别重叠」；1.73.9 原话「工具箱滚动样式参考图标库那边的滚动方式,
  然后放置在底部和关闭同行.右对齐关闭旁边」）。**新控件照抄这两处，不要再发明一套**：
  ① **形态** = 一行三段：`[状态/计数文字 …]` ←8px→ `[按钮组]` ←10px→ `[关闭]`；
     按钮一律**文字按钮**（语言包键：图标库 `IB_PREV/IB_NEXT/IB_RESCAN`、工具箱 `TB_UP/TB_DN`），
     **不用 ▲/▼ 字形**（那是 1.73.8 之前的旧样式，用户点名要参考图标库那种）。
  ② ★★★**几何只有一个来源 = `EVAL_HELP_CFG_BOTTOM()`**（EvalHelp 的**生产读值口**，交出 `midY/closeLeft/closeW/closeH/rowY/rowH/navX0`）。
     `CLOSE_MIDY/CLOSE_LEFT` 是 EvalHelp 的 local，**别的文件读不到**（本文件里 IconBrowser/Toolbox/DataSearch 都是独立模块）；
     各写一份 y 必然漂移。拿不到读值口就按关闭公式回退（`-(H-10-11)` / `W-12-64`），**绝不写死坐标**。
  ③ 按钮顶边 = `midY + 按钮高/2` —— ★**是中线对齐不是顶边对齐**，而各控件高不同（`ibBtn`=16→+8、`tbBtn`=15→+7.5）；
     文字格宽度 = `按钮组左端 − 8 − 左内边距`（**算出来**的，「不重叠」不是靠运气）。
  ④ **判据（读真实控件几何 × 生产关闭几何）**：中线 == 关闭中线 / 按钮组右端 `<=` 关闭左边缘 − 4 / 文字右端 `<=` 按钮组左端 − 2 /
     整行在**列表或网格下面** / 不再是 ▲▼ 字形 / 点**真实 OnClick** 仍能滚。读值口 = `EVAL_IB_TEST_BOTTOM()`（组 92）/ `EVAL_TB_TEST_SCROLL()`（组 118）。
  ⑤ ★★**「写死坐标」在本项目里测不出来**：写死 `-439` 在 660 宽下**照样全绿** → 必须配「写死 + 把**生产**关闭位置上移」的对照变异
     （M90 / M95）才能钉住「它真的在读单一来源」。变异 M86~M95 全捕获。★待统一：数据检索（Tab4）的 ▲/▼ 还是旧样式，照①②③改即可。
- ★★★1.73.15 **「多段一行」的居中：两段判据（生产数字验居中 + 真实控件验落地）**（用户：「「接收方案」开关在分享方案位置也添加一个方便快速关闭，然后三个位置居中对齐」）：
  收到分享时想不接收，原来要「关弹窗 → 开配置窗 → 找那个勾」三步 → 弹窗里加一个常驻勾选框，**当场能关**。
  ★它必须与配置窗那项是**同一个开关**（同一函数读写同一份真值）+ **弹出时刷新**（否则出现「配置窗显示关、弹窗还亮着」的自相矛盾）。
  ★判据两段：① **生产数字**验整组居中（左起点 == 窗口宽 − 左起点 − 整行宽；★别写成「W − 整行宽」，那差一个左起点——
  本轮测试第一版就写错、被断言当场抓出）；② **真实控件**验「这些数字真的落到了控件上」（[导入] 的真实 GetLeft == 左起点 + 勾选框段宽 + 缝）。
  ★标签宽度**实测优先**（GetStringWidth），拿不到才按**字符数**估（★string.len 是字节数）；
  ★**不要为量宽创建一个再 Hide 掉的幽灵 FontString** —— 本客户端 Hide 后仍可能被绘出（既有铁律），
  正解 = 建**真实**标签量宽后直接锚到勾选框右边。变异 M160~M164 全捕获（不居中 / 不写共用真值 / 不刷新 / and/or 陷阱 / 弹出不同步）。
- ★★★1.73.13 **「导出用 token、界面用本地化」= 同一份格式化 + 一个开关**（用户报「debuff 格式化是否没做好」）：
  编辑窗底部**预览**原来直接调导出用的格式化 → 界面上吐出英文 token `(Magic/Curse/Poison)`，而格子里明明写着「魔法/诅咒/毒」
  （同一个类型集合两种形态不一致 = 用户一眼看出没做好）。
  ★正解 = `EVAL_COND_STR(cd, disp)` / `EVAL_GROUP_STR(groups, disp)` 加一个 **disp 开关**：界面三条路（底部预览 / 配置窗方案行 / 行内预览）
  传 true → 走语言包 `DS_T_<ID>`（拿不到退回 loc 中文名、再退回 id）；**导出/往返一律 false → 英文 token，存量逐字不变**。
  ★★★**绝不复制第二份格式化**（复制 = 以后改一处忘一处）——所以是「同一函数 + 开关」，源码检查也钉着这一点。
  ★★**显示形态必须能解析回同一个集合**（`dispelNorm` 对 tok/loc 双向容忍）→ 用户把预览文字拷去导入也照样认；
  这条要用**往返断言**钉住（`EVAL_PARSE_CONDS(EVAL_GROUP_STR(g, true))` 解析回同一个 dt 集合）。
  ★★**断言要读真实 FontString**：预览是生产文件 EvalHelp.lua 的 local（`seUI.preview`），测试够不着 →
  加读值口 `EVAL_TEST_SE_PREVIEW()`，断言「预览行里有本地化名」**且**「不再出现英文 token」（反向哨兵）。
  ★判据 = 组 125（导出 token / 显示本地化 / 本地化往返 / 单选与空集 / 真实预览行）+ 源码检查 `DEBUFF DISPLAY CHECK`；
  变异 M149~M153 全捕获（显示不本地化 / 预览漏传 true / 导出被本地化 / 不传 disp / 方案行漏传）。
- ★★★1.73.10 **「角色名职业着色」轻量化配方**（用户：「参考 xguild 是否更轻量化」→ 落地为 工具箱 · 队伍/社交，默认开）：
  参考 `tmp/XGuild`（275 行）的**需求**，实现只有约 1/3 —— **一张描述表 + 一个 painter + 三个纯函数**。
  ★XGuild 的三个毛病（都在我们这边规避了）：① 公会/查询/好友三段几乎逐字重复；② 原函数备份存**全局**（`oldGuildStatus_Update` → 污染命名空间，与 `FRAME NAME CLASH` 同族）；③ 依赖本客户端**不存在**的 `GetDifficultyColor`（本机 `api_*.html` 全表 **0 命中**；只有 `Core.lua` 的垫片提供它）。
  ★做法：① 三窗口差异（按钮前缀 / 行数常量 / 翻页框 / 列后缀）全进 `TB_PAINT_LISTS`，加窗口只加一行；
  ② 颜色决策（职业色 / 等级难度色 / 同地图绿 / 离线减半 / 阶级插值）是**纯函数**，脱游戏可断言；
  ③ 包装全局刷新函数 = **先调原函数**再叠色 + **幂等守卫** + 备份存 **local**；④ 每处 `_G` / `SetTextColor` 都 pcall，窗口不存在就**整窗口跳过并记名**（`EVAL_TB_PAINT_STATE().missing`）。
  ★**开关关掉 = 不再叠色**（原函数会把颜色刷回客户端原本的配色），**不是**「停止刷新」；勾/取消勾后**立刻重刷**三个窗口（否则要等窗口自己刷新，用户以为开关没用）。
  ★判据 = 组 119 + 源码检查 **`PAINT WIRING CHECK`**（retry ≥2 处 / 三个刷新函数名都在描述表 / 备份必须是 local / **禁用 `hooksecurefunc`** / 有 `/eh go 着色` 诊断）；变异 M96~M103 全捕获。
  ★★**「拿不到就不猜」的实例**：who 窗口第三列（Variable）仅当**确知**当前排序维度是区域时才涂绿（`UIDropDownMenu_GetSelectedID` 不在本客户端 api 表里 → 返回 nil → **不涂**，而不是赌一把）。
- ★★★1.73.11 **工具箱两列版式**（用户：「工具箱分两列」）：16 项开关/设置按**组边界**切成左右两列。
  ★与分类模版窗同一套纪律：① 切点只在**组边界**上选（右列必须从组标题开头，否则某组的后半截甩到右列，「看着像少了一组」）；
  ② 切点 = 允许候选里**两列行数差最小**（组大小 5/5/6 时做不到 8/8 —— 所以判据要写「≤ 候选里的最优差」，不能写死 ≤2）；
  ③ 列宽 = (可用宽 − 列缝×(列数−1)) / 列数，**窗口太窄（列宽 < 200）自动退回单列**；④ 每页 = 列数 × 行数（16 条一页装下 → 计数行与翻页按钮自动隐藏；翻页按**整页**推进）。
  ★★**列不相交必须是几何断言**：行内每个控件都要**显式限宽**（`text`/`extra`/`hdr` —— 原来都是自动宽度），
  然后逐行验「在本列内 + 不越出本列右边缘」（组 120③）。★本轮两个真 bug 就是这条抓到的：
  **`hdr` 没限宽**（长标题按文字撑开压过列缝）、**左列不受 cut 约束**（同一条目在两列各出现一次）。
  ★★★**读值口绝不许复刻映射逻辑**：【实事故】`EVAL_TB_TEST_LAYOUT` 里把「槽位 → 条目」的映射**又算了一遍** →
  变异 M106（刷新里左列不受 cut 约束）**照样存活**：测试读到的是读值口那份「正确版本」，不是刷新真正用的那份。
  正解 = 刷新把**实际映射**记在行上（`r.item` / `r.pi`），读值口与 `[添加]` 查找都**只读**这两个字段（三处映射收成一处）。
  变异 M104~M109 全捕获（退回单列 / 切点不在组边界 / 左列不受 cut / 按钮按整窗定位 / 标签不限宽 / 每页按单列算）。
- ★★★1.73.12 **聊天窗名字着色**（用户：「聊天窗 内的名字能着色吗?需要走缓存?」）：在聊天打印入口**再叠一层** —— 把 `[名字]` 染成职业色。
  ★四条纪律：① **一个包装体管两个功能**（频道屏蔽 + 名字着色，`EVAL_TB_CHAN_INSTALL_ONE`），**绝不叠两层包装**；
  ② **覆盖所有聊天窗**（`DEFAULT_CHAT_FRAME` 与 `ChatFrame1` 常是**同一对象** → 幂等只能按「入口是不是我们挂的那层」判，**不能按名字去重**；
  2..7 号窗靠限频重试**补挂** —— 顺带修好「2 号窗以后照旧冒频道通知」）；
  ③ 缓存**单一来源**（`tbNameClass`，写入点唯一）：窗口上色时**白拿**一笔（`EVAL_TB_PAINT_ROW` 里 `tbNameClassPut`）+ 单位/名册**只读**采集
  （`EVAL_TB_NAMECLASS_HARVEST`，事件驱动 + 每类限频窗）；④ **不做自动 /who**（`SendWho`/`GuildRoster()`/`ShowFriends()` 都是向服务器发查询）
  → 查不到的名字**不上色**；源码检查 `CHAT COLOR WIRING CHECK` 把这条钉死（★**扫描前必须先摘行尾注释**，否则说明性注释会被当成违规）。
  ★★纯函数判据 `EVAL_TB_CHAT_COLOR_LINE`：认三种形态（`[名字]` / 行首「名字:」/ 方括号前缀之后），**拿不准就不碰**
  （未知名 / 单字名 / 已上色 / 物品链接里的同名一律原样）—— 「不碰」只是少一个功能，**弄坏人家聊天才是大事**。
  ★★★三个真坑：① **「已经在富文本里」不能看「往前 11 字节有没有 |c」** —— 物品链接 `|c..|Hitem:..|h[名字]|h|r` 里
  名字左边 11 字节内既没有 `|c` 也没有 `|H` → 会把**链接的显示名**染色（变异 M111 才暴露）；正解 = 看**最后一个未闭合**的 `|c`/`|H`
  （被 `|r`/`|h` 闭合过才算干净）。② **字符数不是字节数**：`string.len("甲") == 3` → 「单字名不写」的判据被 3 字节放过去（组 121① 当场抓到）→ 数 UTF-8 首字节。
  ③ 自己打印的行（`EVAL_SAY` 都带 `EVAL_HELP:` 前缀）**不进样本缓冲、也不参与着色**，否则 `/eh go 聊天` 每跑一次就把真实样本挤掉一批。
  ★判据 = 组 121 + 源码检查 `CHAT COLOR WIRING CHECK`；变异 M110~M119 **11/11 全捕获**（含 M112b「只关行为、保留源码文本」的对照，证明行为那道闸没被源码检查替挡）。
  ★★★**真机实测（用户截图）**：本客户端聊天行里的名字是**客户端自带的玩家链接 + 它自己的颜色码**：
  「｜cffff80ff｜Hplayer:Ionol｜h[Ionol]｜h｜r 悄悄地说: 1」→ 那条「已经在富文本里就不碰」的守卫会把**每一行**都放行
  （现象 = 用户报的「全都没染色」）。正解 = **改那段颜色码**（原位原长换掉，链接照样可点、不叠色）；
  链接前没有颜色码时把**整段链接**包进职业色。★**颜色码长度不许写死**：本客户端是 `|c` + **8 位** hex（aarrggbb），
  6 位 hex 也可能出现 → 用 `|c%x+` 抓下来按**实际长度**替换（写死 10 字节 → 8 位色码匹配不上，等于这条路根本没生效）。
  ★判据 = 组 121 ⑭（**物品链接的反向哨兵**：只认 `|Hplayer:`，`|Hitem:` 一律不碰）；变异 M124（去掉这条路）/M125（改成叠色）捕获。
  ★★**诊断要把三种「现象相同、修法完全不同」的原因分开打**：① 我们的包装**被顶掉**（逐框查「当前入口是不是我们挂的那层」=
  `EVAL_TB_CHATCOLOR_ROUTES`）；② 包装在位但**一条都没经过**（= 客户端不走 Lua 打印，Lua 层做不到）；
  ③ 收得到但一条都没认出来（= 判据/格式）。`/eh go 聊天` 同时打出**同层包装**（频道屏蔽）的经过/吞掉条数当旁证；
  变异 M126/M127 捕获。
  ★★★1.73.12 **未缓存角色的主动查询**（用户追加要求：「未缓存角色默认开启主动查询进缓存,设定个查询频率限制,
  做好查询不到结果的防止重复查询的机制.将关闭查询的开关在工具箱内设置,输出查询日志.归入调试日志」）——
  ★这是对先前「不做自动 /who」的**用户明确推翻**，按《频率防护总则》**四道闸门一起上**（缺一道就是白刷服务器）：
  ① **频率下限** `TB_WHO_GAP=5s`（一次 tick 只发一发，绝不连发）；② **单飞** `TB_WHO_PEND=8s`（上一发没结果绝不发下一发；
  超时也记负缓存，不会卡死在「等结果」上）；③ **负缓存** `TB_WHO_MISS_TTL=1800s`（查不到的名字期内**不再查** =
  用户要的「防止重复查询」）；④ **队列上限** `TB_WHO_QMAX=20`（满了**如实丢弃并记日志**）。
  ★★**查询日志只进调试日志**（`EVAL_LOGLINE` → `/eh logdump` / 存档），**绝不刷聊天框**（用户明确「归入调试日志」）；
  `/eh go 聊天` 顺带打印查询状态（开关/队列/在途/已发/查到/查不到/超时/丢 + 负缓存条数）与最近 3 条查询日志。
  ★★★**「查谁」是独立于「染谁」的第二套判据，而且必须更严格**：只认**发送者位置**的方括号名（紧跟冒号，
  或是本行第一个方括号段且其后先出现冒号）→ 方括号频道名 / 地名 / 物品名 / 纯数字**一律不查**
  （上色可以宽松，**查询是花服务器次数的，不许宽松**）。
  ★★**SendWho 只允许出现在限频滴出 tbWhoTick 里**（聊天热路径里直接发 = 一句话一发 = 必被反滥用）——已落成源码检查
  `CHAT COLOR WIRING CHECK`（SendWho 位置 + 四道闸门 + 入队口唯一）；变异 M128~M133d/M134/M135/M136b 全捕获
  （M136 是我故意放的**对照变异**：只在发送处加个无害标记 → 按预期 SURVIVED，用来确认「没变化就该存活」）。
  ★★教训：**变异体本身必须先过语法检查** —— 本轮一条 M133 把日志语句删成了半个表达式（语法非法）→ 报 CAPTURED，
  其实抓的是 LOAD ERROR、不是判据；补上 luacheck 前置后重跑才拿到真结论（M133~M133d 四发才都真的落在判据上）。
  ★**格式校准入口** `/eh go 聊天`：打印最近 12 条**原文** + 判据对它的判决 —— 客户端聊天行的真实形态我们**看不到源码**（本机没有 FrameXML），
  判据是按 ChatMOD（同代 1.12 插件，它按 `[名字]` 上色）反推的 → 用户一跑就能对照真相（铁律 4 的取证协议）。
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
- ★★★1.73.4 **本客户端的纹理路径是 Unreal 资产路径**：`/Game/Interface/Icons/<名字>_TEX` —— **不是** 1.12 的 `Interface\Icons\<名字>`。★写成 1.12 那种**不会"不画"，而是显示成引擎的「?」缺图占位**（用户截图里一屏问号就是这么来的；旧记忆写「写错什么都不画」是错的，已更正）。
  ★**宏图标表 = 唯一能把整表合法路径吐出来的官方入口**（`GetNumMacroIcons`/`GetMacroIconInfo`，"内置图标磁盘取不到"只对了一半）→ 新增 `/eh go icons` 采集进 `EVAL_HELP_CONFIG.iconDump`，/reload 落盘后取出 1018 条 → 落成 **`doc/图标路径清单.txt`**。
  ★★**这张清单现在是判据的一部分**：`PET ICON CHECK` 从「只守格式」升级为**真存在性校验**（逐条精确匹配清单 + 前缀/`_TEX` 后缀 + 技能间/家族间不撞图）；变异 M58（不存在的名字）/M59（退回老路径）/M60（家族撞图）/M61（少 `_TEX`）全捕获。★要换/加图标：从清单里挑 → 只改 `gen_petdata.js` 的 `SKILL_ICON`/`FAM_ICON` 两张表 → 重生成（该生成器逐字复现 `PetData.lua`，可直接重跑）。
  ★宠物家族用客户端自带的一整套 `Ability_Hunter_Pet_*`（狼/猫/熊/野猪/蟹/龟/鳄/蝙蝠/秃鹫/枭/猩猩/风蛇/蝎/陆行鸟/蜘蛛），**一族一枚不撞图**。
- ★★★1.73.5 **图标语义表（`IconSem.lua`：名称 + 多标签）+ 图标库关键字过滤**（用户：「对存储下来的图标路径进行语义识别,对应一个名称,语义tag 一个图标可以设置多个,比如爪子…然后再图标库内加个输入过滤根据名称/路径进行筛选」）：
  ① **数据** = `gen_iconsem.js` 从 `doc/图标路径清单.txt` 生成 `EVAL_ICON_SEM = { ["<基础名>"] = "名称|标签1/标签2/…" }`（1018 条、**823 条有中文名**，认不出的**如实退回英文基础名**，不编）；生成物独立成文件 = 单一真值（搬进 UI 就是第二份名单）。
  ② ★★★**基础名必须剥 `_TEX`**：客户端给的是 `/Game/Interface/Icons/INV_Misc_MonsterClaw_03_TEX` —— 不剥后缀，语义表的 key **一个都对不上** → 全部退回英文名、中文过滤全废，**而且一声不响**（1.73.4「路径形态」坑的翻版）。判据 = 组 117①b（拿**真实路径形态**直接断言）；变异 M62 当场捕获。
  ③ **过滤 = 四种命中**（语义名 / 标签 / 原始基础名 / 完整路径，大小写不敏感）+ 与分组**叠加**（先分组再关键字、先过滤再切页）；改词走**唯一入口** `EVAL_IB_SET_QUERY`（回第 1 页 + `GetText` **比对后**才回写）；空匹配**如实点名**（不是一片空白）。
  ④ ★★**「叠加」的判据不能只比数量大小**：`nInv <= nAll` 在把分组判定整段删掉时**照样成立** → 必须查**命中项各自的 group**（新增读值口 `EVAL_IB_TEST_MATCH_GROUPS`）+ 一个必然为 0 的反向分组（药水在 inv 有、在 ability 必须 0）。
  ⑤ 测试素材用**真实形态**：`test_engine.js` 把整份清单注入 Lua（`TEST_ICON_FIXTURE`），桩对「已是完整路径」的表项**原样返回**（否则桩永远只喂 1.12 老形态，_TEX 这类错照不到）。
- ★★★1.73.6 **「判据的覆盖面」要跟着文件走 + 正则要按「源码转义」写**（用户：「换成 放大镜图标」）：
  ① **实事故**：抓宠详情页右侧那枚按钮贴的是 `Interface\Icons\INV_Misc_Spyglass_02` —— **两处都错**（1.12 老前缀 + 客户端里根本没有 `_02`，清单只列了 `_01`）→ 真机只剩引擎「?」缺图占位，用户看到的就一直是**露在外面的保底文字「查」**。
  ② **为什么 1.73.4 换图标时漏了它**：`PET ICON CHECK` 当时**只扫 PetData.lua 的 `icon = "…"`** —— 这行是 PetHelper.lua 里的 `local … = "…"`，**从未被任何检查看过**（又一次「检查存在 ≠ 覆盖到位」）。已扩到 PetHelper.lua：**任何**客户端纹理字面量都必须精确在白名单里。
  ③ ★★**第二坑（同类、更隐蔽）**：Lua 源文件里写的是**转义过的** `"Interface\\Icons\\X"`（两个反斜杠）——检查器第一版正则按**一个**反斜杠写 → 老形态**永远匹配不到**，那条「LEGACY」判据**其实是死的**（变异 M75 被「一个纹理都没扫到」的守卫挡下，看着像捕获、其实走的是另一条路）。正解 = 正则匹配两个反斜杠 + 取出来 `unesc` 还原再比对；★并保留「扫不到任何纹理 = FAIL」的守卫（变异 M80 捕获）。
  ④ 判据 = 组 112（读**真控件上的纹理** == 清单里那枚 + 反向哨兵「不再是 1.12 形态」+ 保底文字 `IsShown == false` + 图标 16px）；变异 M75~M80 全捕获。★图标本体改由**显式 Hide 文字**实现（`L("PH_ZOOM")` 仍「在用」，不会再出现「图标没画出来只剩文字」这种半吊子状态）。
- ★★**本机 `api_*.html` 只有函数索引（1370 条）、没有事件列表** → 事件类问题只能两套都注册或 `/eh go probe` 取证；宏图标表 `GetNumMacroIcons`/`GetMacroIconInfo` 给的是**路径**、整套打包在 `Content\Paks`（磁盘取不到）、**纹理不用写进 .toc**；★（**已更正**：纹理路径写错不是"什么都不画"，而是显示成引擎的「?」缺图占位——见本节 1.73.4 条；路径一律从 `doc/图标路径清单.txt` 挑，并由 `PET ICON CHECK` 逐条核对。）
  ★★**1.73.10 实测**：这些页是客户端函数的**名字索引**（name + category + 官方 wiki URL）——「有没有这个函数」可查、签名语义仍要看 URL。**0 命中 = 本客户端没有**：`GetDifficultyColor`（所以我们才有垫片）、`PlaySoundFile`（只有 `PlaySound`）、`hooksecurefunc`、`UIDropDownMenu_GetSelectedID`（FrameXML 里没有）；**有**：`GetGuildRosterInfo`/`GetWhoInfo`/`GetFriendInfo`/`GetNumGuildMembers`/`GetNumWhoResults`/`GetNumFriends`/`GuildControlGetNumRanks`/`GetRealZoneText`/`RemoveChatWindowMessages`（category=ChatWindow → 「按消息组屏蔽」这条官方路是存在的，待办 = 先把真实消息组名打出来）。

### 5.6 内容 / 数据质量
- ★★★1.73.2 **「可驱散类型」多选 = 一个字段三种形态，读侧归一**（用户：「debuff 类型检测 包括团队debuff 类型要支持多选」）：`cd.dt` 可以是 `nil/""/"any"`（任意）、**字符串**（单选 = **存量数据的原样**）、**集合表**（多选，命中任一即算命中）。★**空集 = 任意**（与 nil 同义）——反过来写成「永不命中」是最容易犯的语义错。★文本形态：多选 `(Magic/Poison)`、**单选仍是 `(Magic)`**（老配置导出逐字不变，配反向哨兵）；导入按斜杠拆，顿号/逗号也认（手写宽松）。★改动点只在 `dispelMatch` + 导出/解析三处 → 自身/目标/队友/团员/候选者/选取器**一处生效全部生效**（这就是把判定收在一个函数里的价值）。判据 = 组 114；变异 M46/M47/M50 捕获。
- ★★1.73.2 **多选下拉要「互斥项」时，勾选状态必须由数据重算 + 整表重绘**：类型面板里「任意负面」与具体类型互斥，但 `EVAL_DD_OPEN` 的多选面板**只重画被点的那一行**——不重算就会留着两处勾（先勾「任意」再勾「魔法」）。做法：回调里从 `cd.dt` 重建集合 → 写回 → `EVAL_DD_SYNC(selOf(cd.dt))` 整表重绘。★窄格（62px）列不下就列 2 项 + …，**完整清单走悬停**（不因为格子窄就藏信息）。判据 = 组 114③；变异 M49（去掉互斥重绘）/M48（退回单选）/M51（格子只显示第一项）捕获。
- ★★★1.72.4 **「指定等级」的交换格式 = `技能名(等级 3)`**（与官方 CastSpellByName 同形，括号内必须与**法术书 subtext 逐字相符**）：导出/导入/分享/模版**共用同一条文本通道**，`!` 先剥离再拆括号 → 老文本（无括号）行为一字不变。★**跨语言不通用**（等级3/Rank 3/Ранг 3 是每语言文本）→ 对方法术书没有该串时**如实失败**，绝不退化成「无等级乱放」。★**只有真法术名才拆**：带前缀的特殊技能名（物品:/宠物:/姿态:/跟随:/选取目标:）里的括号属于名字本身（「物品:治疗药水(大)」「跟随:某人(等级 2)」）→ 拆了就是**静默改义**（守卫在 `EVAL_PROFILE_FROM_TEXT`）。判据 = 组 111（27 个模版 0 等级 + 通道幂等 + 前缀名不拆 + 分享自称判据 + UI 不误报）；变异 M21/M25 捕获。★**下拉顺序 = 按等级数字升序**（用户要求「从低到高」）：法术书枚举出来的顺序是乱的，**必须按数字比**（字符串序会把「等级 10」排到「等级 3」前面——最容易写错的那种排序）；无数字的 subtext（如「变形」）排最后；`table.sort` 在 5.1 **不稳定** → 用「数字 + 原始下标」装饰排序。判据 = 组 108①b + 组 110②；变异 M34（去掉排序）/M35（改字符串序）/M36（无数字排最前）全捕获。
- ★★★1.72.4 **「不占动作条也合法」只能有一个判据**（`skillNoSlotOk(skill, rank)`，Engine.lua 导出 `EVAL_NO_SLOT_OK`）：名单原被抄了**三份**（引擎闸门/亮金白名单/「缺技能?」白名单）→ 新增「指定等级」时只改一处，战斗信息UI 就把**本来放得出来的技能**标成「?」+ 变灰（假告警）。判据 = 源码检查 `STOP ATTACK WIRING CHECK`（名单 7/7 + 被接线 ≥3 处）+ 组 111⑤（读真实控件文字）；变异 M22 捕获。
- ★★★1.72.4 审计查出的**既有数据缺口**：`CLASS_LIST` 里**根本没有圣骑士** → 模版 7 处 `[职业:圣骑士]` 一直被**静默丢弃**（名单少一个人 = 那个人永远不被选中，不报错）。修法 = 追加 `{ id="PALADIN", name="圣骑士" }`（★**必须追加末尾**：职业下拉行号按本表下标一一对应）；原组 2 用「圣骑士」当**非法职业样本**，其实是在替这个缺口作证 → 样本改「死亡骑士」。判据 = 组 111⑥（模版职业名必须都在 CLASS_LIST）+ 组 2 新断言；变异 M23 捕获。
- ★★★**模版四条体检**：名字非空 / 同组不重名 / 首行 `# 方案: X` **等于**模版名 / 至少 1 条技能行；并点名检查用户要的那几条在。
- ★★★**「职业过滤」必须同时支持候选者条件**（解析白名单 + 导出 `teamFilterSuffix` + 编辑器格**三处一起**放开）→ **新能力要沿「数据能到的地方」全打通**（解析/导出/UI/求值）；**过滤作用点分两处**：单条条件按**它自己的** `cs`/`gs` 收窄（`teamFilterList(list, cd)`）、**选取器行**按行内条件的**并集**收窄候选（`teamFilterList(list, nil, rule)`）——这才是「挑一个法师」。
- ★★★**「成员过滤」空集 = 不过滤**（不选 = 全部），与**「目标职业」空 = 永不满足**正好相反 → 不共用判据也不共用文案；**成员类条件必须写在一行的最前面**（它负责**扫人 + 切目标**；写在后面 = 后面的条件拿「切之前的目标」求值，静默出错）。
- ★★★**拆数据文件 = 一处真值变两处同步**（磁盘 + .toc），漏任一处都**静默**；`EXAMPLES TOC CHECK` 四条（双向一致 missing/ghost、toc 顺序=选单顺序、数据不许搬回生产文件、examples 排在 `EvalHelp.lua` 之后）；★**新增被装载的数据文件时，装载表本身就是测试的一部分**（1.71.4 漏加 5 个文件 → 新模版一条没被测，`getn(EVAL_IO_TEMPLATES)==6` 照样绿）。
- ★★★**改名只改显示名、id 一律不动**（存量方案/导出/解析不受影响）；显示名真源是语言包 `CT_<UPPER(id)>`，`SE_TYPES[i].name` 只是副本 → **两处都改、三语言同改**。
- ★★**文本往返走单一通道**（`EVAL_PARSE_ONE` 剥 / `teamFilterSuffix` 写）；**空集不写** → 老配置导出**逐字不变**；非队伍/团员类型带后缀 = 写法错误 → **如实丢弃**。
- ★★**菜单标签是运行时拼键** → 静态 `LANG KEY CHECK` 扫不到 → 必须配「**逐语言**菜单无重名/无缺键」断言（只跑一种语言时另一种永远是盲区）；★改名时顺手核三语言白捡一个真 bug（enUS/ruRU 两条原本同串）；`tips`/图标表必须用**下标赋值**填充（`table.insert(t,nil)` 是 **no-op**）。
- ★★★1.72.2 **光环判定 = 两级解析 + 三态**：① 纹理快路径（学习表 > 动作条——动作条图标只是**代理**，增益条上亲自观察到的才是**权威**）；② **名字慢路径**（`auraNameHit` 工具读名，0.5s 缓存，命中即 `learnAuraTex` 自愈回快路径）；③ **两条都不可用才如实失败**（1.71.2 铁律：查不到 ≠ 没有）。
- ★★★1.72.2 **旧版的死接线（分享方案事故）**：六个光环分支写成「纹理解析不出就先 return」→ 按名字兜底**只在纹理已知时才到达**，恰是最不需要它的时候；而**分享出去的方案在别人角色上**纹理必然为空（`debuffTex` 是**每角色**表，目标身上的 debuff 又不是对方动作条技能）→ 条件恒假、技能永远不放（用户实测：十字军圣印/正义圣印跳过）。
- ★★★1.72.2 **扫描可信度**：provider 第二返回 = 「每个看到的光环槽都读到了名字」；`auraNameHit` 因此是**三态**：true=命中（永远可信）/ false=**扫描干净**且确实没有 / nil=不可信→调用方如实失败。★把 nil 当 false 就是复活 1.71.2 的无限重放（变异 M2 被组 70 抓住）；★把「纹理未知」直接当失败就是死接线（变异 M1/M3 被组 70③/103① 抓住）。
- ★实机诊断（1.72.2 新命令）：`/eh go tex`（看学习表）/ `/eh go texdel 名字`（大小写不敏感；**删完下次判定会自动扫描并学回来**——验「自动扫描」的入口）/ `/eh go texclear` / `/eh go texscan`（四类光环 + **本次扫描是否可信**）。
- ★★**测试桩此前没有 `SlashCmdList`**（插件把整条 `/eh` 命令链包在 `if type(SlashCmdList)=="table"` 里）→ 所有斜杠命令**零覆盖**；1.72.2 已补桩 + 组 104。

### 5.7 流程与纪律
- ★★★1.72.2 **载入提示与新手引导必须「每次加载」都打**（用户截图指出：只出了「✅ 已加载成功 + 一行提示」，四步引导缺失）。
  ★旧实现用 `cfg.guideSeen` 做成「只在人生第一局出一次」→ 新人没盯第一局的聊天框就**再也看不到**（该键现已废弃、不再读写）。
  判据 = 组 105：触发 `VARIABLES_LOADED` 两次，**第二次（/reload 语义）仍须打出引导标题与步骤**；
  变异 M5（把 `if not cfg.guideSeen` 的门加回来）→ 组 105 当场炸。★另：`/eh guide` 随时可重看这条路也要在。
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
- **文件结构（1.39.0 起模块化，不是单文件）**：`EvalHelp.toc` + `Locales/{zhCN,enUS,ruRU}.lua` + `Core.lua`（输出/i18n/状态采集）+ `Engine.lua`（规则引擎）+ `EvalHelp.lua`（UI/斜杠命令/init）+ `Toolbox.lua`（工具箱 Tab3）+ `DataSearch.lua`（数据检索 Tab4）+ `Share.lua`（方案分享，1.71.0）+ `IconBrowser.lua`（图标库 Tab5）+ `PetData.lua`/`PetHelper.lua`（抓宠 Tab6，1.73.0）+ `IconSem.lua`（**图标语义表**，1.73.5）+ `examples/*.lua`（**11 个数据文件**）；文档 `README.md`/`README_en.md`/`README_ru.md`/`CHANGELOG.md`/`DEVELOPMENT.md`/`CLAUDE.md`；测试 `luacheck.js`/`test_engine.js`/`test_stub.lua`/`test_assert.lua`。**行数随开发变化，别当固定值引用**。
- ★**toc 载入顺序（以 `EvalHelp.toc` 为唯一真值）**：`Locales/{zhCN,enUS,ruRU}` → `Core` → `Engine` → `EvalHelp` → **`examples/*`（11 个数据文件，必须排在 EvalHelp.lua 之后）** → `Toolbox` → `DataSearch` → `Share` → **`IconSem`** → `IconBrowser` → `PetData` → `PetHelper`（★`EXAMPLES TOC CHECK` 守着「磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序」；`IconSem` 必须在 `IconBrowser` **之前**——后者读它的 `EVAL_ICON_SEM`）。
- ★**新增 .lua 模块要同时改三处**：`EvalHelp.toc` 载入列表、`test_engine.js` 的加载数组（**6 处清单**：DECL ORDER / LANG KEY / COMMENT SWALLOW / EXAMPLES TOC / FRAME NAME CLASH / 主加载循环 —— 漏一处就是那一类检查的盲区，本项目踩过）、`DECL ORDER CHECK` 的文件清单（**目前 10 个**：EvalHelp/Core/Engine/Toolbox/DataSearch/Share/IconSem/IconBrowser/PetData/PetHelper）。★1.73.5 实事故：新增 `IconSem.lua` 后**主加载循环**漏加 → `EVAL_ICON_SEM` 在测试里是 nil，图标库语义/过滤整组断言**全红**（这正是「检查存在 ≠ 覆盖到位」）。
- ★**案例模版数据文件（1.71.2 新增 `examples/*.lua`）只需改两处**：`EvalHelp.toc` + `test_engine.js` 加载数组（它们没有顶层 local，故不进 DECL ORDER 清单）。
- **当前版本**：**1.73.0**（头条 = **抓宠帮手（配置窗第 6 个 Tab）**：
  ① **数据** `PetData.lua` 独立载入（21 技能 = 13 主动 + 8 训练师被动，106 条「技能×等级」，280 条驯服来源）；
     来源 = 用户提供的宠物技能总表截图（`doc/pet_info.png`）逐行转录 → `doc/宠物技能数据.md`；
  ② **图标**：1.73.0 先用占位 → **1.73.4 已全部换成客户端真实路径**（`/Game/Interface/Icons/<名>_TEX`，21 技能 + 16 家族各一枚不撞图）；
     `PET ICON CHECK` 也随之上台阶：从「只守格式」变成**逐条精确匹配 `doc/图标路径清单.txt`**（真存在性校验）；
  ③ **检索**：顶部输入框即时过滤（纯本地数据，无需去抖），列表列出**各等级**；支持按**技能名**或**野兽名/区域**两种搜法；
  ④ **详情页**：简介 / 集中·施法·射程·冷却 / 需求宠物等级 / 拥有该技能的宠物列表（家族 + 名称 + 等级·区域）；训练师被动技能如实注明「无驯服来源」；
  ⑤ **放大镜跳转**：宠物行右侧按钮 → 填入宠物名 → 切「数据检索」Tab 并立即检索（新增 `EVAL_DS_SEARCH_NAME` 入口 + `EVAL_DS_LAST_QUERY` 读值口）；
- **在途（已本地提交、尚未发布/推送；用户实测通过后才进 release）**：
  **1.73.1** 抓宠详情页两处真 bug（搜索行整块没隐藏 = 三层叠印 / Hide 过的控件没逐个 Show）+ 布局审查改成几何断言 →
  **1.73.2** debuff 可驱散类型**多选**（含队友/团员）→ **1.73.3** 滚轮方向收成单一来源 `EVAL_WHEEL_DIR` + `/eh go icons` 图标路径采集 →
  **1.73.4** 抓宠图标全部换成客户端真实路径 → **1.73.5** 图标**语义表**（名称 + 多标签）+ 图标库**关键字过滤**（按语义名/标签/原始名/路径）→
  **1.73.6** 抓宠详情页的「查」换成**真·放大镜图标**（原路径 1.12 老形态 + 名称不存在）+ `PET ICON CHECK` 扩面到 PetHelper.lua。
  **1.73.7** 案例模版窗改成「**方案类别独立一行 + 方案同行多个**」（标题独占一行，方案从下一行横向排）。
  **1.73.8** 图标库的分页信息 + 翻页按钮挪到**与 [关闭] 同一行**（中线对齐、不重叠）。
  **1.73.9** 工具箱的滚动控件照同一条挪到底部行（[上翻][下翻] 文字按钮 + 计数文字，右对齐停在 [关闭] 旁）。
  **1.73.10** 工具箱新增**角色名职业着色**（公会/查询/好友三窗口；参考 tmp/XGuild 轻量化重写，默认开）。
  **1.73.11** 工具箱改成**两列**（组边界切分 + 列不相交的几何断言 + 窄窗自动退回单列）。
  **1.73.12** 聊天窗名字**按职业色**着色（缓存单一来源 + 白拿/只读采集、拿不准不碰、不做自动 /who、一个包装体管两个功能且覆盖 ChatFrame1~7、`/eh go 聊天` 当格式校准入口）。
  **1.73.13** debuff 类型显示**本地化**（界面走本地化名、导出仍走 token；同一份格式化 + disp 开关；本地化形态能解析回同一集合）。
  **1.73.14** 修「开启战斗UI 后物品 tooltip 几秒自动消失」：读数口不再借用真实 GameTooltip，改自建隐形 tooltip（+退化守卫、`/eh go wtt`）。
  新增断言组 106 + 既有「Tab 数 = 5」同步改 6；★本轮踩的坑：**生成器补丁插在输出之后**（数据没进文件，条目数 58≠106 当场暴露）、
     **PetHelper 的 PH 表漏了行池字段**（`PH.rows` 为 nil → 配置窗构建即红字）、**DataSearch 新入口定义在 `dsDoSearch` 之前**（DECL ORDER CHECK 抓住）。
  - 上一版 **1.72.2**（分享方案光环修复 + 载入引导每次都在）：
  ① **分享出去的方案在别人角色上放不出技能** → 根因是六个光环分支「纹理解析不出就先 return」，**按名字扫描的兜底永远到不了**；
  改成**两级解析**（纹理快路径 → 名字慢路径，0.5s 缓存、命中即自愈学习）+ **扫描可信度三态**（不可信就如实失败，防复活 1.71.2 无限重放）；
  ② **新手引导改成每次加载都打**（原来用 `cfg.guideSeen` 只出一次，新人错过第一局就再也看不到，该键已废弃）；
  ③ 顺带修 `EVAL_DS_HUD` 具名帧顶掉同名全局函数 → `/eh ds hud` 静默失效（HUD 开得开、关不掉）；
  新增诊断命令 `/eh go tex | texdel 名字 | texclear | texscan`、源码检查 `FRAME NAME CLASH CHECK`、断言组 103/104/105（变异 M1~M6 全捕获）；
  三语言 README 与 CHANGELOG 同步（版本表 10 行、里程碑范围 1.72.2）；
  ★**已推送**（origin + github 两端 + tag v1.72.2）。
  ① **分享出去的方案在别人角色上放不出技能** → 根因是六个光环分支「纹理解析不出就先 return」，**按名字扫描的兜底永远到不了**；
  改成**两级解析**（纹理快路径 → 名字慢路径，0.5s 缓存、命中即自愈学习）+ **扫描可信度三态**（不可信就如实失败，防复活 1.71.2 无限重放）；
  ② **新手引导改成每次加载都打**（原来用 `cfg.guideSeen` 只出一次，新人错过第一局就再也看不到，该键已废弃）；
  ③ 顺带修 `EVAL_DS_HUD` 具名帧顶掉同名全局函数 → `/eh ds hud` 静默失效（HUD 开得开、关不掉）；
  新增诊断命令 `/eh go tex | texdel 名字 | texclear | texscan`、源码检查 `FRAME NAME CLASH CHECK`、断言组 103/104/105（变异 M1~M6 全捕获）；
  三语言 README 与 CHANGELOG 同步（版本表 10 行、里程碑范围 1.72.2）；
  ★**已推送**（origin + github 两端 + tag v1.72.2）。
  - 上一版 **1.72.1**（**新手上路友好化**：加载成功提示 + 四步新手指引——绑键首选「右键方案 → 方案管理 → 快捷键 → [保存]」、宏降备选；入口三处：自动播报 / 配置窗 [使用引导] / `/eh guide`）；
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

1. **1.72.2** — 🔍 **分享方案光环修复 + 载入引导每次都在**：六个光环分支的早退让「按名字扫描」兜底**永远到不了**（别人角色没学过 debuff 纹理 → 条件恒假、技能不放）→ 改成**两级解析 + 三态**（命中可信 / 扫描干净才敢说「没有」/ 否则如实失败）+ `/eh go tex*` 诊断命令；引导改成每次加载都打；顺手修掉具名帧与同名全局函数冲突导致 `/eh ds hud` 静默失效（新增 `FRAME NAME CLASH CHECK`）。

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
