api = freeswitch.API();


freeswitch.consoleLog("INFO", "Agent UUID watcher started...\n")

-- Subscribe to channel hangups
local ev = freeswitch.EventConsumer("CHANNEL_HANGUP_COMPLETE")

while true do
    local e = ev:pop(1000)
    if e then
        local uuid = e:getHeader("Unique-ID")
        local name = e:getHeader("Channel-Name")
        local cause = e:getHeader("Hangup-Cause")
        local role = e:getHeader("Call-Direction")
       -- local callee_number = e:getHeader("variable_cc_agent")
        local cc_queue = e:getHeader("variable_cc_queue")
	local duration = e:getHeader("variable_billsec")  
        local caller   = e:getHeader("Caller-Caller-ID-Number")
        local callee_number   = e:getHeader("Caller-Destination-Number")
	local callee_left_at = e:getHeader("variable_end_stamp")
        local agent    = e:getHeader("variable_cc_agent")

	local call_id = e:getHeader("variable_callLogId") or e:getHeader("variable_sip_h_X-CallLogId")
	local caller_joined_at = e:getHeader("variable_start_stamp") 
	--local caller_joined_at = tostring(session:getVariable("variable_caller_start")
--	freeswitch.consoleLog("INFO", e:serialize() .. "\n")


	--     local a_leg_uuid =  e:getHeader("variable_cc_member_uuid") or e:getHeader("variable_signal_bond") or e:getHeader("Other-Leg-Unique-ID") or ""	
	-- freeswitch.consoleLog("INFO", "Caller UUID (A-leg): " .. tostring(a_leg_uuid) .. "\n")
--	local call_id = api:execute("uuid_getvar", a_leg_uuid .. " callLogId")
--	local caller = api:execute("uuid_getvar", a_leg_uuid .. " Caller-ANI")

local callee_joined_at = 'null'
  caller_left_at = 'in_call';
       -- if callee_number and cause then
          if callee_number and cause and #callee_number < 4 then 
            if cause == "USER_BUSY"  or cause == "NO_ANSWER" then
	     if cause == "USER_BUSY" then status = "AGENT_REJECT"
		elseif cause =="NO_ANSWER" then status = "NO_ANSWER"
	       end
	-- freeswitch.consoleLog("INFO", e:serialize() .. "\n")

            freeswitch.consoleLog("INFO", "status: " .. tostring(status) .. "\n")
	    freeswitch.consoleLog("INFO", "Caller_joined_at: " .. tostring(caller_joined_at) .. "\n")
            freeswitch.consoleLog("INFO", "callee: " .. tostring(callee_number) .. "\n")	
            freeswitch.consoleLog("INFO", "callee_joined_at at: " .. tostring(callee_joined_at) .. "\n")
	    freeswitch.consoleLog("INFO", "Callee left at at: " .. tostring(callee_left_at) .. "\n")
local payload = string.format(
  '{"call_id":"%s","caller":"%s","callee_number":"%s","caller_joined_at":"%s","caller_left_at":"%s","callee_joined_at":"%s","callee_left_at":"%s","status":"%s","duration":%d}',
  call_id, caller, callee_number, caller_joined_at, caller_left_at,
  callee_joined_at, callee_left_at, status, duration
)
freeswitch.consoleLog("INFO", "Payload: " .. payload .. "\n")

-- API call
local curl_cmd = string.format(
  "https://wapis.discretal.com/calls/update-external-sip-call-details content-type application/json put '%s'",
  payload
)

freeswitch.consoleLog("INFO", "Final curl cmd: " .. curl_cmd .. "\n")

-- Execute request
local response = api:execute("curl", curl_cmd)

freeswitch.consoleLog("INFO", "API Response: " .. tostring(response) .. "\n")



    end
        end
    end
end

