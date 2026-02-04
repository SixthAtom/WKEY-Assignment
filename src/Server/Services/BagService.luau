local BagService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Components = require(ServerStorage.Server.ECS.Components)
local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
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

-- Sequential ID avoids collisions and provides a lightweight way for clients
-- to reference specific entities without passing 64-bit GUIDs
local bagCounter = 0

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

-- Encodes a bag buffer from a table
-- Centralizing this prevents offset mistakes all over the code
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
	-- Modulo wrap-around ensures the ID stays WELL within u16 bounds (0-65535)
	-- preventing buffer overflow on the networking layer
	bagCounter = (bagCounter % 50_000) + 1

	local bagEntity = Bag.new(bagCounter, conveyorEntity)

	-- Combining the remote code and data into one buffer reduces the number
	-- of network calls when spawning
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

do -- Listen for remotes
	-- Caching ECS queries give a very big performance boost (about 5x as fast as non-cached)
	local getAllBagIds = world:query(components.Id, Tags.IsBag):cached()
	local getAllBags = world
		:query(
			components.Id,
			components.MaterialId,
			components.Color,
			components.LinkedToId,
			components.StartedAt,
			components.FinishesAt,
			Tags.IsBag
		)
		:cached()

	SimpleRemotesUtil.bindRemoteEventActions(bagRemoteEvent, {
		[REMOTE_CODES.Events.Clicked] = function(player: Player, b: buffer)
			local offset = 0
			local bagId: number
			bagId, offset = BufferUtil.readu16(b, offset)

			for bagEntity, _bagId in getAllBagIds do
				if _bagId == bagId then
					warn(`{player.Name} just clicked bag {bagId} | server EntityID: {bagEntity}`)
					break
				end
			end
		end,
	}, SimpleRemotesUtil.DecodeActionBuffer)

	SimpleRemotesUtil.bindRemoteFunctionActions(bagRemoteFunction, {
		[REMOTE_CODES.Functions.Get] = function(player: Player)
			-- RETURN: Request is throttled, prevents CPU exhausting from malicious clients
			if Limiter.isDebouncing(`GetBags.{player.UserId}`, 10) then
				return
			end

			local serverTimeNow, bagDataList = workspace:GetServerTimeNow(), {}
			for _, id, materialId, color, conveyorId, startTime, finishTime in getAllBags do
				-- RETURN: Expired bags are excluded to keep network traffic as low as possible
				if serverTimeNow > finishTime then
					continue
				end

				table.insert(bagDataList, 1, {
					id,
					materialId,
					color,
					conveyorId,
					startTime,
					finishTime,
				})
			end

			-- Calculating exact size beforehand avoids the memory cost of
			-- repeatedly resizing or reallocating the buffer during the loop
			local len = #bagDataList
			local b, offset = buffer.create(BYTE_SIZES.u16 + len * BAG_BYTE_SIZE), 0

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
end

do -- Cleanup loop
	local getBagsToDestroy = world:query(Tags.ToDestroy):with(Tags.IsBag):cached()
	local getBagsFinishTime = world:query(components.FinishesAt):with(Tags.IsBag):cached()

	-- A randomized cleanup interval spreads the CPU cost of entity deletion
	-- across multiple frames instead of causing a single massive spike

	local nextCleanup = 0
	RunService.Heartbeat:Connect(function()
		local timeNow = os.clock()
		if timeNow < nextCleanup then
			return
		end
		nextCleanup = timeNow + math.random(10, 30) / 100

		-- Potentially tag entities
		local serverTimeNow = workspace:GetServerTimeNow()
		for bagEntity, finishTime in getBagsFinishTime do
			-- We tag first then delete in a separate pass to ensure we aren't
			-- modifying the query results while iterating over them

			if serverTimeNow >= finishTime then
				world:add(bagEntity, Tags.ToDestroy)
			end
		end

		-- Cleanup entities
		for bagEntity in getBagsToDestroy do
			world:delete(bagEntity)
		end
	end)
end

return BagService
