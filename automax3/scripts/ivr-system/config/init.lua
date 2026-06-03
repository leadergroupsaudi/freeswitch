--------------------------------------------------------------------------------
-- Configuration Module
-- 
-- Handles loading and caching of all IVR system configuration files including:
-- - IVR flow configuration (nodes, operations, routing)
-- - Web API endpoint configurations
-- - Agent extension mappings
-- - Recording type configurations
--
-- Features:
-- - File modification detection for hot-reloading
-- - In-memory caching with TTL support
-- - Atomic configuration updates
-- - Validation of required configuration fields
--
-- Usage:
--   local config = require "config"
--   config.load_all()  -- Load all configurations
--   local ivr_config = config.get("ivr")  -- Get specific config
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load required utility modules
local json_utils = require "utils.json_utils"
local file_utils = require "utils.file_utils"
local logging = require "utils.logging"

-- Initialize module logger
local logger = logging.get_logger("config")

-- Configuration storage
-- Stores all loaded configurations in memory for fast access
local configs = {}

-- Configuration file definitions
-- Maps logical configuration names to their file paths
local config_files = {
    ivr = "ivr-cc-config/ivrconfig.json",           -- IVR flow and node definitions
    webapi = "ivr-cc-config/automax_webAPIConfig.json",  -- API endpoint configurations
    extensions = "ivr-cc-config/Extensions_qa.json",     -- Agent extension mappings
    recording = "ivr-cc-config/RecordingType_qa.json"    -- Recording type definitions
}

-- Configuration last-modified timestamps
-- Used to detect file changes and trigger reloads
local config_mtimes = {}

--------------------------------------------------------------------------------
-- Load All Configurations
-- 
-- Loads all configuration files from disk or cache. If a file has been
-- modified since last load, it will be reloaded and cached.
--
-- @return boolean success - True if all configs loaded successfully
-- @return string|nil error - Error message if loading failed
--------------------------------------------------------------------------------
function M.load_all()
    logger:info("Loading all configuration files...")
    
    local scripts_path = freeswitch.getGlobalVariable("script_dir")
    local loaded_count = 0
    
    -- Iterate through all defined configuration files
    for key, file_path in pairs(config_files) do
        local full_path = scripts_path .. "/" .. file_path
        
        logger:debug(string.format("Loading configuration: %s from %s", key, full_path))
        
        -- Check if file has been modified since last load
        if not file_utils.is_modified(full_path, config_mtimes[key]) then
            logger:debug(string.format("Configuration %s is up-to-date, using cached version", key))
        else
            -- File was modified or not cached yet, load it
            local success, config_data = json_utils.load_file(full_path)
            
            if not success then
                logger:error(string.format(
                    "Failed to load configuration '%s' from %s: %s",
                    key, full_path, tostring(config_data)
                ))
                return false, "Failed to load " .. key .. " configuration"
            end
            
            -- Validate the loaded configuration
            local valid, validation_error = M.validate_config(key, config_data)
            if not valid then
                logger:error(string.format(
                    "Configuration validation failed for '%s': %s",
                    key, validation_error
                ))
                return false, "Invalid " .. key .. " configuration: " .. validation_error
            end
            
            -- Store the loaded configuration
            configs[key] = config_data
            config_mtimes[key] = file_utils.get_mtime(full_path)
            
            logger:info(string.format("Successfully loaded configuration: %s", key))
        end
        
        loaded_count = loaded_count + 1
    end
    
    logger:info(string.format("All %d configurations loaded successfully", loaded_count))
    return true, nil
end

--------------------------------------------------------------------------------
-- Get Configuration
-- 
-- Retrieves a loaded configuration by name.
--
-- @param config_name string - The name of the configuration to retrieve
-- @return table|nil - The configuration data or nil if not found
--------------------------------------------------------------------------------
function M.get(config_name)
    if not configs[config_name] then
        logger:warning(string.format("Configuration '%s' not found", config_name))
        return nil
    end
    
    return configs[config_name]
end

--------------------------------------------------------------------------------
-- Reload Configuration
-- 
-- Forces a reload of a specific configuration file, bypassing the cache.
--
-- @param config_name string - The name of the configuration to reload
-- @return boolean success - True if reload was successful
-- @return string|nil error - Error message if reload failed
--------------------------------------------------------------------------------
function M.reload(config_name)
    if not config_files[config_name] then
        return false, "Unknown configuration: " .. config_name
    end
    
    logger:info(string.format("Force reloading configuration: %s", config_name))
    
    -- Clear the cached modification time to force reload
    config_mtimes[config_name] = nil
    
    local scripts_path = freeswitch.getGlobalVariable("script_dir")
    local full_path = scripts_path .. "/" .. config_files[config_name]
    
    local success, config_data = json_utils.load_file(full_path)
    
    if not success then
        logger:error(string.format("Failed to reload configuration '%s': %s", 
            config_name, tostring(config_data)))
        return false, "Reload failed"
    end
    
    configs[config_name] = config_data
    config_mtimes[config_name] = file_utils.get_mtime(full_path)
    
    logger:info(string.format("Successfully reloaded configuration: %s", config_name))
    return true, nil
end

--------------------------------------------------------------------------------
-- Validate Configuration
-- 
-- Performs basic validation on loaded configuration data to ensure it
-- contains required fields and proper structure.
--
-- @param config_name string - The name of the configuration being validated
-- @param config_data table - The configuration data to validate
-- @return boolean valid - True if configuration is valid
-- @return string|nil error - Error message if validation failed
--------------------------------------------------------------------------------
function M.validate_config(config_name, config_data)
    if type(config_data) ~= "table" then
        return false, "Configuration must be a table/object"
    end
    
    -- Validate IVR configuration structure
    if config_name == "ivr" then
        if not config_data.IVRConfiguration then
            return false, "Missing IVRConfiguration field"
        end
        
        if not config_data.IVRConfiguration[1] then
            return false, "IVRConfiguration must contain at least one configuration"
        end
        
        if not config_data.IVRConfiguration[1].IVRProcessFlow then
            return false, "Missing IVRProcessFlow in configuration"
        end
        
        if not config_data.IVRConfiguration[1].GeneralSettingValues then
            return false, "Missing GeneralSettingValues in configuration"
        end
    end
    
    -- Validate Web API configuration structure
    if config_name == "webapi" then
        if not config_data.result then
            return false, "Missing result field in API configuration"
        end
    end
    
    -- Validate extensions configuration
    if config_name == "extensions" then
        -- Extensions config should be an array or object with extension data
        if not next(config_data) then
            logger:warning("Extensions configuration is empty")
        end
    end
    
    -- All validations passed
    return true, nil
end

--------------------------------------------------------------------------------
-- Get IVR Flow Data
-- 
-- Convenience function to get the IVR process flow configuration directly.
--
-- @return table|nil - The IVR process flow array or nil if not loaded
--------------------------------------------------------------------------------
function M.get_ivr_flow()
    local ivr_config = M.get("ivr")
    if ivr_config and ivr_config.IVRConfiguration and 
       ivr_config.IVRConfiguration[1] then
        return ivr_config.IVRConfiguration[1].IVRProcessFlow
    end
    return nil
end

--------------------------------------------------------------------------------
-- Get General Settings
-- 
-- Convenience function to get the general IVR settings.
--
-- @return table|nil - The general settings object or nil if not loaded
--------------------------------------------------------------------------------
function M.get_general_settings()
    local ivr_config = M.get("ivr")
    if ivr_config and ivr_config.IVRConfiguration and 
       ivr_config.IVRConfiguration[1] then
        return ivr_config.IVRConfiguration[1].GeneralSettingValues
    end
    return nil
end

--------------------------------------------------------------------------------
-- Get Web API Endpoints
--
-- Convenience function to get the web API endpoint configurations.
--
-- @return table|nil - The API endpoints configuration or nil if not loaded
--------------------------------------------------------------------------------
function M.get_webapi_endpoints()
    local webapi_config = M.get("webapi")
    if webapi_config and webapi_config.result then
        return webapi_config.result
    end
    return nil
end

--------------------------------------------------------------------------------
-- Get Recording Configuration
--
-- Convenience function to get the recording type configurations.
--
-- @return table|nil - The recording configuration or nil if not loaded
--------------------------------------------------------------------------------
function M.get_recording_config()
    return M.get("recording")
end

--------------------------------------------------------------------------------
-- Get Agent Extensions
--
-- Convenience function to get the agent extension configurations.
--
-- @return table|nil - The extensions configuration or nil if not loaded
--------------------------------------------------------------------------------
function M.get_agent_extensions()
    return M.get("extensions")
end

return M
