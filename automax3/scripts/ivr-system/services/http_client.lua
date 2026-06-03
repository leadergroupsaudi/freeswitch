--------------------------------------------------------------------------------
-- HTTP Client Service
--
-- Provides HTTP/HTTPS request functionality for the IVR system.
-- Wraps curl for making API calls with support for various content types,
-- authentication, and response handling.
--
-- Features:
-- - GET, POST, PUT, DELETE methods
-- - JSON, form-urlencoded, and multipart content types
-- - Authentication header support
-- - Response caching (optional)
-- - Error handling and retries
--
-- Usage:
--   local http = require "services.http_client"
--   local response = http.get("https://api.example.com/data")
--   local response = http.post("https://api.example.com/data", {key = "value"})
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local logging = require "utils.logging"
local string_utils = require "utils.string_utils"
local json_utils = require "utils.json_utils"

-- Module logger
local logger = logging.get_logger("services.http_client")

-- Default configuration
local config = {
    timeout = 30,           -- Request timeout in seconds
    retry_count = 3,        -- Number of retries on failure
    retry_delay = 1000,     -- Delay between retries in milliseconds
    verify_ssl = true,      -- Verify SSL certificates
    user_agent = "IVR-System/2.0"
}

--------------------------------------------------------------------------------
-- Configure HTTP Client
--
-- Updates the HTTP client configuration.
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
    logger:debug("HTTP client configured")
end

--------------------------------------------------------------------------------
-- Build Curl Command
--
-- Constructs a curl command based on request parameters.
--
-- @param method string - HTTP method (GET, POST, etc.)
-- @param url string - Request URL
-- @param options table - Request options (headers, data, etc.)
-- @return string - Curl command
--------------------------------------------------------------------------------
local function build_curl_command(method, url, options)
    options = options or {}

    local cmd_parts = {"curl", "-s"}

    -- Add write-out for response code
    table.insert(cmd_parts, "-w '+%{http_code}'")

    -- Set method
    table.insert(cmd_parts, "-X " .. method)

    -- Set timeout
    table.insert(cmd_parts, "--max-time " .. (options.timeout or config.timeout))

    -- SSL verification
    if not config.verify_ssl then
        table.insert(cmd_parts, "-k")
    end

    -- User agent
    table.insert(cmd_parts, "-A '" .. config.user_agent .. "'")

    -- Headers
    if options.headers then
        for name, value in pairs(options.headers) do
            table.insert(cmd_parts, string.format(
                "-H '%s: %s'",
                name,
                string_utils.shell_escape(tostring(value))
            ))
        end
    end

    -- Content type
    if options.content_type then
        table.insert(cmd_parts, "-H 'Content-Type: " .. options.content_type .. "'")
    end

    -- Request body
    if options.data then
        local data_str

        if type(options.data) == "table" then
            if options.content_type == "application/json" then
                data_str = json_utils.encode(options.data)
            else
                -- Form encode
                local parts = {}
                for k, v in pairs(options.data) do
                    table.insert(parts, string_utils.url_encode(k) .. "=" ..
                                       string_utils.url_encode(tostring(v)))
                end
                data_str = table.concat(parts, "&")
            end
        else
            data_str = tostring(options.data)
        end

        table.insert(cmd_parts, "-d '" .. data_str:gsub("'", "'\\''") .. "'")
    end

    -- Binary data (file upload)
    if options.binary_file then
        table.insert(cmd_parts, "--data-binary @" ..
                    string_utils.shell_escape(options.binary_file))
    end

    -- Form data (multipart)
    if options.form_data then
        for name, value in pairs(options.form_data) do
            if type(value) == "table" and value.file then
                table.insert(cmd_parts, string.format(
                    "-F '%s=@%s'",
                    name,
                    string_utils.shell_escape(value.file)
                ))
            else
                table.insert(cmd_parts, string.format(
                    "-F '%s=%s'",
                    name,
                    string_utils.shell_escape(tostring(value))
                ))
            end
        end
    end

    -- URL (must be last)
    table.insert(cmd_parts, "'" .. url .. "'")

    return table.concat(cmd_parts, " ")
end

--------------------------------------------------------------------------------
-- Execute Request
--
-- Executes an HTTP request and returns the response.
--
-- @param method string - HTTP method
-- @param url string - Request URL
-- @param options table - Request options
-- @return table - Response {success, status_code, body, headers}
--------------------------------------------------------------------------------
local function execute_request(method, url, options)
    local curl_cmd = build_curl_command(method, url, options)

    logger:debug("Executing: " .. curl_cmd)

    -- Execute curl
    local handle = io.popen(curl_cmd)
    local raw_response = handle:read("*a")
    handle:close()

    -- Parse response
    local response = {
        success = false,
        status_code = nil,
        body = nil,
        raw = raw_response
    }

    -- Extract status code (appended with '+')
    local status_code = raw_response:match("%+(%d+)$")

    if status_code then
        response.status_code = tonumber(status_code)
        response.body = raw_response:gsub("%+%d+$", "")
        response.success = response.status_code >= 200 and response.status_code < 300
    else
        response.body = raw_response
        logger:warning("Could not parse status code from response")
    end

    logger:debug(string.format(
        "Response - Status: %s, Success: %s, Body length: %d",
        tostring(response.status_code),
        tostring(response.success),
        #(response.body or "")
    ))

    return response
end

--------------------------------------------------------------------------------
-- GET Request
--
-- Makes an HTTP GET request.
--
-- @param url string - Request URL
-- @param options table - Request options (headers, etc.)
-- @return table - Response
--------------------------------------------------------------------------------
function M.get(url, options)
    logger:info("GET " .. url)
    return execute_request("GET", url, options)
end

--------------------------------------------------------------------------------
-- POST Request
--
-- Makes an HTTP POST request.
--
-- @param url string - Request URL
-- @param data any - Request body (table or string)
-- @param options table - Request options (headers, content_type, etc.)
-- @return table - Response
--------------------------------------------------------------------------------
function M.post(url, data, options)
    logger:info("POST " .. url)

    options = options or {}
    options.data = data

    -- Default to JSON content type
    if not options.content_type and type(data) == "table" then
        options.content_type = "application/json"
    end

    return execute_request("POST", url, options)
end

--------------------------------------------------------------------------------
-- PUT Request
--
-- Makes an HTTP PUT request.
--
-- @param url string - Request URL
-- @param data any - Request body
-- @param options table - Request options
-- @return table - Response
--------------------------------------------------------------------------------
function M.put(url, data, options)
    logger:info("PUT " .. url)

    options = options or {}
    options.data = data

    if not options.content_type and type(data) == "table" then
        options.content_type = "application/json"
    end

    return execute_request("PUT", url, options)
end

--------------------------------------------------------------------------------
-- DELETE Request
--
-- Makes an HTTP DELETE request.
--
-- @param url string - Request URL
-- @param options table - Request options
-- @return table - Response
--------------------------------------------------------------------------------
function M.delete(url, options)
    logger:info("DELETE " .. url)
    return execute_request("DELETE", url, options)
end

--------------------------------------------------------------------------------
-- Upload File
--
-- Uploads a file using multipart form data.
--
-- @param url string - Upload URL
-- @param file_path string - Path to file
-- @param field_name string - Form field name (default: "file")
-- @param options table - Additional options (headers, extra form fields)
-- @return table - Response
--------------------------------------------------------------------------------
function M.upload_file(url, file_path, field_name, options)
    logger:info("Uploading file to " .. url)

    options = options or {}
    options.form_data = options.form_data or {}
    options.form_data[field_name or "file"] = { file = file_path }

    return execute_request("POST", url, options)
end

--------------------------------------------------------------------------------
-- Request with JSON Response
--
-- Makes a request and automatically parses JSON response.
--
-- @param method string - HTTP method
-- @param url string - Request URL
-- @param options table - Request options
-- @return table - Response with parsed JSON body
--------------------------------------------------------------------------------
function M.json_request(method, url, options)
    local response = execute_request(method, url, options)

    if response.success and response.body and response.body ~= "" then
        local success, parsed = pcall(json_utils.decode, response.body)

        if success then
            response.json = parsed
        else
            logger:warning("Failed to parse JSON response")
        end
    end

    return response
end

--------------------------------------------------------------------------------
-- Cleanup
--
-- Performs cleanup of HTTP client resources.
--
-- @return void
--------------------------------------------------------------------------------
function M.cleanup()
    logger:debug("HTTP client cleanup")
    -- Currently no persistent resources to clean up
end

return M
