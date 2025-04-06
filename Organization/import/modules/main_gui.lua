-- @noindex
--[[
 * FastTrackStudio - Main GUI Module
 * Handles the primary UI for the FTS Import Into Template By Name GUI
--]]

local MainGUI = {}

-- Get the script path for loading dependencies
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local modules_path = script_path:match("(.*[/\\])modules[/\\]")
local root_path = modules_path:match("(.*[/\\])Organization[/\\].*[/\\]")
if not root_path then
    root_path = modules_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

package.path = package.path .. ";" .. modules_path .. "?.lua"
local Utils = require("utils")
local DefaultPatterns = require("default_patterns")
local TrackConfig = require("track_config")
local ImportExport = require("import_export")
local TrackManagement = require("track_management")

-- ExtState name and tabs
local ext_state_name = "FastTrackStudio_ImportByName"
local tabs = { "Track Configurations", "Global Patterns", "Import/Export", "Logs", "Help" }
local current_tab = 1

-- Context and fonts for ImGui
local ctx = nil
local font_title = nil
local font_bold = nil
local font_mini = nil
local first_frame = true
local import_script = nil

-- Log filter settings
local log_filter = {
    organize = true,
    match = true,
    unmatch = true,
    track = true,
    overlap = true,
    create = true,
    move = true,
    error = true,
    summary = true,
    system = true
}

-- Log colors for different categories
local log_colors = {
    ORGANIZE = 0x88AAFFFF, -- Blue
    MATCH = 0x88DDAAFF,    -- Green-ish
    UNMATCH = 0xFFAA88FF,   -- Orange
    TRACK = 0xAAAAFFFF,     -- Light blue
    OVERLAP = 0xFFAAAAFF,   -- Pink
    CREATE = 0xAAFFAAFF,    -- Green
    MOVE = 0xDDDDAAFF,      -- Yellow
    ERROR = 0xFF8888FF,     -- Red
    SUMMARY = 0xFFFFAAFF,   -- Yellow
    SYSTEM = 0xBBBBBBFF,    -- Gray
    DEFAULT = 0xFFFFFFFF    -- White
}

-- Helper functions for ExtState management
function MainGUI.loadExtStateTable(ext_name, key, is_table)
    local value = reaper.GetExtState(ext_name, key)
    if value and value ~= "" and is_table then
        local json = dofile(root_path .. "libraries/utils/json.lua")
        local success, data = pcall(function() return json.decode(value) end)
        if success then return data end
    end
    return value
end

function MainGUI.saveExtStateTable(ext_name, key, value, is_table)
    local data_to_save = value
    if is_table then
        local json = dofile(root_path .. "libraries/utils/json.lua")
        data_to_save = json.encode(value)
    end
    reaper.SetExtState(ext_name, key, data_to_save, true)
end

-- Compatibility layer for different versions of ReaImGui
local function InitImGuiCompatibility()
    -- Check for ImGui functions and create fallbacks if needed
    if not reaper.ImGui_BeginTabBar then
        -- Define fallback for BeginTabBar
        reaper.ImGui_BeginTabBar = function(ctx, name)
            -- Simple implementation that always returns true
            -- In a real implementation, we'd have more logic
            reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "Tab Bar (Compatibility Mode)")
            reaper.ImGui_Separator(ctx)
            return true
        end
    end
    
    if not reaper.ImGui_EndTabBar then
        -- Define fallback for EndTabBar
        reaper.ImGui_EndTabBar = function(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
        end
    end
    
    -- Ensure we have CreateFont function
    if not reaper.ImGui_CreateFont then
        reaper.ImGui_CreateFont = function(face, size)
            return nil
        end
    end
end

-- Initialize the GUI
function MainGUI.Init(import_interface)
    -- Initialize the ImGui compatibility layer
    InitImGuiCompatibility()
    
    -- Store import script interface
    import_script = import_interface
    
    -- Create ImGui context
    ctx = reaper.ImGui_CreateContext('FTS Import Into Template By Name')
    
    -- Use a simpler approach to fonts, using pcall to handle potential errors
    pcall(function()
        -- We'll use default fonts instead of trying to create custom ones
        -- This ensures better compatibility across different versions
    end)
    
    -- Set up deferred calls and main loop
    reaper.defer(MainGUI.Loop)
end

-- Main loop function
function MainGUI.Loop()
    -- Process any deferred commands
    
    -- Set window size
    if first_frame then
        reaper.ImGui_SetNextWindowSize(ctx, 600, 500, reaper.ImGui_Cond_FirstUseEver())
        first_frame = false
    end
    
    -- Main window
    local visible, open = reaper.ImGui_Begin(ctx, 'FTS Import Into Template By Name Modular', true)
    if not visible then 
        if open then
            reaper.defer(MainGUI.Loop)
        end
        return
    end
    
    -- Draw the menu bar
    if reaper.ImGui_BeginMenuBar(ctx) then
        -- File Menu
        if reaper.ImGui_BeginMenu(ctx, "File") then
            if reaper.ImGui_MenuItem(ctx, "Exit") then
                open = false
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        -- Help Menu
        if reaper.ImGui_BeginMenu(ctx, "Help") then
            if reaper.ImGui_MenuItem(ctx, "About") then
                reaper.ShowMessageBox("FTS Import Into Template By Name Modular\nVersion: 2.0\n\nBy FastTrackStudio", "About", 0)
            end
            reaper.ImGui_EndMenu(ctx)
        end
        
        reaper.ImGui_EndMenuBar(ctx)
    end
    
    -- Draw main content
    MainGUI.DrawMainUI(ctx)
    
    reaper.ImGui_End(ctx)
    
    -- Continue loop if window is still open
    if open then
        reaper.defer(MainGUI.Loop)
    else
        reaper.ImGui_DestroyContext(ctx)
    end
end

-- Draw the main UI
function MainGUI.DrawMainUI(ctx)
    -- Apply title font if available, otherwise just use text
    if font_title then
        reaper.ImGui_PushFont(ctx, font_title)
        reaper.ImGui_Text(ctx, "FastTrackStudio Import Into Template By Name")
        reaper.ImGui_PopFont(ctx)
    else
        reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "FastTrackStudio Import Into Template By Name")
        reaper.ImGui_Spacing(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Main Action Buttons - Side by side at the top
    local buttonHeight = 36
    local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
    local buttonWidth = availWidth / 2 - 4 -- Divided by 2 with a small gap
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 8, 8)
    
    -- Import from File button
    if reaper.ImGui_Button(ctx, "Import from File", buttonWidth, buttonHeight) then
        if import_script and import_script.ImportFromFile then
            import_script.ImportFromFile()
        else
            reaper.ShowMessageBox("Import from file functionality not implemented in this version.", "Feature Not Available", 0)
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- Organize Selected Items button
    if reaper.ImGui_Button(ctx, "Organize Selected Items", buttonWidth, buttonHeight) then
        if import_script and import_script.OrganizeSelectedItems then
            import_script.OrganizeSelectedItems()
        else
            reaper.ShowMessageBox("Organize selected items functionality not implemented in this version.", "Feature Not Available", 0)
        end
    end
    
    reaper.ImGui_PopStyleVar(ctx)
    
    reaper.ImGui_Spacing(ctx)
    
    -- Status message display - Only show if message is recent (within 5 seconds)
    if import_script and import_script.LastMessage and import_script.LastMessage ~= "" then
        local currentTime = os.time()
        local messageAge = currentTime - import_script.LastMessageTime
        
        if messageAge < 5 then -- Show message for 5 seconds
            -- Draw message with background
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A661A88) -- Dark green with alpha
            reaper.ImGui_BeginChild(ctx, "##StatusMessage", availWidth, 30, true)
            
            -- Center the text vertically and horizontally
            local textWidth = reaper.ImGui_CalcTextSize(ctx, import_script.LastMessage)
            reaper.ImGui_SetCursorPos(ctx, (availWidth - textWidth) / 2, 8)
            
            -- Draw the message text
            reaper.ImGui_TextColored(ctx, 0xAAFFAAFF, import_script.LastMessage) -- Light green text
            
            reaper.ImGui_EndChild(ctx)
            reaper.ImGui_PopStyleColor(ctx)
            
            reaper.ImGui_Spacing(ctx)
        elseif messageAge >= 5 and messageAge < 6 then
            -- Clear the message after it expires
            import_script.LastMessage = ""
        end
    end
    
    -- Debug controls in a row
    local rowWidth = reaper.ImGui_GetWindowWidth(ctx) - 20
    local resetButtonWidth = 150
    local debugCheckboxWidth = 100
    local renameCheckboxWidth = 120
    local deleteEmptyTracksWidth = 140
    
    -- Delete Empty Tracks checkbox
    reaper.ImGui_SameLine(ctx, rowWidth - resetButtonWidth - debugCheckboxWidth - renameCheckboxWidth - deleteEmptyTracksWidth - 10)
    local delete_empty_changed, delete_empty_value
    if import_script and import_script.LoadConfigs then
        local configs = import_script.LoadConfigs()
        delete_empty_changed, delete_empty_value = reaper.ImGui_Checkbox(ctx, "Delete Empty Tracks", configs.delete_empty_tracks or false)
        if delete_empty_changed then
            configs.delete_empty_tracks = delete_empty_value
            import_script.DeleteEmptyTracks = delete_empty_value
            if import_script.SaveConfigs then
                import_script.SaveConfigs(configs)
            end
        end
    end
    
    -- Rename Tracks checkbox
    reaper.ImGui_SameLine(ctx, rowWidth - resetButtonWidth - debugCheckboxWidth - renameCheckboxWidth - 10)
    local rename_changed, rename_value
    if import_script and import_script.LoadConfigs then
        local configs = import_script.LoadConfigs()
        rename_changed, rename_value = reaper.ImGui_Checkbox(ctx, "Rename Tracks", configs.global_rename_track or false)
        if rename_changed then
            configs.global_rename_track = rename_value
            import_script.GlobalRenameTrack = rename_value
            if import_script.SaveConfigs then
                import_script.SaveConfigs(configs)
            end
        end
    end
    
    -- Debug mode checkbox
    reaper.ImGui_SameLine(ctx, rowWidth - resetButtonWidth - debugCheckboxWidth)
    local debug_changed, debug_value = reaper.ImGui_Checkbox(ctx, "Debug Mode", import_script.DebugMode)
    if debug_changed then
        import_script.DebugMode = debug_value
        if debug_value then
            reaper.ShowConsoleMsg("\n=== DEBUG MODE ENABLED ===\n")
        end
    end
    
    -- Reset Configurations button
    reaper.ImGui_SameLine(ctx, rowWidth - resetButtonWidth + 10)
    if reaper.ImGui_Button(ctx, "Reset Configurations", resetButtonWidth - 10, 0) then
        -- Ask for confirmation before resetting
        local confirm = reaper.ShowMessageBox("This will reset all track configurations to defaults.\nAny user customizations will be lost.\n\nThis can fix issues with pattern inheritance or when tracks\naren't matching properly.\n\nAre you sure?", "Reset Configurations", 1)
        if confirm == 1 then -- 1 = OK, 2 = Cancel
            if import_script and import_script.ResetTrackConfigs then
                -- Reset configurations and load the fresh defaults
                local configs = import_script.ResetTrackConfigs()
                -- No need to show a popup message, we're using the status message system now
            end
        end
    end
    
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Tabs bar
    if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
        -- Configuration tab
        if reaper.ImGui_BeginTabItem(ctx, tabs[1]) then
            TrackConfig.DrawConfigTab(ctx, ext_state_name, import_script)
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Global Patterns tab
        if reaper.ImGui_BeginTabItem(ctx, tabs[2]) then
            DefaultPatterns.DrawGlobalPatternsTab(ctx, ext_state_name, MainGUI.loadExtStateTable, MainGUI.saveExtStateTable)
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Import/Export tab
        if reaper.ImGui_BeginTabItem(ctx, tabs[3]) then
            ImportExport.DrawImportExportTab(ctx, ext_state_name, import_script)
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Logs tab
        if reaper.ImGui_BeginTabItem(ctx, tabs[4]) then
            MainGUI.DrawLogsTab(ctx)
            reaper.ImGui_EndTabItem(ctx)
        end
        
        -- Help tab
        if reaper.ImGui_BeginTabItem(ctx, tabs[5]) then
            MainGUI.DrawHelpTab(ctx)
            reaper.ImGui_EndTabItem(ctx)
        end
        
        reaper.ImGui_EndTabBar(ctx)
    end
end

-- Draw the help tab
function MainGUI.DrawHelpTab(ctx)
    reaper.ImGui_BeginChild(ctx, "##HelpChild", 0, 0, true)
    
    -- Help header
    if font_bold then
        reaper.ImGui_PushFont(ctx, font_bold)
        reaper.ImGui_Text(ctx, "How to Use")
        reaper.ImGui_PopFont(ctx)
    else
        reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "How to Use")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextWrapped(ctx, "This script helps organize your workflow by automatically managing track templates and naming conventions.")
    reaper.ImGui_Spacing(ctx)
    
    -- Basic workflow section
    if font_bold then
        reaper.ImGui_PushFont(ctx, font_bold)
        reaper.ImGui_Text(ctx, "Basic Workflow")
        reaper.ImGui_PopFont(ctx)
    else
        reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "Basic Workflow")
    end
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextWrapped(ctx, "To use this script effectively:")
    reaper.ImGui_BulletText(ctx, "1. Set up track configurations that match your recording workflow")
    reaper.ImGui_BulletText(ctx, "2. Configure naming patterns for consistency")
    reaper.ImGui_BulletText(ctx, "3. Select media files to import")
    reaper.ImGui_BulletText(ctx, "4. Run the importer to automatically place files on appropriate tracks")
    reaper.ImGui_BulletText(ctx, "5. Export your setup for reuse across projects")
    reaper.ImGui_Spacing(ctx)
    
    -- Tips section
    if font_bold then
        reaper.ImGui_PushFont(ctx, font_bold)
        reaper.ImGui_Text(ctx, "Tips")
        reaper.ImGui_PopFont(ctx)
    else
        reaper.ImGui_TextColored(ctx, 0xFFAA33FF, "Tips")
    end
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_BulletText(ctx, "Use consistent file naming conventions to make matching easier")
    reaper.ImGui_BulletText(ctx, "Set up default configurations for your common recording scenarios")
    reaper.ImGui_BulletText(ctx, "Preview how file names will be analyzed in the import dialog")
    reaper.ImGui_BulletText(ctx, "Back up your configurations regularly with the export feature")
    reaper.ImGui_Spacing(ctx)
    
    -- Version and credits
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, "FastTrackStudio Import Into Template By Name")
    reaper.ImGui_Text(ctx, "Version: 2.0.0")
    reaper.ImGui_Text(ctx, "Author: Cody Hanson / FastTrackStudio")
    
    reaper.ImGui_EndChild(ctx)
end

-- Draw the logs tab
function MainGUI.DrawLogsTab(ctx)
    local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
    
    -- Top controls row
    if reaper.ImGui_Button(ctx, "Clear Logs") then
        if import_script and import_script.ClearLogs then
            import_script.ClearLogs()
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Copy to Clipboard") then
        -- Build a string with all visible logs
        local log_text = ""
        local logs = import_script and import_script.GetLogs and import_script.GetLogs() or {}
        
        for _, log in ipairs(logs) do
            log_text = log_text .. log .. "\n"
        end
        
        -- Copy to clipboard using REAPER API
        reaper.CF_SetClipboard(log_text)
    end
    
    -- Category filters
    reaper.ImGui_SameLine(ctx, availWidth - 300)
    reaper.ImGui_Text(ctx, "Filters:")
    
    -- Create filter checkboxes
    reaper.ImGui_BeginChild(ctx, "##FiltersRegion", 0, 30, false)
    local x_pos = 60
    
    -- Organize filter
    reaper.ImGui_SetCursorPosX(ctx, x_pos)
    local changed, value = reaper.ImGui_Checkbox(ctx, "Organize", log_filter.organize)
    if changed then log_filter.organize = value end
    x_pos = x_pos + 80
    
    -- Match filter
    reaper.ImGui_SameLine(ctx, x_pos)
    changed, value = reaper.ImGui_Checkbox(ctx, "Match", log_filter.match)
    if changed then log_filter.match = value end
    x_pos = x_pos + 70
    
    -- Track filter
    reaper.ImGui_SameLine(ctx, x_pos)
    changed, value = reaper.ImGui_Checkbox(ctx, "Track", log_filter.track)
    if changed then log_filter.track = value end
    x_pos = x_pos + 70
    
    -- Error filter
    reaper.ImGui_SameLine(ctx, x_pos)
    changed, value = reaper.ImGui_Checkbox(ctx, "Error", log_filter.error)
    if changed then log_filter.error = value end
    x_pos = x_pos + 70
    
    -- More filter buttons on next row
    reaper.ImGui_SetCursorPosX(ctx, 60)
    
    -- Create filter
    changed, value = reaper.ImGui_Checkbox(ctx, "Create", log_filter.create)
    if changed then log_filter.create = value end
    
    -- Move filter
    reaper.ImGui_SameLine(ctx)
    changed, value = reaper.ImGui_Checkbox(ctx, "Move", log_filter.move)
    if changed then log_filter.move = value end
    
    -- Overlap filter
    reaper.ImGui_SameLine(ctx)
    changed, value = reaper.ImGui_Checkbox(ctx, "Overlap", log_filter.overlap)
    if changed then log_filter.overlap = value end
    
    -- Summary filter
    reaper.ImGui_SameLine(ctx)
    changed, value = reaper.ImGui_Checkbox(ctx, "Summary", log_filter.summary)
    if changed then log_filter.summary = value end
    
    reaper.ImGui_EndChild(ctx)
    
    -- Draw log messages with colors
    reaper.ImGui_Separator(ctx)
    
    -- Calculate logs area height (subtract filter area and some padding)
    local logsHeight = reaper.ImGui_GetContentRegionAvail(ctx)
    
    -- Create a child window with border for the logs
    reaper.ImGui_BeginChild(ctx, "##LogsRegion", 0, logsHeight, true)
    
    -- Get logs from import_script
    local logs = import_script and import_script.GetLogs and import_script.GetLogs() or {}
    
    -- If no logs, show a message
    if #logs == 0 then
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 10)
        reaper.ImGui_SetCursorPosX(ctx, (availWidth - 250) / 2)
        reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "No log messages to display")
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 10)
        reaper.ImGui_SetCursorPosX(ctx, (availWidth - 350) / 2)
        reaper.ImGui_TextColored(ctx, 0xAAAAAAAA, "Organize items or import files to generate logs")
    else
        -- Display logs with colors based on category
        for _, log in ipairs(logs) do
            -- Extract category if it exists
            local category = log:match("%[([%u]+)%]")
            local should_show = true
            
            -- Apply filters
            if category then
                local category_lower = category:lower()
                if category_lower == "organize" and not log_filter.organize then should_show = false end
                if category_lower == "match" and not log_filter.match then should_show = false end
                if category_lower == "unmatch" and not log_filter.unmatch then should_show = false end
                if category_lower == "track" and not log_filter.track then should_show = false end
                if category_lower == "overlap" and not log_filter.overlap then should_show = false end
                if category_lower == "create" and not log_filter.create then should_show = false end
                if category_lower == "move" and not log_filter.move then should_show = false end
                if category_lower == "error" and not log_filter.error then should_show = false end
                if category_lower == "summary" and not log_filter.summary then should_show = false end
                if category_lower == "system" and not log_filter.system then should_show = false end
            end
            
            -- If the log should be shown according to filters
            if should_show then
                -- Determine color based on category
                local textColor = log_colors.DEFAULT
                
                if category then
                    textColor = log_colors[category] or log_colors.DEFAULT
                end
                
                -- Output the log with appropriate color
                reaper.ImGui_TextColored(ctx, textColor, log)
            end
        end
    end
    
    -- If user scrolls to bottom, auto-scroll to new items
    if reaper.ImGui_GetScrollY(ctx) >= reaper.ImGui_GetScrollMaxY(ctx) - 20 then
        reaper.ImGui_SetScrollHereY(ctx, 1.0)
    end
    
    reaper.ImGui_EndChild(ctx)
end

return MainGUI 