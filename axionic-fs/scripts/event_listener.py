#!/usr/bin/env python

import string
import sys
from freeswitchESL import ESL
import json
import requests
import logging
import asyncio
from functools import partial
import time
import base64
import os
import re
import subprocess
from genesis import Consumer
from datetime import datetime

# Gets or creates a logger
logger = logging.getLogger(__name__)

# set log level
logger.setLevel(logging.DEBUG)

# define file handler and set formatter
fs_base_path = "/usr/local/freeswitch-prod-instance"
log_file_path = fs_base_path+"/var/log/freeswitch/events.log"
if not os.path.exists(log_file_path):
	open(log_file_path, 'a').close()
file_handler = logging.FileHandler(log_file_path)
formatter	 = logging.Formatter('%(asctime)s : %(levelname)s : %(name)s : %(message)s')
file_handler.setFormatter(formatter)
logger.propagate = False

# add file handler to logger
logger.addHandler(file_handler)
base_url= "https://Stagingapp.axionic.io/AXBFF"
login_credentials = {"username":"axionicpbx@leadergroup.com","password":"PbXAdm_sysMgr@Ldr_966","rememberMe":False,"sourceId":"77.240.91.132"}
url = base_url+'/Auth/User/Login'
presence_url =  base_url+"/V2/Administration/User/Presence/Extension?Source=SIP"
get_userstatus_api = base_url+"/V2/Administration/User/Presence/Extension" 
voicemail_store_url =  base_url+"/Centrix/VoiceMail"
callLog_update_api = base_url+"AXBFF/Centrix/CallLogs/UpdateAfterCall"
call_record_upload_api = base_url+"/Call/Recording"
call_record_status_api = base_url+"/Call/Recording/UpdateStatus"
get_callLog_api=  base_url+"/Centrix/CallLogs/GetLogById"
callLog_addparticipant_api=  base_url+"/Call/CallLog/Participant/Extension?Domain="
updateParticipant_api =  base_url+"/Call/CallLog/Participant/Extension"
meetingNotification_api =  base_url+"/Meeting/Meeting/Notification?MeetingId={}&Status=S&Initiator={}&extension={}"
callrecord_api =  base_url+"/Call/Chat?Domain="
event_data = {}
token_header = None

def getToken():
	logger.debug("Access Token Request")
	global token_header
	cmd = fs_base_path+"/bin/fs_cli --password='LIGeven-socke$545&' -x 'global_getvar access_token'"
	logger.debug("FS Get Token cmd is {}".format(cmd))
	access_token = subprocess.check_output(cmd, shell=True, universal_newlines=True).strip()
	logger.debug("FS Command Access Token {}".format(access_token))
	if "ERR" in access_token:
		logger.debug("Freeswitch access Token is not available. Generating a Token")
		headers = { 'AppKey': 'DHhCs9PNERBws/CVWqkzhA', 'AppType': 'enduser', 'language': 'en', 'Content-Type': 'application/json'}
		try:
			response = requests.post(url, headers=headers, json=login_credentials)
			if response.status_code == 200:
				access_token = response.json()["response"]["token"]
				logger.debug("Access Token Response: {}".format(access_token))
				token_header = {'Authorization': 'Bearer ' + access_token}
				cmd = fs_base_path+"/bin/fs_cli --password='LIGeven-socke$545&' -x 'global_setvar access_token="+access_token+"'"
				subprocess.check_output(cmd, shell=True, universal_newlines=True).strip()
			else:
				logger.debug("Authenticate API Response Code: {} and Response status: {} ".format(response.status_code,response.text))
		except requests.exceptions.RequestException as e:
			logger.debug("Authenticate API Exception: {}".format(e))
	else:
		token_header = {'Authorization': 'Bearer ' + access_token}				
# === Persistent global ESL connection ===
#try:
 #   conn = ESL.ESLconnection("127.0.0.1", "8021", "LIGeven-socke$545&")
  #  if not conn.connected():
   #     raise Exception("Failed to connect to FreeSWITCH ESL")
    #else:
     #   logger.info("Connected to FreeSWITCH ESL successfully")
#except Exception as e:
 #   logger.error(f"ESL connection failed: {e}")
  #  conn = None
app = Consumer("127.0.0.1", 8021, "LIGeven-socke$545&")
def connect_to_fs():
	conn = ESL.ESLconnection("127.0.0.1","8021","LIGeven-socke$545&")
	return conn

def send_notify_event(event,action):
	fs_conn = connect_to_fs()
	if not fs_conn:
		logger.debug("Can not connect to FS server")
		return
	
	event_obj = ESL.ESLevent("NOTIFY")
	event_obj.addHeader("profile",event.get("variable_sofia_profile_name"))
	event_obj.addHeader("event-string",action)
	
	if event.get('Call-Direction') == 'inbound':
		event_obj.addHeader("user", event.get("variable_sip_to_user"))
		event_obj.addHeader("host", event.get("variable_sip_domain_name"))
		message = event.get("Caller-Caller-ID-Number")
		logger.debug(" {} event direction inbound variable user {} host {} and message {}".format(action,event.get("variable_sip_to_user"),event.get("variable_sip_domain_name"),message))
	else:
		event_obj.addHeader("user", event.get("variable_sip_from_user"))
		event_obj.addHeader("host", event.get("variable_sip_domain_name"))		
		message = event.get("Caller-Caller-ID-Number")
		uuid_Remoteleg = event.get("variable_originate_leg_uuid")
		if action == 'hold':
			cmd = "uuid_broadcast "+uuid_Remoteleg+" local_stream://moh"
			logger.debug("uuid broadcast cmd is {}".format(cmd))
			fs_conn.api(cmd)
		if action == 'talk':
			cmd = "uuid_break "+uuid_Remoteleg
			logger.debug("uuid break broadcast cmd is {}".format(cmd))
			fs_conn.api(cmd)
			#fs_conn.disconnect()
		logger.debug(" {} event outbound variable user {} host {} and message {}".format(action,event.get("variable_sip_from_user"),event.get("variable_sip_domain_name"),message))
	#needs to be tested with Linphone SDK
	#event_obj.addHeader("uuid", event.get("Other-Leg-Unique-ID"))	
	event_obj.addHeader("Content-Type", "text/plain")
	event_obj.addBody(message)
	event_obj.delHeader("Event-Name")
	
	
	resp = fs_conn.sendEvent(event_obj)
	logger.debug("Received response from server {}".format(resp.serialize("json")))
	fs_conn.disconnect()
	
def set_channel_var(event):
	try:		   
		uuid = event.get("variable_originating_leg_uuid")
		if uuid:
			fs_conn = connect_to_fs()
			cmd = "uuid_setvar "+uuid+" "+"sip_term_status"+ " true"
			logger.debug("cmd is {}".format(cmd))
			fs_conn.api(cmd)
			fs_conn.disconnect()  
	except Exception as e:
		logger.debug("Got exception in set_channel_var event handler {}".format(e))
		
def post_presence_data(presence_data):
	if token_header:
		logger.debug("Posting Presence Data from FS: {}".format(presence_data))
		resp = requests.put(presence_url, headers=token_header, json=presence_data)
		logger.debug("The received http response for Post Presenece status API is {}".format(resp))
		if resp.status_code == 200:
			logger.debug("Successfully posted presence status {}".format(presence_data))
		else:
			logger.debug("Failed to Post user Presence status")
	else:
		logger.debug("Authentication Token not found")


def update_participant_inCallStatus(json_string):
	logger.debug("Entered into Participant incallStatus update block")
	logger.debug("Participant payload data is {}".format(json_string))
	if token_header:
		token_header['Content-Type'] = 'application/json'
		response = requests.put(updateParticipant_api,data=json_string,headers=token_header)
		if response.status_code == 200:
			data = response.json()
			logger.debug("Posted InCallStatus data successfully:: {}".format(data))
		else:
			logger.debug("Remove participant InCallStatus Request failed with status code format {}".format(response.status_code))
	else:
		logger.debug("Unable to get token from API server so remove_participant InCallStatus can not be posted")


def get_userstatus_data(from_user,sip_domain_name):
	if token_header:
		user_payload = {'domain':sip_domain_name,'extensionCodes':[from_user]}
		logger.debug("Get User Presence Payload {}".format(user_payload))
		resp = requests.post(get_userstatus_api, headers=token_header, json=user_payload)
		if resp.status_code == 200:
			user_status = resp.json()
			return user_status
		else:
			logger.debug("Unable to get userstatus of {} due to error {}".format(from_user,resp))
	else:
		logger.debug("Unable to get token from API server so not able to get userstatus")

def get_registration_count(user,domain):
	fs_conn		= connect_to_fs()
	user_cmd	= "sofia_count_reg "+user+"@"+domain
	regCount	 = fs_conn.api(user_cmd)
	regCount	 = regCount.getBody()
	logger.debug("Registration Count of user {}@{} is {} ".format(user,domain,regCount))
	fs_conn.disconnect()
	return regCount

def send_voicemail_to_axionic_server(event):
	try:
		logger.debug ("Voicemail file upload section")
		file_path = event.get("variable_voicemail_file_path")
		from_extension	= event.get("Caller-Caller-ID-Number")
		to_extension	= event.get("variable_sip_to_user")
		sip_domain_name = event.get("variable_sip_domain_name")
		file_location, file_name = os.path.split(file_path)
		vm_duration = event.get("variable_voicemail_message_len")
		current_time = datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
		current_time = current_time+"Z"
		payload = {'FromExtension': from_extension, 'ToExtension': to_extension,'Domain': sip_domain_name, 'VoiceMailDuration': vm_duration}
		files=[('File',(file_name,open(file_path,'rb')))]
		logger.debug("VoiceMail Payload {}".format(payload))
		if token_header:
			token_header.pop('Content-Type', None)
			logger.debug("Voicemail token header validated. Hitting voicemail upload API")
			response = requests.post(voicemail_store_url, headers=token_header, data=payload, files=files)
			response.raise_for_status()
			resp = response.json()
			logger.debug("VoiceMail API response {}".format(response))
			logger.debug("VoiceMail API json response data {}".format(resp))
			if 'httpStatusCode' in resp.keys() and resp['httpStatusCode'] == 'OK':
				logger.debug("Successfully uploaded voicemail file {}".format(file_path))
				os.remove(file_path)
			else:
				old_file = os.path.join(file_location, file_name)
				bkp_file_name = file_name + "_bkp"
				new_file = os.path.join(file_location, bkp_file_name)
				logger.debug("Unable to upload voicemail file {}".format(file_path))
				os.rename(old_file, new_file)
	except Exception as e:
		logger.debug("Got exception in send_voicemail_to_axionic_server unable to upload voicemail to server {}".format(e))
		old_file = os.path.join(file_location, file_name)
		bkp_file_name = file_name + "_bkp"
		new_file = os.path.join(file_location, bkp_file_name)
		logger.debug("Unable to upload voicemail file {}".format(file_path))
		os.rename(old_file, new_file)

def send_audio_recording_to_axionic_server(event):
	try:
		logger.debug ("Audio file recording file upload section")
		file_path = event.get("Record-File-Path")
		index = file_path.find('/')
		trimmed_file_path = file_path[index:]
		#record_format = event.get("variable_avformat")
		logger.debug("recording file path: {}".format(trimmed_file_path))
		file_location, file_name = os.path.split(file_path)
		record_duration = event.get("variable_record_seconds")
		logger.debug("recording file name {}".format(file_name))
		if "variable_record_start_time" in event:
			record_time = datetime.strptime(event.get("variable_record_start_time"), "%Y-%m-%d %H:%M:%S")
			record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")
			record_start_time = record_start_time+"Z"
		elif "variable_cc_queue_answered_epoch" in event:
			record_time = datetime.utcfromtimestamp(int((event.get("variable_cc_queue_answered_epoch"))))
			record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")+"Z"
		else:
			record_time = datetime.utcfromtimestamp(event.get("Other-Leg-Channel-Answered-Time"))
			record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")+"Z"
		callLogID = event.get("variable_sip_h_X-CallLogId")
		record_count = event.get("variable_record_count")
		recordtype = event.get("variable_isvideocall")
		if recordtype == "true":
			recordtype = "V"
		else:
			recordtype = "A"
		payload={'CallLogId': callLogID, 'RecordingType': recordtype,'RecordingDate':record_start_time, 'Duration':record_duration,'UploadStatus': 'I'}
		files=[('File',(file_name,open(trimmed_file_path,'rb'),'audio/wav'))]
		logger.debug("call record pyload Data {}".format(payload))
		if token_header:
			token_header.pop('Content-Type', None)
			response = requests.post(call_record_upload_api, headers=token_header, data=payload, files=files)
			resp = response.json()
			logger.debug("Call record API response {}".format(response))
			logger.debug("Call record API json response data {}".format(resp))
			if 'httpStatusCode' in resp.keys() and resp['httpStatusCode'] == 'OK':
				logger.debug("Successfully uploaded recording file {}. Trying to change the upload Status to A".format(trimmed_file_path))
				update_Callrecord_status(callLogID)
				#os.remove(trimmed_file_path)
			else:
				#old_file = os.path.join(file_location, file_name)
				#bkp_file_name = file_name + "_bkp"
				#new_file = os.path.join(file_location, bkp_file_name)
				logger.debug("Cant upload audio recording file {}".format(trimmed_file_path))
				#os.rename(old_file, new_file)
	except Exception as e:
		logger.debug("Got exception in send_audio_recording_to_axionic_server unable to upload audio recording file to server {}".format(e))
		#old_file = os.path.join(file_location, file_name)
		#bkp_file_name = file_name + "_bkp"
		#new_file = os.path.join(file_location, bkp_file_name)
		#logger.debug("Unable to upload audio recording file {}".format(file_path))
		#os.rename(old_file, new_file)

def update_Callrecord_status(callLogID):
	try:
		recordStatus_payload = {'RecordingId':callLogID,'UploadStatus':'A'}
		response = requests.put(call_record_status_api, headers=token_header, json=recordStatus_payload)
		resp = response.json()
		logger.debug("Call record status update 'A' API json response data {}".format(resp))
		if response.status_code == 200:
			logger.debug("Call Recording Status seccuss status updated.")
		else:
			logger.debug("Cant update the call recording update status")
	except Exception as e:
		logger.debug("Got exception in update_Callrecord_status. unable to update the call Record update status {}".format(e))


def send_groupaudio_recording_to_axionic_server(event):
	try:
		logger.debug ("Audio file recording file upload section")
		file_path = event.get("record_path")
		#index = file_path.find('/')
		#trimmed_file_path = file_path[index:]
		#record_format = event.get("variable_avformat")
		logger.debug("recording file path: {}".format(file_path))
		file_location, file_name = os.path.split(file_path)
		record_duration = event.get("record_duration")
		logger.debug("recording file name {}".format(file_name))
		if "record_start_time" in event:
			record_time = datetime.strptime(event.get("record_start_time"), "%Y-%m-%d %H:%M:%S")
			record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")
			record_start_time = record_start_time+"Z"
		#elif "variable_cc_queue_answered_epoch" in event:
		#	record_time = datetime.utcfromtimestamp(int((event.get("variable_cc_queue_answered_epoch"))))
		#	record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")+"Z"
		#else:
		#	record_time = datetime.utcfromtimestamp(event.get("Other-Leg-Channel-Answered-Time"))
		#	record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S")+"Z"
		callLogID = event.get("sip_h_X-CallLogId")
		#record_count = event.get("variable_record_count")
		recordtype = event.get("isvideocall")
		payload={'CallLogId': callLogID, 'RecordingType': recordtype,'RecordingDate':record_start_time, 'Duration':record_duration}
		files=[('File',(file_name,open(file_path,'rb'),'audio/wav'))]
		logger.debug("call record pyload Data {}".format(payload))
		if token_header:
			token_header.pop('Content-Type', None)
			response = requests.post(call_record_upload_api, headers=token_header, data=payload, files=files)
			resp = response.json()
			logger.debug("Call record API response {}".format(response))
			logger.debug("Call record API json response data {}".format(resp))
			if 'httpStatusCode' in resp.keys() and resp['httpStatusCode'] == 'OK':
				logger.debug("Successfully uploaded recording file {}".format(file_path))
				#os.remove(file_path)
			else:
				old_file = os.path.join(file_location, file_name)
				bkp_file_name = file_name + "_bkp"
				new_file = os.path.join(file_location, bkp_file_name)
				logger.debug("Cant upload audio recording file {}".format(file_path))
				os.rename(old_file, new_file)
	except Exception as e:
		logger.debug("Got exception in send_audio_recording_to_axionic_server unable to upload audio recording file to server {}".format(e))
		old_file = os.path.join(file_location, file_name)
		bkp_file_name = file_name + "_bkp"
		new_file = os.path.join(file_location, bkp_file_name)
		logger.debug("Unable to upload audio recording file {}".format(file_path))
		os.rename(old_file, new_file)


def get_callLog_details(callLogID):
	logger.debug("Entered get_CallLOG block")
	if token_header:
		response = requests.get(get_callLog_api+"/"+callLogID, headers=token_header)
		if response.status_code == 200:
			data = response.json()
			return data
		else:
			logger.debug("get_callLog_details Request failed with status code format {}".format(response.status_code))
	else:
		logger.debug("Unable to get token from API server so Get CDR list data not retrieved")

def update_callLog_data(payload):
	logger.debug("Entered into Update recent call logs block")
	logger.debug("CallLog payload Data is {}".format(payload))
	if token_header:
		token_header['Content-Type'] = 'application/json'
		response = requests.put(callLog_update_api,data=payload,headers=token_header)
		if response.status_code == 200:
			data = response.json()
			logger.debug("Posted update_callLogData CDR Recent list successfully:: {}".format(data))
		else:
			logger.debug("update_callLog_data Request failed with status code format {}".format(response.status_code))
	else:
		logger.debug("Unable to get token from API server so update_cdr record can not be posted")

def add_callLog_participant(payload, sip_domain_name):
	logger.debug("Entered into add_callLog_participant block")
	logger.debug("CallLog payload Data is {}".format(payload))
	if token_header:
		token_header['Content-Type'] = 'application/json'
		response = requests.post(callLog_addparticipant_api+sip_domain_name,data=payload,headers=token_header)
		if response.status_code == 200:
			data = response.json()
			logger.debug("Posted add_participant CDR data successfully:: {}".format(data))
		else:
			logger.debug("add_callLog_participant Request failed with status code format {}".format(response.status_code))
	else:
		logger.debug("Unable to get token from API server so add_participant cdr record can not be posted")

def call_record_api(payload,sip_domain_name):
		logger.debug("Entered into callrecord_api with domain {}".format(sip_domain_name))
		logger.debug("Call_record payload Data is {}".format(payload))
		if token_header and sip_domain_name:
				token_header.pop('Content-Type', None)
				response = requests.post(callrecord_api+sip_domain_name,data=payload,headers=token_header)
				#if response.status_code == 200:
				data = response.json()
				logger.debug("API Response for call record Chat Insert :: {}".format(data))
				#else:
				#	   logger.debug("call record Request failed with status code format {}".format(response.status_code))
		else:
				logger.debug("Unable to get token or Domain name")

def meeting_notification_data(meetingUrl, payload):
	logger.debug("Entered into meeting Notification update block")
	if token_header:
		token_header['Content-Type'] = 'application/json'
		response = requests.post(meetingUrl,data=payload,headers=token_header)
		if response.status_code == 200:
			data = response.json()
			logger.debug("Posted MeetingNotification data successfully posted:: {}".format(data))
		else:
			logger.debug("Meeting Notification data Request failed with status code format {}".format(response.status_code))
	else:
		logger.debug("Unable to get token from API server so Meeting_Notification can not be posted")

#@app.handle("RECORD_STOP")
#async def record_stop_event_handler(event):
#	logger.debug("Received RECORD_STOP event {}".format(event))
#	xcallLogID = event.get("variable_sip_h_X-CallLogId")
#	current_app = event.get("variable_current_application")
#	call_direction = event.get("Call-Direction")
#	logger.debug("X-CallLogId of call Record {}".format(xcallLogID))
#	try:		
#		if "variable_sip_h_X-CallLogId" in event and current_app != "voicemail":
#			logger.debug("*********Calling Function Recording file upload *************")
#			send_audio_recording_to_axionic_server(event)
#	except Exception as e:
#		logger.debug("Got exception in RECORD_STOP handler {}".format(e))


#@app.handle("RECORD_EVENT")
#async def record_event_handler(event):
#	logger.debug("Received RECORD_EVENT event {}".format(event))
#	xcallLogID = event.get("sip_h_X-CallLogId")
#	try:		
#		if "sip_h_X-CallLogId" in event:
#			logger.debug("*********Calling Function Recording file upload *************")
#			send_groupaudio_recording_to_axionic_server(event)
#	except Exception as e:
#		logger.debug("Got exception in RECORD_EVENT handler {}".format(e))

@app.handle("CHANNEL_HOLD")
async def hold_event_handler(event):
	logger.debug("Received CHANNEL_HOLD event {}".format(event))
	try:		
		send_notify_event(event,"hold")		
	except Exception as e:
		logger.debug("Got exception in CHANNEL_HOLD handler {}".format(e))
				
@app.handle("CHANNEL_UNHOLD")
async def unhold_event_handler(event):
	logger.debug("Received CHANNEL_UNHOLD event {}".format(event))
	try:		
		send_notify_event(event,"talk")		
	except Exception as e:
		logger.debug("Got exception in CHANNEL_UNHOLD handler {}".format(e))

@app.handle("sofia::register")
async def register_event_handler(event):
	logger.debug("Received REGISTER event")
	from_user = event.get("from-user")
	sip_domain_name = event.get("from-host")
	logger.debug("The Registration Received - user id {}@{}".format(from_user,sip_domain_name))
	try:
		user_status = get_userstatus_data(from_user,sip_domain_name)
		logger.debug("Get UserPresence Data {}".format(user_status))
		if user_status and 'response' in user_status:
			current_status_code = user_status['response'][0]['currentStatusCode']
			logger.debug("Current status code: {}".format(current_status_code))
			if current_status_code == 'SIC' or current_status_code == 'SIM':
				logger.debug("current status of user is SIC, So not changing the status")
			else:
					presence_data = {'domain':sip_domain_name,'extensions':[{'extensionCode': from_user,'statusCode': 'SAV'}]}
					post_presence_data(presence_data)
		else:
			logger.debug("User Presence status not found in GetUserPresence API response")
	except Exception as e:
		logger.debug ("Got exception in register_event_handler {}".format(e))

@app.handle("sofia::unregister")
async def unregister_event_handler(event):
	global token
	logger.debug("Received UN-REGISTER event")
	from_user = event.get("from-user")
	sip_domain_name = event.get("from-host")
	logger.debug("The Un-Registered user id {}@{}".format(from_user,sip_domain_name))
	regCount = get_registration_count(from_user,sip_domain_name)
	try:
		presence_data = {'domain': sip_domain_name,'extensions':[{'extensionCode': from_user,'statusCode': 'SOF'}]}
		if int(regCount) == 0:
			post_presence_data(presence_data)
	except Exception as e:
		logger.debug ("Got exception in unregister_event_handler {}".format(e))

#@app.handle("conference::maintenance")
#async def conference_maintenance_event_handler(event):
#	global event_data
#	try:
#		if event.get("Action") == "del-member":
#			logger.debug("Received CONFERENCE_MAINTENANCE:del-member event ")
#			extension = event.get("Caller-Caller-ID-Number")
#			sip_domain_name = event.get("variable_sip_domain_name")
#			logger.debug("Extension Number for removed participant in Event: {}".format(extension))
#			conferenceName = event.get("Conference-Name")
#			parts = conferenceName.split("_")
#			#callLogId = int("".join(filter(str.isdigit, conferenceName)))
#			if len(parts) > 1 and parts[1]:
#				callLogId = int(parts[1])
#				logger.debug("CallLogId for removed participant in Event: {}".format(callLogId))
#				incall_data = {'domain': sip_domain_name,'callLogId': callLogId,'extension': extension,'inCallStatus': 'N'}
#				incall_data = json.dumps(incall_data)
#				update_participant_inCallStatus(incall_data)
#		elif event.get("Action") == "add-member":
#			logger.debug("Received CONFERENCE_MAINTENANCE:add-member event {}".format(event))
#			extension = event.get("Caller-Caller-ID-Number")
#			sip_domain_name = event.get("variable_sip_domain_name")
#			logger.debug("Extension Number for join participant in Event: {}".format(extension))
#			conferenceName = event.get("Conference-Name")
#			parts = conferenceName.split("_")
			#callLogId = int("".join(filter(str.isdigit, conferenceName)))
#			if len(parts) > 1 and parts[1]:
#				callLogId = int(parts[1])
#				logger.debug("CallLogId for join participant in Event: {}".format(callLogId))
#				incall_data = {'domain': sip_domain_name,'callLogId': callLogId,'extension': extension,'inCallStatus': 'A'}
#				incall_data = json.dumps(incall_data)
#				update_participant_inCallStatus(incall_data)
#		elif event.get("Action") == "conference-create" and event.get("Conference-Profile-Name") == "meetings":
#			logger.debug("Received CONFERENCE_MAINTENANCE:conference-create event")
#			meetingId = event.get("variable_sip_h_X-MeetingId")
#			logger.debug("meetingId for event got: {}".format(meetingId))
#			Initiator = event.get("Caller-Caller-ID-Name")
#			logger.debug("Meeting started by Initiator: {}".format(Initiator))
#			callLogId = event.get("variable_sip_h_X-CallLogId")
#			roomID = event.get("variable_room_id")
#			extension = event.get("variable_sip_from_user")
#			logger.debug("Meeting started extension: {}".format(extension))
#			logger.debug("Meeting callogID: {}".format(callLogId))
#			logger.debug("Meeting roomID: {}".format(roomID))
#			payload = {}
#			meetingUrl = meetingNotification_api.format(meetingId, Initiator, extension)
#			meeting_notification_data(meetingUrl, payload)
#		elif event.get("Action") == "execute_app" and event.get("Application") == "execute_extension MEETING_START_RECORDING XML public" or event.get("Application") == "execute_extension CONF_START_RECORDING XML public":
#			start_time = event.get("Event-Date-Local")
#			format_start_time = datetime.strptime(start_time, '%Y-%m-%d %H:%M:%S')
#			record_start_time = format_start_time.strftime('%Y-%m-%dT%H:%M:%SZ')
#			callLogId = event.get("variable_sip_h_X-CallLogId")
#			sip_domain_name = event.get("variable_sip_domain_name")
#			recordtype = event.get("variable_isvideocall")
#			extensionCode = event.get("variable_sip_from_user")
#			logger.debug("Call Record Event data: {} ".format(event))
#			if recordtype == "true":
#		true = True
#		if (event.get("Answer-State") == "answered"):
#			if (event.get("Call-Direction") == "inbound"):
#				extension	= event.get("Caller-Caller-ID-Number")
#				sip_domain_name	= event.get("variable_sip_domain_name")
#				logger.debug("Extension Number found in inbound CALL_ANSWER Event {}".format(extension))
#				if "variable_sip_h_X-MeetingId" in event:
#					presence_data = {'domain':sip_domain_name,'extensions':[{'extensionCode': extension,'statusCode': 'SIM'}]} 
#				else:
#					presence_data = {'domain':sip_domain_name,'extensions':[{'extensionCode': extension,'statusCode': 'SIC'}]}
#			elif (event.get("Call-Direction") == "outbound"):
#				extension	= event.get("Caller-Callee-ID-Number")
#				sip_domain_name	= event.get("variable_sip_domain_name")
#				logger.debug("Extension Number found in Outbound CALL_ANSWER Event {}".format(extension))
#				if "variable_sip_h_X-MeetingId" in event:
#					presence_data = {'domain':sip_domain_name,'extensions':[{'extensionCode': extension,'statusCode': 'SIM'}]}
#				else:
#					presence_data = {'domain':sip_domain_name,'extensions':[{'extensionCode': extension,'statusCode': 'SIC'}]}
#			post_presence_data(presence_data)
#	except Exception as e:
#		logger.debug ("Got exception in setting Incall status {}".format(e))
#@app.handle("CHANNEL_ANSWER")
async def channel_answer_event_handler(event):
    asyncio.create_task(process_channel_answer(event))


async def process_channel_answer(event):
    try:
        call_direction = (event.get("Call-Direction") or "").lower()
        logger.info(f"Call Direction: {call_direction}")

        # Only process inbound calls
        if call_direction != "inbound":
            logger.debug("Skipping CHANNEL_ANSWER: not inbound")
            return

        # Extract caller and callee
        caller = event.get("Caller-Caller-ID-Number", "")
        callee = event.get("Caller-Destination-Number", "")

        # Only continue if either caller or callee has 6–12 digits
        if 6 <= len(caller) <= 12 or 6 <= len(callee) <= 12:

            # Default assignment
            phone = caller
            extension = callee
            call_using = "phone"

            # Swap if callee length is 6–12 digits
            if 6 <= len(callee) <= 12:
                phone = callee
                extension = caller
                call_using = "sip"

            logger.info(f"CHANNEL_ANSWER triggered | Direction: {call_direction} | Phone: {phone} | Extension: {extension}")

            payload = {"phone": phone, "extension": extension, "call_using": call_using}
            api_url = "https://wapis.discretal.com/calls/phone-sip-call"

            # Run blocking request in a separate thread
            response = await asyncio.to_thread(requests.post, api_url, json=payload, timeout=5, verify=False)
            response.raise_for_status()

            json_api_response = response.json()
            callLogId = json_api_response.get("response", {}).get("sipCallDetails", {}).get("call_id")

            if callLogId:
                logger.info(f"Received callLogId: {callLogId}")
                conn = connect_to_fs()
                if conn and conn.connected():
                    uuid = event.get("Unique-ID")
                    if uuid:
                        conn.api("uuid_setvar", f"{uuid} sip_h_X-CallLogId {callLogId}")
                        conn.api("uuid_setvar", f"{uuid} Call_Log_Id {callLogId}")
                        logger.info(f"Set callLogId={callLogId} for UUID={uuid}")
                    else:
                        logger.warning("No UUID found in event; cannot set channel variable")
                else:
                    logger.error("Failed to connect to FreeSWITCH ESL")
            else:
                logger.warning(f"No callLogId found in API response: {json_api_response}")

        else:
            logger.info(f"Skipping API call because neither caller nor callee is in 6–12 digit range: Caller={caller}, Callee={callee}")

    except Exception as e:
        logger.exception(f"Exception in process_channel_answer: {e}")
#@app.handle("CHANNEL_BRIDGE")
async def on_channel_bridge(event):
    try:
        caller = event.get("Caller-ANI") or event.get("Caller-Caller-ID-Number")
        callee_number = (
            event.get("Other-Leg-Callee-ID-Number")
            or event.get("Other-Leg-Destination-Number") or event.get("Caller-Destination-Number")
        )
        call_id = event.get("variable_sip_h_X-CallLogId")

        caller_joined_at = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
        caller_left_at = None  # Not known at bridge stage

        payload = {
            "call_id": call_id,
            "caller_joined_at": caller_joined_at,
            "caller_left_at": caller_left_at,
            "status": "Answered",
            "callee_number": callee_number
        }

        api_hangup_url = "https://wapis.discretal.com/calls/update-external-sip-call-details"
        logger.info(f"API Endpoint: {api_hangup_url}")
        logger.debug(f"Payload: {json.dumps(payload)}")

        response = requests.put(api_hangup_url, json=payload, timeout=10, verify=False)
        logger.info(f"API Response Code: {response.status_code}")
        logger.info(f"API Response Text: {response.text}")
        logger.info("========== CHANNEL_BRIDGE EVENT ==========")
        logger.info(f"Other-Leg-Callee-ID-Number: {event.get('Other-Leg-Callee-ID-Number')}")
        logger.info(f"Other-Leg-Destination-Number: {event.get('Other-Leg-Destination-Number')}")
        logger.info(f"Caller-Destination-Number: {event.get('Caller-Destination-Number')}")       
        response.raise_for_status()

        logger.debug("Bridge API called successfully!")

    except Exception as e:
        logger.exception(f"Error in CHANNEL_BRIDGE: {e}")


#@app.handle("CHANNEL_HANGUP_COMPLETE")
async def hangup_event_handler(event):
    try:
        logger.info("===== CHANNEL_HANGUP_COMPLETE EVENT TRIGGERED =====")
   
        # Log full event for debugging
       # try:     
        logger.debug(f"Full Event Data: {json.dumps(event, indent=2)}")
        logger.info(f"Other-Leg-Callee-ID-Number: {event.get('Other-Leg-Callee-ID-Number')}")
        logger.info(f"Other-Leg-Destination-Number: {event.get('Other-Leg-Destination-Number')}")
        logger.info(f"Caller-Destination-Number: {event.get('Caller-Destination-Number')}")
        #except Exception as dump_error:
        #    logger.warning(f"Could not dump full event data: {dump_error}")

        api_hangup_url = "https://wapis.discretal.com/calls/update-external-sip-call-details"
        logger.info(f"API Endpoint: {api_hangup_url}")

        call_id = event.get("variable_sip_h_X-CallLogId") or event.get("variable_Call_Log_Id")
        if not call_id:
            logger.warning("No call_id found for this hangup event. Skipping API call.")
            return

        hangup_cause = event.get("Hangup-Cause")

        # Ensure hangup_cause is a string
        if isinstance(hangup_cause, list):
            hangup_cause = hangup_cause[0] if hangup_cause else ""
        else:
            hangup_cause = str(hangup_cause or "").strip()

        billsec = int(event.get("variable_billsec") or 0)
        caller_joined_at = event.get("variable_answer_stamp") or event.get("variable_start_stamp")
        caller_left_at = event.get("variable_end_stamp")
        logger.info(f"billsec    : {billsec}")
        logger.info(f"Hangup Cause    : {hangup_cause}")
        callee_number = (
            event.get("Other-Leg-Callee-ID-Number")
            or event.get("Other-Leg-Destination-Number")
        )

        payload = None  # initialize to avoid UnboundLocalError

        # Determine status and payload structure
        if hangup_cause in ("NO_ANSWER", "ORIGINATOR_CANCEL", "USER_BUSY", "CALL_REJECTED", "CONGESTION", "BUSY","INVALID_NUMBER_FORMAT"):
            status = "MISSED"
            duration = 0
            logger.info(f"billsec    : {billsec}")
            payload = {
                "call_id": call_id,
                "callee_number": callee_number,
                "caller_joined_at": caller_joined_at,
                "caller_left_at": caller_left_at,
                "status": status,
                "duration": duration,
            }

        elif hangup_cause == "NORMAL_CLEARING":
            status = "ENDED"
            duration = billsec
            logger.info(f"billsec    : {billsec}")
            call_answered_time_raw = event.get("Caller-Channel-Answered-Time")
            callee_joined_at = None

            if call_answered_time_raw:
                try:
                    call_answered_time = datetime.strptime(call_answered_time_raw[:14], "%Y%m%d%H%M%S")
                    callee_joined_at = call_answered_time.strftime("%Y-%m-%d %H:%M:%S")
                except Exception as e:
                    logger.error(f"Failed to parse call_answered_time_raw={call_answered_time_raw}: {e}")

            callee_left_at = caller_left_at

            payload = {
                "call_id": call_id,
                "callee_number": callee_number,
                "caller_joined_at": caller_joined_at,
                "caller_left_at": caller_left_at,
                "callee_joined_at": callee_joined_at,
                "callee_left_at": callee_left_at,
                "status": status,
                "duration": duration,
            }

        # Safety: if payload is still None, skip API call
        if payload is None:
            logger.warning(f"No payload created for hangup cause: {hangup_cause}. Skipping API call.")
            return

        logger.info(f"Final Payload for API:\n{json.dumps(payload, indent=2)}")

        # Make API call
        try:
            response = requests.put(api_hangup_url, json=payload, timeout=10, verify=False)
            logger.info(f"API Response Code: {response.status_code}")
            logger.info(f"API Response Text: {response.text}")
            response.raise_for_status()
            logger.debug("Hangup API called successfully!")
        except requests.exceptions.RequestException as api_error:
            logger.error(f"Failed to call hangup API: {api_error}", exc_info=True)

    except Exception as e:
        logger.error(f"Exception in hangup_event_handler: {e}", exc_info=True)
async def event_loop():
    while True:
        try:
            logger.debug("Starting event listener server")

            # ✅ Open direct ESL connection and subscribe to all events
            conn = connect_to_fs()
            if conn.connected():
                logger.debug("✅ Connected to FreeSWITCH — subscribing to ALL events")
                conn.api("events plain ALL")
            else:
                logger.error("❌ Failed to connect to FreeSWITCH ESL")

            # ✅ Start async consumer (handles events)
            await app.start()

        except Exception as e:
            logger.debug(f"Got exception in the event_loop: {e}")
            await asyncio.sleep(5)
            logger.debug("Connection lost to FS server, retrying...")
            continue


asyncio.get_event_loop().run_until_complete(event_loop())
