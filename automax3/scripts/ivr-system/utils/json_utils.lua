--------------------------------------------------------------------------------
-- JSON Utilities Module
-- 
-- Provides JSON parsing and encoding utilities with error handling and
-- file I/O support.
--
-- Features:
-- - JSON parsing with error handling
-- - JSON encoding
-- - Load JSON from files
-- - Save JSON to files
-- - Pretty printing JSON
--
-- Dependencies:
-- - lunajson library (should be available in FreeSWITCH Lua environment)
--
-- Usage:
--   local json_utils = require "utils.json_utils"
--   local success, data = json_utils.load_file("/path/to/file.json")
--   local json_string = json_utils.encode(data, true)  -- true for pretty print
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load the JSON library
local json = require "lunajson"

-- Load logging utility
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("json_utils")

--------------------------------------------------------------------------------
-- Decode JSON String
-- 
-- Parses a JSON string into a Lua table with comprehensive error handling.
--
-- @param json_string string - The JSON string to parse
-- @return boolean success - True if parsing was successful
-- @return table|string result - The parsed data on success, error message on failure
--------------------------------------------------------------------------------
function M.decode(json_string)
    if not json_string or json_string == "" then
        logger:warning("JSON decode called with empty or nil string")
        return false, "JSON string is empty or nil"
    end

    -- Log basic info about the input
    logger:debug(string.format("Attempting to decode JSON (length: %d)", #json_string))

    -- Attempt to decode the JSON
    local success, result = pcall(function()
        return json.decode(json_string)
    end)

    if not success then
        logger:error(string.format("[ERROR] JSON decode failed: %s", tostring(result)))
        logger:error(string.format("[ERROR] JSON string length: %d", #json_string))
        logger:error(string.format("[ERROR] First 500 chars: %s", json_string:sub(1, 500)))

        -- Log hex dump of first 50 bytes for debugging encoding issues
        local hex_dump = ""
        for i = 1, math.min(50, #json_string) do
            hex_dump = hex_dump .. string.format("%02X ", string.byte(json_string, i))
            if i % 16 == 0 then
                hex_dump = hex_dump .. "\n"
            end
        end
        logger:error(string.format("[ERROR] Hex dump (first 50 bytes):\n%s", hex_dump))

        return false, "JSON decode error: " .. tostring(result)
    end

    logger:debug("JSON decode successful")
    return true, result
end

--------------------------------------------------------------------------------
-- Encode Lua Table to JSON
-- 
-- Converts a Lua table to a JSON string.
--
-- @param data table - The Lua table to encode
-- @param pretty boolean - Whether to pretty-print the JSON (default: false)
-- @return boolean success - True if encoding was successful
-- @return string result - The JSON string on success, error message on failure
--------------------------------------------------------------------------------
function M.encode(data, pretty)
    if not data then
        return false, "Data is nil"
    end
    
    if type(data) ~= "table" then
        return false, "Data must be a table"
    end
    
    -- Attempt to encode to JSON
    local success, result = pcall(function()
        if pretty then
            -- Pretty print with indentation
            return json.encode(data, {indent = true})
        else
            return json.encode(data)
        end
    end)
    
    if not success then
        logger:error(string.format("JSON encode failed: %s", tostring(result)))
        return false, "JSON encode error: " .. tostring(result)
    end
    
    return true, result
end

--------------------------------------------------------------------------------
-- Load JSON from File
-- 
-- Reads a JSON file and parses its contents into a Lua table.
--
-- @param file_path string - The path to the JSON file
-- @return boolean success - True if loading was successful
-- @return table|string result - The parsed data on success, error message on failure
--------------------------------------------------------------------------------
function M.load_file(file_path)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    logger:debug(string.format("Loading JSON file: %s", file_path))
    
    -- Open the file for reading
    local file, open_error = io.open(file_path, "r")
    
    if not file then
        logger:error(string.format("Failed to open file %s: %s", 
            file_path, tostring(open_error)))
        return false, "Failed to open file: " .. tostring(open_error)
    end
    
    -- Read the entire file content
    local content = file:read("*a")
    file:close()
    
    if not content or content == "" then
        logger:error(string.format("File is empty: %s", file_path))
        return false, "File is empty"
    end
    
    logger:debug(string.format("Read %d bytes from file", #content))
    
    -- Parse the JSON content
    local success, result = M.decode(content)
    
    if not success then
        return false, "Failed to parse JSON from file: " .. tostring(result)
    end
    
    logger:debug(string.format("Successfully loaded JSON from file: %s", file_path))
    return true, result
end

--------------------------------------------------------------------------------
-- Save JSON to File
-- 
-- Encodes a Lua table to JSON and writes it to a file.
--
-- @param file_path string - The path where the file should be saved
-- @param data table - The data to encode and save
-- @param pretty boolean - Whether to pretty-print the JSON (default: true)
-- @return boolean success - True if saving was successful
-- @return string|nil error - Error message on failure
--------------------------------------------------------------------------------
function M.save_file(file_path, data, pretty)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    if pretty == nil then
        pretty = true  -- Default to pretty printing
    end
    
    logger:debug(string.format("Saving JSON to file: %s", file_path))
    
    -- Encode the data to JSON
    local encode_success, json_string = M.encode(data, pretty)
    
    if not encode_success then
        return false, "Failed to encode data: " .. tostring(json_string)
    end
    
    -- Open the file for writing
    local file, open_error = io.open(file_path, "w")
    
    if not file then
        logger:error(string.format("Failed to open file for writing %s: %s", 
            file_path, tostring(open_error)))
        return false, "Failed to open file for writing: " .. tostring(open_error)
    end
    
    -- Write the JSON string to the file
    file:write(json_string)
    file:close()
    
    logger:debug(string.format("Successfully saved JSON to file: %s", file_path))
    return true, nil
end

--------------------------------------------------------------------------------
-- Validate JSON String
-- 
-- Checks if a string is valid JSON without fully parsing it.
--
-- @param json_string string - The JSON string to validate
-- @return boolean valid - True if the string is valid JSON
-- @return string|nil error - Error message if invalid
--------------------------------------------------------------------------------
function M.is_valid(json_string)
    if not json_string or json_string == "" then
        return false, "JSON string is empty or nil"
    end
    
    local success, result = M.decode(json_string)
    
    if success then
        return true, nil
    else
        return false, result
    end
end

--------------------------------------------------------------------------------
-- Deep Copy
-- 
-- Creates a deep copy of a Lua table by encoding to JSON and decoding back.
-- Note: This only works for JSON-serializable data.
--
-- @param data table - The table to copy
-- @return table|nil - A deep copy of the table, or nil on error
--------------------------------------------------------------------------------
function M.deep_copy(data)
    if type(data) ~= "table" then
        return data  -- Primitive types don't need copying
    end
    
    -- Encode to JSON
    local encode_success, json_string = M.encode(data)
    
    if not encode_success then
        logger:error("Failed to encode data for deep copy")
        return nil
    end
    
    -- Decode back to create a new table
    local decode_success, copied_data = M.decode(json_string)
    
    if not decode_success then
        logger:error("Failed to decode data for deep copy")
        return nil
    end
    
    return copied_data
end

--------------------------------------------------------------------------------
-- Merge Tables
-- 
-- Merges two Lua tables, with values from the second table taking precedence.
-- Only works for simple key-value pairs.
--
-- @param table1 table - The first table
-- @param table2 table - The second table (takes precedence)
-- @return table - The merged table
--------------------------------------------------------------------------------
function M.merge(table1, table2)
    local result = {}
    
    -- Copy all entries from table1
    if table1 then
        for k, v in pairs(table1) do
            result[k] = v
        end
    end
    
    -- Override with entries from table2
    if table2 then
        for k, v in pairs(table2) do
            result[k] = v
        end
    end
    
    return result
end

return M
