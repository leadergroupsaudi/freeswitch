local call_uuid = session:getVariable("uuid")
local json = require("lunajson")
recording_dir = '/usr/local/freeswitch-dev-instance/recordings/IVR-CC/'
session:execute("set","tts_engine=azure_tts")
session:execute("set","tts_voice=ar-SA-ZariyahNeural")
session:execute("sleep","1000")
session:execute("speak","{AZURE_SUBSCRIPTION_KEY=1cfc10bab7f54e53bb5fad1b6d6dfee4,AZURE_REGION=uksouth,speed=0}أهلاً. يرجى التحدث بعد صوت الصفارة")
session:execute("playback","tone_stream://L=1;%(1850,1750,1000)")
session:execute("set","playback_terminators=#")
session:execute("export","nolocal:playback_terminators=#")
local recording_filename = recording_dir..call_uuid..".wav"
--local callRecord = session:recordFile(recording_filename, 30, 200 , 5);
local callRecord = session:execute("record", recording_filename.." 30 200 4");
--session:execute("playback",recording_filename)

function execute_command(command)
     local handle = io.popen(command)
     local result = handle:read("*a")
     handle:close()
     return result
end
local token = "1cfc10bab7f54e53bb5fad1b6d6dfee4"
azure_transcription_api = "curl --location --request POST 'https://uksouth.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=ar-SA' --header 'Ocp-Apim-Subscription-Key: "..token.."' --header 'Content-Type: audio/wav' --data-binary @"..recording_filename..""

freeswitch.consoleLog("INFO","CURL Command :"..azure_transcription_api)
local apiResponse = execute_command(azure_transcription_api)
--local apiResponse = json.decode(apiResponse)
freeswitch.consoleLog("INFO"," Response::  "..apiResponse)
