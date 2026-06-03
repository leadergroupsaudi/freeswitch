api = freeswitch.API()

--------------------------------------------------
-- GET CURRENT COUNT
--------------------------------------------------
local count = tonumber(session:getVariable("count") or "0")

--------------------------------------------------
-- INCREMENT COUNT
--------------------------------------------------
count = count + 1

--------------------------------------------------
-- SAVE UPDATED COUNT
--------------------------------------------------
session:setVariable("count", tostring(count))

freeswitch.consoleLog(
    "INFO",
    "Current Retry Count: " .. count .. "\n"
)

--------------------------------------------------
-- MAX RETRY CHECK
--------------------------------------------------
if count >= 3 then

    freeswitch.consoleLog(
        "WARNING",
        "No available agent found after 3 attempts.\n"
    )

session:execute("transfer", "no_agent XML default")
    return
end

--------------------------------------------------
-- TRANSFER TO AGENT
--------------------------------------------------
session:execute("transfer", "agent XML default")
