--------------------------------------------------------------------------------
-- Incident Service
--
-- Handles incident/ticket creation and management for the IVR system.
-- Integrates with external ticketing/CRM systems.
--
-- Features:
-- - Create incidents from IVR call data
-- - Update incidents with attachments
-- - Query incident status
-- - Error reporting
--
-- Usage:
--   local incidents = require "services.incident_service"
--   local result = incidents.create(incident_data)
--   incidents.update_with_attachment(record_id, attachment_id)
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
local logger = logging.get_logger("services.incident_service")

-- Configuration
local config = {
    api_base_url = nil,
    namespace_id = nil,
    module_id = nil,
    auth_token = nil,
    timeout = 30
}

--------------------------------------------------------------------------------
-- Configure Incident Service
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
    logger:debug("Incident service configured")
end

--------------------------------------------------------------------------------
-- Set Auth Token
--
-- Sets the authentication token for API calls.
--
-- @param token string - Authentication token
-- @return void
--------------------------------------------------------------------------------
function M.set_auth_token(token)
    if token then
        -- Remove quotes if present
        config.auth_token = token:gsub('^"(.*)"$', '%1')
    end
    logger:debug("Auth token updated")
end

--------------------------------------------------------------------------------
-- Build Values Array
--
-- Converts a key-value table to the values array format expected by the API.
--
-- @param data table - Key-value pairs
-- @return table - Values array
--------------------------------------------------------------------------------
local function build_values_array(data)
    local values = {}

    for name, value in pairs(data) do
        table.insert(values, {
            name = name,
            value = type(value) == "table" and json_utils.encode(value) or tostring(value)
        })
    end

    return { values = values }
end

--------------------------------------------------------------------------------
-- Create Incident
--
-- Creates a new incident/ticket in the external system.
--
-- @param incident_data table - Incident data
-- @return table - Result {success, record_id, error}
--------------------------------------------------------------------------------
function M.create(incident_data)
    logger:info("Creating incident")

    -- Check configuration
    if not config.api_base_url then
        logger:error("API base URL not configured")
        return { success = false, error = "API not configured" }
    end

    if not config.auth_token then
        logger:error("Auth token not set")
        return { success = false, error = "Not authenticated" }
    end

    -- Build request URL
    local url = string.format(
        "%s/api/compose/namespace/%s/module/%s/record",
        config.api_base_url,
        config.namespace_id or "",
        config.module_id or ""
    )

    -- Build payload
    local payload = build_values_array(incident_data)
    local payload_json = json_utils.encode(payload)

    logger:debug("Incident payload: " .. payload_json)

    -- Build curl command
    local curl_cmd = string.format(
        "curl -s -w '+%%{http_code}' -X POST '%s' " ..
        "-H 'Content-Type: application/json' " ..
        "-H 'Accept: application/json' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-d '%s'",
        url,
        config.auth_token,
        payload_json:gsub("'", "'\\''")
    )

    logger:debug("Create incident command: " .. curl_cmd)

    -- Execute request
    local handle = io.popen(curl_cmd)
    local response = handle:read("*a")
    handle:close()

    logger:debug("Create incident response: " .. response)

    -- Parse response
    local status_code = response:match("%+(%d+)$")
    local body = response:gsub("%+%d+$", "")

    if status_code then
        status_code = tonumber(status_code)

        if status_code >= 200 and status_code < 300 then
            -- Parse response to get record ID
            local success, parsed = pcall(json_utils.decode, body)

            if success and parsed then
                local record_id = nil

                if parsed.response and parsed.response.recordID then
                    record_id = parsed.response.recordID
                elseif parsed.recordID then
                    record_id = parsed.recordID
                elseif parsed.id then
                    record_id = parsed.id
                end

                logger:info("Incident created: " .. tostring(record_id))

                return {
                    success = true,
                    record_id = record_id,
                    response = parsed
                }
            end

            return { success = true, response_body = body }
        else
            logger:error(string.format(
                "Create incident failed: %d - %s",
                status_code, body
            ))
            return { success = false, error = body, status_code = status_code }
        end
    end

    return { success = false, error = "Failed to parse response" }
end

--------------------------------------------------------------------------------
-- Update Incident
--
-- Updates an existing incident with new data.
--
-- @param record_id string - Record ID to update
-- @param update_data table - Data to update
-- @return table - Result {success, error}
--------------------------------------------------------------------------------
function M.update(record_id, update_data)
    logger:info("Updating incident: " .. tostring(record_id))

    if not record_id then
        return { success = false, error = "Record ID required" }
    end

    if not config.api_base_url or not config.auth_token then
        return { success = false, error = "Service not configured" }
    end

    -- Build URL
    local url = string.format(
        "%s/api/compose/namespace/%s/module/%s/record/%s",
        config.api_base_url,
        config.namespace_id or "",
        config.module_id or "",
        record_id
    )

    -- Build payload
    local payload = build_values_array(update_data)
    local payload_json = json_utils.encode(payload)

    -- Execute request
    local curl_cmd = string.format(
        "curl -s -w '+%%{http_code}' -X POST '%s' " ..
        "-H 'Content-Type: application/json' " ..
        "-H 'Accept: application/json' " ..
        "-H 'Authorization: Bearer %s' " ..
        "-d '%s'",
        url,
        config.auth_token,
        payload_json:gsub("'", "'\\''")
    )

    local handle = io.popen(curl_cmd)
    local response = handle:read("*a")
    handle:close()

    -- Parse response
    local status_code = response:match("%+(%d+)$")

    if status_code and tonumber(status_code) >= 200 and tonumber(status_code) < 300 then
        logger:info("Incident updated successfully")
        return { success = true }
    end

    logger:error("Update incident failed: " .. response)
    return { success = false, error = response }
end

--------------------------------------------------------------------------------
-- Update Incident with Attachment
--
-- Updates an incident to include an attachment reference.
--
-- @param record_id string - Record ID
-- @param attachment_id string - Attachment ID
-- @param additional_data table - Additional data to update (optional)
-- @return table - Result {success, error}
--------------------------------------------------------------------------------
function M.update_with_attachment(record_id, attachment_id, additional_data)
    logger:info(string.format(
        "Updating incident %s with attachment %s",
        tostring(record_id),
        tostring(attachment_id)
    ))

    if not record_id or not attachment_id then
        return { success = false, error = "Record ID and attachment ID required" }
    end

    local update_data = additional_data or {}
    update_data.Attachments = attachment_id

    return M.update(record_id, update_data)
end

--------------------------------------------------------------------------------
-- Get Incident
--
-- Retrieves incident details by ID.
--
-- @param record_id string - Record ID
-- @return table|nil - Incident data or nil if not found
--------------------------------------------------------------------------------
function M.get(record_id)
    logger:debug("Getting incident: " .. tostring(record_id))

    if not record_id or not config.api_base_url or not config.auth_token then
        return nil
    end

    local url = string.format(
        "%s/api/compose/namespace/%s/module/%s/record/%s",
        config.api_base_url,
        config.namespace_id or "",
        config.module_id or "",
        record_id
    )

    local curl_cmd = string.format(
        "curl -s -X GET '%s' " ..
        "-H 'Authorization: Bearer %s'",
        url,
        config.auth_token
    )

    local handle = io.popen(curl_cmd)
    local response = handle:read("*a")
    handle:close()

    local success, parsed = pcall(json_utils.decode, response)

    if success then
        return parsed
    end

    return nil
end

return M
