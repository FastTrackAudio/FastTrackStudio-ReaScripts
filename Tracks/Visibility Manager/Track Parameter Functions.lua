-- @noindex
-- Track Parameter Functions
-- A collection of utility functions for getting and setting track parameters

-- Get all child tracks under a parent track (including nested children)
function GetChildTracks(parent_track)
    local child_tracks = {}
    
    -- Store current selection
    local sel_tracks = {}
    local sel_count = reaper.CountSelectedTracks(0)
    for i = 0, sel_count - 1 do
        table.insert(sel_tracks, reaper.GetSelectedTrack(0, i))
    end
    
    -- Select only the parent track
    reaper.SetTrackSelected(parent_track, true)
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if track ~= parent_track then
            reaper.SetTrackSelected(track, false)
        end
    end
    
    -- Use SWS command to select all children
    reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SELCHILDREN2"), 0)
    
    -- Get all selected tracks (which will be the children)
    local child_count = reaper.CountSelectedTracks(0)
    for i = 0, child_count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track ~= parent_track then -- Don't include the parent track
            table.insert(child_tracks, track)
        end
    end
    
    -- Restore original selection
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(track, false)
    end
    for _, track in ipairs(sel_tracks) do
        reaper.SetTrackSelected(track, true)
    end
    
    return child_tracks
end

-- Get all track parameters in one function
function GetTrackParameters(track)
    local params = {}
    
    -- Get track name
    local _, track_name = reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', '', false)
    if not track_name or track_name == '' then
        track_name = "Unnamed Track"
    end
    params.name = track_name
    
    -- Get visibility states
    params.tcp_visibility = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINTCP")
    params.mcp_visibility = reaper.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER")
    
    -- Get heights
    params.tcp_height = reaper.GetMediaTrackInfo_Value(track, "I_TCPH")
    
    -- Get MCP height from chunk
    local retval, chunk = reaper.GetTrackStateChunk(track, '', false)
    if retval then
        params.mcp_height = tonumber(chunk:match("SHOWINMIX%s+%S-%s+(%S-)%s"))
    end
    
    -- Get folder states
    params.folder_depth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    params.tcp_folder_state = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT")
    
    -- Get MCP folder state from chunk
    if retval then
        local buscomp = chunk:match('BUSCOMP (%d+)')
        if buscomp then
            local clickable = chunk:match('BUSCOMP '..buscomp..' (%d+)')
            if clickable then
                params.mcp_folder_state = tonumber(clickable)
            end
        end
    end
    
    -- Get track layouts using BR_GetMediaTrackLayouts
    local mcp_layout, tcp_layout = reaper.BR_GetMediaTrackLayouts(track)
    params.mcp_layout = mcp_layout or "Default"
    params.tcp_layout = tcp_layout or "Default"
    
    -- Get envelope states
    params.envelopes = {}
    local env_count = reaper.CountTrackEnvelopes(track)
    for i = 0, env_count - 1 do
        local env = reaper.GetTrackEnvelope(track, i)
        local _, env_name = reaper.GetEnvelopeName(env, "")
        local env_height = reaper.GetEnvelopeInfo_Value(env, "I_TCPH")
        local env_active = reaper.GetEnvelopeInfo_Value(env, "B_SHOWINTCP")
        table.insert(params.envelopes, {
            name = env_name,
            height = env_height,
            active = env_active
        })
    end
    
    -- Get child tracks if this is a folder
    if params.folder_depth > 0 then
        params.child_tracks = GetChildTracks(track)
    end
    
    return params
end

-- Set all track parameters in one function
function SetTrackParameters(track, params)
    -- Prevent UI refresh while making changes
    reaper.PreventUIRefresh(1)
    
    -- Set visibility states
    if params.tcp_visibility ~= nil then
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", params.tcp_visibility)
    end
    if params.mcp_visibility ~= nil then
        reaper.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", params.mcp_visibility)
    end
    
    -- Set heights
    if params.tcp_height ~= nil then
        reaper.SetMediaTrackInfo_Value(track, "I_TCPH", params.tcp_height)
    end
    
    -- Set MCP height in chunk
    if params.mcp_height ~= nil then
        local retval, tr_chunk = reaper.GetTrackStateChunk(track, '', true)
        if retval then
            print("\n  Original chunk for MCP height:")
            print(tr_chunk)
            
            local strSHOWINMIX = tr_chunk:match("SHOWINMIX.-\n")
            local FirstHalfLine, SecondHalfLine = tr_chunk:match("(SHOWINMIX%s+%S-%s+)%S+(.-\n)")
            if strSHOWINMIX and FirstHalfLine and SecondHalfLine then
                local height = tonumber(params.mcp_height)
                if height > 1 then height = 1 end
                if height < 0 then height = 0 end
                local tr_chunk_out = tr_chunk:gsub(strSHOWINMIX, FirstHalfLine..height..SecondHalfLine)
                
                print("\n  Modified chunk for MCP height:")
                print(tr_chunk_out)
                
                reaper.SetTrackStateChunk(track, tr_chunk_out, true)
            end
        end
    end
    
    -- Set folder states
    if params.folder_depth ~= nil then
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", params.folder_depth)
    end
    if params.tcp_folder_state ~= nil then
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", params.tcp_folder_state)
    end
    
    -- Set MCP folder state in chunk
    if params.mcp_folder_state ~= nil then
        local retval, tr_chunk = reaper.GetTrackStateChunk(track, '', true)
        if retval then
            print("\n  Original chunk for MCP folder state:")
            print(tr_chunk)
            
            local buscomp = tr_chunk:match('BUSCOMP (%d+)')
            if buscomp then
                local tr_chunk_out = tr_chunk:gsub('BUSCOMP '..buscomp..' %d+', 'BUSCOMP '..buscomp..' '..params.mcp_folder_state)
                
                print("\n  Modified chunk for MCP folder state:")
                print(tr_chunk_out)
                
                reaper.SetTrackStateChunk(track, tr_chunk_out, true)
            end
        end
    end
    
    -- Set track layouts using BR_SetMediaTrackLayouts
    if params.tcp_layout or params.mcp_layout then
        local success = reaper.BR_SetMediaTrackLayouts(track, params.mcp_layout or "", params.tcp_layout or "")
        if success then
            print(string.format("  Successfully set layouts for track %s:", params.name))
            print("    TCP Layout:", params.tcp_layout or "Default")
            print("    MCP Layout:", params.mcp_layout or "Default")
        else
            print(string.format("  No changes needed for layouts on track %s (already set to requested values)", params.name))
        end
    end
    
    -- Set envelope states
    if params.envelopes then
        local env_count = reaper.CountTrackEnvelopes(track)
        for i = 0, env_count - 1 do
            local env = reaper.GetTrackEnvelope(track, i)
            local _, env_name = reaper.GetEnvelopeName(env, "")
            
            -- Find matching envelope in params
            for _, env_params in ipairs(params.envelopes) do
                if env_params.name == env_name then
                    if env_params.height ~= nil then
                        reaper.SetEnvelopeInfo_Value(env, "I_TCPH", env_params.height)
                    end
                    if env_params.active ~= nil then
                        reaper.SetEnvelopeInfo_Value(env, "B_SHOWINTCP", env_params.active)
                    end
                    break
                end
            end
        end
    end
    
    -- Re-enable UI refresh and force update
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()
end

-- Debug function to print all track parameters
function PrintTrackParameters(track)
    local params = GetTrackParameters(track)
    
    print(string.format("\nTrack Parameters for: %s", params.name))
    print("Visibility:")
    print("  TCP:", params.tcp_visibility)
    print("  MCP:", params.mcp_visibility)
    print("Heights:")
    print("  TCP:", params.tcp_height)
    print("  MCP:", params.mcp_height)
    print("Folder States:")
    print("  Depth:", params.folder_depth)
    print("  TCP State:", params.tcp_folder_state)
    print("  MCP State:", params.mcp_folder_state)
    print("Layouts:")
    print("  TCP:", params.tcp_layout)
    print("  MCP:", params.mcp_layout)
    print("Envelopes:")
    for _, env in ipairs(params.envelopes) do
        print(string.format("  - %s", env.name))
        print("    Height:", env.height)
        print("    Active:", env.active)
    end
    
    if params.child_tracks then
        print("\nChild Tracks:")
        for _, child in ipairs(params.child_tracks) do
            local _, child_name = reaper.GetSetMediaTrackInfo_String(child, 'P_NAME', '', false)
            print(string.format("  - %s", child_name or "Unnamed Track"))
        end
    end
    print("---")
end 