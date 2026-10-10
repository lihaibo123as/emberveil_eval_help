-- ★生成物，别手改：python tmp/gen_fontatlas_custom.py --install
--   素材 = 用户提供的**成品字形位图**（addons/EH_Damage/fonts/<目录>/num1.png，数字 0-9）
--   ⇒ 离线切成 6 档 TGA 写进 media/，本文件只负责把逐档度量**并进** EVAL_EDMG_FONTDIGITS.st。
--   ★必须排在 FontDigits.lua **之后**、EH_Damage.lua **之前**（toc 顺序是判据）。
--   ★与 TTF 路（gen_fontatlas.py）互不覆盖：那边重跑不会抹掉这里，反之亦然。
--   ★这 4 种是**完整字形**（自带描边/阴影），不是参数式描边 ⇒ 与 soft/hard/glow/shadow/plain 并列可选。
--   ★★0.2.48 载入期零裸索引：本文件跑在 EH_Damage.lua **之前**（那一刻 say() 还不存在），
--     而它在**文件顶层**就跑 ⇒ 任何 D.tiers[N] 裸索引在表对不上时就是「读条期原生层崩」，pcall 抓不到。
--     ⇒ 逐档先问「在不在 ∧ 是不是表」，缺档**跳过并如实记一行**，由 EH_Damage.lua 在 VARIABLES_LOADED 播报。
local D = rawget(_G, "EVAL_EDMG_FONTDIGITS")
if type(D) ~= "table" or type(D.tiers) ~= "table" then
  _G.EVAL_EDMG_EXTRA_MISS = "字体度量表读不到（EVAL_EDMG_FONTDIGITS / tiers 不是表）"
else
  _G.EVAL_EDMG_EXTRA_MISS = nil
  D.st = D.st or {}
  for i = 1, table.getn(D.tiers) do
    local e = D.tiers[i]
    if type(e) == "table" and type(e.st) ~= "table" then e.st = {} end
  end
  local bi, bIdx, bSeen = 0, {}, {}
  -- ★绝不裸索引：档不在 / 不是表 ⇒ 记一次、跳过（注释独占一行，别与语句同行）
  local function put(i, sid, rec)
    local e = D.tiers[i]
    if type(e) == "table" and type(e.st) == "table" then e.st[sid] = rec return end
    if bSeen[i] then return end
    bSeen[i] = true
    bi = bi + 1
    bIdx[bi] = i
  end
  put(1, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_1.tga", W = 176, cw = { 16,11,15,10,12,9,11,11,11,11,14,13,9,14,9 }, cx = { 0,16,27,42,52,64,73,84,95,106,117,131,144,153,167 } })
  put(1, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_1.tga", W = 178, cw = { 16,11,15,10,12,9,11,11,11,11,16,13,9,14,9 }, cx = { 0,16,27,42,52,64,73,84,95,106,117,133,146,155,169 } })
  put(1, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_1.tga", W = 181, cw = { 13,8,14,13,12,14,11,12,13,12,14,13,9,14,9 }, cx = { 0,13,21,35,48,60,74,85,97,110,122,136,149,158,172 } })
  put(1, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_1.tga", W = 182, cw = { 12,8,14,14,12,14,11,11,13,12,16,13,9,14,9 }, cx = { 0,12,20,34,48,60,74,85,96,109,121,137,150,159,173 } })
  put(2, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_2.tga", W = 220, cw = { 20,14,20,12,16,11,14,15,14,14,17,16,10,17,10 }, cx = { 0,20,34,54,66,82,93,107,122,136,150,167,183,193,210 } })
  put(2, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_2.tga", W = 223, cw = { 21,14,20,12,16,11,14,15,14,14,19,16,10,17,10 }, cx = { 0,21,35,55,67,83,94,108,123,137,151,170,186,196,213 } })
  put(2, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_2.tga", W = 228, cw = { 16,10,18,18,16,18,15,15,17,15,17,16,10,17,10 }, cx = { 0,16,26,44,62,78,96,111,126,143,158,175,191,201,218 } })
  put(2, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_2.tga", W = 230, cw = { 16,10,18,18,16,18,15,15,17,15,19,16,10,17,10 }, cx = { 0,16,26,44,62,78,96,111,126,143,158,177,193,203,220 } })
  put(3, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_3.tga", W = 287, cw = { 27,19,26,16,21,15,18,19,18,18,23,20,12,23,12 }, cx = { 0,27,46,72,88,109,124,142,161,179,197,220,240,252,275 } })
  put(3, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_3.tga", W = 296, cw = { 28,19,26,16,21,15,18,19,18,18,25,22,14,23,14 }, cx = { 0,28,47,73,89,110,125,143,162,180,198,223,245,259,282 } })
  put(3, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_3.tga", W = 299, cw = { 22,13,24,23,21,24,20,20,22,20,23,20,12,23,12 }, cx = { 0,22,35,59,82,103,127,147,167,189,209,232,252,264,287 } })
  put(3, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_3.tga", W = 306, cw = { 22,13,24,23,21,24,19,20,22,20,25,22,14,23,14 }, cx = { 0,22,35,59,82,103,127,146,166,188,208,233,255,269,292 } })
  put(4, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_4.tga", W = 416, cw = { 40,27,39,23,30,21,26,28,26,26,33,30,17,33,17 }, cx = { 0,40,67,106,129,159,180,206,234,260,286,319,349,366,399 } })
  put(4, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_4.tga", W = 414, cw = { 40,28,38,23,30,21,26,28,26,26,33,30,17,31,17 }, cx = { 0,40,68,106,129,159,180,206,234,260,286,319,349,366,397 } })
  put(4, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_4.tga", W = 433, cw = { 31,19,35,34,31,35,28,28,32,30,33,30,17,33,17 }, cx = { 0,31,50,85,119,150,185,213,241,273,303,336,366,383,416 } })
  put(4, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_4.tga", W = 431, cw = { 31,19,35,34,31,35,28,28,33,29,33,30,17,31,17 }, cx = { 0,31,50,85,119,150,185,213,241,274,303,336,366,383,414 } })
  put(5, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_5.tga", W = 527, cw = { 51,35,50,30,39,27,34,36,34,34,40,37,20,40,20 }, cx = { 0,51,86,136,166,205,232,266,302,336,370,410,447,467,507 } })
  put(5, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_5.tga", W = 537, cw = { 52,35,50,30,39,27,34,36,34,34,42,39,22,41,22 }, cx = { 0,52,87,137,167,206,233,267,303,337,371,413,452,474,515 } })
  put(5, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_5.tga", W = 551, cw = { 40,24,45,44,39,45,36,37,42,38,42,37,20,42,20 }, cx = { 0,40,64,109,153,192,237,273,310,352,390,432,469,489,531 } })
  put(5, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_5.tga", W = 555, cw = { 40,24,45,44,39,45,36,36,42,38,42,39,22,41,22 }, cx = { 0,40,64,109,153,192,237,273,309,351,389,431,470,492,533 } })
  put(6, "out9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_out9c_6.tga", W = 714, cw = { 70,48,68,41,53,37,46,49,47,47,53,48,27,53,27 }, cx = { 0,70,118,186,227,280,317,363,412,459,506,559,607,634,687 } })
  put(6, "shd9c", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shd9c_6.tga", W = 726, cw = { 71,48,68,41,53,37,46,49,46,46,55,51,31,53,31 }, cx = { 0,71,119,187,228,281,318,364,413,459,505,560,611,642,695 } })
  put(6, "outwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_outwx_6.tga", W = 745, cw = { 55,33,61,60,54,61,50,50,57,52,55,48,27,55,27 }, cx = { 0,55,88,149,209,263,324,374,424,481,533,588,636,663,718 } })
  put(6, "shdwx", { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shdwx_6.tga", W = 754, cw = { 55,33,61,60,54,61,50,50,57,52,55,51,31,53,31 }, cx = { 0,55,88,149,209,263,324,374,424,481,533,588,639,670,723 } })
  if bi > 0 then
    local s = ""
    for k = 1, bi do s = s .. (k > 1 and "," or "") .. tostring(bIdx[k]) end
    _G.EVAL_EDMG_EXTRA_MISS = "字体度量表缺 " .. tostring(bi) .. " 档（第 " .. s .. " 档）"
  end
  D.styleList = tostring(D.styleList or "") .. ",out9c,shd9c,outwx,shdwx"
end
