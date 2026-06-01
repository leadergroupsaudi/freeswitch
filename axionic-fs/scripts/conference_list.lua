local lunajson = require "lunajson"
local from_num = session:getVariable("caller_id_number")
local dialed_number = session:getVariable("target_num")
freeswitch.consoleLog("INFO","Adding Participant Number:: " ..dialed_number.. "\n")
local from_num = session:getVariable("caller_id_number")
local media_type = session:getVariable("isvideocall")
api = freeswitch.API()
local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"


local sip_domain_name = session:getVariable("sip_domain_name")
local callLogId = session:getVariable("sip_h_X-CallLogId")
local jsonData = api:executeString("conference conf_"..callLogId.." json_list")
local data = lunajson.decode(jsonData)


local callerIdsString = ""
for _, member in ipairs(data[1].members) do
    local callerIdNumber = member.caller_id_number
    if callerIdsString == "" then
        callerIdsString = callerIdNumber
    else
        callerIdsString = callerIdsString .. ";" .. callerIdNumber
    end
end

local from_user_name = api:executeString("user_data "..from_num.."@"..sip_domain_name.." var effective_caller_id_name")
freeswitch.consoleLog("INFO","CallerID Numbers " ..callerIdsString.. "\n")
session:setVariable("from_user_name", from_user_name);
session:setVariable("sip_h_X-GroupCallList", callerIdsString);
session:execute("export","nolocal:sip_h_X-GroupCallList="..callerIdsString)
local access_token = freeswitch.getGlobalVariable("access_token")
freeswitch.consoleLog("INFO", "The received access token is :"..access_token.."\n")

if (media_type == "true") then
       media_type = "V"
else
       media_type = "A"
end
local call_type = "G"
local notify_json = "{\"domain\":\""..sip_domain_name.."\",\"callerId\":\""..from_num.."\",\"receivers\":[\""..dialed_number.."\"],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false,\"logId\":"..callLogId.."}"
api_call.callNotification(notify_json,access_token)
