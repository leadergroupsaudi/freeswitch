local api = freeswitch.API()

-- CREATE EVENT CONSUMER
local consumer = freeswitch.EventConsumer("CHANNEL_HANGUP_COMPLETE")

freeswitch.consoleLog("NOTICE", "Hangup Event Listener started...\n")

-- ---------------- HELPERS ----------------
local function gv(e, name)
    return e:getHeader(name)
end

local function epoch_to_utc(epoch)
    local n = tonumber(epoch)
    if n then
        return os.date("!%Y-%m-%d %H:%M:%S", n)
    end
    return nil
end

local function to_json_value(val)
    if val == nil or val == "" then return "null" end
    return '"' .. tostring(val) .. '"'
end

local function to_json_number(val)
    if val == nil or val == "" then return "null" end
    local num = tonumber(val)
    if not num then return "null" end
    return tostring(num)
end

local function sh(value)
    if value == nil then return "''" end
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- ---------------- DEDUP TABLE ----------------
local processed_calls = {}

-- ---------------- MAIN LOOP ----------------
while true do

    local e = consumer:pop(1)

    if e then

        freeswitch.consoleLog("NOTICE", "\n===== HANGUP EVENT =====\n")

        -- ----------- BASIC DATA -----------
        local call_id = gv(e, "variable_callLogId")

        if not call_id or call_id == "" or call_id == "unknown" then
            freeswitch.consoleLog("NOTICE", "No valid callLogId found, skipping.\n")
            goto continue
        end

        -- ----------- DEDUP CHECK -----------
        if processed_calls[call_id] then
            freeswitch.consoleLog("NOTICE", "Already processed callLogId: " .. call_id .. "\n")
            goto continue
        end
        processed_calls[call_id] = true

        -- ----------- COLLECT VARIABLES -----------
        local caller = gv(e, "variable_orig_caller")
                    or gv(e, "variable_sip_h_X-Orig-Caller")
                    or gv(e, "variable_nolocal:sip_h_X-Orig-Caller")
       
	local callee_number = gv(e, "variable_destination")
                   or gv(e, "variable_sip_h_X-destination")
                   or gv(e, "variable_nolocal:sip_h_X-destination")
        local recfilename = gv(e, "variable_recfilename")
                         or gv(e, "variable_sip_h_X-recfilename")
                         or gv(e, "variable_nolocal:sip_h_X-recfilename")

        local callee_numbers = gv(e, "variable_cc_agent")
                           or gv(e, "Caller-Destination-Number")

          if (caller == nil or caller == "") and (callee_number == nil or callee_number == "") then
          goto continue
        end

        -- Skip if callee starts with 0
        if callee_number and callee_number:match("^0") then
            freeswitch.consoleLog("NOTICE", "Callee starts with 0, skipping.\n")
            callee_number = nil
        end

        local hangup_cause     = gv(e, "Hangup-Cause") or "UNKNOWN"
        local billsec          = tonumber(gv(e, "variable_billsec")) or 0
        local caller_joined_at = gv(e, "variable_start_stamp")
        local caller_left_at   = gv(e, "variable_end_stamp")
        local callee_joined_at = epoch_to_utc(gv(e, "variable_cc_queue_joined_epoch"))
        local callee_left_at   = epoch_to_utc(gv(e, "variable_cc_queue_terminated_epoch"))

        -- ----------- STATUS LOGIC -----------
        local status = "MISSED"

        if hangup_cause == "USER_BUSY" then
            status = "CLIENT_REJECT"

        elseif hangup_cause == "NORMAL_CLEARING" and callee_joined_at ~= nil and callee_numbers ~= nil then
            status = "ENDED"

        elseif hangup_cause == "NO_ANSWER"
            or hangup_cause == "ORIGINATOR_CANCEL"
            or hangup_cause == "CALL_REJECTED"
            or hangup_cause == "CONGESTION"
            or hangup_cause == "BUSY" then
            status  = "MISSED"
            billsec = 0
        end

        if callee_joined_at then
            callee_left_at = tostring(caller_left_at)
        end
-- freeswitch.consoleLog("INFO", e:serialize() .. "\n")
        -- ----------- RECORDING LOGIC -----------
        -- Only attach recording if call was ENDED (answered)
        if status ~= "ENDED" then
            recfilename = nil
        end

        -- Prepend full recordings path
        local recordings_dir = "/usr/local/freeswitch-prod-instance/recordings/"
        if recfilename ~= nil then
            recfilename = recordings_dir .. recfilename
        end

        -- Verify file exists
        if recfilename ~= nil then
            local f = io.open(recfilename, "r")
            if f then
                f:close()
                freeswitch.consoleLog("INFO", "Recording found: " .. recfilename .. "\n")
            else
                freeswitch.consoleLog("ERR", "Recording NOT found: " .. recfilename .. "\n")
                recfilename = nil
            end
        end

        -- ----------- LOG DATA -----------
        freeswitch.consoleLog("NOTICE", "callLogId      : " .. call_id .. "\n")
        freeswitch.consoleLog("NOTICE", "caller         : " .. tostring(caller) .. "\n")

        freeswitch.consoleLog("NOTICE", "callee_number  : " .. tostring(callee_number) .. "\n")
        freeswitch.consoleLog("NOTICE", "callee_numbers_agent  : " .. tostring(callee_numbers) .. "\n")
        freeswitch.consoleLog("NOTICE", "hangup_cause   : " .. hangup_cause .. "\n")
        freeswitch.consoleLog("NOTICE", "status         : " .. status .. "\n")
        freeswitch.consoleLog("NOTICE", "duration       : " .. billsec .. "\n")
        freeswitch.consoleLog("NOTICE", "recfilename    : " .. tostring(recfilename) .. "\n")

        -- ----------- BUILD CURL (multipart) -----------
        local tmp_out = "/tmp/prehangup_" .. call_id .. ".json"

        local fields =
            "-F " .. sh("call_id="  .. call_id)          .. " " ..
            "-F " .. sh("caller="   .. tostring(caller or "")) .. " " ..
            "-F " .. sh("status="   .. status)            .. " " ..
            "-F " .. sh("duration=" .. tostring(billsec))

        if callee_number ~= nil then
            fields = fields .. " -F " .. sh("callee_number=" .. callee_number)
        end
        if caller_joined_at ~= nil then
            fields = fields .. " -F " .. sh("caller_joined_at=" .. caller_joined_at)
        end
        if caller_left_at ~= nil then
            fields = fields .. " -F " .. sh("caller_left_at=" .. caller_left_at)
        end
        if callee_joined_at ~= nil then
            fields = fields .. " -F " .. sh("callee_joined_at=" .. callee_joined_at)
        end
        if callee_left_at ~= nil then
            fields = fields .. " -F " .. sh("callee_left_at=" .. callee_left_at)
        end
        if recfilename ~= nil then
            fields = fields .. " -F " .. sh("file=@" .. recfilename)
        end

        local cmd =
            "curl -k -s -X PUT 'https://wapis.discretal.com/calls/update-external-sip-call-details' " ..
            fields ..
            " > " .. tmp_out .. " 2>&1"

        freeswitch.consoleLog("INFO", "Curl cmd: " .. cmd .. "\n")
        os.execute(cmd)

        -- Read response
        local f = io.open(tmp_out, "r")
        if f then
            local response = f:read("*all")
            f:close()
            os.remove(tmp_out)
            freeswitch.consoleLog("INFO", "API Response: " .. tostring(response) .. "\n")
        else
            freeswitch.consoleLog("ERR", "Could not read curl response\n")
        end

        freeswitch.consoleLog("NOTICE", "==============================\n")

        ::continue::
    end
end
