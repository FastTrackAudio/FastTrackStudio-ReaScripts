-- @noindex
--[[
 * FastTrackStudio - Import/Export Module
 * Handles importing and exporting configurations
--]]

local ImportExport = {}

-- Get dependencies
local script_path = debug.getinfo(1, "S").source:match([[^@?(.*[\/])[^\/]-$]])
local modules_path = script_path:match("(.*[/\\])modules[/\\]")
local root_path = modules_path:match("(.*[/\\])Organization[/\\].*[/\\]")
if not root_path then
    root_path = modules_path:match("(.*[/\\]).*[/\\].*[/\\]")
end

package.path = package.path .. ";" .. modules_path .. "?.lua"
local Utils = require("utils")
local json = dofile(root_path .. "libraries/utils/json.lua")

-- Load default patterns module for inheritance modes
local DefaultPatterns = require("default_patterns")
local INHERITANCE_MODES = DefaultPatterns.INHERITANCE_MODES

-- Draw the import/export tab UI
function ImportExport.DrawImportExportTab(ctx, ext_state_name, import_script)
    -- Import/Export section
    reaper.ImGui_Text(ctx, "Import and Export Configuration Files")
    reaper.ImGui_Spacing(ctx)
    
    -- Get current inheritance modes
    local pattern_mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "patterns", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local track_mode = DefaultPatterns.LoadInheritanceMode(ext_state_name, "track_configs", INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE)
    local mode_names = { "Use Defaults Only", "Use Defaults + Overrides", "Use Overrides Only" }
    
    -- Show what will be exported
    reaper.ImGui_TextWrapped(ctx, "Pattern Inheritance Mode: " .. mode_names[pattern_mode])
    reaper.ImGui_TextWrapped(ctx, "Track Config Inheritance Mode: " .. mode_names[track_mode])
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Import/Export Buttons
    if reaper.ImGui_Button(ctx, "Import Configuration") then
        local retval, file_path = reaper.JS_Dialog_BrowseForOpenFiles("Select configuration file", "", "", "JSON files (.json)\0*.json\0\0", false)
        
        if retval and file_path ~= "" then
            ImportExport.ImportConfiguration(file_path, ext_state_name, import_script)
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, "Export Configuration") then
        local retval, file_path = reaper.JS_Dialog_BrowseForSaveFile("Save configuration file", "", "", "JSON files (.json)\0*.json\0\0", ".json")
        
        if retval and file_path ~= "" then
            ImportExport.ExportConfiguration(file_path, ext_state_name, import_script)
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Specific Pattern Category Import/Export
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Specific Pattern Categories")
    reaper.ImGui_Spacing(ctx)
    
    -- Get pattern categories
    local pattern_categories = {}
    for _, category in ipairs(DefaultPatterns.GLOBAL_PATTERN_CATEGORIES) do
        table.insert(pattern_categories, { key = category.key, name = category.name, selected = false })
    end
    
    -- Initialize selected categories if not already done
    if not ImportExport.selected_categories then
        ImportExport.selected_categories = {}
        for _, category in ipairs(pattern_categories) do
            ImportExport.selected_categories[category.key] = false
        end
    end
    
    -- Allow selection of specific categories
    reaper.ImGui_TextWrapped(ctx, "Select pattern categories to import or export:")
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_BeginChild(ctx, "##PatternCategoriesSelect", -1, 120, true)
    
    -- "Select All" and "Select None" buttons
    if reaper.ImGui_Button(ctx, "Select All") then
        for key, _ in pairs(ImportExport.selected_categories) do
            ImportExport.selected_categories[key] = true
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, "Select None") then
        for key, _ in pairs(ImportExport.selected_categories) do
            ImportExport.selected_categories[key] = false
        end
    end
    
    reaper.ImGui_Separator(ctx)
    
    -- Create a 3-column layout for pattern checkboxes
    local column_count = 3
    local items_per_column = math.ceil(#pattern_categories / column_count)
    
    for i = 1, #pattern_categories do
        local category = pattern_categories[i]
        local changed, selected = reaper.ImGui_Checkbox(ctx, category.name, ImportExport.selected_categories[category.key])
        
        if changed then
            ImportExport.selected_categories[category.key] = selected
        end
        
        -- Create columns for better layout
        if i % items_per_column ~= 0 and i ~= #pattern_categories then
            reaper.ImGui_SameLine(ctx)
        end
    end
    
    reaper.ImGui_EndChild(ctx)
    
    -- Count selected categories
    local selected_count = 0
    local selected_keys = {}
    for key, selected in pairs(ImportExport.selected_categories) do
        if selected then
            selected_count = selected_count + 1
            table.insert(selected_keys, key)
        end
    end
    
    -- Show selection summary
    reaper.ImGui_Text(ctx, string.format("Selected Categories: %d", selected_count))
    
    -- Import/Export buttons for specific categories
    if reaper.ImGui_Button(ctx, "Import Selected Categories") then
        if selected_count == 0 then
            reaper.ShowMessageBox("Please select at least one pattern category to import.", "No Categories Selected", 0)
        else
            local retval, file_path = reaper.JS_Dialog_BrowseForOpenFiles("Select pattern file", "", "", "JSON files (.json)\0*.json\0\0", false)
            
            if retval and file_path ~= "" then
                ImportExport.ImportSpecificPatterns(file_path, ext_state_name, selected_keys)
            end
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, "Export Selected Categories") then
        if selected_count == 0 then
            reaper.ShowMessageBox("Please select at least one pattern category to export.", "No Categories Selected", 0)
        else
            local retval, file_path = reaper.JS_Dialog_BrowseForSaveFile("Save pattern file", "", "", "JSON files (.json)\0*.json\0\0", ".json")
            
            if retval and file_path ~= "" then
                ImportExport.ExportSpecificPatterns(file_path, ext_state_name, selected_keys)
            end
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Import/Export Defaults
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Defaults Management")
    reaper.ImGui_Spacing(ctx)
    
    -- Import/Export Default Buttons
    if reaper.ImGui_Button(ctx, "Import Defaults") then
        local retval, file_path = reaper.JS_Dialog_BrowseForOpenFiles("Select defaults file", "", "", "JSON files (.json)\0*.json\0\0", false)
        
        if retval and file_path ~= "" then
            ImportExport.ImportDefaults(file_path)
        end
    end
    
    reaper.ImGui_SameLine(ctx)
    
    if reaper.ImGui_Button(ctx, "Export Defaults") then
        local retval, file_path = reaper.JS_Dialog_BrowseForSaveFile("Save defaults file", "", "", "JSON files (.json)\0*.json\0\0", ".json")
        
        if retval and file_path ~= "" then
            ImportExport.ExportDefaults(file_path)
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Reset to factory defaults
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Factory Reset")
    reaper.ImGui_TextWrapped(ctx, "Reset configurations to factory defaults. This will remove all custom overrides.")
    reaper.ImGui_Spacing(ctx)
    
    if reaper.ImGui_Button(ctx, "Reset All to Factory Defaults") then
        local confirm = reaper.ShowMessageBox("Are you sure you want to reset ALL configurations to factory defaults? This will remove all custom overrides.", "Confirm Reset", 4)
        
        if confirm == 6 then -- Yes
            -- Clear all ExtState values
            reaper.DeleteExtState(ext_state_name, "track_configs", false)
            reaper.DeleteExtState(ext_state_name, "patterns", false)
            reaper.DeleteExtState(ext_state_name, "global_patterns", false)
            reaper.DeleteExtState(ext_state_name, "patterns_inheritance_mode", false)
            reaper.DeleteExtState(ext_state_name, "track_configs_inheritance_mode", false)
            
            -- Also delete defaults if they exist
            local defaults_path = Utils.GetRootPath() .. "Organization/import/defaults.json"
            local defaults_file = io.open(defaults_path, "r")
            if defaults_file then
                defaults_file:close()
                os.remove(defaults_path)
            end
            
            reaper.ShowMessageBox("All configurations have been reset to factory defaults.", "Reset Complete", 0)
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Help Text
    reaper.ImGui_TextWrapped(ctx, "Import and export your track configurations for backup or sharing between projects. The exported file includes all track configuration groups and pattern settings based on the currently selected inheritance modes.")
end

-- Function to import configuration
function ImportExport.ImportConfiguration(file_path, ext_state_name, import_script)
    local file = io.open(file_path, "r")
    
    if not file then
        reaper.ShowMessageBox("Could not open file: " .. file_path, "Import Error", 0)
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, data = pcall(json.decode, content)
    
    if not ok or not data then
        reaper.ShowMessageBox("Invalid JSON file: " .. file_path, "Import Error", 0)
        return
    end
    
    -- Import track configurations
    if data.track_configs then
        import_script.SaveTrackConfigs(data.track_configs)
    end
    
    -- Import patterns (by category)
    if data.patterns then
        local patterns_str = json.encode(data.patterns)
        reaper.SetExtState(ext_state_name, "patterns", patterns_str, true)
    end
    
    -- Import global patterns
    if data.global_patterns then
        local global_patterns_str = json.encode(data.global_patterns)
        reaper.SetExtState(ext_state_name, "global_patterns", global_patterns_str, true)
    end
    
    -- Import inheritance modes
    if data.patterns_inheritance_mode then
        reaper.SetExtState(ext_state_name, "patterns_inheritance_mode", tostring(data.patterns_inheritance_mode), true)
    end
    
    if data.track_configs_inheritance_mode then
        reaper.SetExtState(ext_state_name, "track_configs_inheritance_mode", tostring(data.track_configs_inheritance_mode), true)
    end
    
    reaper.ShowMessageBox("Configuration imported successfully!", "Import Complete", 0)
end

-- Function to export configuration
function ImportExport.ExportConfiguration(file_path, ext_state_name, import_script)
    -- Get current configurations
    local track_configs = import_script.LoadTrackConfigs()
    
    -- Get current patterns with inheritance applied
    local patterns_json = reaper.GetExtState(ext_state_name, "patterns")
    local patterns = {}
    
    if patterns_json ~= "" then
        local ok, parsed = pcall(json.decode, patterns_json)
        if ok and parsed then
            patterns = parsed
        end
    end
    
    -- Get current global patterns
    local global_patterns_json = reaper.GetExtState(ext_state_name, "global_patterns")
    local global_patterns = {}
    
    if global_patterns_json ~= "" then
        local ok, parsed = pcall(json.decode, global_patterns_json)
        if ok and parsed then
            global_patterns = parsed
        end
    end
    
    -- Get current inheritance modes
    local patterns_mode_str = reaper.GetExtState(ext_state_name, "patterns_inheritance_mode")
    local track_configs_mode_str = reaper.GetExtState(ext_state_name, "track_configs_inheritance_mode")
    
    local patterns_mode = INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE
    if patterns_mode_str ~= "" then
        patterns_mode = tonumber(patterns_mode_str)
    end
    
    local track_configs_mode = INHERITANCE_MODES.DEFAULT_PLUS_OVERRIDE
    if track_configs_mode_str ~= "" then
        track_configs_mode = tonumber(track_configs_mode_str)
    end
    
    -- Create export data
    local export_data = {
        track_configs = track_configs or {},
        patterns = patterns,
        global_patterns = global_patterns,
        patterns_inheritance_mode = patterns_mode,
        track_configs_inheritance_mode = track_configs_mode
    }
    
    -- Encode to JSON
    local content = json.encode(export_data)
    
    -- Save to file
    local file = io.open(file_path, "w")
    
    if not file then
        reaper.ShowMessageBox("Could not write to file: " .. file_path, "Export Error", 0)
        return
    end
    
    file:write(content)
    file:close()
    
    reaper.ShowMessageBox("Configuration exported successfully!", "Export Complete", 0)
end

-- Function to import defaults
function ImportExport.ImportDefaults(file_path)
    local file = io.open(file_path, "r")
    
    if not file then
        reaper.ShowMessageBox("Could not open file: " .. file_path, "Import Error", 0)
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, data = pcall(json.decode, content)
    
    if not ok or not data then
        reaper.ShowMessageBox("Invalid JSON file: " .. file_path, "Import Error", 0)
        return
    end
    
    -- Validate defaults structure
    if not data.default_patterns or not data.default_groups then
        reaper.ShowMessageBox("Invalid defaults file format. Missing required sections.", "Import Error", 0)
        return
    end
    
    -- Save to defaults.json
    local defaults_path = Utils.GetRootPath() .. "Organization/import/defaults.json"
    local defaults_file = io.open(defaults_path, "w")
    
    if not defaults_file then
        reaper.ShowMessageBox("Could not write to defaults file.", "Import Error", 0)
        return
    end
    
    defaults_file:write(content)
    defaults_file:close()
    
    reaper.ShowMessageBox("Defaults imported successfully!", "Import Complete", 0)
end

-- Function to export defaults
function ImportExport.ExportDefaults(file_path)
    -- Load current defaults
    local defaults = DefaultPatterns.LoadDefaults()
    
    -- If no defaults found, create empty structure
    if not defaults then
        defaults = {
            default_patterns = {},
            default_groups = {}
        }
    end
    
    -- Encode to JSON
    local content = json.encode(defaults)
    
    -- Save to file
    local file = io.open(file_path, "w")
    
    if not file then
        reaper.ShowMessageBox("Could not write to file: " .. file_path, "Export Error", 0)
        return
    end
    
    file:write(content)
    file:close()
    
    reaper.ShowMessageBox("Defaults exported successfully!", "Export Complete", 0)
end

-- Function to import specific pattern categories
function ImportExport.ImportSpecificPatterns(file_path, ext_state_name, selected_categories)
    local file = io.open(file_path, "r")
    
    if not file then
        reaper.ShowMessageBox("Could not open file: " .. file_path, "Import Error", 0)
        return false
    end
    
    local content = file:read("*all")
    file:close()
    
    local ok, data = pcall(json.decode, content)
    
    if not ok or not data then
        reaper.ShowMessageBox("Invalid JSON file: " .. file_path, "Import Error", 0)
        return false
    end
    
    -- Check if the file has global_patterns data
    if not data.global_patterns then
        reaper.ShowMessageBox("The selected file does not contain pattern data.", "Import Error", 0)
        return false
    end
    
    -- Get current global patterns
    local global_patterns_json = reaper.GetExtState(ext_state_name, "global_patterns")
    local global_patterns = {}
    
    if global_patterns_json ~= "" then
        local ok, parsed = pcall(json.decode, global_patterns_json)
        if ok and parsed then
            global_patterns = parsed
        end
    end
    
    -- Import only selected categories
    local categories_updated = 0
    for _, category in ipairs(selected_categories) do
        if data.global_patterns[category] then
            global_patterns[category] = data.global_patterns[category]
            categories_updated = categories_updated + 1
        end
    end
    
    -- Save updated global patterns
    if categories_updated > 0 then
        local global_patterns_str = json.encode(global_patterns)
        reaper.SetExtState(ext_state_name, "global_patterns", global_patterns_str, true)
        reaper.ShowMessageBox(string.format("Successfully imported %d pattern categories!", categories_updated), "Import Complete", 0)
        return true
    else
        reaper.ShowMessageBox("No matching pattern categories found in the import file.", "Import Notice", 0)
        return false
    end
end

-- Function to export specific pattern categories
function ImportExport.ExportSpecificPatterns(file_path, ext_state_name, selected_categories)
    -- Get current global patterns
    local global_patterns_json = reaper.GetExtState(ext_state_name, "global_patterns")
    local global_patterns = {}
    
    if global_patterns_json ~= "" then
        local ok, parsed = pcall(json.decode, global_patterns_json)
        if ok and parsed then
            global_patterns = parsed
        end
    end
    
    -- Create a new object with only the selected categories
    local export_patterns = {}
    local categories_exported = 0
    
    for _, category in ipairs(selected_categories) do
        if global_patterns[category] then
            export_patterns[category] = global_patterns[category]
            categories_exported = categories_exported + 1
        end
    end
    
    if categories_exported == 0 then
        reaper.ShowMessageBox("No pattern categories selected for export.", "Export Notice", 0)
        return false
    end
    
    -- Create export data
    local export_data = {
        global_patterns = export_patterns
    }
    
    -- Encode to JSON
    local content = json.encode(export_data)
    
    -- Save to file
    local file = io.open(file_path, "w")
    
    if not file then
        reaper.ShowMessageBox("Could not write to file: " .. file_path, "Export Error", 0)
        return false
    end
    
    file:write(content)
    file:close()
    
    reaper.ShowMessageBox(string.format("Successfully exported %d pattern categories!", categories_exported), "Export Complete", 0)
    return true
end

return ImportExport 