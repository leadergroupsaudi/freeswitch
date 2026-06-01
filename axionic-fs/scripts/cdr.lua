freeswitch.consoleLog("INFO","conference cdr maintainance event was caught in cdr_event.lua\n")
api = freeswitch.API()
--local xml2lua = require("LuaXML")
local xml2lua = require("xml2lua")
local handler = require("xmlhandler.tree")
local xml = require("xml")
json = freeswitch.JSON()
local jsonLib = require "lunajson"

local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path
local api_call = require "lua-functions/api_call"
local config = require "lua-functions/config"

event_data = event:serialize();
freeswitch.consoleLog("NOTICE", "\n [Axionic] Conference:cdr event = " .. event_data);
local cdr_xml = event_data:match("<%?xml version=\"1%.0\"%?>.+")
freeswitch.consoleLog("INFO","\n CDR xml data is" ..cdr_xml);

-- Access the parsed XML structure

local xmlParser = xml2lua.parser(handler)
xmlParser:parse(cdr_xml)
local xmlTable = handler.root

-- Extract start_time
local start_time = event_data:match('<start_time type="UNIX%-epoch">(.-)</start_time>')
local startTime = os.date("%Y-%m-%dT%H:%M:%SZ", start_time)
-- Extract end_time
local end_time = event_data:match('<end_time.-type="UNIX%-epoch">(.-)</end_time>')
local endTime = os.date("%Y-%m-%dT%H:%M:%SZ", end_time)
local call_duration = end_time - start_time
local join_time = event_data:match('<join_time type="UNIX%-epoch">(.-)</join_time>')
--local callLogId = event_data:match('<name>(.-)</name>')
local callLogId = event_data:match('<name>.*_(%d+)</name>')
callLogId = tonumber(callLogId:match("(%d+)"))

freeswitch.consoleLog("INFO","start_time:" .. startTime)
freeswitch.consoleLog("INFO","end_time:" .. endTime)
freeswitch.consoleLog("INFO","call Duration:" ..call_duration)
freeswitch.consoleLog("INFO","calllogId:" ..callLogId)
local access_token = freeswitch.getGlobalVariable("access_token")
local get_callLogs = api:execute("curl", config.api.getCallLogs_api .. callLogId .." append_headers 'Authorization: Bearer "..access_token.."' get ")
freeswitch.consoleLog("INFO","get call log Details:" ..get_callLogs)
get_callLogs = json:decode(get_callLogs)
callLog_response = get_callLogs.response
callLog_response.callDuration = ""..tostring(call_duration).."";
callLog_response.startTime = startTime;
callLog_response.endTime = endTime;
callLog_response.CallStatus = "E";

for i, participant in ipairs(callLog_response.callParticipantsList) do
        local callerId = participant.callerId
        freeswitch.consoleLog("INFO","Participant callerID: " ..callerId)
  for _, member in ipairs(xmlTable.cdr.conference.members.member) do
        freeswitch.consoleLog("INFO","XML CDR Participant ")
    if member.caller_profile ~= nil then

freeswitch.consoleLog("INFO", "Caller profile is there in XML: ")
    -- Check if caller_id_number is present within caller_profile
  	  local callerIdNumber = member.caller_profile.caller_id_number 
	freeswitch.consoleLog("INFO", "Caller ID Number from XML: " .. tostring(callerIdNumber))
    -- Check if both joinTime and callerIdNumber are present before logging
        if callerId == tostring(callerIdNumber) then
		local joinTime = member.join_time[1]
		joinTime = os.date("%Y-%m-%dT%H:%M:%SZ", joinTime)
		freeswitch.consoleLog("INFO","Updating Answer Status condition: ")
                participant.answerStatus = "A"
                participant.callReachTime = joinTime
        end
      end
end
end

callLog_response = jsonLib.encode(callLog_response)
freeswitch.consoleLog("INFO","call log Details after update:" ..callLog_response)
local updateAfterCall_response = api:execute("curl", config.api.updateAfterCall_api.." append_headers 'Authorization: Bearer "..access_token.."' content-type application/JSON put " ..callLog_response)
freeswitch.consoleLog("INFO","Response from API for Update Calllogs : " ..updateAfterCall_response)
