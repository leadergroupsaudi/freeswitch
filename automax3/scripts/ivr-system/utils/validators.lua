--------------------------------------------------------------------------------
-- Validators Module
-- 
-- Provides input validation functions for various data types including:
-- - Phone numbers
-- - Email addresses
-- - Numeric inputs
-- - DTMF inputs
-- - URLs
-- - Data structure validation
--
-- Usage:
--   local validators = require "utils.validators"
--   if validators.is_valid_phone(user_input) then
--       -- Process phone number
--   end
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

--------------------------------------------------------------------------------
-- Validate Phone Number
-- 
-- Validates a phone number string. Accepts various formats including:
-- - 10 digits (e.g., "5551234567")
-- - With country code (e.g., "+15551234567" or "15551234567")
-- - With dashes or spaces (e.g., "555-123-4567" or "555 123 4567")
--
-- @param phone string - The phone number to validate
-- @return boolean valid - True if the phone number is valid
-- @return string|nil normalized - Normalized phone number (digits only) on success
--------------------------------------------------------------------------------
function M.is_valid_phone(phone)
    if not phone or phone == "" then
        return false, nil
    end
    
    -- Convert to string if not already
    phone = tostring(phone)
    
    -- Remove all non-digit characters for validation
    local digits = phone:gsub("[^%d]", "")
    
    -- Check length (should be 10-15 digits)
    if #digits < 10 or #digits > 15 then
        return false, nil
    end
    
    -- Valid phone number
    return true, digits
end

--------------------------------------------------------------------------------
-- Validate Email Address
-- 
-- Validates an email address using a basic pattern match.
-- Note: This is a simplified validation. For production use, consider
-- more comprehensive email validation.
--
-- @param email string - The email address to validate
-- @return boolean valid - True if the email address is valid
--------------------------------------------------------------------------------
function M.is_valid_email(email)
    if not email or email == "" then
        return false
    end
    
    -- Convert to string if not already
    email = tostring(email)
    
    -- Basic email pattern: username@domain.tld
    local pattern = "^[%w%._%%-]+@[%w%._%%-]+%.%w+$"
    
    return email:match(pattern) ~= nil
end

--------------------------------------------------------------------------------
-- Validate DTMF Input
-- 
-- Validates DTMF (Dual-Tone Multi-Frequency) input.
-- Valid DTMF characters are: 0-9, *, #
--
-- @param dtmf string - The DTMF input to validate
-- @param min_length number - Minimum length (default: 1)
-- @param max_length number - Maximum length (default: 20)
-- @return boolean valid - True if the DTMF input is valid
--------------------------------------------------------------------------------
function M.is_valid_dtmf(dtmf, min_length, max_length)
    min_length = min_length or 1
    max_length = max_length or 20
    
    if not dtmf or dtmf == "" then
        return false
    end
    
    -- Convert to string if not already
    dtmf = tostring(dtmf)
    
    -- Check length
    if #dtmf < min_length or #dtmf > max_length then
        return false
    end
    
    -- Check if contains only valid DTMF characters (0-9, *, #)
    return dtmf:match("^[0-9*#]+$") ~= nil
end

--------------------------------------------------------------------------------
-- Validate Numeric Input
-- 
-- Validates that input contains only digits.
--
-- @param input string - The input to validate
-- @param min_length number - Minimum length (optional)
-- @param max_length number - Maximum length (optional)
-- @return boolean valid - True if input is numeric
-- @return number|nil value - The numeric value if valid
--------------------------------------------------------------------------------
function M.is_numeric(input, min_length, max_length)
    if not input or input == "" then
        return false, nil
    end
    
    -- Convert to string if not already
    input = tostring(input)
    
    -- Check if contains only digits
    if not input:match("^%d+$") then
        return false, nil
    end
    
    -- Check length constraints
    if min_length and #input < min_length then
        return false, nil
    end
    
    if max_length and #input > max_length then
        return false, nil
    end
    
    -- Convert to number
    local value = tonumber(input)
    
    return true, value
end

--------------------------------------------------------------------------------
-- Validate Numeric Range
-- 
-- Validates that a number falls within a specific range.
--
-- @param value number - The value to validate
-- @param min number - Minimum allowed value
-- @param max number - Maximum allowed value
-- @return boolean valid - True if value is within range
--------------------------------------------------------------------------------
function M.is_in_range(value, min, max)
    if not value then
        return false
    end
    
    value = tonumber(value)
    
    if not value then
        return false
    end
    
    return value >= min and value <= max
end

--------------------------------------------------------------------------------
-- Validate URL
-- 
-- Validates a URL string with basic pattern matching.
--
-- @param url string - The URL to validate
-- @return boolean valid - True if the URL appears valid
--------------------------------------------------------------------------------
function M.is_valid_url(url)
    if not url or url == "" then
        return false
    end
    
    -- Convert to string if not already
    url = tostring(url)
    
    -- Basic URL pattern: protocol://domain
    local pattern = "^https?://[%w%._%%-]+[%w%._%%-/]*$"
    
    return url:match(pattern) ~= nil
end

--------------------------------------------------------------------------------
-- Validate IP Address
-- 
-- Validates an IPv4 address.
--
-- @param ip string - The IP address to validate
-- @return boolean valid - True if the IP address is valid
--------------------------------------------------------------------------------
function M.is_valid_ip(ip)
    if not ip or ip == "" then
        return false
    end
    
    -- Convert to string if not already
    ip = tostring(ip)
    
    -- Split by dots
    local octets = {}
    for octet in ip:gmatch("[^%.]+") do
        table.insert(octets, octet)
    end
    
    -- Should have exactly 4 octets
    if #octets ~= 4 then
        return false
    end
    
    -- Each octet should be 0-255
    for _, octet in ipairs(octets) do
        local num = tonumber(octet)
        if not num or num < 0 or num > 255 then
            return false
        end
    end
    
    return true
end

--------------------------------------------------------------------------------
-- Validate Extension Number
-- 
-- Validates an extension number (3-5 digits typically).
--
-- @param extension string - The extension to validate
-- @return boolean valid - True if the extension is valid
--------------------------------------------------------------------------------
function M.is_valid_extension(extension)
    if not extension or extension == "" then
        return false
    end
    
    -- Convert to string if not already
    extension = tostring(extension)
    
    -- Extension should be 3-5 digits
    return extension:match("^%d%d%d%d?%d?$") ~= nil
end

--------------------------------------------------------------------------------
-- Validate Required Fields
-- 
-- Validates that all required fields are present in a table.
--
-- @param data table - The data table to validate
-- @param required_fields table - Array of required field names
-- @return boolean valid - True if all required fields are present
-- @return string|nil missing - Name of first missing field, if any
--------------------------------------------------------------------------------
function M.has_required_fields(data, required_fields)
    if type(data) ~= "table" then
        return false, "data_not_table"
    end
    
    if type(required_fields) ~= "table" then
        return false, "required_fields_not_array"
    end
    
    for _, field_name in ipairs(required_fields) do
        if data[field_name] == nil or data[field_name] == "" then
            return false, field_name
        end
    end
    
    return true, nil
end

--------------------------------------------------------------------------------
-- Validate Date Format
-- 
-- Validates a date string in YYYY-MM-DD format.
--
-- @param date_string string - The date string to validate
-- @return boolean valid - True if the date format is valid
-- @return table|nil date_parts - Table with year, month, day if valid
--------------------------------------------------------------------------------
function M.is_valid_date(date_string)
    if not date_string or date_string == "" then
        return false, nil
    end
    
    -- Convert to string if not already
    date_string = tostring(date_string)
    
    -- Pattern: YYYY-MM-DD
    local year, month, day = date_string:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    
    if not year then
        return false, nil
    end
    
    -- Convert to numbers
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)
    
    -- Basic validation
    if month < 1 or month > 12 then
        return false, nil
    end
    
    if day < 1 or day > 31 then
        return false, nil
    end
    
    return true, {year = year, month = month, day = day}
end

--------------------------------------------------------------------------------
-- Validate Time Format
-- 
-- Validates a time string in HH:MM:SS or HH:MM format.
--
-- @param time_string string - The time string to validate
-- @return boolean valid - True if the time format is valid
-- @return table|nil time_parts - Table with hour, minute, second if valid
--------------------------------------------------------------------------------
function M.is_valid_time(time_string)
    if not time_string or time_string == "" then
        return false, nil
    end
    
    -- Convert to string if not already
    time_string = tostring(time_string)
    
    -- Pattern: HH:MM:SS or HH:MM
    local hour, minute, second = time_string:match("^(%d%d):(%d%d):?(%d?%d?)$")
    
    if not hour then
        return false, nil
    end
    
    -- Convert to numbers
    hour = tonumber(hour)
    minute = tonumber(minute)
    second = second and tonumber(second) or 0
    
    -- Validation
    if hour < 0 or hour > 23 then
        return false, nil
    end
    
    if minute < 0 or minute > 59 then
        return false, nil
    end
    
    if second < 0 or second > 59 then
        return false, nil
    end
    
    return true, {hour = hour, minute = minute, second = second}
end

--------------------------------------------------------------------------------
-- Sanitize Input
-- 
-- Removes potentially dangerous characters from user input.
-- Useful for preventing injection attacks.
--
-- @param input string - The input to sanitize
-- @param allowed_chars string - Pattern of allowed characters (default: alphanumeric)
-- @return string - Sanitized input
--------------------------------------------------------------------------------
function M.sanitize_input(input, allowed_chars)
    if not input or input == "" then
        return ""
    end
    
    -- Convert to string if not already
    input = tostring(input)
    
    -- Default: allow alphanumeric, spaces, and common punctuation
    allowed_chars = allowed_chars or "[%w%s%.,!?%-]"
    
    -- Remove any characters not matching the allowed pattern
    local sanitized = input:gsub("[^" .. allowed_chars .. "]", "")
    
    return sanitized
end

return M
