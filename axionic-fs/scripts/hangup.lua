-- siphangup.lua
local api  = freeswitch.API()
local json = freeswitch.JSON()

local uuid = argv[1]

if not uuid or uuid == "" then
    freeswitch.consoleLog("ERR", "Usage: lua siphangup.lua <uuid>\n")
    return
end

-- Skip if busy rejection
local skip = session:getVariable("skip_hangup_log")
if skip == "true" then
    freeswitch.consoleLog("NOTICE", "Skipping hangup log — busy rejection\n")
    return
end

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

local function to_utc_string(epoch)
    epoch = tonumber(epoch)
    if not epoch or epoch <= 0 then return nil end
    if epoch > 9999999999 then epoch = math.floor(epoch / 1000) end
    return os.date("%Y-%m-%d %H:%M:%S", epoch)
end

-- ---------------- FETCH VARIABLES ----------------
local call_id          = safe(session:getVariable("callLogId"), "unknown")
local caller           = safe(session:getVariable("caller_id_number"), "unknown")
local hangup_cause     = session:getVariable("hangup_cause")
local duration         = tonumber(session:getVariable("billsec")) or 0

local caller_joined_at = safe_ts(session:getVariable("start_stamp"))
local caller_left_at   = safe_ts(session:getVariable("end_stamp"))
local callee_left_at   = safe_ts(session:getVariable("end_stamp"))

local answered_by_agent = session:getVariable("cc_queue_answered_epoch")
local callee_joined_at  = to_utc_string(answered_by_agent)

local callee_number    = safe_ts(session:getVariable("cc_agent"))
                      or safe_ts(session:getVariable("destination_number"))

local recfilename      = safe_ts(session:getVariable("recfilename"))

-- Prepend recordings path
local recordings_dir = "/usr/local/freeswitch-prod-instance/recordings/"
if recfilename ~= nil then
    recfilename = recordings_dir .. recfilename
end

-- If callee_number > 4 digits → nil (external number)
if callee_number and #callee_number > 4 then
    callee_number = nil
end

-- ---------------- LOGS ----------------
freeswitch.consoleLog("INFO", "call_id        : " .. call_id .. "\n")
freeswitch.consoleLog("INFO", "caller         : " .. caller .. "\n")
freeswitch.consoleLog("INFO", "callee_number  : " .. tostring(callee_number) .. "\n")
freeswitch.consoleLog("INFO", "hangup_cause   : " .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "caller_joined  : " .. tostring(caller_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "caller_left    : " .. tostring(caller_left_at) .. "\n")
freeswitch.consoleLog("INFO", "callee_joined  : " .. tostring(callee_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "callee_left    : " .. tostring(callee_left_at) .. "\n")
freeswitch.consoleLog("INFO", "recfilename    : " .. tostring(recfilename) .. "\n")
freeswitch.consoleLog("INFO", "duration       : " .. tostring(duration) .. "\n")

-- ---------------- STATUS LOGIC ----------------
local status = "MISSED"

if hangup_cause == "NO_ANSWER"
    or hangup_cause == "ORIGINATOR_CANCEL"
    or hangup_cause == "USER_BUSY"
    or hangup_cause == "CALL_REJECTED"
    or hangup_cause == "CONGESTION"
    or hangup_cause == "BUSY" then
    status   = "MISSED"
    duration = 0

elseif hangup_cause == "NORMAL_CLEARING" then
    if answered_by_agent ~= nil then
        status = "ENDED"
    else
        status = "CALL_BACK"
    end
else
    status = "FAILED"
end

-- No recording for non-ENDED calls
if status ~= "ENDED" then
    recfilename = nil
end

-- No callee_left_at if not answered
if callee_joined_at == nil then
    callee_left_at = nil
end

freeswitch.consoleLog("INFO", "status         : " .. status .. "\n")
freeswitch.consoleLog("INFO", "recfilename    : " .. tostring(recfilename) .. "\n")

-- Verify recording file exists
if recfilename ~= nil then
    local f = io.open(recfilename, "r")
    if f then
        f:close()
        freeswitch.consoleLog("INFO", "Recording found: " .. recfilename .. "\n")
    else
        freeswitch.consoleLog("ERR", "Recording NOT found: " .. recfilename .. "\n")
        recfilename = nil
    end
end

-- ---------------- BUILD CURL (multipart) ----------------
local tmp_out = "/tmp/siphangup_" .. call_id .. ".json"

local fields =
    "-F " .. sh("call_id=" .. call_id)          .. " " ..
    "-F " .. sh("caller="  .. caller)            .. " " ..
    "-F " .. sh("status="  .. status)            .. " " ..
    "-F " .. sh("duration=" .. tostring(duration))

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

-- Kill uuid
api:executeString("uuid_kill " .. uuid)
