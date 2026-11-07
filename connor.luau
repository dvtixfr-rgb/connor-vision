-- Connor Vision
-- Q toggles analysis. E opens flag status in place 2336379484.
-- In Studio, use a LocalScript in StarterPlayerScripts.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Place 155615604 and other places use the base scan.
local teamMode = game.PlaceId == 2336379484

local FLAGS_BY_TEAM = {
	["Green Team"] = { part = "greenflag", brick = BrickColor.new("Bright green") },
	["Desert Team"] = { part = "yellowflag", brick = BrickColor.new("Bright yellow") },
	["Cave Team"] = { part = "caveflag", brick = BrickColor.new("Medium brown") },
	["Jungle Team"] = { part = "jungleflag", brick = BrickColor.new("Bronze") },
	["Snow Team"] = { part = "snowflag", brick = BrickColor.new("Institutional white") },
}

local player = Players.LocalPlayer
if not player then
	error("Connor Vision needs a Roblox client.")
end
local playerGui = player:WaitForChild("PlayerGui")

-- Loading the script again replaces the current scan.
local runtime = type(shared) == "table" and shared or _G
local cleanupKey = "ConnorVisionCleanup"
local previousCleanup = runtime[cleanupKey]
if type(previousCleanup) == "function" then
	previousCleanup()
end

local blue = Color3.fromRGB(107, 163, 218)
local amber = Color3.fromRGB(238, 185, 43)
local warningAmber = Color3.fromRGB(255, 214, 117)
local carrierOrange = Color3.fromRGB(255, 109, 67)
local carrierBlue = Color3.fromRGB(102, 203, 255)
local navy = Color3.fromRGB(7, 13, 25)
local neutralTint = Color3.new(1, 1, 1)
local FONT_FAMILY = "rbxasset://fonts/families/Montserrat.json"
local font = Font.new(FONT_FAMILY, Enum.FontWeight.Medium)
local RENDER_STEP = "ConnorTeamVision"
local GRID_SPACING = 9
local GRID_MAJOR = GRID_SPACING * 2
local GRID_HEIGHT = 8
local GRID_FADE_START = 24
local GRID_FADE_END = 108
local GRID_EXTENT = 142

local function create(class, parent, properties)
	local instance = Instance.new(class)
	for key, value in properties do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local gui = create("ScreenGui", playerGui, {
	Name = "ConnorTeamVision",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
	DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Global,
	Enabled = false,
})

local grade = create("ColorCorrectionEffect", Lighting, {
	Name = "ConnorTeamVisionGrade",
	Enabled = false,
})

local function rect(parent, x, y, width, height, color, opacity, z)
	return create("Frame", parent, {
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - opacity,
		BorderSizePixel = 0,
		ZIndex = z,
	})
end

local function fade(frame, rotation, keypoints)
	create("UIGradient", frame, {
		Rotation = rotation,
		Transparency = NumberSequence.new(keypoints),
	})
end

local wash = rect(gui, 0, 0, 0, 0, navy, 0, 1)
wash.Size = UDim2.fromScale(1, 1)

local vignette = {}
for _, edge in {
	{ 0, 0, .23, 1, 0 }, { .77, 0, .23, 1, 180 },
	{ 0, 0, 1, .22, 90 }, { 0, .71, 1, .29, 270 },
} do
	local frame = rect(gui, 0, 0, 0, 0, navy, 0, 2)
	frame.Position = UDim2.fromScale(edge[1], edge[2])
	frame.Size = UDim2.fromScale(edge[3], edge[4])
	fade(frame, edge[5], {
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(.48, .68),
		NumberSequenceKeypoint.new(1, 1),
	})
	table.insert(vignette, frame)
end

local canvas = rect(gui, 0, 0, 0, 0, navy, 0, 3)
local canvasScale = create("UIScale", canvas, { Scale = 1 })
local gridLayer = rect(canvas, 0, 0, 0, 0, navy, 0, 3)
gridLayer.Size = UDim2.fromScale(1, 1)
local markerLayer
local highlightFolder
if teamMode then
	markerLayer = rect(canvas, 0, 0, 0, 0, navy, 0, 6)
	markerLayer.Size = UDim2.fromScale(1, 1)
	highlightFolder = create("Folder", Workspace, { Name = "ConnorTeamVisionHighlights" })
end
local gridBands = {}
local gridNodes = {}
local enemyVisuals = {}
local enemyTargets = {}
local enemyRefresh = 0

local function makeGridLine(thickness)
	local frame = rect(gridLayer, 0, 0, 1, 1, blue, 0, 3)
	frame.AnchorPoint = Vector2.new(.5, .5)
	frame.Visible = false
	local gradient = create("UIGradient", frame, {})
	return { frame = frame, gradient = gradient, thickness = thickness, visible = false, alpha = 0 }
end

local function makeBand(level, radius, phase, opacity, thickness)
	local lines = {}
	for offset = -radius, radius do
		table.insert(lines, {
			offset = offset,
			alongX = makeGridLine(thickness),
			alongZ = makeGridLine(thickness),
		})
	end
	table.insert(gridBands, { level = level, phase = phase, radius = radius, opacity = opacity, lines = lines })
end

for level = -1, 2 do
	makeBand(level, 7, 0, .31, 1.2)
	makeBand(level, 3, GRID_SPACING, .10, .95)
end

for x = -3, 3 do
	for z = -3, 3 do
		local dot = rect(gridLayer, 0, 0, 4, 4, blue, 0, 4)
		dot.AnchorPoint = Vector2.new(.5, .5)
		create("UICorner", dot, { CornerRadius = UDim.new(.5, 0) })
		local number
		if (x + z) % 3 == 0 then
			number = create("TextLabel", dot, {
				Position = UDim2.fromOffset(8, -13),
				Size = UDim2.fromOffset(52, 15),
				BackgroundTransparency = 1,
				TextColor3 = blue,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = font,
				ZIndex = 4,
			})
		end
		table.insert(gridNodes, {
			x = x, z = z, dot = dot, number = number,
			post = makeGridLine(1.05),
		})
	end
end

local function shieldEdge(parent, x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	local edge = rect(parent, (x1 + x2) / 2, (y1 + y2) / 2, math.sqrt(dx * dx + dy * dy), 1.85,
		warningAmber, .91, 7)
	edge.AnchorPoint = Vector2.new(.5, .5)
	edge.Rotation = math.deg(math.atan2(dy, dx))
end

local function makeEnemyVisual()
	local marker = rect(markerLayer, 0, 0, 0, 0, amber, 0, 6)
	local markerScale = create("UIScale", marker, { Scale = 1 })
	local standard = rect(marker, 0, 0, 0, 0, navy, 0, 6)
	-- Four panels leave the center open. The thin flanks and dot stay separate.
	rect(standard, -12, -10, 9, 20, amber, .95, 6)
	rect(standard, 3, -10, 9, 20, amber, .95, 6)
	rect(standard, -3, -10, 6, 7, amber, .95, 6)
	rect(standard, -3, 3, 6, 7, amber, .95, 6)
	rect(standard, -16, -10, 2, 20, amber, .74, 6)
	rect(standard, 14, -10, 2, 20, amber, .74, 6)
	local dot = rect(standard, -1.5, 14, 3, 3, amber, .90, 6)
	dot.Rotation = 45
	local warning = rect(marker, 23, -9, 0, 0, navy, 0, 7)
	local badge = rect(warning, -3, -2, 22, 23, navy, .68, 7)
	create("UICorner", badge, { CornerRadius = UDim.new(0, 3) })
	shieldEdge(warning, 0, 1, 16, 1)
	shieldEdge(warning, 0, 1, 0, 10)
	shieldEdge(warning, 16, 1, 16, 10)
	shieldEdge(warning, 0, 10, 8, 17)
	shieldEdge(warning, 16, 10, 8, 17)
	rect(warning, 7.25, 4, 1.5, 5, warningAmber, .96, 7)
	rect(warning, 7.25, 11, 1.5, 1.5, warningAmber, .96, 7)
	local warningText = create("TextLabel", warning, {
		Position = UDim2.fromOffset(24, -2),
		Size = UDim2.fromOffset(110, 22),
		BackgroundTransparency = 1,
		Text = "PROTECTED",
		TextColor3 = warningAmber,
		TextStrokeColor3 = navy,
		TextStrokeTransparency = .22,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = font,
		ZIndex = 7,
	})
	warning.Visible = false
	marker.Visible = false
	return {
		marker = marker, scale = markerScale, standard = standard,
		warning = warning, warningText = warningText,
	}
end

local function stopWatchingProtection(visual)
	if visual.protectionCharacter then
		for _, connection in visual.protectionConnections do
			connection:Disconnect()
		end
		visual.protectionCharacter = nil
		visual.protectionRoot = nil
		visual.protectionConnections = nil
	end
	visual.warning.Visible = false
end

local function watchProtection(visual, character, root)
	if visual.protectionCharacter == character and visual.protectionRoot == root then
		return
	end
	stopWatchingProtection(visual)
	visual.protectionCharacter = character
	visual.protectionRoot = root

	local fields = {}
	local function added(child, parent)
		if child:IsA("ForceField") then
			fields[child] = parent
			visual.warning.Visible = true
		end
	end
	local function removed(child, parent)
		if fields[child] == parent then
			fields[child] = nil
			visual.warning.Visible = next(fields) ~= nil
		end
	end

	local connections = {}
	visual.protectionConnections = connections
	for _, parent in { character, root } do
		table.insert(connections, parent.ChildAdded:Connect(function(child)
			added(child, parent)
		end))
		table.insert(connections, parent.ChildRemoved:Connect(function(child)
			removed(child, parent)
		end))
		for _, child in parent:GetChildren() do
			added(child, parent)
		end
	end
end

local function hideEnemy(visual)
	visual.marker.Visible = false
	stopWatchingProtection(visual)
	if visual.highlight then
		visual.highlight:Destroy()
		visual.highlight = nil
	end
end

local function hideEnemies()
	for _, visual in enemyVisuals do
		hideEnemy(visual)
	end
end

local function activeTeam(candidate)
	local team = candidate.Team
	if team and FLAGS_BY_TEAM[team.Name] and not candidate.Neutral then
		return team
	end
	return nil
end

local function aliveRoot(character)
	if character and character:IsDescendantOf(Workspace) then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			return root, humanoid
		end
	end
	return nil
end

-- Flag HUD and pickup tracking
local function makeFlagStatus()
	local pickupRadius = 3.6
	local contactWindow = .48
	local pollInterval = .08

	local byPart = {}
	local byColorNumber = {}
	local byColorName = {}
	for teamName, spec in FLAGS_BY_TEAM do
		spec.teamName = teamName
		byPart[spec.part] = spec
		byColorNumber[spec.brick.Number] = spec
		byColorName[spec.brick.Name:lower()] = spec
	end
	local pale = Color3.fromRGB(241, 245, 249)
	local muted = Color3.fromRGB(168, 187, 204)
	local alert = Color3.fromRGB(255, 141, 97)
	local stateColors = { ["AT BASE"] = pale, TAKEN = alert, UNKNOWN = muted }
	local light = Font.new(FONT_FAMILY, Enum.FontWeight.Light)
	local bold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold)
	local headerWidth, headerHeight = 246, 50
	local readoutWidth, readoutHeight = 218, 36
	local rowInset, rowGap = 17, 6

	local statusGui = create("ScreenGui", playerGui, {
		Name = "ConnorFlagStatus",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 31,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		Enabled = false,
	})
	local overlay = rect(statusGui, 0, 0, headerWidth, headerHeight + (readoutHeight + rowGap) * 2, navy, 0, 1)
	overlay.AnchorPoint = Vector2.new(1, 0)
	overlay.Position = UDim2.new(1, -40, .55, 0)
	local overlayScale = create("UIScale", overlay, { Scale = 1 })
	local lastSize

	local function label(parent, x, y, width, height, color, size, face)
		return create("TextLabel", parent, {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = color,
			TextStrokeColor3 = navy,
			TextStrokeTransparency = .93,
			TextSize = size,
			FontFace = face,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
	end

	local function brackets(parent, x, y, width, height, opacity)
		for _, right in { false, true } do
			local edgeX = right and x + width - 1 or x
			local startX = right and edgeX - 6 or edgeX
			for _, bottom in { false, true } do
				local edgeY = bottom and y + height - 1 or y
				local startY = bottom and edgeY - 7 or edgeY
				rect(parent, startX, edgeY, 7, 1, pale, opacity, 4)
				rect(parent, edgeX, startY, 1, 8, pale, opacity, 4)
			end
		end
	end

	-- Connor's Find Deviant stack uses a solid objective plate above indented subobjectives.
	local header = rect(overlay, 0, 0, headerWidth, headerHeight, navy, 0, 2)
	rect(header, 8, 4, headerWidth - 16, headerHeight - 8, pale, .98, 2)
	rect(header, -14, 4, 27, 1, pale, .34, 2)
	rect(header, headerWidth - 9, headerHeight - 5, 23, 1, pale, .34, 2)
	for _, x in { 11, 15, 19, headerWidth - 20, headerWidth - 16, headerWidth - 12 } do
		rect(header, x, 4, 1.25, headerHeight - 8, navy, .96, 4)
	end
	rect(header, 4, 5, 1, headerHeight - 10, pale, .74, 4)
	rect(header, headerWidth - 5, 5, 1, headerHeight - 10, pale, .74, 4)
	rect(header, 111, 4, 31, 1.7, navy, .89, 4)
	rect(header, 58, headerHeight - 6, 108, 1.9, navy, .89, 4)
	brackets(header, 0, 0, headerWidth, headerHeight, .96)
	local title = label(header, 30, 8, headerWidth - 60, headerHeight - 16, navy, 18, bold)
	title.Text = "FLAGS"
	title.TextStrokeTransparency = 1

	local rail = rect(overlay, rowInset - 4, headerHeight, 1, 0, pale, .32, 2)
	local rows = {}
	for index = 1, 2 do
		local y = headerHeight + rowGap + (index - 1) * (readoutHeight + rowGap)
		local row = rect(overlay, rowInset, y, readoutWidth, readoutHeight, navy, .84, 2)
		fade(row, 0, { NumberSequenceKeypoint.new(0, .03), NumberSequenceKeypoint.new(1, .26) })
		brackets(row, -4, -2, readoutWidth + 8, readoutHeight + 4, .67)
		local role = label(row, 14, 0, 88, readoutHeight, pale, 15, light)
		local state = label(row, 102, 0, readoutWidth - 116, readoutHeight, pale, 15, bold)
		state.TextXAlignment = Enum.TextXAlignment.Right

		row.Visible = false
		rows[index] = { frame = row, role = role, state = state }
	end

	local parts = {}
	local partAdded
	local partRemoving
	local timer = 0
	local matchKey
	local observedRound = false
	local tracks = {}
	local carriers = {}
	local streamingReadable, streaming, minRadius = pcall(function()
		return Workspace.StreamingEnabled, Workspace.StreamingMinRadius
	end)
	local canInferFromAbsence = streamingReadable and streaming == false

	local function indexPart(instance)
		if instance:IsA("BasePart") then
			local spec = byPart[instance.Name:lower()]
			if spec then
				local record = parts[instance]
				if not record then
					record = { spec = spec }
					record.destroying = instance.Destroying:Connect(function()
						record.destroyed = true
					end)
					parts[instance] = record
				end
				record.removedAt = nil
			end
		end
	end

	local function startIndex()
		if partAdded then
			return
		end
		partAdded = Workspace.DescendantAdded:Connect(indexPart)
		partRemoving = Workspace.DescendantRemoving:Connect(function(instance)
			local record = parts[instance]
			if record then
				record.removedAt = os.clock()
			end
		end)
		for _, instance in Workspace:GetDescendants() do
			indexPart(instance)
		end
	end

	local function identifyTool(tool)
		local color = tool:GetAttribute("TeamColor")
		local kind = typeof(color)
		if kind == "BrickColor" then
			return byColorNumber[color.Number]
		elseif kind == "Color3" then
			for _, spec in FLAGS_BY_TEAM do
				if color == spec.brick.Color then
					return spec
				end
			end
		elseif kind == "string" then
			return byColorName[color:lower()]
		elseif kind == "number" then
			return byColorNumber[color]
		end
		return nil
	end

	local function inventoryFlags(container, member, carried)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child.Name:lower() == "flag" then
				local spec = identifyTool(child)
				if spec and spec.teamName ~= member.team.Name then
					local previous = carried[spec]
					if previous == nil then
						carried[spec] = member
					elseif previous ~= member then
						carried[spec] = false
					end
				end
			end
		end
	end

	local function currentCarrier(entry)
		return entry.player.Parent == Players and entry.player.Character == entry.character
			and activeTeam(entry.player) == entry.team and (not entry.humanoid or entry.humanoid.Health > 0)
	end

	local function sampleContacts(track, spec, members, now)
		local half = track.homeHalf
		for _, member in members do
			if member.root and member.team.Name ~= spec.teamName then
				local localPoint = track.homeCFrame:PointToObjectSpace(member.root.Position)
				local x = math.max(math.abs(localPoint.X) - half.X, 0)
				local y = math.max(math.abs(localPoint.Y) - half.Y, 0)
				local z = math.max(math.abs(localPoint.Z) - half.Z, 0)
				if x * x + y * y + z * z <= pickupRadius * pickupRadius then
					member.contactAt = now
					track.contacts[member.player] = member
				end
			end
		end
	end

	local function soleContact(track, now)
		local closest
		for _, entry in track.contacts do
			if now - entry.contactAt <= contactWindow and currentCarrier(entry) then
				if closest then
					return nil
				end
				closest = entry
			end
		end
		return closest
	end

	local function insideStreamingFocus(track)
		if not streamingReadable or not streaming or minRadius <= 8 then
			return false
		end
		local character = player.Character
		local focus = player.ReplicationFocus or (character and character.PrimaryPart)
		return focus and focus:IsA("BasePart")
			and (track.homeCFrame.Position - focus.Position).Magnitude + track.homeHalf.Magnitude + 8 < minRadius
	end

	local function rememberHolder(track, entry)
		local holder = track.holder
		if not holder or holder.player ~= entry.player or holder.character ~= entry.character
			or holder.humanoid ~= entry.humanoid then
			track.holder = {
				player = entry.player, character = entry.character, team = entry.team,
				humanoid = entry.humanoid,
			}
		end
		track.pending = nil
	end

	local function observeFlag(spec, base, direct, disabled, members, now, mayInfer)
		if not spec then
			return "UNKNOWN"
		end
		local track = tracks[spec]
		if not track then
			track = { contacts = {} }
			tracks[spec] = track
		end

		if base and direct == nil then
			if track.homePart ~= base then
				table.clear(track.contacts)
			end
			track.homePart = base
			track.homeRecord = parts[base]
			track.homeCFrame = base.CFrame
			track.homeHalf = base.Size / 2
			track.departedAt = nil
			track.missingSince = nil
			track.pending = nil
			track.holder = nil
			sampleContacts(track, spec, members, now)
			return "AT BASE"
		end

		if track.homePart then
			sampleContacts(track, spec, members, now)
			track.pending = soleContact(track, now)
			track.departedAt = now
			track.nearFocus = insideStreamingFocus(track)
			track.homePart = nil
			table.clear(track.contacts)
		end
		if track.holder and not currentCarrier(track.holder) then
			track.holder = nil
		end
		if track.pending and (now - track.departedAt > .8 or not currentCarrier(track.pending)) then
			track.pending = nil
		end

		local taken = direct ~= nil or disabled
		if direct then
			rememberHolder(track, direct)
		elseif direct == false then
			track.holder = nil
			track.pending = nil
		elseif track.pending and now - track.departedAt >= .16
			and (track.homeRecord.destroyed or (track.nearFocus and insideStreamingFocus(track))) then
			taken = true
		end
		if not taken and mayInfer and canInferFromAbsence then
			track.missingSince = track.missingSince or now
			taken = now - track.missingSince >= .55
		end
		if taken and track.pending and not track.holder then
			rememberHolder(track, track.pending)
		end
		local holder = track.holder
		if holder then
			carriers[holder.player] = holder
		end
		return (taken or holder) and "TAKEN" or "UNKNOWN"
	end

	local function updateStatus()
		local carried, atBase, disabled = {}, {}, {}
		local members = {}
		local ownTeam = activeTeam(player)
		local enemyTeam
		local now = os.clock()
		table.clear(carriers)
		for _, candidate in Players:GetPlayers() do
			local team = activeTeam(candidate)
			if team and team ~= ownTeam then
				enemyTeam = enemyTeam or team
			end
			if team and ownTeam then
				local character = candidate.Character
				local root, humanoid = aliveRoot(character)
				humanoid = humanoid or (character and character:FindFirstChildOfClass("Humanoid"))
				if not humanoid or humanoid.Health > 0 then
					local member = {
						player = candidate, character = character, team = team, root = root, humanoid = humanoid,
					}
					members[candidate] = member
					inventoryFlags(character, member, carried)
					inventoryFlags(candidate:FindFirstChildOfClass("Backpack"), member, carried)
				end
			end
		end

		for part, record in parts do
			if not part:IsDescendantOf(Workspace) then
				if record.removedAt and now - record.removedAt > 1 then
					record.destroying:Disconnect()
					parts[part] = nil
				end
				continue
			end
			local tool = part:FindFirstAncestorOfClass("Tool")
			local container = tool and tool.Parent
			local carrier = container and container:IsA("Model") and Players:GetPlayerFromCharacter(container)
			if not carrier and part.Name:lower() == record.spec.part then
				local visible = part.Transparency < .98
				record.wasVisible = record.wasVisible or visible
				if visible or (part.CanTouch and not record.wasVisible) then
					atBase[record.spec] = part
					record.wasAtBase = true
				elseif record.wasAtBase then
					disabled[record.spec] = true
				end
			end
		end

		local ownFlag = ownTeam and FLAGS_BY_TEAM[ownTeam.Name]
		local enemyFlag = ownTeam and enemyTeam and FLAGS_BY_TEAM[enemyTeam.Name]
		if ownFlag and not enemyTeam then
			for _, spec in FLAGS_BY_TEAM do
				if spec ~= ownFlag and (atBase[spec] or carried[spec] ~= nil) then
					if enemyFlag then
						enemyFlag = nil
						break
					end
					enemyFlag = spec
				end
			end
		end

		local round = (ownTeam and ownTeam.Name or "") .. "/" .. (enemyTeam and enemyTeam.Name or "")
		if matchKey ~= round then
			matchKey = round
			observedRound = false
			table.clear(tracks)
		end
		if ownFlag and (atBase[ownFlag] or carried[ownFlag] ~= nil)
			or enemyFlag and (atBase[enemyFlag] or carried[enemyFlag] ~= nil) then
			observedRound = true
		end

		local mayInfer = observedRound and enemyTeam ~= nil
		local ownState = observeFlag(ownFlag, atBase[ownFlag], carried[ownFlag], disabled[ownFlag], members, now, mayInfer)
		local enemyState = observeFlag(enemyFlag, atBase[enemyFlag], carried[enemyFlag], disabled[enemyFlag], members, now, mayInfer)
		if not statusGui.Enabled then
			return
		end
		local count = 0
		local function show(spec, role, state)
			if not spec then
				return
			end
			count += 1
			local row = rows[count]
			row.frame.Visible = true
			row.role.Text = role
			row.state.Text = state
			row.state.TextColor3 = stateColors[state]
		end
		show(ownFlag, "YOURS", ownState)
		show(enemyFlag, "ENEMY", enemyState)
		if count == 0 then
			local row = rows[1]
			row.frame.Visible = true
			row.role.Text = ""
			row.state.Text = "UNKNOWN"
			row.state.TextColor3 = muted
			count = 1
		end
		for index = count + 1, #rows do
			rows[index].frame.Visible = false
		end
		rail.Size = UDim2.fromOffset(1, (readoutHeight + rowGap) * count)
	end

	local function resizeReadouts(camera)
		local pixels = camera.ViewportSize
		if pixels ~= lastSize then
			lastSize = pixels
			overlayScale.Scale = math.clamp(math.min(pixels.Y / 1080, pixels.X / 1240), .55, 1.20)
		end
	end

	local sampler = RunService.Heartbeat:Connect(function(dt)
		timer -= dt
		if timer <= 0 then
			timer = pollInterval
			if partAdded or activeTeam(player) then
				startIndex()
				updateStatus()
			end
		end
	end)

	return {
		carriers = carriers,
		toggle = function(camera)
			if statusGui.Enabled then
				statusGui.Enabled = false
				return
			end
			startIndex()
			resizeReadouts(camera)
			statusGui.Enabled = true
			updateStatus()
		end,
		close = function()
			statusGui.Enabled = false
		end,
		update = function(camera)
			if statusGui.Enabled then
				resizeReadouts(camera)
			end
		end,
		destroy = function()
			sampler:Disconnect()
			if partAdded then
				partAdded:Disconnect()
				partRemoving:Disconnect()
			end
			for _, record in parts do
				record.destroying:Disconnect()
			end
			statusGui:Destroy()
		end,
	}
end

local flagStatus = if teamMode then makeFlagStatus() else nil

-- Scan lighting, grid projection, and player markers
local scanEnabled = false
local strength = 0
local gridDatum
local sampleTimer = 0
local viewport = Vector2.new(1920, 1080)
local lastPixels
local appliedStrength
local scale = 1
local probeRay = RaycastParams.new()
probeRay.FilterType = Enum.RaycastFilterType.Exclude
probeRay.IgnoreWater = true

local samples = {
	{ x = .50, y = .51, weight = 2 },
	{ x = .22, y = .37, weight = 1 },
	{ x = .78, y = .37, weight = 1 },
	{ x = .22, y = .71, weight = 1 },
	{ x = .78, y = .71, weight = 1 },
	{ x = .50, y = .83, weight = 1 },
}
local targetTone = {
	tint = Color3.fromRGB(219, 230, 250),
	brightness = .006,
	saturation = -.73,
}
local tone = table.clone(targetTone)
local gridView = {}

local function surfaceColor(hit)
	if not hit then
		return nil
	end
	if hit.Instance == Workspace.Terrain then
		return Workspace.Terrain:GetMaterialColor(hit.Material)
	end
	if hit.Instance:IsA("BasePart") and hit.Instance.Transparency < .80 then
		return hit.Instance.Color
	end
	return nil
end

local function luma(color)
	return color.R * .2126 + color.G * .7152 + color.B * .0722
end

local function sampleSurroundings(camera, pixels, position)
	local excluded = {}
	for _, candidate in Players:GetPlayers() do
		if candidate.Character then
			table.insert(excluded, candidate.Character)
		end
	end
	probeRay.FilterDescendantsInstances = excluded

	local ambient = Lighting.OutdoorAmbient:Lerp(Lighting.Ambient, .45)
	local red, green, blueChannel = ambient.R, ambient.G, ambient.B
	local totalWeight = 1
	local chroma = 0
	local function add(color, weight)
		if color then
			red += color.R * weight
			green += color.G * weight
			blueChannel += color.B * weight
			chroma += (math.max(color.R, color.G, color.B) - math.min(color.R, color.G, color.B)) * weight
			totalWeight += weight
		end
	end

	for _, sample in samples do
		local ray = camera:ViewportPointToRay(pixels.X * sample.x, pixels.Y * sample.y)
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 110, probeRay)
		add(surfaceColor(hit), sample.weight)
	end
	local ground = Workspace:Raycast(position, Vector3.new(0, -30, 0), probeRay)
	if not gridDatum then
		gridDatum = ground and ground.Position.Y + .06 or position.Y - 3
	end
	local groundColor = surfaceColor(ground)
	add(groundColor, 1.25)

	local surface = Color3.new(red / totalWeight, green / totalWeight, blueChannel / totalWeight)
	local warmth = surface.R - surface.B
	local greenCast = surface.G - (surface.R + surface.B) * .5
	local sceneLight = luma(surface) * .78 + luma(ambient) * .22
	local floorLight = groundColor and luma(groundColor) * .88 or 0
	local highKey = math.clamp((math.max(sceneLight, floorLight) - .48) / .40, 0, 1)
	local redCut = math.clamp(.099 + highKey * .049 + warmth * .11, .071, .183)
	local greenCut = math.clamp(.071 + highKey * .034 + greenCast * .14, .047, .124)
	local lift = (.43 - sceneLight) * .13
	local lightingOffset = math.clamp((2 - Lighting.Brightness) * .012, -.024, .024)

	targetTone.tint = Color3.new(1 - redCut, 1 - greenCut, .985)
	targetTone.brightness = math.clamp(.014 + lift + lightingOffset - highKey * .027
		- Lighting.ExposureCompensation * .024, -.062, .073)
	targetTone.saturation = -.68 - .17 * math.clamp((chroma / totalWeight - .10) / .52, 0, 1)
end

local function place(frame, point)
	frame.Position = UDim2.fromOffset(point.X, point.Y)
end

local function project(camera, point)
	local projected, visible = camera:WorldToViewportPoint(point)
	return Vector2.new(projected.X, projected.Y) / scale, visible, projected.Z
end

local function clipAxis(origin, delta, limit, first, last)
	if math.abs(delta) < .0001 then
		if origin < 0 or origin > limit then
			return nil
		end
		return first, last
	end

	local edgeA = -origin / delta
	local edgeB = (limit - origin) / delta
	first = math.max(first, math.min(edgeA, edgeB))
	last = math.min(last, math.max(edgeA, edgeB))
	if first > last then
		return nil
	end
	return first, last
end

local function setLineVisible(line, visible)
	if line.visible ~= visible then
		line.visible = visible
		line.frame.Visible = visible
	end
end

local function gridPoint(point)
	return Vector2.new(
		gridView.center.X + point.X / point.Z * gridView.focal.X,
		gridView.center.Y - point.Y / point.Z * gridView.focal.Y
	)
end

local depthGradients = {}
local fadeSpan = GRID_FADE_END - GRID_FADE_START

local function depthWeight(depth)
	local weight = math.clamp((gridView.fadeEnd - depth) * gridView.inverseFadeSpan, 0, 1)
	return weight * weight
end

local function depthLevel(inverseDepth)
	return math.round(depthWeight(1 / inverseDepth) * 8)
end

-- Perspective depth varies with reciprocal Z along the projected segment.
local function applyDepthFade(line, inverseNear, inverseFar)
	local first = depthLevel(inverseNear)
	local last = depthLevel(inverseFar)
	if first == 0 and last == 0 then
		return false
	end

	local step = inverseFar - inverseNear
	local quarter = depthLevel(inverseNear + step * .22)
	local middle = depthLevel(inverseNear + step * .5)
	local threeQuarters = depthLevel(inverseNear + step * .78)
	local key = ((((first * 9 + quarter) * 9 + middle) * 9 + threeQuarters) * 9 + last)
	if line.depthKey ~= key then
		local sequence = depthGradients[key]
		if not sequence then
			sequence = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - first / 8),
				NumberSequenceKeypoint.new(.22, 1 - quarter / 8),
				NumberSequenceKeypoint.new(.5, 1 - middle / 8),
				NumberSequenceKeypoint.new(.78, 1 - threeQuarters / 8),
				NumberSequenceKeypoint.new(1, 1 - last / 8),
			})
			depthGradients[key] = sequence
		end
		line.depthKey = key
		line.gradient.Transparency = sequence
	end
	return true
end

-- Endpoints are already in camera space. Project only the visible segment.
local function drawGridLine(line, start, finish, opacity)
	if opacity < .006 then
		setLineVisible(line, false)
		return
	end
	local near = .85
	local clipStart, clipEnd = clipAxis(start.Z - near, finish.Z - start.Z, gridView.fadeEnd - near, 0, 1)
	if not clipStart then
		setLineVisible(line, false)
		return
	end
	if clipStart > 0 or clipEnd < 1 then
		local segment = finish - start
		finish = start + segment * clipEnd
		start += segment * clipStart
	end

	local a = gridPoint(start)
	local b = gridPoint(finish)
	local delta = b - a
	local first, last = clipAxis(a.X, delta.X, viewport.X, 0, 1)
	if first then
		first, last = clipAxis(a.Y, delta.Y, viewport.Y, first, last)
	end
	if not first then
		setLineVisible(line, false)
		return
	end
	local inverseZ = 1 / start.Z
	local inverseStep = 1 / finish.Z - inverseZ
	if not applyDepthFade(line, inverseZ + inverseStep * first, inverseZ + inverseStep * last) then
		setLineVisible(line, false)
		return
	end

	local frame = line.frame
	place(frame, a + delta * ((first + last) / 2))
	frame.Size = UDim2.fromOffset(delta.Magnitude * (last - first), line.thickness)
	frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	local alpha = math.round(opacity * 255)
	if line.alpha ~= alpha then
		line.alpha = alpha
		frame.BackgroundTransparency = 1 - alpha / 255
	end
	setLineVisible(line, true)
end

local function falloff(distance, near, far)
	return 1 - math.clamp((distance - near) / (far - near), 0, 1)
end

local function updateGrid(camera)
	local view = gridView
	local eye = camera.CFrame
	local fov = camera.FieldOfView
	local lensChanged = view.camera ~= camera or view.fov ~= fov or view.viewport ~= viewport
	if not lensChanged and view.eye == eye and view.strength == strength and view.datum == gridDatum then
		return
	end

	if lensChanged then
		local ahead = eye.Position + eye.LookVector * 8
		local center = project(camera, ahead)
		local offset = project(camera, ahead + eye.RightVector + eye.UpVector)
		view.center = center
		view.focal = Vector2.new((offset.X - center.X) * 8, (center.Y - offset.Y) * 8)
		view.camera = camera
		view.fov = fov
		view.viewport = viewport
	end
	view.eye = eye
	view.strength = strength
	view.datum = gridDatum
	view.fadeEnd = GRID_FADE_START + fadeSpan * strength
	view.inverseFadeSpan = 1 / math.max(1, view.fadeEnd - GRID_FADE_START)

	local origin = eye.Position
	local right, up, look = eye.RightVector, eye.UpVector, eye.LookVector
	local axisX = Vector3.new(right.X, up.X, look.X)
	local axisY = Vector3.new(right.Y, up.Y, look.Y)
	local axisZ = Vector3.new(right.Z, up.Z, look.Z)
	local extentX, extentZ = axisX * GRID_EXTENT, axisZ * GRID_EXTENT
	local centerLevel = math.floor((origin.Y - gridDatum) / GRID_HEIGHT)

	-- World coordinates stay fixed. Only the pool of visible lines follows the view.
	for _, band in gridBands do
		local y = gridDatum + (centerLevel + band.level) * GRID_HEIGHT - origin.Y
		local height = math.abs(y)
		local separation = math.clamp((height - .45) / 2.25, 0, 1)
		local bandOpacity = band.opacity * strength * separation * falloff(height, 6, 15)
		if bandOpacity < .006 then
			for _, item in band.lines do
				setLineVisible(item.alongX, false)
				setLineVisible(item.alongZ, false)
			end
			continue
		end

		local xStart = math.round((origin.X - band.phase) / GRID_MAJOR) * GRID_MAJOR + band.phase - origin.X
		local zStart = math.round((origin.Z - band.phase) / GRID_MAJOR) * GRID_MAJOR + band.phase - origin.Z
		local reach = band.radius * GRID_MAJOR
		local planeOffset = axisY * y
		for _, item in band.lines do
			local offset = item.offset * GRID_MAJOR
			local x, z = xStart + offset, zStart + offset
			local xAnchor = planeOffset + axisZ * z
			local zAnchor = planeOffset + axisX * x
			drawGridLine(item.alongX, xAnchor - extentX, xAnchor + extentX,
				bandOpacity * falloff(math.abs(z), reach * .44, reach))
			drawGridLine(item.alongZ, zAnchor - extentZ, zAnchor + extentZ,
				bandOpacity * falloff(math.abs(x), reach * .44, reach))
		end
	end

	local majorX = math.round(origin.X / GRID_MAJOR)
	local majorZ = math.round(origin.Z / GRID_MAJOR)
	local postExtent = axisY * 14
	for _, item in gridNodes do
		local xIndex = majorX + item.x
		local zIndex = majorZ + item.z
		local x = xIndex * GRID_MAJOR - origin.X
		local z = zIndex * GRID_MAJOR - origin.Z
		local anchor = axisX * x + axisZ * z
		local opacity = strength * falloff(math.max(math.abs(x), math.abs(z)), 27, 57)
		drawGridLine(item.post, anchor - postExtent, anchor + postExtent, opacity * .17)

		local y = gridDatum + (centerLevel + (xIndex + zIndex) % 2) * GRID_HEIGHT - origin.Y
		local node = anchor + axisY * y
		opacity *= depthWeight(node.Z)
		local point
		if node.Z > 2.5 and opacity > .025 then
			local projected = gridPoint(node)
			if projected.X >= 0 and projected.X <= viewport.X
				and projected.Y >= 0 and projected.Y <= viewport.Y then
				point = projected
			end
		end
		local visible = point ~= nil
		if item.visible ~= visible then
			item.visible = visible
			item.dot.Visible = visible
		end
		if not point then
			continue
		end

		place(item.dot, point)
		item.dot.BackgroundTransparency = 1 - opacity * .77
		if item.number then
			local index = xIndex - zIndex
			if item.numberIndex ~= index then
				item.numberIndex = index
				item.number.Text = string.format("%04.1f", (84 + index * 1.7) % 100)
			end
			item.number.TextTransparency = 1 - opacity * .47
		end
	end
end

local function refreshEnemyTargets()
	table.clear(enemyTargets)
	local ownTeam = activeTeam(player)
	if not ownTeam then
		hideEnemies()
		return
	end

	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local team = activeTeam(other)
		local character = other.Character
		local carrier = flagStatus.carriers[other]
		local opponent = team ~= nil and team ~= ownTeam
		local root, humanoid
		if opponent or (carrier and carrier.character == character) then
			root, humanoid = aliveRoot(character)
		end
		local visual = enemyVisuals[other]

		if not root then
			if visual then
				hideEnemy(visual)
			end
			continue
		end

		if not visual then
			visual = makeEnemyVisual()
			enemyVisuals[other] = visual
		end
		local head = character:FindFirstChild("Head")
		visual.player = other
		visual.opponent = opponent
		visual.root = root
		visual.humanoid = humanoid
		visual.head = head and head:IsA("BasePart") and head or nil
		visual.character = character
		watchProtection(visual, character, root)
		if visual.highlight and visual.highlight.Adornee ~= character then
			visual.highlight.Adornee = character
		end
		table.insert(enemyTargets, visual)
	end
end

local function updateEnemies(camera, localPosition, dt)
	enemyRefresh -= dt
	if enemyRefresh <= 0 then
		enemyRefresh = .14
		refreshEnemyTargets()
	end

	for _, visual in enemyTargets do
		local root = visual.root
		local carrier = flagStatus.carriers[visual.player]
		if carrier and carrier.character ~= visual.character then
			carrier = nil
		end
		if visual.humanoid.Health <= 0 or root.Parent ~= visual.character
			or not visual.character:IsDescendantOf(Workspace) or (not visual.opponent and not carrier) then
			hideEnemy(visual)
			continue
		end

		local color = carrier and (visual.opponent and carrierOrange or carrierBlue) or amber
		if visual.markerColor ~= color then
			visual.markerColor = color
			visual.standard.Visible = carrier == nil
			if visual.highlight then
				visual.highlight.FillColor = color
				visual.highlight.OutlineColor = color
			end
			visual.highlightStrength = nil
		end
		if not visual.highlight then
			visual.highlight = create("Highlight", highlightFolder, {
				Adornee = visual.character,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				FillColor = color,
				OutlineColor = color,
			})
			visual.highlightStrength = nil
		end
		local urgent = carrier and visual.opponent
		if urgent or visual.highlightStrength ~= strength then
			visual.highlightStrength = strength
			local outline = urgent and (.87 + .08 * math.sin(os.clock() * 5.2)) or (carrier and .92 or .73)
			visual.highlight.FillTransparency = 1 - (carrier and .21 or .14) * strength
			visual.highlight.OutlineTransparency = 1 - outline * strength
		end

		local head = visual.head
		local markerPoint = root.Position + Vector3.new(0, 3, 0)
		if head and head.Parent == visual.character then
			markerPoint = head.Position + Vector3.new(0, head.Size.Y / 2 + .55, 0)
		end
		local point, onScreen = project(camera, markerPoint)
		visual.marker.Visible = onScreen and (not carrier or visual.warning.Visible)
		if visual.marker.Visible then
			place(visual.marker, point)
			local distance = (root.Position - localPosition).Magnitude
			visual.scale.Scale = math.clamp(1 - distance / 340, .45, .92)
			if visual.warning.Visible then
				local rightSide = point.X < viewport.X - 42
				visual.warning.Position = UDim2.fromOffset(rightSide and 23 or -42, -9)
				visual.warningText.Visible = rightSide and point.X < viewport.X - 137 and distance < 165
			end
		end
	end
end

local function stopScan()
	scanEnabled = false
	if flagStatus then
		flagStatus.close()
		table.clear(enemyTargets)
		enemyRefresh = 0
		markerLayer.Visible = false
		hideEnemies()
	end
end

local function render(dt)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = aliveRoot(character)
	if not camera or not root then
		strength = 0
		if flagStatus then
			flagStatus.close()
			hideEnemies()
		end
		gui.Enabled = false
		grade.Enabled = false
		return
	end

	local target = scanEnabled and 1 or 0
	strength += (target - strength) * (1 - math.exp(-dt * 19))
	if math.abs(strength - target) < .002 then
		strength = target
	end
	local active = scanEnabled or strength > .025
	gui.Enabled = active
	grade.Enabled = active
	if not active then
		return
	end

	local pixels = camera.ViewportSize
	if lastPixels ~= pixels then
		lastPixels = pixels
		scale = math.max(.05, math.min(pixels.Y / 1080, pixels.X / 1240))
		viewport = pixels / scale
		canvasScale.Scale = scale
		canvas.Size = UDim2.fromOffset(viewport.X, viewport.Y)
	end

	sampleTimer -= dt
	if sampleTimer <= 0 then
		sampleTimer = .22
		sampleSurroundings(camera, pixels, root.Position)
	end
	local adjust = 1 - math.exp(-dt * 5)
	tone.tint = tone.tint:Lerp(targetTone.tint, adjust)
	tone.brightness += (targetTone.brightness - tone.brightness) * adjust
	tone.saturation += (targetTone.saturation - tone.saturation) * adjust

	grade.Saturation = tone.saturation * strength
	grade.Brightness = tone.brightness * strength
	grade.TintColor = neutralTint:Lerp(tone.tint, strength)
	if appliedStrength ~= strength then
		appliedStrength = strength
		grade.Contrast = .070 * strength
		wash.BackgroundTransparency = 1 - .043 * strength
		for _, frame in vignette do
			frame.BackgroundTransparency = 1 - .24 * strength
		end
	end
	updateGrid(camera)
	if scanEnabled and flagStatus then
		flagStatus.update(camera)
		markerLayer.Visible = true
		updateEnemies(camera, root.Position, dt)
	end
end

local playerConnections = {}
local function refreshRoster()
	enemyRefresh = 0
end

local function watchPlayer(candidate)
	playerConnections[candidate] = {
		candidate:GetPropertyChangedSignal("Team"):Connect(refreshRoster),
		candidate:GetPropertyChangedSignal("Neutral"):Connect(refreshRoster),
		candidate.CharacterAdded:Connect(refreshRoster),
		candidate.CharacterRemoving:Connect(refreshRoster),
	}
	refreshRoster()
end

local function unwatchPlayer(candidate)
	for _, connection in playerConnections[candidate] or {} do
		connection:Disconnect()
	end
	playerConnections[candidate] = nil
end

local function onInputBegan(input, handled)
	if handled or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		if scanEnabled then
			stopScan()
		else
			scanEnabled = true
			gridDatum = nil
			sampleTimer = 0
		end
	elseif input.KeyCode == Enum.KeyCode.E and scanEnabled and flagStatus then
		local camera = Workspace.CurrentCamera
		if camera and aliveRoot(player.Character) then
			flagStatus.toggle(camera)
		end
	end
end

local connections = {
	UserInputService.InputBegan:Connect(onInputBegan),
	player.CharacterRemoving:Connect(stopScan),
}

if flagStatus then
	for _, candidate in Players:GetPlayers() do
		watchPlayer(candidate)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(other)
		unwatchPlayer(other)
		refreshRoster()
		local visual = enemyVisuals[other]
		if visual then
			hideEnemy(visual)
			visual.marker:Destroy()
			enemyVisuals[other] = nil
		end
	end))
end

local stopped = false
local scriptConnection
local function cleanup()
	if stopped then
		return
	end
	stopped = true
	if runtime[cleanupKey] == cleanup then
		runtime[cleanupKey] = nil
	end
	if scriptConnection then
		scriptConnection:Disconnect()
	end

	RunService:UnbindFromRenderStep(RENDER_STEP)
	for _, connection in connections do
		connection:Disconnect()
	end
	if flagStatus then
		for candidate in playerConnections do
			unwatchPlayer(candidate)
		end
		hideEnemies()
		flagStatus.destroy()
		highlightFolder:Destroy()
	end
	grade:Destroy()
	gui:Destroy()
end

RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, render)
runtime[cleanupKey] = cleanup
if typeof(script) == "Instance" and script:IsA("LocalScript") then
	scriptConnection = script.Destroying:Connect(cleanup)
end

return cleanup
