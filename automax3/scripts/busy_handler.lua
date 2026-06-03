-- busy_handler.lua
-- Args: argv[1]=uuid, argv[2]=destination_number

local uuid        = argv[1]
local destination = argv[2]

-- ============================================================
-- STEP 1: Check if bridge returned USER_BUSY
-- ============================================================
local bridge_cause = session:getVariable("bridge_hangup_cause") or ""
local hangup_cause = session:getVariable("hangup_cause")        or ""

freeswitch.consoleLog("NOTICE", string.format(
    "[busy_handler] uuid=%s bridge_cause=%s hangup_cause=%s\n",
    uuid, bridge_cause, hangup_cause
))

if bridge_cause ~= "USER_BUSY" and hangup_cause ~= "USER_BUSY" then
    freeswitch.consoleLog("NOTICE", string.format(
        "[busy_handler] uuid=%s Not USER_BUSY — skipping\n", uuid
    ))
    return
end

-- ============================================================
-- STEP 2: Save ALL variables to file NOW while session is alive
-- outboundhangup.lua will read this file since uuid_getvar fails
-- ============================================================
local caller_id      = session:getVariable("caller_id_number")   or ""
local caller_name    = session:getVariable("caller_id_name")     or ""
local callee         = session:getVariable("destination_number") or destination
local start_stamp    = session:getVariable("start_stamp")        or ""
local answertime     = session:getVariable("answertime")         or ""
local recfilename    = session:getVariable("recfilename")        or ""
local callLogID      = session:getVariable("callLogID")          or ""
local domain         = session:getVariable("domain_name")        or ""
local call_direction = session:getVariable("call_direction")     or "inbound"

-- Write to temp file — outboundhangup.lua reads this
local varfile = "/tmp/fs_busy_" .. uuid .. ".vars"
local f = io.open(varfile, "w")
if f then
    f:write("caller_id_number=" .. caller_id      .. "\n")
    f:write("caller_id_name="   .. caller_name    .. "\n")
    f:write("destination_number=" .. callee        .. "\n")
    f:write("start_stamp="      .. start_stamp    .. "\n")
    f:write("answertime="       .. answertime      .. "\n")
    f:write("recfilename="      .. recfilename     .. "\n")
    f:write("callLogID="        .. callLogID       .. "\n")
    f:write("domain_name="      .. domain          .. "\n")
    f:write("call_direction="   .. call_direction  .. "\n")
    f:write("x_busy_flag=true\n")
    f:write("hangup_cause=USER_BUSY\n")
    f:write("bridge_hangup_cause=USER_BUSY\n")
    f:close()
    freeswitch.consoleLog("NOTICE", string.format(
        "[busy_handler] uuid=%s vars saved to %s\n", uuid, varfile
    ))
else
    freeswitch.consoleLog("ERR", string.format(
        "[busy_handler] uuid=%s FAILED to write vars file\n", uuid
    ))
end

-- ============================================================
-- STEP 3: Set cause variables on session
-- ============================================================
session:setVariable("x_busy_flag",              "true")
session:setVariable("hangup_cause",             "USER_BUSY")
session:setVariable("bridge_hangup_cause",      "USER_BUSY")
session:setVariable("last_bridge_hangup_cause", "USER_BUSY")
session:setVariable("proto_specific_hangup_cause", "sip:486")

-- ============================================================
-- STEP 4: Answer caller so we can play busy tone
-- ============================================================
if not session:ready() then
    freeswitch.consoleLog("NOTICE", "[busy_handler] caller already gone\n")
    return
end

session:answer()
session:execute("sched_hangup", "+60 USER_BUSY")

freeswitch.consoleLog("NOTICE", string.format(
    "[busy_handler] uuid=%s caller=%s → %s BUSY — 60s tone started\n",
    uuid, caller_id, callee
))

-- ============================================================
-- STEP 5: Loop — busy tone + retry bridge every 5s
-- ============================================================
local max_wait    = 60
local check_every = 5
local waited      = 0
local bridged     = false

while waited < max_wait do

    if not session:ready() then
        freeswitch.consoleLog("NOTICE", string.format(
            "[busy_handler] uuid=%s caller hung up at %ds — USER_BUSY\n",
            uuid, waited
        ))
        break
    end

    -- Play 5 seconds of busy tone
    session:execute("playback", "tone_stream://%(500,500,480,620);loops=5")
    waited = waited + check_every

    if not session:ready() then
        freeswitch.consoleLog("NOTICE", string.format(
            "[busy_handler] uuid=%s caller disconnected after tone at %ds\n",
            uuid, waited
        ))
        break
    end

    freeswitch.consoleLog("NOTICE", string.format(
        "[busy_handler] uuid=%s waited=%ds — retrying bridge to %s\n",
        uuid, waited, destination
    ))

    -- Retry bridge
    session:setVariable("continue_on_fail", "USER_BUSY")
    session:execute("bridge",
        "{sip_h_X-EPM940-UUID=" .. uuid ..
        ",execute_on_answer='lua outbridge.lua " .. uuid .. " " .. destination ..
        "'}user/" .. destination .. "@15.207.94.247"
    )

    local retry_cause = session:getVariable("bridge_hangup_cause") or ""

    freeswitch.consoleLog("NOTICE", string.format(
        "[busy_handler] uuid=%s retry result=%s\n", uuid, retry_cause
    ))

    if retry_cause == "USER_BUSY" then
        -- Still busy — update file with latest cause
        session:setVariable("hangup_cause",             "USER_BUSY")
        session:setVariable("bridge_hangup_cause",      "USER_BUSY")
        session:setVariable("last_bridge_hangup_cause", "USER_BUSY")
        freeswitch.consoleLog("NOTICE", string.format(
            "[busy_handler] uuid=%s still USER_BUSY\n", uuid
        ))

    elseif retry_cause == "NORMAL_CLEARING" or retry_cause == "" then
        -- Bridge succeeded
        freeswitch.consoleLog("NOTICE", string.format(
            "[busy_handler] uuid=%s bridge succeeded\n", uuid
        ))
        session:execute("sched_cancel", "all")
        -- Update file: call completed normally
        local f2 = io.open(varfile, "a")
        if f2 then
            f2:write("x_busy_flag=false\n")
            f2:write("hangup_cause=NORMAL_CLEARING\n")
            f2:write("bridge_hangup_cause=NORMAL_CLEARING\n")
            f2:write("end_stamp=" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
            f2:close()
        end
        session:setVariable("x_busy_flag",              "false")
        session:setVariable("hangup_cause",             "NORMAL_CLEARING")
        session:setVariable("bridge_hangup_cause",      "NORMAL_CLEARING")
        session:setVariable("last_bridge_hangup_cause", "NORMAL_CLEARING")
        bridged = true
        break

    else
        -- Other cause
        freeswitch.consoleLog("NOTICE", string.format(
            "[busy_handler] uuid=%s bridge cause=%s stopping\n",
            uuid, retry_cause
        ))
        session:execute("sched_cancel", "all")
        local f3 = io.open(varfile, "a")
        if f3 then
            f3:write("x_busy_flag=false\n")
            f3:write("hangup_cause=" .. retry_cause .. "\n")
            f3:write("bridge_hangup_cause=" .. retry_cause .. "\n")
            f3:close()
        end
        session:setVariable("x_busy_flag",         "false")
        session:setVariable("hangup_cause",         retry_cause)
        session:setVariable("bridge_hangup_cause",  retry_cause)
        break
    end
end

-- ============================================================
-- STEP 6: Final hangup
-- ============================================================
if not bridged then
    -- Write end_stamp to file before hangup
    local f4 = io.open(varfile, "a")
    if f4 then
        f4:write("end_stamp=" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        f4:close()
    end

    freeswitch.consoleLog("NOTICE", string.format(
        "[busy_handler] uuid=%s final USER_BUSY hangup after %ds\n",
        uuid, waited
    ))
    session:setVariable("x_busy_flag",              "true")
    session:setVariable("hangup_cause",             "USER_BUSY")
    session:setVariable("bridge_hangup_cause",      "USER_BUSY")
    session:setVariable("last_bridge_hangup_cause", "USER_BUSY")
    session:execute("hangup", "USER_BUSY")
end
