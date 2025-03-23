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
        print("No valid group or parent track found")
        return
    end
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        print("Could not find parent track from GUID")
        return
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select the parent track and all its children
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    local i = #Snapshot+1
    Snapshot[i] = {}
    Snapshot[i].Tracks = all_tracks
    Snapshot[i].Group = Configs.CurrentGroup
    Snapshot[i].SubGroup = TempPopupData.subgroup or "TCP"  -- Use the subgroup from TempPopupData
    Snapshot[i].Mode = "ALL"

    -- Set Chunk in Snapshot[i][track]
    Snapshot[i].Chunk = {} 
    print("\n=== Saving Snapshot ===")
    for k , track in pairs(Snapshot[i].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("\nSaving track: " .. track_name)
        
        AutomationItemsPreferences(track) 
        local retval, chunk = reaper.GetTrackStateChunk( track, '', false )
        if retval then
            -- Get current layouts from the track using BR_GetMediaTrackLayouts
            local mcp_layout, tcp_layout = reaper.BR_GetMediaTrackLayouts(track)
            print("\nCurrent layouts:")
            print("TCP Layout:", tcp_layout)
            print("MCP Layout:", mcp_layout)
            
            -- If no layout in chunk, add empty strings for both defaults
            if not chunk:match("LAYOUTS") then
                -- Find the position before MIDIOUT
                local midiout_pos = chunk:find("MIDIOUT")
                if midiout_pos then
                    -- Insert LAYOUTS line before MIDIOUT
                    chunk = chunk:sub(1, midiout_pos - 1) .. "LAYOUTS \"\" \"\"\n" .. chunk:sub(midiout_pos)
                end
            end
            
            print("\nFull chunk being saved:")
            print("================================")
            print(chunk)
            print("================================")
            
            Snapshot[i].Chunk[track] = chunk
        end
    end
    print("\nTotal tracks saved: " .. #Snapshot[i].Tracks)
    print("=== End Saving Snapshot ===\n")

    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)

    VersionModeOverwrite(i) -- If Version mode on it will save last selected snapshot before saving this one
    Snapshot[i].MissTrack = false
    Snapshot[i].Visible = true 
    SoloSelect(i) --set Snapshot[i].Selected
    Snapshot[i].Name = 'New Snapshot '..i
    SaveSend(i) -- set Snapshot[i].Sends[SnapshotSendTrackGUID] = {RTrack = ReceiveGUID, Chunk = 'ChunkLine'},...} -- table each item is a track it sends 
    SaveReceive(i)

    if Configs.PromptName then
        TempRenamePopup = true -- If true open Rename Popup at  OpenPopups(i) --> RenamePopup(i)
        TempPopup_i = i
    end
    
    SaveSnapshotConfig()
end

function OverwriteSnapshot(snapshotName)
    print("\n=== OverwriteSnapshot Debug ===")
    print("Snapshot to overwrite:", snapshotName)
    
    -- Find the snapshot index
    local snapshotIndex = nil
    for i, snapshot in ipairs(Snapshot) do
        if snapshot.Name == snapshotName then
            snapshotIndex = i
            break
        end
    end
    
    if not snapshotIndex then
        print("Error: Could not find snapshot to overwrite")
        return
    end
    
    -- Get the group from the snapshot
    local groupName = Snapshot[snapshotIndex].Group
    print("Found in group:", groupName)
    
    -- Find the group in Configs
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == groupName then
            group = g
            break
        end
    end
    
    if not group then
        print("Error: Could not find group")
        return
    end
    
    -- Get the parent track
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        print("Error: Could not find parent track")
        return
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select the parent track and all its children
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    -- Update the snapshot with new tracks and chunks
    Snapshot[snapshotIndex].Tracks = all_tracks
    Snapshot[snapshotIndex].Chunk = {}
    
    print("\n=== Updating Snapshot Content ===")
    for k, track in pairs(Snapshot[snapshotIndex].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("Updating track: " .. track_name)
        
        AutomationItemsPreferences(track)
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            Snapshot[snapshotIndex].Chunk[track] = chunk
        end
    end
    print("Total tracks updated: " .. #Snapshot[snapshotIndex].Tracks)
    print("=== End Updating Snapshot Content ===\n")
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Save the updated configuration
    SaveSnapshotConfig()
    print("=== End OverwriteSnapshot Debug ===\n")
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
    print("\n=== ChunkSwap ===")
    print("Filter Type:", filterType)
    print("\nSource Chunk:")
    print("================================")
    print(chunk)
    print("================================")
    
    print("\nTarget Chunk:")
    print("================================")
    print(track_chunk)
    print("================================")
    
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
    
    print("\nMerged Chunk:")
    print("================================")
    print(track_chunk)
    print("================================")
    
    return track_chunk
end

-- Helper function to check if a value exists in a table
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
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
    Snapshot[i] = nil
    SaveSnapshotConfig()
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

    for i, value in pairs(Snapshot) do-- For catching Snapshots that lost Tracks while script want running
        for key, track in pairs(Snapshot[i].Tracks) do
            if  type(track) == 'string' and Snapshot[i].MissTrack == false then 
                Snapshot[i].MissTrack  = true
            end 
        end
    end

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

function InitConfigs()
    if not Configs then Configs = {} end
    if not Configs.Groups then Configs.Groups = {} end
    
    Configs.CurrentGroup = nil
    Configs.CurrentSubGroup = "TCP"
    Configs.ExclusiveMode = Configs.ExclusiveMode or false
    
    -- Initialize TCPModes and MCPModes if they don't exist
    if not Configs.TCPModes then
        Configs.TCPModes = {"Audio", "Midi", "Automation", "Recording", "ALL"}
    end
    if not Configs.MCPModes then
        Configs.MCPModes = {"Balance", "Detail", "Tricks", "ALL"}
    end
    
    SaveConfig()
end

function LoadConfigs()
    local Configs = LoadExtStateTable(ScriptName, 'ConfigTable', true)
    if not Configs then
        Configs = InitConfigs()
    else
        -- Ensure all required structures exist and are up to date
        if not Configs.Chunk then Configs.Chunk = {} end
        if not Configs.Chunk.Vis then Configs.Chunk.Vis = {} end
        if not Configs.Chunk.Vis.Options then Configs.Chunk.Vis.Options = {} end
        if not Configs.Groups then Configs.Groups = {} end
        if not Configs.CurrentSubGroup then Configs.CurrentSubGroup = "TCP" end

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
                    Bool = false,
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
    end
    return Configs
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

-- New function to create a group
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
    
    -- Get the track's GUID
    local _, chunk = reaper.GetTrackStateChunk(parentTrack, '', false)
    local trackGUID = chunk:match("TRACKID ({[^}]+})")
    if not trackGUID then
        return false, "Could not get track GUID"
    end
    
    -- Create new group with TCP and MCP sub-groups
    table.insert(Configs.Groups, {
        name = groupName,
        parentTrack = trackGUID,  -- Store the track's GUID instead of the pointer
        subGroups = {
            TCP = {},
            MCP = {}
        }
    })
    
    -- Set as current group
    Configs.CurrentGroup = groupName
    Configs.CurrentSubGroup = "TCP" -- Set default sub-group
    
    SaveConfig()
    return true, "Group created successfully"
end

-- New function to delete a group
function DeleteGroup(groupName)
    if not Configs.Groups then return false, "No groups exist" end
    
    -- Find and remove group
    for i, group in ipairs(Configs.Groups) do
        if group.name == groupName then
            table.remove(Configs.Groups, i)
            
            -- If this was the current group, set to Default
            if Configs.CurrentGroup == groupName then
                Configs.CurrentGroup = "Default"
                Configs.CurrentSubGroup = "TCP"
            end
            
            SaveConfig()
            return true, "Group deleted successfully"
        end
    end
    
    return false, "Group not found"
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
    print("\n=== SetSnapshotFiltered Debug ===")
    print("Snapshot Index:", i)
    print("Filter Type:", filterType)
    print("Snapshot Name:", Snapshot[i].Name)
    
    if not Snapshot[i] then 
        print("No snapshot found at index:", i)
        return 
    end
    
    -- Get the current group
    local group = nil
    for _, g in ipairs(Configs.Groups) do
        if g.name == Snapshot[i].Group then
            group = g
            break
        end
    end
    
    if not group then 
        print("No group found for snapshot:", Snapshot[i].Group)
        return 
    end
    
    print("Group:", group.name)
    
    -- Get all tracks from the snapshot
    local snapshotTracks = {}
    for _, track in pairs(Snapshot[i].Tracks) do
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then
            table.insert(snapshotTracks, track)
            print("Found snapshot track:", reaper.GetTrackName(track))
        end
    end
    
    print("\nTotal tracks to process:", #snapshotTracks)
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select all tracks in the snapshot
    for _, track in pairs(snapshotTracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    -- Apply the snapshot with filtering
    for _, track in pairs(snapshotTracks) do
        if Snapshot[i].Chunk[track] then
            local _, track_name = reaper.GetTrackName(track)
            print("\nProcessing track:", track_name)
            
            -- Get the current track's chunk
            local retval, current_chunk = reaper.GetTrackStateChunk(track, '', false)
            if retval then
                print("\nCurrent track chunk:")
                print("================================")
                print(current_chunk)
                print("================================")
                
                print("\nSnapshot chunk to apply:")
                print("================================")
                print(Snapshot[i].Chunk[track])
                print("================================")
                
                -- Use ChunkSwap with our existing configs to filter parameters
                local newChunk = ChunkSwap(Snapshot[i].Chunk[track], current_chunk, filterType)
                if newChunk then
                    print("\nFinal merged chunk being applied:")
                    print("================================")
                    print(newChunk)
                    print("================================")
                    reaper.SetTrackStateChunk(track, newChunk, false)
                else
                    print("No filtered chunk returned for track")
                end
            end
        else
            local _, track_name = reaper.GetTrackName(track)
            print("\nNo chunk found for track:", track_name)
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Update visibility based on group state
    if group.active then
        print("\nShowing group tracks")
        ShowGroupTracks(group)
    else
        print("\nHiding group tracks")
        HideGroupTracks(group)
    end
    
    -- Refresh the layout and theme
    reaper.TrackList_AdjustWindows(false)
    reaper.ThemeLayout_RefreshAll()
    print("=== End SetSnapshotFiltered Debug ===\n")
end

-- Function to get parent track of a group
function GetParentTrackOfGroup(group)
    print("\n=== GetParentTrackOfGroup Debug ===")
    print("Group:", group.name)
    print("Group type:", type(group))
    
    if not group or not group.parentTrack then
        print("No valid group or parent track found")
        return nil
    end
    
    print("Parent track GUID:", group.parentTrack)
    print("Parent track type:", type(group.parentTrack))
    
    -- Get the actual MediaTrack pointer from the stored GUID
    local parentTrack = GetTrackByGUID(group.parentTrack)
    if not parentTrack then
        print("Could not find parent track from GUID")
        return nil
    end
    
    print("Found parent track:")
    print("Track type:", type(parentTrack))
    print("Track:", tostring(parentTrack))
    
    -- Validate track pointer
    if reaper.ValidatePtr2(0, parentTrack, 'MediaTrack*') then
        print("Track pointer is valid")
    else
        print("Track pointer is invalid")
        return nil
    end
    
    print("=== End GetParentTrackOfGroup Debug ===\n")
    return parentTrack
end

-- Function to show tracks based on snapshots
function ShowGroupTracks(group)
    print("\n=== ShowGroupTracks Debug ===")
    print("Group:", group.name)
    
    if not group then 
        print("No group provided")
        return 
    end
    
    local parentTrack = GetParentTrackOfGroup(group)
    if not parentTrack then 
        print("Failed to get parent track")
        return 
    end
    
    print("Parent track type:", type(parentTrack))
    print("Parent track:", tostring(parentTrack))
    
    -- Get all child tracks
    local childCount = reaper.CountTrackMediaItems(parentTrack)
    print("Child count:", childCount)
    
    for i = 0, childCount - 1 do
        local mediaItem = reaper.GetTrackMediaItem(parentTrack, i)
        if mediaItem then
            local childTrack = reaper.GetTrackMediaItem_Track(mediaItem)
            if childTrack then
                print("\nProcessing child track:")
                print("Track type:", type(childTrack))
                print("Track:", tostring(childTrack))
                
                -- Validate track pointer
                if reaper.ValidatePtr2(0, childTrack, 'MediaTrack*') then
                    local _, track_name = reaper.GetTrackName(childTrack)
                    print("Track name:", track_name)
                    reaper.SetMediaTrackInfo_Value(childTrack, "B_SHOWINTCP", 1)
                    reaper.SetMediaTrackInfo_Value(childTrack, "B_SHOWINMIXER", 1)
                else
                    print("Invalid track pointer")
                end
            else
                print("Failed to get child track from media item")
            end
        else
            print("No media item at index:", i)
        end
    end
    print("=== End ShowGroupTracks Debug ===\n")
end

-- Function to hide all tracks in a group
function HideGroupTracks(group)
    print("\n=== HideGroupTracks Debug ===")
    print("Group:", group.name)
    
    local parentTrack = GetParentTrackOfGroup(group)
    if not parentTrack then 
        print("Failed to get parent track")
        return 
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select the parent track and all its children
    reaper.SetTrackSelected(parentTrack, true)
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    -- Hide all tracks found
    for _, track in ipairs(all_tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("Hiding track:", track_name)
        
        -- Hide in TCP and MCP
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)
        reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
        
        -- Update the track's chunk to ensure visibility state is saved
        local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
        if retval then
            -- Update SHOWINMIX to hide in both TCP and MCP
            chunk = chunk:gsub("SHOWINMIX [^\n]+", "SHOWINMIX 0 0 0 0")
            reaper.SetTrackStateChunk(track, chunk, false)
        end
    end
    
    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    print("=== End HideGroupTracks Debug ===\n")
end

-- Function to apply snapshots to a group
function ApplyGroupSnapshots(group)
    print("\n=== ApplyGroupSnapshots Debug ===")
    print("Group:", group.name)
    print("Selected TCP:", group.selectedTCP)
    print("Selected MCP:", group.selectedMCP)
    print("Group Active:", group.active)
    
    -- Find and apply TCP snapshot
    if group.selectedTCP then
        print("\nProcessing TCP snapshot:", group.selectedTCP)
        for i, snapshot in ipairs(Snapshot) do
            if snapshot.Name == group.selectedTCP and snapshot.Group == group.name then
                print("Found matching snapshot at index:", i)
                print("Applying TCP snapshot")
                SetSnapshotFiltered(i, "TCP")
                break
            end
        end
    end
    
    -- Find and apply MCP snapshot
    if group.selectedMCP then
        print("\nProcessing MCP snapshot:", group.selectedMCP)
        for i, snapshot in ipairs(Snapshot) do
            if snapshot.Name == group.selectedMCP and snapshot.Group == group.name then
                print("Found matching snapshot at index:", i)
                print("Applying MCP snapshot")
                SetSnapshotFiltered(i, "MCP")
                break
            end
        end
    end
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    print("=== End ApplyGroupSnapshots Debug ===\n")
end

-- Modified HandleGroupActivation function
function HandleGroupActivation(group)
    print("\n=== HandleGroupActivation Debug ===")
    print("Group:", group.name)
    print("Active:", group.active)
    
    if not group.active then
        print("Group not active, hiding tracks")
        HideGroupTracks(group)
        return
    end
    
    -- Show all tracks first
    print("Group active, showing tracks")
    ShowGroupTracks(group)
    
    -- Then apply the snapshots
    print("Applying snapshots")
    ApplyGroupSnapshots(group)
    print("=== End HandleGroupActivation Debug ===\n")
end

-- Function to delete all groups and their snapshots
function DeleteAllGroups()
    -- Store all group names before deletion
    local groupsToDelete = {}
    for _, group in ipairs(Configs.Groups) do
        table.insert(groupsToDelete, group.name)
    end
    
    -- Delete snapshots for these groups
    local i = 1
    while i <= #Snapshot do
        local shouldDelete = false
        for _, groupName in ipairs(groupsToDelete) do
            if Snapshot[i].Group == groupName then
                shouldDelete = true
                break
            end
        end
        
        if shouldDelete then
            table.remove(Snapshot, i)
        else
            i = i + 1
        end
    end
    
    -- Reset groups to empty
    Configs.Groups = {}
    
    -- Reset current group to nil
    Configs.CurrentGroup = nil
    Configs.CurrentSubGroup = "TCP"
    
    -- Save changes
    SaveSnapshotConfig()
    SaveConfig()
end

-- New function to save TCP-specific snapshot
function SaveTCPSnapshot()
    local sel_tracks = SaveSelectedTracks()
    if #sel_tracks == 0 then
        print('👨< Please Select Some Tracks ❤️)') 
        return 
    end
    
    -- Save current selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
    
    -- Select all tracks in the folder structure
    for _, track in pairs(sel_tracks) do
        reaper.SetTrackSelected(track, true)
        reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    end
    
    -- Get all selected tracks (including children)
    local all_tracks = {}
    for i = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        table.insert(all_tracks, track)
    end
    
    local i = #Snapshot+1
    Snapshot[i] = {}
    Snapshot[i].Tracks = all_tracks
    Snapshot[i].Group = Configs.CurrentGroup
    Snapshot[i].SubGroup = "TCP"
    Snapshot[i].Mode = "TCP"

    -- Set Chunk in Snapshot[i][track]
    Snapshot[i].Chunk = {} 
    print("\n=== Saving TCP Snapshot ===")
    for k , track in pairs(Snapshot[i].Tracks) do
        local _, track_name = reaper.GetTrackName(track)
        print("Saving track: " .. track_name)
        
        local retval, chunk = reaper.GetTrackStateChunk( track, '', false )
        if retval then
            -- Filter chunk to only include TCP-specific data
            chunk = FilterChunkByType(chunk, "TCP")
            Snapshot[i].Chunk[track] = chunk
        end
    end
    print("Total tracks saved: " .. #Snapshot[i].Tracks)
    print("=== End Saving TCP Snapshot ===\n")

    -- Restore original selection
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)

    Snapshot[i].MissTrack = false
    Snapshot[i].Visible = true 
    SoloSelect(i)
    Snapshot[i].Name = 'New TCP Snapshot '..i

    -- Always prompt for name for TCP snapshots
    TempRenamePopup = true
    TempPopup_i = i
    
    SaveSnapshotConfig()
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
