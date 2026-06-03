--------------------------------------------------------------------------------
-- Input Operations Module
--
-- Handles all input collection related operations including:
-- - Operation 20: Get DTMF input (user input without audio prompt)
-- - Operation 105: Extension transfer input (multi-digit input for extension)
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local input = require "operations.input"
--   input.execute(20, node_data)
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

-- Module logger
local logger = logging.get_logger("operations.input")

-- Get audio path from FreeSWITCH globals
local function get_audio_path()
    local sounds_dir = freeswitch.getGlobalVariable("sounds_dir")
    return sounds_dir .. "/ivr_audiofiles_tts_new/"
end

--------------------------------------------------------------------------------
-- Execute Input Operation
--
-- Main entry point for all input operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (20, 105)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format(
        "Executing input operation %d for node %d",
        operation_code, node_data.NodeId
    ))

    -- Route to appropriate handler
    if operation_code == 20 then
        M.get_user_input(node_data)
    elseif operation_code == 105 then
        M.get_extension_input(node_data)
    else
        error(string.format("Unknown input operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Helper: Check if character exists in allowed set
--
-- @param char string - Single character to check
-- @param set string - Allowed characters string
-- @return boolean - True if character is in set
--------------------------------------------------------------------------------
local function character_exists_in_set(char, set)
    return set:find(char, 1, true) ~= nil
end

--------------------------------------------------------------------------------
-- Helper: Validate all characters in input string
--
-- @param input_string string - Input to validate
-- @param allowed_set string - Allowed characters (comma-separated)
-- @return boolean - True if all characters are valid
--------------------------------------------------------------------------------
local function validate_input_characters(input_string, allowed_set)
    -- Remove commas from allowed set
    local clean_set = allowed_set:gsub(",", "")

    for i = 1, #input_string do
        local char = input_string:sub(i, i)
        if not character_exists_in_set(char, clean_set) then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Operation 20: Get User Input
--
-- Collects DTMF input from the caller without playing an audio prompt.
-- Validates input against ValidKeys and InputLength.
--
-- Node Data Requirements:
-- - ValidKeys: Comma-separated valid DTMF digits
-- - InputLength: Expected number of digits
-- - InputTimeLimit: Timeout in seconds
-- - InvalidInputVoiceFileId: Audio file for invalid input
-- - IsRepetitive: Whether to repeat on invalid input
-- - RepeatLimit: Number of retries allowed
-- - TagName: Session variable to store the input
-- - TimeLimitResponseType: How to handle timeout (10=invalid, 20=default)
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.get_user_input(node_data)
    logger:info(string.format(
        "Operation 20: Getting user input for node %d",
        node_data.NodeId
    ))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Extract configuration
    local valid_digits = node_data.ValidKeys or "0,1,2,3,4,5,6,7,8,9"
    local min_digits = 1
    local max_digits = node_data.InputLength or 1
    local time_limit = (node_data.InputTimeLimit or 5) * 1000
    local audio_path = get_audio_path()
    local invalid_audio = audio_path .. (node_data.InvalidInputVoiceFileId or "InvalidSelection.wav")

    -- Determine repeat limit
    local repeat_limit = 0
    if node_data.IsRepetitive == true then
        repeat_limit = node_data.RepeatLimit or 3
    end

    logger:debug(string.format(
        "Input config - ValidKeys: %s, MaxDigits: %d, Timeout: %dms, Repeats: %d",
        valid_digits, max_digits, time_limit, repeat_limit
    ))

    -- Input collection loop
    for attempt = 0, repeat_limit do
        logger:debug(string.format("DTMF collection attempt %d", attempt + 1))

        -- Clear terminator variable
        session:setVariable("read_terminator_used", "")

        -- Read digits from caller
        local digits = session:read(min_digits, max_digits, "", time_limit, "#")
        local terminator = session:getVariable("read_terminator_used")

        logger:info(string.format(
            "DTMF input received: '%s' (length: %d, terminator: %s)",
            digits or "", #(digits or ""), terminator or "none"
        ))

        -- Process input based on length
        if digits and #digits == max_digits then
            -- Full input received - validate characters
            if validate_input_characters(digits, valid_digits) then
                logger:info("Valid input received: " .. digits)

                -- Store in session variable
                if node_data.TagName then
                    session_manager.set_variable(node_data.TagName, digits)
                    logger:debug(string.format(
                        "Stored input in variable: %s = %s",
                        node_data.TagName, digits
                    ))
                end

                -- Navigate to child node with "#" as input key (success)
                call_flow.find_child_node_with_dtmf_input("#", node_data)
                return
            else
                -- Invalid characters
                logger:warning("Invalid characters in input")
                if file_utils.exists(invalid_audio) then
                    session:execute("playback", invalid_audio)
                end
            end

        elseif digits and #digits > 0 and #digits < max_digits then
            -- Partial input received
            logger:warning(string.format(
                "Incomplete input: got %d digits, expected %d",
                #digits, max_digits
            ))

            if attempt == repeat_limit then
                -- Last attempt - mark as invalid
                call_flow.find_child_node_with_dtmf_input("X", node_data)
                return
            else
                if file_utils.exists(invalid_audio) then
                    session:execute("playback", invalid_audio)
                end
            end

        elseif not digits or #digits == 0 then
            -- No input received (timeout)
            logger:warning("No DTMF input received (timeout)")

            if terminator ~= "#" and node_data.TimeLimitResponseType == 20 then
                -- Use default input
                call_flow.find_child_node_with_dtmf_input("D", node_data)
                return
            elseif node_data.TimeLimitResponseType == 10 and attempt == repeat_limit then
                -- Mark as invalid after all attempts
                call_flow.find_child_node_with_dtmf_input("X", node_data)
                return
            else
                if file_utils.exists(invalid_audio) then
                    session:execute("playback", invalid_audio)
                end
            end
        end
    end

    -- Exhausted all attempts
    logger:warning("All input attempts exhausted")
    call_flow.find_child_node_with_dtmf_input("X", node_data)
end

--------------------------------------------------------------------------------
-- Operation 105: Get Extension Input
--
-- Collects extension number from caller and attempts to transfer.
-- This is a specialized input operation for extension dialing.
--
-- Node Data Requirements:
-- - ValidKeys: Comma-separated valid DTMF digits
-- - InputLength: Expected number of digits for extension
-- - InputTimeLimit: Timeout in seconds
-- - InvalidInputVoiceFileId: Audio file for invalid input
-- - TagName: Session variable to store the extension
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.get_extension_input(node_data)
    logger:info(string.format(
        "Operation 105: Getting extension input for node %d",
        node_data.NodeId
    ))

    -- Get the FreeSWITCH session
    local session = session_manager.get_freeswitch_session()

    if not session or not session:ready() then
        logger:error("Session is not ready")
        return
    end

    -- Get domain and caller info
    local domain = session:getVariable("domain_name")
    local caller_name = session:getVariable("caller_id_name")
    local caller_id = session:getVariable("caller_id_number")

    -- Extract configuration
    local valid_digits = node_data.ValidKeys or "0,1,2,3,4,5,6,7,8,9"
    local min_digits = 1
    local max_digits = node_data.InputLength or 4
    local time_limit = (node_data.InputTimeLimit or 5) * 1000
    local audio_path = get_audio_path()
    local invalid_audio = audio_path .. (node_data.InvalidInputVoiceFileId or "InvalidSelection.wav")

    logger:debug(string.format(
        "Extension input config - MaxDigits: %d, Timeout: %dms",
        max_digits, time_limit
    ))

    -- Clear terminator variable
    session:setVariable("read_terminator_used", "")

    -- Read extension digits
    local digits = session:read(min_digits, max_digits, "", time_limit, "#")
    local terminator = session:getVariable("read_terminator_used")

    logger:info(string.format(
        "Extension input received: '%s' (length: %d)",
        digits or "", #(digits or "")
    ))

    -- Process input
    if digits and #digits == max_digits then
        -- Validate characters
        if validate_input_characters(digits, valid_digits) then
            -- Store extension in session variable
            if node_data.TagName then
                session_manager.set_variable(node_data.TagName, digits)
            end

            -- Check if extension exists
            local api = freeswitch.API()
            local cmd = "user_exists id " .. digits .. " " .. domain
            logger:debug("Extension validation command: " .. cmd)

            local found = api:executeString(cmd)

            if found == "true" then
                logger:info("Extension found, attempting transfer: " .. digits)

                -- Set up the call
                session:setVariable("hangup_after_bridge", "true")

                local dial_string = string.format(
                    "{origination_caller_id_name=%s,origination_caller_id_number=%s," ..
                    "originate_timeout=30,hangup_after_bridge=true}user/%s@%s",
                    caller_name or "Unknown",
                    caller_id or "Unknown",
                    digits,
                    domain
                )

                logger:debug("Dial string: " .. dial_string)

                -- Create second session and bridge
                local second_session = freeswitch.Session(dial_string)
                local hangup_cause = second_session:hangupCause()

                if second_session:ready() then
                    logger:info("Second leg answered, bridging calls")
                    freeswitch.bridge(session, second_session)

                    if second_session:ready() then
                        second_session:hangup()
                    end
                end

                -- Check result
                if hangup_cause ~= "SUCCESS" then
                    logger:warning("Extension transfer failed: " .. hangup_cause)

                    -- Play error message
                    session:set_tts_params("flite", "slt")
                    session:execute("sleep", "1000")
                    session:speak("Hello! The entered Extension is not available or Busy")
                    session:execute("sleep", "1000")
                    session:hangup()
                end
                return
            else
                logger:warning("Extension not found: " .. digits)
                call_flow.find_child_node_with_dtmf_input("F", node_data)
                return
            end
        else
            -- Invalid characters
            if file_utils.exists(invalid_audio) then
                session:execute("playback", invalid_audio)
            end
        end

    elseif digits and #digits > 0 and #digits < max_digits then
        -- Partial input
        logger:warning("Incomplete extension input")
        call_flow.find_child_node_with_dtmf_input("F", node_data)
        return

    else
        -- No input
        logger:warning("No extension input received")
        call_flow.find_child_node_with_dtmf_input("F", node_data)
        return
    end
end

return M
