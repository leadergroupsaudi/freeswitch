local api = freeswitch.API()
local json = freeswitch.JSON()
local json = require "lunajson"
local http = require("socket.http")
local ltn12 = require("ltn12")

local uuid        = argv[1]
local caller      = argv[2]
local callee      = argv[3]
local caller_joined_at    = argv[4]
local caller_left_at      = argv[5]
local duration    = argv[6]
local recfilename = argv[7]
local calllog_id  = argv[8]
local status      = argv[9]
local answertime  = argv[10]

--if not uuid ov uuid == "" then
--    freeswitch.consoleLog("ERR", "Usage: lua hup_both.lua <uuid>\n")
--    return
--end


freeswitch.consoleLog("INFO", "Hangup.lua file start \n")
freeswitch.consoleLog("INFO", "recfilename: " .. tostring(recfilename) .. "\n")


start_at =tostring(caller_joined_at or ""):gsub(" ", "T") .. "Z"
local participants = tostring(callee) .. "," .. tostring(caller)
created_by= caller;

freeswitch.consoleLog("INFO", "Participants = " .. participants .. "\n")

end_at =tostring(caller_left_at or ""):gsub(" ", "T") .. "Z"

freeswitch.consoleLog("INFO", "UUID        : " .. tostring(uuid) .. "\n")
freeswitch.consoleLog("INFO", "Caller      : " .. tostring(caller) .. "\n")
freeswitch.consoleLog("INFO", "Callee      : " .. tostring(callee) .. "\n")
freeswitch.consoleLog("INFO", "Start At    : " .. tostring(start_at) .. "\n")
freeswitch.consoleLog("INFO", "End At      : " .. tostring(end_at) .. "\n")
freeswitch.consoleLog("INFO", "Duration    : " .. tostring(duration) .. "\n")
freeswitch.consoleLog("INFO", "Record File : " .. tostring(recfilename) .. "\n")
freeswitch.consoleLog("INFO", "CallLog ID  : " .. tostring(calllog_id) .. "\n")
freeswitch.consoleLog("INFO", "Status      : " .. tostring(status) .. "\n")
freeswitch.consoleLog("INFO", "Answer Time : " .. tostring(answertime) .. "\n")

-- ================== Helpers ==================

local function safe(v)
    if v == nil or v == "" then return nil end
    return v
end

local function to_iso(ts)
    if not ts or ts == "" then return nil end
    return tostring(ts):gsub(" ", "T") .. "Z"
end

local function encode_json(data)
    local function esc(s)
        s = tostring(s)
        s = s:gsub("\\", "\\\\"):gsub('"', '\\"')
        return '"' .. s .. '"'
    end

    local function arr(t)
        local o = {}
        for _,v in ipairs(t) do
            table.insert(o, type(v)=="number" and v or esc(v))
        end
        return "[" .. table.concat(o, ",") .. "]"
    end

    local function obj(t)
        local o = {}
        for k,v in pairs(t) do
            if v ~= nil then
                local val
                if type(v)=="table" then
                    val = arr(v)
                elseif type(v)=="number" then
                    val = v
                else
                    val = esc(v)
                end
                table.insert(o, esc(k) .. ":" .. val)
            end
        end
        return "{" .. table.concat(o, ",") .. "}"
    end

    return obj(data)
end



-- ================== Participants ==================

local participants = {}
if tonumber(callee) then table.insert(participants, tonumber(callee)) end
if tonumber(caller) then table.insert(participants, tonumber(caller)) end

-- ================== Joined / Invited ==================

local joined_users  = {}
local invited_users = {}

local answered = session:getVariable("answertime")

if answered and answered ~= "" then
    table.insert(joined_users, tonumber(callee))
else
    table.insert(invited_users, tonumber(callee))
end


if hangup_cause == "NO_ANSWER" or hangup_cause == "ORIGINATOR_CANCEL"
      or hangup_cause == "cancelled"
    or hangup_cause == "CONGESTION" or hangup_cause == "BUSY" then
    status = "cancelled"
elseif  hangup_cause == "USER_BUSY" then
        status ="cancel"
elseif hangup_cause == "NORMAL_CLEARING" then
        status = "ended"
end
 if callee_joined_at == nil or callee_joined_at == "" or callee_joined_at =='null' then
      if call_status == "in_call" then
              status= "in_call"
      else
    status= "missed"
--                status = "cancelled"
       end
end

if hangup_cause == "USER_NOT_REGISTERED" then
        status = "offline"
return
elseif hangup_cause == "ORIGINATOR_CANCEL" then
	status = "cancelled"
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
access_token = data["access_token"]
session:setVariable("access_token",access_token)

freeswitch.consoleLog("INFO", "Access Token: " .. access_token .. "\n")
    -- Log to console
    
    -- Set channel variable with the response
   -- session:setVariable("oauth_response", token)
------------------------------------------------------
-- STEP 2: UPLOAD FILE
------------------------------------------------------

 file_path = "/usr/local/freeswitch/recordings/" .. recfilename
freeswitch.consoleLog("INFO", "File Path = " .. tostring(filepath) .. "\n")
local function file_exists(path)
    local f = io.open(path, "r")
    if f then 
        f:close() 
        return true 
    end
    return false
end

if file_exists(file_path) and status == "ended" then
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

--freeswitch.consoleLog("NOTICE", "UPLOAD RAW BODY: " .. tostring(body) .. "\n")
--freeswitch.consoleLog("NOTICE", "UPLOAD HTTP CODE: " .. tostring(http_code) .. "\n")

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

-- attachmentID = decoded and decoded.response and decoded.response.attachmentID

attachmentResponse = decoded and decoded.response 
attachmentID = decoded.response.attachmentID
namespaceID = decoded.response.namespaceID
-- freeswitch.consoleLog("INFO", "namespaceID".. namespaceID)

if attachmentID then
    freeswitch.consoleLog("NOTICE", "Attachment ID: " .. tostring(attachmentID) .. "\n")    
    freeswitch.consoleLog("NOTICE", "Attachment ID: " .. tostring(namespaceID) .. "\n")

       freeswitch.consoleLog("INFO", "Full decoded response: " .. json.encode(decoded) .. "\n")

else
    freeswitch.consoleLog("WARNING", "No attachmentID in response\n")
    freeswitch.consoleLog("INFO", "Full decoded response: " .. json.encode(decoded) .. "\n")
end
end
---------------  call log ----------------------------------
-- Build the payload
local payload = {
--    attachmentID = attachmentID,
--    recording_url=attachmentID,
--    namespaceID = namespaceID,
    call_uuid = call_uuid,
 --   created_by = created_by,
    status = status,
    start_at = start_at,
    end_at = end_at,
--    participants = participants,
    joined_users = joined_users,
    invited_users = invited_users
}
-- freeswitch.consoleLog("INFO", "namespaceID".. namespaceID)

-- Convert to JSON
local json_payload = encode_json(payload)

freeswitch.consoleLog("INFO", "JSON Payload: " .. json_payload .. "\n")

-- Make HTTP PUT request using FreeSWITCH curl
--local api_url = "https://epmstg.automaxsw.com/api/system/call-logs/" ..callog_id

--local api_url = "https://ax3.automaxsw.com/api/v1/calls/" ..call_uuid.."/end?token"
local api_url = "https://epmstg.automaxsw.com/api/v1/calls/" ..call_uuid.."/end?token"

-- Use FreeSWITCH API to make the call with Accept header
--local api = freeswitch.API()
--local access_token = session:getVariable("access_token")
local curl_cmd = string.format(
    "%s%s content-type application/json -H 'Authorization: Bearer %s' -H 'Accept: application/json' post '%s'",
    api_url,
    access_token,
    access_token,
    json_payload
)

freeswitch.consoleLog("INFO", "Final curl cmd: " .. curl_cmd .. "\n")

local response = api:executeString("curl " .. curl_cmd)


-- Check response
if response and response ~= "" then
    freeswitch.consoleLog("INFO", "Call log API request successful\n")
    freeswitch.consoleLog("INFO", "Response body: " .. response .. "\n")
local decoded = json.decode(response)
-- if not decoded then this
if not decoded then
    freeswitch.consoleLog("ERR", "Failed to decode JSON response\n")
    freeswitch.consoleLog("ERR", "Body was: " .. response .. "\n")
    return
end

--local callLogID = decoded and decoded.response and decoded.response.id  and  decoded.response.data.id
 
-- if not decoded then this

    freeswitch.consoleLog("INFO", "call log id response :".. tostring(response))
    freeswitch.consoleLog("INFO", "call log id response :".. tostring(curl_cmd))
end
if recfilename then 
file_path = "/usr/local/freeswitch/recordings/" .. recfilename
freeswitch.consoleLog("INFO", "recording deleted from server  :".. tostring(file_path))
os.execute("rm -f " .. file_path)

end
