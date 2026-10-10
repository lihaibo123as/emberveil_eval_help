# Emberveil 官方插件平台 · 发布与编辑流程

> 独立记忆体（与 `kook/CLAUDE.md` 同一档：**子系统自身管理的记忆**，宿主 `CLAUDE.md` 只留指针）。
> 实测时间 **2026-10-10**，操作人账号 `lihaiboas1`（平台显示名 `LIHAIBOAS1`）。
> 站点 = Laravel + Livewire 渲染（按钮全是 `wire:click`，**不是普通表单提交**）。

## 一、入口 URL

| 用途 | URL |
| --- | --- |
| 插件市场（公开） | `https://emberveil.org/wiki/addons` |
| **我的插件**（自己发布的清单） | `https://emberveil.org/wiki/addons/mine` |
| 提交插件（新建，空表单） | `https://emberveil.org/wiki/addons/submit` |
| 打包指南 | `https://emberveil.org/wiki/addons/guide` |
| 某个插件详情页 | `https://emberveil.org/wiki/addons/<slug>` |
| **编辑某个插件** | `https://emberveil.org/wiki/addons/<slug>/edit` |

★ 登录后导航栏「资料」下拉里才会出现 **My Addons / My Profile**（未登录看不到）。

## 二、登录与「免登录」凭据

- 凭据文件（**全部在 `token/`，该目录已被 `.gitignore` 忽略，绝不入库**）：
  - `token/emberveil_login.json` —— 账号 / 密码 / 登录步骤 / 判据（本文件是操作手册）
  - `token/emberveil_cookies.json` —— 登录 Cookie 备份（`browser_auth restore` 可直接吃这个数组）
- **登录三步**（实测约 10 秒，全程无需人工）：
  1. 打开 `https://emberveil.org/login`
  2. `browser_fill` 填 `input[placeholder="Enter your username"]` / `input[placeholder="Enter your password"]`
  3. 等 1~2 秒 ⇒ `input[name="cf-turnstile-response"]` 的 `value` 长度变成 **~816** ⇒ 点文本为 `LOG IN` 的按钮
- **登录成功判据**：导航栏出现 `LIHAIBOAS1` + 出现 `捐助/Donate`，并且不再有 `Login / Register`。
- ★ **Cloudflare Turnstile 是隐形自动过**：本机会卡在「正在验证…」几秒，**不要**当成人工验证去叫人点；轮询令牌长度即可（首次约 8 秒、第二次 1 秒）。
- ★★ **登录态本身会落盘在浏览器 profile**：`%APPDATA%\dsh-builtin-browser-host\Network\Cookies`，
  实测**关掉标签页 + `Stop-Process electron` 之后重启浏览器仍保持登录**（3 条 Cookie 都是 `is_persistent=1`）。
  所以「免登录」的第一层保障 = **别删这个 profile**；第二层 = `token/emberveil_cookies.json` 兜底 restore。
- Cookie 三条（2026-10-10 导出）：`emberveil-session`（httpOnly，**约 2 小时过期**）· `remember_account_<hash>`（**约 1 年**，免登录主力）· `XSRF-TOKEN`。
- ★ **导出 Cookie 的复算方法**（profile 被清空时重建）：
  1. 关掉浏览器（`Stop-Process -Name electron -Force`）⇒ `Cookies` 数据库才不锁
  2. 复制 `%APPDATA%\dsh-builtin-browser-host\Network\Cookies`
  3. DPAPI 取密钥（`Local State` 的 `os_crypt.encrypted_key`，剥掉 5 字节 `DPAPI` 前缀 → `ProtectedData::Unprotect`）—— ★**要用 `powershell.exe`（5.1）**，`pwsh`(7) 里没有 `System.Security.Cryptography.ProtectedData` 类型
  4. `node:sqlite` 读库 + `aes-256-gcm`（`v10` 前缀：nonce 3~15、tag 末 16 字节）解密
  5. 脚本 = `tmp/emberveil_cookie_export.js`（★**SQL 里大整数列必须 `CAST(... AS TEXT)`**：`expires_utc`/`creation_utc` 超出 JS 安全整数，直选会抛 `ERR_OUT_OF_RANGE`）

## 三、我的插件清单（2026-10-10 · 5 个，全部 `已通过` + `已公开`）

| 显示名 | slug | 分类 | 下载 | 点赞 | 仓库点击 |
| --- | --- | --- | ---: | ---: | ---: |
| **EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料** | `addon` | 战斗 | 733 | 15 | 49 |
| EvalHelp -> EH_Damage · 增强伤害显示（浮动战斗信息） | `evalhelp-eh-damage` | 战斗 | 19 | 3 | 1 |
| EvalHelp -> EH_Bag · 整合背包 | `evalhelp-eh-bag` | 背包与物品栏 | 12 | 2 | 3 |
| EvalHelp -> EH_DPS · 队伍伤害统计（自娱自乐版） | `evalhelp-eh-dps` | 战斗 | 9 | 2 | 1 |
| EvalHelp -> EH_DebugBox · 图层调试 | `evalhelp-eh-debugbox` | 其他 | 7 | 3 | 2 |

（列表按下载量排序；各行"浏览量"均为 0。）

★ 主插件 slug 是 **`addon`**（平台默认 slug，历史遗留），不是 `evalhelp`。

## 四、编辑页表单字段（全量，`.../<slug>/edit`）

| 区块 | 控件 | 说明 / 约束 |
| --- | --- | --- |
| 顶部 | 文案 | 「可随时保存草稿；准备好后再**申请发布** ⇒ 由管理员审核，**当前公开版本一直保留**直到新版本通过」 |
| 预览 | 只读 | 实时渲染 markdown + 名称/描述长度计数（名称 `34/60`、描述按字符） |
| 分类 | `<select>` | 13 类：单位框体 / 动作条 / 战斗 / 地图与小地图 / 背包与物品栏 / 聊天 / 提示信息 / 专业技能 / 任务 / PvP / 界面与框体 / 其他 / 数据包 |
| 版本 | text | 占位 `例如 1.2.0 · 适用于 1.12.1`；★ 由下载链接**自动填入** |
| Git / 仓库链接 | url | **域名白名单**：`github.com` · `gitlab.com` · `bitbucket.org` · `codeberg.org` · `git.sr.ht` |
| **下载链接（必填）** | url | `https://…/Addon-1.2.0.zip`；**必须带版本号**（打了 tag 的发行版或文件名带版本），**严禁 `…/archive/HEAD.zip`** |
| 图标（推荐） | file | 不填则条目显示名称首字母 |
| 封面图（可选） | file | |
| 截图 | file ×最多 10 | 新图追加进列表，每张图角上有 `✕` 可移除 |
| 内容（多语言） | tab | `English` / `Español` / `Русский` / **`简体中文 • (主要)`** —— 先填主要语言再加翻译 |
| 插件名称 | text | **上限 60 字** |
| 描述 | textarea + Markdown 工具条 | `**加粗**` `*斜体*` `` `代码` `` `- 列表` `> 引用` `[文字](链接)`；前 ~160 字进 SEO/分享摘要 |
| 常见问题（可选） | 可重复行 | `wire:click="addFaq"` |
| 更新日志（可选） | 可重复行 | `wire:click="addChangelog"` |

## 五、动作（Livewire action 名 = 自动化锚点）

| 按钮 | `wire:click` | 语义 |
| --- | --- | --- |
| 保存草稿 | `saveDraft` | 存草稿，**不改公开版本** |
| 申请发布 | `requestPublish` | 提交管理员审核，旧公开版本继续生效直到通过 |
| 切换语言 | `switchLocale('en'\|'es'\|'ru'\|'zh_CN')` | |
| 删除（在我的插件页） | `deleteAddon(<id>)` + `wire:confirm` | ★**不可撤销**（连同全部版本/图片/点赞），弹确认框 |

## 六、我的插件页布局

每行 = 名称 + `已通过` / `已公开` 徽章 + 三个动作 **查看 / 编辑 / 删除** + 统计 `浏览量 · 仓库点击 · 下载 · 点赞`。
页面右上 = `插件`（回市场）· `提交插件`。顶部 = `我的插件` 标题。

★★**两个徽章位置 = 两件事，别混读**（2026-10-10 二轮实测）：
- **第一格 = 审核状态**（`草稿` / `待审核` / `已通过`）—— ★★★**`保存草稿` 会把 `待审核` 打回 `草稿`**（见 §八 铁律 6）。
- **第二格 = `已公开`**（线上有没有正在生效的公开版本）—— **新条目从来没有过 ⇒ 这一格不出现**（EH_Mail 就只有「草稿」两个字）。
⇒ 读法：**「草稿 + 已公开」= 线上还是旧版、新草稿没生效**；**「待审核 + 已公开」= 已经交上去等管理员**；**只有「草稿」= 从未发布过**。

## 七、用共享浏览器操作时的注意事项

1. **只读优先**：`保存草稿` / `申请发布` / `删除` 都会改线上数据 ⇒ 排查/查看阶段**一次都别点**。
2. 打开 `/edit` 时会**再报一次 Turnstile**（隐形，等几秒即可），页面元素在 `browser_open` 返回时可能还没渲染 ⇒ **等 4~6 秒**再 `browser_snapshot`。
3. 文件上传（图标/封面/截图）走 `<input type=file>`，共享浏览器**没有文件选择器接口** ⇒ 需要上传图片时让用户手动拖，或先确认工具是否支持。
4. `browser_fill` 对 Livewire（受控输入）有效；但 **Livewire 的 wire:model 需要 `input` 事件**（`browser_fill` 已发），改完值**不必手动触发**、直接点按钮即可。
5. 平台没有公开写 API（未验证）⇒ 自动化一律走 UI；**发布/编辑的自动化脚本若要长期用，锚点用上面那批 `wire:click` 名**（比中文按钮文本稳）。
6. ★★★**本页是 Livewire v3；写字段有两条路，只有第二条可靠**：
   - **不可靠 = 直接改 DOM**：`version` 与 `downloadUrl` 两个输入框用的是 **`wire:model.blur`**（只在**真实失焦**时才把值提交给组件）⇒ 用 `browser_fill` / `el.value=… + input/change` 填完**不触发 blur**，
     值**根本没进服务端模型**；此时点 `保存草稿` 会**照常回「草稿已保存。」并跳回 `/wiki/addons/mine`** —— 这是最阴的一类**假成功**（实测：主插件/EH_Bag/EH_Damage/EH_DebugBox 的版本与下载链接**四次都没写进去**，
     而同一份表单里的描述（普通 `wire:model`，随下一次请求一起发）**写进去了** ⇒ 线上出现「描述已是新版、版本还是旧版」的半更新状态）。
     手动 `el.focus(); el.value=…; input/change; el.blur()` **也无效**（实测 `queuedUpdates` 仍为空）。
   - ★★★**可靠 = Livewire JS API 一次性提交**（`Livewire` 是全局对象；组件对象 = `Livewire.all()` 里 `name === 'wiki.addons.submit'` 那个）：
     ```js
     var c = Livewire.find('<组件 id>');          // 或遍历 Livewire.all() 按 name 取
     c.set('version', 'v1.75.117', false);        // 第 3 参 false = 只改本地模型、不发请求
     c.set('downloadUrl', '…', false);
     c.set('gitUrl', '…', false);
     c.call('saveDraft');                          // 全部字段就位后，唯一一次请求
     ```
     ★`c.get(name)` 可在 save 前**逐字段复核**（这一步就是「完整数据表达填充」的判据）；★**`set(..., false)` 之后 `queuedUpdates` 会是空的**，别拿它当没生效的证据，以 `c.get()` 为准。
   - ★★**两个时序坑**：① 打开 `/edit` 后**等 4~6 秒**再用 JS API —— 组件刚建出来时 **`get/set/call` 还没挂上**（报 `c.get is not a function`），等一会儿再试即可；
     ② 每次保存成功会**跳回 `/wiki/addons/mine`**，要继续下一条得重新进 `/edit`（本地模型不跨页）。
   - ★★**保存后必须复核**：重新打开 `/edit` 读 `c.get('version')` / `c.get('downloadUrl')`，或读 `wire:snapshot` 里 `data.version` —— **只看那句「草稿已保存。」会骗人**。

## 八、与本地 release 流程的关系（★★★ 2026-10-10 用户定案）

**平台环节 = release 的最后一步（第 11 步），必须等前面 9+1 步全部走完再动手**
（用户原话：「**release 流程全部走完最后进行发布平台流程**」）—— 因为条目里要填的下载链接指向**刚刚发布的那个 tag**，提前做就会指向一个还不存在的包。

★★★**三条铁律**：

1. **只保存草稿 —— `保存草稿` 是 AI 能做的最后一步；`申请发布` 由用户自己点**
   （用户 2026-10-10 原话：「**平台发布请保存草稿. 发布由我来点**」）。
   ⇒ AI **绝不点 `申请发布`**，做完就停下来把「哪几条存了草稿、草稿里写的是什么」报给用户。
2. **出现限流就终止等待、继续后续流程**（用户 2026-10-10 原话）。
   平台报错原文 = **「保存过于频繁，请几分钟后再试。」** ⇒ ★**不要反复点击重试**（重复点击会刷新窗口、越等越久）；
   记下哪一条没存上，**继续干别的**，回头再补。
3. **版本变了的插件才更新**（新条目必做）；口径 = 在 `/edit`（新条目走 `/submit`）里改「**版本 + 下载链接**」⇒ `保存草稿`。
4. ★★★**「完整数据表达填充之后，再点一次保存 —— 不要太频繁」**（用户 2026-10-10 原话：「**平台发布编辑插件要完整数据表达填充之后点保存. 不要太频繁**」）。
   ⇒ 顺序**必须**是：**先把这一条要改的字段全部就位**（版本 + 仓库链接 + 下载链接 + 描述/名称里任何要跟着改的），**逐字段复核 `c.get()` 全对了，才发唯一一次 `saveDraft`**；
   **一条条目只保存一次**，多条条目**之间要拉开间隔**（实测连着存会撞「保存过于频繁，请几分钟后再试。」）。
   ★**反面教材就是本轮的实况**：早前「改一个字段→点一次保存」的补丁式做法，四次都**假成功**（返回「草稿已保存。」却没进库），线上留下「描述已更新、版本还是 v1.75.110」的半状态；
   后来改用「一次填齐 + 一次 `c.call('saveDraft')`」，**主插件的 `v1.75.117` + 新下载链接一次就落库**（复核读回确认）。
   ★与铁律 2 的关系：**限流不等于可以反复补点** —— 撞了就**停手**，把「哪几条还没存」记下来，**拉长间隔**再一条一条来。
5. ★**每次保存后必须回读复核**（`/edit` 里 `c.get('version')` / `c.get('downloadUrl')`，或 `wire:snapshot` 的 `data.version`）——「草稿已保存。」**不能作为落库证据**（原因见 §七.6 的 `wire:model.blur` 坑）。
6. ★★★**「保存草稿」会把已经提交的「待审核」打回「草稿」**（2026-10-10 二轮实测）：改前 主插件 / EH_Bag / EH_Damage 三条徽章是 **待审核**，我逐条保存草稿后**六条全变成「草稿」**。
   ⇒ **操作顺序铁律 = 全部条目都改完、复核无误，最后才逐条点「申请发布」**；**申请发布之后再保存草稿 = 把这次申请作废**（得重新点）。
   ⇒ 交付时必须明确报「哪几条现在是草稿、需要你点申请发布」，**不能假设之前的申请还有效**。
7. ★★**「子插件版本/链接」的完整核对法（一条命令级、纯读）**：
   - **逐条字段**：对每个 slug `fetch('/wiki/addons/<slug>/edit')` → 取含 `downloadUrl` 的那个 `wire:snapshot` → 解 HTML 实体 → `JSON.parse` →
     `data.version` / `data.category` / `data.gitUrl` / `data.downloadUrl`；**标题与描述在 `data.locales[0][<语言>][0]`**（不是 `data.name`！形状 = `locales[0].zh_CN[0] = {title, description, faq, changelog}`）⇒ 用 `(box.title||'').length` / `(box.description||'').length` 判断「有没有被保存操作清掉」。
   - **链接可用性**：下载直链用 `curl.exe -s -I -L -x http://127.0.0.1:10809 <url>` 看**最终 200 + `Content-Length` 与本地包一致**（`302` 是 GitHub 正常跳转，**必须带 `-L`**）；仓库链接同样探 200。
   - ★**仓库链接的两种合法形态**：主插件 = **仓库根**（`…/emberveil_eval_help.git`）；子插件 = **`…/tree/<ref>/addons/<名>`**。
     `<ref>` 可以写 **tag**（`v1.75.117`，我写的）或**审批时冻结的 commit**（如 EH_DPS 曾钉在 `7ecf17a`）—— ★**平台审批时会把它改写成冻结 commit**，
     所以看到 commit 形态**不一定是过期的**；要判「是不是旧版」得用 git 比一下：`git diff --stat <commit> v1.75.117 -- addons/<名>`（空 = 内容一致、可不动）。
8. ★★★**子插件「只在有更新的时候才保存草稿」**（2026-10-10 用户原话：「**平台发布子插件只在有更新的时候才保存草稿. 记住**」）。
   **判据 = 「这个子插件自己有没有更新」，不是「宿主版本变了没有」**——一次 release 里子插件目录**一个字节都没动**的，**连草稿都不要保存**（平台条目原样放着）。
   · **怎么判**：`git diff --stat <该条目上次发布时所钉的 commit> <本次 tag> -- addons/<名>` ⇒ **空 = 没更新，不碰**。
   · ★★**只有「非代码差异」也算没更新**（别自己给自己找活干）：只动了 `.toc` 的 `## Title` 改名 / `README.md` / `CLAUDE.md` / `preview\` 截图 ⇒ 玩家装到的东西**功能一字未变** ⇒ **按「没有更新」处理**（例：EH_DPS 与 EH_DebugBox 在 1.75.117 这一轮 `EH_DPS.lua`/`EH_DebugBox.lua` **零改动**，各只有 toc 标题改名 + 文档 + 预览图）。
   · **为什么这条重要**（代价是双份的）：① **保存草稿会把「待审核」打回「草稿」**（铁律 6）⇒ 白折腾用户重新点一次；② 老 tag 的下载链接**只要那个 Release 页还在就仍然可用**（我们 keep 5）⇒ 没更新就没有非改不可的理由。
   · **必须更新的例外**：子插件**代码/资源确实变了**（如本轮 EH_Bag `0.3.27→0.3.48`、EH_Damage `0.2.14→0.2.46`、EH_Mail 新条目）⇒ **必须更新**（否则玩家装到旧包、看不到新功能）。
   · ★★**配套：注意「tag 保留窗口」这把悬着的刀** —— 条目里写的下载链接指向某个 tag，而 **`rel_releases_prune.js --keep 5` 会把老 tag 的 Release 页整页删掉**（附件一起没）⇒ 一旦那个 tag 快被挤出保留窗口，**这一条就属于「有更新理由」**（哪怕代码没动），要顺带把链接升到新 tag，否则**链接变 404**。
     ★这一条要在**每次发布收尾盘点保留窗口**时一起看：`node tmp/rel_gitee_quota.js` 只读配额、Release 列表可直接读两端 API（`/releases`）⇒ 列出「平台条目引用的 tag」∩「即将被删的 tag」。

### 已登记的更新口径（★2026-10-10 二轮**回读复核后的实际落库值**）

> ★★ 下表是**从 `/edit` 的 `wire:snapshot` 里读回来的真实值**（6 条全部复核过），不是「打算写什么」。

| 条目 | 版本字段（实际落库） | 分类 | 下载链接 |
| --- | --- | --- | --- |
| 主插件 `addon` | `v1.75.118` | combat 战斗 | `…/releases/download/v1.75.118/EvalHelp.zip` |
| `evalhelp-eh-bag` | `v1.75.117` | bags 背包与物品栏 | `…/v1.75.117/EH_Bag.zip` |
| `evalhelp-eh-damage` | `v1.75.117` | combat 战斗 | `…/v1.75.117/EH_Damage.zip` |
| `evalhelp-eh-dps` | `v1.75.117` | combat 战斗 | `…/v1.75.117/EH_DPS.zip` |
| `evalhelp-eh-debugbox` | `v1.75.117`（原停在 `v1.75.106`） | misc 其他 | `…/v1.75.117/EH_DebugBox.zip` |
| `evalhelp-eh-mail`（新条目） | `v1.75.117` | bags 背包与物品栏 | `…/v1.75.117/EH_Mail.zip` |

新条目的其它字段：**标题 = `EvalHelp -> EH_Mail · 邮箱增强`** · 仓库链接 = `…/tree/v1.75.117/addons/EH_Mail`。

★★★**版本字段里的 `_<子版本>` 后缀会被平台归一化掉**（2026-10-10 二轮实测）：写入 `v1.75.117_0.3.48`（走 JS API 的 `set`、连 DOM 都没碰）后回读得到的是 **`v1.75.117`**
⇒ **平台在保存时按「下载链接里的 tag」重算版本**（页面顶部那句「★ 由下载链接自动填入」就是它）⇒ **版本字段不必手写子版本**，写了也留不住（老档里那个 `v1.75.110_0.3.42` 属历史遗留，不是现行写法）；**要表达子插件版本就写进描述正文**。

### ★★★ 两个表单操作坑（2026-10-10 实踩）

1. **`分类` 下拉与 `插件名称` 输入框用 `browser_fill` 的 label 匹配会失败**（`field not found`）
   ⇒ 改用 JS 直接写：`select` 要**按 option 文本找到它的 `value`** 再设（`背包与物品栏` 的真实 value 是 `bags`）。
2. ★★★**用 JS 改动会触发 Livewire 重渲染，可能把别的字段的模型状态清掉**
   ⇒ 实测症状 = 保存时报 **`The download url field is required.`**（DOM 里明明有值，服务端状态却是空）
   ⇒ **正解 = 改完 JS 之后再单独写一次「下载链接」，紧接着立刻点保存**（中间别再碰别的字段）。
   ★最稳的路子：能用 `browser_fill` 的字段一律用它（它发原生 setter + `input`/`change`，实测稳定），
   只有 label 匹配不到的才补 JS。

---

## 九、已发布条目的实际形态（2026-10-10 实测）

★ 下载/仓库按钮都是**站内跳转**（`…/go/download`、`…/go/git`，点击计数就记在这里），真实地址要读 302 的 `Location`。
★ 复算脚本 = `tmp/emberveil_go_probe.js`（`fetch(..., {redirect:'manual'})`，**不下文件**）。

| 条目 | slug | 版本 | 分类 | 包大小 | 真实下载直链（`/go/download` →） |
| --- | --- | --- | --- | ---: | --- |
| EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料 | `addon` | `v1.75.118` | 战斗 | 64.26 MB | `…/releases/download/v1.75.118/EvalHelp.zip` |
| EvalHelp -> EH_Damage · 增强伤害显示（浮动战斗信息） | `evalhelp-eh-damage` | `v1.75.117` | 战斗 | 464.3 KB | `…/releases/download/v1.75.117/EH_Damage.zip` |
| EvalHelp -> EH_Bag · 整合背包 | `evalhelp-eh-bag` | `v1.75.117` | 背包与物品栏 | 224.0 KB | `…/releases/download/v1.75.117/EH_Bag.zip` |
| EvalHelp -> EH_DPS · 队伍伤害统计（自娱自乐版） | `evalhelp-eh-dps` | `v1.75.117` | 战斗 | 25.9 KB | `…/releases/download/v1.75.117/EH_DPS.zip` |
| EvalHelp -> EH_DebugBox · 图层调试 | `evalhelp-eh-debugbox` | `v1.75.117` | 其他 | 127.6 KB | `…/releases/download/v1.75.117/EH_DebugBox.zip` |
| **EvalHelp -> EH_Mail · 邮箱增强** | `evalhelp-eh-mail` | `v1.75.117` | 背包与物品栏 | 1003 字描述 | `…/releases/download/v1.75.117/EH_Mail.zip` |

★★ 上表 = **2026-10-10 二轮回读复核后的实际值**（读法：`fetch('/wiki/addons/<slug>/edit')` → 取第 2 个 `wire:snapshot` → `data.version` / `data.downloadUrl`，**一次拉齐 6 条**，纯读）。
★★★ **2026-10-10 三轮回读（v1.75.118）**：**只动主插件一条**（子插件本轮代码零改动 ⇒ 按 §八 铁律 8 **连草稿都没存**，其余五条原样）。写入口径 = 一条 `c.$wire.set(...)`（`version` / `downloadUrl` / `gitUrl`）+ **描述里「自动丢弃指定物品」那一格改写**（`（同上）` → 新增图标/背包选择/每秒主动检查/红色日志的说明，3381 → **3497 字**），**一次 `saveDraft`**；**回读 `c.$wire.get(...)` 确认** `version=v1.75.118` / `downloadUrl=…/v1.75.118/EvalHelp.zip` / 描述含新串且 `（同上）` 已消失。★读法注意：本轮 `Livewire.all()` 拿到的组件**要 15~20 秒后**才挂上方法，且**方法在 `c.$wire.get/set/call` 上**（`c.get` 是 undefined）—— 两种形态都试，别当成「页面坏了」。
★ 一轮的旧值（全部 `v1.75.110`，EH_DebugBox `v1.75.106`）= **假成功留下的半状态**，见 §八 铁律 4 的反面教材。

仓库直链（`/go/git` →）：主插件 = `https://github.com/lihaibo123as/emberveil_eval_help.git`；
子插件 = `…/tree/<审批时冻结的 commit>/addons/<名>`（EH_Bag `3b19ae01…` · EH_DPS `7ecf17a3…` · EH_DebugBox `1515fbe7…` · EH_Damage `d930b713…`）。

★ **要点（下次发布前必看）**：
1. 平台用的是**固定名包**（`EvalHelp.zip` / `EH_Bag.zip` …，不带版本号）—— 与本地 release 上传的「两份」对得上；版本号由**链接里的 tag** 决定，不由文件名决定。
2. ★★**「版本没写进去」不会报错**：写口是 `wire:model.blur`/平台归一化两个坑叠加（§七.6 + §八铁律 4）⇒ **每次保存后必须回读复核**，别信那句「草稿已保存。」。
3. **版本字段是单版本**（`v1.75.117`）：平台保存时按下载链接的 tag 重算 ⇒ `_<子版本>` 后缀留不住（§八 表下那段）。
4. **EH_Mail 已于 2026-10-10 二轮补建**（新条目，`evalhelp-eh-mail`，分类 背包与物品栏）⇒ 「我的插件」现为 **6 条**。
5. 页面上的 **SHA-256 + 字节数由平台在审批时冻结**（GitHub Release 附件直接读 GitHub 记录的哈希）；「下载已在审批时冻结到该提交」—— 所以**审核通过后绝不能替换同 tag 的同名包**。

★ 页面里各段的有无（现状）：**只有主插件有「更新日志」**（列到 `v1.75.110` / `v1.75.106` 两条里程碑，**尚无 1.75.117 那条**）+ **评论 26 条**（作者可回复/编辑/删除）；**子插件页一律没有更新日志、也没有常见问题**；六条都有「简介」与截图区。
⏳ **待办（可选）**：主插件的「更新日志」若要补一条 `v1.75.117` 里程碑 —— 需点 `添加`（`addChangelog`）新增一行，而**新行是追加在数组末尾**（页面按数组顺序渲染）⇒ 会排在两条旧记录**后面**；要它排最前就得把三条 body 整体挪一遍（本会话未做，等用户点名）。

## 十、子插件发布的内容规范

### A. 平台硬规则（原文见 `https://emberveil.org/wiki/addons/guide`，启动器按这套装包）

- **两个必填链接**：① 受支持托管平台的仓库（`github.com` / `gitlab.com` / `bitbucket.org` / `codeberg.org` / `git.sr.ht`）；② **同一仓库里带版本号的 `.zip` 直链**。禁短链 / 记 IP 的链接。
- **严禁 `…/archive/HEAD.zip`**：HEAD 每次都变 ⇒ 哈希失配 ⇒ 启动器拒装。要 `…/releases/download/<tag>/x.zip` 或文件名带版本号。
- **启动器流程**：HTTPS 下载 → 与记录的 SHA-256 校验（不符即拒）→ 解压 → 按 `Folder/Folder.toc` 找插件夹（`.toc` 直接位于同名夹内、大小写不敏感）→ 复制到 `Interface/AddOns/`。**目标已存在非启动器安装的同名夹 ⇒ 不覆盖并中止**（要先手动删）。
- **结构四条**：① 每个夹是 `Folder/Folder.toc`（没有同名 `.toc` 的夹被忽略）；② **文件夹名就是最终名**（别用容器夹包裹、别改名）；③ git-archive 会套一层 `repo-<ref>/` ⇒ **插件必须是仓库的子目录**（我们的 `addons/EH_<名>/` 天然满足；`.toc` 在仓库根目录 = 识别不出）；④ 多夹插件各自放 zip 根。
- **zip 里不许有**：`WTF/`、`SavedVariables`、`Cache/`、`.git`、插件夹以外的任何东西。
- **禁止条目名**：绝对路径 / 以 `/` 开头 / 盘符或 `:` / `..`；Windows 保留名 `CON PRN AUX NUL COM1–9 LPT1–9`（带扩展名也不行，如 `CON.toc`）；文件名不得以点或空格结尾、不得含控制字符或 RTL 字符；**插件夹名不得以 `Blizzard_` 开头**。
- **格式**：仅 `.zip`（stored=0 / deflate=8），**不支持 ZIP64 / 加密 / 分卷**，条目名 UTF-8。
- **大小**：下载 ≤ **64 MB**（**作为 GitHub Release 附件时 ≤ 2 GB** —— 只有这种情况服务器不下载、直接读 GitHub 记录的哈希）；解压后 ≤ 4 GB；单文件 ≤ 256 MB。
  ★ 我们主插件 **63.81 MB** 已贴近 64 MB 的非 Release 上限 ⇒ **必须继续走 GitHub Release 附件**（2 GB 档），别改成源码压缩包 / 别投到别的平台。
- **只安装游戏文件**：`.toc .lua .xml .blp .tga .wav .mp3 .ogg .ttf .m2`；README / LICENSE / 截图 / 构建脚本**不进 AddOns**；`.exe/.dll/.bat/.ps1/.py/.lnk/.url` 永不安装且会列给管理员。
- **媒体魔数校验**：`.blp` 以 `BLP` 开头、`.wav` 以 `RIFF`、`.ogg` 以 `OggS`，否则拒包。
- **审核比对**：GitHub 发行版会拿每个 `.lua/.xml/.toc` 与 **tag 处的仓库**比对，仓库里没有的文件会被标出 ⇒ **发行包必须从打了 tag 的提交构建**。
- **大数据包（>64 MB 语音/贴图/多语言）**：拆成**单独条目**，分类选 **「数据包」**；数据包**只许含 `.toc` + 媒体**（出现任何 `.lua`/`.xml` 直接不批）；数据包也要 `Folder/Folder.toc`，最简 `.toc` 写 `## LoadOnDemand: 1`；主插件描述里说明该装哪个数据包。**描述里的链接既不校验也不安装**。
- **提交后**：提交 → 人工审核 → 服务器校验下载（约 1 分钟，**期间不能编辑**）→ 启动器目录上线；之后任何改动 = 新修订版，**要重新审核**。

### B. 我们现有条目的文案约定（照抄这个模板，别自创）

★ **逐字原文案例集 = `doc/Emberveil插件平台-已发布内容存档.md`**（5 条发布原文 + 版本/大小/SHA-256/图片 URL；复算 `node tmp/emberveil_dump_published.js`，纯读）。写新条目时**先照案例集的句式抄**，再改成本插件的内容。

1. **标题** = `EvalHelp -> EH_<名> · <中文名>（<附注，可省>）`；主插件标题 = `EvalHelp 全职业一键宏,全任务装备检索,工具箱,宠物资料`。
2. **版本字段** = **单版本 `v<宿主版本>`**（如 `v1.75.117`）—— ★平台保存时按下载链接的 tag **重算**，`_<子版本>` 后缀留不住（§八 表下那段）；**要表达子插件版本就写进描述正文**。
3. **分类**：战斗（EH_Damage / EH_DPS）· 背包与物品栏（EH_Bag）· 其他（EH_DebugBox）—— 按**子插件自身功能**选，不跟主插件。
4. **描述结构（子插件统一 5~6 段）**：
   - ① 首行 = `<EH_名> <中文名>子插件`（实测：`EH_Damage · 增强伤害显示（浮动战斗信息）` / `EH_Bag 整合背包子插件` / `EH_DPS · 队伍伤害统计（自娱自乐版）` / `EH_DebugBox 图层调试子插件`）
   - ② 📢 行（固定原文）：`📢 插件发布频道（KOOK）：emberveil 一键宏 · 插件发布 (www.kookapp.cn) —— 每次发布都在这里发帖（主插件与每个子插件各一条），帖内含更新概要、封面/截图与下载包链接。`
   - ③ 定位段：是什么 · 实现口径（如「事件解析走 SCT 模式，本客户端没有结构化战斗事件/GUID」）· 依赖与免责（如 EH_DPS 的「自娱自乐版：准确度不保证」）· 互斥说明（如 EH_Bag 与 OneBag/Bagnon 互斥、`/ebag force`）
   - ④ `打开方式`：宿主 EvalHelp → 配置窗 → **⑦ 子插件** → <组>勾选 → **重载界面**；命令入口（`/edmg` `/ebag` `/edps` `/edb`）
   - ⑤ `功能地图` / `界面构成` / `面板功能地图`：**逐项罗列**（勾选项数、参数档位、按钮、悬停、命令表用表格）
   - ⑥ （EH_Bag 那种自包含条目可加）「本插件是 EvalHelp 的独立子插件：自带 `.toc`、自带存档、自带三份文档（README / CLAUDE.md / CHANGELOG.md）」
5. **不做**：子插件页**不放更新日志、不放常见问题**（现状四条都没有；只有主插件放了 2 条里程碑）。
6. **图标 / 封面 / 截图**：页面有这三个上传位（现状五条都填了截图区）；截图最多 10 张。
7. ★ **描述是给人看的说明书，不是发布流水** —— 不写「本版改了什么」（那是更新日志/CHANGELOG 的事）。
