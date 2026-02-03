local BagService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function BagService.spawn(conveyorEntity: jecs.Entity)
	bagCounter = (bagCounter % 50_000) + 1

	local bagEntity = Bag.new(bagCounter, conveyorEntity)

	local b, offset = buffer.create(BYTE_SIZES.u8 + BAG_BYTE_SIZE), 0
	offset = BufferUtil.writeu8(b, offset, REMOTE_CODES.Events.Spawn)
	offset = BufferUtil.writeu16(b, offset, bagCounter)
	offset = BufferUtil.writeu16(b, offset, world:get(bagEntity, components.MaterialId))
	offset = BufferUtil.writeColor_24(b, offset, world:get(bagEntity, components.Color))
	offset = BufferUtil.writeu8(b, offset, world:get(bagEntity, components.LinkedToId))
	offset = BufferUtil.writef64(b, offset, world:get(bagEntity, components.StartedAt))
	offset = BufferUtil.writef64(b, offset, world:get(bagEntity, components.FinishesAt))

	bagRemoteEvent:FireAllClients(b)
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

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

		-- Collect all bags
		local bagDataList = {}
		for _, id, materialId, color, conveyorId, startTime, finishTime in getAllBags do
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
			offset = BufferUtil.writeu16(b, offset, v[1])
			offset = BufferUtil.writeu16(b, offset, v[2])
			offset = BufferUtil.writeColor_24(b, offset, v[3])
			offset = BufferUtil.writeu8(b, offset, v[4])
			offset = BufferUtil.writef64(b, offset, v[5])
			offset = BufferUtil.writef64(b, offset, v[6])
		end

		return b
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

return BagService
