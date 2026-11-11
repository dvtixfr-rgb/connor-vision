-- Connor Vision
-- Q toggles analysis. In The Strongest Battlegrounds, tap right-click instead.
-- E hides or shows flag status during analysis in place 2336379484.
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
local baseplateMode = game.PlaceId == 130960021905304
local battlegroundsMode = game.PlaceId == 10449761463
local generalMode = not flagMode and not prisonMode

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

local gridBlue = Color3.fromRGB(113, 159, 190)
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
	Volume = .58,
})
local scanOffSound = create("Sound", scanAudio, {
	Name = "ScanOff",
	Volume = .58,
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
		return
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

local READOUT_BLINK_DURATION = .134
local READOUT_BLINK_PALE = Color3.fromRGB(226, 235, 244)
local READOUT_BLINK_CYAN = Color3.fromRGB(60, 182, 214)
-- The rooftop title resolves in three cuts: stacked bars, fragments, then one teal streak.
local readoutBlinkCuts = {
	{ { .025, .12, .95, .35, .73 }, { .028, .62, .94, .30, .69 } },
	{ { .17, .36, .075, .15, .19 }, { .47, .44, .10, .16, .29 }, { .71, .38, .045, .14, .18 } },
	{ { .03, .23, .94, .12, .79 } },
}

local function makeReadoutBlink(parent, x, y, width, height, z)
	local layer = rect(parent, x, y, width, height, navy, 0, z)
	layer.Visible = false
	return { layer = layer, bars = {
		rect(layer, 0, 0, 0, 0, READOUT_BLINK_PALE, 0, z),
		rect(layer, 0, 0, 0, 0, READOUT_BLINK_PALE, 0, z),
		rect(layer, 0, 0, 0, 0, READOUT_BLINK_PALE, 0, z),
	} }
end

local function readoutBlinkPhase(age)
	return if age < 0 then 0 elseif age < .034 then 1 elseif age < .10 then 2
		elseif age < READOUT_BLINK_DURATION then 3 else 4
end

local function drawReadoutBlink(blink, age, color)
	local phase = readoutBlinkPhase(age)
	if blink.phase == phase and (phase == 0 or phase == 4 or blink.color == color) then
		return phase
	end
	blink.phase, blink.color = phase, color
	local cuts = readoutBlinkCuts[phase]
	blink.layer.Visible = cuts ~= nil
	if cuts then
		for index, bar in blink.bars do
			local cut = cuts[index]
			bar.Visible = cut ~= nil
			if cut then
				bar.Position = UDim2.fromScale(cut[1], cut[2])
				bar.Size = UDim2.fromScale(cut[3], cut[4])
				bar.BackgroundColor3 = if phase == 3 then READOUT_BLINK_CYAN else color or READOUT_BLINK_PALE
				bar.BackgroundTransparency = 1 - cut[5]
			end
		end
	end
	return phase
end

local wash = rect(gui, 0, 0, 0, 0, Color3.fromRGB(9, 31, 61), 0, 1)
wash.Size = UDim2.fromScale(1, 1)

local canvas = rect(gui, 0, 0, 0, 0, navy, 0, 3)
local canvasScale = create("UIScale", canvas, { Scale = 1 })
local gridLayer = rect(canvas, 0, 0, 0, 0, navy, 0, 3)
gridLayer.Size = UDim2.fromScale(1, 1)
local highlightFolder = create("Folder", Workspace, { Name = "ConnorTeamVisionHighlights" })
local markerLayer = rect(canvas, 0, 0, 0, 0, navy, 0, 6)
markerLayer.Size = UDim2.fromScale(1, 1)
local gridBands = {}
local gridNodes = {}
local enemyVisuals = {}
local enemyTargets = {}
local enemyRefresh = 0

local function makeGridLine(thickness)
	local frame = rect(gridLayer, 0, 0, 1, 1, gridBlue, 0, 3)
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
	makeBand(level, 7, 0, .25, 1)
	makeBand(level, 3, GRID_SPACING, .075, 1)
end

for x = -3, 3 do
	for z = -3, 3 do
		local dot = rect(gridLayer, 0, 0, 2, 2, gridBlue, 0, 4)
		dot.AnchorPoint = Vector2.new(.5, .5)
		local number
		if (x + z) % 3 == 0 then
			number = create("TextLabel", dot, {
				Position = UDim2.fromOffset(5, -10),
				Size = UDim2.fromOffset(40, 12),
				BackgroundTransparency = 1,
				TextColor3 = gridBlue,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				FontFace = font,
				ZIndex = 4,
			})
		end
		table.insert(gridNodes, {
			x = x, z = z, dot = dot, number = number,
			post = makeGridLine(1),
		})
	end
end

local function scanCorners(parent, radius, length, thickness, color, opacity, z)
	for _, side in { -1, 1 } do
		for _, vertical in { -1, 1 } do
			local x = side * radius
			local y = vertical * radius
			rect(parent, if side < 0 then x else x - length, y, length + thickness, thickness, color, opacity, z)
			rect(parent, x, if vertical < 0 then y else y - length, thickness, length, color, opacity, z)
		end
	end
end

local function makeEnemyVisual()
	local marker = rect(markerLayer, 0, 0, 0, 0, amber, 0, 6)
	local markerScale = create("UIScale", marker, { Scale = 1 })
	local standard = rect(marker, -17, -12, 34, 24, navy, .88, 6)
	-- Detroit's clue locator: a split plate, two rails, and the point below it.
	rect(standard, 3, 0, 28, 24, amber, .96, 7)
	rect(standard, 0, 0, 1.55, 24, amber, .94, 7)
	rect(standard, 32.45, 0, 1.55, 24, amber, .94, 7)
	local seam = rect(standard, 16.5, 0, 1, 24, navy, .43, 8)
	local aperture = rect(standard, 13.25, 8.25, 7.5, 7.5, navy, .91, 8)
	local dot = rect(standard, 15.55, 30.5, 2.9, 2.9, amber, .93, 7)
	dot.Rotation = 45
	local colored = {}
	for _, panel in standard:GetChildren() do
		if panel ~= seam and panel ~= aperture then
			table.insert(colored, panel)
		end
	end
	local visual = {
		marker = marker, scale = markerScale, standard = standard, colored = colored,
		standardBlink = makeReadoutBlink(marker, -17, -12, 34, 24, 9),
	}
	marker.Visible = false
	if prisonMode then
		return visual
	end

	local warning = rect(marker, 23, -9, 0, 0, navy, 0, 7)
	local warningArt = rect(warning, 0, 0, 0, 0, navy, 0, 7)
	local badge = rect(warningArt, 0, 1, 20, 20, navy, .67, 7)
	local icon = rect(badge, 10, 10, 0, 0, navy, 0, 8)
	scanCorners(icon, 10, 4, 1, warningAmber, .83, 8)
	rect(icon, -3.2, -5.8, 6.4, 1.25, warningAmber, .91, 8)
	rect(icon, -3.2, -4.55, 1.25, 4.15, warningAmber, .91, 8)
	rect(icon, 1.95, -4.55, 1.25, 4.15, warningAmber, .91, 8)
	rect(icon, -4.6, -.7, 9.2, 6.4, warningAmber, .96, 8)
	local warningPanel = rect(warningArt, 22, 1, 105, 20, navy, .71, 7)
	fade(warningPanel, 0, {
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(.8, .18),
		NumberSequenceKeypoint.new(1, 1),
	})
	rect(warningPanel, 0, 0, 89, 1, warningAmber, .54, 8)
	create("TextLabel", warningPanel, {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.fromOffset(97, 20),
		BackgroundTransparency = 1,
		Text = "PROTECTED",
		TextColor3 = warningAmber,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = font,
		ZIndex = 8,
	})
	warning.Visible = false
	visual.warning = warning
	visual.warningArt = warningArt
	visual.warningPanel = warningPanel
	visual.warningBlink = makeReadoutBlink(warning, 0, 1, 127, 20, 9)
	return visual
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
		visual.warningAt = nil
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
			if not visual.warning.Visible then
				visual.warningAt = nil
			end
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
	visual.standardAt = nil
	visual.lastOnScreen = nil
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
	if not character or not character:IsDescendantOf(Workspace) then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if (humanoid and humanoid.Health <= 0) or (not humanoid and not generalMode) then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root, humanoid
	end
	if generalMode then
		return character.PrimaryPart or character:FindFirstChildWhichIsA("BasePart", true), humanoid
	end
	return nil
end

local function makeRemoteScan()
	local guiService = game:GetService("GuiService")
	local pitchLimit = math.rad(85)
	local lookSensitivity = .003
	local platformOffset = Vector3.new(14000, 900, 14000)
	local streaming = Workspace.StreamingEnabled
	local parkDistance = 0
	if streaming then
		local ok, radius = pcall(function()
			return Workspace.StreamingMinRadius
		end)
		parkDistance = math.min(32, (if ok then radius else 64) * .45)
	end
	local platform = create("Part", nil, {
		Name = "ConnorScanPlatform",
		Anchored = true,
		CanTouch = false,
		Size = if streaming then Vector3.new(12, 2, 12) else Vector3.new(64, 2, 64),
		Transparency = if streaming then 1 else 0,
	})
	local session

	local function nearPlatform(current)
		local offset = current.root.Position - current.landing
		return math.abs(offset.X) <= platform.Size.X / 2 + 2
			and math.abs(offset.Z) <= platform.Size.Z / 2 + 2 and math.abs(offset.Y) <= 12
	end

	local function findLanding(origin, character, height)
		local clearance = platform.Size.Y / 2 + height + .25
		local minimumY = Workspace.FallenPartsDestroyHeight
		if not streaming then
			local pad = origin + platformOffset
			return Vector3.new(pad.X, math.max(pad.Y, minimumY + 150) + clearance, pad.Z)
		end
		if parkDistance < 8 then
			return nil
		end

		-- Streaming follows the real character. Keep both bodies in the same streamed region.
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = { character }
		overlap.RespectCanCollide = true
		overlap.MaxParts = 1
		local ray = RaycastParams.new()
		ray.FilterType = Enum.RaycastFilterType.Exclude
		ray.FilterDescendantsInstances = { character }
		ray.RespectCanCollide = true
		local space = Vector3.new(platform.Size.X, 2 * clearance, platform.Size.Z)
		for _, direction in { -1, 1 } do
			local landing = origin + Vector3.yAxis * (direction * parkDistance)
			if landing.Y - clearance > minimumY + 8
				and #Workspace:GetPartBoundsInBox(CFrame.new(landing), space, overlap) == 0
				and not Workspace:Raycast(landing - Vector3.yAxis * clearance, Vector3.yAxis * space.Y, ray) then
				return landing
			end
		end
		return nil
	end

	local function releaseMouse(current)
		if current.mouseLock and UserInputService.MouseBehavior == current.mouseLock then
			UserInputService.MouseBehavior = current.previousMouseBehavior
		end
		current.mouseLock = nil
	end

	local function updateView(current, camera)
		if not current.lookPivot then
			local head = current.standIn:FindFirstChild("Head")
			local headPosition = if head and head:IsA("BasePart") then head.Position else current.origin
			local focus = current.focus.Position
			local pivot = if (focus - headPosition).Magnitude <= 6 then focus else headPosition
			local firstPerson = player.CameraMode == Enum.CameraMode.LockFirstPerson
				or (current.view.Position - pivot).Magnitude < 1
			current.lookPivot = if firstPerson then current.view.Position else pivot
			current.firstPerson = firstPerson
			current.freeLook = firstPerson or current.mouseBehavior == Enum.MouseBehavior.LockCenter
			if firstPerson then
				for _, item in current.standIn:GetDescendants() do
					if item:IsA("BasePart") and (item == head or item:FindFirstAncestorOfClass("Accessory")) then
						item.LocalTransparencyModifier = 1
					end
				end
			end
		end

		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end

		local mouseLock
		if UserInputService.MouseEnabled and not guiService.MenuIsOpen and not UserInputService:GetFocusedTextBox() then
			if current.freeLook then
				mouseLock = Enum.MouseBehavior.LockCenter
			elseif UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				mouseLock = Enum.MouseBehavior.LockCurrentPosition
			end
		end
		if mouseLock then
			local mouseBehavior = UserInputService.MouseBehavior
			if not current.mouseLock then
				current.previousMouseBehavior = if mouseBehavior == Enum.MouseBehavior.LockCurrentPosition
					then Enum.MouseBehavior.Default else mouseBehavior
			end
			current.mouseLock = mouseLock
			if mouseBehavior ~= mouseLock then
				UserInputService.MouseBehavior = mouseLock
			end
			local delta = UserInputService:GetMouseDelta()
			if delta.X ~= 0 or delta.Y ~= 0 then
				local view = current.view
				local pitch = math.asin(math.clamp(view.LookVector.Y, -1, 1))
				local tilt = math.clamp(pitch - delta.Y * lookSensitivity, -pitchLimit, pitchLimit) - pitch
				local yawRotation = CFrame.fromAxisAngle(Vector3.yAxis, -delta.X * lookSensitivity)
				local pitchRotation = CFrame.fromAxisAngle(view.RightVector, tilt)
				local pivot = current.lookPivot
				current.view = CFrame.new(pivot) * yawRotation * pitchRotation * (view - pivot)
				current.focus = if current.firstPerson
					then CFrame.new(current.view.Position + current.view.LookVector)
					else CFrame.new(pivot)
			end
		else
			releaseMouse(current)
		end

		camera.CFrame = current.view
		camera.Focus = current.focus
	end

	local function stop(restoreCharacter)
		local current = session
		if not current then
			return
		end
		session = nil
		releaseMouse(current)

		if restoreCharacter and player.Character == current.character
			and aliveRoot(current.character) == current.root and nearPlatform(current) then
			if pcall(current.character.PivotTo, current.character, current.pivot) then
				current.root.AssemblyLinearVelocity = Vector3.zero
				current.root.AssemblyAngularVelocity = Vector3.zero
			end
		end

		local camera = current.camera
		if camera.Parent then
			if camera.CameraSubject == current.standInHumanoid then
				local subject = current.cameraSubject
				camera.CameraSubject = subject and subject.Parent and subject or current.humanoid
			end
			if current.cameraLocked and camera.CameraType == Enum.CameraType.Scriptable then
				camera.CFrame = current.view
				camera.Focus = current.focus
				camera.CameraType = current.cameraType
			end
		end
		current.standIn:Destroy()
		platform.Parent = nil
	end

	local function start()
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local root, humanoid = aliveRoot(character)
		if not camera or not root or not humanoid or root.Anchored or humanoid.SeatPart then
			return
		end
		local origin = root.Position
		local height = math.max(3, humanoid.HipHeight + root.Size.Y / 2)
		local landing = findLanding(origin, character, height)
		if not landing then
			return
		end

		local wasArchivable = character.Archivable
		character.Archivable = true
		local cloned, standIn = pcall(character.Clone, character)
		character.Archivable = wasArchivable
		if not cloned or not standIn then
			return
		end
		local standInHumanoid = standIn:FindFirstChildOfClass("Humanoid")
		if not standInHumanoid or not standIn:FindFirstChild("HumanoidRootPart") then
			standIn:Destroy()
			return
		end

		standIn.Name = "ConnorScanStandIn"
		standInHumanoid.EvaluateStateMachine = false
		standInHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		for _, item in standIn:GetDescendants() do
			if item:IsA("LuaSourceContainer") or item:IsA("Sound") then
				item:Destroy()
			elseif item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = false
				item.CanTouch = false
				item.CanQuery = false
				item.LocalTransparencyModifier = 0
			end
		end

		local pivot = character:GetPivot()
		session = {
			character = character, root = root, humanoid = humanoid, pivot = pivot, origin = origin,
			landing = landing,
			standIn = standIn, standInHumanoid = standInHumanoid, camera = camera,
			cameraSubject = camera.CameraSubject, cameraType = camera.CameraType,
			cameraLocked = camera.CameraType == Enum.CameraType.Scriptable,
			view = camera.CFrame, focus = camera.Focus, mouseBehavior = UserInputService.MouseBehavior,
		}
		standIn.Parent = Workspace
		if not session.cameraLocked then
			camera.CameraSubject = standInHumanoid
		end

		platform.Position = landing - Vector3.yAxis * (platform.Size.Y / 2 + height + .25)
		platform.Parent = Workspace
		if not pcall(character.PivotTo, character, pivot + (landing - origin)) then
			stop(false)
			return
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		if streaming then
			task.spawn(function()
				pcall(player.RequestStreamAroundAsync, player, origin, 2)
			end)
		end
	end

	return {
		start = start,
		stop = stop,
		update = function(camera, root)
			local current = session
			if not current then
				return nil, false
			end
			if root ~= current.root or camera ~= current.camera or not current.standIn.Parent
				or not platform.Parent or not nearPlatform(current) then
				stop(true)
				return nil, true
			end

			-- Keep camera controls around the stand-in if the game's camera stops following it.
			local focus = camera.Focus.Position
			if current.cameraLocked or camera.CameraSubject ~= current.standInHumanoid
				or camera.CameraType == Enum.CameraType.Scriptable
				or (focus - root.Position).Magnitude + 4 < (focus - current.origin).Magnitude then
				current.cameraLocked = true
				updateView(current, camera)
			else
				current.view = camera.CFrame
				current.focus = camera.Focus
				current.mouseBehavior = UserInputService.MouseBehavior
			end
			-- Keep the body on the pad without anchoring its networked assembly.
			current.humanoid:Move(Vector3.zero)
			current.humanoid.Jump = false
			return current.origin
		end,
		destroy = function()
			stop(true)
			platform:Destroy()
		end,
	}
end

local remoteScan = if baseplateMode or battlegroundsMode then makeRemoteScan() else nil

local function makeMissionBanner()
	local height = 64
	local white = Color3.fromRGB(233, 239, 247)
	local cyan = Color3.fromRGB(118, 201, 243)
	local confirmBlue = Color3.fromRGB(53, 172, 234)
	local gray = Color3.fromRGB(148, 160, 176)
	local overlay = create("ScreenGui", playerGui, {
		Name = "ConnorMissionResult",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 32,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	local readout = create("Frame", overlay, {
		AnchorPoint = Vector2.new(1, .5),
		Position = UDim2.fromScale(.955, .42),
		BackgroundTransparency = 1,
	})
	local uiScale = create("UIScale", readout, { Scale = 1 })
	local art = rect(readout, 0, 0, 0, height, navy, 0, 1)
	local strip = rect(art, 0, 4, 0, 42, Color3.fromRGB(5, 13, 22), 0, 1)
	strip.Size = UDim2.new(1, 0, 0, 42)
	fade(strip, 0, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(.12, .13),
		NumberSequenceKeypoint.new(.76, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	local title = create("TextLabel", art, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(7, 0),
		Size = UDim2.new(1, -14, 0, 48),
		Text = "",
		RichText = true,
		FontFace = Font.new(FONT_FAMILY, Enum.FontWeight.Light),
		TextSize = 38,
		TextColor3 = white,
		TextStrokeColor3 = navy,
		TextStrokeTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	local blink = makeReadoutBlink(art, 0, 7, 0, 36, 4)
	blink.layer.Size = UDim2.new(1, 0, 0, 36)
	local fragments = {}
	for _, cut in { { .21, .13, 16, 13, 4 }, { .49, .10, 19, 10, -5 }, { .70, .07, 13, 15, 6 } } do
		local mask = rect(art, 0, 0, 0, 0, navy, 0, 3)
		mask.ClipsDescendants = true
		mask.Visible = false
		local text = title:Clone()
		text.ZIndex = 3
		text.Parent = mask
		table.insert(fragments, { mask = mask, text = text, cut = cut })
	end
	local killer = create("TextLabel", art, {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 45),
		Size = UDim2.new(1, -16, 0, 16),
		Text = "",
		FontFace = font,
		TextSize = 13,
		TextColor3 = gray,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
	})
	local startedAt, successful, lastSize
	local function show(success, killerName)
		successful = success
		local width = if success then 497 else 355
		readout.Size = UDim2.fromOffset(width, height)
		art.Size = UDim2.fromOffset(width, height)
		local result = if success then "SUCCESSFUL" else "FAILED"
		title.Text = 'MISSION <font weight="600">' .. result .. '</font>'
		title.TextTransparency = 1
		title.TextStrokeTransparency = 1
		strip.BackgroundTransparency = 1
		for _, fragment in fragments do
			local cut = fragment.cut
			local x = math.floor(width * cut[1])
			fragment.mask.Position = UDim2.fromOffset(x, cut[3])
			fragment.mask.Size = UDim2.fromOffset(math.ceil(width * cut[2]), cut[4])
			fragment.text.Position = UDim2.fromOffset(7 - x + cut[5], -cut[3])
			fragment.text.Size = UDim2.fromOffset(width - 14, 48)
			fragment.text.Text = title.Text
			fragment.mask.Visible = false
		end
		killer.Visible = not success and killerName ~= nil
		killer.Text = if killer.Visible then "@" .. killerName else ""
		killer.TextTransparency = 1
		startedAt = os.clock()
		drawReadoutBlink(blink, 0)
		overlay.Enabled = true
	end

	local function update()
		if not startedAt then
			return
		end
		local age = os.clock() - startedAt
		local duration = if successful then 4.55 else 2.55
		if age >= duration then
			startedAt = nil
			overlay.Enabled = false
			return
		end
		local pixels = overlay.AbsoluteSize
		if pixels ~= lastSize then
			lastSize = pixels
			uiScale.Scale = math.max(.05, math.min(pixels.Y / 1080, pixels.X / 860))
		end

		local close = math.clamp((age - (duration - .55)) / .55, 0, 1)
		local confirming = successful and age >= 1.03
		local phase = drawReadoutBlink(blink, if confirming then age - 1.03 else age, if confirming then confirmBlue else nil)
		local alpha = (if phase == 4 then 1 elseif phase == 3 then .78 else 0) * (1 - close)
		local blueShift = math.clamp((age - .87) / .20, 0, 1)
		strip.BackgroundTransparency = 1 - .24 * alpha
		title.TextColor3 = if successful then white:Lerp(cyan, blueShift) else white:Lerp(gray, close)
		title.TextTransparency = 1 - alpha
		title.TextStrokeTransparency = 1 - .21 * alpha
		for _, fragment in fragments do
			local showing = phase == 2
			if fragment.mask.Visible ~= showing then
				fragment.mask.Visible = showing
				if showing then
					fragment.text.TextColor3 = title.TextColor3
					fragment.text.TextTransparency = .52
					fragment.text.TextStrokeTransparency = 1
				end
			end
		end
		killer.TextTransparency = 1 - .7 * alpha * math.clamp((age - .20) / .30, 0, 1)
	end

	return { show = show, update = update, destroy = function() overlay:Destroy() end }
end

local function makeBaseplateResults(useTotalKills)
	local banner = makeMissionBanner()
	local closeRange = 11
	local contactWindow = 3.4
	local matchWindow = 1
	local settleTime = .50
	local pollInterval = .10
	local tracked, credits, pending = {}, {}, {}
	local connections = {}

	local function readCount(stat)
		if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then
			return stat.Value
		elseif stat and stat:IsA("StringValue") then
			return tonumber((stat.Value:gsub(",", "")))
		end
		return nil
	end

	local function nearby(entry, now)
		return entry.lastContact and now - entry.lastContact <= contactWindow
	end

	local function recordDeath(entry, now)
		if entry.dead then
			return
		end
		entry.dead = true
		local contacts = {}
		for other, track in tracked do
			if other ~= player and nearby(track, now) then
				contacts[other] = true
			end
		end
		table.insert(pending, { at = now, success = false, contacts = contacts })
	end

	local function untrack(candidate)
		local entry = tracked[candidate]
		if entry and entry.died then
			entry.died:Disconnect()
		end
		tracked[candidate] = nil
	end

	local function observe(candidate, localRoot, now)
		local entry = tracked[candidate]
		if not entry then
			entry = {}
			tracked[candidate] = entry
		end
		local character = candidate.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid ~= entry.humanoid then
			if entry.died then
				entry.died:Disconnect()
				entry.died = nil
			end
			entry.humanoid = humanoid
			entry.lastContact = nil
			entry.dead = not humanoid or humanoid.Health <= 0
			if candidate == player and humanoid and not entry.dead then
				entry.died = humanoid.Died:Connect(function()
					if entry.humanoid == humanoid then
						recordDeath(entry, os.clock())
					end
				end)
			end
		end
		if candidate == player and humanoid and humanoid.Health <= 0 then
			recordDeath(entry, now)
		elseif localRoot and candidate ~= player then
			local root = aliveRoot(character)
			if root and (root.Position - localRoot.Position).Magnitude <= closeRange then
				entry.lastContact = now
			end
		end

		local stats = candidate:FindFirstChild("leaderstats")
		local stat, count
		if stats then
			if useTotalKills then
				stat = stats:FindFirstChild("Total Kills") or stats:FindFirstChild("TotalKills")
				count = readCount(stat)
			end
			if count == nil then
				stat = stats:FindFirstChild("Kills")
				count = readCount(stat)
			end
		end
		if stat == entry.stat and count and entry.count and count > entry.count then
			local delta = count - entry.count
			if candidate == player then
				table.insert(pending, { at = now, success = true })
			else
				table.insert(credits, { at = now, player = candidate, count = delta })
			end
		end
		entry.stat, entry.count = stat, count
	end

	local function resolveKiller(result)
		local matches = 0
		local matched
		for _, candidate in credits do
			if not candidate.used and math.abs(candidate.at - result.at) <= matchWindow
				and result.contacts[candidate.player] then
				candidate.used = true
				matches += 1
				matched = candidate
			end
		end
		if matches == 1 and matched.count == 1 then
			return matched.player.Name
		end
		return nil
	end

	local function poll(now)
		local localRoot = aliveRoot(player.Character)
		for _, candidate in Players:GetPlayers() do
			observe(candidate, localRoot, now)
		end
		while pending[1] and now - pending[1].at >= settleTime do
			local result = table.remove(pending, 1)
			local killer = if result.success then nil else resolveKiller(result)
			banner.show(result.success, killer)
		end
		while credits[1] and now - credits[1].at > matchWindow + settleTime + pollInterval do
			table.remove(credits, 1)
		end
	end

	poll(os.clock())
	local nextPoll = 0
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextPoll then
			nextPoll = now + pollInterval
			poll(now)
		end
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(untrack))
	return {
		update = banner.update,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			for candidate in tracked do
				untrack(candidate)
			end
			banner.destroy()
		end,
	}
end

local baseplateResults = if baseplateMode or battlegroundsMode then makeBaseplateResults(battlegroundsMode) else nil

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
	local paper = Color3.fromRGB(251, 252, 252)
	local ink = Color3.fromRGB(11, 17, 24)
	local white = Color3.fromRGB(238, 244, 250)
	local quiet = Color3.fromRGB(164, 178, 191)
	local risk = Color3.fromRGB(247, 184, 72)
	local confirmed = Color3.fromRGB(63, 172, 235)
	local light = Font.new(FONT_FAMILY, Enum.FontWeight.Light)
	local semibold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold)
	local headerWidth, headerHeight = 326, 72
	local rowWidth, rowHeight = 294, 68
	local rowInset, rowGap = 24, 5
	local trim = 22

	local statusGui = create("ScreenGui", playerGui, {
		Name = "ConnorFlagStatus",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
		DisplayOrder = 31,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		Enabled = false,
	})
	local overlay = rect(statusGui, 0, 0, headerWidth + 2 * trim, headerHeight + 2 * (rowHeight + rowGap) + 8, navy, 0, 1)
	overlay.AnchorPoint = Vector2.new(.5, 0)
	overlay.Position = UDim2.fromScale(.57, .225)
	local overlayScale = create("UIScale", overlay, { Scale = 1 })
	local lastSize

	local function label(parent, x, y, width, height, color, size, face)
		return create("TextLabel", parent, {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			Text = "",
			TextColor3 = color,
			TextSize = size,
			FontFace = face,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		})
	end

	local function rails(parent, x, y, width, height, opacity)
		local right, bottom = x + width - 1, y + height - 1
		rect(parent, x, y, 1, height, white, opacity * .63, 3)
		rect(parent, right, y, 1, height, white, opacity * .63, 3)
		for _, edgeY in { y, bottom } do
			rect(parent, x, edgeY, 8, 1, white, opacity, 4)
			rect(parent, right - 7, edgeY, 8, 1, white, opacity, 4)
		end
	end

	local function revealPlate(x, y, width, height, paddingX, color, opacity)
		local fullWidth, fullHeight = width + 2 * paddingX, height + 6
		local mask = rect(overlay, x - paddingX, y - 3, fullWidth, fullHeight, navy, 0, 2)
		mask.ClipsDescendants = true
		mask.Visible = false
		local frame = rect(mask, paddingX, 3, width, height, color, opacity, 2)
		local edge = rect(mask, 0, 3, 1, height, white, .62, 5)
		edge.Position = UDim2.new(1, -1, 0, 3)
		edge.Visible = false
		local blink = makeReadoutBlink(mask, paddingX, 3, width, height, 5)
		return { mask = mask, frame = frame, edge = edge, blink = blink, width = fullWidth, height = fullHeight }
	end

	-- Find Deviant objective: white strip, paired side cuts and offset dark subobjectives.
	local headerPlate = revealPlate(trim, 4, headerWidth, headerHeight, trim, ink, 0)
	local header = headerPlate.frame
	local headerBody = rect(header, 8, 3, headerWidth - 16, headerHeight - 6, paper, .99, 2)
	rect(header, -trim, 3, trim + 10, 1, white, .34, 3)
	rect(header, headerWidth - 9, 3, trim + 9, 1, white, .31, 3)
	for _, x in { 10, 14, 18, headerWidth - 24, headerWidth - 13 } do
		rect(header, x, 3, 1.4, headerHeight - 6, ink, .96, 4)
	end
	rect(headerBody, 117, 0, 36, 2, ink, .93, 4)
	rect(headerBody, 62, headerHeight - 9, 132, 3, ink, .93, 4)
	rails(header, 0, 0, headerWidth, headerHeight, .95)
	local title = label(header, 37, 0, headerWidth - 58, headerHeight, ink, 20, semibold)
	title.Text = "FLAGS"

	local rows = {}
	for index = 1, 2 do
		local y = 4 + headerHeight + rowGap + (index - 1) * (rowHeight + rowGap)
		local plate = revealPlate(trim + rowInset, y, rowWidth, rowHeight, 3, ink, 0)
		local row = plate.frame
		rect(row, 2, 1, rowWidth - 4, rowHeight - 2, ink, .67, 2)
		rect(row, 1, 0, rowWidth - 2, 1, white, .24, 3)
		rect(row, 1, rowHeight - 1, rowWidth - 2, 1, white, .17, 3)
		rails(row, 0, 0, rowWidth, rowHeight, .57)
		rect(row, 44, 0, 1, rowHeight, white, .09, 3)
		local role = label(row, 59, 10, rowWidth - 71, 22, white, 18, light)
		local state = label(row, 59, 32, rowWidth - 71, 24, white, 20, semibold)
		plate.statusRail = rect(row, 1, 1, 3, rowHeight - 2, white, 0, 3)

		row.Visible = false
		plate.role = role
		plate.state = state
		rows[index] = plate
	end
	local wanted = false
	local closeProgress = 1

	local function restartBlink(plate, age)
		plate.age = age
		plate.mask.Size = UDim2.fromOffset(plate.width, plate.height)
		plate.mask.Visible = false
		plate.frame.Visible = false
		plate.edge.Visible = false
		drawReadoutBlink(plate.blink, -1)
	end

	local function updateBlink(plate, dt)
		local age = plate.age
		if age == nil then
			return
		end
		local phase = drawReadoutBlink(plate.blink, age)
		plate.mask.Visible = phase > 0
		plate.frame.Visible = phase >= 3
		if phase == 4 then
			plate.age = nil
		else
			local nextAge = age + dt
			plate.age = if age < 0 and nextAge > 0 then 0 else nextAge
		end
	end

	local function closePlate(plate, fraction)
		if plate.age ~= nil then
			plate.age = nil
			drawReadoutBlink(plate.blink, READOUT_BLINK_DURATION)
		end
		if plate.frame.Visible and plate.mask.Visible then
			local width = math.ceil(plate.width * (1 - (1 - fraction)^3))
			plate.mask.Size = UDim2.fromOffset(width, plate.height)
			plate.edge.Visible = fraction < .96
		end
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
		local function show(role, state, takenColor)
			count += 1
			local row = rows[count]
			local changed = not row.listed or row.role.Text ~= role or row.state.Text ~= state
			row.listed = true
			if not changed then
				return
			end
			if wanted and (row.age == nil or row.age >= 0) then
				restartBlink(row, 0)
			end
			row.role.Text = role
			row.state.Text = state
			row.state.TextColor3 = if state == "TAKEN" then takenColor elseif state == "UNKNOWN" then quiet else white
			row.statusRail.BackgroundColor3 = takenColor
			row.statusRail.BackgroundTransparency = if state == "TAKEN" then .16 else 1
		end
		if ownFlag then
			show("YOUR FLAG", ownState, risk)
		end
		if enemyFlag then
			show("ENEMY FLAG", enemyState, confirmed)
		end
		if count == 0 then
			show("", "UNKNOWN", quiet)
		end
		for index = count + 1, #rows do
			local row = rows[index]
			row.listed = false
			row.mask.Visible = false
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
		closeProgress = 1
		restartBlink(headerPlate, 0)
		for index, row in rows do
			restartBlink(row, -index * .045)
		end
		if not statusGui.Enabled then
			startIndex()
			statusGui.Enabled = true
			updateStatus()
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
			statusGui.Enabled = false
		end,
		update = function(camera, dt)
			if not statusGui.Enabled then
				return
			end
			resizeReadouts(camera)
			if wanted then
				updateBlink(headerPlate, dt)
				for _, row in rows do
					if row.listed then
						updateBlink(row, dt)
					end
				end
			else
				closeProgress = math.max(0, closeProgress - dt / .18)
				closePlate(headerPlate, closeProgress)
				for _, row in rows do
					closePlate(row, closeProgress)
				end
				if closeProgress == 0 then
					statusGui.Enabled = false
				end
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
local scanAge = 0
local exitAge
local exitStrength = 0
local strength = 0
local gridDatum
local sampleTimer = 0
local viewport = Vector2.new(1920, 1080)
local lastPixels
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
	tint = Color3.fromRGB(244, 249, 255),
	brightness = 0,
	saturation = -.86,
	wash = .176,
	contrast = .032,
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
	local redCut = math.clamp(.038 + highKey * .035 + warmth * .13, .025, .12)
	local greenCut = math.clamp(.018 + highKey * .022 + greenCast * .11, .01, .078)
	local lift = (.29 - sceneLight) * .065
	local exposure = Lighting.ExposureCompensation * .018

	targetTone.tint = Color3.new(1 - redCut, 1 - greenCut, 1)
	targetTone.brightness = math.clamp(lift - exposure - highKey * .033, -.075, .022)
	targetTone.saturation = -.84 - .12 * math.clamp((chroma / totalWeight - .08) / .48, 0, 1)
	targetTone.wash = .176 - .067 * highKey
	targetTone.contrast = .032 + .026 * highKey
end

local function smoothstep(progress)
	progress = math.clamp(progress, 0, 1)
	return progress * progress * (3 - 2 * progress)
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
			objects = {}, appearances = {}, markers = {}, shown = 0,
		},
		{
			name = "Projectiles", names = { Bullet = true },
			explosive = false, color = warningAmber, limit = 48,
			objects = {}, appearances = {}, markers = {}, shown = 0,
		},
	}
	local debris
	local deadlines = setmetatable({}, { __mode = "k" })

	local function makeMarker(group)
		local marker = rect(layer, 0, 0, 0, 0, navy, 0, 5)
		local art = rect(marker, 0, 0, 0, 0, navy, 0, 5)
		local size = if group.explosive then 4.5 else 3.5
		local shadow = rect(art, -size / 2 - 1, -size / 2 - 1, size + 2, size + 2, navy, .82, 5)
		shadow.Rotation = 45
		local diamond = rect(art, -size / 2, -size / 2, size, size, group.color, .98, 5)
		diamond.Rotation = 45
		if group.explosive then
			scanCorners(art, 13, 5.5, 1.2, group.color, .92, 5)
			scanCorners(art, 9.5, 3, 1, group.color, .30, 5)
		else
			rect(art, -6, -.5, 2, 1, group.color, .52, 5)
			rect(art, 4, -.5, 2, 1, group.color, .52, 5)
		end
		local span = if group.explosive then 26 else 12
		return { frame = marker, art = art, blink = makeReadoutBlink(marker, -span / 2, -span / 2, span, span, 6) }
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
		table.clear(group.appearances)
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
			group.appearances[object] = nil
		end)
		for _, object in folder:GetChildren() do
			track(object)
		end
	end

	local function hideUnused(group, count)
		for i = count + 1, group.shown do
			group.markers[i].frame.Visible = false
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
						group.appearances[object] = nil
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
					local appearance = group.appearances[object]
					if not appearance then
						appearance = { at = now, seenAt = now }
						group.appearances[object] = appearance
					elseif now - appearance.seenAt > .18 then
						appearance.at = now
					end
					appearance.seenAt = now
					place(marker.frame, point)
					marker.art.Visible = drawReadoutBlink(marker.blink, now - appearance.at) >= 3
					if count > group.shown then
						marker.frame.Visible = true
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
			table.clear(group.appearances)
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

local function makeRoomSweep()
	local maxDepth = 74
	local travelTime, holdTime = .51, .15
	local viewColumns, viewRows = 7, 5
	local rayLimit = 44
	local colors = {
		Color3.fromRGB(232, 248, 255),
		Color3.fromRGB(151, 202, 246),
		Color3.fromRGB(198, 228, 250),
		Color3.fromRGB(244, 251, 255),
		Color3.fromRGB(118, 164, 223),
	}
	local pools = { Part = {}, WedgePart = {} }
	local active, rows, visibleDepths, frontHits = {}, {}, {}, {}
	local folder, origin, forward, side
	local elapsed, nextRow, nextProbe, viewProbe = 0, 1, 1, 0
	local pending, direction
	local nearDepth, reach, lead, aspect, viewHeight
	local hasCeiling
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.IgnoreWater = true
	ray.RespectCanCollide = true
	local up = Vector3.yAxis
	local axes = { "X", "Y", "Z" }
	local wallHeights = { -1.6, 1.8, 5.2, 8.6 }

	local function release(index)
		local facet = active[index]
		facet.part.Transparency = 1
		table.insert(pools[facet.part.ClassName], facet)
		active[index] = active[#active]
		active[#active] = nil
	end

	local function stop()
		pending = nil
		origin = nil
		table.clear(rows)
		table.clear(visibleDepths)
		table.clear(frontHits)
		for index = #active, 1, -1 do
			release(index)
		end
	end

	local function arrival(depth)
		local fraction = math.clamp((depth - nearDepth) / (reach - nearDepth), 0, 1)
		return lead + travelTime * (if direction > 0 then fraction else 1 - fraction)
	end

	local function facet(class, center, xAxis, normal, width, length, color, time, opacity)
		if elapsed - time >= holdTime then
			return
		end
		if not folder then
			folder = create("Folder", Workspace, { Name = "ConnorObservationSweep" })
		end
		local item = table.remove(pools[class])
		if not item then
			item = { part = create(class, folder, {
				Name = "ScanFacet", Anchored = true, CanCollide = false,
				CanTouch = false, CanQuery = false, CastShadow = false,
				Material = Enum.Material.Neon, Transparency = 1,
			}) }
		end
		local part = item.part
		if class == "WedgePart" then
			-- A Roblox wedge is a triangle in its YZ plane. The thin X axis points off the surface.
			part.Size = Vector3.new(.022, width, length)
			part.CFrame = CFrame.fromMatrix(center, normal, xAxis, normal:Cross(xAxis))
		else
			part.Size = Vector3.new(width, .022, length)
			part.CFrame = CFrame.fromMatrix(center, xAxis, normal, xAxis:Cross(normal))
		end
		part.Color = color
		item.at, item.opacity = time, opacity
		table.insert(active, item)
	end

	local function clipSpan(point, axis, halfSize, span)
		local lower, upper = -span / 2, span / 2
		for _, component in axes do
			local slope = axis[component]
			if math.abs(slope) > .002 then
				local a = (-halfSize[component] - point[component]) / slope
				local b = (halfSize[component] - point[component]) / slope
				lower = math.max(lower, math.min(a, b))
				upper = math.min(upper, math.max(a, b))
			end
		end
		return (lower + upper) / 2, math.max(0, upper - lower)
	end

	local function paint(hit, tangent, width, length, time, seed, split)
		local normal = hit.Normal
		local projected = tangent - normal * tangent:Dot(normal)
		if projected.Magnitude < .05 then
			return
		end
		local xAxis = projected.Unit
		local zAxis = xAxis:Cross(normal)
		local center = hit.Position
		local surface = hit.Instance
		if surface and surface:IsA("Part") and surface.Shape == Enum.PartType.Block then
			local frame, halfSize = surface.CFrame, surface.Size * .5
			local localHit = frame:PointToObjectSpace(center)
			local localX, localZ = frame:VectorToObjectSpace(xAxis), frame:VectorToObjectSpace(zAxis)
			local shiftX, shiftZ
			shiftX, width = clipSpan(localHit, localX, halfSize, width)
			shiftZ, length = clipSpan(localHit, localZ, halfSize, length)
			-- Guard the diagonal corners when the scan is angled to the face.
			local localCenter = localHit + localX * shiftX + localZ * shiftZ
			local fit = 1
			for _, component in axes do
				local extent = (math.abs(localX[component]) * width + math.abs(localZ[component]) * length) / 2
				if extent > .005 then
					fit = math.min(fit, (halfSize[component] - math.abs(localCenter[component])) / extent)
				end
			end
			width *= fit
			length *= fit
			center += xAxis * shiftX + zAxis * shiftZ
		end
		if width < .18 or length < .18 then
			return
		end
		center += normal * .024
		local color = colors[seed % #colors + 1]
		if split then
			facet("WedgePart", center, xAxis, normal, width, length, color, time, .98)
			facet("WedgePart", center, -xAxis, normal, width, length,
				colors[(seed + 2) % #colors + 1], time + .008, .9)
		else
			facet("Part", center, xAxis, normal, width, length, color, time, .98)
		end
	end

	local function gather(camera, budget)
		local pixels = camera.ViewportSize
		while viewProbe < viewColumns * viewRows and budget > 0 do
			local column = viewProbe % viewColumns
			local row = math.floor(viewProbe / viewColumns)
			local screen = camera:ViewportPointToRay(
				pixels.X * (column + .5) / viewColumns, pixels.Y * (row + .5) / viewRows)
			viewProbe += 1
			budget -= 1
			local hit = Workspace:Raycast(screen.Origin, screen.Direction * (maxDepth + 24), ray)
			if hit then
				local depth = (hit.Position - origin):Dot(forward)
				if depth >= nearDepth then
					table.insert(visibleDepths, depth)
					if hit.Normal.Y < -.48 then
						hasCeiling = true
					elseif math.abs(hit.Normal.Y) < .48 and math.abs(hit.Normal:Dot(forward)) >= .54 then
						table.insert(frontHits, { hit = hit, depth = depth, seed = viewProbe })
					end
				end
			end
		end
		return budget
	end

	local function prepareRows()
		table.sort(visibleDepths)
		local typicalFar = visibleDepths[math.ceil(#visibleDepths * .89)]
		reach = if typicalFar then math.clamp(typicalFar + 6, 22, maxDepth) else maxDepth
		local edge = nearDepth
		while edge < reach do
			local step = if edge < -8 then 5.4 elseif edge < 19 then 3.8 elseif edge < 37 then 5.4 else 7.8
			step = math.min(step, reach - edge)
			local depth = edge + step / 2
			local halfWidth = math.clamp(14 + depth * viewHeight * aspect * .38, 12, 40)
			local columns = math.clamp(math.ceil(halfWidth / step), 3, 7)
			table.insert(rows, {
				depth = depth, step = step, width = halfWidth / columns,
				columns = columns, sideRange = math.min(halfWidth + 2, 42),
				at = arrival(depth),
			})
			edge += step
		end
		if direction < 0 then
			table.sort(rows, function(a, b) return a.at < b.at end)
		end
	end

	local function paintFront()
		for index = #frontHits, 1, -1 do
			local sample = frontHits[index]
			local time = arrival(sample.depth)
			if time <= elapsed then
				local hit = sample.hit
				local distance = hit.Distance
				local height = math.clamp(distance * viewHeight / viewRows * 1.16, 2.1, 10)
				local width = math.clamp(distance * viewHeight * aspect / viewColumns * 1.16, 2.5, 12)
				paint(hit, up:Cross(hit.Normal), width, height, time, sample.seed, sample.seed % 3 == 0)
				frontHits[index] = frontHits[#frontHits]
				frontHits[#frontHits] = nil
			end
		end
	end

	local function probeRow(row, rowIndex, probe)
		local center = origin + forward * row.depth
		local span = row.columns * 2 + 1
		local upper = if hasCeiling then span else 0
		if probe <= span + upper then
			local ceiling = probe > span
			local column = (probe - 1) % span - row.columns
			local anchor = center + side * (column * row.width)
			local hit = Workspace:Raycast(anchor + up * .7, up * (if ceiling then 26 else -25), ray)
			if hit and (if ceiling then hit.Normal.Y < -.48 else hit.Normal.Y > .48) then
				local seed = rowIndex * 7 + column * 3
				local time = row.at + math.abs(column) * .003 + seed % 3 * .006
				paint(hit, side, row.width - .025, row.step - .025, time, seed, seed % 4 == 0)
			end
		else
			local slot = probe - span - upper - 1
			local height = wallHeights[slot % #wallHeights + 1]
			local sideways = if slot < #wallHeights then -1 else 1
			local hit = Workspace:Raycast(center + up * height, side * (sideways * row.sideRange), ray)
			if hit and math.abs(hit.Normal.Y) < .6 and math.abs(hit.Normal:Dot(forward)) < .54 then
				local seed = rowIndex * 9 + slot
				paint(hit, up, 3.42, row.step, row.at + seed % 4 * .006, seed, seed % 4 == 0)
			end
		end
		return span + upper + 2 * #wallHeights
	end

	local function update(camera, position, dt)
		if pending then
			local requested = pending
			stop()
			origin, direction = position, requested
			lead = if direction > 0 then .11 else .06
			local view = camera.CFrame
			local look = view.LookVector
			forward = Vector3.new(look.X, 0, look.Z)
			forward = if forward.Magnitude > .02 then forward.Unit else Vector3.new(0, 0, -1)
			side = forward:Cross(up)
			-- Include the near floor when the camera pulls back from the character.
			local cameraDepth = (view.Position - origin):Dot(forward)
			nearDepth = math.clamp(cameraDepth, -32, -8)
			local pixels = camera.ViewportSize
			aspect = pixels.X / math.max(pixels.Y, 1)
			viewHeight = 2 * math.tan(math.rad(camera.FieldOfView) / 2)
			local excluded = table.clone(probeRay.FilterDescendantsInstances)
			local debris = Workspace:FindFirstChild("Debris")
			if debris then
				table.insert(excluded, debris)
			end
			ray.FilterDescendantsInstances = excluded
			local ceiling = Workspace:Raycast(position, up * 24, ray)
			hasCeiling = ceiling and ceiling.Normal.Y < -.48
			elapsed, nextRow, nextProbe, viewProbe = 0, 1, 1, 0
		end
		if not origin then
			return false
		end

		elapsed += dt
		local budget = rayLimit
		if viewProbe < viewColumns * viewRows then
			local remaining = gather(camera, math.min(budget, 14))
			budget -= 14 - remaining
			if viewProbe == viewColumns * viewRows then
				prepareRows()
			else
				return true
			end
		end
		paintFront()
		while nextRow <= #rows and rows[nextRow].at <= elapsed and budget > 0 do
			local row = rows[nextRow]
			if elapsed - row.at >= holdTime then
				nextRow += 1
				nextProbe = 1
			else
				local count = probeRow(row, nextRow, nextProbe)
				budget -= 1
				nextProbe += 1
				if nextProbe > count then
					nextRow += 1
					nextProbe = 1
				end
			end
		end
		for index = #active, 1, -1 do
			local item = active[index]
			local age = elapsed - item.at
			if age >= holdTime then
				release(index)
			elseif age >= 0 then
				local rise = math.min((age + .006) / .018, 1)
				local fall = 1 - math.clamp((age - .043) / (holdTime - .043), 0, 1)
				item.part.Transparency = 1 - item.opacity * rise * fall^2
			end
		end
		if nextRow > #rows and #frontHits == 0 and #active == 0 then
			stop()
			return false
		end
		return true
	end

	return {
		start = function(inward) pending = if inward then -1 else 1 end,
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

local roomSweep = makeRoomSweep()

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
		drawGridLine(item.post, anchor - postExtent, anchor + postExtent, opacity * .11)

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
		item.dot.BackgroundTransparency = 1 - opacity * .56
		if item.number then
			local index = xIndex - zIndex
			if item.numberIndex ~= index then
				item.numberIndex = index
				item.number.Text = string.format("%05.1f", (84 + index * 1.7) % 100)
			end
			item.number.TextTransparency = 1 - opacity * .52
		end
	end
end

local function refreshEnemyTargets()
	table.clear(enemyTargets)
	local ownTeam = if flagMode then activeTeam(player) elseif prisonMode then player.Team else nil
	if not generalMode and (not ownTeam or (prisonMode and (player.Neutral or not PRISON_ROLE_COLORS[ownTeam.Name]))) then
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
		elseif flagMode then
			local team = activeTeam(other)
			opponent = team ~= nil and team ~= ownTeam
		end
		local root, humanoid
		if generalMode or opponent or (carrier and carrier.character == character) then
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
			for _, panel in visual.colored do
				panel.BackgroundColor3 = roleColor
			end
		end
		visual.root = root
		visual.humanoid = humanoid
		visual.head = head and head:IsA("BasePart") and head or nil
		if visual.character ~= character then
			visual.standardAt = nil
			visual.lastOnScreen = nil
			visual.highlightAt = os.clock()
		end
		visual.character = character
		if visual.warning then
			watchProtection(visual, character, root)
		end
		if visual.highlight and visual.highlight.Adornee ~= character then
			visual.highlight.Adornee = character
		end
		table.insert(enemyTargets, visual)
	end
end

local highlightBlinkAlpha = { .79, .29, .88, 1 }
local function updateEnemies(camera, localPosition, dt)
	enemyRefresh -= dt
	if enemyRefresh <= 0 then
		enemyRefresh = .14
		refreshEnemyTargets()
	end

	local now = os.clock()
	for _, visual in enemyTargets do
		local root = visual.root
		local carrier = flagStatus and flagStatus.carriers[visual.player]
		if carrier and carrier.character ~= visual.character then
			carrier = nil
		end
		if (visual.humanoid and visual.humanoid.Health <= 0)
			or not root:IsDescendantOf(visual.character) or not visual.character:IsDescendantOf(Workspace)
			or (not generalMode and not visual.opponent and not carrier) then
			hideEnemy(visual)
			continue
		end

		local color = carrier and (visual.opponent and carrierOrange or carrierBlue)
			or visual.roleColor or amber
		if visual.markerColor ~= color then
			visual.markerColor = color
			visual.standardAt = nil
			visual.highlightAt = now
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
			visual.highlightAt = now
			visual.highlightStrength = nil
		end
		local urgent = carrier and visual.opponent
		local phase = readoutBlinkPhase(now - visual.highlightAt)
		local highlightStrength = strength * highlightBlinkAlpha[phase]
		if urgent or visual.highlightStrength ~= highlightStrength then
			visual.highlightStrength = highlightStrength
			local outline = urgent and (.87 + .08 * math.sin(now * 5.2)) or (carrier and .92 or .66)
			visual.highlight.FillTransparency = 1 - (carrier and .14 or .075) * highlightStrength
			visual.highlight.OutlineTransparency = 1 - outline * highlightStrength
		end
		local head = visual.head
		local markerPoint = root.Position + Vector3.new(0, 3, 0)
		if head and head.Parent == visual.character then
			markerPoint = head.Position + Vector3.new(0, head.Size.Y / 2 + .55, 0)
		end
		local point, onScreen = project(camera, markerPoint)
		local showingWarning = visual.warning ~= nil and visual.warning.Visible
		visual.marker.Visible = onScreen and (not carrier or showingWarning)
		if visual.marker.Visible then
			place(visual.marker, point)
			local distance = (root.Position - localPosition).Magnitude
			visual.scale.Scale = math.clamp(1 - distance / 340, .45, .92)
			if carrier then
				visual.standard.Visible = false
				drawReadoutBlink(visual.standardBlink, -1)
			else
				if not visual.standardAt or now - visual.lastOnScreen > .18 then
					visual.standardAt = now
				end
				visual.lastOnScreen = now
				visual.standard.Visible = drawReadoutBlink(visual.standardBlink, now - visual.standardAt) >= 3
			end
			if showingWarning then
				local rightSide = point.X < viewport.X - 42
				local showPanel = rightSide and point.X < viewport.X - 137 and distance < 165
				visual.warning.Position = UDim2.fromOffset(rightSide and 23 or -42, -9)
				visual.warningPanel.Visible = showPanel
				if not visual.warningAt then
					visual.warningAt = now
				end
				if visual.warningWide ~= showPanel then
					visual.warningWide = showPanel
					visual.warningBlink.layer.Size = UDim2.fromOffset(if showPanel then 127 else 20, 20)
				end
				visual.warningArt.Visible = drawReadoutBlink(visual.warningBlink, now - visual.warningAt) >= 3
			end
		end
	end
end

local function resetScanOrigin()
	scanStarting = true
	scanAge = 0
	exitAge = nil
	gridDatum = nil
	sampleTimer = 0
end

local function stopScan(restoreCharacter)
	scanEnabled = false
	scanStarting = false
	exitAge = nil
	strength = 0
	if remoteScan then
		remoteScan.stop(restoreCharacter ~= false)
	end
	projectileScan.stop()
	roomSweep.stop()
	if flagStatus then
		flagStatus.close()
	end
	table.clear(enemyTargets)
	enemyRefresh = 0
	markerLayer.Visible = false
	hideEnemies()
end

local function render(dt)
	if baseplateResults then
		baseplateResults.update()
	end
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = aliveRoot(character)
	local position = root and root.Position
	if remoteScan and scanEnabled then
		local remotePosition, relocationEnded = remoteScan.update(camera, root)
		position = remotePosition or (root and root.Position)
		if relocationEnded then
			resetScanOrigin()
		end
	end
	if not camera or not root then
		exitAge = nil
		strength = 0
		if scanEnabled and not scanStarting then
			resetScanOrigin()
		end
		projectileScan.stop()
		roomSweep.stop()
		if flagStatus then
			flagStatus.close()
		end
		hideEnemies()
		gui.Enabled = false
		grade.Enabled = false
		return
	end

	local active = scanEnabled or exitAge ~= nil
	gui.Enabled = active
	if not active then
		grade.Enabled = false
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

	if scanEnabled then
		sampleTimer -= dt
		if sampleTimer <= 0 then
			sampleTimer = .22
			sampleSurroundings(camera, pixels, position)
		end
	end
	if scanStarting then
		scanStarting = false
		roomSweep.start()
		if flagStatus then
			flagStatus.open()
		end
	end
	if scanEnabled then
		scanAge += dt
		strength = smoothstep((scanAge - .11) / .29)
	else
		exitAge += dt
		strength = exitStrength * (1 - smoothstep((exitAge - .12) / .42))
	end

	local sweeping = roomSweep.update(camera, position, dt)
	if exitAge and exitAge >= .64 and not sweeping then
		exitAge = nil
	end

	grade.Enabled = strength > .002
	if grade.Enabled then
		local adjust = 1 - math.exp(-dt * 8)
		tone.tint = tone.tint:Lerp(targetTone.tint, adjust)
		tone.brightness += (targetTone.brightness - tone.brightness) * adjust
		tone.saturation += (targetTone.saturation - tone.saturation) * adjust
		tone.contrast += (targetTone.contrast - tone.contrast) * adjust
		tone.wash += (targetTone.wash - tone.wash) * adjust
		grade.Saturation = tone.saturation * strength
		grade.Brightness = tone.brightness * strength
		grade.Contrast = tone.contrast * strength
		grade.TintColor = neutralTint:Lerp(tone.tint, strength)
	end
	wash.BackgroundTransparency = 1 - tone.wash * strength
	gridLayer.Visible = strength > .006 and gridDatum ~= nil
	if gridLayer.Visible then
		updateGrid(camera)
	end
	if scanEnabled and scanAge >= .33 then
		projectileScan.update(camera)
		markerLayer.Visible = true
		updateEnemies(camera, position, dt)
	elseif scanEnabled then
		markerLayer.Visible = false
	end
	if scanEnabled and flagStatus and scanAge >= .61 then
		flagStatus.update(camera, dt)
	end
end

local playerConnections = {}
local function refreshRoster()
	enemyRefresh = 0
end

local function watchPlayer(candidate)
	local candidateConnections = {
		candidate.CharacterAdded:Connect(refreshRoster),
		candidate.CharacterRemoving:Connect(refreshRoster),
	}
	if not generalMode then
		table.insert(candidateConnections, candidate:GetPropertyChangedSignal("Team"):Connect(refreshRoster))
		table.insert(candidateConnections, candidate:GetPropertyChangedSignal("Neutral"):Connect(refreshRoster))
	end
	playerConnections[candidate] = candidateConnections
	refreshRoster()
end

local function unwatchPlayer(candidate)
	for _, connection in playerConnections[candidate] or {} do
		connection:Disconnect()
	end
	playerConnections[candidate] = nil
end

local function toggleScan()
	if scanEnabled then
		local canReverse = scanAge >= .12 and gridDatum ~= nil
		exitStrength = strength
		stopScan()
		if canReverse then
			exitAge = 0
			roomSweep.start(true)
		end
	else
		scanEnabled = true
		resetScanOrigin()
		if remoteScan then
			remoteScan.start()
		end
	end
	playScanSound(scanEnabled)
end

local rightClickStartedAt
local rightClickTravel = 0

local function onInputBegan(input, handled)
	if handled or UserInputService:GetFocusedTextBox() then
		return
	end

	if battlegroundsMode and input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightClickStartedAt = os.clock()
		rightClickTravel = 0
	elseif not battlegroundsMode and input.KeyCode == Enum.KeyCode.Q then
		toggleScan()
	elseif input.KeyCode == Enum.KeyCode.E and scanEnabled and not scanStarting and flagStatus then
		local camera = Workspace.CurrentCamera
		if camera and aliveRoot(player.Character) then
			flagStatus.toggle()
		end
	end
end

local connections = {
	UserInputService.InputBegan:Connect(onInputBegan),
	player.CharacterRemoving:Connect(function()
		if remoteScan and scanEnabled then
			remoteScan.stop(false)
			resetScanOrigin()
		else
			stopScan(false)
		end
	end),
}

if battlegroundsMode then
	-- A tap toggles analysis. Holding or dragging still controls the camera.
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if rightClickStartedAt and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Delta
			rightClickTravel += math.abs(delta.X) + math.abs(delta.Y)
			if rightClickTravel > 6 then
				rightClickStartedAt = nil
			end
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input, handled)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
			return
		end
		local startedAt = rightClickStartedAt
		rightClickStartedAt = nil
		if startedAt and os.clock() - startedAt <= .35 and not handled and not UserInputService:GetFocusedTextBox() then
			toggleScan()
		end
	end))
	table.insert(connections, UserInputService.WindowFocusReleased:Connect(function()
		rightClickStartedAt = nil
	end))
end

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
	if remoteScan then
		remoteScan.destroy()
	end
	if baseplateResults then
		baseplateResults.destroy()
	end
	projectileScan.destroy()
	roomSweep.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	for candidate in playerConnections do
		unwatchPlayer(candidate)
	end
	hideEnemies()
	highlightFolder:Destroy()
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

-- Connor's character-specific Mind Palace events from Detroit's sound bank.
task.defer(prepareScanSound, scanOnSound, "connor-vision-mind-palace-enter-v1.mp3", 90400, [[
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
yoe/kLI16sk8jtPPri6UU+CRYVBwJGJyMe4QkD6oeaBFIpSxrsSA3FdsjVZAyAAAKAM6ghZ3DsTIDXVHNcjyjrPxUr////7kXAhTVSAG3JWphsQSjKW6QmKB
84hADMgABNsFQKLWpmTyh5smpJAJ8IuICoa2bNcy1fI9cv/7VGT3ABHnM8frIRpIHiB4rGMYAQdkWRUshGeAgIJiMawAEAAALIDaA00bBoSuEFaRdjsza6mg
U66Ed1n51LaA4Lt7V7kqxAQBKEANCWWzCiYReNLf0Xu6gwkkgXAllv/SNedUK/+iIBBBoYSABiG4oqsga89CQ+3Glwh/3pFt7GqGPWGFBhSKTEFNRTMuMTAw
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMf/7ZGTpgBHgBEVjMEiAEcB4qGWPAQggdxON4GCAcgGh4ae8ADAwqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqv/7VGT5gFHZG8TjQBowHAB4e2xvAAZoDxMsMAIAjoHhYYYkAKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAw
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMf/7JETwh3EGA8RLARgAHKBIvGBgAQA4BQwBAAAgCYDhgCAABDAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0
gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQA
AAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAA
AQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAI
AAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AA
AGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7
FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAw
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFN
RTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0
gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQA
AAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAA
AQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAI
AAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AA
AGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7
FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAw
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFN
RTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0
gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQA
AAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAA
AQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAI
AAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AA
AGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7
FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqg==
]])

task.defer(prepareScanSound, scanOffSound, "connor-vision-hostage-observation-exit-v1.mp3", 16899, [[
SUQzBAAAAAAAWVRJVDIAAAAtAAADQ29ubm9yIGFuYWx5c2lzIGV4aXQgLSBUaGUgSG9zdGFnZSBnYW1lcGxheQBUU1NFAAAADgAAA0xhdmY2My4xLjEwMgAA
AAAAAAAAAAAA//tUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAWGluZwAAAA8AAAAYAABBoAARERERHR0dHScnJyczMzMzPT09PUdHR0dTU1NT
U11dXV1nZ2dnc3Nzc319fX2JiYmJk5OTk5Ofn5+fqampqbW1tbW/v7+/y8vLy9XV1dXV39/f3+vr6+v19fX1/v7+/v////8AAAAATGF2YzYzLjEuAAAAAAAA
AAAAAAAAJAYwAAAAAAAAQaCGhbOb//vkZAAAATYGydUkAAgjQIlNpgABHVF5ObncEgNcLaW/PUJBAAOq7x0ABG3RAFAQBAkiQEiCDhO8QHBO8H05eCH1CN4I
HPlHc/BAAABNO3jgAACOjHAAQAAAhMcBMPvlwQBDLg+D5/EAIO++IJQAAVm1TGNZPuSyOZOgULAmYximcPAgbMCIaJJEGIgYZg6nGCmLMIgMMNh0Mdw7MFgI
gUwqBBq4gBEwKARb5CMtslYDRoDAYhS6PRd/EUFVURIdjDQ5xBR9FY14ilHW9nEOWKzzpuxl7VQxlUCbLUkwnDi8okEPxl0pPA1JfUI49kDwJD1h0mCXIf5M
yp9nZa4+TuP/DFBGrUOSGzId5509m3nYZ3RzD8S2WVJfqtSy+UwDWlX/zPPn/hhK68zjlutnnMVN7qUm7GVmr///65+v/P+Z5455Xsc/73+yvWqepbynvqxR
n//v//6QAAARE5KDdnEbDLScBQEAjCYD8MMsWUyDEsTMTBGMt4DIwegdjCvAvCAPzC9CuMHUBIw3AQDAHAOFgClqGAIA8UACEwKSAwDTvwNIzAxhYB4ADUnw
MciIuS5Agb3Dshg0HIALCB5EQHcH1FwDKDjJkuGw+QxQI4FyFwZ4PTHaQER6xcYyQGPHPMCcHGOaLKJohxEEg0wiwwRvkgNIkEjRT1zIumh5BNAfRFi8LkHk
0HhdX0U01oKpqUYpl0h58/6/9BjdTVbqUtMzZ//7U6b+hso0SmCAilUAJV7fSXTX7nicGCkSojBLWO/B7FGoyiFLujrjcf+ihQdiEohgiKCwQWIe4cixozll
mF2tGm1P3Gn044kYzoSEGP4QbL6jUmBBODw8iBctiKLq4ROj5FBkfUSNIhJQhRGxdQ/JOJYaLJcXEPUl7xpE8fGRN3cVe+1zUIyIvLfGz28pFTuaABLrtrNr
r7w04WVQeBAKCJB6C1AkJbxtDXU3dYZZrv3HmBeDgiyDAqweMLsMD0Og9EJO5LuYhhQZQ8OQ/ssQz5c1RAt0JDzP4yXe1dJgmxS0gsuyKLpopJgfoRCTVluR
BFoiiNIj0eNFg9OGnGHoUZEoe5CEf3Sf6N30l97c1q1a3tqkMWPf0MWXNABtfsbjiSk5+LADMlHIwic4LNKAb0ziSPNjSqdCamGNAccsw5bN5lp9yCXwXLX8
Q0I5qIi4mkhGlOVrpmDheNLPFxturp8VUGAkjwDPxMwNCIPJ2odSK16nH30RUcSHYjlYZrIqGh2Pa5Ir5Y4whrR7eZWtRIRXjO4MRgcQmSUy//vURMgABCde
0+9lAAiK69pd7KABF3V9Qa1hg+rwr6f1nDA928uttjo3QofcatpTxx/Lp0x/E/7EEC5b+L9iuX1Dh2cFhCfPWIopbJ697I1UCtjVlKH5yrbOooFsqpEIESOu
Nxxtx88Mggoz6B1zn40oEphHiWIIOBhl2UKkyEg2IpUNu/TPn0B03AwTXmXlxaIB2XTA2cMSWOEcCwYL+Li0/W9GUzdWJI4B+fF6ITCIVS+gOlLI0Sqj6Iqc
kK47kIZnkVCIZh2uODeixQwnORzRmK1NEkK753BZGBxCZJS2G6569nk9m7IqVhO3IrTy+h/Bz7kHwdnXr0suavYPIJS5FFZSvI1on0qw/WE04ccK4ekYsD0l
PnfVSIUEKW2SRxNKPgbOWIQMUAICbUOSmgJ0CsTWDHBiRBASk4LXFvrpVwVCMNawwmJQ4/hYHkJSc0JaKIvKjN1bRPV8gHBy68VGjB9B2V/oLFFzSpE2mSGv
Fc/SU88gZaK8JnC1a2ukdUqMj1hl1QyhHamqruujM7Lqc04MiW00tQr3vHy63dNI3EO7biWqf37fNt+vba/xt23u6dy8yhVx7SnaFpip3Q/Qji65YjU/IGAB
y2t2Sxtyc0MMAhjRDmkGuCF4QoqQ5CRYv2DhosbHhyK68VL1GGSqyPbSwuV1otH3bhuBpyipJA0aliY6AEwhRvGiQhEJo0bPpiJBAjFYSYomLNjpdY4Zmj2C
0mKjIvMTprSlbgmfNColUTcYiULmXNZkzRPqLMkwHQusdINfa5ZNymhKRZ4swjZ+qZe7fVJqz9JScozqiSM7zhsT3ACMFaLdYgMTHoDkM78xwHPrVa5G0W+Y
RBBAGAKpFm0gL4GuDkhUxVyFzNspSnYgCZO8TpBcGKgAiItEhEkNB78Zn7hb+wgu+wiGo1XrV2pTx1YRiI+WTthEWiaduGBy6tXH7bzT7p0d/cybZ5jVvQLS
KuacpBASrOEaFzcjbu58aZ78fPbnjxZpBAs3MrkzC0tXQztr2uv3//vERPIABW1d0WtYYWqsrAotaSa7FWl3Ra3hgaquMCj1vCT8ubpXmKZ+yuxt+8rYzytv
iJlTNYoXQIjul6oTkRu/WiSxUEu2yW22VtzmDygVMTBhMAiw6SmDApgxOgjNbAcMeOpi3N6wMZd+a8HWeXsinZdEpHGJbP4snj9+C8fBFDZtinN30wqIkJRZ
AbFIrViiJWmCjKElUDQlbpASLhKa5rE7rkMZIR0mkxBRYi2AmIXfvRtkjljhFClyVdKTPpaPkxf+2nbTHZ3cUJV8oRk7qnSnzEUmzk5oYEkVnGG5qQWMXSOm
FJKVOT6IVKRHVQl97pbY1GpOdEeYxCFygNNlvAUTNApMEKB9zKYGpBVISkQhpGUTniTRdWNSNpru1mt9+VRpxK1+Xu5WLzmYmMGBXctxt4YG0Ls8iAsZYKUX
JQNj0IG12C6ExJexjs2pGC1yg0wYxIykwqnDZxxhG2hWMdSk/Vror9DFO3a7B1QnVON4onlwzc3JtXGFrZeh+GKSTqYaQsRe3oihD+VJHZqbWim2KA0aJhWd
t9drdxGuyEimERBxnCgpgLmGICUR5IKjoSV4jxiX6usH0UXoc016J16gpG4kCSBbAbEqs3j1A2qmPeSsEZOLOzMlIoiPIJTLmROLwOiddRDbNW0HvJ6BmSyb
SSVxVm6AYI7WJ/jmLRiWkGShBJ3IEshyk4f94MEJBLImpuGJY5KmXjaqI3IOT/MTLpjpM6Sb4tDce05t9diMmZAp+auWRJIycjEEo4ygMyggw4k0Is+ZJlFr
DsSCCoJRgua8S7lyNfYnRSuGrzS4IIyRCJiAoq0CQVE3FkbAJkIbc/WaIZaGWkLRtR4AMICqhVsUk7vNtpA0o3OZHjSifIYwxHdtHUSenYQh//vURNeAJSZe
UmtYSfif68qPZSafVT15Ra1hJaKOryn9lho90r0kWdLkqpRhZ6FkHQ9BdGkjZU30uppGpCEHam6vT2cuiq2kaiC/mWhbkrEPoidKyFtEgPuZRREikUAb2J3Y
0BN4iHdp0twgcK0RqEDAHqKYIYXZHCg6McCKpqRy7JSEFEwzttaRNqO8KjM/PgTKC5MoIBmbq0h+Sjg/fMCoHTBVK37CZLxFedyNp8kLInS4zEOp7hm481bT
h98llPWoMbJNe03rCy2jXU5IiqGVRlMc4TFQHujbrHxRSszZ6YkacRLFKUeJQhhRh88tqLXrJlmM0R+4t+13sHdn0tEim57q8IiqAK/sTkjSRb5kc8ZQmHMh
bpBCcnAEI2I+FDHVAoQomwVTFZLw7YzBL9C1JAfnx+Uw+MsLZuSzI1lE6crD8fyc/tmYBGOCQWWSZ6a5adYXPsrj1pCWu3mFq9Icry6D1zz8ea7Q+y3/b2eh
f3M5jduZQw3P07on09bVRjjSzqe2cr5rtecjruT1JmtGv29KUij46ruWjVNy9rRNUnB7rat95UpgPrPNAqYtNxspJFQTEOPLViDwMIE3aSY6hKRJzGmOq+Yk
X9Zvf4tB33BFgljZEAMcHyBNxYbkmSFg8T9UDYrSqkrmibUQkYRnFosgQpG1cMIllzK82PK06XXxZZO5yheQSyntYsNxisT1G4IF02l0l5tum1c1/K0oVU2W
daIaZ8Y+SXULSH/0CUsleYy5R1+aOUUV3UzQomkmmKyBc1UrXbawoCJnElImUglzd7TXz0dDIFxUgDoACpmZCGPFNKkRIAA2FMLGsIYTVcn8XxSzc3otZELO
Qf9nBOrmO7cIETDa5uSjisafJETxvUSGkMsqFEUF4kcfCOkQWu6JpGtbXoTEEsRTh1CsYWwKGHllaUatH3l5xi7rVO9hnmFJ+ePrTlomFg8rFdtvEgHFlPma
Zj3/qSZ/Of/ubrAVCJ1oLyYJen4CsUFAdmcZXKnyNCN+zEQGSPbO//vERPwABSld0Wt4YHqfi+odYYmBVel3Q609i+KVL2n9liY9yt/btZO0owW0nDQZNQNH
APHd0YQXMAxkGlKm5o+x0tA7KHJ/KMcICWKBy86dcENcck3GywV05yMWzu96XjOkS9UakMfYh0VIK95exewoWIVkLliDEvfTHmf2+vf7VJi89Akcc/8T8GQs
SY8yiUeS1/UE1rnDJ0pWeSWlyAfi0rT1Kew0RIlYb5fP//JhRLZpkF+7ySBVqeXEARsWfPes+ANVAjKGYzVZGnC1zwMgKoAQUUSGYIGTGmcjsnmQUSQkSRLq
pXNOTwk1VLykvQ0y2zAL0UnJa/4JmTLJkFg/ElFJETLejBFIfH1QCBeDMpkwKsbzKIsY0EUabRuNWkkkYErIoTJu2WkvNpEy8r2HKqdQrkpbSsUVo6Qusn6q
jQ6HhFJU1QsHyMSOup03/Hfi+w/ld32chpOfRe1kBZSq1QFhWaTAAeXKnbyeNMApK8KqqrrkqSxyDCaBdAkqFUEvRIY0iQuUaYQQMscOHbM6bpL9076bC6Cc
mirCTohXHMbCtSsVYcV2vNLCsqlsLklm/cWHijl3FfZyasyFTomalZqUXbhFpfF/Cg+E1PU6yvLvGrbykVv29h0ix2U6jFUVTwRVcO0mUX0b/lk318sp7Sl5
9U0MdPxysMz/x/915OBwpJjsTBrofS7IkQqOSLgRrEvDxFzmsj5y4xkhRkQ7cjGkx6GIBAkkRfCDikgMDhSJYEAPOocy8AgFyxFd76XXjadJM7Vvr4yWzXrt
CdUfD4zYY8YqFE1S5UUqaN0jcLSRqIxKsKwTQkQiRka5amU1mFLQ0e1BpmSNE8zaRUmwMqGt2yMjxTlJpGvDZJIp2Rn5xpRQQIBYkyr2P/jW//vERO0ABU1d
0ntYSXiiC5pPZeaPVSF7Ue0k16Kiruj1rDA973/9tCGu9eTezBiR5M9O7JLIBhhiAqIx9ghALWVbldbkZdPSKBw0zrMsQvwzlENUoTacN9HiQiOAhHJFLKaQ
s/aW7KUpH5AOT4SWD5TaEqEgtlkG5XORHJQxPDvl666+XimXSnUabsuOP105w9PDsX+kdhUTa6G8rgccOosLzqSB/26MLDjk6hfRklbqlVnU28U7RqPZpmvz
bZcjh1+jlJQ1/ankf1k69v/f5+lObiqsjRuy7jvLEx/Bdv1iGrriE0gpFQVni5dXj62aN4wX2DzMrxxMk0VTQYpQGJ3hUuMjRCKCDClSmSaJAH0Hei0srGJM
KIf+j7NFCJW03lBO9MCRtsYBMcZTRlrC6YMAw2REdkJIueioQgGMAtLVp0iz71pyQmkIpf3xyagMqvHCRf0QkTkMD/TmiKCZGOrd0Ukn5Uzq5+vTooXjxbeq
6/5u9+EJ5nylt19f6n71x5AasLV+VyTF87v+10wgHZIl3dnu+2lvJKZIFMuDNokTDNQQIlEiCw9DmlKKjRwIupgybshcpsNM/T616CXsnnYk02gix40ZaSmM
KSgkmJcvQ9eb5YDQom5+gsJD9x1JWV4qN1ZWedbWpz1FXNXlGJXvyqUJOvG47Kk5FRTfTjGmpIZJZRlbXEDx42W9YVjWnGEJyDSik4pvgvf7/k4T7PvI3knp
VQpFvzy3/UJBTsZSR9ORdFAFSamWp4+tukvNZwTGAUkwZAMUlZIwiRIYyoAWMmRAjQRfbIknGHt/URpWe68rqRiABUtPgECSdEwcjE7OCWXk8DlEcMLMa7DM
9I2IfykIpqiftYwHQzq/R/zw5puNz8B9LWNst2rKyBY4//vURNwABTZe1PtPS0qnS/qfaYmpFRWBVe0w0+KTsCp9p5n82ufo99r1VXuzct5rNaMpHFjSyVZa
7XK2EERF12LS0tyKkbYOXLppcsSkmgLrEb6byeElZCk9jsRITTfPc4jQGaw7O7t//7JMarMXHMwjTMEQsyQ4gRJMAIYRBBgilQgTTjXNBDB2CMxu0Wjo1COd
SyIW8UDOfjVHal24scypXECIwIqLAYd6c3kZsmJ8TV1FfOZ5tigS6OjMEFl0u4kbVeog5hzXJ+zKDMc504nUH2nq0xyZzkWxyaVwal5THTdxkOujdxEoq/9i
tMNe733OpoSz+2d3TnxhvaOUKOHJIqhy5hGlAWeIh3ZNW7Y3xP0BlhkwRKhM8iLrmjBmZCDJgRCigoGByYohWudCtNBsCaDI3gnmbwIz0pmunaEFY+iInE4r
raI6CWnchcuwuLh0lKdlqmMgunyxFaM7EU4kIi4SoiKd2ZOmt/hGbaNvJLu7JCjRoHtkKMy8VqNslj527vIIGWIoGtzTSSLe8jEboNdy23bDfnteM31Xi61r
w42+p6vq6ycjhMQnUmWUiAwSAawuUDHm1YMtPNO6v/ddJcB92dmiGIzjZAGl0KxskgQfVTEwwUxS9yEhK9fDKwJHQfOn6ANJbJKAWTEnEW5uibXVNj94wUIF
XlDHIVYXjkRVZBMSQmccPjtVTeaSgjScvJBDplG7bn8Xk7J423BzcLQo14TjybeVnCECFAxJtvKRJSRQmuRjjC82DjzJK6cL1DNOGsU3bEVF4v5/3OG3JT01
ZzI1BUsJibrqIE5UGN5qWh33smjvMJzMGGAhIrPAZGEEhIYRHCgQKh0bxENZWg4RBGKN+77MmsrFh9tM3YLI6wUJBuh2Vk9s6OD05PlNbLrR4fEIfQ0EYTzE
2OEbi4bXspLBhzXu1u7T79UzNbxxTmRxVYbugU+0OQWgXzzEbp8uM83iQ24ASONyXP2tbagaBt1mMQ7eOYBiAcwpcaeMJB5MQglUtuvk/xxM//vERPwABZFf
0/tMTNimq7qfZYl9VTF7U+0w0+K6sCixvDCk0SGlASkXmSC0p8AOeUufNIxoW+ZmMAQmZoGBY0jHIhoEDIKAjTikCsCgSRA8Bw2XCeUxJRnhSDQei2WVB8cr
xOoSxJQ1hFMYW3lq5JrirDVaOwnsxnHMRi1xyqwrm2PIoVF6vHfnc89OLLdeKi1bymA7lFSBqh37rZKWmx0f2t5wtLqy51eud02v33KazH7Rt+xn/vJywmVV
tHTKLFzPV116OuW+ZyftMH96JPGy7m1/3uq/0u6Kf9oGiJl4hY9klbvMqkmBgE1NJFA5uMsCzMgBTy1QDI4EARxAGVQsu7IHNUvaw07GMQPBcJc9d7EJdM0d
I+c5LBtppd4MRataBEFQWxEK0hkGAGUNgs4kD6EUpynLbvun597Cc6QpVsZkywnRhSMNhTZVJWDBpoNpS85TVTMOT+aibYWy+WWX8o/X7me+vFVsnUhBy6mI
kiLT8/SeLo26YpRnLuWyVigD4GuAqQ8Oqs90jjLpprBaMzQ8wCQ1xYCgjGIi2AcgC5gFJR4egyno9T7sZhhy19Q1KbrOkt1oD0oxeTnQ2s9sKiFVEBgt0ZYv
VnWWi3BUmCVJbITrh3Y08t6/3rvLoggXphTbTtWJuVjahtI0Lp3OJ9i7ckxePHd8DYi//ZKtfH9/+IA/CzKZ9dXooo6rWg7Xd5t86uzFAQLIMj9QkCu8TEwr
72Wx3nXAiS0yZARszCMDLOwE0fxSoIEq4IiDBkQIoyhYdhi64o7J7JISohcuJSjD5SP8KMrdUGoj4vURZRqNGDghExEyYA9gSkx+NSRiJ5+yFPqThVT3JtQi
lPxD68XEEn/yRmXuowjYVRToRn2oucGm3Zazafv5syFg//vEROGABUNbVPt4SfqaS2p/aYaZVF11Ve0xMOqPrep9piZksrfuV9I3f+0cShFJ7Br+kZCUOqu6
aBdFBYK+sqhNWf5+mMBUWadldt7N5bwGKAyUMXiNeCmoQpMAKiIkyFlAsQJRCsDWi/zGnPhpz5DL4Or1WomZXdGRwL4TgySpyCd3ML1gPFiykcPQxtHS1waX
Vo7HdYmR0uQoiaaGRbrMp3a69oRtZ1z3tI2VEX8iep12F46nOlxOovAFwsMyHrDQnQ6zuHSbMY5h1mKVzsTXzprV3xBbdosvnVZzUya1vqFu/cV8Y/MSFQN2
i5hlf+z1uc20dywySYIcZRG1Ix4NrRhgKF6hSbhbNHhH9gzSpAvCEnrj1SJ4QEsZQkt4qJT4jnKe+rqFo+WX9OmDmjaxKuQwNvMAkapETgYA1SpSUAbG5AnB
tFJKDM9Kv33USh5WoVeVtRdnUilaKTL1XLyM+MddsUMLPIgWK/zX91bGe9TaQw3Q8YYnE/AfEJ5NWSbpClYSKSYhljMOXfGFuwlAzh2ZHRbo5m7zXQxCADkp
gwBjwaTRpRDMUjwCVe8GgUK2RugpCDq4ChwJC4rjiTyPHUwLQ+CcpXnI2VnzZ0Vy08YuS7JXmJfSCGFPUSB2G66y8CRUiPrxZTaevGuKxZYq6F0icKyB0khG
3V0zGn0F19ojUQCJuLVgiTQYnaSjNNS7EupUqXlKccYC4wFUgPJgRwiIGkFRtunJMJmZJiWAy320SkUVkbI8X82U1EoGk5EQ7P/ZdJOFbTzCGYNMGhBVAo4v
cPQB4WVjiy9qn3Jaw4imk47zBY4APg2LqI6H0iEIpGJmT0d44lASqhm/XL3Wtq2g8LadxomNvqFL8ZilTH3ONG5upcedhu+/WEru//vURNqABTJdVXtMS9qt
q4p/aYl9VbF5Ve1hgeKbrqm1rCS9GVPeYWGdzF+OCNc10o0BdCenm5zS9qZZQiu/m6cQt3viPWx1gs2hXSzMF75FB9qTjPuzqZ+i5Umg7c4vIZaPqohVd4rO
OstMUQsOtSJvp9pZGpVJxTQYcG9hkQJhwBlRh3aOvA9i3rQS6iqpAAaQJFLctCeJi7cIVfwlEXbNS1Ib4JI40Shs4YcTssqseTkOnVQc3HA8wqkKEza6MQiJ
qKRFS9EH6EGjac9IkFQgk6k1Iv/hnZ3paQocmtP3jixPMqJz0hUSseax/x5hJEuzv8El2YrTnurxQydVV3LERMoZQ4yjIGCorYE0mDrx9xE+150xlQI0aWRz
PRNxKcyesMOqRIblxjkU0bDFphiGYqURCL/PCmSgZyMACFw5HQSHx9PbqT6LjMBY0Fi58gUs+hFZxZzB2XaGQPpkfLC+Iq464sLpLRCNVJ3e8EKhuWY736/r
a9XsYg58y/2/15nS7G4ia5lg7k47DwlnVDwXC0f+Yp9X4dTIruz1vmjUd1u2VTPQOmfScCSXVOjs/j5Ejq8KL+WTSIUPusqyvveoSm5pAEjg0MyF0pxWcx8E
tEXzMsda4YMAWBaKRKDM6LUNEYNhjGSzErX830feKVQBJnKisIgSURvKrHq2dHLHB9CwgBkhEr99rtn0Y0bHhAR3UOOKYiOVNUy3vnB01UeqXHuUXxNLybLZ
41f7ZGbYcpjNN9KPUAsVBgPBoUE6EkQRlt6jzyxQkbbSjGJX783FGW/5x9eVzQnQeSy1EwSiZfPYqss+RmERAV9lBo9GkBSaZZDVZU5CXz+BZaYAJqqgq4iX
C1QO6FXhoUxRA4IgDf0u+m+09xRulHAO7EhUWwwcVj8/ZaeqWjslFYmORrTrX152UxxUjwuOCCMCoZ6XjJ1a080HjvlhZJ6krd/m91jrKIN3OhLOVY3N+I51
rB9I3GUfrFljVJh8ALBF4z31f9rxys+/w7Svj/6tu9mt//vERPQABWpdU3tYYGqri6ovaS++VRF9TeyxL+qTrqm9liYtmxIWoSJhPyACUKExIwfPM9EqklOb
iVtLAoDNJR1Q0edjJlOIowEUZTCWNAZMEQEExRLgoZYGiVO1h1AlA4U9TB4y2Q5cHkVCUooUF5+hsutOLAHgIHWFpDmkN6Ml1kglQNlhYMDNSIE3Q0rJYojK
izC/Xkh2beeEIzkg8E/2U8pq8aijhPDRx8VIedbI0yzBlE3sXePw6pn8GlQqSKC94038YhBIu1fhuX6RqqEwvEqiOsims3Etw6SINe58i6oDV3llhlvb1TmN
RgWgQCBCTMGTAxowIwDGBouIyIyRXNHFDoiutT79NGjqcjxMPBNNCrQvVdE8mrDpWJCwf0z9TRZMwtq48IRCGJmeicsOP2keCgQiRA0CbiI9fi6SUOltDRhe
v2lmTjWdlkm2aSTjpSK0kMKdyyFtpEQiIrA3L/9U5K8PVP2zBLJ+q6Y+eiA6M1IyszkhINZKWnHmE403OMC3TXwh32Ck3tDMjbabtvmg8osYDSLZAHeIs1bz
c5OoZr5hgCEJKxxlXuJLBCDcfDn0MlksSWCESS+HKBAkR8+qHlDWwOrOZZRl6NUSBivPBoYUabZHNFabQqsr1kb6K0RhYinzBsCFLJnTRIq20mpMrV8D2y13
tCnbOlN5MqwvPY/ptoin2EPJ3znXX5du8O6T7//3LZpAdcCan/9xWGgww8+186flBDqZmFVt695JwmMO1OYEJAiGPYA+1ADyhGwlkl2mKg26rUX0ZIrJHIfD
lpcghybGt0xGR0USlYPzNcwlK5jk6dEYXqUZdDwfprcvFWt8w4jZcO9TqoWtY19e8tO1q6i3bovq2+rVuQZaBezDGekqMm4bHrsV//vURN6ABTta0/tMTFqg
q9qfZYl9VXVzU+zhgeq0rmp9jLB1zlMFIHC5JZEoWOPtsVmaZK+rrWfNU8d8WRcvbW1dcVrbKv/vV6gJklmFdG6F8/74peu86xE02DxONDurb1/NzntZck8W
A3wRQYg5RODxgo8bsy1xkUaJf0vs2RpcUT2hhl5aVWhPx+YaTBgi85O7HcqktWB9MazaJpcvJ4XmhGxuhcOYYc8yVstMvmK7l5TPlkMxRt681DU5iWoombK6
Y5jmUvjjUCesfZFbEyxAeWjyThYoXLzhyZlp61Jjlz6r81Kp25233rXD89ecbtuvPoBAWUUKlz+FMtzN6oK1OijchBo2Bks21vxliTxhlOCi4OHwsDCyUYMM
mKABgAKQnD2qdhACIK54NXoyxf7O3kg94pJEHRft+reMpdJ2Hzrt7dPsIDojaQSn7SYm/iEBhWqyJQIKhhv2jawLipoGDo+T26ktd39XYXVbCIFhhF4Y5zTK
EzKEVJLNQ74KwFn2DyI66lZw/he42yw7f4PjCMETaOc9WYWszRnnlLMCCI+NibFbXhHFZ0nSWETkISluuu3ctSWMtzJiwYqEhoFSF1QYGNIDMABKDKVBCIc6
cUahlTl52nvw58Qdx2HhCQtLFYGREEhdgari0PI6KF5WK5wvYyD1q6AOSlc1VFkkLamKg9NlUsFSNsp3SciwyyOz2uMsnf/aJg7UW2aurkJaclmmUy2xT0zI
+cbxSZNKLdZcfvX1n+PChbhtu4E+fLBYtx75vJSFTVp8OPbXBeVsaAfeG/wYme2yv3TpTR7RQzMAKffXb1vZuY0CGIiYxkJC4UlOAljehAyyNIJfAgACGAgK
Y6HqVEBxpdG4MZYsHLWXB4el4xMbnsQ5vNwnU3P4kRw/tHoRJP1RZteSwwdq1bRnVlSNJbYHuhEZVs2jdWKVk4kYoto8hIzksDkcMRXP2msqhZb+2WnWLu0g
rjdapWOYjxmOXY9jdV/TLMG79ZX5zf5btWMadHeXbu4k//vERPwABUNd0+t4SfizC6ptaY+fFVFpUa3lg+qeL6o1rDA9UtGW11Yyj/fRYhqytrgKnm+t/l2c
nNNyKBZluQoGBmNwz0uUIZhUMCA441BmSgqQ1l5V0s3pRHHNbEVaRDzoJujegSFc+fjL7pWE47icctfGVZfLY7mhMslM0i47tGtrGcD2mcKnPM6/ja28S/HH
dSyq8wQqdPb6aO7H5PXr/Y/SDXFhdPTZD/e2PpmJ5lyj2XtRpdf73t0161a0aeXMON3WOOQuEp83cxfEjv6jILPNTbLa7lUBJ3hoZV9VsbmOWbMqAMgAMQDF
TqLZCAMkXM8SIBSWAYJTcJgs+SAe8YrzMb1WyLl+rXTOhGluGhiWTzQ8e4yrT+VC4vXcNQs+FYjR9IWlUKUqEMcFqVT21SMjERvlXJOkmehC/39u0prSLGxG
exfqsNKql2+gjDuik3s44lFunMMLtQlLoh9F7lJWenLLooIcWL58zcRFui0YNOFDA4SoUc2CXFJ5RzF+bx7MBNEQ7u8X2fyTnKyY5QUSNwcY1AygETLzCJUG
lBYUeBLvERC5lwwbWbsr502qtgdmTuGzqQVIKGidiOTdstNXSh6XavPtu8uiOTo3UkrM+LvdLAu8UjkbQuraLemP6y27pZUN10/eo9HD3cmDBOzjR6kECry1
qMpREHnwmby9JBQ1pLMPR68QZHHivN8bqkZ8lHKFJAgoqHbIYphyMJKL7PJVqhN7fWTw2xN87R4IUqamMLBREEJBpgY8AXpPahAcUgGTQCpzKXrFRWZzPuDL
odoXiZnZ47VO3jnMZbVdSwLrK5OdKm0CHNv6NxcTA6EY7AQcAXJJtR2CUAs07KHWUvhxPU/psoXyzCjxKwca5m8pqlKzOpN7eq5M//vUROMABV9a1HtPS3qj
C2qfZYidVeF3T61hh+LHLun9nDC9wHR40lNcWnlXffW2fKRyjb95+203HrX+sC7u6YW40OW2UBPWTkXC0/IJMPtUsJWJJsvx/k5iCxAGiOzOyxdJtG+c0Q4e
InTUWMRYKiHhxiMEWB8gpEBABVwo8RCW0WxQ5DgFA4OgBM9prhMxXIr1PpnbZuVTEci6pQByNyoPy0pN2rtnVj4SFY+diWHa02vjERqLNSMTsDFIfllnj+Wn
4eZorQSqcvIspuHLo8h0XVKiOlYou5DbWfAyp41WQ3+7vVyOt59liaTP9CiajtPd0NZhmzdWZkxH4Wn5dPHoVMDLEnsvx/kziOyyAkR1iUVZlLXZzl0Nr40T
jCJA2hjJg5Ei9EQa8UrUMSoOLApUr2dN11iQuqw5sUSvTNxKRQk6ATHRMJsBoVDokaZ+2sinBhYVEBKaGgPQkBDT2RlWBtZ8ZwbVYgpBmrjI8jXg00IRsbLw
hcxbYA6RGUm8l1WZQVhGXHqqAbZqJTK+yQFDFw+fb1LM9g6z8W3hsxbVPXUrdTNV+NDteVwY4uUyhDK103GUMm7Rd/EFzeLgSNFrDI21v8t4OnABBGWYZZC4
IgQYi8RMAFgjELCxCtnWypbNkadDTfWnwtXpom3OFpJMC6gJzYnrH2Ds5JbEDitx55pa4fCU6cr1w9rYG4ITQaYWn6GddoaNFdmGzzC84WmLZ2uw4OTPVdt6
to1ggqyzh/vzb69s8Fv6oBhvkrAhxYOsfE6slrE3vef6RpLTLrMSSK89p8RY8J65Q8wWOK/TLxxi/x2WSBdvcFwEE5Zvdrm42XzhdDJKxJqZAMHS2OERMFC0
DAEGcxEwaFODDSANmjc0ypZLW0TIEhksklaGnvmRNIySzHTDRCOA+IAeE14cWInHw8jIAKNIZgWJyHHQSAJojErCchF1JRi6v//y8dxoFlDzxyjFRxIiI0O3
Y3Nuc4kyJlZK1F1NGDFY8a//98arneMfGqXfz6xe/tqW//vERPkABYNdU/spfPqui1qPZY+fFZF1Ta0l9arYLil1pmJ9u/uej/tmm2lXyzO1UgMWZ7vo/xAn
eJrbQADJ9dnrM5EpzwcgjqIxRlCgRTGkAYJKgoQCjAj2tiESGB0L2qI9vRI3OaAzS3YYhKAHlAuC1QcwiKhRmT6S/FOyYtDysEY4Ep1cxyQXxQrlbcwRVsCH
wrFMoRSdrA7V3KQPQqXDmLcYaerDlOhmvHUcL79W/+ZncebuxgYOu29O1+c1vm+7yxpce09N+sdzmNnss+pPzUs/UxTT0lpJPUqUkrsTtHO2oxR3L+7dPqlv
zlJghUKAFQbPbf9tZa5OcrAmSAwYlAwXEAuJNBiI+FwA1oGBQwCiaMp0XhJhhGgiEgAYCgiiCLaPxMEEhqrka/J3VLCcIQYIRPJhZoJZmOGGaw7OjiM+EseB
+Nwq4iDoOpOMHFQ4iKDYkwm69KfFyJqNUlrHCuWL0jyVvi6uLa8elp3da72SvNltzyG7Zxd6GQ6ZeaTA4E4kkQSCcWCey6dwvWtV0vNRy27dWtgWLGdZOMLD
EbR4asuPDQtKs6i56O0IdDY4qqXqkJYnNCqyjyLgpo8KzxH99yTwJ6ngHzU3e9jyq5b1WmJDJjGVx3JxcClXeATjgVRVB1sKoOIq0Ii77B0taZSrlKMmzzYn
2ZITY+U066Vb5WHbAUBSKvDKumWpuKKmWomBtC6xdF3qSNBSGwjFxI/1E3Mc18z8SMZrHmFHNRUc3////7bPp/FCZyHWHSWWGJTJASLDMik8iUYShiz5mqxu
BS0DAWYmGwwADEgAMPDECCQwACRGDgSBAgFlwS5zXlhUCTAldQo7TBM40gAcMk5CgTmGKIkTNQlPkpaGCFHeOpqSTq2rahrlBRVU//vUZNYABlNeU+t4YlqH
ybqPYeh9GUl7Se49kWJULKo9pg49kWhf1csv2qGUSbxEiCA/MfsPhkXjjKX9xRZcs8uOoLlh6Ov93b3/L06UnXgONqsLJyIZ2Ym5wSzk3Es9gZhJhLffX0Ll
ywdkgf8tGsgcR6XLYV2V7zCRSYbCmoQWG9vSvrEBQkripD1l6hnA9wOfdWAO+3Msk/2ypSgw61gcCOoZKwArgcNQvNMYETAREwocAAMvKX1cdQwt03Vmb9Fa
hF4OxBEU7KZ2mHooJHh6SIbTKyUTH0Olp0yKT7j5eXy2dLFlHH8Yp07M/uV3c3b6uZmW3UseMFzZFgevEKvuZISEaS6yKO/Sv8QXEEYQII0Ax3DvJ41eBBBO
RmgAXEd30CCAA+O/agN9PrN9HGCqZA1n1iZ4Or0eSBLm0osIZgpc8wsJDk0JuqIjX2Huk0xyWQElVo8gsiI5BZCsk8iWp2+ZWqoF1V3uGTWEpK1FkS8/c1Af
diUwMlZ7II3HH1tnrfjM4ql6JHL5DUdV2sEe3i6Ya5NrdBy7mNeWXJzqs8U1dROSl2HJ1n3LTSZmpyqRopKZqexwMF9m8sxdnQdEQS3AiK7xMNKYtecfYH3K
girEQ7LG9kpKplx2duKixoYqKGJiCSRZA0QThKEgjBAGjFgS0bKVOZU1lh7yw5KnIVDlhKIkzh2ERkfTYPtLBsdGVSJpZg5pgihJENEDLyHgmxp5ohh1QfDz
Rwy9ZZdV5O0yOK+hNIjjibwXIPbHqrmxWWznabYOIZKnJzYeTbuMxc7+OzSk8M7EMzy0osinv/B0y7VnF1f7yTdp4mA4uUIQ2icSo0dpSdgfUFgiNMOzs32t
aSojVSPPMpIzGxg77AVBCoETCXhgEsAzZWBOiKNAfdbzLFh5RbbDdmqMIjwJGR8V6BBA5G9RoQkLJSYXZDJCMgksWMqqSXWJRcSCzJDNseXpcZJ22mWcxnYN
Nwn7Ya6BRPs9epdWcItyUR5BOTbJDOI4xrlEdoak7M1Z//vEROsABTldU2t4YHqsi6pvbykvVP15T+3hI+q0ryo9vCS9RZFpFOSr3QjUkY+hjqMlyUot5XXj
Urm6U1jWxHaSV3yVfRAwamBWiYiJeP/rW3jCxEjShpDMJBwsGGCCBnSdFAdQwEt+IAKZJ4L+ZSsWiVmb+XtJhp/7T7QNInthiiYZDhlYRiZGjRiyGI0o2OoU
IfDSp/Om4VNGTSAlbVgXPk2NldewVMsjrMihRGwjchybcCAU0wsrlcqnmE+uX6RG5V0VcYdNRJqiUpJ3ySLEqWImu+UcpZE3sasjEpLWxbY+L5JXpxT1lEfN
/lCbJ4q+BBA1NQFXiIiHb/aRFQyAhMwggg1W8Cidq4GIR0WGkNB59AMLhUEARAXCTZW9FmVu65kfUSbZrqeMqkktpnAqLB8qXkQyEVf6Ydz1TQmotqdUD2KP
jpBOE6iCAmsrTnYalitktMoSswDWQMw+0nchAIJhOK/6uSglhqDoTSaCaGd5tth71Ztf8/9FM86Um/NPWQbJyEsZvmCJucBfzjL6pLOX+xifPtKcBVu4mIiP
/7G5jAFzBwAFJpzEkVIQMY84DkwKfIDQg+huAgiDUtgZPJo7Q3+l7av1yrapmau8sqGplmQVMl2CRYyaQjkxSKWQTDzMYtqICYgscvAxZEjolFAHHESeIVeX
UGe9JNLGHeE/T/q60KIlx/MD4TQzpe234myzf/pe8tOyEhWfOXYI2KQwK9a+GAj7kIZkFLpBMsUvsxhPn2lvMBoe8iYaN/fpLwSTM99BK8zAwzE4xodc4WOG
bBpYCoWlUzYooO88NKZwlHyTukAouCgsqwiFgTvQuGF0GXSO1Abl49SPL639ZFW2N6/WjNn4VamAwxg6EpW48tbQBCIgu6lT0Vij//vURNSABSBe0/tsNNif
zAqfaSanFQF1Ve0w0aqkLuo9piXdSR1GqjGKOoaWnJmC3dESTFGHYG6ZOiYSltJonnnAh6SFIFuyUHFqCUlmpghxvLL8uR+CjDyL9GjKMWwWnB5MK0BuVBHa
cl2Z9t/5HwaDNdtHCZfUxwsSVLHLCgwAMkACEeW7LUPGxNKx/2+B4SMEEAQ5fKI6EsQoQfajXFjyYQYG6UHrZJU5sn2xIwGX9GaAs8srNHkzCBByIoiRHFQy
mSEBKQF5omWZBo4KTKGsq3XsKLSZTfcMX+uTbOKJYZjNeTZLO6fFObSk5ZkNlKWZHGd2L0FR9343HwFRwjZQ/WjjSTcg3NRNGJnwB8kjTb+Oy6ylLCwDnQ5g
m2FnNwM4ADHIg1AlETHNQHPYK6zKG5wC3GpITBwQgIB40TMAs5E+ayhGKUh8QqBIUhUwEoLCcMtBt6GSgkI6L6m2VUTPJWwhhvRNsPQrhkRCboiNlY4u4LI8
Z4xLZp4JF6xJ8aTAEUuWuXIxlPCXOSctHycSS70lr4SWbGV/v/nt5BiYBQNJFmLsCHAsnPgMONMCpFBvzatty2VpUZICHjlQQYMpZGIqON1KASIVcoFAL+qS
vsvbVRVu8E+exj6HZfO2jBUDjB0/1l7MJ02JKRc6XUkZcSH4+vI7LX6ooWF9ksK1yHWP5bBHWD1K5a2WSsWrHUKlrH0RldVOQRJLk54Ci0ygp8s0wKKXPeZR
yWv01V3n9iS82qpsOXMevW+vn35VETZOlI6xQeZ0+TkuYlgoAEiUk5ZJ4sCIAUQIJzEwApAt8FizMDTiBoTS0w0kWpLGchkxQHAGRbDNaVG3VVVZPRFstnC0
yMN4rlGsC5ChjxWmtkMqjIsLlgm2hqTSwlGo8w+pQu0XfVdZq+maOQZISyc0QlDxLNykrRI9r+JMywQO/uRqPUw0xPpp6ZQ+ya2neeK7eVaGf7GOPavvS2is
EvCEohyVDRY6y5qJBfKCl+HGXsaIDXG25LbrbwR8gcdy//vERPgABQ1e02sJNHqdK9pNZYaPVI1/P0yxL+J2rui1hiYVHWIBkJdJjgaIZcjOHFTDd5GgQmU1
Y+2z8tTlxWM0tROogI2AVLAfGZNWJiSKpQTDiyZO55ho4WifQspDowSAr7XZc209xaSmlLi9qjap1DGNZHU2WX9RK/bsYazsI3wOUqknDeKsMKPghz/Hp1iU
ECierUrXrP2Led9e4f3rTcKfP/EVVGId5PNxQhmqZwuqJQK9qLUlsvjhgaxxk5kTgFGmeVgaiMBRkaYMUDiQ0aAgdJFQzGhYK+7stBcpTVpkpHlyFJUtuG2H
tC+dl5oOTBSdIR9OXucvHRyfQkw/FMPpmnUMs+Xn0UK/chzFkbECyq9+JWUli+8Z4xRlUV27VT5Y/WL10MG0l7MJoJJzjGpNRkLOPZJz36LmK7pubVIbBSNu
TTJGc487fcpbBiycjR6BmQeOATOKjHTACcaaMUllnDk4NYG+JmTLCKCJNTmYKlPUwIUFZFWC4iQqjbZi3zsN0X42oHi0cAuWU97E828XJ25JqNcvGk+UUpW2
t1SqmlBeXqCOhndb2weVjxSPon1a2G93DiHHnWC9dqySp3LTy6C5vK+hdlr182WVTtPOwsWassbeOW0Z3WXE9Hprj3VmkFa1za02Yqzm3xu92FlXrS7dn9Jh
v0eI8dOU7+X5z+bQgA5qkW23ZxAiBgEysgsLxhJvkFVhSp1oVQqgDDF7oFXer1/mnLrclrDrMueWsoSBUuCg64QnR1N0xWSpkJmTAwhUZEgoTEy4wKB1YwOK
L02oDDkw8QEk3UulDGqUnSDW1GEeke+EB+bkkWU03dVraWsKm3sIW0JbWw/Sy6aNpdhZpHsGvNVeOvfLJ+772YLQwhXxyPZUXg7d//vERPWABUdeUFNMNPqp
q8oNawwrFP15P01hI+rKLye1p6WtNIUkR1oWxCXLllXH3HgfoYDrKUiUcUnMUMRAOGYBgUhTpTA0SxMSNCy0YFL4QkMxJBIchNzkHyaZOzhQt8ijjZCXmuXI
mIg4/j8NCedcNq4YTxRNiZgkErJAQKi7YiHDgeEgBBAqgNwHGEywww3C1YJUDaJTamodGGQqJpzWliNlhiECVrahdecGFWuZIGLROWWNSUi3irC7MdSfVrP2
BZpjs7HHIdgribdF2kOq6rA9ZEJxPMzFlno0SyMjYPnj8fphOpJlSK2t3hDM18kMEmGHKvBJE1IcwwIQlgh6XgBQ9acCJtsGbI3jiULhyqORSXzkozq32xwK
0xlMsqVYZtNtOSuEPz2purL6OAYRAS60elRrVQSKZsuVghxm6+pdQDQ1Tr4adFvHV7KK0POyaBclCoEOTLgwmkQNWJ6H1MhawKREfVID4lgpJRVJ7lkbkDcb
SkzUanevz3N/hvTorbPadNucYUpGofanXk3C8JIwuDYoVRThbYpmbmGYIYFGGhoYTbjVbclcvHJjNhSvEFhjcDxxvhmiYboQyO5oCFQ4optFcZB1lT0tYctE
C3slhrk6hJwwUa9esypO9l0xIFulSqlmgOlyq2Y/UYikLLcl0JIIp1ccDAg0wtaEqkrtSleKnwMQmFUIUrXq6TNVShyLVLFPaEeaaMhZFFZozuz6aKTll+w+
3wcolC3yUb/rxi6ulUfjayZol5hpbY2z9i3GCmVDvxM60yeQoFYstPbJ2JrI4JCRqgGjGRBLcnMKCFWh0l5jRYF0aRD5ASwe+Ikj5iISgFZsaqCPheoSB6pw
HR1HcSTYcj4rJiEPKKNcW1zPJ+R+39b8VIzs//vURN0ABf9eUGtPT4q2K+oNZemPFUl3PU1hg2qpr2f1rDClllg+LAkQLbN4vULjBQfnSikxXbszKPQ0Ixcp
rl8VrvM6Ln2D6B+mmZ3FzvHLUv1Q0dWSdDscFaLlp0tpS1m/r8p1juT/3XZetcQ4K91fb6r0365T68S9kkLiyjXsH7dVGrbNrWivAAmpEi0k43eZMIao0BwJ
KJMm+R0M7CoYh4GSLnhAFHke1dsgT1gIFAgA8VR/JY5ackZeuH4fR+ODJMoWOKzJGLopep7hwqEMlniqIkWW5fF8UBwiJ5aQDCHvbjrSPxoVnE1gvry6xnsC
/oEWuevfdadosclty8cLb2/fKQW6zdua96e+W6dHSHJ3/bYYhtkU1bhrDB71cO5ghoYwrmsJaI3K0Ti6sCN3XGy1AL1kZbaSTl5ZgHYAU03DANUTAgwoKaGX
cA6EBIOCUCaYkzC4FQrbgrmAhqNuJJYJRUVCUPpOsICpkzuiEstHR8eXWPONPjBMWr1uDrhTWql0ECzyjk36Fft03SmOT1LAkQmDdHrSdWveeAAAXRoKEkNG
I8pXdIOCHL0jodzXM6mc6/LptlEclQtFk0LIIR0dXTl1vvzyjwojIQBGk/TkRw4ZDgaBCEiyJpKJNOTj/U5TZk/OPM0vBoRCgyIMwlpGRaMaYReBJOUtqTY2
oZMBfM6RUCKmUjuc60FEUaVUAYIh8DY7Q6mlSstPHETPTCsA+y02skgD5PJJvEye2g85CkQilOlEqPvuS7c9aQFD8lVSVBrCvWzzk2pJG+Gn7hdeMk8nsZes
7CVzXqnVNT+Ft7up1OzefqPIiXUlxEQFhE/F3L3I6QDjbDgkSabJSMlN2k0lhhgeQEDpiIGugDtiYFkAdGjSIRSAFMZsL6sigCFMlKgeEcK0JIeoFlpBUeZi
QdSWIYhaTVy9yPZ8rFWBl4rE58hFs8s1ydMblWj/1eXt+970TRzd0SWD1pMzZUjSrRpxLD8IqyjpUzdR9c1GCOFknazmDErsjRKC//vEROWABSxcT+ssNHqh
65n9Yel3U+1pOayw0ep9Lqc1hiX0N0kZs7SCUS7bBytjLs24IaZtV1x+3K8mmZ8XVKLqbRBaTalsaMn2rHYhyq1kfOmezEEMS3Hil2YYT8V87sFgOLYUiYcr
SohHSWJVHdXpieF4wVePp0JLw48uathKQ4G7HRWuNRPPGrOkaIjELtjE+j2CJrTyIquwCJQlaLJtomip4lKNSuKHHVTOat43PYtzJU+k+TTLPhCKqU5Hbh3e
nomslbNYysMklryaVj61ZvKpIsz98pNPr7irMoCtHJLW3G7YcCYtKbQ6wZNSF1WCGYOZApioCx5gALuY+ogxdvWUrDOosZxJ2JubH5NZpHhiTUI870MwQSkq
zUQs8hSkTWhwBZjqLBEC4RWJpbFEJg+EOTNbh1QjQNcPkrCzVCpu0pkVxZUmgjTI8kjnnDaOdE3/lAi9LhJkpZzTVTrNFEh0/45W1n/OvfuUiWEsk5GpEhLV
vkkhBq2wtyR2SwKRNCgcg7nIJIHpdhTYulcylYeEvUpaijIXTVCwVlkDsiUPgSDyMKhHAkzh1CJB1o0srRoQnXiYmljJpQeGTICmdlkUKIe+SRb4lcTreD5k
KFGyU0unC0WFtVFIxloKYkaj8SEhSH7wbKvLa883G7N53zP6aP+Ni/nYj5uCRYxZ2/0Vlx3mzmqsIHBsjGSzkkYBhUnIkbaAqQJMRGPXUIAb0y5MBQcFDUtq
OgaFROEwV/lVSoBJUVj5ctdZBqp+s4trWCMkqUq3VtLHROhgvYlKqLvttfZJKJc9azPtXW1xKTXKza3s0eWwu1WnJ7knVLre2vWXV7Gnqwoeyx0FRFPB1BKy
a1qy6NAGJKLgmeRMYYEeZIJzMUHxCiTMcBFL//u0ROCABNNTTWspNciQChmtYSaPTyTlI+zhgeG+mCR1nDA0IrNZU1dhsmHoAIzCkelcR0JThkfJT3P46QIz
lYSi0ujJLxyt5MZfYqvNKtZWu6yuTk2B7F0ZJPrW2toTFCdy36y7Ndy3suoCgF1BoGkFXT3kSSpMQU1FqqpMQU1FMy4xMDCqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq//sUZOGP8AAAf4AAAAgAAA/wAAABAAABpAAA
ACAAADSAAAAEqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
]])

return cleanup
