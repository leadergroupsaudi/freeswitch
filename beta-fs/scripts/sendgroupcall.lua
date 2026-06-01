api = freeswitch.API()
json = freeswitch.JSON()
lunajson = require "lunajson"
local from_num = session:getVariable("caller_id_number")
local callLogId = session:getVariable("sip_h_X-CallLogId")
local send_groupcall_data = session:getVariable("sip_h_X-SendGroupCall")
groupCallList = send_groupcall_data .. ";" .. from_num;
local codec = session:getVariable("ep_codec_string")
freeswitch.consoleLog("INFO","Send_Group_Call Header List " ..send_groupcall_data.. "\n")
session:setVariable("sip_h_X-GroupCallList", groupCallList)
session:execute("export","nolocal:sip_h_X-GroupCallList="..groupCallList)
local sip_uri = session:getVariable("presence_id")
local sip_domain_name = sip_uri:match("@(.-):?%d*$")
session:setVariable("sip_domain_name", sip_domain_name);
session:execute("export","nolocal:sip_domain="..sip_domain_name)
freeswitch.consoleLog("NOTICE","sip_domain_name:  " ..sip_domain_name.. "\n")
local media_type = session:getVariable("isvideocall")
grpcallString = ""
local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"


if (media_type == "true") then
	freeswitch.consoleLog("INFO","call type found:  " ..media_type.. "\n")
	for id in string.gmatch(send_groupcall_data, "[^;]+") do
           grpcallString  = grpcallString .. "['ignore_early_media=true,sip_h_X-GroupCallList="..groupCallList..",sip_h_X-CallLogId=${sip_h_X-CallLogId}']user/" .. id .. "@" .. sip_domain_name .. ","
        end
 else
	 freeswitch.consoleLog("INFO","call type found:  " ..media_type.. "\n")
	for id in string.gmatch(send_groupcall_data, "[^;]+") do
	   grpcallString  = grpcallString .. "['ignore_early_media=true,sip_h_X-GroupCallList="..groupCallList..",sip_h_X-CallLogId=${sip_h_X-CallLogId},codec_string=PCMA,PCMU,G722']user/" .. id .. "@" .. sip_domain_name .. ","
    	end
end

grpcallString = string.sub(grpcallString, 1, -2)  -- Remove the trailing "|"

freeswitch.consoleLog("INFO","Group Call String: " ..grpcallString.. "\n");
session:setVariable("grpcallString", grpcallString)

-- Get Auth Token
local access_token = freeswitch.getGlobalVariable("access_token")

-- Hit to Push Notification API

local values = {}
for value in send_groupcall_data:gmatch("([^;]+)") do
    table.insert(values, '"' .. value .. '"')
end
local dialed_number = table.concat(values, ",")
freeswitch.consoleLog("INFO", "Destination numbers : " ..dialed_number)
if (media_type == "true") then
     media_type = "V"
else
     media_type = "A"
end
local call_type = "G"
local notify_json = "{\"domain\":\""..sip_domain_name.."\",\"callerId\":\""..from_num.."\",\"receivers\":["..dialed_number.."],\"mediaType\":\""..media_type.."\",\"callType\":\""..call_type.."\",\"isScreenShared\":false,\"logId\":"..callLogId.."}"
api_call.callNotification(notify_json,access_token)

