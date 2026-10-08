-- ★生成物，别手改：python tmp/gen_fontatlas.py（战斗数字图集 R4/R5）
--   每档 × 每风格一张 TGA（type-10 RLE + alpha）；cell 高 == D.TIER_H（档位↔图一一对应）。
--   ★每格宽度**逐字不同**（cw）且带贴图内偏移（cx）、W = 贴图总宽 ⇒ 运行时按字宽排，窄字后面不空空隙。
--   ★顶层 file/W/cw/cx = hard 风格（旧观感、旧文件名）⇒ **没有 st 的旧表照旧能用**（向后兼容）。
--   ★st[风格] = 该风格的独立度量（描边/暗晕不同 ⇒ 墨区不同，必须各一套，否则切边）。
EVAL_EDMG_FONTDIGITS = {
  chars = "0123456789+-.%:",
  styleList = "soft,hard,glow,shadow,plain",
  tiers = {
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_1.tga", h = 18, W = 247, cw = { 20,12,20,21,20,19,19,17,20,19,14,10,8,20,8 }, cx = { 0,20,32,52,73,93,112,131,148,168,187,201,211,219,239 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_1.tga", W = 255, cw = { 20,13,20,22,20,19,21,17,21,21,14,11,8,20,8 }, cx = { 0,20,33,53,75,95,114,135,152,173,194,208,219,227,247 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_1.tga", W = 243, cw = { 19,11,19,21,19,19,19,17,20,19,14,10,8,20,8 }, cx = { 0,19,30,49,70,89,108,127,144,164,183,197,207,215,235 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_1.tga", W = 243, cw = { 19,11,19,21,19,19,19,17,20,19,14,10,8,20,8 }, cx = { 0,19,30,49,70,89,108,127,144,164,183,197,207,215,235 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_1.tga", W = 243, cw = { 19,11,19,21,19,19,19,17,20,19,14,10,8,20,8 }, cx = { 0,19,30,49,70,89,108,127,144,164,183,197,207,215,235 } },
      } },
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_2.tga", h = 24, W = 310, cw = { 24,15,26,27,25,24,25,21,26,25,17,12,9,25,9 }, cx = { 0,24,39,65,92,117,141,166,187,213,238,255,267,276,301 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_2.tga", W = 321, cw = { 26,17,26,29,26,25,25,22,27,25,17,13,9,25,9 }, cx = { 0,26,43,69,98,124,149,174,196,223,248,265,278,287,312 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_2.tga", W = 300, cw = { 23,13,24,26,24,24,24,21,25,24,17,12,9,25,9 }, cx = { 0,23,36,60,86,110,134,158,179,204,228,245,257,266,291 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_2.tga", W = 303, cw = { 24,14,24,27,24,24,24,21,25,24,17,12,9,25,9 }, cx = { 0,24,38,62,89,113,137,161,182,207,231,248,260,269,294 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_2.tga", W = 300, cw = { 23,13,24,26,24,24,24,21,25,24,17,12,9,25,9 }, cx = { 0,23,36,60,86,110,134,158,179,204,228,245,257,266,291 } },
      } },
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_3.tga", h = 32, W = 411, cw = { 33,21,34,36,34,32,33,28,35,33,22,16,11,32,11 }, cx = { 0,33,54,88,124,158,190,223,251,286,319,341,357,368,400 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_3.tga", W = 409, cw = { 33,21,34,36,33,32,33,28,34,33,22,16,11,32,11 }, cx = { 0,33,54,88,124,157,189,222,250,284,317,339,355,366,398 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_3.tga", W = 407, cw = { 32,20,34,36,33,32,33,28,34,33,22,16,11,32,11 }, cx = { 0,32,52,86,122,155,187,220,248,282,315,337,353,364,396 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_3.tga", W = 391, cw = { 31,19,32,34,31,31,31,27,33,31,22,15,11,32,11 }, cx = { 0,31,50,82,116,147,178,209,236,269,300,322,337,348,380 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_3.tga", W = 385, cw = { 30,17,30,34,31,31,31,27,32,31,22,15,11,32,11 }, cx = { 0,30,47,77,111,142,173,204,231,263,294,316,331,342,374 } },
      } },
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_4.tga", h = 48, W = 604, cw = { 49,31,51,54,50,48,49,42,52,49,31,23,14,47,14 }, cx = { 0,49,80,131,185,235,283,332,374,426,475,506,529,543,590 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_4.tga", W = 615, cw = { 49,31,51,55,50,48,51,43,52,51,33,25,14,48,14 }, cx = { 0,49,80,131,186,236,284,335,378,430,481,514,539,553,601 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_4.tga", W = 606, cw = { 49,30,51,55,50,48,49,42,52,49,31,25,14,47,14 }, cx = { 0,49,79,130,185,235,283,332,374,426,475,506,531,545,592 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_4.tga", W = 565, cw = { 45,27,47,51,45,44,47,39,48,47,30,21,14,46,14 }, cx = { 0,45,72,119,170,215,259,306,345,393,440,470,491,505,551 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_4.tga", W = 546, cw = { 43,24,45,49,44,44,44,39,46,44,30,20,14,46,14 }, cx = { 0,43,67,112,161,205,249,293,332,378,422,452,472,486,532 } },
      } },
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_5.tga", h = 64, W = 789, cw = { 64,40,67,71,66,62,65,55,68,65,40,31,17,61,17 }, cx = { 0,64,104,171,242,308,370,435,490,558,623,663,694,711,772 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_5.tga", W = 795, cw = { 64,40,67,72,66,63,65,55,68,65,42,32,17,62,17 }, cx = { 0,64,104,171,243,309,372,437,492,560,625,667,699,716,778 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_5.tga", W = 783, cw = { 64,38,66,71,64,62,65,55,67,65,40,31,17,61,17 }, cx = { 0,64,102,168,239,303,365,430,485,552,617,657,688,705,766 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_5.tga", W = 739, cw = { 60,34,62,67,60,58,61,51,64,61,39,27,17,61,17 }, cx = { 0,60,94,156,223,283,341,402,453,517,578,617,644,661,722 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_5.tga", W = 711, cw = { 56,32,59,64,58,57,58,51,60,57,39,25,17,61,17 }, cx = { 0,56,88,147,211,269,326,384,435,495,552,591,616,633,694 } },
      } },
    { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_6.tga", h = 84, W = 1024, cw = { 83,51,86,93,86,82,85,72,89,85,52,39,21,79,21 }, cx = { 0,83,134,220,313,399,481,566,638,727,812,864,903,924,1003 },
      st = {
        soft = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_soft_6.tga", W = 1051, cw = { 85,53,88,95,87,83,87,73,91,87,55,42,22,81,22 }, cx = { 0,85,138,226,321,408,491,578,651,742,829,884,926,948,1029 } },
        glow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_glow_6.tga", W = 1033, cw = { 83,52,87,94,85,82,85,72,89,85,53,41,22,81,22 }, cx = { 0,83,135,222,316,401,483,568,640,729,814,867,908,930,1011 } },
        shadow = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_shadow_6.tga", W = 966, cw = { 79,46,82,89,79,76,80,67,83,80,50,35,21,78,21 }, cx = { 0,79,125,207,296,375,451,531,598,681,761,811,846,867,945 } },
        plain = { file = "Interface\\AddOns\\EH_Damage\\media\\fontdigits_plain_6.tga", W = 917, cw = { 73,41,76,83,75,74,75,65,78,75,50,32,21,78,21 }, cx = { 0,73,114,190,273,348,422,497,562,640,715,765,797,818,896 } },
      } },
  },
}
