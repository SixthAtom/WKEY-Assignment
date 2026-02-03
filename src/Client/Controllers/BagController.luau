local BagController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Components = require(ReplicatedStorage.Client.ECS.Components)
local Bag = require(ReplicatedStorage.Client.ECS.Entities.Bag)
local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local SimpleRemotesUtil = require(ReplicatedStorage.Shared.Networking.SimpleRemotesUtil)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)

-------------------------------------------------------------------------------
-- TYPES
-------------------------------------------------------------------------------

type BagEntityData = {
	Id: number,
	MaterialId: number,
	Color: Color3,
	ConveyorId: number,
	StartTime: number,
	FinishTime: number,
}

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local REMOTE_CODES = RemoteCodes.Bags
local BYTE_SIZES = BufferConstants.Sizes

local DISTANCE_STEPS = {
	[100] = 3,
	[200] = 5,
	[300] = 7,
	[600] = 15,
}

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local bagRemoteEvent = SimpleRemotes.getEvent("Bag")
local bagRemoteFunction = SimpleRemotes.getFunction("Bag")

local world = Worlds.Default
local components = Components.Default

local camera = workspace.CurrentCamera

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function getStepFromDistance(distance: number)
	local step = 1
	for treshold, s in DISTANCE_STEPS do
		if distance > treshold then
			step = s
			break
		end
	end
	return step
end

-- Method for decoding bag buffers -> following the DRY principle
local function decodeBagBuffer(b: buffer, offset: number)
	local id: number, materialId: number, color: Color3, conveyorId: number
	local startTime: number, finishTime: number

	id, offset = BufferUtil.readu16(b, offset)
	materialId, offset = BufferUtil.readu16(b, offset)
	color, offset = BufferUtil.readColor_24(b, offset)
	conveyorId, offset = BufferUtil.readu8(b, offset)
	startTime, offset = BufferUtil.readf64(b, offset)
	finishTime, offset = BufferUtil.readf64(b, offset)

	return {
		Id = id,
		MaterialId = materialId,
		Color = color,
		ConveyorId = conveyorId,
		StartTime = startTime,
		FinishTime = finishTime,
	},
		offset
end

local function spawnBagEntity(data: BagEntityData)
	local material = Enum.Material:FromValue(data.MaterialId) :: Enum.Material
	local bagEntity = Bag.new(data.Id, material, data.Color, data.ConveyorId, data.StartTime, data.FinishTime)

	local bagModel = world:get(bagEntity, components.Model)

	-- Create click detector
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Parent = bagModel.PrimaryPart
	clickDetector.MouseClick:Connect(function()
		local bagId = world:get(bagEntity, components.Id)
		-- Print ID on client
		warn(`You just clicked bag {bagId} | client EntityID: {bagEntity}`)

		-- Replicate click to server
		local b, offset = buffer.create(BYTE_SIZES.u8 + BYTE_SIZES.u16), 0
		offset = BufferUtil.writeu8(b, offset, REMOTE_CODES.Events.Clicked)
		offset = BufferUtil.writeu16(b, offset, bagId)
		bagRemoteEvent:FireServer(b)
	end)
end

-------------------------------------------------------------------------------
-- CORE FUNCTIONS
-------------------------------------------------------------------------------

function BagController.start()
	-- Invoke server & get existing bags
	local b, offset = buffer.create(BYTE_SIZES.u8), 0
	BufferUtil.writeu8(b, offset, REMOTE_CODES.Functions.Get) -- don't set offset because we're resetting the buffer variable
	b = bagRemoteFunction:InvokeServer(b)

	-- Process first input
	local len: number
	len, offset = BufferUtil.readu16(b, offset)

	for i = 1, len do
		local decoded
		decoded, offset = decodeBagBuffer(b, offset)
		spawnBagEntity(decoded)
	end
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

-- Bag rendering & throttling
local conveyorsStep: { number } = {}
local frames = 0

RunService.RenderStepped:Connect(function()
	frames = (frames + 1) % 10_000

	-- Prepare variables
	local partsList: { BasePart }, cframeList: { CFrame } = {}, {}
	local serverTimeNow = workspace:GetServerTimeNow()
	local cameraPosition = camera.CFrame.Position

	-- Calculate distances
	for _, conveyor in workspace.Conveyors:GetChildren() :: { Model } do
		local root = conveyor.PrimaryPart
		if not root then
			continue
		end

		conveyorsStep[tonumber(conveyor.Name)] = getStepFromDistance((cameraPosition - root.Position).Magnitude)
	end

	-- Construct query, no caching because it tends to break.
	local getAllBags = world
		:query(
			components.Model,
			components.StartedAt,
			components.FinishesAt,
			components.StartPosition,
			components.FinishPosition,
			components.LinkedToId
		)
		:with(components.BagTag)

	-- Loop through query
	local bagEntitiesToDelete = {}

	for bagEntity, model, startTime, finishTime, startPosition, finishPosition, conveyorId in getAllBags do
		if not model.PrimaryPart then
			continue
		end

		local elapsed, duration = serverTimeNow - startTime, finishTime - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local position = startPosition:Lerp(finishPosition, progress)

		if progress >= 1 then
			model:Destroy()
			table.insert(bagEntitiesToDelete, bagEntity)
			continue -- CONTINUE: Model is DONE FOR
		end

		if frames % conveyorsStep[conveyorId] ~= 0 then
			continue -- CONTINUE: Throttled
		end

		if not ({ camera:WorldToViewportPoint(position) })[2] then
			continue -- CONTINUE: Model is not in camera's FOV
		end

		table.insert(cframeList, model:GetPivot().Rotation + position)
		table.insert(partsList, model.PrimaryPart)
	end

	if #partsList > 0 then
		workspace:BulkMoveTo(partsList, cframeList) -- Use BulkMoveTo because it's written in C++ -> more performant over manual CFrame operations.
	end

	for _, bagEntity in next, bagEntitiesToDelete do
		world:delete(bagEntity)
	end
end)

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
	[REMOTE_CODES.Events.Spawn] = function(b: buffer)
		spawnBagEntity(decodeBagBuffer(b, 0))
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

return BagController
