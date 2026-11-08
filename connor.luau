-- Connor Vision
-- Q toggles analysis. E hides or shows flag status during analysis in place 2336379484.
-- In Studio, use a LocalScript in StarterPlayerScripts.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local flagMode = game.PlaceId == 2336379484
local prisonMode = game.PlaceId == 155615604
local hasPlayerScan = flagMode or prisonMode

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
local PRISON_ROLE_COLORS = {
	Guards = Color3.fromRGB(93, 219, 255),
	Inmates = amber,
	Criminals = Color3.fromRGB(255, 89, 112),
}
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

local scanAudio = create("Folder", SoundService, { Name = "ConnorVisionAudio" })
local scanOnSound = create("Sound", scanAudio, {
	Name = "ScanOn",
	Volume = .34,
})
local scanOffSound = create("Sound", scanAudio, {
	Name = "ScanOff",
	Volume = .72,
})
local scanFallback = create("Sound", scanAudio, {
	Name = "ScanFallback",
	SoundId = "rbxassetid://12221990", -- Electronic ping by Roblox
	Volume = .24,
	PlaybackSpeed = 1.1,
})

local function isScanClip(data, byteCount)
	return type(data) == "string" and #data == byteCount and data:sub(1, 3) == "ID3"
end

local function registerScanSound(fileName, byteCount, encodedAudio)
	if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then
		return nil
	end

	local data
	if type(readfile) == "function" then
		local ok, cached = pcall(readfile, fileName)
		if ok then
			data = cached
		end
	end
	if not isScanClip(data, byteCount) then
		local encoded = buffer.fromstring((encodedAudio:gsub("%s", "")))
		local decoded = game:GetService("EncodingService"):Base64Decode(encoded)
		data = buffer.tostring(decoded)
		if not isScanClip(data, byteCount) then
			return nil
		end
		writefile(fileName, data)
	end
	return getcustomasset(fileName)
end

task.defer(function()
	ContentProvider:PreloadAsync({ scanFallback })
end)
local function prepareScanSound(sound, fileName, byteCount, encodedAudio)
	local ok, soundId = pcall(registerScanSound, fileName, byteCount, encodedAudio)
	if ok and type(soundId) == "string" and soundId ~= "" and sound.Parent then
		sound.SoundId = soundId
		ContentProvider:PreloadAsync({ sound })
	end
end

local currentScanSound
local function playScanSound(enabled)
	if currentScanSound then
		currentScanSound:Stop()
		currentScanSound = nil
	end
	local sound = if enabled then scanOnSound else scanOffSound
	if not sound.IsLoaded then
		if not enabled then
			return
		end
		sound = scanFallback
	end
	currentScanSound = sound
	sound:Play()
end

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
if hasPlayerScan then
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
	marker.Visible = false
	if prisonMode then
		return { marker = marker, scale = markerScale, standard = standard }
	end

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
	if visual.warning then
		visual.warning.Visible = false
	end
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

	local function revealPlate(x, y, width, height, paddingX, paddingY, color, opacity)
		local fullWidth, fullHeight = width + paddingX * 2, height + paddingY * 2
		local mask = rect(overlay, x - paddingX, y - paddingY, 0, fullHeight, navy, 0, 2)
		mask.ClipsDescendants = true
		mask.Visible = false
		local frame = rect(mask, paddingX, paddingY, width, height, color, opacity, 2)
		local edge = rect(mask, 0, paddingY + 2, 2, height - 4, pale, .7, 5)
		return { mask = mask, frame = frame, edge = edge, width = fullWidth, height = fullHeight }
	end

	-- Connor's Find Deviant stack uses a solid objective plate above indented subobjectives.
	local headerPlate = revealPlate(0, 0, headerWidth, headerHeight, 16, 2, navy, 0)
	local header = headerPlate.frame
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
		local plate = revealPlate(rowInset, y, readoutWidth, readoutHeight, 5, 3, navy, .84)
		local row = plate.frame
		fade(row, 0, { NumberSequenceKeypoint.new(0, .03), NumberSequenceKeypoint.new(1, .26) })
		brackets(row, -4, -2, readoutWidth + 8, readoutHeight + 4, .67)
		local role = label(row, 14, 0, 88, readoutHeight, pale, 15, light)
		local state = label(row, 102, 0, readoutWidth - 116, readoutHeight, pale, 15, bold)
		state.TextXAlignment = Enum.TextXAlignment.Right

		row.Visible = false
		plate.role = role
		plate.state = state
		rows[index] = plate
	end
	local wanted = false
	local revealProgress = 0
	local drawnProgress
	local railLength = 0

	local function reveal(plate, fraction)
		local visible = fraction > 0 and plate.frame.Visible
		plate.mask.Visible = visible
		if not visible then
			return
		end
		local eased = 1 - (1 - fraction)^3
		local width = math.ceil(plate.width * eased)
		plate.mask.Size = UDim2.fromOffset(width, plate.height)
		plate.edge.Visible = fraction < 1
		plate.edge.Position = UDim2.new(1, -2, 0, 4)
	end

	local function drawReveal()
		if drawnProgress == revealProgress then
			return
		end
		drawnProgress = revealProgress
		reveal(headerPlate, math.clamp(revealProgress / .53, 0, 1))
		for index, row in rows do
			local delay = .21 + .22 * (index - 1)
			reveal(row, math.clamp((revealProgress - delay) / (1 - delay), 0, 1))
		end
		rail.Size = UDim2.fromOffset(1, railLength * math.clamp((revealProgress - .20) / .60, 0, 1))
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
		local length = (readoutHeight + rowGap) * count
		if railLength ~= length then
			railLength = length
			drawnProgress = nil
		end
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

	local function open()
		wanted = true
		if not statusGui.Enabled then
			startIndex()
			statusGui.Enabled = true
			updateStatus()
			drawReveal()
		end
	end

	return {
		carriers = carriers,
		open = open,
		toggle = function()
			if wanted then
				wanted = false
			else
				open()
			end
		end,
		close = function()
			wanted = false
			revealProgress = 0
			drawnProgress = nil
			statusGui.Enabled = false
		end,
		update = function(camera, dt)
			if not statusGui.Enabled then
				return
			end
			resizeReadouts(camera)
			local step = if wanted then dt / .32 else -dt / .18
			revealProgress = math.clamp(revealProgress + step, 0, 1)
			drawReveal()
			if not wanted and revealProgress == 0 then
				statusGui.Enabled = false
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

local flagStatus = if flagMode then makeFlagStatus() else nil

-- Scan lighting, grid projection, and player markers
local scanEnabled = false
local scanStarting = false
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

local function makeProjectileScan()
	local layer = rect(canvas, 0, 0, 0, 0, navy, 0, 5)
	layer.Name = "ProjectileMarkers"
	layer.Size = UDim2.fromScale(1, 1)
	local groups = {
		{
			name = "Explosives", names = { Missile = true, Rocket = true, Part = true },
			explosive = true, color = Color3.fromRGB(255, 128, 75), limit = 32,
			objects = {}, markers = {}, shown = 0,
		},
		{
			name = "Projectiles", names = { Bullet = true },
			explosive = false, color = warningAmber, limit = 48,
			objects = {}, markers = {}, shown = 0,
		},
	}
	local debris
	local deadlines = setmetatable({}, { __mode = "k" })

	local function makeMarker(group)
		local marker = rect(layer, 0, 0, 0, 0, navy, 0, 5)
		local size = if group.explosive then 5 else 4.5
		local shadow = rect(marker, -size/2 - 1, -size/2 - 1, size + 2, size + 2, navy, .8, 5)
		shadow.Rotation = 45
		local diamond = rect(marker, -size/2, -size/2, size, size, group.color, 1, 5)
		diamond.Rotation = 45
		if group.explosive then
			for _, x in { -13, 13 } do
				for _, y in { -11, 11 } do
					local left = if x < 0 then x else x - 5
					local top = if y < 0 then y else y - 5
					rect(marker, left, y, 6, 1.4, group.color, .93, 5)
					rect(marker, x, top, 1.4, 6, group.color, .93, 5)
				end
			end
		end
		return marker
	end

	local function watchFolder(group, folder)
		if group.folder == folder then
			return
		end
		if group.added then
			group.added:Disconnect()
			group.removed:Disconnect()
			group.added = nil
			group.removed = nil
		end
		group.folder = folder
		table.clear(group.objects)
		if not folder then
			return
		end

		local function track(object)
			local isPart = object:IsA("BasePart")
			if isPart or object:IsA("Model") then
				local now = os.clock()
				local deadline = deadlines[object] or now + 15
				deadlines[object] = deadline
				if now < deadline then
					group.objects[object] = isPart
				end
			end
		end
		group.added = folder.ChildAdded:Connect(track)
		group.removed = folder.ChildRemoved:Connect(function(object)
			group.objects[object] = nil
		end)
		for _, object in folder:GetChildren() do
			track(object)
		end
	end

	local function hideUnused(group, count)
		for i = count + 1, group.shown do
			group.markers[i].Visible = false
		end
		group.shown = count
	end

	local function refreshFolders()
		local container = Workspace:FindFirstChild("Debris")
		debris = if container and container:IsA("Folder") then container else nil
		for _, group in groups do
			local folder = debris and debris:FindFirstChild(group.name)
			watchFolder(group, if folder and folder:IsA("Folder") then folder else nil)
		end
	end

	-- Keep observing births when Q is off so toggling analysis never resets their age.
	refreshFolders()
	local folderRefresh = .18
	local folderWatcher = RunService.Heartbeat:Connect(function(dt)
		folderRefresh -= dt
		if folderRefresh <= 0 then
			folderRefresh = .18
			refreshFolders()
		end
	end)

	local function update(camera)
		local now = os.clock()
		for _, group in groups do
			local count = 0
			local folder = group.folder
			if debris and debris.Parent == Workspace and debris.Name == "Debris"
				and folder and folder.Parent == debris and folder.Name == group.name then
				for object, isPart in group.objects do
					if now >= deadlines[object] then
						group.objects[object] = nil
						continue
					end
					if object.Parent ~= folder or not group.names[object.Name] then
						continue
					end
					local position = if isPart then object.Position else object:GetPivot().Position
					local point, onScreen, depth = project(camera, position)
					if not onScreen or depth <= 0 then
						continue
					end
					count += 1
					local marker = group.markers[count]
					if not marker then
						marker = makeMarker(group)
						group.markers[count] = marker
					end
					place(marker, point)
					if count > group.shown then
						marker.Visible = true
					end
					if count == group.limit then
						break
					end
				end
			end
			hideUnused(group, count)
		end
	end

	local function stop()
		for _, group in groups do
			hideUnused(group, 0)
		end
	end

	local function destroy()
		folderWatcher:Disconnect()
		for _, group in groups do
			watchFolder(group, nil)
		end
		stop()
	end

	return { update = update, stop = stop, destroy = destroy }
end

local projectileScan = makeProjectileScan()

local function makeFloorSweep()
	local rows = {}
	local leadingEdge = -13
	for index = 1, 14 do
		local size = if index <= 7 then 4.5 else 8.5
		local depth = leadingEdge + size / 2
		rows[index] = {
			depth = depth, size = size, columns = if index <= 7 then 5 else 6,
			at = .07 + (depth + 13) / 155,
		}
		leadingEdge += size
	end
	local colors = {
		Color3.fromRGB(221, 242, 255), Color3.fromRGB(147, 201, 246),
		Color3.fromRGB(196, 227, 251), Color3.fromRGB(239, 248, 255),
	}
	local available, active = {}, {}
	local folder
	local origin, forward, side
	local floorHeight
	local nextRow, elapsed = 1, 0
	local pending = false
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.IgnoreWater = true
	ray.RespectCanCollide = true
	local down = Vector3.new(0, -35, 0)
	local rise = Vector3.new(0, 4, 0)

	local function release(index)
		local tile = active[index]
		tile.part.Transparency = 1
		table.insert(available, tile)
		active[index] = active[#active]
		active[#active] = nil
	end

	local function stop()
		pending = false
		origin = nil
		for index = #active, 1, -1 do
			release(index)
		end
	end

	local function paintRow(row, index)
		local center = origin + forward * row.depth + rise
		local width = row.size - .12
		for column = -row.columns, row.columns do
			local hit = Workspace:Raycast(center + side * (column * row.size), down, ray)
			if not hit or hit.Normal.Y < .65 or math.abs(hit.Position.Y - floorHeight) > 12 then
				continue
			end
			if not folder then
				folder = create("Folder", Workspace, { Name = "ConnorFloorSweep" })
			end
			local tile = table.remove(available)
			if not tile then
				tile = { part = create("Part", folder, {
					Name = "SweepTile", Anchored = true, CanCollide = false,
					CanTouch = false, CanQuery = false, CastShadow = false,
					Material = Enum.Material.Neon, Transparency = 1,
				}) }
			end
			local normal = hit.Normal
			local right = (side - normal * side:Dot(normal)).Unit
			local part = tile.part
			part.Size = Vector3.new(width, .028, width)
			part.CFrame = CFrame.fromMatrix(hit.Position + normal * .036, right, normal, right:Cross(normal))
			part.Color = colors[(column * 7 + index * 5) % #colors + 1]
			tile.at = row.at + math.abs(column) * .004 + (column + index) % 3 * .007
			table.insert(active, tile)
		end
	end

	local function update(camera, position, dt)
		if pending then
			stop()
			origin = position
			floorHeight = gridDatum
			local look = camera.CFrame.LookVector
			forward = Vector3.new(look.X, 0, look.Z)
			forward = if forward.Magnitude > .02 then forward.Unit else Vector3.new(0, 0, -1)
			side = forward:Cross(Vector3.yAxis)
			local excluded = probeRay.FilterDescendantsInstances
			local debris = Workspace:FindFirstChild("Debris")
			if debris then
				table.insert(excluded, debris)
			end
			ray.FilterDescendantsInstances = excluded
			nextRow, elapsed = 1, 0
		end
		if not origin then
			return
		end
		elapsed += dt
		-- Keep the one-shot raycasts spread over the moving front.
		local budget = 3
		while nextRow <= #rows and rows[nextRow].at <= elapsed and budget > 0 do
			local row = rows[nextRow]
			if elapsed - row.at < .21 then
				paintRow(row, nextRow)
			end
			nextRow += 1
			budget -= 1
		end
		for index = #active, 1, -1 do
			local tile = active[index]
			local age = elapsed - tile.at
			if age >= .21 then
				release(index)
			elseif age >= 0 then
				local peak = math.min(age / .025, 1)
				local tail = 1 - math.clamp((age - .042) / .168, 0, 1)
				tile.part.Transparency = 1 - .88 * peak * tail^2
			end
		end
		if nextRow > #rows and #active == 0 then
			origin = nil
		end
	end

	return {
		start = function() pending = true end,
		stop = stop,
		update = update,
		destroy = function()
			stop()
			if folder then
				folder:Destroy()
			end
		end,
	}
end

local floorSweep = makeFloorSweep()

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
	local ownTeam = if flagMode then activeTeam(player) else player.Team
	if not ownTeam or (prisonMode and (player.Neutral or not PRISON_ROLE_COLORS[ownTeam.Name])) then
		hideEnemies()
		return
	end

	local seesGuards = prisonMode and ownTeam.Name ~= "Guards"
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local character = other.Character
		local carrier = flagStatus and flagStatus.carriers[other]
		local opponent
		local roleColor
		if prisonMode then
			local team = other.Team
			if team and not other.Neutral and (team.Name == "Guards") == seesGuards then
				roleColor = PRISON_ROLE_COLORS[team.Name]
			end
			opponent = roleColor ~= nil
		else
			local team = activeTeam(other)
			opponent = team ~= nil and team ~= ownTeam
		end
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
		if roleColor and visual.roleColor ~= roleColor then
			visual.roleColor = roleColor
			for _, panel in visual.standard:GetChildren() do
				panel.BackgroundColor3 = roleColor
			end
		end
		visual.root = root
		visual.humanoid = humanoid
		visual.head = head and head:IsA("BasePart") and head or nil
		visual.character = character
		if flagMode then
			watchProtection(visual, character, root)
		end
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
		local carrier = flagStatus and flagStatus.carriers[visual.player]
		if carrier and carrier.character ~= visual.character then
			carrier = nil
		end
		if visual.humanoid.Health <= 0 or root.Parent ~= visual.character
			or not visual.character:IsDescendantOf(Workspace) or (not visual.opponent and not carrier) then
			hideEnemy(visual)
			continue
		end

		local color = carrier and (visual.opponent and carrierOrange or carrierBlue)
			or visual.roleColor or amber
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
			if visual.warning and visual.warning.Visible then
				local rightSide = point.X < viewport.X - 42
				visual.warning.Position = UDim2.fromOffset(rightSide and 23 or -42, -9)
				visual.warningText.Visible = rightSide and point.X < viewport.X - 137 and distance < 165
			end
		end
	end
end

local function stopScan()
	scanEnabled = false
	scanStarting = false
	projectileScan.stop()
	floorSweep.stop()
	if flagStatus then
		flagStatus.close()
	end
	if hasPlayerScan then
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
		projectileScan.stop()
		floorSweep.stop()
		if flagStatus then
			flagStatus.close()
		end
		if hasPlayerScan then
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
	if scanStarting then
		scanStarting = false
		floorSweep.start()
		if flagStatus then
			flagStatus.open()
		end
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
	if scanEnabled then
		projectileScan.update(camera)
		floorSweep.update(camera, root.Position, dt)
	end
	if scanEnabled and hasPlayerScan then
		if flagStatus then
			flagStatus.update(camera, dt)
		end
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
			scanStarting = true
			gridDatum = nil
			sampleTimer = 0
		end
		playScanSound(scanEnabled)
	elseif input.KeyCode == Enum.KeyCode.E and scanEnabled and not scanStarting and flagStatus then
		local camera = Workspace.CurrentCamera
		if camera and aliveRoot(player.Character) then
			flagStatus.toggle()
		end
	end
end

local connections = {
	UserInputService.InputBegan:Connect(onInputBegan),
	player.CharacterRemoving:Connect(stopScan),
}

if hasPlayerScan then
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
	projectileScan.destroy()
	floorSweep.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	if hasPlayerScan then
		for candidate in playerConnections do
			unwatchPlayer(candidate)
		end
		hideEnemies()
		highlightFolder:Destroy()
	end
	if flagStatus then
		flagStatus.destroy()
	end
	grade:Destroy()
	scanAudio:Destroy()
	gui:Destroy()
end

RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, render)
runtime[cleanupKey] = cleanup
if typeof(script) == "Instance" and script:IsA("LocalScript") then
	scriptConnection = script.Destroying:Connect(cleanup)
end

-- Scan cues from The Hostage gameplay.
task.defer(prepareScanSound, scanOnSound, "connor-vision-scan-start-v1.mp3", 50293, [[
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
CnYUUIxGA6UXBBCaFc2eA1i2ERielFV2LMGgMCySIWeslSUsQr6tqDpqMmpARG9v//7v/+RAXZohoiP9w6wUETSloGcikXMS7WJo1B4cjI6vbBBNFoSrplEc
BiJxtjVsj0UkCYp//vdZA0MiiIFiXd4WN/QiEY3KFVGGg1QESjiW5ccAKRECyMllrJEIQUacuSM9BjdVbEfiUJigu8c0TclZJ+ghAAD0TQHWcG5WLrIAi3Rc
kDKQGPag7/EQdDWyAAAADboQApWlo0RoTLHSPd/yxVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7dET+ARJcIMr7L0JYTMRpT2GIWQbwWSnsMMjo1Irk/YSZHFVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7FET5j/DnBkTB+Fg4FGCYeEHpAwAA
Af4AAAAgAAA/wAAABFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVQ==
]])

task.defer(prepareScanSound, scanOffSound, "connor-vision-scan-stop-v2.mp3", 17282, [[
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
bOaWxae3geq7bMXGSpk9KRuvTPMxNJ1MHEn/+9RE1IAFN13PayxL6qULmg9liI9UWV897OGDqqkoZ72ssDU95dufA6ue/Dp/6y8tiXPWPrvLaVrajeOXBFyr
UnS7dOYsz7Qd81SD8uXPxnR0rZWLsiWqduwfM17GWZa+k/NXdRVH/qbgOrxFO7NZtbvsOiTiATSFTmMSEeILfmEmqwURByoYCWpdhmCxJEwUCIkhKVSxCWSk
OYHh2XHKlQJNKxwDs8ZJUBs5Kx8faytOVmPMlN2CSqdK1+HzLx7QvKy6XnlvQHalzRBJrjxzbmqHy6Ow5Hf8tiLp5c6gXPI1qE3WF05YJrYAMULXlYnRKiSp
YPqqmnbU3rZb7HTUbNF1nWVNoeedrgC5P5ibzJr4VGQFm7qoZntnmlgAExKpzgzMK0DJKvNmwhhs+eMg7qWyA5I1lrWUeWHP07QuCLCIEj6JcKsxQpNEOlg0
Kj4pZVxVmMeQilkREqTxCZmSpNK+0KGOS6pLklkR/Aszv/laGKJ/TJSgEeRSeCVfvLkZYsAjZycrXnDQnTQUAolJG5JEjPfObuVsyajmSVgKOxBIqXiHZJPb
XGDIlFrQVcDhTVeIBSAodTNY8qCpIl5gcU7bEaTFaTXXJckAJ5cEUJC0VFIZJTgaalG1RSKSWmp2hQoRSzaGEfaFxEKtimKXbGvJWaGCJZFNkREqElSFRNaF
DKOWhgqr/NS1q/QESsUgxqJBQYbk+KdYF+f/6b/45UxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+3RE9g/0ZEzK+wk0eoBn
uU9lI49AAAH+AAAAIAAAP8AAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVU=
]])

return cleanup
