api = freeswitch.API()
json = freeswitch.JSON()
local extensions = {"267", "257","276","268"}
local sip_domain_name = "pbx.axionic.io"
local queue_name = "lesaas-ivr"
local queue_context = "default"

session:answer()
session:execute("sleep", "500")

-- === Step 1: Play welcome message ===
session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")
local module_folder = freeswitch.getGlobalVariable("script_dir") .. "/"
package.path = module_folder .. "?.lua;" .. package.path

local fire_notify_queue = require("fire_notify_queue")

-- === Step 2: Send notification API ===
local notify = require "fire_notify_queue"
notify.send_call_notification(session)

-- === Step 3: Update agent statuses ===
local any_agent_online = false
for _, ext in ipairs(extensions) do
    local contact_status = api:executeString("sofia_contact " .. ext)
    if not string.match(contact_status, "error/user_not_registered") then
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " online, marking Available\n")
        api:executeString("callcenter_config agent set status " .. ext .. " Available")
        api:executeString("callcenter_config agent set state " .. ext .. " Waiting")
        api:executeString("callcenter_config agent set contact " .. ext ..
            " [absolute_codec_string='PCMU,PCMA',leg_timeout=30]" .. contact_status)
        any_agent_online = true
    else
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " offline, marking Logged Out\n")
        api:executeString("callcenter_config agent set status " .. ext .. " 'Logged Out'")
    end
end

-- === Step 4: Check if any agent is online ===
if any_agent_online then
    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Sending call to queue " .. queue_name .. "@" .. queue_context .. "\n")
    session:setVariable("call_timeout", "30")
    session:execute("callcenter", queue_name .. "@" .. queue_context)
else
    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] No agents online, playing busy prompt\n")
    -- Play a "all agents are busy" prompt
    session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/AgentBusy.wav")
    session:hangup("NORMAL_CLEARING")
end

