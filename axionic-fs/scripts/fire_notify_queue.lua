-- fire_notify.lua
--local freeswitch = require("freeswitch")
local api = freeswitch.API()
local json = require "lunajson"

local M = {}

function M.send_call_notification(session)
    local from_num = session:getVariable("caller_id_number") or "unknown"
    local dialed_number = session:getVariable("destination_number") or "unknown"
    local sip_domain_name = "pbx.axionic.io"
    local sip_port = "7440"

    local media_type = session:getVariable("isvideocall")
    if media_type == "true" then
        media_type = "V"
    else
        media_type = "A"
    end

    local call_type = "I"  -- inbound
    local payload = string.format(
        '{"domain":"%s","port":"%s","callerId":"%s","receivers":["%s"],"mediaType":"%s","callType":"%s","isScreenShared":false}',
        sip_domain_name, sip_port, from_num, dialed_number, media_type, call_type
    )

    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Sending queue call notification: " .. payload .. "\n")

    local result = api:executeString("curl https://wapis.discretal.com/calls/sip-call-notification content-type application/JSON post " .. payload .. " ssl-verifyhost 0 ssl-verifypeer 0")

    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Notification API response: " .. tostring(result) .. "\n")
    return result
end

return M

