local ConveyorService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local BufferConstants = require(ReplicatedStorage.Shared.Constants.BufferConstants)
local ConveyorConstants = require(ReplicatedStorage.Shared.Constants.ConveyorConstants)
local Components = require(ServerStorage.Server.ECS.Components)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local SimpleRemotesUtil = require(ReplicatedStorage.Shared.Networking.SimpleRemotesUtil)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)
local PlayersUtil = require(ReplicatedStorage.Shared.Util.PlayersUtil)
local Conveyor = require(ServerStorage.Server.ECS.Entities.Conveyor)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local REMOTE_CODES = RemoteCodes.Conveyor
local INTERVAL_RATES = ConveyorConstants.IntervalRates
local BYTE_SIZES = BufferConstants.Sizes

local DEFAULT_SPAWN_INTERVAL = 1

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local conveyorRemoteEvent = SimpleRemotes.getEvent("Conveyor")

local spawnInterval = DEFAULT_SPAWN_INTERVAL
local conveyorCounter = 0

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function updateIntervalAttribute(newInterval: number)
	ReplicatedStorage:SetAttribute("ConveyorInterval", newInterval)
end

local function assignRandomConveyorsOwner()
	if #Players:GetPlayers() == 0 then
		repeat
			task.wait(1)
		until #Players:GetPlayers() > 0
	end

	local players = Players:GetPlayers()
	local player = players[math.random(#players)]
	player:SetAttribute("ConveyorsOwner", true)
end

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function ConveyorService.setInterval(newInterval: number)
	newInterval = math.clamp(newInterval, INTERVAL_RATES.Min, INTERVAL_RATES.Max)
	spawnInterval = newInterval
	updateIntervalAttribute(newInterval)

	warn(`Set interval to {newInterval}`)

	for conveyorEntity in world:query(components.ConveyorTag) do
		world:set(conveyorEntity, components.Interval, newInterval)
	end
end

-------------------------------------------------------------------------------
-- CORE FUNCTIONS
-------------------------------------------------------------------------------

function ConveyorService.init()
	updateIntervalAttribute(spawnInterval)

	-- Create server conveyor entities
	for _, conveyorModel: Model in next, workspace.Conveyors:GetChildren() do
		conveyorCounter = (conveyorCounter % 10_000) + 1
		Conveyor.new(conveyorCounter, conveyorModel, spawnInterval)
	end
end

function ConveyorService.start()
	assignRandomConveyorsOwner()
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

-- Conveyor spawn detection
RunService.Heartbeat:Connect(function()
	local getConveyors = world:query(components.NextSpawnAt, components.Interval):with(components.ConveyorTag)

	local timeNow = os.clock()
	for conveyorEntity, nextSpawnAt, spawnInterval in getConveyors do
		if timeNow < nextSpawnAt then
			continue
		end
		world:set(conveyorEntity, components.NextSpawnAt, timeNow + spawnInterval)
	end
end)

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(conveyorRemoteEvent, {
	[REMOTE_CODES.Events.SetInterval] = function(player: Player, b: buffer)
		if not player:GetAttribute("ConveyorsOwner") then
			return -- RETURN: This player doesn't have permission
		end

		local offset = 0
		local newInterval: number

		newInterval = BufferUtil.readu16(b, offset)

		ConveyorService.setInterval(newInterval)
	end,
}, function(b: buffer)
	local remoteCode, offset = BufferUtil.readu8(b, 0)
	return remoteCode, BufferUtil.deallocate(b, 0, offset)
end)

-- Connect player events
PlayersUtil.connectEvents({
	PlayerLeft = function(player)
		if player:GetAttribute("ConveyorsOwner") then
			assignRandomConveyorsOwner()
		end
	end,
})

return ConveyorService
