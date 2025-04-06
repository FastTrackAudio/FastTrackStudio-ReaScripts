-- @noindex
--[[
 * FastTrackStudio - Utility Functions Module
 * Common helper functions for the FTS Import Into Template By Name GUI
--]]

local Utils = {}

-- Helper function for deep table copy
function Utils.CopyTable(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = Utils.CopyTable(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Path utility functions
function Utils.GetScriptPath()
    local info = debug.getinfo(1, "S")
    local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
    return script_path
end

-- Get the root path of FastTrackStudio Scripts
function Utils.GetRootPath(script_path)
    -- If script_path is not provided, get it from current script
    if not script_path then
        script_path = Utils.GetScriptPath()
    end
    
    local root_path = script_path:match("(.*[/\\])Organization[/\\].*[/\\]")
    if not root_path then
        root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]")
    end
    return root_path
end

-- Function to create an empty categories structure
function Utils.CreateEmptyCategories(category_keys)
    local result = {}
    for _, key in ipairs(category_keys) do
        result[key] = { patterns = {}, required = false }
    end
    return result
end

-- Function to get category keys from category array
function Utils.GetCategoryKeys(categories)
    local keys = {}
    for _, category in ipairs(categories) do
        table.insert(keys, category.key)
    end
    return keys
end

-- Function to check if a value exists in a table
function Utils.TableContains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Function to get file contents
function Utils.ReadFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    return content
end

-- Function to write file contents
function Utils.WriteFile(path, content)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    
    file:write(content)
    file:close()
    return true
end

-- File path utilities
function Utils.JoinPaths(...)
    local separator = package.config:sub(1,1) -- Get OS path separator
    local result = table.concat({...}, separator)
    return result
end

-- UI Helper functions
function Utils.CreateTooltip(ctx, text)
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, text)
        reaper.ImGui_EndTooltip(ctx)
    end
end

-- String utilities
function Utils.TrimString(s)
    return s:match("^%s*(.-)%s*$")
end

-- Convert boolean to string representation
function Utils.BoolToString(value)
    return value and "Yes" or "No"
end

-- Sort table by key
function Utils.SortTableByKey(tbl)
    local sorted = {}
    for k in pairs(tbl) do
        table.insert(sorted, k)
    end
    table.sort(sorted)
    
    local result = {}
    for _, k in ipairs(sorted) do
        result[k] = tbl[k]
    end
    return result
end

-- Get keys from a table as array
function Utils.GetTableKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

return Utils 