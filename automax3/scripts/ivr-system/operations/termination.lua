--------------------------------------------------------------------------------
-- Termination Operations Module
--
-- Handles call termination operations:
-- - Operation 200: Terminate/hangup the call
--
-- This module provides graceful call termination with optional
-- cleanup and logging.
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local termination = require "operations.termination"
--   termination.execute(200, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local session_manager = require "core.session_manager"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("operations.termination")

--------------------------------------------------------------------------------
-- Execute Termination Operation
--
-- Main entry point for all termination operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (200)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format(
        "Executing termination operation %d for node %d",
        operation_code, node_data.NodeId
    ))

    -- Route to appropriate handler
    if operation_code == 200 then
        M.hangup(node_data)
    else
        error(string.format("Unknown termination operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Operation 200: Hangup
--
-- Terminates the call gracefully. Can optionally play a goodbye message
-- or perform cleanup tasks before hanging up.
--
-- Node Data Requirements:
-- - GoodbyeAudioFile: Optional audio file to play before hangup
-- - HangupCause: Optional hangup cause code
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.hangup(node_data)
    logger:info(string.format(
        "Operation 200: Terminating call for node %d",
        node_data.NodeId
    ))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session then
        logger:warning("Session is nil, nothing to hangup")
        return
    end

    if not session:ready() then
        logger:warning("Session is not ready, may already be hung up")
        return
    end

    -- Log call information before hangup
    local call_uuid = session:getVariable("uuid")
    local caller_id = session:getVariable("caller_id_number")

    logger:info(string.format(
        "Hanging up call - UUID: %s, Caller: %s",
        call_uuid or "unknown",
        caller_id or "unknown"
    ))

    -- Play goodbye audio if configured
    if node_data.GoodbyeAudioFile then
        local sounds_dir = freeswitch.getGlobalVariable("sounds_dir")
        local audio_path = sounds_dir .. "/ivr_audiofiles_tts_new/"
        local goodbye_file = audio_path .. node_data.GoodbyeAudioFile

        logger:debug("Playing goodbye audio: " .. goodbye_file)

        -- Check if file exists before playing
        local f = io.open(goodbye_file, "r")
        if f then
            f:close()
            session:execute("playback", goodbye_file)
            session:execute("sleep", "500")
        else
            logger:warning("Goodbye audio file not found: " .. goodbye_file)
        end
    end

    -- Perform any cleanup tasks
    M.cleanup_before_hangup(session, node_data)

    -- Get hangup cause if specified
    local hangup_cause = node_data.HangupCause or "NORMAL_CLEARING"

    logger:info("Executing hangup with cause: " .. hangup_cause)

    -- Hangup the call
    session:hangup(hangup_cause)
end

--------------------------------------------------------------------------------
-- Cleanup Before Hangup
--
-- Performs cleanup tasks before hanging up the call. This can include
-- updating databases, sending notifications, etc.
--
-- @param session object - The FreeSWITCH session
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.cleanup_before_hangup(session, node_data)
    logger:debug("Performing cleanup before hangup")

    -- Get call statistics
    local call_uuid = session:getVariable("uuid")
    local call_start = session:getVariable("start_epoch")
    local call_duration = session:getVariable("billsec")

    logger:info(string.format(
        "Call statistics - UUID: %s, Duration: %s seconds",
        call_uuid or "unknown",
        call_duration or "0"
    ))

    -- Additional cleanup tasks can be added here:
    -- - Update call log database
    -- - Send notification to external system
    -- - Clean up temporary files
    -- - Release resources

    -- Example: Clean up any temporary recording files
    local temp_recording = session:getVariable("temp_recording_path")
    if temp_recording then
        logger:debug("Cleaning up temporary recording: " .. temp_recording)
        -- Could delete the file here if needed
    end

    logger:debug("Cleanup completed")
end

--------------------------------------------------------------------------------
-- Force Hangup
--
-- Forces an immediate hangup without cleanup. Use in error scenarios
-- where normal hangup might fail.
--
-- @return void
--------------------------------------------------------------------------------
function M.force_hangup()
    logger:warning("Force hangup requested")

    local session = session_manager.get_freeswitch_session()

    if session then
        -- Attempt direct hangup
        pcall(function()
            session:hangup("NORMAL_CLEARING")
        end)
    end

    logger:info("Force hangup completed")
end

return M
