-- resources/strManipulate.lua
strManipulate = {}
        function strManipulate.insert_spaces(str)
            local result = ""
            for i = 1, #str do
                local char = str:sub(i, i)
                if char:match("%d") then
                    result = result .. " " .. char
                else
                    result = result .. char
                end
            end
            return result
        end

        function strManipulate.replacePlaceholder(url, fieldName, replacement)
                 return url:gsub(fieldName, replacement)
        end

return strManipulate
