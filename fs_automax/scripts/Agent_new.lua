-- Load LuaSQL PostgreSQL module
--local luasql = require "luasql.postgres"
-- Create an environment object
--local env = assert(luasql.postgres())
-- PostgreSQL connection details
--local db_host = "localhost"   -- Database host
--local db_port = "5432"        -- Database port
--local db_name = "your_db_name"  -- Your database name
--local db_user = "your_db_user"  -- Your database username
--local db_password = "your_db_password"  -- Your database password
--local conn = assert(env:connect(db_name, db_user, db_password, db_host, db_port))

-- Check if connection is successful
--if conn then
--	freeswitch.consoleLog("INFO", "Connected to PostgreSQL database successfully!\n")
--else
--	freeswitch.consoleLog("ERR", "Failed to connect to PostgreSQL database!\n")
--end

-- Don't forget to close the connection after you're done
--conn:close()
--env:close()


local function operation_code_100_exec(data)
	freeswitch.consoleLog("notice","\n *** Operation code 100 func {Agent Transfer} ***\n")
	local extensions = {}
	local ext_not_reg = "error/user_not_registered"
	local dbh = freeswitch.Dbh("pgsql://freeswitch:AxiV0!P789@127.0.0.1:5432/freeswitch")
	if not dbh then
		freeswitch.consoleLog("ERR", "Failed to connect to PostgreSQL database.\n")
	else
		-- SQL query to test connection
		local sql = "SELECT NOW() AS current_time"

		-- Execute the query
		local result = dbh:query(sql, function(row)
			freeswitch.consoleLog("NOTICE", "Current time from PostgreSQL: " .. row.current_time .. "\n")
		end)

		-- Check for errors
		if not result then
			freeswitch.consoleLog("ERR", "Error executing query.\n")
		end
	end
	for key, value in pairs(agent_extensions.Extensions) do
		if value.IsAgent == false then
			api:executeString("callcenter_config agent set state " .. value.ExtensionCode .. " Idle")
			---need to set 0 in table for that Extension ---
			dbh:query("UPDATE agent_table SET InCall = 0 WHERE ExtensionCode = '" .. value.ExtensionCode .. "'")

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
				-- Check if the agent is already in a call
				local agent_state = api:executeString("callcenter_config agent get state " .. agent_extension)
				if agent_state == "InCall" then
					freeswitch.consoleLog("INFO", "Agent " .. value.ExtensionCode .. " is currently in a call.\n")
				else
					freeswitch.consoleLog("INFO", "Agent " .. value.ExtensionCode .. " is available for a new call.\n")
					-- Proceed to assign the call to this agent
					-- Add logic for call assignment here
					session:execute("sleep","500")
					session:execute("callcenter","ccm-ivr@default")
				end
			else
				freeswitch.consoleLog("notice","Extension " .. value.ExtensionCode .. " Not registered . Changing status to Logged Out ..")
				api:executeString("callcenter_config agent set status " .. value.ExtensionCode .. " 'Logged Out'")
			end
		end
	end
	--     session:execute("sleep","500")
	--       session:execute("callcenter","ccm-ivr@default")
  end
operation_code_100_exec("test data");
