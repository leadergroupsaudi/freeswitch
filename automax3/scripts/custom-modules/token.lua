local mime = require "mime"  -- part of LuaSocket, usually available
local username = "441119749138415617"
local password = "lJTDutCqPycIEIULXgoIjavKsogWm4FCJcWxxb4LEmrqqkknSuyS9058PkSDJrZ7"
 
-- Encode username:password in base64
local credentials = username .. ":" .. password
local encodedAuth = mime.b64(credentials)
 
-- Compose headers with base64 result
local headers = "Authorization: Basic " .. encodedAuth .. "|Content-Type: application/x-www-form-urlencoded"
 
-- Define endpoint and payload
local authenticateAPI = "https://automax.discretal.com/auth/oauth2/token"
local payload = "grant_type=client_credentials&scope=profile%20api"
