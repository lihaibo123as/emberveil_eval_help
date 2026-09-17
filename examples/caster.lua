-- 案例模版 · 通用法系（数据文件：由 EvalHelp.toc 载入）
--   为什么是 .lua 文件而不是 .md：本客户端没有文件读取 API（Lua 沙箱无 io/os），
--   插件运行时读不了自己的目录 → 唯一受支持的「从文件载入」就是列进 .toc 当 Lua 模块加载。
--   格式与导入导出完全一致（md 文本），可直接编辑；顺序 = .toc 里的顺序 = 模版选单顺序。
EVAL_IO_TEMPLATES = EVAL_IO_TEMPLATES or {}
table.insert(EVAL_IO_TEMPLATES,
  { cls = "通用法系", list = {
    { name = "周围补buff", desc = "切最近友方挨个补奥术智慧（切+补一键完成；buff 技能自行替换）", text = "# 方案: 周围补buff\n\n" ..
      "- 选取目标:最近友方 | 目标非战斗\n" ..
      "- 奥术智慧 | 无目标buff:奥术智慧" },
  }})
