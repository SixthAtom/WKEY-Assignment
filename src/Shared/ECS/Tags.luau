local ReplicatedStorage = game:GetService("ReplicatedStorage")

local jecs = require(ReplicatedStorage.Shared.Packages.jecs)

-------------------------------------------------------------------------------
-- RETURN
-------------------------------------------------------------------------------

return {
	ToDestroy = jecs.tag(),
	IsConveyor = jecs.tag(),
	IsBag = jecs.tag(),
}
