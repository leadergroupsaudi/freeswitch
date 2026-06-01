api = freeswitch.API();
local uuid = session:getVariable("UUID");
local caller = session:getVariable("caller");
local callee = session:getVariable("callee");
callerid = session:getVariable("caller_id_number");
calleridname = session:getVariable("caller_id_name");
--local option = tonumber(argv[1]);
option=argv[1];
url = "http://127.0.0.1/file.php?uuid=";
if caller ~= nil then freeswitch.consoleLog("info","Caller is: "..caller);end
if callee ~= nil then freeswitch.consoleLog("info","Callee is: "..callee);end
if option ~= nil then freeswitch.consoleLog("info","Main Option is: "..option);end


if (option == "1" ) then
session:execute("transfer","en_msg XML default");
elseif option == "0" then
session:execute("transfer","record_name XML default");
end


