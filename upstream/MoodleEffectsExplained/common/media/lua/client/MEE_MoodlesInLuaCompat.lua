--[[
    Moodle Effects Explained - Moodles in Lua compatibility

    Moodles in Lua replaces the vanilla Java moodles renderer with its own Lua
    UI element. This optional compatibility patch keeps MEE independent from
    Moodles in Lua, but if Moodles in Lua is loaded it replaces only its tooltip
    drawing function so MEE's multiline moodle descriptions and tooltip font
    option are handled consistently.

    The patch is intentionally defensive:
    - it does nothing when Moodles in Lua is not loaded;
    - it keeps the original Moodles in Lua function as a fallback;
    - it supports both known signatures used by Moodles in Lua B42 branches:
      B42.12: drawMoodleTooltip(moodles, moodleId, x, y)
      B42.13+: drawMoodleTooltip(moodles, moodleType, x, y)
]]

MEE = MEE or {}
MEE.MoodlesInLuaCompat = MEE.MoodlesInLuaCompat or {}

local MEE_MIL_TOOLTIP_FONTS = {
    [1] = UIFont.Small,
    [2] = UIFont.Medium,
    [3] = UIFont.Large,
}

local MEE_MIL_TITLE_R = 1.0
local MEE_MIL_TITLE_G = 1.0
local MEE_MIL_TITLE_B = 1.0
local MEE_MIL_TITLE_A = 1.0
local MEE_MIL_DESC_R = 0.8
local MEE_MIL_DESC_G = 0.8
local MEE_MIL_DESC_B = 0.8
local MEE_MIL_DESC_A = 1.0
local MEE_MIL_BG_A = 0.6
local MEE_MIL_TEXT_PADDING = 10
local MEE_MIL_VERTICAL_PADDING = 2
local MEE_MIL_BOTTOM_PADDING = 4
local MEE_MIL_TOOLTIP_SCREEN_MARGIN = 0
local MEE_MIL_TOOLTIP_LAYOUT_CACHE_LIMIT = 128
local MEE_MIL_TOOLTIP_LAYOUT_CACHE = {}
local MEE_MIL_TOOLTIP_LAYOUT_CACHE_ORDER = {}

local function meeMILNormalizeTooltipText(text)
    -- Convert all supported line-break markers into real newlines.
    local normalized = tostring(text or "")

    -- PZ 42.20.1+ requires %% in JSON translations to display a literal %.
    -- Older B42 builds may return the doubled text unchanged, so collapse it
    -- at render time to keep one visible percent sign across supported builds.
    normalized = normalized:gsub("%%%%", "%%")
    normalized = normalized:gsub("\r\n", "\n")
    normalized = normalized:gsub("\r", "\n")
    normalized = normalized:gsub("<br>", "\n")
    normalized = normalized:gsub(" <LINE> ", "\n")
    normalized = normalized:gsub("<LINE>", "\n")
    return normalized
end

local function meeMILSplitLines(text)
    -- Keep empty descriptions drawable and preserve explicit line breaks.
    local normalized = meeMILNormalizeTooltipText(text) .. "\n"
    local lines = {}

    for line in normalized:gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    if #lines == 0 then
        table.insert(lines, "")
    end

    return lines
end

local function meeMILGetTooltipFont()
    -- Use the same client option as the internal MEE fallback renderer.
    local fontIndex = 1

    if MEE and MEE.Options and MEE.Options.TooltipFontSize then
        fontIndex = tonumber(MEE.Options.TooltipFontSize) or 1
    end

    return MEE_MIL_TOOLTIP_FONTS[fontIndex] or UIFont.Small
end

local function meeMILGetFontHeight(font)
    return getTextManager():getFontHeight(font or UIFont.Small)
end

local function meeMILMeasureMaxLineWidth(lines, font)
    -- Measure the widest title/description line using the selected font.
    local maxWidth = 0
    local textManager = getTextManager()

    for i = 1, #lines do
        local lineWidth = textManager:MeasureStringX(font or UIFont.Small, tostring(lines[i] or ""))
        if lineWidth > maxWidth then
            maxWidth = lineWidth
        end
    end

    return maxWidth
end

local function meeMILCacheTooltipLayout(cacheKey, layout)
    if MEE_MIL_TOOLTIP_LAYOUT_CACHE[cacheKey] ~= nil then
        MEE_MIL_TOOLTIP_LAYOUT_CACHE[cacheKey] = layout
        return layout
    end

    MEE_MIL_TOOLTIP_LAYOUT_CACHE[cacheKey] = layout
    table.insert(MEE_MIL_TOOLTIP_LAYOUT_CACHE_ORDER, cacheKey)

    while #MEE_MIL_TOOLTIP_LAYOUT_CACHE_ORDER > MEE_MIL_TOOLTIP_LAYOUT_CACHE_LIMIT do
        local oldestKey = table.remove(MEE_MIL_TOOLTIP_LAYOUT_CACHE_ORDER, 1)
        if oldestKey then
            MEE_MIL_TOOLTIP_LAYOUT_CACHE[oldestKey] = nil
        end
    end

    return layout
end

local function meeMILGetTooltipLayout(title, description, font)
    -- Moodles in Lua asks for the same tooltip repeatedly while the mouse stays
    -- over a moodle. Cache split lines and measured width for that hover state.
    local cacheKey = tostring(font or UIFont.Small)
            .. "\31" .. tostring(title or "")
            .. "\31" .. tostring(description or "")

    local cached = MEE_MIL_TOOLTIP_LAYOUT_CACHE[cacheKey]
    if cached ~= nil then
        return cached
    end

    local titleLines = meeMILSplitLines(title)
    local descriptionLines = meeMILSplitLines(description)
    local allLines = {}

    for i = 1, #titleLines do
        table.insert(allLines, titleLines[i])
    end
    for i = 1, #descriptionLines do
        table.insert(allLines, descriptionLines[i])
    end

    local fontHeight = meeMILGetFontHeight(font)
    local maxWidth = meeMILMeasureMaxLineWidth(allLines, font)

    return meeMILCacheTooltipLayout(cacheKey, {
        titleLines = titleLines,
        descriptionLines = descriptionLines,
        fontHeight = fontHeight,
        maxWidth = maxWidth,
        titleHeight = #titleLines * fontHeight,
        descriptionHeight = #descriptionLines * fontHeight,
    })
end

local function meeMILGetPlayerScreenVerticalBounds(playerNum)
    -- Use the player viewport when available; this keeps the tooltip inside the
    -- correct visible area in split-screen while still falling back to the full
    -- screen for older or unexpected environments.
    local screenTop = 0
    local screenHeight = getCore():getScreenHeight()

    if getPlayerScreenTop and getPlayerScreenHeight then
        screenTop = getPlayerScreenTop(playerNum or 0) or screenTop
        screenHeight = getPlayerScreenHeight(playerNum or 0) or screenHeight
    end

    return screenTop, screenTop + screenHeight
end

local function meeMILClampTooltipY(boxY, boxHeight, playerNum)
    -- Clamp every MEE-configured tooltip font size, not only Large. Long
    -- translations or future font changes can also overflow with smaller sizes.
    local screenTop, screenBottom = meeMILGetPlayerScreenVerticalBounds(playerNum)
    local minY = screenTop + MEE_MIL_TOOLTIP_SCREEN_MARGIN
    local maxY = screenBottom - boxHeight - MEE_MIL_TOOLTIP_SCREEN_MARGIN

    if maxY < minY then
        return minY
    end

    if boxY < minY then
        return minY
    end

    if boxY > maxY then
        return maxY
    end

    return boxY
end

local function meeMILGetMoodleString(moodles, moodleIdOrType, getterName)
    -- Call the Moodles API defensively because Moodles in Lua uses different
    -- parameter types across B42 branches.
    if not moodles or not moodles[getterName] then
        return nil
    end

    local ok, value = pcall(function()
        return moodles[getterName](moodles, moodleIdOrType)
    end)

    if ok then
        return value
    end

    return nil
end

local function meeMILDrawTooltip(self, moodles, moodleIdOrType, moodleX, moodleY)
    local title = meeMILGetMoodleString(moodles, moodleIdOrType, "getMoodleDisplayString")
    local meeDescription = meeMILGetMoodleString(moodles, moodleIdOrType, "getMoodleDescriptionString")

    if title == nil or meeDescription == nil then
        return false
    end

    local description = meeDescription
    if MEE and MEE.GetMoodleTooltipDescription then
        description = MEE.GetMoodleTooltipDescription(moodles, moodleIdOrType, meeDescription)
    end

    local moodleSize = self:getMoodleSize()
    local tooltipFont = meeMILGetTooltipFont()
    local layout = meeMILGetTooltipLayout(title, description, tooltipFont)
    local titleLines = layout.titleLines
    local descriptionLines = layout.descriptionLines
    local fontHeight = layout.fontHeight

    local options = self.options or {}
    local tooltipPadding = tonumber(options.tooltipPadding) or 1
    local tooltipOffsetX = tonumber(options.tooltipOffsetX) or 5
    local maxWidth = layout.maxWidth
    local boxWidth = maxWidth + (MEE_MIL_TEXT_PADDING * 2)
    local boxHeight = layout.titleHeight + layout.descriptionHeight + (MEE_MIL_VERTICAL_PADDING * 3) + MEE_MIL_BOTTOM_PADDING + (tooltipPadding * 2)
    local anchorY = math.floor((moodleSize - boxHeight) / 2)
    local boxX = moodleX - boxWidth - tooltipOffsetX
    local boxY = meeMILClampTooltipY(moodleY + anchorY, boxHeight, self.playerNum)
    local textLeftX = boxX + MEE_MIL_TEXT_PADDING
    local textRightX = boxX + boxWidth - MEE_MIL_TEXT_PADDING
    local textY = boxY + MEE_MIL_VERTICAL_PADDING + tooltipPadding

    self:drawRect(boxX, boxY, boxWidth, boxHeight, MEE_MIL_BG_A, 0, 0, 0)

    for i = 1, #titleLines do
        self:drawTextRight(titleLines[i], textRightX, textY, MEE_MIL_TITLE_R, MEE_MIL_TITLE_G, MEE_MIL_TITLE_B, MEE_MIL_TITLE_A, tooltipFont)
        textY = textY + fontHeight
    end

    textY = textY + MEE_MIL_VERTICAL_PADDING

    for i = 1, #descriptionLines do
        self:drawText(descriptionLines[i], textLeftX, textY, MEE_MIL_DESC_R, MEE_MIL_DESC_G, MEE_MIL_DESC_B, MEE_MIL_DESC_A, tooltipFont)
        textY = textY + fontHeight
    end

    return true
end

local function meePatchMoodlesInLuaTooltip()
    -- Patch the class method only after Moodles in Lua has defined it.
    if not ISMoodlesInLua or not ISMoodlesInLua.drawMoodleTooltip then
        return false
    end

    if ISMoodlesInLua.MEE_TooltipCompatPatched then
        return true
    end

    local originalDrawMoodleTooltip = ISMoodlesInLua.drawMoodleTooltip
    ISMoodlesInLua.MEE_OriginalDrawMoodleTooltip = originalDrawMoodleTooltip

    ISMoodlesInLua.drawMoodleTooltip = function(self, moodles, moodleIdOrType, moodleX, moodleY)
        -- Use the MEE tooltip when possible, but fall back to Moodles in Lua's
        -- original renderer if another mod or future MIL version changes the API.
        local ok, result = pcall(meeMILDrawTooltip, self, moodles, moodleIdOrType, moodleX, moodleY)

        if ok and result == true then
            return
        end

        return originalDrawMoodleTooltip(self, moodles, moodleIdOrType, moodleX, moodleY)
    end

    ISMoodlesInLua.MEE_TooltipCompatPatched = true
    return true
end

MEE.MoodlesInLuaCompat.PatchTooltip = meePatchMoodlesInLuaTooltip

-- If load order already made Moodles in Lua available, patch immediately.
meePatchMoodlesInLuaTooltip()

-- If MEE loads before Moodles in Lua, patch after all mods have loaded.
Events.OnGameStart.Add(meePatchMoodlesInLuaTooltip)
