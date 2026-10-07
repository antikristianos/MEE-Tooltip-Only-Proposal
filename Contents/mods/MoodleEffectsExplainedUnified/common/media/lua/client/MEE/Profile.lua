if MEE and MEE.Profile then return MEE.Profile end
local keys = require "MEE/ProfileKeys"
MEE = MEE or {}
local Profile = {}
MEE.Profile = Profile

-- Activated IDs describe the whole session, even before companion Lua runs.
-- Do not require foreign modules or infer ownership from incidental globals.
function Profile.resolve()
    if type(getActivatedMods) ~= "function" then return nil end
    local ok, selected = pcall(function()
        local mods = getActivatedMods()
        if not mods or not mods.size or not mods.get then return nil end
        local expanded = false
        for index = 0, mods:size() - 1 do
            local id = tostring(mods:get(index))
            if id == "DynamicTraits" then return "DTEM" end
            if id == "ExpandedMoodles" then expanded = true end
        end
        return expanded and "EM" or "Base"
    end)
    return ok and selected or nil
end

function Profile.apply()
    local selected = Profile.resolve()
    if not selected or not Translator or not Translator.BY_NAME or not HashMap then return false end
    local ok, applied = pcall(function()
        -- BY_NAME is public but its anonymous Java class is not a Lua API.
        -- Copy only the outer map through a public constructor. Inner maps stay
        -- shared with native Translator; no reflection or private fields.
        local categories = HashMap.new(Translator.BY_NAME)
        local moodles = categories:get("Moodles")
        if not moodles then return false end
        local values = {}
        for index = 1, #keys do
            local key = keys[index]
            local value = moodles:get("Moodles_MEEProfile_" .. selected .. "_" .. key)
            if value == nil then return false end
            values[index] = value
        end
        -- Keep raw loader values: getText() would consume percent escapes here
        -- and then consume them again when Vanilla or a foreign tooltip reads.
        for index = 1, #keys do moodles:put(keys[index], values[index]) end
        Profile.selected = selected
        if MEE.ResetDescriptionCache then MEE.ResetDescriptionCache() end
        return true
    end)
    return ok and applied == true
end

local pending = nil
local function finishStartup()
    -- One deferred pass runs after all startup event handlers, independent of
    -- callback registration order. There is no permanent frame/tick correction.
    if pending and Events.OnTick and Events.OnTick.Remove then Events.OnTick.Remove(pending) end
    pending = nil
    Profile.apply()
end
function Profile.refresh()
    Profile.apply()
    if not pending and Events and Events.OnTick and Events.OnTick.Add then
        pending = finishStartup
        Events.OnTick.Add(pending)
    end
end

if Events then
    for _, name in ipairs({ "OnGameBoot", "OnGameStart", "OnCreatePlayer" }) do
        if Events[name] and Events[name].Add then Events[name].Add(Profile.refresh) end
    end
end
return Profile
