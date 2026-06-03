api = freeswitch.API();

local uuid = session:getVariable("UUID");

time=os.time()
session:setVariable("api_hangup_hook","lua hangup.lua "..tostring(uuid));

local calltype="external"
     session:setVariable("sip_h_X-calltype", calltype)
                    session:execute("export", "nolocal:sip_h_X-calltype=" .. calltype)
                    session:setVariable("calltype", calltype)
                   session:setVariable("export_vars", "calltype,sip_h_X-calltype")
                   session:setVariable("cc_export_vars", "calltype,sip_h_X-calltype")

                    session:execute("export", "nolocal:calltype=" .. calltype)



