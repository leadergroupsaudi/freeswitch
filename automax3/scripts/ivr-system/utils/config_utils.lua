--------------------------------------------------------------------------------
-- Configuration Utilities Module
--
-- Provides utility functions for working with IVR configuration settings,
-- including language configuration and session variable management.
--
-- Features:
-- - Language configuration loading and session variable setup
-- - Access to general settings with proper error handling
-- - Integration with session manager and configuration system
--
-- Usage:
--   local config_utils = require "utils.config_utils"
--   config_utils.set_language("1")  -- Set language by code
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local config = require "config"
local session_manager = require "core.session_manager"
local json_utils = require "utils.json_utils"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("utils.config_utils")

--------------------------------------------------------------------------------
-- Set Language Configuration
--
-- Reads language settings from general configuration (SettingId 15) and
-- sets all language-specific session variables based on the selected
-- language code.
--
-- This function:
-- 1. Retrieves general settings from configuration
-- 2. Locates language configuration (SettingId 15)
-- 3. Parses language settings JSON
-- 4. Finds matching language by code
-- 5. Sets all key-value pairs as session variables
--
-- @param language_code string|number - The language code to activate
-- @return boolean - True if language was set successfully, false otherwise
--------------------------------------------------------------------------------
function M.set_language(language_code)
    logger:info(string.format("Setting language to: %s", tostring(language_code)))

    -- Get general settings from configuration
    local general_settings = config.get_general_settings()

    if not general_settings then
        logger:error("Failed to retrieve general settings from configuration")
        return false
    end

    -- Find language settings (SettingId 15)
    for _, settings in pairs(general_settings) do
        if settings.SettingId == 15 then
            logger:debug("Found language settings configuration")

            -- Parse language settings JSON
            local success, language_settings = json_utils.decode(settings.SettingValue)

            if not success then
                logger:error(string.format(
                    "Failed to parse language settings JSON: %s",
                    tostring(language_settings)
                ))
                return false
            end

            -- Convert language_code to number for comparison
            local target_code = tonumber(language_code)

            if not target_code then
                logger:warning(string.format(
                    "Invalid language code format: %s",
                    tostring(language_code)
                ))
                return false
            end

            -- Find matching language configuration
            for _, language_setting in ipairs(language_settings) do
                if language_setting.LanguageCode == target_code then
                    logger:info(string.format(
                        "Found matching language configuration for code: %d",
                        target_code
                    ))

                    -- Set all language configuration values as session variables
                    local var_count = 0
                    for key, value in pairs(language_setting) do
                        session_manager.set_variable(key, value)
                        var_count = var_count + 1
                        logger:debug(string.format(
                            "Set session variable: %s = %s",
                            key,
                            tostring(value)
                        ))
                    end

                    logger:info(string.format(
                        "Successfully set %d session variables for language %d",
                        var_count,
                        target_code
                    ))

                    return true
                end
            end

            -- Language code not found in settings
            logger:warning(string.format(
                "No matching language configuration found for code: %d",
                target_code
            ))
            return false
        end
    end

    -- SettingId 15 not found in general settings
    logger:error("Language settings (SettingId 15) not found in general settings")
    return false
end

return M
