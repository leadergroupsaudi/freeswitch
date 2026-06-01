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
freeswitch.consoleLog("INFO","uuid" ..uuid)
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

getUserPresence_api = config.api.getUserPresence_api


local missed_notified = false

-- Determine media type
if (media_type == "true") then
    media_type = "V"
else
    media_type = "A"
end

local call_type = "O"
local useragent_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false}"

-- API call to check user presence
userPresence_data = api_call.createCallLog(useragent_json)
freeswitch.consoleLog("NOTICE", "API Response: " .. tostring(userPresence_data) .. "\n")

local errorMessage = tostring(userPresence_data)

-- Check if user is already in a call
--if errorMessage:match("User is already in a call") then
if errorMessage:lower():match("in call") then
    freeswitch.consoleLog("INFO", "User is busy, sending Missed notification and voicemail\n")

    -- Send missed call API
    local voicemail_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"status\":\"Missed\"}"
    session:execute("curl", "https://wapis.discretal.com/calls/sip-call-notification content-type application/JSON post " .. voicemail_json .. " ssl-verifyhost 0 ssl-verifypeer 0")
    missed_notified = true

    -- Voicemail processing
    if session:ready() then
  --      session:answer()
        local vm_data = "default " .. sip_domain_name .. " " .. dialed_number
        freeswitch.consoleLog("INFO", "Sending call to voicemail for: " .. dialed_number .. "\n")
        session:execute("voicemail", vm_data)
        session:hangup("NORMAL_CLEARING")
    else
        freeswitch.consoleLog("WARNING", "Session not ready. Cannot send to voicemail.\n")
    end
else
    -- Proceed with actual call flow (not shown in your code)
    -- ...
end

-- Post-call hook: check if the call ended without NORMAL_CLEARING and notify missed if not already done
--[[if not missed_notified then
    local cause = session:hangupCause()
     local cause = session:hangupCause() or "UNKNOWN"
    local disposition = session:getVariable("endpoint_disposition") or "NONE"
    local was_answered = session:answered()
    freeswitch.consoleLog("INFO", "Call ended with cause: " .. cause .. "\n")

--    if cause ~= "NORMAL_CLEARING" then
	if (not was_answered) or cause == "NO_ANSWER" or cause == "ORIGINATOR_CANCEL" or cause == "NONE" or disposition == "no_answer" then
        local voicemail_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"status\":\"Missed\"}"
        session:execute("curl", "https://wapis.discretal.com/calls/sip-call-notification content-type application/JSON post " .. voicemail_json .. " ssl-verifyhost 0 ssl-verifypeer 0")
        missed_notified = true
        freeswitch.consoleLog("INFO", "Missed call API sent due to hangup cause\n")
    end
end]]



if not missed_notified then
    local cause = session:hangupCause() or "UNKNOWN"
    local disposition = session:getVariable("endpoint_disposition") or "NONE"
    local was_answered = session:answered()
    local bridge_cause = session:getVariable("bridge_hangup_cause") or "NONE"

    freeswitch.consoleLog("INFO", "Call ended -- cause: " .. cause .. ", answered: " .. tostring(was_answered) .. ", disposition: " .. disposition .. ", bridge cause: " .. bridge_cause .. "\n")

    -- Only trigger missed call when:
    -- 1. Call was not answered at all
    -- 2. And bridge cause shows it failed
    if (not was_answered) and (bridge_cause == "NO_ANSWER" or bridge_cause == "ORIGINATOR_CANCEL" or bridge_cause == "NORMAL_TEMPORARY_FAILURE") then
        local voicemail_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"status\":\"Missed\"}"
        session:execute("curl", "https://wapis.discretal.com/calls/sip-call-notification content-type application/JSON post " .. voicemail_json .. " ssl-verifyhost 0 ssl-verifypeer 0")
        missed_notified = true
        freeswitch.consoleLog("INFO", "Missed call API sent due to unanswered call\n")
    else
        freeswitch.consoleLog("INFO", "Call was answered or completed, skipping missed call notification\n")
    end
end
