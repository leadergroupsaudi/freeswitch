H="X-Api-Key: LeaderFS@Axionic#2026"

# Real FreeSWITCH use case — time-based routing with anti-action fallback
curl -s -X POST http://127.0.0.1/api/admin/dialplan/public \
  -H "Content-Type: application/json" -H "$H" \
  -d '{
    "name": "office-hours-routing",
    "extension": "^9876543210$",
    "conditions": [
      {
        "field":      "destination_number",
        "expression": "^9876543210$"
      },
      {
        "field":      "date-time",
        "expression": "^2026",
        "year":       "2026",
        "mday":       "1-31",
        "hour":       "9-18",
        "wday":       "2-6",
        "mon":        "1-12"
      }
    ],
    "actions": [
      {"_type": "action",      "application": "set",      "data": "call_direction=inbound"},
      {"_type": "action",      "application": "answer"},
      {"_type": "action",      "application": "transfer",  "data": "1000 XML default"},
      {"_type": "anti-action", "application": "answer"},
      {"_type": "anti-action", "application": "playback",  "data": "ivr/ivr-office_is_closed.wav"},
      {"_type": "anti-action", "application": "hangup"}
    ],
    "priority": 2,
    "enabled": true
  }'
