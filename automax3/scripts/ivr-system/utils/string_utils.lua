--------------------------------------------------------------------------------
-- String Utilities Module
-- 
-- Provides string manipulation and escaping functions for safe handling of
-- user input and shell commands.
--
-- Features:
-- - Shell command escaping (for curl and other shell commands)
-- - SQL escaping (if needed)
-- - URL encoding
-- - String trimming and normalization
-- - String splitting and joining
--
-- Usage:
--   local string_utils = require "utils.string_utils"
--   local safe_input = string_utils.shell_escape(user_input)
--   local trimmed = string_utils.trim(input_string)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

--------------------------------------------------------------------------------
-- Shell Escape
-- 
-- Escapes a string for safe use in shell commands. This is CRITICAL for
-- security when building commands with user input.
--
-- The function wraps the string in single quotes and escapes any single
-- quotes within the string using the '\'' technique.
--
-- Example:
--   shell_escape("test's input") -> 'test'\''s input'
--
-- @param str string - The string to escape
-- @return string - The shell-safe escaped string
--------------------------------------------------------------------------------
function M.shell_escape(str)
    if not str then
        return "''"
    end
    
    -- Convert to string if not already
    str = tostring(str)
    
    -- Escape single quotes by replacing them with '\''
    -- This closes the quote, adds an escaped quote, then reopens the quote
    str = str:gsub("'", "'\"'\"'")
    
    -- Wrap the entire string in single quotes
    return "'" .. str .. "'"
end

--------------------------------------------------------------------------------
-- Trim Whitespace
-- 
-- Removes leading and trailing whitespace from a string.
--
-- @param str string - The string to trim
-- @return string - The trimmed string
--------------------------------------------------------------------------------
function M.trim(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    
    -- Remove leading and trailing whitespace
    return str:match("^%s*(.-)%s*$")
end

--------------------------------------------------------------------------------
-- Split String
-- 
-- Splits a string into an array of substrings based on a delimiter.
--
-- @param str string - The string to split
-- @param delimiter string - The delimiter to split on (default: ",")
-- @return table - Array of substrings
--------------------------------------------------------------------------------
function M.split(str, delimiter)
    if not str then
        return {}
    end
    
    str = tostring(str)
    delimiter = delimiter or ","
    
    local result = {}
    local pattern = string.format("([^%s]+)", delimiter)
    
    for match in str:gmatch(pattern) do
        table.insert(result, match)
    end
    
    return result
end

--------------------------------------------------------------------------------
-- Join Strings
-- 
-- Joins an array of strings with a delimiter.
--
-- @param strings table - Array of strings to join
-- @param delimiter string - The delimiter to use (default: ",")
-- @return string - The joined string
--------------------------------------------------------------------------------
function M.join(strings, delimiter)
    if not strings or type(strings) ~= "table" then
        return ""
    end
    
    delimiter = delimiter or ","
    
    return table.concat(strings, delimiter)
end

--------------------------------------------------------------------------------
-- URL Encode
-- 
-- Encodes a string for safe use in URLs by percent-encoding special
-- characters.
--
-- @param str string - The string to encode
-- @return string - The URL-encoded string
--------------------------------------------------------------------------------
function M.url_encode(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    
    -- Replace special characters with their percent-encoded equivalents
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    
    return str
end

--------------------------------------------------------------------------------
-- URL Decode
-- 
-- Decodes a percent-encoded URL string.
--
-- @param str string - The URL-encoded string to decode
-- @return string - The decoded string
--------------------------------------------------------------------------------
function M.url_decode(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    
    -- Replace plus signs with spaces
    str = str:gsub("+", " ")
    
    -- Replace percent-encoded characters
    str = str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    
    return str
end

--------------------------------------------------------------------------------
-- SQL Escape
-- 
-- Escapes a string for safe use in SQL queries by doubling single quotes.
-- Note: Use prepared statements when possible instead of string escaping.
--
-- @param str string - The string to escape
-- @return string - The SQL-safe escaped string
--------------------------------------------------------------------------------
function M.sql_escape(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    
    -- Double any single quotes
    str = str:gsub("'", "''")
    
    return str
end

--------------------------------------------------------------------------------
-- Starts With
-- 
-- Checks if a string starts with a specific prefix.
--
-- @param str string - The string to check
-- @param prefix string - The prefix to look for
-- @return boolean - True if string starts with prefix
--------------------------------------------------------------------------------
function M.starts_with(str, prefix)
    if not str or not prefix then
        return false
    end
    
    str = tostring(str)
    prefix = tostring(prefix)
    
    return str:sub(1, #prefix) == prefix
end

--------------------------------------------------------------------------------
-- Ends With
-- 
-- Checks if a string ends with a specific suffix.
--
-- @param str string - The string to check
-- @param suffix string - The suffix to look for
-- @return boolean - True if string ends with suffix
--------------------------------------------------------------------------------
function M.ends_with(str, suffix)
    if not str or not suffix then
        return false
    end
    
    str = tostring(str)
    suffix = tostring(suffix)
    
    return suffix == "" or str:sub(-#suffix) == suffix
end

--------------------------------------------------------------------------------
-- Contains
-- 
-- Checks if a string contains a specific substring.
--
-- @param str string - The string to search in
-- @param substring string - The substring to look for
-- @return boolean - True if string contains substring
--------------------------------------------------------------------------------
function M.contains(str, substring)
    if not str or not substring then
        return false
    end
    
    str = tostring(str)
    substring = tostring(substring)
    
    return str:find(substring, 1, true) ~= nil
end

--------------------------------------------------------------------------------
-- Capitalize First Letter
-- 
-- Capitalizes the first letter of a string.
--
-- @param str string - The string to capitalize
-- @return string - The string with first letter capitalized
--------------------------------------------------------------------------------
function M.capitalize(str)
    if not str or str == "" then
        return ""
    end
    
    str = tostring(str)
    
    return str:gsub("^%l", string.upper)
end

--------------------------------------------------------------------------------
-- Is Empty or Whitespace
-- 
-- Checks if a string is nil, empty, or contains only whitespace.
--
-- @param str string - The string to check
-- @return boolean - True if string is empty or whitespace
--------------------------------------------------------------------------------
function M.is_empty_or_whitespace(str)
    if not str then
        return true
    end
    
    str = tostring(str)
    
    return str:match("^%s*$") ~= nil
end

--------------------------------------------------------------------------------
-- Pad Left
-- 
-- Pads a string to a specified length by adding characters to the left.
--
-- @param str string - The string to pad
-- @param length number - The desired total length
-- @param char string - The character to pad with (default: " ")
-- @return string - The padded string
--------------------------------------------------------------------------------
function M.pad_left(str, length, char)
    if not str then
        str = ""
    end
    
    str = tostring(str)
    char = char or " "
    
    while #str < length do
        str = char .. str
    end
    
    return str
end

--------------------------------------------------------------------------------
-- Pad Right
-- 
-- Pads a string to a specified length by adding characters to the right.
--
-- @param str string - The string to pad
-- @param length number - The desired total length
-- @param char string - The character to pad with (default: " ")
-- @return string - The padded string
--------------------------------------------------------------------------------
function M.pad_right(str, length, char)
    if not str then
        str = ""
    end
    
    str = tostring(str)
    char = char or " "
    
    while #str < length do
        str = str .. char
    end
    
    return str
end

--------------------------------------------------------------------------------
-- Remove Quotes
-- 
-- Removes surrounding quotes from a string (both single and double quotes).
--
-- @param str string - The string to process
-- @return string - The string without surrounding quotes
--------------------------------------------------------------------------------
function M.remove_quotes(str)
    if not str then
        return ""
    end
    
    str = tostring(str)
    
    -- Remove surrounding double quotes
    str = str:gsub('^"(.*)"$', '%1')
    
    -- Remove surrounding single quotes
    str = str:gsub("^'(.*)'$", '%1')
    
    return str
end

return M
