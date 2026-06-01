-- resources/speechFuncations.lua

local speechFuncations = {}

function speechFuncations.setLanguage(languageCode)
                freeswitch.consoleLog("INFO","Language Set Function")
                for _,settings in pairs(generalSettings) do
                        if settings.SettingId == 15 then
                                local languageSettings = json.decode(settings.SettingValue)
                                for _, setting in ipairs(languageSettings) do
                                    if setting.LanguageCode == tonumber(languageCode) then
                                        for key, value in pairs(setting) do
                                                session:setVariable(key,value)
                                        end
                                    end
                                end
                                break
                        end
                end
end
return speechFuncations
