--------------------------------------------------------------------------------
-- Logic Operations Module
--
-- Handles conditional logic and branching operations:
-- - Operation 120: Conditional branching based on comparisons
--
-- This module evaluates conditions and routes the call flow based on
-- comparison results (greater than, less than, between, etc.)
--
-- Usage:
--   Called automatically by the operation dispatcher
--   local logic = require "operations.logic"
--   logic.execute(120, node_data)
--
-- Author: IVR System Team
-- Version: 2.0.0
--------------------------------------------------------------------------------

local M = {}

-- Load dependencies
local session_manager = require "core.session_manager"
local call_flow = require "core.call_flow"
local logging = require "utils.logging"

-- Module logger
local logger = logging.get_logger("operations.logic")

--------------------------------------------------------------------------------
-- Execute Logic Operation
--
-- Main entry point for all logic operations. Routes to specific handlers
-- based on operation code.
--
-- @param operation_code number - The operation code (120)
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.execute(operation_code, node_data)
    logger:info(string.format(
        "Executing logic operation %d for node %d",
        operation_code, node_data.NodeId
    ))

    -- Route to appropriate handler
    if operation_code == 120 then
        M.conditional_branch(node_data)
    else
        error(string.format("Unknown logic operation code: %d", operation_code))
    end
end

--------------------------------------------------------------------------------
-- Helper: Get comparison value
--
-- Gets the value to compare, either from a session variable or directly
-- from the configuration.
--
-- @param child_node table - Child node configuration
-- @return number|nil - The numeric value to compare
--------------------------------------------------------------------------------
local function get_comparison_value(child_node)
    local session = session_manager.get_freeswitch_session()
    local value

    if child_node.OperandType == "T" then
        -- Get value from session variable (Tag)
        local tag_value = session:getVariable(child_node.CollectionTag)
        value = tonumber(tag_value)

        logger:debug(string.format(
            "Got value from tag '%s': %s -> %s",
            child_node.CollectionTag,
            tostring(tag_value),
            tostring(value)
        ))
    else
        -- Use the CollectionTag as a direct value
        value = tonumber(child_node.CollectionTag)

        logger:debug(string.format(
            "Using direct value: %s",
            tostring(value)
        ))
    end

    return value
end

--------------------------------------------------------------------------------
-- Helper: Evaluate comparison
--
-- Evaluates a comparison operation.
--
-- @param operator string - Comparison operator (GRT, LST, IBW, EQL, etc.)
-- @param value number - Value to compare
-- @param value1 number - First comparison value
-- @param value2 number|nil - Second comparison value (for range comparisons)
-- @return boolean - Result of comparison
--------------------------------------------------------------------------------
local function evaluate_comparison(operator, value, value1, value2)
    if value == nil then
        logger:warning("Cannot compare: value is nil")
        return false
    end

    logger:debug(string.format(
        "Evaluating: %s %s %s (value2: %s)",
        tostring(value), operator, tostring(value1), tostring(value2)
    ))

    if operator == "GRT" then
        -- Greater than
        return value > value1

    elseif operator == "LST" then
        -- Less than
        return value < value1

    elseif operator == "GTE" then
        -- Greater than or equal
        return value >= value1

    elseif operator == "LTE" then
        -- Less than or equal
        return value <= value1

    elseif operator == "EQL" then
        -- Equal
        return value == value1

    elseif operator == "NEQ" then
        -- Not equal
        return value ~= value1

    elseif operator == "IBW" then
        -- In between (inclusive)
        if value2 == nil then
            logger:warning("IBW comparison requires Value2")
            return false
        end
        return value >= value1 and value <= value2

    elseif operator == "OBW" then
        -- Outside between
        if value2 == nil then
            logger:warning("OBW comparison requires Value2")
            return false
        end
        return value < value1 or value > value2

    else
        logger:warning("Unknown comparison operator: " .. tostring(operator))
        return false
    end
end

--------------------------------------------------------------------------------
-- Operation 120: Conditional Branch
--
-- Evaluates conditions in child node configurations and routes to the
-- first matching child node. If no conditions match, routes to the
-- default child node (one without ApplyComparison).
--
-- Node Data Requirements:
-- - ChildNodeConfig: Array of child nodes with comparison configuration
--   - ApplyComparison: Whether to apply comparison logic
--   - ComparisonOperator: GRT, LST, IBW, EQL, etc.
--   - OperandType: "T" for tag/variable, other for direct value
--   - CollectionTag: Variable name or direct value
--   - Value1: First comparison value
--   - Value2: Second comparison value (for range comparisons)
--   - ChildNodeId: Node to route to if condition matches
--
-- Comparison Operators:
-- - GRT: Greater than (>)
-- - LST: Less than (<)
-- - GTE: Greater than or equal (>=)
-- - LTE: Less than or equal (<=)
-- - EQL: Equal (==)
-- - NEQ: Not equal (~=)
-- - IBW: In between (inclusive) (>= and <=)
-- - OBW: Outside between (< or >)
--
-- @param node_data table - The IVR node configuration data
-- @return void
--------------------------------------------------------------------------------
function M.conditional_branch(node_data)
    logger:info(string.format(
        "Operation 120: Conditional branch for node %d",
        node_data.NodeId
    ))

    -- Validate child node configuration
    if not node_data.ChildNodeConfig or #node_data.ChildNodeConfig == 0 then
        logger:error("No child node configuration for conditional branch")

        local session = session_manager.get_freeswitch_session()
        if session then
            session:hangup()
        end
        return
    end

    -- Iterate through child nodes and evaluate conditions
    for _, child_node in pairs(node_data.ChildNodeConfig) do
        if child_node.ApplyComparison == true then
            logger:debug(string.format(
                "Evaluating condition: %s %s %s",
                child_node.CollectionTag or "?",
                child_node.ComparisonOperator or "?",
                tostring(child_node.Value1)
            ))

            -- Get the value to compare
            local compare_value = get_comparison_value(child_node)

            -- Get comparison values
            local value1 = tonumber(child_node.Value1)
            local value2 = tonumber(child_node.Value2)

            -- Evaluate the comparison
            local result = evaluate_comparison(
                child_node.ComparisonOperator,
                compare_value,
                value1,
                value2
            )

            if result then
                logger:info(string.format(
                    "Condition matched, routing to child node %d",
                    child_node.ChildNodeId
                ))

                -- Find and execute the matching child node
                local target_node = call_flow.find_node_by_id(child_node.ChildNodeId)

                if target_node then
                    call_flow.execute_node(target_node)
                else
                    logger:error("Child node not found: " .. child_node.ChildNodeId)
                end

                return
            end
        else
            -- No comparison applied - this is the default/fallback path
            logger:info(string.format(
                "No comparison applied, using default child node %d",
                child_node.ChildNodeId
            ))

            local target_node = call_flow.find_node_by_id(child_node.ChildNodeId)

            if target_node then
                call_flow.execute_node(target_node)
            else
                logger:error("Default child node not found: " .. child_node.ChildNodeId)
            end

            return
        end
    end

    -- No conditions matched and no default found
    logger:warning("No conditions matched and no default path found")

    local session = session_manager.get_freeswitch_session()
    if session then
        session:hangup()
    end
end

return M
