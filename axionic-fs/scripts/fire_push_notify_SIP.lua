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


 function validateUserPresence(presence_status)
	   freeswitch.consoleLog("DEBUG", "userPresence_data: " .. presence_status .. "\n")
--	   if presence_status ~= nil and (presence_status == "User is already in a call" or presence_status == "Unregistered" or presence_status == "Invalid") then
	   if presence_status ~= nil and (presence_status == "User is already in a call") then
    freeswitch.consoleLog("INFO", "The call will not connect because the presence status is: " .. presence_status .. "\n")

    if session:ready() then
        session:answer()
        freeswitch.consoleLog("INFO", "Sending call to voicemail for: " .. dialed_number .. "\n")
        --send_sip_missed_call(from_num, dialed_number)
        -- Format voicemail data correctly
        local vm_data = "default " .. sip_domain_name .. " " .. dialed_number

        -- Execute voicemail application
        session:execute("voicemail", vm_data)

        -- Properly hang up the call
        session:hangup("NORMAL_CLEARING")
    else
        freeswitch.consoleLog("WARNING", "Session not ready. Cannot send to voicemail.\n")
    end
end
end
	     if (media_type == "true") then
                  media_type = "V"
            else
                  media_type = "A"
            end
            local call_type = "O"
             local useragent_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false}"
	      userPresence_data = api_call.createCallLog(useragent_json)
   freeswitch.consoleLog("NOTICE", "API Response: " .. tostring(userPresence_data) .. "\n")

        
	  local errorMessage = tostring(userPresence_data)
--	  if errorMessage:match("User is already in a call") or errorMessage:match("Unregistered") or errorMessage:match("Invalid") then
	  if errorMessage:match("User is already in a call") then
--               if errorMessage == "In call" or errorMessage == "Unregistered" or errorMessage =="Invalid" then
		        freeswitch.consoleLog("INFO","Entering in status ")
                           local voicemail_json = "{\"domain\":\""..sip_domain_name.."\",\"port\":\""..sip_port.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"status\":Missed}"
			    session:execute("curl", "https://wapis.discretal.com/calls/sip-call-notification content-type application/JSON post " .. voicemail_json .. " ssl-verifyhost 0 ssl-verifypeer 0")
                          validateUserPresence(errorMessage)
                        end


