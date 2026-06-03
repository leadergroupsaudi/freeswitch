-- ============================================================
-- FILE: extension_registry.lua
-- PLACE AT: /etc/freeswitch/scripts/extension_registry.lua
--
-- HOW IT IS INVOKED — lua.conf.xml only:
--   <hook event="REGISTER" script="extension_registry.lua"/>
--
-- That's it. FreeSWITCH calls this file automatically
-- every time any device sends a SIP REGISTER.
-- No dialplan entry needed. No manual calls needed.
-- ============================================================

-- ── Step 1: Read what just registered ───────────────────────
local ext     = event:getHeader("To-User")                      -- e.g. "1001"
local profile = event:getHeader("variable_sofia_profile_name")  -- "wss" or "internal"
local contact = event:getHeader("Contact")                      -- SIP contact URI
local net_ip  = event:getHeader("network-ip")                   -- device IP address
local agent   = event:getHeader("User-Agent")                   -- "Zoiper5" or "WebRTC"

freeswitch.consoleLog("NOTICE", string.format(
    "[Registry] REGISTER received → ext=%s | profile=%s | agent=%s | ip=%s\n",
    tostring(ext), tostring(profile), tostring(agent), tostring(net_ip)
))

-- ── Guard: must have an extension ───────────────────────────
if not ext or ext == "" then
    freeswitch.consoleLog("ERR", "[Registry] No extension in REGISTER event. Aborting.\n")
    return
end

-- ── Step 2: Read existing registry (stored in FS global vars) ──
local old_profile = freeswitch.getGlobalVariable("ext_profile_" .. ext)
local old_ip      = freeswitch.getGlobalVariable("ext_ip_"      .. ext)

-- ── Step 3: Check if already registered ─────────────────────
if old_profile and old_profile ~= "" then

    -- Same device registering again — nothing to do
    if old_profile == profile and old_ip == net_ip then
        freeswitch.consoleLog("INFO", string.format(
            "[Registry] ext %s already on profile=%s ip=%s — no action needed.\n",
            ext, profile, net_ip
        ))
        return
    end

    -- Different device — flush the OLD device first
    freeswitch.consoleLog("WARNING", string.format(
        "[Registry] ext %s moving from profile=%s ip=%s → profile=%s ip=%s\n",
        ext, old_profile, tostring(old_ip), profile, net_ip
    ))

    -- Flush old registration via sofia
    local api    = freeswitch.API()
    local result = api:execute("sofia", string.format(
        "profile %s flush_inbound_reg %s reboot", old_profile, ext
    ))

    freeswitch.consoleLog("NOTICE", string.format(
        "[Registry] Flushed ext %s from old profile=%s | result=%s\n",
        ext, old_profile, tostring(result)
    ))

    -- Clear old record before saving new one
    freeswitch.setGlobalVariable("ext_profile_" .. ext, "")
    freeswitch.setGlobalVariable("ext_ip_"      .. ext, "")
    freeswitch.setGlobalVariable("ext_contact_" .. ext, "")

    -- Small pause so flush completes
    freeswitch.msleep(300)

else
    freeswitch.consoleLog("INFO", string.format(
        "[Registry] ext %s — fresh registration on profile=%s\n", ext, profile
    ))
end

-- ── Step 4: Save new registration ───────────────────────────
freeswitch.setGlobalVariable("ext_profile_" .. ext, profile)
freeswitch.setGlobalVariable("ext_ip_"      .. ext, net_ip)
freeswitch.setGlobalVariable("ext_contact_" .. ext, contact)

freeswitch.consoleLog("NOTICE", string.format(
    "[Registry] ext %s now active → profile=%s | ip=%s | agent=%s\n",
    ext, profile, net_ip, tostring(agent)
))
