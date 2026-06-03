-- Load package system
package.path = freeswitch.getGlobalVariable("script_dir") .. "/?.lua;" .. package.path
script_dir = freeswitch.getGlobalVariable("script_dir") 
dofile(dofile(script_dir.."/init.lua"));
local core = require "core"
local config = require "config"
local utils = require "utils"
 
-- Initialize system
local function main()
    local logger = utils.logging.get_logger("main")
    if not session:ready() then
        logger:error("Session not ready")
        return
    end
    -- Load configuration
    local success, err = config.load_all()
    if not success then
        logger:error("Config load failed: " .. err)
        session:hangup()
        return
    end
    -- Initialize core system
    core.initialize(session)
    -- Start call flow
    core.call_flow.start()
end
 
-- Execute
main()
