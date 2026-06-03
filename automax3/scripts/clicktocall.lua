local api = freeswitch.API()

-- Input arguments
local uuid      = argv[1]
local callee    = argv[2]
local caller_id = session:getVariable("caller_id_number")

-- Generate B-leg UUID
local bleg_uuid = api:executeString("create_uuid")
bleg_uuid = string.gsub(bleg_uuid, "%s+", "")

freeswitch.consoleLog("INFO", "[CLICK2CALL] ALEG=" .. uuid .. " BLEG=" .. bleg_uuid .. "\n")

-- Store correlation variables (will survive to hangup hook)
session:setVariable("aleg_uuid", uuid)
session:setVariable("bleg_uuid", bleg_uuid)
session:setVariable("calltype", "VoiceCallChatOutbound")
session:setVariable("groupID", "TideM")
session:setVariable("team", "Tide")
session:setVariable("callee", callee)
session:setVariable("caller", caller_id)

-------------------------------------------------
-- ✅ HANGUP HOOK (same file)
-------------------------------------------------
function on_hangup(s, status)
    if not s then
        freeswitch.consoleLog("INFO", "[HANGUP] session is nil, cannot get variables\n")
        return
    end

	local hangup_cause = s:hangupCause()
    local q850         = s:getVariable("hangup_cause_q850")

    local dialstatus   = s:getVariable("DIALSTATUS") -- may be nil
    local disposition  = s:getVariable("originate_disposition") -- may be nil
    local fail         = s:getVariable("originate_failed_cause") -- may be nil
 local uuid        = s:getVariable("uuid")
    local caller      = s:getVariable("caller")
    local callee      = s:getVariable("callee")
    local start_at    = s:getVariable("start_at")
    local end_at      = s:getVariable("end_at")
    local duration    = s:getVariable("duration")
    local recfilename = s:getVariable("recfilename")
    local calllog_id  = s:getVariable("calllog_id")
    local call_status = s:getVariable("status")
session:setVariable("session_in_hangup_hook",'true');
    freeswitch.consoleLog("INFO",
        string.format(
            "[CALL-END] CAUSE=%s Q850=%s DIAL=%s DISP=%s FAIL=%s\n",
            tostring(hangup_cause),
            tostring(q850),
            tostring(dialstatus),
            tostring(disposition),
            tostring(fail)
        )
    )
local vars = s:getVars()
    for k,v in pairs(vars) do
        freeswitch.consoleLog("INFO", k .. "=" .. tostring(v) .. "\n")
    end

    --cmd = "bgapi lua hangup.lua " ..tostring(uuid).." "..tostring(caller).." "..tostring(callee).." "..tostring(start_at).." "..tostring(end_at).." "..tostring(duration).." "..tostring(recfilename).." "..tostring(calllog_id).." "..tostring(dialstatus).." "..tostring(answertime)
--api:executeString(cmd);

end

-- Register hangup hook
session:setHangupHook("on_hangup")

-------------------------------------------------
-- ✅ BUILD BRIDGE STRING (internal SIP)
-------------------------------------------------
local bridge_str =
"{execute_on_answer=lua outbridge.lua " .. uuid ..
",origination_uuid=" .. bleg_uuid ..
",origination_caller_id_number=" .. caller_id ..
",origination_caller_id_name=" .. caller_id ..
",caller=" .. caller_id ..
",callee=" .. callee ..
",absolute_codec_string=PCMU,PCMA}" ..
"user/" .. callee

-------------------------------------------------
-- ✅ EXECUTE BRIDGE
-------------------------------------------------
session:execute("bridge", bridge_str)

