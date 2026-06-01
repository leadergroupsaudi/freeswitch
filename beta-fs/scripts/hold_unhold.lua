--digits = session:getDigits(2, "#", 3000);
digits = argv[1]
freeswitch.consoleLog("INFO","Digits:: "..digits)
local json = require "lunajson"
api = freeswitch.API()
local conferenceId = session:getVariable("conference_name")
local sessionuser =  session:getVariable("channel_name")
local conference_jsonList = api:executeString("conference "..conferenceId.." json_list")
local conference_data = json.decode(conference_jsonList)
local holduser = sessionuser:match("(%d+)@")
freeswitch.consoleLog("INFO","From User:: "..holduser)

local function getMembers()
	local member_id,member_uuid;
	for _, member in ipairs(conference_data[1]["members"]) do
                if member["caller_id_number"] == tostring(holduser) then
                member_id = member["id"]
                member_uuid = member["uuid"]
                --id_found = true
                return member_id,member_uuid
            end
        end
end

local function getRemoteMember(id)
        for _, member in ipairs(conference_data[1]["members"]) do
                if member["id"] ~= id then
                remote_member_uuid = member["uuid"]
                --id_found = true
                return remote_member_uuid
            end
        end
end

if digits == "87" or digits == "71" then --call Hold
	local member_count = conference_data[1].member_count
	freeswitch.consoleLog("INFO","Memebr Count:: "..member_count)
	member_id,member_uuid = getMembers()
	freeswitch.consoleLog("INFO","Memebr ID:: "..member_id.." :: Memmer UUID:: "..member_uuid)
        hold_command = "conference "..conferenceId.." hold "..member_id
        deaf_command = "conference "..conferenceId.." deaf "..member_id
        holdResult = api:executeString(hold_command)
        deafResult = api:executeString(deaf_command)
        freeswitch.consoleLog("INFO"," Hold Command Result:: "..holdResult)
        freeswitch.consoleLog("INFO"," Deaf Command Result:: "..deafResult)

	--if member_count < 3 then
        --        remot_member_uuid = getRemoteMember(member_id)
        --        send_moh = api:executeString("uuid_broadcast "..remote_member_uuid.." local_stream://moh")
        --        freeswitch.consoleLog("INFO"," Send MOH Result:: "..send_moh)
	--end
elseif digits == "88" or digits == "72" then --call Un-Hold
        local member_count = conference_data[1]["member_count"]
	member_id,member_uuid = getMembers()
        freeswitch.consoleLog("INFO","Memebr ID:: "..member_id.." :: Memmer UUID:: "..member_uuid)
                unhold_command = "conference "..conferenceId.." unhold "..member_id
		undeaf_command = "conference "..conferenceId.." undeaf "..member_id
                unholdResult = api:executeString(unhold_command)		
		undeafResult = api:executeString(undeaf_command)
		freeswitch.consoleLog("INFO"," Un-Hold Command Result:: "..unholdResult)
		freeswitch.consoleLog("INFO"," Un Deaf Command Result:: "..undeafResult)
        --if member_count < 3 then
        --        remot_member_uuid = getRemoteMember(member_id)
        --        break_moh = api:executeString("uuid_break "..remote_member_uuid)
        --        freeswitch.consoleLog("INFO"," Break MOH Command Result:: "..break_moh)	
	--end
else 
	freeswitch.consoleLog("INFO"," Invalid Hold or Un-hold Key received ")
end
