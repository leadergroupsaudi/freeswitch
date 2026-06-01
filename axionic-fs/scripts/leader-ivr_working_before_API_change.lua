api = freeswitch.API();
json = freeswitch.JSON()
local from_num = session:getVariable("caller_id_number")
freeswitch.consoleLog("notice","Caller ID Number : "..from_num)
local dialed_number = session:getVariable("destination_number")
freeswitch.consoleLog("notice","Caller ID Number : "..dialed_number)
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
        freeswitch.consoleLog("notice","creating token")
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
session:execute("sleep","500")
--dtmf = session:playAndGetDigits(1, 4, 3, 5000, "#","welcome-siptrunk.wav",
--"/usr/local/freeswitch-staging-instance/share/freeswitch/sounds/en/us/callie/ivr/8000/ivr-demo-invalid.wav","[0123456789]");

--for i = 1,3 do
        digits = session:read(1, 4, "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/LeaderWelcome.wav", 5000,"");
        freeswitch.consoleLog("NOTICE", "digits "..digits.."\n");
	if (string.len(digits) == 1 and tonumber(digits) == 0) or digits == '' then
		session:setVariable("continue_on_fail","true")
		local extensions = {"116","110"}
		local ext_not_reg = "error/user_not_registered"
		for j = 1, #extensions do
  			--print([i])
			freeswitch.consoleLog("notice","Extension Array "..extensions[j])
			local extension_status = api:executeString("sofia_contact " .. extensions[j])
			if extension_status ~= ext_not_reg  then
				--api:executeString("callcenter_config agent add " .. value.Extension .. " Callback")
				api:executeString("callcenter_config agent set status " .. extensions[j] .. " Available")
				api:executeString("callcenter_config agent set contact " .. extensions[j] .. " [absolute_codec_string='PCMU,PCMA',leg_timeout=30]" .. extension_status);
				--api:executeString("callcenter_config agent set reject_delay_time " .. extensions[i] .. " 3")
				--api:executeString("callcenter_config agent set no_answer_delay_time " .. extensions[i] .. " 3")
				--api:executeString("callcenter_config agent set reject_delay_time " .. extensions[i] .. " 3")
				--api:executeString("callcenter_config agent set busy_delay_time " .. extensions[i] .. " 3")
				api:executeString("callcenter_config agent set state " .. extensions[j] .. " Waiting")
                                --api:executeString("callcenter_config tier add ivr-test@default " .. value.Extension .. " 1 1")
			 else
                                freeswitch.consoleLog("notice","Extension " .. extensions[j] .. " Not registered . Changing status to Logged Out ..")
                                api:executeString("callcenter_config agent set status " .. extensions[j] .. " 'Logged Out'")
                         end
		end
                --session:execute("callcenter","leader-ivr@default")
                --session:execute("playback","/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/AgentBusy.wav")
                --session:hangup()
		session:execute("transfer","LEADER_910 XML public")
		--session:setVariable("call_timeout", "30");
		--session:execute("transfer","116 XML public");
	elseif string.len(digits) == 3 or  string.len(digits) == 4  then
		 session:execute("export", "nolocal:destination_number=" .. digits)
                cmd = "user_exists id "..digits.." "..sip_domain_name
		freeswitch.consoleLog("notice","freeswitch command ::"..cmd)
                found = api:executeString(cmd)
                freeswitch.consoleLog("notice","Extension Output result"..found)
                if found == 'true' then
			 --session:setVariable("continue_on_fail","true")
                        freeswitch.consoleLog("notice","Extesnion found")
			 freeswitch.consoleLog("notice","IN ELSE Part")
			 session:setVariable("continue_on_fail","true")
			  --session:execute("export", "nolocal:destination_number=" .. digits)
			 -- local sip_domain = session:getVariable("sip_domain") or "default.sip.domain"
        	--	local dial_string = "sofia/internal/" .. digits .. "@" .. sip_domain .. " XML public"
		--	freeswitch.consoleLog("NOTICE", "Digits matched regex. Transferring to: " .. dial_string .. "\n")
        	--	session:execute("transfer", dial_string)
		--	 session:execute("transfer","LEADER_910 XML public")
			--local dial_string = "sofia/internal_stc/" .. digits .. "@" .. sip_domain_name .. " XML public"
			--local result = freeswitch.API():executeString("originate " .. dial_string)
			--freeswitch.consoleLog("notice", "Call originate result: " .. result)
			-- sip_uri = "sip:" .. digits .." @pbx.axionic.io"
			--local dial_string = sip_uri .. " XML public"
                       dial_string = digits .." XML public";
		   --local dial_string = "sofia/internal/" .. digits .. "@" .. sip_domain_name .. " XML public"
		--	freeswitch.consoleLog("notice","dial_string::" ..dial_string)
--			session:setVariable("call_timeout", "30");
                       session:execute("transfer",dial_string);
		      -- session:execute("transfer","Local_Extension_and_group_call XML public")
		--       session:setVariable("continue_on_fail","true")
		  --     session:execute("transfer","LEADER_910 XML public")
		    --   freeswitch.consoleLog("notice","Digits :"..digits)
        --                session:transfer("3087", "XML", "public")
		--	session:execute("transfer", "3087 XML public")
			--session:hangup();
                end
        --end
	else
        session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/en/us/callie/ivr/8000/ivr-you_have_dialed_an_invalid_extension.wav");
--end

end

