-- resources/ivrFunctions.lua

local ivrFunctions = {}

function ivrFunctions.find_childNode(data)
    -- Implementation for finding a child node
end

function ivrFunctions.find_childNode_with_dtmfinput(digits, data)
    -- Implementation for finding a child node with DTMF input
end

function ivrFunctions.operation_code_10_exec(data)
    		-- Play the Audio File
		freeswitch.consoleLog("notice","*********** Entered Operation Code Function 10 {Play Audio} **************")
                local sound = audiopath .. data.VoiceFileId;
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

function ivrFunctions.operation_code_11_exec(data)
    		-- Play the Audio File from Tag value
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

function ivrFunctions.operation_code_20_exec(data)
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

function ivrFunctions.operation_code_30_exec(data)
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
        end



function ivrFunctions.execute_operation(nodedata)
    -- Implementation for executing an operation
end

return ivrFunctions

