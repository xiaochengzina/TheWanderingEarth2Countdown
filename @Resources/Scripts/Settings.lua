-- ============================================================================
-- Settings.lua  控制面板逻辑 v1.2.0
--
-- 对外入口（由 Settings.ini 的鼠标动作调用）：
--   ShowPage(n)                     切换分页 1 内容 / 2 外观 / 3 高级
--   HoverNav(n, over)               导航悬停高亮
--   OpenTextInput(id)               打开文本输入框（预填当前值）
--   SetTextValue(key, value)        提交文字：CnText / EnText
--   StepField(id, delta)            目标时间六项步进（循环 ↔ 数值）
--   SetFieldValue(id, raw)          目标时间六项直接写入（空 = 留空/循环）
--   SliderJump(id, pct)             滑块：按轨道百分比定位
--   SliderStep(id, delta)           滑块：步进
--   ResetToDefaults()               恢复出厂设置
--   PreviewPattern/Next/Remain()    第 1 页的实时预览文字
--
-- 生效模型（ApplyVar）：
--   写 Variables.inc → !SetVariable 同步面板 → !SetVariable 同步主皮肤
--   → 主皮肤 ForceRender() 立即重绘。全程不刷新，不闪屏、不跳页。
-- ============================================================================

local Common

local function EnsureLoaded()
    if Common == nil then
        Common = dofile(SKIN:GetVariable('@') .. 'Scripts\\Common.lua')
    end
end

-- 主皮肤的配置名（位于 Skins\TheWanderingEarth2Countdown）
local MAIN = 'TheWanderingEarth2Countdown'

local PAGE_COUNT = 3
local CurrentPage = 1

-- ------------------------- 控件几何（必须与 Settings.ini 一致） -------------

local TRACK_W = 150   -- 滑块轨道宽度
local KNOB_R = 5      -- 滑块旋钮半径

-- ------------------------- 滑块注册表（改这里就够了） -----------------------

-- kind = 'scale'  → 写 ScalePercent + Scale
-- kind = 'color'  → 写 var 指向的颜色变量的 ch 通道
local SLIDERS = {
    Scale   = { min = 40, max = 200, step = 5, kind = 'scale' },
    AccentR = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorAccent', ch = 'R' },
    AccentG = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorAccent', ch = 'G' },
    AccentB = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorAccent', ch = 'B' },
    TextR   = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorText',   ch = 'R' },
    TextG   = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorText',   ch = 'G' },
    TextB   = { min = 0, max = 255, step = 1, kind = 'color', var = 'ColorText',   ch = 'B' },
}

-- 文字输入：变量名 → InputText 度量名
local INPUT_MEASURES = {
    CnText       = 'InputCnText',
    EnText       = 'InputEnText',
    TargetYear   = 'InputTargetYear',
    TargetMonth  = 'InputTargetMonth',
    TargetDay    = 'InputTargetDay',
    TargetHour   = 'InputTargetHour',
    TargetMinute = 'InputTargetMinute',
    TargetSecond = 'InputTargetSecond',
}

-- 变量名 → 面板上显示该值的 String 度量名
local VALUE_METERS = {
    CnText  = 'CnTitleVal',
    EnText  = 'EnTitleVal',
}

-- ------------------------- 目标时间六项（与 Settings.ini 一致） -------------
-- id      面板里的控件前缀（<id>Label / <id>Minus / <id>Val / <id>Plus）
-- var     Variables.inc 里的键名
-- min/max 合法范围
-- zeroIsWild  填 0 是否等于「留空」
-- stepWild    步进器是否会走到「循环」这一档
--              （年只有 1970–9999 两档邻居，走不到循环，只能靠清空输入框）
local FIELDS = {
    { id = 'Year',  var = 'TargetYear',   min = 1970, max = 9999, zeroIsWild = true,  stepWild = false },
    { id = 'Month', var = 'TargetMonth',  min = 1,    max = 12,   zeroIsWild = true,  stepWild = true },
    { id = 'Day',   var = 'TargetDay',    min = 1,    max = 31,   zeroIsWild = true,  stepWild = true },
    { id = 'Hour',  var = 'TargetHour',   min = 0,    max = 23,   zeroIsWild = false, stepWild = true },
    { id = 'Min',   var = 'TargetMinute', min = 0,    max = 59,   zeroIsWild = false, stepWild = true },
    { id = 'Sec',   var = 'TargetSecond', min = 0,    max = 59,   zeroIsWild = false, stepWild = false },
}

local FIELD_BY_ID = {}
for _, f in ipairs(FIELDS) do FIELD_BY_ID[f.id] = f end

-- 恢复默认：用户设置键名 → Default.inc 里的 Def* 键名
-- 值一律通过 "#DefXxx#" 交给 Rainmeter 自己展开，不经过 Lua，
-- 否则中文会被 Lua 桥接按 ANSI 重新编码而变成乱码。
local DEFAULTS = {
    { 'CnText',       'DefCnText' },
    { 'EnText',       'DefEnText' },
    { 'TargetYear',   'DefTargetYear' },
    { 'TargetMonth',  'DefTargetMonth' },
    { 'TargetDay',    'DefTargetDay' },
    { 'TargetHour',   'DefTargetHour' },
    { 'TargetMinute', 'DefTargetMinute' },
    { 'TargetSecond', 'DefTargetSecond' },
    { 'Scale',        'DefScale' },
    { 'ScalePercent', 'DefScalePercent' },
    { 'ColorAccent',  'DefColorAccent' },
    { 'ColorText',    'DefColorText' },
}

-- ------------------------- 基础工具 ----------------------------------------

local function Repaint()
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

-- 让主皮肤立刻重绘（公式类设置需要连续两次 UpdateMeter 才生效）
local function RenderMain()
    SKIN:Bang('!CommandMeasure', 'MeasureCountdown', 'ForceRender()', MAIN)
end

-- 写盘 + 同步面板 + 同步主皮肤
local function ApplyVar(key, value)
    Common.WriteVar(key, value)
    SKIN:Bang('!SetVariable', key, tostring(value))
    SKIN:Bang('!SetVariable', key, tostring(value), MAIN)
end

-- ------------------------- 外观同步 ----------------------------------------

-- 数值 → 显示文本
local function SliderText(id, v)
    if id == 'Scale' then return v .. '%' end
    return tostring(v)
end

-- 滑块的主色：编辑哪个颜色就用哪个颜色画轨道填充与旋钮描边，
-- 这样一眼就能看出"我在调的是哪种颜色"。缩放滑块固定用强调色。
local function SliderTint(id)
    local s = SLIDERS[id]
    if s and s.kind == 'color' then
        return SKIN:GetVariable(s.var, '234,10,3')
    end
    return SKIN:GetVariable('ColorAccent', '234,10,3')
end

-- 滑块外观：填充宽度 + 旋钮位置 + 数值文字
local function SyncSlider(id, v)
    local s = SLIDERS[id]
    v = math.max(s.min, math.min(s.max, math.floor(v + 0.5)))
    local frac = (v - s.min) / (s.max - s.min)
    local cx = KNOB_R + frac * (TRACK_W - 2 * KNOB_R)
    local tint = SliderTint(id)
    SKIN:Bang('!SetOption', 'Slt' .. id, 'Shape2',
        string.format('Rectangle 0,9,%.2f,6,3 | StrokeWidth 0 | Fill Color %s', cx, tint))
    SKIN:Bang('!SetOption', 'Slt' .. id, 'Shape3',
        string.format('Ellipse %.2f,12,5 | StrokeWidth 1.5 | Stroke Color %s | Fill Color #ColorBg#', cx, tint))
    SKIN:Bang('!SetOption', 'Slt' .. id .. 'Value', 'Text', SliderText(id, v))
end

-- 读取某个滑块当前对应的值
local function SliderValue(id)
    local s = SLIDERS[id]
    if s.kind == 'scale' then
        return Common.ClampInt(SKIN:GetVariable('ScalePercent'), s.min, s.max, 100)
    end
    return Common.ClampInt(Common.ColorChannel(SKIN:GetVariable(s.var, ''), s.ch, 0), s.min, s.max, 0)
end

-- 取色块
local function SyncSwatches()
    local accent = SKIN:GetVariable('ColorAccent', '234,10,3')
    local text = SKIN:GetVariable('ColorText', '227,231,229')
    SKIN:Bang('!SetOption', 'SwatchAccent', 'Shape',
        'Rectangle 0,0,64,28,7 | StrokeWidth 1 | Stroke Color #ColorBorder# | Fill Color ' .. accent)
    SKIN:Bang('!SetOption', 'SwatchText', 'Shape',
        'Rectangle 0,0,64,28,7 | StrokeWidth 1 | Stroke Color #ColorBorder# | Fill Color ' .. text)
end

-- 目标时间六项的显示同步
-- 值为空（留空）时显示「循环」并压暗；否则显示数字
local function SyncFields()
    for _, f in ipairs(FIELDS) do
        local raw = tostring(SKIN:GetVariable(f.var) or ''):match('^%s*(.-)%s*$')
        local isWild = (raw == '') or (f.zeroIsWild and tonumber(raw) == 0)
        local n = tonumber(raw)
        -- 越界值按留空显示，和主皮肤的判定保持一致
        if not isWild and (n == nil or n < f.min or n > f.max) then isWild = true end

        if isWild then
            -- 「循环」两个字从 Settings.ini 的变量读：Lua 里写中文字面量会被
            -- 桥接按 ANSI 重编码成乱码（见 Common.lua 顶部说明）
            SKIN:Bang('!SetOption', f.id .. 'Val', 'Text', SKIN:GetVariable('WildText', ''))
            SKIN:Bang('!SetOption', f.id .. 'Val', 'FontColor', '#ColorHint#')
        else
            SKIN:Bang('!SetOption', f.id .. 'Val', 'Text', tostring(math.floor(n)))
            SKIN:Bang('!SetOption', f.id .. 'Val', 'FontColor', '#ColorText#')
        end
    end
end

-- 全部同步（初始化 / 恢复默认后调用）
local function SyncAll()
    for id in pairs(SLIDERS) do
        SyncSlider(id, SliderValue(id))
    end
    SyncSwatches()
    SyncFields()
    SKIN:Bang('!SetOption', 'CnTitleVal', 'Text', SKIN:GetVariable('CnText', ''))
    SKIN:Bang('!SetOption', 'EnTitleVal', 'Text', SKIN:GetVariable('EnText', ''))
end

-- ------------------------- 分页与导航 --------------------------------------

function ShowPage(n)
    EnsureLoaded()
    n = Common.ClampInt(n, 1, PAGE_COUNT, 1)
    CurrentPage = n
    -- 持久化当前页：刷新面板后仍停留在本页
    Common.WriteVar('SettingsPage', n)
    SKIN:Bang('!SetVariable', 'SettingsPage', tostring(n))
    for i = 1, PAGE_COUNT do
        SKIN:Bang(i == n and '!ShowMeterGroup' or '!HideMeterGroup', 'Page' .. i)
        SKIN:Bang('!SetOption', 'NavBg' .. i, 'MeterStyle', i == n and 'NavBgOnStyle' or 'NavBgOffStyle')
        SKIN:Bang('!SetOption', 'Nav' .. i, 'MeterStyle', i == n and 'NavTextOnStyle' or 'NavTextOffStyle')
    end
    Repaint()
end

function HoverNav(n, over)
    EnsureLoaded()
    if Common.ClampInt(n, 1, PAGE_COUNT, 1) == CurrentPage then return end
    SKIN:Bang('!SetOption', 'NavBg' .. n, 'MeterStyle',
        tonumber(over) == 1 and 'NavBgHoverStyle' or 'NavBgOffStyle')
    SKIN:Bang('!UpdateMeter', 'NavBg' .. n)
    SKIN:Bang('!Redraw')
end

-- ------------------------- 文字输入 ----------------------------------------

function OpenTextInput(id)
    EnsureLoaded()
    local measure = INPUT_MEASURES[id]
    if not measure then return end
    SKIN:Bang('!SetOption', measure, 'DefaultValue', SKIN:GetVariable(id, ''))
    SKIN:Bang('!UpdateMeasure', measure)
    SKIN:Bang('!CommandMeasure', measure, 'ExecuteBatch 1')
end

function SetTextValue(key, value)
    EnsureLoaded()
    if not VALUE_METERS[key] then return end
    value = tostring(value or ''):match('^%s*(.-)%s*$')
    if value == '' then return end
    ApplyVar(key, value)
    SKIN:Bang('!SetOption', VALUE_METERS[key], 'Text', value)
    RenderMain()
    Repaint()
end

-- ------------------------- 目标时间（六项，可留空） -------------------------
--
-- 「留空」在 Variables.inc 里就是一个空值。写进去之后主皮肤那边的
-- Common.TargetSpec() 会把它当成「任意」，于是倒计时自动循环。
--
-- 步进器规则：
--   普通字段（月/日/时/分）：循环 ↔ min … max 之间来回走
--   年：只在 min..max 之间 ±1（相邻两档，走不到「循环」，请用输入框清空）
--   秒：0..59 循环，没有「循环」这一档

-- 读出某项当前的数字；留空 / 越界返回 nil
local function FieldValue(f)
    local raw = tostring(SKIN:GetVariable(f.var) or ''):match('^%s*(.-)%s*$')
    if raw == '' then return nil end
    local n = tonumber(raw)
    if n == nil then return nil end
    n = math.floor(n)
    if f.zeroIsWild and n == 0 then return nil end
    if n < f.min or n > f.max then return nil end
    return n
end

-- 写回某一项；value 为 nil / '' 表示留空
local function ApplyField(f, value)
    if value == nil or value == '' then
        ApplyVar(f.var, '')
    else
        ApplyVar(f.var, tostring(math.floor(value)))
    end
    SyncFields()
    RenderMain()
    Repaint()
end

-- 步进
function StepField(id, delta)
    EnsureLoaded()
    local f = FIELD_BY_ID[id]
    if not f then return end
    delta = tonumber(delta) or 0
    if delta == 0 then return end

    local cur = FieldValue(f)
    local nextVal

    if cur == nil then
        -- 当前是「循环」：+ 进最小值，− 进最大值
        nextVal = (delta > 0) and f.min or f.max
    else
        nextVal = cur + delta
        if f.stepWild then
            -- 在「循环」与数值之间成环
            if nextVal > f.max then nextVal = nil
            elseif nextVal < f.min then nextVal = nil end
            if nextVal == nil then
                -- 走到「循环」这一档；再按一次往回走就落到另一端
                ApplyField(f, nil)
                return
            end
        else
            if nextVal > f.max then nextVal = f.min
            elseif nextVal < f.min then nextVal = f.max end
        end
    end

    ApplyField(f, nextVal)
end

-- 输入框提交：空 → 留空；数字 → 该值（年/月/日 的 0 也算留空）
function SetFieldValue(id, raw)
    EnsureLoaded()
    local f = FIELD_BY_ID[id]
    if not f then return end

    raw = tostring(raw or ''):match('^%s*(.-)%s*$')
    if raw == '' then
        ApplyField(f, nil)
        return
    end

    local n = tonumber(raw)
    if n == nil then return end
    n = math.floor(n)
    if f.zeroIsWild and n == 0 then
        ApplyField(f, nil)
        return
    end
    if n < f.min or n > f.max then return end
    ApplyField(f, n)
end

-- ------------------------- 预览 --------------------------------------------
--
-- ⚠ 这里返回给 meter 的字符串里不能有「Lua 自己拼出来的中文」——
--   Rainmeter 的 Lua 桥接会按 ANSI 重新编码，中文会变乱码。
--   所以：纯 ASCII 的（数字、日期、单位英文）由 Lua 拼；
--         中文文字全部来自 .ini 变量，用 SKIN:GetVariable 读出来再传回去
--         （那是原样往返，不会坏）。中文标签放在 Settings.ini 的 [Variables]。

-- 重复周期标签：读 Settings.ini 里的 Repeat<Key> 变量
local function RepeatLabel()
    local key = Common.TargetRepeatKey(Common.TargetSpec())
    return SKIN:GetVariable('Repeat' .. key:sub(1, 1):upper() .. key:sub(2), '')
end

-- 重复周期标签（中文，值来自 Settings.ini 的 Repeat<Key> 变量）
function PreviewRepeat()
    EnsureLoaded()
    return RepeatLabel()
end

-- 目标模式（纯 ASCII）：'*-10-29 16:30:00'
-- 分隔符由 meter 那边拼，Lua 里一个非 ASCII 字符都不能有
function PreviewPattern()
    EnsureLoaded()
    return Common.TargetPattern(Common.TargetSpec())
end

-- 下一次匹配：有匹配就返回「下一次：<时刻>」，没有就返回中文兜底句
-- 两句中文都从 Settings.ini 的变量里读，避免在 Lua 里拼中文
function PreviewNextLine()
    EnsureLoaded()
    local t = Common.NextTarget(Common.TargetSpec(), os.time())
    if not t then return SKIN:GetVariable('PreviewNoMatch', '') end
    local d = os.date('*t', t)
    return SKIN:GetVariable('PreviewNextPrefix', '') ..
        string.format('%04d-%02d-%02d %02d:%02d:%02d', d.year, d.month, d.day, d.hour, d.min, d.sec)
end

-- 剩余时间：和主皮肤共用 Common.PickUnit，所以单位切换完全一致
local function RemainParts()
    EnsureLoaded()
    local now = os.time()
    local t = Common.NextTarget(Common.TargetSpec(), now)
    local rem = t and (t - now) or 0
    if rem < 0 then rem = 0 end
    return Common.PickUnit(rem)
end

-- 数字部分（纯 ASCII）
function PreviewRemainValue()
    local _, n = RemainParts()
    return tostring(n)
end

-- 中文单位（从 Layout.inc 的单位表读，原样往返）
function PreviewRemainUnit()
    local idx = RemainParts()
    local cn = { 'UnitDayCn', 'UnitHourCn', 'UnitMinuteCn', 'UnitSecondCn' }
    return SKIN:GetVariable(cn[idx], '')
end

-- 英文整行：IN 71 HOURS（单复数自动）
function PreviewRemainEn()
    local idx, n = RemainParts()
    local en = { 'UnitDayEn', 'UnitHourEn', 'UnitMinuteEn', 'UnitSecondEn' }
    local enp = { 'UnitDayEnPlural', 'UnitHourEnPlural', 'UnitMinuteEnPlural', 'UnitSecondEnPlural' }
    local key = (n == 1) and en[idx] or enp[idx]
    return string.format('%s %d %s',
        SKIN:GetVariable('EnDaysPrefix', 'IN'), n, SKIN:GetVariable(key, ''))
end

-- ------------------------- 滑块 --------------------------------------------

local function SetSlider(id, v)
    local s = SLIDERS[id]
    if not s then return end
    v = math.max(s.min, math.min(s.max, math.floor((tonumber(v) or s.min) + 0.5)))

    if s.kind == 'scale' then
        local scale = string.format('%.2f', v / 100)
        ApplyVar('ScalePercent', v)
        ApplyVar('Scale', scale)
        SyncSlider(id, v)
    else
        local cur = SKIN:GetVariable(s.var, '')
        ApplyVar(s.var, Common.ColorWithChannel(cur, s.ch, v))
        -- 同一种颜色的三个通道一起重画：轨道底色变了
        for otherId in pairs(SLIDERS) do
            if SLIDERS[otherId].var == s.var then
                SyncSlider(otherId, SliderValue(otherId))
            end
        end
    end

    SyncSwatches()
    RenderMain()
    Repaint()
end

function SliderSet(id, v)
    EnsureLoaded()
    SetSlider(id, v)
end

function SliderJump(id, pct)
    EnsureLoaded()
    local s = SLIDERS[id]
    if not s then return end
    pct = math.max(0, math.min(100, tonumber(pct) or 0))
    SetSlider(id, s.min + pct / 100 * (s.max - s.min))
end

function SliderStep(id, delta)
    EnsureLoaded()
    local s = SLIDERS[id]
    if not s then return end
    SetSlider(id, SliderValue(id) + (tonumber(delta) or s.step))
end

-- ------------------------- 恢复默认 ----------------------------------------

function ResetToDefaults()
    EnsureLoaded()
    local path = Common.VarsPath()
    for _, m in ipairs(DEFAULTS) do
        local ref = '#' .. m[2] .. '#'      -- 由 Rainmeter 展开，保证中文正确
        SKIN:Bang('!WriteKeyValue', 'Variables', m[1], ref, path)
        SKIN:Bang('!SetVariable', m[1], ref)
        SKIN:Bang('!SetVariable', m[1], ref, MAIN)
    end
    SyncAll()
    RenderMain()
    Repaint()
end

-- ------------------------- 预览 --------------------------------------------

-- ------------------------- Rainmeter 入口 ----------------------------------

function Initialize()
    EnsureLoaded()
    SyncAll()
    ShowPage(Common.ClampInt(SKIN:GetVariable('SettingsPage'), 1, PAGE_COUNT, 1))
    return 0
end

function Update()
    return 0
end
