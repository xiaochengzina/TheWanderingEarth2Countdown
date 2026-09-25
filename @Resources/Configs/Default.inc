; ============================================================================
; Default.inc  出厂默认值
;
; 「控制面板 → 高级 → 恢复默认设置」用的就是这里面的值。
;
; 键名统一加 Def 前缀，原因有两点：
;   1. 避免和 Variables.inc 里的用户设置重名（控制面板同时包含两个文件）；
;   2. 关键 —— 值必须由 Rainmeter 自己读取。Rainmeter 的 Lua 桥接把 Lua
;      字符串当作系统 ANSI 码页处理，中文一旦经过 Lua 转手就会变成乱码，
;      所以控制面板用 #DefCnText# 这种「变量引用」的方式写回去，
;      全程不经过 Lua。详见 Settings.lua 的 ResetToDefaults()。
;
; 【普通用户不需要改这个文件】
;
; 注意：本文件需保存为 UTF-16 LE（带 BOM）且第一行不能是 [Variables]
;       （原因见 Variables.inc 顶部说明）。
; ============================================================================

[Variables]
; ------------------------------------------------------------ 文本内容 ------
DefCnText=距太阳氦闪
DefEnText=THE SOLAR HELIUM FLASH

; ------------------------------------------------------------ 目标时间 ------
; 留空 / 填 0 的规则见 Variables.inc 顶部说明
DefTargetYear=2078
DefTargetMonth=1
DefTargetDay=1
DefTargetHour=0
DefTargetMinute=0
DefTargetSecond=0

; ------------------------------------------------------------ 单位切换 ------
; 阈值规则见 Variables.inc 顶部说明
DefUnitSwitchDay=72
DefUnitSwitchHour=120
DefUnitSwitchMinute=90

; ------------------------------------------------------------ 外观 ----------
DefScale=1.00
DefScalePercent=100
DefColorAccent=234,10,3
DefColorText=227,231,229
