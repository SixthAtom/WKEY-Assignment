local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local jecs = require(ReplicatedStorage.Shared.Packages.jecs)

-------------------------------------------------------------------------------
-- TYPES
-------------------------------------------------------------------------------

type Id<T = nil> = jecs.Id<T>

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local world = Worlds.Default

-------------------------------------------------------------------------------
-- RETURN
-------------------------------------------------------------------------------

return {
	-- Tags
	ConveyorTag = jecs.tag(),
	BagTag = jecs.tag(),

	-- Globals
	Name = world:component() :: Id<string>,
	Id = world:component() :: Id<number>,
	OwnerId = world:component() :: Id<number>,
	Node = world:component() :: Id<BasePart>,
	Model = world:component() :: Id<Model>,
	Purchases = world:component() :: Id<{ [string]: true }>,
	Speed = world:component() :: Id<number>,
	MaterialId = world:component() :: Id<number>,
	Color = world:component() :: Id<Color3>,
	LinkedToId = world:component() :: Id<number>,
	StartedAt = world:component() :: Id<number>,
	FinishesAt = world:component() :: Id<number>,
	StartPosition = world:component() :: Id<Vector3>,
	FinishPosition = world:component() :: Id<Vector3>,
}
