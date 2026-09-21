# EVAL_HELP 记忆体 · 参考卷（CLAUDE_REFERENCE.md）

> 本文件是 `CLAUDE.md` 的**参考卷**：**不自动载入**（因此不占工作区指令预算），需要时由 AI 主动 `read`。
> 内容 = 发布 release 流程（9 步 + 打包脚本 + 推送信息） · §六 历史教训 · §七 开源仓库/官方文档/待开发 · §八 项目位置与现状 · §九 版本要点。
> ★任务涉及「发布 release / 项目位置 / 当前版本 / 工作流纪律 / 官方 API 文档 / 待开发计划 / 历史教训 / 某版本要点」时必须打开本文件。

## 发布 release 流程（9 步全文 + 打包脚本 + 推送信息）

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
# ★只装运行必需：.toc + 10 个顶层 .lua 模块 + **tools/ 子目录模块**（HunterHelper.lua）+ Locales + examples + media
#   + 三语言 README/CHANGELOG/DEVELOPMENT
# ★★1.74.5 教训：模块放进**子目录**后，PACK LIST CHECK 的旧判据只看「顶层 .lua」→ 本地测试全绿、出包却缺文件
#   （用户装了直接报错）。现有判据已扩成「toc 里带路径的 .lua：要么逐个列出、要么所在目录被整目录拷」。
# ★★清单必须**跟着 EvalHelp.toc 走**（下面的模块名与基准数由源码检查 PACK LIST CHECK 守着，改漏一处当场 FAIL）
Copy-Item "$src\EvalHelp.toc","$src\Core.lua","$src\Engine.lua","$src\EvalHelp.lua","$src\Toolbox.lua","$src\DataSearch.lua","$src\Share.lua","$src\IconSem.lua","$src\IconBrowser.lua","$src\PetData.lua","$src\PetHelper.lua" "$staging\EvalHelp\"
Copy-Item "$src\README.md","$src\README_en.md","$src\README_ru.md","$src\CHANGELOG.md","$src\DEVELOPMENT.md" "$staging\EvalHelp\"
Copy-Item "$src\Locales","$src\examples","$src\media","$src\tools" "$staging\EvalHelp\" -Recurse
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.74.28 基准 = **69 个**（+`tools/RareWatch.lua`）；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`，1.74.27 加 `tools/RareWatch.lua`）：
  少一个就是缺文件，用户装了会**直接报错**。
  ★这一条与上面的模块清单都有源码检查 `PACK LIST CHECK` 守着（清单与 .toc 逐个比对 + 基准数按打包口径现算），过时当场 FAIL。
★**不装**：`luacheck.js`/`test_*.lua`/`test_engine.js`（测试）、`preview/`（截图）、`node_modules/`、
`api_*.html`、`.git/`、`bindings/`、`_icons_scan/`、`pay/`。

**推送信息**：分支 `master`；远端 `origin`=gitee（`git@gitee.com:xeval/emberveil_eval_help.git`）、`github`=`git@github.com:lihaibo123as/emberveil_eval_help.git`（1.29.0 起双远程，每次**两端都推**：`git push origin master && git push github master`；本地仓库 = 插件目录本身）；★推送用**默认密钥 `~/.ssh/id_rsa`**（`gitee_id_rsa` 未被授权，别用 `-i` 指定它）。
★★**两个库一律走 SSH（`git@xxx` 形式）+ 本机默认密钥** —— 用户 1.72.0 明确：「发布两个库，记住都走 git@xxx 本地密钥形式」。
即：**不用 HTTPS、不用 token、不用 `-i` 另指密钥**；推送前先 `git remote -v` 核一眼**两个远端都是 `git@`**，
再用 `ssh -T git@github.com` / `ssh -T git@gitee.com` 双端验签（1.72.0 实测：GitHub `Hi lihaibo123as!`、Gitee `Hi eval(@xeval)!`）。
★两个远端名固定：**`origin` = gitee**、**`github` = github**。



## 六、历史教训汇总（1.70.0 ~ 1.70.36，按主题；不再逐版本）

### A. Lua `local` 作用域（累计 13 次，头号杀手）
- 作用域是**词法**的：引用点写在 `local` 声明**之前** → 那个名字**永远是全局**，与运行时调用顺序无关；防法 = 导出函数物理定义在被引用者之后 + `DECL ORDER CHECK` 自动扫。
- ★★**合并冲突在 Lua 里不报错（1.71.1）**：两分支给**同一个全局**赋值 → 后赋值者**静默获胜**（实测：测试桩的富版 `GetNumPartyMembers` 被简版盖掉 → 队伍扫描只扫到自己，组 66 `got=1 want=3`）。语法检查与单文件审查**都看不出来**，只有**跑测试**能发现；`git diff` 里同一函数名出现两次要立刻当错误。
- 不得不提前引用时用**前置声明** `local f`（**无 `=`**）+ 实现处 `function f(...)`（**不带 `local`**）。
- ★检查器盲区：看不见「无 `=` 的前置声明」与 CRLF 的 CR；且按**名字**判定 → 「A 函数里是 local、B 函数里当全局用」看不见（1.70.47 `texOf` 就这样漏掉，表现为「选人结果不对」而非报错）。**没被变异验证过的检查 = 没有**。

### B. 静默失败族
见 §5.2（此处不再重复）。

### C. 断言与测试（「绿」不代表对）
- **桩太宽松**：Show/Hide 空操作、IsShown 恒 nil、CreateFrame 丢 parent、GetWidth/GetHeight 恒 nil → 行为级/父级/尺寸断言全部失效；**写断言前先确认桩有状态**。
- **只测解析函数、不测调用点**（第 4 次发作）：要断言「A 产出配置、B 消费配置」**两边**；能点就点**真实按钮**。
- 结果相同的用例（等价变异）证明不了任何事；CRLF 上用 `\n` 锚点会**静默替换失败** → 变异后**必须回读确认结构真的变了**。

### D. 布局与 UI（本客户端实测）
- 同一行/栏**混用「顶边对齐」与「中线对齐」必然错位**（字体链不同时行高会变）→ 要么全顶边要么全中线（**按中线更稳**）；`中线 = 顶边 - 高度/2`（y 越往下越负）。
- **FontString 一律显式 `SetWidth`**，否则宽度随内容变、换语言就溢出压到别的控件；**改布局要一起改「隐形跟随件」**（占位提示/聚焦热区/背景纹理常写死宽度，grep 旧宽度值能找出来）。
- **`root:SetScript` 是单槽位**：多 Tab 共用根帧时先 `GetScript` 取旧处理器做**链式转发**，否则静默顶掉别人的滚轮。

### E. 兜底机制的设计纪律
- **前提被证伪的兜底必须删掉**（不能因为「留着无害」而保留——它在空转，还让人以为有保护）。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`；开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数、没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」）→ 匹配要剥掉「生物」再比。
- **无 CombatLog API、无免疫查询函数、无 `UnitCastingInfo`、无 SuperWoW**（精确距离/挥击计时做不了）。

### F3. 官方文档现场核对记录（1.70.47 逐条查 emberveil.org，2026-09）
- **Protected（文档明写 addons cannot call this）**：`CastSpellByName`、`SpellTargetUnit`、`SpellStopCasting`；★`TargetUnit`/`TargetByName`/`ClearTarget`/`UseAction`/`IsUsableAction`/`IsActionInRange` 条目里**都没有 Protected 标记**——这正是「切目标 → UseAction」这条唯一可行路径的依据。
- ★**`UnitIsUnit` 相同返回 `true`、不同返回 `nil`（文档原话 never false）** → 只能看真值，**不能写 `== true`**。
- ★**`GetNumPartyMembers()` 在团队里返回「团队人数 - 1」**（不是 0），而 **party 索引只有 `party1..party4` 且不含自己** → **不能拿它当 party 循环上界**（40 人团会去试 party1..party39；已夹到 4 并有调用计数断言守着）。**`GetNumRaidMembers()` = 团队人数含自己，非团队时 0** → raid 直接 `raid1..N`。

### G. 任务/地图专题的关键事实
- tick 帧必须挂 **`WorldFrame`**；视图签名必须含 **areaId + mapFile + continent + zoneIndex**（只比 areaId 会让「关图再开同一张图」被判「未变」）。
- 采集点数据在 `meta.herbs/mines/chests/fish` 里是**负 ID**（负号 = 类型编码），查 objects 表要取反。
- 对方地图标注层**没有地图事件可用，全靠 `REFRESH_INTERVAL=0.25` 轮询**——不要自己发明事件层。

### H. Lua 5.1 / 本客户端语言坑
- `string.find(s, "^14|", 1, true)`：**plain=true 会把 `^` 也当普通字符**；`|` 在 Lua 模式里是**字面量**（不是交替）。
- ★★**中文/多字节串上的模式匹配（1.70.47 一次踩中两个，代价是「整类条件解析不出来」）**：① `|` 不是交替（`(队伍|团队)` 只在匹配字面串时成立）；② **字符组 `[伍团]` 按字节匹配**——set 只吃**一个字节**，`[伍团]` 实际是 `{228,188,141,229,155,162}`，匹配到「伍」首字节后剩两尾字节对不上后续 `buff`，照样失败。**正确写法：用 `(.+)` 抓下来再 `==` 比较**。★症状有欺骗性：**编辑窗能存、导出也正常，但重新导入时条件静默消失**；只有「导出→导入」**往返断言**能抓住（组 66 当场定位）。

### I. 参考代码路径（**先读对方**，见铁律 2 / 3）
- **UnrealQuest**：`...\Interface\AddOns\UnrealQuest\Compatibility\ClientAPI.lua`（实测配方库，注释里全是坑）、`Core/Driver.lua`（帧父级/生命周期）、`Map/MapContext.lua`、`Map/WorldMapPins.lua`、`Map/NpcPins.lua`（CATEGORIES/RANK_ICONS）。
- **Cat（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Cat`（状态变量设计参考）；**OneJudge**（最初的参考：纯色纹理配方）。
- **Heart + C（TurtleWoW）**：`D:\game\TurtleWoW\Interface\AddOns\Heart`（团队/治疗框架）与共享库 `...\AddOns\C`（隐形 tooltip + 单位/buff 采集）——**队伍/血量/蓝量/buff 检测见铁律 3**。
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
- **文件结构（1.39.0 起模块化，不是单文件）**：`EvalHelp.toc` + `Locales/{zhCN,enUS,ruRU}.lua` + `Core.lua`（输出/i18n/状态采集）+ `Engine.lua`（规则引擎）+ `EvalHelp.lua`（UI/斜杠命令/init）+ `Toolbox.lua`（工具箱 Tab3）+ `DataSearch.lua`（数据检索 Tab4）+ `Share.lua`（方案分享，1.71.0）+ `IconBrowser.lua`（图标库 Tab5）+ `PetData.lua`/`PetHelper.lua`（抓宠 Tab6，1.73.0）+ `IconSem.lua`（**图标语义表**，1.73.5）+ **`tools/IconGrid.lua`（通用图标网格选择器，1.74.5：单选/多选、高度自适应、分页、滚轮、夹取） + `tools/HunterHelper.lua`（猎人助手 · 一键喂食） + `tools/ConsumableHelper.lua`（消耗品助手 · 多选横排各自点用）—— 都在 `tools/` 子目录里**
  + `examples/*.lua`（**11 个数据文件**）；文档 `README.md`/`README_en.md`/`README_ru.md`/`CHANGELOG.md`/`DEVELOPMENT.md`/`CLAUDE.md`；测试 `luacheck.js`/`test_engine.js`/`test_stub.lua`/`test_assert.lua`。**行数随开发变化，别当固定值引用**。
- ★**toc 载入顺序（以 `EvalHelp.toc` 为唯一真值）**：`Locales/{zhCN,enUS,ruRU}` → `Core` → `Engine` → `EvalHelp` → **`examples/*`（11 个数据文件，必须排在 EvalHelp.lua 之后）** → `Toolbox` → `DataSearch` → `Share` → **`IconSem`** → `IconBrowser` → `PetData` → `PetHelper` → **`tools\IconGrid.lua`（共用网格件，必须在两个助手之前）** → **`tools\HunterHelper.lua`** → **`tools\ConsumableHelper.lua`**（★`EXAMPLES TOC CHECK` 守着「磁盘 ↔ .toc 双向一致 + 顺序 = 选单顺序」；`IconSem` 必须在 `IconBrowser` **之前**——后者读它的 `EVAL_ICON_SEM`）。
  ★子目录模块（`tools/`）在 toc 里写 **`tools\HunterHelper.lua`**；它们**载入期零副作用**（只定义函数与常量），图标帧在用户打开开关时才建。
  ★**共用件纪律**：喂食与消耗品助手共用 `tools/IconGrid.lua`（网格 + `EVAL_IG_SCAN_BAGS` 扫背包 + `EVAL_IG_TOPLEFT` 位置换算）——
    同一内容不许两处各写（本项目铁律）；1.74.5 实踩一次「`IG.pages` 一名两义」（页号表被总页数覆盖 → 选完食物点格子报错且不收起），已拆成 `pageOf`/`pages`。
- ★**新增 .lua 模块要同时改四处**：① `EvalHelp.toc` 载入列表；② `test_engine.js` 的加载数组
  （**7 处清单**：DECL ORDER / LANG KEY / LANG SOURCE（自动发现，已含 `tools/`）/ COMMENT SWALLOW /
  FRAME NAME CLASH / COLOR CODE LEN / 主加载循环 —— 漏一处就是那一类检查的盲区，本项目踩过）；
  ③ `DECL ORDER CHECK` 的文件清单（**目前 13 个**：EvalHelp/Core/Engine/Toolbox/DataSearch/Share/IconSem/
  IconBrowser/PetData/PetHelper/**tools/IconGrid**/**tools/HunterHelper**/**tools/ConsumableHelper**）；④ ★**发布包清单**（第 9 步的 Copy-Item 行）——
  **放进子目录时尤其容易漏**：1.74.5 实事故预警 = `PACK LIST CHECK` 旧判据只看「顶层 .lua」，
  子目录模块被静默漏掉（本地测试全绿、出包缺文件、用户装了报错）
  → 判据已扩成「toc 里带路径的 `.lua`：要么逐个列出、要么所在目录被 `Copy-Item -Recurse` 整拷」，基准数也把 `tools/` 数进去。★1.73.5 实事故：新增 `IconSem.lua` 后**主加载循环**漏加 → `EVAL_ICON_SEM` 在测试里是 nil，图标库语义/过滤整组断言**全红**（这正是「检查存在 ≠ 覆盖到位」）。
- ★**案例模版数据文件（1.71.2 新增 `examples/*.lua`）只需改两处**：`EvalHelp.toc` + `test_engine.js` 加载数组（它们没有顶层 local，故不进 DECL ORDER 清单）。
- ★**在途（未发版）**：**1.74.5 猎人助手 · 一键喂食**（`tools/HunterHelper.lua` + 工具箱「猎人助手」分组）：
  · 交互 = 图标**左键一键喂食** / **右键选背包食物**（选完图标变该食物）；食物**只存名字**，每次实时重解析包格。
  · 「选食物」= **背包式图标网格**（用户要求「图标搭配 tooltip，类似背包四方格布局 8×N」）：8 列 × 5 行 = 40 格/页，
    **高度按实际行数自适应**（`hhGridHeight(rows)` 单一来源；2 件→115px、2 行→172、满格→343；底栏按钮只改 y 不重算 x），
    **图标 26×26 px、格子=图标尺寸**（★1.74.5 两次用户反馈的最终口径：「图标尺寸缩小到 55」→ 又「打开选择框内的图标也太大了，和外层图标尺寸对齐」
    ⇒ 与外层悬浮图标/配置入口统一为 **26**；步进 28）、**格子不自绘边框**（用户：「物品隐藏边框，图标已经自带边框了」；悬停改为提亮图标），
    ★面板宽 = **max(网格宽 242, 底栏最小宽 278)** —— 格子缩小后底栏会互相压（实发现），宽度下限落成几何断言；
    池子复用、数量角标、tooltip（名字/数量/包格/spec.hint）、`[上翻][下翻]` + 计数「1-40 / N」（绝不静默截断）、
    滚轮翻页走 `EVAL_WHEEL_DIR`（已纳入 `WHEEL DIRECTION CHECK`，8 处）、左键点格即选并收起、贴边夹取、网格不可用时降级文本下拉；
    ★**点框体外部自动关闭**（用户要求）：面板下垫一张**全屏透明 Button 捕手**（层 239 < 面板 240；Frame 收不到 OnClick，
    同「拖动柄必须用 Button」实测）；显隐**只由面板 OnHide 统一负责**（常驻可见 = 吞掉整屏点击）；组 176⑯/177⑦c⑦d。组 176⑯。
  · 工具箱那一行**右侧挂「待测试」黄感叹号**（用户要求；插件本地图 `media/icons/mark-test`，路径单一来源
    `EVAL_UI_MARK_TEST`；12×12 独立小 Button —— 纹理不吃鼠标事件，挂不了 tooltip；组 176⑭）。
  · ★**登录恢复**（用户实测：开着一键喂食、拖好图标、`/reload` 后图标**不见了**）：根因 = 开关只存状态，
    图标帧是「点开关那一下」才懒建的 ⇒ 登录流程里没人重建；修法 = `EVAL_HH_RESTORE()` 由 `VARIABLES_LOADED` 调用
    （+ 工具箱事件帧的 `PLAYER_ENTERING_WORLD` 二次恢复，按真实尺寸重算锚点，幂等）；**关着时一个帧都不建**（懒加载仍成立）。组 176⑰。
  · ★1.74.5 **共用件 `tools/IconGrid.lua`**：把上面那份网格抽成通用件（single/multi 两种模式、spec 给候选与回调），
    喂食助手通过 `EVAL_HH_GRID_*` 薄封装继续用它（既有名字/读值口不变，组 176⑮⑯⑰ 一字未改照跑）。
  · ★1.74.5 **消耗品助手**（`tools/ConsumableHelper.lua` + 工具箱「消耗品助手」分组，默认关）：
    **主图标 = 第 1 个选中项**（左键用掉它；★没选中时左键**不弹面板** —— 用户明确「左键不要触发弹窗选择」，只如实提示走右键；**右键 = 开/关面板**，唯一入口）·
    **横排 = 第 2 个起**（第 1 个已在主图标上，**不重复画** —— 用户截图：「选中一个多了个重复的」「选中第二个的时候才增加」）·
    **重复点格子 = 取消选中**（多选开关，状态落盘）。
    ★**两个助手的主图标都是 26×26**（用户截图：「两个助手的图标都太大了，需要和配置的图标相同」
    ⇒ 与 `EvalHelp.lua` 的配置入口/小地图按钮同尺寸 `mb:SetWidth(26)`；位置记忆存的是「中心偏移」，改尺寸不影响老存档）；
    横排每枚 26×26（步进 28 = 26+2，相对主图标 +4/+32；贴屏幕右缘整条自动翻到左侧）；左键横排 = 用该物品
    （`UseContainerItem(bag,slot)`，包格**按名字实时解析**）、右键横排 = 取消选中；多选状态落盘（`tb.chUse`，顺序=点击顺序，上限 10 如实提示）；
    使用是**服务器写动作 → 0.3s 限频**（同一时刻再点如实拒绝）；
    ★**用完/不在背包 → 图标灰显留在原地**（用户要求；贴图在选中时记进 `tb.chTex` 跟着存档走，找不到时用记住的贴图 +
    顶点色 0.35 三通道同值；补货即恢复白显；判据读真控件 `GetVertexColor`）；登录恢复同喂食助手（`VARIABLES_LOADED` + 进世界二次恢复）；组 177。
  · ★1.74.5 **方案「作者/来源」**（`prof.author` + `prof.src`）：唯一标签函数 `EVAL_PROF_AUTHOR_LABEL(prof)` 分四类 ——
    自创（`src ~= "text"`；★**只显示「自创」** —— 用户澄清：「别称的意思就是方案内显示自创（实际值是自己名字）」⇒ 自己的名字照旧记进 `prof.author` 存档**但不上屏**；老存档无 author 同样显示「自创」）· 案例模版（显示**真实作者**：`技能学院`）· 别人分享（显示**真实作者**：发送者名）· 导入（文本粘贴无作者）。
    三处导入点各自盖章：手建 `EvalHelp.lua` = `UnitName("player")` · 案例模版选单 `ioImportText(p.text, "技能学院")` · 分享弹窗 `EVAL_IMPORT_TEXT(p.text, p.sender)`。
    方案列表 tooltip（一键宏 Tab）= 方案名 + **评级**（品阶名 + 分数）+ **来源**（作者标签）+ 技能数；判据 **组 179**（四类 + 三导入点 + 真 OnEnter + 换一组再比）+ **`SHARE AUTHOR WIRING CHECK`**（源码级接线）。
  · ★1.74.5 **头衔评定只算自创方案**（用户：「角色头衔评定标准是只有自己创建的方案才加入评定分计算」）：
    `EVAL_TITLE_COUNTS()` 按 `p.src ~= "text"` 过滤；`EVAL_TITLE_STATE()` 与创世者彩蛋闸门同源；组 147⑦b。
  · ★1.74.5 **分享「不弹窗」原因全部落日志**（用户：「现在为弹窗原因在日志内显示」）：统一入口 `shNoPop()`，前缀 `[分享] 不弹窗：` ——
    接收开关关着 / 载荷不完整 / 分片超上限 / hex 还原失败 / 重复收齐 / 暂未收齐 / 超时丢弃 / 在途超上限，八条分叉**不再静默**（此前只有「弹窗/过大/自己的回声」三条落盘）；组 178。
  · ★1.74.5 **分享「场景描述」**（用户：「接收方案完成后再加一句模版：<头衔> 根据当前所在<地点>、<有无目标> 做场景描述，背景=魔兽世界」+「头衔根据等级染色」）：
    点 [导入]/[忽略] ⇒ 彩蛋反应（立即发）之后**再补一句**场景描述（进 `shTxQ` 限频队列，≥1s 滴出）；
    分派 = op × `UnitExists("target")` ⇒ **4 张表各 10 条**（`SH_SCENE_{IMP,IGN}_{IDLE,TGT}`，三语言齐）；
    占位符优先级 ① 头衔（句首，**按档位染色** `EVAL_TITLE_CURRENT().color`；没入档→玩家名且**不猜色**）② 地点（`GetRealZoneText`）③ 目标（仅 _TGT 两张表）；
    ★★★**形态铁律（实测事故）**：客户端**不画「有色码但没有链接」的消息** ⇒ 头衔必须包成与封皮 A 行同款的链接
      `|c<档位色>|HEHPF:<传输id> 0/1:0|h[<头衔>]|h|r`（第一版写成「色码 + 纯文本」→ 用户实测整条不显示）；
      拿不到传输 id / 合法 8 位色码 → 退回纯文本（无链接无染色，但**能显示**）。整条**只许一段色码**；地点**永不写死**（只用魔兽世界通用意象）；组 180 + `SHARE SCENE WIRING CHECK`。
  · ★1.74.5 **「取消彩蛋」的口径（用户随后澄清）**：「我说的是删除场景描述的彩蛋，而不是把彩蛋功能删除」⇒
    [导入]/[忽略] **不再发**角色扮演反应句（改发上一条「场景描述」），但彩蛋**功能与三语言 50 格文案全部保留**、只是**未接线**；
    闸门：`SH FUN CHECK` 钉「机制都在（频道映射/两表/抽奖/名链接/超长守卫）**且** 两处调用点未接」，组 170① 仍验文案结构，
    组 82④⑤ 是**反向哨兵**（点了不许发出任何 `SH_FUN_*` 句子）。★恢复接线 = 把 `shSendReaction("imp"/"ign")` 加回回调并**同步改那条检查**。
  · ★1.74.6 **自身/目标 debuff 支持「负面类型」**（用户：「查看自身/目标debuff 条件类型配置项，需要参考队伍debuff 配置支持 debuff 负面类型功能」）：
    队伍/团员/候选者 debuff 本来就有「负面类型」（1.73.2 多选），**自身（`pDebuff`）/目标（`hasDebuff`）**这次补齐，四族走**同一套**：
    | 环节 | 做法 |
    |---|---|
    | 状态层 | 层数表**保持数字**（`st.playerDebuffs/targetDebuffs`，读侧一字不改），类型另存**平行表** `st.playerDebuffType/targetDebuffType`（`UnitDebuff` 第 3 返回） |
    | 解析 | `auraStackSplit()`：**先剥层数后缀再拆名字/类型** ⇒ `断筋(魔法)` / `断筋(魔法) >=2` / `魔法` / `魔法 >=2` 全能解析；**没写括号时与旧行为逐字一致**（`dt=nil`，存量文本一个字节不变） |
    | 求值 | `auraCountOf(cd, 层数表, key, provider, 类型表)`：**名字对上但类型不符 → 视为没有**（`dispelMatch`）；**名称留空 + 类型 = 「有任意该类型」**（按类型表数命中项、层数取命中项**最大值** ⇒ lim=1 是存在性、lim=N 是「有一条叠到 N 层」） |
    | 导出/显示 | **同一份** `dtSuffix()`：导出英文 token（`(Magic/Poison)`）、界面显示本地化名（`(魔法)`）；顺手补上 `candDebuff` 原先**漏掉的类型后缀**（它以前存不住类型） |
    | 编辑窗 | 类型格 `row.dtBtn` 对 pDebuff/hasDebuff 也 Show；判据读 `EVAL_TEST_SE_ROW_DT(i)`（自身/目标两行都要有、**buff 行不许有**） |
    ★判据 **组 181**（解析 / 存量导出不变 / 类型过滤 / 名称留空=任意该类型 / 往返 / 编辑窗三态）；**变异 M181**（拿掉「类型不符=没有」那一行）→ 当场红：`ASSERT FAIL[③★★★名字对上了但类型不符 → 不命中]`。
    ★已知限制：编辑窗光环名下拉**没有「清空回任意」这一项**（自由文本空串被忽略）⇒「名称留空 + 类型」目前靠**默认空名**或文本导入配；要 GUI 化就给 `SE_AURA_MENU` 加一条「任意（按类型）」（会动到菜单顺序断言，故本轮没做）。
  · 位置：**默认落在窗口正中**（用户指定）；拖动后记住「中心偏移」、越界位置夹回屏幕内 —— 换算单一来源
    `hhTopLeft(sw,sh,cx,cy)`（★修掉两个错写法：y 方向写反会落到屏幕上方之外、x 少减 s/2 恒偏 18px）；组 176⑬。
  · **懒加载结论（用户要求分析）**：本客户端**无 `io/os`（无文件读取 API）**、`LoadAddOn` 又是 **Protected**
    ⇒ **文件级懒加载不可能**；能做的是「toc 预载 + 载入期零副作用 + 首次使用才建帧/扫包/建 tick」。
  · 喂食链路 = `RunScript('CastSpellByName("喂食宠物")')` → 等 `SpellIsTargeting()==1` → `PickupContainerItem(包,格)`；
    守卫：没进待选态**绝不点包**（否则把食物捡到光标上）、光标被退回就 `ClearCursor` 还原。判据 = **组 176** + `HH WIRING CHECK`。
  · 取证命令 `/eh go 喂食探针`（`扫书` / `施放 <名>` / `喂 <包> <格>` / `拖` / `收光标`）——**真机四项待实测**见该文件头部注释。
    ★含「**点击分派**」一行（注册右键结果 / 左右键计数 / 最近 button 与**原始参数形状**）。
  · ★★★**本客户端 OnClick 的参数形态不固定**（用户实测：右键「选食物」打不开）：照教科书写 `function(_, button)`
    会在 `self` 占第一位时拿到 **nil** → **右键掉进左键分支**（去喂食了）。正解 = 主程序已实测的**四候选**写法
    （`(type(a)=="string" and a) or (type(b)=="string" and b) or (type(arg1)=="string" and arg1) or "LeftButton"`）；
    判据 组 176⑮（四种形态 + 「左键不许开菜单」反向哨兵）。
  · ★**状态（用户决定）**：用户说「这个工具先放着以后测试」→ **停在「已实现 + 双闸门绿 + 未提交/未实测」**；
    默认**关**（`tb.feedPet` 空 = 关）+ 载入期零副作用 ⇒ **放着不影响任何现有功能**。
    回来继续时：读 `.dsh/reports/hunter-helper-impl.md`（实现说明 + 16 步真机测试流程 + 四个待实测项）。
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.74.28**（v1.74.27 已发布）
  （**v1.74.27 已发布**；`CHANGELOG.md` 的 `## 详情小节` 最新到 **v1.74.6**，`v1.74.7 ~ v1.74.28` 只保留**顶部速览表**一行一版（1.74.28 = 两个助手弹窗候选按物品类型过滤）。
  ★`CHANGELOG.md` 的 `## 🎯 v1.74.0` 小节已把 **1.73.35 ~ 1.74.0**（85 个提交）归纳成 7 条里程碑）。
  ★1.73.35~1.73.67 那批工作（分享封皮/品阶评分/头衔抽卡/彩蛋/角色扮演反应/标题栏徽标/取证探针）已随 **v1.74.0** 一起发布。
- **1.74.9 记忆体瘦身（本机会话）**：常驻卷 `CLAUDE.md` **86,364 → 63,984 字节**（回落到 65,536 预算内，尾部不再被截断）：§3 对照表 / §5.2 两条长案例 / §5.4 UI 全量 / §5.5 API 全量 → 参考卷 **§十**（原文照存）；新增常驻卷「**记忆体写入纪律**」+ 参考卷 **§十一**（上下文成本实测 · 度量法 · 搬迁套路）；`sync_game.js` 加「本机无需同步」自检。
  ★**逐版本流水一律不进本文件**（见文件头写作纪律）——要点查源码注释 / `CHANGELOG.md` / `git log`；
  本节只保留**在途专题的结论**（下面那条方案分享）。
- ★★★**方案分享「隐藏载荷 + 信息行」**（1.73.41~1.73.67，分支 `probe/share-hide-link`）→ **已随 v1.74.0 发布**，
  细节见 `CHANGELOG.md` 的 v1.74.0 小节与 §5.2 的分享条目。这里只留**必须随时可查的硬事实**：
  · 分片形态 `|cff9ad4ff|HEHPF:<id> <i>/<n>:<hex>|h[秘籍传输中...p%]|h|r`（标签**不带方案名**、只报进度，文案走 `SH_CHUNK_LABEL` 三语言，判据 组 144②）；速率 `SH_SEND_RATE=1.0`（每秒 1 片；0.5 秒会时好时坏）。
  · 信息行（最后一步，一段色码）`|c<品阶色>|HEHPF:<id> 0/1:0|h[<符号><品阶>秘籍·<名>]|h|r  <评语>`。
  · **点聊天里的分享链接 = 只弹出确认窗，绝不自动导入**（[导入] 是唯一写入路径，判据 组 144③ / 145③④⑥）。
  · 色码与形态规则见 §5.2；源码检查 `SHARE MSG SHAPE CHECK` / `COLOR CODE LEN CHECK` / `SHARE PALETTE CHECK`。
  · 取证命令：`/eh go 封皮测`（编号变异测）· `分享探针`（发送留痕）· `色码测`（在用色码逐条实发）· `名号色`（彩蛋名号色候选）。
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

## 九、版本要点汇总（最近 10 版，每版一行；完整记录见 CHANGELOG.md 与 git log）
1. **1.74.28** — 🧺 两个助手弹窗候选**按物品类型过滤**（品质 → `GetItemInfo(链接)` → **自建 tooltip 兜底并自愈客户端缓存**；药草矿物材料等全剔，判不出不剔）+ 验证命令。
2. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（打包基准 69）。
3. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；删掉所有与任务插件机制的耦合。
4. **1.74.25** — 📏 切目标文案纠错（真因 = 客户端只认附近单位）+ 目标探针。
5. **1.74.24** — 🎨 稀有提醒名字按**品阶染色** + 可点链接。
6. **1.74.23** — 🔔 **稀有提醒转播**：包住 UnrealQuest 弹窗唯一出口 `RareAlert:Show`。
7. **1.74.22** — 🧩 模版收录「神圣风暴」+ 模版按品阶重命名 + 作者/备注 + 神级改亮蓝。
8. **1.74.21** — 🎯 神级门槛 120 → **50**（封顶与示例全部现算）。
9. **1.74.20** — 👤 **配置分角色存**（三个助手 15 个键，`tbCfg()` 路由代理）。
10. **1.74.19** — 🏅 **评级与头衔重做**：空技能 0 分、条件加权、覆盖封顶、头衔逐级满足。

## 十、常驻卷瘦身移出（1.74.9 审计 · 原文照存）

> 常驻卷 `CLAUDE.md` 超出工作区指令预算（65536）会被**截断加载**，故把下列**明细整段**移到这里（**原文未改一字**），常驻卷里保留一句话索引与必须随时可见的铁律。
> 要查下列内容按标题搜本节即可。

### §3 铁律 3：Heart / C 参考实现「按问题查哪个文件」9 行对照表（原文）

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


### §5.2 两条长案例：1.74.5 回声忽略真凶 + 1.74.4 分片取证探针（原文）

- ★★★1.74.5 **「回声忽略」误判真凶**（用户报「盗贼方案分享无弹窗，其他正常」+ 探针 ⑤ 实锤「收齐 → 回声忽略 IS_MINE=true」）：
  【根因】旧「自己方案回声忽略」判据 = `EVAL_SHARE_IS_MINE(text)`（**接收方库里有没有这份方案**的文本比对）——
    只要接收方**恰好已有**这份方案（同账号共享库 / 以前导入过），就把**别人发的**误判成「自己的回声」吞掉、不弹窗。
    ★本意是「忽略**我自己发**的回声」，但旧判据只看「我有没有」、不看「**是不是我发的**」。
  【修法】判据改成 **`shIsSelfEcho(sender)`（发送者是不是本机玩家，剥色码/剥「-服务器」后缀）**：我发的才是我的回声；
    别人发的，哪怕我库里有同款，也是**别人的分享**，该弹。`EVAL_SHARE_IS_MINE` 函数保留（它自身的单测 5193/8182 仍验它，只是不再用于这一刀）。
  【判据】组 82 ①/①b/③：本人(测试玩家)发 → 忽略；**非本人**(彩虹)发、库里有同款 → **该弹**；说来源照旧弹。
    端到端复现：iotol 发盗贼（接收方库里有同款）→ 待导入=盗贼（修复前=被吞）；本人自发 → 仍忽略。变异 M569/M570 捕获。
  ★★两个教训：① 「自我回声」的判据**必须锚在「发送者是我」**，不能锚在「内容像我」—— 内容匹配会把「别人发的同款」误杀；
    ② 上轮（1.74.4）我按存档日志判「IS_MINE 没触发」是**误判**（日志环缓冲没覆盖到 / 搜索没命中），是探针 ⑤ 一屏定案它其实触发了 ——
    「能做成命令就别让用户手工复现」的价值又一次实证；★「按日志判没发生」≠ 真没发生，日志是环缓冲会覆盖。
- ★★1.74.4 **「分片到了却不弹」取证探针**（用户报「某角色(iotol)分享，对方不弹窗，其他角色正常」，静态查不出因）：
  新增 `SH.dbgChunks`（环形 8 条）+ `shDbgChunk(stage,msg,extra)`，在 `shOnMsg` 的**解析 / 入缓冲 / 收齐 / hex还原失败 / 过大 / 回声忽略 / 弹窗**
  各分叉点记录**原文+走到哪一步**，`/eh go 分享事件` ⑤ 摊开 —— 只记含 `EHPF` 的消息（低量，不碰普通聊天）。
  ★价值：把「分片到了却没弹」从「猜」变成「看到真实载荷 + 死在哪一步」（解析✗=载荷格式不对 / 只入缓冲没收齐=丢片 /
  回声忽略=IS_MINE 误判 / hex还原失败=坏 hex / 过大丢弃 / 弹窗=其实弹了）。
  ★同案顺手修探针假「未注册」：本客户端 `IsEventRegistered` 返回 **`1` 不是 `true`**，旧探针按 `== true` 判 → 全显示「未注册」，
  与实际收到事件（③）自相矛盾、把排查带偏；改判 `(r == true or r == 1)`。
  ★排查过程坐实（排除项）：当前代码对 队伍/队长/私聊 三事件**都能走完弹窗**（harness 复现全过）· IS_MINE 回声忽略**没触发**
  （存档日志无「已忽略（自己的方案回声）」）· 接收配置 recv=true · 分片载荷 `i/n:hex` 自 `975e6f1` 起就有（带「秘籍传输中」标签即新格式）。


### §5.4 UI 与布局 全部逐条判据（原文：品阶色/评分口径/覆盖封顶/头衔晋升/分角色存档/滚动分页/滚轮/弹窗/菜单/技能格等）

### 5.4 UI 与布局
- ★★★标题栏（两窗同一实现）＝玩家名→头衔→品阶徽标→方案名＋右侧两开关；两窗各自 BUILD＋tick 刷（只开状态UI 也要跟·组 168⑤）；头衔取 `EVAL_TITLE_CURRENT()`；色码→RGB `EVAL_COLOR_RGB`（8 位）；CHECK `UI TITLE BADGES CHECK`/`UI TIER BADGE CHECK`/`UI TITLEBAR CHECK`/`UI TITLE NAME CHECK`；组 162/163/164/166/168。
- ★★品阶唯一源 `SH_SEAL_TIERS`：**1.74.21 起** ≤11 普通/12-23 稀有/24-35 珍稀/36-49 绝版/**≥50 神级**（用户定神级 = 50；低四档把 0~49 四等分）；色走 `SH_SEAL_TIERS[].color`（★1.74.22 用户定：**神级 = 亮蓝 |cff00bfff**；配色史 暗金 b87333 → 亮蓝 00bfff → 深红 c00000 → 亮金 ffcc00（试色）→ 亮蓝 00bfff）；`SHARE PALETTE CHECK` 守色码不重复；判据钉边界两侧（11/12 · 23/24 · 35/36 · 49/50）；组 143/146/147/195/196
- ★★★**评分口径（1.74.19 重做，用户「增加评级难度」）**：`EVAL_PROFILE_SCORE` = Σ(每条技能)[ 有条件 ? 1+Σ条件权重 : 0 ]；
  **空技能 0 分**（旧口径白送 1 分 ⇒ 25 条空技能就神级，实测复现过）；条件按类加权 **自身/技能 1 · 目标/光环 2 · 队伍/候选 3**（表在 `SE_TYPE_GROUPS` 的 `w`/`cov`，**唯一来源**）；
  单条上限 12 分；同一行里**完全一样**的条件只算一次；★不占动作条的特殊技能（`EVAL_NO_SLOT_OK`）无条件**保留 1 分**（用户定）。
- ★★★**覆盖封顶**：覆盖 1/2/3 个大类分别封顶 **23/35/49**（值从 `SH_SEAL_TIERS[n+1].max` **现算**），**≥4 类才不封顶** ⇒ 神级必须跨类写；
  ★**带方案表的调用点一律走单入口 `EVAL_PROFILE_TIER(p)`**（`EVAL_SHARE_SEAL_TIER(score, coverage)`；**coverage 传 nil = 不封顶**，别把纯分数调用点误伤）；`COVERAGE CAP WIRING CHECK` 守「没人再写 `EVAL_SHARE_SEAL_TIER(EVAL_PROFILE_SCORE(p))`」。
- ★★★**头衔晋升（1.74.19）**：`SH_TITLE_REQ = { 1, 2, 3, 3, 2 }`（稀有+≥2 · 珍稀+≥3 · 绝版+≥3 · 神级≥2）＋**逐级满足**（断在哪一档就停在哪）；旧口径 2~5 档全是「≥1 个」⇒ 头衔满档只要 1 个方案，连带彩蛋闸门形同虚设。
  ★命令/闸门/样例的分数**一律现算**（`EVAL_SEAL_GOD_SCORE()` / `EVAL_SEAL_TIER_SAMPLE(i)`），不再写死 25 / {3,9,15,21,26} / {1,4,7,10,13}。
- ★★★**配置分角色存（1.74.20，用户「消耗品助手 + 喂食助手 + 骑乘助手整块按角色」）**：新增**角色级存档** `EVAL_HELP_CHAR`（toc 里 `## SavedVariablesPerCharacter` —— 本客户端实测支持：UnrealQuest 已在用、磁盘上 `Saved/Account/<账号>/<服务器>/<角色>/SavedVariables/`）；
  **角色键清单 = `Toolbox.lua` 的 `TB_CHAR_KEYS`（唯一来源，15 个：三个助手的开关/列表/贴图缓存/悬浮件位置）**；`tbCfg()` 返回**路由代理**（`tbMakeRouter()`：角色键落角色表、其余落账号表）⇒ 上百处 `tb.xxx` 调用点**一行未改**；
  ★★**代理的 `__index` 绝不能写 `at and at[k] or nil`** —— `false or nil` 还是 nil，会让所有值为 false 的账号开关被读成 nil（= 用户关掉的开关自己又开了；组 79 当场抓到）。必须 `if not at then return nil end return at[k]`。
  三个助手各自改走 `EVAL_TB_CHAR_STORE()`；老存档里那些键**一次性继承**到每个角色（**账号里那份副本保留** = 还没登录过的角色的种子），迁移挂在 `VARIABLES_LOADED`（**账号表没到位时不许标记**，否则从空表继承出空配置、种子永久丢）；方案库/语言/日志/分享开关**仍旧账号级**；
  `SAVEDVARS SPLIT CHECK`（toc 声明 + 清单唯一来源 + 三助手接线 + **无「按角色键读账号表」的泄漏** + 代理无 and/or）＋组 197（含 false 读回、迁移不覆盖、账号表未就位不标记）。
- ★**COND WEIGHT CHECK 的实战价值**：它上线当场抓到 `target`（「选取目标」，hidden 存量类型）**不在任何分组**里 ⇒ 新口径下会被按 0 分算、也不计覆盖（静默少算）。★「新增条件类型必须进组」由它兜底。
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★纯黑＝`EVAL_SHARE_SEAL_ICON` 两返回值内联进 `pcall(t.SetTexture,…)`⇒多返回值禁内联进可变参数调用；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。
- ★★★滚轮方向唯一源 `EVAL_WHEEL_DIR(a,b)`（幅度归一 ±1）；6 处全走它；`WHEEL DIRECTION CHECK`（禁位移与方向同号）＋组 115；★断言把方向写反⇒反向 bug 被「验证」通过。
- ★★★数据刷新不许改可见性：`EVAL_WAR_TAB_REFRESH()` 又被开配置窗与 `EVAL_PM_APPLY` 调用⇒可见性只由 Tab 切换负责（`EVAL_HELP_CFG_SETTAB` 的清单）；数据照旧每次刷；组 165＋`EVAL_TEST_WAR_ROWS()`。
- ★★视图切换要把另一视图控件整块隐藏（整表 Show/Hide·组 113②）；`Hide` 过的逐个 `Show`（少一个＝永久不显示·组 113③）；布局审查读真实矩形（`EVAL_PH_TEST_GEOM()`·组 113④）；输入框唯一入口 `EVAL_PH_SET_QUERY`（退回列表）、回写前 `GetText` 比对（否则递归）。
- ★入口控件永远不许藏（默认文案「不限」）；查不到≠没有⇒如实说明（`SE_RANK_NONE`）、不弹单项下拉（组 110⑨）；「隐藏」＝不画不是 `Hide()`⇒背板＋挪出可视区 `DD_SEARCH_PARK=-4000`；锚点＝邻居哪条边（`Minimap` 是圆的⇒`RIGHT` 对 `LEFT`）。
- ★分列切点＝允许切点里两列行数差最小；组是不拆的最小单位；版式抽纯函数；组标题不许孤悬行尾；绝不静默截断（`DD_MAX_ROWS=96` 末行「…… 还有 N 项未显示」、`SH_DETAIL_MAX=6`）；不变量读真实几何（本列内/同 y 两列各自成行/不跨列/行数差 ≤2）。
- ★★类别独立一行＝标题独占一行＋本组按钮从下一行排、放不下换行；窗高变高（660×240→660×340）；`rowsOf` 与摆放循环必须逐字一致，用「自报 `rowsL/rowsR` vs 真实控件行数」钉住（组 91）。
- ★工具箱两列（按组边界切、取两列行数差最小）：列宽＝(可用宽−列缝×(列数−1))/列数、< 200 退单列；列不相交要几何断言（每控件显式限宽·组 120③）；★★★读值口绝不许复刻映射逻辑（`EVAL_TB_TEST_LAYOUT` 又算一遍⇒变异存活）。
- ★弹窗高度自适应条目：唯一源 `EVAL_TB_MENU_HEIGHT(条数)`；判据要换一组条目再比；同一行 y 单一源⇒`TB_ROW_TXT_DY`；判据读真实控件顶边；★别用 FontString 高度算中心⇒配反向哨兵。
- ★自绘风格两步：① 先问能否借用官方件（`UnitPopupMenus`/`UnitPopupButtons`）但必须先取证；② 不成则半透明底、宽度上限 ≤4 汉字＝62px、条目 ≤4 字、保留原有入口。
- ★多段一行居中（弹窗「接收方案」勾选）：与配置窗同一开关同一真值＋弹出时刷新；判据两段（生产数字验居中＋真实控件验落地）；标签宽实测优先 `GetStringWidth`、拿不到按字符数估（`string.len` 是字节）。
- ★导出 token、界面本地化＝同一份格式化＋一个开关：`EVAL_COND_STR(cd,disp)`/`EVAL_GROUP_STR(groups,disp)` 让界面走语言包、导出与往返一律 false⇒英文 token 逐字不变；读值口 `EVAL_TEST_SE_PREVIEW()`＋反向哨兵；组 125＋`DEBUFF DISPLAY CHECK`。
- ★职业着色＝描述表 `TB_PAINT_LISTS`＋painter＋三纯函数；包装＝先调原函数再叠色＋幂等守卫＋备份存 local；开关关掉＝不再叠色＋立刻重刷；禁用 `hooksecurefunc`；拿不到就不猜；组 119＋`PAINT WIRING CHECK`。
- ★★聊天窗名字着色：一个包装体管两功能（`EVAL_TB_CHAN_INSTALL_ONE`）不叠两层；覆盖所有窗（`ChatFrame1`＝`DEFAULT_CHAT_FRAME`，幂等按入口判、不按名字去重）；缓存唯一 `tbNameClass`；不做自动 /who（`SendWho` 等都是服务器查询）⇒查不到不上色；纯函数 `EVAL_TB_CHAT_COLOR_LINE` 拿不准就不碰；三坑：前 11 字节判富文本会染链接名·字符数≠字节数·`EVAL_SAY` 行不着色；颜色码长度禁写死（`|c%x+`）、诊断分开打（`EVAL_TB_CHATCOLOR_ROUTES`）；`CHAT COLOR WIRING CHECK`（先摘注释）；组 121①⑭。
- ★主动查询（四道闸门）：`TB_WHO_GAP=5s`、`TB_WHO_PEND=8s`、`TB_WHO_MISS_TTL=1800s`、`TB_WHO_QMAX=20`；查询日志只进调试日志（`EVAL_LOGLINE`⇒`/eh logdump`）；「查谁」更严：只认发送者位置的方括号名；`SendWho` 只许在 `tbWhoTick` 里。
- ★分享弹窗：摘要行⇒「X 分享的 [品阶秘籍·名]」带品阶色；品阶行只留图标、删重复文字、没连图标一起删（`EVAL_SHARE_SEAL_ROW` 被组 145 等用）；坐标 `SH_SEAL_ROW_Y` -50→-46·`SH_DETAIL_Y1` -74→-66·dPanel 顶 -46→-42；组 145；★改 UI 文案要同步反转旧判据。
- ★可点品阶色链接（`|HEHPF:<id>` 形态，封皮 B 行与场景描述头衔同款）：点它靠 `EVAL_SHARE_CLICK_OPEN("EHPF:<id>")` 在 `SH.recent` 找（用 `SH.pending.idh`）⇒ 重填 `SH.pending` 弹出接收页；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本；`shReactionNameLink(p)` 现在是**保留但未接线**（彩蛋取消）；判据组 180②（点头衔链接打开接收页）。
- ★彩蛋角色扮演反应（1.73.64 建 · **1.74.5 起未接线**）：机制/频道表/抽奖/名链接/三语言 50 格文案**全部保留**，但 [导入]/[忽略] **不再发**（改发「场景描述」，见下条）；`SH FUN CHECK` 钉「机制都在 **且** 调用点未接」＋组 170① 仍验每句恰 2 个 `%s`；组 82④⑤ 是**反向哨兵**（点了不发反应句）。
- ★彩蛋创世者亲临闸门：手动创建的方案有**神级**（1.74.19 起 = 封顶后有效分 ≥50，读 `EVAL_SEAL_GOD_SCORE()` 现算，不写死）· 手动方案 **≥3 个**（1.74.19 用户定：不变）· 头衔满档 5；`src`：手工点写 `"manual"`、文本解析在唯一出口 `EVAL_PROFILE_FROM_TEXT` 盖 `"text"`、老存档无 `src`⇒按手动；堵两条路 `EVAL_TITLE_CREATOR_OPEN` 与 `EVAL_TITLE_CREATOR_TRY`；`EVAL_TITLE_EGG_CHECK()` 挂 `EVAL_WAR_TAB_REFRESH`＋登录、只播一次；组 169＋组 150/150⑥＋`CREATOR GATE CHECK`。
- ★★★队伍菜单三条条件（1.74.1，审计定案）：**邀请队伍** = 不在队伍 或 我是队长（修「队长反而邀不了人」的旧 bug）；
- ★1.74.4 邀请队伍再补一刀（用户截图：对方已入队却仍显示邀请队伍）：条件只看「我」的状态是 bug → 改为「**对方不在我队伍/团队里 且 （不在队伍 或 我是队长）**」；队友已入队 → 邀请藏掉（踢出/离开照常）。组 130⑥e2 反转；变异 M568。
  **踢出队伍** = 我是队长 且 被右键的是队友（非队长根本不出现这条，不再是「点了才说不是队长」）；**离开队伍** = 在队伍内显示
  （退队不需权限，与右键的人无关，动作 `LeaveParty()`）。判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`；★助理踢人没有
  `IsRaidAssistant` 接口可判 → 如实接受边界（助理看不到这条，动作里仍有「不是队长」兜底）。成员判定 = `EVAL_TB_NAME_INMYGROUP`
  （UnitInParty/UnitInRaid 反查，party 只扫 1..4）。组 130⑥e/⑥e2/⑥e3 + 组 173 + ⑤b；变异 M564~M567 捕获。
- ★★★技能格按键分派（1.74.2，用户定）：战斗信息UI 技能小图标 **左键 = 快速切换启用/停用**（写 `r.enabled` **配置真值** + 如实播报 + 双刷新 `EVAL_WAR_TAB_REFRESH`/`EVAL_HELP_UI_TICK`）· **右键 = 技能配置弹窗**（开被点那格、不动状态）；格子必须注册 `RightButtonUp`（光注册左键 = 右键永远到不了分派代码）；读值口 `EVAL_TEST_UI_CLICK_CELL` / `EVAL_TEST_SE_SHOWN`；`UI CELL MOUSE CHECK`；组 174。
- ★布局总纪律：需求验性质不验数字；相对量验相对量；同一行中线对齐；中文宽度按字符数估；布局常量单一源（`IO_BW/IO_GAP/IO_PAD`、`CLOSE_LEFT/CLOSE_MIDY`）。



### §5.5 API 与客户端事实 全部逐条（原文：射程/物品 API/纹理路径/IconSem/api 索引有无清单）

### 5.5 API 与客户端事实
- SpellStopCasting()：读条/自动射击/魔杖三类全覆；Protected→须 RunScript（直调无效）；「进度条没了」≠取消。
- AttackTarget()=Toggles 须 IsCurrentAction(攻击格)；Movement 仅 FollowByName/FollowUnit 非 Protected（MoveForwardStart/Stop、TurnLeftStart 是）；FollowByName 空名=当前目标、只搜已知玩家、无返回值、不走 RunScript。
- GetRaidRosterInfo(i) 九返回；越界/非团队只回 nil。
- 1370 API 无 aura 专用函数；GetPlayerBuff(i,f)=增益条 0 基下标；无文件读取 API（无 io/os）→载入文件唯一形式=列进 .toc；★`LoadAddOn` 是 **Protected**（全表仅 13 个）⇒ **文件级懒加载不可能**，只能「toc 预载 + 载入期零副作用 + 首用才建帧」（范式：`tools/HunterHelper.lua`）。
- GetQuestReward 会再触发 QUEST_COMPLETE→须三层防护（同名去重/领取窗口闸门/全局频率上限）；UnitDebuff 第 3 返回=dispel token；UnitMana=主能量且有显示缩放（怒气÷10、幸福÷1000）→判蓝量前先 UnitPowerType(unit)==0。
- 施法 API 全 Protected（CastSpellByName 仅 onSelf/CastSpell/SpellTargetUnit/SpellStopTargeting/SpellStopCasting）；TargetUnit 非 Protected=唯一路径（切目标→UseAction(slot)→还原）；Targetting 另有 TargetLastTarget/ClearTarget/TargetByName/TargetNearestPartyMember。
- ★★★`CHAT_MSG_PARTY_LEADER`/`CHAT_MSG_RAID_LEADER` 是**独立事件**（队长/团长发言）：接收帧**必须也注册**这两个——只注册 `CHAT_MSG_PARTY`/`RAID` 时队长一分享**一片都进不来**（接收端静默、发送端照样报「已发送 N 片」；1.74.3 修的正是这个）；来源判据=触发事件名（队长版映射到「队伍/团队」）；发送侧只留 公会/队伍/说；自查 `/eh go 分享事件`；`SHARE RECV EVENTS CHECK`；组 175。
- 纹理路径=/Game/Interface/Icons/<名>_TEX，写错显 ?；GetNumMacroIcons/GetMacroIconInfo=唯一合法路径入口（1018 条 → doc/图标路径清单.txt）；PET ICON CHECK 校验真存在。
- IconSem.lua（用户要求：名称+多标签+按名/路径过滤）：基础名须剥 _TEX（组 117①b）；过滤=四命中+分组叠加；纹理字面量须在白名单（PET ICON CHECK）；两反斜杠须按两反斜杠匹配（组 112）。
- api_*.html=1370 条索引；无：GetDifficultyColor（有垫片）/PlaySoundFile（只有 PlaySound）/hooksecurefunc/UIDropDownMenu_GetSelectedID；有：GetGuildRosterInfo/GetWhoInfo/GetFriendInfo/GetNumGuildMembers/GetNumWhoResults/GetNumFriends/GuildControlGetNumRanks/GetRealZoneText/RemoveChatWindowMessages。

- ★★★**跨插件：捕获 UnrealQuest 的稀有提醒**（1.74.23，用户「只要知道他发现稀有的那一时刻，在对话框内输出一段文字」）：
  弹窗唯一出口 = `World/RareAlert.lua` 的 `RareAlert:Show(entry, distance, dx, dy, others)`（内部 `SetAlertWindowText → UpdateArrow → Client.ShowObject → shownUntil → 音 → 聊天 → 计数`）
  ⇒ **包住它、在返回后回调 = 卡片已经在屏幕上的那一刻**。模块注册表是**公开**的：全局 `UnrealQuest`（`Core/Namespace.lua:17`）+ `UnrealQuest:GetModule("RareAlert")`（就是 `UQ.modules[name]` 那张**普通表**，`NewModule` 只塞 name/enabled、无元表保护）；
  ★**安装必须等 VARIABLES_LOADED**（AddOns 按目录名排序，**EvalHelp(E) 先于 UnrealQuest(U)**，载入期拿不到对方 —— 与 DataSearch 的 `dsUQModule` 同因；那个是文件内 local，本处提成全局 `EVAL_UQ_MODULE`）；
  ★包装纪律 = **返回值逐个透传 + 原函数抛错照原样 `error(a,0)` 抛出**（吞掉别人的错 = 把别人的 bug 藏起来），只在抛错时如实计数；
  兜底 = `Show` 不可包时轮询对方**公开读值口** `RareAlert:GetStatus().alerts`（单调累计计数；**首读只立基准**，否则会把本次登录前的历史计数当成刚弹过）；兜底 tick 父级必须是 **WorldFrame**（挂 UIParent 开全屏地图会停摆，见 1.70.39）；
  载荷：名字走 `Database:GetUnitName(entry.unitId)`、品阶 `entry.rank`（1 精英/2 稀有精英/3 首领/4 稀有）、`distance` 已是整码、`others` = 同刻另有几只；频率上对方自带「同怪 180s 冷却 + inRange 抖动带」，不会刷屏；
  命令 `/eh go 稀有`（状态/开/关/试；`试` 直接调对方 `TestNearest` 走完整链路自证）；判据 = 组 199 + 源码检查 `RARE WATCH WIRING CHECK`（安装点 / 命令前缀字节数 / 包装透传与照抛 / 兜底 tick 父级）
  染色（**1.74.24** 用户「对稀有精英染色」）：名字按品阶上色（精英 银 c0c0c0 · 稀有 蓝 0070dd · 稀有精英 紫 a335ee · 首领 橙 ff8000 —— 物品品质那套玩家一眼就懂；与「方案品阶」五色是**两个维度**，项目纪律要求错开，故最低档用银不用白）；★**整条消息只许一段 8 位色码**（一条多段会整条不画）⇒ 色码由调用方按品阶给，语言包里不再写死金。
  可点（**1.74.24 → 1.74.26** 用户「点击他可以定位目标」＋「点击头像相当于目标切换到稀有精英目标」＋定案原话「点击名字逻辑很简单.不要和那边插件的机制管理.需求只要是调用类似目标函数选中目标就可以了.如果目标不存在就报错.」）：名字做成链接 `|c..|HEHRW:<名字>|h[名]|h|r`（形态照抄分享封皮那条真机配方：色码在外、链接在里）⇒ **点名字 = 一次 `TargetByName(名字)`**，选中报「已选中目标：X」、选不中报「选不中目标：X」—— **就这一个动作，没有第二动作、没有退路**。★1.74.26 按用户定案**删掉**了所有与那边插件机制的耦合：不再有坐标 / 最近刷新点 / 地图投影 / `EVAL_DS_SHOWMAP` 开图；token 从 `EHRW:areaId:x:y:unitId` 收成 `EHRW:<名字>`（名字是唯一需要的东西）—— 源码检查现在**反向守**：稀有转播里出现 `EVAL_DS_SHOWMAP`/`EVAL_RW_NEAREST_LOC`/`GetCurrentZoneView` 即 FAIL。
  ★★★**1.74.27 提取为独立模块 + 工具箱开关**（用户：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」）：整块搬到 `tools/RareWatch.lua`（**主文件只留两个接线点**：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)`、命令分支 `/eh go 稀有`）；新模块只走**全局桥**（`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`/`rawget(_G,"EVAL_HELP_CONFIG")`），绝不引用主程序文件内 local；工具箱新增「稀有提醒」组 + 开关（Toolbox 的 `t="rw"` 行型）——★**读写走实现自己的单一来源** `EVAL_RW_ENABLED`/`EVAL_RW_SET`，不另存 `tb.rareWatch`（两处真值必然打架）；★工具箱模型 28 条 > 每页容量 26 ⇒ **第 2 页**，判据必须翻页后取控件（`EVAL_TB_TEST_SCROLL_CLICK("dn")` + 新读值口 `EVAL_TEST_TB_CHK_FOR`）；★**新增文件要同步 7 处清单**：toc / 测试载入清单 / DECL ORDER / LANG KEY / COMMENT SWALLOW / WHEEL / COLOR CODE LEN / FRAME NAME CLASH（漏一处就是「新文件永远不被检查」的静默盲区），打包基准 68 → 69（参考卷）；`RARE WATCH WIRING CHECK` 改成**分两段扫**（接线点看主文件、实现模式看两份并集）。判据 = 组 120⑥ + 组 199。
  ★`TargetByName`：**官方 API 索引里有**（category=Targetting），且**不是 Protected**（参考卷 §F3:138 逐条核过）；但它在「附近没有这只」时**静默失败**（官方文档明文「只认附近单位」，`Engine.lua:735-736` 早已记过）⇒ **必须核对结果**：调用后读一次 `UnitName("target")`（否则「点了没反应」会被报成成功）。★对方 RareAlert **明确不做**这件事（自动扫描会抢玩家目标，RareAlert.lua:23-27 有明文），我们只在**玩家主动点一下**时做。
  ★★★**1.74.25 实锤（用户截图，这是本条最重要的事实）**：截图上任务插件导航箭头显示那只稀有在 **556 码**外，而我们写的文案是「它没刷 / 它不在这儿」→ **真因是客户端限制**：`TargetByName` **只认客户端附近的单位**，远处**静默失败**（官方文档 `Targetting#targetbyname` 明文；本项目 `Engine.lua:735-736`、参考卷 §F3 早已记过；参考卷 §F3:138 还确认它**不是** Protected —— 所以「切不到」≠「调用非法」）。
  ★★教训 = **「把自己的限制说成对方/世界的状态」是造谣**：`选不到「X」` 必须**同时报出距离**（`约 N 码`，取转播时对方给的那个数）+ 给出下一步（走近再点 / 右键地图定位），并且**一句话说完**（上一版太长，被聊天框折成两行 —— 截图可见）。反向哨兵：文案里绝不许再出现「它没刷」。
  ★取证命令 `/eh go 稀有 目标探针`：拿**当前目标自己的名字**（必然存在且必然在附近）——先 `ClearTarget()` 再按名字选回来，报 4 步判定。**这是唯一能区分**「客户端只认附近」与「TargetByName 对本插件是空操作」的实验（两者从结果上长得一模一样）；顺带打印库里那份名字与**字节数**，排掉「库名 ≠ 客户端名」这第三种可能。判据 = 组 199⑫（含「它没刷」反向哨兵 + 距离必须出现）与 ⑯。
  ★链接的失败模式是「**整条不画**」⇒ 留了 `稀有 链接` 开关，一键退回**已验证的「只有色码」形态**；命令 `/eh go 稀有 目标|链接|目标探针`；判据 = 组 199⑩~⑯ + `RARE WATCH WIRING CHECK`（4 色逐项 8 位 · 链接**只带名字** · Toolbox 的 `EHRW:` 分派**必须以该语句开头** —— 只查「文件里出现过这串」会被 `if false and …` 骗过，本轮变异测当场撞到 · **反向守**不许再耦合地图机制）。
## 十一、记忆体写入 / 上下文成本实测（1.74.9）

> 常驻卷会随会话反复注入 ⇒「怎么写记忆体」本身就是成本。本节存**实测数据 + 度量方法 + 搬迁套路**（常驻卷只留一句话纪律）。

### 11.1 成本实测（会话 session-3b7c5d3f，5,178 条记录）
- 磁盘日志 6.31 MB（zstd）→ 展开 **19.26 M 字符**；压缩帧 **1,924 个**；JSONL 记录 5,178 条。
- **整份 `CLAUDE.md` 被注入 45 次**（单份解码文本 ≈2.4 万字符 ≈1.5 万 tokens）——每次文件变更都会再注入一份整卷。
- 上次压缩后活动窗口（1,945,361 字符，模型可见）构成：`assistant/message` **66%**（长回复 + `run_code` 脚本正文）· `user/message` + `agent/inbox/spliced` **19%**（注入类）· `tool/call` + `tool/result` **12%**。
- ⇒ **最省的两刀**：① 大段脚本写文件再 `node`（**别塞进 `run_code.code`**）；② 记忆体改动**批量化**、明细进参考卷。

### 11.2 怎么量上下文（别凭感觉）
- 日志路径：`<DSH_HOME>\sessions\--<规范化 cwd>--\<session-id>\session.v3.jsonl.zstd`（本机 `DSH_HOME=C:\Users\EVAL\.dsh`）。
- `request/context` 事件 = **窗口声明**（`contextWindow`）；`compaction/summary` 的 `usage.cacheReadTokens` = **压缩那一刻的真实 prompt**，`shadowedTokenCount` = 被压掉的量。
- 实测：3 次压缩的真实 prompt **393,472 / 393,984 / 446,336** tokens，都在窗口的 **56%~64%** 触发（窗口当时声明 700,000；最新一次请求已声明 1,000,000）。
- **校准法**：把某次压缩之前的可见记录估一遍（CJK×0.95 + 非 CJK÷3.8），与真实 `cacheReadTokens` 相除 —— 干净窗口比例 ≈ **0.61**，据此折算当前窗口的真实量级（实测当前 ≈**40 万** tokens，不是 700k）。
- ★**坑**：`.jsonl.zstd` 是**多帧 zstd 拼接**；Node 的 `zstdDecompressSync` **只解第一帧**（流式解码器读到第二帧报 `Unknown frame descriptor`）⇒ 按 magic `28 B5 2F FD` 扫描切片、逐帧解再拼。

### 11.3 常驻卷瘦身套路（1.74.9 实战：86,364 → 62,810 字节，再补纪律后 63,984）
1. node 统计**每节字节数**（按 `^#{2,3} ` 切段）→ 挑最大的几节下手。
2. node 脚本按**标题锚点**取整段（`findOne` 断言命中唯一、`secEnd` 找下一个标题），**原文照存**追加到参考卷新编号节（§十），常驻卷原地换成「索引 + 铁律 + CHECK 名」。
3. 锚点命中数 ≠1 直接 `exit 2`；替换**从后往前**做，行号不漂移。
4. 常驻卷补**指向新节的索引**（顶部导览 + 末节「什么时候必须去读参考卷」）。
5. 跑 `node luacheck.js` + `node test_engine.js`：★`PACK LIST CHECK` 从**参考卷**读第 9 步打包清单 ⇒ 新节必须**追加在它之后**（本次追加在 §九、§十 之后，检查仍绿）。
6. **一次 commit**（别边改边提交，避免整卷被反复注入）。
