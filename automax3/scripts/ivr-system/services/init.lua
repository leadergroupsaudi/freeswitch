--------------------------------------------------------------------------------
-- Services Module Loader
-- 
-- Provides initialization and access to all service layer modules including:
-- - HTTP client for API calls
-- - Cache manager for performance optimization
-- - Attachment service for file uploads
-- - Incident service for incident management
-- - Authentication service for token management
--
-- Services provide cross-cutting concerns that are used by multiple
-- operation modules.
--
-- Usage:
--   local services = require "services"
--   services.initialize()
--   local http = services.http_client
--   local response = http.request({url = "https://api.example.com"})
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load logging utility
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("services")

-- Service initialization state
M.initialized = false

-- Lazy-loaded service modules
M.http_client = nil
M.cache_manager = nil
M.attachment_service = nil
M.incident_service = nil
M.auth_service = nil

--------------------------------------------------------------------------------
-- Initialize Services
-- 
-- Initializes all service layer components. Should be called once during
-- system startup.
--
-- @return boolean success - True if initialization was successful
-- @return string|nil error - Error message if initialization failed
--------------------------------------------------------------------------------
function M.initialize()
    if M.initialized then
        logger:info("Services already initialized")
        return true, nil
    end
    
    logger:info("Initializing service layer...")
    
    -- Initialize services (lazy loading - only loaded when first accessed)
    logger:debug("Service layer ready for lazy loading")
    
    M.initialized = true
    
    logger:info("Service layer initialization complete")
    return true, nil
end

--------------------------------------------------------------------------------
-- Get HTTP Client
-- 
-- Returns the HTTP client service (lazy loads if not already loaded).
--
-- @return table - The HTTP client service
--------------------------------------------------------------------------------
function M.get_http_client()
    if not M.http_client then
        logger:debug("Loading HTTP client service")
        M.http_client = require "services.http_client"
    end
    return M.http_client
end

--------------------------------------------------------------------------------
-- Get Cache Manager
-- 
-- Returns the cache manager service (lazy loads if not already loaded).
--
-- @return table - The cache manager service
--------------------------------------------------------------------------------
function M.get_cache_manager()
    if not M.cache_manager then
        logger:debug("Loading cache manager service")
        M.cache_manager = require "services.cache_manager"
    end
    return M.cache_manager
end

--------------------------------------------------------------------------------
-- Get Attachment Service
-- 
-- Returns the attachment service (lazy loads if not already loaded).
--
-- @return table - The attachment service
--------------------------------------------------------------------------------
function M.get_attachment_service()
    if not M.attachment_service then
        logger:debug("Loading attachment service")
        M.attachment_service = require "services.attachment_service"
    end
    return M.attachment_service
end

--------------------------------------------------------------------------------
-- Get Incident Service
-- 
-- Returns the incident service (lazy loads if not already loaded).
--
-- @return table - The incident service
--------------------------------------------------------------------------------
function M.get_incident_service()
    if not M.incident_service then
        logger:debug("Loading incident service")
        M.incident_service = require "services.incident_service"
    end
    return M.incident_service
end

--------------------------------------------------------------------------------
-- Get Authentication Service
-- 
-- Returns the authentication service (lazy loads if not already loaded).
--
-- @return table - The authentication service
--------------------------------------------------------------------------------
function M.get_auth_service()
    if not M.auth_service then
        logger:debug("Loading authentication service")
        M.auth_service = require "services.auth_service"
    end
    return M.auth_service
end

--------------------------------------------------------------------------------
-- Cleanup Services
-- 
-- Performs cleanup of all service layer components.
--
-- @return void
--------------------------------------------------------------------------------
function M.cleanup()
    logger:info("Cleaning up service layer")
    
    -- Call cleanup on any loaded services
    if M.cache_manager and M.cache_manager.cleanup then
        M.cache_manager.cleanup()
    end
    
    if M.http_client and M.http_client.cleanup then
        M.http_client.cleanup()
    end
    
    -- Reset state
    M.initialized = false
    M.http_client = nil
    M.cache_manager = nil
    M.attachment_service = nil
    M.incident_service = nil
    M.auth_service = nil
    
    logger:info("Service layer cleanup complete")
end

return M
