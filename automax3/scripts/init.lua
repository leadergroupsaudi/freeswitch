script_dir = freeswitch.getGlobalVariable("script_dir")
local M = {}
local cache_manager = require "services.cache_manager"
local file_utils = require "utils.file_utils"
local json_utils = require "utils.json_utils"
 
local configs = {}
local config_files = {
    ivr = "ivr-cc-config/ivrconfig.json",
    webapi = "ivr-cc-config/automax_webAPIConfig.json",
    extensions = "ivr-cc-config/Extensions_qa.json",
    recording = "ivr-cc-config/RecordingType_qa.json"
}
 
function M.load_all()
    local scripts_path = freeswitch.getGlobalVariable("script_dir")
    for key, file_path in pairs(config_files) do
        local full_path = scripts_path .. "/" .. file_path
        local cached_config = cache_manager.get("config_" .. key)
        if not cached_config or file_utils.is_modified(full_path, "config_" .. key) then
            local success, config = json_utils.load_file(full_path)
            if not success then
                return false, "Failed to load " .. key .. " config"
            end
            configs[key] = config
            cache_manager.set("config_" .. key, config, 3600) -- 1 hour cache
            file_utils.update_mtime(full_path, "config_" .. key)
        else
            configs[key] = cached_config
        end
    end
    return true, nil
end
 
function M.get(config_name)
    return configs[config_name]
end
 
return M
