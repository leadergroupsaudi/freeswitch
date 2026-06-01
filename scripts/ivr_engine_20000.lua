-- IVR Engine: 20000 | Generated: 2026-05-19T07:12:57.016Z
-- No external dependencies (flow embedded as Lua table)
local flow = {
    ["entry"] = "main_menu",
    ["nodes"] = {
      ["main_menu"] = {
        ["type"] = "menu",
        ["audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/ivr_menu.wav",
        ["invalid_audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/provideinput.wav",
        ["digits"] = "1 1 3 5000",
        ["valid_digits"] = "(^1$|^2$|^3$|^4$|^5$)",
        ["max_retries"] = 3,
        ["next"] = {
          ["1"] = "press1",
          ["2"] = "press2",
          ["3"] = "press3",
          ["4"] = "press4",
          ["5"] = "direct_agent"
        }
      },
      ["press1"] = {
        ["type"] = "confirm",
        ["audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/after_press1.wav",
        ["invalid_audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/provideinput.wav",
        ["digits"] = "1 1 3 5000",
        ["valid_digits"] = "(^1$|^2$|^3$|^9$)",
        ["max_retries"] = 3,
        ["next"] = {
          ["1"] = "agent_queue",
          ["2"] = "agent_queue",
          ["3"] = "agent_queue",
          ["9"] = "main_menu"
        }
      },
      ["press2"] = {
        ["type"] = "confirm",
        ["audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/after_press2.wav",
        ["invalid_audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/provideinput.wav",
        ["digits"] = "1 1 3 5000",
        ["valid_digits"] = "(^1$|^2$|^3$|^4$|^9$)",
        ["max_retries"] = 3,
        ["next"] = {
          ["1"] = "agent_queue",
          ["2"] = "agent_queue",
          ["3"] = "agent_queue",
          ["4"] = "agent_queue",
          ["9"] = "main_menu"
        }
      },
      ["press3"] = {
        ["type"] = "confirm",
        ["audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/after_press3.wav",
        ["invalid_audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/provideinput.wav",
        ["digits"] = "1 1 3 5000",
        ["valid_digits"] = "(^1$|^2$|^3$|^4$|^9$)",
        ["max_retries"] = 3,
        ["next"] = {
          ["1"] = "agent_queue",
          ["2"] = "agent_queue",
          ["3"] = "agent_queue",
          ["4"] = "agent_queue",
          ["9"] = "main_menu"
        }
      },
      ["press4"] = {
        ["type"] = "confirm",
        ["audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/after_press4.wav",
        ["invalid_audio"] = "/usr/local/freeswitch-automax-instance/share/freeswitch/sounds/custom/provideinput.wav",
        ["digits"] = "1 1 3 5000",
        ["valid_digits"] = "(^1$|^2$|^3$|^9$)",
        ["max_retries"] = 3,
        ["next"] = {
          ["1"] = "agent_queue",
          ["2"] = "agent_queue",
          ["3"] = "agent_queue",
          ["9"] = "main_menu"
        }
      },
      ["direct_agent"] = {
        ["type"] = "transfer",
        ["destination"] = "direct_agent",
        ["context"] = "default"
      },
      ["agent_queue"] = {
        ["type"] = "transfer",
        ["destination"] = "direct_agent",
        ["context"] = "default"
      }
    }
  }

session:answer()
session:sleep(500)

local function getDigits(n)
  local a,b,c,d = n.digits:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
  return session:playAndGetDigits(
    tonumber(a),tonumber(b),tonumber(c),tonumber(d),
    "#", n.audio or "", n.invalid_audio or "", n.valid_digits or "[0-9]+"
  )
end

local depth = 0
local function exec(name)
  depth = depth + 1
  if depth > 50 then session:execute("hangup"); return end
  local n = flow.nodes[name]
  if not n then session:execute("hangup"); return end
  if n.type == "menu" or n.type == "confirm" or n.type == "submenu" then
    local retries, att = n.max_retries or 3, 0
    while att < retries do
      local d = getDigits(n)
      if d and d ~= "" and n.next and n.next[d] then
        if n.next[d] == "__hangup__" then session:execute("hangup"); return end
        exec(n.next[d]); return
      end
      att = att + 1
    end
    session:execute("hangup")
  elseif n.type == "transfer" then
    local m = n.mode or "blind"
    if m == "queue" then
      session:execute("fifo", n.destination.." in undef "..(n.ringback or "local_stream://moh"))
    else
      session:execute("transfer", n.destination.." XML "..(n.context or "default"))
    end
  elseif n.type == "voicemail" then
    session:execute("voicemail","default "..(n.domain or "default").." "..n.mailbox)
  elseif n.type == "hangup" then
    if n.audio then session:execute("playback",n.audio) end
    session:execute("hangup")
  elseif n.type == "greeting" or n.type == "audio" then
    if n.audio then session:execute("playback",n.audio)
    elseif n.msg then session:execute("speak","flite|kal|"..n.msg) end
    if n.next then
      local nxt = type(n.next)=="string" and n.next or next(n.next)
      if nxt then exec(nxt) end
    end
  elseif n.type == "hours" then
    local hour=tonumber(os.date("%H")); local min=tonumber(os.date("%M"))
    local now=hour*60+min
    local sh,sm=(n.open_start or "09:00"):match("(%d+):(%d+)")
    local eh,em=(n.open_end   or "18:00"):match("(%d+):(%d+)")
    local is_open=now>=tonumber(sh)*60+tonumber(sm) and now<tonumber(eh)*60+tonumber(em)
    exec(is_open and n.next.open or n.next.closed)
  elseif n.type == "holiday" then
    local today=os.date("%Y-%m-%d")
    local is_holiday=(n.holidays or ""):find(today,1,true)~=nil
    exec(is_holiday and n.next.holiday or n.next.normal)
  end
  depth = depth - 1
end

exec(flow.entry or "main_menu")
