local Conveyor = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
local Components = require(ServerStorage.Server.ECS.Components)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local ECSUtil = require(ReplicatedStorage.Shared.Util.ECSUtil)

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function Conveyor.new(id: number, model: Model, spawnInterval: number, speed: number)
	local conveyorEntity = world:entity()

	-------------------------------------------------------------------------------
	-- COMPONENTS
	-------------------------------------------------------------------------------

	-- BulkSet is used for setting components to an entity quickly
	ECSUtil.bulkSet(world, conveyorEntity, {
		[components.Id] = id,
		[components.Model] = model,
		[components.Speed] = speed,
		[components.Interval] = spawnInterval,
		[components.NextSpawnAt] = 0,
	})

	-- Marks the entity as a conveyor to easily query for bags only
	world:add(conveyorEntity, Tags.IsConveyor)

	return conveyorEntity
end

return Conveyor
