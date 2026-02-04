local Bag = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MaterialConstants = require(ReplicatedStorage.Shared.Constants.MaterialConstants)
local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
local Components = require(ServerStorage.Server.ECS.Components)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local jecs = require(ReplicatedStorage.Shared.Packages.jecs)
local ECSUtil = require(ReplicatedStorage.Shared.Util.ECSUtil)

-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------

local MATERIALS = MaterialConstants.Materials

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function Bag.new(id: number, conveyorEntity: jecs.Entity)
	local bagEntity = world:entity()

	-------------------------------------------------------------------------------
	-- PREPARE
	-------------------------------------------------------------------------------

	local conveyorModel = world:get(conveyorEntity, components.Model)

	-- Length is extracted from the Z-axis of the PrrimaryPart to ensure an accurate duration
	local conveyorLength = conveyorModel.PrimaryPart.Size.Z
	local conveyorSpeed = world:get(conveyorEntity, components.Speed)
	local serverTimeNow = workspace:GetServerTimeNow()

	-- Randomized selection from the constants table
	-- this table provides materials that can be applied to parts
	local materialId = MATERIALS[math.random(#MATERIALS)].Value

	-------------------------------------------------------------------------------
	-- COMPONENTS
	-------------------------------------------------------------------------------

	-- BulkSet is used for setting components to an entity quickly
	ECSUtil.bulkSet(world, bagEntity, {
		[components.Id] = id,
		[components.MaterialId] = materialId,
		[components.Color] = Color3.new(math.random(), math.random(), math.random()),
		[components.LinkedToId] = world:get(conveyorEntity, components.Id),
		[components.StartedAt] = serverTimeNow,
		[components.FinishesAt] = serverTimeNow + conveyorLength / conveyorSpeed,
	})

	-- Marks the entity as a bag to easily query for bags only
	world:add(bagEntity, Tags.IsBag)

	return bagEntity
end

return Bag
