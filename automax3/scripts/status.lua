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
api:executeString("uuid_setvar " .. uuid .. " created_by " .. created_by)
-- ================================================
-- HELPER: Check if extension is in a BRIDGED call
-- ================================================

local call_status = in_call and "in_call" or "available"
api:executeString("uuid_setvar " .. uuid .. " call_status " .. call_status)

-- ================================================
-- 4) IF BUSY — PLAY BUSY AUDIO IN A LOOP FOR 60s
--    Uses session:execute("playback", ...) so audio
--    actually plays on the channel reliably.
-- ================================================
