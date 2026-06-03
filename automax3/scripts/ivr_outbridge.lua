-- join_call.lua
-- Triggered when the CALLEE answers and the bridge is established (outbridge event).
-- argv[1] = call UUID
--
-- Responsibilities:
--   1. Record the answer timestamp on the channel.
--   2. POST /api/v1/calls/:uuid/join with the CALLEE's phone number.
--      The backend uses this to set start_at and mark the call as ongoing.
--   3. Update the caller's call_status to "in_call".
--   4. Start recording ONLY after a successful join (sets recfilename for end_call.lua).


local json = require "lunajson"

local BASE_URL = "https://epmstg.automaxsw.com"
local FS_EMAIL = "freeswitch@automax.com"
local FS_PASS  = "Leader@123"

local api = freeswitch.API()

local uuid = argv[1]

freeswitch.consoleLog("INFO", "BRIDGE LUA EXECUTED\n")
local api = freeswitch.API()

-- Start recording
api:executeString(
    "uuid_record " ..
    uuid ..
    " start /usr/local/freeswitch/recordings/" ..
    uuid ..
    ".wav"
)
--local caller_num = session:getVariable("caller_id_number")  or ""
local caller_num = session:getVariable("created_by")  or ""
--local callee_num = session:getVariable("callee_num") or ""
local cc_agent = session:getVariable("cc_agent") or ""
local callee_num = cc_agent or ""

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function log(level, msg)
    freeswitch.consoleLog(level, "[join_call] " .. msg .. "\n")
end

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

-- ── Auth ─────────────────────────────────────────────────────────────────────

local function get_token()
    -- Reuse token stored by start_call.lua when possible
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

-- ── Record answer timestamp ───────────────────────────────────────────────────
--local answer_time== session:getVariable("answertime_ivr") or ""
-- ── Main ─────────────────────────────────────────────────────────────────────

if callee_num == "" then
    log("ERR", "callee number is empty — aborting join")
    return
end

local token = get_token()
if not token then
    log("ERR", "could not obtain auth token — aborting")
    return
end

-- Update caller call_status to in_call
if caller_num ~= "" then
    local status_url  = BASE_URL .. "/api/v1/users/" .. caller_num .. "/status?token=" .. token
    local status_resp = fs_curl(status_url, "PUT", token, json_encode({ call_status = "in_call" }))
    log("INFO", "caller status response: " .. tostring(status_resp))
end

-- Join as the CALLEE — this is what sets start_at on the call log
local join_payload = json_encode({ phone = callee_num })
local join_url     = BASE_URL .. "/api/v1/calls/" .. uuid .. "/join?token=" .. token

log("INFO", "join payload: " .. join_payload)

local resp    = fs_curl(join_url, "POST", token, join_payload)
local decoded = resp and json.decode(resp)

log("INFO", "join response: " .. tostring(resp))

if not decoded or decoded.success == false then
    log("ERR", "join call API failed — recording will NOT start")
    return
end

