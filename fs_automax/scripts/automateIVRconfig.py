import requests;
import json;
import redis;
import logging;
redis_client = redis.StrictRedis(host='localhost', port=6379, db=0)
baseURL = "https://v2.automaxsw.com/Stage/"
athenticateAPI = baseURL+"Automax2/BFF/Login/Authenticate"
ivrConfigurationAPI = baseURL+"Axionic/CCM/API/CLK/IVR/Configuration?IVRCode=IVR02"
getWebConfigurationAPI = baseURL+"Automax2/BFF/WebApiConfig/Type/1"
getExtensionListAPI = baseURL+"Axionic/CCM/API/CLK/Extension/List"


logger = logging.getLogger(__name__)

# set log level
logger.setLevel(logging.DEBUG)

# define file handler and set formatter
file_handler = logging.FileHandler('/var/log/ivr-data.log')
formatter    = logging.Formatter('%(asctime)s : %(levelname)s : %(name)s : %(message)s')
file_handler.setFormatter(formatter)
logger.propagate = False

# add file handler to logger
logger.addHandler(file_handler)


def get_token():
    auth_payload = "{userName: \"HtUztAaXLEVTOINyW+I3Fw==\", passWord: \"HtUztAaXLEVTOINyW+I3Fw==\"}"
    auth_headers = {'Content-Type': 'application/json'}
    auth_response = requests.request("POST", athenticateAPI, headers=auth_headers, data=auth_payload)
    if auth_response.status_code == 200:
        auth_data = auth_response.json()
        token = auth_data["tokenViewModel"]["token"]
        return token
    else:
        print("get_token API returned Error "+auth_response.status_code)

def get_ivrconfig(token):
    if token:
        payload = {}
        headers = {'Authorization': 'Bearer '+token }
        api_response = requests.request("GET", ivrConfigurationAPI, headers=headers, data=payload)
        if api_response.status_code == 200:
            ivr_config = api_response.json()
            ivr_data = json.dumps(ivr_config)
            #ivr_config = ivr_data["result"]
            redis_client.execute_command('JSON.SET', 'api_ivrconfig', '.', ivr_data)
            print(ivr_data)
        else:
            print("get_ivrconfig API returned Error ::")
            print(api_response.status_code)
    else:
         print("Token not found")


def get_webApiConfig(token):
    if token:
        payload = {}
        headers = {'Authorization': 'Bearer '+token }
        api_response = requests.request("GET", getWebConfigurationAPI, headers=headers, data=payload)
        if api_response.status_code == 200:
            webconfig_data = api_response.json()
            print(webconfig_data)
        else:
            print("get_webApiConfig API returned Error "+api_response.status_code)
    else:
         print("Token not found")


def get_extensionsList(token):
    if token:
        payload = {}
        headers = {'Authorization': 'Bearer '+token }
        api_response = requests.request("GET", getWebConfigurationAPI, headers=headers, data=payload)
        if api_response.status_code == 200:
            extensionsList = api_response.json()
            print(extensionsList)
        else:
            print("get_extensionsList API returned Error "+api_response.status_code)
    else:
         print("Token not found")


token = get_token()
print(token)
get_ivrconfig(token)
get_webApiConfig(token)
get_extensionsList(token)
