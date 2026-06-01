local api = freeswitch.API()

local uuid = tostring(argv[1])
local ext = tostring(argv[2])
ext= "1002"
freeswitch.consoleLog("INFO", "EXT = " .. tostring(ext) .. "\n")
freeswitch.consoleLog("INFO", "UUID = " .. tostring(uuid) .. "\n")


-- 1) CHECK REGISTRATION
local contact_status = api:executeString("sofia_contact " .. ext)

local is_registered = true
if string.match(contact_status, "error/user_not_registered") then
    is_registered = false
end

-- 2) CHECK ACTIVE CALL
local channel_info = api:executeString("show channels like " .. ext)
local in_call = false

if string.find(channel_info, ext) then
    in_call = true
end

-- 3) DETERMINE STATUS
local call_status = ""

if not is_registered then
    call_status = "offline"
elseif in_call then
    call_status = "in_call"
else
    call_status = "available"
end

-- 4) UPDATE UUID VARIABLE
local cmd = "uuid_setvar " .. uuid .. " call_status " .. call_status
freeswitch.consoleLog("NOTICE", "Notification cmd: " .. cmd .. "\n")
local a = api:executeString(cmd)

-- 5) PRINT RESULT (FIXED)
freeswitch.consoleLog("INFO",
    "Extension " .. ext ..
    " | Registered: " .. tostring(is_registered) ..
    " | In Call: " .. tostring(in_call) ..
    " | Status: " .. call_status .. "\n"
)
function table_to_json(tbl)
    local json = "{"
    local first = true
    for k, v in pairs(tbl) do
        if not first then json = json .. "," end
        json = json .. string.format('"%s":"%s"', k, v)
        first = false
    end
    json = json .. "}"
    return json
end

-- Build payload
local payload_table = { call_status = call_status }
local payload = table_to_json(payload_table)
--local payload = { call_status =call_status}

freeswitch.consoleLog("INFO", "JSON Payload: " .. payload .. "\n")

-- Make HTTP POST request using FreeSWITCH curl
local api_url = "https://epmstg.automaxsw.com/api/system/users/" .. ext .. "/status"


-- Use FreeSWITCH API to make the call with Accept header
local curl_cmd1 = string.format(
    "%s content-type application/json header 'Accept: application/json' post '%s'",
    api_url,
    payload
)

freeswitch.consoleLog("INFO", "Final curl cmd: " .. curl_cmd1 .. "\n")

local response1 = api:executeString("curl " .. curl_cmd1)

freeswitch.consoleLog("INFO", "API Response1: " .. tostring(response1) .. "\n")

-- Check response
if response and response  ~= "" then
    freeswitch.consoleLog("INFO", "Call log API request successful\n")
    freeswitch.consoleLog("INFO", "Response body: " .. response .. "\n")
else
    freeswitch.consoleLog("WARNING", "Call log API returned empty response\n")
end

