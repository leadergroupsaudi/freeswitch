api = freeswitch.API();
json = freeswitch.JSON()
local caller = session:getVariable("caller_id_number");
freeswitch.consoleLog("notice","Caller ID Number : "..caller)
--local sip_uri = session:getVariable("presence_id")
local sip_domain_name = "pbx.axionic.io"
session:setVariable("sip_domain_name", sip_domain_name);
session:execute("export","nolocal:sip_domain_name="..sip_domain_name)

local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"
local config = require "lua-functions/config"

if freeswitch.getGlobalVariable("access_token") ~= nil then
	access_token = freeswitch.getGlobalVariable("access_token")
	auth_userId = freeswitch.getGlobalVariable("fs_userId")
else
	access_token,auth_userId = api_call.accessToken()
end
if freeswitch.getGlobalVariable("access_token") ~= nil then
	access_token = freeswitch.getGlobalVariable("access_token")
	auth_userId = freeswitch.getGlobalVariable("fs_userId")
else
	access_token,auth_userId = api_call.accessToken()
end

local sip_user_agent = session:getVariable("sip_user_agent")

if access_token ~= nil then 
-- create Call Log for IP-Phone calls
	session:setVariable("access_token",access_token) 
	session:execute("export","nolocal:access_token="..access_token)
	if session:getVariable("sip_h_X-CallLogId") == nil then
		if string.len(from_num) > 4 then isExternal_from = true else isExternal_from = false end
		if string.len(dialed_number) > 4 then isExternal_dialed = true else isExternal_dialed = false end
		useragent_json = "{\"CallType\":\"A\",\"CallMode\":\"O\",\"CallDuration\":\"0\",\"CallParticipantsList\":[{\"IsExternal\":"..tostring(isExternal_from)..",\"CallerId\":\""..from_num.."\",\"IsRead\":false,\"IsCaller\":true,\"AnswerStatus\":\"A\"},{\"IsExternal\":"..tostring(isExternal_dialed)..",\"CallerId\":\""..dialed_number.."\",\"IsRead\":false,\"IsCaller\":false,\"AnswerStatus\":\"A\"}]}"
		userPresence_data = api_call.createCallLog(useragent_json,access_token,auth_userId)
	end
end

session:answer();

session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/JihaziWelcome.wav");

                local extensions = {"130"}
                local ext_not_reg = "error/user_not_registered"
                for i = 1, #extensions do
                        --print([i])
                        freeswitch.consoleLog("notice","Extension Array "..extensions[i])
                        local extension_status = api:executeString("sofia_contact " .. extensions[i])
                        if extension_status ~= ext_not_reg  then
                                api:executeString("callcenter_config agent set status " .. extensions[i] .. " Available")
                                api:executeString("callcenter_config agent set contact " .. extensions[i] .. " [absolute_codec_string='G722,PCMU,PCMA',leg_timeout=30]" .. extension_status);
                                api:executeString("callcenter_config agent set state " .. extensions[i] .. " Waiting")
                         else
                                freeswitch.consoleLog("notice","Extension " .. extensions[i] .. " Not registered . Changing status to Logged Out ..")
                                api:executeString("callcenter_config agent set status " .. extensions[i] .. " 'Logged Out'")
                                api:executeString("callcenter_config agent set state " .. extensions[i] .. " Idle")
                         end
                end

