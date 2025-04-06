--[[ 
 * ReaScript Name: FTS Import Into Template By Name GUI
 * Description: GUI for importing audio files into template tracks based on filename patterns
 * Author: FastTrackStudio
 * Licence: GPL v3
 * REAPER: 5.0+
 * Version: 1.0
--]]

-- Get script path and determine if running directly or being required
local info = debug.getinfo(1, "S")
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
local is_direct_run = not pcall(function() return script_directly_invoked_status end)
script_directly_invoked_status = true -- Signal for future requires

-- Get the path to the FastTrackStudio Scripts root folder
local root_path = script_path:match("(.*[/\\])Organization[/\\].*[/\\]")
if not root_path then
    root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

-- Check for ReaImGui API directly
if not reaper.APIExists("ImGui_CreateContext") then
    reaper.ShowMessageBox("This script requires ReaImGui.\nPlease install ReaTeam Extensions from ReaPack, then run the script again.", "Error", 0)
    return
end

-- Check for JS_ReaScript API
if not reaper.APIExists("JS_Dialog_BrowseForOpenFiles") then
    reaper.ShowMessageBox("This script requires the js_ReaScriptAPI extension.\nPlease install it from ReaPack, then run the script again.", "Error", 0)
    return
end

-- Load JSON library
local json_path = root_path .. "libraries/utils/json.lua"
local r, json = pcall(function() return dofile(json_path) end)
if not r then
    reaper.ShowMessageBox("This script requires the JSON library.\nPlease make sure it exists at: " .. json_path, "Error", 0)
    return
end

-- Load utilities
package.path = package.path .. ";" .. reaper.GetResourcePath() .. "/Scripts/FastTrackStudio Scripts/?.lua"
-- Use dofile for local utilities
dofile(root_path .. "libraries/utils/Serialize Table.lua") -- Load serialization functions

-- Load GUI utilities
local GUI = dofile(root_path .. "libraries/utils/GUI Functions.lua") or {}

-- Load the Import function from the main script
local import_script = dofile(root_path .. "Organization/import/FTS_Import Into Template By Name.lua")

-- Import the Pattern Matching utility
local PatternMatching = require("libraries.utils.Pattern Matching")

-- Imgui shims to 0.7.2 (added after the news at 0.8)
dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.7.2")

-- Create context and fonts
local ctx = reaper.ImGui_CreateContext('Import Into Template By Name', reaper.ImGui_ConfigFlags_DockingEnable())
local font = reaper.ImGui_CreateFont("sans-serif", 13)
local font_mini = reaper.ImGui_CreateFont("sans-serif", 11)
local font_large = reaper.ImGui_CreateFont("sans-serif", 16)
reaper.ImGui_AttachFont(ctx, font)
reaper.ImGui_AttachFont(ctx, font_mini)
reaper.ImGui_AttachFont(ctx, font_large)

-- Constants
local EXT_STATE_NAME = "FTS_ImportTemplate"
local ScriptName = "Import Into Template By Name"
local ScriptVersion = "1.0"

-- Constants for pattern categories
local PATTERN_CATEGORIES = {
    { name = "Prefix", desc = "D, V, Bass, K, Orch, REF (exact matches including whitespace)" },
    { name = "Tracking Info", desc = "Information in square brackets - pass #, take #, etc." },
    { name = "Subtype", desc = "clean, drive, distorted, etc." },
    { name = "Arrangement", desc = "LEAD, Rhythm, Solo, Amb, Big, Little, etc." },
    { name = "Performer", desc = "Names in parentheses - Cody, Josh, John, etc." },
    { name = "Section", desc = "Verse, Chorus, Bridge, VS, CH, etc." },
    { name = "Layers", desc = "#, DBL, Double, etc." },
    { name = "Multi-Mic", desc = "Top, Bottom, L, R, In, Out, 121, 57, DI, Amp, etc." },
    { name = "Playlist", desc = ".# - anything with a period followed by a number" }
}

-- Define global pattern categories
local GLOBAL_PATTERN_CATEGORIES = {
    { name = "Tracking Info", key = "tracking", desc = "Record takes, comps, versions [enclosed in brackets]" },
    { name = "Subtype", key = "subtype", desc = "Specific type variations (Clean, Distorted, Hard, Soft)" },
    { name = "Arrangement", key = "arrangement", desc = "Arrangement parts (Verse, Chorus, Bridge)" },
    { name = "Performer", key = "performer", desc = "Performer name (enclosed in parentheses)" },
    { name = "Section", key = "section", desc = "Song sections or musical parts" },
    { name = "Layers", key = "layers", desc = "Doubled parts, layers, duplicate tracks" },
    { name = "Mic", key = "mic", desc = "Microphone positions or types" },
    { name = "Playlist", key = "playlist", desc = "Multiple takes/alternatives (.1, .2, etc.)" }
}

-- Tool Tips support
local function SafeToolTip(ctx, text)
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_Text(ctx, text)
        reaper.ImGui_EndTooltip(ctx)
    end
end

-- Load configuration from ExtState
function LoadConfigs()
    return import_script.LoadConfigs()
end

-- Save configuration to ExtState
function SaveConfigs(configs)
    import_script.SaveConfigs(configs)
end

-- Load track configurations from ExtState
function LoadTrackConfigs()
    return import_script.LoadTrackConfigs()
end

-- Save track configurations to ExtState
function SaveTrackConfigs(configs)
    import_script.SaveTrackConfigs(configs)
end

-- Constants for inheritance modes
local INHERITANCE_MODES = {
    DEFAULT_ONLY = 1,
    DEFAULT_PLUS_OVERRIDE = 2,
    OVERRIDE_ONLY = 3
}

-- Load defaults from the defaults.json file
function LoadDefaults()
    local defaults_path = root_path .. "Organization/import/defaults.json"
    local file = io.open(defaults_path, "r")
    if not file then
        return { default_patterns = {}, default_groups = {} }
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, defaults = pcall(function() return json.decode(content) end)
    if not success or not defaults then
        reaper.ShowConsoleMsg("Error parsing defaults.json file. Using empty defaults.\n")
        return { default_patterns = {}, default_groups = {} }
    end
    
    return defaults
end

-- Save defaults to the defaults.json file
function SaveDefaults(defaults)
    local defaults_path = root_path .. "Organization/import/defaults.json"
    local file = io.open(defaults_path, "w")
    if not file then
        reaper.ShowConsoleMsg("Error: Could not open defaults.json for writing.\n")
        return false
    end
    
    local content = json.encode(defaults)
    file:write(content)
    file:close()
    return true
end

-- Load inheritance mode preference
function LoadInheritanceMode(key, default_mode)
    local mode = tonumber(reaper.GetExtState(EXT_STATE_NAME, key .. "_inheritance_mode"))
    if not mode or mode < 1 or mode > 3 then
        return default_mode or INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE
    end
    return mode
end

-- Save inheritance mode preference
function SaveInheritanceMode(key, mode)
    reaper.SetExtState(EXT_STATE_NAME, key .. "_inheritance_mode", tostring(mode), true)
end

-- Load global pattern configurations with inheritance
function LoadGlobalPatterns()
    local loaded = LoadExtStateTable(EXT_STATE_NAME, "global_patterns", true)
    local defaults = LoadDefaults().default_patterns
    local mode = LoadInheritanceMode("global_patterns", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    
    -- Default empty global pattern configurations
    local result = {}
    
    -- Prepare result based on inheritance mode
    if mode == INHERITANCE_MODES.DEFAULT_ONLY then
        -- Use defaults only
        for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
            if defaults[category.key] then
                result[category.key] = { 
                    patterns = table.copy(defaults[category.key]),
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
function SaveGlobalPatterns(patterns)
    SaveExtStateTable(EXT_STATE_NAME, "global_patterns", patterns, true)
end

-- Load track configurations with inheritance
function LoadTrackConfigs()
    local loaded = import_script.LoadTrackConfigs()
    local defaults = LoadDefaults().default_groups
    local mode = LoadInheritanceMode("track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    
    -- Handle based on inheritance mode
    if mode == INHERITANCE_MODES.DEFAULT_ONLY then
        -- Use defaults only, converting to the expected format
        local result = {}
        for _, group in ipairs(defaults) do
            result[group.name] = table.copy(group)
            
            -- Ensure required fields are present
            if not result[group.name].parent_track_guid then
                result[group.name].parent_track_guid = ""
            end
            if not result[group.name].matching_track then
                result[group.name].matching_track = ""
            end
            if not result[group.name].matching_track_guid then
                result[group.name].matching_track_guid = ""
            end
            if not result[group.name].default_track then
                result[group.name].default_track = group.name
            end
            if not result[group.name].negative_patterns then
                result[group.name].negative_patterns = {}
            end
            if not result[group.name].create_if_missing then
                result[group.name].create_if_missing = true
            end
        end
        return result
    elseif mode == INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE then
        -- Merge defaults and overrides
        local result = loaded or {}
        
        -- Add default groups that don't exist in overrides
        for _, group in ipairs(defaults) do
            if not result[group.name] then
                result[group.name] = table.copy(group)
                
                -- Ensure required fields are present
                if not result[group.name].parent_track_guid then
                    result[group.name].parent_track_guid = ""
                end
                if not result[group.name].matching_track then
                    result[group.name].matching_track = ""
                end
                if not result[group.name].matching_track_guid then
                    result[group.name].matching_track_guid = ""
                end
                if not result[group.name].default_track then
                    result[group.name].default_track = group.name
                end
                if not result[group.name].negative_patterns then
                    result[group.name].negative_patterns = {}
                end
                if not result[group.name].create_if_missing then
                    result[group.name].create_if_missing = true
                end
            end
        end
        
        return result
    else -- OVERRIDE_ONLY
        return loaded or {}
    end
end

-- Save track configurations to ExtState with override information
function SaveTrackConfigs(configs)
    import_script.SaveTrackConfigs(configs)
end

-- Function to export track configurations including inheritance mode to a JSON file
function ExportConfigToJSON()
    -- Choose a file to save the configuration to
    local retval, filename = reaper.JS_Dialog_BrowseForSaveFile("Export Track Configuration", "", "Track_Configs.json", ".json")
    
    if retval and filename then
        -- Make sure the filename ends with .json
        if not filename:match("%.json$") then
            filename = filename .. ".json"
        end
        
        -- Get the current configurations
        local track_configs = LoadTrackConfigs()
        local global_patterns = LoadGlobalPatterns()
        
        -- Get inheritance modes
        local global_patterns_mode = LoadInheritanceMode("global_patterns")
        local track_configs_mode = LoadInheritanceMode("track_configs")
        
        -- Combine them into a single export object
        local export_data = {
            track_configs = track_configs,
            global_patterns = global_patterns,
            inheritance_modes = {
                global_patterns = global_patterns_mode,
                track_configs = track_configs_mode
            }
        }
        
        -- Convert to JSON
        local json_str = json.encode(export_data)
        
        -- Write to file
        local file = io.open(filename, "w")
        if file then
            file:write(json_str)
            file:close()
            reaper.ShowMessageBox("Configuration exported successfully to " .. filename, "Export Successful", 0)
        else
            reaper.ShowMessageBox("Failed to write configuration to " .. filename, "Export Failed", 0)
        end
    end
end

-- Function to import track configurations from a JSON file
function ImportConfigFromJSON()
    -- Choose a JSON file to import
    local retval, filename = reaper.JS_Dialog_BrowseForOpenFiles("Import Track Configuration", "", "", "JSON files (*.json)|*.json||", false)
    
    if retval and filename then
        -- Read the JSON file
        local file = io.open(filename, "r")
        if file then
            local json_str = file:read("*all")
            file:close()
            
            -- Parse the JSON
            local success, import_data = pcall(function() return json.decode(json_str) end)
            
            if success and import_data then
                -- Save the track configurations if present
                if import_data.track_configs then
                    SaveTrackConfigs(import_data.track_configs)
                end
                
                -- Save the global patterns if present
                if import_data.global_patterns then
                    SaveGlobalPatterns(import_data.global_patterns)
                end
                
                -- Save the inheritance modes if present
                if import_data.inheritance_modes then
                    if import_data.inheritance_modes.global_patterns then
                        SaveInheritanceMode("global_patterns", import_data.inheritance_modes.global_patterns)
                    end
                    
                    if import_data.inheritance_modes.track_configs then
                        SaveInheritanceMode("track_configs", import_data.inheritance_modes.track_configs)
                    end
                end
                
                reaper.ShowMessageBox("Configuration imported successfully from " .. filename, "Import Successful", 0)
            else
                reaper.ShowMessageBox("Failed to parse JSON from " .. filename, "Import Failed", 0)
            end
        else
            reaper.ShowMessageBox("Failed to read from " .. filename, "Import Failed", 0)
        end
    end
end

-- Generate an example configuration with common track types
function GenerateExampleConfig()
    local example_config = {
        Reference = {
            name = "Reference",
            parent_track = "REFERENCE",
            parent_track_guid = "",
            matching_track = "Reference",
            matching_track_guid = "",
            default_track = "Reference",
            insert_mode = "increment",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "ref", "reference" },
            negative_patterns = {},
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "REF" }, required = true },
                type = { patterns = { "WAV", "MP3" } }
            }
        },
        Kick = {
            name = "Kick",
            parent_track = "DRUMS",
            parent_track_guid = "",
            matching_track = "Kick",
            matching_track_guid = "",
            default_track = "Kick",
            insert_mode = "increment",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "kick", "k ", "k_", "bd" },
            negative_patterns = { "click" },
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "K" }, required = true },
                type = { patterns = { "SAMPLE" } }
            }
        },
        Snare = {
            name = "Snare",
            parent_track = "DRUMS",
            parent_track_guid = "",
            matching_track = "Snare",
            matching_track_guid = "",
            default_track = "Snare",
            insert_mode = "increment",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "snare", "snr", "sd" },
            negative_patterns = { "rim" },
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "SN" }, required = true },
                type = { patterns = { "SAMPLE" } }
            }
        },
        HiHat = {
            name = "HiHat",
            parent_track = "DRUMS",
            parent_track_guid = "",
            matching_track = "HH",
            matching_track_guid = "",
            default_track = "HH",
            insert_mode = "increment",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "hat", "hh" },
            negative_patterns = { "crash", "ride" },
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "HH" }, required = true },
                type = { patterns = { "SAMPLE" } }
            }
        },
        Guitar = {
            name = "Guitar",
            parent_track = "GUITARS",
            parent_track_guid = "",
            matching_track = "Guitar",
            matching_track_guid = "",
            default_track = "Guitar",
            insert_mode = "increment",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "gtr", "guitar" },
            negative_patterns = {},
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "GTR", "G" }, required = true },
                type = { patterns = { "BUS", "MIDI" } }
            }
        },
        LeadVocal = {
            name = "Lead Vocal",
            parent_track = "VOCALS",
            parent_track_guid = "",
            matching_track = "Vox",
            matching_track_guid = "",
            default_track = "Vox",
            insert_mode = "existing",
            increment_start = 1,
            only_number_when_multiple = true,
            patterns = { "vox", "vocal", "voc", "lead voc" },
            negative_patterns = { "backing" },
            create_if_missing = true,
            pattern_categories = {
                prefix = { patterns = { "V", "VOX" }, required = true },
                type = { patterns = { "SUM" } }
            }
        }
    }
    
    return example_config
end

-- Function to export an example configuration to a JSON file
function ExportExampleConfig()
    -- Choose a file to save the example configuration to
    local retval, filename = reaper.JS_Dialog_BrowseForSaveFile("Export Example Configuration", "", "Example_Track_Configs.json", ".json")
    
    if retval and filename then
        -- Make sure the filename ends with .json
        if not filename:match("%.json$") then
            filename = filename .. ".json"
        end
        
        -- Generate the example configuration
        local example_config = GenerateExampleConfig()
        
        -- Generate example global patterns
        local example_global_patterns = {
            tracking = {
                patterns = { "take#", "comp", "edit", "master" },
                required = false
            },
            subtype = { 
                patterns = { "clean", "dist", "acoustic", "fat", "room", "tight" },
                required = false
            },
            arrangement = { 
                patterns = { "verse", "chorus", "VS", "CH", "BR", "bridge", "intro", "outro", "solo" },
                required = false
            },
            performer = { 
                patterns = { "john", "mary", "singer", "band", "client" },
                required = false
            },
            section = { 
                patterns = { "main", "alt", "muted", "loud", "soft" },
                required = false
            },
            layers = { 
                patterns = { "dbl", "double", "layer", "L#" },
                required = false
            },
            mic = { 
                patterns = { "SM57", "SM58", "414", "U87", "OH", "room", "close", "DI", "amp" },
                required = false
            },
            playlist = { 
                patterns = { ".#", "alt#", "option#" },
                required = false
            }
        }
        
        -- Combine them into a single export object
        local export_data = {
            track_configs = example_config,
            global_patterns = example_global_patterns
        }
        
        -- Convert to JSON
        local json_str = json.encode(export_data)
        
        -- Write to file
        local file = io.open(filename, "w")
        if file then
            file:write(json_str)
            file:close()
            reaper.ShowMessageBox("Example configuration exported successfully to " .. filename, "Export Successful", 0)
        else
            reaper.ShowMessageBox("Failed to write example configuration to " .. filename, "Export Failed", 0)
        end
    end
end

-- Draw the configs menu
function ConfigsMenu()
    if reaper.ImGui_BeginMenu(ctx, 'Configs') then
        if reaper.ImGui_MenuItem(ctx, 'Import Track Configurations from JSON') then
            ImportConfigFromJSON()
        end
        
        if reaper.ImGui_MenuItem(ctx, 'Export Track Configurations to JSON') then
            ExportConfigToJSON()
        end
        
        if reaper.ImGui_MenuItem(ctx, 'Export Example Configuration') then
            ExportExampleConfig()
        end
        
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_MenuItem(ctx, 'Show Tool Tips') then
            local configs = LoadConfigs()
            configs.ToolTips = not configs.ToolTips
            SaveConfigs(configs)
        end
        
        reaper.ImGui_EndMenu(ctx)
    end
end

-- Draw the about menu
function AboutMenu()
    if reaper.ImGui_BeginMenu(ctx, 'About') then
        if reaper.ImGui_MenuItem(ctx, 'Version: ' .. ScriptVersion) then
            -- Do nothing, just display version
        end
        
        reaper.ImGui_EndMenu(ctx)
    end
end

-- Draw the main UI
function DrawMainUI()
    -- Set window size
    if first_frame then
        reaper.ImGui_SetNextWindowSize(ctx, 600, 500, reaper.ImGui_Cond_FirstUseEver())
        first_frame = false
    end
    
    -- Main window
    local visible, open = reaper.ImGui_Begin(ctx, 'FTS Import Into Template By Name', true)
    if not visible then return open end
    
    -- Menu bar 
    if reaper.ImGui_BeginMenuBar(ctx) then
        -- File Menu
        if reaper.ImGui_BeginMenu(ctx, "File") then
            if reaper.ImGui_MenuItem(ctx, "Exit") then
                return false
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        -- Configuration Menu
        if reaper.ImGui_BeginMenu(ctx, "Configuration") then
            if reaper.ImGui_MenuItem(ctx, "Import Configuration") then
                ImportConfigFromJSON()
            end
            if reaper.ImGui_MenuItem(ctx, "Export Configuration") then
                ExportConfigToJSON()
            end
            if reaper.ImGui_MenuItem(ctx, "Export Example Configuration") then
                ExportExampleConfig()
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        -- Help Menu
        if reaper.ImGui_BeginMenu(ctx, "Help") then
            if reaper.ImGui_MenuItem(ctx, "About") then
                reaper.ShowMessageBox("FTS Import Into Template By Name\nVersion: 1.0\n\nBy FastTrackStudio", "About", 0)
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        reaper.ImGui_EndMenuBar(ctx)
    end
    
    -- Tab bar for main content
    if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
        -- Import tab
        if reaper.ImGui_BeginTabItem(ctx, "Import Files") then
            DrawImportTab()
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Track Configurations tab
        if reaper.ImGui_BeginTabItem(ctx, "Track Configurations") then
            DrawConfigTab()
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Global Patterns tab (NEW)
        if reaper.ImGui_BeginTabItem(ctx, "Global Patterns") then
            DrawGlobalPatternsTab()
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
    
    reaper.ImGui_End(ctx)
    return open
end

-- Function to find the appropriate track for a file
function getTrackForFile(file_name, track_configs)
    if not track_configs or not file_name then return nil end
    
    local file_name_lower = file_name:lower()
    local highest_priority = -1
    local matched_config = nil
    local sub_route_match = nil
    
    -- Loop through all configurations to find a match
    for config_name, config in pairs(track_configs) do
        local priority = config.priority or 0
        local matched = false
        
        -- Skip if this config has a lower priority than already matched
        if priority < highest_priority then goto continue end
        
        -- Check if file matches any pattern
        for _, pattern in ipairs(config.patterns or {}) do
            if file_name_lower:find(pattern:lower()) then
                matched = true
                break
            end
        end
        
        -- Skip if no pattern matched
        if not matched then goto continue end
        
        -- Check for negative patterns (patterns to exclude)
        for _, neg_pattern in ipairs(config.negative_patterns or {}) do
            if file_name_lower:find(neg_pattern:lower()) then
                matched = false
                break
            end
        end
        
        -- Skip if excluded by negative pattern
        if not matched then goto continue end
        
        -- If matched at this point, check for sub-routes
        local sub_matched = false
        for _, sub_route in ipairs(config.sub_routes or {}) do
            local sub_match = false
            
            -- Check if file matches any pattern in the sub-route
            for _, pattern in ipairs(sub_route.patterns or {}) do
                if file_name_lower:find(pattern:lower()) then
                    sub_match = true
                    break
                end
            end
            
            if sub_match then
                sub_route_match = sub_route
                sub_matched = true
                break
            end
        end
        
        -- If match is better than previous, update
        if matched and priority >= highest_priority then
            highest_priority = priority
            matched_config = config
        end
        
        ::continue::
    end
    
    -- Return the matched configuration and any sub-route match
    return matched_config, sub_route_match
end

-- Function to prompt for files using JS_Dialog_BrowseForOpenFiles
function PromptForFiles(title, initial_dir, filter, allow_multiple)
    if not reaper.APIExists("JS_Dialog_BrowseForOpenFiles") then
        reaper.ShowMessageBox("Missing dependency:\nPlease install js_reascriptAPI REAPER extension available from ReaPack.", "Error", 0)
        return nil
    end
    
    local retval, file_names = reaper.JS_Dialog_BrowseForOpenFiles(title, initial_dir, "", filter, allow_multiple)
    
    if not retval or retval == 0 then
        return nil
    end
    
    -- Parse the returned string into a table of file paths
    local files = {}
    if allow_multiple then
        for file in file_names:gmatch("[^\0]*") do
            if file ~= "" then
                table.insert(files, file)
            end
        end
    else
        table.insert(files, file_names)
    end
    
    return files
end

-- Function to get a track by its name
function GetTrackByName(name)
    local name_lower = name:lower()
    local count = reaper.CountTracks(0)
    
    for i = 0, count - 1 do
        local track = reaper.GetTrack(0, i)
        local retval, track_name = reaper.GetTrackName(track)
        
        if track_name:lower() == name_lower then
            return track
        end
    end
    
    return nil
end

-- Function to get a child track by its name under a parent track
function GetChildTrackByName(parent_track, name)
    local name_lower = name:lower()
    local count = reaper.CountTracks(0)
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local current_depth = 1
    
    for i = parent_idx + 1, count - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        -- Adjust depth tracking
        if depth < 0 then
            current_depth = current_depth + depth
            if current_depth <= 0 then
                break -- We've exited this parent's folder
            end
        elseif depth > 0 then
            current_depth = current_depth + depth
        end
        
        -- Check if this track matches the name we're looking for
        local retval, track_name = reaper.GetTrackName(track)
        if track_name:lower() == name_lower then
            return track
        end
    end
    
    return nil
end

-- Function to create a new parent track
function CreateTrack(track_name)
    -- Get the count before insertion
    local track_count = reaper.CountTracks(0)
    
    -- Create the new track at the end
    reaper.InsertTrackAtIndex(track_count, true)
    local new_track = reaper.GetTrack(0, track_count)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    
    -- Make it a folder
    reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 1)
    
    return new_track
end

-- Function to create a track under a parent
function CreateTrackUnderParent(parent_track, track_name)
    -- Get parent track index
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local insert_idx = parent_idx + 1
    
    -- Find the last track in this folder level without modifying any depths
    local current_depth = 1
    for i = parent_idx + 1, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        if depth < 0 then
            current_depth = current_depth + depth
            if current_depth <= 0 then
                insert_idx = i + 1
                break
            end
        elseif depth > 0 then
            current_depth = current_depth + depth
        end
    end
    
    -- Insert the new track
    reaper.InsertTrackAtIndex(insert_idx, true)
    local new_track = reaper.GetTrack(0, insert_idx)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    
    -- Make sure track is visible
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)  -- Show in TCP
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)  -- Show in Mixer
    
    return new_track
end

-- Function to insert a media item on a track
function InsertMediaItemOnTrack(track, file_path, position)
    -- Select the track
    reaper.SetOnlyTrackSelected(track)
    
    -- Set the edit cursor position
    reaper.SetEditCurPos(position, false, false)
    
    -- Insert the media item
    local item = reaper.InsertMedia(file_path, 0) -- 0 = add at edit cursor
    
    return item
end

-- Import audio files function
function ImportAudioFiles()
    -- Get the current configuration
    local track_configs = LoadTrackConfigs()
    
    if not track_configs or next(track_configs) == nil then
        reaper.ShowMessageBox("No track configurations loaded. Please import a configuration first.", "Configuration Error", 0)
        return
    end
    
    -- Get files to import
    local file_list = PromptForFiles("Select audio files to import", "", "Audio files (*.wav, *.mp3, *.flac, *.ogg)\0*.wav;*.mp3;*.flac;*.ogg\0All files\0*.*\0", true)
    
    if not file_list or #file_list == 0 then 
        reaper.ShowConsoleMsg("No files selected for import.\n")
        return 
    end
    
    -- Variables to track results
    local imported_count = 0
    local failed_count = 0
    local tracks_created = {}
    local failed_files = {}
    local unsorted_count = 0
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Loop through each file
    for i, file_path in ipairs(file_list) do
        -- Get just the filename without path
        local file_name = file_path:match("([^/\\]+)$")
        
        -- Find the appropriate track configuration for this file
        local config, sub_route = getTrackForFile(file_name, track_configs)
        
        if config then
            -- Determine which track to place file in
            local parent_name = sub_route and (sub_route.parent_track or config.parent_track) or config.parent_track
            local track_name = sub_route and sub_route.track or nil
            local insert_mode = sub_route and sub_route.insert_mode or config.insert_mode
            local create_if_missing = config.create_if_missing
            
            -- Find parent track
            local parent_track = GetTrackByName(parent_name)
            
            -- Create parent track if it doesn't exist and creation is allowed
            if not parent_track and create_if_missing then
                parent_track = CreateTrack(parent_name)
                tracks_created[parent_name] = true
            end
            
            if parent_track then
                local target_track
                
                -- Generate appropriate track name based on file name
                if not track_name then
                    -- Use the Pattern Matching utility for name generation
                    track_name = PatternMatching.GenerateTrackName(file_name, config)
                end
                
                if insert_mode == "existing" then
                    -- Try to find an existing track with this name under the parent
                    target_track = GetChildTrackByName(parent_track, track_name)
                    
                    -- Create track if it doesn't exist and creation is allowed
                    if not target_track and create_if_missing then
                        target_track = CreateTrackUnderParent(parent_track, track_name)
                        tracks_created[track_name] = true
                    end
                else -- insert_mode == "increment"
                    -- Create a new track with an incremented name
                    local base_name = track_name
                    local increment = config.increment_start or 1
                    local track_exists = true
                    
                    -- Find the next available increment
                    while track_exists do
                        local numbered_name = base_name .. " " .. increment
                        target_track = GetChildTrackByName(parent_track, numbered_name)
                        
                        if not target_track then
                            -- No track with this name exists, create it
                            target_track = CreateTrackUnderParent(parent_track, numbered_name)
                            tracks_created[numbered_name] = true
                            track_exists = false
                        else
                            -- Track exists, try next increment
                            increment = increment + 1
                        end
                    end
                end
                
                if target_track then
                    -- Insert the item at the edit cursor position
                    local cursor_position = reaper.GetCursorPosition()
                    InsertMediaItemOnTrack(target_track, file_path, cursor_position)
                    imported_count = imported_count + 1
                else
                    table.insert(failed_files, file_name .. " (track creation failed)")
                    failed_count = failed_count + 1
                end
            else
                table.insert(failed_files, file_name .. " (parent track not found)")
                failed_count = failed_count + 1
            end
        else
            -- No matching configuration found, place in NOT SORTED folder
            local not_sorted_parent = GetTrackByName("NOT SORTED")
            
            if not not_sorted_parent then
                not_sorted_parent = CreateTrack("NOT SORTED")
            end
            
            if not_sorted_parent then
                local cursor_position = reaper.GetCursorPosition()
                InsertMediaItemOnTrack(not_sorted_parent, file_path, cursor_position)
                unsorted_count = unsorted_count + 1
            else
                table.insert(failed_files, file_name .. " (could not create NOT SORTED folder)")
                failed_count = failed_count + 1
            end
        end
    end
    
    -- End undo block
    reaper.Undo_EndBlock("Import Audio Files", -1)
    
    -- Show results
    local msg = imported_count .. " files imported successfully.\n"
    if unsorted_count > 0 then
        msg = msg .. unsorted_count .. " files placed in NOT SORTED folder.\n"
    end
    if failed_count > 0 then
        msg = msg .. failed_count .. " files failed to import:\n"
        for _, failed in ipairs(failed_files) do
            msg = msg .. "- " .. failed .. "\n"
        end
    end
    
    reaper.ShowConsoleMsg(msg)
end

-- Function to move selected items based on filename
function MoveSelectedItems()
    -- Get the current configuration
    local track_configs = LoadTrackConfigs()
    
    if not track_configs or next(track_configs) == nil then
        reaper.ShowMessageBox("No track configurations loaded. Please import a configuration first.", "Configuration Error", 0)
        return
    end
    
    -- Variables to track results
    local moved_count = 0
    local failed_count = 0
    local tracks_created = {}
    local failed_items = {}
    local unsorted_count = 0
    
    -- Start undo block
    reaper.Undo_BeginBlock()
    
    -- Get all selected items
    local num_items = reaper.CountSelectedMediaItems(0)
    
    if num_items == 0 then
        reaper.ShowMessageBox("No items selected. Please select items to move.", "Selection Error", 0)
        return
    end
    
    -- Get existing tracks for lookup
    local existing_tracks = {}
    local track_count = reaper.CountTracks(0)
    local guid_map = {}  -- Map to store GUIDs to tracks
    local folder_tracks = {}  -- Track folder tracks
    
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local retval, track_name = reaper.GetTrackName(track)
        local track_name_lower = track_name:lower()
        local guid = reaper.GetTrackGUID(track)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        
        existing_tracks[track_name_lower] = track
        
        -- Store GUID mapping
        if guid then
            guid_map[guid] = track
        end
        
        -- Mark folder tracks
        if depth == 1 then
            folder_tracks[track_name_lower] = true
        end
    end
    
    -- Track used configurations for handling "only_number_when_multiple"
    local used_tracks = {}
    
    -- Loop through each selected item
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        
        if take then
            local source = reaper.GetMediaItemTake_Source(take)
            local filename = reaper.GetMediaSourceFileName(source, "")
            
            -- Get just the filename without path
            local file_name = filename:match("([^/\\]+)$")
            
            -- Find the appropriate track configuration for this file
            local config, sub_route = getTrackForFile(file_name, track_configs)
            
            if config then
                -- Determine which track to place file in
                local parent_name = sub_route and (sub_route.parent_track or config.parent_track) or config.parent_track
                local track_name = sub_route and sub_route.track or nil
                local insert_mode = sub_route and sub_route.insert_mode or config.insert_mode
                local create_if_missing = config.create_if_missing
                
                -- Try to find parent track by GUID first, then by name
                local parent_track = nil
                if config.parent_track_guid and config.parent_track_guid ~= "" then
                    parent_track = guid_map[config.parent_track_guid] or GetTrackByGUID(config.parent_track_guid)
                end
                
                -- If no parent track found by GUID, try by name
                if not parent_track then
                    parent_track = existing_tracks[parent_name:lower()]
                end
                
                -- Create parent track if it doesn't exist and creation is allowed
                if not parent_track and create_if_missing then
                    parent_track = CreateTrack(parent_name)
                    existing_tracks[parent_name:lower()] = parent_track
                    tracks_created[parent_name] = true
                end
                
                if parent_track then
                    local target_track
                    
                    -- Generate appropriate track name based on file name
                    if not track_name then
                        -- Use the Pattern Matching utility for name generation
                        track_name = PatternMatching.GenerateTrackName(file_name, config)
                    end
                    
                    -- Track existing items with this configuration for "only_number_when_multiple"
                    local existing_count = used_tracks[config.name] or 0
                    
                    -- Modify track name based on "only_number_when_multiple" setting
                    if insert_mode == "increment" and config.only_number_when_multiple and existing_count == 0 then
                        -- Strip the number if this is the first track and "only_number_when_multiple" is true
                        track_name = config.default_track
                    end
                    
                    if insert_mode == "existing" then
                        -- Try to find an existing track with this name under the parent
                        target_track = GetChildTrackByName(parent_track, track_name)
                        
                        -- Create track if it doesn't exist and creation is allowed
                        if not target_track and create_if_missing then
                            -- Find template track by GUID first
                            local template_track = nil
                            if config.matching_track_guid and config.matching_track_guid ~= "" then
                                template_track = guid_map[config.matching_track_guid] or GetTrackByGUID(config.matching_track_guid)
                            end
                            
                            -- Try by name if GUID not found
                            if not template_track and config.matching_track and config.matching_track ~= "" then
                                template_track = existing_tracks[config.matching_track:lower()]
                            end
                            
                            -- Create track using template if available
                            if template_track then
                                target_track = CreateTrackFromTemplate(template_track, track_name, parent_track)
                            else
                                target_track = CreateTrackUnderParent(parent_track, track_name)
                            end
                            
                            existing_tracks[track_name:lower()] = target_track
                            tracks_created[track_name] = true
                        end
                    else -- insert_mode == "increment"
                        -- Create a new track with an incremented name
                        local base_name = track_name
                        local increment = config.increment_start or 1
                        local track_exists = true
                        
                        -- Find the next available increment
                        while track_exists do
                            local numbered_name = base_name
                            
                            -- Only add number if we need to
                            if increment > 1 or not config.only_number_when_multiple then
                                numbered_name = base_name .. " " .. increment
                            end
                            
                            target_track = GetChildTrackByName(parent_track, numbered_name)
                            
                            if not target_track then
                                -- No track with this name exists, create it
                                -- Find template track by GUID first
                                local template_track = nil
                                if config.matching_track_guid and config.matching_track_guid ~= "" then
                                    template_track = guid_map[config.matching_track_guid] or GetTrackByGUID(config.matching_track_guid)
                                end
                                
                                -- Try by name if GUID not found
                                if not template_track and config.matching_track and config.matching_track ~= "" then
                                    template_track = existing_tracks[config.matching_track:lower()]
                                end
                                
                                -- Create track using template if available
                                if template_track then
                                    target_track = CreateTrackFromTemplate(template_track, numbered_name, parent_track)
                                else
                                    target_track = CreateTrackUnderParent(parent_track, numbered_name)
                                end
                                
                                existing_tracks[numbered_name:lower()] = target_track
                                tracks_created[numbered_name] = true
                                track_exists = false
                            else
                                -- Track exists, try next increment
                                increment = increment + 1
                            end
                        end
                    end
                    
                    if target_track then
                        -- Get item position
                        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        
                        -- Create a new item on the target track
                        local new_item = reaper.CreateNewMIDIItemInProj(target_track, item_pos, item_pos + item_len)
                        
                        -- Copy the source from original item
                        local new_take = reaper.GetActiveTake(new_item)
                        reaper.SetMediaItemTake_Source(new_take, source)
                        
                        -- Copy item properties
                        reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", item_pos)
                        reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", item_len)
                        reaper.SetMediaItemInfo_Value(new_item, "D_VOL", reaper.GetMediaItemInfo_Value(item, "D_VOL"))
                        reaper.SetMediaItemInfo_Value(new_item, "D_PAN", reaper.GetMediaItemInfo_Value(item, "D_PAN"))
                        reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", reaper.GetMediaItemInfo_Value(item, "B_MUTE"))
                        
                        -- Delete the original item
                        reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
                        
                        -- Update the count for this configuration
                        used_tracks[config.name] = (used_tracks[config.name] or 0) + 1
                        
                        moved_count = moved_count + 1
                    else
                        table.insert(failed_items, file_name .. " (track creation failed)")
                        failed_count = failed_count + 1
                    end
                else
                    table.insert(failed_items, file_name .. " (parent track not found)")
                    failed_count = failed_count + 1
                end
            else
                -- No matching configuration found, place in NOT SORTED folder
                local not_sorted_parent = GetTrackByName("NOT SORTED")
                
                if not not_sorted_parent then
                    not_sorted_parent = CreateTrack("NOT SORTED")
                    existing_tracks["not sorted"] = not_sorted_parent
                end
                
                if not_sorted_parent then
                    -- Get item position
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    
                    -- Create a new item on the target track
                    local new_item = reaper.CreateNewMIDIItemInProj(not_sorted_parent, item_pos, item_pos + item_len)
                    
                    -- Copy the source from original item
                    local new_take = reaper.GetActiveTake(new_item)
                    reaper.SetMediaItemTake_Source(new_take, source)
                    
                    -- Copy item properties
                    reaper.SetMediaItemInfo_Value(new_item, "D_POSITION", item_pos)
                    reaper.SetMediaItemInfo_Value(new_item, "D_LENGTH", item_len)
                    reaper.SetMediaItemInfo_Value(new_item, "D_VOL", reaper.GetMediaItemInfo_Value(item, "D_VOL"))
                    reaper.SetMediaItemInfo_Value(new_item, "D_PAN", reaper.GetMediaItemInfo_Value(item, "D_PAN"))
                    reaper.SetMediaItemInfo_Value(new_item, "B_MUTE", reaper.GetMediaItemInfo_Value(item, "B_MUTE"))
                    
                    -- Delete the original item
                    reaper.DeleteTrackMediaItem(reaper.GetMediaItem_Track(item), item)
                    
                    unsorted_count = unsorted_count + 1
                else
                    table.insert(failed_items, file_name .. " (could not create NOT SORTED folder)")
                    failed_count = failed_count + 1
                end
            end
        else
            table.insert(failed_items, "Item #" .. i .. " (no active take)")
            failed_count = failed_count + 1
        end
    end
    
    -- End undo block
    reaper.Undo_EndBlock("Move Selected Items", -1)
    
    -- Show results
    local msg = moved_count .. " items moved successfully.\n"
    if unsorted_count > 0 then
        msg = msg .. unsorted_count .. " items placed in NOT SORTED folder.\n"
    end
    if failed_count > 0 then
        msg = msg .. failed_count .. " items failed to move:\n"
        for _, failed in ipairs(failed_items) do
            msg = msg .. "- " .. failed .. "\n"
        end
    end
    
    reaper.ShowConsoleMsg(msg)
end

-- Draw the import tab content
function DrawImportTab()
    -- Main content
    reaper.ImGui_Text(ctx, "This tool automatically categorizes audio files into tracks based on filename patterns.")
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "Import new files or organize existing items in your project:")
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Center the buttons
    local button_width = 200
    local button_height = 40
    local button_spacing = 20
    local total_width = (button_width * 2) + button_spacing
    local window_width = reaper.ImGui_GetWindowContentRegionMax(ctx)
    reaper.ImGui_SetCursorPosX(ctx, (window_width - total_width) * 0.5)
    
    -- Style the buttons
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x4488CCFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x5599DDFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x66AAEEFF)
    
    -- Import button
    if reaper.ImGui_Button(ctx, "Import Audio Files", button_width, button_height) then
        ImportAudioFiles()
    end
    
    reaper.ImGui_SameLine(ctx, 0, button_spacing)
    
    -- Move selected items button
    if reaper.ImGui_Button(ctx, "Move Selected Items", button_width, button_height) then
        MoveSelectedItems()
    end
    
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Additional information
    reaper.ImGui_Text(ctx, "How it works:")
    reaper.ImGui_BulletText(ctx, "Files are sorted based on filename patterns (e.g., 'kick', 'snare', etc.)")
    reaper.ImGui_BulletText(ctx, "Each pattern is linked to a specific track or folder")
    reaper.ImGui_BulletText(ctx, "New tracks are created if they don't exist")
    reaper.ImGui_BulletText(ctx, "Unmatched files are placed in a 'NOT SORTED' folder")
    
    -- Add a note about configuration
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextWrapped(ctx, "Configure track patterns and naming rules by switching to the Track Configurations tab or importing a JSON configuration file from the Configs menu.")
end

-- Structure for a new config group
function CreateNewConfigGroup()
    return {
        name = "",
        patterns = {},
        negative_patterns = {},
        parent_track = "",
        parent_track_guid = "",
        matching_track = "",  -- New field for the matching/template track
        matching_track_guid = "", -- GUID for the matching track
        default_track = "",   -- Used for track name generation
        insert_mode = "increment",
        increment_start = 1,
        only_number_when_multiple = true, -- Only show numbers when more than one track exists
        create_if_missing = true,
        pattern_categories = {
            prefix = { patterns = {}, required = false },
            type = { patterns = {}, required = false } -- New category for (BUS), (Sum), (MIDI) etc.
        }
    }
end

-- Variables for track config editing
local editing_group = nil
local new_group_name = ""
local selected_category = 1
local new_pattern = ""
local new_negative_pattern = ""
local is_editing_group = false
local show_add_group_popup = false

-- Function to get GUID and name of selected track
function GetSelectedTrackInfo()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then
        return nil, nil
    end
    
    local guid = reaper.GetTrackGUID(track)
    local _, name = reaper.GetTrackName(track)
    
    return guid, name
end

-- Function to handle the Add/Edit Group popup
function ShowAddEditGroupPopup()
    if not is_editing_group then return end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    
    if reaper.ImGui_BeginPopupModal(ctx, "Edit Track Configuration", true, popup_flags) then
        -- Group name input
        reaper.ImGui_Text(ctx, "Group Name:")
        local changed_name, value_name = reaper.ImGui_InputText(ctx, "##groupname", editing_group.name, 256)
        if changed_name then
            editing_group.name = value_name
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Parent track settings with GUID button
        reaper.ImGui_Text(ctx, "Parent Track:")
        local changed_parent, value_parent = reaper.ImGui_InputText(ctx, "##parenttrack", editing_group.parent_track, 256)
        if changed_parent then
            editing_group.parent_track = value_parent
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Get Selected##parent") then
            local guid, name = GetSelectedTrackInfo()
            if guid and name then
                editing_group.parent_track = name
                editing_group.parent_track_guid = guid
                reaper.ShowConsoleMsg("Parent track set to: " .. name .. " (GUID: " .. guid .. ")\n")
            else
                reaper.ShowConsoleMsg("No track selected.\n")
            end
        end
        
        if editing_group.parent_track_guid and editing_group.parent_track_guid ~= "" then
            reaper.ImGui_TextColored(ctx, 0x88CC88FF, "GUID: " .. editing_group.parent_track_guid)
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Matching/Template track with GUID button
        reaper.ImGui_Text(ctx, "Matching Track (template for new tracks):")
        local changed_match, value_match = reaper.ImGui_InputText(ctx, "##matchingtrack", editing_group.matching_track or "", 256)
        if changed_match then
            editing_group.matching_track = value_match
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Get Selected##matching") then
            local guid, name = GetSelectedTrackInfo()
            if guid and name then
                editing_group.matching_track = name
                editing_group.matching_track_guid = guid
                editing_group.default_track = name  -- Also set as default track name
                reaper.ShowConsoleMsg("Matching track set to: " .. name .. " (GUID: " .. guid .. ")\n")
            else
                reaper.ShowConsoleMsg("No track selected.\n")
            end
        end
        
        if editing_group.matching_track_guid and editing_group.matching_track_guid ~= "" then
            reaper.ImGui_TextColored(ctx, 0x88CC88FF, "GUID: " .. editing_group.matching_track_guid)
        end
        
        -- Default track name (used for name generation)
        reaper.ImGui_Text(ctx, "Default Track Name:")
        local changed_default, value_default = reaper.ImGui_InputText(ctx, "##defaulttrack", editing_group.default_track, 256)
        if changed_default then
            editing_group.default_track = value_default
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Insert mode combo
        reaper.ImGui_Text(ctx, "Insert Mode:")
        local insert_modes = { "increment", "existing" }
        local current_insert_mode = 1
        for i, mode in ipairs(insert_modes) do
            if mode == editing_group.insert_mode then
                current_insert_mode = i
                break
            end
        end
        
        local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##insertmode", current_insert_mode - 1, table.concat(insert_modes, "\0") .. "\0", -1)
        if changed_mode then
            editing_group.insert_mode = insert_modes[new_mode + 1]
        end
        
        -- Increment start number
        if editing_group.insert_mode == "increment" then
            reaper.ImGui_Text(ctx, "Increment Start:")
            local changed_inc, value_inc = reaper.ImGui_InputInt(ctx, "##incstart", editing_group.increment_start, 1)
            if changed_inc then
                editing_group.increment_start = math.max(1, value_inc)
            end
            
            -- Option to only show number when multiple tracks exist
            local changed_onm, value_onm = reaper.ImGui_Checkbox(ctx, "Only number when multiple tracks exist", editing_group.only_number_when_multiple or false)
            if changed_onm then
                editing_group.only_number_when_multiple = value_onm
            end
        end
        
        -- Create if missing checkbox
        local changed_create, value_create = reaper.ImGui_Checkbox(ctx, "Create Track If Missing", editing_group.create_if_missing)
        if changed_create then
            editing_group.create_if_missing = value_create
        end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Pattern categories tab bar
        if reaper.ImGui_BeginTabBar(ctx, "PatternCategories") then
            -- General tab for basic patterns
            if reaper.ImGui_BeginTabItem(ctx, "General Patterns") then
                -- Main pattern matching
                reaper.ImGui_Text(ctx, "Main Pattern Matching")
                reaper.ImGui_Text(ctx, "Add patterns that identify this type of track (e.g., 'kick', 'snare')")
                
                -- New pattern input
                local changed_pattern, value_pattern = reaper.ImGui_InputText(ctx, "New Pattern##main", new_pattern, 256)
                if changed_pattern then
                    new_pattern = value_pattern
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##mainpattern") and new_pattern ~= "" then
                    table.insert(editing_group.patterns, new_pattern)
                    new_pattern = ""
                end
                
                -- List of existing patterns
                if #editing_group.patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##patternlist", -1, 100) then
                        for i, pattern in ipairs(editing_group.patterns) do
                            local selected = false
                            local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##" .. i, selected)
                            
                            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                reaper.ImGui_OpenPopup(ctx, "PatternContextMenu" .. i)
                            end
                            
                            if reaper.ImGui_BeginPopup(ctx, "PatternContextMenu" .. i) then
                                if reaper.ImGui_MenuItem(ctx, "Delete") then
                                    table.remove(editing_group.patterns, i)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndListBox(ctx)
                    end
                else
                    reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No patterns defined")
                end
                
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                
                -- Negative pattern matching
                reaper.ImGui_Text(ctx, "Negative Pattern Matching")
                reaper.ImGui_Text(ctx, "Add patterns to exclude from matching (e.g., 'oh' to exclude from 'hi hat')")
                
                -- New negative pattern input
                local changed_neg, value_neg = reaper.ImGui_InputText(ctx, "New Pattern##negative", new_negative_pattern, 256)
                if changed_neg then
                    new_negative_pattern = value_neg
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##negpattern") and new_negative_pattern ~= "" then
                    table.insert(editing_group.negative_patterns, new_negative_pattern)
                    new_negative_pattern = ""
                end
                
                -- List of existing negative patterns
                if #editing_group.negative_patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##negpatternlist", -1, 100) then
                        for i, pattern in ipairs(editing_group.negative_patterns) do
                            local selected = false
                            local clicked, selected = reaper.ImGui_Selectable(ctx, pattern .. "##neg" .. i, selected)
                            
                            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 1) then -- Right click
                                reaper.ImGui_OpenPopup(ctx, "NegPatternContextMenu" .. i)
                            end
                            
                            if reaper.ImGui_BeginPopup(ctx, "NegPatternContextMenu" .. i) then
                                if reaper.ImGui_MenuItem(ctx, "Delete") then
                                    table.remove(editing_group.negative_patterns, i)
                                end
                                reaper.ImGui_EndPopup(ctx)
                            end
                        end
                        reaper.ImGui_EndListBox(ctx)
                    end
                else
                    reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No negative patterns defined")
                end
                
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Prefix category tab
            if reaper.ImGui_BeginTabItem(ctx, "Prefix") then
                reaper.ImGui_Text(ctx, "Track name prefixes like D, V, Bass, K, Orch, REF (exact matches)")
                reaper.ImGui_Spacing(ctx)
                
                -- Required checkbox
                local is_required = editing_group.pattern_categories.prefix and editing_group.pattern_categories.prefix.required or false
                local changed_req, value_req = reaper.ImGui_Checkbox(ctx, "Required in Naming", is_required)
                if changed_req then
                    if not editing_group.pattern_categories.prefix then
                        editing_group.pattern_categories.prefix = { patterns = {}, required = value_req }
                    else
                        editing_group.pattern_categories.prefix.required = value_req
                    end
                end
                
                -- New prefix pattern input
                local new_prefix_pattern = ""
                local changed_prefix, value_prefix = reaper.ImGui_InputText(ctx, "New Prefix Pattern", new_prefix_pattern, 256)
                if changed_prefix then
                    new_prefix_pattern = value_prefix
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##prefix") and new_prefix_pattern ~= "" then
                    if not editing_group.pattern_categories.prefix then
                        editing_group.pattern_categories.prefix = { patterns = {}, required = false }
                    end
                    
                    table.insert(editing_group.pattern_categories.prefix.patterns, new_prefix_pattern)
                    new_prefix_pattern = ""
                end
                
                -- List of existing prefix patterns
                local prefix_patterns = editing_group.pattern_categories.prefix and editing_group.pattern_categories.prefix.patterns or {}
                if #prefix_patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##prefixlist", -1, 100) then
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
                
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Type category tab (NEW)
            if reaper.ImGui_BeginTabItem(ctx, "Type") then
                reaper.ImGui_Text(ctx, "Track type labels in parentheses like (BUS), (Sum), (MIDI)")
                reaper.ImGui_Spacing(ctx)
                
                -- Required checkbox
                local is_required = editing_group.pattern_categories.type and editing_group.pattern_categories.type.required or false
                local changed_req, value_req = reaper.ImGui_Checkbox(ctx, "Required in Naming", is_required)
                if changed_req then
                    if not editing_group.pattern_categories.type then
                        editing_group.pattern_categories.type = { patterns = {}, required = value_req }
                    else
                        editing_group.pattern_categories.type.required = value_req
                    end
                end
                
                -- New type pattern input
                local new_type_pattern = ""
                local changed_type, value_type = reaper.ImGui_InputText(ctx, "New Type Pattern", new_type_pattern, 256)
                if changed_type then
                    new_type_pattern = value_type
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Add##type") and new_type_pattern ~= "" then
                    if not editing_group.pattern_categories.type then
                        editing_group.pattern_categories.type = { patterns = {}, required = false }
                    end
                    
                    table.insert(editing_group.pattern_categories.type.patterns, new_type_pattern)
                    new_type_pattern = ""
                end
                
                -- List of existing type patterns
                local type_patterns = editing_group.pattern_categories.type and editing_group.pattern_categories.type.patterns or {}
                if #type_patterns > 0 then
                    if reaper.ImGui_BeginListBox(ctx, "##typelist", -1, 100) then
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
                
                reaper.ImGui_EndTabItem(ctx)
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
            -- Validate required fields
            if editing_group.name == "" then
                reaper.ShowMessageBox("Group name is required.", "Validation Error", 0)
            elseif editing_group.parent_track == "" then
                reaper.ShowMessageBox("Parent track is required.", "Validation Error", 0)
            elseif editing_group.default_track == "" then
                reaper.ShowMessageBox("Default track name is required.", "Validation Error", 0)
            elseif #editing_group.patterns == 0 then
                reaper.ShowMessageBox("At least one pattern is required.", "Validation Error", 0)
            else
                -- Get existing configs
                local track_configs = LoadTrackConfigs()
                
                -- Add/update the edited group
                track_configs[editing_group.name] = editing_group
                
                -- Save the updated configs
                SaveTrackConfigs(track_configs)
                
                -- Close the popup
                reaper.ImGui_CloseCurrentPopup(ctx)
                is_editing_group = false
            end
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Cancel", button_width) then
            reaper.ImGui_CloseCurrentPopup(ctx)
            is_editing_group = false
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- Modified DrawConfigTab function to show the new/updated fields in the configuration viewer
function DrawConfigTab()
    -- Get current configurations with inheritance applied
    local track_configs = LoadTrackConfigs()
    
    -- Get current inheritance mode
    local current_mode = LoadInheritanceMode("track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local mode_names = { "Use Defaults Only", "Use Defaults + Overrides", "Use Overrides Only" }
    
    reaper.ImGui_Text(ctx, "Current Track Configurations:")
    reaper.ImGui_Spacing(ctx)
    
    -- Inheritance mode combo
    reaper.ImGui_Text(ctx, "Group Inheritance:")
    local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##track_configs_mode", current_mode - 1, table.concat(mode_names, "\0") .. "\0", -1)
    if changed_mode then
        SaveInheritanceMode("track_configs", new_mode + 1)
        -- Reload configurations with new inheritance mode
        track_configs = LoadTrackConfigs()
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
    if reaper.ImGui_Button(ctx, "Import Configuration") then
        ImportConfigFromJSON()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Export Configuration") then
        ExportConfigToJSON()
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Export Example") then
        ExportExampleConfig()
    end
    
    -- Edit Default Groups button
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Edit Default Groups") then
        -- Load current defaults
        local defaults = LoadDefaults()
        
        -- Set up for editing
        is_editing_default_groups = true
        editing_default_groups = table.copy(defaults.default_groups) or {}
        reaper.ImGui_OpenPopup(ctx, "Edit Default Groups")
    end
    
    -- Show the Edit Default Groups popup if active
    ShowEditDefaultGroupsPopup()
    
    -- Add New Group button (only enabled if not in DEFAULT_ONLY mode)
    reaper.ImGui_SameLine(ctx)
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_BeginDisabled(ctx)
    end
    
    if reaper.ImGui_Button(ctx, "Add New Group") then
        editing_group = CreateNewConfigGroup()
        is_editing_group = true
        reaper.ImGui_OpenPopup(ctx, "Edit Track Configuration")
    end
    
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_EndDisabled(ctx)
    end
    
    -- Show the Add/Edit Group popup if active
    ShowAddEditGroupPopup()
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Configuration list with collapsible headers
    reaper.ImGui_PushFont(ctx, font_mini)
    
    -- If no configurations are found
    if not track_configs or next(track_configs) == nil then
        reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No track configurations found. Import a configuration file or add a new group to get started.")
    else
        -- List all configurations
        reaper.ImGui_BeginChild(ctx, "##ConfigScroll", 0, -30, true)
        
        -- Get defaults for highlighting
        local defaults = LoadDefaults().default_groups
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
                    editing_group = table.copy(config)
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
                        SaveTrackConfigs(original_configs)
                        
                        -- Reload with inheritance
                        track_configs = LoadTrackConfigs()
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
                
                reaper.ImGui_Text(ctx, "Matching Track: " .. (config.matching_track or "None"))
                if config.matching_track_guid and config.matching_track_guid ~= "" then
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_TextColored(ctx, 0x88CC88FF, "(GUID Available)")
                end
                
                reaper.ImGui_Text(ctx, "Default Track: " .. (config.default_track or "None"))
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
            end
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_PopFont(ctx)
    
    -- Note about editing
    reaper.ImGui_Spacing(ctx)
    if current_mode == INHERITANCE_MODES.DEFAULT_ONLY then
        reaper.ImGui_TextWrapped(ctx, "In \"Use Defaults Only\" mode, you cannot modify configurations. Switch to another mode to make changes.")
    else
        reaper.ImGui_TextWrapped(ctx, "Configure track patterns and naming rules using the buttons above. You can also import/export configurations as JSON files.")
    end
end

-- Variables for editing default groups
local is_editing_default_groups = false
local editing_default_groups = {}
local selected_default_group_idx = 1

-- Helper function for deep table copy
function table.copy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = table.copy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Function to show the Edit Default Groups popup
function ShowEditDefaultGroupsPopup()
    if not is_editing_default_groups then return end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize() | reaper.ImGui_WindowFlags_NoCollapse()
    
    if reaper.ImGui_BeginPopupModal(ctx, "Edit Default Groups", true, popup_flags) then
        -- Rest of the function...
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- Main loop
function Loop()
    -- Draw UI and check if window is open
    local open = DrawMainUI()
    
    -- Continue if the UI is open
    if open then
        reaper.defer(Loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end

-- Start the loop
reaper.PreventUIRefresh(1)
Loop()
reaper.PreventUIRefresh(-1)

-- Function to get a track by its GUID
function GetTrackByGUID(guid)
    if not guid or guid == "" then
        return nil
    end
    
    -- Ensure GUID is properly formatted with braces
    if not guid:match("^{.*}$") then
        guid = "{" .. guid .. "}"
    end
    
    if reaper.APIExists("BR_GetMediaTrackByGUID") then
        return reaper.BR_GetMediaTrackByGUID(0, guid)
    else
        -- Fallback method if SWS/BR functions are not available
        local track_count = reaper.CountTracks(0)
        for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local track_guid = reaper.GetTrackGUID(track)
            if track_guid == guid then
                return track
            end
        end
    end
    
    return nil
end

-- Function to create a track from a template track
function CreateTrackFromTemplate(template_track, track_name, parent_track, insert_idx)
    if not template_track then
        -- Fall back to standard track creation if no template
        return CreateTrackUnderParent(parent_track, track_name)
    end
    
    -- Determine where to insert the new track
    if not insert_idx then
        -- Get parent track index
        local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
        insert_idx = parent_idx + 1
        
        -- Find the last track in this folder level
        local current_depth = 1
        for i = parent_idx + 1, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            
            if depth < 0 then
                current_depth = current_depth + depth
                if current_depth <= 0 then
                    insert_idx = i
                    break
                end
            elseif depth > 0 then
                current_depth = current_depth + depth
            end
        end
    end
    
    -- Create a new track at the specified index
    reaper.InsertTrackAtIndex(insert_idx, true)
    local new_track = reaper.GetTrack(0, insert_idx)
    
    -- Copy properties from template track
    reaper.TrackCopy(template_track, new_track)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    
    -- Make sure track is visible
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)     -- Show in TCP
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)   -- Show in Mixer
    
    -- Only set folder depth if it's the last track in the project
    if insert_idx == reaper.CountTracks(0) - 1 then
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
    end
    
    return new_track
end

-- Modify the existing getTrackForFile function to merge global patterns with group-specific patterns
function getTrackForFile(file_name, track_configs)
    if not track_configs or not file_name then return nil end
    
    local file_name_lower = file_name:lower()
    local highest_priority = -1
    local matched_config = nil
    local sub_route_match = nil
    
    -- Loop through all configurations to find a match
    for config_name, config in pairs(track_configs) do
        local priority = config.priority or 0
        local matched = false
        
        -- Skip if this config has a lower priority than already matched
        if priority < highest_priority then goto continue end
        
        -- Check if file matches any pattern
        for _, pattern in ipairs(config.patterns or {}) do
            if file_name_lower:find(pattern:lower()) then
                matched = true
                break
            end
        end
        
        -- Skip if no pattern matched
        if not matched then goto continue end
        
        -- Check for negative patterns (patterns to exclude)
        for _, neg_pattern in ipairs(config.negative_patterns or {}) do
            if file_name_lower:find(neg_pattern:lower()) then
                matched = false
                break
            end
        end
        
        -- Skip if excluded by negative pattern
        if not matched then goto continue end
        
        -- If matched at this point, check for sub-routes
        local sub_matched = false
        for _, sub_route in ipairs(config.sub_routes or {}) do
            local sub_match = false
            
            -- Check if file matches any pattern in the sub-route
            for _, pattern in ipairs(sub_route.patterns or {}) do
                if file_name_lower:find(pattern:lower()) then
                    sub_match = true
                    break
                end
            end
            
            if sub_match then
                sub_route_match = sub_route
                sub_matched = true
                break
            end
        end
        
        -- If match is better than previous, update
        if matched and priority >= highest_priority then
            highest_priority = priority
            matched_config = config
        end
        
        ::continue::
    end
    
    -- Return the matched configuration and any sub-route match
    return matched_config, sub_route_match
end

-- Modify the existing getTrackForFile function to merge global patterns with group-specific patterns
function getTrackForFile(file_name, track_configs)
    -- Use the original function to get the basic config
    local config = getTrackForFile(file_name, track_configs)
    
    -- If a config was found, merge with global patterns
    if config then
        -- Load global patterns
        local global_patterns = LoadGlobalPatterns()
        
        -- Merge global patterns into the config's pattern_categories
        for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
            local key = category.key
            if global_patterns[key] and not config.pattern_categories[key] then
                config.pattern_categories[key] = global_patterns[key]
            end
        end
    end
    
    return config
end

-- Function to draw the Global Patterns tab
function DrawGlobalPatternsTab()
    reaper.ImGui_TextWrapped(ctx, "Configure global pattern categories that apply to all track groups. These patterns help generate more descriptive track names by extracting information from filenames.")
    reaper.ImGui_Spacing(ctx)
    
    -- Get global patterns with inheritance applied
    local global_patterns = LoadGlobalPatterns()
    
    -- Get current inheritance mode
    local current_mode = LoadInheritanceMode("global_patterns", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local mode_names = { "Use Defaults Only", "Use Defaults + Overrides", "Use Overrides Only" }
    local modified = false
    
    -- Inheritance mode combo
    reaper.ImGui_Text(ctx, "Pattern Inheritance:")
    local changed_mode, new_mode = reaper.ImGui_Combo(ctx, "##global_patterns_mode", current_mode - 1, table.concat(mode_names, "\0") .. "\0", -1)
    if changed_mode then
        SaveInheritanceMode("global_patterns", new_mode + 1)
        -- Reload patterns with new inheritance mode
        global_patterns = LoadGlobalPatterns()
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
        -- Load current defaults
        local defaults = LoadDefaults()
        
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
    
    -- Show the Edit Default Patterns popup if active
    ShowEditDefaultPatternsPopup()
    
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
            local defaults = LoadDefaults().default_patterns
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
        SaveGlobalPatterns(global_patterns)
        reaper.ShowConsoleMsg("Global patterns saved.\n")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextWrapped(ctx, "Note: Green patterns are from defaults. Global patterns are combined with group-specific patterns (Prefix and Type) when naming tracks.")
end

-- Variables for editing default patterns
local is_editing_defaults = false
local editing_default_patterns = {}
local new_default_pattern = {}

-- Function to show the Edit Default Patterns popup
function ShowEditDefaultPatternsPopup()
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
            local defaults = LoadDefaults()
            
            -- Update the default patterns
            defaults.default_patterns = {}
            for _, category in ipairs(GLOBAL_PATTERN_CATEGORIES) do
                defaults.default_patterns[category.key] = editing_default_patterns[category.key] or {}
            end
            
            -- Save the updated defaults
            SaveDefaults(defaults)
            
            -- Close the popup
            reaper.ImGui_CloseCurrentPopup(ctx)
            is_editing_defaults = false
            
            -- Reload patterns with new defaults
            LoadGlobalPatterns()
        end
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "Cancel", button_width) then
            reaper.ImGui_CloseCurrentPopup(ctx)
            is_editing_defaults = false
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end 