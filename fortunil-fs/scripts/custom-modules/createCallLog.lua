local callLog = {}
local from_num = session:getVariable("caller_id_number")
local uuid = session:getVariable("uuid")
local sip_user_agent = session:getVariable("sip_user_agent")
local timestamp = session:getVariable("created_time")
local startTime = os.date("!%Y-%m-%dT%TZ", timestamp / 1e6)
local domain = session:getVariable("domain_name")

api = freeswitch.API()
json = freeswitch.JSON()
local duration = tonumber(session:getVariable("billsec")) or 0  -- Duration in seconds

local endTime = os.date("!%Y-%m-%dT%TZ", (os.time() + duration))  -- Calculate end time

-- Define the API endpoint
local createCallLogAPI = "https://fortunil.leadergroup.com/api/method/axionic_integration.axionic_integration.api.voip.CreateOrUpdateCallLog"

function callLog.create()
    -- Construct the JSON payload
--    local useragent_json ="{\"CallType\":\"A\",\"CallMode\":\"I\",\"StartTime\":\"" .. startTime .."\",\"participants\":[{\"CallerId\":\"" .. from_num .."\",\"JoinTime\":\"" .. startTime .."\",\"HangupTime\":\"" .. endTime .."\",\"AnswerStatus\":\"A\",\"IsCaller\":\"1\",\"CallReachTime\":\"" .. startTime .."\"}],\"CallStatus\":\"I\"}"
    local useragent_json = string.format(
    '{"CallType":"%s","CallMode":"%s","StartTime":"%s","participants":[{"CallerId":"%s","JoinTime":"%s","HangupTime":"%s","AnswerStatus":"%s","IsCaller":"%s","CallReachTime":"%s"}],"CallStatus":"%s"}',
    "A",            
    "I",           
    startTime,      
    from_num,       
    startTime,      
    endTime,        
    "A",            
    "1",            
    startTime,      
    "I"             
)


    -- Execute the API request
    session:execute("curl", createCallLogAPI.." content-type application/JSON post "..useragent_json)

    
    -- Retrieve and log the API response
    local api_response_code = session:getVariable("curl_response_code")
    local api_response_data = session:getVariable("curl_response_data")
    
   --	 local api_response_data = "{\"message\":[{ \"status\": \"success\",\"message\": \"Call log Added\",\"name\": \"CLOG-2024-00103\"}] }"
    freeswitch.consoleLog("INFO", "The response code of create call log API is: " .. api_response_code .. " :: Response Data: " .. api_response_data)
    
    -- Decode the API response
      local json_api_response, decode_error = json:decode(api_response_data)
    
    if decode_error then
        freeswitch.consoleLog("ERROR", "Failed to decode JSON response: " .. decode_error)
        return nil
    end

    -- Check if result field exists
    if json_api_response and json_api_response.message then
       local callLogId = json_api_response.message.name
        freeswitch.consoleLog("INFO", "The received callLogId is: " .. callLogId .. "\n")
        session:setVariable("sip_h_X-CallLogId", callLogId)
        session:execute("export", "nolocal:sip_h_X-CallLogId=" .. callLogId)
        session:setVariable("Call_Log_Id", callLogId)
        session:execute("export", "nolocal:Call_Log_Id=" .. callLogId)
       return callLogId
   else
        freeswitch.consoleLog("ERROR", "API response does not contain 'result' field. Response data: " .. api_response_data)
        return nil
    end
end

return callLog

