local calling_agent = session:getVariable("caller_id_number")
local domain = "15.207.94.247"
local ring_timeout = 20

-- Full agent list
local agents = {
    "1001","1002","1003","1004","1005",
    "1006","1007","1008","1009","1010",
    "1011","1012","1013","1014","1015",
    "1016","1017","1018","1999","1019","1020"
}

-- Check if agent is registered
local function is_agent_available(agent)
    local contact = freeswitch.API():execute("sofia_contact", agent .. "@" .. domain)
    if not contact or contact == "" or contact:find("error") or contact:find("ERR") then
        return false
    end
    return true
end

-- Build pool of available agents (excluding caller)
local targets = {}
for _, agent in ipairs(agents) do
    if agent ~= calling_agent and is_agent_available(agent) then
        table.insert(targets,
            "[absolute_codec_string='PCMU,PCMA,G722',leg_timeout=" .. ring_timeout .. "]user/" .. agent .. "@" .. domain)
        freeswitch.consoleLog("INFO", "Available agent: " .. agent .. "\n")
    end
end

if #targets == 0 then
    freeswitch.consoleLog("WARNING", "No agents available\n")
    session:setVariable("no_agents_available", "true")
    return
end

-- Bridge to all available agents simultaneously
local bridge_string = table.concat(targets, "|")
freeswitch.consoleLog("INFO", "Bridging to " .. #targets .. " agents\n")
session:execute("bridge", bridge_string)

local dial_status = session:getVariable("DIALSTATUS")
if dial_status == "SUCCESS" then
    freeswitch.consoleLog("INFO", "Call answered. Connected to: " .. tostring(session:getVariable("last_bridge_to")) .. "\n")
else
    freeswitch.consoleLog("WARNING", "No agent answered. DIALSTATUS: " .. tostring(dial_status) .. "\n")
    session:setVariable("no_agent_answered", "true")
end

