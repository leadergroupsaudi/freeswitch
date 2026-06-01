if session:getVariable("record_count") == nil then
    -- If record_count does not exist, set it to 0 for the first recording
    record_count = 0
    session:setVariable("record_count", record_count)
    session:execute("export","nolocal:record_count="..record_count)
    freeswitch.consoleLog("info", "record_count value for the first recording is " .. session:getVariable("record_count") .. "\n")
else
    -- If record_count exists, increment it by 1 for subsequent recordings
    count = session:getVariable("record_count")
    local incrementedCount = tonumber(count) + 1
    session:setVariable("record_count", tostring(incrementedCount))
    freeswitch.consoleLog("info", "Incrementing record_count to " .. incrementedCount .. "\n")
end
