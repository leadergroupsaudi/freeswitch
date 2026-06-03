-- play_result.lua

freeswitch.consoleLog("INFO", "=== Checking Callcenter Result ===\n")

-- Create API object
local api = freeswitch.API()

-- Current channel UUID
local uuid = session:get_uuid() or ""

-- Get agent safely
local cc_agent = session:getVariable("cc_agent") or ""
local callee_num = cc_agent or ""

-- Get queue answered epoch safely
local epoch_str =
    session:getVariable("cc_queue_answered_epoch") or
    session:getVariable("variable_cc_queue_answered_epoch") or
    ""

-- Convert epoch to readable time
local cc_queue_answered_time = ""

if epoch_str ~= "" then
    local epoch = tonumber(epoch_str)

    -- Uncomment if your epoch is milliseconds
    -- if epoch and epoch > 9999999999 then
    --     epoch = math.floor(epoch / 1000)
    -- end

    if epoch then
        -- Local server timezone
        cc_queue_answered_time =
            os.date("%Y-%m-%d %H:%M:%S", epoch) or ""

        -- UTC example:
        -- os.date("!%Y-%m-%d %H:%M:%S", epoch)
    end
end

local callee_joined = cc_queue_answered_time or ""

-- Logs safely
freeswitch.consoleLog("INFO", "UUID                    : " .. tostring(uuid) .. "\n")
freeswitch.consoleLog("INFO", "cc_agent                : " .. tostring(cc_agent) .. "\n")
freeswitch.consoleLog("INFO", "cc_queue_answered_epoch : " .. tostring(epoch_str) .. "\n")
freeswitch.consoleLog("INFO", "cc_queue_answered_time  : " .. tostring(cc_queue_answered_time) .. "\n")
freeswitch.consoleLog("INFO", "callee_joined           : " .. tostring(callee_joined) .. "\n")

-- Set answertime_ivr variable
local answer_time_ivr = cc_queue_answered_time or ""

if answer_time_ivr ~= "" then

    local cmd1 =
        "uuid_setvar " .. tostring(uuid) ..
        " answertime_ivr '" .. tostring(answer_time_ivr) .. "'"

    freeswitch.consoleLog("INFO", "Executing: " .. tostring(cmd1) .. "\n")

    api:executeString(cmd1)
end

-- Set callee_num variable
local cmd2 =
    "uuid_setvar " .. tostring(uuid) ..
    " callee_num '" .. tostring(callee_num) .. "'"

freeswitch.consoleLog("INFO", "Executing: " .. tostring(cmd2) .. "\n")

api:executeString(cmd2)
session:execute("lua", "ivr_outbridge.lua " .. uuid .. " " .. callee_num)
-- Verify variables safely
local verify_var = session:getVariable("answertime_ivr") or ""
local verify_callee_num = session:getVariable("callee_num") or ""

freeswitch.consoleLog(
    "INFO",
    "answertime_ivr         : " .. tostring(verify_var) .. "\n"
)

freeswitch.consoleLog(
    "INFO",
    "callee_num             : " .. tostring(verify_callee_num) .. "\n"
)

-- If no agent answered
if cc_agent == "" then

    freeswitch.consoleLog("INFO", "=== No Agent Answered ===\n")

    -- Play IVR
  session:execute("playback", "/usr/local/freeswitch/sounds/at/ar_noagent_found.wav")
    -- Optional hangup
    -- session:hangup()

else

    freeswitch.consoleLog(
        "INFO",
        "=== Agent Answered : " .. tostring(cc_agent) .. " ===\n"
    )

end
