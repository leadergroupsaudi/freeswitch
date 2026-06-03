api = freeswitch.API();
uuid=tostring(argv[1]);

caller =tostring(argv[2]);
callee =tostring(argv[3]);

calltype = "INBOUND";
status = "ANSWER";
buuid = tostring(argv[4]);
s = freeswitch.Session(uuid);

freeswitch.consoleLog("info","UUID  is: "..tostring(uuid));
freeswitch.consoleLog("info","buuid  is: "..tostring(buuid));

freeswitch.consoleLog("info","Caller  is: "..tostring(caller));
freeswitch.consoleLog("info","Callee  is: "..tostring(callee));


local mix_type = "mono"
local sampling_rate = "16000"
local wss_url ="wss://devon-conferences-importantly-coffee.trycloudflare.com" ..
  "?uuid=" .. uuid .. "&role=caller"

local wss_url1 ="wss://devon-conferences-importantly-coffee.trycloudflare.com" ..
  "?uuid=" .. buuid .. "&role=callee"
-- Construct the API command to start the audio stream
local command = "bgapi uuid_audio_stream     " .. uuid ..   " start   " .. wss_url .. "     " .. mix_type .. " " .. sampling_rate
freeswitch.consoleLog("INFO", "Started audio stream with result: " .. command .. "\n")

-- Execute the command
local result = api:executeString(command)

-- Construct the API command to start the audio stream
local command = "bgapi uuid_audio_stream     " .. buuid ..   " start   " .. wss_url1 .. "     " .. mix_type .. " " .. sampling_rate
freeswitch.consoleLog("INFO", "Started audio stream with result: " .. command .. "\n")

-- Execute the command
local result = api:executeString(command)

-- Log the result of the command
freeswitch.consoleLog("INFO", "Started audio stream with result: " .. tostring(result) .. "\n")





