local uuid = session:getVariable("uuid")
local moh = session:getVariable("hold_music")
api = freeswitch.API()
if session:ready() then
        --local callLogId = callLog.create()
        session:setVariable("sip_h_X-CallLogId","1133")
        session:answer()
        session:execute("sleep","500")
        freeswitch.consoleLog("notice","Session Answered")
	session:sleep(3000);
	--reply = api:executeString("uuid_broadcast ".. uuid .. " "..moh.." aleg");
	reply2 = api:executeString("uuid_break ".. uuid .. " all");
	freeswitch.consoleLog("INFO","Reply ::: "..reply2)
end

