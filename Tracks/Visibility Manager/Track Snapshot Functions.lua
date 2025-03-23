-- @noindex
function SaveSnapshot() -- Set Snapshot table, Save State
    local sel_tracks = SaveSelectedTracks()
    if #sel_tracks == 0 then
        print('👨< Please Select Some Tracks ❤️)') 
        return 
    end
    local i = #Snapshot+1
    Snapshot[i] = {}
    Snapshot[i].Tracks = sel_tracks
    

    -- Set Chunk in Snapshot[i][track]
    Snapshot[i].Chunk = {} 
    for k , track in pairs(Snapshot[i].Tracks) do
        print("\n=== Processing Track " .. k .. " ===")
        AutomationItemsPreferences(track) 
        local retval, chunk = reaper.GetTrackStateChunk( track, '', false )
        if retval then
            print("Successfully got track chunk")
            print("Initial chunk has LAYOUTS:", chunk:match("LAYOUTS") ~= nil)
            
            -- Get current layouts from the track using BR_GetMediaTrackLayouts
            print("\nAttempting to get layouts...")
            local mcp_layout, tcp_layout = reaper.BR_GetMediaTrackLayouts(track)
            print("MCP Layout:", mcp_layout or "nil")
            print("TCP Layout:", tcp_layout or "nil")
            
            local layout_override = nil
            if mcp_layout and tcp_layout then
                layout_override = mcp_layout .. " " .. tcp_layout
                print("\nLayout override:", layout_override)
            else
                print("\nFailed to get valid layouts:")
                print("MCP valid:", mcp_layout ~= nil)
                print("TCP valid:", tcp_layout ~= nil)
            end
            
            -- If no layout in chunk, add empty strings for both defaults
            if not chunk:match("LAYOUTS") then
                print("\nNo LAYOUTS line found, adding empty strings for defaults")
                local old_chunk = chunk
                -- Find the position before MIDIOUT
                local midiout_pos = chunk:find("MIDIOUT")
                if midiout_pos then
                    -- Insert LAYOUTS line before MIDIOUT
                    chunk = chunk:sub(1, midiout_pos - 1) .. "LAYOUTS \"\" \"\"\n" .. chunk:sub(midiout_pos)
                    print("Chunk before modification:")
                    print(old_chunk)
                    print("\nChunk after adding LAYOUTS:")
                    print(chunk)
                else
                    print("Failed to find MIDIOUT in chunk")
                end
            else
                print("\nLAYOUTS line already exists in chunk")
            end
            
            Snapshot[i].Chunk[track] = chunk
            print("\nFinal chunk being saved:")
            print(chunk)
            print("=== End Processing Track " .. k .. " ===\n")
        else
            print("Failed to get track chunk")
        end
    end

    VersionModeOverwrite(i) -- If Version mode on it will save last selected snapshot before saving this one
    --Snapshot[i].Shortcut = nil
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

function OverwriteSnapshot(i) -- Only Called via user UI
    VersionModeOverwrite(i) -- Should I VersionModeOverwrite(i) when overwriting? ->yes) duplicate current snapshot no) current progress is saved only in the the overwrited snap 
    for k,track in pairs(Snapshot[i].Tracks) do 
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then -- Edit if I add a check 
            AutomationItemsPreferences(track)
            local retval, chunk = reaper.GetTrackStateChunk( track, '', false )

            if retval then
                Snapshot[i].Chunk[track] = chunk
            end
        end
    end
    SaveSend(i)
    SaveReceive(i)

    SoloSelect(i)
    SaveSnapshotConfig()  
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
    -- Check if the all tracks exist if no ask if the user want to assign a new track to it Show Last Name.  Currently it wont load missed tracks and load the rest
    for k,track in pairs(Snapshot[i].Tracks) do 
        -- Add loading bar (?) Could be cool 
        if reaper.ValidatePtr2(0, track, 'MediaTrack*') then -- Edit if I add a check
            local chunk = Snapshot[i].Chunk[track]
            if not Configs.Chunk.All then
                chunk = ChunkSwap(chunk, track)
            end 
            reaper.SetTrackStateChunk(track, chunk, false)
        end
        if Configs.Chunk.All or Configs.Chunk.Receive then
            RemakeReceive(i, track)
        end
        if Configs.Chunk.All or Configs.Chunk.Sends then
            RemakeSends(i,track)
        end
    end
    SoloSelect(i)
    
    -- Force REAPER to refresh all layouts
    reaper.ThemeLayout_RefreshAll()
    
    --SaveSnapshotConfig() -- Need because of SoloSelect OR Just Save when Script closes
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

function ChunkSwap(chunk, track) -- Use Configs To change current track_chunk with section from chunk(arg1)
    local retval, track_chunk
    if type(track) == 'string' then
        track_chunk = track
    else 
        retval, track_chunk = reaper.GetTrackStateChunk(track, '', false)
    end

    -- Log the initial chunks
    print("\n=== Initial Chunks ===")
    print("Snapshot Chunk (from EXT state):")
    print(chunk)
    print("\nCurrent Track Chunk:")
    print(track_chunk)

    if Configs.Chunk.Items then
        track_chunk = SwapChunkSection('ITEM',chunk,track_chunk) -- chunk -> track_chunk
    end

    if Configs.Chunk.Fx then
        track_chunk = SwapChunkSection('FXCHAIN',chunk,track_chunk) -- chunk -> track_chunk
    end

    if Configs.Chunk.Env.Bool then
        for i , val in pairs(Configs.Chunk.Env.Envelope) do --Parse every track envelope 
            if Configs.Chunk.Env.Envelope[i].Bool then
                track_chunk = SwapChunkSection(Configs.Chunk.Env.Envelope[i].ChunkKey,chunk,track_chunk) -- chunk -> track_chunk
            end
        end
    end

    for i, value in pairs(Configs.Chunk.Misc) do
        if Configs.Chunk.Misc[i].Bool then
            track_chunk = SwapChunkValue(Configs.Chunk.Misc[i].ChunkKey, chunk, track_chunk)
        end
    end

    -- Handle visibility options
    if Configs.Chunk.Vis.Bool then
        print("\n=== Visibility Options Debug ===")
        print("Configs.Chunk.Vis.Bool:", Configs.Chunk.Vis.Bool)
        print("Number of visibility options:", #Configs.Chunk.Vis.Options)
        
        for i, option in ipairs(Configs.Chunk.Vis.Options) do
            print("\nOption", i)
            print("Name:", option.Name)
            print("ChunkKey:", option.ChunkKey)
            print("Bool:", option.Bool)
            print("ValueIndices:", table.concat(option.ValueIndices or {}, ", "))
            
            if option.Bool then
                -- Special handling for envelope-specific options
                if option.ChunkKey == "VIS" or option.ChunkKey == "LANEHEIGHT" then
                    print("\nProcessing envelope option:", option.ChunkKey)
                    -- Find all envelope sections in both chunks
                    local env_sections1 = {}
                    local env_sections2 = {}
                    
                    -- Extract envelope sections from both chunks using a more precise pattern
                    for env_type in chunk:gmatch("<([A-Z]+ENV%d*)") do
                        table.insert(env_sections1, env_type)
                    end
                    for env_type in track_chunk:gmatch("<([A-Z]+ENV%d*)") do
                        table.insert(env_sections2, env_type)
                    end
                    
                    print("Found envelope sections in source:", table.concat(env_sections1, ", "))
                    print("Found envelope sections in target:", table.concat(env_sections2, ", "))
                    
                    -- For each envelope type found in source chunk
                    for _, env_type in ipairs(env_sections1) do
                        print("\nProcessing envelope type:", env_type)
                        
                        -- Check if envelope exists in target chunk
                        if not table.contains(env_sections2, env_type) then
                            print("Envelope not found in target, adding entire section")
                            -- Get the full envelope section from source chunk
                            local env_section = chunk:match("<" .. env_type .. ".-[>]")
                            if env_section then
                                print("Found envelope section in source:")
                                print(env_section)
                                print("Attempting to add section after MAINSEND...")
                                -- Add the envelope section after MAINSEND
                                local old_chunk = track_chunk
                                -- Find the position after MAINSEND line
                                local insert_pos = track_chunk:find("MAINSEND.-[^\n]*\n()")
                                if insert_pos then
                                    -- Insert the envelope section after MAINSEND
                                    track_chunk = track_chunk:sub(1, insert_pos - 1) .. env_section .. "\n" .. track_chunk:sub(insert_pos)
                                    print("Chunk before modification:")
                                    print(old_chunk)
                                    print("Chunk after modification:")
                                    print(track_chunk)
                                    print("Section added successfully")
                                else
                                    print("Failed to find MAINSEND in target chunk")
                                end
                            else
                                print("Failed to find envelope section in source chunk")
                            end
                        else
                            -- Convert the value indices table to an array of indices
                            local indices = {}
                            for _, index in pairs(option.ValueIndices) do
                                table.insert(indices, index)
                            end
                            print("Indices to update:", table.concat(indices, ", "))
                            
                            -- Use SwapChunkValueInSection to update the parameter
                            track_chunk = SwapChunkValueInSection(env_type, option.ChunkKey, chunk, track_chunk, indices)
                        end
                    end

                    -- Handle envelopes that exist in target but not in source
                    for _, env_type in ipairs(env_sections2) do
                        if not table.contains(env_sections1, env_type) then
                            print("\nHiding envelope that exists in target but not in source:", env_type)
                            -- Set VIS to 0 1 1 to hide the envelope while preserving data
                            track_chunk = SwapChunkValueInSection(env_type, "VIS", chunk, track_chunk, {1, 2, 3}, "0 1 1")
                        end
                    end
                else
                    print("\nProcessing non-envelope option:", option.ChunkKey)
                    -- Convert the value indices table to an array of indices
                    local indices = {}
                    for _, index in pairs(option.ValueIndices) do
                        table.insert(indices, index)
                    end
                    track_chunk = SwapChunkValueSpecific(chunk, track_chunk, option.ChunkKey, indices)
                end
            end
        end
        print("\n=== End Visibility Options Debug ===\n")
    else
        print("\nVisibility options are disabled (Configs.Chunk.Vis.Bool is false)")
    end

    -- Log the final merged chunk
    print("\n=== Final Merged Chunk ===")
    print(track_chunk)
    print("========================\n")

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
    -- Define the current visibility options with specific value indices
    local VisOptions = {
        {"MCP Layout", "LAYOUTS", {1}},              -- First value in LAYOUTS
        {"TCP Layout", "LAYOUTS", {2}},              -- Second value in LAYOUTS
        {"TCP Folder State", "BUSCOMP", {arrange = 1}}, -- First value in BUSCOMP
        {"MCP Folder State", "BUSCOMP", {mixer = 2}},   -- Second value in BUSCOMP
        {"TCP Visibility", "SHOWINMIX", {tcp = 4}},     -- Fourth value in SHOWINMIX
        {"MCP Visibility", "SHOWINMIX", {mcp = 1}},     -- First value in SHOWINMIX
        {"TCP Height", "TRACKHEIGHT", {height = 1}},    -- First value in TRACKHEIGHT
        {"MCP Height", "SHOWINMIX", {height = 2, send_height = 3}},  -- Second and third values in SHOWINMIX
        {"Envelope Visibility", "VIS", {vis = 1, 2, 3}}, -- All three values in VIS
        {"Envelope Lane Height", "LANEHEIGHT", {height = 1, 2}} -- Both values in LANEHEIGHT
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
    local Configs = {}
    Configs.ShowAll = false -- Show All Snapshots Not only the selected tracks (Name on GUI is the opposite (Show selected tracks only))
    Configs.PreventShortcut = false -- Prevent Shortcuts
    Configs.ToolTips = false -- Show ToolTips
    Configs.PromptName = true
    Configs.AutoDeleteAI = true -- Automatically Delete Automation Items (have preference over StoreAI)
    Configs.Select = false -- Show Last Snapshot Loaded per group of tracks
    Configs.VersionMode = false -- Show Last Snapshot Loaded per group of tracks

    ----Load Chunk options
    Configs.Chunk = {}
    Configs.Chunk.All = true
    Configs.Chunk.Fx = false
    Configs.Chunk.Items = false
   
    -- Initialize Visibility Settings
    Configs.Chunk.Vis = {}
    Configs.Chunk.Vis.Bool = false
    Configs.Chunk.Vis.Options = {}

    local VisOptions, env, misc = GetDefaultConfigStructure()

    -- Initialize the visibility setting
    for i, table in pairs(VisOptions) do
        Configs.Chunk.Vis.Options[i] = {}
        Configs.Chunk.Vis.Options[i].Bool = false
        Configs.Chunk.Vis.Options[i].Name = table[1] 
        Configs.Chunk.Vis.Options[i].ChunkKey = table[2]
        -- Add value indices if they exist
        if table[3] then
            Configs.Chunk.Vis.Options[i].ValueIndices = table[3]
        end
    end

    Configs.Chunk.Env = {} -- User Could select which envelopes to load
    Configs.Chunk.Env.Bool = false
    Configs.Chunk.Env.Envelope = {}

    for i, table in pairs(env) do
        Configs.Chunk.Env.Envelope[i] = {}
        Configs.Chunk.Env.Envelope[i].Bool = true
        Configs.Chunk.Env.Envelope[i].Name = table[1] 
        Configs.Chunk.Env.Envelope[i].ChunkKey = table[2]  
    end

    Configs.Chunk.Sends = false
    Configs.Chunk.Receive = false

    Configs.Chunk.Misc = {}
    for _, item in ipairs(misc) do
        Configs.Chunk.Misc[item.key] = {
            Bool = false,
            Name = item.name,
            ChunkKey = item.key
        }
    end

    return Configs
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
                    ChunkKey = item[2]
                }
            else
                Configs.Chunk.Vis.Options[i].Name = item[1]
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
        if reaper.ImGui_MenuItem(ctx, 'Refresh Configs') then
            RefreshConfigs()
        end
        reaper.ImGui_EndMenu(ctx)
    end
end

function SaveSnapshotConfig()
    SaveExtStateTable(ScriptName, 'SnapshotTable',table_copy_regressive(Snapshot), true)
    SaveConfig() 
end

function SaveConfig()
    SaveExtStateTable(ScriptName, 'ConfigTable',table_copy(Configs), false) 
end
