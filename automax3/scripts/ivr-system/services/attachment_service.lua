--------------------------------------------------------------------------------
-- Attachment Service
--
-- Handles file uploads and attachment management for the IVR system.
-- Supports uploading recordings and other files to external systems.
--
-- Features:
-- - File upload to external APIs
-- - Attachment validation
-- - Progress tracking (where supported)
-- - Error handling with retries
--
-- Usage:
--   local attachments = require "services.attachment_service"
--   local result = attachments.upload_recording("/path/to/file.wav")
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local logging = require "utils.logging"
local string_utils = require "utils.string_utils"
local file_utils = require "utils.file_utils"

-- Module logger
local logger = logging.get_logger("services.attachment_service")

-- Configuration
local config = {
    upload_url = nil,
    auth_token = nil,
    max_file_size = 50 * 1024 * 1024,  -- 50 MB
    allowed_extensions = { ".wav", ".mp3", ".pdf", ".jpg", ".png" },
    retry_count = 3,
    timeout = 60
}

--------------------------------------------------------------------------------
-- Configure Attachment Service
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
    logger:debug("Attachment service configured")
end

--------------------------------------------------------------------------------
-- Validate File
--
-- Validates a file before upload.
--
-- @param file_path string - Path to file
-- @return boolean success - True if valid
-- @return string|nil error - Error message if invalid
--------------------------------------------------------------------------------
function M.validate_file(file_path)
    -- Check file exists
    if not file_utils.exists(file_path) then
        return false, "File does not exist: " .. file_path
    end

    -- Check file size
    local file_size = file_utils.get_size(file_path)

    if not file_size then
        return false, "Cannot determine file size"
    end

    if file_size > config.max_file_size then
        return false, string.format(
            "File too large: %d bytes (max: %d bytes)",
            file_size, config.max_file_size
        )
    end

    if file_size == 0 then
        return false, "File is empty"
    end

    -- Check file extension
    local extension = file_path:match("(%.[^%.]+)$")

    if extension then
        extension = extension:lower()
        local valid_extension = false

        for _, allowed in ipairs(config.allowed_extensions) do
            if extension == allowed then
                valid_extension = true
                break
            end
        end

        if not valid_extension then
            return false, "File extension not allowed: " .. extension
        end
    end

    return true, nil
end

--------------------------------------------------------------------------------
-- Upload File
--
-- Uploads a file to the configured endpoint.
--
-- @param file_path string - Path to file
-- @param options table - Upload options (metadata, etc.)
-- @return table - Upload result {success, attachment_id, error}
--------------------------------------------------------------------------------
function M.upload_file(file_path, options)
    options = options or {}

    logger:info("Uploading file: " .. file_path)

    -- Validate file
    local valid, validation_error = M.validate_file(file_path)

    if not valid then
        logger:error("File validation failed: " .. validation_error)
        return { success = false, error = validation_error }
    end

    -- Check configuration
    if not config.upload_url then
        logger:error("Upload URL not configured")
        return { success = false, error = "Upload URL not configured" }
    end

    -- Build curl command
    local auth_header = ""
    if config.auth_token then
        auth_header = string.format("-H 'Authorization: Bearer %s'", config.auth_token)
    end

    local curl_cmd = string.format(
        "curl -s -w '+%%{http_code}' -X POST %s " ..
        "-F 'file=@%s' " ..
        "--max-time %d " ..
        "'%s'",
        auth_header,
        string_utils.shell_escape(file_path),
        config.timeout,
        config.upload_url
    )

    logger:debug("Upload command: " .. curl_cmd)

    -- Execute with retries
    local result = nil
    local last_error = nil

    for attempt = 1, config.retry_count do
        logger:debug(string.format("Upload attempt %d of %d", attempt, config.retry_count))

        local handle = io.popen(curl_cmd)
        local response = handle:read("*a")
        handle:close()

        -- Parse response
        local status_code = response:match("%+(%d+)$")
        local body = response:gsub("%+%d+$", "")

        if status_code then
            status_code = tonumber(status_code)

            if status_code >= 200 and status_code < 300 then
                -- Success
                logger:info("Upload successful")

                -- Try to parse attachment ID from response
                local attachment_id = nil

                -- Try JSON parsing
                local json_utils = require "utils.json_utils"
                local success, parsed = pcall(json_utils.decode, body)

                if success and parsed then
                    attachment_id = parsed.attachmentId or
                                   parsed.attachment_id or
                                   parsed.id or
                                   parsed.fileId
                end

                result = {
                    success = true,
                    attachment_id = attachment_id,
                    response_body = body,
                    status_code = status_code
                }

                break
            else
                last_error = string.format(
                    "Upload failed with status %d: %s",
                    status_code, body
                )
                logger:warning(last_error)
            end
        else
            last_error = "Failed to parse response"
            logger:warning(last_error)
        end

        -- Wait before retry
        if attempt < config.retry_count then
            os.execute("sleep 1")
        end
    end

    if not result then
        return { success = false, error = last_error or "Upload failed" }
    end

    return result
end

--------------------------------------------------------------------------------
-- Upload Recording
--
-- Convenience function to upload a recording file with appropriate metadata.
--
-- @param recording_path string - Path to recording file
-- @param metadata table - Recording metadata (call_uuid, caller_id, etc.)
-- @return table - Upload result
--------------------------------------------------------------------------------
function M.upload_recording(recording_path, metadata)
    metadata = metadata or {}

    logger:info("Uploading recording: " .. recording_path)

    return M.upload_file(recording_path, {
        type = "recording",
        metadata = metadata
    })
end

--------------------------------------------------------------------------------
-- Get Attachment
--
-- Retrieves attachment information by ID.
--
-- @param attachment_id string - Attachment ID
-- @return table|nil - Attachment info or nil if not found
--------------------------------------------------------------------------------
function M.get_attachment(attachment_id)
    logger:debug("Getting attachment: " .. attachment_id)

    -- This would typically call an API to get attachment details
    -- For now, return nil (not implemented)

    logger:warning("get_attachment not fully implemented")
    return nil
end

--------------------------------------------------------------------------------
-- Delete Attachment
--
-- Deletes an attachment by ID.
--
-- @param attachment_id string - Attachment ID
-- @return boolean - True if deleted successfully
--------------------------------------------------------------------------------
function M.delete_attachment(attachment_id)
    logger:debug("Deleting attachment: " .. attachment_id)

    -- This would typically call an API to delete the attachment
    -- For now, return false (not implemented)

    logger:warning("delete_attachment not fully implemented")
    return false
end

return M
