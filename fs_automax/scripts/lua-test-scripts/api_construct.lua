local json = require "lunajson"
local redis = (require 'redis').connect('127.0.0.1',6379) -- redis client connect
local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_qa');", 0))
local webApiData = webApi_Config.result


		session:setVariable("SubClassificationIdEn","1")
		session:setVariable("ClassificationIdEn","1")
		session:setVariable("Longitude","0.000")
		session:setVariable("MobileNumberEn","1111111111")
		session:setVariable("auth_userId","1")
		session:setVariable("Latitude","0.0000")
		session:setVariable("ParentIVRClassificationDigit","1")
		session:setVariable("CallerNameEn","/usr/local/freeswitch-automax-instance/var/lib/freeswitch/recordings/IVR-CCM-Recordings/CL_MSG_22ddcf2c-f71c-446d-8662-3053c55b8610.wav")
		session:setVariable("IncidentDetailsEn","/usr/local/freeswitch-automax-instance/var/lib/freeswitch/recordings/IVR-CCM-Recordings/CL_NM_22ddcf2c-f71c-446d-8662-3053c55b8610.wav")
        local function replacePlaceholder(url, fieldName, replacement)
                 return url:gsub(fieldName, replacement)
        end

	function execute_command(command)
	    local handle = io.popen(command)
	    local result = handle:read("*a")
	    handle:close()
	    return result
	end


        local function constructApi(methodType,contentType,serviceURL,apiInputdata)
                payload = {}
                headers = "";
                formData = "";
                freeswitch.consoleLog("INFO","In Construct API Block")
                for _, item in ipairs(apiInputdata) do
                        if item.InputType == "U" then
                                if item.InputValueType == "D" then
                                   inputValue = session:getVariable(item.InputValue)
                                   freeswitch.consoleLog("INFO","API input Value: "..inputValue)
                                   serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', inputValue)
                                elseif item.InputValueType == "S" then
                                   serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', item.InputValue)
                                end
                        elseif item.InputType == "R" then
                                        payload[item.FieldName] = item.InputValue
                        elseif item.InputType == "F" then
                                 if item.InputValueType == "D" then
					 freeswitch.consoleLog("INFO","Inout Value :: ".. item.InputValue)
                                        inputValue = session:getVariable(item.InputValue)
					if string.find(inputValue, "%.wav$") then
                                        	formData = formData.." -F "..item.FieldName.."=@"..inputValue
					else 
						formData = formData.." -F "..item.FieldName.."="..inputValue
					end
                                 elseif item.InputValueType == "S" then
					if string.find(item.InputValue, "%.wav$") then
                                                formData = formData.." -F "..item.FieldName.."=@"..item.InputValue
                                        else
                                        	formData = formData.." -F "..item.FieldName.."="..item.InputValue
					end
                                 end
                        --[[elseif item.InputType == "H" then
                                   if item.InputValueType == "D" then
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
                                   end]]
                        end
                end
		freeswitch.consoleLog("INFO","Form Data:: "..formData)
                freeswitch.consoleLog("INFO","Service URL : "..serviceURL)
                freeswitch.consoleLog("INFO","Method  :: ".. contentType)
                local finalApi = serviceURL;
		if contentType == "multipart/form-data" then
			finalApi = "curl  -s -w '+%{http_code}' -X POST -H 'Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICIySVNvanNFMmgwVXk3c3ZHd2RSbmhwdnFKdlhnLS0yYkdaUVh6VFlmcW1JIn0.eyJleHAiOjE3MDIwMzYyMzMsImlhdCI6MTcwMjAxODIzMywianRpIjoiYTFjZTM1NDMtZmNjYS00ZmFlLTk4NWEtNWMxODU0Zjc2MmNhIiwiaXNzIjoiaHR0cDovLzE3Mi4zMS4yMC4xMzI6ODA4MC9hdXRoL3JlYWxtcy9BdXRvbWF4IiwiYXVkIjpbInJlYWxtLW1hbmFnZW1lbnQiLCJhY2NvdW50Il0sInN1YiI6Ijc4OGVmYTgzLWNhMmItNDJmOC04YTE3LWY4MDVhNTBmYzAzNCIsInR5cCI6IkJlYXJlciIsImF6cCI6ImF1dG9tYXgyLWRldiIsInNlc3Npb25fc3RhdGUiOiI2NmJkNTlhNS03MDM0LTQwYzMtYWZhMi0xMjU5MDNiMGViN2QiLCJhY3IiOiIxIiwiYWxsb3dlZC1vcmlnaW5zIjpbIiJdLCJyZWFsbV9hY2Nlc3MiOnsicm9sZXMiOlsiZGVmYXVsdC1yb2xlcy1hdXRvbWF4IiwiYXV0b21heF9yb2xlcyIsIm9mZmxpbmVfYWNjZXNzIiwidW1hX2F1dGhvcml6YXRpb24iXX0sInJlc291cmNlX2FjY2VzcyI6eyJyZWFsbS1tYW5hZ2VtZW50Ijp7InJvbGVzIjpbInZpZXctcmVhbG0iLCJ2aWV3LWlkZW50aXR5LXByb3ZpZGVycyIsIm1hbmFnZS1pZGVudGl0eS1wcm92aWRlcnMiLCJpbXBlcnNvbmF0aW9uIiwicmVhbG0tYWRtaW4iLCJjcmVhdGUtY2xpZW50IiwibWFuYWdlLXVzZXJzIiwicXVlcnktcmVhbG1zIiwidmlldy1hdXRob3JpemF0aW9uIiwicXVlcnktY2xpZW50cyIsInF1ZXJ5LXVzZXJzIiwibWFuYWdlLWV2ZW50cyIsIm1hbmFnZS1yZWFsbSIsInZpZXctZXZlbnRzIiwidmlldy11c2VycyIsInZpZXctY2xpZW50cyIsIm1hbmFnZS1hdXRob3JpemF0aW9uIiwibWFuYWdlLWNsaWVudHMiLCJxdWVyeS1ncm91cHMiXX0sImF1dG9tYXgyLWRldiI6eyJyb2xlcyI6WyJtYW5hZ2V1c2VyIl19LCJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6ImVtYWlsIHByb2ZpbGUiLCJzaWQiOiI2NmJkNTlhNS03MDM0LTQwYzMtYWZhMi0xMjU5MDNiMGViN2QiLCJhdXRvbWF4X2Rldmdyb3VwX2NsYWltIjpbImF1dG9tYXhfZGV2Z3JvdXAiXSwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJuYW1lIjoiYWRtaW4gbnVsbCIsInByZWZlcnJlZF91c2VybmFtZSI6ImFkbWluIiwiZ2l2ZW5fbmFtZSI6ImFkbWluIiwiZmFtaWx5X25hbWUiOiJudWxsIiwiZW1haWwiOiJjenhjeHpkc2FAZ21haWwuY29tIn0.ZuvmU1DJh7DXWgyEJRhAqpNnm65wqQjNRAXzXe3IcJJinDc8c5a8CFcHAKC-yVbCQEAXnuW67xZGDTqovAnxVcZ0G6JssoQrTeWMKqUnYoVu1jGAWelyPpR5f2_cNCfaLR-ydFUl0L5SLeFJ-Wcl_s8BiirjBdYnbYVWnHqeDwRY2f0CK1m5sNWubD0uDCO2gOhGbSL3bXAx6taJHm87wXPX8QZzKMLPMkV0pp7KUEtKi-eYDtIWB0euJ7v6b9W4c4Fad0cgL_u8BIA2AM5UReJbWIg3ziXQS-GhVLK52FKx9bdHrrtp6m9UUWzr9HTe-_seTAWGxEgZzwFZMLbBIg' "..formData.." "..finalApi
		else

	                if contentType then
        	                finalApi = finalApi .. " content-type "..contentType
                	end
	                if next(payload) ~= nil then
                                finalApi = finalApi.. " "..methodType.. " " .. json.encode(payload);
        	        end
                	if #headers > 0 then
                        	finalApi = finalApi.. " append_headers '" .. headers .. "'"
	                end
        	        freeswitch.consoleLog("INFO","final Api : "..finalApi)
		end
                	return finalApi

        end		

                local api_id = 32

                local methodType,contentType,serviceURL, apiInputdata,inputKeys
                for _,api in pairs(webApiData) do
                        if api.apiId == api_id then
                        methodType = api.methodType
                        contentType = api.inputMediaType
                        serviceURL = api.serviceURL
                        apiInputdata = json.decode(api.apiInput)
                        apiOutput = api.apiOutput
                        break
                        end
                end
                --freeswitch.consoleLog("INFO", "Method:: "..methodType.." :: contentType :: "..contentType.." :: serviceURL ::"..serviceURL.." :: apiInput ::".. json.encode(apiInputdata))
                local finalApi = constructApi(methodType,contentType,serviceURL,apiInputdata)
                freeswitch.consoleLog("NOTICE","Final modified API: "..finalApi)
		if contentType == "multipart/form-data" then
			local apiResponse = execute_command(finalApi)
			--local status_code = tonumber(string.match(apiResponse, "(%d+)"))
			freeswitch.consoleLog("INFO","HTTP response:"..apiResponse)
			local endIndex = string.find(apiResponse, '+')
			local responseCode = tonumber(string.sub(apiResponse, endIndex + 1))
			local response = string.sub(apiResponse, 1, endIndex-1)
			freeswitch.consoleLog("INFO","HTTP response:"..response)
			freeswitch.consoleLog("INFO","HTTP response:"..responseCode)
			--freeswitch.consoleLog("INFO","HTTP Status Code:"..status_code)
		end
