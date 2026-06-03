#!/usr/bin/env lua


-- ============================================
-- MUST BE FIRST THING in main.lua
-- ============================================
--------------------------------------------------------------------------------
-- IVR System Main Entry Point
-- 
-- This is the main entry point for the FreeSWITCH IVR (Interactive Voice 
-- Response) system. It initializes the package system, loads configurations,
-- and starts the call flow processing.
--
-- Usage:
--   Called directly by FreeSWITCH when a call enters the IVR system
--
-- Dependencies:
--   - FreeSWITCH Lua environment
--   - All core, config, and service modules
--
-- Author: IVR System Team
-- Version: 2.0.0
-- Last Modified: 2025-01-28
--------------------------------------------------------------------------------

-- Setup package path to include our custom modules
local scripts_path = freeswitch.getGlobalVariable("script_dir")
package.path = scripts_path .. "/ivr-system/?.lua;" .. 
               scripts_path .. "/ivr-system/?/init.lua;" .. 
               package.path

-- Load core system modules
local core = require "core"
local config = require "config"
local utils = require "utils"

--------------------------------------------------------------------------------
-- Main initialization and execution function
-- 
-- This function orchestrates the entire IVR system startup:
-- 1. Validates the FreeSWITCH session
-- 2. Loads all configuration files
-- 3. Initializes core services
-- 4. Starts the call flow
--
-- @return void
--------------------------------------------------------------------------------
local function main()
    -- Get logger instance for main module
    local logger = utils.logging.get_logger("main")
    
    logger:info("=== IVR System Starting ===")
    logger:info("Scripts path: " .. scripts_path)
    
    -- Validate that the FreeSWITCH session is ready
    if not session:ready() then
        logger:error("Session is not ready - cannot process call")
        return
    end
    
    -- Log basic call information for debugging
    local call_uuid = session:getVariable("uuid")
    local caller_id = session:getVariable("caller_id_number")
    local domain = session:getVariable("domain_name")
    
    logger:info(string.format(
        "Processing call - UUID: %s, Caller: %s, Domain: %s",
        call_uuid or "unknown",
        caller_id or "unknown",
        domain or "unknown"
    ))
    
    -- Load all configuration files (IVR config, API config, extensions, etc.)
    logger:info("Loading configuration files...")
    local config_success, config_error = config.load_all()
    
    if not config_success then
        logger:error("Failed to load configuration: " .. tostring(config_error))
        session:hangup()
        return
    end
    
    logger:info("Configuration loaded successfully")
    
    -- Initialize core system components
    logger:info("Initializing core system...")
    local init_success, init_error = core.initialize(session)
    
    if not init_success then
        logger:error("Failed to initialize core system: " .. tostring(init_error))
        session:hangup()
        return
    end
    
    logger:info("Core system initialized successfully")
    
    -- Check if this is a call center agent callback scenario
    if session:answered() and session:getVariable("cc_last_nodeId") ~= nil then
        logger:info("Detected call center agent callback scenario")
        core.call_flow.handle_agent_callback()
        return
    end
    
    -- Start the main call flow processing
    logger:info("Starting call flow processing...")
    core.call_flow.start()
    
    logger:info("=== IVR System Complete ===")
end

--------------------------------------------------------------------------------
-- Error Handler Wrapper
-- 
-- Wraps the main execution in a protected call (pcall) to catch any 
-- unexpected errors and log them appropriately.
--------------------------------------------------------------------------------
local function execute_with_error_handling()
    local success, error_msg = pcall(main)
    
    if not success then
        -- Log the error using FreeSWITCH's console logger
        freeswitch.consoleLog("err", 
            "FATAL ERROR in IVR System: " .. tostring(error_msg) .. "\n")
        
        -- Attempt to gracefully terminate the call
        if session and session:ready() then
            session:hangup()
        end
    end
end

-- Execute the main function with error handling
execute_with_error_handling()
