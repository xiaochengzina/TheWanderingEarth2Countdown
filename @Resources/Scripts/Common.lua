-- ============================================================================
-- Common.lua  共享工具模块
--
-- 由 Countdown.lua / Settings.lua 通过 dofile 各自加载一份
-- （Rainmeter 给每个 Script 度量独立的 Lua 沙盒，因此不能跨脚本共享全局量）
--
-- 这里只放「与界面无关」的通用函数：数值校验、颜色解析、日期换算、写设置。
--
-- ⚠ 重要陷阱：Rainmeter 的 Lua 桥接会用「系统 ANSI 码页」解释 Lua 字符串。
--   · 从 bang 参数进来的中文（例如 $UserInput$）再原样传出去是安全的
--     —— 解码/编码对称，来回一趟不会变。
--   · 但如果在 Lua 里自己拼出含中文的字符串（例如从文件原始字节里读出
--     一段 UTF-8），再交给 SKIN:Bang，就会被当成 ANSI 重新编码而变成乱码。
--   所以本皮肤所有「含中文的值」都只走 Rainmeter 自己的变量系统，
--   绝不经过 Lua 中转。见 Settings.lua 的 ResetToDefaults()。
-- ============================================================================

local Common = {}

-- --------------------------------------------------------------- 路径 ------

-- 用户设置文件（#@# = @Resources 目录，自带结尾反斜杠）
function Common.VarsPath()
    return SKIN:GetVariable('@') .. 'Configs\\Variables.inc'
end

-- --------------------------------------------------------------- 变量 ------

-- 读取数值型变量；缺失或非法时返回 default
function Common.GetNum(key, default)
    local v = tonumber(SKIN:GetVariable(key))
    if v == nil then return default end
    return v
end

-- 读取正文字符串变量，并去掉首尾空白
function Common.GetStr(key, default)
    local v = SKIN:GetVariable(key)
    if v == nil or v == '' then return default or '' end
    return v:match('^%s*(.-)%s*$')
end

-- 取整并夹在 [min, max]；越界或非法时返回 default
function Common.ClampInt(raw, min, max, default)
    local n = tonumber(raw)
    if n == nil then return default end
    n = math.floor(n)
    if n < min or n > max then return default end
    return n
end

-- 持久化写入设置文件（写入后还需 !SetVariable 或刷新才会在当前皮肤生效）
function Common.WriteVar(key, value, path)
    SKIN:Bang('!WriteKeyValue', 'Variables', key, tostring(value), path or Common.VarsPath())
end

-- --------------------------------------------------------------- 颜色 ------

-- 解析 'r,g,b' 或 'r,g,b,a' → r, g, b, a（a 默认 255）；非法返回 nil
function Common.ParseColor(str)
    if type(str) ~= 'string' then return nil end
    local r, g, b, a = str:match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%d*)%s*$')
    if not r then return nil end
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    a = (a == '' or a == nil) and 255 or tonumber(a)
    if r > 255 or g > 255 or b > 255 or a > 255 then return nil end
    return r, g, b, a
end

-- 取颜色字符串的某个通道，越界返回 fallback
function Common.ColorChannel(str, channel, fallback)
    local r, g, b, a = Common.ParseColor(str)
    if not r then return fallback end
    if channel == 'R' then return r end
    if channel == 'G' then return g end
    if channel == 'B' then return b end
    return a
end

-- 把某个通道换成新值，返回新的 'r,g,b' 字符串
function Common.ColorWithChannel(str, channel, value)
    local r, g, b = Common.ParseColor(str)
    if not r then r, g, b = 255, 255, 255 end
    value = math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
    if channel == 'R' then r = value
    elseif channel == 'G' then g = value
    elseif channel == 'B' then b = value end
    return string.format('%d,%d,%d', r, g, b)
end

-- --------------------------------------------------------------- 日期 ------

-- 某年某月的天数（含闰年判断）
function Common.DaysInMonth(year, month)
    if month == 2 then
        local leap = (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
        return leap and 29 or 28
    end
    if month == 4 or month == 6 or month == 9 or month == 11 then return 30 end
    return 31
end

-- 目标日期距离今天还有多少天（与 1.x 版算法完全一致，保证显示数字不变）
-- 兼容旧版语义的「还剩几天」（不足一天算一天）。
-- 2.2 起主皮肤改用 Common.NextTarget + floor 取整，这里保留给二次开发者参考。
function Common.DaysLeft(year, month, day)
    year = math.floor(tonumber(year) or 0)
    month = math.floor(tonumber(month) or 0)
    day = math.floor(tonumber(day) or 0)
    if year < 1970 or month < 1 or month > 12 or day < 1 then return 0 end
    day = math.min(day, Common.DaysInMonth(year, month))

    -- os.time 的字段名是 min / sec
    -- ⚠ 远年份会返回 nil，见 FindTimeOnDay 的说明
    local target = os.time({ year = year, month = month, day = day,
                             hour = 0, min = 0, sec = 0 })
    if target == nil then return 0 end
    local diff = target - os.time()
    local left = math.floor(diff / 86400)
    if left < 0 then return 0 end
    return left + 1
end

-- ============================================================================
-- os.time 能表示的最大年份。
-- Windows 的 C 运行时在 3000 年前后就会让 os.time 返回 nil，
-- 所以年份字段的上限用它，而不是看起来更漂亮的 9999。
-- 代码里凡是 os.time 的结果仍然都会判 nil（用户可以手改配置文件绕过面板）。
local YEAR_MAX = 3000

-- 目标模式（倒计时核心）
--
-- 目标不是「一个时刻」而是「一个模式」：年 / 月 / 日 / 时 / 分 都可以留空，
-- 留空表示该项任意，于是目标变成一串重复出现的时刻。
--   · 六项全填 → 只有一个匹配，到点后没有未来匹配 → 停在 0
--   · 任一项留空 → 未来永远还有匹配 → 到点后自动开始下一轮
--
-- 留空判定（控制面板与主皮肤共用这一份，必须保持一致）：
--   年 / 月 / 日：空 或 0 都算留空（0 年 0 月 0 日本来就不合法）
--   时 / 分     ：只有空算留空，0 是「0 点 / 0 分」
--   秒          ：不支持留空，非法值按 0
-- ============================================================================

-- 读取一个可留空字段；返回 nil 表示「任意」
local function ReadField(key, zeroIsWild, min, max)
    local raw = tostring(SKIN:GetVariable(key) or ''):match('^%s*(.-)%s*$')
    if raw == '' then return nil end
    local n = tonumber(raw)
    if n == nil then return nil end
    n = math.floor(n)
    if zeroIsWild and n == 0 then return nil end
    -- 越界值一律按留空处理，避免设置文件被改坏时皮肤报错
    if n < min or n > max then return nil end
    return n
end

-- 读取当前目标模式
--
-- ⚠ 「不能跳级」：通配（留空 = 循环）只能是从「年」开始的一段连续前缀。
--   面板侧会联动保证（见 Settings.lua 的 FixChain），这里再补一遍 ——
--   用户可以直接用记事本改 Variables.inc，那样就绕过了面板。
--   不补的话会出现「年固定 + 月循环」这种组合，语义是「某个年份里的每个月」，
--   作者明确要求禁掉（用户很难看懂）。
--   处理方式是**把前面也当成通配**（而不是把后面的通配取消）：
--   余下的含义是「更频繁地重复」，比「悄悄换成某个具体月日」安全。
function Common.TargetSpec()
    local second = math.floor(tonumber(tostring(SKIN:GetVariable('TargetSecond') or '')) or 0)
    if second < 0 or second > 59 then second = 0 end

    local sp = {
        year   = ReadField('TargetYear',   true,  1970, YEAR_MAX),
        month  = ReadField('TargetMonth',  true,  1, 12),
        day    = ReadField('TargetDay',    true,  1, 31),
        hour   = ReadField('TargetHour',   false, 0, 23),
        minute = ReadField('TargetMinute', false, 0, 59),
        second = second,
    }

    -- 从链条末端往前推：任一项是通配，它前面所有项也必须是通配
    if sp.minute == nil then sp.hour   = nil end
    if sp.hour   == nil then sp.day    = nil end
    if sp.day    == nil then sp.month  = nil end
    if sp.month  == nil then sp.year   = nil end

    return sp
end

-- 在某一天的 时 / 分 里找第一个 >= now 的时刻；找不到返回 nil
-- 注意：os.time 的表字段名是 min / sec（不是 minute / second），
--       写错不会报错，只会被静默忽略当成 0 —— 这里务必用 min / sec。
-- 用 >= 而不是 >：目标时刻那一秒会显示 0，循环计时才看得见「到点」的瞬间。
local function FindTimeOnDay(sp, y, m, d, now)
    -- ⚠ os.time 对太远的年份会返回 nil（Windows 的 C 运行时上限在 3000 年前后）。
    --   拿 nil 去和 now 比较会抛 "attempt to compare nil with number"，
    --   而且这里每秒都会被调用一次，会变成每秒刷屏报错。
    --   所以每个 os.time 的结果都必须挡一道，不能只靠面板限制输入范围
    --   （用户可以手改 Variables.inc 绕过面板）。
    local dayEnd = os.time({ year = y, month = m, day = d, hour = 23, min = 59, sec = 59 })
    if dayEnd == nil then return nil end
    -- 整天都已经过去就直接放弃，省掉最多 1440 次 os.time
    if dayEnd < now then
        return nil
    end

    local hFrom, hTo = 0, 23
    if sp.hour then hFrom, hTo = sp.hour, sp.hour end
    local miFrom, miTo = 0, 59
    if sp.minute then miFrom, miTo = sp.minute, sp.minute end

    for h = hFrom, hTo do
        for mi = miFrom, miTo do
            local t = os.time({ year = y, month = m, day = d,
                                hour = h, min = mi, sec = sp.second })
            if t ~= nil and t >= now then return t end
        end
    end
    return nil
end

-- 未来最多找几天：
--   年固定时只需找到那一年（+1 天容错）
--   年留空时最坏要等 2/29，最多 8 年，留足 9 年
local function MaxSearchDays(sp, now)
    if sp.year then
        local y = os.date('*t', now).year
        if sp.year < y then return 0 end
        return (sp.year - y + 1) * 366
    end
    return 366 * 9
end

-- 返回 > now 的最近匹配时刻；没有则返回 nil
function Common.NextTarget(sp, now)
    -- 快速路径：年月日都固定 → 直接定位那一天，省掉逐日扫描
    if sp.year and sp.month and sp.day then
        if sp.day > Common.DaysInMonth(sp.year, sp.month) then return nil end
        return FindTimeOnDay(sp, sp.year, sp.month, sp.day, now)
    end

    -- 逐日往后找（从今天开始）
    local t = os.date('*t', now)
    local y, m, d = t.year, t.month, t.day
    -- 年固定且在将来时，直接跳到那一年的 1 月 1 日再扫。
    -- 否则要从今天一天天挪过去，目标年越远空转越多 ——
    -- TargetYear 很远时（旧上限 9999）是约 290 万次，而这里每秒都会被调用一次，
    -- 皮肤会明显卡顿。跳过去以后最多只需扫 366 天。
    -- （跳过的那些天 sp.year 不可能等于 y，本来就不会命中。）
    if sp.year and sp.year > y then
        y, m, d = sp.year, 1, 1
    end
    local dim = Common.DaysInMonth(y, m)

    for _ = 1, MaxSearchDays(sp, now) do
        if (sp.year == nil or sp.year == y)
            and (sp.month == nil or sp.month == m)
            and (sp.day == nil or sp.day == d) then
            local hit = FindTimeOnDay(sp, y, m, d, now)
            if hit then return hit end
        end
        d = d + 1
        if d > dim then
            d = 1
            m = m + 1
            if m > 12 then m = 1; y = y + 1 end
            dim = Common.DaysInMonth(y, m)
        end
        -- 年固定时，跨出这一年就不用再找了
        if sp.year and y > sp.year then return nil end
    end
    return nil
end

-- ------------------------------------------------------------- 单位切换 ---

-- 剩余秒数 → 单位索引与数值
--   1 = 天（最大单位，无上限） 2 = 时 3 = 分 4 = 秒
-- 阈值来自 Layout.inc：UnitSwitchDay（小时）、UnitSwitchHour（分钟）、
-- UnitSwitchMinute（秒）。数值一律向下取整。
function Common.PickUnit(rem)
    -- 下限兜底：这三个值直接来自配置文件。手改成 0 或负数时，
    -- 「rem >= 0」永远成立 → 一律用天，剩余 20 小时会显示成「0 天」。
    -- 控制面板的输入校验已经限制了下限（24 / 60 / 60），这里再挡一道，
    -- 保证手改 Variables.inc 也不会出现「0 天」。
    local day    = math.max(24, tonumber(SKIN:GetVariable('UnitSwitchDay'))    or 72) * 3600
    local hour   = math.max(60, tonumber(SKIN:GetVariable('UnitSwitchHour'))   or 120) * 60
    local minute = math.max(60, tonumber(SKIN:GetVariable('UnitSwitchMinute')) or 90)

    if rem >= day then return 1, math.floor(rem / 86400) end
    if rem >= hour then return 2, math.floor(rem / 3600) end
    if rem >= minute then return 3, math.floor(rem / 60) end
    return 4, math.floor(rem)
end

-- 模式里的日期时间部分，纯 ASCII，例如 '*-10-29 16:30:00'
-- ⚠ 这里绝不能拼中文字面量：Rainmeter 的 Lua 桥接会把 Lua 里造出来的中文
--   按 ANSI 重编码 → 乱码。中文一律放在 .ini 的变量里，由 Lua 用
--   SKIN:GetVariable 读出来再传回去（那样是原样往返，不会坏）。
function Common.TargetPattern(sp)
    local function f(v, fmt) return v and string.format(fmt, v) or '*' end
    return string.format('%s-%s-%s %s:%s:%02d',
        f(sp.year, '%04d'), f(sp.month, '%02d'), f(sp.day, '%02d'),
        f(sp.hour, '%02d'), f(sp.minute, '%02d'), sp.second)
end

-- 重复周期键名（纯 ASCII）。取「最小那个留空的字段」作为周期：
--   minute 留空 → 每分钟   hour 留空 → 每小时   day 留空 → 每日
--   month  留空 → 每月     year 留空 → 每年     全填 → 只触发一次
-- 中文文字在 Settings.ini 的 [Variables] 里，键名 Repeat<Key>。
function Common.TargetRepeatKey(sp)
    if sp.minute == nil then return 'minutely' end
    if sp.hour   == nil then return 'hourly' end
    if sp.day    == nil then return 'daily' end
    if sp.month  == nil then return 'monthly' end
    if sp.year   == nil then return 'yearly' end
    return 'once'
end

return Common
