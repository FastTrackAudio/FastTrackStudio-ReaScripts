--[[ 
 * ReaScript Name: FTS Import Into Template By Name
 * Description: Import audio files into template tracks based on filename patterns
 * Author: FastTrackStudio
 * Licence: GPL v3
 * REAPER: 5.0+
 * Version: 2.0
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

-- Load utilities
dofile(root_path .. "libraries/utils/Serialize Table.lua") -- Load serialization functions

-- Import dependencies
package.path = package.path .. ";" .. reaper.GetResourcePath() .. "/Scripts/FastTrackStudio Scripts/?.lua"
-- Use dofile for local utilities instead of require to avoid path issues
local Utils = {}
if pcall(function() dofile(root_path .. "Organization/import/Import Utils.lua") end) then
  Utils = _G.ImportUtils or {}
end

local ConfigManager = {}
if pcall(function() dofile(root_path .. "Organization/import/Config Manager.lua") end) then
  ConfigManager = _G.ConfigManager or {}
end

local PatternMatching = require("libraries.utils.Pattern Matching")

-- Import functions from Pattern Matching module to global scope for convenience
MatchesAnyPattern = PatternMatching.MatchesAnyPattern
MatchesNegativePattern = PatternMatching.MatchesNegativePattern
GenerateTrackName = PatternMatching.GenerateTrackName

-- Constants
local EXT_STATE_NAME = "FTS_ImportTemplate"
local DEFAULT_CONFIGS = {
    ToolTips = true,     -- Whether to show tooltips
    parent_prefix = "+", -- Default parent prefix
    parent_suffix = "+", -- Default parent suffix
    pre_filter = ""      -- Default pre-filter
}

-- Load configuration from ExtState
function LoadConfigs()
    local loaded = LoadExtStateTable(EXT_STATE_NAME, "configs", true)
    if loaded then
        return loaded
    end
    return DEFAULT_CONFIGS
end

-- Save configuration to ExtState
function SaveConfigs(configs)
    SaveExtStateTable(EXT_STATE_NAME, "configs", configs, true)
end

-- Load track configurations from ExtState
function LoadTrackConfigs()
    local loaded = LoadExtStateTable(EXT_STATE_NAME, "track_configs", true)
    if loaded and next(loaded) ~= nil then
        return loaded
    end
    -- Default configurations if none exist
    return {
        Reference = {
            patterns = {"print", "master", "smart tempo multitrack"},
            parent_track = "REF TRACK",
            default_track = "REF TRACK",
            insert_mode = "increment",
            increment_start = 1
        },
        Kick = {
            patterns = {"kick", "kik"},
            parent_track = "KICK SUM",
            default_track = "Kick",
            insert_mode = "increment",
            increment_start = 1,
            negative_patterns = {"kickler"},
            sub_routes = {
                {
                    patterns = {"sub", "sub kick"},
                    track = "Sub Kick",
                    parent_track = "KICK BUS",
                    insert_mode = "existing",
                    priority = 2
                }
            }
        },
        Snare = {
            patterns = {"snare", "snr"},
            parent_track = "SNARE SUM",
            default_track = "Snare",
            insert_mode = "increment",
            increment_start = 1
        }
    }
end

-- Save track configurations to ExtState
function SaveTrackConfigs(configs)
    SaveExtStateTable(EXT_STATE_NAME, "track_configs", configs, true)
end

-- Global track configurations (load from ext state or use defaults)
track_configs = LoadTrackConfigs()

-----------------------------------------------------------
-- UTILITIES FOR IMPORT FUNCTION --
-----------------------------------------------------------

function DebugPrint(message)
    if console then
        reaper.ShowConsoleMsg(message .. "\n")
    end
end

function isAudioFile(filename)
    local VALID_AUDIO_EXTENSIONS = {
        [".wav"] = true,
        [".mp3"] = true,
        [".aif"] = true,
        [".aiff"] = true,
        [".flac"] = true,
        [".ogg"] = true,
        [".m4a"] = true,
        [".wma"] = true
    }
    local ext = string.match(filename:lower(), "%.%w+$")
    return ext and VALID_AUDIO_EXTENSIONS[ext] or false
end

function SplitFileName(strfilename)
    -- Returns the Path, Filename, and Extension as 3 values
    local path = string.match(strfilename, "(.+[\\/])")
    local file = string.match(strfilename, "[\\/]([^\\/%.]*)%.")
    local ext = string.match(strfilename, "%.([^\\/%.]*)$")
    
    if not path then path = "" end
    if not file then file = strfilename end
    if not ext then ext = "" end
    
    return path, file, ext
end

-- Get track from GUID
function GetTrackByGUID(guid)
    if not guid or guid == "" then
        return nil
    end
    
    -- Ensure GUID is properly formatted with braces
    if not guid:match("^{.*}$") then
        guid = "{" .. guid .. "}"
    end
    
    return reaper.BR_GetMediaTrackByGUID(0, guid)
end

-- Get existing tracks BEFORE processing files 
function GetTracksNames()
    local tracks = {}
    local track_hierarchy = {}
    local parent_tracks = {}
    local folder_tracks = {}  -- New table to track folder tracks
    local guid_map = {}       -- New table to map GUIDs to tracks

    local count_tracks = reaper.CountTracks(0)
    for i = 0, count_tracks - 1 do
        local track = reaper.GetTrack(0, i)
        local retval, track_name = reaper.GetTrackName(track)
        local track_name_lower = track_name:lower()
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        local guid = reaper.GetTrackGUID(track)

        -- Store track in main lookup
        tracks[track_name_lower] = track
        
        -- Store track in GUID lookup
        if guid then
            guid_map[guid] = track
        end

        -- If this is a folder track (depth == 1), store it as a potential parent
        if depth == 1 then
            parent_tracks[track_name_lower] = track
            track_hierarchy[track_name_lower] = {
                track = track,
                children = {}
            }
            folder_tracks[track_name_lower] = true  -- Mark as folder track
        end
    end

    -- Store the hierarchies for later use
    tracks._parent_tracks = parent_tracks
    tracks._hierarchy = track_hierarchy
    tracks._folder_tracks = folder_tracks  -- Store folder tracks lookup
    tracks._guid_map = guid_map           -- Store GUID to track mapping
    return tracks
end

function CreateParentTrack(parent_name)
    -- Get the count before insertion
    local track_count = reaper.CountTracks(0)
    
    -- Create the new track at the end
    reaper.InsertTrackAtIndex(track_count, true)
    local parent_track = reaper.GetTrack(0, track_count)
    
    -- Set the track name
    reaper.GetSetMediaTrackInfo_String(parent_track, "P_NAME", parent_name, true)
    
    -- Make it a folder only if it's a new parent track at the end
    if track_count == reaper.CountTracks(0) - 1 then
        reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    end
    
    return parent_track
end

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
                insert_idx = i
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
    
    -- Only set folder depth if it's the last track in the project
    if insert_idx == reaper.CountTracks(0) - 1 then
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", 0)
    end
    
    return new_track
end

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

function getTrackForFile(file_name)
    -- Clean the file name first
    local clean_name = PatternMatching.CleanFileName(file_name)
    
    -- Find the best matching configuration for this file
    local config = PatternMatching.FindMatchingConfig(clean_name, track_configs)
    
    -- Return the matched configuration or default
    return config
end

function LogTrackHierarchy()
    reaper.ShowConsoleMsg("\nTrack Hierarchy:\n")
    reaper.ShowConsoleMsg("------------------\n")
    
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
        local _, name = reaper.GetTrackName(track)
        local indent = string.rep("  ", depth > 0 and depth or 0)
        reaper.ShowConsoleMsg(string.format("%s%s (Depth: %d)\n", indent, name, depth))
    end
    reaper.ShowConsoleMsg("------------------\n")
end

-----------------------------------------------------------
-- IMPORT FUNCTION --
-----------------------------------------------------------

function ImportAudioFiles(configs)
    -- Use provided configs or get from ext state
    local config_settings = configs or LoadConfigs()
    
    if not reaper.JS_Dialog_BrowseForOpenFiles then
        reaper.MB("Missing dependency:\nPlease install js_reascriptAPI REAPER extension available from reapack. See Reapack.com for more infos.", "Error", 0)
        return
    end
    
    reaper.Undo_BeginBlock()
    
    local retval, fileNames = reaper.JS_Dialog_BrowseForOpenFiles("Import media", "", "", "", true)
    
    if retval and retval > 0 then
        -- Store initial cursor position
        local initial_cursor_pos = reaper.GetCursorPosition()
        
        reaper.SelectAllMediaItems(0, false)

        -- Get existing tracks BEFORE processing files
        local tracks = GetTracksNames()

        local files = {}
        local folder = ''
        local i = 1
        local cur_pos = reaper.GetCursorPosition()  -- Store the current cursor position
        local not_sorted_folder = "NOT SORTED"  -- Default folder name for failed items
        local not_sorted_track = nil
        local failed_count = 0  -- Initialize counter
        local success_count = 0  -- Initialize counter
        local total_processed = 0  -- Track total files processed

        local used_tracks = {}  -- Track used tracks for all types
        local failed_files = {}  -- Track which files failed and why

        local stereo_pairs = {}  -- Track stereo pairs for ordering
        local files_to_process = {}  -- Store files for ordered processing

        -- First pass: collect all files and identify stereo pairs
        for file in fileNames:gmatch("[^\0]*") do
            if i > 1 then
                if not isAudioFile(file) then
                    reaper.ShowConsoleMsg("Skipping non-audio file: " .. file .. "\n")
                    goto continue_collect
                end
                
                local path, file_name, extension = SplitFileName(file)
                local track_config = getTrackForFile(file_name)
                
                table.insert(files_to_process, {
                    file = file,
                    name = file_name,
                    config = track_config
                })
                
                if track_config and track_config.stereo_side then
                    local base_name = track_config.default_track:gsub("%s+[LR]$", "")
                    stereo_pairs[base_name] = stereo_pairs[base_name] or {}
                    stereo_pairs[base_name][track_config.stereo_side] = #files_to_process
                end
            else
                folder = file
            end
            ::continue_collect::
            i = i + 1
        end

        -- Sort stereo pairs to ensure L comes before R
        for base_name, pair in pairs(stereo_pairs) do
            if pair.L and pair.R and files_to_process[pair.L].config.stereo_side == "R" then
                -- Swap the files
                files_to_process[pair.L], files_to_process[pair.R] = files_to_process[pair.R], files_to_process[pair.L]
            end
        end

        -- Process files in order
        for _, file_info in ipairs(files_to_process) do
            local file = file_info.file
            local file_name = file_info.name
            local track_config = file_info.config

            -- Debugging output
            reaper.ShowConsoleMsg("Processing file: " .. file_name .. "\n")

            if track_config then
                reaper.ShowConsoleMsg("Matched track config: " .. (track_config.parent_track or "No Parent Track") .. "\n")
                
                -- Skip Printed FX files for now, we'll handle them later
                if track_config.is_printed_fx then
                    goto continue_processing
                end

                -- Try to find parent track by GUID first, then by name
                local parent_track = nil
                if track_config.parent_track_guid and track_config.parent_track_guid ~= "" then
                    parent_track = tracks._guid_map[track_config.parent_track_guid] or GetTrackByGUID(track_config.parent_track_guid)
                end
                
                -- If no parent track found by GUID, try by name
                if not parent_track then
                    parent_track = tracks[track_config.parent_track:lower()]
                end
                
                -- Create parent track if not found
                if not parent_track and track_config.parent_track then
                    parent_track = CreateParentTrack(track_config.parent_track)
                    tracks[track_config.parent_track:lower()] = parent_track
                end

                if parent_track then
                    -- Logic for placing the file in the correct track
                    local existing_track_names = {}
                    for name, _ in pairs(tracks) do
                        if name ~= "_folder_tracks" and name ~= "_guid_map" and name ~= "_parent_tracks" and name ~= "_hierarchy" then
                            table.insert(existing_track_names, name)
                        end
                    end
                    
                    -- Track existing items with this configuration to handle "only_number_when_multiple"
                    local existing_count = used_tracks[track_config.name] or 0
                    local should_add_number = not track_config.only_number_when_multiple or existing_count > 0
                    
                    -- Use our utility function to generate an appropriate track name
                    local target_track_name = PatternMatching.GenerateTrackName(file_name, track_config, existing_track_names)
                    
                    -- Modify the track name based on the "only_number_when_multiple" setting
                    if track_config.insert_mode == "increment" and track_config.only_number_when_multiple and existing_count == 0 then
                        -- Strip the number if this is the first track and "only_number_when_multiple" is true
                        target_track_name = track_config.default_track
                    end
                    
                    -- Find or create the target track
                    local target_track = tracks[target_track_name:lower()]
                    -- Skip if the target track is a folder track
                    if target_track and tracks._folder_tracks[target_track_name:lower()] then
                        target_track = nil
                    end
                    
                    -- Create the target track if it doesn't exist
                    if not target_track and (track_config.create_if_missing or track_config.insert_mode == "increment") then
                        -- Find template track by GUID first
                        local template_track = nil
                        if track_config.matching_track_guid and track_config.matching_track_guid ~= "" then
                            template_track = tracks._guid_map[track_config.matching_track_guid] or GetTrackByGUID(track_config.matching_track_guid)
                        end
                        
                        -- Try by name if GUID not found
                        if not template_track and track_config.matching_track and track_config.matching_track ~= "" then
                            template_track = tracks[track_config.matching_track:lower()]
                        end
                        
                        -- Create track using template if available
                        if template_track then
                            target_track = CreateTrackFromTemplate(template_track, target_track_name, parent_track)
                        else
                            target_track = CreateTrackUnderParent(parent_track, target_track_name)
                        end
                        
                        tracks[target_track_name:lower()] = target_track
                    end

                    if target_track then
                        reaper.SetOnlyTrackSelected(target_track)
                        reaper.SetEditCurPos(cur_pos, false, false)
                        reaper.InsertMedia(file, 0)
                        used_tracks[track_config.name] = (used_tracks[track_config.name] or 0) + 1
                        success_count = success_count + 1
                        total_processed = total_processed + 1
                        reaper.ShowConsoleMsg("Successfully placed file in track: " .. target_track_name .. "\n")
                    else
                        -- Handle failed placement
                        reaper.ShowConsoleMsg("Failed to place file: " .. file_name .. "\n")
                        table.insert(failed_files, {
                            name = file_name,
                            reason = "Could not create or find target track: " .. target_track_name
                        })
                        failed_count = failed_count + 1
                        total_processed = total_processed + 1
                        -- Place in NOT SORTED
                        if not not_sorted_track then
                            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                            not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                            reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                            reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                        end
                        
                        -- Create a new track under NOT SORTED for this file
                        local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                        reaper.SetOnlyTrackSelected(unsorted_track)
                        reaper.SetEditCurPos(cur_pos, false, false)
                        reaper.InsertMedia(file, 0)
                    end
                else
                    -- Handle missing parent track
                    reaper.ShowConsoleMsg("Parent track not found: " .. track_config.parent_track .. "\n")
                    table.insert(failed_files, {
                        name = file_name,
                        reason = "Parent track not found: " .. track_config.parent_track
                    })
                    failed_count = failed_count + 1
                    total_processed = total_processed + 1
                    -- Place in NOT SORTED
                    if not not_sorted_track then
                        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                        not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                        reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                        reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                    end
                    
                    -- Create a new track under NOT SORTED for this file
                    local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                    reaper.SetOnlyTrackSelected(unsorted_track)
                    reaper.SetEditCurPos(cur_pos, false, false)
                    reaper.InsertMedia(file, 0)
                end
            else
                -- Handle no matching config
                reaper.ShowConsoleMsg("No matching track config found for: " .. file_name .. "\n")
                table.insert(failed_files, {
                    name = file_name,
                    reason = "No matching track config found"
                })
                failed_count = failed_count + 1
                total_processed = total_processed + 1
                -- Place in NOT SORTED
                if not not_sorted_track then
                    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
                    not_sorted_track = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
                    reaper.GetSetMediaTrackInfo_String(not_sorted_track, "P_NAME", not_sorted_folder, true)
                    reaper.SetMediaTrackInfo_Value(not_sorted_track, "I_FOLDERDEPTH", 1)  -- Make it a folder
                end
                
                -- Create a new track under NOT SORTED for this file
                local unsorted_track = CreateTrackUnderParent(not_sorted_track, file_name)
                reaper.SetOnlyTrackSelected(unsorted_track)
                reaper.SetEditCurPos(cur_pos, false, false)
                reaper.InsertMedia(file, 0)
            end

            ::continue_processing::
            table.insert(files, { path = folder .. file, name = file_name })
        end

        -- Now handle Printed FX files separately
        local printed_fx_files = {}
        for _, file_info in ipairs(files_to_process) do
            if file_info.config and file_info.config.is_printed_fx then
                table.insert(printed_fx_files, file_info)
            end
        end

        if #printed_fx_files > 0 then
            local printed_fx_track = CreateParentTrack("PRINTED FX")
            local fx_count = 0
            
            for _, file_info in ipairs(printed_fx_files) do
                local track_name = file_info.config.default_track
                if fx_count > 0 then
                    track_name = track_name .. " " .. fx_count
                end
                
                local track = CreateTrackUnderParent(printed_fx_track, track_name)
                reaper.SetOnlyTrackSelected(track)
                reaper.SetEditCurPos(cur_pos, false, false)
                reaper.InsertMedia(file_info.file, 0)
                fx_count = fx_count + 1
                success_count = success_count + 1
                total_processed = total_processed + 1
            end
        end

        -- Print summary
        reaper.ShowConsoleMsg("\nImport Summary:\n")
        reaper.ShowConsoleMsg("Successfully sorted items: " .. tostring(success_count) .. "\n")
        reaper.ShowConsoleMsg("Failed to sort items: " .. tostring(failed_count) .. "\n")
        reaper.ShowConsoleMsg("Total files processed: " .. tostring(total_processed) .. "\n")

        if #failed_files > 0 then
            reaper.ShowConsoleMsg("\nFailed Files Report:\n")
            for _, failure in ipairs(failed_files) do
                reaper.ShowConsoleMsg(string.format("File: %s\nReason: %s\n\n", failure.name, failure.reason))
            end
        end

        LogTrackHierarchy()
        
        -- Restore cursor position
        reaper.SetEditCurPos(initial_cursor_pos, false, false)
        
        reaper.Undo_EndBlock("Import Audio Files into Template", -1)
        
        return success_count, failed_count, total_processed
    end
    
    return 0, 0, 0
end

-- If this script is being run directly (not required by another script),
-- launch the ImportAudioFiles function
if is_direct_run then
    ImportAudioFiles()
end

-- Return the main functions and configurations if being required
return {
    ImportAudioFiles = ImportAudioFiles,
    track_configs = track_configs,
    LoadTrackConfigs = LoadTrackConfigs,
    SaveTrackConfigs = SaveTrackConfigs,
    LoadConfigs = LoadConfigs,
    SaveConfigs = SaveConfigs
} 