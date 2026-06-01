api = freeswitch.API()
json = freeswitch.JSON()

-- 📞 Basic call variables
local from_num = session:getVariable("caller_id_number") or "unknown"
local dialed_number = session:getVariable("destination_number") or "unknown"
freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Incoming call from: " .. from_num .. " to: " .. dialed_number .. "\n")

-- 📡 SIP domain for callback/contact
local sip_domain_name = "pbx.axionic.io"
session:setVariable("sip_domain_name", sip_domain_name)
session:execute("export", "nolocal:sip_domain_name=" .. sip_domain_name)

-- ✅ Answer call
session:answer()
session:execute("sleep", "500")

-- 🕒 Time check (09:00–18:00 AST) — make sure server TZ is AST or adjust offset
local hour = tonumber(os.date("%H"))
if hour < 9 or hour >= 18 then
    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Outside office hours: " .. hour .. "\n")
    session:execute("playback", "/usr/local/freeswitch/sounds/custom-ivrs/LeSaaS_OffHours.mp3")
    session:hangup()
    return
end

-- 🔊 Play welcome message
session:execute("playback", "/usr/local/freeswitch/sounds/custom-ivrs/LeSaaS_Welcome.mp3")

-- 🧠 Optional: Set token and create call log (if required, similar to leader script)
--[[
local module_folder = freeswitch.getGlobalVariable("script_dir") .. "/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"
local config = require "lua-functions/config"

local access_token, auth_userId = api_call.accessToken()
if access_token then
    session:setVariable("access_token", access_token)
    session:execute("export", "nolocal:access_token=" .. access_token)
end
--]]

-- 📡 Dynamically register agents if online (optional improvement)
local extensions = {"3001","3002","3003","3004","3005","3006","3007","3008","3009","3010"}
local not_registered = "error/user_not_registered"

for _, ext in ipairs(extensions) do
    local contact_status = api:executeString("sofia_contact " .. ext)
    if contact_status ~= not_registered then
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " online, setting status Available\n")
        api:executeString("callcenter_config agent set status " .. ext .. " Available")
        api:executeString("callcenter_config agent set contact " .. ext .. " [leg_timeout=30]" .. contact_status)
        api:executeString("callcenter_config agent set state " .. ext .. " Waiting")
    else
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " offline, logging out\n")
        api:executeString("callcenter_config agent set status " .. ext .. " 'Logged Out'")
    end
end

-- 📞 Send call to callcenter queue
session:execute("callcenter", "lesaas_support@default")

-- 📤 If no agent answered
session:execute("playback", "/usr/local/freeswitch/sounds/custom-ivrs/LeSaaS_NoAgentAvailable.mp3")
session:hangup()

