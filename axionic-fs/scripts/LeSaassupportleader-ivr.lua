-- Initialize FreeSWITCH API and JSON
local api = freeswitch.API()
local json = freeswitch.JSON()

-- ?? Call info
local from_num = session:getVariable("caller_id_number") or "unknown"
local dialed_number = session:getVariable("destination_number") or "unknown"
freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Incoming call from: " .. from_num .. " to: " .. dialed_number .. "\n")

-- ?? SIP domain (used for contact)
local sip_domain_name = "pbx.axionic.io"
session:setVariable("sip_domain_name", sip_domain_name)
session:execute("export", "nolocal:sip_domain_name=" .. sip_domain_name)

-- Answer the call and play welcome message
session:answer()


session:execute("sleep", "500")
session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")

-- List of agent extensions in this queue
local extensions = {"267","268","276"}
local ext_not_reg = "error/user_not_registered"

-- Loop through each agent to check availability and register
for _, ext in ipairs(extensions) do
    local contact_status = api:executeString("sofia_contact " .. ext)
    
    if not string.match(contact_status, ext_not_reg) then
        -- Get agent DND/Busy status
        local dnd_status = api:executeString("global_getvar agent_" .. ext .. "_status") or "Available"
        local agent_state = api:executeString("callcenter_config agent get state " .. ext) or "Waiting"
        
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Extension " .. ext .. " status: " .. dnd_status .. ", state: " .. agent_state .. "\n")
	freeswitch.consoleLog("NOTICE", "Test1!\n")        
        -- Only mark agent as Available if not Busy and not already in a queue call
        if dnd_status ~= "Busy" and agent_state ~= "In a queue call" then
            api:executeString("callcenter_config agent set status " .. ext .. " Available")
            -- Remove old contacts, then set the current contact
            api:executeString("callcenter_config agent set contact " .. ext .. " " .. contact_status)
            api:executeString("callcenter_config agent set state " .. ext .. " Waiting")
            freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " is now Available and Waiting\n")
	    freeswitch.consoleLog("NOTICE", "Test22!\n")
        else
            freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Skipping agent " .. ext .. " (Busy or already in a call)\n")
	    freeswitch.consoleLog("NOTICE", "Test33!\n")
        end
    else
        -- If agent is offline, log out
        api:executeString("callcenter_config agent set status " .. ext .. " 'Logged Out'")
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " not registered. Logging out.\n")
    end
end

-- Small delay to ensure agent statuses are updated
session:execute("sleep", "500")

-- Prevent the call from auto-hanging up if needed
session:setAutoHangup(false)

-- Transfer the call into the callcenter queue
session:execute("transfer", "LEADER_Lesaas XML public")
freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Call transferred to LEADER_Lesaas queue\n")

