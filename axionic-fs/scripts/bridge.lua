
local api = freeswitch.API()

-- bridge_action.lua
freeswitch.consoleLog("INFO", ">>> Bridge started! Running bridge.lua <<<\n")

--local uuid = argv[1]  -- current channel uuid
local caller = session:getVariable("caller_id_number")
local agent = session:getVariable("sip_from_user")

-- You can log or call an API here
freeswitch.consoleLog("INFO", "Caller: " .. (caller or "unknown") .. " bridged with agent: " .. (agent or "unknown") .. "\n")

-- Example: call an API or store DB log
-- os.execute("curl -X POST https://example.com/api/bridge?caller=" .. caller .. "&agent=" .. agent)

