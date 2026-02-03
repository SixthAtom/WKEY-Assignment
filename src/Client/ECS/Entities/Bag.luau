local Bag = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(ReplicatedStorage.Client.ECS.Components)
local Worlds = require(ReplicatedStorage.Shared.ECS.Worlds)
local ECSUtil = require(ReplicatedStorage.Shared.Util.ECSUtil)
local ModelUtil = require(ReplicatedStorage.Shared.Util.ModelUtil)

-------------------------------------------------------------------------------
-- PRIVATE VARIABLES
-------------------------------------------------------------------------------

local world = Worlds.Default
local components = Components.Default

-------------------------------------------------------------------------------
-- PRIVATE FUNCTIONS
-------------------------------------------------------------------------------

local function getConveyorModel(conveyorId: number)
	return workspace.Conveyors:WaitForChild(`{conveyorId}`)
end

-------------------------------------------------------------------------------
-- PUBLIC FUNCTIONS
-------------------------------------------------------------------------------

function Bag.new(
	id: number,
	material: Enum.Material,
	color: Color3,
	conveyorId: number,
	startTime: number,
	finishTime: number
)
	local bagEntity = world:entity()

	-------------------------------------------------------------------------------
	-- PREPARE
	-------------------------------------------------------------------------------

	-- Prepare model
	local bagModel = workspace.BagTemplate:Clone()
	local boundingSize = ModelUtil.getBoundingSize(bagModel)

	bagModel.Parent = workspace.Terrain
	for _, v in next, bagModel:QueryDescendants("BasePart") :: { BasePart } do
		v.Color, v.Material = color, material
	end

	-- Get conveyor data
	local conveyorModel = getConveyorModel(conveyorId)
	local conveyorRoot = conveyorModel:WaitForChild("Root")
	local conveyorSpeed = conveyorModel:GetAttribute("Speed")

	local yOffset = Vector3.new(0, boundingSize.Y / 2, 0)
	local startPosition: Vector3 = conveyorRoot.StartAttachment.WorldCFrame.Position + yOffset
	local finishPosition: Vector3 = conveyorRoot.FinishAttachment.WorldCFrame.Position + yOffset

	-------------------------------------------------------------------------------
	-- COMPONENTS
	-------------------------------------------------------------------------------

	ECSUtil.bulkSet(world, bagEntity, {
		[components.Id] = id,
		[components.Speed] = conveyorSpeed,
		[components.Model] = bagModel,
		[components.StartedAt] = startTime,
		[components.FinishesAt] = finishTime,
		[components.StartPosition] = startPosition,
		[components.FinishPosition] = finishPosition,
		[components.LinkedToId] = conveyorId,
	})

	world:add(bagEntity, components.BagTag)

	return bagEntity
end

return Bag
