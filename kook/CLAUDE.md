# KOOK 发布流程 · 记忆体（独立承载）

> 用户 2026-10-09 定：「**将 kook 发布流程独立记录在 kook 文件目录独立记忆体承载**」。
> ⇒ 宿主 `CLAUDE.md` **只留一行指针**，本文件是这条流程的**唯一正文**（两处并存 = 必然漂移，与子插件记忆体同一把尺子）。
> 配套：`kook/README.md`（索引/状态）· `kook/04-发布频道自动上传.md`（使用与排错全文）· `kook/01-频道维护接口调研.md`（官方接口事实 + 实测）· `kook/02-待实测清单.md`（未验证项）。
> 本文件只记**铁律 / 判据 / 锚点 / 实测数**，写法同宿主记忆体：删叙事、留怎么做。

---

## 一、目标与通道（判据：改频道先看这一节）

| 项 | 值 | 锚点 |
| --- | --- | --- |
| 服务器 | `emberveil 一键宏` = `7071527711947717` | `config.json` 的 `guild_id` |
| 频道 | **「插件发布」`5336773639081280`**，实测 **`type=4` = 帖子频道** | `config.json` 的 `channel_id` |
| 帖子分区 | **战斗 `15785972`** · **背包 `15785973`**（`category/list` 读得） | `posts[].category_id` |
| 发布通道 | ★**帖子频道不能用 `message/create`** ⇒ 一律 `POST /api/v3/thread/create`（主楼 `content` = 卡片 JSON 字符串） | `doSend()` 里 `isThreadChannel = chInfo.type === 4` |
| 机器人 | `EvalHelp_Auto_Release#2592`（id `870115382`）· 角色 id `76520477` · `perms=1073741823`（bit0~29 全开 ⇒ 权限足够） | `--check` 打印 |
| token | 仓库根 `token/kook.txt`（`.gitignore: /token`）—— **绝不提交、输出不打印** | `readToken()` |

- ★**用户最初给的链接是「欢迎大厅」`8320814423228312`（`type=1` 文字频道），实测不是目标**；2026-10-09 用户确认发到「插件发布」。
- ★实测判成员关系**只能用 `guild/list`**：`guild/view` 在机器人**不在服务器**时照样返回频道/角色（用它判成员 = 假绿）；`guild/user-list?filter_user_id=` 会回 `code=40000 该用户不在该服务器内`（**HTTP 200 配 code≠0**，判成功只看 `code`）。
- ★`guild-role/list` 要「管理角色权限」(bit10) ⇒ 纯发布机器人 **403**；角色权限改读 **`guild/view.roles`**。

## 二、一个插件一条帖（按插件分类进各自分区）

用户 2026-10-09 定：「**可以将插件自动发布包对应插件分类内并且接入release流程**」，随后追加「**将子插件都发布**」⇒ **每个插件一条帖**（主插件 1 + 每个子插件各 1），`config.json` 的 `posts[]`：

| 帖 | 分区 | `plugins` | 标题模板 | 封面 / 配图（各自 `./preview`） |
| --- | --- | --- | --- | --- |
| 主插件 | 战斗 `15785972` | `EvalHelp` | `EvalHelp v{ver} 发布（主插件 · 全职业工具）` | `main.png` / main·tools·realmap |
| EH_Damage | 战斗 `15785972` | `EH_Damage` | `EH_Damage v{sub} 发布（增强伤害显示）` | `info.png` |
| EH_DPS | 战斗 `15785972` | `EH_DPS` | `EH_DPS v{sub} 发布（队伍伤害统计）` | `tags.png` / tags·info |
| EH_DebugBox | 战斗 `15785972` | `EH_DebugBox` | `EH_DebugBox v{sub} 发布（图层调试）` | `info.png` |
| EH_Bag | 背包 `15785973` | `EH_Bag` | `EH_Bag v{sub} 发布（整合背包）` | `bank.png` / bank·info |

- 占位符：`{ver}` 主插件版本 · `{sub}` 本条帖第一个子插件版本 · `{names}` 插件名列表。
- ★★**两条守卫（缺一个就会漏发/重发）**：**有插件没被任何帖认领**、或**被两条帖重复认领** ⇒ `main()` 里**直接 exit 2 拒发**（新增子插件时**必须同步 `posts[]`**，拒发就是提醒）。
- 单插件帖的卡片版本行走 `**插件**：<名> <版本>`（`buildCard` 里 `!main && plugins.length` 分支）；含主插件的帖才用 `**版本**：EvalHelp …` + `**子插件**：…`。
- ★子插件**本版无改动**时也要发（用户定「将子插件都发布」）⇒ `notes/<版本>.md` 里该插件的段落写「**本版随 EvalHelp vX.Y.Z 一同发布，插件本身无改动**」+ 一句「这插件是干什么的」（照该插件自己的 `README.md` 首段写）。
- 删掉 `posts[]` ⇒ 退化成「一条帖装全部」（分区取顶层 `category_id`）。

## 三、附件模式 = **link**（★用户 2026-10-09 定，别再改回上传）

用户原话：「**kook 发布不需要真实上传文件.只要附带 gitee 的 release 包连接也可以**」⇒ `config.json` 的 `attach_mode: "link"`：

- **一个字节都不上传**（不调 `asset/create`），帖子里放**下载区**：每个包一行 = 包名 + 角色 + 体积 + **`[Gitee] … ｜ [GitHub] …`**（模板 = `download_base`，占位 `{ver}` / `{name}`）。
- ★★★**KOOK 单文件上限实测 ≈30 MiB**（2026-10-09 探针 `tmp/kook_probe_limit.js`）：**30 MiB 过 / 31 MiB 被 nginx 直接 413**（业务码都到不了）；**30.5 MB 起**由业务层回 `code=40014`。而**主插件包 63.8 MB** ⇒ **本来就传不上去**（首轮真发就是栽在这里：`413 Request Entity Too Large`）。
- ⇒ link 模式还顺手解决了另一个隐患：**本机重建的 zip 与发布页资产字节不同**（实测 主插件 66,903,326 vs 官方 **66,909,370**；EH_DPS 26,374 vs **26,474**）—— 走链接 = 玩家拿到的就是**发布页那一份**，不会出现「同一个版本号两套字节」。
- `attach_mode: "file"` 仍保留：只在**所有包都小于上限**时才可用；脚本对超上限的包会**自动降级为链接**并在日志里点名（`★超 … MB 上限 ⇒ 降级为下载链接`），不会硬闯。

## 四、只发完整版本号的包 + 缺包守卫

用户 2026-10-09 定：「kook 发布文件是**完整版本号的包**」⇒ 只发 `<名>-v<版本>.zip`，**固定名那份（`EvalHelp.zip` 等）不发**（`assets: "versioned"`）。

- 包名与版本**全现读**：`EvalHelp.toc` + `addons/*/*.toc` 的 `## Version` 现算（脚本里**不许写死版本号**）。
- **缺包 / 包名版本 ≠ toc 现读版本 ⇒ exit 2 拒发**，并点出目录里的过期包（防把旧包当新版发；首轮实测就抓到了 `EvalHelp-v1.75.35.zip` vs toc `1.75.110`）。
- 包从哪来：`-Out` 参数可指定输出目录；**KOOK 用的是发布页资产**（link 模式），本地包只用于**核对存在性与体积**——所以本机打包目录不必等于游戏 AddOns 目录。

## 五、更新文案 = 按插件分段的「概要」（★不许流水账）

用户 2026-10-09 定：「kook 更新文案需要总结不要做版本流水账记录」+「概要记录每次插件发布的修改」。

- 文件 = `kook/notes/<版本>.md`，用 **`## 插件名` 分段**；**每条帖只显示它自己那几个插件的段落**（首个 `##` 之前的内容 = 开场，只进第一条帖）。**每个插件 1~2 条要点**。
- 取用优先级（唯一实现 `resolveNotes()` + `notesForPost()`）：① 分段文件 → ② 同文件未分段（整段只进第一条帖，控制台提示建议分段）→ ③ 自动摘要（只抽 CHANGELOG 标题行，**滤掉带版本号的行与内部口吻词**，只进第一条帖）→ ④ `--no-notes`。
- `config.json` 的 `notes_fallback`：`auto`（默认）/ `none`（没手写就干脆不附）。
- ★写法铁律：**只讲玩家能得到什么**；**禁止版本流水**（不写「跨越 v1.75.106 → v1.75.110」）、**禁止内部术语/路径**（`判据`/`闸门`/`探针`/`addons\…\CHANGELOG.md`）。本版区没改动 ⇒ **不写该插件的段落**（版本号仍出现在卡片头部）。

## 五·补、封面与正文配图（用户 2026-10-09 定：「kook 发帖需要添加一张封面.从对应插件的 ./preview 内取一张」+「将对应插件内的 ./preview 内的图片上传」）

- **图源 = 该帖插件自己的 `./preview`**：主插件 `preview/`（8 张）· 子插件 `addons/<名>/preview/`（EH_Bag 2 · EH_Damage 1 · EH_DebugBox 1 · EH_DPS 2）—— **全是 png**（★卡片 `image` 只吃 `image/jpeg` / `image/gif` / `image/png`，别的格式进卡片不渲染）。
- **配置**（`config.json`）：`posts[].cover` / `posts[].images`（写**文件名**，跨该帖各插件的 preview 找；找不到会**点名告警**）；没写就走自动挑（`preview.prefer` 列表 → 再按 mtime 最新；`preview.max_per_post` 上限，默认 3）；`preview.enabled: false` 整体关掉。
- **实现锚点**：`previewDirFor()` / `listPreviewImages()` / `pickPreview()`（选图）+ `doSend()` 里的**上传段**（`asset/create` 逐张上传，超 `max_asset_mb` 的图**跳过并点名**）+ `buildCard(..., images)` 里的 **`image-group` 模块**（1~9 张）+ `thread/create` 的 **`cover`** 参数。
- ★★★**封面必须同时放进正文配图**：`pickPreview()` 会把封面 unshift 进 images —— 依据官方原文「资源上传后默认**不可见**，只有作为**卡片图片元素**发出去才刷新可见状态」；只传 `cover` 参数而不进卡片 = 封面可能不显示。`doSend()` 里 `coverUrl` **只在图片真上传成功后才带**（失败就不带，如实打「⚠ 未带封面」）。
- ★**配额与体积**：图片走 `asset/create`（**不计**消息配额，但吃限流桶）；单张上限同 ≈30 MiB（本次最大 5.6 MB）。实测上传耗时秒级，无需后台任务。
- ★实测（2026-10-09，5 条帖版）：主插件 封面 `main.png`（470 KB）+ 配图 main/tools（5.6 MB）/realmap（5.9 MB）· EH_Damage 封面 `info.png`（2.7 MB）+ 1 图 · EH_DPS 封面 `tags.png`（435 KB）+ 2 图 · EH_DebugBox 封面 `info.png`（6.3 MB）+ 1 图 · EH_Bag 封面 `bank.png`（2.5 MB）+ 2 图。回读 `thread/view` 判据 = **`cover` 非空** 且 **`medias` 里出现同数量的 `type:2`（图片）条目**（5 条帖全满足）。

## 六、两条实测坑（都写进了脚本，别再踩）

1. ★**`asset/create` 返回的 url 会把文件名换成随机串**（`EvalHelp-linktest.txt` → `6ac8440d742da.txt`）⇒ 频道里显示的包名**只来自卡片 `file` 模块的 `title`**（不带 title 玩家看到随机名）。link 模式下不涉此坑，但 `attach_mode:"file"` 时必须给 title。
2. ★**发帖后必须回读 `thread/view` 确认 `status=2`**：`thread/create` 的返回里**创建瞬间可能是 `1`（审核中）**，稍后自动变 `2`。脚本 `waitThreadApproved()` 会轮询 4 次 × 2.5s；仍非 2 就**如实报「需在客户端放行」**（绝不假装成功）。复核 = `--thread-view <帖子id>`；清理 = `--thread-delete <id> --send`。

## 七、命令序列（第 10 步怎么做）

```powershell
# 0) 前提：release 前 9 步已做完（tag 已推、Release 页已建）——因为帖子里有发布页链接
# 1) 写对外概要（按插件分段）——缺了会退化成自动摘要或什么都不附
#    kook/notes/<版本>.md
# 2) 只读自检：token/机器人/频道/分区/权限位
cmd /c "node kook\kook_publish.js --check"
# 3) 演练：拆几条帖、进哪个分区、每个包多大、概要几行（不发任何请求）
cmd /c "node kook\kook_publish.js"
cmd /c "node kook\kook_publish.js --print-card"      # 另看卡片 JSON
# 4) 真发
cmd /c "node kook\kook_publish.js --send"
# 5) 复核
cmd /c "node kook\kook_publish.js --thread-view <帖子id>"
```

- ★本机沙箱怪癖：PowerShell 直接 `node kook\kook_publish.js` 会被拒（`node.exe … Access is denied`）⇒ **一律 `cmd /c "node …"`**；长任务/大输出**重定向到文件再读**（`cmd /c` 的输出直接接 `| Select-Object` 也会被拒）。
- 路径/参数：`--dir <目录>`（包目录）· `--files a,b`（手工指定，跳过 toc 核对）· `--attach link|file` · `--mode card|file`（文字频道发法）· `--notes <文件>` / `--notes-auto` / `--no-notes` · `--json`。
- 外部前置脚本：`tmp/pack_main.ps1 -Out <目录>`（主插件，版本现读 toc，自检 48 模块全在包内 + media 计数互比）· `tmp/pack_subaddons.ps1 -Out <目录>`（子插件）· 只读探针 `tmp/kook_probe_limit.js`（体积上限）· `tmp/kook_fetch_release_assets.js`（从 GitHub Release 取**官方那份**资产并按 `digest` 校验 sha256）。

## 八、安全与配额（别把机器人玩坏）

- **token 绝不打印、绝不提交**；脚本里 `maskToken()` 兜住 `Bot ***`。
- **限流**：每请求打印 `x-rate-limit-remaining/limit/reset/bucket`（实测读接口 `Limit=240`/桶，按接口分桶）；429 按 `Reset+1s` 退避，**连撞 3 次主动中止**（官方：多次超速可能禁用 bot）。
- **消息配额**：`message/create`、`message/update`、**`thread/create`、`thread/reply`** 都计入**账号级 10,000 条/日**（北京时间 12:00 重置）⇒ 一次发布 **5 条帖（每插件一条）**，量级安全，但**别把发布循环跑第二遍**（会重复发帖）。
- **重复发帖的清理**：`--thread-delete <id> --send`（帖 id 由 `--send` 日志与 `--json` 的 `results[].thread_id` 给出）。

## 九、自动化引导（用户 2026-10-09 定：「完善下以上两个信息的自动化引导.欢迎词,公告之类的」+「将意见建议自动进行 AI 问题汇总会加入插件优化队列.做自动化优化流程」）

脚本 = **`kook/kook_guide.js`**（零依赖，默认 dry-run，写操作要 `--send`）；三个去处 = **欢迎大厅**（欢迎词）· **公告与通知**（公告）· **建议反馈 → 优化队列**。

| 做什么 | 怎么触发 | 锚点 |
| --- | --- | --- |
| 新人欢迎词 | **事件驱动**：官方事件 `extra.type = "joined_guild"`（body `{user_id, joined_at}`）经 **WebSocket** 收 ⇒ 发到欢迎大厅（模板里 `{user}` 换成 `(met)id(met)`） | `doListen()` / `doWelcome()` |
| 公告维护 | `--announce [--send]`：首次 `message/create` 存 msg_id，之后**原地 `message/update`** + `message/pin` 置顶（不刷屏、不重发） | `doAnnounce()` |
| 建议 → 优化队列 | ① `--listen` 收到**建议反馈频道**的玩家消息**实时入队**；② `--scan` 回扫最近 50 条补齐（`message/list`） | `enqueue()` / `doScan()` |
| AI 汇总 | 队列落两份：`kook/queue/feedback.json`（账本：msg_id 去重 + `status` + 自动标签）· `kook/queue/INBOX.md`（**AI 直接读**：状态分组 + 标签统计 + 四条处理指引） | `renderInbox()` / `tagOf()` |

- 文案与状态：`kook/guide/welcome.md` · `kook/guide/announce.md` · `kook/state/guide.json`（公告 msg_id · 已欢迎成员 · WS 的 `max_sn`/`session_id`）。
- ★★**公告文案的两条口径**（用户 2026-10-09 追加「**这个能力加入公告,修辞美化一下**」）：
  ① **第 ⑤ 段必须把「建议 → 自动汇总 → AI 归并同主题 → 排期 → 随版本落地 → 发版逐条对账」这条能力讲出来**（玩家视角的一句话链，末尾给「怎么写建议一次命中」的提示）；★**是修辞美化、不是罗列机制名**（别写成「机器人调用 message/list 入队」这种内部话）。
  ② **版本行靠模板占位符 `{version_line}`** 插在末尾说明块里（`announceBody()` 的替换；模板没写占位符就退回「追加在最后」的向后兼容路径）—— 版本号**现读** `EvalHelp.toc` + 各子插件 toc，**不许写死**。
  ③ 更新公告**永远 `message/update` 原地改**（`--announce --send`），**绝不新建**（新建 = 频道刷屏、且 ⑤ 的「不重发」承诺当场破功）；更新后 `--check` 或 `message/view` 回读 `updated_at` 变新 = 生效判据。
- **常驻** = `kook/start_guide.cmd`（双击即跑，日志追加 `kook/state/guide.log`；开机自启 = 快捷方式放 `shell:startup` 或任务计划程序）。
- ★★★**state 文件必须「读-改-写」**（2026-10-09 真机踩到）：监听进程常驻、每个事件都写 `max_sn`，而公告/欢迎是**另一个进程**写同一文件 ⇒ 直接写内存快照会**覆盖对方的 `announce_msg_id`**（实测：公告发成功、账本里却没有 ⇒ 下次发布会**重复新建一条公告**）⇒ 唯一写口 = `saveStatePatch()`（load → merge → save），**绝不再 `saveState(内存快照)`**。判据 = 监听运行中发公告，事后 `--check` 仍能报出 `公告 msg_id`。
- ★实测：gateway `?compress=0` → `HELLO ok`（session）→ 收到 `pinned_message`（sn=1）**证明事件管道通**；★**KOOK 不把机器人自己发的消息推回给它**（发完公告/欢迎词收不到自己的消息事件）⇒ 队列里「排除自己」只是兜底守卫。
- ★欢迎大厅那条「系统通知#0001 … 但他还没有意识到问题的严重性…」是 **KOOK 原生欢迎频道**（服务器设置 `welcome_channel_id` = 欢迎大厅）发的，**与机器人无关**，文案在客户端「服务器设置」里改；我们这条欢迎词与它**并存**（不是替代）——要避免两条欢迎就关掉原生那条。
- 队列状态机：`new`（收到）→ **`triaged`（已做可行性分析，★等你确认）** → `planned`（你确认后才进）→ `done` / `rejected`。★**`triaged` 是必停站**：不许从 `new` 直接跳 `planned`，也不许跳过用户确认开工（用户 2026-10-09 定）。★**发版时对账**：`done` 的条目要在该版 `kook/notes/<版本>.md` 的概要里有对应一句（玩家能看见「我提的被做了」）。
- 命令：`--check`（只读：机器人/三个频道/队列/账本）· `--announce [--send] [--no-pin]` · `--welcome <user_id> [--send]`（补发/测试）· `--scan`（回扫入队）· `--queue`（刷新 INBOX）· `--listen [--dry]`（常驻）。

## 九·补、开发计划收集 + 完成回填闭环（用户 2026-10-09 定：「收集kook 开发计划的触发点在每次我问『kook 有什么优化需求吗?』类似问题的时候.就去收集开发计划.如果某一项计划已经完成的.可以将反馈意见那个帖子标记成已完成.并且配备对应的插件优化版本发布链接」）

★★★**触发点（硬性，不许绕过）**：**用户一问「kook 有什么优化需求吗?」这类问题，第一件事就是跑**
```
cmd /c "node kook\kook_guide.js --plan"
```
（= 现读：先回扫建议反馈频道 → 再列队列 → 再列待回填），**据这份输出作答；不许凭印象、不许凭记忆里上次的清单答**。

| 阶段 | 命令 | 做什么 |
| --- | --- | --- |
| **收集** | `--plan`（内含 `--scan` 回扫；`--no-scan` 可跳过） | 输出 `new / triaged / planned / done / rejected` 分组 + **待回填清单** + 四步「处置四步」 |
| **① 可行性分析（先分析、后动手）** | 手改 `kook/queue/feedback.json`：写 `feasibility{verdict,cost,basis,plan}`，status → `triaged` | ★★★**分析必须先做、并按项目铁律做**：**先核 API 存在性**（`api_*.html` / 客户端 exe 符号 / 官方文档）→ 需要才**写探针** → 判真伪与**代价**（能不能做、大概改哪几个文件、判据是什么）。**报障类不许直接改代码** |
| **② ★等用户确认（硬闸门）** | —— | ★★★用户 2026-10-09 定：「**在获取需求的时候先分析验证修复可能性.待我确认**」⇒ **分析完就停下来问用户**：【已分析 · 等你确认】那一组 = 等点头的清单。**没点头不许把 status 改成 `planned`、更不许动代码**；`--plan` 的「处置四步」第 2 条写着这条 |
| **③ 实施** | 用户点头后 status → `planned`，再改代码 | 走项目常规：`node luacheck.js` + `node sync_game.js`（按需补 harness/结构钉） |
| **完成回填** | `--done <msg_id> --version <版本> [--note "一句话做了啥"] [--thread <帖子id>] --send` | **三件一起做**：① 玩家原帖加 ✅ 反应 ② 回复原帖（`quote=msg_id`）带**版本发布链接** ③ 队列 `status=done` + `notified=true` + `note` |
| **补漏** | `--backfill --send` | 扫所有 `done && !notified` 批量补（幂等） |
| **刷新** | `--queue` | 重写 `kook/queue/INBOX.md`（下一个会话直接读；**处理指引第 1~2 条就是这道闸门**） |
| **演练** | `--simulate @tmp/xxx.txt --send` | 机器人**替玩家**在建议反馈频道发一条需求并**直接入队**（`source=sim`）—— 破例点：**绕过「排除机器人自己」的过滤**（否则自己发的消息进不了队列）；`@文件` 写法用于避开 PowerShell 引号地狱 |

- ★★**重复执行守卫**（2026-10-09 演练实测发现）：`--done` 的**反应**是幂等的（先查 `reaction-list`），但**回复不是** ⇒ 同一条再跑一次会在玩家帖下**多一条重复回复** ⇒ 现已加守卫：**队列条目 `notified=true` 时默认跳过**（要再发一次得显式 `--force`）。判据 = 连跑两次 `--done --send`，第二次只打印「已回填过 ⇒ 跳过」且频道消息条数不变。

- ★★**版本链接的来源优先级**（`versionLink()`）：① `--thread <帖子id>` 显式给 → ② **`kook/state/releases.json`**（`kook_publish.js --send` 成功后会**自动记账**：版本 → 各帖 `id`/标题/包名）→ ③ 退回 GitHub/Gitee 发布页链接。
- ★★**「反馈意见那个帖子」= 建议反馈频道里玩家提建议的那条消息**；标记手法 = **给那条消息加 ✅ 反应**（`message/add-reaction`，emoji = **`[#9989;]`** = U+2705 的十进制码 —— 2026-10-09 实测 `add-reaction` / `reaction-list` / `delete-reaction` 全通），**不是改消息**（别人的消息改不了）。
- ★**幂等两条**：`--done` 先查 `reaction-list` 里有没有机器人自己（有就跳过加反应）；`notified` 一旦为真就不再回填（`--backfill` 只挑 `!notified`）。
- 队列条目可写 `ver`（这条建议由哪个版本落地）⇒ `--backfill` 按它取值；没写就用现读的 `EvalHelp.toc` 版本。

## 十、现状与欠账

- ✅ 2026-10-09 全链路真机跑通：`--check` 全绿 · 测试帖（2 个附件）真发 → 回读 `status=2` → 用户确认附件可下载 → 删除；link 模式卡片（下载区 + 按插件分段概要）已离线验证。
- ✅ **2026-10-09 v1.75.110 正式发布完成（现役 5 条帖，一个插件一条，含封面 + 配图）**：

| 帖 | 分区 | `thread_id` | 封面 | 配图 | 状态 |
| --- | --- | --- | --- | --- | --- |
| EvalHelp v1.75.110（主插件 · 全职业工具） | 战斗 | `146705925250482432` | `main.png` | 3 张 | `status=2` |
| EH_Damage v0.2.36（增强伤害显示） | 战斗 | `146705935987901440` | `info.png` | 1 张 | `status=2` |
| EH_DPS v0.2.5（队伍伤害统计） | 战斗 | `146705946071007744` | `tags.png` | 2 张 | `status=2` |
| EH_DebugBox v0.4.0（图层调试） | 战斗 | `146705957898945536` | `info.png` | 1 张 | `status=2` |
| EH_Bag v0.3.42（整合背包） | 背包 | `146705970012095232` | `bank.png` | 2 张 | `status=2` |

  · 频道 https://www.kookapp.cn/app/channels/7071527711947717/5336773639081280 ；发布日志 = `tmp/s5.txt`。
  · ★**前两轮的两对帖都已 `thread/delete` 删除**（先是无封面版 `146705388144689920`/`146705396080313344`，再是「主插件+战斗类」汇总版 `146705650305466624`/`146705664968754176`）—— 用户每次改口径都**删旧发新**，频道里不留同版重复帖。
  · 清理/复核 = `--thread-delete <id> --send` / `--thread-view <id>`。
- ⏳ **未验证**：帖子主楼对**超长文案**的截断阈值（当前卡在 `notes_max_chars`，v1.75.110 实测 10 行无恙）· Gitee 直链是否需要验证码（网页下载弹「请输入验证码，防止盗链」**仅对浏览器**；`/releases/download/…` 直链是否受限未实测 —— ★发布后建议让用户点一次 Gitee 链接确认）· 帖子主楼的**下载链接是否可点**（卡片 `kmarkdown` 的 `[文字](url)` 在帖子主楼里的渲染未亲眼确认）· **封面在客户端列表里的裁切效果**（KOOK 客户端什么样未亲眼确认；`thread/view` 只能证明 `cover` 字段非空）。
- 未决：`kook/02-待实测清单.md` 里的 T1（频道事件投递范围）与其后各项仍属「官方未文档化、未实测」。
- ✅ **2026-10-09 自动化引导已上线（§九）**：公告已发并置顶（`msg_id=badb147b-4175-4d7f-acbd-9bcfaad4c9af`，频道「公告与通知」；**含第 ⑤ 段「建议会被自动汇总进优化队列」**，修辞版）· 优化队列已建（`kook/queue/`，当前 0 条 —— 该频道本来就空）· **WebSocket 事件管道实测通**（收到 `pinned_message`）· 常驻入口 `kook/start_guide.cmd`。
- ✅ **2026-10-09 开发计划闭环已上线（§九·补）**：`--plan`（收集）· `--done`（原帖加 ✅ `[#9989;]` + 回复带版本链接 + 队列记账）· `--backfill`（批量补）· `--simulate`（演练入口）**全路径已端到端真实跑通**：演练需求 `msg_id=83c151e3-9c4b-4c6d-9218-7e898bab5f6d`（内容 = 工具箱「消耗品助手」+ 宠物喂食助手图标要支持 Ctrl+滚轮缩放）→ 入队（标签 功能请求/体验·界面）→ 定性 `planned`（结论：**可行**，项目内已有同款配方 = EH_DPS 的 Ctrl+滚轮整窗缩放走几何重建、禁用 `SetScale`）→ `--done --version 1.75.110` → 频道侧回读确认 **✅×1 反应 + 引用回复（带 v1.75.110 主插件帖链接）** 都在；再跑一次 `--done` **被守卫挡下不再重复回复**。
  · ⏳ 该条目前是**流程演练**标记（note 里写明「真落地时会换成实际改动说明」）⇒ **真要实现这个需求时**：改 note 为实际改动说明 + `--force` 重发一次回复（或直接把队列条目当待办推进，见 §九·补 的 `planned` 阶段）。
  · ★**2026-10-09 收尾（用户定「删除」）**：模拟那条已从队列移除；频道里那条**演练回复 + ✅**也**已删除**（`--msg-delete <消息id> --send`，一次可传多条；✅ 反应随原帖被删一起消失），另删掉机器人自己那条重复帖 —— 建议反馈频道**现只剩玩家那条真需求帖**。★代价如实记：**只能删自己发的**（玩家的原帖删不了）；删完正确状态 = 真需求帖**没有任何 ✅**（此前 83c151e3… 那条演练帖是被删掉的，别再当成「已回填」）。
- ⏳ **队列现存 1 条**：`msg_id=e9579fd6-44dc-4397-b2ad-b5075c6c7e58`（玩家 `eval` 实提，10:17；内容 = 工具箱「消耗品助手」+ 宠物喂食助手图标要支持 Ctrl+滚轮缩放）状态 = **`planned`**（用户 2026-10-09 点头「做」）· **代码已实现（1.75.111：两处图标 Ctrl+滚轮 16~64 调档 + 角色级存档 + 三语提示）** ⇒ ⏳ **待 release 走完第 10 步后回填**：`node kook\kook_guide.js --done e9579fd6-44dc-4397-b2ad-b5075c6c7e58 --version <新版> --send`（**必须等帖子发出来**才有 `releases.json` 里的版本链接；没链接就回填 = 破「配备发布链接」这条口径）。这也是**监听「实时入队」第一次真机见效**（事件日志 `extra.type=9 → 建议入队（队列共 2 条）`）。
- ⏳ **仍未真机验证**：**真人加入服务器时的欢迎词**（`joined_guild` → 欢迎大厅发帖）—— 需要真的有人进服才能验；补测手段 = `node kook/kook_guide.js --welcome <对方KOOK用户id> --send`（手工发一条），或等下一个新成员时看 `kook/state/guide.log` 与欢迎大厅。
