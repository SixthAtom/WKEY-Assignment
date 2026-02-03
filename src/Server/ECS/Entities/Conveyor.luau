local Conveyor = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

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

function Conveyor.new(id: number, model: Model, spawnInterval: number)
	local conveyorEntity = world:entity()

	-------------------------------------------------------------------------------
	-- COMPONENTS
	-------------------------------------------------------------------------------

	ECSUtil.bulkSet(world, conveyorEntity, {
		[components.Id] = id,
		[components.Model] = model,
		[components.Speed] = 1,
		[components.Interval] = spawnInterval,
		[components.NextSpawnAt] = 0,
	})

	world:add(conveyorEntity, components.ConveyorTag)

	return conveyorEntity
end

return Conveyor
