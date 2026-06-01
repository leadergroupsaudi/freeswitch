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

-- SQL to create the agent table if it doesn't exist
local create_table_sql = [[
CREATE TABLE IF NOT EXISTS agentstack (
    extensioncode VARCHAR(50) PRIMARY KEY,
    isactive BOOLEAN DEFAULT FALSE,
    incall BOOLEAN DEFAULT FALSE,
    noofcalls BIGINT DEFAULT 0,
    talktime BIGINT DEFAULT 0,
    waittime BIGINT DEFAULT 0,
    priority INTEGER DEFAULT 1
);
]]

-- Execute the SQL to create the table
local success, err = dbh:query(create_table_sql)
if not success then
    freeswitch.consoleLog("ERR", "Failed to create the agent table - Error: " .. tostring(err) .. "\n")
    return
end

freeswitch.consoleLog("INFO", "Table agent is ready.\n")

-- Manually insert data into the agent table
local insert_sql = [[
    INSERT INTO agentstack (extensioncode, isactive, incall, noofcalls, talktime, waittime, priority)
    VALUES 
    ('1800', TRUE, FALSE, 10, 300, 120, 1),
    ('1801', FALSE, FALSE, 5, 150, 60, 2),
    ('1802', TRUE, TRUE, 15, 450, 30, 1)
    ON CONFLICT (extensioncode) DO NOTHING;  -- Do nothing if the extension already exists
]]

-- Execute the insert SQL statement
local success, err = dbh:query(insert_sql)
if not success then
    freeswitch.consoleLog("ERR", "Failed to insert data into the agent table - Error: " .. tostring(err) .. "\n")
else
    freeswitch.consoleLog("INFO", "Data inserted successfully into the agent table.\n")
end

-- Release the database handle
dbh:release()

