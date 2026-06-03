--json = freeswitch.JSON()
local config = require "lua-functions/config"
authenticate_api = config.api.authenticate_api
createCallLog_api = config.api.createCallLog_api
callLog_api = config.api.callLog_api
getUserPresence_api = config.api.getUserPresence_api
callNotification_api = config.api.callNotification_api
getCallLogs_api = config.api.getCallLogs_api
updateAfterCall_api = config.api.updateAfterCall_api

local api_call ={}
--local json = freeswitch.JSON()
function api_call.accessToken()
local auth_payload = config.payload.authenticate_api
local headers = "append_headers 'AppKey:DHhCs9PNERBws/CVWqkzhA' append_headers 'AppType:enduser' "
session:execute("curl", authenticate_api.." append_headers 'AppKey:DHhCs9PNERBws/CVWqkzhA' append_headers 'AppType:enduser' content-type application/json post "..auth_payload)
auth_api_response_code = tonumber(session:getVariable("curl_response_code"))
auth_api_response_data = json:decode(session:getVariable("curl_response_data"))
freeswitch.consoleLog("NOTICE","iAuthencate API curl Response Code: "..auth_api_response_code)

 if  tonumber(auth_api_response_code) >= 200 and tonumber(auth_api_response_code) < 300 then
    if auth_api_response_data and auth_api_response_data.response and auth_api_response_data.response.token then
        access_token = auth_api_response_data.response.token
        auth_userId = auth_api_response_data.response.userID
        freeswitch.consoleLog("NOTICE","Access Token: "..access_token.." auth_user ID:: "..auth_userId)
	freeswitch.setGlobalVariable("access_token",access_token)
	freeswitch.setGlobalVariable("auth_userId",auth_userId)
	return access_token, auth_userId
    else
        freeswitch.consoleLog("NOTICE", "Token not found in API response." ..json:encdode(auth_api_response_data))
	access_token,auth_userId = nil;
	return access_token
    end
 else
	freeswitch.consoleLog("NOTICE", "Authenticate API Error: " .. auth_api_response_code)
	access_token,auth_userId = nil;
	return access_token
 end
end

function api_call.createCallLog(useragent_json,access_token,auth_userId)
--	session:execute("curl", createCallLog_api.." append_headers 'Authorization: Bearer "..access_token.."' content-type application/JSON post "..useragent_json)
--	session:execute("curl", callLog_api.." content-type application/JSON post "..useragent_json)
--	local curl_command = callLog_api.." content-type application/JSON post "..useragent_json
--	session:execute("curl", callLog_api .. " content-type:application/json post '" .. useragent_json .. "'")
	session:execute("curl", "https://wapis.discretal.com/calls/addAxionicDetails content-type application/JSON post " .. useragent_json .. " ssl-verifyhost 0 ssl-verifypeer 0")
        local api_response_code = session:getVariable("curl_response_code")
	local curl_error = session:getVariable("curl_error")

	local api_response_data = session:getVariable("curl_response_data")
	local api_response_raw = session:getVariable("curl_response_data")
	freeswitch.consoleLog("NOTICE", "cURL Response Code: " .. (api_response_code or "nil") .. "\n")
	freeswitch.consoleLog("ERROR", "cURL Error: " .. (curl_error or "nil") .. "\n")
	freeswitch.consoleLog("NOTICE", "cURL Response Data: " .. (api_response_data or "nil") .. "\n")
        freeswitch.consoleLog("NOTICE","Create Call Log API response code :: " ..api_response_code )
        --------------------------------
	if api_response_code and tonumber(api_response_code) >= 200 and tonumber(api_response_code) < 400 then
    freeswitch.consoleLog("NOTICE", "Create Call Log API success\n")

    -- ================================
    -- VALIDATE RESPONSE BODY
    -- ================================
    if api_response_raw and api_response_raw ~= "" then

        -- ✅ SAFE JSON DECODE (FreeSWITCH cjson)
        local ok, api_response_data = pcall(json.decode, json, api_response_raw)

        if not ok then
            freeswitch.consoleLog("ERROR", "Failed to decode API response JSON\n")
            return
        end

        -- ✅ SAFE JSON PRINT (FIXED)
        freeswitch.consoleLog(
            "NOTICE",
            "Decoded API Response: " .. json:encode(api_response_data) .. "\n"
        )

        -- ================================
        -- ACCESS NESTED DATA
        -- ================================
        if api_response_data.response and api_response_data.response.call_id then
            freeswitch.consoleLog(
                "NOTICE",
                "Received call_id: " .. api_response_data.response.call_id .. "\n"
            )
        end

    else
        freeswitch.consoleLog("WARNING", "curl_response_data is empty\n")
    end
else
    freeswitch.consoleLog("ERROR", "Create Call Log API failed\n")
end
	----------------------------
	if  tonumber(api_response_code) >= 200 and tonumber(api_response_code) <= 400 then
            freeswitch.consoleLog("NOTICE","Create Call Log API response data :: " ..session:getVariable("curl_response_data") )
            local api_response_data = json:decode(session:getVariable("curl_response_data"))
            --if api_response_data and api_response_data.response and api_response_data.response.callLogId then
           -- if api_response_data and api_response_data.response and api_response_data.response.call_id then
	   if api_response_data then
		   local message = api_response_data.message or "No message"
    --		   local  callLogId = api_response_data.response and api_response_data.response.call_id or "No call_id"
		   local callLogId = (api_response_data.response and api_response_data.response.call_id) or session:get_uuid()
                     freeswitch.consoleLog("NOTICE", "Call Log ID is :: " .. callLogId .. "\n")
	            session:setVariable("sip_h_X-CallLogId", callLogId);
	            session:execute("export","nolocal:sip_h_X-CallLogId="..callLogId)
		    local uuid = session:getVariable("uuid")
		       cmd_call="uuid_setvar      "..tostring(uuid).."      ".."call_id".."             "..tostring(callLogId);
                        freeswitch.consoleLog("NOTICE","Notification cmd " .. tostring(cmd_call) .. " ...\n")
                        a=api:executeString(cmd_call)
		    return message .. " | call_id: " .. callLogId
		   -- return api_response_data.message
            else
            	    freeswitch.consoleLog("NOTICE","Create Call Log API response data :: " ..session:getVariable("curl_response_data") )
        	    freeswitch.consoleLog("NOTICE", "Call log ID not found in API response.")
		    session:hangup()
	            do return end
            end
        else
            --freeswitch.consoleLog("NOTICE", "create Call Log ID API Error: " .. json:encode(api_response_data))
            freeswitch.consoleLog("WARNING","Call Log not found")
            session:hangup()
            do return end
        end
end

function api_call.getUserPresence(access_token,getUser_payload)
	session:execute("curl", getUserPresence_api.." append_headers 'Authorization: Bearer "..access_token.."' content-type application/JSON post "..getUser_payload)
	local userPresence_response_code = session:getVariable("curl_response_code")
	freeswitch.consoleLog("INFO","The presence response  API result is: "..userPresence_response_code.. "\n")
        if  tonumber(userPresence_response_code) == 200 then
            local userPresence_response_data = json:decode(session:getVariable("curl_response_data"))
            local presence_status = userPresence_response_data.response[1].currentStatusCode
            freeswitch.consoleLog("INFO", "The current status code is: " .. presence_status .. "\n")
            return presence_status
	else
	    return nil
	end
end

function api_call.callNotification(notify_json,access_token)
        session:execute("curl", callNotification_api.." append_headers 'Authorization: Bearer "..access_token.."' content-type application/JSON post "..notify_json)
        local api_response_code = session:getVariable("curl_response_code")
        freeswitch.consoleLog("NOTICE","The call Notification API curl response code is: " ..api_response_code.. "\n")
end


return api_call
