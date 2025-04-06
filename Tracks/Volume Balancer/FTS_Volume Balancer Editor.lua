-- Volume Balancer Editor
-- UI for managing the Volume Balancer script

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
local GUI = dofile(root_path .. "libraries/utils/GUI Functions.lua") or {}

-- Ensure GUI has a ToolTip function
if not GUI.ToolTip then
    -- Create a local implementation if the module doesn't provide one
    GUI.ToolTip = function(ctx, text)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_BeginTooltip(ctx)
            reaper.ImGui_Text(ctx, text)
            reaper.ImGui_EndTooltip(ctx)
        end
    end
end

-- Script name for ExtState - must match the name used in the core script
local ScriptName = "Volume Balancer"

-- Initialize global Configs
Configs = {
    MinVolume = -60.0,    -- Minimum volume in dB
    MaxVolume = 6.0,      -- Maximum volume in dB
    UseInfMin = false,    -- Whether to use -inf dB as minimum
    ReportValues = false, -- Whether to report values to debug log
    LastReportTime = 0,   -- Last time values were reported
    NudgeAmount = 1.0,    -- Default nudge amount in dB
    AutoNudgeAmount = true, -- Whether to automatically set nudge amount based on group size
    DebugMode = false,    -- Whether to enable debug printing
    BackgroundRunning = false, -- Whether background mode is currently active
    ToolTips = true       -- Whether to show tooltips
}

-- Initialize ReaImGui
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("ReaImGui is required for this script. Please install it.", "Error", 0)
    return
end

-- Imgui shims to 0.7.2 (added after the news at 0.8)
dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.7.2")

-- Create context and fonts
local ctx = reaper.ImGui_CreateContext('Volume Balancer Editor', reaper.ImGui_ConfigFlags_DockingEnable())
local font = reaper.ImGui_CreateFont("sans-serif", 13)
local font_mini = reaper.ImGui_CreateFont("sans-serif", 11)
reaper.ImGui_AttachFont(ctx, font)
reaper.ImGui_AttachFont(ctx, font_mini)

-- Helper functions
function rgba2num(red, green, blue, alpha)
    local blue = blue * 256
    local green = green * 256 * 256
    local red = red * 256 * 256 * 256
    return red + green + blue + alpha
end

function HSV(h, s, v, a)
    local r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a or 1.0)
end

-- Load configuration from ExtState
function LoadConfigs()
    local loaded = LoadExtStateTable(ScriptName, "configs", true)
    if loaded then
        return loaded
    end
    return {
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
end

-- Save configuration to ExtState
function SaveConfigs(configs)
    SaveExtStateTable(ScriptName, "configs", configs, true)
end

-- Load groups from ExtState
function LoadGroups()
    local loaded = LoadExtStateTable(ScriptName, "groups", true)
    if loaded then
        return loaded
    end
    return {}
end

-- Save groups to ExtState
function SaveGroups(groups)
    SaveExtStateTable(ScriptName, "groups", groups, true)
end

-- Get track GUID
function GetTrackGUID(track)
    if not track then
        return nil
    end
    return reaper.GetTrackGUID(track)
end

-- Get track from GUID
function GetTrackFromGUID(guid)
    -- Ensure GUID is properly formatted with braces
    if not guid:match("^{.*}$") then
        guid = "{" .. guid .. "}"
    end
    return reaper.BR_GetMediaTrackByGUID(0, guid)
end

-- Create a new group from selected tracks
function CreateNewGroup(groups)
    local num_tracks = reaper.CountSelectedTracks(0)
    if num_tracks < 2 then
        reaper.ShowMessageBox("Please select at least 2 tracks", "Error", 0)
        return groups
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
        table.insert(groups, new_group)
        SaveGroups(groups)
    else
        local debug_message = "Debug Info:\n\n" .. table.concat(debug_info, "\n") .. 
                            string.format("\n\nFound %d valid tracks out of %d selected", valid_tracks, num_tracks)
        reaper.ShowMessageBox(debug_message, "Error Creating Group", 0)
    end
    
    return groups
end

-- Select all tracks in a group
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

-- Reset a group's volumes to the default value
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
    
    -- Add undo point
    reaper.Undo_OnStateChangeEx("Reset group volumes", -1, -1)
end

-- Remove a group
function RemoveGroup(groups, group_idx)
    if group_idx and group_idx > 0 and group_idx <= #groups then
        table.remove(groups, group_idx)
        SaveGroups(groups)
    end
    return groups
end

-- Toggle background mode
function ToggleBackgroundMode(configs)
    configs.BackgroundRunning = not configs.BackgroundRunning
    SaveConfigs(configs)
    
    -- Update toolbar button state
    if configs.BackgroundRunning then
        -- Set toolbar button ON
        is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
        reaper.SetToggleCommandState(sec, cmd, 1)
        reaper.RefreshToolbar2(sec, cmd)
        
        -- Start the Volume Balancer Core script if it's not already running
        dofile(script_path .. "FTS_Volume Balancer Core.lua")
    else
        -- Set toolbar button OFF
        is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
        reaper.SetToggleCommandState(sec, cmd, 0)
        reaper.RefreshToolbar2(sec, cmd)
        
        -- The core script will detect BackgroundRunning=false and stop itself
    end
    
    return configs
end

-- Draw the UI
function DrawUI()
    -- Set default window size
    reaper.ImGui_SetNextWindowSize(ctx, 400, 500, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Volume Balancer Editor', true)
    if not visible then
        return open
    end
    
    -- Use the main font for the title and buttons
    reaper.ImGui_PushFont(ctx, font)
    
    -- Load current state
    local configs = LoadConfigs()
    local groups = LoadGroups()
    
    -- Create New Group button
    if reaper.ImGui_Button(ctx, 'Create New Group from Selected Tracks') then
        groups = CreateNewGroup(groups)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Create a new volume balancing group from currently selected tracks") end
    
    reaper.ImGui_Separator(ctx)
    
    -- Display existing groups
    for i, group in ipairs(groups) do
        reaper.ImGui_PushID(ctx, i)
        
        -- Create a clickable header that looks like a button
        local buttonColor = 0x2F2F2FFF
        local hoverColor = 0x3F3F3FFF
        local activeColor = 0x4F4F4FFF
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), buttonColor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), hoverColor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), activeColor)
        
        -- Get track count for the group header
        local trackCount = #group
        local headerText = string.format('Group %d (%d tracks)', i, trackCount)
        local is_open = reaper.ImGui_CollapsingHeader(ctx, headerText)
        
        -- If clicked (not just opened/closed), select the tracks
        if reaper.ImGui_IsItemClicked(ctx) then
            SelectGroupTracks(group)
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        if is_open then
            -- Use the mini font for track details
            reaper.ImGui_PushFont(ctx, font_mini)
            
            -- Add some padding
            reaper.ImGui_Indent(ctx, 10)
            
            -- List all tracks in the group
            for j, guid in ipairs(group) do
                local track = GetTrackFromGUID(guid)
                if track then
                    local _, track_name = reaper.GetTrackName(track)
                    local volume = reaper.GetMediaTrackInfo_Value(track, "D_VOL")
                    local volume_db = 20 * math.log(volume, 10)
                    
                    -- Draw track name and volume with different colors
                    reaper.ImGui_Text(ctx, string.format('%d. %s', j, track_name))
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_SetCursorPosX(ctx, 250) -- Align volume values
                    reaper.ImGui_TextColored(ctx, 0x88CC88FF, string.format('%.4f dB', volume_db))
                end
            end
            
            reaper.ImGui_Unindent(ctx, 10)
            
            -- Add a small space before the buttons
            reaper.ImGui_Spacing(ctx)
            
            -- Create a row for the buttons
            local buttonWidth = 120
            local windowWidth = reaper.ImGui_GetWindowContentRegionMax(ctx)
            local spacing = 10
            
            -- Reset Group button
            reaper.ImGui_SetCursorPosX(ctx, (windowWidth - (buttonWidth * 2 + spacing)) * 0.5)
            if reaper.ImGui_Button(ctx, 'Reset Group##' .. i, buttonWidth) then
                ResetGroupVolumes(group)
            end
            if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Reset all tracks in this group to equal volumes (total = 0 dB)") end
            
            -- Remove Group button
            reaper.ImGui_SameLine(ctx, 0, spacing)
            if reaper.ImGui_Button(ctx, 'Remove Group##' .. i, buttonWidth) then
                groups = RemoveGroup(groups, i)
            end
            if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Remove this volume balancing group") end
            
            reaper.ImGui_PopFont(ctx) -- Pop the mini font
        end
        
        reaper.ImGui_PopID(ctx)
    end
    
    -- Add a separator before the settings
    reaper.ImGui_Separator(ctx)
    
    -- Settings section
    reaper.ImGui_Text(ctx, "Settings")
    
    -- Report Values checkbox
    local changed_report, value_report = reaper.ImGui_Checkbox(ctx, "Report Values to Debug Log", configs.ReportValues)
    if changed_report then
        configs.ReportValues = value_report
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Log volume values to the debug console every 5 seconds") end
    
    -- Debug Mode checkbox
    local changed_debug, value_debug = reaper.ImGui_Checkbox(ctx, "Debug Mode", configs.DebugMode)
    if changed_debug then
        configs.DebugMode = value_debug
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Enable detailed debug output in the console") end
    
    -- Use -inf dB checkbox
    local changed_inf, value_inf = reaper.ImGui_Checkbox(ctx, "Use -inf dB as minimum volume", configs.UseInfMin)
    if changed_inf then
        configs.UseInfMin = value_inf
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "When enabled, tracks can be set to -inf dB (complete silence)") end
    
    -- Min volume setting (only show if not using -inf)
    if not configs.UseInfMin then
        local changed_min, value_min = reaper.ImGui_InputDouble(ctx, "Minimum Volume (dB)", configs.MinVolume, 1.0, 5.0, "%.1f")
        if changed_min then
            configs.MinVolume = value_min
            SaveConfigs(configs)
        end
        if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Minimum volume level for tracks in a group") end
    end
    
    -- Max volume setting
    local changed_max, value_max = reaper.ImGui_InputDouble(ctx, "Maximum Volume (dB)", configs.MaxVolume, 0.1, 1.0, "%.1f")
    if changed_max then
        configs.MaxVolume = value_max
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Maximum volume level for tracks in a group") end
    
    -- Nudge amount setting
    local changed_nudge, value_nudge = reaper.ImGui_InputDouble(ctx, "Nudge Amount (dB)", configs.NudgeAmount, 0.1, 1.0, "%.1f")
    if changed_nudge then
        configs.NudgeAmount = value_nudge
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Amount to nudge volume up or down when using the +/- buttons") end
    
    -- Auto nudge amount checkbox
    local changed_auto_nudge, value_auto_nudge = reaper.ImGui_Checkbox(ctx, "Auto Nudge Amount", configs.AutoNudgeAmount)
    if changed_auto_nudge then
        configs.AutoNudgeAmount = value_auto_nudge
        SaveConfigs(configs)
    end
    if Configs and Configs.ToolTips then GUI.ToolTip(ctx, "Automatically set nudge amount based on group size") end
    
    -- Add a separator before the background mode button
    reaper.ImGui_Separator(ctx)
    
    -- Add a small space before the button
    reaper.ImGui_Spacing(ctx)
    
    -- Add a subtle background mode toggle button at the bottom
    local button_text = configs.BackgroundRunning and "● Background Mode Active" or "○ Background Mode Inactive"
    local button_color = configs.BackgroundRunning and 0x88CC88FF or 0x888888FF
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x333333FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x444444FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x555555FF)
    
    -- Center the button
    local button_width = 180
    local window_width = reaper.ImGui_GetWindowContentRegionMax(ctx)
    reaper.ImGui_SetCursorPosX(ctx, (window_width - button_width) * 0.5)
    
    if reaper.ImGui_Button(ctx, button_text, button_width, 25) then
        configs = ToggleBackgroundMode(configs)
    end
    reaper.ImGui_PopStyleColor(ctx, 3)
    
    if Configs and Configs.ToolTips then 
        if configs.BackgroundRunning then
            GUI.ToolTip(ctx, "Background mode is active - script will continue running when UI is closed")
        else
            GUI.ToolTip(ctx, "Background mode is inactive - script will stop when UI is closed")
        end
    end
    
    reaper.ImGui_PopFont(ctx) -- Pop the main font
    
    reaper.ImGui_End(ctx)
    return open
end

-- Main loop
function Loop()
    -- Draw UI and check if window is open
    local open = DrawUI()
    
    -- Continue if the UI is open
    if open then
        reaper.defer(Loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end

-- Start the loop
reaper.PreventUIRefresh(1)

-- Display current state message
local startup_configs = LoadConfigs()
if startup_configs.BackgroundRunning then
    reaper.ShowConsoleMsg("Volume Balancer is currently ACTIVE. Toggle background mode to stop it.\n")
else
    reaper.ShowConsoleMsg("Volume Balancer is currently INACTIVE. Toggle background mode to start it.\n")
end

Loop()
reaper.PreventUIRefresh(-1) 