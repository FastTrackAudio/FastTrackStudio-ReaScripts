-- @version 1.4.9
-- @author Daniel Lumertz
-- @license MIT
-- @provides
--    [nomain] utils/*.lua
--    [nomain] Chunk Functions.lua
--    [main] Delete Snapshots on Project.lua
--    [nomain] General Functions.lua
--    [nomain] GUI Functions.lua
--    [nomain] Serialize Table.lua
--    [nomain] Track Snapshot Functions.lua
--    [nomain] Track Snapshot Send Functions.lua
--    [nomain] theme.lua
--    [nomain] Style Editor.lua
--    [nomain] REAPER Functions.lua
-- @changelog
--    + Correct Checkers

--dofile("C:/Users/DSL/AppData/Roaming/REAPER/Scripts/Meus/Debug VS/DL Debug.lua")

ScriptName = "Visibility Manager" -- Use to call Extstate dont change
ScriptVersion = "1.0.0"

local info = debug.getinfo(1, "S")
script_path = info.source:match([[^@?(.*[\/])[^\/]-$]])
configs_filename = "configs" -- Json ScriptName

dofile(script_path .. "Serialize Table.lua") -- preset to work with Tables
dofile(script_path .. "Track Parameter Functions.lua") -- Functions for track parameters
dofile(script_path .. "Track Snapshot Functions.lua") -- Functions to this script
dofile(script_path .. "General Functions.lua") -- General Functions needed
dofile(script_path .. "GUI Functions.lua") -- General Functions needed
dofile(script_path .. "Chunk Functions.lua") -- General Functions needed
dofile(script_path .. "theme.lua") -- General Functions needed
dofile(script_path .. "Track Snapshot Send Functions.lua") -- General Functions needed
dofile(script_path .. "REAPER Functions.lua") -- preset to work with Tables

if not CheckSWS() or not CheckReaImGUI() or not CheckJS() then
	return
end
-- Imgui shims to 0.7.2 (added after the news at 0.8)
dofile(reaper.GetResourcePath() .. "/Scripts/ReaTeam Extensions/API/imgui.lua")("0.7.2")

--dofile(script_path .. 'Style Editor.lua') -- Remember to remove

--- configs
Configs = {}
Configs.ShowAll = false
Configs.ViewMode = "Toggle" -- Can be "Toggle", "Exclusive", or "LimitedExclusive"

function GuiInit()
	ctx = reaper.ImGui_CreateContext("Track Snapshot", reaper.ImGui_ConfigFlags_DockingEnable())
	FONT = reaper.ImGui_CreateFont("sans-serif", 15) -- Create the fonts you need
	font_mini = reaper.ImGui_CreateFont("sans-serif", 13) -- Create the fonts you need
	reaper.ImGui_AttachFont(ctx, FONT) -- Attach the fonts you need
	reaper.ImGui_AttachFont(ctx, font_mini) -- Attach the fonts you need
end

function Init()
	Snapshot = LoadSnapshot()
	Configs = LoadConfigs()
	GuiInit()
end

function loop()
	if not PreventPassKeys then -- Passthrough keys
		PassThorugh()
	end

	PushTheme() -- Theme
	--StyleLoop()
	--PushStyle()
	CheckProjChange()

	local window_flags = reaper.ImGui_WindowFlags_MenuBar()
	reaper.ImGui_SetNextWindowSize(ctx, 500, 420, reaper.ImGui_Cond_Once()) -- Set the size of the windows.  Use in the 4th argument reaper.ImGui_Cond_FirstUseEver() to just apply at the first user run, so ImGUI remembers user resize s2
	reaper.ImGui_PushFont(ctx, FONT) -- Says you want to start using a specific font

	if SetDock then
		reaper.ImGui_SetNextWindowDockID(ctx, SetDock)
		if SetDock == 0 then
			reaper.ImGui_SetNextWindowSize(ctx, 200, 420)
		end
		SetDock = nil
	end

	local visible, open = reaper.ImGui_Begin(ctx, ScriptName .. " " .. ScriptVersion, true, window_flags)

	if visible then
		-------
		--MENU
		-------
		if reaper.ImGui_BeginMenuBar(ctx) then
			ConfigsMenu()
			AboutMenu()
			DockBtn()
			if Configs.VersionMode then
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4848FF)
				reaper.ImGui_Text(ctx, "V.")
				reaper.ImGui_PopStyleColor(ctx, 1)
				if Configs.ToolTips then
					ToolTip("Track Version Mode ON")
				end
			end
			reaper.ImGui_EndMenuBar(ctx)
		end

		--------
		-- GUI Body
		--------
		GuiLoadChunkOption()

		-- New Group button
		if reaper.ImGui_Button(ctx, 'New Group', -1) then
			TempNewGroupPopup = true
			TempNewGroupName = ""
		end
		if Configs.ToolTips then ToolTip("Create a new group") end

		-- Display groups and their snapshots
		if reaper.ImGui_BeginListBox(ctx, '##grouplist', -1, -1) then
			-- Get window width for responsive layout
			local windowWidth = reaper.ImGui_GetWindowContentRegionMax(ctx)
			-- Calculate column positions and widths (60% for group name, 20% each for TCP/MCP)
			local tcpX = windowWidth * 0.6
			local mcpX = windowWidth * 0.8
			local minGroupWidth = 100  -- Minimum width for group title
			local groupWidth = math.max(tcpX - 8, minGroupWidth)  -- Ensure group width doesn't go below minimum
			
			-- Adjust TCP position if group width hits minimum
			local actualTcpX = math.max(tcpX, minGroupWidth + 8)  -- Ensure TCP doesn't overlap with minimum group width
			local buttonWidth = (windowWidth * 0.2) - 8  -- Adjust button width
			local iconSize = 16  -- Size of icons
			local fixedIconWidth = 24  -- Fixed width for icon-only mode
			local minTextIconWidth = 80  -- Minimum width when showing text + icon
			
			-- Column headers
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "Group")
			reaper.ImGui_EndGroup(ctx)
			
			-- Calculate center positions for T and M headers
			local tWidth = reaper.ImGui_CalcTextSize(ctx, "T")
			local mWidth = reaper.ImGui_CalcTextSize(ctx, "M")
			local tcpHeaderX = actualTcpX + fixedIconWidth - 20 + (fixedIconWidth - tWidth) / 2
			local mcpHeaderX = actualTcpX + (fixedIconWidth * 2) - 12 + (fixedIconWidth - mWidth) / 2
			
			reaper.ImGui_SameLine(ctx, tcpHeaderX)  -- Center T header
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "T")
			reaper.ImGui_EndGroup(ctx)
			
			reaper.ImGui_SameLine(ctx, mcpHeaderX)  -- Center M header
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "M")
			reaper.ImGui_EndGroup(ctx)
			
			reaper.ImGui_Separator(ctx)
			
			-- List groups
			for _, group in ipairs(Configs.Groups) do
				-- First column: Group name with active state
				reaper.ImGui_BeginGroup(ctx)
				
				-- Create an invisible button to limit the clickable area
				local buttonColor = group.color or 0x4444FFFF
				if group.active and not group.isGlobal then
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local buttonPosX, buttonPosY = reaper.ImGui_GetCursorScreenPos(ctx)
					-- Extend the highlight to the full window width
					local windowWidth = reaper.ImGui_GetWindowContentRegionMax(ctx)
					reaper.ImGui_DrawList_AddRectFilled(drawList, buttonPosX, buttonPosY, buttonPosX + windowWidth, buttonPosY + 20, buttonColor)
				end
				
				reaper.ImGui_InvisibleButton(ctx, "##spacer" .. group.name, groupWidth, 20)
				local isHovered = reaper.ImGui_IsItemHovered(ctx)
				local isClicked = reaper.ImGui_IsItemClicked(ctx)
				
				-- Draw hover highlight first
				if isHovered and not group.active then
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local rectMinX, rectMinY = reaper.ImGui_GetItemRectMin(ctx)
					local _, rectMaxY = reaper.ImGui_GetItemRectMax(ctx)
					local windowWidth = reaper.ImGui_GetWindowContentRegionMax(ctx)
					reaper.ImGui_DrawList_AddRectFilled(drawList, rectMinX, rectMinY, rectMinX + windowWidth, rectMaxY, 0x3F3F3FFF)
				end
				
				-- Draw momentary highlight for global groups when clicked
				if group.isGlobal and isHovered and reaper.ImGui_IsMouseDown(ctx, 0) then
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local rectMinX, rectMinY = reaper.ImGui_GetItemRectMin(ctx)
					local _, rectMaxY = reaper.ImGui_GetItemRectMax(ctx)
					local windowWidth = reaper.ImGui_GetWindowContentRegionMax(ctx)
					reaper.ImGui_DrawList_AddRectFilled(drawList, rectMinX, rectMinY, rectMinX + windowWidth, rectMaxY, buttonColor)
				end
				
				-- Draw the text and icon
				local drawList = reaper.ImGui_GetWindowDrawList(ctx)
				local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
				local textColor = group.active and 0xFFFFFFFF or 0xBBBBBBFF
				
				-- Draw icon if exists
				local textOffset = 4
				if group.icon and group.icon ~= "" then
					local icon = LoadIcon(group.icon)
					if SafeDrawIcon(icon, posX + 4, posY + 2, iconSize) then
						textOffset = iconSize + 8
					end
				end
				
				-- Draw text
				if isHovered then
					textColor = 0xFFFFFFFF
				end
				reaper.ImGui_DrawList_AddText(drawList, posX + textOffset, posY + 2, textColor, group.name)
				
				-- Right-click menu for group
				if reaper.ImGui_BeginPopupContextItem(ctx, "##group_context" .. group.name) then
					if reaper.ImGui_MenuItem(ctx, "Set Icon") then
						-- Open icon selector
						OpenIconSelector(group)
					end
					if reaper.ImGui_MenuItem(ctx, "Reset Icon") then
						group.icon = ""
						SaveConfig()
					end
					reaper.ImGui_Separator(ctx)
					
					-- Color picker directly in the menu
					OpenColorPicker(group)
					ColorPickerPopup()
					
					if reaper.ImGui_MenuItem(ctx, "Reset Color") then
						group.color = 0x4444FFFF  -- Reset to default blue
						SaveConfig()
					end
					reaper.ImGui_Separator(ctx)
					
					-- Add Rename Group option
					if reaper.ImGui_MenuItem(ctx, "Rename Group") then
						TempRenameGroupPopup = true
						TempRenameGroupName = group.name
						TempRenameGroupTarget = group
						TempPopup_i = "RenameGroup"
					end
					
					-- Add new menu item for adding selected tracks to group scope
					if reaper.ImGui_MenuItem(ctx, "Add Selected Tracks to Group Scope") then
						local numAdded = AddSelectedTracksToGroupScope(group.name)
						if numAdded > 0 then
							print(string.format("\nAdded %d track(s) to group scope for '%s'", numAdded, group.name))
						else
							print("\nNo new tracks were added to group scope")
						end
					end
					
					-- Add Move Up/Down options
					reaper.ImGui_Separator(ctx)
					
					-- Find the current group index
					local currentIndex = 1
					for i, g in ipairs(Configs.Groups) do
						if g.name == group.name then
							currentIndex = i
							break
						end
					end
					
					-- Move Up option (disabled if already at the top)
					if currentIndex > 1 then
						if reaper.ImGui_MenuItem(ctx, "Move Up") then
							-- Swap with the group above
							Configs.Groups[currentIndex], Configs.Groups[currentIndex-1] = Configs.Groups[currentIndex-1], Configs.Groups[currentIndex]
							SaveConfig()
						end
					else
						reaper.ImGui_BeginDisabled(ctx)
						reaper.ImGui_MenuItem(ctx, "Move Up")
						reaper.ImGui_EndDisabled(ctx)
					end
					
					-- Move Down option (disabled if already at the bottom)
					if currentIndex < #Configs.Groups then
						if reaper.ImGui_MenuItem(ctx, "Move Down") then
							-- Swap with the group below
							Configs.Groups[currentIndex], Configs.Groups[currentIndex+1] = Configs.Groups[currentIndex+1], Configs.Groups[currentIndex]
							SaveConfig()
						end
					else
						reaper.ImGui_BeginDisabled(ctx)
						reaper.ImGui_MenuItem(ctx, "Move Down")
						reaper.ImGui_EndDisabled(ctx)
					end
					
					reaper.ImGui_Separator(ctx)
					
					if reaper.ImGui_MenuItem(ctx, 'Delete Group') then
						if reaper.ShowMessageBox("Are you sure you want to delete the group '" .. group.name .. "' and all its snapshots?", "Delete Group", 4) == 6 then
							DeleteGroup(group.name)
							-- Delete associated snapshots
							local i = 1
							while i <= #Snapshot do
								if Snapshot[i].Group == group.name then
									table.remove(Snapshot, i)
								else
									i = i + 1
								end
							end
							SaveSnapshotConfig()
						end
					end
					reaper.ImGui_EndPopup(ctx)
				end
				
				if isClicked then
					-- Check if shift is held down
					local isShiftHeld = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
					
					if isShiftHeld then
						-- If shift is held, force exclusive mode regardless of config
						-- First deactivate all groups
						for _, otherGroup in ipairs(Configs.Groups) do
							if otherGroup ~= group then
								otherGroup.active = false
							end
						end
						
						-- If the group was already active, deactivate it first
						if group.active then
							group.active = false
							HandleGroupActivation(group)
						end
						
						-- Then activate the clicked group
						group.active = true
						
						-- Temporarily save the current view mode
						local originalViewMode = Configs.ViewMode
						
						-- Force exclusive mode for this activation
						Configs.ViewMode = "Exclusive"
						
						-- Activate the group with exclusive mode
						HandleGroupActivation(group)
						
						-- Restore the original view mode
						Configs.ViewMode = originalViewMode
					else
						-- For global groups, always activate without toggling
						if group.isGlobal then
							group.active = true
							HandleGlobalGroupActivation(group)
						else
							-- Normal toggle behavior for non-global groups
							group.active = not group.active
							HandleGroupActivation(group)
						end
					end
					SaveConfig()
				end
				reaper.ImGui_EndGroup(ctx)
				
				-- TCP snapshots column
				reaper.ImGui_SameLine(ctx, actualTcpX + fixedIconWidth - 20)  -- Use adjusted TCP position
				reaper.ImGui_BeginGroup(ctx)
				local tcpColor = group.active and buttonColor or 0x444444FF
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), tcpColor)
				
				-- Push style vars for combo box height and padding
				reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 2, 2)
				reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 4)

				-- Get snapshots for this group and TCP
				local tcpSnapshots = {}
				for i, snapshot in ipairs(Snapshot) do
					if snapshot.Group == group.name and snapshot.SubGroup == "TCP" then
						table.insert(tcpSnapshots, {index = i, snapshot = snapshot})
					end
				end
				
				-- Show selected snapshot name or count
				local tcpPreviewValue = "TCP"
				if group.selectedTCP then
					tcpPreviewValue = group.selectedTCP
				elseif #tcpSnapshots > 0 then
					tcpPreviewValue = #tcpSnapshots .. " TCP"
				end
				
				-- Calculate available width for preview
				local previewWidth = buttonWidth
				local textWidth = reaper.ImGui_CalcTextSize(ctx, tcpPreviewValue)
				-- Switch to icon-only if we can't fit the full text properly
				local showIconOnly = previewWidth < minTextIconWidth
				
				-- Find selected snapshot and its icon
				local selectedSnapshot = nil
				if group.selectedTCP then
					for _, item in ipairs(tcpSnapshots) do
						if item.snapshot.Name == group.selectedTCP then
							selectedSnapshot = item.snapshot
							break
						end
					end
				end
				
				-- Set the actual combo width - fixed width when showing icon only
				local comboWidth = showIconOnly and fixedIconWidth or math.max(buttonWidth, minTextIconWidth)
				reaper.ImGui_PushItemWidth(ctx, comboWidth)

				-- Add padding to preview text if we have an icon, or empty string if showing icon only
				local paddedPreviewValue = tcpPreviewValue
				if selectedSnapshot and selectedSnapshot.icon and selectedSnapshot.icon ~= "" then
					if showIconOnly then
						paddedPreviewValue = ""  -- Show only icon
					else
						paddedPreviewValue = "    " .. tcpPreviewValue  -- Add space for icon
					end
				elseif showIconOnly then
					-- If no icon but in icon mode, show first letter
					paddedPreviewValue = ""  -- Clear text since we'll draw it manually
				end
				
				-- Start the combo with the preview
				if reaper.ImGui_BeginCombo(ctx, "##tcp" .. group.name, paddedPreviewValue, reaper.ImGui_ComboFlags_NoArrowButton()) then
					reaper.ImGui_SetNextWindowPos(ctx, tcpX - 4, reaper.ImGui_GetCursorScreenPos(ctx), reaper.ImGui_Cond_Always())
					-- List existing snapshots
					for _, item in ipairs(tcpSnapshots) do
						local snapshot = item.snapshot
						local label = snapshot.Name
						
						-- Draw snapshot with icon if it exists
						if snapshot.icon and snapshot.icon ~= "" then
							local icon = LoadIcon(snapshot.icon)
							if icon then
								local cursorX, cursorY = reaper.ImGui_GetCursorScreenPos(ctx)
								SafeDrawIcon(icon, cursorX, cursorY + 2, iconSize)
								reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + iconSize + 4)
							end
						end
						
						if reaper.ImGui_Selectable(ctx, label, group.selectedTCP == snapshot.Name) then
							group.selectedTCP = snapshot.Name
							SaveConfig()
							-- Use the appropriate activation function based on group type
							if group.isGlobal then
								HandleGlobalGroupActivation(group)
							else
								HandleGroupActivation(group)
							end
						end
						
						-- Right-click menu for snapshot
						if reaper.ImGui_BeginPopupContextItem(ctx, "##snapshot" .. item.index) then
							if reaper.ImGui_MenuItem(ctx, "Set Icon") then
								OpenIconSelector(snapshot)
							end
							if reaper.ImGui_MenuItem(ctx, "Reset Icon") then
								snapshot.icon = ""
								SaveSnapshotConfig()
							end
							if reaper.ImGui_MenuItem(ctx, "Load") then
								group.selectedTCP = snapshot.Name
								SaveConfig()
								-- Use the appropriate activation function based on group type
								if group.isGlobal then
									HandleGlobalGroupActivation(group)
								else
									HandleGroupActivation(group)
								end
							end
							if reaper.ImGui_MenuItem(ctx, "Update Snapshot") then
								OverwriteSnapshot(snapshot.Name)
							end
							if reaper.ImGui_MenuItem(ctx, "Delete") then
								if group.selectedTCP == snapshot.Name then
									group.selectedTCP = nil
								end
								DeleteSnapshot(item.index)
								SaveConfig()
							end
							reaper.ImGui_EndPopup(ctx)
						end
					end

					reaper.ImGui_Separator(ctx)
					
					-- Save New option
					if reaper.ImGui_Selectable(ctx, "Save New TCP Snapshot") then
						TempPopup_i = "NewSnapshotName"
						TempPopupData = {group = group.name, subgroup = "TCP"}
						TempNewSnapshotName = ""
					end
					
					reaper.ImGui_EndCombo(ctx)
				end

				-- Draw the preview content over the combo
				if selectedSnapshot then
					if selectedSnapshot.icon and selectedSnapshot.icon ~= "" then
						local icon = LoadIcon(selectedSnapshot.icon)
						if icon then
							local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
							if not SafeDrawIcon(icon, lastX + 4, lastY + 2, iconSize) then
								-- Fallback to first letter if icon fails
								local firstLetter = (selectedSnapshot.Name or "T"):sub(1,1):upper()
								local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, firstLetter)) / 2
								local letterY = lastY + 2
								reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xFFFFFFFF, firstLetter)
							end
						end
					elseif showIconOnly then
						-- Draw first letter in place of icon
						local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
						local drawList = reaper.ImGui_GetWindowDrawList(ctx)
						local firstLetter = (selectedSnapshot.Name or "T"):sub(1,1):upper()
						local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, firstLetter)) / 2
						local letterY = lastY + 2
						reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xFFFFFFFF, firstLetter)
					end
					
					if showIconOnly then
						if reaper.ImGui_IsItemHovered(ctx) then
							reaper.ImGui_BeginTooltip(ctx)
							reaper.ImGui_Text(ctx, tcpPreviewValue)
							reaper.ImGui_EndTooltip(ctx)
						end
					end
				elseif showIconOnly then
					-- Draw "T" for empty TCP
					local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local letter = "T"
					local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, letter)) / 2
					local letterY = lastY + 2
					reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xBBBBBBFF, letter)
				end

				reaper.ImGui_PopStyleVar(ctx, 2)  -- Pop frame padding and item spacing
				reaper.ImGui_PopStyleColor(ctx)
				reaper.ImGui_PopItemWidth(ctx)
				reaper.ImGui_EndGroup(ctx)
				
				-- MCP snapshots column
				reaper.ImGui_SameLine(ctx, actualTcpX + (fixedIconWidth * 2) - 12)  -- Use adjusted TCP position
				reaper.ImGui_BeginGroup(ctx)
				local mcpColor = group.active and buttonColor or 0x444444FF
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), mcpColor)
				
				-- Push style vars for combo box height and padding
				reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 2, 2)
				reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 4)

				-- Get snapshots for this group and MCP
				local mcpSnapshots = {}
				for i, snapshot in ipairs(Snapshot) do
					if snapshot.Group == group.name and snapshot.SubGroup == "MCP" then
						table.insert(mcpSnapshots, {index = i, snapshot = snapshot})
					end
				end
				
				-- Show selected snapshot name or count
				local mcpPreviewValue = "MCP"
				if group.selectedMCP then
					mcpPreviewValue = group.selectedMCP
				elseif #mcpSnapshots > 0 then
					mcpPreviewValue = #mcpSnapshots .. " MCP"
				end
				
				-- Calculate available width for preview
				local previewWidth = buttonWidth
				local textWidth = reaper.ImGui_CalcTextSize(ctx, mcpPreviewValue)
				-- Switch to icon-only if we can't fit the full text properly
				local showIconOnly = previewWidth < minTextIconWidth
				
				-- Find selected snapshot and its icon
				local selectedSnapshot = nil
				if group.selectedMCP then
					for _, item in ipairs(mcpSnapshots) do
						if item.snapshot.Name == group.selectedMCP then
							selectedSnapshot = item.snapshot
							break
						end
					end
				end
				
				-- Set the actual combo width - fixed width when showing icon only
				local comboWidth = showIconOnly and fixedIconWidth or math.max(buttonWidth, minTextIconWidth)
				reaper.ImGui_PushItemWidth(ctx, comboWidth)

				-- Add padding to preview text if we have an icon, or empty string if showing icon only
				local paddedPreviewValue = mcpPreviewValue
				if selectedSnapshot and selectedSnapshot.icon and selectedSnapshot.icon ~= "" then
					if showIconOnly then
						paddedPreviewValue = ""  -- Show only icon
					else
						paddedPreviewValue = "    " .. mcpPreviewValue  -- Add space for icon
					end
				elseif showIconOnly then
					-- If no icon but in icon mode, show first letter
					paddedPreviewValue = ""  -- Clear text since we'll draw it manually
				end
				
				if reaper.ImGui_BeginCombo(ctx, "##mcp" .. group.name, paddedPreviewValue, reaper.ImGui_ComboFlags_NoArrowButton()) then
					reaper.ImGui_SetNextWindowPos(ctx, mcpX - 4, reaper.ImGui_GetCursorScreenPos(ctx), reaper.ImGui_Cond_Always())
					-- List existing snapshots
					for _, item in ipairs(mcpSnapshots) do
						local snapshot = item.snapshot
						local label = snapshot.Name
						
						-- Draw snapshot with icon if it exists
						if snapshot.icon and snapshot.icon ~= "" then
							local icon = LoadIcon(snapshot.icon)
							if icon then
								local cursorX, cursorY = reaper.ImGui_GetCursorScreenPos(ctx)
								SafeDrawIcon(icon, cursorX, cursorY + 2, iconSize)
								reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + iconSize + 4)
							end
						end
						
						if reaper.ImGui_Selectable(ctx, label, group.selectedMCP == snapshot.Name) then
							group.selectedMCP = snapshot.Name
							SaveConfig()
							-- Use the appropriate activation function based on group type
							if group.isGlobal then
								HandleGlobalGroupActivation(group)
							else
								HandleGroupActivation(group)
							end
						end
						
						-- Right-click menu for snapshot
						if reaper.ImGui_BeginPopupContextItem(ctx, "##snapshot" .. item.index) then
							if reaper.ImGui_MenuItem(ctx, "Set Icon") then
								OpenIconSelector(snapshot)
							end
							if reaper.ImGui_MenuItem(ctx, "Reset Icon") then
								snapshot.icon = ""
								SaveSnapshotConfig()
							end
							if reaper.ImGui_MenuItem(ctx, "Load") then
								group.selectedMCP = snapshot.Name
								SaveConfig()
								-- Use the appropriate activation function based on group type
								if group.isGlobal then
									HandleGlobalGroupActivation(group)
								else
									HandleGroupActivation(group)
								end
							end
							if reaper.ImGui_MenuItem(ctx, "Update Snapshot") then
								OverwriteSnapshot(snapshot.Name)
							end
							if reaper.ImGui_MenuItem(ctx, "Delete") then
								if group.selectedMCP == snapshot.Name then
									group.selectedMCP = nil
								end
								DeleteSnapshot(item.index)
								SaveConfig()
							end
							reaper.ImGui_EndPopup(ctx)
						end
					end

					reaper.ImGui_Separator(ctx)
					
					-- Save New option
					if reaper.ImGui_Selectable(ctx, "Save New MCP Snapshot") then
						TempPopup_i = "NewSnapshotName"
						TempPopupData = {group = group.name, subgroup = "MCP"}
						TempNewSnapshotName = ""
					end
					
					reaper.ImGui_EndCombo(ctx)
				end

				-- Draw the preview content over the combo
				if selectedSnapshot then
					if selectedSnapshot.icon and selectedSnapshot.icon ~= "" then
						local icon = LoadIcon(selectedSnapshot.icon)
						if icon then
							local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
							if not SafeDrawIcon(icon, lastX + 4, lastY + 2, iconSize) then
								-- Fallback to first letter if icon fails
								local firstLetter = (selectedSnapshot.Name or "M"):sub(1,1):upper()
								local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, firstLetter)) / 2
								local letterY = lastY + 2
								reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xFFFFFFFF, firstLetter)
							end
						end
					elseif showIconOnly then
						-- Draw first letter in place of icon
						local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
						local drawList = reaper.ImGui_GetWindowDrawList(ctx)
						local firstLetter = (selectedSnapshot.Name or "M"):sub(1,1):upper()
						local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, firstLetter)) / 2
						local letterY = lastY + 2
						reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xFFFFFFFF, firstLetter)
					end
					
					if showIconOnly then
						if reaper.ImGui_IsItemHovered(ctx) then
							reaper.ImGui_BeginTooltip(ctx)
							reaper.ImGui_Text(ctx, mcpPreviewValue)
							reaper.ImGui_EndTooltip(ctx)
						end
					end
				elseif showIconOnly then
					-- Draw "M" for empty MCP
					local lastX, lastY = reaper.ImGui_GetItemRectMin(ctx)
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local letter = "M"
					local letterX = lastX + (fixedIconWidth - reaper.ImGui_CalcTextSize(ctx, letter)) / 2
					local letterY = lastY + 2
					reaper.ImGui_DrawList_AddText(drawList, letterX, letterY, 0xBBBBBBFF, letter)
				end

				reaper.ImGui_PopStyleVar(ctx, 2)  -- Pop frame padding and item spacing
				reaper.ImGui_PopStyleColor(ctx)
				reaper.ImGui_PopItemWidth(ctx)
				reaper.ImGui_EndGroup(ctx)
			end
			reaper.ImGui_EndListBox(ctx)
		end

		OpenPopups(TempPopup_i)
		NewGroupPopup()
		IconSelectorPopup()
		--------
		reaper.ImGui_End(ctx)
	end
	--PopStyle()
	PopTheme()

	reaper.ImGui_PopFont(ctx) -- Pop Font

	if open and reaper.ImGui_IsKeyPressed(ctx, 27) == false then
		reaper.defer(loop)
	else
		reaper.ImGui_DestroyContext(ctx)
	end
end

function NewSnapshotNamePopup()
	if TempPopup_i ~= "NewSnapshotName" then return end

	-- Set popup position first time it runs 
	if TempRename_x then
		reaper.ImGui_SetNextWindowPos(ctx, TempRename_x-125, TempRename_y-30)
		TempRename_x = nil
		TempRename_y = nil
	end

	if reaper.ImGui_BeginPopupModal(ctx, 'New Snapshot Name###NewSnapshotPopup', nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
		-- Colors
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x2E2E2EFF)
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0xC8C8C83A)
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), 0x68C5FE66)

		--Body
		if reaper.ImGui_IsWindowAppearing(ctx) then -- First Run
			reaper.ImGui_SetKeyboardFocusHere(ctx)
			TempRename_x, TempRename_y = reaper.GetMousePosition()
		end
		
		local rv, name = reaper.ImGui_InputText(ctx, "##NewName", TempNewSnapshotName, reaper.ImGui_InputTextFlags_AutoSelectAll())
		if rv then 
			TempNewSnapshotName = name
		end
		
		if reaper.ImGui_Button(ctx, 'Save', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
			if TempNewSnapshotName ~= "" then
				-- Set the current group to the one from TempPopupData
				Configs.CurrentGroup = TempPopupData.group
				
				-- Find the target group
				local targetGroup = nil
				for _, group in ipairs(Configs.Groups) do
					if group.name == TempPopupData.group then
						targetGroup = group
						break
					end
				end
				
				-- Call the appropriate snapshot function based on group type and subgroup
				if targetGroup and targetGroup.isGlobal then
					-- For global snapshots, use the dedicated function
					local success, message = SaveGlobalSnapshot()
					if not success then
						reaper.ShowMessageBox(message, "Error", 0)
					end
				elseif TempPopupData.subgroup == "TCP" then
					SaveTCPSnapshot()
				else
					SaveMCPSnapshot()
				end
				
				CloseForcePreventShortcuts()
				TempPopup_i = nil
				reaper.ImGui_CloseCurrentPopup(ctx)
			end
		end
		
		reaper.ImGui_SameLine(ctx)
		if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
			CloseForcePreventShortcuts()
			TempPopup_i = nil
			reaper.ImGui_CloseCurrentPopup(ctx)
		end

		--End
		reaper.ImGui_PopStyleColor(ctx, 3)
		reaper.ImGui_EndPopup(ctx)
	end    
end

function OpenPopups(popup_i)
	if popup_i then
		if popup_i == "NewSnapshotName" then
			BeginForcePreventShortcuts()
			reaper.ImGui_OpenPopup(ctx, 'New Snapshot Name###NewSnapshotPopup')
		elseif popup_i == "RenameGroup" then
			BeginForcePreventShortcuts()
			reaper.ImGui_OpenPopup(ctx, 'Rename Group###RenameGroupPopup')
			if reaper.ImGui_IsWindowAppearing(ctx) then
				TempRename_x, TempRename_y = reaper.GetMousePosition()
			end
		end
		NewSnapshotNamePopup()
		RenameGroupPopup()
	end
end

function BeginForcePreventShortcuts()
	TempPreventShortCut = Configs.PreventShortcut
	Configs.PreventShortcut = true
	PreventPassKeys = true
end

function CloseForcePreventShortcuts()
	Configs.PreventShortcut = TempPreventShortCut
	TempPreventShortCut = nil
	PreventPassKeys = nil
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
		if reaper.ImGui_MenuItem(ctx, 'Debug Mode') then
			Configs.DebugMode = not Configs.DebugMode
			SaveConfig()
		end
		if reaper.ImGui_MenuItem(ctx, 'Create Global Snapshot') then
			-- Find or create a global group
			local globalGroup = nil
			for _, group in ipairs(Configs.Groups) do
				if group.isGlobal then
					globalGroup = group
					break
				end
			end
			
			if not globalGroup then
				-- Create a new global group at the top
				table.insert(Configs.Groups, 1, {
					name = "Global View",
					active = false,
					color = 0x4444FFFF,  -- Default blue color
					icon = "",  -- No icon by default
					selectedTCP = nil,
					selectedMCP = nil,
					subGroups = {
						TCP = {},
						MCP = {}
					},
					isGlobal = true  -- Flag to identify this as a global group
				})
				globalGroup = Configs.Groups[1]
				SaveConfig()
			end
			
			TempPopup_i = "NewSnapshotName"
			TempPopupData = {group = globalGroup.name, subgroup = "TCP"}
			TempNewSnapshotName = ""
		end
		reaper.ImGui_Separator(ctx)
		
		-- View Mode submenu
		if reaper.ImGui_BeginMenu(ctx, 'View Mode') then
			if reaper.ImGui_MenuItem(ctx, 'Toggle Mode', nil, Configs.ViewMode == "Toggle") then
				Configs.ViewMode = "Toggle"
				SaveConfig()
			end
			if reaper.ImGui_MenuItem(ctx, 'Exclusive Mode', nil, Configs.ViewMode == "Exclusive") then
				Configs.ViewMode = "Exclusive"
				SaveConfig()
			end
			if reaper.ImGui_MenuItem(ctx, 'Limited Exclusive Mode', nil, Configs.ViewMode == "LimitedExclusive") then
				Configs.ViewMode = "LimitedExclusive"
				SaveConfig()
			end
			reaper.ImGui_EndMenu(ctx)
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

function HandleGroupActivation(group)
	DebugPrint("\n=== HandleGroupActivation Debug ===")
	local start_time = reaper.time_precise()
	
	-- Prevent UI updates and undo points for the entire operation
	reaper.PreventUIRefresh(1)
	reaper.Undo_BeginBlock()
	
	-- Save current selection state once at the beginning
	reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_SAVESEL"), 0)
	
	-- Get parent track once at the beginning and cache it
	local parentTrack = GetParentTrackOfGroup(group)
	local parentTracks = {}
	if parentTrack then
		parentTracks = GetParentTracks(parentTrack)
	end
	
	-- Handle deactivation first
	if not group.active then
		local hide_start = reaper.time_precise()
		HideGroupTracks(group)
		DebugPrint(string.format("HideGroupTracks took %.3f ms", (reaper.time_precise() - hide_start) * 1000))
		
		DebugPrint(string.format("Total deactivation took %.3f ms", (reaper.time_precise() - start_time) * 1000))
		DebugPrint("=== End HandleGroupActivation Debug ===\n")
		return
	end
	
	-- Handle activation based on view mode
	if Configs.ViewMode == "Toggle" then
		-- Show tracks
		local show_start = reaper.time_precise()
		ShowGroupTracks(group)
		DebugPrint(string.format("ShowGroupTracks took %.3f ms", (reaper.time_precise() - show_start) * 1000))
	elseif Configs.ViewMode == "Exclusive" then
		-- Hide all tracks first
		local hide_start = reaper.time_precise()
		HideAllTracks()
		DebugPrint(string.format("HideAllTracks took %.3f ms", (reaper.time_precise() - hide_start) * 1000))
		
		-- Deactivate all other groups
		for _, otherGroup in ipairs(Configs.Groups) do
			if otherGroup ~= group then
				otherGroup.active = false
			end
		end
		
		-- Show tracks for active group
		local show_start = reaper.time_precise()
		ShowGroupTracks(group)
		DebugPrint(string.format("ShowGroupTracks took %.3f ms", (reaper.time_precise() - show_start) * 1000))
	elseif Configs.ViewMode == "LimitedExclusive" then
		-- Deactivate all other groups
		for _, otherGroup in ipairs(Configs.Groups) do
			if otherGroup ~= group then
				otherGroup.active = false
			end
		end
		
		-- Set all tracks to minimum height
		local height_start = reaper.time_precise()
		local allTracks = {}
		for i = 0, reaper.CountTracks(0) - 1 do
			table.insert(allTracks, reaper.GetTrack(0, i))
		end
		ShowTracksMinimumHeight(allTracks)
		DebugPrint(string.format("ShowTracksMinimumHeight took %.3f ms", (reaper.time_precise() - height_start) * 1000))
		
		-- Collapse all top-level tracks
		local collapse_start = reaper.time_precise()
		CollapseTopLevelTracks()
		DebugPrint(string.format("CollapseTopLevelTracks took %.3f ms", (reaper.time_precise() - collapse_start) * 1000))
		
		-- Get the parent track of the group
		if parentTrack then
			DebugPrint("Found group parent track")
			
			-- Get all parent tracks of the parent track
			DebugPrint("Found", #parentTracks, "additional parent tracks")
			
			-- Unfold all parent tracks in the hierarchy
			for _, track in ipairs(parentTracks) do
				local _, track_name = reaper.GetTrackName(track)
				DebugPrint("Unfolding parent track:", track_name)
				reaper.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)  -- 0 = unfolded
			end
			
			-- Also unfold the immediate parent track
			DebugPrint("Unfolding immediate parent track")
			reaper.SetMediaTrackInfo_Value(parentTrack, "I_FOLDERCOMPACT", 0)
			
			-- Deselect all tracks and select only the parent
			reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
			reaper.SetTrackSelected(parentTrack, true)
			
			-- Scroll MCP and TCP to show the parent track
			reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS7fb3d74a01cfeae229ad75b83192ca5086acbdbd"), 0) -- Scroll MCP to first selected track
			reaper.Main_OnCommand(reaper.NamedCommandLookup("_RS9d2de0644134078c900c5baf59a2e900f1fe0c55"), 0) -- Scroll TCP vertically to first selected track
		end
	end
	
	-- Apply snapshots only once at the end, after all track operations are complete
	local snapshot_start = reaper.time_precise()
	ApplyGroupSnapshots(group)
	DebugPrint(string.format("ApplyGroupSnapshots took %.3f ms", (reaper.time_precise() - snapshot_start) * 1000))
	
	-- Restore original track selection ONCE at the end
	reaper.Main_OnCommand(reaper.NamedCommandLookup("_SWS_RESTORESEL"), 0)
	
	-- Force REAPER to refresh all layouts
	reaper.ThemeLayout_RefreshAll()
	
	DebugPrint(string.format("Total activation took %.3f ms", (reaper.time_precise() - start_time) * 1000))
	DebugPrint("=== End HandleGroupActivation Debug ===\n")
end

function RenameGroupPopup()
	if not TempRenameGroupPopup then return end

	-- Set popup position first time it runs 
	if TempRename_x then
		reaper.ImGui_SetNextWindowPos(ctx, TempRename_x-125, TempRename_y-30)
	end

	local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
	if reaper.ImGui_BeginPopupModal(ctx, "Rename Group###RenameGroupPopup", nil, popup_flags) then
		-- Colors
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),        0x2E2E2EFF)
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0xC8C8C83A)
		reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextSelectedBg(), 0x68C5FE66)

		-- Body
		if reaper.ImGui_IsWindowAppearing(ctx) then -- First Run
			reaper.ImGui_SetKeyboardFocusHere(ctx)
		end

		reaper.ImGui_Text(ctx, "Enter new group name:")
		reaper.ImGui_PushItemWidth(ctx, 280)
		local rv, temp = reaper.ImGui_InputText(ctx, "##newgroupname", TempRenameGroupName, reaper.ImGui_InputTextFlags_AutoSelectAll())
		if rv then TempRenameGroupName = temp end
		reaper.ImGui_PopItemWidth(ctx)
		
		if reaper.ImGui_Button(ctx, 'Save', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
			if TempRenameGroupName and TempRenameGroupName ~= "" then
				-- Check if the new name already exists
				local nameExists = false
				for _, group in ipairs(Configs.Groups) do
					if group.name == TempRenameGroupName and group ~= TempRenameGroupTarget then
						nameExists = true
						break
					end
				end
				
				if not nameExists then
					-- Update group name
					local oldName = TempRenameGroupTarget.name
					TempRenameGroupTarget.name = TempRenameGroupName
					
					-- Update snapshots that reference this group
					for _, snapshot in ipairs(Snapshot) do
						if snapshot.Group == oldName then
							snapshot.Group = TempRenameGroupName
						end
					end
					
					-- Update current group if it was the renamed one
					if Configs.CurrentGroup == oldName then
						Configs.CurrentGroup = TempRenameGroupName
					end
					
					-- Save changes
					SaveConfig()
					SaveSnapshotConfig()
					
					-- Close popup
					TempRenameGroupName = nil
					TempRenameGroupTarget = nil
					TempRenameGroupPopup = nil
					TempPopup_i = nil
					TempRename_x = nil
					TempRename_y = nil
					CloseForcePreventShortcuts()
					reaper.ImGui_CloseCurrentPopup(ctx)
				else
					reaper.ShowMessageBox("A group with this name already exists.", "Error", 0)
				end
			end
		end
		
		reaper.ImGui_SameLine(ctx)
		if reaper.ImGui_Button(ctx, 'Cancel', 120, 0) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
			TempRenameGroupName = nil
			TempRenameGroupTarget = nil
			TempRenameGroupPopup = nil
			TempPopup_i = nil
			TempRename_x = nil
			TempRename_y = nil
			CloseForcePreventShortcuts()
			reaper.ImGui_CloseCurrentPopup(ctx)
		end

		reaper.ImGui_PopStyleColor(ctx, 3)
		reaper.ImGui_EndPopup(ctx)
	end
end

Init()
loop()
reaper.atexit(SaveSnapshotConfig)
