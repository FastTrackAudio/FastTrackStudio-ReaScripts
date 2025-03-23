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
			-- Column headers
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "Group")
			reaper.ImGui_EndGroup(ctx)
			
			reaper.ImGui_SameLine(ctx, 300)
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "TCP")
			reaper.ImGui_EndGroup(ctx)
			
			reaper.ImGui_SameLine(ctx, 400)
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Text(ctx, "MCP")
			reaper.ImGui_EndGroup(ctx)
			
			reaper.ImGui_Separator(ctx)
			
			-- Calculate width for selectable area
			local groupWidth = 280  -- Width of the Group column
			
			-- List groups
			for _, group in ipairs(Configs.Groups) do
				-- First column: Group name with active state
				reaper.ImGui_BeginGroup(ctx)
				
				-- Create an invisible button to limit the clickable area
				local buttonColor = nil
				if group.active then
					buttonColor = 0x4444FFFF  -- Bright blue for active groups
				end
				
				if buttonColor then
					local drawList = reaper.ImGui_GetWindowDrawList(ctx)
					local buttonPosX, buttonPosY = reaper.ImGui_GetCursorScreenPos(ctx)
					reaper.ImGui_DrawList_AddRectFilled(drawList, buttonPosX, buttonPosY, buttonPosX + groupWidth, buttonPosY + 20, buttonColor)
				end
				
				reaper.ImGui_InvisibleButton(ctx, "##spacer" .. group.name, groupWidth, 20)
				local isHovered = reaper.ImGui_IsItemHovered(ctx)
				local isClicked = reaper.ImGui_IsItemClicked(ctx)
				
				-- Draw the text over the invisible button
				local drawList = reaper.ImGui_GetWindowDrawList(ctx)
				local posX, posY = reaper.ImGui_GetItemRectMin(ctx)
				local textColor = group.active and 0xFFFFFFFF or 0xBBBBBBFF
				if isHovered then
					textColor = 0xFFFFFFFF
					-- Draw hover highlight only if not active
					if not group.active then
						local rectMinX, rectMinY = reaper.ImGui_GetItemRectMin(ctx)
						local rectMaxX, rectMaxY = reaper.ImGui_GetItemRectMax(ctx)
						reaper.ImGui_DrawList_AddRectFilled(drawList, rectMinX, rectMinY, rectMaxX, rectMaxY, 0x3F3F3FFF)
					end
				end
				reaper.ImGui_DrawList_AddText(drawList, posX + 4, posY + 2, textColor, group.name)
				
				if isClicked then
					-- Regular click toggles active state
					if Configs.ExclusiveMode then
						-- In exclusive mode, deactivate all other groups first
						for _, otherGroup in ipairs(Configs.Groups) do
							if otherGroup ~= group then
								if otherGroup.active then
									otherGroup.active = false
									HideGroupTracks(otherGroup)
								end
							end
						end
						group.active = true
						HandleGroupActivation(group)
					else
						-- In non-exclusive mode, just toggle the current group
						group.active = not group.active
						HandleGroupActivation(group)
					end
					-- Always update current group selection
					Configs.CurrentGroup = group.name
					SaveConfig()
				end
				reaper.ImGui_EndGroup(ctx)
				
				-- Second column: TCP snapshots
				reaper.ImGui_SameLine(ctx, 300)
				reaper.ImGui_BeginGroup(ctx)
				reaper.ImGui_PushItemWidth(ctx, 80)
				local tcpColor = group.active and 0x4444FFFF or 0x444444FF
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), tcpColor)
				
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
				
				if reaper.ImGui_BeginCombo(ctx, "##tcp" .. group.name, tcpPreviewValue) then
					-- List existing snapshots first
					for _, item in ipairs(tcpSnapshots) do
						local snapshot = item.snapshot
						local label = snapshot.Name
						if snapshot.Mode then
							label = label .. " (" .. snapshot.Mode .. ")"
						end
						if reaper.ImGui_Selectable(ctx, label, group.selectedTCP == snapshot.Name) then
							print("\n=== TCP Dropdown Selection ===")
							print("Group:", group.name)
							print("Selected snapshot:", snapshot.Name)
							print("Snapshot index:", item.index)
							group.selectedTCP = snapshot.Name
							SaveConfig()
							SoloSelect(item.index)
							SetSnapshotFiltered(item.index, "TCP")
						end
						
						if reaper.ImGui_BeginPopupContextItem(ctx, "##snapshot" .. item.index) then
							if reaper.ImGui_MenuItem(ctx, "Load") then
								SetSnapshotFiltered(item.index, "TCP")
								group.selectedTCP = snapshot.Name
								SaveConfig()
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
						TempPopup_i = "NewSnapshot"
						TempPopupData = {group = group.name, subgroup = "TCP"}
						SaveSnapshot()  -- Call SaveSnapshot directly
					end
					
					-- Overwrite menu
					if reaper.ImGui_BeginMenu(ctx, "Overwrite Snapshot") then
						for _, item in ipairs(tcpSnapshots) do
							local snapshot = item.snapshot
							local label = snapshot.Name
							if snapshot.Mode then
								label = label .. " (" .. snapshot.Mode .. ")"
							end
							if reaper.ImGui_MenuItem(ctx, label) then
								OverwriteSnapshot(snapshot.Name)
							end
						end
						reaper.ImGui_EndMenu(ctx)
					end
					
					reaper.ImGui_EndCombo(ctx)
				end
				reaper.ImGui_PopStyleColor(ctx)
				reaper.ImGui_PopItemWidth(ctx)
				reaper.ImGui_EndGroup(ctx)
				
				-- Third column: MCP snapshots
				reaper.ImGui_SameLine(ctx, 400)
				reaper.ImGui_BeginGroup(ctx)
				reaper.ImGui_PushItemWidth(ctx, 80)
				local mcpColor = group.active and 0x4444FFFF or 0x444444FF
				reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), mcpColor)
				
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
				
				if reaper.ImGui_BeginCombo(ctx, "##mcp" .. group.name, mcpPreviewValue) then
					-- List existing snapshots first
					for _, item in ipairs(mcpSnapshots) do
						local snapshot = item.snapshot
						local label = snapshot.Name
						if snapshot.Mode then
							label = label .. " (" .. snapshot.Mode .. ")"
						end
						if reaper.ImGui_Selectable(ctx, label, group.selectedMCP == snapshot.Name) then
							print("\n=== MCP Dropdown Selection ===")
							print("Group:", group.name)
							print("Selected snapshot:", snapshot.Name)
							print("Snapshot index:", item.index)
							group.selectedMCP = snapshot.Name
							SaveConfig()
							SoloSelect(item.index)
							SetSnapshotFiltered(item.index, "MCP")
						end
						
						if reaper.ImGui_BeginPopupContextItem(ctx, "##snapshot" .. item.index) then
							if reaper.ImGui_MenuItem(ctx, "Load") then
								SetSnapshotFiltered(item.index, "MCP")
								group.selectedMCP = snapshot.Name
								SaveConfig()
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
						TempPopup_i = "NewSnapshot"
						TempPopupData = {group = group.name, subgroup = "MCP"}
						SaveSnapshot()  -- Call SaveSnapshot directly
					end
					
					-- Overwrite menu
					if reaper.ImGui_BeginMenu(ctx, "Overwrite Snapshot") then
						for _, item in ipairs(mcpSnapshots) do
							local snapshot = item.snapshot
							local label = snapshot.Name
							if snapshot.Mode then
								label = label .. " (" .. snapshot.Mode .. ")"
							end
							if reaper.ImGui_MenuItem(ctx, label) then
								OverwriteSnapshot(snapshot.Name)
							end
						end
						reaper.ImGui_EndMenu(ctx)
					end
					
					reaper.ImGui_EndCombo(ctx)
				end
				reaper.ImGui_PopStyleColor(ctx)
				reaper.ImGui_PopItemWidth(ctx)
				reaper.ImGui_EndGroup(ctx)
			end
			reaper.ImGui_EndListBox(ctx)
		end

		OpenPopups(TempPopup_i)
		NewGroupPopup() -- Add the new group popup
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

Init()
loop()
reaper.atexit(SaveSnapshotConfig)
