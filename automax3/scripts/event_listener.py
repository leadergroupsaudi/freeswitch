#!/usr/bin/env python
import string
import sys
from freeswitchESL import ESL
import json
import gzip
import shutil
import requests
import logging
import asyncio
import time
import base64
import os
from genesis import Consumer
from datetime import datetime, timezone
from dateutil import parser

# Gets or creates a logger
logger = logging.getLogger(__name__)

# set log level
logger.setLevel(logging.DEBUG)

# define file handler and set formatter
file_handler = logging.FileHandler('/usr/local/freeswitch-automax-instance/var/log/freeswitch/events.log')
formatter    = logging.Formatter('%(asctime)s : %(levelname)s : %(name)s : %(message)s')
file_handler.setFormatter(formatter)
logger.propagate = False

# add file handler to logger
logger.addHandler(file_handler)
client_id = "441119749138415617"
client_secret = "lJTDutCqPycIEIULXgoIjavKsogWm4FCJcWxxb4LEmrqqkknSuyS9058PkSDJrZ7"
# login_credentials ={"userName":"HtUztAaXLEVTOINyW+I3Fw==","password":"0ddNDqI+Ogk7McKjnVObXmcWuaLyP7/kMFwWUo/3Cqo="} ---Automax2
login_credentials = {"userName": "441119749138415617","password": "lJTDutCqPycIEIULXgoIjavKsogWm4FCJcWxxb4LEmrqqkknSuyS9058PkSDJrZ7"}
# url = 'https://v2.automaxsw.com/stage/automax2/CCM/api/IVR/Authenticate'   --Automax2
url =  'https://automax.discretal.com/auth/oauth2/token'
# callLog_update_api = "https://v2.automaxsw.com/Stage/Axionic/CCM/API/CLK/CallLog"   
# get_callLog_api= "https://v2.automaxsw.com/Stage/Axionic/CCM/API/CLK/CallLog"
# callLog_addparticipant_api= "https://v2.automaxsw.com/Stage/Axionic/CCM/API/CLK/Call/Participant"  
# call_record_upload_api= "https://v2.automaxsw.com/Stage/Axionic/CCM/API/CLK/IVR/Callrecordings" --Automax2
call_record_upload_api = 'https://automax.discretal.com/api/compose/namespace/432712349708976129/module/432712349708910593/record/attachment'
token = None
# domain_name = "leaderfs.axionic.io" -----
domain_name ="pbxqa.axionic.io"
def get_token():
    logger.debug("Entering into get_token block")
    global token
    new_token = True

    if new_token:
        payload = {
            "grant_type": "client_credentials",
            "scope": "profile api"
        }

        # Construct Basic Auth header manually
        auth_string = f"{client_id}:{client_secret}"
        b64_auth = base64.b64encode(auth_string.encode()).decode()

        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "Authorization": f"Basic {b64_auth}"
        }

        try:
            response = requests.post(
                url,
                data=payload,
                headers=headers,
                timeout=10
            )
            logger.debug(f"HTTP response for auth token: {response.status_code} - {response.text}")

            token_response = response.json()
            fresh_token = token_response.get("access_token") or token_response.get("token")  # adapt key as needed

            if fresh_token:
                token = fresh_token
                logger.debug("Using new token")
                return {'Authorization': f'Bearer {fresh_token}'}
            else:
                logger.error("No access token found in the response.")
                return None

        except requests.exceptions.Timeout:
            logger.error("Request timed out.")
            return None
        except requests.exceptions.RequestException as e:
            logger.error(f"Request failed: {str(e)}")
            return None

    else:
        logger.debug("Using old token")
        return {'Authorization': f'Bearer {token}'}

app = Consumer("127.0.0.1", 8022, "ClueCon")

def connect_to_fs():
    conn = ESL.ESLconnection("127.0.0.1","8022","ClueCon")
    return conn

def send_audio_recording_to_axionic_server(event):
    #try:
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
            logger.debug("STEP 6: Using variable_record_start_time")
            record_time = datetime.strptime(event.get("variable_record_start_time"), "%Y-%m-%d %H:%M:%S")
            record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
        elif "variable_cc_queue_answered_epoch" in event:
            logger.debug("STEP 6: Using variable_cc_queue_answered_epoch")
            record_time = datetime.utcfromtimestamp(int(event.get("variable_cc_queue_answered_epoch")))
            record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
        else:
            logger.debug("STEP 6: Using Other-Leg-Channel-Answered-Time")
            logger.debug("STEP 6.1: Other-Leg-Channel-Answered-Time raw value: {}".format(event.get("Other-Leg-Channel-Answered-Time")))
            record_time = datetime.utcfromtimestamp(int(event.get("answered_time") or time.time() * 1_000_000) / 1_000_000)
            #record_time = datetime.utcfromtimestamp(event.get("Other-Leg-Channel-Answered-Time"))
            record_start_time = record_time.strftime("%Y-%m-%dT%H:%M:%S") + "Z"

        #callLogID = event.get("variable_sip_h_X-CallLogId")
        record_count = event.get("variable_record_count")
        recordtype = event.get("variable_isvideocall")
        logger.debug("STEP 8: Record count: {}, Record type: {}".format(record_count, recordtype))
        data ={"fieldName": "Attachments"}
        logger.debug("STEP 9: Preparing file upload object")
        files = {"upload": (file_name, open(trimmed_file_path, 'rb'), 'audio/wav')}
        # Prepare the compressed file for upload
        #files =[('File',(file_name,open(trimmed_file_path,'rb'),'audio/wav'))]
        #files = [('File', (os.path.basename(compressed_file_path), open(compressed_file_path, 'rb'), 'audio/wav'))]
        #logger.debug("Call record payload data: {}".format(payload))
        logger.debug("About to call get_token()...")
        # Fetch token header  
        token_header = get_token()
        
        # Upload the compressed file
        if token_header:
            response = requests.post(call_record_upload_api, headers=token_header, data=data, files=files)
            resp = response.json()
            logger.debug("Call record API response: {}".format(response))
            logger.debug("Call record API JSON response data: {}".format(resp))
            
            #if 'httpStatusCode' in resp.keys() and resp['httpStatusCode'] == 'OK':
            if 'response' in resp:
                attachment_id = resp['response']['attachmentID']
                logger.debug("Successfully uploaded compressed recording file: {}".format(attachment_id))
                logger.debug(f"Full event data: {event}")
                #uuid = event.get("variable_originating_leg_uuid")
                uuid =event.get("variable_uuid")
                #logger.debug(f"Full event data: {event}")
                logger.debug(f"UUID retrieved from event: {uuid}")
                if uuid:
                    fs_conn = connect_to_fs()
                    cmd = f"uuid_setvar {uuid} attachment_id {attachment_id}"
                    logger.debug(f"Setting session variable with cmd: {cmd}")
                    fs_conn.api(cmd)
                    fs_conn.disconnect()
               # os.remove(compressed_file_path)  # Delete the compressed file after successful upload
            else:
                logger.debug("Failed to upload audio recording file: {}".format(trimmed_file_path))
                
#except Exception as e:
 #       logger.debug("Exception in send_audio_recording_to_axionic_server: unable to upload audio recording file to server. Error: {}".format(e))


def get_callLog_details(callLogID, new_token):
    logger.debug("Entered get_CallLOG block")
    token_header = get_token(new_token)
    if token_header:
        response = requests.get(get_callLog_api+"/"+callLogID, headers=token_header)
        full_url = f"{get_callLog_api}/{callLogID}"
        logger.debug(f"Constructed URL: {full_url}")
        logger.debug(f"Token Header: {token_header}") 
        if response.status_code == 200:
            data = response.json()
            logger.debug(f"Response Data: {data}")
            return data
        else:
            logger.debug("get_callLog_details Request failed with status code format {}".format(response.status_code))
    else:
        logger.debug("Unable to get token from API server so Get CDR list data not retrieved")

def updateCallLog_payload(payload, duration, end_time, event):
    logger.debug("Entered into updateCallLog_payload block")
    result = payload["result"]
    participants = result["participants"]
    logger.debug("Collected callLog_info")

    call_answered_time_raw = event.get("Caller-Channel-Answered-Time")
    if call_answered_time_raw:
        logger.debug("Call was answered, processing 'Other-Leg-Channel-Answered-Time'")
        try:
            call_answered_time = int(call_answered_time_raw) / 1e6
            logger.debug("After Answered time")
            call_answered_time = datetime.utcfromtimestamp(call_answered_time).replace(tzinfo=timezone.utc)
            call_answered_time = call_answered_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        except (TypeError, ValueError) as e:
            logger.error(f"Error converting 'Other-Leg-Channel-Answered-Time': {e}", exc_info=True)
            call_answered_time = datetime.utcnow().replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    else:
        logger.debug("'Other-Leg-Channel-Answered-Time' not found; using call start time as fallback.")
        call_answered_time = datetime.utcnow().replace(tzinfo=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    transformed_data = {
        "callLogId": int(result["callLogId"]),
        "callDuration": duration,
        "startTime": result["startTime"],
        "endTime": end_time,
        "participants": [
            {
                "CallerId": participant["callerId"],
                "isCaller": participant["isCaller"],
                "answerStatus": participant["answerStatus"],
                "joinTime": participant["joinTime"],
                "callReachTime": call_answered_time
            }
            for participant in participants
        ]
    }

    logger.debug(f"Transformed Data: {transformed_data}")
    return transformed_data

def update_callLog_data(payload, new_token):
    logger.debug("Entered into Update recent call logs block")
    logger.debug("CallLog payload Data is {}".format(payload))
    token_header = get_token(new_token)
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

def add_callLog_participant(callLogId, payload, new_token):
    logger.debug("Entered into add_callLog_participant block")
    logger.debug("CallLog payload Data is {}".format(payload))
    token_header = get_token(new_token)
    if token_header:
        token_header['Content-Type'] = 'application/json'
        token_header['callLogId'] = str(callLogId)
        response = requests.put(callLog_addparticipant_api,data=payload,headers=token_header)
        if response.status_code == 200:
            data = response.json()
            logger.debug("Posted add_participant data successfully:: {}".format(data))
        else:
            logger.debug("add_callLog_participant Request failed with status code format {}".format(response.status_code))
    else:
        logger.debug("Unable to get token from API server so add_participant cdr record can not be posted")

def update_participant_inCallStatus(json_string, new_token):
    logger.debug("Entered into Participant incallStatus update block")
    logger.debug("Participant payload data is {}".format(json_string))
    token_header = get_token(new_token)
    if token_header:
        token_header['Content-Type'] = 'application/json'
        response = requests.put(updateParticipant_api,data=json_string,headers=token_header)
        if response.status_code == 200:
            data = response.json()
            logger.debug("Posted removeparticipant InCallStatus data successfully:: {}".format(data))
        else:
            logger.debug("Remove participant InCallStatus Request failed with status code format {}".format(response.status_code))
    else:
        logger.debug("Unable to get token from API server so remove_participant InCallStatus can not be posted")

@app.handle("RECORD_STOP")
async def hold_event_handler(event):
    global token
    logger.debug("Received RECORD_STOP event {}".format(event))
    #xcallLogID = event.get("variable_sip_h_X-CallLogId")
    current_app = event.get("variable_current_application")
    call_direction = event.get("Call-Direction")
    incident_id = event.get("variable_incident_no_reponse")
    logger.debug("Incident ID (record_id) from session: {}".format(incident_id))
    logger.debug("All keys: {}".format(list(event.keys())))
    #logger.debug("X-CallLogId of call Record {}".format(xcallLogID))
    """try:     
        if token is None:
            new_token=True
        else:
            new_token = False
        #if "variable_sip_h_X-CallLogId" in event and "variable_cc_agent_bridged" in event and current_app != "voicemail":
        if event.get("variable_cc_agent_bridged") and current_app != "voicemail":
            logger.debug("*********Calling Function Recording file upload *************")
            send_audio_recording_to_axionic_server(event,new_token)
    except Exception as e:
        logger.debug("Got exception in RECORD_STOP handler {}".format(e))"""
    #try:
        # Only call the function if agent bridged and not voicemail
    #   if event.get("variable_cc_agent_bridged") and current_app != "voicemail": ---- condition needed --TO--DO
    logger.debug("*********Calling Function Recording file upload *************")
    send_audio_recording_to_axionic_server(event)
    logger.debug("Finished calling send_audio_recording_to_axionic_server")
    #except Exception as e:
    #logger.debug("Got exception in RECORD_STOP handler {}".format(e))

@app.handle("CHANNEL_BRIDGE")
async def channel_answer_event_handler(event):
    logger.debug("Received CHANNEL_BRIDGE event")
    try:
        global token
        callLogID = (int(float(event.get("variable_sip_h_X-CallLogId"))))
        agent_extension = event.get("Caller-Callee-ID-Number")
        call_created_time = int(event.get("Other-Leg-Channel-Created-Time")) / 1e6
        call_created_time = datetime.utcfromtimestamp(call_created_time).replace(tzinfo=timezone.utc)
        call_created_time = call_created_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        call_answered_time = int(event.get("Other-Leg-Channel-Answered-Time")) / 1e6
        call_answered_time = datetime.utcfromtimestamp(call_answered_time).replace(tzinfo=timezone.utc)
        call_answered_time = call_answered_time.strftime("%Y-%m-%dT%H:%M:%SZ")
        add_payload = json.dumps([{ "CallerId": agent_extension, "JoinTime": call_created_time, "IsCaller": False, "answerStatus": "A", "CallReachTime": call_answered_time}])
        if token is None:
            new_token=True
        else:
            new_token = False
        add_callLog_participant(int(callLogID),add_payload,new_token)
    except Exception as e:
        logger.debug ("Got exception in setting Incall status {}".format(e))
        pass
    
@app.handle("CHANNEL_HANGUP_COMPLETE")
async def hangup_event_handler(event):
    global token
    logger.debug("Received CHANNEL_HANGUP_COMPLETE event {}".format(event))
    callLogID = event.get("variable_sip_h_X-CallLogId")
    logger.debug(f"Call Log ID : {callLogID}")
    val = event.get("Hangup-Cause")[0]
    term_flag = False
    term_code = event.get("variable_sip_term_status")
    if token is None:
        new_token=True
    else:
        new_token = False       
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
            send_voicemail_to_axionic_server(event,new_token)
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
            send_voicemail_to_axionic_server(event,new_token)
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
            send_voicemail_to_axionic_server(event,new_token)
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
    if term_flag or term_code in ['486','603','480'] or val == "NO_ANSWER":
        logger.debug("##########")      
        logger.debug("handled call disposition {} setting channel var".format(val))
        logger.debug(f"Handled call disposition: {val}")
        agent_extension = event.get("variable_sip_to_user") or event.get("Caller-Destination-Number")
        logger.debug(f"Agent extension: {agent_extension}")
        call_created_time = event.get("variable_start_stamp")
        logger.debug(f"Call created time (before formatting): {event.get('variable_start_stamp')}")
        call_created_time = datetime.strptime(call_created_time, "%Y-%m-%d %H:%M:%S").strftime("%Y-%m-%dT%H:%M:%SZ")
        logger.debug(f"Call created time (after formatting): {call_created_time}")
        logger.debug(f"Call start time: {call_start_time}")
        add_payload = json.dumps([{ "CallerId": agent_extension, "JoinTime": call_created_time, "IsCaller": False, "answerStatus": "M", "CallReachTime": call_start_time}])
        callLogID = event.get("variable_sip_h_X-CallLogId")
        logger.debug(f"Call Log ID: {callLogID}")
        logger.debug(f"Payload being sent: {add_payload}")
        add_callLog_participant(int(callLogID),add_payload, new_token)
        #set_channel_var(event)


    try:
        if ("variable_sip_h_X-CallLogId" in event and event.get("Call-Direction") == "inbound"):
            duration    = event.get("variable_billsec")
            call_to      = event.get("variable_sip_to_user")
            call_from        = event.get("variable_sip_from_user") 
            call_end_time   = event.get("variable_end_stamp")
            logger.debug(f"call_end_time: {call_end_time}")
            started     = datetime.strptime(event.get("variable_start_stamp"), "%Y-%m-%d %H:%M:%S")
            ended       = datetime.strptime(call_end_time, "%Y-%m-%d %H:%M:%S")         
            logger.debug(f"ended: {ended}")
            start_time  = started.strftime("%Y-%m-%dT%H:%M:%S")
            logger.debug(f"start_time: {start_time}")
            start_time  = start_time+"Z"
            logger.debug(f"start_time: {start_time}")
            end_time    = ended.strftime("%Y-%m-%dT%H:%M:%S")
            logger.debug(f"end_time: {end_time}")
            end_time    = end_time+"Z"
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
            response_callLogs = get_callLog_details(callLogID, new_token)
            logger.debug(f"Response from get_callLog_details: {response_callLogs}")
            #response_callLogs = json.dumps(response_callLogs)
            #update_callLogs_payload = {"callLogId": int(callLogID),  "callDuration": str(duration)",  "endTime": end_time, "participants": [ { "CallLogId": int(callLogID), "CallerId": call_from } ]}
            update_callLogs_payload = updateCallLog_payload(response_callLogs,duration,end_time,event)
            payload = json.dumps(update_callLogs_payload)
            logger.debug("Updated call json payload in freeswitch: {}".format(payload))
            update_callLog_data(payload,new_token)
        else:
            logger.debug("CDR data can't post to inbound call")
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

