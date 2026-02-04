local Bag = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Components = require(ReplicatedStorage.Client.ECS.Components)
local Tags = require(ReplicatedStorage.Shared.ECS.Tags)
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

-- Returns a conveyor model from it's id
-- Uses WaitForChild so bags don't spawn before the conveyor is ready
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

	-- Wait for the bag to exist to avoid cloning an incomplete template
	workspace.BagTemplate:WaitForChild("MeshPart")

	local bagModel = workspace.BagTemplate:Clone()
	bagModel:SetAttribute("Id", id)

	-- calculate bounding size once so we can position the bag correctly on conveyor
	local boundingSize = ModelUtil.getBoundingSize(bagModel)

	-- Parent to terrain to keep bags separated in the workspace
	bagModel.Parent = workspace.Terrain

	-- Recolor the entire model in one pass
	for _, v in next, bagModel:QueryDescendants("BasePart") :: { BasePart } do
		v.Color, v.Material = color, material
	end

	-- Fetch conveyor data when the model is prepared
	local conveyorModel = getConveyorModel(conveyorId)
	local conveyorRoot = conveyorModel:WaitForChild("Root")
	local conveyorSpeed = conveyorModel:GetAttribute("Speed")

	-- Offset the bag's position by half the height so it rests on the conveyor
	local yOffset = Vector3.new(0, boundingSize.Y / 2, 0)

	-- Start and end positions are taken directly from conveyor attachments
	-- This keeps movement fully dependant on the workspace layout
	local startPosition: Vector3 = conveyorRoot.StartAttachment.WorldCFrame.Position + yOffset
	local finishPosition: Vector3 = conveyorRoot.FinishAttachment.WorldCFrame.Position + yOffset

	-------------------------------------------------------------------------------
	-- COMPONENTS
	-------------------------------------------------------------------------------

	-- BulkSet is used for setting components to an entity quickly
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

	-- Marks the entity as a bag to easily query for bags only
	world:add(bagEntity, Tags.IsBag)

	return bagEntity
end

return Bag
