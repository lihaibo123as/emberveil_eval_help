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
# quest/ 只拷插件要用的三个 .lua（fetch.js/sweep*.js/build*.js/audit.js/chains.js 是开发脚本、cache/ 是抓取缓存，都不进包）
New-Item -ItemType Directory -Force "$staging\EvalHelp\quest" | Out-Null
Copy-Item "$src\quest\QuestData.lua","$src\quest\QuestBulk.lua","$src\quest\QuestChains.lua" "$staging\EvalHelp\quest\"
Remove-Item "$staging\EvalHelp\media\Textures" -Recurse -Force -ErrorAction SilentlyContinue  # 主题素材不进包
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $out)
Remove-Item $staging -Recurse -Force
```
★**装完必须核对条目数**（1.75.1 基准 = **75 个**：+`quest/QuestData.lua`、`quest/QuestBulk.lua`、`quest/QuestChains.lua`（1.75.9 新增 QuestBulk = 全量任务/装备数据）；1.74.34 时是 72（+`tools/LayerFix.lua` 图层特殊处理独立模块）；1.74.30 时是 71（+`tools/DragFrames.lua` 框拖拽从子插件搬进工具模块）；1.74.29 时是 70；1.74.27 时是 69（+`tools/RareWatch.lua`）；1.74.12 时是 68、1.74.6 时是 66、1.73.5 时是 63；1.74.5 陆续加了 `tools/IconGrid.lua` / `tools/HunterHelper.lua` / `tools/ConsumableHelper.lua`，1.74.7 加 `tools/DismountHelper.lua`）：
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
- ★★★1.74.30 **不许把「不确定存在」的 API 当兜底**：先查索引/参考实现，没有就整条别写（`type(X)=="function"` 守卫在**不存在**时是死代码、在**存在但说假话**时更坏——一次误判就把功能掐断）。真要用 → **自校准**：在「状态确定的那一刻」（如 OnMouseDown 时左键必然按着）探一次，返回值不成立就**永久弃用这一层**并如实记录（框拖拽的 `IsMouseButtonDown`/`GetMouseFocus` 两层都这么做，组 202 ⑥a~⑥d 钉住）。
- ★★★1.74.30 **`ClearAllPoints` 之后位置就是 (0,0) = 父级左下角**（官方 wiki Region:ClearAllPoints 明文；SetPoint 条目又写明「新建帧有一个默认 BOTTOMLEFT 种子」）⇒ 看到「窗口/控件贴屏幕左下角」= **清锚点成功、SetPoint 没生效**。纪律：① 别把 SetPoint 包在 `pcall` 里**静默吞掉**结果；② 设完**读回自证**（`GetNumPoints` ≥ 1 + `GetPoint(1)` 的点名/偏移对得上）；③ 要有兜底路径（改用**父级相对**锚点，别跨父级指 UIParent）。

### F. 本客户端 API / 素材的真伪清单（用前必查，别按命名习惯猜）
- **`WorldMapFrame:IsShown()` 两个方向都会撒谎**（可能恒 false，关图后也可能恒 true）→ **绝不进分支**；判「有没有可标注视图」只用 `MapContext:GetViewedZone()` 的 `zoneIndex==0 → continentView`；开图一律 `ShowUIPanel`，**绝不 Toggle**。
- **`UnitBuff`/`UnitDebuff` 只有图标+层数、没有时长**；只有自身光环能查 `GetPlayerBuffTimeLeft`，**它返回 0 = 无限/无数据（不是 0 秒）**。
- **`UnitCreatureType` 返回带后缀的本地化名**（「人型生物」）→ 匹配要剥掉「生物」再比。
- **无 CombatLog API、无免疫查询函数、无 `UnitCastingInfo`、无 SuperWoW**（精确距离/挥击计时做不了）。
- ★★★1.74.30 **没有 `IsMouseButtonDown`**（API 索引 1328 条唯一函数名里查无；整个游戏 AddOns 目录除本插件自己的引用外**零出现**）→ 鼠标按键兜底只能靠 `OnMouseUp` / `OnDragStop`(**真机未证实收得到**：拖动配方要 SetMovable+StartMoving)/ `GetMouseFocus()`(**有**，但要自校准) / 自制**全屏接盘**（拖拽期间 Show 一个吃鼠标的 Button，松手无论指针在哪都收得到 —— UnrealQuest 的筛选菜单同款）/ 超时无位移自动结束。
- ★★1.74.30 **`GetPoint` 的第 2 个返回值是相对帧的「名字字符串」（不是帧对象；父级锚点无名时给 `"auto"`），且它与 `SetPoint` 传参的 y 偏移符号口径有歧义**（wiki 说内部存储取反；UnrealQuest 2026-09-17 定点探针在 UIParent 同名锚点上量到 18/18 同号）⇒ **绝不把 `GetPoint` 的偏移回灌给 `SetPoint`**（回读→加增量→回写会累积成镜像/漂移）。正解 = 用**测量边**（`GetLeft/GetBottom/GetWidth/GetHeight`，UI 像素、原点左下、Y 向上）构造偏移，`GetPoint` 只用来读**点名与相对帧名字**。

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
- **当前版本（源码唯一真值）**：`EvalHelp.lua` 的 `local VERSION` == `EvalHelp.toc` 的 `## Version` = **1.75.2**（v1.75.1 已发布）
  （已发布；`CHANGELOG.md` 最新小节 v1.74.0 已把 **1.73.35 ~ 1.74.0**（85 个提交）归纳成 7 条里程碑）。
  ★1.73.35~1.73.67 那批工作（分享封皮/品阶评分/头衔抽卡/彩蛋/角色扮演反应/标题栏徽标/取证探针）已随 **v1.74.0** 一起发布。
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

1. **1.75.1** — 🔀 **两支合流 + 图层拖拽宽高只给聊天窗 + 宠物动作条**：`probe/map-scale`（框拖拽 / 图层工具 / 缩放大地图）与任务线两支**合流到 master**（5 处冲突逐条审过、3 个合并副作用修净：OnUpdate 真零形参 · `EVAL_HH_PETDECOR` 补 `hhHasPet()` 门 · 参考卷打包脚本补回 quest/ 三行），并立新铁律 **`TEST LOAD ORDER CHECK`**（harness 里 `test_assert.lua` 必须排在所有 `tools/*.lua` 之后 —— 工具模块在**载入期**自登记 `EVAL_TB_MOD_ROWS`，顺序反了组 200 会「模块完全正常却 got=false」）。
  ★★★**图层拖拽：宽/高只对「聊天窗」开放 + 持久化**（用户第三次改口径，1.74.33 的「所有窗口都不给」收窄）：唯一真值 `dfSizeOK`（`^ChatFrame%d+$`，**全项目只许出现一次**）⇒ 目标表项 `noSize` 现算；属性弹窗对聊天窗**建并显示**宽/高两行 + 窗高 224→280，其余窗口 **Hide** 两行并收回窗高（**不是灰掉**）；保存**先抓原值 → 再写新值**（反了等于没还原），落存档 `w/h/ow/oh` ⇒ 重登/应用存档写回；启动清理**只清 `noSize == true`** 的目标，聊天窗的 w/h 一个字段都不动。
  ★**常驻层补「宠物动作条」**：`DF_TARGETS` 新增 `PetActionBarFrame`（候选名解析，同动作条1~4）；★按需出现（没宠物时不在）⇒ 进 `DF_ROSTER_EVENTS` 的**有界跟随**，事件 `UNIT_PET`（有本地证据），★`PET_BAR_UPDATE` 零证据 **不注册**；跟满 `DF_ROSTER_TRIES` 即停。
  ★**口径更名**：「全职业**施法**工具」→「**全职业工具**」（Core / EvalHelp.toc(Title+Notes) / 三语言包 `CFG_TITLE`·`MB_TIP_TITLE` / 三语 README / DEVELOPMENT 一起改），Tab4「数据检索」→「**任务线 & 装备**」（`TAB_DS` + 页内六处文案；Tab 宽 74/78 → **84/88**，7 个 Tab 仍在一行 624 ≤ 660）。
  ★猎人助手提示行收成唯一来源 `EVAL_HH_TIP_LINES()`：没选喂养技能由「未识别」改成**明确提示 + 警示色**（与「食物：未设置」同形）。判据 = 组 207/208 + **新增组 227** + `DF OPEN HOOK CHECK` 四道哨兵。
2. **1.75.0** — 🧭 **数据检索新增「任务线」+ 地图标注右侧的「任务线推荐」弹窗**（`quest/` 独立目录）：**最终口径（数字一律从数据现算）** —— 策展经典链 **62** 条 + 自动任务线 **611** 条（**界面合计 673** 条 · ≥10 步 18 · 开门/史诗 17 · 最长 24 步）+ 全量 **751** 条带装备奖励任务 / **1262** 件物品（装备视图列出 **990** 件），覆盖 **4-60 级**，逐条抓自 `database.emberveil.org`（★首版 22 链 / 88 任务 / 62 奖励已被 1.75.9 全量采集取代）；**奖励优先**（精良武器排最前）+ **完整上下级步骤**；奖励行悬停出原生物品详情、步骤行点击进任务详情；抓取脚本（`fetch.js`/`chains.js`/`build.js`）**与插件零耦合**；数据自带 ⇒ **UnrealQuest 缺席照样能查**；★**弹窗 v2**（数据检索 · 地图标注右侧）：**装备优先**（按可获得等级列装备 + 真实物品图标 → 点装备**反查来源任务线**与完整步骤 → **[在数据检索中查询]** 直连 `EVAL_DS_SEARCH_NAME`）+ 两个视图 Tab（装备/任务线）+ 9 行分页列表 + ▲▼/滚轮 + 四档筛选（等级/类型/档位/阵营）+ 拖动柄；默认关、OnHide 收下拉。
  ★1.75.7 调（用户要求「将返回放置在下一页右边 · 整体按钮左对齐」）：底部按钮顺序改为 **[上页] [下页] [← 返回]** —— 按钮组起点 `QP_NAV_X = QP_PAD`（整体左对齐），返回按钮 x = `QP_NAV_X + (QP_BTN_W + QP_BTN_GAP) * 2`（第三位）。判据 = CHECK（按钮组起点 = 内边距 + 返回必须在第三位）+ 组 192 ⑧h（读真控件 `GetLeft` 验 x 递增；桩不返回几何就如实降级由 CHECK 守）。变异 M14 捕获。
★1.75.6 修（用户截图「样式有点重叠」）：详情**标题压住副标题** —— 根因 = 标题用 `SetPoint("LEFT", qpDetIcon, "RIGHT")` 锚在 **36 高**的大图标上 = **垂直居中**（≈ y −74），而副标题正好也在 −74 ⇒ 必然压字。正解 = 两者都以**图标右上角**为锚、**垂直依次排**（标题 −2 · 副标题 −20），字号/语言变化都不会再压。判据 = `QUEST PANEL CHECK`（钉锚点写法 + **禁**旧的 `LEFT` 写法）+ 组 192 ⑧i（读 `GetTop` 验几何；**桩不支持就如实降级**，绝不假红）。
★1.75.5 修（用户截图「底部按钮不见了」）：翻页按钮**同时进了 listWidgets 与 detWidgets 两份互斥清单** ⇒ `qpShowView` 先 Show（list）后 Hide（det），列表视图下**整个消失**。正解 = **不进任何互斥清单**，由 `qpShowView` **末尾显式 Show**（两视图都常显、位置不跳）。★★可见性契约的又一实例：**同一控件只能属于一份显隐清单**；判据补 CHECK（禁进互斥清单 + 必须显式 Show）与组 192 ⑧h（**两视图下翻页按钮都必须可见** —— 这正是漏过的那条：只验了「详情控件在列表视图要隐藏」，没验「列表自己的按钮要显示」）。变异 M13 捕获。
★1.75.4 追加（用户要求，三条）：① 翻页**不用图标**，改**文字按钮 [上一页][下一页]**（复用图标库 `IB_PREV`/`IB_NEXT` 键），放**底部 [返回] 旁边左对齐**（位置由 `QP_NAV_X = QP_PAD + 64 + QP_BTN_GAP` 单一来源算）；② **焦点离开必须隐藏装备信息**（旧实现 `OnLeave` 只复原底色 ⇒ 原生 tooltip 残留）；③ **详情大图标可获取焦点并显示装备信息**（Texture 收不到鼠标 ⇒ 加了 36×36 的覆盖 Button）。★顺带修：`EVAL_QP_SHOW` 从不调 `qpShowView` ⇒ **首次打开**时详情专用控件（返回/大图标/数据检索钮）在列表视图里露着（用户截图里正是这个）。变异 M12（翻页改回图标式）被 CHECK 捕获。
★1.75.3 追加（用户要求，三条）：① **滚动区铺满窗口** —— 行数**按窗口高度现算**（纯函数 `EVAL_QP_ROWS_FOR(h, top, rowH, tail)`，17 行/页），**禁写死**（图标库那种 `IB_ROWS = 9` 照搬会留白，用户在图 3 圈出）；② 装备详情 **36×36 大图标 + 12 号大标题（品质色）+ 副标题（属性）**，图标仍只取 `GetItemInfo`；③ 放大镜素材换成**本插件自带** `Interface\AddOns\EvalHelp\media\icons\database`（与图标库同款），点击后**不关窗**，只回执一行「已送数据检索：<任务名>」（★旧判据「点完应收起」已按要求**反转**成「必须仍在显示」）。变异 M10（又关窗）/M11（行数写死）均捕获。
★1.75.1 追加（用户要求）：**阵营严格三分类**（联盟/部落/共有 —— 旧写法把「共有」并进联盟/部落，`c.f ~= "B"` 那半句已删）；**每个任务节点左侧放大镜**（素材 `INV_Misc_Spyglass_01_TEX`，与 PetHelper 同源；点了按**任务名**（不是链名）走 `EVAL_DS_SEARCH_NAME` 直达数据检索）；装备视图三个筛选（等级/类型/阵营）⇒ 读值口 `EVAL_QP_SET_FILTER(a,b,c)` 三参。
  ★v1 事故（务必记住）：`local b = dsBtn(..., function() b.btn ... end)` 里的 b 是**全局 nil**（local 作用域从声明之后开始）→ 点按钮当场红字；另有「label 传空串 = 空白按钮」「详情行压住底部按钮」两处 UI 事故 —— 判据分别落在 `QUEST PANEL CHECK`（自引用检测/空白按钮检测/**布局重叠独立验算**）与组 192。变异 M3/M4/M5/M7 全捕获。
3. **1.74.30** — ⏱️ **射击计时 + 条件「距下次射击」**：探针真机定案（法术频道含「自动射击」的原文 = 锚点、`UnitRangedDamage[1]` = 射速 2.09s，与近战**双锚点互不干扰**）；数值条件 `shotLeft`（文本 `距射击<0.5`、初始值 0）；修「切换条件类型把 30.0 带进时间型」；消耗品助手左键不再弹窗。
4. **1.74.29** — 🖼️ 战斗UI **激活方案格品阶色边框** + 两个助手弹窗候选**原生物品详情** + 喂食助手 `GetPetHappiness()` **快乐度边框**（开心亮绿 / 一般金 / 不开心红 / 无宠物默认金）。
5. **1.74.28** — 🧺 两个助手弹窗候选**按物品类型过滤**（品质 → `GetItemInfo(链接)` → **自建 tooltip 兜底并自愈客户端缓存**；药草矿物材料等全剔，判不出不剔）+ 验证命令。
6. **1.74.27** — 🧹 稀有提醒转播**提取为独立模块** `tools/RareWatch.lua`（主程序只留两个接线点）+ **工具箱开关**（打包基准 69）。
7. **1.74.26** — 🧹 点名字**只做一件事**：`TargetByName(名字)` 选中它，选不中**就报错**；删掉所有与任务插件机制的耦合。
8. **1.74.25** — 📏 切目标文案纠错（真因 = 客户端只认附近单位）+ 目标探针。
9. **1.74.24** — 🎨 稀有提醒名字按**品阶染色** + 可点链接。
10. **1.74.23** — 🔔 **稀有提醒转播**：包住 UnrealQuest 弹窗唯一出口 `RareAlert:Show`。

> ★**分支内版本号 ≠ 发布版本号**：任务线那批在 `probe/map-scale` 上曾用 1.75.3~1.75.21 编号，合并后**统一收进 1.75.0 发布**；发布版本只有 **1.75.0 / 1.75.1**，其它 1.75.x 数字只存在于 CHANGELOG 细则与提交史里。
## 十、常驻卷瘦身移出（1.74.9 审计 · 原文照存）

> ★1.75.1 合并说明：本节是 **1.74.9 时代**的「原文照存」快照；同名主题在**附录 R9~R16** 里已按 1.74.32+ 的口径重新整编。本节**整段保留**（含 `§十四` 任务线数据来源明细 —— 常驻卷 §5.5 任务线条目写的就是「明细 → 参考卷 §十四」），用于查**当时的逐字原文**。

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

## 十二、1.74.29 / 1.74.30 明细（射击计时 · UI 三处补完 · 条件与继承修复）

> 常驻卷只留一句铁律与索引；本节是**全部细节与数据**（探针实测量、跳过的坑、判据与变异编号）。

### 12.1 射击计时（探针真机定案）
- 探针：`/eh go 射击探针`（开/关/报告/清空），报告**同时落盘**（`[射击探针]` 进 SavedVariables ⇒ 事后直接读文件，不用截图）。
- **实测数据**（8 发干净样本）：`UnitRangedDamage(player)` → [1]=2.09（秒/击）· [2]=18.59 / [3]=21.59（伤害上下限，差 3.0 = 弹药）· [4][5][6]=0/0/1（噪声，比值表排除）；`UnitAttackSpeed` 主手 3.20 副手 2；`IsAutoRepeatAction(slot 9)` 可用。
- **锚点通道** = `CHAT_MSG_SPELL_SELF_DAMAGE`，原文「你的自动射击击中X造成17点伤害。」/**暴击**「你的自动射击对X造成30的致命一击伤害。」⇒ 判据只认「自动射击 / Auto Shot」子串。
- **Δt 样本**：2.22/2.13/2.04/2.33/2.03/2.13/2.23 → 均值 2.16 vs API 2.09 = 比值 **1.03** ⇒ 本轮**未观测到**急速差异（首个 1.82 的单样本假象被推翻，故未硬编系数）。
- **自校准**：留最近 6 次 (Δt÷API) 中位数；样本 ≥4 且中位数出 [0.9,1.1] 才修正，否则用 API 原值；离群样本（<0.5× 或 >1.5×）丢弃。
- **状态感知单入口**：`EVAL_SWING_KIND/SPEED/REMAIN_ACTIVE`（自动射击中 → 射击）；战斗UI 金色细条、状态UI 行、条件 `swingLeft` 全部自动跟随；文案分「下次射击 / 下次攻击」。
- **新条件 `shotLeft`**：文本 token「距射击」（也认「距下次射击」/`shotLeft`）、编辑窗名 `CT_SHOTLEFT`（三语）、时间型（0.1 步进 / 0~10）、初始值 **0**；与 `swingLeft` 成对但**显式**（不走状态感知）。
- **继承修复**：旧 `new.op, new.n = old.op, old.n` 无条件继承 ⇒ 从「能量>30」切到时间型会带进 30.0；改为纯函数 `seSwitchCond`：**同参数域才继承 n**（op 始终继承），并顺手把时间型清单变单一来源 `SE_TIME_K`/`seIsTimeKind` 且**上移到使用者之前**（原位置在使用者之后 = 闭包只看到全局 nil）。
- **坑记录**：`DECL ORDER CHECK` 当场抓到读值口 `EVAL_TEST_SE_TYPE_INIT` 写在 `SE_TYPES` 声明之前（真机上是全局 nil）→ 已挪到声明之后。

### 12.2 UI 三处补完
- 战斗UI 激活方案格：`uiProfBtnBorder` + BUILD 建 4 条 1px BORDER 纹理；只有激活格 Show；颜色与文字同源（品阶色，算不出暖金）。
- 弹窗候选（`tools/IconGrid.lua` 共用件）：悬停先 `SetBagItem(bag,slot)` 出原生 tooltip，再补「名称 ×数量 [包,格]」+ 提示 + 已选角标；拿不到 bag/slot 退回文本。
- 喂食助手快乐度边框：复用主图标**既有 4 条 1px 亮边**（`HH.edges`），颜色按 `GetPetHappiness()` 现算：3=亮绿 / 2=金 / 1=红 / 无宠物或接口不可用=默认金；只在建帧/刷新/CD tick/悬停时现算（不新开后台 tick）。
- 消耗品助手左键取消弹窗：面板入口收归右键（左键与「拖动图标」争用同一按键），三语 `CH_MAIN_HINT` 同步。

### 12.3 判据与变异（本轮）
- 组 188 ①~⑦（激活边框 · 物品详情 tooltip · 快乐度边框 · 射击计时 · 距下次射击条件 · 类型切换继承）· 组 177 左键反向哨兵。
- 变异：M1 边框着色 · M2 横排 SetBagItem · M3 候选格 SetBagItem · M4 开心→金色 · M5 探针开关 · M6 「自动射击」守卫 · M7 自校准 · M8 初始值 · M9 无数据守卫 · M10 跨域继承 · M11 左键弹窗 —— **11/11 全捕获**。

## 十三、1.74.31 载入审计（阶段 0 探针 + 阶段 1 零风险清理）与 OnUpdate 零参数事故

### 13.1 OnUpdate 零参数（真机炸点 · 用户截图定案）
- **现场**：`EvalHelp.lua:9495: attempt to index local 'f' (a nil value)`，栈顶 `function <...:9494>` ——
  载入报告帧写成 `frame:SetScript("OnUpdate", function(f) pcall(f.SetScript, f, "OnUpdate", nil) ... end)`。
- **根因**：**本客户端调 OnUpdate 时一个参数都不传**（f = nil）。全项目另外 13 处 OnUpdate 注册全是 `function()`，
  只有这一处抄了「`this` 作第一参」的老写法 ⇒ 每帧报错，**载入报告一行都打不出来**（阶段 0 的读数因此一直没拿到）。
- **修法**：帧引用用**外层 `local lf` 捕获**，回调写成 `function()`；摘钩子 `lf:SetScript("OnUpdate", nil)`。
- **判据**：源码检查 **`ONUPDATE ARG CHECK`**（扫 toc 列出的全部模块：匿名回调 `function(<非空参数>)`、
  具名回调 `function name(<非空参数>)` 一律 FAIL；注册点 < 10 处也 FAIL —— 正则失效时必须吵，不能静默放行）
  ＋ 组 190⑦（`GetScript("OnUpdate")` 取**真回调**、**零参数**调一次：不许报错 · 必须打出 `[载入]` · 报完即摘）。
- **变异**：M16（把 `function(f)` 放回去）→ 源码检查 FAIL ＋ 组 190⑦ `ASSERT FAIL`（err 原文正是真机那句，exit 1）；
  M17（给 HunterHelper 的 OnUpdate 加 `self` 参数）→ 源码检查抓到**另一个文件**的同类风险。
- ★**纪律**：`OnEvent` 的参数三态（第 1 参 / 第 2 参 / 全局 `event`）能兼容，`OnUpdate` **不能** —— 它就是零参数。

### 13.2 阶段 0：载入耗时探针（Core.lua）
- `EVAL_LOAD_T0`（`Locales/zhCN.lua` **第 1 行**）＝插件开始加载的时刻；`Core.lua` 尾部：`LOADM`（`t0/files/vars/init`）·
  `EVAL_LOAD_PROBE_KEYS()`（`iconDump/shProbe/shVariantProbe/probeEvents` 四键，唯一来源）· `EVAL_LOAD_MARK(what)`（`t0` 显式重读起点）·
  `EVAL_PROBE_STAMP`（`date("%Y-%m-%d")`）· `EVAL_LOAD_CLEANUP(force)` · `EVAL_LOAD_REPORT(sayFn)` **3 行**：
  源码加载 / SavedVariables 恢复 / 初始化 / 合计 ＋ 顶层键数与最大键 ＋ 本次清理量与下次对比。
- 打点位置：`tools/RareWatch.lua`（toc 最后一个模块）载入完 → `files`；`EvalHelp.lua` 的 `VARIABLES_LOADED` → `vars`；
  **一帧后** `OnUpdate` → `init` 再出报告（不新增事件注册）。
- **阶段 1 零风险清理**：`iconDump` 每次载入一律清；其余探针键**当天不算过期**要保留（非当天才清）；
  `cfg.log` 环形缓冲上限 `EH_LOG_MAX = 300 → 100`（存档体积）；手动入口 `/eh 存档清理`（强制全清）。
- 判据 = 组 190（①~⑦）＋变异 M14（去掉无条件清 iconDump）/ M15（环改回 300）／M16／M17 全捕获。
- ★**为什么先做这两阶段**：用户要求「先分析原因、出方案、待确认」⇒ 阶段 0/1 = **只观测 + 清残渣**，
  零行为风险；**阶段 2**（推迟建帧 / 大表懒建）等两轮 `/reload` 的读数到手再定。
- 存档现状（改造前实测）：`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua` 119 KB
  ＝ iconDump 62 KB ＋ log 25.6 KB ＋ war 18.7 KB ＋ 探针 ≈5.8 KB。

### 13.3 阶段 0 第一次真机读数 ⇒ 探针本身错了（1.74.31 第二版）
- **真机打出来的报告（用户两次 /reload）**：`源码加载 0ms ｜ SavedVariables 恢复 0ms ｜ 初始化 390444014ms ｜ 合计 390444014ms`，
  两次相差 25.5 秒（3904430014 − 3904404490 = 25524ms ≈ 两次 /reload 的真实间隔）。
- **定案**：**本客户端在插件加载阶段 `GetTime()` 恒 0**（进世界才开始走）——
  ① `t0/files/vars` 三点读数都是 0 ⇒ 前两段「0ms」是**假数**（不是"很快"，是量不到）；
  ② `init` 是进世界后的真实时钟 ⇒ 旧公式 `init − t0` 把**游戏运行时长**（39 万秒 ≈ 4.5 天）当成了「初始化耗时」。
- **本客户端只有这几个时间源**（api 索引 1343 条里过滤出来的全部）：`GetTime` · `GetGameTime` · `time`（epoch 秒）· `date`；
  **没有任何 tick/高精度计数器**（无 `GetTickCount`/`debugprofile`）⇒ 载入期的毫秒级计时**目前无解**，
  除非 `GetGameTime` 在载入期就走（第二版探针把三个读数并排打出来就是为了验证这一条）。
- **第二版探针（已实现）**：
  ① `EVAL_LOAD_MARK` 每个打点都记**原始读数**（GetTime / GetGameTime / time / 墙钟 `%H:%M:%S`），`EVAL_LOAD_STATE()` 读值口；
  ② 报告**先判时钟是否启动**（t0/files/vars 任一 GetTime 缺失或 0 ⇒ `dead`）：`dead` 时**如实写「载入期时钟未启动 ⇒ 测不出」**
     ＋ 追加**原始读数行** ＋ **墙钟秒级旁证**（两点同秒 ⇒ 整段载入 < 1 秒），**绝不再打假的 0ms / 39 万 ms**；
  ③ 报告**不再在载入期打**（那时全是 0）：报告帧的 OnUpdate **等 `GetTime() > 0` 的第一帧**才记 `init` 并出报告
     （等于「进世界 → 插件首帧」的真实毫秒），万一一直不可用（停在角色选择界面）最多等 **120 秒**（`time()` 做期限）再如实报告；
  ④ 新增 `PLAYER_ENTERING_WORLD` → `EVAL_LOAD_MARK("world")`（`player` 进世界打点，报告用它算「进世界→首帧」）；
  ⑤ 取证命令 **`/eh 载入报告`**（随时重打，不必 /reload）。
- **判据**：组 190 ⑧（时钟死掉时不许出现 `390444014`／必须写「时钟未启动」／「进世界→首帧」可测／原始读数含 GetGameTime／有墙钟旁证）
  ＋ ⑨（时钟未启动时调真回调**不许**提前报告且**不摘钩**，时钟起来后才报告并摘钩）＋ ⑩（`/eh 载入报告` 入口）。
  变异：**M18**（把 `dead` 分支短路成 `if false`）→ ⑧ 当场 ASSERT FAIL；**M19**（去掉「等时钟」那行）→ ⑨ 当场 ASSERT FAIL。
- ★**顺带确认阶段 1 已生效**：报告里 `iconDump` 已不在存档（62 KB 省掉），
  `SavedVariables 顶层键 28 个；最大键 log（估算 5.9 KB）`（环上限 300 → 100 后只剩 5.9 KB）。
- ★**未决**：载入期毫秒仍测不出（客户端限制）⇒ 阶段 2 的取舍要基于「存档体积 + 墙钟 + 进世界后首帧」这三条证据。

### 13.4 阶段 0 第二次真机读数（1.74.31 第三版）：载入期到底有没有可用时钟
- **用户第二次 /reload 的报告（原文关键行）**：
  `载入期时钟未启动（GetTime() 原始读数 = 0，实测）⇒ 源码/存档两段**测不出**；进世界→首帧 —` ·
  `原始读数 t0/f/v/w/i ｜ GetTime nil/0/0/nil/3904876.377` ·
  `　同序 ｜ GetGameTime nil/6/6/nil/6 ｜ time(秒) nil/1789996554/1789996555/nil/1789996555`
- **定案（三个时间源逐一验完）**：
  | 时间源 | 载入期（files / vars 两点） | 结论 |
  |---|---|---|
  | `GetTime` | `0 / 0` | **载入期恒 0** ⇒ 毫秒级不可测 |
  | `GetGameTime` | `6 / 6`（init 也是 6） | **恒定不动** ⇒ 也不能当时钟 |
  | `time()`（epoch 秒） | `1789996554 / 1789996555` | **载入期真的在走**，但只有 **1 秒分辨率** |
  | `date("%H:%M:%S")` | 同秒级 | 与 `time()` 等价 |
  ⇒ **本客户端载入期没有任何毫秒级时钟**（api 索引 1343 条里已确认没有 tick/高精度计数器）——这是**客户端限制**，不是我们写法问题。
- **第三版探针（已实现）**：
  ① 起点（`Locales/zhCN.lua` 第 1 行）把 `GetTime/GetGameTime/time/date` **四个读数一起采**（存全局），Core.lua 载入时桥接进 `LOAD_RAW.t0`
     —— **必须在第一个文件采**：Core.lua 比它晚载入，那时调不了函数；
  ② 报告加 **墙钟行** ＋ **秒级窗口行**：`time() 差 N 秒`（同秒 ⇒ 这一段 <1 秒；跨秒 ⇒ 至少 1 秒，要继续查），
     且三种读数组合逐一尝试 —— **不许因为缺一个读数就一行不打**（第一次真机就因为起点读数缺，墙钟行整行没打）；
  ③ `GetGameTime` 三处相等时，行尾如实标注 `（GetGameTime 恒 6，不随时间走 ⇒ 不能当时钟）`。
- **判据/变异**：组 190 ①b（起点读数**在第一个文件**就采好）+ ⑧（秒级窗口 / 同秒文案 / GetGameTime 恒定标注 / `time(秒)` 必留）。
  变异 **M20** 去掉 Core 桥接、**M21** 短路秒级窗口行 —— 都当场捕获。
- ★★★**本轮教训（弱判据）**：①b 最初写在 ⑧ 里，而 ⑧ 之前 `②` 已经调过 `EVAL_LOAD_MARK("t0")` **覆写**了 t0 的原始读数
  ⇒ 那条断言**恒为真**、M20 存活（自证式假判据）。**断言必须放在「被测状态尚未被后续步骤覆写」的位置**；
  判据的写法纪律（相对量验相对量）在时间轴上也一样成立。
- ★**下一次要问的问题**：`t0 → vars` 的秒级窗口是 0 秒还是 ≥1 秒 —— 0 秒 ⇒ 插件自己的「编译+恢复」全程 <1 秒，
  「载入慢」不在我们的 Lua 里（阶段 2 拆分/懒建是白费）；≥1 秒 ⇒ 再用同一把尺子做 A/B（临时摘模块看窗口是否变小）。

### 13.5 阶段 0 第三次真机读数（1.74.31 第四版）：把 1 秒分辨率的钟变成可用尺子
- **用户第三次 /reload 的报告（关键行）**：
  `墙钟（秒级旁证）：21:35:50 → 21:35:51` · `秒级窗口：time() 差 1 秒` ·
  `原始读数 t0/f/v/w/i ｜ GetTime 0/0/0/nil/3906072.349` ·
  `　同序 ｜ GetGameTime 6/6/6/nil/6 ｜ time(秒) 1789997750/1789997750/1789997751/nil/1789997751`
- **定案**：
  | 段 | 读数 | 结论 |
  |---|---|---|
  | `t0 → files`（30 模块源码编译+执行） | time 同秒（750 → 750） | **< 1 秒**（上界可用）—— 与离线实测 ≈180 ms 一致 ⇒ **源码编译不是「载入慢」的原因** |
  | `files → vars`（最后模块 → SavedVariables 恢复完） | 750 → 751（跨秒） | **单次定不了量**；两次重载都是跨秒（2/2） |
- ★★★**我犯的措辞错误（已修）**：旧文案写「跨秒 ⇒ 这一段至少 1 秒」——**错**。
  跨秒只说明两点落在不同秒格，**不构成下界**（在边界前 1ms 采样同样跨秒）。
  正确说法 = 「同秒 ⇒ <1 秒（上界）」/「跨秒 ⇒ 单次定不了量」。
- ★★★**正解：抽样平均**（本客户端载入期只有秒级时钟，这是唯一能拿到真值的手段）：
  随机相位下 `E[floor(T2) − floor(T1)] = 真实时长` ⇒ **多次重载求平均秒差就是该段时长的无偏估计**（1 秒分辨率的钟 → 秒级精度的尺子）。
  实现：报告里把 `t0→files`（源码段）与 `files→vars`（存档段）的秒差**累计进 `cfg.loadStat`（写存档）**，并打一行
  `[载入] 秒级抽样 n=N：源码段均 x 秒（跨秒 a）｜ 存档段均 y 秒（跨秒 b）`。
  ⇒ 用户正常玩（每次 /reload 自动记一笔）即可累积样本；**样本够了我可以直接读存档文件**（`%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua`）取统计，不必让用户手工复现。
- **存档现状（实测）**：`EvalHelp.lua` = **51.6 KB**（改造前 119 KB）；`iconDump` 已清、`log` 5.9 KB。
- **判据/变异**：组 190 ⑧b（抽样写进存档 / 报告有抽样行 / 跨秒文案 = 「单次定不了量」/ **禁止**「至少 1 秒」）。
  变异 **M22**（短路抽样块）、**M23**（把措辞改回「至少 1 秒」）—— M23 第一次**存活**，原因：夹具当时 `time()` 两点同秒 ⇒ 报告只走「同秒」分支，
  **那条反向哨兵永远照不到**。修法 = 夹具**必须把被测分支真的走一遍**（让 `files→vars` 跨秒），并加正面断言（必须含「单次定不了量」）；
  重跑 M23 ⇒ 当场捕获。★这是本会话第二次「弱判据」教训（第一次是断言放在被覆写之后）。
- ★**下一版收尾**：取证结束（阶段 2 定案）后，报告要从 6~8 行**精简回 3 行**（原始读数/抽样只在需要时打）。

### 13.6 收尾（1.74.31 定案）：报告精简 + 调试残渣一键清
- **用户定案语**：「优化完成，可以清理调试残留了」⇒ 两件事：**把取证噪音收起来** + **把残渣清干净**（能力保留，噪音清除）。
- **报告分两层**（`EVAL_LOAD_REPORT(sayFn, full)`）：
  · **登录 = 1 行摘要**：`[载入] 源码段均 x 秒 ｜ 存档段均 y 秒（样本 n） ｜ 存档 N 键 / 最大 X ｜ 本次清残渣 k 个`；
  · **`/eh 载入报告`（full=true）= 完整取证**（毫秒段/墙钟/秒级窗口/抽样/原始读数/时间源 dump）；
  · ★**完整取证始终写进调试日志**（聊天只给摘要）⇒ 需要深挖时 `/eh logdump` 也拿得到，不必重载。
- **调试残渣清单一处真源**：`LOAD_RESIDUE_KEYS`（Core.lua）= `probeLog` · `shColorProbe` · `shTitleColorProbe` · `shareIconProbe` ·
  `shareProbe` · `shareProbeHover` · `shareProbeRaw` · `shareProbeVerdicts` · `shareSealDemo` · `shareCreatorOpen` · `loadStat` · `guideSeen`（废弃键）。
  ★判据：**只有 `force`（`/eh 存档清理`）才清**——它们是若干判据的「落盘证人」（自动清掉 = 「事后读回来」的能力无声消失）；
  ★★**真状态键绝不进这个清单**（`ds/tb/war/ui/title/share/log/st/…` 删了就是丢用户配置）。
  ★`LOAD_PROBE_KEYS`（4 个探针数据键）维持原规则：`iconDump` 一律清、其余非当天才清。
- **判据/变异**：组 190 ⑪（默认只 1 行；`full=true` 仍给完整取证）、⑫（非强制**不碰**残渣键、force 一次清干净、清单 ≥8 项）；
  ③ 的期望值从「恰好 4」放宽为「≥4 且 4 个探针键确实消失」（force 现在连残渣一起清）。
  变异 **M24**（force 不清残渣）→ ⑫ 当场捕获；**M25**（非 force 也清残渣）→ **更早的组**（「秘籍样例」以落盘字段为证）当场捕获 ——
  正好证明「残渣键是判据的证人」这条设计理由。
- **工作区清理**：仓库根目录的 `dbg_*.lua`（10 个，历史遗留的一次性调试脚本）与 `CLAUDE.md.bak` 已**搬进 `.dsh/debug-residue-20260922/`**
  （`.dsh/` 在 `.gitignore` 里）——游戏 AddOns 目录因此干净，且随时可翻回来。
- **用户机上还需执行一次**：`/eh 存档清理`（清掉当前存档里已存在的残渣键；`loadStat` 会随之清零，下次登录继续累计）。

## 十四、任务线数据来源（1.75.1）与物品类型过滤明细（1.74.28 原文照存）

### 14.1 ★任务线检索依据 = `https://database.emberveil.org/quests`（用户 1.75.1 明确「记住任务线的检索依据…数据为准」）

- **唯一真值来源**：EmberVeil 官方数据库 `https://database.emberveil.org/quests`。任务线、任务节点、等级、阵营、奖励物品**全部以该站页面为准** —— 不凭记忆、不引别家数据库。
- `quest/QuestData.lua` 是**生成物**（纯数据、无函数）：`node quest/build.js` 用缓存生成、`--force` 全量重抓。★**手改会在下次生成时被覆盖** ⇒「改数据」＝改策展清单 `quest/chains.js`（任务 ID 序列 / 阵营 / 档位 / 等级 / 地区 / 点评）后重跑生成。
- 抓取器 `quest/fetch.js`：自带本地代理自举（`127.0.0.1:10809`，无第三方依赖）、限速 200ms、失败重试 3 次、缓存落 `quest/cache/`（已在 `.gitignore`）。站点要点：Next.js SSR，任务列表 GET 参数 `name/min_level/max_level/type/page`（50 条/页），详情页自带「本系列第 N/M 部分」链信息，`Cookie: lang=zhCN` 全站中文，物品品质取 RSC 的 `qualityColor`。
- **判据**：`QUEST TOC CHECK`（两文件在 toc 且在 DataSearch 之前 + 磁盘↔toc 双向一致 + 数据文件不许出现 function）· 组 191（策展链**逐条**查字段齐 + 任务/物品都在表里 + 档位排序 + 武器优先 + 诚实失败）· 组 192（弹窗：装备优先 / 反查任务线 / 直连数据检索 / **阵营严格三分类** / **任务节点放大镜**）。
- **加新任务线**：往 `quest/chains.js` 加一条（key / 名称 / 阵营 A|H|B / 档位 S|A|B / 等级区间 / 地区 / `quests` 完整 ID 序列 / 一句 note）→ `node quest/build.js` → 跑 `node luacheck.js` + `node test_engine.js`（都要 exit 0）。
- 弹窗行为（1.75.0~1.75.8 五轮）：数据检索 ·「地图标注」右侧 [任务线推荐]；两视图（装备优先 / 任务线）+ 三个筛选（等级 / **类型（种类子类型多选）** / 阵营）+ **行数按窗高现算**（`EVAL_QP_ROWS_FOR`，铺满不留白）+ 滚轮 + 拖动柄；装备行带真实图标（`GetItemInfo` 第 9 返回）与品质色；详情里**每个任务节点左侧放大镜** → 按**任务名**走 `EVAL_DS_SEARCH_NAME` 直达数据检索（★**不关窗**）。

### 14.3 装备「种类细分 + 子类型多选」明细（1.75.8，用户「装备筛选种类细分,支持种类子类型.武器子类型支持.并且支持多选.」）

- **种类唯一来源 = 生成数据的 `k` 字段**（类型：剑/斧/锤/匕首/法杖/弓/盾牌/布甲/皮甲/锁甲/其它），部位在 `s`，**武器与否由 `EVAL_QC_IS_WEAPON`（dps>0）现判** —— 不另立种类表（写死＝与数据脱节，下一批数据就漂移）。
- **数据层**（`quest/QuestChains.lua`）：`EVAL_QC_ITEM_KIND(rec)`（取 `rec.k`）· `EVAL_QC_KIND_LIST()`（**现算**，只列数据里真有的种类；排序 = 武器子类型在前 → 件数降序 → 名字升序 → 首见序，`table.sort` 在 5.1 不稳定故末项兜底）· `EVAL_QC_KIND_GROUPS()`（返回 武器子类型名数组, 其它种类名数组 —— 界面**不自己分组**）· `qcKindPass(set, k)`（非表/空集 = 不过滤）· `EVAL_QC_ITEM_ROWS{..., kinds={[种类]=true}}`。
- **界面**（`DataSearch.lua` 弹窗）：类型筛选按钮 = **`EVAL_DD_OPEN` 的 multi 下拉**（`{ multi = true, selected = sel, locked = locked }`；`onPick(pi, on)` → **两步布尔** `if on == true then ... = true else ... = nil end`，禁用 `on and true or nil` 这种 and/or 写法）· 分组标题（武器/其它）走 `locked[序号]=true`（画纯文本、不画方框、点击无回调）· **末行 = 「全部」一键清空**（`map[末行] = { clear = true }`，与工具箱关键字菜单的 clear 行同范式）· 选项来自 `qpKindMenu()`（数据现算）· 按钮文字 `qpKindLabel()`（空 = 全部 · 1 = 名字 · 2 = 名字、名字 · 更多 = 首项…(N)）· `DS.qpKinds` 是**唯一**选中态（旧三态 token 只作入口：`qpApplyKindToken` 把 `ALL/WP/OT` 或种类名（可 `"剑,斧"`）翻成集合）。
- **读值口**：`EVAL_QP_KINDS()` · `EVAL_QP_SET_KINDS(set)` · `EVAL_QP_KIND_MENU()` · `EVAL_QP_KIND_LABEL()` · `EVAL_QP_F2_TEXT()`（按钮上**真 FontString** 的文字 —— 按钮本体没有文字）。
- **判据**：`QUEST WIRING CHECK`（kinds 判定只准有一处 + 显式布尔 + 空集放行）· `QUEST PANEL CHECK`（无 QP_KIND 三态表 + 传 `kinds=DS.qpKinds` + multi/locked/两步布尔/空集文案/两个 locked 分组标题/走 `EVAL_QC_KIND_GROUPS`）· 组 192 ⑧j（每个武器子类型单独筛只出该子类型 · 多选并集 · 空集=全部 · 真实按钮→真实 multi 下拉→分组标题不可点→真实点行→列表按子类型过滤→按钮文字同步）。
- **变异（全部 CAPTURED）**：M20 数据层忽略 kinds · M21 退回单选 · M22 空集当「什么都不显示」· M23 未勾选时按钮留空 · M24 分组标题可点 · M25 回调写成 and/or 单行。

### 14.4 全量采集（10-60+ 全部任务奖励）+ 审计 + 输入框修复（1.75.9）

**用户原话**：「1. 现在验证可行想.开始进行数据抓取.将任务奖励:只要有装备/武器的都可以进行数据采集.单任务也可以加入采集. 2. 经典任务线衍生到30-60范围.包含大型任务线.各种开门任务线等. 3. 图片内的输入框无法输入 … 任务完成之后要审计装备链接是否正确.任务链接是否正确,任务线是否完整.以上所有数据来源都以 https://database.emberveil.org/quests 为准.装备链接都游戏内信息为准.」

- **可行性实证（先探规模，再动手）**：`/quests?min_level=..&max_level=..&page=N` 每页 50 条、页内有「第 N / M 页」可读总页数；**列表页本身就带奖励物品** —— 每条 `<img src="/icons/small/<图标名>.png" style="border-color:#<品质色>" data-tooltip-entry="<物品id>">` ⇒ 任务→装备的对应关系**不必逐条拉详情页**。10-60 共 **81 页 / 4008 条**任务；有奖励 470、带绿装+ 422、奖励物品 923（绿 637 / 蓝 148 / 紫 49 / 白 89）。
- ★★★**三个必须记住的站点事实（1.75.9 全部实测踩过，每条都对应一次返工）**：
  1. **列表页的奖励图标是「截断显示」**：一行的奖励区只画前几枚（实测 #451 列表只有 `2458`，任务详情页的「选择一件/直接给予」还有 `2459`）⇒ **奖励的权威来源 = 任务详情页**；生成器取「列表 ∪ 详情」并集。★只看列表页时审计 C 检查报了 88 条「仅详情页有」——那就是漏掉的奖励。
  2. **站点搜索 `?name=<词>` 是「任务标题（英文原文）子串」匹配**：`name=Onyxia` → 3 条 ✓；`name=安其拉` → **0 条**（中文只是 `lang=zhCN` 的显示层，不参与检索）；多词短语（`Scepter of the Shifting Sands`）→ 0 条（不是全文检索）⇒ 名人任务线种子必须用**英文单词**（Naxxramas / Onyxia / Quel'Serrar / Thunderfury / Linker / Eranikus…）。
  3. **「本系列第 N/M 部分」必须用结构性解析**：整条系列除「你在这里」那一步外每步都是 `<a href="/quest/ID">名字</a>` ⇒ 按**文档顺序**取块内任务链接、当前页那一步按 `part` 号插回。★旧实现按可见行「数字 / 名字」对齐，在部分页面整块错位（实测 #8949 把 24 步全读成同一个名字、只解出 1 个 id；#1170 奥妮克希亚同样）⇒ 生成出一堆**假任务线**。修好后 id 覆盖率 100%。
- **可抓取规模修正**（修好列表解析后重扫）：有奖励 **1683** 条任务、奖励物品 **1882**（绿装+ 1509）· 装备（部位或 DPS）**994** 件；**发货口径**（进 `QuestBulk.lua`）= 奖励里有装备的 **751** 条任务 + 它们引用到的 **1262** 件物品 + **688** 条自动任务线（≥8 步 36 条 · 开门/史诗 19 条 · 含 30-60 与 55-60 的大线）· 文件 **186 KB**。
  ★30-60 的线是**补抓**出来的：先按「有装备奖励」抓只能拿到 10-31 的小线 ⇒ `sweep_quests.js 1 70`（**全部 4008 条**任务详情，1888 条带系列）+ `refetch_series.js`（解析器每改一次都必须重抓：缓存里存的是**解析结果**）才把整库的线补全。
- ★★★**系列解析第三次返工（1.75.9 收尾）**：站点的「本系列第 N/M 部分」块有三种形态 —— ① 全是链接 ② **全是纯文本（没有链接）** ③ 混合。只按链接解析时，形态②的页面会退化成「只剩你在这里那一步」（实测：迪菲亚兄弟会 1/5、莱恩的净化 1/9、大地之冠 0/7）⇒ 经典线整条消失。**正解 = 链接 + 可见文本「数字→名字」双来源**：名字从可见文本取、id 从链接取（名字与链接对齐），再用 `quest/resolve.js` 的「任务名 → id」补缺（候选要过候选自己那页的 `part/total` 交叉验证）。修好后这些线全部拿到 5/5、9/9、7/7。
- ★★★**步骤名判据事故（1.75.1 · 用户实测「爱与家庭」找不到）**：用户问「60 级经典任务线 爱与家庭怎么没有」—— 它**在包里**，是自动任务线「**救赎**」（`s[555] = 救赎|56|60|东瘟疫之地|A|0|5742,5781,5845,5846,5848,5861,5862` · 7 步）的第 4/5 步，**但搜不到**。根因链：① 全量数据只装「带装备奖励」的任务（`build_bulk.js:105-107`，为省 1.12 客户端内存）⇒ 站点 **4018** 个任务页只进包 **751** 条，这条链 7 个任务 `rewards=[]` ⇒ 全排除；② 系列行**只存步骤 id**，名字靠运行时 `(q and q.n) or sn[id] or ("#"..id)` 补；③ **收集判据写错** —— `build_bulk.js` 原写 `if (!sweepById[ids[i]] && names[i])`，即「任务连**列表页**都没有」才存名字，而这 7 个任务**都在**列表页（4008 条）里、只是没装备奖励 ⇒ 名字**没人接** ⇒ 显示 `#5742`；④ 搜索匹配「线名 + 步骤名」⇒ **0 命中**。★而站点详情页的系列块**本来就带名字**（7 个页面逐页查过全带）⇒ 名字纯粹丢在生成阶段。**规模**：611 条自动线里 604 条（99%）有步骤名缺失、382 条（63%）全无名；1834 个步骤里 **1585 个（86%）没名字**；`sn` 只补了 25 条。**修法** = 判据改成「**不在进包任务表**里」（`shippedIds`）⇒ 重生成后 **sn 25 → 1575 · 无名步骤 0**（QuestBulk 190 KB → 234.6 KB，+44.5 KB 全是名字）。★**闸门** = `quest/audit.js` **H 段（生成物体检）**：直接解析**生成物** `QuestBulk.lua`，任何系列步骤既不在 q 表也不在 sn 表 ⇒ **硬错误**（阈值 0）；变异 = 换回旧生成物 → 1950 无名步骤、exit 1（✅ 捕获）。★★**自查踩坑（假绿）**：`s` 表是**序列**（`s={ "名|lo|hi|…" }`）**没有 `[n]=` 键**，首版按 q/i 那种键值行解析 ⇒ 解析出 **0 条**、闸门恒绿 —— **解析前先确认表的形态**。★★**「都找到了吗」的诚实答案 = 不能确认**：进包口径是「带装备奖励 + 站点自报系列（688 条 → 去重 611）」，策展 62 条是**人工**「值得做」清单、不是经典链总表，且站点没给系列块的线（策展里 29 条）根本拼不出来 ⇒ 要回答必须有**公认经典链主表**做覆盖审计（待办）。
- ★★★**同一坑的**第二层**（1.75.1 · 用户第二轮截图：弹窗里 7 行仍全是 `#5742`）**：生成期修好后**运行期照样读不到名字** —— 两处叠加：① `EVAL_QC_SERIES_DETAIL` 写 `steps[i] = { n = i, id = … }`，把站点系列块抄来的**名字 `n` 覆盖成序号**；② `EVAL_QC_LINES` 取名字写成 `(s.q and s.q.n) or ("#"..id)`，**只认 q 表**（没有装备奖励的步骤在 q 表里根本没有）⇒ 即使 `sn` 有名字也读不到。**修法** = 详情加 `nm`（名字）而 `n` 保留序号 + 行模型**四级来源**（`nm` → `s.q.n` → 新读值口 **`EVAL_QC_STEP_NAME(id)`**（读 `sn`）→ 如实 `#id`）+ 放大镜改用行模型真名（`src.name`，否则这些步骤的放大镜空转）+ `DataSearch` 的「装备→来源任务线」那条路也补 `sn` 兜底。**判据 = 组 228**（搜索 → 详情 → 行模型这条真实链路：7 个步骤行、**0 行带 `#`**、`爱与家庭` 出现 2 次、首行仍是 `1. ` 序号、`EVAL_QC_STEP_NAME(5846) == "爱与家庭"`）；**变异** = 名字解析改回只认 q 表 ⇒「实测带 # **7** 行」exit 1（✅ 捕获，正是截图那 7 行）。★★教训：**「生成期丢一次 + 运行期再丢一次」的项目里，修一处不算修好** —— 判据必须打在**用户真正看到的输出**（行模型/渲染数据）上，而不是中间层。
- **审计结论（`node quest/audit.js`，现 0 硬错误）**：A 装备 994 件全部有名字且品质合法 · B 任务 751 条（奖励 id 全在物品表、无孤立装备）· C 列表页↔详情页 **93 条不一致（全部是「仅详情页有」= 列表页截断，属于站点显示行为，数据已取并集）** · **E 策展链核对（现 62 条）**（★1.75.0 那轮只有 22 条、且全部「与站点一致」；策展扩到 62 条后现状 = **站点同系列更长 12 条 · 站点未给系列块无法核对 29 条**，审计如实列出）（当年按站点把 10 条链补全：维里甘之拳 +1650、尖牙德鲁伊 +880、莱恩的净化 +1023、健忘的勘察员 +729、奥萨拉克斯之塔 +965/966/967、与血色十字军的战争 +383、大地之冠 +917、死亡矿井散件 +2041、诺莫瑞根 +2931、主动式负载平衡器 +3922）· **F 装备↔任务链接不一致 0 条** · D/G 任务线 **769 条（审计缓存口径）**（≥10 步 21 条 · 开门/史诗 19 条 —— ★★**两个口径别混用**：审计数的是缓存里 `total≥2` 的站点系列 **769** 条，而**界面任务线视图实际列出 673 条** = 策展 62 + 自动 611（原始 688 条里 77 条因同名或步骤重合 ≥60% 让位给策展链）。文案写数字前先问「这是谁的口径」：斯塔文的传说、埃提耶什之杖、奥妮克希亚的血脉、基尔卡克的钥匙、安斯雷姆的钥匙、圣光节杖、梦魇的缠绕…）。
- **经典覆盖清点（审计 G 段）**：按区域自动清点 —— 黑石塔 27 条线 · 东瘟疫之地 27 · 希利苏斯 20 · 黑石深渊 19 · 斯坦索姆 17 · 奥达曼 13 · 通灵学院 13 · 厄运之槌 13 · 诺莫瑞根 10 · 沉没的神庙 8 · 祖尔法拉克 6 · 黑暗深渊 4 · 死亡矿井 3 · 哀嚎洞穴 2 · 剃刀高地/沼泽/血色/熔火之心/纳克萨玛斯/奥妮克希亚/安其拉各 1-2 条。★唯一「未命中关键词」= **灰烬使者**，原因如实写进报告：1.12 灰烬使者只有纳克萨玛斯掉落、**没有任务线**（黑翼/祖尔格拉布同理：前者进本靠 UBRS 流程、后者只有硬币与声望重复任务）。

- **数据质量三道补丁（都写进生成器，不许回退）**：① 奖励 = 列表 ∪ 详情；② 系列 `trusted`（id 覆盖 <50% 不采信）+ 步骤数与站点自报 `total` 不等的不采信；③ 物品名两份来源兜底（白/灰物品无「拾取后绑定」行 ⇒ 物品页拿不到名字，用任务页奖励链接文本补）。


- **抓取三层**：`sweep.js`（列表页 → `cache/sweep_10_60.json`，行含 等级/名称/地区/阵营标签/类型/经验/奖励物品）→ `sweep_details.js`（物品页：名称/品质/物品等级/DPS/速度/部位/类型/属性/图标 + 装备判定；任务详情页：`rec.series` = 站点自报「本系列第 N/M 部分」+ 步骤 id/名）→ `build_bulk.js`（→ `quest/QuestBulk.lua`）。
- **`QuestBulk.lua` 记法（紧凑串，分隔符 `|`；生成器**先证明**任何名字都不含它，否则拒绝写出）**：
  `q[id]="名|等级|地区|阵营A/H/空|奖励id,id"` · `i[id]="名|品质|ilvl|dps|speed|部位|类型|属性|图标名|是否装备"` · `s[n]="系列名|lo|hi|地区|档位(长度≥10=S,≥6=A,否则B)|是否开门/史诗|步骤id,id"` · `sn[id]="步骤名"`（步骤任务本身没装备奖励、不在 q 表时用）。
- **自动任务线**：按详情页的 series 步骤 id 集合去重 → 排序 → 等级区间取已知步骤的 min/max → 阵营由成员任务的 A/H 标签推（拿不准按「共有」）→ 开门/史诗靠关键词（之门/节杖/流沙/纳克萨玛斯/黑翼/熔火/安其拉/奥妮克希亚/克尔苏加德/泰坦/奎尔塞拉/雷霆之怒…）。
- **逻辑层**（`QuestChains.lua`）：`EVAL_QC_BULK_READY/META/QUEST/ITEM/ITEM_ROWS/SOURCES` + `EVAL_QC_SERIES_LIST/COUNT/DETAIL/FACTION`；★`EVAL_QC_ITEM_ROWS` = **全量优先、策展兜底**（`qcChainItemRows` 保留旧实现，全量缺席时界面照常可用）；★`EVAL_QC_ITEM/ITEM_NAME` 策展表查不到 → 退回全量；★`EVAL_QC_ITEM_CHAINS` 走**反向索引**（禁借道 `EVAL_QC_ITEM_ROWS`：全量行与策展行形状不同，借道＝静默 nil）；★`EVAL_QC_SEARCH` 追加一遍 **series**（`kind="series"`、键 `"s:<位次>"`），`EVAL_QC_DETAIL("s:n")` 走 `EVAL_QC_SERIES_DETAIL`（详情形状与策展链**完全一致** ⇒ 文案行/界面不分叉）。
- **审计双层**：① **离线** `node quest/audit.js [--online]` —— A 装备（id↔名/品质/部位自洽；列表页 vs 物品页品质交叉验）· B 任务（id↔名/等级；奖励 id 必须在物品表；**装备不许孤立**）· C **双向一致**（列表页奖励 vs 任务详情页「选择一件/直接给予」，站点自己不一致也抓）· D 任务线完整性（步骤 1..M 连续、成员任务自报 total 与系列自洽）；有硬错误 `exit 1`，报告落 `cache/audit_report.json`。② **游戏内** `/eh ds 任务线 审计`（`EVAL_DS_QC_AUDIT`）——逐件对账**游戏内名字/图标**（★以游戏内为准），未缓存的按 `QP_REQ_RATE/QP_REQ_MAX` **排队补缓存**（跑第二次看自愈）。
- **输入框无法输入（用户截图）＝ 真凶是 `EnableMouse`**：主搜索框 `eb` 有 `pcall(eb.EnableMouse, eb, true)`，弹窗 `qpEb` 当初漏了 —— 本客户端 EditBox **不显式开鼠标就收不到点击 ⇒ 拿不到焦点 ⇒ 一个字都打不进**。修法 = 照主框那条已验证配方补齐四件：`EnableMouse` + **点击即聚焦兜底按钮**（`qpEbFocus`，`OnClick → SetFocus`）+ `SetJustifyH("LEFT")`（本客户端默认居中偏右）+ 字体链三级兜底（全失败才启用回声行）+ `OnEnterPressed`/`OnEscapePressed`。判据 = `QUEST PANEL CHECK` 五条 + 组 192 ⑧k（真实点输入区 → `HasFocus` 为真 → 敲字进查询词 → 占位消失）。
- **等级档扩到 10-60**：`QP_LV` = ALL / 10-19 / 20-29 / 30-39 / 40-49 / **50+（hi=999，因为站点在 60-69 还有带装备奖励的团本/开门任务）**；★下拉标签**由 `QP_LV` 现算**（写死四项＝加档必漏一处）；三语言新增 `DS_QP_LV_L4/L5`。
- **判据**：`QUEST TOC CHECK`（三文件顺序 QuestData→QuestBulk→QuestChains、磁盘↔toc 双向、生成物纯数据、**任务行≥200/物品行≥300/系列≥20**、任务行恰好 4 个分隔符）· `QUEST WIRING CHECK`（全量八个接口 + 统一入口「全量优先/策展兜底」+ 反向索引 + 不借道 + plain 查找 + 物品兜底）· `QUEST PANEL CHECK`（等级档 ≥5 档且含 50+、下拉现算、来源=任务名、来源任务可搜、详情来源行挂放大镜、审计函数与命令接线）· 组 192 ⑧l/⑧m/⑧n。
- **变异（1.75.9 新增）**：M27 审计名字对账写反 · M28 `EVAL_QC_ITEM_ROWS` 去掉全量分派 · M29 搜索丢掉 series · M30 审计图标对账不跑。

### 14.5 任务线「按等级排序 + 稀有度染色 + 行尾奖励图标」（1.75.10）

**用户原话**：「任务线也按照等级排序，并且根据稀有程度染色魔兽特有的染色机制。橙色给史诗风剑之类的任务。其他你自行判断」→ 追加「任务线同行后面添加对应的装备奖励图标展示，可以预览链接」→ 再追加「同个任务线如果装备奖励多个就都显示，并排在任务标题右边，左对齐」。

- **排序（需求反转）**：`EVAL_QC_LIST` 与 `EVAL_QC_SERIES_LIST` 都改成 **等级 → 稀有度 → 原序**；旧的「开门/史诗优先 → 档位 → 等级」（1.75.9 那一轮的要求）**已被本轮明确推翻**，组 191 ③ 的断言跟着翻转（榜首 = 全表最低等级的线）。
- **稀有度 6 档 = 魔兽品质色**（**单一来源** `EVAL_QC_RARITY(rec)` → token + RGB 三通道；界面只准读，绝不写死颜色）：

  | 档 | 色 | 判据（自上而下第一条命中即止） |
  |---|---|---|
  | LEG 传说 | `ff8000` (1.00,0.50,0.00) | 链名或**任一步骤任务名**命中传说清单：雷霆之怒 / 逐风者 / 风剑 / 埃提耶什 / 萨弗拉斯 / 灰烬使者 / 流沙 / 甲虫之墙 / 安其拉 |
  | EPIC 史诗 | `a335ee` (0.64,0.21,0.93) | 开门·钥匙·团本清单（纳克萨玛斯/克尔苏加德/奥妮克希亚/熔火之心/黑翼/之门/开门/钥匙/梦魇/达隆郡/林克/爱与家庭/奎尔塞拉/节杖/议会/史诗/传说）或 `open` 标记 或 步数 ≥10 |
  | RARE 稀有 | `0070dd` (0.00,0.44,0.87) | 策展档位 S 或 步数 ≥6 |
  | UNCOMMON 优秀 | `1eff00` (0.12,1.00,0.00) | 策展档位 A 或 步数 ≥4 |
  | COMMON 普通 | `ffffff` | 步数 ≥1（2-3 步小线 / 独立任务） |
  | POOR 粗糙 | `9d9d9d` | 拿不到步骤（数据缺失，如实降级） |

  ★关键词匹配一律 `qcHasAny()` **plain 逐词**（Lua 模式里 `|` 不是交替 —— 项目铁律）；三语言 6 键 `DS_QP_RAR_{LEG,EPIC,RARE,UNCOMMON,COMMON,POOR}`；列表行文字 = `[档位·稀有度] 名字 · 地区 · lo-hi`。
- **行尾奖励图标**：`EVAL_QC_CHAIN_REWARDS(key, max)` 返回奖励 id（与详情**同序**：武器优先→品质→物品等级）+ 总数；每行 6 槽位池（`QP_RW_MAX/QP_RW_STEP`），**紧跟标题左对齐**排（起点 `x0 = 22 + qpTextWidth(文本) + 8`，逐槽 `ClearAllPoints` + `SetPoint("LEFT", row.btn, "LEFT", px, 0)`），图标走与武器列表**同一套** `qpItemTex`（游戏内真实路径优先、未缓存排队补），**悬停出物品链接 tooltip**（`qpItemTooltip`）、点击进该装备详情；装不下的用 `+N` 如实提示。
  ★**宽度单一来源 `qpTextWidth(fs, label, perChar)`**：实测优先 `FontString:GetStringWidth()`（本机 API 表里**没有**它 ⇒ 估算兜底），兜底 = **逐字节判 UTF-8**（首字节 ≥0xE0 记中文 1 字 = perChar、ASCII 记半宽）；**绝不用 `string.len` 当宽度**（字节数，中文高估 3 倍 —— 项目既有教训）。
  ★**行池复用**：每次填充必须逐槽 `Hide` + 清 `rwIds`，否则翻页后上一页图标残留到别的行（变异 M41 实测捕获）。
- **判据**：`QUEST WIRING CHECK`（调色板 6 档逐个比魔兽色 · `EVAL_QC_RARITY/RGB` 在 · 传说关键词表在 · `qcHasAny` 走 plain · 两处排序都等级优先 · 系列记录带 `qs/open`）· `QUEST PANEL CHECK`（行色必须来自 `EVAL_QC_RARITY(c)` 且不留写死色 · 详情标题按稀有度上色 · 图标槽入显隐清单 · 逐槽清理 · 左对齐锚点 · `qpItemTex` 同源 · `+N` 提示 · tooltip/点击接线 · 6 个稀有度语言键三语言齐）· 组 192 ⑦（行色 == 数据层色 + 前 10 行等级单调不降）· ⑧o（调色板字面夹具 + 传说档必须落在风剑/橙杖线上 + 详情奖励行图标/链接 tooltip/点击进详情）· ⑧p（**多个奖励并排都显示** + 悬停弹 tooltip + 点击进详情 + **装备视图不许残留**奖励图标 + 宽度纯函数字面夹具）。
- **变异（全部 CAPTURED）**：M36 行色写死 · M37 排序退回档位优先 · M38 传说关键词清空 · M39 奖励行不配图标 · M40 奖励图标不带 tooltip · M41 行池复用不清图标 · M42 只取 1 件奖励 · M43 图标改右对齐。
- ★**两个踩过的坑（省下一次返工）**：① 测试遍历任务线**别用** `EVAL_QC_SEARCH("",500)` —— 22 策展 + 688 自动线 = 710 条会截断，60 级的风剑线正好被切掉（本轮实测 legN=0）；直接走 `EVAL_QC_LIST` + `EVAL_QC_SERIES_LIST` 两份数据源。② 新 CHECK 放进 `QUEST PANEL CHECK` 段时**没有 `qc` 变量**（那段只读 `ds`）⇒ 要自己 `fs.readFileSync(path.join(__dirname,"quest","QuestChains.lua"))`，否则 test_engine 直接 ReferenceError（本轮踩到，表现是「所有变异都 CAPTURED 但 RESTORED 仍为红」）。

### 14.6 顺滑滚动 + 等级筛选点不动（1.75.11）

**用户原话**：「装备和任务线滚动机制参考抓宠助手的滚动方式.顺滑滚动.」；随后截图报「等级筛选 -> 无法点击」。

- **滚动范式 = 抓宠帮手那一套**：滚轮**一格 = 1 行**（细调），不是整页跳；`[上页][下页]` 仍按页（并带一段短促滑动）。
- **像素滑动动画**（这一轮新加，纯为「顺滑」）：每滚一行先把内容按 **1 行高**错位画出来，再由 tick **每帧 ×0.55 缓动**、`|anim| < 0.6px` 时归零并**摘掉 OnUpdate**（不常驻空转）；整页跳的起步偏移**夹到最多 3 行**（否则拉出一条长滑）。
  - `qpLayoutRows()`：逐行 `ClearAllPoints` + `SetPoint("TOPLEFT", qp, "TOPLEFT", QP_PAD, QP_LIST_TOP - (i-1)*QP_ROW_H + anim)`。★**必须先 ClearAllPoints**（每帧追加锚点 = 布局漂移）。
  - ★★**OnUpdate 回调本客户端一个参数都不传**（1.74.31 实测）⇒ tick 写成 `local function qpAnimTick()`（**无参**），帧引用走**外层 local 捕获**；变异 M48b（`function(f)` 后 `f:SetScript`）当场红字 `attempt to index a nil value (local 'f')`。
  - 帧序（源码顺序也是判据）：`qpLayoutRows/qpAnimStop/qpAnimTick/qpAnimKick` 必须在 `qpFillList` **之前**（fill 收尾要用它），而 `EVAL_QP_SCROLL` 必须在 `qpFillList` **之后** —— 否则它引用的是**全局 nil**（Lua local 词法作用域只从声明之后生效，实测报 `attempt to call a nil value (global 'qpFillList')`）。
- ★★★**填充层绝不能再把 `qpOff` 拍回页边界**：`qpFillList` 原来是 `page=floor(off/ROWS)+1; off=(page-1)*ROWS`，按行滚动后这会把刚滚的一行立刻拍回页首（判据 ⑧r 当场失败）。现在只夹取 `[0, total-ROWS]`。
- **详情视图也能滚**（顺带修好「长链只看得见第一屏」）：正文改由**统一绘制件 `qpDrawDetailBody(body)`** 渲染（body 条目 = `{text, r,g,b, zoom=任务名, item=装备id}`），它一处负责上色/放大镜/奖励图标/链接 tooltip/点击进装备详情；两个 builder（装备详情 / 任务线详情）只负责**拼 body**。滚动量 `DS.qpDetOff`，进详情时归零（`EVAL_QP_DETAIL`/`EVAL_QP_ITEM_DETAIL`），页内计数 `X-Y / N` 写在 `pageTxt`。
- ★★★**「等级筛选点不动」= Lua 遮蔽事故（本轮真凶）**：`qpF1` 的 OnClick 里先 `local labels, cb`，item 分支里又写了一次 `local labels = {}` ⇒ 外层 `labels` 永远是 nil ⇒ `EVAL_DD_OPEN(btn, nil, cb)` 建不出下拉，真机表现就是**点了毫无反应**（不报错、不红字）。修法 = 去掉内层 `local`。
  ★**为什么测试没拦住**：旧判据只核对「标签由 QP_LV 现算」这行代码存在，行为上调用的是 `EVAL_QP_SET_FILTER`（绕过按钮）。现在补了两道：**静态 CHECK**（处理段里再出现 `local labels` 即 FAIL）+ **真点按钮的行为判据 ⑧q**（真按钮 → 下拉打开 → 6 个等级档 → 真选「10-19」→ 列表只剩 10-19，字面夹具 10/19）。
- **判据**：`QUEST PANEL CHECK` 12 条（滚轮不许挂 `EVAL_QP_PAGE`、缺 `EVAL_QP_SCROLL`/常量/`qpLayoutRows`/tick 挂摘钩、**tick 不许带参数**、`ClearAllPoints`、两处夹取各一次、详情接滚轮、f1 处理段禁遮蔽）· 组 192 ⑧q（真按钮→真下拉→真筛）· ⑧r（1 行/格 · 起步 ≈ 一行高 · 动画单调收敛且摘钩 · 到顶不动 · 任务线视图同样 1 行/格 · 长链详情能滚到底且末行有内容）。
- **变异（全部 CAPTURED）**：M44 等级处理段遮蔽 `labels` · M45 滚轮退回整页跳 · M46 填充把 off 拍回页边界 · M47 动画不摘钩 · M48b `function(f)` 索引 f · M49 详情滚动不夹上界。

### 14.7 任务等级+黄色感叹号 / 放大镜跳 tab / 只检索可见装备（1.75.12）

**用户原话**：「1. 装备->任务线信息要展示任务对应的等级.左侧图标也要显示黄色感叹号 2. 点击任务放大镜报错. 3. 需求点击任务放大镜自动打开数据检索tab 进行对应任务的搜索. 4. 装备检索行为只在列表当前页检索.装备链接缓存是否生效?不要顺序检索所有装备,然后要添加检索频率.不要太频繁. 准备详情页,任务线装备页等.只在当前看得见的装备进行检索.而不是所有装备都要检索.」（附两张截图：左=装备详情里 `1. 奥萨拉克斯之塔` 行被红圈，右=`bad argument #1 to 'getn'` 红字）

- **任务行（①）**：详情正文的条目多了一个 `quest = true` 标记 —— **装备详情的来源任务行 / 链步骤行**与**任务线详情的步骤行**都标上；绘制件 `qpDrawDetailBody` 里 `elseif e.quest then` 把**左侧图标槽**贴成黄色感叹号（`QP_QUEST_ICON = DS_ICON_ROOT .. "questIcon"`，**照抄数据检索列表那张同一张图** —— 用户指的第二张图里就是这个 `!`），图标槽与奖励图标复用同一个 Texture（一行要么是奖励、要么是任务）。文本：链步骤行拼 `LvNN`（新增数据层 `EVAL_QC_QUEST_LEVEL(id)`：策展任务表 → 全量任务表依次找，查不到如实 nil）。
- **红字兜底（②）**：真机报 `EvalHelp.lua:4555 bad argument #1 to 'getn' (table expected, got nil)` @ `DD_FILTER` ← `EVAL_DD_OPEN` ← DataSearch 的匿名处理段 —— **根因就是 1.75.11 修的 `local labels` 遮蔽**（下拉收到 nil）。除了修根因，另加**渲染层双重守卫**：`EVAL_DD_OPEN` 里 `if type(items) ~= "table" then return end`、`DD_FILTER` 里 `if type(items) ~= "table" then return {} end`（**绝不因调用方传 nil 糊屏**）。判据 = 组 192 ⑧s 直调 `EVAL_DD_OPEN(btn, nil, cb)` 与 `DD_FILTER(nil,…)` 都不许报错。
- **放大镜跳 tab（③）**：放大镜 OnClick = `EVAL_DS_SEARCH_NAME(word)` → **`pcall(EVAL_HELP_CFG_SETTAB, 4)`**（第 4 个 Tab = 数据检索）→ 回执行；照抄抓宠帮手 `EVAL_PH_JUMP` 的**已验证顺序**（先送词再切 tab）。判据 = ⑧s 把 `EVAL_HELP_CFG_SETTAB` 换成间谍函数，点真按钮后必须收到 **4**。
- **只检索可见装备 + 限频（④）**：`qpItemTex` 仍是唯一入口（GetItemInfo 未命中才排队），但队列改成**每次重绘重建**：`qpReqBegin()` 在 `qpFillList` 与 `qpDrawDetailBody` 的**开头**各调一次（`DS.qcReq.q = {}`）⇒ 只装这一屏真正画出来的那几件，**上一页遗留的排队直接丢**（滚回去会重新排）。限频 `QP_REQ_RATE` 1.5 → **2.0 秒/件**（用户「不要太频繁」），`QP_REQ_MAX=24` 仍是硬上限。`EVAL_QP_REQ_STATE()` 给出 `{queued, visible, rate, cap}`；`/eh ds 任务线` 探针新增一行 `[当前页缓存] 本页装备 N 件 · 客户端已缓存 M · 待请求 K 件（限频 2.0s/件 · 队列上限 24）`（回答「缓存是否生效」：整页命中时 K=0）。
  ★**为什么这样就不算「顺序检索所有装备」**：队列容量由**这一屏**决定（≤ 一页行数 17），且每次重绘清零；994 件里没上屏的一件都不会被请求。
- **判据**：`QUEST PANEL CHECK` 11 条（两处 nil 守卫 · 感叹号常量与 `elseif e.quest` 分支与 `quest = true` ≥3 处 · `Lv` 拼接 · `EVAL_QC_QUEST_LEVEL` 在 · `EVAL_HELP_CFG_SETTAB, 4` · 队列重建两处 · 限频 ≥2.0 · 状态读值口）· 组 192 ⑧s（nil 不报错、感叹号真画出来且有贴图、`^%d+%.` 步骤行带 Lv、点放大镜切 4、队列 ≤ 一页、限频 ≥2、整页命中缓存则零请求）。
- **变异（全部 CAPTURED）**：M50 去掉 `DD_FILTER` 的 nil 守卫 · M51 放大镜不切 tab · M52 不重置请求队列 · M53 限频退回 1.5 · M54 不画感叹号 · M55 步骤行不拼 Lv。

### 14.8 任务线**全量浏览** + 「局部量先引用后声明」审计（1.75.13）

**用户原话**：「1. 任务线列表在看装备的时候报错. 3. 任务线的是否没收集齐.现在看到的最高任务只有30级.需要扫描到60级的全任务线.」（附红字截图：`DataSearch.lua:3301: attempt to call global 'qpFillList' (a nil value)` in `EVAL_QP_SCROLL`）

- **① 红字 `attempt to call global 'qpFillList'`**：根因就是 1.75.11 记下的那条 —— 局部函数的**声明位置即契约**（`local function` 声明在 `EVAL_QP_SCROLL` 之后 ⇒ 那里捕获的是**全局 nil**；截图行号比当前源码小 ~110 行，说明用户当时跑的是修复前的载入副本）。
  - **修法（结构性，不靠位置）**：在动画段前加 `local qpFillList`（**前向声明**，含注释说明为什么），定义改写成 `qpFillList = function()` ⇒ 谁在前面都抓得到同一个 upvalue。
  - **静态 CHECK**：`QUEST PANEL CHECK` 新增 5 条（前向声明在 · 绝不是 `local function` 写法 · 声明早于 `EVAL_QP_SCROLL` · 所有 `qpFillList()` 调用点都在声明之后 · ★**扫描前摘注释** —— 首轮就是被自己注释里的 `` `local function qpFillList()` `` 字面量误报，摘注释后才干净）。
  - ★★**新闸门 `LOCAL ORDER CHECK`**（实现 `probe_localorder.js`）：真正的**词法作用域分析**（`function` 参数 / `then` / `do` / `elseif` / `else` / `end` 配对 · `for` 循环变量 · `local` 多名字 · **字段名与方法名不算引用**），扫 `EvalHelp.toc` 里**全部 33 个 .lua**；正例必报、反例不报（`node probe_localorder.js --selftest` 7 条夹具），并**在真实文件上还原事故形状验证过**（`tmp/lorder_probe_check.js`：无前向声明 + `EVAL_QP_SCROLL` 前移 ⇒ 命中 `qpFillList 引用@3325 < 声明@3329`）。
    ★写这个分析器踩的两个坑（免得重写）：**① 块栈必须收支平衡** —— `else` 只 pop 不 push 会让栈越来越浅、把 `DD_FILTER(items, locked, …)` 的**参数**误报成「先引用后声明」（一次刷出 42 条假警）；**② 字段名不是变量引用** —— `ui.root` / `pc.bg` / `row.icon` / `e.chains[j]` 必须按 `.`/`:` 前缀剔除。
- **② 「任务线最高只有 30 级」= 列表被写死 `cap 200` 截断**（数据其实到 60 级，不是没收集齐）：
  - `EVAL_QC_SEARCH(query, cap, filter)` 的 `cap` 缺省 30、DataSearch 调用处写死 **200**；而任务线是**等级升序**排列 ⇒ 200 条刚好停在 30 级出头（= 22 条策展链 + 前 178 条自报系列）。
  - **数据层从来是全的**（`node quest/probe_range.js` 实测）：任务 751 条（等级 10~60；30-60 级 581 条）· 装备 990 件 · 自报系列 688 条（lo 4~60；**lo≥31 的 425 条** · hi≥50 的 259 条 · ≥8 步的大型线 36 条）。
  - **修法**：`EVAL_QC_SEARCH` 认 `cap ≤ 0 = 不限条数`（`math.huge`），DataSearch 侧新增单一来源常量 `QP_CHAIN_MAX = 0`；`node quest/probe_chainlist.js` 实测 **全量 710 条 · 最高 hi=60**，对照「cap=200 → 200 条 · 最高 hi=40」。
  - **判据**：组 192 ⑧r ★★三条（列表 > 200 条 · 列表里真能翻到 50+ 的线 · `cap=0` 不限 / `cap=5` 如实截断并报 extra）+ `QUEST PANEL CHECK` 4 条（禁写死条数 · 必须走 `QP_CHAIN_MAX` · 常量必须为 0 · QuestChains 侧认 cap≤0）。
- **②b 「任务线有按照任务最低等级排序吗?」= 排序是「两块各自排好后拼接」，不是全局排序**（1.75.14）：
  - `EVAL_QC_SEARCH` 原来先跑策展链循环（`EVAL_QC_LIST` 已按 等级→稀有度排好）、**边收边按 cap 截断**，再跑自动系列循环（`EVAL_QC_SERIES_LIST` 也已排好）接到**同一张 out 后面** ⇒ 顺序 = 「22 条策展链（内部升序）+ 688 条系列（内部升序）」，第 22/23 条之间必然出现**回头**（用户截图正中：策展链尾巴 27/29/30 级，紧接着系列 4-5 级）。
  - **修法**：两个来源**先全收**（`put()` 记 `at` = 原始顺序）→ **统一排序**（键：任务最低等级 → 稀有度权重 → 原始顺序；5.1 的 `table.sort` 不稳定，必须带原下标装饰）→ **最后才按 cap 截断**并把截掉的计入 `extra`。另两个数据层的排序（`EVAL_QC_LIST` / `EVAL_QC_SERIES_LIST`）**不动**（详情位次 `idx`、`s:<位次>` 键都依赖它们）。
  - **顺手揭出的一处真错**（被组 192 ⑦ 抓到）：`EVAL_QC_SERIES_DETAIL` 的 `c` **少给 `qs`**，而稀有度正是从 `qs`/`open`/`t` 算的 ⇒ 同一条任务线**列表行色 ≠ 详情色**（用户看到的颜色与「按稀有度染色」的口径不一致）。修法 = **系列记录单一来源** `qcSeriesRec(s, idx)`，列表行与详情都调它 ⇒ 字段不可能漂移。
  - **实测**（`node quest/probe_chainlist.js`，新增排序行）：710 条 · **等级逆序处 = 0** · 头部 `series/夜行蜘蛛洞穴(lo=4) → 大地之冠(5) → 与血色十字军的战争(8) → 瑟格拉·黑棘(10) → 鱼人的威胁(10) → 火焰的召唤(10)` · 尾部全是 `lo=60`；对照 `cap=200` 现在只到 hi=31（旧实现的观感）。
- **③ 四条旧断言按**排序口径**同步反转**（需求一改必须钉新方向，否则断言自己打歪）：⑤按任务名搜「尖牙德鲁伊」不再钉 `kind == chain|quest`（首个命中现在可能是含该步骤的自动系列）→ 改锚在**命中的名字**；⑦行色断言、⑧o「详情里有奖励行」不再假定**首行**有奖励 → 从命中列表里挑第一条**确实有奖励**的线；另加 ⑧t（全量 710 条 `lo` 单调不降 · 两类来源**必须混排** · `cap=5` 的头部与全量头部**逐条相同**＝截断在排序之后）。
- **变异（全部 CAPTURED）**：M56 `QP_CHAIN_MAX` 退回 200（静态 + 行为双网）· M57 退回 `local function qpFillList()` · M58 QuestChains 不认 cap≤0 · M59 调用处退回字面量 200 · M60 删前向声明 · M61 在声明之前插一个 `qpFillList()` 调用（新闸门当场点名 `DataSearch.lua:3260`）· M62 探针自查行写死 200 · **M63 统一排序去掉「等级」键（⇒ 30 → 4 回头，⑦/⑧t 双网）** · **M64 详情记录退回「另拼一份」（⇒ 行色 ≠ 详情色，静态 CHECK + ⑦ 双网）**。
- **本轮新增工具**：`quest/probe_range.js`（数据等级覆盖）· `quest/probe_chainlist.js`（列表条数/最高等级/extra）· `probe_localorder.js`（顺序审计 + `--selftest`，被 `LOCAL ORDER CHECK` 复用）· `mutate.js`（变异跑手：应用 → 跑两道闸门 → 还原 → 报 CAPTURED/SURVIVED，并摊开**是哪张网抓到的**）。

### 14.9 任务线等级过滤（独立 60 档）+ 策展链扩到 30-60（1.75.15）

**用户原话**：「1. 任务线 1策展链（EVAL_QC_LIST） 只有扫描到30 ,现在再增加30-60 的经典任务线整理扫描 2. 任务线过滤页增加个等级过滤.等级过滤增加个独立档位60」

- **① 任务线视图此前根本没有等级过滤**（不是「不好用」——F1 被**档位**、F2 被**阵营**占了，第三个下拉 F3 只在装备视图显示且喂的是阵营）⇒ 把空着的 **F3 位**给等级：`qpSyncFilterLabels` 的 chain 分支加 `DS_QP_F3_CHAIN`（三语言新键），`qpShowView` 改成**列表态两视图都显示** F3，`qpF3` OnClick 加 chain 分支（标签**由 QP_LV 现算**）。
- **② 等级档加独立 60 档**：`QP_LV` 从 6 项（ALL/10-19/20-29/30-39/40-49/**50+**）变 7 项，末两项 = **50-59** + **60+（hi=999）**；新键 `DS_QP_LV_L6 = "60+"` 三语言同步；旧键 `DS_QP_LV_L5` 的值由 `"50+"` 改成 `"50-59"`（**同一键换语义** —— 判据也跟着反转）。
- **③ 过滤口径 = 区间重叠**（落数据层 `EVAL_QC_SEARCH` 的 `lvOK`）：`(hi >= lvLo) and (lo <= (lvHi or 999))`。写「lo 落在档内」会让**跨档长线**（如 30-40）在「40-49」整条消失 —— 用户按等级找线就找不到。装备视图那边沿用「来源任务等级 `q.lv` 落档」（本来就是这个语义）。
- **④ 策展链扩到 30-60（`quest/curate_classic.js`）**：策展清单原来 22 条、lo 全 ≤30。新脚本从**站点自报系列**（QuestBulk）里整理 30-60 经典线并**追加到 chains.js 的生成块**（幂等：整块替换）：
  - 入选 = `hi ≥ 30 且 lo ≤ 60` · 步骤 ≥3 · **非节日线**（春节/冬幕/情人节…）· **有装备奖励**（弹窗是「装备优先」，一件装备都不给的线不进）· 且（命中经典关键词 或 步骤 ≥6）
  - **同名去重**：站点同名系列常是「联盟版/部落版/长短两版」⇒ 同阵营只留最长的一版；跨阵营两版都留并加 `（联盟）/（部落）`后缀
  - **档位必须与人工策展同语义**（chains.js 头部注释：S=蓝色武器 / A=优秀武器 / B=顺路）：站点自报的 `t` 只按步骤数给（≥8 就 S），直接抄会让「S 级链首条奖励都是武器」当场失败、档位筛选也失去意义 ⇒ 脚本按**奖励里的武器品质**重算 t
  - 结果：**62 条链 / 385 任务 / 193 物品（66 武器）**；`node quest/build.js` 重生成 `QuestData.lua`（55 KB，缓存命中、无抓取失败）
  - ★脚本必须**摘掉自己的生成块再数「现有策展链」**，否则第二次跑会把自己的产物当成「已覆盖」，候选池当场塌掉（首次实测 688 → 46 条候选）
- **⑤ 去重（列表里同一条线只能出一行）**：`EVAL_QC_SERIES_LIST` 里 `qcSeriesCovered(steps, name)` = **同名即覆盖**（策展那条信息更全）**或**步骤重合 ≥60%（阈值不取 100%：抓失败的步骤会让策展 `qs` 变短）。实测自报系列 688 → **611**、列表 **673** 条、**跨集合同名 0**、等级逆序 0。
- **⑥ 判据**：`QUEST PANEL CHECK` 新增 6 条（L1..L6 六档 · L5=50-59 · L6=60+ · chain 标签现算 · F3 两视图都显示 · chain 选中改 `DS.qpLv` · 搜索把 `loMin/loMax` 传进数据层）· QuestChains 侧 1 条（`lvOK` 的重叠式）· 组 192 **⑧q**（7 档 + 末两档字面 `50-59`/`60+` + 真选 60+ 只剩 60 级来源）· **⑧u**（任务线视图真按钮→真下拉→真筛「60+」/「50-59」+ **跨档长线必须命中** = 重叠判据的反向哨兵）· **⑧v**（跨集合同名 0 · 列表条数 == 策展 + 系列 · 策展 ≥55 条且 lo≥30 的 ≥25 条）。
- **⑦ 旧判据按新需求反转**：⑤「空查询列出全部策展链」原来用 `EVAL_QC_SEARCH("", 500)` —— 62 条策展 + 排序后高等级的排在最后，cap 500 会**截掉 60 级那批** ⇒ 改 `cap=0`（不限）。
- **变异（全部 CAPTURED）**：M65 等级档退回 6 档（50+ 吞掉 60 档）· M66 任务线 F3 不接等级（又变成没有等级过滤）· M67 去掉策展↔系列去重（44 个名字两处都在）。
- ★**本轮踩的工具坑**：`node xx.js > log.txt` 在 PowerShell 里写出的是 **UTF-16LE**，node 读回时中文全是乱码（`抓取失败` 那行「看起来不存在」）⇒ 读日志前先确认编码，写日志用 `| Out-File -Encoding utf8`。

### 14.10 请求泵「静静死掉」——当前页不再检索装备（1.75.16）

**用户原话**：「装备检索行为只在列表当前页检索.装备链接缓存是否生效?不要顺序检索所有装备,然后要添加检索频率.不要太频繁. 准备详情页,任务线装备页等.只在当前看得见的装备进行检索.而不是所有装备都要检索. **以上功能实现了吗?现在在任务线列表当前页 没有再检索装备了**」（截图：任务线列表里只有已缓存的那几行有图标）

- **先答「实现了吗」**：队列侧（每次重绘 `qpReqBegin()` 只装这一屏 + 限频 2.0s/件 + 探针 `[当前页缓存]`）**是实现且判定过的**；**没实现/坏掉的是「泵」**——队列堆着没人抽。用户观察完全正确。
- **为什么旧判据全绿却坏着**：⑧s 只断言了「待请求 ≤ 一页」「限频 ≥2s」「整页命中缓存时队列为 0」——**从没断言泵真的把队列抽走**。泵停摆时这三条照样全过 ⇒ **判据漏在「执行环节」而不是「数据环节」**。
- **三处结构性隐患（一次全修）**：
  1. **泵挂在弹窗子级 + 随弹窗 Show/Hide**：`OnUpdate` **只在帧可见时触发** ⇒ 弹窗显隐管线漏一处，泵就永远不跑。→ 改挂 **UIParent** + **常驻开启**（`pcall(qpPump.Show)`，`EVAL_QP_HIDE` 里**故意不 Hide**），要花的活由**内部**判断「弹窗是否显示 + 队列非空」把关（所以「只在当前看得见时检索」照样成立，弹窗关着一件都不请求）。
  2. **工具柄读全局名**：`local wtt = rawget(_G, "EVAL_HELP_WTT")` —— Engine 的自建 tooltip 走 `CreateFrame("GameTooltip", "EVAL_HELP_WTT", …)`，**一旦自建失败退化用 GameTooltip**，这个全局名**恒为 nil**，于是 `if wtt and …` 静默不请求。→ Engine 新增**正式**读值口 **`EVAL_WTT_HANDLE()`**（不是测试专用），泵走它。
  3. **先消费队列再取柄**：`table.remove(st.q, 1)` 在前、取柄在后 ⇒ 柄为 nil 时那一件**白丢**且用户端毫无痕迹。→ 取柄/授权检查**通过之后**才 `table.remove`；拿不到就记 `blocked` 并把队列**原样留着**。
- **一处自己写的 Lua 陷阱**：写 `wtt = (type(EVAL_WTT_HANDLE)=="function") and EVAL_WTT_HANDLE() or rawget(_G,"EVAL_HELP_WTT")` —— `f()` 返 **nil** 时 `and/or` 会**静默回落**到全局名（1.73.15 记过这个形状，本轮又踩；桩把 handle 换成「返回 nil」后仍然取到了全局名）。正解 = 分两步 `if type(F)=="function" then wtt = F() else wtt = 全局 end`。
- **可观测性（这次真正的教训）**：`EVAL_QP_REQ_STATE()` 增 `req`（已请求件数）/`blocked`（因拿不到柄挡下次数）/`tried`/`pumpShown`；探针 `/eh ds 任务线` 增一行 `[请求泵] 已请求 N 件 · 因拿不到工具柄挡下 M 次 · 泵帧=开/关 · 已试过 K 件`。★光看「队列几条」**分不清「在抽」还是「死了」**，这就是本轮排查多花一轮的根因。
- **判据**：新增 **⑧w**（驱动**真泵体** `EVAL_QP_TEST_PUMP_TICK`，桩时间控制限频）：① 时间够 → 队列 −1、`req` +1、**且真的用 `item:` 链接调了 `SetHyperlink`**（桩给隐形 tooltip 补 `SetHyperlink` 并记进 `TEST.wttHyper` —— 真机 GameTooltip 必有此方法，桩缺它则这类判据根本立不起来）② +0.5s 再 tick **不抽**（限频）③ 把 `EVAL_WTT_HANDLE` 换成返回 nil → **队列不动** + `blocked` +1。`QUEST PANEL CHECK` 新增 7 条（Engine 导出 handle · 泵挂 UIParent · 禁 `and/or` 陷阱写法 · 必须走 handle · **取柄失败不许消费队列** · 探针报泵状态 · 读值口暴露 req/blocked · 常驻开启 · `EVAL_QP_HIDE` 不许 Hide 泵）。
- **新增读值口**：`EVAL_QP_TEST_PUMP()` / `EVAL_QP_TEST_PUMP_TICK()`（跑**真**泵体，不复制逻辑）；泵体拆成 `qpPumpTick`（要）+ `qpPumpRetry`（2s 后复查自愈、缓存回来就补画当前页），`OnUpdate` 两句都跑（首版漏了复查 ⇒ 「请求发了但永不补画」）。
- **变异（全部 CAPTURED）**：M68 先消费队列再取柄（静默丢件）· M69 限频失效（每帧抽一件）· M70 泵挂回弹窗子级 · M71 工具柄退回读全局名 · M72 泵不常驻开启 · M73 `EVAL_QP_HIDE` 又去 Hide 泵。

### 14.11 种类按部位细分 + 等级筛选挪最左 + 任务线按种类筛 + 占位图（1.75.17 ~ 1.75.18）

**用户原话**：「任务线->装备->类型:其他能否细分为戒指.项链,饰品?」→「任务线->等级筛选按钮移动到最左侧」→「任务线->档位过滤使用装备那边的种类过滤.」→「任务线列表单元对应的装备再未扫描出装备的情况下使用宏961 宏图标占位,提示数据更新中..如果主动点击.则将这个装备的检索加入检索队列最前面.优先扫描..更新之后就更新这个图标和链接信息」

- **① 「其它」细分成 戒指/项链/饰品（1.75.17）**：站点把这三类的**类型**字段全写成「其它」，**只有「部位」分得开**（`node quest/probe_kinds.js` 实测：990 件装备里 其它 251 件 = 手指 102 / 颈部 77 / 饰品 72 / 双手 1）⇒ `EVAL_QC_ITEM_KIND` 在「类型 = 其它 或 空」时按**部位映射** `QC_SLOT_KIND = { 手指→戒指, 颈部→项链, 饰品→饰品 }` 补；映射只列站点确实给得出的部位名（**种类清单仍由数据现算**，数据里没有的绝不凭空造）。装备列表行文字也改用 `EVAL_QC_ITEM_KIND`（否则筛「戒指」却显示「其它」）。
- **② 等级筛选挪到最左（1.75.18）**：任务线视图此前是 档位(F1)/阵营(F2)/等级(F3) ⇒ 改成 **F1 等级 · F2 类型 · F3 阵营**，**等级在两个视图都在最左**；处理段随之简化：`qpF1`/`qpF3` 不再按 tab 分支（两视图共用等级 / 阵营），只有 `qpF2` 分叉（装备 与 任务线**共用同一份种类菜单**）。`DS.qpTier`/`QP_TIER` **整块删除**（死代码必漂移；数据层仍兼容 `tier` 参数）。读值口 `EVAL_QP_SET_FILTER` 的任务线分支改为只认第 2 参=阵营（第 1 参旧档位忽略），旧测试的 `("ALL","A")` / `("ALL","ALL")` 照旧有效。
- **③ 任务线的「类型」= 装备那边同一套种类多选（1.75.18）**：`DS.qpKinds` **两个视图共用**；判据落数据层：
  - `EVAL_QC_KIND_PASS`（原 `local qcKindPass` 上移成**全局单一来源**，装备/任务线共用）；
  - `qcRecKindsOK(记录, 集合)`：**记录的奖励里有没有勾选的种类**（空集 = 不过滤；拿不到奖励清单就**如实不通过**，不假装命中）；
  - `qcSeriesRec` 顺带把**奖励 id** 收进记录（从站点数据现算 ⇒ 688 条系列也能秒筛，不必逐条调详情）；
  - `EVAL_QC_SEARCH` 的策展链与自报系列两个循环都过 `qcRecKindsOK`。
  ★顺序要求：`QC_SLOT_KIND` / `EVAL_QC_ITEM_KIND` / `EVAL_QC_KIND_PASS` / `qcItemRec` / `qcRecKindsOK` **必须声明在 `EVAL_QC_SEARCH` 之前**（local 用在使用之后 = 真机读到全局 nil；`LOCAL ORDER CHECK` 守着）。
- **④ 未扫描出的装备用「宏图标 961」占位 + 点击优先刷新（1.75.18）**：以前 `qpItemTex(id)` 未命中就**什么都不画**，用户看到「这行有奖励却空着」，无从判断是没扫到还是真没有。
  - 占位图 = **`GetMacroIconInfo(961)`**（宏图标选择器里那个编号，**游戏内素材**），拿不到才退回游戏内既有的问号图标；画出来**置灰**（0.55）以便与真图标区分。
  - 悬停 → 「数据更新中…（点击优先刷新）」（新三语言键 `DS_QP_LOADING`）；**点击 → `qpReqPriority(id)`**：把该 id **插到队列队首** + 清 `st.at`（下一次 tick 立刻抽它，不等 2s）+ 清 `tried[id]`（不等退避窗）+ 计数 `st.pri`。
  - 扫到之后：`qpReqRetry`/重绘自动换成**真图标**，悬停与点击也回到「物品链接 / 装备详情」（同一格根据 `row.rwPh[slot]` / `st.detPh[i]` 分支）。
  - 三处都套上（列表行尾奖励带、任务线详情奖励行、以及**同一套** `qpItemTexPh`），入口唯一：`qpItemTexPh(id) → tex, isPh`。
- **⑤ 判据**：组 192 **⑧y**（按种类筛任务线：真选 → 只剩奖励里有该种类的线、且条数收窄、清空回到全部；种类名由数据现算不写死）+ **⑧z**（占位图 = 宏 961 贴图且真画出来 · 悬停出提示 · 点击后该 id 在**队首**且 `pri` +1 · 塞进缓存后**不再是占位**且换成真图标）。`QUEST WIRING CHECK` 加 4 条（`EVAL_QC_KIND_PASS` 单一来源 · `qcRecKindsOK` 在 · 两个循环都接）· `QUEST PANEL CHECK` 加：任务线等级标签走 F1 现算 · 任务线类型标签走 `qpKindLabel` · 档位残留检测（**扫描前摘注释**，注释里写着 `QP_TIER`/`local labels` 这类字面量）· F1 处理段只准一处 `local labels` 且写回 `DS.qpLv` · F2 只准一个下拉（两视图共用）· 占位四件套（常量 961 / `GetMacroIconInfo` / `rwPh` 标记 / 置灰 / 悬停两支 / 点击两支 / `table.insert(q, 1, id)`）。★`node quest/probe_kinds.js` 是这次「数据里到底有没有区分」的取证工具（部位/类型分布）。
- **⑥ 变异（全部 CAPTURED）**：M66 等级选择不生效（F1 写死 ALL）· M74 任务线搜索不传 `kinds` · M75 数据层种类判据恒真 · M76 点占位直接开详情 · M77 优先插到**队尾** · M78 未扫出的不画占位图。★M75 首版写成「插一行 `return true`」→ 直接把函数写坏（LOAD ERROR），虽然也算 CAPTURED，但**这不是判据在起作用**；改成「末尾 `return false` → `return true`」才是在验语义（判据纪律：变异要打在语义上，不是打在语法上）。

### 14.12 任务线图标「跟不上」的定案 + 队列上限位置 + 省时闸门（1.75.19 ~ 1.75.21）

【用户问题】「任务线推荐 → 装备能及时显示图标，为什么任务线这边不能及时显示？」
【取证】`node quest/probe_chainlist.js`（各档首屏 = 17 行）：

| 档位 | 有奖励的行 | 首屏待抓件数 | 装备视图同屏 |
|---|---|---|---|
| 10-19 | 2 / 17 | 9 | 17 |
| 20-29 | 10 / 17 | 20 | 17 |
| 30-39 | 9 / 17 | 23 | 17 |
| 40-49 | 8 / 17 | 18 | 17 |
| 50-59 | 12 / 17 | 13 | 17 |
| 60+ | 9 / 17 | **66** | 17 |

⇒ 三个原因（按贡献排序）：① **数据密度**：任务线一行最多 6 个奖励图标（装备视图每行 1 个）⇒ 同屏待抓件数最多 4 倍，
限频同为 2.0s/件 ⇒ 装备视图 34 秒铺满、任务线要 ~2 分钟；② **很多行本来没有装备奖励**（10-19 档 17 行只有 2 行）
⇒ 满屏「空着」是数据事实，不是没抓；③ **队列顺序**（1.75.19 已修）。

【1.75.19 按列排队】`qpFillRows` 行循环之后把 `DS.qcReq.q` 按「列优先」重排（rank = j 外层/i 内层遍历 `st.rows[i].rwIds[j]`，
再 `table.sort(dec, by r)`）。★首版只写了「按 rank 过滤」没 sort ⇒ 顺序仍是原样（判据 ⑧aa 当场抓到）：**纯过滤 ≠ 重排**。

【1.75.20 上限位置】上限原本写在 `qpItemTex` **入队时**（`table.getn(st.q) < QP_REQ_MAX`）——那是**行序**的先到先得
⇒ 队列里可能一整屏都是前两行的件，排在后面的行**连排队资格都没有**，事后重排无从救起。
改成「入队不截断 + 收尾 `qpReqTrim()`」（先全收 → 按列排序 → 再截到 24）。判据 ⑧bb；变异 M80（恢复入队截断）/M81（截断挪到排序前）都 CAPTURED。

【★说实话：时间收益 ≈ 0】`probe_chainlist.js` 的「全部点亮」是**逐轮模拟**（泵 2s 抽一件、重绘重建队列）：
各档「旧/新」轮数 —— 10-19 = 6/2 · 20-29 = 18/8 · 30-39 = 22/9 · 40-49 = 14/7 · 50-59 = 8/7 · 60+ = 25/9（单位 = 轮 × 2s）。
★**A（1.75.19 行序截断+重排）与 B（1.75.20 列序截断）逐档打平**（含「每 8 轮才重建一次」的稀疏重绘模型）——
即 1.75.19 已经做到了「每行先出第一件」；1.75.20 的价值是**结构性**的（队列内容 = 优先级最高的 24 件，不再依赖数据分布恰好友好）。
★**量这类「第几轮才轮到」必须逐轮模拟**：首版拿「行序位次 × 2s」当等待时间（60+ 档算出 50 秒）是错的——
A 在下一轮重绘时会把那件重新纳入窗口再排到前面。

【1.75.21 省时闸门】`node check.js` = luacheck + test_engine **并行**（28s）· `--quick` **6.5s**（跳过组 192，**如实打 SKIPPED**）·
`--full` 追加 quest/audit · `--selftest` 验失败上报。实测 **组 192 独占 22s**（1300 行断言 × 每次刷新都要跑 673 条全量检索 + 17 行重绘；
V8 profile 显示时间全在 fengari 的 `luaV_execute`/`adjust_top`/`moveresults`）。`mutate.js` 默认不再全量，且**中断自动还原**。
【教训】`Get-Content`/`Set-Content` 往返改含中文的源码会**不可逆**写坏（103 处 U+FFFD，已重写该探针）⇒ 只用 edit/write 工具或 node 脚本。

### 14.2 两个助手的弹窗候选「按物品类型过滤」明细（1.74.28 · 常驻卷瘦身移出，原文照存）

- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28，用户「弹窗选的物品项目要过滤一下.不要显示武器,装备.灰色物品,草药,矿物,任务物品,材料等等非可使用的物品,验证可行性.」）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，**完全不依赖缓存**）⇒ 灰色一律剔；② **`GetItemInfo`**：★传参**先用物品链接**（`GetContainerItemLink` 给的 `|Hitem:…|h[名]|h` = 客户端的**缓存键**），nil 再退回名字；读第 5/6/8 返回 = 主类型/子类型/**装备槽**（装备槽非空 ⇒ 算护甲，比类型词更硬）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 读守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`**（已核在官方 API 索引里）读**类型行** —— ★★这一步会**把物品写进客户端缓存** ⇒ 下次 `GetItemInfo` 直接命中 = **自愈**（`probed` 计数会掉下来）。
  ★**剔除表** `IG_KIND_DROP`：武器 · 护甲(装备) · 灰色 · **材料（草药/矿物/布料/皮革/附魔材料）** · 任务物品 · 容器 · 箭矢弹药 · 钥匙 · 配方图纸；★**判不出就不剔**（铁律「查不到 ≠ 没有」：宁可多显示一件，也不把真食物藏起来）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」这条路径开**（`EVAL_IG_SCAN_BAGS(bags, { classify = true })`）——按名字解析包格那条路（`EVAL_CH_FIND` / `EVAL_HH_FIND_FOOD`）**绝不过滤**：判错一类 → 用户已配置的物品会**静默找不到**（本项目最恨的失败型）。
  ★★**tooltip 只读 TextLeft2 起**（**跳过 TextLeft1 = 物品名**）：名字里可能含类型词（「草药烤鱼」含「草药」）会污染判定；词表 `IG_KIND_WORDS` 按**真机实测文案**维护（本客户端 zhCN）。
  ★**验证入口**（「验证可行性」= 一条命令）：`/eh go 消耗品探针 过滤` ｜ `/eh go 喂食探针 过滤` → 逐件打出**判定依据**（品质 / 缓存主类型·子类型·装备槽 / tooltip 读到的真实类型行 / 最终判定）+ 统计行（剔除/保留/判不出/缓存命中/未缓存/tooltip 探了几次），上限 30 行并如实报「还有 N 条未显示」；★它同时是**补词表的依据**。
  ★**新增文件/新代码要同步的清单**（本轮 `DECL ORDER` 当场抓到）：报告函数被插到 `IG_KIND_*` **local 声明之前** → 真机上读到**全局 nil**；★凡是新函数引用文件内 local，一律确认声明在前（`DECL ORDER CHECK` 扫全部 14 个生产 .lua）。
  判据 = 组 187（旧档 ①~⑥ + 新档 ⑦~⑩：白色**材料**/任务/容器/箭矢/钥匙/配方逐项剔、tooltip 兜底真的收到 `SetBagItem(bag,slot)`、**缓存自愈后不再探**、判不出不剔但记账、关掉 `classify` 行为不变）。

## 附录 R：从常驻卷（CLAUDE.md）清理迁入的判据详案（不自动载入）

> ★**来源**：常驻卷超工作区指令预算（65,536 字节）被截断，清理时把「判据还在、但踩坑经过/版本流水属于叙事」的块整体迁到这里。
> 常驻卷里对应条目末尾的「全案见参考卷附录 Rx」即指本节。**这些信息没有删，只是不再每会话自动加载**。

### R1. 分享「回声忽略」误判 + 「分片到了却不弹」取证全案（1.74.4~1.74.5）

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

### R2. local 声明顺序连踩三次的实例（1.74.29）

- 本轮在 `addons/` 独立插件上**连踩三次**：`pb8Start`→`autoEnsureLabel`、`pb9SetAll`→`featWm`、`uiRefresh`→`hlApplySelected`。
- 盲区实例：行 OnEnter 里 `add(...)` 用了 21 次、而 `local L = {}`/`local function add` 写在 40 行之后 → 运行期 `attempt to call global 'add'`，闸门静默通过。
  （检查按**名字**比对，文件内还有**缩进的**同名 local 就整名跳过（防误报）⇒ 顶层「先用后声明」漏网。）
- 旧检查只扫 15 个生产文件，独立插件目录曾是盲区（1.70.46 的老教训重演）；1.74.29 补 `ADDON DECL ORDER CHECK`（扫 `addons/**/*.lua`，与主仓同算法）。

### R3. 品阶配色史与评分/头衔旧口径（1.74.19~1.74.22）

- 神级配色史：暗金 b87333 → 亮蓝 00bfff → 深红 c00000 → 亮金 ffcc00（试色）→ **亮蓝 00bfff**（1.74.22 用户定案）。
- 评分旧口径：**空技能白送 1 分** ⇒ 25 条空技能就神级（实测复现过）；1.74.19 重做为「空技能 0 分 + 条件按类加权」。
- 头衔旧口径：2~5 档全是「≥1 个」⇒ 头衔满档只要 1 个方案，连带彩蛋闸门形同虚设；1.74.19 改为 `SH_TITLE_REQ = { 1, 2, 3, 3, 2 }`＋逐级满足。
- 旧写死值（已废，一律现算）：25 / {3,9,15,21,26} / {1,4,7,10,13}。

### R4. 稀有提醒转播全案（1.74.23~1.74.27）

- ★★★**跨插件：捕获 UnrealQuest 的稀有提醒**（1.74.23，用户「只要知道他发现稀有的那一时刻，在对话框内输出一段文字」）：
  弹窗唯一出口 = `World/RareAlert.lua` 的 `RareAlert:Show(entry, distance, dx, dy, others)`（内部 `SetAlertWindowText → UpdateArrow → Client.ShowObject → shownUntil → 音 → 聊天 → 计数`）
  ⇒ **包住它、在返回后回调 = 卡片已经在屏幕上的那一刻**。模块注册表是**公开**的：全局 `UnrealQuest`（`Core/Namespace.lua:17`）+ `UnrealQuest:GetModule("RareAlert")`（就是 `UQ.modules[name]` 那张**普通表**，`NewModule` 只塞 name/enabled、无元表保护）；
  ★**安装必须等 VARIABLES_LOADED**（AddOns 按目录名排序，**EvalHelp(E) 先于 UnrealQuest(U)**，载入期拿不到对方 —— 与 DataSearch 的 `dsUQModule` 同因；那个是文件内 local，本处提成全局 `EVAL_UQ_MODULE`）；
  ★包装纪律 = **返回值逐个透传 + 原函数抛错照原样 `error(a,0)` 抛出**（吞掉别人的错 = 把别人的 bug 藏起来），只在抛错时如实计数；
  兜底 = `Show` 不可包时轮询对方**公开读值口** `RareAlert:GetStatus().alerts`（单调累计计数；**首读只立基准**，否则会把本次登录前的历史计数当成刚弹过）；兜底 tick 父级必须是 **WorldFrame**（挂 UIParent 开全屏地图会停摆，见 1.70.39）；
  载荷：名字走 `Database:GetUnitName(entry.unitId)`、品阶 `entry.rank`（1 精英/2 稀有精英/3 首领/4 稀有）、`distance` 已是整码、`others` = 同刻另有几只；频率上对方自带「同怪 180s 冷却 + inRange 抖动带」，不会刷屏；
  命令 `/eh go 稀有`（状态/开/关/试；`试` 直接调对方 `TestNearest` 走完整链路自证）；判据 = 组 199 + 源码检查 `RARE WATCH WIRING CHECK`（安装点 / 命令前缀字节数 / 包装透传与照抛 / 兜底 tick 父级）。
- 染色（**1.74.24** 用户「对稀有精英染色」）：名字按品阶上色（精英 银 c0c0c0 · 稀有 蓝 0070dd · 稀有精英 紫 a335ee · 首领 橙 ff8000 —— 物品品质那套玩家一眼就懂；与「方案品阶」五色是**两个维度**，项目纪律要求错开，故最低档用银不用白）；★**整条消息只许一段 8 位色码**（一条多段会整条不画）⇒ 色码由调用方按品阶给，语言包里不再写死金。
- 可点（**1.74.24 → 1.74.26** 用户「点击他可以定位目标」＋「点击头像相当于目标切换到稀有精英目标」＋定案原话「点击名字逻辑很简单.不要和那边插件的机制管理.需求只要是调用类似目标函数选中目标就可以了.如果目标不存在就报错.」）：名字做成链接 `|c..|HEHRW:<名字>|h[名]|h|r`（形态照抄分享封皮那条真机配方：色码在外、链接在里）⇒ **点名字 = 一次 `TargetByName(名字)`**，选中报「已选中目标：X」、选不中报「选不中目标：X」—— **就这一个动作，没有第二动作、没有退路**。★1.74.26 按用户定案**删掉**了所有与那边插件机制的耦合：不再有坐标 / 最近刷新点 / 地图投影 / `EVAL_DS_SHOWMAP` 开图；token 从 `EHRW:areaId:x:y:unitId` 收成 `EHRW:<名字>`（名字是唯一需要的东西）—— 源码检查现在**反向守**：稀有转播里出现 `EVAL_DS_SHOWMAP`/`EVAL_RW_NEAREST_LOC`/`GetCurrentZoneView` 即 FAIL。
- ★★★**1.74.27 提取为独立模块 + 工具箱开关**（用户：「将以上功能提取到独立文件内 ./tools 然后再工具箱内设置开关.」）：整块搬到 `tools/RareWatch.lua`（**主文件只留两个接线点**：VARIABLES_LOADED 的 `pcall(EVAL_RW_INSTALL)`、命令分支 `/eh go 稀有`）；新模块只走**全局桥**（`EVAL_SAY`/`EVAL_LOGLINE`/`EVAL_L`/`rawget(_G,"EVAL_HELP_CONFIG")`），绝不引用主程序文件内 local；工具箱新增「稀有提醒」组 + 开关（Toolbox 的 `t="rw"` 行型）——★**读写走实现自己的单一来源** `EVAL_RW_ENABLED`/`EVAL_RW_SET`，不另存 `tb.rareWatch`（两处真值必然打架）；★工具箱模型 28 条 > 每页容量 26 ⇒ **第 2 页**，判据必须翻页后取控件（`EVAL_TB_TEST_SCROLL_CLICK("dn")` + 新读值口 `EVAL_TEST_TB_CHK_FOR`）；★**新增文件要同步 7 处清单**：toc / 测试载入清单 / DECL ORDER / LANG KEY / COMMENT SWALLOW / WHEEL / COLOR CODE LEN / FRAME NAME CLASH（漏一处就是「新文件永远不被检查」的静默盲区），打包基准 68 → 69；`RARE WATCH WIRING CHECK` 改成**分两段扫**（接线点看主文件、实现模式看两份并集）。判据 = 组 120⑥ + 组 199。
- ★`TargetByName`：**官方 API 索引里有**（category=Targetting），且**不是 Protected**（参考卷 §F3:138 逐条核过）；但它在「附近没有这只」时**静默失败**（官方文档明文「只认附近单位」，`Engine.lua:735-736` 早已记过）⇒ **必须核对结果**：调用后读一次 `UnitName("target")`（否则「点了没反应」会被报成成功）。★对方 RareAlert **明确不做**这件事（自动扫描会抢玩家目标，RareAlert.lua:23-27 有明文），我们只在**玩家主动点一下**时做。
- ★★★**1.74.25 实锤（用户截图，这是本条最重要的事实）**：截图上任务插件导航箭头显示那只稀有在 **556 码**外，而我们写的文案是「它没刷 / 它不在这儿」→ **真因是客户端限制**：`TargetByName` **只认客户端附近的单位**，远处**静默失败**（官方文档 `Targetting#targetbyname` 明文；本项目 `Engine.lua:735-736`、参考卷 §F3 早已记过；参考卷 §F3:138 还确认它**不是** Protected —— 所以「切不到」≠「调用非法」）。
- ★★教训 = **「把自己的限制说成对方/世界的状态」是造谣**：`选不到「X」` 必须**同时报出距离**（`约 N 码`，取转播时对方给的那个数）+ 给出下一步（走近再点 / 右键地图定位），并且**一句话说完**（上一版太长，被聊天框折成两行 —— 截图可见）。反向哨兵：文案里绝不许再出现「它没刷」。
- ★取证命令 `/eh go 稀有 目标探针`：拿**当前目标自己的名字**（必然存在且必然在附近）——先 `ClearTarget()` 再按名字选回来，报 4 步判定。**这是唯一能区分**「客户端只认附近」与「TargetByName 对本插件是空操作」的实验（两者从结果上长得一模一样）；顺带打印库里那份名字与**字节数**，排掉「库名 ≠ 客户端名」这第三种可能。判据 = 组 199⑫（含「它没刷」反向哨兵 + 距离必须出现）与 ⑯。
- ★链接的失败模式是「**整条不画**」⇒ 留了 `稀有 链接` 开关，一键退回**已验证的「只有色码」形态**；命令 `/eh go 稀有 目标|链接|目标探针`；判据 = 组 199⑩~⑯ + `RARE WATCH WIRING CHECK`（4 色逐项 8 位 · 链接**只带名字** · Toolbox 的 `EHRW:` 分派**必须以该语句开头** —— 只查「文件里出现过这串」会被 `if false and …` 骗过，本轮变异测当场撞到 · **反向守**不许再耦合地图机制）。

### R5. 队伍菜单三条条件定案经过（1.74.1 / 1.74.4）

- ★★★队伍菜单三条条件（1.74.1，审计定案）：**邀请队伍** = 不在队伍 或 我是队长（修「队长反而邀不了人」的旧 bug）；
- ★1.74.4 邀请队伍再补一刀（用户截图：对方已入队却仍显示邀请队伍）：条件只看「我」的状态是 bug → 改为「**对方不在我队伍/团队里 且 （不在队伍 或 我是队长）**」；队友已入队 → 邀请藏掉（踢出/离开照常）。组 130⑥e2 反转；变异 M568。
  **踢出队伍** = 我是队长 且 被右键的是队友（非队长根本不出现这条，不再是「点了才说不是队长」）；**离开队伍** = 在队伍内显示
  （退队不需权限，与右键的人无关，动作 `LeaveParty()`）。判队长 = `IsPartyLeader()` 或 `IsRaidLeader()`；★助理踢人没有
  `IsRaidAssistant` 接口可判 → 如实接受边界（助理看不到这条，动作里仍有「不是队长」兜底）。成员判定 = `EVAL_TB_NAME_INMYGROUP`
  （UnitInParty/UnitInRaid 反查，party 只扫 1..4）。组 130⑥e/⑥e2/⑥e3 + 组 173 + ⑤b；变异 M564~M567 捕获。

### R6. 铁律 1 / 铁律 2 的代价全案

- **1.9.0 语法事故**：两处 `local function` 误用 `end)` 收尾（多一个右括号），导致 **1.9.0~1.11.0 全部功能实际未生效**；旧的 balance 脚本（数 function/end 配对）**拦不住多余符号**，只能当辅助。
- **铁律 2 的两次代价（都是绕了远路）**：**1.70.17** 自己发明用 `IsShown` 判地图可见性，而对方 `ClientAPI.lua:8664` 早写明这 API 在本客户端**不可靠** → 引入回归；**1.70.39** tick 挂 `UIParent` 导致开图时 OnUpdate 停摆，而对方 `Driver.lua:467-482` 把机理和正确做法全写在注释里——用日志推断**五轮**没找到，**用户一句「可以查看任务插件…」当场破案**。

### R7. 铁律 5 首案（频道进出屏蔽返工三次）

- 频道进出屏蔽返工三次（文本判据 → 官方消息组 → 事件名判据），最后靠核 API 调用 + 探针才定案；而那次「Channel is missing!」报错，核完 API 后确认**插件根本没拿 CHANNEL 发过消息**、错在客户端的频道成员状态 —— 不是插件把 API 调用写错。

### R8. 分享分片限频根因全案（1.72.3）

- ★★★1.72.3 **分享分片必须限频发送**（用户实测：「长方案对方有时候接收不到」，短方案 1 片从不出问题）。
  【根因】`Share.lua` 原实现在一个 for 循环里**连着 `RunScript('SendChatMessage(...)')`** 把 N 片一次发完
  （同一帧 N 条聊天）→ 撞反刷屏限流被吞一片 → 接收端**永远收不齐**（而收不齐当时还是静默丢弃，见常驻卷 §5.2）。
  ★这正是频率防护总则早就写明的铁律的又一次违反：「**RunScript 本身也是队列，连发聊天同样会被反滥用踢线**，通知类输出也要入限频队列」。
  【修法】第 1 片立即发（手感不变），其余进 FIFO 由 OnUpdate 每 `SH_SEND_RATE=0.5s` 滴一片（**2 条/秒**，给服务器留余量），
  队列上限 `SH_MAX_QUEUE=200`（超出如实取消）；★**绝不在瞬间倾泻大量文字**（用户明确：不然服务器被触发预警）。
  ★判据 = 断言组 106（只准立即发 1 片 + 同刻 tick 也抽不干 + 分时发完）；变异 M7（退回一帧全发）→ 当场 got=9 want=1。

### R9. §5.2 被合并条目的原文（1.73.39~1.73.40 族）

- 1.73.39「加个边框」也要读顶点色：四条 1px 纹理（BORDER 层）`tbSolid(1,1,1,0.75)`；判据 = 四条 + 顶点色 ≥0.9 + 跨满窗宽高。
- 1.73.39「A ↔ B 对调位置」= 改数据顺序不是改坐标；判据直接读渲染出的条目文字，别比 x/y。
- 1.73.40「圆角」只能来自原生边贴图：`SetBackdrop` + `edgeFile = UI-Tooltip-Border`（`edgeSize 16` 整数、`insets 4`）；判据 `MENU ROUND CHROME CHECK` + 两条路都验。
- 1.73.40「末行按钮吊在框外」= 高度公式漏算末行自身高度；正解 `h = -TOP + rows*行距 + PAD`；判据别用同一公式自证 → 独立包含性断言：每条按钮落在 `[0,W]×[-H,0]` 内。
- 1.73.40 悬停高亮走 `OnEnter`/`OnLeave` 改颜色（禁用 `SetHighlightTexture`）：底色/文字两处都改、离开逐值复原；判据读真控件 + 每条都挂了两个脚本。
- 1.73.40 计数必须由闸门守：「案例模版 11 组 N 条」散在 4 处（`.toc` + 三语 README）；判据 `TEMPLATE COUNT CHECK`。
- 1.73.40 样式需求会被下一轮推翻 → 断言跟着改方向：新判据 = ①悬停背景逐值没变 ②文字真变白；桩要能读回文字色。
- 1.73.40「框增加 padding」= 宽高/标题/条目位置全由同一组常量算：`TB_MENU_PAD`/`TB_MENU_TOP`；判据用独立阈值，不用生产常量自证。

### R10. 其它被精简表述的原文（4.1 / 4.2 / 5.4 等）

- 4.1 `seBtn` 条原文尾巴：「——1.21.4 修复 SE 技能名按钮把包裹表当按钮用（`uiText` 炸 CreateFontString、SE_BUILD 半成品窗口）」。
- 4.1 local 作用域条原文尾巴：「——1.21.4 修复激活方案下拉（`DD_OPEN` anchorBtn nil）」。
- 4.1 EditBox 条原文：「（1.15.1 用户报告 IO 窗口空白：`pcall` 全「成功」但什么都不可见）→ IO 窗加 FontString 保底预览区（`EVAL_HELP_IO_REFRESH`）；EditBox 字体链先试 `SetFontObject(GameFontHighlightSmall/ChatFontNormal/GameFontNormal)`；**文本类 UI 一律给 FontString 保底**；单行输入弹窗用**回声行**保底（`OnTextChanged` 镜像到 FontString，1.17.0 重命名弹窗 `EVAL_HELP_RP_*` 范式）。」
- 4.2 手写转义全案（1.73.28）：想写「引号 + 反斜杠」时手写 `"` / `\\` 极易写坏（实测把 `string.gsub(name, "[\"\\\\]", "")` 写成了 `"["\]"`）→ 而且 **luacheck 当时只查主文件、照样报 SYNTAX OK**，直到运行时 load 才炸（LOAD ERROR ... expected ')' near backslash）。正解 = 用 `string.char(34)` / `string.char(92)` 构造这类字符，抽成一个小函数（`tbSafeName`）复用；★同时把 `luacheck.js` 改成**逐个文件**检查（当时 27 个 .lua），语法错误再也漏不过去。
- 4.3 配置窗 Tab② 原文：「1.20.0 起底部的图标选择器/条件输入框/`EVAL_WAR_ADD_FROM_UI` 已删除，**新增技能走编辑窗**」。
- 5.4 分享弹窗坐标原文：「坐标 `SH_SEAL_ROW_Y` -50→-46·`SH_DETAIL_Y1` -74→-66·dPanel 顶 -46→-42」。
- 5.4 可点品阶色链接原文补充：「（`|HEHPF:<id>` 形态，封皮 B 行与场景描述头衔同款）；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本」。
- 5.4 品阶显示条原文：「★纯黑＝`EVAL_SHARE_SEAL_ICON` 两返回值内联进 `pcall(t.SetTexture,…)`⇒多返回值禁内联进可变参数调用」。

### R11. §5.2 的 1.73.24~1.73.41 弹窗/菜单细则条目（整批迁入）

> 这些条目判据仍然有效，只是年代较早、引用频率低；常驻卷只留高频条目。

- 右键菜单（1.73.24）：有 `GuildInviteByName`/`CanGuildInvite`；无剪贴板接口、无 `UIDropDownMenu`；`SetItemRef` 可写 → 包它 + 读回确认 + 幂等，只认 `player:` 右键；`/s` 走 `RunScript` + 0.5s 去抖；组 130。
- 资源名必须显示时现算（1.73.27）：`UnitPowerType` 0 法力/1 怒气/2 集中值/3 能量、随形态变 → 写死在表（`COND_NUMNAME.powerPct`）即错；显示名一律 `EVAL_POWERLABEL()`、四处同源；改显示名＝改导出文本 → 解析侧同时认新写法；组 132。
- 「填进输入框」≠「替用户发送」（1.73.29）：只预填不回车、不碰 `SendChatMessage`/`RunScript`；判据双向：内容对 + 一个字都没发；共用 `tbMenuPrefill`。
- 标题栏宽度自适应（1.73.30）= 纯函数拼分隔条：`EVAL_TB_HDR_TEXT(标题,列宽)` 剥装饰后按列宽补破折号；读值口 `EVAL_TEST_TB_HDR_TEXT` 读真控件、逐字相同；「—」三字节 → 绝不写 `[—]`。
- 弹窗规程（1.73.31~36）：层级全 `DIALOG`（10~250 八级，`EVAL_TN` 220、`EVAL_DD_OPEN` 250 最高）；①子弹窗层级必须高于父弹窗；②只设 strata 没设 frame level = 点击不到 → `SetFrameLevel(root,200)` + `EnableMouse(true)`；③可拖拽 = Button 柄 + 三件套 + level=窗口+1 + warm-up；④布局跟窗宽走、不写死 x、文案由调用方给；⑤位置按字面拆 = 左下角贴光标 + 坐标除缩放。
- 布局异常（1.73.33）：①锚点偏移算错（距右边误填距左边的数 → 列头叠画）→ 列几何单一来源（全用「距左边」、列头宽度 = 本列宽度）；判据 = 列头右边缘 == 该列数据右边缘 + 列头互不重叠；②能不能拖先问「有没有柄」。
- 滚动条规范（1.73.34）：①滚轮要显式 `EnableMouseWheel(true)` + `SetScript("OnMouseWheel")`，方向单一来源 `EVAL_WHEEL_DIR(a,b)`；②`off` 双侧夹；③到顶/底、空列表藏箭头；④▲▼不许压数据列 → 专用滚动槽；⑤页码必须整数、末页特判；⑥箭头与指示同一口径。★1.74.30 起升级为「连续窗口」（页码/末页改为行偏移/窗口，见常驻卷 §5.4 滚动模式唯一标准）。
- 右键菜单条件门 + 名字→unit（1.73.35）：①条目出不出现由 `CanGuildRemove()`/`CanGuildInvite()`/`GetNumPartyMembers()>0` 在建菜单时决定；②名字→unit 只扫本机看得到的单位，解析不到如实退回；③查询不许直调 `SendWho` → 走 `EVAL_TB_WHO_ENQUEUE`；④两列 + 宽高由条目数算（`EVAL_TB_MENU_LAYOUT`）。
- 聊天提示搬进弹窗 = 判据跟着落点走（1.73.35）：判据改到弹窗正文 + 「知道了 → `cfg.loadMsgSeen=true` → `EVAL_LOADPOP_SHOW()` 返 false」；按钮判据走真实 `GetScript("OnClick")`。
- 「点了没反应」两根因（1.73.37）：①闭包捕获建菜单那一刻的名字快照（首次右键 nil）→ 名字先写再建 + 闭包改点击时才读；②「关闭」传空函数。判据必须走真实 `OnClick` → `EVAL_TEST_TB_MENU_CLICK(标签)`；测试先用 `EVAL_TEST_TB_MENU_DROP()`；冗余守卫要整组拆。
- 「接收方要支持私聊」（1.73.38）：接收帧本来就注册 `CHAT_MSG_WHISPER`；`IsEventRegistered("CHAT_MSG_WHISPER")` + 用真实路径 `EVAL_SHARE_ONMSG(msg,sender,"CHAT_MSG_WHISPER")` 喂密语分片。
- tooltip 也要列全 + 分层（1.73.38）：金色标题 + 每功能一行 + 灰色注意行，用 `\n` 在一条 `AddLine` 里分行；判据 = 逐个功能名都出现 + 含颜色码 + 含换行。
- 同一内容不要两处各写（1.73.41）：入口全走 `EVAL_HELP_GUIDE`，内部优先 `EVAL_LOADPOP_SHOW`、弹窗不可用才退回聊天打印；判据让 force 承重：`cfg.loadMsgSeen=true` 再点「使用引导」仍必须弹。

### R12. §5.4 的布局细则条目（整批迁入）

> 同样是「判据有效但引用频率低」的一批；常驻卷 §5.4 只留 ★★★ 级与用户点名的判据。

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

### R13. 关键源码检查在守什么（1.74.32 从常驻卷 §5.10 迁入）

> 从常驻卷迁出的原因：这份「一句话清单」与 `test_engine.js` 里的实现**同源**，真正要查全清单时直接看 `test_engine.js` 更快；
> 常驻卷只留一行指针。★判据本身仍然有效（每道检查都做过变异验证）。

- `FRAME NAME CLASH`（具名帧撞全局函数）· `WTT ISOLATION`（禁借 GameTooltip，★扫描前摘注释）· `CHAT COLOR WIRING`（读回确认 + 幂等守卫）· `COLOR CODE LEN`（色码 8 位 + 禁 `"|c"..string.sub(`）· `SHARE MSG SHAPE` / `SHARE PALETTE`（分享形态 / 色表）· `MENU ROUND CHROME`（圆角边贴图）· `TEMPLATE COUNT` · `WHEEL DIRECTION` · `SHARE RECV EVENTS`（接收帧七事件全注册）· `UI CELL MOUSE`（左右键分派）· `DF BARS WIRING CHECK`（候选名解析接线，1.74.31）· `DF ROSTER WIRING CHECK`（队伍/团队「按需出现」的事件跟随接线，1.74.32）。
- 其余：`EXAMPLES TOC` · `STOP ATTACK WIRING` · `PET ICON` · `LANG KEY` · `DECL ORDER` · `PAINT WIRING` · `DEBUFF DISPLAY` · `CREATOR GATE` · `SH FUN` · `PROF ICON PROBE WIRING` · `UI TITLE BADGES`/`UI TIER BADGE`/`UI TITLEBAR`/`UI TITLE NAME`。

### R14. §5.4 的分享弹窗与彩蛋条目（1.74.32 迁入）

> 迁出原因：这 4 条判据**仍然有效**，但引用频率低（彩蛋两条自 1.74.5 起就没接线）；
> 常驻卷只留一行指针，需要时回到这里读原文。

- ★分享弹窗：摘要行⇒「X 分享的 [品阶秘籍·名]」带品阶色；品阶行只留图标、删重复文字（`EVAL_SHARE_SEAL_ROW` 被组 145 等用）；组 145；★改 UI 文案要同步反转旧判据。
- ★可点品阶色链接（`|HEHPF:<id>` 形态）：点它靠 `EVAL_SHARE_CLICK_OPEN("EHPF:<id>")` 在 `SH.recent` 找（用 `SH.pending.idh`）⇒ 重填 `SH.pending` 弹出接收页；超 `SH_MSG_MAX`/缺 id ⇒ 退回纯文本；`shReactionNameLink(p)` **保留但未接线**（彩蛋取消）；判据组 180②。
- ★彩蛋角色扮演反应（1.73.64 建 · **1.74.5 起未接线**）：机制与三语言 50 格文案**全部保留**、只是 [导入]/[忽略] 不再发（改发「场景描述」）；`SH FUN CHECK` 钉「机制都在 **且** 调用点未接」＋组 82④⑤ 反向哨兵。
- ★彩蛋创世者亲临闸门：手动方案有**神级**（封顶后 ≥50，`EVAL_SEAL_GOD_SCORE()` 现算）· 手动 **≥3 个** · 头衔满档 5；`src`：手工 `"manual"` / 文本解析唯一出口 `EVAL_PROFILE_FROM_TEXT` 盖 `"text"` / 老存档无 `src`⇒按手动；堵 `EVAL_TITLE_CREATOR_OPEN`/`EVAL_TITLE_CREATOR_TRY` 两条路；`EVAL_TITLE_EGG_CHECK()` 挂 `EVAL_WAR_TAB_REFRESH`＋登录、只播一次；组 169/150＋`CREATOR GATE CHECK`。

### R15. 真机窗口帧名实测清单 + 客户端取证踩坑全案（1.74.32）

> 这一批全是**真机一次探针跑出来的事实**（`/eh go 框体探针` → 落存档 `EVAL_HELP_CONFIG.dragBars` → 外部读），
> 不是查文档也不是猜的。**下次要动「别人的窗口」，先看这里，别重新探一遍。**

**① 被动打开窗口的真名（探针实测，全部存在）**
- 尺寸统一 **384×512 / lv=1**（打开着的窗口 lv 会变高，实测 `CharacterFrame` 打开时 lv=8）：
  `GuildFrame`(公会) · `CharacterFrame`(属性) · `MailFrame`+`InboxFrame`+`OpenMailFrame`(邮箱) ·
  `QuestFrame`(任务对话) · `SpellBookFrame`(技能树) · `TradeFrame`(交易技能) · `MerchantFrame`(商人) ·
  `FriendsFrame`+`FriendsListFrame`(好友) · `BankFrame` · `BattlefieldFrame` · `DressUpFrame` · `GossipFrame` ·
  `GuildRegistrarFrame` · `ItemTextFrame` · `LFTFrame` · `PetStableFrame` · `PetitionFrame` · `TabardFrame` ·
  `TaxiFrame` · **`ClassTrainerFrame`(训练师 —— `TrainerFrame` 这个名字**不存在**，靠候选表第二个名字才探到)**。
- 其它规格：`QuestLogFrame` 704×512 · `HelpFrame` 640×512 · `ShopFrame` 700×460 · `SoundOptionsFrame` 400×570 ·
  `WorldStateScoreFrame` 640×512 · `LootFrame`/`ContainerFrame1..12` 256×256（背包） · `OneBankFrame` 400×400（OneBank）。
- 子弹窗（**不是**主窗口，别当目标）：`GuildControlPopupFrame` 297×298 · `LFTGroupReadyFrame` 308×220 ·
  `StationeryPopupFrame` 220×298 · `LFTGroupReadyStatusFrame` 360×152 · `LFTRoleCheckFrame` 250×200。
- **队伍没有整队容器**：`PartyFrame`/`PartyMemberFrameContainer`/`PartyFrameContainer`/`PartyContainer` **全不在**，
  只有 `PartyMemberFrame1~4` 四个独立帧 ⇒ 目标表拆成「队伍成员1~4」（用户 1.74.32 定）。
- 满屏（`1228.8×768` = UIParent 尺寸）的全是**事件帧/遮罩**，不是窗口：`EVAL_*`、`UnrealQuest*`、
  `AceEvent20Frame`、`CinematicFrame`、`WorldMapBlackout`、`UIOptionsFrame`、`SoundOptionsFrame`、`StatsFrame`。
- **仍未探到：拍卖行**（`AuctionFrame`/`AuctionHouseFrame`/`AuctionFrameContainer` 全不在、`auction` 关键词命中 0、
  兜底清单里也没有）—— 客户端**确实在跑** `Blizzard_AuctionUI`（它自己在写 SavedVariables），
  所以最可能是**匿名窗口**（`CreateFrame("Frame", nil, UIParent)`）⇒ 只能靠父子链取证（见下）。

**② 客户端取证踩坑全案（每条都真金白银踩过）**
1. **真机 SavedVariables 带 UTF-8 BOM**（`EF BB BF`）：直接丢给 Lua 报 `unexpected symbol near '<\239>'`
   ⇒ 读之前**先剥 BOM**（与当初 PowerShell 写文件那次是同一个符号）。
2. **全 `_G` 扫描是本模块第一处索引「任意全局」的代码**：`_G` 里有些对象是**不可索引的 userdata**
   ⇒ 一句 `f.GetParent` 就抛 `attempt to index local 'f' (a userdata value)`，**把整个探针打断**，
   而报错行看起来跟"帧名"毫无关系。修法 = `dfFrameUsable`（pcall 探测 + 只放 table/userdata）。
3. **`_G` 里同名子件成千上万**：光 `ActionButton*` 的贴图/文字/冷却圈就有 2900+ 个
   ⇒ 必须按 `GetObjectType()=="Frame"` 过滤，否则把 SavedVariables 灌成几百 KB；★判不出类型时**不许丢**。
4. **匿名窗口 `_G` 扫描永远看不到**（只认挂在 `_G` 上的具名帧）⇒ 只能走 `GetChildren()` 父子链两层，
   并**用「具名子件」当身份指纹**（匿名父 + `AuctionFrame*`/`BrowseButton` 这类子件名 = 认得出是谁）。
5. **`GetChildren()` 返回多值不是表** ⇒ 必须 `{ pcall(fr.GetChildren, fr) }` 再遍历；
   写成 `local kids = fr:GetChildren()` 只会拿到**第一个**子件（静默少数据）。
6. **父级「名字」不可靠**：`GetName()` 可能返回 nil（测试桩里 `UIParent` 就是匿名帧）
   ⇒ 判「宿主是谁」一律**比对象身份**（`p == rawget(_G,"UIParent")`），按名字判会一条都匹配不上。
7. **桩不保真三连**：桩原本**没有 `GetChildren`**（宽容兜底给一个返回 nil 的函数 ⇒ 父子链永远空）、
   fengari 是 Lua 5.3 **没有全局 `unpack`**（`unpack(children)` 直接报错、又被 pcall 兜住 ⇒ 表现成"什么都取不到"）、
   `UIParent` 在桩里无名。★都按「桩保真」补上了（补 `GetChildren` + 垫 `unpack`）。
8. **Lua 的 `a and f()` 只保留第一个返回值**：写成 `local p, _, rel = btn and btn:GetPoint(1)` ⇒ 后两个恒 nil，
   断言读到 nil 还以为锚点没设上（本轮 组212⑤ 就是这么误报的）。多值必须**先判后取**。
9. **`/eh go` 别名撞车是静默的**：新命令写了 `go icons` 当英文别名 —— 而 `go icons` 早就被**组 116 的图标路径采集**占了，
   分派是 elseif 链 ⇒ 先命中的赢，那条命令被**静默顶掉**（症状：用户跑 `/eh go icons` 得到完全不相干的行为）。
   现在有 `GO ALIAS UNIQUE CHECK` 守（按**缩进**识别分派链，同分支内的嵌套 `if` 不算新分支）。
10. **取证命令绝不许静默**：子插件那句裸 `pcall(EVAL_DF_PROBE_BARS)` 会把错误吞掉 ⇒ 真机上表现为
    「跑了命令、聊天框空的、存档里连键都没有」，**无法区分**「没跑到」与「跑了一半死了」。修法 = 三态阶段标记
    （`start`/`done`/`error` + 错误原文落档）+ 统一安全入口 + 命令先打一行「命令已收到」即时回显。
11. **拖拽机制会吃掉点击**：`dfDragBegin` 一 Show 全屏接盘（level 800，高于任何窗口图标）⇒ 图标自己的 `OnClick`
    **永远收不到**松手事件。修法 = 在 `dfDragEnd` 里判「按下了但没移动」（`st.moved` 是拖拽机制**自己算的**阈值，
    唯一真值），由它开属性弹窗。
12. **「像窗口」的判据要宽高都够大**：只用一个维度（`w>=200 or h>=200`）会被 400×120 这类条状件占满，
    真窗口反被清单上限挤掉（测试环境当场暴露，真机同样会）。

**③ 从常驻卷迁入的「名字着色族」原文（1.74.32 迁入）**
- 名字着色族（1.73.18~51）：名字在 `arg2`；名字槽不吃富文本 → 吞行自拼；色码必须 8 位 → `COLOR CODE LEN CHECK`；
  缓存唯一 = 名字→职业 token（`tbNameClassPut`）；四来源 = 白拿/`EVAL_TB_NAMECLASS_HARVEST(kind)`//who/事件；
  名册懒加载（`GetNumGuildMembers()` 恒 0）→ 自愈 `EVAL_TB_NAMECLASS_HEAL()` + 一发 `GuildRoster()`；
  `TB_NAMECOLOR_WRITE=false`；组 129b/161 + `NAME CACHE PROBE WIRING CHECK`。

**④ 从常驻卷迁入的「图层树折叠 / 层深」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★★**图层树的层级只能来自「扫描时写下的层号」，不许数路径里的 `/`**（1.74.31）：`scanTree` 递归写 `d = depth + 1` 进节点、`uiBuildEntries` 带进条目 ⇒ 缩进与「层深」过滤**同一口径**。理由：① 根/子条目路径形态不一（前缀源多一层），按路径切父级对不上；② 同帧多区域路径**同名**不唯一；③ 过滤藏掉中间层 ⇒ 按过滤后列表算父子会漂移。
  【父子】`uiTreePass`：DFS 前序 + 未闭合祖先栈，层号 ≤ 栈顶就弹；`uiFiltered` 懒补算；折叠 `ui.treeCollapsed[路径]` 落存档（读回只收「值为真 + 键是字符串」）。
  【三态别混】行上 `▶/▼` 三来源：① 折叠 ② 层深上限卡住本层 ③ 子层被别的过滤藏了（`e.visKid` 记账）⇒ 只有 `(e.kids or 0) > 0` 且（已折叠/被卡住/有可见子层）才画开关，叶子不画。
  【层深 = 展开到第 N 层】唯一写入点 `uiDepthApply`；`0`（全部）**一个标记都不清**；点 ▶ 在「被卡住」时 = 上限抬到本层+1。判据：`DBX TREE WIRING CHECK` ＋ **组 205**；字形 `UI_TREE_OPEN=▼`/`UI_TREE_SHUT=▶`（`▸` 未验证）。

**⑤ 从常驻卷迁入的「只读取证要用哨兵钉住」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★**声明「本次只取证、行为零变化」时，要用哨兵把它钉住**（1.74.32 第 1 步）：被动打开层候选挂成独立清单 `DF_WIN_CANDS` 喂探针（**不进** `DF_TARGETS`）⇒ 源码检查加「候选与 `DF_TARGETS` 零交集 + 目标数 == 12」两条哨兵（★第 2 步实现图标时要一起改掉，代码里有注释提醒）。理由：不小心接进去**不报错**，只是这些窗口突然被贴上整条透明柄。
  ★**通用形态**：凡是「本轮只取证 / 只搬代码 / 只接线，行为不变」的承诺，都要能**用源码检查或断言把它钉死**，否则它只是一句口头承诺 —— 而这类改动的错法恰恰是「悄悄多做了」。

**⑥a 「图层选择」多选下拉全案（1.74.33 用户：「拖拽图层右侧添加设置弹窗支持这么多种类的支持多选的下拉选择，选中的才开启配置和支持拖拽」）**
- **需求**：工具箱 → 拖拽图层行右侧 `[设置]` 弹一个**多选下拉**（38 个目标分三组：① 框体柄 1~10 ② 队伍/团队 11~15 ③ 图标形态窗口 16~38），**勾上的才贴柄/挂图标/应用存档属性/可拖**。
- **真值**：`EVAL_HELP_CONFIG.dragFrames.pick[目标名] = true`；★**表不存在 = 全选**（老存档升级后行为必须与升级前一致）；唯一写入口 `EVAL_DF_PICK_SET(name, on)`。
- ★★**第一次写必须先把「全选」快照物化进表**：老存档里 `pick` 不存在 ⇒ 用户取消勾一个，如果只写 `pick[name]=false`，其余几十层因「表里没键」全部变成未选中（**静默关掉几十个拖拽**，用户以为插件坏了）。物化 = 写之前先按 `DF_TARGETS` 把全部目标填成 true，再改这一项。
- **七条路径都要过 `dfPicked(name)`**：贴柄 `dfRefresh` · 挂图标 `dfIconsRefresh` · 应用存档 `dfApplyAll`/`dfKeepTick`/`dfApplyOne` · 事件结算 `dfRosterPass` · 清理 `EVAL_DF_RESET`。★未勾选的层**记录与属性都不动**（不重锚、不改宽高、不重置），并在播报里**如实报数**（不许假装全都处理了）。
- **单一来源**：下拉内容 = `EVAL_DF_PICK_MENU()`（从 `DF_TARGETS` **现生成**；组标题行走 `locked[i]`（无勾选框、点了不响应）+ `names=nil`）⇒ **工具箱不许有第二份目标表**。
- **判据**：组 214（名单/分组/物化快照/七条路径逐条）+ `DF PICK WIRING CHECK`（真值 + 物化 + 七处 `dfPicked` 门 + 工具箱槽位几何 + 无重复目标表）；变异 M1~M17（含「摘掉图标那道门」「换回 chv 槽」）全捕获。

**⑥ 同一条带上的两个控件 = 遮挡（1.74.33 真机 + 源码双重踩坑全案）**
- **真机侧**：被动窗口的「配」图标原本锚 `TOPRIGHT`、偏移 `-34`（注释写着「要大于关闭按钮宽度」）⇒ 用户截图：**法术书的关闭按钮被「配」压住**（红圈里两个控件叠在一起）。修法 = 右边距抬到 **58**（按关闭按钮 40px 带宽 + 18px 间隙算），图标横跨 `[W−78, W−58]`。判据 = 组 212⑤b（**验性质**：图标右边距 ≥40px，不写死 58）。
- **工具箱侧**：图层拖拽行要放**两个**按钮 ⇒ `[设置]` 用 `r.add`（cRight−96 宽 44）、`[重置]` 原本还在 `r.chv`（**同起点、宽 88**）⇒ 后建的 chv 压在上面，`[设置]` **永远点不到**；而「按钮存在 + OnClick 已挂上」的断言**全绿**（第一版就是这样漏过去的）。修法 = `[重置]` 改挂 `r.clr`（cRight−48 宽 40），两块并排留 4px 缝。
- **两类判据都要有**：① 行为侧 = `EVAL_TB_TEST_ROW_BTNS(key)` 读两个控件的几何，断言 `[设置]右边界 ≤ [重置]左边`；② 源码侧 = `DF PICK WIRING CHECK` 的几何哨兵（lddrag 分支必须 `r.clr.btn:Show()` 且**不许出现 `r.chv.btn`**）。变异 M16/M17（各自换回 chv 槽）都被断言捕获。
- ★**教训一般化**：**「控件建出来了」不等于「用户点得到」** —— 凡是同一行/同一角落放多个控件，或往别人的窗口上贴东西，都要问「它盖住谁 / 谁盖住它」，并把这条写成几何断言。真机截图是唯一能发现「压住原生按钮」的手段（`GetNumPoints`/`IsShown` 都看不出来）。

**⑥b 「头部拖拽带」（1.74.33 用户：「窗口拖拽的区域能否定位到 窗体头部红色部分?」）全案**
- **需求**：图标形态的窗口原来只有右上角 20×20 的小图标能拖；用户截图（任务窗口顶部红线）要求**整条标题栏都能抓**。
- **实现**：再建一条**透明 Button** 贴顶部（`dfHeadBuild`）——`TOPLEFT` 锚在 `(DF_HEAD_LEFT=4, -DF_HEAD_TOP=3)`、宽 = `窗口宽 − DF_HEAD_LEFT − DF_ICON_RIGHT − DF_ICON_SIZE`、**高 `DF_HEAD_H`（1.74.33 用户追加「向下再延伸 15px」⇒ 18 → 33，上沿不动只向下长）**；鼠标分工与图标**共用** `dfBindDragButton`（左键拖窗口 / 右键开属性窗 / 悬停出说明）。
  ★**高度改数字不会卡判据**：组 215① 只验**性质**（控件真实高度落在 10~48 这一档），不钉死 18/33；要按窗口单独调矮时改这一处即可。
- ★★**两项都要减**（这是本轮第二次同类事故）：只减「关闭按钮留空区」时，带的右端正好落在**图标右边界**上 ⇒ 带把图标整块盖住、**右键点不到图标**；组 215③ 的几何断言当场抓到（带右端 326 > 图标左边界 306）。
- ★★**读值口必须现读控件几何**：组 215 第一版的 `h` 直接回常量 `DF_HEAD_H` ⇒ 变异 M28（`SetHeight` 改成 200、带盖住整窗）**照样绿**——这是「写死布局常量＝测自己」的又一例。改成现读 `GetHeight()` 并**验性质**（≥10 且 ≤40：只许盖标题条那一带）后，M28 被捕获。
- ★★**「初始值」被刷新覆盖 ⇒ 打它的是行为等价变异**：`dfHeadBuild` 里的初始 `SetHeight` 每次 `dfIconEnsure` 都会被重设 ⇒ 只改初始值的变异（M30）**应该存活**，别当成漏检；要打得打**权威赋值点**（`dfIconEnsure` 里那道）。
- **随勾选/开关一起收**（`dfIconsRefresh` 的收尾循环里 `rc.head` 与 `rc.b` 必须同进同退）：只收一个会留下**一条看不见却吃点击的带子**，而且这种「透明控件没被收掉」在界面上完全看不出来。
- **判据**：组 215（①在位/层级+10/真实高度只盖标题条 ②右端 ≤ 宽−58 且够宽 ③与图标不重叠 ④左键拖头部落存档且不弹窗 ⑤右键开窗 ⑥取消勾选一并收起）+ `DF ICON ART CHECK`（带的宽度公式必须呈「宽 − 左让开 − 留空区 − 图标宽」形态）；变异 M24~M29 全捕获、M30 为等价变异。
- ★★**图标边距两处都是真机截图改出来的**（同一个「只能靠真机看」的量，改法只有一处）：
  · **右边距 34 → 58**（`DF_ICON_RIGHT`）：34 让「配」压在**窗口自带的关闭按钮**上（法术书截图，两个控件叠在一起）⇒ 组 212⑤b 验性质「右边距 ≥40px」。
  · **上边距 6 → 18**（`DF_ICON_TOP`，1.74.33 用户第二次微调：「窗口的属性打开图标可以再往下移动12像素」，截图 = **好友名单**窗口）：6 让 20×20 的图标**骑在窗口上边框上**（上半截落在标题栏外，像挂在窗口沿上）⇒ 下移 12 ⇒ 图标纵向跨 [18, 38]，整块落进标题栏；组 212⑤c 验性质「上边距 ≥12px」。
  · 变异验证：把 `DF_ICON_TOP` 改回 6 ⇒ 组 212⑤c **当场报红**（`tmp/mut_icontop.js`）—— 证明这条断言真的**现读控件几何**，不是回读常量（回读 = 测自己）。
- ★图标与头部拖拽带**横向相邻、不重叠**（带的右端 = `W − DF_ICON_RIGHT − DF_ICON_SIZE`，组 215③ 守它）⇒ 图标纵向挪多少都不会被那条带盖住；而且两份控件共用**同一套鼠标分工**（`dfBindDragButton`：左键拖窗口 / 右键开属性窗），所以哪怕真叠上，行为也一样（但断言仍按几何查，别依赖这个巧合）。

**⑥c 拖拽「位移叠加漂移」全案（1.74.33 用户：「窗口拖拽有些会有位移叠加漂移，比如角色等其他测试。你拍下什么问题」）**
- **现象**：缩放 ≠ 1 的窗口（角色/法术书……）**每拖一次就多漂一个固定量**（越拖越偏），而且**第一次拖拽就比光标跑得远**；缩放 = 1 的窗口完全正常 —— 所以只有「有些窗口」。
- **真因（三层，缺一层都修不对）**：
  1. `dfCapture` 算锚点偏移用的是 `x = GetLeft + GetWidth × 系数 − 相对帧锚点` —— `GetLeft/GetBottom` 是**屏幕**坐标、`GetWidth/GetHeight` 是**帧本地**尺寸（含缩放），只在缩放 = 1 时同口径 ⇒ 每次捕获都把 `w × 系数 × (1 − s)` 掺进偏移。
  2. 那个偏移是**从几何反算**的（不是 `GetPoint` 原值），与 `SetPoint` 要的偏移差一个**常数**（单位口径 + 锚点系数叠加）⇒ 「按实测系数 k 反解」（`偏移 = 位移 / k`）**解不掉**：它假设响应过原点，实际是 `屏幕 = 常数 + 折算 × 偏移`。★第一版就栽在这里：单次拖拽对（40→40）、**连续三次仍叠加**（90→118.9）。
  3. 尺寸在拖拽**中途**变化时（队伍框来人 ⇒ 行数变了），旧口径记的是 `Δ(屏幕底边 + 本地高度 − 相对锚点)`，会把 `Δh` 当位移记进存档（夹具实测：光标只动 20px，存档记成 68）。
- **修法（口径与单位无关，不猜文档）**：
  · `dfCapture` 除锚点四元组外再记**实测屏幕位置** `out.l/out.b`（命名键、不进数组部分）；老记录没有它们 → 退回旧的纯锚点平移（**不假装能修**）。
  · 位移/落锚唯一入口 `dfPlaceFrom(fr, cap, dx, dy)`（`dx/dy` = **屏幕**单位）：首猜「偏移增量 = 屏幕位移 ÷ `GetEffectiveScale`」→ 落锚 → **量回**（`dfMeasure`）→ 差值是那个**常数**（与位移大小无关，一步消掉）→ 还没到位就用**两次落点手量真实折算**（`Δ屏幕 / Δ偏移`）再修，≤3 轮。返回的 k = 本次折算（**量出来的**；1 表示偏移即屏幕单位）。
  · `dfDragUpdate` 用**光标累计位移**（`cx − st.cx0`，**不除缩放**）喂 `dfPlaceFrom`；`dfDragEnd` 对新式基准记**屏幕差** `rec.dx = fin.l − rec.base.l`；`dfIsAt` 也改按屏幕比；`EVAL_DF_RESET` 走 `dfPlaceFrom(fr, rec.base, 0, 0)`。
  · 实测折算 `|k − 1| > 0.02` 时**在聊天里如实播报**（用户能看到「这个窗口为什么要折算 · 不再叠加」）；读值口 `EVAL_DF_TEST_STATE().lastK`。
- **判据**：组 217（①单次 40px 1:1 ②k ≈ 0.8 ③播报 ④**连续三次各 30px 总位移 = 90**（旧口径 ~118+）⑤纵向 1:1 ⑥「应用存档」回同一屏幕位置 ⑦拖到一半改尺寸仍记 20px 而不是 68）；桩里按真机语义造 1024×768 屏 + 缩放 0.8 的窗口（**UIParent 左下角故意不在 0**，否则单位错会被抹平）；变异 `tmp/mut_drift.js` **6/6**（M35 去掉量回自证→④ · M36 结算退回锚点相减→⑦ · M37 不记屏幕基准→② · M38 去掉修正循环→④ · M39 播报不报系数→③ · M40 `dfIsAt` 永远 true→组204）。
- **测试教训**：① 夹具必须**自洽**（第一版把屏幕基准塞进帧、UIParent 却留在 0 ⇒ 量出来的系数毫无意义，单次断言当场就红）；② 「把窗口挪歪」不能靠替换 `SetPoint`（不调用就不发生），要**直接改夹具的位置状态**；③ 让夹具的**尺寸可中途变化**，否则「尺寸掺进位移」这条路径**测不出来**（M36 会漏）。

**⑥d 开窗探针：被动窗口「打开时重设属性」的可行性取证（1.74.33，用户提问待确认）**
- **用户问题（原话）**：「图层拖拽->被动类窗口能否在打开的时候进行自定义属性重设.或者定时重设? 验证可行性 待我确认」
- **为什么这不是「顺手加个 tick」**：被动窗口（公会/属性/技能树/任务…共 23 个 `icon = true` 目标）的**自定义属性**
  （显隐/缩放/透明度/宽/高）现在只在**四个时刻**写：登录恢复 `dfApplyAll`、拖拽结束保存、显式应用、
  `dfApplyOne`（队伍帧出现时）——`dfAttrsApply` 的注释原文就是「**不做周期性写入**」；
  而 `dfKeepTick` 那套有界复查**只重锚位置、不碰属性**。所以「客户端在开窗时把自己的尺寸摆回去」这件事，
  我们现在**既没侦测、也没补救**（若真发生，用户看到的就是「我配的缩放/宽高，开了窗口就没了」）。
- ★**先取证再动代码**（铁律 4/5）：判断「要不要做」需要真机证据，而不是猜；`/eh go 开窗探针` 就是那件取证工具。
- **探针的四条契约**（错一条，真机取证就会得出错结论 —— 比不做更糟）：
  ① **只读**：只 `IsShown/GetWidth/GetHeight/GetScale/GetAlpha/GetLeft/GetBottom`，一个写接口都不碰
     （判据 = 组 218①：把夹具的 `SetWidth/SetHeight/SetScale/SetAlpha/Show/Hide` 全包计数 ⇒ 必须为 **0**；
     变异 M41「偷偷写一次 SetWidth」当场报红）。
  ② **显隐跳变 = 开窗的唯一可靠证据**，且**前后属性都要记**（前 = 我们写进去的值、后 = 客户端改成的值）——
     这一对就是答案；变异 M44（不记开窗事件）被组 218③ 捕获。
  ③ **开着时被改另记 `attrChange`，位置变化记 `posChange`**（本项目自己的有界复查也会动位置，不许混算）。
  ④ **有界**：武装 60 秒（`DF_ATTR_PROBE_SECS`）× 采样 0.25 秒，到点自停**并摘掉脚本** ——
     本客户端隐藏帧的 `OnUpdate` 照样触发，「只 Hide 不摘」= 永远空转（变异 M42 捕获）。
- **采样策略**（省开销）：每轮只读 23 个目标的 `IsShown`（便宜）；**窗口开着**（或还没有基线）时才读几何 ⇒
  成本与「当前开着几个窗口」成正比，通常每轮只有几次 API 调用。
- **落档**：`EVAL_HELP_CONFIG.dragAttr`（三态 `phase = start/error/done` + `caps` 能力清单 + `rows` 逐目标
  「存档要的 vs 关着时 vs 打开后」+ `events` 事件表）；`/eh go 开窗探针 看` 可复读。
  能力清单要报的三件事：每个目标的 `GetScript("OnShow")` 真值（**链式接管**的必要性）、`type(fr.HookScript)`、
  `type(fr.Show)`、以及全局有没有 `hooksecurefunc`（本客户端**没有**）。
- **命令**：`/eh go 开窗探针`（武装 60 秒）· ` 停`（提前收工，原因记 `manual`）· ` 看`（复读上次落档）。
- **判据**：组 218（①只读哨兵 ②命令入口武装+心跳 ③开窗事件前后对照 ④attrChange ⑤posChange
  ⑥OnShow 三态如实 ⑦到点自停且摘脚本 ⑧三态落档+计数汇总 ⑨停/看两条路）+ `DF PROBE SAFE CHECK`
  （新探针也守三态与 pcall：心跳里 `pcall(dfAttrPStep)`、出错即停并落错误原文）；变异 M41~M45 **5/5 捕获**。
- **测试教训**：夹具要**自己建**（前面的组收尾会把 `_G["GuildFrame"] = nil`）且建完必须 `EVAL_DF_TEST_TARGETS_RESET()`
  清解析缓存，否则探针解析到别组留下的旧对象、夹具上做的一切都测不到；
  「只读」这类承诺必须用**写接口计数器**钉住，光靠「代码里没写 SetXxx」是口头承诺。
- **待用户确认的三个方案**（取证结果出来后再定）：**A** 链式接管 `OnShow`（零轮询，推荐）·
  **B** 只在既有有界复查窗口里顺手重设属性（不改侦测）· **C** 开窗后武装一个 1~2 秒的短复查窗口
  （对付「客户端在 OnShow 之后一两帧才摆好尺寸」）。**都不新增常驻轮询**。
- ★★★**第一轮真机取证结果（用户已跑完：60 秒 · 227 轮采样 · 23 个被动窗口 · 21 条事件）**：
  · **结论 1（属性没被覆盖）**：唯一配过自定义属性的目标（**属性窗口**，只配了缩放 0.7）开窗后实测仍是
    `w=268.8 h=358.4 sc=0.70`，与存档一致 ⇒ **没有被客户端改回去**（落档 `armOK=1/armMismatch=0`、
    `openOK=1/openMismatch=0`）⇒ 就这一条而言「打开即重设」**不是必需**的。
  · **结论 2（但客户端确实会重写尺寸）**：**任务窗口**开窗那一刻宽从 384 → **704**（它的原生规格就是
    704×512）⇒ 客户端在开窗时按**自己的规格**摆尺寸。这次因为它**没配自定义宽高**所以判不出「会不会盖掉我们的值」
    ⇒ 这正是第二轮要问的问题（见下）。
  · **结论 3（侦测手段）**：`hooksecurefunc` 没有，**`Frame:HookScript` 也没有**（23 个目标全 `nil` —— 本轮新量的
    客户端事实）；而 **21/23 个被动窗口原生都挂着 `OnShow` 脚本**（`MailFrame` 明确没有、训练师那层当时不在位读不到）
    ⇒ 将来若要做「打开即重设」，**只能链式接管 `OnShow`**（`GetScript` 存原脚本 → 自己的脚本里**先调原脚本**
    再干自己的事），**绝不能覆盖式接管**（与滚轮链式接管同一纪律）。
  · **结论 4（开窗后没有二次改动）**：`attrChange` 事件 **0 条** ⇒ 没有「开窗后一两帧又被改一次」的现象 ⇒
    方案 C（开窗后短复查）在本次证据里**没有必要性**。
  · **附带发现（位置 ≠ 属性）**：多个目标「关着」与「打开后」的 `left` 读数差很大（属性窗口关着读 655.15、
    打开后读 0），开窗后还有多串 `posChange` ⇒ **隐藏帧的位置读数不可信**（客户端开窗时才真正摆位）；
    而缩放/宽/高/透明度的读数稳定可信。→ 将来任何「按读数判断位置」的逻辑都要记住这条。
  · **口径修正（本轮当场抓到的判据 bug，已修）**：`GetWidth/GetHeight` 含缩放 ⇒「存档要 384×512 + 缩放 0.8、
    实测读回 307.2×409.6」直接比会**假报「被客户端覆盖」**。修法 = `dfAttrPMismatch` 先比原值、不等再比
    「存值 × 实测缩放」，两者都不等才算真不符；「折算后一致」单独落 `foldedArm/foldedOpen` + 计数 `foldedN`
    （**不计入**不符）+ 播报单独一行。判据 = 组 218⑩；变异 M46 捕获（本轮 6/6）。
- **第二轮取证方案（待用户再跑一轮，把结论 2 问到底）**：给**原生规格与自定义值明显不同**的三个窗口各配一眼能
  认出的宽/高（**任务** 原生 704×512 · **帮助** 640×512 · **商店** 700×460 ⇒ 都配「宽 500 / 缩放 0.80」），
  再跑一遍 `/eh go 开窗探针` 并打开这三个窗口各停 2 秒。判据：「打开后」那行若出现**真不符**（不带「折算」字样）
  ⇒ **确证需要「打开即重设」**（方案 A：链式 OnShow）；若仍全一致 ⇒ **这个功能可以不做**（用户配的属性本来就安全）。
**⑥e 被动窗口「不许改宽高」+ 开窗重设 A/C 全案（1.74.33 用户拍板）**
- **用户的硬约束（原话 + 截图）**：「被动类型窗口不能设置宽度.会破坏内部布局.不能同时设置缩放和宽度.UI 会撕裂」
  —— 截图是**法术书**：左边技能列表被撑成一大块、右边那条页签被挤成一条细缝，两边各画各的。
  ⇒ 结论：**宽度对被动窗口是危险能力**（缩放实测安全：属性窗口缩放 0.7 一直好用）⇒ 宁可少一个能力，也不要一个会把界面搞坏的能力。
- **实现（唯一真值 `noSize`）**：`DF_TARGETS` 载入期给所有 `icon = true` 目标打 `noSize = true`（一个循环、一处真值）；
  ① **属性弹窗**：五行改成**带 key** 的行（`p.rowBy`；★不再按下标读值 —— 藏了行之后下标必然错位，那是「静默改错属性」的经典入口），
     被动窗口**藏起宽/高两行**（按钮与标签**都要藏**：标签是 root 的子件，不跟着按钮走）+ 显示一行说明 `TB_LD_NOSIZE_TIP`；
  ② **`dfAttrsApply(fr, rec, quiet, tgt)`**：`allowSize` 门守在两处 SetWidth/SetHeight 上（一个写调用都不发，组 220③ 用写接口计数器钉住）；
  ③ **老记录清理 `EVAL_DF_SIZE_CLEAN`**（挂在 INSTALL、**独立于 `store.mig`** —— 老用户那道迁移早就打过标记，挂它下面等于永不执行）：
     有 `rec.ow/oh` 就**还原原尺寸**，然后清掉 `w/h/ow/oh`，并如实播报「清了几个目标、还原了几项、为什么」。
  ★★**踩过的坑**：`dfCommitPop(target, ...)` 传进来的 `target` 是**帧**（`dfDragEnd`/图标点击都传 `b.dfTarget`），
     而 `noSize` 挂在**目标表项**上 ⇒ 第一版判不出来（组 220② 当场报红）。修法 = 新增 `dfTgtOfName(name)` 按名字回查目标表，弹窗与保存两侧都复用。
- **A：链式接管 `OnShow`**（前提来自第一轮真机取证 ⑥d：21/23 原生有 OnShow、本客户端无 `Frame:HookScript`）：
  · `dfOpenHookEnsure(fr, tgt)`：`GetScript` 读当前 OnShow（nil 也照样存：「原本没有」也是事实）→ `DF.onShowOrig[fr]` → `SetScript` 装 `DF.onShowBoss`；
    ★**幂等**；★**被别人换掉后重新链**，链的是**最新那个**原生脚本（组 220⑥ 用「新原脚本被调用 1 次」验）；
  · `DF.onShowBoss(self)`：**第一件事永远 `pcall(orig, self)`** → 再 `dfApplyOne(tgt)`（属性 + 位置一次做完，复用唯一入口）→ 再 `dfOpenArm`（C）；
    ★**顺序可判**：夹具让原生把 scale 设成 1.0、我们的重设再设回 0.8 ⇒ 触发后读到 0.8 就证明「原生先跑」（组 220⑤）；
  · `dfOpenHookRemove(fr)`：把 OnShow **还回原生那一个**（`orig`，可以是 nil = 摘掉脚本）；关主开关/取消勾选即卸链（组 220⑦）；
  · `dfOpenHooksSync(on)` 在 `dfIconsRefresh` 末尾跑（`dfRefresh → dfIconsRefresh` ⇒ 每次刷新都同步），条件 = 主开关 + 该层被勾选，**与图标显隐开关无关**。
- **C：开窗后有界短复查**：`DF_OPEN_PERIOD=0.3` · `DF_OPEN_CHECKS=4` · `DF_OPEN_WALL=3.0`（绝对墙钟）· `DF_OPEN_MAX_T=12`（超了**如实记 `drop`**）；
  步进体 `dfOpenCheckStep` 只在「位置不在存档点 或 缩放/透明与存档不符」时才 `dfApplyOne`（**宽高不在复查范围** —— 那能力已经拿掉了）；
  **拖拽中/战斗中跳过并如实记 `skips`**；到点 `dfOpenStop` **摘掉 OnUpdate 脚本**。
  为什么还要 C：A 只在 `OnShow` 那一刻重设一次，而客户端有可能**在它自己的 OnShow 之后一两帧**才把尺寸摆好（第一轮证据里任务窗口是 384→704）。
- **判据**：**组 220**（①noSize 唯一真值 ②弹窗藏行+说明 ③应用存档不写宽高&缩放照写 ④清理并还原 ⑤链式顺序 ⑥幂等+重链 ⑦卸链还原 ⑧C 能修回+有界自停摘脚本 ⑨战斗中跳过并记数）
  + 源码检查 **`DF OPEN HOOK CHECK`**（链式顺序/装链存原脚本/卸链还原/`allowSize` 门/`noSize` 标记/清理入口/C 墙钟与摘脚本）；变异 `tmp/mut_openafter.js` **6/6** 捕获。
- **测试教训**：① 夹具要**自己建**且建完 `EVAL_DF_TEST_TARGETS_RESET()` 清解析缓存；② 播报里的数字要**在断言那一刻取**（弹窗会为别的目标重开、清理会再调一次 SetWidth/SetHeight ⇒ 取晚了打出误导数字）；
  ③ 组号**先查有没有被占用**（本轮新组与既有组 219 撞号，改名 220）；④ 源码检查里「取函数体」必须认**列 0 的 end**（缩进的 end 是内层 if 的，用它截断会切半函数体 ⇒ 一串假 FAIL）。

**⑥f 从常驻卷迁入的「物品类型过滤」细则全文（1.74.33 迁入，为被动窗口约束腾预算）**
- ★★★**两个助手的弹窗候选按物品类型过滤**（1.74.28）：判定收在**共用件 `EVAL_IG_ITEM_KIND`**（tools/IconGrid.lua），**三级**按「便宜→贵」早停 ——
  ① **品质**（`GetContainerItemInfo` 第 5 返回，不依赖缓存）⇒ 灰色一律剔；② **`GetItemInfo`**：传参**先用物品链接**（客户端缓存键），nil 再退名字；读第 5/6/8 返回 = 主/子类型/**装备槽**（装备槽非空 ⇒ 算护甲）；③ 缓存为 nil ⇒ **自建隐形 tooltip** `EVAL_HELP_WTT` + 守卫 `EVAL_WTT_MAY_READ` + **`SetBagItem`** 读类型行 —— 这步会**把物品写进客户端缓存** = **自愈**。
  ★**剔除表** `IG_KIND_DROP`：武器/护甲/灰色/**材料**/任务/容器/箭矢弹药/钥匙/配方；★**判不出就不剔**（查不到 ≠ 没有）+ 计入 `EVAL_IG_KIND_STATS().unknown` 如实报。
  ★★**过滤只在「弹窗候选」路径开**（`EVAL_IG_SCAN_BAGS(bags,{classify=true})`）——按名字解析包格那条路（`EVAL_CH_FIND`/`EVAL_HH_FIND_FOOD`）**绝不过滤**（判错一类 = 用户已配置的物品静默找不到）。
  ★★**tooltip 只读 TextLeft2 起**（跳过 TextLeft1 = 物品名，名字可能含类型词会污染判定）；词表 `IG_KIND_WORDS` 按真机实测文案维护。
  ★验证命令：`/eh go 消耗品探针 过滤` ｜ `喂食探针 过滤`（逐件打判定依据 + 统计行，同时是补词表的依据）。判据 = 组 187（剔除逐项 / tooltip 兜底 / 缓存自愈后不再探 / 关掉 `classify` 行为不变）。
- ★★★**第二轮口径收窄（1.74.33 同一天，用户澄清）**：「图层拖拽功能.是所有窗口都不能调整宽高.会把内部原始撕裂.
  是我之前的需求说错了　属性配置需要支持调整的是窗口的 x,y 坐标值」
  —— 第一轮我把范围理解成「被动窗口（icon 目标）」，实际是**所有窗口**（拖拽柄层/动作条也不例外）。
  · **实现改法**：加 `local DF_NO_SIZE = true` 作**唯一真值**；目标表改为 `DF_TARGETS[i].noSize = DF_NO_SIZE`（每项都挂，读值口/判据直接读它）；
    `dfAttrsApply` 的 `allowSize = (not DF_NO_SIZE) and ...`（**不看 tgt 也判定得出来**）；属性弹窗**整体删除**两行 `addRow(-118/-146)`；
    保存处理器里「读原值 → 写宽高 → 读回自证」整段删除（连读都不读）；`EVAL_DF_SIZE_CLEAN` 去掉 `noSize` 过滤 ⇒ **所有**留宽高的记录都清。
  · **判据翻转**：旧组 206（1.74.31 那套「弹窗 5 行 / 选 500×200 / 还原」）**整体重写**成验「宽高改不了」
    （①弹窗不建宽/高行且说明常显 ②真实下拉+保存：缩放照写、**宽高写调用 0 次**、存档不留 w/h/ow/oh、播报不出现「宽 N」
     ③老记录清理并还原 300×60 ④只有 w/h 无原始值 ⇒ 清记录但**不猜尺寸** ⑤应用存档也不写宽高）；
    ★组 208④⑥ 原来用**宽**验「参数立刻生效 / 关掉开关不动目标」⇒ 停用宽高后这两条会变成**恒真的空断言**（弱判据），
      已把载体换成**缩放**（性质不变、载体换成还支持的那一项）——「判据照需求改」而不是删掉了事。
  · **变异**：`tmp/mut_nosize_all.js` **7/7**（摘宽高门→组206⑤ · 弹窗又建宽高行→组206① · 不先调原生→组220⑤ · C 不摘脚本→组220⑧ · 清理不还原→组206③ ·
    不标 noSize→组220① · 清理只挑被动窗口→组206③）。
  · **待用户确认（下一轮做）**：「属性配置需要支持调整的是窗口的 x,y 坐标值」—— x/y 的**语义**要定：
    (a) **绝对屏幕坐标**（X=左边缘、Y=下边缘，如 100 / -50）还是 (b) **相对位移**（相对记录基准的 dx/dy，与拖拽记录同一口径）？
    控件形式也随之定：本客户端 **EditBox 疑似不渲染**（老账）⇒ 只能用**下拉预设**（配合 `EVAL_DD_OPEN` 多列）或**微调按钮 [−][+]**；
    落地时注意：x/y 必须走 `dfPlaceFrom`（量回自证 + 手量折算）这条唯一落锚入口，绝不能再出现「把屏幕量当本地偏移用」。
- ★★★**X/Y 坐标行（用户第二次澄清真正要的那一项）实现全案**：
  · **语义 = 绝对屏幕坐标**（用户选定）：X = 窗口左边缘、Y = 窗口下边缘。实测值域 X 0~1228 / Y 0~768
    （屏幕坐标原点在左下角 —— 第一轮开窗探针的数据：各窗口 `left` 0~655、`bottom` 152~287 ✓）。
  · **控件 = 下拉预设 + [−][+] 微调按钮**（用户选定）：本客户端 EditBox 疑似不渲染（老账）⇒ 不做打字输入；
    ★预设**最多 10 项**（共用下拉列表只有 10 行、没有滚动）⇒ 预设给粗档（`DF_X_PRESETS`/`DF_Y_PRESETS`），
    精调靠按钮（`DF_XY_NUDGE=10`；按住 Shift 走 `DF_XY_NUDGE_FINE=1`，用 `IsShiftKeyDown` 且 pcall 兜住）。
  · **落锚**：X/Y → `dx = nx - base.l`、`dy = ny - base.b` → **`dfPlaceFrom(fr, base, dx, dy)`**（唯一落锚入口，量回自证）；
    ★**绝不许**算完坐标直接 `SetPoint`：那就是「把屏幕量当本地偏移用」的老坑（缩放≠1 必偏，组 222② 专门用「缩放 0.5 的窗口」
    区分：直接 SetPoint 会落在 150 而不是 300）。落完**读回自证**，没到位如实播报（不改口径、不假装成功）。
  · **老记录**：`base.l/base.b` 缺失时先 `dfScreenBaseOf` **反推**基准；反推不出来（尺寸读不到）⇒
    如实说「读不到基准位置 ⇒ 本次没设（不猜位置）」并且**一个写调用都不发**（组 222⑥）。
  · **回填只改显示、不写 `row.value`**：写了就等于「用户没动过也会被保存」，会把「客户端刚把窗口摆回去的错误位置」
    静默固化下来（变异 M60b 捕获）。微调按钮**必须写 `row.value`**（只改显示不写值 = 保存时丢改动，M61b 捕获）。
  · **判据**：组 222（①两行+两按钮+回填不写值 ②下拉 X=300 精确落点 + 老记录反推基准 ③微调 +20 精确生效
    ④Shift 步长 ±1 ⑤Y=400 精确且不动 X ⑥读不到基准不改目标且如实说明）+ `DF OPEN HOOK CHECK` 的 X/Y 三条哨兵；
    变异 `tmp/mut_xy.js`/`mut_xy2.js` **4/4**（绕过 dfPlaceFrom→组222② · Shift 档写反→组222④ · 回填写值→组222① · 微调不写值→组222①）。
**⑦ 从常驻卷迁入的「品阶显示」原文（1.74.33 迁入，为图层选择腾预算）**
- ★★品阶显示现算（不硬编品阶）：文字＝品阶色、底色×（激活 0.45/否则 0.22）；组 160/167。图标＝IconSem 真纹理 13px；★`EVAL_SHARE_SEAL_ICON` 两返回值**禁内联进可变参数调用**（先收局部再 pcall——内联会丢第二个返回值）；`PROF ICON PROBE WIRING CHECK`；组 160⑥⑦。★重锚前 `ClearAllPoints`；文字框留富余（`TPL_TEXT_PAD=4`·组 91）。

**⑧ 从常驻卷迁入的两条零碎判据（1.74.33 迁入，为窗口图标口径腾预算）**
- ★**COND WEIGHT CHECK 的实战价值**：它上线当场抓到 `target`（「选取目标」，hidden 存量类型）**不在任何分组**里 ⇒ 新口径下会被按 0 分算、也不计覆盖（静默少算）。★「新增条件类型必须进组」由它兜底。
- ★★**`/eh go` 别名不许两家共用**（1.74.32）：`go icons` 早被组 116 占用 ⇒ elseif 链先命中的赢、那条命令被**静默顶掉**；`GO ALIAS UNIQUE CHECK` 守。

**⑥g 图层特殊处理（Layer Fixes）全案（1.74.34 用户三连问）**
- **用户原话**：①「能否对固定的某个层内的最后2个纹理做特殊处理.比如隐藏这2个纹理」（配 EH_DebugBox 图层树截图：
  `MainMenuBarArtFrame` 的 #21/#22 两条 `纹理:Texture` 被红框圈出 = 动作条两端那两张狮鹫贴图）；
  ②「以上如果可行.可以在工具箱->UI 工具->添加个图层特处理->设置/重置 ,设置功能支持下拉,目前里面添加个动作条狮鹫 ,支持多选.切换显示选中的特殊处理.」；
  ③「以上特殊处理定义规范配置.以后可能还有其他特殊处理, 弹窗下拉UI参考图层拖拽->设置」。
- **可行性结论 = 可行**，且有本地证据：① 层真名来自用户截图（容器 `MainMenuBar` 的子帧 `MainMenuBarArtFrame` 717×37，
  它 `GetRegions()` 前 6 条是 `纹理:Texture`、第 7 条是 `字体串`）；② `Texture:Hide()` 是普通 Region 方法（非 Protected）；
  ③ 枚举区域本客户端实测可用（EH_DebugBox 整棵图层树就靠 `GetRegions`/`GetChildren` 走）。
- **定义规范（唯一来源 = `tools/DragFrames.lua` 的 `DF_FIXES`，加一条处理只加一项）**：
  `key`（= 存档键，★绝不用序号/显示名）· `group`（下拉分组号）· `kind`（现在只有 `hideTex`）·
  `layer = { cands = {...} }`（帧名候选，与 `DF_TARGETS` 同口径：命中名会如实播报）·
  `pick = { last = N }`（按 `GetRegions()` 顺序取**最后 N 个纹理**）或 `{ path = "子串" }`（按贴图路径小写包含匹配，**更稳**，
  留给拿到真机路径后启用）· `label`/`tip` **必须是取词函数** `function() return L("键") end`
  （★键字面量要出现在源码里，否则 `LANG KEY CHECK` 看不见；★现取才不会绑死加载期语言）。
- **真值** = `EVAL_HELP_CONFIG.dragFrames.fix[key] = true`；★**表不存在 = 一条都不选**（与 `pick` 的「不存在 = 全选」**相反**）：
  特殊处理会改客户端界面，绝不能因为升级/加条目就自动生效（变异 M6 专门验这条：写反 → 组223① 当场报红）。
- **执行三处（全都有界）**：① 勾上/取消**当场**生效或还原（工具箱多选下拉每点一下就调 `EVAL_DF_FIX_SYNC`）；
  ② 载入期 `EVAL_DF_INSTALL` 调一次（重进游戏照样生效）；③ 启动期**有界**复查窗口（`dfKeepTick`，1s×5 次）里补一次
  —— 覆盖「层还没建出来」与「客户端自己又把它显示回来」，窗口结束即停（**不另开常驻计时器**）。
- **三条诚实性硬规矩**：① 层不在 / 层里纹理数少于要处理的个数 ⇒ **一个对象都不动** + 如实播报「没做成 + 这次没动界面」
  （绝不猜一个「看起来像」的层动手）；② 原始状态是**三态**（true=显示 / false=隐藏 / **nil=读不到** ⇒ 还原时按「显示」还原）——
  读不到就当 false 的后果正是用户会看到的「重置了但贴图没回来」；③ 本来就隐藏的元素**绝不**用 `Show` 弄出来（组223⑤）。
- **幂等**：`DF.fixState[key]` 存在即短路（**不重新挑对象**）—— 重新挑会因为在往「更前面」数而藏错对象（组223③b 幂等哨兵）。
- **接线（易漏且不报错的部分）**：★★★ `local dfFixSync, dfFixTick` **前向声明**必须写在 `dfKeepTick` / `EVAL_DF_INSTALL`
  两处调用**之前**（本项目头号坑：写在后面 = 那两个名字绑成全局 nil，而调用点套着 `if ... then` 守卫 ⇒ 静默永不执行）；
  工具箱那一行 `t = "dfFix"` + **`noChk = true`**（真值就是多选里勾了哪几条，多挂一个总开关只会多一份真值）
  ⇒ 渲染段必须 `if not it.noChk then r.chk:Show() end`（否则长出点了没反应的死勾选框）。
- **判据**：**组 223**（①规范 ②菜单唯一来源+默认全不选 ③只藏最后 N 个且前面的一个不动+播报层名与贴图路径 ③b 幂等
  ④取消当场还原/再勾再生效 ⑤诚实还原（隐藏的不弄出来）⑤b 读不到原状按显示还原 ⑥层不在一个不动+如实播报
  ⑦[重置] 还原+清勾选 ⑧存档持久化+重开后守护 ⑨有界复查补晚出现的层+被显示回来再藏 ⑩工具箱端到端）
  + 源码检查 **`DF FIX WIRING CHECK`**（DF_FIXES 必填字段/默认不选/陌生键拒写/菜单现生成/**前向声明哨兵**/
  两处调用都在/工具箱几何与多选/noChk）；变异 **`tmp/mut_dfix.js` 7/7**（全部由**断言**捕获，不是靠源码检查兜）：
  取前 N 个→组223③ · 还原不 Show→组223④ · 写入口不落存档→组223③ · 摘掉有界复查调用→组223⑨ · noChk 失效→组223⑩ ·
  默认语义写反→组223① · 还原后不清记账→组223④。
- **读值口**：`EVAL_DF_TEST_FIXES_RAW()` · `EVAL_DF_TEST_FIX_STATE()`（含每个对象的 `shown`/`orig`/`paths`）·
  `EVAL_DF_TEST_FIX_STATE_CLEAR()` · `EVAL_DF_TEST_STATE().fixApplied/fixRehide` · 工具箱 `EVAL_TB_TEST_ROW_TEXT(key)`。
- **★待真机确认（还没做）**：`pick = { last = 2 }` 是按**用户自己的定义**（层内最后 2 个纹理）实现的；本次播报会打出
  层名 + 两条**真贴图路径** ⇒ 用户跑一次即可核对「藏的是不是那两个」。若顺序/命中不符（或客户端改版换了顺序），
  把该条改成 `pick = { path = "路径关键字" }` 即可（**代码已支持，只改规范表一项**，不需要动引擎）。
- **测试踩坑**：① 桩里 `Texture` 的 `IsShown` 默认 nil（真机 CreateTexture 出来就是显示的）⇒ 夹具要**显式建立**显隐状态；
  ② 夹具的区域顺序必须把**字体串放在纹理后面**（与真机截图一致），否则「不数错类型」这条判据是空的；
  ③ `EVAL_DF_TEST_STATE()` 原本没有 `fixRehide` ⇒ 新读值口要同步补（第一次运行就报了 `attempt to compare number with nil`）；
  ④ `test_assert.lua` 里 `print("ALL TESTS PASS")` 有 **8 处**（14891~14895 是历史遗留的连续 5 行）⇒ 追加新组必须用
  `lastIndexOf` 锚末尾那处，用 `indexOf` 会命中注释（第一版报了「锚点命中 8 次」）。

**⑥g-2 抽成独立模块（1.74.34 第二轮，用户：「能否将以上功能提取到./tools 独立文件脚本管理.尽量少的在ToolBox文件内修改.只要加入嵌入点进行函数调用?」）**
- **落地形态**：新文件 `tools/LayerFix.lua`（约 35 KB，自包含）；`tools/DragFrames.lua` 里那一整段（14.6 KB）
  被**整段删除**（含前向声明 `local dfFixSync, dfFixTick`、`DF` 表里的 `fixState/fixApplied/fixRehide`、
  `dfKeepTick` 与 `EVAL_DF_INSTALL` 里的两处调用、`EVAL_DF_TEST_STATE` 的两个字段、全部 `EVAL_DF_FIX_*` 读值口）。
- **只留两处嵌入点**（这就是用户要的「函数调用」）：
  ① `EvalHelp.lua` 的 VARIABLES_LOADED：`if type(EVAL_LF_INSTALL) == "function" then pcall(EVAL_LF_INSTALL) end`
     （与 `EVAL_RW_INSTALL` / `EVAL_DF_INSTALL` 同一排）；
  ② `Toolbox.lua` 的**模块行**：模型里**一行数据** `{ t = "mod", mod = "layerFix", key = "layerFix", label = L("TB_DFFIX"), tip = L("TB_DFFIX_TIP"), noChk = true }`
     + 渲染段**一个通用分支**：
     ```lua
     elseif it.t == "mod" then
       local reg = rawget(_G, "EVAL_TB_MOD_ROWS")
       local fn = (type(reg) == "table") and reg[it.mod] or nil
       if type(fn) == "function" then pcall(fn, r, it)
       elseif type(EVAL_SAY) == "function" then pcall(EVAL_SAY, "工具箱：这一行要的模块没载入（mod=…）…") end
     end
     ```
     ⇒ 控件、tooltip、下拉、结算**全在模块里**（`lfRow`），Toolbox **一行都不知道**模块内部长什么样。
- **注册表为什么不走「函数登记」而是走全局表**：`EVAL_TB_MOD_ROWS` 由**模块自己**在载入期「没有就现建」，
  Toolbox 只在渲染时 `rawget` 取一次 ⇒ **toc 里谁先谁后都成立**。只认「对方已经建好表」的写法会出现
  「模块先载入 ⇒ 登记无处可去 ⇒ 面板上那一行点不动」的**静默失效**（这类顺序依赖是本项目老坑）。
- **存档搬家 + 一次性迁移**：真值从 `dragFrames.fix` 搬到**本模块自己的子树** `EVAL_HELP_CONFIG.layerFix.fix`；
  `lfMigrate` 把老的 `dragFrames.fix[key]` 逐条搬过去并**把老键清掉**（绝不留两份真值）；存档没就位时**不写、不标记**，
  交给 INSTALL 的 `0.5s × 20` 有界重试。真机用户已勾选的那一条**不会丢**（组 223⑧ 专门验这段迁移）。
- **复查窗口自给自足**：不再蹭框拖拽的 `dfKeepTick`，模块自己开 `EVAL_LF_KEEP`（`1s × 5` 次、墙钟 15s，
  到点 `lfStop` **摘掉 OnUpdate 脚本**）；只在真的做事时播报（补生效 / 再藏回去），不刷屏。
- **与 DragFrames 零耦合**：源码检查**反向守** `tools/LayerFix.lua` 里出现 `DF_TARGETS` / `dfPicked` / `dfStore` /
  `dfTargetFrame` / `dfPlaceFrom` / `dfKeepTick` / `dfApplyOne` 任一即 FAIL；同时反向守 `tools/DragFrames.lua` 里
  出现 `DF_FIXES` / `dfFix` / `EVAL_DF_FIX` / 「图层特殊处理」任一即 FAIL（**搬走必须一份不剩**：两份真值会互相打架）。
- **判据全量改名**：`DF FIX WIRING CHECK` → **`LAYER FIX WIRING CHECK`**（改查 `tools/LayerFix.lua`），
  新增四条哨兵：① 工具箱**不许**认识模块内部件（`LF_FIXES`/`EVAL_LF_`/`EVAL_DF_FIX`/`gryphon`/`MainMenuBar` 出现即 FAIL）；
  ② 两组 `mod` **名字必须一致**（工具箱 `mod = "layerFix"` vs 模块 `LF_TB_ROWS["layerFix"] =`；对不上 = 那一行点不动且不报错）；
  ③ toc 必须列 `tools\LayerFix.lua`；④ `EvalHelp.lua` 里那行必须**可执行**（见下面的 M9 教训）。
  组 223 也全面改成新接口（`EVAL_LF_*` / `EVAL_LF_TEST_*` / 真值子树 `layerFix` / 自己的 tick 帧），并补了两条：
  「模块行的渲染函数**已登记**进 `EVAL_TB_MOD_ROWS`」与「旧位置迁移不丢勾选」。
- **所有 9 处文件清单都要补新文件**：`test_engine.js` 里 8 处 `"tools/DragFrames.lua"` 清单 + 1 处单引号的 fengari 载入清单
  （DECL ORDER / LANG KEY / COMMENT SWALLOW / SAVEDVARS SPLIT / EXAMPLES TOC / WHEEL / COLOR CODE LEN / FRAME NAME CLASH / 载入），
  以及 `EvalHelp.toc`；另外 **`PACK LIST CHECK` 的条目数基准 71 → 72**（参考卷里那句「基准 = **N 个**」）。
- **★本轮踩到的两个新坑（都已落进判据）**：
  ① **「名字还在」不等于「那行能执行」**：变异 M9 把载入期那句改成 `if false then pcall(EVAL_LF_INSTALL) end` ——
     名字与调用都还在 ⇒ 只查 `indexOf("EVAL_LF_INSTALL")` 的源码检查**当场漏过**（10 个变异里唯一一个漏的）。
     修法 = 判据钉**可执行的那一整句**（`if type(EVAL_LF_INSTALL) == "function" then pcall(EVAL_LF_INSTALL) end`）。
  ② **`String.replace` 会把内容里的 `$&`/`$'` 当展开语法吃掉**：早前那版「块文件 + `src.replace(锚点, 块 + 锚点)`」的插入脚本，
     把块里 regex 转义那句 `"\\$&"` 展开成了**锚点原文**（于是 `DF ICON ART CHECK` 的注释文字被注进了代码里，
     文件里出现两处同名注释）。本次改用 `slice` 拼接 + 「残留检查」，并把 `$&` 记进纪律：
     **凡是用 node 脚本改源码，一律 `slice`/`indexOf` 拼接，绝不用 `String.replace` 塞含 `$` 的内容**。
- **变异**：`tmp/mut_lfix.js` **10/10**（9 条由断言捕获、1 条由源码检查捕获——正是两类检查互补的样子）：
  取前 N 个 · 还原不 Show · 写入口不落存档 · 有界复查不补 · noChk 失效 · 默认语义写反 · 还原后不清记账 ·
  嵌入点不调模块 · 载入期不安装（源码检查） · 有界窗口不摘脚本。

**⑥g-3 「图层拖拽」那一行的界面接线也搬进模块（1.74.34 第三轮，用户：「审查下 图层拖拽的功能.在Toolbox.lua 内的代码修改.参考以上也进行./tools 的代码文件归类」）**
- **审查结论（先审后动）**：Toolbox 里属于这个功能的代码只有 **3 处**：① 模型行（`t = "lddrag"` + `ldReset/ldSet` 两个开关字段）；
  ② `elseif it.t == "lddrag" then … end` 分支（约 **128 行**：`[重置]` 的 tooltip/清单/OnClick、`[设置]` 的多选下拉代理、
  主开关的 `r.get/r.set`）；③ 常量 `TB_LD_TIP_W = 460`（只被那段用）。**其余判定/真值/公式本来就都在模块里**
  （`dfPicked`/`EVAL_DF_PICK_*`/`EVAL_DF_RESET`/`EVAL_DF_SET`），所以这次是**纯界面接线搬迁**，行为零变化。
  ★顺带确认：勾选框的 OnClick（`tbBuild` 里那段）是**点击时**才读 `row.get/row.set`，且**没有** `dbgDrag` 专用副作用分支
  ⇒ 模块在自己渲染函数里设 `r.get/r.set` 完全等价（组 202②「两向同源」仍在守它）。
- **搬法**：`dfRow(r, it)`（[重置]=`r.clr` / [设置]=`r.add` / 主开关 `r.get/r.set`）+ `DF_TB_ROWS["dragFrames"] = dfRow`；
  Toolbox 侧模型行改成 `{ t = "mod", mod = "dragFrames", key = "dbgDrag", label = …, tip = … }`
  （★**不写 `noChk`** ⇒ 主开关勾选框照旧；`key` 必须留 —— 读值口按 key 找行，丢了 `key` 断言会**静默跳过**）；
  整段分支与 `TB_LD_TIP_W` 删除，`Toolbox.lua` 里**再不许出现** `EVAL_DF_*`（反向哨兵）。
  净效果：Toolbox 少 128 行、多 1 行数据 + 已有的通用分支（−6.3 KB）。
- **判据跟着搬**（三处源码检查）：
  · `DF PICK WIRING CHECK` ⑤ 段：从「工具箱 [设置] 分支」改成「模块 `dfRow`」（菜单/写入口/结算/计数/重置清单/主开关 8 个接口 +
    多选三件套 + 几何哨兵 `r.clr`/禁 `r.chv`），并保留「工具箱里不许有目标帧名字面量」；
  · `DRAG FRAMES WIRING CHECK`：工具箱侧断言 → 模块侧（`dfRow` 存在 + 登记 + 四个接口）+ 反向哨兵（Toolbox 无 `EVAL_DF_*`）+ 模型行存在；
  · **新增通用检查 `TB MOD ROW CHECK`**：① 通用嵌入分支（注册表取值 + 真调用 + 未登记时如实上报）；
    ② 模型里每个 `t = "mod"` 行必须有 `key`，且 `mod` 名字必须在 `tools/*.lua` 里有**同名登记**（对不上 = 那一行点不动且不报错）；
    ③ Toolbox 不许出现模块内部件（`EVAL_DF_`/`LF_FIXES`/`EVAL_LF_`）。
    ★这条通用检查是这次审查的**产品**：以后再加模块行，名字/键/嵌入点三件事一次判到底，不必给每个模块再写一份。
- **变异**：`tmp/mut_dfrow.js` **6/6**（**全部由既有的行为断言捕获** —— 搬动没有削弱覆盖）：
  不登记（组 200）· [设置] 不结算（组 214⑧）· 换 `chv` 槽（组 200 tooltip/几何）· 工具箱 `mod` 名字写错（组 200）·
  主开关无读写代理（组 202②）· [重置] 不接还原（组 204⑤c）。
- **测试影响**：**零改动** —— 组 200/202/204/214 全部按 `key = "dbgDrag"` 走读值口（`EVAL_TEST_TB_ADD_BTN_FOR` / `CLR_FOR` / `CHK_FOR` / `ROW_BTNS`），
  搬动后按钮仍由模块建在同一套槽位上，断言原样通过（这正是「读值口按稳定键找行」这条纪律的红利）。

**⑥h 工具类归属规范 + Toolbox 剩余功能审查（1.74.34 第四轮，用户：「以上工具类的整理要加入项目记忆。尽量单独文件进行管理，在 Toolbox.lua 内只做开启/配置入口的引入」）**
- **规范（已入常驻卷 §4.1）**：工具功能一律 `./tools/<模块>.lua` **自包含**（真值 + **自己的存档子树** + 界面控件 + 读值口 + **自己的有界计时器**）；
  `Toolbox.lua` 里**只允许**「模型行数据 `t = "mod", mod = "<名>", key = "<键>"`」与「入口按钮（点了就调模块函数）」；
  **不许**出现整窗 UI / 事件帧 / OnUpdate / 解析与状态机 / 协议队列。
  机制 = 模块行注册表 `EVAL_TB_MOD_ROWS[mod]`（模块**载入期自建自登记**，两边谁先载入都成立）；渲染段只有一个通用分支；
  判据 = 通用 **`TB MOD ROW CHECK`**（模块行必须有 `key` + `mod` 名字在 `tools/*.lua` 里有**同名登记** + Toolbox 不许出现模块内部件）
  + 每个模块自己的 `* WIRING CHECK` 里那条**反向哨兵**（「Toolbox 里出现 `<模块内部件>` 即 FAIL」）。
- **审查口径（怎么量）**：`tmp/audit_toolbox.js` —— 按顶层函数块（顶格 `end` 收尾）统计体积，再用「归属判定表」把每个函数归到
  「工具箱自身框架」或「某工具功能」。**判据不是「写在哪个文件」，而是「这函数是谁的知识」**：
  行模型/两列/连续窗口滚动/存档路由/读值口 = 工具箱的**本职**（留在原地）；某个工具的窗/状态机/事件/协议 = 该工具的**知识**（应进 `./tools`）。
- **1.74.34 审查结果（Toolbox.lua 共 5927 行 / 250 个顶层函数）**：

  | 归属 | 体量 | 内容 |
  |---|---|---|
  | 工具箱自身框架（**留**） | ~3000 行 | `EVAL_TB_BUILD`(251) · `EVAL_TB_REFRESH`(234) · `tbModel` · 两列/切点/滚动/`EVAL_TEST_TB_*` 读值口 · `tbCfg`/`tbMakeRouter`/`tbCharStore` · `tbBtn`/`tbText`/`tbSolid` 等自绘助手 |
  | **应进 ./tools（待搬）** | ~1300 行 + 若干混在框架里的助手 | ① 商家助手·**自动购买设置窗** `buyUIBuild`(199)+`buyUIRefresh`(84)+`EVAL_BUY_UI_*` ≈ **334 行**（整窗 UI + 步进器 + 列表 + 滚动 + 自己的读值口）② **聊天名字按职业着色** `EVAL_TB_NAMECLASS_*`/`EVAL_TB_CHATCOLOR_*`/`EVAL_TB_WHO_*`/`tbNcHarvest` ≈ **384 行**（缓存 + who 查询 + 事件帧 + 收尾）③ **右键名字菜单** `tbMenuBuild`(76)+`tbMenuItems`(76)+`tbMenuChrome`(41)+`EVAL_TB_NAMEMENU_*` ≈ **270 行** ④ **子插件注册表与行** `EVAL_TEST_SUBADDONS`(73)+`EVAL_SUBADDONS_*`+`EVAL_PLUGIN_*` ≈ **172 行** ⑤ **频道/拦截关键字** `EVAL_TB_CHANKEYS_*`/`EVAL_TB_QCHAN_*` ≈ **115 行** ⑥ **频道进出屏蔽** `EVAL_TB_CHAN_OFFICIAL_*` ≈ **52 行** ⑦ **旧配置迁移** `tbMigrateBuy`/`tbMigrateQuest` ≈ **17 行** |
  | 混在框架里的同名助手 | — | `EVAL_TB_CHATEVENT_INSTALL`(159) · `EVAL_TB_CHAT_COLOR_LINE`(118) · `EVAL_TB_NAME_PARTY`(67) · `EVAL_TB_TICK`(91)/`EVAL_TB_ONEVENT`(85)（工具箱的事件帧被多个工具共用 ⇒ 搬迁时要么把帧也交给某个模块、要么保留一个**只做派发**的薄壳） |

- **搬迁次序建议（按「干净程度」排，不是按体量）**：
  ① **频道进出屏蔽**（52 行，纯 API 开关 + 一个已存在的 `EVAL_TB_CHAN_OFFSET` 同步点）→ `tools/ChatChan.lua`；
  ② **频道/拦截关键字**（115 行，自己的下拉+输入框）→ 并入同一个 `ChatChan.lua`；
  ③ **右键名字菜单**（270 行，自成一窗、只读缓存）→ `tools/NameMenu.lua`；
  ④ **子插件注册表**（172 行，与配置窗「子插件」Tab 同源）→ `tools/AddonReg.lua`；
  ⑤ **聊天名字着色**（384 行 + 与 who 查询/事件帧耦合最深）→ `tools/NameClass.lua`（**要先把事件帧归属定下来**）；
  ⑥ **自动购买设置窗**（334 行整窗，但依赖工具箱的 `tbCfg()` 与 `tbBtn/tbText` 助手）→ `tools/BuyUI.lua`（**先把自绘助手抽成共用件或让模块自带**）。
  ★**每搬一个都要**：加 `.toc` + 8 处源码检查名单 + 模块行/入口 + 删旧代码 + **反向哨兵** + 跑该功能的既有断言组 + 一条新变异。
- **本轮的边界**：这一轮**只做规范 + 审查**（用户说的是「整理要加入项目记忆」），**没**动上面那 1300 行 —— 搬迁按上表次序**逐个做**，一次一个、每次跑满两道闸门与变异。

**⑥i 从常驻卷迁入的「可驱散负面类型多选」原文（1.74.34 迁入，为工具类规范腾预算）**
- 可驱散「负面类型」多选（1.73.2；**1.74.6 扩到自身/目标 debuff**）：`cd.dt` = nil / 单串 / 集合（**空集 = 任意**）；
  **求值一律走 `dispelMatch` 按类型过滤**（名字对上但类型不符 = **没有**）；
  **名称留空 + 类型 = 「有任意该类型」**（层数取命中项**最大值**）；类型存**平行表** `st.{player,target}DebuffType`（层数表仍是数字）；
  格式化同一份 `dtSuffix()`（导出 token / 显示本地化名）；编辑窗类型格**四族都有**、**buff 行不许有**；组 114 ＋ 组 181。

**⑥j 工具模块自带的测试三件套归模块自己管（1.74.34 落地全案）**
- **用户原话**：「test 相关的搬迁到对应工具类子文件内自身管理。」（承接同一轮的「工具类功能独立文件」规范）
- **落地形态（三件套各归其位）**：
  ① **读值口**留在模块本体 `tools/<模块>.lua`（如 `EVAL_LF_TEST_*`，模块自查用）；
  ② **断言组**搬到 `tests/tools/<模块>.lua`（LayerFix 的组 223 逐字迁入，22.7 KB），文件头写死四条纪律：不进 toc/不随包 · **一律用共用的 `EVAL_TEST_EQ`** · **末行必须 `EVAL_TEST_MOD_DONE("<模块>")`** · 夹具自建自清；
  ③ **源码检查**搬到 `tests/checks/<模块>.js`（原来嵌在 `test_engine.js` 里的 `LAYER FIX WIRING CHECK` 整段抬进 `module.exports = function (root) {…}`），harness 里只留一行 `require("./tests/checks/LayerFix.js")(__dirname);`。
- **共用件**：`test_assert.lua` 头部暴露 `EVAL_TEST_EQ = eq` 与 `EVAL_TEST_MOD_N / EVAL_TEST_MOD_NAMES / EVAL_TEST_MOD_DONE(name)`；**兄弟文件写 `local eq = EVAL_TEST_EQ` 即可** ⇒ 失败格式与其它组逐字一致（自带一套判定 = 两套口径，早晚打架）。
- **harness 接线（`test_engine.js`）**：在 `test_assert.lua` **之后**自动加载 `tests/tools/*.lua`（排序后遍历），跑完打一行 `MODULE TESTS: <跑到底数>/<磁盘文件数>（名字）`，并**当场对账**：不相等 → `TOOL TEST FILES CHECK: FAIL` + `process.exit(1)`。
  ★**为什么必须对账**：这类失效**全是静默的** —— 文件存在但没被加载，整组断言消失，套件**照样打印 ALL TESTS PASS**（本项目最恨的形态）。
- **新源码检查 `TOOL TEST FILES CHECK`**：
  ① 每个 `tests/tools/*.lua` 必须用 `local eq = EVAL_TEST_EQ` + 有 `EVAL_TEST_MOD_DONE("…")` + 有 `GROUP …: PASS` 收尾行；
  ② 每个 `tests/checks/*.js` 必须 `module.exports = function`，且 `test_engine.js` 里**必须真的有一行 require+调用**（漏了 = 那条检查静默缺席）；
  ③ **反向哨兵**：`tests/` 不许出现在 `EvalHelp.toc`（会被当插件模块载入）与发布打包行里（测试代码不随包发给用户）。
- **变异验证**（`tmp/mut_tests.js`，6/6 全捕获）：M1 加载器 `modTests.slice(0,0)` 静默跳过（**只有握手对账能抓**）· M2 末行握手注释掉 · M3 自造 `local eq` · M4 `tests/checks/` 多出一个没人 require 的文件 · M5 harness 里那行 require 被注释 · M6 `tests\tools\LayerFix.lua` 被列进 `.toc`。
- **★第二个真实的插曲（更要记：源码检查自己也会假阳性）**：变异 M5「把 harness 里那行 `require(...)(__dirname)` 注释掉」
  **第一轮没被抓**（退出码 0）—— 原因是我那条检查写的是 `te.indexOf('require("./tests/checks/X.js")(__dirname)') < 0`：
  **注释掉的行文本里照样含这串子串**，`indexOf` 直接命中 ⇒ 检查以为「接线还在」。
  【修法】改成**按行精确匹配**：`te.split(/\r?\n/).map(l => l.trim())`，要求存在一行**以该调用串开头且不是注释**（`l.indexOf(need) === 0 && l.indexOf('//') !== 0`）。
  【通用教训】凡是「检查某段代码在不在」的源码检查，**一律锚到「可执行的那一行」**，不要用裸 `indexOf` 找子串 ——
  注释、字符串字面量、别处的同名调用都会让它**假阳性**（这与第五节的「锚点唯一定位」是同一条纪律，只是这次骗过检查的是**注释**）。
- **一个真实的插曲（值得记）**：变异脚本第一版被 120s 超时杀掉，**M3 的变异残留在工作树里没还原**；下一轮脚本的**基线检查当场把它抓出来**（`TOOL TEST FILES CHECK: FAIL - 没有用共用的 EVAL_TEST_EQ`）⇒ 说明这道源码检查真的在守。教训：变异脚本要给足时间（跑一次 test_engine 约 10s，13 次跑不完），并且**每轮先验基线**。

**⑥k 从常驻卷迁入的「索引任意全局 / 父子链扫描」原文（1.74.34 迁入，为测试规范腾预算）**
- ★★★**索引「任意全局」/ 走父子链的扫描，动手前先看参考卷附录 R15**（1.74.32 真机栽过一整轮）：① 索引前先过守卫（**不可索引的 userdata** 会抛错、**打断整个探针**；只收 `GetObjectType()=="Frame"`）；② **匿名窗口 `_G` 扫描永远看不到** ⇒ 只能靠 `GetChildren()` 父子链 + **具名子件当指纹**；③ 真机存档**带 BOM**、`a and f()` **只保留第一个返回值**、桩里 `unpack` 在 fengari **不存在** —— 都表现为「静默取不到值」。判据 = `DF GLOBAL SCAN GUARD CHECK` + 组 209/211/213。

**⑥l 从常驻卷迁入的「滚动/翻页/分页标准做法」原文（1.74.34 迁入，同上）**
- ★★★滚动/翻页/分页标准做法：三段 `[计数]`←8px→`[按钮组]`←10px→`[关闭]`；文字按钮（`IB_PREV/IB_NEXT`、`TB_UP/TB_DN`）、不用 ▲▼；几何唯一源 `EVAL_HELP_CFG_BOTTOM()`（`midY/closeLeft/closeW/rowY/rowH`；拿不到按 `-(H-10-11)`/`W-12-64` 回退）；判据＝中线==关闭中线、按钮组右端 ≤ 关闭左−4、真实 OnClick 能滚；读值口 `EVAL_IB_TEST_BOTTOM()`（组 92）/`EVAL_TB_TEST_SCROLL()`（组 118）。

**⑥m 拖拽模块（DragFrames）代码归属排查 + 测试整块归类（1.74.34 全案）**
- **用户原话**：「拖拽图层模块（DragFrames）代码也排查下归类到自身文件内。」
- **排查结论（代码侧：已经干净，不需要再搬）**：
  · `Toolbox.lua` 里与 DF 相关的**只剩 5 行**：4 行注释 + 1 行**模块行数据**
    `{ t = "mod", mod = "dragFrames", key = "dbgDrag", label = …, tip = … }`（上次已把 128 行界面接线搬进 `dfRow`）；
    `dragFrames.on` 主开关勾选框由**通用分支**渲染（该行不写 `noChk`）⇒ 工具箱里没有 `EVAL_DF_*` 这类模块内部件。
  · `EvalHelp.lua` 里 18 处 DF 引用**全是命令入口**（`/eh go 框体探针` · `开窗探针 [停|看]` · `框体图标`）：
    带 `type(EVAL_DF_*)=="function"` 守卫 + 模块没载入时**如实播报**，正是「入口只调模块函数」的合规形态，**不该搬**。
  · 结论：`tools/DragFrames.lua`（177 KB）已是自包含模块；工具箱/主插件各留**入口**，无实现残留。
- **测试侧：整块归类（这一轮真正做的事）**：
  · **断言组 18 个**（202/204/206~218/220~222，共 **161,424 字符 ≈ 158 KB**）从 `test_assert.lua` 逐字搬进 `tests/tools/DragFrames.lua`；
    搬迁用的切片口径 = 「`-- ===== 组 N` 标记 → 该组 `print("GROUP N …")` 之后那个独立成行的 `end`」
    （★不能用「到下一个标记为止」：**最后一组会一路吃到文件尾的 `print("ALL TESTS PASS")`**）。
  · **9 道 DF/DRAG 源码检查**（48 KB）搬进 `tests/checks/DragFrames.js`：ANCHOR ID · BARS WIRING · ROSTER WIRING · OPEN HOOK ·
    PROBE SAFE · GLOBAL SCAN GUARD · DRAG FRAMES WIRING · PICK WIRING · ICON ART；harness 里只留一行 `require(...)(__dirname)`。
    ★**TB MOD ROW CHECK 留在 test_engine.js**：它是「工具箱模块行」的**框架契约**（服务所有工具模块），不属于某一个模块。
  · 依赖核对（搬之前先静态查）：这 18 组对 `test_assert.lua` 的**顶层 local 依赖只有 `eq`** ⇒ 一行 `local eq = EVAL_TEST_EQ` 就够。
  · 搬迁代价（如实记）：**组 204 的前置夹具帧是组 202 造的**（全局 `pf`）⇒ 两组必须**保持原顺序**，这不是「搬完就自由排序」。
- **踩坑**：搬成独立文件后 `fs`/`path` 不在作用域里（原来是 `test_engine.js` 的模块级常量）⇒ `ReferenceError: path is not defined`。
  修法：在 `module.exports = function (root)` 里自己 `require("fs")`/`require("path")`（LayerFix.js 早就是这么写的，照抄即可）。
- **新判据 `DF GROUP ROSTER CHECK`（这一步的真正价值）**：把「拖拽模块的组号清单」钉在源码检查里——
  ① 组号集合必须与期望**完全一致**（多/少都 FAIL）；② 必须**升序**（顺序本身是契约，见上条依赖）；
  ③ 每组区间里必须**真的有 `eq(`**（「整组被删」「被掏空成只剩注释」都会当场变红）；④ 每组必须有 `print("GROUP <n> …: PASS")` 收尾行。
  ★为什么必须这样：行为断言与「跑到底握手」都只保证**文件被加载**，管不了「文件里的某一组没了」——那正是本项目最恨的静默失效；
  顺带把组 202 补上了原本缺失的 `GROUP 202 …: PASS` 行（它是唯一没有收尾行的组）。
- **变异验证（`tmp/mut_tests.js` 扩到 10 条，10/10 全捕获）**：新增 4 条针对拖拽模块——
  M7 整组删掉组 217（→ DF GROUP ROSTER CHECK）· M8 删掉组 217 的 PASS 收尾行（→ 同上）·
  M9 注释掉 harness 里 DragFrames 检查的 require（→ TOOL TEST FILES CHECK ②）· M10 注释掉 `EVAL_TEST_MOD_DONE("DragFrames")`（→ 跑到底对账 MODULE TESTS 1/2）。
- **闸门**：`luacheck.js` SYNTAX OK: **39** files（多出的正是新测试文件）· `test_engine.js` ALL TESTS PASS + `MODULE TESTS: 2/2（DragFrames, LayerFix）` + 3 道通用检查全绿，退出码 0。

**⑥n 「缩放大地图」行的 [设置] 下拉 = GUI重开（1.74.35-3 全案）**
- **用户原话**：「工具箱->缩放大地图右侧添加个设置 设置点击下拉->GUI重开 然后提示这个功能会有导致地图
  切换到其他地图后自动刷新到当前地图,,默认关闭.」
- **落地（按新规范：这一行的界面全在模块自己文件里）**：
  · `Toolbox.lua` 那一行由 `t = "c"` 改成 **模块行** `{ t = "mod", mod = "simpleMap", key = "simpleMap", … }`；
    ★顺手删掉两处旧特例：认不出来的死分支 `elseif it.t == "smap"`（模型里从没有这种行，且它走已废弃的子插件注册表）、
    以及勾选后的 `row.modelKey == "simpleMap"` 特例（模块行的 `r.set` 自己就做完「写配置 + 立刻应用/复位」）。
  · `tools/SimpleMap.lua` 交出 `smRow(r, it)`：**主开关勾选框**（真值 = `tbCfg().simpleMap`，读写 = `EVAL_SM_ENABLED/SET`）
    + **`[设置]` 多选下拉**（`EVAL_DD_OPEN(..., {multi=true, selected=sel, locked=locked, tips=tips})`，与 LayerFix/dfRow 同一套）；
    行内摘要 `缩放 0.70 · 透明 0.70 · GUI重开 关`（**现算**）+ tooltip 里把副作用原文摊开。
  · 菜单内容 = `EVAL_SM_MENU()`（`items/locked/tips/sel/keys`，唯一条目 **「GUI重开」**，`sel` 由真值现算 ⇒ 不留第二份状态）。
- **真值**：`SM_CFG.guiReopen`（nil/false = 关 = **默认关**；true = 开）；**一次性迁移**老键 `showGUI`（true/非空表 ⇒ 开，
  false/空表 ⇒ 关，nil ⇒ 什么都不写）后 **清掉老键**（与 1.74.29 清 keepUI 同一纪律）。
- **副作用为什么是真的（读 UnrealQuest 得到的机制，铁律 2）**：`Map/MapContext.lua` 的 `InspectPrimed()` 把
  `Client.IsGameUIHidden() == false` 当作「地图是关着的」信号，然后每 `RECENTER_SECONDS=2s` 调一次 `SetMapToCurrentZone()`，
  把大洲/世界层视图拉回当前地图（注释原文：「A player browsing a continent has the map open and is never overruled」）。
  我们在地图打开时重显 UIParent ⇒ 那条信号被打破 ⇒ 插件以为地图关着 ⇒ 浏览大洲时每 2 秒被拉回当前地图。
  ★所以：**默认关 + 提示必须写清**（中文提示里同时有「自动刷新」与「当前所在地图」两句，源码检查钉住这两句不许被删）。
- **测试三件套**：`tests/tools/SimpleMap.lua`（**组 224**：默认关/迁移四态/菜单 1 项与勾选态/**关掉时开图零动作、开着才发**/摘要现算/行登记同源/单一真值，
  夹具自建自清）＋ `tests/checks/SimpleMap.js`（**SM GUIREOPEN WIRING CHECK** + **SM GROUP ROSTER CHECK**）＋ 模块内读值口 `EVAL_SM_TEST_*`。
  ★「关掉时一个动作都不发」靠**计数器** `FEAT.guiCalls`（`featShowGUI` 内自增）——这才是行为断言照得到的事实。
- **顺手修掉的静默失效（本轮最有价值的发现）**：
  · **`tools/SimpleMap.lua` 从没被 harness 载入过**（`test_engine.js` 的 Lua 加载清单是**硬编码**的，只有 `tools/DragFrames/layerFix/…`）
    ⇒ 它的行为断言一直是盲区。★**新增模块文件必须同步这份清单**（与「9 处清单」同族）。
  · **四个工具模块裸调全局 `L(...)`**（LayerFix / DragFrames / RareWatch / SimpleMap）：项目里 `L` 一律是**文件局部**，
    全仓与游戏目录其它插件都没有全局 `L` ⇒ 调用要么报错、要么靠外部全局；在工具箱里还被 `pcall(fn, r, it)` **吞掉**，
    表现是「按钮文案没设上 / 点击处理器没挂」而那一行看着正常。修法 = 按 `ConsumableHelper/DismountHelper/HunterHelper` 的既有写法
    每个模块自带 `local function L(k, ...)`（走全局 `EVAL_L`）；判据 = 新增的 **`MODULE L SCOPE CHECK`**（`tools/*.lua` 只要调 `L(` 就必须自带）。
  · `TB MOD ROW CHECK` 的反向哨兵名单加了 **`EVAL_SM_`**（工具箱里不许再出现模块内部件）。
- **闸门**：`luacheck.js` SYNTAX OK: **40** files · `test_engine.js` ALL TESTS PASS + `MODULE TESTS: 3/3（DragFrames, LayerFix, SimpleMap）` +
  `SM GUIREOPEN WIRING CHECK` / `SM GROUP ROSTER CHECK` / `MODULE L SCOPE CHECK: 7 个模块` / `TB MOD ROW CHECK: 3 个模块行` 全绿，退出码 0；已同步进本机游戏目录（`SYNC OK: 67 + 4 个文件`）。

**⑥o 工具箱那几行的「配置项」移进 tooltip + 检查文件死代码（1.74.36 全案）**
- **用户原话**：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」（截图圈了「缩放大地图 缩放 0.70 · 透明 0.70 · GUI重开 关」与「图层特殊处理 已生效 1/1 项：动作条狮鹫」）。
- **改法**：`tools/SimpleMap.lua` 的 `smRow` 与 `tools/LayerFix.lua` 的 `lfRow` 去掉 `r.extra:SetText(...)+Show()`，改成显式 `r.extra:Hide()`；
  状态**不丢** —— 仍在 `tip.AddLine` 里现读（LayerFix 的 [设置]/[重置] 各一处、SimpleMap 的 [设置] 一处，含 GUI重开 副作用提示）；
  「图层拖拽柄」行本来就没写行上文本（只有 tooltip），无需改。
- **配套判据**：① 读值口 `EVAL_TB_TEST_ROW_TEXT` 增加 `extraShown`（否则「行上不显示了」断言不了）；
  ② 通用 **`TB MOD ROW CHECK ④`**：`tools/*.lua` 里出现 `extra:SetText` 即 FAIL（那一格是工具箱自己的 `t="l"` 列表行在用）；
  ③ 模块自查 `LF ROW SUMMARY CHECK` / `SM ROW SUMMARY CHECK`：行上不写 + 悬停里**必须**有当前配置（SM 还要有副作用提示）。
  ★断言跟着改：组 223 三条（行上不显示 / 悬停里有 / 重置后悬停跟着变）、组 224 新增两条（走**真实 OnEnter** 读真 GameTooltip 记账）。
- **★顺手抓到的死代码（值得单记）**：`tests/checks/LayerFix.js` 的导出函数开头是 `return (function () {…})();`
  ⇒ 后来追加在它**后面**的检查**永不执行**：文件里 grep 得到、日志里从不打印（新加的 `LF ROW SUMMARY CHECK` 就被吞了一整轮，是我另写一个 node 直跑该文件才发现的）。
  已去掉那个 `return`，并把判据加进 `TOOL TEST FILES CHECK`：「`tests/checks/*.js` 的导出函数体里不许有顶层 `return`」。
  【教训】「文件里有这行代码」≠「它会被跑到」—— 检查类代码同样要证明**它打印了**（本项目那条「少跑一个文件/一组 = 静默」的同族）。
- **并发写工作树的实况（记一笔，避免下次误判）**：本轮我编辑期间，`tools/SimpleMap.lua` 与 `tests/tools/SimpleMap.lua` 被**另一处同时写入**
  （新增 `1.74.35-4 叠加层「跟随地图缩放」自动适配`：`smFitApply` · `EVAL_SM_TEST_MAPFIT_TARGETS` · 跳过 12 张 `WorldMapDetailTile*` 底瓦片；组 225；默认开；节奏 0.1s 爆发 2s → 0.3s 稳态）。
  期间套件一度两处红（`SM GROUP ROSTER CHECK: 多了组 225` + 组 225 自断言失败），**都不是我这轮的改动**；
  ★我当时的处置：**不碰对方文件、不跑同步**（避免把半成品推进游戏目录），如实报告并请用户确认；用户回「那边修改完了」后复核 → 两闸门全绿、组 225 PASS、已同步。
  【教训】共享工作树里出现「我没写的符号/组号」时，先取证（mtime + 符号名 + 两个闸门输出）再动手，别急着「修好」别人未完成的中间态。

**⑥p 「缩放大地图」勾选框点不动 = 模块引用了宿主文件的 local（1.74.36-2 全案）**
- **用户报告**（截图）：工具箱 → 缩放大地图的勾选框**点了不会勾上**，聊天框却每次都打「[简易地图] 已启用（开图会自动应用…）」。
- **根因**：`tbCfg` 是 `Toolbox.lua` 的 **`local function`**；模块里写 `(type(tbCfg) == "function") and tbCfg() or nil` ⇒ 恒取 nil
  ⇒ `EVAL_SM_ENABLED()` 永远 false（勾选框读它）、`EVAL_SM_SET()` 的配置写入也永远不执行 ⇒ 每次点击都 set(true) 并播报「已启用」，**只有播报是真的**。
  ★为什么三个闸门全绿：① Lua 语法没问题（luacheck 绿）；② 行为断言测的是模块自己的纯函数，`EVAL_SM_SUMMARY()` 之类照旧对；
  ③ **组 224 里那条真值往返断言被自己的「跳过分支」吞了**（见下）。
- **顺带扫出的一整族**（同一根因，全都是「真机 nil、本地看不出来」）：`say`（Core.lua L77 与 Toolbox.lua L199 的 local）与 `logLine`（Core.lua L104 的 local）——
  DragFrames ~80 处、RareWatch ~30 处、LayerFix ~11 处、SimpleMap 2 处调它们 ⇒ **所有「如实播报」在真机上静默消失**（`pcall` 吞掉），
  这正是用户多次反馈「出错时什么提示都没有」的底层原因之一。注意 `P`（SimpleMap 自己的 local）与 `EVAL_SAY` 是好的，所以「有的行有输出、有的行全哑」。
- **修法**：
  · `Toolbox.lua` 在 `local function tbCfg()` 之后导出全局 `function EVAL_TB_CFG() return tbCfg() end`（配置真值只读出口）。
  · 四个模块各自补**文件局部** `say`/`logLine`，走 Core.lua 末尾的全局桥（`EVAL_SAY = say` / `EVAL_LOGLINE = logLine`，与 ConsumableHelper 的 chSay 同一写法）。
  · `SimpleMap` 的配置读写改走 `EVAL_TB_CFG()`；读不到时 `smTbCfg(false)` **如实播报一次**（把「开关不落存档」说出来，而不是继续假装成功）。
  · 组 224：`type(tbCfg)` 改成 `type(EVAL_TB_CFG)`，并**先把「跳过分支」删掉**（`（无 tbCfg，跳过）` 那个逃生口正是它让真机 bug 在套件里全绿）。
- **新判据 `MODULE HOST LOCAL CHECK`**：收集宿主（Toolbox/EvalHelp/Core/Engine）的全部 `local`/`local function` 名字（本轮 367 个），
  逐个比对 `tools/*.lua` 里的调用；模块**没自带同名 local** 却调用了 ⇒ FAIL（写明「跨文件只能是全局 nil」）。修完输出：`8 个模块都没有引用宿主文件的 local`。
- **测试纪律（用户同时定的，已进常驻卷）**：改完**默认只跑 `node luacheck.js`（<1s）**；`test_engine.js` **整轮实测 32 秒**，只在**碰到异常 / 改动接线**时跑。
  ★配套教训：语法闸门**照不到接线**——本轮就是 luacheck 全绿而勾选框点不动；所以「动了模块↔宿主接线 / UI 渲染 / 存档读写」时必须补跑一次测试台。


**⑥q 排查「未开启缩放大地图时还在不在监听探索层缩放」（1.75.7 全案）**

**用户原话**：「排查缩放大地图功能.在未开启的情况下会不会监听探索层的缩放操作」

**一、结论：会，而且不只是监听（实测证据）**
- 探针（真机通道：`EVAL_TEST_FIRE_UPDATE(rawget(_G, "EH_SM_FEAT"), 0.05)` 点 10 拍）+ 记账假帧（`WorldMapDetailFrame` 与两张叠加层）：
  `模块开关 EVAL_SM_ENABLED=false ｜ 点了 10 次 tick（0.5s）⇒ 叠加层几何调用 8 次 · ovA=(248.5,-224.0,150.5x150.5) · 记到原值 2 条`。
  ⇒ 关闭状态下：每帧读 `IsShown` + `GetEffectiveScale`（**这就是「监听探索层缩放」**），并且**把叠加层几何折了 ×0.7**。
- 根因两条：
  ① `EH_SM_FEAT` 的 tick 是**载入期无条件建**的（`CreateFrame("Frame","EH_SM_FEAT", WorldFrame)`），与工具箱开关无关；
  ② tick 里 ④ 只看 `smFitOn()`（`SM_CFG.mapFit ~= false`，**nil = 默认开**），③「开图保持」那一段**压根没看总开关**。
  旧注释甚至把这件事写成了**设计**：「只受 smFitOn() 管 —— 否则模块一关，我们已经乘过 es 的几何就没人还原了」——
  也就是说，为了「有人还原」，代价是关掉以后一直跑。

**二、修法（两条，缺一不可）**
1. **tick 免打扰闸门**（放在 `local dt = tonumber(arg1)` **之前**）：`if not EVAL_SM_ENABLED() then FEAT.applied = false
   SMFIT.open/es/burst 清零 return end` —— 关闭时**连读都不读**（IsShown / GetEffectiveScale 各 0 次）。
2. **关闭即还原**：`EVAL_SM_SET(false)` 的 else 分支先 `pcall(smFitRestore, true)`（按首次折算时记下的原值还原），
   再 `featReset()` 复位透明度/缩放/位置，最后**如实播报还原了几项**（没原值的如实说跳过）。
   ⇒ 这样「还原」不再依赖常驻 tick，第 1 条才成立。

**三、修后实测**
`点了 10 次 tick（0.50s）⇒ 叠加层几何调用 0 次 · ovA=(355.0,-320.0,215.0x215.0) · 记到原值 0 条`（读计数也是 0）。

**四、闸门（都做过变异验证）**
- **组 230**（`tests/tools/SimpleMap.lua`，模块自带）：① 关闭 ⇒ `IsShown`/`GetEffectiveScale` 各 **0 次** + 几何 0 次 + 原值 0 条；
  ② 开启 ⇒ 照读照折算（**反向哨兵**：别把功能关死）；③ `EVAL_SM_SET(false)` ⇒ 几何回到原值，之后再点 10 拍依旧全 0。
- **`SM OFF SILENT CHECK`**（`tests/checks/SimpleMap.js`）：源码级钉「闸门在探测之前 + 有 `return` + 清 `FEAT.applied`
  + 关闭路径**真的调用** `pcall(smFitRestore…`」；变异 5/5 捕获（删闸门 / 闸门后移 / 去掉 return / 去掉还原调用 / 基线）。
  ★收紧那一刀值得记：第一版只查「段里出现 `smFitRestore`」⇒ 去掉调用后残留的 `type(smFitRestore)` 仍能骗过检查（M5 漏网）⇒
  判据改成**必须出现调用形态** `pcall(smFitRestore`。
- `SM GROUP ROSTER CHECK` 的 `WANT` 同步为 `[224, 225, 226, 230]`（少一个组 = 整组断言静默消失，这条就是防它的）。
### R16. 铁律 3「先读 Heart / C」的完整对照表（1.74.36-2 从常驻卷 §一.3 迁入）

> 常驻卷只留「一行一入口」的速查；**要动手改队伍/血量/buff 相关代码时回来看这张表**。

| 问题 | 先读 |
|---|---|
| 名字 → unit id（从聊天/战斗文字反查） | `C\C_GetUnitID.lua`（缓存 `C_player_map` + `UnitExists`/名字复核 + 慢查 raid/party/pet/target/mouseover） |
| `target`/`mouseover` → 具体成员 | `C\C_AKA.lua`（`UnitIsUnit` 逐个比对） |
| buff/debuff 全量采集结构 | `C\C_SetPlayerData.lua`（16+16 槽扫描 → `C_player_data[名字].Buff[纹理]`） |
| 采集驱动 + 多插件仲裁 | `C\C_UpdatePlayerData.lua`（★同一轮更新只允许一个调用者） |
| 「某单位有没有某 buff」 | `C\C_UnitGotBuff.lua`/`C\C_UnitGotDebuff.lua`（**要求 `Tick == CurrentTick`** 才算「有」） |
| **用 tooltip 读没暴露的信息** | `C\C.xml`（隐形 `C_Tooltip`）+ `C_GetBuffData`/`C_GetDebuffData`/`C_GetSpellData` |
| 团队主逻辑、血量优先级 | `Heart\Heart.lua`、`Heart\Heart_Helper.lua`（`hpDeficit`、`priority * (healvalue / UnitHealthMax)`） |
| 事件与跨插件通信 | `Heart\Heart_event.lua`、`Heart\Heart_Hooks.lua` + `Plugins\*_Clicks.lua` |
| 图腾 / tooltip 扫描跟踪 | `Heart\Heart_Totem.lua` |

**怎么读**：重点是**大段注释**——对方把踩过的坑、API 的真假、为什么这么写全留在注释里，这是整个仓库**信息密度最高**的内容。


### R17. 「记忆体 65k 上线问题」全案：DSH 换版后限值搬家 + 三条死路（2026-09-25）

> 背景：常驻卷预算被 `dsh-agent-instructions` 的 `maxBytes` 卡在 65536（超了从尾部截断）。2026-09-25 上午在 0.1.5-rc.x 上改好、实证生效；随后 DSH 升级到 **0.1.7-rc.2**，截断又回来了。**排查一上午的结论：问题不在 preset 文件，而在「跑的是哪一份安装 + 限值在哪一层」两头都判断错了。**

**一、判定「现在跑的是哪一份安装 / 哪一版」（★这一条是本轮最贵的教训）**
- 旧判据（看 `_npx\<hash>` 命令行 / 看 `profiles\node_modules` 的 junction）**会骗人**：升级后 junction 仍指着旧的 npx hash（8:23:06 留下的痕迹），而真正在服务 3080 的是全局安装。
- ★**可靠指纹 = 看自己手里有哪些工具**：`dsh` 0.1.7-rc.2 的 `preset-standard`/`preset-ptc` 把 `tool-ralph` 设成 `disabled: true`，而 0.1.5-rc.x 的 standard/ptc **开着它** ⇒ **没有 `ralph` 工具 = 0.1.7-rc.2**（本轮据此判定 = 全局 `%APPDATA%\npm\node_modules\@deepseek-ai\dsh`）。
- 沙箱里 `Get-CimInstance`/`tasklist`/`wmic` 全被拒、`Get-Process` 也看不到宿主 `node.exe` ⇒ **不要指望从进程查命令行**，改用「工具指纹 + `dsh_memory_budget.js status` 列候选安装」。

**二、65536 在 0.1.7-rc.2 里的真实出处（`--dump-config` 实证）**
- preset 不再是 `dsh-agent-presets\presets\<id>\agent.cordis.yml` 目录，而是 **bundle 补丁里的声明行**：`dsh-web-app\presets\<id>.patch.yml` 中 `- id: preset-standard`（`name: @deepseek-ai/dsh-agent-preset`）的 `config.plugins` 里那条 `agent-instructions.config.maxBytes: 65536`。
- 同一份 dump 还显示：宿主（host 平面）那条 `agent-instructions` 是 **`disabled: true`**（被 `dsh-web-app` 的 bundle 补丁关掉）——**这就是「改了等于没改」的根源**。

**三、三条死路（都实测过，别再走）**
| 改法 | 结果 |
|---|---|
| 改 `_npx\<hash>\…\dsh-agent-presets\presets\<id>\agent.cordis.yml`（0.1.5 布局） | 0.1.7 **根本不读这个路径** ⇒ 无效（0.1.5 上升级/换 hash 也会被覆盖） |
| 改安装内 `dsh-web-app\presets\<id>.patch.yml` | **有效但一次性**：`npm i -g` / 换 npx hash 即回 65536 |
| profile 补丁里只写**单层** `- id: agent-instructions` + `config.maxBytes` | dump 里能看到它被应用，但那一行是 **disabled** ⇒ 仍然 65536 |

**四、正解（官方机制）**
- 官方 `dsh-agent-preset` 的 `skills/editing-cordis-compositions` 明确：**按 Loader 行 id 覆盖**，且★**覆盖会替换整个 `config`** ⇒ 必须完整重述 `id`/`order`/`plugins`。写法：
  `- id: preset-standard` + `name: '@deepseek-ai/dsh-agent-preset'` + 完整 `config`（`plugins` 里把 `maxBytes` 改成 1048576）。
- 落点 = **profile 补丁层** `%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml`（覆盖顺序 bundle → **本文件** → home patch → `--patch`）⇒ **升级 dsh / 换 npx hash 都不会丢**。
- ★**不完整重述 = preset 激活失败**：2026-09-25 早上 GUI 崩（「3 个 preset 激活失败」+ 图片识别模型选不到）就是上一轮手工写「两级 id」造成的 —— 所以本轮一律**脚本生成**：仓库根目录 **`dsh_memory_budget.js`**（`apply` 从当前安装重生成 + 先备份；`check` 闸门；`status` 诊断）。
- 代价（须知情）：覆盖块**冻结**了 preset 内容，上游若改 preset（增删行）会被遮住 ⇒ `check` 里的**漂移检测**会在两边行 id 不一致时报警，那时重跑 `apply` 即可。

**五、闸门（免重启、不碰真实 profile）**
- 手法：把真实 profile 的 5 个小配置文件复制进工作区内的**临时 `DSH_HOME`**，用**官方 CLI** 跑
  `node <install>\lib\bin.js --profile web --dump-config`，断言每个 preset 的 `agent-instructions.maxBytes`；
  残留的非目标值**只允许出现在 `disabled` 行**里。
- ★两个沙箱坑：① **node 输出走管道（`| Select-Object`）会被拒**（`Access is denied`）⇒ 改用 `spawnSync` + **文件描述符**落盘再读；② dump 会**重写 profile 的 `cordis.yml`**（`prepareProfile`），所以必须指向临时 `DSH_HOME`。
- `--dump-config` 顺带解释了一件旧事：临时 HOME 里 `dsh-builtin-browser` 解析不到会打警告但不影响 dump（那是 profile 级安装的包）。

**六、生效条件与验证**
- `patchReload = startup` ⇒ **必须重启 GUI**；preset 修订**只影响新开会话**（旧会话保持原预算）。
- 验证仍用老办法：把常驻卷撑过 65,536，看下一次注入有没有 `Workspace instruction budget … truncated`。
- 旧上限下软上限 ≈ 65,240 字节；本轮排查期间常驻卷已被撑到 66,841 ⇒ 截断到 65,244（尾部铁律 AI 看不到）——所以**改完记忆要尽快重启验证**。

**七、自己脚本踩的坑（同族纪律：幂等性必须当场验）**
- 临时脚本用标记注释 `# >>> … dsh_preset_fix.js 生成 …` 写入，正式脚本换了标记文字 ⇒ 剥离正则匹配不到旧块，`apply` 把覆盖块**又追加了一份**（22503 → 43552 字节）。修法 = 剥离用**通用正则**（`^# >>>…常驻指令预算覆盖[\s\S]*?^# <<<`）不认死某一版文字，并在写入后**自检块数 == 1**；★`apply` 连跑两次必须**字节完全相同**（本轮实测 YES）。
- 闸门自身也踩过一次：按「上一个顶层行」划 preset 块 ⇒ 串块（`preset-minimal` 居然“读到” 1048576）。修法 = 块范围从**preset 行自己**起算到下一个顶层行。

**八、复核命令（照抄）**
```
node dsh_memory_budget.js status   # 候选安装 + 采用哪一份
node dsh_memory_budget.js check    # 闸门（exit 0 = 三个 preset 都 1 MiB）
node dsh_memory_budget.js apply    # 升级 dsh 后重新生成覆盖块（先备份，再自证）
```


### R18. 「玩家追踪效果（草药 / 采矿 / 野兽…）」API 调研 + 实证候选表全案（1.75.3）

> 用户原话：「分析API 排查 玩家追踪效果.草药,采矿,野兽之类的.」
> 一句话结论：本客户端**只有三条追踪 API**（读状态 / 读名字 / 取消），**没有枚举**，**小地图圆点读不回来**，
> **事件名官方没公开** ⇒ 实时刷新的事件判据只能真机实测；而「是哪一种追踪」靠**纹理解析**（13 条实证表）
> ＋**名字备用路**两条独立路互证。

**一、API 面（本地 1370 条 `api_*.html` 索引 + 官方 wiki 逐页核对）**

| 目的 | API | 类别 | 官方要点 | Protected |
|---|---|---|---|---|
| 在不在追踪 / 图标 | `GetTrackingTexture()` | Mapping | 返回当前追踪法术的**图标纹理**；没有追踪 = `nil` | 无 Protected 行 ⇒ 可直调 |
| 是**哪一种**（本地化名字） | `GameTooltip:SetTrackingSpell()` | GameTooltip(widget) | 「Fills an aura tooltip from the player's current tracking spell. **Clears lines first. Does nothing if no tracking spell is active.**」 | 同上 |
| 关掉追踪 | `CancelTrackingBuff()` | Buff | 「Cancels the player's current tracking aura (Find Herbs, Track Beasts, and similar)… **Buff-bar auras are unchanged**」 | 同上 |

- **不存在**：`GetNumTrackingTypes` / `GetTrackingInfo` / `SetTracking`（1.12 那套枚举在本客户端没有）。
- **开追踪**：`CastSpell`/`CastSpellByName` 是 Protected ⇒ 插件只能 `UseAction(slot)`（追踪法术得先在动作条上）。
- **小地图圆点**：Minimap 官方页只有 `SetBlipTexture`（队友点）/ `SetIconTexture`（**追踪图标**：生物 / 资源 / 任务 / 宠物）
  两个**纯外观** setter —— **没有任何 blip 列表读口** ⇒ 「图上看到了什么」不能反读。
- **增益条不是追踪的家**：官方明文 `GetPlayerBuff` 会 **skip** hidden/tracking auras，Buff 页也写
  「Tracking auras are **not** listed here」⇒ 光环路线只能当旁证（探针⑤就是拿它做旁证）。
- **事件名**：wiki `/wiki/lua/Events` = **404**，索引里也没有事件表（只有 UIObject 的 `RegisterEvent`）
  ⇒ pfUI 用的 `PLAYER_AURAS_CHANGED` **只是 TurtleWoW 的值**，本客户端**必须实测**（探针⑧）。

**二、候选表怎么从「抄来的」变成「实证的」**

1. 官方数据库 `database.emberveil.org/spell/<id>` 逐条取**英文名 + 图标 png 名**；
2. 拿 png 名去**本机图标清单**（`doc/图标路径清单.txt`，`/eh go icons` 从真机采的 1018 条，形态
   `/Game/Interface/Icons/<基础名>_TEX`）**逐条核对存在性** —— 两条独立证据都对上才写进表；
3. 13 条（pfUI 那张表只覆盖前四条，其余 9 条是本轮补的）：

| 种类（标签） | 客户端图标基础名 | enUS | zhCN | ID |
|---|---|---|---|---|
| 采药 | `INV_Misc_Flower_02` | Find Herbs | 寻找草药 | 2383 |
| 采矿 | `Spell_Nature_Earthquake` | Find Minerals | 寻找矿物 | 2580 |
| 寻找宝藏 | `Racial_Dwarf_FindTreasure` | Find Treasure | 寻找宝藏 | 2481（矮人种族） |
| 追踪野兽 | `Ability_Tracking` | Track Beasts | 追踪野兽 | 1494 |
| 追踪人型生物 | `Spell_Holy_PrayerOfHealing` | Track Humanoids | 追踪人型生物 | 19883 |
| 追踪恶魔 | `Spell_Shadow_SummonFelHunter` | Track Demons | 追踪恶魔 | 19878 |
| 追踪龙类 | `INV_Misc_Head_Dragon_01` | Track Dragonkin | 追踪龙类 | 19879 |
| 追踪元素生物 | `Spell_Frost_SummonWaterElemental` | Track Elementals | 追踪元素生物 | 19880 |
| 追踪巨人 | `Ability_Racial_Avatar` | Track Giants | 追踪巨人 | 19882 |
| 追踪亡灵 | `Spell_Shadow_DarkSummoning` | Track Undead | 追踪亡灵 | 19884 |
| 追踪隐藏生物 | `Ability_Stealth` | Track Hidden | 追踪隐藏生物 | 19885 |
| 感知恶魔 | `Spell_Shadow_Metamorphosis` | Sense Demons | 感知恶魔 | 5500（★算不算「追踪」待真机验） |
| 感知亡灵 | `Spell_Holy_SenseUndead` | Sense Undead | 感知亡灵 | 5502（★同上） |

★**ID 不能照 1.12 抄**：实测 19881 在本客户端是 `Shoot (TEST)`（1.12 里那一档是 Track Elementals 一类的追踪），
ID 全部现取自数据库；★`ruRU` 在数据库里**回落到英文** ⇒ 名字备用路只收 zhCN/enUS（认不出就 nil，不猜）。
★盘点方法可复用：`database.emberveil.org` 的 `/spells` 列表页是服务端渲染的分页（每页 50、搜索框是客户端的），
所以**按已知 ID 逐条取详情页**比爬列表快；详情页图标 png 名 = 客户端图标基础名（小写）。

**三、落地到代码（都带判据）**

- `EVAL_TRACK_BASE(tex)`：剥反斜杠目录（**`string.char(92)`，源码里不手写转义**）/ 取末段 / 剥扩展名 / 剥 `_TEX` / 转小写。
- `EVAL_TRACK_KIND(tex)`：**基础名全等**比对 `TRK.hint`（子串匹配会误报；组 189 有 `..._02_Copy` 变异哨兵钉住）。
- `EVAL_TRACK_KIND_BY_NAME(nm)`：名字备用路（zhCN/enUS）；探针③把两条路**互证 / 不一致**都如实打出来
  （静默取一路 = 候选表某一格写错了用户永远看不到）。
- ⑦ 法术书扫描改按**纹理**判：连「感知亡灵」这种名字里没有「追踪/寻找」的也抓得到；名字像而纹理没命中的**单独列**（= 补表候选）。
- 子命令 `/eh go 追踪探针 表` 把 13 条摊开（回传对照用）。
- 闸门：**`TRACK ICON CHECK`**（`tests/checks/Track.js`：4 列 / 13 条 / 基础名不重复 / 逐条在本机图标清单里存在 /
  表里不许写路径与 `_TEX`）＋ **组 189**（走真实命令入口与真实调用链）。

**四、真机取证流程（本轮还没跑完的那一步）** —— 事件名与「客户端返回的纹理串形态」只能真机拿：

1. 干净状态：`/reload`；
2. **不开追踪**跑 `/eh go 追踪探针` → 看①「本次=（空/无追踪）」、②「当前没追踪」；
3. 用小地图按钮**开草药追踪**再跑一次 → ①应有纹理、②应是「寻找草药」、③应「基础名=inv_misc_flower_02… 两条路互证」；
4. 换**采矿**、再换**野兽**各跑一次（对照「上次 → 本次」）；
5. 开 `追踪探针 监听` → 用按钮切换 3 次（开 → 关 → 换种类）→ 再关掉监听，看**哪条事件计数真的涨**（那就是实时刷新要注册的事件）；
6. `/reload` → 我这边直接读 `%LOCALAPPDATA%\Azeroth\Saved\Account\LIHAIBOAS1\SavedVariables\EvalHelp.lua` 的 `trkProbe`
   （★探针读数另存 40 行小环：`[DS]` 心跳 ~10 秒一行、调试日志环只有 100 条 ⇒ 约 17 分钟就被冲干净）。


**五、真机首轮读数（2026-09-25 用户跑完流程）与本轮探针升级（1.75.4）**

- 存档 `trkProbe` 里只有**两份报告**，且**完全一样**：① `GetTrackingTexture：可用=true ｜ 本次=（空/无追踪）`、
  ② `当前没追踪`；同时 ⑥ 动作条读到 2 个追踪技能（寻找矿物 slot 26 / 追踪野兽 slot 38）、⑦ 法术书 2 条、
  ⑤ 增益条 1 个光环（`Spell_Nature_RavenForm_TEX`）。⇒ **API 与 UI 都活着，但没有任何一条能说明「当前追踪是什么」**。
- ★旧探针的三条**静默路**（这就是「两次都读不到」不能当结论的原因）：
  1. `GetTrackingTexture` 的返回**不是字符串**时被 `type(v)` 等于 string 的判断直接丢掉，报告照写「没追踪」；
  2. ② 的判定挂在 `cur == nil` 上 ⇒ **有追踪也永远走「当前没追踪」那一支**（名字路读了也不给看）；
  3. 事件名靠**猜 4 条候选**，猜不中就永远看不见那条真事件（用户那次也没跑 `监听`，所以事件仍是空白）。
- 1.75.4 的修法（判据全部落在**组 189**）：
  · ① 打「类型 + 原文」；② why 四态（ok / empty / noguard / noapi）+ tooltip 两行原文；
  · ⑤ 光环读名字（`EVAL_PLAYER_BUFF_NAME`），若其中一条命中候选表或名字像追踪 ⇒ 点名「本客户端追踪**占增益条槽位**」；
  · ⑩ **第三条独立路**：默认 UI 追踪按钮（候选名 + 有界 `_G` 扫描名字含 Track/追踪 的对象，报类型 / 纹理 / IsShown），
    ＋ ⑪ 一行快照（开/关各跑一次直接比这一行）；环形读数上限 **40 → 80** 行（装得下 3 份报告）；
  · ⑧ `监听` = `RegisterAllEvents` **全事件抓取**（handler 只计数，关掉时按**次数升序**列全部事件名；
    没有该接口时如实退回 4 条候选并点名）。
  · ★踩到的判据坑：**`pcall` 的第一个返回是成功标志**，而 `RegisterAllEvents` 真机不返回值
    ⇒ `pcall(...) and true or false` 恒为真（退化路永远走不到）；正解 = 「接口在不在 + 抛没抛错」。

**六、真机第二轮读数（1.75.4 探针）= 可行性结论（2026-09-25，追踪野兽 开着）**

- ① `GetTrackingTexture()` = `/Game/Interface/Icons/Ability_Tracking_TEX.Ability_Tracking_TEX`
  ⇒ **确实返回字符串**；形态 = **资产路径 `_TEX` + 「.」 + 对象名 `_TEX`**
  （第一轮读数之所以是「没追踪」，是因为那时**确实没开追踪** —— 探针没错，是状态问题）。
- ② `SetTrackingSpell` 读到 `追踪野兽`（TextLeft1=追踪野兽 ／ TextLeft2=正在追踪野兽。）⇒ 名字主路可用。
- ③ 老 `EVAL_TRACK_BASE` 把上面那条归一成 `ability_tracking_tex.ability_tracking` ⇒ **永远命中不了候选表**
  （报告里 ③ 写「没命中」而 ② 是对的）。**1.75.5 修**：取最后一段后只认第一个「.」之前 ⇒ 归一到 `ability_tracking`。
- ⑤ 增益条只有 1 条别的光环（`Spell_Nature_RavenForm_TEX`，名字读不出，与本主题无关）
  ⇒ **追踪不占增益条**（官方那句 Tracking auras are not listed here 对本客户端**成立**）。
- ⑩ `MiniMapTrackingIcon`（Texture，纹理与①**完全相同**，`IsShown=true`）+ `MiniMapTrackingFrame` / `MiniMapTrackingBorder`
  ⇒ 默认 UI 的追踪按钮可以作为**第三条独立路**（不依赖那两个 API 也能知道「现在在追踪什么」）。
- ⑪ 快照：`纹理类型=string ｜ 纹理=...Ability_Tracking_TEX ｜ 名字=追踪野兽（why=ok） ｜ 光环=1 个 ｜ 追踪按钮命中=2 ｜ 扫描=24 条`。
- ⇒ **可行性结论**：判「在不在追踪」= ① 非 nil；判「是哪一种」= ② 名字 + ① 纹理对候选表（两条路互证）；
  兜底 = ⑩ 追踪按钮图标；**事件名仍未实测**（这轮监听输出被 80 行环挤掉了）
  ⇒ 实时刷新用 **1s 轮询纹理 + 纹理变了才读名字** 即可，不必依赖官方未公开的事件名。

**七、1.75.6 落地：把它做成条件类型（「自身状态 → 追踪类型」单选下拉）**

- 数据流：`TRK.hint`（**id/基础名/en/zh 四列**，第 1 列是语言无关的**稳定 id**）→ `EVAL_TRACK_KIND(tex)` 返回 id →
  `EVAL_TRACK_LABEL(id)` = `L("TRK_"..ID)`（三语，由 TRACK ICON CHECK 守）→ 下拉清单 `EVAL_TRACK_LIST()`（任意 + 13 条）。
- 求值：`EVAL_TRACK_NOW()`（**按纹理缓存**：纹理没变就不读 tooltip）→ `EVAL_TRACK_MATCH(id)` → `condOne` 的
  `k == "tracking"` 分支（`cd.v == false` = 反向）。新加一条的默认值 = 追踪/任意/正向（`seDefaultCond`）。
- 文本：「导出走 id」`EVAL_COND_STR` → `追踪:beast` / 反向 `未追踪:beast`；`disp=true` 显示本地化标签；
  `EVAL_PARSE_ONE` 认 `追踪[:id]` / `tracking[=id]` / `未追踪[[:id]]` / 前置 `!`，id 认「稳定 id / 图标基础名 / enUS / zhCN / 本地化标签」，
  **认不出整条丢弃**（与其它条件的写法错误同口径）。
- 编辑器：类型归 **CTG_1（自身状态）**；点文字格 → 单选下拉，**第 1 行 locked =「当前追踪：X」**（实时，仅参考、点不动），
  当前值用**金色圆点**标出；右侧 是/否 = 正向/反向。
- ★坑 1（当场踩到、且是 `LANG KEY CHECK` 的老脾气）：它的正则是 `L\(\s*"KEY"` 的**子串**匹配，不看前一个标识符 ⇒
  `EVAL_TRACK_LABEL("any")` 会被当成语言键 `any`（三语都缺 → 假红）。→ 走局部变量 `local anyId = "any"`。
- ★坑 2：`EVAL_DD_OPEN(..., { selected = ... })` 的选中标记**只在 `multi = true` 时生效**（`ddUI.sel` 只在 multi 分支赋值）
  ⇒ 单选下拉的「当前值」必须自己在条目文案上加标记（本项目「单选列表」第一次这么做，别再浪费一轮）。
- ★坑 3：TRACK ICON CHECK 查语言键时必须**先剥注释**再匹配（`-- TRK_HERB = "…"` 注释掉照样算有键 ⇒ 变异 M3 当场漏网）。
- 闸门：**组 229**（① id/标签/清单 ② 求值 + 缓存（第二次不再读 tooltip）③ 文本往返 ④ 真实 `condOne` 链
  ⑤ 归组/权重/类型名三语 ⑥ 真实渲染 + 真下拉面板 + 单选落值）+ `TRACK ICON CHECK`（变异 6/6 捕获）。

### R19. 「聊天输出总闸门」全案：`say`/`EVAL_SAY` 联动「调试日志」+ 标签改名（1.75.8）

> 用户原话：「say 函数能否在 根据全局配置->记录调试日志状态开关要不要打印.? 记录调试日志重命名->调试日志」
> 一句话结论：`say`（= `EVAL_SAY`）= 插件往聊天框说话的**唯一出口**，跟「全局 → 日志 → **调试日志**」（`cfg.log.on`）联动；
> 该开关同时是**数据层**闸门（`logLine`）与**输出层**闸门（`say`）；关掉后仍看得见的两类行走**常开出口** `EVAL_SAY_FORCE`。

**一、改造前的形态与三个隐患**

| 位置 | 改造前 | 隐患 |
|---|---|---|
| `Core.lua` 的 `say` | 无条件 `DEFAULT_CHAT_FRAME:AddMessage` | 任何模块的播报都躲不开开关 |
| `cfg.log.on`（配置项「记录调试日志」） | 只门控 `logLine`（写不写日志环） | 「写不写」与「说不说」是两条互不相干的轨 |
| 配置项取名 | 「记录调试日志」 vs 「方案技能日志」 | 并排显示几乎同名（1.71.2 那次排查就是被这个歧义引起的） |

**二、落地（三处生产改动 + 改名）**

1. `Core.lua`：`logEnabled()` **上移到 `say` 之前**；拆成 `chatOut`（裸输出）/ `say`（`if not logEnabled() then return end` → `chatOut`）；
   导出 **`EVAL_SAY_FORCE = chatOut`**（常开）与 **`EVAL_CHAT_ON = logEnabled`**（给自建打印口的模块读）。
   ★声明顺序是硬要求：`logEnabled` 写在 `say` 之后 = 闭包绑成全局 nil，运行时才炸（本项目老坑，`DECL ORDER` 的同族盲区）。
2. `EvalHelp.lua`：新增 `local fsay = EVAL_SAY_FORCE or say`（Core 没载入时退回门控版，绝不 nil 调用）；
   **只有三类行走 fsay** —— `/eh log`（+ `/eh logdump`/`logclear` 的命令反馈）、`/eh wdebug`（同一族日志开关）、`/eh help` 全清单；
   其余（含 `/eh go probe|ds …` 诊断）**一律受门控**。
   ★`/eh log` **关掉那一刻**额外打一行「关掉后插件不再往聊天框说话；/eh log 可随时开回来」= **看得见的回头路**。
   ★`/eh wdebug`/`/eh debug` 文案同步改名「**方案技能日志**」（与总闸门不再撞名）。
3. `tools/SimpleMap.lua`：模块自建打印口 `P`（全仓**唯一**直接写 `DEFAULT_CHAT_FRAME` 的模块口）加 `EVAL_CHAT_ON()` 门控；
   ★`SM.lines`（模块自己的探针读数环）**照记** —— 数据层与输出层分开。
   · 全仓审计：其余模块（`LayerFix`/`DragFrames`/`RareWatch`/`HunterHelper`/`ConsumableHelper`/`DismountHelper`/`Toolbox`/`Share`/`PetHelper`/`IconBrowser`）
     的 say 全是「**优先 `EVAL_SAY`，取不到才直写**」⇒ **委托即门控**，一处生效。
   · **有意例外**：子插件 `addons/EH_DebugBox`（独立 `.toc`、本身就是调试盒子）仍直写聊天框。
4. 三语标签 `G_LOG_FILE`：「调试日志（/eh logdump 查看）」/「Debug log (/eh logdump to view)」/「Журнал отладки (/eh logdump)」；
   代码注释里的「记录调试日志」同步改名（`test_assert.lua` 留一句历史说明）。

**三、判据与变异**

- **组 231**（`test_assert.lua` 末尾）：① 两出口在位 · 关 ⇒ `EVAL_SAY` 一个字都不刷 + `EVAL_SAY_FORCE` 照刷（反向哨兵） ·
  ② 开 ⇒ 照常刷 · ③ 历史三态（nil/false/表）+ 同一判据管数据层（关掉连日志环都不写） · ④ 三语标签改名且与「方案技能日志」不再同名 ·
  ⑤ **真实命令入口** `/eh log`（确认行仍可见 + 说清怎么开回来 + 关后 `EVAL_SAY` 静默） · ⑥ 模块播报（`EVAL_SM_SET`）同样静默。
- **`CHAT GATE CHECK`**（`tests/checks/ChatGate.js`，harness 里一行 require）：`say` 先门控再输出 · 两出口导出 ·
  `logEnabled` 声明在 `say` 之前 · `/eh log` 走常开出口且分支内无受门控 `say` · 模块 `P` 读 `EVAL_CHAT_ON` · 三语 `G_LOG_FILE` 在位且 zhCN 无旧名。
- **变异 6/6**：M1 去掉 `say` 门控（组 231① + CHECK 双响）· M2 删 `EVAL_SAY_FORCE` 导出（组 231①）· M3 `logEnabled` 挪到 `say` 之后（引擎直接炸 = 捕获）·
  M4 `/eh log` 改回受门控 `say`（组 231⑤）· M5 SimpleMap `P` 去掉门控（组 231⑥）· M6 zhCN 标签改回旧名（组 231④）。文件全部由内存原文还原。

**四、纪律（与老判据的关系）**

- 常驻卷 §5.2 那条「两个日志开关不能合并」**已按新口径改写**：`cfg.log.on`（「调试日志」）= **总闸门**（数据 + 输出同一判据），
  `cfg.wdebug`（「方案技能日志」）= 更细的一层（Engine 里那批决策原因同步刷屏）——两条分工仍在，但总闸门现在**同时管「说不说话」**。
- 与 §5.1「关掉零动作」同族：**闸门必须在第一次输出之前**；**关掉时必须留一条看得见的回头路**（否则「怎么开回来」无从得知）。

### R20. 「探索层纹理被缩两遍」全案：客户端自己会级联 ⇒ 折算前必须先探测（1.75.9）

> 用户原话（三轮递进）：「地图缩放 探索层纹理缩放是否操作了两遍?」→「发现问题了: 是在关闭一次大地图缩放.
>   
> 然后重新再打开大地图缩放 就进行了2遍纹理缩放」→「我说的纹理缩放是 WordMapDetailFrame 下面 12 之后的纹理缩放逻辑」→
>   「在开启/关闭.大地图缩放要做好探索层纹理的事件清理. 现在确定是在未开启插件载入..的情况下打开大地图缩放,
>   和在开启插件载入之后重新关闭,又打开 ,这两种情况都会发生.纹理渲染层被缩放两次的问题」。
> 一句话结论：**本客户端自己会把父帧缩放级联到那批纹理上**（几何读回也含缩放）⇒ 我们那套「按 es 折算」是**第二遍**；
>   正确做法 = 先只读探测、只有判定「不会级联」才折算；另外两件必修：**原值只在自然档抓一次**、**开启/关闭都要收钩子**。

**一、真机证据（用户 DebugBox 截图 + 存档）**

| 观测 | 数值 | 说明 |
|---|---|---|
| `WorldMapFrame → WorldMapDetailFrame` | `701×468`（锚 -351,-48） | 该帧自然尺寸 `1002×668` ⇒ **读回 = 自然 × 0.7** |
| `WorldMapOverlay1` | `105×105`（锚 174,-157） | = 我们写的 `150.5／248.5` **再 × 0.7** ⇒ 显示 = 原值 × **0.49** |
| `WorldMapDetailTile1..12` | `179×179`（锚 0,-0） | 互相锚 + 偏移全 0 ⇒ 对缩放免疫（本功能按设计**不碰**） |
| SavedVariables | `tb.simpleMap = true` 在、**`simpleMapCfg` 整块不存在** | 模块的设置与「原值记录」**一个都没落盘** ⇒ 见根因④ |

**二、三条根因（全都属「静默」族）**

1. **方向判反**：`smFitApply` 无条件按 `es` 折算。只有在「客户端**不会**级联」的客户端上这才正确；
   本客户端会级联 ⇒ 我们是第二遍。1.74.34-18b 的老探针（`/edb maptile fit s`，眼看对齐）当年测的是**另一种施加方式**
   （直接缩画布/尺寸），不能外推到今天这条「缩外框 + 折算纹理」的组合 —— ★**旧结论要连条件一起继承**。
2. **原值口径错**：开启路径先 `smApplyDefaults()`（立刻 `SetScale(0.7)`），**之后**才在 tick 里记「原值」；
   本客户端读回含缩放 ⇒ 记下的 `r.w` 已是缩过的值，再折一次 = 第二遍（**违反**「读原值 → 写新值」的顺序铁律）。
3. **关→开连乘**：`smFitRestore` 结尾 `SMFIT.rec = {}`，重开时 `smFitApply` 把**当前（已折的）值**当原值重记 ⇒
   每关开一轮多乘一次（用户第二种情形）。
4. **配置是孤儿表**（同一案附带挖出）：模块在**文件执行期** `return EVAL_HELP_CONFIG.simpleMapCfg`（本项目已定案：
   那时 `EVAL_HELP_CONFIG` 还是**空表**；DragFrames 有明文纪律）⇒ 客户端稍后把全局换成存档那份，本模块此后全写进**没人保存的表**。

**三、修法（六条，全部落成判据）**

1. **配置改懒代理** `EH_SIMPLEMAP_CFG = setmetatable({}, {__index/__newindex → smCfgLive()})`（每次现取 `rawget(_G,"EVAL_HELP_CONFIG").simpleMapCfg`）。
2. **折算前先探测** `smFitDetect()`（只读）：外框缩放在 `1 → 0.7` 走一档，读纹理**屏幕几何**（`GetLeft/GetTop/GetWidth`，本客户端含缩放）——
   跟着变 ⇒ `needFold = false`（**一个几何都不碰**）；不变 ⇒ `true`；读不到 ⇒ `nil`（**按不折算处理**，因为用户实测的两次都发生在会级联这一侧）。
3. **闸门 + 策略三档**：`SM_CFG.mapFitMode` = `nil`/`"fold"`（**默认：照旧折算**，探测结论只进提示/取证）/ `"auto"`（听探测）/ `"nofold"`（一个几何都不碰），
   判定收在唯一入口 `smFitNeedFold()`；`smFitApply` 与 tick **各一道门** —— ★只放一道时变异 M1 当场漏网（见下）。
   ★★**别把默认改成「听探测」**：那一版上线后用户立刻报「**现在正常开启都无法生效缩放修正**」——
   用户看到的是「功能没了」，而真正的 bug 是**原值被污染**。策略口 = `/ehm mapfit mode fold|auto|nofold`（给真机 A/B 定档用）。
   ★**判「显示对不对」要分模型**：级联客户端（读回含缩放）正解 = **显示 = 原值×es 且一个逻辑写都不发**（幂等判据直接跳过）；
   不级联客户端正解 = 逻辑值折一次。把「逻辑值」直接与 `原值×es` 比 = **测错了模型**（级联侧逻辑值永远是原值）。
   ★**「真写过」标记 `SMFIT.wrote`**：本会话一次几何都没写过 ⇒ 关闭时**连还原都不写**（否则级联客户端上会白写 4 次几何）。
4. **原值只在自然档抓** `smFitCapture()`：临时 `SetScale(wm, 1)` 读几何（读完立刻恢复），且**只补没记过的目标**；
   `smFitApply` **不再记原值**（只采纳 `SMFIT.rec` / 带版本戳的存档），`smFitRestore` **不再清 `SMFIT.rec`**（并在有活对象时优先用活对象、写完**读回自证**）。
5. **记录键用纹理名**（`WorldMapOverlay1`…）而不是枚举序号 `tex13`（序号会随换区/重建漂移 ⇒ 还原写到别的纹理上）。
6. **关闭收钩子** `featTeardown()`：摘 `EH_SM_COORDS` 的 OnUpdate + Hide、Hide `EH_SM_DRAG`、把 `UISpecialFrames` 里**我们插的那项**拿掉（`FEAT.escAdded` 记账）；
   滚轮处理器与坐标行各加一道 `EVAL_SM_ENABLED()` 门（不摘链 = 不弄丢客户端原生滚轮）。
   另加 `featApplyScale` **读回自证**（同档不重写；设置累乘的客户端上「一次开启写两遍」也会缩两遍）。
   旧存档迁移：`mapFitVer ~= 2` 的原值**整块丢弃**（旧版可能已被污染）—— 用户那份存档的自愈路径 = `/reload` 后客户端重新布版 + 自然档重抓。

**四、判据与变异**

- **组 232**（`tests/tools/SimpleMap.lua`）：① 会级联客户端 ⇒ 开启后 10 拍 **零几何调用**（含**直接入口** `EVAL_SM_TEST_MAPFIT_APPLY`）；
  ② 不级联客户端 ⇒ 折一次 = `原值×es`，且**关一次再开仍是 `原值×es`**（旧版连乘成 `原值×es²`）；③ 原值取自自然档（`215／355`）且键 = 纹理名；
  ④ 关闭收钩子（坐标行 OnUpdate 摘掉 + Hide、ESC 列项拿掉且**别人的项一个没动**）；⑤ 旧存档无版本戳 ⇒ 整块丢弃；⑥ 同 es 第二拍 `changed = 0`（幂等）。
- **`SM FIT CASCADE CHECK`**（`tests/checks/SimpleMap.js`）：探测存在 · **两道**策略门 · 策略三档齐全且**默认分支必须是 fold**（用户实测的回归）+
  策略写口存在 · apply 不写原值 · 原值取自自然档 · 还原不清记录 · 开启先准备后缩放 · 关闭调 `featTeardown` · 缩放读回自证 · 滚轮/坐标行各一道门。
- **折算取证环**（用户：「可以开启日志.在何种情况下会进行双次缩放操作.」）：`SM_CFG.mapFitTrace`（60 行小环，随 SavedVariables 落盘，**不受「调试日志」开关管**），
  记探测/抓原值/折算/还原/开关五处的**实数**；`/ehm mapfit trace`（走常开出口）随时打出来，`traceclear` 清空。
  ★为什么另存一份：`EVAL_LOGLINE` 走「调试日志」总闸门，关掉就一个字都不记 ⇒ 取证不能挂在它上面。
- **变异 10/10**：M1a 去 apply 的门 · M1b 去 tick 的门 · M2 apply 又写原值 · M3 还原又清 `SMFIT.rec` · M4 先缩放后准备 · M5 缩放不读回自证 ·
  M6 关闭不收钩子 · M7 滚轮去门 · M8 tick 不懒探测 · M9 探测恒「会级联」 · M10 迁移不丢旧值。
  ★**M1 第一轮漏网**（检查只匹配到一处门）⇒ 已补「apply 段内单独钉一道」+ 组 232① 加直接入口断言 —— **变异验证必须跑，而且要看它到底抓没抓到**。
- 另外把 `SM OFF SILENT CHECK` 的闸门定位改成「**从 `EH_SM_FEAT` 创建处往后找**」：新增两道门后，全文件 `indexOf` 会命中前面那些门，顺序判据当场假红。
---

## 十五、速查：分享消息模板 / 取证命令 / 关键 CHECK 明细（1.75.1 从常驻卷 §5.10 整段迁入）

> ★常驻卷超工作区指令预算会被**从尾部截断**，故把本节整体搬来（**原文未改一字**，只把标题降为 15.1）。
> 常驻卷 §5.10 现在只剩一行索引指向本节。

### 15.1 速查：分享消息模板 / 取证命令 / 关键 CHECK 明细

**分享消息（三段：色码打头 + 带链接 + 每条一段 8 位色码，间隔 ≥1s；身份只在 A 行）**
- 分片 `|cff9ad4ff|HEHPF:<id> <i>/<n>:<hex>|h[传输中...p%]|h|r`（走 `SH_CHUNK_LABEL` 三语言）
- A 行 `|c<身份色>|HEHPF:<id> 0/1:0|h[<头衔>]|h|r <名字> 分享了` · B 行（末条）`|c<品阶色>|HEHPF:<id> 0/1:1|h[<符号><品阶>秘籍·<名>]|h|r  <评语>`（★B 不带头衔尾巴）

**取证命令（本项目纪律：能做成命令就别让用户手工复现）**
- 光环：`/eh go tex`（看学习表）· `texdel 名字` · `texclear` · `texscan`；名字着色：`名字缓存`、`聊天 色测`。
- 分享：`/eh go 封皮测`（编号 A/B 变异测）· `分享探针`（发送留痕）· `色码测`（在用色码逐条实发；★跑完等 ≥30 秒再跑第二次）· `名号色 [<n>]`（预览/选用）。
- 其它：`/eh ds hud|trace|rnd` · `/eh go probe|bind|diag` · `/eh logdump` · `/eh guide`；稀有 `/eh go 稀有 目标|链接|目标探针`；框体/开窗 `框体探针`、`开窗探针 [停|看]`（只读）

**关键源码检查在守什么**（逐条清单已迁参考卷**附录 R13**，全清单见 `test_engine.js`）。


---

## 十六、§5.4「框拖拽 / 图层工具」判据原文（1.75.1 从常驻卷整批迁入）

> ★★**口径已于 1.75.1 变更**：宽/高从「所有窗口都不给」收窄为「**只给聊天窗**（并持久化）」——
>   下面是**迁移当时（1.75.1 合并）的原文快照**，作为历史保留；**现行判据以常驻卷 §5.4 ④ 为准**。

> ★常驻卷超工作区指令预算会被**从尾部截断**（§5.10 与 §六 导航行就这么丢过一次），故把这一整块**原文照存**在这里。
> 常驻卷 §5.4 现在只剩 7 行要点总表；要查**逐条判据的完整表述与踩坑经过**看本节（另见 R15 ⑥a~⑥n）。

- ★★★**「图层选择」名单（[设置] 多选下拉）**：真值 `dragFrames.pick[名]=true`，**表不存在 = 全选**；唯一写入口 `EVAL_DF_PICK_SET`（★第一次写先**物化全选快照**，否则一次取消勾选 = 其余几十层静默全关）；**七条路径全过 `dfPicked`**；菜单唯一来源 `EVAL_DF_PICK_MENU`。判据 = 组 214 + `DF PICK WIRING CHECK`；细则见 R15 ⑥a。
  ★**窗口图标与头部拖拽带**：图标 = **346 号宏图标**（按号现取、取不到退回「配」）；**左键只拖窗口、属性窗挂右键**；整条标题栏再挂透明「头部拖拽带」；分工收在 `dfBindDragButton`。判据 = 组 212/215 + `DF ICON ART CHECK`；细则见 R15 ⑥b。
  ★★★**拖拽位移一律「按屏幕算 + 量回自证」**（1.74.33）：`base.l/base.b` = 拖前**实测屏幕位置**；落锚唯一入口 `dfPlaceFrom`（首猜按 `GetEffectiveScale` 折算 →**量回**→**手量折算**修正）；`dfDragEnd` 新式基准记**屏幕差**。★必须**解仿射**（反算偏移与真偏移差一个**常数**，除系数救不了）。判据 = 组 217①~⑦ + `tmp/mut_drift.js` 6/6；全案见 R15 ⑥c。
- ★★★**所有窗口都不许改宽/高**（1.74.33 用户**第二次澄清**：「属性配置需要支持调整的是窗口的 x,y 坐标值」）：唯一真值 = **`DF_NO_SIZE`**（载入期给**每个**目标挂 `noSize`），读它三处 = 属性弹窗（**不建**宽/高行 + 常显说明）· `dfAttrsApply` 的 **`allowSize` 门**（**一个宽高写调用都不发**）· 老记录清理（清 w/h 并**还原 `ow/oh`**，没有原始值就**不去猜**）。★★**开窗重设 = A + C**：A＝**链式接管 `OnShow`**（先 `pcall` 调原生再跑 `dfApplyOne`；可重链、关掉即卸链）；C＝开窗后**有界**短复查（0.3s×4 / 墙钟 3s，**拖拽与战斗跳过**，到点摘脚本）。★★**位置调整 = 属性弹窗 X/Y 两行**（**绝对屏幕坐标** + 下拉预设 + `[−][+]` 微调；一律换算成屏幕位移走 **`dfPlaceFrom`** 量回自证，**绝不许**当本地偏移）。判据 = **组 206** + 组 208④⑥ + 组 220①③④ + **组 222** + `DF OPEN HOOK CHECK`；变异 `mut_nosize_all.js` 7/7 · `mut_xy.js` 4/4；全案见 R15 ⑥e。
- ★★★**1.75.1 追加：常驻层补「宠物动作条」**（用户：「工具→图层拖拽→设置. 常驻层缺少宠物动作条」）：`DF_TARGETS` 新增 `PetActionBarFrame`（`cands` 候选名解析，同动作条1~4 —— 本客户端 UI 编译在 pak 里，帧名只能现场探；一个都没命中就**如实缺席**、不画柄）；★**不带 roster/icon 标记 ⇒ 自然归第 1 组「常驻层（拖拽柄）」**（分组由 `EVAL_DF_PICK_MENU` 现算，标签不写死）。★★它是**按需出现**的（没宠物时不显示）⇒ 与队伍/团队同族，进 `DF_ROSTER_EVENTS` 的**有界跟随**：事件 **`UNIT_PET`** 有本地证据（本项目 `addons/EH_DebugBox/EH_DebugBox.lua` 正在注册它）、★**`PET_BAR_UPDATE` 本地零证据 ⇒ 不注册**（铁律 5④：探测名单不算注册依据）；跟满 `DF_ROSTER_TRIES` 即停、**不做常驻轮询**。判据 = 组 207/208。
- ★★★**1.75.1 起宽/高口径 = 只给聊天窗（并持久化）** —— 本节上面那条「所有窗口都不许改宽/高」是 **1.74.33 的原文快照**，仅作历史；现行以常驻卷 §5.4 ④ 为准（`dfSizeOK` / 弹窗显隐+窗高 / `allowSize` 门 / 清理只清 `noSize==true`；顺序铁律「先抓原值 → 再写新值」）。
- ★★★**「图层特殊处理」= 独立模块 `tools/LayerFix.lua`；「图层拖拽」那一行的界面接线也在自己的模块里**（1.74.34）：处理收在**规范表 `LF_FIXES`**（key/kind/`layer.cands`/`pick{last|path}`/label·tip 取词函数）；真值 = 本模块子树 `layerFix.fix[key]`，★**表不存在 = 一条都不选**（与 pick「不存在=全选」**相反**）；三处执行（勾选当场 / 载入期 / 有界复查到点摘脚本）；**层不在或对象数不够 ⇒ 一个都不动 + 如实播报**；还原三态（nil=读不到 ⇒ 按显示还原）。
  ★★**界面侧只两处嵌入点**（用户：「尽量少的在 ToolBox 里改，只要加入嵌入点进行函数调用」）：① 载入期 `EVAL_LF_INSTALL`/`EVAL_DF_INSTALL`；② 工具箱**模块行**（一行数据 `t = "mod"` + 一个**通用**分支按 `EVAL_TB_MOD_ROWS[mod]` 取渲染函数）—— 工具箱里**不许**出现 `EVAL_DF_*`/`EVAL_LF_*` 这类模块内部件。判据 = **组 223** + `LAYER FIX WIRING CHECK` / **`TB MOD ROW CHECK`**；变异 `mut_lfix.js` 10/10 · `mut_dfrow.js` 6/6；全案见 R15 ⑥g。
- ★★★**工具箱那几行的「配置项」只在 `[设置]` 的悬停说明里显示，行上不再重复**（用户 1.74.36：「工具箱->以上UI工具的配置项.不需要再外部显示,已经在tooltip设置内显示了」）：模块行必须 `r.extra:Hide()`（那一格是工具箱自己的列表行在用），状态一律由 `tip.AddLine` 现读（含副作用提示）。判据 = **`TB MOD ROW CHECK ④`**（`tools/*.lua` 里出现 `extra:SetText` 即 FAIL）+ 各模块自查的 `LF/SM ROW SUMMARY CHECK`（行上不写 + 悬停里必须有）；读值口 `EVAL_TB_TEST_ROW_TEXT` 返回 `extraShown` 才断言得了这件事。
- ★★**「柄」按池位号复用** ⇒ 验「某目标有没有柄」要按**目标名**查当前**显示中**的那条（`dfName` 会被后面的目标改写，拿旧对象读 `IsShown` **误报**）。★**同一带上的两个控件 = 遮挡（断言盲区）**：[设置]/[重置] 同锚 ⇒ 后建者压住前者、按钮**永远点不到**而断言全绿（全案 R15 ⑤/⑥）。

---

## 十七、§5.9 关键标识符索引（1.75.1 从常驻卷整段迁入）

> ★常驻卷超工作区指令预算会被**从尾部截断**，故把索引表整段搬来这里（**原文未改一字**）。
> 完整清单（含全部测试读值口）见 `test_engine.js` 与 `test_assert.lua`；逐文件清单见 `tests/`。


- 配置/语言 `EVAL_HELP_CONFIG` · `EVAL_HELP_CFGWIN`（配置窗根）· `EVAL_HELP_CFG_TOGGLE` · `EVAL_RESOLVE_LANG` · `EVAL_IO_TEMPLATES`；解析/算分 `EVAL_PARSE_CONDS` · `EVAL_PROFILE_SCORE` · `EVAL_CLASS_LIST`。
- 分享/封皮 `EVAL_SHARE_SEAL_INFO` · `EVAL_SHARE_SEAL_TIER_RGB` · `EVAL_SHARE_DISPATCH` · `SH_POP_GOT_NAME`；头衔 `EVAL_TITLE_STATE` · `EVAL_TITLE_REFRESH` · `EVAL_TITLE_SET_CUSTOM`（只认第一次）。
- 聊天名字缓存 `tbNcHarvest` · `tbNcAt` · `tbNameClassEnsureRoster` · `EVAL_TB_NAMECLASS_PROBE`；工具箱 `tbBtn` · `tbMenuBuild` · `tbMigrateQuest` · `EVAL_TB_PAINT_ROW`。
- 图标库/下拉/调试 `EVAL_IB_SET_QUERY` · `EVAL_DD_SYNC` · `EVAL_DS_HUD`；测试读值口全清单见 `tests/`。
