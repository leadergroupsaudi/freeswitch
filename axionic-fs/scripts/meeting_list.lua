local json = require "lunajson"
local from_num = session:getVariable("caller_id_number")
local dialed_number = session:getVariable("target_num")
freeswitch.consoleLog("INFO","Adding Participant Number:: " ..dialed_number.. "\n")
local media_type = session:getVariable("isvideocall")
api = freeswitch.API()
local callLogId = session:getVariable("sip_h_X-CallLogId")
local roomId = session:getVariable("room_id")
local jsonData = api:executeString("conference "..roomId.."_"..callLogId.." json_list")
local data = json.decode(jsonData)
local callerIdsString = ""
for _, member in ipairs(data[1].members) do
    local callerIdNumber = member.caller_id_number
    if callerIdsString == "" then
        callerIdsString = callerIdNumber
    else
        callerIdsString = callerIdsString .. ";" .. callerIdNumber
    end
end
local from_user_name = api:executeString("user_data "..from_num.."@pbx.axionic.io var effective_caller_id_name")
freeswitch.consoleLog("INFO","CallerID Numbers " ..callerIdsString.. "\n")
session:setVariable("from_user_name", from_user_name);
session:setVariable("sip_h_X-GroupCallList", callerIdsString);
session:execute("export","nolocal:sip_h_X-GroupCallList="..callerIdsString)
session:setVariable("sip_h_X-isMeeting", "true");
session:execute("export","nolocal:sip_h_X-isMeeting=true")

local access_token = freeswitch.getGlobalVariable("access_token")
freeswitch.consoleLog("INFO", "The received access token is :"..access_token.."\n")
if (media_type == "true") then
     media_type = "V"
else
     media_type = "A"
end
local call_type = "M"
local notify_json = "{\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false,\"logId\":"..callLogId.."}"
session:execute("curl", "https://app.axionic.io/AXBFF/V2/Administration/UserNotification/Call append_headers 'Authorization: Bearer "..access_token.."' content-type application/JSON post "..notify_json)
local api_response_code = session:getVariable("curl_response_code")
freeswitch.consoleLog("INFO","The curl response code is: " ..api_response_code.. "\n")
