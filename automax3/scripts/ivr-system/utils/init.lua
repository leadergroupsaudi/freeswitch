--------------------------------------------------------------------------------
-- Utilities Module Loader
-- 
-- Provides a unified interface to load all utility modules. This module
-- acts as the entry point for the utility layer.
--
-- Available Utilities:
-- - logging: Smart logging system with levels
-- - string_utils: String manipulation and escaping
-- - json_utils: JSON parsing and encoding
-- - file_utils: File operations and validation
-- - validators: Input validation functions
-- - config_utils: Configuration utilities and language setup
--
-- Usage:
--   local utils = require "utils"
--   utils.logging.get_logger("my_module")
--   utils.string_utils.shell_escape(user_input)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Lazy load utility modules
M.logging = require "utils.logging"
M.string_utils = require "utils.string_utils"
M.json_utils = require "utils.json_utils"
M.file_utils = require "utils.file_utils"
M.validators = require "utils.validators"
M.config_utils = require "utils.config_utils"

return M
