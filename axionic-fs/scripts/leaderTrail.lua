-- answer the call
session:answer()
session:execute("sleep", "500")  -- wait 0.5s

-- speak welcome message using TTS
session:execute("speak", "en-US 'Welcome to LeSaaS support, please wait while we connect you to an agent'")

-- hang up after speaking
session:hangup()

