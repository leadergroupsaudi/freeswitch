local api = freeswitch.API()
local json = freeswitch.JSON()
local json = require "lunajson"
local http = require("socket.http")
local ltn12 = require("ltn12")


local call_uuid = argv[1]
local UUID = argv[1]

--if not uuid or uuid == "" then
--    freeswitch.consoleLog("ERR", "Usage: lua hup_both.lua <uuid>\n")
--    return
--end

local call_uuid =tostring(session:getVariable("UUID"));
local agent_name = session:getVariable("variable_cc_agent") or ""
local caller = session:getVariable("caller_id_number") or ""
local duration = tonumber(session:getVariable("billsec"))
local hangup_cause = session:getVariable("hangup_cause")
local recfilename = session:getVariable("recfilename");

caller = session:getVariable("caller_id_number")
local caller2 =session:getVariable("ani")

 callee = session:getVariable("destination_number")
local agent_uuid = session:getVariable("cc_agent_uuid")

 callee_joined_at = session:getVariable("answertime")
local callog_id = session:getVariable("callLogID")

local call_status = session:getVariable("call_status")


--freeswitch.consoleLog("INFO", ":callLogID " .. tostring(id) .. "\n")

freeswitch.consoleLog("INFO", "call_status at: " .. tostring(call_status) .. "\n")
freeswitch.consoleLog("INFO", "hangup_cause at: " .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "recfilename: " .. tostring(recfilename) .. "\n")

local joined_at = session:getVariable("cc_queue_joined_epoch")
local terminated_at = session:getVariable("cc_queue_terminated_epoch")
-- Get the Callee/Destination Number (using common variable names)

local caller_joined_at = tostring(session:getVariable("start_at"))

start_at =tostring(caller_joined_at or ""):gsub(" ", "T") .. "Z"
local participants = tostring(callee) .. "," .. tostring(caller)
created_by= caller;

freeswitch.consoleLog("INFO", "Participants = " .. participants .. "\n")

local caller_left_at = tostring(session:getVariable("end_stamp"))
local callee_left_at = tostring(session:getVariable("end_stamp"))
end_at =tostring(caller_left_at or ""):gsub(" ", "T") .. "Z"
local callee_number  = tostring(session:getVariable("destination_number"))
local callee_num2 =session:getVariable("destination_number")
freeswitch.consoleLog("INFO", "billsec at: " .. tostring(duration) .. "\n")
freeswitch.consoleLog("INFO", "caller_joined_at at: " .. tostring(caller_joined_at) .. "\n")

freeswitch.consoleLog("INFO", "end at at: " .. tostring(end_at) .. "\n")
freeswitch.consoleLog("INFO", "start at : " .. tostring(start_at) .. "\n")

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

-- ================== Status Logic (CLEAN) ==================
-- ================== Get All Cause Variables ==================

local hangup_cause         = session:getVariable("hangup_cause")
local bridge_hangup_cause  = session:getVariable("bridge_hangup_cause")
local sip_hangup_cause     = session:getVariable("last_bridge_proto_specific_hangup_cause")
local originate_disp       = session:getVariable("originate_disposition")

freeswitch.consoleLog("INFO", "hangup_cause: "        .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "bridge_hangup_cause: " .. tostring(bridge_hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "sip_hangup_cause: "    .. tostring(sip_hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "originate_disp: "      .. tostring(originate_disp) .. "\n")

-- ================== Status Logic ==================
-- ================== Get All Cause Variables ==================

local hangup_cause        = session:getVariable("hangup_cause")
local bridge_hangup_cause = session:getVariable("bridge_hangup_cause")
local sip_hangup_cause    = session:getVariable("last_bridge_proto_specific_hangup_cause")
local originate_disp      = session:getVariable("originate_disposition")

freeswitch.consoleLog("INFO", "hangup_cause: "        .. tostring(hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "bridge_hangup_cause: " .. tostring(bridge_hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "sip_hangup_cause: "    .. tostring(sip_hangup_cause) .. "\n")
freeswitch.consoleLog("INFO", "originate_disp: "      .. tostring(originate_disp) .. "\n")

-- ================== Status Logic ==================

status = "missed"  -- default

if hangup_cause == "USER_NOT_REGISTERED" or
   hangup_cause == "SUBSCRIBER_ABSENT" then
    -- ✅ User offline
    status = "offline"

elseif hangup_cause == "USER_BUSY" or
       sip_hangup_cause == "sip:486" then
    if bridge_hangup_cause ~= nil and bridge_hangup_cause ~= "nil" then
        status = "busy"
    elseif hangup_cause == "USER_BUSY" then 
	    status = "busy"
    else	    
        status = "declined"
    end

elseif hangup_cause == "CALL_REJECTED" or
       sip_hangup_cause == "sip:603" or
       sip_hangup_cause == "603" then
    -- ✅ Hard decline (603)
    status = "declined"

elseif sip_hangup_cause == "sip:480" and
       originate_disp == "NO_USER_RESPONSE" then
    -- ✅ YOUR PHONE'S DECLINE — sends 480 + NO_USER_RESPONSE
    status = "declined"

elseif originate_disp == "ORIGINATOR_CANCEL" or
       hangup_cause == "ORIGINATOR_CANCEL" then
    -- ✅ Caller hung up before answer
    status = "cancelled"

elseif hangup_cause == "NO_ANSWER" or originate_disp == "NO_ANSWER" then
    -- ✅ Rang but nobody answered (timeout)
    status = "missed"

elseif hangup_cause == "NORMAL_CLEARING" then
    if callee_joined_at and callee_joined_at ~= ""
       and callee_joined_at ~= "null" then
        -- ✅ Call was answered and completed normally
        status = "completed"
    else
        -- ✅ Cleared before answer
        status = "cancelled"
    end
end
if bridge_hangup_cause == "NORMAL_CLEARING" then
cmd="uuid_broadcast   "..tostring(uuid).."   /usr/local/freeswitch/sounds/at/thank_you.wav ".."    both"
freeswitch.consoleLog("NOTICE","Notification cmd " .. tostring(cmd) .. " ...\n")
a=api:executeString(cmd)
end
freeswitch.consoleLog("INFO", "Final status: " .. tostring(status) .. "\n")

