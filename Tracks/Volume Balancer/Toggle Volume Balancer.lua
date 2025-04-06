-- Toggle Volume Balancer
-- Simple script to toggle the Volume Balancer Core on and off

local info = debug.getinfo(1, "S")
local script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
dofile(script_path .. "Serialize Table.lua") -- Load serialization functions

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

-- Set ToolBar Button OFF
function SetButtonOFF()
    is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    state = reaper.GetToggleCommandStateEx(sec, cmd)
    reaper.SetToggleCommandState(sec, cmd, 0) -- Set OFF
    reaper.RefreshToolbar2(sec, cmd)
end

-- Load configs and toggle the Volume Balancer
local configs = LoadConfigs()
configs.BackgroundRunning = not configs.BackgroundRunning
SaveConfigs(configs)

if configs.BackgroundRunning then
    SetButtonON()
    -- Load the Volume Balancer Core script
    dofile(script_path .. "Volume Balancer Core.lua")
    -- Show confirmation message
    reaper.ShowMessageBox("Volume Balancer has been started.", "Volume Balancer Started", 0)
else
    SetButtonOFF()
    -- Show confirmation message
    reaper.ShowMessageBox("Volume Balancer has been stopped.", "Volume Balancer Stopped", 0)
end 