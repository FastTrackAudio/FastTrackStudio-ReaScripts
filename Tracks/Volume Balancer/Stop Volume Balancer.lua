-- Stop Volume Balancer
-- Simple script to stop the Volume Balancer Core

local info = debug.getinfo(1, "S")
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])

-- Get the path to the FastTrackStudio Scripts root folder (two levels up)
local root_path = script_path:match("(.*[/\\])Tracks[/\\].*[/\\]")
if not root_path then
    root_path = script_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

-- Load utilities from the libraries/utils folder
dofile(root_path .. "libraries/utils/Serialize Table.lua") -- Load serialization functions

-- Script name for ExtState
local ScriptName = "Volume Balancer"

-- Load configuration from ExtState
function LoadConfigs()
    local loaded = LoadExtStateTable(ScriptName, "configs", true)
    if loaded then
        return loaded
    end
    return {
        BackgroundRunning = false
    }
end

-- Save configuration to ExtState
function SaveConfigs(configs)
    SaveExtStateTable(ScriptName, "configs", configs, true)
end

-- Set ToolBar Button OFF
function SetButtonOFF()
    is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    state = reaper.GetToggleCommandStateEx(sec, cmd)
    reaper.SetToggleCommandState(sec, cmd, 0) -- Set OFF
    reaper.RefreshToolbar2(sec, cmd)
end

-- Load configs and stop the Volume Balancer
local configs = LoadConfigs()
configs.BackgroundRunning = false
SaveConfigs(configs)
SetButtonOFF()

-- Show confirmation message
reaper.ShowMessageBox("Volume Balancer has been stopped.", "Volume Balancer Stopped", 0) 