--------------------------------------------------------------------------------
-- Audio Operations Module
-- 
-- Handles all audio playback related operations including:
-- - Operation 10: Play audio file
-- - Operation 11: Play recorded file
-- - Operation 30: Play audio and get DTMF input
-- - Operation 31: Play audio with menu options
-- - Operation 50: Play number sequence (digit by digit)
--
-- This module demonstrates the standard pattern for operation implementations:
-- 1. Validate session and input data
-- 2. Perform the operation
-- 3. Handle errors gracefully
-- 4. Navigate to next node
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local audio = require "operations.audio"
--   audio.execute(10, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local session_manager = require "core.session_manager"
local call_flow = require "core.call_flow"
local file_utils = require "utils.file_utils"
local logging = require "utils.logging"
local config_utils = require "utils.config_utils"

-- Module logger
local logger = logging.get_logger("operations.audio")

-- Get audio path from FreeSWITCH globals
local function get_audio_path()
    local sounds_dir = freeswitch.getGlobalVariable("sounds_dir")
    return sounds_dir .. "/ivr_audiofiles_tts_new/"
end

--------------------------------------------------------------------------------
-- Execute Audio Operation
-- 
-- Main entry point for all audio operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (10, 11, 30, 31, 50)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format(
        "Executing audio operation %d for node %d",
        operation_code, node_data.NodeId
    ))
    
    -- Route to appropriate handler
    if operation_code == 10 then
        M.play_audio_file(node_data)
    elseif operation_code == 11 then
        M.play_recorded_file(node_data)
    elseif operation_code == 30 then
        M.play_and_get_input(node_data)
    elseif operation_code == 31 then
        M.play_menu_and_get_input(node_data)
    elseif operation_code == 50 then
        M.play_number_sequence(node_data)
    else
        error(string.format("Unknown audio operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Operation 10: Play Audio File
-- 
-- Plays a pre-recorded audio file and then navigates to the next node.
--
-- Node Data Requirements:
-- - VoiceFileId: The filename of the audio file to play
-- - ChildNodeConfig: Configuration for the next node
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.play_audio_file(node_data)
    logger:info(string.format(
        "Operation 10: Playing audio file for node %d",
        node_data.NodeId
    ))
    
    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()
    
    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end
    
    -- Validate that VoiceFileId is provided
    if not node_data.VoiceFileId then
        logger:error("VoiceFileId is missing from node configuration")
        session:hangup()
        return
    end
    
    -- Construct full audio file path
    local audio_path = get_audio_path()
    local audio_file = audio_path .. node_data.VoiceFileId
    
    logger:debug(string.format("Audio file path: %s", audio_file))
    
    -- Check if audio file exists
    if not file_utils.exists(audio_file) then
        logger:error(string.format("Audio file not found: %s", audio_file))
        
        -- Optionally play an error message or just continue
        session:hangup()
        return
    end
    
    -- Play the audio file
    logger:debug(string.format("Playing audio: %s", audio_file))
    session:execute("playback", audio_file)
    
    -- Small pause after playback
    session:sleep(500)
    
    -- Navigate to the child node
    call_flow.find_child_node(node_data)
end

--------------------------------------------------------------------------------
-- Operation 11: Play Recorded File
-- 
-- Plays a caller-recorded audio file (typically from a previous recording
-- operation) and then navigates to the next node.
--
-- Node Data Requirements:
-- - RecordedFileVariable: Session variable containing the path to recorded file
-- - ChildNodeConfig: Configuration for the next node
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.play_recorded_file(node_data)
    logger:info(string.format(
        "Operation 11: Playing recorded file for node %d",
        node_data.NodeId
    ))
    
    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()
    
    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end
    
    -- Get the recorded file path from session variable
    -- Note: Original config uses "TagName", some configs may use "RecordedFileVariable"
    local recorded_file_var = node_data.TagName or node_data.RecordedFileVariable or "recorded_file_path"
    local recorded_file = session_manager.get_variable(recorded_file_var)
    
    if not recorded_file or recorded_file == "" then
        logger:error(string.format(
            "No recorded file found in variable: %s",
            recorded_file_var
        ))
        session:hangup()
        return
    end
    
    logger:debug(string.format("Recorded file path: %s", recorded_file))
    
    -- Check if file exists and has content
    local has_content, file_size = file_utils.has_content(recorded_file)
    
    if not has_content then
        logger:warning(string.format(
            "Recorded file is empty or too small: %s (size: %d bytes)",
            recorded_file, file_size
        ))
        
        -- Could play an error message here
        session:hangup()
        return
    end
    
    -- Play the recorded file
    logger:debug(string.format("Playing recorded file: %s", recorded_file))
    session:execute("playback", recorded_file)
    
    -- Small pause after playback
    session:sleep(500)
    
    -- Navigate to the child node
    call_flow.find_child_node(node_data)
end

--------------------------------------------------------------------------------
-- Operation 30: Play Audio and Get DTMF Input
-- 
-- Plays an audio file and collects a single DTMF digit from the caller,
-- then routes based on the digit pressed.
--
-- Node Data Requirements:
-- - VoiceFileId: The filename of the audio file to play
-- - ValidKeys: String of valid DTMF digits (e.g., "123")
-- - TimeoutInSec: Timeout for input in seconds
-- - InvalidInputAudioFile: Audio to play for invalid input (optional)
-- - ChildNodeConfig: Array of child nodes with DTMFInput mappings
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.play_and_get_input(node_data)
    logger:info(string.format(
        "Operation 30: Playing audio and getting input for node %d",
        node_data.NodeId
    ))
    
    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()
    
    if not session or not session:ready() then
        logger:error("Session is not ready")
        logger:error(tostring(node_data))
        return
    end
    
    -- Validate required fields
    if not node_data.VoiceFileId then
        logger:error("VoiceFileId is missing")
        session:hangup()
        return
    end
    
    if not node_data.ValidKeys then
        logger:error("ValidKeys is missing")
        session:hangup()
        return
    end
    
    -- Construct audio file path
    local audio_path = get_audio_path()
    local audio_file = audio_path .. node_data.VoiceFileId
    
    -- Check if audio file exists
    if not file_utils.exists(audio_file) then
        logger:error(string.format("Audio file not found: %s", audio_file))
        session:hangup()
        return
    end
    
    -- Get timeout (default 5 seconds)
    local timeout = node_data.InputTimeLimit or node_data.TimeoutInSec or 5
    local timeout_ms = timeout * 1000

    -- Build regex pattern: "1,2" → "1|2"
    local dtmf_regex = node_data.ValidKeys:gsub(",", "|")
    -- Escape asterisk for regex: "*" → "\\*"
    dtmf_regex = dtmf_regex:gsub("%*", "\\*")

    logger:debug(string.format(
        "Playing audio with input collection: %s (timeout: %d ms, regex: %s)",
        audio_file, timeout_ms, dtmf_regex
    ))

    -- Play and get digits
    -- FreeSWITCH playAndGetDigits signature (8 args):
    -- min_digits, max_digits, max_tries, timeout, terminators, audio_file, invalid_audio, regex
    local digits = session:playAndGetDigits(
        1,              -- min digits
        1,              -- max digits
        3,              -- max tries
        timeout_ms,     -- timeout in milliseconds
        "",             -- terminator
        audio_file,     -- audio file to play
        "",             -- invalid audio (handled separately)
        dtmf_regex      -- regex for valid input
    )
    
    logger:info(string.format("Collected DTMF input: %s", tostring(digits)))

    -- Store the input in a session variable using TagName from config
    if digits and digits ~= "" then
        -- Store input using TagName if specified
        if node_data.TagName then
            local value_to_store = digits
            if node_data.TagName == "LanguageSelected" then
                logger:debug("Storing language selection input")
                config_utils.set_language(digits)
            end
            -- Apply TagValuePrefix if specified
            if node_data.TagValuePrefix and node_data.TagValuePrefix ~= "" then
                value_to_store = node_data.TagValuePrefix .. digits
                logger:debug(string.format("Applied prefix '%s' to input: %s",
                    node_data.TagValuePrefix, value_to_store))
            end

            session_manager.set_variable(node_data.TagName, value_to_store)
            logger:info(string.format("Stored DTMF input in session variable '%s' = '%s'",
                node_data.TagName, value_to_store))
        else
            -- Fallback to generic variable name if TagName not specified
            session_manager.set_variable("last_dtmf_input", digits)
            logger:debug("No TagName specified, stored in 'last_dtmf_input'")
        end

        call_flow.find_child_node_with_dtmf_input(digits, node_data)
    else
        -- No input received - handle timeout or invalid input
        logger:warning("No valid input received")

        -- Use default input if specified
        if node_data.DeafultInput and node_data.DeafultInput ~= "" then
            logger:info(string.format("Using default input: %s", node_data.DeafultInput))

            if node_data.TagName then
                session_manager.set_variable(node_data.TagName, node_data.DeafultInput)
                logger:info(string.format("Stored default input in '%s' = '%s'",
                    node_data.TagName, node_data.DeafultInput))
            end

            call_flow.find_child_node_with_dtmf_input(node_data.DeafultInput, node_data)
        else
            call_flow.handle_invalid_input(node_data)
        end
    end
end

--------------------------------------------------------------------------------
-- Operation 31: Play Menu and Get Input
-- 
-- Similar to Operation 30 but with additional menu-specific handling.
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.play_menu_and_get_input(node_data)
    logger:info(string.format(
        "Operation 31: Playing menu and getting input for node %d",
        node_data.NodeId
    ))
    
    -- For now, delegate to Operation 30 (they have similar logic)
    -- Can be extended with menu-specific features later
    M.play_and_get_input(node_data)
end

--------------------------------------------------------------------------------
-- Operation 50: Play Number Sequence
-- 
-- Plays a number digit by digit. Useful for playing back phone numbers,
-- account numbers, etc.
--
-- Node Data Requirements:
-- - DeafultInput: Session variable name containing the number to play
-- - LanguageTag: Language code for digit audio files (optional)
-- - ChildNodeConfig: Configuration for the next node
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.play_number_sequence(node_data)
    logger:info(string.format(
        "Operation 50: Playing number sequence for node %d",
        node_data.NodeId
    ))
    
    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()
    
    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end
    
    -- Get the number to play from session variable
    local number_var = node_data.DeafultInput
    if not number_var then
        logger:error("DeafultInput (variable name) is missing")
        session:hangup()
        return
    end
    
    local number_value = session_manager.get_variable(number_var)
    
    if not number_value or number_value == "" then
        logger:error(string.format(
            "No value found in variable: %s",
            number_var
        ))
        session:hangup()
        return
    end
    
    logger:info(string.format("Playing number: %s", number_value))
    
    -- Get language tag for audio files (default to "en" if not specified)
    local language_tag = node_data.LanguageTag or "en"
    
    -- Split the number into individual digits
    local digits = {}
    for i = 1, #number_value do
        local char = string.sub(number_value, i, i)
        -- Only process non-whitespace characters
        if char:match("%S") then
            table.insert(digits, char)
        end
    end
    
    -- Play each digit
    local sounds_dir = freeswitch.getGlobalVariable("sounds_dir")
    
    for _, digit in ipairs(digits) do
        local digit_file = string.format(
            "%s/%s/%s.wav",
            sounds_dir, language_tag, digit
        )
        
        logger:debug(string.format("Playing digit: %s", digit_file))
        
        if file_utils.exists(digit_file) then
            session:execute("playback", digit_file)
            session:execute("sleep", "500")  -- Pause between digits
        else
            logger:warning(string.format("Digit file not found: %s", digit_file))
        end
    end
    
    -- Navigate to the child node
    call_flow.find_child_node(node_data)
end

return M

--------------------------------------------------------------------------------
-- End of audio.lua
--------------------------------------------------------------------------------