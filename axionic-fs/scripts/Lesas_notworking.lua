-- IVR Lua Script for Lesaas Callcenter

-- Load FreeSWITCH API
local api = freeswitch.API()
local json = require "lunajson"

-- Fire notification module
local module_folder = freeswitch.getGlobalVariable("script_dir") .."/"
package.path = module_folder .. "?.lua;" .. package.path

-- Answer the call
session:answer()

-- Play IVR prompt
session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/Lesaas_IVR1.wav")


session:execute("callcenter", "lesaas-ivr@default")

session:hangup()

