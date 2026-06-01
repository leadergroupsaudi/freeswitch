api = freeswitch.API()
digits = session:getDigits(2, "#", 3000);
if digits == "96" then
        local conferenceId = session:getVariable("conference_name")
        freeswitch.consoleLog("INFO","conference Name " ..conferenceId.. "\n")
        local meeting_end = api:executeString("conference " ..conferenceId.. " hup all")
        freeswitch.consoleLog("INFO","Meeting ended " ..meeting_end.. "\n")
end
