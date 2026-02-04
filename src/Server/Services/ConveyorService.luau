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

-- Attributes are used for interval replication because they provide
-- automatic synchronization for joining players without extra remote calls
local function updateIntervalAttribute(newInterval: number)
	ReplicatedStorage:SetAttribute("ConveyorInterval", newInterval)
end

-- A single conveyor owner is designated to prevent multiple clients from attempting
-- to drive global conveyor UI/settings simultaneously, this centralizes authority
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
	-- Clamping ensures that network-received values cannot break the intended values
	newInterval = math.clamp(newInterval, INTERVAL_RATES.Min, INTERVAL_RATES.Max)
	spawnInterval = newInterval
	updateIntervalAttribute(newInterval)

	warn(`Set interval to {newInterval}`)

	-- Updating conveyor components allows the spawning system to pick up
	-- changes on the next spawn trigger
	for conveyorEntity in world:query(Tags.IsConveyor) do
		world:set(conveyorEntity, components.Interval, newInterval)
	end
end

-------------------------------------------------------------------------------
-- CORE FUNCTIONS
-------------------------------------------------------------------------------

function ConveyorService.init()
	updateIntervalAttribute(spawnInterval)

	-- Iterating through the workspace folder allows the map design to
	-- determine the number of conveyor entities without hardcoded lists
	for _, conveyorModel: Model in next, workspace.Conveyors:GetChildren() do
		conveyorCounter = (conveyorCounter % 10_000) + 1

		local conveyorEntity = Conveyor.new(conveyorCounter, conveyorModel, spawnInterval, conveyorSpeed)

		-- The model name is the "replicated Id" to allow for easy access when decoding on the client
		conveyorModel.Name = tostring(conveyorCounter)

		-- Stored in attributes so clients can perform visual calculations without querying the server/ECS
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
			-- CONTINUE: Not yet time for a spawn
			if timeNow < nextSpawnAt then
				continue
			end

			world:set(conveyorEntity, components.NextSpawnAt, timeNow + spawnInterval)
			BagService.spawn(conveyorEntity)
		end
	end)
end

-- Binds remote actions in a table, so adding new events later is easy
SimpleRemotesUtil.bindRemoteEventActions(conveyorRemoteEvent, {
	[REMOTE_CODES.Events.SetInterval] = function(player: Player, b: buffer)
		-- RETURN: This player is not the conveyor owner
		if not player:GetAttribute("ConveyorsOwner") then
			return
		end

		local offset = 0
		local newInterval: number

		newInterval = BufferUtil.readf32(b, offset)

		ConveyorService.setInterval(newInterval)
	end,
}, SimpleRemotesUtil.DecodeActionBuffer)

-- Ensuring the ConveyorsOwner role is passed on prevents the system
-- from becoming locked if the current owner leaves the game
PlayersUtil.connectEvents({
	PlayerLeft = function(player)
		if player:GetAttribute("ConveyorsOwner") then
			assignRandomConveyorsOwner()
		end
	end,
})

return ConveyorService
