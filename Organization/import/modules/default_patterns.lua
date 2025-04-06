-- @noindex
--[[
 * FastTrackStudio - Default Patterns Module
 * Handles the loading, saving, and management of default patterns
--]]

local DefaultPatterns = {}

-- Get dependencies
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local modules_path = script_path:match("(.*[/\\])modules[/\\]")
local root_path = modules_path:match("(.*[/\\])Organization[/\\].*[/\\]")
if not root_path then
    root_path = modules_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

package.path = package.path .. ";" .. modules_path .. "?.lua"
local Utils = require("utils")
local json = dofile(root_path .. "libraries/utils/json.lua")

-- Constants for inheritance modes
local INHERITANCE_MODES = {
    DEFAULT_ONLY = 1,
    DEFAULT_PLUS_OVERRIDE = 2,
    OVERRIDE_ONLY = 3
}
DefaultPatterns.INHERITANCE_MODES = INHERITANCE_MODES

-- Global pattern categories definition
local GLOBAL_PATTERN_CATEGORIES = {
    { key = "tracking", name = "Tracking Info", desc = "Recording takes, comps, versions (enclosed in brackets)" },
    { key = "subtype", name = "Subtype", desc = "Type variations (Clean, Distorted, Hard, Soft)" },
    { key = "arrangement", name = "Arrangement", desc = "Arrangement parts (Verse, Chorus, Bridge)" },
    { key = "performer", name = "Performer", desc = "Performer names (enclosed in parentheses)" },
    { key = "section", name = "Section", desc = "Song sections or musical parts" },
    { key = "layers", name = "Layers", desc = "Doubled parts and layers" },
    { key = "mic", name = "Mic", desc = "Microphone positions or types" },
    { key = "playlist", name = "Playlist", desc = "Multiple takes/alternatives (.1, .2, etc.)" }
}
DefaultPatterns.GLOBAL_PATTERN_CATEGORIES = GLOBAL_PATTERN_CATEGORIES

-- Load defaults from the defaults.json file
function DefaultPatterns.LoadDefaults()
    local defaults_path = root_path .. "Organization/import/defaults.json"
    local content = Utils.ReadFile(defaults_path)
    
    if not content then
        return { default_patterns = {}, default_groups = {} }
    end
    
    local success, defaults = pcall(function() return json.decode(content) end)
    if not success or not defaults then
        reaper.ShowConsoleMsg("Error parsing defaults.json file. Using empty defaults.\n")
        return { default_patterns = {}, default_groups = {} }
    end
    
    return defaults
end

-- Save defaults to the defaults.json file
function DefaultPatterns.SaveDefaults(defaults)
    local defaults_path = root_path .. "Organization/import/defaults.json"
    local content = json.encode(defaults)
    return Utils.WriteFile(defaults_path, content)
end

-- Load inheritance mode preference
function DefaultPatterns.LoadInheritanceMode(ext_state_name, key, default_mode)
    local mode = tonumber(reaper.GetExtState(ext_state_name, key .. "_inheritance_mode"))
    if not mode or mode < 1 or mode > 3 then
        return default_mode or INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE
    end
    return mode
end

-- Save inheritance mode preference
function DefaultPatterns.SaveInheritanceMode(ext_state_name, key, mode)
    reaper.SetExtState(ext_state_name, key .. "_inheritance_mode", tostring(mode), true)
end

-- Load global pattern configurations with inheritance
function DefaultPatterns.LoadGlobalPatterns(ext_state_name, load_ext_state_table_func)
    local loaded
    
    -- Check if load_ext_state_table_func is a function before using it
    if type(load_ext_state_table_func) == "function" then
        loaded = load_ext_state_table_func(ext_state_name, "global_patterns", true)
    else
        -- Fallback implementation if a function wasn't provided
        local value = reaper.GetExtState(ext_state_name, "global_patterns")
        if value and value ~= "" then
            local success, data = pcall(function() return json.decode(value) end)
            if success then loaded = data end
        end
    end
    
    local defaults = DefaultPatterns.LoadDefaults().default_patterns
    local mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "global_patterns", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    
    -- Default empty global pattern configurations
    local result = {}
    
    -- Prepare result based on inheritance mode
    if mode == INHERITANCE_MODES.DEFAULT_ONLY then
        -- Use defaults only
        for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
            if defaults[category.key] then
                result[category.key] = { 
                    patterns = Utils.CopyTable(defaults[category.key]),
                    required = false 
                }
            else
                result[category.key] = { patterns = {}, required = false }
            end
        end
    elseif mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        -- Use defaults plus overrides
        for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
            result[category.key] = { patterns = {}, required = false }
            
            -- Copy defaults first
            if defaults[category.key] then
                for _, pattern in ipairs(defaults[category.key]) do
                    table.insert(result[category.key].patterns, pattern)
                end
            end
            
            -- Then add overrides
            if loaded and loaded[category.key] then
                result[category.key].required = loaded[category.key].required or false
                
                -- Add patterns that aren't already in the defaults
                for _, pattern in ipairs(loaded[category.key].patterns or {}) do
                    -- Check if pattern is already in the result
                    local found = false
                    for _, existing in ipairs(result[category.key].patterns) do
                        if existing == pattern then
                            found = true
                            break
                        end
                    end
                    
                    if not found then
                        table.insert(result[category.key].patterns, pattern)
                    end
                end
            end
        end
    else -- OVERRIDE_ONLY
        -- Only use saved overrides
        if loaded then
            result = loaded
        else
            -- If no overrides, create empty categories
            for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
                result[category.key] = { patterns = {}, required = false }
            end
        end
    end
    
    return result
end

-- Save global pattern configurations
function DefaultPatterns.SaveGlobalPatterns(ext_state_name, patterns, save_ext_state_table_func)
    -- Check if save_ext_state_table_func is a function before using it
    if type(save_ext_state_table_func) == "function" then
        save_ext_state_table_func(ext_state_name, "global_patterns", patterns, true)
    else
        -- Fallback implementation if a function wasn't provided
        local data_to_save = patterns
        if type(data_to_save) == "table" then
            data_to_save = json.encode(patterns)
        end
        reaper.SetExtState(ext_state_name, "global_patterns", data_to_save, true)
    end
end

-- Variables for editing default patterns
local is_editing_defaults = false
local editing_default_patterns = {}
local new_default_pattern = {}

-- Function to setup editing of default patterns
function DefaultPatterns.BeginEditDefaultPatterns(ctx)
    -- Load current defaults
    local defaults = DefaultPatterns.LoadDefaults()
    
    -- Convert default_patterns to the format expected by ShowEditDefaultPatternsPopup
    local editing_patterns = {}
    for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
        editing_patterns[category.key] = defaults.default_patterns[category.key] or {}
    end
    
    -- Set up for editing
    is_editing_defaults = true
    editing_default_patterns = editing_patterns
    reaper.ImGui_OpenPopup(ctx, "Edit Default Patterns")
end

-- Function to show the Edit Default Patterns popup
function DefaultPatterns.ShowEditDefaultPatternsPopup(ctx)
    if not is_editing_defaults then return end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    
    if reaper.ImGui_BeginPopupModal(ctx, "Edit Default Patterns", true, popup_flags) then
        reaper.ImGui_Text(ctx, "Edit the default patterns for all categories")
        reaper.ImGui_Spacing(ctx)
        
        -- Begin a tabbar for the categories
        if reaper.ImGui_BeginTabBar(ctx, "DefaultPatternTabs") then
            for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
                if reaper.ImGui_BeginTabItem(ctx, category.name) then
                    reaper.ImGui_TextWrapped(ctx, category.desc)
                    reaper.ImGui_Spacing(ctx)
                    
                    -- Ensure the category exists
                    if not editing_default_patterns[category.key] then
                        editing_default_patterns[category.key] = {}
                    end
                    
                    -- Ensure new_default_pattern for this category is initialized
                    if not new_default_pattern[category.key] then
                        new_default_pattern[category.key] = ""
                    end
                    
                    -- New pattern input
                    local changed_pattern, value_pattern = reaper.ImGui_InputText(ctx, "New Pattern##default_" .. category.key, new_default_pattern[category.key], 256)
                    if changed_pattern then
                        new_default_pattern[category.key] = value_pattern
                    end
                    
                    reaper.ImGui_SameLine(ctx)
                    
                    if reaper.ImGui_Button(ctx, "Add##default_" .. category.key) and new_default_pattern[category.key] ~= "" then
                        table.insert(editing_default_patterns[category.key], new_default_pattern[category.key])
                        new_default_pattern[category.key] = ""
                    end
                    
                    -- List of patterns
                    local patterns = editing_default_patterns[category.key]
                    if #patterns > 0 then
                        if reaper.ImGui_BeginListBox(ctx, "##default_" .. category.key .. "List", -1, 200) then
                            for i, pattern in ipairs(patterns) do
                                local selected = false
                                local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##default_" .. category.key .. i, selected)
                                
                                if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                    reaper.ImGui_OpenPopup(ctx, "default_" .. category.key .. "ContextMenu" .. i)
                                end
                                
                                if reaper.ImGui_BeginPopup(ctx, "default_" .. category.key .. "ContextMenu" .. i) then
                                    if reaper.ImGui_MenuItem(ctx, "Delete") then
                                        table.remove(editing_default_patterns[category.key], i)
                                    end
                                    reaper.ImGui_EndPopup(ctx)
                                end
                            end
                            reaper.ImGui_EndListBox(ctx)
                        end
                    else
                        reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No default patterns defined")
                    end
                    
                    reaper.ImGui_EndTabItem(ctx)
                end
            end
            reaper.ImGui_EndTabBar(ctx)
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Buttons for save/cancel
        local button_width = 120
        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SetCursorPosX(ctx, (window_width - (button_width * 2 + 10)) / 2)
        
        if reaper.ImGui_Button(ctx, "Save", button_width) then
            -- Get the current defaults
            local defaults = DefaultPatterns.LoadDefaults()
            
            -- Update the default patterns
            defaults.default_patterns = {}
            for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
                defaults.default_patterns[category.key] = editing_default_patterns[category.key] or {}
            end
            
            -- Save the updated defaults
            DefaultPatterns.SaveDefaults(defaults)
            
            -- Close the popup
            reaper.ImGui_CloseCurrentPopup(ctx)
            is_editing_defaults = false
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Cancel", button_width) then
            reaper.ImGui_CloseCurrentPopup(ctx)
            is_editing_defaults = false
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- Draw the Global Patterns tab UI
function DefaultPatterns.DrawGlobalPatternsTab(ctx, ext_state_name, load_ext_state_table_func, save_ext_state_table_func)
    reaper.ImGui_TextWrapped(ctx, "Configure global pattern categories that apply to all track groups. These patterns help generate more descriptive track names by extracting information from filenames.")
    reaper.ImGui_Spacing(ctx)
    
    -- Get global patterns with inheritance applied
    local global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, load_ext_state_table_func)
    
    -- Get current inheritance mode
    local current_mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "global_patterns", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local mode_names = { "Use Defaults Only", "Use Defaults + Overrides", "Use Overrides Only" }
    local modified = false
    
    -- Inheritance mode combo
    reaper.ImGui_Text(ctx, "Pattern Inheritance:")
    local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##global_patterns_mode", current_mode - 1, table.concat(mode_names, "\0") .. "\0", -1)
    if changed_mode then
        DefaultPatterns.SaveInheritanceMode(ext_state_name, "global_patterns", new_mode + 1)
        -- Reload patterns with new inheritance mode
        global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, load_ext_state_table_func)
        modified = true
    end
    
    -- Help text based on inheritance mode
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using default patterns only. Changes will not be saved.")
    elseif current_mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using defaults plus your overrides. New patterns will be saved as overrides.")
    else -- OVERRIDE_ONLY
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using only your overrides, ignoring defaults.")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Manage defaults button
    if reaper.ImGui_Button(ctx, "Edit Default Patterns", -1) then
        DefaultPatterns.BeginEditDefaultPatterns(ctx)
    end
    
    -- Show the Edit Default Patterns popup if active
    DefaultPatterns.ShowEditDefaultPatternsPopup(ctx)
    
    -- Variables for adding new patterns
    local new_pattern_text = {}
    for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
        new_pattern_text[category.key] = new_pattern_text[category.key] or ""
    end
    
    -- Begin a child window for scrolling
    reaper.ImGui_BeginChild(ctx, "##GlobalPatternScroll", 0, -30, true)
    
    -- For each pattern category, display an editor
    for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
        -- Initialize the category if it doesn't exist
        if not global_patterns[category.key] then
            global_patterns[category.key] = { patterns = {}, required = false }
        end
        
        if reaper.ImGui_CollapsingHeader(ctx, category.name) then
            -- Description
            reaper.ImGui_TextWrapped(ctx, category.desc)
            reaper.ImGui_Spacing(ctx)
            
            -- Required checkbox (only enable if not in DEFAULT_ONLY mode)
            local required_changed, required_value
            if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
                reaper.ImGui_BeginDisabled(ctx)
                required_changed, required_value = reaper.ImGui_Checkbox(ctx, "Required in Naming##" .. category.key, global_patterns[category.key].required)
                reaper.ImGui_EndDisabled(ctx)
            else
                required_changed, required_value = reaper.ImGui_Checkbox(ctx, "Required in Naming##" .. category.key, global_patterns[category.key].required)
                if required_changed then
                    global_patterns[category.key].required = required_value
                    modified = true
                end
            end
            
            -- Get default patterns for highlighting
            local defaults = DefaultPatterns.LoadDefaults().default_patterns
            local default_patterns = defaults[category.key] or {}
            
            -- New pattern input (only enable if not in DEFAULT_ONLY mode)
            if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
                reaper.ImGui_BeginDisabled(ctx)
            end
            
            local changed_pattern, value_pattern = reaper.ImGui_InputText(ctx, "New Pattern##" .. category.key, new_pattern_text[category.key], 256)
            if changed_pattern then
                new_pattern_text[category.key] = value_pattern
            end
            
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Add##" .. category.key) and new_pattern_text[category.key] ~= "" then
                table.insert(global_patterns[category.key].patterns, new_pattern_text[category.key])
                new_pattern_text[category.key] = ""
                modified = true
            end
            
            if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
                reaper.ImGui_EndDisabled(ctx)
            end
            
            -- List of existing patterns
            local patterns = global_patterns[category.key].patterns
            if #patterns > 0 then
                if reaper.ImGui_BeginListBox(ctx, "##" .. category.key .. "List", -1, 100) then
                    for i, pattern in ipairs(patterns) do
                        local is_default = false
                        
                        -- Check if this pattern is a default pattern
                        for _, default_pattern in ipairs(default_patterns) do
                            if pattern == default_pattern then
                                is_default = true
                                break
                            end
                        end
                        
                        -- Color code based on if it's a default pattern
                        if is_default then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x88CC88FF)
                        end
                        
                        local selected = false
                        local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##" .. category.key .. i, selected)
                        
                        if is_default then
                            reaper.ImGui_PopStyleColor(ctx)
                        end
                        
                        -- Only allow right-click delete for non-defaults or in OVERRIDE_ONLY mode
                        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) and 
                           (current_mode == INHERITANCE_MODES.OVERRIDE_ONLY or not is_default) then
                            reaper.ImGui_OpenPopup(ctx, category.key .. "ContextMenu" .. i)
                        end
                        
                        if reaper.ImGui_BeginPopup(ctx, category.key .. "ContextMenu" .. i) then
                            if reaper.ImGui_MenuItem(ctx, "Delete") then
                                table.remove(global_patterns[category.key].patterns, i)
                                modified = true
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                    end
                    reaper.ImGui_EndListBox(ctx)
                end
            else
                reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No patterns defined for " .. category.name)
            end
            
            reaper.ImGui_Separator(ctx)
        end
    end
    
    reaper.ImGui_EndChild(ctx)
    
    -- Save button at the bottom
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_BeginDisabled(ctx)
    end
    
    local save_clicked = reaper.ImGui_Button(ctx, "Save Global Patterns", -1)
    
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    if (save_clicked or modified) and current_mode ~= INHERITANCE_MODES.DEFAULT_ONLY then
        DefaultPatterns.SaveGlobalPatterns(ext_state_name, global_patterns, save_ext_state_table_func)
        reaper.ShowConsoleMsg("Global patterns saved.\n")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextWrapped(ctx, "Note: Green patterns are from defaults. Global patterns are combined with group-specific patterns (Prefix and Type) when naming tracks.")
end

-- DrawPatternsTab - Wrapper around DrawGlobalPatternsTab for backward compatibility
function DefaultPatterns.DrawPatternsTab(ctx, ext_state_name, load_ext_state_table_func, save_ext_state_table_func)
    -- Default function implementations if not provided
    local load_func = load_ext_state_table_func or function(ext_name, key, is_table)
        local value = reaper.GetExtState(ext_name, key)
        if value and value ~= "" and is_table then
            local success, data = pcall(function() return json.decode(value) end)
            if success then return data end
        end
        return value
    end
    
    local save_func = save_ext_state_table_func or function(ext_name, key, value, is_table)
        local data_to_save = value
        if is_table then
            data_to_save = json.encode(value)
        end
        reaper.SetExtState(ext_name, key, data_to_save, true)
    end
    
    -- Call the actual implementation
    DefaultPatterns.DrawGlobalPatternsTab(ctx, ext_state_name, load_func, save_func)
end

return DefaultPatterns 