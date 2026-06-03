--------------------------------------------------------------------------------
-- Core System Module
-- 
-- Provides core system initialization and management functionality for the
-- IVR system. This module acts as the central coordinator for all core
-- services and components.
--
-- Components initialized:
-- - Session manager (call session state management)
-- - Call flow engine (IVR navigation logic)
-- - Operation dispatcher (routes operation codes to handlers)
-- - Service layer (HTTP, caching, authentication)
--
-- Usage:
--   local core = require "core"
--   core.initialize(session)
--   core.call_flow.start()
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load core sub-modules
local session_manager = require "core.session_manager"
local call_flow = require "core.call_flow"
local operation_dispatcher = require "core.operation_dispatcher"

-- Load service layer
local services = require "services"

-- Load utilities
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("core")

-- Store reference to the FreeSWITCH session
M.session = nil

-- System initialization state
M.initialized = false

--------------------------------------------------------------------------------
-- Initialize Core System
-- 
-- Initializes all core system components and services. Must be called before
-- any IVR operations can be performed.
--
-- Initialization steps:
-- 1. Store session reference
-- 2. Initialize session manager
-- 3. Initialize service layer
-- 4. Validate system readiness
--
-- @param freeswitch_session object - The FreeSWITCH session object
-- @return boolean success - True if initialization was successful
-- @return string|nil error - Error message if initialization failed
--------------------------------------------------------------------------------
function M.initialize(freeswitch_session)
    if M.initialized then
        logger:warning("Core system already initialized, skipping re-initialization")
        return true, nil
    end
    
    logger:info("Initializing core system...")
    
    -- Validate session parameter
    if not freeswitch_session then
        return false, "FreeSWITCH session is required"
    end
    
    -- Store session reference for global access
    M.session = freeswitch_session
    
    -- Initialize session manager with the FreeSWITCH session
    logger:debug("Initializing session manager...")
    local session_init_success, session_error = session_manager.initialize(freeswitch_session)
    if not session_init_success then
        return false, "Session manager initialization failed: " .. tostring(session_error)
    end
    
    -- Initialize service layer (HTTP client, cache, authentication, etc.)
    logger:debug("Initializing service layer...")
    local services_init_success, services_error = services.initialize()
    if not services_init_success then
        return false, "Services initialization failed: " .. tostring(services_error)
    end
    
    -- Initialize call flow engine
    logger:debug("Initializing call flow engine...")
    call_flow.initialize()
    
    -- Mark system as initialized
    M.initialized = true
    
    logger:info("Core system initialization complete")
    return true, nil
end

--------------------------------------------------------------------------------
-- Shutdown Core System
-- 
-- Performs cleanup and graceful shutdown of all core components.
-- Should be called before the script terminates.
--
-- @return void
--------------------------------------------------------------------------------
function M.shutdown()
    if not M.initialized then
        logger:debug("Core system not initialized, skipping shutdown")
        return
    end
    
    logger:info("Shutting down core system...")
    
    -- Perform cleanup operations
    session_manager.cleanup()
    services.cleanup()
    
    M.initialized = false
    M.session = nil
    
    logger:info("Core system shutdown complete")
end

--------------------------------------------------------------------------------
-- Get Current Session
-- 
-- Retrieves the current FreeSWITCH session object.
--
-- @return object|nil - The FreeSWITCH session or nil if not initialized
--------------------------------------------------------------------------------
function M.get_session()
    return M.session
end

-- Export sub-modules for direct access
M.session_manager = session_manager
M.call_flow = call_flow
M.operation_dispatcher = operation_dispatcher

return M
