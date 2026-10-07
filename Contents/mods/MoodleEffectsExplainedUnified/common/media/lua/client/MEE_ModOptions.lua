pcall(require, "PZAPI/ModOptions")

--[[
    Moodle Effects Explained - client ModOptions

    These options are client-side only. They control the internal Lua moodle
    tooltip renderer used by this mod when the separate "Moodles in Lua" mod is
    not active and no known external moodle renderer is managing the vanilla moodle row. If Moodles in Lua is active, MEE can also apply its tooltip font
    size to Moodles in Lua through the optional compatibility patch.
]]

MEE = MEE or {}
MEE.Options = MEE.Options or {}

local MEE_MOD_OPTIONS_ID = "MoodleEffectsExplained"
local MEE_DEFAULT_TOOLTIP_FONT_SIZE = 1 -- 1 = Small, 2 = Medium, 3 = Large
local MEE_DEFAULT_FALLBACK_TOOLTIP_SHADOW = true
local MEE_DEFAULT_TOOLTIP_DESCRIPTION_MODE = 1 -- 1 = MEE, 2 = MEE + Vanilla, 3 = Vanilla

MEE.Options.TooltipFontSize = MEE.Options.TooltipFontSize or MEE_DEFAULT_TOOLTIP_FONT_SIZE
MEE.Options.FallbackTooltipShadow = MEE.Options.FallbackTooltipShadow ~= false
MEE.Options.TooltipDescriptionMode = MEE.Options.TooltipDescriptionMode or MEE_DEFAULT_TOOLTIP_DESCRIPTION_MODE
MEE.DescriptionCache = MEE.DescriptionCache or {}

function MEE.ResetDescriptionCache()
    MEE.DescriptionCache = {}
end

local function meeClampTooltipFontSize(value)
    -- Keep saved values inside the supported combo range.
    local numericValue = tonumber(value) or MEE_DEFAULT_TOOLTIP_FONT_SIZE
    numericValue = math.floor(numericValue)

    if numericValue < 1 or numericValue > 3 then
        return MEE_DEFAULT_TOOLTIP_FONT_SIZE
    end

    return numericValue
end

local function meeClampTooltipDescriptionMode(value)
    -- 1 = MEE descriptions, 2 = MEE + vanilla descriptions, 3 = vanilla descriptions.
    local numericValue = tonumber(value) or MEE_DEFAULT_TOOLTIP_DESCRIPTION_MODE
    numericValue = math.floor(numericValue)

    if numericValue < 1 or numericValue > 3 then
        return MEE_DEFAULT_TOOLTIP_DESCRIPTION_MODE
    end

    return numericValue
end

local function meeStringToBoolean(value)
    -- Convert ModOptions.ini boolean strings into Lua booleans.
    if value == "true" then
        return true
    elseif value == "false" then
        return false
    end

    return nil
end

local function meeSplitModOptionsLine(line)
    -- Parse the simple pipe-separated format used by PZAPI.ModOptions.
    local parts = {}
    line = tostring(line or "")

    for part in string.gmatch(line .. "|", "(.-)|") do
        table.insert(parts, part)
    end

    return parts
end

local function meeLoadSavedOptionsFromIni()
    -- Load only this mod's saved values without touching other mods' options.
    if not getFileReader then
        return
    end

    local ok, file = pcall(getFileReader, "ModOptions.ini", true)
    if not ok or not file then
        return
    end

    while true do
        local line = file:readLine()
        if line == nil then
            file:close()
            break
        end

        local parts = meeSplitModOptionsLine(line)
        local optionType = parts[1]
        local modOptionsID = parts[2]
        local optionID = parts[3]
        local optionValue = parts[4]

        if modOptionsID == MEE_MOD_OPTIONS_ID then
            if optionType == "combobox" and optionID == "TooltipFontSize" then
                MEE.Options.TooltipFontSize = meeClampTooltipFontSize(optionValue)
            elseif optionType == "combobox" and optionID == "TooltipDescriptionMode" then
                MEE.Options.TooltipDescriptionMode = meeClampTooltipDescriptionMode(optionValue)
            elseif optionType == "tickbox" and optionID == "FallbackTooltipShadow" then
                local boolValue = meeStringToBoolean(optionValue)
                if boolValue ~= nil then
                    MEE.Options.FallbackTooltipShadow = boolValue
                end
            end
        end
    end
end

local function meeSyncOptionsObject(options)
    -- Push the loaded runtime values back into the PZAPI option objects.
    if not options then
        return
    end

    local fontOption = options:getOption("TooltipFontSize")
    if fontOption then
        fontOption:setValue(meeClampTooltipFontSize(MEE.Options.TooltipFontSize))
    end

    local descriptionModeOption = options:getOption("TooltipDescriptionMode")
    if descriptionModeOption then
        descriptionModeOption:setValue(meeClampTooltipDescriptionMode(MEE.Options.TooltipDescriptionMode))
    end

    local shadowOption = options:getOption("FallbackTooltipShadow")
    if shadowOption then
        shadowOption:setValue(MEE.Options.FallbackTooltipShadow ~= false)
    end
end

local function meeCreateModOptions()
    -- Register the options panel only if the vanilla B42 ModOptions API exists.
    if not PZAPI or not PZAPI.ModOptions or not PZAPI.ModOptions.create then
        return
    end

    local existingOptions = PZAPI.ModOptions:getOptions(MEE_MOD_OPTIONS_ID)
    if existingOptions then
        meeLoadSavedOptionsFromIni()
        meeSyncOptionsObject(existingOptions)
        return
    end

    local options = PZAPI.ModOptions:create(MEE_MOD_OPTIONS_ID, "UI_MEE_ModOptions_Title")
    options:addTitle("UI_MEE_ModOptions_Title")

    local tooltipFontSize = options:addComboBox(
        "TooltipFontSize",
        "UI_MEE_TooltipFontSize",
        "UI_MEE_TooltipFontSize_Tooltip"
    )
    tooltipFontSize:addItem("UI_MEE_FontSmall", true)
    tooltipFontSize:addItem("UI_MEE_FontMedium", false)
    tooltipFontSize:addItem("UI_MEE_FontLarge", false)
    tooltipFontSize.onChange = function(self, selected)
        -- Apply the selection immediately while the Options screen is open.
        MEE.Options.TooltipFontSize = meeClampTooltipFontSize(selected)
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end
    tooltipFontSize.onChangeApply = function(self, selected)
        -- Apply the selection when the Options screen is confirmed.
        MEE.Options.TooltipFontSize = meeClampTooltipFontSize(selected)
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end

    local tooltipDescriptionMode = options:addComboBox(
        "TooltipDescriptionMode",
        "UI_MEE_TooltipDescriptionMode",
        "UI_MEE_TooltipDescriptionMode_Tooltip"
    )
    tooltipDescriptionMode:addItem("UI_MEE_DescriptionModeMEE", true)
    tooltipDescriptionMode:addItem("UI_MEE_DescriptionModeMEEVanilla", false)
    tooltipDescriptionMode:addItem("UI_MEE_DescriptionModeVanilla", false)
    tooltipDescriptionMode.onChange = function(self, selected)
        -- Apply the selection immediately while the Options screen is open.
        MEE.Options.TooltipDescriptionMode = meeClampTooltipDescriptionMode(selected)
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end
    tooltipDescriptionMode.onChangeApply = function(self, selected)
        -- Apply the selection when the Options screen is confirmed.
        MEE.Options.TooltipDescriptionMode = meeClampTooltipDescriptionMode(selected)
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end

    local fallbackTooltipShadow = options:addTickBox(
        "FallbackTooltipShadow",
        "UI_MEE_FallbackTooltipShadow",
        MEE_DEFAULT_FALLBACK_TOOLTIP_SHADOW,
        "UI_MEE_FallbackTooltipShadow_Tooltip"
    )
    fallbackTooltipShadow.onChange = function(self, value)
        -- Apply the checkbox immediately while the Options screen is open.
        MEE.Options.FallbackTooltipShadow = value == true
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end
    fallbackTooltipShadow.onChangeApply = function(self, value)
        -- Apply the checkbox when the Options screen is confirmed.
        MEE.Options.FallbackTooltipShadow = value == true
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
    end

    meeLoadSavedOptionsFromIni()
    meeSyncOptionsObject(options)
end


local function meeNormalizeDescriptionForCompare(text)
    local normalized = tostring(text or "")
    normalized = normalized:gsub("%%%%", "%%")
    normalized = normalized:gsub("\r\n", "\n")
    normalized = normalized:gsub("\r", "\n")
    normalized = normalized:gsub("<br>", "\n")
    normalized = normalized:gsub(" <LINE> ", "\n")
    normalized = normalized:gsub("<LINE>", "\n")
    normalized = normalized:gsub("^%s+", "")
    normalized = normalized:gsub("%s+$", "")
    return normalized
end

local function meeGetTextOrNil(key)
    if not key then
        return nil
    end

    if getTextOrNull then
        local ok, value = pcall(getTextOrNull, key)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    if getText then
        local ok, value = pcall(getText, key)
        if ok and value ~= nil and tostring(value) ~= tostring(key) then
            return tostring(value)
        end
    end

    return nil
end

local function meeResolveMoodleDescriptionKey(moodles, moodleType)
    if not moodles or not moodleType or not moodleType.getTranslationName then
        return nil
    end

    local level = 0
    local ok, value = pcall(function()
        return moodles:getMoodleLevel(moodleType)
    end)
    if ok then
        level = tonumber(value) or 0
    end

    if level <= 0 then
        return nil
    end

    local nameOk, translationName = pcall(function()
        return moodleType:getTranslationName()
    end)
    if not nameOk or not translationName then
        return nil
    end

    return "Moodles_" .. tostring(translationName) .. "_desc_lvl" .. tostring(math.floor(level))
end

function MEE.GetVanillaMoodleDescription(moodles, moodleType)
    local descriptionKey = meeResolveMoodleDescriptionKey(moodles, moodleType)
    if not descriptionKey then
        return nil
    end

    return meeGetTextOrNil("MEE_Vanilla_" .. descriptionKey)
end

function MEE.GetMoodleTooltipDescription(moodles, moodleType, meeDescription)
    local mode = meeClampTooltipDescriptionMode(MEE.Options and MEE.Options.TooltipDescriptionMode)
    local descriptionKey = meeResolveMoodleDescriptionKey(moodles, moodleType)
    local cacheKey = tostring(descriptionKey or "")
            .. "\31" .. tostring(mode)
            .. "\31" .. tostring(meeDescription or "")

    if MEE.DescriptionCache and MEE.DescriptionCache[cacheKey] ~= nil then
        return MEE.DescriptionCache[cacheKey]
    end

    local vanillaDescription = nil
    if descriptionKey then
        vanillaDescription = meeGetTextOrNil("MEE_Vanilla_" .. descriptionKey)
    end

    local result = tostring(meeDescription or "")

    if vanillaDescription and vanillaDescription ~= "" then
        if mode == 3 then
            result = vanillaDescription
        elseif mode == 2 then
            local meeText = tostring(meeDescription or "")
            if meeNormalizeDescriptionForCompare(meeText) == meeNormalizeDescriptionForCompare(vanillaDescription) then
                result = meeText
            else
                local header = meeGetTextOrNil("UI_MEE_VanillaDescriptionHeader") or "Vanilla:"
                result = meeText .. "\n\n" .. header .. "\n" .. vanillaDescription
            end
        end
    end

    if MEE.DescriptionCache then
        MEE.DescriptionCache[cacheKey] = result
    end

    return result
end

meeCreateModOptions()
