require "ISUI/ISUIElement"

--[[
    Moodle Effects Explained - Lua moodles fallback

    This file provides an internal moodles renderer that is only used when the
    separate "Moodles in Lua" mod is not active. It hides the vanilla Java
    moodles, redraws the moodles with vanilla textures, and draws a tooltip box
    whose height matches the translated description. The fallback tooltip font
    size and background shadow can be adjusted from this mod's client Mod
    Options.

    This avoids the fixed two-line tooltip height in vanilla MoodlesUI.java and
    works with both translation formats used by this mod:
    - B42.12 to B42.14: " <LINE> "
    - B42.15+: "<br>"
]]

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
local MEE_TOOLTIP_EXTRA_WIDTH = 12
local MEE_TOOLTIP_TEXT_PADDING = 10
local MEE_TOOLTIP_VERTICAL_PADDING = 2
local MEE_TOOLTIP_BOTTOM_PADDING = 4
local MEE_TOOLTIP_SCREEN_MARGIN = 0
local MEE_MOODLE_TOP_Y = 120
local MEE_DEFAULT_MOODLE_SIZE = 32
local MEE_FALLBACK_HITBOX_SIZE = 0
local MEE_MOODLE_SIZES = { [1] = 32, [2] = 48, [3] = 64, [4] = 80, [5] = 96, [6] = 128 }
local MEE_OSCILLATOR_SCALAR = 15.6
local MEE_OSCILLATOR_DECELERATOR = 0.16
local MEE_OSCILLATOR_RATE = 0.8
local MEE_GRAY = 0.5

local MEE_ICON_NAMES = {
    ["Endurance"] = "Status_DifficultyBreathing",
    ["Bleeding"] = "Status_Bleeding",
    ["Angry"] = "Mood_Angry",
    ["Stress"] = "Mood_Stressed",
    ["Thirst"] = "Status_Thirst",
    ["Panic"] = "Mood_Panicked",
    ["Hungry"] = "Status_Hunger",
    ["Injured"] = "Status_InjuredMinor",
    ["Pain"] = "Mood_Pained",
    ["Sick"] = "Mood_Nauseous",
    ["Bored"] = "Mood_Bored",
    ["Unhappy"] = "Mood_Sad",
    ["Tired"] = "Mood_Sleepy",
    ["HeavyLoad"] = "Status_HeavyLoad",
    ["Drunk"] = "Mood_Drunk",
    ["Wet"] = "Status_Wet",
    ["HasACold"] = "Mood_Ill",
    ["Dead"] = "Mood_Dead",
    ["Zombie"] = "Mood_Zombified",
    ["Windchill"] = "Status_Windchill",
    ["CantSprint"] = "Status_MovementRestricted",
    ["Uncomfortable"] = "Mood_Discomfort",
    ["NoxiousSmell"] = "Mood_NoxiousSmell",
    ["FoodEaten"] = "Status_Hunger",
    ["Hyperthermia"] = "Status_TemperatureHot",
    ["Hypothermia"] = "Status_TemperatureLow",
}

local MEE_HIDDEN_VANILLA = {}

local MEE_ACTIVATED_MODS_CACHE = {
    initialized = false,
    active = {},
}
local MEE_UI_CACHE_REFRESH_FRAMES = 30
local MEE_UI_CACHE = {
    frame = 0,
    uiListSize = -1,
    moodleUIs = {},
    canonicalMoodles = {},
}
local MEE_EXTERNAL_ORDER_CACHE_REFRESH_FRAMES = 30
local MEE_EXTERNAL_ORDER_CACHE = {
    frame = 0,
    playerNum = nil,
    resolvable = false,
}
local MEE_TOOLTIP_LAYOUT_CACHE_LIMIT = 128
local MEE_TOOLTIP_LAYOUT_CACHE = {}
local MEE_TOOLTIP_LAYOUT_CACHE_ORDER = {}
local MEE_MOODLE_TYPES_VALUES = nil
local MEE_MOODLE_TYPES_SIZE = 0

local function meeLerp(a, b, t)
    return a + (b - a) * t
end

local function meeGetHighlightColor(goodBadNeutral, moodleLevel)
    local factor = math.max(0, math.min(1, (tonumber(moodleLevel) or 0) / 4.0))
    local targetColor = nil

    if goodBadNeutral == 1 then
        targetColor = getCore():getGoodHighlitedColor()
    elseif goodBadNeutral == 2 then
        targetColor = getCore():getBadHighlitedColor()
    end

    if not targetColor then
        return MEE_GRAY, MEE_GRAY, MEE_GRAY
    end

    return
        meeLerp(MEE_GRAY, targetColor:getR(), factor),
        meeLerp(MEE_GRAY, targetColor:getG(), factor),
        meeLerp(MEE_GRAY, targetColor:getB(), factor)
end

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

local MEE_EXTERNAL_MOODLE_RENDERER_MOD_IDS = {
    ["Hi-Res-Clock"] = true,
    ["PlainMoodles_by_Slobodskoy"] = true,
}

local MEE_EXTERNAL_TOOLTIP_OVERLAY_MOD_IDS = {
    ["Hi-Res-Clock"] = true,
}

local MEE_EXTERNAL_TOOLTIP_OVERLAY_BLOCKER_MOD_IDS = {
    ["PlainMoodles_by_Slobodskoy"] = true,
}

local meeIsFallbackTooltipShadowEnabled

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

local function meeIsExternalMoodleRendererActive()
    -- Some HUD mods intentionally reposition, replace, or reconcile the vanilla
    -- Moodle UI. In that case MEE should keep its translated descriptions but
    -- avoid drawing a second fallback moodle row, preventing duplicate/overlapped
    -- moodles or covering another mod's level indicators.
    for modID, enabled in pairs(MEE_EXTERNAL_MOODLE_RENDERER_MOD_IDS) do
        if enabled == true and meeIsActivatedMod(modID) then
            return true
        end
    end

    return false
end

local function meeIsExternalTooltipOverlayRendererActive()
    -- Only enable MEE's tooltip-only overlay for external renderers whose visible
    -- moodle order can be followed safely from the Java MoodlesUI. Plain Moodles
    -- Redone draws its own fixed-order stack and already draws its own multiline
    -- tooltip, so MEE must not add a second tooltip layer for it.
    for modID, enabled in pairs(MEE_EXTERNAL_TOOLTIP_OVERLAY_BLOCKER_MOD_IDS) do
        if enabled == true and meeIsActivatedMod(modID) then
            return false
        end
    end

    for modID, enabled in pairs(MEE_EXTERNAL_TOOLTIP_OVERLAY_MOD_IDS) do
        if enabled == true and meeIsActivatedMod(modID) then
            return true
        end
    end

    return false
end

local function meeShouldUseFallbackRenderer()
    if meeIsMoodlesInLuaActive() then
        return false
    end

    if meeIsExternalMoodleRendererActive() then
        return false
    end

    return true
end

local function meeShouldUseExternalTooltipOverlay()
    -- When an external HUD mod such as Hi-Res Clock owns the moodle row, MEE
    -- should not redraw icons or hide the vanilla UI. It can still draw a
    -- tooltip-only overlay so multiline descriptions get a correctly sized
    -- shadow and use MEE's tooltip font option.
    --
    -- The overlay is intentionally tied to the shadow option. If the user
    -- disables the fallback tooltip background shadow, MEE leaves the external
    -- renderer's vanilla tooltip untouched instead of drawing a second layer.
    if not meeIsExternalTooltipOverlayRendererActive() then
        return false
    end

    if meeIsMoodlesInLuaActive() then
        return false
    end

    if not meeIsFallbackTooltipShadowEnabled() then
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

meeIsFallbackTooltipShadowEnabled = function()
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


local function meeRefreshVanillaMoodleUICache(force)
    -- Scanning UIManager.getUI() every frame is unnecessary and can be costly in
    -- large modlists. Rebuild the candidate list periodically or when the UI
    -- list size changes, then keep only those known MoodleUI objects suppressed.
    MEE_UI_CACHE.frame = (MEE_UI_CACHE.frame or 0) + 1

    local uiList = nil
    local uiListSize = -1
    local listOk = pcall(function()
        uiList = UIManager.getUI()
        if uiList and uiList.size then
            uiListSize = uiList:size()
        end
    end)

    if not listOk or not uiList or uiListSize < 0 then
        return MEE_UI_CACHE.moodleUIs or {}, MEE_UI_CACHE.canonicalMoodles or {}
    end

    if not force
            and uiListSize == MEE_UI_CACHE.uiListSize
            and (MEE_UI_CACHE.frame % MEE_UI_CACHE_REFRESH_FRAMES) ~= 0 then
        return MEE_UI_CACHE.moodleUIs or {}, MEE_UI_CACHE.canonicalMoodles or {}
    end

    local canonicalMoodles = {}
    if UIManager.getMoodleUI then
        for playerNum = 0, 3 do
            local ok, moodlesUI = pcall(function()
                return UIManager.getMoodleUI(playerNum)
            end)
            if ok and moodlesUI then
                canonicalMoodles[moodlesUI] = true
            end
        end
    end

    local moodleUIs = {}
    for i = 0, uiListSize - 1 do
        local readOk, ui = pcall(function()
            return uiList:get(i)
        end)
        if readOk and ui and tostring(ui):find("MoodlesUI", 1, true) then
            table.insert(moodleUIs, ui)
        end
    end

    MEE_UI_CACHE.uiListSize = uiListSize
    MEE_UI_CACHE.moodleUIs = moodleUIs
    MEE_UI_CACHE.canonicalMoodles = canonicalMoodles

    return moodleUIs, canonicalMoodles
end

local function meeHideVanillaMoodles()
    if not meeShouldUseFallbackRenderer() then
        return
    end

    local moodleUIs, canonicalMoodles = meeRefreshVanillaMoodleUICache(false)

    -- Vanilla ISHotbar:update() uses the canonical MoodlesUI visibility flag to
    -- restore the hotbar after the player leaves the driver's seat. Keep those
    -- canonical panels logically visible while moving them off-screen. Duplicate
    -- or orphaned MoodlesUI instances can still be hidden normally.
    for i = 1, #moodleUIs do
        local ui = moodleUIs[i]
        if ui then
            if ui.setVisible then
                ui:setVisible(canonicalMoodles[ui] == true)
            end
            if ui.setX and ui.setY then
                ui:setX(-4096)
                ui:setY(-4096)
            end
            MEE_HIDDEN_VANILLA[ui] = true
        end
    end
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


local function meeReadJavaField(object, fieldName)
    if not object then
        return nil
    end

    -- Try direct public/exposed-field access only. Kahlua does not expose
    -- java.lang.Class:getDeclaredField() in normal gameplay, and attempting to
    -- call it can produce repeated loop errors on every UI frame.
    --
    -- Private Java state such as MoodlesUI.moodleUiState is therefore optional:
    -- if it is not exposed directly by the runtime, MEE disables the external
    -- tooltip overlay instead of trying unsafe reflection. Public values such as
    -- MoodleUIData.slotsPos can still be read through this path when available.
    local ok, value = pcall(function()
        return object[fieldName]
    end)
    if ok and value ~= nil then
        return value
    end

    return nil
end

local function meeGetVanillaMoodleStateMap(playerNum)
    local moodleUI = meeGetVanillaMoodleUI(playerNum or 0)
    if not moodleUI then
        return nil
    end

    return meeReadJavaField(moodleUI, "moodleUiState")
end

local function meeCanResolveExternalMoodleOrder(playerNum)
    -- Cache the safe-order check. If a future external UI recreates MoodleUI
    -- after startup, the periodic refresh will pick it up without retrying the
    -- same field probe on every UI frame.
    local resolvedPlayerNum = playerNum or 0
    MEE_EXTERNAL_ORDER_CACHE.frame = (MEE_EXTERNAL_ORDER_CACHE.frame or 0) + 1

    if MEE_EXTERNAL_ORDER_CACHE.playerNum == resolvedPlayerNum
            and (MEE_EXTERNAL_ORDER_CACHE.frame % MEE_EXTERNAL_ORDER_CACHE_REFRESH_FRAMES) ~= 0 then
        return MEE_EXTERNAL_ORDER_CACHE.resolvable == true
    end

    local stateMap = meeGetVanillaMoodleStateMap(resolvedPlayerNum)
    local resolvable = stateMap ~= nil and stateMap.entrySet ~= nil

    MEE_EXTERNAL_ORDER_CACHE.playerNum = resolvedPlayerNum
    MEE_EXTERNAL_ORDER_CACHE.resolvable = resolvable

    return resolvable
end

local function meeSuppressExternalVanillaTooltip()
    -- In Hi-Res Clock compatibility mode, the Java Moodle UI can still draw its
    -- fixed two-line tooltip while MEE draws a multiline tooltip overlay. Reset
    -- the Java hover state just before UI rendering so only the MEE tooltip is
    -- visible when the overlay is enabled.
    --
    -- Only do this if MEE can read the Java MoodlesUI order. If reflection is
    -- blocked for any reason, leaving the vanilla tooltip visible is safer than
    -- suppressing it and drawing a tooltip for the wrong moodle.
    if not meeShouldUseExternalTooltipOverlay() then
        return
    end

    if not meeCanResolveExternalMoodleOrder(0) then
        return
    end

    local moodleUI = meeGetVanillaMoodleUI(0)
    if not moodleUI then
        return
    end

    pcall(function()
        moodleUI:onMouseMoveOutside(0, 0)
    end)
end

function MEEMoodlesLuaFallback:new()
    -- Keep this UI element non-interactive at the UIManager hit-test level.
    -- Drawing uses absolute screen coordinates, so the element does not need a
    -- real clickable area. A non-zero hitbox can block vanilla sidebar hover
    -- checks such as ISEquippedItem.movableBtn:isMouseOver().
    local o = ISUIElement:new(0, 0, MEE_FALLBACK_HITBOX_SIZE, MEE_FALLBACK_HITBOX_SIZE)
    setmetatable(o, self)
    self.__index = self

    o.defaultMoodleSize = MEE_DEFAULT_MOODLE_SIZE
    o.previousMoodleLevels = {}
    o.moodleOscillations = {}
    o.moodleOscillationSteps = {}
    o.textureCache = {}
    o.active = false
    o.useCharacter = nil
    o.playerNum = 0
    o.alpha = 1.0
    o.alphaIncrease = true

    return o
end

function MEEMoodlesLuaFallback:start()
    self.active = true
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
    -- Use the same entrySet() order that vanilla MoodlesUI uses to draw icons.
    -- Registries.MOODLE_TYPE order is not guaranteed to match the Java HashMap
    -- render order, which can otherwise make MEE show the tooltip for a
    -- different moodle when an external mod keeps the vanilla moodle row.
    local stateMap = meeGetVanillaMoodleStateMap(self.playerNum or 0)
    if stateMap == nil or stateMap.entrySet == nil then
        return nil
    end

    local ok, entrySet = pcall(function()
        return stateMap:entrySet()
    end)
    if not ok or entrySet == nil or entrySet.iterator == nil then
        return nil
    end

    local iteratorOk, iterator = pcall(function()
        return entrySet:iterator()
    end)
    if not iteratorOk or iterator == nil then
        return nil
    end

    local entries = {}
    local fallbackSlot = 0
    local moodleDistY = (tonumber(moodleSize) or self.defaultMoodleSize or MEE_DEFAULT_MOODLE_SIZE) + 10

    while true do
        local hasNextOk, hasNext = pcall(function()
            return iterator:hasNext()
        end)
        if not hasNextOk or not hasNext then
            break
        end

        local nextOk, entry = pcall(function()
            return iterator:next()
        end)
        if nextOk and entry ~= nil then
            local keyOk, moodleType = pcall(function()
                return entry:getKey()
            end)
            local valueOk, moodleUIData = pcall(function()
                return entry:getValue()
            end)

            if keyOk and moodleType ~= nil then
                local moodleLevel = moodles:getMoodleLevel(moodleType)
                if self:isVisibleMoodle(moodles, moodleType, moodleLevel) then
                    local slotsPos = nil
                    if valueOk and moodleUIData ~= nil then
                        slotsPos = tonumber(meeReadJavaField(moodleUIData, "slotsPos"))
                    end
                    if slotsPos == nil or slotsPos >= 9000 then
                        slotsPos = fallbackSlot * moodleDistY
                    end

                    table.insert(entries, {
                        moodleType = moodleType,
                        yOffset = slotsPos,
                    })
                    fallbackSlot = fallbackSlot + 1
                end
            end
        end
    end

    return entries
end

function MEEMoodlesLuaFallback:getCachedMoodleTypes()
    -- Registry moodle types are stable during a session. Cache the Java list so
    -- fallback rendering does not call Registries.MOODLE_TYPE:values() each frame.
    if MEE_MOODLE_TYPES_VALUES ~= nil then
        return MEE_MOODLE_TYPES_VALUES, MEE_MOODLE_TYPES_SIZE
    end

    if not Registries or not Registries.MOODLE_TYPE or not Registries.MOODLE_TYPE.values then
        return nil, 0
    end

    local ok, moodleTypes = pcall(function()
        return Registries.MOODLE_TYPE:values()
    end)

    if not ok or not moodleTypes then
        return nil, 0
    end

    local sizeOk, size = pcall(function()
        return moodleTypes:size()
    end)

    MEE_MOODLE_TYPES_VALUES = moodleTypes
    MEE_MOODLE_TYPES_SIZE = (sizeOk and tonumber(size)) or 0

    return MEE_MOODLE_TYPES_VALUES, MEE_MOODLE_TYPES_SIZE
end

function MEEMoodlesLuaFallback:getTexture(path)
    if not self.textureCache[path] then
        self.textureCache[path] = getTexture(path)
    end
    return self.textureCache[path]
end

function MEEMoodlesLuaFallback:getBackgroundTexture(size)
    return self:getTexture(string.format("media/ui/Moodles/%d/_Moodles_BGsolid.png", size))
end

function MEEMoodlesLuaFallback:getBorderTexture(size)
    return self:getTexture(string.format("media/ui/Moodles/%d/_Moodles_BGoutline.png", size))
end

function MEEMoodlesLuaFallback:getIconTexture(size, moodleType)
    local iconName = MEE_ICON_NAMES[tostring(moodleType:getTranslationName())]
    if not iconName then
        return nil
    end

    return self:getTexture(string.format("media/ui/Moodles/%d/%s.png", size, iconName))
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

function MEEMoodlesLuaFallback:updateBlinkAlpha(moodleType)
    local blinkingMoodle = getCore():getBlinkingMoodle()

    if blinkingMoodle and tostring(moodleType) == tostring(blinkingMoodle) then
        local fps = getPerformance():getUIRenderFPS() or 30
        if fps <= 0 then fps = 30 end

        if self.alphaIncrease then
            self.alpha = self.alpha + 0.1 * (30.0 / fps)
            if self.alpha > 1.0 then
                self.alpha = 1.0
                self.alphaIncrease = false
            end
        else
            self.alpha = self.alpha - 0.1 * (30.0 / fps)
            if self.alpha < 0.0 then
                self.alpha = 0.0
                self.alphaIncrease = true
            end
        end
    else
        self.alpha = 1.0
    end
end

function MEEMoodlesLuaFallback:updateOscillation(moodleKey, moodleLevel, previousLevel)
    if moodleLevel ~= previousLevel and moodleLevel >= 1 then
        self.moodleOscillations[moodleKey] = 1
    end

    local deltaTime = UIManager.getMillisSinceLastUpdate() / 1000
    local oscillationDeltaTime = deltaTime * 33.3333
    if not oscillationDeltaTime or oscillationDeltaTime <= 0 then
        oscillationDeltaTime = 1
    end

    local moodleOscillation = self.moodleOscillations[moodleKey] or 0
    if moodleOscillation <= 0 then
        return 0
    end

    self.moodleOscillations[moodleKey] = moodleOscillation - moodleOscillation * MEE_OSCILLATOR_DECELERATOR / oscillationDeltaTime
    if self.moodleOscillations[moodleKey] <= 0.015 then
        self.moodleOscillations[moodleKey] = 0
        return 0
    end

    local step = self.moodleOscillationSteps[moodleKey] or 0
    step = step + MEE_OSCILLATOR_RATE / oscillationDeltaTime
    self.moodleOscillationSteps[moodleKey] = step

    return math.sin(step) * MEE_OSCILLATOR_SCALAR * self.moodleOscillations[moodleKey] * 2
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

    if meeIsFallbackTooltipShadowEnabled() then
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
    local fallbackRendererActive = meeShouldUseFallbackRenderer()
    local externalTooltipOverlayActive = meeShouldUseExternalTooltipOverlay()

    if not self.active and not externalTooltipOverlayActive then return end
    if not fallbackRendererActive and not externalTooltipOverlayActive then return end

    local character = self.useCharacter or getSpecificPlayer(self.playerNum) or getPlayer()
    if not character or not character.getMoodles or not character:getMoodles() then return end

    local moodles = character:getMoodles()
    local moodleSize = self:getMoodleSize()
    local moodleDistY = moodleSize + 10
    local x = getPlayerScreenLeft(self.playerNum) + getPlayerScreenWidth(self.playerNum) - 10 - moodleSize
    local y = getPlayerScreenTop(self.playerNum) + MEE_MOODLE_TOP_Y

    if externalTooltipOverlayActive then
        local externalX, externalY = self:getExternalMoodleStackOrigin(moodleSize)
        if not externalX or not externalY then
            return
        end
        x = externalX
        y = externalY
    end

    local mouseX = getMouseX()
    local mouseY = getMouseY()

    -- Keep the UI element anchored at screen origin with a zero-sized hitbox.
    -- The drawing calls below use absolute screen coordinates. Expanding this
    -- element would make it participate in UI hit testing and can block hover
    -- detection for vanilla sidebar buttons.
    if self:getWidth() ~= MEE_FALLBACK_HITBOX_SIZE then
        self:setWidth(MEE_FALLBACK_HITBOX_SIZE)
    end
    if self:getHeight() ~= MEE_FALLBACK_HITBOX_SIZE then
        self:setHeight(MEE_FALLBACK_HITBOX_SIZE)
    end

    if externalTooltipOverlayActive then
        -- Do not inspect the Java MoodleUI order unless the mouse is actually
        -- over the external moodle column. This keeps the overlay path cheap
        -- during normal play when no tooltip is being requested.
        if mouseX < x or mouseX > x + moodleSize then
            return
        end

        local externalEntries = self:getExternalVisibleMoodleEntries(moodles, moodleSize)
        if not externalEntries then
            return
        end

        for i = 1, #externalEntries do
            local entry = externalEntries[i]
            local moodleY = y + (tonumber(entry.yOffset) or ((i - 1) * moodleDistY))
            if mouseX >= x and mouseX <= x + moodleSize and mouseY >= moodleY and mouseY <= moodleY + moodleSize then
                self:drawTooltip(moodles, entry.moodleType, x, moodleY, moodleSize)
                return
            end
        end

        return
    end

    local moodleTypes, numMoodles = self:getCachedMoodleTypes()
    if not moodleTypes or numMoodles <= 0 then
        return
    end

    for moodleIndex = 0, numMoodles - 1 do
        local moodleType = moodleTypes:get(moodleIndex)
        local moodleLevel = moodles:getMoodleLevel(moodleType)

        if self:isVisibleMoodle(moodles, moodleType, moodleLevel) then
            local moodleKey = tostring(moodleType)
            local previousLevel = self.previousMoodleLevels[moodleKey] or 0
            self.previousMoodleLevels[moodleKey] = moodleLevel

            local wiggleOffset = 0

            if fallbackRendererActive then
                wiggleOffset = self:updateOscillation(moodleKey, moodleLevel, previousLevel)
                self:updateBlinkAlpha(moodleType)

                local backgroundTexture = self:getBackgroundTexture(moodleSize)
                local borderTexture = self:getBorderTexture(moodleSize)
                local iconTexture = self:getIconTexture(moodleSize, moodleType)
                local goodBadNeutral = moodles:getGoodBadNeutral(moodleType)
                local bgR, bgG, bgB = meeGetHighlightColor(goodBadNeutral, moodleLevel)

                if backgroundTexture then
                    self:drawTexture(backgroundTexture, x + wiggleOffset, y, 1.0, bgR, bgG, bgB)
                end
                if borderTexture then
                    self:drawTexture(borderTexture, x + wiggleOffset, y, self.alpha)
                end
                if iconTexture then
                    self:drawTexture(iconTexture, x + wiggleOffset, y, self.alpha)
                end
            end

            if mouseX >= x and mouseX <= x + moodleSize and mouseY >= y and mouseY <= y + moodleSize then
                self:drawTooltip(moodles, moodleType, x, y, moodleSize)
            end

            y = y + moodleDistY
        end
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
    o:start()
    o:setCharacter(getSpecificPlayer(0) or getPlayer())
    MEEMoodlesLuaFallback.instance = o

    return o
end

local function meeOnCreatePlayer(playerIndex, playerObj)
    meeRefreshActivatedModsCache()
    local fallback = meeEnsureFallback()
    fallback:setCharacter(playerObj or getSpecificPlayer(playerIndex) or getPlayer())
    meeRefreshVanillaMoodleUICache(true)
end

local function meeMaintainExternalTooltipOverlay()
    -- Hi-Res Clock suppresses MEE's fallback instance to prevent a duplicated
    -- moodle row. Re-enable only the zero-hitbox UI element so MEE can draw a
    -- tooltip-only overlay without drawing icons or hiding vanilla moodles.
    if not meeShouldUseExternalTooltipOverlay() then
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
Events.OnPreUIDraw.Add(meeHideVanillaMoodles)
Events.OnPreUIDraw.Add(meeSuppressExternalVanillaTooltip)
Events.OnPreUIDraw.Add(meeMaintainExternalTooltipOverlay)
