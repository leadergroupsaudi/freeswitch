-- end_call.lua
-- Triggered on channel hangup.
-- Determines the final call status from FreeSwitch hangup variables,
-- then POSTs to /api/v1/calls/:uuid/end.
-- Uploads the recording (if any) and cleans up the local file.


local json  = require "lunajson"
local http  = require "socket.http"
local ltn12 = require "ltn12"

local BASE_URL = "https://epmstg.automaxsw.com"
local FS_EMAIL = "freeswitch@automax.com"
local FS_PASS  = "Leader@123"

local api = freeswitch.API()

local call_uuid      = tostring(session:getVariable("UUID"))
--local caller_num     = session:getVariable("caller_id_number")  or ""
--local callee_num     = session:getVariable("destination_number") or ""
local hangup_cause   = session:getVariable("hangup_cause")       or ""
local bridge_hangup  = session:getVariable("bridge_hangup_cause") or ""
local sip_cause      = session:getVariable("last_bridge_proto_specific_hangup_cause") or ""
local originate_disp = session:getVariable("originate_disposition") or ""

local callee_joined  = session:getVariable("answertime_ivr")         or ""
--local callee_joined  = answer_time or ""
local recfilename    = session:getVariable("recfilename")        or ""
local end_stamp      = session:getVariable("end_stamp")          or ""

local caller_num     = session:getVariable("created_by")  or ""
local callee_num    = session:getVariable("callee_num") or ""

freeswitch.consoleLog("INFO", "ivr callee_joined           : " .. callee_joined           .. "\n")
freeswitch.consoleLog("INFO", "ivr caller_num1           : " .. caller_num           .. "\n")
freeswitch.consoleLog("INFO", "ivr callee_num1           : " .. callee_num           .. "\n")

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function log(level, msg)
    freeswitch.consoleLog(level, "[end_call] " .. msg .. "\n")
end
freeswitch.consoleLog("INFO", "[outboundhangup] RAW SCRIPT STARTED - argv1=" .. tostring(argv[1]) .. "\n")
local function json_encode(val)
    local t = type(val)
    if t == "nil"     then return "null" end
    if t == "boolean" then return tostring(val) end
    if t == "number"  then return tostring(val) end
    if t == "string"  then
        return '"' .. val:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
    end
    if t == "table" then
        if #val > 0 then
            local a = {}
            for _, v in ipairs(val) do a[#a+1] = json_encode(v) end
            return "[" .. table.concat(a, ",") .. "]"
        else
            local o = {}
            for k, v in pairs(val) do
                if v ~= nil then
                    o[#o+1] = '"' .. k .. '":' .. json_encode(v)
                end
            end
            return "{" .. table.concat(o, ",") .. "}"
        end
    end
    return "null"
end

local function fs_curl(url, method, token, body)
    local auth = (token and token ~= "")
        and ("-H 'Authorization: Bearer " .. token .. "' ")
        or ""
    local cmd = string.format(
        "%s content-type application/json %s-H 'Accept: application/json' %s '%s'",
        url, auth, method:lower(), body
    )
    return api:executeString("curl " .. cmd)
end

local function to_iso(ts)
    if not ts or ts == "" then return nil end
    return ts:gsub(" ", "T") .. "Z"
end

local function delete_recording(path)
    os.execute("rm -f " .. path)
    log("INFO", "deleted recording: " .. path)
end

-- ── Auth ─────────────────────────────────────────────────────────────────────

local function get_token()
    local cached = session:getVariable("access_token")
    if cached and cached ~= "" then return cached end

    local body   = json_encode({ email = FS_EMAIL, password = FS_PASS })
    local result = fs_curl(BASE_URL .. "/api/v1/auth/login", "POST", nil, body)
    if not result or result == "" then
        log("ERR", "auth request returned empty response")
        return nil
    end
    local data = json.decode(result)
    if not data or not data.data or not data.data.token then
        log("ERR", "auth response missing token: " .. result)
        return nil
    end
    local t = data.data.token
    session:setVariable("access_token", t)
    return t
end

-- ── Status logic ─────────────────────────────────────────────────────────────

local status = "missed"

if hangup_cause == "USER_NOT_REGISTERED" or hangup_cause == "SUBSCRIBER_ABSENT" then
    status = "offline"

elseif hangup_cause == "USER_BUSY" or sip_cause == "sip:486" then
    status = (bridge_hangup ~= "" and bridge_hangup ~= "nil") and "busy" or "declined"

elseif hangup_cause == "CALL_REJECTED" or sip_cause == "sip:603" or sip_cause == "603" then
    status = "declined"

elseif sip_cause == "sip:480" and originate_disp == "NO_USER_RESPONSE" then
    status = "declined"

elseif originate_disp == "ORIGINATOR_CANCEL" or hangup_cause == "ORIGINATOR_CANCEL" then
    status = "cancelled"

elseif hangup_cause == "NO_ANSWER" or originate_disp == "NO_ANSWER" then
    status = "missed"

elseif hangup_cause == "NORMAL_CLEARING" then
    status = (callee_joined ~= "" and callee_joined ~= "null") and "completed" or "cancelled"
end

log("INFO", string.format(
    "call_uuid=%s status=%s hangup=%s bridge_hangup=%s sip=%s originate=%s callee_joined=%s",
    call_uuid, status, hangup_cause, bridge_hangup, sip_cause, originate_disp, callee_joined
))

-- ── End call ─────────────────────────────────────────────────────────────────

local token = get_token()
if not token then
    log("ERR", "could not obtain auth token — aborting")
    if recfilename ~= "" then delete_recording("/usr/local/freeswitch/recordings/" .. recfilename) end
    return
end

local end_at      = to_iso(end_stamp) or os.date("!%Y-%m-%dT%H:%M:%SZ")
local end_payload = json_encode({ status = status, end_at = end_at })
local end_url     = BASE_URL .. "/api/v1/calls/" .. call_uuid .. "/end?token=" .. token

log("INFO", "end payload: " .. end_payload)

local end_resp    = fs_curl(end_url, "POST", token, end_payload)
local end_decoded = end_resp and json.decode(end_resp)

log("INFO", "end response: " .. tostring(end_resp))

if not end_decoded or end_decoded.success == false then
    log("ERR", "end call API failed — skipping recording upload")
    if recfilename ~= "" then delete_recording("/usr/local/freeswitch/recordings/" .. recfilename) end
    return
end

-- ── Update user status ───────────────────────────────────────────────────────

if callee_joined ~= "" and callee_joined ~= "null" and caller_num ~= "" then
    local status_url  = BASE_URL .. "/api/v1/users/" .. caller_num .. "/status?token=" .. token
    local status_resp = fs_curl(status_url, "PUT", token, json_encode({ call_status = "available" }))
    log("INFO", "caller status response: " .. tostring(status_resp))
end

-- ── Upload recording ─────────────────────────────────────────────────────────

if recfilename == "" then return end

local file_path = "/usr/local/freeswitch/recordings/" .. recfilename

if status ~= "completed" then
    delete_recording(file_path)
    return
end

local f = io.open(file_path, "rb")
if not f then
    log("ERR", "recording not found: " .. file_path)
    return
end
local file_data = f:read("*all")
f:close()

local boundary = "----LuaBoundary" .. call_uuid
local body = "--" .. boundary .. "\r\n"
    .. 'Content-Disposition: form-data; name="file"; filename="' .. recfilename .. '"' .. "\r\n"
    .. "Content-Type: audio/wav\r\n\r\n"
    .. file_data .. "\r\n"
    .. "--" .. boundary .. "--\r\n"

local attach_resp = {}
local attach_url  = BASE_URL .. "/api/v1/calls/" .. call_uuid .. "/attachments?token=" .. token

local _, code = http.request({
    url    = attach_url,
    method = "POST",
    headers = {
        ["Authorization"] = "Bearer " .. token,
        ["Content-Type"]  = "multipart/form-data; boundary=" .. boundary,
        ["Content-Length"] = tostring(#body),
        ["Accept"]        = "application/json",
    },
    source = ltn12.source.string(body),
    sink   = ltn12.sink.table(attach_resp),
})

log("INFO", "upload HTTP code: " .. tostring(code))
log("INFO", "upload response:  " .. table.concat(attach_resp))

delete_recording(file_path)
