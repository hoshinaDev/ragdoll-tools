--!strict

local Ragdoll = {}

export type RagdollOptions = {
	Duration: number?,
	CollideLimbs: boolean?,
	KeepRootCollidable: boolean?,
	DisableGettingUp: boolean?,
	BreakJointsOnDeath: boolean?,
}

type RagdollRecord = {
	character: Model,
	humanoid: Humanoid,
	options: RagdollOptions,
	motors: { Motor6D },
	instances: { Instance },
	originalStates: { [Enum.HumanoidStateType]: boolean },
	originalAutoRotate: boolean,
	originalPlatformStand: boolean,
	originalBreakJointsOnDeath: boolean,
	originalCanCollide: { [BasePart]: boolean },
	rootJoint: Motor6D?,
	expiresAt: number?,
	ancestryConnection: RBXScriptConnection?,
}

local ACTIVE: { [Model]: RagdollRecord } = {}

local RAGDOLL_FOLDER_NAME = "__ServerRagdoll"
local ATTACHMENT_PREFIX = "__RagdollAttachment_"
local SOCKET_PREFIX = "__RagdollSocket_"
local NO_COLLIDE_PREFIX = "__RagdollNoCollision_"

local DEFAULT_OPTIONS: RagdollOptions = {
	Duration = nil,
	CollideLimbs = true,
	KeepRootCollidable = false,
	DisableGettingUp = true,
	BreakJointsOnDeath = false,
}

local BALL_SOCKET_LIMITS: { [string]: { upper: number, twistLower: number, twistUpper: number } } = {
	Neck = { upper = 35, twistLower = -35, twistUpper = 35 },
	Waist = { upper = 25, twistLower = -25, twistUpper = 25 },
	Root = { upper = 10, twistLower = -10, twistUpper = 10 },
	RootJoint = { upper = 10, twistLower = -10, twistUpper = 10 },

	LeftShoulder = { upper = 90, twistLower = -70, twistUpper = 70 },
	RightShoulder = { upper = 90, twistLower = -70, twistUpper = 70 },
	["Left Shoulder"] = { upper = 90, twistLower = -70, twistUpper = 70 },
	["Right Shoulder"] = { upper = 90, twistLower = -70, twistUpper = 70 },
	LeftElbow = { upper = 20, twistLower = 0, twistUpper = 135 },
	RightElbow = { upper = 20, twistLower = 0, twistUpper = 135 },
	LeftWrist = { upper = 35, twistLower = -35, twistUpper = 35 },
	RightWrist = { upper = 35, twistLower = -35, twistUpper = 35 },

	LeftHip = { upper = 75, twistLower = -45, twistUpper = 45 },
	RightHip = { upper = 75, twistLower = -45, twistUpper = 45 },
	["Left Hip"] = { upper = 75, twistLower = -45, twistUpper = 45 },
	["Right Hip"] = { upper = 75, twistLower = -45, twistUpper = 45 },
	LeftKnee = { upper = 15, twistLower = 0, twistUpper = 130 },
	RightKnee = { upper = 15, twistLower = 0, twistUpper = 130 },
	LeftAnkle = { upper = 35, twistLower = -35, twistUpper = 35 },
	RightAnkle = { upper = 35, twistLower = -35, twistUpper = 35 },
}

local ROOT_MOTOR_NAMES: { [string]: boolean } = {
	Root = true,
	RootJoint = true,
}

local function mergeOptions(options: RagdollOptions?): RagdollOptions
	local merged = table.clone(DEFAULT_OPTIONS)

	if options then
		for key, value in pairs(options :: any) do
			(merged :: any)[key] = value
		end
	end

	return merged
end

local function getHumanoid(character: Model): Humanoid
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Ragdoll expected a character Model with a Humanoid")
	return humanoid
end

local function isCharacterMotor(motor: Motor6D, character: Model): boolean
	return motor.Part0 ~= nil
		and motor.Part1 ~= nil
		and motor.Part0:IsDescendantOf(character)
		and motor.Part1:IsDescendantOf(character)
end

local function shouldRagdollMotor(motor: Motor6D): boolean
	if motor.Part0 == nil or motor.Part1 == nil then
		return false
	end

	-- Accessory welds and tool joints are intentionally ignored. R6/R15 body joints are Motor6D
	-- descendants of character parts and connect two BaseParts inside the same character.
	return motor.Part0:IsA("BasePart") and motor.Part1:IsA("BasePart")
end

local function makeFolder(character: Model): Folder
	local oldFolder = character:FindFirstChild(RAGDOLL_FOLDER_NAME)
	if oldFolder then
		oldFolder:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = RAGDOLL_FOLDER_NAME
	folder.Parent = character
	return folder
end

local function makeAttachment(part: BasePart, name: string, cframe: CFrame, folder: Folder): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = cframe
	attachment.Parent = part

	local marker = Instance.new("ObjectValue")
	marker.Name = attachment.Name
	marker.Value = attachment
	marker.Parent = folder

	return attachment
end

local function configureSocket(socket: BallSocketConstraint, motorName: string)
	local limits = BALL_SOCKET_LIMITS[motorName] or { upper = 60, twistLower = -45, twistUpper = 45 }

	socket.LimitsEnabled = true
	socket.UpperAngle = limits.upper
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = limits.twistLower
	socket.TwistUpperAngle = limits.twistUpper
	socket.Restitution = 0
end

local function collectMotors(character: Model): { Motor6D }
	local motors = {}

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and isCharacterMotor(descendant, character) and shouldRagdollMotor(descendant) then
			table.insert(motors, descendant)
		end
	end

	return motors
end

local function setStateEnabled(humanoid: Humanoid, state: Enum.HumanoidStateType, enabled: boolean, record: RagdollRecord)
	local ok, wasEnabled = pcall(function()
		return humanoid:GetStateEnabled(state)
	end)

	if ok then
		record.originalStates[state] = wasEnabled
		pcall(function()
			humanoid:SetStateEnabled(state, enabled)
		end)
	end
end

local function prepareHumanoid(record: RagdollRecord)
	local humanoid = record.humanoid
	local options = record.options

	record.originalAutoRotate = humanoid.AutoRotate
	record.originalPlatformStand = humanoid.PlatformStand
	record.originalBreakJointsOnDeath = humanoid.BreakJointsOnDeath

	humanoid.BreakJointsOnDeath = options.BreakJointsOnDeath == true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	if options.DisableGettingUp ~= false then
		setStateEnabled(humanoid, Enum.HumanoidStateType.GettingUp, false, record)
	end

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
end

local function prepareCollision(record: RagdollRecord)
	local character = record.character
	local options = record.options

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			record.originalCanCollide[descendant] = descendant.CanCollide

			if descendant.Name == "HumanoidRootPart" then
				descendant.CanCollide = options.KeepRootCollidable == true
			elseif options.CollideLimbs ~= false then
				descendant.CanCollide = true
			end
		end
	end
end

local function buildSelfNoCollisionConstraints(record: RagdollRecord, folder: Folder)
	local parts: { BasePart } = {}

	for _, descendant in record.character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	for index = 1, #parts do
		local part0 = parts[index]

		for otherIndex = index + 1, #parts do
			local part1 = parts[otherIndex]

			local noCollision = Instance.new("NoCollisionConstraint")
			noCollision.Name = NO_COLLIDE_PREFIX .. part0.Name .. "_" .. part1.Name
			noCollision.Part0 = part0
			noCollision.Part1 = part1
			noCollision.Parent = folder
			table.insert(record.instances, noCollision)
		end
	end
end

local function buildConstraints(record: RagdollRecord, folder: Folder)
	for _, motor in record.motors do
		local part0 = motor.Part0
		local part1 = motor.Part1

		if part0 and part1 then
			local attachment0 = makeAttachment(part0, ATTACHMENT_PREFIX .. motor.Name .. "_0", motor.C0, folder)
			local attachment1 = makeAttachment(part1, ATTACHMENT_PREFIX .. motor.Name .. "_1", motor.C1, folder)

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = SOCKET_PREFIX .. motor.Name
			socket.Attachment0 = attachment0
			socket.Attachment1 = attachment1
			socket.Parent = folder
			configureSocket(socket, motor.Name)
			table.insert(record.instances, socket)

			table.insert(record.instances, attachment0)
			table.insert(record.instances, attachment1)

			if ROOT_MOTOR_NAMES[motor.Name] then
				record.rootJoint = motor
			end

			motor.Enabled = false
		end
	end
end

local function restoreRecord(record: RagdollRecord)
	local humanoid = record.humanoid

	for _, motor in record.motors do
		if motor.Parent ~= nil then
			motor.Enabled = true
		end
	end

	for _, instance in record.instances do
		if instance.Parent ~= nil then
			instance:Destroy()
		end
	end

	local folder = record.character:FindFirstChild(RAGDOLL_FOLDER_NAME)
	if folder then
		folder:Destroy()
	end

	for part, canCollide in record.originalCanCollide do
		if part.Parent ~= nil then
			part.CanCollide = canCollide
		end
	end

	for state, enabled in record.originalStates do
		pcall(function()
			humanoid:SetStateEnabled(state, enabled)
		end)
	end

	if humanoid.Parent ~= nil then
		humanoid.BreakJointsOnDeath = record.originalBreakJointsOnDeath
		humanoid.AutoRotate = record.originalAutoRotate
		humanoid.PlatformStand = record.originalPlatformStand

		if humanoid.Health > 0 then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end)
		end
	end

	if record.ancestryConnection then
		record.ancestryConnection:Disconnect()
	end
end

local function scheduleUnragdoll(character: Model, duration: number)
	task.delay(duration, function()
		local record = ACTIVE[character]

		if record and record.expiresAt and os.clock() >= record.expiresAt then
			Ragdoll.Unragdoll(character)
		end
	end)
end

function Ragdoll.IsRagdolled(character: Model): boolean
	return ACTIVE[character] ~= nil
end

function Ragdoll.Ragdoll(character: Model, options: RagdollOptions?): boolean
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Ragdoll.Ragdoll expected a character Model")

	if ACTIVE[character] then
		local record = ACTIVE[character]
		local duration = options and options.Duration

		if duration and duration > 0 then
			record.expiresAt = os.clock() + duration
			scheduleUnragdoll(character, duration)
		end

		return false
	end

	local humanoid = getHumanoid(character)
	local mergedOptions = mergeOptions(options)
	local motors = collectMotors(character)

	if #motors == 0 then
		warn(("[Ragdoll] Character %s has no body Motor6D joints to ragdoll."):format(character:GetFullName()))
		return false
	end

	local record: RagdollRecord = {
		character = character,
		humanoid = humanoid,
		options = mergedOptions,
		motors = motors,
		instances = {},
		originalStates = {},
		originalAutoRotate = humanoid.AutoRotate,
		originalPlatformStand = humanoid.PlatformStand,
		originalBreakJointsOnDeath = humanoid.BreakJointsOnDeath,
		originalCanCollide = {},
		rootJoint = nil,
		expiresAt = nil,
		ancestryConnection = nil,
	}

	ACTIVE[character] = record
	record.ancestryConnection = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and ACTIVE[character] == record then
			ACTIVE[character] = nil

			for _, instance in record.instances do
				if instance.Parent ~= nil then
					instance:Destroy()
				end
			end

			if record.ancestryConnection then
				record.ancestryConnection:Disconnect()
			end
		end
	end)

	local folder = makeFolder(character)
	prepareHumanoid(record)
	prepareCollision(record)
	buildConstraints(record, folder)
	buildSelfNoCollisionConstraints(record, folder)

	local duration = mergedOptions.Duration
	if duration and duration > 0 then
		record.expiresAt = os.clock() + duration
		scheduleUnragdoll(character, duration)
	end

	return true
end

function Ragdoll.Unragdoll(character: Model): boolean
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Ragdoll.Unragdoll expected a character Model")

	local record = ACTIVE[character]
	if not record then
		return false
	end

	ACTIVE[character] = nil
	restoreRecord(record)

	return true
end

function Ragdoll.Toggle(character: Model, ragdolled: boolean?, options: RagdollOptions?): boolean
	local shouldRagdoll = if ragdolled == nil then not Ragdoll.IsRagdolled(character) else ragdolled

	if shouldRagdoll then
		return Ragdoll.Ragdoll(character, options)
	end

	return Ragdoll.Unragdoll(character)
end

function Ragdoll.BindDeath(character: Model, options: RagdollOptions?): RBXScriptConnection
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Ragdoll.BindDeath expected a character Model")

	local humanoid = getHumanoid(character)
	humanoid.BreakJointsOnDeath = false

	return humanoid.Died:Connect(function()
		Ragdoll.Ragdoll(character, options)
	end)
end

function Ragdoll.Cleanup(character: Model): boolean
	if ACTIVE[character] then
		return Ragdoll.Unragdoll(character)
	end

	local folder = character:FindFirstChild(RAGDOLL_FOLDER_NAME)
	if folder then
		folder:Destroy()
		return true
	end

	return false
end

return Ragdoll
