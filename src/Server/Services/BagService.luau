local BagService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Components = require(ServerStorage.Server.ECS.Components)
local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local Limiter = require(ReplicatedStorage.Shared.Limiter)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local SimpleRemotesUtil = require(ReplicatedStorage.Shared.Networking.SimpleRemotesUtil)
local jecs = require(ReplicatedStorage.Shared.Packages.jecs)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)
local Bag = require(ServerStorage.Server.ECS.Entities.Bag)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local BYTE_SIZES = BufferConstants.Sizes
local REMOTE_CODES = RemoteCodes.Bags

local BAG_BYTE_SIZE = BYTE_SIZES.u16 * 2 + BYTE_SIZES.u8 + BYTE_SIZES.Color + BYTE_SIZES.f64 * 2

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local bagRemoteEvent = SimpleRemotes.getEvent("Bag")
local bagRemoteFunction = SimpleRemotes.getFunction("Bag")

local bagCounter = 0

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

-- Method for encoding bag buffers -> following the DRY principle
local function encodeBagBuffer(
	b: buffer,
	offset: number,
	data: {
		Id: number,
		MaterialId: number,
		Color: Color3,
		ConveyorId: number,
		StartTime: number,
		FinishTime: number,
	}
)
	offset = BufferUtil.writeu16(b, offset, data.Id)
	offset = BufferUtil.writeu16(b, offset, data.MaterialId)
	offset = BufferUtil.writeColor_24(b, offset, data.Color)
	offset = BufferUtil.writeu8(b, offset, data.ConveyorId)
	offset = BufferUtil.writef64(b, offset, data.StartTime)
	offset = BufferUtil.writef64(b, offset, data.FinishTime)
	return offset
end

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function BagService.spawn(conveyorEntity: jecs.Entity)
	bagCounter = (bagCounter % 50_000) + 1

	local bagEntity = Bag.new(bagCounter, conveyorEntity)

	local b, offset = buffer.create(BYTE_SIZES.u8 + BAG_BYTE_SIZE), 0
	offset = BufferUtil.writeu8(b, offset, REMOTE_CODES.Events.Spawn)
	offset = encodeBagBuffer(b, offset, {
		Id = bagCounter,
		MaterialId = world:get(bagEntity, components.MaterialId),
		Color = world:get(bagEntity, components.Color),
		ConveyorId = world:get(bagEntity, components.LinkedToId),
		StartTime = world:get(bagEntity, components.StartedAt),
		FinishTime = world:get(bagEntity, components.FinishesAt),
	})

	bagRemoteEvent:FireAllClients(b)
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
	[REMOTE_CODES.Events.Clicked] = function(player: Player, b: buffer)
		local offset = 0
		local bagId: number
		bagId, offset = BufferUtil.readu16(b, offset)

		for bagEntity, _bagId in world:query(components.Id):with(components.BagTag) do
			if _bagId == bagId then
				warn(`{player.Name} just clicked bag {bagId} | server EntityID: {bagEntity}`)
				break
			end
		end
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

SimpleRemotesUtil.bindRemoteFunctionActions(bagRemoteFunction, {
	[REMOTE_CODES.Functions.Get] = function(player: Player)
		if Limiter.isDebouncing(`GetBags.{player.UserId}`, 10) then
			return
		end

		-- Query for all bags
		local getAllBags = world
			:query(
				components.Id,
				components.MaterialId,
				components.Color,
				components.LinkedToId,
				components.StartedAt,
				components.FinishesAt
			)
			:with(components.BagTag)

		-- Collect all valid bags
		local serverTimeNow = workspace:GetServerTimeNow()

		local bagDataList = {}
		for _, id, materialId, color, conveyorId, startTime, finishTime in getAllBags do
			if serverTimeNow > finishTime then
				continue
			end

			table.insert(bagDataList, {
				id,
				materialId,
				color,
				conveyorId,
				startTime,
				finishTime,
			})
		end

		-- Pre-alloc buffer
		local len = #bagDataList
		local b, offset = buffer.create(BYTE_SIZES.u16 + len * BAG_BYTE_SIZE), 0

		-- Fill buffer
		offset = BufferUtil.writeu16(b, offset, len)
		for i = 1, #bagDataList do
			local v = bagDataList[i]
			offset = encodeBagBuffer(b, offset, {
				Id = v[1],
				MaterialId = v[2],
				Color = v[3],
				ConveyorId = v[4],
				StartTime = v[5],
				FinishTime = v[6],
			})
		end

		return b
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

-- Clean up the world
local nextCleanup = 0
RunService.Heartbeat:Connect(function()
	local timeNow = os.clock()
	if timeNow < nextCleanup then
		return
	end
	nextCleanup = timeNow + math.random(10, 30) / 100

	local serverTimeNow = workspace:GetServerTimeNow()
	local bagsToDelete = {}

	for bagEntity, finishTime in world:query(components.FinishesAt):with(components.BagTag) do
		if serverTimeNow >= finishTime then
			table.insert(bagsToDelete, bagEntity)
		end
	end

	for _, bagEntity in bagsToDelete do
		world:delete(bagEntity)
	end
end)

return BagService
