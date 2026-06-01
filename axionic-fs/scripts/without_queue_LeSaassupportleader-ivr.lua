local api = freeswitch.API()
--session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")

-- Agent list
local extensions = {"267", "257"}
local sip_domain_name = "pbx.axionic.io"
session:answer()
session:execute("sleep", "500")

-- 🔊 Play welcome message
--session:execute("speak", "en-US 'Welcome to LeSaaS support, please wait while we connect you to an agent'")

session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")

-- Find an available agent
local available_agent = nil
for _, ext in ipairs(extensions) do
    local contact_status = api:executeString("sofia_contact " .. ext)
    if not string.match(contact_status, "error/user_not_registered") then
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " online\n")
        api:executeString("callcenter_config agent set status " .. ext .. " Available")
        available_agent = ext
        break  -- pick first available
    else
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " offline, logging out\n")
        api:executeString("callcenter_config agent set status " .. ext .. " 'Logged Out'")
    end
end

-- Build the dial string
local dial_string = nil
if available_agent then
    -- Use dialplan context for direct call
    dial_string = available_agent .. " XML public"
    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Transferring to available agent " .. available_agent .. " using dialplan\n")
else
    -- No agent available, fallback to queue
    dial_string = "LEADER_Lesaas XML public"
    freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] No agent available, sending call to queue LEADER_Lesaas\n")
end

-- Optional: set call timeout
session:setVariable("call_timeout", "30")

-- Transfer the call
session:execute("transfer", dial_string)

