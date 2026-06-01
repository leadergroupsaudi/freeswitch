local config = {}

--base_url = "https://beta.axionic.io/AXBFF"
base_url_new ="https://wapi.discretal.com"
config.api = {
--	authenticate_api = base_url.."/Auth/User/Login",
--	createCallLog_api = base_url.."/Centrix/CallLogs/CreateCallLogV2",
	callLog_api = base_url_new.."/calls/addAxionicDetails",
--	getUserPresence_api = base_url.."/V2/Administration/User/Presence/Extension",
--	callNotification_api = base_url.."/V2/Administration/UserNotification/Call",
--	getCallLogs_api = base_url.."/Centrix/CallLogs/GetLogById/",
--	updateAfterCall_api = base_url.."/Centrix/CallLogs/UpdateAfterCall"
}

--config.payload = {
--	authenticate_api = "{\"username\":\"axionicpbx@leadergroup.com\",\"password\":\"PbXAdm_sysMgr@Ldr_966\",\"rememberMe\":false,\"sourceId\":\"77.240.91.133\"}"
--}

return config
