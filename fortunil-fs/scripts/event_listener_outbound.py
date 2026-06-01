#!/usr/bin/env python
import string
import sys
from freeswitchESL import ESL
import json
import requests
import logging
import asyncio
import time
import base64
import os
import re
import shutil
from genesis import Consumer
from datetime import datetime,timezone,timedelta

# Gets or creates a logger
logger = logging.getLogger(__name__)

# set log level
logger.setLevel(logging.DEBUG)

# define file handler and set formatter
file_handler = logging.FileHandler('/usr/local/freeswitch-fortunil-instance/var/log/freeswitch/events.log')
formatter        = logging.Formatter('%(asctime)s : %(levelname)s : %(name)s : %(message)s')
file_handler.setFormatter(formatter)
logger.propagate = False

# add file handler to logger
logger.addHandler(file_handler)
global_storage = {}

#call_record_upload_api = "https://erpdev.leadergroup.com/api/method/foxerp.api.voip.saveCallRecordingFile"
call_record_upload_api = "https://fortunil.leadergroup.com/api/method/axionic_integration.axionic_integration.api.voip.UpdateRecordingChildTable"
callLog_addparticipant_api ="https://fortunil.leadergroup.com/api/method/axionic_integration.axionic_integration.api.voip.CreateOrUpdateCallLog"
callLog_update_api ="https://fortunil.leadergroup.com/api/method/axionic_integration.axionic_integration.api.voip.CreateOrUpdateCallLog"
domain_name = "leaderfs.axionic.io"


app = Consumer("127.0.0.1", 8024, "ClueCon")

def connect_to_fs():
        conn = ESL.ESLconnection("127.0.0.1","8024","ClueCon")
        return conn

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


def send_audio_recording_to_axionic_server(event):
    try:
        logger.debug("Audio file recording file upload section")
        file_path = event.get("Record-File-Path")
        index = file_path.find('/')
        trimmed_file_path = file_path[index:]
        
        logger.debug("Recording file path: {}".format(trimmed_file_path))
        file_location, file_name = os.path.split(file_path)
        record_duration = event.get("variable_record_seconds")
        logger.debug("Recording file name: {}".format(file_name))

        # Determine the recording start time
        if "variable_record_start_time" in event:
            record_time = datetime.strptime(event.get("variable_record_start_time"), "%Y-%m-%d %H:%M:%S")
            record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
            logger.debug("in if condition")
        elif "variable_cc_queue_answered_epoch" in event:
            record_time = datetime.utcfromtimestamp(int(event.get("variable_cc_queue_answered_epoch")))
            record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
            logger.debug("in Elseif Condition")
        else:
           # record_time = datetime.utcfromtimestamp(event.get("Other-Leg-Channel-Answered-Time"))
            record_start_time = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            #record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
            logger.debug("in Else Condition")
        callLogID = event.get("variable_sip_h_X-CallLogId")
        logger.debug("X-CallLogId of call Record {}".format(callLogID))
        #record_count = event.get("variable_record_count")
        #recordtype = event.get("variable_isvideocall")
        
        payload = {
            'CallLogId': callLogID,
            'RecordingType': "A",
            'StartedDate': record_start_time,
            'Duration': record_duration
        }

        files =[('File',(file_name,open(trimmed_file_path,'rb'),'audio/wav'))]
        logger.debug(f"Original file path: {file_path}")
        logger.debug(f"Trimmed file path: {trimmed_file_path}")
        response = requests.post(call_record_upload_api,data=payload, files=files)
        resp = response.json()
        logger.debug("Call record API response: {}".format(response))
        logger.debug("Call record API JSON response data: {}".format(resp))
        if response.status_code == 200:
                logger.debug("Successfully uploaded  recording file: {}".format(trimmed_file_path))
               # os.remove(compressed_file_path)  # Delete the compressed file after successful upload
        else:
                logger.debug("Failed to upload audio recording file: {}".format(trimmed_file_path))
                
    except Exception as e:
        logger.debug("Exception in send_audio_recording_to_axionic_server: unable to upload audio recording file to server. Error: {}".format(e))

def add_callLog_participant(callLogID,payload):
        logger.debug("Entered into add_callLog_participant block")
        logger.debug("CallLog payload Data is {}".format(payload))
        headers = {
            "CallLogId": callLogID,
            "Content-Type": "application/json"  
        }
        response = requests.put(callLog_addparticipant_api,json=payload,headers=headers)
        if response.status_code == 200:
                        data = response.json()
                        logger.debug("Posted add_participant data successfully:: {}".format(data))
        else:
                        logger.debug("add_callLog_participant Request failed with status code format {}".format(response.status_code))
                        logger.debug("Response text: {}".format(response.text))

def update_callLog_data(payload,callLogID,duration,end_time,event):
	logger.debug("Entered into Update recent call logs block")
	logger.debug("CallLog payload Data is {}".format(payload))
	headers = {
            "CallLogId": callLogID,
            "Content-Type": "application/json"
        }
	#response = requests.put(callLog_update_api,data=payload,headers={"CallLogId": callLogID})
	response = requests.put(callLog_update_api,json=payload,headers=headers)
	if response.status_code == 200:
			data = response.json()
			logger.debug("Posted update_callLogData CDR Recent list successfully:: {}".format(data))
	else:
			logger.debug("update_callLog_data Request failed with status code format {}".format(response.status_code))

#def updateCallLog_payload(payload,duration,end_time):
#	logger.debug("Entered into updateCallLog_payload block")
#	result = payload["result"]["callLog"]
#	participants = payload["result"]["callParticipants"]

#	transformed_data = {
#		"callLogId": int(result["callLogId"]),
#		"callDuration": duration,
#		"startTime": result["startTime"],
#		"endTime": end_time,
#		"participants": [
 #           {"CallerId": participant["callerId"], "isCaller": participant["isCaller"], "answerStatus": participant["answerStatus"], "joinTime": participant["joinTime"] ,"callReachTime": participant["callReachTime"] }
#			for participant in participants
#		]
#	}
#	return transformed_data

def move_failed_file(file_path, file_location):
        failed_folder = os.path.join(file_location, "failed")
        os.makedirs(failed_folder, exist_ok=True)
        file_name = os.path.basename(file_path)
        shutil.move(file_path, os.path.join(failed_folder, file_name))
        logger.debug("Moved file to 'failed' folder: {}".format(os.path.join(failed_folder, file_name)))


@app.handle("CHANNEL_BRIDGE")
async def channel_answer_event_handler(event):
        logger.debug("Received CHANNEL_BRIDGE event")
        try:
                callLogID = event.get("variable_sip_h_X-CallLogId")
                agent_extension = event.get("Caller-Callee-ID-Number")
                variable_start_stamp = event.get("Caller-Channel-Created-Time")
                logger.debug(f"variable_start_stamp: {variable_start_stamp}")
                raw_time = event.get("Caller-Channel-Created-Time")
                raw_duration = event.get("variable_billsec", "0")
                duration = int(raw_duration)
                time_stamp= int(raw_time) / 1e6	
                started = datetime.utcfromtimestamp(time_stamp)	
                start_time= started.strftime("%Y-%m-%dT%H:%M:%S")
                start_time	= start_time+"Z"
                start_time_dt = datetime.strptime(start_time, "%Y-%m-%dT%H:%M:%SZ")
                end_time_dt = start_time_dt + timedelta(seconds=duration)
                end_time_str = end_time_dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{end_time_dt.microsecond:06d}Z"
                call_created_time = int(event.get("Other-Leg-Channel-Created-Time")) / 1e6
                call_created_time = datetime.utcfromtimestamp(call_created_time).replace(tzinfo=timezone.utc)
                call_created_time = call_created_time.strftime("%Y-%m-%dT%H:%M:%S.")   + f"{call_created_time.microsecond:06d}Z"
                call_answered_time = int(event.get("Other-Leg-Channel-Answered-Time")) / 1e6
                call_answered_time = datetime.utcfromtimestamp(call_answered_time).replace(tzinfo=timezone.utc)
                call_answered_time = call_answered_time.strftime("%Y-%m-%dT%H:%M:%SZ")
                logger.debug(f"Start Time: {start_time}, Call Created Time: {call_created_time}, Answered Time: {call_answered_time},Agent_extension: {agent_extension}")
                global_storage[callLogID] = {
            "join_time": call_answered_time,
            "call_answered_time": call_created_time,
            "agent_extension": agent_extension,
        }
                payload = {
    "participants": [
        {
            "CallerId": agent_extension,
            "JoinTime": call_answered_time,
            "HangupTime":end_time_str ,  # Assuming HangupTime is the same as JoinTime for now
            "AnswerStatus": "A",  # Replace with a dynamic status if available
            "IsCaller": "0",  # Indicates the participant is not the caller
            "CallReachTime": call_created_time
        }
    ]
}
               # payload = json.dumps(new_payload)
                #add_participant(add_payload,callLogID)
                add_callLog_participant(callLogID,payload)
			 
        except Exception as e:
                logger.debug ("Got exception in setting Incall status {}".format(e))
                pass


@app.handle("RECORD_STOP")
async def hold_event_handler(event):
        #global token
        logger.debug("Received RECORD_STOP event {}".format(event))
        #xcallLogID = event.get("variable_sip_h_X-CallLogId")
        current_app = event.get("variable_current_application")
        call_direction = event.get("Call-Direction")
        #logger.debug("X-CallLogId of call Record {}".format(xcallLogID))
        try:
                #if "variable_sip_h_X-CallLogId" in event and current_app != "voicemail":
                if current_app != "voicemail":
                        logger.debug("*********Calling Function Recording file upload *************")
                        send_audio_recording_to_axionic_server(event)

        except Exception as e:
          logger.debug("Got exception in RECORD_STOP handler {}".format(e))

@app.handle("CHANNEL_HANGUP_COMPLETE")
async def hangup_event_handler(event):
	#global token
	logger.debug("Received CHANNEL_HANGUP_COMPLETE event {}".format(event))	
	val = event.get("Hangup-Cause")[0]
	term_flag = False
	term_code = event.get("variable_sip_term_status")
	if (val == "CALL_REJECTED" and event.get("Call-Direction") == "outbound") or\
	   (val == "USER_BUSY" and event.get("Call-Direction") == "outbound"): 
		call_type = "UserBusy"
		call_start_time = event.get("variable_start_stamp")
	elif (val == "ORIGINATOR_CANCEL" and event.get("variable_DIALSTATUS") =="CANCEL") or\
		(val == "NORMAL_CLEARING" and event.get("variable_DIALSTATUS") == "NOANSWER")\
		and event.get("variable_last_app") == "voicemail":
		call_type = "Missed"
		term_flag = True 
		call_start_time = event.get("variable_start_stamp")
	elif val == "NORMAL_CLEARING" and event.get("variable_DIALSTATUS") =="SUCCESS"\
		and event.get("variable_endpoint_disposition") == "ANSWER":
		call_type = "Answered"
		call_start_time = event.get("variable_answer_stamp")
		if(event.get("Call-Direction") == "inbound"):
			extension = event.get("variable_sip_from_user")
		false = False
	elif val == "NORMAL_CLEARING"\
		and event.get("variable_endpoint_disposition") == "ANSWER" and event.get("variable_last_app") == "voicemail":
		logger.debug("Entered in Answered,VoiceMail,Normal clearing")
		if "variable_sip_gateway_name" in event:
			extension = event.get("Caller-Username")
		else:				
			extension = event.get("variable_sip_from_user")
		call_type = "Answered"
		false = False
		call_start_time = event.get("variable_answer_stamp")
		if "variable_voicemail_file_path" in event:
			send_voicemail_to_axionic_server(event)
		else:
			logger.debug("Voicemail not created")
	elif val == "NORMAL_CLEARING"\
		and event.get("variable_endpoint_disposition") == "ANSWER" and event.get("variable_last_app") != "playback":
		logger.debug("Entered in Answered,Normal clearing")
		if "variable_sip_gateway_name" in event:
			extension = event.get("Caller-Username")
		else:		
			if(event.get("Call-Direction") == "outbound"):
				extension = event.get("variable_sip_to_user")
			else:
				extension = event.get("variable_sip_from_user")				
		call_type = "Answered"
		false = False
		call_start_time = event.get("variable_answer_stamp")
		if "variable_voicemail_file_path" in event:
			send_voicemail_to_axionic_server(event)
		else:
			logger.debug("Voicemail not created")
	elif val == "NORMAL_CLEARING" and event.get("variable_DIALSTATUS") in ["NOANSWER","NORMAL_TEMPORARY_FAILURE","INVALIDARGS"]\
		and event.get("variable_last_app") == "voicemail" and event.get("variable_endpoint_disposition") =='ANSWER':
		logger.debug("Entered in Answered,VoiceMail,NOANSWER")		
		if "variable_sip_gateway_name" in event:
			extension = event.get("Caller-Username")
		else:
			extension = event.get("variable_sip_to_user")
		false = False
		call_type = "Answered"
		call_start_time = event.get("variable_answer_stamp")
		if "variable_voicemail_file_path" in event:
			send_voicemail_to_axionic_server(event)
		else:
			logger.debug("Voicemail not created")
	elif val == "NORMAL_CLEARING" and event.get("Call-Direction") == "inbound":
		call_type = "Answered"
	elif term_code in ['486','603','480'] or val == "NO_ANSWER":
		call_type = "Missed"
		term_flag = True
		call_start_time = event.get("variable_start_stamp")
	elif val == "NORMAL_CLEARING" and event.get("Call-Direction") == "outbound":
		call_type = "Answered"
	else:
		logger.debug("##########")
		logger.debug("Unhandled Event info {}".format(event))
		logger.debug("Unhandled call disposition {}".format(val))
		logger.debug("##########")
		return
	
	logger.debug("data {} {}".format(term_flag,term_code))
	if term_flag or term_code in ['486','603','480']  or val == "NO_ANSWER":
		logger.debug("##########")		
		logger.debug("handled call disposition {} setting channel var".format(val))
		agent_extension = event.get("Caller-Username") or event.get("variable_sip_to_user")
		started =datetime.strptime(event.get("variable_start_stamp"), "%Y-%m-%d %H:%M:%S")
		call_created_time = started.strftime("%Y-%m-%dT%H:%M:%S.") + f"{started.microsecond:06d}Z"
		logger.debug(f"start_time: {call_created_time}")
		#add_payload = json.dumps([{ "CallerId": agent_extension, "JoinTime": call_created_time, "IsCaller": "0", "AnswerStatus": "M", "CallReachTime": call_start_time, "HangupTime": call_created_time}])
                #payload = [{ "CallerId": agent_extension, "JoinTime": call_created_time, "HangupTime": call_created_time,"AnswerStatus": "M","IsCaller": "0", "CallReachTime": call_start_time}]
		payload = {
    "participants": [
        {
            "CallerId": agent_extension,
            "JoinTime": call_created_time,
            "HangupTime": call_created_time,  # Assuming HangupTime is the same as JoinTime for now
            "AnswerStatus": "M",  # Replace with a dynamic status if available
            "IsCaller": "0",  # Indicates the participant is not the caller
            "CallReachTime": call_created_time
        }
    ]
}
		callLogID = event.get("variable_sip_h_X-CallLogId")
		logger.debug("X-Call Log ID is {}".format(callLogID))
		add_callLog_participant(callLogID,payload)
		#set_channel_var(event)


	try:
		if ("variable_sip_h_X-CallLogId" in event and event.get("Call-Direction") == "inbound"):
			duration	= event.get("variable_billsec")
			call_to		 = event.get("variable_sip_to_user")
			call_from		 = event.get("variable_sip_from_user") 
			call_end_time	= event.get("variable_end_stamp")
			logger.debug(f"call_end_time: {call_end_time}")
			started		= datetime.strptime(event.get("variable_start_stamp"), "%Y-%m-%d %H:%M:%S")
			start_time = started.strftime("%Y-%m-%dT%H:%M:%S.") + f"{started.microsecond:06d}Z"
			ended		= datetime.strptime(call_end_time, "%Y-%m-%d %H:%M:%S")			
			logger.debug(f"ended: {ended}")
			logger.debug(f"start_time: {start_time}")
			end_time        = ended.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ended.microsecond:06d}Z"
			logger.debug(f"end_time: {end_time}")
			callLogID = event.get("variable_sip_h_X-CallLogId")
			logger.debug("X-Call Log ID is {}".format(callLogID))
			if call_type == "Answered":
				callType = "A"
			elif call_type == "Missed":
				callType = "M"
			elif call_type == "UserBusy":
				callType = "R"
			else:
				callType == "A"
				#response_callLogs = get_callLog_details(callLogID)
			#response_callLogs = json.dumps(response_callLogs)
			#update_callLogs_payload = {"callLogId": int(callLogID),  "callDuration": str(duration)",  "endTime": end_time, "participants": [ { "CallLogId": int(callLogID), "CallerId": call_from } ]}
			#update_callLogs_payload = updateCallLog_payload(response_callLogs,duration,end_time)
			stored_data = global_storage.get(callLogID, {})
			join_time = stored_data.get("join_time")
			agent_extensions = stored_data.get("agent_extension")
			payload = {
    "CallDuration": duration,
    "StartTime": start_time,
    "EndTime": end_time,
    "participants": [
        {
            "CallerId": call_from,
            "IsCaller": "1",  # Assuming the caller is initiating the call
            "JoinTime": start_time,
            "HangupTime": end_time,
            "AnswerStatus": callType,
            "CallReachTime": start_time  
        },
         {
            "CallerId": agent_extensions,  # Receiver details
            "IsCaller": "0",  # Indicates the participant is the receiver
            "JoinTime": join_time,
            "HangupTime": end_time,
            "AnswerStatus": callType,
            "CallReachTime": start_time
        }
    ],
    "CallStatus": "E" 
}
			#payload = json.dumps(update_callLogs_payload)
			logger.debug("Updated call json payload in freeswitch: {}".format(payload))
			update_callLog_data(payload,callLogID,duration,end_time,event)
		else:
			logger.debug("Processing outbound call...")
			duration = event.get("variable_billsec")
			call_to = event.get("Caller-Destination-Number")
			call_from = event.get("Caller-Caller-ID-Number")
			call_end_time = event.get("variable_end_stamp")
			logger.debug(f"call_end_time: {call_end_time}")
			started = datetime.strptime(event.get("variable_start_stamp"), "%Y-%m-%d %H:%M:%S")
			start_time = started.strftime("%Y-%m-%dT%H:%M:%S.") + f"{started.microsecond:06d}Z"
			ended = datetime.strptime(call_end_time, "%Y-%m-%d %H:%M:%S")
			logger.debug(f"ended: {ended}")
			logger.debug(f"start_time: {start_time}")
			end_time = ended.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ended.microsecond:06d}Z"
			logger.debug(f"end_time: {end_time}")
			payload = {
            "CallDuration": duration,
            "StartTime": start_time,
            "EndTime": end_time,
            "participants": [
                {
                    "CallerId": call_from,
                    "IsCaller": "1",
                    "JoinTime": start_time,
                    "HangupTime": end_time,
                    "AnswerStatus": "A",  # Assuming outbound calls are answered
                    "CallReachTime": start_time  
                },
                {
                    "CallerId": call_to,
                    "IsCaller": "0",
                    "JoinTime": start_time,
                    "HangupTime": end_time,
                    "AnswerStatus": "A",
                    "CallReachTime": start_time
                }
            ],
            "CallStatus": "E"
        }
			logger.debug("Updated call json payload for outbound call: {}".format(payload))
			update_callLog_data(payload, None, duration, end_time, event)
			
	except Exception as e:
		logger.debug ("Got exception in hangup_event_handler {}".format(e))

async def event_loop():
        reconnect = False
        while True:
                try:
                        logger.debug("Starting event listener server")
                        await app.start()
                except Exception as e:
                        logger.debug("Got exception in the event_loop {}".format(e))
                        await asyncio.sleep(5)
                        logger.debug("Connection lost to FS server")
                        continue

asyncio.get_event_loop().run_until_complete(event_loop())


