local api = freeswitch.API()
local uuid = tostring(argv[1])
local ext  = tostring(argv[2])

freeswitch.consoleLog("INFO", "EXT = " .. tostring(ext) .. "\n")
freeswitch.consoleLog("INFO", "UUID = " .. tostring(uuid) .. "\n")

local created_by = session:getVariable("caller_id_number")
local time = os.date("%Y-%m-%d %H:%M:%S")

api:executeString("uuid_setvar " .. uuid .. " start_at " .. time)

freeswitch.consoleLog("INFO", "start_at = " .. tostring(time) .. "\n")
freeswitch.consoleLog("INFO", "created_by = " .. tostring(created_by) .. "\n")


--[[
session:setVariable("recording_follow_transfer", "true")

local recfilename = uuid .. ".wav"

session:setVariable("recfilename", recfilename)

local recording_path = "/usr/local/freeswitch/recordings/" .. recfilename

freeswitch.consoleLog("INFO", "Recording file: " .. recording_path .. "\n")

session:execute("record_session", recording_path)
]]
-- ================================================
-- HELPER: Check if extension is in a BRIDGED call
-- ================================================
local function is_ext_busy(extension, current_uuid)
    local calls_info = api:executeString("show calls as json")
  --  freeswitch.consoleLog("INFO", "show calls result: " .. tostring(calls_info) .. "\n")

    if not calls_info or calls_info == "" then
        return false
    end

    for block in calls_info:gmatch('{[^}]+}') do
        if not block:find(current_uuid) then
            local b_uuid = block:match('"b_uuid"%s*:%s*"([^"]+)"')
            local b_dest = block:match('"b_dest"%s*:%s*"([^"]+)"')
            local dest   = block:match('"dest"%s*:%s*"([^"]+)"')
            local b_cid  = block:match('"b_cid_num"%s*:%s*"([^"]+)"')

            freeswitch.consoleLog("INFO",
                "Checking block — b_uuid:" .. tostring(b_uuid) ..
                " dest:" .. tostring(dest) ..
                " b_dest:" .. tostring(b_dest) ..
                " b_cid:" .. tostring(b_cid) .. "\n"
            )

            if b_uuid and b_uuid ~= "" then
                if dest == extension or b_dest == extension or b_cid == extension then
                    freeswitch.consoleLog("INFO",
                        "Extension " .. extension .. " is in an active bridged call.\n"
                    )
                    return true
                end
            end
        end
    end
    return false
end

-- ================================================
-- 1) CHECK IF EXTENSION IS REGISTERED
-- ================================================
local reg_check = api:executeString("sofia_contact " .. ext)
freeswitch.consoleLog("INFO", "sofia_contact result: " .. tostring(reg_check) .. "\n")

local is_registered = reg_check and
                      reg_check ~= "" and
                      not reg_check:find("^error") and
                      not reg_check:find("^-ERR")

if not is_registered then
    freeswitch.consoleLog("INFO",
        "Extension " .. ext .. " is not registered. Playing offline.wav\n"
    )
    if session:ready() then
        session:execute("playback", "/usr/local/freeswitch/sounds/ivr_audiofiles_tts_new/offline.wav"
        )
        session:hangup("USER_NOT_REGISTERED")
    end
    return
end

freeswitch.consoleLog("INFO", "Extension " .. ext .. " is registered.\n")

-- ================================================
-- 2) CHECK IF EXTENSION IS BUSY
-- ================================================
local in_call = is_ext_busy(ext, uuid)

freeswitch.consoleLog("INFO",
    "Extension " .. ext ..
    " | In Call: " .. tostring(in_call) .. "\n"
)

-- ================================================
-- 3) SET UUID VARIABLE
-- ================================================
local call_status = in_call and "in_call" or "available"
api:executeString("uuid_setvar " .. uuid .. " call_status " .. call_status)

-- ================================================
-- 4) IF BUSY — PLAY BUSY AUDIO IN A LOOP FOR 60s
--    Uses session:execute("playback", ...) so audio
--    actually plays on the channel reliably.
-- ================================================
if in_call then
    freeswitch.consoleLog("INFO",
        "Extension " .. ext .. " is busy. Starting 60s busy IVR loop.\n"
    )

    local start_time = os.time()
    local timeout    = 60
    local is_free    = false

    while os.time() - start_time < timeout do

        -- Guard: caller hung up
        if not session:ready() then
            freeswitch.consoleLog("INFO", "Caller hung up during busy IVR.\n")
            return
        end

        -- Recheck if extension is free BEFORE playing
        if not is_ext_busy(ext, uuid) then
            freeswitch.consoleLog("INFO",
                "Extension " .. ext .. " is now free after " ..
                (os.time() - start_time) .. "s.\n"
            )
            api:executeString("uuid_setvar " .. uuid .. " call_status available")
            is_free = true
            break
        end

        -- Still busy: play busy tone via session:execute (blocking, reliable)
        freeswitch.consoleLog("INFO",
            "Extension " .. ext .. " still busy — playing busy_call.wav\n"
        )
        session:execute("playback", "/usr/local/freeswitch/sounds/ivr_audiofiles_tts_new/busy_call.wav"
        )

        -- Small pause between plays so we can recheck promptly
        if session:ready() then
            session:execute("sleep", "500")
        end
    end

    if is_free then
        freeswitch.consoleLog("INFO",
            "Extension " .. ext .. " is now free. Continuing call.\n"
        )
    else
        -- 60s elapsed and still busy
        if session:ready() then
            freeswitch.consoleLog("INFO",
                "60s timeout — extension " .. ext .. " still busy. Hanging up.\n"
            )
            api:executeString("uuid_setvar " .. uuid .. " call_status timeout")
            session:execute("playback", "ivr/ivr-please_try_again_later.wav")
            session:hangup("USER_BUSY")
        end
    end

else
    freeswitch.consoleLog("INFO",
        "Extension " .. ext .. " is available. No busy IVR needed.\n"
    )
end
