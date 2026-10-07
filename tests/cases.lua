local instance = setmetatable({ active = false, playerNum = 0, defaultMoodleSize = 32,
    useCharacter = fixture.character }, { __index = MEEMoodlesLuaFallback })
instance.getWidth = function() return fixture.width or 0 end
instance.getHeight = function() return fixture.height or 0 end
instance.setWidth = function(_, value) fixture.width = value end
instance.setHeight = function(_, value) fixture.height = value end
instance.setVisible = function(_, value) fixture.visible = value end
instance.drawRect = function(_, x, y, width, height)
    fixture.rects[#fixture.rects + 1] = { x = x, y = y, width = width, height = height }
end
instance.drawText = function(_, text, x, y) fixture.text[#fixture.text + 1] = { text = text, y = y } end
instance.drawTextRight = instance.drawText
local iconRequests = 0
instance.getBackgroundTexture = function() iconRequests = iconRequests + 1; return nil end
instance.getBorderTexture = instance.getBackgroundTexture
instance.getIconTexture = instance.getBackgroundTexture
MEEMoodlesLuaFallback.instance = instance
local function frame()
    local nativeX = fixture.ui and fixture.ui:getX()
    local nativeY = fixture.ui and fixture.ui:getY()
    fixture.rects, fixture.text, fixture.drawnTypes = {}, {}, {}
    for _, callback in ipairs(Events.OnPreUIDraw.callbacks) do callback() end
    instance:render()
    check(iconRequests == 0, 'MEE attempted to draw its own Moodle column')
    if fixture.ui then
        check(fixture.ui:getX() == nativeX and fixture.ui:getY() == nativeY,
            'MEE moved the native Moodle root')
    end
end
local function refreshMods()
    Events.OnCreatePlayer.callbacks[1](0, fixture.character)
end
local function compareOrder(ui)
    local expected = nativeOrderFor(ui)
    local entries = instance:getExternalVisibleMoodleEntries(fixture.moodles, instance:getMoodleSize())
    check(entries ~= nil, 'native order unavailable')
    local visibleIndex = 0
    for index = 0, expected:size() - 1 do
        local moodleType = expected:get(index)
        local level = fixture.moodles:getMoodleLevel(moodleType)
        if level > 0 and (moodleType ~= MoodleType.FOOD_EATEN or level >= 3) then
            visibleIndex = visibleIndex + 1
            check(entries[visibleIndex] and entries[visibleIndex].moodleType == moodleType,
                'Java HashMap/native order mismatch at ' .. index)
            check(entries[visibleIndex].yOffset == (visibleIndex - 1) * (instance:getMoodleSize() + 10),
                'logical slot pitch mismatch')
        end
    end
    check(#entries == visibleIndex, 'unexpected visible entry count')
    return entries
end

local readOk, privateState = pcall(function() return probeUI.moodleUiState end)
check(not readOk or privateState == nil, 'test accidentally exposed private state')
local mapOk, mapResult = pcall(function()
    local mirror = HashMap.new()
    for index = 0, Registries.MOODLE_TYPE:values():size() - 1 do
        mirror:put(Registries.MOODLE_TYPE:values():get(index), true)
    end
    local keys = ArrayList.new(mirror:keySet())
    return keys:size() > 0 and keys:get(0) ~= nil
end)
check(mapOk and mapResult, 'exposed Java HashMap API failed: ' .. tostring(mapResult))
local entries = compareOrder(fixture.ui)
check(entries == instance:getExternalVisibleMoodleEntries(fixture.moodles, 32),
    'unchanged visible entries were reallocated')
for index = 1, math.min(#entries, 20) do
    fixture.mouseY = 120 + entries[index].yOffset + 5
    frame()
    check(#fixture.rects == 1 and #fixture.text == 6, 'multiline overlay did not draw')
    check(fixture.drawnTypes[1] == entries[index].moodleType, 'wrong hovered Moodle')
    check(fixture.rects[1].height == 130, 'six-line background height incorrect')
    check(hoverSlotFor(fixture.ui) == 1000, 'native hover was not suppressed')
    check(fixture.width == 0 and fixture.height == 0, 'overlay gained an interactive hitbox')
end

-- Default map capacity must be based on ALL registry keys, including invisible
-- ones. Filtering before insertion changes HashMap capacity/order.
for index = 0, probeNativeOrder:size() - 1 do
    local moodleType = probeNativeOrder:get(index)
    fixture.levels[tostring(moodleType)] = index % 3 == 0 and 4 or 0
end
fixture.levels[tostring(MoodleType.FOOD_EATEN)] = 2
compareOrder(fixture.ui)
fixture.levels[tostring(MoodleType.FOOD_EATEN)] = 3
entries = compareOrder(fixture.ui)
fixture.mouseY = 125
for font = 1, 3 do
    MEE.Options.TooltipFontSize = font
    frame()
    check(#fixture.rects == 1 and fixture.rects[1].height == 6 * font * 20 + 10,
        'configured font sizing incorrect')
    check(fixture.rects[1].y >= 0, 'tooltip not clamped at screen top')
end
MEE.Options.TooltipFontSize = 1
fixture.description = 'Line 1 <LINE> Line 2\nLine 3\r\nLine 4<br>Line 5'
frame()
check(#fixture.text == 6 and fixture.rects[1].height == 130, 'mixed newline normalization failed')

fixture.ui:setY(800.0)
fixture.mouseY = 805
frame()
check(#fixture.rects == 1 and fixture.text[1].y > 700, 'overlay ignored Hi-Res Y relocation')
fixture.ui:setY(1050.0)
fixture.mouseY = 1055
frame()
check(fixture.rects[1].y + fixture.rects[1].height <= 1080, 'bottom clamp failed')
fixture.ui:setY(120.0)
fixture.mouseY = 125

for _, sizeIndex in ipairs({ 1, 2, 3, 4, 5, 6, 7 }) do
    fixture.sizeIndex = sizeIndex
    fixture.fontSizeIndex = 3
    fixture.mouseX = 1910 - instance:getMoodleSize() + 5
    frame()
    check(#fixture.rects == 1, 'size/Auto-size hover failed')
end
fixture.sizeIndex, fixture.mouseX = 1, 1880

fixture.mouseX = 100
frame()
check(#fixture.rects == 0 and instance.externalTooltipContext == nil, 'off-column overlay remains')
fixture.mouseX, fixture.mouseY = 1880, 156
frame()
check(#fixture.rects == 1 and fixture.drawnTypes[1] == entries[1].moodleType,
    'Vanilla row-gap hover did not retain the same complete tooltip')
local previousContext = instance.externalTooltipContext
frame()
check(previousContext == instance.externalTooltipContext, 'unchanged hover context was reallocated')
fixture.mouseY = 125
fixture.ui:setVisible(false)
frame()
check(#fixture.rects == 0, 'invisible native UI produced a tooltip')
fixture.ui:setVisible(true)

MEE.Options.FallbackTooltipShadow = false
frame()
check(#fixture.rects == 0 and #fixture.text == 6 and instance.externalTooltipContext ~= nil,
    'shadow-off must retain MEE text/font/modes without a background')
MEE.Options.FallbackTooltipShadow = true
fixture.activeIds = { probeHiResID, 'PlainMoodles_by_Slobodskoy' }
refreshMods()
frame()
check(#fixture.rects == 0, 'Plain overlay blocker ignored')
fixture.activeIds = { probeHiResID }
refreshMods()
ISMoodlesInLua, ISMoodlesInLuaHandle = {}, { active = true }
frame()
check(#fixture.rects == 0, 'real Moodles-in-Lua renderer ignored')
ISMoodlesInLua, ISMoodlesInLuaHandle = nil, { active = true, hiResClockMoodleEffectsExplainedCompatibility = true }

local savedUi, savedMap = fixture.ui, HashMap
fixture.ui, HashMap = newNativeUI(), nil
frame()
check(#fixture.rects == 0 and instance.externalTooltipContext == nil, 'missing HashMap did not fail safely')
HashMap, fixture.ui = savedMap, newNativeUI()
compareOrder(fixture.ui)
fixture.ui = nil
frame()
check(#fixture.rects == 0, 'missing native UI did not fail safely')
fixture.ui = savedUi
compareOrder(fixture.ui)

-- A late registration is not inserted into the existing Java UI's state map.
-- The cached mirror must likewise keep the old snapshot until UI replacement.
local beforeCount = #instance:getExternalVisibleMoodleEntries(fixture.moodles, 32)
appendRegistryMoodle(probeLateType)
fixture.levels[tostring(probeLateType)] = 4
compareOrder(fixture.ui)
check(#instance:getExternalVisibleMoodleEntries(fixture.moodles, 32) == beforeCount,
    'late registry entry incorrectly added to existing column')
fixture.ui = newNativeUI()
compareOrder(fixture.ui)
check(#instance:getExternalVisibleMoodleEntries(fixture.moodles, 32) == beforeCount + 1,
    'replacement native UI did not rebuild cached order')

-- Standalone MEE must use the native column plus tooltip, with no icon renderer.
fixture.activeIds = {}
refreshMods()
ISMoodlesInLuaHandle = nil
instance.active = true
fixture.mouseX, fixture.mouseY = 1880, 125
frame()
check(#fixture.rects == 1 and #fixture.text == 6 and iconRequests == 0,
    'standalone MEE tooltip-only regression')

-- Execute the actual unmodified MEE description-mode implementation.
for mode, expectedLines in ipairs({ 6, 9, 2 }) do
    MEE.Options.TooltipDescriptionMode = mode
    frame()
    check(#fixture.text == expectedLines, 'native description mode was lost')
    check(fixture.rects[1].height == expectedLines * 20 + 10, 'description-mode background mismatch')
end
MEE.Options.TooltipDescriptionMode = 1

-- The actual unchanged Moodles-in-Lua bridge must still supply the tooltip
-- while the generic native overlay is inactive, regardless of class load order.
local originalCalls = 0
ISMoodlesInLua = { drawMoodleTooltip = function() originalCalls = originalCalls + 1 end }
ISMoodlesInLuaHandle = { active = true }
check(MEE.MoodlesInLuaCompat.PatchTooltip(), 'deferred real-renderer bridge failed')
local wrapped = ISMoodlesInLua.drawMoodleTooltip
check(MEE.MoodlesInLuaCompat.PatchTooltip() and ISMoodlesInLua.drawMoodleTooltip == wrapped,
    'foreign tooltip wrapped more than once')
frame()
check(#fixture.text == 0 and #fixture.rects == 0, 'native tooltip conflicts with foreign renderer')
local foreign = { getMoodleSize = function() return 32 end, playerNum = 0, options = {} }
foreign.drawRect, foreign.drawText, foreign.drawTextRight = instance.drawRect, instance.drawText, instance.drawTextRight
local moodleType = nativeOrderFor(fixture.ui):get(0)
fixture.levels[tostring(moodleType)] = 4
for mode, expectedLines in ipairs({ 6, 9, 2 }) do
    MEE.Options.TooltipDescriptionMode = mode
    fixture.rects, fixture.text = {}, {}
    ISMoodlesInLua.drawMoodleTooltip(foreign, fixture.moodles, moodleType, 1878, 120)
    check(#fixture.text == expectedLines and #fixture.rects == 1,
        'foreign renderer description/font/background mode was lost')
end
ISMoodlesInLua.drawMoodleTooltip(foreign, {}, moodleType, 1878, 120)
check(originalCalls == 1, 'foreign original-tooltip fallback was lost')

-- A foreign class created by a later OnGameStart handler must be patched by
-- bounded delayed discovery, for either confirmed renderer mod ID.
for _, rendererId in ipairs({ 'moodlesinlua', 'PZ_Moodles' }) do
    ISMoodlesInLua = nil
    fixture.activeIds, fixture.nowMs = { rendererId }, 0
    for _, callback in ipairs(Events.OnGameStart.callbacks) do callback() end
    check(#Events.OnTick.callbacks == 1, 'late renderer discovery not scheduled')
    Events.OnTick.callbacks[1]()
    fixture.nowMs = 1000
    ISMoodlesInLua = { drawMoodleTooltip = function() end }
    Events.OnTick.callbacks[1]()
    check(ISMoodlesInLua.MEE_TooltipCompatPatched and #Events.OnTick.callbacks == 0,
        'late foreign renderer was not patched or retry did not stop')
    ISMoodlesInLua = nil
    for _, callback in ipairs(Events.OnGameStart.callbacks) do callback() end
    for attempt = 1, 10 do
        fixture.nowMs = fixture.nowMs + 1000
        if Events.OnTick.callbacks[1] then Events.OnTick.callbacks[1]() end
    end
    check(#Events.OnTick.callbacks == 0, 'missing renderer discovery became a permanent tick poll')
end
