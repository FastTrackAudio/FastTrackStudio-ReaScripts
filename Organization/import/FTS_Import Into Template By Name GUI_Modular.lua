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
                        local matches, pattern = MatchesAnyPattern(file_name, config.patterns)
                        if matches then
                            -- Check negative patterns
                            local negative_match = MatchesNegativePattern(file_name, config.negative_patterns or {})
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
                                            local new_name = MatchesAnyPattern(file_name, matched_config.patterns)
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
function ExtractPatternCategories(item_name, global_patterns, log_matches)
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
        
        -- Check for subtype
        local subtype_patterns = getPatterns(global_patterns.subtype)
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

-- Now, modify the OrganizeSelectedItems function to handle unmatched items and delete empty source tracks
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
    
    -- First, classify all items by their matching configurations
    local classified_items = {}
    local all_items = {}
    local unmatched_item_list = {} -- List to store unmatched items
    local items_organized = 0
    local items_skipped = 0
    local unmatched_items = 0
    local source_tracks = {} -- Keep track of source tracks to check for emptiness later
    
    -- Store items by their matched configuration
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
            
            ImportScript.DebugPrint("\nClassifying item: '" .. take_name .. "'")
            ImportScript.DebugPrint("  Item details:")
            ImportScript.DebugPrint("    - Name (lowercase): '" .. take_name:lower() .. "'")
            ImportScript.DebugPrint("    - Start: " .. item_start .. ", End: " .. item_end)
            
            -- Find a matching track configuration
            local matched_config = nil
            local matched_name = nil
            local matched_pattern = nil
            
            for name, config in pairs(track_configs) do
                ImportScript.DebugPrint("    Checking config: " .. name)
                
                if config.patterns and #config.patterns > 0 then
                    local matches, pattern = PatternMatching.MatchesAnyPattern(take_name, config.patterns)
                    if matches then
                        -- Check negative patterns
                        local negative_match = PatternMatching.MatchesNegativePattern(take_name, config.negative_patterns or {})
                        if not negative_match then
                            matched_config = config
                            matched_name = name
                            matched_pattern = pattern
                            ImportScript.DebugPrint("      ✓ MATCHED with config: '" .. name .. "', pattern: '" .. pattern .. "'")
                            ImportScript.LogMessage("Item '" .. take_name .. "' matched config: '" .. name .. "' with pattern: '" .. pattern .. "'", "MATCH")
                            break
                        end
                    end
                end
            end
            
            if matched_config then
                -- Add to classified items
                if not classified_items[matched_name] then
                    classified_items[matched_name] = {
                        config = matched_config,
                        items = {}
                    }
                end
                
                table.insert(classified_items[matched_name].items, {
                    item = item,
                    take = take,
                    name = take_name,
                    start = item_start,
                    end_time = item_end,
                    pattern = matched_pattern
                })
                
                table.insert(all_items, {
                    item = item,
                    take = take,
                    name = take_name,
                    config_name = matched_name,
                    config = matched_config,
                    start = item_start,
                    end_time = item_end,
                    pattern = matched_pattern
                })
            else
                ImportScript.DebugPrint("    ✗ No matching configuration found")
                ImportScript.LogMessage("Item '" .. take_name .. "' has no matching configuration", "UNMATCH")
                items_skipped = items_skipped + 1
                unmatched_items = unmatched_items + 1
                
                -- Add to unmatched items list
                table.insert(unmatched_item_list, {
                    item = item,
                    take = take,
                    name = take_name,
                    start = item_start,
                    end_time = item_end
                })
            end
        else
            ImportScript.DebugPrint("  ✗ SKIPPED: Item has no take")
            ImportScript.LogMessage("Skipped an item without a take", "SKIP")
            items_skipped = items_skipped + 1
        end
    end
    
    -- Sort all items by start time (for consistent processing)
    table.sort(all_items, function(a, b) return a.start < b.start end)
    
    -- For each group of items by configuration, process them
    local created_tracks = {} -- Track destination tracks we've created
    
    -- Load global patterns for track renaming
    local DefaultPatterns = require("default_patterns")
    local ext_state_name = "FastTrackStudio_ImportByName" -- Define the ext_state_name
    local global_patterns = DefaultPatterns.LoadGlobalPatterns(ext_state_name, ImportScript)
    
    ImportScript.DebugPrint("\n--- ORGANIZING ITEMS ---")
    ImportScript.LogMessage("Processing " .. #all_items .. " matched items", "ORGANIZE")
    
    for _, item_data in ipairs(all_items) do
        ImportScript.DebugPrint("Processing item: '" .. item_data.name .. "' with config: " .. item_data.config_name)
        
        -- Get parent track
        local parent_track = TrackConfig.FindTrackByGUIDWithFallback(
            item_data.config.parent_track_guid, 
            item_data.config.parent_track
        )
        
        if parent_track then
            local _, parent_name = reaper.GetTrackName(parent_track)
            ImportScript.DebugPrint("  Found parent track: '" .. parent_name .. "'")
            ImportScript.LogMessage("Using parent track: '" .. parent_name .. "'", "TRACK")
        else
            ImportScript.DebugPrint("  No parent track found")
            ImportScript.LogMessage("No parent track found for config: '" .. item_data.config_name .. "'", "TRACK")
        end
        
        -- Determine destination track name (base name)
        local base_track_name = item_data.config.destination_track or item_data.config_name
        ImportScript.DebugPrint("  Base destination track name: '" .. base_track_name .. "'")
        
        -- Extract pattern categories from item name for possible track renaming
        local categories = {}
        -- Always extract categories for item name generation, regardless of rename_track setting
        categories = ExtractPatternCategories(item_data.name, global_patterns, true)
        ImportScript.DebugPrint("  Extracted categories for item name generation: " .. ImportScript.GetTableSize(categories))
        
        -- Check if we already have tracks for this configuration
        local config_tracks = created_tracks[item_data.config_name] or {}
        local destination_track = nil
        local track_idx = 0
        
        -- Check if the item can go into an existing track (no overlap, exact name match)
        local can_use_existing = false
        local best_track = nil
        
        ImportScript.DebugPrint("  Checking " .. #config_tracks .. " existing tracks for this configuration")
        
        -- First, check tracks we've already created during this organization
        if #config_tracks > 0 then
            for idx, track_info in ipairs(config_tracks) do
                -- Check if any item on this track has the exact same name
                local exact_name_match = false
                for _, track_item in ipairs(track_info.items) do
                    if track_item.name == item_data.name then
                        exact_name_match = true
                        ImportScript.DebugPrint("    Found exact name match on track " .. idx)
                        break
                    end
                end
                
                -- If we have an exact name match, check for overlap
                if exact_name_match then
                    local overlaps = false
                    for _, track_item in ipairs(track_info.items) do
                        -- Check if items overlap
                        if (item_data.start < track_item.end_time and item_data.end_time > track_item.start) then
                            overlaps = true
                            ImportScript.DebugPrint("    Item overlaps with existing item on track " .. idx)
                            ImportScript.LogMessage("Item '" .. item_data.name .. "' overlaps with existing item on track '" .. track_info.name .. "'", "OVERLAP")
                            break
                        end
                    end
                    
                    if not overlaps then
                        can_use_existing = true
                        best_track = track_info
                        track_idx = idx
                        ImportScript.DebugPrint("    ✓ Can use existing track " .. idx .. " (exact name match, no overlap)")
                        ImportScript.LogMessage("Using existing track '" .. track_info.name .. "' for item '" .. item_data.name .. "'", "TRACK")
                        break
                    else
                        ImportScript.DebugPrint("    ✗ Cannot use track " .. idx .. " due to overlap")
                    end
                else
                    ImportScript.DebugPrint("    ✗ No exact name match on track " .. idx)
                end
            end
        else
            ImportScript.DebugPrint("  No existing tracks created during this organization for this configuration")
        end
        
        -- If we couldn't find a matching track we created, check for an existing destination track in the project
        if not can_use_existing then
            -- First, check if a track with the exact base name exists
            local possible_track_name = base_track_name
            
            -- Check if global rename is enabled or track-specific rename is enabled
            local configs = ImportScript.LoadConfigs and ImportScript.LoadConfigs() or {}
            local global_rename_enabled = configs.global_rename_track
            local should_rename = global_rename_enabled or item_data.config.rename_track
            
            -- If rename is enabled, add categories
            if should_rename and next(categories) then
                possible_track_name = GenerateTrackNameFromCategories(base_track_name, categories)
                ImportScript.DebugPrint("  Generated track name with categories: '" .. possible_track_name .. "'")
            end
            
            local track_count = reaper.CountTracks(0)
            for i = 0, track_count - 1 do
                local track = reaper.GetTrack(0, i)
                local _, track_name = reaper.GetTrackName(track)
                
                -- If track name matches our possible destination
                if track_name == possible_track_name then
                    ImportScript.DebugPrint("  Found existing project track: '" .. track_name .. "'")
                    
                    -- Check for overlaps with existing items on this track
                    local overlaps = false
                    local item_count = reaper.GetTrackNumMediaItems(track)
                    
                    for j = 0, item_count - 1 do
                        local existing_item = reaper.GetTrackMediaItem(track, j)
                        local existing_item_start = reaper.GetMediaItemInfo_Value(existing_item, "D_POSITION")
                        local existing_item_end = existing_item_start + reaper.GetMediaItemInfo_Value(existing_item, "D_LENGTH")
                        
                        -- Check if items overlap
                        if (item_data.start < existing_item_end and item_data.end_time > existing_item_start) then
                            overlaps = true
                            ImportScript.DebugPrint("    Item overlaps with existing project item on track")
                            ImportScript.LogMessage("Item '" .. item_data.name .. "' overlaps with existing project item on track '" .. track_name .. "'", "OVERLAP")
                            break
                        end
                    end
                    
                    if not overlaps then
                        can_use_existing = true
                        destination_track = track
                        ImportScript.DebugPrint("    ✓ Can use existing project track (no overlap)")
                        ImportScript.LogMessage("Using existing project track '" .. track_name .. "' for item '" .. item_data.name .. "'", "TRACK")
                        
                        -- Create a track_info structure for this project track
                        best_track = {
                            track = track,
                            name = track_name,
                            items = {} -- Start with no items listed
                        }
                        
                        -- Add to our tracked list
                        table.insert(config_tracks, best_track)
                        created_tracks[item_data.config_name] = config_tracks
                        break
                    else
                        ImportScript.DebugPrint("    ✗ Cannot use existing project track due to overlap")
                    end
                end
            end
        end
        
        -- If we can't use an existing track, create a new one with incremented name
        if not can_use_existing then
            ImportScript.DebugPrint("  Need to create a new track for this item")
            
            -- Determine the track increment
            local increment_start = item_data.config.increment_start or 1
            track_idx = #config_tracks + 1
            
            -- Build the track name
            local track_name = base_track_name
            
            -- Only add number if needed
            local should_number = true
            if item_data.config.only_number_when_multiple and track_idx == 1 then
                should_number = false
            end
            
            if should_number then
                track_name = track_name .. " " .. (increment_start + track_idx - 1)
            end
            
            -- If rename_track is enabled, add categories
            if item_data.config.rename_track and next(categories) then
                track_name = GenerateTrackNameFromCategories(track_name, categories)
                ImportScript.DebugPrint("  Generated track name with categories: '" .. track_name .. "'")
            end
            
            ImportScript.DebugPrint("  Creating new track: '" .. track_name .. "'")
            local numbering_msg = ""
            if should_number then
                numbering_msg = " (with numbering)"
            end
            ImportScript.LogMessage("Creating new track: '" .. track_name .. "'" .. numbering_msg, "CREATE")
            
            -- Create the track
            destination_track = TrackManagement.FindOrCreateTrack(track_name, nil, parent_track, true)
            
            if destination_track then
                local track_idx = reaper.GetMediaTrackInfo_Value(destination_track, "IP_TRACKNUMBER")
                ImportScript.DebugPrint("    ✓ Created new track: '" .. track_name .. "'")
                ImportScript.LogMessage("Successfully created track '" .. track_name .. "' at position " .. track_idx, "CREATE")
                
                -- Add to our list of created tracks
                table.insert(config_tracks, {
                    track = destination_track,
                    name = track_name,
                    items = {}
                })
                
                created_tracks[item_data.config_name] = config_tracks
                best_track = config_tracks[#config_tracks]
            else
                ImportScript.DebugPrint("    ✗ Failed to create track: TrackManagement.FindOrCreateTrack returned nil")
                ImportScript.LogMessage("Failed to create track for '" .. item_data.name .. "'", "ERROR")
                items_skipped = items_skipped + 1
                goto continue
            end
        else
            destination_track = best_track.track
            
            -- Always try to rename the track with pattern categories, regardless of rename_track setting
            -- Extract categories if we haven't already done so
            if not next(categories) then
                categories = ExtractPatternCategories(item_data.name, global_patterns, true)
                ImportScript.DebugPrint("  Re-extracting categories for track renaming: " .. ImportScript.GetTableSize(categories))
            end
            
            -- If we have pattern categories, generate a full name for the track
            if next(categories) then
                local generated_name = GenerateTrackNameFromCategories(base_track_name, categories)
                if generated_name ~= best_track.name then
                    ImportScript.DebugPrint("  Renaming existing track from '" .. best_track.name .. "' to '" .. generated_name .. "'")
                    reaper.GetSetMediaTrackInfo_String(destination_track, "P_NAME", generated_name, true)
                    best_track.name = generated_name
                    ImportScript.LogMessage("Renamed track to '" .. generated_name .. "'", "TRACK")
                end
            end
            
            ImportScript.DebugPrint("  Using existing track: '" .. best_track.name .. "'")
        end
        
        -- Move the item to the destination track
        if destination_track then
            ImportScript.DebugPrint("  Moving item to track")
            reaper.MoveMediaItemToTrack(item_data.item, destination_track)
            
            -- Add this item to the track's item list
            table.insert(best_track.items, {
                name = item_data.name,
                start = item_data.start,
                end_time = item_data.end_time
            })
            
            -- Generate the full pattern-based name for the item
            local item_name_to_use = best_track.name
            
            -- Always try to generate a full pattern-based name, regardless of rename_track setting
            -- Extract categories if we haven't already
            if not next(categories) then
                categories = ExtractPatternCategories(item_data.name, global_patterns, true)
                ImportScript.DebugPrint("  Re-extracting categories for item renaming: " .. ImportScript.GetTableSize(categories))
            end
            
            -- If we have pattern categories, generate a full name
            if next(categories) then
                local generated_name = GenerateTrackNameFromCategories(base_track_name, categories)
                ImportScript.LogMessage("Generated full name: '" .. generated_name .. "' (track name: '" .. best_track.name .. "')", "RENAME")
                item_name_to_use = generated_name
            end
            
            -- Rename the item's take to match the full name
            local take = reaper.GetActiveTake(item_data.item)
            if take then
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", item_name_to_use, true)
                ImportScript.LogMessage("Renamed item to '" .. item_name_to_use .. "'", "RENAME")
            end
            
            items_organized = items_organized + 1
            ImportScript.LogMessage("Moved item '" .. item_data.name .. "' to track '" .. best_track.name .. "'", "MOVE")
        else
            ImportScript.DebugPrint("  ✗ No destination track available (destination_track is nil)")
            ImportScript.LogMessage("Failed to move item '" .. item_data.name .. "' - no destination track", "ERROR")
            items_skipped = items_skipped + 1
        end
        
        ::continue::
    end
    
    -- Handle unmatched items - move them to NOT SORTED folder
    local not_sorted_count = 0
    if #unmatched_item_list > 0 then
        ImportScript.DebugPrint("\n--- HANDLING UNMATCHED ITEMS ---")
        ImportScript.LogMessage("Processing " .. #unmatched_item_list .. " unmatched items", "ORGANIZE")
        
        -- Find or create NOT SORTED folder
        local not_sorted_track = nil
        local track_count = reaper.CountTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = reaper.GetTrackName(track)
            
            if track_name == "NOT SORTED" then
                not_sorted_track = track
                ImportScript.DebugPrint("  Found existing NOT SORTED folder")
                ImportScript.LogMessage("Using existing NOT SORTED folder", "TRACK")
                break
            end
        end
        
        -- Create NOT SORTED folder if it doesn't exist
        if not not_sorted_track then
            ImportScript.DebugPrint("  Creating NOT SORTED folder")
            ImportScript.LogMessage("Creating NOT SORTED folder", "CREATE")
            
            -- Create the track
            reaper.InsertTrackAtIndex(track_count, true)
            not_sorted_track = reaper.GetTrack(0, track_count)
            
            if not_sorted_track then
                -- Set the track name
                reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", "NOT SORTED", true)
                
                -- Set it as a folder
                reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)
                
                ImportScript.DebugPrint("    ✓ Created NOT SORTED folder")
                ImportScript.LogMessage("Successfully created NOT SORTED folder", "CREATE")
            else
                ImportScript.DebugPrint("    ✗ Failed to create NOT SORTED folder")
                ImportScript.LogMessage("Failed to create NOT SORTED folder", "ERROR")
            end
        end
        
        -- Move unmatched items to NOT SORTED folder
        if not_sorted_track then
            for _, item_data in ipairs(unmatched_item_list) do
                ImportScript.DebugPrint("  Moving unmatched item: '" .. item_data.name .. "' to NOT SORTED folder")
                reaper.MoveMediaItemToTrack(item_data.item, not_sorted_track)
                not_sorted_count = not_sorted_count + 1
                ImportScript.LogMessage("Moved unmatched item '" .. item_data.name .. "' to NOT SORTED folder", "MOVE")
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
    
    -- Log available patterns
    ImportScript.LogMessage("Available pattern categories:", "PATTERN")
    for category, patterns in pairs(global_patterns) do
        if patterns.patterns and #patterns.patterns > 0 then
            ImportScript.LogMessage("  - " .. category .. ": " .. table.concat(patterns.patterns, ", "), "PATTERN")
        end
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
            local categories = ExtractPatternCategories(take_name, global_patterns, true)
            
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
    AnalyzeSelectedItems = ImportScript.AnalyzeSelectedItems
} 