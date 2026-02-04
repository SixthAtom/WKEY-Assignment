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
	Interval = world:component() :: Id<number>,
	NextSpawnAt = world:component() :: Id<number>,
}
