local lastRaw = nil
local maxRows = 8
local changedRows = {}
local baseColors = {}
local rowUrls = {}
local hasBlink = false
local flashOn = false

function Update()
    -- 有未确认的变化就持续闪烁：每 0.5 秒切换一次灰色背景
    if hasBlink then
        flashOn = not flashOn
        applyFlash()
        SKIN:Bang('!Redraw')
    end

    local raw = SKIN:GetMeasure("MeasureBugList"):GetStringValue()

    -- Python 还没跑完（或启动/刷新后）时输出为空：先显示上次成功结果的缓存
    if raw == nil or raw == "" then
        raw = readCache()
        if raw == nil or raw == "" then
            return
        end
    end

    -- 内容没变就不重画
    if raw == lastRaw then
        return
    end
    lastRaw = raw

    maxRows = tonumber(SKIN:GetVariable("MaxBug")) or 8
    local index = 1
    local stamp, errs = nil, ""
    local wFailed = ""
    changedRows = {}
    baseColors = {}
    rowUrls = {}

    for line in string.gmatch(raw, "([^\r\n]+)") do
        if string.sub(line, 1, 8) == "@status|" then
            local s, e, fa = string.match(
                line, "^@status|([^|]*)|([^|]*)|(.*)$")
            if s then
                stamp, errs = s, e or ""
                wFailed = fa or ""
            end
        elseif index <= maxRows then
            renderRow(index, line)
            index = index + 1
        end
    end

    local rows = index - 1

    for i = index, maxRows do
        SKIN:Bang('!SetOption', 'MeterBug' .. i, 'Y', 0)  -- 避免隐藏 meter 撑大窗口
        SKIN:Bang('!HideMeter', 'MeterBug' .. i)
    end

    renderStatus(rows, stamp, errs, wFailed)

    -- 本次结果里是否有变化行
    hasBlink = false
    for i = 1, rows do
        if changedRows[i] then
            hasBlink = true
            break
        end
    end
    flashOn = hasBlink
    applyFlash()

    SKIN:Bang('!Redraw')
end

function renderRow(index, line)
    -- Python 输出格式：<url>|<显示文本>；没有 | 时整行当文本显示
    local url, text = string.match(line, "^([^|]+)|(.*)$")
    if text == nil then
        url, text = nil, line
    end

    -- Python 在“相比上次有变化”的行前加了 "!"，这里去掉并记录下来用于闪烁
    local changed = false
    if string.sub(text, 1, 1) == "!" then
        changed = true
        text = string.sub(text, 2)
    end
    changedRows[index] = changed
    rowUrls[index] = url

    local meter = "MeterBug" .. index
    SKIN:Bang('!SetOption', meter, 'Y', (index - 1) * 20)
    SKIN:Bang('!SetOption', meter, 'Text', text)
    SKIN:Bang('!SetOption', meter, 'ToolTipText', text)  -- 悬停显示完整标题
    local color = getColor(text)
    baseColors[index] = color
    SKIN:Bang('!SetOption', meter, 'FontColor', color)

    -- 点击：打开 bug 页面，并停止这一行的闪烁（写入 ack 让 Python 也不再标记）
    local action = '[!CommandMeasure MeasureLua "StopBlink(' .. index .. ')"]'
    if url then
        action = '["' .. url .. '"]' .. action
    end
    SKIN:Bang('!SetOption', meter, 'LeftMouseUpAction', action)
    SKIN:Bang('!ShowMeter', meter)
end

function applyFlash()
    local gray = SKIN:GetVariable("ColorFlash")
    for i = 1, maxRows do
        if changedRows[i] then
            SKIN:Bang('!SetOption', 'MeterBug' .. i, 'FontColor',
                flashOn and gray or baseColors[i])
        end
    end
end

function StopBlink(index)
    -- 记录用户已经看过这一行，避免下一轮查询又闪
    if rowUrls[index] then
        ackUrl(rowUrls[index])
    end

    changedRows[index] = nil
    if baseColors[index] ~= nil then
        SKIN:Bang('!SetOption', 'MeterBug' .. index, 'FontColor', baseColors[index])
    end

    hasBlink = false
    for i = 1, maxRows do
        if changedRows[i] then
            hasBlink = true
            break
        end
    end
    if not hasBlink then
        flashOn = false
    end
    SKIN:Bang('!Redraw')
end

function ackUrl(url)
    local path = SKIN:GetVariable("AckFile")
    if path == nil or path == "" then
        return
    end
    local f = io.open(path, "a")
    if f then
        f:write(url .. "\n")
        f:close()
    end
end

function renderStatus(rows, stamp, errs, wFailed)
    -- 平时不显示状态行；只有数据源查询失败时才用红字提示
    local show = (errs ~= "")
    local meter = "MeterStatus"

    if show then
        local label = wFailed .. " " .. errs
        if stamp then
            label = stamp .. " | " .. label
        end
        SKIN:Bang('!SetOption', meter, 'Text', label)
        SKIN:Bang('!SetOption', meter, 'FontColor', SKIN:GetVariable("ColorNeed"))
        SKIN:Bang('!SetOption', meter, 'Y', rows * 20 + 4)
        SKIN:Bang('!ShowMeter', meter)
        SKIN:Bang('!UpdateMeter', meter)
    else
        SKIN:Bang('!SetOption', meter, 'Y', 0)
        SKIN:Bang('!HideMeter', meter)
    end

    SKIN:Bang('!SetOption', 'Background', 'Shape',
        'Rectangle 0,0,400,' .. (rows * 20 + (show and 24 or 4)) ..
        ',8 | Fill Color 20,20,20,180 | StrokeWidth 0')
    SKIN:Bang('!UpdateMeter', 'Background')
end

function readCache()
    -- Python 以本机 ANSI 编码（mbcs）写缓存，Lua 原样读入由 Rainmeter 解码
    local path = SKIN:GetVariable("CacheFile")
    if path == nil or path == "" then
        return nil
    end
    local ok, f = pcall(io.open, path, "r")
    if not ok or f == nil then
        return nil
    end
    local okRead, content = pcall(f.read, f, "*a")
    f:close()
    if not okRead then
        return nil
    end
    return content
end

function getColor(line)
    if string.find(line, "%(Assigned%)") then
        return SKIN:GetVariable("ColorAssign")
    elseif string.find(line, "%(Need_?Info%)") then          -- NeedInfo / Need_Info
        return SKIN:GetVariable("ColorNeed")
    elseif string.find(line, "%(Root%-?Caused%)") then        -- RootCaused / Root-Caused
        return SKIN:GetVariable("ColorRoot")
    elseif string.find(line, "%(NEW%)") or string.find(line, "%(New%)")
            or string.find(line, "%(ReOpen%)") or string.find(line, "%(UNCONFIRMED%)") then
        return SKIN:GetVariable("ColorNew")
    else
        return SKIN:GetVariable("ColorDefault")
    end
end
