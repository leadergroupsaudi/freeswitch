local consumer = freeswitch.EventConsumer("CHANNEL_HANGUP_COMPLETE")

while true do
    local e = consumer:pop()

    if e then
        freeswitch.consoleLog("NOTICE", "HANGUP EVENT RECEIVED\n")
        freeswitch.consoleLog("NOTICE", e:serialize() .. "\n")
    end
end
