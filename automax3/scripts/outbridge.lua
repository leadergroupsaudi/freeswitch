api = freeswitch.API();
uuid=tostring(argv[1]);



local time = os.date( "%Y-%m-%d %H:%M:%S");
cmd="uuid_setvar      "..tostring(uuid).."      ".."answertime".."             "..tostring(time)
freeswitch.consoleLog("NOTICE","Notification cmd " .. tostring(cmd) .. " ...\n")
a=api:executeString(cmd)

