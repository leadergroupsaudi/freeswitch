api = freeswitch.API();
local uuid = session:getVariable("UUID");
-- Get UTC time
 wav_path="/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/timecondition.wav";
local utc_time = os.date("!*t")

-- Convert to Saudi local time (UTC+3)
utc_time.hour = utc_time.hour + 3
if utc_time.hour >= 24 then
    utc_time.hour = utc_time.hour - 24
    utc_time.day = utc_time.day + 1
end

-- Build currenttime in HHMMSS format
local currenttime = tonumber(string.format("%02d%02d%02d", utc_time.hour, utc_time.min, utc_time.sec))

-- Get weekday name in English
local weekday = os.date("!%A", os.time(utc_time))  -- still UTC day, but we’ll adjust
if utc_time.hour < 3 then
    -- small correction for day boundary crossing
    local prev = os.time(utc_time) - (3 * 3600)
    weekday = os.date("!%A", prev)
end

freeswitch.consoleLog("INFO", "Saudi Time: " .. string.format("%02d:%02d:%02d", utc_time.hour, utc_time.min, utc_time.sec) .. " (" .. weekday .. ")\n")
session:answer()
-- Now use your existing condition
if weekday=='Sunday' then  
	session:execute("playback","/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/timecondition.wav");
	session:execute("hangup");
elseif weekday=='Saturday'  then
	session:execute("playback","/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/timecondition.wav");
	session:execute("hangup");
elseif weekday ~= 'Sunday' and weekday ~= 'Saturday' and currenttime >= 180000 and currenttime <= 235959 then
 --  session:execute("playback","/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/timecondition.wav");
--  session:execute("hangup");
--local cmd = "uuid_broadcast " .. uuid .. " " .. wav_path .. " both"
--freeswitch.consoleLog("info", "Executing broadcast: " .. cmd .. "\n")
--local result = api:executeString(cmd)
--freeswitch.consoleLog("info", "Broadcast result: " .. tostring(result) .. "\n")
--os.execute("sleep " .. tostring(130));
session:execute("transfer","timecondition");
--session:execute("hangup");
elseif weekday ~= 'Sunday' and weekday ~= 'Saturday' and currenttime >= 0 and currenttime <= 85959 then
--    session:execute("playback","/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/timecondition.wav");
  session:execute("transfer","timecondition");
    --session:execute("hangup");
end

