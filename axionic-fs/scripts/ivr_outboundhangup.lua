-- outboundhangup.lua
local api  = freeswitch.API()
local json = freeswitch.JSON()

-- ---------------- HELPERS ----------------
local function safe(value, default)
    if value == nil or value == "" or value == "nil" then
        return default
    end
    return value
end

local function safe_ts(value)
    if value == nil or value == "" or value == "nil" then
        return nil
    end
    return value
end

local function sh(value)
    if value == nil then return "''" end
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- ---------------- FETCH VARIABLES ----------------
local call_id          = safe(session:getVariable("callLogId"), "unknown")
local caller           = safe(session:getVariable("caller_id_number"), "unknown")
local hangup_cause     = session:getVariable("hangup_cause")
local duration         = tonumber(session:getVariable("billsec")) or 0

local caller_joined_at = safe_ts(session:getVariable("start_stamp"))
local caller_left_at   = safe_ts(session:getVariable("end_stamp"))
local callee_joined_at = safe_ts(session:getVariable("answertime"))
local callee_left_at   = safe_ts(session:getVariable("end_stamp"))
local recfilename      = safe_ts(session:getVariable("recfilename"))
local callee_number = session:getVariable("destination_number")
                 or session:getVariable("dialed_number")
                 or session:getVariable("sip_to_user")

freeswitch.consoleLog("INFO", "Destination: " .. tostring(destination) .. "\n")
if destination == "9920009276" then return end
-- Prepend recordings path
local recordings_dir = "/usr/local/freeswitch-prod-instance/recordings/"
if recfilename ~= nil then
    recfilename = recordings_dir .. recfilename
end

freeswitch.consoleLog("INFO", "callee_number  : " .. tostring(callee_number) .. "\n")
-- If callee_number > 4 digits → nil (external number, not an extension)
--if callee_number and #callee_number > 4 then
  --  callee_number = nil
--end

-- ---------------- LOGS ----------------
freeswitch.consoleLog("INFO", "call_id        : " .. call_id .. "\n")
freeswitch.consoleLog("INFO", "caller         : " .. caller .. "\n")

freeswitch.consoleLog("INFO", "callee_number  : " .. tostring(callee_number) .. "\n")
freeswitch.consoleLog("INFO", "hangup_cause   : " .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "caller_joined  : " .. tostring(caller_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "caller_left    : " .. tostring(caller_left_at) .. "\n")
freeswitch.consoleLog("INFO", "callee_joined  : " .. tostring(callee_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "recfilename    : " .. tostring(recfilename) .. "\n")
freeswitch.consoleLog("INFO", "duration       : " .. tostring(duration) .. "\n")


-- ---------------- STATUS LOGIC ----------------
local status = "MISSED"

if hangup_cause == "NORMAL_CLEARING" and callee_joined_at ~= nil then
    status = "ENDED"

elseif hangup_cause == "UNALLOCATED_NUMBER" then
	return
elseif hangup_cause == "USER_BUSY" then
    status = "CLIENT_REJECT"
elseif hangup_cause == "NO_ANSWER"
    or hangup_cause == "ORIGINATOR_CANCEL"
    or hangup_cause == "CALL_REJECTED"
    or hangup_cause == "CONGESTION"
    or hangup_cause == "BUSY" then
    status = "MISSED"
    duration = 0
else
    status = "FAILED"
end

-- No recording for non-answered calls
if status ~= "ENDED" then
    recfilename = nil
end

-- If no callee_joined_at, clear callee_left_at too
if callee_joined_at == nil then
    callee_left_at = nil
    status ="MISSED"
end

freeswitch.consoleLog("INFO", "status         : " .. status .. "\n")
freeswitch.consoleLog("INFO", "recfilename    : " .. tostring(recfilename) .. "\n")

-- Verify recording file exists
if recfilename ~= nil then
    local f = io.open(recfilename, "r")
    if f then
        f:close()
        freeswitch.consoleLog("INFO", "Recording file found: " .. recfilename .. "\n")
    else
        freeswitch.consoleLog("ERR", "Recording file NOT found: " .. recfilename .. "\n")
        recfilename = nil
    end
end

-- ---------------- BUILD CURL (multipart) ----------------
local tmp_out = "/tmp/outboundhangup_" .. call_id .. ".json"

-- Only add callee_number if it is a valid number
local fields =
    "-F " .. sh("call_id="  .. call_id)          .. " " ..
    "-F " .. sh("caller="   .. caller)            .. " " ..
    "-F " .. sh("status="   .. status)            .. " " ..
    "-F " .. sh("duration=" .. tostring(duration))

-- callee_number: only add if not nil (API expects bigint, skip if unknown)
if callee_number ~= nil then
    fields = fields .. " -F " .. sh("callee_number=" .. callee_number)
end
if caller_joined_at ~= nil then
    fields = fields .. " -F " .. sh("caller_joined_at=" .. caller_joined_at)
end
if caller_left_at ~= nil then
    fields = fields .. " -F " .. sh("caller_left_at=" .. caller_left_at)
end
if callee_joined_at ~= nil then
    fields = fields .. " -F " .. sh("callee_joined_at=" .. callee_joined_at)
end
if callee_left_at ~= nil then
    fields = fields .. " -F " .. sh("callee_left_at=" .. callee_left_at)
end
if recfilename ~= nil then
    fields = fields .. " -F " .. sh("file=@" .. recfilename)
end

local cmd =
    "curl -k -s -X PUT 'https://wapis.discretal.com/calls/update-external-sip-call-details' " ..
    fields ..
    " > " .. tmp_out .. " 2>&1"

-- Print full curl command for debugging
freeswitch.consoleLog("INFO", "Curl cmd: " .. cmd .. "\n")

os.execute(cmd)

-- Read response
local f = io.open(tmp_out, "r")
if f then
    local response = f:read("*all")
    f:close()
    os.remove(tmp_out)
    freeswitch.consoleLog("INFO", "API Response: " .. tostring(response) .. "\n")
else
    freeswitch.consoleLog("ERR", "Could not read curl response\n")
end
