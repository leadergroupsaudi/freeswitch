--------------------------------------------------------------------------------
-- Cache Manager Service
--
-- Provides in-memory caching for the IVR system to improve performance.
-- Supports TTL (Time To Live), automatic expiration, and cache invalidation.
--
-- Features:
-- - Key-value storage with optional TTL
-- - Automatic expiration of stale entries
-- - Cache statistics
-- - Namespace support for organizing cached data
--
-- Usage:
--   local cache = require "services.cache_manager"
--   cache.set("user_123", user_data, 300)  -- Cache for 5 minutes
--   local data = cache.get("user_123")
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("services.cache_manager")

-- Cache storage
local cache_store = {}

-- Cache statistics
local stats = {
    hits = 0,
    misses = 0,
    sets = 0,
    deletes = 0,
    expirations = 0
}

-- Default TTL (seconds) - 0 means no expiration
local default_ttl = 0

--------------------------------------------------------------------------------
-- Get Current Time
--
-- Returns current time in seconds.
--
-- @return number - Current timestamp
--------------------------------------------------------------------------------
local function get_current_time()
    return os.time()
end

--------------------------------------------------------------------------------
-- Is Entry Expired
--
-- Checks if a cache entry has expired.
--
-- @param entry table - Cache entry
-- @return boolean - True if expired
--------------------------------------------------------------------------------
local function is_expired(entry)
    if entry.expires_at == 0 then
        return false  -- Never expires
    end
    return get_current_time() > entry.expires_at
end

--------------------------------------------------------------------------------
-- Set Cache Value
--
-- Stores a value in the cache with optional TTL.
--
-- @param key string - Cache key
-- @param value any - Value to cache
-- @param ttl number - Time to live in seconds (0 = no expiration)
-- @return boolean - True if successful
--------------------------------------------------------------------------------
function M.set(key, value, ttl)
    if not key then
        logger:warning("Cannot cache nil key")
        return false
    end

    ttl = ttl or default_ttl

    local expires_at = 0
    if ttl > 0 then
        expires_at = get_current_time() + ttl
    end

    cache_store[key] = {
        value = value,
        created_at = get_current_time(),
        expires_at = expires_at,
        ttl = ttl
    }

    stats.sets = stats.sets + 1

    logger:debug(string.format(
        "Cache SET: key=%s, ttl=%d",
        key, ttl
    ))

    return true
end

--------------------------------------------------------------------------------
-- Get Cache Value
--
-- Retrieves a value from the cache.
--
-- @param key string - Cache key
-- @return any|nil - Cached value or nil if not found/expired
--------------------------------------------------------------------------------
function M.get(key)
    if not key then
        return nil
    end

    local entry = cache_store[key]

    if not entry then
        stats.misses = stats.misses + 1
        logger:debug("Cache MISS: " .. key)
        return nil
    end

    -- Check expiration
    if is_expired(entry) then
        M.delete(key)
        stats.misses = stats.misses + 1
        stats.expirations = stats.expirations + 1
        logger:debug("Cache EXPIRED: " .. key)
        return nil
    end

    stats.hits = stats.hits + 1
    logger:debug("Cache HIT: " .. key)

    return entry.value
end

--------------------------------------------------------------------------------
-- Check if Key Exists
--
-- Checks if a key exists in the cache (and is not expired).
--
-- @param key string - Cache key
-- @return boolean - True if key exists and is valid
--------------------------------------------------------------------------------
function M.exists(key)
    if not key then
        return false
    end

    local entry = cache_store[key]

    if not entry then
        return false
    end

    if is_expired(entry) then
        M.delete(key)
        return false
    end

    return true
end

--------------------------------------------------------------------------------
-- Delete Cache Entry
--
-- Removes an entry from the cache.
--
-- @param key string - Cache key
-- @return boolean - True if entry was deleted
--------------------------------------------------------------------------------
function M.delete(key)
    if not key then
        return false
    end

    if cache_store[key] then
        cache_store[key] = nil
        stats.deletes = stats.deletes + 1
        logger:debug("Cache DELETE: " .. key)
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Clear Cache
--
-- Removes all entries from the cache.
--
-- @param pattern string - Optional pattern to match keys (not implemented yet)
-- @return number - Number of entries cleared
--------------------------------------------------------------------------------
function M.clear(pattern)
    local count = 0

    if pattern then
        -- Clear matching keys (simple pattern matching)
        for key in pairs(cache_store) do
            if string.find(key, pattern) then
                cache_store[key] = nil
                count = count + 1
            end
        end
    else
        -- Clear all
        for key in pairs(cache_store) do
            count = count + 1
        end
        cache_store = {}
    end

    logger:info(string.format("Cache cleared: %d entries", count))

    return count
end

--------------------------------------------------------------------------------
-- Get or Set
--
-- Gets a value from cache, or calls a function to generate it if not cached.
--
-- @param key string - Cache key
-- @param generator function - Function to generate value if not cached
-- @param ttl number - TTL for new value
-- @return any - Cached or generated value
--------------------------------------------------------------------------------
function M.get_or_set(key, generator, ttl)
    local value = M.get(key)

    if value ~= nil then
        return value
    end

    -- Generate new value
    if type(generator) == "function" then
        value = generator()

        if value ~= nil then
            M.set(key, value, ttl)
        end
    end

    return value
end

--------------------------------------------------------------------------------
-- Cleanup Expired Entries
--
-- Removes all expired entries from the cache.
--
-- @return number - Number of entries cleaned up
--------------------------------------------------------------------------------
function M.cleanup_expired()
    local count = 0
    local current_time = get_current_time()

    for key, entry in pairs(cache_store) do
        if entry.expires_at > 0 and current_time > entry.expires_at then
            cache_store[key] = nil
            count = count + 1
            stats.expirations = stats.expirations + 1
        end
    end

    if count > 0 then
        logger:debug(string.format("Cleaned up %d expired entries", count))
    end

    return count
end

--------------------------------------------------------------------------------
-- Get Statistics
--
-- Returns cache statistics.
--
-- @return table - Statistics data
--------------------------------------------------------------------------------
function M.get_stats()
    local total_entries = 0
    for _ in pairs(cache_store) do
        total_entries = total_entries + 1
    end

    local hit_rate = 0
    local total_requests = stats.hits + stats.misses
    if total_requests > 0 then
        hit_rate = (stats.hits / total_requests) * 100
    end

    return {
        hits = stats.hits,
        misses = stats.misses,
        sets = stats.sets,
        deletes = stats.deletes,
        expirations = stats.expirations,
        total_entries = total_entries,
        hit_rate = hit_rate
    }
end

--------------------------------------------------------------------------------
-- Reset Statistics
--
-- Resets cache statistics.
--
-- @return void
--------------------------------------------------------------------------------
function M.reset_stats()
    stats = {
        hits = 0,
        misses = 0,
        sets = 0,
        deletes = 0,
        expirations = 0
    }
    logger:debug("Cache statistics reset")
end

--------------------------------------------------------------------------------
-- Set Default TTL
--
-- Sets the default TTL for new cache entries.
--
-- @param ttl number - Default TTL in seconds
-- @return void
--------------------------------------------------------------------------------
function M.set_default_ttl(ttl)
    default_ttl = ttl or 0
    logger:debug("Default TTL set to: " .. default_ttl)
end

--------------------------------------------------------------------------------
-- Cleanup
--
-- Performs full cache cleanup.
--
-- @return void
--------------------------------------------------------------------------------
function M.cleanup()
    M.clear()
    M.reset_stats()
    logger:info("Cache manager cleanup complete")
end

return M
