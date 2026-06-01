local api = freeswitch.API()

local agent = argv[1]
local cause = argv[2]

freeswitch.consoleLog("INFO", string.format("Agent %s cancelled or rejected call. Cause: %s\n", agent, cause))

