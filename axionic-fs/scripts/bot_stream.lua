local api = freeswitch.API()

local uuid = tostring(argv[1])

local wss_url = "wss://livechat.discretal.com/api/v1/freeswitch/audio-stream"
local mix_type = "mono"
local sampling_rate = "8000"
--Execute the stream command
 local command = "uuid_audio_stream " .. uuid .. " start " .. wss_url .. " " .. mix_type .. " " .. sampling_rate
 freeswitch.consoleLog("INFO", "Executing command: " .. command .. "\n")
 local result = api:executeString(command)


local duration = 0
while session:ready() and duration < 300 do
  session:sleep(1000)   -- 1000 not 100
  duration = duration + 1
  if duration % 30 == 0 then
    freeswitch.consoleLog("INFO", "Streaming active for " .. duration .. " seconds\n")
  end
end
session:hangup("NORMAL_CLEARING")

