freeswitch.consoleLog("DEBUG", "The inside function details is \n")
local dialed_number = session:getVariable("destination_number")
local from_num = session:getVariable("caller_id_number")
local sip_uri = session:getVariable("presence_id")
--local sip_domain_name = sip_uri:match("@(.-):?%d*$")
 local sip_domain_name = "pbx.axionic.io"
 local sip_port ="7440"
session:setVariable("sip_domain_name", sip_domain_name);
session:execute("export","nolocal:sip_domain_name="..sip_domain_name)
local sip_callid = session:getVariable("sip_call_id")
--local sip_callid = session:getVariable("sip_h_Call-ID")
session:setVariable("sip_call_id", sip_callid);
session:execute("export","nolocal:sip_call_id="..sip_callid)
local call_direction = session:getVariable("direction")
--freeswitch.consoleLog("INFO","Call-Direction" ..call_direction)
local uuid = session:getVariable("uuid")
local sip_user_agent = session:getVariable("sip_user_agent")
--freeswitch.consoleLog("notice","Variable sip_user_agent is :" ..sip_user_agent)
local timestamp = session:getVariable("created_time");
local startTime = os.date("!%Y-%m-%dT%TZ", math.floor(timestamp/1e6))
local isFromAxionic = session:getVariable("sip_h_X-isFromAxionic")
--freeswitch.consoleLog("INFO","Custom headeris" ..isFromAxionic)
local media_type = session:getVariable("isvideocall")
freeswitch.consoleLog("INFO","videocall variable is" ..media_type)
api = freeswitch.API()
json = freeswitch.JSON()
lunajson = require "lunajson"
local time = api:getTime()

local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"
local config = require "lua-functions/config"
function validateUserPresence(presence_status, session)
    freeswitch.consoleLog("DEBUG", "userPresence_data: " .. presence_status .. "\n")

    -- Check if the user is unavailable (In Call, Unregistered, Invalid)
    if presence_status ~= nil and (presence_status == "In call" or presence_status == "Unregistered" or presence_status == "Invalid") then
        freeswitch.consoleLog("INFO", "User is unavailable: " .. presence_status .. "\n")

        -- If session is active, send call to voicemail
        if session and session:ready() then
            session:answer()
            freeswitch.consoleLog("INFO", "Sending call to voicemail for: " .. dialed_number .. "\n")

            local vm_data = "default " .. sip_domain_name .. " " .. dialed_number
            session:execute("voicemail", vm_data)
            session:hangup("NORMAL_CLEARING")
        else
            freeswitch.consoleLog("WARNING", "Session not ready. Cannot send to voicemail.\n")
        end
    end
end

-- Construct user presence check payload
local media_type = (media_type == "true") and "V" or "A"
local call_type = "O"
local useragent_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false}"

-- Call API to check user presence
local userPresence_data = api_call.createCallLog(useragent_json)
freeswitch.consoleLog("NOTICE", "API Response: " .. tostring(userPresence_data) .. "\n")

-- Extract response
local errorMessage = tostring(userPresence_data)

-- Validate presence BEFORE proceeding with the call
if errorMessage == "In call" or errorMessage == "Unregistered" or errorMessage == "Invalid" then
    freeswitch.consoleLog("INFO", "User is unavailable. Handling call appropriately...\n")
    validateUserPresence(errorMessage, session)
else
    -- Proceed with call since the user is available
    freeswitch.consoleLog("INFO", "User is available. Proceeding with call...\n")
end

