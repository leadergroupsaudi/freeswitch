freeswitch.consoleLog("INFO","conference maintainance event was caught in conference_end.lua\n")
api = freeswitch.API()
--event_data = event:serialize();                                                                                                                                                                                    
--freeswitch.consoleLog("NOTICE", "\n [Axionic] Conference:maintenance event = " .. event_data); 

local Action = event:getHeader("Action");
local Result = event:getHeader("Result");
local Conference_size = event:getHeader("Conference-Size");
if Action == "bgdial-result" and Result == "DESTINATION_OUT_OF_ORDER" and Conference_size == "1" then
local conf_name = event:getHeader("Conference-Name");
local command = api:executeString("conference " .. conf_name .. " list")
local count = api:executeString("conference " .. conf_name .. " count")

if tonumber(count) == 1 then
local uuid_kill = api:executeString("conference " ..conf_name .. " hup last")
freeswitch.consoleLog("INFO","uuid kill:" .. uuid_kill)
end
end
