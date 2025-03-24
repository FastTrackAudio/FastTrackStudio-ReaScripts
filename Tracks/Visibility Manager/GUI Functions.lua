-- @noindex
function DrawRectLastItem(r,g,b,a)
    local minx, miny = reaper.ImGui_GetItemRectMin(ctx)
    local maxx, maxy = reaper.ImGui_GetItemRectMax(ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    --local color =  reaper.ImGui_ColorConvertRGBtoHSV( r,  g,  b,  a )
    local color =  rgba2num(r,  g,  b,  a)
    
    reaper.ImGui_DrawList_AddRectFilled(draw_list, minx-50, miny, maxx, maxy, color)
end

function WriteShortkey(key, r,g,b,a)
    local minx, miny = reaper.ImGui_GetItemRectMin(ctx)
    local maxx, maxy = reaper.ImGui_GetItemRectMax(ctx)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local color =  rgba2num(r,  g,  b,  a)
    local text_w, text_h = reaper.ImGui_CalcTextSize(ctx, key, 1, 1)
    local pad = 5
    reaper.ImGui_DrawList_AddText(draw_list, maxx-text_w-pad, miny, color, key)    
end

function SoloSelect(i_solo) -- list:list \n solo_key:string or number
    for i, v in pairs(Snapshot) do
        if i_solo ~= i and TableValuesCompareNoOrder(Snapshot[i].Tracks,Snapshot[i_solo].Tracks) then -- Check if is the same group of tracks
            Snapshot[i].Selected = false
        end       
    end
    Snapshot[i_solo].Selected = true
end

function rgba2num(red, green, blue, alpha)

	local blue = blue * 256
	local green = green * 256 * 256
	local red = red * 256 * 256 * 256
	
	return red + green + blue + alpha
end

function ResetStyleCount()
    reaper.ImGui_PopStyleColor(ctx,CounterStyle) -- Reset The Styles (NEED FOR IMGUI TO WORK)
    CounterStyle = 0
end

function HSV(h, s, v, a)
    local r, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    return reaper.ImGui_ColorConvertDouble4ToU32(r, g, b, a or 1.0)
end

function ChangeColor(H,S,V,A)
    reaper.ImGui_PushID(ctx, 3)
    local button = HSV( H, S, V, A)
    local hover =  HSV( H, S , (V+0.4 < 1) and V+0.4 or 1 , A)
    local active = HSV( H, S, (V+0.2 < 1) and V+0.2 or 1 , A)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),  button)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),  active)
end

function ChangeColorText(H,S,V,A)
    local textcolor = HSV( H, S, V, A)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),  textcolor)
end

function ToolTip(text)
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_BeginTooltip(ctx)
        reaper.ImGui_PushTextWrapPos(ctx, reaper.ImGui_GetFontSize(ctx) * 35.0)
        reaper.ImGui_PushTextWrapPos(ctx, 200)
        reaper.ImGui_Text(ctx, text)
        reaper.ImGui_PopTextWrapPos(ctx)
        reaper.ImGui_EndTooltip(ctx)
    end
end

function BeginForcePreventShortcuts() --Change and Store Configs.PreventShortcut
    TempPreventShortCut = Configs.PreventShortcut
    Configs.PreventShortcut = true
    PreventPassKeys = true
end

function CloseForcePreventShortcuts() -- Restore Configs.PreventShortcut configs
    Configs.PreventShortcut = TempPreventShortCut
    TempPreventShortCut = nil
    PreventPassKeys = nil
end

function RenamePopup(i)
    -- Set Rename Popup Position first time it runs 
    if TempRename_x then
        reaper.ImGui_SetNextWindowPos(ctx, TempRename_x-125, TempRename_y-30)
        TempRename_x = nil
        TempRename_y = nil
    end

    if reaper.ImGui_BeginPopupModal(ctx, 'Rename###RenamePopup', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        -- Colors
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x2E2E2EFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0xC8C8C83A)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), 0x68C5FE66)

        --Body
        if reaper.ImGui_IsWindowAppearing(ctx) then -- First Run
            reaper.ImGui_SetKeyboardFocusHere(ctx)
            TempRename_x, TempRename_y = reaper.GetMousePosition()
            local guid
        end
        
        _, Snapshot[i].Name = reaper.ImGui_InputText(ctx, "##Rename"..i, Snapshot[i].Name, reaper.ImGui_InputTextFlags_AutoSelectAll())
        
        if reaper.ImGui_Button(ctx, 'Close', -1) or reaper.ImGui_IsKeyDown(ctx, 13) then
            if Snapshot[i].Name == '' then Snapshot[i].Name = 'Snapshot '..i end -- If Name == '' Is difficult to see in the GUI
            if Snapshot[i].Name == 'Stevie' then PrintStevie() end -- =)
            SaveSnapshotConfig() 
            CloseForcePreventShortcuts()
            TempPopup_i = nil
            reaper.ImGui_CloseCurrentPopup(ctx) 
        end
        --End
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_EndPopup(ctx)
    end    
end

function OpenPopups(i) -- Need This function to be called outside a menu (else it wouldnt run the popup every loop)... i =  TempPopup_i. Need to TempPopup_i = nil when closing a popup. TempPopup_i = Snaphot[i] that called a popup rename/shortcut
    if i then
        if TempRenamePopup then
            BeginForcePreventShortcuts()
            reaper.ImGui_OpenPopup(ctx, 'Rename###RenamePopup')
            TempRenamePopup = nil
        end
        RenamePopup(i)

        if TempLearnPopup then
            BeginForcePreventShortcuts()
            reaper.ImGui_OpenPopup(ctx, 'Learn')
            TempLearnPopup = nil
        end
        LearnWindow(i)
    end
end

function SnapshotRightClickPopUp(i)
    if reaper.ImGui_BeginPopupContextItem(ctx, "##snapshot" .. i) then
        if reaper.ImGui_MenuItem(ctx, 'Load Snapshot') then
            SetSnapshot(i)
        end
        if reaper.ImGui_MenuItem(ctx, 'Load Snapshot in New Tracks') then
            SetSnapshotInNewTracks(i)
        end
        if reaper.ImGui_MenuItem(ctx, 'Select Tracks') then
            SelectSnapshotTracks(i)
        end
        if reaper.ImGui_MenuItem(ctx, 'Rename') then
            TempRenamePopup = true
            TempPopup_i = i
        end
        if reaper.ImGui_MenuItem(ctx, 'Delete') then
            DeleteSnapshot(i)
        end
        if Snapshot[i].MissTrack then
            if reaper.ImGui_MenuItem(ctx, 'Show Missing Tracks') then
                ShowMissingTracks(i)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

function LearnWindow(i)
    if TempLearn_x then
        reaper.ImGui_SetNextWindowPos(ctx, TempLearn_x-50, TempLearn_y-30)
        TempLearn_x = nil
        TempLearn_y = nil
    end

    if reaper.ImGui_BeginPopupModal(ctx, 'Learn', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        -- First run
        if reaper.ImGui_IsWindowAppearing(ctx) then -- First Run
            TempLearn_x, TempLearn_y = reaper.GetMousePosition()
        end

        reaper.ImGui_Text(ctx, 'Key: '..(Snapshot[i].Shortcut or ''))
        

        for char, keycode in pairs(KeyCodeList()) do
            if reaper.ImGui_IsKeyReleased(ctx, keycode) then
                local check = true
                -- Check if Key is already used
                for check_i, value in pairs(Snapshot) do 
                    if  Snapshot[check_i].Shortcut == char then
                        check = false
                    end
                end
                
                if check then 
                    Snapshot[i].Shortcut = char
                    CloseForcePreventShortcuts()
                    TempPopup_i = nil
                    SaveSnapshotConfig()
                    reaper.ImGui_CloseCurrentPopup(ctx)
                else -- Key Clicked is in Use
                    print('Key Already Used In Snapshot')
                end
            end
        end

        if reaper.ImGui_Button(ctx, 'REMOVE', 120, 0) then 
            Snapshot[i].Shortcut = false
            CloseForcePreventShortcuts()
            TempPopup_i = nil
            SaveSnapshotConfig() 
            reaper.ImGui_CloseCurrentPopup(ctx) 
        end
        reaper.ImGui_EndPopup(ctx)
    end
end


function GuiLoadChunkOption()
    if reaper.ImGui_TreeNode(ctx, 'Load Snapshot Options') then
        if Configs.ToolTips then ToolTip("Filter Things To Be Loaded") end

        reaper.ImGui_PushFont(ctx, font_mini)
        reaper.ImGui_PushItemWidth(ctx, 100)

        if reaper.ImGui_Checkbox(ctx, 'Load All', Configs.Chunk.All) then
            Configs.Chunk.All = not Configs.Chunk.All
            SaveConfig() 
        end

        if not Configs.Chunk.All then 
            reaper.ImGui_Separator(ctx)

            if reaper.ImGui_Checkbox(ctx, 'Items', Configs.Chunk.Items) then
                Configs.Chunk.Items = not Configs.Chunk.Items
                SaveConfig() 
            end
            if reaper.ImGui_Checkbox(ctx, 'FX', Configs.Chunk.Fx) then
                Configs.Chunk.Fx = not Configs.Chunk.Fx
                SaveConfig() 
            end

            -- Visibility Options
            if reaper.ImGui_Checkbox(ctx, 'Visibility', Configs.Chunk.Vis.Bool) then
                Configs.Chunk.Vis.Bool = not Configs.Chunk.Vis.Bool
                SaveConfig() 
            end

            -- Right Click Visibility Options
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x464646FF)
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                -- Only show options that are properly defined in the VisOptions table
                for i = 1, #Configs.Chunk.Vis.Options do
                    local option = Configs.Chunk.Vis.Options[i]
                    if option and option.Name and option.ChunkKey then
                        if reaper.ImGui_Checkbox(ctx, option.Name, option.Bool) then
                            option.Bool = not option.Bool
                            Configs.Chunk.Vis.Bool = true -- Enable visibility options when any option is checked
                            SaveConfig()
                        end
                    end
                end
                reaper.ImGui_EndPopup(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)

            -- if reaper.ImGui_Checkbox(ctx, 'Track Envelopes', Configs.Chunk.Env.Bool) then
            --     Configs.Chunk.Env.Bool = not Configs.Chunk.Env.Bool
            --     SaveConfig() 
            -- end

            -- -- Right Click Track Envelopes
            -- reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x464646FF)
            -- if reaper.ImGui_BeginPopupContextItem(ctx) then
            --     for i, value in pairs(Configs.Chunk.Env.Envelope) do
            --         if reaper.ImGui_Checkbox(ctx, Configs.Chunk.Env.Envelope[i].Name, Configs.Chunk.Env.Envelope[i].Bool) then
            --             Configs.Chunk.Env.Envelope[i].Bool = not Configs.Chunk.Env.Envelope[i].Bool
            --             SaveConfig()
            --         end
            --     end
            --     reaper.ImGui_EndPopup(ctx)
            -- end
            -- reaper.ImGui_PopStyleColor(ctx)

            -- if reaper.ImGui_Checkbox(ctx, 'Sends', Configs.Chunk.Sends) then
            --     Configs.Chunk.Sends = not Configs.Chunk.Sends
            --     SaveConfig() 
            -- end

            -- if reaper.ImGui_Checkbox(ctx, 'Receives', Configs.Chunk.Receive) then
            --     Configs.Chunk.Receive = not Configs.Chunk.Receive
            --     SaveConfig() 
            -- end

            if Configs.ToolTips then ToolTip("Right Click For More Options") end

            reaper.ImGui_Spacing(ctx)

            for key, value in pairs(Configs.Chunk.Misc) do
                if reaper.ImGui_Checkbox(ctx, value.Name, value.Bool) then
                    value.Bool = not value.Bool
                    SaveConfig()
                end
            end
        end

        reaper.ImGui_PopItemWidth(ctx)
        reaper.ImGui_PopFont(ctx)
        reaper.ImGui_TreePop(ctx)
    end
end

function PassThorughOld() -- Actions to pass keys though GUI to REAPER. Find a better way
    if reaper.ImGui_IsKeyPressed(ctx, 32, false) then-- Space
        
        reaper.Main_OnCommand(40044, 0) -- Transport: Play/stop
    end

    local ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_ModCtrl())
    local shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_ModShift())

    if ctrl and shift then 
        if reaper.ImGui_IsKeyPressed(ctx, 90, false) then-- z
            reaper.Main_OnCommand(40030, 0) -- Edit: Redo
        end
    elseif ctrl then 
        if reaper.ImGui_IsKeyPressed(ctx, 90, false) then-- z
            reaper.Main_OnCommand(40029, 0) -- Edit: Undo
        end
    end
end

function FilterPassThorugh(key_name)
    for i,v in pairs(Snapshot) do 
        if Snapshot[i].Shortcut == key_name then return true end
    end
    return false
end


function PassThorugh() -- Might be a little tough on resource
    --Get keys pressed
    local keycodes = KeyCodeList()
    local active_keys = {}
    for key_name, key_val in pairs(keycodes) do
        if FilterPassThorugh(key_name) then goto continue end 
        if reaper.ImGui_IsKeyPressed(ctx, key_val, true) then -- true so holding will perform many times
            active_keys[#active_keys+1] = key_val
        end
        ::continue::
    end

    -- mods
    local mods = reaper.ImGui_GetKeyMods(ctx)
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_ModCtrl()) then active_keys[#active_keys+1] = 17 end -- ctrl
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_ModShift()) then active_keys[#active_keys+1] = 16 end -- Shift
    if reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_ModAlt()) then active_keys[#active_keys+1] = 18 end -- Alt (NOT WORKING)


    --Send Message
    if LastWindowFocus then 
        if #active_keys > 0  then
            for k, key_val in pairs(active_keys) do
                PostKey(LastWindowFocus, key_val)
            end
        end
    end

    -- Get focus window (if not == Script Title)
    local win_focus = reaper.JS_Window_GetFocus()
    local win_name = reaper.JS_Window_GetTitle( win_focus )

    if LastWindowFocus ~= win_focus and (win_name == 'trackview' or win_name == 'midiview')  then -- focused win title is different from script title? INSERT HERE HOW YOU NAME THE SCRIPT
        LastWindowFocus = win_focus
    end    
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
        if reaper.ImGui_MenuItem(ctx, 'Exclusive Mode', nil, Configs.ExclusiveMode) then
            Configs.ExclusiveMode = not Configs.ExclusiveMode
            SaveConfig()
        end
        reaper.ImGui_Separator(ctx)
        
        -- Group Management
        if reaper.ImGui_BeginMenu(ctx, 'Groups') then
            -- Create New Group
            if reaper.ImGui_MenuItem(ctx, 'Create New Group') then
                TempPopup_i = 'NewGroup'
            end
            
            -- Delete All Groups option
            if reaper.ImGui_MenuItem(ctx, 'Delete All Groups') then
                if reaper.ShowMessageBox("This will delete all groups (except Default) and their snapshots. This action cannot be undone. Continue?", "Delete All Groups", 4) == 6 then
                    DeleteAllGroups()
                end
            end
            
            -- List existing groups
            if Configs.Groups then
                reaper.ImGui_Separator(ctx)
                for _, group in ipairs(Configs.Groups) do
                    -- Ensure subGroups exists
                    if not group.subGroups then
                        group.subGroups = {
                            TCP = {},
                            MCP = {}
                        }
                    end
                    
                    local isSelected = Configs.CurrentGroup == group.name
                    if reaper.ImGui_MenuItem(ctx, group.name, isSelected and "✓" or "") then
                        Configs.CurrentGroup = group.name
                        Configs.CurrentSubGroup = "TCP" -- Reset sub-group when changing groups
                        SaveConfig()
                    end
                    
                    -- Add delete option for each group
                    if reaper.ImGui_SmallButton(ctx, "X##" .. group.name) then
                        DeleteGroup(group.name)
                    end
                    
                    -- Show sub-groups if this is the current group
                    if isSelected then
                        reaper.ImGui_Indent(ctx, 20)
                        for subGroupName, _ in pairs(group.subGroups) do
                            local isSubSelected = Configs.CurrentSubGroup == subGroupName
                            if reaper.ImGui_MenuItem(ctx, subGroupName, isSubSelected and "✓" or "") then
                                Configs.CurrentSubGroup = subGroupName
                                SaveConfig()
                            end
                        end
                        reaper.ImGui_Unindent(ctx, 20)
                    end
                end
            end
            
            reaper.ImGui_EndMenu(ctx)
        end
        
        if reaper.ImGui_MenuItem(ctx, 'Refresh Configs') then
            RefreshConfigs()
        end
        reaper.ImGui_EndMenu(ctx)
    end
end

function AboutMenu()
    if reaper.ImGui_BeginMenu(ctx, 'About') then

        if reaper.ImGui_MenuItem(ctx, 'Donate!') then
            open_url('https://www.paypal.com/donate/?hosted_button_id=RWA58GZTYMZ3N')
        end

        if reaper.ImGui_MenuItem(ctx, 'Forum Thread') then
            open_url('https://forum.cockos.com/showthread.php?t=264124')
        end

        if reaper.ImGui_MenuItem(ctx, 'Video') then
            open_url('https://youtu.be/-y8TsehRYzo')
        end
        reaper.ImGui_EndMenu(ctx)

    end
end

function DockBtn()
    local reval_dock =  reaper.ImGui_IsWindowDocked(ctx)
    local dock_text =  reval_dock and  'Undock' or 'Dock'

    if reaper.ImGui_MenuItem(ctx,dock_text ) then
        if reval_dock then -- Already Docked
            SetDock = 0
        else -- Not docked
            SetDock = -3 -- Dock to the right 
        end
    end
end

-- Add new popup for creating groups
function NewGroupPopup()
    if TempNewGroupPopup then
        BeginForcePreventShortcuts()
        reaper.ImGui_OpenPopup(ctx, "New Group")
        TempNewGroupPopup = nil
    end

    local popup_name = "New Group"
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
    reaper.ImGui_SetNextWindowSize(ctx, 300, 200, reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_BeginPopupModal(ctx, popup_name, popup_flags)
    
    if visible then
        reaper.ImGui_Text(ctx, "Enter group name:")
        reaper.ImGui_PushItemWidth(ctx, 280)
        local rv, temp = reaper.ImGui_InputText(ctx, "##newgroupname", TempNewGroupName or "")
        if rv then TempNewGroupName = temp end
        reaper.ImGui_PopItemWidth(ctx)
        
        -- Get the selected track's name and show it in muted text
        local selectedTrack = reaper.GetSelectedTrack(0, 0)
        local trackName = "No track selected"
        if selectedTrack then
            _, trackName = reaper.GetTrackName(selectedTrack)
        end
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)  -- Muted gray color
        reaper.ImGui_Text(ctx, "Parent Track: " .. trackName)
        reaper.ImGui_PopStyleColor(ctx)
        
        reaper.ImGui_Separator(ctx)
        
        -- Center the buttons
        local buttonWidth = 100
        local windowWidth = reaper.ImGui_GetWindowWidth(ctx)
        local centerX = (windowWidth - (buttonWidth * 2 + 10)) / 2  -- 10 is spacing between buttons
        reaper.ImGui_SetCursorPosX(ctx, centerX)
        
        if reaper.ImGui_Button(ctx, "Create", buttonWidth) then
            if TempNewGroupName and TempNewGroupName ~= '' then
                local success, message = CreateGroup(TempNewGroupName)
                if success then
                    TempNewGroupName = nil
                    CloseForcePreventShortcuts()
                    reaper.ImGui_CloseCurrentPopup(ctx)
                else
                    print(message)
                end
            end
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Cancel", buttonWidth) then
            TempNewGroupName = nil
            CloseForcePreventShortcuts()
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        -- Handle Enter key
        if reaper.ImGui_IsKeyPressed(ctx, 13) then  -- 13 is the key code for Enter
            if TempNewGroupName and TempNewGroupName ~= '' then
                local success, message = CreateGroup(TempNewGroupName)
                if success then
                    TempNewGroupName = nil
                    CloseForcePreventShortcuts()
                    reaper.ImGui_CloseCurrentPopup(ctx)
                else
                    print(message)
                end
            end
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- Global variables for icon selector
local ICON_SELECTOR = {
    isOpen = false,
    searchText = "",
    currentTarget = nil,
    icons = {},
    categories = {},
    selectedCategory = "All Icons",
    iconSize = 32,
    windowSize = {500, 500},
    colors = {
        winBg = 0x282828ff,
        sidebarCol = 0x2c2c2cff,
        hoverCol = 0x3c6191ff,
        outlineCol = 0xffcb40ff,
        textActive = 0xf1f2f2ff,
        textInactive = 0x999B9Fff
    }
}

-- Global icon cache
local ICON_CACHE = {}

-- Function to load and cache icons
function LoadIcon(path)
    if not path or path == "" then return nil end
    
    -- Initialize cache if needed
    if not ICON_CACHE then ICON_CACHE = {} end
    
    -- Check if icon is already cached and valid
    if ICON_CACHE[path] then
        if reaper.ImGui_ValidatePtr(ICON_CACHE[path], 'ImGui_Image*') then
            return ICON_CACHE[path]
        else
            -- Remove invalid cached icon
            ICON_CACHE[path] = nil
        end
    end
    
    -- Load new icon
    local success, icon = pcall(reaper.ImGui_CreateImage, path)
    if success and icon and reaper.ImGui_ValidatePtr(icon, 'ImGui_Image*') then
        ICON_CACHE[path] = icon
        return icon
    end
    
    return nil
end

function SafeDrawIcon(icon, x, y, size)
    if not icon then return false end
    
    -- Validate icon pointer
    if not reaper.ImGui_ValidatePtr(icon, 'ImGui_Image*') then
        return false
    end
    
    -- Safely draw the icon
    local success, _ = pcall(function()
        local drawList = reaper.ImGui_GetWindowDrawList(ctx)
        reaper.ImGui_DrawList_AddImage(drawList, icon, x, y, x + size, y + size)
    end)
    
    return success
end

function SafeImageButton(label, icon, size_x, size_y)
    if not icon or not reaper.ImGui_ValidatePtr(icon, 'ImGui_Image*') then
        return false
    end
    
    local success, clicked = pcall(reaper.ImGui_ImageButton, ctx, label, icon, size_x, size_y)
    return success and clicked or false
end

function LoadIcons()
    if #ICON_SELECTOR.icons == 0 then
        local reaper_path = reaper.GetResourcePath()
        local icons_path = reaper_path .. "/Data/track_icons"
        ICON_SELECTOR.icons = {}
        ICON_SELECTOR.categories = {["All Icons"] = {}}
        
        -- Function to scan directory recursively
        local function scanDirectory(path, category)
            for i = 0, math.huge do
                local file = reaper.EnumerateFiles(path, i)
                if not file then break end
                if file:match("%.png$") or file:match("%.jpg$") or file:match("%.jpeg$") then
                    local fullPath = path .. "/" .. file
                    local icon = {
                        path = fullPath,
                        name = file,
                        texture = reaper.ImGui_CreateImage(fullPath)
                    }
                    table.insert(ICON_SELECTOR.icons, icon)
                    table.insert(ICON_SELECTOR.categories["All Icons"], icon)
                    if category then
                        if not ICON_SELECTOR.categories[category] then
                            ICON_SELECTOR.categories[category] = {}
                        end
                        table.insert(ICON_SELECTOR.categories[category], icon)
                    end
                end
            end
            
            -- Scan subdirectories
            for i = 0, math.huge do
                local dir = reaper.EnumerateSubdirectories(path, i)
                if not dir then break end
                scanDirectory(path .. "/" .. dir, dir)
            end
        end
        
        scanDirectory(icons_path)
    end
end

function OpenIconSelector(target)
    ICON_SELECTOR.isOpen = true
    ICON_SELECTOR.currentTarget = target
    ICON_SELECTOR.searchText = ""
    LoadIcons()
end

function IconSelectorPopup()
    if not ICON_SELECTOR.isOpen then return end
    
    reaper.ImGui_SetNextWindowSize(ctx, ICON_SELECTOR.windowSize[1], ICON_SELECTOR.windowSize[2], reaper.ImGui_Cond_FirstUseEver())
    local visible, open = reaper.ImGui_Begin(ctx, 'Icon Selector##popup', true, reaper.ImGui_WindowFlags_NoCollapse())
    ICON_SELECTOR.isOpen = open
    
    if visible then
        -- Left sidebar with categories
        reaper.ImGui_BeginChild(ctx, "Categories", 150, 0, true)
        for category in pairs(ICON_SELECTOR.categories) do
            if reaper.ImGui_Selectable(ctx, category, ICON_SELECTOR.selectedCategory == category) then
                ICON_SELECTOR.selectedCategory = category
            end
        end
        reaper.ImGui_EndChild(ctx)
        
        reaper.ImGui_SameLine(ctx)
        
        -- Right panel with search and icons
        reaper.ImGui_BeginChild(ctx, "Icons", 0, 0, true)
        
        -- Search bar
        local changed, newText = reaper.ImGui_InputText(ctx, "Search", ICON_SELECTOR.searchText)
        if changed then
            ICON_SELECTOR.searchText = newText
        end
        
        -- Icons grid
        local availWidth = reaper.ImGui_GetContentRegionAvail(ctx)
        local iconsPerRow = math.floor(availWidth / (ICON_SELECTOR.iconSize + 8))
        if iconsPerRow < 1 then iconsPerRow = 1 end
        
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 8)
        
        local currentCategory = ICON_SELECTOR.categories[ICON_SELECTOR.selectedCategory] or {}
        for i, icon in ipairs(currentCategory) do
            if ICON_SELECTOR.searchText == "" or icon.name:lower():find(ICON_SELECTOR.searchText:lower()) then
                if i > 1 then
                    local col = (i - 1) % iconsPerRow
                    if col > 0 then reaper.ImGui_SameLine(ctx) end
                end
                
                if SafeImageButton("##" .. icon.path, icon.texture, ICON_SELECTOR.iconSize, ICON_SELECTOR.iconSize) then
                    if ICON_SELECTOR.currentTarget then
                        ICON_SELECTOR.currentTarget.icon = icon.path
                        SaveConfig()
                    end
                    ICON_SELECTOR.isOpen = false
                end
                
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_BeginTooltip(ctx)
                    reaper.ImGui_Text(ctx, icon.name)
                    reaper.ImGui_EndTooltip(ctx)
                end
            end
        end
        
        reaper.ImGui_PopStyleVar(ctx)
        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_End(ctx)
end

-- Global variables for color picker
local COLOR_PICKER = {
    currentTarget = nil,
    currentColor = 0x4444FFFF  -- Default blue color
}

function OpenColorPicker(target)
    COLOR_PICKER.currentTarget = target
    COLOR_PICKER.currentColor = target.color or 0x4444FFFF
end

function ColorPickerPopup()
    if not COLOR_PICKER.currentTarget then return end
    
    -- Color picker directly in the context menu
    local changed, newColor = reaper.ImGui_ColorEdit4(ctx, "##color_picker", COLOR_PICKER.currentColor, reaper.ImGui_ColorEditFlags_AlphaBar())
    if changed then
        COLOR_PICKER.currentTarget.color = newColor
        SaveConfig()
    end
end

