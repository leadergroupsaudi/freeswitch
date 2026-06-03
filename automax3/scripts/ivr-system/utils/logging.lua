--------------------------------------------------------------------------------
-- Logging Utility Module
-- 
-- Provides a comprehensive logging system with support for different log
-- levels, module-specific loggers, and integration with FreeSWITCH's
-- console logging.
--
-- Features:
-- - Multiple log levels (DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL)
-- - Module-specific loggers with prefixes
-- - Conditional logging based on log level
-- - Timestamp support
-- - Structured logging format
--
-- Log Levels (in order of severity):
-- - DEBUG: Detailed diagnostic information
-- - INFO: General informational messages
-- - NOTICE: Important but normal events
-- - WARNING: Warning messages for potential issues
-- - ERROR: Error events that might still allow operation to continue
-- - CRITICAL: Critical events that require immediate attention
--
-- Usage:
--   local logging = require "utils.logging"
--   local logger = logging.get_logger("my_module")
--   logger:info("Application started")
--   logger:error("Failed to connect to database")
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Log level constants
M.LEVELS = {
    DEBUG = 1,
    INFO = 2,
    NOTICE = 3,
    WARNING = 4,
    ERROR = 5,
    CRITICAL = 6
}

-- Log level names for display
local LEVEL_NAMES = {
    [M.LEVELS.DEBUG] = "DEBUG",
    [M.LEVELS.INFO] = "INFO",
    [M.LEVELS.NOTICE] = "NOTICE",
    [M.LEVELS.WARNING] = "WARNING",
    [M.LEVELS.ERROR] = "ERROR",
    [M.LEVELS.CRITICAL] = "CRITICAL"
}

-- Global log level configuration (can be changed at runtime)
M.current_level = M.LEVELS.INFO

-- Map our log levels to FreeSWITCH console log levels
local FS_LOG_LEVELS = {
    [M.LEVELS.DEBUG] = "debug",
    [M.LEVELS.INFO] = "info",
    [M.LEVELS.NOTICE] = "notice",
    [M.LEVELS.WARNING] = "warning",
    [M.LEVELS.ERROR] = "err",
    [M.LEVELS.CRITICAL] = "crit"
}

--------------------------------------------------------------------------------
-- Logger Class
-- 
-- Represents a logger instance for a specific module.
--------------------------------------------------------------------------------
local Logger = {}
Logger.__index = Logger

--------------------------------------------------------------------------------
-- Create New Logger
-- 
-- Creates a new logger instance for a specific module.
--
-- @param module_name string - The name of the module using this logger
-- @return Logger - A new logger instance
--------------------------------------------------------------------------------
function Logger.new(module_name)
    local self = setmetatable({}, Logger)
    self.module_name = module_name or "unknown"
    return self
end

--------------------------------------------------------------------------------
-- Log Message
-- 
-- Internal method to log a message at a specific level.
--
-- @param level number - The log level (use M.LEVELS constants)
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:log(level, message)
    -- Check if this message should be logged based on current log level
    if level < M.current_level then
        return
    end
    
    -- Format the log message
    local formatted_message = string.format(
        "[%s] [%s] %s",
        LEVEL_NAMES[level],
        self.module_name,
        tostring(message)
    )
    
    -- Log to FreeSWITCH console
    local fs_level = FS_LOG_LEVELS[level] or "info"
    freeswitch.consoleLog(fs_level, formatted_message .. "\n")
end

--------------------------------------------------------------------------------
-- Debug Level Log
-- 
-- Logs a debug message. Debug messages provide detailed diagnostic
-- information useful during development.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:debug(message)
    self:log(M.LEVELS.DEBUG, message)
end

--------------------------------------------------------------------------------
-- Info Level Log
-- 
-- Logs an informational message. Info messages provide general information
-- about the application's operation.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:info(message)
    self:log(M.LEVELS.INFO, message)
end

--------------------------------------------------------------------------------
-- Notice Level Log
-- 
-- Logs a notice message. Notices are important but normal events that
-- should be noted.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:notice(message)
    self:log(M.LEVELS.NOTICE, message)
end

--------------------------------------------------------------------------------
-- Warning Level Log
-- 
-- Logs a warning message. Warnings indicate potential issues that don't
-- prevent operation but should be investigated.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:warning(message)
    self:log(M.LEVELS.WARNING, message)
end

--------------------------------------------------------------------------------
-- Error Level Log
-- 
-- Logs an error message. Errors are events that indicate a failure but
-- may allow the application to continue operating.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:error(message)
    self:log(M.LEVELS.ERROR, message)
end

--------------------------------------------------------------------------------
-- Critical Level Log
-- 
-- Logs a critical message. Critical messages indicate severe errors that
-- require immediate attention.
--
-- @param message string - The message to log
-- @return void
--------------------------------------------------------------------------------
function Logger:critical(message)
    self:log(M.LEVELS.CRITICAL, message)
end

--------------------------------------------------------------------------------
-- Log with Data
-- 
-- Logs a message along with structured data. The data is formatted and
-- included in the log output.
--
-- @param level number - The log level
-- @param message string - The message to log
-- @param data table - Additional structured data to log
-- @return void
--------------------------------------------------------------------------------
function Logger:log_with_data(level, message, data)
    local full_message = message
    
    if data then
        local data_str = M.format_data(data)
        full_message = message .. " | Data: " .. data_str
    end
    
    self:log(level, full_message)
end

--------------------------------------------------------------------------------
-- Get Logger
-- 
-- Factory function to create or retrieve a logger for a specific module.
--
-- @param module_name string - The name of the module
-- @return Logger - A logger instance for the module
--------------------------------------------------------------------------------
function M.get_logger(module_name)
    return Logger.new(module_name)
end

--------------------------------------------------------------------------------
-- Set Global Log Level
-- 
-- Changes the global log level. Messages below this level will not be logged.
--
-- @param level number - The new log level (use M.LEVELS constants)
-- @return void
--------------------------------------------------------------------------------
function M.set_level(level)
    if not LEVEL_NAMES[level] then
        error("Invalid log level: " .. tostring(level))
    end
    
    M.current_level = level
    
    freeswitch.consoleLog("info", string.format(
        "[LOGGING] Log level changed to %s\n",
        LEVEL_NAMES[level]
    ))
end

--------------------------------------------------------------------------------
-- Format Data
-- 
-- Formats a Lua table into a readable string for logging.
--
-- @param data table - The data to format
-- @param indent string - Current indentation level (for recursion)
-- @param max_depth number - Maximum recursion depth (default: 3)
-- @param current_depth number - Current recursion depth (for internal use)
-- @return string - Formatted string representation of the data
--------------------------------------------------------------------------------
function M.format_data(data, indent, max_depth, current_depth)
    indent = indent or ""
    max_depth = max_depth or 3
    current_depth = current_depth or 0
    
    if current_depth >= max_depth then
        return tostring(data)
    end
    
    if type(data) ~= "table" then
        return tostring(data)
    end
    
    local parts = {}
    
    for key, value in pairs(data) do
        local key_str = tostring(key)
        local value_str
        
        if type(value) == "table" then
            value_str = M.format_data(
                value, 
                indent .. "  ", 
                max_depth, 
                current_depth + 1
            )
        else
            value_str = tostring(value)
        end
        
        table.insert(parts, string.format("%s%s = %s", indent, key_str, value_str))
    end
    
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end

--------------------------------------------------------------------------------
-- Log Function Call
-- 
-- Utility function to log function entry with parameters.
--
-- @param logger Logger - The logger instance
-- @param function_name string - Name of the function being called
-- @param params table - Function parameters
-- @return void
--------------------------------------------------------------------------------
function M.log_function_call(logger, function_name, params)
    local message = string.format("Entering function: %s", function_name)
    
    if params then
        logger:log_with_data(M.LEVELS.DEBUG, message, params)
    else
        logger:debug(message)
    end
end

return M
