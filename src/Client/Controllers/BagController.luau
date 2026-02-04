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

-- How long bags take to fade in/out at start and end
-- Small window so the effect is subtle and not distracting
local ANIM_TRANSITION_WINDOW = 0.05

-- Frame throttling steps based on distance from camera
-- Further conveyors update bags less often to save performance
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

-- Returns how often a conveyor should update it's bags based on distance
-- Uses a simple lookup instead of math to keep it predictable and cheap
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

-- Finds an already existing bag entity with a given unique id -> this is replicated
-- Linear scan but cheap because bag count isn't substantially high
local function getBagEntityFromId(id: number)
	for bagEntity, _id in world:query(components.Id, Tags.IsBag) do
		if _id == id then
			return bagEntity
		end
	end
	return nil
end

-- Decodes a bag buffer into a proper table
-- Centralizing this prevents offset mistakes all over the code
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

-- Creates an ECS entity for a bag
-- Only runs if the bag is still relevant and not already spawned
local function spawnBagEntity(data: BagEntityData)
	local serverTimeNow = workspace:GetServerTimeNow()
	if serverTimeNow > data.FinishTime then
		return -- RETURN: Dont bother creating bags that already finished
	end

	if getBagEntityFromId(data.Id) then
		return -- RETURN: Avoid duplicates (especially when getting & receiving on join)
	end

	local material = Enum.Material:FromValue(data.MaterialId) :: Enum.Material
	local bagEntity = Bag.new(data.Id, material, data.Color, data.ConveyorId, data.StartTime, data.FinishTime)

	warn(`LID: {data.Id} | WEID: {bagEntity} | LEID: {jecs.ECS_ID(bagEntity)} | GID: {jecs.ECS_GENERATION(bagEntity)}`)

	-- Interaction logic is attached at spawn so it dies with the entity
	local bagModel = world:get(bagEntity, components.Model)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Parent = bagModel.PrimaryPart
	clickDetector.MouseClick:Connect(function()
		local bagId = world:get(bagEntity, components.Id)

		warn(`You just clicked bag {bagId} | client EntityID: {bagEntity}`)

		-- Pack data into buffer and tell server which bag was clicked
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
	-- Ask server for active bags on join
	local b, offset = buffer.create(BYTE_SIZES.u8), 0
	BufferUtil.writeu8(b, offset, REMOTE_CODES.Functions.Get)
	b = bagRemoteFunction:InvokeServer(b)

	-- First value in buffer tells us how many bags to read
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

-- Binds remote actions in a table, so adding new events later is easy
SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
	[REMOTE_CODES.Events.Spawn] = function(b: buffer)
		spawnBagEntity(decodeBagBuffer(b, 0))
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

do -- Rendering and throttling
	-- Caching ECS queries give a very big performance boost (about 5x as fast as non-cached)
	local getAllBags = world:query(components.FinishesAt):with(Tags.IsBag):cached()
	local getBagsToDestroy = world:query(components.Model, Tags.ToDestroy):with(Tags.IsBag):cached()

	local conveyorsStep: { number } = {}
	local frames = 0

	RunService.RenderStepped:Connect(function()
		frames = (frames + 1) % 10_000

		local partsList: { BasePart }, cframeList: { CFrame } = {}, {}
		local serverTimeNow = workspace:GetServerTimeNow()
		local cameraPosition = camera.CFrame.Position

		-- Compute throttling values per conveyor every frame
		-- Much cheaper than doing distance checks per bag
		for _, conveyor in workspace.Conveyors:GetChildren() :: { Model } do
			local root = conveyor.PrimaryPart
			if not root then
				continue
			end

			conveyorsStep[tonumber(conveyor.Name)] = getStepFromDistance((cameraPosition - root.Position).Magnitude)
		end

		-- Main loop for processing every active bag
		for bagEntity, finishTime in getAllBags do
			local model = world:get(bagEntity, components.Model)
			if not model.PrimaryPart then
				continue
			end

			-- Progress is time based, so it's not bound to FPS
			local startTime = world:get(bagEntity, components.StartedAt)
			local elapsed, duration = serverTimeNow - startTime, finishTime - startTime
			local progress = math.clamp(elapsed / duration, 0, 1)

			-------------------------------------------------------------------------------
			-- ANIMATION
			-------------------------------------------------------------------------------

			-- Fade in at start & fade out at end, using a normalized value
			local appearProgress = 1

			if progress < ANIM_TRANSITION_WINDOW then
				appearProgress = progress / ANIM_TRANSITION_WINDOW
			elseif progress > 1 - ANIM_TRANSITION_WINDOW then
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

			-- Lerp instead of Roblox physics to save performance
			local position = startPosition:Lerp(finishPosition, progress)

			-- CONTINUE: Bag has reached end & is marked for deletion
			if progress >= 1 then
				world:add(bagEntity, Tags.ToDestroy)
				continue
			end

			-- CONTINUE: Skip the frame if bag's conveyor is being throttled
			if frames % conveyorsStep[conveyorId] ~= 0 then
				continue
			end

			-- CONTINUE: Bag is outside of camera's view
			if not ({ camera:WorldToViewportPoint(position) })[2] then
				continue
			end

			-- Insert into the bulkmoveto tables
			table.insert(cframeList, model:GetPivot().Rotation + position)
			table.insert(partsList, model.PrimaryPart)
		end

		if #partsList > 0 then
			workspace:BulkMoveTo(partsList, cframeList) -- Use BulkMoveTo because it's written in C++ -> more performant over manual CFrame operations.
		end

		-- Delete AFTER the loop, so we don't modify ECS during the main iteration
		for bagEntity, model in getBagsToDestroy do
			if model then
				model:Destroy()
			end
			world:delete(bagEntity)
		end
	end)
end

return BagController
