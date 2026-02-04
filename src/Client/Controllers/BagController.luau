local BagController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Components = require(ReplicatedStorage.Client.ECS.Components)
local Bag = require(ReplicatedStorage.Client.ECS.Entities.Bag)
local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local SimpleRemotesUtil = require(ReplicatedStorage.Shared.Networking.SimpleRemotesUtil)
local jecs = require(ReplicatedStorage.Shared.Packages.jecs)
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

local ANIM_TRANSITION_WINDOW = 0.05

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

-- Converts distance into a usable step index
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

local function getBagEntityFromId(id: number)
	for bagEntity, _id in world:query(components.Id, Tags.IsBag) do
		if _id == id then
			return bagEntity
		end
	end
	return nil
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

-- Spawns a bag entity on the client if it does not already exist
local function spawnBagEntity(data: BagEntityData)
	local serverTimeNow = workspace:GetServerTimeNow()
	if serverTimeNow > data.FinishTime then
		return -- RETURN: Already finished when arrived
	end

	if getBagEntityFromId(data.Id) then
		return -- RETURN: Bag already exists on the client
	end

	local material = Enum.Material:FromValue(data.MaterialId) :: Enum.Material
	local bagEntity = Bag.new(data.Id, material, data.Color, data.ConveyorId, data.StartTime, data.FinishTime)

	warn(`LID: {data.Id} | WEID: {bagEntity} | LEID: {jecs.ECS_ID(bagEntity)} | GID: {jecs.ECS_GENERATION(bagEntity)}`)

	-- Create click detector
	local bagModel = world:get(bagEntity, components.Model)

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

function BagController.init()
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

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
	[REMOTE_CODES.Events.Spawn] = function(b: buffer)
		spawnBagEntity(decodeBagBuffer(b, 0))
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

do -- Bag rendering & throttling
	local getAllBags = world:query(components.FinishesAt):with(Tags.IsBag):cached()

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

		-- Loop through query
		local bagEntitiesToDelete = {}

		-- for bagEntity, model, startTime, finishTime, startPosition, finishPosition, conveyorId in getAllBags do
		for bagEntity, finishTime in getAllBags do
			local model = world:get(bagEntity, components.Model)
			if not model.PrimaryPart then
				continue
			end

			local startTime = world:get(bagEntity, components.StartedAt)
			local elapsed, duration = serverTimeNow - startTime, finishTime - startTime
			local progress = math.clamp(elapsed / duration, 0, 1)

			-------------------------------------------------------------------------------
			-- ANIMATION
			-------------------------------------------------------------------------------

			local appearProgress = 1
			if progress < ANIM_TRANSITION_WINDOW then
				-- Fade in
				appearProgress = progress / ANIM_TRANSITION_WINDOW
			elseif progress > 1 - ANIM_TRANSITION_WINDOW then
				-- Fade out
				appearProgress = (1 - progress) / ANIM_TRANSITION_WINDOW
			end

			for _, v in model:QueryDescendants("BasePart") :: { BasePart } do
				v.Transparency = 1 - appearProgress
			end

			-------------------------------------------------------------------------------
			-- RENDERING
			-------------------------------------------------------------------------------

			local startPosition = world:get(bagEntity, components.StartPosition)
			local finishPosition = world:get(bagEntity, components.FinishPosition)
			local conveyorId = world:get(bagEntity, components.LinkedToId)

			local position = startPosition:Lerp(finishPosition, progress)

			if progress >= 1 then
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

		-- Delete AFTER the loop, so we don't modify the world during the main iteration
		if #bagEntitiesToDelete > 0 then
			for _, bagEntity in next, bagEntitiesToDelete do
				local model = world:get(bagEntity, components.Model)
				if model then
					model:Destroy()
				end

				world:delete(bagEntity)
			end
		end
	end)
end

return BagController
