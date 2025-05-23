-- @noindex
function SaveSnapshot() -- Set Snapshot table, Save State
    -- Get the current group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == Configs.CurrentGroup then
            group = g
            break
        end
    end
    
    if not group or not group.parentTrack then
        DebugPrint("No valid group or parent track found")
        return
    end
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        DebugPrint("Could not find parent track from GUID")
        return
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Get all tracks in the group without modifying their state
    local all_tracks = {}
    
    -- Add parent track
    table.insert(all_tracks, parentTrack)
    
    -- Add all children of the parent track
    local childCount = reaper.CountTrackMediaItems(parentTrack)
    for i = 0, childCount - 1 do
        local childTrack = reaper.GetTrackMediaItem_Track(reaper.GetTrackMediaItem(parentTrack, i))
        if childTrack and childTrack ~= parentTrack then
            table.insert(all_tracks, childTrack)
        end
    end
    
    -- Add any additional tracks from the group's scope
    if group.additionalTracks then
        for _, guid in ipairs(group.additionalTracks) do
            local track = GetTrackByGUID(guid)
            if track then
                table.insert(all_tracks, track)
            end
        end
    end
    
    local i = #Snapshot+1
    Snapshot[i] = {}
    Snapshot[i].Tracks = all_tracks
    Snapshot[i].Group = Configs.CurrentGroup
    Snapshot[i].SubGroup = TempPopupData.subgroup or "TCP"
    
    -- Set Chunk in Snapshot[i][track]
    Snapshot[i].Chunk = {}
    DebugPrint("\n=== Saving Snapshot ===")
    for k, track in pairs(Snapshot[i].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        DebugPrint("\nSaving track: " .. track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            -- Get current layouts from the track using BR_GetMediaTrackLayouts
            local mcp_layout, tcp_layout = reaper.BR_GetMediaTrackLayouts(track)
            DebugPrint("\nCurrent layouts:")
            DebugPrint("TCP Layout:", tcp_layout)
            DebugPrint("MCP Layout:", mcp_layout)
            
            -- If no layout in chunk, add empty strings for both defaults
            if not chunk:match("LAYOUTS") then
                -- Find the position before MIDIOUT
                local midiout_pos = chunk:find("MIDIOUT")
                if midiout_pos then
                    -- Insert LAYOUTS line before MIDIOUT
                    chunk = chunk:sub(1, midiout_pos - 1) .. "LAYOUTS \"\" \"\"\n" .. chunk:sub(midiout_pos)
                end
            end
            
            DebugPrint("\nFull chunk being saved:")
            DebugPrint("================================")
            DebugPrint(chunk)
            DebugPrint("================================")
            
            Snapshot[i].Chunk[track] = chunk
        end
    end
    DebugPrint("\nTotal tracks saved: " .. #Snapshot[i].Tracks)
    DebugPrint("=== End Saving Snapshot ===\n")

    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)

    VersionModeOverwrite(i) -- If Version mode on it will save last selected snapshot before saving this one
    Snapshot[i].MissTrack = false
    Snapshot[i].Visible = true 
    SoloSelect(i) --set Snapshot[i].Selected
    
    -- Use TempNewSnapshotName if it exists, otherwise use default name
    if TempNewSnapshotName and TempNewSnapshotName ~= "" then
        Snapshot[i].Name = TempNewSnapshotName
    else
        Snapshot[i].Name = 'New Snapshot '..i
    end
    
    SaveSend(i) -- set Snapshot[i].Sends[SnapshotSendTrackGUID] = {RTrack = ReceiveGUID, Chunk = 'ChunkLine'},...} -- table each item is a track it sends 
    SaveReceive(i)

    if Configs.PromptName then
        TempRenamePopup = true -- If true open Rename Popup at  OpenPopups(i) --> RenamePopup(i)
        TempPopup_i = i
    end
    
    SaveSnapshotConfig()
end

function OverwriteSnapshot(snapshotName, groupName)
    DebugPrint("\n=== OverwriteSnapshot Debug ===")
    DebugPrint("Snapshot to overwrite:", snapshotName)
    DebugPrint("Group:", groupName)
    
    -- Find the snapshot index
    local snapshotIndex = nil
    local currentGroup = nil
    
    -- First, find the group
    for _, g in ipairs(Configs.Groups) do
        if g.name == groupName then
            currentGroup = g
            break
        end
    end
    
    if not currentGroup then
        DebugPrint("Error: Could not find group:", groupName)
        return
    end
    
    -- Find the snapshot in this group
    for i, snapshot in ipairs(Snapshot) do
        if snapshot.Name == snapshotName and snapshot.Group == groupName then
            snapshotIndex = i
            break
        end
    end
    
    if not snapshotIndex then
        DebugPrint("Error: Could not find snapshot", snapshotName, "in group", groupName)
        return
    end
    
    DebugPrint("Found snapshot in group:", currentGroup.name)
    
    -- Get the group from the snapshot
    local subGroup = Snapshot[snapshotIndex].SubGroup
    DebugPrint("SubGroup:", subGroup)
    
    -- Get the parent track
    local parentTrack = GetTrackByGUID(currentGroup.parentTrack)
    if not parentTrack then
        DebugPrint("Error: Could not find parent track")
        return
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Initialize all_tracks table
    local all_tracks = {}
    
    -- First, deselect all tracks
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Select the parent track and all its children
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Add parent track and its children to all_tracks
    table.insert(all_tracks, parentTrack)
    local childCount = reaper.CountTrackMediaItems(parentTrack)
    for i = 0, childCount - 1 do
        local childTrack = reaper.GetTrackMediaItem_Track(reaper.GetTrackMediaItem(parentTrack, i))
        if childTrack and childTrack ~= parentTrack then
            table.insert(all_tracks, childTrack)
        end
    end
    
    -- Add additional tracks from the group's scope
    if currentGroup.additionalTracks then
        for _, guid in ipairs(currentGroup.additionalTracks) do
            local track = GetTrackByGUID(guid)
            if track then
                reaper.SetTrackSelected(track, true)
        table.insert(all_tracks, track)
                
                -- If this track is a parent track, also select its children
                local depth = reaper.GetTrackDepth(track)
                if depth >= 0 then
                    -- Save current selection
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
                    
                    -- Select just this track and its children
                    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
                    reaper.SetTrackSelected(track, true)
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
                    
                    -- Get all selected tracks (including children)
                    for j = 0, reaper.CountSelectedTracks(0) - 1 do
                        local childTrack = reaper.GetSelectedTrack(0, j)
                        if childTrack ~= track then -- Don't add the parent track again
                            table.insert(all_tracks, childTrack)
                        end
                    end
                    
                    -- Merge with previous selection
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
                end
            end
        end
    end
    
    -- Update the snapshot with current track states
    Snapshot[snapshotIndex].Tracks = all_tracks
    Snapshot[snapshotIndex].Chunk = {}
    
    -- Always save vertical zoom
    Snapshot[snapshotIndex].VerticalZoom = reaper.SNM_GetIntConfigVar("vzoom2", -1)
    DebugPrint("Saving vertical zoom:", Snapshot[snapshotIndex].VerticalZoom)
    
    DebugPrint("\n=== Saving Tracks to Snapshot ===")
    for k, track in pairs(all_tracks) do
        local _, track_name = reaper.GetTrackName(track)
        DebugPrint("Saving track:", track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            Snapshot[snapshotIndex].Chunk[track] = chunk
        end
    end
    DebugPrint("Total tracks saved:", #all_tracks)
    DebugPrint("=== End Saving Tracks to Snapshot ===\n")
    
    -- Save send and receive configurations
    SaveSend(snapshotIndex)
    SaveReceive(snapshotIndex)
    
    -- Update group's selected snapshot
    if subGroup == "TCP" then
        currentGroup.selectedTCP = snapshotName
    elseif subGroup == "MCP" then
        currentGroup.selectedMCP = snapshotName
    end
    
    -- Save the snapshot configuration
    SaveSnapshotConfig()
    SaveConfig()
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Force REAPER to refresh all layouts
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint("Snapshot updated successfully")
    DebugPrint("=== End OverwriteSnapshot Debug ===\n")
end

function VersionModeOverwrite(i) -- i to check which tracks group is using
    -- Track Versions mode
    -- Get last selected Snapshot for this group of tracks
    -- If there is then 
    -- OverwriteSnapshotVersionMode(last selected Snapshot i) that with current configs
    if Configs.VersionMode then
        local last_i = GetLastSelectedSnapshotForGroupOfTracks(Snapshot[i].Tracks)
        if i ~= last_i then
            if last_i then
                for k,track in pairs(Snapshot[last_i].Tracks) do 
                    if reaper.ValidatePtr2(0, track, 'MediaTrack*') then -- Edit if I add a check 
                        AutomationItemsPreferences(track)
                        local retval, chunk = reaper.GetTrackStateChunk( track, '', false )
            
                        if not Configs.Chunk.All then -- Change what will be saved on the chunk
                            chunk = ChunkSwap(chunk , Snapshot[last_i].Chunk[track])
                        end
            
                        if retval then
                            Snapshot[last_i].Chunk[track] = chunk
                        end
                    end
                end 
                SaveSend(last_i)
                SaveReceive(last_i)
            end
        end
    end
end

function AutomationItemsPreferences(track) -- depreciated!!! not used in the code
    if Configs.AutoDeleteAI then -- remove AI. Not very resourcefull
        RemoveAutomationItems(track)
    --[[ elseif Configs.StoreAI then --This tries to store AI in hidden tracks, I think I won't support this (to turn on uncomment this three lines and at LoadConfigs())
        CheckHiddenTrack()
        StoreAIinHiddenTrack(track)  ]]
    end 
end

function CheckHiddenTrack() -- Check if there is Hidden Track to save AI  depreciated!!! 
    if not Configs.HiddenTrack or not reaper.ValidatePtr2(0, Configs.HiddenTrack, 'MediaTrack*') then 
        local hidden_track = CreateHiddenTrack('Snapshot_Hidden Store AI')
        CreateEnvelopeInTrack(hidden_track,'WIDTHENV2') -- Could be any envelope
        -- Store it
        Configs.HiddenTrack = hidden_track
    end    
end

function SetSnapshot(i)
    -- Undo and refresh
    BeginUndo()

    VersionModeOverwrite(i)
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- First, deselect all tracks
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Select all tracks in the snapshot
    for k,track in pairs(Snapshot[i].Tracks) do 
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
            reaper.SetTrackSelected(track, true)
        end
    end
    
    -- Restore all tracks in the snapshot
    for k,track in pairs(Snapshot[i].Tracks) do 
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
            local chunk = Snapshot[i].Chunk[track]
            if not Configs.Chunk.All then
                chunk = ChunkSwap(chunk, track)
            end 
            reaper.SetTrackStateChunk(track, chunk, false)
            
            if Configs.Chunk.All or Configs.Chunk.Receive then
                RemakeReceive(i, track)
            end
            if Configs.Chunk.All or Configs.Chunk.Sends then
                RemakeSends(i,track)
            end
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    
    EndUndo('Snapshot: Set Snapshot: '..Snapshot[i].Name)
end

function GetLastSelectedSnapshotForGroupOfTracks(group_list) -- return i or false
    for i, v in pairs(Snapshot) do
        if TableValuesCompareNoOrder(Snapshot[i].Tracks,group_list) then
            if Snapshot[i].Selected then
                return i
            end
        end
    end
    return false
end

function SetSnapshotForTrack(i,track, undo)
    -- Check if the all tracks exist if no ask if the user want to assign a new track to it Show Last Name.  Currently it wont load missed tracks and load the rest
    if reaper.ValidatePtr2(0, track, 'MediaTrack*') then -- Edit if I add a check 
        if undo then 
            BeginUndo()
        end

        local chunk = Snapshot[i].Chunk[track]
        if not Configs.Chunk.All then
            chunk = ChunkSwap(chunk, track)
        end 
        reaper.SetTrackStateChunk(track, chunk, false)

        if Configs.Chunk.All or Configs.Chunk.Receive then
            RemakeReceive(i, track)
        end
        if Configs.Chunk.All or Configs.Chunk.Sends then
            RemakeSends(i,track)
        end

        if undo then 
            EndUndo('Snapshot: Set Track Snapshot: '..Snapshot[i].Name)
        end
    end
end

function CreateTrackWithChunk(i,chunk,idx, new_guid)
    reaper.InsertTrackAtIndex( idx, false ) -- wantDefaults=TRUE for default envelopes/FX,otherwise no enabled fx/env
    local new_track = reaper.GetTrack(0, idx)
    if new_guid then
        local start = reaper.time_precise()
        chunk = ResetAllIndentifiers(chunk)
    end

    if not Configs.Chunk.All then -- To make this function general just remove this if section 
        chunk = ChunkSwap(chunk, new_track)
    end 

    reaper.SetTrackStateChunk(new_track, chunk, false)
    return new_track
end

function ChunkSwap(chunk, track_chunk, filterType)
    -- Handle LAYOUTS separately first
    if filterType == "TCP" then
        track_chunk = SwapChunkValueSpecific(chunk, track_chunk, "LAYOUTS", {1})
    elseif filterType == "MCP" then
        track_chunk = SwapChunkValueSpecific(chunk, track_chunk, "LAYOUTS", {2})
    end
    
    -- Process visibility options
    local filteredConfig = GetFilteredConfig(filterType)
    
    -- Process each option type
    for _, option in ipairs(filteredConfig.visibilityOptions) do
        if option.ChunkKey == "LAYOUTS" then
            -- Skip LAYOUTS as we handled it above
        elseif option.ChunkKey == "VIS" or option.ChunkKey == "LANEHEIGHT" then
            -- Handle envelope options
            local sourceEnvelopes = {}
            local targetEnvelopes = {}
            
            -- Find all envelope sections in both chunks
            for envType in chunk:gmatch("<([^>]+)>") do
                if envType:match("^[A-Z]+ENV%d*$") then
                    sourceEnvelopes[envType] = true
                end
            end
            
            for envType in track_chunk:gmatch("<([^>]+)>") do
                if envType:match("^[A-Z]+ENV%d*$") then
                    targetEnvelopes[envType] = true
                end
            end
            
            -- Process each envelope type
            for envType in pairs(sourceEnvelopes) do
                if targetEnvelopes[envType] then
                    local indices = {}
                    -- Handle both string and table value indices
                    if type(option.ValueIndices) == "string" then
                        for idx in option.ValueIndices:gmatch("%d+") do
                            table.insert(indices, tonumber(idx))
                        end
                    elseif type(option.ValueIndices) == "table" then
                        for _, idx in pairs(option.ValueIndices) do
                            if type(idx) == "number" then
                                table.insert(indices, idx)
                            end
                        end
                    end
                    table.insert(indices, 1) -- Always include first value
                    track_chunk = SwapChunkValueInSection(envType, option.ChunkKey, chunk, track_chunk, indices)
                end
            end
        else
            -- Handle non-envelope options
            if option.ValueIndices then
                local indices = {}
                -- Handle both string and table value indices
                if type(option.ValueIndices) == "string" then
                    for idx in option.ValueIndices:gmatch("%d+") do
                        table.insert(indices, tonumber(idx))
                    end
                elseif type(option.ValueIndices) == "table" then
                    for _, idx in pairs(option.ValueIndices) do
                        if type(idx) == "number" then
                            table.insert(indices, idx)
                        end
                    end
                end
                track_chunk = SwapChunkValueSpecific(chunk, track_chunk, option.ChunkKey, indices)
            else
                track_chunk = SwapChunkValue(chunk, track_chunk, option.ChunkKey)
            end
        end
    end
    
    return track_chunk
end

function SwapChunkValueSpecific(sourceChunk, targetChunk, key, indices)
    local start_time = reaper.time_precise()
    
    -- Find the key in both chunks
    local sourcePattern = key .. " ([^\n]+)"
    local targetPattern = key .. " ([^\n]+)"
    
    local sourceValue = sourceChunk:match(sourcePattern)
    local targetValue = targetChunk:match(targetPattern)
    
    if not sourceValue or not targetValue then
        return targetChunk
    end
    
    -- Split values into tables
    local sourceValues = {}
    local targetValues = {}
    
    for value in sourceValue:gmatch("[^%s]+") do
        table.insert(sourceValues, value)
    end
    
    for value in targetValue:gmatch("[^%s]+") do
        table.insert(targetValues, value)
    end
    
    -- Update only the specified indices
    for _, index in ipairs(indices) do
        if sourceValues[index] and targetValues[index] then
            targetValues[index] = sourceValues[index]
        end
    end
    
    -- Reconstruct the value string
    local newValue = table.concat(targetValues, " ")
    
    -- Replace the value in the target chunk
    local newChunk = targetChunk:gsub(targetPattern, key .. " " .. newValue)
    
    DebugPrint(string.format("[SwapChunkValueSpecific] took %.3f ms", (reaper.time_precise() - start_time) * 1000))
    
    return newChunk
end

function SetSnapshotInNewTracks(i)
    BeginUndo()
    for track , chunk in pairs(Snapshot[i].Chunk) do 
        SetSnapshotForTrackInNewTracks(i, track, false)
    end
    EndUndo('Snapshot: Set Snapshot: '..Snapshot[i].Name..' in New Tracks')
end

function SetSnapshotForTrackInNewTracks(i, track, undo)
    -- if is master continue
    if IsMasterTrack(track) then
        goto continue
    end
    --
    if undo then 
        BeginUndo()
    end
    
    local chunk = Snapshot[i].Chunk[track]
    local new_track_index
    if type(track) == 'userdata' then   -------TIDO
        new_track_index = reaper.GetMediaTrackInfo_Value( track, 'IP_TRACKNUMBER' ) -- This is 1 Based (In the end dont need to add +1 )
    elseif type(track) == 'string' then
        new_track_index =  reaper.CountTracks(0) -- This is 1 Based (In the end dont need to add +1 )
    end

    local new_track = CreateTrackWithChunk(i, chunk, new_track_index, true) -- This is 0 Based
        if Configs.Chunk.All or Configs.Chunk.Receive then
            RemakeReceive(i, track, new_track)
        end
        if Configs.Chunk.All or Configs.Chunk.Sends then
            RemakeSends(i, track, new_track)
        end
    
    if undo then 
        EndUndo('Snapshot: Set Track Snapshot: '..Snapshot[i].Name)
    end
    ::continue::
end

function UpdateSnapshotVisible()
    local sel_tracks = SaveSelectedTracks()
    
    for i, value in pairs(Snapshot) do
        Snapshot[i].Visible = TableValuesCompareNoOrder(sel_tracks, Snapshot[i].Tracks) -- Here makes sense to have this group so is faster instead of GetKeys(Snapshot[i].Chunk)
    end
end

function CheckTracksMissing()-- Checks if all tracks in Snapshot Exist (To Catch Tracks deleted with Snapshot open)
    for i, v in pairs(Snapshot) do
        for key, track in pairs(Snapshot[i].Tracks) do
            if type(track) == 'userdata' then 
                if not reaper.ValidatePtr2(0, track, 'MediaTrack*') then
                    Snapshot[i].Tracks[key] = '#$$$#'..tostring(track)
                    Snapshot[i].Chunk['#$$$#'..tostring(track)] = Snapshot[i].Chunk[track] -- Save Chunk
                    Snapshot[i].Chunk[track] = nil
                    Snapshot[i].MissTrack  = true
                end
            end
        end

        if Snapshot[i].MissTrack == true then
            TryToFindMissTracks(i)
            Snapshot[i].MissTrack = not CheckTrackList(Snapshot[i].Tracks) -- Check If MissTrack can be == false
        end
    end
end

function TryToFindMissTracks(i)
    for key, track in pairs(Snapshot[i].Tracks) do

       if type(track) == 'string' then -- Check if this track is missing
            local chunk = Snapshot[i].Chunk[track]
            local guid = GetChunkVal(chunk,'TRACKID')
            local guid_track = GetTrackByGUID(guid)

            if guid_track then
                Snapshot[i].Tracks[key] = guid_track
                Snapshot[i].Chunk[guid_track] = chunk
                Snapshot[i].Chunk[track] = nil
            end
       end         
    end    
end

function SubstituteTrack(i,track, new_track, undo)
    local new_track = new_track or reaper.GetSelectedTrack(0, 0)
    if not new_track then print('👨< Please Select Some Tracks ❤️)') return end 
    -- Check if Already in Snapshot and  Check if track is in the list of tracks
    local bol = false
    for k ,v in pairs(Snapshot[i].Tracks) do
        if new_track== v then 
            --print('Track Already In The Snapshot '..Snapshot[i].Name) -- Catch if track already in this snapshot, still working I just removed the print I used to debug
            return
        end
        if v == track then -- Track is in this snapshot
            bol = true
        end
    end
    if not bol then return end -- Catch Snapshots without this track (this function might be using to iterate every snapshot)

    if undo then 
        BeginUndo()
    end
    -- Change Chunks for the old track (if track still exists it must have another GUID else in next run it can be selected)
    if type(track) == 'userdata' then
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
            ResetTrackIndentifiers(track)
        end
    end

    for k ,v in pairs(Snapshot[i].Tracks) do
        if v == track then
            Snapshot[i].Chunk[new_track] = Snapshot[i].Chunk[track]
            Snapshot[i].Chunk[track] = nil
            Snapshot[i].Tracks[k] = new_track
        end
    end
    SetSnapshotForTrack(i,new_track,false)

    if undo then -- will be true when is executed only once via user 
        SaveSnapshotConfig() 
        EndUndo('Snapshot: Substitute Track'..Snapshot[i].Name)
    end
end

function SubstituteTrackAll(track)
    local new_track = new_track or reaper.GetSelectedTrack(0, 0)
    if not new_track then print('👨< Please Select Some Tracks ❤️)') return end 
    BeginUndo() 
    for i, value in pairs(Snapshot) do
        SubstituteTrack(i,track, new_track,false)
    end
    SubstituteSendsReceives(track, new_track)
    SaveSnapshotConfig()
    EndUndo('Snapshot: Substitute Track in All Snapshot')
end

function SubstituteTrackWithNew(i, track)
    BeginUndo()
    local cnt = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(cnt, false)
    local new_track = reaper.GetTrack(0, cnt)
    SubstituteTrack(i,track,new_track,false)
    SubstituteSendsReceives(track, new_track)
    SaveSnapshotConfig()
    EndUndo('Snapshot: Substitute Track With a New in Snapshot '..Snapshot[i].Name)
end

function SubstituteTrackWithNewAll(i, track)
    BeginUndo()
    local cnt = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(cnt, false)
    local new_track = reaper.GetTrack(0, cnt)
    
    for i, value in pairs(Snapshot) do
        SubstituteTrack(i,track,new_track,false)
    end 
    SaveSnapshotConfig()
    EndUndo('Snapshot: Substitute Track With a New in All Snapshot')
end

function DeleteSnapshot(i)
    DebugPrint("\n=== DeleteSnapshot Debug ===")
    DebugPrint("Deleting snapshot index:", i)
    
    if not Snapshot[i] then
        DebugPrint("Error: Snapshot not found")
        return
    end
    
    -- Get snapshot info before deletion
    local snapshotName = Snapshot[i].Name
    local groupName = Snapshot[i].Group
    local subGroup = Snapshot[i].SubGroup
    
    DebugPrint("Snapshot name:", snapshotName)
    DebugPrint("Group:", groupName)
    DebugPrint("SubGroup:", subGroup)
    
    -- Find the group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == groupName then
            group = g
            break
        end
    end
    
    if group then
        -- Update group's selected snapshots
        if subGroup == "TCP" then
            if group.selectedTCP == snapshotName then
                group.selectedTCP = nil
            end
            -- Remove from TCP subGroups
            if group.subGroups and group.subGroups.TCP then
                for j = #group.subGroups.TCP, 1, -1 do
                    if group.subGroups.TCP[j] == snapshotName then
                        table.remove(group.subGroups.TCP, j)
                        break
                    end
                end
            end
        elseif subGroup == "MCP" then
            if group.selectedMCP == snapshotName then
                group.selectedMCP = nil
            end
            -- Remove from MCP subGroups
            if group.subGroups and group.subGroups.MCP then
                for j = #group.subGroups.MCP, 1, -1 do
                    if group.subGroups.MCP[j] == snapshotName then
                        table.remove(group.subGroups.MCP, j)
                        break
                    end
                end
            end
        end
    end
    
    -- Remove the snapshot
    table.remove(Snapshot, i)
    
    -- Save the updated configuration
    SaveSnapshotConfig()
    SaveConfig()
    
    DebugPrint("Snapshot deleted successfully")
    DebugPrint("=== End DeleteSnapshot Debug ===\n")
end

function RemoveTrackFromSnapshot(i, track)
    for k , v in pairs(Snapshot[i].Tracks) do
        if v == track then
            Snapshot[i].Tracks[k] = nil
        end
        Snapshot[i].Chunk[track] = nil
    end
    SaveSnapshotConfig()
end

function RemoveTrackFromSnapshotAll(track)
    for i , v in pairs(Snapshot) do
        RemoveTrackFromSnapshot(i, track)  
    end
    SaveSnapshotConfig()
end

function SelectSnapshotTracks(i)
    BeginUndo()
    LoadSelectedTracks(Snapshot[i].Tracks)
    EndUndo('Snapshot: Select Tracks Snapshot: '..Snapshot[i].Name)
end

function CheckProjChange() 
    local current_proj = reaper.EnumProjects(-1)
    local current_path = GetFullProjectPath()
    if OldProj or OldPath  then  -- Not First run
        if OldProj ~= current_proj or OldPath ~= current_path then -- Changed the path (can be caused by a new save or dif project but it doesnt matter as it will just reload Snapshot and Configs)
            Snapshot = LoadSnapshot()
            Configs = LoadConfigs()
        end
    end 
    OldPath = current_path
    OldProj = current_proj        
end

function LoadSnapshot()
    local Snapshot = LoadExtStateTable(ScriptName, 'SnapshotTable', true)

    if Snapshot == false then
        Snapshot = {} 
    end

    -- Ensure all snapshots have required fields and valid group associations
    for i, snapshot in pairs(Snapshot) do
        -- Ensure basic fields exist
        if not snapshot.Group then
            print("Warning: Snapshot " .. (snapshot.Name or "unnamed") .. " has no group association")
            snapshot.Group = "Default"  -- Assign to default group if missing
        end
        if not snapshot.SubGroup then
            snapshot.SubGroup = "TCP"  -- Default to TCP if missing
        end
        -- Removed default Mode setting
        
        -- Check for missing tracks
        if snapshot.Tracks then
            for key, track in pairs(snapshot.Tracks) do
                if type(track) == 'string' and not snapshot.MissTrack then 
                    snapshot.MissTrack = true
                end 
        end
    end
        
        -- Ensure chunk data exists
        if not snapshot.Chunk then
            snapshot.Chunk = {}
        end
    end

    -- Save any fixes back to disk
    SaveExtStateTable(ScriptName, 'SnapshotTable', table_copy_regressive(Snapshot), true)

    return Snapshot
end

function GetDefaultConfigStructure()
    -- Define the current visibility options with specific value indices and TCP/MCP designation
    local VisOptions = {
        {"TCP Layout", "LAYOUTS", {1}, "TCP"},              -- First value in LAYOUTS (TCP)
        {"MCP Layout", "LAYOUTS", {2}, "MCP"},              -- Second value in LAYOUTS (MCP)
        {"TCP Folder State", "BUSCOMP", {arrange = 1}, "TCP"}, -- First value in BUSCOMP
        {"MCP Folder State", "BUSCOMP", {mixer = 2}, "MCP"},   -- Second value in BUSCOMP
        {"TCP Visibility", "SHOWINMIX", {tcp = 4}, "TCP"},     -- Fourth value in SHOWINMIX
        {"MCP Visibility", "SHOWINMIX", {mcp = 1}, "MCP"},     -- First value in SHOWINMIX
        {"TCP Height", "TRACKHEIGHT", {height = 1}, "TCP"},    -- First value in TRACKHEIGHT
        {"MCP Height", "SHOWINMIX", {height = 2, send_height = 3}, "MCP"},  -- Second and third values in SHOWINMIX
        {"Envelope Visibility", "VIS", {vis = 1, 2, 3}, "TCP"}, -- All three values in VIS
        {"Envelope Lane Height", "LANEHEIGHT", {height = 1, 2}, "TCP"} -- Both values in LANEHEIGHT
    }

    -- Define envelope options
    local env = {
        {'Volume (pre FX)', 'VOLENV'},
        {'Volume', 'VOLENV2'},
        {'Trim Volume', 'VOLENV3'},
        {'Pan (Pre-FX)', 'PANENV'},
        {'Pan', 'PANENV2'},
        {'Mute', 'MUTEENV'},
        {'Width (Pre-FX)', 'WIDTHENV'},
        {'Width', 'WIDTHENV2'},
        {'Receive Volume', 'AUXVOLENV'},
        {'Receive Pan', 'AUXPANENV'},
        {'Receive Mute', 'AUXMUTEENV'}
    }

    -- Define misc options
    local misc = {
        {key = 'VOLPAN', name = 'Volume & Pan'},
        {key = 'REC', name = 'Rec & Monitor Modes'},
        {key = 'MUTESOLO', name = 'Mute & Solo'},
        {key = 'IPHASE', name = 'Phase'},
        {key = 'NAME', name = 'Name'},
        {key = 'PEAKCOL', name = 'Color'},
        {key = 'AUTOMODE', name = 'Automation Mode'},
    }

    return VisOptions, env, misc
end

-- Add debug mode to Configs structure
function InitConfigs()
    if not Configs then Configs = {} end
    if not Configs.Groups then Configs.Groups = {} end
    
    Configs.CurrentGroup = nil
    Configs.CurrentSubGroup = "TCP"
    Configs.ExclusiveMode = Configs.ExclusiveMode or false
    Configs.DebugMode = Configs.DebugMode or false  -- Add debug mode flag
    
    -- Initialize TCPModes and MCPModes if they don't exist
    if not Configs.TCPModes then
        Configs.TCPModes = {"Audio", "Midi", "Automation", "Recording", "ALL"}
    end
    if not Configs.MCPModes then
        Configs.MCPModes = {"Balance", "Detail", "Tricks", "ALL"}
    end
    
    SaveConfig()
end

-- Add debug print function
function DebugPrint(...)
    if Configs and Configs.DebugMode then
        print(...)
    end
end

function LoadConfigs()
    local success, loaded
    
    -- Try to load configs from ExtState
    success, loaded = pcall(function() 
        return LoadExtStateTable(ScriptName, 'ConfigTable', true) 
    end)
    
    -- If successful and we got a valid table
    if success and loaded and type(loaded) == "table" then
        local Configs = loaded
        
        -- Ensure all required structures exist and are up to date
        if not Configs.Chunk then Configs.Chunk = {} end
        if not Configs.Chunk.Vis then Configs.Chunk.Vis = {} end
        if not Configs.Chunk.Vis.Options then Configs.Chunk.Vis.Options = {} end
        if not Configs.Groups then Configs.Groups = {} end
        if not Configs.CurrentSubGroup then Configs.CurrentSubGroup = "TCP" end
        if Configs.ToolTips == nil then Configs.ToolTips = true end
        if Configs.DebugMode == nil then Configs.DebugMode = false end
        
        -- Ensure all groups have subGroups structure
        for _, group in ipairs(Configs.Groups) do
            if not group.subGroups then
                group.subGroups = {
                    TCP = {},
                    MCP = {}
                }
            end
        end

        local VisOptions, env, misc = GetDefaultConfigStructure()

        -- Update visibility options
        local current_keys = {}
        for _, item in ipairs(VisOptions) do
            current_keys[item[2]] = true
        end

        -- Remove entries that are no longer in the VisOptions list
        for i, _ in pairs(Configs.Chunk.Vis.Options) do
            if not current_keys[Configs.Chunk.Vis.Options[i].ChunkKey] then
                Configs.Chunk.Vis.Options[i] = nil
            end
        end

        -- Add or update entries from the VisOptions list
        for i, item in ipairs(VisOptions) do
            if not Configs.Chunk.Vis.Options[i] then
                Configs.Chunk.Vis.Options[i] = {
                    Bool = true,
                    Name = item[1],
                    ChunkKey = item[2],
                    ValueIndices = item[3],
                    Type = item[4] -- Store TCP/MCP designation
                }
            else
                Configs.Chunk.Vis.Options[i].Name = item[1]
                Configs.Chunk.Vis.Options[i].ValueIndices = item[3]
                Configs.Chunk.Vis.Options[i].Type = item[4] -- Update TCP/MCP designation
            end
        end

        -- Update misc options
        if not Configs.Chunk.Misc then Configs.Chunk.Misc = {} end
        for _, item in ipairs(misc) do
            if not Configs.Chunk.Misc[item.key] then
                Configs.Chunk.Misc[item.key] = {
                    Bool = false,
                    Name = item.name,
                    ChunkKey = item.key
                }
            else
                Configs.Chunk.Misc[item.key].Name = item.name
            end
        end
        
        return Configs
    else
        -- If loading failed or returned invalid data, initialize new configs
        local newConfigs = InitConfigs()
        
        -- Save the new configs to ExtState
        pcall(function() SaveExtStateTable(ScriptName, 'ConfigTable', newConfigs, false) end)
        
        return newConfigs
    end
end

function RefreshConfigs()
    -- Delete the existing configs from ExtState
    reaper.DeleteExtState(ScriptName, 'ConfigTable', false)
    
    -- Create fresh configs using InitConfigs
    Configs = InitConfigs()
    
    -- Save the fresh configs
    SaveConfig()
end

function ConfigsMenu()
    if reaper.ImGui_BeginMenu(ctx, 'Configs') then
        if reaper.ImGui_MenuItem(ctx, 'Show All Snapshots') then
            Configs.ShowAll = not Configs.ShowAll
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Prevent Shortcuts') then
            Configs.PreventShortcut = not Configs.PreventShortcut
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Show ToolTips') then
            Configs.ToolTips = not Configs.ToolTips
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Prompt Name') then
            Configs.PromptName = not Configs.PromptName
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Auto Delete AI') then
            Configs.AutoDeleteAI = not Configs.AutoDeleteAI
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Show Last Snapshot Loaded') then
            Configs.Select = not Configs.Select
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Version Mode') then
            Configs.VersionMode = not Configs.VersionMode
            SaveConfig()
        end
        if reaper.ImGui_MenuItem(ctx, 'Debug Mode') then
            Configs.DebugMode = not Configs.DebugMode
            SaveConfig()
        end
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, 'Delete All Groups') then
            if reaper.ShowMessageBox("This will delete all groups (except Default) and their snapshots. This action cannot be undone. Continue?", "Delete All Groups", 4) == 6 then
                DeleteAllGroups()
            end
        end
        if reaper.ImGui_MenuItem(ctx, 'Refresh Configs') then
            RefreshConfigs()
        end
        reaper.ImGui_EndMenu(ctx)
    end
end

function SaveSnapshotConfig()
    SaveExtStateTable(ScriptName, 'SnapshotTable',table_copy_regressive(Snapshot), true)
    SaveConfig() 
    -- Refresh all layouts after saving snapshot config
    reaper.ThemeLayout_RefreshAll()
end

function SaveConfig()
    SaveExtStateTable(ScriptName, 'ConfigTable',table_copy(Configs), false) 
end

-- Helper function to get all parent tracks up to top level
function GetParentTracks(track)
    DebugPrint("\n=== GetParentTracks Debug ===")
    local _, track_name = reaper.GetTrackName(track)
    DebugPrint("Getting parents for track:", track_name)
    
    local parents = {}
    local currentTrack = track
    
    while currentTrack do
        local depth = reaper.GetTrackDepth(currentTrack)
        if depth <= 0 then 
            DebugPrint("Reached top level track")
            break 
        end
        
        -- Save current selection and select the track
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
        reaper.SetTrackSelected(currentTrack, true)
        
        -- Use SWS action to select parent
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELPARENTS"), 0)
        
        -- Get the selected parent track
        local parent = reaper.GetSelectedTrack(0, 0)
        if parent then
            local _, parent_name = reaper.GetTrackName(parent)
            DebugPrint("Found parent:", parent_name, "at depth:", reaper.GetTrackDepth(parent))
            table.insert(parents, parent)
            currentTrack = parent
        else
            DebugPrint("No more parents found")
            break
        end
        
        -- Restore original selection
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    end
    
    DebugPrint("Total parents found:", #parents)
    DebugPrint("=== End GetParentTracks Debug ===\n")
    return parents
end

-- Modified CreateGroup function
function CreateGroup(groupName)
    if not Configs.Groups then
        Configs.Groups = {}
    end
    
    -- Check if group already exists
    for _, group in ipairs(Configs.Groups) do
        if group.name == groupName then
            return false, "Group already exists"
        end
    end
    
    -- Get the currently selected track as the parent track
    local parentTrack = reaper.GetSelectedTrack(0, 0)
    if not parentTrack then
        return false, "No track selected"
    end
    
    -- Get all parent tracks
    local parentTracks = GetParentTracks(parentTrack)
    
    -- Create new group with TCP and MCP sub-groups
    local newGroup = {
        name = groupName,
        parentTrack = reaper.GetTrackGUID(parentTrack),  -- Store the track's GUID
        additionalTracks = {},  -- For storing arbitrary tracks added to the group
        subGroups = {
            TCP = {},
            MCP = {}
        }
    }
    
    -- Add parent track GUIDs to additionalTracks
    for _, track in ipairs(parentTracks) do
        table.insert(newGroup.additionalTracks, reaper.GetTrackGUID(track))
    end
    
    -- Add the new group to Configs.Groups
    table.insert(Configs.Groups, newGroup)
    
    -- Set as current group
    Configs.CurrentGroup = groupName
    Configs.CurrentSubGroup = "TCP" -- Set default sub-group
    
    SaveConfig()
    return true, "Group created successfully"
end

-- New function to add a track to a group's scope
function AddTrackToGroupScope(groupName, track)
    DebugPrint("\n=== AddTrackToGroupScope Debug ===")
    if not track then
        DebugPrint("Error: No track provided")
        return false, "No track provided"
    end
    
    -- Find the group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == groupName then
            group = g
            break
        end
    end
    
    if not group then
        DebugPrint("Error: Group not found:", groupName)
        return false, "Group not found"
    end
    
    local _, track_name = reaper.GetTrackName(track)
    DebugPrint("Adding track to scope:", track_name)
    DebugPrint("Group:", group.name)
    
    -- Initialize additionalTracks if it doesn't exist
    if not group.additionalTracks then
        DebugPrint("Initializing additionalTracks array")
        group.additionalTracks = {}
    end
    
    -- Get track GUID
    local trackGUID = reaper.GetTrackGUID(track)
    DebugPrint("Track GUID:", trackGUID)
    
    -- Check if track is already in the group's scope
    for _, guid in ipairs(group.additionalTracks) do
        if guid == trackGUID then
            DebugPrint("Track already in group scope")
            return false, "Track already in group scope"
        end
    end
    
    -- Add track GUID to group's scope
    DebugPrint("Adding track GUID to scope")
    table.insert(group.additionalTracks, trackGUID)
    
    -- Get all parent tracks and add them too
    local parents = GetParentTracks(track)
    for _, parent in ipairs(parents) do
        local parentGUID = reaper.GetTrackGUID(parent)
        local _, parent_name = reaper.GetTrackName(parent)
        DebugPrint("Adding parent track to scope:", parent_name)
        
        -- Check if parent is already in scope
        local parentExists = false
        for _, guid in ipairs(group.additionalTracks) do
            if guid == parentGUID then
                parentExists = true
                break
            end
        end
        
        if not parentExists then
            DebugPrint("Adding parent GUID to scope:", parentGUID)
            table.insert(group.additionalTracks, parentGUID)
        else
            DebugPrint("Parent already in scope")
        end
    end
    
    -- Save the updated configuration
    DebugPrint("Saving updated configuration")
    SaveConfig()
    DebugPrint("Total tracks in scope:", #group.additionalTracks)
    DebugPrint("=== End AddTrackToGroupScope Debug ===\n")
    return true, "Track added to group scope"
end

-- Function to add currently selected tracks to group scope
function AddSelectedTracksToGroupScope(groupName)
    DebugPrint("\n=== AddSelectedTracksToGroupScope Debug ===")
    DebugPrint("Adding selected tracks to group:", groupName)
    
    local tracksAdded = 0
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        DebugPrint("\nProcessing selected track:", track_name)
        
        local success, msg = AddTrackToGroupScope(groupName, track)
        if success then
            tracksAdded = tracksAdded + 1
        else
            DebugPrint("Failed to add track:", msg)
        end
    end
    
    DebugPrint("Total tracks added:", tracksAdded)
    DebugPrint("=== End AddSelectedTracksToGroupScope Debug ===\n")
    return tracksAdded
end

-- Helper function to determine if a chunk line belongs to TCP or MCP
function IsChunkLineTCP(line)
    -- TCP-specific parameters
    local tcpPatterns = {
        "^TRACKHEIGHT ",      -- Track height in TCP
        "^PEAKCOL ",         -- Peak color
        "^BEAT ",            -- Beat visualization
        "^VOLTYPE ",         -- Volume type
        "^MUTESOLO ",        -- Mute/Solo state
        "^IPHASE ",          -- Phase state
        "^TRACKID ",         -- Track ID
        "^NAME ",            -- Track name
        "^PERF ",           -- Performance settings
        "^TRACK ",          -- Track settings
        "^VIS ",            -- Visibility
        "^AUXVOLUME ",      -- Volume
        "^AUXPAN ",         -- Pan
        "^AUXMUTE ",        -- Mute
    }
    
    for _, pattern in ipairs(tcpPatterns) do
        if line:match(pattern) then
            return true
        end
    end
    return false
end

function IsChunkLineMCP(line)
    -- MCP-specific parameters
    local mcpPatterns = {
        "^MCPX ",           -- MCP X position
        "^MCPY ",           -- MCP Y position
        "^MCPW ",           -- MCP width
        "^MCPH ",           -- MCP height
        "^MCPPLAY ",        -- MCP playback settings
        "^NCHAN ",          -- Number of channels
        "^FXCHAIN",         -- FX Chain
        "^MAINSEND",        -- Main send
        "^AUXSEND",         -- Aux send
        "^AUXRECV",         -- Aux receive
    }
    
    for _, pattern in ipairs(mcpPatterns) do
        if line:match(pattern) then
            return true
        end
    end
    return false
end

function FilterChunkByType(chunk, chunkType)
    local lines = {}
    local currentLine = ""
    local inFXChain = false
    
    -- Split chunk into lines while preserving empty lines
    for line in chunk:gmatch("([^\n]*)\n?") do
        if line:match("^<FXCHAIN") then
            inFXChain = true
        elseif line:match("^>") then
            inFXChain = false
        end
        
        -- Always include structural elements and track info
        if line:match("^<") or line:match("^>") or line:match("^TRACK") then
            table.insert(lines, line)
        -- Include FX chain for MCP only
        elseif inFXChain then
            if chunkType == "MCP" then
                table.insert(lines, line)
            end
        -- Filter other lines based on type
        elseif chunkType == "TCP" and IsChunkLineTCP(line) then
            table.insert(lines, line)
        elseif chunkType == "MCP" and IsChunkLineMCP(line) then
            table.insert(lines, line)
        end
    end
    
    return table.concat(lines, "\n")
end

-- Modified SetSnapshot to handle TCP/MCP filtering
function SetSnapshotFiltered(i, filterType)
    DebugPrint("\n=== SetSnapshotFiltered ===")
    local start_time = reaper.time_precise()
    
    if not Snapshot[i] then return end
    
    -- Get the current group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == Snapshot[i].Group then
            group = g
            break
        end
    end
    
    if not group then return end
    
    -- Get all tracks from the snapshot
    local snapshotTracks = {}
    for _, track in pairs(Snapshot[i].Tracks) do
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
            table.insert(snapshotTracks, track)
        end
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select all tracks in the snapshot
    for _, track in pairs(snapshotTracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- Get filtered config
    local filteredConfig = GetFilteredConfig(filterType)
    
    -- Cache chunks to avoid repeated processing
    local chunk_cache = {}
    local tracksToUpdate = {}
    local total_chunk_time = 0
    local total_swap_time = 0
    
    -- First pass: collect all chunks and changes
    for _, track in pairs(snapshotTracks) do
        if Snapshot[i].Chunk[track] then
            -- Get the current track's chunk
            local chunk_start = reaper.time_precise()
            local retval, current_chunk = reaper.GetTrackStateChunk(track, '', false)
            local chunk_time = (reaper.time_precise() - chunk_start) * 1000
            total_chunk_time = total_chunk_time + chunk_time
            
            if retval then
                -- Only process if chunks are different
                if current_chunk ~= Snapshot[i].Chunk[track] then
                    -- Cache the chunks
                    chunk_cache[track] = {
                        source = Snapshot[i].Chunk[track],
                        target = current_chunk
                    }
                
                -- Use ChunkSwap with our existing configs to filter parameters
                    local swap_start = reaper.time_precise()
                local newChunk = ChunkSwap(Snapshot[i].Chunk[track], current_chunk, filterType)
                    local swap_time = (reaper.time_precise() - swap_start) * 1000
                    total_swap_time = total_swap_time + swap_time
                    
                if newChunk then
                        table.insert(tracksToUpdate, {track = track, chunk = newChunk})
                end
            end
            end
        end
    end
    
    -- Second pass: apply all changes in a single batch with UI refresh disabled
    reaper.PreventUIRefresh(1)
    
    -- Collect all track updates
    local update_start = reaper.time_precise()
    for _, update in ipairs(tracksToUpdate) do
        reaper.SetTrackStateChunk(update.track, update.chunk, false)
    end
    
    -- Re-enable UI refresh and update layouts ONCE at the very end
    reaper.PreventUIRefresh(-1)
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Update visibility based on group state
    if group.active then
        ShowGroupTracks(group)
    else
        HideGroupTracks(group)
    end
    
    -- Only refresh layouts ONCE at the very end
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    -- Print only critical timing information
    DebugPrint("Chunk processing:", total_chunk_time, "ms")
    DebugPrint("Chunk swapping:", total_swap_time, "ms")
    DebugPrint("Track updates:", (reaper.time_precise() - update_start) * 1000, "ms")
    DebugPrint("Total time:", (reaper.time_precise() - start_time) * 1000, "ms")
    DebugPrint("=== End SetSnapshotFiltered ===\n")
end

-- Function to get parent track of a group
function GetParentTrackOfGroup(group)
    DebugPrint("\n=== GetParentTrackOfGroup Debug ===")
    DebugPrint("Group:", group.name)
    DebugPrint("Group type:", type(group))
    
    if not group or not group.parentTrack then
        DebugPrint("No valid group or parent track found")
        return nil
    end
    
    DebugPrint("Parent track GUID:", group.parentTrack)
    DebugPrint("Parent track type:", type(group.parentTrack))
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        DebugPrint("Could not find parent track from GUID")
        return nil
    end
    
    DebugPrint("Found parent track:")
    DebugPrint("Track type:", type(parentTrack))
    DebugPrint("Track:", tostring(parentTrack))
    
    -- Validate track pointer
    if reaper.ValidatePtr2(0, parentTrack, 'MediaTrack*') then
        DebugPrint("Track pointer is valid")
    else
        DebugPrint("Track pointer is invalid")
        return nil
    end
    
    DebugPrint("=== End GetParentTrackOfGroup Debug ===\n")
    return parentTrack
end

-- Function to show tracks based on snapshots
function ShowGroupTracks(group)
    local start_time = reaper.time_precise()
    DebugPrint("\n=== ShowGroupTracks Debug ===")
    DebugPrint("Group:", group)
    
    local parentTrack = GetParentTrackOfGroup(group)
    DebugPrint("Parent track type:", type(parentTrack))
    DebugPrint("Parent track:", parentTrack)
    
    if not parentTrack then 
        DebugPrint("No parent track found for group:", group)
        DebugPrint("=== End ShowGroupTracks Debug ===\n")
        return 
    end
    
    local childCount = reaper.CountTrackMediaItems(parentTrack)
    DebugPrint("Child count:", childCount)
    
    -- Show parent track
    reaper.SetMediaTrackInfo_Value(parentTrack, "B_SHOWINMIXER", 1)
    reaper.SetMediaTrackInfo_Value(parentTrack, "B_SHOWINTCP", 1)
    
    -- Show all child tracks
    for i = 0, childCount - 1 do
        local childTrack = reaper.GetTrackMediaItem(parentTrack, i)
            if childTrack then
            local childTrackPtr = reaper.GetMediaItem_Track(childTrack)
            if childTrackPtr then
                reaper.SetMediaTrackInfo_Value(childTrackPtr, "B_SHOWINMIXER", 1)
                reaper.SetMediaTrackInfo_Value(childTrackPtr, "B_SHOWINTCP", 1)
            end
        end
    end
    
    DebugPrint("=== End ShowGroupTracks Debug ===\n")
    DebugPrint("ShowGroupTracks took", (reaper.time_precise() - start_time) * 1000, "ms")
end

-- Function to hide all tracks in a group
function HideGroupTracks(group)
    local start_time = reaper.time_precise()
    DebugPrint("\n=== HideGroupTracks Debug ===")
    DebugPrint("Group:", group)
    
    local parentTrack = GetParentTrackOfGroup(group)
    DebugPrint("Parent track type:", type(parentTrack))
    DebugPrint("Parent track:", parentTrack)
    
    if not parentTrack then 
        DebugPrint("No parent track found for group:", group)
        DebugPrint("=== End HideGroupTracks Debug ===\n")
        return 
    end
    
    -- Save current selection at the very beginning
    DebugPrint("\nSaving current selection with _SWS_SAVESEL")
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    DebugPrint("Current selection saved")
    
    -- First, deselect all tracks
    DebugPrint("\nDeselecting all tracks")
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    DebugPrint("All tracks deselected")
    
    -- Select the parent track and all its children
    DebugPrint("\nSelecting parent track and children")
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    DebugPrint("Parent track and children selected")
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    DebugPrint("Found", #all_tracks, "tracks to process")
    
    -- Add any additional tracks from the group's scope
    if group.additionalTracks then
        DebugPrint("\nProcessing additional tracks from group scope")
        for _, guid in ipairs(group.additionalTracks) do
            local track = GetTrackByGUID(guid)
            if track then
                table.insert(all_tracks, track)
                
                -- If this track is a parent track, also add its children
                local depth = reaper.GetTrackDepth(track)
                if depth >= 0 then
                    DebugPrint("\nProcessing parent track's children")
                    -- Select just this track and its children
                    DebugPrint("Selecting track and its children")
                    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
                    reaper.SetTrackSelected(track, true)
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
                    DebugPrint("Track and children selected")
                    
                    -- Add children to all_tracks
                    for i = 0, reaper.CountSelectedTracks(0) - 1 do
                        local childTrack = reaper.GetSelectedTrack(0, i)
                        table.insert(all_tracks, childTrack)
                    end
                    DebugPrint("Added", reaper.CountSelectedTracks(0), "children to process")
                end
            end
        end
    end
    
    -- Create a map of parent tracks that are needed by other active groups
    local needed_parent_tracks = {}
    for _, otherGroup in ipairs(Configs.Groups) do
        if otherGroup ~= group and otherGroup.active then
            -- Check if this group has the same parent track
            local otherParentTrack = GetParentTrackOfGroup(otherGroup)
            if otherParentTrack then
                needed_parent_tracks[otherParentTrack] = true
            end
            
            -- Check additional tracks in the group's scope
            if otherGroup.additionalTracks then
                for _, guid in ipairs(otherGroup.additionalTracks) do
                    local track = GetTrackByGUID(guid)
                    if track then
                        needed_parent_tracks[track] = true
                    end
                end
            end
        end
    end
    
    -- Hide all tracks found without selecting them
    DebugPrint("\nHiding", #all_tracks, "tracks")
    for _, track in ipairs(all_tracks) do
        -- Only hide parent tracks if they're not needed by other active groups
        if not needed_parent_tracks[track] then
            -- Set both TCP and MCP visibility to 0
            reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)  -- Hide in MCP
            reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)   -- Hide in TCP
        else
            DebugPrint("Keeping parent track visible as it's needed by another active group")
        end
    end
    DebugPrint("All tracks hidden")
    
    -- Restore original selection at the very end
    DebugPrint("\nRestoring original selection with _SWS_RESTORESEL")
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    DebugPrint("Original selection restored")
    
    -- Force REAPER to refresh the mixer view
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint("=== End HideGroupTracks Debug ===\n")
    DebugPrint("HideGroupTracks took", (reaper.time_precise() - start_time) * 1000, "ms")
end

-- Function to apply snapshots to a group
function ApplyGroupSnapshots(group)
    DebugPrint("\n=== ApplyGroupSnapshots ===")
    local start_time = reaper.time_precise()
    
    -- Find snapshots first to avoid repeated lookups
    local tcpSnapshot, mcpSnapshot = nil, nil
    
    -- Debug output
    DebugPrint("Looking for snapshots for group:", group.name)
    DebugPrint("Selected TCP:", group.selectedTCP)
    DebugPrint("Selected MCP:", group.selectedMCP)
    
    -- Find TCP snapshot
    if group.selectedTCP then
        for i, snapshot in ipairs(Snapshot) do
            if snapshot.Name == group.selectedTCP and snapshot.Group == group.name and snapshot.SubGroup == "TCP" then
                tcpSnapshot = snapshot
                DebugPrint("Found TCP snapshot:", snapshot.Name)
                break
            end
        end
        if not tcpSnapshot then
            DebugPrint("Warning: Could not find TCP snapshot:", group.selectedTCP)
        end
    end
    
    -- Find MCP snapshot
    if group.selectedMCP then
        for i, snapshot in ipairs(Snapshot) do
            if snapshot.Name == group.selectedMCP and snapshot.Group == group.name and snapshot.SubGroup == "MCP" then
                mcpSnapshot = snapshot
                DebugPrint("Found MCP snapshot:", snapshot.Name)
                break
            end
        end
        if not mcpSnapshot then
            DebugPrint("Warning: Could not find MCP snapshot:", group.selectedMCP)
        end
    end
    
    -- If no snapshots found, return early
    if not tcpSnapshot and not mcpSnapshot then
        DebugPrint("No valid snapshots found for group")
        return
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Get all tracks that need to be updated
    local tracksToUpdate = {}
    
    -- Collect tracks from TCP snapshot
    if tcpSnapshot and tcpSnapshot.Tracks then
        for _, track in pairs(tcpSnapshot.Tracks) do
            if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
                table.insert(tracksToUpdate, track)
            end
        end
    end
    
    -- Collect tracks from MCP snapshot
    if mcpSnapshot and mcpSnapshot.Tracks then
        for _, track in pairs(mcpSnapshot.Tracks) do
            if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
                table.insert(tracksToUpdate, track)
            end
        end
    end
    
    -- Apply snapshots to tracks
    for _, track in ipairs(tracksToUpdate) do
        local tcpChunk = tcpSnapshot and tcpSnapshot.Chunk[track]
        local mcpChunk = mcpSnapshot and mcpSnapshot.Chunk[track]
        
        if tcpChunk or mcpChunk then
            -- Get current track state
            local retval, currentChunk = reaper.GetTrackStateChunk(track, '', false)
            if retval then
                local newChunk = currentChunk
                
                -- Apply TCP changes if available
                if tcpChunk then
                    DebugPrint("\nApplying TCP changes for track:", reaper.GetTrackName(track))
                    newChunk = ChunkSwap(tcpChunk, newChunk, "TCP")
                    
                    -- Apply height lock state from TCP snapshot
                    local trackData = tcpSnapshot.Tracks[track]
                    if trackData and trackData.HeightLock then
                        reaper.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", trackData.HeightLock)
                        if trackData.HeightOverride then
                            reaper.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", trackData.HeightOverride)
                        end
                    end
                end
                
                -- Apply MCP changes if available
                if mcpChunk then
                    DebugPrint("\nApplying MCP changes for track:", reaper.GetTrackName(track))
                    newChunk = ChunkSwap(mcpChunk, newChunk, "MCP")
                end
                
                -- Apply the combined changes
                reaper.SetTrackStateChunk(track, newChunk, false)
            end
        end
    end
    
    -- Restore vertical zoom if in exclusive or limited exclusive mode and we have a TCP snapshot
    if (Configs.ViewMode == "Exclusive" or Configs.ViewMode == "LimitedExclusive") and tcpSnapshot and tcpSnapshot.VerticalZoom then
        local arrangeview = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
        local ok, position, pageSize, min, max = reaper.JS_Window_GetScrollInfo(arrangeview, "v")
        if ok then
            local cur_size = reaper.SNM_GetIntConfigVar("vzoom2", -1)
            if tcpSnapshot.VerticalZoom ~= cur_size then
                reaper.SNM_SetIntConfigVar("vzoom2", tcpSnapshot.VerticalZoom)
                reaper.TrackList_AdjustWindows(true)
                reaper.JS_Window_SetScrollPos(arrangeview, "v", math.floor((position + pageSize/2)*
                (({reaper.JS_Window_GetScrollInfo(arrangeview, "v")})[5] / max) - pageSize/2 + 0.5))
            end
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint(string.format("Total snapshot application took %.3f ms", (reaper.time_precise() - start_time) * 1000))
    DebugPrint("=== End ApplyGroupSnapshots ===\n")
end

-- Function to combine TCP and MCP snapshots and apply them in a single pass
function CombineAndApplySnapshots(tcpSnapshot, mcpSnapshot, tracks)
    print("\n=== CombineAndApplySnapshots ===")
    local start_time = reaper.time_precise()
    
    -- Prevent UI updates for the entire operation
    reaper.PreventUIRefresh(1)
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select all tracks to process
    for _, track in ipairs(tracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- Cache chunks to avoid repeated processing
    local chunk_cache = {}
    local tracksToUpdate = {}
    local total_chunk_time = 0
    local total_swap_time = 0
    
    -- First pass: collect all chunks and changes
    for _, track in ipairs(tracks) do
        -- Get the current track's chunk
        local chunk_start = reaper.time_precise()
        local retval, current_chunk = reaper.GetTrackStateChunk(track, '', false)
        local chunk_time = (reaper.time_precise() - chunk_start) * 1000
        total_chunk_time = total_chunk_time + chunk_time
        
        if retval then
            local newChunk = current_chunk
            
            -- Get filtered configs for both TCP and MCP
            local tcpConfig = GetFilteredConfig("TCP")
            local mcpConfig = GetFilteredConfig("MCP")
            
            -- Process each option type
            for _, option in ipairs(tcpConfig.visibilityOptions) do
                if option.ChunkKey == "LAYOUTS" then
                    -- Get TCP layout value
                    local tcpValue = tcpSnapshot and tcpSnapshot.Chunk[track] and tcpSnapshot.Chunk[track]:match("LAYOUTS%s+([^\n]+)")
                    if tcpValue then
                        local values = {}
                        for v in tcpValue:gmatch("[^%s]+") do
                            table.insert(values, v)
                        end
                        values[1] = values[1] or ""  -- TCP layout
                        
                        -- Get MCP layout value
                        local mcpValue = mcpSnapshot and mcpSnapshot.Chunk[track] and mcpSnapshot.Chunk[track]:match("LAYOUTS%s+([^\n]+)")
                        if mcpValue then
                            local mcpValues = {}
                            for v in mcpValue:gmatch("[^%s]+") do
                                table.insert(mcpValues, v)
                            end
                            values[2] = mcpValues[2] or ""  -- MCP layout
                        else
                            values[2] = values[2] or ""  -- Keep existing MCP layout
                        end
                        
                        -- Construct complete LAYOUTS value
                        local newValue = table.concat(values, " ")
                        newChunk = newChunk:gsub("LAYOUTS%s+[^\n]+", "LAYOUTS " .. newValue)
                    end
                else
                    -- For non-LAYOUTS options, get value from TCP snapshot
                    local tcpValue = tcpSnapshot and tcpSnapshot.Chunk[track] and tcpSnapshot.Chunk[track]:match(option.ChunkKey .. "%s+([^\n]+)")
                    if tcpValue then
                        newChunk = newChunk:gsub(option.ChunkKey .. "%s+[^\n]+", option.ChunkKey .. " " .. tcpValue)
                    end
                end
            end
            
            -- Process MCP-specific options
            for _, option in ipairs(mcpConfig.visibilityOptions) do
                if option.ChunkKey ~= "LAYOUTS" then  -- Skip LAYOUTS as we handled it above
                    local mcpValue = mcpSnapshot and mcpSnapshot.Chunk[track] and mcpSnapshot.Chunk[track]:match(option.ChunkKey .. "%s+([^\n]+)")
                    if mcpValue then
                        newChunk = newChunk:gsub(option.ChunkKey .. "%s+[^\n]+", option.ChunkKey .. " " .. mcpValue)
                    end
                end
            end
            
            if newChunk ~= current_chunk then
                table.insert(tracksToUpdate, {track = track, chunk = newChunk})
            end
        end
    end
    
    -- Apply all changes in a single batch
    local update_start = reaper.time_precise()
    for _, update in ipairs(tracksToUpdate) do
        reaper.SetTrackStateChunk(update.track, update.chunk, false)
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Re-enable UI refresh and update layouts ONCE at the very end
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    -- Print timing information
    print("Chunk processing:", total_chunk_time, "ms")
    print("Chunk swapping:", total_swap_time, "ms")
    print("Track updates:", (reaper.time_precise() - update_start) * 1000, "ms")
    print("Total time:", (reaper.time_precise() - start_time) * 1000, "ms")
    print("=== End CombineAndApplySnapshots ===\n")
end

-- Function to get all top-level tracks
function GetTopLevelTracks()
    local tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(track) == 0 then
            table.insert(tracks, track)
        end
    end
    return tracks
end

-- Function to hide all tracks
function HideAllTracks()
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
    end
end

-- Function to show tracks at minimum height without selecting them
function ShowTracksMinimumHeight(tracks)
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select the tracks temporarily
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    for _, track in ipairs(tracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- Set minimum height
    reaper.Main_OnCommand(40108, 0) -- Track: Set track height to minimum height
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
end

-- Function to show top-level tracks
function ShowTopLevelTracks()
    local topLevelTracks = GetTopLevelTracks()
    for _, track in ipairs(topLevelTracks) do
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 1)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 1)
    end
    
    -- Set minimum height without affecting selection
    ShowTracksMinimumHeight(topLevelTracks)
end

-- Function to collapse all top-level tracks
function CollapseTopLevelTracks()
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Deselect all tracks first
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Get and process all top-level tracks
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetTrackDepth(track) == 0 then
            -- Set folder compact state to 2 (collapsed)
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 2)
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
end

-- Function to handle global group activation
function HandleGlobalGroupActivation(group)
    DebugPrint("\n=== HandleGlobalGroupActivation Debug ===")
    local start_time = reaper.time_precise()
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Prevent UI updates
    reaper.PreventUIRefresh(1)
    
    -- Deactivate all non-global groups
    DebugPrint("Deactivating all non-global groups")
    for _, otherGroup in ipairs(Configs.Groups) do
        if not otherGroup.isGlobal and otherGroup.active then
            DebugPrint("Deactivating group:", otherGroup.name)
            otherGroup.active = false
        end
    end
    
    -- Always show all tracks when activating global snapshot
    DebugPrint("Activating global snapshot - showing all tracks")
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
    end
    
    -- Apply snapshots if they exist
    if group.selectedTCP or group.selectedMCP then
        DebugPrint("Applying global snapshots")
        ApplyGroupSnapshots(group)
        
        -- Find and restore vertical zoom from TCP snapshot
        if group.selectedTCP then
            for _, snapshot in ipairs(Snapshot) do
                if snapshot.Group == group.name and snapshot.Name == group.selectedTCP then
                    -- Get current zoom and scroll info before making changes
                    local cur_size = reaper.SNM_GetIntConfigVar("vzoom2", -1)
                    local arrangeview = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
                    local ok, position, pageSize, min, max = reaper.JS_Window_GetScrollInfo(arrangeview, "v")
                    
                    -- Only proceed if we have valid scroll info
                    if ok and arrangeview then
                        -- If snapshot has a saved zoom value, use it, otherwise keep current
                        local target_zoom = snapshot.VerticalZoom or cur_size
                        
                        -- Only change zoom if it's different
                        if target_zoom ~= cur_size then
                            DebugPrint("Restoring vertical zoom:", target_zoom)
                            
                            -- Set the new zoom value
                            reaper.SNM_SetIntConfigVar("vzoom2", target_zoom)
                            
                            -- Adjust track list and wait for it to complete
                            reaper.TrackList_AdjustWindows(true)
                            reaper.UpdateTimeline()
                            
                            -- Get updated scroll info after zoom change
                            local new_ok, new_position, new_pageSize, new_min, new_max = reaper.JS_Window_GetScrollInfo(arrangeview, "v")
                            
                            -- Calculate new scroll position while maintaining relative view
                            if new_ok then
                                local ratio = position / max
                                local new_scroll_pos = math.floor(ratio * new_max)
                                reaper.JS_Window_SetScrollPos(arrangeview, "v", new_scroll_pos)
                            end
                        end
                    else
                        DebugPrint("Warning: Could not get valid scroll info for vertical zoom restoration")
                    end
                    break
                end
            end
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Re-enable UI refresh and update layouts
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    -- Reset the group's active state to false without triggering another activation
    group.active = false
    
    DebugPrint(string.format("Total activation took %.3f ms", (reaper.time_precise() - start_time) * 1000))
    DebugPrint("=== End HandleGlobalGroupActivation Debug ===\n")
end

-- Main HandleGroupActivation function
function HandleGroupActivation(group)
    DebugPrint("\n=== HandleGroupActivation Debug ===")
    local start_time = reaper.time_precise()
    
    -- Check if this is a global group first
    if group.isGlobal then
        DebugPrint("Handling global group:", group.name)
        -- For global groups, we don't toggle the active state
        -- Just apply the snapshot and reset active state
        HandleGlobalGroupActivation(group)
        return
    end
    
    -- For non-global groups, continue with normal toggle behavior
    -- Log initial selection count
    local initial_selection_count = reaper.CountSelectedTracks(0)
    DebugPrint("Initial selected tracks:", initial_selection_count)
    
    -- Save current selection state at the very beginning
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Prevent UI updates and undo points for the entire operation
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    
    -- Get parent track once at the beginning and cache it
    local parentTrack = GetParentTrackOfGroup(group)
    local parentTracks = {}
    if parentTrack then
        parentTracks = GetParentTracks(parentTrack)
    end
    
    -- Flag to track if snapshots have been applied
    local snapshotsApplied = false
    
    if Configs.ViewMode == "Toggle" then
        if not group.active then
            local hide_start = reaper.time_precise()
            HideGroupTracks(group)
            DebugPrint("HideGroupTracks took:", (reaper.time_precise() - hide_start) * 1000, "ms")
        else
            local show_start = reaper.time_precise()
            ShowGroupTracks(group)
            DebugPrint("ShowGroupTracks took:", (reaper.time_precise() - show_start) * 1000, "ms")
        end
    elseif Configs.ViewMode == "Exclusive" then
        if group.active then
            local hide_start = reaper.time_precise()
            HideAllTracks()
            DebugPrint("HideAllTracks took:", (reaper.time_precise() - hide_start) * 1000, "ms")
            
            local deactivate_start = reaper.time_precise()
            for _, otherGroup in ipairs(Configs.Groups) do
                if otherGroup ~= group then
                    otherGroup.active = false
                end
            end
            DebugPrint("Deactivate other groups took:", (reaper.time_precise() - deactivate_start) * 1000, "ms")
            
            local show_start = reaper.time_precise()
            ShowGroupTracks(group)
            DebugPrint("ShowGroupTracks took:", (reaper.time_precise() - show_start) * 1000, "ms")
        else
            -- When deactivating in Exclusive mode, show all tracks
            local show_start = reaper.time_precise()
            for i = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, i)
                reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
            end
            DebugPrint("Show all tracks took:", (reaper.time_precise() - show_start) * 1000, "ms")
        end
    elseif Configs.ViewMode == "LimitedExclusive" then
        if group.active then
            local deactivate_start = reaper.time_precise()
            for _, otherGroup in ipairs(Configs.Groups) do
                if otherGroup ~= group then
                    otherGroup.active = false
                end
            end
            DebugPrint("Deactivate other groups took:", (reaper.time_precise() - deactivate_start) * 1000, "ms")
            
            local collect_start = reaper.time_precise()
            local allTracks = {}
            for i = 0, reaper.CountTracks(0) - 1 do
                table.insert(allTracks, reaper.GetTrack(0, i))
            end
            DebugPrint("Collect all tracks took:", (reaper.time_precise() - collect_start) * 1000, "ms")
            
            local show_start = reaper.time_precise()
            ShowTracksMinimumHeight(allTracks)
            DebugPrint("ShowTracksMinimumHeight took:", (reaper.time_precise() - show_start) * 1000, "ms")
            
            local collapse_start = reaper.time_precise()
            CollapseTopLevelTracks()
            DebugPrint("CollapseTopLevelTracks took:", (reaper.time_precise() - collapse_start) * 1000, "ms")
            
            -- Only handle parent track operations if we have a valid parent track
            if parentTrack then
                local parent_start = reaper.time_precise()
                -- Perform parent track operations without selecting tracks
                reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERCOMPACT", 2) -- Collapse parent track
                reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERDEPTH", 1)  -- Set folder depth
                DebugPrint("Parent track operations took:", (reaper.time_precise() - parent_start) * 1000, "ms")
            end
        else
            -- When deactivating in LimitedExclusive mode, show all tracks at minimum height
            local show_start = reaper.time_precise()
            local allTracks = {}
            for i = 0, reaper.CountTracks(0) - 1 do
                table.insert(allTracks, reaper.GetTrack(0, i))
            end
            ShowTracksMinimumHeight(allTracks)
            DebugPrint("Show all tracks at minimum height took:", (reaper.time_precise() - show_start) * 1000, "ms")
        end
    end
    
    -- Apply snapshots only once at the end, after all track operations are complete
    if group.active and not snapshotsApplied then
        local snap_start = reaper.time_precise()
        ApplyGroupSnapshots(group)
        snapshotsApplied = true
        DebugPrint("ApplyGroupSnapshots took:", (reaper.time_precise() - snap_start) * 1000, "ms")
    end
    
    -- Re-enable UI refresh and update layouts ONCE at the very end
    local refresh_start = reaper.time_precise()
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    DebugPrint("UI refresh and layout updates took:", (reaper.time_precise() - refresh_start) * 1000, "ms")
    
    -- End undo block with a descriptive name
    local actionName = group.active and "Visibility Manager Group Activation" or "Visibility Manager Group Deactivation"
    reaper.Undo_EndBlock(actionName, -1)
    
    -- Restore original selection at the very end
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Log final selection count
    local final_selection_count = reaper.CountSelectedTracks(0)
    DebugPrint("Final selected tracks:", final_selection_count)
    DebugPrint("Selection count difference:", final_selection_count - initial_selection_count)
    
    DebugPrint("Total activation took", (reaper.time_precise() - start_time) * 1000, "ms")
    DebugPrint("=== End HandleGroupActivation Debug ===\n")
end

-- Function to delete all groups and their snapshots
function DeleteAllGroups()
    print("\n=== DeleteAllGroups Debug ===")
    
    -- Store all group names before deletion
    local groupsToDelete = {}
    for _, group in ipairs(Configs.Groups) do
        if group and group.name then
            print("Adding group to delete:", group.name)
            table.insert(groupsToDelete, group.name)
        end
    end
    
    -- Delete snapshots for these groups
    local i = 1
    while i <= #Snapshot do
        if Snapshot[i] then  -- Check if snapshot exists
            local shouldDelete = false
            for _, groupName in ipairs(groupsToDelete) do
                if Snapshot[i].Group == groupName then
                    print("Deleting snapshot for group:", groupName)
                    shouldDelete = true
                    break
                end
            end
            
            if shouldDelete then
                table.remove(Snapshot, i)
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    
    -- Reset groups to empty
    print("Resetting groups to empty array")
    Configs.Groups = {}
    
    -- Reset current group to nil
    print("Resetting current group and subgroup")
    Configs.CurrentGroup = nil
    Configs.CurrentSubGroup = "TCP"
    
    -- Save changes
    print("Saving configuration")
    SaveSnapshotConfig()
    SaveConfig()
    print("=== End DeleteAllGroups Debug ===\n")
end

-- Function to save TCP-specific snapshot
function SaveTCPSnapshot()
    print("\n=== SaveTCPSnapshot Debug ===")
    -- Get the current group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == Configs.CurrentGroup then
            group = g
            break
        end
    end
    
    if not group or not group.parentTrack then
        print("No valid group or parent track found")
        return
    end
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        print("Could not find parent track from GUID")
        return
    end
    
    local _, parent_name = reaper.GetTrackName(parentTrack)
    print("Group parent track:", parent_name)
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- First, deselect all tracks
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Get all tracks to save
    local all_tracks = {}
    
    -- First, get the parent track and its children
    print("\nProcessing parent track and children:")
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (parent and children)
    local numSelected = reaper.CountSelectedTracks(0)
    for i = 0, numSelected - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then
        local _, track_name = reaper.GetTrackName(track)
            print("Adding track:", track_name)
            table.insert(all_tracks, track)
        end
    end
    
    -- Now find all parent tracks of the parent track
    print("\nFinding parent tracks:")
    local currentTrack = parentTrack
    local currentDepth = reaper.GetTrackDepth(currentTrack)
    local numTracks = reaper.CountTracks(0)
    
    -- Walk up the track hierarchy
    while currentDepth > 0 do
        local foundParent = false
        -- Find the parent track by looking at the track before the current track
        for i = 0, numTracks - 1 do
            local track = reaper.GetTrack(0, i)
            if track then
                local trackDepth = reaper.GetTrackDepth(track)
                
                -- If this track is at a higher level (lower depth) than our current track
                if trackDepth < currentDepth then
                    -- Check if the next track is our current track
                    if i + 1 < numTracks then
                        local nextTrack = reaper.GetTrack(0, i + 1)
                        if nextTrack == currentTrack then
                            local _, track_name = reaper.GetTrackName(track)
                            print("Found parent track:", track_name)
                            table.insert(all_tracks, track)
                            currentTrack = track
                            currentDepth = trackDepth
                            foundParent = true
                            break
                        end
                end
            end
        end
    end
    
        -- If we didn't find a parent, break to prevent infinite loop
        if not foundParent then
            print("No more parent tracks found")
            break
        end
    end
    
    -- Create new snapshot
    local i = #Snapshot + 1
    Snapshot[i] = {
        Tracks = all_tracks,
        Group = Configs.CurrentGroup,
        SubGroup = "TCP",
        Mode = "ALL",
        Chunk = {}
    }

    -- Save vertical zoom
    Snapshot[i].VerticalZoom = reaper.SNM_GetIntConfigVar("vzoom2", -1)
    print("Saving vertical zoom:", Snapshot[i].VerticalZoom)

    -- Set Chunk in Snapshot[i][track]
    print("\n=== Saving Tracks to Snapshot ===")
    for _, track in ipairs(Snapshot[i].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("Saving track:", track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            Snapshot[i].Chunk[track] = chunk
        end
    end
    print("Total tracks saved:", #Snapshot[i].Tracks)
    print("=== End Saving Tracks to Snapshot ===\n")

    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)

    Snapshot[i].MissTrack = false
    Snapshot[i].Visible = true 
    SoloSelect(i)
    
    -- Use TempNewSnapshotName if it exists, otherwise use default name
    if TempNewSnapshotName and TempNewSnapshotName ~= "" then
        Snapshot[i].Name = TempNewSnapshotName
    else
        Snapshot[i].Name = 'New TCP Snapshot '..i
    end

    -- Always prompt for name for TCP snapshots
    TempRenamePopup = true
    TempPopup_i = i
    
    -- Update the group's selected TCP snapshot and add to subGroups
    print("\nUpdating group configuration:")
    print("Group name:", group.name)
    print("New snapshot name:", Snapshot[i].Name)
    
    group.selectedTCP = Snapshot[i].Name
    if not group.subGroups then
        print("Initializing subGroups structure")
        group.subGroups = {
            TCP = {},
            MCP = {}
        }
    end
    
    -- Add to TCP subGroups array
    print("Adding snapshot to TCP subGroups")
    table.insert(group.subGroups.TCP, Snapshot[i].Name)
    print("Current TCP snapshots:", table.concat(group.subGroups.TCP, ", "))
    
    -- Save both configs
    print("\nSaving configurations")
    SaveSnapshotConfig()
    SaveConfig()
    
    -- Force REAPER to refresh the track view
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    print("=== End SaveTCPSnapshot Debug ===\n")
end

-- Function to save MCP-specific snapshot
function SaveMCPSnapshot()
    print("\n=== SaveMCPSnapshot Debug ===")
    
    -- Get the current group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == Configs.CurrentGroup then
            group = g
            break
        end
    end
    
    if not group or not group.parentTrack then
        print("No valid group or parent track found")
        return 
    end
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        print("Could not find parent track from GUID")
        return
    end
    
    local _, parent_name = reaper.GetTrackName(parentTrack)
    print("Group parent track:", parent_name)
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- First, deselect all tracks
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Select the parent track and all its children
    reaper.SetTrackSelected(parentTrack, true)
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    -- Add any additional tracks from the group's scope
    print("\nProcessing additional tracks from group scope:")
    if group.additionalTracks then
        for _, guid in ipairs(group.additionalTracks) do
            local track = GetTrackByGUID(guid)
            if track then
                local _, track_name = reaper.GetTrackName(track)
                print("Adding scope track:", track_name)
                reaper.SetTrackSelected(track, true)
                
                -- If this track is a parent track, also select its children
                local depth = reaper.GetTrackDepth(track)
                if depth >= 0 then
                    print("Track is a parent, adding its children")
                    -- Save current selection
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
                    
                    -- Select just this track and its children
                    reaper.Main_OnCommand(40297, 0) -- Unselect all tracks
                    reaper.SetTrackSelected(track, true)
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
                    
                    -- Merge with previous selection
                    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
                end
            end
        end
    end
    
    -- Get all selected tracks (including children and additional tracks)
    all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    local i = #Snapshot+1
    Snapshot[i] = {}
    Snapshot[i].Tracks = all_tracks
    Snapshot[i].Group = Configs.CurrentGroup
    Snapshot[i].SubGroup = "MCP"  -- Mark as MCP snapshot
    Snapshot[i].Mode = "ALL"      -- Save all data

    -- Set Chunk in Snapshot[i][track]
    Snapshot[i].Chunk = {} 
    print("\n=== Saving MCP Snapshot ===")
    for k, track in pairs(Snapshot[i].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("Saving track:", track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            -- Save complete chunk
            Snapshot[i].Chunk[track] = chunk
        end
    end
    print("Total tracks saved:", #Snapshot[i].Tracks)
    print("=== End Saving MCP Snapshot ===\n")

    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)

    Snapshot[i].MissTrack = false
    Snapshot[i].Visible = true 
    SoloSelect(i)
    
    -- Use TempNewSnapshotName if it exists, otherwise use default name
    if TempNewSnapshotName and TempNewSnapshotName ~= "" then
        Snapshot[i].Name = TempNewSnapshotName
    else
        Snapshot[i].Name = 'New MCP Snapshot '..i
    end

    -- Always prompt for name for MCP snapshots
    TempRenamePopup = true
    TempPopup_i = i
    
    -- Update the group's selected MCP snapshot and add to subGroups
    print("\nUpdating group configuration:")
    print("Group name:", group.name)
    print("New snapshot name:", Snapshot[i].Name)
    
    group.selectedMCP = Snapshot[i].Name
    if not group.subGroups then
        print("Initializing subGroups structure")
        group.subGroups = {
            TCP = {},
            MCP = {}
        }
    end
    
    -- Add to MCP subGroups array
    print("Adding snapshot to MCP subGroups")
    table.insert(group.subGroups.MCP, Snapshot[i].Name)
    print("Current MCP snapshots:", table.concat(group.subGroups.MCP, ", "))
    
    -- Save both configs
    print("\nSaving configurations")
    SaveSnapshotConfig()
    SaveConfig()
    
    -- Force REAPER to refresh the mixer view
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    print("=== End SaveMCPSnapshot Debug ===\n")
end

function GetFilteredConfig(filterType)
    local filteredConfig = {
        visibilityOptions = {}
    }
    
    -- Filter visibility options based on type
    for _, option in ipairs(Configs.Chunk.Vis.Options) do
        if option.Bool and option.Type == filterType then
            table.insert(filteredConfig.visibilityOptions, option)
        end
    end
    
    return filteredConfig
end

function SaveSnapshot(data)
    print("\n=== SaveSnapshot Debug ===")
    print("Creating new snapshot with data:", data.name)
    
    -- Create a new snapshot with the provided data
    local newSnapshot = {
        Name = data.name:gsub("%s+%(ALL%)$", ""), -- Remove (ALL) suffix if present
        Group = data.group,
        SubGroup = data.subgroup,
        icon = "",  -- Default empty icon
        Tracks = {}  -- Will store track visibility states
    }

    -- Get all tracks in the project
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local visibility = {
                TCP = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP"),
                MCP = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER")
            }
            -- Only save the state we're interested in (TCP or MCP)
            if data.subgroup == "TCP" and visibility.TCP == 1 or
               data.subgroup == "MCP" and visibility.MCP == 1 then
                local guid = reaper.GetTrackGUID(track)
                -- Get height lock state
                local heightLock = reaper.GetMediaTrackInfo_Value(track, "B_HEIGHTLOCK")
                local heightOverride = reaper.GetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE")
                
                table.insert(newSnapshot.Tracks, {
                    GUID = guid,
                    TCP = data.subgroup == "TCP" and visibility.TCP or nil,
                    MCP = data.subgroup == "MCP" and visibility.MCP or nil,
                    HeightLock = heightLock,
                    HeightOverride = heightOverride
                })
            end
        end
    end

    -- Add the new snapshot to the Snapshot table
    table.insert(Snapshot, newSnapshot)

    -- Update the group's selected snapshot and subGroups
    for _, group in ipairs(Configs.Groups) do
        if group.name == data.group then
            if data.subgroup == "TCP" then
                group.selectedTCP = newSnapshot.Name
                if not group.subGroups then
                    group.subGroups = { TCP = {}, MCP = {} }
                end
                table.insert(group.subGroups.TCP, newSnapshot.Name)
            else
                group.selectedMCP = newSnapshot.Name
                if not group.subGroups then
                    group.subGroups = { TCP = {}, MCP = {} }
                end
                table.insert(group.subGroups.MCP, newSnapshot.Name)
            end
            break
        end
    end
    
    -- Save configurations
    SaveSnapshotConfig()
    SaveConfig()
    
    print("Snapshot created successfully")
    print("=== End SaveSnapshot Debug ===\n")
end

-- Function to delete a specific group and its snapshots
function DeleteGroup(groupName)
    print("\n=== DeleteGroup Debug ===")
    print("Deleting group:", groupName)
    
    -- Find the group index
    local groupIndex = nil
    for i, group in ipairs(Configs.Groups) do
        if group.name == groupName then
            groupIndex = i
            break
        end
    end
    
    if not groupIndex then
        print("Error: Group not found")
        return false
    end
    
    -- Remove snapshots associated with this group
    local i = 1
    while i <= #Snapshot do
        if Snapshot[i] and Snapshot[i].Group == groupName then
            print("Deleting snapshot:", Snapshot[i].Name)
            table.remove(Snapshot, i)
        else
            i = i + 1
        end
    end
    
    -- Remove the group from Configs.Groups
    table.remove(Configs.Groups, groupIndex)
    
    -- If the deleted group was the current group, reset current group
    if Configs.CurrentGroup == groupName then
        Configs.CurrentGroup = nil
        Configs.CurrentSubGroup = "TCP"
    end
    
    -- Save changes
    SaveSnapshotConfig()
    SaveConfig()
    
    print("Group deleted successfully")
    print("=== End DeleteGroup Debug ===\n")
    return true
end

-- Function to create a global snapshot of all tracks in the project
function CreateGlobalSnapshot()
    DebugPrint("\n=== CreateGlobalSnapshot Debug ===")
    local start_time = reaper.time_precise()
    
    -- Check if Global Snapshots group exists, if not create it
    local globalGroup = nil
    for _, group in ipairs(Configs.Groups) do
        if group.name == "Global Snapshots" then
            globalGroup = group
            break
        end
    end
    
    if not globalGroup then
        -- Create Global Snapshots group at the top of the list
        table.insert(Configs.Groups, 1, {
            name = "Global Snapshots",
            active = false,
            color = 0x4444FFFF,  -- Default blue color
            icon = "",  -- No icon by default
            selectedTCP = nil,
            selectedMCP = nil
        })
        globalGroup = Configs.Groups[1]
        DebugPrint("Created new Global Snapshots group")
    end
    
    -- Get all tracks in the project
    local allTracks = {}
    local numTracks = reaper.CountTracks(0)
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local _, trackName = reaper.GetTrackName(track)
        local trackGUID = reaper.GetTrackGUID(track)
        table.insert(allTracks, {
            name = trackName,
            guid = trackGUID,
            track = track
        })
    end
    
    if #allTracks == 0 then
        DebugPrint("No tracks found in project")
        return false, "No tracks found in project"
    end
    
    -- Create new snapshot entry
    local newSnapshot = {
        Name = "All Project Tracks",
        Group = "Global Snapshots",
        SubGroup = "TCP",
        Tracks = allTracks,
        icon = ""  -- No icon by default
    }
    
    -- Save track states
    for _, trackInfo in ipairs(allTracks) do
        local track = trackInfo.track
        local chunk = reaper.GetTrackStateChunk(track, "")
        trackInfo.state = chunk
    end
    
    -- Add snapshot to the beginning of the list
    table.insert(Snapshot, 1, newSnapshot)
    
    -- Update selected TCP snapshot for the global group
    globalGroup.selectedTCP = newSnapshot.Name
    
    -- Create MCP version of the snapshot
    local mcpSnapshot = {
        Name = "All Project Tracks",
        Group = "Global Snapshots",
        SubGroup = "MCP",
        Tracks = allTracks,
        icon = ""  -- No icon by default
    }
    
    -- Save track states for MCP
    for _, trackInfo in ipairs(allTracks) do
        local track = trackInfo.track
        local chunk = reaper.GetTrackStateChunk(track, "")
        trackInfo.state = chunk
    end
    
    -- Add MCP snapshot to the beginning of the list
    table.insert(Snapshot, 2, mcpSnapshot)
    
    -- Update selected MCP snapshot for the global group
    globalGroup.selectedMCP = mcpSnapshot.Name
    
    -- Save the snapshot configuration
    SaveSnapshotConfig()
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint(string.format("Total execution time: %.3f ms", (reaper.time_precise() - start_time) * 1000))
    DebugPrint("=== End CreateGlobalSnapshot Debug ===\n")
    
    return true, "Global snapshot created successfully"
end

-- Function to save a global snapshot of all tracks
function SaveGlobalSnapshot()
    DebugPrint("\n=== SaveGlobalSnapshot Debug ===")
    DebugPrint("Starting global snapshot creation...")
    local start_time = reaper.time_precise()
    
    -- Check if a global group exists, if not create it
    local globalGroup = nil
    for _, group in ipairs(Configs.Groups) do
        if group.isGlobal then
            globalGroup = group
            DebugPrint("Found existing global group:", group.name)
            break
        end
    end
    
    if not globalGroup then
        -- Create global group at the top of the list
        table.insert(Configs.Groups, 1, {
            name = "Global View",
            active = false,
            color = 0x4444FFFF,  -- Default blue color
            icon = "",  -- No icon by default
            selectedTCP = nil,
            selectedMCP = nil,
            subGroups = {
                TCP = {},
                MCP = {}
            },
            isGlobal = true  -- Flag to identify this as a global group
        })
        globalGroup = Configs.Groups[1]
        DebugPrint("Created new global group: Global View")
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Get all tracks in the project
    local all_tracks = {}
    local numTracks = reaper.CountTracks(0)
    DebugPrint("Total tracks in project:", numTracks)
    
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            table.insert(all_tracks, track)
            local _, track_name = reaper.GetTrackName(track)
            DebugPrint("Adding track to snapshot:", track_name)
        end
    end
    
    if #all_tracks == 0 then
        DebugPrint("Error: No tracks found in project")
        return false, "No tracks found in project"
    end
    
    -- Create new snapshot entry
    local i = #Snapshot + 1
    local snapshotName = TempNewSnapshotName or "All Project Tracks"
    DebugPrint("Creating new global snapshot:", snapshotName)
    
    Snapshot[i] = {
        Name = snapshotName,
        Group = globalGroup.name,
        SubGroup = "TCP",
        Tracks = all_tracks,
        Chunk = {},
        Mode = "ALL",
        MissTrack = false,
        Visible = true,
        isGlobal = true  -- Flag to identify this as a global snapshot
    }
    
    -- Save vertical zoom
    Snapshot[i].VerticalZoom = reaper.SNM_GetIntConfigVar("vzoom2", -1)
    DebugPrint("Saving vertical zoom:", Snapshot[i].VerticalZoom)
    
    -- Save track states
    DebugPrint("\n=== Saving Track States ===")
    local chunk_start_time = reaper.time_precise()
    for _, track in ipairs(all_tracks) do
        local _, track_name = reaper.GetTrackName(track)
        DebugPrint("Saving track state:", track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            Snapshot[i].Chunk[track] = chunk
        else
            DebugPrint("Warning: Failed to get chunk for track:", track_name)
        end
    end
    DebugPrint(string.format("Track state saving took %.3f ms", (reaper.time_precise() - chunk_start_time) * 1000))
    DebugPrint("Total tracks saved:", #all_tracks)
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Update the group's selected TCP snapshot and add to subGroups
    DebugPrint("\nUpdating group configuration:")
    DebugPrint("Group name:", globalGroup.name)
    DebugPrint("New snapshot name:", Snapshot[i].Name)
    
    globalGroup.selectedTCP = Snapshot[i].Name
    if not globalGroup.subGroups then
        DebugPrint("Initializing subGroups structure")
        globalGroup.subGroups = {
            TCP = {},
            MCP = {}
        }
    end
    
    -- Add to TCP subGroups array
    DebugPrint("Adding snapshot to TCP subGroups")
    table.insert(globalGroup.subGroups.TCP, Snapshot[i].Name)
    
    -- Select the new snapshot
    SoloSelect(i)
    
    -- Save both configs
    DebugPrint("\nSaving configurations")
    SaveSnapshotConfig()
    SaveConfig()
    
    -- Force REAPER to refresh all layouts
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint(string.format("Total snapshot creation took %.3f ms", (reaper.time_precise() - start_time) * 1000))
    DebugPrint("=== End SaveGlobalSnapshot Debug ===\n")
    
    return true, "Global snapshot created successfully"
end

-- Function to check if a snapshot is global
function IsGlobalSnapshot(snapshot)
    return snapshot and snapshot.isGlobal
end

-- Modified HandleGroupActivation to use custom handler for global groups
local original_HandleGroupActivation = HandleGroupActivation
function HandleGroupActivation(group)
    if group.isGlobal then
        DebugPrint("\n=== HandleGlobalGroupActivation Debug ===")
        DebugPrint("Activating global group:", group.name)
        DebugPrint("Group active state:", group.active and "true" or "false")
        if group.selectedTCP then
            DebugPrint("Selected TCP snapshot:", group.selectedTCP)
        end
        if group.selectedMCP then
            DebugPrint("Selected MCP snapshot:", group.selectedMCP)
        end
        
        local result = HandleGlobalGroupActivation(group)
        
        DebugPrint("=== End HandleGlobalGroupActivation Debug ===\n")
        return result
    else
        return original_HandleGroupActivation(group)
    end
end

-- Function to change a group's parent track
function ChangeGroupParentTrack(group, newParentTrack)
    DebugPrint("\n=== ChangeGroupParentTrack Debug ===")
    DebugPrint("Group:", group.name)
    
    if not newParentTrack then
        DebugPrint("No new parent track provided")
        return false, "No track selected"
    end
    
    -- Get the track's GUID
    local newParentGUID = reaper.GetTrackGUID(newParentTrack)
    if not newParentGUID then
        DebugPrint("Could not get GUID for new parent track")
        return false, "Invalid track"
    end
    
    -- Update the group's parent track
    group.parentTrack = newParentGUID
    
    -- Get all parent tracks of the new parent track
    local parentTracks = GetParentTracks(newParentTrack)
    
    -- Update additionalTracks to include all parent tracks
    group.additionalTracks = {}
    for _, track in ipairs(parentTracks) do
        local trackGUID = reaper.GetTrackGUID(track)
        if trackGUID then
            table.insert(group.additionalTracks, trackGUID)
        end
    end
    
    -- Save the updated configuration
    SaveConfig()
    
    DebugPrint("Parent track changed successfully")
    DebugPrint("=== End ChangeGroupParentTrack Debug ===\n")
    return true, "Parent track changed successfully"
end

function ResetGroupScope(group)
    DebugPrint("\n=== ResetGroupScope Debug ===")
    DebugPrint("Resetting scope for group:", group.name)
    
    -- Get the parent track
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        DebugPrint("Error: Could not find parent track")
        return false, "Could not find parent track"
    end
    
    -- Initialize new scope with just the parent track
    local newScope = {group.parentTrack}
    
    -- Add all children of the parent track
    local childCount = reaper.CountTrackMediaItems(parentTrack)
    for i = 0, childCount - 1 do
        local childTrack = reaper.GetTrackMediaItem_Track(reaper.GetTrackMediaItem(parentTrack, i))
        if childTrack and childTrack ~= parentTrack then
            local childGUID = reaper.GetTrackGUID(childTrack)
            table.insert(newScope, childGUID)
        end
    end
    
    -- Update the group's scope
    group.additionalTracks = newScope
    
    -- Save the configuration
    SaveConfig()
    
    DebugPrint("Group scope reset successfully")
    DebugPrint("New scope contains", #newScope, "tracks")
    DebugPrint("=== End ResetGroupScope Debug ===\n")
    
    return true
end

-- Function to reset all group scopes
function ResetAllGroupScopes()
    DebugPrint("\n=== ResetAllGroupScopes Debug ===")
    local successCount = 0
    local failCount = 0
    
    for _, group in ipairs(Configs.Groups) do
        DebugPrint("Resetting scope for group:", group.name)
        
        -- Skip global groups
        if group.isGlobal then
            DebugPrint("Skipping global group:", group.name)
            goto continue
        end
        
        -- Skip groups without a parent track
        if not group.parentTrack then
            DebugPrint("Skipping group (no parent track):", group.name)
            failCount = failCount + 1
            goto continue
        end
        
        -- Get the parent track
        local parentTrack = GetTrackByGUID(group.parentTrack)
        if not parentTrack then
            DebugPrint("Failed to find parent track for group:", group.name)
            failCount = failCount + 1
            goto continue
        end
        
        -- Initialize new scope with just the parent track
        local newScope = {group.parentTrack}
        
        -- Add all children of the parent track
        local childCount = reaper.CountTrackMediaItems(parentTrack)
        for i = 0, childCount - 1 do
            local item = reaper.GetTrackMediaItem(parentTrack, i)
            local take = reaper.GetActiveTake(item)
            if take then
                local track = reaper.GetMediaItemTake_Track(take)
                if track then
                    local trackGUID = reaper.GetTrackGUID(track)
                    table.insert(newScope, trackGUID)
                end
            end
        end
        
        -- Update the group's scope
        group.additionalTracks = newScope
        DebugPrint("Successfully reset scope for group:", group.name)
        successCount = successCount + 1
        
        ::continue::
    end
    
    -- Save the configuration
    SaveConfig()
    
    DebugPrint("Reset complete. Success:", successCount, "Failed:", failCount)
    DebugPrint("=== End ResetAllGroupScopes Debug ===\n")
    
    return successCount, failCount
end

-- Function to delete all snapshots from all groups
function DeleteAllSnapshots()
    DebugPrint("\n=== DeleteAllSnapshots Debug ===")
    local snapshotCount = 0
    
    -- Iterate through all groups
    for _, group in ipairs(Configs.Groups) do
        DebugPrint("Processing group:", group.name)
        
        -- Skip global groups
        if group.isGlobal then
            DebugPrint("Skipping global group:", group.name)
            goto continue
        end
        
        -- Delete snapshots for this group from the Snapshot table
        local i = 1
        while i <= #Snapshot do
            if Snapshot[i] and Snapshot[i].Group == group.name then
                DebugPrint("Deleting snapshot:", Snapshot[i].Name)
                table.remove(Snapshot, i)
                snapshotCount = snapshotCount + 1
            else
                i = i + 1
            end
        end
        
        -- Reset group's selected snapshots
        group.selectedTCP = nil
        group.selectedMCP = nil
        
        -- Clear TCP and MCP subGroups if they exist
        if group.subGroups then
            if group.subGroups.TCP then
                group.subGroups.TCP = {}
            end
            if group.subGroups.MCP then
                group.subGroups.MCP = {}
            end
        end
        
        ::continue::
    end
    
    -- Save the configuration
    SaveSnapshotConfig()
    SaveConfig()
    
    DebugPrint("Deleted", snapshotCount, "snapshots (excluding global snapshots)")
    DebugPrint("=== End DeleteAllSnapshots Debug ===\n")
    
    return snapshotCount
end

-- Function to show and unfold all tracks in both TCP and MCP
function ShowAndUnfoldAllTracks()
    DebugPrint("\n=== ShowAndUnfoldAllTracks Debug ===")
    local start_time = reaper.time_precise()
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Get all tracks in the project
    local all_tracks = {}
    local numTracks = reaper.CountTracks(0)
    DebugPrint("Total tracks in project:", numTracks)
    
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            table.insert(all_tracks, track)
            local _, track_name = reaper.GetTrackName(track)
            DebugPrint("Processing track:", track_name)
            
            -- Show track in both TCP and MCP
            reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
            reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
            
            -- Unfold track (0 = unfolded, 1 = compact, 2 = collapsed)
            reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Force REAPER to refresh all layouts
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    
    DebugPrint(string.format("Total execution time: %.3f ms", (reaper.time_precise() - start_time) * 1000))
    DebugPrint("=== End ShowAndUnfoldAllTracks Debug ===\n")
    
    return #all_tracks
end
