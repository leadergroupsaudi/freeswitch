api = freeswitch.API();

-- ==========================================================================
-- track_agents.lua
-- Description: Tracks all agents offered a call in FreeSWITCH Call Center
-- Logs them in console and in /usr/local/freeswitch/log/agent_history.log
-- ==========================================================================

-- Table to store all agents who were offered the call
local offered_agents = {}

-- File path for saving agent offer logs
local logfile = "/usr/local/freeswitch/log/agent_history.log"

-- Get the current session object
local session = nil
if freeswitch then
    session = freeswitch.Session()
end

-- Function to log messages
local function log(level, message)
    freeswitch.consoleLog(level, "[track_agents] " .. message .. "\n")
end

-- Function to append text to a file
local function append_to_file(path, text)
    local file = io.open(path, "a")
    if file then
        file:write(text)
        file:close()
    else
        log("ERR", "Unable to open log file: " .. path)
    end
end

-- Function to record the current agent if available
local function record_current_agent()
    if not session or not session:ready() then return end
    local current_agent = session:getVariable("cc_agent")
    if current_agent and current_agent ~= "" then
        table.insert(offered_agents, current_agent)
        log("NOTICE", "Call offered to agent: " .. current_agent)
    end
end

-- Main logic: Keep polling cc_agent while the call is active
if session and session:ready() then
    log("NOTICE", "Tracking agents for this call...")
    while session:ready() do
        record_current_agent()
        freeswitch.msleep(1000)  -- check every 1 second
    end
end

-- Once call hangs up, log all agents offered
log("NOTICE", "Call ended. Summary of all agents offered:")
for i, agent in ipairs(offered_agents) do
    log("NOTICE", "  " .. i .. ". " .. agent)
end

-- Save to file
append_to_file(logfile, "\n--- Call Summary " .. os.date("%Y-%m-%d %H:%M:%S") .. " ---\n")
for i, agent in ipairs(offered_agents) do
    append_to_file(logfile, "Agent " .. i .. ": " .. agent .. "\n")
end
append_to_file(logfile, "----------------------------------------\n")

log("NOTICE", "Agent history saved to: " .. logfile)


