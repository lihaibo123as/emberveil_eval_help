# 客户端补丁 · API 变更记录

> **用途**：客户端每发一次补丁（rev 递增），把「新增 / 变更的 Lua API」登记到这里 —— 版本、来源、功能推测、置信度、验证方法、对本插件的价值。
> **纪律**：本文件是**登记 + 推测**，**不是判据来源**。任何一条在被真机探针证实前，不许当成事实写进代码或 CLAUDE.md（铁律 5：先核「调用本身对不对」，再动逻辑）。
> **标记**：🟡 推测（高 / 中 / 低）· ✅ 已实测 · ❌ 已证伪。
> **索引快照**：仓库根 `api_*.html`（**1370 条**，查询 = `node parse_api.js <关键词>`）；官方 wiki A–Z 现值 **1054 条**，**滞后于客户端**。
> **来源**：启动器首页补丁说明（中文；用户 2026-09-28 截图）+ 官网月报 [One Month of Emberveil](https://emberveil.org/news/one-month-of-emberveil)（2026-09-15）。
> **同族锚点**：下文「依据」一栏引用的都是本地 1370 条索引里**已存在**的函数 —— 用它们推断新函数的参数形状与语义。

## 版本一览

| 版本 | rev | 日期 | API 变化 | 核对结论 |
|---|---|---|---|---|
| v2333 | 2329 → 2333 | 2026-09-08 | 13 个新全局函数 + `OnCursorChanged` 参数变更 | 本地快照与官方 wiki **都查不到** ⇒ 官方文档滞后，签名一律待实测 |

---

## v2333 · rev. 2329 → 2333 · 2026-09-08

### 一、补丁原文要点（启动器补丁说明）

**新功能**
- 为插件开发者添加了 **13 个新的 Lua API 函数**（完整列表见评论区）
- 队伍浏览器现已完全可用

**修复**：崩溃修复 · LFG 队伍准备确认问题 · 被定身时现在可以旋转角色 · 物品冷却时间现已在提示中显示 · 现在可以通过邮件发送金币 · 控制生物时现在可以看到其法术 · 减益现在在提示中显示剩余时间 · 邮件窗口现已显示正确的背景

**插件 API（13 个，逐字抄录）**

| # | 函数 | # | 函数 |
|---|---|---|---|
| 1 | `PlayMusic()` | 8 | `GetNumFrames()` |
| 2 | `GetActionAutocast()` | 9 | `EnumerateFrames()` |
| 3 | `ForceLogout()` | 10 | `ShowMiniWorldMapArrowFrame()` |
| 4 | `GetAuctionHouseDepositRate()` | 11 | `PositionMiniWorldMapArrowFrame()` |
| 5 | `GetBattlefieldMapIconScale()` | 12 | `UnstablePet()` |
| 6 | `IsMouselooking()` | 13 | `RestoreVideoDefaults()` |
| 7 | `ResetChatColors()` | | |

**事件变更**：`OnCursorChanged` 现在传递 4 个参数 —— `CursorX`、`CursorY`、`CursorW`、`CursorH`

### 二、索引核对（2026-09-28，纯读）

| 核对项 | 结果 |
|---|---|
| 本地 `api_*.html` 1370 条（`node parse_api.js <名>`） | 13 个名字 **全部查不到** |
| 官方 wiki A–Z（`emberveil.org/wiki/lua/functions`，1054 条） | 13 个名字 **全部查不到** |
| 官方月报 2026-09-15 | 点名同批函数：`PlaySoundFile` / `PlayMusic` / `wipe` / `trim` / `GetPlayerFacing` / `EnumerateFrames` / `GetNumFrames` / `UnstablePet` / `ForceLogout` / `IsMouselooking` / `ResetChatColors` / `GetAuctionHouseDepositRate` |

⇒ 三条结论：
1. **官方 wiki 与本地快照都滞后于客户端** ⇒ 这 13 个函数**没有文档可抄**，参数个数 / 返回值 / 语义一律**真机实测**为准。
2. 月报还点名了本补丁列表里**没有**的 `PlaySoundFile`、`wipe`、`trim`、`GetPlayerFacing` ⇒ 新 API 是**分几版陆续加的**，本文件按补丁逐版追加即可。
3. 这 13 个名字在旧索引里**一个都不存在** ⇒ 不存在「新函数顶掉同名老函数」的兼容风险。

### 三、逐条功能推测（总览）

| API | 推测功能（一句话） | 置信度 | 依据（已存在的同族函数） | 建议 |
|---|---|---|---|---|
| `PlayMusic` | 播放**音乐通道**的音频（音乐 ≠ 音效） | 🟡 中高 | `PlaySound`（音效）/ `StopMusic` / `PlayGlueMusic` / `PlayCreditsMusic` / `MusicPlayer_*` / `PlayRadio` | 别拿它做提示音（会顶掉游戏 BGM）；提示音用 `PlaySound` |
| `GetActionAutocast` | 查动作条某一格是否处于「自动施放 / 自动重复」状态 | 🟡 中 | `IsAutoRepeatAction` / `IsCurrentAction` / `GetSpellAutocast` / `ToggleSpellAutocast` | 与 `IsAutoRepeatAction` 对照实测后，可能改善「补自动攻击」的读回判据 |
| `ForceLogout` | **立即登出**（跳过 `Logout` 的营地 / 退出倒计时） | 🟡 中高 | `Logout` / `CancelLogout`（取消计时）/ `Quit` / `ForceQuit`（立即**退进程**、不发登出请求） | 有风险，插件不做「一键强制登出」 |
| `GetAuctionHouseDepositRate` | 返回拍卖行**保证金费率** | 🟡 高 | `CalculateAuctionDeposit(duration)` 的 wiki 原文已写明按「拍卖行保证金费率」「depositRate / 100」计算 | 可在**未放出售格**时预算押金 |
| `GetBattlefieldMapIconScale` | 战场地图（小地图战场版）上旗帜 / 据点图标的缩放系数 | 🟡 中 | `GetBattlefieldFlagPosition` / `GetNumBattlefieldFlagPositions` / `CreateMiniWorldMapArrowFrame` | 自绘战场地图时与客户端图标同尺寸（否则自己猜缩放会大小不一） |
| `IsMouselooking` | 当前是否处于鼠标视角 / 鼠标锁定状态 | 🟡 中高 | `CameraOrSelectOrMoveStart` / `CameraOrSelectOrMoveStop`（右键视角按下 / 抬起）/ `FlipCameraYaw` | 可替代「右键按住」自维护状态（贴手、抢鼠标判定） |
| `ResetChatColors` | 把聊天颜色恢复默认 | 🟡 高 | `ChangeChatColor` / `GetChatTypeIndex` / `ChatTypeInfo` | 给「恢复默认颜色」按钮；排查颜色被别的插件改乱 |
| `GetNumFrames` | 客户端已创建 Frame 的**总数** | 🟡 高 | `GetChildren` / `GetNumChildren`（只能沿父子链） | 与下一条配对，做「帧总量」自检 |
| `EnumerateFrames` | 遍历**客户端所有 Frame**（含匿名帧） | 🟡 高（★关键待实测） | 1.12 原生 API，本客户端此前缺失；本插件只能用 `GetChildren` 沿父子链 | ★★★ 最高价值，见「五、行动项 1」 |
| `ShowMiniWorldMapArrowFrame` | 显示 / 隐藏**小地图（战场小地图）玩家箭头** | 🟡 高 | `CreateMiniWorldMapArrowFrame`（wiki：在 Minimap 上创建玩家箭头，默认界面用于战场小地图）+ `ShowWorldMapArrowFrame` | 地图 / 小地图模块备用 |
| `PositionMiniWorldMapArrowFrame` | 摆**小地图玩家箭头**的位置 | 🟡 高 | `PositionWorldMapArrowFrame`（wiki：参数形状与 `Region:SetPoint` 相同） | 同上 |
| `UnstablePet` | 把宠物从兽栏**取回** | 🟡 高 | `StablePet`（存入）/ `ClickStablePet(ID)` / `GetStablePetInfo`；月报原文「pets can be pulled back out through the addon API too」 | 抓宠帮手 / 兽栏一键存取 |
| `RestoreVideoDefaults` | 恢复**视频 / 画质**设置为默认 | 🟡 中高 | `ClearPreferredGraphicsSettings`（清适配器 / RHI，重启生效）/ `GetCurrentResolution` / `GetScreenResolutions` | 插件一般**别调**（会改玩家画面设置），登记备用 |
| `OnCursorChanged`（4 参数） | 光标内容变化时给出光标的**屏幕位置 + 宽高** | 🟡 中 | 原语义 `OnCursorChanged(type, id, ...)`；`GetCursorPosition` | 贴手窗口可用；★参数语义变更 = 老代码兼容风险 |

### 四、逐条展开（签名猜测 / 依据 / 验证）

**1) `PlayMusic`**
- 签名猜测：`PlayMusic(路径或ID)`；配对的停止口应是已存在的 `StopMusic()`（音乐通道）而不是 `PlaySound`（音效通道）。
- 依据：索引里音乐族已有一整套 —— `MusicPlayer_PlayPause/NextTrack/BackTrack/VolumeUp/VolumeDown`（客户端内置音乐播放器 UI）、`PlayGlueMusic` / `StopGlueMusic`（登录界面）、`PlayCreditsMusic`、`PlayRadio`（Emberveil 自建的电台）。新函数补的是「插件主动播一首音乐」这一格。
- 验证：`/script print(type(PlayMusic))` 先确认真存在；再 `PlayMusic("<任意音频路径>")` 听是否出声、并看 `MusicPlayer_PlayPause` 的当前曲目是否被替换；`StopMusic()` 能否停掉它。
- 结论建议：**本插件不做音乐输出**（提示音也只该用 `PlaySound`）；仅登记。

**2) `GetActionAutocast`**
- 签名猜测：`GetActionAutocast(slot) → 布尔`（或 1/nil）；slot 口径应与 `IsAutoRepeatAction` / `IsCurrentAction` / `IsUsableAction` 的**动作条槽位号一致**。
- 依据：动作条状态查询族已有 `IsCurrentAction`（当前动作）/ `IsAutoRepeatAction`（自动重复，本项目 1.75.31 真机实证**本客户端有此函数**）/ `IsActionInRange`；宠物族有 `GetSpellAutocast` / `ToggleSpellAutocast` ⇒ 新函数是「**动作条格**的自动施放状态」查询，补的是玩家侧这一格。
- 用途（若语义坐实）：本插件「补自动攻击」的复查窗口（`wAtkGuardArm`）现在靠「按后读回」判断自动射击是否被取消；若 `GetActionAutocast` 能直接报「自动射击格是否处于自动施放」，读回判据就更直接。
- 验证：同一时刻对照三种读法 —— `/script print(tostring(GetActionAutocast(S)), tostring(IsAutoRepeatAction(S)), tostring(IsCurrentAction(S)))`（`S` = 自动射击 / 魔杖所在槽位），分别在「未开」「开着」「刚被取消」三种状态下各读一次。

**3) `ForceLogout`**
- 签名猜测：`ForceLogout()` 无参无返回。
- 依据：`Activity` 分类里 `Logout()` 会起一个倒计时（`CancelLogout()` 就是「取消已经开始的登出或退出（营地 / 退出计时器）」），而 `ForceQuit()` 的 wiki 原文是「**立即退出客户端进程，不发送登出请求**」⇒ 新函数应落在两者之间：**立即登出但仍然正常通知服务器**。
- 风险：战斗中被误触 = 直接掉线 ⇒ 插件**不提供**这个按钮；仅登记。

**4) `GetAuctionHouseDepositRate`**
- 签名猜测：`GetAuctionHouseDepositRate() → number`（百分数还是小数**必须实测**，对照下面这条反推）。
- 依据（wiki 原文，非推测）：`CalculateAuctionDeposit(duration)`「返回以 duration 上架当前出售槽物品所收取的保证金……**应用拍卖行保证金费率**」，并给出公式 `sellPrice * stackCount * (duration / 7200) * (depositRate / 100) * (1 + (maxStack - stackCount) * 0.05)`；且**要求出售格已有物品**。
- 用途：把上面公式里的 `depositRate` 暴露出来 ⇒ 插件可在**没往出售格放东西**时也算出押金（例如给「挂这个还是拆了」的建议）。
- 验证：拍卖行开窗 + 出售格放一件已知 `sellPrice / stackCount` 的物品，然后 `/script print(GetAuctionHouseDepositRate(), CalculateAuctionDeposit(120), CalculateAuctionDeposit(480))`，用公式反解 `rate` 与返回值是否一致。

**5) `GetBattlefieldMapIconScale`**
- 签名猜测：`GetBattlefieldMapIconScale() → number`（缩放倍数，如 0.6）。
- 依据：战场族有坐标类 `GetBattlefieldFlagPosition(i)` / `GetNumBattlefieldFlagPositions()` / `GetBattlefieldPosition(i)` 与箭头类 `CreateMiniWorldMapArrowFrame(frame)` ⇒ 缺的正是「图标画多大」。
- 验证：进战场后 `/script print(GetBattlefieldMapIconScale())`；再与 `BattlefieldFrame` 上现存旗帜图标的实测尺寸对比（注意 `GetWidth/GetHeight` **含缩放**，本项目已踩过）。

**6) `IsMouselooking`**
- 签名猜测：`IsMouselooking() → 布尔`（本客户端 `IsEventRegistered` 返 1 而非 true 的旧例在前 ⇒ 返回值类型要打印 `tostring`）。
- 依据：`Action` 族的 `CameraOrSelectOrMoveStart()` / `CameraOrSelectOrMoveStop()` 就是「按住右键开始 / 结束转视角」那对；`Camera` 族只有 `FlipCameraYaw` / `NextView` / `SaveView` 这类动作函数，**没有状态查询** ⇒ 新函数补的正是这个查询。
- 用途：本项目多处需要「玩家正在操作视角 ⇒ 别抢鼠标 / 别弹窗」（`tools/LootCursor.lua` 贴手、`tools/DragFrames.lua` 拖拽、弹窗全屏捕获层）；现在只能自己维护「右键按住」状态。
- 验证：`/script print(tostring(IsMouselooking()))`，分别在「没按」「按住右键拖动中」「松开后」各读一次。

**7) `ResetChatColors`**
- 签名猜测：`ResetChatColors()` 无参；语义边界（重置**全部** ChatTypeInfo 还是当前窗口）待实测。
- 依据：`ChangeChatColor(chatType, r, g, b)` + `GetChatTypeIndex` + `ChatTypeInfo` 表已存在；本插件有聊天窗名字着色功能，正好需要一个「恢复默认」的出口。
- 验证：先用 `ChangeChatColor` 把一个频道改成夸张颜色 → 调 `ResetChatColors()` → 读回该频道的 `ChatTypeInfo` 是否回到默认值。

**8) `GetNumFrames` / 9) `EnumerateFrames`**（★最高价值）
- 签名猜测：`GetNumFrames() → number`；`EnumerateFrames([frame]) → frame or nil`（传 nil 取第一个，传上一个取下一个，末尾返回 nil）。**本客户端语义必须实测**，若不接受参数或末尾不返回 nil，朴素遍历会**死循环** ⇒ 探针一律带迭代上限。
- 依据：`EnumerateFrames` 是 **1.12 原生就有**的 API（老式「帧转储 / 帧浏览器」插件靠它列帧），Emberveil 此前未实现 ⇒ 这版补上。本插件现有手段只有 `GetChildren()/GetNumChildren()` 沿**父子链**扫。
- ★★★ 对本插件的意义：CLAUDE.md 已写明「**匿名窗口 `_G` 扫描永远看不到** ⇒ 只能 `GetChildren()` 父子链 + 具名子件当指纹」（`tools/DragFrames.lua` 的 `dfGlobalScan`、`tools/LayerFix.lua` 的层清单、`/edb bars` 探针全都吃这个限制）。若 `EnumerateFrames` 真能枚举**匿名帧**，这三处就能把**从来看不到的匿名层**纳入。
- 验证（**决定性判据 = 匿名帧能不能读出来**）：
  1. 先自建一个匿名帧：`CreateFrame("Frame")`（**不给名字**），再用 `EnumerateFrames` 遍历找它；找不到 ⇒ 价值大打折扣。
  2. 计数对账：遍历总数（带上限 5000）与 `GetNumFrames()` 是否一致；统计其中 `GetName() == nil` 的条数（> 0 才算过）。
  3. 只对 `GetObjectType() == "Frame"` 的对象做操作（CLAUDE.md 的现成教训：不可索引的 userdata 会抛错并**打断整个探针**）。
  4. 结果必须进**有界落盘环**（`say` 不落日志环 ⇒ 只上屏的探针 AI 读存档时取证断链，本项目已踩过）。

**10) `ShowMiniWorldMapArrowFrame` / 11) `PositionMiniWorldMapArrowFrame`**
- 签名猜测：`ShowMiniWorldMapArrowFrame(show)`；`PositionMiniWorldMapArrowFrame(...)` 的参数形状与已存在的 `PositionWorldMapArrowFrame(point, [relativeFrame, relativePoint,] x, y)`（wiki：同 `Region:SetPoint`）**大概率一致**。
- 依据（wiki 原文）：`CreateMiniWorldMapArrowFrame(frame)` = 「在 Minimap 上创建玩家箭头模型（**默认界面将此用于战场小地图**）」；而 `CreateWorldMapArrowFrame` / `ShowWorldMapArrowFrame` / `PositionWorldMapArrowFrame` / `UpdateWorldMapArrowFrames` 是**世界地图**那一套 ⇒ 新增的两条正是它们的 **Mini（小地图）版**。
- 验证：`/script print(type(ShowMiniWorldMapArrowFrame), type(PositionMiniWorldMapArrowFrame))` 确认存在；随后在`Minimap` 上试着隐藏箭头看是否生效（**别在战斗中做**）。

**12) `UnstablePet`**
- 签名猜测：`UnstablePet(ID)`，ID 口径与 `ClickStablePet(ID)` 相同（**0 = 当前宠物，1+ = 兽栏槽位**）待实测。
- 依据：兽栏族已有 `StablePet`（存入）/ `ClickStablePet`（选择或放置）/ `GetStablePetInfo` / `GetNumStablePets` / `GetSelectedStablePet` / `PickupStablePet`，缺的正是「取出」；且月报原文写着「The stable master was showing one slot fewer than you actually had …… Stabling works, and **pets can be pulled back out through the addon API too**」——两处互相印证。
- 验证：`/script print(type(UnstablePet))`；带宠物找兽栏管理员，`GetNumStablePets()` 有多只时调用并读回（**读回自证**，别只看它不报错）。

**13) `RestoreVideoDefaults`**
- 签名猜测：`RestoreVideoDefaults()` 无参；是否要求重启客户端（像 `ClearPreferredGraphicsSettings` 那样「重启后生效」）待实测。
- 依据：`Settings` 族已有 `GetCurrentResolution` / `GetScreenResolutions` / `ClearPreferredGraphicsSettings`；本月补丁正好大改过视频设置（月报：Win7 支持回归、高 DPI 分辨率、草距可调）。
- 建议：插件**不主动调**（会改玩家画面设置）；若将来做「恢复默认画质」按钮，必须先弹确认并如实播报。

**14) `OnCursorChanged` 参数变更**
- 新语义：回调拿到 `CursorX`、`CursorY`、`CursorW`、`CursorH` 四个参数（光标**位置 + 宽高**）。
- ★注册方式**待实测**：原文说的是「事件」，可能是 `frame:RegisterEvent("OnCursorChanged")` + `OnEvent` 里的 `arg1..arg4`，也可能是帧脚本 `frame:SetScript("OnCursorChanged", handler)` —— **两种都试一遍**再写代码。
- ★单位待实测：屏幕像素？UI 坐标？`CursorW/H` 是否**含缩放**（本项目已有 `GetWidth/GetHeight` 含缩放的现成教训）。
- ★兼容风险：旧语义若为 `OnCursorChanged(type, id, ...)`，那么老代码里读 `arg1` 当「拖拽类型」的地方，现在会拿到一个数字 X ⇒ **凡是要读它的代码都必须按新语义重写**，不能沿用旧读法。
- 用途：`tools/LootCursor.lua`（拾取贴手）现在靠 0.15s `OnUpdate` + `GetCursorPosition()` 跟随光标 ⇒ 事件里直接给坐标可少一次读值、并多拿到**光标图标尺寸**（贴手窗口对齐更准）。**边界如实记**：事件只在**光标内容变化**（拿起 / 放下 / 换物品）时触发，**鼠标移动不触发** ⇒ 连续跟随仍要 `OnUpdate`。
- 验证：注册回调 → 从背包拿起一件物品 → 移到别处 → 放下，打印四个参数的 `type` 与值。

### 五、对本插件的行动项（按价值排序）

1. **`EnumerateFrames` / `GetNumFrames`（先做）**：跑「匿名帧能否枚举」探针；过判据则改造 `tools/DragFrames.lua` 的候选发现 + `tools/LayerFix.lua` 的层清单（把匿名层纳入），并同步 CLAUDE.md 里「匿名窗口 `_G` 扫描永远看不到」那条判断的适用范围。
2. **`IsMouselooking`**：可替换「右键按住」自维护状态（贴手跟随、拖拽、抢鼠标判定）。
3. **`GetActionAutocast`**：与 `IsAutoRepeatAction` 对照实测；若语义更贴合，用于「补自动攻击」的按后读回。
4. **`OnCursorChanged`（4 参数）**：`tools/LootCursor.lua` 可用；★先确认注册方式与单位，并检查项目内有没有按旧语义读 `arg1` 的代码。
5. **`Show/PositionMiniWorldMapArrowFrame`**：地图 / 小地图模块（`tools/SimpleMap.lua`）备用。
6. **`UnstablePet`**：抓宠帮手 / 兽栏一键存取备用。
7. 其余（`PlayMusic` / `ForceLogout` / `GetAuctionHouseDepositRate` / `GetBattlefieldMapIconScale` / `ResetChatColors` / `RestoreVideoDefaults`）：**仅登记**，谁需要谁先跑探针。

### 六、真机探针配方（待跑；未跑前本页全部是推测）

> 纪律：探针**一次只验一个假设**；带迭代上限；只碰 `GetObjectType() == "Frame"` 的对象；读数进**有界落盘环**。

```lua
-- ① EnumerateFrames 能不能看到匿名帧（决定性判据）
/script local f=CreateFrame("Frame") local n,anon=0,0 local it=EnumerateFrames() while it and n<5000 do n=n+1 if not it:GetName() then anon=anon+1 end it=EnumerateFrames(it) end print("frames",n,"anon",anon,"getnum",tostring(GetNumFrames()))

-- ② 鼠标视角状态
/script print("mouselook", tostring(IsMouselooking()))

-- ③ 动作条自动施放 vs 自动重复（S 换成自动射击/魔杖所在槽位）
/script local S=1 print("autocast", tostring(GetActionAutocast(S)), "autorepeat", tostring(IsAutoRepeatAction(S)), "current", tostring(IsCurrentAction(S)))

-- ④ 拍卖行押金费率（需拍卖行开窗 + 出售格已放物品）
/script print("rate", tostring(GetAuctionHouseDepositRate()), "d120", tostring(CalculateAuctionDeposit(120)), "d480", tostring(CalculateAuctionDeposit(480)))

-- ⑤ OnCursorChanged 四参数（注册方式两种都试；拿物品→移动→放下）
/script local f=CreateFrame("Frame") f:SetScript("OnCursorChanged", function() print("cur", type(arg1), tostring(arg1), type(arg2), tostring(arg2), type(arg3), tostring(arg3), type(arg4), tostring(arg4)) end) print("armed")
```

注：`/script` 里多语句用空格分隔即可；`while ... end` 这种整段循环若被客户端的 `/script` 解析截断，就改写成 `tmp/` 下的探针模块（本项目范式：探针挂到 `/eh go <子命令>`，别让用户手工复现）。

### 七、待办与复查

- [ ] 跑第六节探针，把 🟡 改 ✅ / ❌，并补上真实签名与返回类型。
- [ ] 官方 wiki 更新后（A–Z 收录这 13 个名字）再回来对账一次，把「wiki 说法」与「实测结果」并列记录。
- [ ] 每有新补丁：在本文件「版本一览」加一行 + 新增一节，**只记 API 变化**；玩法修复不写在这里。
