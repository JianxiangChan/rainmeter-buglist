
local lastRaw = nil

function Update()
    local raw = SKIN:GetMeasure("MeasureBugList"):GetStringValue()
    -- Python 还没跑完时是空串：保留上一次的显示，不要清空
    if raw == nil or raw == "" then
        return
    end
    -- 内容没变就不重画（皮肤每秒更新一次，避免无谓开销）
    if raw == lastRaw then
        return
    end
    lastRaw = raw

    local maxRows = tonumber(SKIN:GetVariable("MaxBug")) or 5
    local index = 1
    for line in string.gmatch(raw, "([^\r\n]+)") do
        if index > maxRows then break end

        -- Python 输出格式：<url>|<显示文本>，没有 | 时整行当文本显示
        local url, text = string.match(line, "^([^|]+)|(.*)$")
        if text == nil then
            url, text = nil, line
        end

        local meter = "MeterBug" .. index
        local color = getColor(text) or SKIN:GetVariable("ColorDefault")  -- 防止 nil

        SKIN:Bang('!SetOption', meter, 'Text', text)
        SKIN:Bang('!SetOption', meter, 'ToolTipText', text)  -- 悬停显示完整标题
        SKIN:Bang('!SetOption', meter, 'FontColor', color)
        if url then
            SKIN:Bang('!SetOption', meter, 'LeftMouseUpAction', '["' .. url .. '"]')
        else
            SKIN:Bang('!SetOption', meter, 'LeftMouseUpAction', '')
        end
        SKIN:Bang('!ShowMeter', meter)

        index = index + 1
    end

    for i = index, maxRows do
        SKIN:Bang('!HideMeter', 'MeterBug' .. i)
    end

    SKIN:Bang('!Redraw')
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
