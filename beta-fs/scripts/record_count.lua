local record_count = session:getVariable("record_count");
freeswitch.consoleLog("notice","Record_count variable found " .. record_count);
recordcount_incre = record_count + 1

session:setVariable("record_count", recordcount_incre);
freeswitch.consoleLog("notice","Record_count incremented_value : " .. recordcount_incre);
