--------------------------------------------------------------------------------
-- Operation Dispatcher Module
-- 
-- Central dispatcher that routes IVR operation codes to their corresponding
-- handler modules. This provides a clean separation between the call flow
-- logic and the specific operation implementations.
--
-- Operation Code Categories:
-- - 10, 11, 30, 31, 50: Audio playback operations
-- - 20, 105: Input collection operations
-- - 40, 341: Recording operations
-- - 100, 101, 107, 108: Transfer operations
-- - 111, 112, 222: API integration operations
-- - 120: Logic/conditional operations
-- - 200: Call termination
-- - 330, 331: Text-to-speech operations
--
-- Usage:
--   local dispatcher = require "core.operation_dispatcher"
--   dispatcher.execute(operation_code, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load operation modules (lazy loading for performance)
local operations = {
    audio = nil,       -- Operations 10, 11, 30, 31, 50
    input = nil,       -- Operations 20, 105
    recording = nil,   -- Operations 40, 341
    transfer = nil,    -- Operations 100, 101, 107, 108
    api = nil,         -- Operations 111, 112,113
    logic = nil,       -- Operation 120
    termination = nil, -- Operation 200
    tts = nil          -- Operations 330, 331
}

-- Operation code to module mapping
local operation_map = {
    [10] = "audio",     -- Play audio file
    [11] = "audio",     -- Play recorded file
    [20] = "input",     -- Get DTMF input
    [30] = "audio",     -- Play audio and get DTMF
    [31] = "audio",     -- Play audio with menu options
    [40] = "recording", -- Record caller message
    [50] = "audio",     -- Play number sequence
    [100] = "transfer", -- Transfer to extension
    [101] = "transfer", -- Transfer to call center queue
    [105] = "input",    -- Get multi-digit input
    [107] = "transfer", -- Blind transfer
    [108] = "transfer", -- Attended transfer
    [111] = "api",      -- API GET request
    [112] = "api",      -- API GET request
    [113] = "api",      -- API POST request
    [120] = "logic",    -- Conditional logic/branching
    [200] = "termination", -- Terminate call
    [222] = "api",      -- API query creation/authentication
    [330] = "tts",      -- Text-to-speech
    [331] = "tts",      -- Text-to-speech with input
    [341] = "recording" -- Record with options
}

-- Load utilities
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("operation_dispatcher")

-- Statistics tracking
local operation_stats = {
    total_operations = 0,
    operations_by_code = {},
    failed_operations = 0
}

--------------------------------------------------------------------------------
-- Load Operation Module
-- 
-- Lazy loads an operation module when first needed. This improves startup
-- time by only loading modules that are actually used.
--
-- @param module_name string - The name of the operation module to load
-- @return table - The loaded operation module
--------------------------------------------------------------------------------
local function load_operation_module(module_name)
    if not operations[module_name] then
        logger:debug(string.format("Loading operation module: %s", module_name))
        
        local success, module = pcall(require, "operations." .. module_name)
        
        if not success then
            logger:error(string.format(
                "Failed to load operation module '%s': %s",
                module_name, tostring(module)
            ))
            error("Failed to load operation module: " .. module_name)
        end
        
        operations[module_name] = module
        logger:debug(string.format("Successfully loaded module: %s", module_name))
    end
    
    return operations[module_name]
end

--------------------------------------------------------------------------------
-- Execute Operation
-- 
-- Dispatches an operation code to its corresponding handler module.
--
-- Flow:
-- 1. Validate operation code
-- 2. Map operation code to module name
-- 3. Load the operation module (if not already loaded)
-- 4. Call the module's execute function with the operation code and node data
-- 5. Track statistics and handle errors
--
-- @param operation_code number - The operation code to execute (10, 20, etc.)
-- @param node_data table - The IVR node configuration data
-- @return boolean success - True if operation executed successfully
-- @return any result - Result data from the operation (if any)
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    -- Update statistics
    operation_stats.total_operations = operation_stats.total_operations + 1
    operation_stats.operations_by_code[operation_code] = 
        (operation_stats.operations_by_code[operation_code] or 0) + 1
    
    logger:info(string.format(
        "Dispatching operation %d for node %d (%s)",
        operation_code,
        node_data.NodeId or "unknown",
        node_data.NodeName or "unnamed"
    ))
    
    -- Validate operation code
    if not operation_map[operation_code] then
        logger:error(string.format(
            "Unknown operation code: %d - No handler configured",
            operation_code
        ))
        
        operation_stats.failed_operations = operation_stats.failed_operations + 1
        error(string.format("Unknown operation code: %d", operation_code))
    end
    
    -- Get the module name for this operation
    local module_name = operation_map[operation_code]
    
    -- Load the operation module
    local operation_module = load_operation_module(module_name)
    
    -- Execute the operation with error handling
    local success, result = pcall(function()
        return operation_module.execute(operation_code, node_data)
    end)
    
    if not success then
        logger:error(string.format(
            "Operation %d execution failed: %s",
            operation_code, tostring(result)
        ))
        
        operation_stats.failed_operations = operation_stats.failed_operations + 1
        error(string.format("Operation execution failed: %s", tostring(result)))
    end
    
    logger:debug(string.format("Operation %d completed successfully", operation_code))
    return true, result
end

--------------------------------------------------------------------------------
-- Register Custom Operation
-- 
-- Allows registration of custom operation handlers at runtime.
-- Useful for extending the system with new operation types.
--
-- @param operation_code number - The operation code to register
-- @param module_name string - The module name that handles this operation
-- @return boolean success - True if registration was successful
--------------------------------------------------------------------------------
function M.register_operation(operation_code, module_name)
    if operation_map[operation_code] then
        logger:warning(string.format(
            "Operation code %d already registered, overwriting with module '%s'",
            operation_code, module_name
        ))
    end
    
    operation_map[operation_code] = module_name
    
    logger:info(string.format(
        "Registered operation code %d -> module '%s'",
        operation_code, module_name
    ))
    
    return true
end

--------------------------------------------------------------------------------
-- Get Operation Statistics
-- 
-- Returns statistics about operation execution including total operations,
-- operations by code, and failure count.
--
-- @return table - Statistics data
--------------------------------------------------------------------------------
function M.get_statistics()
    return {
        total_operations = operation_stats.total_operations,
        operations_by_code = operation_stats.operations_by_code,
        failed_operations = operation_stats.failed_operations,
        success_rate = operation_stats.total_operations > 0 and
            (1 - (operation_stats.failed_operations / operation_stats.total_operations)) * 100
            or 0
    }
end

--------------------------------------------------------------------------------
-- Reset Statistics
-- 
-- Resets all operation execution statistics.
--
-- @return void
--------------------------------------------------------------------------------
function M.reset_statistics()
    logger:info("Resetting operation statistics")
    
    operation_stats = {
        total_operations = 0,
        operations_by_code = {},
        failed_operations = 0
    }
end

--------------------------------------------------------------------------------
-- List Available Operations
-- 
-- Returns a list of all registered operation codes and their module handlers.
--
-- @return table - Map of operation codes to module names
--------------------------------------------------------------------------------
function M.list_operations()
    return operation_map
end

--------------------------------------------------------------------------------
-- Is Operation Supported
-- 
-- Checks if a given operation code is supported by the dispatcher.
--
-- @param operation_code number - The operation code to check
-- @return boolean - True if the operation is supported
--------------------------------------------------------------------------------
function M.is_operation_supported(operation_code)
    return operation_map[operation_code] ~= nil
end

return M
