api = freeswitch.API()
json = freeswitch.JSON()

-- 📞 Call info
local from_num = session:getVariable("caller_id_number") or "unknown"
local dialed_number = session:getVariable("destination_number") or "unknown"
freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Incoming call from: " .. from_num .. " to: " .. dialed_number .. "\n")

-- 📡 SIP domain (used for contact)
local sip_domain_name = "pbx.axionic.io"
session:setVariable("sip_domain_name", sip_domain_name)
session:execute("export", "nolocal:sip_domain_name=" .. sip_domain_name)

-- ✅ Answer call
session:answer()
session:execute("sleep", "500")

-- 🔊 Play welcome message
--session:execute("speak", "en-US 'Welcome to LeSaaS support, please wait while we connect you to an agent'")

session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")

-- 🧠 (Optional) Register online agents dynamically
local extensions = {"267","268","276"}
local not_registered = "error/user_not_registered"
for _, ext in ipairs(extensions) do
    local contact_status = api:executeString("sofia_contact " .. ext)
    if not string.match(contact_status, "error/user_not_registered") then
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " online, set Available\n")
        api:executeString("callcenter_config agent set status " .. ext .. " Available")
	api:executeString("callcenter_config agent set contact " .. ext .. " [absolute_codec_string='PCMU,PCMA',leg_timeout=30]" .. contact_status)
        api:executeString("callcenter_config agent set state " .. ext .. " Waiting")
    else
        freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Agent " .. ext .. " offline, logging out\n")
        api:executeString("callcenter_config agent set status " .. ext .. " 'Logged Out'")
    end
end
session:setVariable("destination_number", "LEADER_Lesaas")
freeswitch.consoleLog("NOTICE", "[LeSaaS-IVR] Transferring call to LEADER_Lesaas\n")
-- 📞 Send call into callcenter queue
   session:execute("transfer","LEADER_Lesaas XML public")

-- session:execute("transfer","LEADER_Lesaas XML public")

-- 📤 If no agent answers, fallback message
--session:execute("playback", "/usr/local/freeswitch/sounds/custom-ivrs/LeSaaS_NoAgentAvailable.wav")
--session:hangup()

