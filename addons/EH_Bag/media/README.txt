EH_Bag 自带素材（子插件自包含，绝不依赖别的插件）

slotframe.tga  —— 格子/背包条按钮的**白色圆角边框**（透明底）
  来源：参考插件 OneBag（TurtleWoW）的 `media\BagSlot2.tga`，**逐字节复制**（2404 字节、64×64、TGA type-10 RLE）。
  用法：`Interface\AddOns\EH_Bag\media\slotframe.tga`（★插件目录里的散装文件要写扩展名，本插件
        `media\Flags\<名>.tga` 就是这么载入的）。
  几何：画布 64×64，画框只占中间 **39×39**（实测 alpha>32 的 bbox = x 12..50 / y 13..51）
        ⇒ 绘制边长 = 格子 × `B.SLOT_K`（= 64/39）时，画框外缘正好落在格子边上。
  ★为什么复制进来：本项目铁律「插件要绝对独立，依赖的东西要复制到插件内自己载入」——
    直接引用 `Interface\AddOns\OneBag\...` 在别人机器上（没装 OneBag）就是一张空框。

slotfill.tga   —— 格子/背包条按钮的**圆角实心底**（与 slotframe 同一条轮廓；透明底色的替代层）
  来源：由 slotframe.tga **派生**（逐行按画框最左/最右填满），生成脚本 `tmp/mk_slotfill.js`（0.3.16）。
  用法：同 slotframe（写扩展名）；与格框同锚点（CENTER）、同尺寸（格子 × B.SLOT_K）⇒ 不可能错位。

slotglow.tga   —— **同轮廓的圆角辉光**（框上最亮 · 向内渐弱 · **向外 = 0** · 画布四角透明）
  来源：由 slotframe.tga **派生**（框掩码盒式模糊 + 方向加权），生成脚本 `tmp/mk_slotglow.js`（0.3.18）。
  ★★★0.3.28 改判（用户：「**样式不是亮度的问题.是蓝的外层背景线条图没设置高亮.但是绿色把外部背景线条也设置高亮了**」）：
    旧版给「实心（圆角方形）之外」留了 0.35 权重 = **向外泛光** —— 实测 **492 个像素 / 最大 alpha 52** 落在
    **画框带（= 格子边界）之外**（邻格与背景线条上）+ 圆角外 12 个 / 最大 39；ADD 混合下绿（luma 0.587）看得见、
    蓝（luma 0.114）看不见 ⇒ 同屏只有绿格多出一圈亮线（不是亮度调参问题）。
    ⇒ 现在生成器有**硬门** `if (solid[i] === 0) v = 0;`（实心之外一律 0），自证判据 = **「向外必须 = 0」**；
    格子内的衰减（214→143→71→0）与旧版**逐值相同** ⇒ 观感按「蓝的那一档」不变。
    复算脚本 = `node tmp/slotglow_out_probe.js`（**只读**：画框带外 / 圆角外的辉光像素必须 **= 0 个**）。
  用法：`B.SLOT_GLOW` + **ADD** 混合（`B.GLOW_A` / `B.GLOW_A_HOVER` 控强度），画在框之上（OVERLAY）。
  ★为什么不用客户端模板自带的那两张：`ButtonHilight-Square` / `UI-Quickslot-Depress` 都是**方框**，
    套在圆角框上就是「外方内圆」两层边框（用户报的「外层还有一个小边框」）⇒ 已收起。

moneyicons.blp —— **金钱图集**（金/银/铜三枚币，各一格）
  来源：TurtleWoW `Data\interface.MPQ` 里的 `Interface\MoneyFrame\UI-MoneyIcons.blp`，**逐字节复制**
        （2580 字节 · BLP2 · comp=2(DXT) · alphaDepth=8 · **64×16 = 四格 16×16**）；
        取出脚本 = `tmp/mpq_take.js`（`--dir "D:\game\TurtleWoW\Data1" --take "UI-MoneyIcons"`）。
  用法：`Interface\AddOns\EH_Bag\media\moneyicons`（**无后缀**）或 `…moneyicons.blp`（两种写法都试，
        见 `B.MNY_OWN`）；UV 与客户端 `MoneyFrame.xml` 同口径 —— 金 0~0.25 / 银 0.25~0.5 / 铜 0.5~0.75。
  ★读不到就退回客户端那份 `Interface\MoneyFrame\UI-MoneyIcons`（两条都读不到才只画文字 + g/s/c 后缀）。
  ★负对照名字（`ehbag_absent_probe` / `ehbag_absent_probe.blp`）**绝不许真的存在** —— 它们是
    「本客户端对不存在的文件也会报尺寸」那条的探针（`B.ctlTrust` 按后缀各探一次），仓库里有闸门钉着这一点。

=== 0.3.26 又复制进来的 15 张「客户端固定贴图」（资源绝对自包含）===
  来源：全部 = TurtleWoW `Data\interface.MPQ` / `patch*.MPQ`，用 `tmp/mpq_take.js` **逐字节取出**、
        文件名**保留客户端原名**（便于溯源），落点就是本目录。合计 ~50 KB。
  用法：**代码里一律走唯一读口** `B.res(名字, 客户端兜底路径)`；建窗期 `B.resScan(f)` 一次性判定
        「自带优先 → 客户端兜底」（探针 = 新建一张不设宽高的纹理 + `SetTexture` + 读 `GetWidth`；
        负对照 = 同目录同后缀、绝不存在的名字；**两种写法都试**：先无后缀、再 `.blp`）。
        ★判不出 ⇒ 一律退回客户端那条路径（= 与「没复制」逐字节一致的行为，绝不因为探针不可信把界面画没）。
  清单（名字 = `B.RES_LIST` 里的键 = 客户端那张图的基础名）：
    WHITE8X8.blp           8×8    纯色底（WHITE8X8 + SetVertexColor；所有 1px 边/底/滑条）
    ChatFrameBackground.blp 16×16  窗背板（三条背板：主窗 / 设置菜单 / 跨角色总览的 bgFile）
    UI-Tooltip-Border.blp  128×16  窗背板边框（同上三条的 edgeFile）
    ButtonHilight-Square.blp 64×64 顶栏类型图标的悬停高光（ADD）
    Button-Backpack-Up.blp 64×64   左侧背包条「主背包」那颗按钮的图标
    UI-Button-KeyRing.blp  32×64   钥匙链按钮图标（次选）
    KeyRing-Bag-Icon.blp   64×64   钥匙链按钮图标（首选）
    INV_Misc_QuestionMark.blp 64×64 物品占位问号（总览格）+ 顶栏「其它」类图标
    INV_Misc_Note_02.blp / INV_Chest_Plate01.blp / INV_Potion_01.blp / Trade_BlackSmithing.blp /
    INV_Misc_Dust_02.blp / INV_Misc_Bag_11.blp / INV_Ammo_Arrow_01.blp   64×64 ×7 = 顶栏 8 类筛选图标
        （第 8 类是上面的问号；顺序与 `B.CATS` 一一对应）
  ★**两条没法自带的**（代码里如实留着兜底，`/ebag res` 会说明）：
    ① **物品/法术/宏图标** —— 贴图路径是**客户端数据现给的**（`GetContainerItemInfo` 第 1 个返回、
       `GetInventoryItemTexture`、`GetSpellTexture`…），我们只是把客户端给的路径原样交给 `SetTexture`。
       那是游戏本体的物品美术（几万张、跟随版本变），不可能也不应该打包进插件。
    ② **`/Game/Interface/Icons/<名>_TEX`** —— 本客户端（UE 宿主）的**资产路径**形态；EmberVeil 的美术在
       UE pak 里、路径串是压缩的 ⇒ **取不出来**。它现在只是分类图标的**第二顺位**（第一顺位是上面那 8 张自带）。
  ★体检：`/ebag res`（只读；逐条摊开「自带两种写法 + 负对照 + 选定路径 + 理由」，一条命令零步骤）；
    `/ebag status` 里另有一行摘要「资源来源：自带 N/15 条 ｜ 客户端兜底 K 条（点名）」。

