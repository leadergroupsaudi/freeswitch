local call_uuid = session:getVariable("uuid")
local domain = session:getVariable("domain_name")
local caller_name = session:getVariable("caller_id_name")
local caller_id = session:getVariable("caller_id_number")
local json = require "lunajson"
api = freeswitch.API();
--local redis = (require 'redis').connect('127.0.0.1',6379) -- redis client connect
--local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfigurationV6');", 0)) -- storing the IVRNodes data
--local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfiguration_tts_new');", 0)) -- storing the IVRNodes data
--local ivrdata = ivrconfig.IVRConfiguration[1].IVRProcessFlow;
--local generalSettings = ivrconfig.IVRConfiguration[1].GeneralSettingValues

--local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_tts_new');", 0))
--local webApiData = webApi_Config.result

--local ivrextensions = redis:eval("return redis.call('json.get','Extensions_qa');", 0) -- storing the IVRNodes data
--local agent_extensions = json.decode(ivrextensions)

--local ivrrecording_data = redis:eval("return redis.call('json.get','RecordingType_qa');", 0)
--local recording_config = json.decode(ivrrecording_data)
local scripts_path = freeswitch.getGlobalVariable("script_dir")
local ivrFilePath = scripts_path.."/ivr-cc-config/ivrconfig.json"

-- Read the JSON file content
local ivrfile = io.open(ivrFilePath, "r")
if not ivrfile then
    freeswitch.consoleLog("norice","Error: Unable to open IVR file.")
    return
end

local ivrjsonContent = ivrfile:read("*a")
ivrfile:close()

-- Parse the JSON content
local ivrconfig = json.decode(ivrjsonContent)
local ivrdata = ivrconfig.IVRConfiguration[1].IVRProcessFlow;
local generalSettings = ivrconfig.IVRConfiguration[1].GeneralSettingValues
--local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_qa');", 0))
local WebConfigFilePath =scripts_path.."/ivr-cc-config/fortunil_webAPIConfig.json"

-- Read the JSON file content
local webConfigfile = io.open(WebConfigFilePath, "r")
if not webConfigfile then
    freeswitch.consoleLog("norice","Error: Unable to open webConfigfile file.")
    return
end

local webConfigjsonContent = webConfigfile:read("*a")
webConfigfile:close()

-- Parse the JSON content
local webApi_Config = json.decode(webConfigjsonContent)
webApiData = webApi_Config.result

--local ivrextensions = redis:eval("return redis.call('json.get','Extensions_qa');", 0) -- storing the IVRNodes data


local extensionsFilePath = scripts_path.."/ivr-cc-config/fortunil_agents.json"

local extensionConfigfile = io.open(extensionsFilePath, "r")
if not extensionConfigfile then
    freeswitch.consoleLog("norice","Error: Unable to open ExtensionConfigfile file.")
    return
end

local extensionConfigjsonContent = extensionConfigfile:read("*a")
extensionConfigfile:close()

-- Parse the JSON content
local agent_extensions = json.decode(extensionConfigjsonContent)

--local ivrrecording_data = redis:eval("return redis.call('json.get','RecordingType_qa');", 0)
local recordTypeFilePath = scripts_path.."/ivr-cc-config/RecordingType_qa.json"

-- Read the JSON file content
local recordTypeConfigfile = io.open(recordTypeFilePath, "r")
if not recordTypeConfigfile then
    freeswitch.consoleLog("norice","Error: Unable to open recordTypeConfigfile file.")
    return
end

local ivrrecording_data = recordTypeConfigfile:read("*a")
recordTypeConfigfile:close()

local recording_config = json.decode(ivrrecording_data)
local epm_audiofiles_path = freeswitch.getGlobalVariable("sounds_dir")
local audio_recording_path = freeswitch.getGlobalVariable("recordings_dir")                                                                                                                                                                
local audiopath = epm_audiofiles_path .."/ivr_audiofiles_tts_new/"
local recording_dir = audio_recording_path ..'/IVR-CCM-Recordings/'
--local module_folder = "/usr/local/freeswitch-automax-instance/share/freeswitch/scripts/"

--local module_folder = "/usr/local/freeswitch-automax-instance/share/freeswitch/scripts/"
package.path = scripts_path .."/".."?.lua;" .. package.path
local callLog = require "custom-modules.createCallLog"


--local dynamicApi = require "resources.functions.dynamicApi"
        local function find_childNode(data)
                        local iVRChildNodeId;
                                        for key, value in pairs(ivrdata) do
                                                        if( value.NodeId == data.NodeId) then
                                                        iVRChildNodeId = value.ChildNodeConfig[1].ChildNodeId;
                        				Sub_menu(iVRChildNodeId)
							return
                                        end
                                end
                        freeswitch.consoleLog("notice","Found IVR Node ID: " .. iVRChildNodeId)
        end

        local function find_childNode_with_dtmfinput(digits,data)
                freeswitch.consoleLog("notice","*************** Find Child Node With DTMF Digit input : " ..digits);
                local iVRChildNodeId = 0;
                for key, value in pairs(ivrdata) do
                        if(value.NodeId == data.NodeId ) then
				for _,childNode in pairs(value.ChildNodeConfig) do
					if childNode.InputKeys == digits then
						iVRChildNodeId = childNode.ChildNodeId;
                        				Sub_menu(iVRChildNodeId)
							return
					end
				end
                        end
                end
                freeswitch.consoleLog("notice","Found IVR Child Node ID: " .. iVRChildNodeId)
                if iVRChildNodeId == 0 then
                        freeswitch.consoleLog("notice","IVR Child Node ID is not found with DTMF: " .. digits .. " and Parant Node ID: " .. data.NodeId)
                        freeswitch.consoleLog("NOTICE","Hangup the Call")
                        session:hangup()
                end
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

	function execute_command(command)
            local handle = io.popen(command)
            local result = handle:read("*a")
            handle:close()
            return result
        end

	local function setLanguage(languageCode)
		freeswitch.consoleLog("INFO","Language Set Function")
                for _,settings in pairs(generalSettings) do
                        if settings.SettingId == 15 then
                                local languageSettings = json.decode(settings.SettingValue)
				for _, setting in ipairs(languageSettings) do
				    if setting.LanguageCode == tonumber(languageCode) then
				        for key, value in pairs(setting) do
				        	session:setVariable(key,value)
				        end
				    end
				end
                                break
                        end
                end
	end

	local function constructApi(methodType,contentType,serviceURL,apiInputdata)
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


	local function apiCall(contentType,finalApi,apiOutput)
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


        local function operation_code_10_exec(session,data)
                        freeswitch.consoleLog("notice","*********** Entered Operation Code Function 10 {Play Audio} **************")
                        local sound = audiopath .. data.VoiceFileId;
                        freeswitch.consoleLog("notice","Audio File to play: " .. sound)
                        --session:streamFile(sound)
			session:execute("playback", sound)
                        session:sleep(500)
                        local f=io.open(sound,"r")
                        if f~=nil then
                                io.close(f)
                                find_childNode(data)
                                --session:hangup()
                        else
                                freeswitch.consoleLog("notice","Audio file " .. sound .. " Not Found. So hanging the call");
                                session:hangup()
                        end
        end

        local function operation_code_11_exec(data)
                        freeswitch.consoleLog("notice","*********** Entered Operation Code Function 11 {Play Recorded File} **************")
			local tagName = data.TagName;
			local sound = session:getVariable(tagName);
                        freeswitch.consoleLog("notice","Audio File to play: " .. sound)
                        --session:streamFile(sound)
                        local f=io.open(sound,"r")
                        if f~=nil then
				session:execute("playback", sound)
	                        session:sleep(500)
                                io.close(f)
                                find_childNode(data)
                        else
                                freeswitch.consoleLog("notice","Audio file " .. sound .. " Not Found. So hanging the call");
                                session:hangup()
                        end
        end

        local function operation_code_20_exec(data)
                freeswitch.consoleLog("notice","******** Entered Operation Code Function 20 {UserInput} ************")
		freeswitch.consoleLog("notice","Input  InputLengt value: "..data.InputTimeLimit);
		freeswitch.consoleLog("notice","Valid Keys : "..data.ValidKeys);
		freeswitch.consoleLog("notice","Input Time Limit (timeout) value: "..data.InputTimeLimit);
                local validDigits = data.ValidKeys;
                local dtmfVerify = string.gsub(data.ValidKeys,",","|");
		freeswitch.consoleLog("notice","DTMF  Verify string : "..dtmfVerify);
                --local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
		local min_digits = 1;
                local max_digits = data.InputLength ;
		local timeLimit = data.InputTimeLimit * 1000 or 5000
		local invalidaudiofile = audiopath..data.InvalidInputVoiceFileId;
		local repeat_limit;
		if data.IsRepetitive == true then
			repeat_limit= data.RepeatLimit;
		else
			repeat_limit = 0;
		end

		for i = 0,repeat_limit,1 do
			freeswitch.consoleLog("notice","DTMF Validation loop entered ")
			session:setVariable("read_terminator_used", "")
			--local digits = session:getDigits(max_digits, "#", timeLimit);
			digits = session:read(min_digits, max_digits, "", timeLimit, "#")
			terminator = session:getVariable("read_terminator_used")
                	--local digits = session:playAndGetDigits (min_digits, max_digits , 1 ,timeLimit,'#','', invalidaudiofile,(dtmfVerify))
                	freeswitch.consoleLog("notice","DTMF Input received: " .. digits)
			freeswitch.consoleLog("notice","#digit: "..#digits)
			freeswitch.consoleLog("notice","DTMF InputLength Entered by User: " .. #digits)
			if #digits==max_digits then
				freeswitch.consoleLog("notice","DTMF Digits received from user : "..digits)
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
					session:setVariable(data.TagName,digits)
					inputdigits = "#"
        	        	        find_childNode_with_dtmfinput(inputdigits,data)
					break;
				else
					session:execute("playback", invalidaudiofile)
				end
			elseif #digits>0 and #digits<max_digits then
        	                freeswitch.consoleLog("notice","Invalid DTMF Input received!! ")
				if i==repeat_limit then
        	                	freeswitch.consoleLog("notice","Setting the DTMF Input as X ")
					digits = "X" 
                			find_childNode_with_dtmfinput(digits,data)
				else
					session:execute("playback", invalidaudiofile)
				end
			elseif #digits==0 then
        	                freeswitch.consoleLog("notice","No DTMF Input received!!")
				if terminator ~= "#" and data.TimeLimitResponseType == 20 then 
					digits = "D" 
	                       		find_childNode_with_dtmfinput(digits,data)
				elseif data.TimeLimitResponseType == 10 and i==repeat_limit then
                                        digits = "X"
                                        find_childNode_with_dtmfinput(digits,data)
				else
					session:execute("playback", invalidaudiofile)

				end
			else
				freeswitch.consoleLog("notice","Some Condition got Failed")
			end
		end
        end

        local function operation_code_30_exec(data)
                        freeswitch.consoleLog("notice","******** Entered Operation Code Function 30 {InputWithAudio} ************")
                        local min_digits = 1;
                        local ivr_menu_digit_leg = 1;
                        local sound = audiopath .. data.VoiceFileId;
			local timeLimit = data.InputTimeLimit * 1000 or 5000;
			freeswitch.consoleLog("notice","Input Time Limit (timeout) value: "..timeLimit);
                        local invalidaudiofile = audiopath..data.InvalidInputVoiceFileId or audiopath.."InvalidSelection.wav"; 
                        local dtmfVerify = string.gsub(data.ValidKeys,",","|");
                        local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
			local attempts;
			freeswitch.consoleLog("notice","Is Repetitive type: "..type(data.IsRepetitive));
			if data.IsRepetitive == true  then 
                        	attempts = data.RepeatLimit or 3;
			else
				attempts = 1
			end
                        local dtmf_digits;
                        freeswitch.consoleLog("notice","Regex DTMF Validation: " .. dtmfVerify_2);
                        freeswitch.consoleLog("notice","Audio File Name: " .. sound);
                        freeswitch.consoleLog("notice","Invalid Audio File Name: " .. invalidaudiofile);
                        freeswitch.consoleLog("notice","Valid DTMF Digits: " .. data.ValidKeys);
                        freeswitch.consoleLog("notice","Attempts: " .. attempts)
                        session:sleep(500)
                        dtmf_digits = session:playAndGetDigits (min_digits, ivr_menu_digit_leg ,attempts ,timeLimit,'',sound, invalidaudiofile,(dtmfVerify_2))
                        -- session:playAndGetDigits ( min_digits, max_digits, max_attempts, timeout, terminators, prompt_audio_files, input_error_audio_files,digit_regex, variable_name, digit_timeout, transfer_on_failure)
                        -- need pause before stream file
                        session:setVariable("slept", "false");
                        freeswitch.consoleLog("notice","DTMF Entered: " .. dtmf_digits)
                        if dtmf_digits and #dtmf_digits > 0 then
				if data.TagName ~= nil then
					if data.TagName == "LanguageSelected" then
					freeswitch.consoleLog("info","::Found Language Selection TagName::")
					setLanguage(dtmf_digits)
					elseif data.TagValuePrefix ~= nil then
						session:setVariable(data.TagName,data.TagValuePrefix..dtmf_digits)
					else
						session:setVariable(data.TagName,dtmf_digits)
					end
				end
                                find_childNode_with_dtmfinput(dtmf_digits,data);
                        else
				if data.TimeLimitResponseType == 10 then
                                freeswitch.consoleLog("notice","DTMF Input Not received!!, Setting input as X ")
                                --session:hangup()
				dtmf_digits = "X"	
				find_childNode_with_dtmfinput(dtmf_digits,data);
				else
					freeswitch.consoleLog("notice","DTMF Input Not received!!, Setting default input as " ..data.DeafultInput.. " based on TimeLimitResponseType:  " ..data.TimeLimitResponseType)	
					dtmf_digits = data.DeafultInput;
					if data.TagName ~= nil then
						if data.TagName == "LanguageSelected" then
							freeswitch.consoleLog("info","::Found Language Selection TagName::")
							setLanguage(dtmf_digits)
						else
							session:setVariable(data.TagName,dtmf_digits)
						end
         	                        end
					find_childNode_with_dtmfinput(dtmf_digits,data);
				end
                        end
        end --end function

        local function operation_code_31_exec(data)
                        freeswitch.consoleLog("notice","******** Entered Operation Code Function 31 {InputWithAudio} ************")
                        local min_digits = 1;
                        local ivr_menu_digit_leg = 1;
			local tagName = data.TagName;
			local sound = session:getVariable(tagName);
			local timeLimit = data.InputTimeLimit * 1000 or 5000;
			freeswitch.consoleLog("notice","Input Time Limit (timeout) value: "..timeLimit);
                        local invalidaudiofile = audiopath..data.InvalidInputVoiceFileId or audiopath.."InvalidSelection.wav"; 
                        local dtmfVerify = string.gsub(data.ValidKeys,",","|");
                        local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
			local attempts;
			freeswitch.consoleLog("notice","Is Repetitive type: "..type(data.IsRepetitive));
			if data.IsRepetitive == true  then 
                        	attempts = data.RepeatLimit or 3;
			else
				attempts = 1
			end
                        local dtmf_digits;
                        freeswitch.consoleLog("notice","Regex DTMF Validation: " .. dtmfVerify_2);
                        freeswitch.consoleLog("notice","Audio File Name: " .. sound);
                        freeswitch.consoleLog("notice","Invalid Audio File Name: " .. invalidaudiofile);
                        freeswitch.consoleLog("notice","Valid DTMF Digits: " .. data.ValidKeys);
                        freeswitch.consoleLog("notice","Attempts: " .. attempts)
                        session:sleep(500)
                        dtmf_digits = session:playAndGetDigits (min_digits, ivr_menu_digit_leg ,attempts ,timeLimit,'',sound, invalidaudiofile,(dtmfVerify_2))
                        -- session:playAndGetDigits ( min_digits, max_digits, max_attempts, timeout, terminators, prompt_audio_files, input_error_audio_files,digit_regex, variable_name, digit_timeout, transfer_on_failure)
                        -- need pause before stream file
                        session:setVariable("slept", "false");
                        freeswitch.consoleLog("notice","DTMF Entered: " .. dtmf_digits)
                        if dtmf_digits and #dtmf_digits > 0 then
                                find_childNode_with_dtmfinput(dtmf_digits,data);
                        else
				if data.TimeLimitResponseType == 10 then
                                freeswitch.consoleLog("notice","DTMF Input Not received!!, Setting input as X ")
                                --session:hangup()
				dtmf_digits = "X"	
				find_childNode_with_dtmfinput(dtmf_digits,data);
				else
					freeswitch.consoleLog("notice","DTMF Input Not received!!, Setting default input as " ..data.DeafultInput.. " based on TimeLimitResponseType:  " ..data.TimeLimitResponseType)	
					dtmf_digits = data.DeafultInput;
					find_childNode_with_dtmfinput(dtmf_digits,data);
				end
                        end
        end --end function

	local function operation_code_40_exec(data)
		freeswitch.consoleLog("notice","\n *** Entered Operation Code 40 ***\n")
		local recordTimeLimit, recordfilename;
		local silence_hits = data.InputTimeLimit or 5;
		local silence_threshold = 200;
		local recordingTypeId = data.RecordingTypeId;
		for _,recordData in pairs(recording_config.RecordingType) do
			if recordData.RecordingTypeId == recordingTypeId then
				freeswitch.consoleLog("info","Found Recording ID")
				recordTimeLimit = recordData.RecordTimeLimit
				recordfilename = recordData.TypePrefix
				freeswitch.consoleLog("info","RecordTime Limit : "..recordTimeLimit.." Record filename: "..recordfilename);
			break
			end
		end
		recordfilename = recordfilename.."_"..call_uuid..".wav";
		recording_filename = string.format('%s%s', recording_dir, recordfilename)
		freeswitch.consoleLog("NOTICE", "\n Recording time limit Seconds: "..recordTimeLimit.." :: silence Secs: "..silence_hits)
		freeswitch.consoleLog("notice","\n Recording File Name: "..recording_filename);
		session:execute("export","nolocal:playback_terminators=#")
		--local CallerMessage = session:recordFile(recording_filename, tonumber(recordTimeLimit), tonumber(silence_threshold), tonumber(silence_hits));
		local callerMessage = session:execute("record", recording_filename.." "..tonumber(recordTimeLimit).." "..silence_threshold.." "..silence_hits);
		--session:consoleLog("info", "session:recordFile() = " .. callerMessage )
		function hasSoundActivity(wavFilePath)
			local cmd = string.format("sox %s -n stat 2>&1 | grep -i 'RMS     amplitude'  | awk '{print $3}'", wavFilePath)
			freeswitch.consoleLog("NOTICE","Sox Command :: "..cmd)
			local handle = io.popen(cmd)
			local result = handle:read("*a")
			handle:close()

			-- Check if the result is empty or not a valid number
			if result and tonumber(result) then
				local amplitude = tonumber(result)
				-- Adjust the threshold as needed
				local threshold = 0.001
				freeswitch.consoleLog("NOTICE","Sox RMS Amplitude output :: "..amplitude)

				-- Check if the amplitude is above the threshold
				if amplitude >= threshold then
					return true
				end
			end

			return false
		end

		if hasSoundActivity(recording_filename) then
			freeswitch.consoleLog("NOTICE", "The WAV file contains user voice or sound.\n")
			--session:execute("playback", recording_filename)
			local tag_name = data.TagName
			freeswitch.consoleLog("NOTICE", "Tag Name: "..tag_name)
			session:setVariable(tag_name,recording_filename);
			local input = "S"
			find_childNode_with_dtmfinput(input,data);
		else
			--freeswitch.consoleLog("NOTICE", "The WAV file does not have user voice or sound.\n")
			print("NOTICE", "The WAV file does not have user voice or sound.\n")
			local input = "D"
			find_childNode_with_dtmfinput(input,data);
		end	

	end
        local function operation_code_100_exec(data)
                freeswitch.consoleLog("notice","\n *** Operation code 100 func {Agent Transfer} ***\n")
                local extensions = {}
                local ext_not_reg = "error/user_not_registered"
                for key, value in pairs(agent_extensions.Extensions) do
                        if value.IsAgent == false then
                                api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Idle")
                        else
                                local extension_status = api:executeString("sofia_contact " .. value.ExtensionCode)
                                freeswitch.consoleLog("notice",value.ExtensionCode .. " Extension Status : " .. extension_status)
                                if extension_status ~= ext_not_reg  then
                                        --api:executeString("callcenter_config agent add " .. value.ExtensionCode .. " Callback")
                                        api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " Available")
                                        api:executeString("callcenter_config agent set contact " .. value.ExtensionCode .. " " .. extension_status);
					api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Waiting")
                                        --api:executeString("callcenter_config tier add leader-ivr@default " .. value.ExtensionCode .. " 1 1")
                                        extensions[#extensions+1] = value.ExtensionCode;
                                else
                                        freeswitch.consoleLog("notice","Extension " .. value.ExtensionCode .. " Not registered . Changing status to Logged Out ..")
                                        api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " 'Logged Out'")
                                end
                        end
                end
		session:execute("sleep","500")
		session:execute("callcenter","ccm-ivr@default")
        end
        
	local function operation_code_101_exec(data)
                freeswitch.consoleLog("notice","\n *** Operation code 101 func {Agent Transfer with Evaluation} ***\n")
                local extensions = {}
                local ext_not_reg = "error/user_not_registered"
                for key, value in pairs(agent_extensions.Extensions) do
                        if value.IsAgent == false then
                                api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Idle")
                        else
                                local extension_status = api:executeString("sofia_contact " .. value.ExtensionCode)
                                freeswitch.consoleLog("notice",value.ExtensionCode .. " Extension Status : " .. extension_status)
                                if extension_status ~= ext_not_reg  then
                                        --api:executeString("callcenter_config agent add " .. value.ExtensionCode .. " Callback")
                                        api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " Available")
                                        api:executeString("callcenter_config agent set contact " .. value.ExtensionCode .. " " .. extension_status);
					api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Waiting")
                                        --api:executeString("callcenter_config tier add leader-ivr@default " .. value.ExtensionCode .. " 1 1")
                                        extensions[#extensions+1] = value.ExtensionCode;
                                else
                                        freeswitch.consoleLog("notice","Extension " .. value.ExtensionCode .. " Not registered . Changing status to Logged Out ..")
                                        api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " 'Logged Out'")
                                end
                        end
                end
		session:execute("sleep","500")
		session:setAutoHangup(false)
		session:setVariable("cc_last_nodeId",data.NodeId)
		session:execute("transfer","OPCODE_101 XML public")
	end

        local function operation_code_105_exec(data)
                freeswitch.consoleLog("notice","******** Entered Operation Code Function 105 {Extension Tranfer} ************")
		freeswitch.consoleLog("notice","Input  InputLengt value: "..data.InputTimeLimit);
		freeswitch.consoleLog("notice","Valid Keys : "..data.ValidKeys);
		freeswitch.consoleLog("notice","Input Time Limit (timeout) value: "..data.InputTimeLimit);
                local validDigits = data.ValidKeys;
                local dtmfVerify = string.gsub(data.ValidKeys,",","|");
		freeswitch.consoleLog("notice","DTMF  Verify string : "..dtmfVerify);
                --local dtmfVerify_2 =  string.gsub(dtmfVerify,"*","\\*")
		local min_digits = 1;
                local max_digits = data.InputLength ;
		local timeLimit = data.InputTimeLimit * 1000 or 5000
		local invalidaudiofile = audiopath..data.InvalidInputVoiceFileId;
		local repeat_limit;
		if data.IsRepetitive == true then
			repeat_limit= data.RepeatLimit;
		else
			repeat_limit = 0;
		end
		session:setVariable("read_terminator_used", "")
		--local digits = session:getDigits(max_digits, "#", timeLimit);
		digits = session:read(min_digits, max_digits, "", timeLimit, "#")
		terminator = session:getVariable("read_terminator_used")
               	--local digits = session:playAndGetDigits (min_digits, max_digits , 1 ,timeLimit,'#','', invalidaudiofile,(dtmfVerify))
               	freeswitch.consoleLog("notice","DTMF Input received: " .. digits)
		freeswitch.consoleLog("notice","DTMF InputLength Entered by User: " .. #digits)
		if #digits==max_digits then
			freeswitch.consoleLog("notice","DTMF Digits received from user : "..digits)
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
				session:setVariable(data.TagName,digits)
				--dial_string = digits .." XML public";
				cmd = "user_exists id "..digits.." "..domain
				freeswitch.consoleLog("INFO","Extesnion validation command: "..cmd)
				found = api:executeString(cmd)
				if found == "true" then
					session:setVariable("hangup_after_bridge","true")
		        	        --session:execute("transfer",dial_string)
			   		retries = 0;
					max_retries = 3;
					freeswitch.consoleLog("INFO","Max Retries: "..max_retries)
					second_session = null;
					--dialString = "{originate_timeout=30,hangup_after_bridge=true}user/"..digits.."@"..domain
		   			dialString = "{origination_caller_id_name="..caller_name..",origination_caller_id_number="..caller_id..",originate_timeout=30,hangup_after_bridge=true}user/"..digits.."@"..domain
					--session:execute("playback", "local_stream://moh");
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
						freeswitch.consoleLog("WARNING","second leg answered\n")
						freeswitch.bridge(session, second_session)
						--freeswitch.consoleLog("WARNING","After bridge\n")
						if (second_session:ready()) then second_session:hangup(); end
					end 
					--if (session:ready()) then session:hangup(); end
					if hcause ~= "SUCCESS" then 
						freeswitch.consoleLog("WARNING",":::: Extension is not registered or un reachable :::"..hcause)
				        	session:set_tts_params("flite", "slt");
						session:execute("sleep","1000")
		                   		session:speak("Hello! The entered Extension is not available or Busy");
						session:execute("sleep","1000")
						session:hangup()
        	        			--freeswitch.consoleLog("notice","Setting the DTMF Input as F ")
						--inputKey = "F"
						--find_childNode_with_dtmfinput(inputKey,data)
					end
				else
				        freeswitch.consoleLog("NOTICE","Extension Not Found")
				        --session:set_tts_parms("flite", "awb");
	                   		--session:speak("Hello! The entered Extension is not valid");
				        inputKey = "F"
					find_childNode_with_dtmfinput(inputKey,data)					
				 end
                          else
                          	 session:execute("playback", invalidaudiofile)
                          end
		elseif #digits>0 and #digits<max_digits then
        		freeswitch.consoleLog("notice","Invalid DTMF Input received!! ")
        	        freeswitch.consoleLog("notice","Setting the DTMF Input as F ")
			digits = "F" 
                	find_childNode_with_dtmfinput(digits,data)
		elseif #digits==0 then
        	        freeswitch.consoleLog("notice","No DTMF Input received!!")
			--session:execute("playback", invalidaudiofile)
			digits = "F" 
	                find_childNode_with_dtmfinput(digits,data)
		else
			freeswitch.consoleLog("notice","Some Condition got Failed")
		end
	end

	local function operation_code_107_exec(data)
		freeswitch.consoleLog("INFO","Operation Code 107 {Direct Agent transfer to extension:: }"..data.ValidKeys)
		extension = data.ValidKeys
		cmd = "user_exists id "..extension.." "..domain
                found = api:executeString(cmd)
                freeswitch.consoleLog("notice","Extension Output result"..found)
                if found == 'true' then
                   freeswitch.consoleLog("notice","Extesnion found")
                   --dial_string = digits .." XML public";
                   --session:execute("transfer",dial_string);
		   dialString = "{origination_caller_id_name="..caller_name..",origination_caller_id_number="..caller_id..",originate_timeout=30,hangup_after_bridge=true}user/"..extension.."@"..domain
		   freeswitch.consoleLog("INFO","DailString: "..dialString)
		   session:execute("set","ringback=${us-ring}")
	           second_session = freeswitch.Session(dialString)
                   if (second_session:ready()) then
                      freeswitch.consoleLog("WARNING","second leg answered\n")
                      freeswitch.bridge(session, second_session)
                      --freeswitch.consoleLog("WARNING","After bridge\n")
                   else
                      freeswitch.consoleLog("WARNING","second leg failed\n")
		      session:set_tts_params("flite", "slt");
			session:execute("sleep","1000")
		        session:speak("Hello! The entered Extension is not available or Busy");
			session:execute("sleep","1000")
		      session:hangup()
	      	   end
		else	   
		   freeswitch.consoleLog("NOTICE","Extension Not Found")
		   --session:set_tts_parms("flite", "awb");
		   --session:speak("The pre defined Extension is not valid");
		   inputKey = "F"
		   find_childNode_with_dtmfinput(inputKey,data)
	   	end
	end

	local function operation_code_108_exec(data)
		freeswitch.consoleLog("INFO","Operation Code 107 {External line transfer to extension:: }"..data.ValidKeys)
		extension = data.ValidKeys
		--cmd = "user_exists id "..extension.." "..domain
                --found = api:executeString(cmd)
                --freeswitch.consoleLog("notice","Extension Output result"..found)
                --if found == 'true' then
		if extension ~= nil then
                   freeswitch.consoleLog("notice","Extesnion found")
		   dialString = "sofia/gateway/fxax-gateway/"..extension
	           second_session = freeswitch.Session(dialString)
                   if (second_session:ready()) then
                      freeswitch.consoleLog("WARNING","second leg answered\n")
                      freeswitch.bridge(session, second_session)
                      freeswitch.consoleLog("WARNING","After bridge\n")
                   else
                      freeswitch.consoleLog("WARNING","second leg failed\n")
	      	   end
		else	   
		   freeswitch.consoleLog("NOTICE","Extension Not Found")
		   session:set_tts_parms("flite", "awb");
		   session:speak("The pre defined Extension is not valid");
		   inputKey = "F"
		   find_childNode_with_dtmfinput(inputKey,data)
	   	end
	end


        local function operation_code_111_exec(data)
		local api_id = data.APIId
		freeswitch.consoleLog("NOTICE","API ID: "..api_id)
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
		   freeswitch.consoleLog("INFO","HTTP response:"..apiResponse)
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
	     find_childNode_with_dtmfinput(inputKeys,data)
	end

        local function operation_code_112_exec(data)
		local api_id = data.APIId
		local methodType,contentType,serviceURL, apiInputdata,inputKeys
		for _,api in pairs(webApiData) do
			if api.apiId == api_id then
			methodType = api.methodType
			contentType = api.inputMediaType
			serviceURL = api.serviceURL
			apiInputdata = json.decode(api.apiInput)
			break
			end
		end
		local finalApi = constructApi(methodType,contentType,serviceURL,apiInputdata)
		freeswitch.consoleLog("NOTICE","Final modified API: "..finalApi)
		session:execute("curl", finalApi)
		--freeswitch.consoleLog("INFO", tostring(api_response))
		curl_response_code = tonumber(session:getVariable("curl_response_code"))
		curl_response      = session:getVariable("curl_response_data")
		freeswitch.consoleLog("NOTICE","Curl Response Code: "..curl_response_code)
		if curl_response then
			freeswitch.consoleLog("NOTICE","Curl Response Data: "..curl_response)
		end
		if curl_response_code >=200 and curl_response_code < 300 then
			inputKeys = "S"
		else
			inputKeys = "F"
		end
		find_childNode_with_dtmfinput(inputKeys,data)
	end

	local function operation_code_120_exec(data)
	 	for _,childNode in pairs(data.ChildNodeConfig) do
		        if childNode.ApplyComparison == true then
		                if childNode.ComparisonOperator == "GRT" then
                		         if childNode.OperandType == "T" then 
						 if  tonumber(session:getVariable(childNode.CollectionTag)) > tonumber(childNode.Value1) then freeswitch.consoleLog("INFO","Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break
						 end
			                 else 	
						 if tonumber(childNode.CollectionTag) > tonumber(childNode.Value1) then freeswitch.consoleLog("Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break 
						 end
					 end
                		elseif childNode.ComparisonOperator == "LST" then
					if childNode.OperandType == "T" then
		                        	if tonumber(session:getVariable(childNode.CollectionTag)) < tonumber(childNode.Value1) then freeswitch.consoleLog("INFO","Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break 
						end
					else 
						if tonumber(childNode.CollectionTag) > tonumber(childNode.Value1) then freeswitch.consoleLog("Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break	
						end
                			end
				elseif childNode.ComparisonOperator == "IBW" then
                                         if childNode.OperandType == "T" then
                                                 if  tonumber(session:getVariable(childNode.CollectionTag)) >= tonumber(childNode.Value1) and tonumber(session:getVariable(childNode.CollectionTag)) <= tonumber(childNode.Value2) then freeswitch.consoleLog("INFO","Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break
                                                 end
                                         else 
						 if tonumber(childNode.CollectionTag) >= tonumber(childNode.Value1) and tonumber(childNode.CollectionTag) <= tonumber(childNode.Value2) then freeswitch.consoleLog("Found ChildNodeId: "..childNode.ChildNodeId) Sub_menu(childNode.ChildNodeId) break
                                                 end
                                         end
				end
		        else
                		freeswitch.consoleLog("INFO","ApplyComparison:"..tostring(childNode.ApplyComparison))
		                freeswitch.consoleLog("INFO","ChildNodeId: "..childNode.ChildNodeId) 
				Sub_menu(childNode.ChildNodeId) 
				break
			end
        	end
	end

        local function operation_code_341_exec(data) --Speech to Text
                local audioFile = session:getVariable(data.DeafultInput);
		if data.InputType == 40 then
			session:setVariable("DefultInput",audioFile)
		end
                freeswitch.consoleLog("INFO","Audio file to convert into Text: " .. audioFile)
		local languageCode = session:getVariable("LanguageCode")
                freeswitch.consoleLog("INFO","Language Code:: " .. languageCode)
                local api_id = 20
                local methodType,contentType,serviceURL, apiInputdata,inputKeys
                for _,api in pairs(webApiData) do
                        if api.apiId == api_id then
			freeswitch.consoleLog("INFO","::Found API ID::")
                        methodType = api.methodType
                        contentType = api.inputMediaType
                        serviceURL = api.serviceURL
                        apiInputdata = json.decode(api.apiInput)
			apiOutput = api.apiOutput
			break
                        end
                end
                local finalApi = constructApi(methodType,contentType,serviceURL,apiInputdata)
                freeswitch.consoleLog("NOTICE","Final modified API: "..finalApi)
		local apicallResult = apiCall(contentType,finalApi,apiOutput)
		for _,settings in pairs(generalSettings) do
                        if settings.SettingId == 14 then
                                local stt_settingValue = json.decode(settings.SettingValue)
				session:setVariable(data.TagName,session:getVariable(stt_settingValue.TextResponseFieldTag))
                                break
                        end			
		end
                find_childNode_with_dtmfinput(apicallResult,data)
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
		freeswitch.consoleLog("INFO","Text received to convert into Speech:: "..tts_text)
	        --local tts_text = "I N 0000001212313"
		local ttsvoice = session:getVariable("TTSVoiceNameBuiltIn")
	        session:set_tts_params("flite", ttsvoice);
	        --session:set_tts_params("flite", "rms");
	        session:execute("sleep","200")
	        session:speak(tts_text);
	        session:execute("sleep","300")
		find_childNode(data)
	end

        local function operation_code_331_exec(data) --Text to Speech using Cloud API
                local tts_text = session:getVariable(data.DeafultInput);
                local ttsvoice = session:getVariable("TTSVoiceNameCloud")
                session:speak(tts_text);
		session:set_tts_params("azure_tts", ttsvoice);
                session:execute("sleep","200")
	        session:speak("{AZURE_SUBSCRIPTION_KEY=1cfc10bab7f54e53bb5fad1b6d6dfee4,AZURE_REGION=uksouth,speed=0}"..tts_text);
	        session:execute("sleep","500")
                find_childNode(data)
        end

        local function execute_operation(nodedata)
                freeswitch.consoleLog("notice","Operation Code Received: " .. nodedata.OperationCode)
                if (nodedata.OperationCode == 10) then
                        freeswitch.consoleLog("notice","Executing OperationCode 10")
                        operation_code_10_exec(session,nodedata)
		elseif (nodedata.OperationCode == 11) then
                        freeswitch.consoleLog("notice","Executing OperationCode 10")
                        operation_code_11_exec(nodedata)
                elseif (nodedata.OperationCode == 20) then
                        freeswitch.consoleLog("notice","Executing OperationCode 20")
                        operation_code_20_exec(nodedata);
                elseif (nodedata.OperationCode == 30) then
                        if nodedata.ValidKeys then
                                freeswitch.consoleLog("notice","Executing OperationCode 30")
                                operation_code_30_exec(nodedata)
                        else
                                freeswitch.consoleLog("notice","IVR Node Does not have Valid Keys" .. nodedata.NodeId)
                                session:hangup()
                        end
                elseif (nodedata.OperationCode == 31) then
                        if nodedata.ValidKeys then
                                freeswitch.consoleLog("notice","Executing OperationCode 31")
                                operation_code_31_exec(nodedata)
                        else
                                freeswitch.consoleLog("notice","IVR Node Does not have Valid Keys" .. nodedata.NodeId)
                                session:hangup()
                        end
                elseif (nodedata.OperationCode == 40) then
                        freeswitch.consoleLog("notice","Executing OperationCode 40")
                        operation_code_40_exec(nodedata);
                elseif (nodedata.OperationCode == 100) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 100")
                        operation_code_100_exec(nodedata)
                elseif (nodedata.OperationCode == 101) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 101")
                        operation_code_101_exec(nodedata)
                elseif (nodedata.OperationCode == 105) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 105")
                        operation_code_105_exec(nodedata)
                elseif (nodedata.OperationCode == 107) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 107")
                        operation_code_107_exec(nodedata)
                elseif (nodedata.OperationCode == 108) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 108")
                        operation_code_108_exec(nodedata)  
                elseif (nodedata.OperationCode == 111) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 111")
                        operation_code_111_exec(nodedata)
                elseif (nodedata.OperationCode == 112) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 112")
                        operation_code_112_exec(nodedata)
                elseif (nodedata.OperationCode == 120) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 120")
                        operation_code_120_exec(nodedata)
                elseif (nodedata.OperationCode == 200) then
                        freeswitch.consoleLog("notice","Terminating the Call")
                        session:hangup()
                elseif (nodedata.OperationCode == 330) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 330")
                        operation_code_330_exec(nodedata)
                elseif (nodedata.OperationCode == 331) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 331")
                        operation_code_331_exec(nodedata)			
                elseif (nodedata.OperationCode == 341) then
                        freeswitch.consoleLog("notice","Executing Opeartion Code 341")
                        operation_code_341_exec(nodedata)			
                else    freeswitch.consoleLog("err","========== Operation Code " .. nodedata.OperationCode .. " is not Configured in service =================")
                        session:hangup();
                end
        end


        function Sub_menu(nodeid)
                --local iVRNodeId,iVRNodeName,operationCode,audioFile,validKeys,invalidInputAudioFile = 1;
                freeswitch.consoleLog("notice","Sub Menu IVR Child Node ID: " .. nodeid)
		  for key, value in pairs(ivrdata) do
                         if value.NodeId == nodeid then
			    execute_operation(value)
			    break
                      end
                  end
        end
	
	if session:answered() and session:getVariable("cc_last_nodeId") ~= nil then
		freeswitch.consoleLog("NOTICE","************* Agent Evaluation *******************")
		local cc_nodeId = session:getVariable("cc_last_nodeId")
		local cc_cancel_reason = session:getVariable("cc_cancel_reason")
		local cc_agent_bridged = session:getVariable("cc_agent_bridged")
		if cc_cancel_reason == "TIMEOUT" then 
			freeswitch.consoleLog("NOTICE","******** cc_cancel_reason :: "..cc_cancel_reason)
			--local sound = audiopath .. "BusyTone.wav";
			--session:execute("playback", sound)
                      session:set_tts_params("flite", "slt");
                        session:execute("sleep","1000")
                        session:speak("Sorry, the agents are not available or busy at this moment");
                        session:execute("sleep","1000")
                        session:speak("Thank you..");
                        session:execute("sleep","1000")
                      session:hangup()
		end
		if cc_agent_bridged == "true" then freeswitch.consoleLog("NOTICE","******** cc_agent_bridged :: "..cc_agent_bridged)
		local cc_agent_extension = session:getVariable("cc_agent")
		session:setVariable("Receiver_Extension_Code",cc_agent_extension)
		local ext_not_reg = "error/user_not_registered"
		local extension_status = api:executeString("sofia_contact " .. cc_agent_extension)
		freeswitch.consoleLog("notice", cc_agent_extension .. " Extension Status : " .. extension_status)
		if extension_status ~= ext_not_reg  then
			api:executeString("callcenter_config agent set status " .. cc_agent_extension .. " Available")
			api:executeString("callcenter_config agent set contact " .. cc_agent_extension .. " " .. extension_status);
			api:executeString("callcenter_config agent set state " .. cc_agent_extension .. " Waiting")
		else
			freeswitch.consoleLog("notice","Extension " .. cc_agent_extension .. " Not registered . Changing status to Logged Out ..")
			api:executeString("callcenter_config agent set status " .. cc_agent_extension .. " 'Logged Out'")
		end
		freeswitch.consoleLog("NOTICE","Agent Evaluation Node ID: "..cc_nodeId)
                  for key, value in pairs(ivrdata) do
                    if value.NodeId == tonumber(cc_nodeId) then
                     iVRChildNodeId = value.ChildNodeConfig[1].ChildNodeId;
		     freeswitch.consoleLog("NOTICE","child Node ID: "..iVRChildNodeId)
                     Sub_menu(iVRChildNodeId)
                     break
                    end
		  end
		end
		--freeswitch.consoleLog("NOTICE","Child Node ID Not found")
		session:hangup()
	end

if session:ready() then
	local callLogId = callLog.create()
	--session:setVariable("sip_h_X-CallLogId","1133")
        session:answer()
	session:execute("sleep","500")
        freeswitch.consoleLog("notice",call_uuid..": Session Answered\n")
                freeswitch.consoleLog("notice", call_uuid..": Entered menu function\n")
                --local iVRNodeId,iVRNodeName,operationCode,audioFile,isStartNode,validKeys,invalidInputAudioFile,repeatLimit;
                for _, node in pairs(ivrdata) do
                        if(node.IsStartNode == true) then
                	    freeswitch.consoleLog("notice","...Start Menu found... IVR Node ID:" ..node.NodeId.. "  IVR Node Name: " ..node.NodeName.. " Operation Code: " ..node.OperationCode);
			    execute_operation(node)
			    break
                     end

                 end
end
