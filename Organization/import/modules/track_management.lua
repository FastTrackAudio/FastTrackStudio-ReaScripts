-- @noindex
--[[
 * FastTrackStudio - Track Management Module
 * Handles track operations like creating and retrieving tracks
--]]

local TrackManagement = {}

-- Get the script path for loading dependencies
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local modules_path = script_path:match("(.*[/\\])modules[/\\]")
local root_path = modules_path:match("(.*[/\\])Organization[/\\].*[/\\]")
if not root_path then
    root_path = modules_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

package.path = package.path .. ";" .. modules_path .. "?.lua"
local Utils = require("utils")

-- Check if a GUID is valid
function TrackManagement.IsValidGUID(guid)
    -- Check if the GUID is nil or empty
    if not guid or guid == "" then
        return false
    end
    
    -- Check if the GUID has the correct format (8-4-4-4-12 hexadecimal digits)
    local pattern = "^%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%-?"
    pattern = pattern .. "[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%-?"
    pattern = pattern .. "[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%-?"
    pattern = pattern .. "[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%-?"
    pattern = pattern .. "[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%{?[0-9A-Fa-f]%}?$"
    
    return string.match(guid, pattern) ~= nil
end

-- Get a track by GUID
function TrackManagement.GetTrackByGUID(guid)
    -- Check if the GUID is valid
    if not TrackManagement.IsValidGUID(guid) then
        return nil
    end
    
    -- Use SWS/BR API if available
    if reaper.BR_GetMediaTrackByGUID then
        return reaper.BR_GetMediaTrackByGUID(0, guid)
    end
    
    -- Fallback to iterating through all tracks
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local track_guid = reaper.GetTrackGUID(track)
        if track_guid == guid then
            return track
        end
    end
    
    return nil
end

-- Get a track's child tracks
function TrackManagement.GetChildTracks(parent_track)
    if not parent_track then
        return {}
    end
    
    local parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
    local parent_depth = reaper.GetTrackDepth(parent_track)
    local track_count = reaper.CountTracks(0)
    local children = {}
    
    for i = parent_idx + 1, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)
        
        if depth <= parent_depth then
            break
        elseif depth == parent_depth + 1 then
            table.insert(children, track)
        end
    end
    
    return children
end

-- Count tracks with a specific name (or matching pattern)
function TrackManagement.CountTracksWithName(name_pattern, is_regex)
    local count = 0
    local track_count = reaper.CountTracks(0)
    
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        
        if is_regex then
            if string.match(track_name, name_pattern) then
                count = count + 1
            end
        else
            if track_name == name_pattern then
                count = count + 1
            end
        end
    end
    
    return count
end

-- Create a track from a template track
function TrackManagement.CreateTrackFromTemplate(template_track, track_name, parent_track)
    if not template_track then
        return nil
    end
    
    local insert_idx = 0
    
    -- Determine where to insert the new track
    if parent_track then
        -- Find the last child of the parent track
        local last_child_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
        local parent_depth = reaper.GetTrackDepth(parent_track)
        local track_count = reaper.CountTracks(0)
        
        for i = last_child_idx + 1, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local depth = reaper.GetTrackDepth(track)
            
            if depth <= parent_depth then
                break
            end
            
            last_child_idx = i
        end
        
        insert_idx = last_child_idx + 1
    else
        -- Insert at the end of the project
        insert_idx = reaper.CountTracks(0)
    end
    
    -- Create the new track
    reaper.InsertTrackAtIndex(insert_idx, true)
    local new_track = reaper.GetTrack(0, insert_idx)
    
    if not new_track then
        return nil
    end
    
    -- Copy properties from template track
    reaper.TrackFX_CopyToTrack(template_track, 0, new_track, 0, true)
    
    -- Copy send/receives
    local num_sends = reaper.GetTrackNumSends(template_track, 0)  -- 0 = sends
    for i = 0, num_sends - 1 do
        local dest_track = reaper.GetTrackSendInfo_Value(template_track, 0, i, "P_DESTTRACK")
        if dest_track then
            local dest_idx = reaper.GetMediaTrackInfo_Value(dest_track, "IP_TRACKNUMBER") - 1
            reaper.CreateTrackSend(new_track, reaper.GetTrack(0, dest_idx))
        end
    end
    
    -- Copy folder state if needed
    local is_folder = reaper.GetMediaTrackInfo_Value(template_track, "I_FOLDERDEPTH")
    if is_folder > 0 then
        reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", is_folder)
    end
    
    -- Set track name
    if track_name and track_name ~= "" then
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
    end
    
    -- Set folder depth if parent_track is provided
    if parent_track then
        reaper.SetTrackSelected(new_track, true)
        reaper.SetTrackSelected(parent_track, true)
        reaper.ReorderSelectedTracks(reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER"), 0)
        reaper.SetOnlyTrackSelected(new_track)
    end
    
    -- Ensure the track is visible in TCP and mixer
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINTCP", 1)
    reaper.SetMediaTrackInfo_Value(new_track, "B_SHOWINMIXER", 1)
    
    return new_track
end

-- Function to find or create a track
function TrackManagement.FindOrCreateTrack(track_name, template_track, parent_track, ensure_visible)
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
    -- First, find the correct insertion index
    local insert_index = track_count
    local parent_depth = 0
    local parent_idx = -1
    
    -- If we have a parent track, find its index and depth
    if parent_track then
        parent_depth = reaper.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH")
        parent_idx = reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") - 1
        
        -- Find the last child of the parent track
        for i = parent_idx + 1, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local track_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
            
            -- If we find a track at the same or lower depth as the parent, stop
            if track_depth <= parent_depth then
                insert_index = i
                break
            end
        end
    end
    
    -- Create the new track at the correct position
    local new_track = reaper.InsertTrackAtIndex(insert_index, true)
    if new_track then
        -- Set the track name
        reaper.GetSetMediaTrackInfo_String(new_track, "P_NAME", track_name, true)
        
        -- If parent track is provided, set it as a child
        if parent_track then
            -- Set the track as a child of the parent
            reaper.SetMediaTrackInfo_Value(new_track, "P_PARTRACK", parent_track)
            
            -- Set the folder depth to be one level deeper than the parent
            reaper.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", parent_depth + 1)
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

-- Get track info as a table (used for display/debugging)
function TrackManagement.GetTrackInfo(track)
    if not track then
        return nil
    end
    
    local _, name = reaper.GetTrackName(track)
    local guid = reaper.GetTrackGUID(track)
    local depth = reaper.GetTrackDepth(track)
    local idx = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    local is_folder = folder_depth > 0
    
    local parent = nil
    if depth > 0 then
        -- Find parent track
        for i = idx - 1, 0, -1 do
            local check_track = reaper.GetTrack(0, i)
            local check_depth = reaper.GetTrackDepth(check_track)
            
            if check_depth == depth - 1 then
                local _, parent_name = reaper.GetTrackName(check_track)
                parent = {
                    name = parent_name,
                    guid = reaper.GetTrackGUID(check_track)
                }
                break
            end
        end
    end
    
    -- Get children
    local children = {}
    if is_folder then
        local child_tracks = TrackManagement.GetChildTracks(track)
        for _, child in ipairs(child_tracks) do
            local _, child_name = reaper.GetTrackName(child)
            table.insert(children, {
                name = child_name,
                guid = reaper.GetTrackGUID(child)
            })
        end
    end
    
    return {
        name = name,
        guid = guid,
        depth = depth,
        index = idx,
        is_folder = is_folder,
        folder_depth = folder_depth,
        parent = parent,
        children = children
    }
end

-- Move selected items to a destination track
function TrackManagement.MoveSelectedItems(dest_track, track_name, insert_mode, increment_start, only_number_when_multiple)
    if not dest_track then
        return false
    end
    
    local item_count = reaper.CountSelectedMediaItems(0)
    if item_count == 0 then
        return false
    end
    
    -- Prevent UI refreshing during item moving
    reaper.PreventUIRefresh(1)
    
    -- Handle different insert modes
    if insert_mode == "increment" then
        -- Count items with similar names to determine increment
        local base_name = track_name
        local count = 0
        
        if only_number_when_multiple and item_count == 1 then
            -- If only one item and only_number_when_multiple is true, don't add number
            reaper.MoveMediaItemToTrack(reaper.GetSelectedMediaItem(0, 0), dest_track)
            
            -- Resume UI refreshing and update
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()
            
            return true
        end
        
        -- Move items with incremented names
        for i = 0, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local suffix = ""
            
            -- Add increment suffix if multiple items
            if item_count > 1 or not only_number_when_multiple then
                suffix = " " .. (increment_start + i)
            end
            
            -- Move item and update active take name
            reaper.MoveMediaItemToTrack(item, dest_track)
            
            -- Update item/take name if needed
            local take = reaper.GetActiveTake(item)
            if take then
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", base_name .. suffix, true)
            end
        end
    else
        -- Default behavior - just move without renaming
        for i = 0, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            reaper.MoveMediaItemToTrack(item, dest_track)
        end
    end
    
    -- Resume UI refreshing and update
    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    
    return true
end

return TrackManagement 