-- Volume Balancer Core
-- Script to balance volume between tracks while maintaining overall loudness
-- When adjusting one track's volume, other tracks are adjusted inversely to maintain total volume

local info = debug.getinfo(1, "S")
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])

-- Get the path to the FastTrackStudio Scripts root folder (two levels up)
local root_path = script_path:match("(.*[/\\])Tracks[/\\].*[/\\]")
if not root_path then
    root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

-- Load utilities from the libraries/utils folder
dofile(root_path .. "libraries/utils/Serialize Table.lua") -- Load serialization functions

-- Load GUI utilities
local GUI = dofile(root_path .. "libraries/utils/GUI Functions.lua")

-- Script name for ExtState
local ScriptName = "Volume Balancer"

-- Store track groups and their volumes
local track_groups = {}  -- Each group is a table of track GUIDs
local prev_volumes = {}  -- Store previous volumes for each group
local user_changed_tracks = {} -- Track which tracks were changed by the user

-- Configuration
local Configs = {
    MinVolume = -60.0,    -- Minimum volume in dB
    MaxVolume = 6.0,      -- Maximum volume in dB
    UseInfMin = false,    -- Whether to use -inf dB as minimum
    ReportValues = false, -- Whether to report values to debug log
    LastReportTime = 0,   -- Last time values were reported
    NudgeAmount = 1.0,    -- Default nudge amount in dB
    AutoNudgeAmount = true, -- Whether to automatically set nudge amount based on group size
    DebugMode = false,    -- Whether to enable debug printing
    BackgroundRunning = false -- Whether background mode is currently active
}

-- Helper functions
function GetTrackGUID(track)
    if not track then
        return nil
    end
    return reaper.GetTrackGUID(track)
end

function GetTrackFromGUID(guid)
    -- Ensure GUID is properly formatted with braces
    if not guid:match("^{.*}$") then
        guid = "{" .. guid .. "}"
    end
    return reaper.BR_GetMediaTrackByGUID(0, guid)
end

function GetTrackVolumes(group)
    local volumes = {}
    local num_tracks = #group
    
    for i = 1, num_tracks do
        local track = GetTrackFromGUID(group[i])
        if track then
            local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
            volumes[i] = volume
        end
    end
    
    return volumes, num_tracks
end

-- Load saved groups from ExtState
function LoadGroups()
    local loaded = LoadExtStateTable(ScriptName, "groups", true)
    if loaded then
        track_groups = loaded
        -- Initialize prev_volumes for each group
        for i, group in ipairs(track_groups) do
            prev_volumes[i] = GetTrackVolumes(group)
        end
    end
end

-- Save groups to ExtState
function SaveGroups()
    SaveExtStateTable(ScriptName, "groups", track_groups, true)
end

-- Load configuration from ExtState
function LoadConfigs()
    local success, loaded
    
    -- Try to load configs from ExtState
    success, loaded = pcall(function() 
        return LoadExtStateTable(ScriptName, "configs", true) 
    end)
    
    -- If successful and we got a valid table
    if success and loaded and type(loaded) == "table" then
        -- Ensure all required config values exist
        if loaded.NudgeAmount == nil then loaded.NudgeAmount = 1.0 end
        if loaded.AutoNudgeAmount == nil then loaded.AutoNudgeAmount = true end
        if loaded.MinVolume == nil then loaded.MinVolume = -60.0 end
        if loaded.MaxVolume == nil then loaded.MaxVolume = 6.0 end
        if loaded.UseInfMin == nil then loaded.UseInfMin = false end
        if loaded.ReportValues == nil then loaded.ReportValues = false end
        if loaded.LastReportTime == nil then loaded.LastReportTime = 0 end
        if loaded.DebugMode == nil then loaded.DebugMode = false end
        if loaded.BackgroundRunning == nil then loaded.BackgroundRunning = false end
        
        Configs = loaded
        return loaded
    else
        -- Return a default configuration if loading failed
        local default_configs = {
            MinVolume = -60.0,    -- Minimum volume in dB
            MaxVolume = 6.0,      -- Maximum volume in dB
            UseInfMin = false,    -- Whether to use -inf dB as minimum
            ReportValues = false, -- Whether to report values to debug log
            LastReportTime = 0,   -- Last time values were reported
            NudgeAmount = 1.0,    -- Default nudge amount in dB
            AutoNudgeAmount = true, -- Whether to automatically set nudge amount based on group size
            DebugMode = false,    -- Whether to enable debug printing
            BackgroundRunning = false -- Whether background mode is currently active
        }
        
        -- Update the global Configs with default values
        Configs = default_configs
        
        -- Try to save the default configs to ExtState
        pcall(function() SaveExtStateTable(ScriptName, "configs", default_configs, true) end)
        
        return default_configs
    end
end

-- Save configuration to ExtState
function SaveConfigs()
    SaveExtStateTable(ScriptName, "configs", Configs, true)
end

-- Debug print function that only prints when debug mode is enabled
function DebugPrint(format, ...)
    if Configs.DebugMode then
        local args = {...}
        local message = string.format(format, table.unpack(args))
        reaper.ShowConsoleMsg(message)
    end
end

-- Function to report volume values to debug log
function ReportVolumeValues()
    if not Configs.ReportValues then return end
    
    local current_time = reaper.time_precise()
    if current_time - Configs.LastReportTime < 5.0 then return end
    
    Configs.LastReportTime = current_time
    
    reaper.ClearConsole()
    DebugPrint("Volume Balancer - Volume Report (" .. os.date("%H:%M:%S") .. ")\n")
    DebugPrint("==========================================\n\n")
    
    for group_idx, group in ipairs(track_groups) do
        DebugPrint("Group " .. group_idx .. ":\n")
        DebugPrint("------------------------------------------\n")
        
        local total_linear = 0
        local volumes = {}
        local db_values = {}
        local non_zero_count = 0
        
        -- First pass: collect all volumes
        for i, guid in ipairs(group) do
            local track = GetTrackFromGUID(guid)
            if track then
                local _, track_name = reaper.GetTrackName(track)
                local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
                local volume_db = volume > 0 and 20 * math.log(volume, 10) or -150
                
                volumes[i] = volume
                db_values[i] = volume_db
                total_linear = total_linear + volume
                
                if volume > 0 then
                    non_zero_count = non_zero_count + 1
                end
                
                DebugPrint(string.format("Track %d: %s\n", i, track_name))
                DebugPrint(string.format("  Volume: %.6f (%.4f dB)\n", volume, volume_db))
            end
        end
        
        -- Calculate total volume in dB
        local total_db = total_linear > 0 and 20 * math.log(total_linear, 10) or -150
        
        DebugPrint("\nTotal Volume: " .. string.format("%.6f (%.4f dB)\n", total_linear, total_db))
        
        -- Check if volumes are balanced (should sum to 1.0 for perfect null)
        local expected_volume = 1.0 / #group
        local expected_db = -20 * math.log(#group, 10)
        
        DebugPrint(string.format("Expected per-track volume: %.6f (%.4f dB)\n", expected_volume, expected_db))
        
        -- Check for discrepancies using a more sophisticated approach
        -- The primary indicator of correct null testing is that the total volume is 1.0
        
        -- First, check if the total volume is close to 1.0
        local total_volume_discrepancy = math.abs(total_linear - 1.0)
        local total_volume_ok = total_volume_discrepancy < 0.0001
        
        -- If the total volume is exactly 1.0, we consider the tracks to be balanced correctly
        -- regardless of individual track volumes
        if total_volume_ok then
            DebugPrint("All volumes are balanced correctly (total = 1.0).\n")
        else
            DebugPrint(string.format("WARNING: Total volume discrepancy: %.6f (should be 1.0)\n", total_volume_discrepancy))
            
            -- Only check for ratio discrepancies if we have more than one non-zero track
            if non_zero_count > 1 then
                -- Calculate the average volume of non-zero tracks
                local avg_volume = total_linear / non_zero_count
                
                -- Check each track's ratio to the average
                local max_ratio_discrepancy = 0
                local max_ratio_track = 0
                
                for i, volume in ipairs(volumes) do
                    if volume > 0 then
                        local ratio = volume / avg_volume
                        local ratio_discrepancy = math.abs(ratio - 1.0)
                        
                        if ratio_discrepancy > max_ratio_discrepancy then
                            max_ratio_discrepancy = ratio_discrepancy
                            max_ratio_track = i
                        end
                    end
                end
                
                -- Only report ratio discrepancy if it's significant
                if max_ratio_discrepancy > 0.0001 then
                    local track_name = "unknown"
                    local track = GetTrackFromGUID(group[max_ratio_track])
                    if track then
                        _, track_name = reaper.GetTrackName(track)
                    end
                    
                    DebugPrint(string.format("WARNING: Volume ratio discrepancy: %.6f in track '%s'\n", 
                                           max_ratio_discrepancy, track_name))
                end
            end
        end
        
        DebugPrint("\n")
    end
    
    DebugPrint("==========================================\n")
end

-- Function to adjust a track's volume while maintaining balance
function AdjustTrackVolume(track, volume_change_db, group)
    -- Get the current volume
    local current_volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
    if not current_volume or type(current_volume) ~= "number" or current_volume <= 0 then
        return
    end
    
    -- Get track name for logging
    local _, track_name = reaper.GetTrackName(track)
    
    -- Log the nudge operation
    DebugPrint("Nudging track '%s' by %.2f dB\n", track_name, volume_change_db)
    
    -- Calculate the new volume in dB
    local current_db = 20 * math.log(current_volume, 10)
    local new_db = current_db + volume_change_db
    
    -- Clamp to min/max limits
    local min_db = Configs.UseInfMin and -150 or Configs.MinVolume
    new_db = math.max(min_db, math.min(Configs.MaxVolume, new_db))
    
    -- Convert back to linear
    local new_volume
    if new_db <= -150 then
        new_volume = 0.0
    else
        new_volume = 10 ^ (new_db / 20)
    end
    
    -- Find the track's index in the group
    local track_idx = nil
    local track_guid = GetTrackGUID(track)
    for i, guid in ipairs(group) do
        if guid == track_guid then
            track_idx = i
            break
        end
    end
    
    if track_idx then
        -- Mark this track as changed by the user
        user_changed_tracks[track_guid] = true
        
        -- Find the group index
        local group_idx = nil
        for i, g in ipairs(track_groups) do
            if g == group then
                group_idx = i
                break
            end
        end
        
        if group_idx then
            -- Calculate the exact linear volume change
            local volume_change_ratio = new_volume / current_volume
            
            -- Log the volume change ratio
            DebugPrint("Volume change ratio: %.6f\n", volume_change_ratio)
            
            -- Calculate the adjustment for other tracks to maintain null test
            -- For a group of n tracks, if one track changes by a factor of x,
            -- each of the (n-1) other tracks should change by a factor of 1/x^(1/(n-1))
            -- This ensures that the product of all volumes remains constant
            local adjustment_factor = 1 / (volume_change_ratio ^ (1 / (#group - 1)))
            
            -- Log the adjustment factor
            DebugPrint("Adjustment factor for other tracks: %.6f\n", adjustment_factor)
            
            -- Calculate the new volumes for all tracks
            local new_volumes = {}
            local total_volume = 0
            
            -- First, set the new volume for the changed track
            new_volumes[track_idx] = new_volume
            total_volume = total_volume + new_volume
            
            -- Then calculate the new volumes for all other tracks
            for i, guid in ipairs(group) do
                if guid ~= track_guid then
                    local other_track = GetTrackFromGUID(guid)
                    if other_track then
                        local other_volume = reaper.GetMediaTrackInfo_Value(other_track, "D_VOL")
                        if other_volume and type(other_volume) == "number" and other_volume > 0 then
                            -- Calculate new volume using the adjustment factor
                            local new_other_volume = other_volume * adjustment_factor
                            
                            -- Check if this would exceed min or max limits
                            local other_db = 20 * math.log(new_other_volume, 10)
                            if (Configs.UseInfMin and other_db < -150) or (not Configs.UseInfMin and other_db < Configs.MinVolume) or other_db > Configs.MaxVolume then
                                -- If it would exceed limits, clamp it
                                if (Configs.UseInfMin and other_db < -150) or (not Configs.UseInfMin and other_db < Configs.MinVolume) then
                                    local min_db = Configs.UseInfMin and -150 or Configs.MinVolume
                                    new_other_volume = 10 ^ (min_db / 20)
                                else
                                    new_other_volume = 10 ^ (Configs.MaxVolume / 20)
                                end
                            end
                            
                            -- Store the new volume
                            new_volumes[i] = new_other_volume
                            total_volume = total_volume + new_other_volume
                        end
                    end
                end
            end
            
            -- Calculate the correction factor to ensure total volume is exactly 1.0
            local correction_factor = 1.0 / total_volume
            
            -- Log the correction factor
            DebugPrint("Correction factor for perfect null: %.6f\n", correction_factor)
            
            -- Apply the correction to all tracks
            for i, guid in ipairs(group) do
                local check_track = GetTrackFromGUID(guid)
                if check_track then
                    local volume = new_volumes[i]
                    if volume and type(volume) == "number" and volume > 0 then
                        local corrected_volume = volume * correction_factor
                        
                        -- Handle -inf dB case
                        if corrected_volume <= 0.0000001 then
                            reaper.SetMediaTrackInfo_Value(check_track, "D_VOL", 0.0)
                        else
                            reaper.SetMediaTrackInfo_Value(check_track, "D_VOL", corrected_volume)
                        end
                    end
                end
            end
            
            -- Update the previous volumes for this group
            prev_volumes[group_idx] = GetTrackVolumes(group)
            
            -- Log the final volumes
            DebugPrint("Final volumes after adjustment:\n")
            for i = 1, #group do
                local check_track = GetTrackFromGUID(group[i])
                if check_track then
                    local _, name = reaper.GetTrackName(check_track)
                    local volume = reaper.GetMediaTrackInfo_Value(check_track, "D_VOL")
                    if volume and type(volume) == "number" and volume > 0 then
                        local db = 20 * math.log(volume, 10)
                        DebugPrint("  %s: %.6f (%.4f dB)\n", name, volume, db)
                    end
                end
            end
            DebugPrint("\n")
        end
    end
end

-- Function to reset a group's volumes to the default value
function ResetGroupVolumes(group)
    -- Calculate the default volume based on the number of tracks
    -- For n tracks, each track should be at -20 * log10(n) dB
    -- This ensures that the total volume is equivalent to one track at 0 dB
    local num_tracks = #group
    
    -- Calculate the exact dB value for perfect null testing
    local default_db = -20 * math.log(num_tracks, 10)
    
    -- Convert dB to linear with high precision
    local reset_volume = 10^(default_db / 20)
    
    -- Apply the exact volume to all tracks
    for _, guid in ipairs(group) do
        local track = GetTrackFromGUID(guid)
        if track then
            -- Set the volume directly using the linear value
            reaper.SetMediaTrackInfo_Value(track, "D_VOL", reset_volume)
        end
    end
    
    -- Update the previous volumes for this group
    for i, g in ipairs(track_groups) do
        if g == group then
            prev_volumes[i] = GetTrackVolumes(g)
            break
        end
    end
    
    -- Add undo point
    reaper.Undo_OnStateChangeEx("Reset group volumes", -1, -1)
end

-- Function to create a new group from selected tracks
function CreateNewGroup()
    local num_tracks = reaper.CountSelectedTracks(0)
    if num_tracks < 2 then
        reaper.ShowMessageBox("Please select at least 2 tracks", "Error", 0)
        return
    end

    local new_group = {}
    local valid_tracks = 0
    local debug_info = {}
    
    for i = 0, num_tracks - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
            local guid = GetTrackGUID(track)
            local _, track_name = reaper.GetTrackName(track)
            table.insert(debug_info, string.format("Track %d: %s (GUID: %s)", i+1, track_name, guid or "nil"))
            
            if guid and guid ~= "" then
                table.insert(new_group, guid)
                valid_tracks = valid_tracks + 1
            end
        end
    end
    
    if valid_tracks >= 2 then
        table.insert(track_groups, new_group)
        prev_volumes[#track_groups] = GetTrackVolumes(new_group)
        SaveGroups()
    else
        local debug_message = "Debug Info:\n\n" .. table.concat(debug_info, "\n") .. 
                            string.format("\n\nFound %d valid tracks out of %d selected", valid_tracks, num_tracks)
        reaper.ShowMessageBox(debug_message, "Error Creating Group", 0)
    end
end

-- Function to select all tracks in a group
function SelectGroupTracks(group)
    -- Unselect all tracks first
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Select all tracks in the group
    for _, guid in ipairs(group) do
        local track = GetTrackFromGUID(guid)
        if track then
            reaper.SetTrackSelected(track, true)
        end
    end
    
    -- Update UI
    reaper.TrackList_AdjustWindows(false)
end

-- Function to remove a group
function RemoveGroup(group_idx)
    if group_idx and group_idx > 0 and group_idx <= #track_groups then
        table.remove(track_groups, group_idx)
        table.remove(prev_volumes, group_idx)
        SaveGroups()
    end
end

-- Main function to process volume adjustments
function Main()
    -- Process each group
    for group_idx, group in ipairs(track_groups) do
        local volumes, num_tracks = GetTrackVolumes(group)
        
        -- Check if this is the first run for this group
        if not prev_volumes[group_idx] then
            prev_volumes[group_idx] = volumes
            goto continue
        end
        
        -- Find which track changed and by how much
        local changed_track = nil
        local volume_change = 0
        local old_volume = 0
        local new_volume = 0
        local changed_track_guid = nil
        
        -- First, check if any track has changed significantly
        for i = 1, num_tracks do
            -- Ensure both volumes exist and are valid numbers
            if volumes[i] and prev_volumes[group_idx][i] and 
               type(volumes[i]) == "number" and type(prev_volumes[group_idx][i]) == "number" and
               volumes[i] > 0 and prev_volumes[group_idx][i] > 0 and
               math.abs(volumes[i] - prev_volumes[group_idx][i]) > 0.0001 then
                
                changed_track = i
                old_volume = prev_volumes[group_idx][i]
                new_volume = volumes[i]
                changed_track_guid = group[i]
                
                -- Calculate the change in dB
                local old_db = 20 * math.log(old_volume, 10)
                local new_db = 20 * math.log(new_volume, 10)
                volume_change = new_db - old_db
                break
            end
        end
        
        -- If a track changed and it wasn't changed by the script, adjust others
        if changed_track and not user_changed_tracks[changed_track_guid] then
            -- Mark this track as changed by the user
            user_changed_tracks[changed_track_guid] = true
            
            -- Get the track that changed
            local track = GetTrackFromGUID(group[changed_track])
            if track then
                -- Use the same precise adjustment method as in AdjustTrackVolume
                -- Calculate the exact linear volume change
                local volume_change_ratio = new_volume / old_volume
                
                -- Calculate the adjustment for other tracks to maintain null test
                -- For a group of n tracks, if one track changes by a factor of x,
                -- each of the (n-1) other tracks should change by a factor of 1/x^(1/(n-1))
                -- This ensures that the product of all volumes remains constant
                local adjustment_factor = 1 / (volume_change_ratio ^ (1 / (num_tracks - 1)))
                
                -- Calculate the new volumes for all tracks
                local new_volumes = {}
                local total_volume = 0
                
                -- First, set the new volume for the changed track
                new_volumes[changed_track] = new_volume
                total_volume = total_volume + new_volume
                
                -- Then calculate the new volumes for all other tracks
                for i = 1, num_tracks do
                    if i ~= changed_track then
                        local other_track = GetTrackFromGUID(group[i])
                        if other_track then
                            local other_volume = volumes[i]
                            if other_volume and type(other_volume) == "number" and other_volume > 0 then
                                -- Calculate new volume using the adjustment factor
                                local new_other_volume = other_volume * adjustment_factor
                                
                                -- Check if this would exceed min or max limits
                                local other_db = 20 * math.log(new_other_volume, 10)
                                if (Configs.UseInfMin and other_db < -150) or (not Configs.UseInfMin and other_db < Configs.MinVolume) or other_db > Configs.MaxVolume then
                                    -- If it would exceed limits, clamp it
                                    if (Configs.UseInfMin and other_db < -150) or (not Configs.UseInfMin and other_db < Configs.MinVolume) then
                                        local min_db = Configs.UseInfMin and -150 or Configs.MinVolume
                                        new_other_volume = 10 ^ (min_db / 20)
                                    else
                                        new_other_volume = 10 ^ (Configs.MaxVolume / 20)
                                    end
                                end
                                
                                -- Store the new volume
                                new_volumes[i] = new_other_volume
                                total_volume = total_volume + new_other_volume
                            end
                        end
                    end
                end
                
                -- Calculate the correction factor to ensure total volume is exactly 1.0
                local correction_factor = 1.0 / total_volume
                
                -- Apply the correction to all tracks
                for i = 1, num_tracks do
                    local check_track = GetTrackFromGUID(group[i])
                    if check_track then
                        local volume = new_volumes[i]
                        if volume and type(volume) == "number" and volume > 0 then
                            local corrected_volume = volume * correction_factor
                            
                            -- Handle -inf dB case
                            if corrected_volume <= 0.0000001 then
                                reaper.SetMediaTrackInfo_Value(check_track, "D_VOL", 0.0)
                            else
                                reaper.SetMediaTrackInfo_Value(check_track, "D_VOL", corrected_volume)
                            end
                        end
                    end
                end
            end
        end
        
        -- Store current volumes for next run
        prev_volumes[group_idx] = GetTrackVolumes(group)
        
        ::continue::
    end
    
    -- Clear the user_changed_tracks table for the next run
    user_changed_tracks = {}
    
    -- Report values if enabled
    ReportVolumeValues()
end

-- Set ToolBar Button ON
function SetButtonON()
    is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    state = reaper.GetToggleCommandStateEx(sec, cmd)
    reaper.SetToggleCommandState(sec, cmd, 1) -- Set ON
    reaper.RefreshToolbar2(sec, cmd)
end

-- Set ToolBar Button OFF
function SetButtonOFF()
    is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    state = reaper.GetToggleCommandStateEx(sec, cmd)
    reaper.SetToggleCommandState(sec, cmd, 0) -- Set OFF
    reaper.RefreshToolbar2(sec, cmd)
end

-- Main loop
function Loop()
    -- Check if we should be running
    local configs = LoadConfigs()
    
    -- If configs is nil or BackgroundRunning is explicitly set to false, exit the loop
    if not configs or configs.BackgroundRunning == false then
        -- Background mode has been turned off, exit the loop
        DebugPrint("Background mode turned off, exiting loop\n")
        SetButtonOFF()
        return -- Exit the defer loop
    end
    
    -- Always run the Main function to process volume adjustments
    Main()
    
    -- Continue running in the background
    reaper.defer(Loop)
end

-- Initialize
function Init()
    -- Load saved groups and configs
    pcall(LoadGroups) -- Use pcall to prevent errors
    
    -- Make sure Configs exists
    local configs = LoadConfigs()
    
    -- Set toolbar button state based on configs
    if configs and configs.BackgroundRunning then
        SetButtonON()
        
        -- Start the loop if background mode is enabled
        reaper.defer(Loop)
    else
        SetButtonOFF()
    end
end

-- Initialize
Init()

-- Save groups and configs when script ends
reaper.atexit(function() 
    SaveGroups()
    SaveConfigs()
    SetButtonOFF()
end) 