local api = freeswitch.API()
-- hup_both.lua

local json = freeswitch.JSON()

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
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

-- ------------------------------------------------------------
-- Fetch variables
-- ------------------------------------------------------------
local call_id        = session:getVariable("call_id")
local caller_id      = session:getVariable("caller_id_number")
local callee_id      = session:getVariable("destination_number")
local callee_numeric = session:getVariable("destination_number")
local hangup_cause   = session:getVariable("hangup_cause")

local caller_joined_at = safe_ts(session:getVariable("start_stamp"))
local callee_joined_at = safe_ts(session:getVariable("answertime"))
local caller_left_at   = safe_ts(session:getVariable("end_stamp"))
local callee_left_at   = safe_ts(session:getVariable("end_stamp"))
local recfilename      = safe_ts(session:getVariable("recfilename"))

-- Prepend full recordings path
if recfilename ~= nil then
    recfilename = "/usr/local/freeswitch-prod-instance/recordings/" .. recfilename
end

-- ------------------------------------------------------------
-- Normalize
-- ------------------------------------------------------------
call_id        = safe(call_id,        "unknown")
caller_id      = safe(caller_id,      "unknown")
callee_id      = safe(callee_id,      "unknown")
callee_numeric = safe(callee_numeric, "unknown")

-- ------------------------------------------------------------
-- Logs
-- ------------------------------------------------------------
freeswitch.consoleLog("INFO", "call_id         : " .. call_id .. "\n")
freeswitch.consoleLog("INFO", "hangup_cause    : " .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "callee_joined_at: " .. tostring(callee_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "recfilename     : " .. tostring(recfilename) .. "\n")

-- ------------------------------------------------------------
-- Status logic
-- ------------------------------------------------------------
local status = "MISSED"

if hangup_cause == "NORMAL_CLEARING" then
    if callee_joined_at ~= nil then
        status = "LEAVE"
    else
        status = "MISSED"
    end
elseif hangup_cause == "NO_ANSWER"
    or hangup_cause == "ORIGINATOR_CANCEL"
    or hangup_cause == "USER_BUSY"
    or hangup_cause == "CALL_REJECTED"
    or hangup_cause == "CONGESTION"
    or hangup_cause == "BUSY" then
    status = "MISSED"
else
    status = "MISSED"
end

if status == "MISSED" then
    recfilename = nil
end

freeswitch.consoleLog("INFO", "status      : " .. status .. "\n")
freeswitch.consoleLog("INFO", "recfilename : " .. tostring(recfilename) .. "\n")

-- Verify file exists
if recfilename ~= nil then
    local test = io.open(recfilename, "r")
    if test then
        test:close()
        freeswitch.consoleLog("INFO", "Recording file found: " .. recfilename .. "\n")
    else
        freeswitch.consoleLog("ERR", "Recording file NOT found: " .. recfilename .. "\n")
        recfilename = nil
    end
end

-- ------------------------------------------------------------
-- Build -F fields
-- ------------------------------------------------------------
local fields =
    "-F " .. sh("call_id="        .. call_id)        .. " " ..
    "-F " .. sh("callee_id="      .. callee_id)      .. " " ..
    "-F " .. sh("callee_numeric=" .. callee_numeric)  .. " " ..
    "-F " .. sh("caller_id="      .. caller_id)      .. " " ..
    "-F " .. sh("status="         .. status)

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

-- ------------------------------------------------------------
-- Execute curl (no auth token)
-- ------------------------------------------------------------
local tmp_out = "/tmp/hup_curl_" .. call_id .. ".json"

local cmd =
    "curl -k -s -X PUT 'https://wapis.discretal.com/calls/sip-call-details' " ..
    fields ..
    " > " .. tmp_out .. " 2>&1"

os.execute(cmd)

-- Read and log response
local f = io.open(tmp_out, "r")
if f then
    local put_resp = f:read("*all")
    f:close()
    os.remove(tmp_out)
    local resp_json = json:decode(put_resp)
    if resp_json and resp_json.httpStatusCode == 200 then
    freeswitch.consoleLog("INFO", "Call logged successfully: " .. tostring(put_resp) .. "\n")
    else
        freeswitch.consoleLog("ERR", "Call log failed: " .. tostring(put_resp) .. "\n")
    end
else
    freeswitch.consoleLog("ERR", "Could not read curl response from " .. tmp_out .. "\n")
end
