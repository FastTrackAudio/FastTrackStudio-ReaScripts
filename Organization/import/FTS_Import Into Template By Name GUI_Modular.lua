--[[
 * ReaScript Name: FastTrackStudio - Import Into Template By Name GUI (Modular)
 * Description: Configure and manage track templates for importing files into tracks based on naming patterns
 * Instructions: Run the script to open the configuration GUI
 * Author: Cody Hanson / FastTrackStudio
 * Licence: GPL v3
 * REAPER: 6.0+
 * Extensions: SWS/S&M 2.12.1 (optional, provides additional features)
 * Version: 2.0.0
--]]

--[[
 * Changelog:
 * v2.0.0 (2023-07-01)
   + Complete refactoring into modules for better maintainability
   + Added Global Patterns tab for project-wide pattern categories
   + Improved inheritance system for defaults and user overrides
   + Added parent track and template track selection via GUID
   + Better track name generation with prefix and type support
   + Conditional numbering for tracks with only_number_when_multiple option
 * v1.0.0 (2023-05-01)
   + Initial release
--]]

-- Get the script path for loading dependencies
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local dir_path = script_path:match("(.*[/\\])") or ""
local root_path = dir_path:match("(.*[/\\])Organization[/\\].*[/\\]") or ""
if not root_path then
    root_path = dir_path:match("(.*[/\\]).*[/\\].*[/\\]") or ""
end

-- Check if modules directory exists, if not create it
local modules_path = dir_path .. "modules/"
local modules_dir = io.open(modules_path)
if not modules_dir then
    reaper.RecursiveCreateDirectory(modules_path, 0)
else
    modules_dir:close()
end

-- Add modules path to package.path
package.path = package.path .. ";" .. modules_path .. "?.lua"

-- Load required libraries
-- Import json module explicitly
local ok, json = pcall(dofile, root_path .. "libraries/utils/json.lua")
if not ok or not json then
    -- Create a basic json implementation if loading fails
    json = {
        encode = function(data)
            -- Basic implementation for simple tables
            if type(data) ~= "table" then return tostring(data) end
            local result = "{"
            for k, v in pairs(data) do
                local key = type(k) == "number" and k or '"' .. tostring(k) .. '"'
                local value
                if type(v) == "table" then
                    value = json.encode(v)
                elseif type(v) == "string" then
                    value = '"' .. v .. '"'
                else
                    value = tostring(v)
                end
                result = result .. key .. ":" .. value .. ","
            end
            result = result .. "}"
            return result
        end,
        decode = function(data)
            -- Return empty table on error (simplified fallback)
            return {}
        end
    }
end

-- Load PatternMatching module
local PatternMatching = dofile(reaper.GetResourcePath() .. "/Scripts/FastTrackStudio Scripts/libraries/utils/Pattern Matching.lua")
if not PatternMatching then
    -- Create a basic PatternMatching implementation if loading fails
    PatternMatching = {
        MatchesAnyPattern = function(str, patterns)
            if not str or not patterns then return false, nil end
            for _, pattern in ipairs(patterns) do
                if str:match(pattern) then
                    return true, pattern
                end
            end
            return false, nil
        end,
        MatchesNegativePattern = function(str, patterns)
            if not str or not patterns then return false end
            for _, pattern in ipairs(patterns) do
                if str:match(pattern) then
                    return true
                end
            end
            return false
        end
    }
end

-- Load TrackConfig module
local TrackConfig = require("track_config")
if not TrackConfig then
    -- Create a basic TrackConfig implementation if loading fails
    TrackConfig = {
        FindTrackByGUIDWithFallback = function(guid, name)
            -- Try to find track by GUID first
            if guid and guid ~= "" then
                local track = reaper.BR_GetMediaTrackByGUID(0, guid)
                if track then
                    return track
                end
            end
            
            -- If no GUID or not found by GUID, try by name
            if name and name ~= "" then
                local track_count = reaper.CountTracks(0)
                for i = 0, track_count - 1 do
                    local track = reaper.GetTrack(0, i)
                    local _, track_name = reaper.GetTrackName(track)
                    
                    if track_name == name then
                        return track
                    end
                end
            end
            
            return nil
        end
    }
end

-- Load TrackManagement module
local TrackManagement = require("track_management")
if not TrackManagement then
    -- Create a basic TrackManagement implementation if loading fails
    TrackManagement = {
        FindOrCreateTrack = function(track_name, template_track, parent_track, ensure_visible)
            -- Try to find existing track by name
            local track_count = reaper.CountTracks(0)
            for i = 0, track_count - 1 do
                local track = reaper.GetTrack(0, i)
                local _, existing_name = reaper.GetTrackName(track)
                
                if existing_name == track_name then
                    return track
                end
            end
            
            -- If not found, create a new track
            local new_track = reaper.InsertTrackAtIndex(track_count, true)
            if new_track then
                -- Set the track name
                reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
                
                -- If parent track is provided, set it as a child
                if parent_track then
                    -- Set the track as a child of the parent
                    reaper.SetMediaTrackInfo_Value(new_track, "P_PARTRACK", parent_track)
                end
                
                -- Ensure track is visible in TCP and mixer
                if ensure_visible then
                    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)
                    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)
                end
                
                return new_track
            end
            
            return nil
        end
    }
end

-- Add ImGui compatibility for different versions
if reaper.ImGui_CreateContext then
    -- Check if we can load the official compatibility layer
    if reaper.GetResourcePath and reaper.file_exists(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua") then
        dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.7.2")
    end
    
    -- Check for missing ImGui functions and add fallbacks
    if not reaper.ImGui_BeginTabBar then
        reaper.ImGui_BeginTabBar = function(ctx, name)
            reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "Tab Bar (Compatibility Mode)")
            reaper.ImGui_Separator(ctx)
            return true
        end
    end
    
    if not reaper.ImGui_EndTabBar then
        reaper.ImGui_EndTabBar = function(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
        end
    end
else
    -- Show error if ImGui is completely unavailable
    reaper.ShowMessageBox("This script requires ReaImGui to work. Please install ReaImGui from ReaPack.", "Missing Dependency", 0)
    return
end

-- #region Import Script Interface
-- These functions provide an interface to the original script functionality
-- They will be passed to the modules to allow them to interact with the core functionality

local ImportScript = {
    DebugMode = false,
    LastMessage = "",
    LastMessageTime = os.time(),
    LogMessages = {}, -- Array to store log messages
    MaxLogs = 500, -- Maximum number of log messages to keep
}

-- Debug output function
function ImportScript.DebugPrint(message)
    if ImportScript.DebugMode then
        reaper.ShowConsoleMsg(message .. "\n")
        -- Also add to logs without timestamp/category to avoid duplication
        table.insert(ImportScript.LogMessages, 1, message)
        
        -- Limit log size
        if #ImportScript.LogMessages > ImportScript.MaxLogs then
            table.remove(ImportScript.LogMessages)
        end
    end
end

-- Helper function to get table keys as a list
function GetTableKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

-- Helper function to get table size (number of keys)
function ImportScript.GetTableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Constants for inheritance modes
local INHERITANCE_MODES = {
    DEFAULT_ONLY = 1,
    DEFAULT_PLUS_OVERRIDE = 2,
    OVERRIDE_ONLY = 3
}

-- Load defaults from the defaults.json file
function ImportScript.LoadDefaultGroups()
    local root_path = script_path:match("(.*[/\\])Organization[/\\].*[/\\]") or ""
    if not root_path then
        root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]") or ""
    end
    
    local defaults_path = root_path .. "Organization/import/defaults.json"
    
    -- Debug output - only log once per session
    if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
        ImportScript.DefaultGroupsLogged = true
        reaper.ShowConsoleMsg("\n=== DEBUG: LoadDefaultGroups ===\n")
        reaper.ShowConsoleMsg("Loading from: " .. defaults_path .. "\n")
    end
    
    local file = io.open(defaults_path, "r")
    
    if not file then
        if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
            reaper.ShowConsoleMsg("ERROR: Could not open defaults.json file!\n")
            reaper.ShowConsoleMsg("=== END DEBUG: LoadDefaultGroups ===\n\n")
        end
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
        reaper.ShowConsoleMsg("File content length: " .. content:len() .. " characters\n")
    end
    
    local success, defaults = pcall(function() return json.decode(content) end)
    if not success or not defaults then
        if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
            reaper.ShowConsoleMsg("ERROR: Failed to parse defaults.json file! Using empty defaults.\n")
            reaper.ShowConsoleMsg("Parse error: " .. tostring(defaults) .. "\n")
            reaper.ShowConsoleMsg("=== END DEBUG: LoadDefaultGroups ===\n\n")
        end
        return {}
    end
    
    -- Convert array of default groups to a name-indexed table
    local default_groups = {}
    
    if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
        reaper.ShowConsoleMsg("Parsed defaults structure:\n")
        reaper.ShowConsoleMsg("  Has default_groups: " .. tostring(defaults.default_groups ~= nil) .. "\n")
        if defaults.default_groups then
            reaper.ShowConsoleMsg("  Number of default groups: " .. #defaults.default_groups .. "\n")
        end
    end
    
    if defaults.default_groups then
        for idx, group in ipairs(defaults.default_groups) do
            if group.name then
                default_groups[group.name] = group
                
                if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
                    reaper.ShowConsoleMsg("  Loaded group #" .. idx .. ": " .. group.name .. "\n")
                    reaper.ShowConsoleMsg("    Patterns: " .. table.concat(group.patterns or {}, ", ") .. "\n")
                    reaper.ShowConsoleMsg("    Parent track: " .. (group.parent_track or "none") .. "\n")
                    reaper.ShowConsoleMsg("    Destination track: " .. (group.destination_track or "none") .. "\n")
                end
            elseif ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
                reaper.ShowConsoleMsg("  WARNING: Group #" .. idx .. " has no name, skipping!\n")
            end
        end
    end
    
    if ImportScript.DebugMode and not ImportScript.DefaultGroupsLogged then
        reaper.ShowConsoleMsg("Final default groups count: " .. ImportScript.GetTableSize(default_groups) .. "\n")
        reaper.ShowConsoleMsg("=== END DEBUG: LoadDefaultGroups ===\n\n")
    end
    
    return default_groups
end

-- Load inheritance mode preference
function ImportScript.LoadInheritanceMode(key, default_mode)
    local mode = tonumber(reaper.GetExtState("FastTrackStudio_ImportByName", key .. "_inheritance_mode"))
    if not mode or mode < 1 or mode > 3 then
        return default_mode or INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE
    end
    return mode
end

-- Load track configurations from ExtState
function ImportScript.LoadTrackConfigs()
    -- Get user-defined track configs
    local configs_json = reaper.GetExtState("FastTrackStudio_ImportByName", "track_configs")
    local user_configs = {}
    
    if configs_json ~= "" then
        local ok, parsed = pcall(json.decode, configs_json)
        if ok and parsed then
            user_configs = parsed
        end
    end
    
    -- Determine inheritance mode
    local mode = ImportScript.LoadInheritanceMode("track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    
    -- Load default groups from defaults.json
    local default_groups = ImportScript.LoadDefaultGroups()
    
    -- Debug output for troubleshooting - only log once per session
    if ImportScript.DebugMode and not ImportScript.DebugLogged then
        ImportScript.DebugLogged = true
        reaper.ShowConsoleMsg("\n=== DEBUG: LoadTrackConfigs ===\n")
        reaper.ShowConsoleMsg("Inheritance mode: " .. mode .. "\n")
        
        -- Show default groups info
        reaper.ShowConsoleMsg("Default groups from defaults.json:\n")
        for name, config in pairs(default_groups) do
            reaper.ShowConsoleMsg("  Group: " .. name .. " (Patterns: " .. table.concat(config.patterns or {}, ", ") .. ")\n")
        end
        
        -- Show user configs info
        reaper.ShowConsoleMsg("User configurations from ExtState:\n")
        for name, config in pairs(user_configs) do
            reaper.ShowConsoleMsg("  Config: " .. name .. " (Patterns: " .. table.concat(config.patterns or {}, ", ") .. ")\n")
        end
    
        -- Show inheritance mode
        if mode == INHERITANCE_MODES.DEFAULT_ONLY then
            reaper.ShowConsoleMsg("Using DEFAULT_ONLY mode - only default configurations\n")
        elseif mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
            reaper.ShowConsoleMsg("Using DEFAULT_PLUS_OVERRIDE mode - defaults with user overrides\n")
        else -- INHERITANCE_MODES.OVERRIDE_ONLY
            reaper.ShowConsoleMsg("Using OVERRIDE_ONLY mode - only user configurations\n")
        end
    end
    
    -- Apply inheritance based on mode
    local result = {}
    
    if mode == INHERITANCE_MODES.DEFAULT_ONLY then
        -- Use only default configurations
        result = default_groups
    elseif mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        -- Combine defaults with user overrides
        -- Start with defaults
        for name, config in pairs(default_groups) do
            result[name] = config
        end
        
        -- Then apply user overrides, but preserve patterns if override has empty patterns
        for name, config in pairs(user_configs) do
            -- If this is a config that also exists in defaults
            if result[name] then
                -- Check if the override has an empty patterns array
                if not config.patterns or #config.patterns == 0 then
                    -- Keep the original patterns from defaults
                    local default_patterns = result[name].patterns
                    -- Apply the override
                    result[name] = config
                    -- Restore the patterns from defaults
                    result[name].patterns = default_patterns
                    
                    if ImportScript.DebugMode then
                        reaper.ShowConsoleMsg("  Preserving patterns for '" .. name .. "' from defaults\n")
                    end
                else
                    -- Override has valid patterns, use it completely
                    result[name] = config
                end
            else
                -- This is a new config that's not in defaults, just add it
                result[name] = config
            end
        end
    else -- INHERITANCE_MODES.OVERRIDE_ONLY
        -- Use only user configurations
        result = user_configs
    end
    
    -- Debug output final configurations - only log once
    if ImportScript.DebugMode and ImportScript.DebugLogged then
        reaper.ShowConsoleMsg("Final track configurations:\n")
        for name, config in pairs(result) do
            reaper.ShowConsoleMsg("  Final Config: " .. name .. " (Patterns: " .. table.concat(config.patterns or {}, ", ") .. ")\n")
        end
        reaper.ShowConsoleMsg("=== END DEBUG: LoadTrackConfigs ===\n\n")
    end
    
    return result
end

-- Save track configurations to ExtState
function ImportScript.SaveTrackConfigs(configs)
    if not configs then
        configs = {}
    end
    
    local ok, configs_json = pcall(json.encode, configs)
    if not ok or not configs_json then
        configs_json = "{}"
    end
    
    reaper.SetExtState("FastTrackStudio_ImportByName", "track_configs", configs_json, true)
end

-- Reset track configurations to remove user overrides
function ImportScript.ResetTrackConfigs()
    -- Clear the ExtState for track configurations
    reaper.DeleteExtState("FastTrackStudio_ImportByName", "track_configs", true)
    -- Reset the debug log flags to allow a fresh debug output
    ImportScript.DebugLogged = false
    ImportScript.DefaultGroupsLogged = false
    -- Show confirmation in debug console
    if ImportScript.DebugMode then
        reaper.ShowConsoleMsg("\n=== User configuration reset ===\n")
        reaper.ShowConsoleMsg("Track configurations have been reset to defaults.\n")
        reaper.ShowConsoleMsg("===============================\n\n")
    end
    -- Set status message
    ImportScript.LastMessage = "Track configurations have been reset to defaults"
    ImportScript.LastMessageTime = os.time()
    
    return ImportScript.LoadTrackConfigs() -- Return the fresh configs
end

-- Get the name prefix for a track
function ImportScript.GetTrackNamePrefix(track_cfg, global_patterns)
    -- Implementation simplified for modular version
    if track_cfg and track_cfg.pattern_categories and track_cfg.pattern_categories.prefix and 
       track_cfg.pattern_categories.prefix.patterns and #track_cfg.pattern_categories.prefix.patterns > 0 then
        return track_cfg.pattern_categories.prefix.patterns[1]
    elseif global_patterns and global_patterns.prefix and #global_patterns.prefix > 0 then
        return global_patterns.prefix[1]
    end
    return ""
end

-- Import from file
function ImportFromFile()
    -- Prevent UI refreshing during processing
    reaper.PreventUIRefresh(1)
    
    -- Log the start of the operation
    ImportScript.LogMessage("Starting import from file operation", "ORGANIZE")
    
    -- Get file path
    local file_path = reaper.GetProjectPath() .. "/import_files.txt"
    local retval, file_path = reaper.GetUserFileNameForRead("", "Select File List", ".txt")
    
    if not retval or file_path == "" then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing
        ImportScript.LogMessage("Operation cancelled: No file selected", "ERROR")
        return
    end
    
    ImportScript.LogMessage("Selected file: " .. file_path, "ORGANIZE")
    
    -- Read file
    local file = io.open(file_path, "r")
    if not file then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing
        reaper.ShowMessageBox("Could not open file: " .. file_path, "File Error", 0)
        ImportScript.LogMessage("Operation failed: Could not open file " .. file_path, "ERROR")
        return
    end
    
    -- Get available track configurations
    local track_configs = ImportScript.LoadTrackConfigs()
    
    if not track_configs or next(track_configs) == nil then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing
        reaper.ShowMessageBox("No track configurations found. Please create at least one configuration in the Track Configurations tab.", "No Configurations", 0)
        ImportScript.LogMessage("Operation failed: No track configurations found", "ERROR")
        file:close()
        return
    end
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Variables to track results
    local imported_count = 0
    local skipped_count = 0
    local file_exists_count = 0
    
    -- Import files
    ImportScript.LogMessage("Processing files from " .. file_path, "ORGANIZE")
    
    for line in file:lines() do
        line = line:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
        
        if line ~= "" and not line:match("^%s*#") then -- Skip empty lines and comments
            local file_path = line
            
            -- Handle relative paths
            if not file_path:match("^[A-Z]:[/\\]") and not file_path:match("^/") then
                file_path = reaper.GetProjectPath() .. "/" .. file_path
            end
            
            ImportScript.LogMessage("Processing file: " .. file_path, "ORGANIZE")
            
            -- Extract filename
            local file_name = file_path:match("([^/\\]+)$")
            
            if file_name then
                -- Find a matching track configuration
                local matched_config = nil
                local matched_name = nil
                local matched_pattern = nil
                
                for name, config in pairs(track_configs) do
                    if config.patterns and #config.patterns > 0 then
                        local matches, pattern = PatternMatching.MatchesAnyPattern(file_name, config.patterns)
                        if matches then
                            -- Check negative patterns
                            local negative_match = PatternMatching.MatchesNegativePattern(file_name, config.negative_patterns or {})
                            if not negative_match then
                                matched_config = config
                                matched_name = name
                                matched_pattern = pattern
                                ImportScript.LogMessage("File '" .. file_name .. "' matched config: '" .. name .. "' with pattern: '" .. pattern .. "'", "MATCH")
                                break
                            else
                                ImportScript.LogMessage("File '" .. file_name .. "' matched pattern but also matched negative pattern for config: '" .. name .. "'", "UNMATCH")
                            end
                        end
                    end
                end
                
                if matched_config then
                    -- Check if file exists
                    local file_info = io.open(file_path, "rb")
                    if file_info then
                        file_info:close()
                        
                        -- Get parent track
                        local parent_track = nil
                        if matched_config.parent_track_guid and matched_config.parent_track_guid ~= "" then
                            -- Try to find by GUID first
                            parent_track = reaper.BR_GetMediaTrackByGUID(0, matched_config.parent_track_guid)
                        end
                        
                        if not parent_track and matched_config.parent_track and matched_config.parent_track ~= "" then
                            -- If no GUID or not found by GUID, try by name
                            local track_count = reaper.CountTracks(0)
                            for i = 0, track_count - 1 do
                                local track = reaper.GetTrack(0, i)
                                local _, track_name = reaper.GetTrackName(track)
                                
                                if track_name == matched_config.parent_track then
                                    parent_track = track
                                    break
                                end
                            end
                        end
                        
                        if parent_track then
                            local _, parent_name = reaper.GetTrackName(parent_track)
                            ImportScript.LogMessage("Using parent track: '" .. parent_name .. "'", "TRACK")
                        else
                            ImportScript.LogMessage("No parent track found for config: '" .. matched_name .. "'", "TRACK")
                        end
                        
                        -- Determine destination track name (base name)
                        local base_track_name = matched_config.destination_track or matched_name
                        
                        -- Build full track name based on insert mode
                        local destination_track_name = base_track_name
                        
                        -- Import the file
                        local item_added = reaper.InsertMedia(file_path, 0) -- 0 = add to project (don't play)
                        
                        if item_added then
                            local item = reaper.GetSelectedMediaItem(0, 0) -- Get the newly inserted item
                            
                            if item then
                                -- Move the item to the appropriate track
                                local TrackManagement = require("track_management")
                                
                                -- Find or create track
                                local destination_track = TrackManagement.FindOrCreateTrack(destination_track_name, nil, parent_track, true)
                                
                                if destination_track then
                                    local track_idx = reaper.GetMediaTrackInfo_Value(destination_track, "IP_TRACKNUMBER")
                                    ImportScript.LogMessage("Using destination track: '" .. destination_track_name .. "' at position " .. track_idx, "TRACK")
                                    
                                    -- Move item to track
                                    reaper.MoveMediaItemToTrack(item, destination_track)
                                    
                                    -- Update take name if needed
                                    if matched_config.rename_takes then
                                        local take = reaper.GetActiveTake(item)
                                        if take then
                                            local new_name = PatternMatching.MatchesAnyPattern(file_name, matched_config.patterns)
                                            if new_name then
                                                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
                                                ImportScript.LogMessage("Renamed take to: '" .. new_name .. "'", "MOVE")
                                            end
                                        end
                                    end
                                    
                                    imported_count = imported_count + 1
                                    ImportScript.LogMessage("Imported file '" .. file_name .. "' to track '" .. destination_track_name .. "'", "MOVE")
                                else
                                    -- If track creation failed, delete the item
                                    reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
                                    skipped_count = skipped_count + 1
                                    ImportScript.LogMessage("Failed to create track for '" .. file_name .. "'", "ERROR")
                                end
                            else
                                skipped_count = skipped_count + 1
                                ImportScript.LogMessage("Failed to get inserted item for '" .. file_name .. "'", "ERROR")
                            end
                        else
                            skipped_count = skipped_count + 1
                            ImportScript.LogMessage("Failed to insert file '" .. file_name .. "'", "ERROR")
                        end
                    else
                        skipped_count = skipped_count + 1
                        file_exists_count = file_exists_count + 1
                        ImportScript.LogMessage("File not found: '" .. file_path .. "'", "ERROR")
                    end
                else
                    skipped_count = skipped_count + 1
                    ImportScript.LogMessage("No matching configuration for file: '" .. file_name .. "'", "UNMATCH")
                end
            else
                skipped_count = skipped_count + 1
                ImportScript.LogMessage("Invalid filename in line: '" .. line .. "'", "ERROR")
            end
        end
    end
    
    file:close()
    
    -- End undo block
    reaper.Undo_EndBlock("Import files", -1)
    
    -- Resume UI refreshing and update
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    
    -- Log summary
    local summary_message = string.format("Import complete: %d files imported, %d files skipped", imported_count, skipped_count)
    if file_exists_count > 0 then
        summary_message = summary_message .. string.format(" (%d files not found)", file_exists_count)
    end
    
    ImportScript.LogMessage(summary_message, "SUMMARY")
    
    -- Store message for display
    ImportScript.LastMessage = summary_message
    ImportScript.LastMessageTime = os.time()
end

-- Move selected items to a specific track
function MoveSelectedItems()
    -- Prevent UI refreshing during processing
    reaper.PreventUIRefresh(1)
    
    -- Log the start of the operation
    ImportScript.LogMessage("Starting move selected items operation", "ORGANIZE")
    
    -- Check if any items are selected
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing
        reaper.ShowMessageBox("No items selected. Please select items to move.", "No Items Selected", 0)
        ImportScript.LogMessage("Operation failed: No items selected", "ERROR")
        return
    end
    
    -- Get selected track or prompt to select a track
    local dest_track = reaper.GetSelectedTrack(0, 0)
    if not dest_track then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing
        reaper.ShowMessageBox("No track selected. Please select a destination track.", "No Track Selected", 0)
        ImportScript.LogMessage("Operation failed: No destination track selected", "ERROR")
        return
    end
    
    -- Get destination track name
    local _, track_name = reaper.GetTrackName(dest_track)
    ImportScript.LogMessage("Using destination track: '" .. track_name .. "'", "TRACK")
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Move selected items to the destination track
    local moved_count = 0
    local skipped_count = 0
    
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        local item_name = "Unknown"
        
        if take then
            _, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        end
        
        -- Get current track (to check if already on destination)
        local current_track = reaper.GetMediaItemTrack(item)
        if current_track == dest_track then
            ImportScript.LogMessage("Item '" .. item_name .. "' already on destination track", "SKIP")
            skipped_count = skipped_count + 1
        else
            -- Move the item
            if reaper.MoveMediaItemToTrack(item, dest_track) then
                ImportScript.LogMessage("Moved item '" .. item_name .. "' to track '" .. track_name .. "'", "MOVE")
                moved_count = moved_count + 1
            else
                ImportScript.LogMessage("Failed to move item '" .. item_name .. "'", "ERROR")
                skipped_count = skipped_count + 1
            end
        end
    end
    
    -- End undo block
    reaper.Undo_EndBlock("Move selected items", -1)
    
    -- Resume UI refreshing and update
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    
    -- Log summary
    local summary_message = string.format("Move complete: %d items moved, %d items skipped", moved_count, skipped_count)
    ImportScript.LogMessage(summary_message, "SUMMARY")
    
    -- Store message for display
    ImportScript.LastMessage = summary_message
    ImportScript.LastMessageTime = os.time()
end

-- First, add a helper function to extract pattern categories from item name
function ExtractPatternCategories(item_name, global_patterns, track_configs, matched_group, log_matches)
    local categories = {}
    
    -- Convert item name to lowercase for case-insensitive matching
    local item_name_lower = item_name:lower()
    
    -- Helper function to get patterns array depending on structure
    local function getPatterns(category)
        if not category then return {} end
        -- Handle both formats: array of patterns or object with patterns property
        if category.patterns then
            return category.patterns
        else
            return category
        end
    end
    
    -- Helper function to match pattern as a whole word or distinct word segment
    local function matchesAsWord(str, pattern)
        pattern = pattern:lower()
        
        -- Escape special pattern characters
        local escaped_pattern = pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        
        -- Look for word boundaries around the pattern:
        -- 1. At the start of string: ^pattern followed by space or punctuation
        -- 2. After space/punctuation: space/punct + pattern + space/punct
        -- 3. At the end of string: space/punct + pattern$
        -- 4. Exact match: ^pattern$
        local match_patterns = {
            "^" .. escaped_pattern .. "[%s%p]",           -- Start of string
            "[%s%p]" .. escaped_pattern .. "[%s%p]",      -- Middle of string
            "[%s%p]" .. escaped_pattern .. "$",           -- End of string
            "^" .. escaped_pattern .. "$"                 -- Exact match
        }
        
        for _, match_pattern in ipairs(match_patterns) do
            if str:match(match_pattern) then
                return true
            end
        end
        
        return false
    end
    
    -- Check each pattern category
    if global_patterns then
        -- Check for prefix
        local prefix_patterns = getPatterns(global_patterns.prefix)
        for _, pattern in ipairs(prefix_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.prefix = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected prefix pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for tracking info
        local tracking_patterns = getPatterns(global_patterns.tracking)
        for _, pattern in ipairs(tracking_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.tracking = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected tracking info pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for subtype - MODIFIED to use group-specific subtypes if available
        local subtype_patterns = {}
        
        -- If we have a matched group and it has defined subtypes, use those instead of global
        if matched_group and matched_group.subtypes and #matched_group.subtypes > 0 then
            subtype_patterns = matched_group.subtypes
            if log_matches then
                ImportScript.LogMessage("Using group-specific subtypes for '" .. matched_group.name .. "'", "PATTERN")
            end
        else
            -- Otherwise use global subtypes
            subtype_patterns = getPatterns(global_patterns.subtype)
        end
        
        for _, pattern in ipairs(subtype_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.subtype = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected subtype pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for arrangement
        local arrangement_patterns = getPatterns(global_patterns.arrangement)
        for _, pattern in ipairs(arrangement_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.arrangement = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected arrangement pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for performer
        local performer_patterns = getPatterns(global_patterns.performer)
        -- First check the full parentheses content directly
        local performer_in_parens = item_name:match("%(([^)]+)%)")
        if performer_in_parens then
            if log_matches then
                ImportScript.LogMessage("Found text in parentheses: '" .. performer_in_parens .. "'", "PATTERN")
            end
            
            -- Check if the content directly matches any performer pattern
            for _, pattern in ipairs(performer_patterns) do
                -- Direct match on the whole content or part of it - for performers we allow partial matches
                if performer_in_parens:lower():match(pattern:lower()) then
                    categories.performer = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected performer pattern: '" .. pattern .. "' in parentheses '" .. performer_in_parens .. "'", "PATTERN")
                    end
                    break
                end
            end
        end
        
        -- If no direct match, try the original method
        if not categories.performer then
            for _, pattern in ipairs(performer_patterns) do
                -- Check for performer in item name with traditional pattern
                if item_name_lower:match("%(.*" .. pattern:lower() .. ".*%)") then
                    categories.performer = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected performer pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                    end
                    break
                end
            end
        end
        
        -- Check for section
        local section_patterns = getPatterns(global_patterns.section)
        for _, pattern in ipairs(section_patterns) do
            -- Special handling for single-letter patterns like "A", "B", "C"
            if #pattern == 1 then
                -- Single characters need strict word boundaries
                local strict_patterns = {
                    "^" .. pattern:lower() .. "[%s%p]",         -- At start: "A " or "A,"
                    "[%s%p]" .. pattern:lower() .. "[%s%p]",    -- Middle: " A " or ",A,"
                    "[%s%p]" .. pattern:lower() .. "$",         -- At end: " A" or ",A"
                    "^" .. pattern:lower() .. "$"               -- Exact match: just "A"
                }
                
                local found = false
                for _, strict_pattern in ipairs(strict_patterns) do
                    if item_name_lower:match(strict_pattern) then
                        found = true
                        break
                    end
                end
                
                if found then
                    categories.section = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected section pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                    end
                    break
                end
            else
                -- For multi-character patterns, use the regular word matching
                if matchesAsWord(item_name_lower, pattern) then
                    categories.section = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected section pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                    end
                    break
                end
            end
        end
        
        -- Check for layers
        local layer_patterns = getPatterns(global_patterns.layers)
        for _, pattern in ipairs(layer_patterns) do
            -- Special handling for single-letter patterns like "L", "R"
            if #pattern == 1 then
                -- Single characters need strict word boundaries
                local strict_patterns = {
                    "^" .. pattern:lower() .. "[%s%p]",         -- At start: "L " or "L,"
                    "[%s%p]" .. pattern:lower() .. "[%s%p]",    -- Middle: " L " or ",L,"
                    "[%s%p]" .. pattern:lower() .. "$",         -- At end: " L" or ",L"
                    "^" .. pattern:lower() .. "$"               -- Exact match: just "L"
                }
                
                local found = false
                for _, strict_pattern in ipairs(strict_patterns) do
                    if item_name_lower:match(strict_pattern) then
                        found = true
                        break
                    end
                end
                
                if found then
                    categories.layers = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected layer pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                    end
                    break
                end
            else
                -- For multi-character patterns, use the regular word matching
                if matchesAsWord(item_name_lower, pattern) then
                    categories.layers = pattern
                    if log_matches then
                        ImportScript.LogMessage("Detected layer pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                    end
                    break
                end
            end
        end
        
        -- Check for mic
        local mic_patterns = getPatterns(global_patterns.mic)
        for _, pattern in ipairs(mic_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.mic = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected mic pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for playlist
        local playlist_patterns = getPatterns(global_patterns.playlist)
        for _, pattern in ipairs(playlist_patterns) do
            if matchesAsWord(item_name_lower, pattern) then
                categories.playlist = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected playlist pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
        
        -- Check for type
        local type_patterns = getPatterns(global_patterns.type)
        for _, pattern in ipairs(type_patterns) do
            -- For type patterns, we specifically look inside square brackets
            if item_name_lower:match("%[.*" .. pattern:lower() .. ".*%]") then
                categories.type = pattern
                if log_matches then
                    ImportScript.LogMessage("Detected type pattern: '" .. pattern .. "' in '" .. item_name .. "'", "PATTERN")
                end
                break
            end
        end
    end
    
    return categories
end

-- Then, add a function to generate a track name from pattern categories
function GenerateTrackNameFromCategories(base_name, categories)
    -- Start with base name
    local track_name = base_name
    
    -- Add categories in the user-specified order with proper formatting
    local name_parts = {}
    
    -- Start with the prefix (no special formatting)
    if categories.prefix then
        track_name = categories.prefix
    end
    
    -- Add tracking info in square brackets
    if categories.tracking then
        name_parts[#name_parts + 1] = "[" .. categories.tracking .. "]"
    end
    
    -- Add subtype
    if categories.subtype then
        name_parts[#name_parts + 1] = categories.subtype
    end
    
    -- Add arrangement
    if categories.arrangement then
        name_parts[#name_parts + 1] = categories.arrangement
    end
    
    -- Add performer in parentheses
    if categories.performer then
        name_parts[#name_parts + 1] = "(" .. categories.performer .. ")"
    end
    
    -- Add section
    if categories.section then
        name_parts[#name_parts + 1] = categories.section
    end
    
    -- Add layers
    if categories.layers then
        name_parts[#name_parts + 1] = categories.layers
    end
    
    -- Add mic
    if categories.mic then
        name_parts[#name_parts + 1] = categories.mic
    end
    
    -- Add playlist
    if categories.playlist then
        name_parts[#name_parts + 1] = categories.playlist
    end
    
    -- Add type in parentheses
    if categories.type then
        name_parts[#name_parts + 1] = "(" .. categories.type .. ")"
    end
    
    -- Build the track name by joining all parts with spaces
    if #name_parts > 0 then
        track_name = track_name .. " " .. table.concat(name_parts, " ")
    end
    
    return track_name
end

-- Very simple function to create a track right after the parent track
function EnsureTrackInFolder(track_name, parent_track)
    if not track_name or track_name == "" then
        reaper.ShowConsoleMsg("Error: Cannot create track with empty name\n")
        return nil
    end
    
    if not parent_track then
        reaper.ShowConsoleMsg("Error: No parent track provided\n")
        return nil
    end
    
    -- Store the user's original track selection
    local original_selected_tracks = {}
    local selected_track_count = reaper.CountSelectedTracks(0)
    for i = 0, selected_track_count - 1 do
        original_selected_tracks[i+1] = reaper.GetSelectedTrack(0, i)
    end
    
    -- Get parent track information
    local _, parent_name = reaper.GetTrackName(parent_track)
    reaper.ShowConsoleMsg("Creating track '" .. track_name .. "' after '" .. parent_name .. "'\n")
    
    -- Get the parent track's index (0-based) and depth
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local parent_depth = reaper.GetTrackDepth(parent_track)
    reaper.ShowConsoleMsg("Parent track index: " .. parent_idx .. ", depth: " .. parent_depth .. "\n")
    
    -- Find the end of this folder (last track inside the folder)
    local track_count = reaper.CountTracks(0)
    local insert_idx = parent_idx + 1 -- Start right after the parent
    local end_of_folder_idx = nil
    local last_folder_item_idx = parent_idx + 1 -- Initialize to first item after parent
    
    -- Move through tracks one by one until we find a track at parent_depth or lower
    -- This ensures we find the exact end of the folder
    for i = parent_idx + 1, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local current_depth = reaper.GetTrackDepth(track)
        
        if current_depth <= parent_depth then
            -- Found a track at same level or higher than parent - this is the end
            end_of_folder_idx = i
            break
        end
        
        -- Still in the folder
        last_folder_item_idx = i
        reaper.ShowConsoleMsg("  Track at index " .. i .. " has depth " .. current_depth .. " (still in folder)\n")
    end
    
    -- If we found the end of the folder, we want to insert at the last track inside the folder
    if end_of_folder_idx then
        -- We want to insert at the last item inside the folder
        insert_idx = last_folder_item_idx
        reaper.ShowConsoleMsg("Found end of folder at index: " .. end_of_folder_idx .. "\n")
        reaper.ShowConsoleMsg("Will insert at index: " .. insert_idx .. " (at last item in folder)\n")
    else
        -- If we didn't find an end, we're at the end of the project
        insert_idx = track_count
        reaper.ShowConsoleMsg("No end of folder found, will insert at the end of project\n")
    end
    
    -- Store reference to the original last track before we insert the new one
    local last_track = nil
    if insert_idx < track_count then
        last_track = reaper.GetTrack(0, insert_idx)
    end
    
    -- Create the track at the position of the last track in the folder
    reaper.InsertTrackAtIndex(insert_idx, false)
    local new_track = reaper.GetTrack(0, insert_idx)
    
    if not new_track then
        reaper.ShowConsoleMsg("Failed to create track\n")
        -- Restore original track selection
        reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
        for i, track in ipairs(original_selected_tracks) do
            reaper.SetTrackSelected(track, true)
        end
        return nil
    end
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    reaper.ShowConsoleMsg("Set track name: " .. track_name .. "\n")
    
    -- Ensure track is visible
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)
    reaper.ShowConsoleMsg("Set track visibility\n")
    
    -- If we have a reference to the last track that was pushed down, move it UP
    -- This puts our new track at the end of the folder
    if last_track then
        -- Unselect all tracks
        reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
        
        -- Select the last track that was pushed down
        reaper.SetTrackSelected(last_track, true)
        
        -- Move it UP one position (the ReorderSelectedTracks expects 1-based index)
        -- We want to move it to the position of our new track
        reaper.ReorderSelectedTracks(insert_idx, 0)
        reaper.ShowConsoleMsg("Moved the original last track UP - this puts our new track at the end of the folder\n")
    end
    
    -- Restore original track selection
    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
    for i, track in ipairs(original_selected_tracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- Log success
    ImportScript.LogMessage("Created track '" .. track_name .. "' in folder '" .. parent_name .. "'", "CREATE")
    
    return new_track
end

-- Update FindBestDestinationTrack to use our new function
function FindBestDestinationTrack(item_name, categories, config_tracks, group_parent_track, matched_group_name, track_configs)
    -- First, try to find an exact match in existing tracks
    local best_track = nil
    local best_track_info = nil
    local best_score = 0
    local should_use_lanes = false
    local should_duplicate_track = false
    local override_track = nil
    local subtype_parent_override = nil -- Will store parent track override for subtype
    
    -- Debug the match attempt
    ImportScript.DebugPrint("Looking for match for item '" .. item_name .. "', searching " .. #config_tracks .. " existing tracks")
    
    -- Get the available subtypes for this group, if any
    local subtypes = {}
    local matched_config = nil
    for name, config in pairs(track_configs) do
        if name == matched_group_name then
            matched_config = config
            if config.subtypes and #config.subtypes > 0 then
                subtypes = config.subtypes
                ImportScript.DebugPrint("  Found subtypes for group '" .. matched_group_name .. "': " .. table.concat(subtypes, ", "))
            end
            
            -- Check if this config has an override track for items without subtypes
            if config.default_override_track then
                override_track = config.default_override_track
                ImportScript.DebugPrint("  Found override track: '" .. override_track .. "' for items without subtypes")
            end
            break
        end
    end
    
    -- Detect which subtype(s) the item name contains
    local detected_subtypes = {}
    local item_name_lower = item_name:lower()
    
    -- Check for our new subtype tags in the format [GROUP-SUBTYPE]
    local tagged_group, tagged_subtype = item_name_lower:match("%[([%w]+)%-([%w%s]+)%]")
    if tagged_group and tagged_subtype then
        ImportScript.DebugPrint("  Found tagged subtype: '" .. tagged_subtype .. "' for group: '" .. tagged_group .. "'")
        table.insert(detected_subtypes, tagged_subtype)
        
        -- If this is from the same group as our matched config, check for parent override
        if matched_config then
            local config_name_lower = matched_config.name and matched_config.name:lower() or ""
            if tagged_group:lower() == config_name_lower and
               matched_config.subtype_parent_overrides and 
               matched_config.subtype_parent_overrides[tagged_subtype] then
                subtype_parent_override = matched_config.subtype_parent_overrides[tagged_subtype]
                ImportScript.DebugPrint("  ✓ Found parent track override for tagged subtype '" .. tagged_subtype .. "': " .. subtype_parent_override)
                ImportScript.LogMessage("Using parent override '" .. subtype_parent_override .. "' for tagged subtype '" .. tagged_subtype .. "'", "OVERRIDE")
                
                -- Try to find the override parent track
                local override_parent = TrackConfig.FindTrackByGUIDWithFallback(nil, subtype_parent_override)
                if override_parent then
                    local _, override_parent_name = reaper.GetTrackName(override_parent)
                    ImportScript.DebugPrint("  ✓ Found override parent track: '" .. override_parent_name .. "' for subtype '" .. tagged_subtype .. "'")
                    
                    -- Override the group_parent_track with this one
                    group_parent_track = override_parent
                    ImportScript.LogMessage("Using override parent '" .. override_parent_name .. "' for item '" .. item_name .. "'", "PARENT")
                end
            else
                -- Try case-insensitive matching for subtype_parent_overrides
                ImportScript.DebugPrint("  Checking case-insensitive subtype parent overrides")
                if matched_config and matched_config.subtype_parent_overrides then
                    for subtype, override in pairs(matched_config.subtype_parent_overrides) do
                        if tagged_subtype:lower() == subtype:lower() then
                            subtype_parent_override = override
                            ImportScript.DebugPrint("  ✓ Found parent track override for tagged subtype '" .. tagged_subtype .. "' (case-insensitive): " .. subtype_parent_override)
                            ImportScript.LogMessage("Using parent override '" .. subtype_parent_override .. "' for tagged subtype '" .. tagged_subtype .. "' (case-insensitive)", "OVERRIDE")
                            
                            -- Try to find the override parent track
                            local override_parent = TrackConfig.FindTrackByGUIDWithFallback(nil, subtype_parent_override)
                            if override_parent then
                                local _, override_parent_name = reaper.GetTrackName(override_parent)
                                ImportScript.DebugPrint("  ✓ Found override parent track: '" .. override_parent_name .. "' for subtype '" .. tagged_subtype .. "'")
                                
                                -- Override the group_parent_track with this one
                                group_parent_track = override_parent
                                ImportScript.LogMessage("Using override parent '" .. override_parent_name .. "' for item '" .. item_name .. "'", "PARENT")
                            end
                            break
                        end
                    end
                end
            end
        end
    else
        -- If no tagged subtype, fall back to custom subtype patterns if available
        if matched_config and matched_config.subtypes and #matched_config.subtypes > 0 and matched_config.subtype_patterns then
            ImportScript.DebugPrint("  Checking item against subtype patterns")
            
            -- Try to match against custom subtype patterns
            for _, subtype in ipairs(matched_config.subtypes) do
                if matched_config.subtype_patterns[subtype] then
                    local subtype_patterns = matched_config.subtype_patterns[subtype]
                    
                    for _, pattern in ipairs(subtype_patterns) do
                        if item_name_lower:match(pattern:lower()) then
                            table.insert(detected_subtypes, subtype)
                            ImportScript.DebugPrint("  ✓ Detected subtype '" .. subtype .. "' via pattern '" .. pattern .. "' in item name")
                            ImportScript.LogMessage("Detected subtype '" .. subtype .. "' using pattern '" .. pattern .. "' in item '" .. item_name .. "'", "PATTERN")
                            
                            -- Check if this subtype has a parent track override
                            if matched_config.subtype_parent_overrides and matched_config.subtype_parent_overrides[subtype] then
                                subtype_parent_override = matched_config.subtype_parent_overrides[subtype]
                                ImportScript.DebugPrint("  ✓ Found parent track override for subtype '" .. subtype .. "': " .. subtype_parent_override)
                                ImportScript.LogMessage("Using parent override '" .. subtype_parent_override .. "' for subtype '" .. subtype .. "'", "OVERRIDE")
                                
                                -- Try to find the override parent track
                                local override_parent = TrackConfig.FindTrackByGUIDWithFallback(nil, subtype_parent_override)
                                if override_parent then
                                    local _, override_parent_name = reaper.GetTrackName(override_parent)
                                    ImportScript.DebugPrint("  ✓ Found override parent track: '" .. override_parent_name .. "' for subtype '" .. tagged_subtype .. "'")
                                    
                                    -- Override the group_parent_track with this one
                                    group_parent_track = override_parent
                                    ImportScript.LogMessage("Using override parent '" .. override_parent_name .. "' for item '" .. item_name .. "'", "PARENT")
                                end
                            end
                            
                            break
                        end
                    end
                    
                    if #detected_subtypes > 0 then break end
                end
            end
        end
        
        -- If still no subtype found, fall back to direct subtype matching
        if #detected_subtypes == 0 then
            for _, subtype in ipairs(subtypes) do
                if item_name_lower:find(subtype:lower(), 1, true) then
                    table.insert(detected_subtypes, subtype)
                    ImportScript.DebugPrint("  Detected subtype '" .. subtype .. "' in item name via direct match")
                    
                    -- Check if this subtype has a parent track override
                    if matched_config and matched_config.subtype_parent_overrides and 
                       matched_config.subtype_parent_overrides[subtype] then
                        subtype_parent_override = matched_config.subtype_parent_overrides[subtype]
                        ImportScript.DebugPrint("  Found parent track override for subtype '" .. subtype .. "': " .. subtype_parent_override)
                    end
                end
            end
        end
    end
    
    -- Check for playlist markers in the item name (.1, .2, .3, etc.)
    local playlist_number = nil
    local playlist_pattern = item_name_lower:match("%.(%d+)")
    if playlist_pattern then
        playlist_number = tonumber(playlist_pattern)
        ImportScript.DebugPrint("  Detected playlist number: " .. playlist_number)
    end
    
    -- Extract the base name (without playlist number) for comparisons
    local item_base_name = item_name_lower
    if playlist_number then
        item_base_name = item_name_lower:gsub("%." .. playlist_number, "")
        ImportScript.DebugPrint("  Item base name (without playlist): '" .. item_base_name .. "'")
    end
    
    -- Function to determine if two item names are the same except for playlist numbers
    local function areSameNameExceptPlaylist(name1, name2)
        -- Convert to lowercase for comparison
        local n1 = name1:lower()
        local n2 = name2:lower()
        
        -- Remove playlist numbers if present
        local n1_base = n1:gsub("%.%d+", "")
        local n2_base = n2:gsub("%.%d+", "")
        
        -- Return true if the base names match
        return n1_base == n2_base
    end
    
    -- Build a comprehensive list of tracks to check
    local all_tracks_to_check = {}
    
    -- First add tracks from config_tracks (tracks we're already tracking in this operation)
    for _, track_info in ipairs(config_tracks) do
        if track_info.track then
            table.insert(all_tracks_to_check, {
                track = track_info.track,
                info = track_info
            })
        end
    end
    
    -- Then add all child tracks under the parent folder if we have a parent
    if group_parent_track then
        local _, parent_name = reaper.GetTrackName(group_parent_track)
        ImportScript.DebugPrint("  Searching for child tracks under parent: '" .. parent_name .. "'")
        
        local num_tracks = reaper.CountTracks(0)
        for i = 0, num_tracks - 1 do
            local track = reaper.GetTrack(0, i)
            local parent = reaper.GetParentTrack(track)
            
            -- If this track is a child of our parent track
            if parent == group_parent_track then
                -- Check if we've already added this track from config_tracks
                local already_added = false
                for _, track_info in ipairs(config_tracks) do
                    if track_info.track == track then
                        already_added = true
                        break
                    end
                end
                
                if not already_added then
                    local _, track_name = reaper.GetTrackName(track)
                    ImportScript.DebugPrint("  Adding child track: '" .. track_name .. "' from parent: '" .. parent_name .. "'")
                    table.insert(all_tracks_to_check, {
                        track = track,
                        info = {
                            track = track,
                            name = track_name,
                            items = {}
                        }
                    })
                end
            end
        end
    end
    
    -- ADDITION: If we have a subtype with parent override, also check all tracks under that parent
    if subtype_parent_override and #detected_subtypes > 0 then
        ImportScript.DebugPrint("  Scanning for tracks under parent override: '" .. subtype_parent_override .. "'")
        
        -- Find the parent override track
        local override_parent_track = nil
        local num_tracks = reaper.CountTracks(0)
        for i = 0, num_tracks - 1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = reaper.GetTrackName(track)
            
            if track_name == subtype_parent_override then
                override_parent_track = track
                ImportScript.DebugPrint("  Found override parent track: '" .. track_name .. "'")
                break
            end
        end
        
        -- If not found by name, try using the TrackConfig helper
        if not override_parent_track then
            override_parent_track = TrackConfig.FindTrackByGUIDWithFallback(nil, subtype_parent_override)
            if override_parent_track then
                local _, track_name = reaper.GetTrackName(override_parent_track)
                ImportScript.DebugPrint("  Found override parent track via TrackConfig: '" .. track_name .. "'")
            else
                -- Auto-create the override parent if it doesn't exist
                ImportScript.DebugPrint("  Attempting to auto-create missing override parent: '" .. subtype_parent_override .. "'")
                ImportScript.LogMessage("Auto-creating override parent: '" .. subtype_parent_override .. "'", "CREATE")
                
                -- Create the parent at the root level
                reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                override_parent_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                
                if override_parent_track then
                    -- Set the track name
                    reaper.GetSetMediaTrackInfo_String(override_parent_track, "P_NAME", subtype_parent_override, true)
                    
                    -- Make it a folder
                    reaper.SetMediaTrackInfo_Value(override_parent_track, "I_FOLDERDEPTH", 1)
                    
                    ImportScript.DebugPrint("  ✓ Successfully created override parent track: '" .. subtype_parent_override .. "'")
                    ImportScript.LogMessage("Successfully created override parent: '" .. subtype_parent_override .. "'", "CREATE")
                else
                    ImportScript.DebugPrint("  ✗ Failed to create override parent track")
                    ImportScript.LogMessage("Failed to create override parent: '" .. subtype_parent_override .. "'", "ERROR")
                end
            end
        end
        
        -- If we found the override parent, add all its children
        if override_parent_track then
            for i = 0, num_tracks - 1 do
                local track = reaper.GetTrack(0, i)
                local parent = reaper.GetParentTrack(track)
                
                -- If this track is a child of the override parent track
                if parent == override_parent_track then
                    -- Check if we've already added this track
                    local already_added = false
                    for _, track_data in ipairs(all_tracks_to_check) do
                        if track_data.track == track then
                            already_added = true
                            break
                        end
                    end
                    
                    if not already_added then
                        local _, track_name = reaper.GetTrackName(track)
                        ImportScript.DebugPrint("  Adding child track from override parent: '" .. track_name .. "'")
                        table.insert(all_tracks_to_check, {
                            track = track,
                            info = {
                                track = track,
                                name = track_name,
                                items = {}
                            }
                        })
                    end
                end
            end
        end
    end
    
    -- Check all tracks for the best match
    for _, track_data in ipairs(all_tracks_to_check) do
        local track = track_data.track
        local track_info = track_data.info
        
        if track then
            local _, track_name = reaper.GetTrackName(track)
            local track_name_lower = track_name:lower()
            ImportScript.DebugPrint("  Comparing with track: '" .. track_name .. "'")
            
            -- PRIORITY 1: Check for exact subtype match
            if #detected_subtypes > 0 then
                for _, subtype in ipairs(detected_subtypes) do
                    -- When checking for subtypes, we want to be very precise 
                    ImportScript.DebugPrint("  Checking if track '" .. track_name .. "' contains subtype '" .. subtype .. "'")
                    
                    -- More precise subtype matching to avoid false matches
                    local subtype_match = false
                    
                    -- 1. Check if the track name ends with the exact subtype (with space before)
                    if track_name_lower:match("%s" .. subtype:lower() .. "$") then
                        subtype_match = true
                        ImportScript.DebugPrint("  ✓ Track name ends with subtype")
                    -- 2. Check if track name contains the subtype as a whole word
                    elseif track_name_lower:match("%s" .. subtype:lower() .. "%s") then
                        subtype_match = true
                        ImportScript.DebugPrint("  ✓ Track name contains subtype as whole word")
                    -- 3. Direct match for single-word track names
                    elseif track_name_lower == subtype:lower() then
                        subtype_match = true
                        ImportScript.DebugPrint("  ✓ Track name exactly matches subtype")
                    end
                    
                    if subtype_match then
                        -- Found a subtype match - this is highest priority
                        
                        -- Check for playlist difference (if both have playlist numbers)
                        local track_playlist = track_name_lower:match("%.(%d+)")
                        if playlist_number and track_playlist then
                            local track_playlist_num = tonumber(track_playlist)
                            
                            -- If playlists are different but everything else matches,
                            -- we should use take lanes
                            if track_playlist_num ~= playlist_number and areSameNameExceptPlaylist(track_name, item_name) then
                                ImportScript.DebugPrint("  Different playlist numbers: track=" .. track_playlist_num .. 
                                                      ", item=" .. playlist_number .. ", will use take lanes")
                best_track = track
                best_track_info = track_info
                best_score = 100
                                should_use_lanes = true
                                ImportScript.LogMessage("Found playlist variation with track: '" .. track_name .. 
                                                     "', will use take lanes", "MATCH")
                                goto return_best_track
                            end
                        end
                        
                        -- This is a generic approach for all track types with subtypes
                        -- Check if this track is for the specific subtype we're looking for
                        -- Generate track variations to try
                        local base_track_name = ""
                        if matched_config and matched_config.destination_track then
                            base_track_name = matched_config.destination_track
                        else
                            base_track_name = matched_group_name
                        end
                        
                        -- Build possible variations of the track name with the subtype
                        local target_variations = {
                            (base_track_name .. " " .. subtype):lower(),
                            base_track_name:lower() .. subtype:lower(),
                            ("d " .. base_track_name .. " " .. subtype):lower(),
                            ("d " .. base_track_name .. subtype):lower()
                        }
                        
                        -- Add any custom track name variations from config
                        if matched_config and matched_config.track_name_variations then
                            for _, variation in ipairs(matched_config.track_name_variations) do
                                table.insert(target_variations, variation:lower())
                                -- Also add variations with the subtype
                                table.insert(target_variations, (variation .. " " .. subtype):lower())
                                table.insert(target_variations, (variation .. subtype):lower())
                                -- If the variation doesn't start with "d" and this is a drums track, add "d " prefix
                                if variation:sub(1, 1):lower() ~= "d" and 
                                   (matched_config.parent_group == "Drums" or matched_config.name == "Drums") then
                                    table.insert(target_variations, ("d " .. variation):lower())
                                    table.insert(target_variations, ("d " .. variation .. " " .. subtype):lower())
                                    table.insert(target_variations, ("d " .. variation .. subtype):lower())
                                end
                            end
                        end
                        
                        -- Extract base track name without playlist numbers for matching
                        local track_base = track_name_lower:gsub("%.%d+", "")
                        
                        -- Check if this track matches any of our target variations
                        local variation_match = false
                        local matched_variation = ""
                        
                        -- Normalize track name and target for more reliable matching
                        -- Remove case sensitivity and handle common spacing variations
                        local function normalizeTrackName(name)
                            if not name then return "" end
                            local normalized = name:lower()
                                          :gsub("-", " ")  -- Convert dashes to spaces
                                          :gsub("hi hat", "hihat")  -- Normalize common hihat variations
                                          :gsub("hi%-hat", "hihat")
                                          :gsub("hi_hat", "hihat")
                            return normalized
                        end
                        
                        local track_base_normalized = normalizeTrackName(track_base)
                        
                        for _, target in ipairs(target_variations) do
                            local target_normalized = normalizeTrackName(target)
                            
                            if track_base_normalized == target_normalized or
                               track_base_normalized:match(target_normalized .. "$") or 
                               track_base_normalized:match("^" .. target_normalized) then
                                variation_match = true
                                matched_variation = target
                                ImportScript.DebugPrint("  ✓ Found subtype match with track: '" .. track_name .. 
                                                    "' using variation: '" .. target .. "'")
                break
            end
        end
                        
                        if variation_match then
                            ImportScript.DebugPrint("  Found match using variation: '" .. matched_variation .. "'")
                            best_track = track
                            best_track_info = track_info
                            best_score = 100
                            ImportScript.LogMessage("Found subtype match with track: '" .. track_name .. 
                                                 "' for subtype: '" .. subtype .. "' using variation: '" .. matched_variation .. "'", "MATCH")
                            goto return_best_track
                        end
                        
                        -- If we didn't find a specific variation match but we have a subtype match
                        -- still use this track as a fallback
                        best_track = track
                        best_track_info = track_info
                        best_score = 100
                        ImportScript.DebugPrint("  Found subtype match with track: '" .. track_name .. 
                                              "' for subtype: '" .. subtype .. "'")
                        ImportScript.LogMessage("Found subtype match with track: '" .. track_name .. 
                                             "' for subtype: '" .. subtype .. "'", "MATCH")
                        goto return_best_track -- Skip other checks and return this match
                    end
                end
                
                -- If we get here with detected subtypes but no match,
                -- we should duplicate a track with similar base characteristics
                -- if we later find a match with different subtypes
                should_duplicate_track = true
            end
            
            -- PRIORITY 2: Try exact match (case insensitive)
            -- Make a more careful check for exact match of base names
            if string.lower(item_base_name) == string.lower(track_name_lower:gsub("%.%d+", "")) then
                -- Apply playlist checking logic
                local track_playlist = track_name_lower:match("%.(%d+)")
                
                if playlist_number and track_playlist then
                    local track_playlist_num = tonumber(track_playlist)
                    
                    -- If playlists are different but base names match, use take lanes
                    if track_playlist_num ~= playlist_number then
                        ImportScript.DebugPrint("  Same base name with different playlist numbers: track=" .. 
                            track_playlist_num .. ", item=" .. playlist_number .. ", will use take lanes")
                        best_track = track
                        best_track_info = track_info
                        best_score = 90
                        should_use_lanes = true
                        ImportScript.LogMessage("Found track with same base name but different playlist: '" .. 
                            track_name .. "', will use take lanes", "MATCH")
                        goto return_best_track
                    end
                end
                
                -- Exact match (including playlist if both have it, or neither have it)
                best_track = track
                best_track_info = track_info
                best_score = 80
                ImportScript.DebugPrint("  Found exact base name match with track: '" .. track_name .. "'")
                ImportScript.LogMessage("Found exact base name match with track: '" .. track_name .. "'", "MATCH")
                goto return_best_track -- Skip other checks and return this match
            end
            
            -- PRIORITY 3: Try pattern match as last resort
            if best_score < 80 then
                local matches, pattern = PatternMatching.MatchesAnyPattern(item_name, {track_name})
                if matches then
                    -- Found a pattern match
                    best_track = track
                    best_track_info = track_info
                    best_score = 70
                    ImportScript.DebugPrint("  Found pattern match with track: '" .. track_name .. "'")
                    ImportScript.LogMessage("Found pattern match with track: '" .. track_name .. "'", "MATCH")
                    -- Don't break here, continue checking for better matches
                end
            end
        end
    end
    
    ::return_best_track::
    -- If a good match was found, return it along with the lane flags
    if best_track then
        return best_track, best_track_info, best_score, should_use_lanes
    end
    
    -- If no match found, create a new track with appropriate subtype if detected
    -- Generate track name based on categories and detected subtypes
    local new_track_name = ""
    
    -- Use the destination_track from the config as base instead of the matched_group_name
    local base_track_name = ""
    if matched_config and matched_config.destination_track then
        base_track_name = matched_config.destination_track
    else
        base_track_name = matched_group_name
    end
    
    -- If we detected a subtype, append it to the base name
    if #detected_subtypes > 0 then
        local subtype = detected_subtypes[1]
        ImportScript.DebugPrint("  Creating track with subtype: '" .. subtype .. "'")
        
        -- If the parent track name typically starts with "D", make sure our new track does too
        local d_prefix = ""
        if group_parent_track then
            local _, parent_track_name = reaper.GetTrackName(group_parent_track)
            if parent_track_name:sub(1, 1) == "D" and base_track_name:sub(1, 1) ~= "D" then
                d_prefix = "D "
            end
        end
        
        -- Form the track name with the subtype
        new_track_name = d_prefix .. base_track_name .. " " .. subtype
        
        -- Add a unique identifier if needed to ensure separation between subtypes
        -- This is important for instruments like toms where each subtype must go to a specific track
        if matched_config and matched_config.force_separate_subtype_tracks then
            new_track_name = new_track_name .. "_" .. subtype
        end
        
        ImportScript.DebugPrint("  Creating track with name: '" .. new_track_name .. "'")
        ImportScript.LogMessage("Creating track for subtype '" .. subtype .. "': '" .. new_track_name .. "'", "CREATE")
    else
        -- No subtype - just use the base name
        new_track_name = base_track_name
        ImportScript.DebugPrint("  Creating track with base name: '" .. new_track_name .. "'")
        ImportScript.LogMessage("Creating track with base name: '" .. new_track_name .. "'", "CREATE")
    end
    
    -- Create the track
    -- 1. Find the appropriate parent track first
    local parent_track_to_use = group_parent_track
    
    -- 2. If we have a subtype with a parent override, use that instead
    if #detected_subtypes > 0 and subtype_parent_override then
        -- Try to find the override parent (or create it if needed)
        local override_parent = TrackConfig.FindTrackByGUIDWithFallback(nil, subtype_parent_override)
        
        if override_parent then
            local _, override_parent_name = reaper.GetTrackName(override_parent)
            ImportScript.DebugPrint("  Using subtype parent override: '" .. override_parent_name .. "'")
            ImportScript.LogMessage("Using parent override '" .. override_parent_name .. "' for new track", "PARENT")
            parent_track_to_use = override_parent
        else
            -- Auto-create the parent track if it doesn't exist
            ImportScript.DebugPrint("  Parent override track '" .. subtype_parent_override .. "' not found, creating it")
            ImportScript.LogMessage("Creating missing parent track: '" .. subtype_parent_override .. "'", "CREATE")
            
            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
            local new_parent = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
            
            if new_parent then
                -- Set name and make it a folder
                reaper.GetSetMediaTrackInfo_String(new_parent, "P_NAME", subtype_parent_override, true)
                reaper.SetMediaTrackInfo_Value(new_parent, "I_FOLDERDEPTH", 1)
                
                ImportScript.DebugPrint("  Created parent track: '" .. subtype_parent_override .. "'")
                parent_track_to_use = new_parent
            end
            end
        end
        
    -- 3. If we still don't have a parent track, create one using the matched_config
    if not parent_track_to_use and matched_config and matched_config.parent_track then
        ImportScript.DebugPrint("  Creating missing parent track: '" .. matched_config.parent_track .. "'")
        ImportScript.LogMessage("Creating parent track: '" .. matched_config.parent_track .. "'", "CREATE")
        
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local new_parent = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
        
        if new_parent then
            -- Set name and make it a folder
            reaper.GetSetMediaTrackInfo_String(new_parent, "P_NAME", matched_config.parent_track, true)
            reaper.SetMediaTrackInfo_Value(new_parent, "I_FOLDERDEPTH", 1)
            
            ImportScript.DebugPrint("  Created parent track: '" .. matched_config.parent_track .. "'")
            parent_track_to_use = new_parent
        end
    end
    
    -- 4. Now create the actual track at the right position
    -- Create a new track as a child of the parent
    local new_track = nil
    
    if parent_track_to_use then
        -- Find the end of the folder to insert at
        local folder_index = reaper.GetMediaTrackInfo_Value(parent_track_to_use, "IP_TRACKNUMBER") - 1
        local folder_depth = 1  -- Start at depth 1 (inside folder)
        local folder_end_index = -1
        
        -- Find the end of the folder
        for i = folder_index + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local depth_change = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            
            folder_depth = folder_depth + depth_change
            
            if folder_depth <= 0 then
                folder_end_index = i
                break
            end
        end
        
        -- If no folder end found, assume it's at the end of the project
        if folder_end_index == -1 then
            folder_end_index = reaper.CountTracks(0)
        end
        
        -- Create the new track at the folder end
        ImportScript.DebugPrint("  Inserting track at folder end index: " .. folder_end_index)
        reaper.InsertTrackAtIndex(folder_end_index, true)
        new_track = reaper.GetTrack(0, folder_end_index)
    else
        -- No parent, create at the end of the project
        ImportScript.DebugPrint("  No parent found, creating track at end of project")
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        new_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    end
    
    -- 5. Configure the track
        if new_track then
        -- Set the track name
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", new_track_name, true)
        
        -- Configure it as a child track if we have a parent
        if parent_track_to_use then
            -- Set indentation (depth)
            local parent_tcp_depth = reaper.GetMediaTrackInfo_Value(parent_track_to_use, "I_TCPDEPTH")
            reaper.SetMediaTrackInfo_Value(new_track, "I_TCPDEPTH", parent_tcp_depth + 1)
            
            -- Not a folder itself
            reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
        end
        
        -- Create the track info record
        local track_info = {
                track = new_track,
                name = new_track_name,
            items = {},
            tracked = true
        }
        
        ImportScript.DebugPrint("  ✓ Successfully created track: '" .. new_track_name .. "'")
        ImportScript.LogMessage("Created track: '" .. new_track_name .. "'", "CREATE")
        
        -- Return the new track and info
        return new_track, track_info, 50, false
    else
        ImportScript.DebugPrint("  ✗ Failed to create track")
        ImportScript.LogMessage("Failed to create track: '" .. new_track_name .. "'", "ERROR")
    end
    
    return nil, nil, 0, false
end

-- Now, modify the OrganizeSelectedItems function to properly handle destination tracks
function ImportScript.OrganizeSelectedItems()
    -- Prevent UI refresh during organization
    reaper.PreventUIRefresh(1)
    
    -- Get available track configurations
    local track_configs = ImportScript.LoadTrackConfigs()
    
    if not track_configs or next(track_configs) == nil then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing before showing message
        reaper.ShowMessageBox("No track configurations found. Please create at least one configuration in the Track Configurations tab.", "No Configurations", 0)
        ImportScript.LogMessage("Operation failed: No track configurations found", "ERROR")
        return
    end
    
    -- Check if any items are selected
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        reaper.PreventUIRefresh(-1) -- Resume UI refreshing before showing message
        reaper.ShowMessageBox("No items selected. Please select items to organize.", "No Items Selected", 0)
        ImportScript.LogMessage("Operation failed: No items selected", "ERROR")
        return
    end
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Output debug header
    ImportScript.DebugPrint("\n============ ORGANIZE SELECTED ITEMS ============")
    ImportScript.DebugPrint("Processing " .. item_count .. " selected items")
    ImportScript.DebugPrint("Available track configurations: " .. tostring(next(track_configs) and table.concat(GetTableKeys(track_configs), ", ") or "None"))
    
    -- Add to logs
    ImportScript.LogMessage("Started organizing " .. item_count .. " items", "ORGANIZE")
    
    -- Load required modules
    local TrackManagement = require("track_management")
    local PatternMatching = dofile(reaper.GetResourcePath() .. "/Scripts/FastTrackStudio Scripts/libraries/utils/Pattern Matching.lua")
    local TrackConfig = require("track_config")
    
    -- Load global patterns for track renaming
    local DefaultPatterns = require("default_patterns")
    local ext_state_name = "FastTrackStudio_ImportByName"
    local global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, ImportScript)
    
    -- PHASE 1: Collect all possible matches for each item
    ImportScript.DebugPrint("\n--- PHASE 1: COLLECTING ALL POSSIBLE MATCHES ---")
    ImportScript.LogMessage("Phase 1: Collecting all possible matches", "ORGANIZE")
    
    local all_items = {}
    local source_tracks = {} -- Keep track of source tracks to check for emptiness later
    
    -- Tom handling - identify tom tracks by counting them to assign numbers if missing
    local tom_high_found = false
    local tom_mid_found = false
    local tom_low_found = false 
    local tom_floor_found = false
    local unnumbered_toms = {}
    
    -- First pass - identify all tom tracks and look for specific types
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            local take_name_lower = take_name:lower()
            
            -- Check if this is a tom
            if take_name_lower:match("tom") then
                -- Check for specific tom types
                if take_name_lower:match("high") or take_name_lower:match("hi ") or take_name_lower:match("top") then
                    tom_high_found = true
                elseif take_name_lower:match("mid") or take_name_lower:match("middle") then
                    tom_mid_found = true
                elseif take_name_lower:match("low") or take_name_lower:match("bottom") then
                    tom_low_found = true
                elseif take_name_lower:match("floor") then
                    tom_floor_found = true
                elseif not take_name_lower:match("tom%s*%d") then
                    -- This is a tom with no clear identifier - save for later processing
                    table.insert(unnumbered_toms, {
                        item = item,
                        take = take,
                        name = take_name
                    })
                end
            end
        end
    end
    
    -- If we have unnumbered toms and not all tom types are found, try to map them
    if #unnumbered_toms > 0 then
        ImportScript.DebugPrint("Found " .. #unnumbered_toms .. " unnumbered toms, attempting to map them")
        
        -- Sort by pitch if we can, otherwise just use default ordering
        -- For now, we'll use a simple mapping strategy
        local tom_types = {"high", "mid", "low", "floor"}
        local tom_statuses = {tom_high_found, tom_mid_found, tom_low_found, tom_floor_found}
        
        local idx = 1
        for _, tom_data in ipairs(unnumbered_toms) do
            -- Find the next available tom type
            while idx <= 4 and tom_statuses[idx] do
                idx = idx + 1
            end
            
            if idx <= 4 then
                -- Add tag to the name to help with subtype detection
                local take = tom_data.take
                local new_name = tom_data.name .. " [" .. tom_types[idx] .. "]"
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", new_name, true)
                
                ImportScript.DebugPrint("Tagged unnumbered tom '" .. tom_data.name .. "' as '" .. new_name .. "'")
                ImportScript.LogMessage("Automatically tagged tom '" .. tom_data.name .. "' as '" .. tom_types[idx] .. "' type", "TOM")
                
                -- Mark this type as used
                tom_statuses[idx] = true
                idx = idx + 1
            end
        end
    end
    
    -- Now process all items normally
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            
            -- Track source track for possible deletion
            local source_track = reaper.GetMediaItemTrack(item)
            if source_track then
                source_tracks[tostring(source_track)] = source_track
            end
            
            ImportScript.DebugPrint("\nCollecting matches for item: '" .. take_name .. "'")
            
            -- Special handling for Tom tracks - apply tom number to name before matching
            local take_name_lower = take_name:lower()
            local modified_take_name = take_name
            
            -- Instead of special tom logic, use the generic subtype pattern matching for all instrument types
            local matched_subtype = nil
            local matched_group = nil
            
            -- First try to identify which group this item belongs to
            for name, config in pairs(track_configs) do
                if config.patterns and #config.patterns > 0 then
                    local matches, pattern = PatternMatching.MatchesAnyPattern(take_name, config.patterns)
                    if matches and not PatternMatching.MatchesNegativePattern(take_name, config.negative_patterns or {}) then
                        matched_group = config
                        ImportScript.DebugPrint("  ✓ Item matched group: '" .. name .. "' with pattern: '" .. pattern .. "'")
                        
                        -- Now check if this group has subtypes
                        if config.subtypes and #config.subtypes > 0 and config.subtype_patterns then
                            ImportScript.DebugPrint("  Checking for subtypes in group: '" .. name .. "'")
                            
                            -- Try to match a subtype
                            for _, subtype in ipairs(config.subtypes) do
                                if config.subtype_patterns[subtype] then
                                    local subtype_patterns = config.subtype_patterns[subtype]
                                    
                                    for _, pattern in ipairs(subtype_patterns) do
                                        if take_name_lower:match(pattern:lower()) then
                                            matched_subtype = subtype
                                            ImportScript.DebugPrint("  ✓ Item matched subtype: '" .. subtype .. "' with pattern: '" .. pattern .. "'")
                                            
                                            -- Tag the item with the subtype for later use
                                            modified_take_name = take_name .. " [" .. name .. "-" .. subtype .. "]"
                                            ImportScript.LogMessage("Enhanced item '" .. take_name .. "' with subtype tag: '" .. modified_take_name .. "'", "SUBTYPE")
                                            break
                                        end
                                    end
                                    
                                    if matched_subtype then break end
                                end
                            end
                        end
                        
                        break -- Found a matching group, no need to check others
                    end
                end
            end
            
            -- Update take name for pattern matching but don't commit to actual take yet
            take_name = modified_take_name
            if matched_subtype then
                ImportScript.LogMessage("Item '" .. take_name .. "' matched subtype: '" .. matched_subtype .. "'", "SUBTYPE")
            end
            
            -- Find all possible matching track configurations
            local possible_matches = {}
            
            for name, config in pairs(track_configs) do
                ImportScript.DebugPrint("  Checking config: " .. name)
                
                if config.patterns and #config.patterns > 0 then
                    local matches, pattern = PatternMatching.MatchesAnyPattern(take_name, config.patterns)
                    if matches then
                        -- Check negative patterns
                        local negative_match = PatternMatching.MatchesNegativePattern(take_name, config.negative_patterns or {})
                        if not negative_match then
                            -- Calculate match score based on specificity
                            local match_score = 0
                            
                            -- Base score for matching the group
                            match_score = match_score + 10
                            
                            -- Additional score for matching specific track patterns
                            if config.track_patterns and #config.track_patterns > 0 then
                                local track_matches, track_pattern = PatternMatching.MatchesAnyPattern(take_name, config.track_patterns)
                                if track_matches then
                                    match_score = match_score + 20
                                end
                            end
                            
                            -- Add to possible matches
                            table.insert(possible_matches, {
                                name = name,
                                config = config,
                                pattern = pattern,
                                score = match_score
                            })
                            
                            ImportScript.DebugPrint("    ✓ MATCHED with config: '" .. name .. "', pattern: '" .. pattern .. "', score: " .. match_score)
                            ImportScript.LogMessage("Item '" .. take_name .. "' matched config: '" .. name .. "' with pattern: '" .. pattern .. "'", "MATCH")
                        end
                    end
                end
            end
            
            -- Sort matches by score (highest first)
            table.sort(possible_matches, function(a, b) return a.score > b.score end)
            
            -- Extract pattern categories from item name
            -- Now pass the best matched group to ExtractPatternCategories if we have matches
            local matched_group = nil
            if #possible_matches > 0 then
                -- Use the highest scored match's config
                matched_group = possible_matches[1].config
            end
            
            -- Extract categories with the matched group
            local categories = ExtractPatternCategories(take_name, global_patterns, track_configs, matched_group, true)
            
            -- Add to all items with their matches
            table.insert(all_items, {
                item = item,
                take = take,
                name = take_name,
                start = item_start,
                end_time = item_end,
                categories = categories,
                matches = possible_matches
            })
            
            if #possible_matches > 0 then
                ImportScript.DebugPrint("  Found " .. #possible_matches .. " possible matches")
            else
                ImportScript.DebugPrint("  ✗ No matching configuration found")
                ImportScript.LogMessage("Item '" .. take_name .. "' has no matching configuration", "UNMATCH")
            end
        else
            ImportScript.DebugPrint("  ✗ SKIPPED: Item has no take")
            ImportScript.LogMessage("Skipped an item without a take", "SKIP")
        end
    end
    
    -- PHASE 2: Find all existing destination tracks for each group
    ImportScript.DebugPrint("\n--- PHASE 2: FINDING EXISTING DESTINATION TRACKS ---")
    ImportScript.LogMessage("Phase 2: Finding existing destination tracks", "ORGANIZE")
    
    -- Map to store destination tracks for each group
    local group_destination_tracks = {}
    
    -- Helper function to normalize track names for comparison
    local function normalizeTrackName(name)
        if not name then return "" end
        local normalized = name:lower()
                        :gsub("-", " ")  -- Convert dashes to spaces
                        :gsub("hi hat", "hihat")  -- Normalize hihat variations
                        :gsub("hi%-hat", "hihat")
                        :gsub("hi_hat", "hihat")
        return normalized
    end
    
    -- Function to check if two track names match (normalized)
    local function tracksMatch(name1, name2)
        return normalizeTrackName(name1) == normalizeTrackName(name2)
    end
    
    -- For each group, find all existing destination tracks
    for group_name, group_config in pairs(track_configs) do
        -- Get parent track
        local parent_track = TrackConfig.FindTrackByGUIDWithFallback(
            group_config.parent_track_guid, 
            group_config.parent_track
        )
        
        if parent_track then
            -- Find all tracks that are children of this parent
            local destination_tracks = {}
            local track_count = reaper.CountTracks(0)
            
            -- Log the parent track we're checking
            local _, parent_name = reaper.GetTrackName(parent_track)
            ImportScript.DebugPrint("  Checking for destination tracks under parent: '" .. parent_name .. "' for group: '" .. group_name .. "'")
            
            for i = 0, track_count - 1 do
                local track = reaper.GetTrack(0, i)
                local parent = reaper.GetParentTrack(track)
                
                if parent == parent_track then
                    local _, track_name = reaper.GetTrackName(track)
                    local track_normalized = normalizeTrackName(track_name)
                    local dest_normalized = ""
                    
                    -- Check if this is the destination track or matches any variations
                    if group_config.destination_track then
                        dest_normalized = normalizeTrackName(group_config.destination_track)
                        
                        -- Check direct match
                        if track_normalized == dest_normalized then
                            ImportScript.DebugPrint("  ✓ Found exact destination track match: '" .. track_name .. "' for group: '" .. group_name .. "'")
                    table.insert(destination_tracks, {
                        track = track,
                        name = track_name
                    })
                        -- Check D prefix common in drum tracks
                        elseif track_normalized == "d " .. dest_normalized then
                            ImportScript.DebugPrint("  ✓ Found destination track with D prefix: '" .. track_name .. "' for group: '" .. group_name .. "'")
                            table.insert(destination_tracks, {
                                track = track,
                                name = track_name
                            })
                        -- Check name variations if present
                        elseif group_config.track_name_variations then
                            for _, variation in ipairs(group_config.track_name_variations) do
                                if track_normalized == normalizeTrackName(variation) then
                                    ImportScript.DebugPrint("  ✓ Found destination track via variation: '" .. track_name .. "' matches '" .. variation .. "' for group: '" .. group_name .. "'")
                                    table.insert(destination_tracks, {
                                        track = track,
                                        name = track_name
                                    })
                                    break
                                end
                            end
                        end
                    else
                        -- If no destination_track specified, use all children
                        table.insert(destination_tracks, {
                            track = track,
                            name = track_name
                        })
                    end
                    end
                end
                
            -- Store the destination tracks for this group
            group_destination_tracks[group_name] = {
                parent_track = parent_track,
                destination_tracks = destination_tracks
            }
            
            ImportScript.DebugPrint("  Group '" .. group_name .. "' has " .. #destination_tracks .. " destination tracks")
        end
    end
    
    -- PHASE 3: Create all necessary tracks first
    ImportScript.DebugPrint("\n--- PHASE 3: CREATING TRACKS ---")
    ImportScript.LogMessage("Phase 3: Creating necessary tracks", "ORGANIZE")
    
    -- Track created tracks and their items
    local created_tracks = {}
    local items_organized = 0
    local items_skipped = 0
    local unmatched_items = 0
    local track_creation_failed_items = 0
    
    -- First, create all necessary tracks
    for _, item_data in ipairs(all_items) do
        -- Skip items with no matches
        if #item_data.matches == 0 then
            unmatched_items = unmatched_items + 1
            goto continue_phase3
        end
        
        -- Get the best match (highest score)
        local best_match = item_data.matches[1]
        
        -- Get parent track
        local parent_track = TrackConfig.FindTrackByGUIDWithFallback(
            best_match.config.parent_track_guid, 
            best_match.config.parent_track
        )
        
        if parent_track then
            local _, parent_name = reaper.GetTrackName(parent_track)
            ImportScript.DebugPrint("  Found parent track: '" .. parent_name .. "'")
            ImportScript.LogMessage("Using parent track: '" .. parent_name .. "'", "TRACK")
        else
            ImportScript.DebugPrint("  No parent track found")
            ImportScript.LogMessage("No parent track found for config: '" .. best_match.name .. "'", "TRACK")
            
            -- Auto-create parent track if it doesn't exist but we have a parent_track name
            if best_match.config.parent_track and best_match.config.parent_track ~= "" then
                ImportScript.DebugPrint("  Attempting to auto-create missing parent track: '" .. best_match.config.parent_track .. "'")
                ImportScript.LogMessage("Auto-creating parent track: '" .. best_match.config.parent_track .. "'", "CREATE")
                
                -- Create the parent at the root level
                reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                local new_parent = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                
                if new_parent then
                    -- Set the track name
                    reaper.GetSetMediaTrackInfo_String(new_parent, "P_NAME", best_match.config.parent_track, true)
                    
                    -- Make it a folder
                    reaper.SetMediaTrackInfo_Value(new_parent, "I_FOLDERDEPTH", 1)
                    
                    parent_track = new_parent
                    ImportScript.DebugPrint("  ✓ Successfully created parent track: '" .. best_match.config.parent_track .. "'")
                    ImportScript.LogMessage("Successfully created parent track: '" .. best_match.config.parent_track .. "' for group: '" .. best_match.name .. "'", "CREATE")
                else
                    ImportScript.DebugPrint("  ✗ Failed to create parent track")
                    ImportScript.LogMessage("Failed to create parent track: '" .. best_match.config.parent_track .. "'", "ERROR")
                end
            end
        end
        
        -- Determine destination track name (base name)
        local base_track_name = best_match.config.destination_track or best_match.name
        
        -- Get config tracks for this configuration
        local config_tracks = created_tracks[best_match.name] or {}
        
        -- Find the best destination track for this item
        local destination_track, best_track_info, match_score, should_use_lanes = FindBestDestinationTrack(
            item_data.name, 
            item_data.categories, 
            config_tracks, 
            parent_track, 
            base_track_name,
            track_configs
        )
        
        -- If we found a destination track
        if destination_track then
            ImportScript.DebugPrint("  Found destination track with score: " .. match_score)
            
            -- If this is a new track we haven't tracked yet, add it to our list
            if best_track_info and not best_track_info.tracked then
                best_track_info.tracked = true
                table.insert(config_tracks, best_track_info)
                created_tracks[best_match.name] = config_tracks
            end
            
            -- Store the destination track info with the item data for later use
            item_data.destination_track = destination_track
            item_data.best_track_info = best_track_info
            item_data.should_use_lanes = should_use_lanes
        else
            ImportScript.DebugPrint("  ✗ No destination track available")
            ImportScript.LogMessage("Failed to find or create destination track for '" .. item_data.name .. "'", "ERROR")
            items_skipped = items_skipped + 1
            track_creation_failed_items = track_creation_failed_items + 1
        end
        
        ::continue_phase3::
    end
    
    -- PHASE 4: Move items to their destination tracks
    ImportScript.DebugPrint("\n--- PHASE 4: MOVING ITEMS ---")
    ImportScript.LogMessage("Phase 4: Moving items to destination tracks", "ORGANIZE")
    
    -- Track if we used take lanes for any items (for comp creation later)
    local tracks_with_lanes = {}
    
    -- Keep a record of destination tracks and how many items they've received
    local track_item_counts = {}
    
    -- First pass: Count how many items are going to each track
    for _, item_data in ipairs(all_items) do
        -- Skip items with no matches or no destination track
        if #item_data.matches == 0 or not item_data.destination_track then
            goto continue_count
        end
        
        -- Get track GUID for tracking
        local track_guid = reaper.GetTrackGUID(item_data.destination_track)
        if not track_guid then
            track_guid = "unknown_" .. math.random(10000)
        end
        
        -- Initialize count if not exists
        if not track_item_counts[track_guid] then
            track_item_counts[track_guid] = {
                count = 0,
                track = item_data.destination_track,
                items = {} -- Store items for this track
            }
        end
        
        -- Increment count and store the item
        track_item_counts[track_guid].count = track_item_counts[track_guid].count + 1
        table.insert(track_item_counts[track_guid].items, item_data)
        
        ::continue_count::
    end
    
    -- Now move all items to their destination tracks first WITHOUT creating lanes
    for _, item_data in ipairs(all_items) do
        -- Skip items with no matches or no destination track
        if #item_data.matches == 0 or not item_data.destination_track then
            ImportScript.DebugPrint("  Skipping item without destination track: '" .. item_data.name .. "'")
            goto continue_phase4_move
        end
        
        -- Get the best match (highest score)
        local best_match = item_data.matches[1]
        
        -- Determine destination track name (base name)
        local base_track_name = best_match.config.destination_track or best_match.name
        
        -- Get destination track info
        local _, dest_track_name = reaper.GetTrackName(item_data.destination_track)
        ImportScript.DebugPrint("  Destination track is: '" .. dest_track_name .. "'")
        
        -- Get track GUID for tracking
        local track_guid = reaper.GetTrackGUID(item_data.destination_track)
        if not track_guid then
            track_guid = "unknown_" .. math.random(10000)
        end
        
        -- Check if this is a multi-item track (multiple items going to the same track)
        local should_use_lanes_auto = false
        if track_item_counts[track_guid] and track_item_counts[track_guid].count > 1 then
            should_use_lanes_auto = true
            item_data.should_use_lanes_auto = true
            ImportScript.DebugPrint("  Track '" .. dest_track_name .. "' will receive " .. 
                track_item_counts[track_guid].count .. " items, using take lanes")
        end
        
        -- Move the item to the destination track
        ImportScript.DebugPrint("  Moving item '" .. item_data.name .. "' to track: '" .. item_data.best_track_info.name .. "'")
        
        -- Get current track the item is on
        local current_track = reaper.GetMediaItemTrack(item_data.item)
        local _, current_track_name = reaper.GetTrackName(current_track)
        ImportScript.DebugPrint("  Item is currently on track: '" .. current_track_name .. "'")
        
        -- Directly move the item
        if reaper.MoveMediaItemToTrack(item_data.item, item_data.destination_track) then
            ImportScript.DebugPrint("  ✓ Successfully moved item to track")
            
            -- Add this item to the track's item list
            table.insert(item_data.best_track_info.items, {
                name = item_data.name,
                start = item_data.start,
                end_time = item_data.end_time
            })
            
            -- Generate the full pattern-based name for the item
            local item_name_to_use = item_data.best_track_info.name
            
            -- If we have pattern categories, generate a full name
            if next(item_data.categories) then
                local generated_name = GenerateTrackNameFromCategories(base_track_name, item_data.categories)
                ImportScript.LogMessage("Generated full name: '" .. generated_name .. "' (track name: '" .. item_data.best_track_info.name .. "')", "RENAME")
                item_name_to_use = generated_name
            end
            
            -- Rename the item's take to match the full name
            local take = reaper.GetActiveTake(item_data.item)
            if take then
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_name_to_use, true)
                ImportScript.LogMessage("Renamed item to '" .. item_name_to_use .. "'", "RENAME")
            end
            
            -- Store info for lane processing in next step
            local use_lanes = item_data.should_use_lanes or should_use_lanes_auto
            if use_lanes then
                -- Track this for later lane processing
                tracks_with_lanes[track_guid] = item_data.destination_track
            end
            
            items_organized = items_organized + 1
            ImportScript.LogMessage("Moved item '" .. item_data.name .. "' to track '" .. item_data.best_track_info.name .. "'", "MOVE")
        else
            ImportScript.DebugPrint("  ✗ Failed to move item to track")
            ImportScript.LogMessage("Failed to move item '" .. item_data.name .. "' to track '" .. item_data.best_track_info.name .. "'", "ERROR")
            items_skipped = items_skipped + 1
        end
        
        ::continue_phase4_move::
    end
    
    -- PHASE 4B: Now assign items to lanes (as a separate step)
    ImportScript.DebugPrint("\n--- PHASE 4B: ASSIGNING ITEMS TO LANES ---")
    ImportScript.LogMessage("Phase 4B: Assigning items to take lanes", "ORGANIZE")
    
    -- Process each track that needs lanes
    for guid, track in pairs(tracks_with_lanes) do
        if track_item_counts[guid] and track_item_counts[guid].count > 1 then
            local _, track_name = reaper.GetTrackName(track)
            ImportScript.LogMessage("Assigning " .. track_item_counts[guid].count .. " items to lanes on track '" .. track_name .. "'", "LANES")
            
            -- First, make sure no items are selected
            reaper.SelectAllMediaItems(0, false)
            
            -- Unload all current items from lanes if any existed previously
            -- Select all items on this track
            for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                reaper.SetMediaItemSelected(item, true)
            end
            
            -- Move all selected items to the "main" lane (action 42788)
            ImportScript.LogMessage("Moving all items to main lane first", "LANES")
            reaper.Main_OnCommand(42788, 0) -- Move selected items to main lane
            reaper.SelectAllMediaItems(0, false) -- Deselect all
            reaper.UpdateArrange() -- Give REAPER a moment
            
            -- Now process each item one at a time
            for i, item_data in ipairs(track_item_counts[guid].items) do
                if i > 1 then -- First item stays in main lane
                    -- Select just this item
                    reaper.SelectAllMediaItems(0, false) -- Deselect all first
                    reaper.SetMediaItemSelected(item_data.item, true)
                    
                    -- Create a new take lane for this item
                    ImportScript.LogMessage("Moving item '" .. item_data.name .. "' to lane " .. i, "LANES")
                    reaper.Main_OnCommand(42787, 0) -- Move selected items to new take lane
                    reaper.UpdateArrange() -- Give REAPER a moment
                else
                    ImportScript.LogMessage("Keeping item '" .. item_data.name .. "' in main lane", "LANES")
                end
            end
            
            ImportScript.LogMessage("Completed lane assignments for track '" .. track_name .. "'", "LANES")
        end
    end
    
    -- PHASE 4C: Process stereo pairs
    ImportScript.DebugPrint("\n--- PHASE 4C: PROCESSING STEREO PAIRS ---")
    ImportScript.LogMessage("Phase 4C: Processing stereo pairs", "ORGANIZE")
    
    -- Track which items are part of stereo pairs
    local processed_stereo_items = {}
    local stereo_pairs_created = 0
    
    -- Function to check if an item name matches a stereo pattern
    local function matchesStereoPattern(name, patterns)
        name = name:lower()
        for _, pattern in ipairs(patterns) do
            if name:match(pattern:lower()) then
                return true
            end
        end
        return false
    end
    
    -- Group items by their destination tracks
    local track_items = {}
    for _, item_data in ipairs(all_items) do
        -- Skip items with no matches or no destination track
        if #item_data.matches == 0 or not item_data.destination_track then
            goto continue_stereo_check
        end
        
        -- Skip already processed items
        if processed_stereo_items[item_data.item] then
            goto continue_stereo_check
        end
        
        -- Get track GUID for tracking
        local track_guid = reaper.GetTrackGUID(item_data.destination_track)
        if not track_guid then
            track_guid = "unknown_" .. math.random(10000)
        end
        
        -- Initialize array if not exists
        if not track_items[track_guid] then
            track_items[track_guid] = {
                track = item_data.destination_track,
                items = {}
            }
        end
        
        -- Add item to this track's list
        table.insert(track_items[track_guid].items, item_data)
        
        ::continue_stereo_check::
    end
    
    -- Now check each track for potential stereo pairs
    for track_guid, data in pairs(track_items) do
        local track = data.track
        local items = data.items
        
        -- Skip if only one item
        if #items <= 1 then
            goto continue_track_stereo
        end
        
        -- Get the configuration for the first item to check if this is a stereo pair candidate
        local item_data = items[1]
        if #item_data.matches == 0 then
            goto continue_track_stereo
        end
        
        local best_match = item_data.matches[1]
        local matched_config = best_match.config
        
        -- Skip if this config doesn't have stereo pair mode enabled
        if not matched_config.stereo_pair_mode or not matched_config.stereo_pair_patterns then
            goto continue_track_stereo
        end
        
        -- We have a stereo pair candidate track
        local _, track_name = reaper.GetTrackName(track)
        ImportScript.LogMessage("Checking for stereo pairs on track: '" .. track_name .. "'", "STEREO")
        
        -- Look for pairs among items on this track
        local stereo_pairs = {}
        
        -- First identify items by their stereo side (left/right) or position (hat/ride)
        for i, item_data in ipairs(items) do
            local side = nil
            
            -- Check which side this item belongs to
            for side_name, patterns in pairs(matched_config.stereo_pair_patterns) do
                if matchesStereoPattern(item_data.name, patterns) then
                    side = side_name
                    ImportScript.DebugPrint("  Item '" .. item_data.name .. "' matches stereo pattern: " .. side_name)
                    break
                end
            end
            
            -- If we identified a side, add it to potential pairs
            if side then
                if not stereo_pairs[side] then
                    stereo_pairs[side] = {}
                end
                table.insert(stereo_pairs[side], item_data)
            end
        end
        
        -- Now check for valid pairs
        for side1, items1 in pairs(stereo_pairs) do
            for side2, items2 in pairs(stereo_pairs) do
                -- Skip self-comparison
                if side1 == side2 then
                    goto continue_pair_check
                end
                
                -- We have a potential pair: side1 + side2
                ImportScript.DebugPrint("  Potential stereo pair found: " .. side1 .. " + " .. side2)
                
                -- We'll use the first item from each side to form a pair
                local item1 = items1[1]
                local item2 = items2[1]
                
                -- Check if items are at same position (important for stereo pairing)
                if math.abs(reaper.GetMediaItemInfo_Value(item1.item, "D_POSITION") - 
                            reaper.GetMediaItemInfo_Value(item2.item, "D_POSITION")) > 0.001 then
                    ImportScript.DebugPrint("  ✗ Items not at same position, skipping pair")
                    goto continue_pair_check
                end
                
                -- Valid pair found
                ImportScript.LogMessage("Found stereo pair: '" .. item1.name .. "' + '" .. item2.name .. "'", "STEREO")
                
                -- Select just these two items
                reaper.SelectAllMediaItems(0, false)
                reaper.SetMediaItemSelected(item1.item, true)
                reaper.SetMediaItemSelected(item2.item, true)
                
                -- Run the implode to stereo command
                ImportScript.LogMessage("Imploding items into stereo", "STEREO")
                reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS8edc98fd9236b06318e140bf38f9588b552c43dc"), 0)
                
                -- Mark these items as processed
                processed_stereo_items[item1.item] = true
                processed_stereo_items[item2.item] = true
                
                stereo_pairs_created = stereo_pairs_created + 1
                
                ::continue_pair_check::
            end
        end
        
        ::continue_track_stereo::
    end
    
    if stereo_pairs_created > 0 then
        ImportScript.LogMessage("Created " .. stereo_pairs_created .. " stereo pairs", "SUMMARY")
    end
    
    -- PHASE 5: Create comps for tracks with take lanes
    if next(tracks_with_lanes) then
        ImportScript.DebugPrint("\n--- PHASE 5: CREATING COMPS FOR LANES ---")
        ImportScript.LogMessage("Phase 5: Creating comps for tracks with take lanes", "ORGANIZE")
        
        -- Process each track that has take lanes
        local comp_count = 0
        for guid, track in pairs(tracks_with_lanes) do
            if track_item_counts[guid] and track_item_counts[guid].count > 1 then
                local _, track_name = reaper.GetTrackName(track)
                ImportScript.LogMessage("Creating comp for track: '" .. track_name .. "' with " .. track_item_counts[guid].count .. " items", "COMP")
                
                -- IMPORTANT: First deselect all items
                reaper.SelectAllMediaItems(0, false)
                
                -- IMPORTANT: Select the track itself, not its items
                -- Deselect all tracks first
                local num_tracks = reaper.CountTracks(0)
                for i = 0, num_tracks - 1 do
                    local cur_track = reaper.GetTrack(0, i)
                    reaper.SetTrackSelected(cur_track, false)
                end
                
                -- Select only our target track
                reaper.SetTrackSelected(track, true)
                ImportScript.DebugPrint("  Selected track: '" .. track_name .. "' for comp creation")
                
                -- Wait a moment for UI to settle
                reaper.UpdateArrange()
                
                -- Execute action to create comp (ID: 42798) - this requires track selection, not item selection
                ImportScript.LogMessage("Running action 42798 to create comp for track: '" .. track_name .. "'", "COMP")
                reaper.Main_OnCommand(42798, 0) -- Auto-create new comp from selected items
                
                comp_count = comp_count + 1
                ImportScript.DebugPrint("  Created comp for track: '" .. track_name .. "'")
            end
        end
        
        ImportScript.LogMessage("Created " .. comp_count .. " comps for tracks with take lanes", "SUMMARY")
    end
    
    -- Handle unmatched items and items with track creation failures - move them to NOT SORTED folder
    local not_sorted_count = 0
    if unmatched_items > 0 or track_creation_failed_items > 0 then
        ImportScript.DebugPrint("\n--- HANDLING UNMATCHED ITEMS AND TRACK CREATION FAILURES ---")
        ImportScript.LogMessage("Processing " .. (unmatched_items + track_creation_failed_items) .. " items to move to NOT SORTED", "ORGANIZE")
        
        -- Find or create NOT SORTED folder
        local not_sorted_folder = nil
        local track_count = reaper.CountTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = reaper.GetTrackName(track)
            
            if track_name == "NOT SORTED" then
                not_sorted_folder = track
                ImportScript.DebugPrint("  Found existing NOT SORTED folder")
                ImportScript.LogMessage("Using existing NOT SORTED folder", "TRACK")
                break
            end
        end
        
        -- Create NOT SORTED folder if it doesn't exist
        if not not_sorted_folder then
            ImportScript.DebugPrint("  Creating NOT SORTED folder")
            ImportScript.LogMessage("Creating NOT SORTED folder", "CREATE")
            
            -- Create the track
            reaper.InsertTrackAtIndex(track_count, true)
            not_sorted_folder = reaper.GetTrack(0, track_count)
            
            if not_sorted_folder then
                -- Set the track name
                reaper.GetSetMediaTrackInfo_String(not_sorted_folder, "P_NAME", "NOT SORTED", true)
                
                -- Set it as a folder
                reaper.SetMediaTrackInfo_Value(not_sorted_folder, "I_FOLDERDEPTH", 1)
                
                ImportScript.DebugPrint("    ✓ Created NOT SORTED folder")
                ImportScript.LogMessage("Successfully created NOT SORTED folder", "CREATE")
            else
                ImportScript.DebugPrint("    ✗ Failed to create NOT SORTED folder")
                ImportScript.LogMessage("Failed to create NOT SORTED folder", "ERROR")
            end
        end
        
        -- Move unmatched items and items with track creation failures to individual tracks under NOT SORTED folder
        if not_sorted_folder then
            -- Make sure the NOT SORTED track is set as a folder
            reaper.SetMediaTrackInfo_Value(not_sorted_folder, "I_FOLDERDEPTH", 1)
            
            -- Find the folder end using the same approach as above
            local folder_idx = reaper.GetMediaTrackInfo_Value(not_sorted_folder, "IP_TRACKNUMBER") - 1
            local folder_depth = 1  -- Start at depth 1 (inside folder)
            local folder_end_idx = -1
            
            -- Find the end of the folder
            for i = folder_idx + 1, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                local depth_change = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                
                folder_depth = folder_depth + depth_change
                
                if folder_depth <= 0 then
                    folder_end_idx = i
                    break
                end
            end
            
            -- If no folder end found, assume it's at the end of the project
            if folder_end_idx == -1 then
                folder_end_idx = reaper.CountTracks(0)
            end
            
            -- Current insertion point starts at the folder end
            local insert_idx = folder_end_idx
            
            for _, item_data in ipairs(all_items) do
                if #item_data.matches == 0 or not item_data.destination_track then
                    local take = reaper.GetActiveTake(item_data.item)
                    local take_name = take and reaper.GetTakeName(take) or "Unknown Item"
                    
                    ImportScript.DebugPrint("  Creating child track for unmatched item: '" .. take_name .. "'")
                    
                    -- Create a new track at the current insertion point 
                    -- (inserting at folder_end_idx pushes the existing end track forward)
                    reaper.InsertTrackAtIndex(insert_idx, true)
                    local child_track = reaper.GetTrack(0, insert_idx)
                    
                    if child_track then
                        -- Set track name to take name for easy identification
                        reaper.GetSetMediaTrackInfo_String(child_track, "P_NAME", take_name, true)
                        
                        -- Configure it as a child track (indentation)
                        local parent_tcp_depth = reaper.GetMediaTrackInfo_Value(not_sorted_folder, "I_TCPDEPTH")
                        reaper.SetMediaTrackInfo_Value(child_track, "I_TCPDEPTH", parent_tcp_depth + 1)
                        reaper.SetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH", 0)  -- Regular track, not a folder
                        
                        -- Move item to this track
                        reaper.MoveMediaItemToTrack(item_data.item, child_track)
                        
                not_sorted_count = not_sorted_count + 1
                        
                        -- Each time we insert a track, folder_end_idx gets pushed forward
                        insert_idx = insert_idx + 1
                        folder_end_idx = folder_end_idx + 1
                        
                        ImportScript.LogMessage("Created track for unmatched item '" .. take_name .. "' under NOT SORTED folder", "MOVE")
                    else
                        ImportScript.LogMessage("Failed to create track for unmatched item '" .. take_name .. "'", "ERROR")
                    end
                end
            end
            
            -- Make sure the NOT SORTED folder is still a folder after adding all children
            if not_sorted_count > 0 then
                reaper.SetMediaTrackInfo_Value(not_sorted_folder, "I_FOLDERDEPTH", 1) 
            end
        end
    end
    
    -- Handle delete empty tracks option
    local deleted_tracks = 0
    local configs = ImportScript.LoadConfigs()
    if configs and configs.delete_empty_tracks then
        ImportScript.DebugPrint("\n--- CHECKING FOR EMPTY SOURCE TRACKS ---")
        ImportScript.LogMessage("Checking for empty source tracks to delete", "TRACK")
        
        -- Sort source tracks by index (in reverse order to avoid issues when deleting)
        local source_track_array = {}
        for _, track in pairs(source_tracks) do
            table.insert(source_track_array, track)
        end
        
        table.sort(source_track_array, function(a, b)
            local idx_a = reaper.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER")
            local idx_b = reaper.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER")
            return idx_a > idx_b
        end)
        
        -- Check each source track for emptiness
        for _, track in ipairs(source_track_array) do
            local item_count = reaper.GetTrackNumMediaItems(track)
            if item_count == 0 then
                local _, track_name = reaper.GetTrackName(track)
                ImportScript.DebugPrint("  Track '" .. track_name .. "' is now empty, deleting")
                ImportScript.LogMessage("Deleting empty track '" .. track_name .. "'", "TRACK")
                
                -- Delete the track
                local track_idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
                reaper.DeleteTrack(track)
                deleted_tracks = deleted_tracks + 1
            end
        end
    end
    
    ImportScript.DebugPrint("\n=== SUMMARY ===")
    ImportScript.DebugPrint("Items organized: " .. items_organized)
    ImportScript.DebugPrint("Items skipped: " .. items_skipped)
    ImportScript.DebugPrint("Unmatched items: " .. not_sorted_count)
    if deleted_tracks > 0 then
        ImportScript.DebugPrint("Empty tracks deleted: " .. deleted_tracks)
    end
    
    -- Add summary to logs
    ImportScript.LogMessage("Organization complete: " .. items_organized .. " items organized, " .. items_skipped .. " items skipped", "SUMMARY")
    if unmatched_items > 0 then
        ImportScript.LogMessage("Unmatched items: " .. not_sorted_count .. " items moved to NOT SORTED folder", "SUMMARY")
    end
    if deleted_tracks > 0 then
        ImportScript.LogMessage("Empty tracks deleted: " .. deleted_tracks, "SUMMARY")
    end
    
    -- End undo block
    reaper.Undo_EndBlock("Organize selected items", -1)
    
    -- Resume UI refreshing and update the arrange view
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    
    -- Store the organization summary message instead of showing a popup
    local summary_message = string.format("Organization complete: %d items organized, %d items skipped", 
                            items_organized, items_skipped)
    
    if not_sorted_count > 0 then
        summary_message = summary_message .. string.format(", %d unmatched items moved to NOT SORTED", not_sorted_count)
    end
    
    if deleted_tracks > 0 then
        summary_message = summary_message .. string.format(", %d empty tracks deleted", deleted_tracks)
    end
    
    ImportScript.LastMessage = summary_message
    ImportScript.LastMessageTime = os.time()
end

-- Add the logging functions to the ImportScript
function ImportScript.LogMessage(message, category)
    -- Add timestamp to message
    local timestamp = os.date("%H:%M:%S")
    local formatted_message = timestamp .. " - " .. (message or "")
    
    -- Add category tag if provided
    if category then
        formatted_message = "[" .. category .. "] " .. formatted_message
    end
    
    -- Add to log array
    table.insert(ImportScript.LogMessages, 1, formatted_message) -- Insert at beginning for newest-first
    
    -- Limit log size
    if #ImportScript.LogMessages > ImportScript.MaxLogs then
        table.remove(ImportScript.LogMessages) -- Remove oldest entry
    end
    
    -- Also output to console if in debug mode
    if ImportScript.DebugMode then
        reaper.ShowConsoleMsg(formatted_message .. "\n")
    end
end

function ImportScript.ClearLogs()
    ImportScript.LogMessages = {}
    ImportScript.LogMessage("Logs cleared", "SYSTEM")
end

function ImportScript.GetLogs()
    return ImportScript.LogMessages
end

-- Load general configuration from ExtState
function ImportScript.LoadConfigs()
    -- Get user-defined configurations
    local configs_json = reaper.GetExtState("FastTrackStudio_ImportByName", "configs")
    local configs = {}
    
    if configs_json ~= "" then
        local ok, parsed = pcall(json.decode, configs_json)
        if ok and parsed then
            configs = parsed
        end
    end
    
    -- Set defaults for missing values
    if configs.ToolTips == nil then
        configs.ToolTips = true
    end
    
    if configs.parent_prefix == nil then
        configs.parent_prefix = "+"
    end
    
    if configs.parent_suffix == nil then
        configs.parent_suffix = "+"
    end
    
    if configs.pre_filter == nil then
        configs.pre_filter = ""
    end
    
    if configs.global_rename_track == nil then
        configs.global_rename_track = false
    end
    
    if configs.delete_empty_tracks == nil then
        configs.delete_empty_tracks = false
    end
    
    return configs
end

-- Save general configuration to ExtState
function ImportScript.SaveConfigs(configs)
    if not configs then
        configs = {}
    end
    
    local ok, configs_json = pcall(json.encode, configs)
    if not ok or not configs_json then
        configs_json = "{}"
    end
    
    reaper.SetExtState("FastTrackStudio_ImportByName", "configs", configs_json, true)
end

-- Analyze selected items for pattern matches
function ImportScript.AnalyzeSelectedItems()
    -- Debug output to console for troubleshooting
    reaper.ShowConsoleMsg("\n=== AnalyzeSelectedItems Function Called ===\n")
    
    -- Check if any items are selected
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        reaper.ShowMessageBox("No items selected. Please select items to analyze.", "No Items Selected", 0)
        ImportScript.LogMessage("Analysis failed: No items selected", "ERROR")
        return
    end
    
    -- Log the start of analysis (once at the beginning)
    ImportScript.LogMessage("Starting pattern analysis for " .. item_count .. " selected items", "ANALYZE")
    
    -- Load required modules
    local PatternMatching = dofile(reaper.GetResourcePath() .. "/Scripts/FastTrackStudio Scripts/libraries/utils/Pattern Matching.lua")
    
    -- Get available track configurations
    local track_configs = ImportScript.LoadTrackConfigs()
    
    -- Load global patterns for category extraction
    local DefaultPatterns = require("default_patterns")
    local ext_state_name = "FastTrackStudio_ImportByName"
    local global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, ImportScript)
    
    -- Debug: Output number of track configs and global patterns
    reaper.ShowConsoleMsg("Track configs: " .. (next(track_configs) and table.concat(GetTableKeys(track_configs), ", ") or "None") .. "\n")
    reaper.ShowConsoleMsg("Global patterns available: " .. (global_patterns and "Yes" or "No") .. "\n")
    
    -- Log available global patterns
    ImportScript.LogMessage("Available global pattern categories:", "PATTERN")
    for category, patterns in pairs(global_patterns) do
        if patterns.patterns and #patterns.patterns > 0 then
            ImportScript.LogMessage("  - " .. category .. ": " .. table.concat(patterns.patterns, ", "), "PATTERN")
        end
    end
    
    -- Log groups with custom subtypes
    ImportScript.LogMessage("Groups with custom subtypes:", "PATTERN")
    local has_custom_subtypes = false
    for name, config in pairs(track_configs) do
        if config.subtypes and #config.subtypes > 0 then
            has_custom_subtypes = true
            ImportScript.LogMessage("  - " .. name .. ": " .. table.concat(config.subtypes, ", "), "PATTERN")
        end
    end
    if not has_custom_subtypes then
        ImportScript.LogMessage("  - None found (will use global subtypes instead)", "PATTERN")
    end
    
    -- Analyze each selected item
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            
            -- Log item separator and name
            ImportScript.LogMessage("---------------------------------------", "ANALYZE")
            ImportScript.LogMessage("Analyzing item: '" .. take_name .. "'", "ANALYZE")
            
            -- Find matching track configurations
            local matched_configs = {}
            
            for name, config in pairs(track_configs) do
                if config.patterns and #config.patterns > 0 then
                    local matches, pattern = PatternMatching.MatchesAnyPattern(take_name, config.patterns)
                    if matches then
                        -- Check negative patterns
                        local negative_match = PatternMatching.MatchesNegativePattern(take_name, config.negative_patterns or {})
                        if not negative_match then
                            table.insert(matched_configs, {
                                name = name,
                                pattern = pattern,
                                config = config
                            })
                        end
                    end
                end
            end
            
            -- Log matched configurations
            if #matched_configs > 0 then
                ImportScript.LogMessage("Group Matches:", "ANALYZE")
                for _, match in ipairs(matched_configs) do
                    ImportScript.LogMessage("  - " .. match.name .. " (pattern: " .. match.pattern .. ")", "ANALYZE")
                    
                    -- Show destination track
                    local destination = match.config.destination_track or match.name
                    ImportScript.LogMessage("    → Destination track: " .. destination, "ANALYZE")
                    
                    -- Show parent track if set
                    if match.config.parent_track and match.config.parent_track ~= "" then
                        ImportScript.LogMessage("    → Parent folder: " .. match.config.parent_track, "ANALYZE")
                    end
                    
                    -- Show custom subtypes if available
                    if match.config.subtypes and #match.config.subtypes > 0 then
                        ImportScript.LogMessage("    → Group-specific subtypes: " .. table.concat(match.config.subtypes, ", "), "ANALYZE")
                        ImportScript.LogMessage("      (These subtypes will override global subtypes for this group)", "ANALYZE")
                    else
                        ImportScript.LogMessage("    → No group-specific subtypes (will use global subtypes)", "ANALYZE")
                    end
                    
                    -- Show rename track setting
                    local configs = ImportScript.LoadConfigs()
                    local rename_state = "No"
                    if configs.global_rename_track then
                        rename_state = "Yes (from global setting)"
                    elseif match.config.rename_track then
                        rename_state = "Yes (from track config)"
                    end
                    ImportScript.LogMessage("    → Rename track: " .. rename_state, "ANALYZE")
                end
            else
                ImportScript.LogMessage("Group Matches: None - will go to NOT SORTED folder", "ANALYZE")
            end
            
            -- Extract and log pattern categories
            -- Use the best matched group for extracting categories
            local matched_group = nil
            if #matched_configs > 0 then
                matched_group = matched_configs[1].config
            end
            local categories = ExtractPatternCategories(take_name, global_patterns, track_configs, matched_group, true)
            
            -- Log each category type
            ImportScript.LogMessage("Pattern Categories:", "ANALYZE")
            
            -- Create an ordered list of categories to check
            local category_order = {
                {"Prefix", "prefix"},
                {"Tracking Info", "tracking"},
                {"SubType", "subtype"},
                {"Arrangement", "arrangement"},
                {"Performer", "performer"},
                {"Section", "section"},
                {"Layers", "layers"},
                {"Mic", "mic"},
                {"Playlist", "playlist"},
                {"Type", "type"}
            }
            
            -- Check each category in order
            for _, cat in ipairs(category_order) do
                local display_name = cat[1]
                local key = cat[2]
                
                if categories[key] then
                    ImportScript.LogMessage("  - " .. display_name .. ": " .. categories[key], "ANALYZE")
                    
                    -- Add special note for subtypes
                    if key == "subtype" and matched_group and matched_group.subtypes and #matched_group.subtypes > 0 then
                        ImportScript.LogMessage("    (Using " .. matched_group.name .. "-specific subtype)", "ANALYZE")
                    end
                else
                    ImportScript.LogMessage("  - " .. display_name .. ": None", "ANALYZE")
                end
            end
            
            -- Generate track name based on patterns
            if #matched_configs > 0 then
                local config = matched_configs[1].config
                local configs = ImportScript.LoadConfigs()
                -- Check if global rename is enabled or track config has rename enabled
                if configs.global_rename_track or config.rename_track then
                    local base_name = config.destination_track or matched_configs[1].name
                    local track_name = GenerateTrackNameFromCategories(base_name, categories)
                    ImportScript.LogMessage("Generated track name: '" .. track_name .. "'", "ANALYZE")
                end
            end
        else
            ImportScript.LogMessage("Item #" .. i+1 .. " has no active take, skipping", "ANALYZE")
        end
    end
    
    ImportScript.LogMessage("Analysis complete for " .. item_count .. " items", "ANALYZE")
    ImportScript.LogMessage("See the 'Logs' tab for detailed results", "ANALYZE")
    
    -- Set status message
    ImportScript.LastMessage = "Analysis complete for " .. item_count .. " items. See Logs tab for details."
    ImportScript.LastMessageTime = os.time()
end

-- Function to generate a random name for testing pattern matching
function ImportScript.TestRandomNameGeneration(random_order)
    -- Check if any items are selected
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        reaper.ShowMessageBox("No items selected. Please select items to test.", "No Items Selected", 0)
        ImportScript.LogMessage("Test failed: No items selected", "ERROR")
        return
    end
    
    -- Load required modules
    local DefaultPatterns = require("default_patterns")
    local ext_state_name = "FastTrackStudio_ImportByName"
    local global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, ImportScript)
    
    -- Set a random seed based on current time to ensure different results each time
    math.randomseed(os.time())
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Load track configs
    local track_configs = ImportScript.LoadTrackConfigs()
    
    -- Process each selected item
    for i = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            
            -- Create a new categories table with randomly selected patterns
            local categories = {}
            
            -- Helper function to get random pattern from a category
            local function getRandomPattern(category)
                if not category or not category.patterns then return nil end
                local patterns = category.patterns
                if #patterns == 0 then return nil end
                return patterns[math.random(1, #patterns)]
            end
            
            -- Define the order of categories
            local category_order = {
                {key = "prefix", name = "Prefix"},
                {key = "tracking", name = "Tracking Info"},
                {key = "subtype", name = "SubType"},
                {key = "arrangement", name = "Arrangement"},
                {key = "performer", name = "Performer"},
                {key = "section", name = "Section"},
                {key = "layers", name = "Layers"},
                {key = "mic", name = "Mic"},
                {key = "playlist", name = "Playlist"},
                {key = "type", name = "Type"}
            }
            
            -- If random order is requested, shuffle the category order
            if random_order then
                for i = #category_order, 2, -1 do
                    local j = math.random(1, i)
                    category_order[i], category_order[j] = category_order[j], category_order[i]
                end
            end
            
            -- First, select a random group
            local group_names = {}
            for name, _ in pairs(track_configs) do
                table.insert(group_names, name)
            end
            
            if #group_names == 0 then
                ImportScript.LogMessage("No track configuration groups found", "ERROR")
                return
            end
            
            local random_group_name = group_names[math.random(1, #group_names)]
            local random_group = track_configs[random_group_name]
            
            -- Get the parent group prefix if this is a subgroup
            local parent_prefix = ""
            if random_group.parent_group then
                -- Find the parent group
                for name, group in pairs(track_configs) do
                    if name == random_group.parent_group then
                        parent_prefix = group.prefix or ""
                        ImportScript.LogMessage("Using parent group prefix: " .. parent_prefix, "TEST")
                        break
                    end
                end
            end
            
            -- Combine parent prefix with group name (not just prefix) if this is a subgroup
            local final_prefix = parent_prefix
            if random_group.parent_group then
                -- Use the full group name instead of just the prefix
                if parent_prefix ~= "" then
                    final_prefix = parent_prefix .. " " .. random_group.name
                else
                    final_prefix = random_group.name
                end
                ImportScript.LogMessage("Using parent prefix with full group name: " .. final_prefix, "TEST")
            elseif random_group.prefix then
                -- If not a subgroup, just use the group's prefix
                final_prefix = random_group.prefix
                ImportScript.LogMessage("Using group prefix: " .. final_prefix, "TEST")
            end
            
            -- Set the prefix in the categories table
            categories.prefix = final_prefix
            ImportScript.LogMessage("Using final prefix: " .. final_prefix, "TEST")
            
            -- Generate random patterns for other categories
            for _, cat in ipairs(category_order) do
                -- Skip prefix as we've already handled it
                if cat.key ~= "prefix" then
                    -- Special handling for subtype - use group-specific subtypes if available
                    if cat.key == "subtype" and random_group.subtypes and #random_group.subtypes > 0 then
                        -- Use group-specific subtypes
                        local subtypes = random_group.subtypes
                        -- 70% chance to include subtype
                        if math.random() > 0.3 and #subtypes > 0 then
                            categories.subtype = subtypes[math.random(1, #subtypes)]
                            ImportScript.LogMessage("Added group-specific subtype: " .. categories.subtype, "TEST")
                        end
                    else
                        -- Use global patterns for other categories
                        local pattern = getRandomPattern(global_patterns[cat.key])
                        if pattern then
                            -- 70% chance to include each subcategory
                            if math.random() > 0.3 then
                                categories[cat.key] = pattern
                                ImportScript.LogMessage("Added random " .. cat.name .. " pattern: " .. pattern, "TEST")
                            end
                        end
                    end
                end
            end
            
            -- Generate the full name using the existing function
            -- Use an empty string as the base name to start fresh
            local generated_name = GenerateTrackNameFromCategories("", categories)
            
            -- Rename the take with the completely new name
            reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", generated_name, true)
            ImportScript.LogMessage("Generated test name: " .. generated_name, "TEST")
        end
    end
    
    -- End undo block
    reaper.Undo_EndBlock("Generate random test names", -1)
    
    -- Set status message
    ImportScript.LastMessage = "Generated random test names for " .. item_count .. " items"
    ImportScript.LastMessageTime = os.time()
end

-- Load modules
local Utils = require("utils")
local MainGUI = require("main_gui")

-- Initialize global settings from configs
local configs = ImportScript.LoadConfigs()
ImportScript.GlobalRenameTrack = configs.global_rename_track
ImportScript.DeleteEmptyTracks = configs.delete_empty_tracks

-- Start the GUI
MainGUI.Init(ImportScript)

-- Export functions for the main script interface
return {
    LoadConfigs = ImportScript.LoadConfigs,
    SaveConfigs = ImportScript.SaveConfigs,
    LoadTrackConfigs = ImportScript.LoadTrackConfigs,
    SaveTrackConfigs = ImportScript.SaveTrackConfigs,
    ImportFromFile = ImportFromFile,
    OrganizeSelectedItems = ImportScript.OrganizeSelectedItems,
    MoveSelectedItems = MoveSelectedItems,
    ResetTrackConfigs = ImportScript.ResetTrackConfigs,
    DebugMode = ImportScript.DebugMode,
    DebugPrint = ImportScript.DebugPrint,
    LastMessage = ImportScript.LastMessage,
    LastMessageTime = ImportScript.LastMessageTime,
    GlobalRenameTrack = ImportScript.GlobalRenameTrack, -- Use the value from ImportScript
    DeleteEmptyTracks = ImportScript.DeleteEmptyTracks, -- Use the value for deleting empty tracks
    -- Add logging functionality
    LogMessage = ImportScript.LogMessage,
    ClearLogs = ImportScript.ClearLogs,
    GetLogs = ImportScript.GetLogs,
    LogMessages = ImportScript.LogMessages,
    AnalyzeSelectedItems = ImportScript.AnalyzeSelectedItems,
    TestRandomNameGeneration = ImportScript.TestRandomNameGeneration
} 