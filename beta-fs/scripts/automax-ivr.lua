local audiopath = "/usr/local/freeswitch-dev-instance/share/freeswitch/sounds/ivr_audiofiles/"
local sound = audiopath .. "welcome.wav";
local invalidaudiofile = audiopath .. "invalid_input.wav";
freeswitch.consoleLog("notice","Entered into Lua AutoMax IVR script\n")
session:answer()
freeswitch.consoleLog("notice","IVR call is answered\n")
dtmf_digits = session:playAndGetDigits (1, 1 ,2 ,5000,'#',sound, invalidaudiofile,"[1-3]")
freeswitch.consoleLog("notice", "DTMF Received is: " ..dtmf_digits)
if(dtmf_digits == "1" or dtmf_digits == "2" or dtmf_digits == "3" ) then
        session:execute("transfer", "200 XML public")
end
