--------------------------------------------------------------------------------
-- File Utilities Module
-- 
-- Provides file system operations and validation utilities including:
-- - File existence checks
-- - File size validation
-- - File modification time tracking
-- - Directory operations
-- - File path manipulation
--
-- Usage:
--   local file_utils = require "utils.file_utils"
--   if file_utils.exists("/path/to/file") then
--       local size = file_utils.get_size("/path/to/file")
--   end
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load logging utility
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("file_utils")

-- Cache for file modification times
local mtime_cache = {}

--------------------------------------------------------------------------------
-- Check if File Exists
-- 
-- Checks whether a file exists and is accessible.
--
-- @param file_path string - The path to the file to check
-- @return boolean - True if the file exists and is readable
--------------------------------------------------------------------------------
function M.exists(file_path)
    if not file_path or file_path == "" then
        return false
    end
    
    local file = io.open(file_path, "r")
    
    if file then
        file:close()
        return true
    end
    
    return false
end

--------------------------------------------------------------------------------
-- Get File Size
-- 
-- Returns the size of a file in bytes.
--
-- @param file_path string - The path to the file
-- @return number|nil size - The file size in bytes, or nil if file not found
-- @return string|nil error - Error message if file couldn't be accessed
--------------------------------------------------------------------------------
function M.get_size(file_path)
    if not file_path or file_path == "" then
        return nil, "File path is empty or nil"
    end
    
    local file = io.open(file_path, "rb")
    
    if not file then
        return nil, "File not found or not accessible"
    end
    
    -- Seek to end of file to get size
    file:seek("end")
    local size = file:seek()
    file:close()
    
    return size, nil
end

--------------------------------------------------------------------------------
-- Check if File Has Content
-- 
-- Checks if a file has meaningful content (size above threshold).
-- Useful for validating audio files, recordings, etc.
--
-- @param file_path string - The path to the file
-- @param min_size number - Minimum size in bytes (default: 1000)
-- @return boolean has_content - True if file has content above threshold
-- @return number size - The actual file size
--------------------------------------------------------------------------------
function M.has_content(file_path, min_size)
    min_size = min_size or 1000  -- Default 1KB minimum
    
    local size, error_msg = M.get_size(file_path)
    
    if not size then
        logger:warning(string.format("Cannot check content for %s: %s", 
            file_path, error_msg))
        return false, 0
    end
    
    local has_content = size > min_size
    
    if not has_content then
        logger:debug(string.format(
            "File %s size (%d bytes) is below threshold (%d bytes)",
            file_path, size, min_size
        ))
    end
    
    return has_content, size
end

--------------------------------------------------------------------------------
-- Get File Modification Time
-- 
-- Returns the last modification time of a file using the 'stat' command.
--
-- @param file_path string - The path to the file
-- @return number|nil mtime - The modification time as a Unix timestamp, or nil on error
--------------------------------------------------------------------------------
function M.get_mtime(file_path)
    if not file_path or file_path == "" then
        return nil
    end
    
    -- Use stat command to get modification time
    local cmd = string.format("stat -c %%Y %s 2>/dev/null", file_path)
    local handle = io.popen(cmd)
    
    if not handle then
        return nil
    end
    
    local result = handle:read("*a")
    handle:close()
    
    local mtime = tonumber(result)
    
    return mtime
end

--------------------------------------------------------------------------------
-- Update Modification Time Cache
-- 
-- Updates the cached modification time for a file.
--
-- @param file_path string - The path to the file
-- @param cache_key string - The cache key to use (optional, defaults to file_path)
-- @return void
--------------------------------------------------------------------------------
function M.update_mtime(file_path, cache_key)
    cache_key = cache_key or file_path
    
    local mtime = M.get_mtime(file_path)
    
    if mtime then
        mtime_cache[cache_key] = mtime
        logger:debug(string.format("Updated mtime cache for %s", cache_key))
    end
end

--------------------------------------------------------------------------------
-- Check if File is Modified
-- 
-- Checks if a file has been modified since the last cached check.
--
-- @param file_path string - The path to the file
-- @param cached_mtime number|string - The cached modification time or cache key
-- @return boolean modified - True if file has been modified or not in cache
--------------------------------------------------------------------------------
function M.is_modified(file_path, cached_mtime)
    -- If cached_mtime is a string, treat it as a cache key
    if type(cached_mtime) == "string" then
        cached_mtime = mtime_cache[cached_mtime]
    end
    
    -- If no cached time, consider it modified
    if not cached_mtime then
        return true
    end
    
    -- Get current modification time
    local current_mtime = M.get_mtime(file_path)
    
    -- If can't get current time, assume modified
    if not current_mtime then
        return true
    end
    
    -- Compare times
    return current_mtime ~= cached_mtime
end

--------------------------------------------------------------------------------
-- Read File Content
-- 
-- Reads the entire content of a file as a string.
--
-- @param file_path string - The path to the file
-- @return boolean success - True if reading was successful
-- @return string content - The file content on success, error message on failure
--------------------------------------------------------------------------------
function M.read_file(file_path)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    local file, error_msg = io.open(file_path, "r")
    
    if not file then
        logger:error(string.format("Failed to open file %s: %s", 
            file_path, tostring(error_msg)))
        return false, "Failed to open file: " .. tostring(error_msg)
    end
    
    local content = file:read("*a")
    file:close()
    
    if not content then
        return false, "Failed to read file content"
    end
    
    return true, content
end

--------------------------------------------------------------------------------
-- Write File Content
-- 
-- Writes content to a file, creating or overwriting as needed.
--
-- @param file_path string - The path to the file
-- @param content string - The content to write
-- @return boolean success - True if writing was successful
-- @return string|nil error - Error message on failure
--------------------------------------------------------------------------------
function M.write_file(file_path, content)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    if content == nil then
        content = ""
    end
    
    local file, error_msg = io.open(file_path, "w")
    
    if not file then
        logger:error(string.format("Failed to open file for writing %s: %s", 
            file_path, tostring(error_msg)))
        return false, "Failed to open file for writing: " .. tostring(error_msg)
    end
    
    file:write(content)
    file:close()
    
    logger:debug(string.format("Wrote %d bytes to file: %s", #content, file_path))
    return true, nil
end

--------------------------------------------------------------------------------
-- Append to File
-- 
-- Appends content to an existing file or creates it if it doesn't exist.
--
-- @param file_path string - The path to the file
-- @param content string - The content to append
-- @return boolean success - True if appending was successful
-- @return string|nil error - Error message on failure
--------------------------------------------------------------------------------
function M.append_file(file_path, content)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    if content == nil then
        content = ""
    end
    
    local file, error_msg = io.open(file_path, "a")
    
    if not file then
        logger:error(string.format("Failed to open file for appending %s: %s", 
            file_path, tostring(error_msg)))
        return false, "Failed to open file for appending: " .. tostring(error_msg)
    end
    
    file:write(content)
    file:close()
    
    return true, nil
end

--------------------------------------------------------------------------------
-- Delete File
-- 
-- Deletes a file from the file system.
--
-- @param file_path string - The path to the file to delete
-- @return boolean success - True if deletion was successful
-- @return string|nil error - Error message on failure
--------------------------------------------------------------------------------
function M.delete_file(file_path)
    if not file_path or file_path == "" then
        return false, "File path is empty or nil"
    end
    
    local success, error_msg = os.remove(file_path)
    
    if not success then
        logger:error(string.format("Failed to delete file %s: %s", 
            file_path, tostring(error_msg)))
        return false, "Failed to delete file: " .. tostring(error_msg)
    end
    
    logger:debug(string.format("Deleted file: %s", file_path))
    
    -- Remove from mtime cache if present
    mtime_cache[file_path] = nil
    
    return true, nil
end

--------------------------------------------------------------------------------
-- Get File Extension
-- 
-- Extracts the file extension from a file path.
--
-- @param file_path string - The file path
-- @return string|nil - The file extension (without dot), or nil if no extension
--------------------------------------------------------------------------------
function M.get_extension(file_path)
    if not file_path or file_path == "" then
        return nil
    end
    
    local extension = file_path:match("%.([^%.]+)$")
    
    return extension
end

--------------------------------------------------------------------------------
-- Get File Name
-- 
-- Extracts the file name (with extension) from a file path.
--
-- @param file_path string - The file path
-- @return string|nil - The file name, or nil on error
--------------------------------------------------------------------------------
function M.get_filename(file_path)
    if not file_path or file_path == "" then
        return nil
    end
    
    local filename = file_path:match("[^/\\]+$")
    
    return filename
end

--------------------------------------------------------------------------------
-- Get Directory Path
-- 
-- Extracts the directory path from a full file path.
--
-- @param file_path string - The file path
-- @return string|nil - The directory path, or nil on error
--------------------------------------------------------------------------------
function M.get_directory(file_path)
    if not file_path or file_path == "" then
        return nil
    end
    
    local directory = file_path:match("(.+)[/\\]")
    
    return directory
end

--------------------------------------------------------------------------------
-- Ensure Directory Exists
-- 
-- Creates a directory if it doesn't exist (including parent directories).
--
-- @param directory_path string - The directory path to create
-- @return boolean success - True if directory exists or was created
-- @return string|nil error - Error message on failure
--------------------------------------------------------------------------------
function M.ensure_directory(directory_path)
    if not directory_path or directory_path == "" then
        return false, "Directory path is empty or nil"
    end
    
    local cmd = string.format("mkdir -p %s 2>&1", directory_path)
    local handle = io.popen(cmd)
    
    if not handle then
        return false, "Failed to execute mkdir command"
    end
    
    local result = handle:read("*a")
    local success = handle:close()
    
    if not success then
        logger:error(string.format("Failed to create directory %s: %s", 
            directory_path, result))
        return false, "Failed to create directory: " .. result
    end
    
    logger:debug(string.format("Ensured directory exists: %s", directory_path))
    return true, nil
end

return M
