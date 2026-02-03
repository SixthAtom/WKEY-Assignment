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

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local bagRemoteEvent = SimpleRemotes.getEvent("Bag")
local bagRemoteFunction = SimpleRemotes.getFunction("Bag")

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function decodeBuffer(b: buffer, offset: number)
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
	Bag.new(data.Id, material, data.Color, data.ConveyorId, data.StartTime, data.FinishTime)
end

-------------------------------------------------------------------------------
-- CORE FUNCTIONS
-------------------------------------------------------------------------------

function BagController.start()
	-- Invoke server & get existing bags
	local b, offset = buffer.create(BYTE_SIZES.u8), 0
	BufferUtil.writeu8(b, offset, REMOTE_CODES.Functions.Get)
	b = bagRemoteFunction:InvokeServer(b)

	-- Process first input
	local len: number
	len, offset = BufferUtil.readu16(b, offset)

	for i = 1, len do
		local decoded
		decoded, offset = decodeBuffer(b, offset)
		spawnBagEntity(decoded)
	end
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

-- Bag rendering
RunService.RenderStepped:Connect(function()
	-- Construct query, no caching because it tends to break.
	local getAllBags = world
		:query(
			components.Model,
			components.StartedAt,
			components.FinishesAt,
			components.StartPosition,
			components.FinishPosition
		)
		:with(components.BagTag)

	-- Prepare variables
	local partsList: { BasePart }, cframeList: { CFrame } = {}, {}
	local serverTimeNow = workspace:GetServerTimeNow()

	-- Loop
	for bagEntity, model, startTime, finishTime, startPosition, finishPosition in getAllBags do
		if not model.PrimaryPart then
			continue
		end

		local elapsed, duration = serverTimeNow - startTime, finishTime - startTime
		local progress = math.clamp(elapsed / duration, 0, 1)
		local position = startPosition:Lerp(finishPosition, progress)

		table.insert(cframeList, model:GetPivot().Rotation + position)
		table.insert(partsList, model.PrimaryPart)
	end

	-- Move
	workspace:BulkMoveTo(partsList, cframeList)
end)

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
	[REMOTE_CODES.Events.Spawn] = function(b: buffer)
		spawnBagEntity(decodeBuffer(b, 0))
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

return BagController
