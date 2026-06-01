api = freeswitch.API();

local uuid = session:getVariable("UUID");

time=os.time()
session:setVariable("api_hangup_hook","lua hangup.lua "..tostring(uuid));
