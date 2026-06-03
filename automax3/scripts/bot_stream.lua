local api = freeswitch.API()

local uuid = tostring(argv[1])
local session_id=tostring(argv[1])
local api = freeswitch.API()


--local wss_url = "wss://livechat.discretal.com" 
--local wss_url = "wss://gpu.zuqocrm.com:8777/audio?uuid1="..uuid

--local wss_url = "wss://devon-conferences-importantly-coffee.trycloudflare.com" 
local wss_url = "wss://56657a7fabeb.ngrok-free.app/api/v1/freeswitch/pcm16-stream/test123"
local mix_type = "mono"
local sampling_rate = "16000"


local session = freeswitch.Session(uuid)
if not session then
  freeswitch.consoleLog("ERROR", "Failed to get session for UUID: " .. uuid .. "\n")
  return
end

if not session:answered() then
  session:answer()
  freeswitch.consoleLog("INFO", "Call answered for UUID: " .. uuid .. "\n")
end

-- Build and execute the audio stream command
local command = "uuid_audio_stream " .. uuid .. " start " .. wss_url .. " " .. mix_type .. " " .. sampling_rate
freeswitch.consoleLog("INFO", "Executing command: " .. command .. "\n")
local result = api:executeString(command)

-- Check the result
if result == "-ERR no reply" or result == nil then
  freeswitch.consoleLog("ERROR", "Failed to start audio stream: " .. tostring(result) .. "\n")
  session:hangup("NORMAL_CLEARING")
  return
else
  freeswitch.consoleLog("INFO", "Audio stream started successfully: " .. tostring(result) .. "\n")
end

-- Keep the session alive for streaming and playback
local duration = 0
while session:ready() and duration < 300 do -- 5 minutes max
  session:sleep(1000)
  duration = duration + 1
  if duration % 30 == 0 then
    freeswitch.consoleLog("INFO", "Call still active, streaming for " .. duration .. " seconds\n")
  end
end

-- Log call termination
session:hangup("NORMAL_CLEARING")

