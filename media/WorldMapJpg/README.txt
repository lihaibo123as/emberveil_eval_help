「区域实景」贴图放这里（整张图一张 JPG，等比铺满地图帧 1002x668）

命名约定（与 MapOverlayJPGData.lua 的键一一对应）：
    media\WorldMapJpg\<图名>.jpg          ← 图名 = 客户端 GetMapInfo() 报的**地图文件名**
代码里引用时**不带扩展名**（`Interface\AddOns\EvalHelp\media\WorldMapJpg\<图名>`），
这条写法由 1.75.62 的「贴图格式测试」在真机验证（该测试工具与 media\TexTest\ 已在 1.75.69 清理，结论见 CHANGELOG 1.75.62）。

定位数据（都是生成物，手改会被冲掉）：
    MapOverlayJPGData.lua   每图一条 {宽,高,偏移x,偏移y}，帧口径 ⇒ 全库都是 {1002,668,0,0}
                            （生成器：node tmp/gen_mapjpgdata.js）
    MapOverlayOffsetJPG.lua 独立偏移量库（用户在编辑模式里微调后，用 node gen_mapoffset.js --jpg 烘进来）

体检命令（只读，先打开那张地图再敲）：
    /ehm mapfit 图层      报当前图层类型 + 本图基线 + 实景 JPG 探针（含负对照）+ 两套补偿条数
    /ehm mapfit 编辑      进编辑模式，直接拖/箭头微调，列表底部「保存（写盘 + 重载）」落盘

内容说明（这批图的来路与口径）：
1. 区域图（**53 张**）：`tmp/make_zone_jpg2.js` —— 大陆小地图瓦片拼接为主，极少数（陆地 <6%，例 Balor）
   改用客户端自带的区域美术。
2. 主城（**3 座 / 4 个文件名**，见 ⑶ 的老拼写别名）：`tmp/make_city_jpg.js`
   · 暴风城 Stormwind     834x556  真地形（城内）· 放大 1.20x
   · 达纳苏斯 Darnassus   508x338  真地形（城内）· 放大 1.97x
   · 雷霆崖 ThunderBluff  500x334  真地形（城内）· 放大 2.00x
   · 主城矩形与区域图同为 1.5 比例 ⇒ 同一套「等比铺满整帧」口径，不需要任何额外校正。
   · 分辨率代价：主城矩形本身就小（500~834 px 宽），铺到 1002 帧上是 1.2~2.0 倍上采样，
     比区域图（中位 0.56x，即多数在缩小）软一些 —— 小地图瓦片本身的像素密度决定。
3. ★**奥格瑞玛 / 幽暗城 / 铁炉堡 三座已按用户指令移除**（1.75.66b），不在本库里：
   这三座是**室内或半室内城**（铁炉堡城在山体内部、幽暗城在地下、奥格瑞玛有洞内城区），
   而**客户端的资源里没有任何城市小地图瓦片目录**（`textures\Minimap\md5translate.trs` 共 278 个目录，
   一个城市目录都没有）⇒ 从瓦片只能拼出**地表**或**残缺的城内**，不是可用的实景 ⇒ 不做，也不冒充。
   ★这三座的**城内平面图**客户端自己是带的（打开城市地图时游戏画的就是它）：
     `Interface\WorldMap\Ironforge\Ironforge1..6` · `Interface\WorldMap\Undercity\Undercity1..6`
     `Interface\WorldMap\Ogrimmar\Ogrimmar1..6`（★注意目录是暴雪老拼写 Ogrimmar，不是 Orgrimmar）
     各 6 块 × 256 = **768x512 = 1.5 比例**，与地图帧同比例。
   ⇒ **想要这三座的城内图，把图层类型切到「区域彩图」即可**（彩图档对城市图不接管 = 保留客户端原样，
     于是看到的就是客户端自带的那张室内平面图）；「区域实景」档在这三座**不接管**，客户端自己那套照常显示。
4. **一个老拼写别名**：客户端的资源目录用的是暴雪当年的拼写 **Darnassis**（非 Darnassus），
   而运行期贴图路径由客户端实时报的图名拼出来 ⇒ `Darnassis.jpg` 是同一张图的副本，表里也两键并存
   （谁在跑都能定位）。真机确认在跑哪个拼写：打开该主城地图后 `/ehm mapfit 图层`，看「地图=」那一格。

贴图从哪来：这批图是**从客户端小地图瓦片拼出来的**（TurtleWoW `Data1\*.MPQ` 的 `textures\Minimap`，
经 `tmp/minimap_extract.js` 还原成逻辑目录树后按 `WorldMapArea.dbc` 的矩形裁切拼接）。属于暴雪美术资源，
随插件分发前请自行确认许可。
