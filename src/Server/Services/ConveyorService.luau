local ConveyorService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ConveyorConstants = require(ReplicatedStorage.Shared.Constants.ConveyorConstants)
local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
local Components = require(ServerStorage.Server.ECS.Components)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local RemoteCodes = require(ReplicatedStorage.Shared.Networking.RemoteCodes)
local SimpleRemotes = require(ReplicatedStorage.Shared.Networking.SimpleRemotes)
local SimpleRemotesUtil = require(ReplicatedStorage.Shared.Networking.SimpleRemotesUtil)
local BufferUtil = require(ReplicatedStorage.Shared.Util.BufferUtil)
local PlayersUtil = require(ReplicatedStorage.Shared.Util.PlayersUtil)
local Conveyor = require(ServerStorage.Server.ECS.Entities.Conveyor)
local BagService = require(ServerStorage.Server.Services.BagService)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local REMOTE_CODES = RemoteCodes.Conveyor
local INTERVAL_RATES = ConveyorConstants.IntervalRates

local DEFAULT_SPAWN_INTERVAL = 1
local DEFAULT_CONVEYOR_SPEED = 10

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local conveyorRemoteEvent = SimpleRemotes.getEvent("Conveyor")

local spawnInterval = DEFAULT_SPAWN_INTERVAL
local conveyorSpeed = DEFAULT_CONVEYOR_SPEED

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

	for conveyorEntity in world:query(Tags.IsConveyor) do
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

		local conveyorEntity = Conveyor.new(conveyorCounter, conveyorModel, spawnInterval, conveyorSpeed)
		conveyorModel.Name = tostring(conveyorCounter)

		-- Set attributes (for easy client access)
		conveyorModel:SetAttribute("Speed", world:get(conveyorEntity, components.Speed))
	end
end

function ConveyorService.start()
	assignRandomConveyorsOwner()
end

-------------------------------------------------------------------------------
-- LOGIC
-------------------------------------------------------------------------------

do -- Conveyor spawn detection
	local getConveyors = world:query(components.NextSpawnAt, components.Interval, Tags.IsConveyor):cached()

	RunService.Heartbeat:Connect(function()
		local timeNow = os.clock()
		for conveyorEntity, nextSpawnAt, spawnInterval in getConveyors do
			if timeNow < nextSpawnAt then
				continue -- CONTINUE: Not yet refreshing
			end

			world:set(conveyorEntity, components.NextSpawnAt, timeNow + spawnInterval)
			BagService.spawn(conveyorEntity)
		end
	end)
end

-- Listen for remotes
SimpleRemotesUtil.bindRemoteEventActions(conveyorRemoteEvent, {
	[REMOTE_CODES.Events.SetInterval] = function(player: Player, b: buffer)
		if not player:GetAttribute("ConveyorsOwner") then
			return -- RETURN: This player doesn't have permission
		end

		local offset = 0
		local newInterval: number

		newInterval = BufferUtil.readf32(b, offset)

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
