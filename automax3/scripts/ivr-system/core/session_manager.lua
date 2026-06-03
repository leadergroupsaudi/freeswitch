--------------------------------------------------------------------------------
-- Session Manager Module
-- 
-- Manages call session state, variables, and context throughout the IVR flow.
-- Provides a centralized interface for getting and setting session variables
-- with type safety and validation.
--
-- Features:
-- - Session variable management with type conversion
-- - Call context tracking (UUID, caller info, timestamps)
-- - Variable history and state tracking
-- - Automatic logging of variable changes
--
-- Usage:
--   local session_manager = require "core.session_manager"
--   session_manager.initialize(session)
--   session_manager.set_variable("customer_id", "12345")
--   local customer_id = session_manager.get_variable("customer_id")
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load utilities
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("session_manager")

-- Store reference to FreeSWITCH session
local fs_session = nil

-- Session context information
local session_context = {
    call_uuid = nil,
    caller_id = nil,
    caller_name = nil,
    domain = nil,
    call_start_time = nil,
    is_answered = false
}

-- Session variable cache for performance
-- Reduces repeated calls to session:getVariable()
local variable_cache = {}

--------------------------------------------------------------------------------
-- Initialize Session Manager
-- 
-- Initializes the session manager with a FreeSWITCH session object and
-- extracts basic call context information.
--
-- @param session object - The FreeSWITCH session object
-- @return boolean success - True if initialization was successful
-- @return string|nil error - Error message if initialization failed
--------------------------------------------------------------------------------
function M.initialize(session)
    if not session then
        return false, "Session object is required"
    end
    
    fs_session = session
    
    -- Extract and cache basic session context
    session_context.call_uuid = session:getVariable("uuid") or "unknown"
    session_context.caller_id = session:getVariable("caller_id_number") or "unknown"
    session_context.caller_name = session:getVariable("caller_id_name") or "unknown"
    session_context.domain = session:getVariable("domain_name") or "unknown"
    session_context.call_start_time = os.time()
    session_context.is_answered = session:answered()
    
    logger:info(string.format(
        "Session manager initialized - UUID: %s, Caller: %s (%s)",
        session_context.call_uuid,
        session_context.caller_id,
        session_context.caller_name
    ))
    
    return true, nil
end

--------------------------------------------------------------------------------
-- Get Session Context
-- 
-- Returns the current session context information including call UUID,
-- caller information, and timestamps.
--
-- @return table - Session context information
--------------------------------------------------------------------------------
function M.get_context()
    return session_context
end

--------------------------------------------------------------------------------
-- Get Session Variable
-- 
-- Retrieves a session variable value with optional type conversion and
-- default value support.
--
-- @param variable_name string - The name of the variable to retrieve
-- @param default_value any - Default value if variable doesn't exist (optional)
-- @param use_cache boolean - Whether to use cached value (default: true)
-- @return any - The variable value or default value
--------------------------------------------------------------------------------
function M.get_variable(variable_name, default_value, use_cache)
    if use_cache == nil then
        use_cache = true
    end
    
    -- Check cache first if caching is enabled
    if use_cache and variable_cache[variable_name] ~= nil then
        logger:debug(string.format("Retrieved cached variable: %s", variable_name))
        return variable_cache[variable_name]
    end
    
    -- Get variable from FreeSWITCH session
    if not fs_session then
        logger:warning("Session not initialized, cannot get variable: " .. variable_name)
        return default_value
    end
    
    local value = fs_session:getVariable(variable_name)
    
    -- Use default value if variable doesn't exist
    if value == nil then
        logger:debug(string.format(
            "Variable '%s' not found, using default: %s",
            variable_name, tostring(default_value)
        ))
        return default_value
    end
    
    -- Cache the value
    variable_cache[variable_name] = value
    
    logger:debug(string.format("Retrieved variable: %s = %s", variable_name, tostring(value)))
    return value
end

--------------------------------------------------------------------------------
-- Set Session Variable
-- 
-- Sets a session variable with automatic type conversion and validation.
--
-- @param variable_name string - The name of the variable to set
-- @param value any - The value to set (will be converted to string)
-- @param update_cache boolean - Whether to update the cache (default: true)
-- @return boolean success - True if variable was set successfully
--------------------------------------------------------------------------------
function M.set_variable(variable_name, value, update_cache)
    if update_cache == nil then
        update_cache = true
    end
    
    if not fs_session then
        logger:error("Session not initialized, cannot set variable: " .. variable_name)
        return false
    end
    
    -- Convert value to string for FreeSWITCH
    local string_value = tostring(value)
    
    -- Set the variable in FreeSWITCH
    fs_session:setVariable(variable_name, string_value)
    
    -- Update cache
    if update_cache then
        variable_cache[variable_name] = value
    end
    
    logger:debug(string.format("Set variable: %s = %s", variable_name, string_value))
    return true
end

--------------------------------------------------------------------------------
-- Unset Session Variable
-- 
-- Removes a session variable and clears it from the cache.
--
-- @param variable_name string - The name of the variable to unset
-- @return boolean success - True if variable was unset successfully
--------------------------------------------------------------------------------
function M.unset_variable(variable_name)
    if not fs_session then
        logger:error("Session not initialized, cannot unset variable: " .. variable_name)
        return false
    end
    
    -- Unset in FreeSWITCH
    fs_session:setVariable(variable_name, nil)
    
    -- Remove from cache
    variable_cache[variable_name] = nil
    
    logger:debug(string.format("Unset variable: %s", variable_name))
    return true
end

--------------------------------------------------------------------------------
-- Clear Variable Cache
-- 
-- Clears the session variable cache. Useful when variables may have been
-- changed externally and need to be re-read.
--
-- @return void
--------------------------------------------------------------------------------
function M.clear_cache()
    logger:debug("Clearing variable cache")
    variable_cache = {}
end

--------------------------------------------------------------------------------
-- Get Call UUID
-- 
-- Convenience function to get the current call's UUID.
--
-- @return string - The call UUID
--------------------------------------------------------------------------------
function M.get_call_uuid()
    return session_context.call_uuid
end

--------------------------------------------------------------------------------
-- Get Caller ID
-- 
-- Convenience function to get the caller's phone number.
--
-- @return string - The caller ID number
--------------------------------------------------------------------------------
function M.get_caller_id()
    return session_context.caller_id
end

--------------------------------------------------------------------------------
-- Is Session Answered
-- 
-- Checks if the call session has been answered.
--
-- @return boolean - True if the session is answered
--------------------------------------------------------------------------------
function M.is_answered()
    if fs_session then
        return fs_session:answered()
    end
    return false
end

--------------------------------------------------------------------------------
-- Is Session Ready
-- 
-- Checks if the call session is ready for operations.
--
-- @return boolean - True if the session is ready
--------------------------------------------------------------------------------
function M.is_ready()
    if fs_session then
        return fs_session:ready()
    end
    return false
end

--------------------------------------------------------------------------------
-- Get FreeSWITCH Session
-- 
-- Returns the underlying FreeSWITCH session object for direct access.
-- Use with caution - prefer using the wrapper functions when possible.
--
-- @return object|nil - The FreeSWITCH session object
--------------------------------------------------------------------------------
function M.get_freeswitch_session()
    return fs_session
end

--------------------------------------------------------------------------------
-- Cleanup
-- 
-- Performs cleanup operations when the session manager is being shut down.
--
-- @return void
--------------------------------------------------------------------------------
function M.cleanup()
    logger:debug("Cleaning up session manager")
    
    -- Clear caches
    variable_cache = {}
    
    -- Reset context
    session_context = {
        call_uuid = nil,
        caller_id = nil,
        caller_name = nil,
        domain = nil,
        call_start_time = nil,
        is_answered = false
    }
    
    fs_session = nil
end

return M
