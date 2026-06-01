local api = freeswitch.API()


    session:execute("playback", "/usr/local/freeswitch-prod-instance/share/freeswitch/sounds/custom-ivrs/AgentBusy.wav")
   os.execute("sleep   1");
    session:hangup()

