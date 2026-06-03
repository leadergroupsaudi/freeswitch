--------------------------------------------------------------------------------
-- Transfer Operations Module
--
-- Handles all call transfer related operations including:
-- - Operation 100: Transfer to call center queue
-- - Operation 101: Transfer to call center with evaluation
-- - Operation 107: Direct extension transfer
-- - Operation 108: External line (gateway) transfer
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local transfer = require "operations.transfer"
--   transfer.execute(100, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------
local M = {}

-- Load dependencies
local session_manager = require "core.session_manager"
local call_flow = require "core.call_flow"
local config = require "config"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("operations.transfer")

-- FreeSWITCH API instance
local api = freeswitch.API()

--------------------------------------------------------------------------------
-- Execute Transfer Operation
--
-- Main entry point for all transfer operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (100, 101, 107, 108)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format("Executing transfer operation %d for node %d", operation_code, node_data.NodeId))

    -- Route to appropriate handler
    if operation_code == 100 then
        M.transfer_to_queue(node_data)
    elseif operation_code == 101 then
        M.transfer_to_queue_with_evaluation(node_data)
     elseif operation_code == 102 then
        M.transfer_to_queue_with_evaluation(node_data)
    elseif operation_code == 107 then
        M.direct_extension_transfer(node_data)
    elseif operation_code == 108 then
        M.external_line_transfer(node_data)
    else
        error(string.format("Unknown transfer operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Helper: Update Agent Status
--
-- Updates call center agent configuration based on extension status.
--
-- @param extension_code string - The agent's extension
-- @param is_agent boolean - Whether this is an agent (vs supervisor)
-- @return boolean - True if agent is available
--------------------------------------------------------------------------------
local function update_agent_status(extension_code, is_agent)
    local ext_not_reg = "error/user_not_registered"

    if not is_agent then
        -- Non-agent (supervisor) - just set to Idle
        api:executeString("callcenter_config agent set state " .. extension_code .. " Idle")
        return false
    end

    -- Check if extension is registered
    local extension_status = api:executeString("sofia_contact " .. extension_code)
    logger:debug(string.format("Extension %s status: %s", extension_code, extension_status))

    if extension_status ~= ext_not_reg then
        -- Agent is registered - set to available
        api:executeString("callcenter_config agent set status " .. extension_code .. " Available")
        api:executeString("callcenter_config agent set contact " .. extension_code .. " " .. extension_status)
        api:executeString("callcenter_config agent set state " .. extension_code .. " Waiting")

        local agent_state = api:executeString("callcenter_config agent get state " .. extension_code)
        logger:debug(string.format("Agent %s state: %s", extension_code, agent_state))

        return true
    else
        -- Agent not registered - set to logged out
        logger:warning(string.format("Extension %s not registered, setting to Logged Out", extension_code))
        api:executeString("callcenter_config agent set status " .. extension_code .. " 'Logged Out'")
        return false
    end
end

--------------------------------------------------------------------------------
-- Operation 100: Transfer to Call Center Queue
--
-- Transfers the caller to a call center queue. Updates agent statuses
-- and then places the call in queue.
--
-- Node Data Requirements:
-- - QueueName: Name of the call center queue (optional, defaults to ccm-ivr@default)
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.transfer_to_queue(node_data)
    logger:info(string.format("Operation 100: Transfer to call center queue for node %d", node_data.NodeId))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get agent extensions configuration
    local agent_extensions = config.get_agent_extensions()

    if not agent_extensions or not agent_extensions.Extensions then
        logger:error("Agent extensions configuration not found")
        session:hangup()
        return
    end

    -- Update all agent statuses
    local available_agents = {}

    for _, agent in pairs(agent_extensions.Extensions) do
        if update_agent_status(agent.ExtensionCode, agent.IsAgent) then
            table.insert(available_agents, agent.ExtensionCode)
        end
    end

    logger:info(string.format("Available agents: %d", #available_agents))

    -- Transfer to call center queue

    --local queue_name = node_data.QueueName or "ccm-ivr@default"
    local queue_name = node_data.QueueName or "ccm-transfer@default"

    session:execute("sleep", "500")
    session:execute("callcenter", queue_name)

    logger:info("Call transferred to queue: " .. queue_name)
end

--------------------------------------------------------------------------------
-- Operation 101: Transfer to Queue with Evaluation
--
-- Transfers the caller to a call center queue with post-call evaluation.
-- Sets up variables for returning to IVR after agent interaction.
--
-- Node Data Requirements:
-- - QueueName: Name of the call center queue (optional)
-- - NodeId: Used to track return point for evaluation
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.transfer_to_queue_with_evaluation(node_data)
    logger:info(string.format("Operation 101: Transfer to queue with evaluation for node %d", node_data.NodeId))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get agent extensions configuration
    local agent_extensions = config.get_agent_extensions()

    if not agent_extensions or not agent_extensions.Extensions then
        logger:error("Agent extensions configuration not found")
        session:hangup()
        return
    end

    -- Update agent statuses (with DND check)
    local available_agents = {}

    for _, agent in pairs(agent_extensions.Extensions) do
        if not agent.IsAgent then
            api:executeString("callcenter_config agent set state " .. agent.ExtensionCode .. " Idle")
        else
            local ext_not_reg = "error/user_not_registered"
            local extension_status = api:executeString("sofia_contact " .. agent.ExtensionCode)

            if extension_status ~= ext_not_reg then
                local dnd_status = api:executeString("global_getvar agent_" .. agent.ExtensionCode .. "_status")
                logger:debug(string.format("Agent %s DND status: %s", agent.ExtensionCode, dnd_status or "Not Set"))

                local agent_state = api:executeString("callcenter_config agent get state " .. agent.ExtensionCode)

                if dnd_status == "Busy" then
                    logger:debug("Agent " .. agent.ExtensionCode .. " is in DND, skipping")
                elseif agent_state == "In a queue call" then
                    logger:debug("Agent " .. agent.ExtensionCode .. " is in a queue call, skipping")
                else
                    api:executeString("callcenter_config agent set status " .. agent.ExtensionCode .. " Available")
                    api:executeString("callcenter_config agent set contact " .. agent.ExtensionCode .. " " ..
                                          extension_status)
                    api:executeString("callcenter_config agent set state " .. agent.ExtensionCode .. " Waiting")
                    table.insert(available_agents, agent.ExtensionCode)
                end
            else
                api:executeString("callcenter_config agent set status " .. agent.ExtensionCode .. " 'Logged Out'")
            end
        end
    end

    logger:info(string.format("Available agents: %d", #available_agents))

    -- Set up for returning to IVR after agent interaction
    session:execute("sleep", "500")
    session:setAutoHangup(false)
    session:setVariable("cc_last_nodeId", node_data.NodeId)

    -- Transfer to dialplan that handles evaluation return
   -- session:execute("transfer", "OPCODE_101 XML default")
if node_data.NodeId == 1026 then
    session:execute("transfer", "OPCODE_102 XML default")

elseif node_data.NodeId == 1027 then
    session:execute("transfer", "OPCODE_101 XML default")
end
    logger:info("Call transferred for evaluation flow")
end




--------------------------------------------------------------------------------
-- Operation 107: Direct Extension Transfer
--
-- Transfers the call directly to a specific extension defined in the
-- node configuration.
--
-- Node Data Requirements:
-- - ValidKeys: The extension number to transfer to
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.direct_extension_transfer(node_data)
    logger:info(string.format("Operation 107: Direct extension transfer for node %d", node_data.NodeId))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get extension from configuration
    local extension = node_data.ValidKeys

    if not extension or extension == "" then
        logger:error("No extension specified in ValidKeys")
        call_flow.find_child_node_with_dtmf_input("F", node_data)
        return
    end

    logger:info("Transferring to extension: " .. extension)

    -- Get domain and caller info
    local domain = session:getVariable("domain_name")
    local caller_name = session:getVariable("caller_id_name")
    local caller_id = session:getVariable("caller_id_number")

    -- Check if extension exists
    local cmd = "user_exists id " .. extension .. " " .. domain
    local found = api:executeString(cmd)

    logger:debug("Extension check result: " .. tostring(found))

    if found == "true" then
        -- Build dial string
        local dial_string = string.format("{origination_caller_id_name=%s,origination_caller_id_number=%s," ..
                                              "originate_timeout=30,hangup_after_bridge=true}user/%s@%s",
            caller_name or "Unknown", caller_id or "Unknown", extension, domain)

        logger:debug("Dial string: " .. dial_string)

        -- Set ringback tone
        session:execute("set", "ringback=${us-ring}")

        -- Create second session
        local second_session = freeswitch.Session(dial_string)

        if second_session:ready() then
            logger:info("Second leg answered, bridging")
            freeswitch.bridge(session, second_session)
        else
            logger:warning("Second leg failed")

            -- Play error message
            session:set_tts_params("flite", "slt")
            session:execute("sleep", "1000")
            session:speak("Hello! The entered Extension is not available or Busy")
            session:execute("sleep", "1000")
            session:hangup()
        end
    else
        logger:warning("Extension not found: " .. extension)
        call_flow.find_child_node_with_dtmf_input("F", node_data)
    end
end

--------------------------------------------------------------------------------
-- Operation 108: External Line Transfer
--
-- Transfers the call to an external phone number through a SIP gateway.
--
-- Node Data Requirements:
-- - ValidKeys: The external phone number to transfer to
-- - GatewayName: Name of the SIP gateway (optional, defaults to fxax-gateway)
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.external_line_transfer(node_data)
    logger:info(string.format("Operation 108: External line transfer for node %d", node_data.NodeId))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get external number from configuration
    local extension = node_data.ValidKeys

    if not extension or extension == "" then
        logger:error("No external number specified in ValidKeys")
        call_flow.find_child_node_with_dtmf_input("F", node_data)
        return
    end

    logger:info("Transferring to external number: " .. extension)

    -- Get gateway name (default to fxax-gateway)
    local gateway_name = node_data.GatewayName or "fxax-gateway"

    -- Build dial string for gateway
    local dial_string = string.format("sofia/gateway/%s/%s", gateway_name, extension)

    logger:debug("External dial string: " .. dial_string)

    -- Create second session
    local second_session = freeswitch.Session(dial_string)

    if second_session:ready() then
        logger:info("External leg answered, bridging")
        freeswitch.bridge(session, second_session)
        logger:debug("Bridge completed")
    else
        logger:warning("External leg failed")

        -- Play error message
        session:set_tts_params("flite", "awb")
        session:speak("The pre defined Extension is not valid")

        call_flow.find_child_node_with_dtmf_input("F", node_data)
    end
end

return M
