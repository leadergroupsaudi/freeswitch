-- resources/getToken.lua
local getToken ={}
local authenticateAPI = "https://v2.automaxsw.com/stage/automax2/CCM/api/IVR/Authenticate"
local payload = "{\"userName\":\"HtUztAaXLEVTOINyW+I3Fw==\",\"password\":\"0ddNDqI+Ogk7McKjnVObXmcWuaLyP7/kMFwWUo/3Cqo=\"}"
local json = require "lunajson"
--local json = freeswitch.JSON()
function getToken.accessToken()
session:execute("curl", authenticateAPI.." content-type application/JSON post "..payload)
curl_response_code = tonumber(session:getVariable("curl_response_code"))
curl_response      = session:getVariable("curl_response_data")
freeswitch.consoleLog("NOTICE","Curl Response Code: "..curl_response_code)
if curl_response then
        freeswitch.consoleLog("NOTICE","Curl Response Data: "..curl_response)
end
if curl_response_code >=200 and curl_response_code < 300 then
        --tokenViewModel.token
        api_response = json.decode(curl_response)
        token = api_response.token;
        freeswitch.consoleLog("NOTICE","Token:: "..token)
        return token
else
      freeswitch.consoleLog("NOTICE","Authenticate API Error ::"..tostring(curl_response_code))
      token = nil;
      return token
end
end
return getToken
