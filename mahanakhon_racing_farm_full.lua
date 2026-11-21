-- MAHANAKHON RACING (PlaceId: 104549080643413)
-- Full Multi-System Luau Script (Mobile UI, Loading Screen, Persistent UI, Character ViewportFrame,
-- Single "โหมดทำงาน" Mode Switcher, Random Dropoff Scanner, Vehicle/Care Helper, Quest/Reward Helper, Anti-AFK)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local WORK_MODES = {
	"ส่งของ (Delivery)",
	"ทำงานทั่วไป (Work)",
	"รับ-ส่งสินค้า (PickupCargo)",
}

local EXTRA_SYSTEMS = {
	"สแกนจุดส่งสุ่ม",
	"วาร์ปจุดรับ",
	"กดปุ่มใกล้ตัว",
	"ระบบรถและซ่อม",
	"เควสต์และรางวัล",
	"กันหลุด AFK",
}

local CONFIG = {
	PlaceId = 104549080643413,
	ModeIndex = 1,
	SystemIndex = 1,
	Running = false,
	AntiAFK = true,
	AutoPrompt = true,
	WarpDelay = 0.85,
	StepDelay = 1.0,
	PromptHold = 0.25,
	PromptRange = 28,
	ScanRange = 6000,
	PickupCFrame = nil,
	DropoffFallbackCFrame = nil,
	SafeCFrame = nil,
	DropoffKeywords = {
		"drop", "dropoff", "deliver", "delivery", "target", "goal",
		"marker", "customer", "finish", "end", "point", "dest", "destination"
	},
	VehicleKeywords = {
		"repair", "fix", "care", "vehicle", "car", "pcx", "garage", "dyno", "tune", "fuel", "gas"
	},
	RewardKeywords = {
		"quest", "reward", "gift", "claim", "group", "mission", "daily", "prize"
	},
}

local STATE = {
	Cycles = 0,
	StatusText = "พร้อมเริ่มงาน",
	Minimized = false,
	LoadingDone = false,
}

local PALETTE = {
	Bg = Color3.fromRGB(14, 18, 16),
	Card = Color3.fromRGB(23, 31, 27),
	CardAlt = Color3.fromRGB(18, 25, 21),
	Green = Color3.fromRGB(0, 230, 118),
	GreenSoft = Color3.fromRGB(26, 74, 50),
	Text = Color3.fromRGB(245, 250, 247),
	SubText = Color3.fromRGB(178, 198, 188),
	Red = Color3.fromRGB(235, 77, 75),
}

-- ==================== ฟังก์ชันจัดการตัวละครและฟิสิกส์ ====================
local function getCharacter()
	return localPlayer.Character
end

local function getHumanoid()
	local char = getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart()
	local char = getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function getObjectPosition(obj)
	if not obj then
		return nil
	end
	if obj:IsA("BasePart") then
		return obj.Position
	end
	if obj:IsA("Attachment") then
		return obj.WorldPosition
	end
	if obj:IsA("Model") then
		local ok, pivot = pcall(function()
			return obj:GetPivot()
		end)
		if ok and pivot then
			return pivot.Position
		end
	end
	return nil
end

local function isOwnCharacterDescendant(inst)
	local char = getCharacter()
	if not char or not inst then
		return false
	end
	return inst:IsDescendantOf(char)
end

local function matchesAnyKeyword(text, list)
	if not text or text == "" then
		return false
	end
	local lower = string.lower(text)
	for _, kw in ipairs(list) do
		if string.find(lower, kw, 1, true) then
			return true
		end
	end
	return false
end

local function teleportToCFrame(targetCF)
	if not targetCF then
		return false
	end
	local root = getRootPart()
	if not root then
		return false
	end
	local ok = pcall(function()
		local hum = getHumanoid()
		if hum and hum.Sit then
			hum.Sit = false
			task.wait(0.12)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = targetCF + Vector3.new(0, 3, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	return ok
end

-- ==================== ฟังก์ชันโต้ตอบจุดในเกมและสแกนจุดส่งสุ่ม ====================
local function firePromptSafe(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
		return false
	end
	local ok = pcall(function()
		if typeof(fireproximityprompt) == "function" then
			fireproximityprompt(prompt)
		else
			prompt:InputHoldBegin()
			task.wait(CONFIG.PromptHold)
			prompt:InputHoldEnd()
		end
	end)
	return ok
end

local function fireClickSafe(clickDetector)
	if not clickDetector or not clickDetector:IsA("ClickDetector") then
		return false
	end
	local ok = pcall(function()
		if typeof(fireclickdetector) == "function" then
			fireclickdetector(clickDetector)
		end
	end)
	return ok
end

local function interactWithNearby(maxDistance)
	local limit = maxDistance or CONFIG.PromptRange
	local root = getRootPart()
	if not root then
		return 0
	end
	local triggeredCount = 0
	pcall(function()
		for _, desc in ipairs(workspace:GetDescendants()) do
			if not isOwnCharacterDescendant(desc) then
				if desc:IsA("ProximityPrompt") and desc.Enabled then
					local pos = getObjectPosition(desc.Parent)
					if pos and (root.Position - pos).Magnitude <= limit then
						if firePromptSafe(desc) then
							triggeredCount += 1
						end
					end
				elseif desc:IsA("ClickDetector") then
					local pos = getObjectPosition(desc.Parent)
					if pos and (root.Position - pos).Magnitude <= limit then
						if fireClickSafe(desc) then
							triggeredCount += 1
						end
					end
				end
			end
		end
	end)
	return triggeredCount
end

local function findRandomDropoffCFrame()
	local root = getRootPart()
	local bestPosition = nil
	local bestScore = 0

	pcall(function()
		for _, desc in ipairs(workspace:GetDescendants()) do
			if not isOwnCharacterDescendant(desc) then
				if desc:IsA("ProximityPrompt") and desc.Enabled then
					local pos = getObjectPosition(desc.Parent)
					if pos then
						local dist = root and (root.Position - pos).Magnitude or 0
						if dist <= CONFIG.ScanRange then
							local score = 1
							local parentName = desc.Parent and desc.Parent.Name or ""
							local combined = desc.Name .. " " .. desc.ActionText .. " " .. desc.ObjectText .. " " .. parentName
							if matchesAnyKeyword(combined, CONFIG.DropoffKeywords) then
								score += 4
							end
							score -= math.floor(dist / 600)
							if score > bestScore then
								bestScore = score
								bestPosition = pos
							end
						end
					end
				elseif desc:IsA("BasePart") or desc:IsA("Model") or desc:IsA("Attachment") then
					if matchesAnyKeyword(desc.Name, CONFIG.DropoffKeywords) then
						local hasVisualMarker = desc:FindFirstChildWhichIsA("BillboardGui", true) ~= nil
							or desc:FindFirstChildWhichIsA("Highlight", true) ~= nil
							or desc:FindFirstChildWhichIsA("Beam", true) ~= nil
							or desc:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil
						local pos = getObjectPosition(desc)
						if pos then
							local dist = root and (root.Position - pos).Magnitude or 0
							if dist <= CONFIG.ScanRange then
								local score = hasVisualMarker and 5 or 2
								score -= math.floor(dist / 600)
								if score > bestScore then
									bestScore = score
									bestPosition = pos
								end
							end
						end
					end
				end
			end
		end
	end)

	if bestPosition then
		return CFrame.new(bestPosition)
	end
	if CONFIG.DropoffFallbackCFrame then
		return CONFIG.DropoffFallbackCFrame
	end
	return nil
end

local function runVehicleAndCareAction()
	local root = getRootPart()
	local foundPos = nil
	pcall(function()
		for _, desc in ipairs(workspace:GetDescendants()) do
			if not isOwnCharacterDescendant(desc) then
				local label = desc.Name
				if desc:IsA("ProximityPrompt") then
					label = label .. " " .. desc.ActionText .. " " .. desc.ObjectText
				end
				if matchesAnyKeyword(label, CONFIG.VehicleKeywords) then
					local target = desc:IsA("ProximityPrompt") and desc.Parent or desc
					local pos = getObjectPosition(target)
					if pos then
						foundPos = pos
						if root and (root.Position - pos).Magnitude <= 30 then
							if desc:IsA("ProximityPrompt") then
								firePromptSafe(desc)
							elseif desc:IsA("ClickDetector") then
								fireClickSafe(desc)
							end
						end
					end
				end
			end
		end
	end)

	if foundPos then
		teleportToCFrame(CFrame.new(foundPos))
		task.wait(0.4)
		interactWithNearby(30)
		return "ดำเนินการระบบรถ/ซ่อมเรียบร้อย"
	end
	interactWithNearby(25)
	return "ตรวจสอบจุดใกล้ตัวสำหรับรถ/ซ่อมแล้ว"
end

local function runQuestAndRewardAction()
	local root = getRootPart()
	local claimed = 0
	pcall(function()
		for _, desc in ipairs(workspace:GetDescendants()) do
			if not isOwnCharacterDescendant(desc) then
				if desc:IsA("ProximityPrompt") and desc.Enabled then
					local info = desc.Name .. " " .. desc.ActionText .. " " .. desc.ObjectText
					if matchesAnyKeyword(info, CONFIG.RewardKeywords) then
						local pos = getObjectPosition(desc.Parent)
						if pos and root and (root.Position - pos).Magnitude <= 45 then
							if firePromptSafe(desc) then
								claimed += 1
							end
						end
					end
				elseif desc:IsA("ClickDetector") then
					if matchesAnyKeyword(desc.Name, CONFIG.RewardKeywords) then
						local pos = getObjectPosition(desc.Parent)
						if pos and root and (root.Position - pos).Magnitude <= 45 then
							if fireClickSafe(desc) then
								claimed += 1
							end
						end
					end
				end
			end
		end
	end)
	if claimed > 0 then
		return "กดรับเควสต์/รางวัลแล้ว (" .. tostring(claimed) .. ")"
	end
	interactWithNearby(25)
	return "สแกนจุดเควสต์/รางวัลใกล้ตัวแล้ว"
end

-- ==================== กันหลุด AFK ====================
local function triggerAntiAFKOnce()
	pcall(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end)
end

localPlayer.Idled:Connect(function()
	if CONFIG.AntiAFK then
		triggerAntiAFKOnce()
	end
end)

-- ==================== ตัวช่วยสร้าง UI และลากย้ายบนมือถือ ====================
local function applyCorner(instance, px)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, px)
	corner.Parent = instance
	return corner
end

local function applyStroke(instance, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1.5
	stroke.Parent = instance
	return stroke
end

local function enableTouchDrag(dragHandle, targetFrame)
	local isDragging = false
	local dragOrigin = nil
	local frameOrigin = nil

	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			dragOrigin = input.Position
			frameOrigin = targetFrame.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if isDragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragOrigin
			targetFrame.Position = UDim2.new(
				frameOrigin.X.Scale,
				frameOrigin.X.Offset + delta.X,
				frameOrigin.Y.Scale,
				frameOrigin.Y.Offset + delta.Y
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
		end
	end)
end

local UI = {
	Gui = nil,
	Main = nil,
	StatusLabel = nil,
	CycleLabel = nil,
	StartButton = nil,
	SystemButton = nil,
	Viewport = nil,
	VpCamera = nil,
}

local function setStatus(text)
	STATE.StatusText = text
	if UI.StatusLabel and UI.StatusLabel.Parent then
		UI.StatusLabel.Text = "สถานะ: " .. text
	end
end

local function refreshCycleText()
	if UI.CycleLabel and UI.CycleLabel.Parent then
		UI.CycleLabel.Text = localPlayer.DisplayName .. "\nจบรอบ: " .. tostring(STATE.Cycles)
	end
end

local function refreshStartButtonStyle()
	if not UI.StartButton or not UI.StartButton.Parent then
		return
	end
	if CONFIG.Running then
		UI.StartButton.BackgroundColor3 = PALETTE.Green
		UI.StartButton.TextColor3 = PALETTE.Bg
		UI.StartButton.Text = "กำลังทำงาน (กดหยุด)"
	else
		UI.StartButton.BackgroundColor3 = PALETTE.GreenSoft
		UI.StartButton.TextColor3 = PALETTE.Text
		UI.StartButton.Text = "เริ่มทำงาน"
	end
end

local function populateCharacterViewport(viewport, camera)
	if not viewport or not camera then
		return
	end
	pcall(function()
		for _, child in ipairs(viewport:GetChildren()) do
			if not child:IsA("Camera") and not child:IsA("UICorner") then
				child:Destroy()
			end
		end
		local char = getCharacter()
		if not char then
			return
		end
		char.Archivable = true
		local clone = char:Clone()
		char.Archivable = false
		if not clone then
			return
		end
		for _, obj in ipairs(clone:GetDescendants()) do
			if obj:IsA("Script") or obj:IsA("LocalScript") or obj:IsA("Sound") then
				obj:Destroy()
			elseif obj:IsA("BasePart") then
				obj.Anchored = true
				obj.CanCollide = false
			end
		end
		clone.Parent = viewport
		local hrp = clone:FindFirstChild("HumanoidRootPart") or clone:FindFirstChild("Head")
		if hrp then
			camera.CFrame = CFrame.lookAt(
				hrp.Position + (hrp.CFrame.LookVector * 4.5) + Vector3.new(0, 0.85, 0),
				hrp.Position + Vector3.new(0, 0.5, 0)
			)
		end
	end)
end

local function executeSelectedExtraSystem()
	local selected = EXTRA_SYSTEMS[CONFIG.SystemIndex]
	if selected == "สแกนจุดส่งสุ่ม" then
		local dropCF = findRandomDropoffCFrame()
		if dropCF then
			teleportToCFrame(dropCF)
			task.wait(0.3)
			interactWithNearby(28)
			setStatus("เจอจุดส่งสุ่มและวาร์ปแล้ว")
		else
			setStatus("ยังไม่พบจุดส่งสุ่มในแมพ")
		end
	elseif selected == "วาร์ปจุดรับ" then
		if CONFIG.PickupCFrame then
			teleportToCFrame(CONFIG.PickupCFrame)
			setStatus("วาร์ปไปจุดรับแล้ว")
		else
			setStatus("ยังไม่ได้กดจำจุดรับ")
		end
	elseif selected == "กดปุ่มใกล้ตัว" then
		local n = interactWithNearby(28)
		setStatus("กดปุ่มใกล้ตัวแล้ว (" .. tostring(n) .. ")")
	elseif selected == "ระบบรถและซ่อม" then
		setStatus(runVehicleAndCareAction())
	elseif selected == "เควสต์และรางวัล" then
		setStatus(runQuestAndRewardAction())
	elseif selected == "กันหลุด AFK" then
		CONFIG.AntiAFK = not CONFIG.AntiAFK
		if CONFIG.AntiAFK then
			triggerAntiAFKOnce()
		end
		setStatus(CONFIG.AntiAFK and "เปิดกันหลุด AFK แล้ว" or "ปิดกันหลุด AFK แล้ว")
	end
end

local function buildPersistentUI(showLoader)
	local existing = playerGui:FindFirstChild("MahanakhonFullFarmUI")
	if existing then
		pcall(function()
			existing:Destroy()
		end)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MahanakhonFullFarmUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	UI.Gui = gui

	-- ปุ่มลอยสำหรับเปิด/ปิดเมนูบนหน้าจอมือถือ
	local floatBtn = Instance.new("TextButton")
	floatBtn.Name = "FloatingToggleButton"
	floatBtn.Size = UDim2.fromOffset(58, 58)
	floatBtn.Position = UDim2.new(0, 14, 0.40, 0)
	floatBtn.BackgroundColor3 = PALETTE.Bg
	floatBtn.Text = "เมนู\nฟาร์ม"
	floatBtn.TextColor3 = PALETTE.Green
	floatBtn.Font = Enum.Font.GothamBold
	floatBtn.TextSize = 13
	floatBtn.Parent = gui
	applyCorner(floatBtn, 29)
	applyStroke(floatBtn, PALETTE.Green, 2)
	enableTouchDrag(floatBtn, floatBtn)

	-- หน้าต่างหลักขนาดพอดีมือถือ ตัวหนังสือใหญ่ อ่านง่าย
	local main = Instance.new("Frame")
	main.Name = "MainPanel"
	main.Size = UDim2.fromOffset(360, 336)
	main.Position = UDim2.new(0.5, -180, 0.5, -168)
	main.BackgroundColor3 = PALETTE.Bg
	main.Visible = (not showLoader) and (not STATE.Minimized)
	main.Parent = gui
	applyCorner(main, 12)
	applyStroke(main, PALETTE.Green, 2)
	UI.Main = main

	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1, 0, 0, 40)
	topBar.BackgroundColor3 = PALETTE.Card
	topBar.BorderSizePixel = 0
	topBar.Parent = main
	applyCorner(topBar, 12)
	enableTouchDrag(topBar, main)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -92, 1, 0)
	titleLbl.Position = UDim2.fromOffset(12, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "MAHANAKHON RACING | ครบทุกระบบ"
	titleLbl.TextColor3 = PALETTE.Green
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 13
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = topBar

	local toggleVisBtn = Instance.new("TextButton")
	toggleVisBtn.Size = UDim2.fromOffset(68, 28)
	toggleVisBtn.Position = UDim2.new(1, -78, 0.5, -14)
	toggleVisBtn.BackgroundColor3 = PALETTE.GreenSoft
	toggleVisBtn.Text = "ซ่อนหน้าต่าง"
	toggleVisBtn.TextColor3 = PALETTE.Text
	toggleVisBtn.Font = Enum.Font.GothamBold
	toggleVisBtn.TextSize = 11
	toggleVisBtn.Parent = topBar
	applyCorner(toggleVisBtn, 7)

	-- กรอบตัวละครผู้เล่น (ViewportFrame)
	local charCard = Instance.new("Frame")
	charCard.Size = UDim2.fromOffset(112, 198)
	charCard.Position = UDim2.fromOffset(12, 50)
	charCard.BackgroundColor3 = PALETTE.Card
	charCard.Parent = main
	applyCorner(charCard, 10)
	applyStroke(charCard, PALETTE.GreenSoft, 1)

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.new(1, -10, 1, -50)
	vp.Position = UDim2.fromOffset(5, 5)
	vp.BackgroundColor3 = PALETTE.CardAlt
	vp.BorderSizePixel = 0
	vp.Parent = charCard
	applyCorner(vp, 8)
	UI.Viewport = vp

	local vpCam = Instance.new("Camera")
	vpCam.FieldOfView = 45
	vp.CurrentCamera = vpCam
	vpCam.Parent = vp
	UI.VpCamera = vpCam

	local cycleLbl = Instance.new("TextLabel")
	cycleLbl.Size = UDim2.new(1, -8, 0, 36)
	cycleLbl.Position = UDim2.new(0, 4, 1, -42)
	cycleLbl.BackgroundTransparency = 1
	cycleLbl.TextColor3 = PALETTE.Green
	cycleLbl.Font = Enum.Font.GothamBold
	cycleLbl.TextSize = 11
	cycleLbl.Parent = charCard
	UI.CycleLabel = cycleLbl
	refreshCycleText()
	populateCharacterViewport(vp, vpCam)

	-- แผงควบคุมหลักฝั่งขวา
	local statusCard = Instance.new("Frame")
	statusCard.Size = UDim2.new(1, -144, 0, 42)
	statusCard.Position = UDim2.fromOffset(132, 50)
	statusCard.BackgroundColor3 = PALETTE.Card
	statusCard.Parent = main
	applyCorner(statusCard, 8)
	applyStroke(statusCard, PALETTE.GreenSoft, 1)

	local statusLbl = Instance.new("TextLabel")
	statusLbl.Size = UDim2.new(1, -10, 1, 0)
	statusLbl.Position = UDim2.fromOffset(5, 0)
	statusLbl.BackgroundTransparency = 1
	statusLbl.Text = "สถานะ: " .. STATE.StatusText
	statusLbl.TextColor3 = PALETTE.Text
	statusLbl.Font = Enum.Font.GothamBold
	statusLbl.TextSize = 12
	statusLbl.TextWrapped = true
	statusLbl.TextXAlignment = Enum.TextXAlignment.Left
	statusLbl.Parent = statusCard
	UI.StatusLabel = statusLbl

	-- ปุ่มเดียวรวม "โหมดทำงาน"
	local workModeBtn = Instance.new("TextButton")
	workModeBtn.Size = UDim2.new(1, -144, 0, 38)
	workModeBtn.Position = UDim2.fromOffset(132, 98)
	workModeBtn.BackgroundColor3 = PALETTE.Card
	workModeBtn.Text = "โหมดทำงาน: " .. WORK_MODES[CONFIG.ModeIndex]
	workModeBtn.TextColor3 = PALETTE.Green
	workModeBtn.Font = Enum.Font.GothamBold
	workModeBtn.TextSize = 12
	workModeBtn.Parent = main
	applyCorner(workModeBtn, 8)
	applyStroke(workModeBtn, PALETTE.Green, 1.5)

	workModeBtn.MouseButton1Click:Connect(function()
		CONFIG.ModeIndex = (CONFIG.ModeIndex % #WORK_MODES) + 1
		workModeBtn.Text = "โหมดทำงาน: " .. WORK_MODES[CONFIG.ModeIndex]
	end)

	-- ปุ่มเริ่ม / หยุดทำงาน
	local startBtn = Instance.new("TextButton")
	startBtn.Size = UDim2.new(1, -144, 0, 40)
	startBtn.Position = UDim2.fromOffset(132, 142)
	startBtn.Font = Enum.Font.GothamBold
	startBtn.TextSize = 13
	startBtn.Parent = main
	applyCorner(startBtn, 8)
	applyStroke(startBtn, PALETTE.Green, 1.5)
	UI.StartButton = startBtn
	refreshStartButtonStyle()

	startBtn.MouseButton1Click:Connect(function()
		CONFIG.Running = not CONFIG.Running
		refreshStartButtonStyle()
		setStatus(CONFIG.Running and ("เริ่ม " .. WORK_MODES[CONFIG.ModeIndex]) or "หยุดทำงานแล้ว")
	end)

	-- ปุ่มจำจุดรับ / ปุ่มสแกนหาจุดส่งสุ่ม
	local savePickupBtn = Instance.new("TextButton")
	savePickupBtn.Size = UDim2.new(0.5, -138, 0, 34)
	savePickupBtn.Position = UDim2.fromOffset(132, 188)
	savePickupBtn.BackgroundColor3 = PALETTE.Card
	savePickupBtn.Text = CONFIG.PickupCFrame and "จำจุดรับ (แล้ว)" or "จำจุดรับ"
	savePickupBtn.TextColor3 = CONFIG.PickupCFrame and PALETTE.Green or PALETTE.Text
	savePickupBtn.Font = Enum.Font.GothamBold
	savePickupBtn.TextSize = 11
	savePickupBtn.Parent = main
	applyCorner(savePickupBtn, 7)

	local scanDropBtn = Instance.new("TextButton")
	scanDropBtn.Size = UDim2.new(0.5, -138, 0, 34)
	scanDropBtn.Position = UDim2.new(0.5, 4, 0, 188)
	scanDropBtn.BackgroundColor3 = PALETTE.Card
	scanDropBtn.Text = "หาจุดส่งสุ่ม"
	scanDropBtn.TextColor3 = PALETTE.Green
	scanDropBtn.Font = Enum.Font.GothamBold
	scanDropBtn.TextSize = 11
	scanDropBtn.Parent = main
	applyCorner(scanDropBtn, 7)

	savePickupBtn.MouseButton1Click:Connect(function()
		local root = getRootPart()
		if root then
			CONFIG.PickupCFrame = root.CFrame
			savePickupBtn.Text = "จำจุดรับ (แล้ว)"
			savePickupBtn.TextColor3 = PALETTE.Green
			setStatus("จำจุดรับจากตำแหน่งปัจจุบันแล้ว")
		else
			setStatus("ไม่พบตัวละครสำหรับจำจุดรับ")
		end
	end)

	scanDropBtn.MouseButton1Click:Connect(function()
		local dropCF = findRandomDropoffCFrame()
		if dropCF then
			teleportToCFrame(dropCF)
			task.wait(0.25)
			interactWithNearby(28)
			setStatus("สแกนเจอจุดส่งสุ่มและวาร์ปแล้ว")
		else
			setStatus("ยังไม่พบจุดส่งสุ่มในแมพ")
		end
	end)

	-- แถวระบบอื่นๆ (ปุ่มเลือกโหมดระบบย่อย + ปุ่มกดใช้ระบบนั้นทันที)
	local extraBar = Instance.new("Frame")
	extraBar.Size = UDim2.new(1, -24, 0, 44)
	extraBar.Position = UDim2.fromOffset(12, 256)
	extraBar.BackgroundColor3 = PALETTE.Card
	extraBar.Parent = main
	applyCorner(extraBar, 8)
	applyStroke(extraBar, PALETTE.GreenSoft, 1)

	local sysCycleBtn = Instance.new("TextButton")
	sysCycleBtn.Size = UDim2.new(0.58, -6, 0, 32)
	sysCycleBtn.Position = UDim2.fromOffset(4, 6)
	sysCycleBtn.BackgroundColor3 = PALETTE.CardAlt
	sysCycleBtn.Text = "ระบบ: " .. EXTRA_SYSTEMS[CONFIG.SystemIndex]
	sysCycleBtn.TextColor3 = PALETTE.Text
	sysCycleBtn.Font = Enum.Font.GothamBold
	sysCycleBtn.TextSize = 11
	sysCycleBtn.Parent = extraBar
	applyCorner(sysCycleBtn, 6)

	local sysRunBtn = Instance.new("TextButton")
	sysRunBtn.Size = UDim2.new(0.42, -6, 0, 32)
	sysRunBtn.Position = UDim2.new(0.58, 2, 0, 6)
	sysRunBtn.BackgroundColor3 = PALETTE.GreenSoft
	sysRunBtn.Text = "กดใช้ระบบนี้"
	sysRunBtn.TextColor3 = PALETTE.Green
	sysRunBtn.Font = Enum.Font.GothamBold
	sysRunBtn.TextSize = 11
	sysRunBtn.Parent = extraBar
	applyCorner(sysRunBtn, 6)

	sysCycleBtn.MouseButton1Click:Connect(function()
		CONFIG.SystemIndex = (CONFIG.SystemIndex % #EXTRA_SYSTEMS) + 1
		sysCycleBtn.Text = "ระบบ: " .. EXTRA_SYSTEMS[CONFIG.SystemIndex]
	end)

	sysRunBtn.MouseButton1Click:Connect(function()
		executeSelectedExtraSystem()
	end)

	toggleVisBtn.MouseButton1Click:Connect(function()
		STATE.Minimized = true
		main.Visible = false
	end)

	floatBtn.MouseButton1Click:Connect(function()
		STATE.Minimized = main.Visible
		main.Visible = not main.Visible
	end)

	-- หน้าโหลดสคริปต์ (Loading Screen)
	if showLoader and not STATE.LoadingDone then
		local loaderCard = Instance.new("Frame")
		loaderCard.Name = "LoadingOverlay"
		loaderCard.Size = UDim2.fromOffset(300, 140)
		loaderCard.Position = UDim2.new(0.5, -150, 0.5, -70)
		loaderCard.BackgroundColor3 = PALETTE.Bg
		loaderCard.Parent = gui
		applyCorner(loaderCard, 12)
		applyStroke(loaderCard, PALETTE.Green, 2)

		local loadHead = Instance.new("TextLabel")
		loadHead.Size = UDim2.new(1, -20, 0, 30)
		loadHead.Position = UDim2.fromOffset(10, 14)
		loadHead.BackgroundTransparency = 1
		loadHead.Text = "กำลังโหลดสคริปต์..."
		loadHead.TextColor3 = PALETTE.Green
		loadHead.Font = Enum.Font.GothamBold
		loadHead.TextSize = 16
		loadHead.Parent = loaderCard

		local loadMsg = Instance.new("TextLabel")
		loadMsg.Size = UDim2.new(1, -20, 0, 24)
		loadMsg.Position = UDim2.fromOffset(10, 48)
		loadMsg.BackgroundTransparency = 1
		loadMsg.Text = "เตรียมระบบฟาร์มและหน้าจอผู้เล่น"
		loadMsg.TextColor3 = PALETTE.Text
		loadMsg.Font = Enum.Font.Gotham
		loadMsg.TextSize = 12
		loadMsg.Parent = loaderCard

		local barTrack = Instance.new("Frame")
		barTrack.Size = UDim2.new(1, -28, 0, 12)
		barTrack.Position = UDim2.fromOffset(14, 92)
		barTrack.BackgroundColor3 = PALETTE.Card
		barTrack.Parent = loaderCard
		applyCorner(barTrack, 6)

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.new(0.2, 0, 1, 0)
		barFill.BackgroundColor3 = PALETTE.Green
		barFill.BorderSizePixel = 0
		barFill.Parent = barTrack
		applyCorner(barFill, 6)

		task.spawn(function()
			local stages = {
				{0.45, "กำลังโหลดหน้าจอตัวละครและปุ่มควบคุม..."},
				{0.80, "กำลังเตรียมตัวสแกนจุดส่งสุ่มและกัน AFK..."},
				{1.00, "พร้อมใช้งานแล้ว"},
			}
			for _, st in ipairs(stages) do
				if not loaderCard or not loaderCard.Parent then
					return
				end
				barFill.Size = UDim2.new(st[1], 0, 1, 0)
				loadMsg.Text = st[2]
				task.wait(0.35)
			end
			STATE.LoadingDone = true
			if loaderCard and loaderCard.Parent then
				loaderCard:Destroy()
			end
			if main and main.Parent and not STATE.Minimized then
				main.Visible = true
			end
		end)
	end
end

buildPersistentUI(true)

-- คืนค่า UI อัตโนมัติหากถูกลบหรือตัวละครเกิดใหม่
task.spawn(function()
	while true do
		task.wait(1.5)
		if not playerGui:FindFirstChild("MahanakhonFullFarmUI") then
			pcall(function()
				buildPersistentUI(false)
			end)
		end
	end
end)

localPlayer.CharacterAdded:Connect(function()
	task.wait(1.0)
	pcall(function()
		if not playerGui:FindFirstChild("MahanakhonFullFarmUI") then
			buildPersistentUI(false)
		else
			populateCharacterViewport(UI.Viewport, UI.VpCamera)
		end
	end)
end)

-- ลูปฟาร์มหลัก
task.spawn(function()
	while true do
		if CONFIG.Running then
			setStatus("ไปจุดรับ (" .. WORK_MODES[CONFIG.ModeIndex] .. ")")
			if CONFIG.PickupCFrame then
				teleportToCFrame(CONFIG.PickupCFrame)
				task.wait(CONFIG.WarpDelay)
			end
			if CONFIG.AutoPrompt then
				interactWithNearby(CONFIG.PromptRange)
			end
			task.wait(CONFIG.StepDelay)

			if not CONFIG.Running then
				continue
			end

			setStatus("สแกนหาจุดส่งสุ่ม...")
			local randomDropCF = findRandomDropoffCFrame()
			if randomDropCF then
				setStatus("ไปจุดส่งสุ่มแล้ว")
				teleportToCFrame(randomDropCF)
				task.wait(CONFIG.WarpDelay)
				if CONFIG.AutoPrompt then
					interactWithNearby(CONFIG.PromptRange)
				end
				setStatus("จบรอบการทำงานแล้ว")
			else
				setStatus("ไม่พบจุดส่งสุ่มในรอบนี้")
			end

			STATE.Cycles += 1
			refreshCycleText()
			task.wait(CONFIG.StepDelay)
		else
			task.wait(0.3)
		end
	end
end)
