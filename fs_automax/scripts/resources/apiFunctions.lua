-- resources/apiFunctions.lua
local apiFunctions = {}

function apiFunctions.execute_command(command)
            local handle = io.popen(command)
            local result = handle:read("*a")
            handle:close()
            return result
        end

function apiFunctions.constructApi(methodType,contentType,serviceURL,apiInputdata)
                payload = {}
                headers = "";
                formData = "";
                binaryData = "";
                freeswitch.consoleLog("INFO","In Construct API Block")
                for _, item in ipairs(apiInputdata) do
                        if item.InputType == "U" then
                                if item.InputValueType == "D" or item.InputValueType == "E" then
                                   inputValue = session:getVariable(item.InputValue)
                                   freeswitch.consoleLog("INFO","API input Value: "..inputValue)
                                   serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', inputValue)
                                elseif item.InputValueType == "S" then
                                   serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', item.InputValue)
                                end
                        elseif item.InputType == "R" then
                                if item.InputValueType == "D" or item.InputValueType == "E" then
                                        payload[item.FieldName] = session:getVariable(item.InputValue)
                                else
                                        payload[item.FieldName] = item.InputValue
                                end
                        elseif item.InputType == "B" then
                                if item.InputValueType == "D" or item.InputValueType == "E" then
                                        inputValue = session:getVariable(item.InputValue)
                                        freeswitch.consoleLog("INFO","API input Value: "..inputValue)
                                        binaryData = binaryData.." --data-binary @"..inputValue
                                else
                                        inputValue = item.InputValue
                                        binaryData = binaryData.." --data-binary @"..inputValue
                        end
		                        elseif item.InputType == "F" then
                        local inputValue;
                        if item.InputValueType == "D" or item.InputValueType == "E" then
                                 freeswitch.consoleLog("INFO","Inout Value :: ".. item.InputValue)
                                 inputValue = session:getVariable(item.InputValue)
                        elseif item.InputValueType == "S" then
                                 inputValue = item.InputValue
                        end
                        if string.find(inputValue, "%.wav$") then
                                 formData = formData.." -F "..item.FieldName.."=@"..inputValue
                        else
                                 formData = formData.." -F "..item.FieldName.."="..inputValue
                        end
                        elseif item.InputType == "H" then
                                if item.InputValueType == "D" or item.InputValueType == "E" then
                                	local inputValue = item.InputValue
                                        -- Find curly braces in the input string
                                        local start, finish = string.find(inputValue, "{(.-)}")
                                        if start and finish then
                                    	-- Curly braces found
                                            local expression = string.sub(inputValue, start + 1, finish - 1)
                                            local updated_inputValue = session:getVariable(expression)
                                    	-- Replace the expression with "abc" and remove curly braces
                                            local inputValue = string.gsub(inputValue, "{" .. expression .. "}", updated_inputValue)
                                            freeswitch.consoleLog("INFO","Modified string: " .. inputValue)
                                        headers = headers .. item.FieldName .. ": " .. inputValue
                                        else
                                    	-- Curly braces not found
                                        inputValue = session:getVariable(item.InputValue)
                                        headers = headers .. item.FieldName .. ": " .. inputValue
                                        end
                                       elseif item.InputValueType == "S" then
                                   headers = headers .. item.FieldName .. ": " .. item.InputValue
                                end
                        end
                end
		
		                freeswitch.consoleLog("INFO","Service URL : "..serviceURL)
                local finalApi = serviceURL;
                if contentType == "multipart/form-data" then
                        local headers = string.gsub(headers, '"', '')
                        finalApi = "curl  -s -w '+%{http_code}' -X "..methodType.." -H '"..headers.."' "..formData.." "..finalApi
                elseif contentType == "audio/wav" then
                        local headers = string.gsub(headers, '"', '')
                        finalApi = "curl  -s -w '+%{http_code}' -X "..methodType.." -H '"..headers.."' -H  'Content-Type: "..contentType.. "' "..binaryData.." "..finalApi
                else
                        if contentType then
                                finalApi = finalApi .. " content-type "..contentType
                        end
                        if next(payload) ~= nil then
                                finalApi = finalApi.. " "..methodType.. " " .. json.encode(payload);
                        end
                        if #headers > 0 then
                                headers = string.gsub(headers, '"', '')
                                finalApi = finalApi.. " append_headers '" .. headers .. "'"
                        end
                        freeswitch.consoleLog("INFO","final Api : "..finalApi)
                end

                return finalApi
        end
	

	function apiFunctions.apiCall(contentType,finalApi,apiOutput)
           local inputKeys;
           if contentType == "multipart/form-data" or contentType == "audio/wav" then
                   local apiResponse = execute_command(finalApi)
                   freeswitch.consoleLog("INFO","HTTP response code:"..apiResponse)
                   local endIndex = string.find(apiResponse, '+')
                   local curl_response_code = tonumber(string.sub(apiResponse, endIndex + 1))
                if curl_response_code >=200 and curl_response_code < 300 then
                       local curl_response = string.sub(apiResponse, 1, endIndex-1)
                       freeswitch.consoleLog("INFO","HTTP response:"..curl_response)
                        if #apiOutput > 2 then
                            freeswitch.consoleLog("INFO","API Output: "..apiOutput)
                            apiOutput = json.decode(apiOutput)
                            freeswitch.consoleLog("INFO","Curl Response: "..curl_response)
                            curl_response = json.decode(curl_response)
                            for _,key in ipairs(apiOutput) do
                                if key.ParentResultId == nil then
                                        freeswitch.consoleLog("INFO","Found NULL ParentID")
                                        session:setVariable(key.ResultFieldTag,json.encode(curl_response[key.ResultFieldName]))
                                end
                            end
                            for _,key in ipairs(apiOutput) do
                                if key.ParentResultId ~= nil then
                                        freeswitch.consoleLog("INFO","Found ParentID for ResultFieldTag"..key.ResultFieldTag)
                                        local parentResult = json.decode(session:getVariable(key.ParentResultId))
                                        session:setVariable(key.ResultFieldTag,parentResult[key.ResultFieldName])
                                end
                            end
                         inputKeys = "S"
                        else
                         freeswitch.consoleLog("INFO","Null apiOutput")
                         inputKeys = "S"
                        end
                else
                        inputKeys = "F"
                end
           else
	        session:execute("curl", finalApi)
                --freeswitch.consoleLog("INFO", tostring(api_response))
                curl_response_code = tonumber(session:getVariable("curl_response_code"))
                curl_response      = session:getVariable("curl_response_data")
                freeswitch.consoleLog("NOTICE","Curl Response Code: "..curl_response_code)
                if curl_response then
                        freeswitch.consoleLog("NOTICE","Curl Response Data: "..curl_response)
                end
                if curl_response_code >=200 and curl_response_code < 300 then
                        if #apiOutput > 2 then
                            freeswitch.consoleLog("INFO","API Output: "..apiOutput)
                            apiOutput = json.decode(apiOutput)
                            freeswitch.consoleLog("INFO","Curl Response: "..curl_response)
                            curl_response = json.decode(curl_response)
                            for _,key in ipairs(apiOutput) do
                                if key.ParentResultId == nil then
                                        freeswitch.consoleLog("INFO","Found NULL ParentID")
                                        session:setVariable(key.ResultFieldTag,json.encode(curl_response[key.ResultFieldName]))
                                end
                            end
                            for _,key in ipairs(apiOutput) do
                                if key.ParentResultId ~= nil then
                                        freeswitch.consoleLog("INFO","Found ParentID for ResultFieldTag"..key.ResultFieldTag)
                                        local parentResult = json.decode(session:getVariable(key.ParentResultId))
                                        session:setVariable(key.ResultFieldTag,parentResult[key.ResultFieldName])
                                end
                            end
                         inputKeys = "S"
                        else
                         freeswitch.consoleLog("INFO","Null apiOutput")
                         inputKeys = "S"
                        end
                else
                        inputKeys = "F"
                end
            end
            return inputKeys
        end


return apiFunctions
