local json = require("lunajson")

-- Your JSON string
local jsonString = '[{"ResultFieldTag":"auth_token","ResultFieldName":"token","ParentResultId":null,"IsList":false,"ListIndex":0,"ListFilter":null,"OutputFeildId":1,"DefaultValue":"","IsSuccessValidator":false,"SuccessValue":""},{"ResultFieldTag":"auth_userId","ResultFieldName":"userId","ParentResultId":null,"IsList":false,"ListIndex":0,"ListFilter":null,"OutputFeildId":2,"DefaultValue":"0","IsSuccessValidator":false,"SuccessValue":""}]'

-- Parse the JSON string
local jsonData = json.decode(jsonString)

-- Iterate through the array and check if ParentResultId is null
for _, item in ipairs(jsonData) do
    if item.ParentResultId == nil then
        print("ParentResultId is null for ResultFieldTag: " .. item.ResultFieldTag)
    end
end
				
for _, item in ipairs(jsonData) do
    if item.ParentResultId ~= nil then
	
        print("ParentResultId is not null for ResultFieldTag: " .. item.ResultFieldTag)
    end
end
