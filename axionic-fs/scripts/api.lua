local api = freeswitch.API()

-- Build clean JSON payload (escaped properly)
local call_id = "call_hangup_successfully"
if session:ready() then
    session:execute("info", "")
end
freeswitch.consoleLog("INFO", "API Response: " .. tostring(call_id) .. "\n")

