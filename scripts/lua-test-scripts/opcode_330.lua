local json = require "lunajson"
--api = freeswitch.API();
local redis = require "redis".connect('127.0.0.1',6379) -- redis client connect
--local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfigurationV6');", 0)) -- storing the IVRNodes data
local ivrconfig = json.decode(redis:eval("return redis.call('json.get','IVRConfiguration_tts');", 0)) -- storing the IVRNodes data
local ivrdata = ivrconfig.IVRConfiguration[1].IVRProcessFlow;
local generalSettings = ivrconfig.IVRConfiguration[1].GeneralSettingValues

local webApi_Config = json.decode(redis:eval("return redis.call('json.get','IVRWebAPIConfig_tts');", 0))
local webApiData = webApi_Config.result

local ivrextensions = redis:eval("return redis.call('json.get','Extensions_qa');", 0) -- storing the IVRNodes data
local agent_extensions = json.decode(ivrextensions)

local ivrrecording_data = redis:eval("return redis.call('json.get','RecordingType_qa');", 0)
local recording_config = json.decode(ivrrecording_data)
local audiopath = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/ivr_audiofiles_tts/"
local recording_dir = '/usr/local/freeswitch-automax-instance/var/lib/freeswitch/recordings/IVR-CCM-Recordings/'

local function operation_code_330_exec(data) --Speech to Text
	--local tts_text = session:getVariable(data.DeafultInput);
	local tts_text = "I N 0000001212313"
        --session:set_tts_params("flite", session:getVariable(TTSVoiceNameBuiltIn));
        session:set_tts_params("flite", "rms");
        session:execute("sleep","1000")
       session:speak("Incident is created successfully and the Incident number is "..tts_text);
        session:execute("sleep","1000")
       session:hangup()
end

local function operation_code_331_exec(data) --Speech to Text
	--local tts_text = session:getVariable(data.DeafultInput);
	local tts_text = "66208,IN0000003601"
	--session:execute("set","tts_engine=azure_tts")
	--session:execute("set","tts_voice=ar-SA-ZariyahNeural")
        session:set_tts_params("azure_tts", "ar-SA-ZariyahNeural");
        session:speak("{AZURE_SUBSCRIPTION_KEY=1cfc10bab7f54e53bb5fad1b6d6dfee4,AZURE_REGION=uksouth,speed=0}"..tts_text);
        session:execute("sleep","1000")
       session:hangup()
       end
if session:ready() then
        --local callLogId = callLog.create()
        session:setVariable("sip_h_X-CallLogId","1133")
        session:answer()
        session:execute("sleep","500")
        freeswitch.consoleLog("notice","Session Answered")
                freeswitch.consoleLog("notice","Entered menu function\n")
	for key, data in pairs(ivrdata) do
	    if(data.OperationCode == 331) then
        	freeswitch.consoleLog("notice","...Start Menu found... IVR Node ID:" ..data.NodeId.. "  IVR Node Name: " ..data.NodeName.. " Operation Code: " ..data.OperationCode);
	        operation_code_331_exec(data)
	    	break
	    end
	end
end
