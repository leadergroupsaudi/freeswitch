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

-- SQL to create the trials table if it doesn't exist
local create_table_sql = [[
CREATE TABLE IF NOT EXISTS trials (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
]]

-- Execute the SQL to create the table
local success, err = dbh:query(create_table_sql)
if not success then
    freeswitch.consoleLog("ERR", "Failed to create the trials table - Error: " .. tostring(err) .. "\n")
    return
end

freeswitch.consoleLog("INFO", "Table 'trials' is ready.\n")

-- Release the database handle
dbh:release()

