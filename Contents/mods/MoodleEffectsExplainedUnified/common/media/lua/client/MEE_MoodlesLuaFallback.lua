require "ISUI/ISUIElement"
require "MEE/Profile"

-- MEE is a tooltip extension only. Native or foreign mods own Moodle icons,
-- animation, visibility and placement. Retain this historical class/singleton
-- name for existing Hi-Res compatibility code; it no longer renders a column.
MEEMoodlesLuaFallback = ISUIElement:derive("MEEMoodlesLuaFallback")

local MEE_TOOLTIP_FONTS = {
    [1] = UIFont.Small,
    [2] = UIFont.Medium,
    [3] = UIFont.Large,
}
local MEE_TOOLTIP_TITLE_R = 1.0
local MEE_TOOLTIP_TITLE_G = 1.0
local MEE_TOOLTIP_TITLE_B = 1.0
local MEE_TOOLTIP_TITLE_A = 1.0
local MEE_TOOLTIP_DESC_R = 0.8
local MEE_TOOLTIP_DESC_G = 0.8
local MEE_TOOLTIP_DESC_B = 0.8
local MEE_TOOLTIP_DESC_A = 1.0
local MEE_TOOLTIP_BG_A = 0.6
local MEE_TOOLTIP_RIGHT_OFFSET = 10
local MEE_TOOLTIP_TEXT_PADDING = 10
local MEE_TOOLTIP_VERTICAL_PADDING = 2
local MEE_TOOLTIP_BOTTOM_PADDING = 4
local MEE_TOOLTIP_SCREEN_MARGIN = 0

local MEE_DEFAULT_MOODLE_SIZE = 32
local MEE_FALLBACK_HITBOX_SIZE = 0
local MEE_MOODLE_SIZES = { [1] = 32, [2] = 48, [3] = 64, [4] = 80, [5] = 96, [6] = 128 }

local MEE_ACTIVATED_MODS_CACHE = {
    initialized = false,
    active = {},
}

local MEE_EXTERNAL_ORDER_CACHE = {
    moodleUI = nil,
    order = nil,
    visibility = {},
    entries = nil,
    moodles = nil,
    moodleSize = nil,
}
local MEE_TOOLTIP_LAYOUT_CACHE_LIMIT = 128
local MEE_TOOLTIP_LAYOUT_CACHE = {}
local MEE_TOOLTIP_LAYOUT_CACHE_ORDER = {}


local function meeIsHiResClockMoodlesInLuaBypassActive()
    -- Hi-Res Clock 2.0 creates a lightweight ISMoodlesInLuaHandle only to tell
    -- MEE not to draw a second moodle row. Treat that handle as an external UI
    -- compatibility boundary, not as a real Moodles in Lua renderer.
    local handle = rawget(_G, "ISMoodlesInLuaHandle")
    return type(handle) == "table"
            and handle.active == true
            and handle.hiResClockMoodleEffectsExplainedCompatibility == true
            and rawget(_G, "ISMoodlesInLua") == nil
end

local function meeIsMoodlesInLuaActive()
    if ISMoodlesInLuaHandle == nil or ISMoodlesInLuaHandle.active ~= true then
        return false
    end

    if meeIsHiResClockMoodlesInLuaBypassActive() then
        return false
    end

    return true
end


local function meeRefreshActivatedModsCache()
    -- Activated mods do not normally change during an active game session. Cache
    -- this list so per-frame UI paths do not repeatedly scan getActivatedMods().
    local active = {}

    if getActivatedMods then
        local ok, activatedMods = pcall(getActivatedMods)
        if ok and activatedMods then
            if activatedMods.size and activatedMods.get then
                local sizeOk, size = pcall(function()
                    return activatedMods:size()
                end)
                if sizeOk and size then
                    for i = 0, size - 1 do
                        local readOk, value = pcall(function()
                            return activatedMods:get(i)
                        end)
                        if readOk and value ~= nil then
                            active[tostring(value)] = true
                        end
                    end
                end
            end
        end
    end

    MEE_ACTIVATED_MODS_CACHE.active = active
    MEE_ACTIVATED_MODS_CACHE.initialized = true
end

local function meeIsActivatedMod(modID)
    -- Detect optional UI mods without requiring their Lua modules. Requiring an
    -- external module only to check compatibility can initialize it too early.
    if not MEE_ACTIVATED_MODS_CACHE.initialized then
        meeRefreshActivatedModsCache()
    end

    return MEE_ACTIVATED_MODS_CACHE.active[tostring(modID)] == true
end


local function meeShouldUseNativeTooltipOverlay()
    -- Real Lua renderers keep their column and use MEE_MoodlesInLuaCompat.
    -- Plain owns its own tooltip. Hi-Res's marked bypass is not a real renderer.
    if meeIsMoodlesInLuaActive() or meeIsActivatedMod("PlainMoodles_by_Slobodskoy") then
        return false
    end
    return true
end

local function meeNormalizeTooltipText(text)
    local normalized = tostring(text or "")

    -- PZ 42.20.1+ requires %% in JSON translations to display a literal %.
    -- Older B42 builds may return the doubled text unchanged, so collapse it
    -- at render time to keep one visible percent sign across supported builds.
    normalized = normalized:gsub("%%%%", "%%")

    -- Convert all supported line-break markers to real newlines.
    normalized = normalized:gsub("\r\n", "\n")
    normalized = normalized:gsub("\r", "\n")
    normalized = normalized:gsub("<br>", "\n")
    normalized = normalized:gsub(" <LINE> ", "\n")
    normalized = normalized:gsub("<LINE>", "\n")

    return normalized
end

local function meeSplitLines(text)
    local normalized = meeNormalizeTooltipText(text)
    local lines = {}

    normalized = normalized .. "\n"
    for line in normalized:gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    if #lines == 0 then
        table.insert(lines, "")
    end

    return lines
end

local function meeGetTooltipFont()
    -- Resolve the configured tooltip font, falling back to Small.
    local fontIndex = 1

    if MEE and MEE.Options and MEE.Options.TooltipFontSize then
        fontIndex = tonumber(MEE.Options.TooltipFontSize) or 1
    end

    return MEE_TOOLTIP_FONTS[fontIndex] or UIFont.Small
end

local function meeIsTooltipShadowEnabled()
    -- The background shadow can be disabled from Mod Options for compatibility.
    if MEE and MEE.Options and MEE.Options.FallbackTooltipShadow == false then
        return false
    end

    return true
end

local function meeGetFontHeight(font)
    return getTextManager():getFontHeight(font or UIFont.Small)
end

local function meeMeasureMaxLineWidth(lines, font)
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

local function meeCacheTooltipLayout(cacheKey, layout)
    if MEE_TOOLTIP_LAYOUT_CACHE[cacheKey] ~= nil then
        MEE_TOOLTIP_LAYOUT_CACHE[cacheKey] = layout
        return layout
    end

    MEE_TOOLTIP_LAYOUT_CACHE[cacheKey] = layout
    table.insert(MEE_TOOLTIP_LAYOUT_CACHE_ORDER, cacheKey)

    while #MEE_TOOLTIP_LAYOUT_CACHE_ORDER > MEE_TOOLTIP_LAYOUT_CACHE_LIMIT do
        local oldestKey = table.remove(MEE_TOOLTIP_LAYOUT_CACHE_ORDER, 1)
        if oldestKey then
            MEE_TOOLTIP_LAYOUT_CACHE[oldestKey] = nil
        end
    end

    return layout
end

local function meeGetTooltipLayout(title, description, font)
    -- Tooltip text and font normally repeat for the same moodle/level. Cache the
    -- split lines and measured width so hovering does not re-measure every frame.
    local cacheKey = tostring(font or UIFont.Small)
            .. "\31" .. tostring(title or "")
            .. "\31" .. tostring(description or "")

    local cached = MEE_TOOLTIP_LAYOUT_CACHE[cacheKey]
    if cached ~= nil then
        return cached
    end

    local titleLines = meeSplitLines(title)
    local descriptionLines = meeSplitLines(description)
    local allLines = {}

    for i = 1, #titleLines do
        table.insert(allLines, titleLines[i])
    end
    for i = 1, #descriptionLines do
        table.insert(allLines, descriptionLines[i])
    end

    local fontHeight = meeGetFontHeight(font)
    local maxWidth = meeMeasureMaxLineWidth(allLines, font)

    return meeCacheTooltipLayout(cacheKey, {
        titleLines = titleLines,
        descriptionLines = descriptionLines,
        fontHeight = fontHeight,
        maxWidth = maxWidth,
        titleHeight = #titleLines * fontHeight,
        descriptionHeight = #descriptionLines * fontHeight,
    })
end

local function meeGetPlayerScreenVerticalBounds(playerNum)
    -- Prefer the player's viewport bounds when available, so split-screen keeps
    -- tooltip clamping inside the correct visible area.
    local screenTop = 0
    local screenHeight = getCore():getScreenHeight()

    if getPlayerScreenTop and getPlayerScreenHeight then
        screenTop = getPlayerScreenTop(playerNum or 0) or screenTop
        screenHeight = getPlayerScreenHeight(playerNum or 0) or screenHeight
    end

    return screenTop, screenTop + screenHeight
end

local function meeClampTooltipY(boxY, boxHeight, playerNum)
    -- Keep the tooltip inside the visible screen for every configured font size.
    -- Large fonts and long translations can make the box taller than the moodle
    -- icon, so anchoring it vertically around the icon may otherwise push it off
    -- the top edge of the screen.
    local screenTop, screenBottom = meeGetPlayerScreenVerticalBounds(playerNum)
    local minY = screenTop + MEE_TOOLTIP_SCREEN_MARGIN
    local maxY = screenBottom - boxHeight - MEE_TOOLTIP_SCREEN_MARGIN

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



local function meeGetVanillaMoodleUI(playerNum)
    -- Resolve the real Java Moodle UI managed by vanilla or external HUD mods.
    -- Hi-Res Clock moves this element vertically, so tooltip overlay hit-tests
    -- must follow its current position instead of the original vanilla Y value.
    if not UIManager or not UIManager.getMoodleUI then
        return nil
    end

    local ok, moodleUI = pcall(function()
        return UIManager.getMoodleUI(playerNum or 0)
    end)

    if ok then
        return moodleUI
    end

    return nil
end

local function meeCallNumber(object, methodName)
    if not object then
        return nil
    end

    -- Call known UI accessors explicitly. Java-backed objects sometimes expose
    -- methods for colon calls without making dynamic table lookup reliable.
    local ok, value = pcall(function()
        if methodName == "getAbsoluteX" and object.getAbsoluteX then
            return object:getAbsoluteX()
        elseif methodName == "getAbsoluteY" and object.getAbsoluteY then
            return object:getAbsoluteY()
        elseif methodName == "getX" and object.getX then
            return object:getX()
        elseif methodName == "getY" and object.getY then
            return object:getY()
        end
        return nil
    end)

    if ok then
        return tonumber(value)
    end

    return nil
end


local function meeGetExternalMoodleOrder(moodleUI)
    if not moodleUI then return nil end
    if MEE_EXTERNAL_ORDER_CACHE.moodleUI == moodleUI then
        return MEE_EXTERNAL_ORDER_CACHE.order
    end

    MEE_EXTERNAL_ORDER_CACHE.moodleUI = moodleUI
    MEE_EXTERNAL_ORDER_CACHE.order = nil
    MEE_EXTERNAL_ORDER_CACHE.visibility = {}
    MEE_EXTERNAL_ORDER_CACHE.entries = nil
    MEE_EXTERNAL_ORDER_CACHE.moodles = nil

    -- B42.20+ MoodlesUI constructs a default Java HashMap, then inserts every
    -- Registries.MOODLE_TYPE value in registry order. Repeating those exact
    -- insertions with the SAME Java keys reproduces its key iteration order.
    -- Iterating the registry itself does not. No private fields, debug-only
    -- reflection helpers, copied Java hash algorithm, or Java mod are needed.
    -- Cache the snapshot per native UI identity, just as Vanilla does; do not
    -- silently add late registry entries to an already existing native column.
    if not HashMap or not HashMap.new or not ArrayList or not ArrayList.new or not Registries
            or not Registries.MOODLE_TYPE then
        return nil
    end

    local ok, order = pcall(function()
        local values = Registries.MOODLE_TYPE:values()
        local mirror = HashMap.new()
        for index = 0, values:size() - 1 do
            local moodleType = values:get(index)
            mirror:put(moodleType, true)
        end

        local result = {}
        -- ArrayList(Collection) reads the Java Set internally. Its public
        -- size/get accessors avoid depending on unexposed HashMap$KeySet APIs.
        local keys = ArrayList.new(mirror:keySet())
        for index = 0, keys:size() - 1 do
            result[#result + 1] = keys:get(index)
        end
        return result
    end)

    if ok then MEE_EXTERNAL_ORDER_CACHE.order = order end
    return MEE_EXTERNAL_ORDER_CACHE.order
end

local function meeSuppressExternalVanillaTooltip()
    local fallback = MEEMoodlesLuaFallback.instance
    if not fallback then return end
    local previousContext = fallback.externalTooltipContext
    fallback.externalTooltipContext = nil
    if not meeShouldUseNativeTooltipOverlay() then return end

    -- Prepare one exact hover result before suppressing Vanilla. Rendering
    -- consumes this same result, so a missing UI/API/order never leaves the
    -- player without a tooltip. Do not scan the registry outside the column.
    local ok, context = pcall(function()
        local moodleUI = meeGetVanillaMoodleUI(fallback.playerNum or 0)
        if not moodleUI or not moodleUI:isVisible() then return nil end
        local moodleSize = fallback:getMoodleSize()
        local x, y = fallback:getExternalMoodleStackOrigin(moodleSize)
        if not x or not y then return nil end
        local mouseX, mouseY = getMouseX(), getMouseY()
        if mouseX < x or mouseX > x + moodleSize or mouseY < y then
            return nil
        end

        local character = fallback.useCharacter
                or getSpecificPlayer(fallback.playerNum) or getPlayer()
        if not character or not character:getMoodles() then return nil end
        local moodles = character:getMoodles()
        local entries = fallback:getExternalVisibleMoodleEntries(moodles, moodleSize)
        if not entries then return nil end

        for index = 1, #entries do
            local entry = entries[index]
            local moodleY = y + entry.yOffset
            -- Vanilla hover slots include the 10-pixel gap below each icon.
            if mouseY >= moodleY and mouseY < moodleY + moodleSize + 10 then
                if previousContext and previousContext.moodleUI == moodleUI
                        and previousContext.moodles == moodles
                        and previousContext.moodleType == entry.moodleType
                        and previousContext.x == x and previousContext.y == moodleY
                        and previousContext.moodleSize == moodleSize then
                    return previousContext
                end
                return { moodleUI = moodleUI, moodles = moodles,
                    moodleType = entry.moodleType, x = x, y = moodleY,
                    moodleSize = moodleSize }
            end
        end
        return nil
    end)

    if not ok or not context then return end
    local suppressed = pcall(function()
        context.moodleUI:onMouseMoveOutside(0, 0)
    end)
    if suppressed then fallback.externalTooltipContext = context end
end


function MEEMoodlesLuaFallback:new()
    local o = ISUIElement:new(0, 0, MEE_FALLBACK_HITBOX_SIZE, MEE_FALLBACK_HITBOX_SIZE)
    setmetatable(o, self)
    self.__index = self
    o.defaultMoodleSize = MEE_DEFAULT_MOODLE_SIZE
    o.active = true -- Legacy status only; tooltip drawing never depends on it.
    o.useCharacter = nil
    o.playerNum = 0
    return o
end

function MEEMoodlesLuaFallback:setCharacter(character)
    self.useCharacter = character
    if character and character.getPlayerNum then
        self.playerNum = character:getPlayerNum()
    else
        self.playerNum = 0
    end
end

function MEEMoodlesLuaFallback:getMoodleSize()
    local moodleSizeIndex = getCore():getOptionMoodleSize()

    -- Match the vanilla auto-size behavior when the option is set to Auto.
    if moodleSizeIndex == 7 then
        local fontSizeIndex = getCore():getOptionFontSizeReal()
        return MEE_MOODLE_SIZES[fontSizeIndex] or self.defaultMoodleSize
    end

    return MEE_MOODLE_SIZES[moodleSizeIndex] or self.defaultMoodleSize
end


function MEEMoodlesLuaFallback:getExternalMoodleStackOrigin(moodleSize)
    -- Use the live Java Moodle UI position when an external HUD mod owns the
    -- moodle row. This prevents MEE from hit-testing the original vanilla row
    -- position while Hi-Res Clock has moved the visible moodles elsewhere.
    local moodleUI = meeGetVanillaMoodleUI(self.playerNum or 0)
    if not moodleUI then
        return nil, nil
    end

    local uiX = meeCallNumber(moodleUI, "getAbsoluteX") or meeCallNumber(moodleUI, "getX")
    local uiY = meeCallNumber(moodleUI, "getAbsoluteY") or meeCallNumber(moodleUI, "getY")

    if not uiX or not uiY then
        return nil, nil
    end

    local screenLeft = getPlayerScreenLeft(self.playerNum) or 0
    local screenWidth = getPlayerScreenWidth(self.playerNum) or getCore():getScreenWidth()
    local screenRight = screenLeft + screenWidth
    local size = tonumber(moodleSize) or self.defaultMoodleSize or MEE_DEFAULT_MOODLE_SIZE

    -- Vanilla MoodlesUI stores X near the right edge and draws the icon using
    -- texture offsets. Some Lua/UI mods may store the visible left edge instead.
    -- If the resolved X is too close to the right edge to fit the icon, treat it
    -- as the vanilla right-edge anchor and convert it to a visible left edge.
    if uiX > screenRight - size then
        uiX = uiX - size
    end

    return math.floor(uiX), math.floor(uiY)
end


function MEEMoodlesLuaFallback:getExternalVisibleMoodleEntries(moodles, moodleSize)
    local moodleUI = meeGetVanillaMoodleUI(self.playerNum or 0)
    local order = meeGetExternalMoodleOrder(moodleUI)
    if not order then return nil end

    local cache = MEE_EXTERNAL_ORDER_CACHE
    local changed = cache.entries == nil or cache.moodles ~= moodles
            or cache.moodleSize ~= moodleSize
    for index = 1, #order do
        local moodleType = order[index]
        local visible = self:isVisibleMoodle(moodles, moodleType, moodles:getMoodleLevel(moodleType))
        if cache.visibility[index] ~= visible then changed = true end
    end
    if not changed then return cache.entries end

    local entries, visibility = {}, {}
    local moodleDistY = (tonumber(moodleSize) or self.defaultMoodleSize
            or MEE_DEFAULT_MOODLE_SIZE) + 10
    for index = 1, #order do
        local moodleType = order[index]
        local moodleLevel = moodles:getMoodleLevel(moodleType)
        visibility[index] = self:isVisibleMoodle(moodles, moodleType, moodleLevel)
        if visibility[index] then
            -- Vanilla mouseOverSlot follows the logical row (size + 10), not
            -- the transient animated slotsPos of a newly appearing icon.
            entries[#entries + 1] = {
                moodleType = moodleType,
                yOffset = #entries * moodleDistY,
            }
        end
    end
    cache.visibility, cache.entries = visibility, entries
    cache.moodles, cache.moodleSize = moodles, moodleSize
    return entries
end


function MEEMoodlesLuaFallback:isVisibleMoodle(moodles, moodleType, moodleLevel)
    if moodleLevel <= 0 then
        return false
    end

    -- Food Eaten stays hidden until level 3, matching vanilla.
    if moodleType == MoodleType.FOOD_EATEN and moodleLevel < 3 then
        return false
    end

    return true
end


function MEEMoodlesLuaFallback:drawTooltip(moodles, moodleType, moodleX, moodleY, moodleSize)
    local title = tostring(moodles:getMoodleDisplayString(moodleType) or "")
    local meeDescription = tostring(moodles:getMoodleDescriptionString(moodleType) or "")
    local description = meeDescription
    if MEE and MEE.GetMoodleTooltipDescription then
        description = MEE.GetMoodleTooltipDescription(moodles, moodleType, meeDescription)
    end
    local tooltipFont = meeGetTooltipFont()
    local layout = meeGetTooltipLayout(title, description, tooltipFont)
    local titleLines = layout.titleLines
    local descriptionLines = layout.descriptionLines
    local fontHgt = layout.fontHeight
    local maxWidth = layout.maxWidth
    local boxWidth = maxWidth + (MEE_TOOLTIP_TEXT_PADDING * 2)
    local boxHeight = layout.titleHeight + layout.descriptionHeight + (MEE_TOOLTIP_VERTICAL_PADDING * 3) + MEE_TOOLTIP_BOTTOM_PADDING
    local anchorY = math.floor((moodleSize - boxHeight) / 2)
    local boxX = moodleX - MEE_TOOLTIP_RIGHT_OFFSET - maxWidth - MEE_TOOLTIP_TEXT_PADDING
    local boxY = meeClampTooltipY(moodleY + anchorY, boxHeight, self.playerNum)
    local textLeftX = boxX + MEE_TOOLTIP_TEXT_PADDING
    local textRightX = boxX + boxWidth - MEE_TOOLTIP_TEXT_PADDING
    local textY = boxY + MEE_TOOLTIP_VERTICAL_PADDING

    if meeIsTooltipShadowEnabled() then
        self:drawRect(boxX, boxY, boxWidth, boxHeight, MEE_TOOLTIP_BG_A, 0, 0, 0)
    end

    for i = 1, #titleLines do
        self:drawTextRight(titleLines[i], textRightX, textY, MEE_TOOLTIP_TITLE_R, MEE_TOOLTIP_TITLE_G, MEE_TOOLTIP_TITLE_B, MEE_TOOLTIP_TITLE_A, tooltipFont)
        textY = textY + fontHgt
    end

    textY = textY + MEE_TOOLTIP_VERTICAL_PADDING

    for i = 1, #descriptionLines do
        self:drawText(descriptionLines[i], textLeftX, textY, MEE_TOOLTIP_DESC_R, MEE_TOOLTIP_DESC_G, MEE_TOOLTIP_DESC_B, MEE_TOOLTIP_DESC_A, tooltipFont)
        textY = textY + fontHgt
    end
end


function MEEMoodlesLuaFallback:render()
    if not meeShouldUseNativeTooltipOverlay() then return end
    local context = self.externalTooltipContext
    if context then
        self:drawTooltip(context.moodles, context.moodleType,
                context.x, context.y, context.moodleSize)
    end
end

local function meeEnsureFallback()
    meeRefreshActivatedModsCache()

    if MEEMoodlesLuaFallback.instance then
        return MEEMoodlesLuaFallback.instance
    end

    local o = MEEMoodlesLuaFallback:new()
    o:initialise()
    o:instantiate()
    o.javaObject:setConsumeMouseEvents(false)
    o:addToUIManager()
    o:setCharacter(getSpecificPlayer(0) or getPlayer())
    MEEMoodlesLuaFallback.instance = o

    if meeShouldUseNativeTooltipOverlay() then
        meeGetExternalMoodleOrder(meeGetVanillaMoodleUI(o.playerNum or 0))
    end

    return o
end

local function meeOnCreatePlayer(playerIndex, playerObj)
    meeRefreshActivatedModsCache()
    local fallback = meeEnsureFallback()
    fallback:setCharacter(playerObj or getSpecificPlayer(playerIndex) or getPlayer())
    -- Capture normal startup registration as soon as the native UI is ready,
    -- rather than waiting for the first mouse hover.
    if meeShouldUseNativeTooltipOverlay() then
        meeGetExternalMoodleOrder(meeGetVanillaMoodleUI(fallback.playerNum or 0))
    end
end

local function meeMaintainExternalTooltipOverlay()
    -- Re-enable the non-interactive tooltip carrier after legacy Hi-Res
    -- suppression. Native/foreign Moodle roots are never hidden or moved.
    if not meeShouldUseNativeTooltipOverlay() then
        return
    end

    local fallback = MEEMoodlesLuaFallback.instance
    if not fallback then
        return
    end

    if fallback.setVisible then
        fallback:setVisible(true)
    end
    fallback:setWidth(MEE_FALLBACK_HITBOX_SIZE)
    fallback:setHeight(MEE_FALLBACK_HITBOX_SIZE)
end

Events.OnGameStart.Add(meeEnsureFallback)
Events.OnCreatePlayer.Add(meeOnCreatePlayer)
Events.OnPreUIDraw.Add(meeSuppressExternalVanillaTooltip)
Events.OnPreUIDraw.Add(meeMaintainExternalTooltipOverlay)
