local call_uuid = session:getVariable("uuid")
local domain = session:getVariable("domain_name")
local caller_name = session:getVariable("caller_id_name")
local caller_id = session:getVariable("caller_id_number")
local json = require "lunajson"
local http = require("socket.http")
local ltn12 = require("ltn12")
api = freeswitch.API();
-- local redis = (require 'redis').connect('127.0.0.1',6379) -- redis client connect
-- local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfigurationV6');", 0)) -- storing the IVRNodes data
-- local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfiguration_tts_new');", 0)) -- storing the IVRNodes data
-- local ivrdata = ivrconfig.IVRConfiguration[1].IVRProcessFlow;
-- local generalSettings = ivrconfig.IVRConfiguration[1].GeneralSettingValues

-- local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_tts_new');", 0))
-- local webApiData = webApi_Config.result

-- local ivrextensions = redis:eval("return redis.call('json.get','Extensions_qa');", 0) -- storing the IVRNodes data
-- local agent_extensions = json.decode(ivrextensions)

-- local ivrrecording_data = redis:eval("return redis.call('json.get','RecordingType_qa');", 0)
-- local recording_config = json.decode(ivrrecording_data)
local scripts_path = freeswitch.getGlobalVariable("script_dir")
local ivrFilePath = scripts_path .. "/ivr-cc-config/ivrconfig.json"

-- Read the JSON file content
local ivrfile = io.open(ivrFilePath, "r")
if not ivrfile then
    freeswitch.consoleLog("norice", "Error: Unable to open IVR file.")
    return
end

local ivrjsonContent = ivrfile:read("*a")
ivrfile:close()

-- Parse the JSON content
local ivrconfig = json.decode(ivrjsonContent)
local ivrdata = ivrconfig.IVRConfiguration[1].IVRProcessFlow;
local generalSettings = ivrconfig.IVRConfiguration[1].GeneralSettingValues
-- local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_qa');", 0))
local WebConfigFilePath = scripts_path .. "/ivr-cc-config/automax_webAPIConfig.json"

-- Read the JSON file content
local webConfigfile = io.open(WebConfigFilePath, "r")
if not webConfigfile then
    freeswitch.consoleLog("norice", "Error: Unable to open webConfigfile file.")
    return
end

local webConfigjsonContent = webConfigfile:read("*a")
webConfigfile:close()
function printTable(tbl, indent)
    indent = indent or ""
    for k, v in pairs(tbl) do
        local key = tostring(k)
        if type(v) == "table" then
            freeswitch.consoleLog("INFO", indent .. key .. " = {\n")
            printTable(v, indent .. "  ")
            freeswitch.consoleLog("INFO", indent .. "}\n")
        else
            freeswitch.consoleLog("INFO", indent .. key .. " = " .. tostring(v) .. "\n")
        end
    end
end

-- Parse the JSON content
local webApi_Config = json.decode(webConfigjsonContent)
webApiData = webApi_Config.result
printTable(webApiData)

-- local ivrextensions = redis:eval("return redis.call('json.get','Extensions_qa');", 0) -- storing the IVRNodes data

local extensionsFilePath = scripts_path .. "/ivr-cc-config/Extensions_qa.json"

local extensionConfigfile = io.open(extensionsFilePath, "r")
if not extensionConfigfile then
    freeswitch.consoleLog("norice", "Error: Unable to open ExtensionConfigfile file.")
    return
end

local extensionConfigjsonContent = extensionConfigfile:read("*a")
extensionConfigfile:close()

-- Parse the JSON content
local agent_extensions = json.decode(extensionConfigjsonContent)

-- local ivrrecording_data = redis:eval("return redis.call('json.get','RecordingType_qa');", 0)
local recordTypeFilePath = scripts_path .. "/ivr-cc-config/RecordingType_qa.json"

-- Read the JSON file content
local recordTypeConfigfile = io.open(recordTypeFilePath, "r")
if not recordTypeConfigfile then
    freeswitch.consoleLog("norice", "Error: Unable to open recordTypeConfigfile file.")
    return
end

local ivrrecording_data = recordTypeConfigfile:read("*a")
recordTypeConfigfile:close()

local recording_config = json.decode(ivrrecording_data)
local epm_audiofiles_path = freeswitch.getGlobalVariable("sounds_dir")
local audio_recording_path = freeswitch.getGlobalVariable("recordings_dir")
local audiopath = epm_audiofiles_path .. "/ivr_audiofiles_tts_new/"
local recording_dir = audio_recording_path .. '/IVR-CCM-Recordings/'
-- local module_folder = "/usr/local/freeswitch-automax-instance/share/freeswitch/scripts/"

-- local module_folder = "/usr/local/freeswitch-automax-instance/share/freeswitch/scripts/"
package.path = scripts_path .. "/" .. "?.lua;" .. package.path
local callLog = require "custom-modules.createCallLog"

-- local dynamicApi = require "resources.functions.dynamicApi"
local function find_childNode(data)
    local iVRChildNodeId;
    for key, value in pairs(ivrdata) do
        if (value.NodeId == data.NodeId) then
            iVRChildNodeId = value.ChildNodeConfig[1].ChildNodeId;
            Sub_menu(iVRChildNodeId)
            return
        end
    end
    freeswitch.consoleLog("notice", "Found IVR Node ID: " .. iVRChildNodeId)
end

local function find_childNode_with_dtmfinput(digits, data)
    freeswitch.consoleLog("notice", "*************** Find Child Node With DTMF Digit input : " .. digits);
    local iVRChildNodeId = 0;
    for key, value in pairs(ivrdata) do
        if (value.NodeId == data.NodeId) then
            for _, childNode in pairs(value.ChildNodeConfig) do
                if childNode.InputKeys == digits then
                    iVRChildNodeId = childNode.ChildNodeId;
                    Sub_menu(iVRChildNodeId)
                    return
                end
            end
        end
    end
    freeswitch.consoleLog("notice", "Found IVR Child Node ID: " .. iVRChildNodeId)
    if iVRChildNodeId == 0 then
        freeswitch.consoleLog("notice", "IVR Child Node ID is not found with DTMF: " .. digits ..
            " and Parant Node ID: " .. data.NodeId)
        freeswitch.consoleLog("NOTICE", "Hangup the Call")
        session:hangup()
    end
end

-- URL encoding for form-urlencoded content
function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = string.gsub(str, " ", "+")
    end
    return str
end

function urlencode_table(tbl)
    local result = {}
    for k, v in pairs(tbl) do
        table.insert(result, urlencode(k) .. "=" .. urlencode(v))
    end
    return table.concat(result, "&")
end

-- Function to insert spaces between digits in a string
local function insert_spaces(str)
    local result = ""
    for i = 1, #str do
        local char = str:sub(i, i)
        if char:match("%d") then
            result = result .. " " .. char
        else
            result = result .. char
        end
    end
    return result
end

local function replacePlaceholder(url, fieldName, replacement)
    return url:gsub(fieldName, replacement)
end
------ transforming a Lua table into the specific JSON-----
local function convert_to_values_format(tbl)
    local values_array = {}
    for key, value in pairs(tbl) do
        table.insert(values_array, {
            name = key,
            --                              value = type(value) == "table" and json.encode(value):gsub('"', '\\"') or tostring(value)
            value = type(value) == "table" and json.encode(value) or tostring(value)
        })
    end
    return {
        values = values_array
    }
end

function execute_command(command)
    local handle = io.popen(command)
    local result = handle:read("*a")
    handle:close()
    return result
end

local function setLanguage(languageCode)
    freeswitch.consoleLog("INFO", "Language Set Function")
    for _, settings in pairs(generalSettings) do
        if settings.SettingId == 15 then
            local languageSettings = json.decode(settings.SettingValue)
            for _, setting in ipairs(languageSettings) do
                if setting.LanguageCode == tonumber(languageCode) then
                    for key, value in pairs(setting) do
                        session:setVariable(key, value)
                    end
                end
            end
            break
        end
    end
end

local function constructApi(methodType, contentType, serviceURL, apiInputdata)
    payload = {}
    headers = "";
    formData = "";
    binaryData = "";
    freeswitch.consoleLog("INFO", "In Construct API Block")
    local inputArray = apiInputdata.headers or apiInputdata.values or apiInputdata
    for _, item in ipairs(inputArray) do
        freeswitch.consoleLog("INFO", "InputType: " .. item.InputType)
        if item.InputType == "U" then
            freeswitch.consoleLog("INFo", "In Inputtype U")
            if item.InputValueType == "D" or item.InputValueType == "E" then
                inputValue = session:getVariable(item.InputValue)
                freeswitch.consoleLog("INFO", "API input Value: " .. inputValue)
                serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', inputValue)
            elseif item.InputValueType == "S" then
                serviceURL = replacePlaceholder(serviceURL, '{' .. item.FieldName .. '}', item.InputValue)
            end
        elseif item.InputType == "R" then
            -- Log the InputType and InputValueType for debugging
            --	freeswitch.consoleLog("INFO", "Processing InputType: " .. item.InputType .. " with InputValueType: " .. item.InputValueType)
            freeswitch.consoleLog("INFO", "Processing InputType: " .. tostring(item.InputType) ..
                " with InputValueType: " .. tostring(item.InputValueType))
            if item.InputValueType == "D" or item.InputValueType == "E" then
                freeswitch.consoleLog("INFO", "IF Part: " .. tostring(item.InputType) .. " with InputValueType: " ..
                    tostring(item.InputValueType))
                --	freeswitch.consoleLog("INFO", "IF Part: " .. item.InputType .. " with InputValueType: " .. item.InputValueType)
                local key = item.FieldName or item.name
                freeswitch.consoleLog("INFO", "Attempting to fetch session variable: " .. tostring(item.InputValue))
                -- Extract real variable name from template format like {{CallerNameTextEn}
                local rawInput = item.InputValue or item.value
                local variableName = tostring(rawInput):match("{{(.-)}}")
                freeswitch.consoleLog("INFO", "Attempting to fetch session variable: " .. tostring(variableName))
                local val = session:getVariable(variableName)
                -- local val = session:getVariable(item.InputValue)

                if val then
                    -- freeswitch.consoleLog("INFO", "InputValueType is D or E. Fetched dynamic value for " .. tostring(key) .. ": " .. tostring(val))
                    --	payload[key] = val
                    --	freeswitch.consoleLog("INFO", "InputValueType is D or E. Fetched dynamic value for " .. tostring(key) .. ": " .. tostring(val))
                    --	payload[key] = val
                    val = tostring(val):gsub('^"(.*)"$', '%1')
                    local finalValue = tostring(rawInput):gsub("{{" .. variableName .. "}}", val)
                    freeswitch.consoleLog("INFO",
                        "Fetched dynamic value for " .. tostring(key) .. ": " .. tostring(finalValue))
                    payload[key] = finalValue
                else
                    freeswitch.consoleLog("ERR",
                        "InputValueType is D or E. No dynamic value found for " .. tostring(key))
                    freeswitch.consoleLog("ERR", "Missing key or dynamic value for item: " .. json.encode(item)) -- optional, needs json lib
                    --	freeswitch.consoleLog("INFO", "InputValueType is D or E. No dynamic value found for " .. tostring(key))
                    --	freeswitch.consoleLog("ERR", "Missing key or dynamic value for item: " .. tostring(item))
                end

                --[[local key = item.FieldName or item.name
        				local val = session:getVariable(item.InputValue)
        				if val then
            				freeswitch.consoleLog("INFO", "InputValueType is D or E. Fetched dynamic value for " .. tostring(key) .. ": " .. tostring(val))
        				else
            				freeswitch.consoleLog("INFO", "InputValueType is D or E. No dynamic value found for " .. tostring(key))
        				end
        			if key and val then
            			payload[key] = val
        			else
            			freeswitch.consoleLog("ERR", "Missing key or dynamic value for item: " .. tostring(item))
        			end]]
                --[[	local dynamicValue = session:getVariable(item.InputValue)
					if dynamicValue then
            				freeswitch.consoleLog("INFO", "InputValueType is D or E. Fetched dynamic value for " .. item.FieldName .. ": " .. dynamicValue)
        				else
            				freeswitch.consoleLog("INFO", "InputValueType is D or E. No dynamic value found for " .. item.FieldName)
        				end
					payload[item.FieldName] = session:getVariable(item.InputValue)]]
            else
                --[[	freeswitch.consoleLog("INFO", "Else part: " .. item.InputType .. " with InputValueType: " .. item.InputValueType)
				--	freeswitch.consoleLog("INFO", "Else part: " .. tostring(item.InputType) .. " with InputValueType: " .. tostring(item.InputValueType))
					--payload[item.FieldName] = item.InputValue
				--	  payload[item.name] = item.value
					--freeswitch.consoleLog("INFO", "Payload Field: " .. item.FieldName .. " | Value: " .. tostring(payload[item.FieldName]))
				--	freeswitch.consoleLog("INFO", "Payload Field: " .. item.name .. " | Value: " .. tostring(payload[item.name])) ]]

                -- Handle either naming convention
                local key = item.name or item.FieldName
                local val = item.value or item.InputValue

                if key and val then
                    if key == "Map" then
                        -- remove wrapping quotes for normal fields
                        payload[key] = {
                            coordinates = {0.0, 0.0}
                        }
                    else
                        -- for Map field, keep the string as-is (with escaped JSON inside)
                        local cleanVal = tostring(val)
                        cleanVal = cleanVal:gsub('^"(.*)"$', '%1')
                        payload[key] = cleanVal
                    end
                    freeswitch.consoleLog("INFO", "Payload Field: " .. tostring(key) .. " | Value: " .. tostring(val))
                else
                    freeswitch.consoleLog("ERR", "Missing key or value in item: " .. tostring(item))
                end
            end
        elseif item.InputType == "B" then
            freeswitch.consoleLog("INFo", "In Inputtype B")
            if item.InputValueType == "D" or item.InputValueType == "E" then
                inputValue = session:getVariable(item.InputValue)
                freeswitch.consoleLog("INFO", "API input Value: " .. inputValue)
                binaryData = binaryData .. " --data-binary @" .. inputValue
            else
                inputValue = item.InputValue
                binaryData = binaryData .. " --data-binary @" .. inputValue
            end
            --[[    elseif item.InputType == "F" then
	                         if item.InputValueType == "D" or item.InputValueType == "E" then
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
                                 end ]]
        elseif item.InputType == "F" then
            freeswitch.consoleLog("INFo", "In Inputtype F")
            local inputValue;
            if item.InputValueType == "D" or item.InputValueType == "E" then
                freeswitch.consoleLog("INFO", "Inout Value :: " .. item.InputValue)
                inputValue = session:getVariable(item.InputValue)
            elseif item.InputValueType == "S" then
                inputValue = item.InputValue
            end
            if string.find(inputValue, "%.wav$") then
                formData = formData .. " -F " .. item.FieldName .. "=@" .. inputValue
            else
                formData = formData .. " -F " .. item.FieldName .. "=" .. inputValue
            end
        elseif item.InputType == "H" then
            freeswitch.consoleLog("INFo", "In Inputtype H")
            local fieldName = item.FieldName or item.name
            if item.InputValueType == "D" or item.InputValueType == "E" then
                local inputValue = item.InputValue or item.value
                --	local inputValue = item.InputValue
                -- Find curly braces in the input string
                -- local start_pos, end_pos, expression = string.find(inputValue, "{(.-)}")
                local start, finish = string.find(inputValue, "{(.-)}")
                if start and finish then
                    freeswitch.consoleLog("INFo", "Start and Finish")
                    -- Curly braces found
                    local expression = string.sub(inputValue, start + 1, finish - 1)
                    local updated_inputValue = session:getVariable(expression)
                    -- Replace the expression with "abc" and remove curly braces
                    inputValue = string.gsub(inputValue, "{" .. expression .. "}", updated_inputValue)
                    freeswitch.consoleLog("INFO", "Modified string: " .. inputValue)
                    local headerKey = item.FieldName or item.name
                    headers = headers .. headerKey .. ": " .. inputValue
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

    freeswitch.consoleLog("INFO", "Service URL : " .. serviceURL)
    local finalApi = serviceURL;
    finalApi = finalApi .. " -s -w '+%{http_code}' "
    freeswitch.consoleLog("INFO", "Content-Type is: " .. contentType .. "\n")
    if contentType == "multipart/form-data" then
        freeswitch.consoleLog("INFO", "multipart/form-data : " .. serviceURL)
        local headers = string.gsub(headers, '"', '')
        finalApi = "curl  -s -w '+%{http_code}' -X " .. methodType .. " -H '" .. headers .. "' " .. formData .. " " ..
                       finalApi
    elseif contentType == "audio/wav" then
        local headers = string.gsub(headers, '"', '')
        finalApi = "curl  -s -w '+%{http_code}' -X " .. methodType .. " -H '" .. headers .. "' -H  'Content-Type: " ..
                       contentType .. "' " .. binaryData .. " " .. finalApi

    else
        if contentType then
            finalApi = finalApi .. " -H \"Content-Type: " .. contentType .. "\""
            freeswitch.consoleLog("INFO", "Content-Type provided: " .. finalApi .. "\n")
        end
        if next(payload) ~= nil then
            local encodedPayload
            if contentType == "application/x-www-form-urlencoded" then
                encodedPayload = urlencode_table(payload)
            elseif contentType == "application/json" then
                -- Convert to `values` format
                --[[  			local function convert_to_values_format(tbl)
            			local values_array = {}
           			 for key, value in pairs(tbl) do
                		table.insert(values_array, {
                    		name = key,
--				value = type(value) == "table" and json.encode(value):gsub('"', '\\"') or tostring(value)
                    		value = type(value) == "table" and json.encode(value) or tostring(value)
               			 })
            			end
            			return { values = values_array }
        			end ]]
                --		local classificationEnValue = session:getVariable("ClassificationIdEn")
                local classificationValue = session:getVariable("ClassificationIdEn") or
                                                session:getVariable("ClassificationIdAr")
                if classificationEnValue then
                    payload["Classification"] = classificationEnValue
                    freeswitch.consoleLog("INFO",
                        "Updated payload ClassificationEn to: " .. classificationEnValue .. "\n")
                else
                    freeswitch.consoleLog("ERR", "ClassificationEn session variable is nil\n")
                end
                local converted = convert_to_values_format(payload)
                encodedPayload = json.encode(converted)
            else
                encodedPayload = json.encode(payload)
            end
            --				encodedPayload = encodedPayload:gsub('"', '\\"')
            encodedPayload = encodedPayload:gsub("\n", "")
            freeswitch.consoleLog("INFO", "Payload provided: " .. encodedPayload .. "\n")
            -- finalApi = finalApi .. " -X " .. methodType .. " -d \"" .. encodedPayload .. "\""
            finalApi = finalApi .. " -X " .. methodType .. " -d '" .. encodedPayload .. "'"

        end

        if #headers > 0 then
            headers = string.gsub(headers, '"', '')
            freeswitch.consoleLog("INFO", "Headers provided: " .. headers .. "\n")
            finalApi = finalApi .. " -H \"" .. headers .. "\""
        end
        freeswitch.consoleLog("INFO", "final Api_else : " .. finalApi)
    end
    --		finalApi = finalApi .. " -s -w \"HTTPSTATUS:%{http_code}\""
    freeswitch.consoleLog("INFO", "Final API_new: " .. finalApi .. "\n")
    return finalApi
end

local function apiCall(contentType, finalApi, apiOutput)
    local inputKeys;
    if contentType == "multipart/form-data" or contentType == "audio/wav" then
        local apiResponse = execute_command(finalApi)
        freeswitch.consoleLog("INFO", "HTTP response code:" .. apiResponse)
        local endIndex = string.find(apiResponse, '+')
        local curl_response_code = tonumber(string.sub(apiResponse, endIndex + 1))
        if curl_response_code >= 200 and curl_response_code < 300 then
            local curl_response = string.sub(apiResponse, 1, endIndex - 1)
            freeswitch.consoleLog("INFO", "HTTP response:" .. curl_response)
            if #apiOutput > 2 then
                freeswitch.consoleLog("INFO", "API Output: " .. apiOutput)
                apiOutput = json.decode(apiOutput)
                freeswitch.consoleLog("INFO", "Curl Response: " .. curl_response)
                curl_response = json.decode(curl_response)
                for _, key in ipairs(apiOutput) do
                    if key.ParentResultId == nil then
                        freeswitch.consoleLog("INFO", "Found NULL ParentID")
                        session:setVariable(key.ResultFieldTag, json.encode(curl_response[key.ResultFieldName]))
                    end
                end
                for _, key in ipairs(apiOutput) do
                    if key.ParentResultId ~= nil then
                        freeswitch.consoleLog("INFO", "Found ParentID for ResultFieldTag" .. key.ResultFieldTag)
                        local parentResult = json.decode(session:getVariable(key.ParentResultId))
                        session:setVariable(key.ResultFieldTag, parentResult[key.ResultFieldName])
                    end
                end
                inputKeys = "S"
            else
                freeswitch.consoleLog("INFO", "Null apiOutput")
                inputKeys = "S"
            end
        else
            inputKeys = "F"
        end
    else
        session:execute("curl", finalApi)
        -- freeswitch.consoleLog("INFO", tostring(api_response))
        curl_response_code = tonumber(session:getVariable("curl_response_code"))
        curl_response = session:getVariable("curl_response_data")
        freeswitch.consoleLog("NOTICE", "Curl Response Code: " .. curl_response_code)
        if curl_response then
            freeswitch.consoleLog("NOTICE", "Curl Response Data: " .. curl_response)
        end
        if curl_response_code >= 200 and curl_response_code < 300 then
            if #apiOutput > 2 then
                freeswitch.consoleLog("INFO", "API Output: " .. apiOutput)
                apiOutput = json.decode(apiOutput)
                freeswitch.consoleLog("INFO", "Curl Response: " .. curl_response)
                curl_response = json.decode(curl_response)
                for _, key in ipairs(apiOutput) do
                    if key.ParentResultId == nil then
                        freeswitch.consoleLog("INFO", "Found NULL ParentID")
                        session:setVariable(key.ResultFieldTag, json.encode(curl_response[key.ResultFieldName]))
                    end
                end
                for _, key in ipairs(apiOutput) do
                    if key.ParentResultId ~= nil then
                        freeswitch.consoleLog("INFO", "Found ParentID for ResultFieldTag" .. key.ResultFieldTag)
                        local parentResult = json.decode(session:getVariable(key.ParentResultId))
                        session:setVariable(key.ResultFieldTag, parentResult[key.ResultFieldName])
                    end
                end
                inputKeys = "S"
            else
                freeswitch.consoleLog("INFO", "Null apiOutput")
                inputKeys = "S"
            end
        else
            inputKeys = "F"
        end
    end
    return inputKeys
end

local function operation_code_10_exec(session, data)
    freeswitch.consoleLog("notice", "*********** Entered Operation Code Function 10 {Play Audio} **************")
    local sound = audiopath .. data.VoiceFileId;
    freeswitch.consoleLog("notice", "Audio File to play: " .. sound)
    -- session:streamFile(sound)
    session:execute("playback", sound)
    session:sleep(500)
    local f = io.open(sound, "r")
    if f ~= nil then
        io.close(f)
        find_childNode(data)
        -- session:hangup()
    else
        freeswitch.consoleLog("notice", "Audio file " .. sound .. " Not Found. So hanging the call");
        session:hangup()
    end
end

local function operation_code_11_exec(data)
    freeswitch.consoleLog("notice", "*********** Entered Operation Code Function 11 {Play Recorded File} **************")
    local tagName = data.TagName;
    local sound = session:getVariable(tagName);
    freeswitch.consoleLog("notice", "Audio File to play: " .. sound)
    -- session:streamFile(sound)
    local f = io.open(sound, "r")
    if f ~= nil then
        session:execute("playback", sound)
        session:sleep(500)
        io.close(f)
        find_childNode(data)
    else
        freeswitch.consoleLog("notice", "Audio file " .. sound .. " Not Found. So hanging the call");
        session:hangup()
    end
end

local function operation_code_20_exec(data)
    freeswitch.consoleLog("notice", "******** Entered Operation Code Function 20 {UserInput} ************")
    freeswitch.consoleLog("notice", "Input  InputLengt value: " .. data.InputTimeLimit);
    freeswitch.consoleLog("notice", "Valid Keys : " .. data.ValidKeys);
    freeswitch.consoleLog("notice", "Input Time Limit (timeout) value: " .. data.InputTimeLimit);
    local validDigits = data.ValidKeys;
    local dtmfVerify = string.gsub(data.ValidKeys, ",", "|");
    freeswitch.consoleLog("notice", "DTMF  Verify string : " .. dtmfVerify);
    -- local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
    local min_digits = 1;
    local max_digits = data.InputLength;
    local timeLimit = data.InputTimeLimit * 1000 or 5000
    local invalidaudiofile = audiopath .. data.InvalidInputVoiceFileId;
    local repeat_limit;
    if data.IsRepetitive == true then
        repeat_limit = data.RepeatLimit;
    else
        repeat_limit = 0;
    end

    for i = 0, repeat_limit, 1 do
        freeswitch.consoleLog("notice", "DTMF Validation loop entered ")
        session:setVariable("read_terminator_used", "")
        -- local digits = session:getDigits(max_digits, "#", timeLimit);
        digits = session:read(min_digits, max_digits, "", timeLimit, "#")
        terminator = session:getVariable("read_terminator_used")
        -- local digits = session:playAndGetDigits (min_digits, max_digits , 1 ,timeLimit,'#','', invalidaudiofile,(dtmfVerify))
        freeswitch.consoleLog("notice", "DTMF Input received: " .. digits)
        freeswitch.consoleLog("notice", "#digit: " .. #digits)
        freeswitch.consoleLog("notice", "DTMF InputLength Entered by User: " .. #digits)
        if #digits == max_digits then
            freeswitch.consoleLog("notice", "DTMF Digits received from user : " .. digits)
            function characterExistsInSet(char, set)
                return set:find(char, 1, true) ~= nil
            end
            local inputString = digits
            local allowedSet = validDigits;
            local allowedSet = allowedSet:gsub(",", "")
            local allCharactersValid = true
            for i = 1, #inputString do
                local char = inputString:sub(i, i)
                if not characterExistsInSet(char, allowedSet) then
                    allCharactersValid = false
                    break
                end
            end
            if allCharactersValid then
                freeswitch.consoleLog("notice", "valid Character")
                session:setVariable(data.TagName, digits)
                print("session:setVariable(" .. data.TagName .. ", " .. digits .. ")")
                inputdigits = "#"
                find_childNode_with_dtmfinput(inputdigits, data)
                break
            else
                session:execute("playback", invalidaudiofile)
            end
        elseif #digits > 0 and #digits < max_digits then
            freeswitch.consoleLog("notice", "Invalid DTMF Input received!! ")
            if i == repeat_limit then
                freeswitch.consoleLog("notice", "Setting the DTMF Input as X ")
                digits = "X"
                find_childNode_with_dtmfinput(digits, data)
            else
                session:execute("playback", invalidaudiofile)
            end
        elseif #digits == 0 then
            freeswitch.consoleLog("notice", "No DTMF Input received!!")
            if terminator ~= "#" and data.TimeLimitResponseType == 20 then
                digits = "D"
                find_childNode_with_dtmfinput(digits, data)
            elseif data.TimeLimitResponseType == 10 and i == repeat_limit then
                digits = "X"
                find_childNode_with_dtmfinput(digits, data)
            else
                session:execute("playback", invalidaudiofile)

            end
        else
            freeswitch.consoleLog("notice", "Some Condition got Failed")
        end
    end
end

local function operation_code_30_exec(data)
    freeswitch.consoleLog("notice", "******** Entered Operation Code Function 30 {InputWithAudio} ************")
    local min_digits = 1;
    local ivr_menu_digit_leg = 1;
    local sound = audiopath .. data.VoiceFileId;
    local timeLimit = data.InputTimeLimit * 1000 or 5000;
    freeswitch.consoleLog("notice", "Input Time Limit (timeout) value: " .. timeLimit);
    local invalidaudiofile = audiopath .. data.InvalidInputVoiceFileId or audiopath .. "InvalidSelection.wav";
    local dtmfVerify = string.gsub(data.ValidKeys, ",", "|");
    local dtmfVerify_2 = string.gsub(dtmfVerify, "*", "\\*")
    local attempts;
    freeswitch.consoleLog("notice", "Is Repetitive type: " .. type(data.IsRepetitive));
    if data.IsRepetitive == true then
        attempts = data.RepeatLimit or 3;
    else
        attempts = 1
    end
    local dtmf_digits;
    freeswitch.consoleLog("notice", "Regex DTMF Validation: " .. dtmfVerify_2);
    freeswitch.consoleLog("notice", "Audio File Name: " .. sound);
    freeswitch.consoleLog("notice", "Invalid Audio File Name: " .. invalidaudiofile);
    freeswitch.consoleLog("notice", "Valid DTMF Digits: " .. data.ValidKeys);
    freeswitch.consoleLog("notice", "Attempts: " .. attempts)
    session:sleep(500)
    dtmf_digits = session:playAndGetDigits(min_digits, ivr_menu_digit_leg, attempts, timeLimit, '', sound,
        invalidaudiofile, (dtmfVerify_2))
    -- session:playAndGetDigits ( min_digits, max_digits, max_attempts, timeout, terminators, prompt_audio_files, input_error_audio_files,digit_regex, variable_name, digit_timeout, transfer_on_failure)
    -- need pause before stream file
    session:setVariable("slept", "false");
    freeswitch.consoleLog("notice", "DTMF Entered: " .. dtmf_digits)
    if dtmf_digits and #dtmf_digits > 0 then
        if data.TagName ~= nil then
            if data.TagName == "LanguageSelected" then
                freeswitch.consoleLog("info", "::Found Language Selection TagName::")
                setLanguage(dtmf_digits)
            elseif data.TagValuePrefix ~= nil then
                session:setVariable(data.TagName, data.TagValuePrefix .. dtmf_digits)
            else
                session:setVariable(data.TagName, dtmf_digits)
            end
        end
        find_childNode_with_dtmfinput(dtmf_digits, data);
    else
        if data.TimeLimitResponseType == 10 then
            freeswitch.consoleLog("notice", "DTMF Input Not received!!, Setting input as X ")
            -- session:hangup()
            dtmf_digits = "X"
            find_childNode_with_dtmfinput(dtmf_digits, data);
        else
            freeswitch.consoleLog("notice",
                "DTMF Input Not received!!, Setting default input as " .. data.DeafultInput ..
                    " based on TimeLimitResponseType:  " .. data.TimeLimitResponseType)
            dtmf_digits = data.DeafultInput;
            if data.TagName ~= nil then
                if data.TagName == "LanguageSelected" then
                    freeswitch.consoleLog("info", "::Found Language Selection TagName::")
                    setLanguage(dtmf_digits)
                else
                    session:setVariable(data.TagName, dtmf_digits)
                end
            end
            find_childNode_with_dtmfinput(dtmf_digits, data);
        end
    end
end -- end function

local function operation_code_31_exec(data)
    freeswitch.consoleLog("notice", "******** Entered Operation Code Function 31 {InputWithAudio} ************")
    local min_digits = 1;
    local ivr_menu_digit_leg = 1;
    local tagName = data.TagName;
    local sound = session:getVariable(tagName);
    local timeLimit = data.InputTimeLimit * 1000 or 5000;
    freeswitch.consoleLog("notice", "Input Time Limit (timeout) value: " .. timeLimit);
    local invalidaudiofile = audiopath .. data.InvalidInputVoiceFileId or audiopath .. "InvalidSelection.wav";
    local dtmfVerify = string.gsub(data.ValidKeys, ",", "|");
    local dtmfVerify_2 = string.gsub(dtmfVerify, "*", "\\*")
    local attempts;
    freeswitch.consoleLog("notice", "Is Repetitive type: " .. type(data.IsRepetitive));
    if data.IsRepetitive == true then
        attempts = data.RepeatLimit or 3;
    else
        attempts = 1
    end
    local dtmf_digits;
    freeswitch.consoleLog("notice", "Regex DTMF Validation: " .. dtmfVerify_2);
    freeswitch.consoleLog("notice", "Audio File Name: " .. sound);
    freeswitch.consoleLog("notice", "Invalid Audio File Name: " .. invalidaudiofile);
    freeswitch.consoleLog("notice", "Valid DTMF Digits: " .. data.ValidKeys);
    freeswitch.consoleLog("notice", "Attempts: " .. attempts)
    session:sleep(500)
    dtmf_digits = session:playAndGetDigits(min_digits, ivr_menu_digit_leg, attempts, timeLimit, '', sound,
        invalidaudiofile, (dtmfVerify_2))
    -- session:playAndGetDigits ( min_digits, max_digits, max_attempts, timeout, terminators, prompt_audio_files, input_error_audio_files,digit_regex, variable_name, digit_timeout, transfer_on_failure)
    -- need pause before stream file
    session:setVariable("slept", "false");
    freeswitch.consoleLog("notice", "DTMF Entered: " .. dtmf_digits)
    if dtmf_digits and #dtmf_digits > 0 then
        find_childNode_with_dtmfinput(dtmf_digits, data);
    else
        if data.TimeLimitResponseType == 10 then
            freeswitch.consoleLog("notice", "DTMF Input Not received!!, Setting input as X ")
            -- session:hangup()
            dtmf_digits = "X"
            find_childNode_with_dtmfinput(dtmf_digits, data);
        else
            freeswitch.consoleLog("notice",
                "DTMF Input Not received!!, Setting default input as " .. data.DeafultInput ..
                    " based on TimeLimitResponseType:  " .. data.TimeLimitResponseType)
            dtmf_digits = data.DeafultInput;
            find_childNode_with_dtmfinput(dtmf_digits, data);
        end
    end
end -- end function

local function operation_code_40_exec(data)
    freeswitch.consoleLog("notice", "\n *** Entered Operation Code 40 ***\n")
    local recordTimeLimit, recordfilename;
    local silence_hits = data.InputTimeLimit or 5;
    local silence_threshold = 200;
    local recordingTypeId = data.RecordingTypeId;
    for _, recordData in pairs(recording_config.RecordingType) do
        if recordData.RecordingTypeId == recordingTypeId then
            freeswitch.consoleLog("info", "Found Recording ID")
            recordTimeLimit = recordData.RecordTimeLimit
            recordfilename = recordData.TypePrefix
            freeswitch.consoleLog("info",
                "RecordTime Limit : " .. recordTimeLimit .. " Record filename: " .. recordfilename);
            break
        end
    end
    recordfilename = recordfilename .. "_" .. call_uuid .. ".wav";
    recording_filename = string.format('%s%s', recording_dir, recordfilename)
    freeswitch.consoleLog("NOTICE", "\n Recording time limit Seconds: " .. recordTimeLimit .. " :: silence Secs: " ..
        silence_hits)
    freeswitch.consoleLog("notice", "\n Recording File Name: " .. recording_filename);
    session:execute("export", "nolocal:playback_terminators=#")
    -- local CallerMessage = session:recordFile(recording_filename, tonumber(recordTimeLimit), tonumber(silence_threshold), tonumber(silence_hits));
    local callerMessage = session:execute("record", recording_filename .. " " .. tonumber(recordTimeLimit) .. " " ..
        silence_threshold .. " " .. silence_hits);
    -- session:consoleLog("info", "session:recordFile() = " .. callerMessage )
    function hasSoundActivity(wavFilePath)
        local cmd = string.format("sox %s -n stat 2>&1 | grep -i 'RMS     amplitude'  | awk '{print $3}'", wavFilePath)
        freeswitch.consoleLog("NOTICE", "Sox Command :: " .. cmd)
        local handle = io.popen(cmd)
        local result = handle:read("*a")
        handle:close()

        -- Check if the result is empty or not a valid number
        if result and tonumber(result) then
            local amplitude = tonumber(result)
            -- Adjust the threshold as needed
            local threshold = 0.001
            freeswitch.consoleLog("NOTICE", "Sox RMS Amplitude output :: " .. amplitude)

            -- Check if the amplitude is above the threshold
            if amplitude >= threshold then
                return true
            end
        end

        return false
    end

    if hasSoundActivity(recording_filename) then
        freeswitch.consoleLog("NOTICE", "The WAV file contains user voice or sound.\n")
        -- session:execute("playback", recording_filename)
        local tag_name = data.TagName
        freeswitch.consoleLog("NOTICE", "Tag Name: " .. tag_name)
        session:setVariable(tag_name, recording_filename);
        local input = "S"
        find_childNode_with_dtmfinput(input, data);
    else
        -- freeswitch.consoleLog("NOTICE", "The WAV file does not have user voice or sound.\n")
        print("NOTICE", "The WAV file does not have user voice or sound.\n")
        local input = "D"
        find_childNode_with_dtmfinput(input, data);
    end

end
local function operation_code_100_exec(data)
    freeswitch.consoleLog("notice", "\n *** Operation code 100 func {Agent Transfer} ***\n")
    local extensions = {}
    local ext_not_reg = "error/user_not_registered"
    for key, value in pairs(agent_extensions.Extensions) do
        if value.IsAgent == false then
            api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Idle")
        else
            local extension_status = api:executeString("sofia_contact " .. value.ExtensionCode)
            freeswitch.consoleLog("notice", value.ExtensionCode .. " Extension Status : " .. extension_status)
            if extension_status ~= ext_not_reg then
                -- api:executeString("callcenter_config agent add " .. value.ExtensionCode .. " Callback")
                api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " Available")
                api:executeString("callcenter_config agent set contact " .. value.ExtensionCode .. " " ..
                                      extension_status);
                api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Waiting")
                -- api:executeString("callcenter_config tier add leader-ivr@default " .. value.ExtensionCode .. " 1 1")
                extensions[#extensions + 1] = value.ExtensionCode;
                local agent_state = api:executeString("callcenter_config agent get state " .. agent_extension)
                freeswitch.consoleLog("notice", "Agent " .. value.ExtensionCode .. " State: " .. agent_state .. "\n")
            else
                freeswitch.consoleLog("notice", "Extension " .. value.ExtensionCode ..
                    " Not registered . Changing status to Logged Out ..")
                api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " 'Logged Out'")
            end
        end
    end
    session:execute("sleep", "500")
    session:execute("callcenter", "ccm-ivr@default")
end

local function operation_code_101_exec(data)
    freeswitch.consoleLog("notice", "\n *** Operation code 101 func {Agent Transfer with Evaluation} ***\n")
    local extensions = {}
    local ext_not_reg = "error/user_not_registered"
    for key, value in pairs(agent_extensions.Extensions) do
        if value.IsAgent == false then
            api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Idle")
        else
            local extension_status = api:executeString("sofia_contact " .. value.ExtensionCode)
            freeswitch.consoleLog("notice", value.ExtensionCode .. " Extension Status : " .. extension_status)
            if extension_status ~= ext_not_reg then
                -- Check agent's DND status
                local dnd_status = api:executeString("global_getvar agent_" .. value.ExtensionCode .. "_status")
                freeswitch.consoleLog("notice", "Agent " .. value.ExtensionCode .. " DND Status: " ..
                    (dnd_status or "Not Set") .. "\n")
                -- api:executeString("callcenter_config agent add " .. value.ExtensionCode .. " Callback")
                local agent_state = api:executeString("callcenter_config agent get state " .. value.ExtensionCode)
                freeswitch.consoleLog("notice", "Agent " .. value.ExtensionCode .. " State: " .. agent_state .. "\n")
                if dnd_status == "Busy" then
                    freeswitch.consoleLog("notice",
                        "Agent " .. value.ExtensionCode .. " is in DND. Skipping this agent.\n")
                else
                    local agent_state = api:executeString("callcenter_config agent get state " .. value.ExtensionCode)
                    freeswitch.consoleLog("notice", "Agent " .. value.ExtensionCode .. " State: " .. agent_state .. "\n")
                    if agent_state == "In a queue call" then
                        freeswitch.consoleLog("notice", "Agent " .. value.ExtensionCode ..
                            " is currently in a queue call. Skipping this agent.\n")
                    else
                        api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " Available")
                        api:executeString("callcenter_config agent set contact " .. value.ExtensionCode .. " " ..
                                              extension_status);
                        api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Waiting")
                        -- api:executeString("callcenter_config tier add leader-ivr@default " .. value.ExtensionCode .. " 1 1")
                        extensions[#extensions + 1] = value.ExtensionCode;
                    end
                end
            else
                freeswitch.consoleLog("notice", "Extension " .. value.ExtensionCode ..
                    " Not registered . Changing status to Logged Out ..")
                api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " 'Logged Out'")
            end
        end
    end
    session:execute("sleep", "500")
    session:setAutoHangup(false)
    session:setVariable("cc_last_nodeId", data.NodeId)
    session:execute("transfer", "OPCODE_101 XML public")
end

local function operation_code_105_exec(data)
    freeswitch.consoleLog("notice", "******** Entered Operation Code Function 105 {Extension Tranfer} ************")
    freeswitch.consoleLog("notice", "Input  InputLengt value: " .. data.InputTimeLimit);
    freeswitch.consoleLog("notice", "Valid Keys : " .. data.ValidKeys);
    freeswitch.consoleLog("notice", "Input Time Limit (timeout) value: " .. data.InputTimeLimit);
    local validDigits = data.ValidKeys;
    local dtmfVerify = string.gsub(data.ValidKeys, ",", "|");
    freeswitch.consoleLog("notice", "DTMF  Verify string : " .. dtmfVerify);
    -- local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
    local min_digits = 1;
    local max_digits = data.InputLength;
    local timeLimit = data.InputTimeLimit * 1000 or 5000
    local invalidaudiofile = audiopath .. data.InvalidInputVoiceFileId;
    local repeat_limit;
    if data.IsRepetitive == true then
        repeat_limit = data.RepeatLimit;
    else
        repeat_limit = 0;
    end
    session:setVariable("read_terminator_used", "")
    -- local digits = session:getDigits(max_digits, "#", timeLimit);
    digits = session:read(min_digits, max_digits, "", timeLimit, "#")
    terminator = session:getVariable("read_terminator_used")
    -- local digits = session:playAndGetDigits (min_digits, max_digits , 1 ,timeLimit,'#','', invalidaudiofile,(dtmfVerify))
    freeswitch.consoleLog("notice", "DTMF Input received: " .. digits)
    freeswitch.consoleLog("notice", "DTMF InputLength Entered by User: " .. #digits)
    if #digits == max_digits then
        freeswitch.consoleLog("notice", "DTMF Digits received from user : " .. digits)
        function characterExistsInSet(char, set)
            return set:find(char, 1, true) ~= nil
        end
        local inputString = digits
        local allowedSet = validDigits;
        local allowedSet = allowedSet:gsub(",", "")
        local allCharactersValid = true
        for i = 1, #inputString do
            local char = inputString:sub(i, i)
            if not characterExistsInSet(char, allowedSet) then
                allCharactersValid = false
                break
            end
        end
        if allCharactersValid then
            session:setVariable(data.TagName, digits)
            -- dial_string = digits .." XML public";
            cmd = "user_exists id " .. digits .. " " .. domain
            freeswitch.consoleLog("INFO", "Extesnion validation command: " .. cmd)
            found = api:executeString(cmd)
            if found == "true" then
                session:setVariable("hangup_after_bridge", "true")
                -- session:execute("transfer",dial_string)
                retries = 0;
                max_retries = 3;
                freeswitch.consoleLog("INFO", "Max Retries: " .. max_retries)
                second_session = null;
                -- dialString = "{originate_timeout=30,hangup_after_bridge=true}user/"..digits.."@"..domain
                dialString = "{origination_caller_id_name=" .. caller_name .. ",origination_caller_id_number=" ..
                                 caller_id .. ",originate_timeout=30,hangup_after_bridge=true}user/" .. digits .. "@" ..
                                 domain
                -- session:execute("playback", "local_stream://moh");
                --[[  repeat  
				        -- Create session2
					        retries = retries + 1;
						if retries > 1 then
							session:execute("sleep","5000")
						end
					        freeswitch.consoleLog("notice", "*********** Dialing: " .. dialString .. " Try: "..retries.." ***********\n");
						session:execute("set","ringback=$${fr-ring}")
					        second_session = freeswitch.Session(dialString);
						if (second_session:ready()) then
							freeswitch.consoleLog("WARNING","second leg answered\n")
							freeswitch.bridge(session, second_session)
							freeswitch.consoleLog("WARNING","After bridge\n")
							if (second_session:ready()) then second_session:hangup(); end
							break
						else

						end
					        local hcause = second_session:hangupCause();
					        freeswitch.consoleLog("notice", "*********** Leg2: " .. hcause .. " Try: " .. retries .. " ***********\n");
					until not (retries < max_retries and hcause =="DESTINATION_OUT_OF_ORDER") ]]
                second_session = freeswitch.Session(dialString);
                local hcause = second_session:hangupCause();
                if (second_session:ready()) then
                    freeswitch.consoleLog("WARNING", "second leg answered\n")
                    freeswitch.bridge(session, second_session)
                    -- freeswitch.consoleLog("WARNING","After bridge\n")
                    if (second_session:ready()) then
                        second_session:hangup();
                    end
                end
                -- if (session:ready()) then session:hangup(); end
                if hcause ~= "SUCCESS" then
                    freeswitch.consoleLog("WARNING", ":::: Extension is not registered or un reachable :::" .. hcause)
                    session:set_tts_params("flite", "slt");
                    session:execute("sleep", "1000")
                    session:speak("Hello! The entered Extension is not available or Busy");
                    session:execute("sleep", "1000")
                    session:hangup()
                    -- freeswitch.consoleLog("notice","Setting the DTMF Input as F ")
                    -- inputKey = "F"
                    -- find_childNode_with_dtmfinput(inputKey,data)
                end
            else
                freeswitch.consoleLog("NOTICE", "Extension Not Found")
                -- session:set_tts_parms("flite", "awb");
                -- session:speak("Hello! The entered Extension is not valid");
                inputKey = "F"
                find_childNode_with_dtmfinput(inputKey, data)
            end
        else
            session:execute("playback", invalidaudiofile)
        end
    elseif #digits > 0 and #digits < max_digits then
        freeswitch.consoleLog("notice", "Invalid DTMF Input received!! ")
        freeswitch.consoleLog("notice", "Setting the DTMF Input as F ")
        digits = "F"
        find_childNode_with_dtmfinput(digits, data)
    elseif #digits == 0 then
        freeswitch.consoleLog("notice", "No DTMF Input received!!")
        -- session:execute("playback", invalidaudiofile)
        digits = "F"
        find_childNode_with_dtmfinput(digits, data)
    else
        freeswitch.consoleLog("notice", "Some Condition got Failed")
    end
end

local function operation_code_107_exec(data)
    freeswitch.consoleLog("INFO", "Operation Code 107 {Direct Agent transfer to extension:: }" .. data.ValidKeys)
    extension = data.ValidKeys
    cmd = "user_exists id " .. extension .. " " .. domain
    found = api:executeString(cmd)
    freeswitch.consoleLog("notice", "Extension Output result" .. found)
    if found == 'true' then
        freeswitch.consoleLog("notice", "Extesnion found")
        -- dial_string = digits .." XML public";
        -- session:execute("transfer",dial_string);
        dialString = "{origination_caller_id_name=" .. caller_name .. ",origination_caller_id_number=" .. caller_id ..
                         ",originate_timeout=30,hangup_after_bridge=true}user/" .. extension .. "@" .. domain
        freeswitch.consoleLog("INFO", "DailString: " .. dialString)
        session:execute("set", "ringback=${us-ring}")
        second_session = freeswitch.Session(dialString)
        if (second_session:ready()) then
            freeswitch.consoleLog("WARNING", "second leg answered\n")
            freeswitch.bridge(session, second_session)
            -- freeswitch.consoleLog("WARNING","After bridge\n")
        else
            freeswitch.consoleLog("WARNING", "second leg failed\n")
            session:set_tts_params("flite", "slt");
            session:execute("sleep", "1000")
            session:speak("Hello! The entered Extension is not available or Busy");
            session:execute("sleep", "1000")
            session:hangup()
        end
    else
        freeswitch.consoleLog("NOTICE", "Extension Not Found")
        -- session:set_tts_parms("flite", "awb");
        -- session:speak("The pre defined Extension is not valid");
        inputKey = "F"
        find_childNode_with_dtmfinput(inputKey, data)
    end
end

local function operation_code_108_exec(data)
    freeswitch.consoleLog("INFO", "Operation Code 107 {External line transfer to extension:: }" .. data.ValidKeys)
    extension = data.ValidKeys
    -- cmd = "user_exists id "..extension.." "..domain
    -- found = api:executeString(cmd)
    -- freeswitch.consoleLog("notice","Extension Output result"..found)
    -- if found == 'true' then
    if extension ~= nil then
        freeswitch.consoleLog("notice", "Extesnion found")
        dialString = "sofia/gateway/fxax-gateway/" .. extension
        second_session = freeswitch.Session(dialString)
        if (second_session:ready()) then
            freeswitch.consoleLog("WARNING", "second leg answered\n")
            freeswitch.bridge(session, second_session)
            freeswitch.consoleLog("WARNING", "After bridge\n")
        else
            freeswitch.consoleLog("WARNING", "second leg failed\n")
        end
    else
        freeswitch.consoleLog("NOTICE", "Extension Not Found")
        session:set_tts_parms("flite", "awb");
        session:speak("The pre defined Extension is not valid");
        inputKey = "F"
        find_childNode_with_dtmfinput(inputKey, data)
    end
end

local function getLocationID(getLocationResponse, location_index)
    -- Decode JSON string into Lua table
    local response_table, err = json.decode(getLocationResponse)
    if not response_table then
        return nil, "Failed to decode JSON: " .. (err or "unknown error")
    end

    -- Defensive checks
    if not response_table.result or not response_table.result.locations then
        return nil, "Invalid response structure: Missing result.locations"
    end

    local locations = response_table.result.locations

    -- Check if location_index is valid
    if location_index < 1 or location_index > #locations then
        return nil, "location_index out of range"
    end

    local selected_location = locations[location_index]
    if not selected_location or not selected_location.locationID then
        return nil, "locationID not found for index " .. tostring(location_index)
    end

    return selected_location.locationID, nil
end

-- Function to get classification ID from API response
local function getClassificationID(getClassificationResponse, classification_index, subclassification_index)
    local parsed = json.decode(getClassificationResponse)
    if not (parsed and parsed.data and parsed.data.hierarchy) then
        return nil, "Invalid JSON structure"
    end

    local main_class = parsed.data.hierarchy[classification_index]
    if not main_class then
        return nil, "Main classification not found"
    end

    local children = main_class.Children
    if children and type(children) == "table" and #children > 0 then
        local sub_class = children[subclassification_index]
        if sub_class and sub_class.ID then
            return sub_class.ID
        end
    end

    -- fallback to parent ID if no child found
    if main_class.ID then
        return main_class.ID
    end

    return nil, "No valid classification ID found"
end

local function strip_quotes(str)
    if str then
        return str:gsub('^"(.-)"$', '%1')
    end
    return str
end

local function update_incident_with_attachment(recordID, attachment_id)
    freeswitch.consoleLog("INFO", "Entering update_incident")
    -- Check input
    if not recordID or not attachment_id then
        freeswitch.consoleLog("ERROR", "recordID or attachmentID missing\n")
        return
    end

    -- API URL (replace :recordID in URL with actual recordID)
    local url = string.format(
        "https://automax.discretal.com/api/compose/namespace/432712349708976129/module/432712349708910593/record/%s",
        recordID)
    local access_token = session:getVariable("Access_token")
    freeswitch.consoleLog("INFO", "Access token from session: " .. tostring(access_token) .. "\n")
    access_token = access_token:gsub('^"(.*)"$', '%1')
    local token = "Bearer " .. access_token
    local mobilenumber = session:getVariable("MobileNumberEn") or session:getVariable("MobileNumberAr")
    freeswitch.consoleLog("INFO", "Mob number  from session: " .. tostring(mobilenumber) .. "\n")
    -- local CallerNameTextEn = session:getVariable("CallerNameTextEn") or ""
    local CallerNameTextEn = strip_quotes(session:getVariable("CallerNameTextEn") or "")
    local ClassificationIdEn = session:getVariable("ClassificationIdEn") or ""
    local IncidentDetailsTextEn = strip_quotes(session:getVariable("IncidentDetailsTextEn") or "")
    --	local IncidentDetailsTextEn = session:getVariable("IncidentDetailsTextEn") or ""
    local LocationIdEn = session:getVariable("LocationIdEn") or ""
    local attachmentID = session:getVariable("attachment_id") or "" -- adjust key if needed
    local map_value = json.encode({
        coordinates = {0, 0}
    })
    -- Prepare the JSON payload

    local payload_table = {
        values = {{
            name = "Channel",
            value = "IVR"
        }, {
            name = "Criticality",
            value = "Low"
        }, {
            name = "Caller_name",
            value = CallerNameTextEn
        }, {
            name = "Last_call_date",
            value = ""
        }, {
            name = "National_ID",
            value = "IND"
        }, {
            name = "Mobile_number",
            value = "+91" .. mobilenumber
        }, {
            name = "Classification",
            value = ClassificationIdEn
        }, {
            name = "Incident_reason",
            value = IncidentDetailsTextEn
        }, {
            name = "Incident_Description",
            value = IncidentDetailsTextEn
        }, {
            name = "Map",
            value = map_value
        }, -- Proper JSON string with quotes
        {
            name = "Location",
            value = LocationIdEn
        }, {
            name = "District",
            value = LocationIdEn
        }, -- You can change if district differs
        {
            name = "Status",
            value = "Open"
        }, {
            name = "Attachments",
            value = attachmentID
        }}
    }
    local payload = json.encode(payload_table)
    local curl_cmd = string.format("curl -s -X POST '%s' " .. "-H 'Content-Type: application/json' " ..
                                       "-H 'Accept: application/json' " .. "-H 'Authorization: %s' " .. -- %s will insert Bearer <token> without quotes
    "-d '%s'", url, token, payload)

    freeswitch.consoleLog("info", "CURL CMD: " .. curl_cmd .. "\n")
    -- Execute curl command
    local handle = io.popen(curl_cmd)
    local result = handle:read("*a")
    handle:close()
    freeswitch.consoleLog("INFO", "Update Incident API Response: " .. result .. "\n")
end

local function operation_code_111_exec(data)
    local api_id = data.APIId
    freeswitch.consoleLog("NOTICE", "API ID: " .. api_id)
    local methodType, contentType, serviceURL, apiInputdata, inputKeys
    for _, api in pairs(webApiData) do
        if api.apiId == api_id then
            methodType = api.methodType
            contentType = api.inputMediaType
            serviceURL = api.serviceURL
            if type(api.apiInput) == "string" then
                apiInputdata = json.decode(api.apiInput)
            else
                apiInputdata = api.apiInput -- already a table
            end
            -- apiInputdata = json.decode(api.apiInput)
            apiOutput = api.apiOutput
            break
        end
    end
    freeswitch.consoleLog("INFO",
        "Method:: " .. methodType .. " :: contentType :: " .. contentType .. " :: serviceURL ::" .. serviceURL ..
            " :: apiInput ::" .. json.encode(apiInputdata))
    local finalApi = constructApi(methodType, contentType, serviceURL, apiInputdata)
    freeswitch.consoleLog("NOTICE", "Final modified API: " .. finalApi)
    --[[			local access_token = session:getVariable("Access_token")
			local authToken = "Bearer " .. access_token
			local getUrl = "curl -s -X GET 'https://automax.discretal.com/api/classifications/hierarchy?client=mobile' -H 'Authorization: " .. authToken .. "'"
			local handle = io.popen(getUrl)
			local getResponse = handle:read("*a")
			handle:close()
			freeswitch.consoleLog("INFO", "Classification Hierarchy Response: " .. getResponse .. "\n")]]
    --		freeswitch.consoleLog("INFO", "Method:: "..methodType.." :: contentType :: "..contentType.." :: serviceURL ::"..serviceURL.." :: apiInput ::".. json.encode(apiInputdata))
    if contentType == "application/json" then
        freeswitch.consoleLog("NOTICE", "Final modified API in application/json: " .. finalApi)
        local curlCmd = "curl " .. finalApi
        --		   local apiResponse = execute_command(finalApi)
        local handle = io.popen(curlCmd)
        local apiResponse = handle:read("*a")
        handle:close()

        freeswitch.consoleLog("INFO", "HTTP response: " .. tostring(apiResponse) .. "\n")
        -- Match + followed by digits at the end
        local curl_response_code = tonumber(apiResponse:match("%+(%d+)$"))

        -- Remove the +HTTP_CODE from the response to get only JSON
        local curl_response = apiResponse:gsub("%+%d+$", "")

        freeswitch.consoleLog("INFO", "Response body: " .. curl_response .. "\n")
        freeswitch.consoleLog("INFO", "HTTP code: " .. tostring(curl_response_code) .. "\n")

        -- end		   

        --[[       if curl_response_code >=200 and curl_response_code < 300 then
                       --local curl_response = string.sub(apiResponse, 1, endIndex-1)
		       --freeswitch.consoleLog("INFO","HTTP response:"..curl_response)
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
                
	end ]]
        if curl_response_code >= 200 and curl_response_code < 300 then
            freeswitch.consoleLog("INFO", "Curl Response: " .. curl_response .. "\n")
            local success, decoded_response = pcall(json.decode, curl_response)
            if success and decoded_response and decoded_response.response and decoded_response.response.recordID then
                local recordID = decoded_response.response.recordID
                session:setVariable("incident_no_reponse", recordID)
                local record_id = session:getVariable("recordID")
                local attachment_id = session:getVariable("attachment_id")
                freeswitch.consoleLog("INFO", "attachment_id = " .. attachment_id .. "\n")
                freeswitch.consoleLog("INFO", "Set incident_no_reponse = " .. recordID .. "\n")
                if recordID and recordID ~= "" and attachment_id and attachment_id ~= "" then
                    freeswitch.consoleLog("INFO",
                        "Calling update_incident_with_attachment with recordID: " .. recordID .. " and attachment_id: " ..
                            attachment_id .. "\n")
                    update_incident_with_attachment(recordID, attachment_id)
                else
                    freeswitch.consoleLog("INFO",
                        "Skipping update_incident_with_attachment, missing recordID or attachment_id\n")
                end
                inputKeys = "S"
            else
                freeswitch.consoleLog("WARNING", "recordID not found or JSON decode failed\n")
                inputKeys = "F"
            end
        else
            inputKeys = "F"
        end

    else
        freeswitch.consoleLog("INFO", "Executing")
        --	local finalApi = [[https://automax.discretal.com/auth/oauth2/token -s -w '+%{http_code}' -H "Content-Type: application/x-www-form-urlencoded" -X POST -d "scope=profile+api&grant_type=client_credentials" -H "Authorization: Basic NDQxMTE5NzQ5MTM4NDE1NjE3OmxKVER1dENxUHljSUVJVUxYZ29JamF2S3NvZ1dtNEZDSmNXeHhiNExFbXJxcWtrblN1eVM5MDU4UGtTREpyWjc="]]

        -- Extract base URL
        local url = finalApi:match("^(https://%S+)")
        -- Extract all headers
        local headers = {}
        for h in finalApi:gmatch('%-H%s+"[^"]+"') do
            table.insert(headers, h)
        end
        -- Extract -d data
        -- local data = finalApi:match('%-d%s+"([^"]+)"')
        --	local data = finalApi:match('%-d%s*"([^"]+)"')
        local data = finalApi:match('%-d%s*[\'"]([^\'"]+)[\'"]')

        -- Reconstruct
        local curlCmd = 'curl -s -k -X POST \\\n'
        curlCmd = curlCmd .. '  -d "' .. data .. '" \\\n'
        for _, h in ipairs(headers) do
            curlCmd = curlCmd .. '  ' .. h .. ' \\\n'
        end
        curlCmd = curlCmd .. '  ' .. url

        -- Print the result
        freeswitch.consoleLog("NOTICE", "Formatted CURL Command:\n" .. curlCmd .. "\n")

        -- Run the command and capture output
        local handle = io.popen(curlCmd)
        local response = handle:read("*a")
        handle:close()

        -- Print full response for debugging
        freeswitch.consoleLog("NOTICE", "Token Response: " .. response .. "\n")

        -- Try to extract the body and status code (check if there's a valid response)
        local body, status_code = response:match("^(.*)\n(%d%d%d)$")

        if not body or not status_code then
            body = response
            status_code = 200 -- Assuming success if no error in response
        end

        -- Clean up body (remove extra spaces)
        body = body and body:gsub("^%s+", ""):gsub("%s+$", "")
        status_code = tonumber(status_code)
        -- Log full details
        freeswitch.consoleLog("NOTICE", "HTTP Status Code: " .. tostring(status_code))
        freeswitch.consoleLog("NOTICE", "Curl Response Body: " .. tostring(body))

        local curl_response_code = status_code
        local curl_response = body

        -- freeswitch.consoleLog("INFO", tostring(api_response))
        --	curl_response_code = tonumber(session:getVariable("curl_response_code"))
        --	curl_response      = session:getVariable("curl_response_data")
        --	freeswitch.consoleLog("NOTICE","Curl Response Code: "..curl_response_code)
        if curl_response then
            freeswitch.consoleLog("NOTICE", "Curl Response Data: " .. curl_response)
        end
        if curl_response_code >= 200 and curl_response_code < 300 then
            if #apiOutput > 2 then
                freeswitch.consoleLog("INFO", "API Output: " .. apiOutput)
                apiOutput = json.decode(apiOutput)
                freeswitch.consoleLog("INFO", "Curl Response: " .. curl_response)
                local curl_response_decoded = json.decode(curl_response)
                if curl_response_decoded then
                    freeswitch.consoleLog("INFO", "Decoded curl_response: " .. json.encode(curl_response_decoded))
                else
                    freeswitch.consoleLog("ERROR", "Failed to decode curl_response")
                    return
                end
                -- curl_response = json.decode(curl_response)
                if curl_response_decoded then
                    for _, key in ipairs(apiOutput) do
                        if key.ParentResultId == nil then
                            freeswitch.consoleLog("INFO", "Found NULL ParentID")
                            --	local value = curl_response_decoded[key.ResultFieldName]
                            -- Check if the field name matches "access_token"
                            local fieldName = key.ResultFieldName
                            if fieldName == "token" then
                                fieldName = "access_token" -- Adjust to actual field in curl_response_decoded
                                --[[	local access_token = session:getVariable("Access_token")
					local authToken = "Bearer " .. access_token
					local getUrl = "curl -s -X GET 'https://automax.discretal.com/api/classifications/hierarchy?client=mobile' -H 'Authorization: " .. authToken .. "'"
	
					local handle = io.popen(getUrl)
					local getResponse = handle:read("*a")
					handle:close()
					freeswitch.consoleLog("INFO", "Classification Hierarchy Response: " .. getResponse .. "\n")]]
                            end

                            -- Try to access the value
                            local value = curl_response_decoded[fieldName]
                            if value then
                                -- session:setVariable(key.ResultFieldTag, json.encode(value))
                                session:setVariable(key.ResultFieldTag, json.encode(value))
                                local access_token = session:getVariable("Access_token")
                                access_token = access_token:gsub('^"(.*)"$', '%1')
                                local authToken = "Bearer " .. access_token
                                local getclassificationurl =
                                    "curl -s -X GET 'https://automax.discretal.com/api/classifications/hierarchy?client=mobile' -H 'Authorization: " ..
                                        authToken .. "'"
                                local handle = io.popen(getclassificationurl)
                                local getClassificationResponse = handle:read("*a")
                                handle:close()
                                freeswitch.consoleLog("INFO", "Classification Hierarchy Response: " ..
                                    getClassificationResponse .. "\n")
                                --	local getlocationurl ="curl -s -X GET 'https://automax.discretal.com/api/locations'  -H 'Authorization: " .. authToken .. "'"
                                local getlocationurl =
                                    "curl -s -X GET \"https://automax.discretal.com/api/locations\" -H \"Authorization: Bearer " ..
                                        access_token .. "\""
                                freeswitch.consoleLog("INFO", "Executing curl command: " .. getlocationurl .. "\n")
                                local handle = io.popen(getlocationurl)
                                local getLocationResponse = handle:read("*a")
                                handle:close()
                                freeswitch.consoleLog("INFO", "Raw Location Response: " .. tostring(getLocationResponse))
                                -- Get classification indexes from session variables
                                -- local classification_index = tonumber(session:getVariable("ClassificationIdEn"))
                                -- local subclassification_index = tonumber(session:getVariable("SubClassificationIdEn"))
                                -- local location_index = tonumber(session:getVariable("LocationIdEn"))
                                local classification_index = tonumber(
                                    session:getVariable("ClassificationIdEn") or
                                        session:getVariable("ClassificationIdAr"))
                                local subclassification_index = tonumber(
                                    session:getVariable("SubClassificationIdEn") or
                                        session:getVariable("SubClassificationIdAr"))
                                local location_index = tonumber(
                                    session:getVariable("LocationIdEn") or session:getVariable("LocationIdAr"))
                                freeswitch.consoleLog("INFO", "[DEBUG] classification_index: " ..
                                    tostring(classification_index) .. "\n")
                                freeswitch.consoleLog("INFO", "[DEBUG] subclassification_index: " ..
                                    tostring(subclassification_index) .. "\n")
                                freeswitch.consoleLog("INFO",
                                    "[DEBUG] location_index: " .. tostring(location_index) .. "\n")
                                freeswitch.consoleLog("INFO", "[DEBUG] getClassificationResponse: " ..
                                    tostring(getClassificationResponse:sub(1, 500)) .. "\n")
                                --  Call your function to get the classification ID
                                local final_classification_id, err =
                                    getClassificationID(getClassificationResponse, classification_index,
                                        subclassification_index)
                                local final_location_id, err = getLocationID(getLocationResponse, location_index)
                                --  Set session variable or log error
                                if final_classification_id then
                                    session:setVariable("ClassificationIdEn", final_classification_id)
                                    freeswitch.consoleLog("INFO", "Mapped ClassificationEn to ID: " ..
                                        final_classification_id .. "\n")
                                else
                                    freeswitch.consoleLog("ERR", "Error getting classification ID: " ..
                                        (err or "unknown error") .. "\n")
                                end
                                freeswitch.consoleLog("INFO", "Set Variable: " .. key.ResultFieldTag .. " = " ..
                                    json.encode(value))
                                if final_location_id then
                                    session:setVariable("LocationIdEn", final_location_id)
                                    freeswitch.consoleLog("INFO",
                                        "Mapped LocationIdEn to ID: " .. final_location_id .. "\n")
                                else
                                    freeswitch.consoleLog("ERR", "Error getting location ID: " ..
                                        (err or "unknown error") .. "\n")
                                end
                            else
                                freeswitch.consoleLog("ERROR", "Value not found for " .. key.ResultFieldName)
                            end
                            -- session:setVariable(key.ResultFieldTag,json.encode(curl_response[key.ResultFieldName]))
                        end
                    end
                    for _, key in ipairs(apiOutput) do
                        if key.ParentResultId ~= nil then
                            freeswitch.consoleLog("INFO", "Found ParentID for ResultFieldTag" .. key.ResultFieldTag)
                            local parentResult = json.decode(session:getVariable(key.ParentResultId))
                            session:setVariable(key.ResultFieldTag, parentResult[key.ResultFieldName])
                        end
                    end
                end
                inputKeys = "S"
            else
                freeswitch.consoleLog("INFO", "Null apiOutput")
                inputKeys = "S"
            end
        else
            inputKeys = "F"
        end
    end
    find_childNode_with_dtmfinput(inputKeys, data)
end

local function operation_code_112_exec(data)
    local api_id = data.APIId
    local methodType, contentType, serviceURL, apiInputdata, inputKeys
    for _, api in pairs(webApiData) do
        if api.apiId == api_id then
            methodType = api.methodType
            contentType = api.inputMediaType
            serviceURL = api.serviceURL
            apiInputdata = json.decode(api.apiInput)
            break
        end
    end
    local finalApi = constructApi(methodType, contentType, serviceURL, apiInputdata)
    freeswitch.consoleLog("NOTICE", "Final modified API: " .. finalApi)
    session:execute("curl", finalApi)
    -- freeswitch.consoleLog("INFO", tostring(api_response))
    curl_response_code = tonumber(session:getVariable("curl_response_code"))
    curl_response = session:getVariable("curl_response_data")
    freeswitch.consoleLog("NOTICE", "Curl Response Code: " .. curl_response_code)
    if curl_response then
        freeswitch.consoleLog("NOTICE", "Curl Response Data: " .. curl_response)
    end
    if curl_response_code >= 200 and curl_response_code < 300 then
        inputKeys = "S"
    else
        inputKeys = "F"
    end
    find_childNode_with_dtmfinput(inputKeys, data)
end

local function operation_code_120_exec(data)
    for _, childNode in pairs(data.ChildNodeConfig) do
        if childNode.ApplyComparison == true then
            if childNode.ComparisonOperator == "GRT" then
                if childNode.OperandType == "T" then
                    if tonumber(session:getVariable(childNode.CollectionTag)) > tonumber(childNode.Value1) then
                        freeswitch.consoleLog("INFO", "Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                else
                    if tonumber(childNode.CollectionTag) > tonumber(childNode.Value1) then
                        freeswitch.consoleLog("Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                end
            elseif childNode.ComparisonOperator == "LST" then
                if childNode.OperandType == "T" then
                    if tonumber(session:getVariable(childNode.CollectionTag)) < tonumber(childNode.Value1) then
                        freeswitch.consoleLog("INFO", "Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                else
                    if tonumber(childNode.CollectionTag) > tonumber(childNode.Value1) then
                        freeswitch.consoleLog("Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                end
            elseif childNode.ComparisonOperator == "IBW" then
                if childNode.OperandType == "T" then
                    if tonumber(session:getVariable(childNode.CollectionTag)) >= tonumber(childNode.Value1) and
                        tonumber(session:getVariable(childNode.CollectionTag)) <= tonumber(childNode.Value2) then
                        freeswitch.consoleLog("INFO", "Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                else
                    if tonumber(childNode.CollectionTag) >= tonumber(childNode.Value1) and
                        tonumber(childNode.CollectionTag) <= tonumber(childNode.Value2) then
                        freeswitch.consoleLog("Found ChildNodeId: " .. childNode.ChildNodeId)
                        Sub_menu(childNode.ChildNodeId)
                        break
                    end
                end
            end
        else
            freeswitch.consoleLog("INFO", "ApplyComparison:" .. tostring(childNode.ApplyComparison))
            freeswitch.consoleLog("INFO", "ChildNodeId: " .. childNode.ChildNodeId)
            Sub_menu(childNode.ChildNodeId)
            break
        end
    end
end

local function operation_code_341_exec(data) -- Speech to Text
    local audioFile = session:getVariable(data.DeafultInput);
    if data.InputType == 40 then
        session:setVariable("DefultInput", audioFile)
    end
    freeswitch.consoleLog("INFO", "Audio file to convert into Text: " .. audioFile)
    local languageCode = session:getVariable("LanguageCode")
    freeswitch.consoleLog("INFO", "Language Code:: " .. languageCode)
    local api_id = 20
    local methodType, contentType, serviceURL, apiInputdata, inputKeys
    for _, api in pairs(webApiData) do
        if api.apiId == api_id then
            freeswitch.consoleLog("INFO", "::Found API ID::")
            methodType = api.methodType
            contentType = api.inputMediaType
            serviceURL = api.serviceURL
            apiInputdata = json.decode(api.apiInput)
            apiOutput = api.apiOutput
            break
        end
    end
    local finalApi = constructApi(methodType, contentType, serviceURL, apiInputdata)
    freeswitch.consoleLog("NOTICE", "Final modified API: " .. finalApi)
    local apicallResult = apiCall(contentType, finalApi, apiOutput)
    for _, settings in pairs(generalSettings) do
        if settings.SettingId == 14 then
            local stt_settingValue = json.decode(settings.SettingValue)
            session:setVariable(data.TagName, session:getVariable(stt_settingValue.TextResponseFieldTag))
            break
        end
    end
    find_childNode_with_dtmfinput(apicallResult, data)
end

local function operation_code_330_exec(data) -- Text to Speech BuiltIn
    local tts_text = session:getVariable(data.DeafultInput);
    local number = tts_text:match("(%d+)")
    if number then
        -- Adding spaces between digits in the number
        local formatted_number = insert_spaces(number)
        -- Replacing the original number in the string with the formatted number
        tts_text = tts_text:gsub(number, formatted_number)
    end
    freeswitch.consoleLog("INFO", "Text received to convert into Speech:: " .. tts_text)
    -- local tts_text = "I N 0000001212313"
    local ttsvoice = session:getVariable("TTSVoiceNameBuiltIn")
    session:set_tts_params("flite", ttsvoice);
    -- session:set_tts_params("flite", "rms");
    session:execute("sleep", "200")
    session:speak(tts_text);
    session:execute("sleep", "300")
    find_childNode(data)
end

local function operation_code_331_exec(data) -- Text to Speech using Cloud API
    local tts_text = session:getVariable(data.DeafultInput);
    local ttsvoice = session:getVariable("TTSVoiceNameCloud")
    freeswitch.consoleLog("info", "tts_text=" .. tts_text)
    --  session:speak(tts_text);
    session:set_tts_params("azure_tts", ttsvoice);
    session:execute("sleep", "200")
    session:speak("{AZURE_SUBSCRIPTION_KEY=1cfc10bab7f54e53bb5fad1b6d6dfee4,AZURE_REGION=uksouth,speed=0}" .. tts_text);
    -- session:execute("{AZURE_SUBSCRIPTION_KEY=1cfc10bab7f54e53bb5fad1b6d6dfee4,AZURE_REGION=uksouth,speed=0}");

    --	        session:setVariable("tts_ssml", ssml)
    --              session:execute("speak", "ssml")
    session:execute("sleep", "500")
    find_childNode(data)
end

local function operation_code_50_exec(data) -----Instead of TTS 330
    freeswitch.consoleLog("info", "in operation code 50")
    local tag_name = data.TagName -- This is "IncdntMobileNumberAudAr"
    if (data.DeafultInput) then
        freeswitch.consoleLog("info", "data.DeafultInput=" .. data.DeafultInput)
    else
        freeswitch.consoleLog("info", "data.DeafultInput=Empty")
    end
    local default_input = session:getVariable(data.DeafultInput);
    freeswitch.consoleLog("info", "inputvalue=" .. default_input)
    -- if default_input and string.match(default_input, "^%d+$") then
    if default_input then
        local split_numbers = {}
        -- Split the mobile number into individual digits
        for i = 1, #default_input do
            local char = string.sub(default_input, i, i)
            --	 if char ~= " " then
            if char:match("%S") then
                table.insert(split_numbers, char .. ".wav") -- Prepare file names (e.g., "1.wav", "2.wav")
            end
        end
        -- Play each audio file based on the specified language
        for _, wav_file in ipairs(split_numbers) do
            local file_path = string.format("/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/%s/%s",
                tag_name, wav_file)
            freeswitch.consoleLog("info", "Playing: " .. file_path)
            session:execute("playback", file_path) -- Play the audio file
            session:execute("sleep", "500") -- Optional pause between plays
        end
        find_childNode(data)
    end
end

local function execute_operation(nodedata)
    freeswitch.consoleLog("notice", "Operation Code Received: " .. nodedata.OperationCode)
    if (nodedata.OperationCode == 10) then
        freeswitch.consoleLog("notice", "Executing OperationCode 10")
        operation_code_10_exec(session, nodedata)
    elseif (nodedata.OperationCode == 11) then
        freeswitch.consoleLog("notice", "Executing OperationCode 10")
        operation_code_11_exec(nodedata)
    elseif (nodedata.OperationCode == 20) then
        freeswitch.consoleLog("notice", "Executing OperationCode 20")
        operation_code_20_exec(nodedata);
    elseif (nodedata.OperationCode == 30) then
        if nodedata.ValidKeys then
            freeswitch.consoleLog("notice", "Executing OperationCode 30")
            operation_code_30_exec(nodedata)
        else
            freeswitch.consoleLog("notice", "IVR Node Does not have Valid Keys" .. nodedata.NodeId)
            session:hangup()
        end
    elseif (nodedata.OperationCode == 31) then
        if nodedata.ValidKeys then
            freeswitch.consoleLog("notice", "Executing OperationCode 31")
            operation_code_31_exec(nodedata)
        else
            freeswitch.consoleLog("notice", "IVR Node Does not have Valid Keys" .. nodedata.NodeId)
            session:hangup()
        end
    elseif (nodedata.OperationCode == 40) then
        freeswitch.consoleLog("notice", "Executing OperationCode 40")
        operation_code_40_exec(nodedata);
    elseif (nodedata.OperationCode == 100) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 100")
        operation_code_100_exec(nodedata)
    elseif (nodedata.OperationCode == 101) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 101")
        operation_code_101_exec(nodedata)
    elseif (nodedata.OperationCode == 105) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 105")
        operation_code_105_exec(nodedata)
    elseif (nodedata.OperationCode == 107) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 107")
        operation_code_107_exec(nodedata)
    elseif (nodedata.OperationCode == 108) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 108")
        operation_code_108_exec(nodedata)
    elseif (nodedata.OperationCode == 111) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 111")
        operation_code_111_exec(nodedata)
    elseif (nodedata.OperationCode == 112) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 112")
        operation_code_112_exec(nodedata)
    elseif (nodedata.OperationCode == 120) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 120")
        operation_code_120_exec(nodedata)
    elseif (nodedata.OperationCode == 200) then
        freeswitch.consoleLog("notice", "Terminating the Call")
        session:hangup()
    elseif (nodedata.OperationCode == 330) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 330")
        operation_code_330_exec(nodedata)
    elseif (nodedata.OperationCode == 331) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 331")
        operation_code_331_exec(nodedata)
    elseif (nodedata.OperationCode == 50) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 50")
        operation_code_50_exec(nodedata)
    elseif (nodedata.OperationCode == 341) then
        freeswitch.consoleLog("notice", "Executing Opeartion Code 341")
        operation_code_341_exec(nodedata)
    else
        freeswitch.consoleLog("err", "========== Operation Code " .. nodedata.OperationCode ..
            " is not Configured in service =================")
        session:hangup();
    end
end

function Sub_menu(nodeid)
    -- local iVRNodeId,iVRNodeName,operationCode,audioFile,validKeys,invalidInputAudioFile = 1;
    freeswitch.consoleLog("notice", "Sub Menu IVR Child Node ID: " .. nodeid)
    for key, value in pairs(ivrdata) do
        if value.NodeId == nodeid then
            execute_operation(value)
            break
        end
    end
end

if session:answered() and session:getVariable("cc_last_nodeId") ~= nil then
    freeswitch.consoleLog("NOTICE", "************* Agent Evaluation *******************")
    local cc_nodeId = session:getVariable("cc_last_nodeId")
    local cc_cancel_reason = session:getVariable("cc_cancel_reason")
    local cc_agent_bridged = session:getVariable("cc_agent_bridged")
    if cc_cancel_reason == "TIMEOUT" then
        freeswitch.consoleLog("NOTICE", "******** cc_cancel_reason :: " .. cc_cancel_reason)
        -- local sound = audiopath .. "BusyTone.wav";
        -- session:execute("playback", sound)
        session:set_tts_params("flite", "slt");
        session:execute("sleep", "1000")
        session:speak("Sorry, the agents are not available or busy at this moment");
        session:execute("sleep", "1000")
        session:speak("Thank you..");
        session:execute("sleep", "1000")
        session:hangup()
    end
    if cc_agent_bridged == "true" then
        freeswitch.consoleLog("NOTICE", "******** cc_agent_bridged :: " .. cc_agent_bridged)
        local cc_agent_extension = session:getVariable("cc_agent")
        session:setVariable("Receiver_Extension_Code", cc_agent_extension)
        local ext_not_reg = "error/user_not_registered"
        local extension_status = api:executeString("sofia_contact " .. cc_agent_extension)
        freeswitch.consoleLog("notice", cc_agent_extension .. " Extension Status : " .. extension_status)
        if extension_status ~= ext_not_reg then
            api:executeString("callcenter_config agent set status " .. cc_agent_extension .. " Available")
            api:executeString("callcenter_config agent set contact " .. cc_agent_extension .. " " .. extension_status);
            api:executeString("callcenter_config agent set state " .. cc_agent_extension .. " Waiting")
        else
            freeswitch.consoleLog("notice", "Extension " .. cc_agent_extension ..
                " Not registered . Changing status to Logged Out ..")
            api:executeString("callcenter_config agent set status " .. cc_agent_extension .. " 'Logged Out'")
        end
        freeswitch.consoleLog("NOTICE", "Agent Evaluation Node ID: " .. cc_nodeId)
        for key, value in pairs(ivrdata) do
            if value.NodeId == tonumber(cc_nodeId) then
                iVRChildNodeId = value.ChildNodeConfig[1].ChildNodeId;
                freeswitch.consoleLog("NOTICE", "child Node ID: " .. iVRChildNodeId)
                Sub_menu(iVRChildNodeId)
                break
            end
        end
    end
    -- freeswitch.consoleLog("NOTICE","Child Node ID Not found")
    session:hangup()
end

if session:ready() then
    local callLogId = callLog.create()
    -- session:setVariable("sip_h_X-CallLogId","1133")
    session:answer()
    session:execute("sleep", "500")
    freeswitch.consoleLog("notice", call_uuid .. ": Session Answered\n")
    freeswitch.consoleLog("notice", call_uuid .. ": Entered menu function\n")
    -- local iVRNodeId,iVRNodeName,operationCode,audioFile,isStartNode,validKeys,invalidInputAudioFile,repeatLimit;
    for _, node in pairs(ivrdata) do
        if (node.IsStartNode == true) then
            freeswitch.consoleLog("notice",
                "...Start Menu found... IVR Node ID:" .. node.NodeId .. "  IVR Node Name: " .. node.NodeName ..
                    " Operation Code: " .. node.OperationCode);
            execute_operation(node)
            break
        end

    end
end
