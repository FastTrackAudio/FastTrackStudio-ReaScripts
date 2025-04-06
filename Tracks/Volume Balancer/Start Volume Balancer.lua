-- Start Volume Balancer
-- Simple script to start the Volume Balancer Core

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

-- Set ToolBar Button ON
function SetButtonON()
    is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    state = reaper.GetToggleCommandStateEx(sec, cmd)
    reaper.SetToggleCommandState(sec, cmd, 1) -- Set ON
    reaper.RefreshToolbar2(sec, cmd)
end

-- Load configs and start the Volume Balancer
local configs = LoadConfigs()
configs.BackgroundRunning = true
SaveConfigs(configs)
SetButtonON()

-- Load the Volume Balancer Core script
dofile(script_path .. "FTS_Volume Balancer Core.lua")

-- Show confirmation message
reaper.ShowMessageBox("Volume Balancer has been started.", "Volume Balancer Started", 0) 