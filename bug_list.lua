local lastRaw = nil
local lastCached = false

function Update()
    local raw = SKIN:GetMeasure("MeasureBugList"):GetStringValue()
    local cached = false

    -- Python 还没跑完（或启动/刷新后）时输出为空：先显示上次成功结果的缓存
    if raw == nil or raw == "" then
        raw = readCache()
        cached = true
        if raw == nil or raw == "" then
            return
        end
    end

    -- 内容没变就不重画
    if raw == lastRaw and cached == lastCached then
        return
    end
    lastRaw, lastCached = raw, cached

    local maxRows = tonumber(SKIN:GetVariable("MaxBug")) or 8
    local index = 1
    local stamp, errs = nil, ""
    local wUpdated, wCached, wFailed = "", "", ""

    for line in string.gmatch(raw, "([^\r\n]+)") do
        if string.sub(line, 1, 8) == "@status|" then
            local s, e, up, ca, fa = string.match(
                line, "^@status|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if s then
                stamp, errs = s, e or ""
                wUpdated, wCached, wFailed = up or "", ca or "", fa or ""
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

    renderStatus(rows, stamp, errs, cached, wUpdated, wCached, wFailed)
    SKIN:Bang('!Redraw')
end

function renderRow(index, line)
    -- Python 输出格式：<url>|<显示文本>；没有 | 时整行当文本显示
    local url, text = string.match(line, "^([^|]+)|(.*)$")
    if text == nil then
        url, text = nil, line
    end

    local meter = "MeterBug" .. index
    SKIN:Bang('!SetOption', meter, 'Y', (index - 1) * 20)
    SKIN:Bang('!SetOption', meter, 'Text', text)
    SKIN:Bang('!SetOption', meter, 'ToolTipText', text)  -- 悬停显示完整标题
    SKIN:Bang('!SetOption', meter, 'FontColor', getColor(text))
    if url then
        SKIN:Bang('!SetOption', meter, 'LeftMouseUpAction', '["' .. url .. '"]')
    else
        SKIN:Bang('!SetOption', meter, 'LeftMouseUpAction', '')
    end
    SKIN:Bang('!ShowMeter', meter)
end

function renderStatus(rows, stamp, errs, cached, wUpdated, wCached, wFailed)
    local label = ""
    local color = SKIN:GetVariable("ColorMuted")

    if stamp then
        local word = wUpdated
        if cached then
            word = wCached
        end
        label = word .. " " .. stamp
        if not cached and errs ~= "" then
            label = label .. " | " .. wFailed .. " " .. errs
            color = SKIN:GetVariable("ColorNeed")
        end
    end

    SKIN:Bang('!SetOption', 'MeterStatus', 'Text', label)
    SKIN:Bang('!SetOption', 'MeterStatus', 'FontColor', color)
    SKIN:Bang('!SetOption', 'MeterStatus', 'Y', rows * 20 + 4)
    SKIN:Bang('!ShowMeter', 'MeterStatus')
    SKIN:Bang('!UpdateMeter', 'MeterStatus')
    SKIN:Bang('!SetOption', 'Background', 'Shape',
        'Rectangle 0,0,400,' .. (rows * 20 + 24) .. ',8 | Fill Color 20,20,20,180 | StrokeWidth 0')
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
