require = function() end
ISUIElement = { derive = function() return {} end }
UIFont = { Small = 1, Medium = 2, Large = 3 }
MEE = { Options = { FallbackTooltipShadow = true, TooltipFontSize = 1 } }
ISMoodlesInLua = nil
ISMoodlesInLuaHandle = { active = true, hiResClockMoodleEffectsExplainedCompatibility = true }
probeChecks = 0
function check(condition, message)
    probeChecks = probeChecks + 1
    assert(condition, message)
end
fixture = {
    ui = probeUI, mouseX = 1880, mouseY = 130, activeIds = { probeHiResID },
    levels = {}, fontHeight = 20, description = 'Line 1<br>Line 2<br>Line 3<br>Line 4<br>Line 5',
    rects = {}, text = {}, drawnTypes = {}, registryReads = 0,
}
if probeHiResID == '(no Hi-Res)' then
    fixture.activeIds = {}
    ISMoodlesInLuaHandle = nil
end
getTextOrNull = function(key)
    if key == 'UI_MEE_VanillaDescriptionHeader' then return 'Vanilla:' end
    if tostring(key):find('MEE_Vanilla_Moodles_', 1, true) == 1 then return 'Vanilla line' end
    return nil
end
for index = 0, probeNativeOrder:size() - 1 do
    fixture.levels[tostring(probeNativeOrder:get(index))] = 4
end
Events = {}
for _, name in ipairs({ 'OnGameStart', 'OnCreatePlayer', 'OnPreUIDraw', 'OnTick' }) do
    local callbacks = {}
    Events[name] = { callbacks = callbacks, Add = function(callback) callbacks[#callbacks + 1] = callback end,
        Remove = function(callback) for i = #callbacks, 1, -1 do if callbacks[i] == callback then table.remove(callbacks, i) end end end }
end
getActivatedMods = function()
    return { size = function() return #fixture.activeIds end,
        get = function(_, index) return fixture.activeIds[index + 1] end }
end
local core = {
    getOptionMoodleSize = function() return fixture.sizeIndex or 1 end,
    getOptionFontSizeReal = function() return fixture.fontSizeIndex or 1 end,
    getScreenWidth = function() return 1920 end,
    getScreenHeight = function() return 1080 end,
    getBlinkingMoodle = function() return nil end,
}
getCore = function() return core end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenWidth = function() return 1920 end
getPlayerScreenTop = function() return fixture.screenTop or 0 end
getPlayerScreenHeight = function() return fixture.screenHeight or 1080 end
getMouseX = function() return fixture.mouseX end
getMouseY = function() return fixture.mouseY end
getTimestampMs = function() return fixture.nowMs or 0 end
getTextManager = function()
    return { getFontHeight = function(_, font) return font * 20 end,
        MeasureStringX = function(_, _, text) return #text * 8 end }
end
fixture.moodles = {
    getMoodleLevel = function(_, moodleType) return fixture.levels[tostring(moodleType)] or 0 end,
    getGoodBadNeutral = function() return 0 end,
    getMoodleDisplayString = function(_, moodleType)
        fixture.drawnTypes[#fixture.drawnTypes + 1] = moodleType
        return tostring(moodleType)
    end,
    getMoodleDescriptionString = function() return fixture.description end,
}
fixture.character = { getMoodles = function() return fixture.moodles end }
getSpecificPlayer = function() return fixture.character end
getPlayer = function() return fixture.character end
UIManager = { getMoodleUI = function() return fixture.ui end,
    getUI = function() return { size = function() return fixture.ui and 1 or 0 end,
        get = function() return fixture.ui end } end,
    getMillisSinceLastUpdate = function() return 100 end }
