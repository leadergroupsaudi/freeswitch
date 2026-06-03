api = freeswitch.API();
uuid=tostring(argv[1]);

local caller = session:getVariable("caller_id_number")

local callee = session:getVariable("cc_agent")
local caller_left_at= "in_call";
local callee_left_at="in_call";
local call_status="ACCEPTED"


local time = os.date( "%Y-%m-%d %H:%M:%S");

local callee_joined_at=tostring(time);
cmd="uuid_setvar      "..tostring(uuid).."      ".."answertime".."             "..tostring(time)
a=api:executeString(cmd)

freeswitch.consoleLog("NOTICE","Notification cmd " .. tostring(cmd) .. " ...\n")
freeswitch.consoleLog("NOTICE","status " .. tostring(call_status) .. " ...\n")
freeswitch.consoleLog("NOTICE","caller " .. tostring(caller) .. " ...\n")
freeswitch.consoleLog("NOTICE","callee " .. tostring(callee) .. " ...\n")
freeswitch.consoleLog("NOTICE","caller_joined_at " .. tostring(caller_joined_at) .. " ...\n")
freeswitch.consoleLog("NOTICE","caller_left_at " .. tostring(caller_left_at) .. " ...\n")
freeswitch.consoleLog("NOTICE","callee_left_at " .. tostring(callee_left_at) .. " ...\n")

