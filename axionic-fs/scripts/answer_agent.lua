local callLog = {}
local api = freeswitch.API()
local json = freeswitch.JSON()

-- Fetch basic channel info
local uuid = session:getVariable("uuid") or ""
local call_direction = (session:getVariable("Call-Direction") or ""):lower()
local caller_number = session:getVariable("Caller-Caller-ID-Number")
    or session:getVariable("caller_id_number")
    or session:getVariable("effective_caller_id_number")
    or session:getVariable("sip_from_user")
    or ""
--local caller_number =session:getVariable("Caller-Caller-ID-Number") or session:getVariable("Caller-Orig-Caller-ID-Number") or  ""
local callee = session:getVariable("Caller-Destination-Number") or session:getVariable("sip_req_user") or session:getVariable("sip_to_user") or ""
local domain = session:getVariable("domain_name") or ""

-- Safely get created_time (handle missing or bad values)
local created_time_str = session:getVariable("created_time")
local created_time_num = tonumber(created_time_str)

if not created_time_num or created_time_num <= 0 then
    created_time_num = os.time() * 1000000  -- fallback to current epoch in microseconds
end

-- Convert to seconds safely (ensure integer)
local created_time_sec = math.floor(created_time_num / 1000000)
local start_time = os.date("!%Y-%m-%dT%H:%M:%SZ", created_time_sec)

freeswitch.consoleLog("INFO", "[createCallLog] UUID: " .. uuid .. "\n")
freeswitch.consoleLog("INFO", string.format("[createCallLog] Direction: %s | Caller: %s | Callee: %s\n", call_direction, caller_number, callee))
freeswitch.consoleLog("INFO", "Type of caller_number: " .. type(caller_number) .. "\n")

function callLog.create()
    -- Only handle inbound calls
    if call_direction ~= "inbound" then
        freeswitch.consoleLog("INFO", "[createCallLog] Skipping non-inbound call\n")
--        return nil
    end

    -- Validate caller/callee
    if (#caller_number >= 6 and #caller_number <= 12) or (#callee >= 6 and #callee <= 12) then
        -- Determine who is phone vs extension
  	     local phone, extension, call_using
		 freeswitch.consoleLog("INFO", "[createCallLog] in first condition\n")
        if #callee >= 6 and #callee <= 12 then
		  freeswitch.consoleLog("INFO", "[createCallLog] in second condition\n")
            phone = callee
          extension = caller_number
            call_using = "sip"
        else
		 freeswitch.consoleLog("INFO", "[createCallLog] in elsesecond condition\n")
            phone = caller_number
            extension = callee
            call_using = "phone"
        end

	--        freeswitch.consoleLog("INFO", string.format("[createCallLog] Phone: %s | Extension: %s | Call Using: %s\n", phone, extension, call_using))

        -- Prepare JSON payload
        local payload = string.format('{"caller_number":"%s"}', caller_number)
        local api_url = "https://wapis.discretal.com/calls/phone-sip-call"

        -- Execute API POST
        local curl_cmd = string.format("%s content-type application/json post %s", api_url, payload)
        session:execute("curl", curl_cmd)

        local response_code = session:getVariable("curl_response_code") or "0"
        local response_data = session:getVariable("curl_response_data") or ""

        freeswitch.consoleLog("INFO", "[createCallLog] API Response Code: " .. response_code .. "\n")
        freeswitch.consoleLog("INFO", "[createCallLog] API Response Data: " .. response_data .. "\n")

        -- Process successful response
        if tonumber(response_code) >= 200 and tonumber(response_code) < 300 then
            local ok, json_data = pcall(json.decode, json, response_data)
            if ok and json_data and json_data.response and json_data.response.sipCallDetails then
                local callLogId = json_data.response.sipCallDetails.call_id
                if callLogId then
                    freeswitch.consoleLog("INFO", "[createCallLog] Received CallLogId: " .. tostring(callLogId) .. "\n")

                    -- Set CallLogId variables for downstream logic
                    session:setVariable("sip_h_X-CallLogId", callLogId)
                    session:execute("export", "nolocal:sip_h_X-CallLogId=" .. callLogId)
                    session:setVariable("Call_Log_Id", callLogId)
                    session:execute("export", "nolocal:Call_Log_Id=" .. callLogId)

                    return callLogId
                end
            else
                freeswitch.consoleLog("WARNING", "[createCallLog] Failed to parse JSON response\n")
            end
        else
            freeswitch.consoleLog("WARNING", "[createCallLog] API returned non-2xx code: " .. response_code .. "\n")
        end
    else
        freeswitch.consoleLog("WARNING", string.format("[createCallLog] Skipping API call – invalid caller/callee length: %s / %s\n", caller, callee))
    end

    return nil
end
callLog.create()
return callLog

