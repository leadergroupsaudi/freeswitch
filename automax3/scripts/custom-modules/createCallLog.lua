local callLog = {}

local from_num = session:getVariable("caller_id_number")

local uuid = session:getVariable("uuid")

local sip_user_agent = session:getVariable("sip_user_agent")

local timestamp = session:getVariable("created_time");

--local startTime = os.date("!%Y-%m-%dT%TZ", timestamp/1e6)

local startTime = os.date("!%Y-%m-%dT%TZ", math.floor(timestamp / 1e6))

local domain = session:getVariable("domain_name")

api = freeswitch.API()

json = freeswitch.JSON()

local time = api:getTime()

local createCallLogAPI = "https://v2.automaxsw.com/Stage/Axionic/CCM/API/CLK/CallLog append_headers"

local getToken = require "custom-modules.getToken"

function callLog.create()

        access_token = getToken()

        if access_token ~= nil then

             --   useragent_json = "{\"callType\":\"A\",\"callMode\":\"I\",\"startTime\":\""..startTime.."\",\"participants\":[{\"userId\":0,\"extensionId\":0,\"callerId\":\""..from_num.."\",\"joinTime\":\""..startTime.."\",\"isCaller\":true,\"answerStatus\":\"A\",\"callReachTime\":\""..startTime.."\"}]}"

                useragent_json = "{\"callType\":\"A\",\"callMode\":\"I\",\"startTime\":\""..startTime.."\",\"participants\":[{\"callerId\":\""..from_num.."\",\"joinTime\":\""..startTime.."\",\"isCaller\":true,\"answerStatus\":\"A\",\"callReachTime\":\""..startTime.."\"}]}"

                session:execute("curl", createCallLogAPI.." 'Authorization: Bearer "..access_token.."' content-type application/JSON post "..useragent_json)

                local api_response_code = session:getVariable("curl_response_code")

                local api_response_data = session:getVariable("curl_response_data")

                freeswitch.consoleLog("INFO","The response code of create ip phone callLogdata api is :" ..api_response_code.. " :: Response Data:: "..api_response_data)

                if tonumber(api_response_code) >=200 and tonumber(api_response_code) < 300 then

                        local json_api_response = json:decode(api_response_data)

                        local callLogId = json_api_response.result.callLogId

                        callLogId = math.floor(callLogId)

                        freeswitch.consoleLog("INFO", "The received callLogId is :"..callLogId.."\n")

                        session:setVariable("sip_h_X-CallLogId", callLogId);

                        session:execute("export","nolocal:sip_h_X-CallLogId="..callLogId)

                        session:setVariable("Call_Log_Id", callLogId);

                        session:execute("export","nolocal:Call_Log_Id="..callLogId)

                        return callLogId

                else

                      freeswitch.consoleLog("NOTICE","Authenticate API Error ::"..api_response_code)

                      return nil

                end

        else

                freeswitch.consoleLog("NOTICE","Authenticate Error ::")

                return nil

        end

end
 
return callLog

 
