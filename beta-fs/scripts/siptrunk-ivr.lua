api = freeswitch.API();
session:answer();

--dtmf = session:playAndGetDigits(1, 4, 3, 5000, "#","welcome-siptrunk.wav",
--"/usr/local/freeswitch-staging-instance/share/freeswitch/sounds/en/us/callie/ivr/8000/ivr-demo-invalid.wav","[0123456789]");

for i = 0,2,1 
do 
	digits = session:read(1, 4, "/usr/local/freeswitch-staging-instance/share/freeswitch/sounds/en/us/callie/ivr/8000/welcome-siptrunk.wav", 5000,""); 
	freeswitch.consoleLog("NOTICE", "digits "..digits.."\n");
	if string.len(digits) == 1 and tonumber(digits) == 0 then 
		digits ="1011";
		dial_string = digits .." XML public";
		session:execute("transfer",dial_string);
	
	elseif string.len(digits) == 4  then 
		cmd = "user_exists id "..digits.." fsstg.axionic.io"
		found = api:executeString(cmd)
		freeswitch.consoleLog("notice","Extension Output result"..found)
		if found == 'true' then
			freeswitch.consoleLog("notice","Extesnion found")
			dial_string = digits .." XML public";
			session:execute("transfer",dial_string);
		end
	end
	
	session:execute("playback", "/usr/local/freeswitch-staging-instance/share/freeswitch/sounds/en/us/callie/ivr/8000/ivr-demo-invalid.wav");
end

