-- start_call.lua
-- Triggered at the beginning of an outgoing call (before ringing).
-- Registers the call with EPM via POST /api/v1/calls/start.
-- The token is stored on the session for reuse by join_call.lua / end_call.lua.

local json = require "lunajson"

local BASE_URL = "https://epmstg.automaxsw.com"
local FS_EMAIL = "freeswitch@automax.com"
local FS_PASS  = "Leader@123"

local api = freeswitch.API()

local call_uuid  = tostring(session:getVariable("UUID"))
local caller_num = session:getVariable("caller_id_number")  or ""
local callee_num = session:getVariable("destination_number") or ""

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function log(level, msg)
    freeswitch.consoleLog(level, "[start_call] " .. msg .. "\n")
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
    return data.data.token
end

-- ── Main ─────────────────────────────────────────────────────────────────────

log("INFO", string.format("call_uuid=%s caller=%s callee=%s", call_uuid, caller_num, callee_num))

if caller_num == "" or callee_num == "" then
    log("ERR", "caller or callee number is empty — aborting")
    return
end

local token = get_token()
if not token then
    log("ERR", "could not obtain auth token — aborting")
    return
end
session:setVariable("access_token", token)

local payload = json_encode({
    call_uuid = call_uuid,
    call_type = "direct",
    initiator = { phone = caller_num },
    recipient = { phone = callee_num },
})

log("INFO", "payload: " .. payload)

local resp    = fs_curl(BASE_URL .. "/api/v1/calls/start?token=" .. token, "POST", token, payload)
local decoded = resp and json.decode(resp)

log("INFO", "response: " .. tostring(resp))

if not decoded or decoded.success == false then
    log("ERR", "start call API failed")
end
