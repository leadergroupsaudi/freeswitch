--------------------------------------------------------------------------------
-- Text-to-Speech Operations Module
--
-- Handles all text-to-speech related operations including:
-- - Operation 330: Built-in TTS (using Flite)
-- - Operation 331: Cloud TTS (using Azure)
--
-- These operations convert text stored in session variables to speech
-- and play it to the caller.
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local tts = require "operations.tts"
--   tts.execute(330, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local session_manager = require "core.session_manager"
local call_flow = require "core.call_flow"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("operations.tts")

--------------------------------------------------------------------------------
-- Execute TTS Operation
--
-- Main entry point for all TTS operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (330, 331)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format(
        "Executing TTS operation %d for node %d",
        operation_code, node_data.NodeId
    ))

    -- Route to appropriate handler
    if operation_code == 330 then
        M.tts_builtin(node_data)
    elseif operation_code == 331 then
        M.tts_cloud(node_data)
    else
        error(string.format("Unknown TTS operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Helper: Insert spaces between digits
--
-- Adds spaces between digits in a string for better TTS pronunciation
-- of numbers (e.g., "123" becomes " 1 2 3").
--
-- @param str string - String containing digits
-- @return string - String with spaces between digits
--------------------------------------------------------------------------------
local function insert_spaces(str)
    local result = ""

    for i = 1, #str do
        local char = str:sub(i, i)
        if char:match("%d") then
            result = result .. " " .. char
        else
            result = result .. char
        end
    end

    return result
end

--------------------------------------------------------------------------------
-- Helper: Format text for TTS
--
-- Formats text for better TTS pronunciation, including spacing out numbers.
--
-- @param text string - Text to format
-- @return string - Formatted text
--------------------------------------------------------------------------------
local function format_tts_text(text)
    if not text then
        return ""
    end

    -- Find numbers and add spaces between digits
    local number = text:match("(%d+)")

    if number then
        local formatted_number = insert_spaces(number)
        text = text:gsub(number, formatted_number)
    end

    return text
end

--------------------------------------------------------------------------------
-- Operation 330: Built-in TTS
--
-- Uses FreeSWITCH's built-in Flite TTS engine to convert text to speech.
--
-- Node Data Requirements:
-- - DeafultInput: Session variable containing the text to speak
--
-- Session Variables Used:
-- - TTSVoiceNameBuiltIn: Voice name for Flite (e.g., "slt", "rms", "awb")
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.tts_builtin(node_data)
    logger:info(string.format(
        "Operation 330: Built-in TTS for node %d",
        node_data.NodeId
    ))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get text from session variable
    if not node_data.DeafultInput then
        logger:error("DeafultInput not specified")
        call_flow.find_child_node(node_data)
        return
    end

    local tts_text = session_manager.get_variable(node_data.DeafultInput)

    if not tts_text or tts_text == "" then
        logger:warning("No text found in variable: " .. node_data.DeafultInput)
        call_flow.find_child_node(node_data)
        return
    end

    -- Format text for TTS (add spaces between digits)
    tts_text = format_tts_text(tts_text)

    logger:info("TTS text: " .. tts_text)

    -- Get voice name (default to "slt" - female voice)
    local tts_voice = session_manager.get_variable("TTSVoiceNameBuiltIn") or "slt"

    logger:debug("Using Flite voice: " .. tts_voice)

    -- Set TTS parameters
    session:set_tts_params("flite", tts_voice)

    -- Small pause before speaking
    session:execute("sleep", "200")

    -- Speak the text
    session:speak(tts_text)

    -- Small pause after speaking
    session:execute("sleep", "300")

    -- Navigate to child node
    call_flow.find_child_node(node_data)
end

--------------------------------------------------------------------------------
-- Operation 331: Cloud TTS
--
-- Uses Azure cloud TTS service for higher quality speech synthesis.
--
-- Node Data Requirements:
-- - DeafultInput: Session variable containing the text to speak
--
-- Session Variables Used:
-- - TTSVoiceNameCloud: Azure voice name
--
-- Note: Requires Azure TTS configuration in FreeSWITCH with valid
-- subscription key and region.
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.tts_cloud(node_data)
    logger:info(string.format(
        "Operation 331: Cloud TTS for node %d",
        node_data.NodeId
    ))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get text from session variable
    if not node_data.DeafultInput then
        logger:error("DeafultInput not specified")
        call_flow.find_child_node(node_data)
        return
    end

    local tts_text = session_manager.get_variable(node_data.DeafultInput)

    if not tts_text or tts_text == "" then
        logger:warning("No text found in variable: " .. node_data.DeafultInput)
        call_flow.find_child_node(node_data)
        return
    end

    logger:info("TTS text: " .. tts_text)

    -- Get Azure voice name
    local tts_voice = session_manager.get_variable("TTSVoiceNameCloud")

    if not tts_voice then
        logger:warning("TTSVoiceNameCloud not set, using default")
        tts_voice = "en-US-JennyNeural"  -- Default Azure voice
    end

    logger:debug("Using Azure voice: " .. tts_voice)

    -- Set TTS parameters for Azure
    session:set_tts_params("azure_tts", tts_voice)

    -- Small pause before speaking
    session:execute("sleep", "200")

    -- Speak with Azure TTS
    -- Get Azure configuration from session variables or FreeSWITCH globals
    local azure_key = session_manager.get_variable("AZURE_SUBSCRIPTION_KEY") or
                      freeswitch.getGlobalVariable("azure_subscription_key")
    local azure_region = session_manager.get_variable("AZURE_REGION") or
                        freeswitch.getGlobalVariable("azure_region") or
                        "uksouth"
    local azure_speed = session_manager.get_variable("AZURE_TTS_SPEED") or "0"

    if not azure_key then
        logger:error("Azure subscription key not configured")
        logger:error("Set 'azure_subscription_key' in FreeSWITCH globals or AZURE_SUBSCRIPTION_KEY session variable")
        call_flow.find_child_node(node_data)
        return
    end

    local azure_config = string.format(
        "{AZURE_SUBSCRIPTION_KEY=%s,AZURE_REGION=%s,speed=%s}",
        azure_key,
        azure_region,
        azure_speed
    )

    session:speak(azure_config .. tts_text)

    -- Small pause after speaking
    session:execute("sleep", "500")

    -- Navigate to child node
    call_flow.find_child_node(node_data)
end

return M
