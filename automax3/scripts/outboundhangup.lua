local api = freeswitch.API()
local json = freeswitch.JSON()
local json = require "lunajson"
local http = require("socket.http")
local ltn12 = require("ltn12")

--local uuid = argv[1]

--if not uuid or uuid == "" then
--    freeswitch.consoleLog("ERR", "Usage: lua hup_both.lua <uuid>\n")
--    return
--end



--local call_id =tostring(session:getVariable("callLogId"));
local call_uuid =tostring(session:getVariable("UUID"));
local agent_name = session:getVariable("variable_cc_agent")
local caller = session:getVariable("caller_id_number")
local duration = tonumber(session:getVariable("billsec"))
local hangup_cause = session:getVariable("hangup_cause")
local recfilename = session:getVariable("recfilename");

local caller = session:getVariable("caller_id_number")
local caller2 =session:getVariable("ani")

local callee = session:getVariable("destination_number")
local agent_uuid = session:getVariable("cc_agent_uuid")
local callee_joined_at = session:getVariable("answertime")
local call_status = session:getVariable("call_status")

freeswitch.consoleLog("INFO", "call_status at: " .. tostring(call_status) .. "\n")
freeswitch.consoleLog("INFO", "recfilename: " .. tostring(recfilename) .. "\n")

local joined_at = session:getVariable("cc_queue_joined_epoch")
local terminated_at = session:getVariable("cc_queue_terminated_epoch")
-- Get the Callee/Destination Number (using common variable names)

local caller_joined_at = tostring(session:getVariable("start_stamp"))

start_at =tostring(caller_joined_at or ""):gsub(" ", "T") .. "Z"
local participants = tostring(callee) .. "," .. tostring(caller)
created_by= caller;

freeswitch.consoleLog("INFO", "Participants = " .. participants .. "\n")

local caller_left_at = tostring(session:getVariable("end_stamp"))
local callee_left_at = tostring(session:getVariable("end_stamp"))
end_at =tostring(caller_left_at or ""):gsub(" ", "T") .. "Z"
local callee_number  = tostring(session:getVariable("destination_number"))
local callee_num2 =session:getVariable("destination_number")
invited_users ='null'
--Joined_User=callee_number
freeswitch.consoleLog("INFO", "billsec at: " .. tostring(duration) .. "\n")
freeswitch.consoleLog("INFO", "caller_joined_at at: " .. tostring(caller_joined_at) .. "\n")
freeswitch.consoleLog("INFO", "Caller left at at: " .. tostring(caller_left_at) .. "\n")

local function to_utc_string(epoch)
    epoch = tonumber(epoch)
    if not epoch or epoch <= 0 then return "NONE" end
    if epoch > 9999999999 then epoch = math.floor(epoch / 1000) end
    return os.date("!%Y-%m-%dT%H:%M:%SZ", epoch)
end
if callee_joined_at == nil or callee_joined_at == "" then
    callee_joined_at = 'null'
     callee_left_at = 'null'
     status ="MISSED"
     invited_users = callee_number;
     else
	     joined_users=callee_number
end
if hangup_cause == "NO_ANSWER" or hangup_cause == "ORIGINATOR_CANCEL"
      or hangup_cause == "cancelled"
    or hangup_cause == "CONGESTION" or hangup_cause == "BUSY" then
    status = "MISSED"
    billsec = 0
elseif  hangup_cause == "USER_BUSY" then
        status ="in_call"
elseif hangup_cause == "NORMAL_CLEARING" then
        status = "ended" 
--    else
--        status = "CLIENT_REJECT"
--  end

   -- callee_joined_at = caller_joined_at
   -- callee_left_at = caller_left_at
else
    status = "FAILED"
end
 if callee_joined_at == nil or callee_joined_at == "" or callee_joined_at =='null' then
      if call_status == "in_call" then 
	      status= "in_call"
      else
	   status= "missed"
	--	status = "cancelled"
       end
end

--]]
-- Status logic
local function safe(value, default)
  if value == nil or value == '' then
    return default
  end
  return value
end
local call_id         = safe(call_id, "unknown")
local caller          = safe(caller, "unknown")
--local callee_number   = safe(callee_number, "unknown")
local caller_left_at   = safe(caller_left_at, "")
local callee_left_at   = safe(callee_left_at, "")
local invited_users   = safe(invited_users, "")
local joined_users    =safe(joined_users, "")
--local status          = safe(status, "UNKNOWN")
local duration        = tonumber(safe(duration, 0))  -- ensure it's a number


--local status, callee_left_at = "UNKNOWN", "", ""
freeswitch.consoleLog("INFO", "jond_User = " .. tostring(joined_users) .. "\n")
freeswitch.consoleLog("INFO", "Invited_User = " .. tostring(invited_users) .. "\n")
freeswitch.consoleLog("INFO", "call_uuid = " .. tostring(call_uuid) .. "\n")
freeswitch.consoleLog("INFO", "start_at = " .. tostring(start_at) .. "\n")
freeswitch.consoleLog("INFO", "end_at = " .. tostring(end_at) .. "\n")
freeswitch.consoleLog("INFO", "status = " .. tostring(status) .. "\n")
freeswitch.consoleLog("INFO", "created_by = " .. tostring(created_by) .. "\n")
local part1, part2 = participants:match("([^,]+),([^,]+)")
part1 = tostring(part1 or "")
part2 = tostring(part2 or "")
freeswitch.consoleLog("INFO", "part1 = " .. tostring(part1) .. "\n")
freeswitch.consoleLog("INFO", "part2 = " .. tostring(part2) .. "\n")
-- Ensure variables are properly set
call_uuid     = tostring(call_uuid or "")
created_by    = tostring(created_by or "")
call_status   = tostring(call_status or "FAILED")
start_at      = tostring(start_at or "")
end_at        = tostring(end_at or "")
part1         = tostring(part1 or "")
part2         = tostring(part2 or "")


local function parse_csv_to_array(str)
    if not str or str == "" or str == "null" then
        return {}
    end
    local arr = {}
    for item in string.gmatch(str, "[^,]+") do
        local trimmed = item:match("^%s*(.-)%s*$")
        table.insert(arr, tonumber(trimmed) or trimmed)
    end
    return arr
end

-- Parse participants
local participants = parse_csv_to_array(participants)

-- Ensure joined_users and invited_users are always arrays (even if empty)
local joined_users = parse_csv_to_array(joined_users)
if not joined_users then joined_users = {} end

local invited_users = parse_csv_to_array(invited_users)
if not invited_users then invited_users = {} end

-- Mark these as arrays explicitly
joined_users._is_array = true
invited_users._is_array = true

-- Build participants structure
local participants = {}
if part1 then
    table.insert(participants, {
        extension = part1,
        joinedAt = caller_joined_at or start_at,
        leftAt = caller_left_at or end_at
    })
end
if part2 then
    table.insert(participants, {
        extension = part2
    })
end

-- Manual JSON encoding (to avoid library issues)
local function encode_json(data)
    local function escape_string(str)
        if not str then return "null" end
        str = tostring(str)
        str = string.gsub(str, '\\', '\\\\')
        str = string.gsub(str, '"', '\\"')
        str = string.gsub(str, '\n', '\\n')
        str = string.gsub(str, '\r', '\\r')
        str = string.gsub(str, '\t', '\\t')
        return '"' .. str .. '"'
    end
    
    local function encode_array(arr)
        local parts = {}
        for _, v in ipairs(arr) do
            if type(v) == "table" then
                table.insert(parts, encode_object(v))
            elseif type(v) == "number" then
                table.insert(parts, tostring(v))
            else
                table.insert(parts, escape_string(v))
            end
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    
    local function is_array(tbl)
        if type(tbl) ~= "table" then return false end
        -- Check if explicitly marked as array
        if tbl._is_array then return true end
        -- Empty table should be array
        if next(tbl) == nil then return true end
        -- Check if all keys are sequential numbers
        local count = 0
        for _ in pairs(tbl) do count = count + 1 end
        return count == #tbl
    end
    
    function encode_object(obj)
        local parts = {}
        for k, v in pairs(obj) do
            -- Skip internal marker fields
            if k ~= "_is_array" then
                local key = escape_string(k)
                local value
                if type(v) == "table" then
                    if is_array(v) then
                        value = encode_array(v)
                    else
                        value = encode_object(v)
                    end
                elseif type(v) == "number" then
                    value = tostring(v)
                elseif type(v) == "boolean" then
                    value = tostring(v)
                elseif v == nil then
                    value = "null"
                else
                    value = escape_string(v)
                end
                table.insert(parts, key .. ":" .. value)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    
    return encode_object(data)
end
-------------------authentication -------------------------
session:execute("bgsystem","chmod -R 777 /usr/local/freeswitch/recordings/"..tostring(recfilename));
-- STEP 1: GET BEARER TOKEN
 local function get_token()
        local curl_command = [[curl -s -k -X POST \
          -d "scope=profile+api&grant_type=client_credentials" \
          -H "Content-Type: application/x-www-form-urlencoded" \
          -H "Authorization: Basic NDQxMTE5NzQ5MTM4NDE1NjE3OmxKVER1dENxUHljSUVJVUxYZ29JamF2S3NvZ1dtNEZDSmNXeHhiNExFbXJxcWtrblN1eVM5MDU4UGtTREpyWjc=" \
          https://automax.discretal.com/auth/oauth2/token]]
        
        local handle = io.popen(curl_command)
        local result = handle:read("*a")
        handle:close()
        
        return result
    end
    
    -- Get the token
   -- local token = get_token()
    local token_json, err = get_token()
    local data = json.decode(token_json)
local access_token = data["access_token"]

freeswitch.consoleLog("INFO", "Access Token: " .. access_token .. "\n")
    -- Log to console
    
    -- Set channel variable with the response
   -- session:setVariable("oauth_response", token)
------------------------------------------------------
-- STEP 2: UPLOAD FILE
------------------------------------------------------
local file_path = "/usr/local/freeswitch/recordings/" .. recfilename

-- Single request that captures both body and HTTP code
local upload_cmd = string.format([[
curl -s -w '\n%%{http_code}' -X POST "%s" \
    -H "Authorization: Bearer %s" \
    -H "Content-Type: multipart/form-data" \
    -F "fieldName=Attachments" \
    -F "upload=@%s" \
    --compressed \
    --insecure 2>&1
]], 
"https://automax.discretal.com/api/compose/namespace/425787942130548737/module/425787942127468545/record/attachment",
access_token,
file_path
)

freeswitch.consoleLog("INFO", "Executing upload command...\n")
freeswitch.consoleLog("DEBUG", "Command: " .. upload_cmd .. "\n")

-- Check if file exists first
local test_file = io.open(file_path, "r")
if not test_file then
    freeswitch.consoleLog("ERR", "File not found: " .. file_path .. "\n")
    return
else
    test_file:close()
    freeswitch.consoleLog("INFO", "File exists: " .. file_path .. "\n")
end

-- Execute curl command
local handle = io.popen(upload_cmd)
if not handle then
    freeswitch.consoleLog("ERR", "Failed to execute curl command\n")
    return
end

local full_response = handle:read("*a")
local success, exit_type, exit_code = handle:close()

freeswitch.consoleLog("INFO", "Curl exit code: " .. tostring(exit_code) .. "\n")
freeswitch.consoleLog("DEBUG", "Full response length: " .. string.len(full_response or "") .. "\n")

if not full_response or full_response == "" then
    freeswitch.consoleLog("ERR", "Empty response from curl\n")
    return
end

-- Split response: last line is HTTP code, rest is body
local lines = {}
for line in full_response:gmatch("[^\r\n]+") do
    table.insert(lines, line)
end

local http_code = lines[#lines] or "000"
table.remove(lines, #lines) -- Remove HTTP code from body
local body = table.concat(lines, "\n")

freeswitch.consoleLog("NOTICE", "UPLOAD RAW BODY: " .. tostring(body) .. "\n")
freeswitch.consoleLog("NOTICE", "UPLOAD HTTP CODE: " .. tostring(http_code) .. "\n")

-- Check for curl errors
if http_code == "000" then
    freeswitch.consoleLog("ERR", "Upload failed - curl couldn't connect. Check:\n")
    freeswitch.consoleLog("ERR", "  1. Network connectivity\n")
    freeswitch.consoleLog("ERR", "  2. File exists: " .. file_path .. "\n")
    freeswitch.consoleLog("ERR", "  3. Token validity\n")
    freeswitch.consoleLog("ERR", "  4. URL accessibility\n")
    freeswitch.consoleLog("ERR", "Full response: " .. full_response .. "\n")
    return
end

-- Check HTTP status
local http_code_num = tonumber(http_code)
if not http_code_num or http_code_num < 200 or http_code_num >= 300 then
    freeswitch.consoleLog("ERR", "Upload failed with HTTP CODE " .. http_code .. "\n")
    freeswitch.consoleLog("ERR", "Response body: " .. body .. "\n")
    return
end

-- Decode JSON body
local decoded = json.decode(body)
if not decoded then
    freeswitch.consoleLog("ERR", "Failed to decode JSON response\n")
    freeswitch.consoleLog("ERR", "Body was: " .. body .. "\n")
    return
end

local attachmentID = decoded and decoded.response and decoded.response.attachmentID
if attachmentID then
    freeswitch.consoleLog("NOTICE", "Attachment ID: " .. tostring(attachmentID) .. "\n")
else
    freeswitch.consoleLog("WARNING", "No attachmentID in response\n")
    freeswitch.consoleLog("INFO", "Full decoded response: " .. json.encode(decoded) .. "\n")
end
---------------  call log ----------------------------------
-- Build the payload
local payload = {
    attachmentID = attachmentID,
    recording_url=attachmentID,
    call_uuid = call_uuid,
    created_by = created_by,
    status = status,
    start_at = start_at,
    end_at = end_at,
    participants = participants,
    joined_users = joined_users,
    invited_users = invited_users
}
-- Convert to JSON
local json_payload = encode_json(payload)

freeswitch.consoleLog("INFO", "JSON Payload: " .. json_payload .. "\n")

-- Make HTTP POST request using FreeSWITCH curl
local api_url = "https://epmstg.automaxsw.com/api/system/call-logs/"

-- Use FreeSWITCH API to make the call with Accept header
--local api = freeswitch.API()
local curl_cmd = string.format(
    "%s content-type application/json header 'Accept: application/json' post '%s'",
    api_url,
    json_payload
)

freeswitch.consoleLog("INFO", "Final curl cmd: " .. curl_cmd .. "\n")

local response = api:executeString("curl " .. curl_cmd)

freeswitch.consoleLog("INFO", "API Response: " .. tostring(response) .. "\n")

-- Check response
if response ~= "" then
    freeswitch.consoleLog("INFO", "Call log API request successful\n")
    freeswitch.consoleLog("INFO", "Response body: " .. response .. "\n")
else
    freeswitch.consoleLog("WARNING", "Call log API returned empty response\n")
end
