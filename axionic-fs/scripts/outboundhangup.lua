local api = freeswitch.API()
local json = freeswitch.JSON()

--local uuid = argv[1]

--if not uuid or uuid == "" then
--    freeswitch.consoleLog("ERR", "Usage: lua hup_both.lua <uuid>\n")
--    return
--end


local call_id =tostring(session:getVariable("callLogId"));
local agent_name = session:getVariable("variable_cc_agent")
local caller = session:getVariable("caller_id_number")
local duration = tonumber(session:getVariable("billsec")) 
local hangup_cause = session:getVariable("hangup_cause")

local caller = session:getVariable("caller_id_number") 
local caller2 =session:getVariable("ani")

local callee = session:getVariable("cc_agent")
local agent_uuid = session:getVariable("cc_agent_uuid")
local callee_joined_at = session:getVariable("answertime")
local joined_at = session:getVariable("cc_queue_joined_epoch")
local terminated_at = session:getVariable("cc_queue_terminated_epoch")
-- Get the Callee/Destination Number (using common variable names)

local caller_joined_at = tostring(session:getVariable("start_stamp"))

local caller_left_at = tostring(session:getVariable("end_stamp"))
local callee_left_at = tostring(session:getVariable("end_stamp"))

local callee_number = tostring(session:getVariable("destination_number"))
local callee_num2 =session:getVariable("destination_number")

freeswitch.consoleLog("INFO", "billsec at: " .. tostring(duration) .. "\n")
freeswitch.consoleLog("INFO", "caller_joined_at at: " .. tostring(caller_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "Caller left at at: " .. tostring(caller_left_at) .. "\n")

local function to_utc_string(epoch)
    epoch = tonumber(epoch)
    if not epoch or epoch <= 0 then return "NONE" end
    if epoch > 9999999999 then epoch = math.floor(epoch / 1000) end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end
-- Convert each timestamp
--local callee_joined_at = tostring(to_utc_string(answertime))
--local callee_left_at =tostring( to_utc_string(caller_left_at))
-- Log results
if callee_joined_at == nil or callee_joined_at == "" then
    callee_joined_at = 'null'
     callee_left_at = 'null'
end
--]]
hangup_cause = session:getVariable("hangup_cause");
hangup_cause_q850 = session:getVariable("hangup_cause_q850");
sip_hangup_disposition = session:getVariable("sip_hangup_disposition");
sip_term_cause = session:getVariable("sip_term_cause");
proto_specific_hangup_cause = session:getVariable("proto_specific_hangup_cause");
sip_term_status = session:getVariable("sip_term_status");
endpoint_disposition = session:getVariable("endpoint_disposition");

freeswitch.consoleLog("info","hangup_cause  is: "..tostring(hangup_cause));
freeswitch.consoleLog("info","hangup_cause_q850  is: "..tostring(hangup_cause_q850));
freeswitch.consoleLog("info","sip_hangup_disposition is: "..tostring(sip_hangup_disposition));
freeswitch.consoleLog("info","sip_term_cause  is: "..tostring(sip_term_cause));
freeswitch.consoleLog("info","proto_specific_hangup_cause  is: "..tostring(proto_specific_hangup_cause));
freeswitch.consoleLog("info","sip_term_status  is: "..tostring(sip_term_status));
freeswitch.consoleLog("info","endpoint_disposition  is: "..tostring(endpoint_disposition));

freeswitch.consoleLog("INFO", "callee_joined_at: " .. callee_joined_at .. "\n")
freeswitch.consoleLog("INFO", "callee_left_at: " .. callee_left_at .. "\n")
freeswitch.consoleLog("info","callerhost caller_left_at  is: "..tostring(caller_left_at));
freeswitch.consoleLog("info","extension-DID number  is: "..tostring(callee));
freeswitch.consoleLog("info","callee  is: "..tostring(caller));
freeswitch.consoleLog("info","answerstamp  is: "..tostring(answerstamp));
freeswitch.consoleLog("info","caller_joined_at  is: "..tostring(caller_joined_at));
freeswitch.consoleLog("info","caller  is: "..tostring(caller));
freeswitch.consoleLog("info","call_id is: "..tostring(caller2));
freeswitch.consoleLog("info"," callee_number: "..tostring(callee_number));
freeswitch.consoleLog("info"," callee_number  is: "..tostring( callee_num2));
-- Status logic
local function safe(value, default)
  if value == nil or value == '' then
    return default
  end
  return value
end
local call_id         = safe(call_id, "unknown")
local caller          = safe(caller, "unknown")
local callee_number   = safe(callee_number, "unknown")
local caller_left_at   = safe(caller_left_at, "")
local callee_left_at   = safe(callee_left_at, "")
local status          = safe(status, "UNKNOWN")
local duration        = tonumber(safe(duration, 0))  -- ensure it's a number


--local status, callee_left_at = "UNKNOWN", "", ""
if hangup_cause == "NO_ANSWER" or hangup_cause == "ORIGINATOR_CANCEL"
      or hangup_cause == "CALL_REJECTED"
    or hangup_cause == "CONGESTION" or hangup_cause == "BUSY" then
    status = "MISSED"
    billsec = 0
elseif  hangup_cause == "USER_BUSY" then
	status ="CLIENT_REJECT"
elseif hangup_cause == "NORMAL_CLEARING"  and callee_joined_at ~= nil then
--  if  callee_joined_at  ~= nil then
        status = "ENDED"
--    else
--        status = "CLIENT_REJECT"
--  end

   -- callee_joined_at = caller_joined_at
   -- callee_left_at = caller_left_at
else
    status = "FAILED"
end

--freeswitch.consoleLog("INFO", "iiiiii------------:Callee_joined_at: " .. callee_joined_at .. "\n")

-- Build JSON payload manually
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

