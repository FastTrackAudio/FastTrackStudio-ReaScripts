-- @noindex
--[[
 * FastTrackStudio - Track Configuration Module
 * Handles the loading, saving, and management of track configurations
--]]

local TrackConfig = {}

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

-- Load default patterns module for inheritance modes
local DefaultPatterns = require("default_patterns")
local INHERITANCE_MODES = DefaultPatterns.INHERITANCE_MODES

-- Variables for editing track configurations
local is_editing_group = false
local editing_group = nil

-- Variables for editing default groups
local is_editing_default_groups = false
local editing_default_groups = {}
local selected_default_group_idx = 1

-- Create a new configuration group with default values
function TrackConfig.CreateNewConfigGroup()
    return {
        name = "",
        patterns = {},
        negative_patterns = {},
        parent_track = "",
        parent_track_guid = "",
        destination_track = "",
        destination_track_guid = "",
        insert_mode = "increment",
        increment_start = 1,
        only_number_when_multiple = true,
        create_if_missing = true,
        pattern_categories = {
            prefix = { patterns = {}, required = false },
            type = { patterns = {}, required = false }
        },
        rename_track = false
    }
end

-- Load track configurations with inheritance
function TrackConfig.LoadTrackConfigs(ext_state_name, import_script)
    local loaded = import_script.LoadTrackConfigs()
    local defaults = DefaultPatterns.LoadDefaults().default_groups
    local mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    
    -- Handle based on inheritance mode
    if mode == INHERITANCE_MODES.DEFAULT_ONLY then
        -- Use defaults only, converting to the expected format
        local result = {}
        for _, group in ipairs(defaults) do
            result[group.name] = Utils.CopyTable(group)
            
            -- Ensure required fields are present
            if not result[group.name].parent_track_guid then
                result[group.name].parent_track_guid = ""
            end
            
            -- Handle backward compatibility - use destination_track instead of matching_track
            if not result[group.name].destination_track then
                -- If no destination_track but has matching_track, use that
                if result[group.name].matching_track and result[group.name].matching_track ~= "" then
                    result[group.name].destination_track = result[group.name].matching_track
                else
                    -- Otherwise, use default_track or group name
                    result[group.name].destination_track = result[group.name].default_track or group.name
                end
            end
            
            -- Copy GUID if needed
            if not result[group.name].destination_track_guid and 
               result[group.name].matching_track_guid and 
               result[group.name].matching_track_guid ~= "" then
                result[group.name].destination_track_guid = result[group.name].matching_track_guid
            elseif not result[group.name].destination_track_guid then
                result[group.name].destination_track_guid = ""
            end
            
            -- Ensure rename_track option is present
            if result[group.name].rename_track == nil then
                result[group.name].rename_track = false
            end
        end
        return result
    elseif mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        -- Merge defaults and overrides
        local result = loaded or {}
        
        -- Add default groups that don't exist in overrides
        for _, group in ipairs(defaults) do
            if not result[group.name] then
                result[group.name] = Utils.CopyTable(group)
                
                -- Ensure required fields are present
                if not result[group.name].parent_track_guid then
                    result[group.name].parent_track_guid = ""
                end
                
                -- Handle backward compatibility - use destination_track instead of matching_track
                if not result[group.name].destination_track then
                    -- If no destination_track but has matching_track, use that
                    if result[group.name].matching_track and result[group.name].matching_track ~= "" then
                        result[group.name].destination_track = result[group.name].matching_track
                    else
                        -- Otherwise, use default_track or group name
                        result[group.name].destination_track = result[group.name].default_track or group.name
                    end
                end
                
                -- Copy GUID if needed
                if not result[group.name].destination_track_guid and 
                   result[group.name].matching_track_guid and 
                   result[group.name].matching_track_guid ~= "" then
                    result[group.name].destination_track_guid = result[group.name].matching_track_guid
                elseif not result[group.name].destination_track_guid then
                    result[group.name].destination_track_guid = ""
                end
                
                if not result[group.name].negative_patterns then
                    result[group.name].negative_patterns = {}
                end
                if not result[group.name].create_if_missing then
                    result[group.name].create_if_missing = true
                end
                if result[group.name].only_number_when_multiple == nil then
                    result[group.name].only_number_when_multiple = true
                end
                
                -- Ensure rename_track option is present
                if result[group.name].rename_track == nil then
                    result[group.name].rename_track = false
                end
            end
        end
        
        -- Ensure rename_track option is present in every config
        for name, config in pairs(result) do
            if config.rename_track == nil then
                config.rename_track = false
            end
        end
        
        return result
    else -- OVERRIDE_ONLY
        -- Still need to check for backward compatibility
        local result = loaded or {}
        for name, config in pairs(result) do
            -- Handle backward compatibility - use destination_track instead of matching_track
            if not config.destination_track then
                -- If no destination_track but has matching_track, use that
                if config.matching_track and config.matching_track ~= "" then
                    config.destination_track = config.matching_track
                else
                    -- Otherwise, use default_track or group name
                    config.destination_track = config.default_track or name
                end
            end
            
            -- Copy GUID if needed
            if not config.destination_track_guid and 
               config.matching_track_guid and 
               config.matching_track_guid ~= "" then
                config.destination_track_guid = config.matching_track_guid
            elseif not config.destination_track_guid then
                config.destination_track_guid = ""
            end
            
            -- Ensure rename_track option is present
            if config.rename_track == nil then
                config.rename_track = false
            end
        end
        return result
    end
end

-- Get track information for the currently selected track
function TrackConfig.GetSelectedTrackInfo()
    local sel_track = reaper.GetSelectedTrack(0, 0)
    if not sel_track then
        return nil, nil
    end
    
    local _, name = reaper.GetTrackName(sel_track)
    local guid = reaper.GetTrackGUID(sel_track)
    
    return guid, name
end

-- Find a track by GUID with fallback to name
-- This is important because GUIDs are project-specific, so each project can have different GUIDs
-- even when using the same configuration and track names
function TrackConfig.FindTrackByGUIDWithFallback(guid, name)
    -- First try to find by GUID if available
    if guid and guid ~= "" then
        local track = reaper.BR_GetMediaTrackByGUID(0, guid)
        if track then
            return track
        end
    end
    
    -- Fall back to name if GUID doesn't exist or couldn't be found
    if name and name ~= "" then
        -- Convert to lowercase for case-insensitive matching
        local lower_name = name:lower()
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = reaper.GetTrackName(track)
            -- Case-insensitive comparison
            if track_name:lower() == lower_name then
                return track
            end
        end
    end
    
    return nil
end

-- Function to setup editing of default groups
function TrackConfig.BeginEditDefaultGroups(ctx)
    -- Load current defaults
    local defaults = DefaultPatterns.LoadDefaults()
    
    -- Set up for editing
    is_editing_default_groups = true
    editing_default_groups = Utils.CopyTable(defaults.default_groups) or {}
    selected_default_group_idx = #editing_default_groups > 0 and 1 or 0
    reaper.ImGui_OpenPopup(ctx, "Edit Default Groups")
end

-- Draw the configuration tab UI
function TrackConfig.DrawConfigTab(ctx, ext_state_name, import_script)
    -- Get current configurations with inheritance applied
    local track_configs = TrackConfig.LoadTrackConfigs(ext_state_name, import_script)
    
    -- Get current inheritance mode
    local current_mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local mode_names = { "Use Defaults Only", "Use Defaults + Overrides", "Use Overrides Only" }
    
    reaper.ImGui_Text(ctx, "Current Track Configurations:")
    reaper.ImGui_Spacing(ctx)
    
    -- Inheritance mode combo
    reaper.ImGui_Text(ctx, "Group Inheritance:")
    local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##track_configs_mode", current_mode - 1, table.concat(mode_names, "\0") .. "\0", -1)
    if changed_mode then
        DefaultPatterns.SaveInheritanceMode(ext_state_name, "track_configs", new_mode + 1)
        -- Reload configurations with new inheritance mode
        track_configs = TrackConfig.LoadTrackConfigs(ext_state_name, import_script)
    end
    
    -- Help text based on inheritance mode
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using default groups only. Changes will not be saved.")
    elseif current_mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using defaults plus your overrides. New groups will be saved as overrides.")
    else -- OVERRIDE_ONLY
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, "Using only your overrides, ignoring defaults.")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Configuration management buttons
    -- Import/Export buttons will be handled by the main script
    
    -- Edit Default Groups button
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Edit Default Groups") then
        TrackConfig.BeginEditDefaultGroups(ctx)
    end
    
    -- Show the Edit Default Groups popup if active
    TrackConfig.ShowEditDefaultGroupsPopup(ctx)
    
    -- Add New Group button (only enabled if not in DEFAULT_ONLY mode)
    reaper.ImGui_SameLine(ctx)
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_BeginDisabled(ctx)
    end
    
    if reaper.ImGui_Button(ctx, "Add New Group") then
        editing_group = TrackConfig.CreateNewConfigGroup()
        is_editing_group = true
        reaper.ImGui_OpenPopup(ctx, "Edit Track Configuration")
    end
    
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    -- Show the Add/Edit Group popup if active
    TrackConfig.ShowAddEditGroupPopup(ctx, ext_state_name, track_configs, import_script)
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Configuration list with collapsible headers
    -- We'll avoid using custom fonts to prevent issues with different ReaImGui versions
    local font_used = false
    local font_mini = nil
    
    -- Skip font creation and pushing - it's causing errors
    --[[
    -- Try to create a mini font, but handle failure gracefully
    if reaper.ImGui_CreateFont then
        pcall(function()
            font_mini = reaper.ImGui_CreateFont("sans-serif", 11)
            if font_mini then
                reaper.ImGui_PushFont(ctx, font_mini)
                font_used = true
            end
        end)
    end
    ]]
    
    -- If no configurations are found
    if not track_configs or next(track_configs) == nil then
        reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No track configurations found. Import a configuration file or add a new group to get started.")
    else
        -- List all configurations
        reaper.ImGui_BeginChild(ctx, "##ConfigScroll", 0, -30, true)
        
        -- Get defaults for highlighting
        local defaults = DefaultPatterns.LoadDefaults().default_groups
        local default_groups = {}
        for _, group in ipairs(defaults) do
            default_groups[group.name] = true
        end
        
        for name, config in pairs(track_configs) do
            -- Determine if this is a default group
            local is_default = default_groups[name] or false
            
            -- Add a prefix for default groups
            local display_name = name
            if is_default then
                display_name = name .. " (Default)"
            end
            
            if reaper.ImGui_CollapsingHeader(ctx, display_name) then
                -- Edit and Delete buttons (disabled for default groups in DEFAULT_ONLY mode)
                reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - 80)
                
                if current_mode == INHERITANCE_MODES.DEFAULT_ONLY and is_default then
                    reaper.ImGui_BeginDisabled(ctx)
                end
                
                if reaper.ImGui_Button(ctx, "Edit##" .. name) then
                    editing_group = Utils.CopyTable(config)
                    editing_group.name = name
                    is_editing_group = true
                    reaper.ImGui_OpenPopup(ctx, "Edit Track Configuration")
                end
                
                reaper.ImGui_SameLine(ctx)
                
                -- Delete button (only for non-defaults or in OVERRIDE_ONLY mode)
                if reaper.ImGui_Button(ctx, "Delete##" .. name) then
                    if reaper.ShowMessageBox("Are you sure you want to delete the " .. name .. " configuration?", "Confirm Delete", 4) == 6 then
                        -- Get original configs without inheritance
                        local original_configs = import_script.LoadTrackConfigs() or {}
                        original_configs[name] = nil
                        import_script.SaveTrackConfigs(original_configs)
                        
                        -- Reload with inheritance
                        track_configs = TrackConfig.LoadTrackConfigs(ext_state_name, import_script)
                    end
                end
                
                if current_mode == INHERITANCE_MODES.DEFAULT_ONLY and is_default then
                    reaper.ImGui_EndDisabled(ctx)
                end
                
                -- Highlight default group information
                if is_default then
                    reaper.ImGui_TextColored(ctx, 0x88CC88FF, "This is a default group configuration")
                end
                
                -- Track info
                reaper.ImGui_Text(ctx, "Parent Track: " .. (config.parent_track or "None"))
                if config.parent_track_guid and config.parent_track_guid ~= "" then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, 0x88CC88FF, "(GUID Available)")
                end
                
                reaper.ImGui_Text(ctx, "Destination Track: " .. (config.destination_track or config.default_track or "None"))
                if config.destination_track_guid and config.destination_track_guid ~= "" then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, 0x88CC88FF, "(GUID Available)")
                end
                
                reaper.ImGui_Text(ctx, "Insert Mode: " .. (config.insert_mode or "None"))
                
                if config.insert_mode == "increment" then
                    reaper.ImGui_Text(ctx, "Increment Start: " .. (config.increment_start or "1"))
                    reaper.ImGui_Text(ctx, "Only Number When Multiple: " .. (config.only_number_when_multiple and "Yes" or "No"))
                end
                
                -- Patterns
                if config.patterns and #config.patterns > 0 then
                    if reaper.ImGui_TreeNode(ctx, "Match Patterns") then
                        for i, pattern in ipairs(config.patterns) do
                            reaper.ImGui_BulletText(ctx, pattern)
                        end
                        reaper.ImGui_TreePop(ctx)
                    end
                end
                
                -- Negative patterns
                if config.negative_patterns and #config.negative_patterns > 0 then
                    if reaper.ImGui_TreeNode(ctx, "Negative Patterns") then
                        for i, pattern in ipairs(config.negative_patterns) do
                            reaper.ImGui_BulletText(ctx, pattern)
                        end
                        reaper.ImGui_TreePop(ctx)
                    end
                end
                
                -- Pattern categories (only Prefix and Type)
                if config.pattern_categories then
                    if config.pattern_categories.prefix and config.pattern_categories.prefix.patterns and #config.pattern_categories.prefix.patterns > 0 then
                        if reaper.ImGui_TreeNode(ctx, "Prefix Patterns") then
                            reaper.ImGui_Text(ctx, "Required: " .. (config.pattern_categories.prefix.required and "Yes" or "No"))
                            for j, pattern in ipairs(config.pattern_categories.prefix.patterns) do
                                reaper.ImGui_BulletText(ctx, pattern)
                            end
                            reaper.ImGui_TreePop(ctx)
                        end
                    end
                    
                    if config.pattern_categories.type and config.pattern_categories.type.patterns and #config.pattern_categories.type.patterns > 0 then
                        if reaper.ImGui_TreeNode(ctx, "Type Patterns") then
                            reaper.ImGui_Text(ctx, "Required: " .. (config.pattern_categories.type.required and "Yes" or "No"))
                            for j, pattern in ipairs(config.pattern_categories.type.patterns) do
                                reaper.ImGui_BulletText(ctx, pattern)
                            end
                            reaper.ImGui_TreePop(ctx)
                        end
                    end
                end
                
                -- Other properties
                if reaper.ImGui_TreeNode(ctx, "Additional Properties") then
                    reaper.ImGui_Text(ctx, "Create If Missing: " .. (config.create_if_missing and "Yes" or "No"))
                    reaper.ImGui_TreePop(ctx)
                end
                
                -- Add Rename Track checkbox
                local changed_rename, value_rename = reaper.ImGui_Checkbox(ctx, "Rename track based on item patterns", config.rename_track)
                if changed_rename then
                    config.rename_track = value_rename
                    config_changed = true
                end
                Utils.CreateTooltip(ctx, "When enabled, destination tracks will include pattern categories found in item names (like layers, performer, etc.)")
            end
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    -- Remove the PopFont call since we commented out the PushFont
    --[[
    if font_used then
        reaper.ImGui_PopFont(ctx)
    end
    ]]
    
    -- Note about editing
    reaper.ImGui_Spacing(ctx)
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_TextWrapped(ctx, "In \"Use Defaults Only\" mode, you cannot modify configurations. Switch to another mode to make changes.")
    else
        reaper.ImGui_TextWrapped(ctx, "Configure track patterns and naming rules using the buttons above. You can also import/export configurations as JSON files.")
    end
end

-- Show the Edit Default Groups popup
function TrackConfig.ShowEditDefaultGroupsPopup(ctx)
    if not is_editing_default_groups then return end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    
    if reaper.ImGui_BeginPopupModal(ctx, "Edit Default Groups", true, popup_flags) then
        reaper.ImGui_Text(ctx, "Edit the default groups")
        reaper.ImGui_Spacing(ctx)
        
        -- List of default groups
        reaper.ImGui_Text(ctx, "Default Groups:")
        
        if #editing_default_groups > 0 then
            -- Group selection list
            if reaper.ImGui_BeginListBox(ctx, "##default_groups_list", 300, 200) then
                for i, group in ipairs(editing_default_groups) do
                    local selected = i == selected_default_group_idx
                    local clicked, selected_new = reaper.ImGui_Selectable(ctx, group.name, selected)
                    
                    if clicked then
                        selected_default_group_idx = i
                    end
                end
                reaper.ImGui_EndListBox(ctx)
            end
            
            -- Add/Remove buttons
            if reaper.ImGui_Button(ctx, "Add New Group") then
                table.insert(editing_default_groups, {
                    name = "New Group " .. (#editing_default_groups + 1),
                    patterns = {},
                    parent_track = "",
                    destination_track = "New Group " .. (#editing_default_groups + 1),
                    insert_mode = "increment",
                    increment_start = 1,
                    only_number_when_multiple = true,
                    pattern_categories = {
                        prefix = { patterns = {} },
                        type = { patterns = {} }
                    }
                })
                selected_default_group_idx = #editing_default_groups
            end
            
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Remove Selected") and selected_default_group_idx > 0 then
                table.remove(editing_default_groups, selected_default_group_idx)
                if selected_default_group_idx > #editing_default_groups then
                    selected_default_group_idx = #editing_default_groups
                end
            end
            
            -- Edit selected group
            if selected_default_group_idx > 0 and selected_default_group_idx <= #editing_default_groups then
                local group = editing_default_groups[selected_default_group_idx]
                
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Text(ctx, "Edit Group: " .. group.name)
                reaper.ImGui_Spacing(ctx)
                
                -- Group name
                local changed_name, new_name = reaper.ImGui_InputText(ctx, "Group Name", group.name, 256)
                if changed_name then
                    group.name = new_name
                end
                
                -- Parent track
                local changed_parent, new_parent = reaper.ImGui_InputText(ctx, "Parent Track", group.parent_track or "", 256)
                if changed_parent then
                    group.parent_track = new_parent
                end
                
                -- Insert mode
                local modes = {"increment", "single"}
                local current_mode = 1
                for i, mode in ipairs(modes) do
                    if mode == group.insert_mode then
                        current_mode = i
                        break
                    end
                end
                
                local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "Insert Mode", current_mode - 1, table.concat(modes, "\0") .. "\0", -1)
                if changed_mode then
                    group.insert_mode = modes[new_mode + 1]
                end
                
                -- Increment settings
                if group.insert_mode == "increment" then
                    local changed_inc, new_inc = reaper.ImGui_InputInt(ctx, "Increment Start", group.increment_start or 1, 1)
                    if changed_inc then
                        group.increment_start = math.max(1, new_inc)
                    end
                    
                    local changed_onm, new_onm = reaper.ImGui_Checkbox(ctx, "Only Number When Multiple", group.only_number_when_multiple)
                    if changed_onm then
                        group.only_number_when_multiple = new_onm
                    end
                end
                
                -- Match patterns
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Text(ctx, "Match Patterns")
                reaper.ImGui_TextWrapped(ctx, "Add patterns that identify this type of track (e.g., 'kick', 'snare')")
                
                -- New pattern input for match patterns
                local new_pattern = ""
                local changed_pattern, value_pattern = reaper.ImGui_InputText(ctx, "New Pattern##main", new_pattern, 256)
                if changed_pattern then
                    new_pattern = value_pattern
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##mainpattern") and new_pattern ~= "" then
                    table.insert(group.patterns, new_pattern)
                    new_pattern = ""
                end
                
                -- List of match patterns
                if #group.patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##patternlist", 300, 100) then
                        for j, pattern in ipairs(group.patterns) do
                            local selected = false
                            local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##" .. j, selected)
                            
                            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                reaper.ImGui_OpenPopup(ctx, "patternContextMenu" .. j)
                            end
                            
                            if reaper.ImGui_BeginPopup(ctx, "patternContextMenu" .. j) then
                                if reaper.ImGui_MenuItem(ctx, "Delete") then
                                    table.remove(group.patterns, j)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndListBox(ctx)
                    end
                else
                    reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No patterns defined")
                end
            end
        else
            reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No default groups defined")
            
            if reaper.ImGui_Button(ctx, "Add First Group") then
                table.insert(editing_default_groups, {
                    name = "New Group",
                    patterns = {},
                    parent_track = "",
                    destination_track = "New Group",
                    insert_mode = "increment",
                    increment_start = 1,
                    only_number_when_multiple = true,
                    pattern_categories = {
                        prefix = { patterns = {} },
                        type = { patterns = {} }
                    }
                })
                selected_default_group_idx = 1
            end
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- Buttons for save/cancel
        local button_width = 120
        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SetCursorPosX(ctx, (window_width - (button_width * 2 + 10)) / 2)
        
        if reaper.ImGui_Button(ctx, "Save Changes", button_width, 0) then
            -- Save the edited defaults
            local defaults = DefaultPatterns.LoadDefaults()
            defaults.default_groups = editing_default_groups
            DefaultPatterns.SaveDefaults(defaults)
            
            is_editing_default_groups = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Cancel", button_width, 0) then
            is_editing_default_groups = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- Show the Add/Edit Group popup for track configurations
function TrackConfig.ShowAddEditGroupPopup(ctx, ext_state_name, track_configs, import_script)
    if not is_editing_group then return end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    
    if reaper.ImGui_BeginPopupModal(ctx, "Edit Track Configuration", true, popup_flags) then
        -- Group name
        local changed_name, new_name = reaper.ImGui_InputText(ctx, "Group Name", editing_group.name, 256)
        if changed_name then
            editing_group.name = new_name
        end
        
        -- Track selection
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Track Selection")
        reaper.ImGui_Spacing(ctx)
        
        -- Parent track
        local changed_parent, new_parent = reaper.ImGui_InputText(ctx, "Parent Track", editing_group.parent_track or "", 256)
        if changed_parent then
            editing_group.parent_track = new_parent
        end
        
        -- Button to select currently selected track as parent
        if reaper.ImGui_Button(ctx, "Use Selected Track as Parent") then
            local guid, name = TrackConfig.GetSelectedTrackInfo()
            if guid and name then
                editing_group.parent_track = name
                editing_group.parent_track_guid = guid
            end
        end
        
        -- Destination track
        local changed_dest, new_dest = reaper.ImGui_InputText(ctx, "Destination Track", editing_group.destination_track or editing_group.default_track or "", 256)
        if changed_dest then
            editing_group.destination_track = new_dest
            -- For backward compatibility, also update default_track
            editing_group.default_track = new_dest
        end
        
        -- Button to select currently selected track as destination
        if reaper.ImGui_Button(ctx, "Use Selected Track as Destination") then
            local guid, name = TrackConfig.GetSelectedTrackInfo()
            if guid and name then
                editing_group.destination_track = name
                editing_group.destination_track_guid = guid
            end
        end
        
        -- Insert mode settings
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Insert Mode Settings")
        reaper.ImGui_Spacing(ctx)
        
        -- Insert mode combo
        local modes = {"increment", "single"}
        local current_mode = 1
        for i, mode in ipairs(modes) do
            if mode == editing_group.insert_mode then
                current_mode = i
                break
            end
        end
        
        local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "Insert Mode", current_mode - 1, table.concat(modes, "\0") .. "\0", -1)
        if changed_mode then
            editing_group.insert_mode = modes[new_mode + 1]
        end
        
        -- Increment settings if using increment mode
        if editing_group.insert_mode == "increment" then
            local changed_inc, new_inc = reaper.ImGui_InputInt(ctx, "Increment Start", editing_group.increment_start or 1, 1)
            if changed_inc then
                editing_group.increment_start = math.max(1, new_inc)
            end
            
            local changed_onm, new_onm = reaper.ImGui_Checkbox(ctx, "Only Number When Multiple", editing_group.only_number_when_multiple)
            if changed_onm then
                editing_group.only_number_when_multiple = new_onm
            end
        end
        
        -- Create if missing checkbox
        local changed_create, new_create = reaper.ImGui_Checkbox(ctx, "Create Track If Missing", editing_group.create_if_missing)
        if changed_create then
            editing_group.create_if_missing = new_create
        end
        
        -- Pattern matching
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Pattern Matching")
        reaper.ImGui_Spacing(ctx)
        
        -- Main patterns section
        if reaper.ImGui_CollapsingHeader(ctx, "Main Patterns", true) then
            reaper.ImGui_TextWrapped(ctx, "Add patterns that identify this type of track (e.g., 'kick', 'snare')")
            
            -- New pattern input
            local new_pattern = ""
            local changed_pattern, value_pattern = reaper.ImGui_InputText(ctx, "New Pattern##main", new_pattern, 256)
            if changed_pattern then
                new_pattern = value_pattern
            end
            
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Add##mainpattern") and new_pattern ~= "" then
                table.insert(editing_group.patterns, new_pattern)
                new_pattern = ""
            end
            
            -- List of patterns
            if #editing_group.patterns > 0 then
                if reaper.ImGui_BeginListBox(ctx, "##patternlist", 300, 100) then
                    for j, pattern in ipairs(editing_group.patterns) do
                        local selected = false
                        local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##" .. j, selected)
                        
                        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                            reaper.ImGui_OpenPopup(ctx, "patternContextMenu" .. j)
                        end
                        
                        if reaper.ImGui_BeginPopup(ctx, "patternContextMenu" .. j) then
                            if reaper.ImGui_MenuItem(ctx, "Delete") then
                                table.remove(editing_group.patterns, j)
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                    end
                    reaper.ImGui_EndListBox(ctx)
                end
            else
                reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No patterns defined")
            end
        end
        
        -- Negative patterns section
        if reaper.ImGui_CollapsingHeader(ctx, "Negative Patterns", true) then
            reaper.ImGui_TextWrapped(ctx, "Add patterns that should exclude a file from this group (e.g., 'bass' to exclude from 'guitars')")
            
            -- New negative pattern input
            local new_neg_pattern = ""
            local changed_neg_pattern, value_neg_pattern = reaper.ImGui_InputText(ctx, "New Pattern##neg", new_neg_pattern, 256)
            if changed_neg_pattern then
                new_neg_pattern = value_neg_pattern
            end
            
            reaper.ImGui_SameLine(ctx)
            
            if reaper.ImGui_Button(ctx, "Add##negpattern") and new_neg_pattern ~= "" then
                table.insert(editing_group.negative_patterns, new_neg_pattern)
                new_neg_pattern = ""
            end
            
            -- List of negative patterns
            if #editing_group.negative_patterns > 0 then
                if reaper.ImGui_BeginListBox(ctx, "##negpatternlist", 300, 100) then
                    for j, pattern in ipairs(editing_group.negative_patterns) do
                        local selected = false
                        local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##neg" .. j, selected)
                        
                        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                            reaper.ImGui_OpenPopup(ctx, "negpatternContextMenu" .. j)
                        end
                        
                        if reaper.ImGui_BeginPopup(ctx, "negpatternContextMenu" .. j) then
                            if reaper.ImGui_MenuItem(ctx, "Delete") then
                                table.remove(editing_group.negative_patterns, j)
                            end
                            reaper.ImGui_EndPopup(ctx)
                        end
                    end
                    reaper.ImGui_EndListBox(ctx)
                end
            else
                reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No negative patterns defined")
            end
        end
        
        -- Pattern categories section
        if reaper.ImGui_CollapsingHeader(ctx, "Pattern Categories", true) then
            reaper.ImGui_TextWrapped(ctx, "Configure prefix and type patterns for track naming")
            
            -- Prefix patterns
            if reaper.ImGui_TreeNode(ctx, "Prefix Patterns") then
                reaper.ImGui_TextWrapped(ctx, "These patterns will be used as prefixes in track names (e.g., 'Drum', 'Gtr')")
                
                -- Ensure prefix category exists
                if not editing_group.pattern_categories then
                    editing_group.pattern_categories = {}
                end
                if not editing_group.pattern_categories.prefix then
                    editing_group.pattern_categories.prefix = { patterns = {}, required = false }
                end
                
                -- Required checkbox
                local changed_req, new_req = reaper.ImGui_Checkbox(ctx, "Required##prefix", editing_group.pattern_categories.prefix.required)
                if changed_req then
                    editing_group.pattern_categories.prefix.required = new_req
                end
                
                -- New prefix pattern input
                local new_prefix = ""
                local changed_prefix, value_prefix = reaper.ImGui_InputText(ctx, "New Prefix##prefix", new_prefix, 256)
                if changed_prefix then
                    new_prefix = value_prefix
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##prefixpattern") and new_prefix ~= "" then
                    table.insert(editing_group.pattern_categories.prefix.patterns, new_prefix)
                    new_prefix = ""
                end
                
                -- List of prefix patterns
                local prefix_patterns = editing_group.pattern_categories.prefix.patterns
                if #prefix_patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##prefixlist", 300, 100) then
                        for j, pattern in ipairs(prefix_patterns) do
                            local selected = false
                            local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##prefix" .. j, selected)
                            
                            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                reaper.ImGui_OpenPopup(ctx, "prefixContextMenu" .. j)
                            end
                            
                            if reaper.ImGui_BeginPopup(ctx, "prefixContextMenu" .. j) then
                                if reaper.ImGui_MenuItem(ctx, "Delete") then
                                    table.remove(editing_group.pattern_categories.prefix.patterns, j)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndListBox(ctx)
                    end
                else
                    reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No prefix patterns defined")
                end
                
                reaper.ImGui_TreePop(ctx)
            end
            
            -- Type patterns
            if reaper.ImGui_TreeNode(ctx, "Type Patterns") then
                reaper.ImGui_TextWrapped(ctx, "These patterns will be used as type indicators in track names (e.g., 'MIDI', 'VOX')")
                
                -- Ensure type category exists
                if not editing_group.pattern_categories then
                    editing_group.pattern_categories = {}
                end
                if not editing_group.pattern_categories.type then
                    editing_group.pattern_categories.type = { patterns = {}, required = false }
                end
                
                -- Required checkbox
                local changed_req, new_req = reaper.ImGui_Checkbox(ctx, "Required##type", editing_group.pattern_categories.type.required)
                if changed_req then
                    editing_group.pattern_categories.type.required = new_req
                end
                
                -- New type pattern input
                local new_type = ""
                local changed_type, value_type = reaper.ImGui_InputText(ctx, "New Type##type", new_type, 256)
                if changed_type then
                    new_type = value_type
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##typepattern") and new_type ~= "" then
                    table.insert(editing_group.pattern_categories.type.patterns, new_type)
                    new_type = ""
                end
                
                -- List of type patterns
                local type_patterns = editing_group.pattern_categories.type.patterns
                if #type_patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##typelist", 300, 100) then
                        for j, pattern in ipairs(type_patterns) do
                            local selected = false
                            local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##type" .. j, selected)
                            
                            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                reaper.ImGui_OpenPopup(ctx, "typeContextMenu" .. j)
                            end
                            
                            if reaper.ImGui_BeginPopup(ctx, "typeContextMenu" .. j) then
                                if reaper.ImGui_MenuItem(ctx, "Delete") then
                                    table.remove(editing_group.pattern_categories.type.patterns, j)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndListBox(ctx)
                    end
                else
                    reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No type patterns defined")
                end
                
                reaper.ImGui_TreePop(ctx)
            end
        end
        
        -- Buttons for save/cancel
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        local button_width = 120
        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SetCursorPosX(ctx, (window_width - (button_width * 2 + 10)) / 2)
        
        if reaper.ImGui_Button(ctx, "Save Changes", button_width, 0) then
            -- Ensure we have a valid name
            if editing_group.name == "" then
                reaper.ShowMessageBox("Group name cannot be empty.", "Error", 0)
            else
                -- Save the group configuration
                local current_mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
                if current_mode ~= INHERITANCE_MODES.DEFAULT_ONLY then
                    local configs = import_script.LoadTrackConfigs()
                    configs[editing_group.name] = editing_group
                    import_script.SaveTrackConfigs(configs)
                end
                
                is_editing_group = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Cancel", button_width, 0) then
            is_editing_group = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

return TrackConfig 