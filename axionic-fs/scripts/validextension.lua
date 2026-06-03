-- validextension.lua
local destination = session:getVariable("destination_number")

freeswitch.consoleLog("NOTICE", "Checking extension: " .. tostring(destination) .. "\n")

-- Valid patterns matching your dialplan regex
local valid_patterns = {
    "^1%d%d%d$",  -- 1xxx (4 digits)
    "^1%d%d$",    -- 1xx
    "^2%d%d$",    -- 2xx
    "^3%d%d$",    -- 3xx
    "^4%d%d$",    -- 4xx
    "^5%d%d$",    -- 5xx
    "^6%d%d$",    -- 6xx
}

local is_valid = false
for _, pattern in ipairs(valid_patterns) do
    if destination and destination:match(pattern) then
        is_valid = true
        freeswitch.consoleLog("NOTICE", "Extension " .. destination .. " is VALID\n")
        break
    end
end

if not is_valid then
    freeswitch.consoleLog("NOTICE", "Extension " .. tostring(destination) .. " is INVALID — playing message and hanging up\n")
    session:answer()
    session:sleep(500)
    session:streamFile("/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/valid_extension.wav")
    session:hangup("NORMAL_CLEARING")
    return  -- stop here, dialplan actions after lua() won't execute
end

-- Valid: script returns normally, dialplan continues to next actions
freeswitch.consoleLog("NOTICE", "Extension " .. destination .. " is valid, continuing to bridge\n")
