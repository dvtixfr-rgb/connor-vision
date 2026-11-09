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
local baseplateMode = game.PlaceId == 130960021905304
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

local amber = Color3.fromRGB(238, 185, 43)
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
local lensBlur = create("BlurEffect", Lighting, {
	Name = "ConnorObservationLens",
	Enabled = false,
	Size = 0,
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

local wash = rect(gui, 0, 0, 0, 0, Color3.fromRGB(9, 31, 61), 0, 1)
wash.Size = UDim2.fromScale(1, 1)

local canvas = rect(gui, 0, 0, 0, 0, navy, 0, 3)
local canvasScale = create("UIScale", canvas, { Scale = 1 })
local highlightFolder = create("Folder", Workspace, { Name = "ConnorTeamVisionHighlights" })
local markerLayer = rect(canvas, 0, 0, 0, 0, navy, 0, 6)
markerLayer.Size = UDim2.fromScale(1, 1)
local enemyVisuals = {}
local enemyTargets = {}
local enemyRefresh = 0

-- The observation lattice is anchored to the map and is depth tested with the scene.
local function makeObservationGrid()
	local spacing, height = 11, 10
	local lineRadius, postRadius = 5, 3
	local halfSpan = spacing * (lineRadius + 1)
	local lineColor = Color3.fromRGB(82, 130, 181)
	local pointColor = Color3.fromRGB(105, 154, 204)
	local colorSequence = ColorSequence.new(lineColor)
	local function edgeFade(opacity)
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(.22, 1 - opacity * .72),
			NumberSequenceKeypoint.new(.50, 1 - opacity),
			NumberSequenceKeypoint.new(.78, 1 - opacity * .72),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	local majorFade, minorFade = edgeFade(.53), edgeFade(.30)
	local uprightFade = edgeFade(.34)
	local lines, points = {}, {}
	local anchor, cell, lastEye, lastStep

	local function makeLine(axis, offset, band)
		local a = create("Attachment", anchor, {})
		local b = create("Attachment", anchor, {})
		local beam = create("Beam", anchor, {
			Attachment0 = a,
			Attachment1 = b,
			Color = colorSequence,
			Enabled = false,
			FaceCamera = true,
			LightEmission = .30,
			LightInfluence = 0,
			Segments = 8,
		})
		table.insert(lines, { beam = beam, a = a, b = b, axis = axis, offset = offset, band = band })
	end

	local function createPool()
		anchor = create("Part", Workspace, {
			Name = "ConnorObservationGrid",
			Size = Vector3.new(.05, .05, .05),
			Anchored = true,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			CastShadow = false,
			Transparency = 1,
		})
		for band = -1, 2 do
			for offset = -lineRadius, lineRadius do
				makeLine("X", offset, band)
				makeLine("Z", offset, band)
			end
		end
		for x = -postRadius, postRadius do
			for z = -postRadius, postRadius do
				makeLine("Y", x, z)
				-- Only intersections on the coarser lattice carry a point.
				if (x + z) % 2 == 0 then
					local at = create("Attachment", anchor, {})
					local board = create("BillboardGui", at, {
						Adornee = at,
						AlwaysOnTop = false,
						ClipsDescendants = false,
						LightInfluence = 0,
						MaxDistance = 64,
						Size = UDim2.fromScale(.72, .16),
						Enabled = false,
					})
					local dot = rect(board, 0, 0, 0, 0, pointColor, 0, 1)
					dot.AnchorPoint = Vector2.new(.5, .5)
					dot.Position = UDim2.fromScale(.5, .5)
					dot.Size = UDim2.fromScale(.10, .45)
					create("UICorner", dot, { CornerRadius = UDim.new(1, 0) })
					local number = create("TextLabel", board, {
						Position = UDim2.fromScale(.61, .04),
						Size = UDim2.fromScale(.55, .9),
						BackgroundTransparency = 1,
						Text = "",
						TextColor3 = pointColor,
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						FontFace = font,
					})
					table.insert(points, { at = at, board = board, dot = dot, number = number, x = x, z = z })
				end
			end
		end
	end

	local function placePool(center)
		cell = center
		anchor.Position = center
		local xIndex = math.round(center.X / spacing)
		local zIndex = math.round(center.Z / spacing)
		for _, line in lines do
			local offset = line.offset * spacing
			local band = line.band * height
			local width, transparency
			if line.axis == "Y" then
				local z = line.band * spacing
				line.a.Position = Vector3.new(offset, -height, z)
				line.b.Position = Vector3.new(offset, height * 2, z)
				width, transparency = .012, uprightFade
			else
				local acrossX = line.axis == "X"
				local major = ((if acrossX then zIndex else xIndex) + line.offset) % 2 == 0
				if acrossX then
					line.a.Position = Vector3.new(-halfSpan, band, offset)
					line.b.Position = Vector3.new(halfSpan, band, offset)
				else
					line.a.Position = Vector3.new(offset, band, -halfSpan)
					line.b.Position = Vector3.new(offset, band, halfSpan)
				end
				width = if major then .019 else .010
				transparency = if major then majorFade else minorFade
			end
			line.beam.Width0, line.beam.Width1 = width, width
			line.beam.Transparency = transparency
		end
		for _, point in points do
			local x, z = xIndex + point.x, zIndex + point.z
			local upper = (x * 3 + z * 5) % 5 > 1
			point.at.Position = Vector3.new(point.x * spacing, if upper then height else 0, point.z * spacing)
			point.number.Text = if (x - z) % 3 == 0 then string.format("%04.1f", ((x * 67 + z * 23 + 880) % 1000) / 10) else ""
		end
	end

	local function setLineOpacity(line, alpha)
		local step = math.round(alpha * 48)
		if line.step ~= step then
			line.step = step
			line.beam.Enabled = step > 0
			line.beam.LocalTransparencyModifier = 1 - step / 48
		end
	end

	local function hide()
		if not lastEye then
			return
		end
		lastEye, lastStep = nil, nil
		for _, line in lines do
			setLineOpacity(line, 0)
		end
		for _, point in points do
			point.board.Enabled = false
		end
	end

	return {
		update = function(camera, datum, opacity)
			if opacity <= .012 or datum == nil then
				hide()
				return
			end
			if not anchor then
				createPool()
			end
			local eye = camera.CFrame.Position
			local center = Vector3.new(
				math.round(eye.X / spacing) * spacing,
				datum + math.floor((eye.Y - datum) / height) * height,
				math.round(eye.Z / spacing) * spacing
			)
			local step = math.round(opacity * 48)
			if center == cell and lastEye and (lastEye - eye).Magnitude < .4 and lastStep == step then
				return
			end
			if center ~= cell then
				placePool(center)
			end
			lastEye, lastStep = eye, step
			local localEye = eye - center
			for _, line in lines do
				local p = line.a.Position - localEye
				local d
				if line.axis == "X" then
					d = math.sqrt(p.Z * p.Z + p.Y * p.Y * 2)
				elseif line.axis == "Z" then
					d = math.sqrt(p.X * p.X + p.Y * p.Y * 2)
				else
					d = math.sqrt(p.X * p.X + p.Z * p.Z)
				end
				local weight = math.clamp(1 - (d - 5) / 49, 0, 1)
				setLineOpacity(line, opacity * weight^1.65)
			end
			for _, point in points do
				local distance = (point.at.Position - localEye).Magnitude
				local weight = opacity * math.clamp(1 - (distance - 7) / 46, 0, 1)
				point.board.Enabled = weight > .04
				point.dot.BackgroundTransparency = 1 - .71 * weight
				point.number.TextTransparency = 1 - .43 * weight
			end
		end,
		hide = hide,
		destroy = function()
			if anchor then
				anchor:Destroy()
			end
		end,
	}
end

local observationGrid = makeObservationGrid()


local clueGold = Color3.fromRGB(231, 200, 43)
local clueOchre = Color3.fromRGB(170, 137, 12)
local clueInk = Color3.fromRGB(8, 15, 21)
local lockWhite = Color3.fromRGB(224, 229, 233)

local function clueBodyColor(color)
	return if color == clueGold or color == amber then clueOchre else color:Lerp(clueInk, .26)
end

local function makeClue(parent, size, color, z)
	-- The point below the plate sits on the evidence position.
	local plate = rect(parent, -26 * size, -52 * size, 52 * size, 39 * size, navy, 0, z)
	local body = rect(plate, 6 * size, 0, 40 * size, 39 * size, clueBodyColor(color), .99, z)
	local left = rect(plate, 0, 0, 3 * size, 39 * size, color, .99, z)
	local right = rect(plate, 49 * size, 0, 3 * size, 39 * size, color, .99, z)
	rect(plate, 25.5 * size, 0, size, 39 * size, clueInk, .26, z + 1)
	rect(plate, 20.5 * size, 14 * size, 11 * size, 11 * size, clueInk, .98, z + 1)
	local point = rect(plate, 23.5 * size, 49.5 * size, 5 * size, 5 * size, color, .99, z)
	point.Rotation = 45
	return { plate = plate, body = body, left = left, right = right, point = point }
end

local function recolorClue(clue, color)
	if color == amber then
		color = clueGold
	end
	clue.body.BackgroundColor3 = clueBodyColor(color)
	clue.left.BackgroundColor3 = color
	clue.right.BackgroundColor3 = color
	clue.point.BackgroundColor3 = color
end

local function makeEnemyVisual()
	local marker = rect(markerLayer, 0, 0, 0, 0, navy, 0, 6)
	local visual = {
		marker = marker,
		scale = create("UIScale", marker, { Scale = 1 }),
		clue = makeClue(marker, 1, clueGold, 7),
	}
	marker.Visible = false
	if prisonMode then
		return visual
	end

	-- Use Detroit's locked objective symbol for a target behind a ForceField.
	local warning = rect(marker, 31, -44, 61, 23, navy, .62, 8)
	for _, x in { 0, 60 } do
		rect(warning, x, 0, 1, 23, lockWhite, .57, 9)
		local edge = if x == 0 then 0 else x - 3
		rect(warning, edge, 0, 4, 1, lockWhite, .84, 9)
		rect(warning, edge, 22, 4, 1, lockWhite, .84, 9)
	end
	rect(warning, 10, 6, 9, 1.5, lockWhite, .96, 9)
	rect(warning, 10, 7.5, 1.5, 4, lockWhite, .96, 9)
	rect(warning, 17.5, 7.5, 1.5, 4, lockWhite, .96, 9)
	rect(warning, 8.5, 11, 12, 7, lockWhite, .96, 9)
	create("TextLabel", warning, {
		Position = UDim2.fromOffset(25, 1),
		Size = UDim2.fromOffset(32, 21),
		BackgroundTransparency = 1,
		Text = "[...]",
		TextColor3 = lockWhite,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = font,
		ZIndex = 9,
	})
	warning.Visible = false
	visual.warning = warning
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
	local minimumY = Workspace.FallenPartsDestroyHeight + 150
	local platform = create("Part", Workspace, {
		Name = "ConnorScanPlatform",
		Anchored = true,
		CanTouch = false,
		Size = Vector3.new(64, 2, 64),
		Position = Vector3.new(platformOffset.X, math.max(platformOffset.Y, minimumY), platformOffset.Z),
	})
	local session

	local function nearPlatform(root)
		local offset = root.Position - platform.Position
		return math.abs(offset.X) <= 34 and math.abs(offset.Z) <= 34
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
			and aliveRoot(current.character) == current.root and nearPlatform(current.root) then
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
	end

	local function start()
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local root, humanoid = aliveRoot(character)
		if not camera or not root or not humanoid or root.Anchored or humanoid.SeatPart then
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

		local origin = root.Position
		local pivot = character:GetPivot()
		session = {
			character = character, root = root, humanoid = humanoid, pivot = pivot, origin = origin,
			standIn = standIn, standInHumanoid = standInHumanoid, camera = camera,
			cameraSubject = camera.CameraSubject, cameraType = camera.CameraType,
			cameraLocked = camera.CameraType == Enum.CameraType.Scriptable,
			view = camera.CFrame, focus = camera.Focus, mouseBehavior = UserInputService.MouseBehavior,
		}
		standIn.Parent = Workspace
		if not session.cameraLocked then
			camera.CameraSubject = standInHumanoid
		end

		local pad = origin + platformOffset
		platform.Position = Vector3.new(pad.X, math.max(pad.Y, minimumY), pad.Z)
		local height = math.max(3, humanoid.HipHeight + root.Size.Y / 2)
		local landing = platform.Position + Vector3.new(0, platform.Size.Y / 2 + height + .25, 0)
		if not pcall(character.PivotTo, character, pivot + (landing - origin)) then
			stop(false)
			return
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		if Workspace.StreamingEnabled then
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
				or not platform.Parent or not nearPlatform(root)
				or math.abs(root.Position.Y - platform.Position.Y) > 45 then
				stop(true)
				return nil, true
			end

			-- Keep camera controls around the stand-in if the game's camera stops following it.
			local view = camera.CFrame
			if current.cameraLocked or camera.CameraSubject ~= current.standInHumanoid
				or camera.CameraType == Enum.CameraType.Scriptable
				or (view.Position - root.Position).Magnitude < (view.Position - current.origin).Magnitude then
				current.cameraLocked = true
				updateView(current, camera)
			else
				current.view = view
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

local remoteScan = if baseplateMode then makeRemoteScan() else nil

local function makeMissionBanner()
	local height = 64
	local white = Color3.fromRGB(233, 239, 247)
	local cyan = Color3.fromRGB(118, 201, 243)
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
	local reveal = rect(readout, 0, 0, 0, height, navy, 0, 1)
	reveal.ClipsDescendants = true
	local art = rect(reveal, 0, 0, 0, height, navy, 0, 1)
	local strip = rect(art, 0, 4, 0, 42, Color3.fromRGB(5, 13, 22), 0, 1)
	strip.Size = UDim2.new(1, 0, 0, 42)
	fade(strip, 0, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(.12, .13),
		NumberSequenceKeypoint.new(.76, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	local flash = rect(art, 0, 29, 0, 2, cyan, 0, 3)
	flash.Size = UDim2.new(1, 0, 0, 2)
	fade(flash, 0, {
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(.34, .14),
		NumberSequenceKeypoint.new(.71, .52),
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
	local startedAt, width, successful, lastSize
	local function show(success, killerName)
		successful = success
		width = if success then 497 else 355
		readout.Size = UDim2.fromOffset(width, height)
		art.Size = UDim2.fromOffset(width, height)
		local result = if success then "SUCCESSFUL" else "FAILED"
		title.Text = 'MISSION <font weight="600">' .. result .. '</font>'
		killer.Visible = not success and killerName ~= nil
		killer.Text = if killer.Visible then "@" .. killerName else ""
		startedAt = os.clock()
		reveal.Size = UDim2.fromOffset(0, height)
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

		local open = math.clamp(age / .26, 0, 1)
		local close = math.clamp((age - (duration - .55)) / .55, 0, 1)
		local alpha = math.min(age / .14, 1) * (1 - close)
		reveal.Size = UDim2.fromOffset(math.ceil(width * (1 - (1 - open)^2)), height)
		local blueShift = math.clamp((age - .87) / .18, 0, 1)
		local pulse = math.max(0, 1 - math.abs(age - .94) / .09)
		strip.BackgroundTransparency = 1 - .24 * alpha
		title.TextColor3 = if successful then white:Lerp(cyan, blueShift) else white:Lerp(gray, close)
		title.TextTransparency = 1 - alpha
		title.TextStrokeTransparency = 1 - .21 * alpha
		flash.BackgroundTransparency = if successful then 1 - .46 * alpha * pulse else 1
		killer.TextTransparency = 1 - .7 * alpha * math.clamp((age - .20) / .30, 0, 1)
	end

	return { show = show, update = update, destroy = function() overlay:Destroy() end }
end

local function makeBaseplateResults()
	local banner = makeMissionBanner()
	local closeRange = 11
	local contactWindow = 3.4
	local matchWindow = 1
	local settleTime = .50
	local pollInterval = .10
	local tracked, credits, pending = {}, {}, {}
	local connections = {}

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
		local stat = stats and stats:FindFirstChild("Kills")
		local count
		if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then
			count = stat.Value
		elseif stat and stat:IsA("StringValue") then
			count = tonumber((stat.Value:gsub(",", "")))
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

local baseplateResults = if baseplateMode then makeBaseplateResults() else nil

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
		local mask = rect(overlay, x - paddingX, y - 3, 0, fullHeight, navy, 0, 2)
		mask.ClipsDescendants = true
		mask.Visible = false
		local frame = rect(mask, paddingX, 3, width, height, color, opacity, 2)
		local edge = rect(mask, 0, 3, 1, height, white, .62, 5)
		edge.Position = UDim2.new(1, -1, 0, 3)
		return { mask = mask, frame = frame, edge = edge, width = fullWidth, height = fullHeight }
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
	local revealProgress = 0
	local drawnProgress
	local visibleRows = 0

	local function reveal(plate, fraction)
		local visible = fraction > 0 and plate.frame.Visible
		plate.mask.Visible = visible
		if not visible then
			return
		end
		local eased = 1 - (1 - fraction)^3
		local width = math.ceil(plate.width * eased)
		plate.mask.Size = UDim2.fromOffset(width, plate.height)
		plate.edge.Visible = fraction < .96
	end

	local function drawReveal()
		if drawnProgress == revealProgress then
			return
		end
		drawnProgress = revealProgress
		reveal(headerPlate, math.clamp(revealProgress / .39, 0, 1))
		for index, row in rows do
			local delay = .27 + .23 * (index - 1)
			reveal(row, math.clamp((revealProgress - delay) / (1 - delay), 0, 1))
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
			row.frame.Visible = true
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
			rows[index].frame.Visible = false
		end
		if visibleRows ~= count then
			visibleRows = count
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

local lensCamera, lensBaseline, lensApplied
local function resetLens()
	if lensCamera and lensCamera.FieldOfView == lensApplied then
		lensCamera.FieldOfView = lensBaseline
	end
	lensCamera, lensBaseline, lensApplied = nil, nil, nil
	lensBlur.Enabled = false
end

local function updateLens(camera, amount)
	if amount <= .01 then
		if lensCamera then
			resetLens()
		end
		return
	end
	if lensCamera ~= camera then
		resetLens()
		lensCamera = camera
		lensBaseline = camera.FieldOfView
	elseif camera.FieldOfView ~= lensApplied then
		lensBaseline = camera.FieldOfView
	end
	camera.FieldOfView = math.max(1, lensBaseline - 4.2 * amount)
	lensApplied = camera.FieldOfView
	lensBlur.Size = 5.5 * amount
	lensBlur.Enabled = true
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
			explosive = false, color = clueGold, limit = 48,
			objects = {}, markers = {}, shown = 0,
		},
	}
	local debris
	local deadlines = setmetatable({}, { __mode = "k" })

	local function makeMarker(group)
		local marker = rect(layer, 0, 0, 0, 0, navy, 0, 5)
		makeClue(marker, if group.explosive then .56 else .35, group.color, 5)
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

local function makeRoomSweep()
	local nearDepth, maxDepth = -8, 74
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
	local reach, lead, aspect, viewHeight
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
			local step = if edge < 19 then 3.8 elseif edge < 37 then 5.4 else 7.8
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
			local look = camera.CFrame.LookVector
			forward = Vector3.new(look.X, 0, look.Z)
			forward = if forward.Magnitude > .02 then forward.Unit else Vector3.new(0, 0, -1)
			side = forward:Cross(up)
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
			recolorClue(visual.clue, roleColor)
		end
		visual.root = root
		visual.humanoid = humanoid
		visual.head = head and head:IsA("BasePart") and head or nil
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
			visual.clue.plate.Visible = carrier == nil
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
			local outline = urgent and (.87 + .08 * math.sin(os.clock() * 5.2)) or (carrier and .92 or .52)
			visual.highlight.FillTransparency = 1 - (carrier and .14 or .035) * strength
			visual.highlight.OutlineTransparency = 1 - outline * strength
		end
		local head = visual.head
		local markerPoint = root.Position + Vector3.new(0, 3, 0)
		if head and head.Parent == visual.character then
			markerPoint = head.Position + Vector3.new(0, head.Size.Y / 2 + .55, 0)
		end
		local point, onScreen = project(camera, markerPoint)
		local protected = visual.warning ~= nil and visual.warning.Visible
		visual.marker.Visible = onScreen and (not carrier or protected)
		if visual.marker.Visible then
			place(visual.marker, point)
			local distance = (root.Position - localPosition).Magnitude
			visual.scale.Scale = math.clamp(1 - distance / 285, .43, 1)
			visual.clue.plate.Rotation = (point.X / viewport.X - .5) * 7
			if protected then
				local warningX = if carrier then -30 elseif point.X < viewport.X - 96 then 31 else -92
				visual.warning.Position = UDim2.fromOffset(warningX, -44)
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
	resetLens()
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
		resetLens()
		observationGrid.hide()
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
		observationGrid.hide()
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
		local focus = math.clamp(scanAge / .175, 0, 1)
		updateLens(camera, math.sin(focus * math.pi))
	else
		exitAge += dt
		strength = exitStrength * (1 - smoothstep((exitAge - .12) / .42))
		local focus = math.clamp((exitAge - .46) / .17, 0, 1)
		updateLens(camera, math.sin(focus * math.pi))
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
	observationGrid.update(camera, gridDatum, strength)
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

local function onInputBegan(input, handled)
	if handled or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
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
	observationGrid.destroy()
	resetLens()
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
	lensBlur:Destroy()
	scanAudio:Destroy()
	gui:Destroy()
end

RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, render)
runtime[cleanupKey] = cleanup
if typeof(script) == "Instance" and script:IsA("LocalScript") then
	scriptConnection = script.Destroying:Connect(cleanup)
end

-- Original Observation Mode cues from Detroit's Mind Palace sound bank.
task.defer(prepareScanSound, scanOnSound, "connor-vision-scan-start-v2.mp3", 72673, [[
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
tr8jlkNyOchUP1XLi/7wx/W/7////////////////nhY3bv3scf///////////////6e33WHOU98RCGKEM4M1IEAshMSuOMpI4wtMDFBCml8jORrzTgQzsYE
YyQj5kAoYgJFUkZSYEFFnAMICwKwMKBne7EDiEBASAFrysYEYZsIznFCCGuCIOAo076j6vH4YY1xkcDMim2lPhG7bSmsP6wR9M1WpzLWCpAcFF7iwjkTMQk8
tQgedYRkkjR8tS+Ox+KOjBkVZCpNJNH98Kw8JUX4Z6g8EAoGGO/bd6/LIpLnRfGcp7UXfStk85dCQv2qR8nBVxKKz5P/RXJXSSjGdppqW0c5jNwjdeXw5G5f
DkPwPndsU923nS1offOfqWq3a27Pe6gtR1POC3yrxe9G5TLKGejCf5QPbgGL95r/1j/////////////////91zncuf////////////////9ent5/nynv1RAE
KZfJKVRmN9NTauwUFAwsCaAg0jFZRQMNQHgwIxvSEB0wQgJWUmAGBuRAUmBkA4YEQHJgDAAGAkDSBgTAYBOEBWmA+AoJRgSNpiOC/lMS1LfMRLNw85rPGlWC
/q0kl2itPj7tQtTJE1MtkZa2AWsGAApkXMT7gdr6fd2GGur1lrMXZelxHVfFlFO1/jZYBoIbc+mUbZWy1pvq5RffhQdOWGWgTTet6ilksBDy/Yq9LwupQwKy
xyZ+ESicYC1trzIqLOtbj1aVWqtLuQ1H5v/75ERngAmnc9L+eyCBIm56b87kkBFtZVn9tYAiQa8pv7iAAGZVGIJlzXmbw+yWWNwdKXwXPUEu3TzdJ/YYiT+t
9EINeGBnZpX+eN3IekrIIjJ6nxyTRlw82uORPRi3LJXAUOwZAsPyzlneXcs+8xrf///////////////6c2SS7sC35JFP/2sH3AAC1LOululG02dLI0iENBhY
TwcexjvLhkIHhiCgYyApg8Cb8GCovhg0GLQNGBAYsaCwXmGQJGDwBBw6mDgBiIc1k1+IQFAokcdCoJENAFR+SPaHSNfXQrawBo6qsQSneGXLBFuVjumESpL6
YjBTtN9Zc2LKhmX9ajYbjKYnSOK6MEab+N0M3JI3PRlusRhl5IfcWpLWVv7aoKj/yBlE1KKepIYJiMsuxVgjk097DkExuXRqds1KeANu1PSmklsJpHlgGNRh
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
qqqqqqqqqqqqqqqqqqqqqqqqTEFNRTMuMTAwqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7hET6AAHgHEbtYGAITCMJT6wMAQfQJReZkAABqJqkNzSgAKqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FEThj/AAAH+HAAAIAAAP8OAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7FGThj/AAAGkAAAAIAAANIAAAAQAAAaQAAAAgAAA0gAAABKqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqg==
]])

task.defer(prepareScanSound, scanOffSound, "connor-vision-scan-stop-v3.mp3", 40851, [[
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
S4QKYE10y7sEljDHgE8ZYo62dk0pSpYwMkAgWBhBhwM83aG06W4rYS/IUIhJNE5qDXrpmazcP8lFShYjKcHel1lvn5+Z1KqSg7dkrtQDGIcjEvdmBo/qBqkE
OjHsatBKJZCZXZlcPx+26E6y7d/dvsERfGhmXLYC/1mf7ncrPA0Br8vnIlZv53I9TR6RSbOxcpsMMJfa3btQN2zhjen56cxpMZ7LOzO50/P7Z03da8CWc895
b/DPWH63////////////////IXfpLlrPtfD////////////////lrElSAA4EimDIu0rs43bHACSEQcOCApiOWGBIjOgVUjANgmDMBMDmIqphQgb9FEwYBgw2
sHCgIPYSvYQmOsMavQsCFi5MaTWW2e5iOkAQSMQPLQJcsuYk66c6rXdb1a7ApXHI+/Dd5Y8igbhS2PNgg5pLDWaNajWNnr9v46L3OH7vuguRdkjedh1FEIzG
6J////vkRNUACOeBUf5zQIEfUIn/zegAEoVZU/2XgCpBq2p/sQAAw3RVY++k5flDvcisvyt6pIpJq/Mo3DeVSUQqWfTSOmlVPLHbruG2GgpJdhZtZTUCO/Ib
1Sdv4agqXX79mkpX7s739Hb39NR0uGHe16a9hLJ+1GKevRX8cdXJTNEJc2ZMMSQLnP593lOW9c5c////////////////+7T6/ef87////////////////RSq
ct/rlS+CRTlEU8bttklDthMa0kyoxJoBKmciaBrqCANE1zWUsNaa+N5zlzdDbobtyknu9g5zHmtNJWJqPJCe/eIcWs0eE+t9vYKsvGgQYOcZzX0994zq2/f7
x66m+56avndsZ+calt4OK1tf2tiHAiN75uvB9cwv85+LZ+Pq+P/rWc1/xrWKU194187eq0BpVVbuB1i/N9BpwS3U5uYfa61sgVkpaWnIXhfJoIu5L6FqHFwl
/MCZUwKiftbo+jAgRfFRIMQY2SQNEDJaCjExNympJZgXrKc+xiXDIwUTpgZHVImKE8eNHdbrYyO0kzFS1pooTqKVFExQZFdW1JiyZImKRrNk6ndM4xmXiwmd
WjVrsr7InHV3W3/qS6yiQEKo4kTpor/tLO+PXQOqx7mXfdOMEoy5yYlYwgiC9BbllCBJS4YErrVX++cafuBXPrfEcLtD9bX1c+hZFNA5whZMghv/uFkLbUzz
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
EuYEy0Ng9T2U5JJW7L1Msb1Uqah5dEvu5ilReRb3NUaer1up5AFoq//n2TyqKWWS6Io6WPPHyJb1/4sFixvpGoAA93vsYIHEX/+hRtzWFcSACij+0KZRTFuW
frMDqF2M/Lad9t2s71Z5sQGKJhwea/ocpDixWohVhQM5dSMcVHbGdk7Jq6TOv6iiIZdRZHEhYGGOaKuqPN/zgvjQr+KG+8C6XUWBIfdV29VpuA0oTTFi/49l
a+8F1BmruJrKtMnf//+3KrXR0lW0o1iC4YVFI5zdVL4smHS+aMScoqAQ1vzery34qbEjivUSFoqJWFZH6+v8RG+9AAAAA22AjAAEBCTYVD6i658VGfmf////
8xlY23oi6/tD//ukRN4AhAhfSnnpQfhjChkdQSekDCl7J6CksSFWKGQ0B5XoAX///+0AAC7wACTW2wVyPf0arKxpqzCjf/+o956or0z2xX/Ja8Ju4i///4iV
TEFNRTMuMTAwVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1F
My4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1F
My4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//s0RO6P8TA2yGgDFKAnQyipAMKCAAAB/gAAACAAAD/AAAAEVVVVVVVVVVVVVVVVVVVV
VVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVV
VVVV//sUZOGP8AAAf4AAAAgAAA/wAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVV
VVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBVVVVVVVVV
VVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1FMy4xMDBV
VVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVMQU1F
My4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVMQU1FMy4xMDBVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSAAAAEVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAAACAAADSA
AAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAABAAABpAAA
ACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgAAA0gAAAB
AAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sUZOGP8AAAaQAAAAgA
AA0gAAABAAABpAAAACAAADSAAAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
]])

return cleanup
