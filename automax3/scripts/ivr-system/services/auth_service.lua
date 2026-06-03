--------------------------------------------------------------------------------
-- Authentication Service
--
-- Handles authentication and token management for the IVR system.
-- Supports OAuth2 client credentials flow and token refresh.
--
-- Features:
-- - OAuth2 token acquisition
-- - Token caching and refresh
-- - Secure credential handling
-- - Multiple auth providers
--
-- Usage:
--   local auth = require "services.auth_service"
--   auth.configure({ client_id = "...", client_secret = "..." })
--   local token = auth.get_access_token()
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local logging = require "utils.logging"
local json_utils = require "utils.json_utils"
local string_utils = require "utils.string_utils"

-- Module logger
local logger = logging.get_logger("services.auth_service")

-- Configuration
local config = {
    token_url = nil,
    client_id = nil,
    client_secret = nil,
    scope = "profile api",
    grant_type = "client_credentials",
    timeout = 30
}

-- Token cache
local token_cache = {
    access_token = nil,
    expires_at = 0,
    token_type = "Bearer"
}

--------------------------------------------------------------------------------
-- Configure Auth Service
--
-- Updates service configuration.
--
-- @param options table - Configuration options
-- @return void
--------------------------------------------------------------------------------
function M.configure(options)
    if options then
        for key, value in pairs(options) do
            config[key] = value
        end
    end
    logger:debug("Auth service configured")
end

--------------------------------------------------------------------------------
-- Get Current Time
--
-- Returns current timestamp.
--
-- @return number - Current timestamp
--------------------------------------------------------------------------------
local function get_current_time()
    return os.time()
end

--------------------------------------------------------------------------------
-- Is Token Valid
--
-- Checks if the cached token is still valid.
--
-- @return boolean - True if token is valid
--------------------------------------------------------------------------------
local function is_token_valid()
    if not token_cache.access_token then
        return false
    end

    -- Check expiration (with 60 second buffer)
    if token_cache.expires_at > 0 then
        return get_current_time() < (token_cache.expires_at - 60)
    end

    return true
end

--------------------------------------------------------------------------------
-- Request Token
--
-- Requests a new access token from the auth server.
--
-- @return table - Result {success, access_token, expires_in, error}
--------------------------------------------------------------------------------
local function request_token()
    logger:info("Requesting new access token")

    if not config.token_url then
        logger:error("Token URL not configured")
        return { success = false, error = "Token URL not configured" }
    end

    -- Build authorization header (Basic auth with client credentials)
    local auth_string = ""
    if config.client_id and config.client_secret then
        -- Base64 encode client_id:client_secret
        -- Note: Lua doesn't have built-in base64, using pre-encoded value
        -- In production, use a proper base64 library
        auth_string = config.client_id .. ":" .. config.client_secret
    end

    -- Build request body
    local body_parts = {
        "grant_type=" .. string_utils.url_encode(config.grant_type)
    }

    if config.scope then
        table.insert(body_parts, "scope=" .. string_utils.url_encode(config.scope))
    end

    local body = table.concat(body_parts, "&")

    -- Build curl command
    local curl_cmd = string.format(
        "curl -s -k -X POST '%s' " ..
        "-H 'Content-Type: application/x-www-form-urlencoded' " ..
        "-d '%s'",
        config.token_url,
        body
    )

    -- Add auth header if we have credentials
    if config.auth_header then
        curl_cmd = curl_cmd .. string.format(
            " -H 'Authorization: %s'",
            config.auth_header
        )
    end

    logger:debug("Token request command: " .. curl_cmd)

    -- Execute request
    local handle = io.popen(curl_cmd)
    local response = handle:read("*a")
    handle:close()

    logger:debug("Token response: " .. response)

    -- Parse response
    local success, parsed = pcall(json_utils.decode, response)

    if not success then
        logger:error("Failed to parse token response")
        return { success = false, error = "Invalid response" }
    end

    -- Check for access token
    local access_token = parsed.access_token or parsed.token

    if access_token then
        local expires_in = parsed.expires_in or 3600  -- Default 1 hour

        logger:info(string.format(
            "Token acquired, expires in %d seconds",
            expires_in
        ))

        return {
            success = true,
            access_token = access_token,
            token_type = parsed.token_type or "Bearer",
            expires_in = expires_in
        }
    end

    -- Check for error
    local error_msg = parsed.error or parsed.error_description or "Unknown error"
    logger:error("Token request failed: " .. error_msg)

    return { success = false, error = error_msg }
end

--------------------------------------------------------------------------------
-- Get Access Token
--
-- Gets a valid access token, refreshing if necessary.
--
-- @param force_refresh boolean - Force token refresh
-- @return string|nil - Access token or nil if failed
--------------------------------------------------------------------------------
function M.get_access_token(force_refresh)
    -- Check cached token
    if not force_refresh and is_token_valid() then
        logger:debug("Using cached access token")
        return token_cache.access_token
    end

    -- Request new token
    local result = request_token()

    if result.success then
        -- Cache the token
        token_cache.access_token = result.access_token
        token_cache.token_type = result.token_type or "Bearer"
        token_cache.expires_at = get_current_time() + (result.expires_in or 3600)

        return token_cache.access_token
    end

    logger:error("Failed to get access token: " .. (result.error or "Unknown"))
    return nil
end

--------------------------------------------------------------------------------
-- Get Authorization Header
--
-- Gets the full authorization header value.
--
-- @return string|nil - Authorization header value or nil
--------------------------------------------------------------------------------
function M.get_auth_header()
    local token = M.get_access_token()

    if token then
        return token_cache.token_type .. " " .. token
    end

    return nil
end

--------------------------------------------------------------------------------
-- Set Access Token
--
-- Manually sets an access token (for tokens obtained elsewhere).
--
-- @param token string - Access token
-- @param expires_in number - Token lifetime in seconds (optional)
-- @return void
--------------------------------------------------------------------------------
function M.set_access_token(token, expires_in)
    if token then
        -- Remove quotes if present
        token_cache.access_token = token:gsub('^"(.*)"$', '%1')
        token_cache.expires_at = expires_in and (get_current_time() + expires_in) or 0

        logger:debug("Access token set manually")
    end
end

--------------------------------------------------------------------------------
-- Clear Token
--
-- Clears the cached token.
--
-- @return void
--------------------------------------------------------------------------------
function M.clear_token()
    token_cache.access_token = nil
    token_cache.expires_at = 0

    logger:debug("Token cache cleared")
end

--------------------------------------------------------------------------------
-- Is Authenticated
--
-- Checks if we have a valid authentication token.
--
-- @return boolean - True if authenticated
--------------------------------------------------------------------------------
function M.is_authenticated()
    return is_token_valid()
end

--------------------------------------------------------------------------------
-- Authenticate
--
-- Performs authentication and caches the token.
--
-- @return boolean - True if authentication successful
--------------------------------------------------------------------------------
function M.authenticate()
    local token = M.get_access_token(true)
    return token ~= nil
end

return M
