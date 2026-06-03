-- =========================================
-- user_status.lua
-- =========================================

local api = freeswitch.API()

-- -------------------------
-- INPUT ARGUMENTS
-- -------------------------
local uuid = tostring(argv[1])
local ext  = tostring(argv[2])
-- -------------------------
-- LOG INPUT
-- -------------------------
freeswitch.consoleLog("INFO", "UUID = " .. uuid .. "\n")
freeswitch.consoleLog("INFO", "EXT  = " .. ext  .. "\n")


local function is_extension_in_call(ext)
    local info = api:executeString("show channels like " .. ext)
    if info and info:find(ext) then
        return true
    end
    return false
end
-- -------------------------
-- MAIN LOGIC
-- -------------------------
local call_status = ""

-- 🔁 LOOP WHILE EXTENSION IS BUSY
--[[
while session:ready() and is_extension_in_call(ext) do
    call_status = "in_call"

    freeswitch.consoleLog(
        "INFO",
        "Extension " .. ext .. " is in_call, playing busy IVR\n"
    )

    session:execute(
        "playback",
        "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/busy_call.wav"
    )

    -- wait before next check (IMPORTANT)
    session:sleep(2000)  -- 2 seconds
end
]]

local function is_extension_in_call(ext)
    local calls = api:executeString("show calls as csv")
    if not calls or calls == "" then return false end
    for line in calls:gmatch("[^\n]+") do
        if line:match(ext .. "@pbx%.axionic%.io") then
            return true
        end
    end
    return false
end

-- Check if busy
if is_extension_in_call(ext) then
    freeswitch.consoleLog("NOTICE", ext .. " is busy — playing busy tone\n")
    session:answer()
    session:sleep(500)

    -- Wait max 30 seconds for extension to become free
    local max_wait  = 25  -- seconds
    local waited    = 0
    local poll_sec  = 5   -- check every 5 seconds

    while session:ready() and is_extension_in_call(ext) and waited < max_wait do
        freeswitch.consoleLog("NOTICE", ext .. " still busy, waited " .. waited .. "s\n")
        session:streamFile("/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/busy_call.wav")
        session:sleep(poll_sec * 1000)
        waited = waited + poll_sec
    end

    if not session:ready() then
        -- Caller hung up while waiting
        freeswitch.consoleLog("NOTICE", "Caller hung up while waiting\n")
        return

    elseif waited >= max_wait then
        -- Timeout — disconnect
        freeswitch.consoleLog("NOTICE", "Max wait " .. max_wait .. "s reached — hanging up\n")
        session:streamFile("/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/busy_call.wav")
        --api:executeString("uuid_kill " .. uuid)
	session:hangup("USER_BUSY")
        return

    else
        -- Extension is now free — continue dialplan
        freeswitch.consoleLog("NOTICE", ext .. " is now FREE — proceeding\n")
    end
end


local activeuser = api:executeString("sofia_contact " .. ext)
local is_registered = true

if not activeuser or activeuser:find("error") then
    is_registered = false
end


if is_registered then
    call_status = "available"
    freeswitch.consoleLog("INFO", "Extension " .. ext .. " is AVAILABLE\n")
else
    call_status = "offline"
    freeswitch.consoleLog("INFO", "Extension " .. ext .. " is OFFLINE\n")

    session:execute(
        "playback",
        "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/offline.wav")
	session:sleep(3000)
--	session:hangup()
end

api:executeString("uuid_setvar " .. uuid .. " call_status " .. call_status)

freeswitch.consoleLog(
    "INFO",
    "Extension " .. ext ..
    " | Status = " .. call_status .. "\n"
)
local calltype="internal"
     session:setVariable("sip_h_X-calltype", calltype)
                    session:execute("export", "nolocal:sip_h_X-calltype=" .. calltype)
                    session:setVariable("calltype", calltype)
                   session:setVariable("export_vars", "calltype,sip_h_X-calltype")
                   session:setVariable("cc_export_vars", "calltype,sip_h_X-calltype")

                    session:execute("export", "nolocal:calltype=" .. calltype)

