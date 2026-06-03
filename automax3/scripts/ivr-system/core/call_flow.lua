--------------------------------------------------------------------------------
-- Call Flow Module
-- 
-- Manages the IVR call flow navigation and routing logic. This module is
-- responsible for:
-- - Finding and executing IVR nodes
-- - Navigating through the node tree (parent/child relationships)
-- - Handling DTMF input routing
-- - Managing call center agent callbacks
-- - Loop detection and infinite recursion prevention
--
-- The call flow follows this pattern:
-- 1. Start at the IsStartNode=true node
-- 2. Execute the operation for that node
-- 3. Based on operation result and user input, navigate to child nodes
-- 4. Repeat until a termination node or hangup occurs
--
-- Usage:
--   local call_flow = require "core.call_flow"
--   call_flow.initialize()
--   call_flow.start()
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local config = require "config"
local session_manager = require "core.session_manager"
local operation_dispatcher = require "core.operation_dispatcher"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("call_flow")

-- Track visited nodes to prevent infinite loops
local visited_nodes = {}
local max_node_visits = 10  -- Maximum times a node can be visited

-- Reference to IVR flow configuration
local ivr_flow = nil

--------------------------------------------------------------------------------
-- Initialize Call Flow Engine
-- 
-- Initializes the call flow engine and loads the IVR flow configuration.
--
-- @return boolean success - True if initialization was successful
--------------------------------------------------------------------------------
function M.initialize()
    logger:info("Initializing call flow engine")
    
    -- Load IVR flow configuration
    ivr_flow = config.get_ivr_flow()
    
    if not ivr_flow then
        logger:error("Failed to load IVR flow configuration")
        return false
    end
    
    logger:info(string.format("Loaded IVR flow with %d nodes", #ivr_flow))
    
    -- Reset visited nodes tracker
    visited_nodes = {}
    
    return true
end

--------------------------------------------------------------------------------
-- Start Call Flow
-- 
-- Starts the IVR call flow by finding and executing the start node.
-- The start node is identified by IsStartNode=true in the configuration.
--
-- @return void
--------------------------------------------------------------------------------
function M.start()
    logger:info("Starting call flow processing")
    
    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()
    
    if not session or not session:ready() then
        logger:error("Session is not ready, cannot start call flow")
        return
    end
    
    -- Answer the call if not already answered
    if not session:answered() then
        logger:info("Answering call...")
        session:answer()
        
        -- Wait for media to be ready
        session:execute("wait_for_silence", "500 1 5 100")
    end
    
    -- Find the start node in the IVR flow
    local start_node = M.find_start_node()
    
    if not start_node then
        logger:error("No start node found in IVR configuration")
        session:hangup()
        return
    end
    
    logger:info(string.format(
        "Found start node - ID: %s, Name: %s, Operation: %d",
        start_node.NodeId,
        start_node.NodeName or "unnamed",
        start_node.OperationCode
    ))
    
    -- Execute the start node
    M.execute_node(start_node)
end

--------------------------------------------------------------------------------
-- Find Start Node
-- 
-- Searches the IVR flow configuration for the node marked as the start node.
--
-- @return table|nil - The start node or nil if not found
--------------------------------------------------------------------------------
function M.find_start_node()
    if not ivr_flow then
        logger:error("IVR flow not loaded")
        return nil
    end
    
    for _, node in pairs(ivr_flow) do
        if node.IsStartNode == true then
            return node
        end
    end
    
    return nil
end

--------------------------------------------------------------------------------
-- Find Node by ID
-- 
-- Searches for a node in the IVR flow by its NodeId.
--
-- @param node_id number - The ID of the node to find
-- @return table|nil - The node data or nil if not found
--------------------------------------------------------------------------------
function M.find_node_by_id(node_id)
    if not ivr_flow then
        logger:error("IVR flow not loaded")
        return nil
    end
    
    for _, node in pairs(ivr_flow) do
        if node.NodeId == node_id then
            return node
        end
    end
    
    logger:warning(string.format("Node with ID %d not found", node_id))
    return nil
end

--------------------------------------------------------------------------------
-- Execute Node
-- 
-- Executes a specific IVR node by dispatching its operation code to the
-- appropriate operation handler. Includes loop detection to prevent
-- infinite recursion.
--
-- @param node_data table - The node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute_node(node_data)
    local node_id = node_data.NodeId
    
    -- Check for infinite loop
    visited_nodes[node_id] = (visited_nodes[node_id] or 0) + 1
    
    if visited_nodes[node_id] > max_node_visits then
        logger:error(string.format(
            "Infinite loop detected - Node %d visited %d times",
            node_id, visited_nodes[node_id]
        ))
        
        local session = session_manager.get_freeswitch_session()
        if session then
            session:hangup()
        end
        return
    end
    
    logger:info(string.format(
        "Executing node %d (%s) - Operation %d (visit #%d)",
        node_id,
        node_data.NodeName or "unnamed",
        node_data.OperationCode,
        visited_nodes[node_id]
    ))
    
    -- Dispatch to the appropriate operation handler
    local success, error_msg = pcall(function()
        operation_dispatcher.execute(node_data.OperationCode, node_data)
    end)
    
    if not success then
        logger:error(string.format(
            "Error executing node %d operation %d: %s",
            node_id, node_data.OperationCode, tostring(error_msg)
        ))
        
        -- Attempt graceful termination
        local session = session_manager.get_freeswitch_session()
        if session then
            session:hangup()
        end
    end
end

--------------------------------------------------------------------------------
-- Find and Execute Child Node
-- 
-- Finds the first child node of the current node and executes it.
-- Used for simple linear navigation through the IVR tree.
--
-- @param current_node table - The current node data
-- @return void
--------------------------------------------------------------------------------
function M.find_child_node(current_node)
    if not current_node.ChildNodeConfig or 
       #current_node.ChildNodeConfig == 0 then
        logger:info(string.format(
            "Node %d has no child nodes, ending flow",
            current_node.NodeId
        ))
        
        local session = session_manager.get_freeswitch_session()
        if session then
            session:hangup()
        end
        return
    end
    
    -- Get the first child node ID
    local child_node_id = current_node.ChildNodeConfig[1].ChildNodeId
    
    logger:debug(string.format(
        "Navigating from node %d to child node %d",
        current_node.NodeId, child_node_id
    ))
    
    -- Find and execute the child node
    local child_node = M.find_node_by_id(child_node_id)
    
    if child_node then
        M.execute_node(child_node)
    else
        logger:error(string.format("Child node %d not found", child_node_id))
        
        local session = session_manager.get_freeswitch_session()
        if session then
            session:hangup()
        end
    end
end

--------------------------------------------------------------------------------
-- Find Child Node by DTMF Input
-- 
-- Searches for a child node that matches the provided DTMF digit(s).
-- Used for menu navigation where user input determines the next node.
--
-- @param digits string - The DTMF digit(s) pressed by the user
-- @param current_node table - The current node data
-- @return void
--------------------------------------------------------------------------------
function M.find_child_node_with_dtmf_input(digits, current_node)
    logger:info(string.format(
        "Finding child node for DTMF input '%s' from node %d",
        digits, current_node.NodeId
    ))
    
    if not current_node.ChildNodeConfig or 
       #current_node.ChildNodeConfig == 0 then
        logger:warning(string.format(
            "Node %d has no child nodes for DTMF routing",
            current_node.NodeId
        ))
        return
    end
    
    -- Search for a child node matching the DTMF input
    -- Note: Original config uses "InputKeys", some configs may use "DTMFInput"
    for _, child_config in ipairs(current_node.ChildNodeConfig) do
        local input_key = child_config.InputKeys or child_config.DTMFInput
        if input_key and tostring(input_key) == tostring(digits) then
            
            logger:info(string.format(
                "Found matching child node %d for DTMF '%s'",
                child_config.ChildNodeId, digits
            ))
            
            local child_node = M.find_node_by_id(child_config.ChildNodeId)
            
            if child_node then
                M.execute_node(child_node)
                return
            end
        end
    end
    
    -- No exact match — fall back to default child (null InputKeys)
    for _, child_config in ipairs(current_node.ChildNodeConfig) do
        local input_key = child_config.InputKeys or child_config.DTMFInput
        if not input_key then
            local child_node = M.find_node_by_id(child_config.ChildNodeId)
            if child_node then
                logger:info(string.format(
                    "Using default (null-key) child node %d for input '%s' from node %d",
                    child_config.ChildNodeId, digits, current_node.NodeId
                ))
                M.execute_node(child_node)
                return
            end
        end
    end

    -- No matching child found
    logger:warning(string.format(
        "No child node found for DTMF input '%s' from node %d",
        digits, current_node.NodeId
    ))

    -- Handle invalid input (could play error message or retry)
    M.handle_invalid_input(current_node)
end

--------------------------------------------------------------------------------
-- Handle Invalid Input
-- 
-- Handles invalid user input by either playing an error message and
-- re-prompting, or terminating the call based on configuration.
--
-- @param current_node table - The current node data
-- @return void
--------------------------------------------------------------------------------
function M.handle_invalid_input(current_node)
    logger:info(string.format(
        "Handling invalid input for node %d",
        current_node.NodeId
    ))
    
    -- Check if node has invalid input handling configured
    if current_node.InvalidInputAudioFile then
        local session = session_manager.get_freeswitch_session()
        if session and session:ready() then
            local audiopath = freeswitch.getGlobalVariable("sounds_dir") .. 
                            "/ivr_audiofiles_tts_new/"
            local sound = audiopath .. current_node.InvalidInputAudioFile
            
            logger:debug("Playing invalid input message: " .. sound)
            session:execute("playback", sound)
            session:sleep(500)
        end
    end
    
    -- Re-execute the current node (give user another chance)
    -- Or implement retry limit logic here
    M.execute_node(current_node)
end

--------------------------------------------------------------------------------
-- Handle Agent Callback
-- 
-- Handles call center agent callback scenarios where a call is returning
-- from a queue or agent interaction.
--
-- @return void
--------------------------------------------------------------------------------
function M.handle_agent_callback()
    logger:info("Handling call center agent callback")
    
    local session = session_manager.get_freeswitch_session()
    
    -- Get call center variables
    local cc_last_node_id = session_manager.get_variable("cc_last_nodeId")
    local cc_cancel_reason = session_manager.get_variable("cc_cancel_reason")
    local cc_agent_bridged = session_manager.get_variable("cc_agent_bridged")
    
    logger:info(string.format(
        "Agent callback details - Last Node: %s, Cancel Reason: %s, Agent Bridged: %s",
        tostring(cc_last_node_id),
        tostring(cc_cancel_reason),
        tostring(cc_agent_bridged)
    ))
    
    -- Handle timeout scenario
    if cc_cancel_reason == "TIMEOUT" then
        logger:info("Agent timeout occurred")
        
        if session and session:ready() then
            session:set_tts_params("flite", "slt")
            session:execute("sleep", "1000")
            session:speak("Sorry, the agents are not available or busy at this moment")
            session:execute("sleep", "1000")
            session:speak("Thank you")
            session:execute("sleep", "1000")
        end
        
        session:hangup()
        return
    end
    
    -- Handle agent bridge scenario
    if cc_agent_bridged == "true" then
        logger:info("Agent was bridged, processing post-call flow")
        
        -- Update agent status
        local cc_agent = session_manager.get_variable("cc_agent")
        if cc_agent then
            M.update_agent_status(cc_agent)
        end
        
        -- Navigate to post-call node if configured
        if cc_last_node_id then
            local node_id = tonumber(cc_last_node_id)
            local last_node = M.find_node_by_id(node_id)
            
            if last_node and last_node.ChildNodeConfig and 
               #last_node.ChildNodeConfig > 0 then
                local child_node_id = last_node.ChildNodeConfig[1].ChildNodeId
                local child_node = M.find_node_by_id(child_node_id)
                
                if child_node then
                    M.execute_node(child_node)
                    return
                end
            end
        end
    end
    
    -- Default: hangup if no specific flow is configured
    session:hangup()
end

--------------------------------------------------------------------------------
-- Update Agent Status
-- 
-- Updates call center agent status after a call.
--
-- @param agent_extension string - The agent's extension number
-- @return void
--------------------------------------------------------------------------------
function M.update_agent_status(agent_extension)
    logger:info(string.format("Updating status for agent %s", agent_extension))
    
    local api = freeswitch.API()
    local ext_not_reg = "error/user_not_registered"
    
    -- Check if extension is registered
    local extension_status = api:executeString("sofia_contact " .. agent_extension)
    
    logger:debug(string.format(
        "Agent %s status: %s",
        agent_extension, extension_status
    ))
    
    if extension_status ~= ext_not_reg then
        -- Agent is registered, set to available
        api:executeString("callcenter_config agent set status " .. 
                        agent_extension .. " Available")
        api:executeString("callcenter_config agent set contact " .. 
                        agent_extension .. " " .. extension_status)
        api:executeString("callcenter_config agent set state " .. 
                        agent_extension .. " Waiting")
        
        logger:info(string.format("Agent %s set to Available", agent_extension))
    else
        -- Agent is not registered, set to logged out
        api:executeString("callcenter_config agent set status " .. 
                        agent_extension .. " 'Logged Out'")
        
        logger:warning(string.format(
            "Agent %s not registered, set to Logged Out",
            agent_extension
        ))
    end
end

return M
