local url = 'https://automax.discretal.com/auth/oauth2/token'

-- HTTP headers

local headers = {

    ['Authorization'] = 'Basic NDQxMTE5NzQ5MTM4NDE1NjE3OmxKVER1dENxUHljSUVJVUxYZ29JamF2S3NvZ1dtNEZDSmNXeHhiNExFbXJxcWtrblN1eVM5MDU4UGtTREpyWjc=',

    ['Content-Type'] = 'application/x-www-form-urlencoded'

}
 
-- Data to be sent in the POST request

local post_data = 'grant_type=client_credentials&scope=profile%20api'

local curl_command = string.format(

    "curl -X POST '%s' -H 'Authorization: %s' -H 'Content-Type: %s' --data '%s'",

    url, headers["Authorization"], headers["Content-Type"], post_data

)
 
-- Get an API object

local api = freeswitch.API()
 
-- Execute the curl command

--local response = api:execute("system", curl_command)
 
local json = require "lunajson"

--local json = freeswitch.JSON()

function getToken()

        local response = api:execute("system", curl_command)

        freeswitch.consoleLog("INFO", "Generated curl command: " .. curl_command .. "\n")

freeswitch.consoleLog("INFO", "Auth Token Response: " .. tostring(response) .. "\n")

if response then

    -- Assuming the response is JSON, parse it and extract the token

    local api_response = json.decode(response)

    local token = api_response.access_token

    freeswitch.consoleLog("NOTICE", "Token: " .. token)

    return token

else

    freeswitch.consoleLog("ERROR", "Failed to get the token.")

    return nil

end

end

return getToken
