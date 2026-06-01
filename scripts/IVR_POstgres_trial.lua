local json = require("lunajson")

-- Create a database handle
local db_connection_string = "host=127.0.0.1 dbname=freeswitch user=freeswitch password=AxiV0!P789"
local dbh = freeswitch.Dbh(db_connection_string)

-- Check if the connection was successful
if not dbh:connected() then
    freeswitch.consoleLog("ERR", "Failed to connect to PostgreSQL database.\n")
    return
end

freeswitch.consoleLog("INFO", "Successfully connected to PostgreSQL database.\n")

-- SQL to create the agent_status table if it doesn't exist
local create_table_sql = [[
CREATE TABLE IF NOT EXISTS agentstack (
    extensioncode VARCHAR(50) PRIMARY KEY,
    isactive BOOLEAN DEFAULT FALSE,
    incall BOOLEAN DEFAULT FALSE,
    noofcalls BIGINT DEFAULT 0,
    talktime BIGINT DEFAULT 0,
    waittime BIGINT DEFAULT 0,
    priority INTEGER DEFAULT 1,
    json_data JSONB
);
]]

-- Execute the SQL to create the table
local success, err = dbh:query(create_table_sql)
if not success then
    freeswitch.consoleLog("ERR", "Failed to create the agent_status table - Error: " .. tostring(err) .. "\n")
    return
end

freeswitch.consoleLog("INFO", "Table agent_status is ready.\n")

-- Path to the JSON file
local scripts_path = freeswitch.getGlobalVariable("script_dir")
local extensionsFilePath = scripts_path.."/ivr-cc-config/Extensions_qa.json"

-- Open the JSON file
local extensionConfigfile = io.open(extensionsFilePath, "r")
if not extensionConfigfile then
    freeswitch.consoleLog("ERR", "Error: Unable to open Extensions_qa.json file.\n")
    return
end

-- Read and close the JSON file
local extensionConfigjsonContent = extensionConfigfile:read("*a")
extensionConfigfile:close()

-- Parse the JSON content
local extension_data = json.decode(extensionConfigjsonContent)
package.path = scripts_path .."/".."?.lua;" .. package.path

--Check if the Extensions table is not nil
if not extension_data or not extension_data.Extensions then
    freeswitch.consoleLog("ERR", "No extensions found in the JSON data.\n")
    return
else
    freeswitch.consoleLog("INFO", "Extensions loaded successfully.\n")

    -- Loop through the extensions and insert them into the database
    for _, extension in ipairs(extension_data.Extensions) do
         local extensionCode = extension.extensioncode  -- Adjust this based on your JSON structure
         local isActive = extension.isactive or false    -- Assuming you have this field in your JSON
    	local inCall = extension.incall or false        -- Assuming you have this field in your JSON
    	local noOfCalls = extension.noofcalls or 0      -- Assuming you have this field in your JSON
    	local talkTime = extension.talktime or 0        -- Assuming you have this field in your JSON
    	local waitTime = extension.waittime or 0        -- Assuming you have this field in your JSON
    	local priority = extension.priority or 0        -- Assuming you have this field in your JSON
    	local jsonData = extension.json_data or "{}"    -- Assuming you have this field in your JSON


        -- Insert only if isAgent is true (considered inactive)
        if isAgent then
            -- Prepare SQL statement to insert the extension along with its status
            local sql = string.format([[
                INSERT INTO agentstack (extensioncode, isactive, incall, noofcalls, talktime, waittime, priority)
                VALUES ('%s', FALSE, FALSE, 0, 0, 0, %d)
                ON CONFLICT (extensioncode) DO NOTHING;  -- Do nothing if the extension already exists
            ]], extensionCode, extension.PriorityOrder)

            -- Execute the SQL statement and check for errors
            local success, err = dbh:query(sql)
            if not success then
                -- If the query fails, log an error
                freeswitch.consoleLog("ERR", "Failed to insert data for extension: " .. extensionCode .. " - Error: " .. tostring(err) .. "\n")
            else
                -- If the query succeeds, log a success message
                freeswitch.consoleLog("INFO", "Data inserted successfully for extension: " .. extensionCode .. "\n")
            end
        else
            freeswitch.consoleLog("INFO", "Extension " .. extensionCode .. " is active and will not be inserted.\n")
        end
    end
end

-- Release the database handle
dbh:release()

