-- ============================================================================
-- Countdown.lua  主皮肤逻辑（倒计时显示）
--
-- 计时规则本身放在 Common.lua（控制面板也要用同一份）：
--   · 目标是「模式」：年/月/日/时/分 可以留空 = 任意，留空后到点自动循环
--   · 六项全填 = 只触发一次，到点后停在 0 秒
--
-- 本文件只负责「显示」：
--   Value()    大号数字
--   UnitCn()   中文单位（天 / 时 / 分 / 秒）
--   UnitEn()   英文单位（自动单复数）
--   EnLine()   英文整行：IN 71 HOURS
--   *Spacing() 各段字间距（InlineSetting 不支持公式，只能由脚本给值）
--   ForceRender()  控制面板改完设置后调它立即重绘
--
-- 单位切换阈值与取整方式见 Common.PickUnit：一律 floor(剩余 / 单位秒数)。
--
-- 度量使用 UpdateDivider=-1：平时不进更新循环，
-- 只在 meter 通过 [&MeasureCountdown:函数()] 取值时才被调用。
-- ============================================================================

local Common

local function EnsureCommon()
    if Common == nil then
        Common = dofile(SKIN:GetVariable('@') .. 'Scripts\\Common.lua')
    end
end

local function Var(key, default)
    local v = SKIN:GetVariable(key)
    if v == nil or v == '' then return default end
    return v
end

-- ------------------------------------------------------------- 剩余时间 ---

-- 同一秒内 Value / UnitCn / EnLine 会各取一次值，缓存一下避免重复搜索
local cache = { at = -1, rem = 0, unit = 1, value = 0 }

local function Remaining()
    local now = os.time()
    if cache.at == now then return cache.rem end

    EnsureCommon()
    local target = Common.NextTarget(Common.TargetSpec(), now)
    local rem = target and (target - now) or 0
    if rem < 0 then rem = 0 end

    cache.at = now
    cache.rem = rem
    cache.unit, cache.value = Common.PickUnit(rem)
    return rem
end

local function Unit()
    Remaining()
    return cache.unit, cache.value
end

-- ------------------------------------------------------------- 单位文字 ---

-- 单位顺序与 Common.PickUnit 一致：天 / 时 / 分 / 秒
local UNIT_CN  = { 'UnitDayCn', 'UnitHourCn', 'UnitMinuteCn', 'UnitSecondCn' }
local UNIT_EN  = { 'UnitDayEn', 'UnitHourEn', 'UnitMinuteEn', 'UnitSecondEn' }
local UNIT_ENP = { 'UnitDayEnPlural', 'UnitHourEnPlural', 'UnitMinuteEnPlural', 'UnitSecondEnPlural' }

-- ------------------------------------------------------------- 对外 -------

-- 大号数字
function Value()
    local _, n = Unit()
    return tostring(n)
end

-- 中文单位（单字：天 / 时 / 分 / 秒）
function UnitCn()
    local idx = Unit()
    return Var(UNIT_CN[idx], '')
end

-- 英文单位（按单复数自动选）
-- 单数规则：n <= 1 用单数 —— 也就是 0 和 1 都不加 s（作者要求）
function UnitEn()
    local idx, n = Unit()
    local key = (n <= 1) and UNIT_EN[idx] or UNIT_ENP[idx]
    return Var(key, '')
end

-- 英文整行：IN 71 HOURS / IN 1 DAY / IN 0 SECOND
function EnLine()
    local idx, n = Unit()
    local key = (n <= 1) and UNIT_EN[idx] or UNIT_ENP[idx]
    return string.format('%s %d %s', Var('EnDaysPrefix', 'IN'), n, Var(key, ''))
end

-- 剩余秒数（外部排查用）
function RemainingSeconds()
    return Remaining()
end

-- ------------------------------------------------------------- 字间距 -----

-- InlineSetting 不支持公式，字间距必须由脚本给出数值字符串
function CnSpacing()
    EnsureCommon()
    return string.format('%.3f', Common.GetNum('CnSpacing', -4.7) * Common.GetNum('Scale', 1))
end

function EnSpacing()
    EnsureCommon()
    return string.format('%.3f', Common.GetNum('EnSpacing', 0.5) * Common.GetNum('Scale', 1))
end

function DaysSpacing()
    EnsureCommon()
    return string.format('%.3f', Common.GetNum('DaysSpacing', -4.32) * Common.GetNum('Scale', 1))
end

-- ------------------------------------------------------------- 重绘 -------

-- 控制面板改完变量后调用（在主皮肤上下文里执行）
-- 公式类设置需要连续两次 UpdateMeter 才生效
function ForceRender()
    cache.at = -1
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
    return 0
end

-- ------------------------------------------------------------- 入口 -------

function Initialize()
    EnsureCommon()
    cache.at = -1
    return 0
end

function Update()
    return 0
end
