@echo off
REM ── KOOK 自动化引导 · 一键启动（常驻监听）─────────────────────────────
REM  收 joined_guild → 在欢迎大厅发欢迎词；收「建议反馈」频道消息 → 入优化队列。
REM  用法：双击本文件即可；关掉窗口 = 停止。
REM  日志：kook\state\guide.log（追加写，按天不会轮转，体积很小）
REM  ★想开机自启：把本文件的快捷方式放进 shell:startup，或用「任务计划程序」建一条「登录时」任务。
cd /d "%~dp0.."
node kook\kook_guide.js --listen --send >> kook\state\guide.log 2>&1
